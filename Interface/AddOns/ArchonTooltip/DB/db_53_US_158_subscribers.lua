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

local lookup = {'Evoker-Augmentation','Mage-Arcane','Mage-Frost','Mage-Fire','Shaman-Enhancement','Shaman-Restoration','DeathKnight-Blood','Priest-Holy','Shaman-Elemental','Druid-Balance','Druid-Restoration','Druid-Guardian','Evoker-Preservation','Evoker-Devastation','Warlock-Demonology','Priest-Shadow','Unknown-Unknown','Druid-Feral','Rogue-Assassination','Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Hunter-BeastMastery','Warrior-Arms','Rogue-Outlaw','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Warrior-Protection','Paladin-Holy',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=53,date='2026-11-17',data={Ak='Akaeva:BAEANQAECgYIBgAAAA==.',
Al='Alcean:BAEBNQAECn8bAAIBAAkKyRP0CAD8AQmODQAABgA/AHUNAAAEAD8Afw0AAAIAHQCpDQAABABIAFwNAAADAC8AXQ0AAAEAMQBlDQAAAQAXAKQNAAABACEAMw0AAAUAPwABAAkKyRP0CAD8AQmODQAABgA/AHUNAAAEAD8Afw0AAAIAHQCpDQAABABIAFwNAAADAC8AXQ0AAAEAMQBlDQAAAQAXAKQNAAABACEAMw0AAAUAPwAAAA==.Algebra:BAECNQAFFH8QAAMCAAcKQBsCGgAkAQeODQAABABjAHUNAAADAEkAfw0AAAIAXACpDQAABABXAFwNAAABAAgAXQ0AAAEATwAzDQAAAQAeAAIABgoaGgIaACQBBo4NAAAEAGMAdQ0AAAEASAB/DQAAAgBcAKkNAAAEAFcAXA0AAAEACAAzDQAAAQAeAAMAAgoHHsQMAF0AAnUNAAACAEkAXQ0AAAEATwA1AAQKfzAABAIACgpXJB1DAP4CAAIACgrPIR1DAP4CAAQABApDJOUCALMBAAMAAwrlIhYiANoAAAAA.',
Ar='Araakki:BAEBNQAECn8eAAMFAAcKehK3HgA2AQeODQAACAAsAHUNAAAEAFEAfw0AAAMAQQCpDQAAAwArAFwNAAABAB4AMw0AAAYAMAC5DQAABQAkAAUABwp6ErceADYBB44NAAAHACwAdQ0AAAMAUQB/DQAAAgBBAKkNAAABACsAXA0AAAEAHgAzDQAAAwAwALkNAAACACQABgAGChcUyLoA9QAGjg0AAAEAHAB1DQAAAQAwAH8NAAABAB4AqQ0AAAIAOgAzDQAAAwBXALkNAAADADgAAAA=.Aradell:BAEBNQAECn83AAIHAAkKqRfjMABNAgmODQAACQBSAHUNAAAIAEQAfw0AAAgARwCpDQAACABDAFwNAAAFAEkAXQ0AAAUAOgBlDQAABAA6AKQNAAABAA8AMw0AAAcAUQAHAAkKqRfjMABNAgmODQAACQBSAHUNAAAIAEQAfw0AAAgARwCpDQAACABDAFwNAAAFAEkAXQ0AAAUAOgBlDQAABAA6AKQNAAABAA8AMw0AAAcAUQAAAA==.Arceni:BAEANQAECggICAABNQAECgkJNwAHAKkXAA==.Ariizi:BAEANQAECgcIEwAAAA==.Artam:BAEANQADCggICQABNQAFFAkJKQAIAJoaAA==.Arteron:BAEANQADCggICAABNQAFFAgIJQAJAF0jAA==.',
Au='Augstrasza:BAEANQAECgMIAwAAAA==.Aukanawe:BAECNQAFFH8YAAIKAAgKyR3lAwB6AgiODQAABgBhAHUNAAAEADIAfw0AAAIATACpDQAABABfAFwNAAACAEMAXQ0AAAEARABlDQAAAQBNADMNAAAEAEEACgAICskd5QMAegIIjg0AAAYAYQB1DQAABAAyAH8NAAACAEwAqQ0AAAQAXwBcDQAAAgBDAF0NAAABAEQAZQ0AAAEATQAzDQAABABBADUABAp/UwAECgAKCsolaAYAogMACgAKCsolaAYAogMACwAGCvMT5ksA3wAADAABCt4hIloAYAAAAAA=.',
Av='Averelle:BAEANQAECgcIDQAAAA==.',
Ay='Ayoade:BAECNQAFFH8uAAINAAgKAh5HAwBhAgiODQAACABSAHUNAAAIAFwAfw0AAAgAWACpDQAACABcAFwNAAAEAD8AXQ0AAAIAMgBlDQAAAQAwADMNAAAHAGAADQAICgIeRwMAYQIIjg0AAAgAUgB1DQAACABcAH8NAAAIAFgAqQ0AAAgAXABcDQAABAA/AF0NAAACADIAZQ0AAAEAMAAzDQAABwBgADUABAp/PgADDQAKCuAkMgMAhgMADQAKCuAkMgMAhgMADgABCgAAtiwAAAAAAAA=.',
Az='Azzurel:BAEBNQAECn86AAIPAAoKxRdBTQBsAgqODQAABwAuAHUNAAAHAEUAfw0AAAYAJwCpDQAABwA1AFwNAAAHAE8AXQ0AAAYAMABlDQAABQBIAKQNAAADAEAAMw0AAAgAQwC5DQAAAgAzAA8ACgrFF0FNAGwCCo4NAAAHAC4AdQ0AAAcARQB/DQAABgAnAKkNAAAHADUAXA0AAAcATwBdDQAABgAwAGUNAAAFAEgApA0AAAMAQAAzDQAACABDALkNAAACADMAAAA=.',
Ba='Babaghanouj:BAEBNQAECn8gAAMQAAcKdBTFLgCuAQeODQAABgBBAHUNAAAEACsAfw0AAAQAKACpDQAABQA3AFwNAAAFADgAXQ0AAAMAKAAzDQAABQAuABAABwp0FMUuAK4BB44NAAAFAEEAdQ0AAAQAKwB/DQAABAAoAKkNAAAFADcAXA0AAAIAOABdDQAAAgAoADMNAAADAC4ACAAEClogOKIALwEEjg0AAAEASQBcDQAAAwBUAF0NAAABAFsAMw0AAAIAUQAAAA==.Babycino:BAEANQAECgMIBgABNQAECgcIDQARAAAAAA==.Bayati:BAEBNQAECn9RAAISAAoKUSX5AQBGAwqODQAADABhAHUNAAALAGAAfw0AAAsAYgCpDQAADABiAFwNAAAIAFwAXQ0AAAMAXQBlDQAABwBhAKQNAAAEAF0AMw0AAAgAXwC5DQAABQBeABIACgpRJfkBAEYDCo4NAAAMAGEAdQ0AAAsAYAB/DQAACwBiAKkNAAAMAGIAXA0AAAgAXABdDQAAAwBdAGUNAAAHAGEApA0AAAQAXQAzDQAACABfALkNAAAFAF4AAAA=.',
Be='Benghi:BAECNQAFFH8QAAMTAAYKhg7xDwDsAAaODQAABQArAHUNAAADACYAfw0AAAIANACpDQAAAQAbAFwNAAABACYAMw0AAAQAPAAUAAUKzw+GCgAvAQWODQAABQArAHUNAAACACYAfw0AAAIANABcDQAAAQAmADMNAAADABgAEwADCvIK8Q8A7AADdQ0AAAEAHACpDQAAAQAbADMNAAABADwANQAECn8sAAMTAAoKGx8rNQAFAgATAAcKxhwrNQAFAgAUAAcKJBk8JgCVAQAAAA==.Bestcase:BAECNQAFFH8cAAMVAAgKABA2BAAJAgiODQAABwBIAHUNAAAGABIAfw0AAAQABgCpDQAABQA+AFwNAAABAE4AXQ0AAAEACABlDQAAAQAEADMNAAADACoAFQAHCtgSNgQACQIHjg0AAAcASAB1DQAABgASAH8NAAAEAAYAqQ0AAAUAPgBcDQAAAQBOAF0NAAABAAgAMw0AAAEAKgAWAAIKzAEBCgAwAAJlDQAAAQAEADMNAAACABMANQAECn9GAAQVAAoKxCNzDAARAwAVAAoKxCNzDAARAwAWAAgK6hL0CwB2AQAXAAEKPQMHVgAdAAAAAA==.',
Br='Brigbala:BAEANQAECgYICgAAAA==.Bryndll:BAEANQADCgUIBQAAAA==.',
Bu='Burnassus:BAEANQAECgQIBAABNQAECgoKHwAPANsMAA==.',
Ch='Chunghús:BAEANQAECgQICAABNQAFFAEIAQARAAAAAA==.',
Co='Coggettle:BAEBNQAECn8eAAIYAAkK/RyKPgBZAgmODQAABABWAHUNAAAEAE4Afw0AAAQAGwCpDQAABABIAFwNAAAEAEkAXQ0AAAMAQQBlDQAAAwBQADMNAAADAEQAuQ0AAAEAPwAYAAkK/RyKPgBZAgmODQAABABWAHUNAAAEAE4Afw0AAAQAGwCpDQAABABIAFwNAAAEAEkAXQ0AAAMAQQBlDQAAAwBQADMNAAADAEQAuQ0AAAEAPwAAAA==.',
Cr='Crustage:BAEBNQAECn8rAAICAAoKWwjtgwChAQqODQAACAALAHUNAAAHAC4Afw0AAAUAHACpDQAABQASAFwNAAAFABEAXQ0AAAQAEwBlDQAAAwASAKQNAAADABIAMw0AAAEAFgC5DQAAAgAUAAIACgpbCO2DAKEBCo4NAAAIAAsAdQ0AAAcALgB/DQAABQAcAKkNAAAFABIAXA0AAAUAEQBdDQAABAATAGUNAAADABIApA0AAAMAEgAzDQAAAQAWALkNAAACABQAAAA=.',
Dc='Dcae:BAEANQADCgEIAQABNQAECgkJIwACAN0hAA==.',
Du='Dubsii:BAEANQAECgIIAgABNQAFFAgILgANAAIeAA==.Dubsy:BAEBNQAECn9KAAIGAAoK8iXKAgC7AwqODQAABwBbAHUNAAAIAGEAfw0AAAUAYgCpDQAACABiAFwNAAAGAGIAXQ0AAAkAYgBlDQAACgBjAKQNAAAKAGIAMw0AAAQAXQC5DQAABwBiAAYACgryJcoCALsDCo4NAAAHAFsAdQ0AAAgAYQB/DQAABQBiAKkNAAAIAGIAXA0AAAYAYgBdDQAACQBiAGUNAAAKAGMApA0AAAoAYgAzDQAABABdALkNAAAHAGIAATUABRQICC4ADQACHgA=.Dumblefrost:BAEBNQAECn8nAAMCAAkKhga3uwAuAQmODQAABwAMAHUNAAAFABYAfw0AAAUABwCpDQAABgAaAFwNAAAFAAsAXQ0AAAQADQBlDQAABAASAKQNAAABAAwAMw0AAAIABQACAAkKEQa3uwAuAQmODQAABQAEAHUNAAAFABYAfw0AAAUABwCpDQAABgAaAFwNAAAFAAsAXQ0AAAQADQBlDQAABAASAKQNAAABAAwAMw0AAAIABQADAAEKCwWsQgAtAAGODQAAAgAMAAAA.',
Eh='Ehanee:BAEBNQAECn8lAAIJAAkKQyHZEQBhAwmODQAABwBdAHUNAAAGAGAAfw0AAAUAYQCpDQAABgBWAFwNAAAEAGAAXQ0AAAIASgBlDQAAAwBQAKQNAAABAEMAMw0AAAMAWwAJAAkKQyHZEQBhAwmODQAABwBdAHUNAAAGAGAAfw0AAAUAYQCpDQAABgBWAFwNAAAEAGAAXQ0AAAIASgBlDQAAAwBQAKQNAAABAEMAMw0AAAMAWwAAAA==.',
Fa='Fappimeal:BAEANQAECgUICQAAAA==.Fappisham:BAEBNQAECn8hAAIJAAkK6h4VHwARAwmODQAABgBcAHUNAAADAE0Afw0AAAMAVACpDQAABQBVAFwNAAADAF8AXQ0AAAIASwBlDQAABABDAKQNAAADADsAMw0AAAQATQAJAAkK6h4VHwARAwmODQAABgBcAHUNAAADAE0Afw0AAAMAVACpDQAABQBVAFwNAAADAF8AXQ0AAAIASwBlDQAABABDAKQNAAADADsAMw0AAAQATQABNQAECgUICQARAAAAAA==.',
Fs='Fshi:BAECNQAFFH8NAAMSAAcKsBOrAAAHAgeODQAAAQBEAHUNAAACACgAfw0AAAEAEgCpDQAAAQBSAFwNAAABACMAZQ0AAAEAGQAzDQAABgBPABIABgooFqsAAAcCBo4NAAABAEQAdQ0AAAIAKAB/DQAAAQASAKkNAAABAFIAXA0AAAEAIwAzDQAAAgAvAAoAAgrQCXUiAEwAAmUNAAABABkAMw0AAAQATwA1AAQKf1MAAxIACgq/JXUAAPUDABIACgokI3UAAPUDAAoACAp6HtJCAOoBAAAA.',
Fu='Funkey:BAEANQAECggICgAAAA==.',
Gr='Greatanubis:BAEBNQAECn8VAAMKAAkKXw32OwAVAgmODQAAAgA6AHUNAAADADwAfw0AAAMANQCpDQAAAwAuAFwNAAACAAUAXQ0AAAIAGgBlDQAABAAXAKQNAAABABIAMw0AAAEAUgAKAAkKXw32OwAVAgmODQAAAgA6AHUNAAADADwAfw0AAAMANQCpDQAAAwAuAFwNAAABAAUAXQ0AAAIAGgBlDQAABAAXAKQNAAABABIAMw0AAAEAUgALAAEKvgELhAAZAAFcDQAAAQAEAAAA.Grumli:BAECNQAFFH8OAAIGAAcK9BbMCADFAQeODQAABABJAHUNAAACAF0Afw0AAAIARACpDQAAAwBhAFwNAAABAAsAXQ0AAAEAKAAzDQAAAQAbAAYABwr0FswIAMUBB44NAAAEAEkAdQ0AAAIAXQB/DQAAAgBEAKkNAAADAGEAXA0AAAEACwBdDQAAAQAoADMNAAABABsANQAECn84AAMGAAoKFRy3KwC0AgAGAAoKFRy3KwC0AgAJAAgK1xVtXQBvAQABNQADCgUIBQARAAAAAA==.Grummel:BAEANQADCgUIBQAAAA==.',
Ha='Halts:BAEANQAECgUIDAABNQAFFAUICAAGADkNAA==.',
Im='Imei:BAEANQAECgEIAQABNQAFFAcIGgAZAAQgAA==.',
Ja='Jail:BAEBNQAECn8jAAICAAkK3SFnHQBiAwmODQAABwBXAHUNAAAEAGMAfw0AAAMAYgCpDQAABABgAFwNAAADAFcAXQ0AAAMAXABlDQAABABMAKQNAAADAEMAMw0AAAQAXwACAAkK3SFnHQBiAwmODQAABwBXAHUNAAAEAGMAfw0AAAMAYgCpDQAABABgAFwNAAADAFcAXQ0AAAMAXABlDQAABABMAKQNAAADAEMAMw0AAAQAXwAAAA==.Jarco:BAEANQAECgQIBAABNQAFFAcIDgAaANQWAA==.',
Je='Jesyrosa:BAEANQAECgUIBQABNQAECgoKOwANAFIcAA==.',
Ka='Kanavi:BAECNQAFFH8aAAIZAAcKBCCEDADpAQeODQAABwBhAHUNAAAEAGAAfw0AAAIARgCpDQAABQBGAFwNAAABAFkAXQ0AAAEAOAAzDQAABgBbABkABwoEIIQMAOkBB44NAAAHAGEAdQ0AAAQAYAB/DQAAAgBGAKkNAAAFAEYAXA0AAAEAWQBdDQAAAQA4ADMNAAAGAFsANQAECn89AAIZAAoKvCXfCwAyAwAZAAoKvCXfCwAyAwAAAA==.Kantai:BAEANQADCgYICQABNQAFFAcIGgAZAAQgAA==.',
Kn='Knackered:BAEBNQAECn8pAAIbAAkK3RolFgDmAQmODQAABwBLAHUNAAAGAEQAfw0AAAYAUACpDQAABgA6AFwNAAAFAEgAXQ0AAAQAUgBlDQAAAQA/AKQNAAABADwAMw0AAAUASgAbAAkK3RolFgDmAQmODQAABwBLAHUNAAAGAEQAfw0AAAYAUACpDQAABgA6AFwNAAAFAEgAXQ0AAAQAUgBlDQAAAQA/AKQNAAABADwAMw0AAAUASgABNQABCgIIAgARAAAAAA==.',
Ko='Korikora:BAEANQADCgUICAABNQAECgcIHgAFAHoSAA==.',
Kr='Kregazi:BAEBNQAECn8xAAIHAAoKaCHhEQAdAwqODQAACABRAHUNAAAGAF0Afw0AAAUATACpDQAABgBUAFwNAAAEAFUAXQ0AAAQAWwBlDQAABgBHAKQNAAACAF4AMw0AAAcAWgC5DQAAAQBQAAcACgpoIeERAB0DCo4NAAAIAFEAdQ0AAAYAXQB/DQAABQBMAKkNAAAGAFQAXA0AAAQAVQBdDQAABABbAGUNAAAGAEcApA0AAAIAXgAzDQAABwBaALkNAAABAFAAAAA=.',
Ku='Kujali:BAEANQAECggICAABNQAECgoKUQASAFElAA==.Kuroi:BAEANQAECgcIBwABNQAFFAcIGgAZAAQgAA==.',
Ky='Kyssarra:BAECNQAFFH8pAAQcAAkKgSFIAACOAQmODQAACABjAHUNAAAGAF4Afw0AAAYAVwCpDQAABgBjAFwNAAAFAE4AXQ0AAAEATABlDQAAAgA/AKQNAAABAFgAMw0AAAYAXgAcAAYK9SFIAACOAQaODQAAAQBVAHUNAAAGAF4Afw0AAAEAVwCpDQAABgBjAFwNAAABAE4AXQ0AAAEATAAPAAUKtSKSGgAhAQWODQAABwBjAH8NAAAFAFIAXA0AAAMATgCkDQAAAQBYADMNAAABAF4AHQADCt4WOAMAxwADXA0AAAEANQBlDQAAAgA/ADMNAAAFAF4ANQAECn+SAAQcAAoKviYXAAALBAAcAAkKxCYXAAALBAAPAAkKHCY1DgD7AgAdAAUKgiZUCAALAgAAAA==.',
Le='Lexielulu:BAEANQABCgIIBAABNQAECgYICgARAAAAAA==.',
Lo='Lobotomight:BAEANQAECgcIDQABNQAECggICgARAAAAAA==.',
Lu='Lunaë:BAECNQAFFH8TAAMIAAUKgRdcFgBSAQWODQAABABSAHUNAAAEAB4Afw0AAAQARgCpDQAABAAsADMNAAADAEkACAAECgMZXBYAUgEEjg0AAAIAUgB1DQAAAQAeAH8NAAABAEYAMw0AAAMASQAQAAQKVQpZDADSAASODQAAAgAnAHUNAAADABEAfw0AAAMAEQCpDQAABAAWADUABAp/bAADCAAKCjAgLg0AdgMACAAKCjAgLg0AdgMAEAAFCusMCy8AEAEAAAA=.Lunäe:BAEBNQAECn9EAAIIAAoK4SAoEwA/AwqODQAADQBWAHUNAAAIAFgAfw0AAAsAXQCpDQAABgBBAFwNAAAFAFsAXQ0AAAYATABlDQAACABIAKQNAAAGAFIAMw0AAAMAYAC5DQAAAgBYAAgACgrhICgTAD8DCo4NAAANAFYAdQ0AAAgAWAB/DQAACwBdAKkNAAAGAEEAXA0AAAUAWwBdDQAABgBMAGUNAAAIAEgApA0AAAYAUgAzDQAAAwBgALkNAAACAFgAATUABRQFCBMACACBFwA=.',
['Lü']='Lünae:BAEBNQAECn8XAAIIAAoKCxNsRAAmAgqODQAAAwBRAHUNAAADAD0Afw0AAAMAUgCpDQAABAA9AFwNAAABAA8AXQ0AAAEABgBlDQAAAwAcAKQNAAACADsAMw0AAAEABgC5DQAAAgBUAAgACgoLE2xEACYCCo4NAAADAFEAdQ0AAAMAPQB/DQAAAwBSAKkNAAAEAD0AXA0AAAEADwBdDQAAAQAGAGUNAAADABwApA0AAAIAOwAzDQAAAQAGALkNAAACAFQAATUABRQFCBMACACBFwA=.',
Ma='Maildaddy:BAEANQAFFAEIAQAAAA==.Massivemoon:BAEANQAECgIIAQAAAA==.Maxxy:BAEANQAECgcIDwAAAA==.',
Mc='Mckellen:BAEANQAECgcIEwABNQAFFAgILgANAAIeAA==.',
Me='Merarite:BAEBNQAECn9IAAIHAAoKRBbWLgBYAgqODQAADAA8AHUNAAAIAEsAfw0AAAgANACpDQAACABCAFwNAAAHAEYAXQ0AAAcAJQBlDQAACABJAKQNAAAFACkAMw0AAAQAPQC5DQAABQAgAAcACgpEFtYuAFgCCo4NAAAMADwAdQ0AAAgASwB/DQAACAA0AKkNAAAIAEIAXA0AAAcARgBdDQAABwAlAGUNAAAIAEkApA0AAAUAKQAzDQAABAA9ALkNAAAFACAAAAA=.',
Mo='Monkguyy:BAEANQAECgYIBwABNQAECgkJJwACAIYGAA==.',
['Mý']='Mýthra:BAECNQAFFH8GAAMCAAYKLyB6GgAhAQaODQAAAQBJAHUNAAABAFcAfw0AAAEAYABcDQAAAQBVAF0NAAABAFIAMw0AAAEAAQACAAUKHyB6GgAhAQWODQAAAQBJAHUNAAABAFcAfw0AAAEAYABcDQAAAQBVADMNAAABAAEAAwABCl8gNwwAYgABXQ0AAAEAUgA1AAQKfxoAAwIACgobI/UwAH0CAAIACArdJPUwAH0CAAMAAgrTHawlALAAAAAA.',
Na='Nadasa:BAECNQAFFH8JAAIeAAIKwB03HgCoAAKODQAABwBPAKkNAAACAEgAHgACCsAdNx4AqAACjg0AAAcATwCpDQAAAgBIADUABAp/rwACHgAKCmYlPAYAZQMAHgAKCmYlPAYAZQMAAAA=.',
Ni='Nixaanu:BAEANQADCgYICQAAAA==.',
No='Nomadicbear:BAEANQABCgQICAABNQABCgYICAARAAAAAA==.Nomadichunt:BAEANQABCgYICAAAAA==.Nomadicmonk:BAEANQABCgUIBwABNQABCgYICAARAAAAAA==.',
Ny='Nyriaa:BAEANQADCggICAAAAA==.',
['Ní']='Nítedragon:BAEANQAECgMIAwABNQAECgoKOwANAFIcAA==.',
Pa='Painsmith:BAEANQAECgEIAQABNQAECgoKHwAPANsMAA==.Palashin:BAEANQAECgQIBQABNQAFFAUICAAGADkNAA==.',
Pe='Personnelkid:BAEANQADCggICAABNQAECgoKHwAPANsMAA==.',
Ph='Phiirshark:BAEBNQAECn8/AAIfAAoK6SNOBQAiAwqODQAACwBdAHUNAAAGAFkAfw0AAAYAXgCpDQAABwBeAFwNAAAFAFsAXQ0AAAQAVgBlDQAACABcAKQNAAAFAGAAMw0AAAYAXwC5DQAABQBbAB8ACgrpI04FACIDCo4NAAALAF0AdQ0AAAYAWQB/DQAABgBeAKkNAAAHAF4AXA0AAAUAWwBdDQAABABWAGUNAAAIAFwApA0AAAUAYAAzDQAABgBfALkNAAAFAFsAAAA=.',
Po='Poortal:BAEANQAECgEIAQABNQAECggICgARAAAAAA==.Potatogogue:BAECNQAFFH8PAAMJAAcKGxDJFAArAQeODQAABAAuAHUNAAACAA4Afw0AAAEAMgCpDQAAAwAfAFwNAAACAFoAZQ0AAAEAFwAzDQAAAgAiAAkABQpUC8kUACsBBY4NAAAEAC4AdQ0AAAIADgCpDQAAAwAfAGUNAAABABcAMw0AAAIAIgAGAAIKWhREHgChAAJ/DQAAAQBLAFwNAAACABwANQAECn8uAAMJAAoKcCOIJQDuAgAJAAoKcCOIJQDuAgAGAAIKUB9G8QCIAAABNQAFFAEIAQARAAAAAA==.Potatoroguee:BAEANQAECgYIBwABNQAFFAEIAQARAAAAAA==.',
Pu='Punchweagle:BAEANQAECgMIAwABNQAECgoKSAAHAEQWAA==.',
Ro='Roogies:BAECNQAFFH8QAAMTAAUKoR3HBgCuAQWODQAABgBhAHUNAAADAGEAfw0AAAIAUACpDQAABABfAFwNAAABAA0AEwAECsMlxwYArgEEjg0AAAYAYQB1DQAAAwBhAH8NAAABAFAAqQ0AAAQAXwAUAAIKOgU8JgBQAAJ/DQAAAQAeAFwNAAABAA0ANQAECn9PAAMTAAoKmSScAwCeAwATAAoKZSScAwCeAwAUAAUKbR5SaAByAQAAAA==.',
Se='Senzarial:BAEANQAECgIIAQABNQAFFAgIGAAKAMkdAA==.',
Sh='Shalanzar:BAEANQAECgYIDQABNQAFFAUIEwAIAIEXAA==.Shinseer:BAECNQAFFH8IAAIGAAUKOQ0lDwBdAQWODQAAAQAvAHUNAAABAAsAfw0AAAIAIACpDQAAAQA5ADMNAAADABQABgAFCjkNJQ8AXQEFjg0AAAEALwB1DQAAAQALAH8NAAACACAAqQ0AAAEAOQAzDQAAAwAUADUABAp/LgACBgAJCmEfxRIAMwMABgAJCmEfxRIAMwMAAAA=.Shinthyr:BAEBNQAECn8iAAIIAAkKEBaNRQBWAgmODQAACwBfAHUNAAAEAEQAfw0AAAQASwCpDQAABQBTAFwNAAABACcAZQ0AAAEACQCkDQAAAgANADMNAAAFAF0AuQ0AAAEAHgAIAAkKEBaNRQBWAgmODQAACwBfAHUNAAAEAEQAfw0AAAQASwCpDQAABQBTAFwNAAABACcAZQ0AAAEACQCkDQAAAgANADMNAAAFAF0AuQ0AAAEAHgABNQAFFAUICAAGADkNAA==.',
St='Starryangel:BAEANQAECgEIAQABNQAFFAcIHwAeACoSAA==.Stormbroken:BAEANQADCgUIBgABNQAECgoKHwAPANsMAA==.',
Su='Sunwelljuice:BAEANQADCggIHwABNQAECgoKHwAPANsMAA==.',
Sy='Syldrasi:BAEANQADCgQICAABNQAFFAUIEAATAKEdAA==.',
Ta='Tahune:BAEBNQAECn9ZAAQLAAoKBSQiAwDWAwqODQAADQBZAHUNAAAKAGIAfw0AAAkAUgCpDQAACwBcAFwNAAAKAFEAXQ0AAAgAYgBlDQAACQBiAKQNAAAGAGAAMw0AAAgAVgC5DQAABQBgAAsACgoFJCIDANYDCo4NAAALAFkAdQ0AAAgAYgB/DQAABwBSAKkNAAAJAFwAXA0AAAgAUQBdDQAABwBiAGUNAAAJAGIApA0AAAUAYAAzDQAABwBWALkNAAAEAGAACgAHCrgdf0MA5gEHjg0AAAEAUQB1DQAAAQBNAH8NAAABAC8AqQ0AAAEAPABcDQAAAQBPAKQNAAABAFEAMw0AAAEATAAMAAcKCBiaHgCOAQeODQAAAQA8AHUNAAABADgAfw0AAAEAOwCpDQAAAQBBAFwNAAABAEIAXQ0AAAEAMgC5DQAAAQBGAAAA.Talaandea:BAEANQADCggIEwAAAA==.',
Th='Thawd:BAECNQAFFH8hAAIWAAgKrRccAQA2AgiODQAABgBZAHUNAAAFAEYAfw0AAAUAPACpDQAABgAwAFwNAAAEACoAXQ0AAAIALQBlDQAAAQBCADMNAAAEADwAFgAICq0XHAEANgIIjg0AAAYAWQB1DQAABQBGAH8NAAAFADwAqQ0AAAYAMABcDQAABAAqAF0NAAACAC0AZQ0AAAEAQgAzDQAABAA8ADUABAp/OAADFgAKCssfDgUAWgIAFgAKCssfDgUAWgIAFQAJCj0QmhoA1wEAAAA=.Therapygap:BAEANQAECgUIDgABNQAECgoKHwAPANsMAA==.',
Tr='Trèantdaddy:BAEANQAECgYIBgABNQAFFAEIAQARAAAAAA==.',
Vc='Vcoren:BAEBNQAECn8iAAIgAAoKXiPJAwC2AwqODQAAAwBaAHUNAAAFAFwAfw0AAAUAXwCpDQAABQBeAFwNAAAFAF8AXQ0AAAQAXwBlDQAAAgBgAKQNAAACAFMAMw0AAAIAYgC5DQAAAQA9ACAACgpeI8kDALYDCo4NAAADAFoAdQ0AAAUAXAB/DQAABQBfAKkNAAAFAF4AXA0AAAUAXwBdDQAABABfAGUNAAACAGAApA0AAAIAUwAzDQAAAgBiALkNAAABAD0AATUABRQICC4ADQACHgA=.',
Ve='Velleiroth:BAEANQAECgcIDgABNQAFFAgIGAAKAMkdAA==.',
Wh='Whimsiloxi:BAEANQAECgQICgABNQAFFAgIGAAKAMkdAA==.',
Za='Zatum:BAEBNQAECn8mAAQMAAkKRR8kDwBFAgmODQAABwBSAHUNAAAGAFcAfw0AAAUAYwCpDQAABQBJAFwNAAAFAFoAXQ0AAAIATwBlDQAAAQBJADMNAAAGAFUAuQ0AAAEASAAMAAkKRR8kDwBFAgmODQAABQBSAHUNAAAFAFcAfw0AAAUAYwCpDQAABQBJAFwNAAAFAFoAXQ0AAAIATwBlDQAAAQBJADMNAAAEAFUAuQ0AAAEASAAKAAIKYxrvlACEAAKODQAAAQBDADMNAAACADQACwACCkYShWYAawACjg0AAAEALQB1DQAAAQAvAAAA.',
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
