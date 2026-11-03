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

local lookup = {'Warrior-Arms','Monk-Windwalker','DeathKnight-Blood','DeathKnight-Frost','Monk-Brewmaster','Unknown-Unknown','Warlock-Affliction','Druid-Restoration','Mage-Frost','Paladin-Retribution','Paladin-Holy','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','Rogue-Outlaw','Shaman-Restoration','Mage-Arcane','Warrior-Protection','Evoker-Preservation','Evoker-Devastation','Druid-Feral','Druid-Balance','Shaman-Enhancement','DemonHunter-Devourer','Priest-Shadow','Priest-Holy','Warlock-Destruction','Paladin-Protection','Hunter-BeastMastery',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=53,date='2026-11-03',data={Ar='Architwo:BAEANQAECgUICAABNQAFFAkJJgABAJEgAA==.',
As='Astaren:BAEANQAECgYIDwAAAA==.',
Ba='Basin:BAEANQAECgIIAQABNQAFFAQICQACAMAQAA==.',
Br='Bryl:BAECNQAFFH8VAAIDAAcKGBtjCADaAQeODQAABQA7AHUNAAAEAFAAfw0AAAMAQgCpDQAABQBKAFwNAAABAD8AXQ0AAAEARAAzDQAAAgA0AAMABwoYG2MIANoBB44NAAAFADsAdQ0AAAQAUAB/DQAAAwBCAKkNAAAFAEoAXA0AAAEAPwBdDQAAAQBEADMNAAACADQANQAECn8nAAMDAAoKah4dOwAYAgADAAoKLR0dOwAYAgAEAAUK/xNeWQDzAAAAAA==.Brylic:BAECNQAFFH8RAAIFAAYKWyGgAADqAQaODQAABQBSAHUNAAAEAE0Afw0AAAIAOgCpDQAABABQAFwNAAABAFoAXQ0AAAEAXwAFAAYKWyGgAADqAQaODQAABQBSAHUNAAAEAE0Afw0AAAIAOgCpDQAABABQAFwNAAABAFoAXQ0AAAEAXwA1AAQKfzkAAwUACgqsIzAEADoDAAUACgqsIzAEADoDAAIABwoZG/gXALwBAAE1AAUUBwgVAAMAGBsA.Brylicet:BAEANQADCgQIBAABNQAFFAcIFQADABgbAA==.',
Ca='Captpando:BAEANQAECggIEgABNQABCgIIAgAGAAAAAA==.',
Cb='Cbkthree:BAEANQAECgIIAwABNQAFFAgIIwAHADYhAA==.',
Co='Coolshirtbra:BAEANQAECgQIBAABNQAECgoKRQAIAMghAA==.',
Da='Dantius:BAEANQADCggIFAABNQAECgoKOwAJAHwYAA==.Darkorin:BAEBNQAECn9CAAMKAAoK0SZKAQCIAwqODQAACgBjAHUNAAAHAGMAfw0AAAcAXwCpDQAACABjAFwNAAAGAGMAXQ0AAAYAYwBlDQAACQBjAKQNAAAFAGMAMw0AAAUAYwC5DQAAAwBjAAoACgrRJkoBAIgDCo4NAAAKAGMAdQ0AAAcAYwB/DQAABgBfAKkNAAAIAGMAXA0AAAYAYwBdDQAABgBjAGUNAAAJAGMApA0AAAUAYwAzDQAABABjALkNAAADAGMACwACCtoXZv0AgQACfw0AAAEAQwAzDQAAAQA2AAAA.',
Dr='Dragore:BAECNQAFFH8JAAICAAQKwBCrCQC1AASODQAABABJAHUNAAABACcAfw0AAAEAGACpDQAAAwAPAAIABArAEKsJALUABI4NAAAEAEkAdQ0AAAEAJwB/DQAAAQAYAKkNAAADAA8ANQAECn83AAICAAoK8SSoBACIAwACAAoK8SSoBACIAwAAAA==.',
Fo='Foxorcism:BAEANQADCgcIDgABNQAECgQIBQAGAAAAAA==.Foxrocket:BAEANQADCgIIAgABNQAECgQIBQAGAAAAAA==.Foxwu:BAEANQAECgQIBQAAAA==.',
Fr='Fries:BAECNQAFFH8cAAMMAAcKohtvAwApAgeODQAABgBGAHUNAAAFAFsAfw0AAAQAJACpDQAABgBcAFwNAAACAFsAXQ0AAAEABwAzDQAABAA0AAwABwqiG28DACkCB44NAAADAEYAdQ0AAAQAWwB/DQAAAwAkAKkNAAAGAFwAXA0AAAIAWwBdDQAAAQAHADMNAAADADQADQAECksUWgoANQEEjg0AAAMAJwB1DQAAAQBAAH8NAAABAAQAMw0AAAEADwA1AAQKfzYAAw0ACgq+JNQHACoDAAwACgr2I8UIAEwDAA0ACgqXI9QHACoDAAE1AAQKCAgPAAYAAAAA.',
Ga='Galgpal:BAEANQAECgIIAgABNQAFFAgIHgABAIkeAA==.Gardenweed:BAEANQAECgYIDgABNQAECggIFAAOAPgFAA==.',
Gu='Guthynn:BAEBNQAECn8kAAMPAAoKVSVdAADSAwqODQAABABhAHUNAAAEAGIAfw0AAAUAYQCpDQAABgBeAFwNAAAEAGEAXQ0AAAIAXABlDQAAAgBaAKQNAAAFAGMAMw0AAAEAXAC5DQAAAwBeAA8ACgpVJV0AANIDCo4NAAAEAGEAdQ0AAAQAYgB/DQAABQBhAKkNAAAGAF4AXA0AAAQAYQBdDQAAAgBcAGUNAAACAFoApA0AAAMAYwAzDQAAAQBcALkNAAADAF4ADAABCqIYV5oASgABpA0AAAIAPwAAAA==.',
Ha='Havècks:BAEANQAECgUIBQAAAA==.',
Ir='Irro:BAEANQAECgIIAgABNQAECgkJLgAQADgdAA==.Irrogenia:BAEBNQAECn8uAAIQAAkKOB2oLACvAgmODQAABwBZAHUNAAAHAFkAfw0AAAcAVACpDQAABgBZAFwNAAAGAFUAXQ0AAAUAPgBlDQAAAwA3ADMNAAADAEQAuQ0AAAIALgAQAAkKOB2oLACvAgmODQAABwBZAHUNAAAHAFkAfw0AAAcAVACpDQAABgBZAFwNAAAGAFUAXQ0AAAUAPgBlDQAAAwA3ADMNAAADAEQAuQ0AAAIALgAAAA==.',
Kc='Kcmndr:BAEANQAECgYICAABNQAFFAoKNQARAJokAA==.',
La='Lariàs:BAECNQAFFH8cAAISAAcK0h95AABhAgeODQAABgBgAHUNAAAFAFEAfw0AAAQATQCpDQAABABdAFwNAAACAFQAXQ0AAAEAMwAzDQAABgBhABIABwrSH3kAAGECB44NAAAGAGAAdQ0AAAUAUQB/DQAABABNAKkNAAAEAF0AXA0AAAIAVABdDQAAAQAzADMNAAAGAGEANQAECn8+AAMSAAoKviMqAwBxAwASAAoKviMqAwBxAwABAAUKgARsLgF3AAAAAA==.',
Li='Lidariel:BAEANQAECgYIBgABNQAECgoKIAATAOUSAA==.Lidathra:BAEBNQAECn8gAAMTAAoK5RKxGgAaAgqODQAABABCAHUNAAACAA4Afw0AAAIAJQCpDQAABABKAFwNAAADADYAXQ0AAAQALgBlDQAABQBEAKQNAAADACEAMw0AAAMAJwC5DQAAAgAvABMACgrlErEaABoCCo4NAAADAEIAdQ0AAAIADgB/DQAAAgAlAKkNAAADAEoAXA0AAAMANgBdDQAABAAuAGUNAAAFAEQApA0AAAMAIQAzDQAAAgAnALkNAAACAC8AFAADClsVGy4ArgADjg0AAAEAMACpDQAAAQA8ADMNAAABACQAAAA=.Lidishi:BAEANQAECgQIBQABNQAECgoKIAATAOUSAA==.',
Lo='Lochru:BAEBNQAECn8iAAIVAAkK+hkGCQC9AgmODQAABABNAHUNAAAFAFQAfw0AAAUAVwCpDQAABQBXAFwNAAAEAE0AXQ0AAAMAPABlDQAAAwApAKQNAAABACQAMw0AAAQAWgAVAAkK+hkGCQC9AgmODQAABABNAHUNAAAFAFQAfw0AAAUAVwCpDQAABQBXAFwNAAAEAE0AXQ0AAAMAPABlDQAAAwApAKQNAAABACQAMw0AAAQAWgAAAA==.Lowz:BAEANQAFFAYIAQAAAA==.',
Mi='Migwangomage:BAECNQAFFH8GAAIRAAQKUxuqJwBLAQSODQAAAgBfAHUNAAABADMAfw0AAAEAAgCpDQAAAgA+ABEABApTG6onAEsBBI4NAAACAF8AdQ0AAAEAMwB/DQAAAQACAKkNAAACAD4ANQAECn89AAIRAAoK2yZUAAALBAARAAoK2yZUAAALBAABNQAFFAgIBQAWAI8bAA==.Mikmilk:BAEANQAECgYIEgABNQAECgoKRQAIAMghAA==.Mikronos:BAECNQAFFH8NAAMXAAQKrROTAwDVAASODQAABQAuAHUNAAADACAAfw0AAAEAHgCpDQAABABIAA4AAwqOE2EZAPcAA44NAAADAC0AdQ0AAAIAIACpDQAAAgBIABcABAoYEZMDANUABI4NAAACAC4AdQ0AAAEAHQB/DQAAAQAeAKkNAAACADcANQAECn8lAAMOAAkKUh5GKwDSAgAOAAkKARxGKwDSAgAXAAUKBRaEHgB4AQABNQAECgoKRQAIAMghAA==.',
['Mà']='Màsterofhunt:BAEANQAECggIEQAAAA==.Màsterofwar:BAEANQAECgMIAwABNQAECggIEQAGAAAAAA==.',
Ne='Neodefender:BAECNQAFFH8TAAILAAYKDCTABAAIAgaODQAABQBPAHUNAAAEAFwAfw0AAAMAYwCpDQAABQBeAFwNAAABAGMAMw0AAAEAWAALAAYKDCTABAAIAgaODQAABQBPAHUNAAAEAFwAfw0AAAMAYwCpDQAABQBeAFwNAAABAGMAMw0AAAEAWAA1AAQKfzEAAgsACgphJYwEAK0DAAsACgphJYwEAK0DAAAA.',
No='Nosram:BAEBNQAECn84AAIYAAoKxh+ADQANAwqODQAACQBaAHUNAAAIAGEAfw0AAAcAYwCpDQAACABcAFwNAAAHAE4AXQ0AAAYAYQBlDQAABQBJAKQNAAACADcAMw0AAAIAXwC5DQAAAgBCABgACgrGH4ANAA0DCo4NAAAJAFoAdQ0AAAgAYQB/DQAABwBjAKkNAAAIAFwAXA0AAAcATgBdDQAABgBhAGUNAAAFAEkApA0AAAIANwAzDQAAAgBfALkNAAACAEIAAAA=.',
Nu='Nubbz:BAECNQAFFH8QAAIXAAYKAh1FAQAYAgaODQAAAwBKAHUNAAADAFoAfw0AAAIAGQCpDQAAAgBFAFwNAAABAD4AMw0AAAUAQAAXAAYKAh1FAQAYAgaODQAAAwBKAHUNAAADAFoAfw0AAAIAGQCpDQAAAgBFAFwNAAABAD4AMw0AAAUAQAA1AAQKf1UAAxcACgrjJf0BAJMDABcACgrjJf0BAJMDAA4AAQo/C/o2ATMAAAAA.',
Ny='Nyfaria:BAEBNQAECn9GAAIFAAoK8BPgBgDQAQqODQAACwA1AHUNAAAKADgAfw0AAAgAOACpDQAACwA5AFwNAAAHADcAXQ0AAAUANwBlDQAACAAvAKQNAAAEADgAMw0AAAMAFQC5DQAAAwAaAAUACgrwE+AGANABCo4NAAALADUAdQ0AAAoAOAB/DQAACAA4AKkNAAALADkAXA0AAAcANwBdDQAABQA3AGUNAAAIAC8ApA0AAAQAOAAzDQAAAwAVALkNAAADABoAAAA=.',
Or='Orsp:BAECNQAFFH8kAAMZAAgKdBk0AgDcAQiODQAACABYAHUNAAAFAEoAfw0AAAUAOwCpDQAABgBdAFwNAAABACUAXQ0AAAIAEQBlDQAAAQBQADMNAAAIACIAGQAICnQZNAIA3AEIjg0AAAcAWAB1DQAABABKAH8NAAABADsAqQ0AAAQAXQBcDQAAAQAlAF0NAAACABEAZQ0AAAEAUAAzDQAABQAiABoABQq6DJgUAGEBBY4NAAABAC0AdQ0AAAEAAgB/DQAABABJAKkNAAACABgAMw0AAAMAEAA1AAQKfzwAAxkACgq3JFgEAJMDABkACgq3JFgEAJMDABoACQpKE5FnAOgBAAAA.Orspp:BAEBNQAECn8kAAMZAAkKuh6kGQCBAgmODQAABwBhAHUNAAAGAGEAfw0AAAYAXQCpDQAABQBdAFwNAAADAFUAXQ0AAAIAJQBlDQAAAgBJAKQNAAAEAEEAMw0AAAEAIwAZAAcKkR+kGQCBAgeODQAABwBhAHUNAAAEAGEAfw0AAAUAXQCpDQAAAwBdAFwNAAACAFUAXQ0AAAEAJQBlDQAAAgBJABoABwo+D7+JAHkBB3UNAAACAFIAfw0AAAEAKwCpDQAAAgAeAFwNAAABAAoAXQ0AAAEALQCkDQAABAAqADMNAAABABEAATUABRQICCQAGQB0GQA=.',
Pa='Pakk:BAEBNQAECn8uAAMDAAgKexiTNgAwAgiODQAACQBSAHUNAAAJAEsAfw0AAAgATACpDQAABwBMAFwNAAAEAFYAXQ0AAAEAIgAzDQAABwBSALkNAAABABMAAwAHCuIbkzYAMAIHjg0AAAkAUgB1DQAACQBLAH8NAAAIAEwAqQ0AAAcATABcDQAABABWAF0NAAABACIAMw0AAAcAUgAEAAEKdgd/oAAyAAG5DQAAAQATAAAA.Pandotides:BAEANQAECggIEwABNQABCgIIAgAGAAAAAA==.Papadefensve:BAEANQAECgIIAQAAAA==.',
Ra='Razamon:BAEBNQAECn8nAAMQAAoK9xgfMQCcAgqODQAABwBTAHUNAAAEADsAfw0AAAQAWwCpDQAABABiAFwNAAADAEEAXQ0AAAIAOQBlDQAABQAdAKQNAAAEABEAMw0AAAQARgC5DQAAAgBCABAACgr3GB8xAJwCCo4NAAAGAFMAdQ0AAAQAOwB/DQAABABbAKkNAAAEAGIAXA0AAAMAQQBdDQAAAgA5AGUNAAAFAB0ApA0AAAQAEQAzDQAAAwBGALkNAAACAEIADgACCuAHOeIANAACjg0AAAEAFAAzDQAAAQAYAAAA.',
Re='Recurse:BAEANQADCggICAABNQAFFAgIEwAbACsVAA==.',
Ru='Runehaven:BAEANQADCggICAABNQAFFAEIAQAGAAAAAA==.',
Sa='Sairal:BAEANQAECgQIBwABNQAFFAcIHAASANIfAA==.Sargala:BAEANQAECgUIDQAAAA==.',
Sc='Scootybooty:BAEANQAECgYIDgABNQAECgoKFwAZAN0QAA==.Scootypriest:BAEBNQAECn8XAAIZAAoK3RB/JgD6AQqODQAABABBAHUNAAADAC8Afw0AAAMAUQCpDQAAAwBCAFwNAAABACsAXQ0AAAEABwBlDQAAAQAvAKQNAAABACUAMw0AAAMANQC5DQAAAwAeABkACgrdEH8mAPoBCo4NAAAEAEEAdQ0AAAMALwB/DQAAAwBRAKkNAAADAEIAXA0AAAEAKwBdDQAAAQAHAGUNAAABAC8ApA0AAAEAJQAzDQAAAwA1ALkNAAADAB4AAAA=.',
Sm='Smitehaven:BAEBNQAECn8fAAIcAAkKeiD0DADMAgmODQAABgBTAHUNAAAEAFkAfw0AAAQAXgCpDQAABABbAFwNAAAEAFwAXQ0AAAMAVABlDQAAAgBQADMNAAADAEsAuQ0AAAEAOwAcAAkKeiD0DADMAgmODQAABgBTAHUNAAAEAFkAfw0AAAQAXgCpDQAABABbAFwNAAAEAFwAXQ0AAAMAVABlDQAAAgBQADMNAAADAEsAuQ0AAAEAOwABNQAFFAEIAQAGAAAAAA==.',
Tc='Tchoff:BAEANQAECggICQABNQAFFAgIHgABAIkeAA==.',
Th='Thez:BAEANQAECgUICgABNQAECgoKMAASAFYhAA==.Thezadin:BAEANQAECgQIBAABNQAECgoKMAASAFYhAA==.Thezdin:BAEBNQAECn8wAAISAAoKViFIAwBsAwqODQAACQBXAHUNAAAEAF8Afw0AAAQAXgCpDQAABQBiAFwNAAAEAFwAXQ0AAAUAWgBlDQAABwBSAKQNAAAEAEUAMw0AAAUAUQC5DQAAAQBCABIACgpWIUgDAGwDCo4NAAAJAFcAdQ0AAAQAXwB/DQAABABeAKkNAAAFAGIAXA0AAAQAXABdDQAABQBaAGUNAAAHAFIApA0AAAQARQAzDQAABQBRALkNAAABAEIAAAA=.',
Un='Undecided:BAEANQADCgEIAQABNQAECgoKPQALAJ8bAA==.',
Ve='Velohm:BAEANQAECgMIBAAAAA==.',
Wi='Wildbless:BAECNQAFFH8bAAIcAAgK0AkPBACiAQiODQAABgBCAHUNAAAEAAsAfw0AAAQAHgCpDQAABAAjAFwNAAACAAQAXQ0AAAEAAgBlDQAAAQAdADMNAAAFACoAHAAICtAJDwQAogEIjg0AAAYAQgB1DQAABAALAH8NAAAEAB4AqQ0AAAQAIwBcDQAAAgAEAF0NAAABAAIAZQ0AAAEAHQAzDQAABQAqADUABAp/OAACHAAKCoMemQ8AowIAHAAKCoMemQ8AowIAATUABAoECAgABgAAAAA=.Wildform:BAEANQAECgIIAwABNQAECgQICAAGAAAAAA==.Wildkill:BAEBNQAECn8WAAIdAAcKjiMyUwB3AgeODQAABABjAHUNAAADAF4Afw0AAAMAOwCpDQAAAwBTAFwNAAACAEwAZQ0AAAMAYwCkDQAABABcAB0ABwqOIzJTAHcCB44NAAAEAGMAdQ0AAAMAXgB/DQAAAwA7AKkNAAADAFMAXA0AAAIATABlDQAAAwBjAKQNAAAEAFwAATUABAoECAgABgAAAAA=.Wildshield:BAEANQAECgQICAAAAA==.',
Wr='Wrècks:BAEANQAECgYIBwABNQAECgUIBQAGAAAAAA==.Wrèckstorm:BAECNQAFFH8KAAIXAAQKjxyKAgD5AASODQAABQBOAHUNAAACAEMAfw0AAAEARgCpDQAAAgBIABcABAqPHIoCAPkABI4NAAAFAE4AdQ0AAAIAQwB/DQAAAQBGAKkNAAACAEgANQAECn9BAAMXAAoKtCFJBgAhAwAXAAoKtCFJBgAhAwAOAAYK1RgHtQAoAQABNQAECgUIBQAGAAAAAA==.',
Zi='Zick:BAEANQAFFAYIAQAAAA==.',
Zo='Zoe:BAEANQAECgQICAAAAA==.Zogle:BAECNQAFFH8YAAIDAAgKcBWdBAA0AgiODQAABQBOAHUNAAADAB0Afw0AAAMAOwCpDQAABQBPAFwNAAACADwAXQ0AAAEAJABlDQAAAQAsADMNAAAEAGAAAwAICnAVnQQANAIIjg0AAAUATgB1DQAAAwAdAH8NAAADADsAqQ0AAAUATwBcDQAAAgA8AF0NAAABACQAZQ0AAAEALAAzDQAABABgADUABAp/OQACAwAKCv4kdgcAAQMAAwAKCv4kdgcAAQMAATUABAoECAgABgAAAAA=.',
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
