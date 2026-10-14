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

local lookup = {'Druid-Balance','Warrior-Arms','Priest-Holy','Warrior-Protection','Warlock-Demonology','Monk-Brewmaster','Unknown-Unknown','DeathKnight-Frost','DeathKnight-Blood','DeathKnight-Unholy','DemonHunter-Devourer','Shaman-Elemental','Monk-Mistweaver','Shaman-Restoration','Evoker-Augmentation','Priest-Shadow','Druid-Guardian','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Havoc','Rogue-Subtlety','Druid-Restoration','Evoker-Preservation','Druid-Feral','Mage-Arcane','Warlock-Destruction','Priest-Discipline','Paladin-Holy','Warrior-Fury','Rogue-Assassination','Warlock-Affliction','Paladin-Protection','Mage-Frost','Monk-Windwalker','Hunter-Survival',}
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Ackrenoth:BAAANQAECgEIAQAAAA==.',
Ad='Adynn:BAABNQAECn8nAAIBAAkKpyPbBACyAwABAAkKpyPbBACyAwAAAA==.',
Ae='Aermoss:BAAANQAECgEIAQAAAA==.Aeru:BAAANQADCgYIBgAAAA==.Aethreal:BAAANQAECgQIBQAAAA==.',
Af='Afridium:BAAANQADCgEIAQAAAA==.',
Ak='Akikusa:BAAANQADCggICgAAAA==.',
Al='Alderath:BAAANQABCgQJBQAAAA==.Alista:BAABNQAECn8tAAICAAkKKCQMCgCkAwACAAkKKCQMCgCkAwAAAA==.Allyeska:BAAANQADCgUICAAAAA==.Alnharaelune:BAAANQADCgYIDQAAAA==.',
Am='Amarea:BAAANQAECgIIAwAAAA==.Amor:BAAANQAECgYIEgAAAA==.',
An='Anali:BAABNQAECn8WAAIDAAkKVRMKSgBEAgADAAkKVRMKSgBEAgAAAA==.Anani:BAAANQAECgEIAQAAAA==.Angreifer:BAABNQAECn8rAAMEAAkK9BykBgD2AgAEAAkK9BykBgD2AgACAAIKvAMGOwFVAAAAAA==.Anori:BAABNQAECn8YAAIBAAcKDAwMVwB2AQABAAcKDAwMVwB2AQAAAA==.',
Ao='Aonar:BAAANQAECgMICAAAAA==.',
Aq='Aqua:BAAANQAECgEIAwAAAA==.',
Ar='Arc:BAABNQAECn8UAAIFAAcKlhhhcwACAgAFAAcKlhhhcwACAgABNQAECgkJKgAGAPUgAA==.Arcanimous:BAAANQADCggICAAAAA==.Archenteron:BAAANQAECgEIAgAAAA==.Archnunin:BAAANQAECggICAAAAA==.Ardorcinder:BAAANQAECgEIAwAAAA==.Argentur:BAAANQADCgEIAQAAAA==.Arkaan:BAAANQADCgUIBQABNQAECgUIEAAHAAAAAA==.Arrozz:BAAANQADCgQIBAAAAA==.Arthmanafel:BAABNQAECn8hAAQIAAgKqRpgKABQAgAIAAgKvRlgKABQAgAJAAEKqR/EswBeAAAKAAEKJQs04AAxAAAAAA==.',
As='Asbjorne:BAAANQAECgMICAAAAA==.',
Au='Audi:BAAANQADCgMIAwAAAA==.Autumnmoon:BAAANQAECgQIDAAAAA==.',
Av='Avalsong:BAABNQAECn8nAAILAAkK8BsUDgAEAwALAAkK8BsUDgAEAwAAAA==.Avelos:BAABNQAECn8nAAIDAAkKKR/UIgDgAgADAAkKKR/UIgDgAgAAAA==.',
Ay='Ayowenn:BAAANQADCgIIAgAAAA==.Ayzmist:BAABNQAECn8ZAAIMAAYKPQjjrgAxAQAMAAYKPQjjrgAxAQAAAA==.Ayzmyth:BAABNQAECn8iAAMNAAgKRw/EHQCpAQANAAgKRw/EHQCpAQAGAAUKJwTUIQDJAAAAAA==.',
Ba='Banthapooduu:BAAANQADCgcIEwAAAA==.',
Be='Beasic:BAABNQAECn8lAAIMAAgKiAQjoQBPAQAMAAgKiAQjoQBPAQAAAA==.Beletili:BAABNQAECn8nAAIDAAgKnxHyYgD0AQADAAgKnxHyYgD0AQAAAA==.Bellissimio:BAAANQADCgUIBQABNQAECgkJGAAOAEoQAA==.Beátrix:BAAANQADCgIIAgAAAA==.',
Bi='Birdman:BAAANQAECgQIAQAAAA==.Bismuth:BAAANQADCggICwAAAA==.',
Bl='Blatendrg:BAABNQAECn8oAAIPAAgKkxRPCAARAgAPAAgKkhRPCAARAgAAAA==.Blindcloud:BAAANQAECgUICgAAAA==.',
Bo='Boot:BAAANQAECgUICwAAAA==.Borodemonin:BAEBNQAECn8oAAILAAkKQiXgAgCrAwALAAkKQiXgAgCrAwAAAA==.',
Br='Breae:BAABNQAECn8lAAMDAAgKIBPMYQD3AQADAAgKIBPMYQD3AQAQAAUKEALUWACgAAAAAA==.Brieanna:BAAANQADCgUIBgAAAA==.Bristia:BAAANQAECgUICAAAAA==.Brueggar:BAAANQAECgEIAgAAAA==.Brutyl:BAAANQAECgEIAgABNQAECggIDQAHAAAAAA==.',
Bu='Bulky:BAAANQAECgIIAgAAAA==.',
By='Byegone:BAAANQAECgQICAAAAA==.',
Ca='Cadforus:BAAANQADCgcIEAABNQAECgcIFAARADMXAA==.Cafë:BAAANQADCgcICgABNQAFFAMIBQASAN0WAA==.Caicee:BAAANQADCgIIAgAAAA==.Caistin:BAAANQAECgEIAQAAAA==.Calyma:BAAANQAECgEIBgAAAA==.Camelsotters:BAAANQAECgQIEQAAAA==.Casca:BAAANQAECgQICAAAAA==.Catsclaw:BAAANQAECgEIAQAAAA==.',
Ce='Cenjeru:BAABNQAECn8dAAMIAAcKyxg1OwDdAQAIAAcK8BU1OwDdAQAKAAYKnBcRZgB1AQAAAA==.',
Ch='Chezzie:BAAANQAECgYICwAAAA==.Chiot:BAABNQAECn8eAAIEAAgK3B3bCQCoAgAEAAgK3B3bCQCoAgAAAA==.',
Ci='Cimerian:BAAANQAECgIIBAAAAA==.',
Cl='Clone:BAAANQADCgYIBgAAAA==.',
Co='Cobalticus:BAAANQADCgcICwAAAA==.Concealer:BAAANQADCgEIAQAAAA==.Conejamala:BAABNQAECn8iAAMTAAkKNCClFQBEAwATAAkKNCClFQBEAwAUAAMKUw5zXgCoAAAAAA==.Corange:BAAANQABCgIIBAAAAA==.Cordini:BAAANQAECgEIAQAAAA==.Corlock:BAAANQADCgQIBAAAAA==.Cormech:BAAANQAECgQICAAAAA==.Cornite:BAAANQADCgYJDgAAAA==.',
Cr='Crizzo:BAABNQAECn8iAAITAAgK3hkVSACSAgATAAgK3hkVSACSAgAAAA==.',
Da='Daddyslilgrl:BAAANQAECgMIBwAAAA==.Dakra:BAEANQAECgYIEwAAAA==.Dalamar:BAAANQAECgcIFwABNQAECgkJLgAQANMdAQ==.Dalandis:BAABNQAECn8aAAIVAAgK+RqrUQCdAgAVAAgK+RqrUQCdAgAAAA==.Dalyeth:BAABNQAECn8fAAMWAAcKYSV0BAD8AgAWAAcKYSV0BAD8AgAXAAEKAADpmAAoAAAAAA==.Darianno:BAAANQADCgMIAwAAAA==.Darkwingorc:BAABNQAECn8sAAITAAkKvR7JIAASAwATAAkKvR7JIAASAwAAAA==.Darkwulf:BAAANQADCgcJDQAAAA==.Daunt:BAAANQADCgcIBwABNQAECggIIQABAP0JAA==.Dawnfire:BAAANQADCgEIAQAAAA==.Dawnmane:BAAANQADCgEIAQAAAA==.Dayseeker:BAAANQAECgEIAQAAAA==.',
De='Deadsecsi:BAAANQABCgEIAQAAAA==.Decypher:BAAANQAECgMIBQABNQAECggIJgAYACAUAA==.Deebz:BAABNQAECn8fAAIZAAcKNBYNKQDTAQAZAAcKNBYNKQDTAQAAAA==.Deliverance:BAABNQAECn8uAAIQAAkK0x1qEQDjAgAQAAkK0x1qEQDjAgAAAA==.Demigoth:BAABNQAECn8dAAIaAAcKJRNyIgC0AQAaAAcKJRNyIgC0AQAAAA==.Denethmon:BAAANQAECgEJAQABNQAECgMIBAAHAAAAAA==.Dentik:BAABNQAECn8pAAMbAAYK3gt2HQAuAQAbAAYK3gt2HQAuAQAZAAYKYg/4PgAoAQAAAA==.Denuma:BAAANQAECgMIAwAAAA==.Devilina:BAAANQAECgEIAQAAAA==.Deàdpool:BAAANQADCgQIBAABNQAECgkJJgAFAE8YAA==.',
Dh='Dheriana:BAABNQAECn8mAAIYAAgKIBRwFQA2AgAYAAgKIBRwFQA2AgAAAA==.Dherisis:BAAANQAECgMIAwABNQAECggIJgAYACAUAA==.Dherli:BAAANQAECgIIAgABNQAECggIJgAYACAUAA==.',
Di='Diamair:BAABNQAECn8iAAIcAAgK8w2pzADqAQAcAAgK8w2pzADqAQAAAA==.Disney:BAAANQAECggICAAAAA==.Divynelle:BAAANQABCgIIAgAAAA==.Dixiee:BAAANQAECgQIDwABNQAECgUIBwAHAAAAAA==.',
Dn='Dnegelpal:BAABNQAECn8gAAIVAAcKLg0g0QBzAQAVAAcKLg0g0QBzAQAAAA==.',
Do='Dodgecharger:BAAANQAECgIIBAAAAA==.',
Dr='Dragerin:BAAANQAECgMIAwAAAA==.Dragonfood:BAAANQAECgMIBgAAAA==.Drakilu:BAABNQAECn8nAAITAAgK8xfdTwB9AgATAAgK8xfdTwB9AgAAAA==.Drakra:BAEANQAECgYICgABNQAECgYIEwAHAAAAAA==.Drasic:BAABNQAECn8yAAIZAAkKKB8yCQAvAwAZAAkKKB8yCQAvAwAAAA==.Dreamcloud:BAAANQADCgYICAAAAA==.Dreddscott:BAAANQAECgEIAgABNQAECggIIwAYAIAVAA==.Dretro:BAAANQAECgIIBQAAAA==.Drovosi:BAAANQADCggIIgAAAA==.',
Du='Durin:BAABNQAECn8eAAICAAcKKAnVxQBoAQACAAcKKAnVxQBoAQAAAA==.Durward:BAAANQAECgYIEwAAAA==.Duvo:BAABNQAECn8aAAITAAcKCxi7bQA0AgATAAcKCxi7bQA0AgAAAA==.',
Dw='Dwarvey:BAAANQADCgUIBQAAAA==.',
['Dæ']='Dæmôna:BAAANQADCgQIBQAAAA==.',
['Dé']='Détank:BAABNQAECn8nAAIIAAcKohoIMgAUAgAIAAcKohoIMgAUAgAAAA==.',
Ea='Easyname:BAABNQAECn8VAAIVAAkKVRC1iwAJAgAVAAkKVRC1iwAJAgAAAA==.',
Ei='Eiene:BAAANQAECgUICwAAAA==.Eithetala:BAAANQADCgYICAAAAA==.',
El='Elemental:BAAANQAECggIEQABNQAFFAUICwAZADIMAA==.Elloseth:BAAANQAECgMICwAAAA==.Elmorin:BAAANQADCggIFgAAAA==.Eluneh:BAAANQADCgYICAAAAA==.',
Eo='Eolon:BAAANQAECgUICAAAAA==.',
Ep='Epica:BAABNQAECn8kAAIcAAkKeQ6BsQAeAgAcAAkKeQ6BsQAeAgAAAA==.',
Er='Eragonhawk:BAAANQAECgIIBAAAAA==.Eraina:BAAANQAECgMIBAAAAA==.Eroldan:BAAANQADCgYICQAAAA==.Erovianoria:BAAANQAECgYIDwAAAA==.',
Es='Essun:BAABNQAECn8eAAIXAAkKrBn3JgBiAgAXAAkKrBn3JgBiAgABNQAFFAQICAAFAKMHAA==.',
Ev='Evanthe:BAABNQAECn8YAAMOAAkKShByXwDtAQAOAAkKShByXwDtAQAMAAEKAAAPVwEeAAAAAA==.',
Ex='Expire:BAAANQADCgEIAQAAAA==.',
Fa='Faizor:BAAANQAECgEIAwAAAA==.Fastal:BAAANQADCgcIFwAAAA==.Fatalfury:BAAANQAECggIAQAAAA==.Fauxborn:BAAANQAECgQICwAAAA==.Fauxstorm:BAAANQADCgQIBQAAAA==.',
Fe='Fedwell:BAABNQAECn8dAAIVAAcKhAyh0AB0AQAVAAcKhAyh0AB0AQAAAA==.',
Fi='Finluc:BAAANQAECgEIAQAAAA==.Finngan:BAABNQAECn8dAAIdAAgK4weYGwCPAQAdAAgK4weYGwCPAQAAAA==.Fitoria:BAAANQAECgMIBAABNQAECgkJKgAGAPUgAA==.',
Fo='Forestkin:BAAANQAECgQICAABNQAECgcIHwAWAGElAA==.Foxhope:BAAANQAECgUICwAAAA==.',
Fr='Friartuk:BAAANQAECgEIAQAAAA==.Frozenthunda:BAABNQAECn8qAAIcAAgK1gsG2ADUAQAcAAgK1gsG2ADUAQAAAA==.',
Fu='Furna:BAABNQAECn8ZAAIeAAcKVA0+DQBeAQAeAAcKVA0+DQBeAQAAAA==.Fuzzyhooves:BAABNQAECn8nAAMfAAgKgiPBEgA5AwAfAAgKgiPBEgA5AwAVAAEK0wdBoAE0AAAAAA==.',
Ga='Gabrael:BAABNQAECn8sAAMgAAkKdBBBDQDhAQAgAAgKLxFBDQDhAQACAAgKfAs1qwCsAQAAAA==.',
Ge='Genger:BAAANQAECgEIAwAAAA==.',
Gh='Ghorienge:BAAANQAECgQICwAAAA==.',
Gi='Gilox:BAABNQAECn8ZAAIhAAcKuA/iQADCAQAhAAcKuA/iQADCAQAAAA==.',
Gl='Glossu:BAAANQADCgIIAgAAAA==.',
Gn='Gndmexia:BAAANQADCgUICQAAAA==.Gneiss:BAAANQAECgMIAwAAAA==.',
Go='Goldenarrow:BAAANQABCgYIDgAAAA==.Gorgilz:BAAANQADCgMICQAAAA==.Gothgirldemi:BAABNQAECn8oAAIZAAgK4yAPDgDtAgAZAAgK4yAPDgDtAgAAAA==.',
Gr='Graymon:BAAANQAECgMICAAAAA==.Greebo:BAAANQAECgMICAAAAA==.Grist:BAAANQADCgYIDwAAAA==.',
Gu='Guatalupe:BAAANQAECgEIAQAAAA==.Guilherme:BAAANQAECgEIAgAAAA==.',
Gw='Gwenyver:BAAANQAECgEIAwAAAA==.',
Ha='Hailthanatos:BAABNQAECn8aAAIXAAkKLwuLPADOAQAXAAkKLwuLPADOAQAAAA==.Hamord:BAAANQAECgMICAAAAA==.Hansdelbruk:BAAANQADCgUIBQAAAA==.Hardlight:BAAANQAECgIIAgAAAA==.Harliquette:BAABNQAECn8dAAIQAAgK9hKTJgD0AQAQAAgK9hKTJgD0AQAAAA==.Harliqynn:BAAANQAECgUICwAAAA==.Harlock:BAABNQAECn8aAAMYAAkK0BGbGgAAAgAYAAgK7BCbGgAAAgAhAAcKtA8VRQCtAQAAAA==.Hazelnuts:BAAANQADCgUIBQAAAA==.',
Hi='Hiten:BAABNQAECn8cAAIYAAgK3geoIwCoAQAYAAgK3geoIwCoAQAAAA==.',
Ho='Hoofinmouth:BAAANQAECgMIBAAAAA==.Hoosh:BAAANQAECgIIAwAAAA==.Hopedaimond:BAAANQAECgYIDQAAAA==.',
Hu='Huntertattoo:BAABNQAECn8YAAITAAgKTQn9lQDYAQATAAgKTQn9lQDYAQAAAA==.Husgus:BAAANQADCgYIDAABNQAECgkJFwACABIQAA==.Huungron:BAAANQADCgYIDAAAAA==.',
Ic='Icynips:BAAANQADCgQIBAAAAA==.',
Il='Illianarra:BAAANQAECgMIBwAAAA==.Ilthad:BAAANQAECgYIDwAAAA==.',
Im='Imaplantnow:BAAANQAECggICAAAAA==.Imawarrionow:BAAANQADCgIIAgAAAA==.Imora:BAAANQADCgMIAwAAAA==.Imshalar:BAAANQABCgIIAgABNQAECgQIBAAHAAAAAA==.',
In='Infurryating:BAAANQAECggIEgAAAA==.',
Ir='Iroar:BAAANQADCgIIAgAAAA==.Irumble:BAAANQADCggICgAAAA==.',
Is='Ischadè:BAAANQADCgUIBgAAAA==.Iskuros:BAAANQAECgEIAwAAAA==.',
It='Itsirk:BAAANQAECgYIEAAAAA==.',
Iz='Izyebelle:BAAANQAECgUIEQAAAA==.',
Ja='Jadevine:BAAANQADCgEIAQAAAA==.Jalynfein:BAAANQAECgUIDAAAAA==.Janar:BAAANQADCgYIBwAAAA==.',
Je='Jefeorganico:BAABNQAECn8ZAAQiAAYKZQlkFAABAQAiAAUKgglkFAABAQAdAAQKaQV9RwCoAAAFAAQKgQQ7IQF3AAAAAA==.Jeloi:BAAANQAECgIIBQAAAA==.Jenkshi:BAAANQADCgcIDQAAAA==.',
Ji='Jimmydin:BAABNQAECn8nAAMfAAkK/hzkIADoAgAfAAkK/hzkIADoAgAVAAgKrRn7eQAzAgAAAA==.',
Ju='Juego:BAAANQADCgQIBAAAAA==.Julkan:BAAANQAECgQIBgAAAA==.Junhoong:BAABNQAECn8kAAIVAAkKEBG8hAAaAgAVAAkKEBG8hAAaAgAAAA==.Juvia:BAABNQAECn8hAAMMAAgK3hU2XAAKAgAMAAgK3hU2XAAKAgAOAAYKGhCRnwAzAQABNQAECgkJKwAjADsSAA==.',
Jy='Jynnysa:BAAANQAECgEIAgABNQAECgcIHgAjAPMdAA==.',
Ka='Kai:BAAANQAECgMIBQAAAA==.Kairoll:BAABNQAECn8qAAMDAAgKQA3cegClAQADAAgKQA3cegClAQAQAAQKLBEJSgDsAAAAAA==.Kaleìna:BAAANQADCgcICAAAAA==.Kallisto:BAAANQADCgcIBwAAAA==.Karaa:BAAANQAECgIIBQAAAA==.Kariena:BAAANQAECgUIEAAAAA==.Kart:BAAANQADCgEIAQAAAA==.Kashaka:BAAANQADCgcIEgAAAA==.Katesluage:BAABNQAECn8zAAMkAAgKSRqyBgCOAgAkAAgKSRqyBgCOAgAcAAUKMQm3UwEBAQAAAA==.Kawrrl:BAAANQAECgEIAQAAAA==.Kayyaa:BAAANQAECgEIAQAAAA==.',
Ke='Keeya:BAABNQAECn8YAAMKAAcKHgaLfQAiAQAKAAcKHgaLfQAiAQAIAAEKKAK1ugAeAAAAAA==.Kelina:BAAANQADCgIIAgAAAA==.Kendari:BAABNQAECn8dAAMJAAcK6gyUagBGAQAJAAcK5guUagBGAQAIAAQKkAgBegC1AAAAAA==.Kernasas:BAAANQAECgQIEgAAAA==.',
Kh='Khiari:BAAANQADCgUIBQABNQAECgUIDgAHAAAAAA==.',
Ki='Kier:BAAANQAECgEIBAAAAA==.Kizaraan:BAAANQADCgUIBQAAAA==.',
Kl='Kleyntamar:BAAANQAECgMICAAAAA==.',
Kn='Knyghtly:BAAANQAECggIDgAAAA==.',
Ko='Konstantien:BAAANQAECgUIBwAAAA==.Koric:BAAANQAECgcIEAAAAA==.Kourney:BAAANQADCgcIBwABNQAECgkJKwAjADsSAA==.',
Kr='Kretsch:BAAANQADCgUIBQABNQAECgUIDgAHAAAAAA==.Krickket:BAAANQAECgEIAQABNQAECgUIBwAHAAAAAA==.',
Ku='Kupau:BAAANQAECgQICAAAAA==.Kurogami:BAABNQAECn8mAAMKAAgKtRKlVgCzAQAKAAgKzhGlVgCzAQAIAAYKsg/XWAA/AQAAAA==.Kuthixo:BAAANQADCggIKQAAAA==.',
Ky='Kylos:BAAANQABCgQIBgAAAA==.Kynnigos:BAAANQABCgIIAgAAAA==.',
La='Landstrider:BAABNQAECn8cAAITAAkKShQwUQB5AgATAAkKShQwUQB5AgABNQAFFAUICwAZADIMAA==.Lanss:BAABNQAECn8kAAMCAAkKSRmwYgBjAgACAAkKNRmwYgBjAgAEAAQKjx45IgA0AQAAAA==.Larachel:BAAANQAECgUIEAAAAA==.Lastaril:BAAANQADCgYIDwAAAA==.Lastword:BAAANQAECgQIBQAAAA==.Laur:BAABNQAECn8iAAIQAAgKow0cLADCAQAQAAgKow0cLADCAQAAAA==.',
Le='Leipäjuusto:BAAANQAECgcIEgAAAA==.',
Li='Liartes:BAAANQAECgQICAAAAA==.Liderela:BAAANQADCgEIAQAAAA==.Lilipo:BAABNQAECn8WAAIlAAYKFQjxQAAKAQAlAAYKFQjxQAAKAQAAAA==.',
Ll='Llarastrasza:BAAANQAECgIIAgABNQAECgYICQAHAAAAAA==.',
Lo='Logoth:BAAANQAECgQIBAAAAA==.Lohgarak:BAAANQADCggIFQAAAA==.',
Lu='Lunaellana:BAAANQADCgYICAAAAA==.',
Ly='Lystaan:BAAANQABCgQIBAAAAA==.',
['Lü']='Lüvpüp:BAACNQAFFH8FAAISAAMK3RbXCADiAAASAAMK3RbXCADiAAA1AAQKfx4AAhIACQqrIkkFAD0DABIACQqrIkkFAD0DAAAA.',
Ma='Maiku:BAABNQAECn8hAAIFAAgKRxN7agAaAgAFAAgKRxN7agAaAgAAAA==.Majo:BAAANQAECgIIAgAAAA==.Makado:BAABNQAECn8ZAAQiAAkKnAfLDwBOAQAFAAgKGgbOtQBeAQAiAAcKlgfLDwBOAQAdAAEKAADFgwAmAAAAAA==.Maklur:BAAANQAECgQIBAAAAA==.Makoa:BAAANQADCgQIBAAAAA==.Makoroth:BAABNQAECn8cAAIFAAcKshNDjADDAQAFAAcKshNDjADDAQAAAA==.Malanda:BAAANQADCgQIBAAAAA==.Malygosson:BAAANQAECgUIDAAAAA==.Masharu:BAAANQADCgcIBwAAAA==.Matua:BAAANQAECgIIAgAAAA==.Maycee:BAAANQAECgQIDgAAAA==.',
Mc='Mcat:BAAANQAECgMIBQAAAA==.Mcgriddle:BAAANQADCgEIAQAAAA==.Mcnaugh:BAAANQAECgMIBwAAAA==.Mcsaltface:BAAANQAECgMICAAAAA==.',
Me='Meddic:BAAANQAECgUIDwAAAA==.Megavolt:BAAANQAECgQIBAAAAA==.Menarot:BAAANQAECgYIDwAAAA==.Mendais:BAAANQADCgYIDgAAAA==.Meztlitotol:BAAANQAECgcIEgABNQAECgkJKwAEAPQcAA==.',
Mi='Mirosdrigo:BAAANQADCgcIBwAAAA==.Mirosmundo:BAABNQAECn8mAAIGAAkKMh0bCACuAgAGAAkKMh0bCACuAgAAAA==.Mistfit:BAAANQAECggIDwAAAA==.Miyu:BAABNQAECn8nAAMQAAgK7xH7JgDwAQAQAAgK7xH7JgDwAQADAAgKowTkmABFAQAAAA==.',
Mo='Mod:BAABNQAECn8pAAMOAAgK3RnlRABLAgAOAAgK3RnlRABLAgAMAAEKAADdPwEsAAAAAA==.Moeng:BAAANQADCgIIAgAAAA==.Moggatorash:BAAANQAECgUIDwAAAA==.Mogtham:BAABNQAECn8nAAIRAAgKahNpGgDMAQARAAgKahNpGgDMAQAAAA==.Monlaferte:BAAANQAECgUIBQAAAA==.Montsegur:BAAANQADCggICAAAAA==.Mooforn:BAAANQAECgMICAAAAA==.Moonfall:BAAANQAECgUIDQAAAA==.Moosader:BAABNQAECn8VAAMVAAcKmg9XygCBAQAVAAcKmg9XygCBAQAfAAcKOQi5mgBPAQAAAA==.Morellea:BAAANQAECgUJCgAAAA==.Morighann:BAABNQAECn8nAAITAAcKDSEkRgCXAgATAAcKDSEkRgCXAgAAAA==.Moñgoose:BAAANQADCgMIAwAAAA==.',
My='Mynkx:BAAANQAECgUIDgAAAA==.Mythyras:BAABNQAECn8eAAIjAAcK8x3ZEwBkAgAjAAcK8x3ZEwBkAgAAAA==.',
Na='Naeomy:BAABNQAECn8yAAIhAAgKAwhLRACwAQAhAAgKAwhLRACwAQAAAA==.Nahaman:BAAANQAECgMIAwAAAA==.Napolien:BAABNQAECn8rAAMjAAkKOxLnLAByAQAjAAcKOhDnLAByAQAfAAMKrA8y6QCqAAAAAA==.Naugan:BAAANQADCgEIAQAAAA==.',
Ne='Nechahira:BAACNQAFFH8LAAIZAAUKMgxfCABkAQAZAAUKMgxfCABkAQA1AAQKfxcAAhkACApiDUEvAJ0BABkACApiDUEvAJ0BAAAA.Nensho:BAAANQAECgEIAQAAAA==.Nethim:BAAANQAECgIIAwABNQAECgMIBAAHAAAAAA==.Nezana:BAAANQAECgIIAgAAAA==.',
Ni='Nien:BAAANQAECgEIAgAAAA==.Nihlathak:BAAANQAECgYIDgAAAA==.Ninada:BAABNQAECn8aAAMcAAcKbAyEAQGIAQAcAAcK0gqEAQGIAQAkAAIKcgjIQgA8AAAAAA==.Ninalee:BAAANQAECgYIBwAAAA==.',
No='Noranna:BAAANQAECgMICAAAAA==.',
Ny='Nyim:BAAANQAECgEIAQAAAA==.Nymiria:BAAANQABCgEIAQABNQAECgUIBwAHAAAAAA==.Nynsyn:BAAANQAECgQIBgABNQAECgcIHgAjAPMdAA==.Nyxeira:BAAANQAECgYIDwAAAA==.',
['Nâ']='Nâli:BAAANQAECgQIBAAAAA==.',
Ob='Obsidianclaw:BAAANQADCgIIAwAAAA==.',
Oh='Ohthesemyboo:BAAANQAECgIIBQAAAA==.Ohwellz:BAAANQAECgEIAQAAAA==.',
Op='Ophin:BAABNQAECn8nAAIKAAgKqBr6QAAWAgAKAAgKqBr6QAAWAgAAAA==.',
Pa='Panamared:BAABNQAECn8jAAIYAAgKgBVGFgAtAgAYAAgKgBVGFgAtAgAAAA==.Pappawoody:BAABNQAECn8cAAICAAgKCBzdbQBFAgACAAgKCBzdbQBFAgAAAA==.Parishealton:BAAANQADCgcIBwAAAA==.',
Pe='Pellegryn:BAAANQADCgYICQAAAA==.Pennyfeather:BAABNQAECn8lAAMDAAgKWw92bQDRAQADAAgKWw92bQDRAQAQAAQKygkqUQDHAAAAAA==.Pezza:BAABNQAECn8UAAIOAAcKihAJiQBvAQAOAAcKihAJiQBvAQAAAA==.',
Ph='Phaze:BAABNQAECn8jAAImAAcKviFHBAClAgAmAAcKviFHBAClAgAAAA==.Phideauxe:BAAANQAECgQIBgAAAA==.Phorate:BAAANQAECgQICQAAAA==.',
Pl='Pluralbutter:BAABNQAECn8YAAIXAAgK5w/lOwDSAQAXAAgK5w/lOwDSAQAAAA==.',
Po='Popexeo:BAAANQAECgcIDQABNQAFFAcIDgAZADARAA==.',
Pr='Prometheum:BAAANQAECgMIBAAAAA==.',
Ps='Psyvern:BAABNQAECn8ZAAIPAAgK4AcSDgBkAQAPAAgK4AcSDgBkAQAAAA==.',
Qu='Quiccerstorm:BAAANQADCgQIBQAAAA==.',
Ra='Raevennlumis:BAAANQAECgYIEgAAAA==.Raevenns:BAAANQADCggJCAABNQAECgYIEgAHAAAAAA==.Rahkhard:BAABNQAECn8qAAMGAAkK9SBsAwBbAwAGAAkK9SBsAwBbAwAlAAUK/BOyQAAMAQAAAA==.Rascdit:BAAANQAECgUIDAAAAA==.',
Re='Recreant:BAAANQAECgUICgAAAA==.Reiyoso:BAAANQADCggJDgAAAA==.Reui:BAAANQADCgEIAQAAAA==.',
Rh='Rhemibumbum:BAAANQAECgUIDwAAAA==.',
Ro='Rocketbilly:BAAANQAECgEIAQAAAA==.Roobee:BAAANQAECgUIEwAAAA==.',
Ru='Ruaic:BAAANQADCggIEQAAAA==.',
Sa='Sableanne:BAAANQADCgEIAQAAAA==.Sacréd:BAABNQAECn8VAAIjAAYKyBdzKwB9AQAjAAYKyBdzKwB9AQAAAA==.Sarkan:BAAANQADCgcIEAAAAA==.Sarova:BAAANQAECgYIDgAAAA==.Satori:BAAANQAECgMICAAAAA==.',
Sc='Scalewind:BAAANQADCgYIBgAAAA==.',
Se='Seldeath:BAAANQADCgEJAQAAAA==.Selfu:BAABNQAECn8nAAIlAAgKaRUaIgAUAgAlAAgKaRUaIgAUAgAAAA==.Sellidor:BAABNQAECn8nAAITAAgK5SOaFgA/AwATAAgK5SOaFgA/AwAAAA==.Serenesong:BAAANQADCgEIAQAAAA==.Seriniyaa:BAAANQADCggILwAAAA==.Serioth:BAAANQADCgIIAgAAAA==.',
Sh='Sheara:BAAANQAECggIEQAAAA==.Shinjiro:BAABNQAECn8ZAAIVAAcKDQKSSAGkAAAVAAcKDQKSSAGkAAAAAA==.Shirito:BAABNQAECn8uAAMKAAgKWiXnCgBjAwAKAAgKVSXnCgBjAwAIAAgKAiQkCwA9AwAAAA==.Shiritodh:BAABNQAECn8bAAILAAgKfx/7FAC7AgALAAgKfx/7FAC7AgAAAA==.Shockin:BAAANQAECgcIDgAAAA==.Shortnstout:BAACNQAFFH8HAAIjAAIKBR8QCgCmAAAjAAIKBR8QCgCmAAA1AAQKfyMAAyMACQquIkALAOMCACMACQquIkALAOMCABUAAQrIG+OFAUoAAAAA.Shugo:BAAANQAECgUIDAAAAA==.',
Si='Sienje:BAABNQAECn8cAAIVAAgKghdGcgBGAgAVAAgKghdGcgBGAgAAAA==.Sigma:BAABNQAECn8eAAITAAgKLwbNsgCaAQATAAgKLwbNsgCaAQAAAA==.Simpleson:BAABNQAECn8lAAMFAAgKHRyvUQBdAgAFAAcKphyvUQBdAgAdAAEKbhnFaQBMAAAAAA==.Sinbàd:BAACNQAFFH8KAAILAAUKMxT4BgCfAQALAAUKMxT4BgCfAQA1AAQKfysAAgsACQqgGz0VALgCAAsACQqgGz0VALgCAAAA.Sinistris:BAAANQAECgEIAgAAAA==.',
Sk='Skie:BAAANQAECggIDQABNQAECggIDgAHAAAAAA==.Skrabble:BAAANQAECgQICQAAAA==.Skölldraugos:BAAANQAECgEIAwAAAA==.',
Sl='Slaete:BAABNQAECn8UAAIXAAYKEwVhXwD6AAAXAAYKEwVhXwD6AAAAAA==.Slush:BAAANQAECgQIBAAAAA==.',
Sm='Smallz:BAAANQAECgQICQABNQAECgcIGgATAAsYAA==.Smorgas:BAAANQAECgEIAQABNQAECggIGgAVAPkaAA==.Småug:BAAANQADCgMJAwAAAA==.',
So='Solemn:BAABNQAECn8cAAIQAAYKLxc5LQC4AQAQAAYKLxc5LQC4AQABNQAECggIJwATAOUjAA==.Solrana:BAAANQAECgIIBAAAAA==.Songmistress:BAAANQAECgcIDwAAAA==.Sorren:BAAANQAECgEIAQAAAA==.Sotta:BAAANQAECgIIBQAAAA==.Sozin:BAAANQADCgIIAgAAAA==.',
Sp='Speirs:BAAANQAECggIAgAAAA==.Spritmoon:BAAANQADCgYIBgAAAA==.',
Sq='Squeezee:BAAANQAECgEIAQAAAA==.',
St='Stardrive:BAAANQAECgUIEAAAAA==.Stevesteve:BAABNQAECn8VAAIFAAYKMQm4zgAnAQAFAAYKMQm4zgAnAQAAAA==.Stroganov:BAAANQADCgEIAQABNQAECgUIDgAHAAAAAA==.Stumpii:BAAANQADCgIIAgAAAA==.',
Su='Sunasha:BAAANQADCgYIEgAAAA==.Superbautumn:BAAANQAECgMICQAAAA==.',
Sy='Synge:BAAANQAECgUICgAAAA==.Synnyca:BAAANQADCgcJBwABNQAECgcIHgAjAPMdAA==.',
['Sé']='Sélune:BAAANQAECgYICQAAAA==.',
Ta='Tachyon:BAAANQAECgYICQABNQAFFAMIBQASAN0WAA==.Taeonaki:BAAANQAECgQIBAAAAA==.Tagnaras:BAAANQAECgQICQAAAA==.Tahlang:BAAANQAECgEIAgAAAA==.Tali:BAAANQAECgMIBgAAAA==.Taliasluage:BAAANQADCggICAABNQAECggIMwAkAEkaAA==.Tangle:BAABNQAECn8aAAMZAAcKZhf4JwDcAQAZAAcKZhf4JwDcAQABAAUKxQUufwDNAAABNQAECggIDgAHAAAAAA==.Tanka:BAABNQAECn8gAAICAAgKrBw/WgB6AgACAAgKrBw/WgB6AgAAAA==.Tannisse:BAAANQADCgcIFAAAAA==.Tanuki:BAAANQAECgEIAQAAAA==.Tapol:BAAANQAECgUIBwAAAA==.Tashlaraz:BAEANQAECgEIBgAAAA==.Tasi:BAAANQAECgQIBQAAAA==.Taurannosaur:BAAANQAECgEIAQAAAA==.Taurentots:BAAANQAFFAMIAwAAAA==.',
Te='Telkas:BAAANQADCgUIBQAAAA==.Temporantus:BAAANQAECgEIAwAAAA==.Tenko:BAABNQAECn8eAAMcAAcKQApeAAGKAQAcAAcKVAleAAGKAQAkAAIKdAw6NQBkAAAAAA==.',
Th='Thaddeus:BAAANQAECgQICQAAAA==.Therm:BAACNQAFFH8QAAIVAAYKJByzBQD5AQAVAAYKJByzBQD5AQA1AAQKfzkAAxUACQrLJpEBAPgDABUACQrLJpEBAPgDAB8AAQrQBx8cATYAAAAA.Thoramier:BAAANQAECgYIDQAAAA==.',
Ti='Tibble:BAAANQAECgQICAAAAA==.Timoonja:BAAANQAECgUIDQAAAA==.Tirazlea:BAAANQADCgIIAgAAAA==.',
To='Tonatuih:BAABNQAECn8nAAIXAAkKQxtvFQDuAgAXAAkKQxtvFQDuAgAAAA==.',
Tr='Trezzia:BAABNQAECn8VAAIiAAgKShS7BgA6AgAiAAgKShS7BgA6AgAAAA==.Triipod:BAAANQADCgYIFQAAAA==.Trinkat:BAAANQAECgMIBwAAAA==.Trojinn:BAAANQAECgUIBgAAAA==.Tryst:BAAANQADCgYIBgAAAA==.Tráson:BAAANQADCgYIBQAAAA==.',
Tu='Tub:BAAANQAECggIEAAAAA==.',
Ty='Tychlora:BAAANQAECgEIAgABNQAECgkJKwAEAPQcAA==.Tylean:BAAANQAECgIIAgAAAA==.',
['Tì']='Tìríon:BAAANQAECgEIAQAAAA==.',
Ud='Udukai:BAAANQAECgQIBAAAAA==.',
Ul='Ultrastealth:BAAANQAECgUIEQAAAA==.',
Um='Umbrum:BAAANQAECgEIAQABNQAECgkJKwAEAPQcAA==.',
Uu='Uu:BAAANQAECgMIBwAAAA==.',
Va='Vadrozsa:BAAANQADCggIKgAAAA==.Vallarie:BAAANQADCgQJBAAAAA==.Vareyn:BAAANQAECgMIBAAAAA==.',
Vo='Vorth:BAABNQAECn8nAAIIAAgKfhNaOQDoAQAIAAgKfhNaOQDoAQAAAA==.Vorukh:BAAANQADCgQIBAABNQAECgIIBQAHAAAAAA==.Vorúkh:BAAANQAECgMIBQABNQAECgIIBQAHAAAAAA==.Vorükh:BAAANQAECgUIBQABNQAECgIIBQAHAAAAAA==.',
Vu='Vulturous:BAAANQADCgYICgAAAA==.',
Vy='Vydian:BAAANQADCgYICQAAAA==.',
Wa='Waldir:BAABNQAECn8lAAMfAAgKgSOmEwA0AwAfAAgKgSOmEwA0AwAVAAIKIAfagAFRAAAAAA==.Walock:BAAANQAECgEIAQAAAA==.Wanted:BAAANQADCgYIBgAAAA==.Watz:BAAANQADCgYIDAAAAA==.',
We='Wensa:BAAANQADCgcIBwAAAA==.',
Wh='Wholesale:BAABNQAECn8nAAIJAAcKRRiWQgDvAQAJAAcKRRiWQgDvAQAAAA==.',
Wo='Wonders:BAAANQAECgEIAgAAAA==.',
Wr='Wrack:BAAANQADCggIEQAAAA==.Wraithian:BAAANQAECgEIAQAAAA==.Wratsoul:BAABNQAECn8VAAIFAAkKuwtzfADrAQAFAAkKuwtzfADrAQAAAA==.',
Xe='Xessala:BAABNQAECn8eAAIOAAgK9RaKTwAjAgAOAAgK9RaKTwAjAgAAAA==.',
Xh='Xheero:BAABNQAECn8sAAITAAkKGB0FJAAFAwATAAkKGB0FJAAFAwAAAA==.Xheerom:BAAANQADCgUIBQAAAA==.',
Ya='Yagiashi:BAAANQAECgQIBQABNQAECgkJKwAEAPQcAA==.',
Yu='Yulica:BAAANQAECgMICAAAAA==.',
Za='Zaffy:BAABNQAECn8jAAIdAAgKFw3GFQC+AQAdAAgKFw3GFQC+AQAAAA==.Zaktrix:BAAANQAECgEIAwAAAA==.Zaleron:BAAANQADCggIFAAAAA==.Zaruba:BAABNQAECn8iAAIMAAgKIwiOhACVAQAMAAgKIwiOhACVAQABNQAECggIIQABAP0JAA==.Zatkyng:BAABNQAECn8bAAIlAAgKfQ4eMQCKAQAlAAgKfQ4eMQCKAQAAAA==.',
Ze='Zekos:BAAANQAECgEIAQAAAA==.',
Zi='Zillver:BAAANQAECgUIBQABNQAECgkJKwAjADsSAA==.Zimdalar:BAAANQAECgUIDQAAAA==.',
Zu='Zulre:BAABNQAECn8nAAIJAAgK9h4KGwDUAgAJAAgK9h4KGwDUAgAAAA==.',
['Ôv']='Ôverkill:BAABNQAECn8UAAIRAAcKMxfLFgD5AQARAAcKMxfLFgD5AQAAAA==.',
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
