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

local lookup = {'Monk-Windwalker','Monk-Mistweaver','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Unknown-Unknown','Priest-Discipline','Mage-Frost','Paladin-Holy','Paladin-Protection','DemonHunter-Havoc','Mage-Arcane','Paladin-Retribution','Hunter-BeastMastery','Evoker-Devastation','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Elemental','Shaman-Restoration','Evoker-Augmentation','Warrior-Protection','Warrior-Fury',}
local provider = {region='US',realm='Dalaran',name='US',type='subscribers',zone=53,date='2026-09-29',data={Ad='Adansso:BAEBNQAECoEcAAIBAAgKtQwUJAClAQiODQAABQAlAHUNAAAFACMAfw0AAAUAFwCpDQAABAAwAFwNAAADABgAXQ0AAAMAHgBlDQAAAQASADMNAAACACoAAQAICrUMFCQApQEIjg0AAAUAJQB1DQAABQAjAH8NAAAFABcAqQ0AAAQAMABcDQAAAwAYAF0NAAADAB4AZQ0AAAEAEgAzDQAAAgAqAAAA.',
Ap='Apawcowlypse:BAEANQAECgEIAQABNQAECgkJKwACAFUVAA==.',
As='Ashko:BAEANQAECggIEgAAAA==.Astralore:BAEANQAECgYIDQAAAA==.',
Az='Azurlia:BAEANQADCgMIAwAAAA==.',
Ba='Babycora:BAEBNQAECoEYAAIDAAcK5xr2OgA2AgeODQAABABYAHUNAAAEAFsAfw0AAAQAPgCpDQAABABIAFwNAAADACQAXQ0AAAEAMgAzDQAABABQAAMABwrnGvY6ADYCB44NAAAEAFgAdQ0AAAQAWwB/DQAABAA+AKkNAAAEAEgAXA0AAAMAJABdDQAAAQAyADMNAAAEAFAAATUABAoJCUYAAwCyHQA=.Barrui:BAECNQAFFIEcAAMEAAcKaRPpAwDHAQeODQAABQBMAHUNAAAFAEgAfw0AAAQAMQCpDQAABQBeAFwNAAADAAwAXQ0AAAEABAAzDQAABQAlAAQABQpoE+kDAMcBBY4NAAAFAEwAdQ0AAAUASAB/DQAABAAxAFwNAAADAAwAMw0AAAUAJQAFAAIKahOTCQDCAAKpDQAABQBeAF0NAAABAAQANQAECoEdAAMEAAkKWCLPGQDmAQAEAAYKPx/PGQDmAQAFAAQKDyI9PABZAQAAAA==.',
Be='Belynila:BAEBNQAECoEhAAIGAAgK3RqMEgCZAgiODQAABgBCAHUNAAAFAE4Afw0AAAQAQwCpDQAABQBDAFwNAAAEAFwAXQ0AAAMALQBlDQAAAQApADMNAAAFAFoABgAICt0ajBIAmQIIjg0AAAYAQgB1DQAABQBOAH8NAAAEAEMAqQ0AAAUAQwBcDQAABABcAF0NAAADAC0AZQ0AAAEAKQAzDQAABQBaAAAA.Bestiavera:BAEANQAECgQIBwAAAA==.',
Br='Briggoker:BAEANQAECgYIEAAAAA==.Briggys:BAEANQADCgYICQABNQAECgYIEAAHAAAAAA==.',
Bu='Bubblindora:BAECNQAFFIEXAAMDAAcKPRzUAQB7AgeODQAABABaAHUNAAAEAEIAfw0AAAQAPgCpDQAABABDAFwNAAACAFEAXQ0AAAEANQAzDQAABABTAAMABwrrFdQBAHsCB44NAAABADsAdQ0AAAEAFAB/DQAAAQA+AKkNAAABADkAXA0AAAIAUQBdDQAAAQA1ADMNAAABADkACAAFCjQafgAA0gEFjg0AAAMAWgB1DQAAAwBCAH8NAAADABsAqQ0AAAMAQwAzDQAAAwBTADUABAqBKQADCAAJCpIjjQAAfwMACAAJCnsjjQAAfwMAAwADCqEbz4oAAQEAAAA=.',
Ca='Carbonarra:BAEANQAECgUICgAAAA==.',
Da='Dadbanger:BAECNQAFFIEfAAIBAAcKGiKnAADEAgeODQAABgBjAHUNAAAFAFkAfw0AAAQAYQCpDQAABQBhAFwNAAADAFQAXQ0AAAMARgAzDQAABQBJAAEABwoaIqcAAMQCB44NAAAGAGMAdQ0AAAUAWQB/DQAABABhAKkNAAAFAGEAXA0AAAMAVABdDQAAAwBGADMNAAAFAEkANQAECoEfAAIBAAkKjiW6BgBDAwABAAkKjiW6BgBDAwAAAA==.Darkvirgo:BAEBNQAECoEaAAIJAAkKAyPcAACPAwmODQAAAgBhAHUNAAADAGEAfw0AAAMAYQCpDQAABABTAFwNAAADAFsAXQ0AAAMASwBlDQAAAwBiAKQNAAAEAEQAMw0AAAEAYQAJAAkKAyPcAACPAwmODQAAAgBhAHUNAAADAGEAfw0AAAMAYQCpDQAABABTAFwNAAADAFsAXQ0AAAMASwBlDQAAAwBiAKQNAAAEAEQAMw0AAAEAYQABNQAFFAYIEgAGAJ8OAA==.',
De='Deathbeaver:BAEANQAECgUICgABNQAECgYIDQAHAAAAAA==.',
Et='Ethalon:BAEBNQAECoEiAAMKAAgKMB9jHwDDAgiODQAABgBUAHUNAAAFAFoAfw0AAAUASgCpDQAABQBXAFwNAAACADcAXQ0AAAMAXgBlDQAAAwBGADMNAAAFAFEACgAICjAfYx8AwwIIjg0AAAQAVAB1DQAABABaAH8NAAAEAEoAqQ0AAAQAVwBcDQAAAQA3AF0NAAADAF4AZQ0AAAMARgAzDQAAAwBRAAsABgryFfkhAHcBBo4NAAACAEMAdQ0AAAEAQwB/DQAAAQA3AKkNAAABACEAXA0AAAEAMAAzDQAAAgBBAAAA.',
Fa='Fafademon:BAEBNQAECoEYAAIMAAgKKR10GACTAgiODQAABABNAHUNAAAEAFcAfw0AAAQAUgCpDQAABABEAFwNAAADAE0AXQ0AAAIASQBlDQAAAQA0ADMNAAACAE0ADAAICikddBgAkwIIjg0AAAQATQB1DQAABABXAH8NAAAEAFIAqQ0AAAQARABcDQAAAwBNAF0NAAACAEkAZQ0AAAEANAAzDQAAAgBNAAAA.',
Ga='Garlooth:BAEBNQAECoEdAAMNAAgKhBY2owDzAQiODQAABgBAAHUNAAAFADcAfw0AAAUALQCpDQAABABKAFwNAAADADYAXQ0AAAIAHQBlDQAAAQA9ADMNAAADAEoADQAHCtsUNqMA8wEHjg0AAAYAQAB1DQAABQA3AH8NAAAFAC0AqQ0AAAMAEABcDQAAAwA2AGUNAAABAD0AMw0AAAMASgAJAAIKZBTCIgCVAAKpDQAAAQBKAF0NAAACAB0AAAA=.',
Gl='Glizzygary:BAEANQAFFAMIBQAAAQ==.',
Gr='Grimsham:BAEANQAECgEIAQABNQAECgYIDQAHAAAAAA==.Grimvalor:BAEANQADCgUIBQABNQAECgYIDQAHAAAAAA==.Grujo:BAEANQAECggICAABNQAECggIEgAHAAAAAA==.Grunjo:BAEANQAECggICAABNQAECggIEgAHAAAAAA==.',
Ha='Haf:BAEBNQAECoEbAAILAAgK3hL+GQDLAQiODQAABQBAAHUNAAAEADcAfw0AAAQAMgCpDQAABQAeAFwNAAADADQAXQ0AAAIAIQBlDQAAAQAVADMNAAADAEwACwAICt4S/hkAywEIjg0AAAUAQAB1DQAABAA3AH8NAAAEADIAqQ0AAAUAHgBcDQAAAwA0AF0NAAACACEAZQ0AAAEAFQAzDQAAAwBMAAAA.',
He='Heightwalker:BAEANQADCgQIBAAAAA==.Hertzmuch:BAEANQADCggICAABNQAECgkJKwACAFUVAA==.',
Hu='Huntsso:BAEANQADCgYIBgABNQAECggIHAABALUMAA==.',
Il='Illysara:BAEBNQAECoEZAAIIAAcKrCTzAQDuAgeODQAABABbAHUNAAAEAFkAfw0AAAMAXwCpDQAABABhAFwNAAADAFwAXQ0AAAIAXgAzDQAABQBgAAgABwqsJPMBAO4CB44NAAAEAFsAdQ0AAAQAWQB/DQAAAwBfAKkNAAAEAGEAXA0AAAMAXABdDQAAAgBeADMNAAAFAGAAATUABAoICBwADgD+HQA=.',
Ku='Kungfused:BAEBNQAECoErAAMCAAkKVRWSDAB/AgmODQAACABHAHUNAAAGAEYAfw0AAAUAUwCpDQAABgA5AFwNAAADACoAXQ0AAAMAKABlDQAAAgAOAKQNAAABAA4AMw0AAAkAXwACAAkKVRWSDAB/AgmODQAABwBHAHUNAAAFAEYAfw0AAAQAUwCpDQAABQA5AFwNAAACACoAXQ0AAAIAKABlDQAAAgAOAKQNAAABAA4AMw0AAAgAXwABAAcKTBH/JQCQAQeODQAAAQA0AHUNAAABADIAfw0AAAEAIgCpDQAAAQAZAFwNAAABADcAXQ0AAAEALQAzDQAAAQAuAAAA.',
Le='Lennather:BAEBNQAECoEZAAIBAAgKlx8xDADkAgiODQAABABbAHUNAAADAF0Afw0AAAMARwCpDQAAAwBQAFwNAAADAF0AXQ0AAAMARgBlDQAAAgA+ADMNAAAEAFMAAQAICpcfMQwA5AIIjg0AAAQAWwB1DQAAAwBdAH8NAAADAEcAqQ0AAAMAUABcDQAAAwBdAF0NAAADAEYAZQ0AAAIAPgAzDQAABABTAAAA.',
Li='Linnadis:BAEANQADCgcIFQABNQAECgYIEAAHAAAAAA==.',
['Lé']='Lépewpew:BAEANQADCgYIDgABNQAECgIIAgAHAAAAAA==.',
Ma='Mattimus:BAEANQAECgQIBwAAAA==.',
Me='Meviard:BAEANQADCgYIBwABNQAECgYIEAAHAAAAAA==.',
Mo='Mookind:BAEANQAECgYIDQAAAA==.',
No='Noeyednuck:BAEANQAECgQIDgABNQAECggIHAAPAGUeAA==.',
Nu='Nuckshott:BAEBNQAECoEcAAIPAAgKZR4kJADNAgiODQAABABKAHUNAAAFAF4Afw0AAAQANACpDQAABABXAFwNAAADAFkAXQ0AAAMAQgBlDQAAAwBIADMNAAACAFQADwAICmUeJCQAzQIIjg0AAAQASgB1DQAABQBeAH8NAAAEADQAqQ0AAAQAVwBcDQAAAwBZAF0NAAADAEIAZQ0AAAMASAAzDQAAAgBUAAAA.',
Og='Ogx:BAEANQAECggIEgABNQAECggIEgAHAAAAAA==.',
Oh='Ohhio:BAEBNQAECoEhAAIQAAkKohufBwDeAgmODQAABQBVAHUNAAAFAFYAfw0AAAUAUwCpDQAABQBXAFwNAAADAE4AXQ0AAAMAYQBlDQAAAwAjAKQNAAABAAIAMw0AAAMAUAAQAAkKohufBwDeAgmODQAABQBVAHUNAAAFAFYAfw0AAAUAUwCpDQAABQBXAFwNAAADAE4AXQ0AAAMAYQBlDQAAAwAjAKQNAAABAAIAMw0AAAMAUAAAAA==.',
Pu='Purlok:BAEANQAECgMIBAABNQAECggIEgAHAAAAAA==.',
Qu='Quinet:BAEBNQAECoEZAAMRAAgK9iHzFAALAwiODQAABQBcAHUNAAAEAF8Afw0AAAMAUACpDQAAAwBSAFwNAAACAF4AXQ0AAAIAUwBlDQAAAQBMADMNAAAFAFsAEQAICvYh8xQACwMIjg0AAAUAXAB1DQAAAgBfAH8NAAADAFAAqQ0AAAMAUgBcDQAAAgBeAF0NAAACAFMAZQ0AAAEATAAzDQAABQBbABIAAQo1HU9gAEwAAXUNAAACAEoAAAA=.Quinrawx:BAEBNQAECoEVAAITAAgKOR3AQwCEAgiODQAABABSAHUNAAACAFYAfw0AAAIATgCpDQAABABHAFwNAAADAFMAXQ0AAAIAOwBlDQAAAwBSADMNAAABADUAEwAICjkdwEMAhAIIjg0AAAQAUgB1DQAAAgBWAH8NAAACAE4AqQ0AAAQARwBcDQAAAwBTAF0NAAACADsAZQ0AAAMAUgAzDQAAAQA1AAAA.Quinroxx:BAEANQAECgIIBAABNQAECggIFQATADkdAA==.',
Ra='Razzun:BAECNQAFFIEdAAMNAAcKOyPlAgBlAgeODQAAAwBDAHUNAAAFAGMAfw0AAAQAXQCpDQAABQBjAFwNAAAEAFUAXQ0AAAMAVwAzDQAABQBjAA0ABgpgIuUCAGUCBo4NAAADAEMAdQ0AAAUAYwB/DQAABABdAKkNAAACAFMAXA0AAAQAVQAzDQAABQBjAAkAAgqNJM8BANsAAqkNAAADAGMAXQ0AAAMAVwA1AAQKgR8AAw0ACQrzJZQNAJIDAA0ACQrzJZQNAJIDAAkAAQpUJWYzAEMAAAAA.',
Ro='Roofz:BAEBNQAECoEgAAIUAAkKwhkQHwCIAgmODQAABQBNAHUNAAAFAFEAfw0AAAMAPwCpDQAABABQAFwNAAADAFEAXQ0AAAMAKQBlDQAABAArAKQNAAACADEAMw0AAAMASgAUAAkKwhkQHwCIAgmODQAABQBNAHUNAAAFAFEAfw0AAAMAPwCpDQAABABQAFwNAAADAFEAXQ0AAAMAKQBlDQAABAArAKQNAAACADEAMw0AAAMASgAAAA==.Rothana:BAEANQAECgEIAQABNQAECgYIEAAHAAAAAA==.',
Ru='Rufio:BAEBNQAECoEkAAIMAAkKdh45CwAsAwmODQAABQBdAHUNAAAGAGEAfw0AAAUAVgCpDQAABQBQAFwNAAAEAEQAXQ0AAAMASwBlDQAABABVAKQNAAACAEoAMw0AAAIAJgAMAAkKdh45CwAsAwmODQAABQBdAHUNAAAGAGEAfw0AAAUAVgCpDQAABQBQAFwNAAAEAEQAXQ0AAAMASwBlDQAABABVAKQNAAACAEoAMw0AAAIAJgAAAA==.Rufiø:BAEANQAECgUICQABNQAECgkJJAAMAHYeAA==.',
Sa='Saadxevok:BAEANQAECgcIDwABNQAFFAcIGwAGAGUYAA==.Saadxp:BAECNQAFFIEbAAQGAAcKZRjJAQAvAgeODQAABgBiAHUNAAAFAFYAfw0AAAMAKwCpDQAABQA3AFwNAAACACkAXQ0AAAIAKQAzDQAABABFAAYABgrnF8kBAC8CBo4NAAAGAGIAdQ0AAAQAVgB/DQAAAQArAKkNAAABADcAXA0AAAIAKQBdDQAAAQApAAgABAq4EfEAAE0BBHUNAAABAA4Afw0AAAIAOQCpDQAAAwAvADMNAAADAD4AAwADChIPGBIACAEDqQ0AAAEADQBdDQAAAQBBADMNAAABACUANQAECoEfAAQIAAkKCyVWAACeAwAIAAkKISRWAACeAwAGAAQKKh7LLgBcAQADAAIKiBdNrQCUAAAAAA==.Saelaeria:BAEANQAECgQIBQABNQAECggIGwAVAEUgAA==.',
Sg='Sgtgigachad:BAEANQAECggIGQABNQAFFAMIBQAHAAAAAQ==.',
Sh='Shinohikari:BAEANQAECgMJBQABNQAECggIGwAVAEUgAA==.',
Sn='Sneezer:BAEANQAECgIIAgAAAA==.',
Sp='Spilt:BAECNQAFFIEZAAMWAAYKHR9fAgA6AgaODQAABQBcAHUNAAAEAEQAfw0AAAMANQCpDQAABABdAFwNAAAEAFUAMw0AAAUAVAAWAAYKHR9fAgA6AgaODQAABQBcAHUNAAAEAEQAfw0AAAMANQCpDQAABABdAFwNAAAEAFUAMw0AAAQAVAAXAAEKmQD0JAAzAAEzDQAAAQABADUABAqBLAADFgAJChgkdQcAmwMAFgAJChgkdQcAmwMAFwADCgEEQM4AdAAAAAA=.Spiltevoker:BAEANQADCgIIAgABNQAFFAYIGQAWAB0fAA==.Spiltm:BAEANQAECgEIAQABNQAFFAYIGQAWAB0fAA==.Spiltsham:BAEANQAECgYIDAABNQAFFAYIGQAWAB0fAA==.',
Ta='Takalune:BAEANQADCgUIBQABNQAECggIGwAVAEUgAA==.Taku:BAEBNQAECoEbAAIVAAgKRSA8EgDyAgiODQAABQBTAHUNAAAEAFQAfw0AAAQAVACpDQAABQBbAFwNAAADAGIAXQ0AAAIAQwBlDQAAAQBQADMNAAADAEcAFQAICkUgPBIA8gIIjg0AAAUAUwB1DQAABABUAH8NAAAEAFQAqQ0AAAUAWwBcDQAAAwBiAF0NAAACAEMAZQ0AAAEAUAAzDQAAAwBHAAAA.Tayvok:BAEBNQAECoEhAAIYAAgKkhqPBAB6AgiODQAABgBOAHUNAAAEAFEAfw0AAAUAPACpDQAABABCAFwNAAADAEoAXQ0AAAMARgBlDQAAAwAjADMNAAAFAE0AGAAICpIajwQAegIIjg0AAAYATgB1DQAABABRAH8NAAAFADwAqQ0AAAQAQgBcDQAAAwBKAF0NAAADAEYAZQ0AAAMAIwAzDQAABQBNAAAA.',
Te='Tentickles:BAEBNQAECoEhAAQGAAkKJiB9CAA0AwmODQAABABhAHUNAAAFAFwAfw0AAAUAXACpDQAABQBaAFwNAAAEAFEAXQ0AAAMARQBlDQAABABJAKQNAAACAE4AMw0AAAEAQQAGAAkKJiB9CAA0AwmODQAABABhAHUNAAAEAFwAfw0AAAQAXACpDQAABABaAFwNAAADAFEAXQ0AAAIARQBlDQAAAwBJAKQNAAACAE4AMw0AAAEAQQADAAQK5w9mjAD8AAR1DQAAAQAoAH8NAAABAC0AXQ0AAAEALwBlDQAAAQAeAAgAAgocIBITALsAAqkNAAABAF8AXA0AAAEARQABNQAFFAcIHwABABoiAA==.',
Th='Thecheatt:BAEBNQAECoEgAAMZAAgKcCRQBQDjAgiODQAABQBcAHUNAAAFAGEAfw0AAAUAZACpDQAABgBjAFwNAAACAFoAXQ0AAAIAYABlDQAABQBQADMNAAACAFgAGQAHCpskUAUA4wIHjg0AAAQAXAB1DQAABABhAH8NAAAEAGIAqQ0AAAQAYwBcDQAAAQBaAF0NAAABAGAAZQ0AAAIAUAAaAAgK3RqnCAAIAgiODQAAAQAyAHUNAAABAEwAfw0AAAEAZACpDQAAAgA8AFwNAAABADsAXQ0AAAEAKwBlDQAAAwBHADMNAAACAFgAAAA=.Therelore:BAEBNQAECoEcAAMOAAgK/h32OwCaAgiODQAABQBbAHUNAAAEAFUAfw0AAAQAUACpDQAABABEAFwNAAADAE4AXQ0AAAIARQBlDQAAAQAsADMNAAAFAF4ADgAICv4d9jsAmgIIjg0AAAMAWwB1DQAAAwBVAH8NAAACAFAAqQ0AAAIARABcDQAAAgBOAF0NAAACAEUAZQ0AAAEALAAzDQAAAwBeAAoABgrRFpRmAJQBBo4NAAACAFgAdQ0AAAEARAB/DQAAAgAtAKkNAAACAE4AXA0AAAEAAgAzDQAAAgBDAAAA.Thoughtbott:BAEANQAECgMIBgABNQAECgYIBwAHAAAAAA==.',
Tr='Troysrus:BAEANQABCgcIGAABNQAECgcJCgAHAAAAAA==.Troystory:BAEANQAECgMIAwABNQAECgcJCgAHAAAAAA==.',
Ty='Tyära:BAEANQAECgIIAwABNQAECggIIQAJAIQaAA==.',
Ur='Urlathor:BAEANQAECgIJAgAAAA==.',
Vi='Vilexie:BAEANQAECgcJCgAAAA==.',
Wa='Wafflé:BAEANQAECggIDQAAAA==.',
Za='Zanea:BAEANQAECgEIAQABNQAECgYIEAAHAAAAAA==.Zargan:BAEANQAECgYIBgABNQAECggIGwAVAEUgAA==.',
Zi='Zinia:BAEANQAECgYIEAAAAA==.',
Zu='Zubbrael:BAEBNQAECoEnAAQGAAkKKx9XBgBXAwmODQAABgBiAHUNAAAHAGEAfw0AAAUAYwCpDQAABgBbAFwNAAAGAFsAXQ0AAAQAVgBlDQAAAQAvAKQNAAABAE8AMw0AAAMAGQAGAAkKKx9XBgBXAwmODQAABQBiAHUNAAAFAGEAfw0AAAQAYwCpDQAABQBbAFwNAAADAFsAXQ0AAAQAVgBlDQAAAQAvAKQNAAABAE8AMw0AAAEAGQADAAYKOgxyfgAsAQaODQAAAQAFAHUNAAACABQAfw0AAAEAMgCpDQAAAQAoAFwNAAADACkAMw0AAAEAHAAIAAEK0g7wHwA5AAEzDQAAAQAlAAAA.Zubbzdh:BAEANQAECgcIBwABNQAECgkJJwAGACsfAA==.',
Zz='Zzertz:BAECNQAFFIEJAAMGAAMK0hmbCQD1AAOODQAABABaAKkNAAADAFAAMw0AAAIAGwAGAAMK0hmbCQD1AAOODQAAAwBaAKkNAAADAFAAMw0AAAIAGwADAAEK1wVPKABGAAGODQAAAQAOADUABAqBIwADBgAJCtolmgEAwQMABgAJCtolmgEAwQMAAwABCu0MwsQAPAAAAAA=.Zzerz:BAEANQAECgcIDQABNQAFFAMICQAGANIZAA==.',
['Àb']='Àbel:BAEANQAECgQIDQAAAA==.',
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
