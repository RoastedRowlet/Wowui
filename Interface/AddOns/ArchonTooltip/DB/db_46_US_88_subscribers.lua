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

local lookup = {'Warlock-Affliction','DemonHunter-Devourer','DemonHunter-Havoc','Unknown-Unknown','DeathKnight-Blood','Rogue-Assassination','Warrior-Protection','Monk-Mistweaver','DemonHunter-Vengeance','Paladin-Holy','Warlock-Demonology','Paladin-Retribution','Monk-Brewmaster','Druid-Restoration','Priest-Discipline','Evoker-Augmentation','Hunter-Survival','Paladin-Protection','Rogue-Subtlety','Monk-Windwalker','Mage-Frost','Mage-Arcane','Druid-Balance','Priest-Shadow','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Holy','Warlock-Destruction',}
local provider = {region='US',realm='EmeraldDream',name='US',type='subscribers',zone=46,date='2026-07-07',data={Al='Alleryia:BAEALgAECgcJEgABLgAFFAUJFwABAHIZAA==.',
Bl='Blacephalon:BAEBLgAECn8RAAMCAAgJAx2VMAA5AghoDAAAAwBGAGkMAAACAFgAawwAAAMAVwBqDAAAAQAlAGwMAAACAEQAbQwAAAIAOgDqDAAAAwBXAG4MAAABADwAAgAICQMdlTAAOQIIaAwAAAMARgBpDAAAAgBYAGsMAAABAFcAagwAAAEAJQBsDAAAAgBEAG0MAAACADoA6gwAAAMAVwBuDAAAAQA8AAMAAQmNB4J3AC0AAWsMAAACABMAAS4ABAoJCRAABAAAAAA=.',
Bu='Bungulator:BAEALgADCgkJCQABLgAFFAQJEgAFAH8TAA==.',
Ca='Calsbigdk:BAEALgAECgEJAQABLgAFFAgJJgAGABUdAA==.',
Ch='Chûd:BAEALgAECgUJBQAAAA==.',
Cj='Cjk:BAECLgAFFH8SAAIHAAQJ3RisBQASAQRoDAAABABAAGkMAAAFAD0AawwAAAQAPgDqDAAABQBCAAcABAndGKwFABIBBGgMAAAEAEAAaQwAAAUAPQBrDAAABAA+AOoMAAAFAEIALgAECn8xAAIHAAgJgCT4BQCxAgAHAAgJgCT4BQCxAgAAAA==.',
Da='Daddio:BAEALgAECgQJCwABLgADCgcJBwAEAAAAAA==.Damio:BAEALgAFFAQJBAABLgAFFAkJKAAIAFgbAA==.',
De='Dechu:BAECLgAFFH8nAAMJAAYJuiC6AgB9AQZoDAAACwBfAGkMAAAKAFoAawwAAAcAYQBqDAAABABGAGwMAAABADUA6gwAAAYAUQACAAYJxx17IwCiAQZoDAAACgBfAGkMAAAJAFQAawwAAAYARgBqDAAAAwA/AGwMAAABADUA6gwAAAUASwAJAAUJziG6AgB9AQVoDAAAAQBMAGkMAAABAFoAawwAAAEAYQBqDAAAAQBGAOoMAAABAFEALgAECn8+AAMJAAkJUSWbAABQAwAJAAkJUSWbAABQAwACAAgJRx5ZJwAuAgABLgAFFAgJJgAGABUdAA==.Deddio:BAEALgADCgcJBwAAAA==.',
Dr='Drampa:BAEALgADCgUJCgABLgAECgkJEAAEAAAAAA==.',
El='Elysius:BAEALgAECgQJCQAAAA==.',
En='Energizer:BAEALgAECgIJAgABLgAFFAQJDAAKABsgAA==.',
Et='Etheryia:BAECLgAFFH8XAAMBAAUJchkECAD6AAVoDAAABgBKAGkMAAAFAEwAawwAAAMAHwBqDAAAAgAdAOoMAAAHAE0ACwAFCdUVVk0ALAEFaAwAAAUASABpDAAAAwAqAGsMAAADAB8AagwAAAEAHQDqDAAABABNAAEABAnBHQQIAPoABGgMAAABAEoAaQwAAAIATABqDAAAAQAHAOoMAAADAEwALgAECn8qAAILAAkJUiE4EgC6AgALAAkJUiE4EgC6AgAAAA==.',
Fa='Fartslinger:BAEALgADCgQJBAABLgAFFAcJIQAMAOYcAA==.',
Fe='Felenmonk:BAEBLgAFFH8dAAMIAAcJfg+qCwB4AQdoDAAABgBIAGkMAAAGACEAawwAAAUALQBqDAAAAwAoAGwMAAACACQAbQwAAAIACQDqDAAABQAnAAgABwl+D6oLAHgBB2gMAAAEAEgAaQwAAAQAIQBrDAAABAAtAGoMAAADACgAbAwAAAIAJABtDAAAAgAJAOoMAAAFACcADQADCR0CT0YAhgADaAwAAAIABgBpDAAAAgAIAGsMAAABAAAAAS4ABRQJCUQADgAWIQA=.',
Fl='Floydfu:BAEALgAECgEJAgABLgAECgcJDAAEAAAAAA==.',
Gu='Guzzlord:BAEALgAECgkJEAAAAA==.',
Il='Illililili:BAEALgAECgYJDwABLgAECgkJJQAPABkRAA==.',
Jo='Joedragon:BAEBLgAECn8VAAIQAAYJZgt8WQDOAAZoDAAABAAcAGkMAAAEAC0AawwAAAUAGQBqDAAAAwASAGwMAAACABIA6gwAAAMAGwAQAAYJZgt8WQDOAAZoDAAABAAcAGkMAAAEAC0AawwAAAUAGQBqDAAAAwASAGwMAAACABIA6gwAAAMAGwABLgAFFAMJBgARAHIPAA==.',
Ka='Kabigon:BAEALgADCgcJCgABLgAECgkJEAAEAAAAAA==.',
Ki='Kifka:BAECLgAFFH8FAAIMAAIJeBKqlwCIAAJoDAAAAgBCAOoMAAADABsADAACCXgSqpcAiAACaAwAAAIAQgDqDAAAAwAbAC4ABAp/LQADDAAICRsj1xcAtAIADAAICf4h1xcAtAIAEgAHCZUfzQsACQIAAS4ABRQECRkAEwCyIAA=.',
Ma='Maniacul:BAECLgAFFH8ZAAITAAQJsiBGFQBhAQRoDAAACQBbAGkMAAAGAFYAawwAAAQARwDqDAAABgBVABMABAmyIEYVAGEBBGgMAAAJAFsAaQwAAAYAVgBrDAAABABHAOoMAAAGAFUALgAECn92AAITAAkJGiY9AQBqAwATAAkJGiY9AQBqAwAAAA==.',
Mh='Mhyre:BAEALgAECgYJEQAAAA==.',
Mo='Monkio:BAECLgAFFH8oAAIIAAkJWBucBgClAgloDAAABQBgAGkMAAAGAGMAawwAAAcAYQBqDAAABQA7AGwMAAAEAFUAbQwAAAIAOADqDAAABwA4AG4MAAABAB8AbwwAAAMAMQAIAAkJWBucBgClAgloDAAABQBgAGkMAAAGAGMAawwAAAcAYQBqDAAABQA7AGwMAAAEAFUAbQwAAAIAOADqDAAABwA4AG4MAAABAB8AbwwAAAMAMQAuAAQKfyUAAwgACQn9Hx4HAC4DAAgACQn9Hx4HAC4DABQAAglQHT5lAI0AAAAA.',
Od='Odbabymage:BAECLgAFFH85AAIVAAkJrSW7AABhAwloDAAACQBjAGkMAAAFAGEAawwAAAkAYwBqDAAACQBjAGwMAAAGAGQAbQwAAAUAYwDqDAAACQBhAG4MAAADAGAAbwwAAAIAUAAVAAkJrSW7AABhAwloDAAACQBjAGkMAAAFAGEAawwAAAkAYwBqDAAACQBjAGwMAAAGAGQAbQwAAAUAYwDqDAAACQBhAG4MAAADAGAAbwwAAAIAUAAuAAQKfyIAAxUACQnUJgQEAMADABUACQnUJgQEAMADABYAAQlRJCAaAEcAAAAA.',
Og='Og:BAEBLgAECn8bAAIXAAkJmyNeAABFAwloDAAABABXAGkMAAAEAF4AawwAAAQAXwBqDAAAAwBfAGwMAAAFAFkAbQwAAAEAUgDqDAAAAwBdAG4MAAABAFsAbwwAAAIAXgAXAAkJmyNeAABFAwloDAAABABXAGkMAAAEAF4AawwAAAQAXwBqDAAAAwBfAGwMAAAFAFkAbQwAAAEAUgDqDAAAAwBdAG4MAAABAFsAbwwAAAIAXgABLgAECgkJNwAYAOwjAA==.',
Oh='Ohb:BAEBLgAECn8lAAMPAAkJGRENFAAMAgloDAAABAAWAGkMAAAEACUAawwAAAQAPgBqDAAABAA7AGwMAAAEADwAbQwAAAYAJgDqDAAABAApAG4MAAAFAB0AbwwAAAIAKQAPAAkJGRENFAAMAgloDAAAAgAWAGkMAAACACUAawwAAAIAPgBqDAAAAgA7AGwMAAADADwAbQwAAAUAJgDqDAAAAgApAG4MAAAFAB0AbwwAAAIAKQAYAAcJ0QryUADNAAdoDAAAAgAjAGkMAAACAD0AawwAAAIALABqDAAAAgAcAGwMAAABAAIAbQwAAAEAAwDqDAAAAgASAAAA.',
Pa='Pandodruid:BAECLgAFFH8wAAMOAAkJMSKSAACbAwloDAAABQBjAGkMAAAFAGEAawwAAAQAYQBqDAAABABbAGwMAAAEAFYAbQwAAAYATgDqDAAACgBjAG4MAAAFAE4AbwwAAAUAOgAOAAkJMSKSAACbAwloDAAABQBjAGkMAAAFAGEAawwAAAMAYQBqDAAABABbAGwMAAAEAFYAbQwAAAYATgDqDAAACABjAG4MAAAFAE4AbwwAAAUAOgAXAAIJBRNlOgCPAAJrDAAAAQAMAOoMAAACAFQALgAECn8VAAMOAAgJ8SFyDwC9AgAOAAgJ8SFyDwC9AgAXAAEJNCXwbwBoAAAAAA==.',
Ph='Pharyngitis:BAECLgAFFH8eAAIFAAYJ3RGHGAAjAQZoDAAACQBKAGkMAAAIAEkAawwAAAUAJwBqDAAAAwAcAGwMAAABAA0A6gwAAAQAGwAFAAYJ3RGHGAAjAQZoDAAACQBKAGkMAAAIAEkAawwAAAUAJwBqDAAAAwAcAGwMAAABAA0A6gwAAAQAGwAuAAQKfx8AAgUABwnqGEsRAPYBAAUABwnqGEsRAPYBAAAA.',
Ra='Rayocchi:BAECLgAFFH8MAAIIAAUJ5x3PGgCeAQVoDAAAAgBTAGkMAAACAFcAawwAAAIAWABqDAAAAgA7AOoMAAAEAD8ACAAFCecdzxoAngEFaAwAAAIAUwBpDAAAAgBXAGsMAAACAFgAagwAAAIAOwDqDAAABAA/AC4ABAp/FQADCAAHCQMe+k4AMgEACAAGCXQd+k4AMgEAFAAECZsa6UoA1gAAAS4ABRQECQwACgAbIAA=.Rayocell:BAECLgAFFH8MAAIKAAQJGyB0GQBWAQRoDAAABABYAGkMAAAEAF4AawwAAAEAOQDqDAAAAwBYAAoABAkbIHQZAFYBBGgMAAAEAFgAaQwAAAQAXgBrDAAAAQA5AOoMAAADAFgALgAECn8mAAMKAAkJryR2BQAUAwAKAAkJryR2BQAUAwAMAAUJ/xknewCEAQAAAA==.Rayogizer:BAEALgAFFAMJBAABLgAFFAQJDAAKABsgAA==.',
Re='Rejuvenate:BAECLgAFFH8ZAAIOAAYJQhcEFQC/AQZoDAAACABSAGkMAAAHAEkAawwAAAIAOwBqDAAAAgAYAGwMAAABADcA6gwAAAUAPQAOAAYJQhcEFQC/AQZoDAAACABSAGkMAAAHAEkAawwAAAIAOwBqDAAAAgAYAGwMAAABADcA6gwAAAUAPQAuAAQKfyEAAw4ACAm/IS8TAJwCAA4ACAm/IS8TAJwCABcAAQl5DHeOADEAAAAA.',
Ro='Ronakada:BAEALgAECgQJCAABLgAECgQJCQAEAAAAAA==.',
Ru='Ruyari:BAEALgADCgUJBQAAAA==.',
['Rã']='Rãthord:BAEALgAECgEJAQABLgAECgkJRgADADAaAA==.',
Sa='Sahurian:BAEALgAECgcJDAAAAA==.',
Se='Seppä:BAECLgAFFH8IAAIIAAMJyQW0SwB3AANoDAAAAwATAGkMAAABAAUA6gwAAAQAEwAIAAMJyQW0SwB3AANoDAAAAwATAGkMAAABAAUA6gwAAAQAEwAuAAQKfxkAAwgACAmoEcNCAGIBAAgACAmoEcNCAGIBABQAAglXIJtTALwAAAAA.',
Sn='Snigmorder:BAECLgAFFH8mAAQGAAgJFR1AAgCXAQhoDAAACABXAGkMAAAHAFwAawwAAAYAWgBqDAAABQBjAGwMAAABAD8AbQwAAAEASgDqDAAACQBVAG4MAAABABsAEwAFCecdLAsA5wEFaAwAAAcAVwBpDAAABQBcAGsMAAAEAFoA6gwAAAYAVQBuDAAAAQAbAAYABwnJHEACAJcBB2gMAAABAEIAaQwAAAIAVgBrDAAAAQBNAGoMAAADAGMAbAwAAAEAPwBtDAAAAQBKAOoMAAADAEgAGQACCa0C3wEAWgACawwAAAEABgBqDAAAAgBSAC4ABAp/QgAEBgAJCQglmgIAqQIABgAICU8jmgIAqQIAEwAICYwlAQgApwIAGQAGCcYekwkAjwEAAAA=.',
Sp='Splashofray:BAEALgAECgEJAQABLgAFFAQJDAAKABsgAA==.',
To='Tofer:BAECLgAFFH8fAAMRAAcJGx18BADOAQdoDAAACQBiAGkMAAAIAFwAawwAAAQATABqDAAAAQA7AGwMAAABAGEAbQwAAAEAHwDqDAAABwAzABEABgmBH3wEAM4BBmgMAAAJAGIAaQwAAAcAXABrDAAABABMAGoMAAABADsAbAwAAAEAYQDqDAAABQAmABoAAwkjDNBLAFYAA2kMAAABAAoAbQwAAAEAHwDqDAAAAgAzAC4ABAp/RgAEEQAJCa4lMAEAWwMAEQAJCaslMAEAWwMAGgAICdkgMhYAhgIAGwABCTMJg44ALAAAAAA=.Toffuu:BAEBLgAECn8bAAIIAAgJtyS+BQBLAwhoDAAABABiAGkMAAAEAGMAawwAAAQAYgBqDAAABABfAGwMAAAEAGMAbQwAAAEATADqDAAAAwBhAG4MAAADAFcACAAICbckvgUASwMIaAwAAAQAYgBpDAAABABjAGsMAAAEAGIAagwAAAQAXwBsDAAABABjAG0MAAABAEwA6gwAAAMAYQBuDAAAAwBXAAEuAAUUBwkfABEAGx0A.',
Vh='Vhader:BAECLgAFFH8SAAIFAAQJfxMOIgDaAARoDAAABwA0AGkMAAAFADwAawwAAAEAGwDqDAAABQA7AAUABAl/Ew4iANoABGgMAAAHADQAaQwAAAUAPABrDAAAAQAbAOoMAAAFADsALgAECn8tAAIFAAkJcB6WBwCxAgAFAAkJcB6WBwCxAgAAAA==.',
['Wú']='Wú:BAEBLgAECn8lAAMUAAgJvxDiKgBmAQhoDAAABgAzAGkMAAAGADEAawwAAAUAIgBqDAAABQAnAGwMAAAGACsAbQwAAAIAGQDqDAAABgArAG8MAAABADQAFAAICb8Q4ioAZgEIaAwAAAUAMwBpDAAABQAxAGsMAAAEACIAagwAAAQAJwBsDAAABQArAG0MAAACABkA6gwAAAUAKwBvDAAAAQA0AA0ABgkMBJpZAKQABmgMAAABAAUAaQwAAAEABwBrDAAAAQAQAGoMAAABAAsAbAwAAAEAEgDqDAAAAQADAAAA.',
Xu='Xurkitree:BAEALgAECgEJAgABLgAECgkJEAAEAAAAAA==.',
Zo='Zogado:BAEALgAECgUJBgABLgAECgkJKAAcAAUhAA==.',
['Øg']='Øg:BAEBLgAECn82AAQLAAkJQR13GwB/AgloDAAACgBhAGkMAAAJAE4AawwAAAkAWQBqDAAABgBeAGwMAAAFAEwAbQwAAAMANADqDAAACQBcAG4MAAACAE4AbwwAAAEAIgALAAkJvht3GwB/AgloDAAACABYAGkMAAAGAEYAawwAAAcAVwBqDAAABABYAGwMAAAEAEEAbQwAAAMANADqDAAABwBcAG4MAAACAE4AbwwAAAEAIgABAAYJoSGyBwDzAQZoDAAAAgBhAGkMAAADAE4AawwAAAIAWQBqDAAAAQBeAGwMAAABAEwA6gwAAAIAWAAdAAEJAACiVAAAAAFqDAAAAQAmAAEuAAQKCQk3ABgA7CMA.',
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
