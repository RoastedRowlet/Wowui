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

local lookup = {'Unknown-Unknown','Priest-Holy','DemonHunter-Devourer','Evoker-Devastation','Priest-Shadow','Hunter-BeastMastery','Druid-Restoration','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','Paladin-Retribution','Paladin-Holy','Monk-Brewmaster','Rogue-Assassination','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Protection',}
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Ackrenoth:BAAANQADCggIFAAAAA==.',
Ad='Adynn:BAAANQAECgYJDwAAAA==.',
Ae='Aeru:BAAANQADCgYIBgAAAA==.Aethreal:BAAANQADCgYICwAAAA==.',
Af='Afridium:BAAANQADCgEIAQAAAA==.',
Ak='Akikusa:BAAANQADCggICgAAAA==.',
Al='Alderath:BAAANQABCgQJBQAAAA==.Alista:BAAANQAECggIEgAAAA==.Allyeska:BAAANQADCgMIAwAAAA==.Alnharaelune:BAAANQADCgUIBQAAAA==.',
Am='Amor:BAAANQAECgUJCAAAAA==.',
An='Anali:BAAANQAECgcJCgAAAA==.Anani:BAAANQADCggIFAAAAA==.Angreifer:BAAANQAECgcIEgAAAA==.Anori:BAAANQAECgQIBgAAAA==.',
Ao='Aonar:BAAANQADCgcJFAAAAA==.',
Aq='Aqua:BAAANQABCgcJDwAAAA==.',
Ar='Arc:BAAANQAECgUJBgABNQAECgYJDwABAAAAAA==.Archenteron:BAAANQADCgYIDgAAAA==.Ardorcinder:BAAANQADCgYIGAAAAA==.Argentur:BAAANQADCgEIAQAAAA==.Arkaan:BAAANQADCgUIBQABNQAECgEJAQABAAAAAA==.Arthmanafel:BAAANQAECgUJDAAAAA==.',
As='Asbjorne:BAAANQAECgEJAQAAAA==.',
Au='Autumnmoon:BAAANQAECgEJAQAAAA==.',
Av='Avalsong:BAAANQAECgcIEwAAAA==.Avelos:BAABNQAECoEZAAICAAgK5hzfKwBMAgACAAgK5hzfKwBMAgAAAA==.',
Ay='Ayowenn:BAAANQADCgIIAgAAAA==.Ayzmist:BAAANQAECgUICQAAAA==.Ayzmyth:BAAANQAECgYJDQAAAA==.',
Ba='Banthapooduu:BAAANQADCgcJDQAAAA==.',
Be='Beasic:BAAANQAECgUJDgAAAA==.Beletili:BAAANQAECgYJDgAAAA==.Beátrix:BAAANQADCgIIAgAAAA==.',
Bi='Birdman:BAAANQADCgYIBgABNQADCggIIwABAAAAAA==.',
Bl='Blatendrg:BAAANQAECgYIDwAAAA==.Blindcloud:BAAANQAECgEJAQAAAA==.',
Bo='Boot:BAAANQAECgEJAQAAAA==.Borodemonin:BAEBNQAECoEdAAIDAAgKkyS9BQBfAwADAAgKkyS9BQBfAwAAAA==.',
Br='Breae:BAAANQAECgUJCgAAAA==.Brieanna:BAAANQADCgQIBAAAAA==.Bristia:BAAANQADCggICAAAAA==.Brutyl:BAAANQAECgEIAQABNQAECgcIDQABAAAAAA==.',
Bu='Bulky:BAAANQAECgIIAgAAAA==.',
Ca='Cadforus:BAAANQADCgUJCQABNQAECgIJAgABAAAAAA==.Cafë:BAAANQADCgcICgABNQAECgkJGAAEAGgiAA==.Caicee:BAAANQADCgEIAQAAAA==.Caistin:BAAANQADCgYIBgAAAA==.Calyma:BAAANQADCgYJFgAAAA==.Camelsotters:BAAANQAECgQJBwAAAA==.Casca:BAAANQADCgcJFQAAAA==.Catsclaw:BAAANQADCgYIBgAAAA==.',
Ce='Cenjeru:BAAANQAECgUIDQAAAA==.',
Ch='Chezzie:BAAANQAECgYICwAAAA==.Chiot:BAAANQAECgQJBgAAAA==.',
Ci='Cimerian:BAAANQAECgIJAgAAAA==.',
Cl='Clone:BAAANQADCgYIBgAAAA==.',
Co='Concealer:BAAANQADCgEIAQAAAA==.Conejamala:BAAANQAECgYIBgAAAA==.Corange:BAAANQABCgIIBAAAAA==.Corlock:BAAANQADCgQIBAAAAA==.Cormech:BAAANQAECgEIAgAAAA==.Cornite:BAAANQADCgYJDgAAAA==.',
Cr='Crizzo:BAAANQAECgQICQAAAA==.',
Da='Daddyslilgrl:BAAANQAECgMIBQAAAA==.Dakra:BAEANQAECgUJCgAAAA==.Dalamar:BAAANQAECgQIBAABNQAECggJHgAFAKAZAQ==.Dalandis:BAAANQAECgUJBQAAAA==.Dalyeth:BAAANQAECgUJCQAAAA==.Darianno:BAAANQADCgMIAwAAAA==.Darkwingorc:BAABNQAECoEcAAIGAAgKRBp3LgB5AgAGAAgKRBp3LgB5AgAAAA==.Darkwulf:BAAANQADCgcJDQAAAA==.Daunt:BAAANQADCgIIAgABNQAECgUICwABAAAAAA==.Dawnfire:BAAANQADCgEIAQAAAA==.Dawnmane:BAAANQADCgEIAQAAAA==.',
De='Deadsecsi:BAAANQABCgEIAQAAAA==.Decypher:BAAANQADCgYJCwABNQAECgUIDgABAAAAAA==.Deebz:BAAANQAECgYJDwAAAA==.Deliverance:BAABNQAECoEeAAIFAAgKoBnAEgB0AgAFAAgKoBnAEgB0AgAAAA==.Demigoth:BAAANQAECgUICQAAAA==.Denethmon:BAAANQAECgEJAQAAAA==.Dentik:BAAANQAECgUICgAAAA==.Denuma:BAAANQAECgMIAwAAAA==.Devilina:BAAANQADCggJCgAAAA==.',
Dh='Dheriana:BAAANQAECgUIDgAAAA==.Dherisis:BAAANQADCgcIBwABNQAECgUIDgABAAAAAA==.Dherli:BAAANQADCggIDQABNQAECgUIDgABAAAAAA==.',
Di='Diamair:BAAANQAECgQJCQAAAA==.Divynelle:BAAANQABCgIIAgAAAA==.Dixiee:BAAANQADCgcIDwABNQADCggIDwABAAAAAA==.',
Dn='Dnegelpal:BAAANQAECgYICwAAAA==.',
Do='Dodgecharger:BAAANQADCgcIGgAAAA==.',
Dr='Dragerin:BAAANQAECgMIAwAAAA==.Dragonfood:BAAANQAECgMIBAAAAA==.Drakilu:BAAANQAECgUJDgAAAA==.Drakra:BAEANQAECgQJBAABNQAECgUJCgABAAAAAA==.Drasic:BAABNQAECoEaAAIHAAgKiRo1DgCFAgAHAAgKiRo1DgCFAgAAAA==.Dreddscott:BAAANQAECgEJAQABNQAECgUJCwABAAAAAA==.Dretro:BAAANQAECgIJBAAAAA==.Drovosi:BAAANQADCggIHAAAAA==.',
Du='Durin:BAAANQAECgUJCAAAAA==.Durward:BAAANQAECgUIBgAAAA==.Duvo:BAAANQAECgUJBgAAAA==.',
Dw='Dwarvey:BAAANQADCgUJBQAAAA==.',
['Dæ']='Dæmôna:BAAANQADCgQIBQAAAA==.',
['Dé']='Détank:BAAANQAECgcJEgAAAA==.',
Ei='Eiene:BAAANQAECgQJBAAAAA==.Eithetala:BAAANQADCgYICAAAAA==.',
El='Elemental:BAAANQAECgcJCwABNQAECggJFQAHAFkMAA==.Elloseth:BAAANQAECgMJBQAAAA==.Elmorin:BAAANQADCggIFgAAAA==.Eluneh:BAAANQADCgYICAAAAA==.',
Eo='Eolon:BAAANQADCgcIGgAAAA==.',
Ep='Epica:BAAANQAECgYJCwAAAA==.',
Er='Eragonhawk:BAAANQADCggJIQAAAA==.Eraina:BAAANQADCggJDQAAAA==.Eroldan:BAAANQADCgUIBQAAAA==.Erovianoria:BAAANQAECgYJDwAAAA==.',
Es='Essun:BAABNQAECoEeAAIIAAkK9BqQEQC6AgAIAAkK9BqQEQC6AgABNQADCgQIBAABAAAAAA==.',
Ev='Evanthe:BAAANQAECgYJCQAAAA==.',
Ex='Expire:BAAANQADCgEIAQAAAA==.',
Fa='Faizor:BAAANQADCgYIBgAAAA==.Fastal:BAAANQADCgYIEgAAAA==.Fauxborn:BAAANQAECgEJAQAAAA==.',
Fe='Fedwell:BAAANQAECgUJCQAAAA==.',
Fi='Finngan:BAAANQAECgUICwAAAA==.Fitoria:BAAANQADCggIGQABNQAECgYJDwABAAAAAA==.',
Fo='Forestkin:BAAANQADCgcJGQABNQAECgUJCQABAAAAAA==.Foxhope:BAAANQAECgEJAQAAAA==.',
Fr='Friartuk:BAAANQAECgEIAQAAAA==.Frozenthunda:BAAANQAECgYJEgAAAA==.',
Fu='Furna:BAAANQAECgMJAwAAAA==.Fuzzyhooves:BAAANQAECgUJDgAAAA==.',
Ga='Gabrael:BAABNQAECoEbAAMJAAgKPxCRBwDyAQAJAAgKPxCRBwDyAQAKAAEKNwat/gAwAAAAAA==.',
Gh='Ghorienge:BAAANQAECgIJAgAAAA==.',
Gi='Gilox:BAAANQAECgUICAAAAA==.',
Gl='Glossu:BAAANQADCgIIAgAAAA==.',
Gn='Gndmexia:BAAANQADCgMIAwAAAA==.Gneiss:BAAANQAECgMIAwAAAA==.',
Go='Goldenarrow:BAAANQABCgYIDAAAAA==.Gorgilz:BAAANQADCgMIBAAAAA==.Gothgirldemi:BAAANQAECgcJEgAAAA==.',
Gr='Graymon:BAAANQADCgcJFgAAAA==.Greebo:BAAANQADCgcJFgAAAA==.Grist:BAAANQADCgYICQAAAA==.',
Gu='Guatalupe:BAAANQADCgYIBgAAAA==.Guilherme:BAAANQADCggIEAAAAA==.',
Gw='Gwenyver:BAAANQAECgEJAQAAAA==.',
Ha='Hailthanatos:BAAANQAECggIEAAAAA==.Hamord:BAAANQAECgEJAQAAAA==.Harliquette:BAAANQAECgQJCwAAAA==.Harliqynn:BAAANQAECgQIBQAAAA==.Harlock:BAAANQAECgcIEAAAAA==.Hazelnuts:BAAANQADCgMIAwAAAA==.',
Hi='Hiten:BAAANQAECgUJBgAAAA==.',
Ho='Hoofinmouth:BAAANQAECgMIAwAAAA==.Hopedaimond:BAAANQADCgYICgAAAA==.',
Hu='Huntertattoo:BAAANQAECgEJAgAAAA==.Husgus:BAAANQADCgYIDAABNQAECgcJDwABAAAAAA==.Huungron:BAAANQADCgYIDAAAAA==.',
Ic='Icynips:BAAANQADCgQIBAAAAA==.',
Il='Illianarra:BAAANQADCggIEgAAAA==.Ilthad:BAAANQAECgQIBQAAAA==.',
Im='Imawarrionow:BAAANQADCgIIAgAAAA==.Imora:BAAANQADCgMIAwAAAA==.Imshalar:BAAANQABCgIIAgABNQAECgQIBAABAAAAAA==.',
In='Infurryating:BAAANQAECggJCAAAAA==.',
Ir='Irumble:BAAANQADCgMIAwAAAA==.',
Is='Ischadè:BAAANQADCgUIBgAAAA==.Iskuros:BAAANQADCgMIAwAAAA==.',
It='Itsirk:BAAANQAECgQIBgAAAA==.',
Iz='Izyebelle:BAAANQAECgEJAQAAAA==.',
Je='Jefeorganico:BAAANQAECgUICQAAAA==.Jeloi:BAAANQADCggJIQAAAA==.',
Ji='Jimmydin:BAABNQAECoEaAAMLAAgK+xneOwBkAgALAAgK+xneOwBkAgAMAAcKaxtxMQA4AgAAAA==.',
Ju='Juego:BAAANQADCgQIBAAAAA==.Julkan:BAAANQAECgQIBgAAAA==.Junhoong:BAAANQAECgUICAAAAA==.Juvia:BAAANQAECgUICQABNQAECgcJEwABAAAAAA==.',
Jy='Jynnysa:BAAANQADCgYJDQABNQAECgUJCQABAAAAAA==.',
Ka='Kai:BAAANQAECgEJAQAAAA==.Kairoll:BAAANQAECgcJEgAAAA==.Kaleìna:BAAANQADCgcICAAAAA==.Kallisto:BAAANQADCgcIBwAAAA==.Karaa:BAAANQADCggJDwAAAA==.Kariena:BAAANQAECgEJAQAAAA==.Kart:BAAANQADCgEIAQAAAA==.Kashaka:BAAANQADCgYJCwAAAA==.Katesluage:BAAANQAECgcJEgAAAA==.Kawrrl:BAAANQADCgMIAwAAAA==.',
Ke='Keeya:BAAANQAECgQJCQAAAA==.Kelina:BAAANQADCgIIAgAAAA==.Kendari:BAAANQAECgUICQAAAA==.Kernasas:BAAANQAECgEIAwAAAA==.',
Kh='Khiari:BAAANQADCgUIBQABNQAECgEJAQABAAAAAA==.',
Ki='Kier:BAAANQADCggICAAAAA==.Kizaraan:BAAANQADCgUIBQAAAA==.',
Kl='Kleyntamar:BAAANQADCgcJFgAAAA==.',
Kn='Knyghtly:BAAANQAECggICAAAAA==.',
Ko='Konstantien:BAAANQAECgUIBQAAAA==.Koric:BAAANQADCgcIEwAAAA==.',
Kr='Kretsch:BAAANQADCgUIBQAAAA==.Krickket:BAAANQABCgQJBAABNQADCggIDwABAAAAAA==.',
Ku='Kupau:BAAANQAECgQICAAAAA==.Kurogami:BAAANQAECgYIDwAAAA==.Kuthixo:BAAANQADCgcJFwAAAA==.',
Ky='Kylos:BAAANQABCgQIBgAAAA==.Kynnigos:BAAANQABCgIIAgAAAA==.',
La='Landstrider:BAAANQAFFAEIAQABNQAECggJFQAHAFkMAA==.Lanss:BAAANQAECgYIDwAAAA==.Larachel:BAAANQAECgQIBgAAAA==.Lastaril:BAAANQADCgYIDwAAAA==.Lastword:BAAANQAECgEJAQABNQAECgIJAwABAAAAAA==.Laur:BAAANQAECgYIEAAAAA==.',
Li='Liartes:BAAANQADCgcIFgAAAA==.Liderela:BAAANQADCgEIAQAAAA==.Lilipo:BAAANQAECgQIBQAAAA==.',
Lo='Logoth:BAAANQAECgQIBAAAAA==.Lohgarak:BAAANQADCggIFQAAAA==.',
Lu='Lunaellana:BAAANQADCgYICAAAAA==.',
Ly='Lystaan:BAAANQABCgQIBAAAAA==.',
['Lü']='Lüvpüp:BAABNQAECoEYAAIEAAkKaCLQAgBjAwAEAAkKaCLQAgBjAwAAAA==.',
Ma='Maiku:BAAANQAECgQJBgAAAA==.Makado:BAAANQAECgUICgAAAA==.Makoroth:BAAANQAECgUJCQAAAA==.Masharu:BAAANQADCgcIBwAAAA==.Matua:BAAANQAECgIIAgAAAA==.Maycee:BAAANQAECgEIAQAAAA==.',
Mc='Mcat:BAAANQAECgEJAQAAAA==.Mcgriddle:BAAANQADCgEIAQAAAA==.Mcnaugh:BAAANQADCgYIBgAAAA==.Mcsaltface:BAAANQAECgEJAQAAAA==.',
Me='Meddic:BAAANQAECgEJAQAAAA==.Menarot:BAAANQAECgYIDwAAAA==.Mendais:BAAANQADCgUIBgAAAA==.Meztlitotol:BAAANQAECgQIBAABNQAECgcIEgABAAAAAA==.',
Mi='Mirosdrigo:BAAANQADCgcIBwAAAA==.Mirosmundo:BAABNQAECoEZAAINAAgKSh1PBgCHAgANAAgKSh1PBgCHAgAAAA==.Mistfit:BAAANQAECggICAAAAA==.Miyu:BAAANQAECgYIDwAAAA==.',
Mo='Mod:BAAANQAECgcIEgAAAA==.Moggatorash:BAAANQADCgcICwAAAA==.Mogtham:BAAANQAECgUJDgAAAA==.Monlaferte:BAAANQADCgMIAwAAAA==.Montsegur:BAAANQADCggICAAAAA==.Mooforn:BAAANQADCgcJFgAAAA==.Moonfall:BAAANQAECgEJAQAAAA==.Moosader:BAAANQAECgYIDAAAAA==.Morellea:BAAANQAECgUJCgAAAA==.Morighann:BAAANQAECgcJEgAAAA==.Moñgoose:BAAANQADCgMIAwAAAA==.',
My='Mynkx:BAAANQAECgEJAQAAAA==.Mythyras:BAAANQAECgUJCQAAAA==.',
Na='Naeomy:BAABNQAECoEaAAIOAAgKxQXqKQCIAQAOAAgKxQXqKQCIAQAAAA==.Nahaman:BAAANQADCggIFwAAAA==.Napolien:BAAANQAECgcJEwAAAA==.Naugan:BAAANQADCgEIAQAAAA==.',
Ne='Nechahira:BAABNQAECoEVAAIHAAgKWQxnGwDFAQAHAAgKWQxnGwDFAQAAAA==.',
Ni='Nien:BAAANQAECgEIAQAAAA==.Nihlathak:BAAANQAECgQIBgAAAA==.Ninada:BAAANQAECgYJDwAAAA==.',
No='Noranna:BAAANQADCgcJFgAAAA==.',
Ny='Nyim:BAAANQAECgEIAQAAAA==.Nynsyn:BAAANQADCgUIBQABNQAECgUJCQABAAAAAA==.Nyxeira:BAAANQAECgQJBAAAAA==.',
['Nâ']='Nâli:BAAANQADCggIDQAAAA==.',
Ob='Obsidianclaw:BAAANQADCgIIAwAAAA==.',
Oh='Ohwellz:BAAANQAECgEJAQAAAA==.',
Op='Ophin:BAAANQAECgYIDgAAAA==.',
Pa='Panamared:BAAANQAECgUJCwAAAA==.Pappawoody:BAAANQAECgcJEgAAAA==.Parishealton:BAAANQADCgcJBwAAAA==.',
Pe='Pellegryn:BAAANQADCgYICQAAAA==.Pennyfeather:BAAANQAECgUJDgAAAA==.Pezza:BAAANQAECgIJAgAAAA==.',
Ph='Phaze:BAAANQAECgcJDgAAAA==.Phideauxe:BAAANQAECgQIBAAAAA==.Phorate:BAAANQAECgQJBwAAAA==.',
Pl='Pluralbutter:BAAANQAECgcJDwAAAA==.',
Po='Popexeo:BAAANQAECgcIDQABNQAFFAUIDAAHAIYUAA==.',
Ps='Psyvern:BAAANQAECgUJBwAAAA==.',
Qu='Quiccerstorm:BAAANQADCgQIBQAAAA==.',
Ra='Raevennlumis:BAAANQAECgUJCQAAAA==.Raevenns:BAAANQADCggJCAABNQAECgUJCQABAAAAAA==.Rahkhard:BAAANQAECgYJDwAAAA==.Rascdit:BAAANQADCgcIBgAAAA==.',
Re='Reiyoso:BAAANQADCggJDgAAAA==.Reui:BAAANQADCgEIAQAAAA==.',
Rh='Rhemibumbum:BAAANQAECgIJAQAAAA==.',
Ro='Rocketbilly:BAAANQADCgIJAgAAAA==.Roobee:BAAANQAECgEJAQAAAA==.',
Ru='Ruaic:BAAANQADCgYJCQAAAA==.',
Sa='Sableanne:BAAANQADCgEIAQAAAA==.Sacréd:BAAANQAECgUICgAAAA==.Sarkan:BAAANQADCgUICAAAAA==.Sarova:BAAANQAECgQJBAAAAA==.Satori:BAAANQADCgcJFgAAAA==.',
Sc='Scalewind:BAAANQADCgYIBgAAAA==.',
Se='Seldeath:BAAANQADCgEJAQAAAA==.Selfu:BAAANQAECgUJDgAAAA==.Sellidor:BAAANQAECgYICgAAAA==.Seriniyaa:BAAANQADCgcJGQAAAA==.',
Sh='Sheara:BAAANQAECggICAAAAA==.Shinjiro:BAAANQAECgQJBQAAAA==.Shirito:BAABNQAECoEWAAMPAAcK4R+cFAB2AgAPAAcKzB+cFAB2AgAQAAQKeRplVwAbAQAAAA==.Shiritodh:BAAANQAECgUJBgAAAA==.Shockin:BAAANQAECgQICAAAAA==.Shortnstout:BAABNQAECoEaAAMRAAkKfh8CBgADAwARAAkKfh8CBgADAwALAAEKyBv4AgFUAAAAAA==.Shugo:BAAANQAECgEJAQAAAA==.',
Si='Sienje:BAAANQAECgUICAAAAA==.Sigma:BAAANQAECgUIDAAAAA==.Simpleson:BAAANQAECgYIDwAAAA==.Sinbàd:BAABNQAECoEhAAIDAAkKtBtcDQDfAgADAAkKtBtcDQDfAgAAAA==.Sinistris:BAAANQAECgEJAQAAAA==.',
Sk='Skie:BAAANQAECgYIAwABNQAECggICAABAAAAAA==.Skrabble:BAAANQAECgEJAQAAAA==.',
Sl='Slaete:BAAANQAECgIIAgAAAA==.Slush:BAAANQAECgQIBAAAAA==.',
Sm='Smallz:BAAANQADCgcIGQABNQAECgUJBgABAAAAAA==.Småug:BAAANQADCgMJAwAAAA==.',
So='Solemn:BAAANQAECgQICAABNQAECgYICgABAAAAAA==.Solrana:BAAANQAECgEJAQAAAA==.Songmistress:BAAANQAECgQIBgAAAA==.Sorren:BAAANQADCgYJCwAAAA==.Sotta:BAAANQAECgIIAwAAAA==.Sozin:BAAANQADCgIIAgAAAA==.',
Sq='Squeezee:BAAANQADCggJCAAAAA==.',
St='Stardrive:BAAANQAECgEJAQAAAA==.Stevesteve:BAAANQAECgUJBQAAAA==.Stumpii:BAAANQADCgEIAQAAAA==.',
Su='Sunasha:BAAANQADCgYIEgAAAA==.Superbautumn:BAAANQAECgEJAQAAAA==.',
Sy='Synge:BAAANQADCggIDwAAAA==.Synnyca:BAAANQADCgcJBwABNQAECgUJCQABAAAAAA==.',
['Sé']='Sélune:BAAANQADCggICAAAAA==.',
Ta='Tachyon:BAAANQAECgQJBgABNQAECgkJGAAEAGgiAA==.Tagnaras:BAAANQAECgQIBQAAAA==.Tahlang:BAAANQABCgYJCAAAAA==.Tali:BAAANQAECgEJAQAAAA==.Taliasluage:BAAANQADCggICAABNQAECgcJEgABAAAAAA==.Tangle:BAAANQAECgYIBgABNQAECggICAABAAAAAA==.Tanka:BAAANQAECgUJDgAAAA==.Tannisse:BAAANQADCgUIDQAAAA==.Tanuki:BAAANQADCggIDwAAAA==.Tapol:BAAANQADCggIDwAAAA==.Tashlaraz:BAEANQADCgcJFQAAAA==.Tasi:BAAANQAECgQIBAAAAA==.Taurannosaur:BAAANQADCggIDAAAAA==.Taurentots:BAAANQAFFAMIAwAAAA==.',
Te='Telkas:BAAANQADCgUIBQAAAA==.Temporantus:BAAANQADCggIFAAAAA==.Tenko:BAAANQAECgQICQAAAA==.',
Th='Thaddeus:BAAANQAECgEJAQAAAA==.Therm:BAACNQAFFIELAAILAAUKohccAwC5AQALAAUKohccAwC5AQA1AAQKgSgAAgsACQpNJkQBAPIDAAsACQpNJkQBAPIDAAAA.Thoramier:BAAANQAECgEIAQAAAA==.',
Ti='Tibble:BAAANQADCggJIwAAAA==.Timoonja:BAAANQAECgEJAQAAAA==.',
To='Tonatuih:BAAANQAECgcIEgAAAA==.',
Tr='Trezzia:BAAANQAECgQJCAAAAA==.Triipod:BAAANQADCgYJCgAAAA==.Trinkat:BAAANQADCgcJFgAAAA==.Trojinn:BAAANQAECgUIBQAAAA==.Tryst:BAAANQADCgYIBgAAAA==.Tráson:BAAANQADCgUIBQAAAA==.',
Tu='Tub:BAAANQAECgQJBAAAAA==.',
Ty='Tylean:BAAANQADCgcJGQAAAA==.',
Ud='Udukai:BAAANQAECgQIBAAAAA==.',
Ul='Ultrastealth:BAAANQAECgIIAgAAAA==.',
Um='Umbrum:BAAANQADCgIIAgABNQAECgcIEgABAAAAAA==.',
Uu='Uu:BAAANQAECgMIAwAAAA==.',
Va='Vadrozsa:BAAANQADCgcJGQAAAA==.Vallarie:BAAANQADCgQJBAAAAA==.Vareyn:BAAANQADCggJFAAAAA==.',
Vo='Vorth:BAAANQAECgYJDwAAAA==.Vorükh:BAAANQAECgUJBQABNQAECgIIBAABAAAAAA==.',
Vu='Vulturous:BAAANQADCgYICgAAAA==.',
Vy='Vydian:BAAANQADCgYICQAAAA==.',
Wa='Waldir:BAAANQAECgUJDgAAAA==.Walock:BAAANQADCgMJAwAAAA==.Wanted:BAAANQADCgYIBgAAAA==.Watz:BAAANQADCgYIDAAAAA==.',
Wh='Wholesale:BAAANQAECgcJEgAAAA==.',
Wr='Wrack:BAAANQADCgUJCgAAAA==.Wraithian:BAAANQABCgQIBAAAAA==.Wratsoul:BAAANQAECgYICwAAAA==.',
Xe='Xessala:BAAANQAECgQICAAAAA==.',
Xh='Xheero:BAABNQAECoEXAAIGAAgKVRc6LwB2AgAGAAgKVRc6LwB2AgAAAA==.',
Yu='Yulica:BAAANQADCgcJEwAAAA==.',
Za='Zaffy:BAAANQAECgUJCwAAAA==.Zaktrix:BAAANQADCgYJCwAAAA==.Zaleron:BAAANQADCggJDAAAAA==.Zaruba:BAAANQAECgUJCwABNQAECgUICwABAAAAAA==.Zatkyng:BAAANQAECgUIDgAAAA==.',
Ze='Zekos:BAAANQADCgcJGQAAAA==.',
Zi='Zillver:BAAANQAECgUIBQABNQAECgcJEwABAAAAAA==.Zimdalar:BAAANQAECgEJAQAAAA==.',
Zu='Zulre:BAAANQAECgUJDQAAAA==.',
['Ôv']='Ôverkill:BAAANQAECgIJAgAAAA==.',
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
