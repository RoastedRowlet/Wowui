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

local lookup = {'Druid-Balance','Mage-Arcane','DeathKnight-Unholy','Warrior-Arms','DemonHunter-Devourer','Priest-Holy','Warrior-Protection','Shaman-Restoration','Warlock-Demonology','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Paladin-Protection','Unknown-Unknown','Mage-Fire','Priest-Shadow','Shaman-Elemental','Monk-Mistweaver','Monk-Brewmaster','Evoker-Augmentation','Rogue-Assassination','Druid-Guardian','Evoker-Devastation','Druid-Feral','Druid-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Havoc','Rogue-Subtlety','Evoker-Preservation','Warlock-Destruction','Monk-Windwalker','Priest-Discipline','Warrior-Fury','Mage-Frost','Warlock-Affliction','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Ackrenoth:BAAANQAECgUIBQAAAA==.',
Ad='Adynn:BAABNQAECn9MAAIBAAoK0CXoBACyAwABAAoK0CXoBACyAwAAAA==.',
Ae='Aelarlador:BAAANQAECgcIBwABNQAECgoKPwACAN8VAA==.Aermoss:BAAANQABCgUIBQAAAA==.Aeru:BAAANQADCgYIBgAAAA==.Aethreal:BAAANQAFFAEIAQAAAA==.',
Af='Afraid:BAAANQAECggIBAAAAA==.Afridium:BAAANQADCgEIAQAAAA==.',
Ai='Aiselraith:BAAANQAECgUIBQAAAA==.',
Ak='Akikusa:BAAANQADCggICgAAAA==.',
Al='Alarine:BAAANQAECgEIAQABNQAECgYIGgADALsPAA==.Alderath:BAAANQABCgQJBQAAAA==.Alista:BAABNQAECn9GAAIEAAoK7yRNCgCjAwAEAAoK7yRNCgCjAwAAAA==.Allyeska:BAAANQADCgcIDQAAAA==.Alnharaelune:BAAANQADCgYIDQAAAA==.',
Am='Amarea:BAAANQAECgIIAgAAAA==.Amor:BAABNQAECn8nAAIFAAcKQBnvKgDqAQAFAAcKQBnvKgDqAQAAAA==.',
An='Anali:BAABNQAECn8WAAIGAAkKVRMtSwBEAgAGAAkKVRMtSwBEAgAAAA==.Anani:BAAANQAECgUIBQAAAA==.Angreifer:BAABNQAECn88AAMHAAoKCh3BBgD2AgAHAAoKCh3BBgD2AgAEAAIKvAP9PgFVAAAAAA==.Anoana:BAAANQADCgQIBAAAAA==.Anori:BAABNQAECn8lAAIBAAkKPgwYNABVAQABAAkKPgwYNABVAQAAAA==.',
Ao='Aonar:BAABNQAECn8YAAIIAAYKzhHtdAA+AQAIAAYKzhHtdAA+AQAAAA==.',
Aq='Aqua:BAAANQAECgIIBQAAAA==.',
Ar='Arc:BAABNQAECn8sAAIJAAoKMx+YHQCTAgAJAAoKMx+YHQCTAgAAAA==.Arcanimous:BAAANQADCggIDAAAAA==.Archenteron:BAAANQAECgQIBgAAAA==.Archnunin:BAAANQAECggICAAAAA==.Ardorcinder:BAAANQAECgQIDAAAAA==.Argentur:BAAANQADCgEIAQAAAA==.Arkaan:BAAANQADCgUIBQABNQAECgoKKAAIAMsaAA==.Armangaria:BAAANQAECggICAAAAA==.Arrohon:BAAANQAECgcIEAAAAA==.Arrozz:BAAANQADCgQIBAAAAA==.Arthmanafel:BAABNQAECn8xAAQKAAoKVxo/KQBPAgAKAAoKphk/KQBPAgALAAEKqR9btQBeAAADAAEKJQu54gAxAAAAAA==.',
As='Asbjorne:BAABNQAECn8WAAIMAAcKoRZITgDHAQAMAAcKoRZITgDHAQAAAA==.',
At='Atryssa:BAAANQAECgUIBQAAAA==.Attycys:BAAANQAECgEIAQABNQAECgkJLwANAHwbAA==.',
Au='Audi:BAAANQADCgMIAwAAAA==.Aurianne:BAAANQAECgYIDwABNQAECgcIEQAOAAAAAA==.Autumnmoon:BAABNQAECn8dAAIPAAcK6xBYBAAjAQAPAAcK6xBYBAAjAQAAAA==.',
Av='Avalsong:BAABNQAECn9JAAIFAAoK2x5KDgAEAwAFAAoK2x5KDgAEAwAAAA==.Avelos:BAACNQAFFH8KAAIGAAUK3QzAEwBXAQAGAAUK3QzAEwBXAQA1AAQKfzQAAwYACgqmHnAjAOACAAYACgqmHnAjAOACABAAAQrtCsZhAC4AAAAA.',
Ay='Ayowenn:BAAANQADCgIIAgAAAA==.Ayzmist:BAABNQAECn8qAAIRAAgKPQlNbQApAQARAAgKPQlNbQApAQAAAA==.Ayzmyth:BAABNQAECn85AAMSAAoKrBF6EwC2AQASAAoKrBF6EwC2AQATAAUKJwQ4IgDIAAAAAA==.',
Az='Azurelight:BAAANQADCgMIAwAAAA==.',
Ba='Banthapooduu:BAAANQADCggIIAAAAA==.',
Be='Beasic:BAABNQAECn8+AAMRAAoK/QaEcAAgAQARAAkK+gSEcAAgAQAIAAMKkgKV1ABeAAAAAA==.Beastmode:BAAANQAECgUIDAAAAA==.Beletili:BAABNQAECn82AAIGAAoKBhI0ZADzAQAGAAoKBhI0ZADzAQAAAA==.Bellissimio:BAAANQADCgUICAABNQAECgoKLwAIAIMQAA==.Bener:BAAANQADCgcIBwAAAA==.Beátrix:BAAANQAECgEIAQAAAA==.',
Bi='Birdman:BAAANQAECgYIBgAAAA==.Bismuth:BAAANQAECgMIBQAAAA==.',
Bl='Blackraven:BAAANQAECggIEgAAAA==.Blatendrg:BAABNQAECn9AAAIUAAoK+RJhCAARAgAUAAoK+RJhCAARAgAAAA==.Blindcloud:BAAANQAECgcICwAAAA==.',
Bo='Boot:BAABNQAECn8fAAIMAAYK8hXGbQBYAQAMAAYK8hXGbQBYAQAAAA==.Borodemonin:BAEBNQAECn8rAAIFAAkKVyb1AgCrAwAFAAkKVyb1AgCrAwAAAA==.',
Br='Breae:BAABNQAECn8+AAMGAAoK7BRwSQD9AQAGAAoK7BRwSQD9AQAQAAYKFgkXPgCkAAAAAA==.Brieanna:BAAANQADCgUIBgAAAA==.Bristia:BAAANQAECgUIBwAAAA==.Brueggar:BAAANQAECgEIAgAAAA==.Brutyl:BAAANQAECgEIAQABNQAECggIFgAVAB8aAA==.',
Bu='Bulky:BAAANQAECgIIAgAAAA==.',
By='Byegone:BAAANQAECgQIDgAAAA==.',
Ca='Cadforus:BAAANQADCgcIEAABNQAECgkJHgAWAM4WAA==.Cafë:BAAANQADCgcICgABNQAFFAQICQAXAN0WAA==.Caicee:BAAANQADCgQIBAAAAA==.Caistin:BAAANQADCgYIDgAAAA==.Calyma:BAAANQAECgIIBAAAAA==.Camelsotters:BAABNQAECn8XAAUYAAUKEAdHMQCJAAAYAAQKnQVHMQCJAAAWAAUK7wVBSgCCAAAZAAQKwQK/WwByAAABAAIKWQGmugAmAAAAAA==.Casca:BAAANQAECgUICwAAAA==.Catsclaw:BAAANQADCgYICgAAAA==.',
Ce='Cenjeru:BAABNQAECn8eAAMKAAgKfhdHPADdAQAKAAgKHRVHPADdAQADAAYKnBclZwB1AQAAAA==.',
Ch='Chathvia:BAAANQADCgQIBAAAAA==.Chezzie:BAAANQAECgYICwAAAA==.Chiot:BAABNQAECn8vAAIHAAoKphz5CQCnAgAHAAoKphz5CQCnAgAAAA==.',
Ci='Cimerian:BAAANQAECgIIBAAAAA==.',
Cl='Clone:BAAANQADCgYIBgAAAA==.Cloudysky:BAAANQAECgYIBwAAAA==.',
Co='Cobalticus:BAAANQAECgUICwAAAA==.Coffee:BAAANQADCgEIAQABNQADCgMIAwAOAAAAAA==.Coledarus:BAAANQAECgUIBgAAAA==.Concealer:BAAANQADCgEIAQAAAA==.Conejamala:BAABNQAECn80AAMaAAoK5R4fFgBDAwAaAAoK5R4fFgBDAwAbAAMKUw6PXwCoAAAAAA==.Corange:BAAANQABCgIIBAAAAA==.Cordini:BAAANQAECgQIEwAAAA==.Corlink:BAAANQADCgEIAQAAAA==.Corlock:BAAANQAECgIIAgAAAA==.Cormech:BAAANQAECgUICAAAAA==.Cornite:BAAANQAECggICQAAAA==.Cotolete:BAAANQABCgcICQAAAA==.',
Cr='Crizzo:BAABNQAECn86AAIaAAoKWxxXLACBAgAaAAoKWxxXLACBAgAAAA==.',
Da='Daddyslilgrl:BAAANQAECgMIBQAAAA==.Dakra:BAEBNQAECn8hAAIEAAoK8hR8VgDoAQAEAAoK8hR8VgDoAQAAAA==.Dalamar:BAAANQAECggIIwABNQAFFAIIBwAQAO4UAQ==.Dalandis:BAABNQAECn88AAMcAAoKGSD1KACyAgAcAAkK2CL1KACyAgAMAAcKsxf6QwDxAQAAAA==.Dalyeth:BAABNQAECn8rAAMdAAoKCyWGBAD8AgAdAAoKCyWGBAD8AgAeAAEKAAAumwAoAAAAAA==.Darianno:BAAANQADCgMIAwAAAA==.Darkwingorc:BAABNQAECn9DAAIaAAoKJyJfIQASAwAaAAoKJyJfIQASAwAAAA==.Darkwulf:BAAANQAECgUICwAAAA==.Daunt:BAAANQAECgUIBgABNQAECgkJMgABAOIKAA==.Dawnfire:BAAANQADCgEIAQAAAA==.Dawnmane:BAAANQADCgEIAQAAAA==.',
De='Deadsecsi:BAAANQABCgEIAQAAAA==.Decypher:BAAANQAECgYICgABNQAECgoKPwAfAJcUAA==.Deebz:BAABNQAECn8kAAIZAAoKsxJvKQDTAQAZAAoKsxJvKQDTAQAAAA==.Deliverance:BAACNQAFFH8HAAIQAAIK7hRSDgCeAAAQAAIK7hRSDgCeAAA1AAQKfzsAAhAACgroHJ0RAOMCABAACgroHJ0RAOMCAAAA.Demigoth:BAABNQAECn8hAAIgAAcKJROcIgC0AQAgAAcKJROcIgC0AQAAAA==.Denethmon:BAAANQAECgEJAQABNQAECgYIDwAOAAAAAA==.Dentik:BAABNQAECn9AAAMZAAgKHBK1JQCnAQAZAAgKHBK1JQCnAQAYAAYKZQwKHgAsAQAAAA==.Denuma:BAAANQAECgMIAwAAAA==.Devilina:BAAANQADCggICgAAAA==.Deàdpool:BAAANQADCgQIBgABNQAECgoKNQAJADEbAA==.',
Dh='Dheriana:BAABNQAECn8/AAIfAAoKlxSrFQA2AgAfAAoKlxSrFQA2AgAAAA==.Dherisis:BAAANQAECgMIAwABNQAECgoKPwAfAJcUAA==.Dherli:BAAANQAECgMIBAABNQAECgoKPwAfAJcUAA==.',
Di='Diamair:BAABNQAECn8sAAICAAoKlgx8egCkAQACAAoKlgx8egCkAQAAAA==.Disney:BAAANQAECggICgAAAA==.Divynelle:BAAANQABCgIIAgAAAA==.Dixiee:BAABNQAECn8jAAIGAAcKfAu3kwAHAQAGAAcKfAu3kwAHAQAAAA==.',
Dn='Dnegelpal:BAABNQAECn8tAAIcAAgKQQ+NwAA8AQAcAAgKQQ+NwAA8AQAAAA==.',
Do='Dodgecharger:BAABNQAECn8XAAIIAAcKYgtWgQAZAQAIAAcKYgtWgQAZAQAAAA==.',
Dr='Dragerin:BAAANQAECgMIAwAAAA==.Dragonfood:BAAANQAECgMIBAAAAA==.Drakilu:BAABNQAECn8/AAIaAAoKORnWNwBbAgAaAAoKORnWNwBbAgAAAA==.Drakra:BAEANQAECgYICgABNQAECgoKIQAEAPIUAA==.Drasic:BAABNQAECn9TAAIZAAoKQSFkCQAvAwAZAAoKQSFkCQAvAwAAAA==.Dreamcloud:BAAANQADCgYICAAAAA==.Dreddscott:BAAANQAECgYIBgABNQAECgoKLgAfAE8UAA==.Dretro:BAAANQAECgIIBQAAAA==.Drisla:BAAANQADCgMIAwAAAA==.Drovosi:BAAANQADCggIIgAAAA==.',
Du='Durin:BAABNQAECn8tAAIEAAkKvwksjABVAQAEAAkKvwksjABVAQAAAA==.Durward:BAABNQAECn8hAAMDAAkKIxTiNwAqAQALAAcKQBBpWgCJAQADAAcKexTiNwAqAQAAAA==.Duvo:BAABNQAECn8yAAIaAAkKURd1bwAzAgAaAAkKURd1bwAzAgAAAA==.',
Dw='Dwarvey:BAAANQADCggIDgAAAA==.',
['Dæ']='Dæmôna:BAAANQADCgQIBQAAAA==.',
['Dé']='Détank:BAABNQAECn80AAIKAAgKhhsmMwATAgAKAAgKhhsmMwATAgAAAA==.',
Ea='Easyname:BAABNQAECn89AAIcAAoK/hxjNACEAgAcAAoK/hxjNACEAgAAAA==.',
Ei='Eiene:BAAANQAECgUICQAAAA==.Eithetala:BAAANQADCgYICAAAAA==.',
El='Elemental:BAAANQAFFAEIAQABNQAFFAcIEQAZAM4LAA==.Ellohir:BAAANQAECgEIBgAAAA==.Ellomental:BAAANQAECgEIAgAAAA==.Elloseth:BAABNQAECn8ZAAMQAAkK0hXBHACVAQAQAAgKARTBHACVAQAGAAMK9wgU0gBqAAAAAA==.Elmorin:BAAANQAECgQICAAAAA==.Eluneh:BAAANQADCgYICAAAAA==.',
Eo='Eolon:BAABNQAECn8bAAIaAAcKLxF8owBQAQAaAAcKLxF8owBQAQAAAA==.',
Ep='Epica:BAABNQAECn85AAICAAoKhxCjYwDeAQACAAoKhxCjYwDeAQAAAA==.',
Er='Eragonhawk:BAAANQAECgQIDwAAAA==.Eraina:BAAANQAECgYICQAAAA==.Eroldan:BAAANQADCgYICQAAAA==.Erovianoria:BAAANQAECgcIEQAAAA==.',
Es='Essun:BAABNQAECn8eAAIeAAkKrBmOJwBhAgAeAAkKrBmOJwBhAgABNQAFFAUICQAJAC8HAA==.',
Ev='Evanthe:BAABNQAECn8vAAMIAAoKgxCFYADtAQAIAAoKgxCFYADtAQARAAEKAADSWwEeAAAAAA==.',
Ex='Expire:BAAANQADCgEIAQAAAA==.',
Ez='Ezro:BAAANQADCgYICAAAAA==.',
Fa='Faizor:BAAANQAECgQICAAAAA==.Fastal:BAAANQADCgcIFwAAAA==.Fatalfury:BAAANQAECggIBwAAAA==.Fauxborn:BAABNQAECn8ZAAIGAAcKWSDLNABXAgAGAAcKWSDLNABXAgAAAA==.Fauxstorm:BAAANQADCgQIBQAAAA==.',
Fe='Fedwell:BAABNQAECn8gAAIcAAgKpgvX0wB0AQAcAAgKpgvX0wB0AQAAAA==.',
Fi='Finluc:BAAANQAECggIEAAAAA==.Finngan:BAABNQAECn8vAAIhAAkKawtbCQAfAQAhAAkKawtbCQAfAQAAAA==.Fitoria:BAAANQAECgMICAABNQAECgoKLAAJADMfAA==.',
Fo='Forestkin:BAABNQAECn8WAAIWAAcKGxaZKQAmAQAWAAcKGxaZKQAmAQABNQAECgoKKwAdAAslAA==.Foxhope:BAABNQAECn8eAAIXAAYKlRF+HgBrAQAXAAYKlRF+HgBrAQAAAA==.',
Fr='Friartuk:BAAANQAECgEIAQAAAA==.Frozenthunda:BAABNQAECn89AAICAAoKHgzIbwC/AQACAAoKHgzIbwC/AQAAAA==.',
Fu='Furfu:BAABNQAECn9CAAMTAAoKnSB2AwBaAwATAAoKnSB2AwBaAwAiAAkKLBo7GgDCAQAAAA==.Furna:BAABNQAECn8tAAIjAAkKUg01BgB5AQAjAAkKUg01BgB5AQAAAA==.Fuzzyhooves:BAABNQAECn8yAAMMAAoKASQEEwA5AwAMAAoKASQEEwA5AwAcAAEK0wdrpgE0AAAAAA==.',
Ga='Gabrael:BAACNQAFFH8IAAMEAAMKegnLHgC1AAAEAAMKWQbLHgC1AAAkAAEKoA9XBABCAAA1AAQKfzcAAyQACgoBEl8NAOEBACQACQr9EF8NAOEBAAQACQqhDjytAKwBAAAA.',
Gh='Ghorienge:BAAANQAECgYIDQAAAA==.',
Gi='Gilox:BAABNQAECn8iAAIVAAgKAA+GGwBBAQAVAAgKAA+GGwBBAQAAAA==.',
Gl='Glossu:BAAANQAECgIIAgAAAA==.',
Gn='Gndmexia:BAAANQAECgcICwAAAA==.Gneiss:BAAANQAECgQIBgAAAA==.',
Go='Goldenarrow:BAAANQABCgYIDgAAAA==.Gorgilz:BAAANQADCgMICQAAAA==.Gothgirldemi:BAABNQAECn81AAIZAAkK6SBODgDtAgAZAAkK6SBODgDtAgAAAA==.',
Gr='Graymon:BAABNQAECn8aAAIkAAYKgRGVFwDsAAAkAAYKgRGVFwDsAAAAAA==.Greebo:BAABNQAECn8YAAIWAAYKSAO/TQB0AAAWAAYKSAO/TQB0AAAAAA==.Gremsmasha:BAAANQADCggIAQAAAA==.Grist:BAAANQAECgMIAwAAAA==.',
Gu='Guatalupe:BAAANQADCgYIBgAAAA==.Guilherme:BAAANQADCggIEAAAAA==.',
Gw='Gwenyver:BAAANQAECgYIDwAAAA==.',
Ha='Hailthanatos:BAABNQAECn8bAAIeAAkKLwtIPQDOAQAeAAkKLwtIPQDOAQAAAA==.Hamord:BAABNQAECn8WAAINAAcKqgacNwC/AAANAAcKqgacNwC/AAAAAA==.Hansdelbruk:BAAANQADCggIEQAAAA==.Hardlight:BAABNQAECn8UAAIcAAgK1wqYpABvAQAcAAgK1wqYpABvAQAAAA==.Harliquette:BAABNQAECn8qAAIQAAoKWhENGgC0AQAQAAoKWhENGgC0AQAAAA==.Harliqynn:BAAANQAECgYIDwAAAA==.Harlock:BAABNQAECn8sAAMfAAoKhBboGgAAAgAfAAoK+hToGgAAAgAVAAcKtA9FRgCtAQAAAA==.Hashen:BAAANQAECgQIBwAAAA==.Hazelnuts:BAAANQADCgUIBQAAAA==.',
Hi='Hiten:BAABNQAECn81AAIfAAoKKQkCJACoAQAfAAoKKQkCJACoAQAAAA==.',
Ho='Hoofinmouth:BAAANQAECgMIAwAAAA==.Hoosh:BAABNQAECn8VAAMaAAgKyRKkegCrAQAaAAcKyRKkegCrAQAbAAUK9QXTRAB7AAAAAA==.Hopedaimond:BAABNQAECn8hAAMRAAgKSwo2aQA0AQARAAgKSwo2aQA0AQAIAAEKaAE6NwEYAAAAAA==.',
Hu='Huntertattoo:BAABNQAECn8iAAIaAAoKsQlsfgCiAQAaAAoKsQlsfgCiAQAAAA==.Husgus:BAAANQADCgYIDAABNQAFFAIIAgAOAAAAAA==.Huungron:BAAANQADCgYIDAAAAA==.',
Ic='Icynips:BAAANQADCgQIBAAAAA==.',
Il='Illianarra:BAAANQAECgUIDgAAAA==.Ilthad:BAABNQAECn8iAAIeAAcKhQ3oOABIAQAeAAcKhQ3oOABIAQAAAA==.',
Im='Imaplantnow:BAAANQAECggICAAAAA==.Imastealnow:BAAANQAECgIIBAAAAA==.Imawarrionow:BAAANQADCgIIAgAAAA==.Imora:BAAANQADCgMIAwAAAA==.Imshalar:BAAANQABCgIIAgABNQAECgQIBAAOAAAAAA==.',
In='Infurryating:BAAANQAECggIEwAAAA==.',
Ir='Iroar:BAAANQADCgIIAgAAAA==.Irumble:BAAANQAECgEIAQAAAA==.',
Is='Ischadè:BAAANQADCgUIBgAAAA==.Iskuros:BAAANQAECgMICgAAAA==.',
It='Itsirk:BAABNQAECn8aAAIMAAgKxRS1SQDaAQAMAAgKxRS1SQDaAQAAAA==.',
Iz='Izyebelle:BAABNQAECn8YAAIQAAgKdwKNQwCKAAAQAAgKdwKNQwCKAAAAAA==.',
Ja='Jadevine:BAAANQADCgEIAQAAAA==.Jalynfein:BAABNQAECn8iAAIlAAoKLwm7DgCIAQAlAAoKLwm7DgCIAQAAAA==.Janar:BAAANQADCgYIBwAAAA==.',
Je='Jefeorganico:BAABNQAECn8bAAQmAAcKRwiYFAABAQAmAAUKggmYFAABAQAhAAUK4QTjRwCoAAAJAAQKgQTFJAF3AAAAAA==.Jeloi:BAAANQAECgQIDQAAAA==.Jenkshi:BAAANQADCgcIDQAAAA==.',
Ji='Jimmydin:BAACNQAFFH8IAAMMAAMKKB5sFQDWAAAMAAMKKB5sFQDWAAAcAAIKJwzUIgCEAAA1AAQKfzIAAwwACgomHVQhAOgCAAwACgomHVQhAOgCABwACgopGDJ8ADICAAAA.',
Ju='Juego:BAAANQADCgQIBAAAAA==.Julkan:BAAANQAECgQIBwAAAA==.Junhoong:BAABNQAECn8+AAIcAAoKnRGadADRAQAcAAoKnRGadADRAQAAAA==.Juvia:BAABNQAECn8pAAMRAAkKdxZnXQAJAgARAAgK3hVnXQAJAgAIAAgKRg5NoQAzAQABNQAECgkJOAANADwQAA==.',
Jy='Jynnysa:BAAANQAECgEIAgABNQAECgkJLwANAHwbAA==.',
Ka='Kai:BAAANQAECgYIEAAAAA==.Kairoll:BAABNQAECn83AAMGAAkKnBDJcQBuAQAGAAkKnBDJcQBuAQAQAAQKLBHXSgDsAAAAAA==.Kaleìna:BAAANQADCgcICAAAAA==.Kallisto:BAAANQAECgIIAgAAAA==.Karaa:BAAANQAECgUIBwAAAA==.Kariena:BAABNQAECn8oAAIaAAkKfQ18hACUAQAaAAkKfQ18hACUAQAAAA==.Kart:BAAANQADCgEIAQAAAA==.Kashaka:BAAANQADCgcIEgAAAA==.Katesluage:BAABNQAECn9MAAMlAAkK5hrMBgCOAgAlAAkK5hrMBgCOAgACAAUKMQmwVgEBAQAAAA==.Kayyaa:BAAANQADCggICAAAAA==.',
Ke='Keeya:BAABNQAECn8vAAMDAAgKoAtwOAAnAQADAAgKoAtwOAAnAQAKAAEKKAJ9vgAeAAAAAA==.Kelina:BAAANQADCgIIAgAAAA==.Kendari:BAABNQAECn8lAAMLAAgKkQzpUQDnAAALAAgKuQvpUQDnAAAKAAQKkAiUfAC1AAAAAA==.Kernasas:BAABNQAECn8jAAIhAAgKmQyHCwD1AAAhAAgKmQyHCwD1AAAAAA==.',
Kh='Khiari:BAAANQADCgUIBQABNQAECgoKMgAcAFkYAA==.',
Ki='Kier:BAAANQAECgMICAAAAA==.Kizaraan:BAAANQADCgUIBQAAAA==.',
Kl='Kleyntamar:BAABNQAECn8XAAIZAAYKoBl+JQCpAQAZAAYKoBl+JQCpAQAAAA==.',
Kn='Knyghtly:BAAANQAECggIDgABNQAECgkJKAAZAFAYAA==.',
Ko='Konstantien:BAAANQAECgUIBQAAAA==.Koric:BAABNQAECn8jAAMMAAoKhwyNSgDWAQAMAAoKhwyNSgDWAQAcAAcKnhJq3wAIAQAAAA==.Kourney:BAAANQADCgcIBwABNQAECgkJOAANADwQAA==.',
Kr='Kretsch:BAAANQADCgUIBQABNQAECggIFAAJAMMKAA==.Krickket:BAAANQAECgEIAQABNQAECgcIIwAGAHwLAA==.',
Ku='Kupau:BAAANQAECgQICAAAAA==.Kurogami:BAABNQAECn87AAMDAAoKOhF/VwCzAQADAAoKGBF/VwCzAQAKAAkKkQ1BQwB2AQAAAA==.Kuthixo:BAAANQAECgQICQAAAA==.',
Ky='Kylos:BAAANQABCgQIBgAAAA==.Kynnigos:BAAANQABCgIIAgAAAA==.',
La='Landstrider:BAACNQAFFH8HAAIaAAQKVAT1FwDAAAAaAAQKVAT1FwDAAAA1AAQKfy8AAhoACgqlGZ5SAHgCABoACgqlGZ5SAHgCAAE1AAUUBwgRABkAzgsA.Lanss:BAABNQAECn9AAAQEAAoK/x5mKwCFAgAEAAoKiR5mKwCFAgAHAAQKjx61IgA0AQAkAAMKKB85FQAOAQAAAA==.Larachel:BAABNQAECn8eAAIGAAkKTBw+PwAnAgAGAAkKTBw+PwAnAgAAAA==.Lastaril:BAAANQADCgYIDwAAAA==.Lastword:BAAANQAECgYIDgABNQAECgcIEQAOAAAAAA==.Laur:BAABNQAECn80AAIQAAoKEg2qGgCtAQAQAAoKEg2qGgCtAQAAAA==.',
Le='Leipäjuusto:BAABNQAECn8fAAIcAAgKYBC8uABKAQAcAAgKYBC8uABKAQAAAA==.',
Li='Liartes:BAABNQAECn8XAAINAAYK8hmxKQAPAQANAAYK8hmxKQAPAQAAAA==.Liderela:BAAANQADCgEIAQAAAA==.Lilipo:BAABNQAECn80AAIiAAkKEgiKKgAtAQAiAAkKEgiKKgAtAQAAAA==.',
Ll='Llarastrasza:BAAANQAECgIIAgABNQAECggIDAAOAAAAAA==.',
Lo='Logoth:BAAANQAECgQIBAAAAA==.Lohgarak:BAAANQADCggIFQAAAA==.',
Lu='Lunaellana:BAAANQADCgYICAAAAA==.',
Ly='Lystaan:BAAANQABCgQIBAAAAA==.',
['Lü']='Lüvpüp:BAACNQAFFH8JAAIXAAQK3RakAwC/AAAXAAQK3RakAwC/AAA1AAQKfx4AAhcACQqrImIFAD0DABcACQqrImIFAD0DAAAA.',
Ma='Magicfang:BAAANQADCgUICQAAAA==.Maiku:BAABNQAECn8qAAIJAAoKtxEgbAAZAgAJAAoKtxEgbAAZAgAAAA==.Majo:BAAANQAECgIIAgAAAA==.Makado:BAABNQAECn8hAAQmAAoK7Af3DwBOAQAJAAkKrQYKuABeAQAmAAcKlgf3DwBOAQAhAAEKAAB0hAAmAAAAAA==.Makaris:BAAANQAECgQIBAAAAA==.Maklur:BAAANQAECgYIEAAAAA==.Makoa:BAAANQADCgQIBAAAAA==.Makoroth:BAABNQAECn8wAAIJAAoK1RMpQwD6AQAJAAoK1RMpQwD6AQAAAA==.Malanda:BAAANQADCgQIBAAAAA==.Malygosson:BAAANQAECgUICgAAAA==.Masharu:BAAANQADCgcIBwAAAA==.Matua:BAAANQAECgIIAwAAAA==.Maycee:BAABNQAECn8eAAIaAAgKwwlNnQBdAQAaAAgKwwlNnQBdAQAAAA==.',
Mc='Mcat:BAAANQAECgYIEQAAAA==.Mcgriddle:BAAANQADCgEIAQAAAA==.Mcnaugh:BAAANQAECgUIDAAAAA==.Mcsaltface:BAABNQAECn8VAAIcAAcKtxLDzgAkAQAcAAcKtxLDzgAkAQAAAA==.',
Me='Meddic:BAABNQAECn8hAAMGAAcKbAIqrwDBAAAGAAcKbAIqrwDBAAAQAAIKQQDhjgAcAAAAAA==.Megaux:BAAANQAECgQIBAAAAA==.Megavolt:BAABNQAECn8ZAAIIAAoKsQ+oOAAgAgAIAAoKsQ+oOAAgAgAAAA==.Menarot:BAAANQAECgcIEQAAAA==.Mendais:BAAANQADCgYIDgAAAA==.Messia:BAAANQADCgEIAQAAAA==.Meztlitotol:BAABNQAECn8YAAMWAAcKhCCQDQCNAgAWAAcKhCCQDQCNAgAYAAEKAACQQAA5AAABNQAECgoKPAAHAAodAA==.',
Mi='Mirosdrigo:BAAANQADCgcIBwAAAA==.Mirosmundo:BAACNQAFFH8MAAITAAUKzQ8rBQDHAAATAAUKzQ8rBQDHAAA1AAQKfzIAAhMACgooHDAIAK0CABMACgooHDAIAK0CAAAA.Mistfit:BAABNQAECn8bAAISAAkKyQy1GQBPAQASAAkKyQy1GQBPAQAAAA==.Miyu:BAABNQAECn9AAAMQAAoKJBRiJwDwAQAQAAkKlxFiJwDwAQAGAAoKXwbybgB3AQAAAA==.',
Mo='Mod:BAABNQAECn83AAMIAAkK1BvFRQBKAgAIAAkK1BvFRQBKAgARAAEKAABJRAEsAAAAAA==.Moeng:BAAANQADCgIIAgAAAA==.Moggatorash:BAABNQAECn8eAAMIAAkKnAPCowDDAAAIAAkKnAPCowDDAAARAAMKfQFNIAFQAAAAAA==.Mogtham:BAABNQAECn8/AAIWAAoK6hXsEwDmAQAWAAoK6hXsEwDmAQAAAA==.Moisticklez:BAAANQAECgYIBgAAAA==.Monlaferte:BAABNQAECn8ZAAINAAkKgBk8EAARAgANAAkKgBk8EAARAgAAAA==.Montsegur:BAAANQADCggICAAAAA==.Mooforn:BAABNQAECn8aAAQDAAYKuw+vSgDMAAAKAAYKogryagDZAAADAAYKrw2vSgDMAAALAAEKBxNFmgA2AAAAAA==.Moonfall:BAABNQAECn8bAAIFAAYKHhJ2PwBPAQAFAAYKHhJ2PwBPAQAAAA==.Moosader:BAABNQAECn8VAAMcAAcKmg91zQCBAQAcAAcKmg91zQCBAQAMAAcKOQganABPAQAAAA==.Morellea:BAAANQAECgUJCgAAAA==.Morighann:BAABNQAECn82AAIaAAoKdCHTNQBhAgAaAAoKdCHTNQBhAgAAAA==.Moñgoose:BAAANQADCgMIAwAAAA==.',
My='Mynkx:BAABNQAECn8yAAIcAAoKWRilTQAyAgAcAAoKWRilTQAyAgAAAA==.Mythyras:BAABNQAECn8vAAMNAAkKfBsdFABkAgANAAkKWhsdFABkAgAcAAEK5hOWdAFCAAAAAA==.',
Na='Naeomy:BAABNQAECn8/AAIVAAoKHQiRGQBQAQAVAAoKHQiRGQBQAQAAAA==.Nahaman:BAAANQAECgUIEAAAAA==.Napolien:BAABNQAECn84AAMNAAkKPBB7LQBxAQANAAgKPBB7LQBxAQAMAAMKrA8D7ACpAAAAAA==.Naugan:BAAANQADCgEIAQAAAA==.',
Ne='Nechahira:BAACNQAFFH8RAAIZAAcKzgt3BgB9AQAZAAcKzgt3BgB9AQA1AAQKfyQAAxkACgrDFccUAGcCABkACgrDFccUAGcCABYAAQoAANeHAAAAAAAA.Nensho:BAAANQAECgEIAQAAAA==.Nethim:BAAANQAECgYIDwAAAA==.Nezana:BAAANQAECgIIAgAAAA==.',
Ni='Nien:BAAANQAECgIIBwABNQAECgMIAwAOAAAAAA==.Nightfallen:BAAANQAECgQIBwAAAA==.Nihlathak:BAAANQAECgYIDAAAAA==.Ninada:BAABNQAECn8hAAMCAAoK1gporwAzAQACAAoK1glorwAzAQAlAAIKcgifQwA8AAAAAA==.Ninalee:BAAANQAECgYIDQAAAA==.Ninefallen:BAAANQAECgMIBQAAAA==.',
No='Noranna:BAABNQAECn8aAAIaAAYKXQj36gDAAAAaAAYKXQj36gDAAAAAAA==.',
Ny='Nyim:BAAANQAECgEIAQAAAA==.Nymiria:BAAANQABCgEIAQABNQAECgcIIwAGAHwLAA==.Nynsyn:BAABNQAECn8YAAMTAAgK/Br2CQCSAQATAAcKih72CQCSAQAiAAEKNgkKWgAyAAABNQAECgkJLwANAHwbAA==.Nyxeira:BAAANQAECgYICwAAAA==.',
['Nâ']='Nâli:BAAANQAECgQIBAAAAA==.',
Ob='Obsidianclaw:BAAANQADCgIIAwAAAA==.',
Oh='Ohthesemyboo:BAAANQAECgQIEQAAAA==.Ohwellz:BAAANQAECgEIAQAAAA==.',
Ol='Olehei:BAAANQAECgEIAwAAAA==.',
Op='Ophin:BAABNQAECn9EAAIDAAoKqRtYDgCJAgADAAoKqRtYDgCJAgAAAA==.',
Or='Ornaxxi:BAAANQAECgIIAgAAAA==.',
Pa='Panamared:BAABNQAECn8uAAIfAAoKTxSLFgAtAgAfAAoKTxSLFgAtAgAAAA==.Pappawoody:BAABNQAECn8cAAIEAAgKCBxkbwBFAgAEAAgKCBxkbwBFAgAAAA==.Parishealton:BAAANQADCgcIBwAAAA==.',
Pe='Pellegryn:BAAANQADCgYICQAAAA==.Pennyfeather:BAABNQAECn9AAAMGAAoKiRBQUQDeAQAGAAoKiRBQUQDeAQAQAAQKygkUUgDHAAAAAA==.Pezza:BAABNQAECn8eAAIIAAkKJRAnZQBvAQAIAAkKJRAnZQBvAQAAAA==.',
Ph='Phaze:BAABNQAECn8wAAInAAgKZyBPBACkAgAnAAgKZyBPBACkAgAAAA==.Phideauxe:BAAANQAECgQIBQAAAA==.Phorate:BAAANQAECgcIEQAAAA==.',
Pl='Pluralbutter:BAABNQAECn8bAAIeAAoKqA2iPADSAQAeAAoKqA2iPADSAQAAAA==.',
Po='Popexeo:BAAANQAECgcIDQABNQAFFAcIEAAZAGwRAA==.',
Pr='Prometheum:BAAANQAECgcIEAAAAA==.',
Ps='Psyvern:BAABNQAECn8uAAIUAAoK9ge0CgBEAQAUAAoK9ge0CgBEAQAAAA==.',
Qt='Qtkat:BAAANQADCgMIAwABNQAECgYIEgAOAAAAAA==.',
Qu='Quiccerstorm:BAAANQADCgQIBQAAAA==.',
Ra='Raevennlumis:BAABNQAECn8ZAAIcAAkK1ggp5gBPAQAcAAkK1ggp5gBPAQAAAA==.Raevenns:BAAANQADCggJCAABNQAECgkJGQAcANYIAA==.Rascdit:BAAANQAECgUICgAAAA==.',
Re='Recreant:BAAANQAECggIEgAAAA==.Reiyoso:BAAANQAECgIIBAAAAA==.Reui:BAAANQAECgIIAgAAAA==.',
Rh='Rhemibumbum:BAAANQAECgUICwAAAA==.',
Ro='Roberey:BAAANQAECgUIDAAAAA==.Rocketbilly:BAAANQADCgIIAgAAAA==.Roobee:BAABNQAECn8nAAIhAAkK0gMXFACuAAAhAAkK0gMXFACuAAAAAA==.',
Ru='Ruaic:BAAANQAECgEIAQAAAA==.',
Sa='Sableanne:BAAANQAECgMIBgAAAA==.Sacréd:BAABNQAECn8ZAAINAAcKCxcSLAB8AQANAAcKCxcSLAB8AQAAAA==.Sarkan:BAAANQADCggIEQAAAA==.Sarova:BAABNQAECn8jAAIaAAoKfhbfbgDIAQAaAAoKfhbfbgDIAQAAAA==.Satori:BAABNQAECn8ZAAISAAYKIxiTFQCPAQASAAYKIxiTFQCPAQAAAA==.',
Sc='Scalewind:BAAANQADCgYIBgAAAA==.',
Se='Seldeath:BAAANQADCgEJAQAAAA==.Selfu:BAABNQAECn83AAIiAAoKzhYDFQAFAgAiAAoKzhYDFQAFAgAAAA==.Sellidor:BAABNQAECn9DAAIaAAoKviSVCwApAwAaAAoKviSVCwApAwAAAA==.Serenesong:BAAANQAECgMIAwAAAA==.Seriniyaa:BAAANQAECgQICQAAAA==.Serioth:BAAANQADCgIIAgAAAA==.',
Sh='Sheara:BAAANQAECggIEgAAAA==.Shinjiro:BAABNQAECn8lAAIcAAgKAQJhTQGkAAAcAAgKAQJhTQGkAAAAAA==.Shirito:BAABNQAECn9EAAMDAAkKgSQCCwBjAwADAAgKVSUCCwBjAwAKAAkK6yNhCwA9AwAAAA==.Shiritodh:BAABNQAECn8lAAIFAAkKcCBRFQC6AgAFAAkKcCBRFQC6AgAAAA==.Shockin:BAAANQAECgcIDAAAAA==.Shortnstout:BAACNQAFFH8PAAINAAUKfxfGAwAiAQANAAUKfxfGAwAiAQA1AAQKfzAAAw0ACgpfImgLAOICAA0ACgpfImgLAOICABwABwqjG4e5AEgBAAAA.Shugo:BAABNQAECn8gAAInAAYKUQx4CgBuAQAnAAYKUQx4CgBuAQAAAA==.',
Si='Sienje:BAABNQAECn8rAAIcAAoKoxVgdABFAgAcAAoKoxVgdABFAgAAAA==.Sigma:BAABNQAECn8qAAIaAAoKagfvkgBzAQAaAAoKagfvkgBzAQAAAA==.Simpleson:BAABNQAECn89AAMJAAoKch7MKABdAgAJAAkKKR/MKABdAgAhAAEKbhlnagBMAAAAAA==.Sinbàd:BAACNQAFFH8KAAIFAAUKMxQPBwCeAQAFAAUKMxQPBwCeAQA1AAQKfzwAAgUACgo6IaILAIwCAAUACgo6IaILAIwCAAAA.Sinbád:BAAANQAFFAIIAgABNQAFFAUICgAFADMUAA==.Sinistris:BAAANQAECgUIBwAAAA==.',
Sk='Skie:BAABNQAECn8YAAMgAAgKVQ2yHgAHAQAgAAcKLg+yHgAHAQAXAAYKrgW/FwCuAAABNQAECgkJKAAZAFAYAA==.Skrabble:BAABNQAECn8XAAICAAYKXwRiBAGdAAACAAYKXwRiBAGdAAAAAA==.Skölldraugos:BAAANQAECgEIAQAAAA==.',
Sl='Slaete:BAABNQAECn8gAAIeAAcKMgXlVQC3AAAeAAcKMgXlVQC3AAAAAA==.Slush:BAAANQAECgQIBAAAAA==.',
Sm='Smallz:BAABNQAECn8gAAMGAAcKsxzePAAyAgAGAAcKsxzePAAyAgAjAAEKWxSiJgA8AAABNQAECgkJMgAaAFEXAA==.Smorgas:BAAANQAECgQIDQABNQAECgoKPAAcABkgAA==.Småug:BAAANQADCgMIAwAAAA==.',
So='Solemn:BAABNQAECn89AAIQAAoKExg7DwBSAgAQAAoKExg7DwBSAgABNQAECgoKQwAaAL4kAA==.Solrana:BAAANQAECgUIDAAAAA==.Songmistress:BAABNQAECn8ZAAIJAAkK5AVexwA7AQAJAAkK5AVexwA7AQAAAA==.Sorren:BAAANQAECgUIBQAAAA==.Sotta:BAAANQAECgIIBgAAAA==.Sozin:BAAANQADCgIIAgAAAA==.',
Sp='Speirs:BAAANQAECggIAQAAAA==.Spritmoon:BAAANQADCgYIBgAAAA==.',
Sq='Squeezee:BAAANQADCggICAAAAA==.',
St='Stardrive:BAABNQAECn8oAAIIAAoKyxqdHADAAgAIAAoKyxqdHADAAgAAAA==.Stevesteve:BAABNQAECn81AAIJAAkKCA9XTQDZAQAJAAkKCA9XTQDZAQAAAA==.Stroganov:BAABNQAECn8UAAIJAAgKwwq+gQBHAQAJAAgKwwq+gQBHAQAAAA==.Stumpii:BAAANQADCgQIBAAAAA==.',
Su='Sunasha:BAAANQADCgYIEgAAAA==.Superbautumn:BAABNQAECn8lAAIcAAoKbxcCWQATAgAcAAoKbxcCWQATAgAAAA==.',
Sy='Synge:BAABNQAECn8kAAMCAAcKFw4ruAAjAQACAAcKFw4ruAAjAQAlAAEK9AfLSgAwAAAAAA==.Synnyca:BAAANQAECgUIBwABNQAECgkJLwANAHwbAA==.',
['Sé']='Sélune:BAAANQAECggIDAAAAA==.',
['Sï']='Sïnbad:BAAANQAFFAIIAgABNQAFFAUICgAFADMUAA==.',
Ta='Tachyon:BAAANQAECgYICAABNQAFFAQICQAXAN0WAA==.Taeonaki:BAAANQAECgMICgAAAA==.Tagnaras:BAAANQAECgcIDgAAAA==.Tagnaris:BAAANQAECgUIBQAAAA==.Tahlang:BAAANQAECgEIAQAAAA==.Tali:BAAANQAECgYIEgAAAA==.Taliasluage:BAAANQADCggICAABNQAECgkJTAAlAOYaAA==.Tangle:BAABNQAECn8oAAMZAAkKUBhXKADdAQAZAAcKCRlXKADdAQABAAcKfAaiYwCGAAAAAA==.Tanka:BAABNQAECn8vAAIEAAoKqh12SgAPAgAEAAoKqh12SgAPAgAAAA==.Tannisse:BAAANQADCggIFQAAAA==.Tanuki:BAAANQAECgUIBQAAAA==.Tapol:BAABNQAECn8UAAMGAAYKog26jAAbAQAGAAYKog26jAAbAQAQAAMKBAIhbwBLAAABNQAECgcIIwAGAHwLAA==.Tashlaraz:BAEANQAECgUIEAAAAA==.Tasi:BAAANQAECgQIBAAAAA==.Taurannosaur:BAAANQADCggIDAAAAA==.Taurentots:BAABNQAFFH8OAAILAAYKZRKqDQALAQALAAYKZRKqDQALAQAAAA==.',
Te='Telkas:BAAANQAECgUICgAAAA==.Temporantus:BAAANQAECgUIBwAAAA==.Tenko:BAABNQAECn8/AAMCAAoK9wk2dgCvAQACAAoKZAk2dgCvAQAlAAIKdAzaNQBkAAAAAA==.',
Th='Thaddeus:BAABNQAECn8YAAIRAAgKuw0zaAA2AQARAAgKuw0zaAA2AQAAAA==.Therm:BAACNQAFFH8QAAIcAAYKJBzgBQD4AQAcAAYKJBzgBQD4AQA1AAQKf2IAAxwACgrxJoQAAJwDABwACgrxJoQAAJwDAAwAAQrQBwQgATYAAAAA.Thoramier:BAAANQAECgYIEwAAAA==.',
Ti='Tibble:BAABNQAECn8UAAIHAAcKbwL9KwCNAAAHAAcKbwL9KwCNAAAAAA==.Timoonja:BAABNQAECn8YAAIDAAYKyQ0TSgDPAAADAAYKyQ0TSgDPAAAAAA==.Tirazlea:BAAANQADCgIIAgAAAA==.',
To='Tonatuih:BAABNQAECn9MAAIeAAoKMSCzDgCuAgAeAAoKMSCzDgCuAgAAAA==.',
Tr='Treeandra:BAAANQAECgQIBAAAAA==.Trezzia:BAABNQAECn8kAAImAAkK6BTLBgA6AgAmAAkK6BTLBgA6AgAAAA==.Triipod:BAAANQADCgYIIwAAAA==.Trinkat:BAAANQAECgYIEgAAAA==.Trojinn:BAAANQAECgUIBQAAAA==.Tryst:BAAANQADCgYIBgAAAA==.Tráson:BAAANQADCgYIBQAAAA==.',
Tu='Tub:BAABNQAECn8lAAICAAgKnQlorAA5AQACAAgKnQlorAA5AQAAAA==.',
Ty='Tychlora:BAAANQAECgEIAgABNQAECgoKPAAHAAodAA==.Tylean:BAAANQAECgUIEAAAAA==.',
['Tì']='Tìríon:BAAANQABCgEIAQAAAA==.',
Ud='Udukai:BAAANQAECgQIBAAAAA==.',
Ul='Ultrastealth:BAABNQAECn8ZAAQfAAUK6ga9PADSAAAfAAUKAAa9PADSAAAVAAQKdgRTkQBtAAAoAAIKtgNEDAAnAAAAAA==.',
Um='Umbrum:BAAANQADCgIIAgABNQAECgoKPAAHAAodAA==.',
Uu='Uu:BAABNQAECn8cAAIEAAkKxyOiCABHAwAEAAkKxyOiCABHAwAAAA==.',
Va='Vadrozsa:BAAANQAECgQICQAAAA==.Vallarie:BAAANQADCgQJBAAAAA==.Vareyn:BAAANQAECgYICgAAAA==.',
Vo='Vorth:BAABNQAECn9AAAIKAAoKmxQRKQD/AQAKAAoKmxQRKQD/AQAAAA==.Vorukh:BAAANQADCgQIBAABNQAECgcICwAOAAAAAA==.Vorúkh:BAABNQAECn8XAAQBAAkKtQtxSADsAAABAAcKBQpxSADsAAAWAAUKcglmTQB2AAAYAAEK6Q5LSAAsAAABNQAECgcICwAOAAAAAA==.Vorükh:BAAANQAECgYIBwABNQAECgcICwAOAAAAAA==.',
Vu='Vulturous:BAAANQADCgYICgAAAA==.',
Vy='Vydian:BAAANQADCgYICQAAAA==.Vyrlana:BAAANQAECgEIAgAAAA==.',
Wa='Waldir:BAABNQAECn89AAMMAAoKAiRRBgCvAwAMAAoKAiRRBgCvAwAcAAMKkAoPUgFoAAAAAA==.Walock:BAAANQADCgMIAwAAAA==.Wanted:BAAANQADCgYIBgAAAA==.Watz:BAABNQAECn8hAAIaAAoK7gs/XQD2AQAaAAoK7gs/XQD2AQAAAA==.',
We='Wensa:BAAANQAECgYIBwAAAA==.',
Wh='Wholesale:BAABNQAECn82AAILAAgK7BZNQwDuAQALAAgK7BZNQwDuAQAAAA==.',
Wo='Wonders:BAAANQAECgEIAQAAAA==.Worldeater:BAAANQAECgIIAgAAAA==.',
Wr='Wrack:BAAANQADCggIEgAAAA==.Wraithian:BAAANQABCgQIBAAAAA==.Wratsoul:BAABNQAECn8mAAIJAAoKNg5ifgDqAQAJAAoKNg5ifgDqAQAAAA==.',
Wu='Wudan:BAAANQAECgEIAQAAAA==.',
Xe='Xessala:BAABNQAECn8rAAIIAAkKfRaUUAAjAgAIAAkKfRaUUAAjAgAAAA==.',
Xh='Xheero:BAABNQAECn86AAIaAAkK5x2bJAAEAwAaAAkK5x2bJAAEAwAAAA==.Xheerom:BAAANQADCgUIBQAAAA==.',
Ya='Yagiashi:BAAANQAECgUICwABNQAECgoKPAAHAAodAA==.',
Yu='Yulica:BAABNQAECn8ZAAIlAAYKDww5JwC5AAAlAAYKDww5JwC5AAAAAA==.Yunamaesh:BAAANQAECgYIBgAAAA==.',
Za='Zaffy:BAABNQAECn80AAIhAAkKpg9ABgBoAQAhAAkKpg9ABgBoAQAAAA==.Zaktrix:BAAANQAECgIIAwAAAA==.Zaleron:BAAANQADCggIFAAAAA==.Zaruba:BAABNQAECn81AAMRAAoKjwgBWABoAQARAAoKjwgBWABoAQAIAAEKsAHsCAEYAAABNQAECgkJMgABAOIKAA==.Zatkyng:BAABNQAECn8pAAIiAAoK1A80IwBpAQAiAAoK1A80IwBpAQAAAA==.',
Ze='Zekos:BAAANQAECgEIAQAAAA==.',
Zi='Zillver:BAAANQAECgUIBQABNQAECgkJOAANADwQAA==.Zimdalar:BAABNQAECn8iAAITAAYKbBfPFQCFAQATAAYKbBfPFQCFAQAAAA==.',
Zo='Zomi:BAAANQABCgMIAwAAAA==.',
Zu='Zulre:BAABNQAECn8+AAMLAAoK5htkGwDUAgALAAoK5htkGwDUAgAKAAUKnw3HbQDQAAAAAA==.',
Zy='Zynnayde:BAAANQAECgQIBgABNQAECgkJLwANAHwbAA==.',
['Ôv']='Ôverkill:BAABNQAECn8eAAIWAAkKzhZDFwD5AQAWAAkKzhZDFwD5AQAAAA==.',
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
