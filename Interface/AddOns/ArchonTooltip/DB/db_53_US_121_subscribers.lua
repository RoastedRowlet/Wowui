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

local lookup = {'Warrior-Arms','Monk-Windwalker','DeathKnight-Blood','DeathKnight-Frost','Monk-Brewmaster','Paladin-Holy','Unknown-Unknown','Warlock-Affliction','Shaman-Restoration','Druid-Restoration','Mage-Frost','Paladin-Retribution','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Mage-Arcane','Warrior-Protection','Evoker-Preservation','Evoker-Devastation','Druid-Feral','Shaman-Enhancement','Shaman-Elemental','Hunter-BeastMastery','DemonHunter-Devourer','Priest-Shadow','Priest-Holy','Warlock-Demonology','Paladin-Protection',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=53,date='2026-11-17',data={Ar='Architwo:BAEANQAECgUICAABNQAFFAkJLwABADMiAA==.',
As='Astaren:BAEANQAECgYIDQAAAA==.',
Ba='Basin:BAEANQAECgIIAQABNQAFFAUICgACADwSAA==.',
Br='Bryl:BAECNQAFFH8XAAIDAAgKuBtjCADaAQiODQAABQA7AHUNAAAEAFAAfw0AAAMAQgCpDQAABQBKAFwNAAABAD8AXQ0AAAEARABlDQAAAQBOADMNAAADAEoAAwAICrgbYwgA2gEIjg0AAAUAOwB1DQAABABQAH8NAAADAEIAqQ0AAAUASgBcDQAAAQA/AF0NAAABAEQAZQ0AAAEATgAzDQAAAwBKADUABAp/KAADAwAKCmoeHTsAGAIAAwAKCi0dHTsAGAIABAAFCv8TAWsA8QAAAAA=.Brylic:BAECNQAFFH8RAAIFAAYKWyGLAQDWAQaODQAABQBSAHUNAAAEAE0Afw0AAAIAOgCpDQAABABQAFwNAAABAFoAXQ0AAAEAXwAFAAYKWyGLAQDWAQaODQAABQBSAHUNAAAEAE0Afw0AAAIAOgCpDQAABABQAFwNAAABAFoAXQ0AAAEAXwA1AAQKfz0AAwUACgroIzAEADoDAAUACgroIzAEADoDAAIABwoZG8AdALQBAAE1AAUUCAgXAAMAuBsA.Brylicet:BAEANQADCgQIBAABNQAFFAgIFwADALgbAA==.',
Ca='Camreon:BAEBNQAECn8cAAIBAAkKTx17SgCqAgmODQAABABWAHUNAAADAFwAfw0AAAMAPwCpDQAAAwBPAFwNAAADAEoAXQ0AAAMAVABlDQAABQBHAKQNAAABACUAMw0AAAMASQABAAkKTx17SgCqAgmODQAABABWAHUNAAADAFwAfw0AAAMAPwCpDQAAAwBPAFwNAAADAEoAXQ0AAAMAVABlDQAABQBHAKQNAAABACUAMw0AAAMASQAAAA==.Captpando:BAEBNQAFFH8GAAIGAAQKQxiMDQBvAQSODQAAAgBSAKkNAAACAFIAZQ0AAAEALQCkDQAAAQAmAAYABApDGIwNAG8BBI4NAAACAFIAqQ0AAAIAUgBlDQAAAQAtAKQNAAABACYAATUAAQoCCAIABwAAAAA=.',
Cb='Cbkthree:BAEANQAECgIIBQABNQAFFAoKLgAIAJkiAA==.',
Ch='Chataya:BAEANQAECgYICgABNQAECgkJLgAJADgdAA==.',
Co='Coolshirtbra:BAEANQAECgQIBAABNQAECgoKRgAKAMghAA==.',
Da='Dantius:BAEANQAECgcIBwABNQAECgoKQAALAH0YAA==.Darkorin:BAEBNQAECn9GAAMMAAoK1iaxAQCMAwqODQAACwBjAHUNAAAHAGMAfw0AAAcAXwCpDQAACABjAFwNAAAGAGMAXQ0AAAYAYwBlDQAACgBjAKQNAAAGAGMAMw0AAAUAYwC5DQAABABjAAwACgrWJrEBAIwDCo4NAAALAGMAdQ0AAAcAYwB/DQAABgBfAKkNAAAIAGMAXA0AAAYAYwBdDQAABgBjAGUNAAAKAGMApA0AAAYAYwAzDQAABABjALkNAAAEAGMABgACCtoXZv0AgQACfw0AAAEAQwAzDQAAAQA2AAAA.',
Dr='Dragore:BAECNQAFFH8KAAICAAUKPBIMCAAFAQWODQAABABJAHUNAAABACcAfw0AAAEAGACpDQAAAwAPAFwNAAABADoAAgAFCjwSDAgABQEFjg0AAAQASQB1DQAAAQAnAH8NAAABABgAqQ0AAAMADwBcDQAAAQA6ADUABAp/OQACAgAKCvEkqAQAiAMAAgAKCvEkqAQAiAMAAAA=.',
Fo='Foxorcism:BAEANQADCgcIDgABNQAECgQIBQAHAAAAAA==.Foxrocket:BAEANQADCgIIAgABNQAECgQIBQAHAAAAAA==.Foxwu:BAEANQAECgQIBQAAAA==.',
Fr='Fries:BAECNQAFFH8eAAMNAAgK0xpvAwApAgiODQAABgBGAHUNAAAFAFsAfw0AAAQAJACpDQAABgBcAFwNAAACAFsAXQ0AAAEABwBlDQAAAQA6ADMNAAAFADQADQAHCqIbbwMAKQIHjg0AAAMARgB1DQAABABbAH8NAAADACQAqQ0AAAYAXABcDQAAAgBbAF0NAAABAAcAMw0AAAQANAAOAAUKHxVaCgA1AQWODQAAAwAnAHUNAAABAEAAfw0AAAEABABlDQAAAQA6ADMNAAABAA8ANQAECn82AAMOAAoKviSfCQArAwANAAoK9iPFCABMAwAOAAoKlyOfCQArAwABNQAECggIDwAHAAAAAA==.',
Ga='Galgpal:BAEANQAECgQIBQABNQAFFAgIHwABAIkeAA==.Gardenweed:BAEANQAECgYIEQAAAA==.',
Gu='Guthynn:BAEBNQAECn8kAAMPAAoKVSVdAADSAwqODQAABABhAHUNAAAEAGIAfw0AAAUAYQCpDQAABgBeAFwNAAAEAGEAXQ0AAAIAXABlDQAAAgBaAKQNAAAFAGMAMw0AAAEAXAC5DQAAAwBeAA8ACgpVJV0AANIDCo4NAAAEAGEAdQ0AAAQAYgB/DQAABQBhAKkNAAAGAF4AXA0AAAQAYQBdDQAAAgBcAGUNAAACAFoApA0AAAMAYwAzDQAAAQBcALkNAAADAF4ADQABCqIYV5oASgABpA0AAAIAPwAAAA==.',
Ha='Havècks:BAEANQAECgUIBQAAAA==.',
Ir='Irro:BAEANQAECgIIAgABNQAECgkJLgAJADgdAA==.Irrogenia:BAEBNQAECn8uAAIJAAkKOB2oLACvAgmODQAABwBZAHUNAAAHAFkAfw0AAAcAVACpDQAABgBZAFwNAAAGAFUAXQ0AAAUAPgBlDQAAAwA3ADMNAAADAEQAuQ0AAAIALgAJAAkKOB2oLACvAgmODQAABwBZAHUNAAAHAFkAfw0AAAcAVACpDQAABgBZAFwNAAAGAFUAXQ0AAAUAPgBlDQAAAwA3ADMNAAADAEQAuQ0AAAIALgAAAA==.Irrolyn:BAEANQAECgQIBAABNQAECgkJLgAJADgdAA==.',
Kc='Kcmndr:BAEANQAECgYICAABNQAFFAoKOwAQAMEkAA==.',
La='Lariàs:BAECNQAFFH8dAAIRAAgKVhx5AABhAgiODQAABgBgAHUNAAAFAFEAfw0AAAQATQCpDQAABABdAFwNAAACAFQAXQ0AAAEAMwCkDQAAAQAbADMNAAAGAGEAEQAIClYceQAAYQIIjg0AAAYAYAB1DQAABQBRAH8NAAAEAE0AqQ0AAAQAXQBcDQAAAgBUAF0NAAABADMApA0AAAEAGwAzDQAABgBhADUABAp/PgADEQAKCr4jKgMAcQMAEQAKCr4jKgMAcQMAAQAFCoAEbC4BdwAAAAA=.',
Li='Lidariel:BAEANQAECgYIBQABNQAECgoKJAASAJsTAA==.Lidathra:BAEBNQAECn8kAAMSAAoKmxOxGgAaAgqODQAABQBCAHUNAAACAA4Afw0AAAIAJQCpDQAABABKAFwNAAADADYAXQ0AAAQALgBlDQAABgBEAKQNAAAEACEAMw0AAAMAJwC5DQAAAwBBABIACgqbE7EaABoCCo4NAAAEAEIAdQ0AAAIADgB/DQAAAgAlAKkNAAADAEoAXA0AAAMANgBdDQAABAAuAGUNAAAGAEQApA0AAAQAIQAzDQAAAgAnALkNAAADAEEAEwADClsVGy4ArgADjg0AAAEAMACpDQAAAQA8ADMNAAABACQAAAA=.Lidishi:BAEANQAECgQIBAABNQAECgoKJAASAJsTAA==.',
Lo='Lochru:BAEBNQAECn8iAAIUAAkK+hkGCQC9AgmODQAABABNAHUNAAAFAFQAfw0AAAUAVwCpDQAABQBXAFwNAAAEAE0AXQ0AAAMAPABlDQAAAwApAKQNAAABACQAMw0AAAQAWgAUAAkK+hkGCQC9AgmODQAABABNAHUNAAAFAFQAfw0AAAUAVwCpDQAABQBXAFwNAAAEAE0AXQ0AAAMAPABlDQAAAwApAKQNAAABACQAMw0AAAQAWgAAAA==.Lowz:BAEANQAFFAcIAQAAAA==.',
Mi='Migwangomage:BAECNQAFFH8GAAIQAAQKUxuqJwBLAQSODQAAAgBfAHUNAAABADMAfw0AAAEAAgCpDQAAAgA+ABAABApTG6onAEsBBI4NAAACAF8AdQ0AAAEAMwB/DQAAAQACAKkNAAACAD4ANQAECn8/AAIQAAoK2yZUAAALBAAQAAoK2yZUAAALBAAAAA==.Mikmilk:BAEANQAECgYIEgABNQAECgoKRgAKAMghAA==.Mikronos:BAECNQAFFH8NAAMVAAQKrRN9BADOAASODQAABQAuAHUNAAADACAAfw0AAAEAHgCpDQAABABIABYAAwqOE2EZAPcAA44NAAADAC0AdQ0AAAIAIACpDQAAAgBIABUABAoYEX0EAM4ABI4NAAACAC4AdQ0AAAEAHQB/DQAAAQAeAKkNAAACADcANQAECn8lAAMWAAkKUh5GKwDSAgAWAAkKARxGKwDSAgAVAAUKBRaEHgB4AQABNQAECgoKRgAKAMghAA==.',
['Mà']='Màsterofhunt:BAEBNQAECn8UAAIXAAkKrAytpwC2AQmODQAABAAhAHUNAAADAC0Afw0AAAMAFACpDQAAAwAdAFwNAAABACYAXQ0AAAEAJgBlDQAAAQAkADMNAAADABsAuQ0AAAEABQAXAAkKrAytpwC2AQmODQAABAAhAHUNAAADAC0Afw0AAAMAFACpDQAAAwAdAFwNAAABACYAXQ0AAAEAJgBlDQAAAQAkADMNAAADABsAuQ0AAAEABQAAAA==.Màsterofwar:BAEANQAECgMIAwABNQAECgkJFAAXAKwMAA==.',
Ne='Neodefender:BAECNQAFFH8TAAIGAAYKDCSsBwDsAQaODQAABQBPAHUNAAAEAFwAfw0AAAMAYwCpDQAABQBeAFwNAAABAGMAMw0AAAEAWAAGAAYKDCSsBwDsAQaODQAABQBPAHUNAAAEAFwAfw0AAAMAYwCpDQAABQBeAFwNAAABAGMAMw0AAAEAWAA1AAQKfzIAAgYACgpjJYwEAK0DAAYACgpjJYwEAK0DAAAA.',
No='Nosram:BAEBNQAECn9AAAIYAAoKWCGADQANAwqODQAACwBaAHUNAAAIAGEAfw0AAAcAYwCpDQAACABcAFwNAAAHAE4AXQ0AAAYAYQBlDQAABwBOAKQNAAAEAEgAMw0AAAIAXwC5DQAABABMABgACgpYIYANAA0DCo4NAAALAFoAdQ0AAAgAYQB/DQAABwBjAKkNAAAIAFwAXA0AAAcATgBdDQAABgBhAGUNAAAHAE4ApA0AAAQASAAzDQAAAgBfALkNAAAEAEwAAAA=.',
Nu='Nubbz:BAECNQAFFH8QAAIVAAYKAh1FAQAYAgaODQAAAwBKAHUNAAADAFoAfw0AAAIAGQCpDQAAAgBFAFwNAAABAD4AMw0AAAUAQAAVAAYKAh1FAQAYAgaODQAAAwBKAHUNAAADAFoAfw0AAAIAGQCpDQAAAgBFAFwNAAABAD4AMw0AAAUAQAA1AAQKf1YAAxUACgrjJf0BAJMDABUACgrjJf0BAJMDABYAAQo/C/o2ATMAAAAA.',
Ny='Nyfaria:BAEBNQAECn9OAAIFAAoKURR2CADPAQqODQAADQA1AHUNAAAKADgAfw0AAAgAOACpDQAACwA5AFwNAAAHADcAXQ0AAAUANwBlDQAACgAvAKQNAAAGADgAMw0AAAMAFQC5DQAABQAiAAUACgpRFHYIAM8BCo4NAAANADUAdQ0AAAoAOAB/DQAACAA4AKkNAAALADkAXA0AAAcANwBdDQAABQA3AGUNAAAKAC8ApA0AAAYAOAAzDQAAAwAVALkNAAAFACIAAAA=.',
Or='Orsp:BAECNQAFFH8rAAMZAAgKCx5VAwDyAQiODQAACgBgAHUNAAAGAEoAfw0AAAYAOwCpDQAABwBdAFwNAAABACUAXQ0AAAMATwBlDQAAAgBQADMNAAAIACIAGQAICgseVQMA8gEIjg0AAAkAYAB1DQAABQBKAH8NAAACADsAqQ0AAAUAXQBcDQAAAQAlAF0NAAADAE8AZQ0AAAIAUAAzDQAABQAiABoABQq6DJgUAGEBBY4NAAABAC0AdQ0AAAEAAgB/DQAABABJAKkNAAACABgAMw0AAAMAEAA1AAQKf0cAAxkACgq3JFgEAJMDABkACgq3JFgEAJMDABoACQqAFpFnAOgBAAAA.Orspp:BAEBNQAECn8mAAMZAAoKPB2kGQCBAgqODQAABwBhAHUNAAAGAGEAfw0AAAYAXQCpDQAABQBdAFwNAAADAFUAXQ0AAAIAJQBlDQAAAgBJAKQNAAAFAEEAMw0AAAEAIwC5DQAAAQAwABkACAq+HaQZAIECCI4NAAAHAGEAdQ0AAAQAYQB/DQAABQBdAKkNAAADAF0AXA0AAAIAVQBdDQAAAQAlAGUNAAACAEkAuQ0AAAEAMAAaAAcKPxG/iQB5AQd1DQAAAgBSAH8NAAABACsAqQ0AAAIAHgBcDQAAAQAKAF0NAAABAC0ApA0AAAUATgAzDQAAAQARAAE1AAUUCAgrABkACx4A.',
Pa='Pakk:BAEBNQAECn88AAMDAAkK8RgaKAC+AQmODQAADABTAHUNAAALAEsAfw0AAAoAUwCpDQAACQBMAFwNAAAFAFYAXQ0AAAEAIgBlDQAAAgBGADMNAAAJAFIAuQ0AAAEAEwADAAgK2hsaKAC+AQiODQAADABTAHUNAAALAEsAfw0AAAoAUwCpDQAACQBMAFwNAAAFAFYAXQ0AAAEAIgBlDQAAAgBGADMNAAAJAFIABAABCnYHBbcAMgABuQ0AAAEAEwAAAA==.Pandotides:BAEANQAECggIEQABNQABCgIIAgAHAAAAAA==.Papadefensve:BAEANQAECgIIAQAAAA==.',
Ra='Razamon:BAEBNQAECn8rAAMJAAoK9xgfMQCcAgqODQAACABTAHUNAAAEADsAfw0AAAQAWwCpDQAABABiAFwNAAADAEEAXQ0AAAIAOQBlDQAABgAdAKQNAAAFABEAMw0AAAQARgC5DQAAAwBCAAkACgr3GB8xAJwCCo4NAAAHAFMAdQ0AAAQAOwB/DQAABABbAKkNAAAEAGIAXA0AAAMAQQBdDQAAAgA5AGUNAAAGAB0ApA0AAAUAEQAzDQAAAwBGALkNAAADAEIAFgACCuAHK/8ANAACjg0AAAEAFAAzDQAAAQAYAAAA.',
Re='Recurse:BAEANQADCggICAABNQAFFAoKGwAbALMXAA==.',
Ru='Runehaven:BAEANQADCggICAABNQAFFAIIAgAHAAAAAA==.',
Sa='Sairal:BAEANQAECgQIBwABNQAFFAgIHQARAFYcAA==.Sargala:BAEANQAECgUIDQAAAA==.',
Sc='Scootybooty:BAEANQAECgYIDAABNQAECgoKGAAZAN8QAA==.Scootypriest:BAEBNQAECn8YAAIZAAoK3xB/JgD6AQqODQAABABBAHUNAAADAC8Afw0AAAMAUQCpDQAAAwBCAFwNAAABACsAXQ0AAAEABwBlDQAAAQAvAKQNAAACACUAMw0AAAMANQC5DQAAAwAeABkACgrfEH8mAPoBCo4NAAAEAEEAdQ0AAAMALwB/DQAAAwBRAKkNAAADAEIAXA0AAAEAKwBdDQAAAQAHAGUNAAABAC8ApA0AAAIAJQAzDQAAAwA1ALkNAAADAB4AAAA=.',
Sm='Smitehaven:BAEBNQAECn8fAAIcAAkKeiD0DADMAgmODQAABgBTAHUNAAAEAFkAfw0AAAQAXgCpDQAABABbAFwNAAAEAFwAXQ0AAAMAVABlDQAAAgBQADMNAAADAEsAuQ0AAAEAOwAcAAkKeiD0DADMAgmODQAABgBTAHUNAAAEAFkAfw0AAAQAXgCpDQAABABbAFwNAAAEAFwAXQ0AAAMAVABlDQAAAgBQADMNAAADAEsAuQ0AAAEAOwABNQAFFAIIAgAHAAAAAA==.',
Tc='Tchoff:BAEANQAECggICAABNQAFFAgIHwABAIkeAA==.',
Th='Thez:BAEANQAECgUICgABNQAECgoKOAARALEhAA==.Thezadin:BAEANQAECgQIBAABNQAECgoKOAARALEhAA==.Thezdin:BAEBNQAECn84AAIRAAoKsSFIAwBsAwqODQAACgBXAHUNAAAFAF8Afw0AAAUAXgCpDQAABgBiAFwNAAAFAFwAXQ0AAAYAWgBlDQAACABUAKQNAAAFAEoAMw0AAAUAUQC5DQAAAQBCABEACgqxIUgDAGwDCo4NAAAKAFcAdQ0AAAUAXwB/DQAABQBeAKkNAAAGAGIAXA0AAAUAXABdDQAABgBaAGUNAAAIAFQApA0AAAUASgAzDQAABQBRALkNAAABAEIAAAA=.',
Un='Undecided:BAEANQADCgEIAQABNQAECgoKQgAGAJ8bAA==.',
Ve='Velohm:BAEANQAECgMIBAAAAA==.',
Wi='Wildbless:BAECNQAFFH8cAAIcAAkK1wgPBACiAQmODQAABgBCAHUNAAAEAAsAfw0AAAQAHgCpDQAABAAjAFwNAAACAAQAXQ0AAAEAAgBlDQAAAQAdAKQNAAABAAcAMw0AAAUAKgAcAAkK1wgPBACiAQmODQAABgBCAHUNAAAEAAsAfw0AAAQAHgCpDQAABAAjAFwNAAACAAQAXQ0AAAEAAgBlDQAAAQAdAKQNAAABAAcAMw0AAAUAKgA1AAQKfzkAAhwACgqDHpkPAKMCABwACgqDHpkPAKMCAAE1AAQKBAgIAAcAAAAA.Wildform:BAEANQAECgIIAwABNQAECgQICAAHAAAAAA==.Wildkill:BAEBNQAECn8WAAIXAAcKjiMyUwB3AgeODQAABABjAHUNAAADAF4Afw0AAAMAOwCpDQAAAwBTAFwNAAACAEwAZQ0AAAMAYwCkDQAABABcABcABwqOIzJTAHcCB44NAAAEAGMAdQ0AAAMAXgB/DQAAAwA7AKkNAAADAFMAXA0AAAIATABlDQAAAwBjAKQNAAAEAFwAATUABAoECAgABwAAAAA=.Wildshield:BAEANQAECgQICAAAAA==.',
Wr='Wrècks:BAEANQAECgYIBwABNQAECgUIBQAHAAAAAA==.Wrèckstorm:BAECNQAFFH8MAAIVAAQKjxxbAwD1AASODQAABgBOAHUNAAACAEMAfw0AAAEARgCpDQAAAwBIABUABAqPHFsDAPUABI4NAAAGAE4AdQ0AAAIAQwB/DQAAAQBGAKkNAAADAEgANQAECn9JAAMVAAoK4SFmBgDLAgAVAAoK4SFmBgDLAgAWAAYK1RgHtQAoAQABNQAECgUIBQAHAAAAAA==.',
Zi='Zick:BAEANQAFFAcIAQAAAA==.',
Zo='Zoe:BAEANQAECgQICAAAAA==.Zogle:BAECNQAFFH8ZAAIDAAkKSBWdBAA0AgmODQAABQBOAHUNAAADAB0Afw0AAAMAOwCpDQAABQBPAFwNAAACADwAXQ0AAAEAJABlDQAAAQAsAKQNAAABADQAMw0AAAQAYAADAAkKSBWdBAA0AgmODQAABQBOAHUNAAADAB0Afw0AAAMAOwCpDQAABQBPAFwNAAACADwAXQ0AAAEAJABlDQAAAQAsAKQNAAABADQAMw0AAAQAYAA1AAQKfzoAAgMACgr+JDcLAFkDAAMACgr+JDcLAFkDAAE1AAQKBAgIAAcAAAAA.',
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
