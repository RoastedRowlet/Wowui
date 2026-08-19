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

local lookup = {'Paladin-Retribution','Rogue-Assassination','Shaman-Elemental','Mage-Frost','DemonHunter-Devourer','Mage-Fire','Druid-Feral','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Hunter-BeastMastery','Priest-Holy','Warlock-Destruction','Unknown-Unknown','Paladin-Protection','Warlock-Demonology','Hunter-Marksmanship','DeathKnight-Unholy','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Blood','Monk-Brewmaster','Druid-Restoration','Paladin-Holy','Monk-Windwalker','Monk-Mistweaver','Rogue-Subtlety','Mage-Arcane','Hunter-Survival','DemonHunter-Vengeance','Rogue-Outlaw','Warlock-Affliction','Druid-Balance','Warrior-Fury','Warrior-Arms','Warrior-Protection','Shaman-Enhancement','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=46,date='2026-08-18',data={Ac='Acallia:BAAALgAECgQJCwAAAA==.Achkmed:BAABLgAECn8bAAIBAAcJfhi8hgBiAQABAAcJfhi8hgBiAQAAAA==.Acsit:BAAALgAECgEJAQAAAA==.',
Ae='Aelynis:BAABLgAECn8mAAICAAkJOw+VCADFAQACAAkJOw+VCADFAQAAAA==.',
Ak='Akalon:BAABLgAECn83AAIDAAgJ+gnpSwAFAQADAAgJ+gnpSwAFAQAAAA==.',
Al='Alara:BAAALgADCgEJAQABLgAECggJLgAEAGgfAA==.Aldrus:BAAALgADCgYJBgAAAA==.Aleda:BAAALgADCgYJBgAAAA==.Allfrost:BAAALgAECgYJEQAAAA==.',
Am='Amanthelia:BAAALgADCgUJBQAAAA==.Amberina:BAAALgADCgkJGQAAAA==.',
An='Angryman:BAAALgADCgEJAQAAAA==.Angryrose:BAAALgADCgkJCQAAAA==.Annerose:BAABLgAECn8rAAIFAAkJxQQ5sQDFAAAFAAkJxQQ5sQDFAAAAAA==.Anthir:BAAALgADCgEJAgAAAA==.',
Ao='Aoeina:BAABLgAECn9UAAMEAAkJTx8FBQBxAgAEAAkJTx8FBQBxAgAGAAEJiANcFgAlAAAAAA==.',
Ap='Apollo:BAAALgAFFAEJAgAAAA==.',
Aq='Aquinas:BAAALgAECgQJBAABLgAECgcJGgAHAIogAA==.',
Ar='Arcanelotus:BAAALgAECgIJAgAAAA==.Arctus:BAAALgAECgEJAQAAAA==.Arcás:BAAALgADCgYJBgAAAA==.Arette:BAAALgADCgQJBAABLgAECggJGQAIAMIDAA==.Ariaves:BAABLgAECn8kAAMIAAkJGRfaGwD+AQAIAAkJGRfaGwD+AQAJAAQJugjVPgC3AAAAAA==.Arilea:BAAALgAECgQJCAAAAA==.Arioriaa:BAABLgAECn8vAAIKAAkJTAyiUABwAQAKAAkJTAyiUABwAQAAAA==.Arlind:BAABLgAECn8XAAILAAkJBxJgUgCsAQALAAkJBxJgUgCsAQAAAA==.',
As='Asenath:BAAALgADCgEJAQAAAA==.Asoeclya:BAAALgADCgIJAgAAAA==.Asslind:BAAALgAFFAIJAgAAAA==.Assuutu:BAAALgADCgMJAwAAAA==.Astralaia:BAAALgAECgEJAQAAAA==.',
At='Atanatari:BAAALgAECgQJAgABLgAECgkJHwAMAEYGAA==.Attonix:BAAALgAECgEJAQAAAA==.',
Az='Azarine:BAAALgADCggJCQAAAA==.Azem:BAAALgADCggJEwAAAA==.Azixarid:BAAALgAECgQJCAAAAA==.Azurdrache:BAAALgAECgEJAgAAAA==.',
Ba='Baldur:BAAALgADCgcJDAAAAA==.Bassotan:BAABLgAECn8lAAIBAAkJ1hjxMAA9AgABAAkJ1hjxMAA9AgAAAA==.Baticus:BAAALgAECgUJCQAAAA==.Battleares:BAAALgAECgYJEAAAAA==.',
Be='Beardalorian:BAAALgAECgUJBgAAAA==.Beasttoken:BAAALgADCgUJBQAAAA==.Beleva:BAABLgAECn89AAINAAgJMBEtAwBrAQANAAgJMBEtAwBrAQAAAA==.Belias:BAAALgAECgUJBQAAAA==.Bezzaj:BAAALgAFFAEJAgABLgAFFAkJIwAEALMUAA==.',
Bi='Bigboom:BAAALgAECgEJAQABLgAECgYJBwAOAAAAAA==.Bigstan:BAAALgAFFAIJAgAAAA==.Bilbobagging:BAAALgAECgUJCQABLgAFFAcJDwAEAFsYAA==.Bilx:BAAALgAECgYJCwAAAA==.Biromong:BAAALgAECgYJEAAAAA==.',
Bl='Blackendmoon:BAAALgAECggJEwAAAA==.Blackløtus:BAAALgAECgkJCQAAAA==.Blainchet:BAAALgAECgUJDQAAAA==.Bloodknight:BAAALgADCgEJAQAAAA==.Bloodnight:BAAALgAFFAEJAgAAAA==.Bluebeary:BAAALgAECgYJCQAAAA==.Bluebubbles:BAABLgAECn8cAAMBAAgJKA8aEwBJAQABAAgJKA8aEwBJAQAPAAQJ6QEaEgBZAAAAAA==.Bluehax:BAAALgAECgEJAgAAAA==.Bluelocks:BAACLgAFFH8GAAINAAQJRgHSEgCiAAANAAQJRgHSEgCiAAAuAAQKfzIAAw0ACAnrE8wNAF8BAA0ACAnrE8wNAF8BABAAAQlOAk5eASMAAAAA.Blufoot:BAAALgAECgYJBwAAAA==.Bluéyes:BAAALgAECgUJCQAAAA==.Blvckscvl:BAABLgAECn8hAAMLAAgJvBzsFgCBAgALAAgJvBzsFgCBAgARAAEJNQR9kQApAAAAAA==.Blynna:BAAALgAECgcJCwAAAA==.',
Bo='Bogthorn:BAAALgADCgEJAQAAAA==.Bohemond:BAAALgADCgcJBwAAAA==.Borrne:BAAALgAECgEJAQAAAA==.',
Br='Broadleaf:BAAALgAECgcJDwAAAA==.Brujha:BAAALgAECgYJDAABLgAFFAMJBgAFAAYFAA==.',
Bu='Bullcritts:BAAALgAECgEJAwAAAA==.Burnttoast:BAAALgADCgMJAwABLgAECgkJGwABAH4YAA==.',
Ca='Caledra:BAAALgAECgEJAQAAAA==.Calinai:BAAALgAECgQJBgAAAA==.Cambrus:BAAALgADCgkJCQAAAA==.Catastrophi:BAAALgADCgEJAQAAAA==.Catastrophie:BAABLgAECn8xAAISAAgJABNBZgCaAQASAAgJABNBZgCaAQAAAA==.',
Ce='Celivan:BAAALgAECgUJBQABLgAFFAMJBAAOAAAAAA==.Cellturin:BAAALgAECgkJEQAAAA==.',
Ch='Chelais:BAAALgAECgcJCwABLgABCgMJAwAOAAAAAA==.Chiarakai:BAAALgADCgkJKAAAAA==.Chobits:BAAALgAECgUJBgAAAA==.Choc:BAAALgADCgMJAwAAAA==.',
Cl='Claudeena:BAAALgAECgQJBQAAAA==.',
Co='Corvany:BAAALgAECgYJBwAAAA==.Coswell:BAAALgAECgMJAwAAAA==.',
Cr='Crawley:BAAALgAECgEJAQAAAA==.Creeder:BAABLgAECn8jAAIBAAkJuRADdACTAQABAAkJuRADdACTAQAAAA==.Crixus:BAAALgADCgcJBwAAAA==.Crm:BAAALgADCgUJBQAAAA==.',
Cy='Cynise:BAAALgADCgcJDQAAAA==.',
Da='Daedanan:BAAALgADCgIJAgAAAA==.Dagoland:BAAALgAECgMJAwAAAA==.Darkmane:BAAALgAECgQJBgAAAA==.Darthmeep:BAAALgAFFAMJBAAAAA==.',
De='Deaanor:BAABLgAECn8iAAITAAkJIgiwOADWAAATAAkJIgiwOADWAAAAAA==.Deathcòw:BAACLgAFFH8KAAMSAAMJvB2YawAkAQASAAMJgh2YawAkAQAUAAIJPAx1FACAAAAuAAQKfzwAAxIACQnWI38LABEDABIACQnWI38LABEDABUAAgmaCQg+AFkAAAAA.Deathpanthr:BAAALgAECgEJAQABLgAECgYJCgAOAAAAAA==.Decider:BAAALgAECgQJBAAAAA==.Demonhunter:BAAALgAECgIJAgAAAA==.Demonia:BAAALgADCgYJBgAAAA==.Dertbirtlul:BAAALgAECgEJAQAAAA==.Detective:BAABLgAECn8XAAIWAAkJFQvTOgBdAQAWAAkJFQvTOgBdAQAAAA==.Deween:BAAALgADCgYJBgAAAA==.',
Di='Diamond:BAAALgADCgkJIAAAAA==.Dilligafehno:BAAALgADCgkJIAAAAA==.Dionysuz:BAABLgAECn8kAAIEAAkJBBO8CADsAQAEAAkJBBO8CADsAQAAAA==.Discord:BAAALgADCgYJBgAAAA==.',
Do='Doemoe:BAAALgAECgYJBgAAAA==.Dojoro:BAABLgAECn9LAAIWAAkJhxy5AQAeAgAWAAkJhxy5AQAeAgAAAA==.Dora:BAAALgAECgEJAQAAAA==.',
Dp='Dpshut:BAAALgAECgUJBQABLgAECgkJGwABAH4YAA==.',
Dr='Draann:BAAALgADCggJBwABLgAECgYJBwAOAAAAAA==.Draegare:BAABLgAECn8qAAIBAAgJqCXlBQBuAwABAAgJqCXlBQBuAwAAAA==.Dragonknyte:BAAALgAECgMJAwABLgAECgkJRQAVAIcXAA==.Drakengott:BAAALgAECgcJDAAAAA==.Drdeer:BAABLgAECn8nAAIXAAkJGRQUJAArAgAXAAkJGRQUJAArAgAAAA==.Dread:BAAALgADCgUJBwAAAA==.Drittsz:BAAALgADCgIJBAAAAA==.Drumheller:BAAALgAECgQJBAAAAA==.',
Du='Duskraven:BAAALgAECgUJBQAAAA==.',
Ec='Ecclesiarchy:BAABLgAECn8eAAIYAAcJEA3FCAA9AQAYAAcJEA3FCAA9AQAAAA==.',
Ed='Edwar:BAAALgADCgYJBgAAAA==.',
Ee='Eekumbokum:BAAALgAECgEJAQAAAA==.Eelecurb:BAABLgAFFH8JAAMZAAMJow6VJwC0AAAZAAMJyg2VJwC0AAAWAAEJ3gvdJQAtAAAAAA==.',
El='Eligorra:BAAALgADCgEJAQAAAA==.',
Ep='Epicfury:BAAALgADCgEJAQAAAA==.',
Er='Eruna:BAAALgAECgEJAQAAAA==.',
Es='Eshmun:BAAALgAECgUJDQAAAA==.',
Et='Eternalx:BAAALgAECgYJBwAAAA==.Ethidris:BAAALgADCgkJEgABLgAECgkJGwABAH4YAA==.',
Ev='Evang:BAABLgAECn8tAAILAAkJtRIFRQDTAQALAAkJtRIFRQDTAQAAAA==.Eve:BAAALgAFFAMJBAABLgAFFAcJCwABAB8aAA==.Everd:BAABLgAECn8+AAIBAAkJOhbSOQAbAgABAAkJOhbSOQAbAgAAAA==.Evren:BAABLgAFFH8GAAIaAAMJPxTuOwC1AAAaAAMJPxTuOwC1AAAAAA==.',
Fa='Faelilia:BAAALgADCgUJBQAAAA==.Farrakzul:BAAALgAECgMJAwAAAA==.',
Fe='Felorana:BAAALgADCgYJBgAAAA==.Felzup:BAAALgAECgQJCAAAAA==.Feârless:BAAALgAECgYJBgAAAA==.',
Fi='Fiametta:BAACLgAFFH8JAAINAAMJoRJcBgDEAAANAAMJoRJcBgDEAAAuAAQKf1YAAg0ACQmJIucAAAkDAA0ACQmJIucAAAkDAAAA.Finruil:BAAALgADCgYJCQAAAA==.Fireburst:BAAALgAECgIJAgAAAA==.Firerain:BAAALgAECgQJBQAAAA==.',
Fl='Flamehyenard:BAAALgADCgEJAQAAAA==.Flameward:BAAALgAECgQJBAAAAA==.Flent:BAABLgAECn8bAAMRAAgJKgvYEwAkAQARAAgJKgvYEwAkAQALAAEJqQa/QgEuAAAAAA==.Florisá:BAAALgADCgQJBAABLgAECgMJAwAOAAAAAA==.',
Fo='Forkingidiot:BAAALgADCgEJAQAAAA==.Foxymizzy:BAAALgAFFAMJAwAAAA==.',
Fr='Frostydck:BAAALgAECgIJAwAAAA==.',
Fu='Funsize:BAABLgAECn8UAAMJAAkJYA/oBgCUAQAJAAgJtQ/oBgCUAQAMAAUJPgjYTACvAAAAAA==.',
Ga='Gabagoop:BAABLgAECn8VAAIEAAkJmwYNqAAuAQAEAAkJmwYNqAAuAQAAAA==.Galindlianid:BAABLgAECn8jAAIBAAkJAATXxwD+AAABAAkJAATXxwD+AAAAAA==.Gazzlok:BAABLgAECn8XAAILAAYJyg1gHQD4AAALAAYJyg1gHQD4AAAAAA==.',
Ge='Gernik:BAAALgAECgEJAQAAAA==.Geryn:BAAALgADCgMJAwAAAA==.Gesen:BAAALgAECgIJBAAAAA==.',
Gh='Ghuldan:BAAALgAECgEJAQAAAA==.',
Gi='Gigaweenie:BAAALgAFFAIJBAAAAA==.',
Gl='Glavien:BAABLgAECn9AAAIBAAkJhBJZDwB3AQABAAkJhBJZDwB3AQAAAA==.Global:BAAALgAECgEJAQABLgAECgkJKwAGAJMdAA==.',
Go='Gobtjr:BAAALgADCgMJAwAAAA==.Gondra:BAAALgADCgIJAgABLgAECgYJBwAOAAAAAA==.',
Gr='Grandstorm:BAAALgADCgQJBAAAAA==.Greg:BAAALgADCgYJCAAAAA==.Grienke:BAAALgAECgQJBQABLgAFFAQJCAASAMsNAA==.Grumpolbolt:BAABLgAECn8eAAIbAAgJ9RkuJwC/AQAbAAgJ9RkuJwC/AQAAAA==.',
Ha='Haenin:BAAALgAECgEJAwAAAA==.Haplo:BAAALgAECgYJBwAAAA==.Harnessme:BAAALgADCggJCwABLgAECggJHQANAFQOAA==.Harps:BAAALgADCgYJBgAAAA==.Hatéraid:BAAALgAECgEJAgAAAA==.',
He='Hellmet:BAAALgAECgcJCQAAAQ==.Hey:BAACLgAFFH8RAAIKAAYJAxf+FwANAQAKAAYJAxf+FwANAQAuAAQKf1EAAgoACQknIn4GAEkDAAoACQknIn4GAEkDAAAA.',
Hi='Hidatix:BAAALgADCgEJAQAAAA==.Hinamori:BAAALgAECgkJDQAAAA==.',
Ho='Homble:BAAALgADCgQJBAAAAA==.Horadin:BAAALgAECgQJCAAAAA==.Horneswaggle:BAAALgAECgEJAQAAAA==.',
Hu='Huntmeister:BAABLgAECn8qAAILAAgJtyEEDQDWAgALAAgJtyEEDQDWAgAAAA==.Huogmi:BAAALgAECgYJDQAAAA==.',
Ic='Iceehawt:BAABLgAECn8hAAISAAgJuiJFIwB5AgASAAgJuiJFIwB5AgAAAA==.',
Il='Ilharra:BAABLgAECn8eAAMIAAgJJxKjFACYAAAIAAcJpA+jFACYAAAJAAYJfANyXACNAAAAAA==.Ilililili:BAAALgAECgYJCgAAAA==.Illee:BAABLgAECn8VAAMcAAcJqxTtBQDQAAAcAAcJqxTtBQDQAAAEAAEJFA3dZwEuAAAAAA==.Illuminara:BAAALgADCgYJEQAAAA==.',
Im='Imdrood:BAAALgADCgMJAwABLgAFFAMJDgAVAFEgAA==.Imturtle:BAACLgAFFH8OAAMVAAMJUSDeGgAQAQAVAAMJUSDeGgAQAQASAAEJLBNgFAE/AAAuAAQKf0YAAxUACQlwI+cCABcDABUACQlwI+cCABcDABIABwn/FNCtABcBAAAA.',
In='Insømniadk:BAABLgAFFH8JAAISAAMJwiDGjwDsAAASAAMJwiDGjwDsAAABLgAFFAkJLwASAGgkAA==.',
Is='Isshiny:BAABLgAECn8ZAAIBAAgJGxlYTgDcAQABAAgJGxlYTgDcAQAAAA==.Isweat:BAAALgAECgMJAwABLgAECgQJBQAOAAAAAA==.',
Iu='Iupiter:BAABLgAECn8VAAIBAAgJTBUKbQCUAQABAAgJTBUKbQCUAQAAAA==.',
Iv='Ivelos:BAAALgADCgIJAwAAAA==.',
Ix='Ixsoris:BAAALgADCgIJAgAAAA==.',
Iy='Iyahlieairia:BAAALgAECgYJCwAAAA==.',
Iz='Izabeth:BAABLgAECn8qAAIEAAkJPRIvFAA6AQAEAAkJPRIvFAA6AQAAAA==.',
Ja='Jacaar:BAAALgADCgUJBQAAAA==.Jackal:BAAALgAECgQJBAABLgAECgkJRAAdAPoZAA==.Jalaby:BAAALgAECgQJBQAAAA==.Jamella:BAABLgAECn8vAAIPAAkJ8hDJFwBhAQAPAAkJ8hDJFwBhAQAAAA==.',
Je='Jessabella:BAAALgADCgQJBAAAAA==.Jesyikaxyz:BAAALgAECgkJCgAAAA==.Jesüschrist:BAAALgADCgcJBwAAAA==.',
Ji='Jifycornbred:BAAALgAECgMJAwAAAA==.Jigles:BAAALgAECgEJAQAAAA==.',
['Jä']='Jägermeister:BAAALgAECgIJBAABLgAECgUJBQAOAAAAAA==.',
Ka='Kaelynia:BAAALgADCgYJCgAAAA==.Kagosi:BAAALgAECgQJBwAAAA==.Kairn:BAAALgADCgcJBwAAAA==.Kalivath:BAAALgADCgUJCAAAAA==.Kalypso:BAAALgADCgkJCQABLgAECgkJUwAJACYeAA==.Kardaa:BAAALgADCgEJAQAAAA==.Kat:BAABLgAECn8gAAIKAAkJzQV4XwAOAQAKAAkJzQV4XwAOAQAAAA==.Kawi:BAAALgADCgEJAQAAAA==.Kaza:BAAALgAECgEJAQAAAA==.Kazakusan:BAAALgAECgkJDQAAAA==.',
Ke='Kerronger:BAAALgAECgEJAgAAAA==.',
Ki='Kialla:BAAALgADCgYJCQABLgAECgkJGwABAH4YAA==.Kiraneem:BAABLgAECn9EAAMLAAkJ3R6cBACCAgALAAkJ3R6cBACCAgARAAEJ2wGjlwAgAAAAAA==.Kittie:BAABLgAECn9TAAMKAAkJ6Bf5GACDAgAKAAkJ6Bf5GACDAgADAAQJZgx6dgCKAAAAAA==.',
Ko='Kongfupanda:BAAALgAECgYJBgAAAA==.Kotenok:BAAALgAECgYJBgAAAA==.',
Kr='Kreyaa:BAABLgAECn8XAAIEAAgJchBIhQBtAQAEAAgJchBIhQBtAQAAAA==.Krinj:BAABLgAECn8oAAISAAkJZh0dSADqAQASAAkJZh0dSADqAQAAAA==.Kristov:BAAALgAECgIJAgAAAA==.',
Kt='Ktariani:BAAALgAECgQJBwAAAA==.',
Ky='Kyarla:BAABLgAECn9BAAIMAAkJvRfNAgA4AgAMAAkJvRfNAgA4AgAAAA==.Kydo:BAACLgAFFH8HAAIEAAMJfQmTigDEAAAEAAMJfQmTigDEAAAuAAQKfyYAAgQABwm9GBpoAKwBAAQABwm9GBpoAKwBAAAA.Kythera:BAAALgAECgQJBwAAAA==.',
['Kø']='Køe:BAAALgADCgQJBAABLgAECgEJAQAOAAAAAA==.',
La='Lamp:BAAALgAECgQJBQAAAA==.',
Le='Leahim:BAAALgAECgIJAgABLgAECgkJWwAbAKEeAA==.Ledani:BAABLgAECn9WAAMIAAkJiRrnAgAfAgAIAAkJiRrnAgAfAgAMAAYJYxgrBgCBAQAAAA==.Leøna:BAAALgADCgEJAQAAAA==.',
Li='Liberi:BAAALgADCgEJAQAAAA==.Light:BAAALgAFFAkJAQAAAA==.Lightwràth:BAAALgADCgMJAwAAAA==.Lilleath:BAAALgAECgcJBwAAAA==.Lincecum:BAAALgAECggJEAABLgAFFAQJCAASAMsNAA==.Lioni:BAAALgADCgkJCQAAAA==.Listen:BAABLgAECn9bAAIbAAkJoR7wCQCFAgAbAAkJoR7wCQCFAgAAAA==.',
Lo='Loachapoka:BAAALgADCgYJDQAAAA==.Lohith:BAAALgAECgQJBAAAAA==.Lonedawg:BAAALgAECgYJCgAAAA==.Lovécoil:BAAALgAECgEJAwAAAA==.Loweform:BAAALgADCgEJAQAAAA==.',
Lu='Lunâ:BAABLgAECn9TAAIJAAkJJh5zAQDlAgAJAAkJJh5zAQDlAgAAAA==.Luwud:BAAALgADCgcJEAAAAA==.',
Ly='Lyrei:BAABLgAECn8kAAQFAAkJGBlLMAAFAgAFAAkJlxZLMAAFAgATAAMJ7BEtQwCpAAAeAAEJZw7DNAAyAAAAAA==.',
['Lë']='Lëw:BAAALgAFFAIJBAAAAA==.',
Ma='Macfrost:BAAALgADCgUJBgABLgAECgEJBQAOAAAAAA==.Machiavelli:BAAALgAECgcJBgAAAA==.Maddox:BAABLgAECn8aAAIfAAkJ4gsfDQA+AQAfAAkJ4gsfDQA+AQAAAA==.Magichandz:BAAALgAECgYJCQAAAA==.Maikakx:BAAALgAECgEJAQAAAA==.Marsyx:BAABLgAECn8gAAIMAAkJBR85CwCzAgAMAAkJBR85CwCzAgAAAA==.Masfonos:BAAALgADCgEJAQAAAA==.Mayael:BAABLgAECn8UAAISAAkJzxcLQgD8AQASAAkJzxcLQgD8AQAAAA==.Maíkeru:BAAALgADCgEJAQAAAA==.',
Mc='Mcguffinss:BAACLgAFFH8FAAMgAAMJVRk4HABVAAAQAAIJhRfTkACiAAAgAAEJ8xw4HABVAAAuAAQKfx0AAxAACQl4JYw4ACkCABAABwnEJYw4ACkCAA0AAwm6InEnACYBAAAA.',
Me='Medreaux:BAABLgAECn9bAAIMAAkJSSB+CgC/AgAMAAkJSSB+CgC/AgAAAA==.Metalknyte:BAABLgAECn9FAAMVAAkJhxd7AwDpAQAVAAkJhxd7AwDpAQASAAEJAAC0ZQAAAAAAAA==.',
Mi='Midnight:BAAALgAECggJCAAAAA==.Miniknyte:BAABLgAECn87AAMXAAkJFxdjAwAnAgAXAAkJFxdjAwAnAgAhAAMJKBhgFQCJAAAAAA==.Minotauren:BAAALgADCgYJBQAAAA==.Misskitty:BAABLgAECn8aAAIHAAcJiiDQCgASAgAHAAcJiiDQCgASAgAAAA==.',
Mo='Modnoc:BAAALgAECgYJDAAAAA==.Mogden:BAAALgAFFAEJAQABLgAECgkJIAAFAIIgAA==.Mohu:BAAALgADCggJDQAAAA==.Mollog:BAAALgAECgMJAwAAAA==.Mommii:BAAALgADCgEJAQABLgAECgEJAQAOAAAAAA==.Moondanas:BAAALgADCgMJAwAAAA==.Moonshine:BAAALgADCgUJCAAAAA==.Moonsz:BAAALgADCgkJSwAAAA==.Morghulis:BAAALgAECgUJBQAAAA==.',
Mu='Mugmug:BAAALgADCgUJBgAAAA==.Mukakin:BAAALgADCgEJAQAAAA==.',
My='Mychelle:BAABLgAECn9EAAMdAAkJ+hlpCgB4AgAdAAkJfxhpCgB4AgARAAgJ3hXZCwCpAQAAAA==.',
['Mø']='Møgwai:BAAALgAECgEJAQAAAA==.',
Na='Nakryn:BAABLgAECn86AAIEAAkJfAkwewCCAQAEAAkJfAkwewCCAQAAAA==.Naluai:BAAALgADCgEJAQAAAA==.Nandami:BAAALgADCgIJAgAAAA==.Nary:BAAALgAECgkJCgAAAA==.Naryeth:BAAALgAECggJCAAAAA==.Narysham:BAAALgADCgIJAgAAAA==.',
Ne='Neazth:BAAALgADCgEJAQABLgAECgUJDAAOAAAAAA==.Nezaeth:BAAALgAECgUJDAAAAA==.Nezum:BAAALgAECgUJBQABLgAECgUJDAAOAAAAAA==.',
Ni='Nickoli:BAAALgAECgYJCgAAAA==.Nightfuryy:BAAALgAECgQJBAABLgAFFAMJCgAiAEMKAA==.Nightshade:BAAALgADCgkJEgAAAA==.',
No='Nohnehn:BAAALgAECgEJBQAAAA==.Nojomo:BAAALgAECgMJBAAAAA==.Nojomoto:BAAALgAFFAIJBAAAAA==.Norabel:BAAALgAECgYJDgAAAA==.',
Ny='Nyra:BAABLgAECn8qAAILAAkJ6B7XEgC7AgALAAkJ6B7XEgC7AgAAAA==.',
['Nø']='Nøxxi:BAABLgAECn9RAAMNAAkJYx+GAQDNAgANAAkJYx+GAQDNAgAQAAYJ2AtYqgDuAAAAAA==.',
Oc='Ocon:BAAALgADCgUJBQABLgAECgkJCAAOAAAAAA==.',
Ok='Okbloomer:BAACLgAFFH8FAAIhAAMJfRD/GQCwAAAhAAMJfRD/GQCwAAAuAAQKfx8AAyEACQnYHqsQAFkCACEACQnYHqsQAFkCABcABwktDipfADQBAAEuAAUUCQkvAAgAtBMA.',
Ol='Oldben:BAABLgAFFH8RAAIBAAQJQwyJOAC1AAABAAQJQwyJOAC1AAAAAA==.',
On='Onyx:BAAALgAECgUJBQAAAA==.',
Or='Orckeferal:BAAALgADCgYJCQABLgAFFAkJMgAjADAkAA==.Oriel:BAABLgAECn9FAAIJAAkJ8RB2BADyAQAJAAkJ8RB2BADyAQAAAA==.Orthein:BAAALgAECgQJBgABLgAFFAMJBAAOAAAAAA==.',
Pa='Paleblueeye:BAAALgAECggJCgAAAA==.Pamphlet:BAAALgAECgYJCgAAAA==.Paragas:BAAALgAECgYJBgAAAA==.Pawarwar:BAAALgADCgMJAwAAAA==.',
Pe='Pedrita:BAAALgADCgQJBAAAAA==.',
Ph='Phindin:BAABLgAECn8/AAMDAAkJcRT5HwDjAQADAAkJcRT5HwDjAQAKAAcJxwWbewDtAAAAAA==.',
Pi='Pixystix:BAAALgAECgYJBwABLgAECgkJRAAdAPoZAA==.',
Pl='Plumpcheeks:BAAALgADCgcJDwAAAA==.',
Po='Poc:BAABLgAECn8sAAIHAAgJCRMyFAB+AQAHAAgJCRMyFAB+AQAAAA==.Pokoko:BAAALgADCgUJBgAAAA==.Poppett:BAAALgAECgEJAQAAAA==.',
Pr='Priblet:BAABLgAECn8iAAMEAAkJAgxrEgBLAQAEAAkJAgxrEgBLAQAcAAEJZQIKGwAcAAAAAA==.Primo:BAAALgAECgYJDAAAAA==.Prinsana:BAABLgAECn9JAAMPAAkJbBczAgACAgAPAAkJbBczAgACAgABAAQJmxBhLgCeAAAAAA==.',
Pu='Puddytat:BAAALgADCgMJAwAAAA==.Purged:BAABLgAECn8gAAIKAAkJOAbzXwA8AQAKAAkJOAbzXwA8AQAAAA==.Purquis:BAAALgAECgEJAQAAAA==.',
Py='Pya:BAAALgAECgEJAQAAAA==.',
Ra='Ragnus:BAAALgADCgEJAQAAAA==.Raidwipe:BAAALgADCgIJAgABLgAFFAMJBAAOAAAAAA==.Ralden:BAAALgAECgEJAQABLgAECgkJNgAMAE4XAA==.Ralphie:BAAALgADCgcJAQAAAA==.Rasen:BAAALgAECgIJAgABLgAECgUJBQAOAAAAAA==.Ratheer:BAABLgAFFH8FAAIFAAIJSRXSfACEAAAFAAIJSRXSfACEAAABLgAFFAMJBQAgAFUZAA==.Rawfalafel:BAAALgAECggJEwAAAA==.',
Re='Reaperlord:BAABLgAECn8wAAMYAAkJchx9EACUAgAYAAkJchx9EACUAgABAAEJAxidVwBEAAAAAA==.',
Rh='Rhoana:BAAALgADCgcJBwAAAA==.',
Ro='Rodikus:BAACLgAFFH8KAAIMAAQJkRg1EwAvAQAMAAQJkRg1EwAvAQAuAAQKf0IAAwwACQlPInERAFYCAAwACAllInERAFYCAAgACQlhF+oVABwCAAAA.Rootbeer:BAAALgADCgYJBgAAAA==.Rorax:BAABLgAECn8jAAIFAAgJxRkJNwDqAQAFAAgJxRkJNwDqAQAAAA==.Rosanna:BAAALgAECgQJBQAAAA==.',
Rp='Rprunner:BAAALgAECgUJBQABLgAECgcJFgAZAJwPAA==.',
Ru='Rukus:BAAALgADCgQJBAAAAA==.',
['Rä']='Räwry:BAAALgAFFAQJBAABLgAFFAMJCAAJAAoMAA==.',
Sa='Saiaa:BAABLgAECn8iAAICAAkJEweHAwDZAAACAAkJEweHAwDZAAAAAA==.Sakeena:BAAALgAECgYJCgAAAA==.Samará:BAAALgAECgIJBgAAAA==.Sarleigh:BAABLgAECn8ZAAMIAAgJwgP1WwCnAAAIAAcJdQP1WwCnAAAMAAEJVgJrIwAXAAAAAA==.Sattia:BAABLgAECn9TAAIXAAkJ8wrICgAKAQAXAAkJ8wrICgAKAQAAAA==.',
Sc='Scampington:BAAALgAECggJEAAAAA==.',
Se='Sertzert:BAABLgAECn8WAAIHAAYJXhipGwAvAQAHAAYJXhipGwAvAQAAAA==.',
Sh='Sharokk:BAAALgAECggJCgABLgAECggJIwAFAMUZAA==.Sharrow:BAAALgAECgQJBAAAAA==.Shiggy:BAAALgAECgIJAgAAAA==.Shinokami:BAABLgAECn8vAAMWAAkJChJyJwB1AQAWAAkJmRByJwB1AQAZAAEJ1xTXkQA/AAAAAA==.Shoto:BAAALgADCgEJAQAAAA==.',
Si='Silentninjaa:BAACLgAFFH8KAAIiAAMJQwoyHgC7AAAiAAMJQwoyHgC7AAAuAAQKfzUAAiIACQlQHNMQAHACACIACQlQHNMQAHACAAAA.Simphunter:BAEBLgAECn9HAAIFAAkJrCEAAgCsAgAFAAkJrCEAAgCsAgAAAA==.Sinchan:BAAALgADCgEJAQABLgAECgkJCAAOAAAAAA==.Sindaea:BAAALgADCgYJBgAAAA==.Sinfel:BAABLgAECn9SAAMTAAkJOxRiBAC9AQATAAkJOxRiBAC9AQAeAAUJEA1ZBgCtAAAAAA==.Sit:BAAALgAECggJEgAAAA==.',
Sk='Skall:BAAALgAECgEJAQAAAA==.Skoree:BAABLgAECn8gAAIFAAkJgiC/GQC6AgAFAAkJgiC/GQC6AgAAAA==.',
Sl='Slït:BAAALgADCgIJAgAAAA==.',
Sm='Smellme:BAAALgAECgYJBwAAAA==.Smitedaddy:BAAALgAECgEJAQAAAA==.Smothbran:BAAALgADCgIJAwAAAA==.',
Sn='Snapdragon:BAAALgAECgUJCwAAAA==.',
So='Solarasun:BAAALgADCgkJGAABLgAECgkJHwAMAEYGAA==.Soluna:BAAALgAECgQJBAAAAA==.Someonelse:BAAALgAECgMJAwAAAA==.Sonett:BAAALgAECgUJCQAAAA==.',
Sp='Splunk:BAAALgAECgkJEQABLgAECgkJFwAWABULAA==.Spânky:BAAALgAECgYJEQAAAA==.Spíké:BAAALgADCgkJCQAAAA==.',
Sq='Squiggles:BAABLgAECn81AAIRAAkJJhi5BQBCAgARAAkJJhi5BQBCAgAAAA==.',
St='Staggerdaddy:BAAALgADCgYJBgAAAA==.Stariya:BAAALgAECgYJBwAAAA==.Stillwing:BAAALgADCgIJAgAAAA==.Stormkraa:BAAALgAECgkJCAAAAA==.Strawyà:BAAALgADCgQJBwABLgAFFAMJCgAPAFAVAA==.Strawyæ:BAACLgAFFH8KAAIPAAMJUBUICQCMAAAPAAMJUBUICQCMAAAuAAQKfzoAAg8ACQnQG14IAFICAA8ACQnQG14IAFICAAAA.Strike:BAAALgAECgYJCAABLgAFFAYJGgAYAHARAA==.',
Su='Succubi:BAAALgADCgIJAgAAAA==.Sugerfree:BAAALgAECgYJDAAAAA==.Sulkra:BAAALgAECgcJAQABLgAECgkJCAAOAAAAAA==.Suttercane:BAAALgAECgYJCQAAAA==.',
Sy='Syssa:BAAALgAECgYJBwABLgAECggJHQAMAFIbAA==.',
['Sì']='Sìrocco:BAAALgAECgYJDQAAAA==.',
Ta='Taleranor:BAABLgAECn8VAAIHAAgJahMTFwBcAQAHAAgJahMTFwBcAQAAAA==.Talilia:BAAALgAECgMJAwAAAA==.Tallaeya:BAAALgAECgMJAwAAAA==.Tamerizer:BAABLgAECn8wAAMdAAkJOBWPEwAKAgAdAAkJGhOPEwAKAgARAAYJ8xAkRABFAQAAAA==.',
Te='Tealera:BAAALgAECgMJAwAAAA==.Teejrath:BAAALgAECggJEAAAAA==.Teejzool:BAAALgAECggJCQAAAA==.Teekeez:BAABLgAECn8dAAIEAAkJOgiNwQAHAQAEAAkJOgiNwQAHAQAAAA==.Terup:BAAALgADCgUJBQAAAA==.',
Th='Theious:BAAALgAECgUJCAAAAA==.Theodorel:BAAALgAECgMJBQAAAA==.Thicchick:BAABLgAECn8ZAAIDAAgJBBtXAwAiAgADAAgJBBtXAwAiAgAAAA==.Thillarys:BAAALgAECgEJAQAAAA==.Thirge:BAABLgAECn9EAAIiAAkJhxuQDQCWAgAiAAkJhxuQDQCWAgAAAA==.Thorek:BAAALgAECggJEQAAAA==.Thrushbeard:BAAALgADCgkJHwAAAA==.Thunderracks:BAAALgAECgEJAQAAAA==.',
To='Tokas:BAAALgAECgIJAgAAAA==.Tolak:BAABLgAECn8dAAMkAAgJvCP2AADNAgAkAAgJvCP2AADNAgAjAAEJAAAokAAAAAAAAA==.Torturousôwl:BAAALgAECgkJEAAAAA==.',
Tr='Traaze:BAAALgAECgYJDAABLgAFFAcJDwAEAFsYAA==.Tralle:BAAALgAECgMJAwAAAA==.Trapology:BAAALgAECgEJBAAAAA==.Travelgnome:BAAALgADCgkJCQAAAA==.Trisky:BAABLgAECn8rAAMYAAkJ1BhOHQAYAgAYAAgJjxdOHQAYAgABAAcJNQ5FowAyAQAAAA==.Trissa:BAAALgADCgcJEQAAAA==.Trolldax:BAAALgADCgUJBwABLgAECgMJAwAOAAAAAA==.Trydént:BAAALgAECgQJCAAAAA==.Trystàn:BAAALgADCgUJBQAAAA==.',
Tu='Tunip:BAAALgAECgIJAgAAAA==.Turtle:BAABLgAECn8dAAMQAAYJzhpPWwCMAQAQAAYJzhpPWwCMAQANAAIJmwZsRQAiAAABLgAFFAMJDgAVAFEgAA==.',
Ul='Ulric:BAAALgADCgkJEgAAAA==.',
Un='Unhenged:BAAALgADCgQJBAAAAA==.',
Va='Vaceriss:BAAALgADCgYJBgAAAA==.Valatar:BAAALgAECgQJBQAAAA==.Valdrakkquin:BAABLgAECn8sAAIlAAkJCyGRBgBvAgAlAAkJCyGRBgBvAgAAAA==.Valtreya:BAAALgADCgYJBgAAAA==.Vantadim:BAAALgADCgUJBQAAAA==.',
Ve='Vegito:BAABLgAECn84AAIiAAkJQwcvTwALAQAiAAkJQwcvTwALAQAAAA==.Velayna:BAAALgAECgcJCAAAAA==.Veramoon:BAAALgADCgYJBgAAAA==.',
Vi='Victoriia:BAAALgADCggJCAAAAA==.Vincente:BAAALgAECggJEAAAAA==.Vistus:BAAALgAECgcJCwAAAA==.Vivvian:BAAALgAECgEJAQAAAA==.',
Vo='Void:BAAALgADCgQJBAABLgAECgkJRAAdAPoZAA==.Voidmeister:BAABLgAECn8WAAIFAAYJ+RJEmgDsAAAFAAYJ+RJEmgDsAAABLgAECggJKgALALchAA==.Voin:BAACLgAFFH8YAAIkAAYJmxnmBwBcAQAkAAYJmxnmBwBcAQAuAAQKf2IAAyQACQnUJGsBAEkDACQACQnUJGsBAEkDACIABAl9G6xUAPkAAAAA.Vorpine:BAACLgAFFH8KAAIJAAMJJxtcFQDlAAAJAAMJJxtcFQDlAAAuAAQKfzMAAwkACQmkDM8iALgBAAkACQmkDM8iALgBAAgABwmQGX4sAHIBAAAA.',
Vs='Vs:BAACLgAFFH8HAAISAAMJ3RJHJQABAQASAAMJ3RJHJQABAQAuAAQKfxUAAhIACAnYIKhSAPoBABIACAnYIKhSAPoBAAEuAAUUCQl2AAUA3yYA.',
Wa='Warcockeh:BAAALgADCgUJBQAAAA==.Watermelon:BAABLgAECn8cAAMaAAgJZxaIJgDyAQAaAAgJZxaIJgDyAQAZAAEJHgZNtwAhAAAAAA==.',
Wi='Winterberrie:BAAALgADCgYJBAAAAA==.Wirhl:BAABLgAECn8vAAILAAkJ/xHBCgDMAQALAAkJ/xHBCgDMAQAAAA==.',
Wo='Wolfrik:BAAALgAECgUJAwAAAA==.Worthatry:BAABLgAFFH8XAAIBAAYJsxwsEwBjAQABAAYJsxwsEwBjAQAAAA==.',
Wy='Wyn:BAABLgAECn8jAAIBAAgJRB8NNQAsAgABAAgJRB8NNQAsAgAAAA==.',
Xa='Xalbit:BAABLgAECn88AAIKAAkJWR6MCgAOAwAKAAkJWR6MCgAOAwAAAA==.Xalya:BAAALgAECgQJBAAAAA==.Xanae:BAAALgAECggJDwAAAA==.Xanthrash:BAAALgAECgcJEAABLgAFFAMJBAAOAAAAAA==.Xantia:BAABLgAECn86AAIXAAkJaRYsHwBNAgAXAAkJaRYsHwBNAgAAAA==.Xaraena:BAABLgAECn8fAAILAAkJfRr2KAATAgALAAkJfRr2KAATAgAAAA==.Xaraimarra:BAAALgADCgQJBAAAAA==.Xariz:BAAALgAECgcJEgAAAA==.',
Xe='Xedd:BAAALgAECgQJBwAAAA==.Xenlo:BAAALgAECgcJEAABLgAFFAUJFQAYAOQbAA==.',
Xy='Xyndrome:BAAALgAFFAEJAQAAAA==.Xyndrä:BAAALgADCgYJBgAAAA==.',
Yo='Yogurt:BAAALgAECgQJBQABLgAECgcJCQAOAAAAAA==.Yowel:BAAALgADCgIJAgAAAA==.',
Yu='Yungun:BAAALgAECgEJBAAAAA==.',
Za='Zaizel:BAAALgADCgUJBQABLgAFFAYJGAAmAH8YAA==.Zathennyx:BAAALgADCgYJBgABLgAECgMJAwAOAAAAAA==.',
Zb='Zbbqnut:BAAALgADCgEJAQAAAA==.',
Ze='Zeonhalifax:BAAALgAECgMJAwABLgAECgYJBwAOAAAAAA==.Zercus:BAABLgAFFH8MAAIBAAQJXQmyWAD+AAABAAQJXQmyWAD+AAAAAA==.',
Zh='Zhryla:BAAALgADCgUJCQAAAA==.',
Zi='Zipzap:BAAALgAECgQJBAAAAA==.',
Zl='Zleakara:BAAALgADCgQJBAAAAA==.Zleako:BAAALgADCgMJAwAAAA==.',
Zo='Zoel:BAAALgADCgcJCwABLgAECgkJNgAMAE4XAA==.',
['Ðr']='Ðread:BAABLgAECn8jAAMUAAkJSw9tEQBhAQAUAAkJBA9tEQBhAQASAAYJEQzHxQD2AAAAAA==.',
['ßß']='ßßq:BAAALgAECgEJAQAAAA==.ßßqñüt:BAABLgAECn8VAAIIAAgJ5hCkBgB2AQAIAAgJ5hCkBgB2AQAAAA==.',
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
