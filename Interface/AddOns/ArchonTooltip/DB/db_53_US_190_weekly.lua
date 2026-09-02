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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='Shadowsong',name='US',type='weekly',zone=53,date='2026-09-01',data={Ae='Aeriss:BAAANQADCgIIAgAAAA==.',
Ag='Agerol:BAAANQADCgcIDQAAAA==.',
Ah='Ahnari:BAAANQADCgQIBwAAAA==.',
Ak='Akkadien:BAAANQAECgQIBAAAAA==.Akumunter:BAAANQADCgcIDwAAAA==.',
Al='Alacardias:BAAANQAECgEIAQAAAA==.Alihuntress:BAAANQADCgIIAwAAAA==.',
Am='Amarynth:BAAANQADCgQIBAAAAA==.Amäri:BAAANQAECgQIBAAAAA==.',
An='Anassand:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Andimorph:BAAANQADCgcICwAAAA==.Angeleria:BAAANQADCgUIBQAAAA==.',
Ap='Apazz:BAAANQADCgYIBgAAAA==.',
Aq='Aqualight:BAAANQADCgcIDgABNQAECgIIAgABAAAAAA==.Aquaterra:BAAANQAECgIIAgAAAA==.',
Ar='Arakadia:BAAANQADCggIDgAAAA==.Artoriaz:BAAANQADCgQIBAAAAA==.Aruteeru:BAAANQADCgcIDAAAAA==.',
As='Aseanna:BAAANQADCgQIBAAAAA==.Astraen:BAAANQADCgQIBgAAAA==.',
Au='Auxiliater:BAAANQADCgEIAQAAAA==.Auxiliator:BAAANQADCgYIBgAAAA==.',
Av='Avarous:BAAANQADCgcIDQAAAA==.',
Ax='Axel:BAAANQADCgUIBwAAAA==.',
Ay='Ayala:BAAANQAECgYICQAAAA==.',
Az='Azaireos:BAAANQADCgIIAwAAAA==.Azulpunkt:BAAANQAECgYIBgAAAA==.',
Ba='Bananashamma:BAAANQADCggIDQAAAA==.',
Be='Bearmao:BAAANQADCggIDgAAAA==.Beknight:BAAANQAECgIIAgAAAA==.Belfas:BAAANQADCgIIAwAAAA==.Bellah:BAAANQABCgIIAgAAAA==.Bellybutton:BAAANQAECgEIAQAAAA==.',
Bi='Bigpeach:BAAANQADCgEIAQAAAA==.',
Bl='Blackpink:BAAANQADCgUIBQAAAA==.Bludnite:BAAANQAECgYIBwABNQADCgQIBAABAAAAAA==.',
Bo='Bokchoi:BAAANQADCggIEwAAAA==.Boom:BAAANQADCgIIBAAAAA==.',
Br='Bruute:BAAANQAECgMIAwAAAA==.',
Bu='Budplatinum:BAAANQADCgQIBAAAAA==.',
['Bå']='Båcon:BAAANQABCgQIBAAAAA==.',
Ca='Cairo:BAAANQAECgIIAgAAAA==.Capitalchaos:BAAANQADCggICwABNQAECgQIBQABAAAAAA==.Capnbeni:BAAANQADCgMIAwAAAA==.Cassandraa:BAAANQADCgIIAwAAAA==.Castingchaos:BAAANQAECgQIBQAAAA==.',
Ce='Cell:BAAANQAECgMIAwAAAA==.Ceviche:BAAANQAECgIIAgAAAA==.',
Ch='Chibí:BAAANQADCggIDwAAAA==.Chillzmatic:BAAANQADCgYICgAAAA==.Chudbucket:BAAANQABCgQIBAAAAA==.',
Cl='Clovergold:BAAANQAECgEIAQAAAA==.Clyde:BAAANQADCggIDQAAAA==.',
Cr='Crevarus:BAAANQADCgUICwAAAA==.Crimsonjeybi:BAAANQADCggICAAAAA==.Crunchwich:BAAANQADCgUIAwAAAA==.',
Cu='Cutename:BAAANQADCgEIAQAAAA==.',
Cy='Cynamyn:BAAANQADCgUIAwAAAA==.',
Cz='Czeskilight:BAAANQADCgIIAgAAAA==.',
['Cö']='Cömet:BAAANQADCgcICAAAAA==.',
Da='Daane:BAAANQADCgIIAwAAAA==.Dakhran:BAAANQADCgIIAgAAAA==.Darkdemon:BAAANQADCgcIDQAAAA==.Darlord:BAAANQADCgUIAwAAAA==.',
De='Deagle:BAAANQABCgIIAgABNQAECgQIBQABAAAAAA==.Deedubbya:BAAANQADCgYIBgAAAA==.Delryd:BAAANQADCgUIAwAAAA==.Desideria:BAAANQADCgcIDQAAAA==.Desynn:BAAANQAECgEIAQAAAA==.',
Di='Divinesyn:BAAANQADCgYIBgAAAA==.',
Dj='Djtaki:BAAANQAECgQIBAAAAA==.',
Do='Dogwater:BAAANQADCgYIBgABNQAECggIDwABAAAAAA==.Doncarlos:BAAANQAECgQIBQAAAA==.Dotty:BAAANQADCgQIBQAAAA==.Downbeatxo:BAEANQAECggICgAAAA==.',
Dr='Dròòid:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.',
Dw='Dwín:BAAANQAECgIIAgAAAA==.',
['Dê']='Dêals:BAAANQADCgcIDAAAAA==.',
El='Eliselyia:BAAANQADCgQIBAAAAA==.Ellierose:BAAANQAECgIIAgAAAA==.',
Em='Ems:BAAANQADCgMIAwAAAA==.',
En='Enjin:BAAANQAECgIIAgAAAA==.Entheogen:BAAANQADCgcICwAAAA==.',
Eo='Eogan:BAAANQADCgIIAgAAAA==.',
Er='Erolas:BAAANQADCgIIAwAAAA==.',
Et='Ethereall:BAAANQAECgMIAwAAAA==.',
Ev='Evanessance:BAAANQADCgEIAQAAAA==.Evilice:BAAANQAECgIIAgAAAA==.Evoka:BAAANQAECgEIAQAAAA==.',
Fa='Fallendevout:BAAANQAECgIIAgAAAA==.Fallentroll:BAAANQAECgYICAAAAA==.Faydark:BAAANQADCgMIAwAAAA==.Fayye:BAAANQADCgQIBAAAAA==.',
Fi='Fireflydh:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Firragol:BAAANQABCgQIBAAAAA==.Firèflyjd:BAAANQADCgYIBgAAAA==.',
Fl='Floatpass:BAAANQAECgEIAQAAAA==.',
Fr='Frizz:BAAANQADCgUIAwAAAA==.Froey:BAEANQAECgMIAwAAAA==.',
Fu='Fuzzynuttz:BAAANQADCggICAAAAA==.Fuzzypally:BAAANQAECgIIAgAAAA==.',
Ga='Gali:BAAANQADCgQIBAAAAA==.Galiagante:BAAANQADCgQIBAAAAA==.Gallynna:BAAANQAECgIIAgAAAA==.Galorfax:BAAANQADCgcIDQAAAA==.Galushi:BAAANQADCgIIAwAAAA==.Garm:BAAANQAECgIIAgAAAA==.',
Ge='Genovese:BAAANQADCgYIDAAAAA==.',
Gi='Gilgaroth:BAAANQADCggIDQAAAA==.Girlslove:BAAANQADCgIIAgABNQAECggIDwABAAAAAA==.',
Go='Gobo:BAAANQADCgcIDAAAAA==.',
Gr='Graysonn:BAAANQADCgcICwAAAA==.Grýla:BAAANQADCgUIBQAAAA==.',
Gu='Gundrakk:BAAANQAECgIIAgAAAA==.Gunnr:BAAANQADCgcIBwAAAA==.',
He='Heid:BAAANQADCgIIAwAAAA==.',
Hi='Higanbana:BAAANQAFFAEIAQAAAA==.Himawari:BAAANQADCggIDgABNQAFFAEIAQABAAAAAA==.Himejoshi:BAAANQAECggIDwAAAA==.Hippocampus:BAAANQADCgUIBQAAAA==.Hirys:BAAANQAECgYICgAAAA==.',
Ho='Hotdoggin:BAAANQADCgEIAQAAAA==.',
['Há']='Háldrin:BAAANQAECgYICAAAAA==.',
Ic='Icëcrëam:BAAANQADCggICAAAAA==.',
Im='Imbue:BAAANQADCggIDwAAAA==.Imbuer:BAAANQADCgYICwAAAA==.',
In='Innil:BAAANQAECgQIBAAAAA==.',
Ja='Jarda:BAAANQAECgUIBgAAAA==.',
Je='Jessix:BAAANQADCgMIAwAAAA==.Jezebel:BAAANQADCggIDgAAAA==.',
Ji='Jimfowler:BAAANQADCgIIAgAAAA==.',
Jo='Jomadead:BAAANQAECgEIAQABNQAECgcICgABAAAAAA==.Jomas:BAAANQAECgcICgAAAA==.',
Ju='Judera:BAAANQAECgQIBAAAAA==.',
Ka='Kaing:BAAANQADCgYIBgAAAA==.Kaladen:BAAANQADCgYIBgAAAA==.Kalysti:BAAANQADCgcIDQAAAQ==.Kaoticnature:BAAANQADCgIIAwAAAA==.Karolg:BAAANQAECgMIAwAAAA==.Katostrafic:BAAANQADCggIDgAAAA==.',
Ke='Kelarra:BAAANQADCgIIAgAAAA==.',
Kh='Khromscarin:BAAANQAECgQIBQAAAA==.',
Ki='Killidan:BAAANQAECgIIAgAAAA==.Kirklees:BAAANQADCgUIAwAAAA==.',
Ko='Kodama:BAAANQAECgEIAQAAAA==.Koi:BAAANQADCgYICwABNQAECgIIAgABAAAAAA==.Kopili:BAAANQADCgUIBwAAAA==.',
Ku='Kunpochiken:BAAANQABCgEIAQABNQADCggIDgABAAAAAA==.',
Ky='Kyanna:BAAANQADCgUIAgAAAA==.',
La='Lader:BAAANQADCggIEAAAAA==.Laria:BAAANQADCgcIBwAAAA==.Laxinmedium:BAAANQADCgIIAwAAAA==.',
Le='Leenei:BAAANQADCgUIAwAAAA==.Lenlaar:BAAANQADCgUIAwAAAA==.Levande:BAAANQADCgYIDAAAAA==.',
Li='Lilithandria:BAAANQAECgEIAQAAAA==.Linamar:BAAANQADCgYIEAAAAA==.',
Lo='Loaq:BAAANQAECgMIAwAAAA==.Lorbert:BAAANQADCgQIAwABNQAECgQIBAABAAAAAA==.Lostalot:BAAANQAECgIIAgAAAA==.',
Lu='Luxæterna:BAAANQAECgMIBQAAAA==.',
Ly='Lyphiara:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Ma='Malice:BAAANQAECgQIBgAAAA==.Mandwandos:BAAANQAECgEIAQAAAA==.Maraliss:BAAANQADCgYIDAAAAA==.',
Me='Meowzer:BAAANQADCgYICAABNQAECgQIBQABAAAAAA==.Meteora:BAAANQAECgYICgAAAA==.',
Mi='Mideel:BAAANQADCgUIAwAAAA==.Migolbearcow:BAAANQAECgEIAQAAAA==.Missed:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Missedweaver:BAAANQADCgYIBgAAAA==.Missrae:BAAANQABCgIIAgAAAA==.',
Ml='Mlglock:BAAANQADCgMIAwAAAA==.',
Mo='Moiira:BAAANQAECgEIAQAAAA==.Monyshot:BAAANQADCgIIAgAAAA==.Mooniè:BAAANQADCgYIDAAAAA==.Moriavus:BAAANQAECgMIAwAAAA==.Morocha:BAAANQADCgcICAAAAA==.',
Mu='Muragore:BAAANQADCgYIDAAAAA==.',
My='Mychropien:BAAANQADCgUICAAAAA==.Myylus:BAAANQADCgIIBAAAAA==.',
['Mö']='Mökes:BAAANQAECgQIBAAAAA==.',
Na='Nazzersaurus:BAAANQADCggIDwAAAA==.',
Ne='Nec:BAAANQADCgMIBAAAAA==.Necrøtic:BAAANQABCgMIAwAAAA==.Neodin:BAAANQADCgYIEAAAAA==.Nevermiss:BAAANQAECgEIAQAAAA==.',
Ni='Nightjewel:BAAANQADCgIIAwAAAA==.',
No='Notmewasyou:BAAANQADCgcIDAAAAA==.',
Nu='Nuali:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Od='Odysseus:BAAANQADCgQIBAAAAA==.',
On='Onlyspins:BAAANQAECgYIBgAAAA==.',
Or='Orý:BAAANQAECgIIAgAAAA==.',
Ox='Oxosorrel:BAAANQABCgQIBAAAAA==.',
Pa='Paladan:BAAANQAECgIIAgAAAA==.Palagi:BAAANQADCgYICgAAAA==.Pallyana:BAAANQADCggIDgAAAA==.Pallymcbeall:BAAANQADCgQIBwAAAA==.Parallax:BAAANQADCgEIAQAAAA==.Parishealton:BAAANQADCgQIBAAAAA==.Pazzuzu:BAAANQADCgUIBQAAAA==.',
Po='Poulsbo:BAAANQADCgUIAwAAAA==.',
Pr='Prominence:BAAANQAECgIIAgAAAA==.Prozak:BAAANQAECgEIAQAAAA==.',
Py='Pyrolily:BAAANQADCgcIDAAAAA==.',
Qu='Qulung:BAAANQADCgUIBQAAAA==.',
Ra='Raha:BAAANQADCgUIDQAAAA==.Raskela:BAAANQAECgEIAQAAAA==.',
Re='Reesespiecez:BAAANQAECgIIAgAAAA==.Rellidana:BAAANQADCgUIAwAAAA==.Rexi:BAAANQAECgcICwAAAA==.',
Ri='Rickcando:BAAANQADCgUICAAAAA==.Ricshard:BAAANQAECgEIAQAAAA==.',
Ru='Rungar:BAAANQADCgYICQAAAA==.',
['Rà']='Ràein:BAAANQADCgcICwAAAA==.',
['Ró']='Ród:BAAANQAECgcICwAAAA==.',
Sa='Saalira:BAAANQADCgQIBwAAAA==.Sabellice:BAAANQAECgEIAQAAAA==.Sakonna:BAAANQAECgUICQAAAA==.Salinoria:BAAANQAECgIIAgAAAA==.Sandymaw:BAAANQABCgQIBAABNQAECgQIBQABAAAAAA==.Sarlius:BAAANQAECgIIAgAAAA==.Sassybuns:BAAANQABCgQIBAAAAA==.Satyrical:BAAANQAECgEIAQAAAA==.Savin:BAAANQADCgYICAAAAA==.',
Sc='Scavenger:BAAANQADCgcIDQAAAA==.',
Se='Selkamonk:BAAANQAECgIIAgAAAA==.Seniorbold:BAAANQADCgUIBQAAAA==.Sentrina:BAAANQAECgYICQAAAA==.Seraph:BAAANQAECgEIAQAAAA==.Seshy:BAAANQAECgQIBQAAAA==.',
Sh='Shamanagins:BAAANQADCgEIAQAAAA==.Shannoon:BAAANQADCgQIBAAAAA==.Shekzeer:BAAANQAECgQIBQAAAA==.Shiverr:BAAANQADCgYICwAAAA==.Shockakan:BAAANQABCgIIAgAAAA==.Shockazulu:BAAANQADCgIIAgAAAA==.Shocktard:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Si='Silgan:BAAANQADCgYIBgAAAA==.',
Sk='Skizem:BAAANQABCgMIAQAAAA==.Skott:BAAANQADCgQIBwAAAA==.',
Sl='Sleepadin:BAAANQADCgYICgAAAA==.Sleepyr:BAAANQAECgQIBQAAAA==.',
Sn='Snowi:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.',
So='Soakra:BAAANQADCggIDwAAAA==.Solignis:BAAANQAECgcIDQAAAA==.',
Sp='Sparklehappy:BAAANQADCgcIDQAAAA==.',
St='Storri:BAAANQADCggIDgAAAA==.',
Sw='Swiftmage:BAAANQAECgcIDQAAAA==.Switchboard:BAAANQADCgYICgAAAA==.',
Sy='Syndrome:BAAANQADCggIDgAAAA==.Synger:BAAANQADCgEIAQAAAA==.',
Ta='Talyndis:BAAANQAFFAIIAwAAAA==.Tamyr:BAAANQADCgIIAgAAAA==.Taze:BAAANQAECgEIAQABNQADCgQIBAABAAAAAA==.Tazjiingo:BAAANQADCgIIAgAAAA==.',
Te='Ted:BAAANQADCggIEAAAAA==.Terrika:BAAANQADCgcIDAAAAA==.Tetshajeh:BAAANQAECgQIBQAAAA==.Teyliana:BAAANQADCgUIAwAAAA==.',
Th='Thillarick:BAAANQADCgcIDQAAAA==.Thwip:BAAANQAECgcICwAAAA==.',
Ti='Tikwid:BAAANQADCgYIDAAAAA==.Tiranmyashol:BAAANQAECgQIBAAAAA==.',
To='Tomoya:BAAANQAECgcICQAAAA==.Too:BAAANQADCgEIAQAAAA==.Toothdk:BAAANQAECgIIAwAAAA==.',
Tr='Treebreak:BAAANQADCgcIDgAAAA==.',
Ud='Udari:BAAANQADCgUIBQAAAA==.',
Um='Umàdbrah:BAAANQAECgEIAQAAAA==.',
Un='Unbelievable:BAAANQADCgcICQAAAA==.Unprovoked:BAAANQAECgQIBQAAAA==.',
Va='Valamor:BAAANQAECgEIAQAAAA==.',
Ve='Veefib:BAAANQADCggICgAAAA==.Velvettwitch:BAAANQADCgcIDQAAAA==.Vendler:BAAANQADCggIDAAAAA==.Verahla:BAAANQADCgQIBAAAAA==.Vermis:BAAANQAECgIIAwAAAA==.Veryaverage:BAAANQAECgEIAQAAAA==.Vexation:BAAANQADCgUIBwAAAA==.',
Vi='Vicarious:BAAANQADCgYIDAAAAA==.Vidreaux:BAAANQAECgEIAQAAAA==.Villaraa:BAAANQADCgEIAQAAAA==.',
Vo='Voidofvoids:BAAANQADCgYIBgAAAA==.Vowz:BAAANQADCgMIAwAAAA==.',
Vu='Vulpe:BAAANQAECgMIAwAAAA==.',
Vy='Vyolenta:BAAANQADCgIIAgAAAA==.',
Wa='Waldorf:BAAANQADCgYIBgAAAA==.',
Wh='Whitewhitch:BAAANQADCgIIAwAAAA==.Whosethetank:BAAANQADCgQIBAAAAA==.',
Wo='Wolfpup:BAAANQAECgIIAQABNQAECgQIBAABAAAAAA==.Worstelf:BAAANQAECgEIAQAAAA==.',
Xz='Xzavier:BAAANQADCgIIAwAAAA==.',
Yf='Yfelshammy:BAAANQAECgIIAgAAAA==.',
Yv='Yvaldi:BAAANQADCgYICwABNQAECgQIBAABAAAAAA==.',
Za='Zanebusby:BAAANQADCggIDgAAAA==.Zankru:BAAANQABCgIIAgAAAA==.Zaraë:BAAANQADCggIDgAAAA==.Zaria:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Zartash:BAAANQAECgEIAQAAAA==.Zatharis:BAAANQADCgYICgAAAA==.',
Zm='Zmona:BAAANQAECgIIAgAAAA==.',
Zo='Zolrath:BAAANQABCgQIAgAAAA==.',
['Äm']='Ämpstarr:BAAANQADCgEIAQAAAA==.',
['Çy']='Çyanide:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
['Ðr']='Ðragonshaft:BAAANQAECgEIAQAAAA==.',
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
