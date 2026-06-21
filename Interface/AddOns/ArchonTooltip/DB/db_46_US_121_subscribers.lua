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

local lookup = {'Priest-Shadow','Priest-Holy','Monk-Windwalker','Rogue-Subtlety','DeathKnight-Blood','DeathKnight-Unholy','Monk-Brewmaster','Druid-Restoration','Hunter-BeastMastery','Mage-Arcane','Paladin-Retribution','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Mage-Frost','Paladin-Protection','Rogue-Assassination','Shaman-Enhancement','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Outlaw','Druid-Guardian','Druid-Balance','Evoker-Augmentation','Warrior-Protection','Evoker-Preservation','Druid-Feral','Priest-Discipline','Monk-Mistweaver','Hunter-Marksmanship','Hunter-Survival','Warlock-Demonology',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=46,date='2026-06-20',data={As='Astaren:BAEBLgAECn8TAAMBAAkJOQkiMwBNAQloDAAAAwAnAGkMAAACACoAawwAAAIACQBqDAAAAgAWAGwMAAABABAAbQwAAAEACADqDAAABgAkAG4MAAABAAQAbwwAAAEAHgABAAkJOQkiMwBNAQloDAAAAwAnAGkMAAACACoAawwAAAIACQBqDAAAAgAWAGwMAAABABAAbQwAAAEACADqDAAABQAkAG4MAAABAAQAbwwAAAEAHgACAAEJ1hfUaABCAAHqDAAAAQA9AAAA.',
Av='Avenmonk:BAECLgAFFH8gAAIDAAcJTRxXBADsAQdoDAAACQBhAGkMAAAFAFcAawwAAAYAPQBqDAAAAgAVAG0MAAABADgA6gwAAAgAUQBuDAAAAQAxAAMABwlNHFcEAOwBB2gMAAAJAGEAaQwAAAUAVwBrDAAABgA9AGoMAAACABUAbQwAAAEAOADqDAAACABRAG4MAAABADEALgAECn8yAAIDAAkJTyRfAQCiAwADAAkJTyRfAQCiAwAAAA==.Avenstealth:BAEBLgAECn8kAAIEAAkJoBQ9GgDGAQloDAAABQBLAGkMAAAFAEkAawwAAAUAOgBqDAAABQBKAGwMAAAFAD8AbQwAAAIAGQDqDAAABgBIAG4MAAACACMAbwwAAAEAEgAEAAkJoBQ9GgDGAQloDAAABQBLAGkMAAAFAEkAawwAAAUAOgBqDAAABQBKAGwMAAAFAD8AbQwAAAIAGQDqDAAABgBIAG4MAAACACMAbwwAAAEAEgABLgAFFAcJIAADAE0cAA==.',
Az='Azchath:BAEALgAFFAIJAgAAAQ==.',
Br='Bryl:BAECLgAFFH8RAAIFAAcJjReSDAC1AQdoDAAAAgBYAGkMAAABACYAawwAAAEARABqDAAABQA5AGwMAAABADgAbQwAAAEADQDqDAAABgBfAAUABwmNF5IMALUBB2gMAAACAFgAaQwAAAEAJgBrDAAAAQBEAGoMAAAFADkAbAwAAAEAOABtDAAAAQANAOoMAAAGAF8ALgAECn8gAAMFAAkJ2x6rBgDKAgAFAAkJ2x6rBgDKAgAGAAcJYxEccQClAQAAAA==.Brylic:BAECLgAFFH8YAAMHAAUJZSOLDADOAQVoDAAABwBYAGkMAAAHAGEAawwAAAUAWQBsDAAAAgBcAOoMAAADAFUABwAFCbMgiwwAzgEFaAwAAAYAWABpDAAABwBhAGsMAAAFAFkAbAwAAAIAXADqDAAAAQAzAAMAAgmIIEUmALoAAmgMAAABAFAA6gwAAAIAVQAuAAQKfyYAAwMACAk5IyQGAB8DAAMACAkmISQGAB8DAAcACAmqIjIIAAIDAAEuAAUUBwkRAAUAjRcA.Brylicet:BAEALgAFFAQJBAABLgAFFAcJEQAFAI0XAA==.',
Ca='Camreon:BAEALgAFFAEJAgAAAA==.Captpando:BAEALgAECgQJBAABLgAFFAkJJQAIAP0hAA==.',
Ce='Cenitarius:BAEALgADCgcJBwABLgAECgkJOgAJAOYlAA==.',
Cm='Cmenstabber:BAECLgAFFH8LAAIEAAMJbAfCLQDBAANoDAAAAwARAGkMAAACAAQA6gwAAAYAIwAEAAMJbAfCLQDBAANoDAAAAwARAGkMAAACAAQA6gwAAAYAIwAuAAQKfzQAAgQACQkCFugPAC8CAAQACQkCFugPAC8CAAAA.',
Da='Dantius:BAEALgAECgcJBwABLgAFFAMJDQAKAOQWAA==.Darkorin:BAECLgAFFH8SAAILAAUJ7yQrIQCCAQVoDAAABwBiAGkMAAADAGIAawwAAAMAVgBqDAAAAQA5AOoMAAAEAF8ACwAFCe8kKyEAggEFaAwAAAcAYgBpDAAAAwBiAGsMAAADAFYAagwAAAEAOQDqDAAABABfAC4ABAp/LQADCwAJCYklswYAZQMACwAICUsmswYAZQMADAACCcsOiooANgAAAAA=.',
Du='Duskorin:BAEBLgAFFH8MAAMNAAUJ5BiZTwC3AAVoDAAAAwAvAGwMAAABACQAbQwAAAEAXwDqDAAABgAyAG4MAAABAFgADQADCYoRmU8AtwADaAwAAAMALwBsDAAAAQAkAOoMAAADADIADgADCUMV8gYAZwADbQwAAAEAUgDqDAAAAwA9AG4MAAABABMAAS4ABRQFCRIACwDvJAA=.',
Fi='Fishybrew:BAEBLgAECn8tAAIHAAgJYyLLCACmAghoDAAACQBaAGkMAAAIAFsAawwAAAcAUgBqDAAABgBYAGwMAAAFAFAAbQwAAAEAVQDqDAAABwBdAG4MAAACAF0ABwAICWMiywgApgIIaAwAAAkAWgBpDAAACABbAGsMAAAHAFIAagwAAAYAWABsDAAABQBQAG0MAAABAFUA6gwAAAcAXQBuDAAAAgBdAAEuAAQKBgkOAA8AAAAA.',
Fl='Fleasfordays:BAEALgAECgIJAgABLgAFFAMJCwAEAGwHAA==.',
Fo='Foxblade:BAEALgAECgcJDQABLgAECggJHAAQANYYAA==.Foxleaf:BAEALgAECgEJAQABLgAECggJHAAQANYYAA==.Foxorcism:BAEBLgAECn8XAAQMAAcJPBVENACBAQdoDAAABABSAGkMAAAEADEAawwAAAQATABqDAAABAA3AGwMAAACAB0AbQwAAAEABADqDAAABABSAAwABgl5GEQ0AIEBBmgMAAADAFIAaQwAAAMAMQBrDAAAAwBMAGoMAAAEADcAbAwAAAIAHQDqDAAABABSAAsAAwl9BylKAWMAA2gMAAABACoAaQwAAAEABQBrDAAAAQAJABEAAQn6A+1VACQAAW0MAAABAAoAAS4ABAoICRwAEADWGAA=.Foxox:BAEBLgAECn8cAAIQAAgJ1hhGXgDEAQhoDAAABwBKAGkMAAAFAEIAawwAAAQAPgBsDAAABABNAG0MAAACADMA6gwAAAMARQBuDAAAAgA2AG8MAAABADQAEAAICdYYRl4AxAEIaAwAAAcASgBpDAAABQBCAGsMAAAEAD4AbAwAAAQATQBtDAAAAgAzAOoMAAADAEUAbgwAAAIANgBvDAAAAQA0AAAA.',
Fr='Fries:BAEBLgAFFH8FAAMEAAMJmQmkMwCTAANoDAAAAQAyAOoMAAADABIAbgwAAAEABAAEAAIJeQ2kMwCTAAJoDAAAAQAyAOoMAAADABIAEgABCdgBiBIAQgABbgwAAAEABAABLgAFFAUJCgATAP8eAA==.Frip:BAEALgAECgIJAgABLgAECgkJOgAJAOYlAA==.',
Ga='Gardenweed:BAEBLgAECn8hAAILAAkJVgk7igBcAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQALAAkJVgk7igBcAQloDAAABQAjAGkMAAAFABoAawwAAAUAEwBqDAAABQAaAGwMAAAFACgAbQwAAAEADwDqDAAABQAXAG4MAAABAAwAbwwAAAEAEQAAAA==.',
Gr='Grimmyb:BAECLgAFFH8LAAMUAAMJABpCYQDMAANoDAAAAwAxAGkMAAADAEAA6gwAAAUAVQAUAAMJhhZCYQDMAANoDAAAAwAxAGkMAAADAEAA6gwAAAQAOgAVAAEJWiGGDwBXAAHqDAAAAQBVAC4ABAp/JwADFQAJCZgh8gEA8QIAFQAICdsh8gEA8QIAFAAJCaEbB0AAyQEAAS4ABRQJCSgAFQC5HwA=.Grìmbles:BAECLgAFFH8oAAIVAAkJuR8SAAAoAgloDAAABwBiAGkMAAAIAGEAawwAAAgAZABqDAAAAQBQAGwMAAAEAFgAbQwAAAIAZADqDAAABABYAG4MAAADADEAbwwAAAMAGwAVAAkJuR8SAAAoAgloDAAABwBiAGkMAAAIAGEAawwAAAgAZABqDAAAAQBQAGwMAAAEAFgAbQwAAAIAZADqDAAABABYAG4MAAADADEAbwwAAAMAGwAuAAQKfx0AAhUACQmdJTgAAJcDABUACQmdJTgAAJcDAAAA.',
Gu='Guthyne:BAEALgAECgMJBgABLgAECgkJLwAWADYmAA==.Guthynn:BAEBLgAECn8vAAMWAAkJNiYtAAB2AwloDAAACgBhAGkMAAAHAGIAawwAAAcAYgBqDAAABABiAGwMAAADAGIAbQwAAAQAYgDqDAAABgBjAG4MAAAFAGEAbwwAAAEAXgAWAAkJNiYtAAB2AwloDAAABgBhAGkMAAAGAGIAawwAAAYAYgBqDAAAAwBiAGwMAAACAGIAbQwAAAQAYgDqDAAABgBjAG4MAAAFAGEAbwwAAAEAXgASAAUJPyHBCgCIAQVoDAAABABXAGkMAAABAFMAawwAAAEAXwBqDAAAAQBfAGwMAAABAEoAAAA=.',
Gw='Gwimbles:BAECLgAFFH8OAAIFAAMJyhCIDACtAANoDAAAAwA7AGoMAAAEABIA6gwAAAcAGgAFAAMJyhCIDACtAANoDAAAAwA7AGoMAAAEABIA6gwAAAcAGgAuAAQKfy0AAgUACQmMHiYHAL4CAAUACQmMHiYHAL4CAAEuAAUUCQkoABUAuR8A.Gwìmbles:BAEBLgAFFH8IAAMXAAUJ2QX/OQBAAAVoDAAAAwA6AGkMAAABAAAAawwAAAEAAABqDAAAAQABAOoMAAACAAEAFwACCagL/zkAQAACaAwAAAIAOgDqDAAAAgABABgABAkKAGVZAAQABGgMAAABAAAAaQwAAAEAAABrDAAAAQAAAGoMAAABAAEAAS4ABRQJCSgAFQC5HwA=.',
Ir='Irro:BAEALgAECgYJCwABLgAECgkJLgANADwdAA==.Irrofel:BAEALgAECgQJBAABLgAECgkJLgANADwdAA==.Irrogenia:BAEBLgAECn8uAAMNAAkJPB3LEADJAgloDAAABwBgAGkMAAAHAFUAawwAAAYAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgANAAkJPB3LEADJAgloDAAABwBgAGkMAAAGAFUAawwAAAUAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAFAEAAbwwAAAIAHgAOAAIJ/QryjABXAAJpDAAAAQAiAGsMAAABABUAAAA=.Irrowen:BAEALgAECgYJBgABLgAECgkJLgANADwdAA==.',
Ja='Jarik:BAEALgAECgQJDAABLgAECgkJOgAJAOYlAA==.',
La='Larias:BAECLgAFFH8OAAIZAAUJTx0LBgCeAQVoDAAABQBgAGkMAAAEAGEAawwAAAEAFgBsDAAAAQBcAOoMAAADAEIAGQAFCU8dCwYAngEFaAwAAAUAYABpDAAABABhAGsMAAABABYAbAwAAAEAXADqDAAAAwBCAC4ABAp/IgACGQAICZUmTwIAjQMAGQAICZUmTwIAjQMAAS4ABRQGCRAAGgD9GwA=.',
Li='Lidariel:BAEALgAECggJDwABLgAFFAQJCwAbAP8PAA==.Lidathra:BAECLgAFFH8LAAIbAAQJ/w8kGwDkAARoDAAABAAgAGkMAAADAC8AawwAAAEAIQDqDAAAAwAyABsABAn/DyQbAOQABGgMAAAEACAAaQwAAAMALwBrDAAAAQAhAOoMAAADADIALgAECn8sAAIbAAkJ5hViCwAlAgAbAAkJ5hViCwAlAgAAAA==.Lidiosa:BAEBLgAECn8nAAIQAAkJdhr+JACIAgloDAAABwBeAGkMAAAFAE0AawwAAAUAPQBqDAAABAA9AGwMAAAEAEoAbQwAAAIANwDqDAAACQA8AG4MAAACAEwAbwwAAAEAKgAQAAkJdhr+JACIAgloDAAABwBeAGkMAAAFAE0AawwAAAUAPQBqDAAABAA9AGwMAAAEAEoAbQwAAAIANwDqDAAACQA8AG4MAAACAEwAbwwAAAEAKgABLgAFFAQJCwAbAP8PAA==.Lidishi:BAEALgAECgYJCQABLgAFFAQJCwAbAP8PAA==.Lidizine:BAEALgADCggJDAABLgAFFAQJCwAbAP8PAA==.',
Lo='Lochru:BAEBLgAECn9PAAIcAAkJ4yMzAQBDAwloDAAACwBhAGkMAAAKAFgAawwAAAsAUgBqDAAACQBiAGwMAAAJAF4AbQwAAAgAWQDqDAAACgBfAG4MAAAHAF8AbwwAAAQAWwAcAAkJ4yMzAQBDAwloDAAACwBhAGkMAAAKAFgAawwAAAsAUgBqDAAACQBiAGwMAAAJAF4AbQwAAAgAWQDqDAAACgBfAG4MAAAHAF8AbwwAAAQAWwAAAA==.',
Ma='Makoto:BAEBLgAECn8aAAIaAAcJlR3sCwBOAgdoDAAABQBaAGkMAAAFAFcAawwAAAUAWABqDAAABAA7AGwMAAADAE4AbQwAAAEAGgDqDAAAAwBTABoABwmVHewLAE4CB2gMAAAFAFoAaQwAAAUAVwBrDAAABQBYAGoMAAAEADsAbAwAAAMATgBtDAAAAQAaAOoMAAADAFMAAAA=.',
Mi='Mistorin:BAEALgAECgMJAwABLgAFFAUJEgALAO8kAA==.',
Na='Nalfein:BAEALgAECggJDAABLgAECgkJOgAJAOYlAA==.',
Ne='Neodefender:BAECLgAFFH8qAAIMAAcJ7iTyAgDLAgdoDAAACgBjAGkMAAAJAF4AawwAAAcAYwBqDAAABQBjAGwMAAADAF4AbQwAAAEASwDqDAAABwBhAAwABwnuJPICAMsCB2gMAAAKAGMAaQwAAAkAXgBrDAAABwBjAGoMAAAFAGMAbAwAAAMAXgBtDAAAAQBLAOoMAAAHAGEALgAECn8yAAIMAAkJ5yb8AACIAwAMAAkJ5yb8AACIAwAAAA==.',
No='Nosferratu:BAECLgAFFH8qAAMBAAgJthyHAQC2AghoDAAACgBjAGkMAAAHAF4AawwAAAcAWwBqDAAABQAcAGwMAAACAD0A6gwAAAkAYwBuDAAAAQAoAG8MAAABABoAAQAICbYchwEAtgIIaAwAAAoAYwBpDAAABgBeAGsMAAAGAFsAagwAAAUAHABsDAAAAgA9AOoMAAAJAGMAbgwAAAEAKABvDAAAAQAaAB0AAgk4BwM/AH0AAmkMAAABAA8AawwAAAEAFQAuAAQKf0EAAgEACQmEJt0AAHoDAAEACQmEJt0AAHoDAAAA.',
Ny='Nyfaria:BAECLgAFFH8mAAIHAAUJwhwOGgBUAQVoDAAACgBMAGkMAAAJAD0AawwAAAYARQBqDAAABABJAOoMAAAJAFYABwAFCcIcDhoAVAEFaAwAAAoATABpDAAACQA9AGsMAAAGAEUAagwAAAQASQDqDAAACQBWAC4ABAp/LAACBwAJCQ4kDQIAQwMABwAJCQ4kDQIAQwMAAAA=.',
Ol='Oldstandard:BAEALgAECgMJAwABLgAFFAYJEAAaAP0bAA==.',
Oo='Ookook:BAEALgADCgYJBgABLgAFFAkJKAAVALkfAA==.',
Or='Orsp:BAECLgAFFH8qAAQBAAgJRhXgCQDEAQhoDAAACgBiAGkMAAAIAFEAawwAAAcATABqDAAABABHAGwMAAACAAIAbQwAAAEAGwDqDAAACQBaAG8MAAABAAQAAQAHCa0Y4AkAxAEHaAwAAAoAYgBpDAAACABRAGsMAAAHAEwAagwAAAIARwBtDAAAAQAbAOoMAAAJAFoAbwwAAAEABAAdAAIJPAE+FgB+AAJqDAAAAQAAAGwMAAACAAUAAgABCUYB7hQAQQABagwAAAEAAwAuAAQKfyoABAEACQk3IzsFAD0DAAEACQk3IzsFAD0DAAIAAwnKCghlAJkAAB0AAwnBGSVnAGEAAAAA.Orspp:BAECLgAFFH8OAAMBAAQJQBUYGQAfAQRoDAAABABAAGkMAAAEADsAawwAAAEANADqDAAABQAoAAEABAlAFRgZAB8BBGgMAAAEAEAAaQwAAAQAOwBrDAAAAQA0AOoMAAABACgAHQABCQkVFEsAPwAB6gwAAAQANQAuAAQKfxwABAEACAkoGm4hAMwBAAEACAkoGm4hAMwBAAIABgmlCCJJABQBAB0AAQm1DcNVADYAAAEuAAUUCAkqAAEARhUA.',
Pa='Pakk:BAEBLgAECn9CAAIFAAgJOSHOCACHAghoDAAADABeAGkMAAALAFoAawwAAAoAUgBqDAAACQBXAGwMAAAJAFQAbQwAAAEAPwDqDAAACQBdAG4MAAAFAFYABQAICTkhzggAhwIIaAwAAAwAXgBpDAAACwBaAGsMAAAKAFIAagwAAAkAVwBsDAAACQBUAG0MAAABAD8A6gwAAAkAXQBuDAAABQBWAAAA.Pandoken:BAEBLgAFFH8SAAMeAAcJYxu5EgDzAQdoDAAABABNAGkMAAAEAFEAawwAAAQAUgBqDAAAAgBEAGwMAAABAEwA6gwAAAIAQABvDAAAAQAoAB4ABwljG7kSAPMBB2gMAAADAE0AaQwAAAMAUQBrDAAABABSAGoMAAACAEQAbAwAAAEATADqDAAAAgBAAG8MAAABACgAAwACCUkZGywAnQACaAwAAAEALwBpDAAAAQBSAAEuAAUUCQklAAgA/SEA.Pandotides:BAEALgAFFAUJAgABLgAFFAkJJQAIAP0hAA==.Papadefensve:BAEALgAECgYJDgAAAA==.',
Pr='Priff:BAEBLgAECn86AAQJAAkJ5iUTBABQAwloDAAACABiAGkMAAAIAGEAawwAAAgAXQBqDAAABgBgAGwMAAAHAFsAbQwAAAYAYwDqDAAACQBgAG4MAAAEAGMAbwwAAAIAYgAJAAkJ2iUTBABQAwloDAAAAwBhAGkMAAAFAGEAawwAAAQAXQBqDAAAAwBgAGwMAAABAFsAbQwAAAUAYwDqDAAAAwBgAG4MAAAEAGMAbwwAAAIAYgAfAAcJ9yFfGABqAgdoDAAAAwBTAGkMAAADAFwAawwAAAMASgBqDAAAAgAoAGwMAAAEAFQAbQwAAAEAXwDqDAAAAwBaACAABQnlIUAnAGQBBWgMAAACAGIAawwAAAEASgBqDAAAAQBTAGwMAAACAFQA6gwAAAMAWQAAAA==.Priffraff:BAEALgAECggJEwABLgAECgkJOgAJAOYlAA==.',
Ra='Razamon:BAEBLgAECn8rAAMNAAkJMSH3GgBzAgloDAAABgBcAGkMAAAFAFMAawwAAAUASgBqDAAABQBUAGwMAAAFAF4AbQwAAAQAVgDqDAAABQBRAG4MAAAFAF4AbwwAAAMASAANAAkJMSH3GgBzAgloDAAAAgBcAGkMAAABAFMAawwAAAIASgBqDAAAAwBUAGwMAAAEAF4AbQwAAAQAVgDqDAAAAgBRAG4MAAAEAF4AbwwAAAMASAAOAAcJgxiJLgCpAQdoDAAABABSAGkMAAAEAEsAawwAAAMAOABqDAAAAgA/AGwMAAABADYA6gwAAAMASwBuDAAAAQAfAAAA.',
Re='Recurse:BAEALgAFFAIJBAABLgAFFAkJOwAhAIgcAA==.',
Ri='Ripwwmonk:BAEALgADCgcJBwABLgAFFAcJEQAFAI0XAA==.',
Ro='Roukedhh:BAECLgAFFH8WAAIUAAcJxxwFGgDjAQdoDAAABQBSAGkMAAAEAEoAawwAAAMARQBqDAAAAQADAG0MAAABAD8A6gwAAAcAUQBuDAAAAQBHABQABwnHHAUaAOMBB2gMAAAFAFIAaQwAAAQASgBrDAAAAwBFAGoMAAABAAMAbQwAAAEAPwDqDAAABwBRAG4MAAABAEcALgAECn8eAAIUAAgJpyGQFgDPAgAUAAgJpyGQFgDPAgAAAA==.',
Ru='Runehaven:BAEBLgAECn8WAAMGAAYJHx3QjABLAQZoDAAABgBUAGkMAAAEAFQAawwAAAQAUABqDAAAAgAwAGwMAAADADQA6gwAAAMARgAGAAYJHx3QjABLAQZoDAAABABUAGkMAAADAFQAawwAAAMAUABqDAAAAQAwAGwMAAABADQA6gwAAAIARgAFAAYJggpkOwCkAAZoDAAAAgAnAGkMAAABABUAawwAAAEAEQBqDAAAAQAfAGwMAAACACUA6gwAAAEAEgABLgAECgYJFgAGAB8dAA==.',
Sa='Sargala:BAEBLgAECn8xAAMJAAgJfRrMKgAyAghoDAAACgBQAGkMAAAJAEkAawwAAAsAOABqDAAABQBKAGwMAAAEAFIAbQwAAAEAFwDqDAAABwBWAG4MAAACAEcACQAICX0azCoAMgIIaAwAAAkAUABpDAAACABJAGsMAAAKADgAagwAAAQASgBsDAAABABSAG0MAAABABcA6gwAAAcAVgBuDAAAAgBHACAABAnnBbVKAIwABGgMAAABABMAaQwAAAEAEgBrDAAAAQAHAGoMAAABABMAAAA=.',
Sc='Scootybooty:BAEALgAECgUJBQAAAA==.Scootyclap:BAEALgADCgQJBAABLgAECgUJBQAPAAAAAA==.Scootypriest:BAEALgADCggJCAABLgAECgUJBQAPAAAAAA==.Scootysnack:BAEALgADCgcJEAABLgAECgUJBQAPAAAAAA==.Scussy:BAEALgADCgcJBwABLgAECgUJBQAPAAAAAA==.',
Sm='Smitehaven:BAEALgAFFAIJAgABLgAECgYJFgAGAB8dAA==.Smoothdk:BAEALgAFFAIJAgABLgAFFAUJBQAXABEFAA==.Smoothp:BAEALgAFFAIJAgABLgAFFAUJBQAXABEFAA==.Smoothz:BAEALgAFFAIJAgABLgAFFAUJBQAXABEFAA==.',
Th='Thez:BAEALgAECgEJAQABLgAECgkJKAAaAFMdAA==.Thezdin:BAEBLgAECn8oAAIaAAkJUx36CABnAgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAAEAFEAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAaAAkJUx36CABnAgloDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAAEAFEAbQwAAAIAEgDqDAAACgBPAG4MAAABAGIAbwwAAAEASgAAAA==.Thezfu:BAEALgAECgEJAwABLgAECgkJKAAaAFMdAA==.',
Ve='Velohm:BAEBLgAECn8bAAMeAAYJ6CGbGgBDAgZoDAAACABXAGkMAAAFAFAAawwAAAQAXABqDAAABABXAGwMAAACAFIA6gwAAAQAWgAeAAYJ6CGbGgBDAgZoDAAABgBXAGkMAAADAFAAawwAAAIAXABqDAAAAgBXAGwMAAACAFIA6gwAAAMAWgADAAUJSAhaYgCUAAVoDAAAAgAjAGkMAAACABMAawwAAAIADQBqDAAAAgAmAOoMAAABAA8AAAA=.',
Zi='Zick:BAEALgAFFAgJAQAAAA==.Zikker:BAEALgADCgcJBwABLgAFFAgJAQAPAAAAAA==.',
Zo='Zoe:BAECLgAFFH8YAAIHAAcJXx6BBQBAAgdoDAAABQBZAGkMAAAFAGMAawwAAAQAUgBsDAAAAQAlAG0MAAABAF8A6gwAAAcAWgBuDAAAAQAwAAcABwlfHoEFAEACB2gMAAAFAFkAaQwAAAUAYwBrDAAABABSAGwMAAABACUAbQwAAAEAXwDqDAAABwBaAG4MAAABADAALgAECn8vAAIHAAgJVyY4BQDuAgAHAAgJVyY4BQDuAgAAAA==.Zogle:BAEBLgAFFH8JAAIFAAUJGRNkIgDYAAVoDAAAAQA3AGkMAAABAC4AawwAAAEAPABqDAAABQAcAOoMAAABACEABQAFCRkTZCIA2AAFaAwAAAEANwBpDAAAAQAuAGsMAAABADwAagwAAAUAHADqDAAAAQAhAAEuAAUUBwkYAAcAXx4A.Zoog:BAEALgAECggJEwABLgAFFAcJGAAHAF8eAA==.',
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
