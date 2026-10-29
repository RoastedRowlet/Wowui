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

local lookup = {'Evoker-Augmentation','Mage-Arcane','Mage-Frost','Shaman-Enhancement','Shaman-Restoration','DeathKnight-Blood','Priest-Holy','Shaman-Elemental','Druid-Balance','Druid-Restoration','Druid-Guardian','Evoker-Preservation','Evoker-Devastation','Warlock-Demonology','Priest-Shadow','Unknown-Unknown','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Warrior-Arms','Rogue-Outlaw','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Warrior-Protection','Paladin-Holy',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=53,date='2026-10-27',data={Ak='Akaeva:BAEANQAECgYIBgAAAA==.',
Al='Alcean:BAEBNQAECn8aAAIBAAgK6BT0CAD8AQiODQAABgA/AHUNAAAEAD8Afw0AAAIAHQCpDQAABABIAFwNAAADAC8AXQ0AAAEAMQBlDQAAAQAXADMNAAAFAD8AAQAICugU9AgA/AEIjg0AAAYAPwB1DQAABAA/AH8NAAACAB0AqQ0AAAQASABcDQAAAwAvAF0NAAABADEAZQ0AAAEAFwAzDQAABQA/AAAA.Algebra:BAECNQAFFH8PAAMCAAYKQBptCwBBAQaODQAABABjAHUNAAADAEkAfw0AAAIAXACpDQAABABXAFwNAAABAAgAMw0AAAEAHgACAAYKGhptCwBBAQaODQAABABjAHUNAAABAEgAfw0AAAIAXACpDQAABABXAFwNAAABAAgAMw0AAAEAHgADAAEKzRzMDQBVAAF1DQAAAgBJADUABAp/JwADAgAKClckHUMA/gIAAgAKCs8hHUMA/gIAAwADCuUiFiIA2gAAAAA=.',
Ar='Araakki:BAEBNQAECn8aAAMEAAYKQRPKGQD3AAaODQAACAAsAHUNAAAEAFEAfw0AAAMAQQCpDQAAAwArADMNAAAGADAAuQ0AAAIAGwAEAAYKQRPKGQD3AAaODQAABwAsAHUNAAADAFEAfw0AAAIAQQCpDQAAAQArADMNAAADADAAuQ0AAAEAGwAFAAYKuhPIugD1AAaODQAAAQAcAHUNAAABADAAfw0AAAEAHgCpDQAAAgA6ADMNAAADAFcAuQ0AAAEAMwAAAA==.Aradell:BAEBNQAECn83AAIGAAkKqRfjMABNAgmODQAACQBSAHUNAAAIAEQAfw0AAAgARwCpDQAACABDAFwNAAAFAEkAXQ0AAAUAOgBlDQAABAA6AKQNAAABAA8AMw0AAAcAUQAGAAkKqRfjMABNAgmODQAACQBSAHUNAAAIAEQAfw0AAAgARwCpDQAACABDAFwNAAAFAEkAXQ0AAAUAOgBlDQAABAA6AKQNAAABAA8AMw0AAAcAUQAAAA==.Arceni:BAEANQAECggICAABNQAECgkJNwAGAKkXAA==.Ariizi:BAEANQAECgYIDwAAAA==.Artam:BAEANQADCggICQABNQAFFAgIKAAHALobAA==.Arteron:BAEANQADCggICAABNQAFFAcIIwAIAPYjAA==.',
Au='Augstrasza:BAEANQAECgMIAwAAAA==.Aukanawe:BAECNQAFFH8XAAIJAAcKqh3lAwB6AgeODQAABgBhAHUNAAAEADIAfw0AAAIATACpDQAABABfAFwNAAACAEMAXQ0AAAEARAAzDQAABABBAAkABwqqHeUDAHoCB44NAAAGAGEAdQ0AAAQAMgB/DQAAAgBMAKkNAAAEAF8AXA0AAAIAQwBdDQAAAQBEADMNAAAEAEEANQAECn9RAAQJAAoKyiVoBgCiAwAJAAoKyiVoBgCiAwAKAAQKoA/mSwDfAAALAAEK3iEiPwBjAAAAAA==.',
Av='Averelle:BAEANQAECgcIDQAAAA==.',
Ay='Ayoade:BAECNQAFFH8mAAIMAAcKvxxHAwBhAgeODQAABwA3AHUNAAAGAEgAfw0AAAYAWACpDQAABwBXAFwNAAAEAD8AXQ0AAAIAMgAzDQAABgBgAAwABwq/HEcDAGECB44NAAAHADcAdQ0AAAYASAB/DQAABgBYAKkNAAAHAFcAXA0AAAQAPwBdDQAAAgAyADMNAAAGAGAANQAECn8+AAMMAAoK4CQyAwCGAwAMAAoK4CQyAwCGAwANAAEKAAAHIgAAAAAAAA==.',
Az='Azzurel:BAEBNQAECn85AAIOAAoKqRZoNgDRAQqODQAABwAuAHUNAAAHAEUAfw0AAAYAJwCpDQAABwA1AFwNAAAHAE8AXQ0AAAYAMABlDQAABQBIAKQNAAADAEAAMw0AAAgAQwC5DQAAAQAdAA4ACgqpFmg2ANEBCo4NAAAHAC4AdQ0AAAcARQB/DQAABgAnAKkNAAAHADUAXA0AAAcATwBdDQAABgAwAGUNAAAFAEgApA0AAAMAQAAzDQAACABDALkNAAABAB0AAAA=.',
Ba='Babaghanouj:BAEBNQAECn8gAAMPAAcKdBTFLgCuAQeODQAABgBBAHUNAAAEACsAfw0AAAQAKACpDQAABQA3AFwNAAAFADgAXQ0AAAMAKAAzDQAABQAuAA8ABwp0FMUuAK4BB44NAAAFAEEAdQ0AAAQAKwB/DQAABAAoAKkNAAAFADcAXA0AAAIAOABdDQAAAgAoADMNAAADAC4ABwAEClogOKIALwEEjg0AAAEASQBcDQAAAwBUAF0NAAABAFsAMw0AAAIAUQAAAA==.Babycino:BAEANQAECgMIBQABNQAECgcIDQAQAAAAAA==.Bayati:BAEBNQAECn9CAAIRAAoKxCRLAgCUAwqODQAACgBgAHUNAAAJAFsAfw0AAAkAYgCpDQAACgBdAFwNAAAHAFwAXQ0AAAIAXQBlDQAABgBhAKQNAAADAF0AMw0AAAYAXwC5DQAABABeABEACgrEJEsCAJQDCo4NAAAKAGAAdQ0AAAkAWwB/DQAACQBiAKkNAAAKAF0AXA0AAAcAXABdDQAAAgBdAGUNAAAGAGEApA0AAAMAXQAzDQAABgBfALkNAAAEAF4AAAA=.',
Be='Benghi:BAECNQAFFH8QAAMSAAYKhg5iDQDeAAaODQAABQArAHUNAAADACYAfw0AAAIANACpDQAAAQAbAFwNAAABACYAMw0AAAQAPAATAAMK8grxDwDsAAN1DQAAAQAcAKkNAAABABsAMw0AAAEAPAASAAUKzw9iDQDeAAWODQAABQArAHUNAAACACYAfw0AAAIANABcDQAAAQAmADMNAAADABgANQAECn8sAAMTAAoKGx8rNQAFAgATAAcKxhwrNQAFAgASAAcKJBk8JgCVAQAAAA==.Bestcase:BAECNQAFFH8TAAIUAAcK2BI2BAAJAgeODQAABQBIAHUNAAAEABIAfw0AAAMABQCpDQAABAA+AFwNAAABAE4AXQ0AAAEACAAzDQAAAQAqABQABwrYEjYEAAkCB44NAAAFAEgAdQ0AAAQAEgB/DQAAAwAFAKkNAAAEAD4AXA0AAAEATgBdDQAAAQAIADMNAAABACoANQAECn83AAQUAAoKxCNzDAARAwAUAAoKxCNzDAARAwAVAAYKvQx2CwAVAQAWAAEKPQMHVgAdAAAAAA==.',
Br='Brigbala:BAEANQAECgUIBgAAAA==.',
Bu='Burnassus:BAEANQADCggIHwABNQAECgoKLgAHAKYUAA==.',
Ch='Chunghús:BAEANQAECgQICAABNQAFFAEIAQAQAAAAAA==.',
Co='Coggettle:BAEANQAECggIDQAAAA==.',
Cr='Crustage:BAEBNQAECn8YAAICAAgKcAUKhgA2AQiODQAABgAIAHUNAAAFABIAfw0AAAMAHACpDQAAAwASAFwNAAADABEAXQ0AAAIADwBlDQAAAQANAKQNAAABAAYAAgAICnAFCoYANgEIjg0AAAYACAB1DQAABQASAH8NAAADABwAqQ0AAAMAEgBcDQAAAwARAF0NAAACAA8AZQ0AAAEADQCkDQAAAQAGAAAA.',
Dc='Dcae:BAEANQADCgEIAQABNQAECgkJIwACAN0hAA==.',
Du='Dubsy:BAEBNQAECn81AAIFAAoKxSXKAgC7AwqODQAABQBbAHUNAAAGAGEAfw0AAAQAYgCpDQAABgBiAFwNAAAEAGIAXQ0AAAcAYgBlDQAABwBjAKQNAAAIAGEAMw0AAAMAXQC5DQAAAwBfAAUACgrFJcoCALsDCo4NAAAFAFsAdQ0AAAYAYQB/DQAABABiAKkNAAAGAGIAXA0AAAQAYgBdDQAABwBiAGUNAAAHAGMApA0AAAgAYQAzDQAAAwBdALkNAAADAF8AATUABRQHCCYADAC/HAA=.',
Eh='Ehanee:BAEBNQAECn8lAAIIAAkKQyHZEQBhAwmODQAABwBdAHUNAAAGAGAAfw0AAAUAYQCpDQAABgBWAFwNAAAEAGAAXQ0AAAIASgBlDQAAAwBQAKQNAAABAEMAMw0AAAMAWwAIAAkKQyHZEQBhAwmODQAABwBdAHUNAAAGAGAAfw0AAAUAYQCpDQAABgBWAFwNAAAEAGAAXQ0AAAIASgBlDQAAAwBQAKQNAAABAEMAMw0AAAMAWwAAAA==.',
Fa='Fappimeal:BAEANQAECgUICQAAAA==.Fappisham:BAEBNQAECn8hAAIIAAkK6h4VHwARAwmODQAABgBcAHUNAAADAE0Afw0AAAMAVACpDQAABQBVAFwNAAADAF8AXQ0AAAIASwBlDQAABABDAKQNAAADADsAMw0AAAQATQAIAAkK6h4VHwARAwmODQAABgBcAHUNAAADAE0Afw0AAAMAVACpDQAABQBVAFwNAAADAF8AXQ0AAAIASwBlDQAABABDAKQNAAADADsAMw0AAAQATQABNQAECgUICQAQAAAAAA==.',
Fs='Fshi:BAECNQAFFH8LAAMRAAcKsBOrAAAHAgeODQAAAQBEAHUNAAACACgAfw0AAAEAEgCpDQAAAQBSAFwNAAABACMAZQ0AAAEAGQAzDQAABAAvABEABgooFqsAAAcCBo4NAAABAEQAdQ0AAAIAKAB/DQAAAQASAKkNAAABAFIAXA0AAAEAIwAzDQAAAgAvAAkAAgrQCWUXAFMAAmUNAAABABkAMw0AAAIAJAA1AAQKf1AAAxEACgq/JXUAAPUDABEACgokI3UAAPUDAAkABwqsHdJCAOoBAAAA.',
Fu='Funkey:BAEANQAECgIIAgAAAA==.',
Gr='Greatanubis:BAEBNQAECn8VAAMJAAkKXw32OwAVAgmODQAAAgA6AHUNAAADADwAfw0AAAMANQCpDQAAAwAuAFwNAAACAAUAXQ0AAAIAGgBlDQAABAAXAKQNAAABABIAMw0AAAEAUgAJAAkKXw32OwAVAgmODQAAAgA6AHUNAAADADwAfw0AAAMANQCpDQAAAwAuAFwNAAABAAUAXQ0AAAIAGgBlDQAABAAXAKQNAAABABIAMw0AAAEAUgAKAAEKvgELhAAZAAFcDQAAAQAEAAAA.',
Ha='Halts:BAEANQAECgYIDAABNQAFFAUICAAFADkNAA==.',
Im='Imei:BAEANQAECgEIAQABNQAFFAYIGQAXAIAiAA==.',
Ja='Jail:BAEBNQAECn8jAAICAAkK3SFnHQBiAwmODQAABwBXAHUNAAAEAGMAfw0AAAMAYgCpDQAABABgAFwNAAADAFcAXQ0AAAMAXABlDQAABABMAKQNAAADAEMAMw0AAAQAXwACAAkK3SFnHQBiAwmODQAABwBXAHUNAAAEAGMAfw0AAAMAYgCpDQAABABgAFwNAAADAFcAXQ0AAAMAXABlDQAABABMAKQNAAADAEMAMw0AAAQAXwAAAA==.Jarco:BAEANQAECgQIBAABNQAFFAYIDQAYABwaAA==.',
Je='Jesyrosa:BAEANQAECgUIBQABNQAECgoKMAAMAOMaAA==.',
Ka='Kanavi:BAECNQAFFH8ZAAIXAAYKgCKEDADpAQaODQAABwBhAHUNAAAEAGAAfw0AAAIARgCpDQAABQBGAFwNAAABAFkAMw0AAAYAWwAXAAYKgCKEDADpAQaODQAABwBhAHUNAAAEAGAAfw0AAAIARgCpDQAABQBGAFwNAAABAFkAMw0AAAYAWwA1AAQKfzwAAhcACgq8JdgDAFwDABcACgq8JdgDAFwDAAAA.Kantai:BAEANQADCgYICQABNQAFFAYIGQAXAIAiAA==.',
Kn='Knackered:BAEBNQAECn8iAAIZAAgKYhumEgCXAQiODQAABgBLAHUNAAAFAEQAfw0AAAUAUACpDQAABQA6AFwNAAAEAEgAXQ0AAAMAUgBlDQAAAQA/ADMNAAAFAEoAGQAICmIbphIAlwEIjg0AAAYASwB1DQAABQBEAH8NAAAFAFAAqQ0AAAUAOgBcDQAABABIAF0NAAADAFIAZQ0AAAEAPwAzDQAABQBKAAE1AAEKAggCABAAAAAA.',
Ko='Korikora:BAEANQADCgUICAABNQAECgYIGgAEAEETAA==.',
Kr='Kregazi:BAEBNQAECn8xAAIGAAoKaCHhEQAdAwqODQAACABRAHUNAAAGAF0Afw0AAAUATACpDQAABgBUAFwNAAAEAFUAXQ0AAAQAWwBlDQAABgBHAKQNAAACAF4AMw0AAAcAWgC5DQAAAQBQAAYACgpoIeERAB0DCo4NAAAIAFEAdQ0AAAYAXQB/DQAABQBMAKkNAAAGAFQAXA0AAAQAVQBdDQAABABbAGUNAAAGAEcApA0AAAIAXgAzDQAABwBaALkNAAABAFAAAAA=.',
Ku='Kujali:BAEANQAECgYIBQABNQAECgoKQgARAMQkAA==.Kuroi:BAEANQAECgcIBwABNQAFFAYIGQAXAIAiAA==.',
Ky='Kyssarra:BAECNQAFFH8hAAQaAAgKcx4pAACVAQiODQAABgBjAHUNAAAFAFgAfw0AAAUAVwCpDQAABQBjAFwNAAAFAE4AXQ0AAAEATABlDQAAAQAZADMNAAAFAF4AGgAGCm4hKQAAlQEGjg0AAAEAVQB1DQAABQBYAH8NAAABAFcAqQ0AAAUAYwBcDQAAAQBOAF0NAAABAEwADgADCtYikhoAIQEDjg0AAAUAYwB/DQAABABSAFwNAAADAE4AGwADCnwPOAMAxwADXA0AAAEANQBlDQAAAQAZADMNAAAFAF4ANQAECn+JAAQaAAoKbCYXAAALBAAaAAkKxCYXAAALBAAbAAUKgiZUCAALAgAOAAgK9yCDMQDnAQAAAA==.',
Le='Lexielulu:BAEANQABCgIIBAABNQAECgUIBgAQAAAAAA==.',
Lo='Lobotomight:BAEANQAECgcIDQABNQAECgIIAgAQAAAAAA==.',
Lu='Lunaë:BAECNQAFFH8GAAMHAAUK0gxbHQCOAAWODQAAAQA3AHUNAAABAAUAfw0AAAEAFgCpDQAAAQAsADMNAAACACQABwACCukRWx0AjgACjg0AAAEANwAzDQAAAgAkAA8AAwqbBMULAIAAA3UNAAABAAQAfw0AAAEAEACpDQAAAQASADUABAp/SAADBwAKCucctRIANQMABwAKCucctRIANQMADwAFCjgL/h8ACAEAAAA=.Lunäe:BAEBNQAECn8tAAIHAAoKVx6YEADqAgqODQAACQBWAHUNAAAGAFEAfw0AAAkAVQCpDQAABABBAFwNAAADAFMAXQ0AAAQAPQBlDQAABABGAKQNAAACADkAMw0AAAMAYAC5DQAAAQBYAAcACgpXHpgQAOoCCo4NAAAJAFYAdQ0AAAYAUQB/DQAACQBVAKkNAAAEAEEAXA0AAAMAUwBdDQAABAA9AGUNAAAEAEYApA0AAAIAOQAzDQAAAwBgALkNAAABAFgAATUABRQFCAYABwDSDAA=.',
['Lü']='Lünae:BAEANQAECggIBwABNQAFFAUIBgAHANIMAA==.',
Ma='Maildaddy:BAEANQAFFAEIAQAAAA==.Maxxy:BAEANQAECgcIDwAAAA==.',
Mc='Mckellen:BAEANQAECgcIEwABNQAFFAcIJgAMAL8cAA==.',
Me='Merarite:BAEBNQAECn88AAIGAAoK9RXWLgBYAgqODQAACQA8AHUNAAAIAEsAfw0AAAcANACpDQAACABCAFwNAAAHAEYAXQ0AAAYAJABlDQAABgBJAKQNAAADACkAMw0AAAQAPQC5DQAAAgAbAAYACgr1FdYuAFgCCo4NAAAJADwAdQ0AAAgASwB/DQAABwA0AKkNAAAIAEIAXA0AAAcARgBdDQAABgAkAGUNAAAGAEkApA0AAAMAKQAzDQAABAA9ALkNAAACABsAAAA=.',
['Mý']='Mýthra:BAEANQAECggICAAAAA==.',
Na='Nadasa:BAEBNQAECn96AAIcAAoK1yIqDQAMAwqODQAAFwBfAHUNAAATAGAAfw0AABIAYQCpDQAAEgBYAFwNAAALAGEAXQ0AAAUAVQBlDQAACwBaAKQNAAAEAFoAMw0AAAsAYQC5DQAAAgBDABwACgrXIioNAAwDCo4NAAAXAF8AdQ0AABMAYAB/DQAAEgBhAKkNAAASAFgAXA0AAAsAYQBdDQAABQBVAGUNAAALAFoApA0AAAQAWgAzDQAACwBhALkNAAACAEMAAAA=.',
Ni='Nixaanu:BAEANQADCgYICQAAAA==.',
No='Nomadicbear:BAEANQABCgQICAABNQABCgYICAAQAAAAAA==.Nomadichunt:BAEANQABCgYICAAAAA==.Nomadicmonk:BAEANQABCgQIBAABNQABCgYICAAQAAAAAA==.',
Ny='Nyriaa:BAEANQADCggICAAAAA==.',
Pa='Palashin:BAEANQAECgQIBQABNQAFFAUICAAFADkNAA==.',
Pe='Personnelkid:BAEANQADCggICAABNQAECgoKLgAHAKYUAA==.',
Ph='Phiirshark:BAEBNQAECn8zAAIdAAoKWSJOBQAiAwqODQAACABbAHUNAAAGAFkAfw0AAAYAXgCpDQAABwBeAFwNAAAFAFsAXQ0AAAQAVgBlDQAABQBVAKQNAAACAFsAMw0AAAYAXwC5DQAAAgBJAB0ACgpZIk4FACIDCo4NAAAIAFsAdQ0AAAYAWQB/DQAABgBeAKkNAAAHAF4AXA0AAAUAWwBdDQAABABWAGUNAAAFAFUApA0AAAIAWwAzDQAABgBfALkNAAACAEkAAAA=.',
Po='Poortal:BAEANQAECgEIAQABNQAECgIIAgAQAAAAAA==.Potatogogue:BAECNQAFFH8NAAMIAAYK3RHJFAArAQaODQAABAAuAHUNAAACAA4Afw0AAAEAMgCpDQAAAwAfAFwNAAACAFoAMw0AAAEAGAAIAAQKFAzJFAArAQSODQAABAAuAHUNAAACAA4AqQ0AAAMAHwAzDQAAAQAYAAUAAgpaFEQeAKEAAn8NAAABAEsAXA0AAAIAHAA1AAQKfyoAAwgACgrcIYglAO4CAAgACgrcIYglAO4CAAUAAgpQH0bxAIgAAAE1AAUUAQgBABAAAAAA.Potatoroguee:BAEANQAECgYIBwABNQAFFAEIAQAQAAAAAA==.',
Ro='Roogies:BAECNQAFFH8PAAMTAAQKwyWHAgAPAQSODQAABgBhAHUNAAADAGEAfw0AAAIAUACpDQAABABfABMABArDJYcCAA8BBI4NAAAGAGEAdQ0AAAMAYQB/DQAAAQBQAKkNAAAEAF8AEgABCgAA1BwAAAABfw0AAAEAHgA1AAQKf04AAxMACgqZJJwDAJ4DABMACgplJJwDAJ4DABIABQptHo09AGwBAAAA.',
Se='Senzarial:BAEANQAECgIIAQABNQAFFAcIFwAJAKodAA==.Serynytee:BAEBNQAECn8XAAQaAAkKXxpLJQBJAQmODQAABABZAHUNAAACAD4Afw0AAAMAOACpDQAABABQAFwNAAADAFcAXQ0AAAMARQBlDQAAAQAkADMNAAACACwAuQ0AAAEALAAaAAQKmx1LJQBJAQSODQAAAgBZAHUNAAACAD4AqQ0AAAMAUABdDQAAAgBFAA4ABgr2Exd6AAMBBo4NAAACACwAfw0AAAIAKACpDQAAAQA8AF0NAAABAD4AZQ0AAAEAJAAzDQAAAQAiABsABArtGWkbAKYABH8NAAABADgAXA0AAAMAVwAzDQAAAQAsALkNAAABACwAAAA=.',
Sh='Shinseer:BAECNQAFFH8IAAIFAAUKOQ0lDwBdAQWODQAAAQAvAHUNAAABAAsAfw0AAAIAIACpDQAAAQA5ADMNAAADABQABQAFCjkNJQ8AXQEFjg0AAAEALwB1DQAAAQALAH8NAAACACAAqQ0AAAEAOQAzDQAAAwAUADUABAp/LgACBQAJCmEfxRIAMwMABQAJCmEfxRIAMwMAAAA=.Shinthyr:BAEBNQAECn8fAAIHAAgKUBeNRQBWAgiODQAACgBfAHUNAAAEAEQAfw0AAAQASwCpDQAABABTAFwNAAABACcAZQ0AAAEACQCkDQAAAgANADMNAAAFAF0ABwAIClAXjUUAVgIIjg0AAAoAXwB1DQAABABEAH8NAAAEAEsAqQ0AAAQAUwBcDQAAAQAnAGUNAAABAAkApA0AAAIADQAzDQAABQBdAAE1AAUUBQgIAAUAOQ0A.',
St='Starryangel:BAEANQAECgEIAQABNQAFFAYIHAAcADYUAA==.Stormbroken:BAEANQADCgUIBgABNQAECgoKLgAHAKYUAA==.',
Su='Sunwelljuice:BAEANQADCggIHwABNQAECgoKLgAHAKYUAA==.',
Sy='Syldrasi:BAEANQADCgQICAABNQAFFAQIDwATAMMlAA==.',
Ta='Tahune:BAEBNQAECn9GAAQKAAoKHyIIBABZAwqODQAACgBZAHUNAAAJAGIAfw0AAAgAQQCpDQAACQBYAFwNAAAIAFEAXQ0AAAcAYgBlDQAABgBiAKQNAAADAGAAMw0AAAgAVgC5DQAAAgBFAAoACgofIggEAFkDCo4NAAAIAFkAdQ0AAAcAYgB/DQAABgBBAKkNAAAHAFgAXA0AAAYAUQBdDQAABgBiAGUNAAAGAGIApA0AAAIAYAAzDQAABwBWALkNAAABAEUACQAHCrgdf0MA5gEHjg0AAAEAUQB1DQAAAQBNAH8NAAABAC8AqQ0AAAEAPABcDQAAAQBPAKQNAAABAFEAMw0AAAEATAALAAcKCBj4DwCuAQeODQAAAQA8AHUNAAABADgAfw0AAAEAOwCpDQAAAQBBAFwNAAABAEIAXQ0AAAEAMgC5DQAAAQBGAAAA.',
Th='Thawd:BAECNQAFFH8fAAIVAAcKMBccAQA2AgeODQAABgBZAHUNAAAFAEYAfw0AAAUAPACpDQAABgAwAFwNAAAEACoAXQ0AAAIALQAzDQAAAwA8ABUABwowFxwBADYCB44NAAAGAFkAdQ0AAAUARgB/DQAABQA8AKkNAAAGADAAXA0AAAQAKgBdDQAAAgAtADMNAAADADwANQAECn8vAAMVAAoKkB5nBgDnAgAVAAoKkB5nBgDnAgAUAAkKPRDcDwDqAQAAAA==.Therapygap:BAEANQAECgUIDAABNQAECgoKLgAHAKYUAA==.',
Tr='Trèantdaddy:BAEANQAECgYIBgABNQAFFAEIAQAQAAAAAA==.',
Us='Usurah:BAECNQAFFH8RAAIcAAcKKhNTBgDvAQeODQAAAwAmAHUNAAACADEAfw0AAAMAVACpDQAAAwA+AFwNAAABAD8AXQ0AAAEAHwAzDQAABABUABwABwoqE1MGAO8BB44NAAADACYAdQ0AAAIAMQB/DQAAAwBUAKkNAAADAD4AXA0AAAEAPwBdDQAAAQAfADMNAAAEAFQANQAECn89AAIcAAoKgySgBwC+AwAcAAoKgySgBwC+AwAAAA==.',
Vc='Vcoren:BAEBNQAECn8iAAIeAAoKXiPJAwC2AwqODQAAAwBaAHUNAAAFAFwAfw0AAAUAXwCpDQAABQBeAFwNAAAFAF8AXQ0AAAQAXwBlDQAAAgBgAKQNAAACAFMAMw0AAAIAYgC5DQAAAQA9AB4ACgpeI8kDALYDCo4NAAADAFoAdQ0AAAUAXAB/DQAABQBfAKkNAAAFAF4AXA0AAAUAXwBdDQAABABfAGUNAAACAGAApA0AAAIAUwAzDQAAAgBiALkNAAABAD0AATUABRQHCCYADAC/HAA=.',
Ve='Velleiroth:BAEANQAECgcICgABNQAFFAcIFwAJAKodAA==.',
Wh='Whimsiloxi:BAEANQAECgYIBQABNQAFFAcIFwAJAKodAA==.',
Za='Zatum:BAEBNQAECn8fAAQLAAgKDx8cDAD1AQiODQAABgBSAHUNAAAFAFcAfw0AAAQAYwCpDQAABABJAFwNAAAEAFoAXQ0AAAEARQAzDQAABgBVALkNAAABAEgACwAICg8fHAwA9QEIjg0AAAQAUgB1DQAABABXAH8NAAAEAGMAqQ0AAAQASQBcDQAABABaAF0NAAABAEUAMw0AAAQAVQC5DQAAAQBIAAkAAgpjGu+UAIQAAo4NAAABAEMAMw0AAAIANAAKAAIKRhKFZgBrAAKODQAAAQAtAHUNAAABAC8AAAA=.',
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
