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

local lookup = {'Unknown-Unknown','Warrior-Arms','Shaman-Elemental','Hunter-Marksmanship','Druid-Balance','Priest-Holy','Druid-Restoration','Druid-Guardian','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Rogue-Assassination','Mage-Arcane','Priest-Shadow','Priest-Discipline','DemonHunter-Devourer','Evoker-Devastation','Evoker-Preservation','Paladin-Protection',}
local provider = {region='US',realm="Kel'Thuzad",name='US',type='subscribers',zone=53,date='2026-10-20',data={Ag='Agisa:BAEANQAECgYICgABNQAFFAIIAgABAAAAAA==.',
Ar='Arlicdk:BAEANQADCgYIBgABNQAFFAcIDgACAPMZAA==.Arlicmad:BAECNQAFFH8OAAICAAcK8xnPBgBVAgeODQAABAA1AHUNAAABACQAfw0AAAEAQACpDQAAAwBUAFwNAAACAEkAXQ0AAAEAVAAzDQAAAgAOAAIABwrzGc8GAFUCB44NAAAEADUAdQ0AAAEAJAB/DQAAAQBAAKkNAAADAFQAXA0AAAIASQBdDQAAAQBUADMNAAACAA4ANQAECn8uAAICAAoK2x9NHQBCAwACAAoK2x9NHQBCAwAAAA==.Arliczap:BAEBNQAECn8ZAAIDAAoKkhUQEACVAQqODQAABgBTAHUNAAACAEQAfw0AAAIAPwCpDQAAAwBCAFwNAAACACUAXQ0AAAEADQBlDQAABABSAKQNAAADAEEAMw0AAAEADgC5DQAAAQAWAAMACgqSFRAQAJUBCo4NAAAGAFMAdQ0AAAIARAB/DQAAAgA/AKkNAAADAEIAXA0AAAIAJQBdDQAAAQANAGUNAAAEAFIApA0AAAMAQQAzDQAAAQAOALkNAAABABYAATUABRQHCA4AAgDzGQA=.Armisbloo:BAECNQAFFH8YAAICAAcKVB44BgBhAgeODQAABABcAHUNAAADAE8Afw0AAAMAKwCpDQAABABSAFwNAAACAEoAXQ0AAAEAPAAzDQAABwBHAAIABwpUHjgGAGECB44NAAAEAFwAdQ0AAAMATwB/DQAAAwArAKkNAAAEAFIAXA0AAAIASgBdDQAAAQA8ADMNAAAHAEcANQAECn8oAAICAAoKpyKHFABpAwACAAoKpyKHFABpAwAAAA==.',
Ch='Cheekymunky:BAEANQAECgcICgABNQAFFAQIDgAEALELAA==.',
Co='Conuretotem:BAECNQAFFH8YAAIDAAYKvyUvAQC4AQaODQAABgBjAHUNAAAEAGIAfw0AAAMAYwCpDQAABgBjAFwNAAABAFgAMw0AAAQAZAADAAYKvyUvAQC4AQaODQAABgBjAHUNAAAEAGIAfw0AAAMAYwCpDQAABgBjAFwNAAABAFgAMw0AAAQAZAA1AAQKfycAAgMACgqxJlcAAAwEAAMACgqxJlcAAAwEAAAA.',
Dl='Dlwlrma:BAEBNQAECn9fAAIFAAoKlSYzAAAPBAqODQAACgBjAHUNAAAMAGMAfw0AAA4AYwCpDQAADABjAFwNAAALAGQAXQ0AAAkAYwBlDQAACwBjAKQNAAAHAGEAMw0AAAgAYgC5DQAAAQBeAAUACgqVJjMAAA8ECo4NAAAKAGMAdQ0AAAwAYwB/DQAADgBjAKkNAAAMAGMAXA0AAAsAZABdDQAACQBjAGUNAAALAGMApA0AAAcAYQAzDQAACABiALkNAAABAF4AAAA=.',
Ex='Extends:BAEBNQAECn8fAAIGAAoK3SCsEABCAwqODQAABQBOAHUNAAAFAF8Afw0AAAUAYgCpDQAABABhAFwNAAADAFUAXQ0AAAIAWgBlDQAAAgBAAKQNAAADADwAMw0AAAEAYAC5DQAAAQBKAAYACgrdIKwQAEIDCo4NAAAFAE4AdQ0AAAUAXwB/DQAABQBiAKkNAAAEAGEAXA0AAAMAVQBdDQAAAgBaAGUNAAACAEAApA0AAAMAPAAzDQAAAQBgALkNAAABAEoAAAA=.',
Fa='Faada:BAEANQAECggIDQABNQAFFAMIBgAHADIOAA==.Faadi:BAECNQAFFH8GAAMHAAMKMg60EQCDAAOODQAAAwAXAHUNAAABAAcAMw0AAAIATQAHAAIKNAa0EQCDAAKODQAAAwAXAHUNAAABAAcABQABCgAAXRYAAAABMw0AAAIADgA1AAQKfzgABAcACgqqFPMgACICAAcACgqqFPMgACICAAUAAgqoEEWXAHsAAAgAAQr9HgMtAFsAAAAA.Faadiest:BAEANQAECgYICQABNQAFFAMIBgAHADIOAA==.Faadious:BAEANQAECgEIAQABNQAFFAMIBgAHADIOAA==.Faadistrasz:BAEANQAECgYIDgABNQAFFAMIBgAHADIOAA==.Faadithustra:BAEBNQAECn8aAAIJAAkKuxHgNAAQAQmODQAABQBDAHUNAAADACYAfw0AAAQAQQCpDQAAAwA1AF0NAAABAB0AZQ0AAAUAUACkDQAAAwAsADMNAAABABQAuQ0AAAEABwAJAAkKuxHgNAAQAQmODQAABQBDAHUNAAADACYAfw0AAAQAQQCpDQAAAwA1AF0NAAABAB0AZQ0AAAUAUACkDQAAAwAsADMNAAABABQAuQ0AAAEABwABNQAFFAMIBgAHADIOAA==.Faád:BAEBNQAECn8XAAQKAAgK6A5WQgAIAQiODQAABQAdAHUNAAAEAC8Afw0AAAQAOwCpDQAABQAqAFwNAAABAC4AXQ0AAAEAKABlDQAAAgAVADMNAAABAB4ACgAGCjMOVkIACAEGjg0AAAUAHQB/DQAABAA7AKkNAAAEACoAXA0AAAEALgBdDQAAAQAoAGUNAAABABUACwACCs0MS2QAWwACdQ0AAAQALwCpDQAAAQASAAwAAgrQB3gTADgAAmUNAAABABMAMw0AAAEAHgABNQAFFAMIBgAHADIOAA==.',
Fo='Fofer:BAEANQAECggIDwABNQAFFAYIEgANAPMZAA==.',
Ge='Gearsz:BAEANQAECgIIAQAAAA==.',
Gg='Ggwpnoree:BAECNQAFFH8bAAIOAAcKdhx8AQCjAgeODQAABABSAHUNAAAFAFwAfw0AAAUAYwCpDQAABgBZAFwNAAADAF8AXQ0AAAEABAAzDQAAAwBNAA4ABwp2HHwBAKMCB44NAAAEAFIAdQ0AAAUAXAB/DQAABQBjAKkNAAAGAFkAXA0AAAMAXwBdDQAAAQAEADMNAAADAE0ANQAECn86AAIOAAoK2CXsAQDEAwAOAAoK2CXsAQDEAwAAAA==.',
['Gú']='Gúr:BAEBNQAECn8iAAIPAAgKNxrOfQCDAgiODQAABgA5AHUNAAAFAE8Afw0AAAUAVgCpDQAABQAwAFwNAAADADsAXQ0AAAMAUABlDQAAAQBMADMNAAAGAEEADwAICjcazn0AgwIIjg0AAAYAOQB1DQAABQBPAH8NAAAFAFYAqQ0AAAUAMABcDQAAAwA7AF0NAAADAFAAZQ0AAAEATAAzDQAABgBBAAAA.',
He='Heeka:BAECNQAFFH8YAAIQAAYKWCCgAQBzAQaODQAABgBfAHUNAAAEAFEAfw0AAAIAOwCpDQAABQBcAFwNAAACAD0AMw0AAAUAXQAQAAYKWCCgAQBzAQaODQAABgBfAHUNAAAEAFEAfw0AAAIAOwCpDQAABQBcAFwNAAACAD0AMw0AAAUAXQA1AAQKfywAAhAACgobIxAIAFsDABAACgobIxAIAFsDAAAA.Hemon:BAEANQAECgUICQABNQAFFAIIAgABAAAAAA==.',
Jo='Jonnyclaude:BAEANQAECgMICAABNQAECgYIBQABAAAAAA==.',
Lu='Lucere:BAEANQADCggICAABNQAFFAYIFgANAIgdAA==.',
Ma='Maxdeeps:BAEANQAECgEIAwABNQAFFAQIDgAEALELAA==.',
Ni='Nihillus:BAEBNQAECn8tAAQKAAoKuA8tLQBBAQqODQAACAAxAHUNAAAGADkAfw0AAAcAPgCpDQAABwA4AFwNAAADACMAXQ0AAAEACwBlDQAABAApAKQNAAADABgAMw0AAAUAQwC5DQAAAQAtAAwABgoNEAoPAF8BBo4NAAACACEAdQ0AAAIAJwB/DQAAAgAuAKkNAAACADgAXA0AAAIAIwAzDQAAAQAoAAoACgqYDi0tAEEBCo4NAAAGADEAdQ0AAAIAOQB/DQAABAAyAKkNAAAEADUAXA0AAAEADwBdDQAAAQALAGUNAAAEACkApA0AAAMAGAAzDQAABABDALkNAAABAC0ACwADCo8Nb0YArQADdQ0AAAIAMgB/DQAAAQA+AKkNAAABABMAAAA=.',
Pe='Peavers:BAEANQAECggIDgABNQAECgoKHwAGAN0gAA==.',
Ru='Rukemage:BAEBNQAECn8lAAIPAAkK1h4vWADQAgmODQAABABcAHUNAAAFAFYAfw0AAAUAUgCpDQAABQBLAFwNAAAEAE8AXQ0AAAQAWwBlDQAAAwBGAKQNAAABADgAMw0AAAYAVQAPAAkK1h4vWADQAgmODQAABABcAHUNAAAFAFYAfw0AAAUAUgCpDQAABQBLAFwNAAAEAE8AXQ0AAAQAWwBlDQAAAwBGAKQNAAABADgAMw0AAAYAVQAAAA==.',
Ry='Ryaris:BAEANQAECgYIDwABNQAFFAYIFgANAIgdAA==.Ryathe:BAECNQAFFH8WAAINAAYKiB3jBAAtAgaODQAABABZAHUNAAAEADsAfw0AAAQAYACpDQAABQBQAFwNAAABAEgAMw0AAAQATQANAAYKiB3jBAAtAgaODQAABABZAHUNAAAEADsAfw0AAAQAYACpDQAABQBQAFwNAAABAEgAMw0AAAQATQA1AAQKfysAAg0ACgoLJaoKAF8DAA0ACgoLJaoKAF8DAAAA.',
Sh='Shikdk:BAECNQAFFH8OAAINAAUKkw4gEwAnAQWODQAABAAwAHUNAAADAB0Afw0AAAIALwCpDQAABAAiADMNAAABACoADQAFCpMOIBMAJwEFjg0AAAQAMAB1DQAAAwAdAH8NAAACAC8AqQ0AAAQAIgAzDQAAAQAqADUABAp/KQACDQAJCrAcdB4AvgIADQAJCrAcdB4AvgIAAAA=.Shikdruid:BAEANQAECgMICQABNQAFFAUIDgANAJMOAA==.Shikpally:BAEANQAECgUICQABNQAFFAUIDgANAJMOAA==.',
Si='Sickhouse:BAEBNQAECn8hAAMRAAoKwhyKBAB/AgqODQAABAA0AHUNAAAEAE0Afw0AAAQASgCpDQAABABBAFwNAAACAEQAXQ0AAAIATwBlDQAABABYAKQNAAABAGAAMw0AAAcAWwC5DQAAAQAqABEACAriGooEAH8CCI4NAAABADQAdQ0AAAIATQB/DQAAAgBKAKkNAAABAEEAXA0AAAIARABdDQAAAgBPAGUNAAABAC0AMw0AAAUAVwAGAAgKJBdNRgD1AAiODQAAAwAYAHUNAAACABoAfw0AAAIAKwCpDQAAAwA8AGUNAAADAFgApA0AAAEAYAAzDQAAAgBbALkNAAABACoAAAA=.',
Ss='Ssixx:BAEANQADCgYIBgABNQAECgoKJgACAKoZAA==.',
To='Tonymá:BAEANQADCgUJBgABNQAECgoKLQAPAF0VAA==.',
Tr='Trumpetdh:BAEBNQAECn8oAAISAAoK9h39CwAgAwqODQAACABZAHUNAAAHAFUAfw0AAAUAYACpDQAABQBRAFwNAAADAE4AXQ0AAAMAVABlDQAABABRAKQNAAACAEIAMw0AAAIAIAC5DQAAAQAtABIACgr2Hf0LACADCo4NAAAIAFkAdQ0AAAcAVQB/DQAABQBgAKkNAAAFAFEAXA0AAAMATgBdDQAAAwBUAGUNAAAEAFEApA0AAAIAQgAzDQAAAgAgALkNAAABAC0AAAA=.Trumpetman:BAEANQADCgYICAABNQAECgoKKAASAPYdAA==.',
Va='Variable:BAECNQAFFH8JAAIPAAQKTxa7JQBaAQSODQAABABQAHUNAAABABUAfw0AAAEAPgCpDQAAAwBFAA8ABApPFrslAFoBBI4NAAAEAFAAdQ0AAAEAFQB/DQAAAQA+AKkNAAADAEUANQAECn8uAAIPAAoK1h/hJABLAwAPAAoK1h/hJABLAwAAAA==.',
Vr='Vrisard:BAEBNQAECn88AAITAAoKMiLPAgCEAwqODQAABwBaAHUNAAAJAGEAfw0AAAkAWgCpDQAABwBeAFwNAAAGAFQAXQ0AAAQAYABlDQAABABSAKQNAAAFAFgAMw0AAAcAWgC5DQAAAgBBABMACgoyIs8CAIQDCo4NAAAHAFoAdQ0AAAkAYQB/DQAACQBaAKkNAAAHAF4AXA0AAAYAVABdDQAABABgAGUNAAAEAFIApA0AAAUAWAAzDQAABwBaALkNAAACAEEAAAA=.',
Wa='Waluigi:BAEANQAECgYIEAABNQAFFAgIFgAUAOIKAA==.',
Xa='Xanteer:BAEANQAFFAEIAgABNQAFFAcIFQAVAPsdAA==.Xantier:BAECNQAFFH8VAAIVAAcK+x3BAQA+AgeODQAABABPAHUNAAADAFUAfw0AAAIASgCpDQAABABRAFwNAAACAEAAXQ0AAAEASAAzDQAABQBTABUABwr7HcEBAD4CB44NAAAEAE8AdQ0AAAMAVQB/DQAAAgBKAKkNAAAEAFEAXA0AAAIAQABdDQAAAQBIADMNAAAFAFMANQAECn8kAAIVAAkKuSOLBwApAwAVAAkKuSOLBwApAwAAAA==.',
Za='Zaffz:BAEANQAECgQICAABNQAFFAIIAgABAAAAAA==.',
['Zè']='Zèro:BAEANQADCggICAAAAA==.',
['Zé']='Zérò:BAEANQADCgcIFQABNQADCggICAABAAAAAA==.',
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
