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

local lookup = {'Hunter-Marksmanship','Shaman-Elemental','Shaman-Restoration','Unknown-Unknown','Evoker-Devastation','Paladin-Holy','DemonHunter-Havoc','Warrior-Arms','Warrior-Protection','DeathKnight-Unholy','Warrior-Fury','Paladin-Protection','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Vengeance','Mage-Arcane','Mage-Frost','DeathKnight-Blood','Druid-Balance','Priest-Holy','Priest-Discipline','Paladin-Retribution','Hunter-BeastMastery','Monk-Mistweaver','Druid-Guardian','Druid-Feral','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','DemonHunter-Devourer','Monk-Windwalker','Warlock-Affliction','Warlock-Demonology','DeathKnight-Frost','Druid-Restoration',}
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abrams:BAAANQAECgYIEAAAAA==.',
Ad='Addý:BAAANQAECggIDwAAAA==.',
Ae='Aethyra:BAAANQAECgUICQAAAA==.',
Ah='Ahimsa:BAABNQAECn8rAAIBAAoK4RFVEwDVAQABAAoK4RFVEwDVAQAAAA==.',
Ai='Ailisuuith:BAABNQAECn8aAAMCAAkKkxGZyQD/AAACAAcKuA2ZyQD/AAADAAYKtQX/4wCiAAAAAA==.',
Al='Alkyri:BAAANQADCgMIAwAAAA==.Almamun:BAAANQADCgcIDwAAAA==.',
Ar='Arcanemommy:BAAANQAECgEIAQAAAA==.Arcz:BAAANQAECgcIDgABNQAECggICwAEAAAAAA==.',
As='Ashenclaw:BAACNQAFFH8GAAIFAAMK9w/jBACCAAAFAAMK9w/jBACCAAA1AAQKf0gAAgUACgoYGTMFAEYCAAUACgoYGTMFAEYCAAAA.',
At='Athalena:BAAANQAECgQIBgABNQAECgkJOgAGACUTAA==.',
Au='Auzatryx:BAAANQAECgUIBQAAAA==.',
Ba='Babs:BAAANQABCgIIAgABNQAECggIHQAHAIoLAA==.Babyboo:BAAANQADCgcIFAAAAA==.Bamboom:BAAANQAECgEIAwAAAA==.',
Bi='Biggrnmonstr:BAABNQAECn8jAAMIAAkKtQ5EgQBNAQAIAAkKbQ1EgQBNAQAJAAEKdRb6QwAyAAABNQAECgoKRQAKADMfAA==.Bigxthezug:BAABNQAECn8bAAMCAAkKxh2SMwCrAgACAAkKxh2SMwCrAgADAAMKowWu9wB7AAAAAA==.',
Bl='Blaine:BAAANQADCgcIEgAAAA==.',
Bo='Bongripa:BAAANQABCgEIAQAAAA==.Bonquiqui:BAAANQADCgcIDAAAAA==.Boypartz:BAABNQAECn81AAIIAAoK5BmxNABEAgAIAAoK5BmxNABEAgAAAA==.',
Br='Braidedbewbs:BAAANQAECgEIAQAAAA==.Breakfast:BAAANQADCgMIAwABNQAECgkJGwACAMYdAA==.Brittinia:BAAANQAECgIIBAAAAA==.',
Bu='Bulbasaurus:BAACNQAFFH8JAAILAAcKoiM8AACHAQALAAcKoiM8AACHAQA1AAQKfz4AAgsACgqXJjwAAPQDAAsACgqXJjwAAPQDAAAA.Bumbata:BAAANQAECgMICgAAAA==.Bus:BAACNQAFFH8mAAIMAAgK+CYdAAC9AgAMAAgK+CYdAAC9AgA1AAQKfzQAAgwACgr9Jh8AAKIDAAwACgr9Jh8AAKIDAAAA.',
By='Bylunn:BAAANQADCgEIAQAAAA==.',
Ca='Cactusjuicee:BAAANQAECgEIAQAAAA==.',
Ce='Celeres:BAABNQAECn9SAAMNAAoKERstDQDTAgANAAoKERstDQDTAgAOAAcK8wVIDQDjAAAAAA==.Celesdria:BAAANQADCgMIAwABNQAECgoKUgANABEbAA==.Celys:BAAANQADCgIIAgAAAA==.Ceo:BAABNQAECn8gAAMGAAoK9h+NJgBmAgAGAAoK9h+NJgBmAgAMAAUKCQ/VQwDjAAAAAA==.',
Ch='Channie:BAAANQABCgMIAwAAAA==.Chios:BAAANQAECgcIBwABNQABCgIIAwAEAAAAAA==.',
Da='Darkeblood:BAAANQAECgEIAQAAAA==.',
De='Deadcell:BAABNQAECn8iAAMPAAkKlRmGBgD7AQAPAAkKlRmGBgD7AQAHAAMKnAzWdQCiAAAAAA==.Denamage:BAACNQAFFH8bAAMQAAcKXAtUCgB7AQAQAAcKXAtUCgB7AQARAAEKuwQ7FgA8AAA1AAQKfywAAxAACgoAGSF/AIACABAACgoAGSF/AIACABEABQoiCS8nALkAAAAA.Denarrage:BAAANQAFFAEIAQAAAA==.',
Di='Disconnect:BAAANQABCgIJAwAAAA==.',
Do='Dokuganryu:BAAANQADCgIIAgABNQAECgoKMwASAAMmAA==.Dontnerfspls:BAAANQAECgIIAgABNQAECgoKRQAKADMfAA==.Donzul:BAAANQADCgUIBQAAAA==.Doomtickle:BAAANQADCgYIBgAAAA==.',
Ea='Earthigga:BAAANQAECggIDwAAAA==.',
Ei='Eichmann:BAAANQAECgIIAgAAAA==.',
El='Eldruida:BAACNQAFFH8JAAITAAIKZAwrFgCFAAATAAIKZAwrFgCFAAA1AAQKf0QAAhMACgofGWwWADICABMACgofGWwWADICAAAA.Elixxi:BAAANQADCgYIBgAAAA==.Ellipsoro:BAABNQAECn8hAAIKAAgKWRlGIgCcAQAKAAgKWRlGIgCcAQAAAA==.Eltrol:BAAANQAECgEIAwAAAA==.',
En='Enoc:BAAANQAECgQIBwAAAA==.',
Er='Erale:BAAANQAECgEIAgAAAA==.',
Fa='Faeris:BAACNQAFFH8IAAIUAAUKEg1oFABkAQAUAAUKEg1oFABkAQA1AAQKfyQAAxQACgp1H1odAPwCABQACgp1H1odAPwCABUABAq/GZIPADIBAAAA.Fakecheese:BAAANQAECgEIAQABNQAECgoKMAAWAOQUAA==.Fatalis:BAACNQAFFH8OAAMXAAUKUQodGAD6AAAXAAUKUQodGAD6AAABAAEKAAAZKQAeAAA1AAQKf0cAAxcACgrMHQEcAK4CABcACgrMHQEcAK4CAAEAAQoAAJaYACgAAAAA.',
Fe='Fedqt:BAAANQAECgIIBAAAAA==.Felko:BAAANQAECggIDgAAAA==.',
Fi='Fiestykitten:BAAANQAECgEIAQAAAA==.Fizaw:BAABNQAECn8vAAIYAAoKpg1IEwCQAQAYAAoKpg1IEwCQAQAAAA==.',
Fl='Floydmagussy:BAACNQAFFH8MAAIQAAUKESACGQCxAQAQAAUKESACGQCxAQA1AAQKfx8AAhAACQphI2Y3ABoDABAACQphI2Y3ABoDAAAA.',
Fo='Foamdk:BAAANQADCggICwAAAA==.',
Fr='Freezypuff:BAAANQAECgcIBgAAAA==.Frostee:BAAANQAECgEIAQAAAA==.Frøzen:BAABNQAECn8XAAIQAAUKbQWzAAGNAAAQAAUKbQWzAAGNAAAAAA==.',
Fu='Fuzzydots:BAAANQAECgQIBAABNQAECgoKOAAWADQdAA==.',
Ga='Gamu:BAAANQADCgMIAwAAAA==.Gaurr:BAABNQAECn8sAAICAAoK0BMoTQBoAQACAAoK0BMoTQBoAQAAAA==.',
Ge='Genevah:BAAANQADCgUIBQAAAA==.Geneviere:BAAANQADCgMIAwAAAA==.',
Gi='Gianna:BAAANQAECgYICQAAAA==.Gislain:BAAANQADCgcIDQAAAA==.',
Go='Goldeye:BAAANQADCgYIEwAAAA==.',
Gr='Greyspirit:BAABNQAECn9DAAIZAAoKASNOAwCFAwAZAAoKASNOAwCFAwAAAA==.Grimothy:BAABNQAECn8qAAMDAAoKmRgqFwDRAgADAAoKmRgqFwDRAgACAAgKOww9cAD+AAAAAA==.',
Gu='Gulohof:BAAANQADCgEIAQAAAA==.',
Ha='Halcoldrek:BAAANQADCgQJBAAAAA==.',
Hb='Hbc:BAACNQAFFH8IAAIZAAUKPxUdAwDWAAAZAAUKPxUdAwDWAAA1AAQKfxoAAxkACgqWIdkEAPcCABkACgqWIdkEAPcCABoAAQoyHOEyAFIAAAE1AAEKAggDAAQAAAAA.',
He='Healarious:BAABNQAECn8XAAIUAAcKtRadWwCVAQAUAAcKtRadWwCVAQAAAA==.Hembrota:BAAANQADCgcIEgAAAA==.Heyz:BAAANQAECggICwAAAA==.',
Hi='Himbo:BAABNQAECn8eAAIXAAcKrAcfrgARAQAXAAcKrAcfrgARAQAAAA==.',
Ho='Hogs:BAAANQAECgQIDgABNQAECgkJGwACAMYdAA==.Holypoopp:BAABNQAECn8qAAMGAAoKAh2dJQDUAgAGAAoKAh2dJQDUAgAWAAcK+AnS1QDwAAAAAA==.Holyreturn:BAABNQAECn84AAIGAAoKYx+tIACKAgAGAAoKYx+tIACKAgAAAA==.',
Hw='Hwasin:BAAANQAECgQIBAABNQAECggICwAEAAAAAA==.',
Il='Illanyth:BAAANQADCgUIBQAAAA==.Illidaldin:BAAANQADCgYIBgABNQAECgoKKwAbALoXAA==.',
Im='Imran:BAACNQAFFH8MAAIMAAMK4xsYCADjAAAMAAMK4xsYCADjAAA1AAQKf0kAAgwACgrVIbkFAFIDAAwACgrVIbkFAFIDAAAA.',
In='Inthelayer:BAAANQADCgYIBgABNQAECgkJGwACAMYdAA==.',
Ja='Janny:BAAANQABCgQIBAAAAA==.',
Je='Jether:BAAANQAECgEIAQAAAA==.',
Jo='Jojobaggins:BAABNQAECn9FAAQcAAoK5CDREgDCAgAdAAgK5B46FwDCAgAcAAoKJCDREgDCAgAeAAQKzxXIEAANAQAAAA==.',
Ka='Kaadriluna:BAAANQADCgEIAQAAAA==.',
Kc='Kcthegreat:BAAANQADCgQIBQAAAA==.',
Ke='Keyholes:BAACNQAFFH8jAAISAAkKnx1SAwBgAgASAAkKnx1SAwBgAgA1AAQKfx8AAhIACQrvIowUAAgDABIACQrvIowUAAgDAAE1AAEKAggDAAQAAAAA.Keyohs:BAAANQADCgcICAABNQABCgIIAwAEAAAAAA==.',
Ki='Kirky:BAAANQADCgUIBgAAAA==.',
Kk='Kkoda:BAAANQAECgcICQAAAA==.',
Ko='Koal:BAABNQAECn8oAAIXAAcKoRbggwBoAQAXAAcKoRbggwBoAQAAAA==.Kodabear:BAAANQADCggICAAAAA==.',
Kr='Kraz:BAAANQADCgYIBgAAAA==.Kronos:BAAANQADCgYIBgABNQAECgoKHgAMAFQRAA==.',
Ku='Kushage:BAAANQADCgMIAwAAAA==.',
['Kí']='Kírky:BAAANQADCgIIAwABNQADCgUIBgAEAAAAAA==.',
Le='Lettussy:BAACNQAFFH8gAAMcAAcK1iILAwD0AQAcAAYKzR8LAwD0AQAdAAUK+CSCBQDWAQA1AAQKfzkAAx0ACgrWJUwCALsDAB0ACQogJkwCALsDABwACAqxJAcPAOQCAAAA.',
Li='Lixxi:BAABNQAECn89AAIUAAoKAx+WIQCiAgAUAAoKAx+WIQCiAgAAAA==.',
Lu='Luminyssa:BAAANQAECgQIBwAAAA==.',
['Lú']='Lúthien:BAAANQAECggIEQAAAA==.',
Ma='Maeby:BAAANQAECgcIDAAAAA==.Magicwater:BAACNQAFFH8gAAIQAAcK5B4kBgDWAQAQAAcK5B4kBgDWAQA1AAQKfzsAAhAACgoMJL8dAGEDABAACgoMJL8dAGEDAAAA.Magigga:BAAANQAECggIAwAAAA==.Mallcador:BAAANQADCgQIBAAAAA==.',
Me='Meeoowzer:BAABNQAECn80AAIGAAoKSR3cNgCIAgAGAAoKSR3cNgCIAgAAAA==.Meloo:BAABNQAECn8dAAIHAAgKigu8NQA0AQAHAAgKigu8NQA0AQAAAA==.',
Mo='Mollyflo:BAAANQAECgcIDgAAAA==.Mollymauk:BAABNQAECn86AAMGAAkKJRPeZgDjAQAGAAkKJRPeZgDjAQAWAAgKig6yrgDCAQAAAA==.Moorality:BAABNQAFFH8JAAIMAAQKShaNAwAOAQAMAAQKShaNAwAOAQABNQABCgIIAwAEAAAAAA==.Moretino:BAAANQAECgEIAQAAAA==.Morgane:BAAANQADCgEIAQAAAA==.Mothra:BAABNQAECn8eAAIDAAoKXxJZPQDvAQADAAoKXxJZPQDvAQABNQAFFAUIEAABALcOAA==.',
Mu='Muhjo:BAAANQADCgYIDQAAAA==.Muppet:BAABNQAECn8UAAIZAAgK6RM5IACaAQAZAAgK6RM5IACaAQAAAA==.Murryjane:BAAANQAECgcIDQABNQAECggICwAEAAAAAA==.Muufarmer:BAAANQAECgYICgAAAA==.',
Na='Natedk:BAAANQAECgYIBgAAAA==.',
Ne='Neyt:BAABNQAECn8wAAMfAAoKkB6LDAAaAwAfAAoKkB6LDAAaAwAHAAMKahGZcQCzAAAAAA==.',
Ni='Nitesrider:BAAANQAECgQIBQAAAA==.',
No='Nora:BAACNQAFFH80AAMWAAoKjiQRAABwAwAWAAoKjiQRAABwAwAMAAEKAAAyDgBiAAA1AAQKf0cABBYACgrkJnADAOEDABYACgrjJnADAOEDAAwABwqiJgUJAA0DAAYACQotG/c7AHQCAAAA.Nostrodom:BAAANQADCgcIEQAAAA==.',
Nu='Nubbs:BAABNQAECn8VAAIgAAUKpRaDPQAqAQAgAAUKpRaDPQAqAQAAAA==.Nubheala:BAABNQAECn8rAAMUAAoKhyFwCwBmAwAUAAoKhyFwCwBmAwAVAAEKvg5CKgAvAAAAAA==.Nuri:BAABNQAECn8yAAIQAAoK1h3tOwAPAwAQAAoK1h3tOwAPAwAAAA==.',
Od='Odylight:BAAANQADCggICQAAAA==.',
Or='Orcazmo:BAABNQAECn8ZAAMhAAgK3wYECwBHAQAhAAgKpgYECwBHAQAiAAcKQQSI2wASAQAAAA==.',
Pe='Peluij:BAAANQAECgQIBgAAAA==.',
Pi='Pingopango:BAAANQAECgYIDAABNQAECgkJGQAGAMMZAA==.Pinkdefender:BAAANQAECgQIBQABNQAECgoKRQAKADMfAA==.Pinpanpum:BAAANQAECgEIAQAAAA==.',
Po='Pokeumon:BAAANQAECgYIBgAAAA==.Poosistrox:BAABNQAECn9FAAQKAAoKMx/7GgDqAgAKAAkK7SD7GgDqAgAjAAoKdhKJPQDXAQASAAUK8hCSdAAkAQAAAA==.',
Ps='Pspspspsps:BAABNQAECn8WAAIaAAUKzg7UHwC9AAAaAAUKzg7UHwC9AAAAAA==.',
Pt='Ptheve:BAACNQAFFH80AAIHAAoK9iUVAAB8AwAHAAoK9iUVAAB8AwA1AAQKfzUAAgcACgr6Jj8AAJMDAAcACgr6Jj8AAJMDAAAA.',
Pu='Punipuni:BAAANQABCgIIAgAAAA==.',
Qs='Qsham:BAAANQAECgUICAAAAA==.',
Qw='Qwarlock:BAABNQAECn88AAMiAAoK/hYOSwC8AQAiAAkKuBUOSwC8AQAbAAEK5x8CJwBNAAAAAA==.',
Ra='Raela:BAACNQAFFH8LAAIjAAQK9RgFDgDAAAAjAAQK9RgFDgDAAAA1AAQKfzoAAiMACQqwItAYAFMCACMACQqwItAYAFMCAAAA.Rahnarmight:BAAANQADCgMIAwAAAA==.Raygor:BAAANQAECgUIDAAAAA==.Razzle:BAAANQADCgIIAgABNQAECgoKMgAQANYdAA==.',
Re='Renewal:BAAANQAECgUIBQAAAA==.',
Ri='Rickthyr:BAAANQAECgUIDAAAAA==.Rigger:BAAANQADCgYJBgABNQAECgQIBQAEAAAAAA==.Rizzerz:BAAANQADCgcIBwAAAA==.',
Ro='Rodgozinya:BAAANQADCggIBwABNQAECgoKNQAIAOQZAA==.Rosewalker:BAAANQAECgYIEAABNQAFFAcIIAAQAOQeAA==.Rosewall:BAAANQADCgIIAgABNQAFFAcIIAAQAOQeAA==.Rottgut:BAAANQADCgEIAQAAAA==.',
Ru='Rumog:BAAANQAECgUIDAAAAA==.',
Ry='Rykix:BAAANQADCgEIAQAAAA==.Rykò:BAABNQAECn8aAAIXAAYKeBvbkADnAQAXAAYKeBvbkADnAQAAAA==.',
['Ré']='Réckléssnéss:BAAANQAECgUICQAAAA==.',
Sa='Salmorg:BAABNQAECn9FAAMfAAoKmiKGBQD0AgAfAAoKmiKGBQD0AgAHAAgK8h08KgBPAgAAAA==.Satinet:BAAANQAECgEIAQAAAA==.Sayafaed:BAABNQAECn87AAIfAAoKig7IFgDPAQAfAAoKig7IFgDPAQAAAA==.',
Sc='Scalen:BAAANQADCgYIBgAAAA==.Scatback:BAABNQAECn83AAIUAAoK0SIuBQDGAwAUAAoK0SIuBQDGAwAAAA==.Schwarzmagic:BAAANQADCggIEgAAAA==.',
Sh='Shilor:BAABNQAECn8iAAMUAAoKDRNSSQDaAQAUAAoKThBSSQDaAQAVAAMKgBUZFwC+AAAAAA==.Shogun:BAAANQAECgQIDgAAAA==.Shortsnack:BAAANQABCgMJAwAAAA==.',
Si='Sicarii:BAAANQAECggIEAAAAA==.Sicarrious:BAAANQADCggIEQABNQAECggIEAAEAAAAAA==.Sinatra:BAABNQAECn8/AAIkAAoK5yFmAwCqAwAkAAoK5yFmAwCqAwAAAA==.',
Sk='Skyarc:BAAANQAECgIIBAABNQAECggIEwAEAAAAAA==.Skybolt:BAAANQAECgIIAgABNQAECggIEwAEAAAAAA==.Skylite:BAAANQAECggIEwAAAA==.Skyrak:BAAANQADCgQIBAABNQAECggIEwAEAAAAAA==.Skyrun:BAAANQAECgMIAQABNQAECggIEwAEAAAAAA==.',
Sn='Sneaksnstabs:BAAANQAECgYICQABNQAECgoKRQAKADMfAA==.',
So='Soulpurge:BAAANQADCgEIAQAAAA==.',
Sp='Splat:BAAANQAECgUIBgABNQAECgoKKgAGAAIdAA==.Spoopy:BAAANQADCggICAAAAA==.Spënny:BAAANQAECgQIBQAAAA==.',
St='Stélle:BAABNQAECn8uAAIBAAkK7A5ALwDSAQABAAkK7A5ALwDSAQAAAA==.',
Su='Supdude:BAABNQAECn86AAIcAAoKlBzmBwD8AgAcAAoKlBzmBwD8AgAAAA==.',
Ta='Tatorz:BAAANQAECgQICAAAAA==.Tazingo:BAAANQAECgQIBgABNQAECgoKMgAQANYdAA==.',
Te='Tentacrool:BAAANQABCgEIAQAAAA==.',
Ti='Tigas:BAABNQAECn8mAAMIAAoKSB6mQADIAgAIAAoKSB6mQADIAgALAAIKUSIBJQCJAAAAAA==.',
To='Tolally:BAAANQAFFAMIAwAAAA==.Tooth:BAAANQADCgQIBQAAAA==.',
Tr='Trashdragon:BAABNQAECn8uAAMFAAoK4RqDDACbAgAFAAkKcR6DDACbAgAOAAQKsg7VEQCSAAAAAA==.Trashshaman:BAAANQAECgMIAwAAAA==.Trauma:BAAANQAECgYIBwAAAA==.',
Tu='Turtlebear:BAAANQADCgIIAgABNQAECgcIBgAEAAAAAA==.',
Ty='Typhoonz:BAAANQADCgYIBgAAAA==.',
Ur='Uróboros:BAAANQADCgEIAQAAAA==.',
Vi='Vipex:BAAANQAECgIIAwAAAA==.',
Vy='Vynii:BAABNQAECn8xAAMHAAoKWxf3FwAgAgAHAAoKWxf3FwAgAgAfAAIK9gODZQBTAAAAAA==.',
Wa='Wallofstars:BAAANQADCgQIBQAAAA==.Wardamage:BAAANQABCgEIAQAAAA==.Wasabi:BAABNQAECn8eAAINAAcKJBnmEgCKAQANAAcKJBnmEgCKAQAAAA==.',
We='Wey:BAAANQAECggIDQAAAA==.',
Wo='Wonon:BAAANQAECgEIAQAAAA==.',
Xa='Xaida:BAAANQAECgYICgABNQAFFAoKRQANAEEUAA==.Xalant:BAAANQADCggICQAAAA==.',
Yo='Yourhammy:BAAANQADCgMIAwAAAA==.Yoyo:BAAANQAECgIJAgAAAA==.',
Yt='Ytteriul:BAAANQADCgYIEgAAAA==.',
Za='Zangyaku:BAABNQAECn8zAAISAAoKAyYVBgAXAwASAAoKAyYVBgAXAwAAAA==.Zanmetsu:BAAANQAECgUIBQABNQAECgoKMwASAAMmAA==.',
Ze='Zenis:BAABNQAECn8ZAAIGAAkKwxnAJgDOAgAGAAkKwxnAJgDOAgAAAA==.Zerocool:BAAANQADCgYIBgAAAA==.Zerø:BAAANQADCgIIAgAAAA==.Zetsuï:BAAANQAECgcIEwAAAA==.',
['ßa']='ßadfish:BAABNQAECn8hAAIWAAoKDSOfDgCSAwAWAAoKDSOfDgCSAwAAAA==.',
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
