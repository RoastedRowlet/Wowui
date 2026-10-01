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

local lookup = {'Druid-Balance','Warrior-Arms','Warrior-Protection','Monk-Brewmaster','Unknown-Unknown','DemonHunter-Devourer','Priest-Holy','Evoker-Augmentation','Evoker-Devastation','Priest-Shadow','Hunter-BeastMastery','Rogue-Subtlety','Druid-Restoration','Druid-Feral','DeathKnight-Frost','DemonHunter-Havoc','Mage-Arcane','Paladin-Holy','Warrior-Fury','Rogue-Assassination','Paladin-Retribution','Paladin-Protection','Mage-Frost','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Druid-Guardian','Hunter-Survival','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood',}
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Ackrenoth:BAAANQADCggIHAAAAA==.',
Ad='Adynn:BAABNQAECoEYAAIBAAgKSyOlDwArAwABAAgKSyOlDwArAwAAAA==.',
Ae='Aeru:BAAANQADCgYIBgAAAA==.Aethreal:BAAANQADCgYICwAAAA==.',
Af='Afridium:BAAANQADCgEIAQAAAA==.',
Ak='Akikusa:BAAANQADCggICgAAAA==.',
Al='Alderath:BAAANQABCgQJBQAAAA==.Alista:BAABNQAECoEdAAICAAkKlSGMEgBbAwACAAkKlSGMEgBbAwAAAA==.Allyeska:BAAANQADCgMIAwAAAA==.Alnharaelune:BAAANQADCgUICgAAAA==.',
Am='Amor:BAAANQAECgUICQAAAA==.',
An='Anali:BAAANQAECgcICwAAAA==.Anani:BAAANQADCggIHAAAAA==.Angreifer:BAABNQAECoEcAAMDAAgKdRcVDAAhAgADAAgKdRcVDAAhAgACAAIKsASKBQFdAAAAAA==.Anori:BAAANQAECgQICgAAAA==.',
Ao='Aonar:BAAANQAECgEIAQAAAA==.',
Aq='Aqua:BAAANQABCgcIEQAAAA==.',
Ar='Arc:BAAANQAECgUICwABNQAECggIGwAEAI8gAA==.Archenteron:BAAANQADCgYIDgAAAA==.Archnunin:BAAANQAECggICAAAAA==.Ardorcinder:BAAANQADCgcIHwAAAA==.Argentur:BAAANQADCgEIAQAAAA==.Arkaan:BAAANQADCgUIBQABNQAECgIIAwAFAAAAAA==.Arthmanafel:BAAANQAECgcIDgAAAA==.',
As='Asbjorne:BAAANQAECgMIBAAAAA==.',
Au='Autumnmoon:BAAANQAECgIIAwAAAA==.',
Av='Avalsong:BAABNQAECoEdAAIGAAgKNhrPGQBWAgAGAAgKNhrPGQBWAgAAAA==.Avelos:BAABNQAECoEgAAIHAAgKAB+7JQCZAgAHAAgKAB+7JQCZAgAAAA==.',
Ay='Ayowenn:BAAANQADCgIIAgAAAA==.Ayzmist:BAAANQAECgUICgAAAA==.Ayzmyth:BAAANQAECgYIEQAAAA==.',
Ba='Banthapooduu:BAAANQADCgcIEwAAAA==.',
Be='Beasic:BAAANQAECgUIEwAAAA==.Beletili:BAABNQAECoEZAAIHAAcK3Av3agBzAQAHAAcK3Av3agBzAQAAAA==.Beátrix:BAAANQADCgIIAgAAAA==.',
Bi='Birdman:BAAANQADCgYIBgABNQADCggIIwAFAAAAAA==.',
Bl='Blatendrg:BAABNQAECoEbAAIIAAgKcw8fCAC6AQAIAAgKcw8fCAC6AQAAAA==.Blindcloud:BAAANQAECgIIAgAAAA==.',
Bo='Boot:BAAANQAECgMIAwAAAA==.Borodemonin:BAEBNQAECoEiAAIGAAkK0iR0AQDLAwAGAAkK0iR0AQDLAwAAAA==.',
Br='Breae:BAAANQAECgYIEAAAAA==.Brieanna:BAAANQADCgUIBgAAAA==.Bristia:BAAANQAECgIIAgAAAA==.Brueggar:BAAANQAECgEIAQAAAA==.Brutyl:BAAANQAECgEIAQAAAA==.',
Bu='Bulky:BAAANQAECgIIAgAAAA==.',
Ca='Cadforus:BAAANQADCgYICgABNQAECgMIBQAFAAAAAA==.Cafë:BAAANQADCgcICgABNQAECgkJGwAJAGgiAA==.Caicee:BAAANQADCgIIAgAAAA==.Caistin:BAAANQADCgYIDgAAAA==.Calyma:BAAANQADCgcIHQAAAA==.Camelsotters:BAAANQAECgQICwAAAA==.Casca:BAAANQADCgcIHAAAAA==.Catsclaw:BAAANQADCgYIBgAAAA==.',
Ce='Cenjeru:BAAANQAECgUIEgAAAA==.',
Ch='Chezzie:BAAANQAECgYICwAAAA==.Chiot:BAAANQAECgYIDAAAAA==.',
Ci='Cimerian:BAAANQAECgIIBAAAAA==.',
Cl='Clone:BAAANQADCgYIBgAAAA==.',
Co='Concealer:BAAANQADCgEIAQAAAA==.Conejamala:BAAANQAECggIDgAAAA==.Corange:BAAANQABCgIIBAAAAA==.Cordini:BAAANQADCgcIBwAAAA==.Corlock:BAAANQADCgQIBAAAAA==.Cormech:BAAANQAECgQIBgAAAA==.Cornite:BAAANQADCgYJDgAAAA==.',
Cr='Crizzo:BAAANQAECgYIDwAAAA==.',
Da='Daddyslilgrl:BAAANQAECgMIBQAAAA==.Dakra:BAEANQAECgUIDgABNQAECgYIBgAFAAAAAA==.Dalamar:BAAANQAECgQICwABNQAECgkJJwAKAPEcAQ==.Dalandis:BAAANQAECgYICgAAAA==.Dalyeth:BAAANQAECgUIDgAAAA==.Darianno:BAAANQADCgMIAwAAAA==.Darkwingorc:BAABNQAECoEkAAILAAgK8xxXLACqAgALAAgK8xxXLACqAgAAAA==.Darkwulf:BAAANQADCgcJDQAAAA==.Daunt:BAAANQADCgIIAgABNQAECgYIEQAFAAAAAA==.Dawnfire:BAAANQADCgEIAQAAAA==.Dawnmane:BAAANQADCgEIAQAAAA==.',
De='Deadsecsi:BAAANQABCgEIAQAAAA==.Decypher:BAAANQAECgIIAgABNQAECgcIGAAMAJcRAA==.Deebz:BAABNQAECoEaAAINAAcKTRNnIwCoAQANAAcKTRNnIwCoAQAAAA==.Deliverance:BAABNQAECoEnAAIKAAkK8RzBDADxAgAKAAkK8RzBDADxAgAAAA==.Demigoth:BAAANQAECgYIDwAAAA==.Denethmon:BAAANQAECgEJAQABNQAECgMIAwAFAAAAAA==.Dentik:BAABNQAECoEYAAMNAAYK0g4hMAAxAQANAAYK0g4hMAAxAQAOAAUKjggHGgDvAAAAAA==.Denuma:BAAANQAECgMIAwAAAA==.Devilina:BAAANQADCggICgAAAA==.',
Dh='Dheriana:BAABNQAECoEYAAIMAAcKlxH6GgDZAQAMAAcKlxH6GgDZAQAAAA==.Dherisis:BAAANQADCgcIBwABNQAECgcIGAAMAJcRAA==.Dherli:BAAANQADCggIDQABNQAECgcIGAAMAJcRAA==.',
Di='Diamair:BAAANQAECgYIDwAAAA==.Divynelle:BAAANQABCgIIAgAAAA==.Dixiee:BAAANQAECgQIBAAAAA==.',
Dn='Dnegelpal:BAAANQAECgcIEgAAAA==.',
Do='Dodgecharger:BAAANQADCgcIIgAAAA==.',
Dr='Dragerin:BAAANQAECgMIAwAAAA==.Dragonfood:BAAANQAECgMIBAAAAA==.Drakilu:BAABNQAECoEYAAILAAcKgRTnaADqAQALAAcKgRTnaADqAQAAAA==.Drakra:BAEANQAECgYIBgAAAA==.Drasic:BAABNQAECoEiAAINAAkKphyjCQD6AgANAAkKphyjCQD6AgAAAA==.Dreddscott:BAAANQAECgEIAQABNQAECgYIEQAFAAAAAA==.Dretro:BAAANQAECgIIBQAAAA==.Drovosi:BAAANQADCggIIgAAAA==.',
Du='Durin:BAAANQAECgYIDgAAAA==.Durward:BAAANQAECgUIBwAAAA==.Duvo:BAAANQAECgUICwAAAA==.',
Dw='Dwarvey:BAAANQADCgUIBQAAAA==.',
['Dæ']='Dæmôna:BAAANQADCgQIBQAAAA==.',
['Dé']='Détank:BAABNQAECoEZAAIPAAcKxBjOJQAKAgAPAAcKxBjOJQAKAgAAAA==.',
Ea='Easyname:BAAANQAECgQIBAAAAA==.',
Ei='Eiene:BAAANQAECgUICQAAAA==.Eithetala:BAAANQADCgYICAAAAA==.',
El='Elemental:BAAANQAECggIDQABNQAFFAMIBgANAEAOAA==.Elloseth:BAAANQAECgMJBQAAAA==.Elmorin:BAAANQADCggIFgAAAA==.Eluneh:BAAANQADCgYICAAAAA==.',
Eo='Eolon:BAAANQADCgcIIgAAAA==.',
Ep='Epica:BAAANQAECggIEQAAAA==.',
Er='Eragonhawk:BAAANQADCggIKQAAAA==.Eraina:BAAANQADCggJDQAAAA==.Eroldan:BAAANQADCgYICQAAAA==.Erovianoria:BAAANQAECgYIDwAAAA==.',
Es='Essun:BAABNQAECoEeAAIQAAkK9BrbGACQAgAQAAkK9BrbGACQAgABNQAFFAIIAgAFAAAAAA==.',
Ev='Evanthe:BAAANQAECgYIDwAAAA==.',
Ex='Expire:BAAANQADCgEIAQAAAA==.',
Fa='Faizor:BAAANQADCggICQAAAA==.Fastal:BAAANQADCgcIFQAAAA==.Fauxborn:BAAANQAECgMIAwAAAA==.Fauxstorm:BAAANQADCgQIBQAAAA==.',
Fe='Fedwell:BAAANQAECgUIDQAAAA==.',
Fi='Finluc:BAAANQADCgUIBQAAAA==.Finngan:BAAANQAECgUICwAAAA==.Fitoria:BAAANQAECgIIAgABNQAECggIGwAEAI8gAA==.',
Fo='Forestkin:BAAANQADCgcIIAABNQAECgUIDgAFAAAAAA==.Foxhope:BAAANQAECgMIBAAAAA==.',
Fr='Friartuk:BAAANQAECgEIAQAAAA==.Frozenthunda:BAABNQAECoEcAAIRAAcKFQpf1ACMAQARAAcKFQpf1ACMAQAAAA==.',
Fu='Furna:BAAANQAECgUICAAAAA==.Fuzzyhooves:BAABNQAECoEYAAISAAcKXR64LQB2AgASAAcKXR64LQB2AgAAAA==.',
Ga='Gabrael:BAABNQAECoEjAAMTAAgKwxDWCQDmAQATAAgKwxDWCQDmAQACAAcKKwukmQB8AQAAAA==.',
Gh='Ghorienge:BAAANQAECgIIAgAAAA==.',
Gi='Gilox:BAAANQAECgUICgAAAA==.',
Gl='Glossu:BAAANQADCgIIAgAAAA==.',
Gn='Gndmexia:BAAANQADCgMIAwAAAA==.Gneiss:BAAANQAECgMIAwAAAA==.',
Go='Goldenarrow:BAAANQABCgYIDgAAAA==.Gorgilz:BAAANQADCgMIBAAAAA==.Gothgirldemi:BAABNQAECoEaAAINAAgKwR3FEACRAgANAAgKwR3FEACRAgAAAA==.',
Gr='Graymon:BAAANQAECgEIAQAAAA==.Greebo:BAAANQAECgEIAQAAAA==.Grist:BAAANQADCgYIDwAAAA==.',
Gu='Guatalupe:BAAANQADCgYIBgAAAA==.Guilherme:BAAANQADCggIEAAAAA==.',
Gw='Gwenyver:BAAANQAECgEIAQAAAA==.',
Ha='Hailthanatos:BAAANQAECggIEgAAAA==.Hamord:BAAANQAECgMIBAAAAA==.Hansdelbruk:BAAANQADCgUIBQAAAA==.Harliquette:BAAANQAECgYIEQAAAA==.Harliqynn:BAAANQAECgQIBQAAAA==.Harlock:BAABNQAECoEYAAMUAAkKNxDeKgDQAQAUAAcKIxHeKgDQAQAMAAcKhw/nHADGAQAAAA==.Hazelnuts:BAAANQADCgUIBQAAAA==.',
Hi='Hiten:BAAANQAECgUICwAAAA==.',
Ho='Hoofinmouth:BAAANQAECgMIAwAAAA==.Hoosh:BAAANQADCgUIBQAAAA==.Hopedaimond:BAAANQAECgUIBQAAAA==.',
Hu='Huntertattoo:BAAANQAECgYICAAAAA==.Husgus:BAAANQADCgYIDAABNQAECgcIDwAFAAAAAA==.Huungron:BAAANQADCgYIDAAAAA==.',
Ic='Icynips:BAAANQADCgQIBAAAAA==.',
Il='Illianarra:BAAANQAECgIIAgAAAA==.Ilthad:BAAANQAECgQICQAAAA==.',
Im='Imawarrionow:BAAANQADCgIIAgAAAA==.Imora:BAAANQADCgMIAwAAAA==.Imshalar:BAAANQABCgIIAgABNQAECgQIBAAFAAAAAA==.',
In='Infurryating:BAAANQAECggJCAAAAA==.',
Ir='Irumble:BAAANQADCggICQAAAA==.',
Is='Ischadè:BAAANQADCgUIBgAAAA==.Iskuros:BAAANQADCgMIAwAAAA==.',
It='Itsirk:BAAANQAECgUICAAAAA==.',
Iz='Izyebelle:BAAANQAECgUIBgAAAA==.',
Ja='Janar:BAAANQADCgYIBwAAAA==.',
Je='Jefeorganico:BAAANQAECgUIEQAAAA==.Jeloi:BAAANQADCggIKQAAAA==.Jenkshi:BAAANQADCgcIBwAAAA==.',
Ji='Jimmydin:BAABNQAECoEiAAMVAAgKsxrtSwBiAgAVAAgKsxrtSwBiAgASAAcKaxttPQAvAgAAAA==.',
Ju='Juego:BAAANQADCgQIBAAAAA==.Julkan:BAAANQAECgQIBgAAAA==.Junhoong:BAAANQAECggIEAAAAA==.Juvia:BAAANQAECgYIDwABNQAECggIHAAWAIkQAA==.',
Jy='Jynnysa:BAAANQADCgYJDQABNQAECgUIDgAFAAAAAA==.',
Ka='Kai:BAAANQAECgMIBAAAAA==.Kairoll:BAABNQAECoEcAAIHAAgKGQzKWwCtAQAHAAgKGQzKWwCtAQAAAA==.Kaleìna:BAAANQADCgcICAAAAA==.Kallisto:BAAANQADCgcIBwAAAA==.Karaa:BAAANQAECgIIAgAAAA==.Kariena:BAAANQAECgIIAwAAAA==.Kart:BAAANQADCgEIAQAAAA==.Kashaka:BAAANQADCgYJCwAAAA==.Katesluage:BAABNQAECoEfAAMXAAgKoBqjBACZAgAXAAgKoBqjBACZAgARAAUKuQleGwEOAQAAAA==.Kawrrl:BAAANQADCgMIAwAAAA==.',
Ke='Keeya:BAAANQAECgUIDgAAAA==.Kelina:BAAANQADCgIIAgAAAA==.Kendari:BAAANQAECgUICwAAAA==.Kernasas:BAAANQAECgMIBgAAAA==.',
Kh='Khiari:BAAANQADCgUIBQABNQAECgIIAwAFAAAAAA==.',
Ki='Kier:BAAANQADCggICAAAAA==.Kizaraan:BAAANQADCgUIBQAAAA==.',
Kl='Kleyntamar:BAAANQAECgEIAQAAAA==.',
Kn='Knyghtly:BAAANQAECggICAAAAA==.',
Ko='Konstantien:BAAANQAECgUIBQAAAA==.Koric:BAAANQAECgIIAgAAAA==.',
Kr='Kretsch:BAAANQADCgUIBQAAAA==.Krickket:BAAANQADCgMIAwABNQAECgQIBAAFAAAAAA==.',
Ku='Kupau:BAAANQAECgQICAAAAA==.Kurogami:BAABNQAECoEYAAMYAAcKMBE0SQCLAQAYAAcKMBE0SQCLAQAPAAEKmwlnhgAvAAAAAA==.Kuthixo:BAAANQADCgcIHAAAAA==.',
Ky='Kylos:BAAANQABCgQIBgAAAA==.Kynnigos:BAAANQABCgIIAgAAAA==.',
La='Landstrider:BAAANQAFFAEIAQABNQAFFAMIBgANAEAOAA==.Lanss:BAABNQAECoEYAAMCAAgKExtcUwBOAgACAAgKxBdcUwBOAgADAAIKOBn/KACIAAAAAA==.Larachel:BAAANQAECgQICgAAAA==.Lastaril:BAAANQADCgYIDwAAAA==.Lastword:BAAANQAECgEJAQABNQAECgIJAwAFAAAAAA==.Laur:BAABNQAECoEaAAIKAAgKdQ3OIgDOAQAKAAgKdQ3OIgDOAQAAAA==.',
Le='Leipäjuusto:BAAANQAECgQIBAAAAA==.',
Li='Liartes:BAAANQAECgEIAQAAAA==.Liderela:BAAANQADCgEIAQAAAA==.Lilipo:BAAANQAECgQICAAAAA==.',
Lo='Logoth:BAAANQAECgQIBAAAAA==.Lohgarak:BAAANQADCggIFQAAAA==.',
Lu='Lunaellana:BAAANQADCgYICAAAAA==.',
Ly='Lystaan:BAAANQABCgQIBAAAAA==.',
['Lü']='Lüvpüp:BAABNQAECoEbAAIJAAkKaCIkBAA+AwAJAAkKaCIkBAA+AwAAAA==.',
Ma='Maiku:BAAANQAECgYIDAAAAA==.Makado:BAAANQAECgYIEAAAAA==.Maklur:BAAANQADCgIIAQAAAA==.Makoroth:BAAANQAECgUIDAAAAA==.Malanda:BAAANQADCgQIBAAAAA==.Malygosson:BAAANQAECgUIBQAAAA==.Masharu:BAAANQADCgcIBwAAAA==.Matua:BAAANQAECgIIAgAAAA==.Maycee:BAAANQAECgQIBgAAAA==.',
Mc='Mcat:BAAANQAECgMIBAAAAA==.Mcgriddle:BAAANQADCgEIAQAAAA==.Mcnaugh:BAAANQAECgMIAwAAAA==.Mcsaltface:BAAANQAECgMIBAAAAA==.',
Me='Meddic:BAAANQAECgIIAwAAAA==.Menarot:BAAANQAECgYIDwAAAA==.Mendais:BAAANQADCgUICwAAAA==.Meztlitotol:BAAANQAECgYIBgABNQAECggIHAADAHUXAA==.',
Mi='Mirosdrigo:BAAANQADCgcIBwAAAA==.Mirosmundo:BAABNQAECoEgAAIEAAgK3B03BwCMAgAEAAgK3B03BwCMAgAAAA==.Mistfit:BAAANQAECggICAAAAA==.Miyu:BAABNQAECoEZAAMKAAcKjgvYKwB1AQAKAAcKjgvYKwB1AQAHAAcKjwRIhAAZAQAAAA==.',
Mo='Mod:BAABNQAECoEbAAMZAAgK7Rf3PAAiAgAZAAgK7Rf3PAAiAgAaAAEKEQtnBQEuAAAAAA==.Moeng:BAAANQADCgIIAgAAAA==.Moggatorash:BAAANQADCgcICwAAAA==.Mogtham:BAABNQAECoEYAAIbAAcKLBD+FgB0AQAbAAcKLBD+FgB0AQAAAA==.Monlaferte:BAAANQADCgMIAwAAAA==.Montsegur:BAAANQADCggICAAAAA==.Mooforn:BAAANQAECgEIAQAAAA==.Moonfall:BAAANQAECgMIAwAAAA==.Moosader:BAAANQAECgYIEgAAAA==.Morellea:BAAANQAECgUJCgAAAA==.Morighann:BAABNQAECoEZAAILAAcKFB42PABvAgALAAcKFB42PABvAgAAAA==.Moñgoose:BAAANQADCgMIAwAAAA==.',
My='Mynkx:BAAANQAECgIIAwAAAA==.Mythyras:BAAANQAECgUIDgAAAA==.',
Na='Naeomy:BAABNQAECoEiAAIUAAgKAAeHMgCZAQAUAAgKAAeHMgCZAQAAAA==.Nahaman:BAAANQAECgMIAwAAAA==.Napolien:BAABNQAECoEcAAMWAAgKiRCLJgBOAQAWAAcKXw6LJgBOAQASAAIKdhFV1QBvAAAAAA==.Naugan:BAAANQADCgEIAQAAAA==.',
Ne='Nechahira:BAACNQAFFIEGAAINAAMKQA4QCADoAAANAAMKQA4QCADoAAA1AAQKgRcAAg0ACApiDdshALsBAA0ACApiDdshALsBAAAA.',
Ni='Nien:BAAANQAECgEIAQAAAA==.Nihlathak:BAAANQAECgYIDAAAAA==.Ninada:BAABNQAECoEaAAMRAAcKAA2dzwCVAQARAAcK2wudzwCVAQAXAAIKcggYMQBJAAAAAA==.',
No='Noranna:BAAANQAECgEIAQAAAA==.',
Ny='Nyim:BAAANQAECgEIAQAAAA==.Nynsyn:BAAANQADCgcIDAABNQAECgUIDgAFAAAAAA==.Nyxeira:BAAANQAECgQICAAAAA==.',
['Nâ']='Nâli:BAAANQADCggIDQAAAA==.',
Ob='Obsidianclaw:BAAANQADCgIIAwAAAA==.',
Oh='Ohwellz:BAAANQAECgEJAQAAAA==.',
Op='Ophin:BAABNQAECoEZAAIYAAgKUhYYMgAHAgAYAAgKUhYYMgAHAgAAAA==.',
Pa='Panamared:BAAANQAECgYIEQAAAA==.Pappawoody:BAABNQAECoEcAAICAAgK1BsZSAB1AgACAAgK1BsZSAB1AgAAAA==.Parishealton:BAAANQADCgcJBwAAAA==.',
Pe='Pellegryn:BAAANQADCgYICQAAAA==.Pennyfeather:BAAANQAECgUIEgAAAA==.Pezza:BAAANQAECgMIBQAAAA==.',
Ph='Phaze:BAABNQAECoEVAAIcAAcKdCLRAgDFAgAcAAcKdCLRAgDFAgAAAA==.Phideauxe:BAAANQAECgQIBAAAAA==.Phorate:BAAANQAECgQJBwAAAA==.',
Pl='Pluralbutter:BAAANQAECgcJDwAAAA==.',
Po='Popexeo:BAAANQAECgcIDQABNQAFFAUIDAANAIYUAA==.',
Ps='Psyvern:BAAANQAECgYIDQAAAA==.',
Qu='Quiccerstorm:BAAANQADCgQIBQAAAA==.',
Ra='Raevennlumis:BAAANQAECgUJCQAAAA==.Raevenns:BAAANQADCggJCAABNQAECgUJCQAFAAAAAA==.Rahkhard:BAABNQAECoEbAAMEAAgKjyDFBADrAgAEAAgKjyDFBADrAgAdAAUKDhUNMQAfAQAAAA==.Rascdit:BAAANQAECgUIBQAAAA==.',
Re='Recreant:BAAANQAECgUIBQAAAA==.Reiyoso:BAAANQADCggJDgAAAA==.Reui:BAAANQADCgEIAQAAAA==.',
Rh='Rhemibumbum:BAAANQAECgUIBgAAAA==.',
Ro='Rocketbilly:BAAANQADCgIIAgAAAA==.Roobee:BAAANQAECgQIBQAAAA==.',
Ru='Ruaic:BAAANQADCgcICgAAAA==.',
Sa='Sableanne:BAAANQADCgEIAQAAAA==.Sacréd:BAAANQAECgUIDwAAAA==.Sarkan:BAAANQADCgYICQAAAA==.Sarova:BAAANQAECgQJBAAAAA==.Satori:BAAANQAECgEIAQAAAA==.',
Sc='Scalewind:BAAANQADCgYIBgAAAA==.',
Se='Seldeath:BAAANQADCgEJAQAAAA==.Selfu:BAABNQAECoEYAAIdAAcKWBZEIADQAQAdAAcKWBZEIADQAQAAAA==.Sellidor:BAAANQAECgYIEAAAAA==.Seriniyaa:BAAANQADCggIIQAAAA==.',
Sh='Sheara:BAAANQAECggICAAAAA==.Shinjiro:BAAANQAECgUICgAAAA==.Shirito:BAABNQAECoEdAAMPAAcKXiTjDwDYAgAPAAcKXiTjDwDYAgAYAAQKeRptbAD1AAAAAA==.Shiritodh:BAAANQAECgYIDAAAAA==.Shockin:BAAANQAECgUICQAAAA==.Shortnstout:BAABNQAECoEdAAMWAAkKwiAuCADnAgAWAAkKwiAuCADnAgAVAAEKyBvgMQFPAAAAAA==.Shugo:BAAANQAECgMIBAAAAA==.',
Si='Sienje:BAAANQAECgYIDgAAAA==.Sigma:BAAANQAECgcIEwAAAA==.Simpleson:BAABNQAECoEZAAMeAAcKuhqYXgDtAQAeAAYKexuYXgDtAQAfAAEKNhbNZQBAAAAAAA==.Sinbàd:BAABNQAECoEkAAIGAAkKtBs1EQC+AgAGAAkKtBs1EQC+AgAAAA==.Sinistris:BAAANQAECgEIAQAAAA==.',
Sk='Skie:BAAANQAECgYIBQABNQAECggICAAFAAAAAA==.Skrabble:BAAANQAECgMIAwAAAA==.',
Sl='Slaete:BAAANQAECgUIBwAAAA==.Slush:BAAANQAECgQIBAAAAA==.',
Sm='Smallz:BAAANQADCgcIIAABNQAECgUICwAFAAAAAA==.Småug:BAAANQADCgMJAwAAAA==.',
So='Solemn:BAAANQAECgUIDQABNQAECgYIEAAFAAAAAA==.Solrana:BAAANQAECgEJAQAAAA==.Songmistress:BAAANQAECgQIBgAAAA==.Sorren:BAAANQADCggIEwAAAA==.Sotta:BAAANQAECgIIAwAAAA==.Sozin:BAAANQADCgIIAgAAAA==.',
Sp='Spritmoon:BAAANQADCgYIBgAAAA==.',
Sq='Squeezee:BAAANQADCggICAAAAA==.',
St='Stardrive:BAAANQAECgIIAwAAAA==.Stevesteve:BAAANQAECgYICwAAAA==.Stumpii:BAAANQADCgIIAgAAAA==.',
Su='Sunasha:BAAANQADCgYIEgAAAA==.Superbautumn:BAAANQAECgIIAwAAAA==.',
Sy='Synge:BAAANQAECgIIAgAAAA==.Synnyca:BAAANQADCgcJBwABNQAECgUIDgAFAAAAAA==.',
['Sé']='Sélune:BAAANQAECgYICAAAAA==.',
Ta='Tachyon:BAAANQAECgQJBgABNQAECgkJGwAJAGgiAA==.Tagnaras:BAAANQAECgQICQAAAA==.Tahlang:BAAANQABCgYJCAAAAA==.Tali:BAAANQAECgMIBAAAAA==.Taliasluage:BAAANQADCggICAABNQAECggIHwAXAKAaAA==.Tangle:BAAANQAECgYICwABNQAECggICAAFAAAAAA==.Tanka:BAAANQAECgYIEAAAAA==.Tannisse:BAAANQADCgYIDgAAAA==.Tanuki:BAAANQADCggIFwAAAA==.Tapol:BAAANQAECgMIAwABNQAECgQIBAAFAAAAAA==.Tashlaraz:BAEANQAECgEIAQAAAA==.Tasi:BAAANQAECgQIBAAAAA==.Taurannosaur:BAAANQADCggIDAAAAA==.Taurentots:BAAANQAFFAMIAwAAAA==.',
Te='Telkas:BAAANQADCgUIBQAAAA==.Temporantus:BAAANQADCggIHAAAAA==.Tenko:BAAANQAECgUIDgAAAA==.',
Th='Thaddeus:BAAANQAECgQIBQAAAA==.Therm:BAACNQAFFIEPAAIVAAUKLh6VBADHAQAVAAUKLh6VBADHAQA1AAQKgS8AAhUACQqJJq0BAO8DABUACQqJJq0BAO8DAAAA.Thoramier:BAAANQAECgUIBgAAAA==.',
Ti='Tibble:BAAANQAECgEIAQAAAA==.Timoonja:BAAANQAECgMIBAAAAA==.Tirazlea:BAAANQADCgIIAgAAAA==.',
To='Tonatuih:BAABNQAECoEcAAIQAAgKER24FwCaAgAQAAgKER24FwCaAgAAAA==.',
Tr='Trezzia:BAAANQAECgQICQAAAA==.Triipod:BAAANQADCgYIEAAAAA==.Trinkat:BAAANQAECgEIAQAAAA==.Trojinn:BAAANQAECgUIBQAAAA==.Tryst:BAAANQADCgYIBgAAAA==.Tráson:BAAANQADCgYIBQAAAA==.',
Tu='Tub:BAAANQAECgUICQAAAA==.',
Ty='Tylean:BAAANQADCggIIQAAAA==.',
['Tì']='Tìríon:BAAANQABCgEIAQAAAA==.',
Ud='Udukai:BAAANQAECgQIBAAAAA==.',
Ul='Ultrastealth:BAAANQAECgUIBwAAAA==.',
Um='Umbrum:BAAANQADCgIIAgABNQAECggIHAADAHUXAA==.',
Uu='Uu:BAAANQAECgMIBAAAAA==.',
Va='Vadrozsa:BAAANQADCggIIQAAAA==.Vallarie:BAAANQADCgQJBAAAAA==.Vareyn:BAAANQADCggJFAAAAA==.',
Vo='Vorth:BAABNQAECoEZAAIPAAcKgw8WOACFAQAPAAcKgw8WOACFAQAAAA==.Vorükh:BAAANQAECgUJBQABNQAECgIIBAAFAAAAAA==.',
Vu='Vulturous:BAAANQADCgYICgAAAA==.',
Vy='Vydian:BAAANQADCgYICQAAAA==.',
Wa='Waldir:BAABNQAECoEWAAMSAAcK7CBVJACnAgASAAcK7CBVJACnAgAVAAEK3wMYXQEqAAAAAA==.Walock:BAAANQADCgMIAwAAAA==.Wanted:BAAANQADCgYIBgAAAA==.Watz:BAAANQADCgYIDAAAAA==.',
Wh='Wholesale:BAABNQAECoEZAAIgAAcKwBY0OgDcAQAgAAcKwBY0OgDcAQAAAA==.',
Wr='Wrack:BAAANQADCgUJCgAAAA==.Wraithian:BAAANQABCgQIBAAAAA==.Wratsoul:BAAANQAECgYICwAAAA==.',
Xe='Xessala:BAAANQAECgYIDgAAAA==.',
Xh='Xheero:BAABNQAECoEeAAILAAgKdRoYMwCRAgALAAgKdRoYMwCRAgAAAA==.Xheerom:BAAANQADCgUIBQAAAA==.',
Ya='Yagiashi:BAAANQAECgQIBAABNQAECggIHAADAHUXAA==.',
Yu='Yulica:BAAANQAECgEIAQAAAA==.',
Za='Zaffy:BAAANQAECgUIEAAAAA==.Zaktrix:BAAANQADCgYIEQAAAA==.Zaleron:BAAANQADCggIEgAAAA==.Zaruba:BAAANQAECgYIEQABNQAECgYIEQAFAAAAAA==.Zatkyng:BAABNQAECoEUAAIdAAYKTg5fLABMAQAdAAYKTg5fLABMAQAAAA==.',
Ze='Zekos:BAAANQADCggIIQAAAA==.',
Zi='Zillver:BAAANQAECgUIBQABNQAECggIHAAWAIkQAA==.Zimdalar:BAAANQAECgMIBAAAAA==.',
Zu='Zulre:BAABNQAECoEXAAIgAAgKQxq0IQBxAgAgAAgKQxq0IQBxAgAAAA==.',
['Ôv']='Ôverkill:BAAANQAECgMIBQAAAA==.',
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
