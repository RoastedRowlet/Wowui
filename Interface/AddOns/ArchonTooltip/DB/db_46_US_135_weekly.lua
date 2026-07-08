local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Paladin-Retribution','Rogue-Assassination','Shaman-Elemental','Mage-Frost','DemonHunter-Devourer','Mage-Fire','Druid-Feral','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Hunter-BeastMastery','Priest-Holy','Warlock-Destruction','Unknown-Unknown','Warlock-Demonology','Hunter-Marksmanship','DeathKnight-Unholy','DemonHunter-Havoc','DeathKnight-Blood','Monk-Brewmaster','Druid-Restoration','Monk-Windwalker','Monk-Mistweaver','Rogue-Subtlety','Hunter-Survival','Paladin-Protection','DemonHunter-Vengeance','Rogue-Outlaw','Warlock-Affliction','Druid-Balance','Warrior-Arms','Mage-Arcane','Paladin-Holy','Warrior-Fury','Shaman-Enhancement','Warrior-Protection','Evoker-Devastation','DeathKnight-Frost',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=46,date='2026-07-05',data={Ac='Acallia:BAAALgAECgQJCwAAAA==.Achkmed:BAABLgAECn8bAAIBAAcJfhi8hgBiAQABAAcJfhi8hgBiAQAAAA==.',
Ae='Aelynis:BAABLgAECn8mAAICAAkJOw+VCADFAQACAAkJOw+VCADFAQAAAA==.',
Ak='Akalon:BAABLgAECn83AAIDAAgJ+gnpSwAFAQADAAgJ+gnpSwAFAQAAAA==.',
Al='Alara:BAAALgADCgEJAQABLgAECggJLgAEAGgfAA==.Aldrus:BAAALgADCgYJBgAAAA==.Aleda:BAAALgADCgYJBgAAAA==.Allfrost:BAAALgAECgUJEAAAAA==.',
Am='Amanthelia:BAAALgADCgUJBQAAAA==.Amberina:BAAALgADCgkJGQAAAA==.',
An='Angryrose:BAAALgADCgkJCQAAAA==.Annerose:BAABLgAECn8rAAIFAAkJxQQ5sQDFAAAFAAkJxQQ5sQDFAAAAAA==.Anthir:BAAALgADCgEJAgAAAA==.',
Ao='Aoeina:BAABLgAECn9NAAMEAAkJjR7mAgBcAgAEAAkJjR7mAgBcAgAGAAEJiANcFgAlAAAAAA==.',
Ap='Apollo:BAAALgAFFAEJAgAAAA==.',
Aq='Aquinas:BAAALgAECgQJBAABLgAECgcJGgAHAIogAA==.',
Ar='Arcanelotus:BAAALgAECgIJAgAAAA==.Arcás:BAAALgADCgYJBgAAAA==.Arette:BAAALgADCgQJBAABLgAECggJGQAIAMIDAA==.Ariaves:BAABLgAECn8kAAMIAAkJGRfaGwD+AQAIAAkJGRfaGwD+AQAJAAQJugjVPgC3AAAAAA==.Arilea:BAAALgAECgMJAwAAAA==.Arioriaa:BAABLgAECn8vAAIKAAkJTAyiUABwAQAKAAkJTAyiUABwAQAAAA==.Arlind:BAABLgAECn8XAAILAAkJBxJgUgCsAQALAAkJBxJgUgCsAQAAAA==.',
As='Asenath:BAAALgADCgEJAQAAAA==.Asoeclya:BAAALgADCgIJAgAAAA==.Asslind:BAAALgADCgcJDAAAAA==.Assuutu:BAAALgADCgMJAwAAAA==.Astralaia:BAAALgAECgEJAQAAAA==.',
At='Atanatari:BAAALgAECgMJAQABLgAECgkJHwAMAEYGAA==.Attonix:BAAALgAECgEJAQAAAA==.',
Az='Azarine:BAAALgADCggJCQAAAA==.Azem:BAAALgADCggJEwAAAA==.Azixarid:BAAALgAECgMJAwAAAA==.Azurdrache:BAAALgAECgEJAgAAAA==.',
Ba='Baldur:BAAALgADCgcJDAAAAA==.Bassotan:BAABLgAECn8lAAIBAAkJ1hjxMAA9AgABAAkJ1hjxMAA9AgAAAA==.Battleares:BAAALgAECgYJEAAAAA==.',
Be='Beardalorian:BAAALgAECgUJBgAAAA==.Beasttoken:BAAALgADCgUJBQAAAA==.Beleva:BAABLgAECn83AAINAAgJ0hBkFAALAQANAAgJ0hBkFAALAQAAAA==.',
Bi='Bigboom:BAAALgAECgEJAQABLgAECgQJBwAOAAAAAA==.Bigstan:BAAALgAFFAIJAgAAAA==.Bilbobagging:BAAALgAECgUJCQABLgAFFAYJDQAEAMsXAA==.Bilx:BAAALgAECgYJCwAAAA==.Biromong:BAAALgAECgYJEAAAAA==.',
Bl='Blackendmoon:BAAALgAECgUJCwAAAA==.Blackløtus:BAAALgAECgYJAgAAAA==.Blainchet:BAAALgAECgUJDQAAAA==.Bloodknight:BAAALgADCgEJAQAAAA==.Bloodnight:BAAALgAFFAEJAQAAAA==.Bluebeary:BAAALgAECgUJCAAAAA==.Bluebubbles:BAAALgAECgYJDwAAAA==.Bluelocks:BAACLgAFFH8GAAINAAQJRgHSEgCiAAANAAQJRgHSEgCiAAAuAAQKfzIAAw0ACAnrExACAD8BAA0ACAnrExACAD8BAA8AAQlOAk5eASMAAAAA.Blufoot:BAAALgAECgYJBgAAAA==.Bluéyes:BAAALgAECgUJCQAAAA==.Blvckscvl:BAABLgAECn8hAAMLAAgJvBzsFgCBAgALAAgJvBzsFgCBAgAQAAEJNQR9kQApAAAAAA==.Blynna:BAAALgAECgcJCwAAAA==.',
Bo='Bohemond:BAAALgADCgcJBwAAAA==.Borrne:BAAALgAECgEJAQAAAA==.',
Br='Broadleaf:BAAALgAECgQJCQAAAA==.Brujha:BAAALgAECgYJDAABLgAFFAMJBgAFAAYFAA==.Brámble:BAAALgADCgEJAQAAAA==.',
Bu='Bullcritts:BAAALgAECgEJAwAAAA==.Burnttoast:BAAALgADCgMJAwABLgAECgkJGwABAH4YAA==.',
Ca='Caledra:BAAALgAECgEJAQAAAA==.Calinai:BAAALgAECgIJAgAAAA==.Cambrus:BAAALgADCgkJCQAAAA==.Catastrophi:BAAALgADCgEJAQAAAA==.Catastrophie:BAABLgAECn8xAAIRAAgJABNBZgCaAQARAAgJABNBZgCaAQAAAA==.',
Ce='Celivan:BAAALgAECgUJBQABLgAFFAMJAwAOAAAAAA==.Cellturin:BAAALgAECgkJEQAAAA==.',
Ch='Chelais:BAAALgAECgcJCwABLgABCgMJAwAOAAAAAA==.Chiarakai:BAAALgADCgkJHgAAAA==.Chobits:BAAALgAECgUJBgAAAA==.Choc:BAAALgADCgMJAwAAAA==.',
Cl='Claudeena:BAAALgADCgkJEgAAAA==.',
Co='Corvany:BAAALgAECgEJAQABLgAECgQJBwAOAAAAAA==.Coswell:BAAALgAECgMJAwAAAA==.',
Cr='Crawley:BAAALgAECgEJAQAAAA==.Creeder:BAABLgAECn8jAAIBAAkJuRADdACTAQABAAkJuRADdACTAQAAAA==.Crixus:BAAALgADCgcJBwAAAA==.Crm:BAAALgADCgUJBQAAAA==.',
Cy='Cynise:BAAALgADCgcJDQAAAA==.',
Da='Dagoland:BAAALgAECgMJAwAAAA==.Darthmeep:BAAALgAFFAMJAwAAAA==.',
De='Deaanor:BAABLgAECn8gAAISAAgJrQewOADWAAASAAgJrQewOADWAAAAAA==.Deathcòw:BAACLgAFFH8IAAIRAAMJgh2YawAkAQARAAMJgh2YawAkAQAuAAQKfzwAAxEACQnWI38LABEDABEACQnWI38LABEDABMAAgmaCQg+AFkAAAAA.Deathpanthr:BAAALgAECgEJAQABLgAECgYJCgAOAAAAAA==.Decider:BAAALgAECgQJBAAAAA==.Demonhunter:BAAALgAECgIJAgAAAA==.Demonia:BAAALgADCgYJBgAAAA==.Detective:BAABLgAECn8XAAIUAAkJFQvTOgBdAQAUAAkJFQvTOgBdAQAAAA==.Deween:BAAALgADCgYJBgAAAA==.',
Di='Diamond:BAAALgADCgkJIAAAAA==.Dilligafehno:BAAALgADCgkJIAAAAA==.Dionysuz:BAAALgAECggJDQAAAA==.Discord:BAAALgADCgYJBgAAAA==.',
Do='Doemoe:BAAALgAECgIJAgAAAA==.Dojoro:BAABLgAECn9DAAIUAAkJvxswDAByAgAUAAkJvxswDAByAgAAAA==.Dora:BAAALgAECgEJAQAAAA==.',
Dp='Dpshut:BAAALgAECgUJBQABLgAECgkJGwABAH4YAA==.',
Dr='Draann:BAAALgADCggJBwABLgAECgQJBwAOAAAAAA==.Draegare:BAABLgAECn8qAAIBAAgJqCXlBQBuAwABAAgJqCXlBQBuAwAAAA==.Dragonknyte:BAAALgAECgMJAwABLgAECgkJPAATAEAVAA==.Drakengott:BAAALgADCgUJBQAAAA==.Drdeer:BAABLgAECn8nAAIVAAkJGRQUJAArAgAVAAkJGRQUJAArAgAAAA==.Dread:BAAALgADCgUJBwAAAA==.Drittsz:BAAALgADCgIJBAAAAA==.Drumheller:BAAALgAECgQJBAAAAA==.',
Du='Duskraven:BAAALgAECgUJBQAAAA==.',
Ec='Ecclesiarchy:BAAALgAECgEJAQAAAA==.',
Ed='Edwar:BAAALgADCgYJBgAAAA==.',
Ee='Eekumbokum:BAAALgAECgEJAQAAAA==.Eelecurb:BAABLgAFFH8JAAMWAAMJow6VJwC0AAAWAAMJyg2VJwC0AAAUAAEJ3gvCHAA1AAAAAA==.',
El='Eligorra:BAAALgADCgEJAQAAAA==.',
Ep='Epicfury:BAAALgADCgEJAQAAAA==.',
Er='Eruna:BAAALgAECgEJAQAAAA==.',
Es='Eshmun:BAAALgAECgUJDQAAAA==.',
Et='Eternalx:BAAALgAECgQJBQAAAA==.Ethidris:BAAALgADCgkJEgABLgAECgkJGwABAH4YAA==.',
Ev='Evang:BAABLgAECn8tAAILAAkJtRIFRQDTAQALAAkJtRIFRQDTAQAAAA==.Eve:BAAALgAFFAMJBAABLgAFFAcJCwABAB8aAA==.Everd:BAABLgAECn8+AAIBAAkJOhbSOQAbAgABAAkJOhbSOQAbAgAAAA==.Evren:BAABLgAFFH8GAAIXAAMJPxTuOwC1AAAXAAMJPxTuOwC1AAAAAA==.',
Fa='Faelilia:BAAALgADCgUJBQAAAA==.',
Fe='Felorana:BAAALgADCgYJBgAAAA==.Felzup:BAAALgAECgMJAwAAAA==.Feârless:BAAALgAECgYJBgAAAA==.',
Fi='Fiametta:BAACLgAFFH8GAAINAAIJ/hZTEwCeAAANAAIJ/hZTEwCeAAAuAAQKf1MAAg0ACQldIucAAAkDAA0ACQldIucAAAkDAAAA.Finruil:BAAALgADCgYJCQAAAA==.Fireburst:BAAALgAECgIJAgAAAA==.',
Fl='Flamehyenard:BAAALgADCgEJAQAAAA==.Flameward:BAAALgAECgQJBAAAAA==.Flent:BAABLgAECn8bAAMQAAgJKgvYEwAkAQAQAAgJKgvYEwAkAQALAAEJqQa/QgEuAAAAAA==.Florisá:BAAALgADCgQJBAABLgAECgMJAwAOAAAAAA==.',
Fo='Forkingidiot:BAAALgADCgEJAQAAAA==.',
Fr='Frostydck:BAAALgAECgIJAwAAAA==.',
Fu='Funsize:BAAALgAECgUJCgAAAA==.',
Ga='Gabagoop:BAABLgAECn8VAAIEAAkJmwYNqAAuAQAEAAkJmwYNqAAuAQAAAA==.Galindlianid:BAABLgAECn8jAAIBAAkJAATXxwD+AAABAAkJAATXxwD+AAAAAA==.Gazzlok:BAAALgAECgYJEgAAAA==.',
Ge='Gernik:BAAALgAECgEJAQAAAA==.Geryn:BAAALgADCgMJAwAAAA==.Gesen:BAAALgAECgIJBAAAAA==.',
Gh='Ghuldan:BAAALgAECgEJAQAAAA==.',
Gi='Gigaweenie:BAAALgAFFAIJBAAAAA==.',
Gl='Glavien:BAABLgAECn84AAIBAAkJAg99awCYAQABAAkJAg99awCYAQAAAA==.Global:BAAALgADCgkJCQABLgAECgkJKwAGAJMdAA==.',
Go='Gobtjr:BAAALgADCgMJAwAAAA==.Gondra:BAAALgADCgIJAgABLgAECgQJBwAOAAAAAA==.',
Gr='Grandstorm:BAAALgADCgQJBAAAAA==.Greg:BAAALgADCgYJCAAAAA==.Grienke:BAAALgADCgQJBAABLgAFFAQJBwARAMsNAA==.Grumpolbolt:BAABLgAECn8eAAIYAAgJ9RkuJwC/AQAYAAgJ9RkuJwC/AQAAAA==.',
Ha='Haenin:BAAALgAECgEJAwAAAA==.Haplo:BAAALgAECgUJBgAAAA==.Harnessme:BAAALgADCggJCwABLgAECggJHQANAFQOAA==.Harps:BAAALgADCgYJBgAAAA==.Hatéraid:BAAALgAECgEJAgAAAA==.',
He='Hellmet:BAAALgAECgcJCQAAAQ==.Hey:BAACLgAFFH8NAAIKAAQJxhd7OQD8AAAKAAQJxhd7OQD8AAAuAAQKf1EAAgoACQknIn4GAEkDAAoACQknIn4GAEkDAAAA.',
Hi='Hidatix:BAAALgADCgEJAQAAAA==.Hinamori:BAAALgAECgkJDQAAAA==.',
Ho='Homble:BAAALgADCgQJBAAAAA==.Horadin:BAAALgAECgMJAwAAAA==.Horneswaggle:BAAALgAECgEJAQAAAA==.',
Hu='Huntmeister:BAABLgAECn8qAAILAAgJtyEEDQDWAgALAAgJtyEEDQDWAgAAAA==.Huogmi:BAAALgAECgYJCAAAAA==.',
Ic='Iceehawt:BAABLgAECn8hAAIRAAgJuiJFIwB5AgARAAgJuiJFIwB5AgAAAA==.',
Il='Ilharra:BAABLgAECn8cAAMJAAYJBwVyXACNAAAJAAUJsgJyXACNAAAIAAYJ1Q+kDQByAAAAAA==.Ilililili:BAAALgAECgUJCQAAAA==.Illee:BAAALgAECgcJEgAAAA==.Illuminara:BAAALgADCgYJEQAAAA==.',
Im='Imdrood:BAAALgADCgMJAwABLgAFFAMJDgATAFEgAA==.Imturtle:BAACLgAFFH8OAAMTAAMJUSDGCgDpAAATAAMJUSDGCgDpAAARAAEJLBNgFAE/AAAuAAQKf0YAAxMACQlwI+cCABcDABMACQlwI+cCABcDABEABwn/FNCtABcBAAAA.',
In='Insømniadk:BAABLgAFFH8JAAIRAAMJwiDGjwDsAAARAAMJwiDGjwDsAAABLgAFFAcJHQARAIMhAA==.',
Is='Isshiny:BAABLgAECn8ZAAIBAAgJGxlYTgDcAQABAAgJGxlYTgDcAQAAAA==.Isweat:BAAALgAECgMJAwABLgAECgQJBQAOAAAAAA==.',
Iu='Iupiter:BAABLgAECn8VAAIBAAgJTBUKbQCUAQABAAgJTBUKbQCUAQAAAA==.',
Iv='Ivelos:BAAALgADCgIJAwAAAA==.',
Iy='Iyahlieairia:BAAALgAECgYJBgAAAA==.',
Iz='Izabeth:BAABLgAECn8kAAIEAAkJiw3jZgCvAQAEAAkJiw3jZgCvAQAAAA==.',
Ja='Jacaar:BAAALgADCgUJBQAAAA==.Jackal:BAAALgAECgQJBAABLgAECgkJRAAZAPoZAA==.Jamella:BAABLgAECn8vAAIaAAkJ8hDJFwBhAQAaAAkJ8hDJFwBhAQAAAA==.',
Je='Jessabella:BAAALgADCgQJBAAAAA==.Jesyikaxyz:BAAALgAECgkJCgAAAA==.',
Ji='Jifycornbred:BAAALgAECgMJAwAAAA==.Jigles:BAAALgAECgEJAQAAAA==.',
['Jä']='Jägermeister:BAAALgAECgIJBAABLgAECgUJBQAOAAAAAA==.',
Ka='Kaelynia:BAAALgADCgYJCgAAAA==.Kagosi:BAAALgAECgQJBwAAAA==.Kairn:BAAALgADCgcJBwAAAA==.Kalivath:BAAALgADCgUJCAAAAA==.Kalypso:BAAALgADCgkJCQABLgAECgkJSwAJAJ8dAA==.Kardaa:BAAALgADCgEJAQAAAA==.Kat:BAABLgAECn8gAAIKAAkJzQV4XwAOAQAKAAkJzQV4XwAOAQAAAA==.Kawi:BAAALgADCgEJAQAAAA==.Kaza:BAAALgAECgEJAQAAAA==.Kazakusan:BAAALgAECgUJBgAAAA==.',
Ki='Kialla:BAAALgADCgYJCQABLgAECgkJGwABAH4YAA==.Kiraneem:BAABLgAECn87AAMLAAkJ3R69FACsAgALAAkJ3R69FACsAgAQAAEJ2wGjlwAgAAAAAA==.Kittie:BAABLgAECn9MAAMKAAkJ6Bf5GACDAgAKAAkJ6Bf5GACDAgADAAQJZgx6dgCKAAAAAA==.',
Ko='Kongfupanda:BAAALgAECgYJBgAAAA==.Kotenok:BAAALgAECgYJBgAAAA==.',
Kr='Kreyaa:BAABLgAECn8XAAIEAAgJchBIhQBtAQAEAAgJchBIhQBtAQAAAA==.Krinj:BAABLgAECn8oAAIRAAkJZh0dSADqAQARAAkJZh0dSADqAQAAAA==.Kristov:BAAALgAECgIJAgAAAA==.',
Kt='Ktariani:BAAALgAECgQJBAAAAA==.',
Ky='Kyarla:BAABLgAECn87AAIMAAkJvRdXAQA/AgAMAAkJvRdXAQA/AgAAAA==.Kydo:BAACLgAFFH8HAAIEAAMJfQmTigDEAAAEAAMJfQmTigDEAAAuAAQKfyYAAgQABwm9GBpoAKwBAAQABwm9GBpoAKwBAAAA.Kythera:BAAALgAECgQJBwAAAA==.',
['Kø']='Køe:BAAALgADCgQJBAABLgAECgEJAQAOAAAAAA==.',
La='Lamp:BAAALgAECgQJBQAAAA==.',
Le='Leahim:BAAALgAECgIJAgABLgAECgkJWwAYAKEeAA==.Ledani:BAABLgAECn9JAAMIAAkJJBqgAgCeAQAIAAkJJBqgAgCeAQAMAAEJpQpjeQAgAAAAAA==.Leøna:BAAALgADCgEJAQAAAA==.',
Li='Liberi:BAAALgADCgEJAQAAAA==.Lightwràth:BAAALgADCgMJAwAAAA==.Lincecum:BAAALgAECggJEAABLgAFFAQJBwARAMsNAA==.Lioni:BAAALgADCgkJCQAAAA==.Listen:BAABLgAECn9bAAIYAAkJoR7wCQCFAgAYAAkJoR7wCQCFAgAAAA==.',
Lo='Loachapoka:BAAALgADCgYJDQAAAA==.Lohith:BAAALgAECgQJBAAAAA==.Lonedawg:BAAALgAECgUJCQAAAA==.Lovécoil:BAAALgAECgEJAgAAAA==.Loweform:BAAALgADCgEJAQAAAA==.',
Lu='Lunâ:BAABLgAECn9LAAIJAAkJnx1LAQBWAgAJAAkJnx1LAQBWAgAAAA==.Luwud:BAAALgADCgcJEAAAAA==.',
Ly='Lyrei:BAABLgAECn8kAAQFAAkJGBlLMAAFAgAFAAkJlxZLMAAFAgASAAMJ7BEtQwCpAAAbAAEJZw7DNAAyAAAAAA==.',
['Lë']='Lëw:BAAALgAFFAEJAgAAAA==.',
Ma='Macfrost:BAAALgADCgUJBgABLgAECgEJBQAOAAAAAA==.Machiavelli:BAAALgADCgUJBQAAAA==.Maddox:BAABLgAECn8aAAIcAAkJ4gsfDQA+AQAcAAkJ4gsfDQA+AQAAAA==.Magichandz:BAAALgAECgYJCQAAAA==.Maikakx:BAAALgAECgEJAQAAAA==.Marsyx:BAABLgAECn8gAAIMAAkJBR85CwCzAgAMAAkJBR85CwCzAgAAAA==.Masfonos:BAAALgADCgEJAQAAAA==.Mayael:BAAALgAECggJEgAAAA==.Maíkeru:BAAALgADCgEJAQAAAA==.',
Mc='Mcguffinss:BAACLgAFFH8FAAMdAAMJVRk4HABVAAAPAAIJhRfTkACiAAAdAAEJ8xw4HABVAAAuAAQKfx0AAw8ACQl4JYw4ACkCAA8ABwnEJYw4ACkCAA0AAwm6InEnACYBAAAA.',
Me='Medreaux:BAABLgAECn9aAAIMAAkJSSB+CgC/AgAMAAkJSSB+CgC/AgAAAA==.Metalknyte:BAABLgAECn88AAMTAAkJQBUxEgDrAQATAAkJQBUxEgDrAQARAAEJAADPPwAAAAAAAA==.',
Mi='Miniknyte:BAABLgAECn8yAAMVAAkJVxGiBgD2AAAVAAkJVxGiBgD2AAAeAAMJeRWoEABPAAAAAA==.Minotauren:BAAALgADCgYJBQAAAA==.Misskitty:BAABLgAECn8aAAIHAAcJiiDQCgASAgAHAAcJiiDQCgASAgAAAA==.',
Mo='Modnoc:BAAALgAECgYJDAAAAA==.Mogden:BAAALgAFFAEJAQABLgAECgkJIAAFAIIgAA==.Mohu:BAAALgADCggJDQAAAA==.Mollog:BAAALgAECgMJAwAAAA==.Mommii:BAAALgADCgEJAQABLgAECgEJAQAOAAAAAA==.Moondanas:BAAALgADCgMJAwAAAA==.Moonshine:BAAALgADCgUJCAAAAA==.Moonsz:BAAALgADCgkJSwAAAA==.Morghulis:BAAALgAECgUJBQAAAA==.',
Mu='Mugmug:BAAALgADCgUJBgAAAA==.Mukakin:BAAALgADCgEJAQAAAA==.',
My='Mychelle:BAABLgAECn9EAAMZAAkJ+hlpCgB4AgAZAAkJfxhpCgB4AgAQAAgJ3hXZCwCpAQAAAA==.',
['Mø']='Møgwai:BAAALgAECgEJAQAAAA==.',
Na='Nakryn:BAABLgAECn86AAIEAAkJfAkwewCCAQAEAAkJfAkwewCCAQAAAA==.Naluai:BAAALgADCgEJAQAAAA==.Nandami:BAAALgADCgIJAgAAAA==.Nary:BAAALgAECgkJCgAAAA==.Naryeth:BAAALgAECggJCAAAAA==.Narysham:BAAALgADCgIJAgAAAA==.',
Ne='Neazth:BAAALgADCgEJAQABLgAECgUJDAAOAAAAAA==.Nezaeth:BAAALgAECgUJDAAAAA==.Nezum:BAAALgAECgUJBQABLgAECgUJDAAOAAAAAA==.',
Ni='Nickoli:BAAALgAECgYJCgAAAA==.Nightshade:BAAALgADCgkJEgAAAA==.',
No='Nohnehn:BAAALgAECgEJBQAAAA==.Nojomo:BAAALgAECgMJBAAAAA==.Nojomoto:BAAALgAFFAIJAgAAAA==.Norabel:BAAALgAECgYJDgAAAA==.',
Ny='Nyra:BAABLgAECn8qAAILAAkJ6B7XEgC7AgALAAkJ6B7XEgC7AgAAAA==.',
['Nø']='Nøxxi:BAABLgAECn9IAAMNAAkJ7x6GAQDNAgANAAkJ7x6GAQDNAgAPAAYJ2AtYqgDuAAAAAA==.',
Oc='Ocon:BAAALgADCgUJBQAAAA==.',
Ok='Okbloomer:BAABLgAECn8fAAMeAAkJ2B6rEABZAgAeAAkJ2B6rEABZAgAVAAcJLQ4qXwA0AQABLgAFFAMJBQAEAEAEAA==.',
Ol='Oldben:BAABLgAFFH8NAAIBAAQJQApNVgADAQABAAQJQApNVgADAQAAAA==.',
Or='Orckeferal:BAAALgADCgYJCQABLgAFFAgJJAAfAJAfAA==.Oriel:BAABLgAECn88AAIJAAkJBA6jIQDBAQAJAAkJBA6jIQDBAQAAAA==.Orthein:BAAALgAECgQJBgABLgAFFAMJAwAOAAAAAA==.',
Pa='Paleblueeye:BAAALgAECgEJAgAAAA==.Paragas:BAAALgAECgYJBgAAAA==.Pawarwar:BAAALgADCgMJAwAAAA==.',
Pe='Pedrita:BAAALgADCgQJBAAAAA==.',
Ph='Phindin:BAABLgAECn8/AAMDAAkJcRT5HwDjAQADAAkJcRT5HwDjAQAKAAcJxwWbewDtAAAAAA==.',
Pi='Pixystix:BAAALgAECgYJBwABLgAECgkJRAAZAPoZAA==.',
Pl='Plumpcheeks:BAAALgADCgcJCQAAAA==.',
Po='Poc:BAABLgAECn8pAAIHAAgJ4xEyFAB+AQAHAAgJ4xEyFAB+AQAAAA==.Pokoko:BAAALgADCgUJBgAAAA==.',
Pr='Priblet:BAABLgAECn8YAAMEAAkJBgmuDgAMAQAEAAkJBgmuDgAMAQAgAAEJZQIKGwAcAAAAAA==.Primo:BAAALgAECgYJDAAAAA==.Prinsana:BAABLgAECn8/AAMaAAkJPBVkDQDvAQAaAAkJPBVkDQDvAQABAAQJmxASGgCkAAAAAA==.',
Pu='Puddytat:BAAALgADCgMJAwAAAA==.Purged:BAABLgAECn8gAAIKAAkJOAbzXwA8AQAKAAkJOAbzXwA8AQAAAA==.Purquis:BAAALgAECgEJAQAAAA==.',
Py='Pya:BAAALgAECgEJAQAAAA==.',
Ra='Ragnus:BAAALgADCgEJAQAAAA==.Raidwipe:BAAALgADCgIJAgABLgAFFAMJAwAOAAAAAA==.Ralphie:BAAALgADCgcJAQAAAA==.Rasen:BAAALgAECgIJAgABLgAECgUJBQAOAAAAAA==.Ratheer:BAABLgAFFH8FAAIFAAIJSRXSfACEAAAFAAIJSRXSfACEAAABLgAFFAMJBQAdAFUZAA==.Rawfalafel:BAAALgAECggJEwAAAA==.',
Re='Reaperlord:BAABLgAECn8vAAIhAAkJchx9EACUAgAhAAkJchx9EACUAgAAAA==.',
Rh='Rhoana:BAAALgADCgcJBwAAAA==.',
Rl='Rllybuffnerd:BAAALgAECgIJAgAAAA==.',
Ro='Rodikus:BAACLgAFFH8KAAIMAAQJkRg1EwAvAQAMAAQJkRg1EwAvAQAuAAQKf0IAAwwACQlPInERAFYCAAwACAllInERAFYCAAgACQlhF+oVABwCAAAA.Rootbeer:BAAALgADCgYJBgAAAA==.Rorax:BAABLgAECn8jAAIFAAgJxRkJNwDqAQAFAAgJxRkJNwDqAQAAAA==.Rosanna:BAAALgAECgQJBQAAAA==.',
Rp='Rprunner:BAAALgAECgUJBQABLgAECgcJFgAWAJwPAA==.',
Ru='Rukus:BAAALgADCgQJBAAAAA==.',
['Rä']='Räwry:BAAALgAFFAQJBAABLgAFFAMJCAAJAAoMAA==.',
Sa='Saiaa:BAABLgAECn8gAAICAAkJxQahDgA6AQACAAkJxQahDgA6AQAAAA==.Sakeena:BAAALgAECgUJCQAAAA==.Samará:BAAALgAECgIJBgAAAA==.Sarleigh:BAABLgAECn8ZAAMIAAgJwgP1WwCnAAAIAAcJdQP1WwCnAAAMAAEJVgKOFAAfAAAAAA==.Sattia:BAABLgAECn9TAAIVAAkJ8wo0BgAEAQAVAAkJ8wo0BgAEAQAAAA==.',
Sc='Scampington:BAAALgAECgYJDAAAAA==.',
Se='Sertzert:BAABLgAECn8WAAIHAAYJXhipGwAvAQAHAAYJXhipGwAvAQAAAA==.',
Sh='Sharokk:BAAALgAECggJCgABLgAECggJIwAFAMUZAA==.Sharrow:BAAALgAECgMJAwAAAA==.Shiggy:BAAALgAECgIJAgAAAA==.Shinokami:BAABLgAECn8vAAMUAAkJChJyJwB1AQAUAAkJmRByJwB1AQAWAAEJ1xTXkQA/AAAAAA==.Shoto:BAAALgADCgEJAQAAAA==.',
Si='Silentninjaa:BAACLgAFFH8KAAIiAAMJQwofEwDKAAAiAAMJQwofEwDKAAAuAAQKfzUAAiIACQlQHNMQAHACACIACQlQHNMQAHACAAAA.Simphunter:BAEBLgAECn86AAIFAAkJqh8jEQC5AgAFAAkJqh8jEQC5AgAAAA==.Sinchan:BAAALgADCgEJAQAAAA==.Sindaea:BAAALgADCgYJBgAAAA==.Sinfel:BAABLgAECn9FAAMSAAkJoREkBAAyAQASAAkJoREkBAAyAQAbAAUJxAmuAwCgAAAAAA==.Sit:BAAALgAECggJEgAAAA==.',
Sk='Skall:BAAALgAECgEJAQAAAA==.Skoree:BAABLgAECn8gAAIFAAkJgiC/GQC6AgAFAAkJgiC/GQC6AgAAAA==.',
Sl='Slït:BAAALgADCgIJAgAAAA==.',
Sm='Smellme:BAAALgAECgYJBwAAAA==.Smitedaddy:BAAALgAECgEJAQAAAA==.Smothbran:BAAALgADCgIJAwAAAA==.',
Sn='Snapdragon:BAAALgAECgQJBgAAAA==.',
So='Solarasun:BAAALgADCgkJFQABLgAECgkJHwAMAEYGAA==.Soluna:BAAALgAECgQJBAAAAA==.Someonelse:BAAALgAECgMJAwAAAA==.Sonett:BAAALgAECgQJCAAAAA==.',
Sp='Splunk:BAAALgAECgkJEQABLgAECgkJFwAUABULAA==.Spânky:BAAALgAECgYJEQAAAA==.Spíké:BAAALgADCgkJCQAAAA==.',
Sq='Squiggles:BAABLgAECn81AAIQAAkJJhi5BQBCAgAQAAkJJhi5BQBCAgAAAA==.',
St='Staggerdaddy:BAAALgADCgYJBgAAAA==.Stariya:BAAALgAECgUJBgAAAA==.Stillwing:BAAALgADCgIJAgAAAA==.Stormkraa:BAAALgAECgkJCAAAAA==.Strawyà:BAAALgADCgQJBwABLgAFFAMJCgAaAFAVAA==.Strawyæ:BAACLgAFFH8KAAIaAAMJUBVtBACjAAAaAAMJUBVtBACjAAAuAAQKfzoAAhoACQnQG14IAFICABoACQnQG14IAFICAAAA.Strike:BAAALgAECgYJCAABLgAFFAYJFAAhAHARAA==.',
Su='Succubi:BAAALgADCgIJAgAAAA==.Sugerfree:BAAALgAECgYJDAAAAA==.Sulkra:BAAALgAECgcJAQAAAA==.Suttercane:BAAALgAECgYJCQAAAA==.',
['Sì']='Sìrocco:BAAALgAECgYJDQAAAA==.',
Ta='Taleranor:BAABLgAECn8UAAIHAAgJGBITFwBcAQAHAAgJGBITFwBcAQAAAA==.Tallaeya:BAAALgAECgMJAwAAAA==.Tamerizer:BAABLgAECn8wAAMZAAkJOBWPEwAKAgAZAAkJGhOPEwAKAgAQAAYJ8xAkRABFAQAAAA==.',
Te='Tealera:BAAALgAECgMJAwAAAA==.Teejrath:BAAALgAECgYJCAAAAA==.Teekeez:BAABLgAECn8dAAIEAAkJOgiNwQAHAQAEAAkJOgiNwQAHAQAAAA==.Terup:BAAALgADCgUJBQAAAA==.',
Th='Theodorel:BAAALgAECgMJBQAAAA==.Thicchick:BAAALgAECgYJDAAAAA==.Thillarys:BAAALgAECgEJAQAAAA==.Thirge:BAABLgAECn9EAAIiAAkJhxuQDQCWAgAiAAkJhxuQDQCWAgAAAA==.Thorek:BAAALgAECgQJBAAAAA==.Thrushbeard:BAAALgADCgkJHwAAAA==.Thunderracks:BAAALgAECgEJAQAAAA==.',
To='Tokas:BAAALgAECgIJAgAAAA==.Tolak:BAAALgAECgUJEAAAAA==.Torturousôwl:BAAALgAECgkJEAAAAA==.',
Tr='Traaze:BAAALgAECgYJDAABLgAFFAYJDQAEAMsXAA==.Tralle:BAAALgAECgMJAwAAAA==.Trapology:BAAALgAECgEJBAAAAA==.Trisky:BAABLgAECn8rAAMhAAkJ1BhOHQAYAgAhAAgJjxdOHQAYAgABAAcJNQ5FowAyAQAAAA==.Trissa:BAAALgADCgcJEQAAAA==.Trolldax:BAAALgADCgUJBwABLgAECgMJAwAOAAAAAA==.Trydént:BAAALgAECgQJCAAAAA==.Trystàn:BAAALgADCgUJBQAAAA==.',
Tu='Tunip:BAAALgAECgIJAgAAAA==.Turtle:BAABLgAECn8dAAMPAAYJzhpPWwCMAQAPAAYJzhpPWwCMAQANAAIJmwZsRQAiAAABLgAFFAMJDgATAFEgAA==.',
Ul='Ulric:BAAALgADCgkJEgAAAA==.',
Un='Unhenged:BAAALgADCgQJBAAAAA==.',
Va='Vaceriss:BAAALgADCgYJBgAAAA==.Valatar:BAAALgADCgcJCgAAAA==.Valdrakkquin:BAABLgAECn8sAAIjAAkJCyGRBgBvAgAjAAkJCyGRBgBvAgAAAA==.Valtreya:BAAALgADCgYJBgAAAA==.Vantadim:BAAALgADCgUJBQAAAA==.',
Ve='Vegito:BAABLgAECn84AAIiAAkJQwdbDACjAAAiAAkJQwdbDACjAAAAAA==.Velayna:BAAALgAECgYJBQAAAA==.Veramoon:BAAALgADCgYJBgAAAA==.',
Vi='Victoriia:BAAALgADCggJCAAAAA==.Vincente:BAAALgAECggJEAAAAA==.Vistus:BAAALgAECgcJCwAAAA==.',
Vo='Void:BAAALgADCgQJBAABLgAECgkJRAAZAPoZAA==.Voidmeister:BAABLgAECn8WAAIFAAYJ+RJEmgDsAAAFAAYJ+RJEmgDsAAABLgAECggJKgALALchAA==.Voin:BAACLgAFFH8SAAIkAAUJ9B3JBQA6AQAkAAUJ9B3JBQA6AQAuAAQKf2IAAyQACQnUJGsBAEkDACQACQnUJGsBAEkDACIABAl9G6xUAPkAAAAA.Vorpine:BAACLgAFFH8KAAIJAAMJJxtYDgDzAAAJAAMJJxtYDgDzAAAuAAQKfzMAAwkACQmkDM8iALgBAAkACQmkDM8iALgBAAgABwmQGX4sAHIBAAAA.',
Vs='Vs:BAACLgAFFH8HAAIRAAMJ3RJHJQABAQARAAMJ3RJHJQABAQAuAAQKfxUAAhEACAnYIKhSAPoBABEACAnYIKhSAPoBAAEuAAUUCQlZAAUAsiYA.',
Wa='Warcockeh:BAAALgADCgUJBQAAAA==.Watermelon:BAABLgAECn8cAAMXAAgJZxaIJgDyAQAXAAgJZxaIJgDyAQAWAAEJHgZNtwAhAAAAAA==.',
Wi='Winterberrie:BAAALgADCgYJBAAAAA==.Wirhl:BAABLgAECn8vAAILAAkJ/xGpBADoAQALAAkJ/xGpBADoAQAAAA==.',
Wo='Wolfrik:BAAALgAECgUJAwAAAA==.Worthatry:BAABLgAFFH8VAAIBAAUJyyDeDgA9AQABAAUJyyDeDgA9AQAAAA==.',
Wy='Wyn:BAABLgAECn8jAAIBAAgJRB8NNQAsAgABAAgJRB8NNQAsAgAAAA==.',
Xa='Xalbit:BAABLgAECn86AAIKAAkJWR6MCgAOAwAKAAkJWR6MCgAOAwAAAA==.Xalya:BAAALgAECgQJBAAAAA==.Xanae:BAAALgAECggJDwAAAA==.Xanthrash:BAAALgAECgcJEAABLgAFFAMJAwAOAAAAAA==.Xantia:BAABLgAECn86AAIVAAkJaRYsHwBNAgAVAAkJaRYsHwBNAgAAAA==.Xaraena:BAABLgAECn8fAAILAAkJfRr2KAATAgALAAkJfRr2KAATAgAAAA==.Xaraimarra:BAAALgADCgQJBAAAAA==.Xariz:BAAALgAECgcJEgAAAA==.',
Xe='Xedd:BAAALgAECgQJBwAAAA==.Xenlo:BAAALgAECgcJEAABLgAFFAUJFQAhAOQbAA==.',
Xy='Xyndrome:BAAALgAFFAEJAQAAAA==.Xyndrä:BAAALgADCgYJBgAAAA==.',
Yo='Yowel:BAAALgADCgIJAgAAAA==.',
Yu='Yungun:BAAALgAECgEJAwAAAA==.',
Za='Zaizel:BAAALgADCgUJBQABLgAFFAYJGAAlAH8YAA==.Zathennyx:BAAALgADCgYJBgABLgAECgMJAwAOAAAAAA==.',
Ze='Zeonhalifax:BAAALgAECgMJAwABLgAECgUJBgAOAAAAAA==.Zercus:BAABLgAFFH8MAAIBAAQJXQmyWAD+AAABAAQJXQmyWAD+AAAAAA==.',
Zh='Zhryla:BAAALgADCgUJCQAAAA==.',
Zi='Zipzap:BAAALgAECgQJBAAAAA==.',
Zl='Zleakara:BAAALgADCgQJBAAAAA==.Zleako:BAAALgADCgMJAwAAAA==.',
Zo='Zoel:BAAALgADCgcJCwAAAA==.',
['Ðr']='Ðread:BAABLgAECn8jAAMmAAkJSw9tEQBhAQAmAAkJBA9tEQBhAQARAAYJEQzHxQD2AAAAAA==.',
['ßß']='ßßq:BAAALgAECgEJAQAAAA==.ßßqñüt:BAAALgAECgcJCwAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
