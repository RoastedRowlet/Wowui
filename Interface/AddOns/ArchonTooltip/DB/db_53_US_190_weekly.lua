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

local lookup = {'Unknown-Unknown','Druid-Feral','Warrior-Arms','Warrior-Fury','Mage-Arcane','Hunter-Marksmanship',}
local provider = {region='US',realm='Shadowsong',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aarazi:BAAANQAECgMIAwAAAA==.',
Ab='Abolish:BAAANQABCgIIAgAAAA==.',
Ae='Aeriss:BAAANQADCgIIAgAAAA==.',
Ag='Agamotto:BAAANQADCgMIAwAAAA==.Agerol:BAAANQADCggIFQAAAA==.',
Ah='Ahnari:BAAANQADCgcIDgAAAA==.',
Ak='Akkadien:BAAANQAECgcICgAAAA==.Akumunter:BAAANQADCggIGgAAAA==.',
Al='Alacardias:BAAANQAECgEIAgAAAA==.Alihuntress:BAAANQADCgIIAwAAAA==.',
Am='Amarynth:BAAANQADCgQIBAAAAA==.Amäri:BAAANQAECgYICgAAAA==.',
An='Anassand:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.Andimorph:BAAANQAECgEIAQAAAA==.Angeleria:BAAANQADCgUIBQAAAA==.',
Ap='Apazz:BAAANQAECgEIAQAAAA==.',
Aq='Aqualight:BAAANQAECgIIAgABNQAECgQIBgABAAAAAA==.Aquaterra:BAAANQAECgQIBgAAAA==.Aquina:BAAANQABCgIIAgABNQAECgQIBgABAAAAAA==.',
Ar='Arakadia:BAAANQAECgQIBQAAAA==.Artoriaz:BAAANQADCgcICwAAAA==.Aruteeru:BAAANQADCggIFAAAAA==.',
As='Aseanna:BAAANQADCggIDAAAAA==.Astraen:BAAANQADCgQIBgAAAA==.',
Au='Auxiliater:BAAANQADCgEIAQAAAA==.Auxiliator:BAAANQADCgYIBgAAAA==.Auxlox:BAAANQADCgYIBgAAAA==.',
Av='Avarous:BAAANQADCggIFQAAAA==.',
Ax='Axará:BAAANQADCgQIBAAAAA==.Axel:BAAANQADCgUIBwAAAA==.',
Ay='Ayala:BAAANQAECgcICgAAAA==.',
Az='Azaireos:BAAANQADCgIIAwAAAA==.Azulpunkt:BAAANQAECgcIDQAAAA==.',
Ba='Baddaboomkin:BAAANQADCgEIAQAAAA==.Bananashamma:BAAANQAECgEIAQAAAA==.',
Be='Bearmao:BAAANQAECgUIBQAAAA==.Beknight:BAAANQAECgUIBwAAAA==.Belfas:BAAANQADCgcICQAAAA==.Bellah:BAAANQABCgIIAgAAAA==.Bellybutton:BAAANQAECgEIAQAAAA==.',
Bi='Bigpeach:BAAANQADCgEIAQAAAA==.Biltong:BAAANQAECgEIAQAAAA==.',
Bl='Blackpink:BAAANQADCgUIBQAAAA==.Bludnite:BAAANQAECgcIDgABNQADCgQIBAABAAAAAA==.',
Bo='Bokchoi:BAAANQADCggIGwAAAA==.Boom:BAAANQADCgMIBwAAAA==.',
Br='Brey:BAAANQADCggICAAAAA==.Bruute:BAAANQAECgUICAAAAA==.',
Bu='Budplatinum:BAAANQADCgQIBAAAAA==.',
['Bâ']='Bâït:BAAANQADCggICAAAAA==.',
['Bå']='Båcon:BAAANQABCgQIBAAAAA==.',
Ca='Cairo:BAAANQAECgQIBQAAAA==.Capitalchaos:BAAANQAECgIIAgABNQAECgQICQABAAAAAA==.Capnbeni:BAAANQADCgMIAwAAAA==.Cassandraa:BAAANQADCgIIAwAAAA==.Castingchaos:BAAANQAECgQICQAAAA==.',
Ce='Cell:BAAANQAECgYICQAAAA==.Ceviche:BAAANQAECgUIBwAAAA==.Ceàrrdòrn:BAAANQAECgEIAQAAAA==.',
Ch='Chibí:BAAANQADCggIFgAAAA==.Chillzmatic:BAAANQAECgEIAQAAAA==.Chudbucket:BAAANQAECgUIBwAAAA==.',
Cl='Clovergold:BAAANQAECgYIBwAAAA==.Clyde:BAAANQAECgMIAwAAAA==.',
Co='Corbis:BAEANQAECgIIAgAAAA==.',
Cr='Crevarus:BAAANQADCgUIDAAAAA==.Crimsonjeybi:BAAANQAECgIIAgAAAA==.Crunchwich:BAAANQADCgYIBgAAAA==.',
Cu='Cutename:BAAANQADCgEIAQAAAA==.',
Cy='Cynamyn:BAAANQADCgYIBgAAAA==.',
Cz='Czeskilight:BAAANQADCgIIAgAAAA==.',
['Cö']='Cömet:BAAANQADCgcICAAAAA==.',
Da='Daane:BAAANQADCgIIAwAAAA==.Daevarys:BAAANQADCgEIAQAAAA==.Dakhran:BAAANQADCgIIBAAAAA==.Darkdemon:BAAANQADCgcIDQAAAA==.Darlord:BAAANQADCgYIBgAAAA==.Dawnliht:BAAANQADCgIIAgAAAA==.',
De='Deagle:BAAANQABCgIIAgABNQAECgQICAABAAAAAA==.Deandrya:BAAANQADCgQIBAAAAA==.Deedubbya:BAAANQADCgcIBwAAAA==.Delryd:BAAANQADCgYIBgAAAA==.Demônlock:BAAANQADCgYIAwAAAA==.Desideria:BAAANQADCggIFQAAAA==.Desynn:BAAANQAECgMIBAAAAA==.',
Di='Divinesyn:BAAANQADCgYIBgAAAA==.',
Dj='Djelysium:BAAANQADCgYIAwAAAA==.Djtaki:BAAANQAECgYICgAAAA==.',
Do='Dogwater:BAAANQADCgYIBgABNQAECgkJIAACAN0lAA==.Doncarlos:BAAANQAECgYICwAAAA==.Dorn:BAAANQADCgUIBQAAAA==.Dotty:BAAANQADCgQIBQAAAA==.Dottzz:BAAANQADCgYIBgAAAA==.Downbeatxo:BAEANQAFFAEIAQAAAA==.',
Dr='Dròòid:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.',
Du='Dubdred:BAAANQADCgQIBAAAAA==.Duhon:BAAANQADCgQIBAAAAA==.Dumptruck:BAAANQAECgMIAwAAAA==.',
Dw='Dwín:BAAANQAECgIIAgAAAA==.',
['Dê']='Dêals:BAAANQAECgQIBAAAAA==.',
El='Eliselyia:BAAANQADCgQIBgAAAA==.Ellierose:BAAANQAECgUIBwAAAA==.',
Em='Ems:BAAANQADCgQIBwAAAA==.',
En='Enjin:BAAANQAECgQIBgAAAA==.Entheogen:BAAANQADCgcICwAAAA==.',
Eo='Eogan:BAAANQADCgIIAwAAAA==.',
Er='Erolas:BAAANQADCgIIAwAAAA==.',
Et='Ethereall:BAAANQAECgcICgAAAA==.',
Ev='Evanessance:BAAANQADCgEIAQAAAA==.Evilice:BAAANQAECgQIBgAAAA==.Evoka:BAAANQAECgEIAQAAAA==.',
Fa='Fallendevout:BAAANQAECgIIAgAAAA==.Fallentroll:BAAANQAECggIEAAAAA==.Faydark:BAAANQADCgQIBAAAAA==.Fayye:BAAANQADCggIDAAAAA==.',
Fi='Fireflydh:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Firragol:BAAANQABCgQIBAAAAA==.Firèflyjd:BAAANQAECgEIAQAAAA==.',
Fl='Floatpass:BAAANQAECgcICAAAAA==.',
Fr='Frizz:BAAANQADCgUIAwAAAA==.Froey:BAEANQAECgMIAwAAAA==.',
Fu='Fuzzynuttz:BAAANQADCggICAAAAA==.Fuzzypally:BAAANQAECgUIBwAAAA==.',
Ga='Gali:BAAANQADCgQIBAAAAA==.Galiagante:BAAANQADCgQIBAAAAA==.Gallynna:BAAANQAECgMIBQAAAA==.Galorfax:BAAANQADCgcIFAAAAA==.Galushi:BAAANQADCgIIAwAAAA==.Garm:BAAANQAECgUIBwAAAA==.',
Ge='Genovese:BAEANQADCgYIDAABNQAECgIIAgABAAAAAA==.',
Gi='Gilgaroth:BAAANQAECgMIAwAAAA==.Girlslove:BAAANQADCgIIAgABNQAECgkJIAACAN0lAA==.',
Go='Gobo:BAAANQAECgIIAgAAAA==.',
Gr='Graysonn:BAAANQADCgcIDAAAAA==.Greafox:BAAANQADCgEIAQAAAA==.Grýla:BAAANQADCgUIBQAAAA==.',
Gu='Gundrakk:BAAANQAECgQIBQAAAA==.Gunnr:BAAANQAECgIIAwAAAA==.',
He='Heid:BAAANQADCgIIAwAAAA==.',
Hi='Higanbana:BAAANQAFFAIIAwAAAA==.Himawari:BAAANQAECgQIBAABNQAFFAIIAwABAAAAAA==.Himejoshi:BAABNQAECoEgAAICAAkJ3SVtAACtAwACAAkJ3SVtAACtAwAAAA==.Hippocampus:BAAANQADCgcIEQAAAA==.Hirys:BAAANQAECgcIEQAAAA==.',
Ho='Holybeks:BAAANQADCgQIBAABNQAECgUIBwABAAAAAA==.Hotdoggin:BAAANQADCgEIAQAAAA==.',
['Há']='Háldrin:BAAANQAECggIEAAAAA==.',
Ic='Icëcrëam:BAAANQADCggICAAAAA==.',
Im='Imbue:BAAANQAECgIIAgAAAA==.Imbuer:BAAANQADCgYIEQAAAA==.',
In='Innil:BAAANQAECgUICQAAAA==.',
Ja='Jarda:BAAANQAECgUICwAAAA==.',
Je='Jessix:BAAANQADCgYIBgAAAA==.Jezebel:BAAANQAECgEIAQAAAA==.',
Ji='Jimfowler:BAAANQADCgIIAgAAAA==.Jirito:BAAANQAECgIIAgAAAA==.',
Jo='Jomadead:BAAANQAECgEIAQABNQAECgcIEQABAAAAAA==.Jomas:BAAANQAECgcIEQAAAA==.',
Ju='Judera:BAAANQAECgUIBQAAAA==.',
Ka='Kaing:BAAANQADCgcIDQAAAA==.Kaladen:BAAANQAECgMIAwAAAA==.Kalysti:BAAANQAECgEIAQAAAQ==.Kaoticnature:BAAANQADCgIIAwAAAA==.Karolg:BAAANQAECgMIAwAAAA==.Katostrafic:BAAANQAECgMIAwAAAA==.',
Ke='Kelarra:BAAANQADCgQIBgAAAA==.',
Kh='Khromscarin:BAAANQAECgYICwAAAA==.',
Ki='Killidan:BAAANQAECgUIBwAAAA==.Kirklees:BAAANQADCgYIBgAAAA==.',
Ko='Kodama:BAAANQAECgMIBAAAAA==.Koi:BAAANQADCgcIEgABNQAECgMIBQABAAAAAA==.Kookiemon:BAAANQADCgEIAQAAAA==.Kopili:BAAANQADCgUIBwAAAA==.',
Kr='Kromag:BAAANQADCgYIBgAAAA==.',
Ku='Kunpochiken:BAAANQABCgEIAQABNQAECgMIAwABAAAAAA==.',
Ky='Kyanna:BAAANQADCgYIBQAAAA==.',
La='Ladifantasie:BAAANQADCgUIBQAAAA==.Laria:BAAANQADCgcIBwAAAA==.Laxinmedium:BAAANQADCgIIAwAAAA==.',
Le='Leenei:BAAANQADCgYIBgAAAA==.Lenlaar:BAAANQADCgUIAwAAAA==.Levande:BAAANQADCgYIDAAAAA==.',
Li='Lifeblume:BAAANQADCgUIBQAAAA==.Lilithandria:BAAANQAECgMIBAAAAA==.Linamar:BAAANQADCgcIFwAAAA==.',
Lo='Loaq:BAAANQAECgYICQAAAA==.Longbottom:BAAANQADCgYIBgAAAA==.Lorbert:BAAANQADCgQIAwABNQAECgQICQABAAAAAA==.Lostalot:BAAANQAECgMIBQAAAA==.',
Lu='Luxæterna:BAAANQAECgQICQAAAA==.',
Ly='Lyphiara:BAAANQADCgcIDAABNQAECgMIBQABAAAAAA==.',
Ma='Malice:BAAANQAECgUICwAAAA==.Mandwandos:BAAANQAECgMIAwAAAA==.Maraliss:BAAANQADCggIFAAAAA==.',
Me='Melaunis:BAAANQADCgUIBQAAAA==.Meowzer:BAAANQAECgQIBAABNQAECgcIDAABAAAAAA==.Meteora:BAAANQAECgYIEAAAAA==.',
Mi='Mideel:BAAANQADCgYIBgAAAA==.Migolbearcow:BAAANQAECgMIBAAAAA==.Missed:BAAANQAECgEIAQAAAA==.Missedweaver:BAAANQADCgYICAABNQAECgEIAQABAAAAAA==.Missrae:BAAANQADCgQIBAAAAA==.',
Ml='Mlglock:BAAANQADCgMIAwAAAA==.',
Mo='Moiira:BAAANQAECgEIAQAAAA==.Monyshot:BAAANQADCgIIAgAAAA==.Mooniè:BAAANQADCggIFAAAAA==.Moosenuts:BAAANQAECgIIAgAAAA==.Moriavus:BAAANQAECgQIBwAAAA==.Morocha:BAAANQADCgcIDAAAAA==.Mortèm:BAAANQAECgIIAgAAAA==.',
Mu='Muragore:BAAANQADCgYIDQAAAA==.',
My='Mychropien:BAAANQADCgUICAAAAA==.Myylus:BAAANQADCgMIBQAAAA==.',
['Mö']='Mökes:BAAANQAECgYICQAAAA==.',
Na='Nazzersaurus:BAAANQAECgEIAQAAAA==.',
Ne='Nec:BAAANQADCgYICgAAAA==.Necrøtic:BAAANQAECgMIAwAAAA==.Nekosmasta:BAAANQABCgIIAgAAAA==.Neodin:BAAANQADCgcIFwAAAA==.Nevermiss:BAAANQAECgMIBAAAAA==.',
Ni='Nightjewel:BAAANQADCgIIAwAAAA==.',
No='Noggs:BAAANQADCggICAAAAA==.Notmewasyou:BAAANQAECgEIAQAAAA==.',
Nu='Nuali:BAAANQADCgUIBQABNQAECgMIBQABAAAAAA==.Numi:BAAANQADCgUIBwAAAA==.',
Od='Odysseus:BAAANQADCgUICQAAAA==.',
Ok='Okameshiz:BAAANQADCgUIBQAAAA==.',
On='Onlyspins:BAAANQAECgYIBgAAAA==.',
Or='Orý:BAAANQAECgYICAAAAA==.',
Ox='Oxosorrel:BAAANQABCgYIDgAAAA==.',
Pa='Paladan:BAAANQAECgUIBwAAAA==.Palagi:BAAANQADCgYIDwAAAA==.Pallyana:BAAANQAECgEIAQAAAA==.Pallymcbeall:BAAANQADCgUIDAAAAA==.Paprikaman:BAAANQADCgYIAwAAAA==.Parallax:BAAANQADCgEIAQAAAA==.Parishealton:BAAANQADCgQIBAAAAA==.Payday:BAAANQADCgUIBQAAAA==.Pazzuzu:BAAANQADCgUIBQAAAA==.',
Po='Poulsbo:BAAANQADCgYIBgAAAA==.Pozole:BAAANQADCggICAAAAA==.',
Pr='Prominence:BAAANQAECgQIBgAAAA==.Promisques:BAAANQADCgUIBQAAAA==.Prozak:BAAANQAECgEIAgAAAA==.',
Py='Pyrolily:BAAANQADCgcIEQAAAA==.',
Qu='Question:BAAANQADCgEIAQAAAA==.Qulung:BAAANQADCgcIDAAAAA==.',
Ra='Rabyd:BAAANQADCggICAAAAA==.Raegasm:BAAANQADCgYIBgAAAA==.Raha:BAAANQADCgUIDQAAAA==.Raskela:BAAANQAECgIIAwAAAA==.',
Re='Reesespiecez:BAAANQAECgIIBAAAAA==.Rellidana:BAAANQADCgYIBgAAAA==.Rexi:BAAANQAECgcIEQAAAA==.',
Ri='Rickcando:BAAANQAECgIIAgAAAA==.Ricshard:BAAANQAECgEIAQAAAA==.',
Ru='Rungar:BAAANQADCggIEAAAAA==.',
['Rà']='Ràein:BAAANQAECgMIAwAAAA==.',
['Ró']='Ród:BAAANQAECgcIEgAAAA==.',
Sa='Saalira:BAAANQADCgQIBwAAAA==.Sabellice:BAAANQAECgEIAQAAAA==.Sakonna:BAAANQAECgYIDwAAAA==.Salinoria:BAAANQAECgMIBQAAAA==.Sandymaw:BAAANQABCgYICgABNQAECgcIDAABAAAAAA==.Sarlius:BAAANQAECgYICAAAAA==.Sassybuns:BAAANQABCgQIBAAAAA==.Satyrical:BAAANQAECgQIBAAAAA==.Savin:BAAANQADCggIEAAAAA==.',
Sc='Scavenger:BAAANQADCggIFQAAAA==.',
Se='Selkamonk:BAAANQAECgMIBQAAAA==.Seniorbold:BAAANQAECgEIAQAAAA==.Sentrina:BAAANQAECgYIDwAAAA==.Seraph:BAAANQAECgEIAgAAAA==.Seshy:BAAANQAECgcIDAAAAA==.',
Sh='Shamanagins:BAAANQADCgEIAQAAAA==.Shannoon:BAAANQADCgQIBAAAAA==.Sharr:BAAANQADCgYIBgAAAA==.Shekzeer:BAAANQAECgQICAAAAA==.Shiverr:BAAANQADCggIEwAAAA==.Shockakan:BAAANQABCgQIBAAAAA==.Shockazulu:BAAANQADCgIIAgAAAA==.Shocktard:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.',
Si='Siegatrox:BAAANQADCgIIAQAAAA==.Silgan:BAAANQADCgYIBgAAAA==.',
Sk='Skizem:BAAANQABCgQIBQAAAA==.Skott:BAAANQADCggIDwAAAA==.',
Sl='Sleepadin:BAAANQADCggIEQAAAA==.Sleepyr:BAAANQAECgYICwAAAA==.',
Sn='Snowi:BAAANQADCgYIBgABNQAECgIIAwABAAAAAA==.Snowstorm:BAAANQAECgEIAQAAAA==.',
So='Soakra:BAAANQAECgUIBQAAAA==.Solignis:BAABNQAECoEYAAMDAAkJpCWbAgDBAwADAAkJOyWbAgDBAwAEAAEJECfwDwB0AAAAAA==.Soohots:BAAANQADCggICAAAAA==.',
Sp='Sparklehappy:BAAANQADCggIFQAAAA==.',
St='Stormcreek:BAAANQADCgQIBAAAAA==.Storri:BAAANQAECgQIBQAAAA==.',
Su='Suzuya:BAAANQADCgYIBgAAAA==.',
Sw='Swiftmage:BAABNQAECoEYAAIFAAkJMCQlBACrAwAFAAkJMCQlBACrAwAAAA==.Switchboard:BAAANQADCgYICgAAAA==.',
Sy='Sygh:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Syndragonkin:BAAANQAECgIIAgAAAA==.Syndrome:BAAANQADCggIDgAAAA==.Synger:BAAANQADCgIIAgAAAA==.',
Ta='Talyndis:BAACNQAFFIEIAAIGAAUJFhsWAQDcAQAGAAUJFhsWAQDcAQA1AAQKgRkAAgYACQlUI/gBAJkDAAYACQlUI/gBAJkDAAAA.Tamyr:BAAANQADCgIIAgAAAA==.Taze:BAAANQAECgUIBgABNQADCgQIBAABAAAAAA==.Tazjiingo:BAAANQADCgIIBAAAAA==.',
Te='Ted:BAAANQADCggIEAAAAA==.Terna:BAAANQADCgUIBQAAAA==.Terrika:BAAANQADCgcIEwAAAA==.Tetshajeh:BAAANQAECgYICwAAAA==.Teyliana:BAAANQADCgYIBgAAAA==.',
Th='Thillarick:BAAANQADCggIFQAAAA==.Thwip:BAAANQAECggIEwAAAA==.',
Ti='Tikwid:BAAANQADCgcIDQAAAA==.Tiranmyashol:BAAANQAECgQICQAAAA==.',
To='Tomoya:BAAANQAECgcIDQAAAA==.Too:BAAANQADCgEIAQAAAA==.Toothdk:BAAANQAECgQIBwAAAA==.',
Tr='Treebreak:BAAANQAECgQIBAAAAA==.',
Ud='Udari:BAAANQADCgUIBQAAAA==.Udarii:BAAANQAECgIIAgAAAA==.',
Um='Umàdbrah:BAAANQAECgEIAQAAAA==.',
Un='Unbelievable:BAAANQADCggIEQAAAA==.Unprovoked:BAAANQAECgYICwAAAA==.',
Va='Valamor:BAAANQAECgEIAQAAAA==.',
Ve='Veefib:BAAANQAECgMIAwAAAA==.Velvettwitch:BAAANQAECgIIAgAAAA==.Vendler:BAAANQAECgEIAQAAAA==.Verahla:BAAANQADCgQIBQAAAA==.Vermis:BAAANQAECgQIBwAAAA==.Veryaverage:BAAANQAECgEIAgAAAA==.Vexation:BAAANQADCgUIBwAAAA==.',
Vi='Vicarious:BAAANQADCggIFAAAAA==.Vidreaux:BAAANQAECgQIBQAAAA==.Villaraa:BAAANQADCgEIAQAAAA==.',
Vo='Voidofvoids:BAAANQADCgcIBwAAAA==.Votingromney:BAAANQADCgEIAQABNQAECgQICAABAAAAAA==.Vowz:BAAANQADCgMIAwAAAA==.',
Vu='Vulpe:BAAANQAECgQIBwAAAA==.',
Vy='Vyolenta:BAAANQADCgIIAgAAAA==.',
Wa='Waldorf:BAAANQADCgYIBgAAAA==.Walleroot:BAAANQADCggICAAAAA==.',
Wh='Whitewhitch:BAAANQADCgIIAwAAAA==.Whosethetank:BAAANQADCgYIBQAAAA==.',
Wo='Wolfpup:BAAANQAECgIIAQABNQAECgUIBQABAAAAAA==.Worstelf:BAAANQAECgMIAwAAAA==.',
Xz='Xzavier:BAAANQADCgIIAwAAAA==.',
Yf='Yfelshammy:BAAANQAECgIIAgAAAA==.',
Yv='Yvaldi:BAAANQADCgYICwABNQAECgYICgABAAAAAA==.Yvonnél:BAAANQADCgQIBAAAAA==.',
Za='Zanebusby:BAAANQAECgEIAQAAAA==.Zankru:BAAANQADCgEIAQAAAA==.Zaraë:BAAANQADCggIDgAAAA==.Zaria:BAAANQAECgEIAQABNQAECgQICAABAAAAAA==.Zartash:BAAANQAECgEIAgAAAA==.Zatharis:BAAANQADCggIEgAAAA==.',
Ze='Zelik:BAAANQABCgUIBQABNQAECgYICAABAAAAAA==.Zevellian:BAAANQADCgYIBgABNQAECgcICgABAAAAAA==.',
Zm='Zmona:BAAANQAECgQIBgAAAA==.',
Zo='Zolrath:BAAANQABCgQIAgAAAA==.',
['Äm']='Ämpstarr:BAAANQADCgEIAQAAAA==.',
['Çy']='Çyanide:BAAANQADCgQICgABNQAECgQIBAABAAAAAA==.',
['Ðr']='Ðragonshaft:BAAANQAECgMIBAAAAA==.',
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
