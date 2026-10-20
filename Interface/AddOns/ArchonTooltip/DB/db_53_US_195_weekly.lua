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
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Ackrenoth:BAAANQAECgIIAwAAAA==.',
Ad='Adynn:BAABNQAECn8rAAIBAAoKkyToBACyAwABAAoKkyToBACyAwAAAA==.',
Ae='Aermoss:BAAANQAECgEIAQAAAA==.Aeru:BAAANQADCgYIBgAAAA==.Aethreal:BAAANQAFFAEIAQAAAA==.',
Af='Afridium:BAAANQADCgEIAQAAAA==.',
Ak='Akikusa:BAAANQADCggICgAAAA==.',
Al='Alderath:BAAANQABCgQJBQAAAA==.Alista:BAABNQAECn8xAAICAAoKTyNNCgCjAwACAAoKTyNNCgCjAwAAAA==.Allyeska:BAAANQADCgcIDQAAAA==.Alnharaelune:BAAANQADCgYIDQAAAA==.',
Am='Amarea:BAAANQAECgIIAwAAAA==.Amor:BAABNQAECn8YAAIDAAYK6xoqDgBEAQADAAYK6xoqDgBEAQAAAA==.',
An='Anali:BAABNQAECn8WAAIEAAkKVRMtSwBEAgAEAAkKVRMtSwBEAgAAAA==.Anani:BAAANQAECgIIAwAAAA==.Angreifer:BAABNQAECn8yAAMFAAoKaRwKAgADAgAFAAoKaRwKAgADAgACAAIKvAP9PgFVAAAAAA==.Anoana:BAAANQADCgQIBAAAAA==.Anori:BAABNQAECn8ZAAIBAAcKDAzlVwB2AQABAAcKDAzlVwB2AQAAAA==.',
Ao='Aonar:BAAANQAECgMICgAAAA==.',
Aq='Aqua:BAAANQAECgIIAwAAAA==.',
Ar='Arc:BAABNQAECn8aAAIGAAoKbhuhCQANAgAGAAoKbhuhCQANAgABNQAECgoKMgAHAAogAA==.Arcanimous:BAAANQADCggICAAAAA==.Archenteron:BAAANQAECgEIAgAAAA==.Archnunin:BAAANQAECggICAAAAA==.Ardorcinder:BAAANQAECgIIBQAAAA==.Argentur:BAAANQADCgEIAQAAAA==.Arkaan:BAAANQADCgUIBQABNQAECgYIFQAIAHYcAA==.Armangaria:BAAANQAECggICAAAAA==.Arrozz:BAAANQADCgQIBAAAAA==.Arthmanafel:BAABNQAECn8hAAQJAAgKqRo/KQBPAgAJAAgKvRk/KQBPAgAKAAEKqR9btQBeAAALAAEKJQu54gAxAAAAAA==.',
As='Asbjorne:BAAANQAECgMICgAAAA==.',
At='Atryssa:BAAANQAECgUIBQAAAA==.',
Au='Audi:BAAANQADCgMIAwAAAA==.Autumnmoon:BAAANQAECgYIDwAAAA==.',
Av='Avalsong:BAABNQAECn8tAAIDAAoK6xpKDgAEAwADAAoK6xpKDgAEAwAAAA==.Avelos:BAABNQAECn8sAAMEAAoK+R1wIwDgAgAEAAoK+R1wIwDgAgAMAAEK7QqlMwA1AAAAAA==.',
Ay='Ayowenn:BAAANQADCgIIAgAAAA==.Ayzmist:BAABNQAECn8fAAINAAYKfwlRPQDSAAANAAYKfwlRPQDSAAAAAA==.Ayzmyth:BAABNQAECn8mAAMOAAoK2g8VHgCpAQAOAAoK2g8VHgCpAQAHAAUKJwQ4IgDIAAAAAA==.',
Ba='Banthapooduu:BAAANQADCgcIEwAAAA==.',
Be='Beasic:BAABNQAECn8rAAINAAgKiAQISQCzAAANAAgKiAQISQCzAAAAAA==.Beletili:BAABNQAECn8rAAIEAAoK/hE0ZADzAQAEAAoK/hE0ZADzAQAAAA==.Bellissimio:BAAANQADCgUICAABNQAECgkJHgAIAOUQAA==.Bener:BAAANQADCgcIBwAAAA==.Beátrix:BAAANQADCgIIAgAAAA==.',
Bi='Birdman:BAAANQAECgQIAQAAAA==.Bismuth:BAAANQAECgIIAwAAAA==.',
Bl='Blackraven:BAAANQAECgYIBgAAAA==.Blatendrg:BAABNQAECn8vAAIPAAgKqxVgAwAaAQAPAAgKqxVgAwAaAQAAAA==.Blindcloud:BAAANQAECgUIDAAAAA==.',
Bo='Boot:BAAANQAECgUIDwAAAA==.Borodemonin:BAEBNQAECn8qAAIDAAkKVyb1AgCrAwADAAkKVyb1AgCrAwAAAA==.',
Br='Breae:BAABNQAECn8rAAMEAAgKRBeOJwBgAQAEAAgKRBeOJwBgAQAMAAUKEATnWQCgAAAAAA==.Brieanna:BAAANQADCgUIBgAAAA==.Bristia:BAAANQAECgUICAAAAA==.Brueggar:BAAANQAECgEIAgAAAA==.Brutyl:BAAANQAECgEIAgABNQAECggIDgAQAAAAAA==.',
Bu='Bulky:BAAANQAECgIIAgAAAA==.',
By='Byegone:BAAANQAECgQIDAAAAA==.',
Ca='Cadforus:BAAANQADCgcIEAABNQAECgcIGgARAFYXAA==.Cafë:BAAANQADCgcICgABNQAFFAMIBwASAN0WAA==.Caicee:BAAANQADCgIIAgAAAA==.Caistin:BAAANQAECgEIAQAAAA==.Calyma:BAAANQAECgIICAAAAA==.Camelsotters:BAABNQAECn8XAAUTAAUKEAdHMQCJAAATAAQKnQVHMQCJAAARAAUK7wVBSgCCAAAUAAQKwQIJLgB7AAABAAIKWQGmugAmAAAAAA==.Casca:BAAANQAECgQICAAAAA==.Catsclaw:BAAANQAECgEIAQAAAA==.',
Ce='Cenjeru:BAABNQAECn8dAAMJAAcKyxhHPADdAQAJAAcK8BVHPADdAQALAAYKnBclZwB1AQAAAA==.',
Ch='Chezzie:BAAANQAECgYICwAAAA==.Chiot:BAABNQAECn8kAAIFAAgK3B35CQCnAgAFAAgK3B35CQCnAgAAAA==.',
Ci='Cimerian:BAAANQAECgIIBAAAAA==.',
Cl='Clone:BAAANQADCgYIBgAAAA==.',
Co='Cobalticus:BAAANQAECgQIBAAAAA==.Concealer:BAAANQADCgEIAQAAAA==.Conejamala:BAABNQAECn8lAAMVAAoKmB0fFgBDAwAVAAoKmB0fFgBDAwAWAAMKUw6PXwCoAAAAAA==.Corange:BAAANQABCgIIBAAAAA==.Cordini:BAAANQAECgMIBAAAAA==.Corlock:BAAANQADCgQIBAAAAA==.Cormech:BAAANQAECgQICAAAAA==.Cornite:BAAANQADCgYIDgAAAA==.',
Cr='Crizzo:BAABNQAECn8pAAIVAAgK+R2fFQDIAQAVAAgK+R2fFQDIAQAAAA==.',
Da='Daddyslilgrl:BAAANQAECgMIBwAAAA==.Dakra:BAEBNQAECn8XAAICAAcKCxkzjQD7AQACAAcKCxkzjQD7AQAAAA==.Dalamar:BAAANQAECgcIHwABNQAECgoKMQAMAHocAQ==.Dalandis:BAABNQAECn8hAAMXAAkK4xzsGAC/AQAXAAkK4xzsGAC/AQAYAAEKJgeGlgA2AAAAAA==.Dalyeth:BAABNQAECn8iAAMZAAgKPSWGBAD8AgAZAAgKPSWGBAD8AgAaAAEKAAAumwAoAAAAAA==.Darianno:BAAANQADCgMIAwAAAA==.Darkwingorc:BAABNQAECn8yAAIVAAoKrh1fIQASAwAVAAoKrh1fIQASAwAAAA==.Darkwulf:BAAANQADCgcJDQAAAA==.Daunt:BAAANQADCgcIDgABNQAECggIJgABAE8KAA==.Dawnfire:BAAANQADCgEIAQAAAA==.Dawnmane:BAAANQADCgEIAQAAAA==.Dayseeker:BAAANQAECgEIAQAAAA==.',
De='Deadsecsi:BAAANQABCgEIAQAAAA==.Decypher:BAAANQAECgIIBQABNQAECgoKLQAbAOcSAA==.Deebz:BAABNQAECn8fAAIUAAcKNBZvKQDTAQAUAAcKNBZvKQDTAQAAAA==.Deliverance:BAABNQAECn8xAAIMAAoKehydEQDjAgAMAAoKehydEQDjAgAAAA==.Demigoth:BAABNQAECn8hAAIcAAcKJROBDwDYAAAcAAcKJROBDwDYAAAAAA==.Denethmon:BAAANQAECgEJAQABNQAECgMIBQAQAAAAAA==.Dentik:BAABNQAECn8vAAMTAAcKUg8KHgAsAQATAAYK3gsKHgAsAQAUAAcKYA+YPwApAQAAAA==.Denuma:BAAANQAECgMIAwAAAA==.Devilina:BAAANQAECgEIAQAAAA==.Deàdpool:BAAANQADCgQIBAABNQAECgoKKgAGABQZAA==.',
Dh='Dheriana:BAABNQAECn8tAAIbAAoK5xK+CwCCAQAbAAoK5xK+CwCCAQAAAA==.Dherisis:BAAANQAECgMIAwABNQAECgoKLQAbAOcSAA==.Dherli:BAAANQAECgMIBAABNQAECgoKLQAbAOcSAA==.',
Di='Diamair:BAABNQAECn8nAAIdAAgK8w37ZADzAAAdAAgK8w37ZADzAAAAAA==.Disney:BAAANQAECggICAAAAA==.Divynelle:BAAANQABCgIIAgAAAA==.Dixiee:BAAANQAECgYIEgAAAA==.',
Dn='Dnegelpal:BAABNQAECn8nAAIXAAgKJQ5+PQBMAQAXAAgKJQ5+PQBMAQAAAA==.',
Do='Dodgecharger:BAAANQAECgUICAAAAA==.',
Dr='Dragerin:BAAANQAECgMIAwAAAA==.Dragonfood:BAAANQAECgMIBgAAAA==.Drakilu:BAABNQAECn8tAAIVAAgK9RdqUQB7AgAVAAgK9RdqUQB7AgAAAA==.Drakra:BAEANQAECgYICgABNQAECgcIFwACAAsZAA==.Drasic:BAABNQAECn87AAIUAAoK/h3dAgCHAgAUAAoK/h3dAgCHAgAAAA==.Dreamcloud:BAAANQADCgYICAAAAA==.Dreddscott:BAAANQAECgYIBwABNQAECggIJAAbAIAVAA==.Dretro:BAAANQAECgIIBQAAAA==.Drovosi:BAAANQADCggIIgAAAA==.',
Du='Durin:BAABNQAECn8iAAICAAcKKAkQyABoAQACAAcKKAkQyABoAQAAAA==.Durward:BAABNQAECn8XAAMLAAgKOhQIHAAIAQAKAAcKQBBpWgCJAQALAAYKqRQIHAAIAQAAAA==.Duvo:BAABNQAECn8hAAIVAAkK9hRzMABfAQAVAAkK9hRzMABfAQAAAA==.',
Dw='Dwarvey:BAAANQADCgUIBQAAAA==.',
['Dæ']='Dæmôna:BAAANQADCgQIBQAAAA==.',
['Dé']='Détank:BAABNQAECn8uAAIJAAgKWxrQBwDaAQAJAAgKWxrQBwDaAQAAAA==.',
Ea='Easyname:BAABNQAECn8jAAIXAAoKjBM5DQAWAgAXAAoKjBM5DQAWAgAAAA==.',
Ei='Eiene:BAAANQAECgUICwAAAA==.Eithetala:BAAANQADCgYICAAAAA==.',
El='Elemental:BAAANQAECggIEQABNQAFFAUIDwAUAOQNAA==.Elloseth:BAAANQAECgUIDQAAAA==.Elmorin:BAAANQADCggIFgAAAA==.Eluneh:BAAANQADCgYICAAAAA==.',
Eo='Eolon:BAAANQAECgQIDAAAAA==.',
Ep='Epica:BAABNQAECn8qAAIdAAkKkw6jYQD6AAAdAAkKkw6jYQD6AAAAAA==.',
Er='Eragonhawk:BAAANQAECgMIBgAAAA==.Eraina:BAAANQAECgMIBAAAAA==.Eroldan:BAAANQADCgYICQAAAA==.Erovianoria:BAAANQAECgYIDwAAAA==.',
Es='Essun:BAABNQAECn8eAAIaAAkKrBmOJwBhAgAaAAkKrBmOJwBhAgABNQAFFAQICAAGAKMHAA==.',
Ev='Evanthe:BAABNQAECn8eAAMIAAkK5RBhLAAwAQAIAAkK5RBhLAAwAQANAAEKAADSWwEeAAAAAA==.',
Ex='Expire:BAAANQADCgEIAQAAAA==.',
Ez='Ezro:BAAANQADCgYICAAAAA==.',
Fa='Faizor:BAAANQAECgIIBAAAAA==.Fastal:BAAANQADCgcIFwAAAA==.Fatalfury:BAAANQAECggIAgAAAA==.Fauxborn:BAAANQAECgYIEAAAAA==.Fauxstorm:BAAANQADCgQIBQAAAA==.',
Fe='Fedwell:BAABNQAECn8gAAIXAAgKpgvX0wB0AQAXAAgKpgvX0wB0AQAAAA==.',
Fi='Finluc:BAAANQAECgEIAQAAAA==.Finngan:BAABNQAECn8kAAIeAAgKmgn/AwD5AAAeAAgKmgn/AwD5AAAAAA==.Fitoria:BAAANQAECgMIBAABNQAECgoKMgAHAAogAA==.',
Fo='Forestkin:BAAANQAECgUIDAABNQAECggIIgAZAD0lAA==.Foxhope:BAAANQAECgUIDQAAAA==.',
Fr='Friartuk:BAAANQAECgEIAQAAAA==.Frozenthunda:BAABNQAECn8xAAIdAAgK3w3YKgBwAQAdAAgK3w3YKgBwAQAAAA==.',
Fu='Furna:BAABNQAECn8gAAIfAAgK9wx1AwDxAAAfAAgK9wx1AwDxAAAAAA==.Fuzzyhooves:BAABNQAECn8nAAMYAAgKgiMEEwA5AwAYAAgKgiMEEwA5AwAXAAEK0wdrpgE0AAAAAA==.',
Ga='Gabrael:BAABNQAECn8vAAMgAAoKXxBfDQDhAQAgAAkK/RBfDQDhAQACAAgKfAs8rQCsAQAAAA==.',
Ge='Genger:BAAANQAECgEIAwAAAA==.',
Gh='Ghorienge:BAAANQAECgQIDwAAAA==.',
Gi='Gilox:BAABNQAECn8gAAIhAAgKAA/dCwBsAQAhAAgKAA/dCwBsAQAAAA==.',
Gl='Glossu:BAAANQADCgIIAgAAAA==.',
Gn='Gndmexia:BAAANQADCggIDAAAAA==.Gneiss:BAAANQAECgMIAwAAAA==.',
Go='Goldenarrow:BAAANQABCgYIDgAAAA==.Gorgilz:BAAANQADCgMICQAAAA==.Gothgirldemi:BAABNQAECn8vAAIUAAkK4SAGBQAUAgAUAAkK4SAGBQAUAgAAAA==.',
Gr='Graymon:BAAANQAECgMICgAAAA==.Greebo:BAAANQAECgMICgAAAA==.Gremsmasha:BAAANQADCggIAQAAAA==.Grist:BAAANQADCgYIDwAAAA==.',
Gu='Guatalupe:BAAANQAECgEIAQAAAA==.Guilherme:BAAANQAECgEIAgAAAA==.',
Gw='Gwenyver:BAAANQAECgMIBQAAAA==.',
Ha='Hailthanatos:BAABNQAECn8aAAIaAAkKLwtIPQDOAQAaAAkKLwtIPQDOAQAAAA==.Hamord:BAAANQAECgMICgAAAA==.Hansdelbruk:BAAANQADCgUIBQAAAA==.Hardlight:BAAANQAECgYICAAAAA==.Harliquette:BAABNQAECn8kAAIMAAgKGxMmCAByAQAMAAgKGxMmCAByAQAAAA==.Harliqynn:BAAANQAECgYICwAAAA==.Harlock:BAABNQAECn8dAAMbAAoKjhLoGgAAAgAbAAkK5hHoGgAAAgAhAAcKtA9FRgCtAQAAAA==.Hashen:BAAANQAECgQIAwAAAA==.Hazelnuts:BAAANQADCgUIBQAAAA==.',
Hi='Hiten:BAABNQAECn8iAAIbAAgK3gcCJACoAQAbAAgK3gcCJACoAQAAAA==.',
Ho='Hoofinmouth:BAAANQAECgMIBAAAAA==.Hoosh:BAAANQAECgQIBgAAAA==.Hopedaimond:BAABNQAECn8WAAMNAAcKrQdooABVAQANAAcKrQdooABVAQAIAAEKaAE6NwEYAAAAAA==.',
Hu='Huntertattoo:BAABNQAECn8YAAIVAAgKTQkymADXAQAVAAgKTQkymADXAQAAAA==.Husgus:BAAANQADCgYIDAABNQAFFAIIAgAQAAAAAA==.Huungron:BAAANQADCgYIDAAAAA==.',
Ic='Icynips:BAAANQADCgQIBAAAAA==.',
Il='Illianarra:BAAANQAECgMICQAAAA==.Ilthad:BAABNQAECn8VAAIaAAYKWAvkHAAQAQAaAAYKWAvkHAAQAQAAAA==.',
Im='Imaplantnow:BAAANQAECggICAAAAA==.Imawarrionow:BAAANQADCgIIAgAAAA==.Imora:BAAANQADCgMIAwAAAA==.Imshalar:BAAANQABCgIIAgABNQAECgQIBAAQAAAAAA==.',
In='Infurryating:BAAANQAECggIEgAAAA==.',
Ir='Iroar:BAAANQADCgIIAgAAAA==.Irumble:BAAANQADCggICgAAAA==.',
Is='Ischadè:BAAANQADCgUIBgAAAA==.Iskuros:BAAANQAECgEIAwAAAA==.',
It='Itsirk:BAABNQAECn8YAAIYAAgKxRSaCgAZAgAYAAgKxRSaCgAZAgAAAA==.',
Iz='Izyebelle:BAAANQAECgUIEQAAAA==.',
Ja='Jadevine:BAAANQADCgEIAQAAAA==.Jalynfein:BAABNQAECn8UAAIiAAkKBgVlCQD0AAAiAAkKBgVlCQD0AAAAAA==.Janar:BAAANQADCgYIBwAAAA==.',
Je='Jefeorganico:BAABNQAECn8bAAQjAAcKRwiYFAABAQAjAAUKggmYFAABAQAeAAUK4QTjRwCoAAAGAAQKgQTFJAF3AAAAAA==.Jeloi:BAAANQAECgIIBQAAAA==.Jenkshi:BAAANQADCgcIDQAAAA==.',
Ji='Jimmydin:BAABNQAECn8qAAMYAAoKJh1UIQDoAgAYAAoKJh1UIQDoAgAXAAgKrRkyfAAyAgAAAA==.',
Ju='Juego:BAAANQADCgQIBAAAAA==.Julkan:BAAANQAECgQIBgAAAA==.Junhoong:BAABNQAECn8rAAIXAAkKNBIAPQBNAQAXAAkKNBIAPQBNAQAAAA==.Juvia:BAABNQAECn8nAAMNAAkKdxZnXQAJAgANAAgK3hVnXQAJAgAIAAcKDQ9NoQAzAQABNQAECgkJMgAkAB0PAA==.',
Jy='Jynnysa:BAAANQAECgEIAgABNQAECggIIQAkAIwcAA==.',
Ka='Kai:BAAANQAECgMIBQAAAA==.Kairoll:BAABNQAECn8xAAMEAAkKqw0YKABeAQAEAAkKqw0YKABeAQAMAAQKLBHXSgDsAAAAAA==.Kaleìna:BAAANQADCgcICAAAAA==.Kallisto:BAAANQADCgcIBwAAAA==.Karaa:BAAANQAECgUICgAAAA==.Kariena:BAABNQAECn8VAAIVAAYKkA/ItwCUAQAVAAYKkA/ItwCUAQAAAA==.Kart:BAAANQADCgEIAQAAAA==.Kashaka:BAAANQADCgcIEgAAAA==.Katesluage:BAABNQAECn87AAMiAAkKUhpeAgC9AQAiAAkKUhpeAgC9AQAdAAUKMQmwVgEBAQAAAA==.Kawrrl:BAAANQAECgEIAQAAAA==.Kayyaa:BAAANQAECgEIAQAAAA==.',
Ke='Keeya:BAABNQAECn8dAAMLAAcKbQfWLQCpAAALAAcKbQfWLQCpAAAJAAEKKAJ9vgAeAAAAAA==.Kelina:BAAANQADCgIIAgAAAA==.Kendari:BAABNQAECn8lAAMKAAgKkQxyHwD/AAAKAAgKuQtyHwD/AAAJAAQKkAiUfAC1AAAAAA==.Kernasas:BAABNQAECn8XAAIeAAUKbg6wKwAhAQAeAAUKbg6wKwAhAQAAAA==.',
Kh='Khiari:BAAANQADCgUIBQABNQAECgoKGwAXAFwVAA==.',
Ki='Kier:BAAANQAECgIIBQAAAA==.Kizaraan:BAAANQADCgUIBQAAAA==.',
Kl='Kleyntamar:BAAANQAECgMICAAAAA==.',
Kn='Knyghtly:BAAANQAECggIDgABNQAECggIIQAUAPUYAA==.',
Ko='Konstantien:BAAANQAECgUIBwAAAA==.Koric:BAABNQAECn8UAAMXAAoKkRxiIwHkAAAXAAQKlxNiIwHkAAAYAAoKywjJQgDiAAAAAA==.Kourney:BAAANQADCgcIBwABNQAECgkJMgAkAB0PAA==.',
Kr='Kretsch:BAAANQADCgUIBQABNQAECgcIEwAQAAAAAA==.Krickket:BAAANQAECgEIAQABNQAECgYIEgAQAAAAAA==.',
Ku='Kupau:BAAANQAECgQICAAAAA==.Kurogami:BAABNQAECn8pAAMLAAkK8xB/VwCzAQALAAgKzhF/VwCzAQAJAAcK1w2PWgA/AQAAAA==.Kuthixo:BAAANQAECgIIAgAAAA==.',
Ky='Kylos:BAAANQABCgQIBgAAAA==.Kynnigos:BAAANQABCgIIAgAAAA==.',
La='Landstrider:BAABNQAECn8iAAIVAAoKuROZHgCdAQAVAAoKuROZHgCdAQABNQAFFAUIDwAUAOQNAA==.Lanss:BAABNQAECn8tAAMCAAoKoxliBgBkAgACAAoKoxliBgBkAgAFAAQKjx61IgA0AQAAAA==.Larachel:BAABNQAECn8WAAIEAAcKRxweFgDAAQAEAAcKRxweFgDAAQAAAA==.Lastaril:BAAANQADCgYIDwAAAA==.Lastword:BAAANQAECgQICAAAAA==.Laur:BAABNQAECn8lAAIMAAoKgAuHLADCAQAMAAoKgAuHLADCAQAAAA==.',
Le='Leipäjuusto:BAABNQAECn8ZAAIXAAgKIAwZPwBIAQAXAAgKIAwZPwBIAQAAAA==.',
Li='Liartes:BAAANQAECgMICgAAAA==.Liderela:BAAANQADCgEIAQAAAA==.Lilipo:BAABNQAECn8dAAIlAAcK1gYJGwDRAAAlAAcK1gYJGwDRAAAAAA==.',
Ll='Llarastrasza:BAAANQAECgIIAgABNQAECggICgAQAAAAAA==.',
Lo='Logoth:BAAANQAECgQIBAAAAA==.Lohgarak:BAAANQADCggIFQAAAA==.',
Lu='Lunaellana:BAAANQADCgYICAAAAA==.',
Ly='Lystaan:BAAANQABCgQIBAAAAA==.',
['Lü']='Lüvpüp:BAACNQAFFH8HAAISAAMK3RZhAgCQAAASAAMK3RZhAgCQAAA1AAQKfx4AAhIACQqrImIFAD0DABIACQqrImIFAD0DAAAA.',
Ma='Magicfang:BAAANQADCgQIBAAAAA==.Maiku:BAABNQAECn8nAAIGAAgK7hMgbAAZAgAGAAgK7hMgbAAZAgAAAA==.Majo:BAAANQAECgIIAgAAAA==.Makado:BAABNQAECn8bAAQjAAoKZwf3DwBOAQAGAAkKFgYKuABeAQAjAAcKlgf3DwBOAQAeAAEKAAB0hAAmAAAAAA==.Makaris:BAAANQAECgQIBAAAAA==.Maklur:BAAANQAECgQIBAAAAA==.Makoa:BAAANQADCgQIBAAAAA==.Makoroth:BAABNQAECn8hAAIGAAkKgxLfPQATAQAGAAkKgxLfPQATAQAAAA==.Malanda:BAAANQADCgQIBAAAAA==.Malygosson:BAAANQAECgUIDAAAAA==.Masharu:BAAANQADCgcIBwAAAA==.Matua:BAAANQAECgIIAgAAAA==.Maycee:BAAANQAECgYIEQAAAA==.',
Mc='Mcat:BAAANQAECgMIBgAAAA==.Mcgriddle:BAAANQADCgEIAQAAAA==.Mcnaugh:BAAANQAECgMIBwAAAA==.Mcsaltface:BAAANQAECgMICgAAAA==.',
Me='Meddic:BAAANQAECgYIEwAAAA==.Megavolt:BAAANQAECgUIBgAAAA==.Menarot:BAAANQAECgYIDwAAAA==.Mendais:BAAANQADCgYIDgAAAA==.Meztlitotol:BAABNQAECn8YAAMRAAcKhCCQDQCNAgARAAcKhCCQDQCNAgATAAEKAACQQAA5AAABNQAECgoKMgAFAGkcAA==.',
Mi='Mirosdrigo:BAAANQADCgcIBwAAAA==.Mirosmundo:BAABNQAECn8qAAIHAAoK9RkwCACtAgAHAAoK9RkwCACtAgAAAA==.Mistfit:BAAANQAECggIDwAAAA==.Miyu:BAABNQAECn8rAAMMAAoKVBJiJwDwAQAMAAkKog9iJwDwAQAEAAkKnQSKmgBFAQAAAA==.',
Mo='Mod:BAABNQAECn8wAAMIAAkKOhrZFQCmAQAIAAkKOhrZFQCmAQANAAEKAABJRAEsAAAAAA==.Moeng:BAAANQADCgIIAgAAAA==.Moggatorash:BAAANQAECgUIDwAAAA==.Mogtham:BAABNQAECn8sAAIRAAgKahPeGgDNAQARAAgKahPeGgDNAQAAAA==.Monlaferte:BAAANQAECgcIBwAAAA==.Montsegur:BAAANQADCggICAAAAA==.Mooforn:BAAANQAECgMICgAAAA==.Moonfall:BAAANQAECgUIDwAAAA==.Moosader:BAABNQAECn8VAAMXAAcKmg91zQCBAQAXAAcKmg91zQCBAQAYAAcKOQganABPAQAAAA==.Morellea:BAAANQAECgUJCgAAAA==.Morighann:BAABNQAECn8uAAIVAAgK3CC9CAA6AgAVAAgK3CC9CAA6AgAAAA==.Moñgoose:BAAANQADCgMIAwAAAA==.',
My='Mynkx:BAABNQAECn8bAAIXAAoKXBX5EgDjAQAXAAoKXBX5EgDjAQAAAA==.Mythyras:BAABNQAECn8hAAIkAAgKjBwdFABkAgAkAAgKjBwdFABkAgAAAA==.',
Na='Naeomy:BAABNQAECn88AAIhAAoKHQh1CgB7AQAhAAoKHQh1CgB7AQAAAA==.Nahaman:BAAANQAECgQIBwAAAA==.Napolien:BAABNQAECn8yAAMkAAkKHQ+kDQArAQAkAAgKHQ+kDQArAQAYAAMKrA8D7ACpAAAAAA==.Naugan:BAAANQADCgEIAQAAAA==.',
Ne='Nechahira:BAACNQAFFH8PAAIUAAUK5A1cBAAcAQAUAAUK5A1cBAAcAQA1AAQKfxgAAxQACQrGDL0vAJ0BABQACApiDb0vAJ0BABEAAQoAAERLAAAAAAAA.Nensho:BAAANQAECgEIAQAAAA==.Nethim:BAAANQAECgMIBQAAAA==.Nezana:BAAANQAECgIIAgAAAA==.',
Ni='Nien:BAAANQAECgMIAwAAAA==.Nightfallen:BAAANQAECgQIBAAAAA==.Nihlathak:BAAANQAECgYIDgAAAA==.Ninada:BAABNQAECn8aAAMdAAcKbAzvAwGHAQAdAAcK0grvAwGHAQAiAAIKcgifQwA8AAAAAA==.Ninalee:BAAANQAECgYICQAAAA==.',
No='Noranna:BAAANQAECgMICgAAAA==.',
Ny='Nyim:BAAANQAECgEIAQAAAA==.Nymiria:BAAANQABCgEIAQABNQAECgYIEgAQAAAAAA==.Nynsyn:BAAANQAECgUICgABNQAECggIIQAkAIwcAA==.Nyxeira:BAAANQAECgYIDwAAAA==.',
['Nâ']='Nâli:BAAANQAECgQIBAAAAA==.',
Ob='Obsidianclaw:BAAANQADCgIIAwAAAA==.',
Oh='Ohthesemyboo:BAAANQAECgUICQAAAA==.Ohwellz:BAAANQAECgEIAQAAAA==.',
Op='Ophin:BAABNQAECn8qAAILAAkKKReuQQAWAgALAAkKKReuQQAWAgAAAA==.',
Pa='Panamared:BAABNQAECn8kAAIbAAgKgBWLFgAtAgAbAAgKgBWLFgAtAgAAAA==.Pappawoody:BAABNQAECn8cAAICAAgKCBxkbwBFAgACAAgKCBxkbwBFAgAAAA==.Parishealton:BAAANQADCgcIBwAAAA==.',
Pe='Pellegryn:BAAANQADCgYICQAAAA==.Pennyfeather:BAABNQAECn8rAAMEAAgKixAlLwBBAQAEAAgKixAlLwBBAQAMAAQKygkUUgDHAAAAAA==.Pezza:BAABNQAECn8aAAIIAAcK2xFhNgALAQAIAAcK2xFhNgALAQAAAA==.',
Ph='Phaze:BAABNQAECn8qAAImAAgKWB/eAAALAgAmAAgKWB/eAAALAgAAAA==.Phideauxe:BAAANQAECgQIBgAAAA==.Phorate:BAAANQAECgQICQAAAA==.',
Pl='Pluralbutter:BAABNQAECn8bAAIaAAoKqA2iPADSAQAaAAoKqA2iPADSAQAAAA==.',
Po='Popexeo:BAAANQAECgcIDQABNQAFFAcIDgAUADARAA==.',
Pr='Prometheum:BAAANQAECgQICAAAAA==.',
Ps='Psyvern:BAABNQAECn8eAAIPAAgKogg3DgBkAQAPAAgKogg3DgBkAQAAAA==.',
Qu='Quiccerstorm:BAAANQADCgQIBQAAAA==.',
Ra='Raevennlumis:BAABNQAECn8XAAIXAAgKBAkp5gBPAQAXAAgKBAkp5gBPAQAAAA==.Raevenns:BAAANQADCggJCAABNQAECggIFwAXAAQJAA==.Rahkhard:BAABNQAECn8yAAMHAAoKCiBVAQD6AQAHAAoKCiBVAQD6AQAlAAUK/BN3QQAMAQAAAA==.Rascdit:BAAANQAECgUIDAAAAA==.',
Re='Recreant:BAAANQAECgUICgAAAA==.Reiyoso:BAAANQAECgIIAgAAAA==.Reui:BAAANQADCgEIAQAAAA==.',
Rh='Rhemibumbum:BAAANQAECgUIDwAAAA==.',
Ro='Rocketbilly:BAAANQAECgEIAQAAAA==.Roobee:BAABNQAECn8ZAAIeAAYKTQPjPADOAAAeAAYKTQPjPADOAAAAAA==.',
Ru='Ruaic:BAAANQADCggIEgAAAA==.',
Sa='Sableanne:BAAANQADCgEIAQAAAA==.Sacréd:BAABNQAECn8VAAIkAAYKyBcSLAB8AQAkAAYKyBcSLAB8AQAAAA==.Sarkan:BAAANQADCggIEQAAAA==.Sarova:BAABNQAECn8UAAIVAAgKhBQaHACnAQAVAAgKhBQaHACnAQAAAA==.Satori:BAAANQAECgMICgAAAA==.',
Sc='Scalewind:BAAANQADCgYIBgAAAA==.',
Se='Seldeath:BAAANQADCgEJAQAAAA==.Selfu:BAABNQAECn8tAAIlAAgKaRWPIgAUAgAlAAgKaRWPIgAUAgAAAA==.Sellidor:BAABNQAECn8uAAIVAAoKXiI5CQAzAgAVAAoKXiI5CQAzAgAAAA==.Serenesong:BAAANQADCgEIAQAAAA==.Seriniyaa:BAAANQAECgIIAgAAAA==.Serioth:BAAANQADCgIIAgAAAA==.',
Sh='Sheara:BAAANQAECggIEgAAAA==.Shinjiro:BAABNQAECn8eAAIXAAcKDQJhTQGkAAAXAAcKDQJhTQGkAAAAAA==.Shirito:BAABNQAECn85AAMJAAkKdCR1AQDWAgALAAgKVSUCCwBjAwAJAAkKRyN1AQDWAgAAAA==.Shiritodh:BAABNQAECn8hAAIDAAkKcCAaBgCvAQADAAkKcCAaBgCvAQAAAA==.Shockin:BAAANQAECgcIDwAAAA==.Shortnstout:BAACNQAFFH8KAAIkAAMKrhluAgDjAAAkAAMKrhluAgDjAAA1AAQKfyYAAyQACgpfImgLAOICACQACgpfImgLAOICABcAAQrIG7aLAUoAAAAA.Shugo:BAAANQAECgUIEAAAAA==.',
Si='Sienje:BAABNQAECn8fAAIXAAkKzRZgdABFAgAXAAkKzRZgdABFAgAAAA==.Sigma:BAABNQAECn8gAAIVAAgKQAZttQCZAQAVAAgKQAZttQCZAQAAAA==.Simpleson:BAABNQAECn8oAAMGAAkKIhk0UwBcAgAGAAgKFhk0UwBcAgAeAAEKbhlnagBMAAAAAA==.Sinbàd:BAACNQAFFH8KAAIDAAUKMxQPBwCeAQADAAUKMxQPBwCeAQA1AAQKfywAAgMACgonG3sVALgCAAMACgonG3sVALgCAAAA.Sinistris:BAAANQAECgEIAgAAAA==.',
Sk='Skie:BAAANQAECggIDQABNQAECggIIQAUAPUYAA==.Skrabble:BAAANQAECgQIDQAAAA==.Skölldraugos:BAAANQAECgEIAwAAAA==.',
Sl='Slaete:BAABNQAECn8UAAIaAAYKEwWTYAD6AAAaAAYKEwWTYAD6AAAAAA==.Slush:BAAANQAECgQIBAAAAA==.',
Sm='Smallz:BAAANQAECgUIDQABNQAECgkJIQAVAPYUAA==.Smorgas:BAAANQAECgEIAQABNQAECgkJIQAXAOMcAA==.Småug:BAAANQADCgMJAwAAAA==.',
So='Solemn:BAABNQAECn8kAAIMAAgK0RZaBAC+AQAMAAgK0RZaBAC+AQABNQAECgoKLgAVAF4iAA==.Solrana:BAAANQAECgMIBgAAAA==.Songmistress:BAABNQAECn8VAAIGAAgKzwUCbwClAAAGAAgKzwUCbwClAAAAAA==.Sorren:BAAANQAECgIIAwAAAA==.Sotta:BAAANQAECgIIBQAAAA==.Sozin:BAAANQADCgIIAgAAAA==.',
Sp='Speirs:BAAANQAECggIAgAAAA==.Spritmoon:BAAANQADCgYIBgAAAA==.',
Sq='Squeezee:BAAANQAECgEIAQAAAA==.',
St='Stardrive:BAABNQAECn8VAAIIAAYKdhzgHwBpAQAIAAYKdhzgHwBpAQAAAA==.Stevesteve:BAABNQAECn8dAAIGAAgK3wh0IgBkAQAGAAgK3wh0IgBkAQAAAA==.Stroganov:BAAANQAECgIIAgABNQAECgcIEwAQAAAAAA==.Stumpii:BAAANQADCgIIAgAAAA==.',
Su='Sunasha:BAAANQADCgYIEgAAAA==.Superbautumn:BAAANQAECgUIDQAAAA==.',
Sy='Synge:BAAANQAECgUIDwAAAA==.Synnyca:BAAANQADCgcJBwABNQAECggIIQAkAIwcAA==.',
['Sé']='Sélune:BAAANQAECggICgAAAA==.',
Ta='Tachyon:BAAANQAECgYICQABNQAFFAMIBwASAN0WAA==.Taeonaki:BAAANQAECgQIBQAAAA==.Tagnaras:BAAANQAECgUICgAAAA==.Tahlang:BAAANQAECgEIAgAAAA==.Tali:BAAANQAECgMICAAAAA==.Taliasluage:BAAANQADCggICAABNQAECgkJOwAiAFIaAA==.Tangle:BAABNQAECn8hAAMUAAgK9RjeCgCLAQAUAAcKCRneCgCLAQABAAYKZgVygADNAAAAAA==.Tanka:BAABNQAECn8kAAICAAgKrByQWwB5AgACAAgKrByQWwB5AgAAAA==.Tannisse:BAAANQADCggIFQAAAA==.Tanuki:BAAANQAECgIIAwAAAA==.Tapol:BAAANQAECgUICwABNQAECgYIEgAQAAAAAA==.Tashlaraz:BAEANQAECgEIBgAAAA==.Tasi:BAAANQAECgQIBQAAAA==.Taurannosaur:BAAANQAECgEIAQAAAA==.Taurentots:BAAANQAFFAMIAwAAAA==.',
Te='Telkas:BAAANQADCgUIBQAAAA==.Temporantus:BAAANQAECgMIBQAAAA==.Tenko:BAABNQAECn8lAAMdAAgK8wrFMwBYAQAdAAgKLgrFMwBYAQAiAAIKdAzaNQBkAAAAAA==.',
Th='Thaddeus:BAAANQAECgYIDgAAAA==.Therm:BAACNQAFFH8QAAIXAAYKJBzgBQD4AQAXAAYKJBzgBQD4AQA1AAQKf0AAAxcACgrFJpwBAPgDABcACgrFJpwBAPgDABgAAQrQBwQgATYAAAAA.Thoramier:BAAANQAECgYIDQAAAA==.',
Ti='Tibble:BAAANQAECgUIDQAAAA==.Timoonja:BAAANQAECgUIDwAAAA==.Tirazlea:BAAANQADCgIIAgAAAA==.',
To='Tonatuih:BAABNQAECn8rAAIaAAoKuxzkFQDuAgAaAAoKuxzkFQDuAgAAAA==.',
Tr='Trezzia:BAABNQAECn8bAAIjAAgKShTLBgA6AgAjAAgKShTLBgA6AgAAAA==.Triipod:BAAANQADCgYIFQAAAA==.Trinkat:BAAANQAECgMICQAAAA==.Trojinn:BAAANQAECgUIBgAAAA==.Tryst:BAAANQADCgYIBgAAAA==.Tráson:BAAANQADCgYIBQAAAA==.',
Tu='Tub:BAAANQAECggIEgAAAA==.',
Ty='Tychlora:BAAANQAECgEIAgABNQAECgoKMgAFAGkcAA==.Tylean:BAAANQAECgQIBwAAAA==.',
['Tì']='Tìríon:BAAANQAECgEIAQAAAA==.',
Ud='Udukai:BAAANQAECgQIBAAAAA==.',
Ul='Ultrastealth:BAABNQAECn8UAAQbAAUK1QS9PADSAAAbAAUK1QS9PADSAAAhAAMKRQNTkQBtAAAnAAEKpgL/HgAdAAAAAA==.',
Um='Umbrum:BAAANQAECgEIAQABNQAECgoKMgAFAGkcAA==.',
Uu='Uu:BAAANQAECgQICQAAAA==.',
Va='Vadrozsa:BAAANQAECgIIAgAAAA==.Vallarie:BAAANQADCgQJBAAAAA==.Vareyn:BAAANQAECgMIBAAAAA==.',
Vo='Vorth:BAABNQAECn8rAAIJAAoKcxBrOgDoAQAJAAoKcxBrOgDoAQAAAA==.Vorukh:BAAANQADCgQIBAABNQAECgIIBQAQAAAAAA==.Vorúkh:BAAANQAECgUICgABNQAECgIIBQAQAAAAAA==.Vorükh:BAAANQAECgUIBQABNQAECgIIBQAQAAAAAA==.',
Vu='Vulturous:BAAANQADCgYICgAAAA==.',
Vy='Vydian:BAAANQADCgYICQAAAA==.Vyrlana:BAAANQAECgEIAQAAAA==.',
Wa='Waldir:BAABNQAECn8qAAMYAAgKgSPvEwAzAwAYAAgKgSPvEwAzAwAXAAIKIAeQhgFRAAAAAA==.Walock:BAAANQAECgEIAQAAAA==.Wanted:BAAANQADCgYIBgAAAA==.Watz:BAAANQAECgYIBgAAAA==.',
We='Wensa:BAAANQADCgcIBwAAAA==.',
Wh='Wholesale:BAABNQAECn8uAAIKAAgK4BY7DQB8AQAKAAgK4BY7DQB8AQAAAA==.',
Wo='Wonders:BAAANQAECgEIAgAAAA==.',
Wr='Wrack:BAAANQADCggIEQAAAA==.Wraithian:BAAANQAECgEIAQAAAA==.Wratsoul:BAABNQAECn8YAAIGAAoKOAtifgDqAQAGAAoKOAtifgDqAQAAAA==.',
Xe='Xessala:BAABNQAECn8lAAIIAAgKIhi1FACuAQAIAAgKIhi1FACuAQAAAA==.',
Xh='Xheero:BAABNQAECn8zAAIVAAkK5x1aDwD1AQAVAAkK5x1aDwD1AQAAAA==.Xheerom:BAAANQADCgUIBQAAAA==.',
Ya='Yagiashi:BAAANQAECgQIBQABNQAECgoKMgAFAGkcAA==.',
Yu='Yulica:BAAANQAECgMICgAAAA==.',
Za='Zaffy:BAABNQAECn8qAAIeAAgKdg8JAgBYAQAeAAgKdg8JAgBYAQAAAA==.Zaktrix:BAAANQAECgIIBAAAAA==.Zaleron:BAAANQADCggIFAAAAA==.Zaruba:BAABNQAECn8kAAMNAAgKWAhGhgCVAQANAAgKWAhGhgCVAQAIAAEKsAFrqQAYAAABNQAECggIJgABAE8KAA==.Zatkyng:BAABNQAECn8iAAIlAAkKrw7ZDQBEAQAlAAkKrw7ZDQBEAQAAAA==.',
Ze='Zekos:BAAANQAECgEIAgAAAA==.',
Zi='Zillver:BAAANQAECgUIBQABNQAECgkJMgAkAB0PAA==.Zimdalar:BAAANQAECgUIEQAAAA==.',
Zu='Zulre:BAABNQAECn8sAAMKAAkKgx1kGwDUAgAKAAkKgx1kGwDUAgAJAAQKGQ1qPQCuAAAAAA==.',
['Ôv']='Ôverkill:BAABNQAECn8aAAIRAAcKVhdDFwD5AQARAAcKVhdDFwD5AQAAAA==.',
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
