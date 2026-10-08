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

local lookup = {'Monk-Windwalker','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Druid-Guardian','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Priest-Discipline','Mage-Frost','Paladin-Protection','DemonHunter-Havoc','Mage-Arcane','Warrior-Arms','Shaman-Enhancement','Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Warrior-Fury',}
local provider = {region='US',realm='Dalaran',name='US',type='subscribers',zone=53,date='2026-10-06',data={Ad='Adansso:BAEBNQAECoEjAAIBAAgKuAyUKgCWAQiODQAABgAlAHUNAAAGACMAfw0AAAYAFwCpDQAABQAwAFwNAAAEABgAXQ0AAAQAHgBlDQAAAgASADMNAAACACoAAQAICrgMlCoAlgEIjg0AAAYAJQB1DQAABgAjAH8NAAAGABcAqQ0AAAUAMABcDQAABAAYAF0NAAAEAB4AZQ0AAAIAEgAzDQAAAgAqAAAA.',
Ap='Apawcowlypse:BAEANQAECgEIAQABNQAECgkJMwACAA4XAA==.',
As='Ashko:BAEBNQAECoEdAAMDAAkK2xFkgAD3AQmODQAABQA7AHUNAAAEADUAfw0AAAQAQwCpDQAABAAYAFwNAAACACgAXQ0AAAIAJwBlDQAAAgACAKQNAAADACQAMw0AAAMAVgADAAkK2xFkgAD3AQmODQAABAA7AHUNAAAEADUAfw0AAAQAQwCpDQAABAAYAFwNAAACACgAXQ0AAAIAJwBlDQAAAgACAKQNAAADACQAMw0AAAIAVgAEAAIKYgmM9gBWAAKODQAAAQAaADMNAAABABUAAAA=.Astralore:BAEBNQAECoEXAAIFAAcK/xlwEQAIAgeODQAABQBDAHUNAAAFAD0Afw0AAAMAVgCpDQAAAgAlAFwNAAACAE8AXQ0AAAIAOAAzDQAABABNAAUABwr/GXARAAgCB44NAAAFAEMAdQ0AAAUAPQB/DQAAAwBWAKkNAAACACUAXA0AAAIATwBdDQAAAgA4ADMNAAAEAE0AAAA=.',
Az='Azurlia:BAEANQADCgMIAwAAAA==.',
Ba='Babycora:BAEBNQAECoEgAAIGAAgKixsLKgCiAgiODQAABQBYAHUNAAAFAFsAfw0AAAUAVACpDQAABQBYAFwNAAAEACYAXQ0AAAIAMgBlDQAAAQAqADMNAAAFAFAABgAICosbCyoAogIIjg0AAAUAWAB1DQAABQBbAH8NAAAFAFQAqQ0AAAUAWABcDQAABAAmAF0NAAACADIAZQ0AAAEAKgAzDQAABQBQAAE1AAQKCQlLAAYAVB4A.Barrui:BAECNQAFFIEjAAMHAAcKaBamBADOAQeODQAABgBVAHUNAAAGAEgAfw0AAAUAMQCpDQAABgBeAFwNAAAEAAwAXQ0AAAIAHAAzDQAABgA5AAcABQq6FaYEAM4BBY4NAAAGAFUAdQ0AAAYASAB/DQAABQAxAFwNAAAEAAwAMw0AAAYAOQAIAAIKHBiLDQDAAAKpDQAABgBeAF0NAAACABwANQAECoEgAAMHAAkKeCK/HADaAQAHAAYKPx+/HADaAQAIAAQKVyJxSQBVAQAAAA==.',
Be='Belynila:BAEBNQAECoEpAAIJAAgK1h2kEQDFAgiODQAABwBMAHUNAAAGAE4Afw0AAAUAVwCpDQAABgBDAFwNAAAFAFwAXQ0AAAQALQBlDQAAAgBIADMNAAAGAFsACQAICtYdpBEAxQIIjg0AAAcATAB1DQAABgBOAH8NAAAFAFcAqQ0AAAYAQwBcDQAABQBcAF0NAAAEAC0AZQ0AAAIASAAzDQAABgBbAAAA.Bestiavera:BAEANQAECgQIEAAAAA==.',
Br='Briggoker:BAEBNQAECoEbAAQKAAcKgRvjEAAoAgeODQAABQA+AHUNAAAEAEUAfw0AAAQAXgCpDQAABAA+AFwNAAADAD4AXQ0AAAIATgAzDQAABQA+AAoABwqBG+MQACgCB44NAAADAD4AdQ0AAAMARQB/DQAABABeAKkNAAADAD4AXA0AAAIAPgBdDQAAAQBOADMNAAAEAD4ACwAFCokOrywAHAEFjg0AAAEAMwB1DQAAAQAXAFwNAAABABsAXQ0AAAEAIwAzDQAAAQAwAAwAAgoRDrMcAFMAAo4NAAABADkAqQ0AAAEADgAAAA==.Briggys:BAEANQADCgYIDAABNQAECgcIGwAKAIEbAA==.',
Bu='Bubblindora:BAECNQAFFIEYAAMGAAcKPRwUAwBoAgeODQAABABaAHUNAAAEAEIAfw0AAAQAPgCpDQAABABDAFwNAAACAFEAXQ0AAAEANQAzDQAABQBTAAYABwqKFhQDAGgCB44NAAABADsAdQ0AAAEAFAB/DQAAAQA+AKkNAAABADkAXA0AAAIAUQBdDQAAAQA1ADMNAAACAEQADQAFCjQarAAAxgEFjg0AAAMAWgB1DQAAAwBCAH8NAAADABsAqQ0AAAMAQwAzDQAAAwBTADUABAqBLAADDQAJCpIjrwAAdgMADQAJCnsjrwAAdgMABgADCoQdZZgAEAEAAAA=.',
Ca='Carbonarra:BAEANQAECgUIDgAAAA==.',
Da='Dadbanger:BAECNQAFFIEmAAIBAAcKNyO9AADFAgeODQAABwBjAHUNAAAGAFkAfw0AAAUAYQCpDQAABgBhAFwNAAAEAFQAXQ0AAAQAUAAzDQAABgBSAAEABwo3I70AAMUCB44NAAAHAGMAdQ0AAAYAWQB/DQAABQBhAKkNAAAGAGEAXA0AAAQAVABdDQAABABQADMNAAAGAFIANQAECoEfAAIBAAkKjiXnCAAuAwABAAkKjiXnCAAuAwAAAA==.Darkvirgo:BAEBNQAECoEgAAIOAAkKAyM3AQB3AwmODQAAAwBhAHUNAAAEAGEAfw0AAAQAYQCpDQAABQBTAFwNAAAEAFsAXQ0AAAMASwBlDQAAAwBiAKQNAAAEAEQAMw0AAAIAYQAOAAkKAyM3AQB3AwmODQAAAwBhAHUNAAAEAGEAfw0AAAQAYQCpDQAABQBTAFwNAAAEAFsAXQ0AAAMASwBlDQAAAwBiAKQNAAAEAEQAMw0AAAIAYQABNQAFFAYIGAAJAJ4RAA==.',
De='Deathbeaver:BAEANQAECgYIDQABNQAECgcIFwAFAP8ZAA==.',
Et='Ethalon:BAEBNQAECoElAAMEAAkK+hw9GgD6AgmODQAABwBUAHUNAAAFAFoAfw0AAAUASgCpDQAABQBXAFwNAAACADcAXQ0AAAMAXgBlDQAABABGAKQNAAABABwAMw0AAAUAUQAEAAkK+hw9GgD6AgmODQAABQBUAHUNAAAEAFoAfw0AAAQASgCpDQAABABXAFwNAAABADcAXQ0AAAMAXgBlDQAABABGAKQNAAABABwAMw0AAAMAUQAPAAYK8hUdKgBgAQaODQAAAgBDAHUNAAABAEMAfw0AAAEANwCpDQAAAQAhAFwNAAABADAAMw0AAAIAQQAAAA==.',
Fa='Fafademon:BAEBNQAECoEfAAIQAAgKih93FQDSAgiODQAABQBNAHUNAAAFAF4Afw0AAAUAWwCpDQAABQBTAFwNAAAEAF4AXQ0AAAMASQBlDQAAAgA0ADMNAAACAE0AEAAICoofdxUA0gIIjg0AAAUATQB1DQAABQBeAH8NAAAFAFsAqQ0AAAUAUwBcDQAABABeAF0NAAADAEkAZQ0AAAIANAAzDQAAAgBNAAAA.',
Ga='Garlooth:BAEBNQAECoEqAAMOAAgK9xqSEgBVAQiODQAACABGAHUNAAAHAFYAfw0AAAcAPgCpDQAABgBKAFwNAAAEAFEAXQ0AAAMAKABlDQAAAgA9ADMNAAAFAEoAEQAHCoAY9KYAEwIHjg0AAAgARgB1DQAABgA3AH8NAAAHAD4AqQ0AAAUAOwBcDQAAAwA2AGUNAAACAD0AMw0AAAUASgAOAAQKrhuSEgBVAQR1DQAAAQBWAKkNAAABAEoAXA0AAAEAUQBdDQAAAwAoAAAA.',
Gi='Giantquin:BAEANQAECggIAwABNQAECggIFQASADkdAA==.',
Gl='Glizzygary:BAEANQAFFAMIBwAAAQ==.',
Gr='Grimsham:BAEANQAECgEIAgABNQAECgcIFwAFAP8ZAA==.Grimvalor:BAEANQADCgUIBQABNQAECgcIFwAFAP8ZAA==.Grujo:BAEANQAECggICAABNQAECgkJHQADANsRAA==.Grunclaws:BAEANQAECggICQABNQAECgkJHQADANsRAA==.Grunjitsu:BAEANQAECggICAABNQAECgkJHQADANsRAA==.Grunjo:BAEANQAECggIDwABNQAECgkJHQADANsRAA==.Grunsy:BAEANQAECgcIAQABNQAECgkJHQADANsRAA==.',
Ha='Haf:BAEBNQAECoEjAAIPAAgKBRMkIAC4AQiODQAABgBAAHUNAAAFADcAfw0AAAUAMgCpDQAABgAeAFwNAAAEADQAXQ0AAAMAIQBlDQAAAgAYADMNAAAEAEwADwAICgUTJCAAuAEIjg0AAAYAQAB1DQAABQA3AH8NAAAFADIAqQ0AAAYAHgBcDQAABAA0AF0NAAADACEAZQ0AAAIAGAAzDQAABABMAAAA.',
He='Hertzmuch:BAEANQAECgEIAQABNQAECgkJMwACAA4XAA==.',
Hu='Huntsso:BAEANQADCgYIBgABNQAECggIIwABALgMAA==.',
Il='Illysara:BAEBNQAECoEhAAINAAgK/CMJAQBLAwiODQAABQBbAHUNAAAFAFoAfw0AAAQAYACpDQAABQBhAFwNAAAEAFwAXQ0AAAMAXgBlDQAAAQBNADMNAAAGAGAADQAICvwjCQEASwMIjg0AAAUAWwB1DQAABQBaAH8NAAAEAGAAqQ0AAAUAYQBcDQAABABcAF0NAAADAF4AZQ0AAAEATQAzDQAABgBgAAE1AAQKCAgkAAMAfB8A.',
Ku='Kungfused:BAEBNQAECoEzAAMCAAkKDhf1DACRAgmODQAACQBHAHUNAAAHAFEAfw0AAAYAUwCpDQAABwBFAFwNAAAEACoAXQ0AAAMAKABlDQAAAwAZAKQNAAACABMAMw0AAAoAXwACAAkKDhf1DACRAgmODQAACABHAHUNAAAGAFEAfw0AAAUAUwCpDQAABgBFAFwNAAADACoAXQ0AAAIAKABlDQAAAwAZAKQNAAACABMAMw0AAAkAXwABAAcKTBGYLACCAQeODQAAAQA0AHUNAAABADIAfw0AAAEAIgCpDQAAAQAZAFwNAAABADcAXQ0AAAEALQAzDQAAAQAuAAAA.',
Le='Lennather:BAEBNQAECoEfAAIBAAkKjx4wCgAZAwmODQAABQBbAHUNAAAEAF0Afw0AAAQATwCpDQAABABQAFwNAAADAF0AXQ0AAAMARgBlDQAAAwA+AKQNAAABADEAMw0AAAQAUwABAAkKjx4wCgAZAwmODQAABQBbAHUNAAAEAF0Afw0AAAQATwCpDQAABABQAFwNAAADAF0AXQ0AAAMARgBlDQAAAwA+AKQNAAABADEAMw0AAAQAUwAAAA==.',
Li='Linnadis:BAEANQAECgQIBAABNQAECgcIGAATAM4TAA==.',
['Lé']='Lépewpew:BAEANQADCgYIDgABNQAECgIIBAAUAAAAAA==.',
Ma='Mattimus:BAEANQAECgQIDgAAAA==.',
Me='Meowliver:BAEANQAECggICAABNQAECggIHwAIAAcdAA==.Meviard:BAEANQADCgYICQABNQAECgcIGAATAM4TAA==.',
Mo='Mookind:BAEANQAECgYIDQAAAA==.',
No='Noeyednuck:BAEANQAECgUIEAABNQAECggIHQAVAGUeAA==.',
Nu='Nuckshott:BAEBNQAECoEdAAIVAAgKZR62MAC4AgiODQAABABKAHUNAAAFAF4Afw0AAAQANACpDQAABABXAFwNAAADAFkAXQ0AAAMAQgBlDQAABABIADMNAAACAFQAFQAICmUetjAAuAIIjg0AAAQASgB1DQAABQBeAH8NAAAEADQAqQ0AAAQAVwBcDQAAAwBZAF0NAAADAEIAZQ0AAAQASAAzDQAAAgBUAAAA.',
Og='Ogx:BAEBNQAECoEaAAQTAAkKcA7SGwBwAQmODQAAAwA0AHUNAAADAFYAfw0AAAMAMwCpDQAAAwAOAFwNAAADABsAXQ0AAAMAEQBlDQAAAwADAKQNAAADAAUAMw0AAAIARwATAAgKZAvSGwBwAQiODQAAAgA0AHUNAAADAFYAfw0AAAIAMwCpDQAAAgAOAFwNAAABAAAAXQ0AAAIAEQBlDQAAAwADAKQNAAADAAUAFgAGCu0Eea4A5QAGjg0AAAEABQB/DQAAAQAGAKkNAAABABgAXA0AAAEAEwBdDQAAAQAJADMNAAACAAkAFwABCrMKexABOAABXA0AAAEAGwABNQAECgkJHQADANsRAA==.',
Oh='Ohhio:BAEBNQAECoElAAIKAAkK9R/5BAA0AwmODQAABgBXAHUNAAAFAFYAfw0AAAUAUwCpDQAABgBXAFwNAAADAE4AXQ0AAAMAYQBlDQAABAAzAKQNAAACAFMAMw0AAAMAUAAKAAkK9R/5BAA0AwmODQAABgBXAHUNAAAFAFYAfw0AAAUAUwCpDQAABgBXAFwNAAADAE4AXQ0AAAMAYQBlDQAABAAzAKQNAAACAFMAMw0AAAMAUAAAAA==.',
Ol='Oliverance:BAEANQAECggICAABNQAECggIHwAIAAcdAA==.Oliveroil:BAEBNQAECoEfAAMIAAgKBx0dIQBPAgiODQAABgBSAHUNAAAFAE4Afw0AAAUAXACpDQAABABhAFwNAAADAFAAXQ0AAAMARwBlDQAABABMAKQNAAABAA8ACAAICgUaHSEATwIIjg0AAAIAQAB1DQAAAQA8AH8NAAADAEIAqQ0AAAQAYQBcDQAAAQBQAF0NAAADAEcAZQ0AAAQATACkDQAAAQAPAAcABAoFHocnAHEBBI4NAAAEAFIAdQ0AAAQATgB/DQAAAgBcAFwNAAACADUAAAA=.',
Pe='Pewpocalypse:BAEANQADCgYIBgABNQAECgkJMwACAA4XAA==.',
Pu='Purlok:BAEANQAECgMIBAABNQAECgkJHQADANsRAA==.',
Qu='Quinet:BAEBNQAECoEiAAMYAAkKNh/+EQAzAwmODQAABgBcAHUNAAAFAF8Afw0AAAQAUACpDQAABABSAFwNAAADAF4AXQ0AAAMAVQBlDQAAAgBMAKQNAAABABUAMw0AAAYAWwAYAAkKNh/+EQAzAwmODQAABgBcAHUNAAADAF8Afw0AAAQAUACpDQAABABSAFwNAAADAF4AXQ0AAAMAVQBlDQAAAgBMAKQNAAABABUAMw0AAAYAWwAZAAEKNR0nZgBKAAF1DQAAAgBKAAAA.Quinrawx:BAEBNQAECoEVAAISAAgKOR1ZVgBsAgiODQAABABSAHUNAAACAFYAfw0AAAIATgCpDQAABABHAFwNAAADAFMAXQ0AAAIAOwBlDQAAAwBSADMNAAABADUAEgAICjkdWVYAbAIIjg0AAAQAUgB1DQAAAgBWAH8NAAACAE4AqQ0AAAQARwBcDQAAAwBTAF0NAAACADsAZQ0AAAMAUgAzDQAAAQA1AAAA.Quinroxx:BAEANQAECgIIBQABNQAECggIFQASADkdAA==.',
Ra='Razzun:BAECNQAFFIElAAMRAAgKHiRLAQDUAgiODQAABABjAHUNAAAGAGMAfw0AAAUAXQCpDQAABgBjAFwNAAAFAFUAXQ0AAAQAYwBlDQAAAQA/ADMNAAAGAGMAEQAHCtMiSwEA1AIHjg0AAAQAYwB1DQAABgBjAH8NAAAFAF0AqQ0AAAIAUwBcDQAABQBVAGUNAAABAD8AMw0AAAYAYwAOAAIK9SZeAgDpAAKpDQAABABjAF0NAAAEAGMANQAECoEhAAMRAAkKUCb1DwCOAwARAAkKUCb1DwCOAwAOAAEKVCU+OwA/AAAAAA==.',
Ro='Roofz:BAEBNQAECoEgAAIaAAkKwhn9LQBXAgmODQAABQBNAHUNAAAFAFEAfw0AAAMAPwCpDQAABABQAFwNAAADAFEAXQ0AAAMAKQBlDQAABAArAKQNAAACADEAMw0AAAMASgAaAAkKwhn9LQBXAgmODQAABQBNAHUNAAAFAFEAfw0AAAMAPwCpDQAABABQAFwNAAADAFEAXQ0AAAMAKQBlDQAABAArAKQNAAACADEAMw0AAAMASgAAAA==.Rothana:BAEANQAECgQIBQABNQAECgcIGAATAM4TAA==.',
Ru='Rufio:BAEBNQAECoExAAIQAAkK7CHtBgB7AwmODQAABwBdAHUNAAAIAGEAfw0AAAcAWwCpDQAABwBUAFwNAAAFAF0AXQ0AAAQAWQBlDQAABQBYAKQNAAADAEoAMw0AAAMAQwAQAAkK7CHtBgB7AwmODQAABwBdAHUNAAAIAGEAfw0AAAcAWwCpDQAABwBUAFwNAAAFAF0AXQ0AAAQAWQBlDQAABQBYAKQNAAADAEoAMw0AAAMAQwAAAA==.Rufiø:BAEANQAECgUIDAABNQAECgkJMQAQAOwhAA==.',
Sa='Saadxevok:BAEANQAECgcIEAABNQAFFAcIIgAJAAgcAA==.Saadxp:BAECNQAFFIEiAAQJAAcKCBxgAgA9AgeODQAABwBiAHUNAAAGAFYAfw0AAAQAKwCpDQAABgBfAFwNAAADACkAXQ0AAAMAQgAzDQAABQBFAAkABgomHGACAD0CBo4NAAAHAGIAdQ0AAAUAVgB/DQAAAgArAKkNAAACAF8AXA0AAAMAKQBdDQAAAgBCAA0ABAq4ESEBAEsBBHUNAAABAA4Afw0AAAIAOQCpDQAAAwAvADMNAAAEAD4ABgADChIP3hYABwEDqQ0AAAEADQBdDQAAAQBBADMNAAABACUANQAECoEiAAQNAAkKCyVsAACZAwANAAkKISRsAACZAwAJAAUKJCKnJQDZAQAGAAIKiBeQxACTAAAAAA==.Saelaeria:BAEANQAECgYIDwABNQAECggIIwAbACAiAA==.',
Sg='Sgtgigachad:BAEANQAECggIHQABNQAFFAMIBwAUAAAAAQ==.',
Sh='Shinohikari:BAEANQAECgMJBwABNQAECggIIwAbACAiAA==.',
Sn='Sneezer:BAEANQAECgIIBAAAAA==.',
Sp='Spilt:BAECNQAFFIEaAAMXAAYKix+JAwA9AgaODQAABQBcAHUNAAAEAEQAfw0AAAMANQCpDQAABABdAFwNAAAEAFUAMw0AAAYAWgAXAAYKix+JAwA9AgaODQAABQBcAHUNAAAEAEQAfw0AAAMANQCpDQAABABdAFwNAAAEAFUAMw0AAAUAWgAWAAEKmQATLAAzAAEzDQAAAQABADUABAqBLAADFwAJChgkHAoAiwMAFwAJChgkHAoAiwMAFgADCgEE8+YAbAAAAAA=.Spiltevoker:BAEANQADCgIIAgABNQAFFAYIGgAXAIsfAA==.Spiltm:BAEANQAECgEIAQABNQAFFAYIGgAXAIsfAA==.Spiltsham:BAEANQAECgYIDQABNQAFFAYIGgAXAIsfAA==.',
Su='Sunjo:BAEANQAECggICAABNQAECgkJHQADANsRAA==.',
Ta='Takalune:BAEANQADCgUIBQABNQAECggIIwAbACAiAA==.Taku:BAEBNQAECoEjAAIbAAgKICIcEAAZAwiODQAABgBZAHUNAAAFAF0Afw0AAAUAVACpDQAABgBbAFwNAAAEAGIAXQ0AAAMATgBlDQAAAgBQADMNAAAEAFMAGwAICiAiHBAAGQMIjg0AAAYAWQB1DQAABQBdAH8NAAAFAFQAqQ0AAAYAWwBcDQAABABiAF0NAAADAE4AZQ0AAAIAUAAzDQAABABTAAAA.Tayvok:BAEBNQAECoEoAAIMAAgK0BpWBQBxAgiODQAABwBOAHUNAAAFAFEAfw0AAAYAPACpDQAABQBCAFwNAAAEAE8AXQ0AAAQARgBlDQAABAAjADMNAAAFAE0ADAAICtAaVgUAcQIIjg0AAAcATgB1DQAABQBRAH8NAAAGADwAqQ0AAAUAQgBcDQAABABPAF0NAAAEAEYAZQ0AAAQAIwAzDQAABQBNAAAA.',
Te='Tentickles:BAEBNQAECoEnAAQJAAkKJiB4CwAZAwmODQAABgBhAHUNAAAFAFwAfw0AAAUAXACpDQAABQBaAFwNAAAEAFEAXQ0AAAMARQBlDQAABgBJAKQNAAAEAE4AMw0AAAEAQQAJAAkKJiB4CwAZAwmODQAABABhAHUNAAAEAFwAfw0AAAQAXACpDQAABABaAFwNAAADAFEAXQ0AAAIARQBlDQAAAwBJAKQNAAACAE4AMw0AAAEAQQAGAAYK3hVGbQCfAQaODQAAAgBEAHUNAAABACgAfw0AAAEALQBdDQAAAQAvAGUNAAADAD4ApA0AAAIASQANAAIKHCB3FQC5AAKpDQAAAQBfAFwNAAABAEUAATUABRQHCCYAAQA3IwA=.Teotihuacan:BAEANQAECggICQABNQAECggIHwAIAAcdAA==.',
Th='Thecheatt:BAEBNQAECoEmAAMcAAgKByWuBQD1AgiODQAABgBcAHUNAAAGAGMAfw0AAAYAZACpDQAABwBjAFwNAAADAF0AXQ0AAAIAYABlDQAABgBYADMNAAACAFgAHAAHCkglrgUA9QIHjg0AAAUAXAB1DQAABQBjAH8NAAAFAGIAqQ0AAAUAYwBcDQAAAgBdAF0NAAABAGAAZQ0AAAMAWAAdAAgK3RqJCgD8AQiODQAAAQAyAHUNAAABAEwAfw0AAAEAZACpDQAAAgA8AFwNAAABADsAXQ0AAAEAKwBlDQAAAwBHADMNAAACAFgAAAA=.Therelore:BAEBNQAECoEkAAMDAAgKfB/rRgCaAgiODQAABgBbAHUNAAAFAFUAfw0AAAUAUACpDQAABQBEAFwNAAAEAE4AXQ0AAAMARQBlDQAAAgBLADMNAAAGAF4AAwAICnwf60YAmgIIjg0AAAQAWwB1DQAABABVAH8NAAACAFAAqQ0AAAMARABcDQAAAwBOAF0NAAACAEUAZQ0AAAIASwAzDQAABABeAAQABwoBGOdZAOkBB44NAAACAFgAdQ0AAAEARAB/DQAAAwAtAKkNAAACAE4AXA0AAAEAAgBdDQAAAQBPADMNAAACAEMAAAA=.Thoughtbott:BAEANQAECgMIBgABNQAECggIFQARACwEAA==.',
Tr='Troysrus:BAEANQAECgEIAwABNQAECgcICwAUAAAAAA==.Troystory:BAEANQAECgMIBAABNQAECgcICwAUAAAAAA==.',
Ty='Tyära:BAEANQAECgIIBAABNQAECggIKQAOANccAA==.',
Ur='Urlathor:BAEANQAECgIJAwAAAA==.',
Vi='Vilexie:BAEANQAECgcICwAAAA==.',
Wa='Wafflé:BAEANQAECggIEAAAAA==.',
Za='Zanea:BAEANQAECgQIBQABNQAECgcIGAATAM4TAA==.Zargan:BAEANQAECgYICgABNQAECggIIwAbACAiAA==.',
Zi='Zinia:BAEBNQAECoEYAAMTAAcKzhNLFAD7AQeODQAABAA5AHUNAAAEADAAfw0AAAQAJwCpDQAABAAlAFwNAAACADsAXQ0AAAEAHwAzDQAABQBRABMABwrOE0sUAPsBB44NAAAEADkAdQ0AAAQAMAB/DQAABAAnAKkNAAADACUAXA0AAAIAOwBdDQAAAQAfADMNAAAEAFEAFwACCqgMgPgAYQACqQ0AAAEAFQAzDQAAAQArAAAA.',
Zu='Zubbrael:BAEBNQAECoEtAAQJAAkKPB81CABHAwmODQAABwBiAHUNAAAIAGEAfw0AAAYAYwCpDQAABwBbAFwNAAAHAFsAXQ0AAAQAVgBlDQAAAQAvAKQNAAACAFEAMw0AAAMAGQAJAAkKPB81CABHAwmODQAABQBiAHUNAAAFAGEAfw0AAAQAYwCpDQAABQBbAFwNAAADAFsAXQ0AAAQAVgBlDQAAAQAvAKQNAAACAFEAMw0AAAEAGQAGAAYKfhghZQC9AQaODQAAAgAxAHUNAAADADMAfw0AAAIASgCpDQAAAgBZAFwNAAAEAFIAMw0AAAEAHAANAAEK0g6+IwA5AAEzDQAAAQAlAAAA.Zubbzdh:BAEANQAECgcICAABNQAECgkJLQAJADwfAA==.Zubbzi:BAEANQAECgcIBgABNQAECgkJLQAJADwfAA==.',
Zz='Zzertz:BAECNQAFFIEJAAMJAAMK0hnsCwDsAAOODQAABABaAKkNAAADAFAAMw0AAAIAGwAJAAMK0hnsCwDsAAOODQAAAwBaAKkNAAADAFAAMw0AAAIAGwAGAAEK1wWhMABAAAGODQAAAQAOADUABAqBJAADCQAJCtolrgIAqQMACQAJCtolrgIAqQMABgABCu0M+d0APAAAAAA=.Zzerz:BAEANQAECgcIDwABNQAFFAMICQAJANIZAA==.',
['Àb']='Àbel:BAEANQAECgQIEQAAAA==.',
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
