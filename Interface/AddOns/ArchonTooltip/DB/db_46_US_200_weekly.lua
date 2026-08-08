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

local lookup = {'Mage-Frost','Monk-Brewmaster','Druid-Restoration','DeathKnight-Unholy','Mage-Arcane','Shaman-Restoration','Warrior-Fury','Warrior-Arms','Hunter-BeastMastery','Paladin-Retribution','Warlock-Affliction','Shaman-Enhancement','Priest-Holy','Warlock-Destruction','Warlock-Demonology','DeathKnight-Blood','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Frost','DemonHunter-Devourer','Unknown-Unknown','Paladin-Protection','DemonHunter-Havoc','Priest-Shadow','Monk-Windwalker','Shaman-Elemental','DemonHunter-Vengeance','Priest-Discipline','Monk-Mistweaver','Warrior-Protection','Paladin-Holy','Evoker-Augmentation','Druid-Balance','Evoker-Preservation','Evoker-Devastation',}
local provider = {region='US',realm='Smolderthorn',name='US',type='weekly',zone=46,date='2026-08-04',data={Ac='Achoo:BAABLgAECn8YAAIBAAgJCQXH1wDmAAABAAgJCQXH1wDmAAAAAA==.Acorn:BAAALgADCgMJBAAAAA==.',
Ai='Aitnd:BAAALgAECgQJCAAAAA==.Aitns:BAAALgADCgUJBQAAAA==.',
Ak='Akabara:BAAALgAECgQJBwAAAA==.',
Al='Alatyr:BAAALgAECgUJBQABLgAECgkJGgACAHEYAA==.Alduinn:BAAALgADCggJEAAAAA==.',
Am='Amilde:BAAALgAECgkJEQABLgAFFAMJCAADAGkSAA==.Amongor:BAABLgAECn8YAAIEAAYJ3h95UAAAAgAEAAYJ3h95UAAAAgAAAA==.',
An='Anarisa:BAABLgAECn9xAAMBAAkJAiNBAgAYAwABAAkJAiNBAgAYAwAFAAUJcRGGCwAeAQAAAA==.',
Aq='Aquatide:BAAALgAFFAEJAQABLgAFFAkJKQAGAF0eAA==.',
Ar='Arcáz:BAABLgAECn8aAAMHAAkJXx2GAQCzAgAHAAkJXx2GAQCzAgAIAAEJVh8sEgBaAAAAAA==.Artoria:BAAALgADCgkJCwAAAA==.',
At='Athorama:BAABLgAFFH8GAAIJAAMJ5xe1JgAGAQAJAAMJ5xe1JgAGAQABLgAFFAYJJwAEACgdAA==.Atra:BAAALgAECgEJAQAAAA==.',
Av='Avelise:BAABLgAECn8UAAIBAAcJkBelaQADAgABAAcJkBelaQADAgABLgAFFAMJCAADAGkSAA==.Averse:BAACLgAFFH8nAAIEAAYJKB1CHgBsAQAEAAYJKB1CHgBsAQAuAAQKfzcAAgQACQmFILQYALICAAQACQmFILQYALICAAAA.',
Az='Azazygos:BAAALgAECgMJAwAAAA==.',
Ba='Baeloth:BAAALgADCgcJDAAAAA==.Barkknight:BAEALgAECgkJBQABLgAFFAcJFwAKAA0PAA==.Barley:BAAALgAECgUJBQAAAA==.Bauce:BAAALgAECgYJBgAAAA==.',
Be='Bearretheon:BAAALgADCgEJAQAAAA==.Behindyoubro:BAAALgAECgMJAwAAAA==.Benchtally:BAAALgAECgYJDAAAAA==.Benihíme:BAAALgAECgIJAgAAAA==.Bepizo:BAACLgAFFH8XAAMHAAUJpx9uLAACAQAHAAQJHxpuLAACAQAIAAMJyh0sFwCNAAAuAAQKf0YAAwgACQndJFwKAEUCAAgABgnSIlwKAEUCAAcABwmzItUpABICAAAA.',
Bl='Bluetide:BAACLgAFFH8pAAIGAAkJXR4ZAwCuAgAGAAkJXR4ZAwCuAgAuAAQKfykAAgYACQmOJo8AAOEDAAYACQmOJo8AAOEDAAAA.',
Br='Brokemav:BAACLgAFFH8GAAILAAIJVhcaBwC1AAALAAIJVhcaBwC1AAAuAAQKfy8AAgsABwkRIZYCAJMCAAsABwkRIZYCAJMCAAAA.Brooklin:BAABLgAECn8yAAIBAAkJnh7dKwDDAgABAAkJnh7dKwDDAgAAAA==.',
Bu='Busky:BAABLgAECn8lAAMGAAkJAhVaKwDfAQAGAAkJAhVaKwDfAQAMAAcJkhHVFwBLAQAAAA==.',
Ca='Cao:BAABLgAECn8WAAIKAAkJbAx3EQBLAQAKAAkJbAx3EQBLAQAAAA==.Carboncredit:BAABLgAECn8iAAIMAAkJrRAICgAyAgAMAAkJrRAICgAyAgAAAA==.Cassiopea:BAABLgAECn8bAAINAAgJEhupGAAHAgANAAgJEhupGAAHAgAAAA==.Caysia:BAABLgAFFH8IAAIDAAMJaRK5QQCqAAADAAMJaRK5QQCqAAAAAA==.',
Ce='Cellcept:BAABLgAECn8XAAIOAAUJGh4oDgBaAQAOAAUJGh4oDgBaAQAAAA==.',
Ch='Chareth:BAABLgAECn8oAAIBAAkJNgpAcQCXAQABAAkJNgpAcQCXAQAAAA==.Charlee:BAAALgADCgcJBwAAAA==.Chaunticleer:BAAALgAECgcJCwAAAA==.Chesumadre:BAAALgAECgQJBAAAAA==.Chinchillada:BAABLgAECn8lAAIBAAkJCxcUWgDPAQABAAkJCxcUWgDPAQAAAA==.',
Ci='Cinderfal:BAAALgAECgEJAgAAAA==.',
Cl='Claggor:BAAALgAECgMJAwAAAA==.',
Co='Coldbrewed:BAAALgAECgYJBgAAAA==.Cowladin:BAAALgAECgMJBQABLgAECgkJJAAPAAcfAA==.',
Cr='Crossover:BAAALgADCgYJBgAAAA==.',
['Cà']='Càss:BAAALgAECgQJBQABLgAECggJGwANABIbAA==.',
Da='Dabajabaza:BAABLgAECn84AAIQAAkJ6wpkIwA4AQAQAAkJ6wpkIwA4AQAAAA==.Dabergerak:BAACLgAFFH8JAAIHAAMJXCFqLgD4AAAHAAMJXCFqLgD4AAAuAAQKfysAAgcACQmcJWEDADUDAAcACQmcJWEDADUDAAAA.Daenys:BAAALgAECgMJAwABLgAFFAkJMQALACwYAA==.Daggart:BAAALgAECgkJDgAAAA==.Dagrimreaper:BAAALgADCgcJBgABLgAECggJGAALAMIeAA==.Daila:BAAALgAECgEJAgAAAA==.Dakrus:BAACLgAFFH8FAAIRAAMJmg2XIQDNAAARAAMJmg2XIQDNAAAuAAQKfyUAAxIACQkwGVIgACMCABIACAmpFlIgACMCABEABgk9DlUsAEEBAAAA.Dankestacorn:BAAALgADCggJDgAAAA==.Darthßsaber:BAAALgADCgUJBQAAAA==.Dax:BAAALgADCgYJBgAAAA==.',
De='Deadazz:BAABLgAECn8aAAMTAAcJCQ0eFgAoAQATAAcJCQ0eFgAoAQAQAAYJCgSvQwCAAAABLgAFFAcJDQAPAJALAA==.Deadputz:BAAALgAECggJEwABLgAFFAMJCAAUADcbAA==.Deeiinnduh:BAAALgAECgYJBgAAAA==.Dein:BAAALgAECgcJEQAAAA==.Dejanira:BAABLgAECn8gAAIDAAkJzhFpQACQAQADAAkJzhFpQACQAQAAAA==.Demonslayerr:BAAALgADCgQJBAAAAA==.Demotope:BAAALgADCgcJDAABLgAECgYJDAAVAAAAAA==.',
Di='Diddily:BAABLgAECn8YAAMWAAkJjBTuCQC4AAAWAAkJjBTuCQC4AAAKAAIJ7QMwxAEiAAAAAA==.Diesverdi:BAAALgAECgMJAwAAAA==.Dirtylilskin:BAAALgADCgkJHQAAAA==.',
Do='Dookie:BAAALgAECgQJBAAAAA==.',
Dr='Draconae:BAABLgAECn8bAAIXAAYJWQf/PgC6AAAXAAYJWQf/PgC6AAAAAA==.Dracotope:BAAALgAECgYJDAAAAA==.Dragonjoy:BAABLgAECn8kAAIQAAkJORbrFgCwAQAQAAkJORbrFgCwAQAAAA==.Drathier:BAAALgAECgIJAgAAAA==.Dridarok:BAABLgAECn8gAAIHAAkJqQyELgCWAQAHAAkJqQyELgCWAQAAAA==.',
['Dâ']='Dâwn:BAABLgAECn8WAAIYAAgJlQXARQD4AAAYAAgJlQXARQD4AAAAAA==.',
Ei='Eighttyhd:BAAALgADCgQJBAAAAA==.Eightyhd:BAAALgADCgIJAgAAAA==.Eirny:BAAALgAECgMJBAAAAA==.',
El='Eladamry:BAAALgAECgUJBwABLgAECggJMAAZAPQdAA==.Element:BAAALgADCgEJAQABLgAFFAUJFwAHAKcfAA==.Elise:BAABLgAECn8kAAMOAAkJQhckCQAvAgAOAAgJzBckCQAvAgALAAgJARH4DgBBAQAAAA==.Elstrid:BAABLgAECn8kAAMPAAkJBx8uMQAUAgAPAAkJBx8uMQAUAgAOAAEJAACdVQAAAAAAAA==.',
Er='Eremisa:BAABLgAECn8YAAIZAAkJNAu8BQA/AQAZAAkJNAu8BQA/AQABLgAECgkJcQABAAIjAA==.Erzaflame:BAAALgADCgEJAQAAAA==.',
Eu='Euphoria:BAAALgAECgMJAwABLgAECgkJPwAaAG4mAA==.',
Ev='Evochre:BAAALgAECgUJCQAAAA==.',
Fa='Faelgalus:BAAALgAECgUJBwAAAA==.Faerine:BAAALgADCgcJBwAAAA==.Fantasy:BAABLgAECn8/AAIaAAkJbiZHAwA7AwAaAAkJbiZHAwA7AwAAAA==.',
Fe='Felbourn:BAACLgAFFH8QAAMXAAQJTxg1CAAvAQAXAAQJTxg1CAAvAQAUAAEJLwnOWAAyAAAuAAQKfyAABBcACQlkIY4IANkCABcACAmJIY4IANkCABsAAgktFiUiAIwAABQAAgm7CW/MAF0AAAAA.Fendraim:BAAALgAECgYJCwABLgAECgcJEQAVAAAAAA==.',
Fi='Figurefour:BAAALgAECgkJDwAAAA==.',
Fo='Foedris:BAAALgADCgUJBQAAAA==.Forste:BAAALgAECgUJBQAAAA==.Foxfire:BAAALgAECgQJCAAAAA==.',
Fr='Frailboosy:BAACLgAFFH8ZAAIKAAcJWBQHDwCLAQAKAAcJWBQHDwCLAQAuAAQKf1sAAgoACQkYIvgLAAUDAAoACQkYIvgLAAUDAAAA.Fri:BAAALgADCgkJCQAAAA==.Frigamortis:BAABLgAECn8WAAITAAYJLAqOHwDQAAATAAYJLAqOHwDQAAAAAA==.',
Ga='Galnas:BAAALgADCgcJBwABLgAECgUJBwAVAAAAAA==.',
Ge='Gemini:BAAALgAECgQJBQAAAA==.',
Gi='Gilferno:BAAALgAECgQJBAAAAA==.',
Gl='Glitz:BAABLgAFFH8FAAIBAAUJawS/eADnAAABAAUJawS/eADnAAABLgAFFAYJEQAcAMwGAA==.',
Gn='Gnarfok:BAAALgAECgQJEwAAAA==.',
Go='Goopster:BAAALgADCgcJCQABLgAECgQJBgAVAAAAAA==.',
Gr='Graamps:BAABLgAECn8bAAIXAAcJzQsOCwDdAAAXAAcJzQsOCwDdAAAAAA==.Gravedigger:BAACLgAFFH8SAAMQAAQJuBsrFgA5AQAQAAQJuBsrFgA5AQATAAEJZADDLgAoAAAuAAQKf0YAAhAACQn/IHQCACoCABAACQn/IHQCACoCAAAA.',
Gu='Gunde:BAAALgAECgkJBQAAAA==.Gust:BAAALgAECgQJDwAAAA==.',
Ha='Hatredx:BAAALgADCgIJAgAAAA==.',
He='Heisenberg:BAAALgAECgQJCAABLgAFFAUJEQAJAA8PAA==.',
Ho='Holywagyu:BAAALgAECgYJBgAAAA==.',
Hy='Hyllinia:BAAALgADCgEJAQAAAA==.Hyõrinmaru:BAAALgAECgMJAwAAAA==.',
Ih='Iheal:BAAALgAECgEJAQAAAA==.',
In='Inarios:BAABLgAECn8rAAQcAAkJhxuJDQCVAgAcAAgJ/h2JDQCVAgAYAAQJlhUSPwAUAQANAAEJtwzPdQAkAAAAAA==.Infused:BAAALgAECgEJAQABLgAFFAMJBwADAMwPAA==.Inshape:BAAALgAECgYJEwAAAA==.',
Ir='Ironnman:BAAALgAECgEJAQABLgAECgkJGgACAHEYAA==.Ironnmonk:BAABLgAECn8aAAQCAAkJcRiBGwAnAgACAAkJcRiBGwAnAgAZAAEJihEPnQAyAAAdAAEJUgQwdQAcAAAAAA==.',
Ja='Javlin:BAAALgAECgYJEAAAAA==.Jawshoeuh:BAAALgADCgYJDQAAAA==.',
Jo='Joltarin:BAAALgAECgEJAQABLgAECgkJJAAPAAcfAA==.',
Ju='Jujufya:BAAALgAECgIJAgABLgAECggJEgAVAAAAAA==.Jujujab:BAAALgADCgMJAwABLgAECggJEgAVAAAAAA==.Jujukni:BAAALgAECgUJDQABLgAECggJEgAVAAAAAA==.Jujumon:BAAALgAECggJEgAAAA==.Jujupal:BAAALgAECgEJAQABLgAECggJEgAVAAAAAA==.Jujuzap:BAAALgADCgEJAQABLgAECggJEgAVAAAAAA==.Jujuzul:BAAALgADCgUJBgABLgAECggJEgAVAAAAAA==.Justimp:BAACLgAFFH8GAAIPAAMJTQj2hwC2AAAPAAMJTQj2hwC2AAAuAAQKfyQAAg8ACQl4FM1DANABAA8ACQl4FM1DANABAAAA.',
Ka='Kanon:BAABLgAECn8WAAIeAAkJBxObEgDCAQAeAAkJBxObEgDCAQAAAA==.Kanook:BAAALgAECgMJAwAAAA==.Karlek:BAABLgAFFH8HAAMfAAQJPg3oOACHAAAfAAMJ2gToOACHAAAKAAIJewS8ewA5AAAAAA==.Kazeshiní:BAAALgADCgUJBQAAAA==.',
Ke='Kelox:BAAALgAECgEJAQAAAA==.Keynddor:BAAALgAECgEJAQAAAA==.',
Ki='Kikily:BAAALgADCgkJCQAAAA==.',
Ko='Konsistency:BAABLgAECn8fAAIUAAcJlA6icgBNAQAUAAcJlA6icgBNAQAAAA==.Konviction:BAABLgAECn8fAAMKAAkJ/REKiQBeAQAKAAkJ/REKiQBeAQAWAAIJZwK3WQAcAAAAAA==.Korellon:BAAALgADCgMJAwAAAA==.',
Kr='Kreanth:BAAALgAECgkJAwAAAA==.Kreel:BAAALgAECgIJBgAAAA==.Kriskyle:BAAALgADCgYJBgAAAA==.Krogg:BAAALgADCgcJBwAAAA==.',
La='Lalana:BAABLgAECn8mAAIJAAkJ+g8XXgCMAQAJAAkJ+g8XXgCMAQAAAA==.Lan:BAAALgAFFAEJAQAAAA==.Landin:BAAALgAECgcJBwAAAA==.',
Li='Liari:BAECLgAFFH8IAAIBAAMJUwSSkwCtAAABAAMJUwSSkwCtAAAuAAQKfxwAAgEACAkrCuqRAFQBAAEACAkrCuqRAFQBAAEuAAUUBwkXAAoADQ8A.Libra:BAAALgADCgEJAQAAAA==.Lilith:BAACLgAFFH8RAAMcAAYJzAbHCABRAQAcAAYJzAbHCABRAQAYAAQJcwlWKAC7AAAuAAQKfyEAAxwACQmpGG4SACECABwACAk0GW4SACECABgABwmVHEchAM4BAAAA.Lithari:BAAALgADCggJCAAAAA==.',
Lo='Lofwyr:BAACLgAFFH8FAAIgAAMJyQHUUQCDAAAgAAMJyQHUUQCDAAAuAAQKfzQAAiAACQmjEggeAOcBACAACQmjEggeAOcBAAAA.Lootadots:BAAALgAECgEJAQABLgAECgYJGAAHAF4UAA==.',
Lu='Lumes:BAAALgAECgUJBQAAAA==.Lumie:BAABLgAECn8mAAMNAAkJAyCgCADCAgANAAkJAyCgCADCAgAYAAcJ4BEYNQBDAQABLgAFFAMJBwADAMwPAA==.Lumiea:BAAALgAECgYJBgABLgAFFAMJBwADAMwPAA==.Lunar:BAAALgADCgIJAgABLgAFFAYJEQAcAMwGAA==.Lunie:BAACLgAFFH8HAAIDAAMJzA/zQQCqAAADAAMJzA/zQQCqAAAuAAQKfyEAAwMACQkwHTUSALwCAAMACAnTHjUSALwCACEAAwkQC8QUAH4AAAAA.',
Ma='Magadeoz:BAABLgAECn8VAAMBAAcJ6QrOswAcAQABAAcJ6QrOswAcAQAFAAEJPgoLDwAlAAAAAA==.Magicshow:BAACLgAFFH8GAAIBAAMJpQcxjQC/AAABAAMJpQcxjQC/AAAuAAQKfx0AAgEACAn1EPyUAKoBAAEACAn1EPyUAKoBAAAA.Malachite:BAAALgADCgQJBAABLgAFFAYJEQAcAMwGAA==.Malzahar:BAAALgADCgEJAgAAAA==.',
Mc='Mcdracula:BAAALgAECgcJEgAAAA==.',
Mi='Milfred:BAAALgAFFAEJAQAAAA==.Mistrniceguy:BAAALgAECgEJAQAAAA==.',
Mo='Moarticia:BAAALgAECgYJCwABLgAFFAIJBQAgAFkRAA==.Moonbelle:BAAALgAECgcJDAABLgAFFAYJEQAcAMwGAA==.Moxcie:BAAALgAECgkJAQAAAA==.',
Mu='Murthius:BAAALgAECgYJEgAAAA==.Musky:BAAALgAECgEJAgAAAA==.',
My='Myoushi:BAAALgADCgEJAQAAAA==.',
Na='Naâmah:BAAALgAECgUJBQAAAA==.',
Ne='Necromachine:BAACLgAFFH8OAAIEAAQJkg13dgAVAQAEAAQJkg13dgAVAQAuAAQKfxwAAwQACQmYF/J7AGsBAAQACQmYF/J7AGsBABAAAglXBn8+AFYAAAAA.Neiry:BAAALgADCgcJBwAAAA==.Neon:BAAALgAECgYJDgABLgAECgkJPwAaAG4mAA==.',
No='Noctislucis:BAACLgAFFH8LAAIUAAQJ5gn0MgCpAAAUAAQJ5gn0MgCpAAAuAAQKfyEABBsACQn+CiwaAMwAABQABwmkCVmcAOkAABsABwkGCiwaAMwAABcAAQlyACyHAAMAAAAA.Noj:BAAALgADCgUJBQAAAA==.Noobdk:BAABLgAFFH8UAAMQAAkJZhrmAgBsAgAQAAkJIhrmAgBsAgAEAAMJBB8bMgAHAQAAAA==.Noobmonkey:BAACLgAFFH8aAAICAAYJ8yIXBQBJAgACAAYJ8yIXBQBJAgAuAAQKfzMAAgIACQn4JSYBAGIDAAIACQn4JSYBAGIDAAEuAAUUCQkUABAAZhoA.Noobwarr:BAABLgAFFH8HAAIeAAQJdh33BwBVAQAeAAQJdh33BwBVAQABLgAFFAkJFAAQAGYaAA==.Novax:BAAALgAECgQJBgAAAA==.',
Nu='Numeral:BAABLgAFFH8GAAMNAAIJtw32DQCOAAANAAIJtw32DQCOAAAYAAIJsBG7LwCIAAAAAA==.',
Ol='Olegregg:BAAALgADCgUJCAAAAA==.',
On='Onzynn:BAAALgADCgcJCAAAAA==.',
Pa='Paracelsus:BAAALgAECgYJCwAAAA==.',
Pe='Pepka:BAAALgAECgYJCwAAAA==.',
Ph='Phillcollins:BAABLgAECn8pAAMGAAYJfhuUOgDEAQAGAAYJfhuUOgDEAQAaAAYJRhO1RAAgAQABLgAFFAMJBwAgAOcRAA==.',
Pi='Pinktide:BAAALgAECgYJDAABLgAFFAkJKQAGAF0eAA==.',
Po='Pouka:BAAALgAECggJCAABLgAECgkJNAAPALslAA==.Power:BAAALgADCgcJBwAAAA==.',
Pr='Prettypoison:BAABLgAECn9DAAIJAAkJZhr2BgAYAgAJAAkJZhr2BgAYAgAAAA==.',
Pu='Putz:BAACLgAFFH8IAAIUAAMJNxv3UAD6AAAUAAMJNxv3UAD6AAAuAAQKf00AAxQACQlEJDUFADUDABQACQlEJDUFADUDABsAAQnqEaU0ADIAAAAA.',
Ra='Raditz:BAAALgADCgYJBgABLgAFFAkJKQAGAF0eAA==.Rainbow:BAABLgAECn8wAAIdAAkJcR/dCQD7AgAdAAkJcR/dCQD7AgABLgAECgkJPwAaAG4mAA==.Rastasham:BAAALgAECggJDgAAAA==.Ratfondler:BAACLgAFFH8IAAMZAAMJah51GAAAAQAZAAMJah51GAAAAQAdAAEJcwaRawApAAAuAAQKfywAAxkACQlMI6wDACUDABkACQlMI6wDACUDAB0ABAlSD9xvAMgAAAAA.',
Re='Reialaleigh:BAAALgAECgUJDQAAAA==.',
Ri='Ricanthetank:BAAALgAECgQJBAAAAA==.',
Ry='Rysho:BAAALgAECgEJAQAAAA==.',
Sa='Sabeam:BAACLgAFFH8XAAIUAAcJSxOfCQCQAQAUAAcJSxOfCQCQAQAuAAQKfzAAAhQACQnwH84HAE0DABQACQnwH84HAE0DAAAA.Saberdiva:BAABLgAECn81AAIKAAgJlBEQkQBQAQAKAAgJlBEQkQBQAQAAAA==.Saberlorian:BAAALgAECgEJAQAAAA==.Sabershot:BAAALgADCgMJAwAAAA==.Sabersidious:BAAALgADCgUJBQAAAA==.Saberthyr:BAAALgADCgkJEQAAAA==.Saberwookie:BAAALgADCgUJBQAAAA==.Sabs:BAAALgAFFAIJAgABLgAFFAcJFwAUAEsTAA==.Sagesteppe:BAABLgAECn8WAAIMAAYJ9ghkIgDkAAAMAAYJ9ghkIgDkAAAAAA==.Santhon:BAAALgAECgEJAwAAAA==.',
Sc='Scotticus:BAABLgAECn8jAAIEAAgJKg+KkgBBAQAEAAgJKg+KkgBBAQAAAA==.',
Se='Seditionist:BAABLgAECn8iAAMaAAgJIQXhVgDgAAAaAAgJIQXhVgDgAAAGAAEJqAHOQwAUAAAAAA==.Sellis:BAAALgAECgEJAQAAAA==.',
Sh='Shakira:BAAALgADCgkJCQABLgAECgUJDQAVAAAAAA==.Shammywow:BAAALgADCgEJAQAAAA==.Shamon:BAAALgAECgkJBQAAAA==.Sharuga:BAAALgADCgkJCQAAAA==.Shinju:BAAALgAECgEJAQAAAA==.Shocrates:BAAALgAECgIJBAABLgAECgUJBwAVAAAAAA==.Shåtheed:BAAALgADCgYJBgAAAA==.',
Si='Sidthekid:BAABLgAECn8ZAAQiAAYJBBKRBQDTAAAiAAYJBBKRBQDTAAAjAAMJ2ROGGgB6AAAgAAEJVBYOGQBAAAAAAA==.Sinayion:BAABLgAECn8uAAIWAAkJnwSTJgDhAAAWAAkJnwSTJgDhAAAAAA==.',
Sl='Sluggina:BAAALgAECgIJAwAAAA==.',
So='Sonamis:BAAALgADCgYJBwAAAA==.Sorrôw:BAAALgAECgEJAQAAAA==.',
St='Stepbro:BAAALgAFFAEJAQABLgAECggJGwANABIbAA==.Stepdemonh:BAAALgADCgkJEwAAAA==.Stepmôm:BAAALgAECgEJAQABLgAECggJGwANABIbAA==.Stepsis:BAAALgAFFAEJAQABLgAECggJGwANABIbAA==.Stinkoman:BAAALgAECgQJBwABLgAECgQJCAAVAAAAAA==.',
Su='Sunarena:BAABLgAECn8fAAIKAAkJJg8QiwBbAQAKAAkJJg8QiwBbAQAAAA==.',
Ta='Tankobell:BAABLgAECn8bAAIKAAkJBhHjWQC/AQAKAAkJBhHjWQC/AQAAAA==.Tavius:BAAALgADCgEJAQAAAA==.',
Te='Terrible:BAEALgAECgcJAgABLgAFFAgJHQAHACUZAA==.',
Th='Thaldos:BAAALgAECgEJAgABLgAECgUJBwAVAAAAAA==.Thannatos:BAAALgAECgEJAQAAAA==.Thejuiciest:BAAALgADCgEJAgAAAA==.',
To='Tommet:BAAALgADCgUJBQAAAA==.Toukadh:BAAALgAECgYJAgAAAA==.',
Tr='Truart:BAAALgAFFAIJBAAAAA==.',
Tu='Tuerjoie:BAABLgAECn8mAAIBAAgJQhgNUgDmAQABAAgJQhgNUgDmAQAAAA==.',
Tw='Twíla:BAAALgADCgYJCwAAAA==.',
Ty='Tywin:BAAALgAECgMJAwAAAA==.',
Ug='Ugooboom:BAAALgAECgEJAQAAAA==.',
Uh='Uh:BAAALgADCgYJDAAAAA==.',
Un='Unclemagic:BAAALgAECgYJDAABLgAFFAcJDQAPAJALAA==.',
Ut='Utopia:BAAALgAECgQJAwAAAA==.',
Va='Valesko:BAAALgAFFAEJAQAAAA==.Varfus:BAACLgAFFH84AAMbAAkJaSEuAADpAgAbAAkJaSEuAADpAgAUAAMJCSAKIQALAQAuAAQKfzMAAhsACQlKJnIAAFwDABsACQlKJnIAAFwDAAAA.',
Ve='Velentre:BAAALgAECgkJEQAAAA==.',
Vi='Vichy:BAAALgAECgYJCQAAAA==.Vikstyn:BAAALgAECgEJBAAAAA==.',
Vu='Vulquin:BAAALgAECgUJBQAAAA==.',
We='Weather:BAAALgAECgYJCAAAAA==.',
Wi='Wigskid:BAAALgADCgEJAQAAAA==.Winney:BAACLgAFFH8GAAIKAAUJSxXKXwDwAAAKAAUJSxXKXwDwAAAuAAQKfysAAgoACQnbJFUGAD4DAAoACQnbJFUGAD4DAAAA.',
Wo='Wolfjob:BAAALgADCgUJBQAAAA==.Wouka:BAABLgAECn80AAQPAAkJuyUJBABQAwAPAAkJqSUJBABQAwALAAYJqiPVAwBQAgAOAAIJsiPlKwBnAAAAAA==.',
Wr='Wrequiem:BAABLgAECn8dAAITAAgJvAwxBQAWAQATAAgJvAwxBQAWAQAAAA==.',
Wu='Wukong:BAAALgADCgMJAwAAAA==.',
Xh='Xhiaky:BAAALgAECgEJAQAAAA==.',
Ya='Yarlyah:BAAALgADCgkJDgABLgAECgUJBwAVAAAAAA==.',
Yo='Yonnyy:BAAALgAECgYJCwAAAA==.Yoyomba:BAAALgAECgUJBQABLgAECggJMAAZAPQdAA==.',
Za='Zargonia:BAAALgAECgEJAQAAAA==.Zaria:BAAALgADCgUJBQAAAA==.',
Ze='Zendetra:BAAALgADCgUJBQABLgAECgYJEQAVAAAAAA==.Zeposo:BAACLgAFFH8IAAINAAUJ+A7tDgC4AAANAAUJ+A7tDgC4AAAuAAQKfzoAAw0ACQlGICcBAOACAA0ACQlGICcBAOACABgAAgkJCF0qACUAAAAA.Zeppo:BAABLgAECn8UAAMfAAUJCRKHCQASAQAfAAUJCRKHCQASAQAKAAQJbAknNAB3AAABLgAFFAUJCAANAPgOAA==.Zeptide:BAABLgAECn9mAAMGAAkJZh5PDAD3AgAGAAkJZh5PDAD3AgAaAAkJ/Bd8BADHAQABLgAFFAUJCAANAPgOAA==.Zervish:BAAALgAECgEJAQAAAA==.',
Zo='Zoli:BAABLgAECn8YAAIRAAgJ2R8mCwBtAgARAAgJ2R8mCwBtAgAAAA==.',
Zr='Zrichfu:BAAALgADCgIJAgABLgAFFAMJBwAPAFUGAA==.',
Zu='Zugnuts:BAAALgAECgcJBwAAAA==.',
['Øp']='Øphelia:BAAALgAECgMJAwAAAA==.',
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
