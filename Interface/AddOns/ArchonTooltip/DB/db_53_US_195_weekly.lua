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

local lookup = {'Druid-Balance','Warrior-Arms','Warrior-Protection','Monk-Brewmaster','Unknown-Unknown','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Devourer','Priest-Holy','Monk-Mistweaver','Shaman-Elemental','Evoker-Augmentation','Priest-Shadow','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','Rogue-Subtlety','Druid-Restoration','Evoker-Preservation','Druid-Feral','Mage-Arcane','Paladin-Retribution','Paladin-Holy','Warrior-Fury','Rogue-Assassination','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','Paladin-Protection','Mage-Frost','Druid-Guardian','Hunter-Survival','Monk-Windwalker','DeathKnight-Blood',}
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Ackrenoth:BAAANQADCggIJAAAAA==.',
Ad='Adynn:BAABNQAECoEgAAIBAAgK6iQBDQBUAwABAAgK6iQBDQBUAwAAAA==.',
Ae='Aermoss:BAAANQABCgUIBQAAAA==.Aeru:BAAANQADCgYIBgAAAA==.Aethreal:BAAANQADCgYICwAAAA==.',
Af='Afridium:BAAANQADCgEIAQAAAA==.',
Ak='Akikusa:BAAANQADCggICgAAAA==.',
Al='Alderath:BAAANQABCgQJBQAAAA==.Alista:BAABNQAECoEmAAICAAkKgSSxBgC5AwACAAkKgSSxBgC5AwAAAA==.Allyeska:BAAANQADCgMIAwAAAA==.Alnharaelune:BAAANQADCgYIDQAAAA==.',
Am='Amarea:BAAANQAECgIIAgAAAA==.Amor:BAAANQAECgUIDgAAAA==.',
An='Anali:BAAANQAECgcIDQAAAA==.Anani:BAAANQADCggIJAAAAA==.Angreifer:BAABNQAECoEjAAMDAAgKfRvRCQB/AgADAAgKfRvRCQB/AgACAAIKsAT7HwFcAAAAAA==.Anori:BAAANQAECgUIDQAAAA==.',
Ao='Aonar:BAAANQAECgEIAgAAAA==.',
Aq='Aqua:BAAANQABCgcIEwAAAA==.',
Ar='Arc:BAAANQAECgYIEQABNQAECggIIwAEADAiAA==.Archenteron:BAAANQADCgYIDgAAAA==.Archnunin:BAAANQAECggICAAAAA==.Ardorcinder:BAAANQAECgEIAQAAAA==.Argentur:BAAANQADCgEIAQAAAA==.Arkaan:BAAANQADCgUIBQABNQAECgUICAAFAAAAAA==.Arrozz:BAAANQADCgQIBAAAAA==.Arthmanafel:BAABNQAECoEaAAMGAAgKlhgIJQA7AgAGAAgKlhgIJQA7AgAHAAEKJQtmzgAxAAAAAA==.',
As='Asbjorne:BAAANQAECgMIBgAAAA==.',
Au='Autumnmoon:BAAANQAECgQIBwAAAA==.',
Av='Avalsong:BAABNQAECoEhAAIIAAgKeBtYGACAAgAIAAgKeBtYGACAAgAAAA==.Avelos:BAABNQAECoEkAAIJAAkKSh0WHwDZAgAJAAkKSh0WHwDZAgAAAA==.',
Ay='Ayowenn:BAAANQADCgIIAgAAAA==.Ayzmist:BAAANQAECgUIDwAAAA==.Ayzmyth:BAABNQAECoEcAAMKAAgKcQ3WGwCZAQAKAAgKcQ3WGwCZAQAEAAUKWAnjHgDNAAAAAA==.',
Ba='Banthapooduu:BAAANQADCgcIEwAAAA==.',
Be='Beasic:BAABNQAECoEeAAILAAgKBQTzkQBHAQALAAgKBQTzkQBHAQAAAA==.Beletili:BAABNQAECoEhAAIJAAgKdQ/GXQDXAQAJAAgKdQ/GXQDXAQAAAA==.Beátrix:BAAANQADCgIIAgAAAA==.',
Bi='Birdman:BAAANQADCgYIBgABNQADCggIIwAFAAAAAA==.Bismuth:BAAANQADCgYIBgAAAA==.',
Bl='Blatendrg:BAABNQAECoEiAAIMAAgKxRRcBwAQAgAMAAgKxRRcBwAQAgAAAA==.Blindcloud:BAAANQAECgUIBgAAAA==.',
Bo='Boot:BAAANQAECgQIBgAAAA==.Borodemonin:BAEBNQAECoEoAAIIAAkKMyWpAQDLAwAIAAkKMyWpAQDLAwAAAA==.',
Br='Breae:BAABNQAECoEdAAMJAAgKHROYUwD8AQAJAAgKHROYUwD8AQANAAMK/AfnVQCDAAAAAA==.Brieanna:BAAANQADCgUIBgAAAA==.Bristia:BAAANQAECgIIAgAAAA==.Brueggar:BAAANQAECgEIAQAAAA==.Brutyl:BAAANQAECgEIAQABNQAECggICAAFAAAAAA==.',
Bu='Bulky:BAAANQAECgIIAgAAAA==.',
By='Byegone:BAAANQAECgQIBAAAAA==.',
Ca='Cadforus:BAAANQADCgYIDgABNQAECgUICgAFAAAAAA==.Cafë:BAAANQADCgcICgABNQAECgkJHgAOAMUiAA==.Caicee:BAAANQADCgIIAgAAAA==.Caistin:BAAANQADCgYIDgAAAA==.Calyma:BAAANQAECgEIAQAAAA==.Camelsotters:BAAANQAECgQIDwAAAA==.Casca:BAAANQAECgIIAgAAAA==.Catsclaw:BAAANQADCgYIBgAAAA==.',
Ce='Cenjeru:BAABNQAECoEdAAMGAAcK5hh/LwDwAQAGAAcK3BZ/LwDwAQAHAAYKbhdUWwB8AQAAAA==.',
Ch='Chezzie:BAAANQAECgYICwAAAA==.Chiot:BAAANQAECgcIEwAAAA==.',
Ci='Cimerian:BAAANQAECgIIBAAAAA==.',
Cl='Clone:BAAANQADCgYIBgAAAA==.',
Co='Cobalticus:BAAANQADCgQIBAAAAA==.Concealer:BAAANQADCgEIAQAAAA==.Conejamala:BAABNQAECoEZAAMPAAkKnx2WGQAaAwAPAAkKMR2WGQAaAwAQAAMK6w0aVACuAAAAAA==.Corange:BAAANQABCgIIBAAAAA==.Cordini:BAAANQADCgcIDgAAAA==.Corlock:BAAANQADCgQIBAAAAA==.Cormech:BAAANQAECgQIBgAAAA==.Cornite:BAAANQADCgYJDgAAAA==.',
Cr='Crizzo:BAABNQAECoEaAAIPAAcKJxqVWgA7AgAPAAcKJxqVWgA7AgAAAA==.',
Da='Daddyslilgrl:BAAANQAECgMIBQAAAA==.Dakra:BAEANQAECgYIEAAAAA==.Dalamar:BAAANQAECgQIDwABNQAECgkJKwANACIdAQ==.Dalandis:BAAANQAECgYIEAAAAA==.Dalyeth:BAABNQAECoEZAAMRAAcKbSXYAwDyAgARAAcKbSXYAwDyAgASAAEKuAQriQApAAAAAA==.Darianno:BAAANQADCgMIAwAAAA==.Darkwingorc:BAABNQAECoEpAAIPAAkKuRyTIgDvAgAPAAkKuRyTIgDvAgAAAA==.Darkwulf:BAAANQADCgcJDQAAAA==.Daunt:BAAANQADCgcIBwABNQAECggIGgABANsHAA==.Dawnfire:BAAANQADCgEIAQAAAA==.Dawnmane:BAAANQADCgEIAQAAAA==.',
De='Deadsecsi:BAAANQABCgEIAQAAAA==.Decypher:BAAANQAECgIIAgABNQAECggIIAATADsUAA==.Deebz:BAABNQAECoEaAAIUAAcKTRPDKQCeAQAUAAcKTRPDKQCeAQAAAA==.Deliverance:BAABNQAECoErAAINAAkKIh0ODwDqAgANAAkKIh0ODwDqAgAAAA==.Demigoth:BAABNQAECoEWAAIVAAcKIhI4IACzAQAVAAcKIhI4IACzAQAAAA==.Denethmon:BAAANQAECgEJAQABNQAECgMIAwAFAAAAAA==.Dentik:BAABNQAECoEhAAMWAAYKQQu4GAA4AQAWAAYKQQu4GAA4AQAUAAYK0g4KOAAnAQAAAA==.Denuma:BAAANQAECgMIAwAAAA==.Devilina:BAAANQADCggICgAAAA==.',
Dh='Dheriana:BAABNQAECoEgAAITAAgKOxQLFAA4AgATAAgKOxQLFAA4AgAAAA==.Dherisis:BAAANQADCgcIBwABNQAECggIIAATADsUAA==.Dherli:BAAANQAECgIIAgABNQAECggIIAATADsUAA==.',
Di='Diamair:BAABNQAECoEaAAIXAAcKFg813gClAQAXAAcKFg813gClAQAAAA==.Divynelle:BAAANQABCgIIAgAAAA==.Dixiee:BAAANQAECgQICAAAAA==.',
Dn='Dnegelpal:BAABNQAECoEZAAIYAAcKRgtCvgBnAQAYAAcKRgtCvgBnAQAAAA==.',
Do='Dodgecharger:BAAANQAECgIIAgAAAA==.',
Dr='Dragerin:BAAANQAECgMIAwAAAA==.Dragonfood:BAAANQAECgMIBAAAAA==.Drakilu:BAABNQAECoEfAAIPAAgKjxbAVQBIAgAPAAgKjxbAVQBIAgAAAA==.Drakra:BAEANQAECgYICgABNQAECgYIEAAFAAAAAA==.Drasic:BAABNQAECoEqAAIUAAkKBB1bCwD5AgAUAAkKBB1bCwD5AgAAAA==.Dreddscott:BAAANQAECgEIAQABNQAECggIGwATAIMTAA==.Dretro:BAAANQAECgIIBQAAAA==.Drovosi:BAAANQADCggIIgAAAA==.',
Du='Durin:BAAANQAECgYIEwAAAA==.Durward:BAAANQAECgYIDQAAAA==.Duvo:BAAANQAECgYIEQAAAA==.',
Dw='Dwarvey:BAAANQADCgUIBQAAAA==.',
['Dæ']='Dæmôna:BAAANQADCgQIBQAAAA==.',
['Dé']='Détank:BAABNQAECoEgAAIGAAcKthnDKwAIAgAGAAcKthnDKwAIAgAAAA==.',
Ea='Easyname:BAAANQAECgcICwAAAA==.',
Ei='Eiene:BAAANQAECgUICQAAAA==.Eithetala:BAAANQADCgYICAAAAA==.',
El='Elemental:BAAANQAECggIDQABNQAFFAMIBgAUAEAOAA==.Elloseth:BAAANQAECgMIBwAAAA==.Elmorin:BAAANQADCggIFgAAAA==.Eluneh:BAAANQADCgYICAAAAA==.',
Eo='Eolon:BAAANQAECgIIAgAAAA==.',
Ep='Epica:BAABNQAECoEcAAIXAAkKng9PmgAuAgAXAAkKng9PmgAuAgAAAA==.',
Er='Eragonhawk:BAAANQAECgIIAgAAAA==.Eraina:BAAANQAECgMIAwAAAA==.Eroldan:BAAANQADCgYICQAAAA==.Erovianoria:BAAANQAECgYIDwAAAA==.',
Es='Essun:BAABNQAECoEeAAISAAkK9BqxHwB2AgASAAkK9BqxHwB2AgABNQAFFAIIBAAFAAAAAA==.',
Ev='Evanthe:BAAANQAECgYIDwAAAA==.',
Ex='Expire:BAAANQADCgEIAQAAAA==.',
Fa='Faizor:BAAANQADCggIDgAAAA==.Fastal:BAAANQADCgcIFwAAAA==.Fauxborn:BAAANQAECgQIBgAAAA==.Fauxstorm:BAAANQADCgQIBQAAAA==.',
Fe='Fedwell:BAAANQAECgYIEwAAAA==.',
Fi='Finluc:BAAANQADCgUIBQAAAA==.Finngan:BAAANQAECgUIEAAAAA==.Fitoria:BAAANQAECgMIBAABNQAECggIIwAEADAiAA==.',
Fo='Forestkin:BAAANQAECgIIAgABNQAECgcIGQARAG0lAA==.Foxhope:BAAANQAECgQIBgAAAA==.',
Fr='Friartuk:BAAANQAECgEIAQAAAA==.Frozenthunda:BAABNQAECoEjAAIXAAcKywol5wCVAQAXAAcKywol5wCVAQAAAA==.',
Fu='Furna:BAAANQAECgYIDAAAAA==.Fuzzyhooves:BAABNQAECoEfAAIZAAgKeyBXGwDzAgAZAAgKeyBXGwDzAgAAAA==.',
Ga='Gabrael:BAABNQAECoEpAAMaAAgKChICCwDyAQAaAAgKChICCwDyAQACAAcKKwvErgB6AQAAAA==.',
Gh='Ghorienge:BAAANQAECgMIBAAAAA==.',
Gi='Gilox:BAAANQAECgYIDwAAAA==.',
Gl='Glossu:BAAANQADCgIIAgAAAA==.',
Gn='Gndmexia:BAAANQADCgMIAwAAAA==.Gneiss:BAAANQAECgMIAwAAAA==.',
Go='Goldenarrow:BAAANQABCgYIDgAAAA==.Gorgilz:BAAANQADCgMIBgAAAA==.Gothgirldemi:BAABNQAECoEhAAIUAAgKrh7NEQCkAgAUAAgKrh7NEQCkAgAAAA==.',
Gr='Graymon:BAAANQAECgEIAgAAAA==.Greebo:BAAANQAECgEIAgAAAA==.Grist:BAAANQADCgYIDwAAAA==.',
Gu='Guatalupe:BAAANQADCgYIBgAAAA==.Guilherme:BAAANQADCggIEAAAAA==.',
Gw='Gwenyver:BAAANQAECgEIAgAAAA==.',
Ha='Hailthanatos:BAAANQAECggIEwAAAA==.Hamord:BAAANQAECgMIBgAAAA==.Hansdelbruk:BAAANQADCgUIBQAAAA==.Hardlight:BAAANQADCgYIBgAAAA==.Harliquette:BAABNQAECoEXAAINAAcKJxClKwCgAQANAAcKJxClKwCgAQAAAA==.Harliqynn:BAAANQAECgUICQAAAA==.Harlock:BAABNQAECoEaAAMTAAkKJxKNFwAQAgATAAgK+BCNFwAQAgAbAAcKIxF+NgC/AQAAAA==.Hazelnuts:BAAANQADCgUIBQAAAA==.',
Hi='Hiten:BAAANQAECgYIEQAAAA==.',
Ho='Hoofinmouth:BAAANQAECgMIAwAAAA==.Hoosh:BAAANQAECgIIAgAAAA==.Hopedaimond:BAAANQAECgYICQAAAA==.',
Hu='Huntertattoo:BAAANQAECgYIDQAAAA==.Husgus:BAAANQADCgYIDAABNQAFFAIIAgAFAAAAAA==.Huungron:BAAANQADCgYIDAAAAA==.',
Ic='Icynips:BAAANQADCgQIBAAAAA==.',
Il='Illianarra:BAAANQAECgMIBAAAAA==.Ilthad:BAAANQAECgQICQAAAA==.',
Im='Imawarrionow:BAAANQADCgIIAgAAAA==.Imora:BAAANQADCgMIAwAAAA==.Imshalar:BAAANQABCgIIAgABNQAECgQIBAAFAAAAAA==.',
In='Infurryating:BAAANQAECggIDAAAAA==.',
Ir='Iroar:BAAANQADCgIIAgAAAA==.Irumble:BAAANQADCggICgAAAA==.',
Is='Ischadè:BAAANQADCgUIBgAAAA==.Iskuros:BAAANQADCgMIAwAAAA==.',
It='Itsirk:BAAANQAECgYIDAAAAA==.',
Iz='Izyebelle:BAAANQAECgUICgAAAA==.',
Ja='Jadevine:BAAANQADCgEIAQAAAA==.Jalynfein:BAAANQAECgUIBQAAAA==.Janar:BAAANQADCgYIBwAAAA==.',
Je='Jefeorganico:BAABNQAECoEWAAQcAAYKnQP8GQCSAAAcAAMK/QT8GQCSAAAdAAQKFQJBVAB3AAAeAAQKTQJ6EAFjAAAAAA==.Jeloi:BAAANQAECgIIAgAAAA==.Jenkshi:BAAANQADCgcIDQAAAA==.',
Ji='Jimmydin:BAABNQAECoEkAAMZAAkK6RpKJADCAgAZAAkK6RpKJADCAgAYAAgKsxqdYQBJAgAAAA==.',
Ju='Juego:BAAANQADCgQIBAAAAA==.Julkan:BAAANQAECgQIBgAAAA==.Junhoong:BAABNQAECoEcAAIYAAkKExDLdwANAgAYAAkKExDLdwANAgAAAA==.Juvia:BAABNQAECoEaAAMLAAgKBxTaUQAEAgALAAgKBxTaUQAEAgAfAAYKGhDijQA4AQABNQAECggIIwAgAJwQAA==.',
Jy='Jynnysa:BAAANQAECgEIAQABNQAECgcIGAAgAIMcAA==.',
Ka='Kai:BAAANQAECgMIBAAAAA==.Kairoll:BAABNQAECoEjAAIJAAgKHA06agCqAQAJAAgKHA06agCqAQAAAA==.Kaleìna:BAAANQADCgcICAAAAA==.Kallisto:BAAANQADCgcIBwAAAA==.Karaa:BAAANQAECgIIAgAAAA==.Kariena:BAAANQAECgUICAAAAA==.Kart:BAAANQADCgEIAQAAAA==.Kashaka:BAAANQADCgcIEgAAAA==.Katesluage:BAABNQAECoEpAAMhAAgKHRxWBQCXAgAhAAgKHRxWBQCXAgAXAAUKuQlEOAEKAQAAAA==.Kawrrl:BAAANQADCgMIAwAAAA==.Kayyaa:BAAANQADCggICAAAAA==.',
Ke='Keeya:BAAANQAECgUIDwAAAA==.Kelina:BAAANQADCgIIAgAAAA==.Kendari:BAAANQAECgYIEQAAAA==.Kernasas:BAAANQAECgQICAAAAA==.',
Kh='Khiari:BAAANQADCgUIBQABNQAECgUICAAFAAAAAA==.',
Ki='Kier:BAAANQADCggICAAAAA==.Kizaraan:BAAANQADCgUIBQAAAA==.',
Kl='Kleyntamar:BAAANQAECgEIAgAAAA==.',
Kn='Knyghtly:BAAANQAECggICAAAAA==.',
Ko='Konstantien:BAAANQAECgUIBQAAAA==.Koric:BAAANQAECgcICQAAAA==.',
Kr='Kretsch:BAAANQADCgUIBQAAAA==.Krickket:BAAANQADCgMIAwABNQAECgQICAAFAAAAAA==.',
Ku='Kupau:BAAANQAECgQICAAAAA==.Kurogami:BAABNQAECoEgAAMHAAgKMBFVTQC2AQAHAAgKMBFVTQC2AQAGAAEKmwkYmAAtAAAAAA==.Kuthixo:BAAANQADCggIIwAAAA==.',
Ky='Kylos:BAAANQABCgQIBgAAAA==.Kynnigos:BAAANQABCgIIAgAAAA==.',
La='Landstrider:BAABNQAECoEWAAIPAAkK9hPQQwB6AgAPAAkK9hPQQwB6AgABNQAFFAMIBgAUAEAOAA==.Lanss:BAABNQAECoEfAAMCAAgK8hvtXQBVAgACAAgKoxjtXQBVAgADAAIKOBnMLwCBAAAAAA==.Larachel:BAAANQAECgQIDAAAAA==.Lastaril:BAAANQADCgYIDwAAAA==.Lastword:BAAANQAECgEJAQABNQAECgIIBAAFAAAAAA==.Laur:BAABNQAECoEaAAINAAgKdQ1gKAC/AQANAAgKdQ1gKAC/AQAAAA==.',
Le='Leipäjuusto:BAAANQAECgcICwAAAA==.',
Li='Liartes:BAAANQAECgEIAgAAAA==.Liderela:BAAANQADCgEIAQAAAA==.Lilipo:BAAANQAECgUIDQAAAA==.',
Ll='Llarastrasza:BAAANQAECgIIAgABNQAECgYICAAFAAAAAA==.',
Lo='Logoth:BAAANQAECgQIBAAAAA==.Lohgarak:BAAANQADCggIFQAAAA==.',
Lu='Lunaellana:BAAANQADCgYICAAAAA==.',
Ly='Lystaan:BAAANQABCgQIBAAAAA==.',
['Lü']='Lüvpüp:BAABNQAECoEeAAIOAAkKxSITBABOAwAOAAkKxSITBABOAwAAAA==.',
Ma='Maiku:BAAANQAECgcIEwAAAA==.Majo:BAAANQAECgIIAgAAAA==.Makado:BAAANQAECgcIEgAAAA==.Makoroth:BAAANQAECgYIEgAAAA==.Malanda:BAAANQADCgQIBAAAAA==.Malygosson:BAAANQAECgUICgAAAA==.Masharu:BAAANQADCgcIBwAAAA==.Matua:BAAANQAECgIIAgAAAA==.Maycee:BAAANQAECgQICgAAAA==.',
Mc='Mcat:BAAANQAECgMIBAAAAA==.Mcgriddle:BAAANQADCgEIAQAAAA==.Mcnaugh:BAAANQAECgMIBQAAAA==.Mcsaltface:BAAANQAECgMIBgAAAA==.',
Me='Meddic:BAAANQAECgUICAAAAA==.Menarot:BAAANQAECgYIDwAAAA==.Mendais:BAAANQADCgYIDgAAAA==.Meztlitotol:BAAANQAECgYICwABNQAECggIIwADAH0bAA==.',
Mi='Mirosdrigo:BAAANQADCgcIBwAAAA==.Mirosmundo:BAABNQAECoEjAAIEAAkK8BzIBgC8AgAEAAkK8BzIBgC8AgAAAA==.Mistfit:BAAANQAECggICAAAAA==.Miyu:BAABNQAECoEhAAMNAAgKpg9bJgDSAQANAAgKpg9bJgDSAQAJAAcKzwTAlQAZAQAAAA==.',
Mo='Mod:BAABNQAECoEiAAMfAAgKPxgBRwAaAgAfAAgKPxgBRwAaAgALAAEKEQtvIgEsAAAAAA==.Moeng:BAAANQADCgIIAgAAAA==.Moggatorash:BAAANQAECgQIBAAAAA==.Mogtham:BAABNQAECoEfAAIiAAgK7BHwFgC6AQAiAAgK7BHwFgC6AQAAAA==.Monlaferte:BAAANQADCgMIAwAAAA==.Montsegur:BAAANQADCggICAAAAA==.Mooforn:BAAANQAECgEIAgAAAA==.Moonfall:BAAANQAECgQIBgAAAA==.Moosader:BAAANQAECgYIEgAAAA==.Morellea:BAAANQAECgUJCgAAAA==.Morighann:BAABNQAECoEgAAIPAAcK2x6JRwBwAgAPAAcK2x6JRwBwAgAAAA==.Moñgoose:BAAANQADCgMIAwAAAA==.',
My='Mynkx:BAAANQAECgUICAAAAA==.Mythyras:BAABNQAECoEYAAIgAAcKgxwcFgAmAgAgAAcKgxwcFgAmAgAAAA==.',
Na='Naeomy:BAABNQAECoEqAAIbAAgKXQehPQCWAQAbAAgKXQehPQCWAQAAAA==.Nahaman:BAAANQAECgMIAwAAAA==.Napolien:BAABNQAECoEjAAMgAAgKnBCGLQBGAQAgAAcKdg6GLQBGAQAZAAIKdhFW7ABvAAAAAA==.Naugan:BAAANQADCgEIAQAAAA==.',
Ne='Nechahira:BAACNQAFFIEGAAIUAAMKQA6fCgDfAAAUAAMKQA6fCgDfAAA1AAQKgRcAAhQACApiDSIoAK4BABQACApiDSIoAK4BAAAA.Nethim:BAAANQAECgIIAgABNQAECgMIAwAFAAAAAA==.Nezana:BAAANQAECgIIAgAAAA==.',
Ni='Nien:BAAANQAECgEIAQAAAA==.Nihlathak:BAAANQAECgYIDAAAAA==.Ninada:BAABNQAECoEaAAMXAAcKAA3Q6ACSAQAXAAcK2wvQ6ACSAQAhAAIKcggePAA8AAAAAA==.',
No='Noranna:BAAANQAECgEIAgAAAA==.',
Ny='Nyim:BAAANQAECgEIAQAAAA==.Nynsyn:BAAANQAECgEIAQABNQAECgcIGAAgAIMcAA==.Nyxeira:BAAANQAECgYICgAAAA==.',
['Nâ']='Nâli:BAAANQADCggIDQAAAA==.',
Ob='Obsidianclaw:BAAANQADCgIIAwAAAA==.',
Oh='Ohthesemyboo:BAAANQAECgIIAgAAAA==.Ohwellz:BAAANQAECgEJAQAAAA==.',
Op='Ophin:BAABNQAECoEgAAIHAAgKuBgzOAAfAgAHAAgKuBgzOAAfAgAAAA==.',
Pa='Panamared:BAABNQAECoEbAAITAAgKgxNKFQApAgATAAgKgxNKFQApAgAAAA==.Pappawoody:BAABNQAECoEcAAICAAgK1BvfWABkAgACAAgK1BvfWABkAgAAAA==.Parishealton:BAAANQADCgcJBwAAAA==.',
Pe='Pellegryn:BAAANQADCgYICQAAAA==.Pennyfeather:BAABNQAECoEdAAMJAAgKgAwOawCnAQAJAAgKgAwOawCnAQANAAQKQApGSQDNAAAAAA==.Pezza:BAAANQAECgUICgAAAA==.',
Ph='Phaze:BAABNQAECoEcAAIjAAcKdCJ9AwCwAgAjAAcKdCJ9AwCwAgAAAA==.Phideauxe:BAAANQAECgQIBQAAAA==.Phorate:BAAANQAECgQICAAAAA==.',
Pl='Pluralbutter:BAAANQAECgcIEAAAAA==.',
Po='Popexeo:BAAANQAECgcIDQABNQAFFAYIDQAUAJIRAA==.',
Pr='Prometheum:BAAANQAECgIIAgAAAA==.',
Ps='Psyvern:BAAANQAECgcIDgAAAA==.',
Qu='Quiccerstorm:BAAANQADCgQIBQAAAA==.',
Ra='Raevennlumis:BAAANQAECgYIDwAAAA==.Raevenns:BAAANQADCggJCAABNQAECgYIDwAFAAAAAA==.Rahkhard:BAABNQAECoEjAAMEAAgKMCKSBAATAwAEAAgKMCKSBAATAwAkAAUKDhU8OQASAQAAAA==.Rascdit:BAAANQAECgUICgAAAA==.',
Re='Recreant:BAAANQAECgUICAAAAA==.Reiyoso:BAAANQADCggJDgAAAA==.Reui:BAAANQADCgEIAQAAAA==.',
Rh='Rhemibumbum:BAAANQAECgUICwAAAA==.',
Ro='Rocketbilly:BAAANQADCgIIAgAAAA==.Roobee:BAAANQAECgUICgAAAA==.',
Ru='Ruaic:BAAANQADCgcICgAAAA==.',
Sa='Sableanne:BAAANQADCgEIAQAAAA==.Sacréd:BAAANQAECgUIDwAAAA==.Sarkan:BAAANQADCgYICQAAAA==.Sarova:BAAANQAECgYICgAAAA==.Satori:BAAANQAECgEIAgAAAA==.',
Sc='Scalewind:BAAANQADCgYIBgAAAA==.',
Se='Seldeath:BAAANQADCgEJAQAAAA==.Selfu:BAABNQAECoEfAAIkAAgKShZqHgATAgAkAAgKShZqHgATAgAAAA==.Sellidor:BAABNQAECoEaAAIPAAgKkB8PHgAEAwAPAAgKkB8PHgAEAwAAAA==.Serenesong:BAAANQADCgEIAQAAAA==.Seriniyaa:BAAANQADCggIKAAAAA==.',
Sh='Sheara:BAAANQAECggICQAAAA==.Shinjiro:BAAANQAECgUIDgAAAA==.Shirito:BAABNQAECoEmAAMHAAgKiCUKCQBmAwAHAAgKeCUKCQBmAwAGAAcKXiQEFQDBAgAAAA==.Shiritodh:BAAANQAECgcIEwAAAA==.Shockin:BAAANQAECgYICgAAAA==.Shortnstout:BAACNQAFFIEFAAIgAAIKBR/+BwCtAAAgAAIKBR/+BwCtAAA1AAQKgSAAAyAACQppIVsJAOkCACAACQppIVsJAOkCABgAAQrIGxxbAUwAAAAA.Shugo:BAAANQAECgMIBQAAAA==.',
Si='Sienje:BAAANQAECgcIEgAAAA==.Sigma:BAAANQAECgcIEwAAAA==.Simpleson:BAABNQAECoEhAAMeAAgKLB2sRABnAgAeAAcK9B2sRABnAgAdAAEKtBcjZwBHAAAAAA==.Sinbàd:BAACNQAFFIEFAAIIAAQKuQwkCQAnAQAIAAQKuQwkCQAnAQA1AAQKgSYAAggACQplHBESAMYCAAgACQplHBESAMYCAAAA.Sinistris:BAAANQAECgEIAQAAAA==.',
Sk='Skie:BAAANQAECgYIBwABNQAECggICAAFAAAAAA==.Skrabble:BAAANQAECgMIBAAAAA==.',
Sl='Slaete:BAAANQAECgUIDAAAAA==.Slush:BAAANQAECgQIBAAAAA==.',
Sm='Smallz:BAAANQAECgEIAQABNQAECgYIEQAFAAAAAA==.Smorgas:BAAANQAECgEIAQABNQAECgYIEAAFAAAAAA==.Småug:BAAANQADCgMJAwAAAA==.',
So='Solemn:BAAANQAECgUIEgABNQAECggIGgAPAJAfAA==.Solrana:BAAANQAECgIIAwAAAA==.Songmistress:BAAANQAECgYIDAAAAA==.Sorren:BAAANQADCggIGwAAAA==.Sotta:BAAANQAECgIIAwAAAA==.Sozin:BAAANQADCgIIAgAAAA==.',
Sp='Spritmoon:BAAANQADCgYIBgAAAA==.',
Sq='Squeezee:BAAANQADCggICAAAAA==.',
St='Stardrive:BAAANQAECgUICAAAAA==.Stevesteve:BAAANQAECgYIEQAAAA==.Stumpii:BAAANQADCgIIAgAAAA==.',
Su='Sunasha:BAAANQADCgYIEgAAAA==.Superbautumn:BAAANQAECgIIBAAAAA==.',
Sy='Synge:BAAANQAECgMIBAAAAA==.Synnyca:BAAANQADCgcJBwABNQAECgcIGAAgAIMcAA==.',
['Sé']='Sélune:BAAANQAECgYICAAAAA==.',
Ta='Tachyon:BAAANQAECgQJBgABNQAECgkJHgAOAMUiAA==.Taeonaki:BAAANQADCgMIAwAAAA==.Tagnaras:BAAANQAECgQICQAAAA==.Tahlang:BAAANQABCgYICAAAAA==.Tali:BAAANQAECgMIBAAAAA==.Taliasluage:BAAANQADCggICAABNQAECggIKQAhAB0cAA==.Tangle:BAAANQAECgYIEQABNQAECggICAAFAAAAAA==.Tanka:BAABNQAECoEbAAICAAgKRRyOSgCQAgACAAgKRRyOSgCQAgAAAA==.Tannisse:BAAANQADCgYIDgAAAA==.Tanuki:BAAANQADCggIHwAAAA==.Tapol:BAAANQAECgQIBwABNQAECgQICAAFAAAAAA==.Tashlaraz:BAEANQAECgEIAgAAAA==.Tasi:BAAANQAECgQIBAAAAA==.Taurannosaur:BAAANQADCggIDAAAAA==.Taurentots:BAAANQAFFAMIAwAAAA==.',
Te='Telkas:BAAANQADCgUIBQAAAA==.Temporantus:BAAANQADCggIJAAAAA==.Tenko:BAABNQAECoEXAAMXAAcK0goP9QB7AQAXAAcK5wgP9QB7AQAhAAIKhw92LwBkAAAAAA==.',
Th='Thaddeus:BAAANQAECgQIBQAAAA==.Therm:BAACNQAFFIEPAAIYAAUKLh4iBwC0AQAYAAUKLh4iBwC0AQA1AAQKgTIAAxgACQqJJiIDAN4DABgACQqJJiIDAN4DABkAAQrQB/gCATsAAAAA.Thoramier:BAAANQAECgUICQAAAA==.',
Ti='Tibble:BAAANQAECgMIBAAAAA==.Timoonja:BAAANQAECgQIBwAAAA==.Tirazlea:BAAANQADCgIIAgAAAA==.',
To='Tonatuih:BAABNQAECoEkAAISAAgKMx+wFgDHAgASAAgKMx+wFgDHAgAAAA==.',
Tr='Trezzia:BAAANQAECgQIDQAAAA==.Triipod:BAAANQADCgYIEAAAAA==.Trinkat:BAAANQAECgEIAgAAAA==.Trojinn:BAAANQAECgUIBQAAAA==.Tryst:BAAANQADCgYIBgAAAA==.Tráson:BAAANQADCgYIBQAAAA==.',
Tu='Tub:BAAANQAECggICQAAAA==.',
Ty='Tylean:BAAANQADCggIJAAAAA==.',
['Tì']='Tìríon:BAAANQABCgEIAQAAAA==.',
Ud='Udukai:BAAANQAECgQIBAAAAA==.',
Ul='Ultrastealth:BAAANQAECgUIDQAAAA==.',
Um='Umbrum:BAAANQADCgIIAgABNQAECggIIwADAH0bAA==.',
Uu='Uu:BAAANQAECgMIBgAAAA==.',
Va='Vadrozsa:BAAANQADCggIIwAAAA==.Vallarie:BAAANQADCgQJBAAAAA==.Vareyn:BAAANQAECgMIAwAAAA==.',
Vo='Vorth:BAABNQAECoEhAAIGAAgKWxKoLwDvAQAGAAgKWxKoLwDvAQAAAA==.Vorukh:BAAANQADCgQIBAABNQAECgIIBAAFAAAAAA==.Vorúkh:BAAANQAECgIIAgABNQAECgIIBAAFAAAAAA==.Vorükh:BAAANQAECgUJBQABNQAECgIIBAAFAAAAAA==.',
Vu='Vulturous:BAAANQADCgYICgAAAA==.',
Vy='Vydian:BAAANQADCgYICQAAAA==.',
Wa='Waldir:BAABNQAECoEdAAMZAAgKbCHEJQC7AgAZAAcKjCLEJQC7AgAYAAIKgAXMVQFUAAAAAA==.Walock:BAAANQADCgMIAwAAAA==.Wanted:BAAANQADCgYIBgAAAA==.Watz:BAAANQADCgYIDAAAAA==.',
Wh='Wholesale:BAABNQAECoEgAAIlAAcK9xfSPgDlAQAlAAcK9xfSPgDlAQAAAA==.',
Wr='Wrack:BAAANQADCgcIDwAAAA==.Wraithian:BAAANQABCgQIBAAAAA==.Wratsoul:BAAANQAECgcIDQAAAA==.',
Xe='Xessala:BAABNQAECoEXAAIfAAcKxBJHZwCnAQAfAAcKxBJHZwCnAQAAAA==.',
Xh='Xheero:BAABNQAECoEjAAIPAAgKdRpcQQCCAgAPAAgKdRpcQQCCAgAAAA==.Xheerom:BAAANQADCgUIBQAAAA==.',
Ya='Yagiashi:BAAANQAECgQIBAABNQAECggIIwADAH0bAA==.',
Yu='Yulica:BAAANQAECgEIAgAAAA==.',
Za='Zaffy:BAABNQAECoEbAAIdAAcKhwuFHgByAQAdAAcKhwuFHgByAQAAAA==.Zaktrix:BAAANQADCgYIEQAAAA==.Zaleron:BAAANQADCggIFAAAAA==.Zaruba:BAABNQAECoEdAAILAAgKOAqNcgCZAQALAAgKOAqNcgCZAQABNQAECggIGgABANsHAA==.Zatkyng:BAABNQAECoEZAAIkAAcKFw0mMABhAQAkAAcKFw0mMABhAQAAAA==.',
Ze='Zekos:BAAANQADCggIKQAAAA==.',
Zi='Zillver:BAAANQAECgUIBQABNQAECggIIwAgAJwQAA==.Zimdalar:BAAANQAECgQIBwAAAA==.',
Zu='Zulre:BAABNQAECoEfAAIlAAgK8R4OGQDOAgAlAAgK8R4OGQDOAgAAAA==.',
['Ôv']='Ôverkill:BAAANQAECgUICgAAAA==.',
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
