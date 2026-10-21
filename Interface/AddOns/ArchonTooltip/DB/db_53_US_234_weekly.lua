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

local lookup = {'Rogue-Assassination','Mage-Frost','Mage-Arcane','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Arms','Hunter-BeastMastery','Paladin-Retribution','Priest-Holy','Paladin-Protection','DemonHunter-Devourer','Unknown-Unknown','Paladin-Holy','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Havoc','Druid-Balance','Warrior-Protection','Hunter-Survival','Hunter-Marksmanship','Druid-Restoration','DeathKnight-Frost','Druid-Guardian','Priest-Shadow','DemonHunter-Vengeance','Evoker-Preservation','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Warrior-Fury','Shaman-Enhancement','Monk-Windwalker','Rogue-Outlaw','Monk-Brewmaster',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abel:BAEANQADCggICAABNQAECgkJHgABANgNAA==.',
Ae='Aeidail:BAACNQAFFH8VAAMCAAcK6hhwBQC7AAADAAUK3xe0GgCmAQACAAMKmhVwBQC7AAA1AAQKfzAAAwIACgpMIAoHAIYCAAMACQogIulUANYCAAIACAqKHgoHAIYCAAAA.',
Ag='Agraceful:BAAANQAECgUIBgAAAA==.',
Ai='Aidton:BAAANQAECgEIAQAAAA==.Aiobhicefall:BAAANQAECgUIBwAAAA==.Aiobhicefell:BAAANQAECgUIDgAAAA==.Aiobicefall:BAAANQAECgcIDQAAAA==.Aioboicefall:BAAANQADCggIDAAAAA==.Aioicefall:BAAANQAECgQIBAAAAA==.Aiza:BAABNQAECn89AAQEAAoKwhgNDgBzAQAEAAYKFxUNDgBzAQAFAAgK5Rj9OQAdAQAGAAMKkguNSQCjAAAAAA==.',
Al='Albinoknight:BAAANQADCgEIAQAAAA==.Alessia:BAAANQADCgYICgAAAA==.',
An='Angrypants:BAAANQAECgYIEAAAAA==.Animalfriend:BAAANQAECgMIAwAAAA==.Anklesmasher:BAAANQAECgIIBwAAAA==.Antisocial:BAAANQADCggIEAABNQAECgoKLgAHAM4gAA==.',
Ar='Arfaz:BAABNQAECn8gAAMHAAoKxBXHBADyAQAHAAoKxBXHBADyAQAIAAEKcg7Y0wApAAAAAA==.Arthemis:BAAANQAECgQIBAAAAA==.Arçano:BAAANQADCgMIAwABNQAECgoKLQAJAFIVAA==.',
As='Astramoon:BAAANQAECgUIEQAAAA==.',
Ba='Baerd:BAAANQADCgcICQAAAA==.Barlz:BAAANQADCgUIEwAAAA==.',
Be='Beasthunt:BAABNQAECn8XAAIKAAcK8Rw3agA/AgAKAAcK8Rw3agA/AgAAAA==.Beatmywillie:BAAANQAECgUIBQAAAA==.Bebby:BAAANQAECgQICwAAAA==.Belienn:BAAANQADCggICAAAAA==.Belwolf:BAAANQADCgcIFAAAAA==.Bennehona:BAAANQADCgEIAQAAAA==.Bergstrom:BAABNQAECn8rAAILAAgKJQ1aQABGAQALAAgKJQ1aQABGAQAAAA==.Betrayer:BAAANQAECgIIAwABNQAECgkJNQAFADYjAA==.',
Bi='Biancafiamma:BAAANQAECgIIAgAAAA==.Biancaneve:BAABNQAECn8bAAIMAAgKmRZAWQAWAgAMAAgKmRZAWQAWAgAAAA==.',
Bo='Bombacløt:BAABNQAECn8gAAMGAAgKJBEfEwDaAQAGAAcKDBMfEwDaAQAFAAUKWQuNTQDrAAAAAA==.',
Br='Brastin:BAABNQAECn8eAAINAAcKNxfQEQAAAQANAAcKNxfQEQAAAQAAAA==.Brenell:BAABNQAECn8hAAIDAAgKbBXQtQAYAgADAAgKbBXQtQAYAgAAAA==.Brixscen:BAAANQAECgYICwAAAA==.',
Bu='Bubblehearth:BAAANQAECgEIAQABNQAFFAUIEAAOAHQLAA==.',
Ca='Cabëla:BAAANQAECgUICQABNQAECgYIEAAPAAAAAA==.Caineicefall:BAAANQADCggICwAAAA==.Calacolinda:BAABNQAECn8dAAMQAAYKuQURwAD8AAAQAAYKuQURwAD8AAALAAYKIAjWMgHOAAAAAA==.',
Ce='Celestiall:BAAANQAECgYICQAAAA==.Ceridwyn:BAAANQADCgcIEgAAAA==.',
Ch='Chadalonius:BAAANQADCgQIBAABNQAFFAUIDQARAJ8SAA==.Cheesecurd:BAAANQAECgIIAgAAAA==.Choal:BAAANQADCgYICwAAAA==.Chriswin:BAAANQADCgEIAgAAAA==.',
Cl='Claytonbigsb:BAAANQADCgYIBgABNQAECgYIDwAPAAAAAA==.',
Co='Corahin:BAAANQAECgQIBAAAAA==.',
Cu='Cuecumba:BAAANQAECgYIDwAAAA==.',
Cy='Cynndi:BAAANQABCgYIBgAAAA==.',
Da='Dalren:BAACNQAFFH8TAAISAAYKSBYfAQDjAAASAAYKSBYfAQDjAAA1AAQKfzwAAxIACgqkH4MEAFMDABIACgqOH4MEAFMDABMAAgpnHQQcAIcAAAAA.Dalvix:BAAANQAECgIIAwABNQAECggIIwAUAN8iAA==.Dammedude:BAAANQABCgMIAwAAAA==.Dartagnan:BAABNQAECn8bAAIKAAoKYhNSfwAOAgAKAAoKYhNSfwAOAgAAAA==.Darthmaul:BAABNQAECn8tAAIVAAkKMA8xDgBsAQAVAAkKMA8xDgBsAQAAAA==.Daveykrook:BAAANQAECggIBAABNQAECggIIQAFACEWAA==.David:BAABNQAECn8VAAILAAgKWwqF1QBwAQALAAgKWwqF1QBwAQAAAA==.',
De='Dendiian:BAAANQADCgYICQAAAA==.Depletor:BAABNQAECn8kAAMJAAoKXwiNugCKAQAJAAoKXwiNugCKAQAWAAMKCASbPABTAAAAAA==.Devils:BAAANQADCgEIAQAAAA==.',
Di='Diem:BAAANQAECgYICgAAAA==.Dirtydotss:BAAANQAECgQIBQAAAA==.',
Do='Docholiday:BAABNQAECn8aAAQXAAcKcROQCADFAQAXAAYK+xWQCADFAQAYAAUKGgenIwCDAAAKAAIKmQHcPQFoAAAAAA==.Docsassist:BAAANQAECgYICwAAAA==.Dowedoes:BAABNQAECn80AAILAAkKzQt0QgBBAQALAAkKzQt0QgBBAQAAAA==.',
Dr='Drachula:BAAANQAECgUIEQAAAA==.Dracultra:BAAANQADCgYIBgABNQAECggIGAAQAIIVAA==.Draeun:BAAANQAECgEIAQABNQAFFAYIEwASAEgWAA==.Dreolan:BAABNQAECn8XAAIZAAgKjw8MFwAKAQAZAAgKjw8MFwAKAQAAAA==.Druaga:BAAANQAECggIDgAAAA==.Dràchula:BAAANQADCgYICQAAAA==.Dràúgr:BAAANQADCgMIAwAAAA==.',
Dy='Dyala:BAABNQAECn8gAAIZAAoK9hsXGAB/AgAZAAoK9hsXGAB/AgAAAA==.',
Dz='Dzznuts:BAAANQABCgYICgAAAA==.',
['Dé']='Démonléth:BAAANQAECgIIAgABNQAECgkJJgAaAEQZAA==.',
['Dö']='Dönövan:BAABNQAECn8gAAILAAgKowu8dADeAAALAAgKowu8dADeAAAAAA==.',
Eg='Eggyolk:BAABNQAECn8aAAIbAAgKXxdAFAAhAgAbAAgKXxdAFAAhAgAAAA==.',
El='Elastwo:BAAANQADCggIGQAAAA==.Eloise:BAAANQAECgEIAQAAAA==.Elvenbane:BAABNQAECn80AAMcAAkKvhI4JAAPAgAcAAkKvhI4JAAPAgAMAAgKWgOPoAAzAQAAAA==.',
Eu='Eunliza:BAAANQAECggICAAAAA==.',
Ew='Ew:BAACNQAFFH8QAAMKAAYK6BWNBQD7AQAKAAYK6BWNBQD7AQAYAAEKyAdXJQBAAAA1AAQKfzUAAwoACgphIa8WAEADAAoACgphIa8WAEADABgABwpHGfM1AJ4BAAE1AAQKCgouAAcAziAA.',
Ex='Extrathick:BAAANQAECgEIAQAAAA==.',
Fa='Fathershale:BAAANQADCgYIFAAAAA==.',
Fe='Fedupdk:BAAANQADCgYIDQAAAA==.Feet:BAAANQAECgYICgAAAA==.',
Fi='Firedancer:BAAANQAECgQICAAAAA==.Fizzfiend:BAAANQADCggIDQAAAA==.',
Fo='Foulcor:BAAANQAECgIIAwABNQAECgcIFwAKAPEcAA==.',
Fr='Freakadeek:BAAANQAECgMIBgABNQAECgcIGgAXAHETAA==.Freâkadeek:BAAANQADCgQIBAABNQAECgcIGgAXAHETAA==.Frieren:BAABNQAECn8hAAICAAkKYxQ3AgDHAQACAAkKYxQ3AgDHAQAAAA==.Frëak:BAAANQADCgUIBgABNQAECgcIGgAXAHETAA==.',
Ga='Gabbyo:BAABNQAECn8dAAIZAAYKpQkpFwAJAQAZAAYKpQkpFwAJAQAAAA==.Galadorn:BAABNQAECn8jAAMUAAgK3yLbEQAQAwAUAAgKXiLbEQAQAwAdAAUKriBGEACuAQAAAA==.',
Ge='Genasis:BAAANQABCgMIBQAAAA==.Gerdash:BAAANQAECgYIEwAAAA==.Gerred:BAABNQAECn8uAAIJAAkKiB64CgATAgAJAAkKiB64CgATAgAAAA==.',
Gh='Ghallow:BAAANQAECgYICgAAAA==.Ghosthowl:BAAANQAECgUIDAAAAA==.',
Gl='Gladur:BAAANQAECgIIAgABNQAFFAcIFQACAOoYAA==.',
Go='Goldenflame:BAAANQAECgUICgAAAA==.Goldenlight:BAABNQAECn8qAAIMAAkK4BJmVgAgAgAMAAkK4BJmVgAgAgAAAA==.Goldenmunc:BAAANQADCgIIAgAAAA==.Goldenone:BAAANQAECgUIDwAAAA==.Goldenpants:BAAANQADCggIDwAAAA==.',
Gr='Grandesaxx:BAAANQAECgQICAAAAA==.Grievous:BAABNQAECn80AAIdAAkKkCRvAADQAgAdAAkKkCRvAADQAgAAAA==.',
Ha='Hailmary:BAAANQAECgYIEAAAAA==.Hakudoshi:BAAANQAECgUIBwAAAA==.Harmanee:BAAANQADCgYIBgAAAA==.Hauser:BAABNQAECn8iAAILAAoKsxn+YwBvAgALAAoKsxn+YwBvAgAAAA==.',
He='Healaga:BAAANQAECgUIBwABNQAECgoKIAAHAMQVAA==.Heinrich:BAAANQADCgMIAwAAAA==.',
Hh='Hhoonnzz:BAAANQADCgYIBgABNQAECgoKLgAHAM4gAA==.',
Ho='Hornreaper:BAABNQAECn8hAAQeAAoKBhDULABAAQAeAAcKoQnULABAAQATAAgKPgySEAAvAQASAAIKywSXFAA8AAAAAA==.',
Hu='Hubbabubbajr:BAABNQAECn8YAAIMAAcKzh0mDQAXAgAMAAcKzh0mDQAXAgAAAA==.',
Il='Ilavengu:BAAANQAECggIEQABNQAFFAUIEAAcADMgAA==.',
Is='Isochu:BAAANQADCgMJAwAAAA==.',
Ja='Jayonor:BAABNQAECn8xAAMfAAkKPxl1CgDCAQAfAAkKPxl1CgDCAQAgAAEKwQCVOAEWAAAAAA==.',
Jo='Jonohae:BAAANQAECgIIAQABNQAECgoKLQAJAFIVAA==.',
Ju='Judgethis:BAAANQABCgIIAgAAAA==.Juicycucci:BAAANQAECgQIBAABNQAFFAUIEAAOAHQLAA==.',
Ka='Kaevrielle:BAEBNQAECn8VAAIdAAgKWRmCDAD+AQAdAAgKWRmCDAD+AQAAAA==.Kaidrosa:BAAANQAECgIIAgAAAA==.Kainicefall:BAABNQAECn8UAAIVAAgK/AdcJQDQAAAVAAgK/AdcJQDQAAAAAA==.Kainicefell:BAAANQAECgIIAgAAAA==.Kainoficefal:BAAANQAECgYICQAAAA==.Kaladîn:BAAANQAECgEIAQABNQAFFAcIFQACAOoYAA==.Kalokako:BAAANQADCgEIAQAAAA==.Kamel:BAAANQABCgQIBQAAAA==.Karwin:BAAANQAECggICwAAAA==.',
Ke='Keeper:BAAANQAECggIEAABNQAFFAIIBwALAAMiAA==.Keeperodark:BAABNQAECn8aAAIFAAoKEhGGZwAkAgAFAAoKEhGGZwAkAgABNQAFFAIIBwALAAMiAA==.Keeperolight:BAACNQAFFH8HAAILAAIKAyJ5CgDBAAALAAIKAyJ5CgDBAAA1AAQKfzsAAgsACgpoJUgFAM8DAAsACgpoJUgFAM8DAAAA.',
Ki='Kifo:BAAANQAECgQIBAAAAA==.Killkat:BAAANQAECgYIEAAAAA==.Kirkulus:BAAANQAECggICAAAAA==.',
Ko='Koojo:BAAANQAECgYIEAAAAA==.',
La='Lans:BAAANQAECgIIAgAAAA==.Larew:BAAANQAECgQICAAAAA==.',
Le='Lealla:BAABNQAECn8zAAIVAAkKWBtiBQDxAQAVAAkKWBtiBQDxAQAAAA==.Leodin:BAAANQADCgYIBgAAAA==.Lethhunt:BAAANQAECgEIAQABNQAECgkJJgAaAEQZAA==.Letholas:BAABNQAECn8mAAQaAAkKRBl0NQAEAgAaAAgKHxl0NQAEAgAHAAcKwxNfXgCWAQAIAAEKAADo0wApAAAAAA==.',
Li='Lightmàiden:BAAANQADCgEIAQAAAA==.Lilkingpunch:BAAANQADCgYIBgABNQAFFAQICAAhABMRAA==.Lizardgang:BAAANQAECgUIDgAAAA==.',
Lo='Loganshu:BAAANQADCgYIBgAAAA==.Lokan:BAABNQAECn8jAAMKAAoKrRhEKQB2AQAKAAkKtBpEKQB2AQAXAAYKaA1qDAASAQAAAA==.Lots:BAABNQAECn8nAAMFAAoKhSHrOwCfAgAFAAgKyyHrOwCfAgAGAAIKtCBhQgC7AAAAAA==.',
Lu='Ludakris:BAAANQAECgYIEAAAAA==.',
['Lí']='Líonheart:BAAANQAECgcICgAAAA==.',
Ma='Maami:BAAANQAECgYICwAAAA==.Machognome:BAAANQADCgQIBAAAAA==.Mahina:BAAANQAECgUIEgAAAA==.Makrabro:BAAANQABCgIIAgAAAA==.Marcille:BAAANQAECgcIDgAAAA==.Mattix:BAAANQADCggICAAAAA==.Matíx:BAABNQAECn8hAAMFAAgKIRZLEQC5AQAFAAgKIRZLEQC5AQAGAAIKVA49XABtAAAAAA==.Mayhaps:BAABNQAECn8qAAMKAAoKyQ1aaQBBAgAKAAoKyQ1aaQBBAgAYAAEKAABdoQAWAAAAAA==.Mayoke:BAAANQAECgEIAQAAAA==.',
Me='Mentaltitty:BAABNQAECn8VAAIDAAcKXRM44QDGAQADAAcKXRM44QDGAQAAAA==.',
Mi='Milhouse:BAABNQAECn80AAIIAAkKHiAHAwBSAgAIAAkKHiAHAwBSAgAAAA==.Minerwor:BAAANQAECgQIBAAAAA==.Miooh:BAAANQADCgcIGQAAAA==.Mirrayla:BAAANQADCgEIAQAAAA==.Misty:BAAANQAECgQIBAAAAA==.',
Mm='Mmisty:BAABNQAECn8fAAIVAAkKjg/jRADeAQAVAAkKjg/jRADeAQAAAA==.',
Mo='Momometaru:BAABNQAECn8hAAQGAAoKCw5QMgD8AAAFAAoK4gsJhQDZAQAGAAQK8BFQMgD8AAAEAAMKnwo4GgC0AAAAAA==.Monsterbee:BAABNQAECn8yAAIFAAoKcBVyUABjAgAFAAoKcBVyUABjAgAAAA==.Morne:BAAANQADCgYIBgAAAA==.',
Mu='Mustypizza:BAAANQAECgYIEAAAAA==.',
My='Mystery:BAABNQAECn80AAIeAAkK9ht8AgAUAgAeAAkK9ht8AgAUAgAAAA==.',
Na='Nailme:BAAANQAECgUIBQAAAA==.Nats:BAABNQAECn8aAAIgAAgK7RNAUwAaAgAgAAgK7RNAUwAaAgAAAA==.',
Ne='Neameny:BAABNQAECn80AAIKAAkK7A5fEwDXAQAKAAkK7A5fEwDXAQAAAA==.',
Ni='Nightstar:BAAANQADCgYIBgAAAA==.',
Nu='Nualrossan:BAAANQADCgEIAgAAAA==.Nubrac:BAAANQAECgYIEQAAAA==.',
Ob='Oblivion:BAABNQAECn81AAMFAAkKNiPZAwCYAgAFAAkKNiPZAwCYAgAGAAIK0BQiVgB8AAAAAA==.',
Om='Omey:BAAANQAECgUIDgAAAA==.',
Pa='Pallyshore:BAAANQADCggICAAAAA==.Papichuló:BAAANQADCgMIBgABNQAECgcIGgAXAHETAA==.',
Pi='Pixae:BAAANQAECggIDwAAAA==.',
Po='Portknight:BAAANQAECgEIAQAAAA==.Potatochip:BAAANQAECgIIAgAAAA==.Powerplant:BAACNQAFFH8QAAIKAAUKeiJ8BAAVAQAKAAUKeiJ8BAAVAQA1AAQKfy4AAgoACgoCIi0YADkDAAoACgoCIi0YADkDAAAA.',
Py='Pyralys:BAABNQAECn8yAAIMAAkK9w9bHQCSAQAMAAkK9w9bHQCSAQAAAA==.',
['Pâ']='Pârtyrockêr:BAAANQAECgEIAQABNQAECgcIGgAXAHETAA==.',
['Pä']='Pärts:BAAANQADCgQIBAABNQAECggIEAAPAAAAAA==.',
Ra='Raelene:BAAANQADCgYICQAAAA==.Ragedk:BAAANQAECgIIAwABNQAECgcIBwAPAAAAAA==.Ragenbefcake:BAAANQAECgQIBAAAAA==.Ragetality:BAAANQAECgcIBwAAAA==.Rallaster:BAAANQAECgUICQABNQAECgkJNAAcAL4SAA==.Rampage:BAAANQABCgUIAgAAAA==.Raserei:BAABNQAECn8hAAMiAAgK9R6dBwB6AgAiAAgKxx2dBwB6AgAJAAMKmxtgiACOAAAAAA==.Rattelyr:BAAANQADCgQIBAAAAA==.Rawb:BAAANQAECgYJCgABNQAECgoKLgAHAM4gAA==.',
Re='Recolada:BAAANQADCgcJDAAAAA==.Regicee:BAABNQAECn8VAAMHAAgKchOUVQC7AQAHAAcK7BWUVQC7AQAIAAEKDwfcYQA2AAAAAA==.',
Ri='Riffraff:BAAANQADCggICgAAAA==.',
Ro='Rockdyou:BAAANQAECgYICwAAAA==.Rotlobster:BAABNQAECn8eAAIEAAkKhyJAAQBUAwAEAAkKhyJAAQBUAwABNQAECgkJLAAjAKcfAA==.Rottenrigger:BAAANQABCgQIBAAAAA==.',
Ru='Rudal:BAAANQADCgIIAgAAAA==.Rundvelt:BAAANQADCgIIAgAAAA==.',
Ry='Rydiaicefall:BAAANQAECgQIBwAAAA==.',
Sa='Sapkick:BAAANQAECgQIBAAAAA==.',
Se='Selina:BAAANQAECgQIBAAAAA==.Serdwarf:BAABNQAECn8bAAMMAAgKaBmcVQAiAgAMAAcK3RqcVQAiAgAcAAcKfgzGGQC6AAAAAA==.Sertian:BAAANQADCgQIBAAAAA==.',
Sh='Shatha:BAAANQADCgQIBQAAAA==.Sherten:BAAANQAECgIIAgAAAA==.Shooturiout:BAAANQAECgMIAwAAAA==.Shtanky:BAABNQAECn8bAAIWAAoKzhDCCwDzAAAWAAoKzhDCCwDzAAAAAA==.',
Si='Sinpony:BAAANQABCgQIBAAAAA==.Sixsixsix:BAAANQADCggJCgABNQAECgoKLgAHAM4gAA==.',
Sk='Sketch:BAAANQAECgIIAgABNQAFFAYIFwAbAH0YAA==.Skoogz:BAAANQAECgcIBgAAAA==.',
So='Soggyy:BAAANQAECgEIAQAAAA==.Sogsy:BAABNQAECn8UAAIDAAcKKwX4LgE+AQADAAcKKwX4LgE+AQAAAA==.Soleri:BAAANQAECgQIBAAAAA==.Soulfulgingr:BAAANQAECgIIAgAAAA==.',
St='Styx:BAAANQAECgUICgAAAA==.Stza:BAAANQABCgYICAAAAA==.',
Su='Sunbake:BAAANQAECgQICQAAAA==.',
Sw='Sweetbbyraze:BAACNQAFFH8QAAISAAUK/BaCAQDGAAASAAUK/BaCAQDGAAA1AAQKfyMAAhIACQqIH7IIAOwCABIACQqIH7IIAOwCAAAA.Swiftzz:BAAANQADCgcIBwAAAA==.',
['Sí']='Sín:BAAANQADCgIJAgABNQAECgoKLgAHAM4gAA==.',
Ta='Talipally:BAABNQAECn8aAAMLAAkKrQeK1AByAQALAAgKagiK1AByAQANAAEKQAPqPQAiAAAAAA==.Taliwhacker:BAAANQADCgMIAwABNQAECgkJGgALAK0HAA==.Talonleafgrd:BAABNQAECn8UAAIYAAYKWRTxOQCBAQAYAAYKWRTxOQCBAQAAAA==.Tandsonna:BAAANQAECggIDQAAAA==.Tanisong:BAAANQAECgQIBwAAAA==.',
Te='Terayus:BAAANQADCgIJAgAAAA==.Terraform:BAAANQADCgYICwAAAA==.',
Th='Thalor:BAAANQAFFAMIAwABNQAFFAYIDQAkAG8ZAA==.Thekingpunch:BAACNQAFFH8IAAIhAAQKExFXAgAfAQAhAAQKExFXAgAfAQA1AAQKf0kAAiEACgpNIcQFAEEDACEACgpNIcQFAEEDAAAA.Thenle:BAAANQAECgEIAQAAAA==.Theworst:BAAANQAECgYIBgABNQAECgoKLgAHAM4gAA==.',
Ti='Tillwar:BAABNQAECn83AAIJAAkKZhiSDAD7AQAJAAkKZhiSDAD7AQAAAA==.Timmu:BAAANQADCgEIAQAAAA==.Tiàna:BAAANQADCgEIAQAAAA==.',
To='Tofu:BAABNQAECn8YAAIHAAgKlSCSLwBxAgAHAAgKlSCSLwBxAgAAAA==.Tortillachip:BAAANQADCgYIBgAAAA==.',
Tr='Treibh:BAABNQAECn8vAAIZAAoK6xVNBAAxAgAZAAoK6xVNBAAxAgAAAA==.Trulydps:BAABNQAECn8cAAIKAAgK5grtmQDTAQAKAAgK5grtmQDTAQAAAA==.',
Tu='Tust:BAAANQAECgQIBwABNQADCgcICwAPAAAAAA==.',
Ty='Tymora:BAAANQADCggICAABNQAECgkJNAAcAL4SAA==.',
['Të']='Tërris:BAABNQAECn8WAAIIAAgKnBobPAATAgAIAAgKnBobPAATAgAAAA==.',
['Tî']='Tîlldeath:BAAANQAECgUICgAAAA==.',
Un='Undzl:BAACNQAFFH8IAAMaAAIKox/SEwChAAAaAAIKox/SEwChAAAHAAEKcgYWJQA4AAA1AAQKfz8AAwcACgoSJEwKAGoDAAcACQqhIkwKAGoDABoACQpHI8cLADkDAAAA.Unknowna:BAAANQADCgYIBgAAAA==.',
Ur='Urowndad:BAAANQADCgIIAgABNQAECgYIDwAPAAAAAA==.',
Va='Vallez:BAEBNQAECn8kAAMQAAoKtyR1DQBeAwAQAAoKtyR1DQBeAwALAAEKAACargEwAAAAAA==.Varnusshadow:BAAANQAECgIIBAAAAA==.Vayn:BAAANQAECgUICgAAAA==.',
Ve='Velladoree:BAAANQAECgIIAgAAAA==.Vexahlia:BAAANQAECggIDgAAAA==.',
Vg='Vgurlpally:BAAANQADCgIIAgAAAA==.',
['Vé']='Véñable:BAABNQAECn8eAAQBAAkK2A0vBgC5AQABAAkKvA0vBgC5AQAlAAMK2gQRFwB1AAARAAEKAADcVgAnAAAAAA==.',
Wa='Waveygravee:BAAANQADCgcJCwAAAA==.Wavygraivy:BAAANQAECgUIEQAAAA==.',
We='Wedragon:BAAANQAECgQIBQAAAA==.',
Wo='Woofwoof:BAAANQAECgIIBAAAAA==.Wooshh:BAAANQAECgUIDQAAAA==.',
Xh='Xhexana:BAABNQAECn8hAAIgAAcK+BGyIQBgAQAgAAcK+BGyIQBgAQABNQAECgkJNAAKAOwOAA==.',
Xi='Xianofukuju:BAABNQAECn8lAAIVAAgKmxO+QwDlAQAVAAgKmxO+QwDlAQABNQAECgoKIQAGAAsOAA==.',
Xr='Xrayl:BAABNQAECn8uAAMmAAoKjhkHCwBeAgAmAAoKTRYHCwBeAgAkAAYKvhy9LAC0AQAAAA==.',
Xz='Xzerocool:BAAANQAECgYIDwAAAA==.',
Yo='Yoshikazu:BAAANQAECgIIAgAAAA==.',
Za='Zaarah:BAAANQADCgUIGQAAAA==.Zanthian:BAAANQABCgEIAQAAAA==.',
Ze='Zendezoth:BAAANQAECgcIDgAAAA==.Zevthekuatin:BAABNQAECn8XAAIKAAYKOQqVfAC0AAAKAAYKOQqVfAC0AAAAAA==.',
Zh='Zhiva:BAABNQAECn8XAAIVAAcKfQfBIgDdAAAVAAcKfQfBIgDdAAAAAA==.',
Zy='Zykoz:BAAANQAECgYIEAAAAA==.',
['Åy']='Åyna:BAAANQADCgcIEQAAAA==.',
['Ða']='Ðaddy:BAAANQAECgcIEQAAAA==.Ðamned:BAAANQAECgUICAABNQAECgoKLgAHAM4gAA==.',
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
