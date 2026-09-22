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

local lookup = {'Monk-Mistweaver','Unknown-Unknown','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Priest-Discipline','Monk-Windwalker','Paladin-Holy','Paladin-Protection','Hunter-BeastMastery','Evoker-Devastation','Mage-Arcane','Mage-Frost','DemonHunter-Havoc','Evoker-Augmentation','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','Warrior-Protection',}
local provider = {region='US',realm='Dalaran',name='US',type='subscribers',zone=53,date='2026-09-22',data={Ad='Adansso:BAEANQAECgYIEwAAAA==.',
Ap='Apawcowlypse:BAEANQADCggIDgABNQAECggIHQABAH4WAA==.',
As='Ashko:BAEANQAECggJDQAAAA==.Astralore:BAEANQAECgMJBwABNQAECgUJBQACAAAAAA==.',
Az='Azurlia:BAEANQADCgMIAwAAAA==.',
Ba='Babycora:BAEANQAECgUIDgABNQAECggJNwADAOAfAA==.Barrui:BAECNQAFFIEWAAMEAAcKEhD+AgDKAQeODQAABABMAHUNAAAEADUAfw0AAAMAKACpDQAABABBAFwNAAACAAoAXQ0AAAEABAAzDQAABAAlAAQABQoPEf4CAMoBBY4NAAAEAEwAdQ0AAAQANQB/DQAAAwAoAFwNAAACAAoAMw0AAAQAJQAFAAIKmg0aBwCzAAKpDQAABABBAF0NAAABAAQANQAECoEbAAMEAAkK8B9nFgD1AQAEAAYKPx9nFgD1AQAFAAQKphxVNAA3AQAAAA==.',
Be='Belynila:BAEBNQAECoEZAAIGAAcKAheaGQARAgeODQAABQA9AHUNAAAEADkAfw0AAAMANQCpDQAABAAoAFwNAAADAEAAXQ0AAAIALQAzDQAABABaAAYABwoCF5oZABECB44NAAAFAD0AdQ0AAAQAOQB/DQAAAwA1AKkNAAAEACgAXA0AAAMAQABdDQAAAgAtADMNAAAEAFoAAAA=.Bestiavera:BAEANQAECgEIAwAAAA==.',
Br='Briggoker:BAEANQAECgUICgAAAA==.Briggys:BAEANQADCgUJBQABNQAECgUICgACAAAAAA==.',
Bu='Bubblindora:BAECNQAFFIEQAAMHAAYKDBdcAADgAQaODQAAAwBaAHUNAAADAEIAfw0AAAMAGwCpDQAAAwBDAFwNAAABABIAMw0AAAMAUwAHAAUKNBpcAADgAQWODQAAAwBaAHUNAAADAEIAfw0AAAMAGwCpDQAAAwBDADMNAAADAFMAAwABCkMHvBkAWQABXA0AAAEAEgA1AAQKgSYAAgcACQp7I2kAAIcDAAcACQp7I2kAAIcDAAAA.',
Ca='Carbonarra:BAEANQAECgUJCgAAAA==.',
Da='Dadbanger:BAECNQAFFIEYAAIIAAcKQSBbAADNAgeODQAABQBjAHUNAAAEAFIAfw0AAAMAYQCpDQAABABhAFwNAAACAFQAXQ0AAAIALAAzDQAABABJAAgABwpBIFsAAM0CB44NAAAFAGMAdQ0AAAQAUgB/DQAAAwBhAKkNAAAEAGEAXA0AAAIAVABdDQAAAgAsADMNAAAEAEkANQAECoEcAAIIAAkKDyUgBQBQAwAIAAkKDyUgBQBQAwAAAA==.Darkvirgo:BAEANQAECggIEwABNQAFFAUJDAAGADsQAA==.',
De='Deathbeaver:BAEANQAECgUJBQAAAA==.',
Et='Ethalon:BAEBNQAECoEaAAMJAAgKMB8DGADOAgiODQAABQBUAHUNAAAEAFoAfw0AAAQASgCpDQAABABXAFwNAAABADcAXQ0AAAIAXgBlDQAAAgBGADMNAAAEAFEACQAICjAfAxgAzgIIjg0AAAQAVAB1DQAABABaAH8NAAAEAEoAqQ0AAAQAVwBcDQAAAQA3AF0NAAACAF4AZQ0AAAIARgAzDQAAAgBRAAoAAgoCF1w7AHoAAo4NAAABADQAMw0AAAIAQQAAAA==.',
Fa='Fafademon:BAEANQAECgYIDwAAAA==.',
Ga='Garlooth:BAEANQAECgYIEwAAAA==.',
Gl='Glizzygary:BAEANQAFFAIIAgAAAQ==.',
Gr='Grimsham:BAEANQAECgEIAQABNQAECgUJBQACAAAAAA==.Grimvalor:BAEANQADCgUIBQABNQAECgUJBQACAAAAAA==.Grujo:BAEANQAECggJCAABNQAECggJDQACAAAAAA==.',
Ha='Haf:BAEANQAECgYJEQAAAA==.',
He='Heightwalker:BAEANQADCgQIBAAAAA==.Hertzmuch:BAEANQADCggICAABNQAECggIHQABAH4WAA==.',
Hu='Huntsso:BAEANQADCgYIBgABNQAECgYIEwACAAAAAA==.',
Il='Illysara:BAEANQAECgYIDgABNQAECgYJEAACAAAAAA==.',
Ku='Kungfused:BAEBNQAECoEdAAIBAAgKfhaIDABLAgiODQAABgA3AHUNAAAEAEUAfw0AAAMAUwCpDQAABAA5AFwNAAACACoAXQ0AAAIAKABlDQAAAQAOADMNAAAHAF8AAQAICn4WiAwASwIIjg0AAAYANwB1DQAABABFAH8NAAADAFMAqQ0AAAQAOQBcDQAAAgAqAF0NAAACACgAZQ0AAAEADgAzDQAABwBfAAAA.',
Le='Lennather:BAEANQAECgcIDgAAAA==.',
Li='Linnadis:BAEANQADCgcJEwABNQAECgUJCgACAAAAAA==.',
['Lé']='Lépewpew:BAEANQADCgYIDgABNQADCggIDQACAAAAAA==.',
Ma='Mattimus:BAEANQAECgQIBwAAAA==.',
Me='Meviard:BAEANQADCgQIBQABNQAECgUJCgACAAAAAA==.',
Mo='Mookind:BAEANQAECgYICgAAAA==.',
['Má']='Mákí:BAEANQADCgYIBgAAAA==.',
No='Noeyednuck:BAEANQAECgQICAABNQAECggIFgALACYcAA==.',
Nu='Nuckshott:BAEBNQAECoEWAAILAAgKJhzXIgCuAgiODQAABABKAHUNAAAEAFwAfw0AAAMANACpDQAAAwA8AFwNAAACAFEAXQ0AAAIAPgBlDQAAAgBEADMNAAACAFQACwAICiYc1yIArgIIjg0AAAQASgB1DQAABABcAH8NAAADADQAqQ0AAAMAPABcDQAAAgBRAF0NAAACAD4AZQ0AAAIARAAzDQAAAgBUAAAA.',
Og='Ogx:BAEANQAECggICgABNQAECggJDQACAAAAAA==.',
Oh='Ohhio:BAEBNQAECoEYAAIMAAgKqBuKCQCYAgiODQAABABQAHUNAAAEAE8Afw0AAAQAUwCpDQAABABFAFwNAAACADYAXQ0AAAIAUwBlDQAAAQAjADMNAAADAFAADAAICqgbigkAmAIIjg0AAAQAUAB1DQAABABPAH8NAAAEAFMAqQ0AAAQARQBcDQAAAgA2AF0NAAACAFMAZQ0AAAEAIwAzDQAAAwBQAAAA.',
Pu='Purlok:BAEANQAECgMIBAABNQAECggJDQACAAAAAA==.',
Qu='Quinet:BAEANQAECgYJDQAAAA==.Quinrawx:BAEANQAECgcJEAAAAA==.Quinroxx:BAEANQAECgIIBAABNQAECgcJEAACAAAAAA==.',
Ra='Razzun:BAECNQAFFIEWAAMNAAcKoiDeAQBkAgeODQAAAgAuAHUNAAAEAGMAfw0AAAMAXQCpDQAABABaAFwNAAADAE0AXQ0AAAIATwAzDQAABABiAA0ABgp0IN4BAGQCBo4NAAACAC4AdQ0AAAQAYwB/DQAAAwBdAKkNAAACAFMAXA0AAAMATQAzDQAABABiAA4AAgo8IUkBAM4AAqkNAAACAFoAXQ0AAAIATwA1AAQKgR0AAw0ACQrzJcIIAKcDAA0ACQrzJcIIAKcDAA4AAQpUJfcoAEsAAAAA.',
Ro='Rothana:BAEANQADCggIEQABNQAECgUJCgACAAAAAA==.',
Ru='Rufio:BAEBNQAECoEcAAIPAAkKuhZ1FQCLAgmODQAABABOAHUNAAAFAEoAfw0AAAQAVACpDQAABABFAFwNAAADAEQAXQ0AAAIAEgBlDQAAAwAvAKQNAAABACoAMw0AAAIAJgAPAAkKuhZ1FQCLAgmODQAABABOAHUNAAAFAEoAfw0AAAQAVACpDQAABABFAFwNAAADAEQAXQ0AAAIAEgBlDQAAAwAvAKQNAAABACoAMw0AAAIAJgAAAA==.Rufiø:BAEANQAECgIJBAABNQAECgkJHAAPALoWAA==.',
Ry='Rytiou:BAECNQAFFIEKAAIQAAYKkBEXAQD8AQaODQAAAgArAHUNAAACADUAfw0AAAIAEwCpDQAAAgAvAFwNAAABACcAMw0AAAEAQgAQAAYKkBEXAQD8AQaODQAAAgArAHUNAAACADUAfw0AAAIAEwCpDQAAAgAvAFwNAAABACcAMw0AAAEAQgA1AAQKgSAAAhAACQp/H3UCAO8CABAACQp/H3UCAO8CAAAA.',
Sa='Saadxevok:BAEANQAECgcIDwABNQAFFAcIFQAHADQXAA==.Saadxp:BAECNQAFFIEVAAQHAAcKNBeiAABfAQeODQAABQBhAHUNAAAEAA4Afw0AAAIAOQCpDQAABAAvAFwNAAABAEgAXQ0AAAEAQQAzDQAABAA+AAcABAq4EaIAAF8BBHUNAAABAA4Afw0AAAIAOQCpDQAAAwAvADMNAAADAD4ABgADCuAY2QUALAEDjg0AAAUAYgB1DQAAAwBEAFwNAAABABcAAwADChIPvAwADAEDqQ0AAAEADQBdDQAAAQBBADMNAAABACUANQAECoEcAAQHAAkKCyWoAABbAwAHAAgK0iWoAABbAwAGAAQKIR4XKABmAQADAAIKiBcRkgCVAAAAAA==.Saelaeria:BAEANQAECgQIBQABNQAECgYJEQACAAAAAA==.',
Sg='Sgtgigachad:BAEANQAECggIFwABNQAFFAIIAgACAAAAAQ==.',
Sh='Shinohikari:BAEANQAECgMJBQABNQAECgYJEQACAAAAAA==.',
Sn='Sneezer:BAEANQADCggIDQAAAA==.',
Sp='Spilt:BAECNQAFFIETAAMRAAYKChxoAQA1AgaODQAABABcAHUNAAADADsAfw0AAAIANQCpDQAAAwBZAFwNAAADADMAMw0AAAQAVAARAAYKChxoAQA1AgaODQAABABcAHUNAAADADsAfw0AAAIANQCpDQAAAwBZAFwNAAADADMAMw0AAAMAVAASAAEKmQDGHAAzAAEzDQAAAQABADUABAqBKgADEQAJChgk8QQArAMAEQAJChgk8QQArAMAEgADCv8DxLEAgQAAAAA=.Spiltevoker:BAEANQADCgIIAgABNQAFFAYIEwARAAocAA==.Spiltm:BAEANQAECgEIAQABNQAFFAYIEwARAAocAA==.Spiltsham:BAEANQAECgYIDAABNQAFFAYIEwARAAocAA==.',
Ta='Takalune:BAEANQADCgUIBQABNQAECgYJEQACAAAAAA==.Taku:BAEANQAECgYJEQAAAA==.Tayvok:BAEBNQAECoEZAAIQAAgKDxh5BABSAgiODQAABQBOAHUNAAADAEQAfw0AAAQAOgCpDQAAAwBCAFwNAAACAEkAXQ0AAAIAOwBlDQAAAgAQADMNAAAEAEcAEAAICg8YeQQAUgIIjg0AAAUATgB1DQAAAwBEAH8NAAAEADoAqQ0AAAMAQgBcDQAAAgBJAF0NAAACADsAZQ0AAAIAEAAzDQAABABHAAAA.',
Te='Tentickles:BAEBNQAECoEcAAQGAAkKex5CCwD0AgmODQAAAwBhAHUNAAAEAFoAfw0AAAQAUwCpDQAABABYAFwNAAAEAFEAXQ0AAAMARQBlDQAABABJAKQNAAABADUAMw0AAAEAQQAGAAkKex5CCwD0AgmODQAAAwBhAHUNAAADAFoAfw0AAAMAUwCpDQAAAwBYAFwNAAADAFEAXQ0AAAIARQBlDQAAAwBJAKQNAAABADUAMw0AAAEAQQADAAQK5w9ldQACAQR1DQAAAQAoAH8NAAABAC0AXQ0AAAEALwBlDQAAAQAeAAcAAgocIEEQAL0AAqkNAAABAF8AXA0AAAEARQABNQAFFAcIGAAIAEEgAA==.',
Th='Thecheatt:BAEBNQAECoEZAAMTAAgKfR9RBgAgAgiODQAABABcAHUNAAAEAGAAfw0AAAQAZACpDQAABQBcAFwNAAABADsAXQ0AAAEAKwBlDQAABABHADMNAAACAFgAEwAICt0aUQYAIAIIjg0AAAEAMgB1DQAAAQBMAH8NAAABAGQAqQ0AAAIAPABcDQAAAQA7AF0NAAABACsAZQ0AAAMARwAzDQAAAgBYABQABQpiITkMAOEBBY4NAAADAFwAdQ0AAAMAYAB/DQAAAwBhAKkNAAADAFwAZQ0AAAEALwAAAA==.Therelore:BAEANQAECgYJEAAAAA==.Thoughtbott:BAEANQAECgMIBgABNQAECgYIBgACAAAAAA==.',
Tr='Troysrus:BAEANQABCgcIEwABNQAECgcJCgACAAAAAA==.Troystory:BAEANQAECgMJAwABNQAECgcJCgACAAAAAA==.',
Ty='Tyära:BAEANQAECgEJAQABNQAECggIGwAOAIQaAA==.',
Ur='Urlathor:BAEANQAECgIJAgAAAA==.',
Vi='Vilexie:BAEANQAECgcJCgAAAA==.',
Wa='Wafflé:BAEANQAECgcJDAAAAA==.',
Za='Zanea:BAEANQAECgEIAQABNQAECgUJCgACAAAAAA==.',
Zi='Zinia:BAEANQAECgUJCgAAAA==.',
Zu='Zubbrael:BAEBNQAECoEeAAQGAAgKvxoKEACeAgiODQAABQBbAHUNAAAGAFkAfw0AAAQAYQCpDQAABQBAAFwNAAAEAD8AXQ0AAAIARQBlDQAAAQAvADMNAAADABkABgAICr8aChAAngIIjg0AAAQAWwB1DQAABABZAH8NAAADAGEAqQ0AAAQAQABcDQAAAQA/AF0NAAACAEUAZQ0AAAEALwAzDQAAAQAZAAMABgo6DB1nADoBBo4NAAABAAUAdQ0AAAIAFAB/DQAAAQAyAKkNAAABACgAXA0AAAMAKQAzDQAAAQAcAAcAAQrSDpYaADwAATMNAAABACUAAAA=.Zubbzdh:BAEANQAECgcIBwABNQAECggIHgAGAL8aAA==.',
Zz='Zzertz:BAECNQAFFIEHAAMGAAMK0hnMBgAEAQOODQAABABaAKkNAAACAFAAMw0AAAEAGwAGAAMK0hnMBgAEAQOODQAAAwBaAKkNAAACAFAAMw0AAAEAGwADAAEK1wUVHwBHAAGODQAAAQAOADUABAqBHwADBgAJCoMkvAEAvAMABgAJCoMkvAEAvAMAAwABCu0MS6cAPgAAAAA=.Zzerz:BAEANQAECgcIDQABNQAFFAMIBwAGANIZAA==.',
['Àb']='Àbel:BAEANQAECgQJCQAAAA==.',
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
