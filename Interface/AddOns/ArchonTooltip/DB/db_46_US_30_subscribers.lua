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

local lookup = {'Druid-Feral','Druid-Balance','Druid-Guardian','Unknown-Unknown','Hunter-BeastMastery','Paladin-Retribution','Priest-Shadow','Warrior-Fury','DeathKnight-Unholy','Priest-Holy','Monk-Mistweaver','Paladin-Protection','Paladin-Holy','Shaman-Restoration','DeathKnight-Frost','Priest-Discipline','Warlock-Demonology','Warlock-Destruction','Shaman-Elemental','Warlock-Affliction','DeathKnight-Blood','Monk-Brewmaster','Monk-Windwalker','Warrior-Arms','Druid-Restoration','Hunter-Survival',}
local provider = {region='US',realm='Barthilas',name='US',type='subscribers',zone=46,date='2026-05-31',data={Bi='Bigbites:BAEBLgAECn8jAAQBAAYJOhIuJQC/AAZoDAAABQAgAGkMAAAHADsAawwAAAYANABqDAAABgAnAGwMAAAFADgA6gwAAAYAIAACAAYJ0AqxTQDzAAZoDAAABAAgAGkMAAAEACIAawwAAAQAFQBqDAAABAARAGwMAAAEABIA6gwAAAYAIAABAAQJ6hUuJQC/AARpDAAAAgA7AGsMAAABADQAagwAAAEAJwBsDAAAAQA4AAMABAmjCphLAFwABGgMAAABABwAaQwAAAEAGgBrDAAAAQAaAGoMAAABAB8AAS4ABAoFCQoABAAAAAA=.Bitemyshiney:BAEALgAECgMJBgABLgAECggJJQAFAKwRAA==.',
Bo='Boofaexe:BAECLgAFFH8GAAIGAAMJlBgNSAAFAQNoDAAAAgBhAGkMAAABAC8A6gwAAAMALAAGAAMJlBgNSAAFAQNoDAAAAgBhAGkMAAABAC8A6gwAAAMALAAuAAQKfx0AAgYABwm1H0U5AAYCAAYABwm1H0U5AAYCAAEuAAUUBAkMAAcAxxYA.',
Bw='Bwoom:BAEBLgAECn8YAAIIAAcJ6xhqKwCVAQdoDAAABgA4AGkMAAAEADoAawwAAAQAOgBqDAAAAgARAGwMAAABAC4A6gwAAAYARwBuDAAAAQBbAAgABwnrGGorAJUBB2gMAAAGADgAaQwAAAQAOgBrDAAABAA6AGoMAAACABEAbAwAAAEALgDqDAAABgBHAG4MAAABAFsAAS4ABRQECQwABwDHFgA=.',
Ca='Cantbearme:BAEALgAECgQJBwABLgAECggJJQAFAKwRAA==.',
Fe='Felrisen:BAEALgAECgEJAQABLgAFFAMJCQAJAF8GAA==.',
Fl='Flagmewillya:BAEBLgAECn8UAAMKAAUJrwtbRQC+AAVoDAAABgAkAGkMAAAFAB8AawwAAAQAHwBqDAAAAQAEAOoMAAAEAC4ACgAFCa8LW0UAvgAFaAwAAAQAJABpDAAABAAfAGsMAAADAB8AagwAAAEABADqDAAABAAuAAcAAwl2AuV9AC0AA2gMAAACAAkAaQwAAAEABwBrDAAAAQACAAEuAAQKCAklAAUArBEA.',
Fy='Fyrre:BAECLgAFFH8TAAIFAAYJQBeKAwBlAQZoDAAAAwBRAGkMAAADAFoAawwAAAIAOwBqDAAAAQAXAGwMAAACAA4A6gwAAAgAMwAFAAYJQBeKAwBlAQZoDAAAAwBRAGkMAAADAFoAawwAAAIAOwBqDAAAAQAXAGwMAAACAA4A6gwAAAgAMwAuAAQKf0AAAgUACQlSJM0DAFMDAAUACQlSJM0DAFMDAAAA.',
Gd='Gdkhan:BAEALgADCgcJEwABLgAFFAQJDgAKAPIZAA==.',
Il='Ilovemyself:BAEALgAECgYJEAABLgAECggJJQAFAKwRAA==.',
Jc='Jcmnk:BAEBLgAFFH8IAAILAAQJyRD3JgDoAARoDAAAAgArAGkMAAACACwAawwAAAIAMADqDAAAAgAiAAsABAnJEPcmAOgABGgMAAACACsAaQwAAAIALABrDAAAAgAwAOoMAAACACIAAAA=.',
Ji='Jingsho:BAEALgAECgMJBAAAAA==.',
Le='Leë:BAECLgAFFH8FAAIGAAIJiA/bhACEAAJoDAAAAwA+AOoMAAACABEABgACCYgP24QAhAACaAwAAAMAPgDqDAAAAgARAC4ABAp/GwAEDAAHCY8d8QoAHQIADAAGCUEg8QoAHQIABgAGCQUVjq0ACAEADQABCdsKv5cAMgAAAS4ABRQDCQYADgB1IQA=.',
Lo='Lotheril:BAEALgAFFAIJAgABLgAFFAMJCQAJAF8GAA==.',
Lu='Lunaadk:BAEALgADCgEJAQABLgAFFAUJHAAFAHkSAA==.',
Ma='Masamura:BAECLgAFFH8JAAIJAAMJXwaLmgC8AANoDAAABAAdAGkMAAABAAUA6gwAAAQADQAJAAMJXwaLmgC8AANoDAAABAAdAGkMAAABAAUA6gwAAAQADQAuAAQKfyMAAwkACAliGU1iAJIBAAkACAlcFU1iAJIBAA8ABQmFENILAP0AAAAA.',
Mi='Mimíkyu:BAECLgAFFH8GAAMQAAUJng3sGQBaAQVoDAAAAQAPAGkMAAABACEAawwAAAEAOABqDAAAAgAEAOoMAAABAD8AEAAFCZ4N7BkAWgEFaAwAAAEADwBpDAAAAQAhAGsMAAABADgAagwAAAEABADqDAAAAQA/AAcAAQkAAFI5AAAAAWoMAAABACYALgAECn8ZAAIHAAgJZCCRDABvAgAHAAgJZCCRDABvAgABLgAFFAUJGAALAIIeAA==.',
Mo='Moogledrake:BAEALgADCgcJBwABLgAECgQJBAAEAAAAAA==.Moogledrood:BAEALgAECgQJBAAAAA==.Morbingsage:BAEALgAECgcJEQABLgAFFAgJHAARAPocAA==.Mourningsage:BAECLgAFFH8cAAMRAAgJ+hxYDwD2AQhoDAAABgBaAGkMAAAFAFoAawwAAAUAXwBqDAAABAAwAGwMAAACAEQAbQwAAAEALQDqDAAABABVAG4MAAABACsAEQAHCdQeWA8A9gEHaAwAAAYAWgBpDAAABQBaAGsMAAACAF8AagwAAAMAMABsDAAAAgBEAOoMAAAEAFUAbgwAAAEAKwASAAMJwBRjDgCZAANrDAAAAwA8AGoMAAABAAYAbQwAAAEALQAuAAQKfywAAxEACQk7JV0IAD4DABEACQmoJF0IAD4DABIABwmLJWIDAEoCAAAA.',
Mu='Mudflapp:BAEALgADCgUJBAABLgAFFAQJDAAHAMcWAA==.',
Na='Naturegift:BAEALgAECgkJEgAAAA==.',
Ni='Nickbatum:BAEBLgAECn8ZAAMOAAkJVQ/hPQCKAQloDAAAAwAbAGkMAAAEACYAawwAAAQASgBqDAAABAAjAGwMAAACADwAbQwAAAIALADqDAAAAgAnAG4MAAACAAsAbwwAAAIAFQAOAAkJVQ/hPQCKAQloDAAAAwAbAGkMAAADACYAawwAAAMASgBqDAAAAgAjAGwMAAACADwAbQwAAAIALADqDAAAAgAnAG4MAAACAAsAbwwAAAIAFQATAAMJNAzLfQBZAANpDAAAAQAYAGsMAAABACYAagwAAAIALwAAAA==.',
Pe='Peterpikachu:BAEALgAECgkJAQABLgAECgkJEgAEAAAAAA==.',
Ra='Randomno:BAECLgAFFH8iAAMSAAgJoAPzCADkAAhoDAAABwAWAGkMAAAHABYAawwAAAYABgBqDAAABAAEAGwMAAACAAIAbQwAAAEAAADqDAAABgAHAG4MAAABAAIAEQAHCeUD5TEAVQEHaAwAAAUAFgBpDAAABQAWAGsMAAADAAYAagwAAAQABABsDAAAAgACAOoMAAACAAIAbgwAAAEAAgASAAUJFwLzCADkAAVoDAAAAgAFAGkMAAACAAcAawwAAAMABgBtDAAAAQAAAOoMAAAEAAcALgAECn8zAAQSAAkJ2RnHCgATAgASAAkJ8BLHCgATAgARAAkJyBMIVwDDAQAUAAYJhRqICgCVAQAAAA==.',
Sc='Sceptile:BAEBLgAFFH8KAAMVAAMJBhiDIQC4AANoDAAAAgBKAGkMAAACABkA6gwAAAYAVAAVAAMJKRSDIQC4AANoDAAAAgBKAGkMAAACABkA6gwAAAIANwAJAAEJMiFP3QBeAAHqDAAABABUAAEuAAUUBAkWABYA7B4A.',
Se='Señorpunchy:BAECLgAFFH8YAAQLAAUJgh69HgAoAQVoDAAABwBHAGkMAAAHAEgAawwAAAQASQBqDAAAAQBjAOoMAAAFAEkACwAECWQcvR4AKAEEaAwAAAQARwBpDAAABABIAGsMAAACAEkA6gwAAAQASQAWAAUJMhD4IwAFAQVoDAAAAwA0AGkMAAACABEAawwAAAIAPQBqDAAAAQAeAOoMAAABACMAFwABCeUL3xAAUAABaQwAAAEAHgAuAAQKfysABAsACAlBICAHAOgCAAsACAlBICAHAOgCABYABwmZGaQbALgBABcABAklE4RDAAkBAAAA.',
Sh='Shazàm:BAECLgAFFH8GAAIOAAMJdSFxKgAYAQNoDAAAAwBVAGkMAAABAFUA6gwAAAIAVQAOAAMJdSFxKgAYAQNoDAAAAwBVAGkMAAABAFUA6gwAAAIAVQAuAAQKfxoAAg4ABgmnHF01AMIBAA4ABgmnHF01AMIBAAAA.Sherkia:BAEALgADCggJFAABLgAECgYJGAAYADUUAA==.Sherko:BAEBLgAECn8YAAMYAAYJNRRrKQASAQZoDAAABwAtAGkMAAAFAEIAawwAAAUAQgBqDAAAAwA2AGwMAAABADAA6gwAAAMAIAAYAAUJFRJrKQASAQVoDAAABQAtAGkMAAADAEIAawwAAAMAJwBsDAAAAQAwAOoMAAACACAACAAFCfIP3l0AxQAFaAwAAAIAIwBpDAAAAgA3AGsMAAACAEIAagwAAAMANgDqDAAAAQAEAAAA.Shruggo:BAECLgAFFH8dAAILAAUJfyJ6DADwAQVoDAAACABeAGkMAAAIAFkAawwAAAUATwBqDAAAAQBSAOoMAAAHAF8ACwAFCX8iegwA8AEFaAwAAAgAXgBpDAAACABZAGsMAAAFAE8AagwAAAEAUgDqDAAABwBfAC4ABAp/NQACCwAJCaYiLAUAEQMACwAJCaYiLAUAEQMAAAA=.Shtkhan:BAECLgAFFH8OAAIKAAQJ8hllEAAqAQRoDAAABABQAGkMAAAEAEUAawwAAAIASQDqDAAABAAqAAoABAnyGWUQACoBBGgMAAAEAFAAaQwAAAQARQBrDAAAAgBJAOoMAAAEACoALgAECn9FAAMKAAkJxB9WBQD7AgAKAAkJxB9WBQD7AgAHAAQJKAv/VQCTAAAAAA==.',
Sk='Skankmane:BAECLgAFFH8MAAIHAAQJxxZXFgAbAQRoDAAABABQAGkMAAACAEcAawwAAAMALwDqDAAAAwAiAAcABAnHFlcWABsBBGgMAAAEAFAAaQwAAAIARwBrDAAAAwAvAOoMAAADACIALgAECn8yAAMHAAkJWyLPCwDGAgAHAAkJWyLPCwDGAgAQAAUJrQsGRADPAAAAAA==.',
St='Stormreign:BAECLgAFFH8HAAIJAAMJbw5PjgDRAANoDAAAAwBSAGkMAAABAAoA6gwAAAMAEQAJAAMJbw5PjgDRAANoDAAAAwBSAGkMAAABAAoA6gwAAAMAEQAuAAQKfyQAAgkACAm7FMlaAKQBAAkACAm7FMlaAKQBAAEuAAUUBAkMAAcAxxYA.',
Su='Sungrass:BAEBLgAECn8dAAIZAAkJ1RnIHwBDAgloDAAABABdAGkMAAAEAFQAawwAAAQAUwBqDAAAAwA/AGwMAAADAEYAbQwAAAIANADqDAAABABBAG4MAAAEADMAbwwAAAEAHgAZAAkJ1RnIHwBDAgloDAAABABdAGkMAAAEAFQAawwAAAQAUwBqDAAAAwA/AGwMAAADAEYAbQwAAAIANADqDAAABABBAG4MAAAEADMAbwwAAAEAHgAAAA==.',
Ta='Tapmepleasé:BAEBLgAECn8lAAIFAAgJrBHoVACOAQhoDAAABgBLAGkMAAAGADoAawwAAAYANQBqDAAABAAxAGwMAAADACoAbQwAAAIACwDqDAAABgA3AG4MAAAEABIABQAICawR6FQAjgEIaAwAAAYASwBpDAAABgA6AGsMAAAGADUAagwAAAQAMQBsDAAAAwAqAG0MAAACAAsA6gwAAAYANwBuDAAABAASAAAA.',
Ze='Zeigndeath:BAEBLgAFFH8GAAMFAAMJRRYgUADgAANoDAAAAgA/AGkMAAACADMA6gwAAAIAOAAFAAMJ5REgUADgAANoDAAAAQAdAGkMAAABADMA6gwAAAIAOAAaAAIJchOvIgCeAAJoDAAAAQA/AGkMAAABACQAAAA=.',
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
