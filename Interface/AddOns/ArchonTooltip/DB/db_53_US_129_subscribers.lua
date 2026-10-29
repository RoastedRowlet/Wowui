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
local provider = {region='US',realm="Kel'Thuzad",name='US',type='subscribers',zone=53,date='2026-10-27',data={Ag='Agisa:BAEANQAECgYICwABNQAFFAIIAgABAAAAAA==.',
Ar='Arlicdk:BAEANQAECgEIAQABNQAFFAcIDgACAPMZAA==.Arlicmad:BAECNQAFFH8OAAICAAcK8xnPBgBVAgeODQAABAA1AHUNAAABACQAfw0AAAEAQACpDQAAAwBUAFwNAAACAEkAXQ0AAAEAVAAzDQAAAgAOAAIABwrzGc8GAFUCB44NAAAEADUAdQ0AAAEAJAB/DQAAAQBAAKkNAAADAFQAXA0AAAIASQBdDQAAAQBUADMNAAACAA4ANQAECn82AAICAAoKjSOKEQDZAgACAAoKjSOKEQDZAgAAAA==.Arliczap:BAEBNQAECn8ZAAIDAAoKkhWBVgAgAgqODQAABgBTAHUNAAACAEQAfw0AAAIAPwCpDQAAAwBCAFwNAAACACUAXQ0AAAEADQBlDQAABABSAKQNAAADAEEAMw0AAAEADgC5DQAAAQAWAAMACgqSFYFWACACCo4NAAAGAFMAdQ0AAAIARAB/DQAAAgA/AKkNAAADAEIAXA0AAAIAJQBdDQAAAQANAGUNAAAEAFIApA0AAAMAQQAzDQAAAQAOALkNAAABABYAATUABRQHCA4AAgDzGQA=.Armisbloo:BAECNQAFFH8aAAICAAgKDh44BgBhAgiODQAABABcAHUNAAADAE8Afw0AAAMAKwCpDQAABABSAFwNAAACAEoAXQ0AAAEAPABlDQAAAQBJADMNAAAIAEcAAgAICg4eOAYAYQIIjg0AAAQAXAB1DQAAAwBPAH8NAAADACsAqQ0AAAQAUgBcDQAAAgBKAF0NAAABADwAZQ0AAAEASQAzDQAACABHADUABAp/MgACAgAKCoYlhxQAaQMAAgAKCoYlhxQAaQMAAAA=.',
Ch='Cheekymunky:BAEANQAECgcIDgABNQAFFAQIDgAEALELAA==.',
Co='Conuretotem:BAECNQAFFH8dAAIDAAcKCCbgAAAzAgeODQAABwBjAHUNAAAFAGMAfw0AAAQAYwCpDQAABwBjAFwNAAABAFgAXQ0AAAEAYwAzDQAABABkAAMABwoIJuAAADMCB44NAAAHAGMAdQ0AAAUAYwB/DQAABABjAKkNAAAHAGMAXA0AAAEAWABdDQAAAQBjADMNAAAEAGQANQAECn8wAAIDAAoKAicaAACcAwADAAoKAicaAACcAwAAAA==.',
Dl='Dlwlrma:BAEBNQAECn9qAAIFAAoKqiYzAAAPBAqODQAACwBjAHUNAAANAGMAfw0AAA8AYwCpDQAADQBjAFwNAAAMAGQAXQ0AAAoAYwBlDQAADABjAKQNAAAJAGMAMw0AAAkAYgC5DQAAAgBeAAUACgqqJjMAAA8ECo4NAAALAGMAdQ0AAA0AYwB/DQAADwBjAKkNAAANAGMAXA0AAAwAZABdDQAACgBjAGUNAAAMAGMApA0AAAkAYwAzDQAACQBiALkNAAACAF4AAAA=.',
Er='Ermeila:BAEANQAECgIIAwABNQAFFAcIHQADAAgmAA==.',
Ex='Extends:BAEBNQAECn8mAAIGAAoK3yH+CQA/AwqODQAABgBOAHUNAAAGAF8Afw0AAAYAYgCpDQAABQBhAFwNAAAEAFkAXQ0AAAMAWwBlDQAAAwBUAKQNAAADADwAMw0AAAEAYAC5DQAAAQBKAAYACgrfIf4JAD8DCo4NAAAGAE4AdQ0AAAYAXwB/DQAABgBiAKkNAAAFAGEAXA0AAAQAWQBdDQAAAwBbAGUNAAADAFQApA0AAAMAPAAzDQAAAQBgALkNAAABAEoAAAA=.',
Fa='Faada:BAEANQAECggIDgABNQAECgoKOgAHALMUAA==.Faadi:BAEBNQAECn86AAQHAAoKsxTzIAAiAgqODQAACgA/AHUNAAAGADAAfw0AAAYATQCpDQAABAAoAFwNAAAFADgAXQ0AAAUAIgBlDQAACgBRAKQNAAAHADYAMw0AAAQALwC5DQAAAQAZAAcACgqzFPMgACICCo4NAAAKAD8AdQ0AAAUAMAB/DQAABQBNAKkNAAADACgAXA0AAAUAOABdDQAABQAiAGUNAAAKAFEApA0AAAcANgAzDQAABAAvALkNAAABABkABQACCqgQRZcAewACfw0AAAEAPQCpDQAAAQAqAAgAAQr9Hk5FAFIAAXUNAAABAE8AAAA=.Faadiest:BAEANQAECgYICQABNQAECgoKOgAHALMUAA==.Faadious:BAEANQAECgEIAQABNQAECgoKOgAHALMUAA==.Faadistrasz:BAEANQAECgYIDwABNQAECgoKOgAHALMUAA==.Faadithustra:BAEBNQAECn8aAAIJAAkKuxHtdgCnAQmODQAABQBDAHUNAAADACYAfw0AAAQAQQCpDQAAAwA1AF0NAAABAB0AZQ0AAAUAUACkDQAAAwAsADMNAAABABQAuQ0AAAEABwAJAAkKuxHtdgCnAQmODQAABQBDAHUNAAADACYAfw0AAAQAQQCpDQAAAwA1AF0NAAABAB0AZQ0AAAUAUACkDQAAAwAsADMNAAABABQAuQ0AAAEABwABNQAECgoKOgAHALMUAA==.Faád:BAEBNQAECn8cAAQKAAgKdRCufgD5AAiODQAABQAdAHUNAAAFADkAfw0AAAUAOwCpDQAABgA1AFwNAAACAC4AXQ0AAAIAKwBlDQAAAgAVADMNAAABAB4ACgAGCkoPrn4A+QAGjg0AAAUAHQB/DQAABQA7AKkNAAAFADUAXA0AAAIALgBdDQAAAgArAGUNAAABABUACwACCrcOS2QAWwACdQ0AAAUAOQCpDQAAAQASAAwAAgrQB7scADcAAmUNAAABABMAMw0AAAEAHgABNQAECgoKOgAHALMUAA==.',
Fo='Fofer:BAEANQAECggIDwABNQAFFAYIEgANAPMZAA==.',
Ge='Gearsz:BAEANQAECgEIAwAAAA==.',
Gg='Ggwpnoree:BAECNQAFFH8bAAIOAAcKdhx8AQCjAgeODQAABABSAHUNAAAFAFwAfw0AAAUAYwCpDQAABgBZAFwNAAADAF8AXQ0AAAEABAAzDQAAAwBNAA4ABwp2HHwBAKMCB44NAAAEAFIAdQ0AAAUAXAB/DQAABQBjAKkNAAAGAFkAXA0AAAMAXwBdDQAAAQAEADMNAAADAE0ANQAECn9EAAIOAAoKJyYMAQBPAwAOAAoKJyYMAQBPAwAAAA==.',
['Gú']='Gúr:BAEBNQAECn8iAAIPAAgKNxrOfQCDAgiODQAABgA5AHUNAAAFAE8Afw0AAAUAVgCpDQAABQAwAFwNAAADADsAXQ0AAAMAUABlDQAAAQBMADMNAAAGAEEADwAICjcazn0AgwIIjg0AAAYAOQB1DQAABQBPAH8NAAAFAFYAqQ0AAAUAMABcDQAAAwA7AF0NAAADAFAAZQ0AAAEATAAzDQAABgBBAAAA.',
He='Heeka:BAECNQAFFH8ZAAIQAAcKeh/PAQDGAQeODQAABgBfAHUNAAAEAFEAfw0AAAIAOwCpDQAABQBcAFwNAAACAD0AXQ0AAAEARwAzDQAABQBdABAABwp6H88BAMYBB44NAAAGAF8AdQ0AAAQAUQB/DQAAAgA7AKkNAAAFAFwAXA0AAAIAPQBdDQAAAQBHADMNAAAFAF0ANQAECn87AAMQAAoKByVjAwAQAwAQAAoKByVjAwAQAwAGAAgKfArySwCBAQAAAA==.Hemon:BAEANQAECgUICgABNQAFFAIIAgABAAAAAA==.',
Ji='Jirtz:BAEANQAECgEIAQABNQAFFAIIAgABAAAAAA==.',
Jo='Jonnyclaude:BAEANQAECgYIDgAAAA==.',
Lu='Lucere:BAEANQADCggICAABNQAFFAcIFwANABYdAA==.',
Ma='Maxdeeps:BAEANQAECgEIBgABNQAFFAQIDgAEALELAA==.Maxdeepz:BAEANQAECgIIAgABNQAFFAQIDgAEALELAA==.',
Ni='Nihillus:BAEBNQAECn80AAQKAAoKtBE1OgDAAQqODQAACAAxAHUNAAAHAEAAfw0AAAgAQwCpDQAACAA4AFwNAAAEADMAXQ0AAAIAHgBlDQAABAApAKQNAAAEABgAMw0AAAYAQwC5DQAAAQAtAAoACgqRETU6AMABCo4NAAAGADEAdQ0AAAMAQAB/DQAABQBDAKkNAAAFADUAXA0AAAIAMwBdDQAAAgAeAGUNAAAEACkApA0AAAQAGAAzDQAABQBDALkNAAABAC0ADAAGCg0QCg8AXwEGjg0AAAIAIQB1DQAAAgAnAH8NAAACAC4AqQ0AAAIAOABcDQAAAgAjADMNAAABACgACwADCo8Nb0YArQADdQ0AAAIAMgB/DQAAAQA+AKkNAAABABMAAAA=.',
Pe='Peavers:BAEANQAECggIDgABNQAECgoKJgAGAN8hAA==.',
Ru='Rukelock:BAEBNQAECn8ZAAIKAAkKcxmcIAA6AgmODQAABAA+AHUNAAADAEsAfw0AAAMAPACpDQAAAwBMAFwNAAACAE0AXQ0AAAIARgBlDQAAAwAsAKQNAAADACoAuQ0AAAIASAAKAAkKcxmcIAA6AgmODQAABAA+AHUNAAADAEsAfw0AAAMAPACpDQAAAwBMAFwNAAACAE0AXQ0AAAIARgBlDQAAAwAsAKQNAAADACoAuQ0AAAIASAABNQAECgkJJQAPANYeAA==.Rukemage:BAEBNQAECn8lAAIPAAkK1h4vWADQAgmODQAABABcAHUNAAAFAFYAfw0AAAUAUgCpDQAABQBLAFwNAAAEAE8AXQ0AAAQAWwBlDQAAAwBGAKQNAAABADgAMw0AAAYAVQAPAAkK1h4vWADQAgmODQAABABcAHUNAAAFAFYAfw0AAAUAUgCpDQAABQBLAFwNAAAEAE8AXQ0AAAQAWwBlDQAAAwBGAKQNAAABADgAMw0AAAYAVQAAAA==.',
Ry='Ryaris:BAEBNQAECn8aAAIIAAkK7iFjBgCOAgmODQAABQBUAHUNAAAEAF4Afw0AAAQAXQCpDQAABABbAFwNAAACAEwAXQ0AAAIAWABlDQAAAQBWAKQNAAABAFUAMw0AAAMAWQAIAAkK7iFjBgCOAgmODQAABQBUAHUNAAAEAF4Afw0AAAQAXQCpDQAABABbAFwNAAACAEwAXQ0AAAIAWABlDQAAAQBWAKQNAAABAFUAMw0AAAMAWQABNQAFFAcIFwANABYdAA==.Ryathe:BAECNQAFFH8XAAINAAcKFh3jBAAtAgeODQAABABZAHUNAAAEADsAfw0AAAQAYACpDQAABQBQAFwNAAABAEgAXQ0AAAEARQAzDQAABABNAA0ABwoWHeMEAC0CB44NAAAEAFkAdQ0AAAQAOwB/DQAABABgAKkNAAAFAFAAXA0AAAEASABdDQAAAQBFADMNAAAEAE0ANQAECn8sAAINAAoKESWqCgBfAwANAAoKESWqCgBfAwAAAA==.',
Sh='Shikdk:BAECNQAFFH8UAAINAAcKShFTBQBSAQeODQAABQAwAHUNAAAEACoAfw0AAAMAMwCpDQAABQAzAFwNAAABACsAXQ0AAAEAIwAzDQAAAQAqAA0ABwpKEVMFAFIBB44NAAAFADAAdQ0AAAQAKgB/DQAAAwAzAKkNAAAFADMAXA0AAAEAKwBdDQAAAQAjADMNAAABACoANQAECn8qAAINAAkKsBx0HgC+AgANAAkKsBx0HgC+AgAAAA==.Shikdruid:BAEANQAECggIEgABNQAFFAcIFAANAEoRAA==.Shikpally:BAEANQAECgUICQABNQAFFAcIFAANAEoRAA==.',
Si='Sickhouse:BAEBNQAECn8jAAMRAAoKAR2KBAB/AgqODQAABAA0AHUNAAAEAE0Afw0AAAQASgCpDQAABABBAFwNAAACAEQAXQ0AAAIATwBlDQAABABYAKQNAAACAGAAMw0AAAcAWwC5DQAAAgAwABEACAriGooEAH8CCI4NAAABADQAdQ0AAAIATQB/DQAAAgBKAKkNAAABAEEAXA0AAAIARABdDQAAAgBPAGUNAAABAC0AMw0AAAUAVwAGAAgKcResgQCSAQiODQAAAwAYAHUNAAACABoAfw0AAAIAKwCpDQAAAwA8AGUNAAADAFgApA0AAAIAYAAzDQAAAgBbALkNAAACADAAAAA=.',
Ss='Ssixx:BAEANQADCgYIBgABNQAECgoKLQACAEocAA==.',
To='Tonymá:BAEANQAECgEIAQABNQAECgoKLQAPAF0VAA==.',
Tr='Trumpetdh:BAEBNQAECn8tAAISAAoKSCD9CwAgAwqODQAACQBZAHUNAAAHAFUAfw0AAAUAYACpDQAABQBRAFwNAAADAE4AXQ0AAAMAVABlDQAABgBRAKQNAAADAFYAMw0AAAIAIAC5DQAAAgBIABIACgpIIP0LACADCo4NAAAJAFkAdQ0AAAcAVQB/DQAABQBgAKkNAAAFAFEAXA0AAAMATgBdDQAAAwBUAGUNAAAGAFEApA0AAAMAVgAzDQAAAgAgALkNAAACAEgAAAA=.Trumpetman:BAEANQADCgYICAABNQAECgoKLQASAEggAA==.',
Va='Variable:BAECNQAFFH8JAAIPAAQKTxa7JQBaAQSODQAABABQAHUNAAABABUAfw0AAAEAPgCpDQAAAwBFAA8ABApPFrslAFoBBI4NAAAEAFAAdQ0AAAEAFQB/DQAAAQA+AKkNAAADAEUANQAECn8uAAIPAAoK1h/hJABLAwAPAAoK1h/hJABLAwAAAA==.',
Vr='Vrisard:BAEBNQAECn9GAAITAAoKfSNhAQD4AgqODQAACABdAHUNAAAKAGEAfw0AAAoAYQCpDQAACABeAFwNAAAHAFQAXQ0AAAUAYABlDQAABQBVAKQNAAAGAFgAMw0AAAgAXwC5DQAAAwBVABMACgp9I2EBAPgCCo4NAAAIAF0AdQ0AAAoAYQB/DQAACgBhAKkNAAAIAF4AXA0AAAcAVABdDQAABQBgAGUNAAAFAFUApA0AAAYAWAAzDQAACABfALkNAAADAFUAAAA=.',
Wa='Waluigi:BAEANQAECgYIEAABNQAFFAgIFgAUAOIKAA==.',
Xa='Xanteer:BAEANQAFFAEIAQABNQAFFAgIFgAVAEIbAA==.Xantier:BAECNQAFFH8WAAIVAAgKQhvBAQA+AgiODQAABABPAHUNAAADAFUAfw0AAAIASgCpDQAABABRAFwNAAACAEAAXQ0AAAEASABlDQAAAQAiADMNAAAFAFMAFQAICkIbwQEAPgIIjg0AAAQATwB1DQAAAwBVAH8NAAACAEoAqQ0AAAQAUQBcDQAAAgBAAF0NAAABAEgAZQ0AAAEAIgAzDQAABQBTADUABAp/JgACFQAKCg8jiwcAKQMAFQAKCg8jiwcAKQMAAAA=.',
Za='Zaffz:BAEANQAECgQICQABNQAFFAIIAgABAAAAAA==.',
['Zè']='Zèro:BAEANQADCggICAABNQAECgQIBQABAAAAAA==.Zèrô:BAEANQADCgMIAwABNQAECgQIBQABAAAAAA==.',
['Zé']='Zérò:BAEANQAECgQIBQAAAA==.',
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
