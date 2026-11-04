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

local lookup = {'Druid-Balance','Warrior-Arms','DemonHunter-Devourer','Priest-Holy','Warrior-Protection','Warlock-Demonology','Monk-Brewmaster','Shaman-Restoration','DeathKnight-Frost','DeathKnight-Blood','DeathKnight-Unholy','Mage-Fire','Priest-Shadow','Shaman-Elemental','Monk-Mistweaver','Evoker-Augmentation','Paladin-Holy','Unknown-Unknown','Druid-Guardian','Evoker-Devastation','Druid-Feral','Druid-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Havoc','Rogue-Subtlety','Evoker-Preservation','Mage-Arcane','Warlock-Destruction','Priest-Discipline','Warrior-Fury','Rogue-Assassination','Mage-Frost','Warlock-Affliction','Paladin-Protection','Monk-Windwalker','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Ackrenoth:BAAANQAECgUIBQAAAA==.',
Ad='Adynn:BAABNQAECn9HAAIBAAoKlyXoBACyAwABAAoKlyXoBACyAwAAAA==.',
Ae='Aermoss:BAAANQABCgUIBQAAAA==.Aeru:BAAANQADCgYIBgAAAA==.Aethreal:BAAANQAFFAEIAQAAAA==.',
Af='Afraid:BAAANQAECggIAQAAAA==.Afridium:BAAANQADCgEIAQAAAA==.',
Ai='Aiselraith:BAAANQAECgUIBQAAAA==.',
Ak='Akikusa:BAAANQADCggICgAAAA==.',
Al='Alderath:BAAANQABCgQJBQAAAA==.Alista:BAABNQAECn9BAAICAAoK7yRNCgCjAwACAAoK7yRNCgCjAwAAAA==.Allyeska:BAAANQADCgcIDQAAAA==.Alnharaelune:BAAANQADCgYIDQAAAA==.',
Am='Amarea:BAAANQAECgIIAgAAAA==.Amor:BAABNQAECn8hAAIDAAcK2hjvKgDqAQADAAcK2hjvKgDqAQAAAA==.',
An='Anali:BAABNQAECn8WAAIEAAkKVRMtSwBEAgAEAAkKVRMtSwBEAgAAAA==.Anani:BAAANQAECgUIBQAAAA==.Angreifer:BAABNQAECn88AAMFAAoKCh30BQB2AgAFAAoKCh30BQB2AgACAAIKvAP9PgFVAAAAAA==.Anoana:BAAANQADCgQIBAAAAA==.Anori:BAABNQAECn8jAAIBAAgKbwt+OgASAQABAAgKbwt+OgASAQAAAA==.',
Ao='Aonar:BAAANQAECgUIDAAAAA==.',
Aq='Aqua:BAAANQABCgcIEwAAAA==.',
Ar='Arc:BAABNQAECn8sAAIGAAoKMx8oFwChAgAGAAoKMx8oFwChAgABNQAECgoKPQAHAEMgAA==.Arcanimous:BAAANQADCggIDAAAAA==.Archenteron:BAAANQAECgQIBQAAAA==.Archnunin:BAAANQAECggICAAAAA==.Ardorcinder:BAAANQAECgQICAAAAA==.Argentur:BAAANQADCgEIAQAAAA==.Arkaan:BAAANQADCgUIBQABNQAECgoKIQAIAGgZAA==.Armangaria:BAAANQAECggICAAAAA==.Arrohon:BAAANQAECgcIDgAAAA==.Arrozz:BAAANQADCgQIBAAAAA==.Arthmanafel:BAABNQAECn8rAAQJAAoKtBk/KQBPAgAJAAoKAxk/KQBPAgAKAAEKqR9btQBeAAALAAEKJQu54gAxAAAAAA==.',
As='Asbjorne:BAAANQAECgUIEQAAAA==.',
At='Atryssa:BAAANQAECgUIBQAAAA==.',
Au='Audi:BAAANQADCgMIAwAAAA==.Aurianne:BAAANQAECgcIBgAAAA==.Autumnmoon:BAABNQAECn8WAAIMAAcK0BDIAwAdAQAMAAcK0BDIAwAdAQAAAA==.',
Av='Avalsong:BAABNQAECn9CAAIDAAoKvh1KDgAEAwADAAoKvh1KDgAEAwAAAA==.Avelos:BAACNQAFFH8IAAIEAAMKohCcGwDRAAAEAAMKohCcGwDRAAA1AAQKfzQAAwQACgqmHnAjAOACAAQACgqmHnAjAOACAA0AAQrtCkFZAC4AAAAA.',
Ay='Ayowenn:BAAANQADCgIIAgAAAA==.Ayzmist:BAABNQAECn8pAAIOAAcKhAn8cwD1AAAOAAcKhAn8cwD1AAAAAA==.Ayzmyth:BAABNQAECn80AAMPAAoK9hCLEQCwAQAPAAoK9hCLEQCwAQAHAAUKJwQ4IgDIAAAAAA==.',
Az='Azurelight:BAAANQADCgMIAwAAAA==.',
Ba='Banthapooduu:BAAANQADCggIIAAAAA==.',
Be='Beasic:BAABNQAECn88AAMOAAkK+gS8YwAgAQAOAAkK+gS8YwAgAQAIAAIKMwI71gBDAAAAAA==.Beastmode:BAAANQAECgUICgAAAA==.Beletili:BAABNQAECn8xAAIEAAoK/hE0ZADzAQAEAAoK/hE0ZADzAQAAAA==.Bellissimio:BAAANQADCgUICAABNQAECgoKKwAIAIMQAA==.Bener:BAAANQADCgcIBwAAAA==.Beátrix:BAAANQADCgIIAgAAAA==.',
Bi='Bismuth:BAAANQAECgMIBQAAAA==.',
Bl='Blackraven:BAAANQAECgcIDQAAAA==.Blatendrg:BAABNQAECn9AAAIQAAoK+RJhCAARAgAQAAoK+RJhCAARAgAAAA==.Blindcloud:BAAANQAECgUICQAAAA==.',
Bo='Boot:BAABNQAECn8bAAIRAAYK8hWcYABlAQARAAYK8hWcYABlAQAAAA==.Borodemonin:BAEBNQAECn8rAAIDAAkKVyb1AgCrAwADAAkKVyb1AgCrAwAAAA==.',
Br='Breae:BAABNQAECn88AAMEAAkKcBWxTQDIAQAEAAkKcBWxTQDIAQANAAYKFgnQNwCkAAAAAA==.Brieanna:BAAANQADCgUIBgAAAA==.Bristia:BAAANQAECgUIBwAAAA==.Brueggar:BAAANQAECgEIAgAAAA==.Brutyl:BAAANQAECgEIAQABNQAECggIEQASAAAAAA==.',
Bu='Bulky:BAAANQAECgIIAgAAAA==.',
By='Byegone:BAAANQAECgQIDgAAAA==.',
Ca='Cadforus:BAAANQADCgcIEAABNQAECgkJHgATAM4WAA==.Cafë:BAAANQADCgcICgABNQAFFAQICQAUAN0WAA==.Caicee:BAAANQADCgQIBAAAAA==.Caistin:BAAANQADCgYIDgAAAA==.Calyma:BAAANQAECgIIBAAAAA==.Camelsotters:BAABNQAECn8XAAUVAAUKEAdHMQCJAAAVAAQKnQVHMQCJAAATAAUK7wVBSgCCAAAWAAQKwQJZUwByAAABAAIKWQGmugAmAAAAAA==.Casca:BAAANQAECgUICwAAAA==.Catsclaw:BAAANQADCgYICgAAAA==.',
Ce='Cenjeru:BAABNQAECn8eAAMJAAgKfhdHPADdAQAJAAgKHRVHPADdAQALAAYKnBclZwB1AQAAAA==.',
Ch='Chezzie:BAAANQAECgYICwAAAA==.Chiot:BAABNQAECn8tAAIFAAkKJRz5CQCnAgAFAAkKJRz5CQCnAgAAAA==.',
Ci='Cimerian:BAAANQAECgIIBAAAAA==.',
Cl='Clone:BAAANQADCgYIBgAAAA==.Cloudysky:BAAANQAECgUIBQAAAA==.',
Co='Cobalticus:BAAANQAECgUICQAAAA==.Coffee:BAAANQADCgEIAQABNQADCgMIAwASAAAAAA==.Coledarus:BAAANQADCgUIBQAAAA==.Concealer:BAAANQADCgEIAQAAAA==.Conejamala:BAABNQAECn8xAAMXAAoK5R4fFgBDAwAXAAoK5R4fFgBDAwAYAAMKUw6PXwCoAAAAAA==.Corange:BAAANQABCgIIBAAAAA==.Cordini:BAAANQAECgQIDAAAAA==.Corlock:BAAANQAECgIIAgAAAA==.Cormech:BAAANQAECgQIBwAAAA==.Cornite:BAAANQAECggICAAAAA==.',
Cr='Crizzo:BAABNQAECn82AAIXAAoKThwkJQCAAgAXAAoKThwkJQCAAgAAAA==.',
Da='Daddyslilgrl:BAAANQAECgMIBQAAAA==.Dakra:BAEBNQAECn8fAAICAAkKkRT4XgCpAQACAAkKkRT4XgCpAQAAAA==.Dalamar:BAAANQAECggIIwABNQAFFAIIBQANAOcLAQ==.Dalandis:BAABNQAECn82AAMZAAoKth/XJACoAgAZAAkKZyLXJACoAgARAAcKuxWsQgDWAQAAAA==.Dalyeth:BAABNQAECn8lAAMaAAkKQiWGBAD8AgAaAAkKQiWGBAD8AgAbAAEKAAAumwAoAAAAAA==.Darianno:BAAANQADCgMIAwAAAA==.Darkwingorc:BAABNQAECn9AAAIXAAoKCyKVGwCwAgAXAAoKCyKVGwCwAgAAAA==.Darkwulf:BAAANQAECgUIBQAAAA==.Daunt:BAAANQADCgcIDgABNQAECgkJLwABANIKAA==.Dawnfire:BAAANQADCgEIAQAAAA==.Dawnmane:BAAANQADCgEIAQAAAA==.',
De='Deadsecsi:BAAANQABCgEIAQAAAA==.Decypher:BAAANQAECgUICgABNQAECgoKPQAcANgTAA==.Deebz:BAABNQAECn8fAAIWAAcKNBZvKQDTAQAWAAcKNBZvKQDTAQAAAA==.Deliverance:BAACNQAFFH8FAAINAAIK5wujDQCNAAANAAIK5wujDQCNAAA1AAQKfzsAAg0ACgroHJ0RAOMCAA0ACgroHJ0RAOMCAAAA.Demigoth:BAABNQAECn8hAAIdAAcKJROcIgC0AQAdAAcKJROcIgC0AQAAAA==.Denethmon:BAAANQAECgEJAQABNQAECgUIDQASAAAAAA==.Dentik:BAABNQAECn86AAMWAAcKLxTkIwCIAQAWAAcKLxTkIwCIAQAVAAYK5wsKHgAsAQAAAA==.Denuma:BAAANQAECgMIAwAAAA==.Devilina:BAAANQADCggICgAAAA==.Deàdpool:BAAANQADCgQIBgABNQAECgoKNQAGADEbAA==.',
Dh='Dheriana:BAABNQAECn89AAIcAAoK2BMmMwDxAQAcAAoK2BMmMwDxAQAAAA==.Dherisis:BAAANQAECgMIAwABNQAECgoKPQAcANgTAA==.Dherli:BAAANQAECgMIBAABNQAECgoKPQAcANgTAA==.',
Di='Diamair:BAABNQAECn8qAAIeAAkKoQzGhABwAQAeAAkKoQzGhABwAQAAAA==.Disney:BAAANQAECggICAAAAA==.Divynelle:BAAANQABCgIIAgAAAA==.Dixiee:BAABNQAECn8dAAIEAAYK4gw3lgDfAAAEAAYK4gw3lgDfAAAAAA==.',
Dn='Dnegelpal:BAABNQAECn8tAAIZAAgKQQ9PrwAxAQAZAAgKQQ9PrwAxAQAAAA==.',
Do='Dodgecharger:BAAANQAECgYIEAAAAA==.',
Dr='Dragerin:BAAANQAECgMIAwAAAA==.Dragonfood:BAAANQAECgMIBAAAAA==.Drakilu:BAABNQAECn89AAIXAAkKWhhqUQB7AgAXAAkKWhhqUQB7AgAAAA==.Drakra:BAEANQAECgYICgABNQAECgkJHwACAJEUAA==.Drasic:BAABNQAECn9KAAIWAAoKBB9kCQAvAwAWAAoKBB9kCQAvAwAAAA==.Dreamcloud:BAAANQADCgYICAAAAA==.Dreddscott:BAAANQAECgYIBgABNQAECgkJLQAcAAMVAA==.Dretro:BAAANQAECgIIBQAAAA==.Drisla:BAAANQADCgMIAwAAAA==.Drovosi:BAAANQADCggIIgAAAA==.',
Du='Durin:BAABNQAECn8tAAICAAkKvwk/fQBXAQACAAkKvwk/fQBXAQAAAA==.Durward:BAABNQAECn8eAAMLAAkK4RMRMwAqAQAKAAcKQBBpWgCJAQALAAcKLxQRMwAqAQAAAA==.Duvo:BAABNQAECn8tAAIXAAkK9hV1bwAzAgAXAAkK9hV1bwAzAgAAAA==.',
Dw='Dwarvey:BAAANQADCggIDgAAAA==.',
['Dæ']='Dæmôna:BAAANQADCgQIBQAAAA==.',
['Dé']='Détank:BAABNQAECn80AAIJAAgKhhsmMwATAgAJAAgKhhsmMwATAgAAAA==.',
Ea='Easyname:BAABNQAECn83AAIZAAoKnRzILwB4AgAZAAoKnRzILwB4AgAAAA==.',
Ei='Eiene:BAAANQAECgUICQAAAA==.Eithetala:BAAANQADCgYICAAAAA==.',
El='Elemental:BAAANQAECggIDQABNQAFFAYIEAAWACMNAA==.Ellohir:BAAANQABCgIIAgAAAA==.Elloseth:BAAANQAECgYIDgAAAA==.Elmorin:BAAANQAECgQICAAAAA==.Eluneh:BAAANQADCgYICAAAAA==.',
Eo='Eolon:BAABNQAECn8WAAIXAAYKdxM8rAAVAQAXAAYKdxM8rAAVAQAAAA==.',
Ep='Epica:BAABNQAECn83AAIeAAoKVA7ybgCjAQAeAAoKVA7ybgCjAQAAAA==.',
Er='Eragonhawk:BAAANQAECgMICgAAAA==.Eraina:BAAANQAECgMIAwAAAA==.Eroldan:BAAANQADCgYICQAAAA==.Erovianoria:BAAANQAECgcIEQAAAA==.',
Es='Essun:BAABNQAECn8eAAIbAAkKrBmOJwBhAgAbAAkKrBmOJwBhAgABNQAFFAUICQAGAC8HAA==.',
Ev='Evanthe:BAABNQAECn8rAAMIAAoKgxC1RwDCAQAIAAoKgxC1RwDCAQAOAAEKAADSWwEeAAAAAA==.',
Ex='Expire:BAAANQADCgEIAQAAAA==.',
Ez='Ezro:BAAANQADCgYICAAAAA==.',
Fa='Faizor:BAAANQAECgQIBgAAAA==.Fastal:BAAANQADCgcIFwAAAA==.Fatalfury:BAAANQAECggIBAAAAA==.Fauxborn:BAAANQAECgYIEwAAAA==.Fauxstorm:BAAANQADCgQIBQAAAA==.',
Fe='Fedwell:BAABNQAECn8gAAIZAAgKpgvX0wB0AQAZAAgKpgvX0wB0AQAAAA==.',
Fi='Finluc:BAAANQAECggICQAAAA==.Finngan:BAABNQAECn8sAAIfAAgK3gmwCgDsAAAfAAgK3gmwCgDsAAAAAA==.Fitoria:BAAANQAECgMICAABNQAECgoKPQAHAEMgAA==.',
Fo='Forestkin:BAAANQAECgUIDwABNQAECgkJJQAaAEIlAA==.Foxhope:BAABNQAECn8ZAAIUAAYKlRF+HgBrAQAUAAYKlRF+HgBrAQAAAA==.',
Fr='Friartuk:BAAANQAECgEIAQAAAA==.Frozenthunda:BAABNQAECn83AAIeAAkKngwGgAB7AQAeAAkKngwGgAB7AQAAAA==.',
Fu='Furna:BAABNQAECn8oAAIgAAkKDg2bBgBAAQAgAAkKDg2bBgBAAQAAAA==.Fuzzyhooves:BAABNQAECn8wAAMRAAkK4CMEEwA5AwARAAkK4CMEEwA5AwAZAAEK0wdrpgE0AAAAAA==.',
Ga='Gabrael:BAACNQAFFH8FAAMhAAIKCwnfAwBDAAAhAAEKoA/fAwBDAAACAAIKXAGeMQAuAAA1AAQKfzcAAyEACgoBEl8NAOEBACEACQr9EF8NAOEBAAIACQqhDjytAKwBAAAA.',
Gh='Ghorienge:BAAANQAECgQIDAAAAA==.',
Gi='Gilox:BAABNQAECn8iAAIiAAgKAA9tGQBEAQAiAAgKAA9tGQBEAQAAAA==.',
Gl='Glossu:BAAANQADCgIIAgAAAA==.',
Gn='Gndmexia:BAAANQAECggIBwAAAA==.Gneiss:BAAANQAECgQIBgAAAA==.',
Go='Goldenarrow:BAAANQABCgYIDgAAAA==.Gorgilz:BAAANQADCgMICQAAAA==.Gothgirldemi:BAABNQAECn81AAIWAAkK6SBODgDtAgAWAAkK6SBODgDtAgAAAA==.',
Gr='Graymon:BAAANQAECgUIDgAAAA==.Greebo:BAAANQAECgUIDAAAAA==.Gremsmasha:BAAANQADCggIAQAAAA==.Grist:BAAANQADCgYIDwAAAA==.',
Gu='Guatalupe:BAAANQADCgYIBgAAAA==.Guilherme:BAAANQADCggIEAAAAA==.',
Gw='Gwenyver:BAAANQAECgUIDQAAAA==.',
Ha='Hailthanatos:BAABNQAECn8bAAIbAAkKLwtIPQDOAQAbAAkKLwtIPQDOAQAAAA==.Hamord:BAAANQAECgUIEQAAAA==.Hansdelbruk:BAAANQADCggIEQAAAA==.Hardlight:BAAANQAECgcIEwAAAA==.Harliquette:BAABNQAECn8qAAINAAoKWhH1FgC1AQANAAoKWhH1FgC1AQAAAA==.Harliqynn:BAAANQAECgYIDQAAAA==.Harlock:BAABNQAECn8oAAMcAAoKhBboGgAAAgAcAAoK6RToGgAAAgAiAAcKtA9FRgCtAQAAAA==.Hashen:BAAANQAECgQIBQAAAA==.Hazelnuts:BAAANQADCgUIBQAAAA==.',
Hi='Hiten:BAABNQAECn8zAAIcAAkK0AgCJACoAQAcAAkK0AgCJACoAQAAAA==.',
Ho='Hoofinmouth:BAAANQAECgMIAwAAAA==.Hoosh:BAAANQAECgYIDwAAAA==.Hopedaimond:BAABNQAECn8hAAMOAAgKSwoWXQA0AQAOAAgKSwoWXQA0AQAIAAEKaAE6NwEYAAAAAA==.',
Hu='Huntertattoo:BAABNQAECn8gAAIXAAkKbwn/hQBkAQAXAAkKbwn/hQBkAQAAAA==.Husgus:BAAANQADCgYIDAABNQAFFAIIAgASAAAAAA==.Huungron:BAAANQADCgYIDAAAAA==.',
Ic='Icynips:BAAANQADCgQIBAAAAA==.',
Il='Illianarra:BAAANQAECgUIDQAAAA==.Ilthad:BAABNQAECn8iAAIbAAcKfw3tMgBFAQAbAAcKfw3tMgBFAQAAAA==.',
Im='Imaplantnow:BAAANQAECggICAAAAA==.Imastealnow:BAAANQABCgMIAwAAAA==.Imawarrionow:BAAANQADCgIIAgAAAA==.Imora:BAAANQADCgMIAwAAAA==.Imshalar:BAAANQABCgIIAgABNQAECgQIBAASAAAAAA==.',
In='Infurryating:BAAANQAECggIEgAAAA==.',
Ir='Iroar:BAAANQADCgIIAgAAAA==.Irumble:BAAANQAECgEIAQAAAA==.',
Is='Ischadè:BAAANQADCgUIBgAAAA==.Iskuros:BAAANQAECgIIBAAAAA==.',
It='Itsirk:BAABNQAECn8aAAIRAAgKxRT3PwDhAQARAAgKxRT3PwDhAQAAAA==.',
Iz='Izyebelle:BAABNQAECn8YAAINAAgKdwLNPACKAAANAAgKdwLNPACKAAAAAA==.',
Ja='Jadevine:BAAANQADCgEIAQAAAA==.Jalynfein:BAABNQAECn8gAAIjAAoK7QiSDACHAQAjAAoK7QiSDACHAQAAAA==.Janar:BAAANQADCgYIBwAAAA==.',
Je='Jefeorganico:BAABNQAECn8bAAQkAAcKRwiYFAABAQAkAAUKggmYFAABAQAfAAUK4QTjRwCoAAAGAAQKgQTFJAF3AAAAAA==.Jeloi:BAAANQAECgMICAAAAA==.Jenkshi:BAAANQADCgcIDQAAAA==.',
Ji='Jimmydin:BAACNQAFFH8FAAMRAAIKpBp6HABoAAARAAIKpBp6HABoAAAZAAIK0gISJwBNAAA1AAQKfzIAAxEACgomHVQhAOgCABEACgomHVQhAOgCABkACgopGDJ8ADICAAAA.',
Ju='Juego:BAAANQADCgQIBAAAAA==.Julkan:BAAANQAECgQIBgAAAA==.Junhoong:BAABNQAECn87AAIZAAoKZxHWcACuAQAZAAoKZxHWcACuAQAAAA==.Juvia:BAABNQAECn8pAAMOAAkKdxZnXQAJAgAOAAgK3hVnXQAJAgAIAAgKRg5NoQAzAQABNQAECgkJOAAlADwQAA==.',
Jy='Jynnysa:BAAANQAECgEIAQABNQAECgkJKgAlAHwbAA==.',
Ka='Kai:BAAANQAECgUIDQAAAA==.Kairoll:BAABNQAECn83AAMEAAkKnBCQZAB1AQAEAAkKnBCQZAB1AQANAAQKLBHXSgDsAAAAAA==.Kaleìna:BAAANQADCgcICAAAAA==.Kallisto:BAAANQAECgIIAgAAAA==.Karaa:BAAANQAECgUIBwAAAA==.Kariena:BAABNQAECn8gAAIXAAkKFg1ReACDAQAXAAkKFg1ReACDAQAAAA==.Kart:BAAANQADCgEIAQAAAA==.Kashaka:BAAANQADCgcIEgAAAA==.Katesluage:BAABNQAECn9IAAMjAAkK5hrMBgCOAgAjAAkK5hrMBgCOAgAeAAUKMQmwVgEBAQAAAA==.Kayyaa:BAAANQADCggICAAAAA==.',
Ke='Keeya:BAABNQAECn8oAAMLAAcK8wr5PQDvAAALAAcK8wr5PQDvAAAJAAEKKAJ9vgAeAAAAAA==.Kelina:BAAANQADCgIIAgAAAA==.Kendari:BAABNQAECn8lAAMKAAgKkQxwSgDpAAAKAAgKuQtwSgDpAAAJAAQKkAiUfAC1AAAAAA==.Kernasas:BAABNQAECn8eAAIfAAgKmQwSCgD3AAAfAAgKmQwSCgD3AAAAAA==.',
Kh='Khiari:BAAANQADCgUIBQABNQAECgoKKgAZAOEWAA==.',
Ki='Kier:BAAANQAECgMIBQAAAA==.Kizaraan:BAAANQADCgUIBQAAAA==.',
Kl='Kleyntamar:BAAANQAECgUIDAAAAA==.',
Kn='Knyghtly:BAAANQAECggIDgABNQAECgkJJAAWAFAYAA==.',
Ko='Konstantien:BAAANQAECgUIBQAAAA==.Koric:BAABNQAECn8eAAMRAAoKhwwFQADhAQARAAoKhwwFQADhAQAZAAQKlxNiIwHkAAAAAA==.Kourney:BAAANQADCgcIBwABNQAECgkJOAAlADwQAA==.',
Kr='Kretsch:BAAANQADCgUIBQABNQAECgcIEgASAAAAAA==.Krickket:BAAANQADCgMIAwABNQAECgYIHQAEAOIMAA==.',
Ku='Kupau:BAAANQAECgQICAAAAA==.Kurogami:BAABNQAECn8xAAMLAAoKkxB/VwCzAQALAAgKzhF/VwCzAQAJAAkKAA2nRgA9AQAAAA==.Kuthixo:BAAANQAECgQICQAAAA==.',
Ky='Kylos:BAAANQABCgQIBgAAAA==.Kynnigos:BAAANQABCgIIAgAAAA==.',
La='Landstrider:BAACNQAFFH8GAAIXAAMKVATHFADFAAAXAAMKVATHFADFAAA1AAQKfy8AAhcACgqlGZ5SAHgCABcACgqlGZ5SAHgCAAE1AAUUBggQABYAIw0A.Lanss:BAABNQAECn8/AAQCAAoK/x5lJACQAgACAAoKiR5lJACQAgAFAAQKjx61IgA0AQAhAAMKKB8xEgATAQAAAA==.Larachel:BAABNQAECn8bAAIEAAkKuRsSOAAlAgAEAAkKuRsSOAAlAgAAAA==.Lastaril:BAAANQADCgYIDwAAAA==.Lastword:BAAANQAECgYIDAABNQAECgcIEAASAAAAAA==.Laur:BAABNQAECn80AAINAAoKEg2OFwCuAQANAAoKEg2OFwCuAQAAAA==.',
Le='Leipäjuusto:BAABNQAECn8fAAIZAAgKYBBfqAA9AQAZAAgKYBBfqAA9AQAAAA==.',
Li='Liartes:BAAANQAECgYIDAAAAA==.Liderela:BAAANQADCgEIAQAAAA==.Lilipo:BAABNQAECn8tAAImAAkKEghJJgAuAQAmAAkKEghJJgAuAQAAAA==.',
Ll='Llarastrasza:BAAANQAECgIIAgABNQAECggICwASAAAAAA==.',
Lo='Logoth:BAAANQAECgQIBAAAAA==.Lohgarak:BAAANQADCggIFQAAAA==.',
Lu='Lunaellana:BAAANQADCgYICAAAAA==.',
Ly='Lystaan:BAAANQABCgQIBAAAAA==.',
['Lü']='Lüvpüp:BAACNQAFFH8JAAIUAAQK3RYkAwDEAAAUAAQK3RYkAwDEAAA1AAQKfx4AAhQACQqrImIFAD0DABQACQqrImIFAD0DAAAA.',
Ma='Magicfang:BAAANQADCgQIBAAAAA==.Maiku:BAABNQAECn8oAAIGAAkK1REgbAAZAgAGAAkK1REgbAAZAgAAAA==.Majo:BAAANQAECgIIAgAAAA==.Makado:BAABNQAECn8gAAQkAAoK7Af3DwBOAQAGAAkKrQYKuABeAQAkAAcKlgf3DwBOAQAfAAEKAAB0hAAmAAAAAA==.Makaris:BAAANQAECgQIBAAAAA==.Maklur:BAAANQAECgYIDwAAAA==.Makoa:BAAANQADCgQIBAAAAA==.Makoroth:BAABNQAECn8pAAIGAAoKWRJpQADhAQAGAAoKWRJpQADhAQAAAA==.Malanda:BAAANQADCgQIBAAAAA==.Malygosson:BAAANQAECgUICgAAAA==.Masharu:BAAANQADCgcIBwAAAA==.Matua:BAAANQAECgIIAgAAAA==.Maycee:BAABNQAECn8eAAIXAAgKwwmghwBgAQAXAAgKwwmghwBgAQAAAA==.',
Mc='Mcat:BAAANQAECgUIDgAAAA==.Mcgriddle:BAAANQADCgEIAQAAAA==.Mcnaugh:BAAANQAECgQICQAAAA==.Mcsaltface:BAAANQAECgUIEQAAAA==.',
Me='Meddic:BAABNQAECn8aAAMEAAcKbALKnQDOAAAEAAcKbALKnQDOAAANAAIKQQDhjgAcAAAAAA==.Megavolt:BAABNQAECn8XAAIIAAoKPg98LwAyAgAIAAoKPg98LwAyAgAAAA==.Menarot:BAAANQAECgcIEQAAAA==.Mendais:BAAANQADCgYIDgAAAA==.Messia:BAAANQADCgEIAQAAAA==.Meztlitotol:BAABNQAECn8YAAMTAAcKhCCQDQCNAgATAAcKhCCQDQCNAgAVAAEKAACQQAA5AAABNQAECgoKPAAFAAodAA==.',
Mi='Mirosdrigo:BAAANQADCgcIBwAAAA==.Mirosmundo:BAACNQAFFH8KAAIHAAMKzQ9TBADOAAAHAAMKzQ9TBADOAAA1AAQKfzIAAgcACgooHDAIAK0CAAcACgooHDAIAK0CAAAA.Mistfit:BAABNQAECn8bAAIPAAkKyQzPFgBVAQAPAAkKyQzPFgBVAQAAAA==.Miyu:BAABNQAECn87AAMNAAoKbRJiJwDwAQANAAkKog9iJwDwAQAEAAoK9QVUYQCBAQAAAA==.',
Mo='Mod:BAABNQAECn83AAMIAAkK1BvFRQBKAgAIAAkK1BvFRQBKAgAOAAEKAABJRAEsAAAAAA==.Moeng:BAAANQADCgIIAgAAAA==.Moggatorash:BAAANQAECgYIEgAAAA==.Mogtham:BAABNQAECn89AAITAAkK5hRaFwCXAQATAAkK5hRaFwCXAQAAAA==.Moisticklez:BAAANQAECgYIBgAAAA==.Monlaferte:BAABNQAECn8VAAIlAAkKUxl7DgANAgAlAAkKUxl7DgANAgAAAA==.Montsegur:BAAANQADCggICAAAAA==.Mooforn:BAABNQAECn8UAAMLAAYKrw2lRADOAAALAAYKrw2lRADOAAAKAAEKBxMLkAA3AAAAAA==.Moonfall:BAABNQAECn8bAAIDAAYKHhJ2PwBPAQADAAYKHhJ2PwBPAQAAAA==.Moosader:BAABNQAECn8VAAMZAAcKmg91zQCBAQAZAAcKmg91zQCBAQARAAcKOQganABPAQAAAA==.Morellea:BAAANQAECgUJCgAAAA==.Morighann:BAABNQAECn82AAIXAAoKdCEBKgBsAgAXAAoKdCEBKgBsAgAAAA==.Moñgoose:BAAANQADCgMIAwAAAA==.',
My='Mynkx:BAABNQAECn8qAAIZAAoK4RYwUAAGAgAZAAoK4RYwUAAGAgAAAA==.Mythyras:BAABNQAECn8qAAMlAAkKfBsdFABkAgAlAAkKWhsdFABkAgAZAAEK5hOgWAFCAAAAAA==.',
Na='Naeomy:BAABNQAECn8/AAIiAAoKHQieFwBSAQAiAAoKHQieFwBSAQAAAA==.Nahaman:BAAANQAECgUIEAAAAA==.Napolien:BAABNQAECn84AAMlAAkKPBDqJAAUAQAlAAgKPBDqJAAUAQARAAMKrA8D7ACpAAAAAA==.Naugan:BAAANQADCgEIAQAAAA==.',
Ne='Nechahira:BAACNQAFFH8QAAIWAAYKIw0aBwBHAQAWAAYKIw0aBwBHAQA1AAQKfyMAAxYACgrCFXARAGkCABYACgrCFXARAGkCABMAAQoAAFt8AAAAAAAA.Nethim:BAAANQAECgUIDQAAAA==.Nezana:BAAANQAECgIIAgAAAA==.',
Ni='Nien:BAAANQAECgMIAwABNQAECgUIAgASAAAAAA==.Nightfallen:BAAANQAECgQIBwAAAA==.Nihlathak:BAAANQAECgYIDAAAAA==.Ninada:BAABNQAECn8gAAMeAAoKPgqbqAAoAQAeAAoKPgmbqAAoAQAjAAIKcgifQwA8AAAAAA==.Ninalee:BAAANQAECgcICQAAAA==.Ninefallen:BAAANQAECgMIBQAAAA==.',
No='Noranna:BAABNQAECn8UAAIXAAYKgAcy6QCfAAAXAAYKgAcy6QCfAAAAAA==.',
Ny='Nyim:BAAANQAECgEIAQAAAA==.Nymiria:BAAANQABCgEIAQABNQAECgYIHQAEAOIMAA==.Nynsyn:BAABNQAECn8XAAMHAAcKzxrtCwBAAQAHAAYKNR/tCwBAAQAmAAEKNgl0UwAzAAABNQAECgkJKgAlAHwbAA==.Nyxeira:BAAANQAECgYICgAAAA==.',
['Nâ']='Nâli:BAAANQAECgQIBAAAAA==.',
Ob='Obsidianclaw:BAAANQADCgIIAwAAAA==.',
Oh='Ohthesemyboo:BAAANQAECgQICgAAAA==.Ohwellz:BAAANQAECgEIAQAAAA==.',
Ol='Olehei:BAAANQAECgEIAQAAAA==.',
Op='Ophin:BAABNQAECn89AAILAAoKuhq4DgBpAgALAAoKuhq4DgBpAgAAAA==.',
Pa='Panamared:BAABNQAECn8tAAIcAAkKAxWLFgAtAgAcAAkKAxWLFgAtAgAAAA==.Pappawoody:BAABNQAECn8cAAICAAgKCBxkbwBFAgACAAgKCBxkbwBFAgAAAA==.Parishealton:BAAANQADCgcIBwAAAA==.',
Pe='Pellegryn:BAAANQADCgYICQAAAA==.Pennyfeather:BAABNQAECn88AAMEAAkKfhFvUQC7AQAEAAkKfhFvUQC7AQANAAQKygkUUgDHAAAAAA==.Pezza:BAABNQAECn8eAAIIAAkKJRADWACCAQAIAAkKJRADWACCAQAAAA==.',
Ph='Phaze:BAABNQAECn8wAAInAAgKZyBPBACkAgAnAAgKZyBPBACkAgAAAA==.Phideauxe:BAAANQAECgQIBQAAAA==.Phorate:BAAANQAECgcIDwAAAA==.',
Pl='Pluralbutter:BAABNQAECn8bAAIbAAoKqA2iPADSAQAbAAoKqA2iPADSAQAAAA==.',
Po='Popexeo:BAAANQAECgcIDQABNQAFFAcIEAAWAGwRAA==.',
Pr='Prometheum:BAAANQAECgcIEAAAAA==.',
Ps='Psyvern:BAABNQAECn8sAAIQAAkKOwg3DgBkAQAQAAkKOwg3DgBkAQAAAA==.',
Qt='Qtkat:BAAANQADCgMIAwABNQAECgUIDQASAAAAAA==.',
Qu='Quiccerstorm:BAAANQADCgQIBQAAAA==.',
Ra='Raevennlumis:BAABNQAECn8ZAAIZAAkK1ggp5gBPAQAZAAkK1ggp5gBPAQAAAA==.Raevenns:BAAANQADCggJCAABNQAECgkJGQAZANYIAA==.Rahkhard:BAABNQAECn89AAMHAAoKQyB2AwBaAwAHAAoKCiB2AwBaAwAmAAkKLBoNFwDHAQAAAA==.Rascdit:BAAANQAECgUICgAAAA==.',
Re='Recreant:BAAANQAECggIEAAAAA==.Reiyoso:BAAANQAECgIIAgAAAA==.Reui:BAAANQAECgIIAgAAAA==.',
Rh='Rhemibumbum:BAAANQAECgUICwAAAA==.',
Ro='Roberey:BAAANQAECgUICgAAAA==.Rocketbilly:BAAANQADCgIIAgAAAA==.Roobee:BAABNQAECn8mAAIfAAkK0gNvEQCyAAAfAAkK0gNvEQCyAAAAAA==.',
Ru='Ruaic:BAAANQAECgEIAQAAAA==.',
Sa='Sableanne:BAAANQAECgEIAQAAAA==.Sacréd:BAABNQAECn8ZAAIlAAcKCxcSLAB8AQAlAAcKCxcSLAB8AQAAAA==.Sarkan:BAAANQADCggIEQAAAA==.Sarova:BAABNQAECn8dAAIXAAkKhBQukgDkAQAXAAkKhBQukgDkAQAAAA==.Satori:BAAANQAECgUIDgAAAA==.',
Sc='Scalewind:BAAANQADCgYIBgAAAA==.',
Se='Seldeath:BAAANQADCgEJAQAAAA==.Selfu:BAABNQAECn82AAImAAkKPhYSGAC6AQAmAAkKPhYSGAC6AQAAAA==.Sellidor:BAABNQAECn8+AAIXAAoKeCQwDAAUAwAXAAoKeCQwDAAUAwAAAA==.Serenesong:BAAANQADCgEIAQAAAA==.Seriniyaa:BAAANQAECgQICQAAAA==.Serioth:BAAANQADCgIIAgAAAA==.',
Sh='Sheara:BAAANQAECggIEgAAAA==.Shinjiro:BAABNQAECn8kAAIZAAgKAQJhTQGkAAAZAAgKAQJhTQGkAAAAAA==.Shirito:BAABNQAECn9EAAMLAAkKgSQCCwBjAwALAAgKVSUCCwBjAwAJAAkK6yNhCwA9AwAAAA==.Shiritodh:BAABNQAECn8lAAIDAAkKcCBRFQC6AgADAAkKcCBRFQC6AgAAAA==.Shockin:BAAANQAECgcIDAAAAA==.Shortnstout:BAACNQAFFH8OAAIlAAQKtxrCBADZAAAlAAQKtxrCBADZAAA1AAQKfywAAyUACgpfImgLAOICACUACgpfImgLAOICABkABQpTGjIMAZ8AAAAA.Shugo:BAABNQAECn8cAAInAAYKQQx4CgBuAQAnAAYKQQx4CgBuAQAAAA==.',
Si='Sienje:BAABNQAECn8qAAIZAAoKoxVgdABFAgAZAAoKoxVgdABFAgAAAA==.Sigma:BAABNQAECn8qAAIXAAoKagcagwBqAQAXAAoKagcagwBqAQAAAA==.Simpleson:BAABNQAECn84AAMGAAoKFB2XJwBIAgAGAAkKmh2XJwBIAgAfAAEKbhlnagBMAAAAAA==.Sinbàd:BAACNQAFFH8KAAIDAAUKMxQPBwCeAQADAAUKMxQPBwCeAQA1AAQKfzwAAgMACgo6IXwJAJ4CAAMACgo6IXwJAJ4CAAAA.Sinistris:BAAANQAECgQIBQAAAA==.',
Sk='Skie:BAABNQAECn8YAAMdAAgKVQ2dGwAIAQAdAAcKLg+dGwAIAQAUAAYKrgWiFQCwAAABNQAECgkJJAAWAFAYAA==.Skrabble:BAAANQAECgQIDgAAAA==.Skölldraugos:BAAANQAECgEIAQAAAA==.',
Sl='Slaete:BAABNQAECn8cAAIbAAcK1gSTYAD6AAAbAAcK1gSTYAD6AAAAAA==.Slush:BAAANQAECgQIBAAAAA==.',
Sm='Smallz:BAAANQAECgYIEwABNQAECgkJLQAXAPYVAA==.Smorgas:BAAANQAECgQICQABNQAECgoKNgAZALYfAA==.Småug:BAAANQADCgMIAwAAAA==.',
So='Solemn:BAABNQAECn80AAINAAkK3BbyEgDzAQANAAkK3BbyEgDzAQABNQAECgoKPgAXAHgkAA==.Solrana:BAAANQAECgQICQAAAA==.Songmistress:BAABNQAECn8ZAAIGAAkK5AVexwA7AQAGAAkK5AVexwA7AQAAAA==.Sorren:BAAANQAECgUIBQAAAA==.Sotta:BAAANQAECgIIBQAAAA==.Sozin:BAAANQADCgIIAgAAAA==.',
Sp='Spritmoon:BAAANQADCgYIBgAAAA==.',
Sq='Squeezee:BAAANQADCggICAAAAA==.',
St='Stardrive:BAABNQAECn8hAAIIAAoKaBn/GgCyAgAIAAoKaBn/GgCyAgAAAA==.Stevesteve:BAABNQAECn8uAAIGAAkKSA6xRgDLAQAGAAkKSA6xRgDLAQAAAA==.Stroganov:BAAANQAECgYIDQABNQAECgcIEgASAAAAAA==.Stumpii:BAAANQADCgQIBAAAAA==.',
Su='Sunasha:BAAANQADCgYIEgAAAA==.Superbautumn:BAABNQAECn8aAAIZAAcK8xtVkgBnAQAZAAcK8xtVkgBnAQAAAA==.',
Sy='Synge:BAABNQAECn8fAAMeAAYKJw9DvQACAQAeAAYKJg9DvQACAQAjAAEK9AfLSgAwAAAAAA==.Synnyca:BAAANQAECgUIBQABNQAECgkJKgAlAHwbAA==.',
['Sé']='Sélune:BAAANQAECggICwAAAA==.',
['Sï']='Sïnbad:BAAANQAFFAIIAgABNQAFFAUICgADADMUAA==.',
Ta='Tachyon:BAAANQAECgYICAABNQAFFAQICQAUAN0WAA==.Taeonaki:BAAANQAECgMIBwAAAA==.Tagnaras:BAAANQAECgcIDgAAAA==.Tagnaris:BAAANQAECgUIBQAAAA==.Tahlang:BAAANQABCggICgAAAA==.Tali:BAAANQAECgUIDwAAAA==.Taliasluage:BAAANQADCggICAABNQAECgkJSAAjAOYaAA==.Tangle:BAABNQAECn8kAAMWAAkKUBhXKADdAQAWAAcKCRlXKADdAQABAAcKfAaOXACGAAAAAA==.Tanka:BAABNQAECn8tAAICAAkK5h2QWwB5AgACAAkK5h2QWwB5AgAAAA==.Tannisse:BAAANQADCggIFQAAAA==.Tanuki:BAAANQAECgUIBQAAAA==.Tapol:BAAANQAECgUIEgABNQAECgYIHQAEAOIMAA==.Tashlaraz:BAEANQAECgUICgAAAA==.Tasi:BAAANQAECgQIBAAAAA==.Taurannosaur:BAAANQADCggIDAAAAA==.Taurentots:BAABNQAFFH8JAAIKAAUKkRWsDwDLAAAKAAUKkRWsDwDLAAAAAA==.',
Te='Telkas:BAAANQAECgEIAgAAAA==.Temporantus:BAAANQAECgUIBQAAAA==.Tenko:BAABNQAECn82AAMeAAkKeAo+fQCBAQAeAAkK0Ak+fQCBAQAjAAIKdAzaNQBkAAAAAA==.',
Th='Thaddeus:BAAANQAECgUIDwAAAA==.Therm:BAACNQAFFH8QAAIZAAYKJBzgBQD4AQAZAAYKJBzgBQD4AQA1AAQKf1cAAxkACgrrJssAAJADABkACgrrJssAAJADABEAAQrQBwQgATYAAAAA.Thoramier:BAAANQAECgYIEgAAAA==.',
Ti='Tibble:BAAANQAECgYIEwAAAA==.Timoonja:BAAANQAECgUIEAAAAA==.Tirazlea:BAAANQADCgIIAgAAAA==.',
To='Tonatuih:BAABNQAECn9HAAIbAAoKLCC8DACyAgAbAAoKLCC8DACyAgAAAA==.',
Tr='Trezzia:BAABNQAECn8kAAIkAAkK6BTLBgA6AgAkAAkK6BTLBgA6AgAAAA==.Triipod:BAAANQADCgYIIwAAAA==.Trinkat:BAAANQAECgUIDQAAAA==.Trojinn:BAAANQAECgUIBQAAAA==.Tryst:BAAANQADCgYIBgAAAA==.Tráson:BAAANQADCgYIBQAAAA==.',
Tu='Tub:BAABNQAECn8gAAIeAAgKnQn7mwBAAQAeAAgKnQn7mwBAAQAAAA==.',
Ty='Tylean:BAAANQAECgQICgAAAA==.',
['Tì']='Tìríon:BAAANQABCgEIAQAAAA==.',
Ud='Udukai:BAAANQAECgQIBAAAAA==.',
Ul='Ultrastealth:BAABNQAECn8ZAAQcAAUK6ga9PADSAAAcAAUKAAa9PADSAAAiAAQKdgRTkQBtAAAoAAIKtgOXCwAnAAAAAA==.',
Um='Umbrum:BAAANQADCgIIAgABNQAECgoKPAAFAAodAA==.',
Uu='Uu:BAAANQAECggIEQAAAA==.',
Va='Vadrozsa:BAAANQAECgQICQAAAA==.Vallarie:BAAANQADCgQJBAAAAA==.Vareyn:BAAANQAECgMIAwAAAA==.',
Vo='Vorth:BAABNQAECn87AAIJAAoKYRHaKwDFAQAJAAoKYRHaKwDFAQAAAA==.Vorukh:BAAANQADCgQIBAABNQAECgIIBAASAAAAAA==.Vorúkh:BAAANQAECgcIEgABNQAECgIIBAASAAAAAA==.Vorükh:BAAANQAECgYIBgABNQAECgIIBAASAAAAAA==.',
Vu='Vulturous:BAAANQADCgYICgAAAA==.',
Vy='Vydian:BAAANQADCgYICQAAAA==.Vyrlana:BAAANQAECgEIAQAAAA==.',
Wa='Waldir:BAABNQAECn87AAMRAAkKVyR4CgBbAwARAAkKVyR4CgBbAwAZAAMKkArcQwFZAAAAAA==.Walock:BAAANQADCgMIAwAAAA==.Wanted:BAAANQADCgYIBgAAAA==.Watz:BAABNQAECn8cAAIXAAoKRwlPXwDDAQAXAAoKRwlPXwDDAQAAAA==.',
We='Wensa:BAAANQAECgYIBgAAAA==.',
Wh='Wholesale:BAABNQAECn82AAIKAAgK7BZjMQBcAQAKAAgK7BZjMQBcAQAAAA==.',
Wr='Wrack:BAAANQADCggIEgAAAA==.Wraithian:BAAANQABCgQIBAAAAA==.Wratsoul:BAABNQAECn8hAAIGAAoKNg5ifgDqAQAGAAoKNg5ifgDqAQAAAA==.',
Xe='Xessala:BAABNQAECn8lAAIIAAgKIhiUUAAjAgAIAAgKIhiUUAAjAgAAAA==.',
Xh='Xheero:BAABNQAECn86AAIXAAkK5x2bJAAEAwAXAAkK5x2bJAAEAwAAAA==.Xheerom:BAAANQADCgUIBQAAAA==.',
Ya='Yagiashi:BAAANQAECgUICgABNQAECgoKPAAFAAodAA==.',
Yu='Yulica:BAAANQAECgUIDgAAAA==.',
Za='Zaffy:BAABNQAECn8wAAIfAAgKdg8uBwA0AQAfAAgKdg8uBwA0AQAAAA==.Zaktrix:BAAANQAECgIIAgAAAA==.Zaleron:BAAANQADCggIFAAAAA==.Zaruba:BAABNQAECn8tAAMOAAkKHQhGhgCVAQAOAAkKHQhGhgCVAQAIAAEKsAEg+gAYAAABNQAECgkJLwABANIKAA==.Zatkyng:BAABNQAECn8pAAImAAoK1A9xHwBqAQAmAAoK1A9xHwBqAQAAAA==.',
Ze='Zekos:BAAANQAECgEIAQAAAA==.',
Zi='Zillver:BAAANQAECgUIBQABNQAECgkJOAAlADwQAA==.Zimdalar:BAABNQAECn8dAAIHAAYKbBeMDwD7AAAHAAYKbBeMDwD7AAAAAA==.',
Zo='Zomi:BAAANQABCgMIAwAAAA==.',
Zu='Zulre:BAABNQAECn86AAMKAAoKuRtkGwDUAgAKAAoKkRtkGwDUAgAJAAUKnw1qYgDRAAAAAA==.',
['Ôv']='Ôverkill:BAABNQAECn8eAAITAAkKzhZDFwD5AQATAAkKzhZDFwD5AQAAAA==.',
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
