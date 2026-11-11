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

local lookup = {'Hunter-Marksmanship','Shaman-Elemental','Shaman-Restoration','Unknown-Unknown','Evoker-Devastation','Paladin-Holy','DemonHunter-Havoc','Warrior-Arms','Warrior-Protection','DeathKnight-Unholy','Warrior-Fury','Paladin-Protection','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Vengeance','Mage-Arcane','Mage-Frost','DeathKnight-Blood','Druid-Balance','Priest-Holy','Priest-Discipline','Paladin-Retribution','Hunter-BeastMastery','Monk-Mistweaver','Druid-Guardian','Druid-Feral','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','DemonHunter-Devourer','Monk-Windwalker','Warlock-Affliction','Warlock-Demonology','DeathKnight-Frost','Druid-Restoration','Priest-Shadow',}
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abrams:BAAANQAECgYIEAAAAA==.',
Ad='Addý:BAAANQAECggIEQAAAA==.',
Ae='Aethyra:BAAANQAECgYICwAAAA==.',
Ah='Ahimsa:BAABNQAECn8rAAIBAAoK4RGdFQDZAQABAAoK4RGdFQDZAQAAAA==.',
Ai='Ailisuuith:BAABNQAECn8aAAMCAAkKlRGZyQD/AAACAAcKug2ZyQD/AAADAAYKtQX/4wCiAAAAAA==.',
Al='Alkyri:BAAANQADCgMIAwAAAA==.Almamun:BAAANQADCgcIDwAAAA==.',
Ar='Arcanemommy:BAAANQAECgEIAQAAAA==.Arcz:BAAANQAECgcIDgABNQAECggIDAAEAAAAAA==.',
As='Ashenclaw:BAACNQAFFH8GAAIFAAMK9w+cBQB+AAAFAAMK9w+cBQB+AAA1AAQKf0gAAgUACgoYGfYFAEICAAUACgoYGfYFAEICAAAA.',
At='Athalena:BAAANQAECgQICAABNQAECgoKOwAGAGAUAA==.',
Au='Auzatryx:BAAANQAECgUIBQAAAA==.',
Ba='Babs:BAAANQABCgIIAgABNQAECggIHQAHAIoLAA==.Babyboo:BAAANQADCgcIFAAAAA==.Bamboom:BAAANQAECgEIAwAAAA==.',
Bi='Biggrnmonstr:BAABNQAECn8oAAMIAAkKlRHefwByAQAIAAkKTRDefwByAQAJAAEKdRb6QwAyAAABNQAECgoKSwAKADMfAA==.Bigxthezug:BAABNQAECn8bAAMCAAkKxh2SMwCrAgACAAkKxh2SMwCrAgADAAMKowWu9wB7AAAAAA==.',
Bl='Blaine:BAAANQADCgcIEgAAAA==.',
Bo='Bongripa:BAAANQABCgEIAQAAAA==.Bonquiqui:BAAANQADCgcIDAAAAA==.Boypartz:BAABNQAECn81AAIIAAoK5BlFPQA+AgAIAAoK5BlFPQA+AgAAAA==.',
Br='Braidedbewbs:BAAANQAECgEIAQAAAA==.Breakfast:BAAANQADCgMIAwABNQAECgkJGwACAMYdAA==.Brittinia:BAAANQAECgIIBAAAAA==.',
Bu='Budders:BAAANQAECgEIAQAAAA==.Bulbasaurus:BAACNQAFFH8JAAILAAcKoiNSAAB/AQALAAcKoiNSAAB/AQA1AAQKfz8AAgsACgqYJjwAAPQDAAsACgqYJjwAAPQDAAAA.Bumbata:BAAANQAECgMIDQAAAA==.Bus:BAACNQAFFH8sAAIMAAgK+CYvAAC4AgAMAAgK+CYvAAC4AgA1AAQKfz4AAgwACgr+Jg8AAKUDAAwACgr+Jg8AAKUDAAAA.',
By='Bylunn:BAAANQADCgEIAQAAAA==.',
Ca='Cactusjuicee:BAAANQAECgEIAgAAAA==.',
Ce='Celeres:BAABNQAECn9VAAMNAAoKERstDQDTAgANAAoKERstDQDTAgAOAAcK8wXrDgDiAAAAAA==.Celesdria:BAAANQADCgMIAwABNQAECgoKVQANABEbAA==.Celys:BAAANQADCgIIAgAAAA==.Ceo:BAABNQAECn8gAAMGAAoK9h8aLQBgAgAGAAoK9h8aLQBgAgAMAAUKCQ/VQwDjAAAAAA==.',
Ch='Channie:BAAANQABCgMIAwAAAA==.Chios:BAAANQAECgcICAABNQABCgIIAwAEAAAAAA==.',
Da='Darkeblood:BAAANQAECgEIAQAAAA==.Davros:BAAANQAECgEIAgAAAA==.',
De='Deadcell:BAABNQAECn8iAAMPAAkKlRmaBwD1AQAPAAkKlRmaBwD1AQAHAAMKnAzWdQCiAAAAAA==.Denamage:BAACNQAFFH8bAAMQAAcKXAv+DQB1AQAQAAcKXAv+DQB1AQARAAEKuwQ7FgA8AAA1AAQKfywAAxAACgoAGSF/AIACABAACgoAGSF/AIACABEABQoiCS8nALkAAAAA.Denarrage:BAAANQAFFAEIAQAAAA==.',
Di='Disconnect:BAAANQAECgEIAQAAAA==.',
Do='Doingmost:BAAANQAECgEIAQAAAA==.Dokuganryu:BAAANQADCgIIAgABNQAECgoKMwASAAMmAA==.Dontnerfspls:BAAANQAECgIIAgABNQAECgoKSwAKADMfAA==.Donzul:BAAANQADCgUIBQAAAA==.Doomtickle:BAAANQADCgYIBgAAAA==.',
Ea='Earthigga:BAAANQAECggIEAAAAA==.',
Ei='Eichmann:BAAANQAECgIIAgAAAA==.',
El='Eldruida:BAACNQAFFH8JAAITAAIKZAy/GQCEAAATAAIKZAy/GQCEAAA1AAQKf0QAAhMACgofGUkZAC8CABMACgofGUkZAC8CAAAA.Elixxi:BAAANQADCgYIBgAAAA==.Ellipsoro:BAABNQAECn8lAAIKAAgKXxtWIgC5AQAKAAgKXxtWIgC5AQAAAA==.Eltrol:BAAANQAECgIIBQAAAA==.',
En='Enoc:BAAANQAECgQIBwAAAA==.',
Er='Erale:BAAANQAECgEIAgAAAA==.',
Fa='Faeris:BAACNQAFFH8IAAIUAAUKEg1oFABkAQAUAAUKEg1oFABkAQA1AAQKfyQAAxQACgp1H1odAPwCABQACgp1H1odAPwCABUABAq/GZIPADIBAAAA.Fakecheese:BAAANQAECgEIAQABNQAECgoKMAAWAOQUAA==.Fatalis:BAACNQAFFH8OAAMXAAUKUQodGAD6AAAXAAUKUQodGAD6AAABAAEKAAAZKQAeAAA1AAQKf1AAAxcACgpRH40YANcCABcACgpRH40YANcCAAEAAQoAAJaYACgAAAAA.',
Fe='Fedqt:BAAANQAECgIIBQAAAA==.Felko:BAABNQAECn8WAAMGAAkKjhm1IwCVAgAGAAkKjhm1IwCVAgAWAAYKhw/zxwAvAQAAAA==.',
Fi='Fiestykitten:BAAANQAECgEIAQAAAA==.Fireballcat:BAAANQAECgEIAQAAAA==.Fizaw:BAABNQAECn8zAAIYAAoKwQ2XGwDJAQAYAAoKwQ2XGwDJAQAAAA==.',
Fl='Floydmagussy:BAACNQAFFH8MAAIQAAUKESACGQCxAQAQAAUKESACGQCxAQA1AAQKfx8AAhAACQphI2Y3ABoDABAACQphI2Y3ABoDAAAA.',
Fo='Foamdk:BAAANQADCggICwAAAA==.',
Fr='Freezypuff:BAAANQAECgUIBgAAAA==.Frostee:BAAANQAECgEIAgAAAA==.Frøzen:BAABNQAECn8XAAIQAAUKbQWpbAHhAAAQAAUKbQWpbAHhAAAAAA==.',
Fu='Fuzzydots:BAAANQAECgQIBAABNQAECgoKQQAWAGAfAA==.',
Ga='Gamu:BAAANQADCgMIAwAAAA==.Gaurr:BAABNQAECn8sAAICAAoK0BObUgB5AQACAAoK0BObUgB5AQAAAA==.',
Ge='Genevah:BAAANQADCgUIBQAAAA==.Geneviere:BAAANQADCgMIAwAAAA==.',
Gi='Gianna:BAAANQAECgYIDgAAAA==.',
Go='Goldeye:BAAANQADCgYIEwAAAA==.',
Gr='Greyspirit:BAABNQAECn9DAAIZAAoKASNOAwCFAwAZAAoKASNOAwCFAwAAAA==.Grimothy:BAABNQAECn8uAAMDAAoKmRgRHQC8AgADAAoKmRgRHQC8AgACAAgKOwzpfgD9AAAAAA==.',
Gu='Gulohof:BAAANQADCgEIAQAAAA==.',
Ha='Halcoldrek:BAAANQADCgQJBAAAAA==.',
Hb='Hbc:BAACNQAFFH8LAAIZAAYKeBiSAQA6AQAZAAYKeBiSAQA6AQA1AAQKfxsAAxkACgrBIb8FAPECABkACgqWIb8FAPECABoAAgopHsQmALAAAAE1AAEKAggDAAQAAAAA.',
He='Healarious:BAABNQAECn8bAAIUAAcKtRYVYQCmAQAUAAcKtRYVYQCmAQAAAA==.Hembrota:BAAANQADCgcIEgAAAA==.Heyz:BAAANQAECggIDAAAAA==.',
Hi='Himbo:BAABNQAECn8eAAIXAAcKrAcf0QBeAQAXAAcKrAcf0QBeAQAAAA==.',
Ho='Hogs:BAAANQAECgQIDgABNQAECgkJGwACAMYdAA==.Holypoopp:BAABNQAECn8sAAMGAAoKAh2dJQDUAgAGAAoKAh2dJQDUAgAWAAkKFwuVrQBeAQAAAA==.Holyreturn:BAABNQAECn9FAAIGAAoKECHoDgA8AwAGAAoKECHoDgA8AwAAAA==.',
Hu='Huntigga:BAAANQAECgQIBgAAAA==.',
Hw='Hwasin:BAAANQAECgQIBAABNQAECggIDAAEAAAAAA==.',
Il='Illanyth:BAAANQADCgUIBQAAAA==.Illidaldin:BAAANQADCgYIBgABNQAECgoKKwAbALoXAA==.',
Im='Imran:BAACNQAFFH8MAAIMAAMK4xsYCADjAAAMAAMK4xsYCADjAAA1AAQKf0wAAgwACgo7IrkFAFIDAAwACgo7IrkFAFIDAAAA.',
In='Inthelayer:BAAANQADCgYIBgABNQAECgkJGwACAMYdAA==.',
Ja='Janny:BAAANQABCgQIBAAAAA==.',
Je='Jether:BAAANQAECgEIAwAAAA==.',
Jo='Jojobaggins:BAABNQAECn9HAAQcAAoK5CCCFQDEAgAcAAoKJCCCFQDEAgAdAAgK5B46FwDCAgAeAAQKzxXIEAANAQAAAA==.',
Ka='Kaadriluna:BAAANQADCgEIAQAAAA==.',
Kc='Kcthegreat:BAAANQAECgEIAgAAAA==.',
Ke='Keyholes:BAACNQAFFH8nAAISAAkKnx1SAwBgAgASAAkKnx1SAwBgAgA1AAQKfx8AAhIACQrvIowUAAgDABIACQrvIowUAAgDAAE1AAEKAggDAAQAAAAA.Keyohs:BAAANQADCgcICAABNQABCgIIAwAEAAAAAA==.',
Ki='Kirky:BAAANQADCgUIBgAAAA==.',
Kk='Kkoda:BAAANQAECgcICQAAAA==.',
Ko='Koal:BAABNQAECn8oAAIXAAcKoRZNkwByAQAXAAcKoRZNkwByAQAAAA==.Kodabear:BAAANQADCggICAAAAA==.',
Kr='Kraz:BAAANQADCgYIBgAAAA==.Kronos:BAAANQADCgYIBgABNQAECgoKHgAMAFQRAA==.',
Ku='Kushage:BAAANQADCgMIAwAAAA==.',
['Kí']='Kírky:BAAANQADCgIIAwABNQADCgUIBgAEAAAAAA==.',
Le='Lettussy:BAACNQAFFH8gAAMcAAcK1iI4BAD1AQAcAAYKzR84BAD1AQAdAAUK+CSCBQDWAQA1AAQKfzsAAx0ACgrhJUwCALsDAB0ACQogJkwCALsDABwACArfJOEPAPACAAAA.',
Li='Lixxi:BAABNQAECn9AAAIUAAoKAx9nJwDNAgAUAAoKAx9nJwDNAgAAAA==.',
Lu='Luminyssa:BAAANQAECgQIBwAAAA==.',
['Lú']='Lúthien:BAAANQAECggIEQAAAA==.',
Ma='Maeby:BAABNQAECn8VAAIIAAkKdxWuPgA4AgAIAAkKdxWuPgA4AgAAAA==.Magicwater:BAACNQAFFH8lAAIQAAcKLyBQBwD8AQAQAAcKLyBQBwD8AQA1AAQKfzwAAhAACgpJJL8dAGEDABAACgpJJL8dAGEDAAAA.Magigga:BAAANQAECggIBAAAAA==.Mallcador:BAAANQADCgQIBAAAAA==.',
Me='Meeoowzer:BAABNQAECn86AAIGAAoKSR3cNgCIAgAGAAoKSR3cNgCIAgAAAA==.Meloo:BAABNQAECn8dAAIHAAgKigvZPAAxAQAHAAgKigvZPAAxAQAAAA==.Melyda:BAAANQAECgEIAQAAAA==.',
Mo='Mollyflo:BAAANQAECgcIDgAAAA==.Mollymauk:BAABNQAECn87AAMGAAoKYBTeZgDjAQAGAAoKYBTeZgDjAQAWAAgKig6yrgDCAQAAAA==.Moorality:BAABNQAFFH8MAAIMAAUKyxjrAwAZAQAMAAUKyxjrAwAZAQABNQABCgIIAwAEAAAAAA==.Moretino:BAAANQAECgQIBwAAAA==.Morgane:BAAANQADCgEIAQAAAA==.Mothra:BAABNQAECn8gAAIDAAoKXxLfQgDyAQADAAoKXxLfQgDyAQABNQAFFAUIEAABALcOAA==.',
Mu='Muhjo:BAAANQADCgYIDQAAAA==.Muppet:BAABNQAECn8UAAIZAAgK6RM5IACaAQAZAAgK6RM5IACaAQAAAA==.Murryjane:BAAANQAECgcIDwABNQAECggIDAAEAAAAAA==.Muufarmer:BAAANQAECgYIDAAAAA==.',
Na='Natedk:BAAANQAECgYIBgAAAA==.',
Ne='Neyt:BAABNQAECn8wAAMfAAoKkB6LDAAaAwAfAAoKkB6LDAAaAwAHAAMKahGZcQCzAAAAAA==.',
Ni='Nitesrider:BAAANQAECgQIBQAAAA==.',
No='Nora:BAACNQAFFH8+AAMWAAoKaSUTAAB/AwAWAAoKaSUTAAB/AwAMAAEKAAAyDgBiAAA1AAQKf0gABBYACgrkJnADAOEDABYACgrjJnADAOEDAAwABwqiJgUJAA0DAAYACQotG/c7AHQCAAAA.Nostrodom:BAAANQADCgcIEQAAAA==.',
Nu='Nubbs:BAABNQAECn8VAAIgAAUKpRaDPQAqAQAgAAUKpRaDPQAqAQAAAA==.Nubheala:BAABNQAECn80AAMUAAoKXiLOCACaAwAUAAoKXiLOCACaAwAVAAEKvg5CKgAvAAAAAA==.Nuri:BAABNQAECn8yAAIQAAoK1h3tOwAPAwAQAAoK1h3tOwAPAwAAAA==.',
Od='Odylight:BAAANQADCggICQAAAA==.',
Or='Orcazmo:BAABNQAECn8cAAMhAAkKyQjzCQCYAQAhAAkKvQjzCQCYAQAiAAcKQQSI2wASAQAAAA==.',
Pa='Paladigga:BAAANQAECgEIAQAAAA==.Pandalorenzo:BAAANQAECgEIAQAAAA==.',
Pe='Peluij:BAAANQAECgQIBwAAAA==.',
Pi='Pingopango:BAAANQAECgYIDAABNQAECgkJGQAGAMMZAA==.Pinkdefender:BAAANQAECgQIBgABNQAECgoKSwAKADMfAA==.Pinpanpum:BAAANQAECgEIAQAAAA==.',
Po='Pocketsize:BAAANQAECgEIAQAAAA==.Pokeumon:BAAANQAECgYIBgAAAA==.Poosistrox:BAABNQAECn9LAAQKAAoKMx/7GgDqAgAKAAkK7SD7GgDqAgAjAAoKURTINwCrAQASAAUK8hCSdAAkAQAAAA==.',
Ps='Pspspspsps:BAABNQAECn8WAAIaAAUKzg5cJQC6AAAaAAUKzg5cJQC6AAAAAA==.',
Pt='Ptheve:BAACNQAFFH8+AAIHAAoKKSYUAACDAwAHAAoKKSYUAACDAwA1AAQKfzUAAgcACgr6Jl0AAJIDAAcACgr6Jl0AAJIDAAAA.',
Pu='Punipuni:BAAANQABCgIIAgAAAA==.',
Qs='Qsham:BAAANQAECgUICgAAAA==.',
Qw='Qwarlock:BAABNQAECn8/AAMiAAoKJhdFUADQAQAiAAkK5hVFUADQAQAbAAEK5x/nKgBMAAAAAA==.',
Ra='Raela:BAACNQAFFH8LAAIjAAQK9Rh6EAC8AAAjAAQK9Rh6EAC8AAA1AAQKfzoAAiMACQqwIrkdAJwCACMACQqwIrkdAJwCAAAA.Rahnarmight:BAAANQAECgEIAgAAAA==.Raygor:BAAANQAECgUIDgAAAA==.Razzle:BAAANQADCgIIAgABNQAECgoKMgAQANYdAA==.',
Re='Renewal:BAAANQAECgUIBQAAAA==.',
Ri='Rickthyr:BAAANQAECgUIDwAAAA==.Rigger:BAAANQADCgYJBgABNQAECgQIBQAEAAAAAA==.Rizzerz:BAAANQADCgcIBwAAAA==.',
Ro='Rodgozinya:BAAANQADCggIBwABNQAECgoKNQAIAOQZAA==.Rosewalker:BAAANQAECgYIEgABNQAFFAcIJQAQAC8gAA==.Rosewall:BAAANQADCgIIAgABNQAFFAcIJQAQAC8gAA==.Rottgut:BAAANQADCgEIAQAAAA==.',
Ru='Rumog:BAAANQAECgUIDQAAAA==.',
Ry='Rykix:BAAANQADCgEIAQAAAA==.Rykò:BAABNQAECn8aAAIXAAYKeBvbkADnAQAXAAYKeBvbkADnAQAAAA==.',
['Ré']='Réckléssnéss:BAAANQAECgUIDgAAAA==.',
Sa='Salmorg:BAABNQAECn9IAAMfAAoKESMBBgD4AgAfAAoKESMBBgD4AgAHAAgK8h08KgBPAgAAAA==.Satinet:BAAANQAECgQIBQAAAA==.Sayafaed:BAABNQAECn87AAIfAAoKig4nGgDJAQAfAAoKig4nGgDJAQAAAA==.',
Sc='Scalen:BAAANQADCgYIBgAAAA==.Scatback:BAABNQAECn84AAIUAAoK0SLjBgC2AwAUAAoK0SLjBgC2AwAAAA==.Schwarzmagic:BAAANQAECgEIAwAAAA==.',
Sh='Shilor:BAABNQAECn8nAAMUAAoKhhVGOABHAgAUAAoKxxJGOABHAgAVAAMKgBUZFwC+AAAAAA==.Shogun:BAAANQAECgQIEgAAAA==.Shortsnack:BAAANQABCgMJAwAAAA==.',
Si='Sicarii:BAAANQAECggIEwAAAA==.Sicarrious:BAAANQADCggIEQABNQAECggIEwAEAAAAAA==.Sinatra:BAABNQAECn9IAAIkAAoK2iI3AwDHAwAkAAoK2iI3AwDHAwAAAA==.',
Sk='Skyarc:BAAANQAECgIICwABNQAECggIEwAEAAAAAA==.Skybolt:BAAANQAECgIIAgABNQAECggIEwAEAAAAAA==.Skylite:BAAANQAECggIEwAAAA==.Skyrak:BAAANQADCgQIBAABNQAECggIEwAEAAAAAA==.Skyrun:BAAANQAECgMIAQABNQAECggIEwAEAAAAAA==.',
Sn='Sneaksnstabs:BAAANQAECgYICgABNQAECgoKSwAKADMfAA==.',
So='Soulpurge:BAAANQADCgEIAQAAAA==.Soçks:BAAANQAECgEIAQAAAA==.',
Sp='Splat:BAAANQAECgUICAABNQAECgoKLAAGAAIdAA==.Spoopy:BAAANQADCggICAAAAA==.Spënny:BAAANQAECgQIBQAAAA==.',
St='Stélle:BAABNQAECn8yAAIBAAoKaQ1ALwDSAQABAAoKaQ1ALwDSAQAAAA==.',
Su='Supdude:BAABNQAECn8+AAIcAAoKzxzmBwD8AgAcAAoKzxzmBwD8AgAAAA==.',
Ta='Tatorz:BAAANQAECgQICAAAAA==.Tazbirkloa:BAAANQAECgEIBQAAAA==.Tazingo:BAAANQAECgQIBgABNQAECgoKMgAQANYdAA==.',
Te='Tentacrool:BAAANQABCgEIAQAAAA==.',
Ti='Tigas:BAABNQAECn8oAAMIAAoKSB6mQADIAgAIAAoKSB6mQADIAgALAAIKUSIBJQCJAAAAAA==.',
To='Tolally:BAABNQAFFH8HAAIfAAQKuRAeCADZAAAfAAQKuRAeCADZAAAAAA==.Tooth:BAAANQADCgQIBQAAAA==.',
Tr='Trashdragon:BAABNQAECn8uAAMFAAoK4RqDDACbAgAFAAkKcR6DDACbAgAOAAQKsg7AEwCRAAAAAA==.Trashshaman:BAAANQAECgMIAwAAAA==.Trauma:BAAANQAECgYIBwAAAA==.',
Tu='Turtlebear:BAAANQADCgIIAgABNQAECgUIBgAEAAAAAA==.',
Ty='Typhoonz:BAAANQADCgYIBgAAAA==.',
Ur='Uróboros:BAAANQADCgEIAQAAAA==.',
Vi='Vipex:BAAANQAECgIIBAAAAA==.',
Vo='Vore:BAAANQAECgEIAQAAAA==.',
Vy='Vynii:BAABNQAECn81AAMHAAoK+RcMGQA5AgAHAAoK+RcMGQA5AgAfAAIK9gODZQBTAAAAAA==.',
Wa='Wallofstars:BAAANQADCgQIBQAAAA==.Wardamage:BAAANQABCgEIAQAAAA==.Wasabi:BAABNQAECn8eAAINAAcKJBlUFQCIAQANAAcKJBlUFQCIAQAAAA==.',
We='Wey:BAABNQAECn8YAAMUAAkKWhGVWgC9AQAUAAgKZBCVWgC9AQAlAAUKJA0tMwDfAAAAAA==.',
Wo='Wonon:BAAANQAECgEIAQAAAA==.',
Xa='Xaida:BAAANQAECgYICgABNQAFFAoKRQANAEEUAA==.Xalant:BAAANQADCggICQAAAA==.',
Yo='Yourhammy:BAAANQADCgMIAwAAAA==.Yoyo:BAAANQAECgIJAgAAAA==.',
Yt='Ytteriul:BAAANQADCgYIEgAAAA==.',
Za='Zangyaku:BAABNQAECn8zAAISAAoKAyYfBwAQAwASAAoKAyYfBwAQAwAAAA==.Zanmetsu:BAAANQAECgUIBQABNQAECgoKMwASAAMmAA==.',
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
