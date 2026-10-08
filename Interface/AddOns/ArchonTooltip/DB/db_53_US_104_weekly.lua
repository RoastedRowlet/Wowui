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

local lookup = {'Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Paladin-Holy','Evoker-Devastation','Unknown-Unknown','DeathKnight-Blood','DeathKnight-Frost','Evoker-Preservation','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Monk-Windwalker','Priest-Shadow','Paladin-Protection','Mage-Arcane','Warrior-Protection','DemonHunter-Devourer','Shaman-Restoration','Shaman-Elemental','Druid-Balance','DemonHunter-Havoc','Druid-Guardian','Evoker-Augmentation','Warrior-Fury','Warrior-Arms','DeathKnight-Unholy','Rogue-Assassination','Monk-Mistweaver','Shaman-Enhancement','Druid-Restoration','Druid-Feral','Rogue-Subtlety','Priest-Holy','Priest-Discipline','Hunter-Survival','DemonHunter-Vengeance','Mage-Frost','Monk-Brewmaster','Rogue-Outlaw',}
local provider = {region='US',realm='Garona',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aartoo:BAAANQABCggIDQAAAA==.',
Ac='Acherona:BAAANQABCgQIBAAAAA==.Acuminada:BAAANQADCgIIAgAAAA==.Acuna:BAAANQAECgUIDAAAAA==.',
Ad='Adison:BAAANQAECgUIBgAAAA==.',
Af='Affliction:BAABNQAECoEVAAQBAAcKJB41GQCaAQABAAUKNxo1GQCaAQACAAQK1x7gDABmAQADAAIKfBXQAAGOAAAAAA==.',
Ai='Airz:BAAANQAECgYIDAAAAA==.',
Ak='Akâkiôs:BAAANQAECgYIEwAAAA==.',
Al='Aladorman:BAAANQAECgYICwAAAA==.Alamo:BAAANQAECgUIDQAAAA==.Albertlin:BAAANQAECgcIEQAAAA==.Alexinar:BAAANQAECgEIAQAAAA==.',
Am='Amakuagsak:BAAANQAECgUICgAAAA==.Amicus:BAAANQAECgUIDAAAAA==.Ampmage:BAAANQAECgQICAAAAA==.Ampsdk:BAAANQADCgYIBgAAAA==.',
An='Anthren:BAAANQADCgUIBQAAAA==.Antihose:BAAANQABCgQJBAAAAA==.',
Ap='Apollo:BAABNQAECoEgAAIEAAgKYxbfRgAsAgAEAAgKYxbfRgAsAgAAAA==.Apolynnæ:BAABNQAECoEZAAIFAAcKShgfFADsAQAFAAcKShgfFADsAQABNQAECggIEAAGAAAAAA==.',
Ar='Araniss:BAABNQAECoEVAAMHAAYKqSDoMgAjAgAHAAYKqSDoMgAjAgAIAAEK+wcKngAlAAAAAA==.Arasthel:BAAANQADCggIFAAAAA==.Aratrath:BAABNQAECoElAAIJAAgKOhtSEQCBAgAJAAgKOhtSEQCBAgAAAA==.Araxxi:BAAANQADCgYIBgAAAA==.Aryasilly:BAABNQAECoEVAAIKAAcK5xreYgAlAgAKAAcK5xreYgAlAgAAAA==.',
As='Asdi:BAAANQAECgMIBgAAAA==.Ashe:BAACNQAFFIEPAAILAAQK+SBgCgBzAQALAAQK+SBgCgBzAQA1AAQKgSkAAgsACQrzJBcEAI0DAAsACQrzJBcEAI0DAAAA.',
At='Athenix:BAAANQAECggIBgAAAA==.Attabubble:BAAANQAECgEIAQABNQAECgkJLQAKACgeAA==.Attaraxia:BAABNQAECoEtAAMKAAkKKB5XHwD+AgAKAAkKKB5XHwD+AgALAAEK7QzKeAA3AAAAAA==.',
Au='Aurelith:BAAANQADCgIIBAAAAA==.Aurellya:BAAANQAECgQIBwAAAA==.',
Av='Aviarra:BAAANQABCgcICgAAAA==.Avodakadavra:BAAANQADCggICAAAAA==.',
Ay='Ayroon:BAAANQAECgQIBwAAAA==.',
['Aé']='Aéquítas:BAAANQAECgQIBgAAAA==.',
Ba='Bamfbutcher:BAAANQAECgcIDQAAAA==.Barent:BAAANQADCgYIDAAAAA==.Barrimen:BAABNQAECoEfAAIMAAgKrQ8jjgDVAQAMAAgKrQ8jjgDVAQAAAA==.Bartolomew:BAAANQAECgYIFwAAAQ==.Bartonella:BAAANQADCgIIAgABNQAECgQIBwAGAAAAAA==.',
Be='Bealzabung:BAAANQADCgUIBQABNQAECgYIBgAGAAAAAA==.Bedemere:BAABNQAECoEdAAIKAAcKgRiBZgAcAgAKAAcKgRiBZgAcAgAAAA==.Beepers:BAABNQAECoEYAAIKAAgKxg7ZcAACAgAKAAgKxg7ZcAACAgAAAA==.Behodahlia:BAAANQAECgYIEAAAAA==.Belfie:BAAANQAECgUJBQAAAA==.Berrylla:BAAANQADCgIIAgAAAA==.',
Bi='Bigdemon:BAAANQAECgIIAQAAAA==.Bigmakk:BAABNQAECoEfAAINAAgK0g2dKgCVAQANAAgK0g2dKgCVAQAAAA==.Bimzelx:BAAANQAECgIJAgAAAA==.Bipolar:BAAANQAECggIDAAAAA==.Bitterblood:BAABNQAECoEjAAIKAAcKYRvyUABUAgAKAAcKYRvyUABUAgAAAA==.',
Bl='Blastgamer:BAAANQAECgMIAwAAAA==.Blondebeard:BAABNQAECoEWAAIKAAgK7g9gagASAgAKAAgK7g9gagASAgAAAA==.',
Bo='Booshi:BAAANQAECgIIAgAAAA==.Bowiiesenpai:BAABNQAECoEdAAIOAAgKBiK/DQD6AgAOAAgKBiK/DQD6AgAAAA==.',
Br='Bragontix:BAACNQAFFIEHAAIFAAMKNB22BgAUAQAFAAMKNB22BgAUAQA1AAQKgR0AAgUACQpeG7kKAKkCAAUACQpeG7kKAKkCAAAA.Bravehearth:BAAANQADCgUICgABNQAECgYIBgAGAAAAAA==.Brewvoke:BAAANQAECgUJCQAAAA==.Brightxan:BAABNQAECoEuAAIPAAkKeBLvGgDtAQAPAAkKeBLvGgDtAQAAAA==.',
Bu='Bubbadruid:BAAANQADCgQIBAABNQAECggIIgAKADQkAA==.Bubbahunter:BAABNQAECoEiAAIKAAgKNCSpEgA/AwAKAAgKNCSpEgA/AwAAAA==.Bubbashaman:BAAANQADCgIIAgABNQAECggIIgAKADQkAA==.Buddahspanks:BAAANQADCgcIBQAAAA==.Buddahthai:BAABNQAECoErAAIQAAkKFh1aTgDUAgAQAAkKFh1aTgDUAgAAAA==.Buddhabum:BAABNQAECoEZAAIDAAgKlBFUZAAJAgADAAgKlBFUZAAJAgAAAA==.Budweaver:BAAANQADCgYICQAAAA==.Bus:BAABNQAECoEpAAIRAAkKySZhAADuAwARAAkKySZhAADuAwABNQAFFAYIFQAPAKYhAA==.Bussdefense:BAAANQADCggIHQAAAA==.Butterrs:BAAANQAFFAQICAAAAQ==.Butterz:BAAANQAECgIIBQABNQAFFAQICAAGAAAAAA==.',
Ca='Caleian:BAAANQAECgYIDAAAAA==.Caloren:BAABNQAECoEaAAISAAcKehiHIAArAgASAAcKehiHIAArAgAAAA==.Caorou:BAAANQAECgYIDwAAAA==.Carahpri:BAAANQAECgIIAgABNQAFFAYIDwATAH8dAA==.Cashaboo:BAAANQADCgYICwAAAA==.',
Ch='Charlyte:BAABNQAECoEYAAIEAAgK7xJ3UAAKAgAEAAgK7xJ3UAAKAgAAAA==.Charuzu:BAAANQADCgYIBgAAAA==.',
Co='Corneater:BAAANQAECgYIAQAAAA==.',
Cr='Crysinia:BAAANQADCgUICgAAAA==.',
Cu='Cuigy:BAABNQAECoEUAAMTAAYKiCBJRQAhAgATAAYKiCBJRQAhAgAUAAYKJBO/eQCFAQAAAA==.',
Cy='Cyriene:BAAANQAECgQICwAAAA==.Cyril:BAAANQAECgMIAgABNQAECgUIDgAGAAAAAA==.',
Da='Dagadin:BAAANQAECgYICgAAAA==.Dalio:BAAANQAECgUIBwAAAA==.Danté:BAAANQAECgQICQABNQAECggIIQADANcUAA==.Daraen:BAAANQADCgYIBwAAAA==.Daylen:BAAANQAECgUIEAAAAA==.',
Dd='Ddeathchura:BAAANQAECggIEAAAAA==.',
De='Deactrim:BAABNQAECoEYAAIHAAYKmhPmXABdAQAHAAYKmhPmXABdAQAAAA==.Deafknights:BAAANQAECgMIBAABNQAECggIDAAGAAAAAA==.Dema:BAAANQADCgQIBAAAAA==.Demonicflats:BAAANQADCgUIBQAAAA==.Demonodie:BAAANQABCggIDAAAAA==.Dendrada:BAAANQAECgUIEAAAAA==.Deuce:BAAANQAECgUIDwAAAA==.',
Di='Diogenes:BAAANQADCgQIBAAAAA==.Dizimo:BAAANQAECgUICgAAAA==.',
Dk='Dkflat:BAAANQADCgEIAQAAAA==.',
Do='Dogmeat:BAACNQAFFIEFAAIKAAIKJh75FwDAAAAKAAIKJh75FwDAAAA1AAQKgSQAAgoACQpOInMRAEcDAAoACQpOInMRAEcDAAE1AAUUBggVABUAvBcA.Doncowleone:BAAANQADCgMIAwABNQAECgYIBgAGAAAAAA==.Dotisa:BAAANQADCggICwAAAA==.',
Dr='Dragonlex:BAAANQADCgcIDQAAAA==.Drakeshadows:BAAANQADCgIIAgAAAA==.Drchivago:BAAANQADCgYICgAAAA==.Drdreadful:BAAANQABCgIIAgAAAA==.Drfumanchu:BAAANQADCgQIBAABNQAECgYIBgAGAAAAAA==.Druidtime:BAAANQAECggICAAAAA==.',
Du='Duna:BAAANQAECgUIDAAAAA==.Dungoofed:BAAANQAECgEJAQAAAA==.Duvidressra:BAABNQAECoEsAAMCAAkKwhltAgDdAgACAAkKwhltAgDdAgADAAIK1QdgDQFrAAAAAA==.',
Dx='Dxmvn:BAAANQADCgQIBQAAAA==.',
Ed='Edisonn:BAACNQAFFIEGAAIDAAMKwQ/LGwDnAAADAAMKwQ/LGwDnAAA1AAQKgSkAAwMACQoNHw4sALwCAAMACAqwHg4sALwCAAEABQr7EpkkAEMBAAAA.',
Eg='Eggies:BAAANQADCggIEwABNQAECgkJJgADAEEjAA==.',
Ek='Ektrim:BAAANQAECgEIAQABNQAECgYIGAAHAJoTAA==.',
El='Eladio:BAAANQADCgIIAgAAAA==.Eldarya:BAAANQAECgUICgAAAA==.Elentisa:BAAANQAECgQIBgAAAA==.Elghinn:BAABNQAECoEeAAIWAAcKzg9XOwCnAQAWAAcKzg9XOwCnAQAAAA==.Elissaria:BAAANQADCgQIBAAAAA==.Ellastrasza:BAABNQAECoEhAAIXAAcKXBQ7GQCeAQAXAAcKXBQ7GQCeAQAAAA==.Ellie:BAAANQAECgYIEwAAAA==.Elroy:BAABNQAECoEkAAIMAAgKUhE6iADjAQAMAAgKUhE6iADjAQAAAA==.',
Em='Embold:BAAANQADCggICAABNQAFFAQIEAAOANojAA==.Emernantus:BAABNQAECoEXAAIPAAcKzxTwIACwAQAPAAcKzxTwIACwAQAAAA==.',
Er='Erazar:BAABNQAECoEkAAQFAAgKYSHEBgAEAwAFAAgKYSHEBgAEAwAJAAIK/QM4QwBaAAAYAAEKjhqeHwA2AAAAAA==.',
Es='Espy:BAAANQAECgMIBAAAAA==.',
Eu='Eunbyeol:BAABNQAECoEXAAIZAAgKzh70BAC0AgAZAAgKzh70BAC0AgAAAA==.',
Ev='Evee:BAAANQABCgQIBAAAAA==.',
Fa='Faeria:BAAANQAECgYIEwAAAA==.Fatcritties:BAAANQAECgIIBAAAAA==.Fatnchunkydk:BAAANQAECgUIEAAAAA==.',
Fe='Feeblemind:BAAANQAECgUIDwAAAA==.Feli:BAABNQAECoEUAAMZAAYK2g1/EgBRAQAZAAYKYQ1/EgBRAQAaAAYK1wcHyQAwAQAAAA==.Felmommy:BAAANQADCggICAAAAA==.Femboi:BAAANQADCggIDgAAAA==.Fender:BAAANQAECgQICQAAAA==.',
Ff='Ffugntotems:BAAANQADCgcICwAAAA==.Ffviitifa:BAAANQADCgcICwAAAA==.',
Fi='Finfangfoom:BAAANQADCgQIBgABNQAECgYIBgAGAAAAAA==.Fingertoes:BAABNQAECoEfAAIQAAgKExxTcACHAgAQAAgKExxTcACHAgAAAA==.Fistbeard:BAAANQADCgUJBQABNQADCgcJCgAGAAAAAA==.Fizzlerazz:BAAANQADCgUIBQAAAA==.',
Fl='Flattulata:BAAANQADCgEJAQAAAA==.Flatulatta:BAABNQAECoEiAAIDAAgKXgygfADDAQADAAgKXgygfADDAQAAAA==.Flyciful:BAAANQAECgIJAgAAAA==.Flyingweasle:BAAANQADCgQIBwAAAA==.',
Fo='Forceed:BAEANQAECgEIAQABNQAECgUICgAGAAAAAA==.Forsythe:BAAANQABCgcICQAAAA==.Foxehh:BAAANQABCgUIBwAAAA==.Foxxycontin:BAAANQADCgEIAQAAAA==.',
Fr='Fraternaldk:BAACNQAFFIEIAAIbAAMKOwlSEQC+AAAbAAMKOwlSEQC+AAA1AAQKgSgAAhsACQo5IhQIAHADABsACQo5IhQIAHADAAAA.Fraturnal:BAAANQADCgIIAgAAAA==.Freestyle:BAAANQADCgcIDgAAAA==.Frodowagons:BAAANQAFFAQIBAAAAA==.Frostpie:BAABNQAECoEgAAIQAAkKMhTxcQCEAgAQAAkKMhTxcQCEAgAAAA==.',
Fu='Fuglybaby:BAAANQADCgcICwAAAA==.Fuhenhenka:BAAANQAECgMIAwAAAA==.Furyofheaven:BAAANQADCggICgAAAA==.',
Fw='Fwakos:BAAANQAECgUICwAAAA==.Fwakow:BAAANQADCgYIEAAAAA==.',
Ga='Gacke:BAAANQADCgEIAQABNQAECgcIHgAPAEchAA==.Gakmonk:BAAANQADCggJDgABNQAECgcIHgAPAEchAA==.Gakpaladin:BAABNQAECoEeAAIPAAcKRyHqDgCIAgAPAAcKRyHqDgCIAgAAAA==.Galaway:BAAANQAECgQICAAAAA==.Galthul:BAAANQADCgUIBQABNQAECgcIGgAUAMsYAA==.Garfyaz:BAAANQADCgYICwAAAA==.',
Gd='Gdlez:BAAANQAECgQIBQAAAA==.',
Ge='Gethael:BAAANQADCgIIAgAAAA==.',
Go='Goatroth:BAAANQAECgQIBgAAAA==.Golorious:BAABNQAECoEcAAMPAAkKSh11DwCAAgAPAAkK+ht1DwCAAgAMAAEK0xpYWQFPAAAAAA==.Goododie:BAAANQAECgUIDAAAAA==.',
Gr='Grayback:BAAANQAECggIBgABNQAECgkJHAASAIsbAA==.Grenas:BAAANQABCgQICQAAAA==.Grippyweasle:BAABNQAECoEeAAIHAAgKsRZLNwAMAgAHAAgKsRZLNwAMAgAAAA==.Grovelly:BAAANQABCggIEAAAAA==.Growlius:BAAANQADCgcIBwABNQAECgUJBQAGAAAAAA==.',
Gu='Gudit:BAAANQADCggICAABNQAECgYIBgAGAAAAAA==.Gulaken:BAAANQAECgUIDgAAAA==.Guseva:BAAANQAECgEIAQAAAA==.Guttershark:BAABNQAECoEaAAIcAAgKWx0CGwB8AgAcAAgKWx0CGwB8AgAAAA==.',
Ha='Hafnia:BAAANQAECgQIBwAAAA==.Halliday:BAAANQADCggIHAAAAA==.Haoasakura:BAABNQAECoEkAAIMAAkKqSIPHQA5AwAMAAkKqSIPHQA5AwAAAA==.Haylo:BAAANQAECgIIBAAAAA==.',
He='Headshop:BAAANQADCgcIEgAAAA==.Healzforfood:BAAANQAECgYIBwAAAA==.Heap:BAAANQAECgMIAwABNQAECggIFgAKAO4PAA==.Heartlight:BAAANQADCgMIAwAAAA==.Heavyreign:BAAANQADCgQIBwAAAA==.Helicobacter:BAAANQADCgYIBgAAAA==.Hewnoshaqa:BAAANQAECgUIEwAAAA==.Hexorcist:BAACNQAFFIEFAAMUAAMKtwppFgDjAAAUAAMKtwppFgDjAAATAAEKDxWjJABLAAA1AAQKgSAAAxMACQozH2sgAMkCABMACQozH2sgAMkCABQAAwpFGa7CAN4AAAAA.',
Hi='Hickerbilly:BAAANQADCgEIAQAAAA==.Hitormist:BAABNQAECoEZAAIdAAgK0hSbFQD0AQAdAAgK0hSbFQD0AQAAAA==.',
Ho='Holyanne:BAAANQADCgQIAgAAAA==.Holyspanks:BAAANQADCgYIBgABNQAECggIGwAeAC8eAA==.Horous:BAAANQAECgMIAQAAAA==.',
Hr='Hruuli:BAAANQADCgYIBgAAAA==.',
Hu='Huntrlicious:BAABNQAECoEgAAIKAAcK0w17hwDMAQAKAAcK0w17hwDMAQAAAA==.Husqvarnna:BAAANQAECgEIAQAAAA==.Huugor:BAAANQAECggIEAAAAA==.',
Ic='Icnips:BAAANQADCgUIBQAAAA==.Icoulddowork:BAAANQAECggICQABNQAECgkJGAAVACwgAA==.',
Id='Idoshiftwork:BAABNQAECoEYAAQVAAkKLCCxGADoAgAVAAgKziGxGADoAgAfAAIK3B+PUQCTAAAgAAIK2RJ7KQCEAAAAAA==.Idunno:BAAANQADCgYICQAAAA==.',
Ih='Ihriel:BAAANQADCgEJAQAAAA==.',
Ik='Ikazuchi:BAABNQAECoEWAAIIAAcK5Qs6QwBxAQAIAAcK5Qs6QwBxAQAAAA==.',
Il='Illcutabish:BAABNQAECoEiAAMcAAgKayScCAA2AwAcAAgKayScCAA2AwAhAAgKfhd6GgDyAQAAAA==.Illtank:BAAANQAECgUJBQAAAA==.',
Im='Imatankin:BAAANQAECgEIAgAAAA==.Imk:BAAANQAECgUIEAAAAA==.',
Io='Iock:BAEANQAECgUIBQAAAA==.',
Ir='Ironarms:BAAANQAECgYJEwAAAA==.',
Is='Ishido:BAAANQADCgYIBgAAAA==.',
Je='Jennypoo:BAABNQAECoEcAAIfAAcKUBR3JgC+AQAfAAcKUBR3JgC+AQAAAA==.Jessd:BAAANQADCgcJBwAAAA==.',
Ji='Jinuoo:BAAANQADCgQIBAAAAA==.',
Jo='Johnwarrior:BAABNQAECoEeAAIZAAgKah6KBADJAgAZAAgKah6KBADJAgAAAA==.Jorrix:BAABNQAECoEZAAIMAAcKMAn3xABZAQAMAAcKMAn3xABZAQAAAA==.',
Ju='Juduspriestt:BAAANQAECgYIEwAAAA==.',
Jy='Jynaxa:BAAANQADCgEIAQAAAA==.',
['Jä']='Jägermeister:BAAANQADCgYJDAAAAA==.',
Ka='Kaaeko:BAAANQAECgcIDgAAAA==.Kalerito:BAABNQAECoEZAAIfAAcKkSEKFACJAgAfAAcKkSEKFACJAgAAAA==.Kallythea:BAAANQADCggICAAAAA==.Kardie:BAAANQADCgQIBAABNQAECggIJAAFAGEhAA==.Karl:BAAANQAECgMIBwAAAA==.Kaserr:BAACNQAFFIEXAAMhAAcK3RqDAgAfAgAhAAYK8xiDAgAfAgAcAAUKABoQBADJAQA1AAQKgSwAAyEACQrPJbMFACMDACEACAq+JbMFACMDABwABQrqJLgsAP8BAAAA.Kayserdh:BAAANQAECgUICAAAAA==.Kazaf:BAABNQAECoEZAAIHAAcKdRcgQADfAQAHAAcKdRcgQADfAQAAAA==.Kazrik:BAAANQAECgUIBQAAAA==.',
Ke='Kebru:BAAANQAECgYIEQAAAA==.Keitrek:BAABNQAECoEeAAIEAAcKNwydfQB3AQAEAAcKNwydfQB3AQAAAA==.Kelthias:BAAANQADCgYJDQAAAA==.Kenje:BAAANQADCgIIAgAAAA==.Kerwîck:BAAANQAECgcIEwAAAA==.Keyen:BAAANQAECgUIDgAAAA==.',
Kh='Kheiko:BAAANQAECgUIBQAAAA==.',
Ki='Kibalion:BAAANQAECgYIEQAAAA==.Killbent:BAAANQAECgQIBQAAAA==.Kinnky:BAAANQAECgYIEgAAAA==.Kino:BAAANQAECgUIDgAAAA==.Kitn:BAAANQABCgQIBAAAAA==.Kityana:BAAANQADCgIIAgAAAA==.',
Kp='Kpop:BAAANQADCgIIAwAAAA==.',
Kr='Krasdan:BAAANQAECgIIAgAAAA==.Kreettip:BAABNQAECoEeAAIiAAcK/xrpSgAcAgAiAAcK/xrpSgAcAgAAAA==.Krispy:BAAANQADCgcJBwABNQAECggIJQAJADobAA==.',
Ks='Ksp:BAAANQADCgQIBQAAAA==.',
Ku='Kugamoo:BAABNQAECoEbAAMVAAkKPxWjNwAHAgAVAAgKRxOjNwAHAgAfAAcKZAd6MwBKAQAAAA==.Kulgan:BAABNQAECoEkAAMiAAkKVRovNAB2AgAiAAkKVRovNAB2AgAjAAEKJxF4JQA0AAAAAA==.Kurgen:BAAANQAECgUIDAAAAA==.Kuroda:BAAANQAECgQIBwAAAA==.Kurolucifer:BAAANQADCgcIFgAAAA==.',
Ky='Kylex:BAAANQAECgMIBwAAAA==.',
['Kä']='Käßoom:BAAANQAECgQIBQAAAA==.',
La='Lamiah:BAAANQAECgQIBAAAAA==.Laredemos:BAAANQADCgIIAgAAAA==.Lauadia:BAAANQAECgIJAgAAAA==.',
Lc='Lckdown:BAAANQAECggICwAAAA==.',
Le='Legomyegolas:BAAANQADCgYJBgAAAA==.Lelaeh:BAAANQAECgcIBwAAAA==.',
Li='Lightsocket:BAAANQADCgYJCAABNQAECgIJAgAGAAAAAA==.Lishy:BAAANQADCgEIAQAAAA==.Livingkntpib:BAAANQADCggICAAAAA==.',
Lo='Lockedout:BAAANQAECgMIAwABNQAECggIJAAQAMgiAA==.Loden:BAAANQAECgcIDAAAAA==.Lodez:BAAANQAFFAEIAgAAAA==.Loktarhogar:BAAANQAECgUICAAAAA==.Lostadin:BAAANQADCgIIAgAAAA==.Lovi:BAABNQAECoEfAAITAAkKRRBsZQCtAQATAAkKRRBsZQCtAQAAAA==.',
Lu='Luck:BAAANQAECgQIBAABNQAECgQIBAAGAAAAAA==.Luckyboi:BAABNQAECoEgAAQVAAgKDAhHVABdAQAVAAgK1gdHVABdAQAfAAcKLgZoNwAsAQAXAAQKvQVSOgCQAAAAAA==.Lumeria:BAAANQAECgUICgAAAA==.Lumina:BAAANQAECgcIEgAAAA==.Lusciifi:BAACNQAFFIEOAAMMAAYKJR6nBQDYAQAMAAUKwh6nBQDYAQAPAAIKmhDJCQCBAAA1AAQKgTIAAwwACQobJu0IAKoDAAwACQoYJu0IAKoDAA8ABgpCIx4VADICAAAA.',
Ly='Lykie:BAABNQAECoEeAAIPAAgKZB0eEQBmAgAPAAgKZB0eEQBmAgAAAA==.Lynxic:BAAANQAECgMIAwAAAA==.Lyone:BAAANQAECgUIEgAAAA==.',
['Lä']='Lävey:BAAANQADCgEIAQAAAA==.',
['Lé']='Léxa:BAAANQADCgYICgAAAA==.',
['Lú']='Lúvaa:BAAANQAECgcIEwAAAA==.',
Ma='Macavity:BAAANQADCgMIAwAAAA==.Madmanmike:BAAANQADCgIIAgAAAA==.Magalis:BAAANQAECgQIDQAAAA==.Magicwoman:BAAANQAECgUICwAAAA==.Magikkisback:BAAANQAECgQIAwAAAA==.Magsh:BAAANQADCggIJAAAAA==.Mandorius:BAAANQAECgUICwAAAA==.Maphra:BAAANQADCggJCAABNQAECggIGQAdANIUAA==.Marcos:BAAANQADCgIIAgAAAA==.Marl:BAAANQAECgEIAgAAAA==.Marvolo:BAAANQAECggIDgABNQAECgkJHAASAIsbAA==.Maverickdog:BAABNQAECoEdAAQLAAgKdh6DKQDdAQALAAcKQBuDKQDdAQAkAAQKXBQ9CwAPAQAKAAMKayT76gD7AAAAAA==.',
Mc='Mchammerwork:BAAANQAECgUIBwABNQAECgkJGAAVACwgAA==.',
Me='Mechunter:BAAANQADCgYIBgABNQAECgMIBAAGAAAAAA==.Meekzz:BAABNQAECoEUAAIiAAYKjxzJTgAOAgAiAAYKjxzJTgAOAgAAAA==.Meeshie:BAABNQAECoFEAAQiAAkKmBc0MQCCAgAiAAkKmBc0MQCCAgAOAAUKtg6tOwAjAQAjAAIK5QVZHwBSAAAAAA==.Melodrop:BAAANQAECggIBQAAAA==.',
Mi='Mihawk:BAAANQADCgEIAQABNQAECggIHwAQABMcAA==.Mikexfire:BAABNQAECoEZAAIWAAgKlA0tNwDDAQAWAAgKlA0tNwDDAQAAAA==.Mikuzume:BAAANQADCgYIBgAAAA==.Mildchaos:BAAANQAECggJAQAAAA==.Mimic:BAAANQADCgIIAgAAAA==.Mishima:BAAANQAECggICAAAAA==.Misspell:BAAANQADCggJFAAAAA==.Miznewbooty:BAABNQAECoEbAAIOAAkKpRNjGwBJAgAOAAkKpRNjGwBJAgAAAA==.',
Mo='Moochella:BAAANQAECgUIDQAAAA==.Moojestic:BAAANQADCggIDwAAAA==.Moonflungpoo:BAAANQAECgEIAQAAAA==.Moonq:BAAANQAECgUIEAAAAA==.Moosie:BAABNQAECoEdAAIlAAcKiw8NEQBuAQAlAAcKiw8NEQBuAQAAAA==.Moosifer:BAAANQADCgQIBAABNQAFFAMIBQAUALcKAA==.Mooska:BAAANQAECgEIAQABNQAECgcIHQAlAIsPAA==.Mostunknown:BAAANQADCgYIBgAAAA==.Moxflip:BAAANQAECgcICQAAAA==.Moxtsm:BAAANQAECgMIBAAAAA==.Mozzers:BAAANQADCgcIBwAAAA==.',
Mu='Muertenegra:BAAANQADCgUIBQABNQAECgYIEwAGAAAAAA==.Muffy:BAAANQAECgUIDwAAAA==.Muln:BAAANQADCggIBwAAAA==.Murlouh:BAAANQADCgQIBAAAAA==.',
My='Mydevil:BAAANQADCgQIBAAAAA==.Myllakura:BAAANQAECgQICQABNQAECggICwAGAAAAAA==.Mystk:BAAANQADCgIIAgAAAA==.Mythnarra:BAACNQAFFIEGAAMWAAMKBxQNDgDlAAAWAAMKBxQNDgDlAAASAAIKggQYEABrAAA1AAQKgSAAAxIACQoHIl8JADYDABIACQoHIl8JADYDABYABAp7Gu1JAEQBAAAA.',
['Mä']='Mäomäo:BAAANQADCgMIAwAAAA==.',
['Mí']='Mísanthrope:BAAANQADCgQIBAABNQAECgQIBgAGAAAAAA==.',
['Mò']='Mòrpheus:BAAANQAECgEIAQABNQAECggIIQADANcUAA==.',
Na='Nadíne:BAABNQAECoEdAAIQAAcKYhN+xADYAQAQAAcKYhN+xADYAQAAAA==.Nanukimon:BAAANQAECgUIDAAAAA==.Narawe:BAAANQAECgEIAQABNQAECgkJIQATAKgaAA==.Nastymccasty:BAAANQAECggIAwABNQAECggIIgAcAGskAA==.Naughtgelic:BAAANQADCgYICgAAAA==.',
Ne='Nedgamingttv:BAEANQAECgUICgAAAA==.Nekrimah:BAAANQAECgYIDAABNQAECgcIBwAGAAAAAA==.Nerph:BAAANQADCgYIEQAAAA==.Nevaera:BAAANQADCgYIDAAAAA==.',
Ni='Ni:BAAANQAECgQIBAAAAA==.Nick:BAACNQAFFIEPAAMHAAQKbhI8EwDzAAAbAAQKbhJ2DAAZAQAHAAQKnws8EwDzAAA1AAQKgSsAAxsACQr4Jd8NADQDABsACQr4Jd8NADQDAAcAAwpPF2ODAMkAAAAA.Nikor:BAEANQAECgcICwAAAA==.',
Nm='Nmue:BAAANQADCgIIAgAAAA==.',
No='Nokorii:BAAANQAECgUIDAAAAA==.Nomecoma:BAAANQAECgYIEwAAAA==.Nonok:BAAANQADCgIIAgAAAA==.Nookah:BAAANQAECgYIBgABNQAECgkJLQAKACgeAA==.Noshom:BAABNQAECoEaAAMTAAcKJCIJKACiAgATAAcKJCIJKACiAgAUAAIKyQXU+gBdAAAAAA==.Notches:BAAANQADCgEIAQAAAA==.',
Ns='Nsyncrogue:BAAANQADCgYJBgAAAA==.',
Ny='Nymful:BAAANQAECgUIEAAAAA==.',
['Nè']='Nèlo:BAABNQAECoEUAAIaAAYKOA6CugBZAQAaAAYKOA6CugBZAQAAAA==.',
Ob='Obianstrider:BAAANQADCgYIFQAAAA==.',
Oc='Oceanspell:BAABNQAECoEkAAImAAYKtiJ0BwBJAgAmAAYKtiJ0BwBJAgAAAA==.',
Og='Oggleboggle:BAAANQADCgEIAQAAAA==.',
Ol='Oldbuse:BAABNQAECoEeAAMeAAgKmiBUCQDOAgAeAAgKmiBUCQDOAgAUAAEK1BjYBwFEAAAAAA==.',
On='Onlytoez:BAAANQAECgQICAABNQAECgkJRAAiAJgXAA==.',
Or='Orave:BAAANQAECgUICQAAAA==.Oromë:BAAANQABCgQIBAAAAA==.Orzik:BAAANQADCgcIBwAAAA==.',
Os='Osox:BAAANQAECggICAAAAA==.Ostena:BAAANQAECgYIEQAAAA==.Osteole:BAABNQAECoEUAAMOAAUKwgcARADsAAAOAAUKwgcARADsAAAiAAMKCALVzgBtAAABNQAECgYIEQAGAAAAAA==.',
Ou='Oulawdpriest:BAACNQAFFIEHAAIOAAQK1Qj/CQAiAQAOAAQK1Qj/CQAiAQA1AAQKgSIAAw4ACQrOF2gaAFUCAA4ACQrOF2gaAFUCACIAAQpjE1LgADUAAAAA.',
Ov='Overture:BAAANQAECgMIAwAAAA==.',
Ow='Owthatburns:BAAANQADCgYIBgAAAA==.',
Pa='Pakszdude:BAAANQADCgUIBQAAAA==.Pandamonious:BAAANQADCggICAABNQAECgEIAgAGAAAAAA==.Papawoof:BAAANQADCgQJBQABNQAFFAMIBQAUALcKAA==.Parkour:BAAANQAECgMIBQAAAA==.Paullyfists:BAABNQAECoEVAAINAAgKoyGADwDPAgANAAgKoyGADwDPAgAAAA==.',
Pe='Peni:BAAANQAECgIIAgAAAA==.',
Pi='Pintobeans:BAAANQAECgEIAgAAAA==.',
Po='Popkorn:BAACNQAFFIEXAAMSAAcKFyI9AgBLAgASAAYKEiE9AgBLAgAlAAMKuSDKAQAlAQA1AAQKgSwAAxIACQqsJpcAAPMDABIACQqTJpcAAPMDACUAAgptIjMbANAAAAAA.Popkourne:BAAANQAECggIDQABNQAFFAcIFwASABciAA==.Poplocks:BAAANQADCgYICgAAAA==.Porrana:BAAANQAECgcIDwAAAA==.Powaqa:BAAANQAECgUIEAAAAA==.',
Pr='Praetorian:BAABNQAECoEcAAIMAAgKwg89kQDNAQAMAAgKwg89kQDNAQAAAA==.Praxxus:BAAANQADCgYIBgAAAA==.',
Ps='Psy:BAAANQAECggIAgAAAA==.',
Py='Pyrahna:BAAANQADCgYIBgABNQAECgQIBQAGAAAAAA==.',
Qm='Qmen:BAAANQADCgIIAgAAAA==.',
Qu='Quasient:BAABNQAECoEhAAIQAAgKTx5JWwC2AgAQAAgKTx5JWwC2AgAAAA==.Quethelos:BAAANQADCgcIHwAAAA==.Quickbrew:BAAANQAECgUIBQAAAA==.Quickspell:BAAANQAECgcIEAAAAA==.',
Ra='Raalcar:BAAANQAECgMIAwABNQAECgYICwAGAAAAAA==.Raedyyn:BAAANQAECgYICQAAAA==.Ragarninn:BAAANQAECgIIAgABNQAECgkJLAATADclAA==.Ragarth:BAAANQAECgEIAQAAAA==.Ragendecay:BAAANQAECgUIDQAAAA==.Ragequits:BAACNQAFFIEcAAIaAAgKbSS0AAAYAwAaAAgKbSS0AAAYAwA1AAQKgSUAAhoACQpFJtUMAIwDABoACQpFJtUMAIwDAAAA.Ragewar:BAAANQABCgcIDAAAAA==.Rakshassa:BAAANQAECgYICgAAAA==.Ralcar:BAAANQAECgYICwAAAA==.Rawkphyst:BAAANQADCgQIAgAAAA==.Razrscale:BAAANQAECgEIAQAAAA==.',
Re='Redhuntsman:BAAANQAECgEIAQAAAA==.Regrow:BAAANQADCgcIBwABNQAECgMIBAAGAAAAAA==.Reska:BAAANQAECgQIBQAAAA==.',
Rh='Rholdentodor:BAAANQADCgEIAQABNQAECgcIKQAQANEUAA==.',
Ri='Rindorin:BAAANQAECgYIDAAAAA==.Ritarepulsa:BAAANQADCgYIDAAAAA==.',
Ro='Rohra:BAABNQAECoEXAAIfAAcKTArrNAA/AQAfAAcKTArrNAA/AQAAAA==.Roral:BAAANQAECgEIAQABNQAECgQIBgAGAAAAAA==.Rosiee:BAAANQAECgQIBQABNQAECggIHwANANINAA==.Rozynwen:BAAANQAECgEIAQAAAA==.',
Ru='Ruah:BAAANQABCgMIAwAAAA==.Rubmytoes:BAAANQAECgEJAQAAAA==.Rukuna:BAAANQAECgEIAQAAAA==.Runecast:BAABNQAECoEjAAIIAAgKYBkrIQBYAgAIAAgKYBkrIQBYAgAAAA==.',
Sa='Saelyrinth:BAAANQAECgEIAQABNQAECgUICgAGAAAAAA==.Salamence:BAAANQADCggIDwABNQAECgYIFwAGAAAAAQ==.Sambor:BAAANQAECggIDwAAAA==.Sarapheena:BAABNQAECoEcAAITAAkKXxs0IgDAAgATAAkKXxs0IgDAAgAAAA==.Sarouk:BAABNQAECoEhAAIaAAgKphcyaAA4AgAaAAgKphcyaAA4AgAAAA==.Satanbomb:BAAANQAECgIIBAAAAA==.Satansbride:BAAANQAECgYIBgABNQAECgYIBgAGAAAAAA==.Saterli:BAABNQAECoEdAAMiAAkK6haPNgBsAgAiAAkK6haPNgBsAgAOAAEKZQKbeAAkAAAAAA==.Saturno:BAAANQAECgEIAQAAAA==.Saucypirate:BAABNQAECoEaAAMmAAgKHRHdEQBgAQAQAAgKTgrJzgDDAQAmAAYKZhPdEQBgAQAAAA==.Sayygurl:BAAANQAECgUIBgAAAA==.',
Sc='Scalvert:BAABNQAECoEpAAIQAAcK0RTpvgDiAQAQAAcK0RTpvgDiAQAAAA==.Scalypanda:BAABNQAECoEWAAMYAAgK8A7YCQCvAQAYAAgK3g3YCQCvAQAFAAYKKQlbIQAmAQAAAA==.Scamander:BAABNQAECoEcAAISAAkKixvPEADXAgASAAkKixvPEADXAgAAAA==.Scoobs:BAAANQADCgQIBAABNQAECgQIBgAGAAAAAA==.Screamsalot:BAAANQAECgEIAQAAAA==.Sculi:BAABNQAECoEcAAIKAAcKERIqfwDgAQAKAAcKERIqfwDgAQAAAA==.',
Se='Seiishiro:BAAANQAECgQIBAAAAA==.Seldon:BAAANQAECgUIEAAAAA==.Senyor:BAABNQAECoEfAAIPAAkKThUPFQAzAgAPAAkKThUPFQAzAgAAAA==.Seradormi:BAAANQADCgMIAwAAAA==.Seraphiel:BAAANQAECgQICAABNQAECgYICwAGAAAAAA==.Serelyth:BAAANQADCgMIAwABNQAECggIJAAQAMgiAA==.Serfort:BAAANQADCgUICwAAAA==.',
Sh='Shadowpaksz:BAAANQAECgYIEwAAAA==.Shadowsneak:BAAANQAECgYIDwAAAA==.Shadowvixen:BAAANQAECgMIBAAAAA==.Shaelistra:BAAANQAECgUIEAAAAA==.Shalilama:BAABNQAECoEsAAITAAkKNyUhAgC5AwATAAkKNyUhAgC5AwAAAA==.Shamanana:BAABNQAECoEYAAIeAAkK3AnbEQArAgAeAAkK3AnbEQArAgAAAA==.Shamboli:BAAANQADCggIEgAAAA==.Shamirah:BAAANQADCgcJCQAAAA==.Shaï:BAAANQAECgUICQAAAA==.Shenderp:BAAANQAECgYICwAAAA==.Shinerbock:BAABNQAECoEbAAInAAcKSwwEFwBPAQAnAAcKSwwEFwBPAQAAAA==.Shockitti:BAAANQAECgIIAgAAAA==.Shtark:BAAANQAECgIIAwAAAA==.',
Si='Sianvar:BAAANQAECggIDAAAAA==.Silshara:BAABNQAECoEeAAIJAAkKEA2AGwDzAQAJAAkKEA2AGwDzAQAAAA==.Silverjustis:BAAANQAECgUIEAAAAA==.Siwe:BAABNQAECoEaAAMUAAcKyxjqUgAAAgAUAAcKyxjqUgAAAgATAAEKlRHP/wA5AAAAAA==.Six:BAAANQAECgIIAgABNQAECgMIAwAGAAAAAA==.',
Sk='Skip:BAAANQADCgMIAwAAAA==.Skribblez:BAABNQAECoEkAAMMAAgKDRu7WwBaAgAMAAgKDRu7WwBaAgAEAAQKJBS6qwD9AAAAAA==.Skyanna:BAAANQAECgEIAQAAAA==.',
Sl='Slackback:BAAANQAECggIBwABNQAFFAMIBgAUAMUQAA==.Sloop:BAAANQADCgYIEAAAAA==.Sloot:BAAANQAECgcIDwAAAA==.',
Sn='Sneasel:BAAANQAECgMIBAABNQAECgQIBAAGAAAAAA==.Snoogins:BAAANQADCgUIDgABNQAECgYIBgAGAAAAAA==.',
So='Sockszz:BAABNQAECoEnAAIgAAgKNSYlAgCIAwAgAAgKNSYlAgCIAwAAAA==.Songblade:BAAANQABCgcICgAAAA==.Soulsy:BAABNQAECoEcAAIMAAcKiCL4UQB2AgAMAAcKiCL4UQB2AgAAAA==.Soulvalk:BAAANQADCgQIBAAAAA==.Sourmagic:BAABNQAECoEaAAIQAAgKuhGYrwABAgAQAAgKuhGYrwABAgAAAA==.',
Sp='Splendorae:BAABNQAECoEYAAIEAAgKXxY+PQBSAgAEAAgKXxY+PQBSAgAAAA==.Sprints:BAABNQAECoEgAAITAAgKuxJZYAC+AQATAAgKuxJZYAC+AQAAAA==.Spritz:BAABNQAECoEoAAMUAAgKUiL1JwDBAgAUAAcKLyL1JwDBAgATAAgKZB45JwCnAgAAAA==.Sprucewillis:BAAANQADCgQICQABNQAECgYIBgAGAAAAAA==.Spyderelite:BAABNQAECoEZAAIBAAcKZRJdEQDjAQABAAcKZRJdEQDjAQAAAA==.',
Sq='Squirrel:BAAANQAECgYIEgAAAA==.',
Ss='Ssuperss:BAAANQADCgQICgAAAA==.',
St='Stabbot:BAAANQAECgMJAwABNQAECggIGQAdANIUAA==.Stankstarstu:BAAANQAECgYIBgAAAA==.Starblood:BAAANQABCgMIAwAAAA==.Starspeaker:BAAANQAECgQICAAAAA==.Stellf:BAAANQADCgYIBgAAAA==.Stompmyballs:BAAANQAECgYIEgABNQAFFAgIHAAaAG0kAA==.Stoogotz:BAAANQADCgIIBAAAAA==.Studlebane:BAAANQAECgUIBQAAAA==.Studlepalm:BAAANQAECgMIBgABNQAECgUIBQAGAAAAAA==.',
Su='Sundaresh:BAAANQADCgEIAQAAAA==.Sunwing:BAABNQAECoEYAAIiAAgKRyFWIQDNAgAiAAgKRyFWIQDNAgAAAA==.Supersasian:BAAANQAECgcIBwAAAA==.Supersheep:BAAANQAECgUICwAAAA==.Suvien:BAAANQAECgEIAQAAAA==.',
Sy='Sylvarian:BAAANQAECgYIEwAAAA==.Sylvinna:BAAANQADCggIFQAAAA==.',
Ta='Tagda:BAAANQADCggJCAAAAA==.Takeurland:BAAANQADCgQIBQAAAA==.Taterdotz:BAAANQAECgIIAgAAAA==.Tatersack:BAAANQABCgUIBQAAAA==.Tatortwats:BAAANQAFFAEIAwAAAA==.Taxdeeznutz:BAAANQADCgUIBQAAAA==.',
Te='Tengrit:BAAANQADCgcIDgAAAA==.Tephine:BAABNQAECoEbAAIeAAgKLx7ZCgCvAgAeAAgKLx7ZCgCvAgAAAA==.Tepicoyotl:BAABNQAECoEhAAMTAAkKqBpMIgC/AgATAAkKqBpMIgC/AgAUAAEKiAC4PAEYAAAAAA==.',
Th='Thaymor:BAAANQADCgcJCgAAAA==.Thebigkitti:BAAANQADCgEIAQAAAA==.Thelonecone:BAABNQAECoEuAAIIAAkKlSRZBACNAwAIAAkKlSRZBACNAwAAAA==.Theodor:BAAANQAECgMIBAAAAA==.Theoganth:BAAANQAECgMIBAABNQAECggIIQADANcUAA==.Theraphee:BAAANQADCgcIFwAAAA==.Therym:BAAANQADCgEIAQABNQAECggIGAAHADEPAA==.Thomwizard:BAAANQADCggIFAAAAA==.Thormorn:BAAANQAECgUIBQAAAA==.Thunnha:BAAANQADCgYJEwAAAA==.',
Ti='Tierali:BAAANQAECgEIAQAAAA==.Tio:BAAANQADCggIGwAAAA==.',
To='Toastedsushi:BAAANQADCgYIBgAAAA==.Toofwess:BAAANQAECgIIAwABNQAECggIGQAdANIUAA==.Torrinchaos:BAAANQADCgQIBAAAAA==.Tosala:BAAANQAECgMIBQAAAA==.Totemkiller:BAAANQAECgQIDgAAAA==.',
Tr='Traael:BAAANQAECggIEwAAAA==.Treesap:BAABNQAECoEZAAIoAAgKuiCMAwDbAgAoAAgKuiCMAwDbAgAAAA==.Trinityeve:BAAANQAECgQICQAAAA==.Trmz:BAAANQAECggIDAAAAA==.Trnzlock:BAAANQAECgYIDwABNQAECggIDAAGAAAAAA==.Trîggêr:BAAANQADCgYIBgAAAA==.',
Tu='Tulanii:BAAANQADCgcICQAAAA==.Tularana:BAAANQAECggIEAAAAA==.Tumble:BAAANQAECgQICAAAAA==.',
Tw='Twignberryz:BAAANQAECgQIBQABNQAECgYIBgAGAAAAAA==.Twinkie:BAAANQAECgYIDAAAAA==.Twodogz:BAAANQAECgYIEwAAAA==.',
Ty='Tyious:BAABNQAECoEfAAQIAAkKcha2LgD1AQAIAAgKDxa2LgD1AQAbAAUKXhGikADBAAAHAAEKnwPMwwApAAAAAA==.Tyndara:BAAANQAECgUIEAAAAA==.Tyìous:BAAANQADCgcIBgAAAA==.',
['Tü']='Tüesdaÿ:BAAANQAECgQIBQAAAA==.',
Ub='Ubavoke:BAAANQAECgYICAAAAA==.',
Uk='Ukita:BAABNQAECoEnAAIMAAkKgCE2MQDmAgAMAAkKgCE2MQDmAgAAAA==.',
Ur='Ursane:BAABNQAECoEnAAMaAAgKKhjrWwBbAgAaAAgKKhjrWwBbAgAZAAQK1AhEHgCpAAAAAA==.Ursully:BAAANQAECgUIEAAAAA==.',
Uz='Uzi:BAABNQAECoEZAAIBAAYKahcpEwDPAQABAAYKahcpEwDPAQAAAA==.',
Va='Valentíne:BAAANQADCgYIDAAAAA==.Valhalla:BAAANQAECgMIBgAAAA==.Vanncint:BAAANQAECgUICQAAAA==.Vashie:BAAANQADCgYICgAAAA==.',
Ve='Vexus:BAACNQAFFIEGAAIUAAMKxRDHFADyAAAUAAMKxRDHFADyAAA1AAQKgRwAAhQACQpBHNcpALYCABQACQpBHNcpALYCAAAA.',
Vi='Vinecone:BAAANQAECgQIBAAAAA==.Vivifyght:BAAANQAECgEIAQAAAA==.Vixly:BAAANQADCgUIEgAAAA==.',
Vl='Vladios:BAABNQAECoEYAAIMAAYKLwXf9AD6AAAMAAYKLwXf9AD6AAAAAA==.',
Vo='Voidmommy:BAAANQADCgYIDAABNQAECgUICgAGAAAAAA==.Vordarian:BAAANQAECgEIAQAAAA==.',
Wa='Wardrak:BAAANQAECgIIAwAAAA==.Warlokholmes:BAAANQADCgIIAgAAAA==.Warrax:BAAANQADCgcIEAAAAA==.Watchmeburst:BAAANQADCgYICAAAAA==.',
We='Wezleydoomz:BAAANQADCgYIBgABNQAECggIIgAKACUiAA==.',
Wh='Whaler:BAAANQAECggIEwAAAA==.',
Wi='Windeagle:BAAANQADCgQIBAABNQAECgUJBQAGAAAAAA==.Windowskey:BAAANQAECgYIAwABNQAECggIEgAGAAAAAA==.',
Wu='Wuzntmyfault:BAAANQAECgMIBAAAAA==.',
Wy='Wyldfyire:BAAANQAECgYIEwAAAA==.',
Xa='Xaven:BAAANQAECgUIDgAAAA==.Xavenuke:BAAANQADCgcJDQABNQAECgUIDgAGAAAAAA==.',
Xi='Xiaotao:BAAANQAECgMIAwAAAA==.',
Xt='Xtraxtra:BAAANQADCggICQABNQAECggIJQAJADobAA==.',
Ye='Yellenheller:BAAANQAECgIIAgABNQAECgkJIAAQADIUAA==.',
Yo='Yoan:BAAANQAECggICwAAAQ==.Yoga:BAAANQAECgQICAAAAA==.',
Za='Zabra:BAAANQADCggJFQAAAA==.Zahshia:BAAANQAECgUICQAAAA==.Zalarian:BAAANQADCgEIAQAAAA==.Zaldina:BAAANQADCgIIAgAAAA==.Zathaeus:BAACNQAFFIEMAAISAAUKGhOgBgCPAQASAAUKGhOgBgCPAQA1AAQKgR8AAhIACQqhGy0RANMCABIACQqhGy0RANMCAAAA.Zaylian:BAABNQAECoEhAAIWAAkKdBopGwCcAgAWAAkKdBopGwCcAgAAAA==.Zayragossa:BAABNQAECoEmAAMDAAkKQSOzBgCJAwADAAkKQSOzBgCJAwABAAIKTSFWPwC7AAAAAA==.Zayrah:BAAANQAECgUIBwABNQAECgkJJgADAEEjAA==.',
Ze='Zeerkk:BAABNQAECoEcAAMBAAcKGhjrJABBAQABAAQKmhvrJABBAQADAAQKVxNkzwD9AAAAAA==.Zergmark:BAAANQADCgUIBgAAAA==.',
Zi='Zirilian:BAAANQADCgQICAABNQAECgYIEwAGAAAAAA==.',
Zo='Zoomzoom:BAAANQAECgUJBgABNQAFFAQIBwAOANUIAA==.Zouris:BAAANQAECgIIAwABNQAECgQIBgAGAAAAAA==.',
Zu='Zulkraa:BAAANQAECgQICAAAAA==.',
Zy='Zynreth:BAAANQADCgIIAgAAAA==.',
['Ài']='Àirén:BAABNQAECoEaAAQOAAgKdCFXEADYAgAOAAgKdCFXEADYAgAiAAEKhxt43gA7AAAjAAEKRhBdIwA6AAAAAA==.',
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
