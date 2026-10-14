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

local lookup = {'Shaman-Restoration','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Shaman-Elemental','Druid-Balance','Unknown-Unknown','Paladin-Holy','Evoker-Devastation','Mage-Arcane','DeathKnight-Blood','DeathKnight-Frost','Evoker-Preservation','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Monk-Windwalker','Priest-Shadow','Paladin-Protection','Warrior-Protection','DemonHunter-Devourer','Monk-Mistweaver','Priest-Holy','DeathKnight-Unholy','DemonHunter-Havoc','Druid-Guardian','Evoker-Augmentation','Warrior-Fury','Warrior-Arms','Rogue-Assassination','Shaman-Enhancement','Druid-Restoration','Druid-Feral','Rogue-Subtlety','Priest-Discipline','Hunter-Survival','DemonHunter-Vengeance','Mage-Frost','Monk-Brewmaster','Mage-Fire','Rogue-Outlaw',}
local provider = {region='US',realm='Garona',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aartoo:BAAANQABCggIDQAAAA==.',
Ac='Acherona:BAAANQABCgQIBAAAAA==.Ackreshanot:BAAANQADCgMIAwABNQAFFAMIBwABAAMiAA==.Acuminada:BAAANQADCgIIAgAAAA==.Acuna:BAAANQAECgUIDAAAAA==.',
Ad='Adison:BAAANQAECgUIBgAAAA==.',
Af='Affliction:BAABNQAECn8WAAQCAAgKmB9oEAD4AQACAAYKPhloEAD4AQADAAQKxCIFDwBcAQAEAAIKIRFHGgGKAAAAAA==.',
Ai='Airz:BAAANQAECgYIEgAAAA==.',
Ak='Akâkiôs:BAABNQAECn8eAAIFAAcKXhn8WgAOAgAFAAcKXhn8WgAOAgAAAA==.',
Al='Aladorman:BAAANQAECgYIEQAAAA==.Alamo:BAAANQAECgUIEQAAAA==.Albertlin:BAABNQAECn8WAAIGAAgKQxN3PwD7AQAGAAgKQxN3PwD7AQAAAA==.Alexinar:BAAANQAECgEIAQABNQAECgQICAAHAAAAAA==.Alinbirt:BAAANQADCggICAABNQAECgkJMwADAGEaAA==.',
Am='Amakuagsak:BAAANQAECgUIDwAAAA==.Amicus:BAAANQAECgUIDAAAAA==.Ampmage:BAAANQAECgQICAAAAA==.Ampsdk:BAAANQADCgYIBgAAAA==.',
An='Anthren:BAAANQADCgUIBQAAAA==.Antihose:BAAANQABCgQJBAAAAA==.',
Ap='Apollo:BAABNQAECn8oAAIIAAgKuxxFNQCNAgAIAAgKuxxFNQCNAgAAAA==.Apolynnæ:BAABNQAECn8ZAAIJAAcKFRajFgDfAQAJAAcKFRajFgDfAQABNQAECgkJGgAKAI8XAA==.',
Ar='Araniss:BAABNQAECn8ZAAMLAAcKHh/TLQBcAgALAAcKHh/TLQBcAgAMAAMKPQ4gfwClAAAAAA==.Arasthel:BAAANQADCggIFAAAAA==.Aratrath:BAABNQAECn8lAAINAAgKOhtWEwB2AgANAAgKOhtWEwB2AgAAAA==.Araxxi:BAAANQADCgYIBgAAAA==.Arthour:BAAANQADCgUIBQAAAA==.Aryasilly:BAABNQAECn8ZAAIOAAgKRBt2VwBqAgAOAAgKRBt2VwBqAgAAAA==.',
As='Asdi:BAAANQAECgQICgAAAA==.Ashe:BAACNQAFFH8TAAIPAAQKix8eDQBnAQAPAAQKix8eDQBnAQA1AAQKfywAAg8ACQrkJOEEAIMDAA8ACQrkJOEEAIMDAAAA.',
At='Athenix:BAAANQAECggIBgAAAA==.Attabubble:BAAANQAECgEIAQABNQAFFAMICQAOAOgZAA==.Attaraxia:BAACNQAFFH8JAAIOAAMK6BnLFAATAQAOAAMK6BnLFAATAQA1AAQKfzcAAw4ACQpxHngdACADAA4ACQpxHngdACADAA8AAwriD99fAKMAAAAA.',
Au='Aurelith:BAAANQADCgIIBAAAAA==.Aurellya:BAAANQAECgQICwAAAA==.',
Av='Avalora:BAAANQADCgQIBAAAAA==.Aviarra:BAAANQABCgcICgAAAA==.Avodakadavra:BAAANQADCggICAAAAA==.',
Ay='Ayroon:BAAANQAECgQICQAAAA==.',
['Aé']='Aéquítas:BAAANQAECgQIBgAAAA==.',
Ba='Bamfbutcher:BAAANQAECgcIEAAAAA==.Barent:BAAANQADCgYIDAAAAA==.Barrimen:BAABNQAECn8mAAIQAAgK8A1IogDXAQAQAAgK8A1IogDXAQAAAA==.Bartolomew:BAAANQAECggIHgAAAQ==.Bartonella:BAAANQADCgYICAABNQAECgUICwAHAAAAAA==.',
Be='Bealzabung:BAAANQADCgUIBQABNQAECgYIBgAHAAAAAA==.Bedemere:BAABNQAECn8kAAIOAAcKGBxzcAAuAgAOAAcKGBxzcAAuAgAAAA==.Beepers:BAABNQAECn8bAAIOAAgKsg+jhQD8AQAOAAgKsg+jhQD8AQAAAA==.Behodahlia:BAAANQAECgcIEQAAAA==.Belfie:BAAANQAECgUJBQAAAA==.Berrylla:BAAANQADCgIIAgAAAA==.',
Bi='Bigdemon:BAAANQAECgIIAQAAAA==.Bigmakk:BAABNQAECn8mAAIRAAgKJw+MKwC7AQARAAgKJw+MKwC7AQAAAA==.Bimzelx:BAAANQAECgQIBgAAAA==.Bipolar:BAAANQAECggIDAAAAA==.Bitterblood:BAABNQAECn8vAAIOAAcK6BrAXgBYAgAOAAcK6BrAXgBYAgAAAA==.',
Bl='Blastgamer:BAAANQAECgMIAwAAAA==.Blondebeard:BAABNQAECn8ZAAIOAAgKFhCQfwAKAgAOAAgKFhCQfwAKAgAAAA==.',
Bo='Booshi:BAAANQAECgIIAgAAAA==.Bowiiesenpai:BAABNQAECn8fAAISAAgKmyEUEQDnAgASAAgKmyEUEQDnAgAAAA==.',
Br='Bragontix:BAACNQAFFH8LAAIJAAQKQh1IBQBrAQAJAAQKQh1IBQBrAQA1AAQKfyAAAgkACQp+HQgMAKMCAAkACQp+HQgMAKMCAAAA.Bravehearth:BAAANQADCgUIDgABNQAECgYIBgAHAAAAAA==.Brewvoke:BAAANQAECgUJCQAAAA==.Brightxan:BAABNQAECn86AAITAAkKVRP9IADZAQATAAkKVRP9IADZAQAAAA==.',
Bu='Bubbadruid:BAAANQADCgQIBAABNQAECgkJKgAOAEsjAA==.Bubbahunter:BAABNQAECn8qAAIOAAkKSyPBCACWAwAOAAkKSyPBCACWAwAAAA==.Bubbashaman:BAAANQADCgIIAgABNQAECgkJKgAOAEsjAA==.Buddahspanks:BAAANQADCgcIBQAAAA==.Buddahthai:BAABNQAECn8xAAIKAAkKPx+nQQABAwAKAAkKPx+nQQABAwAAAA==.Buddhabum:BAABNQAECn8gAAIEAAkKihY/PQCYAgAEAAkKihY/PQCYAgAAAA==.Budweaver:BAAANQADCgYICQAAAA==.Bus:BAABNQAECn8pAAIUAAkK4CaXAADlAwAUAAkK4CaXAADlAwABNQAFFAcIFQALABkhAA==.Bussdefense:BAAANQADCggIJQAAAA==.Butterrs:BAAANQAFFAYICQAAAQ==.Butterz:BAAANQAECgQICAABNQAFFAYICQAHAAAAAA==.',
Ca='Caleian:BAAANQAECgYIEgAAAA==.Caloren:BAABNQAECn8jAAIVAAkKhBnIDgD9AgAVAAkKhBnIDgD9AgAAAA==.Caorou:BAABNQAECn8ZAAIFAAgK/AaujACBAQAFAAgK/AaujACBAQAAAA==.Carahpri:BAAANQAECgIIAgABNQAFFAcIEAABABoeAA==.Cashaboo:BAAANQADCgYICwAAAA==.',
Cb='Cbrn:BAAANQAECgQIBAABNQAECgkJHAAWAEwTAA==.',
Ch='Charlyte:BAABNQAECn8YAAIIAAgK7xIcXgD7AQAIAAgK7xIcXgD7AQAAAA==.Charuzu:BAAANQADCgYIBgAAAA==.',
Co='Corneater:BAAANQAECgYIAQAAAA==.',
Cr='Crysinia:BAAANQADCgUICwAAAA==.',
Cu='Cuigy:BAABNQAECn8VAAMBAAcK1B/IPABqAgABAAcK1B/IPABqAgAFAAYKYhRejACBAQAAAA==.',
Cy='Cyriene:BAAANQAECgYIDQAAAA==.Cyril:BAAANQAECgMIAgABNQAECgUIEwAHAAAAAA==.',
Da='Dagadin:BAAANQAECgcIDgAAAA==.Dalio:BAAANQAECgYIDAAAAA==.Danté:BAAANQAECgQICQABNQAFFAIIAgAHAAAAAA==.Daraen:BAAANQADCgYIBwAAAA==.Daylen:BAABNQAECn8cAAIXAAcK5wrQjwBiAQAXAAcK5wrQjwBiAQAAAA==.',
Dd='Ddeathchura:BAABNQAECn8cAAILAAcKUxJYVwCTAQALAAcKUxJYVwCTAQAAAA==.',
De='Deactrim:BAABNQAECn8ZAAILAAcKkxJJVQCcAQALAAcKkxJJVQCcAQAAAA==.Deafknights:BAAANQAECgMIBAABNQAECggIDAAHAAAAAA==.Deathscoobs:BAAANQAECgUIBQABNQAECgUICwAHAAAAAA==.Dema:BAAANQADCgUICAAAAA==.Demonicflats:BAEANQADCgcIDAABNQAECgkJKwAEAFERAA==.Demonodie:BAAANQABCggIDAAAAA==.Dendrada:BAABNQAECn8cAAMMAAcKiyHZHwCKAgAMAAcKiyHZHwCKAgAYAAYK1htcVAC9AQAAAA==.Deuce:BAAANQAECgUIEwAAAA==.',
Di='Diogenes:BAAANQADCgQIBAAAAA==.Dizimo:BAAANQAECgUICgAAAA==.',
Dk='Dkflat:BAEANQADCggICQABNQAECgkJKwAEAFERAA==.',
Do='Dogmeat:BAACNQAFFH8JAAIOAAQK/BfNDgBjAQAOAAQK/BfNDgBjAQA1AAQKfyYAAg4ACQqCI2IQAGEDAA4ACQqCI2IQAGEDAAE1AAUUBggWAAYAuhwA.Doncowleone:BAAANQADCgMIAwABNQAECgYIBgAHAAAAAA==.Dotisa:BAAANQAECgEIAQAAAA==.',
Dr='Dragonlex:BAAANQADCgcIDQAAAA==.Drakeshadows:BAAANQADCgIIAgAAAA==.Drchivago:BAAANQADCgYICgAAAA==.Drdreadful:BAAANQABCgIIAgAAAA==.Drfumanchu:BAAANQADCgUICQABNQAECgYIBgAHAAAAAA==.Drotgar:BAAANQAECgIIAgABNQAECggIDgAHAAAAAA==.Druidtime:BAAANQAECggICAAAAA==.',
Du='Duna:BAAANQAECgYIDgAAAA==.Dungoofed:BAAANQAECgEJAQAAAA==.Duvidressra:BAABNQAECn8zAAMDAAkKYRoVAwDUAgADAAkKYRoVAwDUAgAEAAIK1QeaJwFnAAAAAA==.',
Dx='Dxmvn:BAAANQADCgQIBQAAAA==.',
Ed='Edisonn:BAACNQAFFH8HAAIEAAMKbRBoIwDlAAAEAAMKbRBoIwDlAAA1AAQKfywAAwQACQptIOsxAL4CAAQACAotIOsxAL4CAAIABQoxEssmAD8BAAAA.',
Eg='Eggies:BAAANQADCggIGAABNQAECgkJKQAEAKgjAA==.',
Ek='Ektrim:BAAANQAECgEIAQABNQAECgcIGQALAJMSAA==.',
El='Eladio:BAAANQADCgIIAgAAAA==.Eldarya:BAAANQAECgUICgAAAA==.Elentisa:BAAANQAECgUICwAAAA==.Elghinn:BAABNQAECn8lAAIZAAgK4g+vOgDbAQAZAAgK4g+vOgDbAQAAAA==.Elissaria:BAAANQADCgQIBAAAAA==.Ellastrasza:BAABNQAECn8pAAIaAAgKzRKiGwDBAQAaAAgKzRKiGwDBAQAAAA==.Ellie:BAABNQAECn8cAAIOAAcK9BXnhgD5AQAOAAcK9BXnhgD5AQAAAA==.Elroy:BAABNQAECn8rAAIQAAgKVxBMoADcAQAQAAgKVxBMoADcAQAAAA==.',
Em='Embold:BAAANQADCggICAABNQAFFAQIEwASAKYkAA==.Emernantus:BAABNQAECn8bAAITAAcKZROqJAC3AQATAAcKZROqJAC3AQAAAA==.',
Er='Erazar:BAABNQAECn8vAAQJAAkKkyEZAwB4AwAJAAkKkyEZAwB4AwANAAIK/QOrSABXAAAbAAEKjhpqIwA2AAAAAA==.',
Es='Espy:BAAANQAECgMIBAAAAA==.',
Eu='Eunbyeol:BAABNQAECn8ZAAIcAAgKRB5GBgCnAgAcAAgKRB5GBgCnAgAAAA==.',
Ev='Evee:BAAANQABCgQIBAAAAA==.',
Fa='Faeria:BAABNQAECn8cAAIXAAcKXxdJbADVAQAXAAcKXxdJbADVAQAAAA==.Fatcritties:BAAANQAECgIIBAAAAA==.Fatnchunkydk:BAABNQAECn8ZAAILAAYKxBD1agBEAQALAAYKxBD1agBEAQAAAA==.',
Fe='Feeblemind:BAAANQAECgUIDwAAAA==.Feli:BAABNQAECn8VAAMcAAcK6A1xFQBCAQAdAAcKUwhEyABhAQAcAAYKvQ1xFQBCAQAAAA==.Felmommy:BAAANQADCggICAAAAA==.Femboi:BAAANQADCggIDgAAAA==.Fender:BAAANQAECgYIDwAAAA==.',
Ff='Ffugntotems:BAAANQADCgcICwAAAA==.Ffviitifa:BAAANQADCgcICwAAAA==.',
Fi='Finfangfoom:BAAANQADCgQICQABNQAECgYIBgAHAAAAAA==.Fingertoes:BAABNQAECn8fAAIKAAgKDxp/hAB1AgAKAAgKDxp/hAB1AgAAAA==.Fistbeard:BAAANQADCgUJBQABNQADCgcJCgAHAAAAAA==.Fizban:BAAANQADCgcIBwAAAA==.Fizzlerazz:BAAANQADCgUIBQAAAA==.',
Fl='Flattulata:BAEANQADCggICQABNQAECgkJKwAEAFERAA==.Flatulatta:BAEBNQAECn8rAAIEAAkKURHxXAA9AgAEAAkKURHxXAA9AgAAAA==.Flatunter:BAEANQADCggICAABNQAECgkJKwAEAFERAA==.Flory:BAAANQAECggICAAAAA==.Flyciful:BAAANQAECgQIBgAAAA==.Flyingweasle:BAAANQADCgQIBwAAAA==.',
Fo='Forceed:BAEANQAECgEIAQABNQAECgUIDwAHAAAAAA==.Forsythe:BAAANQABCgcICQAAAA==.Foxehh:BAAANQABCgUIBwAAAA==.Foxxycontin:BAAANQADCgEIAQAAAA==.',
Fr='Fraternaldk:BAACNQAFFH8NAAIYAAUK9xLfCACHAQAYAAUK9xLfCACHAQA1AAQKfzEAAhgACQpsIbcJAG8DABgACQpsIbcJAG8DAAAA.Fraturnal:BAAANQADCgIIAgAAAA==.Freestyle:BAAANQADCggIEwAAAA==.Frodowagons:BAAANQAFFAQIBAAAAA==.Frostpie:BAABNQAECn8oAAIKAAkKthU2egCJAgAKAAkKthU2egCJAgAAAA==.',
Fu='Fuglybaby:BAAANQAECggICAAAAA==.Fuhenhenka:BAAANQAECgMIAwAAAA==.Furyofheaven:BAAANQAECgEIAgAAAA==.',
Fw='Fwakos:BAAANQAECgUIDwAAAA==.Fwakow:BAAANQADCgYIEAAAAA==.',
Ga='Gacke:BAAANQADCgEIAQABNQAECggIJQATAOgfAA==.Gakmonk:BAAANQADCggJDgABNQAECggIJQATAOgfAA==.Gakpaladin:BAABNQAECn8lAAITAAgK6B9iDADSAgATAAgK6B9iDADSAgAAAA==.Galaway:BAAANQAECgUICQAAAA==.Galthul:BAAANQADCgUIBQABNQAECggIIQAFAPwcAA==.Garfyaz:BAAANQADCgYIDAAAAA==.',
Gd='Gdlez:BAAANQAECgQICQAAAA==.',
Ge='Gethael:BAAANQADCgIIAgAAAA==.',
Go='Goatroth:BAAANQAECgUICwAAAA==.Golorious:BAABNQAECn8fAAMTAAkKYR3aEwBkAgATAAkKYR3aEwBkAgAQAAEKAAB0gwFNAAAAAA==.Goododie:BAAANQAECgYIDgAAAA==.',
Gr='Grayback:BAAANQAECggICAABNQAECgkJHwAVAHQaAA==.Grenas:BAAANQABCgQICQAAAA==.Grippyweasle:BAABNQAECn8lAAILAAgKUBeQOgAYAgALAAgKUBeQOgAYAgAAAA==.Grishnakh:BAAANQABCgYICQAAAA==.Grovelly:BAAANQABCggIEAAAAA==.Growlius:BAAANQADCgcIBwABNQAECgUJBQAHAAAAAA==.',
Gu='Gudit:BAAANQADCggICgABNQAECgUIDwAHAAAAAA==.Gulaken:BAAANQAECgUIEwAAAA==.Guseva:BAAANQAECgEIAQAAAA==.Guttershark:BAABNQAECn8aAAIeAAgKxxziIgBrAgAeAAgKxxziIgBrAgAAAA==.',
Ha='Hafnia:BAAANQAECgUICwAAAA==.Halliday:BAAANQADCggIHAAAAA==.Haoasakura:BAABNQAECn8kAAIQAAkKLSLhKgAaAwAQAAkKLSLhKgAaAwAAAA==.Haylo:BAAANQAECgIIBAAAAA==.',
He='Headshop:BAAANQADCgcIEgAAAA==.Healzforfood:BAAANQAECgYICwAAAA==.Heap:BAAANQAECgMIAwABNQAECggIGQAOABYQAA==.Heartlight:BAAANQADCgMIAwAAAA==.Heavyreign:BAAANQADCgQIBwAAAA==.Helicobacter:BAAANQADCgYIBgAAAA==.Hewnoshaqa:BAAANQAECgUIEwAAAA==.Hexorcist:BAACNQAFFH8IAAMFAAMK6Qx6GgDpAAAFAAMK6Qx6GgDpAAABAAEKDxV9LgA6AAA1AAQKfyQAAwEACQozH2MnAMQCAAEACQozH2MnAMQCAAUABgqfF81uANABAAAA.',
Hi='Hickerbilly:BAAANQADCgEIAQAAAA==.Hitormist:BAABNQAECn8cAAIWAAkKTBNuFgASAgAWAAkKTBNuFgASAgAAAA==.',
Ho='Holyanne:BAAANQADCgQIAgAAAA==.Holyspanks:BAAANQADCgYIBgABNQAECggIGwAfAF0eAA==.Horous:BAAANQAECgMIAQAAAA==.',
Hr='Hruuli:BAAANQADCgYIBgAAAA==.',
Hu='Huntrlicious:BAABNQAECn8gAAIOAAcKkwtDnwDEAQAOAAcKkwtDnwDEAQAAAA==.Husqvarnna:BAAANQAECgEIAQAAAA==.Huugor:BAAANQAECggIEAAAAA==.',
Ic='Icnips:BAAANQADCgUIBQAAAA==.Icoulddowork:BAAANQAECggIDQABNQAECgkJGwAGAMwfAA==.',
Id='Idoshiftwork:BAABNQAECn8bAAQGAAkKzB/fHQDZAgAGAAgK6CHfHQDZAgAgAAUKrBrGMwB4AQAhAAIK2RIRMQCCAAAAAA==.Idunno:BAAANQADCgYICQAAAA==.',
Ih='Ihriel:BAAANQADCgEJAQAAAA==.',
Ik='Ikazuchi:BAABNQAECn8dAAIMAAcKdw06TwBwAQAMAAcKdw06TwBwAQAAAA==.',
Il='Illcutabish:BAABNQAECn8lAAMeAAgKcySnCwAoAwAeAAgKcySnCwAoAwAiAAgKKhZpHQDkAQAAAA==.Illtank:BAAANQAECgUIBQAAAA==.',
Im='Imatankin:BAAANQAECgEIAgAAAA==.Imk:BAABNQAECn8cAAIVAAcKdwukNgCKAQAVAAcKdwukNgCKAQAAAA==.',
Io='Iock:BAEANQAECgUIBQAAAA==.',
Ir='Ironarms:BAAANQAECgYJEwAAAA==.',
Is='Ishido:BAAANQADCgYIBgAAAA==.',
Je='Jennypoo:BAABNQAECn8jAAIgAAcKWBYpKQDSAQAgAAcKWBYpKQDSAQAAAA==.Jessd:BAAANQADCgcJBwAAAA==.',
Ji='Jinuoo:BAAANQADCgQIBAAAAA==.',
Jo='Johnwarrior:BAABNQAECn8pAAIcAAgKoh7LBADiAgAcAAgKoh7LBADiAgAAAA==.Jorrix:BAABNQAECn8fAAIQAAgK+wkpwACWAQAQAAgK+wkpwACWAQAAAA==.',
Ju='Juduspriestt:BAABNQAECn8eAAIQAAcKQBGatwCoAQAQAAcKQBGatwCoAQAAAA==.',
Jy='Jynaxa:BAAANQADCgEIAQAAAA==.',
['Jä']='Jägermeister:BAAANQADCgYJDAAAAA==.',
Ka='Kaaeko:BAAANQAECgcIDgAAAA==.Kalerito:BAABNQAECn8dAAIgAAgKrCANEADVAgAgAAgKrCANEADVAgAAAA==.Kallythea:BAAANQADCggICAAAAA==.Kardie:BAAANQADCgQIBAABNQAECgkJLwAJAJMhAA==.Karl:BAAANQAECgMIBwABNQAECgUIEAAHAAAAAA==.Kaserr:BAACNQAFFH8XAAMiAAcK4BlVAwADAgAiAAYKfxhVAwADAgAeAAUK3RspBgC5AQA1AAQKfywAAyIACQrrJd0GAA8DACIACArZJd0GAA8DAB4ABQrqJMw3APIBAAAA.Kayserdh:BAAANQAECgUICAAAAA==.Kazaf:BAABNQAECn8hAAILAAgKIhkMNQA1AgALAAgKIhkMNQA1AgAAAA==.Kazrik:BAAANQAECgUICAAAAA==.',
Ke='Kebru:BAAANQAECgcIEwAAAA==.Keitrek:BAABNQAECn8lAAIIAAgKzAtcfAChAQAIAAgKzAtcfAChAQAAAA==.Kelthias:BAAANQADCgYJDQAAAA==.Kenje:BAAANQADCgIIAgAAAA==.Kerwîck:BAABNQAECn8gAAIIAAkKNxTQPgBnAgAIAAkKNxTQPgBnAgAAAA==.Keyen:BAABNQAECn8ZAAIIAAcKXxHrewCiAQAIAAcKXxHrewCiAQAAAA==.',
Kh='Kheiko:BAAANQAECgUIBQAAAA==.',
Ki='Kibalion:BAAANQAECgYIEQAAAA==.Killbent:BAAANQAECgQICQAAAA==.Kinnky:BAAANQAECgcIEwAAAA==.Kino:BAAANQAECgUIEwAAAA==.Kitn:BAAANQABCgQIBAAAAA==.Kityana:BAAANQADCgIIAgAAAA==.',
Kp='Kpop:BAAANQADCgIIAwAAAA==.',
Kr='Krasdan:BAAANQAECgIIAgAAAA==.Kreettip:BAABNQAECn8lAAIXAAgK2RgpRgBRAgAXAAgK2RgpRgBRAgAAAA==.Krispy:BAAANQADCgcJBwABNQAECggIJQANADobAA==.',
Ks='Ksp:BAAANQADCgQIBQAAAA==.',
Ku='Kugamoo:BAABNQAECn8eAAMGAAkKTRdJLwBjAgAGAAkKTRdJLwBjAgAgAAcKZAcJPAA8AQAAAA==.Kulgan:BAABNQAECn8kAAMXAAkKVRpBQQBjAgAXAAkKVRpBQQBjAgAjAAEKJxEMKAA0AAAAAA==.Kurgen:BAAANQAECgYIDgAAAA==.Kuroda:BAAANQAECgQIBwAAAA==.Kurolucifer:BAAANQADCgcIFgAAAA==.',
Ky='Kylex:BAAANQAECggIDgAAAA==.',
['Kä']='Käßoom:BAAANQAECgYIBwAAAA==.',
La='Lamiah:BAAANQAECgUIBwAAAA==.Laredemos:BAAANQAECgUIBQAAAA==.Lauadia:BAAANQAECgMIAwAAAA==.',
Lc='Lckdown:BAAANQAECggIEQAAAA==.',
Le='Legomyegolas:BAAANQADCgYJBgAAAA==.Lelaeh:BAAANQAECggIDwAAAA==.',
Li='Lightsocket:BAAANQADCgYJCAABNQAECgIIAgAHAAAAAA==.Lishy:BAAANQADCgEIAQAAAA==.Livingkntpib:BAAANQADCggICAAAAA==.',
Lo='Lobotany:BAAANQADCgIIAgAAAA==.Lockedout:BAAANQAECgMIAwABNQAECgkJKAAKAIAhAA==.Loden:BAAANQAECgcIDAAAAA==.Lodez:BAAANQAFFAEIAgAAAA==.Loktarhogar:BAAANQAECgUICAAAAA==.Lostadin:BAAANQADCgIIAgAAAA==.Lovi:BAABNQAECn8mAAIBAAkK1xBIZwDTAQABAAkK1xBIZwDTAQAAAA==.',
Lu='Luck:BAAANQAECgQIBAABNQAECgQIBAAHAAAAAA==.Luckyboi:BAABNQAECn8hAAQGAAkKpwk9XQBYAQAGAAgKngY9XQBYAQAgAAgKGgZDOQBPAQAaAAQKKAQQRwCMAAAAAA==.Lumeria:BAAANQAECgUIDQAAAA==.Lumina:BAABNQAECn8ZAAIQAAcK8gk03wBWAQAQAAcK8gk03wBWAQAAAA==.Lusciifi:BAACNQAFFH8SAAMQAAYK3R8vCADGAQAQAAUK3R8vCADGAQATAAQKlAu9BgAWAQA1AAQKfzUAAxAACQpNJnsOAJIDABAACQpKJnsOAJIDABMACAqQIrkLANwCAAAA.',
Ly='Lykie:BAABNQAECn8hAAITAAgKTR2dFQBRAgATAAgKTR2dFQBRAgAAAA==.Lynxic:BAAANQAECgUIBwAAAA==.Lyone:BAABNQAECn8aAAIUAAYKLRs0GACnAQAUAAYKLRs0GACnAQAAAA==.',
['Lä']='Lävey:BAAANQADCgEIAQAAAA==.',
['Lé']='Léxa:BAAANQAECgMIAwAAAA==.',
['Lú']='Lúvaa:BAAANQAECgcIEwAAAA==.',
Ma='Macavity:BAAANQADCgMIAwAAAA==.Madmanmike:BAAANQADCgIIAgAAAA==.Magalis:BAAANQAECgQIDQAAAA==.Magicwoman:BAAANQAECgUIDwAAAA==.Magikkisback:BAAANQAECgQIAwAAAA==.Magsh:BAAANQAECgIIAwAAAA==.Mandorius:BAAANQAECgUIDAAAAA==.Maphra:BAAANQADCggJCAABNQAECgkJHAAWAEwTAA==.Marcos:BAAANQADCgIIAgAAAA==.Marl:BAAANQAECgIIBAAAAA==.Marvolo:BAAANQAECggIDgABNQAECgkJHwAVAHQaAA==.Maverickdog:BAABNQAECn8dAAQPAAgKpx2WLwDNAQAPAAcKMxuWLwDNAQAkAAQKOBKDDAAIAQAOAAMKPiNRBQH2AAAAAA==.',
Mc='Mchammerwork:BAAANQAECgYICgABNQAECgkJGwAGAMwfAA==.',
Me='Mechunter:BAAANQADCgYIBgABNQAECgUICAAHAAAAAA==.Meekzz:BAABNQAECn8cAAIXAAgKzhgBPQBzAgAXAAgKzhgBPQBzAgAAAA==.Meeshie:BAABNQAECn9NAAQXAAkKxBiGMwCXAgAXAAkKxBiGMwCXAgASAAYKMg5BOABfAQAjAAIK5QVsIgBRAAAAAA==.Melodrop:BAAANQAECggIDQAAAA==.',
Mi='Mihawk:BAAANQADCgEIAQABNQAECggIHwAKAA8aAA==.Mikexfire:BAABNQAECn8cAAIZAAgKNQ2KPwC7AQAZAAgKNQ2KPwC7AQAAAA==.Mikuzume:BAAANQADCgYIBgAAAA==.Mildchaos:BAAANQAECggJAQAAAA==.Mimic:BAAANQADCgIIAgAAAA==.Mishima:BAAANQAECggIEAAAAA==.Misspell:BAAANQADCggJFAAAAA==.Miznewbooty:BAABNQAECn8eAAISAAkK3RMaHwBAAgASAAkK3RMaHwBAAgAAAA==.',
Mo='Moochella:BAAANQAECgcIEAAAAA==.Moojestic:BAAANQAECgMIAwAAAA==.Moonflungpoo:BAAANQAECgIIAgAAAA==.Moonq:BAABNQAECn8cAAIgAAcKIANTSwDdAAAgAAcKIANTSwDdAAAAAA==.Moosie:BAABNQAECn8jAAIlAAgKOxU9DgDTAQAlAAgKOxU9DgDTAQAAAA==.Moosifer:BAAANQADCgQIBAABNQAFFAMICAAFAOkMAA==.Mooska:BAAANQAECgEIAQABNQAECggIIwAlADsVAA==.Mostunknown:BAAANQADCgYIBgAAAA==.Moxflip:BAAANQAECgcICQAAAA==.Moxtsm:BAAANQAECgMIBgAAAA==.Mozzers:BAAANQAECgIIAgAAAA==.',
Mu='Muertenegra:BAAANQADCgUIBQABNQAECgcIHgAFAF4ZAA==.Muffy:BAABNQAECn8XAAINAAYKSRDXKgBTAQANAAYKSRDXKgBTAQAAAA==.Muln:BAAANQADCggIBwAAAA==.Murlouh:BAAANQADCgQIBAAAAA==.',
My='Mydevil:BAAANQAECgMIBAAAAA==.Myllakura:BAAANQAECgQICQABNQAECggIDwAHAAAAAA==.Mystk:BAAANQADCgIIAgAAAA==.Mythnarra:BAACNQAFFH8KAAMZAAQKehcMDQA5AQAZAAQKehcMDQA5AQAVAAIKggTjEgBjAAA1AAQKfyMAAxUACQrqIhkNABADABUACQpAIhkNABADABkABArrIO1LAGsBAAAA.',
['Mä']='Mäomäo:BAAANQADCgMIAwAAAA==.',
['Mí']='Mísanthrope:BAAANQADCgQIBAABNQAECgUICwAHAAAAAA==.',
['Mò']='Mòrpheus:BAAANQAFFAIIAgAAAA==.',
Na='Nadíne:BAABNQAECn8gAAIKAAgKXhMsvgAGAgAKAAgKXhMsvgAGAgAAAA==.Nanukimon:BAAANQAECgYIDgAAAA==.Narawe:BAAANQAECgQIBQABNQAECgkJKwABALgfAA==.Nardionger:BAAANQAECgQIBAAAAA==.Nastymccasty:BAAANQAECggIAwABNQAECggIJQAeAHMkAA==.Naughtgelic:BAAANQADCgYICgAAAA==.',
Ne='Nedgamingttv:BAEANQAECgUIDwAAAA==.Nekrimah:BAAANQAECgYIDAABNQAECggIDwAHAAAAAA==.Nerph:BAAANQADCgYIEQAAAA==.Nevaera:BAAANQAECgIIAgAAAA==.',
Ni='Ni:BAAANQAECgQIBAAAAA==.Nick:BAACNQAFFH8TAAMLAAQKtxO0FQD/AAAYAAQKLRPwDgAZAQALAAQKMRG0FQD/AAA1AAQKfy4AAxgACQoEJqgRACkDABgACQoEJqgRACkDAAsAAwqnGl6FAOQAAAAA.Nikor:BAEANQAECgcIDwAAAA==.',
Nm='Nmue:BAAANQADCgIIAgAAAA==.',
No='Nokorii:BAAANQAECgYIDgAAAA==.Nomecoma:BAABNQAECn8gAAILAAkKGxAtTwC1AQALAAkKGxAtTwC1AQAAAA==.Nonok:BAAANQADCgIIAgAAAA==.Nookah:BAAANQAECgYIBgABNQAFFAMICQAOAOgZAA==.Noshom:BAABNQAECn8dAAMBAAgKRiKPGwD/AgABAAgKRiKPGwD/AgAFAAMKbQ6Z6gC7AAAAAA==.Notches:BAAANQADCgEIAQAAAA==.',
Ns='Nsyncrogue:BAAANQADCgYJBgAAAA==.',
Ny='Nymful:BAABNQAECn8ZAAIPAAcKcgeFPwBSAQAPAAcKcgeFPwBSAQAAAA==.',
['Nè']='Nèlo:BAABNQAECn8VAAIdAAcK6w6xtgCPAQAdAAcK6w6xtgCPAQAAAA==.',
Ob='Obianstrider:BAAANQADCggIHQAAAA==.',
Oc='Oceanspell:BAABNQAECn8rAAImAAYKRyG9CABMAgAmAAYKRyG9CABMAgAAAA==.',
Og='Oggleboggle:BAAANQADCgEIAQAAAA==.',
Ol='Oldbuse:BAABNQAECn8hAAMfAAgKZCDyCwCvAgAfAAgKZCDyCwCvAgAFAAEK1BjxIgFEAAAAAA==.',
On='Onlytoez:BAAANQAECgYIDgABNQAECgkJTQAXAMQYAA==.',
Or='Orave:BAAANQAECgUIDQAAAA==.Orionah:BAAANQAECgYIBgAAAA==.Oromë:BAAANQABCgQIBAAAAA==.Orzik:BAAANQADCgcIBwAAAA==.',
Os='Osox:BAAANQAECggICAAAAA==.Ostena:BAAANQAECgYIEQAAAA==.Osteole:BAABNQAECn8ZAAMSAAYKLgeOSgDpAAASAAUKkweOSgDpAAAXAAQKVwRR0QCrAAABNQAECgYIEQAHAAAAAA==.',
Ou='Oulawdpriest:BAACNQAFFH8KAAISAAQKcgn3CwAjAQASAAQKcgn3CwAjAQA1AAQKfyUAAxIACQo5FwcdAFcCABIACQo5FwcdAFcCABcAAQpjE/75ADAAAAAA.',
Ov='Overture:BAAANQAECgMIAwAAAA==.',
Ow='Owthatburns:BAAANQADCgYIBgAAAA==.',
Pa='Pakszdude:BAAANQADCgUIBQAAAA==.Pandamonious:BAAANQADCggICAABNQAECgEIAgAHAAAAAA==.Papawoof:BAAANQADCgQJBQABNQAFFAMICAAFAOkMAA==.Parkour:BAAANQAECgMIBwAAAA==.Paullyfists:BAABNQAECn8YAAIRAAgKWCHnEQDMAgARAAgKWCHnEQDMAgAAAA==.',
Pe='Peni:BAAANQAECgIIAgAAAA==.',
Pi='Pintobeans:BAAANQAECgEIAgAAAA==.',
Po='Popkorn:BAACNQAFFH8eAAMVAAcK8iUKAQCdAgAVAAYK8iUKAQCdAgAlAAMKQB5KAgAgAQA1AAQKfy8AAxUACQrSJvoAAOcDABUACQrSJvoAAOcDACUAAgomHhYfAM0AAAAA.Popkourne:BAAANQAECggIDQABNQAFFAcIHgAVAPIlAA==.Poplocks:BAAANQADCgYICgAAAA==.Porrana:BAABNQAECn8UAAIdAAcKfRpEhwAGAgAdAAcKfRpEhwAGAgAAAA==.Powaqa:BAAANQAECgUIEgAAAA==.',
Pr='Praetorian:BAABNQAECn8fAAIQAAkKHw5klwDwAQAQAAkKHw5klwDwAQAAAA==.Praxxus:BAAANQADCgYIBgAAAA==.',
Ps='Psy:BAAANQAECggIAgAAAA==.',
Py='Pyrahna:BAAANQADCgYIBgABNQAECgUICQAHAAAAAA==.',
Qm='Qmen:BAAANQADCgIIAgAAAA==.',
Qu='Quasient:BAABNQAECn8oAAIKAAkKhBzZSQDuAgAKAAkKhBzZSQDuAgAAAA==.Quethelos:BAAANQADCgcIHwAAAA==.Quickbrew:BAAANQAECgUIBQAAAA==.Quickspell:BAABNQAECn8dAAImAAkK3RvcAwD7AgAmAAkK3RvcAwD7AgAAAA==.',
Ra='Raalcar:BAAANQAECgMIAwABNQAECgYIEQAHAAAAAA==.Raedyyn:BAAANQAECgcICgAAAA==.Ragarninn:BAAANQAECgYICQABNQAFFAMIBwABAAMiAA==.Ragarth:BAAANQAECgEIAQAAAA==.Ragendecay:BAAANQAECgYIDgAAAA==.Ragequits:BAACNQAFFH8dAAIdAAgK5CNjAQD/AgAdAAgK5CNjAQD/AgA1AAQKfycAAh0ACQo3JkgRAHcDAB0ACQo3JkgRAHcDAAAA.Ragewar:BAAANQABCgcIDAAAAA==.Rakshassa:BAAANQAECgcICwAAAA==.Ralcar:BAAANQAECgYIEQAAAA==.Rawkphyst:BAAANQADCgQIAgAAAA==.Razrscale:BAAANQAECgEIAQAAAA==.',
Re='Redhuntsman:BAAANQAECgMIAwAAAA==.Regrow:BAAANQADCgcIBwABNQAECgUICAAHAAAAAA==.Reska:BAAANQAECgUICQAAAA==.',
Rh='Rholdentodor:BAAANQAECgQIBQABNQAECgcIMAAKAMcaAA==.',
Ri='Rindorin:BAAANQAECgYIEgAAAA==.Ritarepulsa:BAAANQADCgYIDAAAAA==.',
Ro='Rohra:BAABNQAECn8bAAIgAAcKDAubOwA/AQAgAAcKDAubOwA/AQAAAA==.Roral:BAAANQAECgEIAQABNQAECgUICwAHAAAAAA==.Rosiee:BAAANQAECgQICQABNQAECggIJgARACcPAA==.Rozynwen:BAAANQAECgIIAwAAAA==.',
Ru='Ruah:BAAANQABCgMIAwAAAA==.Rubmytoes:BAAANQAECgEJAQAAAA==.Rukuna:BAAANQAECgEIAQAAAA==.Runecast:BAABNQAECn8qAAIMAAkK0RmBHQCbAgAMAAkK0RmBHQCbAgAAAA==.',
Sa='Saelyrinth:BAAANQAECgEIAQABNQAECgUIDQAHAAAAAA==.Salamence:BAAANQADCggIDwABNQAECggIHgAHAAAAAQ==.Sambor:BAABNQAECn8XAAIgAAgKoAPYUADBAAAgAAgKoAPYUADBAAAAAA==.Sarapheena:BAABNQAECn8fAAIBAAkKXxvOKQC6AgABAAkKXxvOKQC6AgAAAA==.Sarouk:BAABNQAECn8oAAIdAAkKPhdDVQCIAgAdAAkKPhdDVQCIAgAAAA==.Satanbomb:BAAANQAECgIIBAAAAA==.Satansbride:BAAANQAECgYIBgABNQAECgYIBgAHAAAAAA==.Saterli:BAACNQAFFH8JAAIXAAUKEw8UEgB5AQAXAAUKEw8UEgB5AQA1AAQKfyAAAxcACQo1FwdCAGACABcACQo1FwdCAGACABIAAQplAkKEACMAAAAA.Saturno:BAAANQAECgEIAQAAAA==.Saucypirate:BAABNQAECn8hAAMmAAgKKxEPFQBYAQAKAAgKSAy80wDcAQAmAAYKlRIPFQBYAQAAAA==.Sayygurl:BAAANQAECgQIBgAAAA==.',
Sc='Scalvert:BAABNQAECn8wAAIKAAcKxxqwtQAWAgAKAAcKxxqwtQAWAgAAAA==.Scalypanda:BAABNQAECn8ZAAMbAAgK2g9bCwCoAQAbAAgKoA5bCwCoAQAJAAYKxQn+IwAgAQAAAA==.Scamander:BAABNQAECn8fAAIVAAkKdBqWFQC1AgAVAAkKdBqWFQC1AgAAAA==.Scoobs:BAAANQADCgQIBAABNQAECgUICwAHAAAAAA==.Screamsalot:BAAANQAECgEIAQAAAA==.Sculi:BAABNQAECn8iAAIOAAcKDBINlgDYAQAOAAcKDBINlgDYAQAAAA==.',
Se='Seiishiro:BAAANQAECgUIBwAAAA==.Seldon:BAABNQAECn8ZAAIQAAYKqRNTygCBAQAQAAYKqRNTygCBAQAAAA==.Senyor:BAABNQAECn8mAAITAAkK4RaYGAAwAgATAAkK4RaYGAAwAgAAAA==.Seradormi:BAAANQADCgMIAwAAAA==.Seraphiel:BAAANQAECgUIDQABNQAECgYIEQAHAAAAAA==.Serelyth:BAAANQADCgMIAwABNQAECgkJKAAKAIAhAA==.Serfort:BAAANQADCgcIDQAAAA==.',
Sh='Shadowpaksz:BAABNQAECn8eAAQSAAcKRRYyJwDuAQASAAcKRRYyJwDuAQAXAAYKHhpMcgDBAQAjAAMKThL3FwCwAAAAAA==.Shadowsneak:BAABNQAECn8VAAMiAAYK8goPLABdAQAiAAYK8goPLABdAQAeAAEKkgbboAAzAAAAAA==.Shadowvixen:BAAANQAECgMIBAAAAA==.Shaelistra:BAABNQAECn8ZAAIhAAYK0RG/GABsAQAhAAYK0RG/GABsAQAAAA==.Shalilama:BAACNQAFFH8HAAIBAAMKAyJxEgAkAQABAAMKAyJxEgAkAQA1AAQKfzQAAgEACQq5JXIBANEDAAEACQq5JXIBANEDAAAA.Shamanana:BAABNQAECn8aAAIfAAkKiQvVFAAXAgAfAAkKiQvVFAAXAgAAAA==.Shamanic:BAAANQAECgQIBAAAAA==.Shamboli:BAAANQADCggIEgAAAA==.Shamirah:BAAANQADCgcJCQAAAA==.Shaï:BAAANQAECgUICQAAAA==.Shenderp:BAAANQAECgYIEQAAAA==.Shinerbock:BAABNQAECn8bAAInAAcKOQuLGQBIAQAnAAcKOQuLGQBIAQAAAA==.Shockitti:BAAANQAECgIIAgAAAA==.Shtark:BAAANQAECgQIBwAAAA==.',
Si='Sianvar:BAAANQAECggIDwAAAA==.Silshara:BAABNQAECn8hAAINAAkKqw0DHgDtAQANAAkKqw0DHgDtAQAAAA==.Silverjustis:BAABNQAECn8cAAIQAAcKNAW6BQEPAQAQAAcKNAW6BQEPAQAAAA==.Siwe:BAABNQAECn8hAAQFAAgK/BxTYQD6AQAFAAcKjBpTYQD6AQAfAAYKqhkgGADhAQABAAIKCxSC9QB6AAAAAA==.Six:BAAANQAECgIIAgABNQAECgMIAwAHAAAAAA==.',
Sk='Skip:BAAANQADCgMIAwAAAA==.Skittulz:BAAANQADCgQIBQAAAA==.Skribblez:BAABNQAECn8nAAMQAAgKvRpCbgBQAgAQAAgKvRpCbgBQAgAIAAQKJBTqvwD4AAAAAA==.Skyanna:BAAANQAECgIIAwAAAA==.',
Sl='Slackback:BAAANQAECggIDgABNQAFFAMIBgAFAMUQAA==.Sloop:BAAANQADCgYIEAAAAA==.Sloot:BAAANQAECgcIDwAAAA==.',
Sn='Sneasel:BAAANQAECgMIBAABNQAECgQIBAAHAAAAAA==.Snoogins:BAAANQAECgEIAQABNQAECgYIBgAHAAAAAA==.',
So='Sockszz:BAABNQAECn8qAAIhAAgKPyaVAgCIAwAhAAgKPyaVAgCIAwAAAA==.Songblade:BAAANQABCgcICwAAAA==.Soulsy:BAABNQAECn8fAAIQAAgKwiD8SwCtAgAQAAgKwiD8SwCtAgAAAA==.Soulvalk:BAAANQADCgQIBAAAAA==.Sourmagic:BAABNQAECn8cAAMKAAgK2xIeyQDxAQAKAAgK0A4eyQDxAQAmAAIKcBl7KwCbAAAAAA==.',
Sp='Splendorae:BAABNQAECn8bAAIIAAgKXxaNSQA/AgAIAAgKXxaNSQA/AgAAAA==.Sprints:BAABNQAECn8nAAIBAAgKuxKgbwC5AQABAAgKuxKgbwC5AQAAAA==.Spritz:BAABNQAECn8qAAMFAAgKciKyLQDDAgAFAAcKciKyLQDDAgABAAgKZB6pMACcAgAAAA==.Sprucewillis:BAAANQADCgQIDAABNQAECgYIBgAHAAAAAA==.Spyderelite:BAABNQAECn8cAAICAAkKsw75CQBXAgACAAkKsw75CQBXAgAAAA==.',
Sq='Squirrel:BAAANQAECgcIEwAAAA==.',
Ss='Ssuperss:BAAANQADCgQICgAAAA==.',
St='Stabbot:BAAANQAECgMJAwABNQAECgkJHAAWAEwTAA==.Stankstarstu:BAAANQAECgYIBgAAAA==.Starblood:BAAANQABCgMIAwAAAA==.Starspeaker:BAAANQAECgQICAAAAA==.Stellf:BAAANQADCgYIBgAAAA==.Steviewonder:BAAANQADCgUIBQAAAA==.Stompmyballs:BAAANQAECgYIEgABNQAFFAgIHQAdAOQjAA==.Stoogotz:BAAANQADCgIIBAAAAA==.Studlebane:BAAANQAECgUICgAAAA==.Studlepalm:BAAANQAECgMIBgABNQAECgUICgAHAAAAAA==.',
Su='Sundaresh:BAAANQADCgEIAQAAAA==.Sunwing:BAABNQAECn8bAAIXAAgKRyERKgC+AgAXAAgKRyERKgC+AgAAAA==.Supersasian:BAAANQAECggICgAAAA==.Supersheep:BAAANQAECgYIDAAAAA==.Suvien:BAAANQAECgIIBAAAAA==.',
Sy='Sylvarian:BAABNQAECn8ZAAIoAAgKWg7ZAgD4AQAoAAgKWg7ZAgD4AQAAAA==.Sylvinna:BAAANQADCggIFQAAAA==.',
Ta='Tagda:BAAANQADCggICAAAAA==.Takeurland:BAAANQAECgUIBAAAAA==.Taterdotz:BAAANQAECgIIAgAAAA==.Tatersack:BAAANQABCgUIBQAAAA==.Tatortwats:BAAANQAFFAEIAwAAAA==.Taxdeeznutz:BAAANQADCgUIBQAAAA==.',
Te='Tengrit:BAAANQADCgcIDgAAAA==.Tephine:BAABNQAECn8bAAIfAAgKXR7iDgB6AgAfAAgKXR7iDgB6AgAAAA==.Tepicoyotl:BAABNQAECn8rAAMBAAkKuB+XEAA/AwABAAkKuB+XEAA/AwAFAAEKAADbWwEYAAAAAA==.',
Th='Thaymor:BAAANQADCgcJCgAAAA==.Thebigkitti:BAAANQADCgEIAQAAAA==.Thelonecone:BAACNQAFFH8HAAIMAAMKXhYWDgDxAAAMAAMKXhYWDgDxAAA1AAQKfzQAAgwACQoVJUwGAHsDAAwACQoVJUwGAHsDAAAA.Theodor:BAAANQAECgMIBAAAAA==.Theoganth:BAAANQAECgMIBAABNQAFFAIIAgAHAAAAAA==.Theraphee:BAAANQADCgcIFwAAAA==.Therym:BAAANQADCgEIAQABNQAECgcIFgAnALMPAA==.Thomwizard:BAAANQADCggIFAAAAA==.Thormorn:BAAANQAECgUIBQAAAA==.Thunnha:BAAANQADCgYJEwAAAA==.',
Ti='Tierali:BAAANQAECgIIAgAAAA==.Tio:BAAANQADCggIGwAAAA==.',
To='Toastedsushi:BAAANQADCgYIBgAAAA==.Toofwess:BAAANQAECgUICAABNQAECgkJHAAWAEwTAA==.Torrinchaos:BAAANQADCgQIBAAAAA==.Tosala:BAAANQAECgMIBQAAAA==.Totemkiller:BAAANQAECgQIDgAAAA==.',
Tr='Traael:BAABNQAECn8dAAIOAAgKJRPqTwB9AgAOAAgKJRPqTwB9AgAAAA==.Treesap:BAABNQAECn8cAAIpAAgKiyFQBADKAgApAAgKiyFQBADKAgAAAA==.Trinityeve:BAAANQAECgQIDQAAAA==.Trmz:BAAANQAECggIDAAAAA==.Trnzlock:BAAANQAECgYIDwABNQAECggIDAAHAAAAAA==.Tryzk:BAAANQAECggICAAAAA==.Trîggêr:BAAANQADCgYIBgAAAA==.',
Tu='Tulanii:BAAANQADCgcICQAAAA==.Tularana:BAABNQAECn8aAAIKAAkKjxf2bQCiAgAKAAkKjxf2bQCiAgAAAA==.Tumble:BAAANQAECgQICAAAAA==.',
Tw='Twignberryz:BAAANQAECgQIBgABNQAECgYIBgAHAAAAAA==.Twinkie:BAAANQAECgcIDgAAAA==.Twodogz:BAABNQAECn8cAAIOAAcKTiEXQwCgAgAOAAcKTiEXQwCgAgAAAA==.',
Ty='Tyious:BAABNQAECn8jAAQMAAkKWRbEMQAVAgAMAAkKWRbEMQAVAgAYAAUKkA+snQC/AAALAAEKnwNc0gApAAAAAA==.Tyndara:BAABNQAECn8ZAAIIAAYK/g95lgBaAQAIAAYK/g95lgBaAQAAAA==.Tyìous:BAAANQAECgEIAQAAAA==.',
['Tü']='Tüesdaÿ:BAAANQAECgQIBQAAAA==.',
Ub='Ubavoke:BAAANQAECggICQAAAA==.',
Uk='Ukita:BAABNQAECn8rAAIQAAkKByOPKQAeAwAQAAkKByOPKQAeAwAAAA==.',
Ur='Ursane:BAABNQAECn8uAAMdAAkK8xlKRQC3AgAdAAkK8xlKRQC3AgAcAAQKSgiLIgCeAAAAAA==.Ursully:BAABNQAECn8ZAAIaAAYKbhbXHAC1AQAaAAYKbhbXHAC1AQAAAA==.',
Uz='Uzi:BAABNQAECn8bAAICAAcK7REjDwAIAgACAAcK7REjDwAIAgAAAA==.',
Va='Vaardux:BAAANQAECgEIAQAAAA==.Valentíne:BAAANQADCgYIDAAAAA==.Valhalla:BAAANQAECgMIBgAAAA==.Vanish:BAAANQAFFAIIAgAAAA==.Vanncint:BAAANQAECgUIDgAAAA==.Vashie:BAAANQADCgYICgAAAA==.',
Ve='Vexus:BAACNQAFFH8GAAIFAAMKxRDIGQDvAAAFAAMKxRDIGQDvAAA1AAQKfx4AAgUACQrdHL4pANcCAAUACQrdHL4pANcCAAAA.',
Vi='Vinecone:BAAANQAECgQIBAAAAA==.Vivifyght:BAAANQAECgIIAwAAAA==.Vixly:BAAANQADCggIGgAAAA==.',
Vl='Vladios:BAABNQAECn8aAAIQAAcK2gSO/wAaAQAQAAcK2gSO/wAaAQAAAA==.',
Vo='Voidmommy:BAAANQADCgYIDAABNQAECgUIDQAHAAAAAA==.Vordarian:BAAANQAECgEIAQAAAA==.',
Wa='Wardrak:BAAANQAECgIIAwAAAA==.Warlokholmes:BAAANQADCgIIAgAAAA==.Warrax:BAAANQADCgcIEAAAAA==.Watchmeburst:BAAANQADCgYICAAAAA==.',
We='Wezleydoomz:BAAANQADCgYIBgABNQAECgkJKAAOAOoiAA==.',
Wh='Whaler:BAABNQAECn8hAAIdAAkKxRmBRgCzAgAdAAkKxRmBRgCzAgAAAA==.',
Wi='Windeagle:BAAANQADCgQIBAABNQAECgUJBQAHAAAAAA==.Windowskey:BAAANQAECgYIAwABNQAECggIEgAHAAAAAA==.',
Wu='Wuzntmyfault:BAAANQAECgUICAAAAA==.',
Wy='Wyldfyire:BAABNQAECn8aAAIJAAcKzAaVIABMAQAJAAcKzAaVIABMAQAAAA==.',
Xa='Xaven:BAABNQAECn8XAAIeAAYK9RY5RwCiAQAeAAYK9RY5RwCiAQAAAA==.Xavenuke:BAAANQADCgcJDQABNQAECgYIFwAeAPUWAA==.',
Xi='Xiaotao:BAAANQAECgMIAwAAAA==.',
Xt='Xtraxtra:BAAANQADCggICQABNQAECggIJQANADobAA==.',
Ye='Yellenheller:BAAANQAECgIIAgABNQAECgkJKAAKALYVAA==.',
Yo='Yoan:BAAANQAECggIEQAAAQ==.Yoga:BAAANQAECgYIDgAAAA==.',
Za='Zabra:BAAANQADCggJFQAAAA==.Zahshia:BAAANQAECgUICQAAAA==.Zakilron:BAAANQAECgUIBQAAAA==.Zalarian:BAAANQADCgEIAQAAAA==.Zaldina:BAAANQADCgIIAgAAAA==.Zathaeus:BAACNQAFFH8OAAIVAAUKHxltCABxAQAVAAUKHxltCABxAQA1AAQKfyUAAhUACQpPIeEGAGMDABUACQpPIeEGAGMDAAAA.Zaylian:BAABNQAECn8kAAIZAAkKnRoXIgCHAgAZAAkKnRoXIgCHAgAAAA==.Zayragossa:BAABNQAECn8pAAMEAAkKqCP/CACDAwAEAAkKqCP/CACDAwACAAIKTSEeQwC3AAAAAA==.Zayrah:BAAANQAECgYIDQABNQAECgkJKQAEAKgjAA==.',
Ze='Zeerkk:BAABNQAECn8jAAMCAAgKSBiTGwCPAQACAAUKrRqTGwCPAQAEAAQKfhOG5wD1AAAAAA==.Zergmark:BAAANQADCgUIBgAAAA==.Zervise:BAAANQABCgIIAgAAAA==.',
Zi='Zirdford:BAAANQAECgIIAgABNQAECggIDgAHAAAAAA==.Zirilian:BAAANQADCgQICAABNQAECgcIHgAQAEARAA==.',
Zo='Zoomzoom:BAAANQAECgYIBgABNQAFFAQICgASAHIJAA==.Zouris:BAAANQAECgUIBwAAAA==.',
Zu='Zulkraa:BAAANQAECgUIDQAAAA==.',
Zy='Zynreth:BAAANQADCgIIAgAAAA==.',
['Ài']='Àirén:BAABNQAECn8aAAQSAAgK3SD2EwDDAgASAAgK3SD2EwDDAgAXAAEKhxtp9gA4AAAjAAEKRhCRKAAyAAAAAA==.',
['Åb']='Åbon:BAAANQADCgcIEAAAAA==.',
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
