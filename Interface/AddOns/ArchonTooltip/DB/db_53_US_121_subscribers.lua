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

local lookup = {'DeathKnight-Blood','Monk-Brewmaster','Druid-Restoration','Paladin-Retribution','Paladin-Holy','Monk-Windwalker','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Mage-Arcane','Warrior-Protection','Warrior-Arms','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Feral','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Warlock-Destruction','Paladin-Protection','Hunter-BeastMastery','Shaman-Enhancement',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=53,date='2026-09-29',data={As='Astaren:BAEANQAECgMIBgAAAA==.',
Br='Bryl:BAECNQAFFIEKAAIBAAUKvxDLCgBMAQWODQAAAwA3AHUNAAACABwAfw0AAAEAGACpDQAAAwA1ADMNAAABADQAAQAFCr8QywoATAEFjg0AAAMANwB1DQAAAgAcAH8NAAABABgAqQ0AAAMANQAzDQAAAQA0ADUABAqBGAACAQAJCo8bIysAMgIAAQAJCo8bIysAMgIAAAA=.Brylic:BAEBNQAECoEmAAICAAkKHCICAwBEAwmODQAABgBXAHUNAAAFAFgAfw0AAAUAWgCpDQAABQBZAFwNAAAEAFkAXQ0AAAMAXwBlDQAABQBaAKQNAAACADwAMw0AAAMAXQACAAkKHCICAwBEAwmODQAABgBXAHUNAAAFAFgAfw0AAAUAWgCpDQAABQBZAFwNAAAEAFkAXQ0AAAMAXwBlDQAABQBaAKQNAAACADwAMw0AAAMAXQABNQAFFAUICgABAL8QAA==.Brylicet:BAEANQADCgQIBAABNQAFFAUICgABAL8QAA==.',
Co='Coldasfrick:BAEANQAECggIEwAAAA==.Coolshirtbra:BAEANQAECgQIBAABNQAECgcIGQADAEkhAA==.',
Da='Darkorin:BAEBNQAECoEmAAMEAAkKXyb+AQDqAwmODQAABQBjAHUNAAAFAGMAfw0AAAUAXwCpDQAABQBjAFwNAAAEAFwAXQ0AAAQAYwBlDQAABABjAKQNAAACAGMAMw0AAAQAYwAEAAkKXyb+AQDqAwmODQAABQBjAHUNAAAFAGMAfw0AAAQAXwCpDQAABQBjAFwNAAAEAFwAXQ0AAAQAYwBlDQAABABjAKQNAAACAGMAMw0AAAMAYwAFAAIK2hfCzgCEAAJ/DQAAAQBDADMNAAABADYAAAA=.',
Dr='Dragore:BAEBNQAECoEiAAIGAAkKryNLAwCOAwmODQAABABbAHUNAAAEAGAAfw0AAAQAVQCpDQAABQBeAFwNAAAEAGMAXQ0AAAQAXABlDQAABABZAKQNAAAEAEsAMw0AAAEAYQAGAAkKryNLAwCOAwmODQAABABbAHUNAAAEAGAAfw0AAAQAVQCpDQAABQBeAFwNAAAEAGMAXQ0AAAQAXABlDQAABABZAKQNAAAEAEsAMw0AAAEAYQAAAA==.',
Fo='Foxorcism:BAEANQADCgcIDgABNQAECgQIBQAHAAAAAA==.Foxrocket:BAEANQADCgIIAgABNQAECgQIBQAHAAAAAA==.Foxwu:BAEANQAECgQIBQAAAA==.',
Fr='Frickntotems:BAEANQAECgEIAQABNQAECggIEwAHAAAAAA==.Fries:BAECNQAFFIERAAMIAAUK9BY6AwCuAQWODQAABAApAHUNAAADAEkAfw0AAAIAJACpDQAABABZADMNAAAEADQACAAFCvQWOgMArgEFjg0AAAIAKQB1DQAAAwBJAH8NAAACACQAqQ0AAAQAWQAzDQAAAwA0AAkAAgq8CnwLAKAAAo4NAAACACcAMw0AAAEADwA1AAQKgSAAAggACQq+JH0DAH8DAAgACQq+JH0DAH8DAAE1AAQKCAgLAAcAAAAA.',
Ga='Gardenweed:BAEANQABCgYIDAABNQAECgQIBAAHAAAAAA==.',
Gu='Guthynn:BAEBNQAECoEYAAMKAAkKYSGLAgAHAwmODQAAAwBhAHUNAAADAFkAfw0AAAQAXACpDQAABQBeAFwNAAADAFoAXQ0AAAIAXABlDQAAAQA4AKQNAAACAD8AMw0AAAEAXAAKAAgKeSKLAgAHAwiODQAAAwBhAHUNAAADAFkAfw0AAAQAXACpDQAABQBeAFwNAAADAFoAXQ0AAAIAXABlDQAAAQA4ADMNAAABAFwACAABCqIYY24ASwABpA0AAAIAPwAAAA==.',
Ha='Havècks:BAEANQADCggICAAAAA==.',
Ir='Irrogenia:BAEANQAECgYICwAAAA==.',
Kc='Kcmndr:BAEANQAECgYICAABNQAFFAcIHQALADsjAA==.',
La='Lariàs:BAECNQAFFIEKAAIMAAUKIR26AADVAQWODQAAAgBgAHUNAAACAE8Afw0AAAEAJwCpDQAAAgBIADMNAAADAFQADAAFCiEdugAA1QEFjg0AAAIAYAB1DQAAAgBPAH8NAAABACcAqQ0AAAIASAAzDQAAAwBUADUABAqBMAADDAAJCm4jugEAiwMADAAJCm4jugEAiwMADQAFCukC+/kAegAAAAA=.',
Li='Lidariel:BAEANQADCgUICQABNQAECgcIEAAHAAAAAA==.Lidathra:BAEANQAECgcIEAAAAA==.Lidishi:BAEANQADCgYIBgABNQAECgcIEAAHAAAAAA==.Lilgup:BAECNQAFFIEJAAQOAAUKFxITCgAvAQWODQAAAgASAHUNAAABABMAfw0AAAIAHwCpDQAAAgBWADMNAAACAEsADgAECikOEwoALwEEjg0AAAEAEgB1DQAAAQATAH8NAAACAB8AMw0AAAIASwAPAAIK3Q3sCQCGAAKODQAAAQA0AKkNAAABABIAEAABCmYWVggASAABqQ0AAAEAOQA1AAQKgSIABA4ACQobGxALAM8CAA4ACQobGxALAM8CAA8ABAqRGwQeADABABAAAwqZI34NABcBAAAA.',
Lo='Lochru:BAEBNQAECoEfAAIRAAkKshq0BwB+AgmODQAABABNAHUNAAAEAFQAfw0AAAQASwCpDQAABABGAFwNAAAEAE0AXQ0AAAMAPABlDQAAAwApAKQNAAABACQAMw0AAAQAWgARAAkKshq0BwB+AgmODQAABABNAHUNAAAEAFQAfw0AAAQASwCpDQAABABGAFwNAAAEAE0AXQ0AAAMAPABlDQAAAwApAKQNAAABACQAMw0AAAQAWgAAAA==.Lotide:BAEBNQAFFIENAAMSAAcKbw6WAgAvAgeODQAAAgAEAHUNAAACACoAfw0AAAIAMwCpDQAAAgAZAFwNAAACADMAXQ0AAAEATgAzDQAAAgAEABIABwpvDpYCAC8CB44NAAABAAQAdQ0AAAIAKgB/DQAAAgAzAKkNAAABABkAXA0AAAIAMwBdDQAAAQBOADMNAAABAAQAEwADCnsS8xAA7AADjg0AAAEAEwCpDQAAAQA/ADMNAAABADoAATUABRQFCAkADgAXEgA=.',
Mi='Migwangomage:BAEBNQAECoEXAAILAAkKFSYNAQD0AwmODQAAAgBjAHUNAAADAGMAfw0AAAMAXgCpDQAAAgBjAFwNAAADAGMAXQ0AAAMAYwBlDQAAAgBWAKQNAAADAGIAMw0AAAIAYwALAAkKFSYNAQD0AwmODQAAAgBjAHUNAAADAGMAfw0AAAMAXgCpDQAAAgBjAFwNAAADAGMAXQ0AAAMAYwBlDQAAAgBWAKQNAAADAGIAMw0AAAIAYwABNQAECgkJTAAUAOYmAA==.Mikmilk:BAEANQAECgYIDQABNQAECgcIGQADAEkhAA==.Mikronos:BAEBNQAECoEbAAITAAkK8hmKKACjAgmODQAABQBEAHUNAAADADwAfw0AAAMATQCpDQAAAwBNAFwNAAADAC4AXQ0AAAIANgBlDQAAAwBEAKQNAAACADcAMw0AAAMAVgATAAkK8hmKKACjAgmODQAABQBEAHUNAAADADwAfw0AAAMATQCpDQAAAwBNAFwNAAADAC4AXQ0AAAIANgBlDQAAAwBEAKQNAAACADcAMw0AAAMAVgABNQAECgcIGQADAEkhAA==.',
['Mà']='Màsterofhunt:BAEANQAECgYICwAAAA==.Màsterofwar:BAEANQAECgIIAgABNQAECgYICwAHAAAAAA==.',
Ne='Neodefender:BAEBNQAECoEfAAIFAAkKpiDNCABnAwmODQAABQBhAHUNAAAFAGEAfw0AAAUAYwCpDQAABgBjAFwNAAADAGAAXQ0AAAIAYQBlDQAAAgBIAKQNAAABACwAMw0AAAIALwAFAAkKpiDNCABnAwmODQAABQBhAHUNAAAFAGEAfw0AAAUAYwCpDQAABgBjAFwNAAADAGAAXQ0AAAIAYQBlDQAAAgBIAKQNAAABACwAMw0AAAIALwAAAA==.',
Ny='Nyfaria:BAEBNQAECoElAAICAAgKLg+REACbAQiODQAABgAtAHUNAAAFADEAfw0AAAUANwCpDQAABgAxAFwNAAAFACsAXQ0AAAQAGgBlDQAAAwASADMNAAADABUAAgAICi4PkRAAmwEIjg0AAAYALQB1DQAABQAxAH8NAAAFADcAqQ0AAAYAMQBcDQAABQArAF0NAAAEABoAZQ0AAAMAEgAzDQAAAwAVAAAA.',
Pa='Pakk:BAEANQAECgcIDgAAAA==.Pandotides:BAEANQAECggIDQABNQABCgIIAgAHAAAAAA==.Papadefensve:BAEANQAECgEIAQAAAA==.',
Ra='Razamon:BAEANQAECgcIEQAAAA==.',
Re='Recurse:BAEANQADCggICAABNQAFFAYIDQAVAEkRAA==.',
Ru='Runehaven:BAEANQADCggICAABNQAECgcIDgAHAAAAAA==.',
Sa='Sairal:BAEANQAECgQIBwABNQAFFAUICgAMACEdAA==.Sargala:BAEANQADCggJHgAAAA==.',
Sc='Scootybooty:BAEANQAECgEIAQABNQAECgUIDgAHAAAAAA==.Scootypriest:BAEANQAECgUIDgAAAA==.',
Sm='Smitehaven:BAEANQAECgcIDgAAAA==.',
Tc='Tchoff:BAEANQADCgUIBQABNQAFFAYIFgANACYjAA==.',
Th='Thez:BAEANQAECgUICgABNQAECggIHgAMAI8iAA==.Thezdin:BAEBNQAECoEeAAIMAAgKjyK5AwAeAwiODQAABQBWAHUNAAAEAF8Afw0AAAQAXgCpDQAABABiAFwNAAADAFwAXQ0AAAQAWgBlDQAAAgBMADMNAAAEAEgADAAICo8iuQMAHgMIjg0AAAUAVgB1DQAABABfAH8NAAAEAF4AqQ0AAAQAYgBcDQAAAwBcAF0NAAAEAFoAZQ0AAAIATAAzDQAABABIAAAA.',
Ve='Velohm:BAEANQAECgIJAgAAAA==.',
Wi='Wildbless:BAECNQAFFIEZAAIWAAcKvAkeAgC3AQeODQAABgBCAHUNAAAEAAsAfw0AAAQAHgCpDQAABAAjAFwNAAACAAQAXQ0AAAEAAgAzDQAABAAWABYABwq8CR4CALcBB44NAAAGAEIAdQ0AAAQACwB/DQAABAAeAKkNAAAEACMAXA0AAAIABABdDQAAAQACADMNAAAEABYANQAECoEoAAIWAAkKch44CQDPAgAWAAkKch44CQDPAgABNQAECgQICAAHAAAAAA==.Wildkill:BAEBNQAECoETAAIXAAcKziF9MACaAgeODQAABABjAHUNAAADAF4Afw0AAAMAOwCpDQAAAwBTAFwNAAACAEwAZQ0AAAIAYwCkDQAAAgBcABcABwrOIX0wAJoCB44NAAAEAGMAdQ0AAAMAXgB/DQAAAwA7AKkNAAADAFMAXA0AAAIATABlDQAAAgBjAKQNAAACAFwAATUABAoECAgABwAAAAA=.Wildshield:BAEANQAECgQICAAAAA==.',
Wr='Wrècks:BAEANQAECgYJBwABNQADCggICAAHAAAAAA==.Wrèckstorm:BAEBNQAECoEjAAMYAAgK1Bq7CQCmAgiODQAABgBJAHUNAAAFAFkAfw0AAAUAWQCpDQAABQBFAFwNAAAEAEwAXQ0AAAQALwBlDQAAAgA5ADMNAAAEAC0AGAAICswZuwkApgIIjg0AAAYASQB1DQAABABZAH8NAAAEAFkAqQ0AAAQARQBcDQAAAgA3AF0NAAAEAC8AZQ0AAAIAOQAzDQAABAAtABMABAqFGg6GAD4BBHUNAAABADwAfw0AAAEARwCpDQAAAQA+AFwNAAACAEwAATUAAwoICAgABwAAAAA=.',
Zo='Zoe:BAEANQAECgQICAAAAA==.Zogle:BAECNQAFFIEWAAIBAAcKIhigAQBeAgeODQAABQBOAHUNAAADAB0Afw0AAAMAOwCpDQAABQBPAFwNAAACADwAXQ0AAAEAJAAzDQAAAwBYAAEABwoiGKABAF4CB44NAAAFAE4AdQ0AAAMAHQB/DQAAAwA7AKkNAAAFAE8AXA0AAAIAPABdDQAAAQAkADMNAAADAFgANQAECoEoAAIBAAkKQyQ0BgB9AwABAAkKQyQ0BgB9AwABNQAECgQICAAHAAAAAA==.',
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
