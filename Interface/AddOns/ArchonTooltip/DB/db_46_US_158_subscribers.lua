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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Mage-Fire','Mage-Frost','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Druid-Guardian','DemonHunter-Vengeance','Rogue-Outlaw','Monk-Brewmaster','DeathKnight-Unholy','Paladin-Holy','Rogue-Subtlety','Warrior-Fury','DemonHunter-Devourer','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Blood','Druid-Restoration','Rogue-Assassination','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Druid-Balance','DemonHunter-Havoc',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=46,date='2026-05-31',data={Ad='Advvy:BAEALgAECgUJEgAAAA==.',
Ag='Ageregressor:BAEALgAECgcJBwAAAA==.',
Ai='Aihime:BAEALgADCgYJBgABLgAECgEJAQABAAAAAA==.',
Al='Alcean:BAEBLgAECn86AAICAAkJgCJTBQD2AgloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAFAFoAbwwAAAQAXQACAAkJgCJTBQD2AgloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAFAFoAbwwAAAQAXQAAAA==.Algebra:BAECLgAFFH8bAAMDAAYJwiRlAACzAQZoDAAABwBfAGkMAAAGAGEAawwAAAUAYwBqDAAAAwBaAGwMAAABAFkA6gwAAAUAWQAEAAYJfiTGFAAKAgZoDAAABgBbAGkMAAAFAGEAawwAAAQAYwBqDAAAAgBaAGwMAAABAFkA6gwAAAQAWQADAAUJxSRlAACzAQVoDAAAAQBfAGkMAAABAF8AawwAAAEAYQBqDAAAAQBUAOoMAAABAFgALgAECn8dAAIEAAkJoSTRCAAiAwAEAAkJoSTRCAAiAwAAAA==.Aléyna:BAEALgAECgEJAgAAAA==.',
Ar='Araakki:BAEALgAECgcJDwAAAA==.Arteron:BAEALgAFFAIJAwABLgAFFAcJFAAFAGweAA==.',
Ay='Ayoade:BAECLgAFFH8dAAIGAAUJ+RSQEQBdAQVoDAAABwAzAGkMAAAHAD0AawwAAAcATgBqDAAAAQAfAOoMAAAHAC0ABgAFCfkUkBEAXQEFaAwAAAcAMwBpDAAABwA9AGsMAAAHAE4AagwAAAEAHwDqDAAABwAtAC4ABAp/GAADBgAICWkcnQoAjAIABgAICWkcnQoAjAIABwACCREV4zEAhwAAAS4ABRQICS8ACAB9IAA=.',
Az='Azzurel:BAEBLgAECn8XAAMJAAgJMBE+cwBKAQhoDAAABAAxAGkMAAAEACkAawwAAAMAOABqDAAAAwAwAGwMAAADADwAbQwAAAIAEADqDAAAAwAwAG4MAAABACMACQAICTARPnMASgEIaAwAAAQAMQBpDAAABAApAGsMAAADADgAagwAAAIAMABsDAAAAwA8AG0MAAACABAA6gwAAAMAMABuDAAAAQAjAAoAAQkAAD5yADMAAWoMAAABABQAAAA=.',
Ba='Bareskin:BAEBLgAFFH8FAAILAAUJawoZFAC/AAVoDAAAAQAyAGkMAAABAAkAawwAAAEAGwBqDAAAAQAiAOoMAAABABMACwAFCWsKGRQAvwAFaAwAAAEAMgBpDAAAAQAJAGsMAAABABsAagwAAAEAIgDqDAAAAQATAAEuAAUUBQkSAAwAIBUA.',
Bl='Bloodroyal:BAEALgADCgcJBwABLgAFFAMJDQANAEsdAA==.',
Bo='Bobbysan:BAECLgAFFH8fAAIOAAgJnhiPBAAdAghoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACgAbQwAAAEAGwDqDAAACABWAG4MAAABADgADgAICZ4YjwQAHQIIaAwAAAYAUABpDAAABQBMAGsMAAAEAEkAagwAAAQAQABsDAAAAgAoAG0MAAABABsA6gwAAAgAVgBuDAAAAQA4AC4ABAp/LwACDgAJCRgh0woAdwIADgAJCRgh0woAdwIAAAA=.Bonemommyxo:BAECLgAFFH8TAAIPAAYJqCKiFgDhAQZoDAAABABbAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAPAAYJqCKiFgDhAQZoDAAABABbAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAuAAQKfysAAg8ACQmQJRwCALsDAA8ACQmQJRwCALsDAAAA.',
Br='Brigbala:BAEALgAECgMJBgAAAA==.',
Bu='Buttlustplz:BAEALgAFFAEJAQABLgAFFAMJBgAQAI8fAA==.',
Ch='Chunghús:BAEALgAECgYJBgABLgAFFAgJGwAGAEUNAA==.',
Cr='Crustome:BAEBLgAECn8aAAIRAAgJ0QdnJQBQAQhoDAAABgATAGkMAAAGABMAawwAAAUAEABqDAAAAwAaAGwMAAACACQAbQwAAAEABgDqDAAAAgAJAG4MAAABAB8AEQAICdEHZyUAUAEIaAwAAAYAEwBpDAAABgATAGsMAAAFABAAagwAAAMAGgBsDAAAAgAkAG0MAAABAAYA6gwAAAIACQBuDAAAAQAfAAAA.Crustorc:BAEBLgAECn8XAAISAAkJigdgMwBqAQloDAAAAwAXAGkMAAADABYAawwAAAMADwBqDAAAAwAXAGwMAAADABwAbQwAAAEACQDqDAAABAAPAG4MAAACABEAbwwAAAEAFQASAAkJigdgMwBqAQloDAAAAwAXAGkMAAADABYAawwAAAMADwBqDAAAAwAXAGwMAAADABwAbQwAAAEACQDqDAAABAAPAG4MAAACABEAbwwAAAEAFQABLgAECggJGgARANEHAA==.',
Cu='Cubed:BAEALgAFFAEJAQABLgAFFAYJGwADAMIkAA==.',
De='Deathhunterz:BAEBLgAECn8UAAITAAYJWQXHsgCiAAZoDAAABAAPAGkMAAAEABIAawwAAAUACQBqDAAAAgAaAGwMAAACABEA6gwAAAMABgATAAYJWQXHsgCiAAZoDAAABAAPAGkMAAAEABIAawwAAAUACQBqDAAAAgAaAGwMAAACABEA6gwAAAMABgAAAA==.Demagogué:BAECLgAFFH8NAAMUAAcJFRVwEABzAQdoDAAAAgA9AGsMAAABAAkAagwAAAEAJQBsDAAAAgBgAG0MAAABACcA6gwAAAUAQQBuDAAAAQA0ABQABgnCEXAQAHMBBmgMAAABAD0AawwAAAEACQBqDAAAAQAlAG0MAAABACcA6gwAAAUAQQBuDAAAAQA0AAgAAglvD3BVAIQAAmgMAAABABwAbAwAAAIAMgAuAAQKfycAAxQACAn7IyEIAMkCABQACAn7IyEIAMkCAAgABwmRHIoxANQBAAEuAAUUCAkbAAYARQ0A.Demonipryde:BAEALgAECgMJAwAAAA==.',
Dr='Dreamspun:BAECLgAFFH8NAAINAAMJSx2PBgABAQNoDAAABQBGAGkMAAACAEoA6gwAAAYAUAANAAMJSx2PBgABAQNoDAAABQBGAGkMAAACAEoA6gwAAAYAUAAuAAQKfzQAAg0ACQmeIokAADEDAA0ACQmeIokAADEDAAAA.Drunkenqrow:BAEALgAECgYJDQABLgAECggJEAABAAAAAA==.',
Du='Dubsii:BAECLgAFFH8PAAIVAAYJUiDZCAArAgZoDAAAAwBTAGkMAAADAGAAawwAAAQAXABqDAAAAQBUAGwMAAACAC4A6gwAAAIAXQAVAAYJUiDZCAArAgZoDAAAAwBTAGkMAAADAGAAawwAAAQAXABqDAAAAQBUAGwMAAACAC4A6gwAAAIAXQAuAAQKfxcAAxUACAmLIZwGAPMCABUACAmLIZwGAPMCABYAAQl/JkdnAGwAAAEuAAUUCAkvAAgAfSAA.Dubsy:BAECLgAFFH8vAAIIAAgJfSB/AAA2AghoDAAACgBQAGkMAAAKAF8AawwAAAcAWwBqDAAACABjAGwMAAABAEMAbQwAAAEALADqDAAACQBWAG4MAAABAGQACAAICX0gfwAANgIIaAwAAAoAUABpDAAACgBfAGsMAAAHAFsAagwAAAgAYwBsDAAAAQBDAG0MAAABACwA6gwAAAkAVgBuDAAAAQBkAC4ABAp/MwADCAAJCdAllgAAtAMACAAJCdAllgAAtAMAFAAECbUjfioAhwEAAAA=.',
Eh='Ehanee:BAEALgAFFAIJAwAAAA==.',
Er='Ereshin:BAEBLgAECn8WAAIIAAgJWB9zCwDtAghoDAAABABiAGkMAAADAGAAawwAAAQAWQBqDAAAAwBKAGwMAAACAE8AbQwAAAEAEgDqDAAAAwBYAG4MAAACAGAACAAICVgfcwsA7QIIaAwAAAQAYgBpDAAAAwBgAGsMAAAEAFkAagwAAAMASgBsDAAAAgBPAG0MAAABABIA6gwAAAMAWABuDAAAAgBgAAAA.',
Ev='Evieari:BAECLgAFFH8WAAMXAAYJ8xcICQCQAQZoDAAABABAAGkMAAAEACYAawwAAAQALwBqDAAABAAlAGwMAAABAGAA6gwAAAUAUgAXAAUJZBkICQCQAQVoDAAAAgBAAGkMAAABACYAawwAAAEAKgBsDAAAAQBgAOoMAAADAFIAGAAFCVAMqxoAUQEFaAwAAAIAJQBpDAAAAwAYAGsMAAADAC8AagwAAAQAJQDqDAAAAgAKAC4ABAp/GQADGAAJCdYaxBkA4wEAGAAGCaYcxBkA4wEAFwAHCbkZmCkApQEAAS4ABRQGCQUAFwBKHwA=.Evielyssa:BAEALgAFFAQJBAABLgAFFAYJBQAXAEofAA==.Evierari:BAEBLgAFFH8FAAMXAAIJSh8aIACaAAJoDAAAAwBQAGkMAAACAE8AFwACCUofGiAAmgACaAwAAAIAUABpDAAAAgBPABkAAQkgAb8XADwAAWgMAAABAAIAAAA=.',
Fa='Fappimeal:BAECLgAFFH8mAAMPAAYJkyRkEAAKAgZoDAAACQBiAGkMAAAJAGEAawwAAAcAWgBqDAAABABVAGwMAAABAFEA6gwAAAgAYwAPAAYJkyRkEAAKAgZoDAAABwBiAGkMAAAHAGEAawwAAAUAWgBqDAAAAgBVAGwMAAABAFEA6gwAAAUAYwAaAAUJtBaVCAA9AQVoDAAAAgAtAGkMAAACADwAawwAAAIAPQBqDAAAAgAkAOoMAAADAEAALgAECn8/AAMPAAkJMCZ3AgC0AwAPAAkJMCZ3AgC0AwAaAAYJpxy5CgCmAQAAAA==.',
Fe='Felshins:BAEALgADCgMJBgABLgAECggJFgAIAFgfAA==.',
Fo='Fofer:BAEBLgAECn8nAAIOAAcJASawCACZAgdoDAAACABjAGkMAAAIAGIAawwAAAgAYwBqDAAABQBjAGwMAAAFAGMAbQwAAAEAWQDqDAAABABgAA4ABwkBJrAIAJkCB2gMAAAIAGMAaQwAAAgAYgBrDAAACABjAGoMAAAFAGMAbAwAAAUAYwBtDAAAAQBZAOoMAAAEAGAAAS4ABRQICR8AGwBCHwA=.Foil:BAEALgADCgkJGwABLgAECgkJTQAcAFslAA==.',
Fr='Froshin:BAEALgADCgUJCwABLgAECggJFgAIAFgfAA==.',
Fs='Fshi:BAEALgAECgYJAwAAAA==.',
Fu='Funkey:BAECLgAFFH8SAAMMAAUJIBWeAgCjAAVoDAAABQBDAGkMAAAFAFoAawwAAAIAFABqDAAAAgAWAOoMAAAEACYAEwAFCZkOOkYA/QAFaAwAAAMAIQBpDAAABAA4AGsMAAACABQAagwAAAIAFgDqDAAABAAmAAwAAgm2Hp4CAKMAAmgMAAACAEMAaQwAAAEAWgAuAAQKfycAAwwACQmfIMQBAPwCAAwACAmzIsQBAPwCABMABgl+Fi9MAIsBAAAA.',
Gr='Greatares:BAEALgAFFAMJAwAAAA==.Greathades:BAEALgAECgkJAgABLgAFFAMJAwABAAAAAA==.Greatmonkey:BAEALgAECgcJBgABLgAFFAMJAwABAAAAAA==.Greatodin:BAEALgAECgkJBAABLgAFFAMJAwABAAAAAA==.Greatosiris:BAEALgAECgkJAgABLgAFFAMJAwABAAAAAA==.Greatra:BAEALgADCgEJAQABLgAFFAMJAwABAAAAAA==.Grummel:BAECLgAFFH8NAAIRAAMJACI4HQATAQNoDAAABwBbAGkMAAACAE8A6gwAAAQAWgARAAMJACI4HQATAQNoDAAABwBbAGkMAAACAE8A6gwAAAQAWgAuAAQKfycAAxEACQk8IH8JAPkCABEACQk8IH8JAPkCAB0AAQlwFGwdAEAAAAAA.',
Hb='Hbcarter:BAEBLgAFFH8HAAIcAAMJSxQNMgDbAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgAcAAMJSxQNMgDbAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgABLgAFFAgJLwAIAH0gAA==.',
Hr='Hrtenjoyer:BAEBLgAECn8UAAIWAAgJJhpMEAAzAghoDAAABABfAGkMAAADAEgAawwAAAMATQBqDAAAAwASAGwMAAAEAE8A6gwAAAEANABuDAAAAQA+AG8MAAABAB0AFgAICSYaTBAAMwIIaAwAAAQAXwBpDAAAAwBIAGsMAAADAE0AagwAAAMAEgBsDAAABABPAOoMAAABADQAbgwAAAEAPgBvDAAAAQAdAAEuAAUUBAkIAA8AlBoA.',
Ia='Iambuns:BAEALgADCgcJBwABLgAFFAYJJgAPAJMkAA==.',
Il='Illiyania:BAEALgAECgEJAQAAAA==.Ilnarya:BAEALgAECgEJAQABLgAECgkJHgATALIRAA==.',
Im='Imquitelarge:BAEBLgAECn8VAAIeAAkJWhbBDAAHAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAeAAkJWhbBDAAHAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAAAA==.',
Iz='Izapotato:BAECLgAFFH8TAAITAAUJMxgjCQCXAQVoDAAABABUAGkMAAAEACoAawwAAAQANABqDAAAAwBDAOoMAAAEAEQAEwAFCTMYIwkAlwEFaAwAAAQAVABpDAAABAAqAGsMAAAEADQAagwAAAMAQwDqDAAABABEAC4ABAp/IgACEwAHCaElIx0AUwIAEwAHCaElIx0AUwIAAS4ABRQICRsABgBFDQA=.',
Ka='Katestinks:BAECLgAFFH8IAAIPAAQJlBoSOwBeAQRoDAAAAgBXAGkMAAACAFMAawwAAAEABADqDAAAAwBhAA8ABAmUGhI7AF4BBGgMAAACAFcAaQwAAAIAUwBrDAAAAQAEAOoMAAADAGEALgAECn8qAAMPAAkJ0CMJBQBLAwAPAAkJ0CMJBQBLAwAbAAEJtgrsVgAqAAAAAA==.',
Ke='Kelandrea:BAECLgAFFH8HAAIfAAIJ3gtgggCHAAJoDAAAAwAWAOoMAAAEACYAHwACCd4LYIIAhwACaAwAAAMAFgDqDAAABAAmAC4ABAp/HQAEHwAJCaEa2CIAngIAHwAJCaEa2CIAngIAEAACCdIQ94EAcAAAIAACCTMX00MAQAAAAS4ABRQDCQUAHwCKFAA=.',
Ki='Kirkh:BAEALgAECgcJDAABLgAECgkJJgAZAEobAA==.Kirkpriest:BAEBLgAECn8mAAIZAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAZAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAAAA==.Kitowatt:BAEALgAECgYJCgABLgAECggJHQAhAFcdAA==.',
Kr='Kregazi:BAECLgAFFH8MAAIbAAQJYhjYEwAkAQRoDAAABAA7AGkMAAAEAEMAawwAAAEAXADqDAAAAwAdABsABAliGNgTACQBBGgMAAAEADsAaQwAAAQAQwBrDAAAAQBcAOoMAAADAB0ALgAECn8wAAIbAAkJyCLLBADSAgAbAAkJyCLLBADSAgAAAA==.',
Ky='Kyriste:BAEBLgAECn8aAAIXAAcJZiEnDQB9AgdoDAAABQBbAGkMAAAFAFoAawwAAAQAWABqDAAAAwBVAGwMAAADAEAA6gwAAAQAWwBuDAAAAgBXABcABwlmIScNAH0CB2gMAAAFAFsAaQwAAAUAWgBrDAAABABYAGoMAAADAFUAbAwAAAMAQADqDAAABABbAG4MAAACAFcAAS4ABRQFCR0AEQD5IQA=.',
La='Larissaqt:BAECLgAFFH8hAAIZAAcJ0hF4BgDVAQdoDAAABwBTAGkMAAAGAEoAawwAAAcAHQBqDAAABgAgAGwMAAACADEA6gwAAAQAGwBuDAAAAQAIABkABwnSEXgGANUBB2gMAAAHAFMAaQwAAAYASgBrDAAABwAdAGoMAAAGACAAbAwAAAIAMQDqDAAABAAbAG4MAAABAAgALgAECn8pAAIZAAkJ3iGSAwASAwAZAAkJ3iGSAwASAwAAAA==.',
Li='Lioshi:BAEALgAECgYJCQABLgAFFAQJEAAEAJ4aAA==.',
Ma='Maildaddy:BAECLgAFFH8bAAIGAAgJRQ3QBwANAghoDAAABQAwAGkMAAAFAEMAawwAAAUALQBqDAAAAwAmAGwMAAABAAoAbQwAAAEACADqDAAABgAxAG4MAAABAAQABgAICUUN0AcADQIIaAwAAAUAMABpDAAABQBDAGsMAAAFAC0AagwAAAMAJgBsDAAAAQAKAG0MAAABAAgA6gwAAAYAMQBuDAAAAQAEAC4ABAp/JAAEBgAICYkcQAkARQIABgAHCSUgQAkARQIAAgAFCSgRKjcAGwEABwADCRwc3ycA4gAAAAA=.Maxxy:BAEBLgAECn8cAAIcAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAcAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAAAA==.',
Mc='Mckellen:BAECLgAFFH8LAAMXAAQJqBrADgA/AQRoDAAAAwBFAGkMAAADADgAawwAAAIAPADqDAAAAwBWABcABAmoGsAOAD8BBGgMAAADAEUAaQwAAAIAOABrDAAAAgA8AOoMAAACAFYAGAACCREJAhQAlgACaQwAAAEAGgDqDAAAAQAUAC4ABAp/HQADGAAICc4ZmQwAbgIAGAAICc4ZmQwAbgIAFwAECSYMg1wAwQAAAS4ABRQICS8ACAB9IAA=.',
Me='Medranden:BAEALgADCgcJBwABLgAECgYJFAATAFkFAA==.Merarite:BAEALgAECgkJEAABLgAECgkJNgAOADYQAA==.',
Mi='Militee:BAEALgADCgMJBAAAAA==.',
Mo='Mordraius:BAEALgAECggJEQABLgAFFAQJEAAEAJ4aAA==.',
My='Myceliums:BAEALgAECgUJDgAAAA==.',
Na='Nadasa:BAECLgAFFH8XAAIfAAUJ6BO7NgAoAQVoDAAABgAzAGkMAAAFAD4AawwAAAQAOgBqDAAAAwAxAOoMAAAFAB8AHwAFCegTuzYAKAEFaAwAAAYAMwBpDAAABQA+AGsMAAAEADoAagwAAAMAMQDqDAAABQAfAC4ABAp/RAACHwAJCZMhcRIAwQIAHwAJCZMhcRIAwQIAAAA=.Naramonria:BAEALgADCgcJCAAAAA==.',
Nh='Nhylia:BAEBLgAFFH8FAAIfAAMJihR1TwDzAANoDAAAAgAtAGkMAAABAB4A6gwAAAIAUQAfAAMJihR1TwDzAANoDAAAAgAtAGkMAAABAB4A6gwAAAIAUQAAAA==.',
Ni='Nixaanu:BAEALgAECgEJAQABLgAECggJFAAUAH8aAA==.Nixei:BAEBLgAECn8UAAIUAAgJfxpEGABTAghoDAAAAgAyAGkMAAACAEIAawwAAAIATwBqDAAAAgA3AGwMAAAEAFAAbQwAAAMARwDqDAAAAgA3AG4MAAADAEYAFAAICX8aRBgAUwIIaAwAAAIAMgBpDAAAAgBCAGsMAAACAE8AagwAAAIANwBsDAAABABQAG0MAAADAEcA6gwAAAIANwBuDAAAAwBGAAAA.',
Ny='Nyriaa:BAECLgAFFH8GAAIXAAQJ3hkVEQAjAQRoDAAAAgBIAGkMAAACAFEAawwAAAEAOgDqDAAAAQA0ABcABAneGRURACMBBGgMAAACAEgAaQwAAAIAUQBrDAAAAQA6AOoMAAABADQALgAECn8eAAIXAAkJvSMKBAA5AwAXAAkJvSMKBAA5AwAAAA==.',
['Ní']='Nítedragon:BAEALgADCggJAwABLgAECgcJFAAGAFAgAA==.',
Ow='Owlenjoyer:BAECLgAFFH8GAAIhAAMJRxUxKADGAANoDAAAAwAiAGkMAAACADQA6gwAAAEATAAhAAMJRxUxKADGAANoDAAAAwAiAGkMAAACADQA6gwAAAEATAAuAAQKfx8AAiEACQmGGowLAIcCACEACQmGGowLAIcCAAEuAAUUBAkIAA8AlBoA.',
Pa='Palashin:BAEALgAECgYJDwABLgAECggJFgAIAFgfAA==.',
Pe='Personnelkid:BAEALgAECgcJDQABLgAECgkJPwAXAIMZAA==.',
Ph='Pheiro:BAEBLgAECn8cAAIEAAgJcQ1wiADBAQhoDAAABQBSAGkMAAAFAC0AawwAAAQAJQBqDAAAAgAXAGwMAAACABAAbQwAAAQADwDqDAAABQAmAG4MAAABAAUABAAICXENcIgAwQEIaAwAAAUAUgBpDAAABQAtAGsMAAAEACUAagwAAAIAFwBsDAAAAgAQAG0MAAAEAA8A6gwAAAUAJgBuDAAAAQAFAAAA.',
Pl='Platedaddy:BAEALgAECgYJDAABLgAFFAgJGwAGAEUNAA==.',
Pu='Punchweagle:BAEBLgAECn82AAMOAAkJNhBgHwCbAQloDAAACAAzAGkMAAAHAEAAawwAAAgAOgBqDAAABgAoAGwMAAAGADkAbQwAAAUAEQDqDAAABgAwAG4MAAAFAA0AbwwAAAMAEwAOAAkJ8Q5gHwCbAQloDAAABAAzAGkMAAAEADQAawwAAAQAMwBqDAAABAAZAGwMAAAEADkAbQwAAAUAEQDqDAAABAAqAG4MAAAFAA0AbwwAAAMAEwAWAAYJUxRGMgBbAQZoDAAABAAyAGkMAAADAEAAawwAAAQAOgBqDAAAAgAoAGwMAAACACUA6gwAAAIAMAAAAA==.',
Qr='Qrowdrake:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.Qrowfather:BAEALgAECggJEAAAAA==.Qrowsunny:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.',
Ra='Raveglaive:BAEALgAECgUJAwAAAA==.',
Re='Redvine:BAEALgADCgUJBQABLgAFFAUJEgAMACAVAA==.Rexpanda:BAEALgAECgQJBgABLgAECgUJBQABAAAAAA==.Rextank:BAEALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ro='Roogies:BAECLgAFFH8dAAIRAAUJ+SE3DwBwAQVoDAAACQBcAGkMAAAJAFUAawwAAAUASgBqDAAAAgBdAOoMAAAEAF4AEQAFCfkhNw8AcAEFaAwAAAkAXABpDAAACQBVAGsMAAAFAEoAagwAAAIAXQDqDAAABABeAC4ABAp/QQADEQAJCYglbwQA5AIAEQAJCVklbwQA5AIAHQACCZ0YIRUAqAAAAAA=.',
Ru='Rumpy:BAEALgAFFAIJBAABLgAFFAMJDQARAAAiAA==.',
['Ræ']='Ræx:BAEALgAECgUJBQAAAA==.',
Sh='Shiins:BAEALgAECgIJAwABLgAECggJFgAIAFgfAA==.Shinthyr:BAEBLgAECn8YAAIXAAcJ5R4eFQA0AgdoDAAABQBTAGkMAAAEAFUAawwAAAQAXQBqDAAAAwBHAGwMAAACAFUA6gwAAAQASwBuDAAAAgA6ABcABwnlHh4VADQCB2gMAAAFAFMAaQwAAAQAVQBrDAAABABdAGoMAAADAEcAbAwAAAIAVQDqDAAABABLAG4MAAACADoAAS4ABAoICRYACABYHwA=.',
Si='Sizzlefox:BAEALgAECgEJAQABLgAECgcJDwABAAAAAA==.',
St='Stygianfox:BAEALgAECgEJAgABLgAECgcJDwABAAAAAA==.',
Ta='Tahune:BAEBLgAECn9NAAMcAAkJWyUhAQDJAwloDAAACwBdAGkMAAAKAGIAawwAAAoAYgBqDAAACgBfAGwMAAAJAGEAbQwAAAcAXwDqDAAACgBhAG4MAAAGAFoAbwwAAAQAXQAcAAkJWyUhAQDJAwloDAAACQBdAGkMAAAKAGIAawwAAAgAYgBqDAAACgBfAGwMAAAJAGEAbQwAAAcAXwDqDAAACgBhAG4MAAAGAFoAbwwAAAQAXQAhAAIJhiEeWACXAAJoDAAAAgBWAGsMAAACAFUAAAA=.Taso:BAEBLgAECn8dAAIOAAgJVhE2KwBNAQhoDAAABgA/AGkMAAAFAEMAawwAAAUASgBqDAAABQBPAGwMAAABAAAAbQwAAAEAAADqDAAABQBBAG4MAAABACYADgAICVYRNisATQEIaAwAAAYAPwBpDAAABQBDAGsMAAAFAEoAagwAAAUATwBsDAAAAQAAAG0MAAABAAAA6gwAAAUAQQBuDAAAAQAmAAEuAAUUBQkWABsA6CAA.',
Th='Therapygap:BAEBLgAECn8wAAQXAAgJHBMYJACPAQhoDAAACABMAGkMAAAJADwAawwAAAUANwBqDAAABgAdAGwMAAAJADQAbQwAAAMALwDqDAAABwA8AG4MAAABAAgAFwAHCVcVGCQAjwEHaAwAAAUATABpDAAABQA8AGsMAAAEADcAagwAAAUAHQBsDAAABwA0AG0MAAADAC8A6gwAAAYAPAAZAAYJKwqeVACYAAZoDAAAAwAnAGkMAAAEABUAawwAAAEAEgBqDAAAAQAHAGwMAAACACkA6gwAAAEACAAYAAEJfAN/eAAhAAFuDAAAAQAIAAEuAAQKCQk/ABcAgxkA.',
Tr='Triboon:BAEALgADCgMJAwABLgAFFAgJFwAVAKQaAA==.Trèantdaddy:BAEALgAFFAEJAgABLgAFFAgJGwAGAEUNAA==.',
Tw='Twomonk:BAEALgAFFAEJAQABLgAFFAIJBgAWAL4hAA==.',
Un='Unsown:BAEALgAECgUJBQABLgAFFAMJDQANAEsdAA==.',
Us='Usurah:BAECLgAFFH8ZAAIfAAcJcxUjEACtAQdoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAACABsAbQwAAAEACADqDAAABAA+AB8ABwlzFSMQAK0BB2gMAAAGAE4AaQwAAAYAVgBrDAAAAwBBAGoMAAADADwAbAwAAAIAGwBtDAAAAQAIAOoMAAAEAD4ALgAECn8rAAMfAAkJgCLECQBDAwAfAAkJgCLECQBDAwAgAAUJWBwvGQA5AQAAAA==.',
Vi='Vindh:BAECLgAFFH8SAAMTAAUJugd9TADqAAVoDAAABgAXAGkMAAAEABUAawwAAAMACABqDAAAAQAJAOoMAAAEABgAEwAFCboHfUwA6gAFaAwAAAYAFwBpDAAABAAVAGsMAAADAAgAagwAAAEACQDqDAAAAwAYAAwAAQkOBp4QACkAAeoMAAABAA8ALgAECn8oAAQTAAkJtxVdPQD/AQATAAkJtxVdPQD/AQAMAAIJOgNiLAA9AAAiAAEJAAD7dgAAAAAAAA==.',
Vy='Vyndraennis:BAEBLgAECn8eAAITAAkJshGJPwC1AQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQATAAkJshGJPwC1AQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAAAA==.',
['Vî']='Vîtâl:BAEALgADCgMJAwABLgAFFAQJDwAVADkdAA==.',
Ya='Yaav:BAEBLgAECn8XAAIPAAkJxhCtUADAAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAPAAkJxhCtUADAAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAAAA==.',
Yu='Yufia:BAEBLgAECn8ZAAIJAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAJAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAAAA==.',
Za='Zatum:BAEBLgAECn8dAAIhAAgJVx2yEQA3AghoDAAABQBKAGkMAAAFAFYAawwAAAQAUABqDAAAAwA7AGwMAAAFAFMAbQwAAAEASgDqDAAABQBUAG4MAAABACoAIQAICVcdshEANwIIaAwAAAUASgBpDAAABQBWAGsMAAAEAFAAagwAAAMAOwBsDAAABQBTAG0MAAABAEoA6gwAAAUAVABuDAAAAQAqAAAA.',
Zh='Zhuröng:BAECLgAFFH8QAAIEAAQJnhrbTQA0AQRoDAAABQBJAGkMAAAFAE4AawwAAAMAKgDqDAAAAwBPAAQABAmeGttNADQBBGgMAAAFAEkAaQwAAAUATgBrDAAAAwAqAOoMAAADAE8ALgAECn8mAAIEAAkJlx/KTQBNAgAEAAkJlx/KTQBNAgAAAA==.',
Zo='Zomb:BAECLgAFFH8WAAIbAAUJ6CAsDQBvAQVoDAAABwBbAGkMAAAGAEQAawwAAAMAXQBqDAAAAQBMAOoMAAAFAFQAGwAFCeggLA0AbwEFaAwAAAcAWwBpDAAABgBEAGsMAAADAF0AagwAAAEATADqDAAABQBUAC4ABAp/JQACGwAICY4haQQABQMAGwAICY4haQQABQMAAAA=.',
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
