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

local lookup = {'Unknown-Unknown','Paladin-Retribution',}
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=53,date='2026-09-08',data={Ac='Ackrenoth:BAAANQADCgQIBQAAAA==.',
Ad='Adynn:BAAANQAECgQIBQAAAA==.',
Ae='Aeru:BAAANQADCgYIBgAAAA==.',
Af='Afridium:BAAANQADCgEIAQAAAA==.',
Ak='Akikusa:BAAANQADCggICgAAAA==.',
Al='Alista:BAAANQAECgYIBwAAAA==.Allyeska:BAAANQADCgMIAwAAAA==.',
Am='Amor:BAAANQADCggIEwAAAA==.',
An='Anali:BAAANQAECgEIAQAAAA==.Anani:BAAANQADCgQIBQAAAA==.Angreifer:BAAANQAECgcIBwAAAA==.Anori:BAAANQAECgEIAQAAAA==.',
Ao='Aonar:BAAANQADCgQIBgAAAA==.',
Aq='Aqua:BAAANQABCgUIBwAAAA==.',
Ar='Arc:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Archenteron:BAAANQADCgUICAAAAA==.Ardorcinder:BAAANQADCgUIDAAAAA==.Argentur:BAAANQADCgEIAQAAAA==.Arthmanafel:BAAANQAECgQIBQAAAA==.',
As='Asbjorne:BAAANQADCgcIEgAAAA==.',
Au='Autumnmoon:BAAANQADCgcIEAAAAA==.',
Av='Avalsong:BAAANQAECgYICgAAAA==.Avelos:BAAANQAECgYICgAAAA==.',
Ay='Ayowenn:BAAANQADCgIIAgAAAA==.Ayzmist:BAAANQADCgUIBQAAAA==.Ayzmyth:BAAANQAECgIIAgAAAA==.',
Be='Beasic:BAAANQAECgQIBQAAAA==.Beletili:BAAANQAECgQIBAAAAA==.Beátrix:BAAANQADCgIIAgAAAA==.',
Bi='Birdman:BAAANQADCgYIBgABNQADCggIEwABAAAAAA==.',
Bl='Blatendrg:BAAANQAECgQIBAAAAA==.Blindcloud:BAAANQADCgQIBAAAAA==.',
Bo='Boot:BAAANQADCgcIEQAAAA==.Borodemonin:BAEANQAECgcIDAAAAA==.',
Br='Breae:BAAANQAECgEIAQAAAA==.',
Bu='Bulky:BAAANQAECgIIAgAAAA==.',
Ca='Cadforus:BAAANQADCgMIAwABNQADCggIEwABAAAAAA==.Cafë:BAAANQADCgcICgABNQAECgcIDQABAAAAAA==.Caistin:BAAANQADCgYIBgAAAA==.Calyma:BAAANQADCgYICgAAAA==.Camelsotters:BAAANQAECgEIAQAAAA==.Casca:BAAANQADCgUIDAAAAA==.Catsclaw:BAAANQADCgYIBgAAAA==.',
Ce='Cenjeru:BAAANQAECgMIAwAAAA==.',
Ch='Chezzie:BAAANQAECgUIBQAAAA==.Chiot:BAAANQAECgQIBQAAAA==.',
Ci='Cimerian:BAAANQADCgcIBwAAAA==.',
Cl='Clone:BAAANQADCgYIBgAAAA==.',
Co='Concealer:BAAANQADCgEIAQAAAA==.Corange:BAAANQABCgIIAgAAAA==.Corlock:BAAANQADCgQIBAAAAA==.Cormech:BAAANQAECgEIAgAAAA==.Cornite:BAAANQADCgYICAAAAA==.',
Cr='Crizzo:BAAANQAECgEIAQAAAA==.',
Da='Daddyslilgrl:BAAANQAECgEIAgAAAA==.Dakra:BAEANQAECgEIAQABNQAECgQIBAABAAAAAA==.Dalyeth:BAAANQAECgEIAQAAAA==.Darkwingorc:BAAANQAECgYICwAAAA==.Daunt:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Dawnfire:BAAANQADCgEIAQAAAA==.Dawnmane:BAAANQADCgEIAQAAAA==.',
De='Deadsecsi:BAAANQABCgEIAQAAAA==.Decypher:BAAANQADCgYICwABNQAECgQIBQABAAAAAA==.Deebz:BAAANQAECgQIBQAAAA==.Deliverance:BAAANQAECgYICwAAAA==.Denethmon:BAAANQADCgcIEgAAAA==.Dentik:BAAANQAECgQIBAAAAA==.Devilina:BAAANQADCggICgAAAA==.',
Dh='Dheriana:BAAANQAECgQIBQAAAA==.Dherli:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.',
Di='Diamair:BAAANQAECgQIBQAAAA==.Divynelle:BAAANQABCgIIAgAAAA==.Dixiee:BAAANQADCgUICAAAAA==.',
Dn='Dnegelpal:BAAANQAECgUIBQAAAA==.',
Do='Dodgecharger:BAAANQADCgUIDAAAAA==.',
Dr='Dragerin:BAAANQAECgMIAwAAAA==.Dragonfood:BAAANQAECgEIAQAAAA==.Drakilu:BAAANQAECgQIBQAAAA==.Drakra:BAEANQAECgQIBAAAAA==.Drasic:BAAANQAECgUICgAAAA==.Dretro:BAAANQAECgEIAQAAAA==.Drovosi:BAAANQADCgYICgAAAA==.',
Du='Durin:BAAANQAECgEIAQAAAA==.Durward:BAAANQAECgEIAQAAAA==.Duvo:BAAANQAECgEIAQAAAA==.',
['Dæ']='Dæmôna:BAAANQADCgQIBQAAAA==.',
['Dé']='Détank:BAAANQAECgUIBQAAAA==.',
Ei='Eiene:BAAANQADCggIDgAAAA==.',
El='Elemental:BAAANQAECgYICgABNQAECgcIDwABAAAAAA==.Elloseth:BAAANQAECgEIAQAAAA==.Elmorin:BAAANQADCgcIBwAAAA==.Eluneh:BAAANQADCgYICAAAAA==.',
Eo='Eolon:BAAANQADCgUIDAAAAA==.',
Ep='Epica:BAAANQAECgQIBQAAAA==.',
Er='Eragonhawk:BAAANQADCgcIEQAAAA==.Eroldan:BAAANQADCgUIBQAAAA==.Erovianoria:BAAANQAECgUIBQAAAA==.',
Es='Essun:BAAANQAECgcIDgABNQABCgYICQABAAAAAA==.',
Ev='Evanthe:BAAANQAECgIIAgAAAA==.',
Ex='Expire:BAAANQADCgEIAQAAAA==.',
Fa='Fastal:BAAANQADCgYICAAAAA==.Fauxborn:BAAANQADCgYIDgAAAA==.',
Fe='Fedwell:BAAANQAECgEIAQAAAA==.',
Fi='Finngan:BAAANQAECgIIAgAAAA==.Fitoria:BAAANQADCgcIEQABNQAECgQIBQABAAAAAA==.',
Fo='Forestkin:BAAANQADCgUIDAABNQAECgEIAQABAAAAAA==.Foxhope:BAAANQADCgcIEQAAAA==.',
Fr='Friartuk:BAAANQAECgEIAQAAAA==.Frozenthunda:BAAANQAECgQICAAAAA==.',
Fu='Furna:BAAANQAECgEIAQAAAA==.Fuzzyhooves:BAAANQAECgQIBQAAAA==.',
Ga='Gabrael:BAAANQAECgYICwAAAA==.',
Gh='Ghorienge:BAAANQADCgcIHAAAAA==.',
Gi='Gilox:BAAANQAECgEIAQAAAA==.',
Go='Gorgilz:BAAANQADCgMIBAAAAA==.Gothgirldemi:BAAANQAECgUIBQAAAA==.',
Gr='Graymon:BAAANQADCgUICAAAAA==.Greebo:BAAANQADCgUICAAAAA==.',
Gu='Guatalupe:BAAANQADCgYIBgAAAA==.Guilherme:BAAANQADCgcICQAAAA==.',
Gw='Gwenyver:BAAANQADCgcIEgAAAA==.',
Ha='Hailthanatos:BAAANQAECgQIBQAAAA==.Hamord:BAAANQADCgcIDQAAAA==.Harliquette:BAAANQAECgQIBQAAAA==.Harliqynn:BAAANQADCgQIBAAAAA==.Harlock:BAAANQAECgQIBAAAAA==.',
Hi='Hiten:BAAANQAECgEIAQAAAA==.',
Ho='Hoofinmouth:BAAANQAECgMIAwAAAA==.Hopedaimond:BAAANQADCgQIBAAAAA==.',
Hu='Huntertattoo:BAAANQAECgEIAQAAAA==.Husgus:BAAANQADCgYIDAABNQAECgYICQABAAAAAA==.',
Il='Illianarra:BAAANQADCgYICgAAAA==.Ilthad:BAAANQAECgEIAQAAAA==.',
Im='Imshalar:BAAANQABCgIIAgABNQADCgYICgABAAAAAA==.',
Is='Ischadè:BAAANQADCgQIBQAAAA==.Iskuros:BAAANQADCgMIAwAAAA==.',
It='Itsirk:BAAANQAECgEIAQAAAA==.',
Iz='Izyebelle:BAAANQADCggIEgAAAA==.',
Je='Jefeorganico:BAAANQADCgYIDwAAAA==.Jeloi:BAAANQADCgcIEQAAAA==.',
Ji='Jimmydin:BAAANQAECgYICwAAAA==.',
Ju='Julkan:BAAANQAECgQIBAAAAA==.Junhoong:BAAANQAECgEIAQAAAA==.Juvia:BAAANQAECgUIBQABNQAECgUIBgABAAAAAA==.',
Jy='Jynnysa:BAAANQADCgQIBwABNQAECgEIAQABAAAAAA==.',
Ka='Kai:BAAANQADCgcIEgAAAA==.Kairoll:BAAANQAECgUIBQAAAA==.Kaleìna:BAAANQADCgcICAAAAA==.Kallisto:BAAANQADCgcIBwAAAA==.Karaa:BAAANQADCgIIAgAAAA==.Kariena:BAAANQADCgcIEAAAAA==.Kart:BAAANQADCgEIAQAAAA==.Kashaka:BAAANQADCgUIBQAAAA==.Katesluage:BAAANQAECgUIBQAAAA==.Kawrrl:BAAANQADCgMIAwAAAA==.',
Ke='Keeya:BAAANQAECgIIAgAAAA==.Kelina:BAAANQADCgIIAgAAAA==.Kendari:BAAANQAECgEIAQAAAA==.Kernasas:BAAANQAECgEIAQAAAA==.',
Ki='Kizaraan:BAAANQADCgUIBQAAAA==.',
Kl='Kleyntamar:BAAANQADCgUICAAAAA==.',
Kn='Knyghtly:BAAANQAECggICAAAAA==.',
Ko='Konstantien:BAAANQAECgQIBAAAAA==.Koric:BAAANQADCgcIEwAAAA==.',
Kr='Kretsch:BAAANQADCgUIBQAAAA==.',
Ku='Kupau:BAAANQAECgQIBAAAAA==.Kurogami:BAAANQAECgQIBQAAAA==.Kuthixo:BAAANQADCgUICgAAAA==.',
Ky='Kylos:BAAANQABCgQIBAAAAA==.Kynnigos:BAAANQABCgIIAgAAAA==.',
La='Landstrider:BAAANQADCggICwABNQAECgcIDwABAAAAAA==.Lanss:BAAANQAECgQIBQAAAA==.Larachel:BAAANQAECgEIAQAAAA==.Lastaril:BAAANQADCgUICQAAAA==.Lastword:BAAANQADCggIEwAAAA==.Laur:BAAANQAECgUICgAAAA==.',
Li='Liartes:BAAANQADCgUICAAAAA==.Liderela:BAAANQADCgEIAQAAAA==.Lilipo:BAAANQAECgEIAQAAAA==.',
Lo='Logoth:BAAANQADCgYICgAAAA==.Lohgarak:BAAANQADCggIDwAAAA==.',
Lu='Lunaellana:BAAANQADCgYICAAAAA==.',
Ly='Lystaan:BAAANQABCgQIBAAAAA==.',
['Lü']='Lüvpüp:BAAANQAECgcIDQAAAA==.',
Ma='Maiku:BAAANQAECgQIBQAAAA==.Makado:BAAANQAECgEIAQAAAA==.Makoroth:BAAANQAECgEIAQAAAA==.Masharu:BAAANQADCgcIBwAAAA==.Maycee:BAAANQADCgUICAAAAA==.',
Mc='Mcat:BAAANQADCgcIDAAAAA==.Mcgriddle:BAAANQADCgEIAQAAAA==.Mcnaugh:BAAANQADCgYIBgAAAA==.Mcsaltface:BAAANQADCgYIEAAAAA==.',
Me='Meddic:BAAANQADCgcIDgAAAA==.Menarot:BAAANQAECgUIBQAAAA==.Mendais:BAAANQADCgEIAQAAAA==.Meztlitotol:BAAANQADCggIEwABNQAECgcIBwABAAAAAA==.',
Mi='Mirosdrigo:BAAANQADCgcIBwAAAA==.Mirosmundo:BAAANQAECgYICgAAAA==.Miyu:BAAANQAECgQIBQAAAA==.',
Mo='Mod:BAAANQAECgUIBQAAAA==.Moggatorash:BAAANQADCgUICQAAAA==.Mogtham:BAAANQAECgQIBQAAAA==.Monlaferte:BAAANQADCgMIAwAAAA==.Mooforn:BAAANQADCgUICAAAAA==.Moonfall:BAAANQADCgcIEgAAAA==.Moosader:BAAANQAECgQIBgAAAA==.Morellea:BAAANQAECgEIAQAAAA==.Morighann:BAAANQAECgUIBQAAAA==.Moñgoose:BAAANQADCgMIAwAAAA==.',
My='Mynkx:BAAANQADCgcICwAAAA==.Mythyras:BAAANQAECgEIAQAAAA==.',
Na='Naeomy:BAAANQAECgUICQAAAA==.Nahaman:BAAANQADCgUICAAAAA==.Napolien:BAAANQAECgUIBgAAAA==.Naugan:BAAANQADCgEIAQAAAA==.',
Ne='Nechahira:BAAANQAECgcIDwAAAA==.',
Ni='Nien:BAAANQAECgEIAQAAAA==.Nihlathak:BAAANQADCgcIDQAAAA==.Ninada:BAAANQAECgQIBQAAAA==.',
No='Noranna:BAAANQADCgUICAAAAA==.',
Ny='Nyim:BAAANQAECgEIAQAAAA==.Nynsyn:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Nyxeira:BAAANQADCggICAAAAA==.',
Ob='Obsidianclaw:BAAANQADCgIIAwAAAA==.',
Oh='Ohwellz:BAAANQADCggIDgAAAA==.',
Op='Ophin:BAAANQAECgMIAwAAAA==.',
Pa='Panamared:BAAANQAECgMIAwAAAA==.Pappawoody:BAAANQAECgUIBQAAAA==.',
Pe='Pellegryn:BAAANQADCgQIBAAAAA==.Pennyfeather:BAAANQAECgQIBQAAAA==.Pezza:BAAANQADCggIEwAAAA==.',
Ph='Phaze:BAAANQAECgQIBAAAAA==.',
Pl='Pluralbutter:BAAANQAECgEIAgAAAA==.',
Po='Popexeo:BAAANQAECgcIDQABNQAFFAIIAgABAAAAAA==.',
Ps='Psyvern:BAAANQAECgEIAQAAAA==.',
Qu='Quiccerstorm:BAAANQADCgQIBQAAAA==.',
Ra='Raevennlumis:BAAANQAECgEIAQAAAA==.Rahkhard:BAAANQAECgQIBQAAAA==.Rascdit:BAAANQADCgcIBgAAAA==.',
Re='Reiyoso:BAAANQADCgQIBAAAAA==.Reui:BAAANQADCgEIAQAAAA==.',
Rh='Rhemibumbum:BAAANQADCgcIBgAAAA==.',
Ro='Rocketbilly:BAAANQADCgIIAgAAAA==.Roobee:BAAANQADCggIEwAAAA==.',
Ru='Ruaic:BAAANQADCgMIBAAAAA==.',
Sa='Sableanne:BAAANQADCgEIAQAAAA==.Sacréd:BAAANQAECgIIAgAAAA==.Sarkan:BAAANQADCgUIBQAAAA==.Sarova:BAAANQADCgYIBgAAAA==.Satori:BAAANQADCgUICAAAAA==.',
Sc='Scalewind:BAAANQADCgYIBgAAAA==.',
Se='Seldeath:BAAANQADCgEIAQAAAA==.Selfu:BAAANQAECgQIBQAAAA==.Sellidor:BAAANQADCgcIEgAAAA==.Seriniyaa:BAAANQADCgUIDAAAAA==.',
Sh='Sheara:BAAANQAECggIBwAAAA==.Shinjiro:BAAANQAECgEIAQAAAA==.Shirito:BAAANQAECgYICgAAAA==.Shiritodh:BAAANQAECgUIBgAAAA==.Shockin:BAAANQADCggIFgAAAA==.Shortnstout:BAAANQAECgYICwAAAA==.Shugo:BAAANQADCgYIEAAAAA==.',
Si='Sienje:BAAANQAECgMIAwAAAA==.Sigma:BAAANQAECgQIBQAAAA==.Simpleson:BAAANQAECgQIBQAAAA==.Sinbàd:BAAANQAECgcIDgAAAA==.Sinistris:BAAANQADCgcIBwAAAA==.',
Sk='Skrabble:BAAANQADCgcIEQAAAA==.',
Sl='Slaete:BAAANQADCggIDgAAAA==.Slush:BAAANQAECgQIBAAAAA==.',
Sm='Smallz:BAAANQADCgUIDAABNQAECgEIAQABAAAAAA==.',
So='Solemn:BAAANQADCgcIDAABNQADCgcIEgABAAAAAA==.Solrana:BAAANQADCgcIEQAAAA==.Songmistress:BAAANQADCgYICQAAAA==.Sorren:BAAANQADCgQIBQAAAA==.Sozin:BAAANQADCgIIAgAAAA==.',
St='Stardrive:BAAANQADCgcIEAAAAA==.Stevesteve:BAAANQADCgUIBQAAAA==.',
Su='Sunasha:BAAANQADCgUIDAAAAA==.Superbautumn:BAAANQADCgQIBAAAAA==.',
Ta='Tachyon:BAAANQAECgIIAgABNQAECgcIDQABAAAAAA==.Tagnaras:BAAANQAECgEIAQAAAA==.Tali:BAAANQADCgcIEgAAAA==.Taliasluage:BAAANQADCggICAABNQAECgUIBQABAAAAAA==.Tangle:BAAANQAECgEIAQABNQAECggICAABAAAAAA==.Tanka:BAAANQAECgQIBQAAAA==.Tannisse:BAAANQADCgUICAAAAA==.Tashlaraz:BAEANQADCgUICAAAAA==.Tasi:BAAANQAECgQIBAAAAA==.Taurannosaur:BAAANQADCgMIAwAAAA==.Taurentots:BAAANQAECgMIAQAAAA==.',
Te='Telkas:BAAANQADCgUIBQAAAA==.Temporantus:BAAANQADCgQIBQAAAA==.Tenko:BAAANQAECgEIAQAAAA==.',
Th='Thaddeus:BAAANQADCggIEwAAAA==.Therm:BAABNQAECoEXAAICAAkJXyPNAwCUAwACAAkJXyPNAwCUAwAAAA==.Thoramier:BAAANQADCggIDgAAAA==.',
Ti='Tibble:BAAANQADCggIFwAAAA==.Timoonja:BAAANQADCgYICgAAAA==.',
To='Tonatuih:BAAANQAECgQIBgAAAA==.',
Tr='Trezzia:BAAANQAECgEIAQAAAA==.Triipod:BAAANQADCgYICgAAAA==.Trinkat:BAAANQADCgUICAAAAA==.Trojinn:BAAANQAECgUIBQAAAA==.Tryst:BAAANQADCgYIBgAAAA==.',
Ty='Tylean:BAAANQADCgcIEQAAAA==.',
Ud='Udukai:BAAANQAECgQIBAAAAA==.',
Uu='Uu:BAAANQADCgYIDwAAAA==.',
Va='Vadrozsa:BAAANQADCgUIDAAAAA==.Vareyn:BAAANQADCgYIBwAAAA==.',
Vo='Vorth:BAAANQAECgQIBQAAAA==.',
Vu='Vulturous:BAAANQADCgYICgAAAA==.',
Vy='Vydian:BAAANQADCgQIBAAAAA==.',
Wa='Waldir:BAAANQAECgQIBQAAAA==.Wanted:BAAANQADCgYIBgAAAA==.Watz:BAAANQADCgYIDAAAAA==.',
Wh='Wholesale:BAAANQAECgUIBQAAAA==.',
Wr='Wrack:BAAANQADCgQIBQAAAA==.Wraithian:BAAANQABCgQIBAAAAA==.Wratsoul:BAAANQAECgQIBAAAAA==.',
Xe='Xessala:BAAANQAECgQIBAAAAA==.',
Xh='Xheero:BAAANQAECgUICQAAAA==.',
Yu='Yulica:BAAANQADCgUICAAAAA==.',
Za='Zaffy:BAAANQAECgIIAgAAAA==.Zaktrix:BAAANQADCgMIBQAAAA==.Zaleron:BAAANQADCgIIAgAAAA==.Zaruba:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Zatkyng:BAAANQAECgQIBQAAAA==.',
Ze='Zekos:BAAANQADCgUIDAAAAA==.',
Zi='Zimdalar:BAAANQADCgcIEQAAAA==.',
Zu='Zulre:BAAANQAECgMIAwAAAA==.',
['Ôv']='Ôverkill:BAAANQADCggIEwAAAA==.',
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
