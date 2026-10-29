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

local lookup = {'DeathKnight-Unholy','Paladin-Holy','Paladin-Retribution','Hunter-Marksmanship','Priest-Shadow','Hunter-BeastMastery','Hunter-Survival','Rogue-Assassination','Warlock-Destruction','Unknown-Unknown','Druid-Feral','DeathKnight-Frost','Shaman-Enhancement','Warlock-Demonology','Warlock-Affliction','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','Druid-Balance','Paladin-Protection','Shaman-Elemental',}
local provider = {region='US',realm='Barthilas',name='US',type='subscribers',zone=53,date='2026-10-27',data={Al='Alithira:BAEANQAECgIIAQABNQAFFAQIBgABAFgHAA==.Aluggo:BAEBNQAECn80AAMCAAoKbSQiBgCbAwqODQAACABXAHUNAAAHAGAAfw0AAAcAYACpDQAABwBhAFwNAAAEAGMAXQ0AAAQAYgBlDQAABgBdAKQNAAADAFoAMw0AAAQATAC5DQAAAgBgAAIACgptJCIGAJsDCo4NAAAGAFcAdQ0AAAcAYAB/DQAABwBgAKkNAAAGAGEAXA0AAAQAYwBdDQAABABiAGUNAAAFAF0ApA0AAAMAWgAzDQAABABMALkNAAACAGAAAwADCsERoEMBtAADjg0AAAIAMwCpDQAAAQAzAGUNAAABACAAAAA=.',
Ca='Cakelynn:BAEBNQAECn8YAAIEAAcKqhcQHAAgAQeODQAABQBEAKkNAAACAD8AXA0AAAIAKgBlDQAABQA5AKQNAAAFADgAMw0AAAIADgC5DQAAAwBLAAQABwqqFxAcACABB44NAAAFAEQAqQ0AAAIAPwBcDQAAAgAqAGUNAAAFADkApA0AAAUAOAAzDQAAAgAOALkNAAADAEsAATUABRQGCAkABQAUEgA=.',
Cr='Crumbshot:BAEBNQAECn8qAAIGAAoKjhcEQwCiAgqODQAABgBRAHUNAAAFAEwAfw0AAAUALwCpDQAABQA+AFwNAAAFAEcAXQ0AAAUANQBlDQAABwAwAKQNAAABADsAMw0AAAIASAC5DQAAAQAdAAYACgqOFwRDAKICCo4NAAAGAFEAdQ0AAAUATAB/DQAABQAvAKkNAAAFAD4AXA0AAAUARwBdDQAABQA1AGUNAAAHADAApA0AAAEAOwAzDQAAAgBIALkNAAABAB0AAAA=.',
Cu='Cutehunter:BAECNQAFFH8XAAMGAAcKLx6OAwAqAgeODQAABABfAHUNAAAEAF8Afw0AAAIASwCpDQAABQBjAFwNAAACABMAZQ0AAAEASwAzDQAABQBXAAYABgpRHo4DACoCBo4NAAADAF8AdQ0AAAIAXwB/DQAAAgBLAKkNAAACAGMAXA0AAAIAEwAzDQAAAQARAAQABQruEnwRACYBBY4NAAABACIAdQ0AAAIAFQCpDQAAAwA9AGUNAAABAEsAMw0AAAQAVwA1AAQKfzkABAQACgqtJWkQAOUCAAQACQq7H2kQAOUCAAYACQrkJo00AM4CAAcAAQpeEA4SAEcAAAAA.',
De='Deathseen:BAEANQADCgYIBgABNQAECggIGgAIAKYPAA==.Dehfack:BAEBNQAECn8oAAIBAAcKfwNaQQC0AAeODQAACgAGAHUNAAAIAAkAfw0AAAsACACpDQAABgAHAFwNAAACABEApA0AAAEABQC5DQAAAgAGAAEABwp/A1pBALQAB44NAAAKAAYAdQ0AAAgACQB/DQAACwAIAKkNAAAGAAcAXA0AAAIAEQCkDQAAAQAFALkNAAACAAYAAAA=.',
Fo='Forseen:BAEBNQAECn8aAAIIAAgKpg8zNgAAAgiODQAABwA2AHUNAAAFACkAfw0AAAMAMACpDQAAAwAbAFwNAAADADkAXQ0AAAEAHQBlDQAAAQAdADMNAAADADoACAAICqYPMzYAAAIIjg0AAAcANgB1DQAABQApAH8NAAADADAAqQ0AAAMAGwBcDQAAAwA5AF0NAAABAB0AZQ0AAAEAHQAzDQAAAwA6AAAA.',
Fy='Fyrre:BAECNQAFFH8VAAIGAAYKLyFzAwB7AQaODQAABQBbAHUNAAAEAFsAfw0AAAEAQACpDQAABgBGAFwNAAABAFYAMw0AAAQAWgAGAAYKLyFzAwB7AQaODQAABQBbAHUNAAAEAFsAfw0AAAEAQACpDQAABgBGAFwNAAABAFYAMw0AAAQAWgA1AAQKf0AAAgYACgomJSoOAG8DAAYACgomJSoOAG8DAAAA.',
['Fô']='Fôrseen:BAEANQADCgcIEwABNQAECggIGgAIAKYPAA==.',
Hu='Huegreen:BAEANQAECgEIAQABNQAFFAgIGgAJAGcCAA==.',
Ji='Jingsho:BAEANQAECggIDwAAAA==.',
Kh='Khlp:BAEANQAECgEIAwABNQAECgQIBQAKAAAAAA==.',
['Kí']='Kíngkongkod:BAEANQAECggICgABNQAFFAUIFQALAHokAA==.',
Lo='Lotheril:BAEBNQAECn82AAIDAAoKmBvALgBBAgqODQAABwBEAHUNAAAFAFUAfw0AAAUAQwCpDQAABwBCAFwNAAAFAFcAXQ0AAAQAOgBlDQAABgBSAKQNAAAFAD4AMw0AAAgAUwC5DQAAAgA2AAMACgqYG8AuAEECCo4NAAAHAEQAdQ0AAAUAVQB/DQAABQBDAKkNAAAHAEIAXA0AAAUAVwBdDQAABAA6AGUNAAAGAFIApA0AAAUAPgAzDQAACABTALkNAAACADYAATUABRQECAYAAQBYBwA=.',
Ma='Malpractis:BAEANQAECgQIBAABNQAFFAoKJwAFADgeAA==.Masamura:BAECNQAFFH8GAAIBAAQKWAdBBgDIAASODQAAAgAYAHUNAAABAAYAqQ0AAAIAGQAzDQAAAQAXAAEABApYB0EGAMgABI4NAAACABgAdQ0AAAEABgCpDQAAAgAZADMNAAABABcANQAECn9XAAMBAAoKkxw3FgDPAQABAAkKtRw3FgDPAQAMAAUKyxFsZQANAQAAAA==.Mathstutorli:BAECNQAFFH8VAAILAAUKeiTTAADsAQWODQAABgBjAHUNAAAEAFoAfw0AAAIAOQCpDQAABgBaADMNAAADAFcACwAFCnok0wAA7AEFjg0AAAYAYwB1DQAABABaAH8NAAACADkAqQ0AAAYAWgAzDQAAAwBXADUABAp/TgACCwAKCnImmwAA7QMACwAKCnImmwAA7QMAAAA=.',
Mi='Miidira:BAEBNQAECn8uAAMBAAoKHRW/SAD0AQqODQAABwA5AHUNAAAFADgAfw0AAAcAQQCpDQAABgAuAFwNAAAEAFAAXQ0AAAMAMABlDQAAAwA3AKQNAAAEADIAMw0AAAUANgC5DQAAAgAkAAEACQpJFb9IAPQBCY4NAAAHADkAdQ0AAAQAOAB/DQAABwBBAKkNAAAGAC4AXA0AAAQAUABdDQAAAgAwAGUNAAACADcAMw0AAAUANgC5DQAAAgAkAAwABApsDAF4AMQABHUNAAABACwAXQ0AAAEACQBlDQAAAQAWAKQNAAAEADIAATUABRQECAYAAQBYBwA=.',
Mo='Mofugga:BAEBNQAECn8lAAINAAoKiCL2AwBZAwqODQAABQBTAHUNAAAEAFwAfw0AAAUAVQCpDQAABQBgAFwNAAACAFoAXQ0AAAIAWABlDQAABgBQAKQNAAAFAE8AMw0AAAEAUgC5DQAAAgBeAA0ACgqIIvYDAFkDCo4NAAAFAFMAdQ0AAAQAXAB/DQAABQBVAKkNAAAFAGAAXA0AAAIAWgBdDQAAAgBYAGUNAAAGAFAApA0AAAUATwAzDQAAAQBSALkNAAACAF4AATUABRQFCBUACwB6JAA=.Moojesticc:BAEANQADCgcIDgABNQAECgoKKgAGAI4XAA==.Mourningsage:BAECNQAFFH8ZAAQOAAgKKxVLBgAIAgiODQAABABYAHUNAAADADcAfw0AAAQANQCpDQAABQBTAFwNAAACADgAXQ0AAAEAEgBlDQAAAQAXADMNAAAFAFAADgAGChEYSwYACAIGjg0AAAQAWAB/DQAABAA1AKkNAAAFAFMAXA0AAAIAOABdDQAAAQASADMNAAAFAFAADwABCg8JNQgAVwABZQ0AAAEAFwAJAAEKrxXeGwBOAAF1DQAAAwA3ADUABAp/QwAEDgAKCjklNgQAKQMADgAKChglNgQAKQMACQAGCuIYJhoAmwEADwADCrAhwRIAHgEAAAA=.',
Ni='Nickbatum:BAEANQAECggIEQAAAA==.',
Nu='Nutshocker:BAEANQAECggICQAAAA==.',
Pa='Pafupafu:BAEANQAECgYIBwABNQAECgkJJQAGAKEiAA==.',
Pe='Peterpikachu:BAEANQAECgMIAwABNQAECgkJGAAQAD0SAA==.',
Pr='Prophethic:BAEANQAECgYIBwABNQAECggIGgAIAKYPAA==.',
Ra='Randomno:BAECNQAFFH8aAAQJAAgKZwIqBwC4AAiODQAABQAPAHUNAAAEAAQAfw0AAAQAAgCpDQAABAAJAFwNAAACAAMAXQ0AAAEAAABlDQAAAQACADMNAAAFAA0ADgAGCp8CNhMAYgEGjg0AAAMADAB/DQAABAACAKkNAAABAAkAXA0AAAIAAwBdDQAAAQAAADMNAAAFAA0ACQADCjwDKgcAuAADjg0AAAIADwB1DQAABAAEAKkNAAADAAQADwABCh0BKQoATAABZQ0AAAEAAgA1AAQKf1QABAkACgpvEj4JAGYCAAkACQoqDz4JAGYCAA4ACgotEBtAAKkBAA8AAQrwDCscADoAAAAA.',
Ro='Roksta:BAEANQAECgYICAABNQAECggICAAKAAAAAA==.Rounnin:BAEANQADCgIIAgABNQAFFAQIBgABAFgHAA==.',
Sh='Sherkia:BAEANQADCgQIBgABNQAECgUIBwAKAAAAAA==.Sherko:BAEANQAECgUIBwAAAA==.Sherkocalyps:BAEANQAECgEIAQABNQAECgUIBwAKAAAAAA==.Shruggo:BAEBNQAECn8bAAMRAAkKbBcvCQAtAgmODQAABABQAHUNAAAEAE4Afw0AAAQAQQCpDQAAAwBOAFwNAAADAEQAXQ0AAAMAJwBlDQAAAgBBADMNAAACACAAuQ0AAAIAHgARAAkKbBcvCQAtAgmODQAABABQAHUNAAAEAE4Afw0AAAQAQQCpDQAAAwBOAFwNAAADAEQAXQ0AAAMAJwBlDQAAAgBBADMNAAABACAAuQ0AAAIAHgASAAEKAACmVgAAAAEzDQAAAQAPAAE1AAQKCgo0AAIAbSQA.',
Sk='Skorpbear:BAEBNQAECn8uAAQTAAoKlBJYGQDfAQqODQAACgBSAHUNAAAIAFgAfw0AAAYARgCpDQAABgAzAFwNAAACABAAXQ0AAAEABABlDQAABgA6AKQNAAABABoAMw0AAAQASQC5DQAAAgAzABMABgqNGlgZAN8BBo4NAAABAFIAdQ0AAAEAWAB/DQAAAQBGAKkNAAABACoAZQ0AAAEAOgAzDQAAAwBJABQACgpjDr0iAG4BCo4NAAAHADMAdQ0AAAUAOgB/DQAAAwBEAKkNAAADADMAXA0AAAIAEABdDQAAAQAEAGUNAAAFACEApA0AAAEAGgAzDQAAAQA6ALkNAAACADMACwAECjwMIisAuAAEjg0AAAIAFQB1DQAAAgAjAH8NAAACAA4AqQ0AAAIAJQAAAA==.Skorpionjr:BAEBNQAECn8rAAMDAAoKuRcPcwBIAgqODQAACQA8AHUNAAAHAEIAfw0AAAcAPwCpDQAABQA4AFwNAAACAEYAXQ0AAAEAMgBlDQAABQA1AKQNAAADADwAMw0AAAIANQC5DQAAAgBCAAMACgq5Fw9zAEgCCo4NAAAIADwAdQ0AAAYAQgB/DQAABwA/AKkNAAAFADgAXA0AAAIARgBdDQAAAQAyAGUNAAAFADUApA0AAAMAPAAzDQAAAgA1ALkNAAACAEIAFQACCq8LUk0ALwACjg0AAAEAFAB1DQAAAQAnAAE1AAQKCgouABMAlBIA.Skorprunes:BAEANQAECgUIEgABNQAECgoKLgATAJQSAA==.',
Sp='Sparkmac:BAEBNQAECn8YAAMQAAgKtA1ThwB4AQiODQAABAA3AHUNAAAEACoAfw0AAAQAMACpDQAABABRAFwNAAADAA0AXQ0AAAIAEABlDQAAAQAIADMNAAACAA0AEAAHCrgOU4cAeAEHjg0AAAIANwB1DQAAAQAqAH8NAAABADAAqQ0AAAIAUQBcDQAAAQANAGUNAAABAAgAMw0AAAEADQAWAAcKLhSKQABSAQeODQAAAgAwAHUNAAADAEQAfw0AAAMALgCpDQAAAgA8AFwNAAACADYAXQ0AAAIAGwAzDQAAAQApAAE1AAUUCAgZAA4AKxUA.',
Ta='Tafftidermy:BAEANQAECgYIEQABNQAECgoKKgAGAI4XAA==.',
Wa='Wafuwafu:BAEANQAECgYICAABNQAECgkJJQAGAKEiAA==.Waterheart:BAEBNQAECn8YAAMQAAkKPRK7dgCnAQmODQAAAgAtAHUNAAACAEIAfw0AAAIAKgCpDQAAAgAiAFwNAAAEABsAXQ0AAAYAQABlDQAAAgAgAKQNAAADACgAuQ0AAAEAQgAQAAkKPRK7dgCnAQmODQAAAgAtAHUNAAACAEIAfw0AAAIAKgCpDQAAAQAiAFwNAAADABsAXQ0AAAYAQABlDQAAAgAgAKQNAAACACgAuQ0AAAEAQgAWAAMKrhMsdAC4AAOpDQAAAQBGAFwNAAABAC0ApA0AAAEAIgAAAA==.',
Wi='Wijon:BAEBNQAECn83AAISAAoKtBuMCwAdAwqODQAABgBVAHUNAAAHAFAAfw0AAAkAXACpDQAABwBaAFwNAAAGAEwAXQ0AAAMASwBlDQAABgBQAKQNAAAGAEkAMw0AAAQAXwC5DQAAAQAEABIACgq0G4wLAB0DCo4NAAAGAFUAdQ0AAAcAUAB/DQAACQBcAKkNAAAHAFoAXA0AAAYATABdDQAAAwBLAGUNAAAGAFAApA0AAAYASQAzDQAABABfALkNAAABAAQAAAA=.',
Xu='Xugi:BAEBNQAECn8fAAIOAAgK+hhbKQANAgiODQAABQBCAHUNAAAFAFAAfw0AAAUAXACpDQAABQBDAFwNAAAFAD0AXQ0AAAQARwBlDQAAAQA6AKQNAAABACkADgAICvoYWykADQIIjg0AAAUAQgB1DQAABQBQAH8NAAAFAFwAqQ0AAAUAQwBcDQAABQA9AF0NAAAEAEcAZQ0AAAEAOgCkDQAAAQApAAE1AAQKCgo0AAIAbSQA.',
Xx='Xxlanaconda:BAEANQAECggIEQABNQAFFAUIFQALAHokAA==.',
Zy='Zygote:BAEBNQAECn8lAAIGAAkKoSJMCQALAwmODQAABgBgAHUNAAAGAFsAfw0AAAQAVQCpDQAABABcAFwNAAADAF0AXQ0AAAQAYgBlDQAABQBVAKQNAAAEAGEAuQ0AAAEANQAGAAkKoSJMCQALAwmODQAABgBgAHUNAAAGAFsAfw0AAAQAVQCpDQAABABcAFwNAAADAF0AXQ0AAAQAYgBlDQAABQBVAKQNAAAEAGEAuQ0AAAEANQAAAA==.',
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
