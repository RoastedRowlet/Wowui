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

local lookup = {'Druid-Guardian','Druid-Feral','Druid-Balance','Druid-Restoration','Paladin-Protection','Paladin-Holy','Paladin-Retribution','Warlock-Affliction','Warrior-Arms','Warrior-Protection','Priest-Holy','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Warlock-Demonology','Mage-Frost','Shaman-Elemental','Priest-Discipline','Hunter-BeastMastery','Evoker-Devastation','DeathKnight-Blood','Shaman-Restoration','Mage-Arcane','DeathKnight-Unholy','Priest-Shadow','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='EmeraldDream',name='US',type='subscribers',zone=53,date='2026-11-17',data={Ad='Adleymoon:BAECNQAFFH8nAAMBAAgKPiEcAADxAgiODQAABgBkAHUNAAAEAGIAfw0AAAUAYACpDQAABgBgAFwNAAAEAFwAZQ0AAAEARwCkDQAABAAzADMNAAAJAGQAAQAICj4hHAAA8QIIjg0AAAYAZAB1DQAABABiAH8NAAAFAGAAqQ0AAAYAYABcDQAABABcAGUNAAABAEcApA0AAAQAMwAzDQAABwBkAAIAAQoAABEGAAAAATMNAAACAFUANQAECn80AAUBAAoKFybkAQC7AwABAAkK5SXkAQC7AwACAAgKCCUWCQC7AgADAAQKaiJjVgB+AQAEAAUK8x5tMQBlAQAAAA==.Adleytoll:BAECNQAFFH8SAAIFAAgKOyDLAACpAgiODQAAAQBYAHUNAAABAFQAfw0AAAEAXgCpDQAAAQBTAFwNAAABADYAXQ0AAAUAWwBlDQAABQBdADMNAAADAFwABQAICjsgywAAqQIIjg0AAAEAWAB1DQAAAQBUAH8NAAABAF4AqQ0AAAEAUwBcDQAAAQA2AF0NAAAFAFsAZQ0AAAUAXQAzDQAAAwBcADUABAp/FAAEBQAKCvohExIAgAIABQAJChMiExIAgAIABgAECkoXDsoA5wAABwACCsIg1mgBYAAAATUABRQICCcAAQA+IQA=.',
Al='Alleryia:BAEANQAECgIIAgABNQAFFAMICAAIALAPAA==.',
Cj='Cjk:BAECNQAFFH8bAAIJAAgKjgxJDQDdAQiODQAABQBDAHUNAAADABQAfw0AAAMAIgCpDQAABQAjAFwNAAACADEAXQ0AAAEACgBlDQAAAQAJADMNAAAHADkACQAICo4MSQ0A3QEIjg0AAAUAQwB1DQAAAwAUAH8NAAADACIAqQ0AAAUAIwBcDQAAAgAxAF0NAAABAAoAZQ0AAAEACQAzDQAABwA5ADUABAp/JwADCQAKCvYdM2QAYgIACQAKCvYdM2QAYgIACgABCgAAu1EAAAAAAAA=.',
Da='Damio:BAEANQAECgcIDwABNQAFFAkJJwALAEQQAA==.',
De='Dechu:BAECNQAFFH8OAAMMAAgKaAt+BgC2AQiODQAAAgAmAHUNAAACADQAfw0AAAIABwCpDQAAAgAjAFwNAAACACEAXQ0AAAIABABlDQAAAQAKADMNAAABAAkADAAHCmgLfgYAtgEHjg0AAAIAJgB1DQAAAgA0AH8NAAACAAcAqQ0AAAEAIwBcDQAAAgAhAF0NAAACAAQAZQ0AAAEACgANAAIKygmDEgA+AAKpDQAAAQAZADMNAAABAAkANQAECn8mAAQNAAoKgRl3JgASAgANAAkKShN3JgASAgAMAAQKJxcwbADIAAAOAAIKxx5WIgCvAAAAAA==.',
Et='Etheryia:BAECNQAFFH8IAAMIAAMKsA+DAwDeAAOODQAABAAmAHUNAAABAEEAqQ0AAAMAEAAIAAMKmw+DAwDeAAOODQAAAQAmAHUNAAABAEEAqQ0AAAEADwAPAAIKFgezLAB6AAKODQAAAwATAKkNAAACABAANQAECn87AAMIAAoKWR0nBwAwAgAPAAkKYxwBWABOAgAIAAgKdR0nBwAwAgAAAA==.',
Fr='Frostsprit:BAEBNQAECn8WAAIQAAkKkxTnEQCHAQmODQAABQA2AHUNAAADAEMAfw0AAAMAUQCpDQAAAgApAFwNAAABAE4AZQ0AAAIAKQCkDQAAAgAtADMNAAADADsAuQ0AAAEAJwAQAAkKkxTnEQCHAQmODQAABQA2AHUNAAADAEMAfw0AAAMAUQCpDQAAAgApAFwNAAABAE4AZQ0AAAIAKQCkDQAAAgAtADMNAAADADsAuQ0AAAEAJwAAAA==.',
Ga='Gaping:BAEANQAECgYICwAAAA==.',
Ho='Holonna:BAEANQAECgIIAgABNQAFFAcIFAARACsPAA==.Holymolio:BAECNQAFFH8nAAMLAAkKRBBNBgA1AgmODQAABgBQAHUNAAAFABQAfw0AAAQAUwCpDQAABAAlAFwNAAAEACMAXQ0AAAMADwBlDQAAAgAnAKQNAAACABQAMw0AAAkAKQALAAkKRBBNBgA1AgmODQAABgBQAHUNAAAEABQAfw0AAAQAUwCpDQAAAwAlAFwNAAAEACMAXQ0AAAMADwBlDQAAAgAnAKQNAAACABQAMw0AAAgAKQASAAMKlwRBAgC/AAN1DQAAAQARAKkNAAABAA8AMw0AAAEAAQA1AAQKf1IAAwsACgogJLMLAGUDAAsACgogJLMLAGUDABIACArhDMkLAIEBAAAA.Hossidan:BAEANQADCgEIAQABNQAFFAgIEgATAFUcAA==.',
Jb='Jbg:BAEANQADCgUIBQABNQAECgkJKQAUAGIXAA==.',
Ki='Kirumar:BAEANQAECgcIBwABNQAECgoKIwATAGAPAA==.',
Kl='Klarth:BAEBNQAECn8dAAIVAAkK+Rv0IwDbAQmODQAACABeAHUNAAAGAF0Afw0AAAUAWwCpDQAAAwAmAFwNAAABADwAXQ0AAAIAUQBlDQAAAQA7AKQNAAABAEgAMw0AAAIAPwAVAAkK+Rv0IwDbAQmODQAACABeAHUNAAAGAF0Afw0AAAUAWwCpDQAAAwAmAFwNAAABADwAXQ0AAAIAUQBlDQAAAQA7AKQNAAABAEgAMw0AAAIAPwABNQAFFAMIDwAWACcaAA==.',
Le='Levitoc:BAECNQAFFH8nAAMXAAkKBCJbBwBOAgmODQAABABgAHUNAAAFAF8Afw0AAAUAWwCpDQAABQBbAFwNAAAEAGAAXQ0AAAMAYwBlDQAAAgBCAKQNAAACAD4AMw0AAAkAYgAXAAgKMyFbBwBOAgiODQAABABgAHUNAAAFAF8Afw0AAAUAWwCpDQAABQBbAFwNAAAEAGAAZQ0AAAIAQgCkDQAAAgA+ADMNAAAJAGIAEAABCuwmhgoAdQABXQ0AAAMAYwA1AAQKfzsAAhcACgpCJiYCAHgDABcACgpCJiYCAHgDAAAA.',
Li='Liothen:BAEANQAECggIEgAAAA==.',
Mo='Moodist:BAEANQAECgMIAwABNQAFFAgIDgAMAGgLAA==.',
Nu='Nurak:BAEANQADCgYIBgAAAA==.',
Ph='Pharyngitis:BAEBNQAECn9IAAIYAAoKjR0mHADjAgqODQAADABVAHUNAAAKAFgAfw0AAAkAVwCpDQAACgBPAFwNAAAHAFQAXQ0AAAUAVABlDQAABQBLAKQNAAAFAD8AMw0AAAYAWAC5DQAAAwAsABgACgqNHSYcAOMCCo4NAAAMAFUAdQ0AAAoAWAB/DQAACQBXAKkNAAAKAE8AXA0AAAcAVABdDQAABQBUAGUNAAAFAEsApA0AAAUAPwAzDQAABgBYALkNAAADACwAAAA=.',
Pw='Pwrdpando:BAECNQAFFH84AAQLAAoKZho6AQDXAgqODQAACABZAHUNAAAGAB4Afw0AAAcAWQCpDQAABgApAFwNAAAFAFkAXQ0AAAQANQBlDQAABQBYAKQNAAAFAFwAMw0AAAkAWQC5DQAAAQAMAAsACgpmGjoBANcCCo4NAAAGAFkAdQ0AAAYAHgB/DQAABwBZAKkNAAAGACkAXA0AAAUAWQBdDQAABAA1AGUNAAACAFgApA0AAAUAXAAzDQAACQBZALkNAAABAAwAEgABCtcg8wEAZgABZQ0AAAMAVAAZAAEKUxfaFgBFAAGODQAAAgA7ADUABAp/LAAECwAKCqskaxUAJQMACwAKClEhaxUAJQMAEgAECtkkEQ4ATwEAGQACCgchgVMAwAAAATUAAQoCCAIAGgAAAAA=.',
Ra='Rayocchi:BAEANQAECgMIAwABNQAECgoKLwAGAJceAA==.Rayocell:BAEBNQAECn8vAAMGAAoKlx74MgCZAgqODQAABwBcAHUNAAAFAEUAfw0AAAQAWwCpDQAABQBOAFwNAAAFAFMAXQ0AAAQAVwBlDQAABQAoAKQNAAADAE8AMw0AAAQAPgC5DQAABQBiAAYACgqXHvgyAJkCCo4NAAAFAFwAdQ0AAAMARQB/DQAAAwBbAKkNAAADAE4AXA0AAAMAUwBdDQAAAwBXAGUNAAACACgApA0AAAEATwAzDQAAAwA+ALkNAAAFAGIABwAJCkwdj5YAnwEJjg0AAAIATQB1DQAAAgBaAH8NAAABAFgAqQ0AAAIARgBcDQAAAgBQAF0NAAABAEcAZQ0AAAMAUgCkDQAAAgA0ADMNAAABADoAAAA=.Rayogizer:BAEBNQAECn8ZAAILAAoKwR7pGwADAwqODQAAAwBPAHUNAAADAE0Afw0AAAMAYQCpDQAAAwBdAFwNAAACAD0AXQ0AAAIAVwBlDQAAAgBPAKQNAAAFAFMAMw0AAAEAMQC5DQAAAQBNAAsACgrBHukbAAMDCo4NAAADAE8AdQ0AAAMATQB/DQAAAwBhAKkNAAADAF0AXA0AAAIAPQBdDQAAAgBXAGUNAAACAE8ApA0AAAUAUwAzDQAAAQAxALkNAAABAE0AATUABAoKCi8ABgCXHgA=.',
Sn='Snigmorder:BAECNQAFFH8bAAMbAAcKFB8QAgB5AgeODQAABgBhAHUNAAAFAFsAfw0AAAUAUgCpDQAABgBhAFwNAAADAD8AXQ0AAAEAYABlDQAAAQAeABsABgrqIhACAHkCBo4NAAAFAGEAdQ0AAAUAWwB/DQAABABSAKkNAAAGAGEAXA0AAAMAPwBdDQAAAQBgABwAAwq8DSEPAJkAA44NAAABACcAfw0AAAEAJABlDQAAAQAeADUABAp/OwADGwAKCvolTwEAYQMAGwAJCnclTwEAYQMAHAAKCgUkgwYASQMAATUABRQICA4ADABoCwA=.',
Sp='Splashofray:BAEANQAECgQIBAABNQAECgoKLwAGAJceAA==.',
Th='Thwonknchad:BAECNQAFFH8jAAIFAAkKUSaEAADTAgmODQAABQBhAHUNAAAEAGAAfw0AAAQARQCpDQAABABiAFwNAAADAGIAXQ0AAAMAYwBlDQAAAgBgAKQNAAACAGMAMw0AAAgAZAAFAAkKUSaEAADTAgmODQAABQBhAHUNAAAEAGAAfw0AAAQARQCpDQAABABiAFwNAAADAGIAXQ0AAAMAYwBlDQAAAgBgAKQNAAACAGMAMw0AAAgAZAA1AAQKf1cAAgUACgraJjMAAJ4DAAUACgraJjMAAJ4DAAAA.',
Vh='Vhader:BAEBNQAECn8vAAIVAAoKDxy1EQAfAwqODQAACABhAHUNAAAGAFkAfw0AAAUAVACpDQAABgBbAFwNAAAFAF8AXQ0AAAUAGgBlDQAABQBGAKQNAAACAEoAMw0AAAQAWgC5DQAAAQAcABUACgoPHLURAB8DCo4NAAAIAGEAdQ0AAAYAWQB/DQAABQBUAKkNAAAGAFsAXA0AAAUAXwBdDQAABQAaAGUNAAAFAEYApA0AAAIASgAzDQAABABaALkNAAABABwAAAA=.',
['Wú']='Wú:BAEANQAECgUIBgABNQAECgoKIwATAGAPAA==.',
Zo='Zogado:BAEBNQAECn8zAAMWAAoKCx7TFwD3AgqODQAACQBjAHUNAAAHAFoAfw0AAAcAXACpDQAABgBgAFwNAAAGAFoAXQ0AAAQAPwBlDQAABQBYAKQNAAACAFkAMw0AAAQALgC5DQAAAQALABYACgoLHtMXAPcCCo4NAAAGAGMAdQ0AAAcAWgB/DQAABwBcAKkNAAAEAGAAXA0AAAYAWgBdDQAABAA/AGUNAAAFAFgApA0AAAIAWQAzDQAAAgAuALkNAAABAAsAEQADCm8dU9kA4gADjg0AAAMAQgCpDQAAAgBTADMNAAACAEEAAAA=.',
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
