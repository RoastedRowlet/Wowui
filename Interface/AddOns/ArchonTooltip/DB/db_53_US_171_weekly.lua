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

local lookup = {'Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Evoker-Devastation','Paladin-Holy','DemonHunter-Havoc','Warrior-Arms','Warrior-Protection','DeathKnight-Unholy','Warrior-Fury','Paladin-Protection','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Vengeance','Mage-Arcane','Mage-Frost','DeathKnight-Blood','Druid-Balance','Priest-Holy','Priest-Discipline','Hunter-BeastMastery','Monk-Mistweaver','Druid-Guardian','Paladin-Retribution','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','DemonHunter-Devourer','DeathKnight-Frost','Druid-Feral','Warlock-Demonology','Druid-Restoration',}
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abrams:BAAANQAECgYIDwAAAA==.',
Ad='Addý:BAAANQAECggIDwAAAA==.',
Ae='Aethyra:BAAANQAECgUICQAAAA==.',
Ah='Ahimsa:BAABNQAECn8rAAIBAAoK0xHqDQDwAQABAAoK0xHqDQDwAQAAAA==.',
Ai='Ailisuuith:BAABNQAECn8ZAAMCAAkKvAj/4wCiAAACAAYKtQX/4wCiAAADAAcK2QucfgChAAAAAA==.',
Al='Almamun:BAAANQADCgYIDgAAAA==.',
Ar='Arcanemommy:BAAANQAECgEIAQAAAA==.Arcz:BAAANQAECgcIDQABNQAECggICAAEAAAAAA==.',
As='Ashenclaw:BAACNQAFFH8GAAIFAAMK9w/qAwCIAAAFAAMK9w/qAwCIAAA1AAQKfz4AAgUACgqZF8EEABkCAAUACgqZF8EEABkCAAAA.',
At='Athalena:BAAANQAECgQIBgABNQAECgkJMwAGACUTAA==.',
Au='Auzatryx:BAAANQAECgUIBQAAAA==.',
Ba='Babs:BAAANQABCgIIAgABNQAECggIHQAHAIoLAA==.Babyboo:BAAANQADCgcIFAAAAA==.Bamboom:BAAANQAECgEIAwAAAA==.',
Bi='Biggrnmonstr:BAABNQAECn8aAAMIAAkKOg1FtwCSAQAIAAkK8QtFtwCSAQAJAAEKdRb6QwAyAAABNQAECgoKOwAKAPwdAA==.Bigxthezug:BAABNQAECn8bAAMDAAkKxh2SMwCrAgADAAkKxh2SMwCrAgACAAMKowWu9wB7AAAAAA==.',
Bl='Blaine:BAAANQADCgcIEgAAAA==.',
Bo='Bongripa:BAAANQABCgEIAQAAAA==.Bonquiqui:BAAANQADCgcIDAAAAA==.Boypartz:BAABNQAECn8yAAIIAAoKqBhJKgA2AgAIAAoKqBhJKgA2AgAAAA==.',
Br='Braidedbewbs:BAAANQAECgEIAQAAAA==.Breakfast:BAAANQADCgMIAwABNQAECgkJGwADAMYdAA==.Brittinia:BAAANQAECgIIBAAAAA==.',
Bu='Bulbasaurus:BAACNQAFFH8IAAILAAYKqiReAAA0AQALAAYKqiReAAA0AQA1AAQKfzkAAgsACgqXJjwAAPQDAAsACgqXJjwAAPQDAAAA.Bus:BAACNQAFFH8fAAIMAAgK0yYTAAC+AgAMAAgK0yYTAAC+AgA1AAQKfzMAAgwACgr9JgkAAKYDAAwACgr9JgkAAKYDAAAA.',
By='Bylunn:BAAANQADCgEIAQAAAA==.',
Ca='Cactusjuicee:BAAANQAECgEIAQAAAA==.',
Ce='Celeres:BAABNQAECn9KAAMNAAoKERstDQDTAgANAAoKERstDQDTAgAOAAcK8wUdCgDsAAAAAA==.Celesdria:BAAANQADCgMIAwABNQAECgoKSgANABEbAA==.Celys:BAAANQADCgIIAgAAAA==.Ceo:BAABNQAECn8gAAMGAAoK9h/UGQB1AgAGAAoK9h/UGQB1AgAMAAUKCQ/VQwDjAAAAAA==.',
Ch='Channie:BAAANQABCgMIBAAAAA==.Chios:BAAANQAECgcIBwABNQABCgIIAwAEAAAAAA==.',
De='Deadcell:BAABNQAECn8hAAMPAAkKlRl4BAAJAgAPAAkKlRl4BAAJAgAHAAMKbAvWdQCiAAAAAA==.Denamage:BAACNQAFFH8WAAMQAAcKUgrUDAAwAQAQAAcKUgrUDAAwAQARAAEKuwQ7FgA8AAA1AAQKfysAAxAACgpVGCF/AIACABAACgpVGCF/AIACABEABQoiCS8nALkAAAAA.Denarrage:BAAANQAFFAEIAQAAAA==.',
Di='Disconnect:BAAANQABCgIJAwAAAA==.',
Do='Dokuganryu:BAAANQADCgIIAgABNQAECgoKLwASAOIlAA==.Dontnerfspls:BAAANQAECgIIAgABNQAECgoKOwAKAPwdAA==.Donzul:BAAANQADCgUIBQAAAA==.Doomtickle:BAAANQADCgYIBgAAAA==.',
Ea='Earthigga:BAAANQAECgUICgAAAA==.',
Ei='Eichmann:BAAANQAECgIIAgAAAA==.',
El='Eldruida:BAACNQAFFH8JAAITAAIKZAzhEQCMAAATAAIKZAzhEQCMAAA1AAQKf0MAAhMACgofGSEQAEUCABMACgofGSEQAEUCAAAA.Elixxi:BAAANQADCgYIBgAAAA==.Ellipsoro:BAABNQAECn8ZAAIKAAcKHRg1MgD9AAAKAAcKHRg1MgD9AAAAAA==.Eltrol:BAAANQAECgEIAwAAAA==.',
En='Enoc:BAAANQAECgIIAwAAAA==.',
Er='Erale:BAAANQAECgEIAgAAAA==.',
Fa='Faeris:BAACNQAFFH8IAAIUAAUKEg1oFABkAQAUAAUKEg1oFABkAQA1AAQKfyQAAxQACgp1H1odAPwCABQACgp1H1odAPwCABUABAq/GZIPADIBAAAA.Fatalis:BAACNQAFFH8OAAMWAAUKUQo0EADKAAAWAAUKUQo0EADKAAABAAEKAAAZKQAeAAA1AAQKfz4AAxYACgo4GnYgAGcCABYACgo4GnYgAGcCAAEAAQoAAJaYACgAAAAA.',
Fe='Fedqt:BAAANQAECgIIBAAAAA==.Felko:BAAANQAECgYIBgAAAA==.',
Fi='Fiestykitten:BAAANQAECgEIAQAAAA==.Fizaw:BAABNQAECn8mAAIXAAoKjgyXGwDJAQAXAAoKjgyXGwDJAQAAAA==.',
Fl='Floydmagussy:BAACNQAFFH8MAAIQAAUKESACGQCxAQAQAAUKESACGQCxAQA1AAQKfx8AAhAACQphI2Y3ABoDABAACQphI2Y3ABoDAAAA.',
Fo='Foamdk:BAAANQADCggICwAAAA==.',
Fr='Freezypuff:BAAANQAECgcIBQAAAA==.Frostee:BAAANQAECgEIAQAAAA==.Frøzen:BAABNQAECn8WAAIQAAUKbQUC5ACOAAAQAAUKbQUC5ACOAAAAAA==.',
Fu='Fuzzydots:BAAANQAECgQIBAABNQAECgcICwAEAAAAAA==.',
Ga='Gamu:BAAANQADCgMIAwAAAA==.Gaurr:BAABNQAECn8lAAIDAAkKDhJqbADbAQADAAkKDhJqbADbAQAAAA==.',
Ge='Geneviere:BAAANQADCgMIAwAAAA==.',
Gi='Gianna:BAAANQAECgYICQAAAA==.Gislain:BAAANQADCgcIDQAAAA==.',
Go='Goldeye:BAAANQADCgYIEwAAAA==.',
Gr='Greyspirit:BAABNQAECn86AAIYAAoK0CJOAwCFAwAYAAoK0CJOAwCFAwAAAA==.Grimothy:BAABNQAECn8hAAMCAAoKThioDgDiAgACAAoKThioDgDiAgADAAMK+Q0E+QChAAAAAA==.',
Gu='Gulohof:BAAANQADCgEIAQAAAA==.',
Ha='Halcoldrek:BAAANQADCgQJBAAAAA==.',
Hb='Hbc:BAACNQAFFH8FAAIYAAUKjxKPAgDTAAAYAAUKjxKPAgDTAAA1AAQKfxkAAhgACgqWISEDAAgDABgACgqWISEDAAgDAAE1AAEKAggDAAQAAAAA.',
He='Healarious:BAAANQAECgUIEAAAAA==.Hembrota:BAAANQADCgcIEgAAAA==.Heyz:BAAANQAECggICAAAAA==.',
Hi='Himbo:BAABNQAECn8YAAIWAAYKIQgf0QBeAQAWAAYKIQgf0QBeAQAAAA==.',
Ho='Hogs:BAAANQAECgQIDgABNQAECgkJGwADAMYdAA==.Holypoopp:BAABNQAECn8lAAMGAAoKCxydJQDUAgAGAAoKCxydJQDUAgAZAAcK+Am3rwD4AAAAAA==.Holyreturn:BAABNQAECn8yAAIGAAoKyxzWLwCnAgAGAAoKyxzWLwCnAgAAAA==.',
Hw='Hwasin:BAAANQADCgYICAABNQAECggICAAEAAAAAA==.',
Il='Illanyth:BAAANQADCgUIBQAAAA==.Illidaldin:BAAANQADCgYIBgABNQAECgoKKwAaALoXAA==.',
Im='Imran:BAACNQAFFH8MAAIMAAMK4xsYCADjAAAMAAMK4xsYCADjAAA1AAQKf0IAAgwACgpwIbkFAFIDAAwACgpwIbkFAFIDAAAA.',
In='Inthelayer:BAAANQADCgYIBgABNQAECgkJGwADAMYdAA==.',
Je='Jether:BAAANQAECgEIAQAAAA==.',
Jo='Jojobaggins:BAABNQAECn86AAQbAAoK5CBNDgC7AgAcAAgK5B46FwDCAgAbAAoKJCBNDgC7AgAdAAQKzxXIEAANAQAAAA==.',
Kc='Kcthegreat:BAAANQADCgQIBQAAAA==.',
Ke='Keyholes:BAACNQAFFH8gAAISAAkKNhxSAwBgAgASAAkKNhxSAwBgAgA1AAQKfx8AAhIACQrvIowUAAgDABIACQrvIowUAAgDAAE1AAEKAggDAAQAAAAA.Keyohs:BAAANQADCgcICAABNQABCgIIAwAEAAAAAA==.',
Ki='Kirky:BAAANQADCgUIBgAAAA==.',
Kk='Kkoda:BAAANQAECgYICAAAAA==.',
Ko='Koal:BAABNQAECn8oAAIWAAcKoRYhYQB8AQAWAAcKoRYhYQB8AQAAAA==.Kodabear:BAAANQADCggICAAAAA==.',
Kr='Kraz:BAAANQADCgYIBgAAAA==.Kronos:BAAANQADCgYIBgABNQAECgoKHgAMAFQRAA==.',
Ku='Kushage:BAAANQADCgMIAwAAAA==.',
['Kí']='Kírky:BAAANQADCgIIAwABNQADCgUIBgAEAAAAAA==.',
Le='Lettussy:BAACNQAFFH8aAAMbAAcK1iJDAgDjAQAbAAYKSh1DAgDjAQAcAAUK+CSCBQDWAQA1AAQKfzcAAxwACgrWJUwCALsDABwACQogJkwCALsDABsACAqxJD8LAN8CAAAA.',
Li='Lixxi:BAABNQAECn83AAIUAAoK1hxnJwDNAgAUAAoK1hxnJwDNAgAAAA==.',
Lu='Luminyssa:BAAANQAECgQIBwAAAA==.',
['Lú']='Lúthien:BAAANQAECggIEQAAAA==.',
Ma='Maeby:BAAANQAECgYIBQAAAA==.Magicwater:BAACNQAFFH8bAAIQAAYK6SGeBgCCAQAQAAYK6SGeBgCCAQA1AAQKfzcAAhAACgoMJL8dAGEDABAACgoMJL8dAGEDAAAA.Magigga:BAAANQAECgYIAwAAAA==.',
Me='Meeoowzer:BAABNQAECn8yAAIGAAoKSR0nHgBUAgAGAAoKSR0nHgBUAgAAAA==.Meloo:BAABNQAECn8dAAIHAAgKigsnKwBDAQAHAAgKigsnKwBDAQAAAA==.',
Mo='Mollyflo:BAAANQAECgYIDQAAAA==.Mollymauk:BAABNQAECn8zAAMGAAkKJRPeZgDjAQAGAAkKJRPeZgDjAQAZAAgKZQ2yrgDCAQAAAA==.Moorality:BAABNQAFFH8FAAIMAAIKtR3nBQCaAAAMAAIKtR3nBQCaAAABNQABCgIIAwAEAAAAAA==.Moretino:BAAANQADCgEIAQAAAA==.Morgane:BAAANQADCgEIAQAAAA==.Mothra:BAABNQAECn8YAAICAAoKgBCgSwBnAQACAAoKgBCgSwBnAQABNQAFFAUIEAABALcOAA==.',
Mu='Muhjo:BAAANQADCgYIDQAAAA==.Muppet:BAABNQAECn8UAAIYAAgK6RNgGABLAQAYAAgK6RNgGABLAQAAAA==.Murryjane:BAAANQAECgcIDQABNQAECggICAAEAAAAAA==.Muufarmer:BAAANQAECgYICgAAAA==.',
Na='Natedk:BAAANQADCgUIBQAAAA==.',
Ne='Neyt:BAABNQAECn8wAAMeAAoKkB6LDAAaAwAeAAoKkB6LDAAaAwAHAAMKahGZcQCzAAAAAA==.',
Ni='Nitesrider:BAAANQAECgQIBQAAAA==.',
No='Nora:BAACNQAFFH8qAAMZAAoK0CAQAAAnAwAZAAoK0CAQAAAnAwAMAAEKAAAyDgBiAAA1AAQKf0YABBkACgrkJnADAOEDABkACgrjJnADAOEDAAwABwqiJgUJAA0DAAYACQotG/c7AHQCAAAA.Nostrodom:BAAANQADCgcIEQAAAA==.',
Nu='Nubbs:BAAANQAECgUIDgAAAA==.Nubheala:BAABNQAECn8hAAMUAAoKWyEFEABGAwAUAAoKWyEFEABGAwAVAAEKvg5CKgAvAAAAAA==.Nuri:BAABNQAECn8sAAIQAAoKvhztOwAPAwAQAAoKvhztOwAPAwAAAA==.',
Od='Odylight:BAAANQADCggICQAAAA==.',
Or='Orcazmo:BAAANQAECgcIEQAAAA==.',
Pa='Pandalorenzo:BAAANQADCgYIBwAAAA==.',
Pe='Peluij:BAAANQAECgQIBgAAAA==.',
Pi='Pingopango:BAAANQAECgYIDAABNQAECgkJGQAGAMMZAA==.Pinkdefender:BAAANQAECgQIBQABNQAECgoKOwAKAPwdAA==.Pinpanpum:BAAANQAECgEIAQAAAA==.',
Po='Pokeumon:BAAANQADCggIEwAAAA==.Poosistrox:BAABNQAECn87AAQKAAoK/B37GgDqAgAKAAkK7CD7GgDqAgAfAAoKhhCJPQDXAQASAAUK8hCSdAAkAQAAAA==.',
Ps='Pspspspsps:BAABNQAECn8WAAIgAAUKzg6NFwDIAAAgAAUKzg6NFwDIAAAAAA==.',
Pt='Ptheve:BAACNQAFFH8qAAIHAAoKhiUhAABNAwAHAAoKhiUhAABNAwA1AAQKfzQAAgcACgr1JhoAAJ8DAAcACgr1JhoAAJ8DAAAA.',
Pu='Punipuni:BAAANQABCgIIAgAAAA==.',
Qs='Qsham:BAAANQAECgUICAAAAA==.',
Qw='Qwarlock:BAABNQAECn8zAAMhAAoKixXqOQDCAQAhAAkKERTqOQDCAQAaAAEK5x+2IgBIAAAAAA==.',
Ra='Raela:BAACNQAFFH8LAAIfAAQK9Rh9CgDLAAAfAAQK9Rh9CgDLAAA1AAQKfzYAAh8ACQpIIaYWAB8CAB8ACQpIIaYWAB8CAAAA.Rahnarmight:BAAANQADCgMIAwAAAA==.Raygor:BAAANQAECgUIDAAAAA==.Razzle:BAAANQADCgIIAgABNQAECgoKLAAQAL4cAA==.',
Re='Renewal:BAAANQAECgUIBQAAAA==.',
Ri='Rickthyr:BAAANQAECgUIDAAAAA==.Rigger:BAAANQADCgYJBgABNQAECgQIBQAEAAAAAA==.Rizzerz:BAAANQADCgcIBwAAAA==.',
Ro='Rodgozinya:BAAANQADCggIBwABNQAECgoKMgAIAKgYAA==.Rosewalker:BAAANQAECgYIEAABNQAFFAYIGwAQAOkhAA==.Rosewall:BAAANQADCgIIAgABNQAFFAYIGwAQAOkhAA==.Rottgut:BAAANQADCgEIAQAAAA==.',
Ru='Rumog:BAAANQAECgUIDAAAAA==.',
Ry='Rykix:BAAANQADCgEIAQAAAA==.Rykò:BAABNQAECn8aAAIWAAYKeBvbkADnAQAWAAYKeBvbkADnAQAAAA==.',
['Ré']='Réckléssnéss:BAAANQAECgUIBAAAAA==.',
Sa='Salmorg:BAABNQAECn87AAMeAAoKWSAjEwDRAgAeAAkKnR8jEwDRAgAHAAgK8h08KgBPAgAAAA==.Sayafaed:BAABNQAECn8yAAIeAAoK7Q1REQDVAQAeAAoK7Q1REQDVAQAAAA==.',
Sc='Scalen:BAAANQADCgYIBgAAAA==.Scatback:BAABNQAECn8yAAIUAAoKUCFeBACnAwAUAAoKUCFeBACnAwAAAA==.Schwarzmagic:BAAANQADCggIEgAAAA==.',
Sh='Shilor:BAABNQAECn8aAAMUAAkKFxMaWgBMAQAUAAkKChAaWgBMAQAVAAMKgBUZFwC+AAAAAA==.Shogun:BAAANQAECgMICgAAAA==.Shortsnack:BAAANQABCgMJAwAAAA==.',
Si='Sicarii:BAAANQAECgcJEAAAAA==.Sicarrious:BAAANQADCggIEQABNQAECgcJEAAEAAAAAA==.Sinatra:BAABNQAECn81AAIiAAoK8B1GBwDoAgAiAAoK8B1GBwDoAgAAAA==.',
Sk='Skyarc:BAAANQAECgIIBAABNQAECggIEwAEAAAAAA==.Skybolt:BAAANQAECgIIAgABNQAECggIEwAEAAAAAA==.Skylite:BAAANQAECggIEwAAAA==.Skyrak:BAAANQADCgQIBAABNQAECggIEwAEAAAAAA==.Skyrun:BAAANQAECgMIAQABNQAECggIEwAEAAAAAA==.',
Sn='Sneaksnstabs:BAAANQAECgUIBwABNQAECgoKOwAKAPwdAA==.',
So='Soulpurge:BAAANQADCgEIAQAAAA==.',
Sp='Splat:BAAANQAECgUIBgABNQAECgoKJQAGAAscAA==.Spoopy:BAAANQADCggICAAAAA==.Spënny:BAAANQAECgQIBQAAAA==.',
St='Stélle:BAABNQAECn8rAAIBAAgKng5ALwDSAQABAAgKng5ALwDSAQAAAA==.',
Su='Supdude:BAABNQAECn8yAAIbAAoKlBzmBwD8AgAbAAoKlBzmBwD8AgAAAA==.',
Sy='Sycoraxx:BAAANQABCgIIAgAAAA==.',
Ta='Tatorz:BAAANQAECgQICAAAAA==.',
Te='Tentacrool:BAAANQABCgEIAQAAAA==.',
Ti='Tigas:BAABNQAECn8iAAMIAAoK/BymQADIAgAIAAoK/BymQADIAgALAAIKUSIBJQCJAAAAAA==.',
To='Tolally:BAAANQAECgcICAAAAA==.Tooth:BAAANQADCgQIBQAAAA==.',
Tr='Trashdragon:BAABNQAECn8uAAMFAAoK4RqDDACbAgAFAAkKcR6DDACbAgAOAAQKsg5CDgCaAAAAAA==.Trashshaman:BAAANQAECgMIAwAAAA==.Trauma:BAAANQAECgYIBwAAAA==.',
Tu='Turtlebear:BAAANQADCgIIAgABNQAECgcIBQAEAAAAAA==.',
Ty='Typhoonz:BAAANQADCgYIBgAAAA==.',
Ur='Uróboros:BAAANQADCgEIAQAAAA==.',
Vi='Vipex:BAAANQAECgIIAwAAAA==.',
Vy='Vynii:BAABNQAECn8oAAMHAAoKOxZmHwCfAgAHAAoKOxZmHwCfAgAeAAIK9gODZQBTAAAAAA==.',
Wa='Wallofstars:BAAANQADCgQIBQAAAA==.Wardamage:BAAANQABCgEIAQAAAA==.Wasabi:BAABNQAECn8YAAINAAYKCxqLEQBSAQANAAYKCxqLEQBSAQAAAA==.',
We='Wey:BAAANQAECgcIBwAAAA==.',
Wo='Wonon:BAAANQAECgEIAQAAAA==.',
Xa='Xaida:BAAANQAECgYICgABNQAFFAoKPAANAJcTAA==.Xalant:BAAANQADCggICQAAAA==.',
Yo='Yourhammy:BAAANQADCgMIAwAAAA==.Yoyo:BAAANQAECgIJAgAAAA==.',
Yt='Ytteriul:BAAANQADCgYIEgAAAA==.',
Za='Zangyaku:BAABNQAECn8vAAISAAoK4iU+BAAeAwASAAoK4iU+BAAeAwAAAA==.Zanmetsu:BAAANQAECgUIBQABNQAECgoKLwASAOIlAA==.',
Ze='Zenis:BAABNQAECn8ZAAIGAAkKwxnAJgDOAgAGAAkKwxnAJgDOAgAAAA==.Zerocool:BAAANQADCgYIBgAAAA==.Zerø:BAAANQADCgIIAgAAAA==.Zetsuï:BAAANQAECgcIEwAAAA==.',
['ßa']='ßadfish:BAABNQAECn8hAAIZAAoKDSOfDgCSAwAZAAoKDSOfDgCSAwAAAA==.',
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
