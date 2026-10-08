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

local lookup = {'Paladin-Holy','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Warrior-Protection','Unknown-Unknown','Mage-Frost','Druid-Restoration','Druid-Balance','Druid-Guardian','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Rogue-Assassination','Rogue-Subtlety','Monk-Mistweaver','Hunter-Marksmanship','Rogue-Outlaw','Warrior-Arms','Warlock-Affliction','Shaman-Enhancement','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Druid-Feral','DemonHunter-Havoc','Hunter-BeastMastery','Mage-Arcane','Mage-Fire','Shaman-Restoration',}
local provider = {region='US',realm='BleedingHollow',name='US',type='subscribers',zone=53,date='2026-10-06',data={Ad='Addex:BAEBNQAECoEkAAQBAAkK6BX+NwBoAgmODQAABwAyAHUNAAAEACIAfw0AAAQAJwCpDQAABAAyAFwNAAAEADEAXQ0AAAIASwBlDQAABgBRAKQNAAADAFEAMw0AAAIAKQABAAkK6BX+NwBoAgmODQAAAwAyAHUNAAABACIAfw0AAAEAJwCpDQAAAQAyAFwNAAABADEAXQ0AAAEASwBlDQAABABRAKQNAAADAFEAMw0AAAIAKQACAAcK6xpFgAD3AQeODQAAAgA8AHUNAAABAFEAfw0AAAEANACpDQAAAQBUAFwNAAABAEUAXQ0AAAEAOQBlDQAAAgBLAAMABQrYGnkyACQBBY4NAAACAFEAdQ0AAAIATAB/DQAAAgAzAKkNAAACAEcAXA0AAAIAPgABNQAFFAgIJwAEAI4kAA==.',
Am='Ambient:BAECNQAFFIEnAAIEAAgKjiRtAAAgAwiODQAABwBkAHUNAAAGAFsAfw0AAAUAWwCpDQAABgBZAFwNAAAFAFYAXQ0AAAQAXgBlDQAAAQBhADMNAAAFAGEABAAICo4kbQAAIAMIjg0AAAcAZAB1DQAABgBbAH8NAAAFAFsAqQ0AAAYAWQBcDQAABQBWAF0NAAAEAF4AZQ0AAAEAYQAzDQAABQBhADUABAqBGwACBAAJCoQiAwwA1AIABAAJCoQiAwwA1AIAAAA=.',
Av='Avarat:BAECNQAFFIEQAAIFAAUKHBl6AQCZAQWODQAABABLAHUNAAADAEkAfw0AAAIAIQCpDQAABABHADMNAAADAEMABQAFChwZegEAmQEFjg0AAAQASwB1DQAAAwBJAH8NAAACACEAqQ0AAAQARwAzDQAAAwBDADUABAqBHQACBQAJCmUcZwgAowIABQAJCmUcZwgAowIAATUABAoICBMABgAAAAA=.Avtrene:BAEANQADCgIJAgAAAA==.',
Ba='Banddaid:BAEANQAECgQIBQABNQAFFAQICwAHAHYQAA==.Barkkobama:BAEBNQAECoEwAAQIAAkKZiSYAgCYAwmODQAABwBiAHUNAAAGAFsAfw0AAAYAYwCpDQAABwBhAFwNAAAFAGMAXQ0AAAUAYwBlDQAABABWAKQNAAACAE4AMw0AAAYAVwAIAAkKZiSYAgCYAwmODQAABwBiAHUNAAADAFsAfw0AAAMAYwCpDQAABQBhAFwNAAACAGMAXQ0AAAMAYwBlDQAAAgBWAKQNAAACAE4AMw0AAAQAVwAJAAcK9CIWIQCmAgd1DQAAAgBfAH8NAAACAFsAqQ0AAAIAWgBcDQAAAwBhAF0NAAACAFsAZQ0AAAIARQAzDQAAAgBaAAoAAgpyJM0vANQAAnUNAAABAFsAfw0AAAEAXwAAAA==.',
Bo='Boimilk:BAEANQAECgIIAgABNQAFFAcIFwALAE0ZAA==.',
Br='Brapcannon:BAECNQAFFIELAAMEAAYKCQI1DAAlAQaODQAAAwAJAHUNAAABAAcAfw0AAAEABACpDQAABAAEAFwNAAABAAIAMw0AAAEAAwAEAAUKQQI1DAAlAQWODQAAAQAJAHUNAAABAAcAfw0AAAEABACpDQAAAQAEADMNAAABAAMADAADCsoI2AgAxgADjg0AAAIAMwCpDQAAAwAMAFwNAAABAAMANQAECoEeAAMMAAkKeBJgEQAgAgAMAAkKeBJgEQAgAgAEAAYK3QaILAAdAQAAAA==.Briéè:BAEANQADCgEIAQAAAA==.Bruwon:BAECNQAFFIEVAAINAAYK9B0DAQANAgaODQAABABTAHUNAAADAFEAfw0AAAMASQCpDQAABABbAFwNAAACACkAMw0AAAUAWAANAAYK9B0DAQANAgaODQAABABTAHUNAAADAFEAfw0AAAMASQCpDQAABABbAFwNAAACACkAMw0AAAUAWAA1AAQKgR8AAg0ACQqfJRgCAIIDAA0ACQqfJRgCAIIDAAAA.',
Ch='Charzie:BAEANQAFFAEIAQABNQAFFAYIFQANAPQdAA==.',
Da='Danitsia:BAEANQAECgYIEQAAAA==.',
De='Deathkleburg:BAEBNQAECoErAAQOAAkKLB6cFgCyAgmODQAABgBCAHUNAAAGAFsAfw0AAAYATgCpDQAABgBSAFwNAAADAFUAXQ0AAAMARABlDQAABABSAKQNAAADAEIAMw0AAAYASAAOAAkKShycFgCyAgmODQAABABCAHUNAAACAE8Afw0AAAIATACpDQAABABSAFwNAAACAFUAXQ0AAAIARABlDQAAAgA6AKQNAAADAEIAMw0AAAQARAAPAAcKPxllSwDAAQeODQAAAgBAAHUNAAACAFsAfw0AAAIARwCpDQAAAgBBAFwNAAABAAQAZQ0AAAIAUgAzDQAAAQBIABAABArSGZluABUBBHUNAAACADgAfw0AAAIATgBdDQAAAQBAADMNAAABAEEAAAA=.Delacoûr:BAEANQAECgQICAABNQAFFAcIEAARAIsZAA==.Deleerious:BAEBNQAECoEfAAMSAAkKvx75EwC5AgmODQAABABaAHUNAAAEAF8Afw0AAAQARwCpDQAABABWAFwNAAAEAGAAXQ0AAAMAWQBlDQAAAgAeAKQNAAACADYAMw0AAAQAXQASAAkKux35EwC5AgmODQAAAgBaAHUNAAACAF8Afw0AAAIARQCpDQAAAwBWAFwNAAADAGAAXQ0AAAMAWQBlDQAAAgAeAKQNAAACADYAMw0AAAIASAATAAYKlx5bIgCjAQaODQAAAgBKAHUNAAACAFsAfw0AAAIARwCpDQAAAQBDAFwNAAABAEcAMw0AAAIAXQAAAA==.',
Do='Doorstuck:BAEANQADCggICAABNQAECggIEwAGAAAAAA==.',
El='Elfylicious:BAEANQAECgMICAABNQAECgYICQAGAAAAAA==.',
Fe='Fentweaver:BAECNQAFFIEVAAIUAAYK+B1bAQA3AgaODQAABQA/AHUNAAAEAFUAfw0AAAMAUACpDQAABQBMAFwNAAABADYAMw0AAAMAYwAUAAYK+B1bAQA3AgaODQAABQA/AHUNAAAEAFUAfw0AAAMAUACpDQAABQBMAFwNAAABADYAMw0AAAMAYwA1AAQKgSsAAhQACQqdI/4DAFgDABQACQqdI/4DAFgDAAAA.',
Gi='Ginebra:BAEANQADCggIFgAAAA==.',
Gj='Gjlo:BAEANQADCggICAABNQAFFAMIBQAVABIfAA==.',
Gr='Gronknose:BAECNQAFFIEaAAMWAAcKZxZoAAAQAgeODQAABgBcAHUNAAAFAEcAfw0AAAUANACpDQAABQBVAFwNAAACAAQAXQ0AAAEAKgAzDQAAAgA0ABYABgplF2gAABACBo4NAAAGAFwAdQ0AAAUARwB/DQAABQA0AKkNAAAFAFUAXA0AAAIABAAzDQAAAgA0ABIAAQpxEHUVAFwAAV0NAAABACoANQAECoEqAAQWAAkKECXZAACbAwAWAAkK4iTZAACbAwASAAMK3iHZVAAZAQATAAEKWRX5RgBIAAAAAA==.',
Ha='Hakdh:BAEANQAECgEIAQABNQAFFAcIGgADAGEPAA==.Hakdk:BAEANQAECgMIBgABNQAFFAcIGgADAGEPAA==.Hakmonk:BAEANQAECgEIAQABNQAFFAcIGgADAGEPAA==.',
He='Hekight:BAEANQAECggIBwABNQAECgkJHAACAA0VAA==.',
Ho='Hobo:BAEANQADCgIIBAABNQAECggIGAAXADghAA==.Hoboomkin:BAEANQAECgYIEQABNQAECggIGAAXADghAA==.Hoborc:BAEBNQAECoEYAAIXAAgKOCHhJwAKAwiODQAABABiAHUNAAADAFgAfw0AAAMAPgCpDQAAAwBcAFwNAAADAGEAXQ0AAAMAXgBlDQAAAwBTAKQNAAACAD8AFwAICjgh4ScACgMIjg0AAAQAYgB1DQAAAwBYAH8NAAADAD4AqQ0AAAMAXABcDQAAAwBhAF0NAAADAF4AZQ0AAAMAUwCkDQAAAgA/AAAA.',
Hu='Hunterinnit:BAEANQADCgEIAQAAAA==.',
Ih='Ihateffxiv:BAEANQAECgYIBgABNQAFFAYICwAEAAkCAA==.',
Im='Immolater:BAEANQAECggIAQABNQAFFAcIGgADAGEPAA==.',
In='Inaríus:BAEANQAECgcIDwAAAA==.',
Jw='Jwsmashfan:BAEBNQAECoEZAAIXAAkKmBkhTQCIAgmODQAAAgA8AHUNAAACADAAfw0AAAIASQCpDQAAAgBGAFwNAAACAD0AXQ0AAAQAPwBlDQAABgBfAKQNAAAEADEAMw0AAAEAQQAXAAkKmBkhTQCIAgmODQAAAgA8AHUNAAACADAAfw0AAAIASQCpDQAAAgBGAFwNAAACAD0AXQ0AAAQAPwBlDQAABgBfAKQNAAAEADEAMw0AAAEAQQABNQAFFAcIFwALAE0ZAA==.',
Ka='Kalevias:BAECNQAFFIEaAAIDAAcKYQ9aAgDgAQeODQAABgBKAHUNAAAFAAYAfw0AAAUAQACpDQAABQA7AFwNAAACABgAXQ0AAAEAIwAzDQAAAgAJAAMABwphD1oCAOABB44NAAAGAEoAdQ0AAAUABgB/DQAABQBAAKkNAAAFADsAXA0AAAIAGABdDQAAAQAjADMNAAACAAkANQAECoEnAAIDAAkKqBp1EgBUAgADAAkKqBp1EgBUAgAAAA==.',
Ki='Kirith:BAEBNQAECoEZAAISAAcKcR+AHABxAgeODQAABQBUAHUNAAAEAEkAfw0AAAMAVgCpDQAABQBfAFwNAAADAFAAZQ0AAAIATwCkDQAAAwA/ABIABwpxH4AcAHECB44NAAAFAFQAdQ0AAAQASQB/DQAAAwBWAKkNAAAFAF8AXA0AAAMAUABlDQAAAgBPAKQNAAADAD8AATUABRQCCAoACQCIEwA=.',
Le='Lewinskibidi:BAECNQAFFIEXAAILAAcKTRleAQBRAgeODQAABABbAHUNAAADAEUAfw0AAAMAOgCpDQAABgA9AFwNAAADAEAAXQ0AAAIAOAAzDQAAAgAyAAsABwpNGV4BAFECB44NAAAEAFsAdQ0AAAMARQB/DQAAAwA6AKkNAAAGAD0AXA0AAAMAQABdDQAAAgA4ADMNAAACADIANQAECoEfAAILAAkK/SMWAwD2AgALAAkK/SMWAwD2AgAAAA==.',
Li='Lilsoup:BAEBNQAFFIEIAAIRAAQKlAYTFAAsAQSODQAAAwASAHUNAAACAAwAqQ0AAAIAEgAzDQAAAQASABEABAqUBhMUACwBBI4NAAADABIAdQ0AAAIADACpDQAAAgASADMNAAABABIAAAA=.',
Ma='Madtheaug:BAEANQAECgcICAABNQAFFAkKIgAYAJwjAA==.Mangofart:BAEBNQAECoExAAIZAAkKMx5xBgAPAwmODQAACQBfAHUNAAAHAFAAfw0AAAcAUACpDQAACABQAFwNAAAFAE4AXQ0AAAQASQBlDQAAAwBQAKQNAAACAD0AMw0AAAQAQQAZAAkKMx5xBgAPAwmODQAACQBfAHUNAAAHAFAAfw0AAAcAUACpDQAACABQAFwNAAAFAE4AXQ0AAAQASQBlDQAAAwBQAKQNAAACAD0AMw0AAAQAQQAAAA==.Mattchstep:BAEANQAECggICAABNQAFFAcIFwALAE0ZAA==.',
Mi='Minbä:BAEBNQAECoEtAAIaAAkKeyQABADGAwmODQAACABhAHUNAAAGAGEAfw0AAAUAYwCpDQAABQBhAFwNAAAEAGEAXQ0AAAMAXQBlDQAABQBhAKQNAAADAEAAMw0AAAYAYQAaAAkKeyQABADGAwmODQAACABhAHUNAAAGAGEAfw0AAAUAYwCpDQAABQBhAFwNAAAEAGEAXQ0AAAMAXQBlDQAABQBhAKQNAAADAEAAMw0AAAYAYQABNQAFFAcIEwAbAL0TAA==.Miniss:BAECNQAFFIETAAMbAAcKvRPcBQDmAQeODQAABABSAHUNAAADADMAfw0AAAMAJQCpDQAAAgBDAFwNAAACACUAXQ0AAAEAEAAzDQAABAA7ABsABgqzE9wFAOYBBo4NAAADAFIAfw0AAAMAJQCpDQAAAgBDAFwNAAACACUAXQ0AAAEAEAAzDQAABAA7ABwAAgpmEAAOAJoAAo4NAAABACAAdQ0AAAMAMwA1AAQKgTkABBsACQrzIswTACkDABsACQrwIswTACkDABgABwqzG2AFAEoCABwABwo3HPcMAB0CAAAA.',
Mo='Mobes:BAEBNQAECoEhAAMKAAkKghWrDwAoAgmODQAABgBMAHUNAAAFAEcAfw0AAAUAPgCpDQAABAAjAFwNAAADACoAXQ0AAAIAJwBlDQAAAwA7AKQNAAABABkAMw0AAAQAUwAKAAgK7harDwAoAgiODQAABgBMAHUNAAAFAEcAfw0AAAUAPgCpDQAABAAjAFwNAAADACoAXQ0AAAIAJwBlDQAAAwA7ADMNAAAEAFMAHQABCiIKQj4AIAABpA0AAAEAGQAAAA==.Moosclemommy:BAEBNQAFFIEVAAINAAYK9BmDAQDkAQaODQAABQA/AHUNAAAEAEEAfw0AAAMAQgCpDQAABQBKAFwNAAABADYAMw0AAAMASQANAAYK9BmDAQDkAQaODQAABQA/AHUNAAAEAEEAfw0AAAMAQgCpDQAABQBKAFwNAAABADYAMw0AAAMASQABNQAECggIEwAGAAAAAA==.Mowrii:BAEANQADCgYIBgABNQAECgkJIgAeAPEhAA==.',
Ni='Niniane:BAECNQAFFIERAAMfAAYKohV8BgC/AQaODQAABABLAHUNAAAEAD8Afw0AAAEAEwCpDQAABQBZAFwNAAABABcAMw0AAAIAPAAfAAUKcBh8BgC/AQWODQAAAQBLAHUNAAABAD8AqQ0AAAQAWQBcDQAAAQAXADMNAAACADwAFQAECrgMJQ8AHwEEjg0AAAMAOwB1DQAAAwAbAH8NAAABABMAqQ0AAAEAGAA1AAQKgScAAx8ACQr7JFALAHEDAB8ACQr7JFALAHEDABUAAgoJEbheAIMAAAAA.',
No='Noradk:BAEANQAECgYIDAABNQAFFAMIBgADACgXAA==.Noralisa:BAECNQAFFIEGAAIDAAMKKBeYBgDYAAOODQAAAwA/AKkNAAACAEcAMw0AAAEAKwADAAMKKBeYBgDYAAOODQAAAwA/AKkNAAACAEcAMw0AAAEAKwA1AAQKgSMAAgMACQr1IRgHABsDAAMACQr1IRgHABsDAAAA.Noreleasa:BAEANQADCgUIBQABNQAFFAMIBgADACgXAA==.Notspidee:BAEANQADCgYIBgABNQAECgUIAgAGAAAAAA==.Novelus:BAEBNQAFFIELAAIFAAUKnSLIAAD6AQWODQAAAwBaAHUNAAACAFYAfw0AAAIAWACpDQAAAwBgADMNAAABAFAABQAFCp0iyAAA+gEFjg0AAAMAWgB1DQAAAgBWAH8NAAACAFgAqQ0AAAMAYAAzDQAAAQBQAAAA.',
Ol='Oldbronze:BAEBNQAECoE3AAIFAAkKvCWAAADiAwmODQAACQBiAHUNAAAIAGIAfw0AAAcAYwCpDQAACABiAFwNAAAHAGEAXQ0AAAQAYQBlDQAABABeAKQNAAACAFcAMw0AAAYAYQAFAAkKvCWAAADiAwmODQAACQBiAHUNAAAIAGIAfw0AAAcAYwCpDQAACABiAFwNAAAHAGEAXQ0AAAQAYQBlDQAABABeAKQNAAACAFcAMw0AAAYAYQAAAA==.',
Pa='Parkercannon:BAEANQAECgEIAQABNQAFFAcIFwALAE0ZAA==.Patrennessy:BAEANQAECgEJAQABNQAFFAcIGgAWAGcWAA==.',
Ra='Ramsama:BAEANQADCggICAABNQAFFAUICAAJAO4PAA==.Ramsw:BAECNQAFFIEVAAIXAAcKyyPBAQDIAgeODQAABQBWAHUNAAAEAGIAfw0AAAMAUgCpDQAAAwBhAFwNAAABAFkAXQ0AAAEAWQAzDQAABABhABcABwrLI8EBAMgCB44NAAAFAFYAdQ0AAAQAYgB/DQAAAwBSAKkNAAADAGEAXA0AAAEAWQBdDQAAAQBZADMNAAAEAGEANQAECoEjAAIXAAkKfyWUEAB1AwAXAAkKfyWUEAB1AwAAAA==.',
Re='Recursively:BAECNQAFFIENAAQcAAYKSRFEAwDcAAaODQAAAQAKAHUNAAADABcAfw0AAAIAKwCpDQAAAwA7AF0NAAABAD4AMw0AAAMAQgAbAAMKdRE5GwDqAAN/DQAAAgArAKkNAAABABwAXQ0AAAEAPgAcAAMKIAxEAwDcAAOODQAAAQAKAHUNAAADABcAqQ0AAAIAOwAYAAEK7BkPCgBMAAEzDQAAAwBCADUABAqBNQADGwAJCrQlMB0A+gIAGwAHCt8lMB0A+gIAHAAHCsYXCA0AGwIAAAA=.Resika:BAECNQAFFIEIAAIJAAUK7g+OCwCDAQWODQAAAQA4AHUNAAACAB4AqQ0AAAIAPQBcDQAAAQATADMNAAACACIACQAFCu4PjgsAgwEFjg0AAAEAOAB1DQAAAgAeAKkNAAACAD0AXA0AAAEAEwAzDQAAAgAiADUABAqBMwACCQAJCjIfpRIAHgMACQAJCjIfpRIAHgMAAAA=.Retaholics:BAEANQADCggIDgAAAA==.',
Ru='Ruwon:BAEANQAECgUIBgABNQAFFAYIFQANAPQdAA==.Ruwondk:BAEBNQAECoElAAIQAAkK1yEoCQBiAwmODQAABgBfAHUNAAAEAF8Afw0AAAUAWQCpDQAABQBeAFwNAAAEAGEAXQ0AAAMAMABlDQAAAwBRAKQNAAACAFEAMw0AAAUAXwAQAAkK1yEoCQBiAwmODQAABgBfAHUNAAAEAF8Afw0AAAUAWQCpDQAABQBeAFwNAAAEAGEAXQ0AAAMAMABlDQAAAwBRAKQNAAACAFEAMw0AAAUAXwABNQAFFAYIFQANAPQdAA==.',
Sh='Shadythicc:BAEANQAECgQIBAABNQAECggICAAGAAAAAA==.Sharrq:BAECNQAFFIEJAAIgAAQKexUtIABDAQSODQAAAwA5AHUNAAACAEoAqQ0AAAMANAAzDQAAAQAiACAABAp7FS0gAEMBBI4NAAADADkAdQ0AAAIASgCpDQAAAwA0ADMNAAABACIANQAECoEmAAQgAAkKPyBiNQASAwAgAAkKNx9iNQASAwAhAAcKjhmdAgDrAQAHAAUK4BjyEwBEAQAAAA==.',
Si='Silversoph:BAEANQADCgQIAgAAAA==.',
Sl='Slimelight:BAEANQAECgQIBgAAAA==.',
St='Stuu:BAECNQAFFIESAAIQAAYKAyLGAgBNAgaODQAABABbAHUNAAADAFIAfw0AAAMASwCpDQAABABfAFwNAAACAE0AMw0AAAIAYwAQAAYKAyLGAgBNAgaODQAABABbAHUNAAADAFIAfw0AAAMASwCpDQAABABfAFwNAAACAE0AMw0AAAIAYwA1AAQKgR8AAxAACQoCJXAHAHYDABAACQoCJXAHAHYDAA8AAgpcB2K7AFIAAAE1AAQKBwgHAAYAAAAA.Stuwy:BAEANQAECgcIBwAAAA==.',
Te='Tendiarii:BAEANQADCgcIEwAAAA==.',
Th='Thanala:BAECNQAFFIELAAIBAAUK8g7NCgCNAQWODQAAAwBTAHUNAAACAAYAfw0AAAIACwCpDQAAAgAIADMNAAACAFEAAQAFCvIOzQoAjQEFjg0AAAMAUwB1DQAAAgAGAH8NAAACAAsAqQ0AAAIACAAzDQAAAgBRADUABAqBFwACAQAJCtAXxjAAhwIAAQAJCtAXxjAAhwIAAAA=.Thejigglr:BAECNQAFFIEKAAIaAAQKiQY0EQAeAQR1DQAAAQAIAH8NAAACABMAqQ0AAAMAEgAzDQAABAAUABoABAqJBjQRAB4BBHUNAAABAAgAfw0AAAIAEwCpDQAAAwASADMNAAAEABQANQAECoEhAAIaAAkKyBzgLQCiAgAaAAkKyBzgLQCiAgAAAA==.',
Wo='Wormdropper:BAEBNQAECoEbAAMiAAYKYhjqbgCPAQaODQAABAA2AHUNAAAEAFgAfw0AAAUASACpDQAABQAvAFwNAAAEADQAMw0AAAUAOwAiAAYKYhjqbgCPAQaODQAAAwA2AHUNAAADAFgAfw0AAAUASACpDQAABAAvAFwNAAAEADQAMw0AAAQAOwAaAAQK0wRy2gCqAASODQAAAQAOAHUNAAABAAkAqQ0AAAEACwAzDQAAAQANAAAA.Wormite:BAEANQAECgMIAwABNQAECgYIGwAiAGIYAA==.',
Xm='Xmal:BAEANQAECgQIBAABNQAECgkJIgAeAPEhAA==.',
Yu='Yukirippurr:BAEBNQAECoEeAAMJAAYKOhIhVQBZAQaODQAABQAmAHUNAAAFACkAfw0AAAUARwCpDQAABgAqAFwNAAAEAB0AMw0AAAUAOQAJAAYKfRAhVQBZAQaODQAABAAmAHUNAAAFACkAfw0AAAQARwCpDQAABgAqAFwNAAAEAB0AMw0AAAQAHgAdAAMK3xK+IwDAAAOODQAAAQATAH8NAAABAEMAMw0AAAEAOQAAAA==.',
Zd='Zdeath:BAEANQADCgYIBgABNQAECgkJMQAZADMeAA==.',
Ze='Zemonn:BAEANQADCggICAABNQAECgkJMQAZADMeAA==.',
Zu='Zuri:BAEANQAECggIEAABNQAFFAYIFQANAPQdAA==.',
['Çb']='Çbk:BAECNQAFFIESAAQbAAYK6SIZBwDMAQaODQAAAgBjAHUNAAAEAFsAfw0AAAMAUgCpDQAABABRAFwNAAACAFMAMw0AAAMAYQAbAAUKBB8ZBwDMAQWODQAAAgBjAHUNAAABADIAfw0AAAMAUgCpDQAAAwBRAFwNAAABAFMAGAACCjojGwIA0wACXA0AAAEAUgAzDQAAAwBhABwAAgqlHCUHALUAAnUNAAADAFsAqQ0AAAEANwA1AAQKgS4ABBsACQqmJcIVAB4DABsACAqmJcIVAB4DABgABQqkI10IAOIBABwABgp3GEgUAMQBAAAA.',
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
