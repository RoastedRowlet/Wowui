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

local lookup = {'Paladin-Holy','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Warrior-Protection','Priest-Shadow','Priest-Discipline','Mage-Frost','Druid-Restoration','Druid-Balance','Druid-Guardian','Monk-Windwalker','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Priest-Holy','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Assassination','Rogue-Subtlety','Unknown-Unknown','Monk-Mistweaver','Hunter-Marksmanship','Rogue-Outlaw','Warrior-Arms','Warlock-Affliction','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Druid-Feral','DemonHunter-Havoc','Hunter-BeastMastery','Mage-Arcane','Mage-Fire','Shaman-Restoration',}
local provider = {region='US',realm='BleedingHollow',name='US',type='subscribers',zone=53,date='2026-10-20',data={Ad='Addex:BAEBNQAECn8kAAQBAAkK6BU6QQBgAgmODQAABwAyAHUNAAAEACIAfw0AAAQAJwCpDQAABAAyAFwNAAAEADEAXQ0AAAIASwBlDQAABgBRAKQNAAADAFEAMw0AAAIAKQABAAkK6BU6QQBgAgmODQAAAwAyAHUNAAABACIAfw0AAAEAJwCpDQAAAQAyAFwNAAABADEAXQ0AAAEASwBlDQAABABRAKQNAAADAFEAMw0AAAIAKQACAAcKAhwroADhAQeODQAAAgA8AHUNAAABAFEAfw0AAAEANACpDQAAAQBUAFwNAAABAEUAXQ0AAAEAOQBlDQAAAgBLAAMABQqFHN07ABMBBY4NAAACAFEAdQ0AAAIATAB/DQAAAgAzAKkNAAACAEcAXA0AAAIAPgABNQAFFAkJKQAEAOQjAA==.',
Am='Ambient:BAECNQAFFH8pAAIEAAkK5CPSAAANAwmODQAABwBkAHUNAAAGAFsAfw0AAAUAWwCpDQAABgBZAFwNAAAFAFYAXQ0AAAQAXgBlDQAAAQBhAKQNAAABAE4AMw0AAAYAYQAEAAkK5CPSAAANAwmODQAABwBkAHUNAAAGAFsAfw0AAAUAWwCpDQAABgBZAFwNAAAFAFYAXQ0AAAQAXgBlDQAAAQBhAKQNAAABAE4AMw0AAAYAYQA1AAQKfxwAAgQACgqtIqUNAM0CAAQACgqtIqUNAM0CAAAA.',
Av='Avarat:BAECNQAFFH8VAAIFAAYKIxrXAQCnAQaODQAABQBLAHUNAAAEAEkAfw0AAAMANACpDQAABQBVAFwNAAABACAAMw0AAAMAQwAFAAYKIxrXAQCnAQaODQAABQBLAHUNAAAEAEkAfw0AAAMANACpDQAABQBVAFwNAAABACAAMw0AAAMAQwA1AAQKfx8AAgUACgqKHCoKAKECAAUACgqKHCoKAKECAAE1AAQKCQkWAAEAOhQA.Avtrene:BAEANQADCgIJAgAAAA==.',
Ba='Banddaid:BAEBNQAECn8VAAMGAAoKPBptAwDiAQqODQAAAwAyAHUNAAACAEgAfw0AAAIAOACpDQAAAgBOAFwNAAABAEEAXQ0AAAEAUQBlDQAAAgAvAKQNAAACADAAMw0AAAUAWwC5DQAAAQBbAAYACQrjGG0DAOIBCY4NAAACADIAdQ0AAAEASAB/DQAAAQA4AKkNAAABAE4AXA0AAAEAQQBdDQAAAQBRAGUNAAABAC8ApA0AAAIAMAAzDQAAAwBbAAcABwo7FjANAGIBB44NAAABAEEAdQ0AAAEANAB/DQAAAQBOAKkNAAABADcAZQ0AAAEAIwAzDQAAAgA6ALkNAAABADQAATUABRQECBAACACWGAA=.Barkkobama:BAEBNQAECn83AAQJAAoKcCRKAwCUAwqODQAACQBiAHUNAAAGAFsAfw0AAAYAYwCpDQAABwBhAFwNAAAFAGMAXQ0AAAUAYwBlDQAABgBWAKQNAAAEAFQAMw0AAAYAVwC5DQAAAQBYAAkACgpwJEoDAJQDCo4NAAAJAGIAdQ0AAAMAWwB/DQAAAwBjAKkNAAAFAGEAXA0AAAIAYwBdDQAAAwBjAGUNAAAEAFYApA0AAAQAVAAzDQAABABXALkNAAABAFgACgAHCqgiTycAmgIHdQ0AAAIAXwB/DQAAAgBbAKkNAAACAFoAXA0AAAMAYQBdDQAAAgBbAGUNAAACAEUAMw0AAAIAWgALAAIKrSPwOwDRAAJ1DQAAAQBbAH8NAAABAF8AAAA=.',
Bo='Boimilk:BAEBNQAFFH8GAAIMAAUKOgeTCQA3AQWODQAAAQAbAHUNAAABAAwAfw0AAAEABACpDQAAAQAPADMNAAACAB8ADAAFCjoHkwkANwEFjg0AAAEAGwB1DQAAAQAMAH8NAAABAAQAqQ0AAAEADwAzDQAAAgAfAAE1AAUUCAgeAA0A/xYA.',
Br='Brapcannon:BAECNQAFFH8MAAMEAAcK9wTDDgAYAQeODQAAAwAJAHUNAAABAAcAfw0AAAEABACpDQAABAAEAFwNAAABAAIAXQ0AAAEAOQAzDQAAAQADAAQABQpBAsMOABgBBY4NAAABAAkAdQ0AAAEABwB/DQAAAQAEAKkNAAABAAQAMw0AAAEAAwAOAAQKKwiTBwARAQSODQAAAgAzAKkNAAADAAwAXA0AAAEAAwBdDQAAAQAQADUABAp/IAADDgAKCrYQbxMAGAIADgAKCrYQbxMAGAIABAAHCrYJ5SkAYAEAAAA=.Briéè:BAEANQADCgEIAQAAAA==.Bruwon:BAECNQAFFH8YAAIPAAcK0RmRAQAEAgeODQAABABTAHUNAAADAFEAfw0AAAMASQCpDQAABABbAFwNAAACACkAZQ0AAAEAIAAzDQAABwBYAA8ABwrRGZEBAAQCB44NAAAEAFMAdQ0AAAMAUQB/DQAAAwBJAKkNAAAEAFsAXA0AAAIAKQBlDQAAAQAgADMNAAAHAFgANQAECn8mAAIPAAoKzyRcAgCGAwAPAAoKzyRcAgCGAwAAAA==.',
Ch='Charzie:BAEANQAFFAEIAQABNQAFFAcIGAAPANEZAA==.',
Da='Danitsia:BAEBNQAECn8dAAQQAAcKjwXuogAsAQeODQAABgANAHUNAAAGAA4Afw0AAAUADQCpDQAABQAVAFwNAAADAAoAXQ0AAAEACAAzDQAAAwARABAABwqPBe6iACwBB44NAAAFAA0AdQ0AAAUADgB/DQAABQANAKkNAAAEABUAXA0AAAMACgBdDQAAAQAIADMNAAACABEABgACCrYDQSsATwACjg0AAAEABACpDQAAAQAOAAcAAgqSBEYJAEkAAnUNAAABAAkAMw0AAAEADQAAAA==.',
De='Deathkleburg:BAEBNQAECn86AAQRAAoKBB7jEAAIAwqODQAACABXAHUNAAAIAFsAfw0AAAgATwCpDQAABwBSAFwNAAAEAFUAXQ0AAAQARABlDQAABgBSAKQNAAAFAEgAMw0AAAcAUgC5DQAAAQAqABEACgq0HeMQAAgDCo4NAAAGAFcAdQ0AAAMAWgB/DQAAAwBPAKkNAAAFAFIAXA0AAAMAVQBdDQAAAwBEAGUNAAAEAE0ApA0AAAUASAAzDQAABABEALkNAAABACoAEgAHChYYDVAA0wEHjg0AAAIAQAB1DQAAAwBbAH8NAAADAEcAqQ0AAAIAQQBcDQAAAQAEAGUNAAACAFIAMw0AAAIAUgATAAQKjhcRegAQAQR1DQAAAgA4AH8NAAACAE4AXQ0AAAEAQAAzDQAAAQBBAAAA.Delacoûr:BAEANQAECgUICQABNQAFFAcIEQAQAIsZAA==.Deleerious:BAEBNQAECn8fAAMUAAkKVR71GgCmAgmODQAABABaAHUNAAAEAF8Afw0AAAQARwCpDQAABABWAFwNAAAEAGAAXQ0AAAMAWQBlDQAAAgAeAKQNAAACADYAMw0AAAQAXQAUAAkKVR71GgCmAgmODQAAAgBaAHUNAAACAF8Afw0AAAIARQCpDQAAAwBWAFwNAAADAGAAXQ0AAAMAWQBlDQAAAgAeAKQNAAACADYAMw0AAAIASAAVAAYKyB0+JgCVAQaODQAAAgBKAHUNAAACAFsAfw0AAAIARwCpDQAAAQBDAFwNAAABAEcAMw0AAAIAXQAAAA==.',
Do='Doorstuck:BAEANQADCggICAABNQAECgkJFgABADoUAA==.',
El='Elfylicious:BAEANQAECgYIDgABNQAECggIDAAWAAAAAA==.',
Fe='Fentweaver:BAECNQAFFH8cAAIXAAcK7R75AQAiAgeODQAABgA/AHUNAAAFAFUAfw0AAAQAUACpDQAABgBMAFwNAAACAFYAXQ0AAAEAPgAzDQAABABjABcABwrtHvkBACICB44NAAAGAD8AdQ0AAAUAVQB/DQAABABQAKkNAAAGAEwAXA0AAAIAVgBdDQAAAQA+ADMNAAAEAGMANQAECn8yAAIXAAoK3SFJBQBNAwAXAAoK3SFJBQBNAwAAAA==.',
Gi='Ginebra:BAEANQADCggIFgAAAA==.',
Gj='Gjlo:BAEANQADCggICAABNQAFFAUICgAYABQfAA==.',
Gr='Gronknose:BAECNQAFFH8gAAMZAAcKMByTAAAPAgeODQAABgBcAHUNAAAGAEcAfw0AAAYANACpDQAABQBVAFwNAAADAEUAXQ0AAAIAKgAzDQAABABVABkABgogH5MAAA8CBo4NAAAGAFwAdQ0AAAUARwB/DQAABgA0AKkNAAAFAFUAXA0AAAMARQAzDQAAAgA0ABQAAwqzFfUNABABA3UNAAABAEUAXQ0AAAIAKgAzDQAAAgBVADUABAp/MAAEGQAJCtYlJQEAiwMAGQAJCsskJQEAiwMAFAADCgYlaRAAQQEAFQABClkVRU4ASAAAAAA=.',
Ha='Hakdh:BAEANQAECgEIAQABNQAFFAcIIAADAK8QAA==.Hakdk:BAEANQAFFAEIAQABNQAFFAcIIAADAK8QAA==.Hakgek:BAEANQAECggIBAABNQAFFAcIIAADAK8QAA==.Hakmonk:BAEANQAECgIIBAABNQAFFAcIIAADAK8QAA==.Hakwar:BAEANQAECggICAABNQAFFAcIIAADAK8QAA==.',
He='Hekight:BAEANQAECggIDQABNQAECgoKJAACAIEZAA==.',
Ho='Hobo:BAEANQADCgIIBAABNQAECgkJJAAaALEiAA==.Hoboomkin:BAEANQAECgYIEQABNQAECgkJJAAaALEiAA==.Hoborc:BAEBNQAECn8kAAMaAAkKsSJiJQAjAwmODQAABgBiAHUNAAAEAGAAfw0AAAQASQCpDQAABABcAFwNAAAEAGEAXQ0AAAQAXgBlDQAABQBbAKQNAAAEAFEAuQ0AAAEAOgAaAAkKsSJiJQAjAwmODQAABQBiAHUNAAAEAGAAfw0AAAQASQCpDQAABABcAFwNAAAEAGEAXQ0AAAQAXgBlDQAABQBbAKQNAAAEAFEAuQ0AAAEAOgAFAAEKQhrbPQBLAAGODQAAAQBDAAAA.',
Ih='Ihateffxiv:BAEANQAECggIEAABNQAFFAcIDAAEAPcEAA==.',
Im='Immolater:BAEANQAECggIAQABNQAFFAcIIAADAK8QAA==.',
In='Inaríus:BAEANQAECgcIEAAAAA==.',
Jw='Jwsmashfan:BAEBNQAECn8ZAAIaAAkKIxnlXgBwAgmODQAAAgA8AHUNAAACADAAfw0AAAIASQCpDQAAAgBGAFwNAAACAD0AXQ0AAAQAPwBlDQAABgBfAKQNAAAEADEAMw0AAAEAQQAaAAkKIxnlXgBwAgmODQAAAgA8AHUNAAACADAAfw0AAAIASQCpDQAAAgBGAFwNAAACAD0AXQ0AAAQAPwBlDQAABgBfAKQNAAAEADEAMw0AAAEAQQABNQAFFAgIHgANAP8WAA==.',
Ka='Kalevias:BAECNQAFFH8gAAIDAAcKrxAWAwDeAQeODQAABwBKAHUNAAAGAA4Afw0AAAYAQACpDQAABgA+AFwNAAADABoAXQ0AAAIAIwAzDQAAAgAJAAMABwqvEBYDAN4BB44NAAAHAEoAdQ0AAAYADgB/DQAABgBAAKkNAAAGAD4AXA0AAAMAGgBdDQAAAgAjADMNAAACAAkANQAECn8qAAIDAAoKPBgtGAA3AgADAAoKPBgtGAA3AgAAAA==.',
Ki='Kirith:BAECNQAFFH8IAAIUAAUK8xHCAgDwAAWODQAAAgAvAHUNAAACACsAfw0AAAEAPwCpDQAAAgAuADMNAAABAEwAFAAFCvMRwgIA8AAFjg0AAAIALwB1DQAAAgArAH8NAAABAD8AqQ0AAAIALgAzDQAAAQBMADUABAp/HgACFAAIClcfsiMAagIAFAAIClcfsiMAagIAAAA=.',
Le='Lewinskibidi:BAECNQAFFH8eAAINAAgK/xYxAgA8AgiODQAABQBbAHUNAAAEAEUAfw0AAAMAOgCpDQAABwA9AFwNAAAEAEAAXQ0AAAMAOABlDQAAAQAJADMNAAADADIADQAICv8WMQIAPAIIjg0AAAUAWwB1DQAABABFAH8NAAADADoAqQ0AAAcAPQBcDQAABABAAF0NAAADADgAZQ0AAAEACQAzDQAAAwAyADUABAp/IgACDQAKChcinwMA8wIADQAKChcinwMA8wIAAAA=.',
Li='Lilsoup:BAECNQAFFH8KAAIQAAYKDwYpFQBaAQaODQAAAwASAHUNAAACAAwAfw0AAAEACQCpDQAAAgASAFwNAAABABAAMw0AAAEAEgAQAAYKDwYpFQBaAQaODQAAAwASAHUNAAACAAwAfw0AAAEACQCpDQAAAgASAFwNAAABABAAMw0AAAEAEgA1AAQKfxgAAhAACgoWF6scAJYBABAACgoWF6scAJYBAAAA.',
Ma='Madtheaug:BAEANQAECgcICAABNQAFFAkKMAAbAIcjAA==.Mattchstep:BAEANQAECggICAABNQAFFAgIHgANAP8WAA==.',
Mi='Minbä:BAECNQAFFH8FAAIcAAIKUBZIIQCoAAKODQAABAAwAKkNAAABAEEAHAACClAWSCEAqAACjg0AAAQAMACpDQAAAQBBADUABAp/MgACHAAJClok0AQAxQMAHAAJClok0AQAxQMAATUABRQHCBQAHQAAFAA=.Miniss:BAECNQAFFH8UAAQdAAcKABRgCQDTAQeODQAABABSAHUNAAADADMAfw0AAAMAJQCpDQAAAgBDAFwNAAACACUAXQ0AAAEAEAAzDQAABQA7AB0ABgoCFGAJANMBBo4NAAADAFIAfw0AAAMAJQCpDQAAAgBDAFwNAAACACUAXQ0AAAEAEAAzDQAABAA7AB4AAgpmEFsPAJYAAo4NAAABACAAdQ0AAAMAMwAbAAEKAAABCAAAAAEzDQAAAQAkADUABAp/RQAEGwAKCkci4wMArQIAHQAJCnAi3RsAFgMAGwAICi4i4wMArQIAHgAHCnMfPQ4AFgIAAAA=.',
Mo='Mobes:BAEBNQAECn8sAAMLAAoKIRaVEABXAgqODQAACQBMAHUNAAAGAEcAfw0AAAYAPgCpDQAABAAjAFwNAAADACoAXQ0AAAIAJwBlDQAABQA7AKQNAAADADgAMw0AAAUAUwC5DQAAAQBIAAsACgohFpUQAFcCCo4NAAAIAEwAdQ0AAAUARwB/DQAABQA+AKkNAAAEACMAXA0AAAMAKgBdDQAAAgAnAGUNAAAFADsApA0AAAIAOAAzDQAABQBTALkNAAABAEgAHwAECq4PJygAzQAEjg0AAAEAJAB1DQAAAQA5AH8NAAABABgApA0AAAEAGQAAAA==.Moosclemommy:BAEBNQAFFH8VAAIPAAYKRBkVAgDfAQaODQAABQA/AHUNAAAEAEEAfw0AAAMAQgCpDQAABQBKAFwNAAABADYAMw0AAAMASQAPAAYKRBkVAgDfAQaODQAABQA/AHUNAAAEAEEAfw0AAAMAQgCpDQAABQBKAFwNAAABADYAMw0AAAMASQABNQAECgkJFgABADoUAA==.Mowrii:BAEANQADCgYIBgABNQAFFAQIBwAgAEYOAA==.',
Ni='Niniane:BAECNQAFFH8aAAMhAAYKUR0bCQC3AQaODQAABgBLAHUNAAAFAEMAfw0AAAMAFACpDQAABwBZAFwNAAADAEIAMw0AAAIAPAAhAAUK3xwbCQC3AQWODQAAAgBLAHUNAAABAD8AqQ0AAAUAWQBcDQAAAwBCADMNAAACADwAGAAECkEWSBEAKAEEjg0AAAQAPwB1DQAABABDAH8NAAADABQAqQ0AAAIAJwA1AAQKfy4AAyEACgrwJN4PAGUDACEACgrwJN4PAGUDABgAAgqDEktpAIgAAAAA.',
No='Noradk:BAEANQAECgYIEgABNQAFFAUICwADAIIYAA==.Noralisa:BAECNQAFFH8LAAIDAAUKghgtAgDwAAWODQAABAA/AHUNAAACAC8Afw0AAAEAEwCpDQAAAwBNADMNAAABACsAAwAFCoIYLQIA8AAFjg0AAAQAPwB1DQAAAgAvAH8NAAABABMAqQ0AAAMATQAzDQAAAQArADUABAp/JwACAwAKCt4h3gkA/gIAAwAKCt4h3gkA/gIAAAA=.Noreleasa:BAEANQADCgUIBQABNQAFFAUICwADAIIYAA==.Notspidee:BAEANQADCgYIBgABNQAECgUIAgAWAAAAAA==.Novelus:BAECNQAFFH8LAAIFAAUKniMrAQDvAQWODQAAAwBaAHUNAAACAFYAfw0AAAIAWACpDQAAAwBgADMNAAABAFAABQAFCp4jKwEA7wEFjg0AAAMAWgB1DQAAAgBWAH8NAAACAFgAqQ0AAAMAYAAzDQAAAQBQADUABAp/FQADBQAJCo0jxwQANAMABQAJCo0jxwQANAMAGgACCiYMorUARwAAAAA=.',
Ol='Oldbronze:BAECNQAFFH8HAAIFAAMKrxhHAQDbAAOODQAABABMAHUNAAABADsAqQ0AAAIANAAFAAMKrxhHAQDbAAOODQAABABMAHUNAAABADsAqQ0AAAIANAA1AAQKf0UAAgUACgpXJYkAAOgDAAUACgpXJYkAAOgDAAAA.',
Pa='Parkercannon:BAEANQAECgEIAQABNQAFFAgIHgANAP8WAA==.Patrennessy:BAEANQAECgEJAQABNQAFFAcIIAAZADAcAA==.',
Ra='Ramsama:BAEANQADCggICAABNQAFFAcIDwAKAJoNAA==.Ramsw:BAECNQAFFH8aAAIaAAcKQSUsAgDaAgeODQAABgBgAHUNAAAEAGIAfw0AAAQAUgCpDQAABABhAFwNAAACAFkAXQ0AAAIAXgAzDQAABABhABoABwpBJSwCANoCB44NAAAGAGAAdQ0AAAQAYgB/DQAABABSAKkNAAAEAGEAXA0AAAIAWQBdDQAAAgBeADMNAAAEAGEANQAECn8kAAIaAAoKOyUWGABYAwAaAAoKOyUWGABYAwAAAA==.',
Re='Recursively:BAECNQAFFH8PAAQeAAcKjQ5EBADTAAeODQAAAQAKAHUNAAADABcAfw0AAAIAKwCpDQAAAwA7AF0NAAABAD4AZQ0AAAEAHgAzDQAABABCAB0AAwqzESIlANkAA38NAAACACsAqQ0AAAEAHABdDQAAAQA+AB4AAwogDEQEANMAA44NAAABAAoAdQ0AAAMAFwCpDQAAAgA7ABsAAgryC1AEAKoAAmUNAAABAB4AMw0AAAQAQgA1AAQKf0EAAx4ACgoAJKANAB8CAB0ACApsI/kiAPgCAB4ABwr0F6ANAB8CAAAA.Resika:BAECNQAFFH8PAAIKAAcKmg26BAAdAQeODQAAAgA4AHUNAAADAB4Afw0AAAEABgCpDQAAAwA+AFwNAAABABMAXQ0AAAEABAAzDQAABAAqAAoABwqaDboEAB0BB44NAAACADgAdQ0AAAMAHgB/DQAAAQAGAKkNAAADAD4AXA0AAAEAEwBdDQAAAQAEADMNAAAEACoANQAECn80AAIKAAoKxxpRFwANAwAKAAoKxxpRFwANAwAAAA==.Retaholics:BAEANQADCggIDgAAAA==.',
Ru='Ruwon:BAEANQAECgYICQABNQAFFAcIGAAPANEZAA==.Ruwondk:BAEBNQAECn8nAAITAAkKMCFSDABQAwmODQAABgBfAHUNAAAEAF8Afw0AAAUAWQCpDQAABQBeAFwNAAAEAGEAXQ0AAAMAMABlDQAAAwBRAKQNAAADAFEAMw0AAAYAXwATAAkKMCFSDABQAwmODQAABgBfAHUNAAAEAF8Afw0AAAUAWQCpDQAABQBeAFwNAAAEAGEAXQ0AAAMAMABlDQAAAwBRAKQNAAADAFEAMw0AAAYAXwABNQAFFAcIGAAPANEZAA==.',
Sa='Sascya:BAEANQAECgIIAgABNQAFFAcIIAADAK8QAA==.',
Sh='Shadythicc:BAEANQAECgQIBAABNQAECggICAAWAAAAAA==.Sharrq:BAECNQAFFH8LAAIiAAYKDxXlGwCeAQaODQAAAwA5AHUNAAACAEoAfw0AAAEAUgCpDQAAAwA0AFwNAAABAB4AMw0AAAEAIgAiAAYKDxXlGwCeAQaODQAAAwA5AHUNAAACAEoAfw0AAAEAUgCpDQAAAwA0AFwNAAABAB4AMw0AAAEAIgA1AAQKfyoABCIACgr5IH86ABIDACIACgryH386ABIDACMABwojGRcDAOEBAAgABQpMFi4YADgBAAAA.',
Si='Silversoph:BAEANQADCgQIAgAAAA==.',
Sl='Slimelight:BAEANQAECgQIBgAAAA==.',
St='Stuu:BAECNQAFFH8YAAITAAYK7CE/BAA/AgaODQAABQBbAHUNAAAEAFIAfw0AAAQASwCpDQAABQBfAFwNAAADAE0AMw0AAAMAYwATAAYK7CE/BAA/AgaODQAABQBbAHUNAAAEAFIAfw0AAAQASwCpDQAABQBfAFwNAAADAE0AMw0AAAMAYwA1AAQKfyQAAxMACgrbJZQIAHYDABMACgrbJZQIAHYDABIAAgpcB6PNAFIAAAE1AAQKBwgHABYAAAAA.Stuwy:BAEANQAECgcIBwAAAA==.',
Te='Tendiarii:BAEANQADCggIGwAAAA==.',
Th='Thanala:BAECNQAFFH8VAAIBAAYKaRiUBgAEAgaODQAABQBTAHUNAAAEAB0Afw0AAAQAQwCpDQAABAA7AFwNAAACADUAMw0AAAIAUQABAAYKaRiUBgAEAgaODQAABQBTAHUNAAAEAB0Afw0AAAQAQwCpDQAABAA7AFwNAAACADUAMw0AAAIAUQA1AAQKfxoAAgEACgq9F6ozAJYCAAEACgq9F6ozAJYCAAAA.Thejigglr:BAECNQAFFH8MAAIcAAQKUQXCFQAfAQR1DQAAAQAIAH8NAAADABMAqQ0AAAMAEgAzDQAABQAdABwABApRBcIVAB8BBHUNAAABAAgAfw0AAAMAEwCpDQAAAwASADMNAAAFAB0ANQAECn8kAAIcAAoKnhrXNwCXAgAcAAoKnhrXNwCXAgAAAA==.',
Wo='Wormdropper:BAEBNQAECn8bAAMkAAYKYhjtgQCGAQaODQAABAA2AHUNAAAEAFgAfw0AAAUASACpDQAABQAvAFwNAAAEADQAMw0AAAUAOwAkAAYKYhjtgQCGAQaODQAAAwA2AHUNAAADAFgAfw0AAAUASACpDQAABAAvAFwNAAAEADQAMw0AAAQAOwAcAAQKvASw9QCpAASODQAAAQAOAHUNAAABAAkAqQ0AAAEACwAzDQAAAQANAAAA.Wormite:BAEANQAECgYICwABNQAECgYIGwAkAGIYAA==.',
Xm='Xmal:BAEANQAECgQIBAABNQAFFAQIBwAgAEYOAA==.',
Yu='Yukirippurr:BAEBNQAECn8qAAMfAAcKmg4lIwD2AAeODQAABwAmAHUNAAAHAC0Afw0AAAcARwCpDQAACAA1AFwNAAAGAB8AXQ0AAAEAEQAzDQAABgA5AAoABwq2DRZeAFgBB44NAAAFACYAdQ0AAAcALQB/DQAABgBHAKkNAAAHACoAXA0AAAUAHwBdDQAAAQARADMNAAAFAB4AHwAFCjcOJSMA9gAFjg0AAAIAGAB/DQAAAQBDAKkNAAABADUAXA0AAAEAHwAzDQAAAQA5AAAA.',
Zu='Zuri:BAEBNQAECn8UAAIQAAgKRQSfwwDSAAiODQAABAAaAHUNAAADAB4Afw0AAAIACQCpDQAAAgAHAFwNAAACAAEAXQ0AAAIABABlDQAAAgABAKQNAAADAAYAEAAICkUEn8MA0gAIjg0AAAQAGgB1DQAAAwAeAH8NAAACAAkAqQ0AAAIABwBcDQAAAgABAF0NAAACAAQAZQ0AAAIAAQCkDQAAAwAGAAE1AAUUBwgYAA8A0RkA.',
['Çb']='Çbk:BAECNQAFFH8XAAQdAAcKCiFaAgByAgeODQAAAwBjAHUNAAAEAFsAfw0AAAMAUgCpDQAABQBRAFwNAAACAFMAXQ0AAAEAQgAzDQAABQBhAB0ABwrMHVoCAHICB44NAAADAGMAdQ0AAAEAMgB/DQAAAwBSAKkNAAADAFEAXA0AAAEAUwBdDQAAAQBCADMNAAABAFIAGwACCkUg4QIA0wACXA0AAAEAUgAzDQAABABhAB4AAgoHIQ8JAKwAAnUNAAADAFsAqQ0AAAIATQA1AAQKfzgABB0ACgrCJZgXACoDAB0ACQr4JJgXACoDABsABgrOIx8KANkBAB4ABgqAHyoUAM4BAAAA.',
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
