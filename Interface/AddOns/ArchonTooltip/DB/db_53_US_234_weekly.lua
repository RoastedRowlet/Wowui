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

local lookup = {'Unknown-Unknown','Mage-Frost','Mage-Arcane','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Warrior-Arms','Paladin-Retribution','DemonHunter-Devourer','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Hunter-BeastMastery','Druid-Balance','Warrior-Protection','Druid-Restoration','DeathKnight-Frost','Druid-Guardian','Priest-Shadow','Priest-Holy','Hunter-Marksmanship','DemonHunter-Vengeance','Evoker-Preservation','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','Monk-Mistweaver','Hunter-Survival','Warrior-Fury','Shaman-Enhancement','Monk-Windwalker','Paladin-Holy','Monk-Brewmaster',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abel:BAEANQADCggICAABNQAECgIIDQABAAAAAA==.',
Ae='Aeidail:BAACNQAFFIEQAAMCAAYKZhqrAwDAAAADAAQKVxj2HABhAQACAAIKhB6rAwDAAAA1AAQKgSsAAwIACQoaJEcFAJoCAAMACQq1IN5AAPUCAAIABwqaI0cFAJoCAAAA.',
Ag='Agraceful:BAAANQAECgUIBgAAAA==.',
Ai='Aidton:BAAANQAECgEIAQAAAA==.Aiobhicefall:BAAANQAECgMIBAAAAA==.Aiobhicefell:BAAANQAECgQICgAAAA==.Aiobicefall:BAAANQAECgQICAAAAA==.Aioboicefall:BAAANQADCgQIBAAAAA==.Aioicefall:BAAANQABCgYIBgAAAA==.Aiza:BAABNQAECoEuAAQEAAkK/hg0DAB3AQAFAAcK6RdjXQAdAgAEAAYKXhE0DAB3AQAGAAMKkgsFRQCnAAAAAA==.',
Al='Albinoknight:BAAANQADCgEIAQAAAA==.Alessia:BAAANQADCgYICgAAAA==.',
An='Angrypants:BAAANQAECgUICgAAAA==.Animalfriend:BAAANQADCggJDgAAAA==.Anklesmasher:BAAANQAECgIIAwAAAA==.Antisocial:BAAANQADCggIEAABNQAECgkKJAAHAFMhAA==.',
Ar='Arfaz:BAAANQAECgYIDgAAAA==.Arçano:BAAANQADCgMIAwABNQAECggIHgAIAN0SAA==.',
As='Astramoon:BAAANQAECgQICAAAAA==.',
Ba='Baerd:BAAANQADCgcICQAAAA==.Barlz:BAAANQADCgUIEwAAAA==.',
Be='Beasthunt:BAAANQAECgUICwAAAA==.Beatmywillie:BAAANQAECgUIBQAAAA==.Bebby:BAAANQAECgQICAAAAA==.Belwolf:BAAANQADCgcIFAAAAA==.Bennehona:BAAANQADCgEIAQAAAA==.Bergstrom:BAABNQAECoEfAAIJAAgKaAwingCvAQAJAAgKaAwingCvAQAAAA==.',
Bi='Biancafiamma:BAAANQAECgIIAgAAAA==.Biancaneve:BAAANQAECgcIEwAAAA==.',
Bo='Bombacløt:BAAANQAECgYIEAAAAA==.',
Br='Brastin:BAAANQAECgUIEAAAAA==.Brenell:BAABNQAECoEaAAIDAAcKtBY+xADYAQADAAcKtBY+xADYAQAAAA==.Brixscen:BAAANQAECgQIBAAAAA==.',
Bu='Bubblehearth:BAAANQAECgEIAQABNQAFFAUIDgAKAF4FAA==.',
Ca='Cabëla:BAAANQAECgQIBQABNQAECgUICgABAAAAAA==.Caineicefall:BAAANQADCgcIBwAAAA==.Calacolinda:BAAANQAECgQIEQAAAA==.',
Ce='Celestiall:BAAANQAECgUIBQAAAA==.Ceridwyn:BAAANQADCgcIEgAAAA==.',
Ch='Chadalonius:BAAANQADCgQIBAABNQAFFAQICAALAPINAA==.Cheesecurd:BAAANQAECgIIAgAAAA==.Choal:BAAANQADCgYICwAAAA==.',
Cl='Claytonbigsb:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.',
Co='Corahin:BAAANQAECgQIBAAAAA==.',
Cu='Cuecumba:BAAANQAECgUICQAAAA==.',
Cy='Cynndi:BAAANQABCgYIBgAAAA==.',
Da='Dalren:BAACNQAFFIEJAAIMAAQKgBAxBgAnAQAMAAQKgBAxBgAnAQA1AAQKgTYAAwwACQprHxIFADEDAAwACQpXHxIFADEDAA0AAgpnHU4YAIoAAAAA.Dalvix:BAAANQAECgIIAwABNQAECgYIEwABAAAAAA==.Dammedude:BAAANQABCgMIAwAAAA==.Dartagnan:BAABNQAECoEWAAIOAAcKnhNZiQDHAQAOAAcKnhNZiQDHAQAAAA==.Darthmaul:BAABNQAECoEdAAIPAAgKmw2UQwC5AQAPAAgKmw2UQwC5AQAAAA==.Daveykrook:BAAANQAECgIIAQABNQAECgUIEQABAAAAAA==.David:BAAANQAECgUICwAAAA==.',
De='Dendiian:BAAANQADCgYICQAAAA==.Depletor:BAABNQAECoEeAAMIAAgK4Ac/pQCUAQAIAAgK4Ac/pQCUAQAQAAMK4wLWNABWAAAAAA==.',
Di='Diem:BAAANQAECgIIBAAAAA==.Dirtydotss:BAAANQAECgEIAQAAAA==.',
Do='Docholiday:BAAANQAECgYIDwAAAA==.Docsassist:BAAANQAECgUICgAAAA==.Dowedoes:BAABNQAECoEkAAIJAAgKDwoiqwCRAQAJAAgKDwoiqwCRAQAAAA==.',
Dr='Drachula:BAAANQAECgQICAAAAA==.Dracultra:BAAANQADCgYIBgABNQAECgcIEwABAAAAAA==.Draeun:BAAANQAECgEIAQABNQAFFAQICQAMAIAQAA==.Dreolan:BAAANQAECgcIDgAAAA==.Druaga:BAAANQAECggIEAAAAA==.Dràchula:BAAANQADCgYICQAAAA==.Dràúgr:BAAANQADCgMIAwAAAA==.',
Dy='Dyala:BAABNQAECoEaAAIRAAgKYBzQEwCMAgARAAgKYBzQEwCMAgAAAA==.',
Dz='Dzznuts:BAAANQABCgYICgAAAA==.',
['Dé']='Démonléth:BAAANQAECgIIAgABNQAECgkJJAASAO8XAA==.',
['Dö']='Dönövan:BAAANQAECgYIEAAAAA==.',
Eg='Eggyolk:BAABNQAECoEWAAITAAgKCxd8EAAZAgATAAgKCxd8EAAZAgAAAA==.',
El='Elastwo:BAAANQADCgcIFgAAAA==.Eloise:BAAANQAECgEIAQAAAA==.Elvenbane:BAABNQAECoEkAAMUAAgKVhEFJADpAQAUAAgKVhEFJADpAQAVAAgKmgJKjAA3AQAAAA==.',
Eu='Eunliza:BAAANQAECggICAAAAA==.',
Ew='Ew:BAACNQAFFIEQAAMOAAYKsRVxAwAKAgAOAAYKsRVxAwAKAgAWAAEKyAeNHwBEAAA1AAQKgSwAAw4ACQoEIo8PAFMDAA4ACQoEIo8PAFMDABYABwqpGewuAK4BAAE1AAQKCQokAAcAUyEA.',
Ex='Extrathick:BAAANQAECgEIAQAAAA==.',
Fa='Fathershale:BAAANQADCgYIDQAAAA==.',
Fe='Fedupdk:BAAANQADCgYICwAAAA==.Feet:BAAANQAECgUIBgAAAA==.Felidae:BAEANQADCgcIHAAAAA==.',
Fi='Firedancer:BAAANQAECgIIAwAAAA==.Fizzfiend:BAAANQADCggIDQAAAA==.',
Fo='Foulcor:BAAANQAECgIIAgABNQAECgUICwABAAAAAA==.',
Fr='Freakadeek:BAAANQAECgIIBQABNQAECgYIDwABAAAAAA==.Freâkadeek:BAAANQADCgQIBAABNQAECgYIDwABAAAAAA==.Frieren:BAAANQAECgcIDwAAAA==.Frëak:BAAANQADCgUIBgABNQAECgYIDwABAAAAAA==.',
Ga='Gabbyo:BAAANQAECgUIDAAAAA==.Galadorn:BAAANQAECgYIEwAAAA==.',
Ge='Genasis:BAAANQABCgMIBQAAAA==.Gerdash:BAAANQAECgYIEwAAAA==.Gerred:BAABNQAECoEjAAIIAAgK3BkjZQBAAgAIAAgK3BkjZQBAAgAAAA==.',
Gh='Ghallow:BAAANQADCgcIDAAAAA==.Ghosthowl:BAAANQAECgUIDAAAAA==.',
Go='Goldenflame:BAAANQAECgIIAwAAAA==.Goldenlight:BAABNQAECoEmAAIVAAkK3xAcTAAYAgAVAAkK3xAcTAAYAgAAAA==.Goldenmunc:BAAANQADCgIIAgAAAA==.Goldenone:BAAANQAECgQIBgAAAA==.Goldenpants:BAAANQADCggIDwAAAA==.',
Gr='Grandesaxx:BAAANQAECgQICAAAAA==.Grievous:BAABNQAECoEkAAIXAAgK5iW+AQBuAwAXAAgK5iW+AQBuAwAAAA==.',
Ha='Hailmary:BAAANQAECgUICgAAAA==.Hakudoshi:BAAANQAECgMIAwAAAA==.Harmanee:BAAANQADCgYIBgAAAA==.Hauser:BAABNQAECoEeAAIJAAgKch2gTACHAgAJAAgKch2gTACHAgAAAA==.',
He='Healaga:BAAANQAECgUIBwABNQAECgYIDgABAAAAAA==.Heinrich:BAAANQADCgMIAwAAAA==.',
Hh='Hhoonnzz:BAAANQADCgYIBgABNQAECgkKJAAHAFMhAA==.',
Ho='Hornreaper:BAABNQAECoEbAAQYAAcKoQn6KABGAQAYAAcKoQn6KABGAQANAAUK5xGxEAAAAQAMAAEK4AJbPAApAAAAAA==.',
Hu='Hubbabubbajr:BAAANQAECgUICgAAAA==.',
Il='Ilavengu:BAAANQAECgEIAQABNQAFFAQIBwAUALEVAA==.',
Is='Isochu:BAAANQADCgMJAwAAAA==.',
Ja='Jayonor:BAABNQAECoEhAAMZAAgKdBl2PwBNAgAZAAgKdBl2PwBNAgAaAAEKwQDoHQEWAAAAAA==.',
Je='Jek:BAAANQADCgEIAQAAAA==.',
Ju='Judgethis:BAAANQABCgIIAgAAAA==.Juicycucci:BAAANQADCgYIBgABNQAFFAUIDgAKAF4FAA==.',
Ka='Kaevrielle:BAEANQAECgcIEAAAAA==.Kaidrosa:BAAANQADCggIFwAAAA==.Kainicefall:BAAANQAECgUIBgAAAA==.Kainicefell:BAAANQAECgIIAgAAAA==.Kainoficefal:BAAANQAECgUIBgAAAA==.Kaladîn:BAAANQAECgEIAQABNQAFFAYIEAACAGYaAA==.Kalokako:BAAANQADCgEIAQAAAA==.Kamel:BAAANQABCgQIBQAAAA==.Karwin:BAAANQAECgYICwAAAA==.',
Ke='Keeper:BAAANQAECgcIBwABNQAECgkJKwAJACslAA==.Keeperodark:BAABNQAECoEWAAIFAAkKSRAYWAAtAgAFAAkKSRAYWAAtAgABNQAECgkJKwAJACslAA==.Keeperolight:BAABNQAECoErAAIJAAkKKyVpBQDGAwAJAAkKKyVpBQDGAwAAAA==.',
Ki='Kifo:BAAANQADCggIDQABNQAECgQIBgABAAAAAA==.Killkat:BAAANQAECgUICgAAAA==.',
Ko='Koojo:BAAANQAECgUIDgAAAA==.',
La='Lans:BAAANQAECgIIAgAAAA==.Larew:BAAANQAECgQIBgAAAA==.',
Le='Lealla:BAABNQAECoEjAAIPAAgKWRu3JwB1AgAPAAgKWRu3JwB1AgAAAA==.Leodin:BAAANQADCgYIBgAAAA==.Lethhunt:BAAANQAECgEIAQABNQAECgkJJAASAO8XAA==.Letholas:BAABNQAECoEkAAQSAAkK7xdOKAAjAgASAAgKlhlOKAAjAgAHAAcKuRTxUwCaAQAbAAEKpwlUwwApAAAAAA==.',
Li='Lightmàiden:BAAANQADCgEIAQAAAA==.Lilkingpunch:BAAANQADCgYIBgABNQAECgkJPwAcAEwhAA==.Lizardgang:BAAANQAECgMIBAAAAA==.',
Lo='Loganshu:BAAANQADCgYIBgAAAA==.Lokan:BAABNQAECoEYAAMOAAgKHBsIQQCDAgAOAAgKdBoIQQCDAgAdAAUKaxIPCwAYAQAAAA==.Lots:BAABNQAECoEfAAMFAAgKvCKKSgBVAgAFAAYKaiOKSgBVAgAGAAIKtCA7PgC+AAAAAA==.',
Lu='Ludakris:BAAANQAECgUICgAAAA==.',
['Lí']='Líonheart:BAAANQAECgIIBAAAAA==.',
Ma='Maami:BAAANQAECgYICwAAAA==.Machognome:BAAANQADCgQIBAAAAA==.Mahina:BAAANQAECgUICgAAAA==.Marcille:BAAANQAECgcJDgAAAA==.Mattix:BAAANQADCggICAAAAA==.Matíx:BAAANQAECgUIEQAAAA==.Mayhaps:BAABNQAECoEcAAMOAAgKogxadQD3AQAOAAgKogxadQD3AQAWAAEKgwCwjAAWAAAAAA==.',
Me='Mentaltitty:BAAANQAECgQICwAAAA==.',
Mi='Milhouse:BAABNQAECoEkAAIbAAgKIiLXFADwAgAbAAgKIiLXFADwAgAAAA==.Minerwor:BAAANQADCggIDgAAAA==.Miooh:BAAANQADCgcIGQAAAA==.Mirrayla:BAAANQADCgEIAQAAAA==.Misty:BAAANQADCggIDwAAAA==.',
Mm='Mmisty:BAAANQAECgUIDAAAAA==.',
Mo='Momometaru:BAABNQAECoEZAAQGAAcKMxOALwAAAQAFAAcKbQ/UggCyAQAGAAQKuBKALwAAAQAEAAIKcQs6IwBOAAABNQAECgcIHgAPAIsVAA==.Monsterbee:BAABNQAECoElAAIFAAgKHxaRVAA3AgAFAAgKHxaRVAA3AgAAAA==.Morne:BAAANQADCgYIBgAAAA==.',
Mu='Mustypizza:BAAANQAECgUICgAAAA==.',
My='Mystery:BAABNQAECoEkAAIYAAgKRRxADwChAgAYAAgKRRxADwChAgAAAA==.',
Na='Nats:BAAANQAECgcIEAAAAA==.',
Ne='Neameny:BAABNQAECoEkAAIOAAgKcg1KcAADAgAOAAgKcg1KcAADAgAAAA==.',
Ni='Nightstar:BAAANQADCgYIBgAAAA==.',
Nu='Nualrossan:BAAANQADCgEIAQAAAA==.Nubrac:BAAANQAECgUICQAAAA==.',
Ob='Oblivion:BAABNQAECoElAAMFAAgKfSMsFQAiAwAFAAgKfSMsFQAiAwAGAAIK0BSKUQB+AAAAAA==.',
Om='Omey:BAAANQAECgUICQAAAA==.',
Pa='Pallyshore:BAAANQADCggICAAAAA==.Papichuló:BAAANQADCgMIBgABNQAECgYIDwABAAAAAA==.',
Pi='Pixae:BAAANQAECgUICgAAAA==.',
Po='Portknight:BAAANQADCgcIBwAAAA==.Potatochip:BAAANQAECgIIAgAAAA==.Powerplant:BAACNQAFFIEHAAIOAAQK/hvaCgBuAQAOAAQK/hvaCgBuAQA1AAQKgScAAg4ACQo5IagTADkDAA4ACQo5IagTADkDAAAA.',
Py='Pyralys:BAABNQAECoEiAAIVAAgKmg9+XADcAQAVAAgKmg9+XADcAQAAAA==.',
['Pâ']='Pârtyrockêr:BAAANQADCgUIBwABNQAECgYIDwABAAAAAA==.',
Ra='Raelene:BAAANQADCgYICQAAAA==.Ragedk:BAAANQAECgIIAwABNQAECgcIBwABAAAAAA==.Ragenbefcake:BAAANQADCggICwAAAA==.Ragetality:BAAANQAECgcIBwAAAA==.Rallaster:BAAANQAECgUICQABNQAECggIJAAUAFYRAA==.Rampage:BAAANQABCgUIAgAAAA==.Raserei:BAABNQAECoEdAAMeAAgKPR7sBQCNAgAeAAgKax3sBQCNAgAIAAEKqBr7JAFPAAAAAA==.Rawb:BAAANQAECgYJCgABNQAECgkKJAAHAFMhAA==.',
Re='Recolada:BAAANQADCgcJDAAAAA==.Regicee:BAAANQAECgYIEQAAAA==.',
Ri='Riffraff:BAAANQADCggICgAAAA==.',
Ro='Rockdyou:BAAANQAECgUIBgAAAA==.Rotlobster:BAABNQAECoEeAAIEAAkKiiLmAABmAwAEAAkKiiLmAABmAwABNQAECgkJLAAfAPEgAA==.',
Ru='Rudal:BAAANQADCgIIAgAAAA==.Rundvelt:BAAANQADCgIIAgAAAA==.',
Ry='Rydiaicefall:BAAANQAECgMIAwAAAA==.',
Se='Selina:BAAANQAECgQIBAAAAA==.Serdwarf:BAAANQAECgYICwAAAA==.Sertian:BAAANQADCgQIBAAAAA==.',
Sh='Shatha:BAAANQADCgQIBQAAAA==.Sherten:BAAANQAECgIJAgAAAA==.Shooturiout:BAAANQAECgMIAwAAAA==.Shtanky:BAAANQAECgcIEgAAAA==.',
Si='Sixsixsix:BAAANQADCggJCgABNQAECgkKJAAHAFMhAA==.',
Sk='Sketch:BAAANQAECgIIAgABNQAFFAYIEQATAGEVAA==.Skoogz:BAAANQAECgQIBAAAAA==.',
So='Sogsy:BAAANQAECgUIDgAAAA==.Soleri:BAAANQAECgQIBAAAAA==.Soulfulgingr:BAAANQAECgIIAgAAAA==.',
St='Styx:BAAANQAECgQIBAAAAA==.Stza:BAAANQABCgYICAAAAA==.',
Su='Sunbake:BAAANQAECgQIBgAAAA==.',
Sw='Sweetbbyraze:BAACNQAFFIEIAAIMAAUKkg3hBABgAQAMAAUKkg3hBABgAQA1AAQKgR4AAgwACQomHwYIAOUCAAwACQomHwYIAOUCAAAA.',
['Sí']='Sín:BAAANQADCgIJAgABNQAECgkKJAAHAFMhAA==.',
Ta='Talipally:BAAANQAECgcIEgAAAA==.Taliwhacker:BAAANQADCgMIAwABNQAECgcIEgABAAAAAA==.Talonleafgrd:BAABNQAECoEUAAIWAAYKGhWnMgCOAQAWAAYKGhWnMgCOAQAAAA==.Tandsonna:BAAANQAECgUIBQAAAA==.Tanisong:BAAANQADCgUICQAAAA==.',
Te='Terayus:BAAANQADCgIJAgAAAA==.Terraform:BAAANQADCgYICwAAAA==.',
Th='Thalor:BAAANQAECgYIDAABNQAFFAYIDQAgAMMWAA==.Thekingpunch:BAABNQAECoE/AAIcAAkKTCFRBABOAwAcAAkKTCFRBABOAwAAAA==.Thenle:BAAANQAECgEIAQAAAA==.Theworst:BAAANQAECgYIBgABNQAECgkKJAAHAFMhAA==.',
Ti='Tillwar:BAABNQAECoEkAAIIAAgKmhTxcgAaAgAIAAgKmhTxcgAaAgAAAA==.Tiàna:BAAANQADCgEIAQAAAA==.',
To='Tofu:BAAANQAECgcIEwAAAA==.Tortillachip:BAAANQADCgYIBgAAAA==.',
Tr='Treibh:BAABNQAECoEdAAIRAAgKrReAHAAlAgARAAgKrReAHAAlAgAAAA==.Trulydps:BAAANQAECgYIDQAAAA==.',
Tu='Tust:BAAANQAECgQIBQABNQADCgQIBAABAAAAAA==.',
Ty='Tymora:BAAANQADCggICAABNQAECggIJAAUAFYRAA==.',
['Të']='Tërris:BAAANQAECgUIEgAAAA==.',
['Tî']='Tîlldeath:BAAANQAECgUIBQAAAA==.',
Un='Undzl:BAACNQAFFIEGAAMSAAIKox/jDQCuAAASAAIKox/jDQCuAAAHAAEKcgZ4IAA4AAA1AAQKgS8AAwcACQo8JPYHAHEDAAcACQpXI/YHAHEDABIACAqlIRkSAN4CAAAA.Unknowna:BAAANQADCgYIBgAAAA==.',
Ur='Urowndad:BAAANQADCgIIAgABNQAECgUICQABAAAAAA==.',
Va='Vallez:BAEBNQAECoEeAAMhAAgKuyWjCgBlAwAhAAgKuyWjCgBlAwAJAAEKjgtNfAEwAAAAAA==.Varnusshadow:BAAANQAECgIIBAAAAA==.Vayn:BAAANQAECgUICQAAAA==.',
Ve='Velladoree:BAAANQAECgIJAgAAAA==.Vexahlia:BAAANQAECggICwAAAA==.',
Vy='Vyrable:BAAANQAECgcIDQAAAA==.',
Wa='Waveygravee:BAAANQADCgcJCwAAAA==.Wavygraivy:BAAANQAECgQIBgAAAA==.',
We='Wedragon:BAAANQAECgQIBQAAAA==.',
Wo='Woofwoof:BAAANQAECgIIBAAAAA==.Wooshh:BAAANQAECgUIDQAAAA==.',
Xh='Xhexana:BAAANQAECgUIEgABNQAECggIJAAOAHINAA==.',
Xi='Xianofukuju:BAABNQAECoEeAAIPAAcKixWYPwDTAQAPAAcKixWYPwDTAQAAAA==.',
Xr='Xrayl:BAABNQAECoElAAMiAAkKShz6CQBcAgAiAAgKoBv6CQBcAgAgAAYKxhk0LgBzAQAAAA==.',
Xz='Xzerocool:BAAANQAECgUICQAAAA==.',
Yo='Yoshikazu:BAAANQAECgIIAgAAAA==.',
Za='Zaarah:BAAANQADCgUIDwAAAA==.',
Ze='Zendezoth:BAAANQAECgYICgAAAA==.Zevthekuatin:BAAANQAECgUIDQAAAA==.',
Zh='Zhiva:BAAANQAECgUICAAAAA==.',
Zy='Zykoz:BAAANQAECgUICgAAAA==.',
['Åy']='Åyna:BAAANQADCgcIEQAAAA==.',
['Ða']='Ðaddy:BAAANQAECgYICwAAAA==.Ðamned:BAAANQAECgUICAABNQAECgkKJAAHAFMhAA==.',
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
