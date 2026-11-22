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

local lookup = {'Druid-Balance','Mage-Arcane','DeathKnight-Frost','Warrior-Arms','DemonHunter-Devourer','Priest-Holy','Warrior-Protection','Shaman-Restoration','Warlock-Demonology','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Holy','Paladin-Protection','Unknown-Unknown','Mage-Fire','Priest-Shadow','Shaman-Elemental','Monk-Mistweaver','Monk-Brewmaster','Hunter-BeastMastery','Evoker-Augmentation','Druid-Guardian','Evoker-Devastation','Druid-Feral','Druid-Restoration','Hunter-Marksmanship','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Havoc','Rogue-Subtlety','Evoker-Preservation','Warlock-Destruction','Monk-Windwalker','Priest-Discipline','Warrior-Fury','Rogue-Assassination','Mage-Frost','Warlock-Affliction','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Ackrenoth:BAAANQAECgUIBQAAAA==.',
Ad='Adynn:BAABNQAECn9UAAIBAAoK4iWpAwBWAwABAAoK4iWpAwBWAwAAAA==.',
Ae='Aelarlador:BAAANQAECgcIDQABNQAECgoKPwACAN8VAA==.Aermoss:BAAANQABCgUIBQAAAA==.Aeru:BAAANQADCgYIBgAAAA==.Aethreal:BAAANQAFFAEIAQAAAA==.',
Af='Afraid:BAAANQAECggIAQAAAA==.Afridium:BAAANQADCgEIAQAAAA==.',
Ai='Aiselraith:BAAANQAECgUIBQAAAA==.',
Ak='Akikusa:BAAANQADCggICgAAAA==.',
Al='Alarine:BAAANQABCgQIBAABNQAECgcIIQADABoQAA==.Alderath:BAAANQABCgQJBQAAAA==.Alista:BAABNQAECn9JAAIEAAoK7yRNCgCjAwAEAAoK7yRNCgCjAwAAAA==.Allyeska:BAAANQADCgcIDQAAAA==.Alnharaelune:BAAANQADCgYIDQAAAA==.',
Am='Amarea:BAAANQAECgIIAgAAAA==.Amor:BAABNQAECn8pAAIFAAcKQBnvKgDqAQAFAAcKQBnvKgDqAQAAAA==.',
An='Anali:BAABNQAECn8WAAIGAAkKVRMtSwBEAgAGAAkKVRMtSwBEAgAAAA==.Anani:BAAANQAECgYIBQAAAA==.Angreifer:BAABNQAECn88AAMHAAoKCh3BBgD2AgAHAAoKCh3BBgD2AgAEAAIKvAP9PgFVAAAAAA==.Anoana:BAAANQADCgQIBAAAAA==.Anori:BAABNQAECn8lAAIBAAkKPgwPOABUAQABAAkKPgwPOABUAQAAAA==.Anowyyn:BAAANQAECgIIAgAAAA==.',
Ao='Aonar:BAABNQAECn8fAAIIAAcK7RAZcABjAQAIAAcK7RAZcABjAQAAAA==.',
Aq='Aqua:BAAANQADCgEIAQAAAA==.',
Ar='Arc:BAABNQAECn8sAAIJAAoKMx/wIQCKAgAJAAoKMx/wIQCKAgAAAA==.Arcanimous:BAAANQADCggIDAAAAA==.Archenteron:BAAANQAECgQIBQAAAA==.Archnunin:BAAANQAECggICAAAAA==.Ardorcinder:BAAANQAECgQIDAAAAA==.Argentur:BAAANQADCgEIAQAAAA==.Arkaan:BAAANQADCgUIBQABNQAECgoKKAAIAMsaAA==.Armangaria:BAAANQAECggICAAAAA==.Arrohon:BAAANQAECgcIDgAAAA==.Arrozz:BAAANQADCgQIBAAAAA==.Artea:BAAANQAECgIIAgAAAA==.Arthmanafel:BAABNQAECn8xAAQDAAoKVxo/KQBPAgADAAoKphk/KQBPAgAKAAEKqR9btQBeAAALAAEKJQu54gAxAAAAAA==.',
As='Asbjorne:BAABNQAECn8cAAIMAAcK7hcnUQDQAQAMAAcK7hcnUQDQAQAAAA==.',
At='Atryssa:BAAANQAECgUIBQAAAA==.Attycys:BAAANQAECgQIBAABNQAECgoKNQANAL8bAA==.',
Au='Audi:BAAANQADCgMIAwAAAA==.Aunalea:BAAANQAECgEIAQAAAA==.Aurianne:BAAANQAECgYIDAABNQAECgcIDgAOAAAAAA==.Autumnmoon:BAABNQAECn8dAAIPAAcK6xDmBAAjAQAPAAcK6xDmBAAjAQAAAA==.',
Av='Avalsong:BAABNQAECn9JAAIFAAoK2x5KDgAEAwAFAAoK2x5KDgAEAwAAAA==.Avelos:BAACNQAFFH8KAAIGAAUK3QybFgBPAQAGAAUK3QybFgBPAQA1AAQKfzkAAwYACgqmHnAjAOACAAYACgqmHnAjAOACABAAAQrtCtJnAC4AAAAA.',
Ay='Ayowenn:BAAANQADCgIIAgAAAA==.Ayzmist:BAABNQAECn8vAAIRAAgK7AkKdAAuAQARAAgK7AkKdAAuAQAAAA==.Ayzmyth:BAABNQAECn9BAAMSAAoKlhTmDwAYAgASAAoKlhTmDwAYAgATAAUKJwQ4IgDIAAAAAA==.',
Az='Azurelight:BAAANQADCgMIAwAAAA==.',
Ba='Banthapooduu:BAAANQADCggIIAAAAA==.',
Be='Beasic:BAABNQAECn8+AAMRAAoK/QbDeQAgAQARAAkK+gTDeQAgAQAIAAMKkgIY3QBeAAAAAA==.Beastmode:BAAANQAECgUICgAAAA==.Beletili:BAABNQAECn82AAIGAAoKBhI0ZADzAQAGAAoKBhI0ZADzAQAAAA==.Bellissimio:BAAANQAECgUIBQABNQAECgoKLwAIAIMQAA==.Bener:BAAANQADCgcIBwAAAA==.Beátrix:BAAANQAECgMIAwAAAA==.',
Bi='Birdman:BAAANQAECgYIBgAAAA==.Bismuth:BAAANQAECgMIBQAAAA==.',
Bl='Blackraven:BAABNQAECn8dAAIUAAkKmBEMTgAyAgAUAAkKmBEMTgAyAgAAAA==.Blatendrg:BAABNQAECn9AAAIVAAoK+RJhCAARAgAVAAoK+RJhCAARAgAAAA==.Blindcloud:BAAANQAECgcICgAAAA==.',
Bo='Boot:BAABNQAECn8lAAIMAAcK3hNOaQB6AQAMAAcK3hNOaQB6AQAAAA==.Borodemonin:BAEBNQAECn8rAAIFAAkKVyb1AgCrAwAFAAkKVyb1AgCrAwAAAA==.',
Br='Breae:BAABNQAECn9CAAMGAAoKYRYaQgAxAgAGAAoKYRYaQgAxAgAQAAYKFglrQgCkAAAAAA==.Brieanna:BAAANQADCgUIBgAAAA==.Bristia:BAAANQAECgUIBwAAAA==.Brueggar:BAAANQAECgUIBwAAAA==.Brutyl:BAAANQAECgEIAQABNQAECggIEQAOAAAAAA==.',
Bu='Bulky:BAAANQAECgIIAgAAAA==.',
By='Byegone:BAAANQAECgQIDgAAAA==.',
Ca='Cadforus:BAAANQADCgcIEAABNQAECgoKHwAWABAWAA==.Cafë:BAAANQADCgcICgABNQAFFAQICQAXAN0WAA==.Caicee:BAAANQADCgQIBAAAAA==.Caistin:BAAANQADCgYIDgAAAA==.Calyma:BAAANQAECgMIBQAAAA==.Camelsotters:BAABNQAECn8XAAUYAAUKEAdHMQCJAAAYAAQKnQVHMQCJAAAWAAUK7wVBSgCCAAAZAAQKwQIyYQByAAABAAIKWQGmugAmAAAAAA==.Casca:BAAANQAECgUICwAAAA==.Catsclaw:BAAANQADCgYICgAAAA==.',
Ce='Cenjeru:BAABNQAECn8eAAMDAAgKfhdHPADdAQADAAgKHRVHPADdAQALAAYKnBclZwB1AQAAAA==.',
Ch='Chathvia:BAAANQADCgQIBAAAAA==.Chezzie:BAAANQAECgYICwAAAA==.Chiot:BAABNQAECn8zAAIHAAoK1hz5CQCnAgAHAAoK1hz5CQCnAgAAAA==.',
Ci='Cimerian:BAAANQAECgIIBAAAAA==.',
Cl='Clone:BAAANQADCgYIBgAAAA==.Cloudysky:BAAANQAECgYICgAAAA==.',
Co='Cobalticus:BAAANQAECgUICQAAAA==.Coffee:BAAANQADCgEIAQABNQADCgMIAwAOAAAAAA==.Coledarus:BAAANQAECgUIBQAAAA==.Concealer:BAAANQADCgEIAQAAAA==.Conejamala:BAABNQAECn81AAMUAAoK5R4fFgBDAwAUAAoK5R4fFgBDAwAaAAMKUw6PXwCoAAAAAA==.Corange:BAAANQABCgIIBAAAAA==.Cordini:BAAANQAECgQIDwAAAA==.Corlink:BAAANQADCgEIAQAAAA==.Corlock:BAAANQAECgIIAgAAAA==.Cormech:BAAANQAECgUICAAAAA==.Cornite:BAAANQAECggICQAAAA==.Cotolete:BAAANQADCgUIBQAAAA==.',
Cr='Crizzo:BAABNQAECn8+AAIUAAoK5x1/LQCMAgAUAAoK5x1/LQCMAgAAAA==.',
Da='Daddyslilgrl:BAAANQAECgMIBQAAAA==.Dakra:BAEBNQAECn8kAAIEAAoK9xYhTAAbAgAEAAoK9xYhTAAbAgAAAA==.Dalamar:BAAANQAECggIJAABNQAFFAMICAAQAO4UAQ==.Dalandis:BAABNQAECn9AAAMbAAoKIiCQLACvAgAbAAkK4iKQLACvAgAMAAcKsxeOSgDpAQAAAA==.Dalyeth:BAABNQAECn8vAAMcAAoKPiWGBAD8AgAcAAoKPiWGBAD8AgAdAAEKAAAumwAoAAAAAA==.Darianno:BAAANQADCgMIAwAAAA==.Darkwingorc:BAABNQAECn9EAAIUAAoKJyJfIQASAwAUAAoKJyJfIQASAwAAAA==.Darkwulf:BAAANQAECgcIEAAAAA==.Daunt:BAAANQAECgUIBQABNQAECgkJNAABAOIKAA==.Dawnfire:BAAANQADCgEIAQAAAA==.Dawnmane:BAAANQADCgEIAQAAAA==.',
De='Deadsecsi:BAAANQABCgEIAQAAAA==.Decypher:BAAANQAECgUICgABNQAECgoKRwAeAMsUAA==.Deebz:BAABNQAECn8sAAIZAAoKVBbHGgA2AgAZAAoKVBbHGgA2AgAAAA==.Deliverance:BAACNQAFFH8IAAIQAAMK7hT1DwCeAAAQAAMK7hT1DwCeAAA1AAQKfzsAAhAACgroHJ0RAOMCABAACgroHJ0RAOMCAAAA.Demigoth:BAABNQAECn8hAAIfAAcKJROcIgC0AQAfAAcKJROcIgC0AQAAAA==.Denethmon:BAAANQAECgEJAQABNQAECgcIFgAMAFkKAA==.Dentik:BAABNQAECn9GAAMZAAgKSRTuJQDDAQAZAAgKSRTuJQDDAQAYAAYKZQwKHgAsAQAAAA==.Denuma:BAAANQAECgQIBAAAAA==.Devilina:BAAANQADCggICgAAAA==.Deàdpool:BAAANQADCgQIBgABNQAECgoKNQAJADEbAA==.',
Dh='Dheriana:BAABNQAECn9HAAIeAAoKyxR4OQAWAgAeAAoKyxR4OQAWAgAAAA==.Dherisis:BAAANQAECgMIAwABNQAECgoKRwAeAMsUAA==.Dherli:BAAANQAECgMIBAABNQAECgoKRwAeAMsUAA==.',
Di='Diamair:BAABNQAECn8wAAICAAoKNQ37fACxAQACAAoKNQ37fACxAQAAAA==.Diokhan:BAAANQAECgEIAQABNQAECgoKPAACAK8QAA==.Disney:BAAANQAECggICAAAAA==.Divynelle:BAAANQABCgIIAgAAAA==.Dixiee:BAABNQAECn8jAAIGAAcKfAt8nQAEAQAGAAcKfAt8nQAEAQAAAA==.',
Dn='Dnegelpal:BAABNQAECn8tAAIbAAgKQQ/RzgA5AQAbAAgKQQ/RzgA5AQAAAA==.',
Do='Dodgecharger:BAABNQAECn8bAAIIAAcKsAw1gQAwAQAIAAcKsAw1gQAwAQAAAA==.',
Dr='Dragerin:BAAANQAECgMIAwAAAA==.Dragonfood:BAAANQAECgMIBAAAAA==.Drakilu:BAABNQAECn9DAAIUAAoKZBkMOgBlAgAUAAoKZBkMOgBlAgAAAA==.Drakra:BAEANQAECgcICgABNQAECgoKJAAEAPcWAA==.Drasic:BAABNQAECn9bAAIZAAoKNCLWCABJAwAZAAoKNCLWCABJAwAAAA==.Dreamcloud:BAAANQADCgYICAAAAA==.Dreddscott:BAAANQAECgYIBgABNQAECgoKMQAeAE8UAA==.Dretro:BAAANQAECgIIBgAAAA==.Drisla:BAAANQADCgMIAwAAAA==.Drovosi:BAAANQADCggIIgAAAA==.',
Du='Durin:BAABNQAECn8tAAIEAAkKvwlvlgBTAQAEAAkKvwlvlgBTAQAAAA==.Durward:BAABNQAECn8iAAMLAAkKIxQ4OwApAQAKAAcKQBBpWgCJAQALAAcKexQ4OwApAQAAAA==.Duvo:BAABNQAECn84AAIUAAoKRhZ1bwAzAgAUAAoKRhZ1bwAzAgAAAA==.',
Dw='Dwarvey:BAAANQADCggIDgAAAA==.',
['Dæ']='Dæmôna:BAAANQADCgQIBQAAAA==.',
['Dé']='Détank:BAABNQAECn80AAIDAAgKhhsmMwATAgADAAgKhhsmMwATAgAAAA==.',
Ea='Easyname:BAABNQAECn9EAAIbAAoK/hx8OgB9AgAbAAoK/hx8OgB9AgAAAA==.',
Ei='Eiene:BAAANQAECgUICQAAAA==.Eithetala:BAAANQADCgYICAAAAA==.',
El='Elemental:BAAANQAFFAEIAQABNQAFFAcIEQAZAM4LAA==.Ellohir:BAAANQAECgIIAgAAAA==.Elloseth:BAABNQAECn8gAAMQAAoKDxaKHgCaAQAQAAgKMBSKHgCaAQAGAAQKyQcsuADAAAAAAA==.Elmorin:BAAANQAECgQICAAAAA==.Eluneh:BAAANQADCgYICAAAAA==.',
Eo='Eolon:BAABNQAECn8fAAIUAAcKLxHorgBUAQAUAAcKLxHorgBUAQAAAA==.',
Ep='Epica:BAABNQAECn88AAICAAoKrxCGaQDgAQACAAoKrxCGaQDgAQAAAA==.',
Er='Eragonhawk:BAABNQAECn8UAAIbAAUKyxG8JgGwAAAbAAUKyxG8JgGwAAAAAA==.Eraina:BAAANQAECgYICQAAAA==.Eroldan:BAAANQADCgYICQAAAA==.Erovianoria:BAAANQAECgcIEQAAAA==.',
Es='Essun:BAABNQAECn8eAAIdAAkKrBmOJwBhAgAdAAkKrBmOJwBhAgABNQAFFAUICQAJAC8HAA==.',
Ev='Evanthe:BAABNQAECn8vAAMIAAoKgxCFYADtAQAIAAoKgxCFYADtAQARAAEKAADSWwEeAAAAAA==.',
Ex='Expire:BAAANQADCgEIAQAAAA==.',
Ez='Ezro:BAAANQADCgYICAAAAA==.',
Fa='Faizor:BAAANQAECgQICQAAAA==.Fastal:BAAANQADCgcIFwAAAA==.Fatalfury:BAAANQAECggIBAAAAA==.Fauxborn:BAABNQAECn8ZAAIGAAcKWSCmOgBRAgAGAAcKWSCmOgBRAgAAAA==.Fauxstorm:BAAANQADCgQIBQAAAA==.',
Fe='Fedwell:BAABNQAECn8gAAIbAAgKpgvX0wB0AQAbAAgKpgvX0wB0AQAAAA==.',
Fi='Finluc:BAAANQAECggIDQAAAA==.Finngan:BAABNQAECn80AAIgAAkKSA1yCABGAQAgAAkKSA1yCABGAQAAAA==.Fitoria:BAAANQAECgMICAABNQAECgoKLAAJADMfAA==.',
Fo='Forestkin:BAABNQAECn8aAAIWAAcKGxYfKwAyAQAWAAcKGxYfKwAyAQABNQAECgoKLwAcAD4lAA==.Foxhope:BAABNQAECn8eAAIXAAYKlRF+HgBrAQAXAAYKlRF+HgBrAQAAAA==.',
Fr='Friartuk:BAAANQAECgEIAQAAAA==.Frozenthunda:BAABNQAECn9GAAICAAoKXQzScgDLAQACAAoKXQzScgDLAQAAAA==.',
Fu='Furfu:BAABNQAECn9CAAMTAAoKnSB2AwBaAwATAAoKnSB2AwBaAwAhAAkKLBqCHADCAQAAAA==.Furna:BAABNQAECn8tAAIiAAkKUg0vBwBlAQAiAAkKUg0vBwBlAQAAAA==.Fuzzyhooves:BAABNQAECn82AAMMAAoKUSQEEwA5AwAMAAoKUSQEEwA5AwAbAAEK0wdrpgE0AAAAAA==.',
Ga='Gabrael:BAACNQAFFH8JAAMEAAQKegmdIQC1AAAEAAMKWQadIQC1AAAjAAIKoA+yBABCAAA1AAQKfzgAAyMACgorEl8NAOEBACMACQr9EF8NAOEBAAQACQrRDjytAKwBAAAA.Galarsar:BAAANQADCgQIBAAAAA==.',
Gh='Ghorienge:BAAANQAECgYIDQAAAA==.',
Gi='Gilox:BAABNQAECn8kAAIkAAgKAA8JGwBMAQAkAAgKAA8JGwBMAQAAAA==.',
Gl='Glossu:BAAANQADCgIIAgAAAA==.',
Gn='Gndmexia:BAAANQAECggIDwAAAA==.Gneiss:BAAANQAECgQIBgAAAA==.',
Go='Goldenarrow:BAAANQABCgYIDgAAAA==.Gorgilz:BAAANQADCgMICQAAAA==.Gothgirldemi:BAABNQAECn81AAIZAAkK6SBODgDtAgAZAAkK6SBODgDtAgAAAA==.',
Gr='Graymon:BAABNQAECn8hAAIjAAcKMBN4EwBBAQAjAAcKMBN4EwBBAQAAAA==.Greebo:BAABNQAECn8fAAIWAAcKLQUkRACtAAAWAAcKLQUkRACtAAAAAA==.Gremsmasha:BAAANQADCggIAQAAAA==.Grist:BAAANQAECgUICAAAAA==.',
Gu='Guatalupe:BAAANQADCgYIBgAAAA==.Guilherme:BAAANQADCggIEAAAAA==.',
Gw='Gwenyver:BAABNQAECn8WAAIbAAcKYgIxSgGCAAAbAAcKYgIxSgGCAAAAAA==.',
Ha='Hailthanatos:BAABNQAECn8bAAIdAAkKLwtIPQDOAQAdAAkKLwtIPQDOAQAAAA==.Hamord:BAABNQAECn8cAAINAAcKNAcOOgDFAAANAAcKNAcOOgDFAAAAAA==.Hansdelbruk:BAAANQADCggIEQAAAA==.Hardlight:BAABNQAECn8UAAIbAAgK1wr+sgBqAQAbAAgK1wr+sgBqAQAAAA==.Harliquette:BAABNQAECn8qAAIQAAoKWhESHAC0AQAQAAoKWhESHAC0AQAAAA==.Harliqynn:BAAANQAECgYIDQAAAA==.Harlock:BAABNQAECn8wAAMeAAoKhBboGgAAAgAeAAoKYRXoGgAAAgAkAAcKtA9FRgCtAQAAAA==.Hashen:BAAANQAECgQIBQAAAA==.Hazelnuts:BAAANQADCgUIBQAAAA==.',
Hi='Hiten:BAABNQAECn85AAIeAAoKOwkCJACoAQAeAAoKOwkCJACoAQAAAA==.',
Ho='Hoofinmouth:BAAANQAECgMIAwAAAA==.Hoosh:BAABNQAECn8bAAMUAAgKyRJ1hwCpAQAUAAcKyRJ1hwCpAQAaAAUK9QWGSAB7AAAAAA==.Hopedaimond:BAABNQAECn8hAAMRAAgKSwrscQAzAQARAAgKSwrscQAzAQAIAAEKaAE6NwEYAAAAAA==.',
Hu='Huntertattoo:BAABNQAECn8lAAIUAAoKsQlRiwChAQAUAAoKsQlRiwChAQAAAA==.Husgus:BAAANQADCgYIDAABNQAFFAIIAgAOAAAAAA==.Huungron:BAAANQADCgYIDAAAAA==.',
Ic='Icynips:BAAANQADCgQIBAAAAA==.',
Il='Illianarra:BAABNQAECn8VAAIUAAcKLwZY1wAEAQAUAAcKLwZY1wAEAQAAAA==.Ilthad:BAABNQAECn8iAAIdAAcKhQ3VPQBFAQAdAAcKhQ3VPQBFAQAAAA==.',
Im='Imaplantnow:BAAANQAECggICAAAAA==.Imastealnow:BAAANQABCgMIAwAAAA==.Imawarrionow:BAAANQADCgIIAgAAAA==.Imora:BAAANQADCgMIAwAAAA==.Imshalar:BAAANQABCgIIAgABNQAECgQIBAAOAAAAAA==.',
In='Infurryating:BAAANQAECggIEgAAAA==.',
Ir='Iroar:BAAANQADCgIIAgAAAA==.Irumble:BAAANQAECgEIAQAAAA==.',
Is='Ischadè:BAAANQADCgUIBwAAAA==.Iskuros:BAAANQAECgUICgAAAA==.',
It='Itsirk:BAABNQAECn8dAAIMAAoKfxI9OQA1AgAMAAoKfxI9OQA1AgAAAA==.',
Iz='Izyebelle:BAABNQAECn8aAAMQAAoKaQWORwCNAAAQAAkKOQKORwCNAAAGAAEKgwFRBQEXAAAAAA==.',
Ja='Jadevine:BAAANQADCgEIAQAAAA==.Jalynfein:BAABNQAECn8oAAMlAAoKPQmGEACGAQAlAAoKLwmGEACGAQAPAAYKvQjTBgDGAAAAAA==.Janar:BAAANQADCgYIBwAAAA==.',
Je='Jefeorganico:BAABNQAECn8bAAQmAAcKRwiYFAABAQAmAAUKggmYFAABAQAgAAUK4QTjRwCoAAAJAAQKgQTFJAF3AAAAAA==.Jeloi:BAAANQAECgQIDwAAAA==.Jenkshi:BAAANQADCgcIDQAAAA==.',
Ji='Jimmydin:BAACNQAFFH8JAAMMAAQKaBmXEgAYAQAMAAQKaBmXEgAYAQAbAAIKJwx8JgCCAAA1AAQKfzMAAwwACgomHVQhAOgCAAwACgomHVQhAOgCABsACgopGDJ8ADICAAAA.',
Ju='Juego:BAAANQADCgQIBAAAAA==.Julkan:BAAANQAECgQIBgAAAA==.Junhoong:BAABNQAECn8+AAIbAAoKnRFqgADMAQAbAAoKnRFqgADMAQAAAA==.Juvia:BAABNQAECn8pAAMRAAkKdxZnXQAJAgARAAgK3hVnXQAJAgAIAAgKRg5NoQAzAQABNQAECgkJOAANADwQAA==.',
Jy='Jynnysa:BAAANQAECgYIBwABNQAECgoKNQANAL8bAA==.',
Ka='Kai:BAAANQAECgYIDgAAAA==.Kairoll:BAABNQAECn83AAMGAAkKnBA4fAClAQAGAAkKnBA4fAClAQAQAAQKLBHXSgDsAAAAAA==.Kaleìna:BAAANQADCgcICAAAAA==.Kallisto:BAAANQAECgIIAgAAAA==.Karaa:BAAANQAECgYICgAAAA==.Kariena:BAABNQAECn8pAAIUAAkK5w5KjACeAQAUAAkK5w5KjACeAQAAAA==.Kart:BAAANQADCgEIAQAAAA==.Kashaka:BAAANQADCgcIEgAAAA==.Katesluage:BAABNQAECn9TAAMlAAkK5hrMBgCOAgAlAAkK5hrMBgCOAgACAAUKMQmwVgEBAQAAAA==.Kayyaa:BAAANQADCggICAAAAA==.',
Ke='Keeya:BAABNQAECn82AAMLAAgKvQuGOwAnAQALAAgKvQuGOwAnAQADAAEKKAJ9vgAeAAAAAA==.Kelina:BAAANQADCgIIAgAAAA==.Kendari:BAABNQAECn8lAAMKAAgKkQwUVwDhAAAKAAgKuQsUVwDhAAADAAQKkAiUfAC1AAAAAA==.Kernasas:BAABNQAECn8rAAIgAAkKERAEBwBoAQAgAAkKERAEBwBoAQAAAA==.',
Kh='Khiari:BAAANQADCgUIBQABNQAECgoKMgAbAFkYAA==.',
Ki='Kier:BAAANQAECgIIBQAAAA==.Kizaraan:BAAANQADCgUIBQAAAA==.',
Kl='Kleyntamar:BAABNQAECn8eAAIZAAcKJBgQIgDnAQAZAAcKJBgQIgDnAQAAAA==.',
Kn='Knyghtly:BAAANQAECggIDgABNQAECgkJKAAZAFAYAA==.',
Ko='Konstantien:BAAANQAECgUIBQAAAA==.Koric:BAABNQAECn8kAAMMAAoKhwzsUQDMAQAMAAoKhwzsUQDMAQAbAAcKnhIe8AADAQAAAA==.Kourney:BAAANQADCgcIBwABNQAECgkJOAANADwQAA==.',
Kr='Kretsch:BAAANQAECgMIAwABNQAECggIFAAJAMMKAA==.Krickket:BAAANQADCgMIAwABNQAECgcIIwAGAHwLAA==.',
Ku='Kupau:BAAANQAECgQICAAAAA==.Kurogami:BAABNQAECn9DAAMDAAoKxRF0PACsAQALAAoKGBF/VwCzAQADAAoKdg10PACsAQAAAA==.Kuthixo:BAAANQAECgUIEwAAAA==.',
Ky='Kylos:BAAANQABCgQIBgAAAA==.Kynnigos:BAAANQABCgIIAgAAAA==.',
La='Landstrider:BAACNQAFFH8HAAIUAAQKVASrGgC+AAAUAAQKVASrGgC+AAA1AAQKfy8AAhQACgqlGZ5SAHgCABQACgqlGZ5SAHgCAAE1AAUUBwgRABkAzgsA.Lanss:BAABNQAECn9GAAQEAAoK/x4kMAB+AgAEAAoKiR4kMAB+AgAHAAcKNh2UEwCFAQAjAAMKKB9zFwALAQAAAA==.Larachel:BAABNQAECn8hAAIGAAkKaxwgRAAoAgAGAAkKaxwgRAAoAgAAAA==.Lastaril:BAAANQADCgYIDwAAAA==.Lastword:BAAANQAECgYIDAABNQAECgcIEAAOAAAAAA==.Laur:BAABNQAECn80AAIQAAoKEg3DHACtAQAQAAoKEg3DHACtAQAAAA==.',
Le='Leipäjuusto:BAABNQAECn8fAAIbAAgKYBDgxgBHAQAbAAgKYBDgxgBHAQAAAA==.',
Li='Liartes:BAABNQAECn8eAAINAAcKVhhPIwBUAQANAAcKVhhPIwBUAQAAAA==.Liderela:BAAANQADCgEIAQAAAA==.Lilipo:BAABNQAECn88AAIhAAkKjgj5KgBBAQAhAAkKjgj5KgBBAQAAAA==.',
Ll='Llarastrasza:BAAANQAECgIIAgABNQAECggIDgAOAAAAAA==.',
Lo='Logoth:BAAANQAECgQIBAAAAA==.Lohgarak:BAAANQADCggIFQAAAA==.',
Lu='Lunaellana:BAAANQADCgYICAAAAA==.',
Ly='Lystaan:BAAANQABCgQIBAAAAA==.',
['Lü']='Lüvpüp:BAACNQAFFH8JAAIXAAQK3Rb1AwC5AAAXAAQK3Rb1AwC5AAA1AAQKfx4AAhcACQqrImIFAD0DABcACQqrImIFAD0DAAAA.',
Ma='Magicfang:BAAANQADCgUICQAAAA==.Maiku:BAABNQAECn8uAAIJAAoKIRIgbAAZAgAJAAoKIRIgbAAZAgAAAA==.Majo:BAAANQAECgIIAgAAAA==.Makado:BAABNQAECn8hAAQmAAoK7Af3DwBOAQAJAAkKrQYKuABeAQAmAAcKlgf3DwBOAQAgAAEKAAB0hAAmAAAAAA==.Makaris:BAAANQAECgQIBAAAAA==.Maklur:BAAANQAECgYIDwAAAA==.Makoa:BAAANQADCgQIBAAAAA==.Makoroth:BAABNQAECn84AAIJAAoKIhVtPwAYAgAJAAoKIhVtPwAYAgAAAA==.Malanda:BAAANQADCgQIBAAAAA==.Malygosson:BAAANQAECgUICgAAAA==.Masharu:BAAANQADCgcIBwAAAA==.Matua:BAAANQAECgIIAgAAAA==.Maycee:BAABNQAECn8eAAIUAAgKwwl+qwBbAQAUAAgKwwl+qwBbAQAAAA==.',
Mc='Mcat:BAAANQAECgYIDwAAAA==.Mcgriddle:BAAANQADCgEIAQAAAA==.Mcnaugh:BAABNQAECn8UAAIKAAcKMAm4WwDSAAAKAAcKMAm4WwDSAAAAAA==.Mcsaltface:BAABNQAECn8bAAIbAAcKfxWzzAA9AQAbAAcKfxWzzAA9AQAAAA==.',
Me='Meddic:BAABNQAECn8hAAMGAAcKbAJwtQDGAAAGAAcKbAJwtQDGAAAQAAIKQQDhjgAcAAAAAA==.Megaux:BAAANQAECgQICAAAAA==.Megavolt:BAABNQAECn8bAAIIAAoKsQ9fPQAgAgAIAAoKsQ9fPQAgAgAAAA==.Menarot:BAAANQAECgcIEQAAAA==.Mendais:BAAANQADCgYIDgAAAA==.Messia:BAAANQADCgEIAQAAAA==.Meztlitotol:BAABNQAECn8YAAMWAAcKhCCQDQCNAgAWAAcKhCCQDQCNAgAYAAEKAACQQAA5AAABNQAECgoKPAAHAAodAA==.',
Mi='Mirosdrigo:BAAANQADCgcIBwAAAA==.Mirosmundo:BAACNQAFFH8MAAITAAUKzQ8aBgC7AAATAAUKzQ8aBgC7AAA1AAQKfzoAAhMACgphHC8FAFUCABMACgphHC8FAFUCAAAA.Mistfit:BAABNQAECn8bAAISAAkKyQyFGwBMAQASAAkKyQyFGwBMAQAAAA==.Miyu:BAABNQAECn9IAAMQAAoKUBV3EwAlAgAQAAoKUBV3EwAlAgAGAAoKXwaZdgB2AQAAAA==.',
Mo='Mod:BAABNQAECn83AAMIAAkK1BvFRQBKAgAIAAkK1BvFRQBKAgARAAEKAABJRAEsAAAAAA==.Moeng:BAAANQADCgIIAgAAAA==.Moggatorash:BAABNQAECn8hAAMIAAkKnAO2owDWAAAIAAkKnAO2owDWAAARAAMKfQFNIAFQAAAAAA==.Mogtham:BAABNQAECn9DAAIWAAoKiBYxFQDsAQAWAAoKiBYxFQDsAQAAAA==.Moisticklez:BAAANQAECgYIBgAAAA==.Monlaferte:BAABNQAECn8ZAAINAAkKgBn4EQANAgANAAkKgBn4EQANAgAAAA==.Montsegur:BAAANQADCggICAAAAA==.Mooforn:BAABNQAECn8hAAQDAAcKGhB7WgAsAQADAAcKGw57WgAsAQALAAYKrw1MTgDLAAAKAAEKBxNToQA0AAAAAA==.Moonfall:BAABNQAECn8lAAIFAAoKPA9EHADFAQAFAAoKPA9EHADFAQAAAA==.Moosader:BAABNQAECn8VAAMbAAcKmg91zQCBAQAbAAcKmg91zQCBAQAMAAcKOQganABPAQAAAA==.Morellea:BAAANQAECgUJCgAAAA==.Morighann:BAABNQAECn82AAIUAAoKdCFiPQBcAgAUAAoKdCFiPQBcAgAAAA==.Moñgoose:BAAANQADCgMIAwAAAA==.',
My='Mynkx:BAABNQAECn8yAAIbAAoKWRg3VwApAgAbAAoKWRg3VwApAgAAAA==.Mythyras:BAABNQAECn81AAQNAAoKvxvnEQANAgANAAoKoRvnEQANAgAbAAMKQRkzNQGdAAAMAAEKjhsH5ABRAAAAAA==.',
Na='Naeomy:BAABNQAECn8/AAIkAAoKHQj9GgBNAQAkAAoKHQj9GgBNAQAAAA==.Nahaman:BAAANQAECgUIEAAAAA==.Napolien:BAABNQAECn84AAMNAAkKPBB7LQBxAQANAAgKPBB7LQBxAQAMAAMKrA8D7ACpAAAAAA==.Naugan:BAAANQADCgEIAQAAAA==.',
Ne='Nechahira:BAACNQAFFH8RAAIZAAcKzgtGBwB9AQAZAAcKzgtGBwB9AQA1AAQKfyQAAxkACgrDFeoWAGUCABkACgrDFeoWAGUCABYAAQoAAH2PAAAAAAAA.Nethim:BAABNQAECn8WAAQMAAcKWQo5pwDQAAAMAAYKzgU5pwDQAAAbAAYK4gh7FQHJAAANAAUKTQPgSgB5AAAAAA==.Nezana:BAAANQAECgIIAgAAAA==.',
Ni='Nien:BAAANQAECgIIAwAAAA==.Nightfallen:BAAANQAECgQIBwAAAA==.Nihlathak:BAAANQAECgYIDAAAAA==.Ninada:BAABNQAECn8hAAMCAAoK1gpBuQAyAQACAAoK1glBuQAyAQAlAAIKcgifQwA8AAAAAA==.Ninalee:BAAANQAECgYICgAAAA==.Ninefallen:BAAANQAECgMIBQAAAA==.',
No='Noranna:BAABNQAECn8hAAIUAAcKqAii0gANAQAUAAcKqAii0gANAQAAAA==.',
Ny='Nyim:BAAANQAECgEIAQAAAA==.Nymiria:BAAANQABCgEIAQABNQAECgcIIwAGAHwLAA==.Nynsyn:BAABNQAECn8YAAMTAAgK/BrLCgCRAQATAAcKih7LCgCRAQAhAAEKNgmzXgAyAAABNQAECgoKNQANAL8bAA==.Nyxeira:BAAANQAECgYICgAAAA==.',
['Nâ']='Nâli:BAAANQAECgQIBAAAAA==.',
Ob='Obsidianclaw:BAAANQADCgIIAwAAAA==.',
Oh='Ohthesemyboo:BAAANQAECgQIEQAAAA==.Ohwellz:BAAANQAECgEIAQAAAA==.',
Ol='Olehei:BAAANQAECgEIAQAAAA==.',
Op='Ophin:BAABNQAECn9EAAILAAoKqRuzDwCFAgALAAoKqRuzDwCFAgAAAA==.',
Or='Ornaxxi:BAAANQAECgIIAgAAAA==.',
Pa='Panamared:BAABNQAECn8xAAIeAAoKTxSLFgAtAgAeAAoKTxSLFgAtAgAAAA==.Pappawoody:BAABNQAECn8cAAIEAAgKCBxkbwBFAgAEAAgKCBxkbwBFAgAAAA==.Parishealton:BAAANQADCgcIBwAAAA==.Patitasuaves:BAAANQAECgEIAQABNQAECgoKQQAnAHEhAA==.',
Pe='Pellegryn:BAAANQADCgYICQAAAA==.Pennyfeather:BAABNQAECn9EAAMGAAoKZRN8SwAKAgAGAAoKZRN8SwAKAgAQAAQKygkUUgDHAAAAAA==.Pezza:BAABNQAECn8fAAIIAAoKgg/FXgCcAQAIAAoKgg/FXgCcAQAAAA==.',
Ph='Phaze:BAABNQAECn8wAAInAAgKZyBPBACkAgAnAAgKZyBPBACkAgAAAA==.Phideauxe:BAAANQAECgQIBQAAAA==.Phorate:BAAANQAECgcIDwAAAA==.',
Pl='Pluralbutter:BAABNQAECn8bAAIdAAoKqA2iPADSAQAdAAoKqA2iPADSAQAAAA==.',
Po='Popexeo:BAAANQAECgcIDQABNQAFFAcIEAAZAGwRAA==.',
Pr='Prometheum:BAABNQAECn8UAAMRAAgKQw/YVQCGAQARAAgKQw/YVQCGAQAIAAIKHQF8IgErAAAAAA==.',
Ps='Psyvern:BAABNQAECn8yAAMVAAoKRQg/CwBKAQAVAAoKRQg/CwBKAQAfAAMK7gOWMgBoAAAAAA==.',
Qt='Qtkat:BAAANQADCgMIAwABNQAECgcIHAAlACUFAA==.',
Qu='Quiccerstorm:BAAANQADCgQIBQAAAA==.',
Ra='Raeburne:BAAANQAECgQIBAAAAA==.Raevennlumis:BAABNQAECn8ZAAIbAAkK1ggp5gBPAQAbAAkK1ggp5gBPAQAAAA==.Raevenns:BAAANQADCggJCAABNQAECgkJGQAbANYIAA==.Rascdit:BAAANQAECgUICgAAAA==.',
Re='Recreant:BAABNQAECn8UAAIbAAoK+QLgIAG4AAAbAAoK+QLgIAG4AAAAAA==.Reiyoso:BAAANQAECgQIAwAAAA==.Reui:BAAANQAECgIIAgAAAA==.',
Rh='Rhemibumbum:BAAANQAECgUICwAAAA==.',
Ro='Roberey:BAAANQAECgUICgAAAA==.Rocketbilly:BAAANQADCgIIAgAAAA==.Roobee:BAABNQAECn8qAAIgAAoKfgSmEQDIAAAgAAoKfgSmEQDIAAAAAA==.',
Ru='Ruaic:BAAANQAECgEIAQAAAA==.',
Sa='Sableanne:BAAANQAECgQIBwAAAA==.Sacréd:BAABNQAECn8ZAAINAAcKCxcSLAB8AQANAAcKCxcSLAB8AQAAAA==.Sarkan:BAAANQADCggIEQAAAA==.Sarova:BAABNQAECn8pAAIUAAoKKhf9dADVAQAUAAoKKhf9dADVAQAAAA==.Satori:BAABNQAECn8gAAISAAcKZRf0EwDGAQASAAcKZRf0EwDGAQAAAA==.',
Sc='Scalewind:BAAANQADCgYIBgAAAA==.',
Se='Seldeath:BAAANQADCgEJAQAAAA==.Selfu:BAABNQAECn87AAIhAAoKJxf2FAAbAgAhAAoKJxf2FAAbAgAAAA==.Sellidor:BAABNQAECn9DAAIUAAoKviTGDQAhAwAUAAoKviTGDQAhAwAAAA==.Serenesong:BAAANQAECgMIBgAAAA==.Seriniyaa:BAAANQAECgUIEwAAAA==.Serioth:BAAANQADCgIIAgAAAA==.',
Sh='Sheara:BAAANQAECggIEgAAAA==.Shinjiro:BAABNQAECn8nAAIbAAoKoQJhTQGkAAAbAAoKoQJhTQGkAAAAAA==.Shirito:BAABNQAECn9EAAMLAAkKgSQCCwBjAwALAAgKVSUCCwBjAwADAAkK6yNhCwA9AwAAAA==.Shiritodh:BAABNQAECn8lAAIFAAkKcCBRFQC6AgAFAAkKcCBRFQC6AgAAAA==.Shockin:BAAANQAECgcIDAAAAA==.Shortnstout:BAACNQAFFH8PAAINAAUKfxdvBAAeAQANAAUKfxdvBAAeAQA1AAQKfzEAAw0ACgq/ImgLAOICAA0ACgq/ImgLAOICABsABwqjG7TKAEEBAAAA.Shugo:BAABNQAECn8mAAInAAcKxQzICgAfAQAnAAcKxQzICgAfAQAAAA==.',
Si='Sienje:BAABNQAECn8zAAIbAAoKRBcCZAAKAgAbAAoKRBcCZAAKAgAAAA==.Sigma:BAABNQAECn8qAAIUAAoKagfVoAByAQAUAAoKagfVoAByAQAAAA==.Simpleson:BAABNQAECn9FAAMJAAoKrx5oIwCEAgAJAAkKcB9oIwCEAgAgAAEKbhlvMQBFAAAAAA==.Sinbàd:BAACNQAFFH8LAAIFAAYKExMPBwCeAQAFAAYKExMPBwCeAQA1AAQKfzwAAgUACgo6IQANAIMCAAUACgo6IQANAIMCAAAA.Sinbád:BAAANQAFFAIIAgABNQAFFAYICwAFABMTAA==.Sinistris:BAAANQAECgUIBgAAAA==.',
Sk='Skie:BAABNQAECn8YAAMfAAgKVQ3HIAAGAQAfAAcKLg/HIAAGAQAXAAYKrgUCGQCuAAABNQAECgkJKAAZAFAYAA==.Skrabble:BAABNQAECn8dAAICAAcK1APQAwGuAAACAAcK1APQAwGuAAAAAA==.Skölldraugos:BAAANQAECgEIAQAAAA==.',
Sl='Slaete:BAABNQAECn8hAAIdAAgKigWVUgDZAAAdAAgKigWVUgDZAAAAAA==.Slush:BAAANQAECgQIBAAAAA==.',
Sm='Smallz:BAABNQAECn8mAAMGAAoKkBgHHgDsAgAGAAoKkBgHHgDsAgAiAAEKWxSiJgA8AAABNQAECgoKOAAUAEYWAA==.Smorgas:BAAANQAECgQICQABNQAECgoKQAAbACIgAA==.Småug:BAAANQADCgMIAwAAAA==.',
So='Solemn:BAABNQAECn89AAIQAAoKExhrEABTAgAQAAoKExhrEABTAgABNQAECgoKQwAUAL4kAA==.Solrana:BAAANQAECgYIEAAAAA==.Songmistress:BAABNQAECn8ZAAIJAAkK5AVexwA7AQAJAAkK5AVexwA7AQAAAA==.Sorren:BAAANQAECgUIBQAAAA==.Sotta:BAAANQAECgIIBQAAAA==.Sozin:BAAANQADCgIIAgAAAA==.',
Sp='Spritmoon:BAAANQADCgYIBgAAAA==.',
Sq='Squeezee:BAAANQADCggICAAAAA==.',
St='Stardrive:BAABNQAECn8oAAIIAAoKyxpsIAC6AgAIAAoKyxpsIAC6AgAAAA==.Stevesteve:BAABNQAECn87AAIJAAkKzg+OUADiAQAJAAkKzg+OUADiAQAAAA==.Stroganov:BAABNQAECn8UAAIJAAgKwwpDiwBGAQAJAAgKwwpDiwBGAQAAAA==.Stumpii:BAAANQADCgQIBAAAAA==.',
Su='Sunasha:BAAANQADCgYIEgAAAA==.Superbautumn:BAABNQAECn8sAAIbAAoKlBjiVAAvAgAbAAoKlBjiVAAvAgAAAA==.',
Sy='Synge:BAABNQAECn8oAAMCAAcKFw7MwQAjAQACAAcKFw7MwQAjAQAlAAEK9AfLSgAwAAAAAA==.Synnyca:BAAANQAECgcICQABNQAECgoKNQANAL8bAA==.',
['Sé']='Sélune:BAAANQAECggIDgAAAA==.',
['Sï']='Sïnbad:BAAANQAFFAIIAgABNQAFFAYICwAFABMTAA==.',
Ta='Tachyon:BAAANQAECgYICAABNQAFFAQICQAXAN0WAA==.Taeonaki:BAAANQAECgMIBwAAAA==.Tagnaras:BAAANQAECgcIDgAAAA==.Tagnaris:BAAANQAECgUIBQAAAA==.Tahlang:BAAANQABCggICgAAAA==.Tali:BAABNQAECn8aAAIUAAcKkArLvQA2AQAUAAcKkArLvQA2AQAAAA==.Taliasluage:BAAANQADCggICAABNQAECgkJUwAlAOYaAA==.Tangle:BAABNQAECn8oAAMZAAkKUBhXKADdAQAZAAcKCRlXKADdAQABAAcKfAayaACGAAAAAA==.Tanka:BAABNQAECn8zAAIEAAoKAx/3NABrAgAEAAoKAx/3NABrAgAAAA==.Tannisse:BAAANQADCggIFQAAAA==.Tanuki:BAAANQAECgcIBgAAAA==.Tapol:BAAANQAECgYIEgABNQAECgcIIwAGAHwLAA==.Tashlaraz:BAEBNQAECn8aAAMdAAcKPAkCTwDpAAAdAAcKPAkCTwDpAAAcAAMKXQMbLgA4AAAAAA==.Tasi:BAAANQAECgQIBAAAAA==.Taurannosaur:BAAANQADCggIDAAAAA==.Taurentots:BAABNQAFFH8OAAIKAAYKZRJKEAACAQAKAAYKZRJKEAACAQAAAA==.',
Te='Telkas:BAAANQAECgYIDAAAAA==.Temporantus:BAAANQAECgYIBgAAAA==.Tenko:BAABNQAECn9IAAMCAAoKjwtubwDSAQACAAoKTQtubwDSAQAlAAIKdAzaNQBkAAAAAA==.',
Th='Thaddeus:BAABNQAECn8cAAIRAAkKfA5zWAB+AQARAAkKfA5zWAB+AQAAAA==.Therm:BAACNQAFFH8RAAIbAAcKzxfgBQD4AQAbAAcKzxfgBQD4AQA1AAQKf2gAAxsACgrxJpYAAJwDABsACgrxJpYAAJwDAAwAAQrQBwQgATYAAAAA.Thoramier:BAABNQAECn8UAAINAAcKeBPALQBvAQANAAcKeBPALQBvAQAAAA==.',
Ti='Tibble:BAABNQAECn8XAAIHAAcKugJHLgCTAAAHAAcKugJHLgCTAAAAAA==.Timoonja:BAABNQAECn8cAAILAAYKyQ2eSQDgAAALAAYKyQ2eSQDgAAAAAA==.Tirazlea:BAAANQADCgIIAgAAAA==.',
To='Tonatuih:BAABNQAECn9UAAMdAAoKMSBpEACqAgAdAAoKMSBpEACqAgAcAAgKfhU7CgC+AQAAAA==.',
Tr='Treeandra:BAAANQAECgUICQAAAA==.Trezzia:BAABNQAECn8oAAImAAoKCBXLBgA6AgAmAAoKCBXLBgA6AgAAAA==.Triipod:BAAANQADCgYIIwAAAA==.Trinkat:BAABNQAECn8cAAIlAAcKJQVCIgDGAAAlAAcKJQVCIgDGAAAAAA==.Trojinn:BAAANQAECgUIBQAAAA==.Tryst:BAAANQADCgYIBgAAAA==.Tráson:BAAANQADCgYIBQAAAA==.',
Tu='Tub:BAABNQAECn8lAAICAAgKnQnetQA5AQACAAgKnQnetQA5AQAAAA==.',
Ty='Tylean:BAABNQAECn8XAAIUAAcKrwv5nwB0AQAUAAcKrwv5nwB0AQAAAA==.',
['Tì']='Tìríon:BAAANQABCgEIAQAAAA==.',
Ud='Udukai:BAAANQAECgQIBAAAAA==.',
Ul='Ultrastealth:BAABNQAECn8ZAAQeAAUK6ga9PADSAAAeAAUKAAa9PADSAAAkAAQKdgRTkQBtAAAoAAIKtgO6DAAnAAAAAA==.',
Um='Umbrum:BAAANQADCgIIAgABNQAECgoKPAAHAAodAA==.',
Uu='Uu:BAABNQAECn8gAAIEAAkK1SO2CQBDAwAEAAkK1SO2CQBDAwAAAA==.',
Va='Vadrozsa:BAAANQAECgUIEgAAAA==.Vallarie:BAAANQADCgQJBAAAAA==.Vareyn:BAAANQAECgYICQAAAA==.',
Vo='Vorth:BAABNQAECn9IAAIDAAoKmxTkLAD9AQADAAoKmxTkLAD9AQAAAA==.Vorukh:BAAANQADCgQIBAABNQAECgcIDgAOAAAAAA==.Vorúkh:BAABNQAECn8lAAQBAAoKUQ0+OwBCAQABAAgKzws+OwBCAQAWAAYKdAvbRACqAAAYAAEK6Q7mTgArAAABNQAECgcIDgAOAAAAAA==.Vorükh:BAAANQAECggIDQABNQAECgcIDgAOAAAAAA==.',
Vu='Vulturous:BAAANQADCgYICgAAAA==.',
Vy='Vydian:BAAANQADCgYICQAAAA==.Vyrlana:BAAANQAECgEIAQAAAA==.',
Wa='Waldir:BAABNQAECn89AAMMAAoKAiR+BwClAwAMAAoKAiR+BwClAwAbAAMKkApRZAFlAAAAAA==.Wanted:BAAANQADCgYIBgAAAA==.Watz:BAABNQAECn8pAAIUAAoKUwwrZAD9AQAUAAoKUwwrZAD9AQAAAA==.',
We='Wensa:BAAANQAECgYIBgAAAA==.',
Wh='Wholesale:BAABNQAECn82AAIKAAgK7BZNQwDuAQAKAAgK7BZNQwDuAQAAAA==.',
Wo='Worldeater:BAAANQAECgIIAgAAAA==.',
Wr='Wrack:BAAANQADCggIEgAAAA==.Wraithian:BAAANQABCgQIBAAAAA==.Wratsoul:BAABNQAECn8qAAIJAAoKMBBifgDqAQAJAAoKMBBifgDqAQAAAA==.',
Xa='Xalldin:BAAANQADCgEIAQAAAA==.',
Xe='Xessala:BAABNQAECn8uAAIIAAkKfRaUUAAjAgAIAAkKfRaUUAAjAgAAAA==.',
Xh='Xheero:BAABNQAECn86AAIUAAkK5x2bJAAEAwAUAAkK5x2bJAAEAwAAAA==.Xheerom:BAAANQADCgUIBQAAAA==.',
Ya='Yagiashi:BAAANQAECgUICgABNQAECgoKPAAHAAodAA==.',
Yu='Yulica:BAABNQAECn8bAAIlAAcK1ApCHwDaAAAlAAcK1ApCHwDaAAAAAA==.Yunamaesh:BAAANQAECgYIBgAAAA==.',
Za='Zaffy:BAABNQAECn86AAIgAAkKpg8jBwBkAQAgAAkKpg8jBwBkAQAAAA==.Zaktrix:BAAANQAECgIIAgAAAA==.Zaleron:BAAANQADCggIFAAAAA==.Zaruba:BAABNQAECn81AAMRAAoKjwjMXwBnAQARAAoKjwjMXwBnAQAIAAEKsAHlEgEYAAABNQAECgkJNAABAOIKAA==.Zatkyng:BAABNQAECn8pAAIhAAoK1A8QJgBpAQAhAAoK1A8QJgBpAQAAAA==.',
Ze='Zekos:BAAANQAECgEIAQAAAA==.',
Zi='Zillver:BAAANQAECgUIBQABNQAECgkJOAANADwQAA==.Zimdalar:BAABNQAECn8oAAITAAcK8xd8DQBTAQATAAcK8xd8DQBTAQAAAA==.',
Zo='Zomi:BAAANQADCgIIAgAAAA==.',
Zu='Zulre:BAABNQAECn8+AAMKAAoK5htkGwDUAgAKAAoK5htkGwDUAgADAAUKnw3LdADQAAAAAA==.',
Zy='Zynnayde:BAAANQAECgUIBQABNQAECgoKNQANAL8bAA==.',
['Ôv']='Ôverkill:BAABNQAECn8fAAIWAAoKEBZOGgC0AQAWAAoKEBZOGgC0AQAAAA==.',
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
