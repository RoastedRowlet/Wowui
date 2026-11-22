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

local lookup = {'Paladin-Retribution','Hunter-Marksmanship','Shaman-Elemental','Shaman-Restoration','Unknown-Unknown','Evoker-Devastation','Paladin-Holy','DemonHunter-Havoc','Warrior-Arms','Warrior-Protection','DeathKnight-Unholy','Warrior-Fury','Paladin-Protection','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Vengeance','Mage-Arcane','Mage-Frost','DeathKnight-Blood','Druid-Balance','Priest-Holy','Priest-Discipline','Hunter-BeastMastery','Monk-Mistweaver','Druid-Guardian','Druid-Feral','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','DemonHunter-Devourer','Monk-Windwalker','Warlock-Affliction','Warlock-Demonology','DeathKnight-Frost','Druid-Restoration','Priest-Shadow',}
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abrams:BAABNQAECn8VAAIBAAcKGQ0wCQEPAQABAAcKGQ0wCQEPAQAAAA==.',
Ad='Addý:BAAANQAECggIDwAAAA==.',
Ae='Aethyra:BAAANQAECgYICQAAAA==.',
Ah='Ahimsa:BAABNQAECn8vAAICAAoKuhNrFQDvAQACAAoKuhNrFQDvAQAAAA==.',
Ai='Ailisuuith:BAABNQAECn8aAAMDAAkKlRGZyQD/AAADAAcKug2ZyQD/AAAEAAYKtQX/4wCiAAAAAA==.',
Al='Alkyri:BAAANQADCgMIAwAAAA==.Almamun:BAAANQADCgcIDwAAAA==.',
Ar='Arcanemommy:BAAANQAECgEIAQAAAA==.Arcz:BAAANQAECgcIDgABNQAECggICwAFAAAAAA==.',
As='Ashenclaw:BAACNQAFFH8GAAIGAAMK9w8QBgB5AAAGAAMK9w8QBgB5AAA1AAQKf0gAAgYACgoYGXwGAEECAAYACgoYGXwGAEECAAAA.',
At='Athalena:BAAANQAECgQIBgABNQAECgoKOwAHAGAUAA==.',
Au='Auzatryx:BAAANQAECgUIBQAAAA==.',
Ba='Babs:BAAANQABCgIIAgABNQAECggIHQAIAIoLAA==.Babyboo:BAAANQADCgcIFAAAAA==.Bamboom:BAAANQAECgEIAwAAAA==.',
Bi='Biggrnmonstr:BAABNQAECn8sAAMJAAkKlRFAiQBxAQAJAAkKTRBAiQBxAQAKAAEKdRb6QwAyAAABNQAECgoKTAALADMfAA==.Bigxthezug:BAABNQAECn8bAAMDAAkKxh2SMwCrAgADAAkKxh2SMwCrAgAEAAMKowWu9wB7AAAAAA==.',
Bl='Blaine:BAAANQADCgcIEgAAAA==.',
Bo='Bongripa:BAAANQABCgEIAQAAAA==.Bonquiqui:BAAANQADCgcIDAAAAA==.Boypartz:BAABNQAECn81AAIJAAoK5BmwQgA5AgAJAAoK5BmwQgA5AgAAAA==.',
Br='Braidedbewbs:BAAANQAECgEIAQAAAA==.Breakfast:BAAANQADCgMIAwABNQAECgkJGwADAMYdAA==.Brittinia:BAAANQAECgIIBAAAAA==.',
Bu='Bulbasaurus:BAACNQAFFH8JAAIMAAcKoiNnAAB5AQAMAAcKoiNnAAB5AQA1AAQKf0IAAgwACgqYJjwAAPQDAAwACgqYJjwAAPQDAAAA.Bumbata:BAAANQAECgMICgAAAA==.Bus:BAACNQAFFH82AAINAAoKYCIOAABgAwANAAoKYCIOAABgAwA1AAQKf0MAAg0ACgoEJwMAAKwDAA0ACgoEJwMAAKwDAAAA.',
By='Bylunn:BAAANQADCgEIAQAAAA==.',
Ca='Cactusjuicee:BAAANQAECgEIAQAAAA==.',
Ce='Celeres:BAACNQAFFH8FAAIOAAIK9wsyFACDAAAOAAIK9wsyFACDAAA1AAQKf1kAAw4ACgpLGy0NANMCAA4ACgpLGy0NANMCAA8ABwrzBe0PAOIAAAAA.Celesdria:BAAANQADCgMIAwABNQAFFAIIBQAOAPcLAA==.Celys:BAAANQADCgIIAgAAAA==.Ceo:BAABNQAECn8gAAMHAAoK9h/JMQBYAgAHAAoK9h/JMQBYAgANAAUKCQ/VQwDjAAAAAA==.',
Ch='Channie:BAAANQABCgMIAwAAAA==.Chios:BAAANQAECgcIBwABNQABCgIIAwAFAAAAAA==.',
Da='Darkeblood:BAAANQAECgEIAQAAAA==.',
De='Deadcell:BAABNQAECn8iAAMQAAkKlRl1CADzAQAQAAkKlRl1CADzAQAIAAMKnAzWdQCiAAAAAA==.Denamage:BAACNQAFFH8bAAMRAAcKXAswEgBoAQARAAcKXAswEgBoAQASAAEKuwQ7FgA8AAA1AAQKfywAAxEACgoAGSF/AIACABEACgoAGSF/AIACABIABQoiCS8nALkAAAAA.Denarrage:BAAANQAFFAEIAQAAAA==.',
Di='Disconnect:BAAANQABCgIJAwAAAA==.',
Do='Dokuganryu:BAAANQADCgIIAgABNQAECgoKMwATAAMmAA==.Dontnerfspls:BAAANQAECgIIAgABNQAECgoKTAALADMfAA==.Donzul:BAAANQADCgUIBQAAAA==.Doomtickle:BAAANQADCgYIBgAAAA==.',
Ea='Earthigga:BAAANQAECggIDwAAAA==.',
Ei='Eichmann:BAAANQAECgIIAgAAAA==.',
El='Eldruida:BAACNQAFFH8JAAIUAAIKZAytHACEAAAUAAIKZAytHACEAAA1AAQKf0QAAhQACgofGSgbAC8CABQACgofGSgbAC8CAAAA.Elixxi:BAAANQADCgYIBgAAAA==.Ellipsoro:BAABNQAECn8lAAILAAgKXxs7JQC2AQALAAgKXxs7JQC2AQAAAA==.Eltrol:BAAANQAECgIIAwAAAA==.',
En='Enoc:BAAANQAECgQIBwAAAA==.',
Er='Erale:BAAANQAECgEIAgAAAA==.',
Fa='Faeris:BAACNQAFFH8IAAIVAAUKEg1oFABkAQAVAAUKEg1oFABkAQA1AAQKfyQAAxUACgp1H1odAPwCABUACgp1H1odAPwCABYABAq/GZIPADIBAAAA.Fakecheese:BAAANQAECgEIAQABNQAECgoKMAABAOQUAA==.Fatalis:BAACNQAFFH8QAAMXAAUKVwsdGAD6AAAXAAUKVwsdGAD6AAACAAEKAAAZKQAeAAA1AAQKf1cAAxcACgplH/sbANICABcACgplH/sbANICAAIAAQoAAJaYACgAAAAA.',
Fe='Fedqt:BAAANQAECgIIBAAAAA==.Felko:BAABNQAECn8YAAMHAAkKjhn3JwCMAgAHAAkKjhn3JwCMAgABAAYKNBFyygBBAQAAAA==.',
Fi='Fiestykitten:BAAANQAECgEIAQAAAA==.Fizaw:BAABNQAECn8zAAIYAAoKwQ2XGwDJAQAYAAoKwQ2XGwDJAQAAAA==.',
Fl='Floydmagussy:BAACNQAFFH8MAAIRAAUKESACGQCxAQARAAUKESACGQCxAQA1AAQKfx8AAhEACQphI2Y3ABoDABEACQphI2Y3ABoDAAAA.',
Fo='Foamdk:BAAANQADCggICwAAAA==.',
Fr='Freezypuff:BAAANQAECgUIBgAAAA==.Frostee:BAAANQAECgEIAQAAAA==.Frøzen:BAABNQAECn8XAAIRAAUKbQWpbAHhAAARAAUKbQWpbAHhAAAAAA==.',
Fu='Fuzzydots:BAAANQAECgQIBAABNQAECgoKRwABALEhAA==.',
Ga='Gamu:BAAANQADCgMIAwAAAA==.Gaurr:BAABNQAECn8sAAIDAAoK0BNqbADbAQADAAoK0BNqbADbAQAAAA==.',
Ge='Genevah:BAAANQADCgUIBQAAAA==.Geneviere:BAAANQADCgMIAwAAAA==.',
Gi='Gianna:BAAANQAECgYICQAAAA==.Gislain:BAAANQADCgcIDQAAAA==.',
Go='Goldeye:BAAANQADCgYIEwAAAA==.',
Gr='Greyspirit:BAABNQAECn9HAAIZAAoKeSPLAwAvAwAZAAoKeSPLAwAvAwAAAA==.Grimothy:BAABNQAECn8yAAMEAAoKMRnkHgDEAgAEAAoKMRnkHgDEAgADAAgKOwxviAD8AAAAAA==.',
Gu='Gulohof:BAAANQADCgEIAQAAAA==.',
Ha='Halcoldrek:BAAANQADCgQJBAAAAA==.',
Hb='Hbc:BAACNQAFFH8PAAIZAAYKERxrAQBWAQAZAAYKERxrAQBWAQA1AAQKfxsAAxkACgrBIVoGAO4CABkACgqWIVoGAO4CABoAAgopHtUqALAAAAE1AAEKAggDAAUAAAAA.',
He='Healarious:BAABNQAECn8bAAIVAAcKtRYbawCcAQAVAAcKtRYbawCcAQAAAA==.Hembrota:BAAANQADCgcIEgAAAA==.Heyz:BAAANQAECggICwAAAA==.',
Hi='Himbo:BAABNQAECn8eAAIXAAcKrAcf0QBeAQAXAAcKrAcf0QBeAQAAAA==.',
Ho='Hogs:BAAANQAECgQIDgABNQAECgkJGwADAMYdAA==.Holypoopp:BAABNQAECn8wAAMHAAoK0B2dJQDUAgAHAAoK0B2dJQDUAgABAAkKFwtwvABZAQAAAA==.Holyreturn:BAABNQAECn9MAAIHAAoKsiKfBQDDAwAHAAoKsiKfBQDDAwAAAA==.',
Hu='Hunttigga:BAAANQAECgQIBgAAAA==.',
Hw='Hwasin:BAAANQAECgQIBAABNQAECggICwAFAAAAAA==.',
Il='Illanyth:BAAANQADCgUIBQAAAA==.Illidaldin:BAAANQADCgYIBgABNQAECgoKKwAbALoXAA==.',
Im='Imran:BAACNQAFFH8MAAINAAMK4xsYCADjAAANAAMK4xsYCADjAAA1AAQKf0wAAg0ACgo7IrkFAFIDAA0ACgo7IrkFAFIDAAAA.',
In='Inthelayer:BAAANQADCgYIBgABNQAECgkJGwADAMYdAA==.',
Ja='Janny:BAAANQABCgQIBAAAAA==.',
Je='Jether:BAAANQAECgEIAQAAAA==.',
Jo='Jojobaggins:BAABNQAECn9HAAQcAAoK5CDZFgDGAgAcAAoKJCDZFgDGAgAdAAgK5B46FwDCAgAeAAQKzxXIEAANAQAAAA==.',
Ka='Kaadriluna:BAAANQADCgEIAQAAAA==.',
Kc='Kcthegreat:BAAANQADCgQIBQAAAA==.',
Ke='Keyholes:BAACNQAFFH8rAAITAAkKCR9SAwBgAgATAAkKCR9SAwBgAgA1AAQKfx8AAhMACQrvIowUAAgDABMACQrvIowUAAgDAAE1AAEKAggDAAUAAAAA.Keyohs:BAAANQADCgcICAABNQABCgIIAwAFAAAAAA==.',
Ki='Kindness:BAAANQADCgUIBQAAAA==.Kirky:BAAANQADCgUIBgAAAA==.',
Kk='Kkoda:BAAANQAECgcICQAAAA==.',
Ko='Koal:BAABNQAECn8oAAIXAAcKoRY4pQC7AQAXAAcKoRY4pQC7AQAAAA==.Kodabear:BAAANQADCggICAAAAA==.',
Kr='Kraz:BAAANQADCgYIBgAAAA==.Kronos:BAAANQADCgYIBgABNQAECgoKHgANAFQRAA==.',
Ku='Kushage:BAAANQADCgMIAwAAAA==.',
['Kí']='Kírky:BAAANQADCgIIAwABNQADCgUIBgAFAAAAAA==.',
Le='Lettussy:BAACNQAFFH8gAAMcAAcK1iJ8BQD0AQAcAAYKzR98BQD0AQAdAAUK+CSCBQDWAQA1AAQKfzsAAx0ACgrhJUwCALsDAB0ACQogJkwCALsDABwACArfJOsQAPACAAAA.',
Li='Lixxi:BAABNQAECn9AAAIVAAoKAx9nJwDNAgAVAAoKAx9nJwDNAgAAAA==.',
Lu='Luminyssa:BAAANQAECgQIBwAAAA==.',
['Lú']='Lúthien:BAAANQAECggIEQAAAA==.',
Ma='Maeby:BAABNQAECn8XAAIJAAkKCxfdPgBHAgAJAAkKCxfdPgBHAgAAAA==.Magicwater:BAACNQAFFH8lAAIRAAcKLyARCgDvAQARAAcKLyARCgDvAQA1AAQKfzwAAhEACgpJJL8dAGEDABEACgpJJL8dAGEDAAAA.Magigga:BAAANQAECggIAwAAAA==.Mallcador:BAAANQADCgQIBAAAAA==.',
Me='Meeoowzer:BAABNQAECn87AAMHAAoKSR3cNgCIAgAHAAoKSR3cNgCIAgANAAEKAAAoggAAAAAAAA==.Meloo:BAABNQAECn8dAAIIAAgKigvPQQAuAQAIAAgKigvPQQAuAQAAAA==.',
Mo='Mokoko:BAABNQAECn8gAAMdAAoKGxhCCQBOAgAdAAoKGxhCCQBOAgAeAAMKFA0eCQBzAAAAAA==.Mollyflo:BAAANQAECgcIDgAAAA==.Mollymauk:BAABNQAECn87AAMHAAoKYBTeZgDjAQAHAAoKYBTeZgDjAQABAAgKig6yrgDCAQAAAA==.Momoka:BAABNQAECn8jAAMBAAoKYRcqSwBJAgABAAoKYRcqSwBJAgANAAIK8AN1XwA/AAAAAA==.Moorality:BAABNQAFFH8OAAINAAUKyxitBAATAQANAAUKyxitBAATAQABNQABCgIIAwAFAAAAAA==.Moretino:BAAANQAECgUIDAAAAA==.Morgane:BAAANQADCgEIAQAAAA==.Mothra:BAABNQAECn8gAAIEAAoKXxK+SQDsAQAEAAoKXxK+SQDsAQABNQAFFAUIEAACALcOAA==.',
Mu='Muhjo:BAAANQADCgYIDQAAAA==.Muppet:BAABNQAECn8UAAIZAAgK6RM5IACaAQAZAAgK6RM5IACaAQAAAA==.Murryjane:BAAANQAECgcIDQABNQAECggICwAFAAAAAA==.Muufarmer:BAAANQAECgYICgAAAA==.',
Na='Natedk:BAAANQAECgYIBgAAAA==.',
Ne='Neyt:BAABNQAECn8wAAMfAAoKkB6LDAAaAwAfAAoKkB6LDAAaAwAIAAMKahGZcQCzAAAAAA==.',
Ni='Nitesrider:BAAANQAECgQIBQAAAA==.',
No='Nora:BAACNQAFFH9IAAMBAAoKNiYOAACWAwABAAoKNiYOAACWAwANAAEKAAAyDgBiAAA1AAQKf0kABAEACgrkJnADAOEDAAEACgrjJnADAOEDAA0ABwqiJgUJAA0DAAcACQotG/c7AHQCAAAA.Nostrodom:BAAANQADCgcIEQAAAA==.',
Nu='Nubbs:BAABNQAECn8VAAIgAAUKpRaDPQAqAQAgAAUKpRaDPQAqAQAAAA==.Nubheala:BAABNQAECn86AAMVAAoKpyNKBgDOAwAVAAoKpyNKBgDOAwAWAAEKvg5CKgAvAAAAAA==.Nuri:BAABNQAECn8yAAIRAAoK1h3tOwAPAwARAAoK1h3tOwAPAwAAAA==.',
Od='Odylight:BAAANQADCggICQAAAA==.',
Or='Orcazmo:BAABNQAECn8uAAMhAAkKhBEzBgARAgAhAAkKhBEzBgARAgAiAAcKQQSI2wASAQAAAA==.',
Pe='Peluij:BAAANQAECgQIBgAAAA==.',
Pi='Pingopango:BAAANQAECgYIDAABNQAECgkJGQAHAMMZAA==.Pinkdefender:BAAANQAECgQIBQABNQAECgoKTAALADMfAA==.Pinpanpum:BAAANQAECgEIAQAAAA==.',
Po='Pokeumon:BAAANQAECgYIBgAAAA==.Poosistrox:BAABNQAECn9MAAQLAAoKMx/7GgDqAgALAAkK7SD7GgDqAgAjAAoKURTMPQCmAQATAAUK8hCSdAAkAQAAAA==.',
Ps='Pspspspsps:BAABNQAECn8WAAIaAAUKzg5DKQC6AAAaAAUKzg5DKQC6AAAAAA==.',
Pt='Ptheve:BAACNQAFFH9AAAIIAAoKSiYZAAB9AwAIAAoKSiYZAAB9AwA1AAQKfzUAAggACgr6Jn4AAJADAAgACgr6Jn4AAJADAAAA.',
Pu='Punipuni:BAAANQABCgIIAgAAAA==.',
Qs='Qsham:BAAANQAECgUICAAAAA==.',
Qw='Qwarlock:BAABNQAECn8/AAMiAAoKJhcnWADMAQAiAAkK5hUnWADMAQAbAAEK5x96LQBMAAAAAA==.',
Ra='Raela:BAACNQAFFH8MAAIjAAUKCROADgDkAAAjAAUKCROADgDkAAA1AAQKfzoAAiMACQqwIrkdAJwCACMACQqwIrkdAJwCAAAA.Rahnarmight:BAAANQADCgMIAwAAAA==.Raygor:BAAANQAECgUIDAAAAA==.Razzle:BAAANQADCgIIAgABNQAECgoKMgARANYdAA==.',
Re='Renewal:BAAANQAECgUIBQAAAA==.',
Ri='Rickthyr:BAAANQAECgUIDAAAAA==.Rigger:BAAANQADCgYJBgABNQAECgQIBQAFAAAAAA==.Rizzerz:BAAANQADCgcIBwAAAA==.',
Ro='Rodgozinya:BAAANQADCggIBwABNQAECgoKNQAJAOQZAA==.Rosewalker:BAAANQAECgYIEAABNQAFFAcIJQARAC8gAA==.Rosewall:BAAANQADCgIIAgABNQAFFAcIJQARAC8gAA==.Rottgut:BAAANQADCgEIAQAAAA==.',
Ru='Rumog:BAAANQAECgUIDAAAAA==.',
Ry='Rykix:BAAANQADCgEIAQAAAA==.Rykò:BAABNQAECn8aAAIXAAYKeBvbkADnAQAXAAYKeBvbkADnAQAAAA==.Rysho:BAAANQADCgYIBQAAAA==.',
['Ré']='Réckléssnéss:BAAANQAECgUIEAAAAA==.',
Sa='Salmorg:BAACNQAFFH8FAAIfAAIKJx2PCgC2AAAfAAIKJx2PCgC2AAA1AAQKf0wAAx8ACgoqI/UFAP8CAB8ACgoqI/UFAP8CAAgACAryHTwqAE8CAAAA.Satinet:BAAANQAECgQIBQAAAA==.Sayafaed:BAABNQAECn8/AAIfAAoKhA9RGwDQAQAfAAoKhA9RGwDQAQAAAA==.',
Sc='Scalen:BAAANQADCgYIBgAAAA==.Scatback:BAABNQAECn84AAIVAAoK0SJICACxAwAVAAoK0SJICACxAwAAAA==.Schwarzmagic:BAAANQAECgEIAQAAAA==.',
Sh='Shilor:BAABNQAECn8xAAMVAAoKahh1KQCmAgAVAAoKVxd1KQCmAgAWAAMKgBUZFwC+AAAAAA==.Shogun:BAAANQAECgQIDgAAAA==.Shortsnack:BAAANQABCgMJAwAAAA==.',
Si='Sicarii:BAAANQAECggIEAAAAA==.Sicarrious:BAAANQADCggIEQABNQAECggIEAAFAAAAAA==.Sinatra:BAABNQAECn9SAAIkAAoKWCM+AwDSAwAkAAoKWCM+AwDSAwAAAA==.',
Sk='Skyarc:BAAANQAECgIIBAABNQAECggIEwAFAAAAAA==.Skybolt:BAAANQAECgIIAgABNQAECggIEwAFAAAAAA==.Skylite:BAAANQAECggIEwAAAA==.Skyrak:BAAANQADCgQIBAABNQAECggIEwAFAAAAAA==.Skyrun:BAAANQAECgMIAQABNQAECggIEwAFAAAAAA==.',
Sn='Sneaksnstabs:BAAANQAECgYIDAABNQAECgoKTAALADMfAA==.',
So='Soulpurge:BAAANQADCgEIAQAAAA==.Soçks:BAAANQAECgEIAQAAAA==.',
Sp='Splat:BAAANQAECgUIBgABNQAECgoKMAAHANAdAA==.Spoopy:BAAANQADCggICAAAAA==.Spënny:BAAANQAECgQIBQAAAA==.',
St='Stélle:BAABNQAECn8yAAICAAoKaQ1ALwDSAQACAAoKaQ1ALwDSAQAAAA==.',
Su='Supdude:BAABNQAECn8+AAIcAAoKzxzmBwD8AgAcAAoKzxzmBwD8AgAAAA==.',
Ta='Tatorz:BAAANQAECgQICAAAAA==.Tazingo:BAAANQAECgQIBgABNQAECgoKMgARANYdAA==.',
Te='Tentacrool:BAAANQABCgEIAQAAAA==.',
Ti='Tigas:BAABNQAECn8pAAMJAAoKSB6mQADIAgAJAAoKSB6mQADIAgAMAAIKUSIBJQCJAAAAAA==.',
To='Tolally:BAACNQAFFH8JAAIfAAUKqA0uBgAKAQAfAAUKqA0uBgAKAQA1AAQKfxgAAh8ACQo3GUgOAHACAB8ACQo3GUgOAHACAAAA.Tooth:BAAANQADCgQIBQAAAA==.',
Tr='Trashdragon:BAABNQAECn8uAAMGAAoK4RqDDACbAgAGAAkKcR6DDACbAgAPAAQKsg4bFQCPAAAAAA==.Trashshaman:BAAANQAECgMIAwAAAA==.Trauma:BAAANQAECgYIBwAAAA==.',
Tu='Turtlebear:BAAANQADCgIIAgABNQAECgUIBgAFAAAAAA==.',
Ty='Typhoonz:BAAANQADCgYIBgAAAA==.',
Ur='Uróboros:BAAANQADCgEIAQAAAA==.',
Vi='Vipex:BAAANQAECgIIAwAAAA==.',
Vy='Vynii:BAABNQAECn85AAMIAAoKEhgBGwA5AgAIAAoKEhgBGwA5AgAfAAIK9gODZQBTAAAAAA==.',
Wa='Wallofstars:BAAANQADCgQIBQAAAA==.Wardamage:BAAANQABCgEIAQAAAA==.Wasabi:BAABNQAECn8eAAIOAAcKJBnZFgCIAQAOAAcKJBnZFgCIAQAAAA==.',
We='Wey:BAABNQAECn8bAAMVAAkKWhGSYwC1AQAVAAgKZBCSYwC1AQAlAAYK3A/PKgAvAQAAAA==.',
Wo='Wonon:BAAANQAECgEIAQAAAA==.',
Xa='Xaida:BAAANQAECgYICgABNQAFFAoKRQAOAEEUAA==.Xalant:BAAANQADCggICQAAAA==.',
Yo='Yourhammy:BAAANQADCgMIAwAAAA==.Yoyo:BAAANQAECgIIAgAAAA==.',
Yt='Ytteriul:BAAANQADCgYIEgAAAA==.',
Za='Zangyaku:BAABNQAECn8zAAITAAoKAyblBwAKAwATAAoKAyblBwAKAwAAAA==.Zanmetsu:BAAANQAECgUIBQABNQAECgoKMwATAAMmAA==.',
Ze='Zenis:BAABNQAECn8ZAAIHAAkKwxnAJgDOAgAHAAkKwxnAJgDOAgAAAA==.Zerocool:BAAANQADCgYIBgAAAA==.Zerø:BAAANQADCgIIAgAAAA==.Zetsuï:BAAANQAECgcIEwAAAA==.',
['ßa']='ßadfish:BAABNQAECn8hAAIBAAoKDSOfDgCSAwABAAoKDSOfDgCSAwAAAA==.',
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
