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

local lookup = {'Warrior-Arms','Monk-Windwalker','DeathKnight-Blood','DeathKnight-Frost','Monk-Brewmaster','Unknown-Unknown','Warlock-Affliction','Shaman-Restoration','Druid-Restoration','Mage-Frost','Paladin-Retribution','Paladin-Holy','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','Rogue-Outlaw','Mage-Arcane','Warrior-Protection','Evoker-Preservation','Evoker-Devastation','Druid-Feral','Shaman-Enhancement','Hunter-BeastMastery','DemonHunter-Devourer','Priest-Shadow','Priest-Holy','Warlock-Demonology','Paladin-Protection',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=53,date='2026-11-10',data={Ar='Architwo:BAEANQAECgUICAABNQAFFAkJKQABAJEgAA==.',
As='Astaren:BAEANQAECgYIDQAAAA==.',
Ba='Basin:BAEANQAECgIIAQABNQAFFAUICgACADwSAA==.',
Br='Bryl:BAECNQAFFH8XAAIDAAgKuBtjCADaAQiODQAABQA7AHUNAAAEAFAAfw0AAAMAQgCpDQAABQBKAFwNAAABAD8AXQ0AAAEARABlDQAAAQBOADMNAAADAEoAAwAICrgbYwgA2gEIjg0AAAUAOwB1DQAABABQAH8NAAADAEIAqQ0AAAUASgBcDQAAAQA/AF0NAAABAEQAZQ0AAAEATgAzDQAAAwBKADUABAp/JwADAwAKCmoeHTsAGAIAAwAKCi0dHTsAGAIABAAFCv8TE2QA8QAAAAA=.Brylic:BAECNQAFFH8RAAIFAAYKWyH7AADiAQaODQAABQBSAHUNAAAEAE0Afw0AAAIAOgCpDQAABABQAFwNAAABAFoAXQ0AAAEAXwAFAAYKWyH7AADiAQaODQAABQBSAHUNAAAEAE0Afw0AAAIAOgCpDQAABABQAFwNAAABAFoAXQ0AAAEAXwA1AAQKfzsAAwUACgqsIzAEADoDAAUACgqsIzAEADoDAAIABwoZGzYbALYBAAE1AAUUCAgXAAMAuBsA.Brylicet:BAEANQADCgQIBAABNQAFFAgIFwADALgbAA==.',
Ca='Camreon:BAEBNQAECn8cAAIBAAkKTx17SgCqAgmODQAABABWAHUNAAADAFwAfw0AAAMAPwCpDQAAAwBPAFwNAAADAEoAXQ0AAAMAVABlDQAABQBHAKQNAAABACUAMw0AAAMASQABAAkKTx17SgCqAgmODQAABABWAHUNAAADAFwAfw0AAAMAPwCpDQAAAwBPAFwNAAADAEoAXQ0AAAMAVABlDQAABQBHAKQNAAABACUAMw0AAAMASQAAAA==.Captpando:BAEANQAFFAIIAgABNQABCgIIAgAGAAAAAA==.',
Cb='Cbkthree:BAEANQAECgIIBQABNQAFFAgIJQAHAJYjAA==.',
Ch='Chataya:BAEANQAECgUIBQABNQAECgkJLgAIADgdAA==.',
Co='Coolshirtbra:BAEANQAECgQIBAABNQAECgoKRgAJAMghAA==.',
Da='Dantius:BAEANQAECgEIAQABNQAECgoKPQAKAHwYAA==.Darkorin:BAEBNQAECn9GAAMLAAoK1iZDAQCQAwqODQAACwBjAHUNAAAHAGMAfw0AAAcAXwCpDQAACABjAFwNAAAGAGMAXQ0AAAYAYwBlDQAACgBjAKQNAAAGAGMAMw0AAAUAYwC5DQAABABjAAsACgrWJkMBAJADCo4NAAALAGMAdQ0AAAcAYwB/DQAABgBfAKkNAAAIAGMAXA0AAAYAYwBdDQAABgBjAGUNAAAKAGMApA0AAAYAYwAzDQAABABjALkNAAAEAGMADAACCtoXZv0AgQACfw0AAAEAQwAzDQAAAQA2AAAA.',
Dr='Dragore:BAECNQAFFH8KAAICAAUKPBLmBgAMAQWODQAABABJAHUNAAABACcAfw0AAAEAGACpDQAAAwAPAFwNAAABADoAAgAFCjwS5gYADAEFjg0AAAQASQB1DQAAAQAnAH8NAAABABgAqQ0AAAMADwBcDQAAAQA6ADUABAp/OAACAgAKCvEkqAQAiAMAAgAKCvEkqAQAiAMAAAA=.',
Fo='Foxorcism:BAEANQADCgcIDgABNQAECgQIBQAGAAAAAA==.Foxrocket:BAEANQADCgIIAgABNQAECgQIBQAGAAAAAA==.Foxwu:BAEANQAECgQIBQAAAA==.',
Fr='Fries:BAECNQAFFH8cAAMNAAcKohtvAwApAgeODQAABgBGAHUNAAAFAFsAfw0AAAQAJACpDQAABgBcAFwNAAACAFsAXQ0AAAEABwAzDQAABAA0AA0ABwqiG28DACkCB44NAAADAEYAdQ0AAAQAWwB/DQAAAwAkAKkNAAAGAFwAXA0AAAIAWwBdDQAAAQAHADMNAAADADQADgAECksUWgoANQEEjg0AAAMAJwB1DQAAAQBAAH8NAAABAAQAMw0AAAEADwA1AAQKfzYAAw4ACgq+JNwIAC0DAA0ACgr2I8UIAEwDAA4ACgqXI9wIAC0DAAE1AAQKCAgPAAYAAAAA.',
Ga='Galgpal:BAEANQAECgMIBQABNQAFFAgIHgABAIkeAA==.Gardenweed:BAEANQAECgUIDAABNQAECggIFAAPAPgFAA==.',
Gu='Guthynn:BAEBNQAECn8kAAMQAAoKVSVdAADSAwqODQAABABhAHUNAAAEAGIAfw0AAAUAYQCpDQAABgBeAFwNAAAEAGEAXQ0AAAIAXABlDQAAAgBaAKQNAAAFAGMAMw0AAAEAXAC5DQAAAwBeABAACgpVJV0AANIDCo4NAAAEAGEAdQ0AAAQAYgB/DQAABQBhAKkNAAAGAF4AXA0AAAQAYQBdDQAAAgBcAGUNAAACAFoApA0AAAMAYwAzDQAAAQBcALkNAAADAF4ADQABCqIYV5oASgABpA0AAAIAPwAAAA==.',
Ha='Havècks:BAEANQAECgUIBQAAAA==.',
Ir='Irro:BAEANQAECgIIAgABNQAECgkJLgAIADgdAA==.Irrogenia:BAEBNQAECn8uAAIIAAkKOB2oLACvAgmODQAABwBZAHUNAAAHAFkAfw0AAAcAVACpDQAABgBZAFwNAAAGAFUAXQ0AAAUAPgBlDQAAAwA3ADMNAAADAEQAuQ0AAAIALgAIAAkKOB2oLACvAgmODQAABwBZAHUNAAAHAFkAfw0AAAcAVACpDQAABgBZAFwNAAAGAFUAXQ0AAAUAPgBlDQAAAwA3ADMNAAADAEQAuQ0AAAIALgAAAA==.Irrolyn:BAEANQAECgQIBAABNQAECgkJLgAIADgdAA==.',
Kc='Kcmndr:BAEANQAECgYICAABNQAFFAoKNwARAMEkAA==.',
La='Lariàs:BAECNQAFFH8dAAISAAgKVhx5AABhAgiODQAABgBgAHUNAAAFAFEAfw0AAAQATQCpDQAABABdAFwNAAACAFQAXQ0AAAEAMwCkDQAAAQAbADMNAAAGAGEAEgAIClYceQAAYQIIjg0AAAYAYAB1DQAABQBRAH8NAAAEAE0AqQ0AAAQAXQBcDQAAAgBUAF0NAAABADMApA0AAAEAGwAzDQAABgBhADUABAp/PgADEgAKCr4jKgMAcQMAEgAKCr4jKgMAcQMAAQAFCoAEbC4BdwAAAAA=.',
Li='Lidariel:BAEANQAECgYIBQABNQAECgoKJAATAJsTAA==.Lidathra:BAEBNQAECn8kAAMTAAoKmxOxGgAaAgqODQAABQBCAHUNAAACAA4Afw0AAAIAJQCpDQAABABKAFwNAAADADYAXQ0AAAQALgBlDQAABgBEAKQNAAAEACEAMw0AAAMAJwC5DQAAAwBBABMACgqbE7EaABoCCo4NAAAEAEIAdQ0AAAIADgB/DQAAAgAlAKkNAAADAEoAXA0AAAMANgBdDQAABAAuAGUNAAAGAEQApA0AAAQAIQAzDQAAAgAnALkNAAADAEEAFAADClsVGy4ArgADjg0AAAEAMACpDQAAAQA8ADMNAAABACQAAAA=.Lidishi:BAEANQAECgQIBAABNQAECgoKJAATAJsTAA==.',
Lo='Lochru:BAEBNQAECn8iAAIVAAkK+hkGCQC9AgmODQAABABNAHUNAAAFAFQAfw0AAAUAVwCpDQAABQBXAFwNAAAEAE0AXQ0AAAMAPABlDQAAAwApAKQNAAABACQAMw0AAAQAWgAVAAkK+hkGCQC9AgmODQAABABNAHUNAAAFAFQAfw0AAAUAVwCpDQAABQBXAFwNAAAEAE0AXQ0AAAMAPABlDQAAAwApAKQNAAABACQAMw0AAAQAWgAAAA==.Lowz:BAEANQAFFAcIAQAAAA==.',
Mi='Migwangomage:BAECNQAFFH8GAAIRAAQKUxuqJwBLAQSODQAAAgBfAHUNAAABADMAfw0AAAEAAgCpDQAAAgA+ABEABApTG6onAEsBBI4NAAACAF8AdQ0AAAEAMwB/DQAAAQACAKkNAAACAD4ANQAECn8/AAIRAAoK2yZUAAALBAARAAoK2yZUAAALBAAAAA==.Mikmilk:BAEANQAECgYIEgABNQAECgoKRgAJAMghAA==.Mikronos:BAECNQAFFH8NAAMWAAQKrRMQBADRAASODQAABQAuAHUNAAADACAAfw0AAAEAHgCpDQAABABIAA8AAwqOE2EZAPcAA44NAAADAC0AdQ0AAAIAIACpDQAAAgBIABYABAoYERAEANEABI4NAAACAC4AdQ0AAAEAHQB/DQAAAQAeAKkNAAACADcANQAECn8lAAMPAAkKUh5GKwDSAgAPAAkKARxGKwDSAgAWAAUKBRaEHgB4AQABNQAECgoKRgAJAMghAA==.',
['Mà']='Màsterofhunt:BAEBNQAECn8UAAIXAAkKrAytpwC2AQmODQAABAAhAHUNAAADAC0Afw0AAAMAFACpDQAAAwAdAFwNAAABACYAXQ0AAAEAJgBlDQAAAQAkADMNAAADABsAuQ0AAAEABQAXAAkKrAytpwC2AQmODQAABAAhAHUNAAADAC0Afw0AAAMAFACpDQAAAwAdAFwNAAABACYAXQ0AAAEAJgBlDQAAAQAkADMNAAADABsAuQ0AAAEABQAAAA==.Màsterofwar:BAEANQAECgMIAwABNQAECgkJFAAXAKwMAA==.',
Ne='Neodefender:BAECNQAFFH8TAAIMAAYKDCRHBgACAgaODQAABQBPAHUNAAAEAFwAfw0AAAMAYwCpDQAABQBeAFwNAAABAGMAMw0AAAEAWAAMAAYKDCRHBgACAgaODQAABQBPAHUNAAAEAFwAfw0AAAMAYwCpDQAABQBeAFwNAAABAGMAMw0AAAEAWAA1AAQKfzIAAgwACgpjJYwEAK0DAAwACgpjJYwEAK0DAAAA.',
No='Nosram:BAEBNQAECn88AAIYAAoKbCCADQANAwqODQAACgBaAHUNAAAIAGEAfw0AAAcAYwCpDQAACABcAFwNAAAHAE4AXQ0AAAYAYQBlDQAABgBOAKQNAAADADcAMw0AAAIAXwC5DQAAAwBKABgACgpsIIANAA0DCo4NAAAKAFoAdQ0AAAgAYQB/DQAABwBjAKkNAAAIAFwAXA0AAAcATgBdDQAABgBhAGUNAAAGAE4ApA0AAAMANwAzDQAAAgBfALkNAAADAEoAAAA=.',
Nu='Nubbz:BAECNQAFFH8QAAIWAAYKAh1FAQAYAgaODQAAAwBKAHUNAAADAFoAfw0AAAIAGQCpDQAAAgBFAFwNAAABAD4AMw0AAAUAQAAWAAYKAh1FAQAYAgaODQAAAwBKAHUNAAADAFoAfw0AAAIAGQCpDQAAAgBFAFwNAAABAD4AMw0AAAUAQAA1AAQKf1YAAxYACgrjJf0BAJMDABYACgrjJf0BAJMDAA8AAQo/C/o2ATMAAAAA.',
Ny='Nyfaria:BAEBNQAECn9KAAIFAAoK8BPzBwDLAQqODQAADAA1AHUNAAAKADgAfw0AAAgAOACpDQAACwA5AFwNAAAHADcAXQ0AAAUANwBlDQAACQAvAKQNAAAFADgAMw0AAAMAFQC5DQAABAAaAAUACgrwE/MHAMsBCo4NAAAMADUAdQ0AAAoAOAB/DQAACAA4AKkNAAALADkAXA0AAAcANwBdDQAABQA3AGUNAAAJAC8ApA0AAAUAOAAzDQAAAwAVALkNAAAEABoAAAA=.',
Or='Orsp:BAECNQAFFH8lAAMZAAgKdBkPAwDNAQiODQAACQBYAHUNAAAFAEoAfw0AAAUAOwCpDQAABgBdAFwNAAABACUAXQ0AAAIAEQBlDQAAAQBQADMNAAAIACIAGQAICnQZDwMAzQEIjg0AAAgAWAB1DQAABABKAH8NAAABADsAqQ0AAAQAXQBcDQAAAQAlAF0NAAACABEAZQ0AAAEAUAAzDQAABQAiABoABQq6DJgUAGEBBY4NAAABAC0AdQ0AAAEAAgB/DQAABABJAKkNAAACABgAMw0AAAMAEAA1AAQKf0MAAxkACgq3JFgEAJMDABkACgq3JFgEAJMDABoACQpKE5FnAOgBAAAA.Orspp:BAEBNQAECn8lAAMZAAoKPB2kGQCBAgqODQAABwBhAHUNAAAGAGEAfw0AAAYAXQCpDQAABQBdAFwNAAADAFUAXQ0AAAIAJQBlDQAAAgBJAKQNAAAEAEEAMw0AAAEAIwC5DQAAAQAwABkACAq+HaQZAIECCI4NAAAHAGEAdQ0AAAQAYQB/DQAABQBdAKkNAAADAF0AXA0AAAIAVQBdDQAAAQAlAGUNAAACAEkAuQ0AAAEAMAAaAAcKPg+/iQB5AQd1DQAAAgBSAH8NAAABACsAqQ0AAAIAHgBcDQAAAQAKAF0NAAABAC0ApA0AAAQAKgAzDQAAAQARAAE1AAUUCAglABkAdBkA.',
Pa='Pakk:BAEBNQAECn81AAMDAAkKUBjbJwCxAQmODQAACgBSAHUNAAAKAEsAfw0AAAkATwCpDQAACABMAFwNAAAFAFYAXQ0AAAEAIgBlDQAAAQA7ADMNAAAIAFIAuQ0AAAEAEwADAAgKHxvbJwCxAQiODQAACgBSAHUNAAAKAEsAfw0AAAkATwCpDQAACABMAFwNAAAFAFYAXQ0AAAEAIgBlDQAAAQA7ADMNAAAIAFIABAABCnYHKq4AMgABuQ0AAAEAEwAAAA==.Pandotides:BAEANQAECggIEQABNQABCgIIAgAGAAAAAA==.Papadefensve:BAEANQAECgIIAQAAAA==.',
Ra='Razamon:BAEBNQAECn8rAAMIAAoK9xgfMQCcAgqODQAACABTAHUNAAAEADsAfw0AAAQAWwCpDQAABABiAFwNAAADAEEAXQ0AAAIAOQBlDQAABgAdAKQNAAAFABEAMw0AAAQARgC5DQAAAwBCAAgACgr3GB8xAJwCCo4NAAAHAFMAdQ0AAAQAOwB/DQAABABbAKkNAAAEAGIAXA0AAAMAQQBdDQAAAgA5AGUNAAAGAB0ApA0AAAUAEQAzDQAAAwBGALkNAAADAEIADwACCuAHtPMANAACjg0AAAEAFAAzDQAAAQAYAAAA.',
Re='Recurse:BAEANQADCggICAABNQAFFAoKGwAbALMXAA==.',
Ru='Runehaven:BAEANQADCggICAABNQAFFAIIAgAGAAAAAA==.',
Sa='Sairal:BAEANQAECgQIBwABNQAFFAgIHQASAFYcAA==.Sargala:BAEANQAECgUIDQAAAA==.',
Sc='Scootybooty:BAEANQAECgYIDAABNQAECgoKFwAZAN0QAA==.Scootypriest:BAEBNQAECn8XAAIZAAoK3RB/JgD6AQqODQAABABBAHUNAAADAC8Afw0AAAMAUQCpDQAAAwBCAFwNAAABACsAXQ0AAAEABwBlDQAAAQAvAKQNAAABACUAMw0AAAMANQC5DQAAAwAeABkACgrdEH8mAPoBCo4NAAAEAEEAdQ0AAAMALwB/DQAAAwBRAKkNAAADAEIAXA0AAAEAKwBdDQAAAQAHAGUNAAABAC8ApA0AAAEAJQAzDQAAAwA1ALkNAAADAB4AAAA=.',
Sm='Smitehaven:BAEBNQAECn8fAAIcAAkKeiD0DADMAgmODQAABgBTAHUNAAAEAFkAfw0AAAQAXgCpDQAABABbAFwNAAAEAFwAXQ0AAAMAVABlDQAAAgBQADMNAAADAEsAuQ0AAAEAOwAcAAkKeiD0DADMAgmODQAABgBTAHUNAAAEAFkAfw0AAAQAXgCpDQAABABbAFwNAAAEAFwAXQ0AAAMAVABlDQAAAgBQADMNAAADAEsAuQ0AAAEAOwABNQAFFAIIAgAGAAAAAA==.',
Tc='Tchoff:BAEANQAECggICAABNQAFFAgIHgABAIkeAA==.',
Th='Thez:BAEANQAECgUICgABNQAECgoKOAASALEhAA==.Thezadin:BAEANQAECgQIBAABNQAECgoKOAASALEhAA==.Thezdin:BAEBNQAECn84AAISAAoKsSFIAwBsAwqODQAACgBXAHUNAAAFAF8Afw0AAAUAXgCpDQAABgBiAFwNAAAFAFwAXQ0AAAYAWgBlDQAACABUAKQNAAAFAEoAMw0AAAUAUQC5DQAAAQBCABIACgqxIUgDAGwDCo4NAAAKAFcAdQ0AAAUAXwB/DQAABQBeAKkNAAAGAGIAXA0AAAUAXABdDQAABgBaAGUNAAAIAFQApA0AAAUASgAzDQAABQBRALkNAAABAEIAAAA=.',
Un='Undecided:BAEANQADCgEIAQABNQAECgoKQQAMAJ8bAA==.',
Ve='Velohm:BAEANQAECgMIBAAAAA==.',
Wi='Wildbless:BAECNQAFFH8bAAIcAAgK0AkPBACiAQiODQAABgBCAHUNAAAEAAsAfw0AAAQAHgCpDQAABAAjAFwNAAACAAQAXQ0AAAEAAgBlDQAAAQAdADMNAAAFACoAHAAICtAJDwQAogEIjg0AAAYAQgB1DQAABAALAH8NAAAEAB4AqQ0AAAQAIwBcDQAAAgAEAF0NAAABAAIAZQ0AAAEAHQAzDQAABQAqADUABAp/OQACHAAKCoMemQ8AowIAHAAKCoMemQ8AowIAATUABAoECAgABgAAAAA=.Wildform:BAEANQAECgIIAwABNQAECgQICAAGAAAAAA==.Wildkill:BAEBNQAECn8WAAIXAAcKjiMyUwB3AgeODQAABABjAHUNAAADAF4Afw0AAAMAOwCpDQAAAwBTAFwNAAACAEwAZQ0AAAMAYwCkDQAABABcABcABwqOIzJTAHcCB44NAAAEAGMAdQ0AAAMAXgB/DQAAAwA7AKkNAAADAFMAXA0AAAIATABlDQAAAwBjAKQNAAAEAFwAATUABAoECAgABgAAAAA=.Wildshield:BAEANQAECgQICAAAAA==.',
Wr='Wrècks:BAEANQAECgYIBwABNQAECgUIBQAGAAAAAA==.Wrèckstorm:BAECNQAFFH8MAAIWAAQKjxzxAgD5AASODQAABgBOAHUNAAACAEMAfw0AAAEARgCpDQAAAwBIABYABAqPHPECAPkABI4NAAAGAE4AdQ0AAAIAQwB/DQAAAQBGAKkNAAADAEgANQAECn9JAAMWAAoK4SGnBQDSAgAWAAoK4SGnBQDSAgAPAAYK1RgHtQAoAQABNQAECgUIBQAGAAAAAA==.',
Zi='Zick:BAEANQAFFAYIAQAAAA==.',
Zo='Zoe:BAEANQAECgQICAAAAA==.Zogle:BAECNQAFFH8YAAIDAAgKcBWdBAA0AgiODQAABQBOAHUNAAADAB0Afw0AAAMAOwCpDQAABQBPAFwNAAACADwAXQ0AAAEAJABlDQAAAQAsADMNAAAEAGAAAwAICnAVnQQANAIIjg0AAAUATgB1DQAAAwAdAH8NAAADADsAqQ0AAAUATwBcDQAAAgA8AF0NAAABACQAZQ0AAAEALAAzDQAABABgADUABAp/OgACAwAKCv4kqwgA+gIAAwAKCv4kqwgA+gIAATUABAoECAgABgAAAAA=.',
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
