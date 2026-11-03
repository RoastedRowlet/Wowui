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

local lookup = {'Evoker-Augmentation','Mage-Arcane','Mage-Frost','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Blood','Priest-Holy','Shaman-Elemental','Druid-Balance','Druid-Restoration','Druid-Guardian','Evoker-Preservation','Evoker-Devastation','Warlock-Demonology','Priest-Shadow','Unknown-Unknown','Druid-Feral','Rogue-Assassination','Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Hunter-BeastMastery','Warrior-Arms','Rogue-Outlaw','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Warrior-Protection','Paladin-Holy',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=53,date='2026-11-03',data={Ak='Akaeva:BAEANQAECgYIBgAAAA==.',
Al='Alcean:BAEBNQAECn8bAAIBAAkKyRP0CAD8AQmODQAABgA/AHUNAAAEAD8Afw0AAAIAHQCpDQAABABIAFwNAAADAC8AXQ0AAAEAMQBlDQAAAQAXAKQNAAABACEAMw0AAAUAPwABAAkKyRP0CAD8AQmODQAABgA/AHUNAAAEAD8Afw0AAAIAHQCpDQAABABIAFwNAAADAC8AXQ0AAAEAMQBlDQAAAQAXAKQNAAABACEAMw0AAAUAPwAAAA==.Algebra:BAECNQAFFH8PAAMCAAYKQBqMEAA2AQaODQAABABjAHUNAAADAEkAfw0AAAIAXACpDQAABABXAFwNAAABAAgAMw0AAAEAHgACAAYKGhqMEAA2AQaODQAABABjAHUNAAABAEgAfw0AAAIAXACpDQAABABXAFwNAAABAAgAMw0AAAEAHgADAAEKzRzMDQBVAAF1DQAAAgBJADUABAp/KwADAgAKClckHUMA/gIAAgAKCs8hHUMA/gIAAwADCuUiFiIA2gAAAAA=.',
Ar='Araakki:BAEBNQAECn8bAAMEAAYKuhPIugD1AAaODQAACAAcAHUNAAAEADAAfw0AAAMAHgCpDQAAAwA6ADMNAAAGAFcAuQ0AAAMAMwAEAAYKuhPIugD1AAaODQAAAQAcAHUNAAABADAAfw0AAAEAHgCpDQAAAgA6ADMNAAADAFcAuQ0AAAEAMwAFAAYKJRTPHgD1AAaODQAABwAsAHUNAAADAFEAfw0AAAIAQQCpDQAAAQArADMNAAADADAAuQ0AAAIAJAAAAA==.Aradell:BAEBNQAECn83AAIGAAkKqRfjMABNAgmODQAACQBSAHUNAAAIAEQAfw0AAAgARwCpDQAACABDAFwNAAAFAEkAXQ0AAAUAOgBlDQAABAA6AKQNAAABAA8AMw0AAAcAUQAGAAkKqRfjMABNAgmODQAACQBSAHUNAAAIAEQAfw0AAAgARwCpDQAACABDAFwNAAAFAEkAXQ0AAAUAOgBlDQAABAA6AKQNAAABAA8AMw0AAAcAUQAAAA==.Arceni:BAEANQAECggICAABNQAECgkJNwAGAKkXAA==.Ariizi:BAEANQAECgYIEQAAAA==.Artam:BAEANQADCggICQABNQAFFAgIKAAHALobAA==.Arteron:BAEANQADCggICAABNQAFFAcIIwAIAPYjAA==.',
Au='Augstrasza:BAEANQAECgMIAwAAAA==.Aukanawe:BAECNQAFFH8XAAIJAAcKqh3lAwB6AgeODQAABgBhAHUNAAAEADIAfw0AAAIATACpDQAABABfAFwNAAACAEMAXQ0AAAEARAAzDQAABABBAAkABwqqHeUDAHoCB44NAAAGAGEAdQ0AAAQAMgB/DQAAAgBMAKkNAAAEAF8AXA0AAAIAQwBdDQAAAQBEADMNAAAEAEEANQAECn9TAAQJAAoKyiVoBgCiAwAJAAoKyiVoBgCiAwAKAAYK8xPmSwDfAAALAAEK3iGFTABhAAAAAA==.',
Av='Averelle:BAEANQAECgcIDQAAAA==.',
Ay='Ayoade:BAECNQAFFH8rAAIMAAcKmR9HAwBhAgeODQAACABSAHUNAAAHAFwAfw0AAAcAWACpDQAACABcAFwNAAAEAD8AXQ0AAAIAMgAzDQAABwBgAAwABwqZH0cDAGECB44NAAAIAFIAdQ0AAAcAXAB/DQAABwBYAKkNAAAIAFwAXA0AAAQAPwBdDQAAAgAyADMNAAAHAGAANQAECn8+AAMMAAoK4CQyAwCGAwAMAAoK4CQyAwCGAwANAAEKAACYJwAAAAAAAA==.',
Az='Azzurel:BAEBNQAECn85AAIOAAoKqRZBTQBsAgqODQAABwAuAHUNAAAHAEUAfw0AAAYAJwCpDQAABwA1AFwNAAAHAE8AXQ0AAAYAMABlDQAABQBIAKQNAAADAEAAMw0AAAgAQwC5DQAAAQAdAA4ACgqpFkFNAGwCCo4NAAAHAC4AdQ0AAAcARQB/DQAABgAnAKkNAAAHADUAXA0AAAcATwBdDQAABgAwAGUNAAAFAEgApA0AAAMAQAAzDQAACABDALkNAAABAB0AAAA=.',
Ba='Babaghanouj:BAEBNQAECn8gAAMPAAcKdBTFLgCuAQeODQAABgBBAHUNAAAEACsAfw0AAAQAKACpDQAABQA3AFwNAAAFADgAXQ0AAAMAKAAzDQAABQAuAA8ABwp0FMUuAK4BB44NAAAFAEEAdQ0AAAQAKwB/DQAABAAoAKkNAAAFADcAXA0AAAIAOABdDQAAAgAoADMNAAADAC4ABwAEClogOKIALwEEjg0AAAEASQBcDQAAAwBUAF0NAAABAFsAMw0AAAIAUQAAAA==.Babycino:BAEANQAECgMIBgABNQAECgcIDQAQAAAAAA==.Bayati:BAEBNQAECn9RAAIRAAoKUSVJAQBRAwqODQAADABhAHUNAAALAGAAfw0AAAsAYgCpDQAADABiAFwNAAAIAFwAXQ0AAAMAXQBlDQAABwBhAKQNAAAEAF0AMw0AAAgAXwC5DQAABQBeABEACgpRJUkBAFEDCo4NAAAMAGEAdQ0AAAsAYAB/DQAACwBiAKkNAAAMAGIAXA0AAAgAXABdDQAAAwBdAGUNAAAHAGEApA0AAAQAXQAzDQAACABfALkNAAAFAF4AAAA=.',
Be='Benghi:BAECNQAFFH8QAAMSAAYKhg7xDwDsAAaODQAABQArAHUNAAADACYAfw0AAAIANACpDQAAAQAbAFwNAAABACYAMw0AAAQAPAATAAUKzw+GCgAvAQWODQAABQArAHUNAAACACYAfw0AAAIANABcDQAAAQAmADMNAAADABgAEgADCvIK8Q8A7AADdQ0AAAEAHACpDQAAAQAbADMNAAABADwANQAECn8sAAMSAAoKGx8rNQAFAgASAAcKxhwrNQAFAgATAAcKJBk8JgCVAQAAAA==.Bestcase:BAECNQAFFH8UAAMUAAcK2BI2BAAJAgeODQAABQBIAHUNAAAEABIAfw0AAAMABQCpDQAABAA+AFwNAAABAE4AXQ0AAAEACAAzDQAAAgAqABQABwrYEjYEAAkCB44NAAAFAEgAdQ0AAAQAEgB/DQAAAwAFAKkNAAAEAD4AXA0AAAEATgBdDQAAAQAIADMNAAABACoAFQABCgAAwggAAAABMw0AAAEAEwA1AAQKfz8ABBQACgrEI3MMABEDABQACgrEI3MMABEDABUACArYEVgKAGcBABYAAQo9AwdWAB0AAAAA.',
Br='Brigbala:BAEANQAECgUICgAAAA==.',
Bu='Burnassus:BAEANQAECgQIBAABNQAECgoKGgAOAHILAA==.',
Ch='Chunghús:BAEANQAECgQICAABNQAFFAEIAQAQAAAAAA==.',
Co='Coggettle:BAEBNQAECn8YAAIXAAkKVhzIMABRAgmODQAAAwBSAHUNAAADAE4Afw0AAAMAGwCpDQAAAwBIAFwNAAADAEkAXQ0AAAMAQQBlDQAAAgBHADMNAAADAEQAuQ0AAAEAPwAXAAkKVhzIMABRAgmODQAAAwBSAHUNAAADAE4Afw0AAAMAGwCpDQAAAwBIAFwNAAADAEkAXQ0AAAMAQQBlDQAAAgBHADMNAAADAEQAuQ0AAAEAPwAAAA==.',
Cr='Crustage:BAEBNQAECn8iAAICAAoKpgV4hABxAQqODQAABwALAHUNAAAGABYAfw0AAAQAHACpDQAABAASAFwNAAAEABEAXQ0AAAMADwBlDQAAAgANAKQNAAACAAkAMw0AAAEAFgC5DQAAAQAHAAIACgqmBXiEAHEBCo4NAAAHAAsAdQ0AAAYAFgB/DQAABAAcAKkNAAAEABIAXA0AAAQAEQBdDQAAAwAPAGUNAAACAA0ApA0AAAIACQAzDQAAAQAWALkNAAABAAcAAAA=.',
Dc='Dcae:BAEANQADCgEIAQABNQAECgkJIwACAN0hAA==.',
Du='Dubsii:BAEANQAECgIIAgABNQAFFAcIKwAMAJkfAA==.Dubsy:BAEBNQAECn8/AAIEAAoKxSXKAgC7AwqODQAABgBbAHUNAAAHAGEAfw0AAAUAYgCpDQAABwBiAFwNAAAFAGIAXQ0AAAgAYgBlDQAACABjAKQNAAAJAGEAMw0AAAQAXQC5DQAABABfAAQACgrFJcoCALsDCo4NAAAGAFsAdQ0AAAcAYQB/DQAABQBiAKkNAAAHAGIAXA0AAAUAYgBdDQAACABiAGUNAAAIAGMApA0AAAkAYQAzDQAABABdALkNAAAEAF8AATUABRQHCCsADACZHwA=.Dumblefrost:BAEBNQAECn8nAAMCAAkKhgZvpQAuAQmODQAABwAMAHUNAAAFABYAfw0AAAUABwCpDQAABgAaAFwNAAAFAAsAXQ0AAAQADQBlDQAABAASAKQNAAABAAwAMw0AAAIABQACAAkKEQZvpQAuAQmODQAABQAEAHUNAAAFABYAfw0AAAUABwCpDQAABgAaAFwNAAAFAAsAXQ0AAAQADQBlDQAABAASAKQNAAABAAwAMw0AAAIABQADAAEKCwW6OAAtAAGODQAAAgAMAAAA.',
Eh='Ehanee:BAEBNQAECn8lAAIIAAkKQyHZEQBhAwmODQAABwBdAHUNAAAGAGAAfw0AAAUAYQCpDQAABgBWAFwNAAAEAGAAXQ0AAAIASgBlDQAAAwBQAKQNAAABAEMAMw0AAAMAWwAIAAkKQyHZEQBhAwmODQAABwBdAHUNAAAGAGAAfw0AAAUAYQCpDQAABgBWAFwNAAAEAGAAXQ0AAAIASgBlDQAAAwBQAKQNAAABAEMAMw0AAAMAWwAAAA==.',
Fa='Fappimeal:BAEANQAECgUICQAAAA==.Fappisham:BAEBNQAECn8hAAIIAAkK6h4VHwARAwmODQAABgBcAHUNAAADAE0Afw0AAAMAVACpDQAABQBVAFwNAAADAF8AXQ0AAAIASwBlDQAABABDAKQNAAADADsAMw0AAAQATQAIAAkK6h4VHwARAwmODQAABgBcAHUNAAADAE0Afw0AAAMAVACpDQAABQBVAFwNAAADAF8AXQ0AAAIASwBlDQAABABDAKQNAAADADsAMw0AAAQATQABNQAECgUICQAQAAAAAA==.',
Fs='Fshi:BAECNQAFFH8MAAMRAAcKsBOrAAAHAgeODQAAAQBEAHUNAAACACgAfw0AAAEAEgCpDQAAAQBSAFwNAAABACMAZQ0AAAEAGQAzDQAABQA5ABEABgooFqsAAAcCBo4NAAABAEQAdQ0AAAIAKAB/DQAAAQASAKkNAAABAFIAXA0AAAEAIwAzDQAAAgAvAAkAAgrQCZYcAEwAAmUNAAABABkAMw0AAAMAOQA1AAQKf1EAAxEACgq/JXUAAPUDABEACgokI3UAAPUDAAkACAp6HtJCAOoBAAAA.',
Fu='Funkey:BAEANQAECggICgAAAA==.',
Gr='Greatanubis:BAEBNQAECn8VAAMJAAkKXw32OwAVAgmODQAAAgA6AHUNAAADADwAfw0AAAMANQCpDQAAAwAuAFwNAAACAAUAXQ0AAAIAGgBlDQAABAAXAKQNAAABABIAMw0AAAEAUgAJAAkKXw32OwAVAgmODQAAAgA6AHUNAAADADwAfw0AAAMANQCpDQAAAwAuAFwNAAABAAUAXQ0AAAIAGgBlDQAABAAXAKQNAAABABIAMw0AAAEAUgAKAAEKvgELhAAZAAFcDQAAAQAEAAAA.Grumli:BAECNQAFFH8NAAIEAAYKKhjMCADFAQaODQAABABJAHUNAAACAF0Afw0AAAIARACpDQAAAwBhAFwNAAABAAsAMw0AAAEAGwAEAAYKKhjMCADFAQaODQAABABJAHUNAAACAF0Afw0AAAIARACpDQAAAwBhAFwNAAABAAsAMw0AAAEAGwA1AAQKfzMAAwQACgqcG7crALQCAAQACgqcG7crALQCAAgACArXFZhJAHUBAAE1AAMKBQgFABAAAAAA.Grummel:BAEANQADCgUIBQAAAA==.',
Ha='Halts:BAEANQAECgUIDAABNQAFFAUICAAEADkNAA==.',
Im='Imei:BAEANQAECgEIAQABNQAFFAcIGgAYAAQgAA==.',
Ja='Jail:BAEBNQAECn8jAAICAAkK3SFnHQBiAwmODQAABwBXAHUNAAAEAGMAfw0AAAMAYgCpDQAABABgAFwNAAADAFcAXQ0AAAMAXABlDQAABABMAKQNAAADAEMAMw0AAAQAXwACAAkK3SFnHQBiAwmODQAABwBXAHUNAAAEAGMAfw0AAAMAYgCpDQAABABgAFwNAAADAFcAXQ0AAAMAXABlDQAABABMAKQNAAADAEMAMw0AAAQAXwAAAA==.Jarco:BAEANQAECgQIBAABNQAFFAYIDQAZABwaAA==.',
Je='Jesyrosa:BAEANQAECgUIBQABNQAECgoKNgAMAOMaAA==.',
Ka='Kanavi:BAECNQAFFH8aAAIYAAcKBCCEDADpAQeODQAABwBhAHUNAAAEAGAAfw0AAAIARgCpDQAABQBGAFwNAAABAFkAXQ0AAAEAOAAzDQAABgBbABgABwoEIIQMAOkBB44NAAAHAGEAdQ0AAAQAYAB/DQAAAgBGAKkNAAAFAEYAXA0AAAEAWQBdDQAAAQA4ADMNAAAGAFsANQAECn88AAIYAAoKvCUECABFAwAYAAoKvCUECABFAwAAAA==.Kantai:BAEANQADCgYICQABNQAFFAcIGgAYAAQgAA==.',
Kn='Knackered:BAEBNQAECn8iAAIaAAgKYhsNGQCCAQiODQAABgBLAHUNAAAFAEQAfw0AAAUAUACpDQAABQA6AFwNAAAEAEgAXQ0AAAMAUgBlDQAAAQA/ADMNAAAFAEoAGgAICmIbDRkAggEIjg0AAAYASwB1DQAABQBEAH8NAAAFAFAAqQ0AAAUAOgBcDQAABABIAF0NAAADAFIAZQ0AAAEAPwAzDQAABQBKAAE1AAEKAggCABAAAAAA.',
Ko='Korikora:BAEANQADCgUICAABNQAECgYIGwAEALoTAA==.',
Kr='Kregazi:BAEBNQAECn8xAAIGAAoKaCHhEQAdAwqODQAACABRAHUNAAAGAF0Afw0AAAUATACpDQAABgBUAFwNAAAEAFUAXQ0AAAQAWwBlDQAABgBHAKQNAAACAF4AMw0AAAcAWgC5DQAAAQBQAAYACgpoIeERAB0DCo4NAAAIAFEAdQ0AAAYAXQB/DQAABQBMAKkNAAAGAFQAXA0AAAQAVQBdDQAABABbAGUNAAAGAEcApA0AAAIAXgAzDQAABwBaALkNAAABAFAAAAA=.',
Ku='Kujali:BAEANQAECggIBQABNQAECgoKUQARAFElAA==.Kuroi:BAEANQAECgcIBwABNQAFFAcIGgAYAAQgAA==.',
Ky='Kyssarra:BAECNQAFFH8jAAQbAAkKBh88AAB8AQmODQAABgBjAHUNAAAFAFgAfw0AAAUAVwCpDQAABQBjAFwNAAAFAE4AXQ0AAAEATABlDQAAAQAZAKQNAAABAFgAMw0AAAYAXgAbAAYKbiE8AAB8AQaODQAAAQBVAHUNAAAFAFgAfw0AAAEAVwCpDQAABQBjAFwNAAABAE4AXQ0AAAEATAAOAAUKtSKSGgAhAQWODQAABQBjAH8NAAAEAFIAXA0AAAMATgCkDQAAAQBYADMNAAABAF4AHAADCnwPOAMAxwADXA0AAAEANQBlDQAAAQAZADMNAAAFAF4ANQAECn+SAAQbAAoKviYXAAALBAAbAAkKxCYXAAALBAAOAAkKHCYECgACAwAcAAUKgiZUCAALAgAAAA==.',
Le='Lexielulu:BAEANQABCgIIBAABNQAECgUICgAQAAAAAA==.',
Lo='Lobotomight:BAEANQAECgcIDQABNQAECggICgAQAAAAAA==.',
Lu='Lunaë:BAECNQAFFH8KAAMPAAUKlAZyCgDCAAWODQAAAgAZAHUNAAACAAYAfw0AAAIAEACpDQAAAgASADMNAAACACwADwAECpQGcgoAwgAEjg0AAAEAGQB1DQAAAgAGAH8NAAACABAAqQ0AAAIAEgAHAAIK6REtJACKAAKODQAAAQA3ADMNAAACACQANQAECn9TAAMHAAoKax++DgA/AwAHAAoKax++DgA/AwAPAAUKjAsRKAAHAQAAAA==.Lunäe:BAEBNQAECn81AAIHAAoKkB62GADkAgqODQAACgBWAHUNAAAHAFEAfw0AAAoAVQCpDQAABQBBAFwNAAAEAFMAXQ0AAAUAPQBlDQAABQBGAKQNAAADAD8AMw0AAAMAYAC5DQAAAQBYAAcACgqQHrYYAOQCCo4NAAAKAFYAdQ0AAAcAUQB/DQAACgBVAKkNAAAFAEEAXA0AAAQAUwBdDQAABQA9AGUNAAAFAEYApA0AAAMAPwAzDQAAAwBgALkNAAABAFgAATUABRQFCAoADwCUBgA=.',
['Lü']='Lünae:BAEANQAECggIDAABNQAFFAUICgAPAJQGAA==.',
Ma='Maildaddy:BAEANQAFFAEIAQAAAA==.Maxxy:BAEANQAECgcIDwAAAA==.',
Mc='Mckellen:BAEANQAECgcIEwABNQAFFAcIKwAMAJkfAA==.',
Me='Merarite:BAEBNQAECn9CAAIGAAoKGhbWLgBYAgqODQAACgA8AHUNAAAIAEsAfw0AAAgANACpDQAACABCAFwNAAAHAEYAXQ0AAAcAJQBlDQAABwBJAKQNAAAEACkAMw0AAAQAPQC5DQAAAwAcAAYACgoaFtYuAFgCCo4NAAAKADwAdQ0AAAgASwB/DQAACAA0AKkNAAAIAEIAXA0AAAcARgBdDQAABwAlAGUNAAAHAEkApA0AAAQAKQAzDQAABAA9ALkNAAADABwAAAA=.',
Mo='Monkguyy:BAEANQAECgYIBwABNQAECgkJJwACAIYGAA==.',
['Mý']='Mýthra:BAEANQAECggIEAAAAA==.',
Na='Nadasa:BAECNQAFFH8GAAIdAAIKWxx5GACjAAKODQAABQBIAKkNAAABAEgAHQACClsceRgAowACjg0AAAUASACpDQAAAQBIADUABAp/jAACHQAKCmgknAwALAMAHQAKCmgknAwALAMAAAA=.',
Ni='Nixaanu:BAEANQADCgYICQAAAA==.',
No='Nomadicbear:BAEANQABCgQICAABNQABCgYICAAQAAAAAA==.Nomadichunt:BAEANQABCgYICAAAAA==.Nomadicmonk:BAEANQABCgUIBwABNQABCgYICAAQAAAAAA==.',
Ny='Nyriaa:BAEANQADCggICAAAAA==.',
Pa='Painsmith:BAEANQAECgEIAQABNQAECgoKGgAOAHILAA==.Palashin:BAEANQAECgQIBQABNQAFFAUICAAEADkNAA==.',
Pe='Personnelkid:BAEANQADCggICAABNQAECgoKGgAOAHILAA==.',
Ph='Phiirshark:BAEBNQAECn83AAIeAAoKwiNOBQAiAwqODQAACQBdAHUNAAAGAFkAfw0AAAYAXgCpDQAABwBeAFwNAAAFAFsAXQ0AAAQAVgBlDQAABgBcAKQNAAADAGAAMw0AAAYAXwC5DQAAAwBXAB4ACgrCI04FACIDCo4NAAAJAF0AdQ0AAAYAWQB/DQAABgBeAKkNAAAHAF4AXA0AAAUAWwBdDQAABABWAGUNAAAGAFwApA0AAAMAYAAzDQAABgBfALkNAAADAFcAAAA=.',
Po='Poortal:BAEANQAECgEIAQABNQAECggICgAQAAAAAA==.Potatogogue:BAECNQAFFH8NAAMIAAYK3RHJFAArAQaODQAABAAuAHUNAAACAA4Afw0AAAEAMgCpDQAAAwAfAFwNAAACAFoAMw0AAAEAGAAIAAQKFAzJFAArAQSODQAABAAuAHUNAAACAA4AqQ0AAAMAHwAzDQAAAQAYAAQAAgpaFEQeAKEAAn8NAAABAEsAXA0AAAIAHAA1AAQKfy4AAwgACgpwI4glAO4CAAgACgpwI4glAO4CAAQAAgpQH0bxAIgAAAE1AAUUAQgBABAAAAAA.Potatoroguee:BAEANQAECgYIBwABNQAFFAEIAQAQAAAAAA==.',
Pu='Punchweagle:BAEANQAECgMIAwABNQAECgoKQgAGABoWAA==.',
Ro='Roogies:BAECNQAFFH8QAAMSAAUKoR3HBgCuAQWODQAABgBhAHUNAAADAGEAfw0AAAIAUACpDQAABABfAFwNAAABAA0AEgAECsMlxwYArgEEjg0AAAYAYQB1DQAAAwBhAH8NAAABAFAAqQ0AAAQAXwATAAIKOgU+HwBQAAJ/DQAAAQAeAFwNAAABAA0ANQAECn9PAAMSAAoKmSScAwCeAwASAAoKZSScAwCeAwATAAUKbR6MUAByAQAAAA==.',
Se='Senzarial:BAEANQAECgIIAQABNQAFFAcIFwAJAKodAA==.',
Sh='Shinseer:BAECNQAFFH8IAAIEAAUKOQ0lDwBdAQWODQAAAQAvAHUNAAABAAsAfw0AAAIAIACpDQAAAQA5ADMNAAADABQABAAFCjkNJQ8AXQEFjg0AAAEALwB1DQAAAQALAH8NAAACACAAqQ0AAAEAOQAzDQAAAwAUADUABAp/LgACBAAJCmEfxRIAMwMABAAJCmEfxRIAMwMAAAA=.Shinthyr:BAEBNQAECn8hAAIHAAgKUBeNRQBWAgiODQAACwBfAHUNAAAEAEQAfw0AAAQASwCpDQAABQBTAFwNAAABACcAZQ0AAAEACQCkDQAAAgANADMNAAAFAF0ABwAIClAXjUUAVgIIjg0AAAsAXwB1DQAABABEAH8NAAAEAEsAqQ0AAAUAUwBcDQAAAQAnAGUNAAABAAkApA0AAAIADQAzDQAABQBdAAE1AAUUBQgIAAQAOQ0A.',
St='Starryangel:BAEANQAECgEIAQABNQAFFAcIHQAdACoSAA==.Stormbroken:BAEANQADCgUIBgABNQAECgoKGgAOAHILAA==.',
Su='Sunwelljuice:BAEANQADCggIHwABNQAECgoKGgAOAHILAA==.',
Sy='Syldrasi:BAEANQADCgQICAABNQAFFAUIEAASAKEdAA==.',
Ta='Tahune:BAEBNQAECn9PAAQKAAoK4SNUAgDVAwqODQAACwBZAHUNAAAKAGIAfw0AAAkAUgCpDQAACgBcAFwNAAAJAFEAXQ0AAAgAYgBlDQAABwBiAKQNAAAEAGAAMw0AAAgAVgC5DQAAAwBcAAoACgrhI1QCANUDCo4NAAAJAFkAdQ0AAAgAYgB/DQAABwBSAKkNAAAIAFwAXA0AAAcAUQBdDQAABwBiAGUNAAAHAGIApA0AAAMAYAAzDQAABwBWALkNAAACAFwACQAHCrgdf0MA5gEHjg0AAAEAUQB1DQAAAQBNAH8NAAABAC8AqQ0AAAEAPABcDQAAAQBPAKQNAAABAFEAMw0AAAEATAALAAcKCBjaFgCcAQeODQAAAQA8AHUNAAABADgAfw0AAAEAOwCpDQAAAQBBAFwNAAABAEIAXQ0AAAEAMgC5DQAAAQBGAAAA.Talaandea:BAEANQADCggIEwAAAA==.',
Th='Thawd:BAECNQAFFH8fAAIVAAcKMBccAQA2AgeODQAABgBZAHUNAAAFAEYAfw0AAAUAPACpDQAABgAwAFwNAAAEACoAXQ0AAAIALQAzDQAAAwA8ABUABwowFxwBADYCB44NAAAGAFkAdQ0AAAUARgB/DQAABQA8AKkNAAAGADAAXA0AAAQAKgBdDQAAAgAtADMNAAADADwANQAECn83AAMVAAoK3x5uBABJAgAVAAoK3x5uBABJAgAUAAkKPRBiFQDdAQAAAA==.Therapygap:BAEANQAECgUIDgABNQAECgoKGgAOAHILAA==.',
Tr='Trèantdaddy:BAEANQAECgYIBgABNQAFFAEIAQAQAAAAAA==.',
Vc='Vcoren:BAEBNQAECn8iAAIfAAoKXiPJAwC2AwqODQAAAwBaAHUNAAAFAFwAfw0AAAUAXwCpDQAABQBeAFwNAAAFAF8AXQ0AAAQAXwBlDQAAAgBgAKQNAAACAFMAMw0AAAIAYgC5DQAAAQA9AB8ACgpeI8kDALYDCo4NAAADAFoAdQ0AAAUAXAB/DQAABQBfAKkNAAAFAF4AXA0AAAUAXwBdDQAABABfAGUNAAACAGAApA0AAAIAUwAzDQAAAgBiALkNAAABAD0AATUABRQHCCsADACZHwA=.',
Ve='Velleiroth:BAEANQAECggICwABNQAFFAcIFwAJAKodAA==.',
Wh='Whimsiloxi:BAEANQAECgQICQABNQAFFAcIFwAJAKodAA==.',
Za='Zatum:BAEBNQAECn8fAAQLAAgKEx9kEQDkAQiODQAABgBSAHUNAAAFAFcAfw0AAAQAYwCpDQAABABJAFwNAAAEAFoAXQ0AAAEARgAzDQAABgBVALkNAAABAEgACwAIChMfZBEA5AEIjg0AAAQAUgB1DQAABABXAH8NAAAEAGMAqQ0AAAQASQBcDQAABABaAF0NAAABAEYAMw0AAAQAVQC5DQAAAQBIAAkAAgpjGu+UAIQAAo4NAAABAEMAMw0AAAIANAAKAAIKRhKFZgBrAAKODQAAAQAtAHUNAAABAC8AAAA=.',
Zo='Zomb:BAEANQAECgYIBgAAAA==.',
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
