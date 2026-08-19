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

local lookup = {'DeathKnight-Unholy','Shaman-Restoration','Druid-Feral','Druid-Balance','Druid-Guardian','Unknown-Unknown','Shaman-Elemental','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Paladin-Holy','Paladin-Retribution','Monk-Mistweaver','Paladin-Protection','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Warrior-Fury','Warrior-Arms','Druid-Restoration','Hunter-Marksmanship','Hunter-Survival',}
local provider = {region='US',realm='Barthilas',name='US',type='subscribers',zone=46,date='2026-08-18',data={An='Andronix:BAEALgAECgEJAQABLgAFFAMJCgABAHULAA==.Angelreese:BAEALgAECgEJAQABLgAECgkJGQACAFUPAA==.',
Bi='Bigbites:BAEBLgAECn8jAAQDAAYJOhJoKgDAAAZoDAAABQAgAGkMAAAHADsAawwAAAYANABqDAAABgAnAGwMAAAFADgA6gwAAAYAIAAEAAYJ0AqxTQDzAAZoDAAABAAgAGkMAAAEACIAawwAAAQAFQBqDAAABAARAGwMAAAEABIA6gwAAAYAIAADAAQJ6hVoKgDAAARpDAAAAgA7AGsMAAABADQAagwAAAEAJwBsDAAAAQA4AAUABAmjCtxYAFsABGgMAAABABwAaQwAAAEAGgBrDAAAAQAaAGoMAAABAB8AAS4ABRQBCQEABgAAAAA=.Bitemyshiney:BAEBLgAECn8YAAMCAAkJEhKnBgD0AQloDAAABQAjAGkMAAAEAEoAawwAAAQASABqDAAAAQA2AGwMAAACADkAbQwAAAEAEwDqDAAABQBCAG4MAAABABIAbwwAAAEAEgACAAkJEhKnBgD0AQloDAAAAgAjAGkMAAACAEoAawwAAAIASABqDAAAAQA2AGwMAAACADkAbQwAAAEAEwDqDAAAAwBCAG4MAAABABIAbwwAAAEAEgAHAAQJBAcGdgCLAARoDAAAAwAYAGkMAAACABAAawwAAAIACADqDAAAAgAVAAEuAAQKCQkxAAgA4hIA.',
Ca='Cantbearme:BAEALgAECgUJDAABLgAECgkJMQAIAOISAA==.',
Ez='Ezarufwun:BAEALgAECgQJBgABLgAFFAIJBwACADMYAA==.',
Fe='Felrisen:BAEALgAECggJCQABLgAFFAMJCgABAHULAA==.',
Fl='Flagmewillya:BAEBLgAECn8cAAMJAAYJ5wwCQwDeAAZoDAAACABLAGkMAAAHAB8AawwAAAUAHwBqDAAAAgAHAGwMAAABAAUA6gwAAAUALgAJAAYJ5wwCQwDeAAZoDAAABgBLAGkMAAAGAB8AawwAAAQAHwBqDAAAAgAHAGwMAAABAAUA6gwAAAQALgAKAAQJ4gQCbABvAARoDAAAAgAJAGkMAAABAAcAawwAAAEAAgDqDAAAAQAfAAEuAAQKCQkxAAgA4hIA.',
Fy='Fyrre:BAECLgAFFH8fAAIIAAkJ5BSKAwBlAQloDAAABQBRAGkMAAAFAF0AawwAAAQAVQBqDAAAAQAXAGwMAAACAA4AbQwAAAEALgDqDAAACwAzAG4MAAABACUAbwwAAAEAEQAIAAkJ5BSKAwBlAQloDAAABQBRAGkMAAAFAF0AawwAAAQAVQBqDAAAAQAXAGwMAAACAA4AbQwAAAEALgDqDAAACwAzAG4MAAABACUAbwwAAAEAEQAuAAQKf0AAAggACQlSJM0DAFMDAAgACQlSJM0DAFMDAAAA.',
He='Heyimapanda:BAEALgAECgUJBQABLgAECgkJMQAIAOISAA==.',
Il='Ilovemyself:BAEBLgAECn8YAAMLAAkJYw8zVwDaAAloDAAAAwAiAGkMAAADABcAawwAAAMACgBqDAAAAgBRAGwMAAABAB4AbQwAAAEACADqDAAACAA4AG4MAAACAE4AbwwAAAEAHgALAAUJawozVwDaAAVoDAAAAQAiAGkMAAABABcAawwAAAEACgBtDAAAAQAIAOoMAAABADgADAAICSILXC4AngAIaAwAAAIAJQBpDAAAAgAKAGsMAAACAAgAagwAAAIAFgBsDAAAAQAcAOoMAAAHAEoAbgwAAAIAEABvDAAAAQAXAAEuAAQKCQkxAAgA4hIA.',
Jc='Jcmnk:BAEBLgAFFH8oAAINAAkJQxs3AgAGAwloDAAABwBiAGkMAAAHAF4AawwAAAcAWABqDAAABABhAGwMAAADAE4AbQwAAAEAMQDqDAAAAwAiAG4MAAAHAE4AbwwAAAEACQANAAkJQxs3AgAGAwloDAAABwBiAGkMAAAHAF4AawwAAAcAWABqDAAABABhAGwMAAADAE4AbQwAAAEAMQDqDAAAAwAiAG4MAAAHAE4AbwwAAAEACQAAAA==.',
Ji='Jingsho:BAEALgAECgMJBAAAAA==.',
Le='Leë:BAECLgAFFH8FAAIMAAIJiA/goQB8AAJoDAAAAwA+AOoMAAACABEADAACCYgP4KEAfAACaAwAAAMAPgDqDAAAAgARAC4ABAp/GwAEDgAHCY8d8QoAHQIADgAGCUEg8QoAHQIADAAGCQUVgsEABgEACwABCdsKv5cAMgAAAS4ABRQDCQYAAgB1IQA=.',
Lo='Lotheril:BAEALgAFFAIJAgABLgAFFAMJCgABAHULAA==.',
Lu='Lunaadk:BAEALgADCgEJAQABLgAFFAYJHwAIAK8SAA==.',
Ma='Malpractis:BAECLgAFFH88AAIKAAgJwiJDAgCSAghoDAAADABhAGkMAAALAGMAawwAAAsAYABqDAAACgBkAGwMAAADAGIAbQwAAAIAUwDqDAAACgBkAG4MAAABAC4ACgAICcIiQwIAkgIIaAwAAAwAYQBpDAAACwBjAGsMAAALAGAAagwAAAoAZABsDAAAAwBiAG0MAAACAFMA6gwAAAoAZABuDAAAAQAuAC4ABAp/HwACCgAJCVUl1gUAMQMACgAJCVUl1gUAMQMAAS4ABRQJCX0ACgBkJgA=.Masamura:BAECLgAFFH8KAAIBAAMJdQttugCzAANoDAAABAAdAGkMAAABAAUA6gwAAAUANAABAAMJdQttugCzAANoDAAABAAdAGkMAAABAAUA6gwAAAUANAAuAAQKfyYAAwEACAl5G3hlAJwBAAEACAk9GHhlAJwBAA8ABQmFENILAP0AAAAA.Mathstutorli:BAEBLgAFFH8YAAIDAAgJHx9/AACUAghoDAAABABUAGkMAAACAF0AawwAAAQAOwBqDAAAAgATAGwMAAACAC8AbQwAAAEAUwDqDAAACABhAG4MAAABAFsAAwAICR8ffwAAlAIIaAwAAAQAVABpDAAAAgBdAGsMAAAEADsAagwAAAIAEwBsDAAAAgAvAG0MAAABAFMA6gwAAAgAYQBuDAAAAQBbAAAA.',
Mo='Moogledrake:BAEALgADCgcJBwABLgAECgUJBQAGAAAAAA==.Moogledrood:BAEALgAECgUJBQAAAA==.Morbingsage:BAEALgAECgcJEQABLgAFFAkJMQAQAAgfAA==.Mourningsage:BAECLgAFFH8xAAMQAAkJCB8JDQDxAQloDAAACABaAGkMAAAGAFoAawwAAAUAXwBqDAAABAAwAGwMAAADAEsAbQwAAAIALQDqDAAABQBYAG4MAAAIADgAbwwAAAgAXQAQAAgJ6SAJDQDxAQhoDAAACABaAGkMAAAGAFoAawwAAAIAXwBqDAAAAwAwAGwMAAADAEsA6gwAAAUAWABuDAAACAA4AG8MAAAIAF0AEQADCcAUYw4AmQADawwAAAMAPABqDAAAAQAGAG0MAAACAC0ALgAECn8sAAMQAAkJOyVdCAA+AwAQAAkJqCRdCAA+AwARAAcJiyUlBABCAgAAAA==.',
Na='Naturegift:BAEALgAECgkJEgAAAA==.',
Ni='Nickbatum:BAEBLgAECn8ZAAMCAAkJVQ/hPQCKAQloDAAAAwAbAGkMAAAEACYAawwAAAQASgBqDAAABAAjAGwMAAACADwAbQwAAAIALADqDAAAAgAnAG4MAAACAAsAbwwAAAIAFQACAAkJVQ/hPQCKAQloDAAAAwAbAGkMAAADACYAawwAAAMASgBqDAAAAgAjAGwMAAACADwAbQwAAAIALADqDAAAAgAnAG4MAAACAAsAbwwAAAIAFQAHAAMJNAxwiwBZAANpDAAAAQAYAGsMAAABACYAagwAAAIALwAAAA==.',
Pe='Peterpikachu:BAEALgAECgkJAgABLgAECgkJEgAGAAAAAA==.',
Ra='Randomno:BAECLgAFFH82AAMQAAkJIgcgGABoAQloDAAACAAWAGkMAAAIABYAawwAAAYABgBqDAAABAAEAGwMAAADAA4AbQwAAAIABADqDAAABwAzAG4MAAAIAAUAbwwAAAgAEgAQAAgJ4gcgGABoAQhoDAAABgAWAGkMAAAGABYAawwAAAMABgBqDAAABAAEAGwMAAADAA4A6gwAAAMAMwBuDAAACAAFAG8MAAAIABIAEQAFCWYCwwYABQEFaAwAAAIABQBpDAAAAgAHAGsMAAADAAYAbQwAAAIABADqDAAABAAHAC4ABAp/MwAEEQAJCdkZxwoAEwIAEQAJCfASxwoAEwIAEAAJCcQTCFcAwwEAEgAGCYUaiAoAlQEAAAA=.',
['Rï']='Rïvver:BAEALgAECgUJBQABLgAFFAkJHwAIAOQUAA==.',
Sa='Saddk:BAEALgAECgEJAQAAAA==.',
Sc='Sceptile:BAEBLgAFFH8ZAAQPAAcJZxuqBACOAQdoDAAABABQAGkMAAAEADIAawwAAAIAPgBtDAAAAgBIAOoMAAAKAFQAbgwAAAIARABvDAAAAQBGAA8ABQmKGKoEAI4BBWgMAAACAFAAaQwAAAIAMgBrDAAAAgA+AOoMAAACADEAbwwAAAEARgABAAMJix3rvACvAANtDAAAAgBIAOoMAAAGAFQAbgwAAAIARAATAAMJKRQRKgCnAANoDAAAAgBKAGkMAAACABkA6gwAAAIANwAAAA==.',
Sh='Shazàm:BAECLgAFFH8GAAICAAMJdSHaNQALAQNoDAAAAwBVAGkMAAABAFUA6gwAAAIAVQACAAMJdSHaNQALAQNoDAAAAwBVAGkMAAABAFUA6gwAAAIAVQAuAAQKfxoAAgIABgmnHJY7AMABAAIABgmnHJY7AMABAAAA.Sherkia:BAEALgAECgQJBAABLgAECgkJHwAUAAMVAA==.Sherko:BAEBLgAECn8fAAMUAAkJAxU9DgDpAAloDAAABwAtAGkMAAAFAEIAawwAAAUAQgBqDAAAAwA2AGwMAAACADMAbQwAAAEAKgDqDAAABgBCAG4MAAABAB0AbwwAAAEAPgAVAAUJFRJXLwALAQVoDAAABQAtAGkMAAADAEIAawwAAAMAJwBsDAAAAQAwAOoMAAACACAAFAAJCQkUPQ4A6QAJaAwAAAIAIwBpDAAAAgA3AGsMAAACAEIAagwAAAMANgBsDAAAAQAzAG0MAAABACoA6gwAAAQAQgBuDAAAAQAdAG8MAAABAD4AAAA=.Shruggo:BAECLgAFFH8hAAINAAUJmSIHFADkAQVoDAAACQBeAGkMAAAJAFkAawwAAAUATwBqDAAAAQBSAOoMAAAJAGAADQAFCZkiBxQA5AEFaAwAAAkAXgBpDAAACQBZAGsMAAAFAE8AagwAAAEAUgDqDAAACQBgAC4ABAp/PAACDQAJCaYiLAUAEQMADQAJCaYiLAUAEQMAAAA=.',
Su='Sungrass:BAEBLgAECn8dAAIWAAkJ1RnIHwBDAgloDAAABABdAGkMAAAEAFQAawwAAAQAUwBqDAAAAwA/AGwMAAADAEYAbQwAAAIANADqDAAABABBAG4MAAAEADMAbwwAAAEAHgAWAAkJ1RnIHwBDAgloDAAABABdAGkMAAAEAFQAawwAAAQAUwBqDAAAAwA/AGwMAAADAEYAbQwAAAIANADqDAAABABBAG4MAAAEADMAbwwAAAEAHgAAAA==.',
Ta='Tapmepleasé:BAEBLgAECn8xAAMIAAkJ4hKmQgDaAQloDAAABwBLAGkMAAAHADoAawwAAAcANQBqDAAABQAxAGwMAAAEACsAbQwAAAMAEQDqDAAABwA7AG4MAAAGABwAbwwAAAMAMAAIAAkJ4hKmQgDaAQloDAAABwBLAGkMAAAHADoAawwAAAYANQBqDAAABQAxAGwMAAAEACsAbQwAAAMAEQDqDAAABwA7AG4MAAAGABwAbwwAAAMAMAAXAAEJaA3cPAAxAAFrDAAAAQAiAAAA.',
Th='Thedèvil:BAEALgAECgUJCwABLgAECgkJMQAIAOISAA==.',
Ze='Zeigndeath:BAEBLgAFFH8GAAMIAAMJRRbvZADbAANoDAAAAgA/AGkMAAACADMA6gwAAAIAOAAIAAMJ5RHvZADbAANoDAAAAQAdAGkMAAABADMA6gwAAAIAOAAYAAIJchM9JwCaAAJoDAAAAQA/AGkMAAABACQAAAA=.Zelemonk:BAEBLgAECn8VAAINAAcJcyFGIQASAgdoDAAAAwBbAGkMAAADAFoAawwAAAEAUQBqDAAAAwBTAGwMAAAIAF4AbQwAAAEARADqDAAAAgBYAA0ABwlzIUYhABICB2gMAAADAFsAaQwAAAMAWgBrDAAAAQBRAGoMAAADAFMAbAwAAAgAXgBtDAAAAQBEAOoMAAACAFgAAS4ABRQHCRUAAQC6HgA=.',
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
