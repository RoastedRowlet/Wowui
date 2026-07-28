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

local lookup = {'Priest-Shadow','Priest-Holy','Unknown-Unknown','DemonHunter-Vengeance','DeathKnight-Blood','DeathKnight-Unholy','Monk-Brewmaster','Monk-Windwalker','Druid-Restoration','Shaman-Restoration','Mage-Arcane','Paladin-Retribution','Paladin-Holy','Shaman-Elemental','Paladin-Protection','Mage-Frost','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Shaman-Enhancement','Rogue-Outlaw','DemonHunter-Devourer','Evoker-Augmentation','Warrior-Protection','Warrior-Fury','Evoker-Preservation','Druid-Feral','Priest-Discipline','Monk-Mistweaver','Warlock-Demonology','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Frost','Druid-Guardian',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=46,date='2026-07-28',data={As='Astaren:BAEBLgAECn8TAAMBAAkJOQkmMwBNAQloDAAAAwAnAGkMAAACACoAawwAAAIACQBqDAAAAgAWAGwMAAABABAAbQwAAAEACADqDAAABgAkAG4MAAABAAQAbwwAAAEAHgABAAkJOQkmMwBNAQloDAAAAwAnAGkMAAACACoAawwAAAIACQBqDAAAAgAWAGwMAAABABAAbQwAAAEACADqDAAABQAkAG4MAAABAAQAbwwAAAEAHgACAAEJ1hfXaABDAAHqDAAAAQA9AAAA.',
Az='Azchath:BAEALgAFFAIJAgAAAQ==.',
Ba='Basin:BAEALgAECgcJBwABLgAFFAMJAwADAAAAAA==.',
Be='Bearècks:BAEALgAECgcJCwABLgAFFAQJEwAEAO4UAA==.',
Br='Bryl:BAECLgAFFH8TAAIFAAcJjReGDAC1AQdoDAAAAgBYAGkMAAABACYAawwAAAEARABqDAAABQA5AGwMAAABADgAbQwAAAEADQDqDAAACABfAAUABwmNF4YMALUBB2gMAAACAFgAaQwAAAEAJgBrDAAAAQBEAGoMAAAFADkAbAwAAAEAOABtDAAAAQANAOoMAAAIAF8ALgAECn8gAAMFAAkJ2x6rBgDKAgAFAAkJ2x6rBgDKAgAGAAcJYxEccQClAQABLgAFFAcJHgAHAD8gAA==.Brylic:BAECLgAFFH8eAAMHAAcJPyB5DADOAQdoDAAACABYAGkMAAAIAGEAawwAAAYAWQBqDAAAAQAMAGwMAAADAFwA6gwAAAMAVQBuDAAAAQAqAAcABwkAHnkMAM4BB2gMAAAHAFgAaQwAAAgAYQBrDAAABgBZAGoMAAABAAwAbAwAAAMAXADqDAAAAQAzAG4MAAABACoACAACCYggRiYAugACaAwAAAEAUADqDAAAAgBVAC4ABAp/JgADCAAICTkjJAYAHwMACAAICSYhJAYAHwMABwAICaoiMggAAgMAAAA=.Brylicet:BAEALgAFFAQJBAABLgAFFAcJHgAHAD8gAA==.',
Ca='Camreon:BAEALgAFFAEJAgAAAA==.Captpando:BAEALgAECgQJBAABLgAFFAkJNgAJAGQjAA==.',
Ch='Chataya:BAEALgAECgEJAwABLgAECgkJLgAKADwdAA==.',
Da='Dantius:BAEALgAECgcJCAABLgAFFAQJEQALAOwWAA==.Darkorin:BAECLgAFFH8TAAIMAAUJ7yQTIQCCAQVoDAAABwBiAGkMAAADAGIAawwAAAMAVgBqDAAAAQA5AOoMAAAFAF8ADAAFCe8kEyEAggEFaAwAAAcAYgBpDAAAAwBiAGsMAAADAFYAagwAAAEAOQDqDAAABQBfAC4ABAp/LQADDAAJCYklswYAZQMADAAICUsmswYAZQMADQACCcsOhooANgAAAAA=.',
Dr='Dragore:BAEALgAECgYJBwABLgAFFAMJAwADAAAAAA==.Drazgore:BAEALgAECgYJBgABLgAFFAMJAwADAAAAAA==.Drkillertofu:BAEALgAFFAMJAwAAAA==.',
Du='Duskorin:BAEBLgAFFH8QAAMOAAgJ3xSQEAAYAQhoDAAABAA2AGkMAAABADMAawwAAAEAMABqDAAAAQA/AGwMAAABAD8AbQwAAAEASwDqDAAABgA9AG4MAAABABMADgAHCTsUkBAAGAEHaAwAAAEANgBpDAAAAQAzAGsMAAABADAAagwAAAEAPwBtDAAAAQBLAOoMAAADAD0AbgwAAAEAEwAKAAMJihGeTwC3AANoDAAAAwAvAGwMAAABACQA6gwAAAMAMgABLgAFFAUJEwAMAO8kAA==.',
Fi='Fishybrew:BAEBLgAECn8xAAIHAAkJ4CHMCACmAgloDAAACQBaAGkMAAAIAFsAawwAAAcAUgBqDAAABgBYAGwMAAAFAFAAbQwAAAIAVwDqDAAABwBdAG4MAAAEAF0AbwwAAAEASwAHAAkJ4CHMCACmAgloDAAACQBaAGkMAAAIAFsAawwAAAcAUgBqDAAABgBYAGwMAAAFAFAAbQwAAAIAVwDqDAAABwBdAG4MAAAEAF0AbwwAAAEASwABLgAECgYJGgAPABkhAA==.',
Fo='Foxblade:BAEALgAECgcJDQABLgAECgkJLQALAM0eAA==.Foxdemon:BAEALgAECgcJDAABLgAECgkJLQALAM0eAA==.Foxleaf:BAEALgAECgEJAQABLgAECgkJLQALAM0eAA==.Foxorcism:BAEBLgAECn8cAAQNAAcJXxYYBQCMAQdoDAAABQBUAGkMAAAFADsAawwAAAUAUwBqDAAABQA3AGwMAAACAB0AbQwAAAEABADqDAAABQBTAA0ABgnNGRgFAIwBBmgMAAAEAFQAaQwAAAQAOwBrDAAABABTAGoMAAAFADcAbAwAAAIAHQDqDAAABQBTAAwAAwl9BzFKAWMAA2gMAAABACoAaQwAAAEABQBrDAAAAQAJAA8AAQn6A+1VACQAAW0MAAABAAoAAS4ABAoJCS0ACwDNHgA=.Foxox:BAEBLgAECn8tAAQLAAkJzR72AAC5AQloDAAACQBYAGkMAAAHAFMAawwAAAYATgBqDAAABABXAGwMAAAFAE0AbQwAAAMAVgDqDAAABQBfAG4MAAAEAEQAbwwAAAIAMwAQAAkJeBxVBgARAgloDAAACABYAGkMAAAGAFMAawwAAAYATgBqDAAABABXAGwMAAAFAE0AbQwAAAIAMwDqDAAABABfAG4MAAACADYAbwwAAAIAMwALAAUJNx72AAC5AQVoDAAAAQBRAGkMAAABAEgAbQwAAAEAVgDqDAAAAQBNAG4MAAABAEQAEQABCXUOhgYALgABbgwAAAEAJQAAAA==.Foxrocket:BAEALgAECgIJAwABLgAECgkJLQALAM0eAA==.',
Fr='Fries:BAEBLgAFFH8FAAMSAAMJmQmjMwCTAANoDAAAAQAyAOoMAAADABIAbgwAAAEABAASAAIJeQ2jMwCTAAJoDAAAAQAyAOoMAAADABIAEwABCdgBiBIAQgABbgwAAAEABAABLgAFFAUJCwAUAE0fAA==.',
Ga='Gardenweed:BAEBLgAECn8hAAIMAAkJVgk8igBcAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQAMAAkJVgk8igBcAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQAAAA==.',
Gu='Guthyne:BAEALgAECgMJBgABLgAFFAMJBQAVAC8kAA==.Guthynn:BAECLgAFFH8FAAIVAAMJLyR2AwDWAANoDAAAAgBcAGkMAAACAFwA6gwAAAEAXQAVAAMJLyR2AwDWAANoDAAAAgBcAGkMAAACAFwA6gwAAAEAXQAuAAQKfy8AAxUACQk2Ji0AAHYDABUACQk2Ji0AAHYDABMABQk/IcEKAIgBAAAA.',
Ha='Havècks:BAECLgAFFH8TAAMEAAQJ7hQFAwAPAQRoDAAACABdAGkMAAAHADIAawwAAAIAGQDqDAAAAgAsAAQABAnuFAUDAA8BBGgMAAAHAF0AaQwAAAYAMgBrDAAAAQAZAOoMAAABACwAFgAECS0DwjYAlAAEaAwAAAEACQBpDAAAAQAFAGsMAAABAAcA6gwAAAEACgAuAAQKfz4AAwQACQngHL8FAEUCAAQACAmGH78FAEUCABYAAglCCJD0AFkAAAAA.',
Ir='Irro:BAEALgAECgYJCwABLgAECgkJLgAKADwdAA==.Irrofel:BAEALgAECgQJBAABLgAECgkJLgAKADwdAA==.Irrogenia:BAEBLgAECn8uAAMKAAkJPB3LEADJAgloDAAABwBgAGkMAAAHAFUAawwAAAYAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgAKAAkJPB3LEADJAgloDAAABwBgAGkMAAAGAFUAawwAAAUAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgAOAAIJ/QrxjABXAAJpDAAAAQAiAGsMAAABABUAAAA=.Irrolyn:BAEALgAECgEJAQABLgAECgkJLgAKADwdAA==.Irrowen:BAEALgAECgYJBgABLgAECgkJLgAKADwdAA==.',
La='Larias:BAECLgAFFH8OAAIXAAUJTx0LBgCeAQVoDAAABQBgAGkMAAAEAGEAawwAAAEAFgBsDAAAAQBcAOoMAAADAEIAFwAFCU8dCwYAngEFaAwAAAUAYABpDAAABABhAGsMAAABABYAbAwAAAEAXADqDAAAAwBCAC4ABAp/IgACFwAICZUmTwIAjQMAFwAICZUmTwIAjQMAAS4ABRQJCTQAGACAHAA=.Lariàs:BAECLgAFFH80AAMYAAkJgBwAAgB+AgloDAAACABVAGkMAAAIAFYAawwAAAcAUgBqDAAABABSAGwMAAAFAEMAbQwAAAIAPQDqDAAACQBXAG4MAAADADEAbwwAAAYAQAAYAAkJgBwAAgB+AgloDAAABwBVAGkMAAAIAFYAawwAAAcAUgBqDAAABABSAGwMAAAFAEMAbQwAAAIAPQDqDAAACQBXAG4MAAADADEAbwwAAAYAQAAZAAEJIQC1WwANAAFoDAAAAQAAAC4ABAp/GgACGAAJCawjXgAAPQMAGAAJCawjXgAAPQMAAAA=.Lariås:BAEBLgAFFH8gAAIHAAkJ8Bf3AgAkAgloDAAABABRAGkMAAAEAGEAawwAAAQAWABqDAAAAgATAGwMAAACACYAbQwAAAIABgDqDAAACABZAG4MAAAEAC8AbwwAAAIAKQAHAAkJ8Bf3AgAkAgloDAAABABRAGkMAAAEAGEAawwAAAQAWABqDAAAAgATAGwMAAACACYAbQwAAAIABgDqDAAACABZAG4MAAAEAC8AbwwAAAIAKQABLgAFFAkJNAAYAIAcAA==.',
Li='Lidariel:BAEALgAECggJDwABLgAFFAQJCwAaAP8PAA==.Lidathra:BAECLgAFFH8LAAIaAAQJ/w8hGwDkAARoDAAABAAgAGkMAAADAC8AawwAAAEAIQDqDAAAAwAyABoABAn/DyEbAOQABGgMAAAEACAAaQwAAAMALwBrDAAAAQAhAOoMAAADADIALgAECn8sAAIaAAkJ5hViCwAlAgAaAAkJ5hViCwAlAgAAAA==.Lidiosa:BAEBLgAECn8nAAIQAAkJdhr7JACIAgloDAAABwBeAGkMAAAFAE0AawwAAAUAPQBqDAAABAA9AGwMAAAEAEoAbQwAAAIANwDqDAAACQA8AG4MAAACAEwAbwwAAAEAKgAQAAkJdhr7JACIAgloDAAABwBeAGkMAAAFAE0AawwAAAUAPQBqDAAABAA9AGwMAAAEAEoAbQwAAAIANwDqDAAACQA8AG4MAAACAEwAbwwAAAEAKgABLgAFFAQJCwAaAP8PAA==.Lidishi:BAEALgAECgYJCQABLgAFFAQJCwAaAP8PAA==.Lidizine:BAEALgADCggJDAABLgAFFAQJCwAaAP8PAA==.Lilgup:BAEALgAFFAEJAQAAAA==.',
Lo='Lochru:BAECLgAFFH8FAAIbAAMJ4BKXBgDBAANoDAAAAgAzAGkMAAACADsA6gwAAAEAIgAbAAMJ4BKXBgDBAANoDAAAAgAzAGkMAAACADsA6gwAAAEAIgAuAAQKf08AAhsACQnjIzMBAEMDABsACQnjIzMBAEMDAAAA.',
Ma='Makoto:BAEBLgAECn8aAAIYAAcJlR3sCwBOAgdoDAAABQBaAGkMAAAFAFcAawwAAAUAWABqDAAABAA7AGwMAAADAE4AbQwAAAEAGgDqDAAAAwBTABgABwmVHewLAE4CB2gMAAAFAFoAaQwAAAUAVwBrDAAABQBYAGoMAAAEADsAbAwAAAMATgBtDAAAAQAaAOoMAAADAFMAAAA=.',
Mi='Migwangomage:BAEALgAFFAcJAQABLgAFFAgJGAAQAIMeAA==.Mistorin:BAEALgAECgMJAwABLgAFFAUJEwAMAO8kAA==.',
My='Mysaria:BAEALgAECgEJAQABLgAECgkJLgAKADwdAA==.',
Ne='Neodefender:BAECLgAFFH8rAAINAAgJZiTsAgDLAghoDAAACgBjAGkMAAAJAF4AawwAAAcAYwBqDAAABQBjAGwMAAADAF4AbQwAAAEASwDqDAAABwBhAG4MAAABAFMADQAICWYk7AIAywIIaAwAAAoAYwBpDAAACQBeAGsMAAAHAGMAagwAAAUAYwBsDAAAAwBeAG0MAAABAEsA6gwAAAcAYQBuDAAAAQBTAC4ABAp/MgACDQAJCecm/AAAiAMADQAJCecm/AAAiAMAAAA=.',
No='Nosferratu:BAECLgAFFH9TAAMBAAkJ5BzqAAAOAwloDAAADwBjAGkMAAANAF8AawwAAAwAWwBqDAAACQBdAGwMAAAIAE8AbQwAAAIANADqDAAADgBjAG4MAAAFACoAbwwAAAUAHgABAAkJ5BzqAAAOAwloDAAADwBjAGkMAAAMAF8AawwAAAsAWwBqDAAACQBdAGwMAAAIAE8AbQwAAAIANADqDAAADgBjAG4MAAAFACoAbwwAAAUAHgAcAAIJOAcAPwB9AAJpDAAAAQAPAGsMAAABABUALgAECn9BAAIBAAkJhCbcAAB6AwABAAkJhCbcAAB6AwAAAA==.',
Ny='Nyfaria:BAECLgAFFH8pAAIHAAUJih0AGgBUAQVoDAAACwBMAGkMAAAKAEUAawwAAAYARQBqDAAABABJAOoMAAAKAFYABwAFCYodABoAVAEFaAwAAAsATABpDAAACgBFAGsMAAAGAEUAagwAAAQASQDqDAAACgBWAC4ABAp/MgACBwAJCbIkDQIAQwMABwAJCbIkDQIAQwMAAAA=.',
Ol='Oldstandard:BAEALgAECgMJAwABLgAFFAkJNAAYAIAcAA==.',
Or='Orsp:BAECLgAFFH9IAAQBAAkJMh7nAAAQAwloDAAADQBiAGkMAAANAFoAawwAAAsAYQBqDAAACQBHAGwMAAAEADsAbQwAAAUAVQDqDAAADABcAG4MAAACACcAbwwAAAMANQABAAkJMh7nAAAQAwloDAAADQBiAGkMAAANAFoAawwAAAsAYQBqDAAABwBHAGwMAAABADsAbQwAAAUAVQDqDAAADABcAG4MAAACACcAbwwAAAMANQAcAAIJPAE+FgB+AAJqDAAAAQAAAGwMAAACAAUAAgACCeMEoRwAQgACagwAAAEAAwBsDAAAAQAVAC4ABAp/LQAEAQAJCcUjOwUAPQMAAQAJCcUjOwUAPQMAAgADCcoKCGUAmQAAHAADCcEZKmcAYQAAAAA=.Orspp:BAECLgAFFH8TAAMBAAUJlxXgDQAGAQVoDAAABgBVAGkMAAAGAEcAawwAAAEANADqDAAABQAoAG8MAAABABkAAQAFCZcV4A0ABgEFaAwAAAYAVQBpDAAABgBHAGsMAAABADQA6gwAAAEAKABvDAAAAQAZABwAAQkJFRJLAD8AAeoMAAAEADUALgAECn8cAAQBAAgJKBpuIQDMAQABAAgJKBpuIQDMAQACAAYJpQgiSQAUAQAcAAEJtQ3DVQA2AAABLgAFFAkJSAABADIeAA==.',
Pa='Pakk:BAEBLgAECn9EAAIFAAkJqCAXAgA+AgloDAAADABeAGkMAAALAFoAawwAAAoAUgBqDAAACQBXAGwMAAAJAFQAbQwAAAEAPwDqDAAACQBdAG4MAAAGAFYAbwwAAAEASQAFAAkJqCAXAgA+AgloDAAADABeAGkMAAALAFoAawwAAAoAUgBqDAAACQBXAGwMAAAJAFQAbQwAAAEAPwDqDAAACQBdAG4MAAAGAFYAbwwAAAEASQAAAA==.Pandoken:BAEBLgAFFH8XAAMdAAgJ7RxdDABCAghoDAAABABNAGkMAAAEAFEAawwAAAQAUgBqDAAAAgBEAGwMAAABAEwA6gwAAAQAQwBuDAAAAQA/AG8MAAADAEsAHQAICe0cXQwAQgIIaAwAAAMATQBpDAAAAwBRAGsMAAAEAFIAagwAAAIARABsDAAAAQBMAOoMAAAEAEMAbgwAAAEAPwBvDAAAAwBLAAgAAglJGRosAJ0AAmgMAAABAC8AaQwAAAEAUgABLgAFFAkJNgAJAGQjAA==.Pandotides:BAEALgAFFAUJAgABLgAFFAkJNgAJAGQjAA==.Papadefensve:BAEBLgAECn8aAAIPAAYJGSFLAgDZAQZoDAAABQBUAGkMAAAFAFUAawwAAAUAVQBqDAAAAwBXAGwMAAADAEsA6gwAAAUAXAAPAAYJGSFLAgDZAQZoDAAABQBUAGkMAAAFAFUAawwAAAUAVQBqDAAAAwBXAGwMAAADAEsA6gwAAAUAXAAAAA==.',
Ra='Razamon:BAEBLgAECn8rAAMKAAkJMSH5GgBzAgloDAAABgBcAGkMAAAFAFMAawwAAAUASgBqDAAABQBUAGwMAAAFAF4AbQwAAAQAVgDqDAAABQBRAG4MAAAFAF4AbwwAAAMASAAKAAkJMSH5GgBzAgloDAAAAgBcAGkMAAABAFMAawwAAAIASgBqDAAAAwBUAGwMAAAEAF4AbQwAAAQAVgDqDAAAAgBRAG4MAAAEAF4AbwwAAAMASAAOAAcJgxiJLgCpAQdoDAAABABSAGkMAAAEAEsAawwAAAMAOABqDAAAAgA/AGwMAAABADYA6gwAAAMASwBuDAAAAQAfAAAA.Razx:BAEALgAFFAIJAgABLgAFFAMJBQAbAOASAA==.',
Re='Recurse:BAEALgAFFAIJBAABLgAFFAkJFQAeADscAA==.',
Ri='Ripwwmonk:BAEALgADCgcJBwABLgAFFAcJHgAHAD8gAA==.',
Ro='Roukedhh:BAECLgAFFH8XAAIWAAcJxxzyGQDjAQdoDAAABgBSAGkMAAAEAEoAawwAAAMARQBqDAAAAQADAG0MAAABAD8A6gwAAAcAUQBuDAAAAQBHABYABwnHHPIZAOMBB2gMAAAGAFIAaQwAAAQASgBrDAAAAwBFAGoMAAABAAMAbQwAAAEAPwDqDAAABwBRAG4MAAABAEcALgAECn8eAAIWAAgJpyGQFgDPAgAWAAgJpyGQFgDPAgAAAA==.',
Ru='Runehaven:BAECLgAFFH8FAAIGAAQJzBeYMwD8AARoDAAAAgAwAGkMAAABAFQAawwAAAEASwDqDAAAAQAiAAYABAnMF5gzAPwABGgMAAACADAAaQwAAAEAVABrDAAAAQBLAOoMAAABACIALgAECn8YAAMGAAYJlB3PjABLAQAGAAYJlB3PjABLAQAFAAYJggpnOwCkAAABLgAFFAQJBQAGAMwXAA==.',
Sa='Sairal:BAEBLgAFFH8bAAIYAAkJuhseAQDPAgloDAAABABgAGkMAAADAFIAawwAAAQAUwBqDAAABABBAGwMAAADADgAbQwAAAIAJgDqDAAAAwBfAG4MAAACAE0AbwwAAAIAJgAYAAkJuhseAQDPAgloDAAABABgAGkMAAADAFIAawwAAAQAUwBqDAAABABBAGwMAAADADgAbQwAAAIAJgDqDAAAAwBfAG4MAAACAE0AbwwAAAIAJgABLgAFFAkJNAAYAIAcAA==.Sargala:BAEBLgAECn84AAMfAAkJTh3HBgAKAgloDAAACwBQAGkMAAAKAFcAawwAAAwASQBqDAAABgBKAGwMAAAFAFIAbQwAAAIALADqDAAABwBWAG4MAAACAEcAbwwAAAEASgAfAAkJTh3HBgAKAgloDAAACgBQAGkMAAAJAFcAawwAAAsASQBqDAAABQBKAGwMAAAFAFIAbQwAAAIALADqDAAABwBWAG4MAAACAEcAbwwAAAEASgAgAAQJ5wW5SgCMAARoDAAAAQATAGkMAAABABIAawwAAAEABwBqDAAAAQATAAAA.',
Sc='Scootybooty:BAEALgAECgUJBQAAAA==.Scootyclap:BAEALgADCgQJBAABLgAECgUJBQADAAAAAA==.Scootypriest:BAEALgADCggJCAABLgAECgUJBQADAAAAAA==.Scootysnack:BAEALgADCgcJEAABLgAECgUJBQADAAAAAA==.Scussy:BAEALgADCgcJBwABLgAECgUJBQADAAAAAA==.',
Sm='Smitehaven:BAEALgAFFAIJAgABLgAFFAQJBQAGAMwXAA==.Smoothdk:BAEBLgAFFH8FAAQGAAIJMxGMYgCKAAJoDAAAAwAhAOoMAAACADYABgACCTMRjGIAigACaAwAAAIAIQDqDAAAAQA2ACEAAQnwBLgqAD0AAWgMAAABAAwABQABCZoFIkQAJgAB6gwAAAEADgABLgAFFAQJCQAiAHcaAA==.Smoothp:BAEALgAFFAIJAgABLgAFFAQJCQAiAHcaAA==.Smoothz:BAEALgAFFAIJAgABLgAFFAQJCQAiAHcaAA==.',
Th='Thez:BAEALgAECgEJAQABLgAECgkJKAAYAFMdAA==.Thezdin:BAEBLgAECn8oAAIYAAkJUx35CABnAgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAAEAFEAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAYAAkJUx35CABnAgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAAEAFEAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAAAA==.Thezfu:BAEALgAECgEJAwABLgAECgkJKAAYAFMdAA==.',
Ve='Velohm:BAEBLgAECn8pAAMdAAkJLSEPAQAtAwloDAAACgBXAGkMAAAGAFMAawwAAAUAXABqDAAABQBXAGwMAAADAFkAbQwAAAEATgDqDAAABgBaAG4MAAADAEgAbwwAAAIAUwAdAAkJLSEPAQAtAwloDAAACABXAGkMAAAEAFMAawwAAAMAXABqDAAAAwBXAGwMAAADAFkAbQwAAAEATgDqDAAABQBaAG4MAAADAEgAbwwAAAIAUwAIAAUJSAhYYgCUAAVoDAAAAgAjAGkMAAACABMAawwAAAIADQBqDAAAAgAmAOoMAAABAA8AAAA=.',
Wr='Wreckss:BAEBLgAECn8WAAMOAAcJXhOgOQBQAQdoDAAABAAtAGkMAAAEADQAawwAAAQAPABqDAAAAwArAGwMAAACADkAbQwAAAEALADqDAAABAAjAA4ABwleE6A5AFABB2gMAAADAC0AaQwAAAQANABrDAAABAA8AGoMAAACACsAbAwAAAIAOQBtDAAAAQAsAOoMAAAEACMAFAACCRcJ2ysANgACaAwAAAEAFwBqDAAAAQARAAEuAAUUBAkTAAQA7hQA.',
Zi='Zick:BAEALgAFFAgJAQAAAA==.Zigle:BAEBLgAFFH8XAAIiAAcJ1yH5AACvAgdoDAAAAwBfAGkMAAADAFsAawwAAAMAXQBsDAAABABUAG0MAAADAEwA6gwAAAQAXwBuDAAAAwBFACIABwnXIfkAAK8CB2gMAAADAF8AaQwAAAMAWwBrDAAAAwBdAGwMAAAEAFQAbQwAAAMATADqDAAABABfAG4MAAADAEUAAS4ABRQHCRgABwBfHgA=.Zikker:BAEALgADCgcJBwABLgAFFAgJAQADAAAAAA==.',
Zo='Zoe:BAECLgAFFH8YAAIHAAcJXx5+BQBAAgdoDAAABQBZAGkMAAAFAGMAawwAAAQAUgBsDAAAAQAlAG0MAAABAF8A6gwAAAcAWgBuDAAAAQAwAAcABwlfHn4FAEACB2gMAAAFAFkAaQwAAAUAYwBrDAAABABSAGwMAAABACUAbQwAAAEAXwDqDAAABwBaAG4MAAABADAALgAECn8vAAIHAAgJVyY5BQDuAgAHAAgJVyY5BQDuAgAAAA==.Zogle:BAEBLgAFFH8QAAIFAAYJOxZgIgDYAAZoDAAAAQA3AGkMAAABAC4AawwAAAEAPABqDAAACABHAOoMAAABACEAbwwAAAQAWQAFAAYJOxZgIgDYAAZoDAAAAQA3AGkMAAABAC4AawwAAAEAPABqDAAACABHAOoMAAABACEAbwwAAAQAWQABLgAFFAcJGAAHAF8eAA==.Zoog:BAEALgAECggJEwABLgAFFAcJGAAHAF8eAA==.',
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
