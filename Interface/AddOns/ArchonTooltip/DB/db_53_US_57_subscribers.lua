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

local lookup = {'Monk-Windwalker','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Shaman-Enhancement','Druid-Guardian','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Priest-Discipline','Mage-Frost','Paladin-Protection','DemonHunter-Havoc','Mage-Arcane','Warrior-Arms','Unknown-Unknown','Hunter-BeastMastery','Shaman-Elemental','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Warrior-Fury',}
local provider = {region='US',realm='Dalaran',name='US',type='subscribers',zone=53,date='2026-10-13',data={Ad='Adansso:BAEBNQAECn8qAAIBAAgK4RLOJwDeAQiODQAABwAvAHUNAAAHADwAfw0AAAcANQCpDQAABgAwAFwNAAAFAD8AXQ0AAAUAHgBlDQAAAwAoADMNAAACACoAAQAICuESzicA3gEIjg0AAAcALwB1DQAABwA8AH8NAAAHADUAqQ0AAAYAMABcDQAABQA/AF0NAAAFAB4AZQ0AAAMAKAAzDQAAAgAqAAAA.',
Ap='Apawcowlypse:BAEANQAECgEIAQABNQAECgkJMwACAA4XAA==.',
As='Ashko:BAEBNQAECn8YAAMDAAkK7BINqADLAQmODQAABAA7AHUNAAADADUAfw0AAAMALQCpDQAAAwAYAFwNAAACACgAXQ0AAAIAJwBlDQAAAgBUAKQNAAACACQAMw0AAAMAVgADAAkK7BINqADLAQmODQAAAwA7AHUNAAADADUAfw0AAAMALQCpDQAAAwAYAFwNAAACACgAXQ0AAAIAJwBlDQAAAgBUAKQNAAACACQAMw0AAAIAVgAEAAIKYgkrDQFWAAKODQAAAQAaADMNAAABABUAATUABAoJCRkABQCoCwA=.Astralore:BAEBNQAECn8eAAIGAAgKMhf5EQA9AgiODQAABgBDAHUNAAAGAD0Afw0AAAQAVgCpDQAAAwA1AFwNAAADAE8AXQ0AAAMAOABlDQAAAQAmADMNAAAEAE0ABgAICjIX+REAPQIIjg0AAAYAQwB1DQAABgA9AH8NAAAEAFYAqQ0AAAMANQBcDQAAAwBPAF0NAAADADgAZQ0AAAEAJgAzDQAABABNAAAA.',
Az='Azurlia:BAEANQADCgMIAwAAAA==.',
Ba='Babycora:BAEBNQAECn8mAAIHAAgKyRuyMACiAgiODQAABgBYAHUNAAAGAFsAfw0AAAYAVACpDQAABgBYAFwNAAAEACYAXQ0AAAIAMgBlDQAAAgAqADMNAAAGAFUABwAICskbsjAAogIIjg0AAAYAWAB1DQAABgBbAH8NAAAGAFQAqQ0AAAYAWABcDQAABAAmAF0NAAACADIAZQ0AAAIAKgAzDQAABgBVAAE1AAQKCQlRAAcAZx4A.Barrui:BAECNQAFFH8rAAMIAAgKNhh6BQDEAQiODQAABwBVAHUNAAAHAEgAfw0AAAYAMQCpDQAABwBeAFwNAAAFACUAXQ0AAAMAMgBlDQAAAQAfADMNAAAHADkACAAFCm4ZegUAxAEFjg0AAAcAVQB1DQAABwBIAH8NAAAGADEAXA0AAAUAJQAzDQAABwA5AAkAAwr9FgINAB8BA6kNAAAHAF4AXQ0AAAMAMgBlDQAAAQAfADUABAp/IQADCAAJCnUiMiAAyQEACAAGCp4dMiAAyQEACQAFClcirUQArwEAAAA=.',
Be='Belynila:BAEBNQAECn8vAAIKAAkK0hnSEADqAgmODQAACABOAHUNAAAGAE4Afw0AAAUAVwCpDQAABwBDAFwNAAAGAFwAXQ0AAAQALQBlDQAAAwBIAKQNAAABABsAMw0AAAcAWwAKAAkK0hnSEADqAgmODQAACABOAHUNAAAGAE4Afw0AAAUAVwCpDQAABwBDAFwNAAAGAFwAXQ0AAAQALQBlDQAAAwBIAKQNAAABABsAMw0AAAcAWwAAAA==.Bestiavera:BAEANQAECgUIDAAAAA==.',
Br='Briggoker:BAEBNQAECn8eAAQLAAgKbRpJDgB4AgiODQAABgA+AHUNAAAEAEUAfw0AAAQAXgCpDQAABAA+AFwNAAADAD4AXQ0AAAIATgBlDQAAAQBFADMNAAAGAD4ACwAICm0aSQ4AeAIIjg0AAAQAPgB1DQAAAwBFAH8NAAAEAF4AqQ0AAAMAPgBcDQAAAgA+AF0NAAABAE4AZQ0AAAEARQAzDQAABQA+AAwABQqJDlEwABYBBY4NAAABADMAdQ0AAAEAFwBcDQAAAQAbAF0NAAABACMAMw0AAAEAMAANAAIKEQ5IIABTAAKODQAAAQA5AKkNAAABAA4AAAA=.Briggys:BAEANQAECgEIAQABNQAECggIHgALAG0aAA==.',
Bu='Bubblindora:BAECNQAFFH8ZAAMHAAcKPRzyBABPAgeODQAABABaAHUNAAAEAEIAfw0AAAQAPgCpDQAABABDAFwNAAACAFEAXQ0AAAEANQAzDQAABgBTAAcABwqKFvIEAE8CB44NAAABADsAdQ0AAAEAFAB/DQAAAQA+AKkNAAABADkAXA0AAAIAUQBdDQAAAQA1ADMNAAADAEQADgAFCjQa2AAAwQEFjg0AAAMAWgB1DQAAAwBCAH8NAAADABsAqQ0AAAMAQwAzDQAAAwBTADUABAp/LwADDgAJCpIj4wAAawMADgAJCnsj4wAAawMABwADCjAfRKsADwEAAAA=.',
Ca='Carbonarra:BAEANQAECgYIDAAAAA==.Catcam:BAEANQAECgUIBgAAAA==.',
Da='Dadbanger:BAECNQAFFH8oAAIBAAgK7CKOAAAWAwiODQAABwBjAHUNAAAGAFkAfw0AAAUAYQCpDQAABgBhAFwNAAAEAFQAXQ0AAAQAUABlDQAAAQBVADMNAAAHAFIAAQAICuwijgAAFgMIjg0AAAcAYwB1DQAABgBZAH8NAAAFAGEAqQ0AAAYAYQBcDQAABABUAF0NAAAEAFAAZQ0AAAEAVQAzDQAABwBSADUABAp/IgACAQAJCo4lEQsAIQMAAQAJCo4lEQsAIQMAAAA=.Darkvirgo:BAEBNQAECn8hAAIPAAkKICLVAQBlAwmODQAAAwBhAHUNAAAEAGEAfw0AAAQAYQCpDQAABQBTAFwNAAAEAFsAXQ0AAAMASwBlDQAAAwBiAKQNAAAEAEQAMw0AAAMAYQAPAAkKICLVAQBlAwmODQAAAwBhAHUNAAAEAGEAfw0AAAQAYQCpDQAABQBTAFwNAAAEAFsAXQ0AAAMASwBlDQAAAwBiAKQNAAAEAEQAMw0AAAMAYQABNQAFFAYIGQAKAEoQAA==.',
De='Deathbeaver:BAEANQAECgcIDAABNQAECggIHgAGADIXAA==.',
Et='Ethalon:BAEBNQAECn8lAAMEAAkK+hzQIADpAgmODQAABwBUAHUNAAAFAFoAfw0AAAUASgCpDQAABQBXAFwNAAACADcAXQ0AAAMAXgBlDQAABABGAKQNAAABABwAMw0AAAUAUQAEAAkK+hzQIADpAgmODQAABQBUAHUNAAAEAFoAfw0AAAQASgCpDQAABABXAFwNAAABADcAXQ0AAAMAXgBlDQAABABGAKQNAAABABwAMw0AAAMAUQAQAAYKKhU9MQBSAQaODQAAAgBDAHUNAAABAEMAfw0AAAEANwCpDQAAAQAhAFwNAAABADAAMw0AAAIAQQAAAA==.',
Fa='Fafademon:BAEBNQAECn8mAAIRAAgKASCXGADTAgiODQAABgBNAHUNAAAGAF4Afw0AAAYAWwCpDQAABgBTAFwNAAAFAF4AXQ0AAAQASgBlDQAAAwBCADMNAAACAE0AEQAICgEglxgA0wIIjg0AAAYATQB1DQAABgBeAH8NAAAGAFsAqQ0AAAYAUwBcDQAABQBeAF0NAAAEAEoAZQ0AAAMAQgAzDQAAAgBNAAAA.',
Ga='Garlooth:BAEBNQAECn8uAAMPAAkKRxkDFgBMAQmODQAACQBGAHUNAAAIAFYAfw0AAAgAPgCpDQAABgBKAFwNAAAEAFEAXQ0AAAMAKABlDQAAAgA9AKQNAAABACUAMw0AAAUASgASAAgKNRakoQA9AgiODQAACQBGAHUNAAAHADkAfw0AAAgAPgCpDQAABQA7AFwNAAADADYAZQ0AAAIAPQCkDQAAAQAlADMNAAAFAEoADwAECq4bAxYATAEEdQ0AAAEAVgCpDQAAAQBKAFwNAAABAFEAXQ0AAAMAKAAAAA==.',
Gi='Giantquin:BAEANQAECggICgABNQAECggIFQATAGgeAA==.',
Gl='Glizzygary:BAEANQAFFAMIBwAAAQ==.',
Gr='Grimsham:BAEANQAECgEIAQABNQAECggIHgAGADIXAA==.Grimvalor:BAEANQADCgUIBQABNQAECggIHgAGADIXAA==.Grujo:BAEANQAECggIBwABNQAECgkJGQAFAKgLAA==.Grunjitsu:BAEANQAECggICAABNQAECgkJGQAFAKgLAA==.Grunjo:BAEANQAECggIBwABNQAECgkJGQAFAKgLAA==.Grunsy:BAEANQAECgcIAQABNQAECgkJGQAFAKgLAA==.',
Ha='Haf:BAEBNQAECn8oAAIQAAkKyhG6HQD5AQmODQAABwBEAHUNAAAFADcAfw0AAAUAMgCpDQAABwAoAFwNAAAEADQAXQ0AAAMAIQBlDQAAAwAiAKQNAAABACAAMw0AAAUATAAQAAkKyhG6HQD5AQmODQAABwBEAHUNAAAFADcAfw0AAAUAMgCpDQAABwAoAFwNAAAEADQAXQ0AAAMAIQBlDQAAAwAiAKQNAAABACAAMw0AAAUATAAAAA==.Halrak:BAEANQADCggICAABNQAECggIHwAFAIoZAA==.',
He='Hertzmuch:BAEANQADCggICAABNQAECgkJMwACAA4XAA==.',
Hu='Hungbi:BAEANQAECggICAABNQAECggIJgAJABAhAA==.Huntsso:BAEANQADCgYIBgABNQAECggIKgABAOESAA==.',
Il='Illysara:BAEBNQAECn8hAAIOAAgK/CNfAQBBAwiODQAABQBbAHUNAAAFAFoAfw0AAAQAYACpDQAABQBhAFwNAAAEAFwAXQ0AAAMAXgBlDQAAAQBNADMNAAAGAGAADgAICvwjXwEAQQMIjg0AAAUAWwB1DQAABQBaAH8NAAAEAGAAqQ0AAAUAYQBcDQAABABcAF0NAAADAF4AZQ0AAAEATQAzDQAABgBgAAE1AAQKCAgsAAMANCIA.',
Ku='Kungfused:BAEBNQAECn8zAAMCAAkKDheUDwCCAgmODQAACQBHAHUNAAAHAFEAfw0AAAYAUwCpDQAABwBFAFwNAAAEACoAXQ0AAAMAKABlDQAAAwAZAKQNAAACABMAMw0AAAoAXwACAAkKDheUDwCCAgmODQAACABHAHUNAAAGAFEAfw0AAAUAUwCpDQAABgBFAFwNAAADACoAXQ0AAAIAKABlDQAAAwAZAKQNAAACABMAMw0AAAkAXwABAAcK5BE+MwB3AQeODQAAAQA0AHUNAAABADIAfw0AAAEAIgCpDQAAAQAZAFwNAAABADcAXQ0AAAEALQAzDQAAAQAuAAAA.',
Le='Lennather:BAEBNQAECn8nAAIBAAkK7x4kCwAfAwmODQAABgBbAHUNAAAFAF0Afw0AAAUAUQCpDQAABQBQAFwNAAAEAF0AXQ0AAAQAUgBlDQAABAA+AKQNAAACADEAMw0AAAQAUwABAAkK7x4kCwAfAwmODQAABgBbAHUNAAAFAF0Afw0AAAUAUQCpDQAABQBQAFwNAAAEAF0AXQ0AAAQAUgBlDQAABAA+AKQNAAACADEAMw0AAAQAUwAAAA==.',
Li='Linnadis:BAEANQAECgUICQABNQAECggIHwAFAIoZAA==.',
['Lé']='Lépewpew:BAEANQADCgYIDgABNQAECgMIBwAUAAAAAA==.',
Ma='Mattimus:BAEANQAECgQICgAAAA==.',
Me='Meowliver:BAEANQAECggICQABNQAECggIJgAJABAhAA==.Meviard:BAEANQAECgQIBAABNQAECggIHwAFAIoZAA==.',
Mo='Mookind:BAEANQAECgYIDQAAAA==.',
No='Noeyednuck:BAEANQAECgYIEAABNQAECgkJIAAVAHQeAA==.',
Nu='Nuckshott:BAEBNQAECn8gAAIVAAkKdB49KgDuAgmODQAABQBKAHUNAAAFAF4Afw0AAAQANACpDQAABABXAFwNAAADAFkAXQ0AAAMAQgBlDQAABQBIAKQNAAABADwAMw0AAAIAVAAVAAkKdB49KgDuAgmODQAABQBKAHUNAAAFAF4Afw0AAAQANACpDQAABABXAFwNAAADAFkAXQ0AAAMAQgBlDQAABQBIAKQNAAABADwAMw0AAAIAVAAAAA==.',
Og='Ogx:BAEBNQAECn8ZAAQFAAkKqAs3IABVAQmODQAAAgA0AHUNAAADAFYAfw0AAAMAMwCpDQAAAwAOAFwNAAADABsAXQ0AAAMAEQBlDQAAAwADAKQNAAADAAUAMw0AAAIARwAFAAgKIAo3IABVAQiODQAAAgA0AHUNAAADAFYAfw0AAAIAMwCpDQAAAgAOAFwNAAABAAAAXQ0AAAIAEQBlDQAAAwADAKQNAAADAAUAFgABCrMKAAAAAAABXA0AAAEAGwAXAAUKgwUAAAAAAAV/DQAAAQAGAKkNAAABABgAXA0AAAEAEwBdDQAAAQAJADMNAAACAAkAAAA=.',
Oh='Ohhio:BAEBNQAECn8lAAILAAkK6h84BgAmAwmODQAABgBXAHUNAAAFAFYAfw0AAAUAUwCpDQAABgBXAFwNAAADAE4AXQ0AAAMAYQBlDQAABAAzAKQNAAACAFMAMw0AAAMAUAALAAkK6h84BgAmAwmODQAABgBXAHUNAAAFAFYAfw0AAAUAUwCpDQAABgBXAFwNAAADAE4AXQ0AAAMAYQBlDQAABAAzAKQNAAACAFMAMw0AAAMAUAAAAA==.',
Ol='Oliverance:BAEANQAECggIEAABNQAECggIJgAJABAhAA==.Oliveroil:BAEBNQAECn8mAAMJAAgKECE3GQCvAgiODQAACABSAHUNAAAFAE4Afw0AAAUAXACpDQAABABhAFwNAAADAFAAXQ0AAAMARwBlDQAABgBbAKQNAAAEAFsACQAIChIfNxkArwIIjg0AAAIAQAB1DQAAAQA8AH8NAAADAEIAqQ0AAAQAYQBcDQAAAQBQAF0NAAADAEcAZQ0AAAYAWwCkDQAABABbAAgABAryGxQrAGYBBI4NAAAGAFIAdQ0AAAQATgB/DQAAAgBcAFwNAAACADUAAAA=.',
Pe='Pewpocalypse:BAEANQADCgYIBgABNQAECgkJMwACAA4XAA==.',
Pu='Purlok:BAEANQAECgMIBAABNQAECgkJGQAFAKgLAA==.',
Qu='Quinet:BAEBNQAECn8qAAMYAAkKQSIADQBkAwmODQAABwBcAHUNAAAGAF8Afw0AAAUAUACpDQAABQBSAFwNAAAEAGAAXQ0AAAQAWwBlDQAAAwBXAKQNAAACAEMAMw0AAAYAWwAYAAkKQSIADQBkAwmODQAABwBcAHUNAAAEAF8Afw0AAAUAUACpDQAABQBSAFwNAAAEAGAAXQ0AAAQAWwBlDQAAAwBXAKQNAAACAEMAMw0AAAYAWwAZAAEKNR1xawBIAAF1DQAAAgBKAAAA.Quinrawx:BAEBNQAECn8VAAITAAgKaB7HagBNAgiODQAABABSAHUNAAACAFYAfw0AAAIATgCpDQAABABHAFwNAAADAFMAXQ0AAAIAOwBlDQAAAwBSADMNAAABADUAEwAICmgex2oATQIIjg0AAAQAUgB1DQAAAgBWAH8NAAACAE4AqQ0AAAQARwBcDQAAAwBTAF0NAAACADsAZQ0AAAMAUgAzDQAAAQA1AAAA.Quinroxx:BAEANQAECgIIBAABNQAECggIFQATAGgeAA==.',
Ra='Razzun:BAECNQAFFH8lAAMSAAgKoCNhAgDFAgiODQAABABjAHUNAAAGAGMAfw0AAAUAXQCpDQAABgBjAFwNAAAFAFUAXQ0AAAQAYwBlDQAAAQA/ADMNAAAGAGMAEgAHCrchYQIAxQIHjg0AAAQAYwB1DQAABgBjAH8NAAAFAF0AqQ0AAAIAUwBcDQAABQBVAGUNAAABAD8AMw0AAAYAYwAPAAIK9SZbAwDmAAKpDQAABABjAF0NAAAEAGMANQAECn8iAAMSAAkKoSbZFwB1AwASAAkKoSbZFwB1AwAPAAEKVCVRQwA7AAAAAA==.',
Ro='Ronimus:BAEANQADCgIIAgAAAA==.Roofz:BAEBNQAECn8gAAIaAAkKXxlGNgBLAgmODQAABQBNAHUNAAAFAFEAfw0AAAMAPwCpDQAABABQAFwNAAADAFEAXQ0AAAMAKQBlDQAABAArAKQNAAACADEAMw0AAAMASgAaAAkKXxlGNgBLAgmODQAABQBNAHUNAAAFAFEAfw0AAAMAPwCpDQAABABQAFwNAAADAFEAXQ0AAAMAKQBlDQAABAArAKQNAAACADEAMw0AAAMASgAAAA==.Rothana:BAEANQAECgQICAABNQAECggIHwAFAIoZAA==.',
Ru='Rufio:BAECNQAFFH8GAAIRAAMKbQ91EQDXAAOODQAAAwA9AHUNAAABABMAqQ0AAAIAJQARAAMKbQ91EQDXAAOODQAAAwA9AHUNAAABABMAqQ0AAAIAJQA1AAQKfzgAAhEACQoVIxwHAIUDABEACQoVIxwHAIUDAAAA.Rufiø:BAEANQAECgUICwABNQAFFAMIBgARAG0PAA==.',
Sa='Saadxevok:BAEANQAECgcIDwABNQAFFAgIJAAKAHMdAA==.Saadxp:BAECNQAFFH8kAAQKAAgKcx1uAwAtAgiODQAABwBiAHUNAAAGAFYAfw0AAAQAKwCpDQAABgBfAFwNAAADACkAXQ0AAAMAQgBlDQAAAQA/ADMNAAAGAEUACgAGCmcebgMALQIGjg0AAAcAYgB1DQAABQBWAH8NAAACACsAqQ0AAAIAXwBcDQAAAwApAF0NAAACAEIADgAFChYT9AAAqwEFdQ0AAAEADgB/DQAAAgA5AKkNAAADAC8AZQ0AAAEAPgAzDQAABQA+AAcAAwoSD0kcAP4AA6kNAAABAA0AXQ0AAAEAQQAzDQAAAQAlADUABAp/JQAEDgAJCgslhgAAmAMADgAJCiEkhgAAmAMACgAFCjAkqioAzwEABwACCogX/dkAkQAAAAA=.Saelaeria:BAEANQAECgYICwABNQAECggIKwAbAEwjAA==.',
Sg='Sgtgigachad:BAEANQAECggIGgABNQAFFAMIBwAUAAAAAQ==.',
Sh='Shinohikari:BAEANQAECgMJBQABNQAECggIKwAbAEwjAA==.',
Sn='Sneezer:BAEANQAECgMIBwAAAA==.',
Sp='Spilt:BAECNQAFFH8bAAMWAAYKMCELBQAzAgaODQAABQBcAHUNAAAEAEQAfw0AAAMANQCpDQAABABdAFwNAAAEAFUAMw0AAAcAWgAWAAYKMCELBQAzAgaODQAABQBcAHUNAAAEAEQAfw0AAAMANQCpDQAABABdAFwNAAAEAFUAMw0AAAYAWgAXAAEKmQCHMQAzAAEzDQAAAQABADUABAp/LAADFgAJCkkl+QwAfwMAFgAJCkkl+QwAfwMAFwADCgEEGPoAcQAAAAA=.Spiltevoker:BAEANQADCgIIAgABNQAFFAYIGwAWADAhAA==.Spiltm:BAEANQAECgEIAQABNQAFFAYIGwAWADAhAA==.Spiltsham:BAEANQAECgYIDAABNQAFFAYIGwAWADAhAA==.',
Ta='Takalune:BAEANQADCgUIBQABNQAECggIKwAbAEwjAA==.Taku:BAEBNQAECn8rAAIbAAgKTCMZDwA0AwiODQAABwBZAHUNAAAGAF0Afw0AAAYAVgCpDQAABwBhAFwNAAAFAGIAXQ0AAAQATgBlDQAAAwBVADMNAAAFAF0AGwAICkwjGQ8ANAMIjg0AAAcAWQB1DQAABgBdAH8NAAAGAFYAqQ0AAAcAYQBcDQAABQBiAF0NAAAEAE4AZQ0AAAMAVQAzDQAABQBdAAAA.Tayvok:BAEBNQAECn8rAAINAAkKkBgKBQCgAgmODQAACABOAHUNAAAFAFEAfw0AAAYAPACpDQAABQBCAFwNAAAEAE8AXQ0AAAQARgBlDQAABQArAKQNAAABABQAMw0AAAUATQANAAkKkBgKBQCgAgmODQAACABOAHUNAAAFAFEAfw0AAAYAPACpDQAABQBCAFwNAAAEAE8AXQ0AAAQARgBlDQAABQArAKQNAAABABQAMw0AAAUATQAAAA==.',
Te='Tentickles:BAEBNQAECn8oAAQKAAkKiCByDQATAwmODQAABwBhAHUNAAAFAFwAfw0AAAUAXACpDQAABQBaAFwNAAAEAFEAXQ0AAAMARQBlDQAABgBJAKQNAAAEAE4AMw0AAAEAQQAKAAkKiCByDQATAwmODQAABQBhAHUNAAAEAFwAfw0AAAQAXACpDQAABABaAFwNAAADAFEAXQ0AAAIARQBlDQAAAwBJAKQNAAACAE4AMw0AAAEAQQAHAAYK3hVLfwCWAQaODQAAAgBEAHUNAAABACgAfw0AAAEALQBdDQAAAQAvAGUNAAADAD4ApA0AAAIASQAOAAIKHCCVFwC1AAKpDQAAAQBfAFwNAAABAEUAATUABRQICCgAAQDsIgA=.Teotihuacan:BAEANQAECggICQABNQAECggIJgAJABAhAA==.',
Th='Thecheatt:BAEBNQAECn8pAAMcAAkKniPgBgDwAgmODQAABwBcAHUNAAAGAGMAfw0AAAYAZACpDQAABwBjAFwNAAADAF0AXQ0AAAIAYABlDQAABwBYAKQNAAABAEQAMw0AAAIAWAAcAAcKGCXgBgDwAgeODQAABgBcAHUNAAAFAGMAfw0AAAUAYgCpDQAABQBjAFwNAAACAF0AXQ0AAAEAYABlDQAABABYAB0ACQoAGIUJADoCCY4NAAABADIAdQ0AAAEATAB/DQAAAQBkAKkNAAACADwAXA0AAAEAOwBdDQAAAQArAGUNAAADAEcApA0AAAEARAAzDQAAAgBYAAAA.Therelore:BAEBNQAECn8sAAMDAAgKNCIoMwD9AgiODQAABwBbAHUNAAAGAFsAfw0AAAYAUACpDQAABgBYAFwNAAAFAFsAXQ0AAAQAVgBlDQAAAwBLADMNAAAHAF4AAwAICjQiKDMA/QIIjg0AAAUAWwB1DQAABQBbAH8NAAADAFAAqQ0AAAQAWABcDQAABABbAF0NAAADAFYAZQ0AAAMASwAzDQAABQBeAAQABwoBGP5lAOMBB44NAAACAFgAdQ0AAAEARAB/DQAAAwAtAKkNAAACAE4AXA0AAAEAAgBdDQAAAQBPADMNAAACAEMAAAA=.Thoughtbott:BAEANQAECgMIBgABNQAECggIFwASAOIEAA==.',
Tr='Troysrus:BAEANQAECgQIBAABNQAECgcIDwAUAAAAAA==.Troystory:BAEANQAECgMIAwABNQAECgcIDwAUAAAAAA==.',
Ty='Tyära:BAEANQAECgIIAwABNQAECgkJMgAPAFsZAA==.',
Ur='Urlathor:BAEANQAECgIJAgAAAA==.',
Vi='Vilexie:BAEANQAECgcIDwAAAA==.',
Wa='Wafflé:BAEANQAECggIEAAAAA==.',
Za='Zanea:BAEANQAECgQICgABNQAECggIHwAFAIoZAA==.Zargan:BAEANQAECgYIDgABNQAECggIKwAbAEwjAA==.',
Zi='Zinia:BAEBNQAECn8fAAMFAAgKihknDwB1AgiODQAABQA5AHUNAAAFAD4Afw0AAAUAPACpDQAABQBRAFwNAAADAFgAXQ0AAAIASwBlDQAAAQAaADMNAAAFAFEABQAICooZJw8AdQIIjg0AAAQAOQB1DQAABQA+AH8NAAAEACcAqQ0AAAQAUQBcDQAAAwBYAF0NAAACAEsAZQ0AAAEAGgAzDQAABABRABYABAr3CrPXAOAABI4NAAABACIAfw0AAAEAPACpDQAAAQAVADMNAAABACsAAAA=.Zinidinia:BAEANQADCgUIBQABNQAECggIHwAFAIoZAA==.',
Zu='Zubbrael:BAEBNQAECn8tAAQKAAkKMCG6CgA1AwmODQAABwBiAHUNAAAIAGEAfw0AAAYAYwCpDQAABwBbAFwNAAAHAFsAXQ0AAAQAVgBlDQAAAQAvAKQNAAACAFEAMw0AAAMAGQAKAAkKMCG6CgA1AwmODQAABQBiAHUNAAAFAGEAfw0AAAQAYwCpDQAABQBbAFwNAAADAFsAXQ0AAAQAVgBlDQAAAQAvAKQNAAACAFEAMw0AAAEAGQAHAAYKfhiUdgCzAQaODQAAAgAxAHUNAAADADMAfw0AAAIASgCpDQAAAgBZAFwNAAAEAFIAMw0AAAEAHAAOAAEK0g6GKQAwAAEzDQAAAQAlAAE1AAQKCQkZABYAkyIA.Zubbzdh:BAEANQAECgcIBwABNQAECgkJGQAWAJMiAA==.Zubbzi:BAEBNQAECn8ZAAMWAAkKkyKmCAChAwmODQAABABdAHUNAAADAGAAfw0AAAQAYACpDQAABABiAFwNAAACAFcAXQ0AAAIAXwBlDQAAAwBPAKQNAAABAEQAMw0AAAIAVwAWAAkKkyKmCAChAwmODQAABABdAHUNAAADAGAAfw0AAAQAYACpDQAABABiAFwNAAACAFcAXQ0AAAEAXwBlDQAAAgBPAKQNAAABAEQAMw0AAAIAVwAXAAIKaAeH/wBkAAJdDQAAAQAXAGUNAAABAA4AAAA=.',
Zz='Zzertz:BAECNQAFFH8MAAMKAAUKTSHRBwCSAQWODQAABABaAHUNAAABAFUAfw0AAAEAGwCpDQAABABQADMNAAACABsACgAFCk0h0QcAkgEFjg0AAAMAWgB1DQAAAQBVAH8NAAABABsAqQ0AAAQAUAAzDQAAAgAbAAcAAQrXBXU5ADgAAY4NAAABAA4ANQAECn8kAAMKAAkKriUqBACVAwAKAAkKriUqBACVAwAHAAEK7QwZ9QA8AAAAAA==.Zzerz:BAEANQAECgcIDQABNQAFFAUIDAAKAE0hAA==.',
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
