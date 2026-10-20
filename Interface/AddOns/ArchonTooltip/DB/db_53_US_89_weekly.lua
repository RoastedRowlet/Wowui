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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Hunter-BeastMastery','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','Druid-Guardian','DeathKnight-Blood','Hunter-Marksmanship','Shaman-Elemental','Shaman-Enhancement','Druid-Balance','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Shadow','Paladin-Holy','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Monk-Windwalker','DeathKnight-Frost','DeathKnight-Unholy','Priest-Holy','Mage-Arcane','Monk-Brewmaster','Warrior-Arms','Mage-Frost','Priest-Discipline','DemonHunter-Vengeance','Warrior-Fury','Mage-Fire','Rogue-Outlaw','Druid-Feral',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abysseus:BAAANQADCgcIDwAAAA==.',
Ad='Admired:BAAANQAECgEIAgABNQAECgQICQABAAAAAA==.',
Ae='Aerdrie:BAAANQABCgMIAwAAAA==.Aevelin:BAABNQAECn8WAAICAAoKSQ4RngDmAQACAAoKSQ4RngDmAQAAAA==.',
Aj='Ajagar:BAAANQAECgIIAgABNQAECgcIEAABAAAAAA==.',
Al='Alamora:BAAANQAECgUIBwAAAA==.Alastair:BAAANQAECggIAgAAAA==.Alathena:BAAANQAECgMIAwAAAA==.Alexandrya:BAABNQAECn8oAAIDAAkKaQsigwAGAgADAAkKaQsigwAGAgAAAA==.Alickdh:BAAANQADCgIIAgABNQAFFAEIAQABAAAAAA==.Almostpanda:BAAANQADCgUIBQABNQAECgoKHgAEAOQNAA==.Altery:BAAANQAECgEIAQAAAA==.',
Am='Ampharos:BAAANQABCgYIBgAAAA==.Amsahunter:BAAANQADCggICAABNQAECgYIDQABAAAAAA==.Amsroeb:BAAANQAECgYIDQAAAA==.',
An='Anelavenger:BAACNQAFFH8VAAIFAAYKHhedAQBCAQAFAAYKHhedAQBCAQA1AAQKf0gAAwUACgo/I+gAAK4DAAUACgo/I+gAAK4DAAYABgppDEEjACwBAAAA.Anelblast:BAAANQAECgUIDAABNQAFFAYIFQAFAB4XAA==.Angerwina:BAAANQAECgMIBQAAAA==.Annain:BAAANQADCgYJCgAAAA==.',
Ar='Arathor:BAAANQADCggIEQAAAA==.Ardent:BAAANQAECgUICwAAAA==.Ardor:BAAANQADCgYICgABNQAECgUICwABAAAAAA==.Arent:BAABNQAECn8pAAMHAAkKGxL0IAAiAgAHAAkKGxL0IAAiAgAIAAYKbQb3FQDUAAAAAA==.Arkanna:BAAANQADCgYIBgAAAA==.Artemislives:BAAANQAECggICAAAAA==.',
As='Asharia:BAAANQAECgYICQAAAA==.Ashla:BAAANQADCgIIAgAAAA==.Asilan:BAAANQABCgEIAQAAAA==.Assateague:BAAANQAECgQIBwAAAA==.Astelossa:BAAANQADCgcIIwAAAA==.',
['Aë']='Aëro:BAAANQADCgYICQAAAA==.',
Ba='Bahnna:BAAANQADCgUICAAAAA==.Bananapistol:BAAANQABCgIIBAAAAA==.Barracksbuny:BAAANQAECgYIDQABNQAECgkJFAAJAKATAA==.Barrathfrogy:BAAANQADCgUIDAAAAA==.',
Be='Bebheishel:BAAANQADCgQICwAAAA==.Beefcake:BAAANQADCgYJFQABNQAECgIIAgABAAAAAA==.Bertello:BAAANQAECgQIBAAAAA==.Beserol:BAAANQAECgQIBgAAAA==.',
Bi='Biest:BAAANQAECggIAQAAAA==.Biggs:BAAANQADCggICQABNQAECggIBgABAAAAAA==.Billy:BAAANQAECgcIEQAAAA==.Bilywitchdoc:BAAANQAECgIIBAABNQAECggIIwAKAIQgAA==.Bionicle:BAAANQADCgQIBAAAAA==.Biscuít:BAAANQAECgUICwAAAA==.',
Bk='Bk:BAAANQADCgcIDQABNQAECgoKJAALAE8ZAA==.',
Bl='Blasuoff:BAAANQADCgYIBgAAAA==.Bloodyfate:BAAANQADCgYIBgAAAA==.Bluechalk:BAAANQAECgcIEAABNQAFFAcIGgAMAEgjAA==.',
Bo='Boomslap:BAAANQAECggICQAAAA==.Borzoi:BAABNQAECn8/AAICAAkKryJLCABeAgACAAkKryJLCABeAgAAAA==.',
Br='Brawne:BAAANQADCgUIBQAAAA==.',
Bu='Buzzdruu:BAABNQAECn8cAAMNAAoK9xjQLgBoAgANAAkK8BjQLgBoAgAIAAEKJRkTLwBVAAAAAA==.',
['Bó']='Bóg:BAAANQADCgEIAQAAAA==.',
['Bø']='Bønës:BAAANQADCgQIBAAAAA==.',
Ca='Caaniss:BAAANQABCgQIBAAAAA==.Caduceus:BAAANQADCgUIBQAAAA==.Caesus:BAAANQADCgcICwAAAA==.Cagedancer:BAAANQADCgUICQAAAA==.Callio:BAABNQAECn8mAAIDAAkKcgrBigD1AQADAAkKcgrBigD1AQAAAA==.Canus:BAAANQAECgQIBAAAAA==.Caprisunsipz:BAAANQAECggICAAAAA==.Caritta:BAABNQAECn8UAAMOAAcK/hSpPgBVAQAOAAYKSRCpPgBVAQAPAAMKqxaubADGAAAAAA==.Cathillex:BAAANQAECgYICwAAAA==.Caycay:BAACNQAFFH8KAAIPAAUKaxnPCgB2AQAPAAUKaxnPCgB2AQA1AAQKfzkAAg8ACQrWJIECAM4DAA8ACQrWJIECAM4DAAAA.',
Ce='Celestian:BAAANQAECggIBwAAAA==.Cels:BAAANQAECgcIBwAAAA==.',
Ch='Chillbros:BAABNQAECn8dAAMLAAkKtySFGgAqAwALAAgKaiWFGgAqAwAMAAgKexuiFQAOAgAAAA==.Churd:BAACNQAFFH8GAAIQAAIK8QtHFQB2AAAQAAIK8QtHFQB2AAA1AAQKfygAAhAACgpfFEMMADkBABAACgpfFEMMADkBAAAA.Chypnotic:BAABNQAECn8qAAIDAAkKXxkARQCdAgADAAkKXxkARQCdAgAAAA==.Chypotle:BAAANQADCgYJBgAAAA==.Chypster:BAAANQADCgYIBgAAAA==.',
Ci='Ciceroe:BAAANQAECgcIBwAAAA==.',
Cl='Cleft:BAABNQAECn8mAAMCAAcK3AeM7QBBAQACAAcK3AeM7QBBAQARAAcK4wgJUwC3AAAAAA==.Clevelandk:BAAANQADCgQIBAAAAA==.Clowwnshoes:BAAANQAECgQICgAAAA==.',
Co='Coalystra:BAABNQAECn8uAAIOAAkKIR2kEQDgAgAOAAkKIR2kEQDgAgAAAA==.Cocopuffs:BAAANQAECgYIDAAAAA==.Colostrom:BAABNQAECn8wAAISAAkK5SMDBgBMAwASAAkK5SMDBgBMAwAAAA==.Coramage:BAAANQAECgYICQAAAA==.Corliss:BAAANQAECgEIAQAAAA==.Cornholeo:BAAANQABCgIIBAAAAA==.Corruptdata:BAABNQAECn8kAAQTAAgKfBT5YAA1AgATAAgKfBT5YAA1AgAUAAEKBBRXFQA7AAAVAAEKjQhnMgAwAAABNQAFFAUIFgACAGQRAA==.',
Cp='Cpair:BAAANQADCggICAAAAA==.Cplusmc:BAAANQADCgQIBQAAAA==.',
Da='Darkbeast:BAAANQAECggIEgAAAA==.Darthorc:BAAANQAECgIIAgAAAA==.Daten:BAABNQAECn8uAAICAAoKqgzjKACFAQACAAoKqgzjKACFAQAAAA==.Dazshauran:BAAANQADCgUICwAAAA==.',
De='Deadzexcs:BAAANQAECgQIBwAAAA==.Decayed:BAABNQAECn8UAAIJAAkKoBNLTADFAQAJAAkKoBNLTADFAQAAAA==.Deladoria:BAAANQAECgYICgAAAA==.Deragor:BAAANQADCgMIAwABNQAECgMIAwABAAAAAA==.',
Di='Diagonalli:BAAANQAECgUIDgAAAA==.Dirk:BAAANQAECgIIBAABNQAECggIGwAJANcCAA==.Dirkdìggler:BAAANQADCgUIBwAAAA==.Divirian:BAAANQAECgQIAwAAAA==.',
Dj='Djdaemon:BAAANQADCggIFgAAAA==.Djdrakshadow:BAAANQADCgUIFQAAAA==.Djdruidshadw:BAAANQADCgYIHAAAAA==.Djpaly:BAAANQADCgUIGwAAAA==.Djpriest:BAAANQAECgQIAwAAAA==.Djshadow:BAAANQADCgYIJAAAAA==.Djshadowar:BAAANQADCgYIHgAAAA==.Djshadowlock:BAAANQADCgYIGwAAAA==.Djshadowlok:BAAANQAECgIIAQAAAA==.Djshadowrog:BAAANQAECgEIAQAAAA==.Djshadruid:BAAANQADCgYIEwAAAA==.Djshamy:BAAANQAECgIIAgAAAA==.Djshaolin:BAAANQAECgEIAQAAAA==.Djzhadow:BAAANQAECgEIAQAAAA==.Djzhadruid:BAAANQAECgEIAQAAAA==.',
Dk='Dkshadow:BAAANQAECgIIAQAAAA==.',
Dr='Dragonchalk:BAAANQADCgYIBgABNQAFFAcIGgAMAEgjAA==.Drakhadir:BAAANQAECgMIAgAAAA==.Drakmon:BAAANQADCggIDgAAAA==.Draktând:BAABNQAECn8lAAMWAAgKHRdMFwAkAgAWAAgKHRdMFwAkAgAXAAEK5gXjpQAwAAAAAA==.Dreve:BAAANQABCgIIBAAAAA==.Driftier:BAAANQAECgEIAQAAAA==.Drogon:BAEANQAECggIDgABNQAECgoKKQAYAIQiAA==.Drunkenpanda:BAABNQAECn8eAAMEAAoK5A3bHgCdAQAEAAoK5A3bHgCdAQAZAAEKAADhewAXAAAAAA==.',
Du='Duneshadow:BAAANQADCgUICQAAAA==.',
Ec='Echö:BAEBNQAECn8uAAIPAAkKtg6HOQDnAQAPAAkKtg6HOQDnAQAAAA==.',
Ei='Eirø:BAAANQAECgUICAABNQAFFAUICgAKACQWAA==.',
El='Elberon:BAAANQAECgIIAgABNQAECgMIBQABAAAAAA==.Elnax:BAAANQADCgYIBgAAAA==.Elöhim:BAAANQAECggIBgAAAA==.',
En='Enæmberclad:BAAANQAECgQIBAAAAA==.',
Ep='Epic:BAAANQADCgYICQAAAA==.',
Eq='Eqo:BAAANQAECgUIBQAAAA==.',
Er='Erebosa:BAAANQABCgQIBAAAAA==.',
Fa='Fallden:BAAANQAECgMIAwABNQAECgoKJQAQAEoWAA==.Fatherchill:BAABNQAECn8dAAISAAgKhRdSIQDZAQASAAgKhRdSIQDZAQAAAA==.Fathermoses:BAAANQAECgUIBQAAAA==.',
Fi='Fitco:BAAANQAECgQIBQAAAA==.',
Fl='Flokii:BAAANQADCgEIAQAAAA==.',
Fr='Frantecks:BAAANQAECgYIBgAAAA==.Freela:BAEANQADCgUIBQABNQAECggIHAADACgdAA==.Frost:BAAANQAECgIJAgABNQAFFAcIFQAaAPMUAA==.Frostmon:BAABNQAECn8yAAIbAAoKDB1fGgDuAgAbAAoKDB1fGgDuAgAAAA==.Frostyaf:BAAANQADCgIIAgAAAA==.',
Fu='Furbee:BAAANQAECggIBgAAAA==.',
Ga='Galeandra:BAAANQAECgYICwAAAA==.Gambas:BAAANQAECgQIAwAAAA==.Garim:BAABNQAECn8cAAIMAAgKbw4lGgDBAQAMAAgKbw4lGgDBAQAAAA==.Gaztingo:BAABNQAECn8gAAMcAAkKGQxsegCrAQAcAAkKGQxsegCrAQAQAAIKcAK2dAA9AAAAAA==.',
Gh='Ghostbanri:BAAANQABCgcICAAAAA==.',
Gi='Gildor:BAAANQAECgEIAQAAAA==.Giox:BAAANQADCgMIAwAAAA==.Girthshock:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.',
Gn='Gnar:BAAANQADCgcICAAAAA==.',
Go='Gobi:BAABNQAECn8cAAIdAAoKnxpKKwBuAQAdAAoKnxpKKwBuAQAAAA==.Gowtherpunch:BAABNQAECn8xAAIeAAkK0A5wFACcAQAeAAkK0A5wFACcAQAAAA==.',
Gr='Gravewynd:BAAANQADCggIDwAAAA==.Grimsy:BAABNQAECn8cAAIfAAoKhxS/LwBOAQAfAAoKhxS/LwBOAQAAAA==.Grogg:BAAANQADCgQIBAAAAA==.Gruxxiron:BAAANQAECgQIBgABNQAECgoKJQAJAOcRAA==.',
Gu='Gulnn:BAABNQAECn8fAAQTAAkKnBdVfwDoAQATAAcKGRhVfwDoAQAUAAIKYxYUCwBzAAAVAAEKAAA4MAA1AAAAAA==.Gumby:BAAANQABCgQIBAAAAA==.',
Ha='Haelena:BAAANQAECgIIAgAAAA==.Hage:BAAANQADCggIAQAAAA==.Harmossy:BAAANQAECgUJDgAAAA==.',
He='Heartsfang:BAAANQADCgMIBAAAAA==.Heriotza:BAAANQAECgcIEAAAAA==.',
Ho='Hogmaine:BAAANQADCgUICQAAAA==.Holypaladin:BAABNQAECn8gAAITAAcK+BkmhwDUAQATAAcK+BkmhwDUAQAAAA==.',
Ib='Ibrakeforimp:BAAANQAECggIAQAAAA==.',
Ii='Iimit:BAAANQAECgUIDQABNQAECgoKGwAgACwdAA==.',
Il='Illidead:BAACNQAFFH8dAAMdAAcKTiLFBQBnAgAdAAYK0iPFBQBnAgAgAAEKQRx8BABkAAA1AAQKfywAAx0ACgoZJVkqADwDAB0ACQoeJVkqADwDACAAAQr6JK89AEoAAAAA.Illooj:BAACNQAFFH8MAAIcAAQKhyQ3DgCrAQAcAAQKhyQ3DgCrAQA1AAQKfyoAAyEACgpdJlwBAEQDABwACQpXJR0PAE0DACEACAq+JVwBAEQDAAAA.',
In='Indexes:BAAANQAECgUIBwAAAA==.Inspiration:BAAANQADCgQICwAAAA==.',
Is='Ist:BAABNQAECn8nAAIiAAoKBxDLDQDhAQAiAAoKBxDLDQDhAQAAAA==.',
It='Itchigo:BAAANQAECgQIBQAAAA==.Itskamertime:BAAANQAECgIIAQABNQAECgkJMgANACkdAA==.',
Iv='Ivgorod:BAAANQAECgYIDwAAAA==.',
Ja='Jabbadahut:BAAANQAECggIBgAAAA==.Jarhead:BAAANQAECgUIDgAAAA==.Jaxtoy:BAAANQADCgYIBgAAAA==.Jaybas:BAAANQABCgIIAgAAAA==.Jazilyne:BAAANQADCgMIAwAAAA==.Jaziriel:BAAANQADCgYIBgAAAA==.',
Je='Jenka:BAAANQAECgMIAwAAAA==.',
Jo='Joleya:BAAANQADCgYICwAAAA==.',
Ju='Judihopps:BAAANQAECgIIAwAAAA==.Justcalmdown:BAAANQAECgYIDgABNQAECgIIAgABAAAAAA==.Justyra:BAAANQAECgQICAABNQAECggIGwAOAE8cAA==.',
Ka='Kalder:BAAANQADCgIJAgABNQAECgUICAABAAAAAA==.Kalloo:BAAANQAECgYIBgABNQAFFAQIDAAcAIckAA==.Kambative:BAABNQAECn8yAAMNAAkKKR17JACtAgANAAgKTB17JACtAgAHAAUKmBXPRQABAQAAAA==.Kambustable:BAAANQADCggICwABNQAECgkJMgANACkdAA==.Kammunion:BAAANQAECgYIBQABNQAECgkJMgANACkdAA==.Kamphiyer:BAAANQADCgMIBAABNQAECgkJMgANACkdAA==.Kamscendance:BAAANQADCggICgABNQAECgkJMgANACkdAA==.Kanan:BAAANQADCggIFQAAAA==.Kandosii:BAAANQABCgIIAgAAAA==.Kantheal:BAAANQAECgYIEAAAAA==.',
Ke='Keirmania:BAAANQADCgYIBgAAAA==.',
Ki='Kiagas:BAABNQAECn8cAAMjAAoK5gs9GAAcAQAfAAoKXwurmQDcAQAjAAYKvwk9GAAcAQABNQADCgIIAgABAAAAAA==.Kimbrawly:BAAANQADCgYIBgAAAA==.',
Kr='Kravex:BAABNQAECn8nAAINAAkKwRA+CQCmAQANAAkKwRA+CQCmAQAAAA==.Kreynar:BAAANQAECgQJBAABNQAECgkJJwANAMEQAA==.Krrayt:BAAANQAECgQICQAAAA==.',
Ku='Kukoc:BAAANQAECgcIEgAAAA==.',
Ky='Kylana:BAAANQADCgYICwABNQAECgkJIwAHAIgSAA==.Kyriel:BAABNQAECn8mAAIYAAkKcRlKJQBPAQAYAAkKcRlKJQBPAQAAAA==.',
['Ké']='Kélly:BAAANQAECggICAAAAA==.',
La='Laayna:BAAANQAECgQICwAAAA==.Lanta:BAAANQAECgcIEAAAAA==.Larayvia:BAABNQAECn8hAAIDAAoK4AekkADoAQADAAoK4AekkADoAQAAAA==.',
Le='Leesala:BAABNQAECn8hAAIYAAkKZxaPVAAVAgAYAAkKZxaPVAAVAgAAAA==.Leiman:BAAANQAECgQIDAAAAA==.Leymonte:BAAANQADCgMIAwAAAA==.',
Lg='Lg:BAABNQAECn8nAAMXAAkKFiDvCgAyAwAXAAkK1x7vCgAyAwAWAAEKdRZlRwBJAAABNQAECgIIAgABAAAAAA==.',
Li='Lic:BAABNQAECn8cAAIDAAcK7g4dTAAbAQADAAcK7g4dTAAbAQAAAA==.Lilbitty:BAAANQADCgEIAQAAAA==.Lilililil:BAABNQAECn8kAAMLAAoKTxlsBAA4AgALAAoKTxlsBAA4AgAYAAEKqwyUIAEuAAAAAA==.Lillabet:BAAANQAECgQIBAAAAA==.Limpydk:BAAANQADCgUIBQABNQAECgcIEAABAAAAAA==.Limpylock:BAAANQAECgYIDQABNQAECgcIEAABAAAAAA==.Limpypal:BAAANQAECgcIEAAAAA==.Lispeth:BAABNQAECn8UAAQOAAcKaAk6QgA9AQAOAAcKaAk6QgA9AQAPAAEKAADZmwAnAAAiAAIKoAT2NwAfAAAAAA==.',
Lo='Lockém:BAAANQABCgYIBwAAAA==.Longtrang:BAAANQADCgMIAwAAAA==.Loriander:BAAANQADCgQIBAAAAA==.',
Lu='Luckyleaf:BAAANQADCggIGgAAAA==.Lunaaris:BAAANQAECggICQAAAA==.',
Ma='Macallan:BAAANQAECgMIAwAAAA==.Magifur:BAABNQAECn8cAAIdAAgKABITzADuAQAdAAgKABITzADuAQAAAA==.Magnakilro:BAABNQAECn8kAAIDAAcKLRW/LQBoAQADAAcKLRW/LQBoAQAAAA==.Magnomar:BAAANQADCgcIDQAAAA==.Maisy:BAAANQADCgUIBwAAAA==.Malditto:BAAANQADCgIIAgAAAA==.Maleficus:BAAANQAECgUICAAAAA==.Mamoswine:BAAANQABCgcICgAAAA==.Mareki:BAAANQADCggIDQAAAA==.Markdfordeth:BAAANQADCgcIBwAAAA==.Mattyfu:BAAANQAECgYIDQAAAA==.Maxrogue:BAAANQADCgUIBQABNQAECggIIgAIAEgMAA==.Mazikeen:BAAANQAECgcIDgAAAA==.',
Me='Meatsupreme:BAACNQAFFH8FAAICAAEKTgwvGQA/AAACAAEKTgwvGQA/AAA1AAQKfyQAAgIACgq9Eu+kANcBAAIACgq9Eu+kANcBAAAA.Meepin:BAABNQAECn8qAAQRAAoKTh7OOgB5AgARAAkKlB3OOgB5AgACAAgKBRNsoQDeAQASAAMKLwxVWQB4AAAAAA==.Merdoc:BAAANQAECgQIBwAAAA==.Mesophistole:BAAANQADCgQICgABNQAECgUIBwABAAAAAA==.Mesopunchy:BAAANQAECgUIBwAAAA==.Mesopyro:BAAANQADCgMIBgABNQAECgUIBwABAAAAAA==.',
Mi='Miamore:BAAANQADCggICAAAAA==.Microchyp:BAAANQADCgEIAQAAAA==.Milemarker:BAABNQAECn8VAAIRAAgK2QZIiwB6AQARAAgK2QZIiwB6AQAAAA==.Mindstorm:BAAANQADCggICAAAAA==.Misstwizted:BAABNQAECn8XAAMTAAcKfwTK1wAaAQATAAcKfgTK1wAaAQAVAAIK5AEZKwBBAAAAAA==.',
Mo='Mohinu:BAAANQAECgcIDAAAAA==.Mojodaemon:BAAANQADCgUIBQAAAA==.Moocowmoo:BAAANQADCggIDgABNQAECggIIAATAPgZAA==.Moondevil:BAAANQADCgUICwAAAA==.Morta:BAEBNQAECn8cAAIDAAgKKB1+EwDVAQADAAgKKB1+EwDVAQAAAA==.Mortkavaliro:BAAANQADCgYIBgABNQAECgcIEAABAAAAAA==.',
Mu='Mugzy:BAAANQAECggIAgAAAA==.Muted:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
['Mö']='Mörph:BAAANQAECgMIAwABNQAECgkJHAARAEobAA==.',
Na='Nanérs:BAAANQAECgUIBgABNQAFFAYIEQANAGgcAA==.Narrodus:BAAANQAECgUICQAAAA==.Nasht:BAAANQADCggICQAAAA==.Nasun:BAAANQADCgQIBAAAAA==.Nataku:BAAANQAECgYIDwAAAA==.',
Ne='Neelix:BAAANQAECgEIAQAAAA==.Nezzick:BAABNQAECn8pAAMLAAkKcxmjOwCHAgALAAkKcxmjOwCHAgAYAAgK2wgplgBQAQAAAA==.',
Ni='Nicholasrage:BAAANQABCgQIBAAAAA==.Nidalap:BAAANQADCgEIAQAAAA==.Nightreaper:BAAANQADCggINwAAAA==.Nightsinger:BAAANQABCgIIAgAAAA==.Nimbus:BAACNQAFFH8aAAMLAAcKPBccAwB6AgALAAcKPBccAwB6AgAYAAEKXgHEKwBGAAA1AAQKf6cAAgsACgqRJfkAAPkDAAsACgqRJfkAAPkDAAAA.',
No='Nomns:BAAANQAECgUICwABNQAECgcIHwAIAI0kAA==.Normel:BAAANQAECgEIAQAAAA==.Noz:BAAANQAECgIIBAABNQAECggIGwACACwfAA==.',
Nr='Nrvous:BAAANQADCgIIAgAAAA==.',
Nu='Nuid:BAAANQAECggIAQAAAA==.Numbers:BAAANQAECgcICgAAAA==.',
Ny='Nytesage:BAACNQAFFH8QAAIkAAUKfyUuAACsAQAkAAUKfyUuAACsAQA1AAQKfycAAiQACQqKJikAANoDACQACQqKJikAANoDAAAA.',
['Nä']='Näners:BAAANQAECgIIAQABNQAFFAYIEQANAGgcAA==.',
['Në']='Nëvërmind:BAABNQAECn8tAAISAAkKOxs8AwD3AQASAAkKOxs8AwD3AQAAAA==.',
['Nì']='Nìghtcat:BAAANQAECgQIBwAAAA==.',
Or='Orgrom:BAAANQAECggICAAAAA==.',
Oz='Ozgar:BAAANQAECgIICQAAAA==.Ozo:BAAANQADCgIIAgAAAA==.',
Pa='Painavolian:BAABNQAECn85AAIdAAoKsxyQMQAoAwAdAAoKsxyQMQAoAwAAAA==.Palcris:BAAANQADCgcIBwAAAA==.Paxren:BAAANQABCgIIAgAAAA==.',
Pe='Peeches:BAAANQAECgYIBQAAAA==.Pelonis:BAAANQADCgQIBgAAAA==.',
Ph='Pheayre:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Phoenixdówn:BAABNQAECn8bAAIYAAcKcCLaLwCiAgAYAAcKcCLaLwCiAgAAAA==.Phoosa:BAAANQADCgEIAQAAAA==.',
Pi='Pingpong:BAABNQAECn8jAAQZAAgK4RtuIAAqAgAZAAgK4RtuIAAqAgAeAAQKEQKiDwBpAAAEAAEKBQOtVAAgAAAAAA==.Pisspadpanda:BAABNQAECn8tAAMTAAkKdhstJABeAQATAAkKxhotJABeAQAVAAQKWBXBEwAPAQAAAA==.',
Pl='Plungsnipes:BAAANQADCggIFAABNQAECggICQABAAAAAA==.',
Po='Poggies:BAACNQAFFH8OAAMkAAYKlSI5AACCAQAdAAUK7SJpFgDEAQAkAAQKvhs5AACCAQA1AAQKfxoAAyQACQqdJVABAMECAB0ACQqOJIQyACYDACQACAojI1ABAMECAAAA.Potatodh:BAAANQAECgEIAgAAAA==.Potatolock:BAAANQAECggICwAAAA==.',
Pr='Praynes:BAABNQAECn8uAAIcAAkKHBwMPwBuAgAcAAkKHBwMPwBuAgAAAA==.',
Pu='Pupperputh:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Puppet:BAAANQADCgEIAQAAAA==.',
Py='Pylanora:BAAANQADCgMIAwAAAA==.',
Qu='Quinnx:BAAANQADCgMJAQAAAA==.',
Ra='Rach:BAABNQAECn8gAAIDAAoKIxXFPQA8AQADAAoKIxXFPQA8AQAAAA==.Rael:BAAANQADCgIJAgAAAA==.Ranoe:BAAANQAECgIIAwABNQAECgoKGwAgACwdAA==.Rathalos:BAAANQABCgIIAgAAAA==.Raxity:BAABNQAECn8VAAIcAAcKUx2rJQBoAQAcAAcKUx2rJQBoAQAAAA==.Razji:BAABNQAECn8jAAMKAAgKhCCAGgCBAgAKAAcK9iGAGgCBAgADAAQK8hu68wAaAQAAAA==.',
Re='Redmg:BAAANQADCgUIDQABNQAECgMIAwABAAAAAA==.Renfro:BAAANQADCgMIAwAAAA==.',
Ri='Riete:BAABNQAECn8fAAIVAAgKLg+PAgBVAQAVAAgKLg+PAgBVAQAAAA==.Rinoa:BAAANQAECgQIEAAAAA==.',
Ro='Rochallie:BAAANQAECgMIBwAAAA==.Rockii:BAAANQADCgYIBgAAAA==.Rocknwolf:BAAANQAECgYICgAAAA==.Rokd:BAABNQAECn8jAAISAAkKHyHwCAAOAwASAAkKHyHwCAAOAwAAAA==.Rosalee:BAEANQABCgIIAgABNQAECgYIDAABAAAAAA==.Roscoelock:BAABNQAECn8VAAMUAAYKrRh1IABtAQAUAAUK4Rt1IABtAQATAAQKPgzV9gDdAAAAAA==.Roxxann:BAAANQADCgYIBgAAAA==.',
Ru='Ruibaron:BAAANQAECgEIAQAAAA==.Rumur:BAAANQADCgYIBgABNQAECgcIFwAbANUOAA==.',
['Rà']='Ràidèn:BAAANQADCgcIBwABNQAECgkJLAAYAEAfAA==.',
['Rá']='Ráyne:BAAANQAECgEIAQAAAA==.',
Sa='Sadeel:BAABNQAECn8wAAMVAAkK4xSHBwAjAgAVAAkKnBOHBwAjAgATAAcKlAxtsgBrAQAAAA==.Sadewolf:BAABNQAECn8fAAMOAAoKtx33FAC+AgAOAAgKTyP3FAC+AgAPAAQKHxLSHgAEAQAAAA==.Salvadore:BAAANQADCggICAAAAA==.Samentoni:BAACNQAFFH8GAAIRAAIKzRATIwCAAAARAAIKzRATIwCAAAA1AAQKfygAAhEACgrTFrJAAGICABEACgrTFrJAAGICAAAA.Samgal:BAAANQAECgYICwAAAA==.Sampsyn:BAAANQABCgYICgAAAA==.Sanctalux:BAAANQADCgQIBgAAAA==.Sasha:BAAANQAECgMICAAAAA==.Satyra:BAABNQAECn8bAAIOAAgKTxzjHwBPAgAOAAgKTxzjHwBPAgAAAA==.Saurphang:BAACNQAFFH8LAAMbAAUKqBFdBQCZAAAbAAQKqBFdBQCZAAAJAAEKAABvPgAWAAA1AAQKfzQAAhsACgoUIVUPADwDABsACgoUIVUPADwDAAAA.',
Sc='Scamanes:BAAANQAECgYIDAAAAA==.',
Se='Semperfi:BAAANQABCgYICQAAAA==.Severis:BAAANQADCgEIAQAAAA==.',
Sh='Shadora:BAAANQAECgYICgAAAA==.Shadowwizard:BAABNQAECn88AAIUAAgKvg4+EgDjAQAUAAgKvg4+EgDjAQAAAA==.Shadybrat:BAAANQADCggIFwABNQAECgkJKAADAGkLAA==.Shaladin:BAAANQAECggIEAAAAA==.Shidan:BAABNQAECn8sAAIYAAkKQB83HAD9AgAYAAkKQB83HAD9AgAAAA==.Shmeepin:BAAANQAECgIIAgAAAA==.Shockaho:BAAANQAECgUIBwAAAA==.Shockchalk:BAACNQAFFH8aAAIMAAcKSCMyAADNAgAMAAcKSCMyAADNAgA1AAQKfzMAAgwACgq6Jn4AAN8DAAwACgq6Jn4AAN8DAAAA.Shocknorris:BAAANQAECgIIBAABNQAECgQIBQABAAAAAA==.Shrooclaw:BAAANQADCgIIAgAAAA==.Shulk:BAABNQAECn8UAAICAAgK9QsUvwCeAQACAAgK9QsUvwCeAQAAAA==.',
Si='Sibbiah:BAEANQAECgYIDAAAAQ==.Silanre:BAAANQAECgUIDQAAAA==.',
Sk='Skaðï:BAACNQAFFH8KAAIKAAUKJBZsDQBnAQAKAAUKJBZsDQBnAQA1AAQKfzUAAwoACgp8HY8ZAIoCAAoACgp8HY8ZAIoCAAMAAgrQAI9AAWEAAAAA.',
Sl='Slizzard:BAAANQADCgIIAgABNQAFFAUIDQAbAM0VAA==.',
Sm='Smalldrogø:BAAANQADCggICAAAAA==.',
Sp='Spadesrage:BAAANQAECgYIEQAAAA==.Spadestree:BAAANQADCgYICgAAAA==.Spash:BAAANQADCggIDgAAAA==.Spicyycurryy:BAABNQAECn8jAAIfAAgKPBlbNgA8AQAfAAgKPBlbNgA8AQAAAA==.',
St='Staticshock:BAAANQADCgUICAABNQAECggICQABAAAAAA==.Strahm:BAABNQAECn8iAAIIAAgKSAx2FQDYAAAIAAgKSAx2FQDYAAAAAA==.Strehm:BAAANQADCgYIDAABNQAECggIIgAIAEgMAA==.Stryhm:BAAANQADCgQIBwABNQAECggIIgAIAEgMAA==.',
Su='Sulfass:BAAANQABCgIIAgAAAA==.Surai:BAABNQAECn8bAAIYAAkK2yB2DwBIAwAYAAkK2yB2DwBIAwABNQAFFAQIBgAWAMoMAA==.',
Sy='Sylryn:BAAANQADCgQIBAAAAA==.Sylvexa:BAAANQAECgMIAwAAAA==.Symple:BAAANQAECgEIAgAAAA==.Syns:BAAANQADCggIFAAAAA==.Synz:BAAANQAECgIIAgAAAA==.Syssare:BAABNQAECn8UAAIPAAcKrx0zMAAmAgAPAAcKrx0zMAAmAgAAAA==.',
Ta='Tacpally:BAAANQADCgYIFQAAAA==.Talamor:BAAANQADCgMJAwAAAA==.Talasam:BAAANQADCgQIBAAAAA==.Tandsonnara:BAAANQAECggIAQAAAA==.Tastetickle:BAABNQAECn8zAAIdAAoKLxmfZAC1AgAdAAoKLxmfZAC1AgAAAA==.Tazdrin:BAABNQAECn8wAAIlAAkKSxUlCAAiAgAlAAkKSxUlCAAiAgAAAA==.',
Te='Telidrus:BAACNQAFFH8GAAMgAAMK2REvCQCMAAAdAAMKlg9AOwDXAAAgAAIKxg8vCQCMAAA1AAQKfyQABCAACQqpIC8MAPkBAB0ACAp6HdCaAEsCACAABwpBHi8MAPkBACQAAgroDlMJAHUAAAAA.Teneturadvys:BAAANQADCgQIBAABNQAECgYIBwABAAAAAA==.Terrax:BAAANQADCgQIBAAAAA==.',
Th='Thepoacher:BAAANQAECgQIBAABNQAECgkJFAAJAKATAA==.Thicc:BAAANQABCgQIBAAAAA==.Thicchunter:BAABNQAECn8uAAIKAAoKCBxCCwAkAwAKAAoKCBxCCwAkAwAAAA==.Thiccmage:BAAANQAECggIEAAAAA==.Thiccwiggy:BAAANQADCgMIAwABNQAECgYIDQABAAAAAA==.Thuk:BAAANQAECgcICQAAAA==.Thunderbug:BAAANQADCggICAAAAA==.',
To='Topaze:BAABNQAECn8cAAMRAAkKShuzKADFAgARAAkKShuzKADFAgASAAEKAAAcdgAnAAAAAA==.Totemmonster:BAAANQABCgIIAgAAAA==.',
Tr='Trancendantx:BAAANQADCgcIBwAAAA==.Tripx:BAACNQAFFH8WAAICAAUKZBGFDACCAQACAAUKZBGFDACCAQA1AAQKfycAAgIACgpDGAhaAIkCAAIACgpDGAhaAIkCAAAA.Tripxed:BAABNQAECn85AAMNAAoKiBeaAwA2AgANAAoKiBeaAwA2AgAmAAEKWgqVQAA5AAABNQAFFAUIFgACAGQRAA==.Trishan:BAAANQAECgQIBwAAAA==.Trolk:BAAANQADCgUIBwAAAA==.Tronko:BAABNQAECn8WAAMYAAkK+xN/DQD0AQAYAAkK+xN/DQD0AQALAAEKNgOnQgEtAAAAAA==.Truthjustice:BAAANQADCggIEgAAAA==.',
Tu='Turntsnaco:BAABNQAECn88AAMWAAoKrBknEgBhAgAWAAgKZRonEgBhAgAXAAYKQBVOZQAeAQAAAA==.Turyon:BAAANQADCgEIAQAAAA==.',
Tw='Twiztedfaith:BAAANQADCgYIBgAAAA==.',
Ul='Ulhume:BAAANQADCgEJAQABNQAECgkJJwANAMEQAA==.',
Un='Unafhaen:BAAANQADCgQIBAAAAA==.Unaverse:BAAANQAECgYIBQAAAA==.',
Ur='Urp:BAAANQAECgMIBwAAAA==.',
Us='Usmc:BAAANQADCgYIBgAAAA==.Usmccpl:BAAANQADCgYICQAAAA==.',
Va='Valengarde:BAABNQAECn8VAAICAAoKqxZGjgAIAgACAAoKqxZGjgAIAgAAAA==.Valentin:BAAANQABCgIIAgAAAA==.Valhalia:BAAANQABCgIIAgAAAA==.Vanderneuker:BAAANQAECgQIBwABNQAFFAUIDQAbAM0VAA==.Vangoon:BAEBNQAECn8kAAMXAAoK6h8sCQBHAwAXAAkKJSEsCQBHAwAWAAEKShd1RwBJAAAAAA==.Vanmonk:BAAANQAECgIIAQAAAA==.Vann:BAAANQADCgQIBwAAAA==.Vannix:BAABNQAECn8vAAIQAAgKISR8CwAuAwAQAAgKISR8CwAuAwAAAA==.',
Ve='Velkanos:BAAANQADCgQIBAAAAA==.Velkhaz:BAAANQABCgYIBgAAAA==.Vereena:BAAANQAECgUIDgAAAA==.Vesstar:BAAANQABCggIFgAAAA==.',
Vi='Vigo:BAAANQAECgIIAgAAAA==.Violet:BAAANQADCgMIAwAAAA==.Virmethir:BAAANQAECgUIEAAAAA==.',
Vo='Voltaren:BAAANQAECgIJAgAAAA==.',
Wh='Whtmg:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Wi='Winterbreeze:BAAANQADCgQICgAAAA==.Wiwi:BAACNQAFFH8NAAMbAAUKzRWDEQDyAAAbAAMKfBmDEQDyAAAaAAMKaBNvFQCTAAA1AAQKfzcAAxsACgrWG7ZMAOIBABsACArtGrZMAOIBABoABwpPGTVEALEBAAAA.',
Wo='Woopie:BAAANQAECgEIAQAAAA==.',
Wu='Wukøng:BAAANQABCgIIAgAAAA==.',
Xa='Xake:BAAANQAECgUICgAAAA==.Xares:BAABNQAECn8bAAMgAAoKLB2gCABUAgAgAAkKLB2gCABUAgAdAAYKiw0kIAFWAQAAAA==.',
Xe='Xenp:BAABNQAECn84AAMSAAoKlxb5CABrAQASAAoKlxb5CABrAQACAAQKfwoOOwHBAAAAAA==.',
Xi='Xiovemm:BAAANQADCgcJBQAAAA==.',
Xu='Xuri:BAABNQAECn8ZAAIDAAkKBAxjkADoAQADAAkKBAxjkADoAQAAAA==.',
Ya='Yalda:BAAANQADCgIIAgAAAA==.',
Yd='Ydriel:BAAANQADCgUIBwAAAA==.',
['Yö']='Yöurfired:BAAANQADCgQICAAAAA==.',
Za='Zake:BAABNQAECn8wAAIDAAoK8ReiKwDrAgADAAoK8ReiKwDrAgAAAA==.Zalileina:BAAANQADCgMIAgAAAA==.Zantanna:BAAANQADCgYJEAAAAA==.Zappythile:BAABNQAECn8fAAMYAAgKNiB5KADCAgAYAAgKNiB5KADCAgALAAEKAACJQwEsAAAAAA==.Zayiro:BAAANQADCgYIDAAAAA==.',
Ze='Zealdavir:BAAANQABCgIIAgAAAA==.Zenà:BAAANQAECgEIAQAAAA==.',
Zi='Zigzagoon:BAAANQABCgYIBgAAAA==.',
Zo='Zoz:BAAANQAECgUIBwAAAA==.',
Zu='Zulfrik:BAABNQAECn8jAAMdAAkK6RVNRQAxAQAdAAkKwxJNRQAxAQAgAAIKEh2DMwBsAAAAAA==.',
Zy='Zyzy:BAAANQAECgcICQABNQAFFAcIHQAQAP8bAA==.',
['Äh']='Ählis:BAAANQAECgIIAwAAAA==.',
['ße']='ßeef:BAAANQAECgcIDQAAAA==.',
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
