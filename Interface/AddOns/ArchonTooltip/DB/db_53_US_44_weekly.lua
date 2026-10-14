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

local lookup = {'Mage-Arcane','Hunter-BeastMastery','Rogue-Subtlety','Warrior-Arms','Unknown-Unknown','DeathKnight-Unholy','Shaman-Restoration','Druid-Restoration','Druid-Balance','Druid-Guardian','Priest-Holy','Warrior-Fury','Paladin-Retribution','Evoker-Preservation','DeathKnight-Blood','Priest-Shadow','Hunter-Marksmanship','Priest-Discipline','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Holy','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Mage-Fire','DemonHunter-Vengeance','Druid-Feral','Shaman-Enhancement','Shaman-Elemental','Monk-Brewmaster','Warlock-Affliction','DeathKnight-Frost','Evoker-Devastation','Evoker-Augmentation','Monk-Mistweaver','Monk-Windwalker','Hunter-Survival',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abobadrin:BAAANQADCgcIDgAAAA==.Abrakadaver:BAABNQAECn8eAAIBAAgKiBdZrwAiAgABAAgKiBdZrwAiAgAAAA==.',
Ac='Acceb:BAAANQADCgQJBAAAAA==.',
Ad='Adventureux:BAABNQAECn8jAAICAAkKVRl+OwC1AgACAAkKVRl+OwC1AgAAAA==.',
Ae='Aedx:BAABNQAECn8oAAIDAAkKIxWGEgBaAgADAAkKIxWGEgBaAgAAAA==.Aerolorea:BAAANQADCgYICQAAAA==.',
Al='Alastar:BAABNQAECn8ZAAIEAAgK6h6hWwB2AgAEAAgK6h6hWwB2AgABNQAFFAEIAQAFAAAAAA==.Alexmage:BAAANQADCgYIBgABNQADCgcIBwAFAAAAAA==.Alios:BAAANQAECgQIBAAAAA==.Alphasalt:BAAANQADCgcIBwABNQAECgQIDgAFAAAAAA==.Alucard:BAAANQAECgYIDwAAAA==.Alunadoom:BAAANQAECgcIDwAAAA==.Alvera:BAACNQAFFH8KAAIGAAQK6BcmCwBZAQAGAAQK6BcmCwBZAQA1AAQKfy4AAgYACQrEJIEHAIgDAAYACQrEJIEHAIgDAAAA.',
Am='Ambellìna:BAAANQADCgIIAgABNQAECgEIAQAFAAAAAA==.',
An='Ancestor:BAABNQAECn8kAAIHAAkKjBJOSgA2AgAHAAkKjBJOSgA2AgAAAA==.Angechi:BAEANQADCgIJAgABNQAFFAEIAQAFAAAAAA==.Angrydk:BAAANQAECgEIAQAAAA==.Antisocial:BAABNQAECn8pAAIGAAkKaiIAEgAmAwAGAAkKaiIAEgAmAwABNQAECgkKKQAGAGoiAA==.',
Ar='Arm:BAABNQAECn86AAQIAAkK4xaCFwCBAgAIAAkK4xaCFwCBAgAJAAYKmAyVZQAzAQAKAAIKehM7UABaAAAAAA==.Armee:BAABNQAECn8aAAILAAgKehhrVgAcAgALAAgKehhrVgAcAgAAAA==.Armz:BAAANQABCgEIAQAAAA==.',
As='Astrael:BAAANQAECgcIDwAAAA==.Aszea:BAAANQAECgIIAwAAAA==.',
At='Attewode:BAAANQAECgEIAQAAAA==.',
Ax='Axra:BAABNQAECn8bAAIMAAkKog4MDQDlAQAMAAkKog4MDQDlAQAAAA==.',
Ay='Ayda:BAAANQADCgIIAQAAAA==.',
Az='Azairius:BAAANQADCggIEAAAAA==.Azzman:BAAANQADCgMIAwAAAA==.Azóg:BAAANQAECgcIEQAAAA==.',
Ba='Balsin:BAABNQAECn8kAAINAAkKhSNsEwB3AwANAAkKhSNsEwB3AwAAAA==.Bambii:BAAANQADCgUIBwAAAA==.Bangungot:BAAANQAECgUIBgABNQAFFAcIFAAOAB0XAA==.Barlaf:BAABNQAECn82AAICAAgK4R+5NQDHAgACAAgK4R+5NQDHAgABNQAECgIIAwAFAAAAAA==.Batou:BAAANQAECgUICAAAAA==.',
Be='Beeski:BAAANQADCgYIFQAAAA==.Beeto:BAACNQAFFH8HAAINAAMKzgucGQDWAAANAAMKzgucGQDWAAA1AAQKfysAAg0ACQrSGMuRAPwBAA0ACQrSGMuRAPwBAAAA.Belyndris:BAABNQAECn8cAAILAAkKkxRMQwBbAgALAAkKkxRMQwBbAgAAAA==.Benbear:BAEANQAFFAEIAQAAAA==.Benlian:BAEBNQAECn8iAAIPAAgKDhHqUQCqAQAPAAgKDhHqUQCqAQABNQAFFAEIAQAFAAAAAA==.',
Bl='Blighty:BAAANQAECgYIDQAAAA==.Blâze:BAACNQAFFH8PAAIBAAUK+xivGgCgAQABAAUK+xivGgCgAQA1AAQKfyIAAgEACQrkGl54AI0CAAEACQrkGl54AI0CAAAA.',
Bo='Bombardi:BAAANQAECgMIAwAAAA==.Bonknsmash:BAABNQAECn8fAAIEAAgKJhQnjAD6AQAEAAgKJhQnjAD6AQAAAA==.Boof:BAABNQAECn8jAAIQAAkK+hTFHABaAgAQAAkK+hTFHABaAgAAAA==.Boregut:BAAANQAECggICAAAAA==.',
Br='Brewdock:BAAANQABCgIIAgAAAA==.Bronxor:BAABNQAECn8kAAIRAAkK6RM1IQBBAgARAAkK6RM1IQBBAgAAAA==.',
Bu='Bubbleoshift:BAAANQAECgMIAwABNQAECgcIEQAFAAAAAA==.Bushgarden:BAAANQADCgYIBwABNQADCgYICgAFAAAAAA==.Buzsmash:BAAANQAECgYIBgAAAA==.Buzzbuzz:BAAANQAECgMIBQABNQAECgkJGgABAMwQAA==.',
['Bó']='Bóba:BAACNQAFFH8dAAIOAAcKUiKQAQC8AgAOAAcKUiKQAQC8AgA1AAQKfygAAg4ACQrCI9UFAEwDAA4ACQrCI9UFAEwDAAAA.',
['Bö']='Böba:BAABNQAECn8ZAAQLAAkKkCT3CwBhAwALAAkKkCT3CwBhAwASAAYKCyBaBgAnAgAQAAEKAACrdwA1AAABNQAFFAcIHQAOAFIiAA==.',
Ca='Cadiva:BAAANQADCgQIBAABNQAECgcIEQAFAAAAAA==.Cadroyd:BAABNQAECn8aAAMIAAkKjBqsGgBgAgAIAAgKQhmsGgBgAgAJAAIK4AGMnQBhAAAAAA==.Caelin:BAABNQAECn8wAAMTAAkKpBMmNQAAAgATAAgKpBMmNQAAAgAUAAMK1g/sVgCoAAAAAA==.Cailand:BAABNQAECn8dAAIEAAcKxRalhQAKAgAEAAcKxRalhQAKAgAAAA==.Caishana:BAABNQAECn8rAAIHAAkKIiKCDgBMAwAHAAkKIiKCDgBMAwAAAA==.Cambium:BAAANQAECgYIEAAAAA==.Camerbunne:BAAANQADCgYIDwAAAA==.Catdude:BAAANQAECgQJBQAAAA==.',
Ce='Cecil:BAAANQADCgYIBgAAAA==.Celebrate:BAAANQADCgMIAwAAAA==.',
Ch='Chaddingus:BAAANQAECggICwAAAA==.Chopadk:BAABNQAECn8gAAIPAAkKsA9fUgCoAQAPAAkKsA9fUgCoAQAAAA==.Chumlëy:BAAANQADCgUIBQAAAA==.',
Cl='Clash:BAAANQADCgUICAAAAA==.Clique:BAABNQAECn8fAAIVAAgKVBsVNwCFAgAVAAgKVBsVNwCFAgAAAA==.',
Cn='Cnc:BAAANQAECgEIAQAAAA==.',
Co='Coheedkil:BAAANQAECgEIAQAAAA==.Coldbreeze:BAABNQAECn8aAAIBAAcK8wc8FAFnAQABAAcK8wc8FAFnAQAAAA==.Collateral:BAAANQAECgQIBAAAAA==.Colomel:BAAANQAECgYIDQAAAA==.Comegetsum:BAAANQADCgYIEQAAAA==.Compaktdisc:BAAANQADCgYJBgABNQAECgcIEQAFAAAAAA==.Conqbine:BAAANQAECgIIAgAAAA==.Corg:BAAANQAECgQIBAAAAA==.Countchocula:BAAANQAECgUIDgAAAA==.',
Cr='Crimmi:BAAANQAECgYIDwAAAA==.Critzilla:BAAANQAECgUIBQAAAA==.',
Cu='Cuddy:BAAANQADCgYICgAAAA==.',
Cy='Cybuster:BAAANQADCgUJBQABNQAECgkJIwABADsbAA==.Cyndle:BAABNQAECn8tAAIHAAkKiQpGdACrAQAHAAkKiQpGdACrAQAAAA==.',
Da='Daddythicc:BAABNQAECn8hAAIBAAgK1gkd4wC/AQABAAgK1gkd4wC/AQAAAA==.Darnwrath:BAAANQAECgYIBgAAAA==.Darrkness:BAAANQADCgYIBgAAAA==.',
De='Deadgirljd:BAAANQAECgQIBQAAAA==.Deadillusion:BAAANQADCgUIBQABNQAECgYIBwAFAAAAAA==.Deathpockets:BAAANQAECgMIBAAAAA==.Deran:BAABNQAECn8jAAMNAAgK8httYAB0AgANAAgKhRptYAB0AgAWAAYKZRrWLAByAQAAAA==.',
Di='Diante:BAAANQAECgIIAwAAAA==.Dimple:BAAANQAECgIJAgAAAA==.Dirtmonkgirt:BAAANQAECgcIEwAAAA==.',
Dk='Dknujabes:BAAANQAECggIDwAAAA==.',
Do='Doofus:BAAANQADCgEIAQAAAA==.Doompockets:BAABNQAECn8iAAMXAAkKxgychgDRAQAXAAkKrgmchgDRAQAYAAMKJg22RgCrAAAAAA==.',
Dr='Dracara:BAABNQAECn8mAAQZAAkKnxdhBQC8AgAZAAkKnxdhBQC8AgAaAAUK4wyKBQAiAQABAAMKrAXolwGPAAAAAA==.Dracia:BAAANQAECgYIEAAAAA==.Drakulya:BAAANQABCgQIBAAAAA==.Dreadz:BAABNQAECn8bAAMUAAcKkBCcNACaAQAUAAcKJhCcNACaAQAbAAIKJAn9KQBfAAAAAA==.Drewish:BAABNQAECn8jAAIcAAgKtR9GBwDqAgAcAAgKtR9GBwDqAgAAAA==.Drg:BAAANQADCgQIBAABNQADCgUIBQAFAAAAAA==.Drizzle:BAABNQAECn8pAAIUAAkKHSPHBACGAwAUAAkKHSPHBACGAwAAAA==.Drktotem:BAABNQAECn8lAAMdAAkKDiEEAwByAwAdAAkKDiEEAwByAwAHAAYKtxYMjwBfAQAAAA==.Druidia:BAAANQADCgIIAgAAAA==.',
Du='Dulezlok:BAAANQADCgUIBQAAAA==.Dumbdog:BAACNQAFFH8jAAIIAAcK7yJ8AADNAgAIAAcK7yJ8AADNAgA1AAQKfzwAAggACQqoI9wDAIcDAAgACQqoI9wDAIcDAAAA.Dumbledwarf:BAAANQADCggICAAAAA==.Dusan:BAABNQAECn8mAAILAAgKeR3OMgCaAgALAAgKeR3OMgCaAgAAAA==.',
['Dï']='Dïvinity:BAAANQADCgIIAgAAAA==.',
Ea='Ea:BAAANQADCgcICAAAAA==.',
Ec='Echeyaket:BAABNQAECn8bAAMHAAgKLhsLQABdAgAHAAgKLhsLQABdAgAeAAIKmRCzCwFtAAAAAA==.',
Ed='Edonsian:BAABNQAECn8zAAIEAAkKfhc8VQCIAgAEAAkKfhc8VQCIAgAAAA==.',
Eg='Egmont:BAAANQADCgUIBwAAAA==.',
El='Elektabuzz:BAAANQADCggIEAABNQAECggIGgANAOgbAA==.Elelusion:BAAANQAECgYIBwAAAA==.Elliekins:BAAANQAECgcIEAAAAA==.Elçhapo:BAAANQAECgIIAwAAAA==.',
En='Endlesshour:BAAANQADCgMIAwAAAA==.Endlessly:BAAANQAECgUIBgAAAA==.Enoka:BAABNQAECn8fAAIBAAgKHxcwrgAlAgABAAgKHxcwrgAlAgAAAA==.',
Es='Estelá:BAAANQADCgYIBgAAAA==.',
Et='Etikwa:BAABNQAECn8ZAAIIAAgKKAnnNgBgAQAIAAgKKAnnNgBgAQAAAA==.',
Eu='Euclid:BAAANQAECgMIAwAAAA==.',
Ev='Evilguard:BAABNQAECn8aAAIPAAgKlA08XgB2AQAPAAgKlA08XgB2AQAAAA==.',
Ex='Excessive:BAAANQAECgIIAgAAAA==.Exroastbeef:BAAANQADCggICAAAAA==.',
Fa='Falador:BAAANQAECgUIDwAAAA==.Fariebubbles:BAAANQAECgIIAwAAAA==.',
Fe='Felene:BAABNQAECn8fAAMeAAkKcxvHKADcAgAeAAkKcxvHKADcAgAHAAIK7A7Z/wBjAAAAAA==.Fenwell:BAAANQADCgcIBwAAAA==.',
Fi='Firitako:BAAANQAECgYIDQAAAA==.',
Fr='Frailey:BAAANQAECgYIEAAAAA==.Frankiejr:BAAANQAECgEIAQABNQAECgcIGQANALQiAA==.Fraubles:BAAANQAECgMIBAAAAA==.Friedpickel:BAAANQADCgYIBwAAAA==.Friter:BAAANQADCggICQAAAA==.Frostnite:BAAANQAECgQICAAAAA==.Frostpoptart:BAABNQAECn8nAAIdAAkKuRqsCQDYAgAdAAkKuRqsCQDYAgAAAA==.Frozenblade:BAABNQAECn8jAAIPAAkKJRUUQQD2AQAPAAkKJRUUQQD2AQAAAA==.',
Fu='Furball:BAAANQAECgUIBQABNQAFFAQICwAYAP8QAA==.Furiousgeorg:BAAANQAECgUIDAAAAA==.',
Ga='Gagabooney:BAABNQAFFH8GAAIfAAIKsiI+BwDHAAAfAAIKsiI+BwDHAAAAAA==.Garabashi:BAAANQADCgcJBwAAAA==.Garrick:BAAANQAECgYIDAAAAA==.Gazze:BAABNQAECn8mAAIKAAgKIAmtKQBEAQAKAAgKIAmtKQBEAQAAAA==.',
Ge='Gemli:BAAANQADCgUIBQAAAA==.Gennissa:BAAANQAECgMIBAAAAA==.Gethsemane:BAABNQAECn8iAAMXAAkKLBagQwCEAgAXAAkKLBagQwCEAgAgAAQK6RRlEgAgAQAAAA==.',
Gi='Gigadoot:BAAANQABCgQIAgAAAA==.Gigglez:BAAANQADCgcJCQAAAA==.Gillis:BAAANQADCggIDAAAAA==.',
Gl='Glassdance:BAAANQADCgcIBwAAAA==.',
Gn='Gnryderp:BAAANQADCgUIBQAAAA==.',
Go='Goam:BAAANQADCggIFwAAAA==.Googrektar:BAAANQAECgQIBAABNQAFFAIIBgABAEccAA==.Goonielama:BAABNQAECn8mAAIPAAkKYyBLDgA8AwAPAAkKYyBLDgA8AwABNQAFFAIIBgAfALIiAA==.Goonietai:BAAANQAECgUICQABNQAFFAIIBgABAEccAA==.',
Gr='Greenterror:BAAANQADCgIIAgAAAA==.Grid:BAAANQAECgEIAQABNQAECgkJQwAXAJkkAA==.Griitz:BAAANQAECgQICAAAAA==.Grimmsheeper:BAACNQAFFH8JAAIBAAQK8RMcKQA5AQABAAQK8RMcKQA5AQA1AAQKfy4AAgEACQqPIiZEAPsCAAEACQqPIiZEAPsCAAAA.Gryff:BAAANQADCgUJBQAAAA==.',
Gu='Guess:BAAANQAECgQIBAAAAA==.Gurtdk:BAACNQAFFH8gAAQGAAcKLxoyBADtAQAGAAUKyB8yBADtAQAPAAEKAAAHKABWAAAhAAEKyQMNGwBSAAA1AAQKfykAAgYACQq+JQkLAGIDAAYACQq+JQkLAGIDAAAA.',
Gy='Gyat:BAAANQADCgMJAwAAAA==.',
Ha='Hairynujabes:BAAANQAECggIDgAAAA==.Hamandcheeze:BAAANQABCgcIBwAAAA==.Hanyuu:BAABNQAECn8eAAIQAAkKTwhqLwCkAQAQAAkKTwhqLwCkAQAAAA==.',
He='Heiter:BAABNQAECn8mAAILAAkKCxgrQgBfAgALAAkKCxgrQgBfAgAAAA==.Hellbound:BAABNQAECn8qAAMXAAgK8Rj6XAA9AgAXAAgK+Rb6XAA9AgAYAAIK/BOPVAB/AAAAAA==.Hellinhunt:BAABNQAFFH8IAAMCAAcKyQwnFwD9AAARAAQKRQg6EgAWAQACAAMKkRMnFwD9AAAAAA==.',
Ho='Holyekko:BAAANQADCgEIAQAAAA==.Holypants:BAAANQADCgYIBgAAAA==.Honk:BAAANQAECgUIBQABNQAECgkJGgABAMwQAA==.Hornivore:BAAANQADCgcIFQABNQAECggILQACAOsaAA==.',
Hy='Hyrja:BAAANQADCgUIBgABNQAECgkJJgAZAJ8XAA==.',
Ic='Icefrosting:BAAANQAECgYIDgAAAA==.',
Id='Idistroya:BAAANQAECgQICAABNQAECgkJIAACAG8aAA==.',
Ig='Iggnogg:BAAANQAECgMIAwAAAA==.',
Ik='Ikura:BAACNQAFFH8NAAILAAUKHg41EgB3AQALAAUKHg41EgB3AQA1AAQKfyQABBIACQoxEywNAGEBAAsACQqDD5dlAOoBABIABwoyDSwNAGEBABAAAQoAAMuFACIAAAAA.',
Il='Ilithiya:BAABNQAECn8eAAIUAAkKeCSPBACLAwAUAAkKeCSPBACLAwAAAA==.Ilk:BAABNQAECn8ZAAIdAAcKKQoCHgB8AQAdAAcKKQoCHgB8AQAAAA==.Illududu:BAAANQAECgEIAQABNQAECgYIBwAFAAAAAA==.',
Im='Imangry:BAAANQADCgEIAQAAAA==.',
Is='Isaidnoice:BAAANQADCgYICgAAAA==.Ishiftmyself:BAAANQAECgcIEQAAAA==.Ishton:BAABNQAECn8hAAINAAkKyhsHSAC5AgANAAkKyhsHSAC5AgAAAA==.Istompgnomes:BAAANQAECgYIEwAAAA==.',
It='Itsnowz:BAAANQADCgQIBAAAAA==.',
Ja='Jacobean:BAAANQADCgQIBAAAAA==.Jasøn:BAAANQADCgcIDgABNQAECggIHQACAMYMAA==.',
Je='Jecthyr:BAABNQAECn8gAAMOAAgKrRidFgBLAgAOAAgKrRidFgBLAgAiAAMKuw65LAC4AAAAAA==.Jefeson:BAAANQAECgQIBwAAAA==.Jemhdar:BAAANQAECgEIAQAAAA==.Jermdaga:BAAANQADCgQIBAAAAA==.',
Ji='Jinnasaiquoi:BAAANQAECgYIBwAAAA==.',
Js='Jsdruid:BAAANQAECgUIBQAAAA==.',
Ju='Juicyheals:BAAANQADCgQIBgAAAA==.',
Ka='Kaelosu:BAABNQAECn8xAAIXAAkK3BzwLQDLAgAXAAkK3BzwLQDLAgAAAA==.Kakum:BAAANQAECgUIBQAAAA==.Kaldrogo:BAAANQADCggIFAAAAA==.Kalnuggets:BAAANQAECgMIAwAAAA==.Kalrathen:BAABNQAECn8pAAMLAAkK1Ba3OgB7AgALAAkK1Ba3OgB7AgAQAAEKewFvkAAXAAAAAA==.Kanda:BAABNQAECn8rAAICAAkK4xjvOgC3AgACAAkK4xjvOgC3AgAAAA==.Karsh:BAABNQAECn8WAAIMAAgKJwU2GAAZAQAMAAgKJwU2GAAZAQAAAA==.Kazadax:BAABNQAECn8aAAIXAAgKGQ7ofwDiAQAXAAgKGQ7ofwDiAQAAAA==.',
Ke='Kealosu:BAAANQADCggIDgAAAA==.Keen:BAAANQAECgEIAQAAAA==.Keuaakepo:BAABNQAECn8gAAICAAkKbxofMgDUAgACAAkKbxofMgDUAgAAAA==.',
Ki='Kienne:BAABNQAECn8fAAICAAcKZhXPgwAAAgACAAcKZhXPgwAAAgAAAA==.Kiljaedra:BAAANQAECgEIAgABNQAECgkJJgAZAJ8XAA==.Kinomi:BAAANQADCgYJBgABNQAECgcIEQAFAAAAAA==.Kitenna:BAAANQAECgMIAwAAAA==.',
Kl='Kleenex:BAAANQADCgEIAQAAAA==.',
Ko='Korbanhavoc:BAABNQAECn8XAAINAAcK4hGgwwCPAQANAAcK4hGgwwCPAQAAAA==.Korogar:BAAANQAECgMIBQAAAA==.',
Kp='Kpes:BAAANQADCgUJBQAAAA==.',
Kr='Kreamyumyums:BAAANQAECgUICgAAAA==.Krisp:BAAANQADCgUICAAAAA==.Krizzl:BAAANQADCgUIBQABNQAFFAUIEgAGALYmAA==.Kronknar:BAAANQABCgQJBAABNQAECgkJKAAeALkcAA==.',
Ky='Kymira:BAABNQAECn8qAAIfAAkKxhtCBwDJAgAfAAkKxhtCBwDJAgAAAA==.',
La='Lace:BAABNQAECn9DAAMXAAkKmSRuCQCAAwAXAAkKRCJuCQCAAwAYAAIK4yTiOQDYAAAAAA==.Lanzen:BAAANQADCgEIAQAAAA==.Larrfena:BAABNQAECn8tAAICAAgK6xqaVQBuAgACAAgK6xqaVQBuAgAAAA==.Lavatory:BAAANQADCgEIAQAAAA==.Lazarou:BAAANQAECgUIBgAAAA==.',
Le='Legsday:BAAANQADCgUIBgAAAA==.Lementz:BAACNQAFFH8OAAIeAAQKVhFfEgBDAQAeAAQKVhFfEgBDAQA1AAQKfyAAAh4ACQp4HsIgAAYDAB4ACQp4HsIgAAYDAAAA.',
Li='Liadres:BAAANQADCgIIAgAAAA==.Liante:BAAANQADCgcIEgABNQAECgIIAwAFAAAAAA==.Libellule:BAAANQABCgQIBAAAAA==.Lilboat:BAAANQAECgEIAQAAAA==.Lillia:BAABNQAECn8mAAIXAAgK+RDsdAD+AQAXAAgK+RDsdAD+AQAAAA==.Lillybell:BAAANQADCgUIBQAAAA==.Littleboyz:BAAANQADCgcIBwAAAA==.',
Lo='Loop:BAAANQAECggICAAAAA==.Loopku:BAAANQAECggICAAAAA==.Lorinash:BAAANQADCgYICQAAAA==.Lothelo:BAAANQAECgEIAgABNQAECgcIEAAFAAAAAA==.',
Lu='Lumpia:BAABNQAECn8dAAMGAAkKwhqgLgB0AgAGAAkKwhqgLgB0AgAPAAIKuwUDvABNAAAAAA==.',
Lv='Lvel:BAAANQADCgYICgAAAA==.',
Ma='Maey:BAABNQAECn8rAAMBAAkKdRZ5jABmAgABAAkKehN5jABmAgAZAAEKASH4OgBRAAAAAA==.Magoobers:BAAANQADCgEIAQAAAA==.Maktah:BAABNQAECn8oAAMeAAkKuRyALgC/AgAeAAkKuRyALgC/AgAdAAEK/AgANAA+AAAAAA==.Malpractice:BAAANQAECgUIBQABNQAECgcIEQAFAAAAAA==.Maybesinged:BAABNQAECn8sAAIBAAkKghlQWADPAgABAAkKghlQWADPAgAAAA==.',
Me='Meanboy:BAAANQAECgMIAwAAAA==.Meishra:BAAANQADCgcICQAAAA==.Mentos:BAABNQAECn8vAAQiAAkKvh9qBQA6AwAiAAkKvh9qBQA6AwAOAAIK4xQ0QACZAAAjAAEKCRPZIgA5AAAAAA==.',
Mi='Midgetninja:BAAANQADCgQIBAABNQAECgkJFAAfABEiAA==.Miltank:BAABNQAECn8tAAINAAkKyx0PPQDbAgANAAkKyx0PPQDbAgAAAA==.Minaqt:BAAANQADCgEIAQAAAA==.Minatory:BAABNQAECn8gAAIUAAkKmBguGACZAgAUAAkKmBguGACZAgAAAA==.Mionn:BAABNQAECn8aAAMNAAgK6BuLaQBcAgANAAcKux6LaQBcAgAVAAEK7grHGwE3AAAAAA==.Misfires:BAAANQABCggIEwAAAA==.',
Ml='Mlleena:BAABNQAECn8ZAAIYAAcKgBBZGQCgAQAYAAcKgBBZGQCgAQAAAA==.',
Mo='Moddim:BAAANQADCgUIBQAAAA==.Modotz:BAAANQADCgEIAQAAAA==.Mogg:BAAANQAECgEIAQAAAA==.Moghoul:BAAANQAECgQIBQAAAA==.Montorgo:BAAANQADCgYIBgAAAA==.Moofi:BAAANQADCggIDgABNQAECgcIEgAFAAAAAA==.Mooncake:BAABNQAECn8fAAMiAAkKIQdCGgCiAQAiAAkKIQdCGgCiAQAjAAIKhALmIQBBAAAAAA==.Moosiah:BAAANQADCgcIBwAAAA==.Motoko:BAABNQAECn8cAAMfAAkKXhojCgBzAgAfAAkKXhojCgBzAgAkAAEKQAKVUwAgAAAAAA==.',
Mu='Musesong:BAAANQADCgMIAwAAAA==.',
['Mø']='Møøfi:BAAANQAECgcIEgAAAA==.',
Na='Naianasha:BAAANQAECgcIDwAAAA==.Nameless:BAABNQAECn8yAAIBAAkK3xGTlQBUAgABAAkK3xGTlQBUAgAAAA==.Narc:BAAANQAECgUIDAAAAA==.',
Ne='Necroraise:BAAANQADCgIIAgAAAA==.Neeraj:BAABNQAECn8aAAICAAgKBBEMbgAzAgACAAgKBBEMbgAzAgAAAA==.Nevergreen:BAAANQABCgIIAgAAAA==.',
Ni='Nightreaver:BAAANQAECgQIBAABNQAECgkJFAAfABEiAA==.Nippiest:BAAANQABCggICwAAAA==.',
No='Nokzash:BAAANQAECggIEgAAAA==.Noova:BAABNQAECn8oAAIBAAkKqh27SADxAgABAAkKqh27SADxAgAAAA==.',
Ny='Nyang:BAAANQAECgYIDQAAAA==.Nythendrac:BAAANQADCgQIBAABNQAECgkJJgAZAJ8XAA==.',
Ob='Obliverat:BAAANQAECggIEQAAAA==.',
Od='Odysseus:BAAANQADCgIIBAAAAA==.',
Ok='Okiedokie:BAAANQADCggIDAABNQAECgYIEAAFAAAAAA==.',
Oo='Oongaboonga:BAABNQAECn8mAAIEAAgKjxwKSgCoAgAEAAgKjxwKSgCoAgAAAA==.',
Or='Orcaneblast:BAACNQAFFH8GAAIBAAIKRxyzPwCvAAABAAIKRxyzPwCvAAA1AAQKfywAAgEACQq+H5pIAPECAAEACQq+H5pIAPECAAAA.Orcsoup:BAAANQAECgYIEgABNQAECgkJIwAIAOwcAA==.',
Pa='Paddord:BAAANQADCgcIBwAAAA==.Pandemnik:BAAANQAECgQIBAAAAA==.Paranoià:BAAANQADCgIIAgABNQAECgEIAQAFAAAAAA==.',
Pe='Penance:BAAANQAECgYICwAAAA==.Percible:BAAANQADCgYIBgAAAA==.',
Pi='Pivnert:BAABNQAECn8dAAQBAAcKTRpPvAAKAgABAAcKeRhPvAAKAgAZAAIKIBc1LQCPAAAaAAIKVxi5CACJAAAAAA==.',
Pl='Plums:BAAANQAECggIBwAAAA==.',
Po='Popdkook:BAAANQADCgYIEgAAAA==.',
Pr='Proko:BAAANQADCggICAAAAA==.',
Ps='Psychopump:BAAANQAECgYICgAAAA==.',
['Pü']='Pünish:BAACNQAFFH8IAAIGAAQKohhxDABDAQAGAAQKohhxDABDAQA1AAQKf0gABAYACQoJJewGAI4DAAYACQoJJewGAI4DACEAAwpxFR55ALgAAA8AAQpfBS3QACsAAAAA.',
Qq='Qqpewpew:BAAANQAECggIBAAAAA==.',
Qu='Quinn:BAAANQADCgIJAgABNQAECgkJFAAfABEiAA==.',
Ra='Rabit:BAAANQADCgUIBQAAAA==.Raelina:BAABNQAECn8iAAMBAAkKIh+6SwDqAgABAAkKUB26SwDqAgAZAAIKoCKMJgC7AAABNQAFFAgIJAABABYeAA==.Ragingiscool:BAAANQADCggIDwAAAA==.Rail:BAAANQAECgEIAQAAAA==.Rajank:BAAANQADCgQIBAAAAA==.Rallek:BAABNQAECn8dAAIVAAgKHhCEawDSAQAVAAgKHhCEawDSAQAAAA==.Ranuggul:BAAANQAECgEIAQAAAA==.Ratsrepus:BAAANQADCgcICwAAAA==.Raza:BAAANQAECgQIDAABNQAFFAQICAAGAKIYAA==.',
Re='Read:BAAANQAECgQICAAAAA==.Reddawn:BAAANQADCgcIBwAAAA==.Remeras:BAAANQAECgcIEAAAAA==.',
Ri='Riken:BAAANQAECgYIEwAAAA==.',
Ro='Roadi:BAAANQAECgUIBQABNQAECgkJMAAXAHQeAA==.Roxer:BAABNQAECn8bAAIVAAkKYRAFUAAoAgAVAAkKYRAFUAAoAgAAAA==.',
Ru='Rukaa:BAAANQAECgIIAgAAAA==.Rummyy:BAAANQAFFAEIAQAAAA==.',
Ry='Rycken:BAABNQAECn8jAAMIAAkKYA1jKQDQAQAIAAkKYA1jKQDQAQAJAAYK+RY6UACYAQAAAA==.',
Sa='Saeylva:BAAANQAECgMIBAAAAA==.Saosis:BAAANQAECgYIBgAAAA==.Savage:BAAANQADCgIIAgAAAA==.Sayurri:BAAANQADCgEJAQAAAA==.',
Sc='Scribble:BAAANQAECgMIBAAAAA==.Sculper:BAAANQAECgUIEAAAAA==.',
Se='Senica:BAAANQAECgcIDwAAAA==.Seriphina:BAAANQADCggICAAAAA==.',
Sg='Sgornyweaver:BAAANQADCgUJBQAAAA==.',
Sh='Shabbarankzz:BAABNQAECn8pAAIhAAgKzBOmNAAEAgAhAAgKzBOmNAAEAgAAAA==.Shadetotem:BAABNQAECn8bAAIdAAYK1hCpHQCCAQAdAAYK1hCpHQCCAQAAAA==.Shammyblammy:BAAANQABCgEIAQAAAA==.Sheshotu:BAAANQADCggIFwAAAA==.Shiftor:BAAANQADCggIEgAAAA==.Shinedown:BAAANQADCgMIAwAAAA==.Shmoopy:BAAANQAECgIIAgAAAA==.Shradehn:BAABNQAECn8ZAAITAAkK5RUrLAA9AgATAAkK5RUrLAA9AgAAAA==.Shutitdown:BAAANQAECgUIBQAAAA==.',
Si='Sisterswede:BAABNQAECn8dAAIQAAkK/h0bEwDPAgAQAAkK/h0bEwDPAgAAAA==.Sizzle:BAABNQAECn8aAAIBAAkKzBC+oAA/AgABAAkKzBC+oAA/AgAAAA==.',
Sm='Smokeahontas:BAAANQAECgQIDQAAAA==.Smokindots:BAAANQAECgUICQABNQAFFAMICAAHAAkVAA==.Smokingreen:BAAANQADCggICAABNQAFFAMICAAHAAkVAA==.Smokinmyrrh:BAAANQAECgUIBQABNQAFFAMICAAHAAkVAA==.Smokinmyth:BAAANQADCgcICAAAAA==.Smokinpsalm:BAAANQAECgcIEgABNQAFFAMICAAHAAkVAA==.Smokintotem:BAACNQAFFH8IAAIHAAMKCRVHFgDxAAAHAAMKCRVHFgDxAAA1AAQKfzMAAwcACQoFI00MAFwDAAcACQoFI00MAFwDAB4ABgqBGuFqANwBAAAA.',
Sn='Snawkin:BAAANQADCgEIAQAAAA==.',
Sp='Spaghet:BAEANQAECgQIBgABNQAFFAUICgAEADYSAA==.Sparklnmagic:BAAANQADCgcICAAAAA==.Spore:BAAANQADCgIIAgAAAA==.',
Sq='Squigboogalo:BAAANQADCgEIAQAAAA==.',
St='Steadyrock:BAAANQAECgcIEwAAAA==.Stemi:BAAANQAECgEIAQAAAA==.Steveirwin:BAAANQADCggJCAAAAA==.Stiffsheets:BAAANQAECgQIBAABNQAECgkJFAAfABEiAA==.Stiltz:BAAANQADCgEIAQAAAA==.Stormywind:BAABNQAECn8VAAIeAAgKaQfEiwCDAQAeAAgKaQfEiwCDAQAAAA==.Stormz:BAABNQAECn8nAAIJAAgKqBIqPwD9AQAJAAgKqBIqPwD9AQAAAA==.',
Su='Sunblade:BAAANQAECgYIEAABNQAECgkJMgABAN8RAA==.Sundowning:BAAANQAECgUIBQAAAA==.Sunreaver:BAAANQAECgcICQAAAA==.Supercappy:BAAANQAECgEIAQAAAA==.Suraegi:BAAANQAECgIIAgAAAA==.',
Sw='Swabby:BAAANQADCgEIAQAAAA==.Swiftdragon:BAABNQAECn8UAAMfAAkKESKyBAAlAwAfAAgK6iOyBAAlAwAlAAEK+RaeZABFAAAAAA==.',
Ta='Taapfer:BAAANQAECgMIAwABNQAECggIHgABAIgXAA==.Tackyh:BAABNQAECn8eAAICAAYKAB1hdQAiAgACAAYKAB1hdQAiAgAAAA==.Takamatsu:BAABNQAECn8oAAMLAAgKsiP4FQAgAwALAAgKsiP4FQAgAwASAAMKDA5IGgCWAAAAAA==.Taku:BAAANQAECgIIBAAAAA==.Tar:BAABNQAECn8dAAMCAAgKxgwfuQCNAQACAAYK7w4fuQCNAQARAAMKFAhDYwCZAAAAAA==.Taxii:BAABNQAECn8oAAMEAAkKfCL1JAAjAwAEAAkKXB/1JAAjAwAMAAYKuyXUBgCRAgAAAA==.',
Te='Tealnujabes:BAAANQAECgYIBwAAAA==.Teapots:BAAANQAFFAEIAQAAAA==.Tempi:BAAANQABCgMIAwABNQAECgYIBgAFAAAAAA==.Tenpiece:BAAANQADCgMIAwAAAA==.',
Th='Thayelith:BAAANQAECgUIBAAAAA==.Thedeus:BAAANQAECgcIEAAAAA==.Thellira:BAAANQADCgEIAQAAAA==.Thermaul:BAABNQAECn8rAAIdAAkKaRksCwC8AgAdAAkKaRksCwC8AgAAAA==.Threebeans:BAABNQAECn8jAAMIAAkK7BzWDAD9AgAIAAkK7BzWDAD9AgAJAAcKrBEyRgDSAQAAAA==.Thromir:BAACNQAFFH8HAAMNAAQKGR0qEQA0AQANAAMKbiAqEQA0AQAVAAMKyA+sFwDjAAA1AAQKfyAAAxUACQoEILcWACADABUACQoEILcWACADAA0ABgpdJlZNAKkCAAAA.Thyrn:BAABNQAECn8nAAIPAAgKXR4XIgCiAgAPAAgKXR4XIgCiAgAAAA==.',
Ti='Tirare:BAABNQAECn8iAAIGAAgKvRqzMwBZAgAGAAgKvRqzMwBZAgAAAA==.',
Tr='Tri:BAABNQAECn8ZAAINAAcKtCKyQADQAgANAAcKtCKyQADQAgAAAA==.Tristam:BAAANQAECgEIAQAAAA==.',
Tu='Tuneleitor:BAABNQAECn8ZAAImAAkKkg/WBQBOAgAmAAkKkg/WBQBOAgAAAA==.Turdferguson:BAAANQADCgcIBwABNQAFFAIIBgAfALIiAA==.Turgrok:BAAANQAECgcIEwAAAA==.',
Tw='Twothang:BAAANQAECgcIEwAAAA==.',
Ty='Tyllan:BAABNQAECn8jAAMBAAkKOxtAlgBTAgABAAgK5BhAlgBTAgAZAAMKmRoEIQDeAAAAAA==.',
['Tâ']='Tâku:BAAANQADCggIHgAAAA==.',
Up='Upgrayedd:BAAANQADCgUIBQAAAA==.',
Va='Vainhellsing:BAAANQAECgUIDQAAAA==.Vanzier:BAAANQAECgcIEAAAAA==.Vaxis:BAABNQAECn8cAAICAAgKOQ4UgQAHAgACAAgKOQ4UgQAHAgAAAA==.',
Vi='Vid:BAACNQAFFH8QAAIkAAYKpxbLAgDnAQAkAAYKpxbLAgDnAQA1AAQKfyQAAiQACQrFIP4IAPoCACQACQrFIP4IAPoCAAAA.',
Vo='Voidillusion:BAAANQAECgMIAwABNQAECgYIBwAFAAAAAA==.',
Wa='Watooie:BAAANQADCgYIBgAAAA==.',
We='Weave:BAAANQABCgIIAgABNQAECgkJQwAXAJkkAA==.Wernov:BAABNQAECn8kAAMeAAkKNhuxMQCwAgAeAAkKNhuxMQCwAgAHAAUK5BB4qgAYAQABNQAECgkJJgALAAsYAA==.',
Wh='Whitetail:BAAANQADCgEJAQAAAA==.',
Wi='Wichan:BAABNQAECn8iAAIKAAgKAxz7DQCAAgAKAAgKAxz7DQCAAgAAAA==.Wildstrike:BAAANQADCgYIBgABNQAECgkJHAAfAF4aAA==.Wiziviji:BAAANQAECgcIDAAAAA==.',
Wo='Woodrow:BAAANQADCgcIBwAAAA==.',
Ws='Ws:BAAANQAECgIIAgAAAA==.',
Xa='Xanorea:BAAANQADCgYIBgABNQAECgYIEQAFAAAAAA==.',
Xd='Xdknight:BAAANQABCgIIAwAAAA==.',
Xe='Xerø:BAAANQAECgUIBwAAAA==.',
Xr='Xray:BAABNQAECn8cAAIBAAgKORAVvQAIAgABAAgKORAVvQAIAgAAAA==.',
Xt='Xtra:BAAANQAECgMIAwAAAA==.Xtreme:BAAANQADCggIDQAAAA==.',
Ya='Yamii:BAAANQAECggIEgABNQAECgkJHQAGAMIaAA==.Yaphetkotto:BAAANQADCgcJCAAAAA==.Yawnk:BAAANQAECgUIDQAAAA==.',
Yu='Yunsky:BAAANQAECgIIAwAAAA==.',
Za='Zanber:BAAANQADCgIIAgAAAA==.Zandrakar:BAABNQAECn8sAAQHAAkK8BdzOQB2AgAHAAkK8BdzOQB2AgAdAAEKAADeNwAtAAAeAAEKPQXTRAEpAAAAAA==.Zanosuke:BAAANQAECggIEgAAAA==.Zaria:BAABNQAECn8bAAIXAAgKmBHNcAAKAgAXAAgKmBHNcAAKAgAAAA==.Zaryor:BAABNQAECn8WAAMlAAcKIRRMMgB/AQAlAAcKIRRMMgB/AQAfAAQKYhLWHwDkAAAAAA==.Zaun:BAAANQAECgUIBQAAAA==.',
Ze='Zentul:BAAANQAECgQIBAAAAA==.Zerica:BAAANQADCgQIBAAAAA==.Zerika:BAABNQAECn8pAAILAAkKgiI+DwBKAwALAAkKgiI+DwBKAwAAAA==.',
Zh='Zhaohu:BAAANQADCgYIBgAAAA==.',
Zi='Zigzwag:BAAANQAECgIIBQAAAA==.Zionna:BAAANQAECgYIEAABNQAECgcIEQAFAAAAAA==.Zitos:BAABNQAECn82AAMNAAkKDCUNBgDIAwANAAkKDCUNBgDIAwAVAAEKfgjuJgEsAAABNQAECgkJNgANAAwlAA==.',
Zo='Zomgqq:BAAANQAFFAEIAQAAAA==.',
Zw='Zwagster:BAAANQAECgIIAgAAAA==.',
Zy='Zydis:BAAANQAECgUICgAAAA==.Zyggy:BAAANQAECgQICAAAAA==.Zynfanatic:BAAANQAECgYICAABNQAECgkJIwAIAOwcAA==.',
['Än']='Ännihilation:BAAANQAECgIIAgAAAA==.',
['Èe']='Èepy:BAAANQAECgEIAQABNQAECgUIBQAFAAAAAA==.',
['És']='Éstéla:BAABNQAECn8kAAICAAkKNhbyVgBrAgACAAkKNhbyVgBrAgAAAA==.',
['Ío']='Ío:BAAANQAECgUICAAAAA==.',
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
