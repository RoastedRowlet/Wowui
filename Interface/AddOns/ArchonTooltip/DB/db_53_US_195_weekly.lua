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

local lookup = {'Unknown-Unknown','DemonHunter-Havoc','Druid-Restoration','DemonHunter-Devourer','Paladin-Retribution',}
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Ackrenoth:BAAANQADCgcIDAAAAA==.',
Ad='Adynn:BAAANQAECgQICQAAAA==.',
Ae='Aeru:BAAANQADCgYIBgAAAA==.Aethreal:BAAANQADCgYIBgAAAA==.',
Af='Afridium:BAAANQADCgEIAQAAAA==.',
Ak='Akikusa:BAAANQADCggICgAAAA==.',
Al='Alderath:BAAANQABCgIIAwAAAA==.Alista:BAAANQAECgYIDAAAAA==.Allyeska:BAAANQADCgMIAwAAAA==.Alnharaelune:BAAANQADCgUIBQAAAA==.',
Am='Amor:BAAANQAECgMIAwAAAA==.',
An='Anali:BAAANQAECgMIAwAAAA==.Anani:BAAANQADCgcIDAAAAA==.Angreifer:BAAANQAECgcICwAAAA==.Anori:BAAANQAECgEIAgAAAA==.',
Ao='Aonar:BAAANQADCgcIDQAAAA==.',
Aq='Aqua:BAAANQABCgcIDQAAAA==.',
Ar='Arc:BAAANQAECgEIAQABNQAECgQICQABAAAAAA==.Archenteron:BAAANQADCgUICAAAAA==.Ardorcinder:BAAANQADCgYIEgAAAA==.Argentur:BAAANQADCgEIAQAAAA==.Arkaan:BAAANQADCgUIBQABNQADCgcIFwABAAAAAA==.Arthmanafel:BAAANQAECgUICAAAAA==.',
As='Asbjorne:BAAANQADCggIGgAAAA==.',
Au='Autumnmoon:BAAANQADCgcIFwAAAA==.',
Av='Avalsong:BAAANQAECgcIDwAAAA==.Avelos:BAAANQAECgcIEQAAAA==.',
Ay='Ayowenn:BAAANQADCgIIAgAAAA==.Ayzmist:BAAANQAECgQIBAAAAA==.Ayzmyth:BAAANQAECgQIBwAAAA==.',
Ba='Banthapooduu:BAAANQADCgcIBwAAAA==.',
Be='Beasic:BAAANQAECgQICQAAAA==.Beletili:BAAANQAECgQICAAAAA==.Beátrix:BAAANQADCgIIAgAAAA==.',
Bi='Birdman:BAAANQADCgYIBgABNQADCggIGwABAAAAAA==.',
Bl='Blatendrg:BAAANQAECgUICQAAAA==.Blindcloud:BAAANQADCgYICwAAAA==.',
Bo='Boot:BAAANQADCggIGQAAAA==.Borodemonin:BAEANQAECgcIEwAAAA==.',
Br='Breae:BAAANQAECgQIBQAAAA==.Brieanna:BAAANQADCgQIBAAAAA==.Brutyl:BAAANQADCgMIAwAAAA==.',
Bu='Bulky:BAAANQAECgIIAgAAAA==.',
Ca='Cadforus:BAAANQADCgUIBwABNQADCggIEwABAAAAAA==.Cafë:BAAANQADCgcICgABNQAECgcIEwABAAAAAA==.Caistin:BAAANQADCgYIBgAAAA==.Calyma:BAAANQADCgYIEAAAAA==.Camelsotters:BAAANQAECgIIAwAAAA==.Casca:BAAANQADCgYIDgAAAA==.Catsclaw:BAAANQADCgYIBgAAAA==.',
Ce='Cenjeru:BAAANQAECgUICAAAAA==.',
Ch='Chezzie:BAAANQAECgYICwAAAA==.Chiot:BAAANQAECgQIBgAAAA==.',
Ci='Cimerian:BAAANQADCggICAAAAA==.',
Cl='Clone:BAAANQADCgYIBgAAAA==.',
Co='Concealer:BAAANQADCgEIAQAAAA==.Conejamala:BAAANQADCgUIBQAAAA==.Corange:BAAANQABCgIIBAAAAA==.Corlock:BAAANQADCgQIBAAAAA==.Cormech:BAAANQAECgEIAgAAAA==.Cornite:BAAANQADCgYICAAAAA==.',
Cr='Crizzo:BAAANQAECgQIBQAAAA==.',
Da='Daddyslilgrl:BAAANQAECgMIBQAAAA==.Dakra:BAEANQAECgQIBQAAAA==.Dalamar:BAAANQADCggICQABNQAECgYIEQABAAAAAQ==.Dalyeth:BAAANQAECgMIBAAAAA==.Darkwingorc:BAAANQAECgcIEgAAAA==.Darkwulf:BAAANQADCgYIBgAAAA==.Daunt:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.Dawnfire:BAAANQADCgEIAQAAAA==.Dawnmane:BAAANQADCgEIAQAAAA==.',
De='Deadsecsi:BAAANQABCgEIAQAAAA==.Decypher:BAAANQADCgYICwABNQAECgQICQABAAAAAA==.Deebz:BAAANQAECgQICQAAAA==.Deliverance:BAAANQAECgYIEQAAAA==.Demigoth:BAAANQAECgQIBAAAAA==.Denethmon:BAAANQADCggIGgAAAA==.Dentik:BAAANQAECgQIBQAAAA==.Devilina:BAAANQADCggICgAAAA==.',
Dh='Dheriana:BAAANQAECgQICQAAAA==.Dherisis:BAAANQADCgcIBwABNQAECgQICQABAAAAAA==.Dherli:BAAANQADCgcIBwABNQAECgQICQABAAAAAA==.',
Di='Diamair:BAAANQAECgQIBgAAAA==.Divynelle:BAAANQABCgIIAgAAAA==.Dixiee:BAAANQADCgcIDwAAAA==.',
Dn='Dnegelpal:BAAANQAECgYICwAAAA==.',
Do='Dodgecharger:BAAANQADCgYIEgAAAA==.',
Dr='Dragerin:BAAANQAECgMIAwAAAA==.Dragonfood:BAAANQAECgMIBAAAAA==.Drakilu:BAAANQAECgQICQAAAA==.Drakra:BAEANQAECgQIBAABNQAECgQIBQABAAAAAA==.Drasic:BAAANQAECgYIEAAAAA==.Dreddscott:BAAANQADCgIIAgABNQAECgQIBwABAAAAAA==.Dretro:BAAANQAECgIIAwAAAA==.Drovosi:BAAANQADCgcIFQAAAA==.',
Du='Durin:BAAANQAECgQIBQAAAA==.Durward:BAAANQAECgEIAQAAAA==.Duvo:BAAANQAECgEIAQAAAA==.',
['Dæ']='Dæmôna:BAAANQADCgQIBQAAAA==.',
['Dé']='Détank:BAAANQAECgYICwAAAA==.',
Ei='Eiene:BAAANQADCggIDgAAAA==.Eithetala:BAAANQADCgYICAAAAA==.',
El='Elemental:BAAANQAECgcICwABNQAFFAEIAQABAAAAAA==.Elloseth:BAAANQAECgMIBAAAAA==.Elmorin:BAAANQADCgcIDgAAAA==.Eluneh:BAAANQADCgYICAAAAA==.',
Eo='Eolon:BAAANQADCgYIEgAAAA==.',
Ep='Epica:BAAANQAECgYICwAAAA==.',
Er='Eragonhawk:BAAANQADCggIGQAAAA==.Eraina:BAAANQADCgUIBQAAAA==.Eroldan:BAAANQADCgUIBQAAAA==.Erovianoria:BAAANQAECgUICQAAAA==.',
Es='Essun:BAABNQAECoEXAAICAAgJOBwBEACPAgACAAgJOBwBEACPAgABNQADCgQIBAABAAAAAA==.',
Ev='Evanthe:BAAANQAECgMIAwAAAA==.',
Ex='Expire:BAAANQADCgEIAQAAAA==.',
Fa='Fastal:BAAANQADCgYIDAAAAA==.Fauxborn:BAAANQADCggIFgAAAA==.',
Fe='Fedwell:BAAANQAECgMIBAAAAA==.',
Fi='Finngan:BAAANQAECgQIBgAAAA==.Fitoria:BAAANQADCgcIEQABNQAECgQICQABAAAAAA==.',
Fo='Forestkin:BAAANQADCgYIEgABNQAECgMIBAABAAAAAA==.Foxhope:BAAANQADCgcIGAAAAA==.',
Fr='Friartuk:BAAANQAECgEIAQAAAA==.Frozenthunda:BAAANQAECgQIDAAAAA==.',
Fu='Furna:BAAANQAECgMIAwAAAA==.Fuzzyhooves:BAAANQAECgQICQAAAA==.',
Ga='Gabrael:BAAANQAECgYIEQAAAA==.',
Gh='Ghorienge:BAAANQADCgcIHAAAAA==.',
Gi='Gilox:BAAANQAECgMIBAAAAA==.',
Gn='Gneiss:BAAANQAECgMIAwAAAA==.',
Go='Goldenarrow:BAAANQABCgYICgAAAA==.Gorgilz:BAAANQADCgMIBAAAAA==.Gothgirldemi:BAAANQAECgYICwAAAA==.',
Gr='Graymon:BAAANQADCgcIDwAAAA==.Greebo:BAAANQADCgcIDwAAAA==.Grist:BAAANQADCgMIAwAAAA==.',
Gu='Guatalupe:BAAANQADCgYIBgAAAA==.Guilherme:BAAANQADCggIEAAAAA==.',
Gw='Gwenyver:BAAANQADCggIGgAAAA==.',
Ha='Hailthanatos:BAAANQAECgQICQAAAA==.Hamord:BAAANQADCggIFQAAAA==.Harliquette:BAAANQAECgQIBwAAAA==.Harliqynn:BAAANQAECgIIAgAAAA==.Harlock:BAAANQAECgUICQAAAA==.',
Hi='Hiten:BAAANQAECgEIAQAAAA==.',
Ho='Hoofinmouth:BAAANQAECgMIAwAAAA==.Hopedaimond:BAAANQADCgYICgAAAA==.',
Hu='Huntertattoo:BAAANQAECgEIAgAAAA==.Husgus:BAAANQADCgYIDAABNQAECgcIDgABAAAAAA==.Huungron:BAAANQADCgYIDAAAAA==.',
Ic='Icynips:BAAANQADCgQIBAAAAA==.',
Il='Illianarra:BAAANQADCggIEgAAAA==.Ilthad:BAAANQAECgEIAQAAAA==.',
Im='Imawarrionow:BAAANQADCgEIAQAAAA==.Imora:BAAANQADCgMIAwAAAA==.Imshalar:BAAANQABCgIIAgABNQADCgYIEAABAAAAAA==.',
In='Infurryating:BAAANQAECggICAAAAA==.',
Is='Ischadè:BAAANQADCgUIBgAAAA==.Iskuros:BAAANQADCgMIAwAAAA==.',
It='Itsirk:BAAANQAECgMIBAAAAA==.',
Iz='Izyebelle:BAAANQAECgEIAQAAAA==.',
Je='Jefeorganico:BAAANQAECgQIBAAAAA==.Jeloi:BAAANQADCggIGQAAAA==.',
Ji='Jimmydin:BAAANQAECgYIEAAAAA==.',
Ju='Julkan:BAAANQAECgQIBgAAAA==.Junhoong:BAAANQAECgIIAwAAAA==.Juvia:BAAANQAECgUICQABNQAECgYIDAABAAAAAA==.',
Jy='Jynnysa:BAAANQADCgYIDQABNQAECgMIBAABAAAAAA==.',
Ka='Kai:BAAANQADCggIGgAAAA==.Kairoll:BAAANQAECgYICwAAAA==.Kaleìna:BAAANQADCgcICAAAAA==.Kallisto:BAAANQADCgcIBwAAAA==.Karaa:BAAANQADCggICgAAAA==.Kariena:BAAANQADCgcIFwAAAA==.Kart:BAAANQADCgEIAQAAAA==.Kashaka:BAAANQADCgUIBQAAAA==.Katesluage:BAAANQAECgYICwAAAA==.Kawrrl:BAAANQADCgMIAwAAAA==.',
Ke='Keeya:BAAANQAECgMIBQAAAA==.Kelina:BAAANQADCgIIAgAAAA==.Kendari:BAAANQAECgMIBAAAAA==.Kernasas:BAAANQAECgEIAgAAAA==.',
Kh='Khiari:BAAANQADCgUIBQABNQADCgcIEgABAAAAAA==.',
Ki='Kizaraan:BAAANQADCgUIBQAAAA==.',
Kl='Kleyntamar:BAAANQADCgcIDwAAAA==.',
Kn='Knyghtly:BAAANQAECggICAAAAA==.',
Ko='Konstantien:BAAANQAECgUIBQAAAA==.Koric:BAAANQADCgcIEwAAAA==.',
Kr='Kretsch:BAAANQADCgUIBQAAAA==.Krickket:BAAANQABCgQIBAABNQADCgcIDwABAAAAAA==.',
Ku='Kupau:BAAANQAECgQICAAAAA==.Kurogami:BAAANQAECgQICQAAAA==.Kuthixo:BAAANQADCgYIEAAAAA==.',
Ky='Kylos:BAAANQABCgQIBAAAAA==.Kynnigos:BAAANQABCgIIAgAAAA==.',
La='Landstrider:BAAANQAECgYIBgABNQAFFAEIAQABAAAAAA==.Lanss:BAAANQAECgQICQAAAA==.Larachel:BAAANQAECgIIAwAAAA==.Lastaril:BAAANQADCgYIDwAAAA==.Lastword:BAAANQADCggIEwABNQAECgEIAQABAAAAAA==.Laur:BAAANQAECgYIEAAAAA==.',
Li='Liartes:BAAANQADCgcIDwAAAA==.Liderela:BAAANQADCgEIAQAAAA==.Lilipo:BAAANQAECgEIAQAAAA==.',
Lo='Logoth:BAAANQADCgYIEAAAAA==.Lohgarak:BAAANQADCggIFQAAAA==.',
Lu='Lunaellana:BAAANQADCgYICAAAAA==.',
Ly='Lystaan:BAAANQABCgQIBAAAAA==.',
['Lü']='Lüvpüp:BAAANQAECgcIEwAAAA==.',
Ma='Maiku:BAAANQAECgQIBgAAAA==.Makado:BAAANQAECgQIBQAAAA==.Makoroth:BAAANQAECgMIBAAAAA==.Masharu:BAAANQADCgcIBwAAAA==.Maycee:BAAANQADCgcIEgAAAA==.',
Mc='Mcat:BAAANQADCggIFAAAAA==.Mcgriddle:BAAANQADCgEIAQAAAA==.Mcnaugh:BAAANQADCgYIBgAAAA==.Mcsaltface:BAAANQADCggIGAAAAA==.',
Me='Meddic:BAAANQADCgcIFQAAAA==.Menarot:BAAANQAECgUICQAAAA==.Mendais:BAAANQADCgUIBgAAAA==.Meztlitotol:BAAANQADCggIGwABNQAECgcICwABAAAAAA==.',
Mi='Mirosdrigo:BAAANQADCgcIBwAAAA==.Mirosmundo:BAAANQAECgcIEQAAAA==.Miyu:BAAANQAECgQICQAAAA==.',
Mo='Mod:BAAANQAECgYICwAAAA==.Moggatorash:BAAANQADCgYICgAAAA==.Mogtham:BAAANQAECgQICQAAAA==.Monlaferte:BAAANQADCgMIAwAAAA==.Mooforn:BAAANQADCgcIDwAAAA==.Moonfall:BAAANQADCggIGgAAAA==.Moosader:BAAANQAECgQIBgAAAA==.Morellea:BAAANQAECgUIBgAAAA==.Morighann:BAAANQAECgYICwAAAA==.Moñgoose:BAAANQADCgMIAwAAAA==.',
My='Mynkx:BAAANQADCgcIEgAAAA==.Mythyras:BAAANQAECgMIBAAAAA==.',
Na='Naeomy:BAAANQAECgYIDwAAAA==.Nahaman:BAAANQADCgcIDwAAAA==.Napolien:BAAANQAECgYIDAAAAA==.Naugan:BAAANQADCgEIAQAAAA==.',
Ne='Nechahira:BAAANQAFFAEIAQAAAA==.',
Ni='Nien:BAAANQAECgEIAQAAAA==.Nihlathak:BAAANQAECgIIAgAAAA==.Ninada:BAAANQAECgQICQAAAA==.',
No='Noranna:BAAANQADCgcIDwAAAA==.',
Ny='Nyim:BAAANQAECgEIAQAAAA==.Nynsyn:BAAANQADCgUIBQABNQAECgMIBAABAAAAAA==.Nyxeira:BAAANQAECgQIBAAAAA==.',
['Nâ']='Nâli:BAAANQADCgUIBQAAAA==.',
Ob='Obsidianclaw:BAAANQADCgIIAwAAAA==.',
Oh='Ohwellz:BAAANQAECgEIAQAAAA==.',
Op='Ophin:BAAANQAECgUICAAAAA==.',
Pa='Panamared:BAAANQAECgQIBwAAAA==.Pappawoody:BAAANQAECgYICwAAAA==.',
Pe='Pellegryn:BAAANQADCgYICQAAAA==.Pennyfeather:BAAANQAECgQICQAAAA==.Pezza:BAAANQADCggIEwAAAA==.',
Ph='Phaze:BAAANQAECgUIBwAAAA==.Phorate:BAAANQAECgMIAwAAAA==.',
Pl='Pluralbutter:BAAANQAECgYICAAAAA==.',
Po='Popexeo:BAAANQAECgcIDQABNQAFFAUIBwADAHAOAA==.',
Ps='Psyvern:BAAANQAECgEIAgAAAA==.',
Qu='Quiccerstorm:BAAANQADCgQIBQAAAA==.',
Ra='Raevennlumis:BAAANQAECgQIBAAAAA==.Rahkhard:BAAANQAECgQICQAAAA==.Rascdit:BAAANQADCgcIBgAAAA==.',
Re='Reiyoso:BAAANQADCgYIBgAAAA==.Reui:BAAANQADCgEIAQAAAA==.',
Ro='Rocketbilly:BAAANQADCgIIAgAAAA==.Roobee:BAAANQAECgEIAQAAAA==.',
Ru='Ruaic:BAAANQADCgYICQAAAA==.',
Sa='Sableanne:BAAANQADCgEIAQAAAA==.Sacréd:BAAANQAECgMIBQAAAA==.Sarkan:BAAANQADCgUICAAAAA==.Sarova:BAAANQADCgYIBgAAAA==.Satori:BAAANQADCgcIDwAAAA==.',
Sc='Scalewind:BAAANQADCgYIBgAAAA==.',
Se='Seldeath:BAAANQADCgEIAQAAAA==.Selfu:BAAANQAECgQICQAAAA==.Sellidor:BAAANQAECgQIBAAAAA==.Seriniyaa:BAAANQADCgYIEgAAAA==.',
Sh='Sheara:BAAANQAECggICAAAAA==.Shinjiro:BAAANQAECgQIBQAAAA==.Shirito:BAAANQAECgcIEAAAAA==.Shiritodh:BAAANQAECgUIBgAAAA==.Shockin:BAAANQAECgQIBAAAAA==.Shortnstout:BAAANQAFFAEIAQAAAA==.Shugo:BAAANQADCggIGAAAAA==.',
Si='Sienje:BAAANQAECgQIBQAAAA==.Sigma:BAAANQAECgQIBwAAAA==.Simpleson:BAAANQAECgQICQAAAA==.Sinbàd:BAABNQAECoEbAAIEAAgJOBoNEQCKAgAEAAgJOBoNEQCKAgAAAA==.Sinistris:BAAANQADCggIDAAAAA==.',
Sk='Skie:BAAANQAECgYIAwABNQAECggICAABAAAAAA==.Skrabble:BAAANQADCggIGQAAAA==.',
Sl='Slaete:BAAANQADCggIDgAAAA==.Slush:BAAANQAECgQIBAAAAA==.',
Sm='Smallz:BAAANQADCgYIEgABNQAECgEIAQABAAAAAA==.',
So='Solemn:BAAANQAECgQIBAABNQAECgQIBAABAAAAAA==.Solrana:BAAANQADCggIGQAAAA==.Songmistress:BAAANQAECgIIAgAAAA==.Sorren:BAAANQADCgUICgAAAA==.Sotta:BAAANQAECgIIAgAAAA==.Sozin:BAAANQADCgIIAgAAAA==.',
St='Stardrive:BAAANQADCgcIFwAAAA==.Stevesteve:BAAANQADCgUICgAAAA==.',
Su='Sunasha:BAAANQADCgYIEgAAAA==.Superbautumn:BAAANQADCgQIBAAAAA==.',
Sy='Synge:BAAANQADCgcIBwAAAA==.',
Ta='Tachyon:BAAANQAECgQIBgABNQAECgcIEwABAAAAAA==.Tagnaras:BAAANQAECgEIAQAAAA==.Tahlang:BAAANQABCgYICAAAAA==.Tali:BAAANQADCggIGgAAAA==.Taliasluage:BAAANQADCggICAABNQAECgYICwABAAAAAA==.Tangle:BAAANQAECgYIAQABNQAECggICAABAAAAAA==.Tanka:BAAANQAECgQICQAAAA==.Tannisse:BAAANQADCgUIDQAAAA==.Tanuki:BAAANQADCgcIBwAAAA==.Tapol:BAAANQADCgcIBwABNQADCgcIDwABAAAAAA==.Tashlaraz:BAEANQADCgcIDgAAAA==.Tasi:BAAANQAECgQIBAAAAA==.Taurannosaur:BAAANQADCgUIBAAAAA==.Taurentots:BAAANQAFFAMIBAAAAA==.',
Te='Telkas:BAAANQADCgUIBQAAAA==.Temporantus:BAAANQADCgcIDAAAAA==.Tenko:BAAANQAECgQIBQAAAA==.',
Th='Thaddeus:BAAANQAECgEIAQAAAA==.Therm:BAACNQAFFIEIAAIFAAUJehaUAQC6AQAFAAUJehaUAQC6AQA1AAQKgSAAAgUACQnvJDoDAMUDAAUACQnvJDoDAMUDAAAA.Thoramier:BAAANQADCggIFQAAAA==.',
Ti='Tibble:BAAANQADCggIGwAAAA==.Timoonja:BAAANQADCggIEgAAAA==.',
To='Tonatuih:BAAANQAECgUICwAAAA==.',
Tr='Trezzia:BAAANQAECgQIBAAAAA==.Triipod:BAAANQADCgYICgAAAA==.Trinkat:BAAANQADCgcIDwAAAA==.Trojinn:BAAANQAECgUIBQAAAA==.Tryst:BAAANQADCgYIBgAAAA==.Tráson:BAAANQADCgUIBQAAAA==.',
Tu='Tub:BAAANQADCgUIBQAAAA==.',
Ty='Tylean:BAAANQADCgcIGAAAAA==.',
Ud='Udukai:BAAANQAECgQIBAAAAA==.',
Ul='Ultrastealth:BAAANQADCgQIBAAAAA==.',
Um='Umbrum:BAAANQADCgIIAgABNQAECgcICwABAAAAAA==.',
Uu='Uu:BAAANQAECgIIAgAAAA==.',
Va='Vadrozsa:BAAANQADCgYIEgAAAA==.Vareyn:BAAANQADCggIDAAAAA==.',
Vo='Vorth:BAAANQAECgQICQAAAA==.Vorükh:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Vu='Vulturous:BAAANQADCgYICgAAAA==.',
Vy='Vydian:BAAANQADCgYICQAAAA==.',
Wa='Waldir:BAAANQAECgQICQAAAA==.Walock:BAAANQADCgMIAwAAAA==.Wanted:BAAANQADCgYIBgAAAA==.Watz:BAAANQADCgYIDAAAAA==.',
Wh='Wholesale:BAAANQAECgYICwAAAA==.',
Wr='Wrack:BAAANQADCgUICgAAAA==.Wraithian:BAAANQABCgQIBAAAAA==.Wratsoul:BAAANQAECgQIBwAAAA==.',
Xe='Xessala:BAAANQAECgQICAAAAA==.',
Xh='Xheero:BAAANQAECgYIDwAAAA==.',
Yu='Yulica:BAAANQADCgcIDwAAAA==.',
Za='Zaffy:BAAANQAECgQIBgAAAA==.Zaktrix:BAAANQADCgYICwAAAA==.Zaleron:BAAANQADCgQIBAAAAA==.Zaruba:BAAANQAECgQIBgABNQAECgQIBgABAAAAAA==.Zatkyng:BAAANQAECgQICQAAAA==.',
Ze='Zekos:BAAANQADCgYIEgAAAA==.',
Zi='Zimdalar:BAAANQADCggIGQAAAA==.',
Zu='Zulre:BAAANQAECgUICAAAAA==.',
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
