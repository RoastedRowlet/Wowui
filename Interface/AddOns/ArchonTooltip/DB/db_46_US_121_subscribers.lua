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

local lookup = {'Monk-Windwalker','Rogue-Subtlety','DeathKnight-Blood','DeathKnight-Unholy','Monk-Brewmaster','Monk-Mistweaver','Hunter-BeastMastery','Paladin-Retribution','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Mage-Frost','Paladin-Protection','Warlock-Demonology','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Outlaw','Rogue-Assassination','Druid-Guardian','Druid-Balance','Evoker-Preservation','Druid-Feral','Warrior-Protection','Priest-Shadow','Priest-Discipline','Priest-Holy','Hunter-Marksmanship','Hunter-Survival',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=46,date='2026-06-08',data={As='Astaren:BAEALgAECgkJEgAAAA==.',
Av='Avenmonk:BAECLgAFFH8gAAIBAAcJTRxOAwD9AQdoDAAACQBhAGkMAAAFAFcAawwAAAYAPQBqDAAAAgAVAG0MAAABADgA6gwAAAgAUQBuDAAAAQAxAAEABwlNHE4DAP0BB2gMAAAJAGEAaQwAAAUAVwBrDAAABgA9AGoMAAACABUAbQwAAAEAOADqDAAACABRAG4MAAABADEALgAECn8yAAIBAAkJTyRfAQCiAwABAAkJTyRfAQCiAwAAAA==.Avenstealth:BAEBLgAECn8kAAICAAkJoBTyGADIAQloDAAABQBLAGkMAAAFAEkAawwAAAUAOgBqDAAABQBKAGwMAAAFAD8AbQwAAAIAGQDqDAAABgBIAG4MAAACACMAbwwAAAEAEgACAAkJoBTyGADIAQloDAAABQBLAGkMAAAFAEkAawwAAAUAOgBqDAAABQBKAGwMAAAFAD8AbQwAAAIAGQDqDAAABgBIAG4MAAACACMAbwwAAAEAEgABLgAFFAcJIAABAE0cAA==.',
Az='Azchath:BAEALgAFFAIJAgAAAQ==.',
Br='Bryl:BAECLgAFFH8PAAIDAAYJ2Bd9DwBzAQZoDAAAAgBYAGkMAAABACYAawwAAAEARABqDAAABAA5AG0MAAABAA0A6gwAAAYAXwADAAYJ2Bd9DwBzAQZoDAAAAgBYAGkMAAABACYAawwAAAEARABqDAAABAA5AG0MAAABAA0A6gwAAAYAXwAuAAQKfyAAAwMACQnbHqsGAMoCAAMACQnbHqsGAMoCAAQABwljERxxAKUBAAAA.Brylic:BAECLgAFFH8XAAMFAAUJZSMCCgDTAQVoDAAABgBYAGkMAAAHAGEAawwAAAUAWQBsDAAAAgBcAOoMAAADAFUABQAFCbMgAgoA0wEFaAwAAAYAWABpDAAABwBhAGsMAAAFAFkAbAwAAAIAXADqDAAAAQAzAAEAAQl3IRo2AGAAAeoMAAACAFUALgAECn8mAAMBAAgJOSMkBgAfAwABAAgJJiEkBgAfAwAFAAgJqiIyCAACAwABLgAFFAYJDwADANgXAA==.',
Ca='Camreon:BAEALgAFFAEJAgAAAA==.Captpando:BAEALgAECgQJBAABLgAFFAgJEQAGAFIdAA==.',
Ce='Cenitarius:BAEALgADCgcJBwABLgAECgkJOQAHAOYlAA==.',
Cm='Cmenstabber:BAECLgAFFH8KAAICAAMJbAdIKgDDAANoDAAAAwARAGkMAAACAAQA6gwAAAUAIwACAAMJbAdIKgDDAANoDAAAAwARAGkMAAACAAQA6gwAAAUAIwAuAAQKfyoAAgIACQmbFTkRABgCAAIACQmbFTkRABgCAAAA.',
Da='Darkorin:BAECLgAFFH8PAAIIAAUJxySoHQB/AQVoDAAABgBhAGkMAAACAGIAawwAAAIAVgBqDAAAAQA5AOoMAAAEAF8ACAAFCcckqB0AfwEFaAwAAAYAYQBpDAAAAgBiAGsMAAACAFYAagwAAAEAOQDqDAAABABfAC4ABAp/LQADCAAJCYklswYAZQMACAAICUsmswYAZQMACQACCcsOVYYANgAAAAA=.',
Du='Duskorin:BAEBLgAFFH8KAAMKAAQJwhXXSQC4AARoDAAAAwAvAGwMAAABACQA6gwAAAUAMgBuDAAAAQBYAAoAAwmJEddJALgAA2gMAAADAC8AbAwAAAEAJADqDAAAAwAyAAsAAgnND9I6AJIAAuoMAAACAD0AbgwAAAEAEwABLgAFFAUJDwAIAMckAA==.',
Fi='Fishybrew:BAEBLgAECn8tAAIFAAgJYyJMCACoAghoDAAACQBaAGkMAAAIAFsAawwAAAcAUgBqDAAABgBYAGwMAAAFAFAAbQwAAAEAVQDqDAAABwBdAG4MAAACAF0ABQAICWMiTAgAqAIIaAwAAAkAWgBpDAAACABbAGsMAAAHAFIAagwAAAYAWABsDAAABQBQAG0MAAABAFUA6gwAAAcAXQBuDAAAAgBdAAEuAAQKBgkGAAwAAAAA.',
Fl='Fleasfordays:BAEALgAECgIJAgABLgAFFAMJCgACAGwHAA==.',
Fo='Foxblade:BAEALgAECgcJDQABLgAECgcJGgANANgWAA==.Foxleaf:BAEALgAECgEJAQABLgAECgcJGgANANgWAA==.Foxorcism:BAEBLgAECn8XAAQJAAcJPBV3MgCDAQdoDAAABABSAGkMAAAEADEAawwAAAQATABqDAAABAA3AGwMAAACAB0AbQwAAAEABADqDAAABABSAAkABgl5GHcyAIMBBmgMAAADAFIAaQwAAAMAMQBrDAAAAwBMAGoMAAAEADcAbAwAAAIAHQDqDAAABABSAAgAAwl9B4A9AWMAA2gMAAABACoAaQwAAAEABQBrDAAAAQAJAA4AAQn6A4NSACQAAW0MAAABAAoAAS4ABAoHCRoADQDYFgA=.Foxox:BAEBLgAECn8aAAINAAcJ2BZPZQCvAQdoDAAABwBKAGkMAAAFAEIAawwAAAQAPgBsDAAABABNAG0MAAACADMA6gwAAAMARQBuDAAAAQAHAA0ABwnYFk9lAK8BB2gMAAAHAEoAaQwAAAUAQgBrDAAABAA+AGwMAAAEAE0AbQwAAAIAMwDqDAAAAwBFAG4MAAABAAcAAAA=.',
Fr='Fries:BAEALgAFFAMJBAABLgAFFAQJBwAPAKYPAA==.Frip:BAEALgAECgIJAgABLgAECgkJOQAHAOYlAA==.',
Ga='Gardenweed:BAEBLgAECn8hAAIIAAkJVglzgwBfAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQAIAAkJVglzgwBfAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQAAAA==.',
Gr='Grimmyb:BAECLgAFFH8LAAMQAAMJABogWgDRAANoDAAAAwAxAGkMAAADAEAA6gwAAAUAVQAQAAMJhhYgWgDRAANoDAAAAwAxAGkMAAADAEAA6gwAAAQAOgARAAEJWiH+DQBYAAHqDAAAAQBVAC4ABAp/JwADEQAJCZgh8gEA8QIAEQAICdsh8gEA8QIAEAAJCaEbzD0AyAEAAS4ABRQJCSAAEQCYHQA=.Grìmbles:BAECLgAFFH8gAAIRAAkJmB0SAAAoAgloDAAABQBiAGkMAAAIAGEAawwAAAgAZABqDAAAAQBQAGwMAAADAFgAbQwAAAEAZADqDAAABABYAG4MAAABAAUAbwwAAAEAGwARAAkJmB0SAAAoAgloDAAABQBiAGkMAAAIAGEAawwAAAgAZABqDAAAAQBQAGwMAAADAFgAbQwAAAEAZADqDAAABABYAG4MAAABAAUAbwwAAAEAGwAuAAQKfx0AAhEACQmdJTgAAJcDABEACQmdJTgAAJcDAAAA.',
Gu='Guthyne:BAEALgAECgMJBgABLgAECgkJLwASADYmAA==.Guthynn:BAEBLgAECn8vAAMSAAkJNiYjAAB4AwloDAAACgBhAGkMAAAHAGIAawwAAAcAYgBqDAAABABiAGwMAAADAGIAbQwAAAQAYgDqDAAABgBjAG4MAAAFAGEAbwwAAAEAXgASAAkJNiYjAAB4AwloDAAABgBhAGkMAAAGAGIAawwAAAYAYgBqDAAAAwBiAGwMAAACAGIAbQwAAAQAYgDqDAAABgBjAG4MAAAFAGEAbwwAAAEAXgATAAUJPyFbCgCJAQVoDAAABABXAGkMAAABAFMAawwAAAEAXwBqDAAAAQBfAGwMAAABAEoAAAA=.',
Gw='Gwimbles:BAECLgAFFH8OAAIDAAMJyhCIDACtAANoDAAAAwA7AGoMAAAEABIA6gwAAAcAGgADAAMJyhCIDACtAANoDAAAAwA7AGoMAAAEABIA6gwAAAcAGgAuAAQKfy0AAgMACQmMHiYHAL4CAAMACQmMHiYHAL4CAAEuAAUUCQkgABEAmB0A.Gwìmbles:BAEBLgAFFH8IAAMUAAUJ2QUbMwBBAAVoDAAAAwA6AGkMAAABAAAAawwAAAEAAABqDAAAAQABAOoMAAACAAEAFAACCagLGzMAQQACaAwAAAIAOgDqDAAAAgABABUABAkKALRSAAMABGgMAAABAAAAaQwAAAEAAABrDAAAAQAAAGoMAAABAAEAAS4ABRQJCSAAEQCYHQA=.',
Ir='Irro:BAEALgAECgYJCwABLgAECgkJLgAKADwdAA==.Irrogenia:BAEBLgAECn8uAAMKAAkJPB29DwDLAgloDAAABwBgAGkMAAAHAFUAawwAAAYAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgAKAAkJPB29DwDLAgloDAAABwBgAGkMAAAGAFUAawwAAAUAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgALAAIJ/QpphgBXAAJpDAAAAQAiAGsMAAABABUAAAA=.Irrowen:BAEALgAECgYJBgABLgAECgkJLgAKADwdAA==.',
Ja='Jarik:BAEALgAECgQJDAABLgAECgkJOQAHAOYlAA==.',
Li='Lidariel:BAEALgAECggJDwABLgAFFAQJCwAWAP8PAA==.Lidathra:BAECLgAFFH8LAAIWAAQJ/w9lGQDtAARoDAAABAAgAGkMAAADAC8AawwAAAEAIQDqDAAAAwAyABYABAn/D2UZAO0ABGgMAAAEACAAaQwAAAMALwBrDAAAAQAhAOoMAAADADIALgAECn8sAAIWAAkJ5hUSCwAmAgAWAAkJ5hUSCwAmAgAAAA==.Lidiosa:BAEBLgAECn8nAAINAAkJdhocIwCMAgloDAAABwBeAGkMAAAFAE0AawwAAAUAPQBqDAAABAA9AGwMAAAEAEoAbQwAAAIANwDqDAAACQA8AG4MAAACAEwAbwwAAAEAKgANAAkJdhocIwCMAgloDAAABwBeAGkMAAAFAE0AawwAAAUAPQBqDAAABAA9AGwMAAAEAEoAbQwAAAIANwDqDAAACQA8AG4MAAACAEwAbwwAAAEAKgABLgAFFAQJCwAWAP8PAA==.Lidishi:BAEALgAECgYJCQABLgAFFAQJCwAWAP8PAA==.Lidizine:BAEALgADCggJDAABLgAFFAQJCwAWAP8PAA==.',
Lo='Lochru:BAEBLgAECn9GAAIXAAkJ4yMZAQBIAwloDAAACgBhAGkMAAAJAFgAawwAAAoAUgBqDAAACABiAGwMAAAIAF4AbQwAAAcAWQDqDAAACQBfAG4MAAAGAF8AbwwAAAMAWwAXAAkJ4yMZAQBIAwloDAAACgBhAGkMAAAJAFgAawwAAAoAUgBqDAAACABiAGwMAAAIAF4AbQwAAAcAWQDqDAAACQBfAG4MAAAGAF8AbwwAAAMAWwAAAA==.',
Ma='Makoto:BAEBLgAECn8aAAIYAAcJlR3sCwBOAgdoDAAABQBaAGkMAAAFAFcAawwAAAUAWABqDAAABAA7AGwMAAADAE4AbQwAAAEAGgDqDAAAAwBTABgABwmVHewLAE4CB2gMAAAFAFoAaQwAAAUAVwBrDAAABQBYAGoMAAAEADsAbAwAAAMATgBtDAAAAQAaAOoMAAADAFMAAAA=.',
Mi='Mistorin:BAEALgAECgMJAwABLgAFFAUJDwAIAMckAA==.',
Na='Nalfein:BAEALgAECggJDAABLgAECgkJOQAHAOYlAA==.',
Ne='Neodefender:BAECLgAFFH8pAAIJAAYJKCZ1BAB6AgZoDAAACgBjAGkMAAAJAF4AawwAAAcAYwBqDAAABQBjAGwMAAADAF4A6gwAAAcAYQAJAAYJKCZ1BAB6AgZoDAAACgBjAGkMAAAJAF4AawwAAAcAYwBqDAAABQBjAGwMAAADAF4A6gwAAAcAYQAuAAQKfzIAAgkACQnnJvwAAIgDAAkACQnnJvwAAIgDAAAA.',
No='Nosferratu:BAECLgAFFH8lAAMZAAcJvh8YAwBYAgdoDAAACQBjAGkMAAAGAF4AawwAAAYAWwBqDAAABQAcAGwMAAACAD0A6gwAAAgAYwBuDAAAAQAoABkABwm+HxgDAFgCB2gMAAAJAGMAaQwAAAUAXgBrDAAABQBbAGoMAAAFABwAbAwAAAIAPQDqDAAACABjAG4MAAABACgAGgACCTgHgDkAgAACaQwAAAEADwBrDAAAAQAVAC4ABAp/QQACGQAJCYQmvQAAgQMAGQAJCYQmvQAAgQMAAAA=.',
Ny='Nyfaria:BAECLgAFFH8hAAIFAAUJwhwMFwBbAQVoDAAACQBMAGkMAAAIAD0AawwAAAUARQBqDAAABABJAOoMAAAHAFYABQAFCcIcDBcAWwEFaAwAAAkATABpDAAACAA9AGsMAAAFAEUAagwAAAQASQDqDAAABwBWAC4ABAp/LAACBQAJCQ4k3wEARgMABQAJCQ4k3wEARgMAAAA=.',
Oo='Ookook:BAEALgADCgYJBgABLgAFFAkJIAARAJgdAA==.',
Or='Orsp:BAECLgAFFH8jAAQZAAcJgRgkCADQAQdoDAAACABiAGkMAAAGAFEAawwAAAUATABqDAAABABHAGwMAAACAAIAbQwAAAEAGwDqDAAACQBaABkABgk8HSQIANABBmgMAAAIAGIAaQwAAAYAUQBrDAAABQBMAGoMAAACAEcAbQwAAAEAGwDqDAAACQBaABoAAgk8AT4WAH4AAmoMAAABAAAAbAwAAAIABQAbAAEJRgHuFABBAAFqDAAAAQADAC4ABAp/KgAEGQAJCTcjOwUAPQMAGQAJCTcjOwUAPQMAGwADCcoKCGUAmQAAGgADCcEZ30YAhgAAAAA=.Orspp:BAECLgAFFH8KAAMZAAQJCRPEIADaAARoDAAAAwBAAGkMAAADADsAawwAAAEANADqDAAAAwARABkAAwkJF8QgANoAA2gMAAADAEAAaQwAAAMAOwBrDAAAAQA0ABoAAQkJFdxEAEAAAeoMAAADADUALgAECn8cAAQZAAgJKBpuIQDMAQAZAAgJKBpuIQDMAQAbAAYJpQgiSQAUAQAaAAEJtQ3DVQA2AAABLgAFFAcJIwAZAIEYAA==.',
Pa='Pakk:BAEBLgAECn81AAIDAAgJOSEwCACNAghoDAAACgBeAGkMAAAJAFoAawwAAAgAUgBqDAAABwBXAGwMAAAHAFQAbQwAAAEAPwDqDAAABwBdAG4MAAAEAFYAAwAICTkhMAgAjQIIaAwAAAoAXgBpDAAACQBaAGsMAAAIAFIAagwAAAcAVwBsDAAABwBUAG0MAAABAD8A6gwAAAcAXQBuDAAABABWAAAA.Pandoken:BAEBLgAFFH8RAAMGAAYJUh0KDwD7AQZoDAAABABNAGkMAAAEAFEAawwAAAQAUgBqDAAAAgBEAGwMAAABAEwA6gwAAAIAQAAGAAYJUh0KDwD7AQZoDAAAAwBNAGkMAAADAFEAawwAAAQAUgBqDAAAAgBEAGwMAAABAEwA6gwAAAIAQAABAAIJSRlZKACnAAJoDAAAAQAvAGkMAAABAFIAAAA=.Pandotides:BAEALgAFFAUJAgABLgAFFAgJEQAGAFIdAA==.Papadefensve:BAEALgAECgYJBgAAAA==.',
Pr='Priff:BAEBLgAECn85AAQHAAkJ5iVtAwBWAwloDAAACABiAGkMAAAIAGEAawwAAAgAXQBqDAAABgBgAGwMAAAHAFsAbQwAAAYAYwDqDAAACABgAG4MAAAEAGMAbwwAAAIAYgAHAAkJ2iVtAwBWAwloDAAAAwBhAGkMAAAFAGEAawwAAAQAXQBqDAAAAwBgAGwMAAABAFsAbQwAAAUAYwDqDAAAAwBgAG4MAAAEAGMAbwwAAAIAYgAcAAcJ9yFfGABqAgdoDAAAAwBTAGkMAAADAFwAawwAAAMASgBqDAAAAgAoAGwMAAAEAFQAbQwAAAEAXwDqDAAAAwBaAB0ABQnlIbQmAGYBBWgMAAACAGIAawwAAAEASgBqDAAAAQBTAGwMAAACAFQA6gwAAAIAWQAAAA==.Priffraff:BAEALgAECgYJCwABLgAECgkJOQAHAOYlAA==.',
Ra='Razamon:BAEBLgAECn8rAAMKAAkJMSGRGQB0AgloDAAABgBcAGkMAAAFAFMAawwAAAUASgBqDAAABQBUAGwMAAAFAF4AbQwAAAQAVgDqDAAABQBRAG4MAAAFAF4AbwwAAAMASAAKAAkJMSGRGQB0AgloDAAAAgBcAGkMAAABAFMAawwAAAIASgBqDAAAAwBUAGwMAAAEAF4AbQwAAAQAVgDqDAAAAgBRAG4MAAAEAF4AbwwAAAMASAALAAcJgxiJLgCpAQdoDAAABABSAGkMAAAEAEsAawwAAAMAOABqDAAAAgA/AGwMAAABADYA6gwAAAMASwBuDAAAAQAfAAAA.',
Re='Recurse:BAEALgAFFAIJBAABLgAFFAkJMAAPAEEbAA==.Relsham:BAEALgAECgkJAgABLgAFFAQJCAANAFIHAA==.',
Ri='Ripwwmonk:BAEALgADCgcJBwABLgAFFAYJDwADANgXAA==.',
Ro='Roukedhh:BAECLgAFFH8SAAIQAAcJKhghGwC/AQdoDAAABABSAGkMAAADAEoAawwAAAIAEgBqDAAAAQADAG0MAAABAD8A6gwAAAYAPQBuDAAAAQBHABAABwkqGCEbAL8BB2gMAAAEAFIAaQwAAAMASgBrDAAAAgASAGoMAAABAAMAbQwAAAEAPwDqDAAABgA9AG4MAAABAEcALgAECn8eAAIQAAgJpyGQFgDPAgAQAAgJpyGQFgDPAgAAAA==.',
Ru='Runehaven:BAEBLgAECn8WAAMEAAYJHx2siABNAQZoDAAABgBUAGkMAAAEAFQAawwAAAQAUABqDAAAAgAwAGwMAAADADQA6gwAAAMARgAEAAYJHx2siABNAQZoDAAABABUAGkMAAADAFQAawwAAAMAUABqDAAAAQAwAGwMAAABADQA6gwAAAIARgADAAYJggqbOACpAAZoDAAAAgAnAGkMAAABABUAawwAAAEAEQBqDAAAAQAfAGwMAAACACUA6gwAAAEAEgABLgAECgYJFgAEAB8dAA==.',
Sa='Sargala:BAEBLgAECn8sAAMHAAgJJhq5LQAdAghoDAAACQBLAGkMAAAIAEkAawwAAAoANwBqDAAABQBKAGwMAAAEAFIAbQwAAAEAFwDqDAAABgBWAG4MAAABAEcABwAICSYauS0AHQIIaAwAAAgASwBpDAAABwBJAGsMAAAJADcAagwAAAQASgBsDAAABABSAG0MAAABABcA6gwAAAYAVgBuDAAAAQBHAB0ABAnnBeJHAJIABGgMAAABABMAaQwAAAEAEgBrDAAAAQAHAGoMAAABABMAAAA=.',
Sc='Scootybooty:BAEALgAECgUJBQAAAA==.Scootyclap:BAEALgADCgQJBAABLgAECgUJBQAMAAAAAA==.Scootypriest:BAEALgADCggJCAABLgAECgUJBQAMAAAAAA==.Scootysnack:BAEALgADCgcJEAABLgAECgUJBQAMAAAAAA==.Scussy:BAEALgADCgcJBwABLgAECgUJBQAMAAAAAA==.',
Sm='Smoothdk:BAEALgAFFAIJAgABLgAFFAUJBQAUABEFAA==.Smoothp:BAEALgAFFAIJAgABLgAFFAUJBQAUABEFAA==.Smoothz:BAEALgAFFAIJAgABLgAFFAUJBQAUABEFAA==.',
Th='Thez:BAEALgAECgEJAQABLgAECgkJJwAYAAgdAA==.Thezdin:BAEBLgAECn8nAAIYAAkJCB2wCgA8AgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAADAEsAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAYAAkJCB2wCgA8AgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAADAEsAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAAAA==.Thezfu:BAEALgAECgEJAwABLgAECgkJJwAYAAgdAA==.',
Ve='Velohm:BAEBLgAECn8bAAMGAAYJ6CHkGABEAgZoDAAACABXAGkMAAAFAFAAawwAAAQAXABqDAAABABXAGwMAAACAFIA6gwAAAQAWgAGAAYJ6CHkGABEAgZoDAAABgBXAGkMAAADAFAAawwAAAIAXABqDAAAAgBXAGwMAAACAFIA6gwAAAMAWgABAAUJSAi1XQCWAAVoDAAAAgAjAGkMAAACABMAawwAAAIADQBqDAAAAgAmAOoMAAABAA8AAAA=.',
Zi='Zick:BAEALgAFFAcJAQAAAA==.Zikker:BAEALgADCgcJBwABLgAFFAcJAQAMAAAAAA==.',
Zo='Zoe:BAECLgAFFH8YAAIFAAcJXx4aBABGAgdoDAAABQBZAGkMAAAFAGMAawwAAAQAUgBsDAAAAQAlAG0MAAABAF8A6gwAAAcAWgBuDAAAAQAwAAUABwlfHhoEAEYCB2gMAAAFAFkAaQwAAAUAYwBrDAAABABSAGwMAAABACUAbQwAAAEAXwDqDAAABwBaAG4MAAABADAALgAECn8vAAIFAAgJVybiBADwAgAFAAgJVybiBADwAgAAAA==.Zogle:BAEBLgAFFH8JAAIDAAUJGRO8HgDlAAVoDAAAAQA3AGkMAAABAC4AawwAAAEAPABqDAAABQAcAOoMAAABACEAAwAFCRkTvB4A5QAFaAwAAAEANwBpDAAAAQAuAGsMAAABADwAagwAAAUAHADqDAAAAQAhAAEuAAUUBwkYAAUAXx4A.Zoog:BAEALgAECggJEwABLgAFFAcJGAAFAF8eAA==.',
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
