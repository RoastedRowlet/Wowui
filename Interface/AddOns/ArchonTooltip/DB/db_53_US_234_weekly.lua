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

local lookup = {'Rogue-Assassination','Mage-Frost','Mage-Arcane','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Unknown-Unknown','Warrior-Arms','DeathKnight-Unholy','DeathKnight-Blood','Hunter-BeastMastery','Paladin-Retribution','Priest-Holy','Paladin-Protection','DemonHunter-Devourer','Paladin-Holy','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','Warrior-Protection','Hunter-Survival','Hunter-Marksmanship','Druid-Restoration','DeathKnight-Frost','Druid-Guardian','Priest-Shadow','DemonHunter-Vengeance','Evoker-Preservation','Druid-Feral','Warrior-Fury','Monk-Mistweaver','Monk-Windwalker','Rogue-Outlaw','Monk-Brewmaster',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abel:BAEANQADCggICAABNQAECgkJHgABANgNAA==.',
Ae='Aeidail:BAACNQAFFH8YAAMCAAgKQBdwBQC7AAADAAUK3xe0GgCmAQACAAUK7hNwBQC7AAA1AAQKf0cAAwIACgonJloAAH4DAAIACgonJloAAH4DAAMACQogIulUANYCAAAA.',
Ag='Agraceful:BAAANQAECgUICAAAAA==.',
Ai='Aidton:BAAANQAECgEIAQAAAA==.Aiobhicefall:BAAANQAECgYIEQAAAA==.Aiobhicefell:BAAANQAECgUIEQAAAA==.Aiobicefall:BAABNQAECn8aAAQEAAgK2Q+RawBbAQAEAAgK2Q+RawBbAQAFAAIKcg8g6QA9AAAGAAEKAAC0OwAcAAAAAA==.Aioboicefall:BAAANQAECgEIAQAAAA==.Aioicefall:BAAANQAECgQIBwAAAA==.Aiza:BAABNQAECn9OAAQHAAoKLhkNDgBzAQAIAAgKdRmCZAAsAgAHAAYKFxUNDgBzAQAJAAMKkguNSQCjAAAAAA==.',
Al='Albinoknight:BAAANQADCgEIAQAAAA==.Alessia:BAAANQADCgYICgAAAA==.Allarria:BAAANQADCggICAABNQAECgkJMAAKAGQiAA==.Altic:BAAANQAECgMIAwABNQAECggIBwALAAAAAA==.',
An='Angrypants:BAABNQAECn8YAAIMAAgK8AzyqQASAQAMAAgK8AzyqQASAQAAAA==.Animalfriend:BAAANQAECgMIAwAAAA==.Anklesmasher:BAAANQAECgUIDgAAAA==.Antisocial:BAAANQAECgEIAQABNQAECgoKLgANAM4gAA==.',
Ar='Archfury:BAAANQABCgYIBwAAAA==.Arctodus:BAAANQAECgEIAQAAAA==.Ardicon:BAAANQABCgEIAQAAAA==.Arfaz:BAABNQAECn82AAMNAAoKCRsPEgBaAgANAAoKCRsPEgBaAgAOAAEKcg7Y0wApAAAAAA==.Arthemis:BAAANQAECgQIBQAAAA==.Arthroy:BAAANQABCgIIAwAAAA==.Arçano:BAAANQADCgMIAwABNQAECgoKPgAMAKoXAA==.',
As='Asbestos:BAAANQAECgMIAwAAAA==.Astramoon:BAABNQAECn8VAAIPAAUKggREAgGTAAAPAAUKggREAgGTAAAAAA==.',
Ay='Aylå:BAAANQAECgEIAQAAAA==.',
Ba='Baerd:BAAANQADCgcICQAAAA==.Barlz:BAAANQADCgUIEwAAAA==.',
Be='Beasthunt:BAABNQAECn8hAAIPAAkKxRyvSAAsAgAPAAkKxRyvSAAsAgAAAA==.Beatmywillie:BAAANQAECgUICAAAAA==.Bebby:BAAANQAECgUIEwAAAA==.Belienn:BAAANQAECgEIAQAAAA==.Belwolf:BAAANQADCggIHQAAAA==.Bennehona:BAAANQADCgEIAQAAAA==.Bergstrom:BAABNQAECn8rAAIQAAgKJQ3NtQCzAQAQAAgKJQ3NtQCzAQAAAA==.Betrayer:BAAANQAECgIIBAABNQAECgoKSwAIANIkAA==.',
Bi='Biancafiamma:BAAANQAECgIIBgAAAA==.Biancaneve:BAABNQAECn8kAAIRAAoKbRa0QgAYAgARAAoKbRa0QgAYAgAAAA==.',
Bo='Bombacløt:BAABNQAECn8sAAMJAAkKjBEfEwDaAQAJAAcKDBMfEwDaAQAIAAcK/A20eABeAQAAAA==.',
Br='Brastin:BAABNQAECn8kAAISAAgK/xfKHwBaAQASAAgK/xfKHwBaAQAAAA==.Brenell:BAABNQAECn8jAAIDAAoKQBHQtQAYAgADAAoKQBHQtQAYAgAAAA==.Brixscen:BAABNQAECn8iAAIIAAoKlRI2SgDjAQAIAAoKlRI2SgDjAQAAAA==.',
Bu='Bubblehearth:BAAANQAECgEIAQABNQAFFAUIEAATAHQLAA==.Buhliz:BAAANQAECgMIAwAAAA==.',
Ca='Cabëla:BAAANQAECgYIDgABNQAECggIEgALAAAAAA==.Caineicefall:BAAANQAECgUICQAAAA==.Calacolinda:BAABNQAECn8iAAMUAAcKaAURwAD8AAAUAAcKaAURwAD8AAAQAAYKIAjWMgHOAAAAAA==.',
Ce='Celestiall:BAAANQAECggIEQAAAA==.Ceridwyn:BAAANQADCggIGgAAAA==.',
Ch='Chadalonius:BAAANQADCgQIBAABNQAFFAcIFwAVAF4VAA==.Cheesecurd:BAAANQAECgIIAgAAAA==.Choal:BAAANQADCgYICwAAAA==.Chriswin:BAAANQAECgMIAwAAAA==.',
Cl='Claytonbigsb:BAAANQADCgYIBgABNQAECgYIDwALAAAAAA==.',
Co='Corahin:BAAANQAECgUIBgAAAA==.',
Cu='Cuecumba:BAAANQAECgcIEAAAAA==.',
Cy='Cynndi:BAAANQABCgYIBgAAAA==.',
Da='Dalren:BAACNQAFFH8WAAMWAAgKWxa8AQAlAQAWAAcKQxe8AQAlAQAXAAEK0hGBDABPAAA1AAQKf0sAAxYACgq5IYMEAFMDABYACgqJIYMEAFMDABcABQr7HRsNAAgBAAAA.Dalvix:BAAANQAECgYICQABNQAECgkJMAAKAGQiAA==.Damballàh:BAAANQADCgEIAQAAAA==.Dammedude:BAAANQAECgEIAgAAAA==.Darksun:BAAANQABCgEIAQAAAA==.Dartagnan:BAABNQAECn8iAAIPAAoK6BRSfwAOAgAPAAoK6BRSfwAOAgAAAA==.Darthmaul:BAABNQAECn9BAAIYAAoKdg/XJgCyAQAYAAoKdg/XJgCyAQAAAA==.David:BAABNQAECn8cAAIQAAoKAQqF1QBwAQAQAAoKAQqF1QBwAQAAAA==.',
De='Deathkush:BAAANQAECgEIAQAAAA==.Dendiian:BAAANQADCgYICQAAAA==.Depletor:BAABNQAECn8rAAMMAAoKGgqNugCKAQAMAAoKGgqNugCKAQAZAAMKCASbPABTAAAAAA==.Devils:BAAANQADCgEIAQAAAA==.',
Di='Diem:BAAANQAECgYICwAAAA==.Dinendal:BAAANQADCgEIAQAAAA==.Dirtydotss:BAAANQAECgQICQAAAA==.',
Do='Docholiday:BAABNQAECn8aAAQaAAcKcROQCADFAQAaAAYK+xWQCADFAQAbAAUKGgemRgB0AAAPAAIKmQHcPQFoAAAAAA==.Docsassist:BAAANQAECgcIDAAAAA==.Doradasplora:BAAANQADCgMIAwAAAA==.Dowedoes:BAABNQAECn9IAAIQAAoK9Qy9iQCkAQAQAAoK9Qy9iQCkAQAAAA==.',
Dr='Drachula:BAABNQAECn8ZAAMEAAcK0g9LmwBCAQAEAAcK0g9LmwBCAQAFAAEKPAiC8wA1AAAAAA==.Dracultra:BAAANQADCgYIBgABNQAECgoKIAAUAAEXAA==.Draeun:BAAANQAECggICQABNQAFFAgIFgAWAFsWAA==.Dreolan:BAABNQAECn8kAAIcAAkKMRL+HwDfAQAcAAkKMRL+HwDfAQAAAA==.Druaga:BAAANQAECggIDgAAAA==.Dràchula:BAAANQADCgYICQAAAA==.Dràúgr:BAAANQADCgMIAwAAAA==.',
Dy='Dyala:BAABNQAECn8nAAIcAAoKYB0XGAB/AgAcAAoKYB0XGAB/AgAAAA==.',
Dz='Dzznuts:BAAANQABCgYICgAAAA==.',
['Dé']='Démonléth:BAAANQAECgIIAwABNQAECgkJJgAdAEQZAA==.',
['Dö']='Dönövan:BAABNQAECn8tAAIQAAoKYwy7nQB8AQAQAAoKYwy7nQB8AQAAAA==.',
Eg='Eggyolk:BAABNQAECn8dAAIeAAoKpBdAFAAhAgAeAAoKpBdAFAAhAgAAAA==.',
El='Elastwo:BAAANQADCggIGQAAAA==.Eloise:BAAANQAECgUIBgAAAA==.Elvenbane:BAABNQAECn9IAAMfAAoKcRSXFAD/AQAfAAoKcRSXFAD/AQARAAgKWgOPoAAzAQAAAA==.',
Es='Espeon:BAAANQAECgUIBQABNQAECgoKFwAUAPkUAA==.',
Et='Ethereal:BAAANQAECgUIBQAAAA==.',
Eu='Eunliza:BAAANQAECggICAAAAA==.',
Ew='Ew:BAACNQAFFH8QAAMPAAYK6BWNBQD7AQAPAAYK6BWNBQD7AQAbAAEKyAdXJQBAAAA1AAQKf0gAAw8ACgrFIq8WAEADAA8ACgrFIq8WAEADABsABwpHGfM1AJ4BAAE1AAQKCgouAA0AziAA.',
Ex='Extrathick:BAAANQAECgEIAQAAAA==.',
Fa='Fathershale:BAAANQADCgYIFAAAAA==.',
Fe='Fedupdk:BAAANQADCgYIDQAAAA==.Feet:BAAANQAECgcICwAAAA==.Felidae:BAEANQAECgUICAAAAA==.Felps:BAAANQAECgEIAQAAAA==.',
Fi='Firedancer:BAAANQAECgUIDQAAAA==.Fizzfiend:BAAANQAECgEIAgAAAA==.',
Fo='Foulcor:BAAANQAECgQIBgABNQAECgkJIQAPAMUcAA==.',
Fr='Freakadeek:BAAANQAECgMIBgABNQAECgcIGgAaAHETAA==.Freâkadeek:BAAANQADCgQIBAABNQAECgcIGgAaAHETAA==.Frieren:BAABNQAECn8tAAICAAoKBxUxCgAoAgACAAoKBxUxCgAoAgAAAA==.Frëak:BAAANQADCgUIBgABNQAECgcIGgAaAHETAA==.',
Ga='Gabbyo:BAABNQAECn8oAAIcAAgKegn9MwA5AQAcAAgKegn9MwA5AQAAAA==.Galadorn:BAABNQAECn8wAAMKAAkKZCLbEQAQAwAKAAkKZCLbEQAQAwAgAAUKriBGEACuAQAAAA==.',
Ge='Genasis:BAAANQABCgMIBQAAAA==.Gerdash:BAAANQAECgYIEwAAAA==.Gerred:BAABNQAECn9CAAIMAAkK0SFDJgCcAgAMAAkK0SFDJgCcAgAAAA==.',
Gh='Ghallow:BAABNQAECn8cAAIGAAoKKxVrDAA/AgAGAAoKKxVrDAA/AgAAAA==.Ghosthowl:BAAANQAECgUIEAAAAA==.',
Gl='Gladur:BAAANQAECggICgABNQAFFAgIGAACAEAXAA==.',
Go='Goldenflame:BAAANQAECgcIDQAAAA==.Goldenlight:BAABNQAECn8vAAIRAAoKkRJmVgAgAgARAAoKkRJmVgAgAgAAAA==.Goldenmunc:BAAANQADCgIIAgAAAA==.Goldenone:BAABNQAECn8UAAIUAAYKMxygTADOAQAUAAYKMxygTADOAQAAAA==.Goldenpants:BAAANQADCggIDwAAAA==.',
Gr='Grandesaxx:BAAANQAECgQICgAAAA==.Grievous:BAABNQAECn9IAAIgAAoK3SXTAABXAwAgAAoK3SXTAABXAwAAAA==.',
Gu='Guggins:BAAANQABCggIDQAAAA==.',
Ha='Hailmary:BAAANQAECgcIEQAAAA==.Hakudoshi:BAAANQAECgUIDgAAAA==.Harmanee:BAAANQADCgYIBgAAAA==.Hauser:BAABNQAECn8qAAMQAAoK5x3+YwBvAgAQAAoK2B3+YwBvAgASAAEKFxitVwBGAAAAAA==.',
He='Healaga:BAAANQAECgUICQABNQAECgoKNgANAAkbAA==.Heinrich:BAAANQADCgMIAwAAAA==.',
Hh='Hhoonnzz:BAAANQADCgYIBgABNQAECgoKLgANAM4gAA==.',
Ho='Hornreaper:BAABNQAECn8jAAQhAAoKWBDULABAAQAhAAcKoQnULABAAQAXAAgK+w2SEAAvAQAWAAIKywRdJAA1AAAAAA==.',
Hu='Hubbabubbajr:BAABNQAECn8eAAIRAAgKJhwSRQAOAgARAAgKJhwSRQAOAgAAAA==.',
['Hü']='Hülkster:BAAANQADCgEIAQAAAA==.',
Il='Ilavengu:BAABNQAECn8kAAIKAAkK7CH3EACTAgAKAAkK7CH3EACTAgABNQAFFAUIEAAfADMgAA==.',
Ir='Irôn:BAAANQAECgEIAQAAAA==.',
Is='Isochu:BAAANQADCgMJAwAAAA==.',
Ja='Jayonor:BAABNQAECn9FAAMFAAoKCR3zHwBjAgAFAAoKCR3zHwBjAgAEAAEKwQCVOAEWAAAAAA==.',
Je='Jek:BAAANQAECgIIAwAAAA==.',
Jo='Jonohae:BAAANQAECgIIAQABNQAECgoKPgAMAKoXAA==.',
Ju='Judgethis:BAAANQADCggICAAAAA==.Juicycucci:BAAANQAECgYICQABNQAFFAUIEAATAHQLAA==.',
Ka='Kaevrielle:BAEBNQAECn8aAAMgAAoKmhmCDAD+AQAgAAoKmhmCDAD+AQAKAAIK/Q8VegA8AAAAAA==.Kaidrosa:BAAANQAECgIIAgAAAA==.Kainicefall:BAABNQAECn8sAAQiAAoKZxPDDADkAQAiAAkKWBPDDADkAQAYAAgKNgm/TQDUAAAeAAMKwBBJUgBnAAAAAA==.Kainicefell:BAAANQAECgIIBAAAAA==.Kainoficefal:BAABNQAECn8gAAMjAAoKrAukDQCPAQAjAAoKrAukDQCPAQAMAAgKEAZi3AAzAQAAAA==.Kaisa:BAAANQAECgQIBAAAAA==.Kaladîn:BAAANQAECgEIAQABNQAFFAgIGAACAEAXAA==.Kalokako:BAAANQAECgEIAQAAAA==.Kamel:BAAANQAECgEIAQAAAA==.Karwin:BAAANQAECggIEQAAAA==.',
Ke='Keeper:BAABNQAECn8jAAIBAAoKgxrABwBqAgABAAoKgxrABwBqAgABNQAFFAMICgAQAJciAA==.Keeperodark:BAABNQAECn8uAAIIAAoKCRTGQQD/AQAIAAoKCRTGQQD/AQABNQAFFAMICgAQAJciAA==.Keeperolight:BAACNQAFFH8KAAIQAAMKlyI4GAC+AAAQAAMKlyI4GAC+AAA1AAQKf1kAAhAACgp4JmECAIMDABAACgp4JmECAIMDAAAA.',
Ki='Kifo:BAAANQAECgUIBwAAAA==.Killkat:BAAANQAECgcIEQAAAA==.Kirkulus:BAAANQAECggICQAAAA==.',
Ko='Koojo:BAABNQAECn8jAAIiAAkK0Rr3BgB5AgAiAAkK0Rr3BgB5AgAAAA==.',
Ky='Kyndrassa:BAAANQADCggICAABNQAECgkJMAAKAGQiAA==.',
La='Lans:BAAANQAECgIIAgAAAA==.Larew:BAAANQAECgUIDAAAAA==.',
Le='Lealla:BAABNQAECn9HAAIYAAoKghxyFgBQAgAYAAoKghxyFgBQAgAAAA==.Leodin:BAAANQAECgIIAgAAAA==.Lethhunt:BAAANQAECgEIAQABNQAECgkJJgAdAEQZAA==.Letholas:BAABNQAECn8mAAQdAAkKRBl0NQAEAgAdAAgKHxl0NQAEAgANAAcKwxNfXgCWAQAOAAEKAADo0wApAAAAAA==.',
Li='Lightmàiden:BAAANQADCgEIAQAAAA==.Lilkingpunch:BAAANQADCgYIBgABNQAFFAYIDgAkAN0OAA==.Lizardgang:BAAANQAECgYIEQAAAA==.',
Lo='Loganshu:BAAANQAECgEIAQAAAA==.Lokan:BAABNQAECn83AAMPAAoKzx7OIACvAgAPAAoKzx7OIACvAgAaAAYKaA1qDAASAQAAAA==.Lots:BAABNQAECn84AAMIAAoKrCPrOwCfAgAIAAgKrSPrOwCfAgAJAAIKqSPmDwDLAAAAAA==.',
Lu='Ludakris:BAAANQAECggIEgAAAA==.',
['Lí']='Líonheart:BAABNQAECn8hAAIQAAkKKxGTjACeAQAQAAkKKxGTjACeAQAAAA==.',
Ma='Maami:BAAANQAECgYIDQAAAA==.Machognome:BAAANQADCgUIBAAAAA==.Mahina:BAABNQAECn8bAAIRAAYKtwEmygB9AAARAAYKtwEmygB9AAAAAA==.Makrabro:BAAANQAECgEIAQAAAA==.Marcille:BAAANQAECgcIDwAAAA==.Marquistanyl:BAAANQAECgMIAwAAAA==.Mattix:BAAANQADCggICAAAAA==.Matíx:BAABNQAECn8nAAMIAAgK/ReaZgCPAQAIAAgK/ReaZgCPAQAJAAIKVA49XABtAAAAAA==.Mayhaps:BAABNQAECn8zAAMPAAoKHA5aaQBBAgAPAAoKHA5aaQBBAgAbAAEKAABdoQAWAAAAAA==.Mayoke:BAAANQAECgEIAwAAAA==.',
Me='Mentaltitty:BAABNQAECn8bAAIDAAcKXRM44QDGAQADAAcKXRM44QDGAQAAAA==.',
Mi='Milhouse:BAABNQAECn9IAAIOAAoK6CNsBgAbAwAOAAoK6CNsBgAbAwAAAA==.Minerwor:BAAANQAECgUICwAAAA==.Mirrayla:BAAANQADCgEIAQAAAA==.Misty:BAAANQAECgUIDwAAAA==.',
Mm='Mmisty:BAABNQAECn84AAIYAAoKBhbnGwATAgAYAAoKBhbnGwATAgAAAA==.',
Mo='Momometaru:BAABNQAECn8nAAQJAAoKyxBQMgD8AAAIAAoKog4JhQDZAQAJAAQK8BFQMgD8AAAHAAMKnwo4GgC0AAABNQAECgoKKwAYAMoQAA==.Monsterbee:BAABNQAECn9QAAIIAAoKKxoKJQBuAgAIAAoKKxoKJQBuAgAAAA==.Morne:BAAANQADCggIFwAAAA==.',
Mu='Mustypizza:BAAANQAECgcIEQAAAA==.',
My='Mystery:BAABNQAECn9IAAMhAAoKzRsqEQCXAgAhAAoKzRsqEQCXAgAWAAIKYAorIwA7AAAAAA==.',
Na='Nailme:BAAANQAECgYIBwAAAA==.Nats:BAABNQAECn8hAAIEAAgKuhVAUwAaAgAEAAgKuhVAUwAaAgAAAA==.',
Ne='Neameny:BAABNQAECn8+AAIPAAoKoQ8OXgD0AQAPAAoKoQ8OXgD0AQAAAA==.',
Ni='Nightstar:BAAANQAECgYIBgAAAA==.',
Nu='Nualrossan:BAAANQADCgEIAgAAAA==.Nubrac:BAABNQAECn8gAAMcAAoKzRxFEACqAgAcAAoKzRxFEACqAgAYAAEKAADangAAAAAAAA==.',
Ob='Oblivion:BAABNQAECn9LAAMIAAoK0iTSCAAcAwAIAAoK0iTSCAAcAwAJAAIK0BQiVgB8AAAAAA==.',
Om='Omey:BAABNQAECn8UAAIQAAYKewMnPAHAAAAQAAYKewMnPAHAAAAAAA==.',
On='Onepercent:BAAANQAECggICAAAAA==.',
Pa='Pallyshore:BAAANQADCggICAAAAA==.Papichuló:BAAANQADCgMIBgABNQAECgcIGgAaAHETAA==.',
Pi='Pixae:BAABNQAECn8aAAIhAAkKeRDTJgCDAQAhAAkKeRDTJgCDAQAAAA==.',
Po='Porthoss:BAAANQABCgIIAgAAAA==.Portknight:BAAANQAECgEIAQAAAA==.Potatochip:BAAANQAECgIIAgAAAA==.Powerplant:BAACNQAFFH8RAAIPAAYKUB8ZCABVAQAPAAYKUB8ZCABVAQA1AAQKf0UAAg8ACgopJfgEAGMDAA8ACgopJfgEAGMDAAAA.',
Pu='Purrder:BAAANQAECgEIAQAAAA==.',
Py='Pyralys:BAABNQAECn9FAAIRAAoKOhDNSwD0AQARAAoKOhDNSwD0AQAAAA==.',
['Pâ']='Pârtyrockêr:BAAANQAECgYIBwABNQAECgcIGgAaAHETAA==.',
['Pä']='Pärts:BAAANQADCgQIBAABNQAECggIEQALAAAAAA==.',
Ra='Raelene:BAAANQADCgYICQAAAA==.Ragedk:BAAANQAECgIIAwABNQAECgcIBwALAAAAAA==.Ragenbefcake:BAAANQAECgQIBQAAAA==.Ragetality:BAAANQAECgcIBwAAAA==.Rallaster:BAAANQAECgUIDwABNQAECgoKSAAfAHEUAA==.Rampage:BAAANQABCgUIAgAAAA==.Raserei:BAABNQAECn8kAAMjAAoKYxydBwB6AgAjAAgKxx2dBwB6AgAMAAUK1RhssgD/AAAAAA==.Rattelyr:BAAANQADCgQIBAAAAA==.Rawb:BAAANQAECgYJCgABNQAECgoKLgANAM4gAA==.',
Re='Recolada:BAAANQADCgcJDAAAAA==.Regicee:BAABNQAECn8VAAMNAAgKchOUVQC7AQANAAcK7BWUVQC7AQAOAAEKDwernQAyAAAAAA==.',
Ri='Riffraff:BAAANQADCggICgAAAA==.Ripperoni:BAAANQAECgEIAQAAAA==.',
Ro='Rockdyou:BAABNQAECn8jAAMdAAoKsxOWMADSAQAdAAkKtA6WMADSAQANAAgKyxPuMwBAAQAAAA==.Roflstomper:BAAANQADCgMIAwAAAA==.Rotlobster:BAABNQAECn8fAAIHAAkKhyJAAQBUAwAHAAkKhyJAAQBUAwABNQAECgoKOgAGAEMeAA==.Rottenrigger:BAAANQABCgQIBAAAAA==.',
Ru='Rudal:BAAANQADCgIIAgAAAA==.Rundvelt:BAAANQADCgIIAgAAAA==.',
Ry='Rydiaicefall:BAAANQAECgUIEQAAAA==.',
Sa='Sapkick:BAAANQAECgQIBAAAAA==.',
Se='Selina:BAAANQAECgQIBAAAAA==.Serdwarf:BAABNQAECn8oAAMRAAoKixicVQAiAgARAAgKdhmcVQAiAgAfAAgK4hCfIABrAQAAAA==.Sertian:BAAANQADCgQIBAAAAA==.',
Sh='Shatha:BAAANQADCgQIBQAAAA==.Sherten:BAAANQAECgIIAwAAAA==.Shooturiout:BAAANQAECgMIBAAAAA==.Shtanky:BAABNQAECn8fAAIZAAoKZxKfFgDAAQAZAAoKZxKfFgDAAQAAAA==.',
Si='Sinpony:BAAANQABCgQIBAAAAA==.Sixsixsix:BAAANQADCggJCgABNQAECgoKLgANAM4gAA==.',
Sk='Sketch:BAAANQAECgIIAgABNQAFFAgIGQAeADEWAA==.Skoogz:BAABNQAECn8XAAQOAAoKNAyLSwAAAQAOAAcKDg6LSwAAAQAdAAMKHQm6ggCRAAANAAIKoQSYjAAnAAAAAA==.',
So='Soggyy:BAAANQAECgEIAQAAAA==.Sogsy:BAABNQAECn8UAAIDAAcKKwX4LgE+AQADAAcKKwX4LgE+AQAAAA==.Soleri:BAAANQAECgYICgAAAA==.Soulfulgingr:BAAANQAECgUIBwAAAA==.',
Sq='Squiblus:BAAANQADCgYIBgAAAA==.',
St='Styx:BAABNQAECn8bAAIbAAcK4gTOMADYAAAbAAcK4gTOMADYAAAAAA==.Stza:BAAANQABCgYICAAAAA==.',
Su='Sunbake:BAAANQAECgUIEQAAAA==.',
Sw='Sweetbbyraze:BAACNQAFFH8RAAMWAAYKyBPYBAB8AQAWAAUK/BbYBAB8AQAXAAEKLQqSDQBHAAA1AAQKfyoAAxYACgr8HrIIAOwCABYACgpaHrIIAOwCABcAAQpWG88YAFEAAAAA.Swiftzz:BAAANQAECggICwAAAA==.',
Sz='Szayell:BAAANQADCgQIBAAAAA==.',
['Sí']='Sín:BAAANQADCgIJAgABNQAECgoKLgANAM4gAA==.',
Ta='Talipally:BAABNQAECn8eAAMQAAoKmwqK1AByAQAQAAoKmwqK1AByAQASAAEKQAMybQAdAAAAAA==.Taliwhacker:BAAANQADCgMIAwABNQAECgoKHgAQAJsKAA==.Talonleafgrd:BAABNQAECn8gAAIbAAcKYRP8HgBkAQAbAAcKYRP8HgBkAQAAAA==.Tandsonna:BAAANQAECggIEQAAAA==.Tanisong:BAAANQAECgUICAAAAA==.',
Te='Terayus:BAAANQADCgIJAgAAAA==.Terraform:BAAANQADCgYICwAAAA==.',
Th='Thalor:BAABNQAECn8hAAMOAAoKGRy0EwBnAgAOAAoKGRy0EwBnAgAdAAMK0BZ5jgB9AAABNQAFFAYIDQAlAG8ZAA==.Thekingpunch:BAACNQAFFH8OAAIkAAYK3Q7EAwCJAQAkAAYK3Q7EAwCJAQA1AAQKf2EAAiQACgo0IsQFAEEDACQACgo0IsQFAEEDAAAA.Thenle:BAAANQAECgEIAQAAAA==.Theworst:BAAANQAECgYIBgABNQAECgoKLgANAM4gAA==.Thiel:BAAANQAECggIBwAAAA==.',
Ti='Tillwar:BAABNQAECn9KAAIMAAoKsBrlPAA/AgAMAAoKsBrlPAA/AgAAAA==.Timmu:BAAANQADCgEIAQAAAA==.Tiàna:BAAANQADCgEIAQAAAA==.',
To='Tofu:BAABNQAECn8bAAINAAoK1x2SLwBxAgANAAoK1x2SLwBxAgAAAA==.Tortillachip:BAAANQADCgYIBgAAAA==.Totemayhem:BAAANQADCgcIBwAAAA==.',
Tr='Treibh:BAABNQAECn9DAAIcAAoKthonEACsAgAcAAoKthonEACsAgAAAA==.Trulydps:BAABNQAECn8pAAIPAAoKyArdjgB8AQAPAAoKyArdjgB8AQAAAA==.',
Tu='Tust:BAAANQAECgQIBwABNQAECgUIDQALAAAAAA==.',
Ty='Tymora:BAAANQAECgEIAQABNQAECgoKSAAfAHEUAA==.',
['Të']='Tërris:BAABNQAECn8ZAAIOAAoKOhcbPAATAgAOAAoKOhcbPAATAgAAAA==.',
['Tî']='Tîlldeath:BAAANQAECgUICwAAAA==.',
Ug='Uglyrazorbak:BAAANQAECgEIAQAAAA==.',
Un='Undzl:BAACNQAFFH8KAAMdAAIKox/SEwChAAAdAAIKox/SEwChAAANAAEKcgYWJQA4AAA1AAQKf1MAAw0ACgqrJUwKAGoDAA0ACQqhIkwKAGoDAB0ACQoJJccLADkDAAAA.Unknowna:BAAANQADCgYIBgAAAA==.',
Ur='Urowndad:BAAANQADCgIIAgABNQAECgYIDwALAAAAAA==.Urownmother:BAAANQAECgEIAQABNQAECgYIDwALAAAAAA==.',
Va='Vallez:BAEBNQAECn8rAAMUAAoKBSV1DQBeAwAUAAoKBSV1DQBeAwAQAAEKAACargEwAAAAAA==.Varnusshadow:BAAANQAECgIIBgAAAA==.Vayn:BAABNQAECn8aAAIKAAcK7gq3RwD2AAAKAAcK7gq3RwD2AAAAAA==.',
Ve='Velladoree:BAAANQAECgIIAwAAAA==.Vexahlia:BAAANQAECggIDgAAAA==.',
Vg='Vgurlpally:BAAANQADCgIIAgAAAA==.',
['Vé']='Véñable:BAABNQAECn8eAAQBAAkK2A1EFACEAQABAAkKvA1EFACEAQAmAAMK2gQRFwB1AAAVAAEKAADcVgAnAAAAAA==.',
Wa='Waveygravee:BAAANQADCgcJCwAAAA==.Wavygraivy:BAABNQAECn8bAAIEAAYKtRJEcQBJAQAEAAYKtRJEcQBJAQAAAA==.',
We='Wedragon:BAAANQAECgUICAAAAA==.',
Wi='Wildearth:BAAANQAECgQIAwAAAA==.',
Wo='Woofwoof:BAAANQAECgIIBAAAAA==.Wooshh:BAAANQAECgUIDwAAAA==.',
Xh='Xhexana:BAABNQAECn8hAAIEAAcK+BHcjQBmAQAEAAcK+BHcjQBmAQABNQAECgoKPgAPAKEPAA==.',
Xi='Xianofukuju:BAABNQAECn8rAAIYAAoKyhC+QwDlAQAYAAoKyhC+QwDlAQAAAA==.',
Xr='Xrayl:BAACNQAFFH8FAAMlAAMKNg5CEACLAAAlAAMKNg5CEACLAAAnAAEK2Ay4CAA8AAA1AAQKfzUAAycACgpzHAcLAF4CACcACgpqGgcLAF4CACUABgq+HL0sALQBAAAA.',
Xz='Xzerocool:BAAANQAECgYIDwAAAA==.',
Yo='Yoshikazu:BAAANQAECgIIAgAAAA==.',
Za='Zaarah:BAAANQADCgUIGQAAAA==.Zanthian:BAAANQABCgEIAQAAAA==.',
Ze='Zendezoth:BAABNQAECn8eAAIWAAoK+wwICgC9AQAWAAoK+wwICgC9AQAAAA==.Zevthekuatin:BAABNQAECn8nAAIPAAoKlw9YUwAPAgAPAAoKlw9YUwAPAgAAAA==.',
Zh='Zhiva:BAABNQAECn8mAAIYAAoKoAhGNQBOAQAYAAoKoAhGNQBOAQAAAA==.',
Zy='Zykoz:BAAANQAECgcIEQAAAA==.',
['Åy']='Åyna:BAAANQAECgEIAQAAAA==.',
['Ða']='Ðaddy:BAAANQAECgcIEQAAAA==.Ðamned:BAAANQAECgUICgABNQAECgoKLgANAM4gAA==.',
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
