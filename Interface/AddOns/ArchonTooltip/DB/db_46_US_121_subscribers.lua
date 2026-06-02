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

local lookup = {'Monk-Windwalker','Rogue-Subtlety','DeathKnight-Blood','DeathKnight-Unholy','Monk-Brewmaster','Monk-Mistweaver','Hunter-BeastMastery','Paladin-Retribution','Paladin-Holy','Shaman-Elemental','Shaman-Restoration','Unknown-Unknown','Paladin-Protection','Mage-Frost','Warlock-Demonology','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Outlaw','Rogue-Assassination','Druid-Guardian','Druid-Balance','Evoker-Preservation','Druid-Feral','Warrior-Protection','Priest-Shadow','Priest-Discipline','Priest-Holy','Hunter-Marksmanship','Hunter-Survival',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=46,date='2026-06-01',data={As='Astaren:BAEALgAECggJEAAAAA==.',
Av='Avenmonk:BAECLgAFFH8gAAIBAAcJTRyLAgADAgdoDAAACQBhAGkMAAAFAFcAawwAAAYAPQBqDAAAAgAVAG0MAAABADgA6gwAAAgAUQBuDAAAAQAxAAEABwlNHIsCAAMCB2gMAAAJAGEAaQwAAAUAVwBrDAAABgA9AGoMAAACABUAbQwAAAEAOADqDAAACABRAG4MAAABADEALgAECn8yAAIBAAkJTyRfAQCiAwABAAkJTyRfAQCiAwAAAA==.Avenstealth:BAEBLgAECn8kAAICAAkJoBR7FwDKAQloDAAABQBLAGkMAAAFAEkAawwAAAUAOgBqDAAABQBKAGwMAAAFAD8AbQwAAAIAGQDqDAAABgBIAG4MAAACACMAbwwAAAEAEgACAAkJoBR7FwDKAQloDAAABQBLAGkMAAAFAEkAawwAAAUAOgBqDAAABQBKAGwMAAAFAD8AbQwAAAIAGQDqDAAABgBIAG4MAAACACMAbwwAAAEAEgABLgAFFAcJIAABAE0cAA==.',
Az='Azchath:BAEALgAFFAIJAgAAAQ==.',
Br='Bryl:BAECLgAFFH8NAAIDAAUJcxwFEQBCAQVoDAAAAgBYAGkMAAABACYAawwAAAEARABqDAAABAA5AOoMAAAFAF8AAwAFCXMcBREAQgEFaAwAAAIAWABpDAAAAQAmAGsMAAABAEQAagwAAAQAOQDqDAAABQBfAC4ABAp/IAADAwAJCdseqwYAygIAAwAJCdseqwYAygIABAAHCWMRHHEApQEAAS4ABRQFCRcABQBlIwA=.Brylic:BAECLgAFFH8XAAMFAAUJZSMuCADZAQVoDAAABgBYAGkMAAAHAGEAawwAAAUAWQBsDAAAAgBcAOoMAAADAFUABQAFCbMgLggA2QEFaAwAAAYAWABpDAAABwBhAGsMAAAFAFkAbAwAAAIAXADqDAAAAQAzAAEAAQl3ITUxAGIAAeoMAAACAFUALgAECn8mAAMBAAgJOSMkBgAfAwABAAgJJiEkBgAfAwAFAAgJqiIyCAACAwAAAA==.',
Ca='Camreon:BAEALgAFFAEJAgAAAA==.Captpando:BAEALgAECgQJBAABLgAFFAgJDAAGAD0dAA==.',
Ce='Cenitarius:BAEALgADCgcJBwABLgAECgkJMgAHAE4lAA==.',
Cm='Cmenstabber:BAECLgAFFH8IAAICAAMJCQfbJwC6AANoDAAAAwARAGkMAAABAAEA6gwAAAQAIwACAAMJCQfbJwC6AANoDAAAAwARAGkMAAABAAEA6gwAAAQAIwAuAAQKfyoAAgIACQmbFfUPABoCAAIACQmbFfUPABoCAAAA.',
Da='Darkorin:BAECLgAFFH8PAAIIAAUJxyRWFwCJAQVoDAAABgBhAGkMAAACAGIAawwAAAIAVgBqDAAAAQA5AOoMAAAEAF8ACAAFCcckVhcAiQEFaAwAAAYAYQBpDAAAAgBiAGsMAAACAFYAagwAAAEAOQDqDAAABABfAC4ABAp/LQADCAAJCYklswYAZQMACAAICUsmswYAZQMACQACCcsORIEAOAAAAAA=.',
Du='Duskorin:BAEBLgAFFH8IAAMKAAMJ5Q/lNwCIAANoDAAAAwBGAOoMAAAEAB8AbgwAAAEAEwAKAAIJDQrlNwCIAALqDAAAAQAfAG4MAAABABMACwACCSoTN1oAdwACaAwAAAMALwDqDAAAAwAyAAEuAAUUBQkPAAgAxyQA.',
Fi='Fishybrew:BAEBLgAECn8tAAIFAAgJYyK9BwCqAghoDAAACQBaAGkMAAAIAFsAawwAAAcAUgBqDAAABgBYAGwMAAAFAFAAbQwAAAEAVQDqDAAABwBdAG4MAAACAF0ABQAICWMivQcAqgIIaAwAAAkAWgBpDAAACABbAGsMAAAHAFIAagwAAAYAWABsDAAABQBQAG0MAAABAFUA6gwAAAcAXQBuDAAAAgBdAAEuAAQKBgkGAAwAAAAA.',
Fl='Fleasfordays:BAEALgAECgIJAgABLgAFFAMJCAACAAkHAA==.',
Fo='Foxblade:BAEALgAECgcJDQABLgAECgcJFwAJADwVAA==.Foxleaf:BAEALgAECgEJAQABLgAECgcJFwAJADwVAA==.Foxorcism:BAEBLgAECn8XAAQJAAcJPBWIMACFAQdoDAAABABSAGkMAAAEADEAawwAAAQATABqDAAABAA3AGwMAAACAB0AbQwAAAEABADqDAAABABSAAkABgl5GIgwAIUBBmgMAAADAFIAaQwAAAMAMQBrDAAAAwBMAGoMAAAEADcAbAwAAAIAHQDqDAAABABSAAgAAwl9B4E2AVwAA2gMAAABACoAaQwAAAEABQBrDAAAAQAJAA0AAQn6A8FNACcAAW0MAAABAAoAAAA=.Foxox:BAEBLgAECn8XAAIOAAYJExpCbgCHAQZoDAAABwBKAGkMAAAFAEIAawwAAAQAPgBsDAAAAwBNAG0MAAABADIA6gwAAAMARQAOAAYJExpCbgCHAQZoDAAABwBKAGkMAAAFAEIAawwAAAQAPgBsDAAAAwBNAG0MAAABADIA6gwAAAMARQABLgAECgcJFwAJADwVAA==.',
Fr='Fries:BAEALgAECgcJCgABLgAFFAQJBwAPAKYPAA==.Frip:BAEALgAECgIJAgABLgAECgkJMgAHAE4lAA==.',
Ga='Gardenweed:BAEBLgAECn8hAAIIAAkJVgmZgABWAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQAIAAkJVgmZgABWAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQAAAA==.',
Gr='Grimmyb:BAECLgAFFH8LAAMQAAMJABpLUgDaAANoDAAAAwAxAGkMAAADAEAA6gwAAAUAVQAQAAMJhhZLUgDaAANoDAAAAwAxAGkMAAADAEAA6gwAAAQAOgARAAEJWiGWDABZAAHqDAAAAQBVAC4ABAp/JwADEQAJCZgh8gEA8QIAEQAICdsh8gEA8QIAEAAJCaEbNjoAygEAAS4ABRQICR8AEQBMIAA=.Grìmbles:BAECLgAFFH8fAAIRAAgJTCASAAAoAghoDAAABQBiAGkMAAAIAGEAawwAAAgAZABqDAAAAQBQAGwMAAADAFgAbQwAAAEAZADqDAAABABYAG4MAAABAAUAEQAICUwgEgAAKAIIaAwAAAUAYgBpDAAACABhAGsMAAAIAGQAagwAAAEAUABsDAAAAwBYAG0MAAABAGQA6gwAAAQAWABuDAAAAQAFAC4ABAp/HQACEQAJCZ0lOAAAlwMAEQAJCZ0lOAAAlwMAAAA=.',
Gu='Guthyne:BAEALgAECgMJBgABLgAECgkJLwASADYmAA==.Guthynn:BAEBLgAECn8vAAMSAAkJNiYdAAB7AwloDAAACgBhAGkMAAAHAGIAawwAAAcAYgBqDAAABABiAGwMAAADAGIAbQwAAAQAYgDqDAAABgBjAG4MAAAFAGEAbwwAAAEAXgASAAkJNiYdAAB7AwloDAAABgBhAGkMAAAGAGIAawwAAAYAYgBqDAAAAwBiAGwMAAACAGIAbQwAAAQAYgDqDAAABgBjAG4MAAAFAGEAbwwAAAEAXgATAAUJPyHrCQCMAQVoDAAABABXAGkMAAABAFMAawwAAAEAXwBqDAAAAQBfAGwMAAABAEoAAAA=.',
Gw='Gwimbles:BAECLgAFFH8OAAIDAAMJyhCIDACtAANoDAAAAwA7AGoMAAAEABIA6gwAAAcAGgADAAMJyhCIDACtAANoDAAAAwA7AGoMAAAEABIA6gwAAAcAGgAuAAQKfy0AAgMACQmMHiYHAL4CAAMACQmMHiYHAL4CAAEuAAUUCAkfABEATCAA.Gwìmbles:BAEBLgAFFH8IAAMUAAUJ2QVMLABDAAVoDAAAAwA6AGkMAAABAAAAawwAAAEAAABqDAAAAQABAOoMAAACAAEAFAACCagLTCwAQwACaAwAAAIAOgDqDAAAAgABABUABAkKACxMAAMABGgMAAABAAAAaQwAAAEAAABrDAAAAQAAAGoMAAABAAEAAS4ABRQICR8AEQBMIAA=.',
Ir='Irro:BAEALgAECgYJCwABLgAECgkJLgALADwdAA==.Irrogenia:BAEBLgAECn8uAAMLAAkJPB1kDgDNAgloDAAABwBgAGkMAAAHAFUAawwAAAYAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgALAAkJPB1kDgDNAgloDAAABwBgAGkMAAAGAFUAawwAAAUAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgAKAAIJ/QpAgABXAAJpDAAAAQAiAGsMAAABABUAAAA=.',
Ja='Jarik:BAEALgAECgQJDAABLgAECgkJMgAHAE4lAA==.',
Li='Lidariel:BAEALgAECggJDwABLgAFFAQJCwAWAP8PAA==.Lidathra:BAECLgAFFH8LAAIWAAQJ/w+mFwAEAQRoDAAABAAgAGkMAAADAC8AawwAAAEAIQDqDAAAAwAyABYABAn/D6YXAAQBBGgMAAAEACAAaQwAAAMALwBrDAAAAQAhAOoMAAADADIALgAECn8sAAIWAAkJ5hWmCgAlAgAWAAkJ5hWmCgAlAgAAAA==.Lidiosa:BAEBLgAECn8lAAIOAAgJ5Bv8MQA8AghoDAAABwBeAGkMAAAFAE0AawwAAAUAPQBqDAAABAA9AGwMAAAEAEoAbQwAAAIANwDqDAAACQA8AG4MAAABAEwADgAICeQb/DEAPAIIaAwAAAcAXgBpDAAABQBNAGsMAAAFAD0AagwAAAQAPQBsDAAABABKAG0MAAACADcA6gwAAAkAPABuDAAAAQBMAAEuAAUUBAkLABYA/w8A.Lidishi:BAEALgAECgYJCAABLgAFFAQJCwAWAP8PAA==.Lidizine:BAEALgADCggJDAABLgAFFAQJCwAWAP8PAA==.',
Lo='Lochru:BAEBLgAECn89AAIXAAkJbSJzAQAhAwloDAAACQBhAGkMAAAIAFgAawwAAAkAUgBqDAAABwBiAGwMAAAHAF4AbQwAAAYATwDqDAAACABfAG4MAAAFAFQAbwwAAAIAUwAXAAkJbSJzAQAhAwloDAAACQBhAGkMAAAIAFgAawwAAAkAUgBqDAAABwBiAGwMAAAHAF4AbQwAAAYATwDqDAAACABfAG4MAAAFAFQAbwwAAAIAUwAAAA==.',
Ma='Makoto:BAEBLgAECn8aAAIYAAcJlR3sCwBOAgdoDAAABQBaAGkMAAAFAFcAawwAAAUAWABqDAAABAA7AGwMAAADAE4AbQwAAAEAGgDqDAAAAwBTABgABwmVHewLAE4CB2gMAAAFAFoAaQwAAAUAVwBrDAAABQBYAGoMAAAEADsAbAwAAAMATgBtDAAAAQAaAOoMAAADAFMAAAA=.',
Mi='Mistorin:BAEALgAECgMJAwABLgAFFAUJDwAIAMckAA==.',
Na='Nalfein:BAEALgAECggJDAABLgAECgkJMgAHAE4lAA==.',
Ne='Neodefender:BAECLgAFFH8pAAIJAAYJKCZIAwCEAgZoDAAACgBjAGkMAAAJAF4AawwAAAcAYwBqDAAABQBjAGwMAAADAF4A6gwAAAcAYQAJAAYJKCZIAwCEAgZoDAAACgBjAGkMAAAJAF4AawwAAAcAYwBqDAAABQBjAGwMAAADAF4A6gwAAAcAYQAuAAQKfzIAAgkACQnnJvwAAIgDAAkACQnnJvwAAIgDAAAA.',
No='Nosferratu:BAECLgAFFH8lAAMZAAcJvh81AgBfAgdoDAAACQBjAGkMAAAGAF4AawwAAAYAWwBqDAAABQAcAGwMAAACAD0A6gwAAAgAYwBuDAAAAQAoABkABwm+HzUCAF8CB2gMAAAJAGMAaQwAAAUAXgBrDAAABQBbAGoMAAAFABwAbAwAAAIAPQDqDAAACABjAG4MAAABACgAGgACCTgHMDQAhgACaQwAAAEADwBrDAAAAQAVAC4ABAp/QQACGQAJCYQmmwAAeQMAGQAJCYQmmwAAeQMAAAA=.',
Ny='Nyfaria:BAECLgAFFH8cAAIFAAUJuxmeFwBHAQVoDAAACABLAGkMAAAHADkAawwAAAQALABqDAAAAwBJAOoMAAAGAFYABQAFCbsZnhcARwEFaAwAAAgASwBpDAAABwA5AGsMAAAEACwAagwAAAMASQDqDAAABgBWAC4ABAp/LAACBQAJCQ4kqQEARwMABQAJCQ4kqQEARwMAAAA=.',
Oo='Ookook:BAEALgADCgYJBgABLgAFFAgJHwARAEwgAA==.',
Or='Orsp:BAECLgAFFH8fAAQZAAcJQhjXBgDSAQdoDAAABwBeAGkMAAAFAFEAawwAAAQATABqDAAABABHAGwMAAACAAIAbQwAAAEAGwDqDAAACABaABkABgnwHNcGANIBBmgMAAAHAF4AaQwAAAUAUQBrDAAABABMAGoMAAACAEcAbQwAAAEAGwDqDAAACABaABoAAgk8AT4WAH4AAmoMAAABAAAAbAwAAAIABQAbAAEJRgHuFABBAAFqDAAAAQADAC4ABAp/KgAEGQAJCTcjOwUAPQMAGQAJCTcjOwUAPQMAGwADCcoKCGUAmQAAGgADCcEZo1sAYgAAAAA=.Orspp:BAECLgAFFH8GAAMZAAMJfxITJgCeAANoDAAAAgBAAGkMAAACADsA6gwAAAIAEQAZAAIJOxgTJgCeAAJoDAAAAgBAAGkMAAACADsAGgABCQkVRz8AQgAB6gwAAAIANQAuAAQKfxwABBkACAkoGm4hAMwBABkACAkoGm4hAMwBABsABgmlCCJJABQBABoAAQm1DcNVADYAAAEuAAUUBwkfABkAQhgA.',
Pa='Pakk:BAEBLgAECn8uAAIDAAgJoiBHCACDAghoDAAACQBeAGkMAAAIAFIAawwAAAcATwBqDAAABgBQAGwMAAAGAFQAbQwAAAEAPwDqDAAABgBdAG4MAAADAFYAAwAICaIgRwgAgwIIaAwAAAkAXgBpDAAACABSAGsMAAAHAE8AagwAAAYAUABsDAAABgBUAG0MAAABAD8A6gwAAAYAXQBuDAAAAwBWAAAA.Pandoken:BAEBLgAFFH8MAAIGAAUJPR1zEgCrAQVoDAAAAwBNAGkMAAADAFEAawwAAAMAUgBqDAAAAQBEAOoMAAACAEAABgAFCT0dcxIAqwEFaAwAAAMATQBpDAAAAwBRAGsMAAADAFIAagwAAAEARADqDAAAAgBAAAAA.Pandotides:BAEALgAFFAUJAgABLgAFFAgJDAAGAD0dAA==.Papadefensve:BAEALgAECgYJBgAAAA==.',
Pr='Priff:BAEBLgAECn8yAAQHAAkJTiXvEgCoAgloDAAACABiAGkMAAAHAFwAawwAAAcAXQBqDAAABQBdAGwMAAAGAFQAbQwAAAUAYwDqDAAABwBgAG4MAAADAGMAbwwAAAIAYgAHAAgJnyXvEgCoAghoDAAAAwBhAGkMAAAEAFgAawwAAAMAXQBqDAAAAgBdAG0MAAAEAGMA6gwAAAIAYABuDAAAAwBjAG8MAAACAGIAHAAHCfchXxgAagIHaAwAAAMAUwBpDAAAAwBcAGsMAAADAEoAagwAAAIAKABsDAAABABUAG0MAAABAF8A6gwAAAMAWgAdAAUJ5SEhJQBoAQVoDAAAAgBiAGsMAAABAEoAagwAAAEAUwBsDAAAAgBUAOoMAAACAFkAAAA=.Priffraff:BAEALgAECgUJBQABLgAECgkJMgAHAE4lAA==.',
Ra='Razamon:BAEBLgAECn8rAAMLAAkJMSHJFwB2AgloDAAABgBcAGkMAAAFAFMAawwAAAUASgBqDAAABQBUAGwMAAAFAF4AbQwAAAQAVgDqDAAABQBRAG4MAAAFAF4AbwwAAAMASAALAAkJMSHJFwB2AgloDAAAAgBcAGkMAAABAFMAawwAAAIASgBqDAAAAwBUAGwMAAAEAF4AbQwAAAQAVgDqDAAAAgBRAG4MAAAEAF4AbwwAAAMASAAKAAcJgxiJLgCpAQdoDAAABABSAGkMAAAEAEsAawwAAAMAOABqDAAAAgA/AGwMAAABADYA6gwAAAMASwBuDAAAAQAfAAAA.',
Re='Recurse:BAEALgAFFAIJBAABLgAFFAkJKQAPAMYYAA==.',
Ri='Ripwwmonk:BAEALgADCgcJBwABLgAFFAUJFwAFAGUjAA==.',
Ro='Roukedhh:BAECLgAFFH8RAAIQAAYJcRdoJQBvAQZoDAAABABSAGkMAAADAEoAawwAAAIAEgBqDAAAAQADAG0MAAABAD8A6gwAAAYAPQAQAAYJcRdoJQBvAQZoDAAABABSAGkMAAADAEoAawwAAAIAEgBqDAAAAQADAG0MAAABAD8A6gwAAAYAPQAuAAQKfx4AAhAACAmnIZAWAM8CABAACAmnIZAWAM8CAAAA.',
Ru='Runehaven:BAEBLgAECn8WAAMEAAYJHx06ggBOAQZoDAAABgBUAGkMAAAEAFQAawwAAAQAUABqDAAAAgAwAGwMAAADADQA6gwAAAMARgAEAAYJHx06ggBOAQZoDAAABABUAGkMAAADAFQAawwAAAMAUABqDAAAAQAwAGwMAAABADQA6gwAAAIARgADAAYJggrdNQCrAAZoDAAAAgAnAGkMAAABABUAawwAAAEAEQBqDAAAAQAfAGwMAAACACUA6gwAAAEAEgABLgAECgYJFgAEAB8dAA==.',
Sa='Sargala:BAEBLgAECn8sAAMHAAgJJhr8KQAjAghoDAAACQBLAGkMAAAIAEkAawwAAAoANwBqDAAABQBKAGwMAAAEAFIAbQwAAAEAFwDqDAAABgBWAG4MAAABAEcABwAICSYa/CkAIwIIaAwAAAgASwBpDAAABwBJAGsMAAAJADcAagwAAAQASgBsDAAABABSAG0MAAABABcA6gwAAAYAVgBuDAAAAQBHAB0ABAnnBX5FAJMABGgMAAABABMAaQwAAAEAEgBrDAAAAQAHAGoMAAABABMAAAA=.',
Sc='Scootybooty:BAEALgAECgUJBQAAAA==.Scootyclap:BAEALgADCgQJBAABLgAECgUJBQAMAAAAAA==.Scootypriest:BAEALgADCggJCAABLgAECgUJBQAMAAAAAA==.Scootysnack:BAEALgADCgcJEAABLgAECgUJBQAMAAAAAA==.Scussy:BAEALgADCgcJBwABLgAECgUJBQAMAAAAAA==.',
Sm='Smoothz:BAEALgAECgcJDAABLgAFFAUJBQAUABEFAA==.',
Th='Thez:BAEALgAECgEJAQABLgAECgkJJwAYAAgdAA==.Thezdin:BAEBLgAECn8nAAIYAAkJCB30CQBDAgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAADAEsAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAYAAkJCB30CQBDAgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAADAEsAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAAAA==.Thezfu:BAEALgAECgEJAwABLgAECgkJJwAYAAgdAA==.',
Ve='Velohm:BAEBLgAECn8VAAMGAAYJSQ5sVADvAAZoDAAABwBXAGkMAAAEABEAawwAAAMABABqDAAAAwAFAGwMAAABACcA6gwAAAMAQQAGAAYJSQ5sVADvAAZoDAAABQBXAGkMAAACABEAawwAAAEABABqDAAAAQAFAGwMAAABACcA6gwAAAIAQQABAAUJSAhoWACbAAVoDAAAAgAjAGkMAAACABMAawwAAAIADQBqDAAAAgAmAOoMAAABAA8AAAA=.',
Zi='Zick:BAEALgAFFAcJAQAAAA==.Zikker:BAEALgADCgcJBwABLgAFFAcJAQAMAAAAAA==.',
Zo='Zoe:BAECLgAFFH8YAAIFAAcJXx4IAwBNAgdoDAAABQBZAGkMAAAFAGMAawwAAAQAUgBsDAAAAQAlAG0MAAABAF8A6gwAAAcAWgBuDAAAAQAwAAUABwlfHggDAE0CB2gMAAAFAFkAaQwAAAUAYwBrDAAABABSAGwMAAABACUAbQwAAAEAXwDqDAAABwBaAG4MAAABADAALgAECn8vAAIFAAgJVyaLBADyAgAFAAgJVyaLBADyAgAAAA==.Zogle:BAEBLgAFFH8JAAIDAAUJGRNNGwDmAAVoDAAAAQA3AGkMAAABAC4AawwAAAEAPABqDAAABQAcAOoMAAABACEAAwAFCRkTTRsA5gAFaAwAAAEANwBpDAAAAQAuAGsMAAABADwAagwAAAUAHADqDAAAAQAhAAEuAAUUBwkYAAUAXx4A.Zoog:BAEALgAECggJEwABLgAFFAcJGAAFAF8eAA==.',
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
