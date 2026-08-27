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

local lookup = {'Mage-Frost','Monk-Brewmaster','Druid-Restoration','DeathKnight-Unholy','Mage-Arcane','Shaman-Restoration','Warrior-Fury','Warrior-Arms','Hunter-BeastMastery','Paladin-Retribution','Unknown-Unknown','Warlock-Affliction','Shaman-Enhancement','Priest-Holy','Warlock-Destruction','Warlock-Demonology','DeathKnight-Blood','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Frost','DemonHunter-Devourer','Paladin-Protection','DemonHunter-Havoc','Priest-Shadow','Monk-Windwalker','Shaman-Elemental','DemonHunter-Vengeance','Priest-Discipline','Monk-Mistweaver','Warrior-Protection','Paladin-Holy','Evoker-Augmentation','Druid-Balance','Evoker-Preservation','Evoker-Devastation',}
local provider = {region='US',realm='Smolderthorn',name='US',type='weekly',zone=46,date='2026-08-25',data={Ac='Achoo:BAABLgAECn8YAAIBAAgJCQXH1wDmAAABAAgJCQXH1wDmAAAAAA==.Acorn:BAAALgADCgMJBAAAAA==.',
Ai='Aitnd:BAAALgAECgQJCAAAAA==.Aitns:BAAALgADCgUJBQAAAA==.',
Ak='Akabara:BAAALgAECgQJBwAAAA==.',
Al='Alatyr:BAAALgAECgUJBQABLgAECgkJGgACAHEYAA==.Alduinn:BAAALgADCggJEAAAAA==.',
Am='Amilde:BAAALgAECgkJEQABLgAFFAMJCAADAGkSAA==.Amongor:BAABLgAECn8YAAIEAAYJ3h95UAAAAgAEAAYJ3h95UAAAAgAAAA==.',
An='Anarisa:BAABLgAECn96AAMBAAkJUiMfAgApAwABAAkJUiMfAgApAwAFAAUJcRGGCwAeAQAAAA==.',
Aq='Aquatide:BAAALgAFFAEJAQABLgAFFAkJKgAGAGAfAA==.',
Ar='Arcáz:BAABLgAECn8aAAMHAAkJXx2nAQCxAgAHAAkJXx2nAQCxAgAIAAEJVh9zFABaAAAAAA==.Artoria:BAAALgADCgkJCwAAAA==.',
At='Athorama:BAABLgAFFH8GAAIJAAMJ5xfHJwAGAQAJAAMJ5xfHJwAGAQABLgAFFAYJJwAEACgdAA==.Atra:BAAALgAECgEJAQAAAA==.',
Av='Avelise:BAABLgAECn8UAAIBAAcJkBelaQADAgABAAcJkBelaQADAgABLgAFFAMJCAADAGkSAA==.Averse:BAACLgAFFH8nAAIEAAYJKB0yHwBsAQAEAAYJKB0yHwBsAQAuAAQKfzcAAgQACQmFILQYALICAAQACQmFILQYALICAAAA.',
Az='Azazygos:BAAALgAECgMJAwAAAA==.',
Ba='Baeloth:BAAALgADCgcJDAAAAA==.Barkknight:BAEALgAECgkJBQABLgAFFAcJFwAKAA0PAA==.Barley:BAAALgAECgUJBQAAAA==.Bauce:BAAALgAECgYJBgAAAA==.',
Be='Bearretheon:BAAALgADCgEJAQAAAA==.Behindyoubro:BAAALgAECgMJAwAAAA==.Benchtally:BAAALgAECgYJDAAAAA==.Benihíme:BAAALgAECgIJAgAAAA==.Bepizo:BAACLgAFFH8XAAMHAAUJpx9uLAACAQAHAAQJHxpuLAACAQAIAAMJyh3uFwCQAAAuAAQKf0YAAwgACQndJFwKAEUCAAgABgnSIlwKAEUCAAcABwmzItUpABICAAAA.',
Bl='Bluetide:BAACLgAFFH8qAAIGAAkJYB8ZAwCuAgAGAAkJYB8ZAwCuAgAuAAQKfykAAgYACQmOJo8AAOEDAAYACQmOJo8AAOEDAAAA.',
Bo='Borgus:BAAALgADCgkJCQABLgAECgUJBwALAAAAAA==.',
Br='Brokemav:BAACLgAFFH8GAAIMAAIJVhdDBwC0AAAMAAIJVhdDBwC0AAAuAAQKfy8AAgwABwkRIZYCAJMCAAwABwkRIZYCAJMCAAAA.Brooklin:BAABLgAECn8yAAIBAAkJnh7dKwDDAgABAAkJnh7dKwDDAgAAAA==.',
Bu='Busky:BAABLgAECn8lAAMGAAkJAhVaKwDfAQAGAAkJAhVaKwDfAQANAAcJkhHVFwBLAQAAAA==.',
Ca='Cao:BAABLgAECn8WAAIKAAkJbAziEgBLAQAKAAkJbAziEgBLAQAAAA==.Carboncredit:BAABLgAECn8iAAINAAkJrRAICgAyAgANAAkJrRAICgAyAgAAAA==.Cassiopea:BAABLgAECn8bAAIOAAgJEhupGAAHAgAOAAgJEhupGAAHAgAAAA==.Caysia:BAABLgAFFH8IAAIDAAMJaRK5QQCqAAADAAMJaRK5QQCqAAAAAA==.',
Ce='Cellcept:BAABLgAECn8XAAIPAAUJGh4oDgBaAQAPAAUJGh4oDgBaAQAAAA==.',
Ch='Chareth:BAABLgAECn8oAAIBAAkJNgpAcQCXAQABAAkJNgpAcQCXAQAAAA==.Charlee:BAAALgADCgcJBwAAAA==.Chaunticleer:BAAALgAECgcJCwAAAA==.Chesumadre:BAAALgAECgQJBAAAAA==.Chinchillada:BAABLgAECn8lAAIBAAkJCxcUWgDPAQABAAkJCxcUWgDPAQAAAA==.',
Ci='Cinderfal:BAAALgAECgEJAgAAAA==.',
Cl='Claggor:BAAALgAECgMJAwAAAA==.',
Co='Coldbrewed:BAAALgAECgYJBgAAAA==.Cowladin:BAAALgAECgMJBQABLgAECgkJJAAQAAcfAA==.',
Cr='Crossover:BAAALgADCgYJBgAAAA==.',
['Cà']='Càss:BAAALgAECgQJBQABLgAECggJGwAOABIbAA==.',
Da='Dabajabaza:BAABLgAECn84AAIRAAkJ6wpkIwA4AQARAAkJ6wpkIwA4AQAAAA==.Dabergerak:BAACLgAFFH8JAAIHAAMJXCFqLgD4AAAHAAMJXCFqLgD4AAAuAAQKfysAAgcACQmcJWEDADUDAAcACQmcJWEDADUDAAAA.Daenys:BAAALgAECgMJAwABLgAFFAkJMQAMACwYAA==.Daggart:BAAALgAECgkJDgAAAA==.Dagrimreaper:BAAALgADCgcJBgABLgAECggJGAAMAMIeAA==.Daila:BAAALgAECgEJAgAAAA==.Dakrus:BAACLgAFFH8FAAISAAMJmg2XIQDNAAASAAMJmg2XIQDNAAAuAAQKfyUAAxMACQkwGVIgACMCABMACAmpFlIgACMCABIABgk9DlUsAEEBAAAA.Dankestacorn:BAAALgADCggJDgAAAA==.Darthßsaber:BAAALgAECgEJAQAAAA==.Dax:BAAALgADCgYJBgAAAA==.',
De='Deadazz:BAABLgAECn8aAAMUAAcJCQ0eFgAoAQAUAAcJCQ0eFgAoAQARAAYJCgSvQwCAAAABLgAFFAcJDQAQAJALAA==.Deadputz:BAAALgAECggJEwABLgAFFAMJCAAVADcbAA==.Deeiinnduh:BAAALgAECgYJBgAAAA==.Dein:BAAALgAECgcJEQAAAA==.Dejanira:BAABLgAECn8gAAIDAAkJzhFpQACQAQADAAkJzhFpQACQAQAAAA==.Demonslayerr:BAAALgADCgQJBAAAAA==.Demotope:BAAALgADCgcJDAABLgAECgYJDAALAAAAAA==.',
Di='Diddily:BAABLgAECn8YAAMWAAkJjBSvCgC2AAAWAAkJjBSvCgC2AAAKAAIJ7QMwxAEiAAAAAA==.Diesverdi:BAAALgAECgMJAwAAAA==.Dirtylilskin:BAAALgADCgkJHQAAAA==.',
Do='Dookie:BAAALgAECgQJBAAAAA==.',
Dr='Draconae:BAABLgAECn8bAAIXAAYJWQf/PgC6AAAXAAYJWQf/PgC6AAAAAA==.Dracotope:BAAALgAECgYJDAAAAA==.Dragonjoy:BAABLgAECn8kAAIRAAkJORbrFgCwAQARAAkJORbrFgCwAQAAAA==.Drathier:BAAALgAECgIJAgAAAA==.Dridarok:BAABLgAECn8gAAIHAAkJqQyELgCWAQAHAAkJqQyELgCWAQAAAA==.',
['Dâ']='Dâwn:BAABLgAECn8WAAIYAAgJlQXARQD4AAAYAAgJlQXARQD4AAAAAA==.',
Ei='Eighttyhd:BAAALgADCgQJBAAAAA==.Eightyhd:BAAALgADCgIJAgAAAA==.Eirny:BAAALgAECgMJBAAAAA==.',
El='Element:BAAALgADCgEJAQABLgAFFAUJFwAHAKcfAA==.Elise:BAABLgAECn8kAAMPAAkJQhckCQAvAgAPAAgJzBckCQAvAgAMAAgJARH4DgBBAQAAAA==.Elstrid:BAABLgAECn8kAAMQAAkJBx8uMQAUAgAQAAkJBx8uMQAUAgAPAAEJAACdVQAAAAAAAA==.',
Er='Eremisa:BAABLgAECn8YAAIZAAkJNAtxBgA3AQAZAAkJNAtxBgA3AQABLgAECgkJegABAFIjAA==.Erzaflame:BAAALgADCgEJAQAAAA==.',
Eu='Euphoria:BAAALgAECgMJAwABLgAECgkJQAAaAG4mAA==.',
Ev='Evochre:BAAALgAECgUJCQAAAA==.',
Fa='Faelgalus:BAAALgAECgUJBwAAAA==.Faerine:BAAALgADCgcJBwAAAA==.Fantasy:BAABLgAECn9AAAIaAAkJbiZHAwA7AwAaAAkJbiZHAwA7AwAAAA==.',
Fe='Felbourn:BAACLgAFFH8QAAMXAAQJTximCAApAQAXAAQJTximCAApAQAVAAEJLwklXAAuAAAuAAQKfyAABBcACQlkIY4IANkCABcACAmJIY4IANkCABsAAgktFiUiAIwAABUAAgm7CW/MAF0AAAAA.Fendraim:BAAALgAECgYJCwABLgAECgcJEQALAAAAAA==.',
Fi='Figurefour:BAAALgAECgkJDwAAAA==.',
Fo='Foedris:BAAALgADCgUJBQAAAA==.Forste:BAAALgAECgUJBQAAAA==.Foxfire:BAAALgAECgQJCAAAAA==.',
Fr='Frailboosy:BAACLgAFFH8dAAIKAAcJThfxCwC6AQAKAAcJThfxCwC6AQAuAAQKf1sAAgoACQkYIvgLAAUDAAoACQkYIvgLAAUDAAAA.Fri:BAAALgADCgkJCQAAAA==.Frigamortis:BAABLgAECn8WAAIUAAYJLAqOHwDQAAAUAAYJLAqOHwDQAAAAAA==.',
Ga='Galnas:BAAALgADCgcJBwABLgAECgUJBwALAAAAAA==.',
Ge='Gemini:BAAALgAECgUJBgAAAA==.',
Gi='Gilferno:BAAALgAECgQJBAAAAA==.',
Gl='Glitz:BAABLgAFFH8FAAIBAAUJawS/eADnAAABAAUJawS/eADnAAABLgAFFAYJEQAcAMwGAA==.',
Gn='Gnarfok:BAAALgAECgQJEwAAAA==.',
Go='Goopster:BAAALgADCgcJCQABLgAECgQJBgALAAAAAA==.',
Gr='Graamps:BAABLgAECn8bAAIXAAcJzQvwCwDdAAAXAAcJzQvwCwDdAAAAAA==.Gravedigger:BAACLgAFFH8SAAMRAAQJuBsrFgA5AQARAAQJuBsrFgA5AQAUAAEJZADDLgAoAAAuAAQKf0YAAhEACQn/ILACACoCABEACQn/ILACACoCAAAA.',
Gu='Gunde:BAAALgAECgkJBQAAAA==.Gust:BAAALgAECgQJDwAAAA==.',
Ha='Hatredx:BAAALgADCgIJAgAAAA==.',
He='Heisenberg:BAAALgAECgQJCAABLgAFFAUJEQAJAA8PAA==.',
Ho='Holywagyu:BAAALgAECgYJBgAAAA==.',
Hy='Hyllinia:BAAALgADCgEJAQAAAA==.Hyõrinmaru:BAAALgAECgMJAwAAAA==.',
Ih='Iheal:BAAALgAECgEJAQAAAA==.',
In='Inarios:BAABLgAECn8rAAQcAAkJhxuJDQCVAgAcAAgJ/h2JDQCVAgAYAAQJlhUSPwAUAQAOAAEJtwzPdQAkAAAAAA==.Infused:BAAALgAECgEJAQABLgAFFAMJBwADAMwPAA==.Inshape:BAAALgAECgYJEwAAAA==.',
Ir='Ironnman:BAAALgAECgEJAQABLgAECgkJGgACAHEYAA==.Ironnmonk:BAABLgAECn8aAAQCAAkJcRiBGwAnAgACAAkJcRiBGwAnAgAZAAEJihEPnQAyAAAdAAEJUgQwdQAcAAAAAA==.',
Ja='Javlin:BAAALgAECgYJEAAAAA==.Jawshoeuh:BAAALgADCgcJFAAAAA==.',
Ji='Jindo:BAAALgAECgYJDAAAAA==.',
Jo='Joltarin:BAAALgAECgEJAQABLgAECgkJJAAQAAcfAA==.',
Ju='Jujufya:BAAALgAECgIJAgABLgAECggJEgALAAAAAA==.Jujujab:BAAALgADCgMJAwABLgAECggJEgALAAAAAA==.Jujukni:BAAALgAECgUJDQABLgAECggJEgALAAAAAA==.Jujumon:BAAALgAECggJEgAAAA==.Jujupal:BAAALgAECgEJAQABLgAECggJEgALAAAAAA==.Jujuzap:BAAALgADCgEJAQABLgAECggJEgALAAAAAA==.Jujuzul:BAAALgADCgUJBgABLgAECggJEgALAAAAAA==.Justimp:BAACLgAFFH8GAAIQAAMJTQj2hwC2AAAQAAMJTQj2hwC2AAAuAAQKfyQAAhAACQl4FM1DANABABAACQl4FM1DANABAAAA.',
Ka='Kanon:BAABLgAECn8WAAIeAAkJBxObEgDCAQAeAAkJBxObEgDCAQAAAA==.Kanook:BAAALgAECgMJAwAAAA==.Karlek:BAABLgAFFH8HAAMfAAQJPg3oOACHAAAfAAMJ2gToOACHAAAKAAIJewRaegA4AAAAAA==.Kazeshiní:BAAALgADCgUJBQAAAA==.',
Ke='Kelox:BAAALgAECgEJAQAAAA==.Keynddor:BAAALgAECgEJAQAAAA==.',
Ki='Kikily:BAAALgADCgkJCQAAAA==.',
Ko='Konsistency:BAABLgAECn8fAAIVAAcJlA6icgBNAQAVAAcJlA6icgBNAQAAAA==.Konviction:BAABLgAECn8fAAMKAAkJ/REKiQBeAQAKAAkJ/REKiQBeAQAWAAIJZwK3WQAcAAAAAA==.Korellon:BAAALgADCgMJAwAAAA==.',
Kr='Kreanth:BAAALgAECgkJAwAAAA==.Kreel:BAAALgAECgIJBgAAAA==.Kriskyle:BAAALgADCgYJBgAAAA==.Krogg:BAAALgADCgcJBwAAAA==.',
La='Lalana:BAABLgAECn8mAAIJAAkJ+g8XXgCMAQAJAAkJ+g8XXgCMAQAAAA==.Lan:BAAALgAFFAEJAQAAAA==.Landin:BAAALgAECgcJBwAAAA==.',
Li='Liari:BAECLgAFFH8IAAIBAAMJUwSsWgBtAAABAAMJUwSsWgBtAAAuAAQKfxwAAgEACAkrCuqRAFQBAAEACAkrCuqRAFQBAAEuAAUUBwkXAAoADQ8A.Libra:BAAALgADCgEJAQAAAA==.Lilith:BAACLgAFFH8RAAMcAAYJzAbHCABRAQAcAAYJzAbHCABRAQAYAAQJcwlWKAC7AAAuAAQKfyEAAxwACQmpGG4SACECABwACAk0GW4SACECABgABwmVHEchAM4BAAAA.Lithari:BAAALgADCggJCAABLgAFFAMJCAADAGkSAA==.',
Lo='Lofwyr:BAACLgAFFH8FAAIgAAMJyQHUUQCDAAAgAAMJyQHUUQCDAAAuAAQKfzQAAiAACQmjEggeAOcBACAACQmjEggeAOcBAAAA.Lootadots:BAAALgAECgEJAQABLgAECgYJGAAHAF4UAA==.',
Lu='Lumaie:BAACLgAFFH8HAAIDAAMJzA/zQQCqAAADAAMJzA/zQQCqAAAuAAQKfyMAAwMACQkwHTUSALwCAAMACAnTHjUSALwCACEABQlPDEISAKoAAAAA.Lumes:BAAALgAECgUJBQAAAA==.Lumie:BAABLgAECn8mAAMOAAkJAyCgCADCAgAOAAkJAyCgCADCAgAYAAcJ4BEYNQBDAQABLgAFFAMJBwADAMwPAA==.Lumiea:BAAALgAECgYJBgABLgAFFAMJBwADAMwPAA==.Lunar:BAAALgADCgIJAgABLgAFFAYJEQAcAMwGAA==.',
Ma='Magadeoz:BAABLgAECn8VAAMBAAcJ6QrOswAcAQABAAcJ6QrOswAcAQAFAAEJPgqrEQAlAAAAAA==.Magicshow:BAACLgAFFH8GAAIBAAMJpQcxjQC/AAABAAMJpQcxjQC/AAAuAAQKfx0AAgEACAn1EPyUAKoBAAEACAn1EPyUAKoBAAAA.Malachite:BAAALgADCgQJBAABLgAFFAYJEQAcAMwGAA==.Malzahar:BAAALgADCgEJAgAAAA==.',
Mc='Mcdracula:BAAALgAECgcJEgAAAA==.',
Mi='Milfred:BAAALgAFFAEJAQAAAA==.Mistrniceguy:BAAALgAECgEJAQAAAA==.',
Mo='Moarticia:BAAALgAECgYJCwABLgAFFAIJBQAgAFkRAA==.Moonbelle:BAAALgAECgcJDAABLgAFFAYJEQAcAMwGAA==.Moxcie:BAAALgAECgkJAQAAAA==.',
Mu='Murthius:BAAALgAECgYJEgAAAA==.Musky:BAAALgAECgEJAgAAAA==.',
My='Myoushi:BAAALgADCgEJAQAAAA==.',
Na='Naâmah:BAAALgAECgUJBQAAAA==.',
Ne='Necromachine:BAACLgAFFH8OAAIEAAQJkg13dgAVAQAEAAQJkg13dgAVAQAuAAQKfxwAAwQACQmYF/J7AGsBAAQACQmYF/J7AGsBABEAAglXBn8+AFYAAAAA.Neiry:BAAALgADCgcJBwAAAA==.Neon:BAAALgAECgYJDwABLgAECgkJQAAaAG4mAA==.',
No='Noctislucis:BAACLgAFFH8MAAIVAAQJnAqGMgCsAAAVAAQJnAqGMgCsAAAuAAQKfyEABBsACQn+CiwaAMwAABUABwmkCVmcAOkAABsABwkGCiwaAMwAABcAAQlyACyHAAMAAAAA.Noj:BAAALgADCgUJBQAAAA==.Noobdk:BAABLgAFFH8VAAMRAAkJZhogAwBoAgARAAkJIhogAwBoAgAEAAMJBB9dMwAGAQAAAA==.Noobmonkey:BAACLgAFFH8aAAICAAYJ8yIXBQBJAgACAAYJ8yIXBQBJAgAuAAQKfzMAAgIACQn4JSYBAGIDAAIACQn4JSYBAGIDAAEuAAUUCQkVABEAZhoA.Noobwarr:BAABLgAFFH8HAAIeAAQJdh00CABRAQAeAAQJdh00CABRAQABLgAFFAkJFQARAGYaAA==.Novax:BAAALgAECgQJBgAAAA==.',
Nu='Numeral:BAABLgAFFH8GAAMOAAIJtw32DQCOAAAOAAIJtw32DQCOAAAYAAIJsBG7LwCIAAAAAA==.',
Ol='Olegregg:BAAALgADCgUJCAAAAA==.',
On='Onzynn:BAAALgADCgcJCAAAAA==.',
Pa='Paracelsus:BAAALgAECgYJCwAAAA==.',
Pe='Pepka:BAAALgAECgYJCwAAAA==.',
Ph='Phillcollins:BAABLgAECn8pAAMGAAYJfhuUOgDEAQAGAAYJfhuUOgDEAQAaAAYJRhO1RAAgAQABLgAFFAMJBwAgAOcRAA==.',
Pi='Pinktide:BAAALgAECgYJDAABLgAFFAkJKgAGAGAfAA==.',
Po='Pouka:BAAALgAECggJCAABLgAECgkJNAAQALslAA==.Power:BAAALgADCgcJBwAAAA==.',
Pr='Prettypoison:BAABLgAECn9DAAIJAAkJZhqWBwAVAgAJAAkJZhqWBwAVAgAAAA==.',
Pu='Putz:BAACLgAFFH8IAAIVAAMJNxv3UAD6AAAVAAMJNxv3UAD6AAAuAAQKf00AAxUACQlEJDUFADUDABUACQlEJDUFADUDABsAAQnqEaU0ADIAAAAA.',
Ra='Raditz:BAAALgADCgYJBgABLgAFFAkJKgAGAGAfAA==.Rainbow:BAABLgAECn8wAAIdAAkJcR/dCQD7AgAdAAkJcR/dCQD7AgABLgAECgkJQAAaAG4mAA==.Rastasham:BAAALgAECggJDgAAAA==.Ratfondler:BAACLgAFFH8IAAMZAAMJah51GAAAAQAZAAMJah51GAAAAQAdAAEJcwaRawApAAAuAAQKfywAAxkACQlMI6wDACUDABkACQlMI6wDACUDAB0ABAlSD9xvAMgAAAAA.',
Re='Reialaleigh:BAAALgAECgUJDQAAAA==.',
Ri='Ricanthetank:BAAALgAECgQJBAAAAA==.',
Ry='Rysho:BAAALgAECgEJAQAAAA==.',
Sa='Sabeam:BAACLgAFFH8XAAIVAAcJSxOfCQCQAQAVAAcJSxOfCQCQAQAuAAQKfzAAAhUACQnwH84HAE0DABUACQnwH84HAE0DAAAA.Saberdiva:BAABLgAECn81AAIKAAgJlBEQkQBQAQAKAAgJlBEQkQBQAQAAAA==.Saberlorian:BAAALgAECgEJAQAAAA==.Sabershot:BAAALgADCgMJAwAAAA==.Sabersidious:BAAALgADCgUJBQAAAA==.Saberthyr:BAAALgADCgkJEQAAAA==.Saberwookie:BAAALgADCgUJBQAAAA==.Sabs:BAAALgAFFAIJAgABLgAFFAcJFwAVAEsTAA==.Sagesteppe:BAABLgAECn8WAAINAAYJ9ghkIgDkAAANAAYJ9ghkIgDkAAAAAA==.Santhon:BAAALgAECgEJAwAAAA==.',
Sc='Scotticus:BAABLgAECn8jAAIEAAgJKg+KkgBBAQAEAAgJKg+KkgBBAQAAAA==.',
Se='Seditionist:BAABLgAECn8iAAMaAAgJIQXhVgDgAAAaAAgJIQXhVgDgAAAGAAEJqAEXSAAUAAAAAA==.Sellis:BAAALgAECgEJAQAAAA==.',
Sh='Shakira:BAAALgADCgkJCQABLgAECgUJDQALAAAAAA==.Shammywow:BAAALgADCgEJAQAAAA==.Shamon:BAAALgAECgkJBQAAAA==.Sharuga:BAAALgADCgkJCQAAAA==.Shinju:BAAALgAECgEJAQAAAA==.Shocrates:BAAALgAECgIJBAABLgAECgUJBwALAAAAAA==.Shåtheed:BAAALgADCgYJBgAAAA==.',
Si='Sidthekid:BAABLgAECn8ZAAQiAAYJBBIdBgDSAAAiAAYJBBIdBgDSAAAjAAMJ2ROGGgB6AAAgAAEJVBbeGQBAAAAAAA==.Sinayion:BAABLgAECn8uAAIWAAkJnwSTJgDhAAAWAAkJnwSTJgDhAAAAAA==.',
Sl='Sluggina:BAAALgAECgIJAwAAAA==.',
So='Sonamis:BAAALgADCgYJBwAAAA==.Sorrôw:BAAALgAECgEJAQAAAA==.',
Sp='Sparkleshout:BAAALgADCgkJCQAAAA==.',
St='Stepbro:BAAALgAFFAEJAQABLgAECggJGwAOABIbAA==.Stepdemonh:BAAALgADCgkJEwAAAA==.Stepmôm:BAAALgAECgEJAQABLgAECggJGwAOABIbAA==.Stepsis:BAAALgAFFAEJAQABLgAECggJGwAOABIbAA==.Stinkoman:BAAALgAECgQJBwABLgAECgQJCAALAAAAAA==.',
Su='Sunarena:BAABLgAECn8fAAIKAAkJJg8QiwBbAQAKAAkJJg8QiwBbAQAAAA==.',
Ta='Tankobell:BAABLgAECn8bAAIKAAkJBhHjWQC/AQAKAAkJBhHjWQC/AQAAAA==.Tavius:BAAALgADCgEJAQAAAA==.',
Te='Terrible:BAEALgAECgcJAgABLgAFFAgJHQAHACUZAA==.',
Th='Thaldos:BAAALgAECgEJAgABLgAECgUJBwALAAAAAA==.Thannatos:BAAALgAECgEJAQAAAA==.Thejuiciest:BAAALgADCgEJAgAAAA==.',
To='Tommet:BAAALgADCgUJBQAAAA==.Toukadh:BAAALgAECgYJAgAAAA==.',
Tr='Truart:BAAALgAFFAIJBAAAAA==.',
Tu='Tuerjoie:BAABLgAECn8mAAIBAAgJQhgNUgDmAQABAAgJQhgNUgDmAQAAAA==.',
Tw='Twíla:BAAALgADCgYJCwAAAA==.',
Ty='Tywin:BAAALgAECgMJAwAAAA==.',
Ug='Ugooboom:BAAALgAECgEJAQAAAA==.',
Uh='Uh:BAAALgADCgYJDAAAAA==.',
Un='Unclemagic:BAAALgAECgYJDAABLgAFFAcJDQAQAJALAA==.',
Ut='Utopia:BAAALgAECgQJAwAAAA==.',
Va='Valesko:BAAALgAFFAEJAQAAAA==.Varfus:BAACLgAFFH85AAMbAAkJjyExAADnAgAbAAkJjyExAADnAgAVAAMJCSCbIQAJAQAuAAQKfzMAAhsACQlKJnIAAFwDABsACQlKJnIAAFwDAAAA.',
Ve='Velentre:BAAALgAECgkJEQAAAA==.',
Vi='Vichy:BAAALgAECgYJCQAAAA==.Vikstyn:BAAALgAECgEJBAAAAA==.',
Vu='Vulquin:BAAALgAECgUJBQAAAA==.',
We='Weather:BAAALgAECgYJCAAAAA==.',
Wi='Wigskid:BAAALgADCgEJAQAAAA==.Winney:BAACLgAFFH8GAAIKAAUJSxXKXwDwAAAKAAUJSxXKXwDwAAAuAAQKfysAAgoACQnbJFUGAD4DAAoACQnbJFUGAD4DAAAA.',
Wo='Wolfjob:BAAALgADCgUJBQAAAA==.Wouka:BAABLgAECn80AAQQAAkJuyUJBABQAwAQAAkJqSUJBABQAwAMAAYJqiPVAwBQAgAPAAIJsiPlKwBnAAAAAA==.',
Wr='Wrequiem:BAABLgAECn8hAAIUAAgJVQ63BAA2AQAUAAgJVQ63BAA2AQAAAA==.',
Wu='Wukong:BAAALgADCgMJAwAAAA==.',
Xh='Xhiaky:BAAALgAECgEJAQAAAA==.',
Ya='Yarlyah:BAAALgADCgkJDgABLgAECgUJBwALAAAAAA==.',
Yo='Yonnyy:BAAALgAECgYJCAAAAA==.Yoyomba:BAAALgAECgUJBQABLgAECggJMAAZAPQdAA==.',
Za='Zargonia:BAAALgAECgEJAQAAAA==.Zaria:BAAALgADCgUJBQABLgAFFAMJCAADAGkSAA==.',
Ze='Zendetra:BAAALgADCgUJBQABLgAECgYJEQALAAAAAA==.Zeposo:BAACLgAFFH8IAAIOAAUJ+A5VDwC4AAAOAAUJ+A5VDwC4AAAuAAQKfzoAAw4ACQlGIEkBAN0CAA4ACQlGIEkBAN0CABgAAgkJCNEsACUAAAAA.Zeptide:BAABLgAECn90AAMGAAkJDyGaAgC2AgAGAAkJDyGaAgC2AgAaAAkJ/Bf0AwD7AQABLgAFFAUJCAAOAPgOAA==.Zervish:BAAALgAECgEJAQAAAA==.',
Zo='Zoli:BAABLgAECn8YAAISAAgJ2R8mCwBtAgASAAgJ2R8mCwBtAgAAAA==.',
Zr='Zrichfu:BAAALgADCgIJAgABLgAFFAMJBwAQAFUGAA==.',
Zu='Zugnuts:BAAALgAECgcJBwAAAA==.',
['Zë']='Zëp:BAABLgAECn8cAAMfAAcJ3xfMAwD1AQAfAAcJ3xfMAwD1AQAKAAQJbAnXNwB3AAABLgAFFAUJCAAOAPgOAA==.',
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
