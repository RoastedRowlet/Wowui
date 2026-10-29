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

local lookup = {'Mage-Arcane','Hunter-BeastMastery','Rogue-Subtlety','Warrior-Arms','Shaman-Enhancement','Unknown-Unknown','Warlock-Affliction','DeathKnight-Unholy','Druid-Guardian','Druid-Restoration','Druid-Balance','Priest-Holy','Warrior-Fury','Paladin-Retribution','Evoker-Preservation','DeathKnight-Blood','Priest-Shadow','Hunter-Marksmanship','Evoker-Devastation','Priest-Discipline','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Restoration','Paladin-Holy','Paladin-Protection','Monk-Windwalker','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Mage-Fire','DemonHunter-Vengeance','Druid-Feral','Shaman-Elemental','Warrior-Protection','DeathKnight-Frost','Evoker-Augmentation','Monk-Mistweaver','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abobadrin:BAAANQADCgcIDgAAAA==.Abrakadaver:BAABNQAECn8mAAIBAAoKpBXesAAhAgABAAoKpBXesAAhAgAAAA==.',
Ac='Acceb:BAAANQADCgQJBAAAAA==.',
Ad='Adventureux:BAACNQAFFH8FAAICAAIKuxQhGQCMAAACAAIKuxQhGQCMAAA1AAQKfywAAgIACgpnGHo8ALQCAAIACgpnGHo8ALQCAAAA.',
Ae='Aedx:BAABNQAECn8oAAIDAAkKIxWrEgBZAgADAAkKIxWrEgBZAgAAAA==.Aerolorea:BAAANQADCgYICQAAAA==.',
Al='Alastar:BAABNQAECn8ZAAIEAAgK6h72XAB1AgAEAAgK6h72XAB1AgABNQAFFAIIBQAFACohAA==.Alexmage:BAAANQADCgYIBgABNQADCgcIBwAGAAAAAA==.Alios:BAAANQAECgQIBAAAAA==.Alphasalt:BAAANQADCgcIBwABNQAECgYIFgAHADAYAA==.Alucard:BAAANQAECgYIDwAAAA==.Alunadoom:BAABNQAECn8cAAICAAcKSgYPygBtAQACAAcKSgYPygBtAQAAAA==.Alvera:BAACNQAFFH8KAAIIAAQK6BdICwBZAQAIAAQK6BdICwBZAQA1AAQKfzMAAggACgrKJI0HAIgDAAgACgrKJI0HAIgDAAAA.',
Am='Ambellìna:BAAANQADCgIIAgABNQAECgEIAQAGAAAAAA==.',
An='Angechi:BAEANQADCgIJAgABNQAECgoKHAAJAIcRAA==.Angrydk:BAAANQAECgMIBwAAAA==.Annoying:BAAANQAECgQIBAAAAA==.Antisocial:BAABNQAECn8uAAIIAAoKziAuEgAmAwAIAAoKziAuEgAmAwABNQAECgoKLgAIAM4gAA==.',
Ar='Arm:BAABNQAECn9OAAQKAAoKIhtMCADNAgAKAAoKIhtMCADNAgALAAYKmAyMZgAzAQAJAAIKehMZUgBaAAAAAA==.Armee:BAABNQAECn8iAAIMAAoKIRqpVwAbAgAMAAoKIRqpVwAbAgAAAA==.Armz:BAAANQABCgEIAQAAAA==.',
As='Astrael:BAABNQAECn8VAAIBAAkKwhektgAWAgABAAkKwhektgAWAgAAAA==.Aszea:BAAANQAECgMICQAAAA==.',
At='Attewode:BAAANQAECgEIAQAAAA==.',
Ax='Axas:BAAANQADCgcIBwAAAA==.Axra:BAABNQAECn8jAAINAAoKIA8kDQDmAQANAAoKIA8kDQDmAQAAAA==.',
Ay='Ayda:BAAANQADCgIIAQAAAA==.',
Az='Azairius:BAAANQADCggIGAAAAA==.Azzman:BAAANQADCgMIAwAAAA==.Azóg:BAABNQAECn8XAAIIAAkKjw7IVwCxAQAIAAkKjw7IVwCxAQAAAA==.',
Ba='Balsin:BAABNQAECn8uAAIOAAoKuiP4EwB2AwAOAAoKuiP4EwB2AwAAAA==.Bambii:BAAANQADCgUIBwAAAA==.Bangungot:BAAANQAECgUIBgABNQAFFAgIFwAPABEVAA==.Barlaf:BAABNQAECn8+AAICAAoKABvkNgDGAgACAAoKABvkNgDGAgABNQAECgMIAwAGAAAAAA==.Batou:BAAANQAECgUICAAAAA==.',
Be='Beeski:BAAANQADCgcIFgAAAA==.Beeto:BAACNQAFFH8PAAIOAAUKQhB2DQDaAAAOAAUKQhB2DQDaAAA1AAQKfy8AAg4ACgq5F/OTAPwBAA4ACgq5F/OTAPwBAAAA.Belyndris:BAABNQAECn8oAAIMAAoK1RnNJwAvAgAMAAoK1RnNJwAvAgAAAA==.Benbear:BAEBNQAECn8cAAIJAAoKhxFeFwBVAQAJAAoKhxFeFwBVAQAAAA==.Benlian:BAEBNQAECn8lAAIQAAgKDhG1UgCqAQAQAAgKDhG1UgCqAQABNQAECgoKHAAJAIcRAA==.',
Bl='Blighty:BAAANQAECgcIDQAAAA==.Blâze:BAACNQAFFH8aAAIBAAYKsh+/BwBvAQABAAYKsh+/BwBvAQA1AAQKfy4AAgEACgoII+UJAAkDAAEACgoII+UJAAkDAAAA.',
Bo='Bombardi:BAAANQAECgMIAwAAAA==.Bonknsmash:BAABNQAECn8fAAIEAAgKJhTYjQD6AQAEAAgKJhTYjQD6AQAAAA==.Boof:BAABNQAECn8nAAMRAAoKrRUQHQBaAgARAAkKjBUQHQBaAgAMAAEKvCCWswBbAAAAAA==.Boregut:BAAANQAECggICAAAAA==.',
Br='Brewdock:BAAANQABCgIIAgAAAA==.Bronxor:BAABNQAECn8sAAISAAoKFxWYIQBAAgASAAoKFxWYIQBAAgAAAA==.',
Bu='Bubbleoshift:BAAANQAECgMIBAABNQAECggIFAALACYPAA==.Bushgarden:BAAANQADCgYIBwABNQADCgYICgAGAAAAAA==.Buzsmash:BAAANQAECgYIBgAAAA==.Buzzbuzz:BAAANQAECgMIBQABNQAECgkJGgABAMwQAA==.',
['Bó']='Bóba:BAACNQAFFH8fAAIPAAgKYCKlAQC8AgAPAAgKYCKlAQC8AgA1AAQKfzIAAw8ACgruI+QFAEwDAA8ACgruI+QFAEwDABMABgoaI58FAPQBAAAA.',
['Bö']='Böba:BAABNQAECn8eAAQMAAkKkCQ+DABhAwAMAAkKkCQ+DABhAwAUAAkK0yBpBgAnAgARAAEKAABOeQA1AAABNQAFFAgIHwAPAGAiAA==.',
Ca='Cadroyd:BAABNQAECn8tAAQKAAoKLB0fCgCfAgAKAAkKUhwfCgCfAgALAAMKQgVJnwBhAAAJAAEKAABFZwAAAAAAAA==.Caelin:BAACNQAFFH8GAAMVAAMK1AO9CACUAAAVAAMKqwG9CACUAAAWAAEKZgi1EwA/AAA1AAQKf0UAAxYACgrnEtc1AAACABYACQrnEtc1AAACABUABgqpDgQqANgAAAAA.Cailand:BAABNQAECn8mAAIEAAkKDhRqhwAJAgAEAAkKDhRqhwAJAgAAAA==.Caishana:BAABNQAECn87AAIXAAoKmiPLAgDIAwAXAAoKmiPLAgDIAwAAAA==.Cambium:BAAANQAECgYIEAAAAA==.Camerbunne:BAAANQADCgYIDwAAAA==.Caramel:BAAANQAECgIIAgAAAA==.Catdude:BAAANQAECgYICgAAAA==.',
Ce='Cecil:BAAANQADCgYIBgAAAA==.Celebrate:BAAANQADCgMIAwAAAA==.',
Ch='Chaddingus:BAAANQAECggIEAAAAA==.Chopadk:BAABNQAECn8hAAIQAAkKsA8YUwCoAQAQAAkKsA8YUwCoAQAAAA==.Chumlëy:BAAANQADCgUIBQAAAA==.',
Cl='Clash:BAAANQADCgYIDgAAAA==.Clique:BAABNQAECn8sAAIYAAgKJh67NwCFAgAYAAgKJh67NwCFAgAAAA==.',
Cn='Cnc:BAAANQAECgEIAQAAAA==.',
Co='Coheedkil:BAAANQAECgEIAQAAAA==.Coldbreeze:BAABNQAECn8eAAIBAAcK8wfqFgFmAQABAAcK8wfqFgFmAQAAAA==.Collateral:BAAANQAECgQIBAAAAA==.Colomel:BAABNQAECn8UAAIBAAgKOAqWAwGIAQABAAgKOAqWAwGIAQAAAA==.Comegetsum:BAAANQADCgYIEQAAAA==.Compaktdisc:BAAANQADCgYIBgABNQAECggIFAALACYPAA==.Conqbine:BAAANQAECgQIAwAAAA==.Corg:BAAANQAECgUICgAAAA==.Countchocula:BAABNQAECn8bAAIBAAgK8xFTUQC6AQABAAgK8xFTUQC6AQAAAA==.',
Cr='Crimmi:BAABNQAECn8aAAIIAAgKbgj9LwAKAQAIAAgKbgj9LwAKAQAAAA==.Critzilla:BAAANQAECgYIBQAAAA==.',
Cu='Cuddy:BAAANQADCgYICgAAAA==.',
Cy='Cybuster:BAAANQADCgUJBQABNQAECgoKOQABABweAA==.Cyndle:BAABNQAECn81AAIXAAoK4gyLdQCrAQAXAAoK4gyLdQCrAQAAAA==.',
Da='Daddythicc:BAABNQAECn8pAAIBAAoKowpy5QC+AQABAAoKowpy5QC+AQAAAA==.Darnwrath:BAAANQAECgYIBgAAAA==.Darrkness:BAAANQADCgYIBgAAAA==.',
De='Deadgirljd:BAAANQAECgQIBQAAAA==.Deadillusion:BAAANQADCgUIBQABNQAECgYIDQAGAAAAAA==.Deathpockets:BAAANQAECgMIBAAAAA==.Deran:BAABNQAECn8rAAMOAAgK8hsdYgB0AgAOAAgKSxsdYgB0AgAZAAYKZRp9LQBxAQAAAA==.',
Di='Diante:BAAANQAECgMICQAAAA==.Dimple:BAAANQAECgIJAgAAAA==.Dirtmonkgirt:BAABNQAECn8dAAIaAAoKSBUAEQDVAQAaAAoKSBUAEQDVAQAAAA==.Dirtnasty:BAAANQAECgYICwABNQAFFAMIBwAbAJEgAA==.',
Dk='Dknujabes:BAAANQAECggIDwAAAA==.',
Do='Doofus:BAAANQADCgEIAQAAAA==.Doompockets:BAABNQAECn8iAAMcAAkKxgx/iADRAQAcAAkKrgl/iADRAQAdAAMKJg0cRwCrAAAAAA==.',
Dr='Dracara:BAABNQAECn80AAQeAAoK5hZvBQC7AgAeAAoK5hZvBQC7AgAfAAUK4wyRBQAiAQABAAMKBAeAnAGMAAAAAA==.Dracia:BAAANQAECgYIEAAAAA==.Drakulya:BAAANQABCgQIBAAAAA==.Drakunda:BAAANQAECggICQABNQAECgoKNAAeAOYWAA==.Dreadz:BAABNQAECn8bAAMVAAcKkBA4NQCaAQAVAAcKJhA4NQCaAQAgAAIKJAmWKgBfAAAAAA==.Drewish:BAABNQAECn8rAAIhAAoKbh5zBwDpAgAhAAoKbh5zBwDpAgAAAA==.Drg:BAAANQADCgQIBAABNQADCgUIBQAGAAAAAA==.Drizzle:BAACNQAFFH8GAAIVAAIK0h+pBwCvAAAVAAIK0h+pBwCvAAA1AAQKfzIAAhUACgrmI9wEAIYDABUACgrmI9wEAIYDAAAA.Drktotem:BAABNQAECn81AAMFAAoKjiOgAQApAwAFAAoKjiOgAQApAwAXAAYKtxaCkABfAQAAAA==.Druidia:BAAANQADCgIIAgAAAA==.',
Du='Dulezlok:BAAANQADCgUIBQAAAA==.Dumbdog:BAACNQAFFH8mAAIKAAgKdyGMAADJAgAKAAgKdyGMAADJAgA1AAQKf0kAAgoACgqWIvMDAIcDAAoACgqWIvMDAIcDAAAA.Dumbledwarf:BAAANQADCggICAAAAA==.Dusan:BAABNQAECn82AAIMAAkKFB6ZMwCZAgAMAAkKFB6ZMwCZAgAAAA==.',
['Dï']='Dïvinity:BAAANQADCgIIAgAAAA==.',
Ea='Ea:BAAANQADCgcICAAAAA==.',
Ec='Echeyaket:BAABNQAECn8jAAMXAAoKchzKQABdAgAXAAoKchzKQABdAgAiAAIKmRChDwFsAAAAAA==.',
Ed='Edonsian:BAABNQAECn9DAAIEAAoKvBgmMAAYAgAEAAoKvBgmMAAYAgAAAA==.',
Eg='Egmont:BAAANQADCgUIBwAAAA==.',
El='Elektabuzz:BAAANQADCggIEAABNQAECgoKJAAOAH8cAA==.Elelusion:BAAANQAECgYIDQAAAA==.Eliyah:BAAANQAECgIIAgAAAA==.Elliekins:BAABNQAECn8iAAIMAAoKqwcKSACRAQAMAAoKqwcKSACRAQAAAA==.Elçhapo:BAAANQAECgIIAwAAAA==.',
Em='Emergence:BAAANQAECgEIAQAAAA==.',
En='Endlesshour:BAAANQADCgMIAwAAAA==.Endlessly:BAABNQAECn8YAAIRAAkK2g+5EgCeAQARAAkK2g+5EgCeAQAAAA==.Enoka:BAABNQAECn8xAAIBAAoKahjHLwAyAgABAAoKahjHLwAyAgAAAA==.',
Es='Estelá:BAAANQADCgYIBgAAAA==.',
Et='Etikwa:BAABNQAECn8lAAIKAAkK8g28GQCfAQAKAAkK8g28GQCfAQAAAA==.',
Eu='Euclid:BAAANQAECgMIAwAAAA==.',
Ev='Evaporate:BAAANQAECgUIBQAAAA==.Evilguard:BAABNQAECn8dAAIQAAgKlA0EXwB2AQAQAAgKlA0EXwB2AQAAAA==.',
Ex='Excessive:BAAANQAECgIIAgAAAA==.Exroastbeef:BAAANQADCggICAAAAA==.',
Fa='Falador:BAABNQAECn8XAAIEAAYKPgvv2AA8AQAEAAYKPgvv2AA8AQAAAA==.Fariebubbles:BAAANQAECgMICQAAAA==.',
Fe='Felene:BAABNQAECn8pAAMiAAoKHx1QKQDcAgAiAAoKHx1QKQDcAgAXAAIK7A7HAgFjAAAAAA==.Fenwell:BAAANQADCgcIBwAAAA==.',
Fi='Firitako:BAAANQAECgYIEAAAAA==.',
Fr='Frailey:BAABNQAECn8YAAMHAAcKzxd0CQDsAQAHAAcKzxd0CQDsAQAcAAMKUgzeJwFvAAAAAA==.Frankiejr:BAAANQAECgIIBAABNQAECggIJgAOAGIhAA==.Fraubles:BAAANQAECgMIBAAAAA==.Friedpickel:BAAANQADCgYIBwAAAA==.Friter:BAAANQAECgMIAwAAAA==.Frostnite:BAAANQAECgQIDAAAAA==.Frostpoptart:BAABNQAECn8qAAMFAAkKxxrpCQDVAgAFAAkKxxrpCQDVAgAXAAIKQhcGnQCBAAAAAA==.Frozenblade:BAABNQAECn8sAAIQAAoKvRO9QQD2AQAQAAoKvRO9QQD2AQAAAA==.',
Fu='Furball:BAAANQAECgYICwABNQAFFAYIFQAcAOQVAA==.Furiousgeorg:BAAANQAECgUIDAAAAA==.',
Ga='Gagabooney:BAACNQAFFH8HAAIbAAMKkSBtBwDHAAAbAAMKkSBtBwDHAAA1AAQKfxYAAhsACAouIQgJAJYCABsACAouIQgJAJYCAAAA.Galay:BAAANQAECgQIBgAAAA==.Garabashi:BAAANQADCgcJBwAAAA==.Garrick:BAABNQAECn8WAAQjAAkKWBnlCADBAQAjAAgKOxrlCADBAQAEAAQKCwjoIwGRAAANAAEKKBPgHwBCAAAAAA==.Gazze:BAABNQAECn82AAIJAAkKQgmTIAAEAQAJAAkKQgmTIAAEAQAAAA==.',
Ge='Gemli:BAAANQADCgUIBQAAAA==.Gennissa:BAAANQAECgMIBAAAAA==.Gertog:BAAANQADCgQIBAAAAA==.Gethsemane:BAABNQAECn8jAAMcAAkKGhfeRACEAgAcAAkKGhfeRACEAgAHAAQK6RSgEgAfAQAAAA==.',
Gi='Gigadoot:BAAANQABCgQIAgAAAA==.Gigglez:BAAANQADCgcJCQAAAA==.Gillis:BAAANQADCggIDAAAAA==.',
Gl='Glassdance:BAAANQADCggICgAAAA==.',
Gn='Gnryderp:BAAANQADCgUIBQAAAA==.',
Go='Goam:BAAANQADCggIFwAAAA==.Googrektar:BAAANQAECgQIBAABNQAFFAUICwABAFkUAA==.Goonielama:BAABNQAECn8qAAIQAAoKHCF/DgA7AwAQAAoKHCF/DgA7AwABNQAFFAMIBwAbAJEgAA==.Goonietai:BAAANQAECgUICQABNQAFFAUICwABAFkUAA==.',
Gr='Greenterror:BAAANQADCgIIAgAAAA==.Grid:BAAANQAECgMIAwABNQAFFAIIBAAcAJAOAA==.Griitz:BAAANQAECgQICAAAAA==.Grimmsheeper:BAACNQAFFH8KAAIBAAUKNxQ/KgA5AQABAAUKNxQ/KgA5AQA1AAQKfzoAAwEACgrpIt8aAJUCAAEACgrpIt8aAJUCAB4AAQqdAxsvACcAAAAA.Gryff:BAAANQADCgUJBQAAAA==.',
Gu='Guess:BAAANQAECgQIBAAAAA==.Gurtdk:BAACNQAFFH8jAAQIAAgK7hZIBADtAQAIAAYKwxpIBADtAQAQAAEKAACZKABWAAAkAAEKyQPOGwBSAAA1AAQKfzEAAggACgrwJTALAGEDAAgACgrwJTALAGEDAAAA.',
Gy='Gyat:BAAANQADCgMJAwAAAA==.',
Ha='Hairynujabes:BAABNQAECn8WAAMLAAgK2w09ZQA4AQALAAcKSg09ZQA4AQAJAAIKtBDBUAAzAAAAAA==.Hamandcheeze:BAAANQAECgIIAQAAAA==.Hanyuu:BAABNQAECn8uAAIRAAoKlg48DwDdAQARAAoKlg48DwDdAQAAAA==.',
He='Heiter:BAABNQAECn8mAAIMAAkKCxg3QwBfAgAMAAkKCxg3QwBfAgABNQAECgoKKAAiAOQZAA==.Hellbound:BAABNQAECn84AAMcAAoKORgyMwDeAQAcAAoKvxYyMwDeAQAdAAIK/BMFVQB/AAAAAA==.Hellinhunt:BAABNQAFFH8KAAMCAAgKLAyuFwD9AAASAAUKeQiWEgAWAQACAAMKkROuFwD9AAAAAA==.',
Ho='Holyekko:BAAANQADCgEIAQAAAA==.Holypants:BAAANQADCgYIBgAAAA==.Honk:BAAANQAECgUIBQABNQAECgkJGgABAMwQAA==.Hornivore:BAAANQADCgcIFQABNQAECgoKOgACAIMYAA==.',
Hy='Hyrja:BAAANQADCgUIBgABNQAECgoKNAAeAOYWAA==.',
['Hâ']='Hâvyr:BAAANQADCgIIAQAAAA==.',
Ic='Icefrosting:BAABNQAECn8dAAIBAAoKhhhmLABBAgABAAoKhhhmLABBAgABNQAECgoKIgARAIUdAA==.',
Id='Idistroya:BAAANQAECgUICAABNQAECgoKKwACAEUcAA==.',
Ig='Iggnogg:BAAANQAECgMIBQAAAA==.',
Ik='Ikura:BAACNQAFFH8SAAIMAAUKzBIEDABrAQAMAAUKzBIEDABrAQA1AAQKfy4ABBQACgpUFgUFAEABAAwACgpAEdtmAOoBABQACApREAUFAEABABEAAgrHCP9JADEAAAAA.',
Il='Ilithiya:BAABNQAECn8pAAIVAAoKSySjBACKAwAVAAoKSySjBACKAwAAAA==.Ilk:BAABNQAECn8eAAIFAAgKywlPHgB8AQAFAAgKywlPHgB8AQAAAA==.Illududu:BAAANQAECgEIAQABNQAECgYIDQAGAAAAAA==.',
Im='Imangry:BAAANQADCgEIAQAAAA==.',
Is='Isaidnoice:BAAANQADCgYICgAAAA==.Ishiftmyself:BAABNQAECn8UAAILAAgKJg/7RgDRAQALAAgKJg/7RgDRAQAAAA==.Ishton:BAABNQAECn8pAAIOAAoKRxtESQC5AgAOAAoKRxtESQC5AgAAAA==.Istompgnomes:BAABNQAECn8VAAIiAAcKYBcBdgC/AQAiAAcKYBcBdgC/AQAAAA==.',
It='Itsnowz:BAAANQADCgQIBAAAAA==.',
Ja='Jacobean:BAAANQADCgQIBAAAAA==.Jasøn:BAAANQADCgcIDgABNQAECgkJIAACAIcMAA==.',
Je='Jecthyr:BAABNQAECn8xAAQPAAoKSRq9FgBMAgAPAAkK4Ri9FgBMAgATAAgK6xRsBwClAQAlAAEKjAT7FgAlAAAAAA==.Jefeson:BAAANQAECgYICQAAAA==.Jemhdar:BAAANQAECgEIAQAAAA==.Jermdaga:BAAANQADCgQIBAAAAA==.',
Ji='Jinnasaiquoi:BAABNQAECn8WAAMOAAkKhxdxNgAfAgAOAAkK2xRxNgAfAgAZAAQKTRSUQQDwAAAAAA==.',
Js='Jsdruid:BAAANQAECgYIBgAAAA==.',
Ka='Kaelosu:BAABNQAECn8xAAIcAAkK3BwALwDKAgAcAAkK3BwALwDKAgAAAA==.Kakum:BAAANQAECgcIEQAAAA==.Kaldrogo:BAAANQAECgUIBQAAAA==.Kalnuggets:BAAANQAECgcIBgAAAA==.Kalrathen:BAABNQAECn80AAMMAAoKnximOwB7AgAMAAoKnximOwB7AgARAAEKewFQkgAXAAAAAA==.Kanda:BAABNQAECn8xAAICAAoKaBrNOwC3AgACAAoKaBrNOwC3AgAAAA==.Karsh:BAABNQAECn8bAAMNAAoK7ARoGAAZAQANAAgKJwVoGAAZAQAEAAQKWwRTygB4AAAAAA==.Kazadax:BAABNQAECn8fAAIcAAoK4wy1gQDiAQAcAAoK4wy1gQDiAQAAAA==.',
Ke='Kealosu:BAAANQADCggIDgAAAA==.Keen:BAAANQAECgEIAQAAAA==.Keuaakepo:BAABNQAECn8rAAICAAoKRRwSKABBAgACAAoKRRwSKABBAgAAAA==.',
Ki='Kienne:BAABNQAECn8qAAICAAoKIxTPQADgAQACAAoKIxTPQADgAQAAAA==.Kiljaedra:BAAANQAECgEIAgABNQAECgoKNAAeAOYWAA==.Kinomi:BAAANQADCgYIBgABNQAECggIFAALACYPAA==.Kitenna:BAAANQAECgcIAwAAAA==.',
Kl='Kleenex:BAAANQADCgEIAQAAAA==.',
Ko='Korbanhavoc:BAABNQAECn8XAAIOAAcK4hHMxgCOAQAOAAcK4hHMxgCOAQAAAA==.Korogar:BAAANQAECgQICQAAAA==.',
Kp='Kpes:BAAANQADCgUJBQAAAA==.',
Kr='Kreamyumyums:BAAANQAECgYICgAAAA==.Krisp:BAAANQADCgUICAAAAA==.Krizzl:BAAANQADCgUIBQABNQAFFAYIGgAIALEmAA==.Kronknar:BAAANQABCgQJBAABNQAECgoKLwAiABEdAA==.Krìzzl:BAAANQAECgMIAwABNQAFFAYIGgAIALEmAA==.',
Ky='Kymira:BAABNQAECn8wAAIbAAoKOBpVBwDIAgAbAAoKOBpVBwDIAgAAAA==.',
La='Lace:BAACNQAFFH8EAAMcAAIKkA7EHgBrAAAcAAIKfw3EHgBrAAAdAAEK8QIaEQA0AAA1AAQKf10AAxwACgqgJLAJAH8DABwACgqSIrAJAH8DAB0AAgrzJJsMALoAAAAA.Lanzen:BAAANQADCgEIAQAAAA==.Larrfena:BAABNQAECn86AAICAAoKgxjZLAAtAgACAAoKgxjZLAAtAgAAAA==.Lavatory:BAAANQADCgMIBAAAAA==.Lazarou:BAAANQAECgUIBgAAAA==.',
Le='Legsday:BAAANQAECgEIAQAAAA==.Lementz:BAACNQAFFH8OAAIiAAQKVhHPEgBDAQAiAAQKVhHPEgBDAQA1AAQKfyAAAiIACQp4HjEhAAUDACIACQp4HjEhAAUDAAAA.',
Li='Liadres:BAAANQADCgIIAgAAAA==.Liante:BAAANQADCgcIEgABNQAECgMICQAGAAAAAA==.Libellule:BAAANQABCgQIBAAAAA==.Lilboat:BAAANQAECgEIAQAAAA==.Lillia:BAABNQAECn82AAIcAAkKWhKAOwC7AQAcAAkKWhKAOwC7AQAAAA==.Lillybell:BAAANQADCgUIBQAAAA==.Littleboyz:BAAANQADCgcIBwAAAA==.',
Lo='Loop:BAABNQAFFH8IAAIEAAgKagFSHACEAAAEAAgKagFSHACEAAAAAA==.Loopku:BAAANQAECggICAAAAA==.Lorinash:BAAANQADCgYICQAAAA==.Lothelo:BAAANQAECgEIAgABNQAECgkJGQAOAKEcAA==.',
Lu='Lumpia:BAACNQAFFH8FAAIIAAIKkRW5BwChAAAIAAIKkRW5BwChAAA1AAQKfysAAwgACgpaGyEvAHQCAAgACgpaGyEvAHQCABAABgpYBwhOAK4AAAAA.',
Lv='Lvel:BAAANQADCgYICgAAAA==.',
['Lë']='Lëeloo:BAAANQAECgcIBwABNQAECgoKQAAcADsgAA==.',
Ma='Machinism:BAAANQADCgIIAgABNQADCgcJCAAGAAAAAA==.Maey:BAABNQAECn8xAAMBAAoKZxaAjQBkAgABAAoKzBOAjQBkAgAeAAEKASHLOwBQAAAAAA==.Magoobers:BAAANQADCgEIAQAAAA==.Maktah:BAABNQAECn8vAAMiAAoKER0ELwDAAgAiAAoKER0ELwDAAgAFAAEK/AiiNAA+AAAAAA==.Malpractice:BAAANQAECgUIBQABNQAECggIFAALACYPAA==.Maybesinged:BAABNQAECn88AAIBAAoKlBv8IgBsAgABAAoKlBv8IgBsAgAAAA==.',
Me='Meanboy:BAAANQAECgMIAwAAAA==.Meishra:BAAANQADCgcICQAAAA==.Mentos:BAABNQAECn81AAQTAAoKjx+HBQA5AwATAAoKjx+HBQA5AwAPAAIK4xQSQQCYAAAlAAEKCRNJIwA5AAAAAA==.',
Mi='Midgetninja:BAAANQADCgQIBAABNQAECgoKGAAbAIMfAA==.Miltank:BAACNQAFFH8GAAIOAAIKCRjJFACYAAAOAAIKCRjJFACYAAA1AAQKfzYAAg4ACgqAIEU+ANoCAA4ACgqAIEU+ANoCAAAA.Minaqt:BAAANQADCgEIAQAAAA==.Minatory:BAABNQAECn8kAAIVAAoKqRlvGACZAgAVAAoKqRlvGACZAgAAAA==.Mionn:BAABNQAECn8kAAMOAAoKfxyqawBaAgAOAAkKmR6qawBaAgAYAAEK7gokHwE3AAAAAA==.Misfires:BAAANQABCggIEwAAAA==.',
Ml='Mlleena:BAABNQAECn8fAAIdAAcKLRH1BwDyAAAdAAcKLRH1BwDyAAAAAA==.',
Mo='Moddim:BAAANQADCgUIBQAAAA==.Modotz:BAAANQADCgEIAQAAAA==.Mogg:BAAANQAECgEIAQAAAA==.Moghoul:BAAANQAECgQIBQAAAA==.Montorgo:BAAANQADCgYIBgAAAA==.Moofi:BAAANQADCggIEQABNQAECggIGwAFADgLAA==.Mooncake:BAABNQAECn8fAAMTAAkKIQdqGgCiAQATAAkKIQdqGgCiAQAlAAIKhAJWIgBBAAAAAA==.Moonless:BAAANQAECgEIAQABNQAECgoKQgABAOkXAA==.Moosiah:BAAANQADCgcIBwAAAA==.Mossfire:BAAANQAECgEIAQABNQAECgkJFgAjAFgZAA==.Motoko:BAABNQAECn8fAAMbAAoKvRk/CgByAgAbAAoKvRk/CgByAgAmAAEKQALEVAAgAAAAAA==.',
Mu='Musesong:BAAANQADCgMIAwAAAA==.',
['Mø']='Møø:BAAANQAECgYICwABNQAECgkJIAACAIcMAA==.Møøfi:BAABNQAECn8bAAIFAAgKOAtiEwBQAQAFAAgKOAtiEwBQAQAAAA==.',
Na='Naianasha:BAABNQAECn8ZAAMMAAgK1xtJLwCrAgAMAAgK1xtJLwCrAgAUAAEKWBhsJABIAAAAAA==.Nameless:BAABNQAECn9CAAIBAAoK6ReiIQByAgABAAoK6ReiIQByAgAAAA==.Narc:BAABNQAECn8XAAILAAYKUgWLSgCbAAALAAYKUgWLSgCbAAAAAA==.',
Ne='Necroraise:BAAANQADCgIIAgAAAA==.Neeraj:BAABNQAECn8rAAICAAoKqBWpKAA/AgACAAoKqBWpKAA/AgAAAA==.Nevergreen:BAAANQABCgIIAgAAAA==.',
Ni='Nightreaver:BAAANQAECgQIBAABNQAECgoKGAAbAIMfAA==.Nikwillig:BAAANQAECgUICQAAAA==.Nippiest:BAAANQABCggICwAAAA==.',
No='Nokzash:BAABNQAECn8iAAIYAAoKsx7UEgCzAgAYAAoKsx7UEgCzAgAAAA==.Noova:BAABNQAECn80AAIBAAoKfR76SQDuAgABAAoKfR76SQDuAgAAAA==.',
Ny='Nyang:BAAANQAECgYIDQAAAA==.Nythendrac:BAAANQADCgQIBAABNQAECgoKNAAeAOYWAA==.',
Ob='Obliverat:BAAANQAECggIEgAAAA==.',
Od='Odysseus:BAAANQADCgIIBAAAAA==.',
Oo='Oongaboonga:BAABNQAECn8wAAIEAAgKkh/oMAAUAgAEAAgKkh/oMAAUAgAAAA==.',
Or='Orcaneblast:BAACNQAFFH8LAAIBAAUKWRREGwDVAAABAAUKWRREGwDVAAA1AAQKfzIAAgEACgp7HblJAO8CAAEACgp7HblJAO8CAAAA.Orcsoup:BAABNQAECn8WAAIiAAcKpxtUVgAhAgAiAAcKpxtUVgAhAgABNQAECgoKMwAKACYcAA==.',
Pa='Paddord:BAAANQADCggICgAAAA==.Paranoià:BAAANQADCgIIAgABNQAECgEIAQAGAAAAAA==.',
Pe='Penance:BAAANQAECgYICwAAAA==.Percible:BAAANQAECgIIAgAAAA==.',
Pi='Pivnert:BAABNQAECn8oAAQBAAkK3hkGQAD1AQABAAkKMRgGQAD1AQAeAAIKbBi8LQCPAAAfAAIKVxjZCACJAAAAAA==.',
Pl='Plums:BAAANQAECggICQAAAA==.',
Po='Popdkook:BAAANQADCgYIEgAAAA==.',
Pr='Proko:BAAANQADCggICAAAAA==.',
Ps='Psychopump:BAAANQAECggIDQAAAA==.',
['Pü']='Pünish:BAACNQAFFH8MAAIIAAUKRhyhDABDAQAIAAUKRhyhDABDAQA1AAQKf1cABAgACgqPI/0GAI4DAAgACgqPI/0GAI4DACQAAwpxFcR7ALgAABAAAQpfBRvSACsAAAAA.',
Qq='Qqpewpew:BAAANQAECggIBAAAAA==.',
Qu='Quinn:BAAANQADCgIJAgABNQAECgoKGAAbAIMfAA==.',
Ra='Rabit:BAAANQADCgUIBQAAAA==.Raelina:BAABNQAECn8lAAMBAAkKhSHdTADnAgABAAkKsx/dTADnAgAeAAIKoCISJwC6AAABNQAFFAkJLAABABEeAA==.Ragingiscool:BAAANQADCggIDwAAAA==.Rail:BAAANQAECgEIAQAAAA==.Rajank:BAAANQADCgQIBAAAAA==.Rallek:BAABNQAECn8gAAIYAAoKjRB4bADSAQAYAAoKjRB4bADSAQAAAA==.Ranuggul:BAAANQAECgIIAQAAAA==.Rarn:BAAANQADCgMIAwABNQAECgoKMgAQAG4cAA==.Ratsrepus:BAAANQADCgcICwAAAA==.Raza:BAAANQAECgQIDAABNQAFFAUIDAAIAEYcAA==.',
Re='Read:BAABNQAECn8UAAILAAUK4RFxPwDHAAALAAUK4RFxPwDHAAAAAA==.Reddawn:BAAANQADCgcIBwAAAA==.Remeras:BAABNQAECn8VAAIOAAkKwBGrlQD4AQAOAAkKwBGrlQD4AQAAAA==.',
Ri='Riken:BAABNQAECn8UAAImAAcKvQ3qJABUAQAmAAcKvQ3qJABUAQAAAA==.Ripblast:BAAANQAECgEIAQABNQAECgoKGAAbAIMfAA==.Ritual:BAABNQAECn80AAIXAAoK2RoFDgDrAgAXAAoK2RoFDgDrAgAAAA==.',
Ro='Roadi:BAAANQAECgUIBwABNQAECgoKQAAcADsgAA==.Roxer:BAABNQAECn8hAAIYAAoKGhEYUQAnAgAYAAoKGhEYUQAnAgAAAA==.',
Ru='Rukaa:BAAANQAECgIIAwAAAA==.Rummyy:BAABNQAECn8eAAMVAAoK0BwpFgCyAgAVAAoK0BwpFgCyAgAWAAEKkwwVjwA8AAAAAA==.',
Ry='Rycken:BAABNQAECn81AAMKAAoKaA7ZKQDQAQAKAAoKaA7ZKQDQAQALAAgKWxgLHACsAQAAAA==.',
Sa='Saeylva:BAAANQAECgQIBwAAAA==.Saosis:BAAANQAECgYIBgAAAA==.Savage:BAAANQADCgIIAgAAAA==.Sayurri:BAAANQADCgEJAQAAAA==.',
Sc='Scribble:BAAANQAECgQICAAAAA==.Sculper:BAABNQAECn8XAAInAAcK6hFBDQB2AQAnAAcK6hFBDQB2AQAAAA==.',
Se='Senica:BAABNQAECn8mAAIMAAoK3yJGAgDnAwAMAAoK3yJGAgDnAwAAAA==.Seriphina:BAAANQADCggICAAAAA==.',
Sg='Sgornyweaver:BAAANQADCgUJBQAAAA==.',
Sh='Shabbarankzz:BAABNQAECn86AAIkAAoK7ROrNQADAgAkAAoK7ROrNQADAgAAAA==.Shadetotem:BAABNQAECn8iAAIFAAcKqxH+FQAqAQAFAAcKqxH+FQAqAQAAAA==.Shammyblammy:BAAANQABCgEIAQAAAA==.Sheshotu:BAAANQADCggIFwAAAA==.Shiftor:BAAANQADCggIEgAAAA==.Shinedown:BAAANQADCgMIAwAAAA==.Shmoopy:BAAANQAECgIIAgAAAA==.Shradehn:BAABNQAECn8ZAAIWAAkK5RXMLAA9AgAWAAkK5RXMLAA9AgAAAA==.Shutitdown:BAAANQAECgUIBQAAAA==.',
Si='Sisterswede:BAABNQAECn8dAAIRAAkK/h1LEwDPAgARAAkK/h1LEwDPAgAAAA==.Sizzle:BAABNQAECn8aAAIBAAkKzBBAowA7AgABAAkKzBBAowA7AgAAAA==.',
Sm='Smokeahontas:BAAANQAECgQIDQAAAA==.Smokindots:BAAANQAECgcIEgABNQAFFAQIDgAXAJ8XAA==.Smokingreen:BAAANQADCggICAABNQAFFAQIDgAXAJ8XAA==.Smokinice:BAAANQADCggICAABNQAFFAQIDgAXAJ8XAA==.Smokinloud:BAAANQADCgIIAgAAAA==.Smokinmyrrh:BAAANQAECgUIBQABNQAFFAQIDgAXAJ8XAA==.Smokinmyth:BAAANQADCgcICAAAAA==.Smokinpsalm:BAABNQAECn8WAAIMAAgKzQ+NgQCTAQAMAAgKzQ+NgQCTAQABNQAFFAQIDgAXAJ8XAA==.Smokintotem:BAACNQAFFH8OAAIXAAQKnxfVFgDxAAAXAAQKnxfVFgDxAAA1AAQKfz4AAxcACgrkIoMMAFwDABcACgrkIoMMAFwDACIABgqBGllsANsBAAAA.',
Sn='Snawkin:BAAANQADCgEIAQAAAA==.',
Sp='Spaghet:BAEBNQAECn8VAAIiAAkKURwZEACWAgAiAAkKURwZEACWAgABNQAFFAYICwAEADYSAA==.Sparklnmagic:BAAANQAECgIIAgAAAA==.Spore:BAAANQADCgIIAgAAAA==.',
Sq='Squigboogalo:BAAANQADCgEIAQAAAA==.',
St='Steadyrock:BAABNQAECn8ZAAMLAAoK7xRCNwAzAgALAAoK7xRCNwAzAgAKAAEK8QR4eAAuAAAAAA==.Stemi:BAAANQAECgEIAQAAAA==.Steveirwin:BAAANQADCggJCAAAAA==.Stiffsheets:BAAANQAECgUIBAABNQAECgoKGAAbAIMfAA==.Stiltz:BAAANQADCgEIAQAAAA==.Stormywind:BAABNQAECn8bAAIiAAgKQQhojQCCAQAiAAgKQQhojQCCAQAAAA==.Stormz:BAABNQAECn86AAILAAoKARKuGADQAQALAAoKARKuGADQAQAAAA==.',
Su='Sunblade:BAABNQAECn8VAAIQAAcKGhVyWwCFAQAQAAcKGhVyWwCFAQABNQAECgoKQgABAOkXAA==.Sundayskoolz:BAAANQADCgUIBQAAAA==.Sundowning:BAAANQAECgcIDAAAAA==.Sunreaver:BAAANQAECggIDgAAAA==.Supercappy:BAAANQAECgIIBAAAAA==.Suraegi:BAAANQAECgIIAgAAAA==.',
Sw='Swabby:BAAANQADCgEIAQAAAA==.Swiftdragon:BAABNQAECn8YAAMbAAoKgx/GBAAlAwAbAAgK6iPGBAAlAwAaAAIKThLEOAB2AAAAAA==.',
Ta='Taapfer:BAAANQAECgMIAwABNQAECgoKJgABAKQVAA==.Tackyh:BAABNQAECn8pAAICAAcKiR18dwAgAgACAAcKiR18dwAgAgAAAA==.Takamatsu:BAABNQAECn84AAMMAAkKXiRnFgAgAwAMAAkKXiRnFgAgAwAUAAMKDA6LGgCWAAAAAA==.Taku:BAAANQAECgIIBAAAAA==.Tanktoucher:BAAANQAECggIAQAAAA==.Tar:BAABNQAECn8gAAMCAAkKhwzOuwCMAQACAAgK2gzOuwCMAQASAAMKFAiGZACZAAAAAA==.Taxii:BAABNQAECn8wAAMEAAoKsCXNJQAiAwAEAAoK8iLNJQAiAwANAAgKJSXpBgCRAgAAAA==.',
Te='Tealnujabes:BAAANQAECgYIBwAAAA==.Teapots:BAABNQAFFH8FAAIFAAIKKiEAAwDAAAAFAAIKKiEAAwDAAAAAAA==.Tempi:BAAANQABCgMIAwABNQAECgYIBgAGAAAAAA==.Tenpiece:BAAANQADCgMIAwAAAA==.',
Th='Thayelith:BAAANQAECgUIBAAAAA==.Thedeus:BAABNQAECn8ZAAIOAAkKoRz8UwCZAgAOAAkKoRz8UwCZAgAAAA==.Thellira:BAAANQADCgEIAQAAAA==.Thermaul:BAABNQAECn84AAIFAAoKoBpRCwC7AgAFAAoKoBpRCwC7AgAAAA==.Threebeans:BAABNQAECn8zAAMKAAoKJhwGDQD+AgAKAAoKJhwGDQD+AgALAAcK9BHwRgDSAQAAAA==.Thromir:BAACNQAFFH8HAAMOAAQKGR28EQA0AQAOAAMKbiC8EQA0AQAYAAMKyA8rGADjAAA1AAQKfywAAw4ACgqzJRAGAE0DAA4ACQqzJRAGAE0DABgACQoEIDQXAB8DAAAA.Thyrn:BAABNQAECn8yAAIQAAoKbhz+EgAYAgAQAAoKbhz+EgAYAgAAAA==.',
Ti='Tirare:BAABNQAECn8iAAIIAAgKvRpJNABZAgAIAAgKvRpJNABZAgAAAA==.',
Tr='Tri:BAABNQAECn8mAAIOAAgKYiH4QQDPAgAOAAgKYiH4QQDPAgAAAA==.Tristam:BAAANQAECgEIAQAAAA==.',
Tu='Tuneleitor:BAABNQAECn8oAAIoAAoKyxJDAwABAgAoAAoKyxJDAwABAgAAAA==.Turdferguson:BAAANQAECgMIAwABNQAFFAMIBwAbAJEgAA==.Turgrok:BAABNQAECn8XAAMSAAgKUAuoNACoAQASAAgKUAuoNACoAQACAAEKeQZTEgEzAAAAAA==.',
Tw='Twothang:BAABNQAECn8UAAMQAAgKOAiyagBJAQAQAAgKoweyagBJAQAkAAIKMwWlnwBRAAAAAA==.',
Ty='Tyllan:BAABNQAECn85AAMBAAoKHB6uWQCgAQABAAkKHRyuWQCgAQAeAAMKUB1/EgDnAAAAAA==.',
['Tâ']='Tâku:BAAANQAECgIIAgAAAA==.',
Up='Upgrayedd:BAAANQAECgQICgAAAA==.',
Ur='Urugargo:BAAANQABCgYIBgAAAA==.',
Va='Vainhellsing:BAABNQAECn8bAAIWAAcKQgbqPwDKAAAWAAcKQgbqPwDKAAAAAA==.Vanzier:BAABNQAECn8XAAICAAoKpRWHagA+AgACAAoKpRWHagA+AgAAAA==.Vaxis:BAABNQAECn8kAAICAAoKOQ/uggAGAgACAAoKOQ/uggAGAgAAAA==.',
Vi='Vid:BAACNQAFFH8RAAImAAcKQxThAgDmAQAmAAcKQxThAgDmAQA1AAQKfzEAAiYACgo9HyMJAPkCACYACgo9HyMJAPkCAAAA.',
Vo='Voidillusion:BAAANQAECgMIAwABNQAECgYIDQAGAAAAAA==.Voldoom:BAAANQAECgIIAwAAAA==.',
Wa='Watooie:BAAANQADCgYIBgAAAA==.',
We='Weave:BAAANQABCgIIAgABNQAFFAIIBAAcAJAOAA==.Wernov:BAABNQAECn8oAAMiAAoK5BmCMgCwAgAiAAoK5BmCMgCwAgAXAAUK5BA2rAAYAQAAAA==.',
Wh='Whitetail:BAAANQAECgEIAgAAAA==.',
Wi='Wichan:BAABNQAECn8wAAIJAAoKpBqaCwD/AQAJAAoKpBqaCwD/AQAAAA==.Wildsniper:BAAANQABCgIIAgAAAA==.Wildstrike:BAAANQADCgYIBgABNQAECgoKHwAbAL0ZAA==.Wiziviji:BAABNQAECn8XAAIBAAgKKweLEwFsAQABAAgKKweLEwFsAQAAAA==.',
Wo='Woodrow:BAAANQADCgcIBwAAAA==.',
Ws='Ws:BAAANQAECgIIAgAAAA==.',
Xa='Xanorea:BAAANQADCgYIBgABNQAECgcIFwATAO0QAA==.',
Xd='Xdknight:BAAANQABCgIIAwAAAA==.',
Xe='Xerø:BAAANQAECggIDwAAAA==.',
Xr='Xray:BAABNQAECn8fAAIBAAkKHA6vvgAHAgABAAkKHA6vvgAHAgAAAA==.',
Xt='Xtra:BAAANQAECgMIAwAAAA==.Xtreme:BAAANQADCggIDQAAAA==.',
Ya='Yamii:BAABNQAECn8jAAMjAAoKeBqvDgBBAgAjAAkK/hqvDgBBAgAEAAgKihInbABDAQABNQAFFAIIBQAIAJEVAA==.Yaphetkotto:BAAANQADCgcJCAAAAA==.Yawnk:BAABNQAECn8YAAMmAAkKwAsJGQDzAAAmAAcKKw4JGQDzAAAaAAYKDwovMwCWAAAAAA==.',
Yu='Yunsky:BAAANQAECgIIBQAAAA==.',
Za='Zanber:BAAANQADCgIIAgAAAA==.Zandrakar:BAABNQAECn81AAQXAAoK0xgzOgB2AgAXAAoK0xgzOgB2AgAFAAEKAACDOAAtAAAiAAEKPQViSQEpAAAAAA==.Zanosuke:BAAANQAECggIEgAAAA==.Zaria:BAABNQAECn8eAAIcAAkKpBGVcgAJAgAcAAkKpBGVcgAJAgAAAA==.Zaryor:BAABNQAECn8WAAMaAAcKIRTjMgB/AQAaAAcKIRTjMgB/AQAbAAQKYhIiIADkAAAAAA==.Zaun:BAAANQAECgUIBQAAAA==.',
Ze='Zentul:BAAANQAECgQIBAAAAA==.Zerica:BAAANQAECgIIAgAAAA==.Zerika:BAACNQAFFH8FAAIMAAIK9wivHwB9AAAMAAIK9wivHwB9AAA1AAQKfzQAAgwACgo1IpEPAEkDAAwACgo1IpEPAEkDAAAA.',
Zh='Zhaohu:BAAANQADCgYIBgAAAA==.',
Zi='Zigzwag:BAAANQAECgIIBgAAAA==.Zionna:BAAANQAECgYIEQABNQAECggIFAALACYPAA==.Zitos:BAABNQAECn9FAAMOAAoKYCQ+BgDIAwAOAAoKYCQ+BgDIAwAYAAEKfghNKgEsAAABNQAECgoKRQAOAGAkAA==.',
Zo='Zomgqq:BAABNQAECn8fAAMFAAoKeBk/CwC9AgAFAAoKeBk/CwC9AgAXAAQK7Q0X0gDDAAAAAA==.',
Zw='Zwagster:BAAANQAECgYICwAAAA==.',
Zy='Zydis:BAAANQAECgUICgAAAA==.Zyggy:BAABNQAECn8YAAIQAAkKpxAzHQCnAQAQAAkKpxAzHQCnAQAAAA==.Zynfanatic:BAAANQAECgcIDAABNQAECgoKMwAKACYcAA==.',
['Än']='Ännihilation:BAAANQAECgIIAgAAAA==.',
['Èe']='Èepy:BAAANQAECgEIAQABNQAECgQIBAAGAAAAAA==.',
['És']='Éstéla:BAABNQAECn8tAAICAAoKnRRVWABqAgACAAoKnRRVWABqAgAAAA==.',
['Ío']='Ío:BAAANQAECgUICwAAAA==.',
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
