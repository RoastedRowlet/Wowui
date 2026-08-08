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

local lookup = {'DeathKnight-Unholy','Shaman-Restoration','Druid-Feral','Druid-Balance','Druid-Guardian','Unknown-Unknown','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Paladin-Holy','Paladin-Retribution','Monk-Mistweaver','Paladin-Protection','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','Shaman-Elemental','Warlock-Affliction','DeathKnight-Blood','Warrior-Fury','Warrior-Arms','Druid-Restoration','Hunter-Marksmanship','Hunter-Survival',}
local provider = {region='US',realm='Barthilas',name='US',type='subscribers',zone=46,date='2026-08-04',data={An='Andronix:BAEALgAECgEJAQABLgAFFAMJCgABAHULAA==.Angelreese:BAEALgAECgEJAQABLgAECgkJGQACAFUPAA==.',
Bi='Bigbites:BAEBLgAECn8jAAQDAAYJOhJoKgDAAAZoDAAABQAgAGkMAAAHADsAawwAAAYANABqDAAABgAnAGwMAAAFADgA6gwAAAYAIAAEAAYJ0AqxTQDzAAZoDAAABAAgAGkMAAAEACIAawwAAAQAFQBqDAAABAARAGwMAAAEABIA6gwAAAYAIAADAAQJ6hVoKgDAAARpDAAAAgA7AGsMAAABADQAagwAAAEAJwBsDAAAAQA4AAUABAmjCtxYAFsABGgMAAABABwAaQwAAAEAGgBrDAAAAQAaAGoMAAABAB8AAS4ABRQBCQEABgAAAAA=.Bitemyshiney:BAEALgAECgYJEwABLgAECgkJMQAHAOISAA==.',
Ca='Cantbearme:BAEALgAECgQJCAABLgAECgkJMQAHAOISAA==.',
Ez='Ezarufwun:BAEALgAECgQJBgABLgAFFAIJBwACADMYAA==.',
Fe='Felrisen:BAEALgAECggJCQABLgAFFAMJCgABAHULAA==.',
Fl='Flagmewillya:BAEBLgAECn8cAAMIAAYJ5wwCQwDeAAZoDAAACABLAGkMAAAHAB8AawwAAAUAHwBqDAAAAgAHAGwMAAABAAUA6gwAAAUALgAIAAYJ5wwCQwDeAAZoDAAABgBLAGkMAAAGAB8AawwAAAQAHwBqDAAAAgAHAGwMAAABAAUA6gwAAAQALgAJAAQJ4gQCbABvAARoDAAAAgAJAGkMAAABAAcAawwAAAEAAgDqDAAAAQAfAAEuAAQKCQkxAAcA4hIA.',
Fy='Fyrre:BAECLgAFFH8eAAIHAAgJ5BaKAwBlAQhoDAAABQBRAGkMAAAFAF0AawwAAAQAVQBqDAAAAQAXAGwMAAACAA4AbQwAAAEALgDqDAAACwAzAG4MAAABACUABwAICeQWigMAZQEIaAwAAAUAUQBpDAAABQBdAGsMAAAEAFUAagwAAAEAFwBsDAAAAgAOAG0MAAABAC4A6gwAAAsAMwBuDAAAAQAlAC4ABAp/QAACBwAJCVIkzQMAUwMABwAJCVIkzQMAUwMAAAA=.',
He='Heyimapanda:BAEALgAECgUJBQABLgAECgkJMQAHAOISAA==.',
Il='Ilovemyself:BAEBLgAECn8YAAMKAAkJYw8zVwDaAAloDAAAAwAiAGkMAAADABcAawwAAAMACgBqDAAAAgBRAGwMAAABAB4AbQwAAAEACADqDAAACAA4AG4MAAACAE4AbwwAAAEAHgAKAAUJawozVwDaAAVoDAAAAQAiAGkMAAABABcAawwAAAEACgBtDAAAAQAIAOoMAAABADgACwAICSILCSsAnwAIaAwAAAIAJQBpDAAAAgAKAGsMAAACAAgAagwAAAIAFgBsDAAAAQAcAOoMAAAHAEoAbgwAAAIAEABvDAAAAQAXAAEuAAQKCQkxAAcA4hIA.',
Jc='Jcmnk:BAEBLgAFFH8oAAIMAAkJQxv7AQANAwloDAAABwBiAGkMAAAHAF4AawwAAAcAWABqDAAABABhAGwMAAADAE4AbQwAAAEAMQDqDAAAAwAiAG4MAAAHAE4AbwwAAAEACQAMAAkJQxv7AQANAwloDAAABwBiAGkMAAAHAF4AawwAAAcAWABqDAAABABhAGwMAAADAE4AbQwAAAEAMQDqDAAAAwAiAG4MAAAHAE4AbwwAAAEACQAAAA==.',
Ji='Jingsho:BAEALgAECgMJBAAAAA==.',
Le='Leë:BAECLgAFFH8FAAILAAIJiA/goQB8AAJoDAAAAwA+AOoMAAACABEACwACCYgP4KEAfAACaAwAAAMAPgDqDAAAAgARAC4ABAp/GwAEDQAHCY8d8QoAHQIADQAGCUEg8QoAHQIACwAGCQUVgsEABgEACgABCdsKv5cAMgAAAS4ABRQDCQYAAgB1IQA=.',
Lo='Lotheril:BAEALgAFFAIJAgABLgAFFAMJCgABAHULAA==.',
Lu='Lunaadk:BAEALgADCgEJAQABLgAFFAYJHwAHAK8SAA==.',
Ma='Malpractis:BAECLgAFFH88AAIJAAgJwiJDAgCSAghoDAAADABhAGkMAAALAGMAawwAAAsAYABqDAAACgBkAGwMAAADAGIAbQwAAAIAUwDqDAAACgBkAG4MAAABAC4ACQAICcIiQwIAkgIIaAwAAAwAYQBpDAAACwBjAGsMAAALAGAAagwAAAoAZABsDAAAAwBiAG0MAAACAFMA6gwAAAoAZABuDAAAAQAuAC4ABAp/HwACCQAJCVUl1gUAMQMACQAJCVUl1gUAMQMAAS4ABRQJCX0ACQBkJgA=.Masamura:BAECLgAFFH8KAAIBAAMJdQttugCzAANoDAAABAAdAGkMAAABAAUA6gwAAAUANAABAAMJdQttugCzAANoDAAABAAdAGkMAAABAAUA6gwAAAUANAAuAAQKfyYAAwEACAl5G3hlAJwBAAEACAk9GHhlAJwBAA4ABQmFENILAP0AAAAA.Mathstutorli:BAEBLgAFFH8UAAIDAAgJBB2ZAABlAghoDAAAAwBTAGkMAAABADsAawwAAAMAOwBqDAAAAgATAGwMAAACAC8AbQwAAAEAUwDqDAAABwBeAG4MAAABAFsAAwAICQQdmQAAZQIIaAwAAAMAUwBpDAAAAQA7AGsMAAADADsAagwAAAIAEwBsDAAAAgAvAG0MAAABAFMA6gwAAAcAXgBuDAAAAQBbAAAA.',
Mo='Moogledrake:BAEALgADCgcJBwABLgAECgUJBQAGAAAAAA==.Moogledrood:BAEALgAECgUJBQAAAA==.Morbingsage:BAEALgAECgcJEQABLgAFFAkJLwAPAGYeAA==.Mourningsage:BAECLgAFFH8vAAMPAAkJZh56DAD2AQloDAAACABaAGkMAAAGAFoAawwAAAUAXwBqDAAABAAwAGwMAAADAEsAbQwAAAIALQDqDAAABQBYAG4MAAAHACsAbwwAAAcAXQAPAAgJMCB6DAD2AQhoDAAACABaAGkMAAAGAFoAawwAAAIAXwBqDAAAAwAwAGwMAAADAEsA6gwAAAUAWABuDAAABwArAG8MAAAHAF0AEAADCcAUYw4AmQADawwAAAMAPABqDAAAAQAGAG0MAAACAC0ALgAECn8sAAMPAAkJOyVdCAA+AwAPAAkJqCRdCAA+AwAQAAcJiyUlBABCAgAAAA==.',
Na='Naturegift:BAEALgAECgkJEgAAAA==.',
Ni='Nickbatum:BAEBLgAECn8ZAAMCAAkJVQ/hPQCKAQloDAAAAwAbAGkMAAAEACYAawwAAAQASgBqDAAABAAjAGwMAAACADwAbQwAAAIALADqDAAAAgAnAG4MAAACAAsAbwwAAAIAFQACAAkJVQ/hPQCKAQloDAAAAwAbAGkMAAADACYAawwAAAMASgBqDAAAAgAjAGwMAAACADwAbQwAAAIALADqDAAAAgAnAG4MAAACAAsAbwwAAAIAFQARAAMJNAxwiwBZAANpDAAAAQAYAGsMAAABACYAagwAAAIALwAAAA==.',
Pe='Peterpikachu:BAEALgAECgkJAgABLgAECgkJEgAGAAAAAA==.',
Ra='Randomno:BAECLgAFFH80AAMPAAkJIgdrFgB4AQloDAAACAAWAGkMAAAIABYAawwAAAYABgBqDAAABAAEAGwMAAADAA4AbQwAAAIABADqDAAABwAzAG4MAAAHAAUAbwwAAAcAEgAPAAgJ4gdrFgB4AQhoDAAABgAWAGkMAAAGABYAawwAAAMABgBqDAAABAAEAGwMAAADAA4A6gwAAAMAMwBuDAAABwAFAG8MAAAHABIAEAAFCWYCwwYABQEFaAwAAAIABQBpDAAAAgAHAGsMAAADAAYAbQwAAAIABADqDAAABAAHAC4ABAp/MwAEEAAJCdkZxwoAEwIAEAAJCfASxwoAEwIADwAJCcQTCFcAwwEAEgAGCYUaiAoAlQEAAAA=.',
['Rï']='Rïvver:BAEALgAECgUJBQABLgAFFAgJHgAHAOQWAA==.',
Sa='Saddk:BAEALgAECgEJAQAAAA==.',
Sc='Sceptile:BAEBLgAFFH8YAAQOAAYJZRsxBwA0AQZoDAAABABQAGkMAAAEADIAawwAAAIAPgBtDAAAAgBIAOoMAAAKAFQAbgwAAAIARAAOAAQJ0RcxBwA0AQRoDAAAAgBQAGkMAAACADIAawwAAAIAPgDqDAAAAgAxAAEAAwmLHeu8AK8AA20MAAACAEgA6gwAAAYAVABuDAAAAgBEABMAAwkpFBEqAKcAA2gMAAACAEoAaQwAAAIAGQDqDAAAAgA3AAAA.',
Sh='Shazàm:BAECLgAFFH8GAAICAAMJdSHaNQALAQNoDAAAAwBVAGkMAAABAFUA6gwAAAIAVQACAAMJdSHaNQALAQNoDAAAAwBVAGkMAAABAFUA6gwAAAIAVQAuAAQKfxoAAgIABgmnHJY7AMABAAIABgmnHJY7AMABAAAA.Sherkia:BAEALgAECgQJBAABLgAECgkJHwAUAAMVAA==.Sherko:BAEBLgAECn8fAAMUAAkJAxVhDQDqAAloDAAABwAtAGkMAAAFAEIAawwAAAUAQgBqDAAAAwA2AGwMAAACADMAbQwAAAEAKgDqDAAABgBCAG4MAAABAB0AbwwAAAEAPgAVAAUJFRJXLwALAQVoDAAABQAtAGkMAAADAEIAawwAAAMAJwBsDAAAAQAwAOoMAAACACAAFAAJCQkUYQ0A6gAJaAwAAAIAIwBpDAAAAgA3AGsMAAACAEIAagwAAAMANgBsDAAAAQAzAG0MAAABACoA6gwAAAQAQgBuDAAAAQAdAG8MAAABAD4AAAA=.Shruggo:BAECLgAFFH8hAAIMAAUJmSIHFADkAQVoDAAACQBeAGkMAAAJAFkAawwAAAUATwBqDAAAAQBSAOoMAAAJAGAADAAFCZkiBxQA5AEFaAwAAAkAXgBpDAAACQBZAGsMAAAFAE8AagwAAAEAUgDqDAAACQBgAC4ABAp/PAACDAAJCaYiLAUAEQMADAAJCaYiLAUAEQMAAAA=.',
Su='Sungrass:BAEBLgAECn8dAAIWAAkJ1RnIHwBDAgloDAAABABdAGkMAAAEAFQAawwAAAQAUwBqDAAAAwA/AGwMAAADAEYAbQwAAAIANADqDAAABABBAG4MAAAEADMAbwwAAAEAHgAWAAkJ1RnIHwBDAgloDAAABABdAGkMAAAEAFQAawwAAAQAUwBqDAAAAwA/AGwMAAADAEYAbQwAAAIANADqDAAABABBAG4MAAAEADMAbwwAAAEAHgAAAA==.',
Ta='Tapmepleasé:BAEBLgAECn8xAAMHAAkJ4hKmQgDaAQloDAAABwBLAGkMAAAHADoAawwAAAcANQBqDAAABQAxAGwMAAAEACsAbQwAAAMAEQDqDAAABwA7AG4MAAAGABwAbwwAAAMAMAAHAAkJ4hKmQgDaAQloDAAABwBLAGkMAAAHADoAawwAAAYANQBqDAAABQAxAGwMAAAEACsAbQwAAAMAEQDqDAAABwA7AG4MAAAGABwAbwwAAAMAMAAXAAEJaA3cPAAxAAFrDAAAAQAiAAAA.',
Th='Thedèvil:BAEALgAECgUJCwABLgAECgkJMQAHAOISAA==.',
Ze='Zeigndeath:BAEBLgAFFH8GAAMHAAMJRRbvZADbAANoDAAAAgA/AGkMAAACADMA6gwAAAIAOAAHAAMJ5RHvZADbAANoDAAAAQAdAGkMAAABADMA6gwAAAIAOAAYAAIJchM9JwCaAAJoDAAAAQA/AGkMAAABACQAAAA=.Zelemonk:BAEBLgAECn8VAAIMAAcJcyFGIQASAgdoDAAAAwBbAGkMAAADAFoAawwAAAEAUQBqDAAAAwBTAGwMAAAIAF4AbQwAAAEARADqDAAAAgBYAAwABwlzIUYhABICB2gMAAADAFsAaQwAAAMAWgBrDAAAAQBRAGoMAAADAFMAbAwAAAgAXgBtDAAAAQBEAOoMAAACAFgAAS4ABRQHCRQAAQC6HgA=.',
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
