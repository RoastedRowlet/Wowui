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

local lookup = {'Unknown-Unknown','Mage-Frost','Mage-Arcane','Hunter-BeastMastery','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','DeathKnight-Frost','Hunter-Marksmanship','DeathKnight-Unholy','DeathKnight-Blood','Monk-Mistweaver','Shaman-Enhancement','Druid-Feral','Monk-Windwalker',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abel:BAEANQADCggICAABNQAECgIIBgABAAAAAA==.',
Ae='Aeidail:BAABNQAECoEeAAMCAAkJfCGvAwBMAgADAAkJEx/pJgD2AgACAAYJNSKvAwBMAgAAAA==.',
Ag='Agraceful:BAAANQAECgUIBgAAAA==.',
Ai='Aidton:BAAANQADCgcIBwAAAA==.Aiobhicefall:BAAANQAECgMIAwAAAA==.Aiobicefall:BAAANQABCgIIAgAAAA==.Aiza:BAAANQAECgcIEgAAAA==.',
Al='Albinoknight:BAAANQADCgEIAQAAAA==.Alessia:BAAANQADCgYICgAAAA==.',
An='Angrypants:BAAANQADCggIHAAAAA==.Animalfriend:BAAANQADCggIDgAAAA==.Anklesmasher:BAAANQADCgYIDQAAAA==.Antisocial:BAAANQADCggIEAABNQAECgkJHwAEAE4hAA==.',
Ar='Arfaz:BAAANQAECgIIAgAAAA==.',
As='Astramoon:BAAANQAECgEIAQAAAA==.',
Ba='Baerd:BAAANQADCgcICQAAAA==.Barlz:BAAANQADCgUIEQAAAA==.',
Be='Beasthunt:BAAANQADCgcIEAABNQAECgIIAgABAAAAAA==.Beatmywillie:BAAANQAECgUIBQAAAA==.Bebby:BAAANQADCggIIwAAAA==.Belwolf:BAAANQADCgYIDgAAAA==.Bennehona:BAAANQADCgEIAQAAAA==.Bergstrom:BAAANQAECgYICQAAAA==.',
Bi='Biancafiamma:BAAANQADCgcIFQAAAA==.Biancaneve:BAAANQAECgQIBwAAAA==.',
Bo='Bombacløt:BAAANQAECgIIAgAAAA==.',
Br='Brastin:BAAANQAECgMIBAAAAA==.Brenell:BAAANQAECgYICwAAAA==.',
Ca='Cabëla:BAAANQADCggIDgAAAA==.Calacolinda:BAAANQAECgIIAwAAAA==.',
Ce='Celestiall:BAAANQADCggIDwAAAA==.Ceridwyn:BAAANQADCgYIDAAAAA==.',
Ch='Chadalonius:BAAANQADCgQIBAABNQAECggIGgAFAE0fAA==.Cheesecurd:BAAANQADCgcIGAAAAA==.Choal:BAAANQADCgYICwAAAA==.',
Co='Corahin:BAAANQAECgQIBAAAAA==.',
Da='Dalren:BAABNQAECoEiAAMGAAkJjRoeBgDZAgAGAAkJcRkeBgDZAgAHAAIJZx24DQCaAAAAAA==.Dammedude:BAAANQABCgMIAwAAAA==.Dartagnan:BAAANQAECgUICQAAAA==.Darthmaul:BAAANQAECgYICwAAAA==.Daveykrook:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.David:BAAANQAECgEIAQAAAA==.',
De='Dendiian:BAAANQADCgYICQAAAA==.Depletor:BAAANQAECgUICQAAAA==.',
Di='Diem:BAAANQADCgYICAAAAA==.',
Do='Docholiday:BAAANQAECgIIAwAAAA==.Docsassist:BAAANQADCggIFQAAAA==.Dowedoes:BAAANQAECgYICwAAAA==.',
Dr='Drachula:BAAANQAECgEIAQAAAA==.Dracultra:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.Draeun:BAAANQAECgEIAQABNQAECgkJIgAGAI0aAA==.Dreolan:BAAANQAECgMIAwAAAA==.Dràchula:BAAANQADCgIIAgAAAA==.Dràúgr:BAAANQADCgMIAwAAAA==.',
Dy='Dyala:BAAANQAECgUICgAAAA==.',
Dz='Dzznuts:BAAANQABCgYICgAAAA==.',
['Dé']='Démonléth:BAAANQAECgIIAgABNQAECgkJFgAIACUSAA==.',
['Dö']='Dönövan:BAAANQAECgIIAgAAAA==.',
Eg='Eggyolk:BAAANQAECgQIBwAAAA==.',
El='Elastwo:BAAANQADCgYICAAAAA==.Eloise:BAAANQADCggIFwAAAA==.Elvenbane:BAAANQAECgYICwAAAA==.',
Eu='Eunliza:BAAANQAECggICAAAAA==.',
Ew='Ew:BAABNQAECoEfAAMEAAkJTiF4BwBaAwAEAAkJTiF4BwBaAwAJAAYJkBoHHwCpAQAAAA==.',
Ex='Extrathick:BAAANQAECgEIAQAAAA==.',
Fa='Fathershale:BAAANQADCgEIAQAAAA==.',
Fe='Feet:BAAANQAECgQIBAAAAA==.Felidae:BAAANQADCgUICQAAAA==.',
Fi='Firedancer:BAAANQADCgUIBQAAAA==.Fizzfiend:BAAANQADCggIDQAAAA==.',
Fo='Foulcor:BAAANQAECgIIAgAAAA==.',
Fr='Freakadeek:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Freâkadeek:BAAANQADCgQIBAABNQAECgIIAwABAAAAAA==.Frieren:BAAANQAECgIIAgAAAA==.Frëak:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.',
Ga='Gabbyo:BAAANQADCggIGwAAAA==.Galadorn:BAAANQAECgMIBQAAAA==.',
Ge='Genasis:BAAANQABCgMIBQAAAA==.Gerdash:BAAANQAECgIIAwAAAA==.Gerred:BAAANQAECgUIDAAAAA==.',
Gh='Ghosthowl:BAAANQAECgIIAgAAAA==.',
Go='Goldenflame:BAAANQADCgcICwAAAA==.Goldenlight:BAAANQAECgYIDgAAAA==.Goldenmunc:BAAANQADCgIIAgAAAA==.Goldenone:BAAANQADCgcIDgAAAA==.Goldenpants:BAAANQADCggIDwAAAA==.',
Gr='Grandesaxx:BAAANQAECgQICAAAAA==.Grievous:BAAANQAECgYICwAAAA==.',
Ha='Hailmary:BAAANQADCggIHQAAAA==.Hakudoshi:BAAANQADCgUICgAAAA==.Harmanee:BAAANQADCgYIBgAAAA==.Hauser:BAAANQAECgUICQAAAA==.',
He='Healaga:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Heinrich:BAAANQADCgMIAwAAAA==.',
Ho='Hornreaper:BAAANQAECgQICQAAAA==.',
Hu='Hubbabubbajr:BAAANQADCgcIBwABNQAECgMIBAABAAAAAA==.',
Is='Isochu:BAAANQADCgMIAQAAAA==.',
Ja='Jayonor:BAAANQAECgYICwAAAA==.',
Je='Jek:BAAANQADCgEIAQAAAA==.',
Ju='Judgethis:BAAANQABCgIIAgAAAA==.',
Ka='Kaevrielle:BAEANQAECgQIBwAAAA==.Kaidrosa:BAAANQADCgYIEAAAAA==.Kainicefall:BAAANQAECgEIAQAAAA==.Kaladîn:BAAANQAECgEIAQABNQAECgkJHgACAHwhAA==.Kamel:BAAANQABCgQIBQAAAA==.Karwin:BAAANQAECgYIAgAAAA==.',
Ke='Keeper:BAAANQADCggIDwABNQAFFAEIAQABAAAAAA==.Keeperodark:BAAANQAECgUIBQABNQAFFAEIAQABAAAAAA==.Keeperolight:BAAANQAFFAEIAQAAAA==.',
Ki='Kifo:BAAANQADCgUICgABNQADCgYIBgABAAAAAA==.Killkat:BAAANQADCggIHQAAAA==.',
Ko='Koojo:BAAANQADCggIEQAAAA==.',
La='Lans:BAAANQAECgIIAgAAAA==.Larew:BAAANQAECgEIAQAAAA==.',
Le='Lealla:BAAANQAECgYICwAAAA==.Lethhunt:BAAANQAECgEIAQABNQAECgkJFgAIACUSAA==.Letholas:BAABNQAECoEWAAQIAAkJJRLwFQD1AQAIAAgJjRDwFQD1AQAKAAYJuhPyOACMAQALAAEJpwkciAApAAAAAA==.',
Li='Lightmàiden:BAAANQADCgEIAQAAAA==.Lilkingpunch:BAAANQADCgYIBgABNQAECggIIAAMAAgaAA==.Lizardgang:BAAANQADCggIGAAAAA==.',
Lo='Loganshu:BAAANQADCgYIBgAAAA==.Lokan:BAAANQAECgUICgAAAA==.Lots:BAAANQAECgUICgAAAA==.',
Lu='Ludakris:BAAANQADCggIHQAAAA==.',
['Lí']='Líonheart:BAAANQADCggIDgAAAA==.',
Ma='Maami:BAAANQADCgIIAgAAAA==.Machognome:BAAANQADCgQIBAAAAA==.Mahina:BAAANQADCgUICgAAAA==.Marcille:BAAANQAECgcICAAAAA==.Matíx:BAAANQAECgQIBAAAAA==.Mayhaps:BAAANQAECgYIBgAAAA==.',
Me='Mentaltitty:BAAANQAECgEIAQAAAA==.',
Mi='Milhouse:BAAANQAECgYICwAAAA==.Minerwor:BAAANQADCgUICgAAAA==.Miooh:BAAANQADCgYIDAAAAA==.Mirrayla:BAAANQADCgEIAQAAAA==.Misty:BAAANQADCgcICAAAAA==.',
Mm='Mmisty:BAAANQAECgIIAgAAAA==.',
Mo='Momometaru:BAAANQAECgMIAwABNQAECgQIBwABAAAAAA==.Monsterbee:BAAANQAECgYIDAAAAA==.',
Mu='Mustypizza:BAAANQADCggIHQAAAA==.',
My='Mystery:BAAANQAECgYICwAAAA==.',
Na='Nats:BAAANQADCggIFAAAAA==.',
Ne='Neameny:BAAANQAECgYICwAAAA==.',
Nu='Nubrac:BAAANQADCggIFAAAAA==.',
Ob='Oblivion:BAAANQAECgYIDAAAAA==.',
Pa='Papichuló:BAAANQADCgMIBgABNQAECgIIAwABAAAAAA==.',
Pi='Pixae:BAAANQAECgQICQAAAA==.',
Po='Powerplant:BAABNQAECoEXAAIEAAgJUh1dHACeAgAEAAgJUh1dHACeAgAAAA==.',
Py='Pyralys:BAAANQAECgYICwAAAA==.',
['Pâ']='Pârtyrockêr:BAAANQADCgUIBwABNQAECgIIAwABAAAAAA==.',
Ra='Raelene:BAAANQADCgIIAgAAAA==.Ragedk:BAAANQAECgIIAwABNQAECgYIBgABAAAAAA==.Ragetality:BAAANQAECgYIBgAAAA==.Raserei:BAAANQAECgYICwAAAA==.Rawb:BAAANQAECgYICgABNQAECgkJHwAEAE4hAA==.',
Re='Recolada:BAAANQADCgcIBwAAAA==.Regicee:BAAANQAECgQIBQAAAA==.',
Ro='Rockdyou:BAAANQAECgQIBQAAAA==.Rotlobster:BAAANQAFFAIIAgABNQAECgkJHQANANAeAA==.',
Ru='Rudal:BAAANQADCgIIAgAAAA==.Rundvelt:BAAANQADCgIIAgAAAA==.',
Se='Selina:BAAANQAECgQIBAAAAA==.Serdwarf:BAAANQAECgIIAgAAAA==.Sertian:BAAANQADCgQIBAAAAA==.',
Sh='Sherten:BAAANQAECgIIAgAAAA==.Shooturiout:BAAANQADCgUIBQAAAA==.Shtanky:BAAANQAECgUICgAAAA==.',
Si='Sixsixsix:BAAANQADCggICgABNQAECgkJHwAEAE4hAA==.',
Sk='Sketch:BAAANQADCggICAABNQAECgkJGwAOAPIgAA==.Skoogz:BAAANQADCgcICgAAAA==.',
So='Sogsy:BAAANQAECgQIBAAAAA==.Soulfulgingr:BAAANQADCgcIGAAAAA==.',
St='Stza:BAAANQABCgYICAAAAA==.',
Su='Sunbake:BAAANQADCggIFQAAAA==.',
Sw='Sweetbbyraze:BAAANQAECgcIEwAAAA==.',
['Sí']='Sín:BAAANQADCgIIAgABNQAECgkJHwAEAE4hAA==.',
Ta='Talipally:BAAANQAECgUICQAAAA==.Taliwhacker:BAAANQADCgMIAwABNQAECgUICQABAAAAAA==.Talonleafgrd:BAAANQAECgIIAwAAAA==.Tanisong:BAAANQADCgUICQAAAA==.',
Te='Terayus:BAAANQADCgIIAgAAAA==.Terraform:BAAANQADCgYICwAAAA==.',
Th='Thalor:BAAANQAECgIIAgABNQAECgkJGwAPACEgAA==.Thekingpunch:BAABNQAECoEgAAIMAAgJCBqhCAB8AgAMAAgJCBqhCAB8AgAAAA==.Thenle:BAAANQADCgcIDAAAAA==.Theworst:BAAANQAECgYIBgABNQAECgkJHwAEAE4hAA==.',
Ti='Tillwar:BAAANQAECgYICwAAAA==.Tiàna:BAAANQADCgEIAQAAAA==.',
To='Tofu:BAAANQAECgQIBwAAAA==.Tortillachip:BAAANQADCgYIBgAAAA==.',
Tr='Treibh:BAAANQAECgYICwAAAA==.Trulydps:BAAANQAECgIIAgAAAA==.',
Tu='Tust:BAAANQADCgcICQABNQABCgQIAgABAAAAAA==.',
Ty='Tymora:BAAANQADCggICAABNQAECgYICwABAAAAAA==.',
['Të']='Tërris:BAAANQAECgIIBAAAAA==.',
Un='Undzl:BAAANQAFFAIIAgAAAA==.Unknowna:BAAANQADCgYIBgAAAA==.',
Va='Vallez:BAAANQAECgUICwAAAA==.',
Ve='Velladoree:BAAANQADCgYIFAAAAA==.',
Vy='Vyrable:BAAANQAECgQIBgAAAA==.',
Wa='Waveygravee:BAAANQADCgYICgAAAA==.Wavygraivy:BAAANQADCgUIDQAAAA==.',
We='Wedragon:BAAANQADCgQIBAAAAA==.',
Wo='Woofwoof:BAAANQAECgIIBAAAAA==.Wooshh:BAAANQAECgIIBAAAAA==.',
Xh='Xhexana:BAAANQAECgMIBAABNQAECgYICwABAAAAAA==.',
Xi='Xianofukuju:BAAANQAECgQIBwAAAA==.',
Xr='Xrayl:BAAANQAECgYIEgAAAA==.',
Xz='Xzerocool:BAAANQADCggIHAAAAA==.',
Yo='Yoshikazu:BAAANQADCgIIAgAAAA==.',
Za='Zaarah:BAAANQADCgQIBgAAAA==.',
Ze='Zendezoth:BAAANQADCgcIDQAAAA==.',
Zh='Zhiva:BAAANQAECgIIAgAAAA==.',
Zy='Zykoz:BAAANQADCggIHAAAAA==.',
['Åy']='Åyna:BAAANQADCgIIAgAAAA==.',
['Ða']='Ðaddy:BAAANQAECgMIAwAAAA==.Ðamned:BAAANQAECgUICAABNQAECgkJHwAEAE4hAA==.',
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
