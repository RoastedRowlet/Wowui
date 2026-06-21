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

local lookup = {'Paladin-Retribution','Rogue-Assassination','Shaman-Elemental','Mage-Frost','DemonHunter-Devourer','Mage-Fire','Druid-Feral','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Hunter-BeastMastery','Warlock-Destruction','Unknown-Unknown','Warlock-Demonology','Hunter-Marksmanship','DeathKnight-Unholy','DemonHunter-Havoc','DeathKnight-Blood','Monk-Brewmaster','Druid-Restoration','Monk-Windwalker','Monk-Mistweaver','DeathKnight-Frost','Rogue-Subtlety','Paladin-Protection','Priest-Holy','DemonHunter-Vengeance','Rogue-Outlaw','Warlock-Affliction','Druid-Balance','Hunter-Survival','Warrior-Arms','Paladin-Holy','Warrior-Fury','Shaman-Enhancement','Warrior-Protection','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=46,date='2026-06-20',data={Ac='Acallia:BAAALgAECgQJCwAAAA==.Achkmed:BAABLgAECn8bAAIBAAcJfhi9hgBiAQABAAcJfhi9hgBiAQAAAA==.',
Ae='Aelynis:BAABLgAECn8mAAICAAkJOw+VCADFAQACAAkJOw+VCADFAQAAAA==.',
Ak='Akalon:BAABLgAECn83AAIDAAgJ+gnnSwAFAQADAAgJ+gnnSwAFAQAAAA==.',
Al='Alara:BAAALgADCgEJAQABLgAECggJLgAEAGgfAA==.Aldrus:BAAALgADCgYJBgAAAA==.Allfrost:BAAALgAECgQJDwAAAA==.',
Am='Amanthelia:BAAALgADCgUJBQAAAA==.Amberina:BAAALgADCgkJEgAAAA==.',
An='Annerose:BAABLgAECn8qAAIFAAgJgwQ3sQDFAAAFAAgJgwQ3sQDFAAAAAA==.Anthir:BAAALgADCgEJAgAAAA==.',
Ao='Aoeina:BAABLgAECn9FAAMEAAkJFR37HgCkAgAEAAkJFR37HgCkAgAGAAEJiANbFgAlAAAAAA==.',
Ap='Apollo:BAAALgAFFAEJAgAAAA==.',
Aq='Aquinas:BAAALgAECgQJBAABLgAECgcJGgAHAIogAA==.',
Ar='Arcanelotus:BAAALgAECgIJAgAAAA==.Arcás:BAAALgADCgYJBgAAAA==.Arette:BAAALgADCgQJBAABLgAECgcJGAAIAHUDAA==.Ariaves:BAABLgAECn8kAAMIAAkJGRfaGwD+AQAIAAkJGRfaGwD+AQAJAAQJugjVPgC3AAAAAA==.Arilea:BAAALgAECgMJAwAAAA==.Arioriaa:BAABLgAECn8uAAIKAAgJ8gydUABwAQAKAAgJ8gydUABwAQAAAA==.Arlind:BAABLgAECn8XAAILAAkJARJgUgCsAQALAAkJARJgUgCsAQAAAA==.',
As='Asenath:BAAALgADCgEJAQAAAA==.Asoeclya:BAAALgADCgIJAgAAAA==.Asslind:BAAALgADCgUJBQAAAA==.Assuutu:BAAALgADCgMJAwAAAA==.',
At='Atanatari:BAAALgAECgEJAQABLgAECgYJFAAIAIAFAA==.Attonix:BAAALgAECgEJAQAAAA==.',
Az='Azarine:BAAALgADCggJCQAAAA==.Azem:BAAALgADCggJEwAAAA==.Azixarid:BAAALgAECgMJAwAAAA==.Azurdrache:BAAALgAECgEJAgAAAA==.',
Ba='Baldur:BAAALgADCgcJDAAAAA==.Bassotan:BAABLgAECn8lAAIBAAkJ1hjzMAA9AgABAAkJ1hjzMAA9AgAAAA==.Battleares:BAAALgAECgYJEAAAAA==.',
Be='Beardalorian:BAAALgAECgUJBgAAAA==.Beasttoken:BAAALgADCgUJBQAAAA==.Beleva:BAABLgAECn8zAAIMAAcJWA1jFAALAQAMAAcJWA1jFAALAQAAAA==.',
Bi='Bigboom:BAAALgAECgEJAQABLgAECgQJBwANAAAAAA==.Bigstan:BAAALgAECgcJDwAAAA==.Bilbobagging:BAAALgAECgMJBAABLgAFFAYJCwAEAGoVAA==.Bilx:BAAALgAECgYJCwAAAA==.Biromong:BAAALgAECgYJDwAAAA==.',
Bl='Blackendmoon:BAAALgAECgUJCwAAAA==.Blackløtus:BAAALgAECgYJAgAAAA==.Blainchet:BAAALgADCgIJAgAAAA==.Bloodknight:BAAALgADCgEJAQAAAA==.Bloodnight:BAAALgAECgIJBQAAAA==.Bluebeary:BAAALgAECgQJBwAAAA==.Bluebubbles:BAAALgAECgQJBAAAAA==.Bluelocks:BAACLgAFFH8GAAIMAAQJRgHZEgCiAAAMAAQJRgHZEgCiAAAuAAQKfywAAwwACAmNEMwNAF8BAAwACAmNEMwNAF8BAA4AAQlOAk1eASMAAAAA.Blufoot:BAAALgAECgUJBQAAAA==.Bluéyes:BAAALgAECgUJCQAAAA==.Blvckscvl:BAABLgAECn8hAAMLAAgJvBzsFgCBAgALAAgJvBzsFgCBAgAPAAEJNQR9kQApAAAAAA==.Blynna:BAAALgAECgYJCQAAAA==.',
Bo='Bohemond:BAAALgADCgcJBwAAAA==.Borrne:BAAALgAECgEJAQAAAA==.',
Br='Broadleaf:BAAALgAECgQJCQAAAA==.Brujha:BAAALgAECgYJDAABLgAFFAMJBQAFABkEAA==.',
Bu='Bullcritts:BAAALgAECgEJAgAAAA==.Burnttoast:BAAALgADCgMJAwABLgAECgkJGwABAH4YAA==.',
Ca='Caledra:BAAALgAECgEJAQAAAA==.Calinai:BAAALgAECgIJAgAAAA==.Cambrus:BAAALgADCgkJCQAAAA==.Catastrophi:BAAALgADCgEJAQAAAA==.Catastrophie:BAABLgAECn8xAAIQAAgJABM/ZgCaAQAQAAgJABM/ZgCaAQAAAA==.',
Ce='Cellturin:BAAALgAECgkJEQAAAA==.',
Ch='Chelais:BAAALgAECgcJCwABLgABCgMJAwANAAAAAA==.Chiarakai:BAAALgADCgkJHgAAAA==.Chobits:BAAALgAECgUJBgAAAA==.Choc:BAAALgADCgMJAwAAAA==.',
Cl='Claudeena:BAAALgADCgkJEgAAAA==.',
Co='Corvany:BAAALgAECgEJAQABLgAECgQJBwANAAAAAA==.Coswell:BAAALgAECgMJAwAAAA==.',
Cr='Creeder:BAABLgAECn8jAAIBAAkJuRADdACTAQABAAkJuRADdACTAQAAAA==.Crixus:BAAALgADCgcJBwAAAA==.Crm:BAAALgADCgUJBQAAAA==.',
Cy='Cynise:BAAALgADCgcJDQAAAA==.',
Da='Dagoland:BAAALgAECgMJAwAAAA==.Darthmeep:BAAALgAECgMJBwABLgAECgcJEAANAAAAAA==.',
De='Deaanor:BAABLgAECn8fAAIRAAgJnQetOADWAAARAAgJnQetOADWAAAAAA==.Deathcòw:BAACLgAFFH8IAAIQAAMJgh2dawAkAQAQAAMJgh2dawAkAQAuAAQKfzwAAxAACQnWI38LABEDABAACQnWI38LABEDABIAAgmaCQg+AFkAAAAA.Deathpanthr:BAAALgAECgEJAQABLgAECgYJBgANAAAAAA==.Decider:BAAALgAECgEJAQAAAA==.Demonhunter:BAAALgAECgIJAgAAAA==.Demonia:BAAALgADCgYJBgAAAA==.Detective:BAABLgAECn8XAAITAAkJFQvTOgBdAQATAAkJFQvTOgBdAQAAAA==.Deween:BAAALgADCgYJBgAAAA==.',
Di='Diamond:BAAALgADCgkJIAAAAA==.Dilligafehno:BAAALgADCgkJGQAAAA==.Dionysuz:BAAALgADCgcJBwAAAA==.Discord:BAAALgADCgYJBgAAAA==.',
Do='Dojoro:BAABLgAECn84AAITAAkJ/xovDAByAgATAAkJ/xovDAByAgAAAA==.Dora:BAAALgAECgEJAQAAAA==.',
Dp='Dpshut:BAAALgAECgUJBQABLgAECgkJGwABAH4YAA==.',
Dr='Draann:BAAALgADCggJBwABLgAECgQJBwANAAAAAA==.Draegare:BAABLgAECn8qAAIBAAgJqCXlBQBuAwABAAgJqCXlBQBuAwAAAA==.Dragonknyte:BAAALgADCgYJBgABLgAECgkJOQASAEAVAA==.Drdeer:BAABLgAECn8nAAIUAAkJGRQWJAArAgAUAAkJGRQWJAArAgAAAA==.Dread:BAAALgADCgUJBwAAAA==.Drittsz:BAAALgADCgIJBAAAAA==.Drumheller:BAAALgAECgQJBAAAAA==.',
Du='Duskraven:BAAALgAECgUJBQAAAA==.',
Ec='Ecclesiarchy:BAAALgADCgkJGgAAAA==.',
Ed='Edwar:BAAALgADCgYJBgAAAA==.',
Ee='Eekumbokum:BAAALgAECgEJAQAAAA==.Eelecurb:BAABLgAFFH8JAAMVAAMJow6VJwC0AAAVAAMJyg2VJwC0AAATAAEJ3gtgBwA+AAAAAA==.',
El='Eligorra:BAAALgADCgEJAQAAAA==.',
Ep='Epicfury:BAAALgADCgEJAQAAAA==.',
Er='Eruna:BAAALgAECgEJAQAAAA==.',
Es='Eshmun:BAAALgAECgUJDQAAAA==.',
Et='Eternalx:BAAALgAECgQJBQAAAA==.Ethidris:BAAALgADCgkJEgABLgAECgkJGwABAH4YAA==.',
Ev='Evang:BAABLgAECn8sAAILAAgJdBQFRQDTAQALAAgJdBQFRQDTAQAAAA==.Eve:BAAALgAFFAMJBAABLgAFFAYJCgABAFwaAA==.Everd:BAABLgAECn8+AAIBAAkJOhbVOQAbAgABAAkJOhbVOQAbAgAAAA==.Evren:BAABLgAFFH8GAAIWAAMJPxTsOwC1AAAWAAMJPxTsOwC1AAAAAA==.',
Fa='Faelilia:BAAALgADCgUJBQAAAA==.',
Fe='Felorana:BAAALgADCgYJBgAAAA==.Felzup:BAAALgAECgMJAwAAAA==.Feârless:BAAALgAECgYJBgAAAA==.',
Fi='Fiametta:BAABLgAECn9KAAIMAAkJXSLnAAAJAwAMAAkJXSLnAAAJAwAAAA==.Finruil:BAAALgADCgYJCQAAAA==.Fireburst:BAAALgAECgIJAgAAAA==.',
Fl='Flameward:BAAALgAECgQJBAAAAA==.Flent:BAABLgAECn8bAAMPAAgJKgvYEwAkAQAPAAgJKgvYEwAkAQALAAEJqQa8QgEuAAAAAA==.Florisá:BAAALgADCgQJBAABLgAECgMJAwANAAAAAA==.',
Fo='Forkingidiot:BAAALgADCgEJAQAAAA==.',
Fr='Frostydck:BAAALgAECgEJAgAAAA==.',
Fu='Funsize:BAAALgAECgUJCgAAAA==.',
Ga='Gabagoop:BAABLgAECn8VAAIEAAkJlQYKqAAuAQAEAAkJlQYKqAAuAQAAAA==.Galindlianid:BAABLgAECn8jAAIBAAkJAATUxwD+AAABAAkJAATUxwD+AAAAAA==.Gazzlok:BAAALgAECgQJBwAAAA==.',
Ge='Gernik:BAAALgAECgEJAQAAAA==.Geryn:BAAALgADCgMJAwAAAA==.Gesen:BAAALgAECgIJBAAAAA==.',
Gh='Ghuldan:BAAALgAECgEJAQAAAA==.',
Gi='Gigaweenie:BAAALgAFFAIJBAAAAA==.',
Gl='Glavien:BAABLgAECn83AAIBAAkJxA6BawCYAQABAAkJxA6BawCYAQAAAA==.Global:BAAALgADCgkJCQABLgAECggJKgAGAE4dAA==.',
Go='Gobtjr:BAAALgADCgMJAwAAAA==.Gondra:BAAALgADCgIJAgABLgAECgQJBwANAAAAAA==.',
Gr='Grandstorm:BAAALgADCgQJBAAAAA==.Greg:BAAALgADCgYJCAAAAA==.Grienke:BAAALgADCgQJBAABLgAECgkJMgAXADMgAA==.Grumpolbolt:BAABLgAECn8eAAIYAAgJ9RkuJwC/AQAYAAgJ9RkuJwC/AQAAAA==.',
Ha='Haenin:BAAALgAECgEJAwAAAA==.Haplo:BAAALgAECgQJBQAAAA==.Harnessme:BAAALgADCggJCwABLgAECggJHQAMAFQOAA==.Harps:BAAALgADCgYJBgAAAA==.',
He='Hellmet:BAAALgAECgcJCQAAAA==.Hey:BAACLgAFFH8KAAIKAAMJaB50OQD8AAAKAAMJaB50OQD8AAAuAAQKf1EAAgoACQknIoAGAEkDAAoACQknIoAGAEkDAAAA.',
Hi='Hidatix:BAAALgADCgEJAQAAAA==.Hinamori:BAAALgAECggJDAAAAA==.',
Ho='Homble:BAAALgADCgQJBAAAAA==.Horadin:BAAALgAECgMJAwAAAA==.Horneswaggle:BAAALgAECgEJAQAAAA==.',
Hu='Huntmeister:BAABLgAECn8qAAILAAgJtyEEDQDWAgALAAgJtyEEDQDWAgAAAA==.Huogmi:BAAALgAECgYJCAAAAA==.',
Ic='Iceehawt:BAABLgAECn8hAAIQAAgJuiJFIwB5AgAQAAgJuiJFIwB5AgAAAA==.',
Il='Ilharra:BAABLgAECn8aAAMIAAUJ5Q2bUwDEAAAIAAUJ5Q2bUwDEAAAJAAUJsgJxXACNAAAAAA==.Ilililili:BAAALgAECgQJCAAAAA==.Illee:BAAALgAECgcJEgAAAA==.Illuminara:BAAALgADCgYJEQAAAA==.',
Im='Imdrood:BAAALgADCgMJAwABLgAFFAMJCAASAFEgAA==.Imturtle:BAACLgAFFH8IAAMSAAMJUSDjGgAQAQASAAMJUSDjGgAQAQAQAAEJLBNkFAE/AAAuAAQKf0YAAxIACQlwI+oCABcDABIACQlwI+oCABcDABAABwn/FMmtABcBAAAA.',
In='Insømniadk:BAABLgAFFH8JAAIQAAMJwiDKjwDrAAAQAAMJwiDKjwDrAAABLgAFFAYJHAAQAOkgAA==.',
Is='Isshiny:BAABLgAECn8ZAAIBAAgJGxlaTgDcAQABAAgJGxlaTgDcAQAAAA==.Isweat:BAAALgAECgMJAwABLgAECgQJBQANAAAAAA==.',
Iu='Iupiter:BAABLgAECn8VAAIBAAgJTBUObQCUAQABAAgJTBUObQCUAQAAAA==.',
Iv='Ivelos:BAAALgADCgIJAwAAAA==.',
Iy='Iyahlieairia:BAAALgAECgUJBQAAAA==.',
Iz='Izabeth:BAABLgAECn8kAAIEAAkJiw3iZgCvAQAEAAkJiw3iZgCvAQAAAA==.',
Ja='Jacaar:BAAALgADCgUJBQAAAA==.Jamella:BAABLgAECn8uAAIZAAgJhA/JFwBhAQAZAAgJhA/JFwBhAQAAAA==.',
Je='Jessabella:BAAALgADCgQJBAAAAA==.Jesyikaxyz:BAAALgAECgkJCgAAAA==.',
Ji='Jifycornbred:BAAALgAECgMJAwAAAA==.Jigles:BAAALgAECgEJAQAAAA==.',
['Jä']='Jägermeister:BAAALgAECgIJBAABLgAECgUJBQANAAAAAA==.',
Ka='Kaelynia:BAAALgADCgYJCgAAAA==.Kagosi:BAAALgAECgQJBwAAAA==.Kairn:BAAALgADCgcJBwAAAA==.Kalivath:BAAALgADCgUJCAAAAA==.Kalypso:BAAALgADCgkJCQABLgAECgkJQAAJAA0aAA==.Kardaa:BAAALgADCgEJAQAAAA==.Kat:BAABLgAECn8gAAIKAAkJzQV4XwAOAQAKAAkJzQV4XwAOAQAAAA==.Kawi:BAAALgADCgEJAQAAAA==.Kazakusan:BAAALgAECgUJBgAAAA==.',
Ki='Kialla:BAAALgADCgYJCQABLgAECgkJGwABAH4YAA==.Kiraneem:BAABLgAECn85AAMLAAkJ3R6+FACsAgALAAkJ3R6+FACsAgAPAAEJ2wGjlwAgAAAAAA==.Kittie:BAABLgAECn9MAAMKAAkJ6Bf4GACDAgAKAAkJ6Bf4GACDAgADAAQJZgx3dgCKAAAAAA==.',
Ko='Kongfupanda:BAAALgAECgYJBgAAAA==.Kotenok:BAAALgAECgYJBgAAAA==.',
Kr='Kreyaa:BAABLgAECn8XAAIEAAgJchBHhQBtAQAEAAgJchBHhQBtAQAAAA==.Krinj:BAABLgAECn8oAAIQAAkJZh0ZSADqAQAQAAkJZh0ZSADqAQAAAA==.Kristov:BAAALgAECgIJAgAAAA==.',
Kt='Ktariani:BAAALgAECgQJBAAAAA==.',
Ky='Kyarla:BAABLgAECn8rAAIaAAYJ4haOLABmAQAaAAYJ4haOLABmAQAAAA==.Kydo:BAACLgAFFH8HAAIEAAMJfQmwigDEAAAEAAMJfQmwigDEAAAuAAQKfyYAAgQABwm9GBloAKwBAAQABwm9GBloAKwBAAAA.Kythera:BAAALgAECgQJBwAAAA==.',
['Kø']='Køe:BAAALgADCgQJBAABLgAECgEJAQANAAAAAA==.',
La='Lamp:BAAALgAECgQJBQAAAA==.',
Le='Ledani:BAABLgAECn8+AAMIAAkJMxfkEgA7AgAIAAkJMxfkEgA7AgAaAAEJpQpceQAgAAAAAA==.Leøna:BAAALgADCgEJAQAAAA==.',
Li='Liberi:BAAALgADCgEJAQAAAA==.Lightwràth:BAAALgADCgMJAwAAAA==.Lincecum:BAAALgAECggJEAABLgAECgkJMgAXADMgAA==.Lioni:BAAALgADCgkJCQAAAA==.Listen:BAABLgAECn9bAAIYAAkJoR7tCQCFAgAYAAkJoR7tCQCFAgAAAA==.',
Lo='Loachapoka:BAAALgADCgYJDQAAAA==.Lohith:BAAALgAECgQJBAAAAA==.Lonedawg:BAAALgAECgQJCAAAAA==.Lovécoil:BAAALgAECgEJAgAAAA==.Loweform:BAAALgADCgEJAQAAAA==.',
Lu='Lunâ:BAABLgAECn9AAAIJAAkJDRrwCwCwAgAJAAkJDRrwCwCwAgAAAA==.Luwud:BAAALgADCgcJEAAAAA==.',
Ly='Lyrei:BAABLgAECn8kAAQFAAkJGBlOMAAFAgAFAAkJlxZOMAAFAgARAAMJ7BEsQwCpAAAbAAEJZw7ANAAyAAAAAA==.',
['Lë']='Lëw:BAAALgAFFAEJAgAAAA==.',
Ma='Macfrost:BAAALgADCgUJBgABLgAECgEJBQANAAAAAA==.Machiavelli:BAAALgADCgUJBQAAAA==.Maddox:BAABLgAECn8aAAIcAAkJWgsgDQA+AQAcAAkJWgsgDQA+AQAAAA==.Magichandz:BAAALgAECgYJCQAAAA==.Maikakx:BAAALgAECgEJAQAAAA==.Marsyx:BAABLgAECn8gAAIaAAkJBR84CwCzAgAaAAkJBR84CwCzAgAAAA==.Masfonos:BAAALgADCgEJAQAAAA==.Mayael:BAAALgAECggJEgAAAA==.Maíkeru:BAAALgADCgEJAQAAAA==.',
Mc='Mcguffinss:BAACLgAFFH8FAAMdAAMJVRk3HABVAAAOAAIJhRfnkACiAAAdAAEJ8xw3HABVAAAuAAQKfx0AAw4ACQl4JYw4ACkCAA4ABwnEJYw4ACkCAAwAAwm6InEnACYBAAAA.',
Me='Medreaux:BAABLgAECn9TAAIaAAkJuhx+CgC/AgAaAAkJuhx+CgC/AgAAAA==.Metalknyte:BAABLgAECn85AAISAAkJQBUwEgDrAQASAAkJQBUwEgDrAQAAAA==.',
Mi='Miniknyte:BAABLgAECn8sAAMUAAkJuQ2jAgClAAAUAAkJuQ2jAgClAAAeAAEJvQ+miwA1AAAAAA==.Minotauren:BAAALgADCgYJBQAAAA==.Misskitty:BAABLgAECn8aAAIHAAcJiiDOCgASAgAHAAcJiiDOCgASAgAAAA==.',
Mo='Modnoc:BAAALgAECgYJDAAAAA==.Mogden:BAAALgAFFAEJAQABLgAECgkJIAAFAIIgAA==.Mohu:BAAALgADCggJDQAAAA==.Mollog:BAAALgAECgMJAwAAAA==.Mommii:BAAALgADCgEJAQABLgAECgEJAQANAAAAAA==.Moondanas:BAAALgADCgMJAwAAAA==.Moonshine:BAAALgADCgUJCAAAAA==.Moonsz:BAAALgADCgkJSwAAAA==.Morghulis:BAAALgAECgUJBQAAAA==.',
Mu='Mugmug:BAAALgADCgUJBgAAAA==.Mukakin:BAAALgADCgEJAQAAAA==.',
My='Mychelle:BAABLgAECn9DAAMfAAkJ+hlqCgB4AgAfAAkJXBhqCgB4AgAPAAgJ3hXYCwCpAQAAAA==.',
['Mø']='Møgwai:BAAALgAECgEJAQAAAA==.',
Na='Nakryn:BAABLgAECn86AAIEAAkJfwkxewCCAQAEAAkJfwkxewCCAQAAAA==.Naluai:BAAALgADCgEJAQAAAA==.Nandami:BAAALgADCgIJAgAAAA==.Nary:BAAALgAECgkJCgAAAA==.Naryeth:BAAALgAECggJCAAAAA==.Narysham:BAAALgADCgIJAgAAAA==.',
Ne='Neazth:BAAALgADCgEJAQABLgAECgUJDAANAAAAAA==.Nezaeth:BAAALgAECgUJDAAAAA==.Nezum:BAAALgAECgUJBQABLgAECgUJDAANAAAAAA==.',
Ni='Nickoli:BAAALgAECgYJBwAAAA==.Nightshade:BAAALgADCgkJEgAAAA==.',
No='Nohnehn:BAAALgAECgEJBQAAAA==.Nojomo:BAAALgAECgMJBAAAAA==.Nojomoto:BAAALgAECgIJBAAAAA==.Norabel:BAAALgAECgYJDgAAAA==.',
Ny='Nyra:BAABLgAECn8qAAILAAkJ6B7aEgC7AgALAAkJ6B7aEgC7AgAAAA==.',
['Nø']='Nøxxi:BAABLgAECn9GAAMMAAkJ7x6GAQDNAgAMAAkJ7x6GAQDNAgAOAAYJ2AtZqgDuAAAAAA==.',
Oc='Ocon:BAAALgADCgUJBQAAAA==.',
Ok='Okbloomer:BAABLgAECn8fAAMeAAkJ2B6qEABZAgAeAAkJ2B6qEABZAgAUAAcJLQ4qXwA0AQABLgAFFAMJBQAEAEAEAA==.',
Ol='Oldben:BAABLgAFFH8NAAIBAAQJQAptCACxAAABAAQJQAptCACxAAAAAA==.',
Op='Optometrist:BAAALgADCgcJBwAAAA==.',
Or='Orckeferal:BAAALgADCgYJCQABLgAFFAgJJAAgAJAfAA==.Oriel:BAABLgAECn85AAIJAAkJBA7RAQDeAAAJAAkJBA7RAQDeAAAAAA==.Orthein:BAAALgAECgQJBgABLgAECgcJEAANAAAAAA==.',
Pa='Paleblueeye:BAAALgAECgEJAgAAAA==.Paragas:BAAALgAECgYJBgAAAA==.Pawarwar:BAAALgADCgMJAwAAAA==.',
Pe='Pedrita:BAAALgADCgQJBAAAAA==.',
Ph='Phindin:BAABLgAECn8/AAMDAAkJcRT6HwDjAQADAAkJcRT6HwDjAQAKAAcJxwWTewDtAAAAAA==.',
Pi='Pixystix:BAAALgADCgkJCQABLgAECgkJQwAfAPoZAA==.',
Po='Poc:BAABLgAECn8nAAIHAAgJ3BEyFAB+AQAHAAgJ3BEyFAB+AQAAAA==.Pokoko:BAAALgADCgUJBgAAAA==.',
Pr='Priblet:BAAALgAFFAEJAQAAAA==.Primo:BAAALgAECgYJDAAAAA==.Prinsana:BAABLgAECn85AAIZAAkJPBVkDQDvAQAZAAkJPBVkDQDvAQAAAA==.',
Pu='Puddytat:BAAALgADCgMJAwAAAA==.Purged:BAABLgAECn8gAAIKAAkJOAbtXwA8AQAKAAkJOAbtXwA8AQAAAA==.Purquis:BAAALgAECgEJAQAAAA==.',
Py='Pya:BAAALgAECgEJAQAAAA==.',
Ra='Ragnus:BAAALgADCgEJAQAAAA==.Raidwipe:BAAALgADCgIJAgABLgAECgcJEAANAAAAAA==.Ralphie:BAAALgADCgcJAQAAAA==.Rasen:BAAALgAECgIJAgABLgAECgUJBQANAAAAAA==.Ratheer:BAABLgAFFH8FAAIFAAIJSRXcfACEAAAFAAIJSRXcfACEAAABLgAFFAMJBQAdAFUZAA==.Rawfalafel:BAAALgAECggJEwAAAA==.',
Re='Reaperlord:BAABLgAECn8uAAIhAAgJyRx/EACUAgAhAAgJyRx/EACUAgAAAA==.',
Rh='Rhoana:BAAALgADCgcJBwAAAA==.',
Rl='Rllybuffnerd:BAAALgAECgIJAgAAAA==.',
Ro='Rodikus:BAACLgAFFH8KAAIaAAQJkRg0EwAvAQAaAAQJkRg0EwAvAQAuAAQKf0IAAxoACQlPInERAFYCABoACAllInERAFYCAAgACQlhF+sVABwCAAAA.Rootbeer:BAAALgADCgYJBgAAAA==.Rorax:BAABLgAECn8jAAIFAAgJxRkJNwDqAQAFAAgJxRkJNwDqAQAAAA==.Rosanna:BAAALgAECgQJBQAAAA==.',
Rp='Rprunner:BAAALgAECgUJBQABLgAECgcJFgAVAJwPAA==.',
Ru='Rukus:BAAALgADCgQJBAAAAA==.',
['Rä']='Räwry:BAAALgAFFAQJBAABLgAFFAMJCAAJAAoMAA==.',
Sa='Saiaa:BAABLgAECn8eAAICAAkJTgagDgA6AQACAAkJTgagDgA6AQAAAA==.Sakeena:BAAALgAECgQJCAAAAA==.Samará:BAAALgAECgIJBgAAAA==.Sarleigh:BAABLgAECn8YAAIIAAcJdQPtWwCnAAAIAAcJdQPtWwCnAAAAAA==.Sattia:BAABLgAECn9RAAIUAAkJxwcUAgDOAAAUAAkJxwcUAgDOAAAAAA==.',
Sc='Scampington:BAAALgAECgYJDAAAAA==.',
Se='Sertzert:BAABLgAECn8WAAIHAAYJXhinGwAvAQAHAAYJXhinGwAvAQAAAA==.',
Sh='Sharokk:BAAALgAECgcJCQABLgAECggJIwAFAMUZAA==.Sharrow:BAAALgAECgMJAwAAAA==.Shiggy:BAAALgAECgIJAgAAAA==.Shinokami:BAABLgAECn8uAAMTAAgJDBNuJwB1AQATAAgJZxFuJwB1AQAVAAEJ1xTXkQA/AAAAAA==.Shoto:BAAALgADCgEJAQAAAA==.',
Si='Silentninjaa:BAABLgAECn81AAIiAAkJUBzVEABwAgAiAAkJUBzVEABwAgAAAA==.Simphunter:BAEBLgAECn83AAIFAAkJfB4lEQC5AgAFAAkJfB4lEQC5AgAAAA==.Sinchan:BAAALgADCgEJAQAAAA==.Sindaea:BAAALgADCgYJBgAAAA==.Sinfel:BAABLgAECn85AAIRAAkJAxCrGQCzAQARAAkJAxCrGQCzAQAAAA==.Sit:BAAALgAECggJEgAAAA==.',
Sk='Skall:BAAALgAECgEJAQAAAA==.Skoree:BAABLgAECn8gAAIFAAkJgiC/GQC6AgAFAAkJgiC/GQC6AgAAAA==.',
Sl='Slït:BAAALgADCgIJAgAAAA==.',
Sm='Smellme:BAAALgAECgMJAwAAAA==.Smitedaddy:BAAALgAECgEJAQAAAA==.Smothbran:BAAALgADCgIJAwAAAA==.',
Sn='Snapdragon:BAAALgAECgQJBgAAAA==.',
So='Solarasun:BAAALgADCgkJDgABLgAECgYJFAAIAIAFAA==.Soluna:BAAALgAECgQJBAAAAA==.Someonelse:BAAALgAECgMJAwAAAA==.Sonett:BAAALgAECgQJCAAAAA==.',
Sp='Splunk:BAAALgAECgkJEQABLgAECgkJFwATABULAA==.Spânky:BAAALgAECgYJEQAAAA==.Spíké:BAAALgADCgkJCQAAAA==.',
Sq='Squiggles:BAABLgAECn8xAAIPAAkJDBi5BQBCAgAPAAkJDBi5BQBCAgAAAA==.',
St='Staggerdaddy:BAAALgADCgYJBgAAAA==.Stariya:BAAALgAECgQJBQAAAA==.Stillwing:BAAALgADCgIJAgAAAA==.Stormkraa:BAAALgAECgkJBwAAAA==.Strawyà:BAAALgADCgQJBwABLgAECgkJOgAZANAbAA==.Strawyæ:BAABLgAECn86AAIZAAkJ0BteCABSAgAZAAkJ0BteCABSAgAAAA==.Strike:BAAALgAECgYJCAABLgAFFAYJFAAhAHARAA==.',
Su='Succubi:BAAALgADCgIJAgAAAA==.Sugerfree:BAAALgAECgYJDAAAAA==.Sulkra:BAAALgAECgcJAQAAAA==.Suttercane:BAAALgAECgYJCQAAAA==.',
['Sì']='Sìrocco:BAAALgAECgYJDQAAAA==.',
Ta='Taleranor:BAAALgAECgcJEwAAAA==.Tallaeya:BAAALgAECgMJAwAAAA==.Tamerizer:BAABLgAECn8sAAMfAAkJhROREwAKAgAfAAkJZxGREwAKAgAPAAYJ8xAkRABFAQAAAA==.',
Te='Tealera:BAAALgAECgMJAwAAAA==.Teejrath:BAAALgAECgYJCAAAAA==.Teekeez:BAABLgAECn8cAAIEAAgJmQiGwQAHAQAEAAgJmQiGwQAHAQAAAA==.Terup:BAAALgADCgUJBQAAAA==.',
Th='Theodorel:BAAALgAECgIJBAAAAA==.Thillarys:BAAALgAECgEJAQAAAA==.Thirge:BAABLgAECn9DAAIiAAkJhxuODQCWAgAiAAkJhxuODQCWAgAAAA==.Thorek:BAAALgADCgkJIAAAAA==.Thrushbeard:BAAALgADCgkJHwAAAA==.Thunderracks:BAAALgAECgEJAQAAAA==.',
To='Tokas:BAAALgAECgIJAgAAAA==.Tolak:BAAALgAECgUJCwAAAA==.Torturousôwl:BAAALgAECgkJEAAAAA==.',
Tr='Traaze:BAAALgAECgYJDAABLgAFFAYJCwAEAGoVAA==.Tralle:BAAALgAECgMJAwAAAA==.Trapology:BAAALgAECgEJBAAAAA==.Trisky:BAABLgAECn8rAAMhAAkJ1BhPHQAYAgAhAAgJjxdPHQAYAgABAAcJNQ5GowAyAQAAAA==.Trissa:BAAALgADCgcJEQAAAA==.Trolldax:BAAALgADCgUJBwABLgAECgMJAwANAAAAAA==.Trydént:BAAALgAECgQJCAAAAA==.Trystàn:BAAALgADCgUJBQAAAA==.',
Tu='Tunip:BAAALgAECgIJAgAAAA==.Turtle:BAABLgAECn8dAAMOAAYJzhpRWwCMAQAOAAYJzhpRWwCMAQAMAAIJmwZsRQAiAAABLgAFFAMJCAASAFEgAA==.',
Ul='Ulric:BAAALgADCgkJEgAAAA==.',
Un='Unhenged:BAAALgADCgQJBAAAAA==.',
Va='Vaceriss:BAAALgADCgYJBgAAAA==.Valatar:BAAALgADCgcJCgAAAA==.Valdrakkquin:BAABLgAECn8sAAIjAAkJCyGRBgBvAgAjAAkJCyGRBgBvAgAAAA==.Valtreya:BAAALgADCgYJBgAAAA==.Vantadim:BAAALgADCgUJBQAAAA==.',
Ve='Vegito:BAABLgAECn80AAIiAAgJwAUsTwALAQAiAAgJwAUsTwALAQAAAA==.Velayna:BAAALgAECgYJBQAAAA==.Veramoon:BAAALgADCgYJBgAAAA==.',
Vi='Victoriia:BAAALgADCggJCAAAAA==.Vincente:BAAALgAECgYJDQAAAA==.Vistus:BAAALgAECgcJCwAAAA==.',
Vo='Void:BAAALgADCgQJBAABLgAECgkJQwAfAPoZAA==.Voidmeister:BAABLgAECn8WAAIFAAYJ+RJDmgDsAAAFAAYJ+RJDmgDsAAABLgAECggJKgALALchAA==.Voin:BAACLgAFFH8JAAIkAAUJBR0sAQBDAQAkAAUJBR0sAQBDAQAuAAQKf2IAAyQACQnUJGsBAEkDACQACQnUJGsBAEkDACIABAl9G6VUAPkAAAAA.Vorpine:BAABLgAECn8zAAMJAAkJpAzMIgC4AQAJAAkJpAzMIgC4AQAIAAcJkBl8LAByAQAAAA==.',
Vs='Vs:BAACLgAFFH8HAAIQAAMJ3RJHJQABAQAQAAMJ3RJHJQABAQAuAAQKfxUAAhAACAnYIKhSAPoBABAACAnYIKhSAPoBAAEuAAUUCQlHAAUAKCYA.',
Wa='Warcockeh:BAAALgADCgUJBQAAAA==.Watermelon:BAABLgAECn8cAAMWAAgJZxaHJgDyAQAWAAgJZxaHJgDyAQAVAAEJHgZLtwAhAAAAAA==.',
Wi='Winterberrie:BAAALgADCgYJBAAAAA==.Wirhl:BAABLgAECn8rAAILAAkJDBB8AQC8AQALAAkJDBB8AQC8AQAAAA==.',
Wo='Wolfrik:BAAALgAECgUJAwAAAA==.Worthatry:BAABLgAFFH8QAAIBAAUJQyB+KwBgAQABAAUJQyB+KwBgAQAAAA==.',
Wy='Wyn:BAABLgAECn8jAAIBAAgJRB8NNQAsAgABAAgJRB8NNQAsAgAAAA==.',
Xa='Xalbit:BAABLgAECn84AAIKAAkJWR6OCgAOAwAKAAkJWR6OCgAOAwAAAA==.Xanae:BAAALgAECggJDgAAAA==.Xanthrash:BAAALgAECgcJEAAAAA==.Xantia:BAABLgAECn86AAIUAAkJaRYuHwBNAgAUAAkJaRYuHwBNAgAAAA==.Xaraena:BAABLgAECn8fAAILAAkJfRr2KAATAgALAAkJfRr2KAATAgAAAA==.Xaraimarra:BAAALgADCgQJBAAAAA==.Xariz:BAAALgAECgcJEgAAAA==.',
Xe='Xedd:BAAALgAECgQJBgAAAA==.Xenlo:BAAALgAECgcJEAABLgAFFAUJFQAhAOQbAA==.',
Xy='Xyndrome:BAAALgAFFAEJAQAAAA==.Xyndrä:BAAALgADCgYJBgAAAA==.',
Yu='Yungun:BAAALgAECgEJAgAAAA==.',
Za='Zaizel:BAAALgADCgUJBQABLgAFFAYJGAAlAH8YAA==.Zathennyx:BAAALgADCgYJBgABLgAECgMJAwANAAAAAA==.',
Ze='Zeonhalifax:BAAALgAECgMJAwABLgAECgQJBQANAAAAAA==.Zercus:BAABLgAFFH8MAAIBAAQJXQm+WAD+AAABAAQJXQm+WAD+AAAAAA==.',
Zh='Zhryla:BAAALgADCgUJCQAAAA==.',
Zl='Zleakara:BAAALgADCgQJBAAAAA==.Zleako:BAAALgADCgMJAwAAAA==.',
Zo='Zoel:BAAALgADCgcJCwAAAA==.',
['Ðr']='Ðread:BAABLgAECn8iAAMXAAgJog5tEQBhAQAXAAgJUQ5tEQBhAQAQAAYJEQy+xQD2AAAAAA==.',
['ßß']='ßßq:BAAALgAECgEJAQAAAA==.ßßqñüt:BAAALgAECgIJAgAAAA==.',
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
