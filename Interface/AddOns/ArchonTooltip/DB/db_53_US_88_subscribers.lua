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

local lookup = {'Druid-Guardian','Druid-Feral','Druid-Balance','Druid-Restoration','Paladin-Protection','Warlock-Affliction','Warrior-Arms','Warrior-Protection','Priest-Holy','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Assassination','Warlock-Demonology','Shaman-Elemental','Priest-Discipline','Hunter-BeastMastery','Evoker-Devastation','DeathKnight-Blood','Shaman-Restoration','Mage-Arcane','Mage-Frost','Evoker-Preservation','Warlock-Destruction','DeathKnight-Unholy','Priest-Shadow','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Rogue-Subtlety',}
local provider = {region='US',realm='EmeraldDream',name='US',type='subscribers',zone=53,date='2026-11-10',data={Ad='Adleymoon:BAECNQAFFH8jAAMBAAcKRCIcAADxAgeODQAABQBkAHUNAAAEAGIAfw0AAAUAYACpDQAABQBgAFwNAAAEAFwApA0AAAMAMwAzDQAACQBkAAEABwpEIhwAAPECB44NAAAFAGQAdQ0AAAQAYgB/DQAABQBgAKkNAAAFAGAAXA0AAAQAXACkDQAAAwAzADMNAAAHAGQAAgABCgAAcAUAAAABMw0AAAIAVQA1AAQKfzQABQEACgoXJuQBALsDAAEACQrlJeQBALsDAAIACAoIJRYJALsCAAMABApqImNWAH4BAAQABQrzHmAtAGcBAAE1AAUUCAgSAAUAOyAA.Adleytoll:BAEBNQAFFH8SAAIFAAgKOyDLAACpAgiODQAAAQBYAHUNAAABAFQAfw0AAAEAXgCpDQAAAQBTAFwNAAABADYAXQ0AAAUAWwBlDQAABQBdADMNAAADAFwABQAICjsgywAAqQIIjg0AAAEAWAB1DQAAAQBUAH8NAAABAF4AqQ0AAAEAUwBcDQAAAQA2AF0NAAAFAFsAZQ0AAAUAXQAzDQAAAwBcAAAA.',
Al='Alleryia:BAEANQAECgIIAgABNQAFFAMICAAGALAPAA==.',
Cj='Cjk:BAECNQAFFH8ZAAIHAAcKVw5JDQDdAQeODQAABQBDAHUNAAADABQAfw0AAAMAIgCpDQAABQAjAFwNAAACADEAXQ0AAAEACgAzDQAABgA5AAcABwpXDkkNAN0BB44NAAAFAEMAdQ0AAAMAFAB/DQAAAwAiAKkNAAAFACMAXA0AAAIAMQBdDQAAAQAKADMNAAAGADkANQAECn8nAAMHAAoK9h0zZABiAgAHAAoK9h0zZABiAgAIAAEKAADmTAAAAAAAAA==.',
Da='Damio:BAEANQAECgcIDwABNQAFFAkJIAAJACUNAA==.',
De='Dechu:BAECNQAFFH8GAAMKAAYK+QcMCgATAQaODQAAAQAgAHUNAAABAAYAfw0AAAEABwCpDQAAAQAZAFwNAAABACEAXQ0AAAEABAAKAAUKhQcMCgATAQWODQAAAQAgAHUNAAABAAYAfw0AAAEABwBcDQAAAQAhAF0NAAABAAQACwABCsoJfREAQAABqQ0AAAEAGQA1AAQKfyYABAsACgqBGXcmABICAAsACQpKE3cmABICAAoABAonFzBsAMgAAAwAAgrHHlYiAK8AAAE1AAUUBwgbAA0AFB8A.',
Et='Etheryia:BAECNQAFFH8IAAMGAAMKsA/DAgDfAAOODQAABAAmAHUNAAABAEEAqQ0AAAMAEAAGAAMKmw/DAgDfAAOODQAAAQAmAHUNAAABAEEAqQ0AAAEADwAOAAIKFgekKAB9AAKODQAAAwATAKkNAAACABAANQAECn87AAMGAAoKWR0nBwAwAgAOAAkKYxwBWABOAgAGAAgKdR0nBwAwAgAAAA==.',
Fr='Frostsprit:BAEANQAECgcIEgAAAA==.',
Ga='Gaping:BAEANQAECgYICwAAAA==.',
Ho='Holonna:BAEANQAECgIIAgABNQAFFAcIFAAPACsPAA==.Holymolio:BAECNQAFFH8gAAMJAAkKJQ1NBgA1AgmODQAABQBQAHUNAAAEABQAfw0AAAQAUwCpDQAABAAlAFwNAAADAAwAXQ0AAAIADwBlDQAAAQACAKQNAAABAAgAMw0AAAgAKQAJAAkKJQ1NBgA1AgmODQAABQBQAHUNAAADABQAfw0AAAQAUwCpDQAAAwAlAFwNAAADAAwAXQ0AAAIADwBlDQAAAQACAKQNAAABAAgAMw0AAAcAKQAQAAMKlwRBAgC/AAN1DQAAAQARAKkNAAABAA8AMw0AAAEAAQA1AAQKf1IAAwkACgogJLMLAGUDAAkACgogJLMLAGUDABAACArhDMkLAIEBAAAA.Hossidan:BAEANQADCgEIAQABNQAFFAcIEQARAFIcAA==.',
Jb='Jbg:BAEANQADCgUIBQABNQAECgkJKQASAGIXAA==.',
Ke='Ketu:BAEBNQAECn8WAAUDAAoKjBU4TACyAQqODQAABQBHAHUNAAADAEAAfw0AAAIAUwCpDQAAAgA8AFwNAAACADsAXQ0AAAEAJgBlDQAAAQBBAKQNAAABADAAMw0AAAMARAC5DQAAAgAgAAMABwpgFThMALIBB44NAAAEAD0AdQ0AAAIAQAB/DQAAAQBTAKkNAAABADwAXQ0AAAEAJgCkDQAAAQAwADMNAAACAEAAAQAFCkUQq0UAlQAFdQ0AAAEAPAB/DQAAAQAzAKkNAAABAB0AXA0AAAEAIgAzDQAAAQBEAAQAAgo0EMZZAHoAAmUNAAABAA8AuQ0AAAIAQwACAAIKoRmnOwBOAAKODQAAAQBHAFwNAAABADsAAAA=.',
Ki='Kirumar:BAEANQAECgcICAABNQAECgkJHAARAKwPAA==.',
Kl='Klarth:BAEBNQAECn8cAAITAAkK+Rt/IQDfAQmODQAABwBeAHUNAAAGAF0Afw0AAAUAWwCpDQAAAwAmAFwNAAABADwAXQ0AAAIAUQBlDQAAAQA7AKQNAAABAEgAMw0AAAIAPwATAAkK+Rt/IQDfAQmODQAABwBeAHUNAAAGAF0Afw0AAAUAWwCpDQAAAwAmAFwNAAABADwAXQ0AAAIAUQBlDQAAAQA7AKQNAAABAEgAMw0AAAIAPwABNQAFFAMIDwAUACcaAA==.',
Le='Levitoc:BAECNQAFFH8fAAMVAAkKLiBbBwBOAgmODQAABABgAHUNAAAEAE8Afw0AAAQAWwCpDQAABABbAFwNAAADAGAAXQ0AAAIAYQBlDQAAAQAzAKQNAAABAD4AMw0AAAgAYgAVAAgKMR9bBwBOAgiODQAABABgAHUNAAAEAE8Afw0AAAQAWwCpDQAABABbAFwNAAADAGAAZQ0AAAEAMwCkDQAAAQA+ADMNAAAIAGIAFgABChwmhwoAagABXQ0AAAIAYQA1AAQKfzsAAhUACgpCJrABAHwDABUACgpCJrABAHwDAAAA.',
Li='Liothen:BAEBNQAECn8VAAIXAAoK+wDpQQCSAAqODQAAAwADAHUNAAADAAAAfw0AAAMABACpDQAAAgAAAFwNAAACAAIAXQ0AAAIAAABlDQAAAgAAAKQNAAABAAEAMw0AAAIAAwC5DQAAAQAGABcACgr7AOlBAJIACo4NAAADAAMAdQ0AAAMAAAB/DQAAAwAEAKkNAAACAAAAXA0AAAIAAgBdDQAAAgAAAGUNAAACAAAApA0AAAEAAQAzDQAAAgADALkNAAABAAYAAAA=.',
Mo='Moodist:BAEANQAECgMIAwABNQAFFAcIGwANABQfAA==.',
Nu='Nurak:BAEANQADCgYIBgAAAA==.',
Og='Og:BAEBNQAECn8cAAMOAAgKvBxHWwBFAgiODQAABQBUAHUNAAAEAE0Afw0AAAQASwCpDQAABABJAFwNAAADAEUAXQ0AAAIAVAAzDQAABQBgALkNAAABADQADgAICmocR1sARQIIjg0AAAUAVAB1DQAAAwBIAH8NAAAEAEsAqQ0AAAQASQBcDQAAAwBFAF0NAAACAFQAMw0AAAUAYAC5DQAAAQA0ABgAAQpNHmNmAFYAAXUNAAABAE0AATUABAoKChYAAwCMFQA=.Ogthul:BAEANQAECggIDgABNQAECgoKFgADAIwVAA==.',
Op='Op:BAEANQAECgcIEgABNQAECgoKFgADAIwVAA==.',
Ph='Pharyngitis:BAEBNQAECn9IAAIZAAoKjR0mHADjAgqODQAADABVAHUNAAAKAFgAfw0AAAkAVwCpDQAACgBPAFwNAAAHAFQAXQ0AAAUAVABlDQAABQBLAKQNAAAFAD8AMw0AAAYAWAC5DQAAAwAsABkACgqNHSYcAOMCCo4NAAAMAFUAdQ0AAAoAWAB/DQAACQBXAKkNAAAKAE8AXA0AAAcAVABdDQAABQBUAGUNAAAFAEsApA0AAAUAPwAzDQAABgBYALkNAAADACwAAAA=.',
Pw='Pwrdpando:BAECNQAFFH84AAQJAAoKZhrfAABvAwqODQAACABZAHUNAAAGAB4Afw0AAAcAWQCpDQAABgApAFwNAAAFAFkAXQ0AAAQANQBlDQAABQBYAKQNAAAFAFwAMw0AAAkAWQC5DQAAAQAMAAkACgpmGt8AAG8DCo4NAAAGAFkAdQ0AAAYAHgB/DQAABwBZAKkNAAAGACkAXA0AAAUAWQBdDQAABAA1AGUNAAACAFgApA0AAAUAXAAzDQAACQBZALkNAAABAAwAEAABCtcgzAEAZgABZQ0AAAMAVAAaAAEKUxdUFQBFAAGODQAAAgA7ADUABAp/LAAECQAKCqskaxUAJQMACQAKClEhaxUAJQMAEAAECtkkEQ4ATwEAGgACCgchgVMAwAAAATUAAQoCCAIAGwAAAAA=.',
Ra='Rayocchi:BAEANQAECgMIAwABNQAECgoKLgAcAEYeAA==.Rayocell:BAEBNQAECn8uAAMcAAoKRh74MgCZAgqODQAABwBcAHUNAAAFAEUAfw0AAAQAWwCpDQAABQBOAFwNAAAFAFMAXQ0AAAQAVwBlDQAABQAoAKQNAAADAE8AMw0AAAQAPgC5DQAABABaABwACgpGHvgyAJkCCo4NAAAFAFwAdQ0AAAMARQB/DQAAAwBbAKkNAAADAE4AXA0AAAMAUwBdDQAAAwBXAGUNAAACACgApA0AAAEATwAzDQAAAwA+ALkNAAAEAFoAHQAJCkwdW4cAqQEJjg0AAAIATQB1DQAAAgBaAH8NAAABAFgAqQ0AAAIARgBcDQAAAgBQAF0NAAABAEcAZQ0AAAMAUgCkDQAAAgA0ADMNAAABADoAAAA=.Rayogizer:BAEBNQAECn8ZAAIJAAoKwR7pGwADAwqODQAAAwBPAHUNAAADAE0Afw0AAAMAYQCpDQAAAwBdAFwNAAACAD0AXQ0AAAIAVwBlDQAAAgBPAKQNAAAFAFMAMw0AAAEAMQC5DQAAAQBNAAkACgrBHukbAAMDCo4NAAADAE8AdQ0AAAMATQB/DQAAAwBhAKkNAAADAF0AXA0AAAIAPQBdDQAAAgBXAGUNAAACAE8ApA0AAAUAUwAzDQAAAQAxALkNAAABAE0AATUABAoKCi4AHABGHgA=.',
Sn='Snigmorder:BAECNQAFFH8bAAMNAAcKFB8QAgB5AgeODQAABgBhAHUNAAAFAFsAfw0AAAUAUgCpDQAABgBhAFwNAAADAD8AXQ0AAAEAYABlDQAAAQAeAA0ABgrqIhACAHkCBo4NAAAFAGEAdQ0AAAUAWwB/DQAABABSAKkNAAAGAGEAXA0AAAMAPwBdDQAAAQBgAB4AAwq8DSEPAJkAA44NAAABACcAfw0AAAEAJABlDQAAAQAeADUABAp/OwADDQAKCvolHwEAZQMADQAJCnclHwEAZQMAHgAKCgUk/QUASwMAAAA=.',
Sp='Splashofray:BAEANQAECgQIBAABNQAECgoKLgAcAEYeAA==.',
Th='Thwonknchad:BAECNQAFFH8gAAIFAAkKWiWEAADTAgmODQAABQBhAHUNAAAEAGAAfw0AAAQARQCpDQAABABiAFwNAAADAGIAXQ0AAAIAYgBlDQAAAQBQAKQNAAABAGMAMw0AAAgAZAAFAAkKWiWEAADTAgmODQAABQBhAHUNAAAEAGAAfw0AAAQARQCpDQAABABiAFwNAAADAGIAXQ0AAAIAYgBlDQAAAQBQAKQNAAABAGMAMw0AAAgAZAA1AAQKf1cAAgUACgraJi0AAJ4DAAUACgraJi0AAJ4DAAAA.',
Vh='Vhader:BAEBNQAECn8vAAITAAoKDxy1EQAfAwqODQAACABhAHUNAAAGAFkAfw0AAAUAVACpDQAABgBbAFwNAAAFAF8AXQ0AAAUAGgBlDQAABQBGAKQNAAACAEoAMw0AAAQAWgC5DQAAAQAcABMACgoPHLURAB8DCo4NAAAIAGEAdQ0AAAYAWQB/DQAABQBUAKkNAAAGAFsAXA0AAAUAXwBdDQAABQAaAGUNAAAFAEYApA0AAAIASgAzDQAABABaALkNAAABABwAAAA=.',
['Wú']='Wú:BAEANQAECgUIBgABNQAECgkJHAARAKwPAA==.',
Zo='Zogado:BAEBNQAECn8qAAMUAAkKSCAGLQBaAgmODQAACABjAHUNAAAGAFgAfw0AAAYAXACpDQAABQBgAFwNAAAFAFoAXQ0AAAMAPwBlDQAABABYAKQNAAABAE4AMw0AAAQALgAUAAkKSCAGLQBaAgmODQAABQBjAHUNAAAGAFgAfw0AAAYAXACpDQAAAwBgAFwNAAAFAFoAXQ0AAAMAPwBlDQAABABYAKQNAAABAE4AMw0AAAIALgAPAAMKbx1T2QDiAAOODQAAAwBCAKkNAAACAFMAMw0AAAIAQQAAAA==.',
['Øg']='Øg:BAEANQAECgMIAwABNQAECgoKFgADAIwVAA==.',
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
