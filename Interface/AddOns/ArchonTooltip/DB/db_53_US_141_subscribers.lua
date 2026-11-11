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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Warrior-Arms','Monk-Brewmaster','Mage-Arcane','Druid-Guardian','Paladin-Retribution','Paladin-Protection','Shaman-Elemental','DeathKnight-Frost','DeathKnight-Blood','Shaman-Restoration','Mage-Frost','Priest-Holy','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Devourer',}
local provider = {region='US',realm='Lightbringer',name='US',type='subscribers',zone=53,date='2026-11-10',data={An='Anasrastra:BAEANQADCgIIAgABNQAECgIIAgABAAAAAA==.Andrà:BAEBNQAECn8nAAICAAoKqB7OLwDdAgqODQAACABXAHUNAAAEAFcAfw0AAAQAVgCpDQAABABUAFwNAAADAC4AXQ0AAAMARABlDQAABQBIAKQNAAAEAFwAMw0AAAMAWgC5DQAAAQBZAAIACgqoHs4vAN0CCo4NAAAIAFcAdQ0AAAQAVwB/DQAABABWAKkNAAAEAFQAXA0AAAMALgBdDQAAAwBEAGUNAAAFAEgApA0AAAQAXAAzDQAAAwBaALkNAAABAFkAAAA=.',
Be='Bestworgnevr:BAEANQAECgMIAwABNQAECgoKIAADALMZAA==.',
Bi='Bighugz:BAEBNQAECn8YAAIEAAgKthpkDAA9AgiODQAABABCAHUNAAAEAFAAfw0AAAQAUgCpDQAAAgBCAFwNAAACAFAAXQ0AAAIATABlDQAAAQAoADMNAAAFAEoABAAICrYaZAwAPQIIjg0AAAQAQgB1DQAABABQAH8NAAAEAFIAqQ0AAAIAQgBcDQAAAgBQAF0NAAACAEwAZQ0AAAEAKAAzDQAABQBKAAAA.',
Bw='Bwe:BAEBNQAECn8gAAIDAAoKsxl9RgAdAgqODQAABwBOAHUNAAADADsAfw0AAAMAYQCpDQAAAgA5AFwNAAABAC0AXQ0AAAEAIwBlDQAABgBTAKQNAAAEAFIAMw0AAAEAMAC5DQAABABTAAMACgqzGX1GAB0CCo4NAAAHAE4AdQ0AAAMAOwB/DQAAAwBhAKkNAAACADkAXA0AAAEALQBdDQAAAQAjAGUNAAAGAFMApA0AAAQAUgAzDQAAAQAwALkNAAAEAFMAAAA=.Bwelol:BAEBNQAECn8aAAIFAAoKkhGjmABhAQqODQAABAA+AHUNAAACABoAfw0AAAIAJQCpDQAAAgASAFwNAAABAAcAXQ0AAAEAMABlDQAABABNAKQNAAADADQAMw0AAAMAPAC5DQAABABBAAUACgqSEaOYAGEBCo4NAAAEAD4AdQ0AAAIAGgB/DQAAAgAlAKkNAAACABIAXA0AAAEABwBdDQAAAQAwAGUNAAAEAE0ApA0AAAMANAAzDQAAAwA8ALkNAAAEAEEAATUABAoKCiAAAwCzGQA=.Bwè:BAEANQADCgMIBQABNQAECgoKIAADALMZAA==.',
Ca='Catcatchme:BAECNQAFFH8GAAIGAAIKeA6kBwBnAAKODQAABAArAKkNAAACAB4ABgACCngOpAcAZwACjg0AAAQAKwCpDQAAAgAeADUABAp/LAACBgAKCpke+wUANAMABgAKCpke+wUANAMAAAA=.',
Ch='Chixor:BAEANQAECgQIBAABNQAECgoKRgAHALAeAA==.',
Cr='Crackerjill:BAEBNQAECn9GAAMHAAoKsB6bOAB0AgqODQAADQBTAHUNAAAKAFgAfw0AAAkAXgCpDQAABwBMAFwNAAAFAFMAXQ0AAAUAQgBlDQAACQBHAKQNAAAFAFMAMw0AAAMAVAC5DQAABABLAAcACgqYHps4AHQCCo4NAAAMAFEAdQ0AAAkAWAB/DQAACABeAKkNAAAHAEwAXA0AAAUAUwBdDQAABQBCAGUNAAAJAEcApA0AAAUAUwAzDQAAAwBUALkNAAAEAEsACAADCpkgdzwApwADjg0AAAEAUwB1DQAAAQBTAH8NAAABAC4AAAA=.',
Ei='Eilinn:BAEANQAECgMIBwABNQAECgoKIAADALMZAA==.',
Er='Erz:BAEANQAECggIDAAAAA==.',
Fe='Felgrihm:BAEANQAFFAQIBAAAAA==.',
Fh='Fhurian:BAEANQAECgYIEAABNQAFFAQIBAABAAAAAA==.',
Ga='Gandgof:BAEANQAECgQIBQABNQAECgoKKwAJAH4bAA==.',
Go='Gof:BAEBNQAECn8jAAMKAAoKbBpyMAAiAgqODQAABgBTAHUNAAAFAFYAfw0AAAMAVgCpDQAAAwBJAFwNAAACAEgAXQ0AAAEARgBlDQAABQBLAKQNAAAGAD4AMw0AAAIARQC5DQAAAgAQAAoACQpNHXIwACICCY4NAAAEAFMAdQ0AAAUAVgB/DQAAAwBWAKkNAAADAEkAXA0AAAIASABdDQAAAQBGAGUNAAACAEsApA0AAAQAPgAzDQAAAQBFAAsABQo8DidbAMcABY4NAAACACYAZQ0AAAMAMwCkDQAAAgAmADMNAAABAAgAuQ0AAAIAEAABNQAECgoKKwAJAH4bAA==.Gofsham:BAEBNQAECn8rAAMJAAoKfhvHOwCGAgqODQAABQA9AHUNAAAEAGEAfw0AAAQAMQCpDQAABgBRAFwNAAAFAEwAXQ0AAAIAQwBlDQAABQA0AKQNAAAGAE4AMw0AAAMASQC5DQAAAwAuAAkACQoEG8c7AIYCCY4NAAAEAD0AdQ0AAAMAYQB/DQAAAgAxAKkNAAADAFEAXA0AAAIATABdDQAAAQBDAGUNAAABADQAMw0AAAMASQC5DQAAAQAuAAwACQqQEudVAKQBCY4NAAABAAIAdQ0AAAEAFAB/DQAAAgBEAKkNAAADAD8AXA0AAAMAYABdDQAAAQAYAGUNAAAEABIApA0AAAYAPwC5DQAAAgBFAAAA.',
Gr='Gripymcgripy:BAEANQAECgcICAABNQAFFAYIFQANAEwaAA==.',
['Gö']='Göffles:BAEANQAECgcIEAABNQAECgoKKwAJAH4bAA==.',
['Gø']='Gøf:BAEANQAECggIDAABNQAECgoKKwAJAH4bAA==.Gøffles:BAEANQAECgQIBAABNQAECgoKKwAJAH4bAA==.',
Ha='Hawa:BAEBNQAECn8pAAMJAAkKoB+2LAAVAgmODQAABwBYAHUNAAAFAFgAfw0AAAYAUwCpDQAABQBVAFwNAAADAFEAZQ0AAAMAQwCkDQAABABLADMNAAAFAFsAuQ0AAAMATwAJAAkKoB+2LAAVAgmODQAABwBYAHUNAAAFAFgAfw0AAAYAUwCpDQAABQBVAFwNAAADAFEAZQ0AAAMAQwCkDQAABABLADMNAAAEAFsAuQ0AAAMATwAMAAEKFRDlIQEsAAEzDQAAAQApAAE1AAQKCgogAAMAsxkA.',
Ma='Manaplz:BAEANQABCgYIDAABNQAECggIGAAEALYaAA==.',
Pa='Pandomedic:BAEBNQAECn8jAAIOAAkKPwuOjABwAQmODQAABwAyAHUNAAAGADYAfw0AAAUAMwCpDQAABgAmAFwNAAAEAA8AXQ0AAAIAEQBlDQAAAQAIADMNAAADAA4AuQ0AAAEACAAOAAkKPwuOjABwAQmODQAABwAyAHUNAAAGADYAfw0AAAUAMwCpDQAABgAmAFwNAAAEAA8AXQ0AAAIAEQBlDQAAAQAIADMNAAADAA4AuQ0AAAEACAAAAA==.',
Sh='Shaihardt:BAEANQAECggICwABNQAECgoKPQAPAMARAA==.Shaimee:BAEANQAECgUIBgABNQAECgoKPQAPAMARAA==.Shaî:BAEBNQAECn89AAQPAAoKwBFJYwDuAQqODQAACQAqAHUNAAAGACEAfw0AAAYASQCpDQAABwBBAFwNAAAFABQAXQ0AAAUAJABlDQAABgAvAKQNAAAHAB0AMw0AAAcAPQC5DQAAAwAtAA8ACgrAEUljAO4BCo4NAAAHACoAdQ0AAAUAIQB/DQAABQBJAKkNAAAFAEEAXA0AAAQAFABdDQAABAAkAGUNAAAEAC8ApA0AAAMAHQAzDQAABgA9ALkNAAABAC0ACAAICuYRPyMAPwEIdQ0AAAEAOAB/DQAAAQAQAKkNAAABACYAXA0AAAEAMQBdDQAAAQAhAKQNAAADADgAMw0AAAEAKwC5DQAAAQApAAcABQrgC67kAAABBY4NAAACABcAqQ0AAAEAGgBlDQAAAgAlAKQNAAABAC0AuQ0AAAEAEwAAAA==.',
St='Stemihunter:BAEANQAECgUIDAABNQAECgkJIwAOAD8LAA==.Stemislayer:BAEANQADCgYIBgABNQAECgkJIwAOAD8LAA==.Strzyga:BAECNQAFFH8KAAIQAAQKqgdvEACvAASODQAABQAhAHUNAAABAAQAfw0AAAEALQCpDQAAAwAUABAABAqqB28QAK8ABI4NAAAFACEAdQ0AAAEABAB/DQAAAQAtAKkNAAADABQANQAECn9LAAMQAAoKNBqhHwCdAgAQAAoK9RmhHwCdAgARAAcK8xFLNACgAQAAAA==.',
Su='Superbwe:BAEANQAECgQICQABNQAECgoKIAADALMZAA==.',
Th='Thorgrihm:BAEBNQAECn8XAAIJAAgKFRKVdQDAAQiODQAABQBIAHUNAAAEAEUAfw0AAAMAPgCpDQAAAgBKAFwNAAABADoAZQ0AAAMAAQCkDQAAAgABADMNAAADAEgACQAIChUSlXUAwAEIjg0AAAUASAB1DQAABABFAH8NAAADAD4AqQ0AAAIASgBcDQAAAQA6AGUNAAADAAEApA0AAAIAAQAzDQAAAwBIAAE1AAUUBAgEAAEAAAAA.Threslor:BAEBNQAECn8tAAIRAAoKEh96FwCiAgqODQAABQBcAHUNAAAEAFoAfw0AAAQAYQCpDQAABgBaAFwNAAAEAFMAXQ0AAAMAPgBlDQAABQBYAKQNAAAFAEMAMw0AAAUAVwC5DQAABAA8ABEACgoSH3oXAKICCo4NAAAFAFwAdQ0AAAQAWgB/DQAABABhAKkNAAAGAFoAXA0AAAQAUwBdDQAAAwA+AGUNAAAFAFgApA0AAAUAQwAzDQAABQBXALkNAAAEADwAAAA=.',
Vr='Vrah:BAEANQAECggICAABNQAECgoKKwAJAH4bAA==.',
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
