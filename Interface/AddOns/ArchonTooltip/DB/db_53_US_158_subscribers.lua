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

local lookup = {'Druid-Feral','Evoker-Augmentation','Mage-Arcane','Mage-Frost','DeathKnight-Blood','Priest-Holy','Shaman-Elemental','Druid-Balance','Druid-Restoration','Druid-Guardian','Evoker-Preservation','Evoker-Devastation','Warlock-Demonology','Priest-Shadow','Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Hunter-BeastMastery','Shaman-Restoration','Warrior-Arms','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Warrior-Protection','Paladin-Holy',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=53,date='2026-10-20',data={Ae='Aesinth:BAEANQAECgQIAgABNQAECgkJKgABAG4cAA==.',
Ak='Akaeva:BAEANQAECgYIBgAAAA==.',
Al='Alcean:BAEBNQAECn8aAAICAAgK6BT0CAD8AQiODQAABgA/AHUNAAAEAD8Afw0AAAIAHQCpDQAABABIAFwNAAADAC8AXQ0AAAEAMQBlDQAAAQAXADMNAAAFAD8AAgAICugU9AgA/AEIjg0AAAYAPwB1DQAABAA/AH8NAAACAB0AqQ0AAAQASABcDQAAAwAvAF0NAAABADEAZQ0AAAEAFwAzDQAABQA/AAAA.Algebra:BAECNQAFFH8OAAMDAAUK9SGDCwD/AAWODQAABABjAHUNAAADAEkAfw0AAAIAXACpDQAABABXADMNAAABAB4AAwAFCsEhgwsA/wAFjg0AAAQAYwB1DQAAAQBIAH8NAAACAFwAqQ0AAAQAVwAzDQAAAQAeAAQAAQrNHMwNAFUAAXUNAAACAEkANQAECn8jAAMDAAoKySNjFgC4AQADAAoKQSFjFgC4AQAEAAMK5SIWIgDaAAAAAA==.',
Ar='Araakki:BAEANQAECgQIEgAAAA==.Aradell:BAEBNQAECn83AAIFAAkKqRfjMABNAgmODQAACQBSAHUNAAAIAEQAfw0AAAgARwCpDQAACABDAFwNAAAFAEkAXQ0AAAUAOgBlDQAABAA6AKQNAAABAA8AMw0AAAcAUQAFAAkKqRfjMABNAgmODQAACQBSAHUNAAAIAEQAfw0AAAgARwCpDQAACABDAFwNAAAFAEkAXQ0AAAUAOgBlDQAABAA6AKQNAAABAA8AMw0AAAcAUQAAAA==.Arceni:BAEANQAECggICAABNQAECgkJNwAFAKkXAA==.Ariizi:BAEANQAECgUIDQAAAA==.Artam:BAEANQADCggICQABNQAFFAcIJwAGAF0cAA==.Arteron:BAEANQADCggICAABNQAFFAcIIwAHAPYjAA==.',
Au='Augstrasza:BAEANQAECgMIAwAAAA==.Aukanawe:BAECNQAFFH8XAAIIAAcKqh3lAwB6AgeODQAABgBhAHUNAAAEADIAfw0AAAIATACpDQAABABfAFwNAAACAEMAXQ0AAAEARAAzDQAABABBAAgABwqqHeUDAHoCB44NAAAGAGEAdQ0AAAQAMgB/DQAAAgBMAKkNAAAEAF8AXA0AAAIAQwBdDQAAAQBEADMNAAAEAEEANQAECn9JAAQIAAoKOyVoBgCiAwAIAAoKOyVoBgCiAwAJAAQKoA/mSwDfAAAKAAEK3iG/KABoAAAAAA==.',
Av='Averelle:BAEANQAECgcICgAAAA==.',
Ay='Ayoade:BAECNQAFFH8mAAILAAcKvxxHAwBhAgeODQAABwA3AHUNAAAGAEgAfw0AAAYAWACpDQAABwBXAFwNAAAEAD8AXQ0AAAIAMgAzDQAABgBgAAsABwq/HEcDAGECB44NAAAHADcAdQ0AAAYASAB/DQAABgBYAKkNAAAHAFcAXA0AAAQAPwBdDQAAAgAyADMNAAAGAGAANQAECn80AAMLAAoKpyQyAwCGAwALAAoKpyQyAwCGAwAMAAEKAAB/GAAAAAAAAA==.',
Az='Azzurel:BAEBNQAECn85AAINAAoKqRbkCgD8AQqODQAABwAuAHUNAAAHAEUAfw0AAAYAJwCpDQAABwA1AFwNAAAHAE8AXQ0AAAYAMABlDQAABQBIAKQNAAADAEAAMw0AAAgAQwC5DQAAAQAdAA0ACgqpFuQKAPwBCo4NAAAHAC4AdQ0AAAcARQB/DQAABgAnAKkNAAAHADUAXA0AAAcATwBdDQAABgAwAGUNAAAFAEgApA0AAAMAQAAzDQAACABDALkNAAABAB0AAAA=.',
Ba='Babaghanouj:BAEBNQAECn8gAAMOAAcKdBTFLgCuAQeODQAABgBBAHUNAAAEACsAfw0AAAQAKACpDQAABQA3AFwNAAAFADgAXQ0AAAMAKAAzDQAABQAuAA4ABwp0FMUuAK4BB44NAAAFAEEAdQ0AAAQAKwB/DQAABAAoAKkNAAAFADcAXA0AAAIAOABdDQAAAgAoADMNAAADAC4ABgAEClogOKIALwEEjg0AAAEASQBcDQAAAwBUAF0NAAABAFsAMw0AAAIAUQAAAA==.Babycino:BAEANQAECgMIBAABNQAECgcICgAPAAAAAA==.Bayati:BAEBNQAECn83AAIBAAoK6SJLAgCUAwqODQAACQBgAHUNAAAIAFsAfw0AAAcAYgCpDQAACABdAFwNAAAGAFwAXQ0AAAIAXQBlDQAABQBSAKQNAAACAEcAMw0AAAUAXwC5DQAAAwBeAAEACgrpIksCAJQDCo4NAAAJAGAAdQ0AAAgAWwB/DQAABwBiAKkNAAAIAF0AXA0AAAYAXABdDQAAAgBdAGUNAAAFAFIApA0AAAIARwAzDQAABQBfALkNAAADAF4AAAA=.',
Be='Benghi:BAECNQAFFH8QAAMQAAYKhg5TBgDqAAaODQAABQArAHUNAAADACYAfw0AAAIANACpDQAAAQAbAFwNAAABACYAMw0AAAQAPAARAAMK8grxDwDsAAN1DQAAAQAcAKkNAAABABsAMw0AAAEAPAAQAAUKzw9TBgDqAAWODQAABQArAHUNAAACACYAfw0AAAIANABcDQAAAQAmADMNAAADABgANQAECn8sAAMRAAoKGx8rNQAFAgARAAcKxhwrNQAFAgAQAAcKJBnkJgDHAAAAAA==.Bestcase:BAECNQAFFH8TAAISAAcK2BI2BAAJAgeODQAABQBIAHUNAAAEABIAfw0AAAMABQCpDQAABAA+AFwNAAABAE4AXQ0AAAEACAAzDQAAAQAqABIABwrYEjYEAAkCB44NAAAFAEgAdQ0AAAQAEgB/DQAAAwAFAKkNAAAEAD4AXA0AAAEATgBdDQAAAQAIADMNAAABACoANQAECn8vAAQSAAoKdyBzDAARAwASAAkK4CNzDAARAwATAAQKWAopCwClAAAUAAEKPQMHVgAdAAAAAA==.',
Bi='Birchmire:BAEANQAECgUIBQABNQAECgkJKgABAG4cAA==.',
Br='Brigbala:BAEANQAECgQIBQAAAA==.',
Bu='Burnassus:BAEANQADCggIFwABNQAECgoKKAAGALATAA==.',
Ch='Chunghús:BAEANQAECgQICAABNQAFFAEIAQAPAAAAAA==.',
Co='Coggettle:BAEANQAECgYIBgABNQAECgoKIwAVADUgAA==.',
Cr='Crustage:BAEANQAECgcIEQAAAA==.',
Dc='Dcae:BAEANQADCgEIAQABNQAECgkJIwADAN0hAA==.',
Du='Dubsy:BAEBNQAECn8pAAIWAAoKdSXKAgC7AwqODQAABABbAHUNAAAFAGEAfw0AAAMAYgCpDQAABQBiAFwNAAADAGIAXQ0AAAYAYgBlDQAABgBjAKQNAAAGAF4AMw0AAAIAXQC5DQAAAQBaABYACgp1JcoCALsDCo4NAAAEAFsAdQ0AAAUAYQB/DQAAAwBiAKkNAAAFAGIAXA0AAAMAYgBdDQAABgBiAGUNAAAGAGMApA0AAAYAXgAzDQAAAgBdALkNAAABAFoAATUABRQHCCYACwC/HAA=.Dumblefrost:BAEBNQAECn8dAAIDAAgK4wTgagDnAAiODQAABQAEAHUNAAAEABYAfw0AAAQABwCpDQAABAAMAFwNAAAEAAkAXQ0AAAMABwBlDQAAAwASADMNAAACAAUAAwAICuME4GoA5wAIjg0AAAUABAB1DQAABAAWAH8NAAAEAAcAqQ0AAAQADABcDQAABAAJAF0NAAADAAcAZQ0AAAMAEgAzDQAAAgAFAAAA.',
Eh='Ehanee:BAEBNQAECn8hAAIHAAkKQyHZEQBhAwmODQAABgBdAHUNAAAFAGAAfw0AAAQAYQCpDQAABQBWAFwNAAAEAGAAXQ0AAAIASgBlDQAAAwBQAKQNAAABAEMAMw0AAAMAWwAHAAkKQyHZEQBhAwmODQAABgBdAHUNAAAFAGAAfw0AAAQAYQCpDQAABQBWAFwNAAAEAGAAXQ0AAAIASgBlDQAAAwBQAKQNAAABAEMAMw0AAAMAWwAAAA==.',
Fa='Fappimeal:BAEANQAECgUICQAAAA==.Fappisham:BAEBNQAECn8hAAIHAAkK6h4VHwARAwmODQAABgBcAHUNAAADAE0Afw0AAAMAVACpDQAABQBVAFwNAAADAF8AXQ0AAAIASwBlDQAABABDAKQNAAADADsAMw0AAAQATQAHAAkK6h4VHwARAwmODQAABgBcAHUNAAADAE0Afw0AAAMAVACpDQAABQBVAFwNAAADAF8AXQ0AAAIASwBlDQAABABDAKQNAAADADsAMw0AAAQATQABNQAECgUICQAPAAAAAA==.',
Fs='Fshi:BAECNQAFFH8KAAMBAAYKKBarAAAHAgaODQAAAQBEAHUNAAACACgAfw0AAAEAEgCpDQAAAQBSAFwNAAABACMAMw0AAAQALwABAAYKKBarAAAHAgaODQAAAQBEAHUNAAACACgAfw0AAAEAEgCpDQAAAQBSAFwNAAABACMAMw0AAAIALwAIAAEKAABRKQA9AAEzDQAAAgAkADUABAp/TgADAQAKCiQjdQAA9QMAAQAKCiQjdQAA9QMACAAGClod0kIA6gEAAAA=.',
Gr='Greatanubis:BAEBNQAECn8VAAMIAAkKXw32OwAVAgmODQAAAgA6AHUNAAADADwAfw0AAAMANQCpDQAAAwAuAFwNAAACAAUAXQ0AAAIAGgBlDQAABAAXAKQNAAABABIAMw0AAAEAUgAIAAkKXw32OwAVAgmODQAAAgA6AHUNAAADADwAfw0AAAMANQCpDQAAAwAuAFwNAAABAAUAXQ0AAAIAGgBlDQAABAAXAKQNAAABABIAMw0AAAEAUgAJAAEKvgELhAAZAAFcDQAAAQAEAAAA.',
Ha='Halts:BAEANQAECgUICgABNQAFFAUICAAWADkNAA==.',
Im='Imei:BAEANQAECgEIAQABNQAFFAUIGAAXAGYiAA==.',
Ja='Jail:BAEBNQAECn8jAAIDAAkK3SFnHQBiAwmODQAABwBXAHUNAAAEAGMAfw0AAAMAYgCpDQAABABgAFwNAAADAFcAXQ0AAAMAXABlDQAABABMAKQNAAADAEMAMw0AAAQAXwADAAkK3SFnHQBiAwmODQAABwBXAHUNAAAEAGMAfw0AAAMAYgCpDQAABABgAFwNAAADAFcAXQ0AAAMAXABlDQAABABMAKQNAAADAEMAMw0AAAQAXwAAAA==.Jarco:BAEANQAECgQIBAAAAA==.',
Je='Jesyrosa:BAEANQAECgUIBQABNQAECgoKKAALAOMaAA==.',
Ka='Kanavi:BAECNQAFFH8YAAIXAAUKZiKEDADpAQWODQAABwBhAHUNAAAEAGAAfw0AAAIARgCpDQAABQBGADMNAAAGAFsAFwAFCmYihAwA6QEFjg0AAAcAYQB1DQAABABgAH8NAAACAEYAqQ0AAAUARgAzDQAABgBbADUABAp/MgACFwAKCn0koQ8AgQMAFwAKCn0koQ8AgQMAAAA=.Kantai:BAEANQADCgYICQABNQAFFAUIGAAXAGYiAA==.',
Kn='Knackered:BAEBNQAECn8hAAIYAAcK7BukBwBrAQeODQAABgBLAHUNAAAFAEQAfw0AAAUAUACpDQAABQA6AFwNAAAEAEgAXQ0AAAMAUgAzDQAABQBKABgABwrsG6QHAGsBB44NAAAGAEsAdQ0AAAUARAB/DQAABQBQAKkNAAAFADoAXA0AAAQASABdDQAAAwBSADMNAAAFAEoAATUAAQoCCAIADwAAAAA=.',
Ko='Korikora:BAEANQADCgUICAABNQAECgQIEgAPAAAAAA==.',
Kr='Kregazi:BAEBNQAECn8tAAIFAAkKqyHhEQAdAwmODQAABwBRAHUNAAAGAF0Afw0AAAUATACpDQAABgBUAFwNAAAEAFUAXQ0AAAQAWwBlDQAABQBHAKQNAAACAF4AMw0AAAYAWgAFAAkKqyHhEQAdAwmODQAABwBRAHUNAAAGAF0Afw0AAAUATACpDQAABgBUAFwNAAAEAFUAXQ0AAAQAWwBlDQAABQBHAKQNAAACAF4AMw0AAAYAWgAAAA==.',
Ky='Kyssarra:BAECNQAFFH8hAAQZAAgKcx4QAACjAQiODQAABgBjAHUNAAAFAFgAfw0AAAUAVwCpDQAABQBjAFwNAAAFAE4AXQ0AAAEATABlDQAAAQAZADMNAAAFAF4AGQAGCm4hEAAAowEGjg0AAAEAVQB1DQAABQBYAH8NAAABAFcAqQ0AAAUAYwBcDQAAAQBOAF0NAAABAEwADQADCtYikhoAIQEDjg0AAAUAYwB/DQAABABSAFwNAAADAE4AGgADCnwPOAMAxwADXA0AAAEANQBlDQAAAQAZADMNAAAFAF4ANQAECn9/AAQZAAkK4iYXAAALBAAZAAkKxCYXAAALBAANAAUKYya2bwAQAgAaAAUKgiZUCAALAgAAAA==.',
Lo='Lobotomight:BAEANQAECgcIDQABNQAFFAMIBwAFAFoRAA==.',
Lu='Lunaë:BAEBNQAECn8/AAMGAAoK5xy1EgA1AwqODQAACQBJAHUNAAAHAFEAfw0AAAcAWQCpDQAACQBMAFwNAAAIAFAAXQ0AAAUAMQBlDQAABgBTAKQNAAAGAFwAMw0AAAUAYAC5DQAAAQAQAAYACgrnHLUSADUDCo4NAAAIAEkAdQ0AAAcAUQB/DQAABwBZAKkNAAAJAEwAXA0AAAgAUABdDQAABQAxAGUNAAAFAFMApA0AAAYAXAAzDQAABQBgALkNAAABABAADgACCrsJiyIAeQACjg0AAAEAKABlDQAAAQAJAAAA.Lunäe:BAEBNQAECn8nAAIGAAkKdx20BQChAgmODQAACABWAHUNAAAFAFEAfw0AAAcAVQCpDQAABABBAFwNAAADAFMAXQ0AAAQAPQBlDQAAAwA9AKQNAAACADkAMw0AAAMAYAAGAAkKdx20BQChAgmODQAACABWAHUNAAAFAFEAfw0AAAcAVQCpDQAABABBAFwNAAADAFMAXQ0AAAQAPQBlDQAAAwA9AKQNAAACADkAMw0AAAMAYAABNQAECgoKPwAGAOccAA==.',
['Lü']='Lünae:BAEANQAECgcIBwABNQAECgoKPwAGAOccAA==.',
Ma='Maildaddy:BAEANQAFFAEIAQAAAA==.Maxxy:BAEANQAECgYIDwAAAA==.',
Mc='Mckellen:BAEANQAECgcIEwABNQAFFAcIJgALAL8cAA==.',
Me='Merarite:BAEBNQAECn84AAIFAAoKKxXNCgCWAQqODQAACAA8AHUNAAAIAEsAfw0AAAcANACpDQAACABCAFwNAAAHAEYAXQ0AAAYAJABlDQAABQBJAKQNAAACACEAMw0AAAQAPQC5DQAAAQASAAUACgorFc0KAJYBCo4NAAAIADwAdQ0AAAgASwB/DQAABwA0AKkNAAAIAEIAXA0AAAcARgBdDQAABgAkAGUNAAAFAEkApA0AAAIAIQAzDQAABAA9ALkNAAABABIAAAA=.',
Mo='Monkguyy:BAEANQAECgYIBwABNQAECggIHQADAOMEAA==.',
['Mý']='Mýthra:BAEANQAECggICAAAAA==.',
Na='Nadasa:BAEBNQAECn9qAAIbAAoK0h/2BQCMAgqODQAAFABfAHUNAAARAGAAfw0AABAAYQCpDQAAEABYAFwNAAAKAGEAXQ0AAAMARwBlDQAACgBaAKQNAAADAEsAMw0AAAoAWwC5DQAAAQAjABsACgrSH/YFAIwCCo4NAAAUAF8AdQ0AABEAYAB/DQAAEABhAKkNAAAQAFgAXA0AAAoAYQBdDQAAAwBHAGUNAAAKAFoApA0AAAMASwAzDQAACgBbALkNAAABACMAAAA=.',
Ni='Nixaanu:BAEANQADCgYICQAAAA==.',
No='Nomadicbear:BAEANQABCgQICAABNQABCgYICAAPAAAAAA==.Nomadichunt:BAEANQABCgYICAAAAA==.Nomadicmonk:BAEANQABCgQIBAABNQABCgYICAAPAAAAAA==.',
Ny='Nyriaa:BAEANQADCggICAAAAA==.',
Pa='Palashin:BAEANQAECgQIBQABNQAFFAUICAAWADkNAA==.',
Pe='Personnelkid:BAEANQADCggICAABNQAECgoKKAAGALATAA==.',
Ph='Phiirshark:BAEBNQAECn8vAAIcAAoKkyBOBQAiAwqODQAABwBbAHUNAAAGAFkAfw0AAAYAXgCpDQAABwBeAFwNAAAFAFsAXQ0AAAQAVgBlDQAABABUAKQNAAABAFoAMw0AAAYAXwC5DQAAAQAnABwACgqTIE4FACIDCo4NAAAHAFsAdQ0AAAYAWQB/DQAABgBeAKkNAAAHAF4AXA0AAAUAWwBdDQAABABWAGUNAAAEAFQApA0AAAEAWgAzDQAABgBfALkNAAABACcAAAA=.',
Po='Poortal:BAEANQAECgEIAQABNQAFFAMIBwAFAFoRAA==.Potatogogue:BAECNQAFFH8NAAMHAAYK3RHJFAArAQaODQAABAAuAHUNAAACAA4Afw0AAAEAMgCpDQAAAwAfAFwNAAACAFoAMw0AAAEAGAAHAAQKFAzJFAArAQSODQAABAAuAHUNAAACAA4AqQ0AAAMAHwAzDQAAAQAYABYAAgpaFEQeAKEAAn8NAAABAEsAXA0AAAIAHAA1AAQKfycAAwcACgpaH4glAO4CAAcACgpaH4glAO4CABYAAgpQH0bxAIgAAAE1AAUUAQgBAA8AAAAA.Potatoroguee:BAEANQAECgYIBwABNQAFFAEIAQAPAAAAAA==.',
Ri='Ritren:BAEANQAECgMIAwABNQAECgcIDgAPAAAAAA==.',
Ro='Roogies:BAECNQAFFH8PAAMRAAQKwyW/AQAaAQSODQAABgBhAHUNAAADAGEAfw0AAAIAUACpDQAABABfABEABArDJb8BABoBBI4NAAAGAGEAdQ0AAAMAYQB/DQAAAQBQAKkNAAAEAF8AEAABCgAAURAAAAABfw0AAAEAHgA1AAQKf0QAAhEACgrKI5wDAJ4DABEACgrKI5wDAJ4DAAAA.',
Se='Senzarial:BAEANQAECgEIAQABNQAFFAcIFwAIAKodAA==.Serynytee:BAEBNQAECn8VAAQZAAgK1xtLJQBJAQiODQAABABZAHUNAAACAD4Afw0AAAMAOACpDQAABABQAFwNAAADAFcAXQ0AAAMARQBlDQAAAQAkADMNAAABACIAGQAECpsdSyUASQEEjg0AAAIAWQB1DQAAAgA+AKkNAAADAFAAXQ0AAAIARQANAAYK9hPXOQAdAQaODQAAAgAsAH8NAAACACgAqQ0AAAEAPABdDQAAAQA+AGUNAAABACQAMw0AAAEAIgAaAAIKSyJpGwCmAAJ/DQAAAQA4AFwNAAADAFcAAAA=.',
Sh='Shinseer:BAECNQAFFH8IAAIWAAUKOQ0lDwBdAQWODQAAAQAvAHUNAAABAAsAfw0AAAIAIACpDQAAAQA5ADMNAAADABQAFgAFCjkNJQ8AXQEFjg0AAAEALwB1DQAAAQALAH8NAAACACAAqQ0AAAEAOQAzDQAAAwAUADUABAp/KgACFgAJCmEfxRIAMwMAFgAJCmEfxRIAMwMAAAA=.Shinthyr:BAEBNQAECn8ZAAIGAAgKpxaNRQBWAgiODQAACABRAHUNAAADAEQAfw0AAAMASwCpDQAAAwBTAFwNAAABACcAZQ0AAAEACQCkDQAAAgANADMNAAAEAF0ABgAICqcWjUUAVgIIjg0AAAgAUQB1DQAAAwBEAH8NAAADAEsAqQ0AAAMAUwBcDQAAAQAnAGUNAAABAAkApA0AAAIADQAzDQAABABdAAE1AAUUBQgIABYAOQ0A.',
St='Starryangel:BAEANQAECgEIAQABNQAFFAUIFwAbAAUTAA==.Stormbroken:BAEANQADCgUIBQABNQAECgoKKAAGALATAA==.',
Su='Sunwelljuice:BAEANQADCggIGQABNQAECgoKKAAGALATAA==.',
Sy='Syldrasi:BAEANQADCgQICAABNQAFFAQIDwARAMMlAA==.',
Ta='Tahune:BAEBNQAECn89AAMJAAoKHyLDAACBAwqODQAACQBZAHUNAAAIAGIAfw0AAAcAQQCpDQAACABYAFwNAAAHAFEAXQ0AAAYAYgBlDQAABQBiAKQNAAACAGAAMw0AAAgAVgC5DQAAAQBFAAkACgofIsMAAIEDCo4NAAAIAFkAdQ0AAAcAYgB/DQAABgBBAKkNAAAHAFgAXA0AAAYAUQBdDQAABgBiAGUNAAAFAGIApA0AAAIAYAAzDQAABwBWALkNAAABAEUACAAGCiodf0MA5gEGjg0AAAEAUQB1DQAAAQBNAH8NAAABAC8AqQ0AAAEAPABcDQAAAQBPADMNAAABAEwAAAA=.',
Th='Thawd:BAECNQAFFH8fAAITAAcKMBccAQA2AgeODQAABgBZAHUNAAAFAEYAfw0AAAUAPACpDQAABgAwAFwNAAAEACoAXQ0AAAIALQAzDQAAAwA8ABMABwowFxwBADYCB44NAAAGAFkAdQ0AAAUARgB/DQAABQA8AKkNAAAGADAAXA0AAAQAKgBdDQAAAgAtADMNAAADADwANQAECn8mAAITAAoKkB5nBgDnAgATAAoKkB5nBgDnAgAAAA==.Therapygap:BAEANQAECgQIBwABNQAECgoKKAAGALATAA==.',
Tr='Trèantdaddy:BAEANQAECgYIBgABNQAFFAEIAQAPAAAAAA==.',
Us='Usurah:BAECNQAFFH8RAAIbAAcKKhNTBgDvAQeODQAAAwAmAHUNAAACADEAfw0AAAMAVACpDQAAAwA+AFwNAAABAD8AXQ0AAAEAHwAzDQAABABUABsABwoqE1MGAO8BB44NAAADACYAdQ0AAAIAMQB/DQAAAwBUAKkNAAADAD4AXA0AAAEAPwBdDQAAAQAfADMNAAAEAFQANQAECn80AAIbAAkKISSgBwC+AwAbAAkKISSgBwC+AwAAAA==.',
Vc='Vcoren:BAEBNQAECn8iAAIdAAoKXiPJAwC2AwqODQAAAwBaAHUNAAAFAFwAfw0AAAUAXwCpDQAABQBeAFwNAAAFAF8AXQ0AAAQAXwBlDQAAAgBgAKQNAAACAFMAMw0AAAIAYgC5DQAAAQA9AB0ACgpeI8kDALYDCo4NAAADAFoAdQ0AAAUAXAB/DQAABQBfAKkNAAAFAF4AXA0AAAUAXwBdDQAABABfAGUNAAACAGAApA0AAAIAUwAzDQAAAgBiALkNAAABAD0AATUABRQHCCYACwC/HAA=.',
Ve='Velleiroth:BAEANQAECgMIBAABNQAFFAcIFwAIAKodAA==.',
Wh='Whimsiloxi:BAEANQAECgQIBAABNQAFFAcIFwAIAKodAA==.',
Za='Zatum:BAEANQAECgUIEgAAAA==.',
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
