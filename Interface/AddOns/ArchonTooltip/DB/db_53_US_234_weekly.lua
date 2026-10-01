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

local lookup = {'Unknown-Unknown','Mage-Frost','Mage-Arcane','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Warrior-Arms','DemonHunter-Devourer','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Hunter-BeastMastery','Warrior-Protection','Paladin-Retribution','DeathKnight-Frost','Priest-Shadow','Priest-Holy','Hunter-Marksmanship','DemonHunter-Vengeance','Shaman-Elemental','Shaman-Restoration','Druid-Balance','DeathKnight-Blood','Monk-Mistweaver','Evoker-Preservation','Warrior-Fury','Shaman-Enhancement','Druid-Guardian','Monk-Windwalker','Druid-Restoration','Monk-Brewmaster',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abel:BAEANQADCggICAABNQAECgIIBgABAAAAAA==.',
Ae='Aeidail:BAACNQAFFIEMAAMCAAUKZheOAwCvAAADAAMKChZTIQD+AAACAAIKcBmOAwCvAAA1AAQKgSgAAwIACQrqI/0DALcCAAMACQpdIEU9AOwCAAIABwqaI/0DALcCAAAA.',
Ag='Agraceful:BAAANQAECgUIBgAAAA==.',
Ai='Aidton:BAAANQAECgEIAQAAAA==.Aiobhicefall:BAAANQAECgMIBAAAAA==.Aiobhicefell:BAAANQAECgQICAAAAA==.Aiobhoicefal:BAAANQAECgUICQAAAA==.Aiobicefall:BAAANQAECgQIBQAAAA==.Aiza:BAABNQAECoEnAAQEAAkKchg8CgCBAQAFAAcKNRc+UAAbAgAEAAYKXhE8CgCBAQAGAAMKkgu4QACrAAAAAA==.',
Al='Albinoknight:BAAANQADCgEIAQAAAA==.Alessia:BAAANQADCgYICgAAAA==.',
An='Angrypants:BAAANQAECgQIBQAAAA==.Animalfriend:BAAANQADCggJDgAAAA==.Anklesmasher:BAAANQAECgEIAQAAAA==.Antisocial:BAAANQADCggIEAABNQAECgkKHgAHAPYfAA==.',
Ar='Arfaz:BAAANQAECgYICQAAAA==.Arçano:BAAANQADCgMIAwABNQAECggIGAAIAN0SAA==.',
As='Astramoon:BAAANQAECgIIBAAAAA==.',
Ba='Baerd:BAAANQADCgcICQAAAA==.Barlz:BAAANQADCgUIEwAAAA==.',
Be='Beasthunt:BAAANQAECgMIBgAAAA==.Beatmywillie:BAAANQAECgUIBQAAAA==.Bebby:BAAANQAECgIIBAAAAA==.Belwolf:BAAANQADCgYIEwAAAA==.Bennehona:BAAANQADCgEIAQAAAA==.Bergstrom:BAAANQAECgYIEwAAAA==.',
Bi='Biancafiamma:BAAANQAECgIIAgAAAA==.Biancaneve:BAAANQAECgUIEQAAAA==.',
Bo='Bombacløt:BAAANQAECgUICgAAAA==.',
Br='Brastin:BAAANQAECgUIDQAAAA==.Brenell:BAABNQAECoEaAAIDAAcKtBarqQDkAQADAAcKtBarqQDkAQAAAA==.',
Bu='Bubblehearth:BAAANQAECgEIAQABNQAFFAUICwAJANwDAA==.',
Ca='Cabëla:BAAANQAECgQIBAABNQAECgQIBQABAAAAAA==.Calacolinda:BAAANQAECgQICgAAAA==.',
Ce='Celestiall:BAAANQAECgEIAQAAAA==.Ceridwyn:BAAANQADCgYIEQAAAA==.',
Ch='Chadalonius:BAAANQADCgQIBAABNQAECgkJIwAKAGgdAA==.Cheesecurd:BAAANQAECgIIAgAAAA==.Choal:BAAANQADCgYICwAAAA==.',
Cl='Claytonbigsb:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.',
Co='Corahin:BAAANQAECgQIBAAAAA==.',
Cu='Cuecumba:BAAANQAECgQIBAAAAA==.',
Da='Dalren:BAACNQAFFIEIAAILAAQKBxA+BQArAQALAAQKBxA+BQArAQA1AAQKgS8AAwsACQpVHTwGAAMDAAsACQpCHTwGAAMDAAwAAgpnHeUUAIwAAAAA.Dalvix:BAAANQAECgIIAwABNQAECgUIDwABAAAAAA==.Dammedude:BAAANQABCgMIAwAAAA==.Dartagnan:BAABNQAECoEWAAINAAcKnhPrcQDSAQANAAcKnhPrcQDSAQAAAA==.Darthmaul:BAAANQAECgcIEgAAAA==.Daveykrook:BAAANQADCgYIBgABNQAECgUIDQABAAAAAA==.David:BAAANQAECgUIBgAAAA==.',
De='Dendiian:BAAANQADCgYICQAAAA==.Depletor:BAABNQAECoEXAAMIAAcKiAZctwAjAQAIAAcKZQZctwAjAQAOAAMK4wKRLQBZAAAAAA==.',
Di='Diem:BAAANQAECgIIAgAAAA==.Dirtydotss:BAAANQADCgYICwAAAA==.',
Do='Docholiday:BAAANQAECgQICQAAAA==.Docsassist:BAAANQAECgQIBQAAAA==.Dowedoes:BAABNQAECoEcAAIPAAgKhgnTlACOAQAPAAgKhgnTlACOAQAAAA==.',
Dr='Drachula:BAAANQAECgIIBAAAAA==.Dracultra:BAAANQADCgYIBgABNQAECgUIEQABAAAAAA==.Draeun:BAAANQAECgEIAQABNQAFFAQICAALAAcQAA==.Dreolan:BAAANQAECgUICgAAAA==.Druaga:BAAANQAECggICAAAAA==.Dràchula:BAAANQADCgYICAAAAA==.Dràúgr:BAAANQADCgMIAwAAAA==.',
Dy='Dyala:BAAANQAECgYIEAAAAA==.',
Dz='Dzznuts:BAAANQABCgYICgAAAA==.',
['Dé']='Démonléth:BAAANQAECgIJAgABNQAECgkJIQAQAEgXAA==.',
['Dö']='Dönövan:BAAANQAECgUICgAAAA==.',
Eg='Eggyolk:BAAANQAECgUIEwAAAA==.',
El='Elastwo:BAAANQADCgcIDwAAAA==.Eloise:BAAANQAECgEIAQAAAA==.Elvenbane:BAABNQAECoEcAAMRAAgKwg59IgDSAQARAAgKwg59IgDSAQASAAYKHQK4mADVAAAAAA==.',
Eu='Eunliza:BAAANQAECggICAAAAA==.',
Ew='Ew:BAACNQAFFIEMAAMNAAYK+RIuAgAIAgANAAYK+RIuAgAIAgATAAEKmQMjHQA+AAA1AAQKgSoAAw0ACQr8ISkNAFMDAA0ACQr8ISkNAFMDABMABwqpGUkoALwBAAE1AAQKCQoeAAcA9h8A.',
Ex='Extrathick:BAAANQAECgEIAQAAAA==.',
Fa='Fathershale:BAAANQADCgYICQAAAA==.',
Fe='Feet:BAAANQAECgUIBgAAAA==.Felidae:BAEANQADCgYIFQAAAA==.',
Fi='Firedancer:BAAANQAECgIIAwAAAA==.Fizzfiend:BAAANQADCggIDQAAAA==.',
Fo='Foulcor:BAAANQAECgIIAgABNQAECgMIBgABAAAAAA==.',
Fr='Freakadeek:BAAANQAECgIIBAABNQAECgQICQABAAAAAA==.Freâkadeek:BAAANQADCgQIBAABNQAECgQICQABAAAAAA==.Frieren:BAAANQAECgYICQAAAA==.Frëak:BAAANQADCgQIAgABNQAECgQICQABAAAAAA==.',
Ga='Gabbyo:BAAANQAECgQIBwAAAA==.Galadorn:BAAANQAECgUIDwAAAA==.',
Ge='Genasis:BAAANQABCgMIBQAAAA==.Gerdash:BAAANQAECgUIDQAAAA==.Gerred:BAABNQAECoEbAAIIAAgKBBeyWQA5AgAIAAgKBBeyWQA5AgAAAA==.',
Gh='Ghallow:BAAANQADCgYIBgAAAA==.Ghosthowl:BAAANQAECgUIDAAAAA==.',
Go='Goldenflame:BAAANQAECgEIAgAAAA==.Goldenlight:BAABNQAECoEgAAISAAgKERJ7TQDnAQASAAgKERJ7TQDnAQAAAA==.Goldenmunc:BAAANQADCgIIAgAAAA==.Goldenone:BAAANQAECgIIAgAAAA==.Goldenpants:BAAANQADCggIDwAAAA==.',
Gr='Grandesaxx:BAAANQAECgQICAAAAA==.Grievous:BAABNQAECoEcAAIUAAgKwyVhAQB1AwAUAAgKwyVhAQB1AwAAAA==.',
Ha='Hailmary:BAAANQAECgQIBQAAAA==.Hakudoshi:BAAANQADCgcIDQAAAA==.Harmanee:BAAANQADCgYIBgAAAA==.Hauser:BAABNQAECoEXAAIPAAcKYRdmdgDgAQAPAAcKYRdmdgDgAQAAAA==.',
He='Healaga:BAAANQAECgUJBwABNQAECgYICQABAAAAAA==.Heinrich:BAAANQADCgMIAwAAAA==.',
Ho='Hornreaper:BAAANQAECgUIEgAAAA==.',
Hu='Hubbabubbajr:BAAANQAECgUIBQAAAA==.',
Il='Ilavengu:BAAANQAECgEIAQABNQAECgkJKQARAKgkAA==.',
Is='Isochu:BAAANQADCgMJAwAAAA==.',
Ja='Jayonor:BAABNQAECoEZAAMVAAcKKRlIRQATAgAVAAcKKRlIRQATAgAWAAEKwQCDBAEWAAAAAA==.',
Je='Jek:BAAANQADCgEIAQAAAA==.',
Ju='Judgethis:BAAANQABCgIIAgAAAA==.',
Ka='Kaevrielle:BAEANQAECgUIDgAAAA==.Kaidrosa:BAAANQADCgYIFQAAAA==.Kainicefall:BAAANQAECgUIBgAAAA==.Kainicefell:BAAANQAECgIIAgAAAA==.Kainoficefal:BAAANQAECgIIAgAAAA==.Kaladîn:BAAANQAECgEIAQABNQAFFAUIDAACAGYXAA==.Kalokako:BAAANQADCgEIAQAAAA==.Kamel:BAAANQABCgQIBQAAAA==.Karwin:BAAANQAECgYICAAAAA==.',
Ke='Keeper:BAAANQAECgcIBwABNQAECgkJJAAPAL8kAA==.Keeperodark:BAABNQAECoEVAAIFAAkK5g+5SAA1AgAFAAkK5g+5SAA1AgABNQAECgkJJAAPAL8kAA==.Keeperolight:BAABNQAECoEkAAIPAAkKvySsBgCzAwAPAAkKvySsBgCzAwAAAA==.',
Ki='Kifo:BAAANQADCgcIDAABNQAECgIIAgABAAAAAA==.Killkat:BAAANQAECgQIBQAAAA==.',
Ko='Koojo:BAAANQAECgUICQAAAA==.',
La='Lans:BAAANQAECgIIAgAAAA==.Larew:BAAANQAECgEIAgAAAA==.',
Le='Lealla:BAABNQAECoEcAAIXAAgKmBp+JQBrAgAXAAgKmBp+JQBrAgAAAA==.Leodin:BAAANQADCgYIBgAAAA==.Lethhunt:BAAANQAECgEIAQABNQAECgkJIQAQAEgXAA==.Letholas:BAABNQAECoEhAAQQAAkKSBeZIQAuAgAQAAgK/BiZIQAuAgAHAAYKuhPlWQBCAQAYAAEKpwkOswApAAAAAA==.',
Li='Lightmàiden:BAAANQADCgEIAQAAAA==.Lilkingpunch:BAAANQADCgYIBgABNQAECgkJNgAZAAggAA==.Lizardgang:BAAANQAECgIIAgAAAA==.',
Lo='Loganshu:BAAANQADCgYIBgAAAA==.Lokan:BAAANQAECgYIDwAAAA==.Lots:BAABNQAECoEYAAMFAAcK5R8DawDGAQAFAAUKICADawDGAQAGAAIKUx/8PwCuAAAAAA==.',
Lu='Ludakris:BAAANQAECgQIBQAAAA==.',
['Lí']='Líonheart:BAAANQAECgIIAgAAAA==.',
Ma='Maami:BAAANQAECgYICwAAAA==.Machognome:BAAANQADCgQIBAAAAA==.Mahina:BAAANQAECgUIBwAAAA==.Marcille:BAAANQAECgcJDgAAAA==.Matíx:BAAANQAECgUIDQAAAA==.Mayhaps:BAABNQAECoEYAAMNAAgKUQzsYQD9AQANAAgKUQzsYQD9AQATAAEKgwCfewAWAAAAAA==.',
Me='Mentaltitty:BAAANQAECgMIBwAAAA==.',
Mi='Milhouse:BAABNQAECoEcAAIYAAgKICLbEQD2AgAYAAgKICLbEQD2AgAAAA==.Minerwor:BAAANQADCgcIDQAAAA==.Miooh:BAAANQADCgYIEgAAAA==.Mirrayla:BAAANQADCgEIAQAAAA==.Misty:BAAANQADCgcICQAAAA==.',
Mm='Mmisty:BAAANQAECgUIBwAAAA==.',
Mo='Momometaru:BAAANQAECgQIEAABNQAECgUIEAABAAAAAA==.Monsterbee:BAABNQAECoEeAAIFAAgKSxJkVQAKAgAFAAgKSxJkVQAKAgAAAA==.',
Mu='Mustypizza:BAAANQAECgQIBQAAAA==.',
My='Mystery:BAABNQAECoEcAAIaAAgKNBa5FQAnAgAaAAgKNBa5FQAnAgAAAA==.',
Na='Nats:BAAANQAECgcIDAAAAA==.',
Ne='Neameny:BAABNQAECoEcAAINAAgKgglIbADgAQANAAgKgglIbADgAQAAAA==.',
Ni='Nightstar:BAAANQADCgYIBgAAAA==.',
Nu='Nubrac:BAAANQAECgMIBAAAAA==.',
Ob='Oblivion:BAABNQAECoEdAAMFAAgKbiPdDwAsAwAFAAgKbiPdDwAsAwAGAAIK0BSJTACDAAAAAA==.',
Om='Omey:BAAANQAECgQIBAAAAA==.',
Pa='Pallyshore:BAAANQADCggICAAAAA==.Papichuló:BAAANQADCgMIBgABNQAECgQICQABAAAAAA==.',
Pi='Pixae:BAAANQAECgUICgAAAA==.',
Po='Portknight:BAAANQADCgcIBwAAAA==.Powerplant:BAABNQAECoEkAAINAAkKGyG7DgBHAwANAAkKGyG7DgBHAwAAAA==.',
Py='Pyralys:BAABNQAECoEaAAISAAgKlAhvZgCFAQASAAgKlAhvZgCFAQAAAA==.',
['Pâ']='Pârtyrockêr:BAAANQADCgUIBwABNQAECgQICQABAAAAAA==.',
Ra='Raelene:BAAANQADCgYICAAAAA==.Ragedk:BAAANQAECgIIAwABNQAECgcIBwABAAAAAA==.Ragenbefcake:BAAANQADCggICwAAAA==.Ragetality:BAAANQAECgcIBwAAAA==.Rallaster:BAAANQAECgQIBAABNQAECggIHAARAMIOAA==.Rampage:BAAANQABCgUIAgAAAA==.Raserei:BAABNQAECoEbAAMbAAgKax1mBACiAgAbAAgKax1mBACiAgAIAAEKpRNxDgFFAAAAAA==.Rawb:BAAANQAECgYJCgABNQAECgkKHgAHAPYfAA==.',
Re='Recolada:BAAANQADCgcJDAAAAA==.Regicee:BAAANQAECgUICgAAAA==.',
Ri='Riffraff:BAAANQADCggICgAAAA==.',
Ro='Rockdyou:BAAANQAECgQJBQAAAA==.Rotlobster:BAABNQAECoEeAAIEAAkKiiKPAAB+AwAEAAkKiiKPAAB+AwABNQAECgkJKQAcANwfAA==.',
Ru='Rudal:BAAANQADCgIIAgAAAA==.Rundvelt:BAAANQADCgIIAgAAAA==.',
Se='Selina:BAAANQAECgQIBAAAAA==.Serdwarf:BAAANQAECgUICgAAAA==.Sertian:BAAANQADCgQIBAAAAA==.',
Sh='Shatha:BAAANQADCgQIBQAAAA==.Sherten:BAAANQAECgIJAgAAAA==.Shooturiout:BAAANQADCgUIBQAAAA==.Shtanky:BAAANQAECgYICwAAAA==.',
Si='Sixsixsix:BAAANQADCggJCgABNQAECgkKHgAHAPYfAA==.',
Sk='Sketch:BAAANQAECgIIAgABNQAFFAQICwAdAHsSAA==.Skoogz:BAAANQAECgIIAQAAAA==.',
So='Sogsy:BAAANQAECgUIDgAAAA==.Soleri:BAAANQAECgQIBAAAAA==.Soulfulgingr:BAAANQAECgIIAgAAAA==.',
St='Styx:BAAANQADCggICAAAAA==.Stza:BAAANQABCgYICAAAAA==.',
Su='Sunbake:BAAANQAECgIJAgAAAA==.',
Sw='Sweetbbyraze:BAABNQAECoEcAAILAAkKxR0wBwDpAgALAAkKxR0wBwDpAgAAAA==.',
['Sí']='Sín:BAAANQADCgIJAgABNQAECgkKHgAHAPYfAA==.',
Ta='Talipally:BAAANQAECgcIEAAAAA==.Taliwhacker:BAAANQADCgMIAwABNQAECgcIEAABAAAAAA==.Talonleafgrd:BAAANQAECgYIDgAAAA==.Tandsonna:BAAANQAECgUIBQAAAA==.Tanisong:BAAANQADCgUICQAAAA==.',
Te='Terayus:BAAANQADCgIJAgAAAA==.Terraform:BAAANQADCgYICwAAAA==.',
Th='Thalor:BAAANQAECgIIBgABNQAFFAUICgAeAEUWAA==.Thekingpunch:BAABNQAECoE2AAIZAAkKCCDpBAAtAwAZAAkKCCDpBAAtAwAAAA==.Thenle:BAAANQADCgcIEgAAAA==.Theworst:BAAANQAECgYIBgABNQAECgkKHgAHAPYfAA==.',
Ti='Tillwar:BAABNQAECoEcAAIIAAgKSBPYagAFAgAIAAgKSBPYagAFAgAAAA==.Tiàna:BAAANQADCgEIAQAAAA==.',
To='Tofu:BAAANQAECgUIEQAAAA==.Tortillachip:BAAANQADCgYIBgAAAA==.',
Tr='Treibh:BAABNQAECoEcAAIfAAgKrRf0FwAxAgAfAAgKrRf0FwAxAgAAAA==.Trulydps:BAAANQAECgUIBwAAAA==.',
Tu='Tust:BAAANQAECgQIBQABNQABCgQIAgABAAAAAA==.',
Ty='Tymora:BAAANQADCggICAABNQAECggIHAARAMIOAA==.',
['Të']='Tërris:BAAANQAECgUIDQAAAA==.',
Un='Undzl:BAACNQAFFIEGAAMQAAIKox8iCwCzAAAQAAIKox8iCwCzAAAHAAEKcgbQGAA5AAA1AAQKgSgAAwcACQr3I24OABoDAAcACQoWIm4OABoDABAACApZITUOAOsCAAAA.Unknowna:BAAANQADCgYIBgAAAA==.',
Ur='Urowndad:BAAANQADCgIIAgABNQAECgMIBAABAAAAAA==.',
Va='Vallez:BAEANQAECgcIEgAAAA==.Varnusshadow:BAAANQAECgIIAgAAAA==.Vayn:BAAANQAECgUIBQAAAA==.',
Ve='Velladoree:BAAANQAECgIJAgAAAA==.Vexahlia:BAAANQAECggICgAAAA==.',
Vy='Vyrable:BAAANQAECgQIBgAAAA==.',
Wa='Waveygravee:BAAANQADCgcJCwAAAA==.Wavygraivy:BAAANQAECgIIAgAAAA==.',
We='Wedragon:BAAANQADCgYICQAAAA==.',
Wo='Woofwoof:BAAANQAECgIIBAAAAA==.Wooshh:BAAANQAECgQICAAAAA==.',
Xh='Xhexana:BAAANQAECgUIDQABNQAECggIHAANAIIJAA==.',
Xi='Xianofukuju:BAAANQAECgUIEAAAAA==.',
Xr='Xrayl:BAABNQAECoEdAAMgAAkKtxssCwAaAgAgAAcKIRwsCwAaAgAeAAYKmBn/JwB6AQAAAA==.',
Xz='Xzerocool:BAAANQAECgMIBAAAAA==.',
Yo='Yoshikazu:BAAANQAECgIIAgAAAA==.',
Za='Zaarah:BAAANQADCgQICgAAAA==.',
Ze='Zendezoth:BAAANQAECgQIBAAAAA==.',
Zh='Zhiva:BAAANQAECgIIAwAAAA==.',
Zy='Zykoz:BAAANQAECgQIBQAAAA==.',
['Åy']='Åyna:BAAANQADCgcIDwAAAA==.',
['Ða']='Ðaddy:BAAANQAECgMIAwAAAA==.Ðamned:BAAANQAECgUICAABNQAECgkKHgAHAPYfAA==.',
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
