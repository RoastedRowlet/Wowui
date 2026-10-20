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

local lookup = {'DeathKnight-Unholy','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Rogue-Assassination','Warlock-Destruction','Unknown-Unknown','Druid-Feral','Priest-Shadow','DeathKnight-Frost','Warrior-Arms','Warrior-Fury','Shaman-Enhancement','Warlock-Demonology','Warlock-Affliction','Shaman-Restoration','Druid-Balance','Druid-Guardian','Paladin-Protection','Shaman-Elemental','Monk-Windwalker',}
local provider = {region='US',realm='Barthilas',name='US',type='subscribers',zone=53,date='2026-10-20',data={Al='Alithira:BAEANQAECgEIAwABNQAFFAQIBgABAFgHAA==.Aluggo:BAEBNQAECn8nAAMCAAoKQSQiBgCbAwqODQAABgBXAHUNAAAFAGAAfw0AAAUAYACpDQAABgBhAFwNAAADAGMAXQ0AAAMAYgBlDQAABQBdAKQNAAACAFYAMw0AAAMATAC5DQAAAQBgAAIACgpBJCIGAJsDCo4NAAAEAFcAdQ0AAAUAYAB/DQAABQBgAKkNAAAFAGEAXA0AAAMAYwBdDQAAAwBiAGUNAAAEAF0ApA0AAAIAVgAzDQAAAwBMALkNAAABAGAAAwADCsERoEMBtAADjg0AAAIAMwCpDQAAAQAzAGUNAAABACAAAAA=.',
Cu='Cutehunter:BAECNQAFFH8VAAMEAAYKUR6OAwAqAgaODQAABABfAHUNAAAEAF8Afw0AAAIASwCpDQAABQBjAFwNAAACABMAMw0AAAQAVwAEAAYKUR6OAwAqAgaODQAAAwBfAHUNAAACAF8Afw0AAAIASwCpDQAAAgBjAFwNAAACABMAMw0AAAEAEQAFAAQKWw98EQAmAQSODQAAAQAiAHUNAAACABUAqQ0AAAMAPQAzDQAAAwBXADUABAp/LwAEBQAKCq0laRAA5QIABQAJCo8faRAA5QIABAAJCuQmjTQAzgIABgABCl4QDhIARwAAAAA=.',
De='Deathseen:BAEANQADCgYIBgABNQAECggIGgAHAKYPAA==.Dehfack:BAEBNQAECn8dAAIBAAYKrAMxLgCnAAaODQAACAAGAHUNAAAGAAkAfw0AAAcACACpDQAABQAHAFwNAAACABEApA0AAAEABQABAAYKrAMxLgCnAAaODQAACAAGAHUNAAAGAAkAfw0AAAcACACpDQAABQAHAFwNAAACABEApA0AAAEABQAAAA==.',
Fo='Forseen:BAEBNQAECn8aAAIHAAgKpg/EGQD8AAiODQAABwA2AHUNAAAFACkAfw0AAAMAMACpDQAAAwAbAFwNAAADADkAXQ0AAAEAHQBlDQAAAQAdADMNAAADADoABwAICqYPxBkA/AAIjg0AAAcANgB1DQAABQApAH8NAAADADAAqQ0AAAMAGwBcDQAAAwA5AF0NAAABAB0AZQ0AAAEAHQAzDQAAAwA6AAAA.',
Fy='Fyrre:BAECNQAFFH8SAAIEAAUK8yCOBwDWAQWODQAABQBbAHUNAAADAFsAfw0AAAEAQACpDQAABQBGADMNAAAEAFoABAAFCvMgjgcA1gEFjg0AAAUAWwB1DQAAAwBbAH8NAAABAEAAqQ0AAAUARgAzDQAABABaADUABAp/NwACBAAKCngkXAIA2gIABAAKCngkXAIA2gIAAAA=.',
['Fô']='Fôrseen:BAEANQADCgcIEwABNQAECggIGgAHAKYPAA==.',
Hu='Huegreen:BAEANQAECgEIAQABNQAFFAcIGAAIAKkCAA==.',
Ji='Jingsho:BAEANQAECggIDwAAAA==.',
Kh='Khlp:BAEANQAECgEIAwABNQAECgQIBgAJAAAAAA==.',
['Kí']='Kíngkongkod:BAEANQAECgIIAwABNQAFFAUIFAAKAHokAA==.',
Lo='Lotheril:BAEBNQAECn8sAAIDAAoKwBkOPwDYAgqODQAABgBEAHUNAAAEAFUAfw0AAAQAQwCpDQAABgBCAFwNAAAEAFcAXQ0AAAMANQBlDQAABQBFAKQNAAAEAD4AMw0AAAcAUwC5DQAAAQAiAAMACgrAGQ4/ANgCCo4NAAAGAEQAdQ0AAAQAVQB/DQAABABDAKkNAAAGAEIAXA0AAAQAVwBdDQAAAwA1AGUNAAAFAEUApA0AAAQAPgAzDQAABwBTALkNAAABACIAATUABRQECAYAAQBYBwA=.',
Ma='Malpractis:BAEANQAECgQIBAABNQAFFAoKHwALAFMaAA==.Masamura:BAECNQAFFH8GAAIBAAQKWAe+AwDKAASODQAAAgAYAHUNAAABAAYAqQ0AAAIAGQAzDQAAAQAXAAEABApYB74DAMoABI4NAAACABgAdQ0AAAEABgCpDQAAAgAZADMNAAABABcANQAECn9OAAMBAAoK+xm9LQB7AgABAAkKCRu9LQB7AgAMAAUKiA9sZQANAQAAAA==.Mathstutorli:BAECNQAFFH8UAAIKAAUKeiTTAADsAQWODQAABgBjAHUNAAAEAFoAfw0AAAIAOQCpDQAABgBaADMNAAACAEwACgAFCnok0wAA7AEFjg0AAAYAYwB1DQAABABaAH8NAAACADkAqQ0AAAYAWgAzDQAAAgBMADUABAp/PgACCgAKCk0mmwAA7QMACgAKCk0mmwAA7QMAAAA=.',
Me='Meiizm:BAEANQADCgUJBQABNQAECgoKLgANAMwiAA==.Meiizy:BAEANQAECgEIAgABNQAECgoKLgANAMwiAA==.Meiz:BAEBNQAECn8uAAMNAAoKzCIKBgDDAwqODQAABgBZAHUNAAAFAGMAfw0AAAUAYwCpDQAABgBfAFwNAAAEAGIAXQ0AAAQAYgBlDQAABgBYAKQNAAAFAE0AMw0AAAQAXAC5DQAAAQBAAA0ACgrMIgoGAMMDCo4NAAAGAFkAdQ0AAAUAYwB/DQAABQBjAKkNAAAGAF8AXA0AAAMAYgBdDQAABABiAGUNAAAGAFgApA0AAAUATQAzDQAABABcALkNAAABAEAADgABCtcFzzQAMQABXA0AAAEADgAAAA==.',
Mi='Miidira:BAEBNQAECn8sAAMBAAoKmxS/SAD0AQqODQAABwA5AHUNAAAFADgAfw0AAAcAQQCpDQAABgAuAFwNAAAEAFAAXQ0AAAMAMABlDQAAAwA3AKQNAAADACsAMw0AAAUANgC5DQAAAQAhAAEACQokFb9IAPQBCY4NAAAHADkAdQ0AAAQAOAB/DQAABwBBAKkNAAAGAC4AXA0AAAQAUABdDQAAAgAwAGUNAAACADcAMw0AAAUANgC5DQAAAQAhAAwABAqoCwF4AMQABHUNAAABACwAXQ0AAAEACQBlDQAAAQAWAKQNAAADACsAATUABRQECAYAAQBYBwA=.',
Mo='Mofugga:BAEBNQAECn8dAAIPAAoK9SEJAgAyAgqODQAABABTAHUNAAADAFwAfw0AAAQAVQCpDQAABABYAFwNAAABAFoAXQ0AAAEAWABlDQAABQBQAKQNAAAFAE8AMw0AAAEAUgC5DQAAAQBaAA8ACgr1IQkCADICCo4NAAAEAFMAdQ0AAAMAXAB/DQAABABVAKkNAAAEAFgAXA0AAAEAWgBdDQAAAQBYAGUNAAAFAFAApA0AAAUATwAzDQAAAQBSALkNAAABAFoAATUABRQFCBQACgB6JAA=.Mourningsage:BAECNQAFFH8XAAMQAAcKlxdLBgAIAgeODQAABABYAHUNAAADADcAfw0AAAQANQCpDQAABQBTAFwNAAACADgAXQ0AAAEAEgAzDQAABABQABAABgoRGEsGAAgCBo4NAAAEAFgAfw0AAAQANQCpDQAABQBTAFwNAAACADgAXQ0AAAEAEgAzDQAABABQAAgAAQqvFd4bAE4AAXUNAAADADcANQAECn84AAQQAAoKfSOwFAA5AwAQAAoKXCOwFAA5AwAIAAYK4hgmGgCbAQARAAMKsCHBEgAeAQAAAA==.',
Ni='Nickbatum:BAEANQAECggIEQAAAA==.',
Nu='Nutshocker:BAEANQAECggICgAAAA==.',
Pa='Pafupafu:BAEANQAECgYIBwABNQAECgkJHwAEAOghAA==.',
Pe='Peterpikachu:BAEANQAECgMIAwABNQAECgkJGAASAD0SAA==.',
Ra='Randomno:BAECNQAFFH8YAAMIAAcKqQIqBwC4AAeODQAABQAPAHUNAAAEAAQAfw0AAAQAAgCpDQAABAAJAFwNAAACAAMAXQ0AAAEAAAAzDQAABAANABAABgqfAjYTAGIBBo4NAAADAAwAfw0AAAQAAgCpDQAAAQAJAFwNAAACAAMAXQ0AAAEAAAAzDQAABAANAAgAAwo8AyoHALgAA44NAAACAA8AdQ0AAAQABACpDQAAAwAEADUABAp/SQAECAAKCvwQPgkAZgIACAAJCioPPgkAZgIAEAAJCvwOEmQALQIAEQABCvAMjxIAPgAAAAA=.',
Ro='Roksta:BAEANQAECgUIBQABNQAECgcICwAJAAAAAA==.Rounnin:BAEANQADCgIIAgABNQAFFAQIBgABAFgHAA==.',
Sh='Sherkia:BAEANQADCgQIBgABNQAECgIIBAAJAAAAAA==.Sherko:BAEANQAECgIIBAAAAA==.Shruggo:BAEANQAECgcICgABNQAECgoKJwACAEEkAA==.',
Sk='Skorpbear:BAEBNQAECn8mAAQTAAoKZRGHEwA+AQqODQAACABSAHUNAAAHAFgAfw0AAAUARgCpDQAABQAqAFwNAAACABAAXQ0AAAEABABlDQAABQA6AKQNAAABABoAMw0AAAMASQC5DQAAAQAjABQABgqNGlgZAN8BBo4NAAABAFIAdQ0AAAEAWAB/DQAAAQBGAKkNAAABACoAZQ0AAAEAOgAzDQAAAgBJABMACgohC4cTAD4BCo4NAAAFABMAdQ0AAAQAOgB/DQAAAgBEAKkNAAACACAAXA0AAAIAEABdDQAAAQAEAGUNAAAEACEApA0AAAEAGgAzDQAAAQA6ALkNAAABACMACgAECjwMIisAuAAEjg0AAAIAFQB1DQAAAgAjAH8NAAACAA4AqQ0AAAIAJQAAAA==.Skorpionjr:BAEBNQAECn8gAAMDAAoKFRYFQgBCAQqODQAABgA8AHUNAAAFAEIAfw0AAAUALgCpDQAABAA3AFwNAAACAEYAXQ0AAAEAMgBlDQAABAA1AKQNAAACADwAMw0AAAIANQC5DQAAAQAiAAMACgoVFgVCAEIBCo4NAAAFADwAdQ0AAAQAQgB/DQAABQAuAKkNAAAEADcAXA0AAAIARgBdDQAAAQAyAGUNAAAEADUApA0AAAIAPAAzDQAAAgA1ALkNAAABACIAFQACCq8LhTQAOAACjg0AAAEAFAB1DQAAAQAnAAE1AAQKCgomABMAZREA.Skorprunes:BAEANQAECgUIDgABNQAECgoKJgATAGURAA==.',
Sp='Sparkmac:BAEANQAECgcIEAABNQAFFAcIFwAQAJcXAA==.',
Wa='Wafuwafu:BAEANQAECgcICAABNQAECgkJHwAEAOghAA==.Waterheart:BAEBNQAECn8YAAMSAAkKPRK7dgCnAQmODQAAAgAtAHUNAAACAEIAfw0AAAIAKgCpDQAAAgAiAFwNAAAEABsAXQ0AAAYAQABlDQAAAgAgAKQNAAADACgAuQ0AAAEAQgASAAkKPRK7dgCnAQmODQAAAgAtAHUNAAACAEIAfw0AAAIAKgCpDQAAAQAiAFwNAAADABsAXQ0AAAYAQABlDQAAAgAgAKQNAAACACgAuQ0AAAEAQgAWAAMKrhNnPgDPAAOpDQAAAQBGAFwNAAABAC0ApA0AAAEAIgAAAA==.',
Wi='Wijon:BAEBNQAECn83AAIXAAoKtBuMCwAdAwqODQAABgBVAHUNAAAHAFAAfw0AAAkAXACpDQAABwBaAFwNAAAGAEwAXQ0AAAMASwBlDQAABgBQAKQNAAAGAEkAMw0AAAQAXwC5DQAAAQAEABcACgq0G4wLAB0DCo4NAAAGAFUAdQ0AAAcAUAB/DQAACQBcAKkNAAAHAFoAXA0AAAYATABdDQAAAwBLAGUNAAAGAFAApA0AAAYASQAzDQAABABfALkNAAABAAQAAAA=.',
Xu='Xugi:BAEBNQAECn8YAAIQAAcKWRgNDgDWAQeODQAABAA5AHUNAAAEAFAAfw0AAAQAXACpDQAABAA/AFwNAAAEADwAXQ0AAAMARwCkDQAAAQApABAABwpZGA0OANYBB44NAAAEADkAdQ0AAAQAUAB/DQAABABcAKkNAAAEAD8AXA0AAAQAPABdDQAAAwBHAKQNAAABACkAATUABAoKCicAAgBBJAA=.',
Xx='Xxlanaconda:BAEANQAECggIDwABNQAFFAUIFAAKAHokAA==.',
Zy='Zygote:BAEBNQAECn8fAAIEAAkK6CFsBgBjAgmODQAABQBgAHUNAAAFAFsAfw0AAAMAVQCpDQAAAwBcAFwNAAADAF0AXQ0AAAMAYgBlDQAABQBVAKQNAAADAFIAuQ0AAAEANQAEAAkK6CFsBgBjAgmODQAABQBgAHUNAAAFAFsAfw0AAAMAVQCpDQAAAwBcAFwNAAADAF0AXQ0AAAMAYgBlDQAABQBVAKQNAAADAFIAuQ0AAAEANQAAAA==.',
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
