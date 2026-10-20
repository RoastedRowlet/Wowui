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

local lookup = {'Hunter-Marksmanship','Shaman-Elemental','Shaman-Restoration','Evoker-Devastation','Paladin-Holy','DemonHunter-Havoc','Warrior-Arms','Warrior-Protection','DeathKnight-Unholy','Warrior-Fury','Paladin-Protection','Evoker-Preservation','Unknown-Unknown','DemonHunter-Vengeance','Mage-Arcane','Mage-Frost','Druid-Balance','Priest-Holy','Priest-Discipline','Hunter-BeastMastery','Monk-Mistweaver','Paladin-Retribution','Druid-Guardian','Warlock-Destruction','Rogue-Assassination','Rogue-Outlaw','Rogue-Subtlety','DeathKnight-Blood','DemonHunter-Devourer','DeathKnight-Frost','Druid-Feral','Warlock-Demonology','Druid-Restoration','Evoker-Augmentation',}
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abrams:BAAANQAECgYIDwAAAA==.',
Ad='Addý:BAAANQAECggIDwAAAA==.',
Ae='Aethyra:BAAANQAECgUICQAAAA==.',
Ah='Ahimsa:BAABNQAECn8hAAIBAAkKvxFgIgA6AgABAAkKvxFgIgA6AgAAAA==.',
Ai='Ailisuuith:BAABNQAECn8WAAMCAAkKPRBtSgCwAAACAAcK2QttSgCwAAADAAUKuwX/4wCiAAAAAA==.',
Al='Almamun:BAAANQADCgYICAAAAA==.',
Ar='Arcanemommy:BAAANQAECgEIAQAAAA==.Arcz:BAAANQAECgcIDQAAAA==.',
As='Ashenclaw:BAACNQAFFH8GAAIEAAMK9w+BAgCLAAAEAAMK9w+BAgCLAAA1AAQKfzAAAgQACgpIF70LAKsCAAQACgpIF70LAKsCAAAA.',
At='Athalena:BAAANQAECgQIBgABNQAECgkJMQAFACUTAA==.',
Au='Auzatryx:BAAANQAECgUIBQAAAA==.',
Ba='Babs:BAAANQABCgIIAgABNQAECggIFgAGAF4KAA==.Babyboo:BAAANQADCgcIFAAAAA==.Bamboom:BAAANQAECgEIAwAAAA==.',
Bi='Biggrnmonstr:BAABNQAECn8aAAMHAAkKOg2AZQDOAAAHAAkK8QuAZQDOAAAIAAEKdRb6QwAyAAABNQAECgoKNgAJAPwdAA==.Bigxthezug:BAABNQAECn8bAAMCAAkKxh2SMwCrAgACAAkKxh2SMwCrAgADAAMKowWu9wB7AAAAAA==.',
Bl='Blaine:BAAANQADCgcIEgAAAA==.',
Bo='Bongripa:BAAANQABCgEIAQAAAA==.Bonquiqui:BAAANQADCgcIDAAAAA==.Boypartz:BAABNQAECn8oAAIHAAgKcxtkDgDnAQAHAAgKcxtkDgDnAQAAAA==.',
Br='Braidedbewbs:BAAANQAECgEIAQAAAA==.Breakfast:BAAANQADCgMIAwABNQAECgkJGwACAMYdAA==.Brittinia:BAAANQAECgIIBAAAAA==.',
Bu='Bulbasaurus:BAACNQAFFH8IAAIKAAYKqiQpAABCAQAKAAYKqiQpAABCAQA1AAQKfzEAAgoACgpZJjwAAPQDAAoACgpZJjwAAPQDAAAA.Bus:BAACNQAFFH8XAAILAAYK/SAHAgArAgALAAYK/SAHAgArAgA1AAQKfycAAgsACgrHJisAAAoEAAsACgrHJisAAAoEAAAA.',
By='Bylunn:BAAANQADCgEIAQAAAA==.',
Ca='Cactusjuicee:BAAANQAECgEIAQAAAA==.',
Ce='Celeres:BAABNQAECn89AAIMAAoKERstDQDTAgAMAAoKERstDQDTAgAAAA==.Celesdria:BAAANQADCgMIAwABNQAECgoKPQAMABEbAA==.Celys:BAAANQADCgIIAgAAAA==.Ceo:BAABNQAECn8ZAAMFAAcKEx63RABTAgAFAAcKEx63RABTAgALAAUKCQ/VQwDjAAAAAA==.',
Ch='Chios:BAAANQAECgcIBwABNQABCgIIAwANAAAAAA==.',
De='Deadcell:BAABNQAECn8bAAMOAAgKIxrbAQDTAQAOAAgKIxrbAQDTAQAGAAMKbAvWdQCiAAAAAA==.Denamage:BAACNQAFFH8RAAMPAAUK/A0QJQBfAQAPAAUK/A0QJQBfAQAQAAEKuwQ7FgA8AAA1AAQKfysAAw8ACgpVGCF/AIACAA8ACgpVGCF/AIACABAABQoiCS8nALkAAAAA.Denarrage:BAAANQAFFAEIAQAAAA==.',
Di='Disconnect:BAAANQABCgIJAwAAAA==.',
Do='Dontnerfspls:BAAANQAECgIIAgABNQAECgoKNgAJAPwdAA==.Doomtickle:BAAANQADCgYIBgAAAA==.',
Dr='Drakussy:BAAANQABCgMIAwABNQAECggIFgAGAF4KAA==.',
Ea='Earthigga:BAAANQAECgUICQAAAA==.',
Ei='Eichmann:BAAANQAECgIIAgAAAA==.',
El='Eldruida:BAACNQAFFH8HAAIRAAIKTgpSDQCBAAARAAIKTgpSDQCBAAA1AAQKfzgAAhEACgp+EwcFAP0BABEACgp+EwcFAP0BAAAA.Elixxi:BAAANQADCgYIBgAAAA==.Ellipsoro:BAABNQAECn8XAAIJAAcKHRhSGwAMAQAJAAcKHRhSGwAMAQAAAA==.Eltrol:BAAANQAECgEIAwAAAA==.',
En='Enoc:BAAANQAECgIIAgAAAA==.',
Er='Erale:BAAANQAECgEIAgAAAA==.',
Fa='Faeris:BAACNQAFFH8IAAISAAUKEg1oFABkAQASAAUKEg1oFABkAQA1AAQKfyMAAxIACQqFIVodAPwCABIACQqFIVodAPwCABMABAq/GZIPADIBAAAA.Fatalis:BAACNQAFFH8KAAMUAAQKTgYdGAD6AAAUAAQKTgYdGAD6AAABAAEKAAAZKQAeAAA1AAQKfzQAAxQACgoMFc1LAIoCABQACgoMFc1LAIoCAAEAAQoAAJaYACgAAAAA.',
Fe='Fedqt:BAAANQAECgIIBAAAAA==.Felko:BAAANQADCgIIAgAAAA==.',
Fi='Fiestykitten:BAAANQAECgEJAQAAAA==.Fizaw:BAABNQAECn8mAAIVAAoKjgyXGwDJAQAVAAoKjgyXGwDJAQAAAA==.',
Fl='Floydmagussy:BAACNQAFFH8MAAIPAAUKESACGQCxAQAPAAUKESACGQCxAQA1AAQKfx8AAg8ACQphI2Y3ABoDAA8ACQphI2Y3ABoDAAAA.',
Fo='Foamdk:BAAANQADCggIBAAAAA==.',
Fr='Freezypuff:BAAANQADCggICAAAAA==.Frostee:BAAANQAECgEIAQAAAA==.Frøzen:BAAANQAECgQIDgAAAA==.',
Fu='Fuzzydots:BAAANQADCgYIDQABNQAECgoKKQAWAKMbAA==.',
Ga='Gamu:BAAANQADCgMIAwAAAA==.Gaurr:BAABNQAECn8gAAICAAkKlhDWIQA0AQACAAkKlhDWIQA0AQAAAA==.',
Ge='Geneviere:BAAANQADCgMIAwAAAA==.',
Gi='Gianna:BAAANQAECgcICQAAAA==.Gislain:BAAANQADCgcIDQAAAA==.',
Go='Goldeye:BAAANQADCgYIEwAAAA==.',
Gr='Greyspirit:BAABNQAECn8wAAIXAAoKcSJOAwCFAwAXAAoKcSJOAwCFAwAAAA==.Grimothy:BAABNQAECn8XAAMDAAoKeQ0PgACMAQADAAoKeQ0PgACMAQACAAMK+Q0E+QChAAAAAA==.',
Ha='Halcoldrek:BAAANQADCgQJBAAAAA==.',
Hb='Hbc:BAAANQAECgcIDQABNQABCgIIAwANAAAAAA==.',
He='Healarious:BAAANQAECgUIDAAAAA==.Hembrota:BAAANQADCgcIEgAAAA==.Heyz:BAAANQAECgYIBwABNQAECgcIDQANAAAAAA==.',
Hi='Himbo:BAAANQAECgUIEQAAAA==.',
Ho='Hogs:BAAANQAECgQIDgABNQAECgkJGwACAMYdAA==.Holypoopp:BAABNQAECn8cAAMFAAoKNxmdJQDUAgAFAAkKLhudJQDUAgAWAAQKVQfT1ABYAAAAAA==.Holyreturn:BAABNQAECn8nAAIFAAkKWxrWLwCnAgAFAAkKWxrWLwCnAgAAAA==.',
Hw='Hwasin:BAAANQADCgQJBAABNQAECgcIDQANAAAAAA==.',
Il='Illanyth:BAAANQADCgUIBQAAAA==.Illidaldin:BAAANQADCgYIBgABNQAECgoKKQAYAKcUAA==.',
Im='Imran:BAACNQAFFH8MAAILAAMK4xsYCADjAAALAAMK4xsYCADjAAA1AAQKfzoAAgsACgpwIbkFAFIDAAsACgpwIbkFAFIDAAAA.',
In='Inthelayer:BAAANQADCgYIBgABNQAECgkJGwACAMYdAA==.',
Je='Jether:BAAANQAECgEIAQAAAA==.',
Jo='Jojobaggins:BAABNQAECn8tAAQZAAoKQB46FwDCAgAZAAgK5B46FwDCAgAaAAQKzxXIEAANAQAbAAUKsxk/LACtAAAAAA==.',
Kc='Kcthegreat:BAAANQADCgQIBQAAAA==.',
Ke='Keyholes:BAACNQAFFH8dAAIcAAgKrhtSAwBgAgAcAAgKrhtSAwBgAgA1AAQKfx8AAhwACQrvIowUAAgDABwACQrvIowUAAgDAAE1AAEKAggDAA0AAAAA.Keyohs:BAAANQADCgcICAABNQABCgIIAwANAAAAAA==.',
Ki='Kirky:BAAANQADCgUIBgAAAA==.',
Kk='Kkoda:BAAANQAECgIIAgAAAA==.',
Ko='Koal:BAABNQAECn8oAAIUAAcKoRYSHwCbAQAUAAcKoRYSHwCbAQAAAA==.Kodabear:BAAANQADCggICAAAAA==.',
Kr='Kraz:BAAANQADCgYIBQAAAA==.Kronos:BAAANQADCgYIBgABNQAECgoKHgALAFQRAA==.',
Ku='Kushage:BAAANQADCgMIAwAAAA==.',
['Kí']='Kírky:BAAANQADCgIIAwABNQADCgUIBgANAAAAAA==.',
Le='Lettussy:BAACNQAFFH8VAAMZAAYK4iKCBQDWAQAZAAUK+CSCBQDWAQAbAAQKDxhcBAARAQA1AAQKfy8AAxkACgpvJUwCALsDABkACQogJkwCALsDABsAAwrIHEQaAA4BAAAA.',
Li='Lixxi:BAABNQAECn8vAAISAAoK1RxnJwDNAgASAAoK1RxnJwDNAgAAAA==.',
Lu='Luminyssa:BAAANQAECgQIBwAAAA==.',
['Lú']='Lúthien:BAAANQAECggIEQAAAA==.',
Ma='Maeby:BAAANQADCgYIBgAAAA==.Magicwater:BAACNQAFFH8WAAIPAAUKECAWCgAKAQAPAAUKECAWCgAKAQA1AAQKfy0AAg8ACgprI78dAGEDAA8ACgprI78dAGEDAAAA.Magigga:BAAANQAECgYIAwAAAA==.',
Me='Meeoowzer:BAABNQAECn8pAAIFAAkKXx3cNgCIAgAFAAkKXx3cNgCIAgAAAA==.Meloo:BAABNQAECn8WAAIGAAgKXgpdSwB0AQAGAAgKXgpdSwB0AQAAAA==.',
Mo='Mollyflo:BAAANQAECgQICgAAAA==.Mollymauk:BAABNQAECn8xAAMFAAkKJRPeZgDjAQAFAAkKJRPeZgDjAQAWAAgKZQ3URAA8AQAAAA==.Moorality:BAAANQAFFAIIAwABNQABCgIIAwANAAAAAA==.Moretino:BAAANQADCgEIAQAAAA==.Morgane:BAAANQADCgEIAQAAAA==.Mothra:BAABNQAECn8WAAIDAAoKig8pHgByAQADAAoKig8pHgByAQABNQAFFAUIDAABAMIMAA==.',
Mu='Muhjo:BAAANQADCgYIDQAAAA==.Muppet:BAAANQAECgcIEAAAAA==.Murryjane:BAAANQAECgYIDQABNQAECgcIDQANAAAAAA==.Muufarmer:BAAANQAECgYICgAAAA==.',
Na='Natedk:BAAANQADCgUIBQAAAA==.',
Ne='Neyt:BAABNQAECn8sAAMdAAoK4RyLDAAaAwAdAAoK4RyLDAAaAwAGAAMKahGZcQCzAAAAAA==.',
Ni='Nitesrider:BAAANQAECgQIBAAAAA==.',
No='Nora:BAACNQAFFH8gAAMWAAkKIR+AAADzAgAWAAkKIR+AAADzAgALAAEKAAAyDgBiAAA1AAQKfz0ABBYACgrkJnADAOEDABYACgrjJnADAOEDAAsABwqiJgUJAA0DAAUACAqfHfc7AHQCAAAA.Nostrodom:BAAANQADCgcIEQAAAA==.',
Nu='Nubbs:BAAANQAECgQICQAAAA==.Nubheala:BAABNQAECn8fAAMSAAoKWyGEAwAAAwASAAoKWyGEAwAAAwATAAEKvg5CKgAvAAAAAA==.Nuri:BAABNQAECn8jAAIPAAkK4h7tOwAPAwAPAAkK4h7tOwAPAwAAAA==.',
Od='Odylight:BAAANQADCggICQAAAA==.',
Or='Orcazmo:BAAANQAECgcIDAAAAA==.',
Pa='Pandalorenzo:BAAANQADCgYIBwAAAA==.',
Pe='Peluij:BAAANQAECgQIBgAAAA==.',
Pi='Pingopango:BAAANQAECgYIDAABNQAECgkJGQAFAMMZAA==.Pinkdefender:BAAANQAECgMIBQABNQAECgoKNgAJAPwdAA==.Pinpanpum:BAAANQAECgEIAQAAAA==.',
Po='Pokeumon:BAAANQADCggIEwAAAA==.Poosistrox:BAABNQAECn82AAQJAAoK/B37GgDqAgAJAAkK7CD7GgDqAgAeAAoKhhCJPQDXAQAcAAUK8hCSdAAkAQAAAA==.',
Ps='Pspspspsps:BAABNQAECn8WAAIfAAUKzg4YDADdAAAfAAUKzg4YDADdAAAAAA==.',
Pt='Ptheve:BAACNQAFFH8gAAIGAAkKCSV4AAA5AwAGAAkKCSV4AAA5AwA1AAQKfysAAgYACgqdJnECAM8DAAYACgqdJnECAM8DAAAA.',
Pu='Punipuni:BAAANQABCgIIAgAAAA==.',
Qs='Qsham:BAAANQAECgUICAAAAA==.',
Qw='Qwarlock:BAABNQAECn8qAAMgAAoK8hQHGQCOAQAgAAkKYhMHGQCOAQAYAAEK5x9xYwBdAAAAAA==.',
Ra='Raela:BAACNQAFFH8LAAIeAAQK9RhfBgDPAAAeAAQK9RhfBgDPAAA1AAQKfy4AAh4ACQoYHbkdAJwCAB4ACQoYHbkdAJwCAAAA.Rahnarmight:BAAANQADCgMIAwAAAA==.Raygor:BAAANQAECgUIDAAAAA==.Razzle:BAAANQADCgIIAgABNQAECgkJIwAPAOIeAA==.',
Re='Renewal:BAAANQAECgUIBQAAAA==.',
Ri='Rickthyr:BAAANQAECgUIDAAAAA==.Rigger:BAAANQADCgYJBgABNQAECgQIBQANAAAAAA==.Rizzerz:BAAANQADCgcIBwAAAA==.',
Ro='Rosewalker:BAAANQAECgYIEAABNQAFFAUIFgAPABAgAA==.Rosewall:BAAANQADCgIIAgABNQAFFAUIFgAPABAgAA==.Rottgut:BAAANQADCgEIAQAAAA==.',
Ru='Rumog:BAAANQAECgUIDAAAAA==.',
Ry='Rykix:BAAANQADCgEIAQAAAA==.Rykò:BAABNQAECn8aAAIUAAYKeBvbkADnAQAUAAYKeBvbkADnAQAAAA==.',
Sa='Salmorg:BAABNQAECn83AAMdAAoKQR4jEwDRAgAdAAkKuhwjEwDRAgAGAAgK8h08KgBPAgAAAA==.Sayafaed:BAABNQAECn8oAAIdAAoKlQq7KAD+AQAdAAoKlQq7KAD+AQAAAA==.',
Sc='Scalen:BAAANQADCgYIBgAAAA==.Scatback:BAABNQAECn8oAAISAAoK1ByeDAAdAgASAAoK1ByeDAAdAgAAAA==.Schwarzmagic:BAAANQADCggIEgAAAA==.',
Sh='Shilor:BAAANQAECgYIEgAAAA==.Shogun:BAAANQAECgMIBwAAAA==.Shortsnack:BAAANQABCgMJAwAAAA==.',
Si='Sicarii:BAAANQAECgcJEAAAAA==.Sicarrious:BAAANQADCggIEQABNQAECgcJEAANAAAAAA==.Sinatra:BAABNQAECn8rAAIhAAoKZB1LCwAVAwAhAAoKZB1LCwAVAwAAAA==.',
Sk='Skyarc:BAAANQAECgIIBAABNQAECggIEwANAAAAAA==.Skybolt:BAAANQAECgIIAgABNQAECggIEwANAAAAAA==.Skylite:BAAANQAECggIEwAAAA==.Skyrak:BAAANQADCgQIBAABNQAECggIEwANAAAAAA==.Skyrun:BAAANQAECgMIAQABNQAECggIEwANAAAAAA==.',
Sn='Sneaksnstabs:BAAANQAECgIIAwABNQAECgoKNgAJAPwdAA==.',
So='Soulpurge:BAAANQADCgEIAQAAAA==.',
Sp='Splat:BAAANQAECgUIBgABNQAECgoKHAAFADcZAA==.Spoopy:BAAANQADCggICAAAAA==.Spënny:BAAANQAECgQIBQAAAA==.',
St='Stélle:BAABNQAECn8rAAIBAAgKng5ALwDSAQABAAgKng5ALwDSAQAAAA==.',
Su='Supdude:BAABNQAECn8sAAIbAAoKGRvmBwD8AgAbAAoKGRvmBwD8AgAAAA==.',
Sy='Sycoraxx:BAAANQABCgIIAgAAAA==.',
Ta='Tatorz:BAAANQAECgQICAAAAA==.Tazbirkloa:BAAANQADCgUIDwAAAA==.',
Ti='Tigas:BAABNQAECn8iAAMHAAoK/BymQADIAgAHAAoK/BymQADIAgAKAAIKUSIBJQCJAAAAAA==.',
To='Tolally:BAAANQAECgEIAgAAAA==.Tooth:BAAANQADCgQIBQAAAA==.',
Tr='Trashdragon:BAABNQAECn8kAAMEAAgKXh6DDACbAgAEAAgKXh6DDACbAgAiAAMKERUKCQB9AAAAAA==.Trashshaman:BAAANQAECgMIAwAAAA==.Trauma:BAAANQAECgEIAQAAAA==.',
Ty='Typhoonz:BAAANQADCgYIBgAAAA==.',
Ur='Uróboros:BAAANQADCgEIAQAAAA==.',
Vi='Vipex:BAAANQAECgIIAwAAAA==.',
Vo='Vore:BAAANQADCgYIBgAAAA==.',
Vy='Vynii:BAABNQAECn8eAAMGAAkKCBdmHwCfAgAGAAkKCBdmHwCfAgAdAAIK9gODZQBTAAAAAA==.',
Wa='Wallofstars:BAAANQADCgQIBQAAAA==.Wardamage:BAAANQABCgEIAQAAAA==.Wasabi:BAAANQAECgUIEQAAAA==.',
Wo='Wonon:BAAANQAECgEIAQAAAA==.',
Xa='Xaida:BAAANQAECgYICgABNQAFFAoKNQAMACYSAA==.Xalant:BAAANQADCggICQAAAA==.',
Yo='Yourhammy:BAAANQADCgMIAwAAAA==.Yoyo:BAAANQAECgIJAgAAAA==.',
Yt='Ytteriul:BAAANQADCgYIEgAAAA==.',
Za='Zangyaku:BAABNQAECn8lAAIcAAgK7yWRCgBgAwAcAAgK7yWRCgBgAwAAAA==.Zanmetsu:BAAANQAECgUIBQABNQAECggIJQAcAO8lAA==.',
Ze='Zenis:BAABNQAECn8ZAAIFAAkKwxnAJgDOAgAFAAkKwxnAJgDOAgAAAA==.Zerocool:BAAANQADCgYIBgAAAA==.Zerø:BAAANQADCgIIAgAAAA==.Zetsuï:BAAANQAECgcIEwAAAA==.',
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
