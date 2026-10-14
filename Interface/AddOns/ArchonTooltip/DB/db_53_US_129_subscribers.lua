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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Warrior-Arms','Hunter-Marksmanship','Shaman-Elemental','Druid-Balance','Priest-Holy','Druid-Restoration','Shaman-Restoration','Rogue-Assassination','Mage-Arcane','Priest-Shadow','DeathKnight-Blood','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Priest-Discipline','DemonHunter-Devourer','Evoker-Devastation','Evoker-Preservation','Paladin-Protection',}
local provider = {region='US',realm="Kel'Thuzad",name='US',type='subscribers',zone=53,date='2026-10-13',data={Ag='Agisa:BAEANQAECgUICQABNQAFFAIIAgABAAAAAA==.',
An='Anasi:BAEBNQAECn8hAAICAAgK1CMVMgDUAgiODQAABQBfAHUNAAAGAGEAfw0AAAUAYwCpDQAABQBaAFwNAAAEAFkAXQ0AAAIAXwBlDQAAAwBSADMNAAADAFQAAgAICtQjFTIA1AIIjg0AAAUAXwB1DQAABgBhAH8NAAAFAGMAqQ0AAAUAWgBcDQAABABZAF0NAAACAF8AZQ0AAAMAUgAzDQAAAwBUAAAA.',
Ar='Arlicdk:BAEANQADCgYIBgABNQAFFAcIDgADAPMZAA==.Arlicmad:BAECNQAFFH8OAAIDAAcK8xl8BgBVAgeODQAABAA1AHUNAAABACQAfw0AAAEAQACpDQAAAwBUAFwNAAACAEkAXQ0AAAEAVAAzDQAAAgAOAAMABwrzGXwGAFUCB44NAAAEADUAdQ0AAAEAJAB/DQAAAQBAAKkNAAADAFQAXA0AAAIASQBdDQAAAQBUADMNAAACAA4ANQAECn8qAAIDAAkKLSLcHABDAwADAAkKLSLcHABDAwAAAA==.Arliczap:BAEANQAECggIEgABNQAFFAcIDgADAPMZAA==.Armisbloo:BAECNQAFFH8XAAIDAAcKVB7nBQBiAgeODQAABABcAHUNAAADAE8Afw0AAAMAKwCpDQAABABSAFwNAAACAEoAXQ0AAAEAPAAzDQAABgBHAAMABwpUHucFAGICB44NAAAEAFwAdQ0AAAMATwB/DQAAAwArAKkNAAAEAFIAXA0AAAIASgBdDQAAAQA8ADMNAAAGAEcANQAECn8jAAIDAAkKUSIrFABpAwADAAkKUSIrFABpAwAAAA==.',
Ch='Cheekymunky:BAEANQAECgUIBgABNQAFFAQIDgAEALELAA==.',
Co='Conuremage:BAEANQAECgQICQABNQAFFAUIEgAFANMmAA==.Conuretotem:BAECNQAFFH8SAAIFAAUK0yZzBABJAgWODQAABQBjAHUNAAADAGIAfw0AAAIAYwCpDQAABQBjADMNAAADAGMABQAFCtMmcwQASQIFjg0AAAUAYwB1DQAAAwBiAH8NAAACAGMAqQ0AAAUAYwAzDQAAAwBjADUABAp/JAACBQAJCgQnVQAADAQABQAJCgQnVQAADAQAAAA=.',
Dl='Dlwlrma:BAEBNQAECn9SAAIGAAkK0CYvAAAPBAmODQAACQBjAHUNAAAKAGMAfw0AAAwAYwCpDQAACwBjAFwNAAAKAGMAXQ0AAAgAYwBlDQAACQBjAKQNAAAFAGEAMw0AAAgAYgAGAAkK0CYvAAAPBAmODQAACQBjAHUNAAAKAGMAfw0AAAwAYwCpDQAACwBjAFwNAAAKAGMAXQ0AAAgAYwBlDQAACQBjAKQNAAAFAGEAMw0AAAgAYgAAAA==.',
Ex='Extends:BAEBNQAECn8aAAIHAAkKfSBVEABCAwmODQAABABOAHUNAAAEAF8Afw0AAAQAYgCpDQAABABhAFwNAAADAFUAXQ0AAAIAWgBlDQAAAgBAAKQNAAACACkAMw0AAAEAYAAHAAkKfSBVEABCAwmODQAABABOAHUNAAAEAF8Afw0AAAQAYgCpDQAABABhAFwNAAADAFUAXQ0AAAIAWgBlDQAAAgBAAKQNAAACACkAMw0AAAEAYAAAAA==.',
Fa='Faada:BAEANQAECggIDQABNQAECgkJMgAIAE4UAA==.Faadi:BAEBNQAECn8yAAMIAAkKThSaIAAhAgmODQAACAA/AHUNAAAFADAAfw0AAAYATQCpDQAABAAoAFwNAAAFADgAXQ0AAAUAIgBlDQAABwBQAKQNAAAGABIAMw0AAAQALwAIAAkKThSaIAAhAgmODQAACAA/AHUNAAAFADAAfw0AAAUATQCpDQAAAwAoAFwNAAAFADgAXQ0AAAUAIgBlDQAABwBQAKQNAAAGABIAMw0AAAQALwAGAAIKqBCglQB7AAJ/DQAAAQA9AKkNAAABACoAAAA=.Faadiest:BAEANQAECgYICQABNQAECgkJMgAIAE4UAA==.Faadistrasz:BAEANQAECgYIDgABNQAECgkJMgAIAE4UAA==.Faadithustra:BAEBNQAECn8WAAIJAAgK2A6XdQCnAQiODQAABAAqAHUNAAADACYAfw0AAAQAQQCpDQAAAwA1AF0NAAABAB0AZQ0AAAQAJQCkDQAAAgAQADMNAAABABQACQAICtgOl3UApwEIjg0AAAQAKgB1DQAAAwAmAH8NAAAEAEEAqQ0AAAMANQBdDQAAAQAdAGUNAAAEACUApA0AAAIAEAAzDQAAAQAUAAE1AAQKCQkyAAgAThQA.Faád:BAEANQAECgUIDwABNQAECgkJMgAIAE4UAA==.',
Fo='Fofer:BAEANQAECggIDgABNQAFFAQIBAABAAAAAA==.',
Gg='Ggwpnoree:BAECNQAFFH8bAAIKAAcKdhxiAQCkAgeODQAABABSAHUNAAAFAFwAfw0AAAUAYwCpDQAABgBZAFwNAAADAF8AXQ0AAAEABAAzDQAAAwBNAAoABwp2HGIBAKQCB44NAAAEAFIAdQ0AAAUAXAB/DQAABQBjAKkNAAAGAFkAXA0AAAMAXwBdDQAAAQAEADMNAAADAE0ANQAECn84AAIKAAkKnSbZAQDEAwAKAAkKnSbZAQDEAwAAAA==.',
['Gú']='Gúr:BAEBNQAECn8iAAILAAgKNxoDfQCEAgiODQAABgA5AHUNAAAFAE8Afw0AAAUAVgCpDQAABQAwAFwNAAADADsAXQ0AAAMAUABlDQAAAQBMADMNAAAGAEEACwAICjcaA30AhAIIjg0AAAYAOQB1DQAABQBPAH8NAAAFAFYAqQ0AAAUAMABcDQAAAwA7AF0NAAADAFAAZQ0AAAEATAAzDQAABgBBAAAA.',
He='Heeka:BAECNQAFFH8TAAIMAAYKiBx5AwArAgaODQAABQBfAHUNAAADAFEAfw0AAAEACQCpDQAABABcAFwNAAABABYAMw0AAAUAXQAMAAYKiBx5AwArAgaODQAABQBfAHUNAAADAFEAfw0AAAEACQCpDQAABABcAFwNAAABABYAMw0AAAUAXQA1AAQKfygAAgwACQqwJOcHAFsDAAwACQqwJOcHAFsDAAAA.Hemon:BAEANQAECgUICQABNQAFFAIIAgABAAAAAA==.',
Jo='Jonnyclaude:BAEANQAECgMIBQAAAA==.',
Lu='Lucere:BAEANQADCggICAABNQAFFAYIFQANAIgdAA==.',
Ma='Maxdeeps:BAEANQAECgEIAQABNQAFFAQIDgAEALELAA==.',
Ni='Nihillus:BAEBNQAECn8lAAQOAAkK/g7eDgBfAQmODQAABwAxAHUNAAAFADIAfw0AAAYAPgCpDQAABgA4AFwNAAADACMAXQ0AAAEACwBlDQAAAwApAKQNAAACABgAMw0AAAQAMgAPAAkKQQ08dQD+AQmODQAABQAxAHUNAAABACoAfw0AAAMAKQCpDQAAAwA1AFwNAAABAA8AXQ0AAAEACwBlDQAAAwApAKQNAAACABgAMw0AAAMAMgAOAAYKDRDeDgBfAQaODQAAAgAhAHUNAAACACcAfw0AAAIALgCpDQAAAgA4AFwNAAACACMAMw0AAAEAKAAQAAMKjw39RQCtAAN1DQAAAgAyAH8NAAABAD4AqQ0AAAEAEwAAAA==.',
Pe='Peavers:BAEANQAECggIDgABNQAECgkJGgAHAH0gAA==.',
Ru='Rukemage:BAEBNQAECn8lAAILAAkK1h41VwDRAgmODQAABABcAHUNAAAFAFYAfw0AAAUAUgCpDQAABQBLAFwNAAAEAE8AXQ0AAAQAWwBlDQAAAwBGAKQNAAABADgAMw0AAAYAVQALAAkK1h41VwDRAgmODQAABABcAHUNAAAFAFYAfw0AAAUAUgCpDQAABQBLAFwNAAAEAE8AXQ0AAAQAWwBlDQAAAwBGAKQNAAABADgAMw0AAAYAVQAAAA==.',
Ry='Ryaris:BAEANQAECgYIDwABNQAFFAYIFQANAIgdAA==.Ryathe:BAECNQAFFH8VAAINAAYKiB2cBAAtAgaODQAABABZAHUNAAAEADsAfw0AAAQAYACpDQAABQBQAFwNAAABAEgAMw0AAAMATQANAAYKiB2cBAAtAgaODQAABABZAHUNAAAEADsAfw0AAAQAYACpDQAABQBQAFwNAAABAEgAMw0AAAMATQA1AAQKfygAAg0ACQr8JIIKAGADAA0ACQr8JIIKAGADAAAA.',
Sh='Shikdk:BAECNQAFFH8OAAINAAUKkw66EgAnAQWODQAABAAwAHUNAAADAB0Afw0AAAIALwCpDQAABAAiADMNAAABACoADQAFCpMOuhIAJwEFjg0AAAQAMAB1DQAAAwAdAH8NAAACAC8AqQ0AAAQAIgAzDQAAAQAqADUABAp/KQACDQAJCrAcEx4AvwIADQAJCrAcEx4AvwIAAAA=.Shikdruid:BAEANQAECgMIBgABNQAFFAUIDgANAJMOAA==.Shikpally:BAEANQAECgUICQABNQAFFAUIDgANAJMOAA==.',
Si='Sickhouse:BAEBNQAECn8eAAMRAAgKJR2CBAB+AgiODQAABAA0AHUNAAAEAE0Afw0AAAQASgCpDQAABABBAFwNAAACAEQAXQ0AAAIATwBlDQAAAwBYADMNAAAHAFsAEQAICuIaggQAfgIIjg0AAAEANAB1DQAAAgBNAH8NAAACAEoAqQ0AAAEAQQBcDQAAAgBEAF0NAAACAE8AZQ0AAAEALQAzDQAABQBXAAcABgrIFTCAAJMBBo4NAAADABgAdQ0AAAIAGgB/DQAAAgArAKkNAAADADwAZQ0AAAIAWAAzDQAAAgBbAAAA.',
To='Tonymá:BAEANQADCgUJBgABNQAECgkJJwALAPUVAA==.',
Tr='Trumpetdh:BAEBNQAECn8jAAISAAkKtR/LEADnAgmODQAABwBZAHUNAAAGAFUAfw0AAAUAYACpDQAABQBRAFwNAAADAE4AXQ0AAAMAVABlDQAAAwBRAKQNAAABAEIAMw0AAAIAIAASAAkKtR/LEADnAgmODQAABwBZAHUNAAAGAFUAfw0AAAUAYACpDQAABQBRAFwNAAADAE4AXQ0AAAMAVABlDQAAAwBRAKQNAAABAEIAMw0AAAIAIAAAAA==.Trumpetman:BAEANQADCgYICAABNQAECgkJIwASALUfAA==.',
Va='Variable:BAECNQAFFH8JAAILAAQKTxbMJABZAQSODQAABABQAHUNAAABABUAfw0AAAEAPgCpDQAAAwBFAAsABApPFswkAFkBBI4NAAAEAFAAdQ0AAAEAFQB/DQAAAQA+AKkNAAADAEUANQAECn8tAAILAAkKWSEYJABNAwALAAkKWSEYJABNAwAAAA==.',
Vr='Vrisard:BAEBNQAECn8yAAITAAkKbiO5AgCFAwmODQAABwBaAHUNAAAHAGEAfw0AAAcAWgCpDQAABwBeAFwNAAAGAFQAXQ0AAAQAYABlDQAABABSAKQNAAADAFgAMw0AAAUAWgATAAkKbiO5AgCFAwmODQAABwBaAHUNAAAHAGEAfw0AAAcAWgCpDQAABwBeAFwNAAAGAFQAXQ0AAAQAYABlDQAABABSAKQNAAADAFgAMw0AAAUAWgAAAA==.',
Wa='Waluigi:BAEANQAECgYIEAABNQAFFAcIFAAUAGIMAA==.',
Xa='Xanteer:BAEANQAFFAEIAQABNQAFFAcIFQAVAPsdAA==.Xantier:BAECNQAFFH8VAAIVAAcK+x2xAQA/AgeODQAABABPAHUNAAADAFUAfw0AAAIASgCpDQAABABRAFwNAAACAEAAXQ0AAAEASAAzDQAABQBTABUABwr7HbEBAD8CB44NAAAEAE8AdQ0AAAMAVQB/DQAAAgBKAKkNAAAEAFEAXA0AAAIAQABdDQAAAQBIADMNAAAFAFMANQAECn8jAAIVAAkKuSNqBwAqAwAVAAkKuSNqBwAqAwAAAA==.',
Za='Zaffz:BAEANQAECgQICAABNQAFFAIIAgABAAAAAA==.Zanansi:BAEANQABCgQJBAABNQAECggIIQACANQjAA==.',
['Zè']='Zèro:BAEANQADCgYIBgABNQADCgYIDQABAAAAAA==.',
['Zé']='Zérò:BAEANQADCgYIDQAAAA==.',
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
