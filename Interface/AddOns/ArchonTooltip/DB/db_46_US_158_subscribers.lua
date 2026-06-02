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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Mage-Fire','Mage-Frost','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Druid-Guardian','DemonHunter-Vengeance','Rogue-Outlaw','Monk-Brewmaster','DeathKnight-Unholy','Paladin-Holy','Hunter-BeastMastery','Rogue-Subtlety','Warrior-Fury','DemonHunter-Devourer','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Blood','Druid-Restoration','Rogue-Assassination','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Druid-Balance','DemonHunter-Havoc',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=46,date='2026-06-01',data={Ad='Advvy:BAEALgAECgUJEgAAAA==.',
Ag='Ageregressor:BAEALgAECgcJBwAAAA==.',
Ai='Aihime:BAEALgADCgYJBgABLgAECgEJAQABAAAAAA==.',
Al='Alcean:BAEBLgAECn86AAICAAkJgCJnBQD1AgloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAFAFoAbwwAAAQAXQACAAkJgCJnBQD1AgloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAFAFoAbwwAAAQAXQAAAA==.Algebra:BAECLgAFFH8bAAMDAAYJwiRuAACxAQZoDAAABwBfAGkMAAAGAGEAawwAAAUAYwBqDAAAAwBaAGwMAAABAFkA6gwAAAUAWQAEAAYJfiTgFQAIAgZoDAAABgBbAGkMAAAFAGEAawwAAAQAYwBqDAAAAgBaAGwMAAABAFkA6gwAAAQAWQADAAUJxSRuAACxAQVoDAAAAQBfAGkMAAABAF8AawwAAAEAYQBqDAAAAQBUAOoMAAABAFgALgAECn8dAAIEAAkJoST7CAAiAwAEAAkJoST7CAAiAwAAAA==.Aléyna:BAEALgAECgEJAgAAAA==.',
Ar='Araakki:BAEALgAECgcJDwAAAA==.Arteron:BAEALgAFFAIJAwABLgAFFAcJFAAFAGweAA==.',
Ay='Ayoade:BAECLgAFFH8dAAIGAAUJ+RTbEQBdAQVoDAAABwAzAGkMAAAHAD0AawwAAAcATgBqDAAAAQAfAOoMAAAHAC0ABgAFCfkU2xEAXQEFaAwAAAcAMwBpDAAABwA9AGsMAAAHAE4AagwAAAEAHwDqDAAABwAtAC4ABAp/GAADBgAICWkcnQoAjAIABgAICWkcnQoAjAIABwACCREV4zEAhwAAAS4ABRQICS8ACAB9IAA=.',
Az='Azzurel:BAEBLgAECn8XAAMJAAgJMBHjcwBKAQhoDAAABAAxAGkMAAAEACkAawwAAAMAOABqDAAAAwAwAGwMAAADADwAbQwAAAIAEADqDAAAAwAwAG4MAAABACMACQAICTAR43MASgEIaAwAAAQAMQBpDAAABAApAGsMAAADADgAagwAAAIAMABsDAAAAwA8AG0MAAACABAA6gwAAAMAMABuDAAAAQAjAAoAAQkAAD5yADMAAWoMAAABABQAAAA=.',
Ba='Bareskin:BAEBLgAFFH8FAAILAAUJawqOFAC/AAVoDAAAAQAyAGkMAAABAAkAawwAAAEAGwBqDAAAAQAiAOoMAAABABMACwAFCWsKjhQAvwAFaAwAAAEAMgBpDAAAAQAJAGsMAAABABsAagwAAAEAIgDqDAAAAQATAAEuAAUUBQkSAAwAIBUA.',
Bl='Bloodroyal:BAEALgADCgcJBwABLgAFFAMJDQANAEsdAA==.',
Bo='Bobbysan:BAECLgAFFH8fAAIOAAgJnhjCBAAcAghoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACgAbQwAAAEAGwDqDAAACABWAG4MAAABADgADgAICZ4YwgQAHAIIaAwAAAYAUABpDAAABQBMAGsMAAAEAEkAagwAAAQAQABsDAAAAgAoAG0MAAABABsA6gwAAAgAVgBuDAAAAQA4AC4ABAp/LwACDgAJCRgh6AoAdwIADgAJCRgh6AoAdwIAAAA=.Bonemommyxo:BAECLgAFFH8TAAIPAAYJqCLOFgDpAQZoDAAABABbAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAPAAYJqCLOFgDpAQZoDAAABABbAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAuAAQKfysAAg8ACQmQJRwCALsDAA8ACQmQJRwCALsDAAAA.',
Br='Brigbala:BAEALgAECgMJBgAAAA==.',
Bu='Buttlustplz:BAEALgAFFAEJAQABLgAFFAMJBgAQAI8fAA==.',
Ch='Chunghús:BAEALgAECgYJBgABLgAFFAgJGwAGAEUNAA==.',
Co='Coggettle:BAEALgADCgcJBwABLgAECggJIAARACwgAA==.',
Cr='Crustome:BAEBLgAECn8aAAISAAgJ0QfFJQBPAQhoDAAABgATAGkMAAAGABMAawwAAAUAEABqDAAAAwAaAGwMAAACACQAbQwAAAEABgDqDAAAAgAJAG4MAAABAB8AEgAICdEHxSUATwEIaAwAAAYAEwBpDAAABgATAGsMAAAFABAAagwAAAMAGgBsDAAAAgAkAG0MAAABAAYA6gwAAAIACQBuDAAAAQAfAAAA.Crustorc:BAEBLgAECn8XAAITAAkJigfKMwBqAQloDAAAAwAXAGkMAAADABYAawwAAAMADwBqDAAAAwAXAGwMAAADABwAbQwAAAEACQDqDAAABAAPAG4MAAACABEAbwwAAAEAFQATAAkJigfKMwBqAQloDAAAAwAXAGkMAAADABYAawwAAAMADwBqDAAAAwAXAGwMAAADABwAbQwAAAEACQDqDAAABAAPAG4MAAACABEAbwwAAAEAFQABLgAECggJGgASANEHAA==.',
Cu='Cubed:BAEALgAFFAEJAQABLgAFFAYJGwADAMIkAA==.',
De='Deathhunterz:BAEBLgAECn8UAAIUAAYJWAXgswCiAAZoDAAABAAPAGkMAAAEABIAawwAAAUACQBqDAAAAgAaAGwMAAACABEA6gwAAAMABgAUAAYJWAXgswCiAAZoDAAABAAPAGkMAAAEABIAawwAAAUACQBqDAAAAgAaAGwMAAACABEA6gwAAAMABgAAAA==.Demagogué:BAECLgAFFH8NAAMVAAcJFRXjEAByAQdoDAAAAgA9AGsMAAABAAkAagwAAAEAJQBsDAAAAgBgAG0MAAABACcA6gwAAAUAQQBuDAAAAQA0ABUABgnCEeMQAHIBBmgMAAABAD0AawwAAAEACQBqDAAAAQAlAG0MAAABACcA6gwAAAUAQQBuDAAAAQA0AAgAAglvD5ZWAIQAAmgMAAABABwAbAwAAAIAMgAuAAQKfycAAxUACAn7I0AIAMkCABUACAn7I0AIAMkCAAgABwmRHPUxANQBAAEuAAUUCAkbAAYARQ0A.Demonipryde:BAEALgAECgMJAwAAAA==.',
Dr='Dreamspun:BAECLgAFFH8NAAINAAMJSx2vBgABAQNoDAAABQBGAGkMAAACAEoA6gwAAAYAUAANAAMJSx2vBgABAQNoDAAABQBGAGkMAAACAEoA6gwAAAYAUAAuAAQKfzYAAg0ACQmeIowAADEDAA0ACQmeIowAADEDAAAA.Drunkenqrow:BAEALgAECgYJDQABLgAECggJEAABAAAAAA==.',
Du='Dubsii:BAECLgAFFH8UAAIWAAYJUiBMCQAqAgZoDAAABABTAGkMAAAEAGAAawwAAAUAXABqDAAAAgBUAGwMAAACAC4A6gwAAAMAXQAWAAYJUiBMCQAqAgZoDAAABABTAGkMAAAEAGAAawwAAAUAXABqDAAAAgBUAGwMAAACAC4A6gwAAAMAXQAuAAQKfxcAAxYACAmLIZwGAPMCABYACAmLIZwGAPMCABcAAQl/JhpoAGwAAAEuAAUUCAkvAAgAfSAA.Dubsy:BAECLgAFFH8vAAIIAAgJfSB/AAA2AghoDAAACgBQAGkMAAAKAF8AawwAAAcAWwBqDAAACABjAGwMAAABAEMAbQwAAAEALADqDAAACQBWAG4MAAABAGQACAAICX0gfwAANgIIaAwAAAoAUABpDAAACgBfAGsMAAAHAFsAagwAAAgAYwBsDAAAAQBDAG0MAAABACwA6gwAAAkAVgBuDAAAAQBkAC4ABAp/MwADCAAJCdAllgAAtAMACAAJCdAllgAAtAMAFQAECbUj5SoAhwEAAAA=.',
Eh='Ehanee:BAEALgAFFAIJAwAAAA==.',
Er='Ereshin:BAEBLgAECn8XAAIIAAgJWB+bCwDsAghoDAAABABiAGkMAAADAGAAawwAAAQAWQBqDAAAAwBKAGwMAAACAE8AbQwAAAEAEgDqDAAAAwBYAG4MAAADAGAACAAICVgfmwsA7AIIaAwAAAQAYgBpDAAAAwBgAGsMAAAEAFkAagwAAAMASgBsDAAAAgBPAG0MAAABABIA6gwAAAMAWABuDAAAAwBgAAAA.',
Ev='Evieari:BAECLgAFFH8WAAMYAAYJ8xdICQCPAQZoDAAABABAAGkMAAAEACYAawwAAAQALwBqDAAABAAlAGwMAAABAGAA6gwAAAUAUgAYAAUJZBlICQCPAQVoDAAAAgBAAGkMAAABACYAawwAAAEAKgBsDAAAAQBgAOoMAAADAFIAGQAFCVAMgBsATAEFaAwAAAIAJQBpDAAAAwAYAGsMAAADAC8AagwAAAQAJQDqDAAAAgAKAC4ABAp/GQADGQAJCdYaGBoA4wEAGQAGCaYcGBoA4wEAGAAHCbkZmCkApQEAAS4ABRQGCQUAGABKHwA=.Evielyssa:BAEBLgAFFH8JAAIYAAUJGRJMDgBJAQVoDAAAAgAZAGkMAAACACUAawwAAAIAMQBqDAAAAQBMAOoMAAACACoAGAAFCRkSTA4ASQEFaAwAAAIAGQBpDAAAAgAlAGsMAAACADEAagwAAAEATADqDAAAAgAqAAEuAAUUBgkFABgASh8A.Evierari:BAEBLgAFFH8FAAMYAAIJSh+WIACaAAJoDAAAAwBQAGkMAAACAE8AGAACCUofliAAmgACaAwAAAIAUABpDAAAAgBPABoAAQkgAb8XADwAAWgMAAABAAIAAAA=.',
Fa='Fappimeal:BAECLgAFFH8mAAMPAAYJkyQLEgAIAgZoDAAACQBiAGkMAAAJAGEAawwAAAcAWgBqDAAABABVAGwMAAABAFEA6gwAAAgAYwAPAAYJkyQLEgAIAgZoDAAABwBiAGkMAAAHAGEAawwAAAUAWgBqDAAAAgBVAGwMAAABAFEA6gwAAAUAYwAbAAUJtBbVCAA6AQVoDAAAAgAtAGkMAAACADwAawwAAAIAPQBqDAAAAgAkAOoMAAADAEAALgAECn8/AAMPAAkJMCZ3AgC0AwAPAAkJMCZ3AgC0AwAbAAYJpxzbCgCmAQAAAA==.',
Fe='Felshins:BAEALgADCgMJBgABLgAECggJFwAIAFgfAA==.',
Fo='Fofer:BAEBLgAECn8nAAIOAAcJASbFCACZAgdoDAAACABjAGkMAAAIAGIAawwAAAgAYwBqDAAABQBjAGwMAAAFAGMAbQwAAAEAWQDqDAAABABgAA4ABwkBJsUIAJkCB2gMAAAIAGMAaQwAAAgAYgBrDAAACABjAGoMAAAFAGMAbAwAAAUAYwBtDAAAAQBZAOoMAAAEAGAAAS4ABRQICR8AHABCHwA=.Foil:BAEALgADCgkJGwABLgAECgkJTQAdAFslAA==.',
Fr='Froshin:BAEALgADCgUJCwABLgAECggJFwAIAFgfAA==.',
Fs='Fshi:BAEALgAECgYJAwAAAA==.',
Fu='Funkey:BAECLgAFFH8SAAMMAAUJIBWeAgCjAAVoDAAABQBDAGkMAAAFAFoAawwAAAIAFABqDAAAAgAWAOoMAAAEACYAFAAFCZkOckcA/QAFaAwAAAMAIQBpDAAABAA4AGsMAAACABQAagwAAAIAFgDqDAAABAAmAAwAAgm2Hp4CAKMAAmgMAAACAEMAaQwAAAEAWgAuAAQKfycAAwwACQmfIMQBAPwCAAwACAmzIsQBAPwCABQABgl+FrNMAIsBAAAA.',
Gr='Greatares:BAEALgAFFAMJAwAAAA==.Greathades:BAEALgAECgkJAgABLgAFFAMJAwABAAAAAA==.Greatmonkey:BAEALgAECgcJBgABLgAFFAMJAwABAAAAAA==.Greatodin:BAEALgAECgkJBAABLgAFFAMJAwABAAAAAA==.Greatosiris:BAEALgAECgkJAgABLgAFFAMJAwABAAAAAA==.Greatra:BAEALgADCgEJAQABLgAFFAMJAwABAAAAAA==.Grummel:BAECLgAFFH8NAAISAAMJACKzHQASAQNoDAAABwBbAGkMAAACAE8A6gwAAAQAWgASAAMJACKzHQASAQNoDAAABwBbAGkMAAACAE8A6gwAAAQAWgAuAAQKfycAAxIACQk8IH8JAPkCABIACQk8IH8JAPkCAB4AAQlwFGwdAEAAAAAA.',
Hb='Hbcarter:BAEBLgAFFH8HAAIdAAMJSxTzMgDYAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgAdAAMJSxTzMgDYAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgABLgAFFAgJLwAIAH0gAA==.',
Hr='Hrtenjoyer:BAEBLgAECn8YAAIXAAkJ4R2EBgDUAgloDAAABABfAGkMAAADAEgAawwAAAMATQBqDAAABABaAGwMAAAEAE8AbQwAAAEAUgDqDAAAAgBaAG4MAAACAFQAbwwAAAEAHQAXAAkJ4R2EBgDUAgloDAAABABfAGkMAAADAEgAawwAAAMATQBqDAAABABaAGwMAAAEAE8AbQwAAAEAUgDqDAAAAgBaAG4MAAACAFQAbwwAAAEAHQABLgAFFAQJCAAPAJQaAA==.',
Ia='Iambuns:BAEALgADCgcJBwABLgAFFAYJJgAPAJMkAA==.',
Il='Illiyania:BAEALgAECgEJAQAAAA==.Ilnarya:BAEALgAECgEJAQABLgAECgkJHgAUALIRAA==.',
Im='Imquitelarge:BAEBLgAECn8VAAIfAAkJWhbwDAAGAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAfAAkJWhbwDAAGAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAAAA==.',
Iz='Izapotato:BAECLgAFFH8TAAIUAAUJMxgjCQCXAQVoDAAABABUAGkMAAAEACoAawwAAAQANABqDAAAAwBDAOoMAAAEAEQAFAAFCTMYIwkAlwEFaAwAAAQAVABpDAAABAAqAGsMAAAEADQAagwAAAMAQwDqDAAABABEAC4ABAp/IgACFAAHCaElbR0AUwIAFAAHCaElbR0AUwIAAS4ABRQICRsABgBFDQA=.',
Ka='Katestinks:BAECLgAFFH8IAAIPAAQJlBrmPABdAQRoDAAAAgBXAGkMAAACAFMAawwAAAEABADqDAAAAwBhAA8ABAmUGuY8AF0BBGgMAAACAFcAaQwAAAIAUwBrDAAAAQAEAOoMAAADAGEALgAECn8qAAMPAAkJ0CMnBQBLAwAPAAkJ0CMnBQBLAwAcAAEJtgq6VwAqAAAAAA==.',
Ke='Kelandrea:BAECLgAFFH8HAAIgAAIJ3guNhACHAAJoDAAAAwAWAOoMAAAEACYAIAACCd4LjYQAhwACaAwAAAMAFgDqDAAABAAmAC4ABAp/HQAEIAAJCaEa2CIAngIAIAAJCaEa2CIAngIAEAACCdIQ94EAcAAAIQACCTMXckQAQAAAAS4ABRQDCQUAIACKFAA=.',
Ki='Kirkh:BAEALgAECgcJDAABLgAECgkJJgAaAEobAA==.Kirkpriest:BAEBLgAECn8mAAIaAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAaAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAAAA==.Kitowatt:BAEALgAECgYJCgABLgAECggJJQAiAGQfAA==.',
Kr='Kregazi:BAECLgAFFH8MAAIcAAQJYhh0FAAgAQRoDAAABAA7AGkMAAAEAEMAawwAAAEAXADqDAAAAwAdABwABAliGHQUACABBGgMAAAEADsAaQwAAAQAQwBrDAAAAQBcAOoMAAADAB0ALgAECn8wAAIcAAkJyCLoBADSAgAcAAkJyCLoBADSAgAAAA==.',
Ky='Kyriste:BAEBLgAECn8aAAIYAAcJZiFQDQB8AgdoDAAABQBbAGkMAAAFAFoAawwAAAQAWABqDAAAAwBVAGwMAAADAEAA6gwAAAQAWwBuDAAAAgBXABgABwlmIVANAHwCB2gMAAAFAFsAaQwAAAUAWgBrDAAABABYAGoMAAADAFUAbAwAAAMAQADqDAAABABbAG4MAAACAFcAAS4ABRQFCR0AEgD5IQA=.',
La='Larissaqt:BAECLgAFFH8hAAIaAAcJ0hHBBgDUAQdoDAAABwBTAGkMAAAGAEoAawwAAAcAHQBqDAAABgAgAGwMAAACADEA6gwAAAQAGwBuDAAAAQAIABoABwnSEcEGANQBB2gMAAAHAFMAaQwAAAYASgBrDAAABwAdAGoMAAAGACAAbAwAAAIAMQDqDAAABAAbAG4MAAABAAgALgAECn8yAAIaAAkJDiN1AgA0AwAaAAkJDiN1AgA0AwAAAA==.',
Li='Lioshi:BAEALgAECgYJCQABLgAFFAQJEAAEAJ4aAA==.',
Ma='Maildaddy:BAECLgAFFH8bAAIGAAgJRQ0TCAANAghoDAAABQAwAGkMAAAFAEMAawwAAAUALQBqDAAAAwAmAGwMAAABAAoAbQwAAAEACADqDAAABgAxAG4MAAABAAQABgAICUUNEwgADQIIaAwAAAUAMABpDAAABQBDAGsMAAAFAC0AagwAAAMAJgBsDAAAAQAKAG0MAAABAAgA6gwAAAYAMQBuDAAAAQAEAC4ABAp/JAAEBgAICYkcTAkARQIABgAHCSUgTAkARQIAAgAFCSgRKjcAGwEABwADCRwc3ycA4gAAAAA=.Maxxy:BAEBLgAECn8cAAIdAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAdAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAAAA==.',
Mc='Mckellen:BAECLgAFFH8LAAMYAAQJqBoRDwA/AQRoDAAAAwBFAGkMAAADADgAawwAAAIAPADqDAAAAwBWABgABAmoGhEPAD8BBGgMAAADAEUAaQwAAAIAOABrDAAAAgA8AOoMAAACAFYAGQACCREJAhQAlgACaQwAAAEAGgDqDAAAAQAUAC4ABAp/HQADGQAICc4ZmQwAbgIAGQAICc4ZmQwAbgIAGAAECSYMg1wAwQAAAS4ABRQICS8ACAB9IAA=.',
Me='Medranden:BAEALgADCgcJBwABLgAECgYJFAAUAFgFAA==.Merarite:BAEALgAFFAIJAgAAAA==.',
Mi='Militee:BAEALgADCgMJBAAAAA==.',
Mo='Mordraius:BAEALgAECggJEQABLgAFFAQJEAAEAJ4aAA==.',
My='Myceliums:BAEALgAECgUJDgAAAA==.',
Na='Nadasa:BAECLgAFFH8XAAIgAAUJ6BPpNwAoAQVoDAAABgAzAGkMAAAFAD4AawwAAAQAOgBqDAAAAwAxAOoMAAAFAB8AIAAFCegT6TcAKAEFaAwAAAYAMwBpDAAABQA+AGsMAAAEADoAagwAAAMAMQDqDAAABQAfAC4ABAp/RAACIAAJCZMhvhIAwQIAIAAJCZMhvhIAwQIAAAA=.Naramonria:BAEALgADCgcJCAAAAA==.',
Nh='Nhylia:BAEBLgAFFH8FAAIgAAMJihQIUQDyAANoDAAAAgAtAGkMAAABAB4A6gwAAAIAUQAgAAMJihQIUQDyAANoDAAAAgAtAGkMAAABAB4A6gwAAAIAUQAAAA==.',
Ni='Nixaanu:BAEALgAECgEJAQABLgAECggJFAAVAH8aAA==.Nixei:BAEBLgAECn8UAAIVAAgJfxpEGABTAghoDAAAAgAyAGkMAAACAEIAawwAAAIATwBqDAAAAgA3AGwMAAAEAFAAbQwAAAMARwDqDAAAAgA3AG4MAAADAEYAFQAICX8aRBgAUwIIaAwAAAIAMgBpDAAAAgBCAGsMAAACAE8AagwAAAIANwBsDAAABABQAG0MAAADAEcA6gwAAAIANwBuDAAAAwBGAAAA.',
Ny='Nyriaa:BAECLgAFFH8GAAIYAAQJ3hluEQAiAQRoDAAAAgBIAGkMAAACAFEAawwAAAEAOgDqDAAAAQA0ABgABAneGW4RACIBBGgMAAACAEgAaQwAAAIAUQBrDAAAAQA6AOoMAAABADQALgAECn8eAAIYAAkJvSMYBAA4AwAYAAkJvSMYBAA4AwAAAA==.',
['Ní']='Nítedragon:BAEALgADCggJAwABLgAECgcJFAAGAFAgAA==.',
Ow='Owlenjoyer:BAECLgAFFH8GAAIiAAMJRxXVKADGAANoDAAAAwAiAGkMAAACADQA6gwAAAEATAAiAAMJRxXVKADGAANoDAAAAwAiAGkMAAACADQA6gwAAAEATAAuAAQKfx8AAiIACQmGGroLAIcCACIACQmGGroLAIcCAAEuAAUUBAkIAA8AlBoA.',
Pa='Palashin:BAEALgAECgYJDwABLgAECggJFwAIAFgfAA==.',
Pe='Personnelkid:BAEALgAECgcJDQABLgAECgkJPwAYAIMZAA==.',
Ph='Pheiro:BAEBLgAECn8cAAIEAAgJcQ1wiADBAQhoDAAABQBSAGkMAAAFAC0AawwAAAQAJQBqDAAAAgAXAGwMAAACABAAbQwAAAQADwDqDAAABQAmAG4MAAABAAUABAAICXENcIgAwQEIaAwAAAUAUgBpDAAABQAtAGsMAAAEACUAagwAAAIAFwBsDAAAAgAQAG0MAAAEAA8A6gwAAAUAJgBuDAAAAQAFAAAA.',
Pl='Platedaddy:BAEALgAECgYJDAABLgAFFAgJGwAGAEUNAA==.',
Pu='Punchweagle:BAEBLgAECn82AAMOAAkJNhCrHwCbAQloDAAACAAzAGkMAAAHAEAAawwAAAgAOgBqDAAABgAoAGwMAAAGADkAbQwAAAUAEQDqDAAABgAwAG4MAAAFAA0AbwwAAAMAEwAOAAkJ8Q6rHwCbAQloDAAABAAzAGkMAAAEADQAawwAAAQAMwBqDAAABAAZAGwMAAAEADkAbQwAAAUAEQDqDAAABAAqAG4MAAAFAA0AbwwAAAMAEwAXAAYJUxRGMgBbAQZoDAAABAAyAGkMAAADAEAAawwAAAQAOgBqDAAAAgAoAGwMAAACACUA6gwAAAIAMAABLgAFFAIJAgABAAAAAA==.',
Qr='Qrowdrake:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.Qrowfather:BAEALgAECggJEAAAAA==.Qrowsunny:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.',
Ra='Raveglaive:BAEALgAECgUJAwAAAA==.',
Re='Redvine:BAEALgADCgUJBQABLgAFFAUJEgAMACAVAA==.Rexpanda:BAEALgAECgQJBgABLgAECgUJBQABAAAAAA==.Rextank:BAEALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ro='Roogies:BAECLgAFFH8dAAISAAUJ+SGtDwBvAQVoDAAACQBcAGkMAAAJAFUAawwAAAUASgBqDAAAAgBdAOoMAAAEAF4AEgAFCfkhrQ8AbwEFaAwAAAkAXABpDAAACQBVAGsMAAAFAEoAagwAAAIAXQDqDAAABABeAC4ABAp/QQADEgAJCYglgwQA4wIAEgAJCVklgwQA4wIAHgACCZ0YIRUAqAAAAAA=.',
Ru='Rumpy:BAEALgAFFAIJBAABLgAFFAMJDQASAAAiAA==.',
['Ræ']='Ræx:BAEALgAECgUJBQAAAA==.',
Sh='Shiins:BAEALgAECgIJAwABLgAECggJFwAIAFgfAA==.Shinthyr:BAEBLgAECn8YAAIYAAcJ5R4eFQA0AgdoDAAABQBTAGkMAAAEAFUAawwAAAQAXQBqDAAAAwBHAGwMAAACAFUA6gwAAAQASwBuDAAAAgA6ABgABwnlHh4VADQCB2gMAAAFAFMAaQwAAAQAVQBrDAAABABdAGoMAAADAEcAbAwAAAIAVQDqDAAABABLAG4MAAACADoAAS4ABAoICRcACABYHwA=.',
Si='Sizzlefox:BAEALgAECgEJAQABLgAECgcJDwABAAAAAA==.',
St='Stygianfox:BAEALgAECgEJAgABLgAECgcJDwABAAAAAA==.',
Ta='Tahune:BAEBLgAECn9NAAMdAAkJWyUmAQDJAwloDAAACwBdAGkMAAAKAGIAawwAAAoAYgBqDAAACgBfAGwMAAAJAGEAbQwAAAcAXwDqDAAACgBhAG4MAAAGAFoAbwwAAAQAXQAdAAkJWyUmAQDJAwloDAAACQBdAGkMAAAKAGIAawwAAAgAYgBqDAAACgBfAGwMAAAJAGEAbQwAAAcAXwDqDAAACgBhAG4MAAAGAFoAbwwAAAQAXQAiAAIJhiG4WACXAAJoDAAAAgBWAGsMAAACAFUAAAA=.Taso:BAEBLgAECn8dAAIOAAgJVhGIKwBNAQhoDAAABgA/AGkMAAAFAEMAawwAAAUASgBqDAAABQBPAGwMAAABAAAAbQwAAAEAAADqDAAABQBBAG4MAAABACYADgAICVYRiCsATQEIaAwAAAYAPwBpDAAABQBDAGsMAAAFAEoAagwAAAUATwBsDAAAAQAAAG0MAAABAAAA6gwAAAUAQQBuDAAAAQAmAAEuAAUUBQkWABwA6CAA.',
Th='Therapygap:BAEBLgAECn8wAAQYAAgJHBNfJACOAQhoDAAACABMAGkMAAAJADwAawwAAAUANwBqDAAABgAdAGwMAAAJADQAbQwAAAMALwDqDAAABwA8AG4MAAABAAgAGAAHCVcVXyQAjgEHaAwAAAUATABpDAAABQA8AGsMAAAEADcAagwAAAUAHQBsDAAABwA0AG0MAAADAC8A6gwAAAYAPAAaAAYJKwpCVQCYAAZoDAAAAwAnAGkMAAAEABUAawwAAAEAEgBqDAAAAQAHAGwMAAACACkA6gwAAAEACAAZAAEJfAOveQAhAAFuDAAAAQAIAAEuAAQKCQk/ABgAgxkA.',
Tr='Triboon:BAEALgADCgMJAwABLgAFFAgJFwAWAKQaAA==.Trèantdaddy:BAEALgAFFAEJAgABLgAFFAgJGwAGAEUNAA==.',
Tw='Twomonk:BAEALgAFFAEJAQABLgAFFAIJBgAXAL4hAA==.',
Un='Unsown:BAEALgAECgUJBQABLgAFFAMJDQANAEsdAA==.',
Us='Usurah:BAECLgAFFH8ZAAIgAAcJcxUjEQCpAQdoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAACABsAbQwAAAEACADqDAAABAA+ACAABwlzFSMRAKkBB2gMAAAGAE4AaQwAAAYAVgBrDAAAAwBBAGoMAAADADwAbAwAAAIAGwBtDAAAAQAIAOoMAAAEAD4ALgAECn8rAAMgAAkJgCLECQBDAwAgAAkJgCLECQBDAwAhAAUJWBx1GQA5AQAAAA==.',
Vi='Vindh:BAECLgAFFH8SAAMUAAUJugfDTQDpAAVoDAAABgAXAGkMAAAEABUAawwAAAMACABqDAAAAQAJAOoMAAAEABgAFAAFCboHw00A6QAFaAwAAAYAFwBpDAAABAAVAGsMAAADAAgAagwAAAEACQDqDAAAAwAYAAwAAQkOBuAQACkAAeoMAAABAA8ALgAECn8oAAQUAAkJtxVdPQD/AQAUAAkJtxVdPQD/AQAMAAIJOgOtLAA9AAAjAAEJAABHeAAAAAAAAA==.',
Vy='Vyndraennis:BAEBLgAECn8eAAIUAAkJshH+PwC1AQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAUAAkJshH+PwC1AQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAAAA==.',
['Vî']='Vîtâl:BAEALgADCgMJAwABLgAFFAQJDwAWADkdAA==.',
Ya='Yaav:BAEBLgAECn8XAAIPAAkJxhBeUQDAAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAPAAkJxhBeUQDAAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAAAA==.',
Yu='Yufia:BAEBLgAECn8ZAAIJAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAJAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAAAA==.',
Za='Zatum:BAEBLgAECn8lAAMiAAgJZB85DQByAghoDAAABgBTAGkMAAAGAFYAawwAAAUAUABqDAAABABLAGwMAAAGAFMAbQwAAAIASgDqDAAABgBUAG4MAAACAEYAIgAICWQfOQ0AcgIIaAwAAAYAUwBpDAAABgBWAGsMAAAFAFAAagwAAAQASwBsDAAABQBTAG0MAAABAEoA6gwAAAUAVABuDAAAAgBGAB0AAwmYCSaVAHgAA2wMAAABACIAbQwAAAEAHQDqDAAAAQAJAAAA.',
Zh='Zhuröng:BAECLgAFFH8QAAIEAAQJnhoXTwA0AQRoDAAABQBJAGkMAAAFAE4AawwAAAMAKgDqDAAAAwBPAAQABAmeGhdPADQBBGgMAAAFAEkAaQwAAAUATgBrDAAAAwAqAOoMAAADAE8ALgAECn8mAAIEAAkJlx/KTQBNAgAEAAkJlx/KTQBNAgAAAA==.',
Zo='Zomb:BAECLgAFFH8WAAIcAAUJ6CCtDQBrAQVoDAAABwBbAGkMAAAGAEQAawwAAAMAXQBqDAAAAQBMAOoMAAAFAFQAHAAFCeggrQ0AawEFaAwAAAcAWwBpDAAABgBEAGsMAAADAF0AagwAAAEATADqDAAABQBUAC4ABAp/JQACHAAICY4haQQABQMAHAAICY4haQQABQMAAAA=.',
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
