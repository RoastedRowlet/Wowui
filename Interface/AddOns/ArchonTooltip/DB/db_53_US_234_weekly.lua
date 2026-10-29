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

local lookup = {'Rogue-Assassination','Mage-Frost','Mage-Arcane','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Warrior-Arms','DeathKnight-Unholy','DeathKnight-Blood','Hunter-BeastMastery','Paladin-Retribution','Priest-Holy','Paladin-Protection','DemonHunter-Devourer','Unknown-Unknown','Paladin-Holy','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','Warrior-Protection','Hunter-Survival','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','DeathKnight-Frost','Druid-Guardian','Priest-Shadow','DemonHunter-Vengeance','Evoker-Preservation','Druid-Feral','Monk-Mistweaver','Warrior-Fury','Shaman-Enhancement','Monk-Windwalker','Rogue-Outlaw','Monk-Brewmaster',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abel:BAEANQADCggICAABNQAECgkJHgABANgNAA==.',
Ae='Aeidail:BAACNQAFFH8WAAMCAAcK6hhwBQC7AAADAAUK3xe0GgCmAQACAAQKmhVwBQC7AAA1AAQKfzoAAwIACgpjJRoBAAUDAAIACgodJRoBAAUDAAMACQogIulUANYCAAAA.',
Ag='Agraceful:BAAANQAECgUIBgAAAA==.',
Ai='Aidton:BAAANQAECgEIAQAAAA==.Aiobhicefall:BAAANQAECgMIBwAAAA==.Aiobhicefell:BAAANQAECgUIDgAAAA==.Aiobicefall:BAAANQAECgcIEgAAAA==.Aioboicefall:BAAANQADCggIDAAAAA==.Aioicefall:BAAANQAECgQIBAAAAA==.Aiza:BAABNQAECn9GAAQEAAoKEhkNDgBzAQAFAAgKUBkKRQCXAQAEAAYKFxUNDgBzAQAGAAMKkguNSQCjAAAAAA==.',
Al='Albinoknight:BAAANQADCgEIAQAAAA==.Alessia:BAAANQADCgYICgAAAA==.Allarria:BAAANQADCggICAABNQAECggIKgAHAN8iAA==.',
An='Angrypants:BAABNQAECn8XAAIIAAgK8Ay3fgAXAQAIAAgK8Ay3fgAXAQAAAA==.Animalfriend:BAAANQAECgMIAwAAAA==.Anklesmasher:BAAANQAECgIIBwAAAA==.Antisocial:BAAANQADCggIEAABNQAECgoKLgAJAM4gAA==.',
Ar='Ardicon:BAAANQABCgEIAQAAAA==.Arfaz:BAABNQAECn8oAAMJAAoKvhYfDwArAgAJAAoKvhYfDwArAgAKAAEKcg7Y0wApAAAAAA==.Arthemis:BAAANQAECgQIBAAAAA==.Arthroy:BAAANQABCgIIAwAAAA==.Arçano:BAAANQADCgMIAwABNQAECgoKMgAIAFkWAA==.',
As='Asbestos:BAAANQAECgMIAwAAAA==.Astramoon:BAABNQAECn8UAAILAAUKggRczQCXAAALAAUKggRczQCXAAAAAA==.',
Ay='Aylå:BAAANQADCgYIBgAAAA==.',
Ba='Baerd:BAAANQADCgcICQAAAA==.Barlz:BAAANQADCgUIEwAAAA==.',
Be='Beasthunt:BAABNQAECn8eAAILAAgK8Rw3agA/AgALAAgK8Rw3agA/AgAAAA==.Beatmywillie:BAAANQAECgUIBQAAAA==.Bebby:BAAANQAECgQIDwAAAA==.Belienn:BAAANQADCggICAAAAA==.Belwolf:BAAANQADCgcIFAAAAA==.Bennehona:BAAANQADCgEIAQAAAA==.Bergstrom:BAABNQAECn8rAAIMAAgKJQ3NtQCzAQAMAAgKJQ3NtQCzAQAAAA==.Betrayer:BAAANQAECgIIAwABNQAECgoKPwAFAHojAA==.',
Bi='Biancafiamma:BAAANQAECgIIAgAAAA==.Biancaneve:BAABNQAECn8jAAINAAoKzRVUJwAyAgANAAoKzRVUJwAyAgAAAA==.',
Bo='Bombacløt:BAABNQAECn8kAAMGAAgKyREfEwDaAQAGAAcKDBMfEwDaAQAFAAYK2wygcQAYAQAAAA==.',
Br='Brastin:BAABNQAECn8eAAIOAAcKNxfNJQCxAQAOAAcKNxfNJQCxAQAAAA==.Brenell:BAABNQAECn8jAAIDAAoKQBHQtQAYAgADAAoKQBHQtQAYAgAAAA==.Brixscen:BAAANQAECggIEgAAAA==.',
Bu='Bubblehearth:BAAANQAECgEIAQABNQAFFAUIEAAPAHQLAA==.Buhliz:BAAANQAECgMIAwAAAA==.',
Ca='Cabëla:BAAANQAECgUICQABNQAECgYIEAAQAAAAAA==.Caineicefall:BAAANQAECgQIBAAAAA==.Calacolinda:BAABNQAECn8iAAMRAAcKaAURwAD8AAARAAcKaAURwAD8AAAMAAYKIAjWMgHOAAAAAA==.',
Ce='Celestiall:BAAANQAECgUIDQAAAA==.Ceridwyn:BAAANQADCgcIEgAAAA==.',
Ch='Chadalonius:BAAANQADCgQIBAABNQAFFAYIEQASAKkVAA==.Cheesecurd:BAAANQAECgIIAgAAAA==.Choal:BAAANQADCgYICwAAAA==.Chriswin:BAAANQAECgMIAwAAAA==.',
Cl='Claytonbigsb:BAAANQADCgYIBgABNQAECgYIDwAQAAAAAA==.',
Co='Corahin:BAAANQAECgQIBAAAAA==.',
Cu='Cuecumba:BAAANQAECgYIDwAAAA==.',
Cy='Cynndi:BAAANQABCgYIBgAAAA==.',
Da='Dalren:BAACNQAFFH8TAAITAAYKSBYrAwDGAQATAAYKSBYrAwDGAQA1AAQKf0UAAxMACgpQIYMEAFMDABMACgqXH4MEAFMDABQABQpwHU4JAAEBAAAA.Dalvix:BAAANQAECgIIAwABNQAECggIKgAHAN8iAA==.Dammedude:BAAANQABCgMIAwAAAA==.Darksun:BAAANQABCgEIAQAAAA==.Dartagnan:BAABNQAECn8fAAILAAoKYhNSfwAOAgALAAoKYhNSfwAOAgAAAA==.Darthmaul:BAABNQAECn83AAIVAAoKBg+RGwCxAQAVAAoKBg+RGwCxAQAAAA==.Daveykrook:BAAANQAECggIBgABNQAECggIIQAFACEWAA==.David:BAABNQAECn8YAAIMAAoKvQmF1QBwAQAMAAoKvQmF1QBwAQAAAA==.',
De='Dendiian:BAAANQADCgYICQAAAA==.Depletor:BAABNQAECn8oAAMIAAoK2gmNugCKAQAIAAoK2gmNugCKAQAWAAMKCASbPABTAAAAAA==.Devils:BAAANQADCgEIAQAAAA==.',
Di='Diem:BAAANQAECgYICgAAAA==.Dirtydotss:BAAANQAECgQICQAAAA==.',
Do='Docholiday:BAABNQAECn8aAAQXAAcKcROQCADFAQAXAAYK+xWQCADFAQAYAAUKGgewNgB5AAALAAIKmQHcPQFoAAAAAA==.Docsassist:BAAANQAECgYICwAAAA==.Dowedoes:BAABNQAECn8+AAIMAAoKbwzQYgCTAQAMAAoKbwzQYgCTAQAAAA==.',
Dr='Drachula:BAABNQAECn8WAAMZAAYK+RBLmwBCAQAZAAYK+RBLmwBCAQAaAAEKPAhRxAA1AAAAAA==.Dracultra:BAAANQADCgYIBgABNQAECgoKIAARAAEXAA==.Draeun:BAAANQAECgEIAQABNQAFFAYIEwATAEgWAA==.Dreolan:BAABNQAECn8dAAIbAAkKBBGPGACsAQAbAAkKBBGPGACsAQAAAA==.Druaga:BAAANQAECggIDgAAAA==.Dràchula:BAAANQADCgYICQAAAA==.Dràúgr:BAAANQADCgMIAwAAAA==.',
Dy='Dyala:BAABNQAECn8kAAIbAAoKwBwXGAB/AgAbAAoKwBwXGAB/AgAAAA==.',
Dz='Dzznuts:BAAANQABCgYICgAAAA==.',
['Dé']='Démonléth:BAAANQAECgIIAgABNQAECgkJJgAcAEQZAA==.',
['Dö']='Dönövan:BAABNQAECn8kAAIMAAgKqQsF0QB5AQAMAAgKqQsF0QB5AQAAAA==.',
Eg='Eggyolk:BAABNQAECn8dAAIdAAoKpBdAFAAhAgAdAAoKpBdAFAAhAgAAAA==.',
El='Elastwo:BAAANQADCggIGQAAAA==.Eloise:BAAANQAECgEIAQAAAA==.Elvenbane:BAABNQAECn8+AAMeAAoK9hNhDgDwAQAeAAoK9hNhDgDwAQANAAgKWgOPoAAzAQAAAA==.',
Es='Espeon:BAAANQAECgUIBQABNQAECggIEQAQAAAAAA==.',
Eu='Eunliza:BAAANQAECggICAAAAA==.',
Ew='Ew:BAACNQAFFH8QAAMLAAYK6BWNBQD7AQALAAYK6BWNBQD7AQAYAAEKyAdXJQBAAAA1AAQKfzwAAwsACgp7Ia8WAEADAAsACgp7Ia8WAEADABgABwpHGfM1AJ4BAAE1AAQKCgouAAkAziAA.',
Ex='Extrathick:BAAANQAECgEIAQAAAA==.',
Fa='Fathershale:BAAANQADCgYIFAAAAA==.',
Fe='Fedupdk:BAAANQADCgYIDQAAAA==.Feet:BAAANQAECgcICwAAAA==.Felidae:BAEANQAECgQIBAAAAA==.',
Fi='Firedancer:BAAANQAECgQICAAAAA==.Fizzfiend:BAAANQADCggIDQAAAA==.',
Fo='Foulcor:BAAANQAECgIIAwABNQAECggIHgALAPEcAA==.',
Fr='Freakadeek:BAAANQAECgMIBgABNQAECgcIGgAXAHETAA==.Freâkadeek:BAAANQADCgQIBAABNQAECgcIGgAXAHETAA==.Frieren:BAABNQAECn8nAAICAAkKYxQxCgAoAgACAAkKYxQxCgAoAgAAAA==.Frëak:BAAANQADCgUIBgABNQAECgcIGgAXAHETAA==.',
Ga='Gabbyo:BAABNQAECn8hAAIbAAcKqwnUKAAYAQAbAAcKqwnUKAAYAQAAAA==.Galadorn:BAABNQAECn8qAAMHAAgK3yLbEQAQAwAHAAgKXiLbEQAQAwAfAAUKriBGEACuAQAAAA==.',
Ge='Genasis:BAAANQABCgMIBQAAAA==.Gerdash:BAAANQAECgYIEwAAAA==.Gerred:BAABNQAECn82AAIIAAkKpiHAKwAuAgAIAAkKpiHAKwAuAgAAAA==.',
Gh='Ghallow:BAAANQAECgcIDwAAAA==.Ghosthowl:BAAANQAECgUIDAAAAA==.',
Gl='Gladur:BAAANQAECgIIAgABNQAFFAcIFgACAOoYAA==.',
Go='Goldenflame:BAAANQAECgUICgAAAA==.Goldenlight:BAABNQAECn8sAAINAAkK5BJmVgAgAgANAAkK5BJmVgAgAgAAAA==.Goldenmunc:BAAANQADCgIIAgAAAA==.Goldenone:BAABNQAECn8UAAIRAAYKMxxhMQDdAQARAAYKMxxhMQDdAQAAAA==.Goldenpants:BAAANQADCggIDwAAAA==.',
Gr='Grandesaxx:BAAANQAECgQICAAAAA==.Grievous:BAABNQAECn8+AAIfAAoKkSWhAABIAwAfAAoKkSWhAABIAwAAAA==.',
Ha='Hailmary:BAAANQAECgYIEAAAAA==.Hakudoshi:BAAANQAECgQICQAAAA==.Harmanee:BAAANQADCgYIBgAAAA==.Hauser:BAABNQAECn8mAAIMAAoKHhv+YwBvAgAMAAoKHhv+YwBvAgAAAA==.',
He='Healaga:BAAANQAECgUIBwABNQAECgoKKAAJAL4WAA==.Heinrich:BAAANQADCgMIAwAAAA==.',
Hh='Hhoonnzz:BAAANQADCgYIBgABNQAECgoKLgAJAM4gAA==.',
Ho='Hornreaper:BAABNQAECn8hAAQgAAoKBhDULABAAQAgAAcKoQnULABAAQAUAAgKPgySEAAvAQATAAIKywRvHQA1AAAAAA==.',
Hu='Hubbabubbajr:BAABNQAECn8YAAINAAcKzh2RMgDzAQANAAcKzh2RMgDzAQAAAA==.',
Il='Ilavengu:BAABNQAECn8cAAIHAAkKnSB9DACGAgAHAAkKnSB9DACGAgABNQAFFAUIEAAeADMgAA==.',
Is='Isochu:BAAANQADCgMJAwAAAA==.',
Ja='Jayonor:BAABNQAECn87AAMaAAoKohrKGQAuAgAaAAoKohrKGQAuAgAZAAEKwQCVOAEWAAAAAA==.',
Je='Jek:BAAANQAECgEIAQAAAA==.',
Jo='Jonohae:BAAANQAECgIIAQABNQAECgoKMgAIAFkWAA==.',
Ju='Judgethis:BAAANQABCgIIAgAAAA==.Juicycucci:BAAANQAECgYICQABNQAFFAUIEAAPAHQLAA==.',
Ka='Kaevrielle:BAEBNQAECn8aAAMfAAoKmhmCDAD+AQAfAAoKmhmCDAD+AQAHAAIK/Q9wZQA8AAAAAA==.Kaidrosa:BAAANQAECgIIAgAAAA==.Kainicefall:BAABNQAECn8eAAMhAAoKWA1/DQBVAQAhAAgKEQx/DQBVAQAVAAgKNglnOQDiAAAAAA==.Kainicefell:BAAANQAECgIIAgAAAA==.Kainoficefal:BAAANQAECgcIEAAAAA==.Kaladîn:BAAANQAECgEIAQABNQAFFAcIFgACAOoYAA==.Kalokako:BAAANQADCgEIAQAAAA==.Kamel:BAAANQABCgQIBQAAAA==.Karwin:BAAANQAECggICwAAAA==.',
Ke='Keeper:BAABNQAECn8ZAAIBAAoKoRPVDgCVAQABAAoKoRPVDgCVAQABNQAFFAMICgAMAJciAA==.Keeperodark:BAABNQAECn8jAAIFAAoKEhGGZwAkAgAFAAoKEhGGZwAkAgABNQAFFAMICgAMAJciAA==.Keeperolight:BAACNQAFFH8KAAIMAAMKlyJKDwDLAAAMAAMKlyJKDwDLAAA1AAQKf0UAAgwACgoBJkgFAM8DAAwACgoBJkgFAM8DAAAA.',
Ki='Kifo:BAAANQAECgQIBgAAAA==.Killkat:BAAANQAECgYIEAAAAA==.Kirkulus:BAAANQAECggICAAAAA==.',
Ko='Koojo:BAABNQAECn8XAAIhAAcKtBapDQBTAQAhAAcKtBapDQBTAQAAAA==.',
La='Lans:BAAANQAECgIIAgAAAA==.Larew:BAAANQAECgUICAAAAA==.',
Le='Lealla:BAABNQAECn89AAIVAAoKhRs0EQA1AgAVAAoKhRs0EQA1AgAAAA==.Leodin:BAAANQADCgYIBgAAAA==.Lethhunt:BAAANQAECgEIAQABNQAECgkJJgAcAEQZAA==.Letholas:BAABNQAECn8mAAQcAAkKRBl0NQAEAgAcAAgKHxl0NQAEAgAJAAcKwxNfXgCWAQAKAAEKAADo0wApAAAAAA==.',
Li='Lightmàiden:BAAANQADCgEIAQAAAA==.Lilkingpunch:BAAANQADCgYIBgABNQAFFAUIDAAiAOAOAA==.Lizardgang:BAAANQAECgYIDwAAAA==.',
Lo='Loganshu:BAAANQADCgYIBgAAAA==.Lokan:BAABNQAECn8nAAMLAAoKAx4sPgDpAQALAAoKAx4sPgDpAQAXAAYKaA1qDAASAQAAAA==.Lots:BAABNQAECn8wAAMFAAoKayLrOwCfAgAFAAgK/SLrOwCfAgAGAAIKtCCyEgCEAAAAAA==.',
Lu='Ludakris:BAAANQAECgYIEAAAAA==.',
['Lí']='Líonheart:BAAANQAECgcIEAAAAA==.',
Ma='Maami:BAAANQAECgYICwAAAA==.Machognome:BAAANQADCgQIBAAAAA==.Mahina:BAAANQAECgUIEgAAAA==.Makrabro:BAAANQABCgIIAgAAAA==.Marcille:BAAANQAECgcIDgAAAA==.Mattix:BAAANQADCggICAAAAA==.Matíx:BAABNQAECn8hAAMFAAgKIRZRSACMAQAFAAgKIRZRSACMAQAGAAIKVA49XABtAAAAAA==.Mayhaps:BAABNQAECn8zAAMLAAoKHA5aaQBBAgALAAoKHA5aaQBBAgAYAAEKAABdoQAWAAAAAA==.Mayoke:BAAANQAECgEIAgAAAA==.',
Me='Mentaltitty:BAABNQAECn8aAAIDAAcKXRM44QDGAQADAAcKXRM44QDGAQAAAA==.',
Mi='Milhouse:BAABNQAECn8+AAIKAAoKeCPFBgDrAgAKAAoKeCPFBgDrAgAAAA==.Minerwor:BAAANQAECgQIBgAAAA==.Mirrayla:BAAANQADCgEIAQAAAA==.Misty:BAAANQAECgUIBgAAAA==.',
Mm='Mmisty:BAABNQAECn8oAAIVAAoKpBM0GgC+AQAVAAoKpBM0GgC+AQAAAA==.',
Mo='Momometaru:BAABNQAECn8mAAQGAAoKeRBQMgD8AAAFAAoKUA4JhQDZAQAGAAQK8BFQMgD8AAAEAAMKnwo4GgC0AAABNQAECgoKKwAVAMoQAA==.Monsterbee:BAABNQAECn88AAIFAAoKrxY6JgAdAgAFAAoKrxY6JgAdAgAAAA==.Morne:BAAANQADCggIDgAAAA==.',
Mu='Mustypizza:BAAANQAECgYIEAAAAA==.',
My='Mystery:BAABNQAECn8+AAMgAAoKzRtuCAA+AgAgAAoKzRtuCAA+AgATAAEKAAB7IgAAAAAAAA==.',
Na='Nailme:BAAANQAECgYIBgAAAA==.Nats:BAABNQAECn8aAAIZAAgK7RNAUwAaAgAZAAgK7RNAUwAaAgAAAA==.',
Ne='Neameny:BAABNQAECn8+AAILAAoKoQ/ZNgAEAgALAAoKoQ/ZNgAEAgAAAA==.',
Ni='Nightstar:BAAANQADCgYIBgAAAA==.',
Nu='Nualrossan:BAAANQADCgEIAgAAAA==.Nubrac:BAABNQAECn8bAAMbAAoKjRyiCwB+AgAbAAoKjRyiCwB+AgAVAAEKAAAkggAAAAAAAA==.',
Ob='Oblivion:BAABNQAECn8/AAMFAAoKeiNtBwD+AgAFAAoKeiNtBwD+AgAGAAIK0BQiVgB8AAAAAA==.',
Om='Omey:BAAANQAECgUIDgAAAA==.',
On='Onepercent:BAAANQAECggICAAAAA==.',
Pa='Pallyshore:BAAANQADCggICAAAAA==.Papichuló:BAAANQADCgMIBgABNQAECgcIGgAXAHETAA==.',
Pi='Pixae:BAAANQAFFAEIAQAAAA==.',
Po='Portknight:BAAANQAECgEIAQAAAA==.Potatochip:BAAANQAECgIIAgAAAA==.Powerplant:BAACNQAFFH8RAAILAAYKUB8iBABlAQALAAYKUB8iBABlAQA1AAQKfzcAAgsACgpaIjQMAO8CAAsACgpaIjQMAO8CAAAA.',
Py='Pyralys:BAABNQAECn87AAINAAoKvg8UMQD6AQANAAoKvg8UMQD6AQAAAA==.',
['Pâ']='Pârtyrockêr:BAAANQAECgYIBwABNQAECgcIGgAXAHETAA==.',
['Pä']='Pärts:BAAANQADCgQIBAABNQAECggIEQAQAAAAAA==.',
Ra='Raelene:BAAANQADCgYICQAAAA==.Ragedk:BAAANQAECgIIAwABNQAECgcIBwAQAAAAAA==.Ragenbefcake:BAAANQAECgQIBAAAAA==.Ragetality:BAAANQAECgcIBwAAAA==.Rallaster:BAAANQAECgUIDQABNQAECgoKPgAeAPYTAA==.Rampage:BAAANQABCgUIAgAAAA==.Raserei:BAABNQAECn8kAAMjAAoKYxydBwB6AgAjAAgKxx2dBwB6AgAIAAUK1RhYhQAHAQAAAA==.Rattelyr:BAAANQADCgQIBAAAAA==.Rawb:BAAANQAECgYJCgABNQAECgoKLgAJAM4gAA==.',
Re='Recolada:BAAANQADCgcJDAAAAA==.Regicee:BAABNQAECn8VAAMJAAgKchOUVQC7AQAJAAcK7BWUVQC7AQAKAAEKDweWggAzAAAAAA==.',
Ro='Rockdyou:BAABNQAECn8WAAMJAAoKRxLRJABQAQAJAAgKyxPRJABQAQAcAAUK+Qj4RgD7AAAAAA==.Roflstomper:BAAANQADCgEIAQAAAA==.Rotlobster:BAABNQAECn8fAAIEAAkKhyJAAQBUAwAEAAkKhyJAAQBUAwABNQAECgoKMwAkAKEdAA==.Rottenrigger:BAAANQABCgQIBAAAAA==.',
Ru='Rudal:BAAANQADCgIIAgAAAA==.Rundvelt:BAAANQADCgIIAgAAAA==.',
Ry='Rydiaicefall:BAAANQAECgQICQAAAA==.',
Sa='Sapkick:BAAANQAECgQIBAAAAA==.',
Se='Selina:BAAANQAECgQIBAAAAA==.Serdwarf:BAABNQAECn8fAAMNAAgKuhqcVQAiAgANAAcK3RqcVQAiAgAeAAcKeREMGwA2AQAAAA==.Sertian:BAAANQADCgQIBAAAAA==.',
Sh='Shatha:BAAANQADCgQIBQAAAA==.Sherten:BAAANQAECgIIAgAAAA==.Shooturiout:BAAANQAECgMIAwAAAA==.Shtanky:BAABNQAECn8fAAIWAAoKZxKfFgDAAQAWAAoKZxKfFgDAAQAAAA==.',
Si='Sinpony:BAAANQABCgQIBAAAAA==.Sixsixsix:BAAANQADCggJCgABNQAECgoKLgAJAM4gAA==.',
Sk='Sketch:BAAANQAECgIIAgABNQAFFAcIGAAdAFAXAA==.Skoogz:BAAANQAECgUICgAAAA==.',
So='Soggyy:BAAANQAECgEIAQAAAA==.Sogsy:BAABNQAECn8UAAIDAAcKKwX4LgE+AQADAAcKKwX4LgE+AQAAAA==.Soleri:BAAANQAECgQIBAAAAA==.Soulfulgingr:BAAANQAECgUIBwAAAA==.',
St='Styx:BAAANQAECgUIDgAAAA==.Stza:BAAANQABCgYICAAAAA==.',
Su='Sunbake:BAAANQAECgQIDQAAAA==.',
Sw='Sweetbbyraze:BAACNQAFFH8RAAMTAAYKyBPYBAB8AQATAAUK/BbYBAB8AQAUAAEKLQoKCQBMAAA1AAQKfyYAAhMACgpaHrIIAOwCABMACgpaHrIIAOwCAAAA.Swiftzz:BAAANQADCgcIDgAAAA==.',
['Sí']='Sín:BAAANQADCgIJAgABNQAECgoKLgAJAM4gAA==.',
Ta='Talipally:BAABNQAECn8eAAMMAAoKmwqK1AByAQAMAAoKmwqK1AByAQAOAAEKQAOmVQAfAAAAAA==.Taliwhacker:BAAANQADCgMIAwABNQAECgoKHgAMAJsKAA==.Talonleafgrd:BAABNQAECn8aAAIYAAYKWRTdHAAYAQAYAAYKWRTdHAAYAQAAAA==.Tandsonna:BAAANQAECggIEAAAAA==.Tanisong:BAAANQAECgQIBwAAAA==.',
Te='Terayus:BAAANQADCgIJAgAAAA==.Terraform:BAAANQADCgYICwAAAA==.',
Th='Thalor:BAABNQAECn8bAAMKAAkK0xvbDAB5AgAKAAkK0xvbDAB5AgAcAAMK0BZ5jgB9AAABNQAFFAYIDQAlAG8ZAA==.Thekingpunch:BAACNQAFFH8MAAIiAAUK4A45AwBFAQAiAAUK4A45AwBFAQA1AAQKf1kAAiIACgo0IsQFAEEDACIACgo0IsQFAEEDAAAA.Thenle:BAAANQAECgEIAQAAAA==.Theworst:BAAANQAECgYIBgABNQAECgoKLgAJAM4gAA==.',
Ti='Tillwar:BAABNQAECn9AAAIIAAoKGxouLAAsAgAIAAoKGxouLAAsAgAAAA==.Timmu:BAAANQADCgEIAQAAAA==.Tiàna:BAAANQADCgEIAQAAAA==.',
To='Tofu:BAABNQAECn8bAAIJAAoK1x2SLwBxAgAJAAoK1x2SLwBxAgAAAA==.Tortillachip:BAAANQADCgYIBgAAAA==.Totemayhem:BAAANQADCgcIBwAAAA==.',
Tr='Treibh:BAABNQAECn85AAIbAAoKBhqECgCVAgAbAAoKBhqECgCVAgAAAA==.Trulydps:BAABNQAECn8gAAILAAgKZwvtmQDTAQALAAgKZwvtmQDTAQAAAA==.',
Tu='Tust:BAAANQAECgQIBwABNQAECgQIBQAQAAAAAA==.',
Ty='Tymora:BAAANQADCggICAABNQAECgoKPgAeAPYTAA==.',
['Të']='Tërris:BAABNQAECn8XAAIKAAkKdhgbPAATAgAKAAkKdhgbPAATAgAAAA==.',
['Tî']='Tîlldeath:BAAANQAECgUICgAAAA==.',
Un='Undzl:BAACNQAFFH8JAAMcAAIKox/SEwChAAAcAAIKox/SEwChAAAJAAEKcgYWJQA4AAA1AAQKf0YAAwkACgpHJUwKAGoDAAkACQqhIkwKAGoDABwACQp7JMcLADkDAAAA.Unknowna:BAAANQADCgYIBgAAAA==.',
Ur='Urowndad:BAAANQADCgIIAgABNQAECgYIDwAQAAAAAA==.',
Va='Vallez:BAEBNQAECn8oAAMRAAoKBSV1DQBeAwARAAoKBSV1DQBeAwAMAAEKAACargEwAAAAAA==.Varnusshadow:BAAANQAECgIIBAAAAA==.Vayn:BAAANQAECgUIDgAAAA==.',
Ve='Velladoree:BAAANQAECgIIAwAAAA==.Vexahlia:BAAANQAECggIDgAAAA==.',
Vg='Vgurlpally:BAAANQADCgIIAgAAAA==.',
['Vé']='Véñable:BAABNQAECn8eAAQBAAkK2A2qDQClAQABAAkKvA2qDQClAQAmAAMK2gQRFwB1AAASAAEKAADcVgAnAAAAAA==.',
Wa='Waveygravee:BAAANQADCgcJCwAAAA==.Wavygraivy:BAAANQAECgQIEwAAAA==.',
We='Wedragon:BAAANQAECgQIBQAAAA==.',
Wi='Wildearth:BAAANQAECgEIAQAAAA==.',
Wo='Woofwoof:BAAANQAECgIIBAAAAA==.Wooshh:BAAANQAECgUIDQAAAA==.',
Xh='Xhexana:BAABNQAECn8hAAIZAAcK+BG+UwBJAQAZAAcK+BG+UwBJAQABNQAECgoKPgALAKEPAA==.',
Xi='Xianofukuju:BAABNQAECn8rAAIVAAoKyhC+QwDlAQAVAAoKyhC+QwDlAQAAAA==.',
Xr='Xrayl:BAABNQAECn8yAAMnAAoKcRwHCwBeAgAnAAoKyhkHCwBeAgAlAAYKvhy9LAC0AQAAAA==.',
Xz='Xzerocool:BAAANQAECgYIDwAAAA==.',
Yo='Yoshikazu:BAAANQAECgIIAgAAAA==.',
Za='Zaarah:BAAANQADCgUIGQAAAA==.Zanthian:BAAANQABCgEIAQAAAA==.',
Ze='Zendezoth:BAAANQAECggIEgAAAA==.Zevthekuatin:BAABNQAECn8eAAILAAgKsQ1ZXwCAAQALAAgKsQ1ZXwCAAQAAAA==.',
Zh='Zhiva:BAABNQAECn8dAAIVAAcKrgl9NQD2AAAVAAcKrgl9NQD2AAAAAA==.',
Zy='Zykoz:BAAANQAECgYIEAAAAA==.',
['Åy']='Åyna:BAAANQADCgcIEQAAAA==.',
['Ða']='Ðaddy:BAAANQAECgcIEQAAAA==.Ðamned:BAAANQAECgUICAABNQAECgoKLgAJAM4gAA==.',
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
