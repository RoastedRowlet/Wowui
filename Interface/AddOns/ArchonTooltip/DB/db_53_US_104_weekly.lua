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

local lookup = {'Evoker-Devastation','Evoker-Preservation','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Retribution','Unknown-Unknown','Paladin-Protection','Mage-Arcane','Warlock-Demonology','Warrior-Protection','Paladin-Holy','Warlock-Destruction','Druid-Balance','Warlock-Affliction','Druid-Guardian','Priest-Shadow','Evoker-Augmentation','DeathKnight-Unholy','DemonHunter-Devourer','Rogue-Assassination','Shaman-Restoration','Shaman-Elemental','Rogue-Subtlety','Warrior-Fury','DeathKnight-Blood','Druid-Restoration','Priest-Holy','Hunter-Survival','Priest-Discipline','Mage-Frost','Shaman-Enhancement','DemonHunter-Vengeance','Warrior-Arms','DeathKnight-Frost','Monk-Brewmaster','Druid-Feral','Rogue-Outlaw','DemonHunter-Havoc',}
local provider = {region='US',realm='Garona',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aartoo:BAAANQABCggICQAAAA==.',
Ac='Acherona:BAAANQABCgQIBAAAAA==.Acuminada:BAAANQADCgIIAgAAAA==.Acuna:BAAANQAECgUIDAAAAA==.',
Ad='Adison:BAAANQADCgYIBgAAAA==.',
Af='Affliction:BAAANQAECgYIDwAAAA==.',
Ai='Airz:BAAANQAECgIJBgAAAA==.',
Ak='Akâkiôs:BAAANQAECgUIDQAAAA==.',
Al='Aladorman:BAAANQAECgQIBQAAAA==.Alamo:BAAANQAECgUICAAAAA==.Albertlin:BAAANQAECgcICwAAAA==.Alexinar:BAAANQAECgEIAQAAAA==.',
Am='Amakuagsak:BAAANQAECgUIBQAAAA==.Amicus:BAAANQAECgQIBwAAAA==.Ampmage:BAAANQAECgMIBQAAAA==.Ampsdk:BAAANQADCgYIBgAAAA==.',
An='Anthren:BAAANQADCgUIBQAAAA==.Antihose:BAAANQABCgQJBAAAAA==.',
Ap='Apollo:BAAANQAECgYIEwAAAA==.Apolynnæ:BAABNQAECoEZAAIBAAcKShiuEQD6AQABAAcKShiuEQD6AQAAAA==.',
Ar='Araniss:BAAANQAECgYIDwAAAA==.Arasthel:BAAANQADCggIFAAAAA==.Aratrath:BAABNQAECoEeAAICAAgK4RorDwCJAgACAAgK4RorDwCJAgAAAA==.Aryasilly:BAAANQAECgYIDwAAAA==.',
As='Asdi:BAAANQAECgMIAwAAAA==.Ashe:BAACNQAFFIELAAIDAAQK+h8ACQBnAQADAAQK+h8ACQBnAQA1AAQKgScAAgMACQrzJFwDAJMDAAMACQrzJFwDAJMDAAAA.',
At='Athenix:BAAANQAECggIBgAAAA==.Attabubble:BAAANQAECgEIAQABNQAECgkJJAAEAPAcAA==.Attaraxia:BAABNQAECoEkAAMEAAkK8BwSIADgAgAEAAkK8BwSIADgAgADAAEK7QwAagA4AAAAAA==.',
Au='Aurelith:BAAANQADCgIIBAAAAA==.Aurellya:BAAANQAECgMIAwAAAA==.',
Av='Aviarra:BAAANQABCgcICgAAAA==.Avodakadavra:BAAANQADCggICAAAAA==.',
Ay='Ayroon:BAAANQAECgMIAwAAAA==.',
['Aé']='Aéquítas:BAAANQAECgQIBgAAAA==.',
Ba='Bamfbutcher:BAAANQAECgYICgAAAA==.Barent:BAAANQADCgYIDAAAAA==.Barrimen:BAABNQAECoEXAAIFAAcKMBCPjACjAQAFAAcKMBCPjACjAQAAAA==.Bartolomew:BAAANQAECgYIEQAAAQ==.Bartonella:BAAANQADCgIIAgABNQAECgIIBAAGAAAAAA==.',
Be='Bedemere:BAAANQAECgYIEgAAAA==.Beepers:BAABNQAECoEXAAIEAAcKyQ6fcgDQAQAEAAcKyQ6fcgDQAQAAAA==.Behodahlia:BAAANQAECgYICgAAAA==.Belfie:BAAANQAECgUJBQAAAA==.Berrylla:BAAANQADCgIIAgAAAA==.',
Bi='Bigdemon:BAAANQAECgIIAQAAAA==.Bigmakk:BAAANQAECgYIEgAAAA==.Bimzelx:BAAANQAECgIJAgAAAA==.Bipolar:BAAANQAECgUIBQAAAA==.Bitterblood:BAAANQAECgUIEgAAAA==.',
Bl='Blastgamer:BAAANQAECgMIAwAAAA==.Blondebeard:BAAANQAECgcIEwAAAA==.',
Bo='Booshi:BAAANQAECgIIAgAAAA==.Bowiiesenpai:BAAANQAECgcIEwAAAA==.',
Br='Bragontix:BAABNQAECoEaAAIBAAkKYRncCwB4AgABAAkKYRncCwB4AgAAAA==.Bravehearth:BAAANQADCgQIBAABNQAECgYIBgAGAAAAAA==.Brewvoke:BAAANQAECgUJCQAAAA==.Brightxan:BAABNQAECoElAAIHAAkKmhGNGgDEAQAHAAkKmhGNGgDEAQAAAA==.',
Bu='Bubbadruid:BAAANQADCgQIBAABNQAECggIGgAEAPciAA==.Bubbahunter:BAABNQAECoEaAAIEAAgK9yL+EwAjAwAEAAgK9yL+EwAjAwAAAA==.Bubbashaman:BAAANQADCgIIAgABNQAECggIGgAEAPciAA==.Buddahspanks:BAAANQADCgcIBQAAAA==.Buddahthai:BAABNQAECoEmAAIIAAkKtBsHTwC8AgAIAAkKtBsHTwC8AgAAAA==.Buddhabum:BAABNQAECoENAAIJAAgKRAuGgQCCAQAJAAgKRAuGgQCCAQAAAA==.Budweaver:BAAANQADCgYICQAAAA==.Bus:BAABNQAECoEhAAIKAAkKvCZDAADzAwAKAAkKvCZDAADzAwABNQAFFAYIEwAHAE8hAA==.Bussdefense:BAAANQADCgYIGgAAAA==.Butterrs:BAAANQAFFAQICAAAAQ==.Butterz:BAAANQAECgIIBAABNQAFFAQICAAGAAAAAA==.',
Ca='Caleian:BAAANQAECgUIBgAAAA==.Caloren:BAAANQAECgYIEgAAAA==.Caorou:BAAANQAECgUICQAAAA==.Cashaboo:BAAANQADCgYIBgAAAA==.',
Ch='Charlyte:BAABNQAECoEWAAILAAcKbxQ3UwDaAQALAAcKbxQ3UwDaAQAAAA==.Charuzu:BAAANQADCgYIBgAAAA==.',
Co='Corneater:BAAANQAECgYIAQAAAA==.',
Cr='Crysinia:BAAANQADCgUIBQAAAA==.',
Cu='Cuigy:BAAANQAECgYIDgAAAA==.',
Cy='Cyriene:BAAANQAECgQIBwAAAA==.Cyril:BAAANQAECgIIAgABNQAECgUICQAGAAAAAA==.',
Da='Dagadin:BAAANQAECgQIBAAAAA==.Dalio:BAAANQAECgMIAwAAAA==.Danté:BAAANQAECgQICQABNQAECgcIGgAMAPsVAA==.Daraen:BAAANQADCgYIBwAAAA==.Daylen:BAAANQAECgQICwAAAA==.',
Dd='Ddeathchura:BAAANQAECgQICwAAAA==.',
De='Deactrim:BAAANQAECgUIDwAAAA==.Dema:BAAANQADCgQIBAAAAA==.Demonicflats:BAAANQADCgUIBQAAAA==.Demonodie:BAAANQABCggIDAAAAA==.Dendrada:BAAANQAECgQICwAAAA==.Deuce:BAAANQAECgQICgAAAA==.',
Di='Diogenes:BAAANQADCgQIBAAAAA==.Dizimo:BAAANQAECgUICgAAAA==.',
Dk='Dkflat:BAAANQADCgEIAQAAAA==.',
Do='Dogmeat:BAABNQAECoEkAAIEAAkKTiLqCgBlAwAEAAkKTiLqCgBlAwABNQAFFAYIEAANALwVAA==.Dotisa:BAAANQADCggICwAAAA==.',
Dr='Dragonlex:BAAANQADCgcIDQAAAA==.Drakeshadows:BAAANQADCgIIAgAAAA==.Drchivago:BAAANQADCgYICgAAAA==.Drdreadful:BAAANQABCgIIAgAAAA==.Druidtime:BAAANQAECggICAAAAA==.',
Du='Duna:BAAANQAECgQIBwAAAA==.Dungoofed:BAAANQAECgEJAQAAAA==.Duvidressra:BAABNQAECoEnAAMOAAkKBRipAgC2AgAOAAkKBRipAgC2AgAJAAIK1QfT7wBtAAAAAA==.',
Dx='Dxmvn:BAAANQADCgQIBQAAAA==.',
Ed='Edisonn:BAABNQAECoEmAAMJAAkKDR+TIADPAgAJAAgKsB6TIADPAgAMAAUK+xKsIQBPAQAAAA==.',
Eg='Eggies:BAAANQADCggIDgABNQAECgkJIAAJANIhAA==.',
Ek='Ektrim:BAAANQAECgEIAQABNQAECgUIDwAGAAAAAA==.',
El='Eladio:BAAANQADCgIIAgAAAA==.Eldarya:BAAANQAECgUICgAAAA==.Elentisa:BAAANQAECgIIAgAAAA==.Elghinn:BAAANQAECgYIEwAAAA==.Elissaria:BAAANQADCgQIBAAAAA==.Ellastrasza:BAABNQAECoEaAAIPAAcKvhJ9FQCHAQAPAAcKvhJ9FQCHAQAAAA==.Ellie:BAAANQAECgYIDQAAAA==.Elroy:BAABNQAECoEcAAIFAAgKHhGFcgDrAQAFAAgKHhGFcgDrAQAAAA==.',
Em='Embold:BAAANQADCggICAABNQAFFAQIDQAQAHcjAA==.Emernantus:BAAANQAECgYIEQAAAA==.',
Er='Erazar:BAABNQAECoEcAAQBAAYKSx8GEQAHAgABAAYKSx8GEQAHAgACAAIK/QMSPQBbAAARAAEKjhrRGwA3AAAAAA==.',
Es='Espy:BAAANQAECgMIBAAAAA==.',
Eu='Eunbyeol:BAAANQAECgcIEwAAAA==.',
Ev='Evee:BAAANQABCgQIBAAAAA==.',
Fa='Faeria:BAAANQAECgUIDQAAAA==.Fatcritties:BAAANQAECgIIBAAAAA==.Fatnchunkydk:BAAANQAECgUICwAAAA==.',
Fe='Feeblemind:BAAANQAECgQICgAAAA==.Feli:BAAANQAECgYIDgAAAA==.Felmommy:BAAANQADCggICAAAAA==.Femboi:BAAANQADCggIDgAAAA==.Fender:BAAANQAECgQICQAAAA==.',
Ff='Ffugntotems:BAAANQADCgcICwAAAA==.Ffviitifa:BAAANQADCgcICwAAAA==.',
Fi='Finfangfoom:BAAANQADCgIIAgABNQAECgYIBgAGAAAAAA==.Fingertoes:BAABNQAECoEdAAIIAAcKdR5GdgBbAgAIAAcKdR5GdgBbAgAAAA==.Fistbeard:BAAANQADCgUJBQABNQADCgcJCgAGAAAAAA==.Fizzlerazz:BAAANQADCgUIBQAAAA==.',
Fl='Flattulata:BAAANQADCgEJAQAAAA==.Flatulatta:BAABNQAECoEbAAIJAAgKAwr2dQCkAQAJAAgKAwr2dQCkAQAAAA==.Flyciful:BAAANQAECgIJAgAAAA==.Flyingweasle:BAAANQADCgQIBwAAAA==.',
Fo='Forceed:BAEANQAECgEIAQABNQAECgMIBQAGAAAAAA==.Forsythe:BAAANQABCgcICQAAAA==.Foxehh:BAAANQABCgUIBwAAAA==.Foxxycontin:BAAANQADCgEIAQAAAA==.',
Fr='Fraternaldk:BAACNQAFFIEIAAISAAMKOwmECwDFAAASAAMKOwmECwDFAAA1AAQKgRcAAhIACQpOHYQWAM4CABIACQpOHYQWAM4CAAAA.Fraturnal:BAAANQADCgIIAgAAAA==.Freestyle:BAAANQADCgYICgAAAA==.Frodowagons:BAAANQAFFAQIBAAAAA==.Frostpie:BAABNQAECoEYAAIIAAgKLA+cnwD7AQAIAAgKLA+cnwD7AQAAAA==.',
Fu='Fuglybaby:BAAANQADCgcICwAAAA==.Fuhenhenka:BAAANQAECgMIAwAAAA==.',
Fw='Fwakos:BAAANQAECgQIBgAAAA==.Fwakow:BAAANQADCgYICwAAAA==.',
Ga='Gakmonk:BAAANQADCggJDgABNQAECgYIEwAGAAAAAA==.Gakpaladin:BAAANQAECgYIEwAAAA==.Galaway:BAAANQAECgQIBAAAAA==.Galthul:BAAANQADCgUIBQABNQAECgYIEwAGAAAAAA==.Garfyaz:BAAANQADCgYICwAAAA==.',
Gd='Gdlez:BAAANQADCgcIDAAAAA==.',
Ge='Gethael:BAAANQADCgIIAgAAAA==.',
Go='Goatroth:BAAANQAECgIIAgAAAA==.Golorious:BAABNQAECoEYAAIHAAgKTByaEABGAgAHAAgKTByaEABGAgAAAA==.Goododie:BAAANQAECgQIBwAAAA==.',
Gr='Grayback:BAAANQAECggJBgABNQAECggIGQATAJQaAA==.Grenas:BAAANQABCgMIBQAAAA==.Grippyweasle:BAAANQAECgYIEgAAAA==.Grovelly:BAAANQABCggIEAAAAA==.Growlius:BAAANQADCgcIBwABNQAECgUJBQAGAAAAAA==.',
Gu='Gudit:BAAANQADCggICAABNQAECgUIDAAGAAAAAA==.Gulaken:BAAANQAECgQICgAAAA==.Guseva:BAAANQAECgEIAQAAAA==.Guttershark:BAABNQAECoEYAAIUAAcKGB7zHgAvAgAUAAcKGB7zHgAvAgAAAA==.',
Ha='Hafnia:BAAANQAECgIIBAAAAA==.Halliday:BAAANQADCggIHAAAAA==.Haoasakura:BAABNQAECoEhAAIFAAgKiCPWIgAGAwAFAAgKiCPWIgAGAwAAAA==.Haylo:BAAANQAECgIIBAAAAA==.',
He='Headshop:BAAANQADCgcIEgAAAA==.Healzforfood:BAAANQAECgEJAQAAAA==.Heap:BAAANQAECgMIAwABNQAECgcIEwAGAAAAAA==.Heartlight:BAAANQADCgMIAwAAAA==.Heavyreign:BAAANQADCgQIBwAAAA==.Helicobacter:BAAANQADCgYIBgAAAA==.Hewnoshaqa:BAAANQAECgUIDgAAAA==.Hexorcist:BAABNQAECoEbAAMVAAkKzh6tHADHAgAVAAkKzh6tHADHAgAWAAEKwxGJ8QA+AAAAAA==.',
Hi='Hickerbilly:BAAANQADCgEIAQAAAA==.Hitormist:BAAANQAECgcIDgAAAA==.',
Ho='Holyanne:BAAANQADCgQIAgAAAA==.Holyspanks:BAAANQADCgYIBgABNQAECgYIEwAGAAAAAA==.',
Hr='Hruuli:BAAANQADCgYIBgAAAA==.',
Hu='Huntrlicious:BAABNQAECoEeAAIEAAYKXg4CiwCRAQAEAAYKXg4CiwCRAQAAAA==.Husqvarnna:BAAANQADCgYIBgAAAA==.Huugor:BAAANQAECggICAAAAA==.',
Ic='Icnips:BAAANQADCgUIBQAAAA==.Icoulddowork:BAAANQAECggICAABNQAECggIEwAGAAAAAA==.',
Id='Idoshiftwork:BAAANQAECggIEwAAAA==.Idunno:BAAANQADCgYICQAAAA==.',
Ih='Ihriel:BAAANQADCgEJAQAAAA==.',
Ik='Ikazuchi:BAAANQAECgYIDwAAAA==.',
Il='Illcutabish:BAABNQAECoEfAAMUAAgKDCClDQDeAgAUAAcKfySlDQDeAgAXAAgKfhcwFwACAgAAAA==.Illtank:BAAANQAECgUJBQAAAA==.',
Im='Imatankin:BAAANQAECgEIAQAAAA==.Imk:BAAANQAECgQICwAAAA==.',
Io='Iock:BAEANQAECgUIBQAAAA==.',
Ir='Ironarms:BAAANQAECgYJEwAAAA==.',
Is='Ishido:BAAANQADCgYIBgAAAA==.',
Je='Jennypoo:BAAANQAECgYIEQAAAA==.Jessd:BAAANQADCgcJBwAAAA==.',
Ji='Jinuoo:BAAANQADCgQIBAAAAA==.',
Jo='Johnwarrior:BAABNQAECoEXAAIYAAcKIx68BQBsAgAYAAcKIx68BQBsAgAAAA==.Jorrix:BAAANQAECgYIDwAAAA==.',
Ju='Juduspriestt:BAAANQAECgUIDQAAAA==.',
Jy='Jynaxa:BAAANQADCgEIAQAAAA==.',
['Jä']='Jägermeister:BAAANQADCgYJDAAAAA==.',
Ka='Kaaeko:BAAANQAECgYIDQAAAA==.Kalerito:BAAANQAECgYIEwAAAA==.Kallythea:BAAANQADCggICAAAAA==.Kardie:BAAANQADCgQIBAABNQAECgYIHAABAEsfAA==.Karl:BAAANQAECgIIBAAAAA==.Kaserr:BAACNQAFFIETAAMXAAYKLRdmAgAGAgAXAAYKdBVmAgAGAgAUAAIK7Bg0CgC2AAA1AAQKgSkAAxcACQpFJbUEADUDABcACAq+JbUEADUDABQAAwrBI+JEACQBAAAA.Kayserdh:BAAANQAECgUICAAAAA==.Kazaf:BAABNQAECoEUAAIZAAYKNBeRRQChAQAZAAYKNBeRRQChAQAAAA==.',
Ke='Kebru:BAAANQAECgUIEAAAAA==.Keitrek:BAAANQAECgYIEwAAAA==.Kelthias:BAAANQADCgYJDQAAAA==.Kerwîck:BAAANQAECgYIDAAAAA==.Keyen:BAAANQAECgQICQAAAA==.',
Kh='Kheiko:BAAANQAECgUIBQAAAA==.',
Ki='Kibalion:BAAANQAECgYICwAAAA==.Killbent:BAAANQAECgEIAQAAAA==.Kinnky:BAAANQAECgYIDQAAAA==.Kino:BAAANQAECgUICQAAAA==.Kitn:BAAANQABCgQIBAAAAA==.Kityana:BAAANQADCgIIAgAAAA==.',
Kp='Kpop:BAAANQADCgIIAwAAAA==.',
Kr='Krasdan:BAAANQAECgIIAgAAAA==.Kreettip:BAAANQAECgYIEwAAAA==.Krispy:BAAANQADCgcJBwABNQAECggIHgACAOEaAA==.',
Ks='Ksp:BAAANQADCgQIBQAAAA==.',
Ku='Kugamoo:BAABNQAECoEXAAMNAAcKLhPwNwDgAQANAAcKLhPwNwDgAQAaAAQK+Qf7PwC+AAAAAA==.Kulgan:BAABNQAECoEcAAIbAAkKnxlYKgCBAgAbAAkKnxlYKgCBAgAAAA==.Kurgen:BAAANQAECgQIBwAAAA==.Kuroda:BAAANQAECgIIAwAAAA==.Kurolucifer:BAAANQADCgcIFgAAAA==.',
Ky='Kylex:BAAANQAECgMIBgAAAA==.',
['Kä']='Käßoom:BAAANQAECgEIAQAAAA==.',
La='Lamiah:BAAANQAECgIIAgAAAA==.Lauadia:BAAANQAECgIJAgAAAA==.',
Lc='Lckdown:BAAANQAECggICwAAAA==.',
Le='Legomyegolas:BAAANQADCgYJBgAAAA==.',
Li='Lightsocket:BAAANQADCgYJCAABNQAECgIJAgAGAAAAAA==.Livingkntpib:BAAANQADCggICAAAAA==.',
Lo='Lockedout:BAAANQAECgMIAwABNQAECggIHQAIAO8hAA==.Loden:BAAANQAECgcIDAAAAA==.Lodez:BAAANQAFFAEIAgAAAA==.Loktarhogar:BAAANQAECgUICAAAAA==.Lostadin:BAAANQADCgIIAgAAAA==.Lovi:BAAANQAECggIEwAAAA==.',
Lu='Luck:BAAANQADCgMIAwABNQAECgQIBAAGAAAAAA==.Luckyboi:BAABNQAECoEYAAMaAAgKtAdmLwA5AQAaAAcKLgZmLwA5AQANAAcK/AdXVAA2AQAAAA==.Lumeria:BAAANQAECgMIBQAAAA==.Lumina:BAAANQAECgUIDAAAAA==.Lusciifi:BAACNQAFFIEKAAMFAAUKbBeUCQBDAQAFAAQKhBaUCQBDAQAHAAIKmhD7BwCBAAA1AAQKgS8AAwUACQrwJSwGALgDAAUACQruJSwGALgDAAcABgpCI5MQAEcCAAAA.',
Ly='Lykie:BAABNQAECoEbAAIHAAcKXxp/GQDQAQAHAAcKXxp/GQDQAQAAAA==.Lynxic:BAAANQADCgQJBwABNQAECgIIAgAGAAAAAA==.Lyone:BAAANQAECgQIDQAAAA==.',
['Lä']='Lävey:BAAANQADCgEIAQAAAA==.',
['Lé']='Léxa:BAAANQADCgQIBAAAAA==.',
['Lú']='Lúvaa:BAAANQAECgcIEwAAAA==.',
Ma='Macavity:BAAANQADCgMJAwAAAA==.Madmanmike:BAAANQADCgIIAgAAAA==.Magalis:BAAANQAECgQICwAAAA==.Magicwoman:BAAANQAECgQIBgAAAA==.Magikkisback:BAAANQAECgIIAwAAAA==.Magsh:BAAANQADCggIJAAAAA==.Mandorius:BAAANQAECgUICwAAAA==.Maphra:BAAANQADCggJCAABNQAECgcIDgAGAAAAAA==.Marcos:BAAANQADCgIIAgAAAA==.Marl:BAAANQADCgQICAAAAA==.Marvolo:BAAANQAECggIDgABNQAECggIGQATAJQaAA==.Maverickdog:BAABNQAECoEdAAQDAAgKdh5AIwDwAQADAAcKQBtAIwDwAQAcAAQKXBTiCQAdAQAEAAMKaySdyQADAQAAAA==.',
Mc='Mchammerwork:BAAANQAECgUIBwABNQAECggIEwAGAAAAAA==.',
Me='Mechunter:BAAANQADCgYIBgABNQAECgMIBAAGAAAAAA==.Meekzz:BAAANQAECgUICQAAAA==.Meeshie:BAABNQAECoEyAAQbAAkK+Bb9JwCOAgAbAAkK+Bb9JwCOAgAQAAQKdQliQgDIAAAdAAIK5QWWGwBWAAAAAA==.Melodrop:BAAANQAECggIBQAAAA==.',
Mi='Mihawk:BAAANQADCgEIAQABNQAECgcIHQAIAHUeAA==.Mikexfire:BAAANQAECgYIEAAAAA==.Mikuzume:BAAANQADCgYIBgAAAA==.Mildchaos:BAAANQAECggJAQAAAA==.Mishima:BAAANQAECggICAAAAA==.Misspell:BAAANQADCggJFAAAAA==.Miznewbooty:BAABNQAECoEXAAIQAAcKqhNrIgDSAQAQAAcKqhNrIgDSAQAAAA==.',
Mo='Moochella:BAAANQAECgUJCAAAAA==.Moojestic:BAAANQADCggIDwAAAA==.Moonq:BAAANQAECgQICwAAAA==.Moosie:BAAANQAECgYIEgAAAA==.Moosifer:BAAANQADCgQIBAABNQAECgkJGwAVAM4eAA==.Mooska:BAAANQAECgEIAQABNQAECgYIEgAGAAAAAA==.Moxflip:BAAANQAECgcICQAAAA==.Moxtsm:BAAANQAECgMIAgAAAA==.Mozzers:BAAANQADCgcIBwAAAA==.',
Mu='Muertenegra:BAAANQADCgUIBQABNQAECgUIDQAGAAAAAA==.Muffy:BAAANQAECgQICgAAAA==.Muln:BAAANQADCggIBwAAAA==.Murlouh:BAAANQADCgQIBAAAAA==.',
My='Mydevil:BAAANQADCgQIBAAAAA==.Myllakura:BAAANQAECgMIBgAAAA==.Mythnarra:BAABNQAECoEcAAITAAkKByJDBwBLAwATAAkKByJDBwBLAwAAAA==.',
['Mä']='Mäomäo:BAAANQADCgMIAwAAAA==.',
['Mí']='Mísanthrope:BAAANQADCgQIBAABNQAECgIIAgAGAAAAAA==.',
Na='Nadíne:BAABNQAECoEaAAIIAAcKARKHtQDLAQAIAAcKARKHtQDLAQAAAA==.Nanukimon:BAAANQAECgQIBwAAAA==.Narawe:BAAANQADCgIJAgAAAA==.Nastymccasty:BAAANQAECggIAwABNQAECggIHwAUAAwgAA==.Naughtgelic:BAAANQADCgYJCQAAAA==.',
Ne='Nedgamingttv:BAEANQAECgMIBQAAAA==.Nekrimah:BAAANQAECgYIDAAAAA==.Nerph:BAAANQADCgUICwAAAA==.Nevaera:BAAANQADCgYIDAAAAA==.',
Ni='Ni:BAAANQAECgQIBAAAAA==.Nick:BAACNQAFFIELAAMSAAQKbhKGBwApAQASAAQKbhKGBwApAQAZAAEKkQLLIABBAAA1AAQKgSgAAhIACQr4JesGAHEDABIACQr4JesGAHEDAAAA.Nikor:BAEANQAECgIIBAAAAA==.',
Nm='Nmue:BAAANQADCgIIAgAAAA==.',
No='Nokorii:BAAANQAECgQIBwAAAA==.Nomecoma:BAAANQAECgUIDQAAAA==.Nonok:BAAANQADCgIIAgAAAA==.Nookah:BAAANQABCgIIAgABNQAECgkJJAAEAPAcAA==.Noshom:BAAANQAECgYIEgAAAA==.Notches:BAAANQADCgEIAQAAAA==.',
Ns='Nsyncrogue:BAAANQADCgYJBgAAAA==.',
Ny='Nymful:BAAANQAECgUICwAAAA==.',
['Nè']='Nèlo:BAAANQAECgYIDwAAAA==.',
Ob='Obianstrider:BAAANQADCgYIFQAAAA==.',
Oc='Oceanspell:BAABNQAECoEeAAIeAAYKFyL0BgA8AgAeAAYKFyL0BgA8AgAAAA==.',
Og='Oggleboggle:BAAANQADCgEIAQAAAA==.',
Ol='Oldbuse:BAABNQAECoEXAAMfAAcKaiBYDABuAgAfAAcKaiBYDABuAgAWAAEK1BhH7ABGAAAAAA==.',
On='Onlytoez:BAAANQAECgQICAABNQAECgkJMgAbAPgWAA==.',
Or='Orave:BAAANQAECgIIBAAAAA==.Oromë:BAAANQABCgQIBAAAAA==.Orzik:BAAANQADCgcIBwAAAA==.',
Os='Osox:BAAANQAECggICAAAAA==.Ostena:BAAANQAECgYICwAAAA==.Osteole:BAAANQAECgUIDwABNQAECgYICwAGAAAAAA==.',
Ou='Oulawdpriest:BAACNQAFFIEFAAIQAAMK6wiyCgDaAAAQAAMK6wiyCgDaAAA1AAQKgSIAAxAACQrOF8IVAG4CABAACQrOF8IVAG4CABsAAQpjE0HHADUAAAAA.',
Ov='Overture:BAAANQADCgQIBgAAAA==.',
Ow='Owthatburns:BAAANQADCgYIBgAAAA==.',
Pa='Pakszdude:BAAANQADCgUIBQAAAA==.Pandamonious:BAAANQADCggICAABNQAECgEIAgAGAAAAAA==.Papawoof:BAAANQADCgQJBQABNQAECgkJGwAVAM4eAA==.Parkour:BAAANQAECgIIAgAAAA==.Paullyfists:BAAANQAECgcIEwAAAA==.',
Pe='Peni:BAAANQAECgIIAgAAAA==.',
Pi='Pintobeans:BAAANQAECgEIAgAAAA==.',
Po='Popkorn:BAACNQAFFIEQAAMTAAYKmCBUAwDsAQATAAUKTh9UAwDsAQAgAAMKViBHAQAnAQA1AAQKgSkAAxMACQqpJmwAAPkDABMACQqRJmwAAPkDACAAAgptIgAXANIAAAAA.Popkourne:BAAANQAECggIDQABNQAFFAYIEAATAJggAA==.Poplocks:BAAANQADCgYICgAAAA==.Porrana:BAAANQAECgUICAAAAA==.Powaqa:BAAANQAECgUICwAAAA==.',
Pr='Praetorian:BAAANQAECgcIEgAAAA==.Praxxus:BAAANQADCgYIBgAAAA==.',
Ps='Psy:BAAANQAECggIAgAAAA==.',
Pu='Purify:BAABNQAFFIEJAAIVAAYK+xqUAgAwAgAVAAYK+xqUAgAwAgAAAA==.',
Qm='Qmen:BAAANQADCgIIAgAAAA==.',
Qu='Quasient:BAABNQAECoEbAAIIAAgKHx7JUAC4AgAIAAgKHx7JUAC4AgAAAA==.Quethelos:BAAANQADCgcJGwAAAA==.Quickbrew:BAAANQADCgQIBAAAAA==.Quickspell:BAAANQAECgcIEAAAAA==.',
Ra='Raalcar:BAAANQAECgMIAwABNQAECgUIBQAGAAAAAA==.Raedyyn:BAAANQAECgMIAwAAAA==.Ragarninn:BAAANQADCgcIDwABNQAECgkJJAAVAKIkAA==.Ragarth:BAAANQAECgEIAQAAAA==.Ragendecay:BAAANQAECgUJCAAAAA==.Ragequits:BAACNQAFFIEaAAIhAAcKaiR8AQC0AgAhAAcKaiR8AQC0AgA1AAQKgSIAAiEACQpEJiMJAJoDACEACQpEJiMJAJoDAAAA.Ragewar:BAAANQABCgcIDAAAAA==.Rakshassa:BAAANQAECgMIBAAAAA==.Ralcar:BAAANQAECgUIBQAAAA==.Rawkphyst:BAAANQADCgQIAgAAAA==.Razrscale:BAAANQAECgEIAQAAAA==.',
Re='Redhuntsman:BAAANQADCggIGgAAAA==.Regrow:BAAANQADCgcIBwABNQAECgMIBAAGAAAAAA==.Reska:BAAANQAECgQIBQAAAA==.',
Rh='Rholdentodor:BAAANQADCgEIAQABNQAECgcIHQAIAG4SAA==.',
Ri='Rindorin:BAAANQAECgYIBwAAAA==.Ritarepulsa:BAAANQADCgYIDAAAAA==.',
Ro='Rohra:BAAANQAECgYIEQAAAA==.Rosiee:BAAANQAECgIIAgABNQAECgYIEgAGAAAAAA==.Rozynwen:BAAANQAECgEIAQAAAA==.',
Ru='Ruah:BAAANQABCgMIAwAAAA==.Rubmytoes:BAAANQAECgEJAQAAAA==.Rukuna:BAAANQAECgEIAQAAAA==.Runecast:BAABNQAECoEcAAIiAAgK/BcDIAA8AgAiAAgK/BcDIAA8AgAAAA==.',
Sa='Saelyrinth:BAAANQAECgEIAQABNQAECgMIBQAGAAAAAA==.Salamence:BAAANQADCggJDgABNQAECgYIEQAGAAAAAQ==.Sambor:BAAANQAECggIBwAAAA==.Sarapheena:BAABNQAECoEZAAIVAAgK4x2bJACaAgAVAAgK4x2bJACaAgAAAA==.Sarouk:BAABNQAECoEaAAIhAAgKchf1XQAsAgAhAAgKchf1XQAsAgAAAA==.Satanbomb:BAAANQAECgIIBAAAAA==.Satansbride:BAAANQADCgUICQABNQAECgYIBgAGAAAAAA==.Saterli:BAABNQAECoEaAAMbAAkKcRaELQByAgAbAAkKcRaELQByAgAQAAEKZQI6aQAmAAAAAA==.Saturno:BAAANQAECgEIAQAAAA==.Saucypirate:BAAANQAECgYIEAAAAA==.Sayygurl:BAAANQAECgIJAwAAAA==.',
Sc='Scalvert:BAABNQAECoEdAAIIAAcKbhJcswDQAQAIAAcKbhJcswDQAQAAAA==.Scalypanda:BAAANQAECgcIEwAAAA==.Scamander:BAABNQAECoEZAAITAAgKlBqtFwBvAgATAAgKlBqtFwBvAgAAAA==.Scoobs:BAAANQADCgQIBAABNQAECgIIAgAGAAAAAA==.Screamsalot:BAAANQAECgEIAQAAAA==.Sculi:BAAANQAECggIEgAAAA==.',
Se='Seiishiro:BAAANQAECgIIAgAAAA==.Seldon:BAAANQAECgUICwAAAA==.Senyor:BAAANQAECggIEwAAAA==.Seradormi:BAAANQADCgMIAwAAAA==.Seraphiel:BAAANQAECgIIBAABNQAECgUIBQAGAAAAAA==.Serfort:BAAANQADCgUIBQAAAA==.',
Sh='Shadowpaksz:BAAANQAECgUIDQAAAA==.Shadowsneak:BAAANQAECgUICQAAAA==.Shadowvixen:BAAANQAECgEIAQAAAA==.Shaelistra:BAAANQAECgUICwAAAA==.Shalilama:BAABNQAECoEkAAIVAAkKoiS8AgCqAwAVAAkKoiS8AgCqAwAAAA==.Shamanana:BAAANQAECgcIEQAAAA==.Shamboli:BAAANQADCggIEgAAAA==.Shamirah:BAAANQADCgcJCQAAAA==.Shaï:BAAANQAECgQJBAAAAA==.Shenderp:BAAANQAECgMIBQAAAA==.Shinerbock:BAABNQAECoEbAAIjAAcKSwxTFABVAQAjAAcKSwxTFABVAQAAAA==.Shockitti:BAAANQAECgIIAgAAAA==.Shtark:BAAANQAECgIIAgAAAA==.',
Si='Sianvar:BAAANQAECgQIBAAAAA==.Silshara:BAABNQAECoEbAAICAAkKEA14GAD8AQACAAkKEA14GAD8AQAAAA==.Silverjustis:BAAANQAECgQICwAAAA==.Siwe:BAAANQAECgYIEwAAAA==.Six:BAAANQAECgIIAgABNQAECgMIAwAGAAAAAA==.',
Sk='Skip:BAAANQADCgMIAwAAAA==.Skribblez:BAABNQAECoEhAAMFAAgKlxoESABwAgAFAAgKlxoESABwAgALAAQKJBS1mQAAAQAAAA==.Skyanna:BAAANQAECgEIAQAAAA==.',
Sl='Slackback:BAAANQAECggIBwABNQAFFAIIBQAWAFoRAA==.Sloop:BAAANQADCgUICgAAAA==.Sloot:BAAANQAECgcICwAAAA==.',
Sn='Sneasel:BAAANQAECgMIBAABNQAECgQIBAAGAAAAAA==.Snoogins:BAAANQADCgUIDgABNQAECgYIBgAGAAAAAA==.',
So='Sockszz:BAABNQAECoEhAAIkAAgKhCUJAgB1AwAkAAgKhCUJAgB1AwAAAA==.Songblade:BAAANQABCgUIBgAAAA==.Soulsy:BAABNQAECoEcAAIFAAcKiCKuPQCUAgAFAAcKiCKuPQCUAgAAAA==.Soulvalk:BAAANQADCgQIBAAAAA==.Sourmagic:BAAANQAECgcIDwAAAA==.',
Sp='Splendorae:BAABNQAECoEVAAILAAcK+Bd9QgAaAgALAAcK+Bd9QgAaAgAAAA==.Sprints:BAABNQAECoEYAAIVAAcKABL7aAB6AQAVAAcKABL7aAB6AQAAAA==.Spritz:BAABNQAECoEfAAMVAAgKZB04JQCWAgAVAAgKZB04JQCWAgAWAAIKDB0nxwChAAAAAA==.Sprucewillis:BAAANQADCgMIBgABNQAECgYIBgAGAAAAAA==.Spyderelite:BAABNQAECoEZAAIMAAcKZRK7DwDwAQAMAAcKZRK7DwDwAQAAAA==.',
Sq='Squirrel:BAAANQAECgUIDAAAAA==.',
Ss='Ssuperss:BAAANQADCgQICgAAAA==.',
St='Stabbot:BAAANQAECgMJAwABNQAECgcIDgAGAAAAAA==.Stankstarstu:BAAANQAECgYIBgAAAA==.Starblood:BAAANQABCgMIAwAAAA==.Starspeaker:BAAANQAECgQIBAAAAA==.Stompmyballs:BAAANQAECgYIEgABNQAFFAcIGgAhAGokAA==.Stoogotz:BAAANQADCgIIBAAAAA==.Studlebane:BAAANQADCgYIBgABNQAECgMIBgAGAAAAAA==.Studlepalm:BAAANQAECgMIBgAAAA==.',
Su='Sundaresh:BAAANQADCgEIAQAAAA==.Sunwing:BAABNQAECoEVAAIbAAcKHSPhJwCPAgAbAAcKHSPhJwCPAgAAAA==.Supersasian:BAAANQAECgcIBwAAAA==.Supersheep:BAAANQAECgUJCAAAAA==.Suvien:BAAANQADCggICwAAAA==.',
Sy='Sylvarian:BAAANQAECgYIDQAAAA==.Sylvinna:BAAANQADCggIFQAAAA==.',
Ta='Tagda:BAAANQADCggJCAAAAA==.Takeurland:BAAANQADCgQIBQAAAA==.Taterdotz:BAAANQAECgIIAgAAAA==.Tatersack:BAAANQABCgUIBQAAAA==.Tatortwats:BAAANQAFFAEIAwAAAA==.Taxdeeznutz:BAAANQADCgUIBQAAAA==.',
Te='Tengrit:BAAANQADCgUIBwAAAA==.Tephine:BAAANQAECgYIEwAAAA==.Tepicoyotl:BAABNQAECoEaAAMVAAgKpBmhMABbAgAVAAgKpBmhMABbAgAWAAEKiACyHQEZAAAAAA==.',
Th='Thaymor:BAAANQADCgcJCgAAAA==.Thebigkitti:BAAANQADCgEIAQAAAA==.Thelonecone:BAABNQAECoEoAAIiAAkKgCTKAwCNAwAiAAkKgCTKAwCNAwAAAA==.Theodor:BAAANQAECgMIBAAAAA==.Theoganth:BAAANQAECgMIBAABNQAECgcIGgAMAPsVAA==.Theraphee:BAAANQADCgcJFwAAAA==.Therym:BAAANQADCgEIAQABNQAECggIGAAZADEPAA==.Thomwizard:BAAANQADCggIFAAAAA==.Thormorn:BAAANQADCggIFQAAAA==.Thunnha:BAAANQADCgYJEwAAAA==.',
Ti='Tierali:BAAANQADCgcICwAAAA==.Tio:BAAANQADCggIGwAAAA==.',
To='Toastedsushi:BAAANQADCgYIBgAAAA==.Toofwess:BAAANQAECgIJAgABNQAECgcIDgAGAAAAAA==.Torrinchaos:BAAANQADCgQIBAAAAA==.Tosala:BAAANQAECgMIBQAAAA==.Totemkiller:BAAANQAECgQICwAAAA==.',
Tr='Traael:BAAANQAECgYIDAAAAA==.Treesap:BAABNQAECoEWAAIlAAgKISAZAwDfAgAlAAgKISAZAwDfAgAAAA==.Trinityeve:BAAANQAECgMIBQAAAA==.Trmz:BAAANQAECggIDAAAAA==.Trnzlock:BAAANQAECgYIDwABNQAECggIDAAGAAAAAA==.Trîggêr:BAAANQADCgYIBgAAAA==.',
Tu='Tulanii:BAAANQADCgcICQAAAA==.Tularana:BAAANQAECgcICAABNQAECgcJGQABAEoYAA==.Tumble:BAAANQAECgQICAAAAA==.',
Tw='Twignberryz:BAAANQAECgEIAQABNQAECgYIBgAGAAAAAA==.Twinkie:BAAANQAECgYICQAAAA==.Twodogz:BAAANQAECgUIDQAAAA==.',
Ty='Tyious:BAABNQAECoEbAAMiAAgKTheuJgADAgAiAAgKDxauJgADAgASAAQK0BHfiACUAAAAAA==.Tyndara:BAAANQAECgUICwAAAA==.',
['Tü']='Tüesdaÿ:BAAANQAECgIIAgAAAA==.',
Ub='Ubavoke:BAAANQAECgYIBwAAAA==.',
Uk='Ukita:BAABNQAECoEkAAIFAAkKsyC5JAD9AgAFAAkKsyC5JAD9AgAAAA==.',
Ur='Ursane:BAABNQAECoEfAAMhAAgKRRRaagAGAgAhAAgKRRRaagAGAgAYAAQK1AgyGgCsAAAAAA==.Ursully:BAAANQAECgUICwAAAA==.',
Uz='Uzi:BAAANQAECgUIDwAAAA==.',
Va='Valentíne:BAAANQADCgYIDAAAAA==.Valhalla:BAAANQAECgMIBQAAAA==.Vanncint:BAAANQAECgUIBgAAAA==.Vashie:BAAANQADCgYICgAAAA==.',
Ve='Vexus:BAACNQAFFIEFAAIWAAIKWhGfFwCgAAAWAAIKWhGfFwCgAAA1AAQKgRsAAhYACQrpG3MjAMECABYACQrpG3MjAMECAAAA.',
Vi='Vinecone:BAAANQAECgQIBAAAAA==.Vixly:BAAANQADCgUIEgAAAA==.',
Vl='Vladios:BAAANQAECgUIDwAAAA==.',
Vo='Voidmommy:BAAANQADCgYIBgABNQAECgMIBQAGAAAAAA==.Vordarian:BAAANQAECgEIAQAAAA==.',
Wa='Walolas:BAAANQADCggIFQAAAA==.Wardrak:BAAANQAECgIIAgAAAA==.Warlokholmes:BAAANQADCgIIAgAAAA==.Warrax:BAAANQADCgcIEAAAAA==.Watchmeburst:BAAANQADCgYICAAAAA==.',
Wh='Whaler:BAAANQAECggIDQAAAA==.',
Wi='Windeagle:BAAANQADCgQIBAABNQAECgUJBQAGAAAAAA==.Windowskey:BAAANQAECgYIAwABNQAECggIEgAGAAAAAA==.',
Wu='Wuzntmyfault:BAAANQAECgMIBAAAAA==.',
Wy='Wyldfyire:BAAANQAECgUIDQAAAA==.',
Xa='Xaven:BAAANQAECgQICQAAAA==.Xavenuke:BAAANQADCgcJDQABNQAECgQICQAGAAAAAA==.',
Xi='Xiaotao:BAAANQAECgMIAwAAAA==.',
Xt='Xtraxtra:BAAANQADCggICQABNQAECggIHgACAOEaAA==.',
Ye='Yellenheller:BAAANQAECgIIAgABNQAECggIGAAIACwPAA==.',
Yo='Yoan:BAAANQAECgUIBQAAAQ==.Yoga:BAAANQAECgIIBAAAAA==.',
Za='Zabra:BAAANQADCggJFQAAAA==.Zahshia:BAAANQAECgIIBAAAAA==.Zaldina:BAAANQADCgIIAgAAAA==.Zathaeus:BAACNQAFFIEIAAITAAUKSQzEBQB+AQATAAUKSQzEBQB+AQA1AAQKgRwAAhMACQocG2MPANQCABMACQocG2MPANQCAAAA.Zaylian:BAABNQAECoEdAAImAAkKdBnBGACQAgAmAAkKdBnBGACQAgAAAA==.Zayragossa:BAABNQAECoEgAAMJAAkK0iG2BwBtAwAJAAkK0iG2BwBtAwAMAAIKTSGJOwC/AAAAAA==.Zayrah:BAAANQAECgMIAwABNQAECgkJIAAJANIhAA==.',
Ze='Zeerkk:BAAANQAECgYIEQAAAA==.Zergmark:BAAANQADCgUIBgAAAA==.',
Zi='Zirilian:BAAANQADCgQICAABNQAECgUIDQAGAAAAAA==.',
Zo='Zoomzoom:BAAANQAECgUJBgABNQAFFAMIBQAQAOsIAA==.Zouris:BAAANQAECgIIAwABNQAECgQIBgAGAAAAAA==.',
Zu='Zulkraa:BAAANQAECgIIBAAAAA==.',
Zy='Zynreth:BAAANQADCgIIAgAAAA==.',
['Ài']='Àirén:BAABNQAECoEYAAQQAAgKdCGqDADyAgAQAAgKdCGqDADyAgAbAAEKhxtexAA+AAAdAAEKRhCNHwA6AAAAAA==.',
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
