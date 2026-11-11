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

local lookup = {'Unknown-Unknown','Warrior-Arms','Shaman-Elemental','Hunter-Marksmanship','Druid-Balance','Priest-Holy','Druid-Restoration','Druid-Guardian','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Protection','Rogue-Assassination','Mage-Arcane','Priest-Shadow','DeathKnight-Blood','DeathKnight-Unholy','Priest-Discipline','DemonHunter-Devourer','Mage-Frost','Evoker-Devastation','Evoker-Preservation',}
local provider = {region='US',realm="Kel'Thuzad",name='US',type='subscribers',zone=53,date='2026-11-10',data={Ag='Agisa:BAEANQAECgYICgABNQAFFAIIAgABAAAAAA==.',
Ar='Arlic:BAEANQAECgMIAwABNQAFFAcIDgACAPMZAA==.Arlicdk:BAEANQADCgYIBgABNQAFFAcIDgACAPMZAA==.Arlicmad:BAECNQAFFH8OAAICAAcK8xnPBgBVAgeODQAABAA1AHUNAAABACQAfw0AAAEAQACpDQAAAwBUAFwNAAACAEkAXQ0AAAEAVAAzDQAAAgAOAAIABwrzGc8GAFUCB44NAAAEADUAdQ0AAAEAJAB/DQAAAQBAAKkNAAADAFQAXA0AAAIASQBdDQAAAQBUADMNAAACAA4ANQAECn84AAICAAoKHiWrGADgAgACAAoKHiWrGADgAgAAAA==.Arlicstab:BAEANQAECggIDQABNQAFFAcIDgACAPMZAA==.Arliczap:BAEBNQAECn8ZAAIDAAoKkhWBVgAgAgqODQAABgBTAHUNAAACAEQAfw0AAAIAPwCpDQAAAwBCAFwNAAACACUAXQ0AAAEADQBlDQAABABSAKQNAAADAEEAMw0AAAEADgC5DQAAAQAWAAMACgqSFYFWACACCo4NAAAGAFMAdQ0AAAIARAB/DQAAAgA/AKkNAAADAEIAXA0AAAIAJQBdDQAAAQANAGUNAAAEAFIApA0AAAMAQQAzDQAAAQAOALkNAAABABYAATUABRQHCA4AAgDzGQA=.Armisbloo:BAECNQAFFH8aAAICAAgKDh44BgBhAgiODQAABABcAHUNAAADAE8Afw0AAAMAKwCpDQAABABSAFwNAAACAEoAXQ0AAAEAPABlDQAAAQBJADMNAAAIAEcAAgAICg4eOAYAYQIIjg0AAAQAXAB1DQAAAwBPAH8NAAADACsAqQ0AAAQAUgBcDQAAAgBKAF0NAAABADwAZQ0AAAEASQAzDQAACABHADUABAp/NAACAgAKCoYlhxQAaQMAAgAKCoYlhxQAaQMAAAA=.Armisgreen:BAEANQADCgYIBgABNQAFFAgIGgACAA4eAA==.',
Ch='Cheekymunky:BAEANQAECgcICgABNQAFFAQIEgAEAL0QAA==.',
Co='Conuremage:BAEANQAFFAEIAQABNQAFFAcIHQADAAgmAA==.Conuretotem:BAECNQAFFH8dAAIDAAcKCCZJAgAkAgeODQAABwBjAHUNAAAFAGMAfw0AAAQAYwCpDQAABwBjAFwNAAABAFgAXQ0AAAEAYwAzDQAABABkAAMABwoIJkkCACQCB44NAAAHAGMAdQ0AAAUAYwB/DQAABABjAKkNAAAHAGMAXA0AAAEAWABdDQAAAQBjADMNAAAEAGQANQAECn8xAAIDAAoKAydXAAAMBAADAAoKAydXAAAMBAAAAA==.',
Dl='Dlwlrma:BAEBNQAECn99AAIFAAoKtiYzAAAPBAqODQAADQBjAHUNAAAPAGMAfw0AABEAYwCpDQAADwBjAFwNAAAOAGQAXQ0AAAwAYwBlDQAADgBjAKQNAAALAGMAMw0AAAkAYgC5DQAABQBfAAUACgq2JjMAAA8ECo4NAAANAGMAdQ0AAA8AYwB/DQAAEQBjAKkNAAAPAGMAXA0AAA4AZABdDQAADABjAGUNAAAOAGMApA0AAAsAYwAzDQAACQBiALkNAAAFAF8AAAA=.',
Er='Ermeila:BAEANQAECggIDgABNQAFFAcIHQADAAgmAA==.',
Ex='Extends:BAEBNQAECn8qAAIGAAoK3yGsEABCAwqODQAACABOAHUNAAAGAF8Afw0AAAYAYgCpDQAABgBhAFwNAAAFAFkAXQ0AAAMAWwBlDQAAAwBUAKQNAAADADwAMw0AAAEAYAC5DQAAAQBKAAYACgrfIawQAEIDCo4NAAAIAE4AdQ0AAAYAXwB/DQAABgBiAKkNAAAGAGEAXA0AAAUAWQBdDQAAAwBbAGUNAAADAFQApA0AAAMAPAAzDQAAAQBgALkNAAABAEoAAAA=.',
Fa='Faada:BAEANQAECggIEAABNQAFFAQICQAHAEMLAA==.Faadi:BAECNQAFFH8JAAMHAAQKQwsbDQC5AASODQAABAA5AHUNAAABAAcAqQ0AAAEAIwAzDQAAAwAOAAcABApDCxsNALkABI4NAAAEADkAdQ0AAAEABwCpDQAAAQAjADMNAAABAA4ABQABCgAAficAAAABMw0AAAIADgA1AAQKf0MABAcACgriFPMgACICAAcACgriFPMgACICAAUABAqzDUWXAHsAAAgAAQr9Hs9cAE4AAAAA.Faadiest:BAEANQAECgYICQABNQAFFAQICQAHAEMLAA==.Faadious:BAEANQAECggICwABNQAFFAQICQAHAEMLAA==.Faadistrasz:BAEANQAECgYIDgABNQAFFAQICQAHAEMLAA==.Faadithustra:BAEBNQAECn8cAAIJAAkKchTtdgCnAQmODQAABgBDAHUNAAADACYAfw0AAAQAQQCpDQAAAwA1AF0NAAABAB0AZQ0AAAUAUACkDQAAAwAsADMNAAABABQAuQ0AAAIARgAJAAkKchTtdgCnAQmODQAABgBDAHUNAAADACYAfw0AAAQAQQCpDQAAAwA1AF0NAAABAB0AZQ0AAAUAUACkDQAAAwAsADMNAAABABQAuQ0AAAIARgABNQAFFAQICQAHAEMLAA==.Faád:BAEBNQAECn8cAAQKAAgKdRCVpgD0AAiODQAABQAdAHUNAAAFADkAfw0AAAUAOwCpDQAABgA1AFwNAAACAC4AXQ0AAAIAKwBlDQAAAgAVADMNAAABAB4ACgAGCkoPlaYA9AAGjg0AAAUAHQB/DQAABQA7AKkNAAAFADUAXA0AAAIALgBdDQAAAgArAGUNAAABABUACwACCrcOS2QAWwACdQ0AAAUAOQCpDQAAAQASAAwAAgrQB0owADUAAmUNAAABABMAMw0AAAEAHgABNQAFFAQICQAHAEMLAA==.',
Fo='Fofer:BAEANQAECggIEAABNQAFFAYIBgANAFcjAA==.',
Ge='Gearsz:BAEANQAECgEIAQAAAA==.',
Gg='Ggwpnoree:BAECNQAFFH8dAAIOAAgKxxx8AQCjAgiODQAABABSAHUNAAAFAFwAfw0AAAUAYwCpDQAABgBZAFwNAAADAF8AXQ0AAAEABABlDQAAAQBNADMNAAAEAFUADgAICsccfAEAowIIjg0AAAQAUgB1DQAABQBcAH8NAAAFAGMAqQ0AAAYAWQBcDQAAAwBfAF0NAAABAAQAZQ0AAAEATQAzDQAABABVADUABAp/VwACDgAKCicm7AEAxAMADgAKCicm7AEAxAMAAAA=.',
['Gú']='Gúr:BAEBNQAECn8oAAIPAAkK7hrOfQCDAgmODQAACAA5AHUNAAAFAE8Afw0AAAUAVgCpDQAABQAwAFwNAAADADsAXQ0AAAMAUABlDQAAAwBNAKQNAAACAE4AMw0AAAYAQQAPAAkK7hrOfQCDAgmODQAACAA5AHUNAAAFAE8Afw0AAAUAVgCpDQAABQAwAFwNAAADADsAXQ0AAAMAUABlDQAAAwBNAKQNAAACAE4AMw0AAAYAQQAAAA==.',
He='Heeka:BAECNQAFFH8eAAIQAAcKeh9HAwC9AQeODQAABwBfAHUNAAAFAFEAfw0AAAMAOwCpDQAABgBcAFwNAAACAD0AXQ0AAAIARwAzDQAABQBdABAABwp6H0cDAL0BB44NAAAHAF8AdQ0AAAUAUQB/DQAAAwA7AKkNAAAGAFwAXA0AAAIAPQBdDQAAAgBHADMNAAAFAF0ANQAECn9AAAMQAAoKCiXnBAAiAwAQAAoKCiXnBAAiAwAGAAgKfAomcABzAQAAAA==.Hemon:BAEANQAECgUICQABNQAFFAIIAgABAAAAAA==.',
Ji='Jirtz:BAEANQAECgEIAQABNQAFFAIIAgABAAAAAA==.',
Lu='Lucere:BAEANQADCggICAABNQAFFAcIFwARABYdAA==.',
Ma='Maxdeeps:BAEANQAECgEIAQABNQAFFAQIEgAEAL0QAA==.Maxdeepz:BAEANQAECggIDAABNQAFFAQIEgAEAL0QAA==.',
Ni='Nihillus:BAEBNQAECn86AAQKAAoKuRHzSgDhAQqODQAACQAxAHUNAAAIAEAAfw0AAAkAQwCpDQAACQA4AFwNAAAEADMAXQ0AAAIAHgBlDQAABAApAKQNAAAEABgAMw0AAAcAQwC5DQAAAgAtAAoACgqVEfNKAOEBCo4NAAAHADEAdQ0AAAMAQAB/DQAABgBDAKkNAAAGADUAXA0AAAIAMwBdDQAAAgAeAGUNAAAEACkApA0AAAQAGAAzDQAABgBDALkNAAACAC0ADAAGCg0QCg8AXwEGjg0AAAIAIQB1DQAAAwAnAH8NAAACAC4AqQ0AAAIAOABcDQAAAgAjADMNAAABACgACwADCo8Nb0YArQADdQ0AAAIAMgB/DQAAAQA+AKkNAAABABMAAAA=.',
Pe='Peavers:BAEANQAECggIDgABNQAECgoKKgAGAN8hAA==.',
Ru='Ruke:BAEANQAECgYIBgABNQAECgkJJQAPANYeAA==.Rukelock:BAEBNQAECn8dAAIKAAkK1xkbOAAgAgmODQAABAA+AHUNAAADAEsAfw0AAAMAPACpDQAAAwBMAFwNAAACAE0AXQ0AAAIARgBlDQAABAAwAKQNAAAEAC4AuQ0AAAQASAAKAAkK1xkbOAAgAgmODQAABAA+AHUNAAADAEsAfw0AAAMAPACpDQAAAwBMAFwNAAACAE0AXQ0AAAIARgBlDQAABAAwAKQNAAAEAC4AuQ0AAAQASAABNQAECgkJJQAPANYeAA==.Rukemage:BAEBNQAECn8lAAIPAAkK1h4vWADQAgmODQAABABcAHUNAAAFAFYAfw0AAAUAUgCpDQAABQBLAFwNAAAEAE8AXQ0AAAQAWwBlDQAAAwBGAKQNAAABADgAMw0AAAYAVQAPAAkK1h4vWADQAgmODQAABABcAHUNAAAFAFYAfw0AAAUAUgCpDQAABQBLAFwNAAAEAE8AXQ0AAAQAWwBlDQAAAwBGAKQNAAABADgAMw0AAAYAVQAAAA==.',
Ry='Ryaris:BAEBNQAECn8jAAIIAAkKcCNJBwDJAgmODQAABgBUAHUNAAAFAF4Afw0AAAUAXQCpDQAABQBbAFwNAAADAFcAXQ0AAAMAWgBlDQAAAgBdAKQNAAACAF0AMw0AAAQAWwAIAAkKcCNJBwDJAgmODQAABgBUAHUNAAAFAF4Afw0AAAUAXQCpDQAABQBbAFwNAAADAFcAXQ0AAAMAWgBlDQAAAgBdAKQNAAACAF0AMw0AAAQAWwABNQAFFAcIFwARABYdAA==.Ryathe:BAECNQAFFH8XAAIRAAcKFh3jBAAtAgeODQAABABZAHUNAAAEADsAfw0AAAQAYACpDQAABQBQAFwNAAABAEgAXQ0AAAEARQAzDQAABABNABEABwoWHeMEAC0CB44NAAAEAFkAdQ0AAAQAOwB/DQAABABgAKkNAAAFAFAAXA0AAAEASABdDQAAAQBFADMNAAAEAE0ANQAECn8uAAIRAAoKJSWqCgBfAwARAAoKJSWqCgBfAwAAAA==.',
Sh='Shikdk:BAECNQAFFH8UAAIRAAcKShHPCgBAAQeODQAABQAwAHUNAAAEACoAfw0AAAMAMwCpDQAABQAzAFwNAAABACsAXQ0AAAEAIwAzDQAAAQAqABEABwpKEc8KAEABB44NAAAFADAAdQ0AAAQAKgB/DQAAAwAzAKkNAAAFADMAXA0AAAEAKwBdDQAAAQAjADMNAAABACoANQAECn8sAAMRAAoK2xx0HgC+AgARAAoK2xx0HgC+AgASAAEKlgd9hQAyAAAAAA==.Shikdruid:BAEBNQAECn8ZAAMIAAoKSx9+CACtAgqODQAABQBdAHUNAAABAEcAfw0AAAEAVACpDQAAAQBFAFwNAAABAFAAXQ0AAAEATwBlDQAABgBbAKQNAAAFAFMAMw0AAAEAXQC5DQAAAwBGAAgACgpLH34IAK0CCo4NAAADAF0AdQ0AAAEARwB/DQAAAQBUAKkNAAABAEUAXA0AAAEAUABdDQAAAQBPAGUNAAADAFsApA0AAAIAUwAzDQAAAQBdALkNAAACAEYABwAECr8L2FQAjwAEjg0AAAIAFABlDQAAAwAvAKQNAAADACAAuQ0AAAEAEwABNQAFFAcIFAARAEoRAA==.Shikpally:BAEANQAECgUICQABNQAFFAcIFAARAEoRAA==.',
Si='Sickhouse:BAEBNQAECn8mAAMTAAoKlh6KBAB/AgqODQAABQBcAHUNAAAEAE0Afw0AAAQASgCpDQAABABBAFwNAAACAEQAXQ0AAAIATwBlDQAABQBYAKQNAAADAGAAMw0AAAcAWwC5DQAAAgAwABMACAoOHooEAH8CCI4NAAACAFwAdQ0AAAIATQB/DQAAAgBKAKkNAAABAEEAXA0AAAIARABdDQAAAgBPAGUNAAACAEYAMw0AAAUAVwAGAAgKcResgQCSAQiODQAAAwAYAHUNAAACABoAfw0AAAIAKwCpDQAAAwA8AGUNAAADAFgApA0AAAMAYAAzDQAAAgBbALkNAAACADAAAAA=.',
Ss='Ssixx:BAEANQADCgYIBgABNQAECgoKNwACAF8fAA==.',
To='Tonymá:BAEANQADCgUJBgABNQAECgoKLQAPAF0VAA==.',
Tr='Trumpetdh:BAEBNQAECn83AAIUAAoKUiD9CwAgAwqODQAACgBaAHUNAAAJAFUAfw0AAAcAYACpDQAABwBRAFwNAAADAE4AXQ0AAAMAVABlDQAABgBRAKQNAAAFAFYAMw0AAAIAIAC5DQAAAwBIABQACgpSIP0LACADCo4NAAAKAFoAdQ0AAAkAVQB/DQAABwBgAKkNAAAHAFEAXA0AAAMATgBdDQAAAwBUAGUNAAAGAFEApA0AAAUAVgAzDQAAAgAgALkNAAADAEgAAAA=.Trumpetman:BAEANQADCgYICAABNQAECgoKNwAUAFIgAA==.',
Va='Variable:BAECNQAFFH8JAAIPAAQKTxa7JQBaAQSODQAABABQAHUNAAABABUAfw0AAAEAPgCpDQAAAwBFAA8ABApPFrslAFoBBI4NAAAEAFAAdQ0AAAEAFQB/DQAAAQA+AKkNAAADAEUANQAECn86AAMPAAoKkSDhJABLAwAPAAoKkSDhJABLAwAVAAEKrRPmNABMAAAAAA==.',
Vr='Vrisard:BAEBNQAECn9QAAIWAAoKpSOMAQAiAwqODQAACQBdAHUNAAALAGEAfw0AAAsAYQCpDQAACQBhAFwNAAAIAFQAXQ0AAAYAYABlDQAABgBVAKQNAAAHAFgAMw0AAAkAXwC5DQAABABVABYACgqlI4wBACIDCo4NAAAJAF0AdQ0AAAsAYQB/DQAACwBhAKkNAAAJAGEAXA0AAAgAVABdDQAABgBgAGUNAAAGAFUApA0AAAcAWAAzDQAACQBfALkNAAAEAFUAAAA=.',
Wa='Waluigi:BAEANQAECgYIEAABNQAFFAkJFwAXAHcKAA==.',
Xa='Xanteer:BAEANQAFFAEIAgABNQAFFAgIFgANAEIbAA==.Xantier:BAECNQAFFH8WAAINAAgKQhvBAQA+AgiODQAABABPAHUNAAADAFUAfw0AAAIASgCpDQAABABRAFwNAAACAEAAXQ0AAAEASABlDQAAAQAiADMNAAAFAFMADQAICkIbwQEAPgIIjg0AAAQATwB1DQAAAwBVAH8NAAACAEoAqQ0AAAQAUQBcDQAAAgBAAF0NAAABAEgAZQ0AAAEAIgAzDQAABQBTADUABAp/JgACDQAKCg8jiwcAKQMADQAKCg8jiwcAKQMAAAA=.',
Za='Zaffz:BAEANQAECgQICAABNQAFFAIIAgABAAAAAA==.',
['Zè']='Zèro:BAEANQADCggICAABNQAECgYICwABAAAAAA==.Zèrð:BAEANQAECgIIAgABNQAECgYICwABAAAAAA==.Zèrô:BAEANQADCgMIAwABNQAECgYICwABAAAAAA==.',
['Zé']='Zérò:BAEANQAECgYICwAAAA==.',
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
