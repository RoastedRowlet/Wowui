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

local lookup = {'Hunter-Marksmanship','Unknown-Unknown','Mage-Arcane','Warlock-Demonology','Paladin-Retribution','Druid-Restoration','Druid-Balance',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=53,date='2026-09-08',data={Ac='Acemage:BAAANQAECgIIAwABNQAECgkJGwABAPEfAA==.',
Ae='Aegon:BAAANQAECgYICwAAAA==.Aelivalor:BAAANQADCggIFAAAAA==.Aendoran:BAAANQADCgMIAwAAAA==.Aeon:BAAANQADCgYIBgAAAA==.Aesthelyan:BAAANQADCgcIGAAAAA==.',
Ah='Ahdonis:BAAANQAECgEIAQAAAA==.',
Ai='Aiarra:BAAANQAECgQIBAAAAA==.Aindriana:BAAANQAECgEIAQAAAA==.',
Aj='Ajx:BAAANQADCgEIAQABNQADCggIFAACAAAAAA==.',
Ak='Akame:BAAANQADCgQIBAAAAA==.Akashajade:BAAANQADCggIDwAAAA==.Akzeriyuth:BAAANQADCgEIAQABNQAECgYICAACAAAAAA==.',
Al='Alerothon:BAAANQAECgYICwAAAA==.Alestiana:BAAANQAECgQIBQAAAA==.Alevora:BAAANQADCgIIAgAAAA==.',
Am='Amephyst:BAAANQAECgQIBAAAAA==.Amnadores:BAAANQAECgEIAQABNQAECgYIDAACAAAAAA==.',
An='Annati:BAAANQAECgcIEQAAAA==.Antarres:BAAANQADCgYIBwAAAA==.',
Ao='Aoba:BAAANQAECgQIBAAAAA==.',
Ap='Apila:BAAANQADCgEIAQABNQAECgEIAQACAAAAAQ==.Apox:BAAANQADCgEIAQAAAA==.',
Ar='Arathria:BAAANQADCgUIBQABNQAECgQIBQACAAAAAA==.Armagedon:BAAANQADCgUIBQAAAA==.Artemisomega:BAAANQADCgEIAgABNQADCggIEgACAAAAAA==.Artemisshade:BAAANQADCggIEgAAAA==.Arthillius:BAAANQADCgQIBQAAAA==.',
As='Astro:BAAANQADCggICAAAAA==.',
Av='Aviana:BAAANQADCgYIBgAAAA==.',
Ay='Aylá:BAAANQADCgQICAAAAA==.',
Be='Beefypal:BAAANQADCgUIBQAAAA==.Beldar:BAAANQAECgUIBwAAAA==.',
Bi='Bip:BAAANQAECgQIBwAAAA==.',
Bl='Blakely:BAAANQADCgQIBAAAAA==.Blitzy:BAAANQAECgQIBgAAAA==.',
Bo='Bobbette:BAAANQADCgUIBQABNQAECgUIBgACAAAAAA==.',
Br='Brenick:BAAANQADCgcIEgAAAA==.Bringer:BAAANQADCgYIDAAAAA==.Bristlegonad:BAAANQADCgEIAQAAAA==.Bråyden:BAAANQADCgcIEQAAAA==.',
Bu='Bubbléoseven:BAAANQADCgYIBgAAAA==.Bullgrim:BAAANQADCgUIBAAAAA==.Burnie:BAAANQADCgcIEQAAAA==.',
['Bò']='Bònkers:BAAANQADCgMIAwAAAA==.',
Ca='Camilah:BAAANQAECgIIAgAAAA==.Capa:BAAANQAECgYICAAAAA==.Carcine:BAAANQADCgUIBQAAAA==.Carion:BAAANQAECgQIBQAAAA==.',
Ce='Celestiné:BAAANQADCgUIBQAAAA==.Cemeteri:BAAANQADCgQIBAAAAA==.',
Ch='Chaingun:BAAANQADCgcIDAAAAA==.Chilblain:BAAANQAECgQIBAAAAA==.Chilchizedek:BAAANQADCgQIBAAAAA==.Chobii:BAAANQAECgcICQAAAA==.',
Ci='Cibochevski:BAAANQADCgQIBAABNQADCgcIEQACAAAAAA==.Ciratorynth:BAAANQAECgUIBQAAAA==.Circumschism:BAAANQADCgQIBAAAAA==.Citrus:BAAANQAECgcIDgAAAA==.',
Cl='Clearlovec:BAAANQADCggICAABNQAECgQIBAACAAAAAA==.Closetfurry:BAAANQADCgcIEgAAAA==.',
Co='Condor:BAAANQADCggIDwAAAA==.Corrinne:BAAANQAECgEIAQAAAA==.Cosmicmage:BAAANQADCgUIBQAAAA==.',
Cr='Critmypänts:BAAANQADCgcIDgAAAA==.',
Cz='Czernobog:BAAANQADCgUIBQAAAA==.',
Da='Daeshan:BAAANQAECgQIBAAAAA==.Daldolarette:BAAANQAECgYICwAAAA==.Daradevil:BAAANQADCgQIBAAAAA==.Daralune:BAAANQADCgYIDgAAAA==.Darkenrahll:BAAANQADCgIIAgAAAA==.Darner:BAAANQAECgQIBQAAAA==.Dasecondone:BAAANQADCgUIBwAAAA==.',
De='Demonicfyre:BAABNQAECoEOAAIDAAkJlBYPJgC0AgADAAkJlBYPJgC0AgAAAA==.Destros:BAAANQADCggIDAAAAA==.',
Di='Disdain:BAAANQADCggIDgABNQAECgkJGQAEACgkAA==.',
Do='Donchapper:BAAANQADCgcIBwAAAA==.Doomsteel:BAAANQADCgQIBAABNQADCgQIBAACAAAAAA==.',
Dr='Drauger:BAAANQADCgUIBQAAAA==.Drucyllå:BAAANQADCgIIAgAAAA==.Druidson:BAAANQABCgQIBAAAAA==.Drusti:BAAANQADCgYIBgAAAA==.Dryageribeye:BAAANQAECgYICAAAAA==.Drzip:BAAANQADCggICAAAAA==.Drzippy:BAAANQADCggIEgAAAA==.',
Du='Duskthrasher:BAAANQADCggIFQAAAA==.Duyii:BAAANQADCgYIBgABNQAECgEIAQACAAAAAQ==.',
Dy='Dyanthus:BAAANQAECgQIBAAAAA==.',
['Dà']='Dàrktress:BAAANQADCgcIDAAAAA==.',
Ea='Easterneon:BAAANQAECgIIAwABNQAECgQIBAACAAAAAA==.',
Ec='Ech:BAAANQAECgQIBAAAAA==.',
Ei='Eiraveta:BAAANQAECgQIBAAAAA==.',
El='Elemental:BAAANQADCggIEgAAAA==.Elendirs:BAAANQABCgYICwAAAA==.Ellois:BAAANQAECgIIAgAAAA==.',
Ep='Epicnoname:BAAANQAECgQIBQAAAA==.',
Er='Erëdor:BAAANQAECgEIAQAAAA==.',
Es='Esmerèlda:BAAANQADCgEIAQAAAA==.',
Ev='Evershine:BAAANQADCggICAAAAA==.',
Fa='Fairlight:BAAANQAECgQIBAAAAA==.',
Fe='Feannesse:BAAANQADCgcIEQAAAA==.',
Fi='Firebolt:BAAANQAECgIIBAAAAA==.Fitts:BAAANQADCggIDAABNQAECgYICwACAAAAAA==.',
Fr='Frags:BAAANQADCgcIBgAAAA==.Fricorith:BAAANQADCgcIEQAAAA==.Frostytoot:BAAANQADCgcICgAAAA==.',
['Fë']='Fëhirthane:BAAANQADCgYICwAAAA==.',
['Fù']='Fùzz:BAAANQAECgUIBgAAAA==.',
Ga='Garekk:BAAANQADCggIDwAAAA==.',
Gi='Gilgamésh:BAAANQAECgcIEgAAAA==.',
Go='Golldehammer:BAAANQADCgQIBAAAAA==.Goneville:BAAANQADCgYIBgAAAA==.',
Gr='Grizzabella:BAAANQADCggIDwAAAA==.',
Gu='Guias:BAAANQADCgEIAQAAAA==.Gutworthy:BAAANQADCgUIBQAAAA==.',
Ha='Hairykrishna:BAAANQADCgYIDAAAAA==.Haldevarik:BAAANQADCgQIBAAAAA==.Hallzofhell:BAAANQAECgIIAgAAAA==.Hammerjane:BAAANQADCgcIDwAAAA==.Hamur:BAAANQAECgEIAQAAAA==.Hariyaki:BAAANQADCgcIEQAAAA==.',
He='Heavywinner:BAAANQAECgYICwAAAA==.Hecûba:BAAANQABCgQIBAAAAA==.Hedoniist:BAAANQADCgYIBgAAAA==.Hellslayer:BAAANQADCgcIEAAAAA==.',
Hu='Hubbabubbá:BAAANQADCgcIBwAAAA==.Hughmann:BAAANQADCgcIEQAAAA==.',
['Hâ']='Hârlot:BAAANQADCgcIEQAAAA==.',
['Hè']='Hèathen:BAAANQADCgQIBAAAAA==.',
In='Ingenii:BAAANQADCggICAABNQAECgYICAACAAAAAA==.',
Is='Ishaa:BAAANQADCgIIAgAAAA==.Isllwyn:BAAANQADCgMIAwAAAA==.Isummonyou:BAAANQAECggICwAAAA==.',
Ja='Jadeth:BAAANQADCgYICgAAAA==.Jaidah:BAAANQADCgUICQAAAA==.Jansôlo:BAAANQAECgQIBwAAAA==.Jaratri:BAAANQAECgYIDwAAAA==.',
Je='Jeka:BAAANQADCgMIAwAAAA==.Jenton:BAAANQAECgEIAQAAAA==.',
Ka='Kaerovia:BAAANQAECgYICAAAAA==.Kaisen:BAAANQADCgUICwAAAA==.Kamthesham:BAAANQAECgIIAgAAAA==.Kanchome:BAAANQADCgYIBgAAAA==.Kaneki:BAAANQADCgYIDAAAAA==.Karg:BAAANQAECgIIAgAAAA==.Karmai:BAAANQAECgQIBQAAAA==.Kathine:BAAANQADCgUICAAAAA==.Kayliey:BAAANQADCgUIBQAAAA==.',
Ke='Kelvala:BAAANQAECgYICwAAAA==.Kelwynd:BAAANQADCggIFQAAAA==.',
Kh='Khasaziel:BAAANQADCgcIBwAAAA==.',
Ki='Kirean:BAAANQAECgQIBAAAAA==.Kiuke:BAAANQAECgIIAgAAAA==.',
Ko='Kobesama:BAAANQAECgMIAwAAAA==.Kodask:BAAANQADCgYICwAAAA==.Kodera:BAAANQAECgUIBgAAAA==.Konata:BAAANQADCggIDwABNQAECgQIBAACAAAAAA==.Korbenzoo:BAAANQADCgMIAwABNQAECgEIAQACAAAAAQ==.',
Kr='Kryssie:BAAANQAECgUIBwAAAA==.',
Ku='Kuroku:BAAANQADCgUIBQAAAA==.',
Kw='Kwaili:BAAANQAECgMIAwAAAA==.',
La='Lanaya:BAAANQADCggIEwAAAA==.Laserheadten:BAAANQAECgUICgAAAA==.Lawrensce:BAAANQAECgIIAgAAAA==.',
Le='Lencho:BAAANQADCggIEQAAAA==.Lenchodude:BAAANQADCgQIBAAAAA==.Lenian:BAAANQADCgcIEQAAAA==.Leâfs:BAAANQADCgYICQAAAA==.',
Li='Litesout:BAAANQAECgMIAwAAAA==.',
Lo='Loreck:BAAANQADCgUICAAAAA==.Lorlea:BAAANQADCgMIAwAAAA==.',
Lu='Lunarcateyes:BAAANQABCgIIBAAAAA==.Lunariel:BAAANQADCggIFAAAAA==.',
Ly='Lyraae:BAAANQAECgQIBAAAAA==.',
Ma='Mackas:BAAANQADCgYICAAAAA==.Maidenofhate:BAAANQAECgYICwAAAA==.Maiganoss:BAAANQADCggIFAAAAA==.Makeloa:BAAANQADCgIIAgAAAA==.Mardon:BAAANQABCgMIBAABNQABCgYICwACAAAAAA==.',
Me='Megid:BAAANQAECgQIBAAAAA==.Mestopheles:BAAANQAECgEIAQAAAA==.',
Mi='Midianite:BAAANQADCgMIAwAAAA==.Mimiru:BAAANQADCgYIBgAAAA==.Minié:BAAANQADCgUIBQAAAA==.Mizblumkin:BAAANQADCgcIDQAAAA==.',
Mo='Monkies:BAAANQADCgQIBAAAAA==.Moonnshine:BAAANQAECgYICAAAAA==.',
My='Mylittlepwni:BAAANQADCgYICwAAAA==.',
['Mä']='Mälcharion:BAAANQADCgQIBAAAAA==.',
Na='Nakros:BAAANQAECgMIAwAAAA==.',
Ne='Nemonas:BAAANQADCgYIDAAAAA==.Nerik:BAAANQADCgMIBAAAAA==.',
Ng='Ngyue:BAAANQADCgYIGQAAAA==.',
Ni='Niala:BAAANQADCgUIBQAAAA==.Nianna:BAAANQAECgQIBAAAAA==.Nickto:BAAANQADCggIEAAAAA==.Nightshayed:BAAANQADCgQIBAAAAA==.',
Nu='Nubin:BAAANQADCgYIBgAAAA==.Numbed:BAAANQADCgYIBgAAAA==.',
Ny='Nytwalker:BAAANQADCgYIDgAAAA==.Nyårlåthôtêp:BAAANQADCgcICgAAAA==.',
Og='Ogbruced:BAAANQADCgYIBQABNQADCgcIEAACAAAAAA==.',
Op='Opalla:BAAANQADCggIFAAAAA==.',
Or='Orceo:BAAANQADCggIEwAAAA==.Orcrest:BAAANQADCgQIBAAAAA==.Ororo:BAAANQAECgYICgAAAA==.',
Pa='Palal:BAAANQADCgcIBwABNQAECgIIAgACAAAAAA==.Paryah:BAAANQADCgcIEQAAAA==.',
Ph='Phanceester:BAAANQADCgQIBQAAAA==.Phindra:BAAANQADCgUIBgAAAA==.Phréek:BAAANQAECgEIAQAAAA==.',
Pl='Plethknight:BAAANQAECgIIAgABNQAECgcIEAACAAAAAA==.',
Pr='Praze:BAAANQADCgQIBQAAAA==.',
Pu='Puoh:BAAANQABCgYIBwAAAA==.Pustülio:BAAANQADCggICAAAAA==.',
Ra='Raha:BAAANQADCgYIBgAAAA==.Rahis:BAAANQAECgUIBwAAAA==.Raiu:BAAANQADCgcIEQAAAA==.Ramsis:BAAANQAECgUIBgAAAA==.Randir:BAAANQAECgYICAAAAA==.Rath:BAAANQAECgQIBAAAAA==.',
Re='Rebarka:BAAANQADCggIDAAAAA==.Rebrewke:BAAANQADCgYICwAAAA==.',
Rh='Rhiannonage:BAAANQADCgQIBAABNQADCgcIEQACAAAAAA==.',
Ro='Robinhoodx:BAAANQAECgQIBAAAAA==.Roenabur:BAAANQADCgQIBAAAAA==.Romok:BAAANQADCgQIBQAAAA==.',
Ru='Rubysunday:BAAANQADCggIGQAAAA==.',
Ry='Rykarranger:BAAANQADCgQIBAAAAA==.',
['Rì']='Rìseandemìse:BAAANQABCgEIAQAAAA==.',
Sa='Sacrìfice:BAAANQAECgMIAwAAAA==.Samoot:BAAANQAECgIIAgAAAA==.Sarreus:BAAANQADCgIIAgABNQAECgEIAQACAAAAAQ==.',
Se='Sepharim:BAAANQADCgQIBwAAAA==.',
Sh='Shael:BAAANQADCgcIEQAAAA==.Shamanstein:BAEANQADCggIDwABNQAECgkJGgAFAGAkAA==.Shammbo:BAAANQAECgEIAQABNQAECgUICAACAAAAAA==.Sharty:BAAANQAECgIIAgAAAA==.Shortigen:BAAANQADCgQIBQAAAA==.Shrilynda:BAAANQADCgUIBwAAAA==.Shupala:BAAANQAECgIIBAAAAA==.',
Si='Sicnus:BAAANQADCgIIAgAAAA==.Sinadin:BAAANQAECgQIBwAAAA==.',
Sk='Skolmaster:BAAANQADCgcIEQAAAA==.Skootter:BAAANQADCgYIBwAAAA==.Skyfury:BAAANQADCgYIDwABNQAECgIIBAACAAAAAA==.',
Sm='Smâlls:BAAANQADCggIFAAAAA==.',
Sn='Snugz:BAAANQADCgYIBgAAAA==.',
So='Soleil:BAAANQAECgIIAgAAAA==.Sourdiesel:BAAANQADCgYIDAAAAA==.Southsound:BAAANQAECgQIBAAAAA==.',
St='Stallos:BAAANQADCgQIBAAAAA==.Stark:BAAANQADCgQIBAAAAA==.Starmie:BAAANQADCgcIBwAAAA==.Steakknife:BAAANQADCgcIDQAAAA==.Sturma:BAAANQAECgMIBAAAAA==.',
Su='Superrad:BAAANQADCgcIFQAAAA==.',
Sw='Swayla:BAAANQADCgUIBwAAAA==.Sweatyhog:BAAANQADCggICgAAAA==.',
Sy='Sybil:BAAANQADCggIDgAAAA==.',
['Sà']='Sàlvage:BAAANQADCgYIBgAAAA==.',
['Sí']='Sínner:BAAANQADCgIIAgAAAA==.',
Ta='Tahfyn:BAAANQADCgcIDwAAAA==.Tahtiania:BAAANQADCgYICgAAAA==.Tazedtilblue:BAAANQADCgYIDwAAAA==.',
Te='Ted:BAAANQAECgIIAgAAAA==.Teo:BAAANQAECgQIBAAAAA==.Teyamat:BAAANQAECgQIBAABNQABCgQIBwACAAAAAA==.',
Th='Thalumind:BAAANQADCgQIBAAAAA==.Thelock:BAAANQAECgYICAAAAA==.Thetree:BAABNQAECoEYAAMGAAkJkRajCABpAgAGAAkJkRajCABpAgAHAAMJwhVXQQC/AAAAAA==.Thien:BAAANQADCgUIBQAAAA==.Thoinus:BAAANQADCgYIBwABNQAECgQIBAACAAAAAA==.Thundertaco:BAAANQADCggICAAAAA==.Thundertwig:BAAANQAECgIIAgAAAA==.',
Ti='Timoris:BAAANQADCgQIBAABNQAECgYICAACAAAAAA==.',
To='Tobiume:BAAANQADCgUICQABNQAECgYIDAACAAAAAA==.Tofulhundun:BAAANQADCggIEAAAAA==.Toggo:BAAANQADCgQIBQAAAA==.Tommytwotusk:BAAANQADCgcIEAAAAA==.',
Tr='Trenon:BAAANQADCgYICAAAAA==.Triannah:BAAANQAECgIIAgAAAA==.Trildjr:BAAANQADCggIDwAAAA==.',
Tu='Tuchmi:BAAANQADCgYIBgAAAA==.Tuldag:BAAANQAECgIIAgAAAA==.',
Ty='Tyrse:BAAANQADCgcIDwAAAA==.',
Tz='Tzerina:BAAANQADCgcIEQAAAA==.',
['Tâ']='Tânkyû:BAAANQADCgUIBQAAAA==.',
['Tï']='Tïmbits:BAAANQADCgYIBgAAAA==.',
Ut='Uthadravis:BAAANQADCggIDwABNQAECgEIAQACAAAAAQ==.',
Va='Valford:BAAANQAECgEIAQAAAA==.Validan:BAAANQADCgYICAAAAA==.Vallyrie:BAAANQAECgUICgAAAA==.Valssharess:BAAANQADCggIFQAAAA==.Valth:BAAANQADCgQIBQAAAA==.Valzen:BAAANQADCgEIAQAAAA==.Vanae:BAAANQADCgMIAwAAAA==.Vaporgriffin:BAAANQADCgcIDAAAAA==.',
Ve='Velendez:BAAANQADCgEIAQAAAA==.Veleria:BAAANQAECgUIBgAAAA==.Vellysonna:BAAANQADCgYIBgAAAA==.Versatina:BAAANQADCgQIBQAAAA==.',
Vi='Victra:BAAANQADCggIEwAAAA==.Viko:BAAANQADCgcICQAAAA==.Vinaya:BAAANQADCgQIBQAAAA==.',
Vo='Volthemar:BAAANQAECgUIBgAAAA==.Voodoopunch:BAAANQABCgIIAgAAAA==.',
Wa='Warrpath:BAAANQADCgEIAQAAAA==.Watsuki:BAAANQADCgQIBAABNQADCgcIEQACAAAAAA==.',
We='Weoo:BAAANQADCgYIBwAAAA==.Werrick:BAAANQAECgIIAgAAAA==.',
Wh='Whitespot:BAAANQADCgQIBgAAAA==.',
Wi='Wisegurl:BAAANQAECgUIBQAAAA==.',
Wo='Woodpecker:BAAANQAECgQIBAAAAA==.',
Wr='Wreckreation:BAAANQAECgIIAgAAAA==.',
Wy='Wylecsham:BAAANQADCgUIBQAAAA==.Wylectra:BAAANQAECgQIBAAAAA==.',
Xe='Xethos:BAAANQADCgQIBAAAAA==.',
Ya='Yanikå:BAAANQADCgQICAAAAA==.',
Ye='Yeira:BAAANQAECgQIBQAAAA==.Yerdedmatey:BAAANQADCggICAAAAA==.',
Yo='Yourdemon:BAAANQADCgcICQAAAA==.',
Za='Zagasham:BAAANQAECgQIBAAAAA==.Zahvaria:BAAANQADCgcIDwAAAA==.Zaphiell:BAAANQAECgEIAQAAAA==.',
Ze='Zeid:BAAANQAECgYICAAAAA==.Zev:BAAANQADCgQIBAAAAA==.',
Zi='Zillz:BAAANQADCgYIDAAAAA==.Zinderalanot:BAAANQAECgEIAQAAAQ==.',
Zo='Zoeystorm:BAAANQAECgQIBQAAAA==.',
Zu='Zuldrak:BAAANQAECgYICgAAAA==.',
Zy='Zykie:BAAANQADCgcIBwAAAA==.',
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
