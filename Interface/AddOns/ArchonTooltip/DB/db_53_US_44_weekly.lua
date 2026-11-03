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

local lookup = {'Mage-Arcane','Hunter-BeastMastery','Rogue-Subtlety','Warrior-Arms','Shaman-Enhancement','Unknown-Unknown','Warlock-Affliction','DeathKnight-Unholy','Druid-Guardian','Druid-Restoration','Druid-Balance','Priest-Holy','Warrior-Fury','Paladin-Retribution','Evoker-Preservation','Monk-Brewmaster','DeathKnight-Blood','Priest-Shadow','Hunter-Marksmanship','Evoker-Devastation','Priest-Discipline','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Restoration','Paladin-Holy','Shaman-Elemental','Paladin-Protection','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Mage-Fire','DemonHunter-Vengeance','Druid-Feral','Warrior-Protection','DeathKnight-Frost','Evoker-Augmentation','Monk-Mistweaver','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abobadrin:BAAANQADCgcIDgAAAA==.Abrakadaver:BAABNQAECn8mAAIBAAoKpBXesAAhAgABAAoKpBXesAAhAgAAAA==.',
Ac='Acceb:BAAANQADCgQJBAAAAA==.',
Ad='Adventureux:BAACNQAFFH8HAAICAAIKTRuhGQCjAAACAAIKTRuhGQCjAAA1AAQKfzEAAgIACgppGno8ALQCAAIACgppGno8ALQCAAAA.',
Ae='Aedx:BAABNQAECn8oAAIDAAkKIxWrEgBZAgADAAkKIxWrEgBZAgAAAA==.Aerolorea:BAAANQADCgYICQAAAA==.',
Ai='Aiblul:BAAANQAECgQIBQAAAA==.',
Al='Alastar:BAABNQAECn8ZAAIEAAgK6h72XAB1AgAEAAgK6h72XAB1AgABNQAFFAIIBwAFACohAA==.Alexmage:BAAANQADCgYIBgABNQADCgcIBwAGAAAAAA==.Alios:BAAANQAECgQIBAAAAA==.Alphasalt:BAAANQADCgcIBwABNQAECgYIFgAHADAYAA==.Alucard:BAAANQAECgYIDwAAAA==.Alunadoom:BAABNQAECn8iAAICAAgK7AYPygBtAQACAAgK7AYPygBtAQAAAA==.Alvera:BAACNQAFFH8KAAIIAAQK6BdICwBZAQAIAAQK6BdICwBZAQA1AAQKfzsAAggACgrtJI0HAIgDAAgACgrtJI0HAIgDAAAA.',
Am='Ambellìna:BAAANQADCgIIAgABNQAECgEIAQAGAAAAAA==.',
An='Angechi:BAEANQADCgIJAgABNQAECgoKJQAJANMWAA==.Angrydk:BAAANQAECgYIDAAAAA==.Annoying:BAAANQAECgcICgAAAA==.Antisocial:BAABNQAECn8uAAIIAAoKziAuEgAmAwAIAAoKziAuEgAmAwABNQAECgoKLgAIAM4gAA==.',
Ar='Arm:BAABNQAECn9OAAQKAAoKIhviDAC5AgAKAAoKIhviDAC5AgALAAYKmAyMZgAzAQAJAAIKehMZUgBaAAAAAA==.Armee:BAABNQAECn8iAAIMAAoKIRqpVwAbAgAMAAoKIRqpVwAbAgAAAA==.Armz:BAAANQABCgEIAQAAAA==.',
As='Astrael:BAABNQAECn8ZAAIBAAkK7hektgAWAgABAAkK7hektgAWAgAAAA==.Aszea:BAAANQAECgUIDgAAAA==.',
At='Attewode:BAAANQAECgEIAQAAAA==.',
Ax='Axas:BAAANQADCgcICAAAAA==.Axra:BAABNQAECn8oAAINAAoK0A8kDQDmAQANAAoK0A8kDQDmAQAAAA==.',
Ay='Ayda:BAAANQAECgEIAQAAAA==.',
Az='Azairius:BAAANQADCggIGAAAAA==.Azzman:BAAANQADCgMIAwAAAA==.Azóg:BAABNQAECn8fAAIIAAoKsQ9pIwCTAQAIAAoKsQ9pIwCTAQAAAA==.',
Ba='Balsin:BAABNQAECn8uAAIOAAoKuiP4EwB2AwAOAAoKuiP4EwB2AwAAAA==.Bambii:BAAANQADCgUIBwAAAA==.Bangungot:BAAANQAECgUIBgABNQAFFAgIGAAPABEVAA==.Barlaf:BAABNQAECn9CAAICAAoKrBvkNgDGAgACAAoKrBvkNgDGAgABNQAECgMIAwAGAAAAAA==.Batou:BAAANQAECgUICAAAAA==.',
Be='Beeski:BAAANQADCggIHQAAAA==.Beeto:BAACNQAFFH8TAAIOAAUK1xlHGgDWAAAOAAUK1xlHGgDWAAA1AAQKfzIAAg4ACgqqGEBoAMMBAA4ACgqqGEBoAMMBAAAA.Bellflower:BAAANQAECgQIBAABNQAECgoKGwAQAIMhAA==.Belyndris:BAABNQAECn8oAAIMAAoK1RkMOgAcAgAMAAoK1RkMOgAcAgAAAA==.Benbear:BAEBNQAECn8lAAIJAAoK0xYNDgAcAgAJAAoK0xYNDgAcAgAAAA==.Benlian:BAEBNQAECn8oAAIRAAgKuBG1UgCqAQARAAgKuBG1UgCqAQABNQAECgoKJQAJANMWAA==.',
Bl='Blighty:BAAANQAECgcIDQAAAA==.Bloran:BAAANQADCgIIAgAAAA==.Blâze:BAACNQAFFH8aAAIBAAYKsh8MDABiAQABAAYKsh8MDABiAQA1AAQKfy8AAgEACgoII84SAOwCAAEACgoII84SAOwCAAAA.',
Bo='Bombardi:BAAANQAECgMIAwAAAA==.Bonknsmash:BAABNQAECn8fAAIEAAgKJhTYjQD6AQAEAAgKJhTYjQD6AQAAAA==.Boof:BAABNQAECn8nAAMSAAoKrRUQHQBaAgASAAkKjBUQHQBaAgAMAAEKvCAWzQBXAAAAAA==.Boregut:BAAANQAECggICAAAAA==.',
Br='Brewdock:BAAANQABCgIIAgAAAA==.Bronxor:BAABNQAECn8vAAMTAAoK2xaYIQBAAgATAAoKMhaYIQBAAgACAAEKhxfrIwFEAAAAAA==.',
Bu='Bubbleoshift:BAAANQAECgcICwABNQAECgoKFgALAFkPAA==.Bushgarden:BAAANQADCgYIBwABNQADCgYICgAGAAAAAA==.Buzsmash:BAAANQAECgYIBgAAAA==.Buzzbuzz:BAAANQAECgMIBQABNQAECgkJGgABAMwQAA==.',
By='Byte:BAAANQAECgEIAQAAAA==.',
['Bó']='Bóba:BAACNQAFFH8fAAIPAAgKYCKlAQC8AgAPAAgKYCKlAQC8AgA1AAQKfzIAAw8ACgruI+QFAEwDAA8ACgruI+QFAEwDABQABgoaI7cHAOYBAAAA.',
['Bö']='Böba:BAABNQAECn8eAAQMAAkKkCQ+DABhAwAMAAkKkCQ+DABhAwAVAAkK0yBpBgAnAgASAAEKAABOeQA1AAABNQAFFAgIHwAPAGAiAA==.',
Ca='Cadroyd:BAABNQAECn8vAAQKAAoKjR2/DgCXAgAKAAkKvRy/DgCXAgALAAMKQgVJnwBhAAAJAAEKAADSegAAAAAAAA==.Caelin:BAACNQAFFH8GAAMWAAMK1AO8CgCPAAAWAAMKqwG8CgCPAAAXAAEKZginFwA/AAA1AAQKf08AAxcACgrnEtc1AAACABcACQrnEtc1AAACABYACApqDp8hAFsBAAAA.Cailand:BAABNQAECn8tAAIEAAoKmxUITwDgAQAEAAoKmxUITwDgAQAAAA==.Caishana:BAABNQAECn87AAIYAAoKmiPrBAC3AwAYAAoKmiPrBAC3AwAAAA==.Cambium:BAAANQAECgYIEQAAAA==.Camerbunne:BAAANQADCgYIEQAAAA==.Caramel:BAAANQAECgMIBQAAAA==.Catdude:BAAANQAECgUIDQAAAA==.',
Ce='Cecil:BAAANQADCgYIBgAAAA==.Celebrate:BAAANQAECgEIAQAAAA==.',
Ch='Chaddingus:BAAANQAECggIEwAAAA==.Chopadk:BAABNQAECn8hAAIRAAkKsA8YUwCoAQARAAkKsA8YUwCoAQAAAA==.Chumlëy:BAAANQAECgEIAwAAAA==.',
Cl='Clash:BAAANQADCgYIDgAAAA==.Clique:BAABNQAECn8sAAIZAAgKJh67NwCFAgAZAAgKJh67NwCFAgAAAA==.',
Cn='Cnc:BAAANQAECgEIAQAAAA==.',
Co='Coheedkil:BAAANQAECgEIAQAAAA==.Coldbreeze:BAABNQAECn8eAAIBAAcK8wfqFgFmAQABAAcK8wfqFgFmAQAAAA==.Collateral:BAAANQAECgQIBAAAAA==.Colomel:BAABNQAECn8UAAIBAAgKOAqWAwGIAQABAAgKOAqWAwGIAQAAAA==.Comegetsum:BAAANQADCgYIEQAAAA==.Compaktdisc:BAAANQADCgYIBgABNQAECgoKFgALAFkPAA==.Conqbine:BAAANQAECgQIBAAAAA==.Corg:BAAANQAECggIDwAAAA==.Countchocula:BAABNQAECn8iAAIBAAgKfRT6YQDHAQABAAgKfRT6YQDHAQAAAA==.',
Cr='Crimmi:BAABNQAECn8dAAIIAAkKwQjWMQAxAQAIAAkKwQjWMQAxAQAAAA==.Critzilla:BAAANQAECgYIBQAAAA==.',
Cu='Cuddy:BAAANQADCgYICgAAAA==.',
Cy='Cybuster:BAAANQADCgUJBQABNQAECgoKRgABAG0eAA==.Cyndle:BAABNQAECn85AAIYAAoK4gyLdQCrAQAYAAoK4gyLdQCrAQAAAA==.',
Da='Daddythicc:BAABNQAECn8sAAIBAAoKowpy5QC+AQABAAoKowpy5QC+AQAAAA==.Dadknight:BAAANQAECgEIAgAAAA==.Darnwrath:BAAANQAECgYIBgAAAA==.Darrkness:BAAANQADCgYIBgAAAA==.',
De='Deadgirljd:BAAANQAECgQICQAAAA==.Deadillusion:BAAANQADCgUIBQABNQAECgoKGQAaAFgeAA==.Deathpockets:BAAANQAECgMIBAAAAA==.Deran:BAABNQAECn8uAAMOAAkK1RsdYgB0AgAOAAkKRhsdYgB0AgAbAAcK4Bd9LQBxAQAAAA==.',
Di='Diante:BAAANQAECgUIDgAAAA==.Dimple:BAAANQAECgIJAgAAAA==.Dirtmonkgirt:BAABNQAECn8dAAIcAAoKSBW4FgDLAQAcAAoKSBW4FgDLAQAAAA==.Dirtnasty:BAABNQAECn8WAAIJAAoKtyCABAAAAwAJAAoKtyCABAAAAwABNQAFFAMIBwAQAJEgAA==.',
Dk='Dknujabes:BAAANQAECggIDwAAAA==.',
Do='Doofus:BAAANQADCgEIAQAAAA==.Doompockets:BAABNQAECn8iAAMdAAkKxgx/iADRAQAdAAkKrgl/iADRAQAeAAMKJg0cRwCrAAAAAA==.',
Dr='Dracara:BAABNQAECn80AAQfAAoK5hZvBQC7AgAfAAoK5hZvBQC7AgAgAAUK4wyRBQAiAQABAAMKBAeAnAGMAAAAAA==.Dracia:BAAANQAECgYIEAAAAA==.Drakulya:BAAANQABCgQIBAAAAA==.Drakunda:BAABNQAECn8WAAMFAAoKPQVDHQAJAQAFAAoKPQVDHQAJAQAYAAQKVgMotgCCAAABNQAECgoKNAAfAOYWAA==.Dreadz:BAABNQAECn8bAAMWAAcKkBA4NQCaAQAWAAcKJhA4NQCaAQAhAAIKJAmWKgBfAAAAAA==.Drewish:BAABNQAECn8uAAIiAAoKFB9zBwDpAgAiAAoKFB9zBwDpAgAAAA==.Drg:BAAANQADCgQIBAABNQADCgUIBQAGAAAAAA==.Drizzle:BAACNQAFFH8HAAIWAAIK0h94CQClAAAWAAIK0h94CQClAAA1AAQKfzwAAhYACgoFJNwEAIYDABYACgoFJNwEAIYDAAAA.Drktotem:BAABNQAECn81AAMFAAoKjiMlAwBvAwAFAAoKjiMlAwBvAwAYAAYKtxaCkABfAQAAAA==.Druidia:BAAANQADCgIIAgAAAA==.',
Du='Dulezlok:BAAANQADCgUIBQAAAA==.Dumbdog:BAACNQAFFH8mAAIKAAgKdyGMAADJAgAKAAgKdyGMAADJAgA1AAQKf0sAAgoACgrjIvMDAIcDAAoACgrjIvMDAIcDAAAA.Dumbledwarf:BAAANQADCggICAAAAA==.Dusan:BAABNQAECn85AAIMAAkKFB6ZMwCZAgAMAAkKFB6ZMwCZAgAAAA==.',
['Dï']='Dïvinity:BAAANQADCgIIAgAAAA==.',
Ea='Ea:BAAANQADCgcICAAAAA==.',
Ec='Echeyaket:BAABNQAECn8nAAMYAAoKWR7KQABdAgAYAAoKWR7KQABdAgAaAAIKmRChDwFsAAAAAA==.',
Ed='Edonsian:BAABNQAECn9DAAIEAAoKvBjeQgAKAgAEAAoKvBjeQgAKAgAAAA==.',
Eg='Egmont:BAAANQADCgUIBwAAAA==.',
El='Elektabuzz:BAAANQADCggIEAABNQAECgoKKgAOAOMcAA==.Elelusion:BAABNQAECn8ZAAIaAAoKWB6/FACiAgAaAAoKWB6/FACiAgAAAA==.Eliyah:BAAANQAECgIIAgAAAA==.Elliekins:BAABNQAECn8rAAIMAAoKqwc+XwCIAQAMAAoKqwc+XwCIAQAAAA==.Elçhapo:BAAANQAECgIIAwAAAA==.',
Em='Emergence:BAAANQAECgEIAQAAAA==.',
En='Endlesshour:BAAANQADCgMIAwAAAA==.Endlessly:BAABNQAECn8gAAISAAkK0hDUFgC3AQASAAkK0hDUFgC3AQAAAA==.Enoka:BAABNQAECn85AAIBAAoKoRkENQBPAgABAAoKoRkENQBPAgAAAA==.',
Es='Estelá:BAAANQADCgYICgAAAA==.',
Et='Etikwa:BAABNQAECn8tAAMKAAkK8g3AIwCJAQAKAAkK8g3AIwCJAQALAAUKgAOkYAB4AAAAAA==.',
Eu='Euclid:BAAANQAECgQIBwAAAA==.',
Ev='Evaporate:BAAANQAECgYICAAAAA==.Evilguard:BAABNQAECn8dAAIRAAgKlA0EXwB2AQARAAgKlA0EXwB2AQAAAA==.',
Ex='Excessive:BAAANQAECgIIAgAAAA==.Exroastbeef:BAAANQADCggICAAAAA==.',
Fa='Falador:BAABNQAECn8XAAIEAAYKPgvv2AA8AQAEAAYKPgvv2AA8AQAAAA==.Fariebubbles:BAAANQAECgUIDgAAAA==.',
Fe='Felene:BAACNQAFFH8FAAIaAAIKOAkmGgCBAAAaAAIKOAkmGgCBAAA1AAQKfy4AAxoACgpNHlApANwCABoACgpNHlApANwCABgAAgrsDscCAWMAAAAA.Fenwell:BAAANQADCgcIBwAAAA==.',
Fi='Firitako:BAABNQAECn8VAAMYAAYKpA4SowAuAQAYAAYKpA4SowAuAQAaAAMKSQxnngCXAAAAAA==.',
Fr='Frailey:BAABNQAECn8ZAAMHAAgK6hd0CQDsAQAHAAgK6hd0CQDsAQAdAAMKUgzeJwFvAAAAAA==.Frankiejr:BAAANQAECgMICAABNQAECgkJLQAOAHQfAA==.Fraubles:BAAANQAECgMIBAAAAA==.Friedpickel:BAAANQADCgYIBwAAAA==.Friter:BAAANQAECgMIAwAAAA==.Frostnite:BAAANQAECgUIEAAAAA==.Frostpoptart:BAABNQAECn8qAAMFAAkKxxrpCQDVAgAFAAkKxxrpCQDVAgAYAAIKQhcBuAB9AAAAAA==.Frozenblade:BAABNQAECn8wAAIRAAoK4hO9QQD2AQARAAoK4hO9QQD2AQAAAA==.',
Fu='Furball:BAAANQAECgYIEQABNQAFFAcIFgAdALIRAA==.Furiousgeorg:BAAANQAECgUIDAAAAA==.',
Ga='Gagabooney:BAACNQAFFH8HAAIQAAMKkSBtBwDHAAAQAAMKkSBtBwDHAAA1AAQKfxgAAhAACAouIQgJAJYCABAACAouIQgJAJYCAAAA.Galay:BAAANQAECggIDwAAAA==.Garabashi:BAAANQADCgcJBwAAAA==.Garrick:BAABNQAECn8eAAQjAAkK2RldDQCpAQAjAAgKOxpdDQCpAQANAAgKChG5CgCiAQAEAAQKCwjoIwGRAAAAAA==.Gazze:BAABNQAECn85AAIJAAkKQgllKgD/AAAJAAkKQgllKgD/AAAAAA==.',
Ge='Gemli:BAAANQADCgUIBQAAAA==.Gennissa:BAAANQAECgMIBAAAAA==.Gertog:BAAANQADCgQIBAAAAA==.Gethsemane:BAABNQAECn8jAAMdAAkKGhfeRACEAgAdAAkKGhfeRACEAgAHAAQK6RSgEgAfAQAAAA==.',
Gh='Ghostfate:BAAANQAECgEIAQAAAA==.',
Gi='Gigadoot:BAAANQABCgQIAgAAAA==.Gigglez:BAAANQADCgcJCQAAAA==.Gillis:BAAANQADCggIDAAAAA==.',
Gl='Glassdance:BAAANQAECgQIBQAAAA==.',
Gn='Gnryderp:BAAANQADCgUIBQAAAA==.',
Go='Goam:BAAANQADCggIFwAAAA==.Googrektar:BAAANQAECgQIBAABNQAFFAUICwABAFkUAA==.Goonielama:BAABNQAECn8qAAIRAAoKHCF/DgA7AwARAAoKHCF/DgA7AwABNQAFFAMIBwAQAJEgAA==.Goonietai:BAAANQAECgUICQABNQAFFAUICwABAFkUAA==.',
Gr='Greenterror:BAAANQADCgIIAgAAAA==.Grid:BAAANQAECgMIBwABNQAFFAIIBgAdACMUAA==.Griitz:BAAANQAECgQICAAAAA==.Grimmsheeper:BAACNQAFFH8LAAMBAAYKCRM/KgA5AQABAAUKNxQ/KgA5AQAfAAEKUQ4vDQBYAAA1AAQKf0QAAwEACgqNJJoYAMwCAAEACgqNJJoYAMwCAB8AAQr8Ie0pAGQAAAAA.Gryff:BAAANQADCgUJBQAAAA==.',
Gu='Guess:BAAANQAECgQIBAAAAA==.Gurtdk:BAACNQAFFH8kAAQIAAgK7hZIBADtAQAIAAYKwxpIBADtAQARAAEKAACZKABWAAAkAAEKyQPOGwBSAAA1AAQKfzIAAggACgrwJTALAGEDAAgACgrwJTALAGEDAAAA.',
Gy='Gyat:BAAANQADCgMJAwAAAA==.',
Ha='Hairynujabes:BAABNQAECn8WAAMLAAgK2w09ZQA4AQALAAcKSg09ZQA4AQAJAAIKtBARYQAwAAAAAA==.Hamandcheeze:BAAANQAECgIIAgAAAA==.Hanyuu:BAABNQAECn8uAAISAAoKlg7AFADWAQASAAoKlg7AFADWAQAAAA==.',
He='Healviji:BAAANQAECgYIAwAAAA==.Heiter:BAABNQAECn8mAAIMAAkKCxg3QwBfAgAMAAkKCxg3QwBfAgABNQAECgoKLQAaAGgbAA==.Hellbound:BAABNQAECn88AAMdAAoKIhqZOwDzAQAdAAoKqBiZOwDzAQAeAAIK/BMFVQB/AAAAAA==.Hellinhunt:BAACNQAFFH8KAAMCAAgKLAyuFwD9AAATAAUKeQiWEgAWAQACAAMKkROuFwD9AAA1AAQKfxkAAwIACgoXIINQAO0BAAIABwpjIYNQAO0BABMABwoMGXgfADgBAAAA.',
Ho='Holyekko:BAAANQADCgEIAQAAAA==.Holypants:BAAANQADCgYIBgAAAA==.Honk:BAAANQAECgUIBQABNQAECgkJGgABAMwQAA==.Hornivore:BAAANQADCgcIFQABNQAECgoKPAACAJUZAA==.',
Hy='Hyrja:BAAANQADCgUIBgABNQAECgoKNAAfAOYWAA==.',
['Hâ']='Hâvyr:BAAANQAECgYIBgAAAA==.',
Ic='Icefrosting:BAABNQAECn8fAAIBAAoK1Bk6NgBLAgABAAoK1Bk6NgBLAgABNQAECgoKJAASAIUdAA==.',
Id='Idistroya:BAAANQAECgUICAABNQAECgoKKwACAEUcAA==.',
Ig='Iggnogg:BAAANQAECgQICQAAAA==.',
Ik='Ikura:BAACNQAFFH8SAAIMAAUKzBL5DwBnAQAMAAUKzBL5DwBnAQA1AAQKfy4ABBUACgpUFp4GAD8BAAwACgpAEdtmAOoBABUACApREJ4GAD8BABIAAgrHCOpXADEAAAAA.',
Il='Ilithiya:BAABNQAECn8uAAIWAAoKSySjBACKAwAWAAoKSySjBACKAwAAAA==.Ilk:BAABNQAECn8eAAIFAAgKywlPHgB8AQAFAAgKywlPHgB8AQAAAA==.Illududu:BAAANQAECgUIBwABNQAECgoKGQAaAFgeAA==.',
Im='Imangry:BAAANQADCgEIAQAAAA==.',
Is='Isaidnoice:BAAANQADCgYICgAAAA==.Ishiftmyself:BAABNQAECn8WAAILAAoKWQ/7RgDRAQALAAoKWQ/7RgDRAQAAAA==.Ishton:BAACNQAFFH8FAAIOAAIK2gfuIAB3AAAOAAIK2gfuIAB3AAA1AAQKfy4AAg4ACgpHG0RJALkCAA4ACgpHG0RJALkCAAAA.Istompgnomes:BAABNQAECn8VAAIaAAcKYBcBdgC/AQAaAAcKYBcBdgC/AQAAAA==.',
It='Itsnowz:BAAANQADCgQIBAAAAA==.',
Ja='Jacobean:BAAANQADCgQIBAAAAA==.Jasøn:BAAANQADCgcIDgABNQAECgkJIAACAIcMAA==.',
Je='Jecthyr:BAABNQAECn81AAQPAAoKBxlXDwDVAQAPAAoKBxlXDwDVAQAUAAgK6xQPCgCYAQAlAAEKjASuGwAkAAAAAA==.Jefeson:BAAANQAECgYICQAAAA==.Jemhdar:BAAANQAECgEIAQAAAA==.Jermdaga:BAAANQADCgQIBAAAAA==.',
Ji='Jinnasaiquoi:BAABNQAECn8dAAMOAAkKHhhrRgAjAgAOAAkKOxdrRgAjAgAbAAQKTRSUQQDwAAAAAA==.Jinnasasquoi:BAAANQAECggICQAAAA==.',
Js='Jsdruid:BAAANQAECgYIBgAAAA==.',
Ka='Kaelitha:BAAANQAECgEIAQAAAA==.Kaelosu:BAABNQAECn8xAAIdAAkK3BwALwDKAgAdAAkK3BwALwDKAgAAAA==.Kakum:BAABNQAECn8aAAMZAAoKmBwxCwBRAwAZAAoKmBwxCwBRAwAOAAEKAADVqAEAAAAAAA==.Kaldrogo:BAAANQAECgUIBgAAAA==.Kalnuggets:BAAANQAECgcIBgAAAA==.Kalrathen:BAABNQAECn83AAMMAAoKJxqmOwB7AgAMAAoKJxqmOwB7AgASAAEKewFQkgAXAAAAAA==.Kanda:BAABNQAECn83AAICAAoKaBrNOwC3AgACAAoKaBrNOwC3AgAAAA==.Karsh:BAABNQAECn8bAAMNAAoK7ARoGAAZAQANAAgKJwVoGAAZAQAEAAQKWwQq5QB3AAAAAA==.Kazadax:BAABNQAECn8jAAIdAAoKDw+1gQDiAQAdAAoKDw+1gQDiAQAAAA==.',
Ke='Kealosu:BAAANQADCggIDgAAAA==.Keen:BAAANQAECgEIAQAAAA==.Keuaakepo:BAABNQAECn8rAAICAAoKRRwzMwDSAgACAAoKRRwzMwDSAgAAAA==.',
Ki='Kienne:BAABNQAECn8uAAICAAoKxBekSQAAAgACAAoKxBekSQAAAgAAAA==.Kiljaedra:BAAANQAECgEIAgABNQAECgoKNAAfAOYWAA==.Kinomi:BAAANQADCgYIBgABNQAECgoKFgALAFkPAA==.Kitenna:BAAANQAECggICAAAAA==.',
Kl='Kleenex:BAAANQADCgEIAQAAAA==.',
Ko='Korbanhavoc:BAABNQAECn8XAAIOAAcK4hHMxgCOAQAOAAcK4hHMxgCOAQAAAA==.Korogar:BAAANQAECgQICQAAAA==.',
Kp='Kpes:BAAANQADCgUJBQAAAA==.',
Kr='Kreamyumyums:BAAANQAECggIDgAAAA==.Krisp:BAAANQADCgUICAAAAA==.Krizzl:BAAANQADCgUIBQABNQAFFAYIGgAIALEmAA==.Kronknar:BAAANQABCgQJBAABNQAECgoKLwAaABEdAA==.Krìzzl:BAAANQAECggIEQABNQAFFAYIGgAIALEmAA==.',
Ky='Kymira:BAABNQAECn82AAIQAAoKOBpVBwDIAgAQAAoKOBpVBwDIAgAAAA==.',
La='Lace:BAACNQAFFH8GAAMdAAIKIxS+JAB1AAAdAAIKfw2+JAB1AAAeAAEKFg6xEQBEAAA1AAQKf2kABB0ACgrYJLAJAH8DAB0ACgrKIrAJAH8DAAcABAqbH7cJAGYBAB4AAgrzJA8PAMMAAAAA.Lanzen:BAAANQADCgEIAQAAAA==.Larrfena:BAABNQAECn88AAICAAoKlRnJQgAVAgACAAoKlRnJQgAVAgAAAA==.Lavatory:BAAANQADCgMIBgAAAA==.Lazarou:BAAANQAECgUIBgAAAA==.',
Le='Legsday:BAAANQAECgIIBAAAAA==.Lementz:BAACNQAFFH8OAAIaAAQKVhHPEgBDAQAaAAQKVhHPEgBDAQA1AAQKfyAAAhoACQp4HjEhAAUDABoACQp4HjEhAAUDAAAA.',
Li='Liadres:BAAANQADCgIIAgAAAA==.Liante:BAAANQADCgcIEgABNQAECgUIDgAGAAAAAA==.Libellule:BAAANQABCgQIBAAAAA==.Lilboat:BAAANQAECgEIAQAAAA==.Lillia:BAABNQAECn8+AAIdAAoKlxJtPADwAQAdAAoKlxJtPADwAQAAAA==.Lillybell:BAAANQADCgUIBQAAAA==.Littleboyz:BAAANQADCgcIBwAAAA==.',
Lo='Loop:BAACNQAFFH8IAAIEAAgKagF3IgCDAAAEAAgKagF3IgCDAAA1AAQKfxgAAgQACgoWHqkhAJ4CAAQACgoWHqkhAJ4CAAAA.Loopku:BAAANQAECggIDAAAAA==.Lorinash:BAAANQADCgYICQAAAA==.Lothelo:BAAANQAECgEIAgABNQAECgoKHAAOAH0bAA==.',
Lu='Lumpia:BAACNQAFFH8HAAIIAAIKGBkYCQCkAAAIAAIKGBkYCQCkAAA1AAQKfy8AAwgACgpvGyEvAHQCAAgACgpvGyEvAHQCABEABgpYB+RcAKoAAAAA.',
Lv='Lvel:BAAANQADCgYICgAAAA==.',
['Lë']='Lëeloo:BAAANQAECgcICAABNQAECggICwAGAAAAAA==.',
Ma='Maboomhammer:BAAANQAECgEIAQAAAA==.Machinism:BAAANQADCgIIAgABNQADCgcJCAAGAAAAAA==.Maey:BAABNQAECn82AAMBAAoKuhaAjQBkAgABAAoKHxSAjQBkAgAfAAEKASHLOwBQAAAAAA==.Magoobers:BAAANQADCgEIAQAAAA==.Maktah:BAABNQAECn8vAAMaAAoKER0ELwDAAgAaAAoKER0ELwDAAgAFAAEK/AiiNAA+AAAAAA==.Malpractice:BAAANQAECggIDQABNQAECgoKFgALAFkPAA==.Maybesinged:BAABNQAECn88AAIBAAoKlBsaNQBPAgABAAoKlBsaNQBPAgAAAA==.',
Me='Meanboy:BAAANQAECgMIAwAAAA==.Meishra:BAAANQADCgcICQAAAA==.Mentos:BAABNQAECn86AAQUAAoK8h+HBQA5AwAUAAoK8h+HBQA5AwAPAAIK4xQSQQCYAAAlAAEKCRNJIwA5AAAAAA==.',
Mi='Midgetninja:BAAANQAECgEIAgABNQAECgoKGwAQAIMhAA==.Miltank:BAACNQAFFH8HAAIOAAIKCRjRGgCVAAAOAAIKCRjRGgCVAAA1AAQKf0AAAg4ACgo2IhgZAOQCAA4ACgo2IhgZAOQCAAAA.Minaqt:BAAANQADCgEIAQAAAA==.Minatory:BAABNQAECn8kAAIWAAoKqRlvGACZAgAWAAoKqRlvGACZAgAAAA==.Mionn:BAABNQAECn8qAAMOAAoK4xyqawBaAgAOAAkKCx+qawBaAgAZAAEK7gokHwE3AAAAAA==.Misfires:BAAANQAECgEIAQAAAA==.',
Ml='Mlleena:BAABNQAECn8fAAIeAAcKLRF8CgDuAAAeAAcKLRF8CgDuAAAAAA==.',
Mo='Moddim:BAAANQADCgUIBQAAAA==.Modotz:BAAANQAECgEIAQAAAA==.Mogg:BAAANQAECgEIAQAAAA==.Moghoul:BAAANQAECgQIBQAAAA==.Monandwah:BAAANQADCgYIBwAAAA==.Montorgo:BAAANQADCgYIBgAAAA==.Moofi:BAAANQADCggIEQABNQAECggIHgAFADgLAA==.Mooncake:BAABNQAECn8fAAMUAAkKIQdqGgCiAQAUAAkKIQdqGgCiAQAlAAIKhAJWIgBBAAAAAA==.Moonless:BAAANQAECgEIAQABNQAECgoKRgABAL8ZAA==.Moosiah:BAAANQADCgcIBwAAAA==.Mossfire:BAAANQAECgIIBQABNQAECgkJHgAjANkZAA==.Motoko:BAABNQAECn8gAAMQAAoKvRk/CgByAgAQAAoKvRk/CgByAgAmAAIK3AT4NwAuAAAAAA==.',
Mu='Musesong:BAAANQADCgMIAwAAAA==.',
['Mø']='Møø:BAAANQAECgYIDAABNQAECgkJIAACAIcMAA==.Møøfi:BAABNQAECn8eAAIFAAgKOAstGABNAQAFAAgKOAstGABNAQAAAA==.',
Na='Naianasha:BAABNQAECn8dAAMMAAgK1xtJLwCrAgAMAAgK1xtJLwCrAgAVAAIKqRRsJABIAAAAAA==.Nameless:BAABNQAECn9GAAIBAAoKvxnWKwByAgABAAoKvxnWKwByAgAAAA==.Narc:BAABNQAECn8XAAILAAYKUgWeWACTAAALAAYKUgWeWACTAAAAAA==.',
Ne='Necroraise:BAAANQADCgIIAgAAAA==.Neeraj:BAABNQAECn8rAAICAAoKqBU/PwAgAgACAAoKqBU/PwAgAgAAAA==.Nevergreen:BAAANQABCgIIAgAAAA==.',
Ni='Nightreaver:BAAANQAECgUIBwABNQAECgoKGwAQAIMhAA==.Nikwillig:BAAANQAECgYICgAAAA==.Nippiest:BAAANQABCggICwAAAA==.',
No='Nokzash:BAABNQAECn8kAAIZAAoKsx5dHQCgAgAZAAoKsx5dHQCgAgAAAA==.Noova:BAABNQAECn83AAIBAAoKQh/6SQDuAgABAAoKQh/6SQDuAgAAAA==.',
Ny='Nyang:BAAANQAECgYIDQAAAA==.Nythendrac:BAAANQADCgQIBAABNQAECgoKNAAfAOYWAA==.',
Ob='Obliverat:BAAANQAECggIEwAAAA==.',
Od='Odysseus:BAAANQADCgIIBAAAAA==.',
Oo='Oongaboonga:BAABNQAECn8xAAIEAAgKkh9PSwCnAgAEAAgKkh9PSwCnAgAAAA==.',
Or='Orcaneblast:BAACNQAFFH8LAAIBAAUKWRTWIgDOAAABAAUKWRTWIgDOAAA1AAQKfzsAAwEACgpPILlJAO8CAAEACgpPILlJAO8CACAABwrRFwwCAL4BAAAA.Orcsoup:BAABNQAECn8WAAIaAAcKpxtUVgAhAgAaAAcKpxtUVgAhAgABNQAECgoKMwAKACYcAA==.',
Pa='Paddord:BAAANQADCggICgAAAA==.Paranoià:BAAANQADCgIIAgABNQAECgEIAQAGAAAAAA==.',
Pe='Peewpewpew:BAAANQADCgYIBgAAAA==.Penance:BAAANQAECgcICwAAAA==.Percible:BAAANQAECgIIBAAAAA==.',
Ph='Phoeniex:BAAANQAECgEIAgABNQAECgoKGwAQAIMhAA==.',
Pi='Pivnert:BAABNQAECn8sAAQBAAkKHxp+VADsAQABAAkKcRh+VADsAQAfAAIKbBi8LQCPAAAgAAIKVxjZCACJAAAAAA==.',
Pl='Plums:BAAANQAECggICQAAAA==.',
Po='Popdkook:BAAANQADCgYIEgAAAA==.',
Pr='Proko:BAAANQADCggICAAAAA==.',
Ps='Psychopump:BAAANQAECgYIDwAAAA==.',
['Pü']='Pünish:BAACNQAFFH8MAAIIAAUKRhyhDABDAQAIAAUKRhyhDABDAQA1AAQKf2EABAgACgoJJP0GAI4DAAgACgoJJP0GAI4DACQAAwpxFcR7ALgAABEAAQpfBRvSACsAAAAA.',
Qq='Qqpewpew:BAAANQAECggIBAAAAA==.',
Qu='Quinn:BAAANQADCgIJAgABNQAECgoKGwAQAIMhAA==.',
Ra='Rabit:BAAANQADCgUIBQAAAA==.Raelina:BAABNQAECn8lAAMBAAkKhSHdTADnAgABAAkKsx/dTADnAgAfAAIKoCISJwC6AAABNQAFFAkJNAABAOsgAA==.Ragingiscool:BAAANQADCggIDwAAAA==.Rail:BAAANQAECgEIAQAAAA==.Rajank:BAAANQADCgQIBAAAAA==.Rallek:BAABNQAECn8gAAIZAAoKjRB4bADSAQAZAAoKjRB4bADSAQAAAA==.Ranuggul:BAAANQAECgIIAQAAAA==.Rarn:BAAANQADCgMIAwABNQAECgoKNgARAO0cAA==.Ratsrepus:BAAANQADCgcICwAAAA==.Raza:BAAANQAECgQIDAABNQAFFAUIDAAIAEYcAA==.',
Re='Read:BAABNQAECn8aAAILAAcKkRB3NQAsAQALAAcKkRB3NQAsAQAAAA==.Reddawn:BAAANQADCgcIBwAAAA==.Redvi:BAAANQAECgEIAgAAAA==.Remeras:BAABNQAECn8WAAIOAAoKKhGrlQD4AQAOAAoKKhGrlQD4AQAAAA==.',
Ri='Riken:BAABNQAECn8UAAImAAcKvQ3qJABUAQAmAAcKvQ3qJABUAQAAAA==.Ripblast:BAAANQAECgUICAABNQAECgoKGwAQAIMhAA==.Ritual:BAABNQAECn83AAIYAAoKzRtNFADpAgAYAAoKzRtNFADpAgAAAA==.',
Ro='Roadi:BAAANQAECggICwAAAA==.Roxer:BAACNQAFFH8FAAIZAAEKCwnFJAA6AAAZAAEKCwnFJAA6AAA1AAQKfyEAAhkACgoaERhRACcCABkACgoaERhRACcCAAAA.',
Ru='Rukaa:BAAANQAECgIIAwAAAA==.Rummyy:BAACNQAFFH8GAAIWAAIK7CBCCADHAAAWAAIK7CBCCADHAAA1AAQKfyEAAxYACgoJHSkWALICABYACgoJHSkWALICABcAAQqTDBWPADwAAAAA.',
Ry='Rycken:BAABNQAECn89AAMKAAoKaA7ZKQDQAQAKAAoKaA7ZKQDQAQALAAgKWxi5JACgAQAAAA==.',
Sa='Saeylva:BAAANQAECgQIBwAAAA==.Saosis:BAAANQAECgYIBgAAAA==.Savage:BAAANQADCgIIAgAAAA==.Sayurri:BAAANQADCgEJAQAAAA==.',
Sc='Scribble:BAAANQAECgQICAAAAA==.Sculper:BAABNQAECn8XAAInAAcK6hFBDQB2AQAnAAcK6hFBDQB2AQAAAA==.',
Se='Senica:BAABNQAECn8sAAIMAAoK3yKBBADUAwAMAAoK3yKBBADUAwAAAA==.Seriphina:BAAANQADCggICAAAAA==.',
Sg='Sgornyweaver:BAAANQADCgUJBQAAAA==.',
Sh='Shabbarankzz:BAABNQAECn8+AAIkAAoKvxWrNQADAgAkAAoKvxWrNQADAgAAAA==.Shadetotem:BAABNQAECn8jAAIFAAgKBhABFwBeAQAFAAgKBhABFwBeAQAAAA==.Shammyblammy:BAAANQABCgEIAQAAAA==.Sheshotu:BAAANQADCggIFwAAAA==.Shiftor:BAAANQADCggIEgAAAA==.Shinedown:BAAANQADCgMIAwAAAA==.Shmoopy:BAAANQAECgMIBAAAAA==.Shradehn:BAABNQAECn8ZAAIXAAkK5RXMLAA9AgAXAAkK5RXMLAA9AgAAAA==.Shutitdown:BAAANQAECgUIBgAAAA==.',
Si='Sisterswede:BAABNQAECn8dAAISAAkK/h1LEwDPAgASAAkK/h1LEwDPAgAAAA==.Sixfingers:BAAANQADCgQIBAAAAA==.Sizzle:BAABNQAECn8aAAIBAAkKzBBAowA7AgABAAkKzBBAowA7AgAAAA==.',
Sm='Smokeahontas:BAABNQAECn8jAAIaAAoKMRDNPgCeAQAaAAoKMRDNPgCeAQAAAA==.Smokindots:BAAANQAECgcIEgABNQAFFAUIDwAYAKoUAA==.Smokingreen:BAAANQADCggICAABNQAFFAUIDwAYAKoUAA==.Smokinice:BAAANQADCggICwABNQAFFAUIDwAYAKoUAA==.Smokinloud:BAAANQADCgIIAgAAAA==.Smokinmyrrh:BAAANQAECgUIBQABNQAFFAUIDwAYAKoUAA==.Smokinmyth:BAAANQADCgcICAAAAA==.Smokinpsalm:BAABNQAECn8XAAIMAAgKzQ+NgQCTAQAMAAgKzQ+NgQCTAQABNQAFFAUIDwAYAKoUAA==.Smokintotem:BAACNQAFFH8PAAIYAAUKqhRYEAARAQAYAAUKqhRYEAARAQA1AAQKf0MAAxgACgo0I4MMAFwDABgACgo0I4MMAFwDABoABgqBGllsANsBAAAA.',
Sn='Snawkin:BAAANQADCgEIAQAAAA==.',
Sp='Spaghet:BAEBNQAECn8fAAIaAAkKnh59EgC3AgAaAAkKnh59EgC3AgABNQAFFAcIDQAEAMAPAA==.Sparklnmagic:BAAANQAECgIIBgAAAA==.Spore:BAAANQADCgIIAgAAAA==.',
Sq='Squigboogalo:BAAANQADCgEIAQAAAA==.',
St='Steadyrock:BAABNQAECn8ZAAMLAAoK7xRCNwAzAgALAAoK7xRCNwAzAgAKAAEK8QR4eAAuAAAAAA==.Stemi:BAAANQAECgEIAQAAAA==.Steveirwin:BAAANQADCggJCAAAAA==.Stiffsheets:BAAANQAECgUIBQABNQAECgoKGwAQAIMhAA==.Stiltz:BAAANQADCgEIAQAAAA==.Stormywind:BAABNQAECn8bAAIaAAgKQQhojQCCAQAaAAgKQQhojQCCAQAAAA==.Stormz:BAABNQAECn8/AAILAAoKlxTvHADoAQALAAoKlxTvHADoAQAAAA==.',
Su='Sunblade:BAABNQAECn8YAAIRAAcKGhVyWwCFAQARAAcKGhVyWwCFAQABNQAECgoKRgABAL8ZAA==.Sundayskoolz:BAAANQADCgUIBQAAAA==.Sundowning:BAAANQAECgcIDAAAAA==.Sunreaver:BAABNQAECn8XAAIZAAoKjw7QSAC+AQAZAAoKjw7QSAC+AQAAAA==.Supercappy:BAAANQAECgMIBQAAAA==.Suraegi:BAAANQAECgIIAgAAAA==.',
Sw='Swabby:BAAANQADCgEIAQAAAA==.Swiftdragon:BAABNQAECn8bAAMQAAoKgyHGBAAlAwAQAAkK6SPGBAAlAwAcAAIK2RNVQQB4AAAAAA==.',
Ta='Taapfer:BAAANQAECgMIAwABNQAECgoKJgABAKQVAA==.Tackyh:BAABNQAECn8wAAICAAcK5x58dwAgAgACAAcK5x58dwAgAgAAAA==.Takamatsu:BAABNQAECn88AAMMAAoKUiRnFgAgAwAMAAoKUiRnFgAgAwAVAAMKDA6LGgCWAAAAAA==.Taku:BAAANQAECgQICAAAAA==.Tanktoucher:BAAANQAECggIAQAAAA==.Tar:BAABNQAECn8gAAMCAAkKhwzOuwCMAQACAAgK2gzOuwCMAQATAAMKFAiGZACZAAAAAA==.Taxii:BAABNQAECn80AAMEAAoK6SXNJQAiAwAEAAoKgCPNJQAiAwANAAgKJSXpBgCRAgAAAA==.Taxilan:BAAANQAECgQIBAABNQAECgoKNAAEAOklAA==.',
Te='Tealnujabes:BAAANQAECgYIBwAAAA==.Teapots:BAACNQAFFH8HAAIFAAIKKiEYBAC3AAAFAAIKKiEYBAC3AAA1AAQKfxUAAgUABQrnI0sVAHkBAAUABQrnI0sVAHkBAAAA.Tempi:BAAANQABCgMIAwABNQAECgYIBgAGAAAAAA==.Tenpiece:BAAANQADCgMIAwAAAA==.',
Th='Thayelith:BAAANQAECgUIBAAAAA==.Thedeus:BAABNQAECn8cAAIOAAoKfRv8UwCZAgAOAAoKfRv8UwCZAgAAAA==.Thellira:BAAANQADCgEIAQAAAA==.Thermaul:BAABNQAECn8/AAIFAAoKQxzaCABmAgAFAAoKQxzaCABmAgAAAA==.Threebeans:BAABNQAECn8zAAMKAAoKJhwGDQD+AgAKAAoKJhwGDQD+AgALAAcK9BHwRgDSAQAAAA==.Thromir:BAACNQAFFH8IAAMOAAUKUB68EQA0AQAOAAQK8CC8EQA0AQAZAAMKyA8rGADjAAA1AAQKfzYAAw4ACgrAJdAHAEwDAA4ACgrAJdAHAEwDABkACQoEIDQXAB8DAAAA.Thyrn:BAABNQAECn82AAIRAAoK7Rx/FgAtAgARAAoK7Rx/FgAtAgAAAA==.',
Ti='Tirare:BAABNQAECn8lAAIIAAkKbxlJNABZAgAIAAkKbxlJNABZAgAAAA==.',
Tr='Tri:BAABNQAECn8tAAIOAAkKdB/4QQDPAgAOAAkKdB/4QQDPAgAAAA==.Tristam:BAAANQAECgEIAQAAAA==.',
Tu='Tuneleitor:BAABNQAECn8sAAIoAAoKzRKSBAD6AQAoAAoKzRKSBAD6AQAAAA==.Turdferguson:BAAANQAECgQIAwABNQAFFAMIBwAQAJEgAA==.Turgrok:BAABNQAECn8gAAMCAAoKNA+YUADsAQACAAkKNA+YUADsAQATAAgKUAuoNACoAQAAAA==.',
Tw='Twill:BAAANQAECgEIAQAAAA==.Twothang:BAABNQAECn8UAAMRAAgKOAiyagBJAQARAAgKoweyagBJAQAkAAIKMwWlnwBRAAAAAA==.',
Ty='Tyllan:BAABNQAECn9GAAMBAAoKbR5UlwBSAgABAAkKeRxUlwBSAgAfAAMKUB0WFgD6AAAAAA==.',
['Tâ']='Tâku:BAAANQAECgIIAgAAAA==.',
Up='Upgrayedd:BAAANQAECgUIEgAAAA==.',
Ur='Urugargo:BAAANQAECgEIAQAAAA==.',
Va='Vainhellsing:BAABNQAECn8hAAIXAAcKHwelRwDTAAAXAAcKHwelRwDTAAAAAA==.Vanzier:BAABNQAECn8XAAICAAoKpRWHagA+AgACAAoKpRWHagA+AgAAAA==.Vaxis:BAABNQAECn8kAAICAAoKOQ/uggAGAgACAAoKOQ/uggAGAgAAAA==.',
Vi='Vid:BAACNQAFFH8RAAImAAcKQxThAgDmAQAmAAcKQxThAgDmAQA1AAQKfzMAAiYACgpQICMJAPkCACYACgpQICMJAPkCAAAA.',
Vo='Voidillusion:BAAANQAECgMIBQABNQAECgoKGQAaAFgeAA==.Voldoom:BAAANQAECgIIBAAAAA==.',
Wa='Watooie:BAAANQADCgYIBgAAAA==.',
We='Weave:BAAANQABCgIIAgABNQAFFAIIBgAdACMUAA==.Wernov:BAABNQAECn8tAAMaAAoKaBuCMgCwAgAaAAoKaBuCMgCwAgAYAAUK5BA2rAAYAQAAAA==.',
Wh='Whitetail:BAAANQAECgMIBQAAAA==.',
Wi='Wichan:BAABNQAECn80AAIJAAoKexzZDAA2AgAJAAoKexzZDAA2AgAAAA==.Wildsniper:BAAANQAECgEIAQAAAA==.Wildstrike:BAAANQADCgYIBgABNQAECgoKIAAQAL0ZAA==.Wiziviji:BAABNQAECn8eAAIBAAoKYwdsnwA5AQABAAoKYwdsnwA5AQAAAA==.',
Wo='Woodrow:BAAANQADCgcIBwAAAA==.',
Ws='Ws:BAAANQAECgIIAgAAAA==.',
Xa='Xanorea:BAAANQADCgYIBgABNQAECgcIFwAUAO0QAA==.',
Xd='Xdknight:BAAANQABCgIIAwAAAA==.',
Xe='Xerø:BAAANQAECggIEAAAAA==.',
Xr='Xray:BAABNQAECn8fAAIBAAkKHA6vvgAHAgABAAkKHA6vvgAHAgAAAA==.',
Xt='Xtra:BAAANQAECgMIAwAAAA==.Xtreme:BAAANQADCggIDQAAAA==.',
Ya='Yamii:BAABNQAECn8qAAMjAAoK2hsoCAAmAgAjAAkKkhwoCAAmAgAEAAgKihKchwA+AQABNQAFFAIIBwAIABgZAA==.Yaphetkotto:BAAANQADCgcJCAAAAA==.Yawnk:BAABNQAECn8ZAAMmAAkKAQwmHwDrAAAmAAcKKw4mHwDrAAAcAAYKLw19NwCxAAAAAA==.',
Yu='Yunsky:BAAANQAECgQIBwAAAA==.',
Za='Zanber:BAAANQADCgIIAgAAAA==.Zandrakar:BAABNQAECn85AAQYAAoK0xgzOgB2AgAYAAoK0xgzOgB2AgAFAAEKAACDOAAtAAAaAAEKPQViSQEpAAAAAA==.Zanosuke:BAAANQAECggIEgAAAA==.Zaria:BAABNQAECn8eAAIdAAkKpBGVcgAJAgAdAAkKpBGVcgAJAgAAAA==.Zaryor:BAABNQAECn8WAAMcAAcKIRTjMgB/AQAcAAcKIRTjMgB/AQAQAAQKYhIiIADkAAAAAA==.Zaun:BAAANQAECgUIBQAAAA==.',
Ze='Zentul:BAAANQAECgQIBAAAAA==.Zerica:BAAANQAECgIIAgAAAA==.Zerika:BAACNQAFFH8HAAIMAAIK+whzJgB6AAAMAAIK+whzJgB6AAA1AAQKfzgAAgwACgobI5EPAEkDAAwACgobI5EPAEkDAAAA.',
Zh='Zhaohu:BAAANQADCgYIBgAAAA==.',
Zi='Zigzwag:BAAANQAECgIIBgAAAA==.Zionna:BAAANQAECgYIEwABNQAECgoKFgALAFkPAA==.Zitos:BAABNQAECn9FAAMOAAoKYCQ+BgDIAwAOAAoKYCQ+BgDIAwAZAAEKfghNKgEsAAABNQAECgoKRQAOAGAkAA==.',
Zo='Zomgqq:BAABNQAECn8jAAMFAAoKMhw/CwC9AgAFAAoKMhw/CwC9AgAYAAQK7Q0X0gDDAAAAAA==.',
Zw='Zwagster:BAAANQAECggIEgAAAA==.',
Zy='Zydis:BAAANQAECgYICgAAAA==.Zyggy:BAABNQAECn8bAAIRAAkKfxIEIwC2AQARAAkKfxIEIwC2AQAAAA==.Zynfanatic:BAAANQAECgcIDgABNQAECgoKMwAKACYcAA==.',
['Än']='Ännihilation:BAAANQAECgIIAgAAAA==.',
['Èe']='Èepy:BAAANQAECgEIAQABNQAECgUIBAAGAAAAAA==.',
['És']='Éstéla:BAABNQAECn8xAAICAAoKaxZVWABqAgACAAoKaxZVWABqAgAAAA==.',
['Ío']='Ío:BAAANQAECgUIDgAAAA==.',
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
