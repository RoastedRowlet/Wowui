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

local lookup = {'Unknown-Unknown','Shaman-Restoration','DeathKnight-Unholy','Rogue-Subtlety','Warrior-Arms','Warrior-Fury','Rogue-Assassination',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Aberaht:BAAANQAECgUIBwAAAA==.Absolution:BAAANQADCgcIEgAAAA==.',
Ac='Ackianae:BAAANQAECgQIBAAAAA==.',
Ad='Adewey:BAAANQAECgEIAgAAAA==.',
Ae='Aenastian:BAAANQADCgUIDwABNQAECgYICAABAAAAAA==.',
Ak='Akhalla:BAAANQADCgEIAQABNQADCgYIEQABAAAAAA==.Akumä:BAAANQADCgUIBQAAAA==.',
Al='Aleannia:BAAANQADCggICAAAAA==.Alekz:BAAANQADCgYIBgAAAA==.Alestria:BAAANQAECgQIBAAAAA==.Algodón:BAAANQADCgEIAgABNQAECgcIDwABAAAAAA==.Allus:BAAANQABCgQIBwAAAA==.Alphaomega:BAAANQADCgcIEAAAAA==.',
An='Anarcy:BAAANQADCgQIBgAAAA==.Anastaysha:BAAANQABCgQIBAABNQADCgUIBQABAAAAAA==.',
Ar='Ardatha:BAAANQADCgIIAgAAAA==.Ariêz:BAAANQADCgQIBAAAAA==.',
As='Astrocakes:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
At='Athenä:BAAANQAECggIEgAAAA==.Atsuma:BAAANQADCgYIBgAAAA==.Atthel:BAAANQAECgEIAQAAAA==.',
Ay='Aylah:BAAANQABCgIIAgABNQAECgQIBQABAAAAAA==.',
Az='Azei:BAAANQADCgMIAwAAAA==.',
['Aí']='Aísling:BAAANQADCggIFQAAAA==.',
Ba='Baela:BAAANQAECgMIAwABNQAECgkJFgACALYjAA==.Bajafresh:BAAANQADCgMIAwAAAA==.',
Be='Benjinana:BAAANQAECgIIAgAAAA==.',
Bk='Bkunstopabl:BAAANQADCgIIAgAAAA==.',
Bl='Bloodbraid:BAAANQADCgMIAwAAAA==.',
Bo='Boricua:BAAANQADCgYIBgAAAA==.Bountty:BAAANQADCgYIBgAAAA==.',
Br='Brightbane:BAAANQAECgEIAQAAAA==.',
Bu='Bulleitrye:BAAANQADCgYIBgAAAA==.',
By='Byorn:BAAANQAECgYIBwAAAA==.',
Ca='Cairdamane:BAAANQAECgQIBQAAAA==.Calidrina:BAAANQAECgQIBgAAAA==.',
Ce='Celldrassil:BAAANQADCggIEgAAAA==.Cereel:BAAANQADCgYICAABNQAECgIIAgABAAAAAA==.',
Ch='Chardaney:BAAANQADCgUIBQAAAA==.',
Ci='Cii:BAAANQAECgIIAgAAAA==.Ciruzita:BAAANQADCgUIBQAAAA==.',
Co='Colandros:BAAANQADCgEIAQAAAA==.Colara:BAAANQADCggIFQAAAA==.Colbear:BAAANQABCgQIBAAAAA==.Coldspace:BAAANQAECgYICAAAAA==.',
Cr='Crassberry:BAABNQAECoEWAAIDAAkJESPtAwB5AwADAAkJESPtAwB5AwAAAA==.Creepindeath:BAAANQADCgYIBgAAAA==.',
Cy='Cyndal:BAAANQABCgUIBwABNQAECgQIBQABAAAAAA==.Cyntu:BAAANQABCgYICAABNQAECgQIBQABAAAAAA==.',
Da='Dankothy:BAAANQADCgUIDgABNQADCggICAABAAAAAA==.Dantes:BAAANQADCgIIAgAAAA==.Darkryu:BAAANQADCgUICgAAAA==.Darthsix:BAAANQADCgEIAQAAAA==.Dazex:BAAANQADCgYIEAAAAA==.',
De='Deathforever:BAAANQADCgYICgAAAA==.Deaus:BAAANQADCggIEgAAAA==.Delrus:BAAANQAECgQIAwAAAA==.Demon:BAAANQAECgUIBAABNQAECgkJFwAEAKkaAA==.Denzvic:BAAANQADCgYIEQAAAA==.Destro:BAAANQADCggICAAAAA==.Devil:BAAANQABCgQIBAAAAA==.',
Di='Disowneege:BAAANQADCgcIDwABNQAECgkJFgAFALYgAA==.',
Do='Doodu:BAAANQAECgcIBwAAAA==.',
Dr='Dragnas:BAAANQAECgUICAAAAA==.Drakass:BAAANQADCggICAAAAA==.Drakeskid:BAAANQAECgUIDAAAAA==.Dramakiller:BAAANQADCgYIEAAAAA==.Drcornbread:BAAANQAECgIIAgAAAA==.Drcornellia:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Drdreggs:BAAANQADCgcIEgAAAA==.',
Du='Durden:BAAANQADCgIIAgABNQAECgEIAwABAAAAAA==.',
El='Elastar:BAAANQAECgUIBwAAAA==.Ellimist:BAEANQAECgcIDAAAAA==.Elsan:BAAANQADCgQIBAAAAA==.Elycee:BAAANQAECgMIAwAAAA==.',
En='Enveliria:BAAANQADCgUIBQABNQAECgYICAABAAAAAA==.',
Er='Eraser:BAAANQAECgQIBwAAAA==.Erazar:BAAANQADCgcIEgAAAA==.Erickk:BAAANQAECgQICgAAAA==.Eristela:BAAANQADCgMIBAAAAA==.',
Es='Escanorlion:BAAANQADCgYIEQAAAA==.Essense:BAAANQAECgUIBwAAAA==.',
Ex='Exodari:BAAANQAECgQIBQAAAA==.',
Fa='Fabbioh:BAAANQADCgEIAQAAAA==.Fadeddh:BAAANQAECgIIAgAAAA==.',
Fe='Fel:BAAANQAECgYICwAAAA==.',
Fi='Fibitz:BAAANQAECgYICgAAAA==.Findstewie:BAAANQABCgQIBgAAAA==.Fiofio:BAAANQAECgUIBwAAAA==.Fizban:BAAANQAECgIIAgAAAA==.',
Fl='Flik:BAAANQADCgUIBQABNQAECgYICwABAAAAAA==.',
Fr='Frigidheart:BAAANQAECgQIBwABNQAECgcICgABAAAAAA==.',
Ga='Gadogear:BAAANQADCggIEwAAAA==.Galabren:BAAANQAECgYIBwAAAA==.Garlik:BAAANQADCgUICAAAAA==.',
Gf='Gfr:BAAANQAECgEIAQAAAA==.',
Gi='Gilnean:BAAANQABCgEIAQAAAA==.',
Go='Goatcheeze:BAAANQAECgEIAQAAAA==.Gohlemsaurus:BAAANQABCgIIAwAAAA==.',
Gu='Gulen:BAAANQADCgYICwAAAA==.',
Gw='Gwennevier:BAAANQABCgUICAAAAA==.',
['Gí']='Gíga:BAAANQAECgQIAwAAAA==.',
Ha='Halsten:BAAANQADCgcIDQAAAA==.',
He='Hellenkeller:BAEANQAECgIIAwABNQAECgkJFgAEADsiAA==.',
Hi='Hitt:BAAANQADCgcIDQAAAA==.',
Ho='Hogwortsfun:BAAANQADCggICAAAAA==.',
Hr='Hroc:BAAANQAECgIIAgAAAA==.',
Ic='Icywolfy:BAAANQAECgIIAgAAAA==.',
Il='Illune:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.',
Im='Imleapingit:BAAANQADCggIDgAAAA==.',
In='Intoodeep:BAAANQAECgUICQAAAA==.',
Ir='Ir:BAAANQAECgYICwAAAA==.',
Is='Isawarriorr:BAAANQAECgQIBgAAAA==.Ishdo:BAAANQAECgIIAgAAAA==.Ishlok:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Ja='Jakytreehorn:BAAANQAECgcIEQAAAA==.',
Je='Jenevelle:BAAANQADCgYIBgAAAA==.Jerisil:BAAANQADCgMIAwAAAA==.Jessiel:BAAANQADCggIEgAAAA==.Jet:BAAANQAECgUIBwAAAA==.',
Ju='Julthaenia:BAAANQAECgIIAgABNQAECgYICAABAAAAAA==.',
Ka='Kagebushin:BAAANQABCgIIAgAAAA==.Kagome:BAAANQADCgQIBAABNQADCgUIBQABAAAAAA==.Kalofelement:BAAANQADCgEIAQAAAA==.Karash:BAAANQAECgEIAwAAAA==.Karnrae:BAAANQADCggIDAAAAA==.Karynos:BAAANQAECgMIBAAAAA==.Katwolf:BAAANQAECgEIAQAAAA==.Katyah:BAAANQAECgQIBAAAAA==.',
Ke='Keynivas:BAAANQADCgYIBgAAAA==.',
Ko='Konspiracy:BAAANQAECgMIBAAAAA==.',
Kr='Kraguva:BAAANQADCgEIAQAAAA==.Krataar:BAAANQAECgEIAQAAAA==.Krous:BAAANQAECgcIEgAAAA==.Kryph:BAAANQAECgMIAgAAAA==.',
['Kä']='Kämpfer:BAAANQADCgcIFQABNQAECgQIBwABAAAAAA==.',
La='Lafiel:BAAANQAECgMIBAAAAA==.Landiedoo:BAAANQAECggIAQAAAA==.Laurandre:BAAANQAECgIIAgAAAA==.',
Le='Letsgetwet:BAAANQADCgUIBQAAAA==.',
Li='Liefic:BAAANQADCgYIBgAAAA==.Lilibeth:BAAANQADCggICgAAAA==.Lilstooge:BAAANQABCgMIAwABNQABCgQIBgABAAAAAA==.',
Ll='Llylith:BAAANQABCgEIAQAAAA==.',
Lu='Luckykilla:BAAANQAECgMIBAAAAA==.Lucÿ:BAAANQAECgYIDwAAAA==.Lune:BAAANQADCgMIBgAAAA==.Lurith:BAAANQAECgMIBAAAAA==.Luxtyrannica:BAAANQADCgYIBgAAAA==.',
Ly='Lydrain:BAAANQADCgIIAgAAAA==.',
Ma='Marahh:BAAANQABCgIIAgAAAA==.Mattbolt:BAAANQAECgEIAgAAAA==.Mayu:BAAANQADCgQIBAAAAA==.Mazigos:BAAANQADCggIDgAAAA==.',
Me='Medjrab:BAAANQADCggICQAAAA==.Meristem:BAAANQADCggIEgAAAA==.Merko:BAAANQADCgEIAQABNQAECgYICgABAAAAAA==.',
Mi='Mignius:BAAANQADCgYIBgAAAA==.Mistified:BAAANQABCgIIBAAAAA==.',
Mo='Moedorai:BAAANQAECgMIBQAAAA==.Mogma:BAAANQADCgUIBQAAAA==.Moonbounds:BAAANQAECggIEAAAAA==.Moondoggey:BAAANQADCgUIBQAAAA==.Morgana:BAAANQADCgUIBQAAAA==.Mousechief:BAAANQADCgcIDwAAAA==.Moxxzi:BAAANQAECgIIAgAAAA==.',
Mu='Muhfookinbak:BAAANQADCggIDwAAAA==.',
Na='Naksu:BAAANQADCgYICgABNQADCggIEAABAAAAAA==.Naksù:BAAANQADCgUIBQABNQADCggIEAABAAAAAA==.Naksü:BAAANQADCggIEAAAAA==.',
Ne='Neifeb:BAAANQAECgIIAgAAAA==.Nerfherder:BAAANQABCgYIBgAAAA==.',
Ni='Nights:BAAANQAECgIIAwABNQAECgkJFwAEAKkaAA==.Ninh:BAAANQAECgYICwAAAA==.Ninthgate:BAAANQADCgUICgAAAA==.',
No='Nogood:BAAANQAECgQIBAAAAA==.Northwest:BAAANQABCgYIBQAAAA==.Notsodemon:BAAANQAECgQICAAAAA==.Notsomage:BAAANQAECgQIBAABNQAECgQICAABAAAAAA==.',
Ny='Nyorai:BAAANQABCgQIAwAAAA==.Nyxwing:BAAANQADCgQIBAAAAA==.',
['Në']='Nëao:BAAANQADCgYIBgAAAA==.',
Ob='Obvinotagirl:BAAANQAECgIIAwAAAA==.',
Od='Odinheâthen:BAAANQABCgYIBgAAAA==.',
Ol='Olydwarf:BAAANQAECgEIAQAAAA==.',
On='Onebadmutha:BAAANQADCggICAAAAA==.Ontop:BAAANQAECgYICwAAAA==.',
Or='Orb:BAAANQAECgEIAQAAAA==.Ortinks:BAAANQAECgEIAQAAAA==.',
Ow='Owneege:BAABNQAECoEWAAMFAAkJtiC/DwAPAwAFAAkJnSC/DwAPAwAGAAMJXSH0CAAjAQAAAA==.',
Pa='Paapaa:BAAANQADCgcIBQAAAA==.Pallinar:BAAANQADCggIEAAAAA==.Pasquale:BAAANQADCgUICQAAAA==.',
Pe='Pebbles:BAAANQAECgUIBgAAAA==.Pedorus:BAAANQABCgYIBwABNQAECgYIDwABAAAAAA==.',
Pi='Picklericky:BAAANQADCgIIBAAAAA==.Pilgrimm:BAEBNQAECoEWAAMEAAkJOyLVAgBAAwAEAAgJGiXVAgBAAwAHAAEJQQvrLwBDAAAAAA==.Pistola:BAAANQADCgUIBQAAAA==.',
Pl='Plaguerott:BAAANQAECgQIBQAAAA==.Plaguewind:BAAANQADCgEIAQAAAA==.',
Po='Polydh:BAAANQAECgUIBgAAAA==.Poobah:BAAANQADCggIEwAAAA==.Popsicles:BAAANQAECgUIBQAAAA==.Pouffant:BAAANQAECgEIAQAAAA==.',
Pr='Praddagy:BAAANQADCgUIBQAAAA==.Pronoz:BAAANQADCggIAQAAAA==.',
Pu='Purpyl:BAAANQADCgYIEQAAAA==.',
Pw='Pwnjitsu:BAAANQAECgUIBwAAAA==.',
Py='Pyrothermia:BAAANQAECggIEwAAAA==.',
Ra='Rakugan:BAAANQABCgMIAwAAAA==.Rawhoof:BAAANQAECgYICwAAAA==.Razak:BAAANQAECgYICwAAAA==.',
Rd='Rdnckromeo:BAAANQADCgIIAgAAAA==.',
Re='Redlock:BAAANQADCgcIEQAAAA==.Redrum:BAAANQAECgQICQAAAA==.Renarin:BAAANQAECgYICwAAAA==.Renisa:BAAANQAECgIIAgAAAA==.Retman:BAAANQADCggIDgAAAA==.Revlyk:BAAANQAECgIIBAABNQAECgYICAABAAAAAA==.',
Rh='Rhoanna:BAAANQADCgQIBAAAAA==.Rhoupert:BAAANQADCggIDAABNQAECgQIBAABAAAAAA==.',
Ro='Roccot:BAAANQAECgUIBwAAAA==.Rotjaw:BAAANQADCggICgAAAA==.',
['Rè']='Rèjuva:BAAANQADCgEIAQAAAA==.',
Sa='Saintess:BAAANQABCgYIDAAAAA==.',
Sc='Scalycat:BAAANQAECgQIBgAAAA==.Schuey:BAAANQADCggICAAAAA==.Scum:BAAANQADCgYIBgAAAA==.',
Se='Senaeda:BAAANQADCgQIBAAAAA==.Senate:BAAANQAECgUIBgAAAA==.',
Sh='Shablaam:BAAANQADCggIAQAAAA==.Shadowbear:BAAANQADCgcIEAAAAA==.Sherrilyn:BAAANQADCgIIAgAAAA==.',
Si='Singularity:BAAANQAECgEIAQAAAA==.',
Sk='Skelli:BAEANQAECggIDQABNQAECgcIDAABAAAAAA==.Skittlesdan:BAAANQAECgUIBQAAAA==.',
Sl='Slaykween:BAAANQADCgYICQAAAA==.',
Sm='Smallz:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Sn='Sneakin:BAAANQADCgIIAgAAAA==.Snooptrogg:BAAANQAECgIIAgAAAA==.',
Sp='Spacelaser:BAAANQADCgMIAwAAAA==.Specialtwo:BAAANQADCgEIAQAAAA==.',
Sq='Sqwurl:BAAANQADCgUIBQAAAA==.',
St='Stonedragon:BAEANQAECggIEwAAAA==.Stormrender:BAAANQAECgUIBQAAAA==.Stormriders:BAAANQADCgYICAAAAA==.Stouty:BAAANQADCgQIAQAAAA==.Streea:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.Stubz:BAAANQABCgQIBgAAAA==.',
Su='Sukonamí:BAAANQAECgMIBAAAAA==.Suzhou:BAAANQADCggIEwAAAA==.Suzoomies:BAAANQADCggIDwAAAA==.',
Sw='Swisscheese:BAAANQAECgUIBgAAAA==.',
Sy='Sycò:BAAANQAECgcICgAAAA==.',
['Sú']='Súbzerø:BAAANQAECgEIAQABNQAECgcIEQABAAAAAA==.',
Ta='Taedish:BAAANQADCgQIBAAAAA==.Tahzdingle:BAAANQADCgYICwAAAA==.',
Te='Teknobutts:BAAANQADCgUIBQAAAA==.Tenastin:BAAANQADCgIIAgAAAA==.Terragosa:BAAANQADCggIEgAAAA==.Tetchybono:BAAANQADCggIDgAAAA==.Tettra:BAAANQABCgEIAQABNQAECgQIBQABAAAAAA==.',
Th='Thahawtz:BAAANQADCgYIBgAAAA==.Thirinis:BAAANQADCgUIBgAAAA==.Thope:BAAANQADCgYIEAAAAA==.Thundergirl:BAAANQADCgMIAwAAAA==.',
Tr='Traesdyne:BAAANQADCgMIBAAAAA==.Trailwalkur:BAAANQADCgYIDAABNQAECgIIAgABAAAAAA==.Trainar:BAAANQABCgYICgAAAA==.Trollbear:BAAANQADCgcIBwAAAA==.Trooze:BAAANQADCgcIDQAAAA==.',
Tu='Tuba:BAAANQADCgYIDAAAAA==.Turim:BAAANQADCgUICAAAAA==.',
Ty='Tyrlidd:BAAANQADCggIEgAAAA==.',
Un='Unavoidable:BAAANQADCgMIAwAAAA==.Unholirolla:BAAANQADCgUIBQAAAA==.Unlikelytale:BAAANQAECgUIBQAAAA==.',
Ur='Uricash:BAAANQAECgYIDAAAAA==.Urzual:BAAANQAECgMIAgAAAA==.',
Va='Vandreynna:BAAANQAECgYICAAAAA==.',
Ve='Vehlrine:BAAANQADCgIIAgAAAA==.Velveetah:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Verbrennen:BAAANQAECgQIBwAAAA==.Verita:BAAANQADCgcIEgAAAA==.',
Vi='Viviann:BAAANQAECgUIBwAAAA==.',
Wa='Warraxe:BAAANQADCgYIBgAAAA==.Wayloren:BAAANQAECgMIAgAAAA==.',
Wi='Wickathy:BAAANQAECgQIAgAAAA==.',
Wo='Worstdps:BAAANQAECgYICwAAAA==.',
Wu='Wuldorr:BAAANQAECggICAAAAA==.',
Wy='Wynnifred:BAAANQAECgIIAgAAAA==.',
Xa='Xaltheris:BAAANQADCgcIEgAAAA==.',
Xe='Xethreal:BAAANQADCggIEgAAAA==.',
Xz='Xzara:BAAANQAECgQIBQAAAA==.',
Yv='Yvvee:BAAANQADCggICAAAAA==.',
Zi='Zifao:BAAANQAECgEIAQAAAA==.',
Zo='Zonora:BAAANQAECgYICgAAAA==.',
['Äz']='Äzrael:BAAANQAECgIIAgAAAA==.',
['Çr']='Çréwüsæðèr:BAAANQADCggIEwAAAA==.',
['Ðì']='Ðìaßlo:BAAANQAECgcIEQAAAA==.',
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
