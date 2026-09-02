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
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Ackrenoth:BAAANQADCgQIBQAAAA==.',
Ad='Adynn:BAAANQAECgEIAQAAAA==.',
Af='Afridium:BAAANQADCgEIAQAAAA==.',
Ak='Akikusa:BAAANQADCgIIAgAAAA==.',
Al='Alista:BAAANQAECgIIAgAAAA==.Allyeska:BAAANQADCgMIAwAAAA==.',
Am='Amor:BAAANQADCgYICwAAAA==.',
An='Anali:BAAANQADCgcIDQAAAA==.Anani:BAAANQADCgQIBQAAAA==.Angreifer:BAAANQADCggIDwAAAA==.Anori:BAAANQADCgcICQAAAA==.',
Ao='Aonar:BAAANQADCgMIAwAAAA==.',
Ar='Arc:BAAANQADCgYIBgAAAA==.Archenteron:BAAANQADCgMIAwAAAA==.Ardorcinder:BAAANQADCgQIBwAAAA==.Arthmanafel:BAAANQAECgEIAQAAAA==.',
As='Asbjorne:BAAANQADCgYICwAAAA==.',
Au='Autumnmoon:BAAANQADCgUICQAAAA==.',
Av='Avalsong:BAAANQAECgQIBAAAAA==.Avelos:BAAANQAECgQIBAAAAA==.',
Ay='Ayowenn:BAAANQADCgEIAQAAAA==.Ayzmist:BAAANQADCgQIBAAAAA==.Ayzmyth:BAAANQADCgYICwAAAA==.',
Be='Beasic:BAAANQAECgEIAQAAAA==.Beletili:BAAANQADCgYIBgAAAA==.Beátrix:BAAANQADCgIIAgAAAA==.',
Bi='Birddh:BAAANQADCgYICwAAAA==.',
Bl='Blatendrg:BAAANQAECgEIAQAAAA==.Blindcloud:BAAANQADCgMIAwAAAA==.',
Bo='Boot:BAAANQADCgYICgAAAA==.Borodemonin:BAEANQAECgUICAAAAA==.',
Br='Breae:BAAANQAECgEIAQAAAA==.',
Bu='Bulky:BAAANQADCgYICwAAAA==.',
Ca='Cafë:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.Caistin:BAAANQADCgYIBgAAAA==.Calyma:BAAANQADCgQIBAAAAA==.Camelsotters:BAAANQADCgYIBgAAAA==.Casca:BAAANQADCgQIBwAAAA==.Catsclaw:BAAANQABCgIIAgAAAA==.',
Ce='Cenjeru:BAAANQADCggIDgAAAA==.',
Ch='Chiot:BAAANQAECgEIAQAAAA==.',
Ci='Cimerian:BAAANQADCgYIBgAAAA==.',
Cl='Clone:BAAANQADCgYIBgAAAA==.',
Co='Corange:BAAANQABCgIIAgAAAA==.Cormech:BAAANQAECgEIAQAAAA==.Cornite:BAAANQADCgUICAAAAA==.',
Cr='Crizzo:BAAANQADCggIDgAAAA==.',
Da='Daddyslilgrl:BAAANQAECgEIAQAAAA==.Dakra:BAEANQAECgEIAQAAAA==.Dalyeth:BAAANQADCgcIDAAAAA==.Darkwingorc:BAAANQAECgUIBgAAAA==.Daunt:BAAANQADCgIIAgABNQADCgYICwABAAAAAA==.Dawnfire:BAAANQADCgEIAQAAAA==.Dawnmane:BAAANQADCgEIAQAAAA==.',
De='Decypher:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.Deebz:BAAANQAECgEIAQAAAA==.Deliverance:BAAANQAECgQIBQAAAA==.Denethmon:BAAANQADCgYICwAAAA==.Dentik:BAAANQADCgcICgAAAA==.Devilina:BAAANQADCgIIAgAAAA==.',
Dh='Dheriana:BAAANQAECgEIAQAAAA==.',
Di='Diamair:BAAANQAECgEIAQAAAA==.Dixiee:BAAANQADCgUICAAAAA==.',
Dn='Dnegelpal:BAAANQADCggIDgAAAA==.',
Do='Dodgecharger:BAAANQADCgQIBwAAAA==.',
Dr='Dragerin:BAAANQAECgMIAwAAAA==.Dragonfood:BAAANQADCgcIDAAAAA==.Drakilu:BAAANQAECgEIAQAAAA==.Drakra:BAEANQADCgMIAwABNQAECgEIAQABAAAAAA==.Drasic:BAAANQAECgQIBQAAAA==.Dretro:BAAANQAECgEIAQAAAA==.Drovosi:BAAANQADCgQIBAAAAA==.',
Du='Durin:BAAANQADCgYICwAAAA==.Durward:BAAANQADCgcICAAAAA==.Duvo:BAAANQADCgcIDAAAAA==.',
['Dæ']='Dæmôna:BAAANQADCgQIBAAAAA==.',
['Dé']='Détank:BAAANQADCgUIBQAAAA==.',
Ei='Eiene:BAAANQADCgYIBgAAAA==.',
El='Elemental:BAAANQAECgQIBAABNQAECgcICAABAAAAAA==.Elloseth:BAAANQADCgUICAAAAA==.Eluneh:BAAANQADCgYICAAAAA==.',
Eo='Eolon:BAAANQADCgQIBwAAAA==.',
Ep='Epica:BAAANQAECgEIAQAAAA==.',
Er='Eragonhawk:BAAANQADCgYICgAAAA==.Eroldan:BAAANQADCgUIBQAAAA==.Erovianoria:BAAANQADCgUIBQAAAA==.',
Es='Essun:BAAANQAECgUIBwABNQABCgQIBgABAAAAAA==.',
Ev='Evanthe:BAAANQADCggIDgAAAA==.',
Fa='Fastal:BAAANQADCgQIBAAAAA==.Fauxborn:BAAANQADCgYICAAAAA==.',
Fe='Fedwell:BAAANQADCgcIDAAAAA==.',
Fi='Finngan:BAAANQADCgcIDwAAAA==.Fitoria:BAAANQADCgUICgAAAA==.',
Fo='Forestkin:BAAANQADCgQIBwABNQADCgcIDAABAAAAAA==.Foxhope:BAAANQADCgYICgAAAA==.',
Fr='Friartuk:BAAANQADCgUIBQAAAA==.Frozenthunda:BAAANQAECgIIAgAAAA==.',
Fu='Furna:BAAANQADCgcICwAAAA==.Fuzzyhooves:BAAANQAECgEIAQAAAA==.',
Ga='Gabrael:BAAANQAECgQIBQAAAA==.',
Gh='Ghorienge:BAAANQADCgYIEAAAAA==.',
Gi='Gilox:BAAANQADCggIDgAAAA==.',
Go='Gorgilz:BAAANQADCgEIAQAAAA==.Gothgirldemi:BAAANQADCggICAAAAA==.',
Gr='Graymon:BAAANQADCgMIAwAAAA==.Greebo:BAAANQADCgMIAwAAAA==.',
Gu='Guilherme:BAAANQADCgUIBQAAAA==.',
Gw='Gwenyver:BAAANQADCgYICwAAAA==.',
Ha='Hailthanatos:BAAANQAECgEIAQAAAA==.Hamord:BAAANQADCgYIBgAAAA==.Harliquette:BAAANQAECgEIAQAAAA==.Harlock:BAAANQADCggIDgAAAA==.',
He='Helleye:BAAANQADCgYICgAAAA==.',
Hi='Hiten:BAAANQAECgEIAQAAAA==.',
Ho='Hoofinmouth:BAAANQADCgYIBgAAAA==.Hopedaimond:BAAANQADCgQIBAAAAA==.',
Hu='Huntertattoo:BAAANQAECgEIAQAAAA==.Husgus:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.',
Il='Illianarra:BAAANQADCgYICgAAAA==.Ilthad:BAAANQADCggIDgAAAA==.',
Im='Imshalar:BAAANQABCgIIAgABNQADCgYICgABAAAAAA==.',
Is='Ischadè:BAAANQADCgEIAQAAAA==.Iskuros:BAAANQADCgMIAwAAAA==.',
It='Itsirk:BAAANQADCggIDgAAAA==.',
Iz='Izyebelle:BAAANQADCggICwAAAA==.',
Je='Jefeorganico:BAAANQADCgYICgAAAA==.Jeloi:BAAANQADCgYICgAAAA==.',
Ji='Jimmydin:BAAANQAECgQIBQAAAA==.',
Ju='Julkan:BAAANQADCgcIBwAAAA==.Junhoong:BAAANQADCgcIDQAAAA==.',
Jy='Jynnysa:BAAANQADCgQIBwABNQADCgcIDAABAAAAAA==.',
Ka='Kai:BAAANQADCgYICwAAAA==.Kairoll:BAAANQADCggIDgAAAA==.Kaleìna:BAAANQADCgcICAAAAA==.Kallisto:BAAANQADCgcIBwAAAA==.Karaa:BAAANQADCgIIAgAAAA==.Kariena:BAAANQADCgUICQAAAA==.Kart:BAAANQADCgEIAQAAAA==.Kashaka:BAAANQADCgUIBQAAAA==.Katesluage:BAAANQADCggIDgABNQAECgEIAQABAAAAAA==.',
Ke='Keeya:BAAANQADCgcIDAAAAA==.Kelina:BAAANQADCgIIAgAAAA==.Kendari:BAAANQADCggIDgAAAA==.Kernasas:BAAANQADCgYICgAAAA==.',
Ki='Kizaraan:BAAANQADCgUIBQAAAA==.',
Kl='Kleyntamar:BAAANQADCgMIAwAAAA==.',
Kn='Knyghtly:BAAANQADCggIBgABNQADCggIBwABAAAAAA==.',
Ko='Koric:BAAANQADCgYIDAAAAA==.',
Kr='Kretsch:BAAANQADCgUIBQAAAA==.',
Ku='Kupau:BAAANQADCgcIBwAAAA==.Kurogami:BAAANQAECgEIAQAAAA==.Kuthixo:BAAANQADCgQIBQAAAA==.',
Ky='Kylos:BAAANQABCgQIBAAAAA==.Kynnigos:BAAANQABCgIIAgAAAA==.',
La='Landstrider:BAAANQADCgMIAwABNQAECgcICAABAAAAAA==.Lanss:BAAANQAECgEIAQAAAA==.Larachel:BAAANQADCgYICwAAAA==.Lastaril:BAAANQADCgQIBQAAAA==.Lastword:BAAANQADCgYICwAAAA==.Laur:BAAANQAECgQIBQAAAA==.',
Li='Liartes:BAAANQADCgMIAwAAAA==.Liderela:BAAANQADCgEIAQAAAA==.Lilipo:BAAANQADCggIDQAAAA==.',
Lo='Logoth:BAAANQADCgYICgAAAA==.Lohgarak:BAAANQADCgcIBwAAAA==.',
Lu='Lunaellana:BAAANQADCgYICAAAAA==.',
['Lü']='Lüvpüp:BAAANQAECgQIBgAAAA==.',
Ma='Maiku:BAAANQAECgEIAQAAAA==.Makado:BAAANQADCgcIBwAAAA==.Makoroth:BAAANQADCgcIDAAAAA==.Masharu:BAAANQADCgcIBwAAAA==.Maycee:BAAANQADCgUICAAAAA==.',
Mc='Mcat:BAAANQADCgUIBQAAAA==.Mcgriddle:BAAANQADCgEIAQAAAA==.Mcsaltface:BAAANQADCgUICgAAAA==.',
Me='Meddic:BAAANQADCgUIBwAAAA==.Menarot:BAAANQADCgUIBQAAAA==.Meztlitotol:BAAANQADCgcICwABNQADCggIDwABAAAAAA==.',
Mi='Mirosmundo:BAAANQAECgQIBAAAAA==.Miyu:BAAANQAECgEIAQAAAA==.',
Mo='Mod:BAAANQADCggIDgAAAA==.Moggatorash:BAAANQADCgUICQAAAA==.Mogtham:BAAANQAECgEIAQAAAA==.Monlaferte:BAAANQADCgIIAgAAAA==.Mooforn:BAAANQADCgMIAwAAAA==.Moonfall:BAAANQADCgcICwAAAA==.Moosader:BAAANQAECgIIAgAAAA==.Morellea:BAAANQAECgEIAQAAAA==.Morighann:BAAANQADCggIDgAAAA==.Moñgoose:BAAANQADCgMIAwAAAA==.',
My='Mynkx:BAAANQADCgQIBAAAAA==.Mythyras:BAAANQADCgcIDAAAAA==.',
Na='Naeomy:BAAANQAECgMIBAAAAA==.Nahaman:BAAANQADCgUICAAAAA==.Napolien:BAAANQAECgEIAQAAAA==.Naugan:BAAANQADCgEIAQAAAA==.',
Ne='Nechahira:BAAANQAECgcICAAAAA==.',
Ni='Nien:BAAANQAECgEIAQAAAA==.Nihlathak:BAAANQADCgcIDQAAAA==.Ninada:BAAANQAECgEIAQAAAA==.',
No='Noranna:BAAANQADCgMIAwAAAA==.',
Ny='Nyim:BAAANQADCgMIAwAAAA==.',
Ob='Obsidianclaw:BAAANQADCgIIAwAAAA==.',
Oh='Ohwellz:BAAANQADCgUIBgAAAA==.',
Op='Ophin:BAAANQADCggIDAAAAA==.',
Pa='Panamared:BAAANQAECgEIAQAAAA==.Pappawoody:BAAANQADCggICwAAAA==.',
Pe='Pennyfeather:BAAANQAECgEIAQAAAA==.Pezza:BAAANQADCgcICwAAAA==.',
Ph='Phaze:BAAANQADCggIDgAAAA==.',
Pl='Pluralbutter:BAAANQAECgEIAQAAAA==.',
Po='Popexeo:BAAANQAECgcIDQAAAA==.',
Qu='Quiccerstorm:BAAANQADCgQIBQAAAA==.',
Ra='Raevennlumis:BAAANQADCgcIDgAAAA==.Rahkhard:BAAANQAECgEIAQAAAA==.Rascdit:BAAANQADCgYIBgAAAA==.',
Re='Reiyoso:BAAANQADCgQIBAAAAA==.Reui:BAAANQADCgEIAQAAAA==.',
Rh='Rhemibumbum:BAAANQADCgYIBgAAAA==.',
Ro='Roobee:BAAANQADCgcICwAAAA==.',
Ru='Ruaic:BAAANQADCgMIBAAAAA==.',
Sa='Sableanne:BAAANQADCgEIAQAAAA==.Sacréd:BAAANQADCgYICwAAAA==.Sarova:BAAANQADCgYIBgAAAA==.Satori:BAAANQADCgMIAwAAAA==.',
Sc='Scalewind:BAAANQADCgYIBgAAAA==.',
Se='Seldeath:BAAANQADCgEIAQAAAA==.Selfu:BAAANQAECgEIAQAAAA==.Sellidor:BAAANQADCgYICwAAAA==.Seriniyaa:BAAANQADCgUIBwAAAA==.',
Sh='Sheara:BAAANQAECggIBwAAAA==.Shinjiro:BAAANQADCggIDAAAAA==.Shirito:BAAANQAECgQIBAAAAA==.Shiritodh:BAAANQAECgEIAQAAAA==.Shockin:BAAANQADCggIDwAAAA==.Shortnstout:BAAANQAECgQIBQAAAA==.Shugo:BAAANQADCgYICgAAAA==.',
Si='Sienje:BAAANQADCgYICgAAAA==.Sigma:BAAANQAECgEIAQAAAA==.Simpleson:BAAANQAECgEIAQAAAA==.Sinbàd:BAAANQAECgUIBwAAAA==.',
Sk='Skie:BAAANQADCggIBwAAAA==.Skrabble:BAAANQADCgYICgAAAA==.',
Sl='Slaete:BAAANQADCgYICgAAAA==.',
Sm='Smallz:BAAANQADCgQIBwABNQADCgcIDAABAAAAAA==.',
So='Solemn:BAAANQADCgUIBQABNQADCgYICwABAAAAAA==.Solrana:BAAANQADCgUICgAAAA==.Songmistress:BAAANQADCgYICQAAAA==.Sorren:BAAANQADCgQIBQAAAA==.Sozin:BAAANQADCgIIAgAAAA==.',
St='Stardrive:BAAANQADCgUICQAAAA==.',
Su='Sunasha:BAAANQADCgUIBwAAAA==.Superbautumn:BAAANQADCgQIBAAAAA==.',
Ta='Tachyon:BAAANQADCggICAABNQAECgQIBgABAAAAAA==.Tagnaras:BAAANQADCgYIBgAAAA==.Tali:BAAANQADCgYICwAAAA==.Tangle:BAAANQADCgcIDAABNQADCggIBwABAAAAAA==.Tanka:BAAANQAECgEIAQAAAA==.Tannisse:BAAANQADCgIIAwAAAA==.Tashlaraz:BAEANQADCgMIAwAAAA==.Taurannosaur:BAAANQADCgMIAwAAAA==.Taurentots:BAAANQAECgEIAQAAAA==.',
Te='Telkas:BAAANQADCgUIBQAAAA==.Temporantus:BAAANQADCgQIBQAAAA==.Tenko:BAAANQADCggIDwAAAA==.',
Th='Thaddeus:BAAANQADCgcICwAAAA==.Therm:BAAANQAFFAEIAQAAAA==.Thoramier:BAAANQADCgYIBgAAAA==.',
Ti='Tibble:BAAANQADCgYICwAAAA==.Timoonja:BAAANQADCgQICAAAAA==.',
To='Tonatuih:BAAANQAECgIIAgAAAA==.',
Tr='Trezzia:BAAANQAECgEIAQAAAA==.Triipod:BAAANQADCgQIBQAAAA==.Trinkat:BAAANQADCgMIAwAAAA==.Trojinn:BAAANQADCgcICwAAAA==.Tryst:BAAANQADCgYIBgAAAA==.',
Ty='Tylean:BAAANQADCgUICgAAAA==.',
Uu='Uu:BAAANQADCgYIDAAAAA==.',
Va='Vadrozsa:BAAANQADCgUIBwAAAA==.Vareyn:BAAANQADCgYIBwAAAA==.',
Vo='Vorth:BAAANQAECgEIAQAAAA==.',
Vu='Vulturous:BAAANQADCgYICgAAAA==.',
Wa='Waldir:BAAANQAECgEIAQAAAA==.Watz:BAAANQADCgYIDAAAAA==.',
Wh='Wholesale:BAAANQADCggIDgAAAA==.',
Wr='Wrack:BAAANQADCgQIBQAAAA==.Wraithian:BAAANQABCgQIBAAAAA==.',
Xh='Xheero:BAAANQAECgQIBAAAAA==.',
Yu='Yulica:BAAANQADCgMIAwAAAA==.',
Za='Zaffy:BAAANQADCgcIDAAAAA==.Zaktrix:BAAANQADCgMIBQAAAA==.Zaleron:BAAANQADCgIIAgAAAA==.Zaruba:BAAANQADCgUIBQABNQADCgYICwABAAAAAA==.Zatkyng:BAAANQAECgEIAQAAAA==.',
Ze='Zekos:BAAANQADCgUIBwAAAA==.',
Zi='Zimdalar:BAAANQADCgYICgAAAA==.',
Zu='Zulre:BAAANQADCggIDQAAAA==.',
['Ôv']='Ôverkill:BAAANQADCgcICwAAAA==.',
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
