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

local lookup = {'Warrior-Arms','DeathKnight-Blood','DeathKnight-Frost','Monk-Brewmaster','Monk-Windwalker','Unknown-Unknown','Druid-Restoration','Mage-Arcane','Paladin-Retribution','Paladin-Holy','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Shaman-Restoration','Warrior-Protection','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Feral','Shaman-Elemental','Druid-Balance','Shaman-Enhancement','DemonHunter-Devourer','Priest-Shadow','Priest-Holy','Warlock-Destruction','Paladin-Protection','Hunter-BeastMastery',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=53,date='2026-10-27',data={Ar='Architwo:BAEANQAECgUICgABNQAFFAkJIAABACEfAA==.',
As='Astaren:BAEANQAECgYIEAAAAA==.',
Br='Bryl:BAECNQAFFH8VAAICAAcKGBtjCADaAQeODQAABQA7AHUNAAAEAFAAfw0AAAMAQgCpDQAABQBKAFwNAAABAD8AXQ0AAAEARAAzDQAAAgA0AAIABwoYG2MIANoBB44NAAAFADsAdQ0AAAQAUAB/DQAAAwBCAKkNAAAFAEoAXA0AAAEAPwBdDQAAAQBEADMNAAACADQANQAECn8mAAMCAAoKIR4dOwAYAgACAAoK5RwdOwAYAgADAAUK/xMvRgD+AAAAAA==.Brylic:BAECNQAFFH8QAAIEAAUKViDwAACBAQWODQAABQBSAHUNAAAEAE0Afw0AAAIAOgCpDQAABABQAFwNAAABAFoABAAFClYg8AAAgQEFjg0AAAUAUgB1DQAABABNAH8NAAACADoAqQ0AAAQAUABcDQAAAQBaADUABAp/NgADBAAKCoAiMAQAOgMABAAKCoAiMAQAOgMABQAHChkb1hEAyAEAATUABRQHCBUAAgAYGwA=.Brylicet:BAEANQADCgQIBAABNQAFFAcIFQACABgbAA==.',
Ca='Captpando:BAEANQAECggICQABNQABCgIIAgAGAAAAAA==.',
Co='Coolshirtbra:BAEANQAECgQIBAABNQAECgoKPAAHAMAeAA==.',
Da='Dantius:BAEANQADCggIDAABNQAECgoKOgAIAMEWAA==.Darkorin:BAEBNQAECn84AAMJAAoKeCZDAwBsAwqODQAACQBjAHUNAAAGAGMAfw0AAAYAXwCpDQAABwBjAFwNAAAFAFwAXQ0AAAUAYwBlDQAACABjAKQNAAAEAGMAMw0AAAQAYwC5DQAAAgBjAAkACgp4JkMDAGwDCo4NAAAJAGMAdQ0AAAYAYwB/DQAABQBfAKkNAAAHAGMAXA0AAAUAXABdDQAABQBjAGUNAAAIAGMApA0AAAQAYwAzDQAAAwBjALkNAAACAGMACgACCtoXZv0AgQACfw0AAAEAQwAzDQAAAQA2AAAA.',
Dr='Dragore:BAECNQAFFH8JAAIFAAQKwBDCBwC9AASODQAABABJAHUNAAABACcAfw0AAAEAGACpDQAAAwAPAAUABArAEMIHAL0ABI4NAAAEAEkAdQ0AAAEAJwB/DQAAAQAYAKkNAAADAA8ANQAECn80AAIFAAoKaSSoBACIAwAFAAoKaSSoBACIAwAAAA==.',
Fo='Foxorcism:BAEANQADCgcIDgABNQAECgQIBgAGAAAAAA==.Foxrocket:BAEANQADCgIIAgABNQAECgQIBgAGAAAAAA==.Foxwu:BAEANQAECgQIBgAAAA==.',
Fr='Fries:BAECNQAFFH8cAAMLAAcKohtvAwApAgeODQAABgBGAHUNAAAFAFsAfw0AAAQAJACpDQAABgBcAFwNAAACAFsAXQ0AAAEABwAzDQAABAA0AAsABwqiG28DACkCB44NAAADAEYAdQ0AAAQAWwB/DQAAAwAkAKkNAAAGAFwAXA0AAAIAWwBdDQAAAQAHADMNAAADADQADAAECksUWgoANQEEjg0AAAMAJwB1DQAAAQBAAH8NAAABAAQAMw0AAAEADwA1AAQKfzEAAwwACgq+JO4FACMDAAsACgr2I8UIAEwDAAwACgqXI+4FACMDAAE1AAQKCAgRAAYAAAAA.',
Ga='Gardenweed:BAEANQAECgUICQAAAA==.',
Gu='Guthynn:BAEBNQAECn8jAAMNAAoKVSVdAADSAwqODQAABABhAHUNAAAEAGIAfw0AAAUAYQCpDQAABgBeAFwNAAAEAGEAXQ0AAAIAXABlDQAAAgBaAKQNAAAFAGMAMw0AAAEAXAC5DQAAAgBeAA0ACgpVJV0AANIDCo4NAAAEAGEAdQ0AAAQAYgB/DQAABQBhAKkNAAAGAF4AXA0AAAQAYQBdDQAAAgBcAGUNAAACAFoApA0AAAMAYwAzDQAAAQBcALkNAAACAF4ACwABCqIYV5oASgABpA0AAAIAPwAAAA==.',
Ha='Havècks:BAEANQAECgUIBQAAAA==.',
Ir='Irrogenia:BAEBNQAECn8qAAIOAAkKOB2oLACvAgmODQAABwBZAHUNAAAGAFkAfw0AAAYAVACpDQAABQBZAFwNAAAGAFUAXQ0AAAUAPgBlDQAAAwA3ADMNAAADAEQAuQ0AAAEALgAOAAkKOB2oLACvAgmODQAABwBZAHUNAAAGAFkAfw0AAAYAVACpDQAABQBZAFwNAAAGAFUAXQ0AAAUAPgBlDQAAAwA3ADMNAAADAEQAuQ0AAAEALgAAAA==.',
Kc='Kcmndr:BAEANQAECgYICgABNQAFFAoKLQAIAFseAA==.',
La='Lariàs:BAECNQAFFH8cAAIPAAcK0h95AABhAgeODQAABgBgAHUNAAAFAFEAfw0AAAQATQCpDQAABABdAFwNAAACAFQAXQ0AAAEAMwAzDQAABgBhAA8ABwrSH3kAAGECB44NAAAGAGAAdQ0AAAUAUQB/DQAABABNAKkNAAAEAF0AXA0AAAIAVABdDQAAAQAzADMNAAAGAGEANQAECn89AAMPAAoKviMqAwBxAwAPAAoKviMqAwBxAwABAAUKgARsLgF3AAAAAA==.',
Li='Lidariel:BAEANQAECgYICAABNQAECgoKHwAQAOUSAA==.Lidathra:BAEBNQAECn8fAAMQAAoK5RKxGgAaAgqODQAABABCAHUNAAACAA4Afw0AAAIAJQCpDQAABABKAFwNAAADADYAXQ0AAAQALgBlDQAABQBEAKQNAAADACEAMw0AAAMAJwC5DQAAAQAvABAACgrlErEaABoCCo4NAAADAEIAdQ0AAAIADgB/DQAAAgAlAKkNAAADAEoAXA0AAAMANgBdDQAABAAuAGUNAAAFAEQApA0AAAMAIQAzDQAAAgAnALkNAAABAC8AEQADClsVGy4ArgADjg0AAAEAMACpDQAAAQA8ADMNAAABACQAAAA=.Lidishi:BAEANQAECgQIBwABNQAECgoKHwAQAOUSAA==.Lilgup:BAECNQAFFH8JAAQQAAUKFxLRDgAXAQWODQAAAgASAHUNAAABABMAfw0AAAIAHwCpDQAAAgBWADMNAAACAEsAEAAECikO0Q4AFwEEjg0AAAEAEgB1DQAAAQATAH8NAAACAB8AMw0AAAIASwARAAIK3Q3mDAB9AAKODQAAAQA0AKkNAAABABIAEgABCmYWGw0APwABqQ0AAAEAOQA1AAQKfyIABBAACQobGyMPALYCABAACQobGyMPALYCABEABArvHyskACABABIAAwq+I3ISAAsBAAAA.',
Lo='Lochru:BAEBNQAECn8iAAITAAkK+hkGCQC9AgmODQAABABNAHUNAAAFAFQAfw0AAAUAVwCpDQAABQBXAFwNAAAEAE0AXQ0AAAMAPABlDQAAAwApAKQNAAABACQAMw0AAAQAWgATAAkK+hkGCQC9AgmODQAABABNAHUNAAAFAFQAfw0AAAUAVwCpDQAABQBXAFwNAAAEAE0AXQ0AAAMAPABlDQAAAwApAKQNAAABACQAMw0AAAQAWgAAAA==.Lotide:BAECNQAFFH8PAAMOAAgKTw8XBgAGAgiODQAAAgAEAHUNAAACACoAfw0AAAIAMwCpDQAAAgAZAFwNAAACADMAXQ0AAAEATgBlDQAAAQANADMNAAADAC4ADgAICk8PFwYABgIIjg0AAAEABAB1DQAAAgAqAH8NAAACADMAqQ0AAAEAGQBcDQAAAgAzAF0NAAABAE4AZQ0AAAEADQAzDQAAAgAuABQAAwpHEGUbAOYAA44NAAABABMAqQ0AAAEAPwAzDQAAAQA6ADUABAp/FgADFAAKCnAiwREAgwIAFAAJCs0hwREAgwIADgADCokNu/kAdwAAATUABRQFCAkAEAAXEgA=.Lowz:BAEANQAFFAYIAQAAAA==.',
Mi='Migwangomage:BAECNQAFFH8GAAIIAAQKUxuqJwBLAQSODQAAAgBfAHUNAAABADMAfw0AAAEAAgCpDQAAAgA+AAgABApTG6onAEsBBI4NAAACAF8AdQ0AAAEAMwB/DQAAAQACAKkNAAACAD4ANQAECn82AAIIAAoK2yZUAAALBAAIAAoK2yZUAAALBAABNQAFFAgIBQAVAI8bAA==.Mikmilk:BAEANQAECgYIEwABNQAECgoKPAAHAMAeAA==.Mikronos:BAECNQAFFH8NAAMWAAQKrROrAgDbAASODQAABQAuAHUNAAADACAAfw0AAAEAHgCpDQAABABIABQAAwqOE2EZAPcAA44NAAADAC0AdQ0AAAIAIACpDQAAAgBIABYABAoYEasCANsABI4NAAACAC4AdQ0AAAEAHQB/DQAAAQAeAKkNAAACADcANQAECn8lAAMUAAkKUh5GKwDSAgAUAAkKARxGKwDSAgAWAAUKBRaEHgB4AQABNQAECgoKPAAHAMAeAA==.',
['Mà']='Màsterofhunt:BAEANQAECgYIEgAAAA==.Màsterofwar:BAEANQAECgMIAwABNQAECgYIEgAGAAAAAA==.',
Ne='Neodefender:BAECNQAFFH8TAAIKAAYKDCQCAwATAgaODQAABQBPAHUNAAAEAFwAfw0AAAMAYwCpDQAABQBeAFwNAAABAGMAMw0AAAEAWAAKAAYKDCQCAwATAgaODQAABQBPAHUNAAAEAFwAfw0AAAMAYwCpDQAABQBeAFwNAAABAGMAMw0AAAEAWAA1AAQKfzAAAgoACgphJYwEAK0DAAoACgphJYwEAK0DAAAA.',
No='Nosram:BAEBNQAECn80AAIXAAoKwx2ADQANAwqODQAACABYAHUNAAAIAGEAfw0AAAcAYwCpDQAACABcAFwNAAAHAE4AXQ0AAAYAYQBlDQAABABJAKQNAAABAB0AMw0AAAIAXwC5DQAAAQA0ABcACgrDHYANAA0DCo4NAAAIAFgAdQ0AAAgAYQB/DQAABwBjAKkNAAAIAFwAXA0AAAcATgBdDQAABgBhAGUNAAAEAEkApA0AAAEAHQAzDQAAAgBfALkNAAABADQAAAA=.',
Nu='Nubbz:BAECNQAFFH8QAAIWAAYKAh1FAQAYAgaODQAAAwBKAHUNAAADAFoAfw0AAAIAGQCpDQAAAgBFAFwNAAABAD4AMw0AAAUAQAAWAAYKAh1FAQAYAgaODQAAAwBKAHUNAAADAFoAfw0AAAIAGQCpDQAAAgBFAFwNAAABAD4AMw0AAAUAQAA1AAQKf0wAAxYACgrjJTwBADwDABYACgrjJTwBADwDABQAAQo/C/o2ATMAAAAA.',
Ny='Nyfaria:BAEBNQAECn9AAAIEAAoKihInBQDVAQqODQAACgA1AHUNAAAJADgAfw0AAAgAOACpDQAACgA5AFwNAAAHADcAXQ0AAAUANwBlDQAABwAvAKQNAAADACEAMw0AAAMAFQC5DQAAAgAVAAQACgqKEicFANUBCo4NAAAKADUAdQ0AAAkAOAB/DQAACAA4AKkNAAAKADkAXA0AAAcANwBdDQAABQA3AGUNAAAHAC8ApA0AAAMAIQAzDQAAAwAVALkNAAACABUAAAA=.',
Or='Orsp:BAECNQAFFH8fAAMYAAcKaxUbAwBjAQeODQAABwBSAHUNAAAEAEYAfw0AAAUAOwCpDQAABQBJAFwNAAABACUAXQ0AAAEACgAzDQAACAAiABgABwprFRsDAGMBB44NAAAGAFIAdQ0AAAMARgB/DQAAAQA7AKkNAAADAEkAXA0AAAEAJQBdDQAAAQAKADMNAAAFACIAGQAFCroMmBQAYQEFjg0AAAEALQB1DQAAAQACAH8NAAAEAEkAqQ0AAAIAGAAzDQAAAwAQADUABAp/OwADGAAKCrMkWAQAkwMAGAAKCrMkWAQAkwMAGQAJCkoTkWcA6AEAAAA=.Orspp:BAEBNQAECn8kAAMYAAkKuh6kGQCBAgmODQAABwBhAHUNAAAGAGEAfw0AAAYAXQCpDQAABQBdAFwNAAADAFUAXQ0AAAIAJQBlDQAAAgBJAKQNAAAEAEEAMw0AAAEAIwAYAAcKkR+kGQCBAgeODQAABwBhAHUNAAAEAGEAfw0AAAUAXQCpDQAAAwBdAFwNAAACAFUAXQ0AAAEAJQBlDQAAAgBJABkABwo+D7+JAHkBB3UNAAACAFIAfw0AAAEAKwCpDQAAAgAeAFwNAAABAAoAXQ0AAAEALQCkDQAABAAqADMNAAABABEAATUABRQHCB8AGABrFQA=.',
Pa='Pakk:BAEBNQAECn8oAAMCAAgKLBiTNgAwAgiODQAACABSAHUNAAAIAEoAfw0AAAcATACpDQAABgBMAFwNAAADAFMAXQ0AAAEAIgAzDQAABgBSALkNAAABABMAAgAHCoMbkzYAMAIHjg0AAAgAUgB1DQAACABKAH8NAAAHAEwAqQ0AAAYATABcDQAAAwBTAF0NAAABACIAMw0AAAYAUgADAAEKdgdxiwAzAAG5DQAAAQATAAAA.Pandotides:BAEANQAECggIEgABNQABCgIIAgAGAAAAAA==.Papadefensve:BAEANQAECgIIAgAAAA==.',
Ra='Razamon:BAEBNQAECn8jAAMOAAoKpRYfMQCcAgqODQAABgBPAHUNAAAEADsAfw0AAAQAWwCpDQAABABiAFwNAAADAEEAXQ0AAAIAOQBlDQAABAAdAKQNAAADAA4AMw0AAAQARgC5DQAAAQANAA4ACgqlFh8xAJwCCo4NAAAFAE8AdQ0AAAQAOwB/DQAABABbAKkNAAAEAGIAXA0AAAMAQQBdDQAAAgA5AGUNAAAEAB0ApA0AAAMADgAzDQAAAwBGALkNAAABAA0AFAACCuAHfcQANQACjg0AAAEAFAAzDQAAAQAYAAAA.',
Re='Recurse:BAEANQADCggICAABNQAFFAgIEQAaAMANAA==.',
Ru='Runehaven:BAEANQADCggICAABNQAFFAEIAQAGAAAAAA==.',
Sa='Sairal:BAEANQAECgQICQABNQAFFAcIHAAPANIfAA==.Sargala:BAEANQAECgQICAAAAA==.',
Sc='Scootybooty:BAEANQAECgQIDwABNQAECgkJFQAYACsRAA==.Scootypriest:BAEBNQAECn8VAAIYAAkKKxF/JgD6AQmODQAABABBAHUNAAADAC8Afw0AAAMAUQCpDQAAAwBCAFwNAAABACsAXQ0AAAEABwBlDQAAAQAvADMNAAADADUAuQ0AAAIAHgAYAAkKKxF/JgD6AQmODQAABABBAHUNAAADAC8Afw0AAAMAUQCpDQAAAwBCAFwNAAABACsAXQ0AAAEABwBlDQAAAQAvADMNAAADADUAuQ0AAAIAHgAAAA==.',
Sm='Smitehaven:BAEBNQAECn8fAAIbAAkKeiD0DADMAgmODQAABgBTAHUNAAAEAFkAfw0AAAQAXgCpDQAABABbAFwNAAAEAFwAXQ0AAAMAVABlDQAAAgBQADMNAAADAEsAuQ0AAAEAOwAbAAkKeiD0DADMAgmODQAABgBTAHUNAAAEAFkAfw0AAAQAXgCpDQAABABbAFwNAAAEAFwAXQ0AAAMAVABlDQAAAgBQADMNAAADAEsAuQ0AAAEAOwABNQAFFAEIAQAGAAAAAA==.',
Tc='Tchoff:BAEANQAECggICQABNQAFFAgIHgABAIkeAA==.',
Th='Thez:BAEANQAECgUICwABNQAECgoKLgAPAEchAA==.Thezadin:BAEANQAECgQIBAABNQAECgoKLgAPAEchAA==.Thezdin:BAEBNQAECn8uAAIPAAoKRyFIAwBsAwqODQAACABXAHUNAAAEAF8Afw0AAAQAXgCpDQAABQBiAFwNAAAEAFwAXQ0AAAUAWgBlDQAABgBRAKQNAAAEAEUAMw0AAAUAUQC5DQAAAQBCAA8ACgpHIUgDAGwDCo4NAAAIAFcAdQ0AAAQAXwB/DQAABABeAKkNAAAFAGIAXA0AAAQAXABdDQAABQBaAGUNAAAGAFEApA0AAAQARQAzDQAABQBRALkNAAABAEIAAAA=.',
Ve='Velohm:BAEANQAECgMIBgAAAA==.',
Wi='Wildbless:BAECNQAFFH8bAAIbAAgK0AkPBACiAQiODQAABgBCAHUNAAAEAAsAfw0AAAQAHgCpDQAABAAjAFwNAAACAAQAXQ0AAAEAAgBlDQAAAQAdADMNAAAFACoAGwAICtAJDwQAogEIjg0AAAYAQgB1DQAABAALAH8NAAAEAB4AqQ0AAAQAIwBcDQAAAgAEAF0NAAABAAIAZQ0AAAEAHQAzDQAABQAqADUABAp/NwACGwAKCo4dmQ8AowIAGwAKCo4dmQ8AowIAATUABAoECAoABgAAAAA=.Wildform:BAEANQAECgIIAwABNQAECgQICgAGAAAAAA==.Wildkill:BAEBNQAECn8WAAIcAAcKjiMyUwB3AgeODQAABABjAHUNAAADAF4Afw0AAAMAOwCpDQAAAwBTAFwNAAACAEwAZQ0AAAMAYwCkDQAABABcABwABwqOIzJTAHcCB44NAAAEAGMAdQ0AAAMAXgB/DQAAAwA7AKkNAAADAFMAXA0AAAIATABlDQAAAwBjAKQNAAAEAFwAATUABAoECAoABgAAAAA=.Wildshield:BAEANQAECgQICgAAAA==.',
Wr='Wrècks:BAEANQAECgYICAABNQAECgUIBQAGAAAAAA==.Wrèckstorm:BAECNQAFFH8GAAIWAAMK6xVaAwCpAAOODQAABABOAHUNAAABABAAqQ0AAAEASAAWAAMK6xVaAwCpAAOODQAABABOAHUNAAABABAAqQ0AAAEASAA1AAQKfz0AAxYACgofIUgEALcCABYACgofIUgEALcCABQABAoPGge1ACgBAAE1AAQKBQgFAAYAAAAA.',
Zi='Zick:BAEANQAFFAYIAQAAAA==.',
Zo='Zoe:BAEANQAECgQICgAAAA==.Zogle:BAECNQAFFH8YAAICAAgKcBWdBAA0AgiODQAABQBOAHUNAAADAB0Afw0AAAMAOwCpDQAABQBPAFwNAAACADwAXQ0AAAEAJABlDQAAAQAsADMNAAAEAGAAAgAICnAVnQQANAIIjg0AAAUATgB1DQAAAwAdAH8NAAADADsAqQ0AAAUATwBcDQAAAgA8AF0NAAABACQAZQ0AAAEALAAzDQAABABgADUABAp/NgACAgAKCv4jNwsAWQMAAgAKCv4jNwsAWQMAATUABAoECAoABgAAAAA=.',
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
