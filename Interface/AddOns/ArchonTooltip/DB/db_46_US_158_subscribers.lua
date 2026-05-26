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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Mage-Frost','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Druid-Guardian','DemonHunter-Vengeance','Rogue-Outlaw','Monk-Brewmaster','DeathKnight-Unholy','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Blood','Druid-Restoration','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Warrior-Arms','Paladin-Retribution','Paladin-Holy','Paladin-Protection','Druid-Balance','DemonHunter-Havoc',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=46,date='2026-05-25',data={Ad='Advvy:BAEALgAECgUJEQAAAA==.',
Ag='Ageregressor:BAEALgAECgcJBwAAAA==.',
Ai='Aihime:BAEALgADCgYJBgABLgAECgEJAQABAAAAAA==.',
Al='Alcean:BAEBLgAECn84AAICAAkJgCLvBAACAwloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAEAFoAbwwAAAMAXQACAAkJgCLvBAACAwloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAEAFoAbwwAAAMAXQAAAA==.Algebra:BAECLgAFFH8VAAIDAAUJ6SQSHwCtAQVoDAAABgBbAGkMAAAFAGEAawwAAAQAYwBqDAAAAgBaAOoMAAAEAFkAAwAFCekkEh8ArQEFaAwAAAYAWwBpDAAABQBhAGsMAAAEAGMAagwAAAIAWgDqDAAABABZAC4ABAp/HQACAwAJCaEkogcAMAMAAwAJCaEkogcAMAMAAAA=.Aléyna:BAEALgAECgEJAgAAAA==.',
Ar='Araakki:BAEALgAECgcJDwAAAA==.Arteron:BAEALgAFFAIJAwABLgAFFAcJDgAEAOodAA==.',
Ay='Ayoade:BAECLgAFFH8ZAAIFAAUJ+RQ1DwBzAQVoDAAABgAzAGkMAAAGAD0AawwAAAYATgBqDAAAAQAfAOoMAAAGAC0ABQAFCfkUNQ8AcwEFaAwAAAYAMwBpDAAABgA9AGsMAAAGAE4AagwAAAEAHwDqDAAABgAtAC4ABAp/GAADBQAICWkcnQoAjAIABQAICWkcnQoAjAIABgACCREV4zEAhwAAAS4ABRQICSoABwB9IAA=.',
Az='Azzurel:BAEBLgAECn8XAAMIAAgJMBFJbABSAQhoDAAABAAxAGkMAAAEACkAawwAAAMAOABqDAAAAwAwAGwMAAADADwAbQwAAAIAEADqDAAAAwAwAG4MAAABACMACAAICTARSWwAUgEIaAwAAAQAMQBpDAAABAApAGsMAAADADgAagwAAAIAMABsDAAAAwA8AG0MAAACABAA6gwAAAMAMABuDAAAAQAjAAkAAQkAAD5yADMAAWoMAAABABQAAAA=.',
Ba='Bareskin:BAEBLgAFFH8FAAIKAAUJawr7DwDGAAVoDAAAAQAyAGkMAAABAAkAawwAAAEAGwBqDAAAAQAiAOoMAAABABMACgAFCWsK+w8AxgAFaAwAAAEAMgBpDAAAAQAJAGsMAAABABsAagwAAAEAIgDqDAAAAQATAAEuAAUUBQkRAAsAIBUA.',
Bl='Bloodroyal:BAEALgADCgcJBwABLgAFFAMJCgAMALMWAA==.',
Bo='Bobbysan:BAECLgAFFH8fAAINAAgJnhg8AwAnAghoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACgAbQwAAAEAGwDqDAAACABWAG4MAAABADgADQAICZ4YPAMAJwIIaAwAAAYAUABpDAAABQBMAGsMAAAEAEkAagwAAAQAQABsDAAAAgAoAG0MAAABABsA6gwAAAgAVgBuDAAAAQA4AC4ABAp/LAACDQAJCWMgmAoA4AIADQAJCWMgmAoA4AIAAAA=.Bonemommyxo:BAECLgAFFH8TAAIOAAYJqCJFDwD5AQZoDAAABABbAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAOAAYJqCJFDwD5AQZoDAAABABbAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAuAAQKfysAAg4ACQmQJRwCALsDAA4ACQmQJRwCALsDAAAA.',
Br='Brigbala:BAEALgAECgMJBgAAAA==.',
Cr='Crustome:BAEALgAECgYJEgAAAA==.Crustorc:BAEALgAECgcJDgABLgAECgYJEgABAAAAAA==.',
Cu='Cubed:BAEALgAFFAEJAQABLgAFFAUJFQADAOkkAA==.',
De='Deathhunterz:BAEALgAECgYJDQAAAA==.Demagogué:BAECLgAFFH8KAAMPAAYJfhOgJwDRAAZoDAAAAQA9AGsMAAABAAkAagwAAAEAJQBsDAAAAgBgAG0MAAABACcA6gwAAAQAKgAPAAQJ5gugJwDRAARrDAAAAQAJAGoMAAABACUAbQwAAAEAJwDqDAAABAAqAAcAAglvD8JMAIkAAmgMAAABABwAbAwAAAIAMgAuAAQKfyEAAw8ACAnvI8wIALMCAA8ACAnvI8wIALMCAAcABwnaGRo3AKoBAAEuAAUUCAkWAAUARQ0A.Demonipryde:BAEALgAECgMJAwAAAA==.',
Dr='Dreamspun:BAECLgAFFH8KAAIMAAMJsxbFCACpAANoDAAABABGAGkMAAABABkA6gwAAAUATwAMAAMJsxbFCACpAANoDAAABABGAGkMAAABABkA6gwAAAUATwAuAAQKfy4AAgwACQmTISABAOUCAAwACQmTISABAOUCAAAA.Drunkenqrow:BAEALgAECgYJDQABLgAECggJEAABAAAAAA==.',
Du='Dubsii:BAECLgAFFH8PAAIQAAYJUiDIBgA7AgZoDAAAAwBTAGkMAAADAGAAawwAAAQAXABqDAAAAQBUAGwMAAACAC4A6gwAAAIAXQAQAAYJUiDIBgA7AgZoDAAAAwBTAGkMAAADAGAAawwAAAQAXABqDAAAAQBUAGwMAAACAC4A6gwAAAIAXQAuAAQKfxcAAxAACAmLIZwGAPMCABAACAmLIZwGAPMCABEAAQl/JrJgAG0AAAEuAAUUCAkqAAcAfSAA.Dubsy:BAECLgAFFH8qAAIHAAgJfSB/AAA2AghoDAAACQBQAGkMAAAJAF8AawwAAAYAWwBqDAAABwBjAGwMAAABAEMAbQwAAAEALADqDAAACABWAG4MAAABAGQABwAICX0gfwAANgIIaAwAAAkAUABpDAAACQBfAGsMAAAGAFsAagwAAAcAYwBsDAAAAQBDAG0MAAABACwA6gwAAAgAVgBuDAAAAQBkAC4ABAp/MgADBwAJCdAllgAAtAMABwAJCdAllgAAtAMADwADCfQiizwAGQEAAAA=.',
Eh='Ehanee:BAEALgAFFAIJAwAAAA==.',
Er='Ereshin:BAEALgAECggJDwAAAA==.',
Ev='Evieari:BAECLgAFFH8WAAMSAAYJ8xdwBwCgAQZoDAAABABAAGkMAAAEACYAawwAAAQALwBqDAAABAAlAGwMAAABAGAA6gwAAAUAUgASAAUJZBlwBwCgAQVoDAAAAgBAAGkMAAABACYAawwAAAEAKgBsDAAAAQBgAOoMAAADAFIAEwAFCVAMARcAaAEFaAwAAAIAJQBpDAAAAwAYAGsMAAADAC8AagwAAAQAJQDqDAAAAgAKAC4ABAp/GQADEwAJCdYayxgA5QEAEwAGCaYcyxgA5QEAEgAHCbkZmCkApQEAAS4ABRQDCQUAEgBKHwA=.Evielyssa:BAEALgAFFAQJBAABLgAFFAMJBQASAEofAA==.Evierari:BAEBLgAFFH8FAAMSAAIJSh9nHgCgAAJoDAAAAwBQAGkMAAACAE8AEgACCUofZx4AoAACaAwAAAIAUABpDAAAAgBPABQAAQkgAb8XADwAAWgMAAABAAIAAAA=.',
Fa='Fappimeal:BAECLgAFFH8gAAMOAAUJkiTPCgB8AQVoDAAACABiAGkMAAAIAGEAawwAAAYATgBqDAAAAwA3AOoMAAAHAGMADgAFCZIkzwoAfAEFaAwAAAYAYgBpDAAABgBhAGsMAAAEAE4AagwAAAEANwDqDAAABQBjABUABQl3Fu4GAEUBBWgMAAACAC0AaQwAAAIAPABrDAAAAgA9AGoMAAACACQA6gwAAAIAPgAuAAQKfz8AAw4ACQkwJncCALQDAA4ACQkwJncCALQDABUABgmnHHcJALABAAAA.',
Fe='Felshins:BAEALgADCgMJAwABLgAECggJDwABAAAAAA==.',
Fo='Fofer:BAEBLgAECn8nAAINAAcJASYHCACaAgdoDAAACABjAGkMAAAIAGIAawwAAAgAYwBqDAAABQBjAGwMAAAFAGMAbQwAAAEAWQDqDAAABABgAA0ABwkBJgcIAJoCB2gMAAAIAGMAaQwAAAgAYgBrDAAACABjAGoMAAAFAGMAbAwAAAUAYwBtDAAAAQBZAOoMAAAEAGAAAS4ABRQICR8AFgBCHwA=.Foil:BAEALgADCgkJEgABLgAECgkJRAAXAFMlAA==.',
Fr='Froshin:BAEALgADCgUJCwABLgAECggJDwABAAAAAA==.',
Fu='Funkey:BAECLgAFFH8RAAMLAAUJIBWeAgCjAAVoDAAABQBDAGkMAAAFAFoAawwAAAIAFABqDAAAAQAWAOoMAAAEACYAGAAFCZkOyD4ABgEFaAwAAAMAIQBpDAAABAA4AGsMAAACABQAagwAAAEAFgDqDAAABAAmAAsAAgm2Hp4CAKMAAmgMAAACAEMAaQwAAAEAWgAuAAQKfycAAwsACQmfIMQBAPwCAAsACAmzIsQBAPwCABgABgl+FtlHAJEBAAAA.',
Gr='Greathades:BAEALgAECgkJAgABLgAECgkJBAABAAAAAA==.Greatmonkey:BAEALgAECgcJBgABLgAECgkJBAABAAAAAA==.Greatodin:BAEALgAECgkJBAAAAA==.Greatosiris:BAEALgAECgkJAgABLgAECgkJBAABAAAAAA==.Greatra:BAEALgADCgEJAQABLgAECgkJBAABAAAAAA==.Grummel:BAECLgAFFH8LAAIZAAMJACK5GQAgAQNoDAAABgBbAGkMAAACAE8A6gwAAAMAWgAZAAMJACK5GQAgAQNoDAAABgBbAGkMAAACAE8A6gwAAAMAWgAuAAQKfycAAxkACQk8IH8JAPkCABkACQk8IH8JAPkCABoAAQlwFGwdAEAAAAAA.',
Hb='Hbcarter:BAEBLgAFFH8HAAIXAAMJSxRRLQDmAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgAXAAMJSxRRLQDmAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgABLgAFFAgJKgAHAH0gAA==.',
Ia='Iambuns:BAEALgADCgcJBwABLgAFFAUJIAAOAJIkAA==.',
Il='Illiyania:BAEALgAECgEJAQAAAA==.Ilnarya:BAEALgAECgEJAQABLgAECgkJHgAYALIRAA==.',
Im='Imquitelarge:BAEBLgAECn8VAAIbAAkJWhZqCwAOAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAbAAkJWhZqCwAOAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAAAA==.',
Iz='Izapotato:BAECLgAFFH8TAAIYAAUJMxgjCQCXAQVoDAAABABUAGkMAAAEACoAawwAAAQANABqDAAAAwBDAOoMAAAEAEQAGAAFCTMYIwkAlwEFaAwAAAQAVABpDAAABAAqAGsMAAAEADQAagwAAAMAQwDqDAAABABEAC4ABAp/IgACGAAHCaElCxsAWQIAGAAHCaElCxsAWQIAAS4ABRQICRYABQBFDQA=.',
Ke='Kelandrea:BAECLgAFFH8HAAIcAAIJ3gskcwCPAAJoDAAAAwAWAOoMAAAEACYAHAACCd4LJHMAjwACaAwAAAMAFgDqDAAABAAmAC4ABAp/HAAEHAAJCaEa2CIAngIAHAAJCaEa2CIAngIAHQACCdIQ94EAcAAAHgACCTMXsT8AQAAAAAA=.',
Ki='Kirkh:BAEALgAECgcJDAABLgAECgkJJgAUAEobAA==.Kirkpriest:BAEBLgAECn8mAAIUAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAUAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAAAA==.Kitowatt:BAEALgAECgYJCgABLgAECgcJHAAfAGIdAA==.',
Kr='Kregazi:BAECLgAFFH8JAAIWAAQJYhhjEQApAQRoDAAAAwA7AGkMAAADAEMAawwAAAEAXADqDAAAAgAdABYABAliGGMRACkBBGgMAAADADsAaQwAAAMAQwBrDAAAAQBcAOoMAAACAB0ALgAECn8uAAIWAAkJlCJkBADSAgAWAAkJlCJkBADSAgAAAA==.',
Ky='Kyriste:BAEBLgAECn8aAAISAAcJZiHnCwCFAgdoDAAABQBbAGkMAAAFAFoAawwAAAQAWABqDAAAAwBVAGwMAAADAEAA6gwAAAQAWwBuDAAAAgBXABIABwlmIecLAIUCB2gMAAAFAFsAaQwAAAUAWgBrDAAABABYAGoMAAADAFUAbAwAAAMAQADqDAAABABbAG4MAAACAFcAAS4ABRQFCRgAGQBgIQA=.',
La='Larissaqt:BAECLgAFFH8cAAIUAAYJ0xJlCQCTAQZoDAAABgBKAGkMAAAFADoAawwAAAYAHQBqDAAABQAgAGwMAAACADEA6gwAAAQAGwAUAAYJ0xJlCQCTAQZoDAAABgBKAGkMAAAFADoAawwAAAYAHQBqDAAABQAgAGwMAAACADEA6gwAAAQAGwAuAAQKfykAAhQACQneIR8DACEDABQACQneIR8DACEDAAAA.',
Li='Lioshi:BAEALgAECgYJCQABLgAFFAQJEAADAJ4aAA==.',
Ma='Maildaddy:BAECLgAFFH8WAAIFAAgJRQ3oBQAgAghoDAAABAAwAGkMAAAEAEMAawwAAAQALQBqDAAAAgAmAGwMAAABAAoAbQwAAAEACADqDAAABQAxAG4MAAABAAQABQAICUUN6AUAIAIIaAwAAAQAMABpDAAABABDAGsMAAAEAC0AagwAAAIAJgBsDAAAAQAKAG0MAAABAAgA6gwAAAUAMQBuDAAAAQAEAC4ABAp/JAAEBQAICYkctwgARQIABQAHCSUgtwgARQIAAgAFCSgRKjcAGwEABgADCRwc3ycA4gAAAAA=.Maxxy:BAEBLgAECn8cAAIXAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAXAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAAAA==.',
Mc='Mckellen:BAECLgAFFH8HAAMSAAQJ+A3DFAD3AARoDAAAAgAwAGkMAAACADYAawwAAAEAEwDqDAAAAgAUABIABAldDcMUAPcABGgMAAACADAAaQwAAAEANgBrDAAAAQATAOoMAAABAA0AEwACCREJAhQAlgACaQwAAAEAGgDqDAAAAQAUAC4ABAp/HQADEwAICc4ZmQwAbgIAEwAICc4ZmQwAbgIAEgAECSYMg1wAwQAAAS4ABRQICSoABwB9IAA=.',
Me='Medranden:BAEALgADCgcJBwABLgAECgYJDQABAAAAAA==.Merarite:BAEALgAECgcJBwABLgAECgkJNgANADYQAA==.',
Mi='Militee:BAEALgADCgMJBAAAAA==.',
Mo='Mordraius:BAEALgAECggJEQABLgAFFAQJEAADAJ4aAA==.',
My='Myceliums:BAEALgAECgUJDgAAAA==.',
Na='Nadasa:BAECLgAFFH8SAAIcAAUJ6BOSLgAxAQVoDAAABQAzAGkMAAAEAD4AawwAAAMAOgBqDAAAAgAxAOoMAAAEAB8AHAAFCegTki4AMQEFaAwAAAUAMwBpDAAABAA+AGsMAAADADoAagwAAAIAMQDqDAAABAAfAC4ABAp/PwACHAAJCVUhkhEAxQIAHAAJCVUhkhEAxQIAAAA=.Naramonria:BAEALgADCgcJCAAAAA==.',
Nh='Nhylia:BAEALgAECgkJAgABLgAFFAIJBwAcAN4LAA==.',
Ni='Nixaanu:BAEALgAECgEJAQABLgAECggJFAAPAH8aAA==.Nixei:BAEBLgAECn8UAAIPAAgJfxpEGABTAghoDAAAAgAyAGkMAAACAEIAawwAAAIATwBqDAAAAgA3AGwMAAAEAFAAbQwAAAMARwDqDAAAAgA3AG4MAAADAEYADwAICX8aRBgAUwIIaAwAAAIAMgBpDAAAAgBCAGsMAAACAE8AagwAAAIANwBsDAAABABQAG0MAAADAEcA6gwAAAIANwBuDAAAAwBGAAAA.',
Ny='Nyriaa:BAEBLgAECn8eAAISAAkJvSN0AwBCAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwASAAkJvSN0AwBCAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwAAAA==.',
['Ní']='Nítedragon:BAEALgADCggJAwABLgAECgcJEwABAAAAAA==.',
Pa='Palashin:BAEALgAECgUJCQABLgAECggJDwABAAAAAA==.',
Pe='Personnelkid:BAEALgAECgYJBwABLgAECgkJPAASAIMZAA==.',
Ph='Pheiro:BAEBLgAECn8cAAIDAAgJcQ1wiADBAQhoDAAABQBSAGkMAAAFAC0AawwAAAQAJQBqDAAAAgAXAGwMAAACABAAbQwAAAQADwDqDAAABQAmAG4MAAABAAUAAwAICXENcIgAwQEIaAwAAAUAUgBpDAAABQAtAGsMAAAEACUAagwAAAIAFwBsDAAAAgAQAG0MAAAEAA8A6gwAAAUAJgBuDAAAAQAFAAAA.',
Pl='Platedaddy:BAEALgAECgYJBgABLgAFFAgJFgAFAEUNAA==.',
Pu='Punchweagle:BAEBLgAECn82AAMNAAkJNhBqHQCfAQloDAAACAAzAGkMAAAHAEAAawwAAAgAOgBqDAAABgAoAGwMAAAGADkAbQwAAAUAEQDqDAAABgAwAG4MAAAFAA0AbwwAAAMAEwANAAkJ8Q5qHQCfAQloDAAABAAzAGkMAAAEADQAawwAAAQAMwBqDAAABAAZAGwMAAAEADkAbQwAAAUAEQDqDAAABAAqAG4MAAAFAA0AbwwAAAMAEwARAAYJUxRGMgBbAQZoDAAABAAyAGkMAAADAEAAawwAAAQAOgBqDAAAAgAoAGwMAAACACUA6gwAAAIAMAAAAA==.',
Qr='Qrowdrake:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.Qrowfather:BAEALgAECggJEAAAAA==.Qrowsunny:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.',
Ra='Raveglaive:BAEALgAECgUJAwAAAA==.',
Re='Redvine:BAEALgADCgUJBQABLgAFFAUJEQALACAVAA==.Rexpanda:BAEALgAECgQJBgABLgAECgUJBQABAAAAAA==.Rextank:BAEALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ro='Roogies:BAECLgAFFH8YAAIZAAUJYCExDQBzAQVoDAAACABcAGkMAAAIAFUAawwAAAQARABqDAAAAQBdAOoMAAADAF4AGQAFCWAhMQ0AcwEFaAwAAAgAXABpDAAACABVAGsMAAAEAEQAagwAAAEAXQDqDAAAAwBeAC4ABAp/PwADGQAJCYgl6gMA6gIAGQAJCVkl6gMA6gIAGgACCZ0YIRUAqAAAAAA=.',
Ru='Rumpy:BAEALgAFFAIJBAABLgAFFAMJCwAZAAAiAA==.',
['Ræ']='Ræx:BAEALgAECgUJBQAAAA==.',
Sh='Shiins:BAEALgAECgIJAwABLgAECggJDwABAAAAAA==.Shinthyr:BAEBLgAECn8VAAISAAcJ5R4eFQA0AgdoDAAABABTAGkMAAADAFUAawwAAAMAXQBqDAAAAwBHAGwMAAACAFUA6gwAAAQASwBuDAAAAgA6ABIABwnlHh4VADQCB2gMAAAEAFMAaQwAAAMAVQBrDAAAAwBdAGoMAAADAEcAbAwAAAIAVQDqDAAABABLAG4MAAACADoAAS4ABAoICQ8AAQAAAAA=.',
Si='Sizzlefox:BAEALgAECgEJAQABLgAECgcJDwABAAAAAA==.',
St='Stygianfox:BAEALgAECgEJAgABLgAECgcJDwABAAAAAA==.',
Ta='Tahune:BAEBLgAECn9EAAMXAAkJUyUFAQDJAwloDAAACgBdAGkMAAAJAGIAawwAAAkAYQBqDAAACQBfAGwMAAAIAGEAbQwAAAYAXwDqDAAACQBhAG4MAAAFAFoAbwwAAAMAXQAXAAkJUyUFAQDJAwloDAAACABdAGkMAAAJAGIAawwAAAcAYQBqDAAACQBfAGwMAAAIAGEAbQwAAAYAXwDqDAAACQBhAG4MAAAFAFoAbwwAAAMAXQAfAAIJhiF0UwCXAAJoDAAAAgBWAGsMAAACAFUAAAA=.Taso:BAEBLgAECn8dAAINAAgJVhE0KQBPAQhoDAAABgA/AGkMAAAFAEMAawwAAAUASgBqDAAABQBPAGwMAAABAAAAbQwAAAEAAADqDAAABQBBAG4MAAABACYADQAICVYRNCkATwEIaAwAAAYAPwBpDAAABQBDAGsMAAAFAEoAagwAAAUATwBsDAAAAQAAAG0MAAABAAAA6gwAAAUAQQBuDAAAAQAmAAEuAAUUBQkVABYAxiAA.',
Th='Therapygap:BAEBLgAECn8oAAQSAAgJgBK0IwCIAQhoDAAABwBMAGkMAAAIADwAawwAAAQANwBqDAAABQAdAGwMAAAIADQAbQwAAAEAIwDqDAAABgA8AG4MAAABAAgAEgAHCaYUtCMAiAEHaAwAAAQATABpDAAABAA8AGsMAAADADcAagwAAAQAHQBsDAAABgA0AG0MAAABACMA6gwAAAUAPAAUAAYJKwoUTwCqAAZoDAAAAwAnAGkMAAAEABUAawwAAAEAEgBqDAAAAQAHAGwMAAACACkA6gwAAAEACAATAAEJfANycQAhAAFuDAAAAQAIAAEuAAQKCQk8ABIAgxkA.',
Tr='Triboon:BAEALgADCgMJAwABLgAFFAcJEwAQAHYbAA==.Trèantdaddy:BAEALgAFFAEJAgABLgAFFAgJFgAFAEUNAA==.',
Tw='Twomonk:BAEALgAECgIJAwABLgAFFAIJBgARAL4hAA==.',
Un='Unsown:BAEALgAECgUJBQABLgAFFAMJCgAMALMWAA==.',
Us='Usurah:BAECLgAFFH8YAAIcAAYJDBnNEwCJAQZoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAACABsA6gwAAAQAPgAcAAYJDBnNEwCJAQZoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAACABsA6gwAAAQAPgAuAAQKfysAAxwACQmAIsQJAEMDABwACQmAIsQJAEMDAB4ABQlYHIwXADsBAAAA.',
Vi='Vindh:BAECLgAFFH8PAAMYAAUJugflRQDuAAVoDAAABQAXAGkMAAADABUAawwAAAIACABqDAAAAQAJAOoMAAAEABgAGAAFCboH5UUA7gAFaAwAAAUAFwBpDAAAAwAVAGsMAAACAAgAagwAAAEACQDqDAAAAwAYAAsAAQkOBrMOACsAAeoMAAABAA8ALgAECn8oAAQYAAkJtxVdPQD/AQAYAAkJtxVdPQD/AQALAAIJOgOeKQA9AAAgAAEJAADUbQAAAAAAAA==.',
Vy='Vyndraennis:BAEBLgAECn8eAAIYAAkJshH2OQDCAQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAYAAkJshH2OQDCAQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAAAA==.',
Ya='Yaav:BAEBLgAECn8XAAIOAAkJxhBjSwDDAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAOAAkJxhBjSwDDAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAAAA==.',
Yu='Yufia:BAEBLgAECn8ZAAIIAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAIAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAAAA==.',
Za='Zatum:BAEBLgAECn8cAAIfAAcJYh2UGADiAQdoDAAABQBKAGkMAAAFAFYAawwAAAQAUABqDAAAAwA7AGwMAAAFAFMA6gwAAAUAVABuDAAAAQAqAB8ABwliHZQYAOIBB2gMAAAFAEoAaQwAAAUAVgBrDAAABABQAGoMAAADADsAbAwAAAUAUwDqDAAABQBUAG4MAAABACoAAAA=.',
Zh='Zhuröng:BAECLgAFFH8QAAIDAAQJnhoYRABCAQRoDAAABQBJAGkMAAAFAE4AawwAAAMAKgDqDAAAAwBPAAMABAmeGhhEAEIBBGgMAAAFAEkAaQwAAAUATgBrDAAAAwAqAOoMAAADAE8ALgAECn8mAAIDAAkJlx/KTQBNAgADAAkJlx/KTQBNAgAAAA==.',
Zo='Zomb:BAECLgAFFH8VAAIWAAUJxiCwCwBuAQVoDAAABwBbAGkMAAAGAEQAawwAAAMAXQBqDAAAAQBMAOoMAAAEAFIAFgAFCcYgsAsAbgEFaAwAAAcAWwBpDAAABgBEAGsMAAADAF0AagwAAAEATADqDAAABABSAC4ABAp/JQACFgAICY4haQQABQMAFgAICY4haQQABQMAAAA=.',
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
