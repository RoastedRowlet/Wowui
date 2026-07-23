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

local lookup = {'Priest-Shadow','Priest-Holy','Unknown-Unknown','DemonHunter-Vengeance','DeathKnight-Blood','DeathKnight-Unholy','Monk-Brewmaster','Monk-Windwalker','Druid-Restoration','Shaman-Restoration','Mage-Arcane','Paladin-Retribution','Paladin-Holy','Shaman-Elemental','Paladin-Protection','Mage-Frost','Rogue-Subtlety','Rogue-Assassination','Shaman-Enhancement','Rogue-Outlaw','DemonHunter-Devourer','Evoker-Augmentation','Warrior-Protection','Warrior-Fury','Evoker-Preservation','Druid-Feral','Priest-Discipline','Monk-Mistweaver','Warlock-Demonology','Hunter-BeastMastery','Hunter-Survival','Druid-Guardian',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=46,date='2026-07-20',data={As='Astaren:BAEBLgAECn8TAAMBAAkJOQkmMwBNAQloDAAAAwAnAGkMAAACACoAawwAAAIACQBqDAAAAgAWAGwMAAABABAAbQwAAAEACADqDAAABgAkAG4MAAABAAQAbwwAAAEAHgABAAkJOQkmMwBNAQloDAAAAwAnAGkMAAACACoAawwAAAIACQBqDAAAAgAWAGwMAAABABAAbQwAAAEACADqDAAABQAkAG4MAAABAAQAbwwAAAEAHgACAAEJ1hfXaABDAAHqDAAAAQA9AAAA.',
Az='Azchath:BAEALgAFFAIJAgAAAQ==.',
Ba='Basin:BAEALgAECgcJBwABLgAFFAMJAwADAAAAAA==.',
Be='Bearècks:BAEALgAECgcJCwABLgAFFAQJDgAEACcTAA==.',
Br='Bryl:BAECLgAFFH8SAAIFAAcJjReGDAC1AQdoDAAAAgBYAGkMAAABACYAawwAAAEARABqDAAABQA5AGwMAAABADgAbQwAAAEADQDqDAAABwBfAAUABwmNF4YMALUBB2gMAAACAFgAaQwAAAEAJgBrDAAAAQBEAGoMAAAFADkAbAwAAAEAOABtDAAAAQANAOoMAAAHAF8ALgAECn8gAAMFAAkJ2x6rBgDKAgAFAAkJ2x6rBgDKAgAGAAcJYxEccQClAQABLgAFFAcJHgAHAD8gAA==.Brylic:BAECLgAFFH8eAAMHAAcJPyB5DADOAQdoDAAACABYAGkMAAAIAGEAawwAAAYAWQBqDAAAAQAMAGwMAAADAFwA6gwAAAMAVQBuDAAAAQAqAAcABwkAHnkMAM4BB2gMAAAHAFgAaQwAAAgAYQBrDAAABgBZAGoMAAABAAwAbAwAAAMAXADqDAAAAQAzAG4MAAABACoACAACCYggRiYAugACaAwAAAEAUADqDAAAAgBVAC4ABAp/JgADCAAICTkjJAYAHwMACAAICSYhJAYAHwMABwAICaoiMggAAgMAAAA=.Brylicet:BAEALgAFFAQJBAABLgAFFAcJHgAHAD8gAA==.',
Ca='Camreon:BAEALgAFFAEJAgAAAA==.Captpando:BAEALgAECgQJBAABLgAFFAkJNAAJAKIiAA==.',
Ch='Chataya:BAEALgAECgEJAwABLgAECgkJLgAKADwdAA==.',
Da='Dantius:BAEALgAECgcJBwABLgAFFAQJEQALAOwWAA==.Darkorin:BAECLgAFFH8TAAIMAAUJ7yQTIQCCAQVoDAAABwBiAGkMAAADAGIAawwAAAMAVgBqDAAAAQA5AOoMAAAFAF8ADAAFCe8kEyEAggEFaAwAAAcAYgBpDAAAAwBiAGsMAAADAFYAagwAAAEAOQDqDAAABQBfAC4ABAp/LQADDAAJCYklswYAZQMADAAICUsmswYAZQMADQACCcsOhooANgAAAAA=.',
Dr='Dragore:BAEALgAECgYJBwABLgAFFAMJAwADAAAAAA==.Drazgore:BAEALgAECgYJBgABLgAFFAMJAwADAAAAAA==.Drkillertofu:BAEALgAFFAMJAwAAAA==.',
Du='Duskorin:BAEBLgAFFH8QAAMOAAgJ3xReDgAmAQhoDAAABAA2AGkMAAABADMAawwAAAEAMABqDAAAAQA/AGwMAAABAD8AbQwAAAEASwDqDAAABgA9AG4MAAABABMADgAHCTsUXg4AJgEHaAwAAAEANgBpDAAAAQAzAGsMAAABADAAagwAAAEAPwBtDAAAAQBLAOoMAAADAD0AbgwAAAEAEwAKAAMJihGeTwC3AANoDAAAAwAvAGwMAAABACQA6gwAAAMAMgABLgAFFAUJEwAMAO8kAA==.',
Fi='Fishybrew:BAEBLgAECn8xAAIHAAkJ4CHMCACmAgloDAAACQBaAGkMAAAIAFsAawwAAAcAUgBqDAAABgBYAGwMAAAFAFAAbQwAAAIAVwDqDAAABwBdAG4MAAAEAF0AbwwAAAEASwAHAAkJ4CHMCACmAgloDAAACQBaAGkMAAAIAFsAawwAAAcAUgBqDAAABgBYAGwMAAAFAFAAbQwAAAIAVwDqDAAABwBdAG4MAAAEAF0AbwwAAAEASwABLgAECgYJGgAPABkhAA==.',
Fo='Foxblade:BAEALgAECgcJDQABLgAECgkJKwALAM0eAA==.Foxdemon:BAEALgAECgUJBQABLgAECgkJKwALAM0eAA==.Foxleaf:BAEALgAECgEJAQABLgAECgkJKwALAM0eAA==.Foxorcism:BAEBLgAECn8cAAQNAAcJXxZ6BACMAQdoDAAABQBUAGkMAAAFADsAawwAAAUAUwBqDAAABQA3AGwMAAACAB0AbQwAAAEABADqDAAABQBTAA0ABgnNGXoEAIwBBmgMAAAEAFQAaQwAAAQAOwBrDAAABABTAGoMAAAFADcAbAwAAAIAHQDqDAAABQBTAAwAAwl9BzFKAWMAA2gMAAABACoAaQwAAAEABQBrDAAAAQAJAA8AAQn6A+1VACQAAW0MAAABAAoAAS4ABAoJCSsACwDNHgA=.Foxox:BAEBLgAECn8rAAMLAAkJzR7IAAC5AQloDAAACQBYAGkMAAAHAFMAawwAAAYATgBqDAAABABXAGwMAAAFAE0AbQwAAAMAVgDqDAAABQBfAG4MAAADAEQAbwwAAAEAMwAQAAkJeByLBQAUAgloDAAACABYAGkMAAAGAFMAawwAAAYATgBqDAAABABXAGwMAAAFAE0AbQwAAAIAMwDqDAAABABfAG4MAAACADYAbwwAAAEAMwALAAUJNx7IAAC5AQVoDAAAAQBRAGkMAAABAEgAbQwAAAEAVgDqDAAAAQBNAG4MAAABAEQAAAA=.Foxrocket:BAEALgAECgIJAwABLgAECgkJKwALAM0eAA==.',
Fr='Fries:BAEBLgAFFH8FAAMRAAMJmQmjMwCTAANoDAAAAQAyAOoMAAADABIAbgwAAAEABAARAAIJeQ2jMwCTAAJoDAAAAQAyAOoMAAADABIAEgABCdgBiBIAQgABbgwAAAEABAABLgAFFAUJCwATAE0fAA==.',
Ga='Gardenweed:BAEBLgAECn8hAAIMAAkJVgk8igBcAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQAMAAkJVgk8igBcAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQAAAA==.',
Gu='Guthyne:BAEALgAECgMJBgABLgAFFAMJBQAUAC8kAA==.Guthynn:BAECLgAFFH8FAAIUAAMJLyQ3AwDZAANoDAAAAgBcAGkMAAACAFwA6gwAAAEAXQAUAAMJLyQ3AwDZAANoDAAAAgBcAGkMAAACAFwA6gwAAAEAXQAuAAQKfy8AAxQACQk2Ji0AAHYDABQACQk2Ji0AAHYDABIABQk/IcEKAIgBAAAA.',
Ha='Havècks:BAECLgAFFH8OAAMEAAQJJxOYAwDcAARoDAAABgBdAGkMAAAFADIAawwAAAEABwDqDAAAAgAsAAQAAwmRGJgDANwAA2gMAAAGAF0AaQwAAAUAMgDqDAAAAQAsABUAAgmEA1lEAEwAAmsMAAABAAcA6gwAAAEACgAuAAQKfz4AAwQACQngHL8FAEUCAAQACAmGH78FAEUCABUAAglCCJD0AFkAAAAA.',
Ir='Irro:BAEALgAECgYJCwABLgAECgkJLgAKADwdAA==.Irrofel:BAEALgAECgQJBAABLgAECgkJLgAKADwdAA==.Irrogenia:BAEBLgAECn8uAAMKAAkJPB3LEADJAgloDAAABwBgAGkMAAAHAFUAawwAAAYAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgAKAAkJPB3LEADJAgloDAAABwBgAGkMAAAGAFUAawwAAAUAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgAOAAIJ/QrxjABXAAJpDAAAAQAiAGsMAAABABUAAAA=.Irrowen:BAEALgAECgYJBgABLgAECgkJLgAKADwdAA==.',
La='Larias:BAECLgAFFH8OAAIWAAUJTx0LBgCeAQVoDAAABQBgAGkMAAAEAGEAawwAAAEAFgBsDAAAAQBcAOoMAAADAEIAFgAFCU8dCwYAngEFaAwAAAUAYABpDAAABABhAGsMAAABABYAbAwAAAEAXADqDAAAAwBCAC4ABAp/IgACFgAICZUmTwIAjQMAFgAICZUmTwIAjQMAAS4ABRQJCS0AFwAQHAA=.Lariàs:BAECLgAFFH8tAAMXAAkJEBykAQCOAgloDAAABwBVAGkMAAAGAFYAawwAAAYAUgBqDAAAAwBSAGwMAAAEADoAbQwAAAIAPQDqDAAACABXAG4MAAADADEAbwwAAAYAQAAXAAkJEBykAQCOAgloDAAABgBVAGkMAAAGAFYAawwAAAYAUgBqDAAAAwBSAGwMAAAEADoAbQwAAAIAPQDqDAAACABXAG4MAAADADEAbwwAAAYAQAAYAAEJIQC1WwANAAFoDAAAAQAAAC4ABAp/GgACFwAJCawjUAAAQwMAFwAJCawjUAAAQwMAAAA=.Lariås:BAEBLgAFFH8gAAIHAAkJ8Bd5AgAyAgloDAAABABRAGkMAAAEAGEAawwAAAQAWABqDAAAAgATAGwMAAACACYAbQwAAAIABgDqDAAACABZAG4MAAAEAC8AbwwAAAIAKQAHAAkJ8Bd5AgAyAgloDAAABABRAGkMAAAEAGEAawwAAAQAWABqDAAAAgATAGwMAAACACYAbQwAAAIABgDqDAAACABZAG4MAAAEAC8AbwwAAAIAKQABLgAFFAkJLQAXABAcAA==.',
Li='Lidariel:BAEALgAECggJDwABLgAFFAQJCwAZAP8PAA==.Lidathra:BAECLgAFFH8LAAIZAAQJ/w8hGwDkAARoDAAABAAgAGkMAAADAC8AawwAAAEAIQDqDAAAAwAyABkABAn/DyEbAOQABGgMAAAEACAAaQwAAAMALwBrDAAAAQAhAOoMAAADADIALgAECn8sAAIZAAkJ5hViCwAlAgAZAAkJ5hViCwAlAgAAAA==.Lidiosa:BAEBLgAECn8nAAIQAAkJdhr7JACIAgloDAAABwBeAGkMAAAFAE0AawwAAAUAPQBqDAAABAA9AGwMAAAEAEoAbQwAAAIANwDqDAAACQA8AG4MAAACAEwAbwwAAAEAKgAQAAkJdhr7JACIAgloDAAABwBeAGkMAAAFAE0AawwAAAUAPQBqDAAABAA9AGwMAAAEAEoAbQwAAAIANwDqDAAACQA8AG4MAAACAEwAbwwAAAEAKgABLgAFFAQJCwAZAP8PAA==.Lidishi:BAEALgAECgYJCQABLgAFFAQJCwAZAP8PAA==.Lidizine:BAEALgADCggJDAABLgAFFAQJCwAZAP8PAA==.',
Lo='Lochru:BAECLgAFFH8FAAIaAAMJ4BLXBQDIAANoDAAAAgAzAGkMAAACADsA6gwAAAEAIgAaAAMJ4BLXBQDIAANoDAAAAgAzAGkMAAACADsA6gwAAAEAIgAuAAQKf08AAhoACQnjIzMBAEMDABoACQnjIzMBAEMDAAAA.',
Ma='Makoto:BAEBLgAECn8aAAIXAAcJlR3sCwBOAgdoDAAABQBaAGkMAAAFAFcAawwAAAUAWABqDAAABAA7AGwMAAADAE4AbQwAAAEAGgDqDAAAAwBTABcABwmVHewLAE4CB2gMAAAFAFoAaQwAAAUAVwBrDAAABQBYAGoMAAAEADsAbAwAAAMATgBtDAAAAQAaAOoMAAADAFMAAAA=.',
Mi='Mistorin:BAEALgAECgMJAwABLgAFFAUJEwAMAO8kAA==.',
My='Mysaria:BAEALgAECgEJAQABLgAECgkJLgAKADwdAA==.',
Ne='Neodefender:BAECLgAFFH8rAAINAAgJZiTsAgDLAghoDAAACgBjAGkMAAAJAF4AawwAAAcAYwBqDAAABQBjAGwMAAADAF4AbQwAAAEASwDqDAAABwBhAG4MAAABAFMADQAICWYk7AIAywIIaAwAAAoAYwBpDAAACQBeAGsMAAAHAGMAagwAAAUAYwBsDAAAAwBeAG0MAAABAEsA6gwAAAcAYQBuDAAAAQBTAC4ABAp/MgACDQAJCecm/AAAiAMADQAJCecm/AAAiAMAAAA=.',
No='Nosferratu:BAECLgAFFH9LAAMBAAkJlBzRAAAKAwloDAAADgBjAGkMAAAMAF4AawwAAAsAWwBqDAAACABdAGwMAAAHAE8AbQwAAAIANADqDAAADQBjAG4MAAAEACgAbwwAAAQAGgABAAkJlBzRAAAKAwloDAAADgBjAGkMAAALAF4AawwAAAoAWwBqDAAACABdAGwMAAAHAE8AbQwAAAIANADqDAAADQBjAG4MAAAEACgAbwwAAAQAGgAbAAIJOAcAPwB9AAJpDAAAAQAPAGsMAAABABUALgAECn9BAAIBAAkJhCbcAAB6AwABAAkJhCbcAAB6AwAAAA==.',
Ny='Nyfaria:BAECLgAFFH8pAAIHAAUJih0AGgBUAQVoDAAACwBMAGkMAAAKAEUAawwAAAYARQBqDAAABABJAOoMAAAKAFYABwAFCYodABoAVAEFaAwAAAsATABpDAAACgBFAGsMAAAGAEUAagwAAAQASQDqDAAACgBWAC4ABAp/MgACBwAJCbIkDQIAQwMABwAJCbIkDQIAQwMAAAA=.',
Ol='Oldstandard:BAEALgAECgMJAwABLgAFFAkJLQAXABAcAA==.',
Or='Orsp:BAECLgAFFH9BAAQBAAkJbxzNAAALAwloDAAADABiAGkMAAAMAFoAawwAAAoAWABqDAAACABHAGwMAAAEADsAbQwAAAUAVQDqDAAACwBcAG4MAAABACcAbwwAAAIAGQABAAkJbxzNAAALAwloDAAADABiAGkMAAAMAFoAawwAAAoAWABqDAAABgBHAGwMAAABADsAbQwAAAUAVQDqDAAACwBcAG4MAAABACcAbwwAAAIAGQAbAAIJPAE+FgB+AAJqDAAAAQAAAGwMAAACAAUAAgACCeMEgRoARQACagwAAAEAAwBsDAAAAQAVAC4ABAp/LAAEAQAJCcUjOwUAPQMAAQAJCcUjOwUAPQMAAgADCcoKCGUAmQAAGwADCcEZKmcAYQAAAAA=.Orspp:BAECLgAFFH8TAAMBAAUJlxUNDAANAQVoDAAABgBVAGkMAAAGAEcAawwAAAEANADqDAAABQAoAG8MAAABABkAAQAFCZcVDQwADQEFaAwAAAYAVQBpDAAABgBHAGsMAAABADQA6gwAAAEAKABvDAAAAQAZABsAAQkJFRJLAD8AAeoMAAAEADUALgAECn8cAAQBAAgJKBpuIQDMAQABAAgJKBpuIQDMAQACAAYJpQgiSQAUAQAbAAEJtQ3DVQA2AAABLgAFFAkJQQABAG8cAA==.',
Pa='Pakk:BAEBLgAECn9EAAIFAAkJqCC/AQBGAgloDAAADABeAGkMAAALAFoAawwAAAoAUgBqDAAACQBXAGwMAAAJAFQAbQwAAAEAPwDqDAAACQBdAG4MAAAGAFYAbwwAAAEASQAFAAkJqCC/AQBGAgloDAAADABeAGkMAAALAFoAawwAAAoAUgBqDAAACQBXAGwMAAAJAFQAbQwAAAEAPwDqDAAACQBdAG4MAAAGAFYAbwwAAAEASQAAAA==.Pandoken:BAEBLgAFFH8XAAMcAAgJ7RxdDABCAghoDAAABABNAGkMAAAEAFEAawwAAAQAUgBqDAAAAgBEAGwMAAABAEwA6gwAAAQAQwBuDAAAAQA/AG8MAAADAEsAHAAICe0cXQwAQgIIaAwAAAMATQBpDAAAAwBRAGsMAAAEAFIAagwAAAIARABsDAAAAQBMAOoMAAAEAEMAbgwAAAEAPwBvDAAAAwBLAAgAAglJGRosAJ0AAmgMAAABAC8AaQwAAAEAUgABLgAFFAkJNAAJAKIiAA==.Pandotides:BAEALgAFFAUJAgABLgAFFAkJNAAJAKIiAA==.Papadefensve:BAEBLgAECn8aAAIPAAYJGSEBAgDbAQZoDAAABQBUAGkMAAAFAFUAawwAAAUAVQBqDAAAAwBXAGwMAAADAEsA6gwAAAUAXAAPAAYJGSEBAgDbAQZoDAAABQBUAGkMAAAFAFUAawwAAAUAVQBqDAAAAwBXAGwMAAADAEsA6gwAAAUAXAAAAA==.',
Ra='Razamon:BAEBLgAECn8rAAMKAAkJMSH5GgBzAgloDAAABgBcAGkMAAAFAFMAawwAAAUASgBqDAAABQBUAGwMAAAFAF4AbQwAAAQAVgDqDAAABQBRAG4MAAAFAF4AbwwAAAMASAAKAAkJMSH5GgBzAgloDAAAAgBcAGkMAAABAFMAawwAAAIASgBqDAAAAwBUAGwMAAAEAF4AbQwAAAQAVgDqDAAAAgBRAG4MAAAEAF4AbwwAAAMASAAOAAcJgxiJLgCpAQdoDAAABABSAGkMAAAEAEsAawwAAAMAOABqDAAAAgA/AGwMAAABADYA6gwAAAMASwBuDAAAAQAfAAAA.Razx:BAEALgAFFAIJAgABLgAFFAMJBQAaAOASAA==.',
Re='Recurse:BAEALgAFFAIJBAABLgAFFAkJFQAdADscAA==.',
Ri='Ripwwmonk:BAEALgADCgcJBwABLgAFFAcJHgAHAD8gAA==.',
Ro='Roukedhh:BAECLgAFFH8XAAIVAAcJxxzyGQDjAQdoDAAABgBSAGkMAAAEAEoAawwAAAMARQBqDAAAAQADAG0MAAABAD8A6gwAAAcAUQBuDAAAAQBHABUABwnHHPIZAOMBB2gMAAAGAFIAaQwAAAQASgBrDAAAAwBFAGoMAAABAAMAbQwAAAEAPwDqDAAABwBRAG4MAAABAEcALgAECn8eAAIVAAgJpyGQFgDPAgAVAAgJpyGQFgDPAgAAAA==.',
Ru='Runehaven:BAECLgAFFH8FAAIGAAQJzBfKLwAEAQRoDAAAAgAwAGkMAAABAFQAawwAAAEASwDqDAAAAQAiAAYABAnMF8ovAAQBBGgMAAACADAAaQwAAAEAVABrDAAAAQBLAOoMAAABACIALgAECn8YAAMGAAYJlB3PjABLAQAGAAYJlB3PjABLAQAFAAYJggpnOwCkAAABLgAFFAQJBQAGAMwXAA==.',
Sa='Sairal:BAEBLgAFFH8TAAIXAAkJzxg5AQC2AgloDAAAAwBgAGkMAAADAFIAawwAAAMAUwBqDAAAAwAuAGwMAAACADgAbQwAAAEACQDqDAAAAgBfAG4MAAABADEAbwwAAAEAIwAXAAkJzxg5AQC2AgloDAAAAwBgAGkMAAADAFIAawwAAAMAUwBqDAAAAwAuAGwMAAACADgAbQwAAAEACQDqDAAAAgBfAG4MAAABADEAbwwAAAEAIwABLgAFFAkJLQAXABAcAA==.Sargala:BAEBLgAECn84AAMeAAkJTh3VBQAMAgloDAAACwBQAGkMAAAKAFcAawwAAAwASQBqDAAABgBKAGwMAAAFAFIAbQwAAAIALADqDAAABwBWAG4MAAACAEcAbwwAAAEASgAeAAkJTh3VBQAMAgloDAAACgBQAGkMAAAJAFcAawwAAAsASQBqDAAABQBKAGwMAAAFAFIAbQwAAAIALADqDAAABwBWAG4MAAACAEcAbwwAAAEASgAfAAQJ5wW5SgCMAARoDAAAAQATAGkMAAABABIAawwAAAEABwBqDAAAAQATAAAA.',
Sc='Scootybooty:BAEALgAECgUJBQAAAA==.Scootyclap:BAEALgADCgQJBAABLgAECgUJBQADAAAAAA==.Scootypriest:BAEALgADCggJCAABLgAECgUJBQADAAAAAA==.Scootysnack:BAEALgADCgcJEAABLgAECgUJBQADAAAAAA==.Scussy:BAEALgADCgcJBwABLgAECgUJBQADAAAAAA==.',
Sm='Smitehaven:BAEALgAFFAIJAgABLgAFFAQJBQAGAMwXAA==.Smoothdk:BAEALgAFFAIJBAABLgAFFAQJCQAgAHcaAA==.Smoothp:BAEALgAFFAIJAgABLgAFFAQJCQAgAHcaAA==.Smoothz:BAEALgAFFAIJAgABLgAFFAQJCQAgAHcaAA==.',
Th='Thez:BAEALgAECgEJAQABLgAECgkJKAAXAFMdAA==.Thezdin:BAEBLgAECn8oAAIXAAkJUx35CABnAgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAAEAFEAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAXAAkJUx35CABnAgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAAEAFEAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAAAA==.Thezfu:BAEALgAECgEJAwABLgAECgkJKAAXAFMdAA==.',
Ve='Velohm:BAEBLgAECn8nAAMcAAkJLSH0AAAuAwloDAAACgBXAGkMAAAGAFMAawwAAAUAXABqDAAABQBXAGwMAAADAFkAbQwAAAEATgDqDAAABgBaAG4MAAACAEgAbwwAAAEAUwAcAAkJLSH0AAAuAwloDAAACABXAGkMAAAEAFMAawwAAAMAXABqDAAAAwBXAGwMAAADAFkAbQwAAAEATgDqDAAABQBaAG4MAAACAEgAbwwAAAEAUwAIAAUJSAhYYgCUAAVoDAAAAgAjAGkMAAACABMAawwAAAIADQBqDAAAAgAmAOoMAAABAA8AAAA=.',
Wr='Wreckss:BAEBLgAECn8WAAMOAAcJXhOgOQBQAQdoDAAABAAtAGkMAAAEADQAawwAAAQAPABqDAAAAwArAGwMAAACADkAbQwAAAEALADqDAAABAAjAA4ABwleE6A5AFABB2gMAAADAC0AaQwAAAQANABrDAAABAA8AGoMAAACACsAbAwAAAIAOQBtDAAAAQAsAOoMAAAEACMAEwACCRcJ2ysANgACaAwAAAEAFwBqDAAAAQARAAEuAAUUBAkOAAQAJxMA.',
Zi='Zick:BAEALgAFFAgJAQAAAA==.Zigle:BAEBLgAFFH8TAAIgAAcJwB/5AACIAgdoDAAAAwBfAGkMAAADAFsAawwAAAMAXQBsDAAAAwBUAG0MAAACAD8A6gwAAAMASgBuDAAAAgBBACAABwnAH/kAAIgCB2gMAAADAF8AaQwAAAMAWwBrDAAAAwBdAGwMAAADAFQAbQwAAAIAPwDqDAAAAwBKAG4MAAACAEEAAS4ABRQHCRgABwBfHgA=.Zikker:BAEALgADCgcJBwABLgAFFAgJAQADAAAAAA==.',
Zo='Zoe:BAECLgAFFH8YAAIHAAcJXx5+BQBAAgdoDAAABQBZAGkMAAAFAGMAawwAAAQAUgBsDAAAAQAlAG0MAAABAF8A6gwAAAcAWgBuDAAAAQAwAAcABwlfHn4FAEACB2gMAAAFAFkAaQwAAAUAYwBrDAAABABSAGwMAAABACUAbQwAAAEAXwDqDAAABwBaAG4MAAABADAALgAECn8vAAIHAAgJVyY5BQDuAgAHAAgJVyY5BQDuAgAAAA==.Zogle:BAEBLgAFFH8PAAIFAAYJ6xVgIgDYAAZoDAAAAQA3AGkMAAABAC4AawwAAAEAPABqDAAACABHAOoMAAABACEAbwwAAAMAVAAFAAYJ6xVgIgDYAAZoDAAAAQA3AGkMAAABAC4AawwAAAEAPABqDAAACABHAOoMAAABACEAbwwAAAMAVAABLgAFFAcJGAAHAF8eAA==.Zoog:BAEALgAECggJEwABLgAFFAcJGAAHAF8eAA==.',
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
