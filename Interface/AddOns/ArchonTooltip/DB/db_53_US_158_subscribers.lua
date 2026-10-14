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

local lookup = {'Druid-Feral','Evoker-Augmentation','Mage-Arcane','Mage-Frost','DeathKnight-Blood','Priest-Holy','Shaman-Elemental','Druid-Balance','Druid-Restoration','Evoker-Preservation','Warlock-Demonology','Priest-Shadow','Rogue-Assassination','Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Warrior-Arms','Rogue-Outlaw','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Paladin-Holy',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=53,date='2026-10-13',data={Ae='Aesinth:BAEANQAECgQIAgABNQAECgkJKAABAPcbAA==.',
Ak='Akaeva:BAEANQAECgYIBgAAAA==.',
Al='Alcean:BAEBNQAECn8aAAICAAgK6BToCAD8AQiODQAABgA/AHUNAAAEAD8Afw0AAAIAHQCpDQAABABIAFwNAAADAC8AXQ0AAAEAMQBlDQAAAQAXADMNAAAFAD8AAgAICugU6AgA/AEIjg0AAAYAPwB1DQAABAA/AH8NAAACAB0AqQ0AAAQASABcDQAAAwAvAF0NAAABADEAZQ0AAAEAFwAzDQAABQA/AAAA.Algebra:BAECNQAFFH8KAAMDAAUK9SE+IgBuAQWODQAAAwBjAHUNAAACAEkAfw0AAAEAOwCpDQAAAwBXADMNAAABAB4AAwAECogkPiIAbgEEjg0AAAMAYwB/DQAAAQA7AKkNAAADAFcAMw0AAAEAHgAEAAEKzRxuDQBWAAF1DQAAAgBJADUABAp/HwADAwAJCuAiEEIAAAMAAwAJCvsfEEIAAAMABAADCuUimiEA2gAAAAA=.',
Ar='Araakki:BAEANQAECgQIDQAAAA==.Aradell:BAEBNQAECn83AAIFAAkKqRdYMABOAgmODQAACQBSAHUNAAAIAEQAfw0AAAgARwCpDQAACABDAFwNAAAFAEkAXQ0AAAUAOgBlDQAABAA6AKQNAAABAA8AMw0AAAcAUQAFAAkKqRdYMABOAgmODQAACQBSAHUNAAAIAEQAfw0AAAgARwCpDQAACABDAFwNAAAFAEkAXQ0AAAUAOgBlDQAABAA6AKQNAAABAA8AMw0AAAcAUQAAAA==.Arceni:BAEANQAECggICAABNQAECgkJNwAFAKkXAA==.Ariizi:BAEANQAECgQIDAAAAA==.Artam:BAEANQADCggICQABNQAFFAcIIgAGAEobAA==.Arteron:BAEANQADCggICAABNQAFFAcIHQAHAJ0iAA==.',
Au='Augstrasza:BAEANQAECgMIAwAAAA==.Aukanawe:BAECNQAFFH8XAAIIAAcKqh22AwB7AgeODQAABgBhAHUNAAAEADIAfw0AAAIATACpDQAABABfAFwNAAACAEMAXQ0AAAEARAAzDQAABABBAAgABwqqHbYDAHsCB44NAAAGAGEAdQ0AAAQAMgB/DQAAAgBMAKkNAAAEAF8AXA0AAAIAQwBdDQAAAQBEADMNAAAEAEEANQAECn9GAAMIAAkK7yVFBgCiAwAIAAkK7yVFBgCiAwAJAAQKoA8JSwDeAAAAAA==.',
Av='Averelle:BAEANQAECgYIBgAAAA==.',
Ay='Ayoade:BAECNQAFFH8mAAIKAAcKvxwiAwBhAgeODQAABwA3AHUNAAAGAEgAfw0AAAYAWACpDQAABwBXAFwNAAAEAD8AXQ0AAAIAMgAzDQAABgBgAAoABwq/HCIDAGECB44NAAAHADcAdQ0AAAYASAB/DQAABgBYAKkNAAAHAFcAXA0AAAQAPwBdDQAAAgAyADMNAAAGAGAANQAECn8tAAIKAAkKASQvAwCGAwAKAAkKASQvAwCGAwAAAA==.',
Az='Azzurel:BAEBNQAECn8wAAILAAkK9BUETABsAgmODQAABgAuAHUNAAAGAEUAfw0AAAUAJwCpDQAABgAqAFwNAAAGAEsAXQ0AAAUAMABlDQAABAAuAKQNAAADAEAAMw0AAAcAQwALAAkK9BUETABsAgmODQAABgAuAHUNAAAGAEUAfw0AAAUAJwCpDQAABgAqAFwNAAAGAEsAXQ0AAAUAMABlDQAABAAuAKQNAAADAEAAMw0AAAcAQwAAAA==.',
Ba='Babaghanouj:BAEBNQAECn8gAAMMAAcKdBROLgCuAQeODQAABgBBAHUNAAAEACsAfw0AAAQAKACpDQAABQA3AFwNAAAFADgAXQ0AAAMAKAAzDQAABQAuAAwABwp0FE4uAK4BB44NAAAFAEEAdQ0AAAQAKwB/DQAABAAoAKkNAAAFADcAXA0AAAIAOABdDQAAAgAoADMNAAADAC4ABgAEClogX6AALwEEjg0AAAEASQBcDQAAAwBUAF0NAAABAFsAMw0AAAIAUQAAAA==.Bayati:BAEBNQAECn8qAAIBAAkKkCJCAgCUAwmODQAABwBgAHUNAAAGAFoAfw0AAAUAXQCpDQAABgBcAFwNAAAEAFwAXQ0AAAIAXQBlDQAABQBSAKQNAAACAEcAMw0AAAUAXwABAAkKkCJCAgCUAwmODQAABwBgAHUNAAAGAFoAfw0AAAUAXQCpDQAABgBcAFwNAAAEAFwAXQ0AAAIAXQBlDQAABQBSAKQNAAACAEcAMw0AAAUAXwAAAA==.',
Be='Benghi:BAECNQAFFH8LAAMNAAUKBQ2JDwDsAAWODQAABAArAHUNAAACABwAfw0AAAEADwCpDQAAAQAbADMNAAADADwADgAECoQJUgoALwEEjg0AAAQAKwB1DQAAAQAEAH8NAAABAA8AMw0AAAIAGAANAAMK8gqJDwDsAAN1DQAAAQAcAKkNAAABABsAMw0AAAEAPAA1AAQKfygAAw0ACQp1Hik0AAUCAA0ABwrGHCk0AAUCAA4ABgqGFsslAJUBAAAA.Bestcase:BAECNQAFFH8TAAIPAAcK2BIMBAAJAgeODQAABQBIAHUNAAAEABIAfw0AAAMABQCpDQAABAA+AFwNAAABAE4AXQ0AAAEACAAzDQAAAQAqAA8ABwrYEgwEAAkCB44NAAAFAEgAdQ0AAAQAEgB/DQAAAwAFAKkNAAAEAD4AXA0AAAEATgBdDQAAAQAIADMNAAABACoANQAECn8rAAQPAAkK4CM/DAARAwAPAAkK4CM/DAARAwAQAAEKAABVNQAhAAARAAEKPQPUVAAdAAAAAA==.',
Bi='Birchmire:BAEANQAECgUIBQABNQAECgkJKAABAPcbAA==.',
Br='Brigbala:BAEANQAECgQIBQAAAA==.',
Bu='Burnassus:BAEANQADCggICwABNQAECgkJJwAGAOAUAA==.',
Ch='Chunghús:BAEANQAECgQICAABNQAFFAEIAQASAAAAAA==.',
Co='Coggettle:BAEANQAECgYIBgABNQAECggIIQATADwhAA==.',
Cr='Crustage:BAEANQAECgYIDwAAAA==.',
Dc='Dcae:BAEANQADCgEIAQABNQAECgkJIgADAN0hAA==.',
Du='Dumblefrost:BAEBNQAECn8XAAIDAAgK4gRnFgFjAQiODQAABAAEAHUNAAADABYAfw0AAAMABACpDQAAAwAMAFwNAAADAAkAXQ0AAAMABwBlDQAAAgASADMNAAACAAUAAwAICuIEZxYBYwEIjg0AAAQABAB1DQAAAwAWAH8NAAADAAQAqQ0AAAMADABcDQAAAwAJAF0NAAADAAcAZQ0AAAIAEgAzDQAAAgAFAAAA.',
Eh='Ehanee:BAEBNQAECn8dAAIHAAkKICGjEQBhAwmODQAABQBaAHUNAAAEAGAAfw0AAAMAYQCpDQAABABWAFwNAAAEAGAAXQ0AAAIASgBlDQAAAwBQAKQNAAABAEMAMw0AAAMAWwAHAAkKICGjEQBhAwmODQAABQBaAHUNAAAEAGAAfw0AAAMAYQCpDQAABABWAFwNAAAEAGAAXQ0AAAIASgBlDQAAAwBQAKQNAAABAEMAMw0AAAMAWwAAAA==.',
Fa='Fappimeal:BAEANQAECgUICQAAAA==.Fappisham:BAEBNQAECn8hAAIHAAkK6h6sHgARAwmODQAABgBcAHUNAAADAE0Afw0AAAMAVACpDQAABQBVAFwNAAADAF8AXQ0AAAIASwBlDQAABABDAKQNAAADADsAMw0AAAQATQAHAAkK6h6sHgARAwmODQAABgBcAHUNAAADAE0Afw0AAAMAVACpDQAABQBVAFwNAAADAF8AXQ0AAAIASwBlDQAABABDAKQNAAADADsAMw0AAAQATQABNQAECgUICQASAAAAAA==.',
Fs='Fshi:BAECNQAFFH8KAAMBAAYKKBapAAAHAgaODQAAAQBEAHUNAAACACgAfw0AAAEAEgCpDQAAAQBSAFwNAAABACMAMw0AAAQALwABAAYKKBapAAAHAgaODQAAAQBEAHUNAAACACgAfw0AAAEAEgCpDQAAAQBSAFwNAAABACMAMw0AAAIALwAIAAEKAACuKAA9AAEzDQAAAgAkADUABAp/TQADAQAJCqwmbwAA9gMAAQAJCqwmbwAA9gMACAAGClodO0IA6gEAAAA=.',
Gr='Greatanubis:BAEBNQAECn8VAAMIAAkKXw1KOwAVAgmODQAAAgA6AHUNAAADADwAfw0AAAMANQCpDQAAAwAuAFwNAAACAAUAXQ0AAAIAGgBlDQAABAAXAKQNAAABABIAMw0AAAEAUgAIAAkKXw1KOwAVAgmODQAAAgA6AHUNAAADADwAfw0AAAMANQCpDQAAAwAuAFwNAAABAAUAXQ0AAAIAGgBlDQAABAAXAKQNAAABABIAMw0AAAEAUgAJAAEKvgHcgQAZAAFcDQAAAQAEAAAA.',
Ha='Halts:BAEANQAECgUICgABNQAFFAUIBwAUADkNAA==.',
Il='Ilnarya:BAEANQADCgcICwABNQADCggIEwASAAAAAA==.',
Im='Imei:BAEANQAECgEIAQABNQAFFAUIFwAVAGYiAA==.',
Ja='Jail:BAEBNQAECn8iAAIDAAkK3SHVHABkAwmODQAABwBXAHUNAAAEAGMAfw0AAAMAYgCpDQAABABgAFwNAAADAFcAXQ0AAAMAXABlDQAABABMAKQNAAACAEMAMw0AAAQAXwADAAkK3SHVHABkAwmODQAABwBXAHUNAAAEAGMAfw0AAAMAYgCpDQAABABgAFwNAAADAFcAXQ0AAAMAXABlDQAABABMAKQNAAACAEMAMw0AAAQAXwAAAA==.Jarco:BAEANQAECgQIBAABNQAFFAYIDAAWABwaAA==.',
Je='Jesyrosa:BAEANQAECgUIBQABNQAECgkJJQAKADwZAA==.',
Jl='Jlycett:BAEBNQAECn8kAAIUAAkKsyW4AgC7AwmODQAAAwBbAHUNAAAEAGEAfw0AAAMAYgCpDQAABQBiAFwNAAADAGIAXQ0AAAYAYgBlDQAABQBjAKQNAAAFAF4AMw0AAAIAXQAUAAkKsyW4AgC7AwmODQAAAwBbAHUNAAAEAGEAfw0AAAMAYgCpDQAABQBiAFwNAAADAGIAXQ0AAAYAYgBlDQAABQBjAKQNAAAFAF4AMw0AAAIAXQABNQAFFAcIJgAKAL8cAA==.',
Ka='Kanavi:BAECNQAFFH8XAAIVAAUKZiIdDADqAQWODQAABwBhAHUNAAAEAGAAfw0AAAIARgCpDQAABQBGADMNAAAFAFQAFQAFCmYiHQwA6gEFjg0AAAcAYQB1DQAABABgAH8NAAACAEYAqQ0AAAUARgAzDQAABQBUADUABAp/LQACFQAJCmUkOQ8AggMAFQAJCmUkOQ8AggMAAAA=.Kantai:BAEANQADCgYICQABNQAFFAUIFwAVAGYiAA==.',
Kn='Knackered:BAEBNQAECn8bAAIXAAcK7BuPIwAuAgeODQAABQBLAHUNAAAEAEQAfw0AAAQAUACpDQAABAA6AFwNAAADAEgAXQ0AAAIAUgAzDQAABQBKABcABwrsG48jAC4CB44NAAAFAEsAdQ0AAAQARAB/DQAABABQAKkNAAAEADoAXA0AAAMASABdDQAAAgBSADMNAAAFAEoAATUAAQoCCAIAEgAAAAA=.',
Ko='Korikora:BAEANQADCgUICAABNQAECgQIDQASAAAAAA==.',
Kr='Kregazi:BAEBNQAECn8oAAIFAAkKHyGdEQAeAwmODQAABgBRAHUNAAAGAF0Afw0AAAUATACpDQAABQBNAFwNAAAEAFUAXQ0AAAQAWwBlDQAABABHAKQNAAABAFwAMw0AAAUATQAFAAkKHyGdEQAeAwmODQAABgBRAHUNAAAGAF0Afw0AAAUATACpDQAABQBNAFwNAAAEAFUAXQ0AAAQAWwBlDQAABABHAKQNAAABAFwAMw0AAAUATQAAAA==.',
Ky='Kyssarra:BAECNQAFFH8bAAQYAAcKkCIvAQAxAQeODQAABQBjAHUNAAAEAFgAfw0AAAQAUgCpDQAABABjAFwNAAAEAE4AXQ0AAAEATAAzDQAABQBeABgAAwpiIi8BADEBA3UNAAAEAFgAqQ0AAAQAYwBdDQAAAQBMAAsAAwrWIr0aACMBA44NAAAFAGMAfw0AAAQAUgBcDQAAAwBOABkAAgoWFR8DAMcAAlwNAAABADUAMw0AAAUAXgA1AAQKf38ABBgACQriJhcAAAsEABgACQrEJhcAAAsEAAsABQpjJv1tABACABkABQqCJjwIAAwCAAAA.',
Lo='Lobotomight:BAEANQAECgcIDQABNQAFFAIIBQAFAFoRAA==.',
Lu='Lunaë:BAEBNQAECn80AAIGAAkKWB9eEgA2AwmODQAABwBJAHUNAAAGAFEAfw0AAAYAWQCpDQAACABMAFwNAAAHAFAAXQ0AAAQAMQBlDQAABQBTAKQNAAAFAFsAMw0AAAQAYAAGAAkKWB9eEgA2AwmODQAABwBJAHUNAAAGAFEAfw0AAAYAWQCpDQAACABMAFwNAAAHAFAAXQ0AAAQAMQBlDQAABQBTAKQNAAAFAFsAMw0AAAQAYAAAAA==.Lunäe:BAEBNQAECn8dAAIGAAkK+BpTJQDTAgmODQAABgBRAHUNAAAEAD8Afw0AAAYAUQCpDQAAAwA+AFwNAAACAEUAXQ0AAAMANABlDQAAAQA3AKQNAAABADkAMw0AAAMAYAAGAAkK+BpTJQDTAgmODQAABgBRAHUNAAAEAD8Afw0AAAYAUQCpDQAAAwA+AFwNAAACAEUAXQ0AAAMANABlDQAAAQA3AKQNAAABADkAMw0AAAMAYAABNQAECgkJNAAGAFgfAA==.',
['Lü']='Lünae:BAEANQAECgcIBwABNQAECgkJNAAGAFgfAA==.',
Ma='Maildaddy:BAEANQAFFAEIAQAAAA==.Maxxy:BAEANQAECgYIDwAAAA==.',
Mc='Mckellen:BAEANQAECgcIEwABNQAFFAcIJgAKAL8cAA==.',
Me='Merarite:BAEBNQAECn8vAAIFAAkK9xZMLgBZAgmODQAABwA8AHUNAAAHAEsAfw0AAAYANACpDQAABwBCAFwNAAAGAEYAXQ0AAAUAIQBlDQAABABJAKQNAAABACAAMw0AAAQAPQAFAAkK9xZMLgBZAgmODQAABwA8AHUNAAAHAEsAfw0AAAYANACpDQAABwBCAFwNAAAGAEYAXQ0AAAUAIQBlDQAABABJAKQNAAABACAAMw0AAAQAPQAAAA==.',
Mo='Monkguyy:BAEANQAECgYIBwABNQAECggIFwADAOIEAA==.',
Na='Nadasa:BAEBNQAECn9SAAIaAAkKMyIgEQCDAwmODQAADgBdAHUNAAAMAF8Afw0AAAwAYQCpDQAADABYAFwNAAAJAGEAXQ0AAAMARwBlDQAACQBaAKQNAAACAEsAMw0AAAkAWwAaAAkKMyIgEQCDAwmODQAADgBdAHUNAAAMAF8Afw0AAAwAYQCpDQAADABYAFwNAAAJAGEAXQ0AAAMARwBlDQAACQBaAKQNAAACAEsAMw0AAAkAWwAAAA==.',
Ni='Nixaanu:BAEANQADCgYICQAAAA==.',
No='Nomadicbear:BAEANQABCgQICAABNQABCgYICAASAAAAAA==.Nomadichunt:BAEANQABCgYICAAAAA==.Nomadicmonk:BAEANQABCgQIBAABNQABCgYICAASAAAAAA==.',
Ny='Nyriaa:BAEANQADCggICAAAAA==.',
Pa='Palashin:BAEANQAECgQIBQABNQAFFAUIBwAUADkNAA==.',
Pe='Personnelkid:BAEANQADCggICAABNQAECgkJJwAGAOAUAA==.',
Po='Poortal:BAEANQAECgEIAQABNQAFFAIIBQAFAFoRAA==.Potatogogue:BAECNQAFFH8NAAMHAAYK3RFOFAArAQaODQAABAAuAHUNAAACAA4Afw0AAAEAMgCpDQAAAwAfAFwNAAACAFoAMw0AAAEAGAAHAAQKFAxOFAArAQSODQAABAAuAHUNAAACAA4AqQ0AAAMAHwAzDQAAAQAYABQAAgpaFJAdAKEAAn8NAAABAEsAXA0AAAIAHAA1AAQKfyQAAwcACQqZIAclAO4CAAcACQqZIAclAO4CABQAAgpQH5fuAIgAAAE1AAUUAQgBABIAAAAA.Potatoroguee:BAEANQAECgYIBwABNQAFFAEIAQASAAAAAA==.',
Ri='Ritren:BAEANQAECgMIAwABNQAECgcIDgASAAAAAA==.',
Ro='Roogies:BAECNQAFFH8LAAINAAQKwyWPBgCvAQSODQAABQBhAHUNAAACAGEAfw0AAAEAUACpDQAAAwBfAA0ABArDJY8GAK8BBI4NAAAFAGEAdQ0AAAIAYQB/DQAAAQBQAKkNAAADAF8ANQAECn9AAAINAAkK1iR7AwCeAwANAAkK1iR7AwCeAwAAAA==.',
Se='Senzarial:BAEANQAECgEIAQABNQAFFAcIFwAIAKodAA==.Serynytee:BAEANQAECgYIDQAAAA==.',
Sh='Shinseer:BAECNQAFFH8HAAIUAAUKOQ27DgBdAQWODQAAAQAvAHUNAAABAAsAfw0AAAIAIACpDQAAAQA5ADMNAAACABQAFAAFCjkNuw4AXQEFjg0AAAEALwB1DQAAAQALAH8NAAACACAAqQ0AAAEAOQAzDQAAAgAUADUABAp/KQACFAAJCmEfdxIAMwMAFAAJCmEfdxIAMwMAAAA=.Shinthyr:BAEANQAFFAEIAQABNQAFFAUIBwAUADkNAA==.',
St='Starryangel:BAEANQAECgEIAQABNQAFFAUIEwAaAAUTAA==.Stormbroken:BAEANQADCgUIBQABNQAECgkJJwAGAOAUAA==.',
Su='Sunwelljuice:BAEANQADCggIGQABNQAECgkJJwAGAOAUAA==.',
Sy='Syldrasi:BAEANQADCgQICAABNQAFFAQICwANAMMlAA==.',
Ta='Tahune:BAEBNQAECn8zAAMJAAkKkSJfBQBqAwmODQAACABZAHUNAAAHAGIAfw0AAAYAQQCpDQAABwBYAFwNAAAGAFEAXQ0AAAUAYgBlDQAABABiAKQNAAABAFgAMw0AAAcAVgAJAAkKkSJfBQBqAwmODQAABwBZAHUNAAAGAGIAfw0AAAUAQQCpDQAABgBYAFwNAAAFAFEAXQ0AAAUAYgBlDQAABABiAKQNAAABAFgAMw0AAAYAVgAIAAYKKh3ZQgDmAQaODQAAAQBRAHUNAAABAE0Afw0AAAEALwCpDQAAAQA8AFwNAAABAE8AMw0AAAEATAAAAA==.Talaandea:BAEANQADCggIEwAAAA==.',
Th='Thawd:BAECNQAFFH8dAAIQAAcKMBcQAQA3AgeODQAABgBZAHUNAAAFAEYAfw0AAAUAPACpDQAABgAwAFwNAAADACoAXQ0AAAEALQAzDQAAAwA8ABAABwowFxABADcCB44NAAAGAFkAdQ0AAAUARgB/DQAABQA8AKkNAAAGADAAXA0AAAMAKgBdDQAAAQAtADMNAAADADwANQAECn8lAAIQAAkKpR9dBgDnAgAQAAkKpR9dBgDnAgAAAA==.Therapygap:BAEANQAECgIIAwABNQAECgkJJwAGAOAUAA==.',
Tr='Trèantdaddy:BAEANQAECgYIBgABNQAFFAEIAQASAAAAAA==.',
Us='Usurah:BAECNQAFFH8PAAIaAAYK4hThBQD1AQaODQAAAwAmAHUNAAACADEAfw0AAAMAVACpDQAAAwA+AFwNAAABAD8AMw0AAAMAVAAaAAYK4hThBQD1AQaODQAAAwAmAHUNAAACADEAfw0AAAMAVACpDQAAAwA+AFwNAAABAD8AMw0AAAMAVAA1AAQKfzEAAhoACQoDJGgHAL4DABoACQoDJGgHAL4DAAAA.',
Vc='Vcoren:BAEBNQAECn8hAAIbAAkKnCSwAwC3AwmODQAAAwBaAHUNAAAFAFwAfw0AAAUAXwCpDQAABQBeAFwNAAAFAF8AXQ0AAAQAXwBlDQAAAgBgAKQNAAACAFMAMw0AAAIAYgAbAAkKnCSwAwC3AwmODQAAAwBaAHUNAAAFAFwAfw0AAAUAXwCpDQAABQBeAFwNAAAFAF8AXQ0AAAQAXwBlDQAAAgBgAKQNAAACAFMAMw0AAAIAYgABNQAFFAcIJgAKAL8cAA==.',
Wh='Whimsiloxi:BAEANQAECgEIAQABNQAFFAcIFwAIAKodAA==.',
Za='Zatum:BAEANQAECgUIDQAAAA==.',
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
