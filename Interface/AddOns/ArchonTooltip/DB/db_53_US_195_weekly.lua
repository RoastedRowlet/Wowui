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

local lookup = {'Druid-Balance','Warrior-Arms','DemonHunter-Devourer','Priest-Holy','Warrior-Protection','Warlock-Demonology','Monk-Brewmaster','Shaman-Restoration','DeathKnight-Frost','DeathKnight-Blood','DeathKnight-Unholy','Priest-Shadow','Shaman-Elemental','Monk-Mistweaver','Evoker-Augmentation','Unknown-Unknown','Druid-Guardian','Evoker-Devastation','Druid-Feral','Druid-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Paladin-Holy','DemonHunter-Vengeance','DemonHunter-Havoc','Rogue-Subtlety','Evoker-Preservation','Mage-Arcane','Warlock-Destruction','Priest-Discipline','Warrior-Fury','Rogue-Assassination','Mage-Frost','Warlock-Affliction','Paladin-Protection','Monk-Windwalker','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Ackrenoth:BAAANQAECgQIBAAAAA==.',
Ad='Adynn:BAABNQAECn9BAAIBAAoKNyXoBACyAwABAAoKNyXoBACyAwAAAA==.',
Ae='Aermoss:BAAANQABCgUIBQAAAA==.Aeru:BAAANQADCgYIBgAAAA==.Aethreal:BAAANQAFFAEIAQAAAA==.',
Af='Afridium:BAAANQADCgEIAQAAAA==.',
Ak='Akikusa:BAAANQADCggICgAAAA==.',
Al='Alderath:BAAANQABCgQJBQAAAA==.Alista:BAABNQAECn87AAICAAoKyiRNCgCjAwACAAoKyiRNCgCjAwAAAA==.Allyeska:BAAANQADCgcIDQAAAA==.Alnharaelune:BAAANQADCgYIDQAAAA==.',
Am='Amarea:BAAANQAECgIIAgAAAA==.Amor:BAABNQAECn8fAAIDAAcK2hizFwB9AQADAAcK2hizFwB9AQAAAA==.',
An='Anali:BAABNQAECn8WAAIEAAkKVRMtSwBEAgAEAAkKVRMtSwBEAgAAAA==.Anani:BAAANQAECgQIBAAAAA==.Angreifer:BAABNQAECn87AAMFAAoKCh3cAwCOAgAFAAoKCh3cAwCOAgACAAIKvAP9PgFVAAAAAA==.Anoana:BAAANQADCgQIBAAAAA==.Anori:BAABNQAECn8jAAIBAAgKbwtRLgAeAQABAAgKbwtRLgAeAQAAAA==.',
Ao='Aonar:BAAANQAECgMICQAAAA==.',
Aq='Aqua:BAAANQABCgcIEwAAAA==.',
Ar='Arc:BAABNQAECn8oAAIGAAoKMB4OEACpAgAGAAoKMB4OEACpAgABNQAECgoKPQAHAEMgAA==.Arcanimous:BAAANQADCggIDAAAAA==.Archenteron:BAAANQAECgQIBQAAAA==.Archnunin:BAAANQAECggICAAAAA==.Ardorcinder:BAAANQAECgQICAAAAA==.Argentur:BAAANQADCgEIAQAAAA==.Arkaan:BAAANQADCgUIBQABNQAECgYIGgAIAPAfAA==.Armangaria:BAAANQAECggICAAAAA==.Arrohon:BAAANQAECgcIBwAAAA==.Arrozz:BAAANQADCgQIBAAAAA==.Arthmanafel:BAABNQAECn8lAAQJAAoKphk/KQBPAgAJAAoK9Rg/KQBPAgAKAAEKqR9btQBeAAALAAEKJQu54gAxAAAAAA==.',
As='Asbjorne:BAAANQAECgQIDAAAAA==.',
At='Atryssa:BAAANQAECgUIBQAAAA==.',
Au='Audi:BAAANQADCgMIAwAAAA==.Autumnmoon:BAAANQAECgUIEAAAAA==.',
Av='Avalsong:BAABNQAECn89AAIDAAoKvh1KDgAEAwADAAoKvh1KDgAEAwAAAA==.Avelos:BAACNQAFFH8HAAIEAAMK8w1cFgDQAAAEAAMK8w1cFgDQAAA1AAQKfzAAAwQACgqmHnAjAOACAAQACgqmHnAjAOACAAwAAQrtCv5KAC4AAAAA.',
Ay='Ayowenn:BAAANQADCgIIAgAAAA==.Ayzmist:BAABNQAECn8lAAINAAcKhAlTXQD1AAANAAcKhAlTXQD1AAAAAA==.Ayzmyth:BAABNQAECn8uAAMOAAoK6hC9DADGAQAOAAoK6hC9DADGAQAHAAUKJwQ4IgDIAAAAAA==.',
Az='Azurelight:BAAANQADCgMIAwAAAA==.',
Ba='Banthapooduu:BAAANQADCggIGwAAAA==.',
Be='Beasic:BAABNQAECn8zAAMNAAkKigQ2owBPAQANAAkKigQ2owBPAQAIAAIKMwKeuwBFAAAAAA==.Beastmode:BAAANQAECgUICgAAAA==.Beletili:BAABNQAECn8rAAIEAAoK/hE0ZADzAQAEAAoK/hE0ZADzAQAAAA==.Bellissimio:BAAANQADCgUICAABNQAECgkJJQAIAHsRAA==.Bener:BAAANQADCgcIBwAAAA==.Beátrix:BAAANQADCgIIAgAAAA==.',
Bi='Bismuth:BAAANQAECgMIBQAAAA==.',
Bl='Blackraven:BAAANQAECgYIBgAAAA==.Blatendrg:BAABNQAECn82AAIPAAkKwxJhCAARAgAPAAkKwxJhCAARAgAAAA==.Blindcloud:BAAANQAECgUICQAAAA==.',
Bo='Boot:BAAANQAECgUIEgAAAA==.Borodemonin:BAEBNQAECn8rAAIDAAkKVyb1AgCrAwADAAkKVyb1AgCrAwAAAA==.',
Br='Breae:BAABNQAECn8zAAMEAAkKLxUkOADXAQAEAAkKLxUkOADXAQAMAAUKIQTnWQCgAAAAAA==.Brieanna:BAAANQADCgUIBgAAAA==.Bristia:BAAANQAECgUIBwAAAA==.Brueggar:BAAANQAECgEIAgAAAA==.Brutyl:BAAANQAECgEIAQABNQAECggIEAAQAAAAAA==.',
Bu='Bulky:BAAANQAECgIIAgAAAA==.',
By='Byegone:BAAANQAECgQIDAAAAA==.',
Ca='Cadforus:BAAANQADCgcIEAABNQAECggIGwARAGsWAA==.Cafë:BAAANQADCgcICgABNQAFFAQICQASAN0WAA==.Caicee:BAAANQADCgQIBAAAAA==.Caistin:BAAANQADCgYIDgAAAA==.Calyma:BAAANQAECgIIBAAAAA==.Camelsotters:BAABNQAECn8XAAUTAAUKEAdHMQCJAAATAAQKnQVHMQCJAAARAAUK7wVBSgCCAAAUAAQKwQIqRgB0AAABAAIKWQGmugAmAAAAAA==.Casca:BAAANQAECgUICwAAAA==.Catsclaw:BAAANQADCgYICQAAAA==.',
Ce='Cenjeru:BAABNQAECn8eAAMJAAgKfhdHPADdAQAJAAgKHRVHPADdAQALAAYKnBclZwB1AQAAAA==.',
Ch='Chezzie:BAAANQAECgYICwAAAA==.Chiot:BAABNQAECn8sAAIFAAkKJRz5CQCnAgAFAAkKJRz5CQCnAgAAAA==.',
Ci='Cimerian:BAAANQAECgIIBAAAAA==.',
Cl='Clone:BAAANQADCgYIBgAAAA==.Cloudysky:BAAANQAECgUIBQAAAA==.',
Co='Cobalticus:BAAANQAECgQIBAAAAA==.Concealer:BAAANQADCgEIAQAAAA==.Conejamala:BAABNQAECn8tAAMVAAoK5R4fFgBDAwAVAAoK5R4fFgBDAwAWAAMKUw6PXwCoAAAAAA==.Corange:BAAANQABCgIIBAAAAA==.Cordini:BAAANQAECgQICAAAAA==.Corlock:BAAANQAECgIIAgAAAA==.Cormech:BAAANQAECgQIBgAAAA==.Cornite:BAAANQADCgYIDgAAAA==.',
Cr='Crizzo:BAABNQAECn8zAAIVAAoKThz0GACRAgAVAAoKThz0GACRAgAAAA==.',
Da='Daddyslilgrl:BAAANQAECgMIBQAAAA==.Dakra:BAEBNQAECn8XAAICAAcKCxkzjQD7AQACAAcKCxkzjQD7AQAAAA==.Dalamar:BAAANQAECggIIAABNQAFFAIIBQAMAOcLAQ==.Dalandis:BAABNQAECn8sAAMXAAoKQR3bNgAdAgAXAAkKmR/bNgAdAgAYAAcKuxXtLwDlAQAAAA==.Dalyeth:BAABNQAECn8lAAMZAAkKQiWGBAD8AgAZAAkKQiWGBAD8AgAaAAEKAAAumwAoAAAAAA==.Darianno:BAAANQADCgMIAwAAAA==.Darkwingorc:BAABNQAECn88AAIVAAoKOR9fIQASAwAVAAoKOR9fIQASAwAAAA==.Darkwulf:BAAANQADCgcJDQAAAA==.Daunt:BAAANQADCgcIDgABNQAECggIJgABAE8KAA==.Dawnfire:BAAANQADCgEIAQAAAA==.Dawnmane:BAAANQADCgEIAQAAAA==.',
De='Deadsecsi:BAAANQABCgEIAQAAAA==.Decypher:BAAANQAECgUICgABNQAECgoKNwAbABITAA==.Deebz:BAABNQAECn8fAAIUAAcKNBZvKQDTAQAUAAcKNBZvKQDTAQAAAA==.Deliverance:BAACNQAFFH8FAAIMAAIK5wvSCgCXAAAMAAIK5wvSCgCXAAA1AAQKfzkAAgwACgp6HJcJAF4CAAwACgp6HJcJAF4CAAAA.Demigoth:BAABNQAECn8hAAIcAAcKJROcIgC0AQAcAAcKJROcIgC0AQAAAA==.Denethmon:BAAANQAECgEJAQABNQAECgQICAAQAAAAAA==.Dentik:BAABNQAECn80AAMTAAcKWg8KHgAsAQATAAYK5wsKHgAsAQAUAAcKYA+YPwApAQAAAA==.Denuma:BAAANQAECgMIAwAAAA==.Devilina:BAAANQADCggICgAAAA==.Deàdpool:BAAANQADCgQIBgAAAA==.',
Dh='Dheriana:BAABNQAECn83AAIbAAoKEhOrFQA2AgAbAAoKEhOrFQA2AgAAAA==.Dherisis:BAAANQAECgMIAwABNQAECgoKNwAbABITAA==.Dherli:BAAANQAECgMIBAABNQAECgoKNwAbABITAA==.',
Di='Diamair:BAABNQAECn8pAAIdAAgK8w0zfQBIAQAdAAgK8w0zfQBIAQAAAA==.Disney:BAAANQAECggICAAAAA==.Divynelle:BAAANQABCgIIAgAAAA==.Dixiee:BAAANQAECgQIEwABNQAECgUIEAAQAAAAAA==.',
Dn='Dnegelpal:BAABNQAECn8tAAIXAAgKQQ9jhQBGAQAXAAgKQQ9jhQBGAQAAAA==.',
Do='Dodgecharger:BAAANQAECgUICwAAAA==.',
Dr='Dragerin:BAAANQAECgMIAwAAAA==.Dragonfood:BAAANQAECgMIBAAAAA==.Drakilu:BAABNQAECn81AAIVAAkKQRYgPADxAQAVAAkKQRYgPADxAQAAAA==.Drakra:BAEANQAECgYICgABNQAECgcIFwACAAsZAA==.Drasic:BAABNQAECn9EAAIUAAoKBB9kCQAvAwAUAAoKBB9kCQAvAwAAAA==.Dreamcloud:BAAANQADCgYICAAAAA==.Dreddscott:BAAANQAECgYIBgABNQAECgkJLAAbAAMVAA==.Dretro:BAAANQAECgIIBQAAAA==.Drovosi:BAAANQADCggIIgAAAA==.',
Du='Durin:BAABNQAECn8qAAICAAgKOwnlewAdAQACAAgKOwnlewAdAQAAAA==.Durward:BAABNQAECn8cAAMKAAgKOhRpWgCJAQAKAAcKQBBpWgCJAQALAAYKqRTmMQD+AAAAAA==.Duvo:BAABNQAECn8oAAIVAAkKwBV1bwAzAgAVAAkKwBV1bwAzAgAAAA==.',
Dw='Dwarvey:BAAANQADCgUIBQAAAA==.',
['Dæ']='Dæmôna:BAAANQADCgQIBQAAAA==.',
['Dé']='Détank:BAABNQAECn80AAIJAAgKhht4IADJAQAJAAgKhht4IADJAQAAAA==.',
Ea='Easyname:BAABNQAECn8tAAIXAAoKuBbtNAAlAgAXAAoKuBbtNAAlAgAAAA==.',
Ei='Eiene:BAAANQAECgUICQAAAA==.Eithetala:BAAANQADCgYICAAAAA==.',
El='Elemental:BAAANQAECggIDQABNQAFFAYIEAAUACMNAA==.Ellohir:BAAANQABCgIIAgAAAA==.Elloseth:BAAANQAECgUIDgAAAA==.Elmorin:BAAANQAECgQICAAAAA==.Eluneh:BAAANQADCgYICAAAAA==.',
Eo='Eolon:BAAANQAECgUIDwAAAA==.',
Ep='Epica:BAABNQAECn8xAAIdAAoKMw6wWwCaAQAdAAoKMw6wWwCaAQAAAA==.',
Er='Eragonhawk:BAAANQAECgMICAAAAA==.Eraina:BAAANQAECgMIAwAAAA==.Eroldan:BAAANQADCgYICQAAAA==.Erovianoria:BAAANQAECgcIEQAAAA==.',
Es='Essun:BAABNQAECn8eAAIaAAkKrBmOJwBhAgAaAAkKrBmOJwBhAgABNQAFFAUICQAGAC8HAA==.',
Ev='Evanthe:BAABNQAECn8lAAMIAAkKexHpQQCPAQAIAAkKexHpQQCPAQANAAEKAADSWwEeAAAAAA==.',
Ex='Expire:BAAANQADCgEIAQAAAA==.',
Ez='Ezro:BAAANQADCgYICAAAAA==.',
Fa='Faizor:BAAANQAECgEIAgAAAA==.Fastal:BAAANQADCgcIFwAAAA==.Fatalfury:BAAANQAECggIBAAAAA==.Fauxborn:BAAANQAECgYIDQAAAA==.Fauxstorm:BAAANQADCgQIBQAAAA==.',
Fe='Fedwell:BAABNQAECn8gAAIXAAgKpgvX0wB0AQAXAAgKpgvX0wB0AQAAAA==.',
Fi='Finluc:BAAANQAECgcICAAAAA==.Finngan:BAABNQAECn8pAAIeAAgKmgmzCADjAAAeAAgKmgmzCADjAAAAAA==.Fitoria:BAAANQAECgMICAABNQAECgoKPQAHAEMgAA==.',
Fo='Forestkin:BAAANQAECgUIDwABNQAECgkJJQAZAEIlAA==.Foxhope:BAAANQAECgUIEAAAAA==.',
Fr='Friartuk:BAAANQAECgEIAQAAAA==.Frozenthunda:BAABNQAECn83AAIdAAkKngx/YgCHAQAdAAkKngx/YgCHAQAAAA==.',
Fu='Furna:BAABNQAECn8jAAIfAAkKDg1ODQBeAQAfAAkKDg1ODQBeAQAAAA==.Fuzzyhooves:BAABNQAECn8vAAMYAAkK7yEEEwA5AwAYAAkK7yEEEwA5AwAXAAEK0wdrpgE0AAAAAA==.',
Ga='Gabrael:BAACNQAFFH8FAAMgAAIKCwkYAwBFAAAgAAEKoA8YAwBFAAACAAIKXAHhKQAwAAA1AAQKfzMAAyAACgr0EF8NAOEBACAACQr9EF8NAOEBAAIACQokDTytAKwBAAAA.',
Gh='Ghorienge:BAAANQAECgQIDAAAAA==.',
Gi='Gilox:BAABNQAECn8iAAIhAAgKAA9DFABZAQAhAAgKAA9DFABZAQAAAA==.',
Gl='Glossu:BAAANQADCgIIAgAAAA==.',
Gn='Gndmexia:BAAANQADCggIFAAAAA==.Gneiss:BAAANQAECgMIBQAAAA==.',
Go='Goldenarrow:BAAANQABCgYIDgAAAA==.Gorgilz:BAAANQADCgMICQAAAA==.Gothgirldemi:BAABNQAECn81AAIUAAkK6SBODgDtAgAUAAkK6SBODgDtAgAAAA==.',
Gr='Graymon:BAAANQAECgMICQAAAA==.Greebo:BAAANQAECgMICQAAAA==.Gremsmasha:BAAANQADCggIAQAAAA==.Grist:BAAANQADCgYIDwAAAA==.',
Gu='Guatalupe:BAAANQADCgYIBgAAAA==.Guilherme:BAAANQADCggIEAAAAA==.',
Gw='Gwenyver:BAAANQAECgQICAAAAA==.',
Ha='Hailthanatos:BAABNQAECn8bAAIaAAkKLwtIPQDOAQAaAAkKLwtIPQDOAQAAAA==.Hamord:BAAANQAECgQIDAAAAA==.Hansdelbruk:BAAANQADCggIDQAAAA==.Hardlight:BAAANQAECgYIDQAAAA==.Harliquette:BAABNQAECn8oAAIMAAoKkBCXEQCyAQAMAAoKkBCXEQCyAQAAAA==.Harliqynn:BAAANQAECgUIDQAAAA==.Harlock:BAABNQAECn8jAAMbAAoK9xToGgAAAgAbAAoKXBPoGgAAAgAhAAcKtA9FRgCtAQAAAA==.Hashen:BAAANQAECgQIBQAAAA==.Hazelnuts:BAAANQADCgUIBQAAAA==.',
Hi='Hiten:BAABNQAECn8qAAIbAAkKuAieRgBEAQAbAAkKuAieRgBEAQAAAA==.',
Ho='Hoofinmouth:BAAANQAECgMIAwAAAA==.Hoosh:BAAANQAECgUICgAAAA==.Hopedaimond:BAABNQAECn8cAAMNAAcKGAk4XQD1AAANAAcKGAk4XQD1AAAIAAEKaAE6NwEYAAAAAA==.',
Hu='Huntertattoo:BAABNQAECn8gAAIVAAkKbwlcYwB2AQAVAAkKbwlcYwB2AQAAAA==.Husgus:BAAANQADCgYIDAABNQAFFAIIAgAQAAAAAA==.Huungron:BAAANQADCgYIDAAAAA==.',
Ic='Icynips:BAAANQADCgQIBAAAAA==.',
Il='Illianarra:BAAANQAECgUIDQAAAA==.Ilthad:BAABNQAECn8cAAIaAAcKGAyxKQBNAQAaAAcKGAyxKQBNAQAAAA==.',
Im='Imaplantnow:BAAANQAECggICAAAAA==.Imawarrionow:BAAANQADCgIIAgAAAA==.Imora:BAAANQADCgMIAwAAAA==.Imshalar:BAAANQABCgIIAgABNQAECgQIBAAQAAAAAA==.',
In='Infurryating:BAAANQAECggIEgAAAA==.',
Ir='Iroar:BAAANQADCgIIAgAAAA==.Irumble:BAAANQADCggICgAAAA==.',
Is='Ischadè:BAAANQADCgUIBgAAAA==.Iskuros:BAAANQADCgMIAwAAAA==.',
It='Itsirk:BAAANQAECggIEwAAAA==.',
Iz='Izyebelle:BAABNQAECn8YAAIMAAgKdwJPMQCNAAAMAAgKdwJPMQCNAAAAAA==.',
Ja='Jadevine:BAAANQADCgEIAQAAAA==.Jalynfein:BAABNQAECn8WAAIiAAkKOwV8EgDnAAAiAAkKOwV8EgDnAAAAAA==.Janar:BAAANQADCgYIBwAAAA==.',
Je='Jefeorganico:BAABNQAECn8bAAQjAAcKRwiYFAABAQAjAAUKggmYFAABAQAeAAUK4QTjRwCoAAAGAAQKgQTFJAF3AAAAAA==.Jeloi:BAAANQAECgMIBgAAAA==.Jenkshi:BAAANQADCgcIDQAAAA==.',
Ji='Jimmydin:BAACNQAFFH8FAAMYAAIKpBqbFwBrAAAYAAIKpBqbFwBrAAAXAAIK0gITIABPAAA1AAQKfy4AAxgACgomHVQhAOgCABgACgomHVQhAOgCABcACgr4FzJ8ADICAAAA.',
Ju='Juego:BAAANQADCgQIBAAAAA==.Julkan:BAAANQAECgQIBgAAAA==.Junhoong:BAABNQAECn81AAIXAAoKURFzUADEAQAXAAoKURFzUADEAQAAAA==.Juvia:BAABNQAECn8pAAMNAAkKdxZnXQAJAgANAAgK3hVnXQAJAgAIAAgKRg5NoQAzAQABNQAECgkJOAAkADwQAA==.',
Jy='Jynnysa:BAAANQAECgEIAQABNQAECgkJJAAkAFobAA==.',
Ka='Kai:BAAANQAECgQICAAAAA==.Kairoll:BAABNQAECn83AAMEAAkKnBDzTAB9AQAEAAkKnBDzTAB9AQAMAAQKLBHXSgDsAAAAAA==.Kaleìna:BAAANQADCgcICAAAAA==.Kallisto:BAAANQAECgIIAgAAAA==.Karaa:BAAANQAECgUIBwAAAA==.Kariena:BAABNQAECn8bAAIVAAcKHg1kkAARAQAVAAcKHg1kkAARAQAAAA==.Kart:BAAANQADCgEIAQAAAA==.Kashaka:BAAANQADCgcIEgAAAA==.Katesluage:BAABNQAECn9EAAMiAAkKUhrMBgCOAgAiAAkKUhrMBgCOAgAdAAUKMQmwVgEBAQAAAA==.Kayyaa:BAAANQADCggICAAAAA==.',
Ke='Keeya:BAABNQAECn8iAAMLAAcKWQikfgAiAQALAAcKWQikfgAiAQAJAAEKKAJ9vgAeAAAAAA==.Kelina:BAAANQADCgIIAgAAAA==.Kendari:BAABNQAECn8lAAMKAAgKkQyjPADvAAAKAAgKuQujPADvAAAJAAQKkAiUfAC1AAAAAA==.Kernasas:BAABNQAECn8aAAIeAAgKmQy3BwD4AAAeAAgKmQy3BwD4AAAAAA==.',
Kh='Khiari:BAAANQADCgUIBQABNQAECgoKIAAXAGsVAA==.',
Ki='Kier:BAAANQAECgEIAwAAAA==.Kizaraan:BAAANQADCgUIBQAAAA==.',
Kl='Kleyntamar:BAAANQAECgMIBwAAAA==.',
Kn='Knyghtly:BAAANQAECggIDgABNQAECgkJJAAUAFAYAA==.',
Ko='Konstantien:BAAANQAECgUIBQAAAA==.Koric:BAABNQAECn8eAAMYAAoKhwy7LAD2AQAYAAoKhwy7LAD2AQAXAAQKlxNiIwHkAAAAAA==.Kourney:BAAANQADCgcIBwABNQAECgkJOAAkADwQAA==.',
Kr='Kretsch:BAAANQADCgUIBQABNQAECgcIEgAQAAAAAA==.Krickket:BAAANQADCgMIAwABNQAECgUIEAAQAAAAAA==.',
Ku='Kupau:BAAANQAECgQICAAAAA==.Kurogami:BAABNQAECn8rAAMLAAoK7g9/VwCzAQALAAgKzhF/VwCzAQAJAAgK/wyPWgA/AQAAAA==.Kuthixo:BAAANQAECgMIBQAAAA==.',
Ky='Kylos:BAAANQABCgQIBgAAAA==.Kynnigos:BAAANQABCgIIAgAAAA==.',
La='Landstrider:BAABNQAECn8nAAIVAAoKUxieUgB4AgAVAAoKUxieUgB4AgABNQAFFAYIEAAUACMNAA==.Lanss:BAABNQAECn82AAMCAAoKiR4qGACnAgACAAoKiR4qGACnAgAFAAQKjx61IgA0AQAAAA==.Larachel:BAABNQAECn8ZAAIEAAgKahzSMgDyAQAEAAgKahzSMgDyAQAAAA==.Lastaril:BAAANQADCgYIDwAAAA==.Lastword:BAAANQAECgYIDAAAAA==.Laur:BAABNQAECn8wAAIMAAoKYwxyEgCjAQAMAAoKYwxyEgCjAQAAAA==.',
Le='Leipäjuusto:BAABNQAECn8fAAIXAAgKYBAQfgBVAQAXAAgKYBAQfgBVAQAAAA==.',
Li='Liartes:BAAANQAECgMIBwAAAA==.Liderela:BAAANQADCgEIAQAAAA==.Lilipo:BAABNQAECn8mAAIlAAcKqQcDKgDVAAAlAAcKqQcDKgDVAAAAAA==.',
Ll='Llarastrasza:BAAANQAECgIIAgABNQAECggICQAQAAAAAA==.',
Lo='Logoth:BAAANQAECgQIBAAAAA==.Lohgarak:BAAANQADCggIFQAAAA==.',
Lu='Lunaellana:BAAANQADCgYICAAAAA==.',
Ly='Lystaan:BAAANQABCgQIBAAAAA==.',
['Lü']='Lüvpüp:BAACNQAFFH8JAAISAAQK3RZyAgDKAAASAAQK3RZyAgDKAAA1AAQKfx4AAhIACQqrImIFAD0DABIACQqrImIFAD0DAAAA.',
Ma='Magicfang:BAAANQADCgQIBAAAAA==.Maiku:BAABNQAECn8nAAIGAAgK7hMgbAAZAgAGAAgK7hMgbAAZAgAAAA==.Majo:BAAANQAECgIIAgAAAA==.Makado:BAABNQAECn8fAAQjAAoK7Af3DwBOAQAGAAkKrQYKuABeAQAjAAcKlgf3DwBOAQAeAAEKAAB0hAAmAAAAAA==.Makaris:BAAANQAECgQIBAAAAA==.Maklur:BAAANQAECgUICQAAAA==.Makoa:BAAANQADCgQIBAAAAA==.Makoroth:BAABNQAECn8jAAIGAAkKgxJljgDDAQAGAAkKgxJljgDDAQAAAA==.Malanda:BAAANQADCgQIBAAAAA==.Malygosson:BAAANQAECgUICgAAAA==.Masharu:BAAANQADCgcIBwAAAA==.Matua:BAAANQAECgIIAgAAAA==.Maycee:BAAANQAECgQIEQAAAA==.',
Mc='Mcat:BAAANQAECgQICQAAAA==.Mcgriddle:BAAANQADCgEIAQAAAA==.Mcnaugh:BAAANQAECgQICQAAAA==.Mcsaltface:BAAANQAECgQIDAAAAA==.',
Me='Meddic:BAABNQAECn8ZAAMEAAYKjAKwjwCyAAAEAAYKjAKwjwCyAAAMAAIKQQDhjgAcAAAAAA==.Megavolt:BAAANQAECgcIDQAAAA==.Menarot:BAAANQAECgcIEQAAAA==.Mendais:BAAANQADCgYIDgAAAA==.Messia:BAAANQADCgEIAQAAAA==.Meztlitotol:BAABNQAECn8YAAMRAAcKhCCQDQCNAgARAAcKhCCQDQCNAgATAAEKAACQQAA5AAABNQAECgoKOwAFAAodAA==.',
Mi='Mirosdrigo:BAAANQADCgcIBwAAAA==.Mirosmundo:BAACNQAFFH8HAAIHAAMKdw5ZAwDLAAAHAAMKdw5ZAwDLAAA1AAQKfy4AAgcACgqEGzAIAK0CAAcACgqEGzAIAK0CAAAA.Mistfit:BAABNQAECn8bAAIOAAkKyQyZEQBeAQAOAAkKyQyZEQBeAQAAAA==.Miyu:BAABNQAECn81AAMMAAoKVBJiJwDwAQAMAAkKog9iJwDwAQAEAAoK1wWhTwBzAQAAAA==.',
Mo='Mod:BAABNQAECn82AAMIAAkKmxokLgDtAQAIAAkKmxokLgDtAQANAAEKAABJRAEsAAAAAA==.Moeng:BAAANQADCgIIAgAAAA==.Moggatorash:BAAANQAECgYIEQAAAA==.Mogtham:BAABNQAECn80AAIRAAkKChQwEgCOAQARAAkKChQwEgCOAQAAAA==.Moisticklez:BAAANQAECgYIBgAAAA==.Monlaferte:BAAANQAECggIDwAAAA==.Montsegur:BAAANQADCggICAAAAA==.Mooforn:BAAANQAECgMICQAAAA==.Moonfall:BAAANQAECgUIEAAAAA==.Moosader:BAABNQAECn8VAAMXAAcKmg91zQCBAQAXAAcKmg91zQCBAQAYAAcKOQganABPAQAAAA==.Morellea:BAAANQAECgUJCgAAAA==.Morighann:BAABNQAECn81AAIVAAkKMSF3MAAeAgAVAAkKMSF3MAAeAgAAAA==.Moñgoose:BAAANQADCgMIAwAAAA==.',
My='Mynkx:BAABNQAECn8gAAIXAAoKaxXYPgAAAgAXAAoKaxXYPgAAAgAAAA==.Mythyras:BAABNQAECn8kAAIkAAkKWhsdFABkAgAkAAkKWhsdFABkAgAAAA==.',
Na='Naeomy:BAABNQAECn8/AAIhAAoKHQibEgBpAQAhAAoKHQibEgBpAQAAAA==.Nahaman:BAAANQAECgQIBwAAAA==.Napolien:BAABNQAECn84AAMkAAkKPBBcHAAZAQAkAAgKPBBcHAAZAQAYAAMKrA8D7ACpAAAAAA==.Naugan:BAAANQADCgEIAQAAAA==.',
Ne='Nechahira:BAACNQAFFH8QAAIUAAYKIw1hBQBMAQAUAAYKIw1hBQBMAQA1AAQKfyMAAxQACgrCFZQLAH8CABQACgrCFZQLAH8CABEAAQoAAKhoAAAAAAAA.Nethim:BAAANQAECgQICAAAAA==.Nezana:BAAANQAECgIIAgAAAA==.',
Ni='Nien:BAAANQAECgIIAwAAAA==.Nightfallen:BAAANQAECgQIBAAAAA==.Nihlathak:BAAANQAECgYIDAAAAA==.Ninada:BAABNQAECn8aAAMdAAcKbAzvAwGHAQAdAAcK0grvAwGHAQAiAAIKcgifQwA8AAAAAA==.Ninalee:BAAANQAECgYICAAAAA==.Ninefallen:BAAANQAECgMIBQAAAA==.',
No='Noranna:BAAANQAECgMICQAAAA==.',
Ny='Nyim:BAAANQAECgEIAQAAAA==.Nymiria:BAAANQABCgEIAQABNQAECgUIEAAQAAAAAA==.Nynsyn:BAAANQAECgUIEwABNQAECgkJJAAkAFobAA==.Nyxeira:BAAANQAECgYICgAAAA==.',
['Nâ']='Nâli:BAAANQAECgQIBAAAAA==.',
Ob='Obsidianclaw:BAAANQADCgIIAwAAAA==.',
Oh='Ohthesemyboo:BAAANQAECgQICAAAAA==.Ohwellz:BAAANQAECgEIAQAAAA==.',
Ol='Olehei:BAAANQAECgEIAQAAAA==.',
Op='Ophin:BAABNQAECn8zAAILAAoKmxj7FgDGAQALAAoKmxj7FgDGAQAAAA==.',
Pa='Panamared:BAABNQAECn8sAAIbAAkKAxWLFgAtAgAbAAkKAxWLFgAtAgAAAA==.Pappawoody:BAABNQAECn8cAAICAAgKCBxkbwBFAgACAAgKCBxkbwBFAgAAAA==.Parishealton:BAAANQADCgcIBwAAAA==.',
Pe='Pellegryn:BAAANQADCgYICQAAAA==.Pennyfeather:BAABNQAECn8zAAMEAAkKOhEhPADFAQAEAAkKOhEhPADFAQAMAAQKygkUUgDHAAAAAA==.Pezza:BAABNQAECn8bAAIIAAgKkxH/WAA2AQAIAAgKkxH/WAA2AQAAAA==.',
Ph='Phaze:BAABNQAECn8wAAImAAgKZyBPBACkAgAmAAgKZyBPBACkAgAAAA==.Phideauxe:BAAANQAECgQIBQAAAA==.Phorate:BAAANQAECgcIDwAAAA==.',
Pl='Pluralbutter:BAABNQAECn8bAAIaAAoKqA2iPADSAQAaAAoKqA2iPADSAQAAAA==.',
Po='Popexeo:BAAANQAECgcIDQABNQAFFAcIDgAUADARAA==.',
Pr='Prometheum:BAAANQAECgQICAAAAA==.',
Ps='Psyvern:BAABNQAECn8jAAIPAAgKogg3DgBkAQAPAAgKogg3DgBkAQAAAA==.',
Qt='Qtkat:BAAANQADCgMIAwABNQAECgMICAAQAAAAAA==.',
Qu='Quiccerstorm:BAAANQADCgQIBQAAAA==.',
Ra='Raevennlumis:BAABNQAECn8XAAIXAAgKBAkp5gBPAQAXAAgKBAkp5gBPAQAAAA==.Raevenns:BAAANQADCggJCAABNQAECggIFwAXAAQJAA==.Rahkhard:BAABNQAECn89AAMHAAoKQyB2AwBaAwAHAAoKCiB2AwBaAwAlAAkKLBoiEQDTAQAAAA==.Rascdit:BAAANQAECgUICgAAAA==.',
Re='Recreant:BAAANQAECgUICAAAAA==.Reiyoso:BAAANQAECgIIAgAAAA==.Reui:BAAANQAECgIIAgAAAA==.',
Rh='Rhemibumbum:BAAANQAECgUICwAAAA==.',
Ro='Roberey:BAAANQAECgUICgAAAA==.Rocketbilly:BAAANQADCgIIAgAAAA==.Roobee:BAABNQAECn8eAAIeAAYKhwPjPADOAAAeAAYKhwPjPADOAAAAAA==.',
Ru='Ruaic:BAAANQADCggIEgAAAA==.',
Sa='Sableanne:BAAANQADCgEIAQAAAA==.Sacréd:BAABNQAECn8YAAIkAAYKyBcSLAB8AQAkAAYKyBcSLAB8AQAAAA==.Sarkan:BAAANQADCggIEQAAAA==.Sarova:BAABNQAECn8bAAIVAAkKhBThXwB/AQAVAAkKhBThXwB/AQAAAA==.Satori:BAAANQAECgMICQAAAA==.',
Sc='Scalewind:BAAANQADCgYIBgAAAA==.',
Se='Seldeath:BAAANQADCgEJAQAAAA==.Selfu:BAABNQAECn81AAIlAAkKPhYHEgDFAQAlAAkKPhYHEgDFAQAAAA==.Sellidor:BAABNQAECn84AAIVAAoKaSMRCgAEAwAVAAoKaSMRCgAEAwAAAA==.Serenesong:BAAANQADCgEIAQAAAA==.Seriniyaa:BAAANQAECgMIBQAAAA==.Serioth:BAAANQADCgIIAgAAAA==.',
Sh='Sheara:BAAANQAECggIEgAAAA==.Shinjiro:BAABNQAECn8jAAIXAAcKDQJhTQGkAAAXAAcKDQJhTQGkAAAAAA==.Shirito:BAABNQAECn9BAAMLAAkKgSQCCwBjAwALAAgKVSUCCwBjAwAJAAkK6yNhCwA9AwAAAA==.Shiritodh:BAABNQAECn8lAAIDAAkKcCBRFQC6AgADAAkKcCBRFQC6AgAAAA==.Shockin:BAAANQAECgcIDAAAAA==.Shortnstout:BAACNQAFFH8NAAIkAAMKtxqMAwDlAAAkAAMKtxqMAwDlAAA1AAQKfygAAyQACgpfImgLAOICACQACgpfImgLAOICABcAAgrIG7aLAUoAAAAA.Shugo:BAAANQAECgUIEQAAAA==.',
Si='Sienje:BAABNQAECn8mAAIXAAkKkhdgdABFAgAXAAkKkhdgdABFAgAAAA==.Sigma:BAABNQAECn8gAAIVAAgKQAZttQCZAQAVAAgKQAZttQCZAQAAAA==.Simpleson:BAABNQAECn8yAAMGAAoKlRhIMADsAQAGAAkKdhhIMADsAQAeAAEKbhntJQBAAAAAAA==.Sinbàd:BAACNQAFFH8KAAIDAAUKMxQPBwCeAQADAAUKMxQPBwCeAQA1AAQKfzUAAgMACgomH7oKAEoCAAMACgomH7oKAEoCAAAA.Sinistris:BAAANQAECgQIBQAAAA==.',
Sk='Skie:BAAANQAECggIEQABNQAECgkJJAAUAFAYAA==.Skrabble:BAAANQAECgQIDQAAAA==.Skölldraugos:BAAANQAECgEIAQAAAA==.',
Sl='Slaete:BAABNQAECn8XAAIaAAcK1gSTYAD6AAAaAAcK1gSTYAD6AAAAAA==.Slush:BAAANQAECgQIBAAAAA==.',
Sm='Smallz:BAAANQAECgUIDgABNQAECgkJKAAVAMAVAA==.Smorgas:BAAANQAECgIIBQABNQAECgoKLAAXAEEdAA==.Småug:BAAANQADCgMJAwAAAA==.',
So='Solemn:BAABNQAECn8tAAIMAAkK8xXqDwDRAQAMAAkK8xXqDwDRAQABNQAECgoKOAAVAGkjAA==.Solrana:BAAANQAECgQICQAAAA==.Songmistress:BAABNQAECn8WAAIGAAgKzwVexwA7AQAGAAgKzwVexwA7AQAAAA==.Sorren:BAAANQAECgQIBAAAAA==.Sotta:BAAANQAECgIIBQAAAA==.Sozin:BAAANQADCgIIAgAAAA==.',
Sp='Spritmoon:BAAANQADCgYIBgAAAA==.',
Sq='Squeezee:BAAANQADCggICAAAAA==.',
St='Stardrive:BAABNQAECn8aAAIIAAYK8B8sMgDYAQAIAAYK8B8sMgDYAQAAAA==.Stevesteve:BAABNQAECn8mAAIGAAkKBQxGOwC8AQAGAAkKBQxGOwC8AQAAAA==.Stroganov:BAAANQAECgUIBwABNQAECgcIEgAQAAAAAA==.Stumpii:BAAANQADCgQIBAAAAA==.',
Su='Sunasha:BAAANQADCgYIEgAAAA==.Superbautumn:BAAANQAECgYIEAAAAA==.',
Sy='Synge:BAABNQAECn8bAAMdAAYK5ww0rADvAAAdAAYK5gw0rADvAAAiAAEK9AfLSgAwAAAAAA==.Synnyca:BAAANQAECgUIBQABNQAECgkJJAAkAFobAA==.',
['Sé']='Sélune:BAAANQAECggICQAAAA==.',
Ta='Tachyon:BAAANQAECgYICAABNQAFFAQICQASAN0WAA==.Taeonaki:BAAANQAECgMIBAAAAA==.Tagnaras:BAAANQAECgYICwAAAA==.Tagnaris:BAAANQAECgUIBQAAAA==.Tahlang:BAAANQABCggICgAAAA==.Tali:BAAANQAECgQICgAAAA==.Taliasluage:BAAANQADCggICAABNQAECgkJRAAiAFIaAA==.Tangle:BAABNQAECn8kAAMUAAkKUBgcHgBwAQAUAAcKCRkcHgBwAQABAAcKfAYUTwCJAAAAAA==.Tanka:BAABNQAECn8pAAICAAkK9hyQWwB5AgACAAkK9hyQWwB5AgAAAA==.Tannisse:BAAANQADCggIFQAAAA==.Tanuki:BAAANQAECgQIBAAAAA==.Tapol:BAAANQAECgUIEAAAAA==.Tashlaraz:BAEANQAECgMIBQAAAA==.Tasi:BAAANQAECgQIBAAAAA==.Taurannosaur:BAAANQADCggIDAAAAA==.Taurentots:BAAANQAFFAMIAwAAAA==.',
Te='Telkas:BAAANQAECgEIAQAAAA==.Temporantus:BAAANQAECgQIBAAAAA==.Tenko:BAABNQAECn8tAAMdAAkKMAqhaAB3AQAdAAkKhwmhaAB3AQAiAAIKdAzaNQBkAAAAAA==.',
Th='Thaddeus:BAAANQAECgUIDwAAAA==.Therm:BAACNQAFFH8QAAIXAAYKJBzgBQD4AQAXAAYKJBzgBQD4AQA1AAQKf0wAAxcACgrbJmYAAJgDABcACgrbJmYAAJgDABgAAQrQBwQgATYAAAAA.Thoramier:BAAANQAECgYIEgAAAA==.',
Ti='Tibble:BAAANQAECgUIDQAAAA==.Timoonja:BAAANQAECgUIEAAAAA==.Tirazlea:BAAANQADCgIIAgAAAA==.',
To='Tonatuih:BAABNQAECn9BAAIaAAoKtx6kCgCkAgAaAAoKtx6kCgCkAgAAAA==.',
Tr='Trezzia:BAABNQAECn8jAAIjAAkKXRMlBADCAQAjAAkKXRMlBADCAQAAAA==.Triipod:BAAANQADCgYIGwAAAA==.Trinkat:BAAANQAECgMICAAAAA==.Trojinn:BAAANQAECgUIBQAAAA==.Tryst:BAAANQADCgYIBgAAAA==.Tráson:BAAANQADCgYIBQAAAA==.',
Tu='Tub:BAAANQAECggIEwAAAA==.',
Ty='Tylean:BAAANQAECgQICgAAAA==.',
['Tì']='Tìríon:BAAANQABCgEIAQAAAA==.',
Ud='Udukai:BAAANQAECgQIBAAAAA==.',
Ul='Ultrastealth:BAABNQAECn8ZAAQbAAUK6ga9PADSAAAbAAUKAAa9PADSAAAhAAQKdgRTkQBtAAAnAAIKtgOGCgAnAAAAAA==.',
Um='Umbrum:BAAANQADCgIIAgABNQAECgoKOwAFAAodAA==.',
Uu='Uu:BAAANQAECggIEAAAAA==.',
Va='Vadrozsa:BAAANQAECgMIBQAAAA==.Vallarie:BAAANQADCgQJBAAAAA==.Vareyn:BAAANQAECgMIAwAAAA==.',
Vo='Vorth:BAABNQAECn81AAIJAAoKMBFGIQDCAQAJAAoKMBFGIQDCAQAAAA==.Vorukh:BAAANQADCgQIBAABNQAECgIIBAAQAAAAAA==.Vorúkh:BAAANQAECgQIDAABNQAECgIIBAAQAAAAAA==.Vorükh:BAAANQAECgUIBQABNQAECgIIBAAQAAAAAA==.',
Vu='Vulturous:BAAANQADCgYICgAAAA==.',
Vy='Vydian:BAAANQADCgYICQAAAA==.Vyrlana:BAAANQAECgEIAQAAAA==.',
Wa='Waldir:BAABNQAECn8yAAMYAAkKAyPvEwAzAwAYAAkKAyPvEwAzAwAXAAMKkAruDgFsAAAAAA==.Walock:BAAANQADCgMIAwAAAA==.Wanted:BAAANQADCgYIBgAAAA==.Watz:BAAANQAECggIDgAAAA==.',
We='Wensa:BAAANQADCgcIBwAAAA==.',
Wh='Wholesale:BAABNQAECn80AAIKAAgK7BZnJQBrAQAKAAgK7BZnJQBrAQAAAA==.',
Wr='Wrack:BAAANQADCggIEQAAAA==.Wraithian:BAAANQABCgQIBAAAAA==.Wratsoul:BAABNQAECn8eAAIGAAoKxgxifgDqAQAGAAoKxgxifgDqAQAAAA==.',
Xe='Xessala:BAABNQAECn8lAAIIAAgKIhiUUAAjAgAIAAgKIhiUUAAjAgAAAA==.',
Xh='Xheero:BAABNQAECn86AAIVAAkK5x2bJAAEAwAVAAkK5x2bJAAEAwAAAA==.Xheerom:BAAANQADCgUIBQAAAA==.',
Ya='Yagiashi:BAAANQAECgQIBgABNQAECgoKOwAFAAodAA==.',
Yu='Yulica:BAAANQAECgMICQAAAA==.',
Za='Zaffy:BAABNQAECn8sAAIeAAgKdg+eBQA0AQAeAAgKdg+eBQA0AQAAAA==.Zaktrix:BAAANQAECgIIAgAAAA==.Zaleron:BAAANQADCggIFAAAAA==.Zaruba:BAABNQAECn8qAAMNAAgKaghGhgCVAQANAAgKaghGhgCVAQAIAAEKsAGq3QAYAAABNQAECggIJgABAE8KAA==.Zatkyng:BAABNQAECn8mAAIlAAkK4A4IHwAvAQAlAAkK4A4IHwAvAQAAAA==.',
Ze='Zekos:BAAANQAECgEIAQAAAA==.',
Zi='Zillver:BAAANQAECgUIBQABNQAECgkJOAAkADwQAA==.Zimdalar:BAAANQAECgUIEwAAAA==.',
Zu='Zulre:BAABNQAECn8wAAMKAAoKuRtkGwDUAgAKAAkKgx1kGwDUAgAJAAUKnw0sTwDZAAAAAA==.',
['Ôv']='Ôverkill:BAABNQAECn8bAAIRAAgKaxZDFwD5AQARAAgKaxZDFwD5AQAAAA==.',
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
