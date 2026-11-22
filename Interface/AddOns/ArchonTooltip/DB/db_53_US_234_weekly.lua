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
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abel:BAEANQADCggICAABNQAECgkJHgABANgNAA==.',
Ae='Aeidail:BAACNQAFFH8YAAMCAAgKQBdwBQC7AAADAAUK3xe0GgCmAQACAAUK7hNwBQC7AAA1AAQKf0cAAwIACgonJnUAAHoDAAIACgonJnUAAHoDAAMACQogIulUANYCAAAA.',
Ag='Agraceful:BAAANQAECgUIBgAAAA==.',
Ai='Aidton:BAAANQAECgEIAQAAAA==.Aiobhicefall:BAAANQAECgYIDAAAAA==.Aiobhicefell:BAAANQAECgUIDgAAAA==.Aiobicefall:BAABNQAECn8aAAQEAAgK2Q8HdABXAQAEAAgK2Q8HdABXAQAFAAIKcg/j9AA8AAAGAAEKAAC0OwAcAAAAAA==.Aioboicefall:BAAANQADCggIDAAAAA==.Aioicefall:BAAANQAECgQIBAAAAA==.Aiza:BAABNQAECn9UAAQHAAoKLhkNDgBzAQAIAAgKdRmCZAAsAgAHAAYKFxUNDgBzAQAJAAMKkguNSQCjAAAAAA==.',
Al='Albinoknight:BAAANQADCgEIAQAAAA==.Alessia:BAAANQAECgQIBAAAAA==.Allarria:BAAANQADCggICAABNQAECgoKNAAKAM0hAA==.Altic:BAAANQAECgMIAwABNQAECggIBwALAAAAAA==.',
An='Angrypants:BAABNQAECn8YAAIMAAgK8AwotAAQAQAMAAgK8AwotAAQAQAAAA==.Animalfriend:BAAANQAECgMIAwAAAA==.Anklesmasher:BAAANQAECgUIEAAAAA==.Antisocial:BAAANQADCggIEAABNQAECgoKLgANAM4gAA==.',
Ar='Archfury:BAAANQABCgYIBwAAAA==.Ardicon:BAAANQADCgIIAgAAAA==.Arfaz:BAABNQAECn83AAMNAAoKCRuCEwBYAgANAAoKCRuCEwBYAgAOAAEKcg7Y0wApAAAAAA==.Arthemis:BAAANQAECgQIBAAAAA==.Arthroy:BAAANQABCgIIAwAAAA==.Arçano:BAAANQADCgMIAwABNQAECgoKPgAMAKoXAA==.',
As='Asbestos:BAAANQAECgMIAwAAAA==.Astramoon:BAABNQAECn8VAAIPAAUKggSEFgHWAAAPAAUKggSEFgHWAAAAAA==.',
Ay='Aylå:BAAANQADCgYIBgAAAA==.',
Ba='Baerd:BAAANQADCgcICQAAAA==.Barlz:BAAANQADCgUIEwAAAA==.',
Be='Beasthunt:BAABNQAECn8hAAIPAAkKxRz8UQApAgAPAAkKxRz8UQApAgAAAA==.Beatmywillie:BAAANQAECgUIBQAAAA==.Bebby:BAAANQAECgUIEwAAAA==.Belienn:BAAANQADCggICAAAAA==.Belwolf:BAAANQADCggIHgAAAA==.Bennehona:BAAANQADCgEIAQAAAA==.Bergstrom:BAABNQAECn8xAAIQAAoKDQyipACFAQAQAAoKDQyipACFAQAAAA==.Betrayer:BAAANQAECgIIAwABNQAECgoKUQAIANIkAA==.',
Bi='Biancafiamma:BAAANQAECgIIAgAAAA==.Biancaneve:BAABNQAECn8kAAIRAAoKbRbxSQAQAgARAAoKbRbxSQAQAgAAAA==.',
Bo='Bombacløt:BAABNQAECn8xAAMJAAoKuBAfEwDaAQAJAAcKDBMfEwDaAQAIAAgKjA1SbgCOAQAAAA==.Bombadin:BAAANQAECgUIBQAAAA==.',
Br='Brastin:BAABNQAECn8kAAISAAgK/xcTIwBWAQASAAgK/xcTIwBWAQAAAA==.Brenell:BAABNQAECn8jAAIDAAoKQBHQtQAYAgADAAoKQBHQtQAYAgAAAA==.Brixscen:BAABNQAECn8jAAIIAAoKlRIYUADkAQAIAAoKlRIYUADkAQAAAA==.',
Bu='Bubblehearth:BAAANQAECgEIAQABNQAFFAUIEAATAHQLAA==.Buhliz:BAAANQAECgMIAwAAAA==.',
Ca='Cabëla:BAAANQAECgYIDAABNQAECggIEQALAAAAAA==.Caineicefall:BAAANQAECgUIBwAAAA==.Calacolinda:BAABNQAECn8iAAMUAAcKaAURwAD8AAAUAAcKaAURwAD8AAAQAAYKIAjWMgHOAAAAAA==.',
Ce='Celestiall:BAAANQAECggIEAAAAA==.Ceridwyn:BAAANQADCggIGwAAAA==.',
Ch='Chadalonius:BAAANQADCgQIBAABNQAFFAcIFwAVAF4VAA==.Cheesecurd:BAAANQAECgIIAgAAAA==.Choal:BAAANQADCgYICwAAAA==.Chriswin:BAAANQAECgMIAwAAAA==.',
Cl='Claytonbigsb:BAAANQADCgYIBgABNQAECgYIDwALAAAAAA==.',
Co='Corahin:BAAANQAECgUIBgAAAA==.',
Cu='Cuecumba:BAAANQAECgcIEAAAAA==.',
Cy='Cynndi:BAAANQABCgYIBgAAAA==.',
Da='Dalren:BAACNQAFFH8WAAMWAAgKWxb9AQAfAQAWAAcKQxf9AQAfAQAXAAEK0hEbDgBPAAA1AAQKf0sAAxYACgq5IYMEAFMDABYACgqJIYMEAFMDABcABQr7HQcOAAgBAAAA.Dalvix:BAAANQAECgYICQABNQAECgoKNAAKAM0hAA==.Damballàh:BAAANQADCgEIAQAAAA==.Dammedude:BAAANQABCgMIAwAAAA==.Darksun:BAAANQABCgEIAQAAAA==.Dartagnan:BAABNQAECn8iAAIPAAoK6BRSfwAOAgAPAAoK6BRSfwAOAgAAAA==.Darthmaul:BAABNQAECn9HAAIYAAoKdg/qKQCwAQAYAAoKdg/qKQCwAQAAAA==.David:BAABNQAECn8cAAIQAAoKAQqF1QBwAQAQAAoKAQqF1QBwAQAAAA==.',
De='Dendiian:BAAANQADCgYICQAAAA==.Depletor:BAABNQAECn8rAAMMAAoKGgqNugCKAQAMAAoKGgqNugCKAQAZAAMKCASbPABTAAAAAA==.Devils:BAAANQADCgEIAQAAAA==.',
Di='Diem:BAAANQAECgUIDgAAAA==.Dinendal:BAAANQADCgEIAQAAAA==.Dirtydotss:BAAANQAECgQICQAAAA==.',
Do='Docholiday:BAABNQAECn8aAAQaAAcKcROQCADFAQAaAAYK+xWQCADFAQAbAAUKGgduSgB0AAAPAAIKmQHcPQFoAAAAAA==.Docsassist:BAAANQAECgcIDAAAAA==.Doradasplora:BAAANQADCgMIAwAAAA==.Dowedoes:BAABNQAECn9OAAIQAAoKGw3HkwClAQAQAAoKGw3HkwClAQAAAA==.',
Dr='Drachula:BAABNQAECn8ZAAMEAAcK0g9LmwBCAQAEAAcK0g9LmwBCAQAFAAEKPAgA/wA1AAAAAA==.Dracultra:BAAANQADCgYIBgABNQAECgoKIAAUAAEXAA==.Draeun:BAAANQAECggICQABNQAFFAgIFgAWAFsWAA==.Dreolan:BAABNQAECn8kAAIcAAkKMRJRIwDcAQAcAAkKMRJRIwDcAQAAAA==.Druaga:BAAANQAECggIDgAAAA==.Dràchula:BAAANQADCgYICQAAAA==.Dràúgr:BAAANQADCgMIAwAAAA==.',
Dy='Dyala:BAABNQAECn8nAAIcAAoKYB0XGAB/AgAcAAoKYB0XGAB/AgAAAA==.',
Dz='Dzznuts:BAAANQABCgYICgAAAA==.',
['Dé']='Démonléth:BAAANQAECgIIAgABNQAECgkJJgAdAEQZAA==.',
['Dö']='Dönövan:BAABNQAECn8zAAIQAAoKig3ToQCKAQAQAAoKig3ToQCKAQAAAA==.',
Eg='Eggyolk:BAABNQAECn8dAAIeAAoKpBdAFAAhAgAeAAoKpBdAFAAhAgAAAA==.',
El='Elastwo:BAAANQADCggIGQAAAA==.Eloise:BAAANQAECgYICwAAAA==.Elvenbane:BAABNQAECn9IAAMfAAoKcRQoFgD/AQAfAAoKcRQoFgD/AQARAAgKWgOPoAAzAQAAAA==.',
Es='Espeon:BAAANQAECgUIBQABNQAECgoKFwAUAPkUAA==.',
Et='Ethereal:BAAANQAECgUIBQAAAA==.',
Eu='Eunliza:BAAANQAECggICAAAAA==.',
Ew='Ew:BAACNQAFFH8QAAMPAAYK6BWNBQD7AQAPAAYK6BWNBQD7AQAbAAEKyAdXJQBAAAA1AAQKf0gAAw8ACgrFIq8WAEADAA8ACgrFIq8WAEADABsABwpHGfM1AJ4BAAE1AAQKCgouAA0AziAA.',
Ex='Extrathick:BAAANQAECgEIAQAAAA==.',
Fa='Fathershale:BAAANQADCgYIFAAAAA==.',
Fe='Fedupdk:BAAANQADCgYIDQAAAA==.Feet:BAAANQAECgcICwAAAA==.Felidae:BAEANQAECgUIBwAAAA==.',
Fi='Firedancer:BAAANQAECgUICwAAAA==.Fizzfiend:BAAANQADCggIDQAAAA==.',
Fo='Foulcor:BAAANQAECgQIBAABNQAECgkJIQAPAMUcAA==.',
Fr='Freakadeek:BAAANQAECgMIBgABNQAECgcIGgAaAHETAA==.Freâkadeek:BAAANQADCgQIBAABNQAECgcIGgAaAHETAA==.Frieren:BAABNQAECn8tAAICAAoKBxUxCgAoAgACAAoKBxUxCgAoAgAAAA==.Frëak:BAAANQADCgUIBgABNQAECgcIGgAaAHETAA==.',
Fu='Furiosa:BAAANQAECgUIBQAAAA==.',
Ga='Gabbyo:BAABNQAECn8pAAIcAAkK2Ah3MwBWAQAcAAkK2Ah3MwBWAQAAAA==.Galadorn:BAABNQAECn80AAMKAAoKzSFKDgDEAgAKAAoKzSFKDgDEAgAgAAUKriBGEACuAQAAAA==.',
Ge='Genasis:BAAANQABCgMIBQAAAA==.Gerdash:BAABNQAECn8UAAMdAAYKoBJRVABdAQAdAAYKoBJRVABdAQANAAEKdgN28QAlAAAAAA==.Gerred:BAABNQAECn9EAAIMAAkK0SHHKgCUAgAMAAkK0SHHKgCUAgAAAA==.',
Gh='Ghallow:BAABNQAECn8iAAIGAAoKyhX4DABGAgAGAAoKyhX4DABGAgAAAA==.Ghosthowl:BAAANQAECgUIDAAAAA==.',
Gl='Gladur:BAAANQAECggICgABNQAFFAgIGAACAEAXAA==.',
Go='Goldenflame:BAAANQAECgcICwAAAA==.Goldenlight:BAABNQAECn8vAAIRAAoKkRJmVgAgAgARAAoKkRJmVgAgAgAAAA==.Goldenmunc:BAAANQADCgIIAgAAAA==.Goldenone:BAABNQAECn8UAAIUAAYKMxwBUwDJAQAUAAYKMxwBUwDJAQAAAA==.Goldenpants:BAAANQADCggIDwAAAA==.',
Gr='Grandesaxx:BAAANQAECgQICAAAAA==.Grievous:BAABNQAECn9OAAIgAAoK3SXtAABWAwAgAAoK3SXtAABWAwAAAA==.',
Gu='Guggins:BAAANQABCggIDQAAAA==.',
Ha='Hailmary:BAABNQAECn8YAAIRAAgKjh+WLgCLAgARAAgKjh+WLgCLAgAAAA==.Hakudoshi:BAAANQAECgUIDgAAAA==.Harmanee:BAAANQADCgYIBgAAAA==.Hauser:BAABNQAECn8qAAMQAAoK5x3+YwBvAgAQAAoK2B3+YwBvAgASAAEKFxj2XABGAAAAAA==.',
He='Healaga:BAAANQAECgUIBwABNQAECgoKNwANAAkbAA==.Heinrich:BAAANQADCgMIAwAAAA==.',
Hh='Hhoonnzz:BAAANQADCgYIBgABNQAECgoKLgANAM4gAA==.',
Ho='Hornreaper:BAABNQAECn8jAAQhAAoKWBDULABAAQAhAAcKoQnULABAAQAXAAgK+w2SEAAvAQAWAAIKywQaJgA1AAAAAA==.',
Hu='Hubbabubbajr:BAABNQAECn8eAAIRAAgKJhy/TAAFAgARAAgKJhy/TAAFAgAAAA==.',
['Hü']='Hülkster:BAAANQADCgEIAQAAAA==.',
Il='Ilavengu:BAABNQAECn8mAAIKAAkKmSIgEQCiAgAKAAkKmSIgEQCiAgABNQAFFAUIEAAfADMgAA==.',
Is='Isochu:BAAANQADCgMJAwAAAA==.',
Ja='Jayonor:BAABNQAECn9LAAMFAAoKCR1TIwBeAgAFAAoKCR1TIwBeAgAEAAQKRQhiugCkAAAAAA==.',
Je='Jek:BAAANQAECgQIBwAAAA==.',
Jo='Jonohae:BAAANQAECgIIAQABNQAECgoKPgAMAKoXAA==.',
Ju='Judgethis:BAAANQADCggICAAAAA==.Juicycucci:BAAANQAECgYICQABNQAFFAUIEAATAHQLAA==.',
Ka='Kaevrielle:BAEBNQAECn8aAAMgAAoKmhmCDAD+AQAgAAoKmhmCDAD+AQAKAAIK/Q+4gQA6AAAAAA==.Kaidrosa:BAAANQAECgIIAgAAAA==.Kainicefall:BAABNQAECn8tAAQiAAoKZxOFDgDiAQAiAAkKWBOFDgDiAQAYAAgKNgmqUgDUAAAeAAMKwBDBVwBmAAAAAA==.Kainicefell:BAAANQAECgIIAgAAAA==.Kainoficefal:BAABNQAECn8iAAMjAAoK3gsHDwCOAQAjAAoK3gsHDwCOAQAMAAgKEAZi3AAzAQAAAA==.Kaisa:BAAANQAECgQIBAAAAA==.Kaladîn:BAAANQAECgEIAQABNQAFFAgIGAACAEAXAA==.Kalokako:BAAANQADCgEIAQAAAA==.Kamel:BAAANQABCgQIBQAAAA==.Karwin:BAAANQAECggICwAAAA==.',
Ke='Keeper:BAABNQAECn8oAAIBAAoKPRxxCABlAgABAAoKPRxxCABlAgABNQAFFAQICwAQADQhAA==.Keeperodark:BAABNQAECn8yAAIIAAoKJRccRwD/AQAIAAoKJRccRwD/AQABNQAFFAQICwAQADQhAA==.Keeperolight:BAACNQAFFH8LAAIQAAQKNCEyDgAVAQAQAAQKNCEyDgAVAQA1AAQKf18AAhAACgp4JgcDAH4DABAACgp4JgcDAH4DAAAA.',
Ki='Kifo:BAAANQAECgUIBwAAAA==.Killkat:BAAANQAECgcIEQAAAA==.Kirkulus:BAAANQAECggICQAAAA==.',
Ko='Koojo:BAABNQAECn8nAAIiAAkK0RrqBwB0AgAiAAkK0RrqBwB0AgAAAA==.',
Ky='Kyndrassa:BAAANQADCggICAABNQAECgoKNAAKAM0hAA==.',
La='Lans:BAAANQAECgIIAgAAAA==.Larew:BAAANQAECgUICAAAAA==.',
Le='Lealla:BAABNQAECn9NAAIYAAoKghxaFQBtAgAYAAoKghxaFQBtAgAAAA==.Leodin:BAAANQAECgIIAgAAAA==.Lethhunt:BAAANQAECgEIAQABNQAECgkJJgAdAEQZAA==.Letholas:BAABNQAECn8mAAQdAAkKRBl0NQAEAgAdAAgKHxl0NQAEAgANAAcKwxNfXgCWAQAOAAEKAADo0wApAAAAAA==.',
Li='Lightmàiden:BAAANQADCgEIAQAAAA==.Lilkingpunch:BAAANQADCgYIBgABNQAFFAYIDgAkAN0OAA==.Lizardgang:BAAANQAECgcIEQAAAA==.',
Ll='Llynath:BAAANQAECgQIBAAAAA==.',
Lo='Lokan:BAABNQAECn83AAMPAAoKzx7ZJQCnAgAPAAoKzx7ZJQCnAgAaAAYKaA1qDAASAQAAAA==.Lots:BAABNQAECn84AAMIAAoKrCPrOwCfAgAIAAgKrSPrOwCfAgAJAAIKqSNyEQDKAAAAAA==.',
Lu='Ludakris:BAAANQAECggIEQAAAA==.',
['Lí']='Líonheart:BAABNQAECn8mAAIQAAoKHRLaaAD/AQAQAAoKHRLaaAD/AQAAAA==.',
Ma='Maami:BAAANQAECgYICwAAAA==.Machognome:BAAANQADCgUIBAAAAA==.Mahina:BAABNQAECn8fAAIRAAYKiwImywCRAAARAAYKiwImywCRAAAAAA==.Makrabro:BAAANQABCgIIAgAAAA==.Marcille:BAAANQAECgcIDgAAAA==.Marquistanyl:BAAANQAECgMIAwAAAA==.Mattix:BAAANQADCggICAAAAA==.Matíx:BAABNQAECn8nAAMIAAgK/RcBfADwAQAIAAgK/RcBfADwAQAJAAIKVA49XABtAAAAAA==.Mayhaps:BAABNQAECn8zAAMPAAoKHA5aaQBBAgAPAAoKHA5aaQBBAgAbAAEKAABdoQAWAAAAAA==.Mayoke:BAAANQAECgEIAwAAAA==.',
Me='Mentaltitty:BAABNQAECn8bAAIDAAcKXRM44QDGAQADAAcKXRM44QDGAQAAAA==.',
Mi='Milhouse:BAABNQAECn9OAAIOAAoK6CMiBwAVAwAOAAoK6CMiBwAVAwAAAA==.Minerwor:BAAANQAECgUICwAAAA==.Mirrayla:BAAANQADCgEIAQAAAA==.Misty:BAAANQAECggIEgAAAA==.',
Mm='Mmisty:BAABNQAECn9BAAIYAAoKCBbcHQATAgAYAAoKCBbcHQATAgAAAA==.',
Mo='Momometaru:BAABNQAECn8nAAQJAAoKyxBQMgD8AAAIAAoKog4JhQDZAQAJAAQK8BFQMgD8AAAHAAMKnwo4GgC0AAABNQAECgoKKwAYAMoQAA==.Monsterbee:BAACNQAFFH8FAAIIAAMKNgqaHADLAAAIAAMKNgqaHADLAAA1AAQKf1YAAggACgpbGt4oAGwCAAgACgpbGt4oAGwCAAAA.Morne:BAAANQADCggIFwAAAA==.',
Mu='Mustypizza:BAAANQAECgcIEQAAAA==.',
My='Mystery:BAABNQAECn9OAAMhAAoKfxwVCgCXAgAhAAoKfxwVCgCXAgAWAAIKYAr3JAA6AAAAAA==.',
['Mì']='Mìndfrêêk:BAAANQADCgQIBAAAAA==.',
Na='Nailme:BAAANQAECgYIBgAAAA==.Nats:BAABNQAECn8hAAIEAAgKuhVAUwAaAgAEAAgKuhVAUwAaAgAAAA==.',
Ne='Neameny:BAABNQAECn8+AAIPAAoKoQ8TaQDxAQAPAAoKoQ8TaQDxAQAAAA==.',
Ni='Nightstar:BAAANQAECgYIBgAAAA==.',
Nu='Nualrossan:BAAANQADCgEIAgAAAA==.Nubrac:BAABNQAECn8gAAMcAAoKzRwVEgCnAgAcAAoKzRwVEgCnAgAYAAEKAABYpgAAAAAAAA==.',
Ob='Oblivion:BAABNQAECn9RAAMIAAoK0iTbCQAcAwAIAAoK0iTbCQAcAwAJAAIK0BQiVgB8AAAAAA==.',
Om='Omey:BAABNQAECn8UAAIQAAYKewMnPAHAAAAQAAYKewMnPAHAAAAAAA==.',
On='Onepercent:BAAANQAECggIDQAAAA==.',
Pa='Pallyshore:BAAANQADCggICAAAAA==.Papichuló:BAAANQADCgMIBgABNQAECgcIGgAaAHETAA==.',
Pi='Pixae:BAABNQAECn8aAAIhAAkKeRDTJgCDAQAhAAkKeRDTJgCDAQAAAA==.',
Po='Porthoss:BAAANQABCgIIAgAAAA==.Portknight:BAAANQAECgEIAQAAAA==.Potatochip:BAAANQAECgIIAgAAAA==.Powerplant:BAACNQAFFH8SAAIPAAcKSRw4BQCrAQAPAAcKSRw4BQCrAQA1AAQKf0UAAg8ACgopJQsGAF0DAA8ACgopJQsGAF0DAAAA.',
Pu='Purrder:BAAANQAECgEIAQAAAA==.',
Py='Pyralys:BAABNQAECn9FAAIRAAoKOhDPUwDsAQARAAoKOhDPUwDsAQAAAA==.',
['Pâ']='Pârtyrockêr:BAAANQAECgYIBwABNQAECgcIGgAaAHETAA==.',
['Pä']='Pärts:BAAANQADCgQIBAABNQAECggIEQALAAAAAA==.',
Ra='Raelene:BAAANQADCgYICQAAAA==.Ragedk:BAAANQAECgIIAwABNQAECgcIBwALAAAAAA==.Ragenbefcake:BAAANQAECgQIBAAAAA==.Ragetality:BAAANQAECgcIBwAAAA==.Rallaster:BAABNQAECn8XAAITAAoKHgrjJwBaAQATAAoKHgrjJwBaAQABNQAECgoKSAAfAHEUAA==.Rampage:BAAANQABCgUIAgAAAA==.Raserei:BAABNQAECn8kAAMjAAoKYxydBwB6AgAjAAgKxx2dBwB6AgAMAAUK1RhivAD+AAAAAA==.Rattelyr:BAAANQADCgQIBAAAAA==.Rawb:BAAANQAECgYJCgABNQAECgoKLgANAM4gAA==.',
Re='Recolada:BAAANQADCgcJDAAAAA==.Regicee:BAABNQAECn8VAAMNAAgKchOUVQC7AQANAAcK7BWUVQC7AQAOAAEKDwc0owAyAAAAAA==.',
Ri='Riffraff:BAAANQADCggICgAAAA==.',
Ro='Rockdyou:BAABNQAECn8jAAMdAAoKsxN6NQDNAQAdAAkKtA56NQDNAQANAAgKyxNFNwA+AQAAAA==.Roflstomper:BAAANQADCgMIAwAAAA==.Rotlobster:BAABNQAECn8fAAIHAAkKhyJAAQBUAwAHAAkKhyJAAQBUAwABNQAECgoKOgAGAEMeAA==.Rottenrigger:BAAANQABCgQIBAAAAA==.',
Ru='Rudal:BAAANQADCgIIAgAAAA==.Rundvelt:BAAANQADCgIIAgAAAA==.',
Ry='Rydiaicefall:BAAANQAECgUIDgAAAA==.',
Sa='Sapkick:BAAANQAECgQIBAAAAA==.',
Se='Selina:BAAANQAECgQIBAAAAA==.Serdwarf:BAABNQAECn8tAAMRAAoKiRacVQAiAgARAAoKiRacVQAiAgAfAAkKRxHQHACsAQAAAA==.Sertian:BAAANQADCgQIBAAAAA==.',
Sh='Shaozehn:BAAANQAECgMIAwAAAA==.Shatha:BAAANQADCgQIBQAAAA==.Sherten:BAAANQAECgIIAgAAAA==.Shooturiout:BAAANQAECgMIAwAAAA==.Shtanky:BAABNQAECn8fAAIZAAoKZxKfFgDAAQAZAAoKZxKfFgDAAQAAAA==.',
Si='Sinpony:BAAANQABCgQIBAAAAA==.Sixsixsix:BAAANQADCggJCgABNQAECgoKLgANAM4gAA==.',
Sk='Sketch:BAAANQAECgIIAgABNQAFFAgIGQAeADEWAA==.Skoogz:BAABNQAECn8YAAQOAAoKNAzHUAD6AAAOAAcKDg7HUAD6AAAdAAMKHQlHiwCOAAANAAIKoQTRkgAnAAAAAA==.',
So='Soggyy:BAAANQAECgEIAQAAAA==.Sogsy:BAABNQAECn8UAAIDAAcKKwX4LgE+AQADAAcKKwX4LgE+AQAAAA==.Soleri:BAAANQAECgYICgAAAA==.Soulfulgingr:BAAANQAECgUIBwAAAA==.',
Sq='Squiblus:BAAANQADCgYIBgAAAA==.',
St='Styx:BAABNQAECn8eAAIbAAgKZAWdKwANAQAbAAgKZAWdKwANAQAAAA==.Stza:BAAANQABCgYICAAAAA==.',
Su='Sunbake:BAAANQAECgUIEQAAAA==.',
Sw='Sweetbbyraze:BAACNQAFFH8SAAMWAAcKSRDYBAB8AQAWAAUK/BbYBAB8AQAXAAIKPQbsCwCLAAA1AAQKfyoAAxYACgr8HrIIAOwCABYACgpaHrIIAOwCABcAAQpWG0IaAFIAAAAA.Swiftzz:BAABNQAECn8aAAMcAAgKXg2DMwBVAQAcAAcK5w2DMwBVAQAYAAcK+QaQSgD3AAAAAA==.',
Sz='Szayell:BAAANQADCgQIBAAAAA==.',
['Sí']='Sín:BAAANQADCgIJAgABNQAECgoKLgANAM4gAA==.',
Ta='Talipally:BAABNQAECn8eAAMQAAoKmwqK1AByAQAQAAoKmwqK1AByAQASAAEKQAPpcgAdAAAAAA==.Taliwhacker:BAAANQADCgMIAwABNQAECgoKHgAQAJsKAA==.Talonleafgrd:BAABNQAECn8gAAIbAAcKYRNZIQBiAQAbAAcKYRNZIQBiAQAAAA==.Tandsonna:BAAANQAECggIEAAAAA==.Tanisong:BAAANQAECgUICAAAAA==.',
Te='Terayus:BAAANQADCgIJAgAAAA==.Terraform:BAAANQADCgYICwAAAA==.',
Th='Thalor:BAABNQAECn8hAAMOAAoKGRxnFQBgAgAOAAoKGRxnFQBgAgAdAAMK0BZ5jgB9AAABNQAFFAYIDQAlAG8ZAA==.Thekingpunch:BAACNQAFFH8OAAIkAAYK3Q54BACAAQAkAAYK3Q54BACAAQA1AAQKf2MAAiQACgo0IsQFAEEDACQACgo0IsQFAEEDAAAA.Thenle:BAAANQAECgEIAQAAAA==.Theworst:BAAANQAECgYIBgABNQAECgoKLgANAM4gAA==.Thiel:BAAANQAECggIBwAAAA==.',
Ti='Tillwar:BAABNQAECn9OAAIMAAoKsBqbQgA6AgAMAAoKsBqbQgA6AgAAAA==.Timmu:BAAANQADCgEIAQAAAA==.Tiàna:BAAANQADCgEIAQAAAA==.',
To='Tofu:BAABNQAECn8bAAINAAoK1x2SLwBxAgANAAoK1x2SLwBxAgAAAA==.Tortillachip:BAAANQADCgYIBgAAAA==.Totemayhem:BAAANQADCgcIBwAAAA==.',
Tr='Treibh:BAABNQAECn9DAAIcAAoKthoJEgCoAgAcAAoKthoJEgCoAgAAAA==.Trulydps:BAABNQAECn8xAAIPAAoKCgvtmQDTAQAPAAoKCgvtmQDTAQAAAA==.',
Tu='Tust:BAAANQAECgQIBwABNQAECgUIDQALAAAAAA==.',
Ty='Tymora:BAAANQADCggICAABNQAECgoKSAAfAHEUAA==.',
['Të']='Tërris:BAABNQAECn8ZAAIOAAoKOhcbPAATAgAOAAoKOhcbPAATAgAAAA==.',
['Tî']='Tîlldeath:BAAANQAECgUICgAAAA==.',
Un='Undzl:BAACNQAFFH8LAAMdAAMKQhnSEwChAAAdAAMKQhnSEwChAAANAAEKcgYWJQA4AAA1AAQKf1MAAw0ACgqqJUwKAGoDAA0ACQqhIkwKAGoDAB0ACQoIJccLADkDAAAA.Unknowna:BAAANQADCgYIBgAAAA==.',
Ur='Urowndad:BAAANQADCgIIAgABNQAECgYIDwALAAAAAA==.Urownmother:BAAANQAECgEIAQABNQAECgYIDwALAAAAAA==.',
Va='Vaelira:BAAANQADCgMIAwAAAA==.Vallez:BAEBNQAECn8rAAMUAAoKBSV1DQBeAwAUAAoKBSV1DQBeAwAQAAEKAACargEwAAAAAA==.Varnusshadow:BAAANQAECgIIBAAAAA==.Vayn:BAABNQAECn8eAAIKAAgKBw5fPQBIAQAKAAgKBw5fPQBIAQAAAA==.',
Ve='Velladoree:BAAANQAECgIIAwAAAA==.Vexahlia:BAAANQAECggIDgAAAA==.',
Vg='Vgurlpally:BAAANQADCgIIAgAAAA==.',
['Vé']='Véñable:BAABNQAECn8eAAQBAAkK2A2oFQCAAQABAAkKvA2oFQCAAQAmAAMK2gQRFwB1AAAVAAEKAADcVgAnAAAAAA==.',
Wa='Waveygravee:BAAANQADCgcJCwAAAA==.Wavygraivy:BAABNQAECn8bAAIEAAYKtRLueQBFAQAEAAYKtRLueQBFAQAAAA==.',
We='Wedragon:BAAANQAECgUIBQAAAA==.',
Wi='Wildearth:BAAANQAECgQIAwAAAA==.',
Wo='Woofwoof:BAAANQAECgIIBAAAAA==.Wooshh:BAAANQAECgUIDQAAAA==.',
Xh='Xhexana:BAABNQAECn8hAAIEAAcK+BHcjQBmAQAEAAcK+BHcjQBmAQABNQAECgoKPgAPAKEPAA==.',
Xi='Xianofukuju:BAABNQAECn8rAAIYAAoKyhC+QwDlAQAYAAoKyhC+QwDlAQAAAA==.',
Xr='Xrayl:BAACNQAFFH8GAAMnAAQKXA6ABwCCAAAlAAMKNg5CEACLAAAnAAIKvw2ABwCCAAA1AAQKfzUAAycACgpzHAcLAF4CACcACgpqGgcLAF4CACUABgq+HL0sALQBAAAA.',
Xz='Xzerocool:BAAANQAECgYIDwAAAA==.',
Yo='Yoshikazu:BAAANQAECgIIAgAAAA==.',
Za='Zaarah:BAAANQADCgUIGQAAAA==.Zaniaz:BAAANQAECgMIAwABNQAECgoKNwANAAkbAA==.Zanthian:BAAANQABCgEIAQAAAA==.',
Ze='Zendezoth:BAABNQAECn8eAAIWAAoK+wzFCgC8AQAWAAoK+wzFCgC8AQAAAA==.Zevthekuatin:BAABNQAECn8oAAIPAAoKlw+jXQANAgAPAAoKlw+jXQANAgAAAA==.',
Zh='Zhiva:BAABNQAECn8nAAIYAAoK3wmxMQB8AQAYAAoK3wmxMQB8AQAAAA==.',
Zy='Zykoz:BAAANQAECgcIEQAAAA==.',
['Åy']='Åyna:BAAANQADCgcIEQAAAA==.',
['Ða']='Ðaddy:BAAANQAECgcIEQAAAA==.Ðamned:BAAANQAECgUICAABNQAECgoKLgANAM4gAA==.',
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
