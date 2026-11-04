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

local lookup = {'Rogue-Assassination','Mage-Frost','Mage-Arcane','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Unknown-Unknown','Warrior-Arms','DeathKnight-Unholy','DeathKnight-Blood','Hunter-BeastMastery','Paladin-Retribution','Priest-Holy','Paladin-Protection','DemonHunter-Devourer','Paladin-Holy','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','Warrior-Protection','Hunter-Survival','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','DeathKnight-Frost','Druid-Guardian','Priest-Shadow','DemonHunter-Vengeance','Shaman-Enhancement','Evoker-Preservation','Druid-Feral','Warrior-Fury','Monk-Mistweaver','Monk-Windwalker','Rogue-Outlaw','Monk-Brewmaster',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abel:BAEANQADCggICAABNQAECgkJHgABANgNAA==.',
Ae='Aeidail:BAACNQAFFH8WAAMCAAcK6hhwBQC7AAADAAUK3xe0GgCmAQACAAQKmhVwBQC7AAA1AAQKf0QAAwIACgoYJkYAAH8DAAIACgoQJkYAAH8DAAMACQogIulUANYCAAAA.',
Ag='Agraceful:BAAANQAECgUIBgAAAA==.',
Ai='Aidton:BAAANQAECgEIAQAAAA==.Aiobhicefall:BAAANQAECgcIDAAAAA==.Aiobhicefell:BAAANQAECgUIDgAAAA==.Aiobicefall:BAAANQAECgcIEgAAAA==.Aioboicefall:BAAANQADCggIDAAAAA==.Aioicefall:BAAANQAECgQIBAAAAA==.Aiza:BAABNQAECn9KAAQEAAoKLhkNDgBzAQAFAAgKdRmCZAAsAgAEAAYKFxUNDgBzAQAGAAMKkguNSQCjAAAAAA==.',
Al='Albinoknight:BAAANQADCgEIAQAAAA==.Alessia:BAAANQADCgYICgAAAA==.Allarria:BAAANQADCggICAABNQAECgkJLAAHAL0hAA==.Altic:BAAANQAECgMIAwABNQAECggIBgAIAAAAAA==.',
An='Angrypants:BAABNQAECn8YAAIJAAgK8AxhmgAUAQAJAAgK8AxhmgAUAQAAAA==.Animalfriend:BAAANQAECgMIAwAAAA==.Anklesmasher:BAAANQAECgUIDAAAAA==.Antisocial:BAAANQADCggIEAABNQAECgoKLgAKAM4gAA==.',
Ar='Archfury:BAAANQABCgYIBwAAAA==.Ardicon:BAAANQABCgEIAQAAAA==.Arfaz:BAABNQAECn8uAAMKAAoK2hg2EwAxAgAKAAoK2hg2EwAxAgALAAEKcg7Y0wApAAAAAA==.Arthemis:BAAANQAECgQIBAAAAA==.Arthroy:BAAANQABCgIIAwAAAA==.Arçano:BAAANQADCgMIAwABNQAECgoKPQAJAKoXAA==.',
As='Asbestos:BAAANQAECgMIAwAAAA==.Astramoon:BAABNQAECn8VAAIMAAUKggTY7gCTAAAMAAUKggTY7gCTAAAAAA==.',
Ay='Aylå:BAAANQADCgYIBgAAAA==.',
Ba='Baerd:BAAANQADCgcICQAAAA==.Barlz:BAAANQADCgUIEwAAAA==.',
Be='Beasthunt:BAABNQAECn8hAAIMAAkKxRyAOgAvAgAMAAkKxRyAOgAvAgAAAA==.Beatmywillie:BAAANQAECgUIBQAAAA==.Bebby:BAAANQAECgUIEwAAAA==.Belienn:BAAANQADCggICAAAAA==.Belwolf:BAAANQADCggIHQAAAA==.Bennehona:BAAANQADCgEIAQAAAA==.Bergstrom:BAABNQAECn8rAAINAAgKJQ3NtQCzAQANAAgKJQ3NtQCzAQAAAA==.Betrayer:BAAANQAECgQIAwABNQAECgoKSQAFAIgkAA==.',
Bi='Biancafiamma:BAAANQAECgIIAgAAAA==.Biancaneve:BAABNQAECn8jAAIOAAoKzRV3OQAfAgAOAAoKzRV3OQAfAgAAAA==.',
Bo='Bombacløt:BAABNQAECn8pAAMGAAkKjBEfEwDaAQAGAAcKDBMfEwDaAQAFAAcK/A38bABXAQAAAA==.',
Br='Brastin:BAABNQAECn8kAAIPAAgK/xcCGwBjAQAPAAgK/xcCGwBjAQAAAA==.Brenell:BAABNQAECn8jAAIDAAoKQBHQtQAYAgADAAoKQBHQtQAYAgAAAA==.Brixscen:BAABNQAECn8cAAIFAAoKHQ7ZUQCmAQAFAAoKHQ7ZUQCmAQAAAA==.',
Bu='Bubblehearth:BAAANQAECgEIAQABNQAFFAUIEAAQAHQLAA==.Buhliz:BAAANQAECgMIAwAAAA==.',
Ca='Cabëla:BAAANQAECgYIDAABNQAECggIEQAIAAAAAA==.Caineicefall:BAAANQAECgUIBwAAAA==.Calacolinda:BAABNQAECn8iAAMRAAcKaAURwAD8AAARAAcKaAURwAD8AAANAAYKIAjWMgHOAAAAAA==.',
Ce='Celestiall:BAAANQAECggIEAAAAA==.Ceridwyn:BAAANQADCggIGgAAAA==.',
Ch='Chadalonius:BAAANQADCgQIBAABNQAFFAYIFgASAF0XAA==.Cheesecurd:BAAANQAECgIIAgAAAA==.Choal:BAAANQADCgYICwAAAA==.Chriswin:BAAANQAECgMIAwAAAA==.',
Cl='Claytonbigsb:BAAANQADCgYIBgABNQAECgYIDwAIAAAAAA==.',
Co='Corahin:BAAANQAECgUIBgAAAA==.',
Cu='Cuecumba:BAAANQAECgcIEAAAAA==.',
Cy='Cynndi:BAAANQABCgYIBgAAAA==.',
Da='Dalren:BAACNQAFFH8UAAITAAcKQxdhAQAuAQATAAcKQxdhAQAuAQA1AAQKf0oAAxMACgqfIYMEAFMDABMACgqJIYMEAFMDABQABQpwHWEMAPcAAAAA.Dalvix:BAAANQAECgYICQABNQAECgkJLAAHAL0hAA==.Dammedude:BAAANQABCgMIAwAAAA==.Darksun:BAAANQABCgEIAQAAAA==.Dartagnan:BAABNQAECn8iAAIMAAoK6BRSfwAOAgAMAAoK6BRSfwAOAgAAAA==.Darthmaul:BAABNQAECn9BAAIVAAoKdg9YIgC0AQAVAAoKdg9YIgC0AQAAAA==.David:BAABNQAECn8ZAAINAAoKxgmF1QBwAQANAAoKxgmF1QBwAQAAAA==.',
De='Dendiian:BAAANQADCgYICQAAAA==.Depletor:BAABNQAECn8rAAMJAAoKGgqNugCKAQAJAAoKGgqNugCKAQAWAAMKCASbPABTAAAAAA==.Devils:BAAANQADCgEIAQAAAA==.',
Di='Diem:BAAANQAECgYICgAAAA==.Dinendal:BAAANQADCgEIAQAAAA==.Dirtydotss:BAAANQAECgQICQAAAA==.',
Do='Docholiday:BAABNQAECn8aAAQXAAcKcROQCADFAQAXAAYK+xWQCADFAQAYAAUKGgeaPwB2AAAMAAIKmQHcPQFoAAAAAA==.Docsassist:BAAANQAECgcIDAAAAA==.Dowedoes:BAABNQAECn9IAAINAAoK9QxMewCXAQANAAoK9QxMewCXAQAAAA==.',
Dr='Drachula:BAABNQAECn8YAAMZAAYKLRJLmwBCAQAZAAYKLRJLmwBCAQAaAAEKPAgG4gA1AAAAAA==.Dracultra:BAAANQADCgYIBgABNQAECgoKIAARAAEXAA==.Draeun:BAAANQAECgEIAQABNQAFFAcIFAATAEMXAA==.Dreolan:BAABNQAECn8iAAIbAAkKJxFGIACpAQAbAAkKJxFGIACpAQAAAA==.Druaga:BAAANQAECggIDgAAAA==.Dràchula:BAAANQADCgYICQAAAA==.Dràúgr:BAAANQADCgMIAwAAAA==.',
Dy='Dyala:BAABNQAECn8nAAIbAAoKYB0XGAB/AgAbAAoKYB0XGAB/AgAAAA==.',
Dz='Dzznuts:BAAANQABCgYICgAAAA==.',
['Dé']='Démonléth:BAAANQAECgIIAgABNQAECgkJJgAcAEQZAA==.',
['Dö']='Dönövan:BAABNQAECn8pAAINAAkK2wsWrwAxAQANAAkK2wsWrwAxAQAAAA==.',
Eg='Eggyolk:BAABNQAECn8dAAIdAAoKpBdAFAAhAgAdAAoKpBdAFAAhAgAAAA==.',
El='Elastwo:BAAANQADCggIGQAAAA==.Eloise:BAAANQAECgUIBgAAAA==.Elvenbane:BAABNQAECn9IAAMeAAoKcRQyEgAAAgAeAAoKcRQyEgAAAgAOAAgKWgOPoAAzAQAAAA==.',
Es='Espeon:BAAANQAECgUIBQABNQAECgkJFQARAKoTAA==.',
Et='Ethereal:BAAANQAECgUIBQAAAA==.',
Eu='Eunliza:BAAANQAECggICAAAAA==.',
Ew='Ew:BAACNQAFFH8QAAMMAAYK6BWNBQD7AQAMAAYK6BWNBQD7AQAYAAEKyAdXJQBAAAA1AAQKf0QAAwwACgp7Ia8WAEADAAwACgp7Ia8WAEADABgABwpHGfM1AJ4BAAE1AAQKCgouAAoAziAA.',
Ex='Extrathick:BAAANQAECgEIAQAAAA==.',
Fa='Fathershale:BAAANQADCgYIFAAAAA==.',
Fe='Fedupdk:BAAANQADCgYIDQAAAA==.Feet:BAAANQAECgcICwAAAA==.Felidae:BAEANQAECgQIBAAAAA==.',
Fi='Firedancer:BAAANQAECgUICwAAAA==.Fizzfiend:BAAANQADCggIDQAAAA==.',
Fo='Foulcor:BAAANQAECgQIBAABNQAECgkJIQAMAMUcAA==.',
Fr='Freakadeek:BAAANQAECgMIBgABNQAECgcIGgAXAHETAA==.Freâkadeek:BAAANQADCgQIBAABNQAECgcIGgAXAHETAA==.Frieren:BAABNQAECn8pAAICAAkKYxQxCgAoAgACAAkKYxQxCgAoAgAAAA==.Frëak:BAAANQADCgUIBgABNQAECgcIGgAXAHETAA==.',
Ga='Gabbyo:BAABNQAECn8nAAIbAAcKGgqWMwASAQAbAAcKGgqWMwASAQAAAA==.Galadorn:BAABNQAECn8sAAMHAAkKvSHbEQAQAwAHAAkKTyHbEQAQAwAfAAUKriBGEACuAQAAAA==.',
Ge='Genasis:BAAANQABCgMIBQAAAA==.Gerdash:BAAANQAECgYIEwAAAA==.Gerred:BAABNQAECn8/AAIJAAkKlyHCIQCdAgAJAAkKlyHCIQCdAgAAAA==.',
Gh='Ghallow:BAABNQAECn8ZAAIgAAoKhhNACwAyAgAgAAoKhhNACwAyAgAAAA==.Ghosthowl:BAAANQAECgUIDAAAAA==.',
Gl='Gladur:BAAANQAECggICgABNQAFFAcIFgACAOoYAA==.',
Go='Goldenflame:BAAANQAECgcICwAAAA==.Goldenlight:BAABNQAECn8vAAIOAAoKkRJmVgAgAgAOAAoKkRJmVgAgAgAAAA==.Goldenmunc:BAAANQADCgIIAgAAAA==.Goldenone:BAABNQAECn8UAAIRAAYKMxx3QgDXAQARAAYKMxx3QgDXAQAAAA==.Goldenpants:BAAANQADCggIDwAAAA==.',
Gr='Grandesaxx:BAAANQAECgQICAAAAA==.Grievous:BAABNQAECn9IAAIfAAoK3SWfAABfAwAfAAoK3SWfAABfAwAAAA==.',
Ha='Hailmary:BAAANQAECgcIEQAAAA==.Hakudoshi:BAAANQAECgQICQAAAA==.Harmanee:BAAANQADCgYIBgAAAA==.Hauser:BAABNQAECn8pAAINAAoK2B3+YwBvAgANAAoK2B3+YwBvAgAAAA==.',
He='Healaga:BAAANQAECgUIBwABNQAECgoKLgAKANoYAA==.Heinrich:BAAANQADCgMIAwAAAA==.',
Hh='Hhoonnzz:BAAANQADCgYIBgABNQAECgoKLgAKAM4gAA==.',
Ho='Hornreaper:BAABNQAECn8jAAQhAAoKWBDULABAAQAhAAcKoQnULABAAQAUAAgK+w2SEAAvAQATAAIKywTjIQA1AAAAAA==.',
Hu='Hubbabubbajr:BAABNQAECn8eAAIOAAgKJhwuOgAbAgAOAAgKJhwuOgAbAgAAAA==.',
['Hü']='Hülkster:BAAANQADCgEIAQAAAA==.',
Il='Ilavengu:BAABNQAECn8hAAIHAAkKwyG+DgCVAgAHAAkKwyG+DgCVAgABNQAFFAUIEAAeADMgAA==.',
Is='Isochu:BAAANQADCgMJAwAAAA==.',
Ja='Jayonor:BAABNQAECn9FAAMaAAoKCR0RGwBsAgAaAAoKCR0RGwBsAgAZAAEKwQCVOAEWAAAAAA==.',
Je='Jek:BAAANQAECgIIAwAAAA==.',
Jo='Jonohae:BAAANQAECgIIAQABNQAECgoKPQAJAKoXAA==.',
Ju='Judgethis:BAAANQABCgIIAgAAAA==.Juicycucci:BAAANQAECgYICQABNQAFFAUIEAAQAHQLAA==.',
Ka='Kaevrielle:BAEBNQAECn8aAAMfAAoKmhmCDAD+AQAfAAoKmhmCDAD+AQAHAAIK/Q/3cAA8AAAAAA==.Kaidrosa:BAAANQAECgIIAgAAAA==.Kainicefall:BAABNQAECn8kAAMiAAoKEA9LEABzAQAiAAgKDBBLEABzAQAVAAgKNgnaRgDVAAAAAA==.Kainicefell:BAAANQAECgIIAgAAAA==.Kainoficefal:BAABNQAECn8YAAMjAAkKAwjREwD5AAAJAAgKEAZi3AAzAQAjAAcKPwjREwD5AAAAAA==.Kaisa:BAAANQAECgQIBAAAAA==.Kaladîn:BAAANQAECgEIAQABNQAFFAcIFgACAOoYAA==.Kalokako:BAAANQADCgEIAQAAAA==.Kamel:BAAANQABCgQIBQAAAA==.Karwin:BAAANQAECggICwAAAA==.',
Ke='Keeper:BAABNQAECn8eAAIBAAoKFRcoCABAAgABAAoKFRcoCABAAgABNQAFFAMICgANAJciAA==.Keeperodark:BAABNQAECn8rAAIFAAoKrBKCPQDsAQAFAAoKrBKCPQDsAQABNQAFFAMICgANAJciAA==.Keeperolight:BAACNQAFFH8KAAINAAMKlyJDFADDAAANAAMKlyJDFADDAAA1AAQKf08AAg0ACgp2JocCAHkDAA0ACgp2JocCAHkDAAAA.',
Ki='Kifo:BAAANQAECgQIBgAAAA==.Killkat:BAAANQAECgcIEQAAAA==.Kirkulus:BAAANQAECggICQAAAA==.',
Ko='Koojo:BAABNQAECn8bAAIiAAcKRxcyDwCFAQAiAAcKRxcyDwCFAQAAAA==.',
La='Lans:BAAANQAECgIIAgAAAA==.Larew:BAAANQAECgUICAAAAA==.',
Le='Lealla:BAABNQAECn9HAAIVAAoKghyjEwBVAgAVAAoKghyjEwBVAgAAAA==.Leodin:BAAANQAECgIIAgAAAA==.Lethhunt:BAAANQAECgEIAQABNQAECgkJJgAcAEQZAA==.Letholas:BAABNQAECn8mAAQcAAkKRBl0NQAEAgAcAAgKHxl0NQAEAgAKAAcKwxNfXgCWAQALAAEKAADo0wApAAAAAA==.',
Li='Lightmàiden:BAAANQADCgEIAQAAAA==.Lilkingpunch:BAAANQADCgYIBgABNQAFFAUIDQAkAOAOAA==.Lizardgang:BAAANQAECgYIDwAAAA==.',
Lo='Lokan:BAABNQAECn8wAAMMAAoKzx4QGQC+AgAMAAoKzx4QGQC+AgAXAAYKaA1qDAASAQAAAA==.Lots:BAABNQAECn84AAMFAAoKrCPrOwCfAgAFAAgKrSPrOwCfAgAGAAIKqSPLDQDNAAAAAA==.',
Lu='Ludakris:BAAANQAECggIEQAAAA==.',
['Lí']='Líonheart:BAABNQAECn8bAAINAAkKKxF+hACDAQANAAkKKxF+hACDAQAAAA==.',
Ma='Maami:BAAANQAECgYICwAAAA==.Machognome:BAAANQADCgQIBAAAAA==.Mahina:BAABNQAECn8YAAIOAAYKUgGevQB9AAAOAAYKUgGevQB9AAAAAA==.Makrabro:BAAANQABCgIIAgAAAA==.Marcille:BAAANQAECgcIDgAAAA==.Marquistanyl:BAAANQAECgMIAwAAAA==.Mattix:BAAANQADCggICAAAAA==.Matíx:BAABNQAECn8nAAMFAAgK/Re4VgCWAQAFAAgK/Re4VgCWAQAGAAIKVA49XABtAAAAAA==.Mayhaps:BAABNQAECn8zAAMMAAoKHA5aaQBBAgAMAAoKHA5aaQBBAgAYAAEKAABdoQAWAAAAAA==.Mayoke:BAAANQAECgEIAwAAAA==.',
Me='Mentaltitty:BAABNQAECn8bAAIDAAcKXRM44QDGAQADAAcKXRM44QDGAQAAAA==.',
Mi='Milhouse:BAABNQAECn9IAAILAAoK6CNyBQAiAwALAAoK6CNyBQAiAwAAAA==.Minerwor:BAAANQAECgQIBgAAAA==.Mirrayla:BAAANQADCgEIAQAAAA==.Misty:BAAANQAECgUICgAAAA==.',
Mm='Mmisty:BAABNQAECn8yAAIVAAoKyBWcGAAWAgAVAAoKyBWcGAAWAgAAAA==.',
Mo='Momometaru:BAABNQAECn8nAAQGAAoKyxBQMgD8AAAFAAoKog7iaQBfAQAGAAQK8BFQMgD8AAAEAAMKnwo4GgC0AAABNQAECgoKKwAVAMoQAA==.Monsterbee:BAABNQAECn9GAAIFAAoK5BYiMgAZAgAFAAoK5BYiMgAZAgAAAA==.Morne:BAAANQADCggIEQAAAA==.',
Mu='Mustypizza:BAAANQAECgcIEQAAAA==.',
My='Mystery:BAABNQAECn9IAAMhAAoKzRtNCwA7AgAhAAoKzRtNCwA7AgATAAIKYAp/IAA8AAAAAA==.',
Na='Nailme:BAAANQAECgYIBgAAAA==.Nats:BAABNQAECn8aAAIZAAgK7RNAUwAaAgAZAAgK7RNAUwAaAgAAAA==.',
Ne='Neameny:BAABNQAECn8+AAIMAAoKoQ9CUQDqAQAMAAoKoQ9CUQDqAQAAAA==.',
Ni='Nightstar:BAAANQAECgYIBgAAAA==.',
Nu='Nualrossan:BAAANQADCgEIAgAAAA==.Nubrac:BAABNQAECn8fAAMbAAoKzRx+EQBoAgAbAAoKzRx+EQBoAgAVAAEKAABHlAAAAAAAAA==.',
Ob='Oblivion:BAABNQAECn9JAAMFAAoKiCRjBwAbAwAFAAoKiCRjBwAbAwAGAAIK0BQiVgB8AAAAAA==.',
Om='Omey:BAABNQAECn8UAAINAAYKewMnPAHAAAANAAYKewMnPAHAAAAAAA==.',
On='Onepercent:BAAANQAECggICAAAAA==.',
Pa='Pallyshore:BAAANQADCggICAAAAA==.Papichuló:BAAANQADCgMIBgABNQAECgcIGgAXAHETAA==.',
Pi='Pixae:BAABNQAECn8aAAIhAAkKeRDTJgCDAQAhAAkKeRDTJgCDAQAAAA==.',
Po='Porthoss:BAAANQABCgIIAgAAAA==.Portknight:BAAANQAECgEIAQAAAA==.Potatochip:BAAANQAECgIIAgAAAA==.Powerplant:BAACNQAFFH8RAAIMAAYKUB9CBgBaAQAMAAYKUB9CBgBaAQA1AAQKfzwAAgwACgqoInwRAO0CAAwACgqoInwRAO0CAAAA.',
Py='Pyralys:BAABNQAECn9FAAIOAAoKOhB3QAAAAgAOAAoKOhB3QAAAAgAAAA==.',
['Pâ']='Pârtyrockêr:BAAANQAECgYIBwABNQAECgcIGgAXAHETAA==.',
['Pä']='Pärts:BAAANQADCgQIBAABNQAECggIEQAIAAAAAA==.',
Ra='Raelene:BAAANQADCgYICQAAAA==.Ragedk:BAAANQAECgIIAwABNQAECgcIBwAIAAAAAA==.Ragenbefcake:BAAANQAECgQIBAAAAA==.Ragetality:BAAANQAECgcIBwAAAA==.Rallaster:BAAANQAECgUIDQABNQAECgoKSAAeAHEUAA==.Rampage:BAAANQABCgUIAgAAAA==.Raserei:BAABNQAECn8kAAMjAAoKYxydBwB6AgAjAAgKxx2dBwB6AgAJAAUK1RjKogAAAQAAAA==.Rattelyr:BAAANQADCgQIBAAAAA==.Rawb:BAAANQAECgYJCgABNQAECgoKLgAKAM4gAA==.',
Re='Recolada:BAAANQADCgcJDAAAAA==.Regicee:BAABNQAECn8VAAMKAAgKchOUVQC7AQAKAAcK7BWUVQC7AQALAAEKDweskwAzAAAAAA==.',
Ro='Rockdyou:BAABNQAECn8fAAMcAAoKaRN1KgDOAQAcAAkKXw51KgDOAQAKAAgKyxPzLgBCAQAAAA==.Roflstomper:BAAANQADCgEIAQAAAA==.Rotlobster:BAABNQAECn8fAAIEAAkKhyJAAQBUAwAEAAkKhyJAAQBUAwABNQAECgoKOgAgAEMeAA==.Rottenrigger:BAAANQABCgQIBAAAAA==.',
Ru='Rudal:BAAANQADCgIIAgAAAA==.Rundvelt:BAAANQADCgIIAgAAAA==.',
Ry='Rydiaicefall:BAAANQAECgUICgAAAA==.',
Sa='Sapkick:BAAANQAECgQIBAAAAA==.',
Se='Selina:BAAANQAECgQIBAAAAA==.Serdwarf:BAABNQAECn8kAAMOAAkKmRmcVQAiAgAOAAcK8xqcVQAiAgAeAAgKxhAfHQBqAQAAAA==.Sertian:BAAANQADCgQIBAAAAA==.',
Sh='Shatha:BAAANQADCgQIBQAAAA==.Sherten:BAAANQAECgIIAgAAAA==.Shooturiout:BAAANQAECgMIAwAAAA==.Shtanky:BAABNQAECn8fAAIWAAoKZxKfFgDAAQAWAAoKZxKfFgDAAQAAAA==.',
Si='Sinpony:BAAANQABCgQIBAAAAA==.Sixsixsix:BAAANQADCggJCgABNQAECgoKLgAKAM4gAA==.',
Sk='Sketch:BAAANQAECgIIAgABNQAFFAcIGAAdAFAXAA==.Skoogz:BAAANQAECggIDAAAAA==.',
So='Soggyy:BAAANQAECgEIAQAAAA==.Sogsy:BAABNQAECn8UAAIDAAcKKwX4LgE+AQADAAcKKwX4LgE+AQAAAA==.Soleri:BAAANQAECgYICgAAAA==.Soulfulgingr:BAAANQAECgUIBwAAAA==.',
St='Styx:BAAANQAECgYIDwAAAA==.Stza:BAAANQABCgYICAAAAA==.',
Su='Sunbake:BAAANQAECgUIEQAAAA==.',
Sw='Sweetbbyraze:BAACNQAFFH8RAAMTAAYKyBPYBAB8AQATAAUK/BbYBAB8AQAUAAEKLQqmCwBMAAA1AAQKfyoAAxMACgr8HrIIAOwCABMACgpaHrIIAOwCABQAAQpWG6oWAFEAAAAA.Swiftzz:BAAANQAECgcIBwAAAA==.',
Sz='Szayell:BAAANQADCgQIBAAAAA==.',
['Sí']='Sín:BAAANQADCgIJAgABNQAECgoKLgAKAM4gAA==.',
Ta='Talipally:BAABNQAECn8eAAMNAAoKmwqK1AByAQANAAoKmwqK1AByAQAPAAEKQAPgZAAdAAAAAA==.Taliwhacker:BAAANQADCgMIAwABNQAECgoKHgANAJsKAA==.Talonleafgrd:BAABNQAECn8gAAIYAAcKYRPfGwBeAQAYAAcKYRPfGwBeAQAAAA==.Tandsonna:BAAANQAECggIEAAAAA==.Tanisong:BAAANQAECgQIBwAAAA==.',
Te='Terayus:BAAANQADCgIJAgAAAA==.Terraform:BAAANQADCgYICwAAAA==.',
Th='Thalor:BAABNQAECn8fAAMLAAoKGRw4EQBvAgALAAoKGRw4EQBvAgAcAAMK0BZ5jgB9AAABNQAFFAYIDQAlAG8ZAA==.Thekingpunch:BAACNQAFFH8NAAIkAAUK4A5EBAA5AQAkAAUK4A5EBAA5AQA1AAQKf1wAAiQACgo0IsQFAEEDACQACgo0IsQFAEEDAAAA.Thenle:BAAANQAECgEIAQAAAA==.Theworst:BAAANQAECgYIBgABNQAECgoKLgAKAM4gAA==.Thiel:BAAANQAECggIBwAAAA==.',
Ti='Tillwar:BAABNQAECn9KAAIJAAoKsBoxNABGAgAJAAoKsBoxNABGAgAAAA==.Timmu:BAAANQADCgEIAQAAAA==.Tiàna:BAAANQADCgEIAQAAAA==.',
To='Tofu:BAABNQAECn8bAAIKAAoK1x2SLwBxAgAKAAoK1x2SLwBxAgAAAA==.Tortillachip:BAAANQADCgYIBgAAAA==.Totemayhem:BAAANQADCgcIBwAAAA==.',
Tr='Treibh:BAABNQAECn9DAAIbAAoKthqXDQCsAgAbAAoKthqXDQCsAgAAAA==.Trulydps:BAABNQAECn8lAAIMAAkK8wrtmQDTAQAMAAkK8wrtmQDTAQAAAA==.',
Tu='Tust:BAAANQAECgQIBwABNQAECgUIDAAIAAAAAA==.',
Ty='Tymora:BAAANQADCggICAABNQAECgoKSAAeAHEUAA==.',
['Të']='Tërris:BAABNQAECn8YAAILAAkKdhgbPAATAgALAAkKdhgbPAATAgAAAA==.',
['Tî']='Tîlldeath:BAAANQAECgUICgAAAA==.',
Un='Undzl:BAACNQAFFH8KAAMcAAIKox/SEwChAAAcAAIKox/SEwChAAAKAAEKcgYWJQA4AAA1AAQKf1AAAwoACgqqJUwKAGoDAAoACQqhIkwKAGoDABwACQr8JMcLADkDAAAA.Unknowna:BAAANQADCgYIBgAAAA==.',
Ur='Urowndad:BAAANQADCgIIAgABNQAECgYIDwAIAAAAAA==.Urownmother:BAAANQAECgEIAQABNQAECgYIDwAIAAAAAA==.',
Va='Vallez:BAEBNQAECn8rAAMRAAoKBSV1DQBeAwARAAoKBSV1DQBeAwANAAEKAACargEwAAAAAA==.Varnusshadow:BAAANQAECgIIBAAAAA==.Vayn:BAAANQAECgYIDwAAAA==.',
Ve='Velladoree:BAAANQAECgIIAwAAAA==.Vexahlia:BAAANQAECggIDgAAAA==.',
Vg='Vgurlpally:BAAANQADCgIIAgAAAA==.',
['Vé']='Véñable:BAABNQAECn8eAAQBAAkK2A1lEgCIAQABAAkKvA1lEgCIAQAmAAMK2gQRFwB1AAASAAEKAADcVgAnAAAAAA==.',
Wa='Waveygravee:BAAANQADCgcJCwAAAA==.Wavygraivy:BAAANQAECgQIEwAAAA==.',
We='Wedragon:BAAANQAECgUIBQAAAA==.',
Wi='Wildearth:BAAANQAECgQIAwAAAA==.',
Wo='Woofwoof:BAAANQAECgIIBAAAAA==.Wooshh:BAAANQAECgUIDQAAAA==.',
Xh='Xhexana:BAABNQAECn8hAAIZAAcK+BEWbAA9AQAZAAcK+BEWbAA9AQABNQAECgoKPgAMAKEPAA==.',
Xi='Xianofukuju:BAABNQAECn8rAAIVAAoKyhC+QwDlAQAVAAoKyhC+QwDlAQAAAA==.',
Xr='Xrayl:BAACNQAFFH8FAAMlAAMKNg5CEACLAAAlAAMKNg5CEACLAAAnAAEK2AynBwA8AAA1AAQKfzUAAycACgpzHAcLAF4CACcACgpqGgcLAF4CACUABgq+HL0sALQBAAAA.',
Xz='Xzerocool:BAAANQAECgYIDwAAAA==.',
Yo='Yoshikazu:BAAANQAECgIIAgAAAA==.',
Za='Zaarah:BAAANQADCgUIGQAAAA==.Zanthian:BAAANQABCgEIAQAAAA==.',
Ze='Zendezoth:BAABNQAECn8eAAITAAoK+wzgCAC/AQATAAoK+wzgCAC/AQAAAA==.Zevthekuatin:BAABNQAECn8iAAIMAAoKqw0HUADuAQAMAAoKqw0HUADuAQAAAA==.',
Zh='Zhiva:BAABNQAECn8eAAIVAAgKDQkZOwAOAQAVAAgKDQkZOwAOAQAAAA==.',
Zy='Zykoz:BAAANQAECgcIEQAAAA==.',
['Åy']='Åyna:BAAANQADCgcIEQAAAA==.',
['Ða']='Ðaddy:BAAANQAECgcIEQAAAA==.Ðamned:BAAANQAECgUICAABNQAECgoKLgAKAM4gAA==.',
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
