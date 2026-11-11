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
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abobadrin:BAAANQADCgcIDgAAAA==.Abrakadaver:BAABNQAECn8mAAIBAAoKpBXesAAhAgABAAoKpBXesAAhAgAAAA==.',
Ac='Acceb:BAAANQADCgQJBAAAAA==.',
Ad='Adventureux:BAACNQAFFH8KAAICAAUK9BMoEwDnAAACAAUK9BMoEwDnAAA1AAQKfzIAAgIACgppGno8ALQCAAIACgppGno8ALQCAAAA.',
Ae='Aedx:BAABNQAECn8oAAIDAAkKIxWrEgBZAgADAAkKIxWrEgBZAgAAAA==.Aerolorea:BAAANQADCgYICQAAAA==.',
Ai='Aiblul:BAAANQAECgQIBAAAAA==.',
Al='Alastar:BAABNQAECn8ZAAIEAAgK6h72XAB1AgAEAAgK6h72XAB1AgABNQAFFAUICgAFAAoaAA==.Alexmage:BAAANQADCgYIBgABNQADCgcIBwAGAAAAAA==.Alios:BAAANQAECgQIBAAAAA==.Alphasalt:BAAANQADCgcIBwABNQAECgYIFgAHADAYAA==.Alucard:BAAANQAECgYIDwAAAA==.Alunadoom:BAABNQAECn8nAAICAAkKAwcPygBtAQACAAkKAwcPygBtAQAAAA==.Alvera:BAACNQAFFH8KAAIIAAQK6BdICwBZAQAIAAQK6BdICwBZAQA1AAQKfz0AAggACgpCJY0HAIgDAAgACgpCJY0HAIgDAAAA.',
Am='Ambellìna:BAAANQADCgIIAgABNQAECgEIAQAGAAAAAA==.',
An='Angechi:BAEANQADCgIJAgABNQAECgoKJgAJANMWAA==.Angrydk:BAAANQAECgUIEAAAAA==.Annoying:BAAANQAECgUICwAAAA==.Antisocial:BAABNQAECn8uAAIIAAoKziAuEgAmAwAIAAoKziAuEgAmAwABNQAECgoKLgAIAM4gAA==.',
Ar='Arm:BAABNQAECn9SAAQKAAoK/RsoDgDNAgAKAAoK/RsoDgDNAgALAAYKmAyMZgAzAQAJAAQKyw49VgBdAAAAAA==.Armee:BAABNQAECn8iAAIMAAoKIRqpVwAbAgAMAAoKIRqpVwAbAgAAAA==.Armz:BAAANQABCgEIAQAAAA==.',
As='Astrael:BAACNQAFFH8HAAIBAAUK0ApxJgDTAAABAAUK0ApxJgDTAAA1AAQKfxoAAgEACQqYGKS2ABYCAAEACQqYGKS2ABYCAAAA.Aszea:BAAANQAECgUIEgAAAA==.',
At='Attewode:BAAANQAECgEIAQAAAA==.',
Ax='Axas:BAAANQADCgcICwAAAA==.Axra:BAABNQAECn8pAAINAAoK0A8kDQDmAQANAAoK0A8kDQDmAQAAAA==.',
Ay='Ayda:BAAANQADCgIIAQAAAA==.',
Az='Azairius:BAAANQADCggIGAAAAA==.Azzman:BAAANQADCgMIAwAAAA==.Azóg:BAABNQAECn8nAAIIAAoKbRNzGQAKAgAIAAoKbRNzGQAKAgAAAA==.',
Ba='Balsin:BAABNQAECn8uAAIOAAoKuiP4EwB2AwAOAAoKuiP4EwB2AwAAAA==.Bambii:BAAANQADCgUIBwAAAA==.Bangungot:BAAANQAECgUIBgABNQAFFAkJGgAPACQUAA==.Barlaf:BAABNQAECn9GAAICAAoKvBzkNgDGAgACAAoKvBzkNgDGAgABNQAECgMIAwAGAAAAAA==.Batou:BAAANQAECgUICAAAAA==.',
Be='Beeski:BAAANQADCggIHQAAAA==.Beeto:BAACNQAFFH8XAAIOAAUKJBp2DgABAQAOAAUKJBp2DgABAQA1AAQKfzQAAg4ACgp+GXxXABcCAA4ACgp+GXxXABcCAAAA.Bellflower:BAAANQAECgQIAwABNQAECgoKGwAQAIMhAA==.Belyndris:BAABNQAECn8oAAIMAAoK1RldRABaAgAMAAoK1RldRABaAgAAAA==.Benbear:BAEBNQAECn8mAAIJAAoK0xbeEAAUAgAJAAoK0xbeEAAUAgAAAA==.Benlian:BAEBNQAECn8rAAIRAAkKkBFkOgBKAQARAAkKkBFkOgBKAQABNQAECgoKJgAJANMWAA==.',
Bl='Blighty:BAAANQAECgcIDQAAAA==.Bloran:BAAANQADCgIIAgAAAA==.Blâze:BAACNQAFFH8bAAIBAAcKiR3uCQC1AQABAAcKiR3uCQC1AQA1AAQKfzAAAgEACgoII7cYANoCAAEACgoII7cYANoCAAAA.',
Bo='Bombardi:BAAANQAECgMIAwAAAA==.Bonknsmash:BAABNQAECn8fAAIEAAgKJhTYjQD6AQAEAAgKJhTYjQD6AQAAAA==.Boof:BAABNQAECn8nAAMSAAoKrRUQHQBaAgASAAkKjBUQHQBaAgAMAAEKvCCH2gBVAAAAAA==.Boregut:BAAANQAECggICAAAAA==.',
Br='Brewdock:BAAANQABCgIIAgAAAA==.Bronxor:BAABNQAECn8vAAMTAAoK2xaYIQBAAgATAAoKMhaYIQBAAgACAAEKhxdlKwFNAAAAAA==.',
Bu='Bubbleoshift:BAAANQAECgcICAABNQAECgoKFgALAFkPAA==.Bushgarden:BAAANQADCgYIBwABNQADCgYICgAGAAAAAA==.Buzsmash:BAAANQAECgYIBgAAAA==.Buzzbuzz:BAAANQAECgMIBQABNQAECgkJGgABAMwQAA==.',
['Bó']='Bóba:BAACNQAFFH8fAAIPAAgKYCKlAQC8AgAPAAgKYCKlAQC8AgA1AAQKfzIAAw8ACgruI+QFAEwDAA8ACgruI+QFAEwDABQABgoaI8UIAOIBAAAA.',
['Bö']='Böba:BAABNQAECn8eAAQMAAkKkCQ+DABhAwAMAAkKkCQ+DABhAwAVAAkK0yBpBgAnAgASAAEKAABOeQA1AAABNQAFFAgIHwAPAGAiAA==.',
Ca='Cadroyd:BAABNQAECn8zAAQKAAoKjh2GEQCWAgAKAAkKvxyGEQCWAgALAAQKHA4BWQCqAAAJAAEKAAA1hgAAAAAAAA==.Caelin:BAACNQAFFH8KAAMWAAQKUgZQCgCrAAAWAAQKKQRQCgCrAAAXAAEKZgiPGgA8AAA1AAQKf1YAAxcACgpTE9c1AAACABcACQpTE9c1AAACABYACApqDi4lAFwBAAAA.Cailand:BAABNQAECn8uAAIEAAoKmxVJWgDcAQAEAAoKmxVJWgDcAQAAAA==.Caishana:BAABNQAECn9EAAIYAAoKmiNWBgCnAwAYAAoKmiNWBgCnAwAAAA==.Cambium:BAAANQAECgYIEQAAAA==.Camerbunne:BAAANQADCgYIEQAAAA==.Caramel:BAAANQAECgMIBQAAAA==.Catdude:BAAANQAECgUICwAAAA==.',
Ce='Cecil:BAAANQADCgYIBgAAAA==.Celebrate:BAAANQADCgMIAwAAAA==.',
Ch='Chaddingus:BAAANQAECggIEAAAAA==.Chopadk:BAABNQAECn8hAAIRAAkKsA8YUwCoAQARAAkKsA8YUwCoAQAAAA==.',
Cl='Clash:BAAANQADCgYIDgAAAA==.Clique:BAABNQAECn8uAAIZAAkKbRy7NwCFAgAZAAkKbRy7NwCFAgAAAA==.',
Cn='Cnc:BAAANQAECgEIAQAAAA==.',
Co='Coheedkil:BAAANQAECgEIAQAAAA==.Coldbreeze:BAABNQAECn8eAAIBAAcK8wfqFgFmAQABAAcK8wfqFgFmAQAAAA==.Collateral:BAAANQAECgQIBAAAAA==.Colomel:BAABNQAECn8UAAIBAAgKOAqWAwGIAQABAAgKOAqWAwGIAQAAAA==.Comegetsum:BAAANQADCgYIEQAAAA==.Compaktdisc:BAAANQADCgYIBgABNQAECgoKFgALAFkPAA==.Conqbine:BAAANQAECgQIAwAAAA==.Corg:BAAANQAECggICwAAAA==.Countchocula:BAABNQAECn8rAAIBAAkKGhSLTQAYAgABAAkKGhSLTQAYAgAAAA==.',
Cr='Crimmi:BAABNQAECn8dAAIIAAkKwQgONwAuAQAIAAkKwQgONwAuAQAAAA==.Critzilla:BAAANQAECgYIBQAAAA==.',
Cu='Cuddy:BAAANQADCgYICgAAAA==.',
Cy='Cybuster:BAAANQADCgUJBQABNQAECgoKVgABANgfAA==.Cyndle:BAABNQAECn86AAIYAAoK4gyLdQCrAQAYAAoK4gyLdQCrAQAAAA==.',
Da='Daddythicc:BAABNQAECn8sAAIBAAoKowpy5QC+AQABAAoKowpy5QC+AQAAAA==.Darnwrath:BAAANQAECgYIBgAAAA==.Darrkness:BAAANQADCgYIBgAAAA==.',
De='Deadgirljd:BAAANQAECgQICQAAAA==.Deadillusion:BAAANQADCgUIBQABNQAECgoKIAAaAGMfAA==.Deathpockets:BAAANQAECgMIBAAAAA==.Deran:BAABNQAECn8yAAMOAAoKTh7GPABmAgAOAAoK0B3GPABmAgAbAAcK4Bd9LQBxAQAAAA==.',
Di='Diante:BAAANQAECgUIEgAAAA==.Dimple:BAAANQAECgIJAgAAAA==.Dirtmonkgirt:BAABNQAECn8dAAIcAAoKSBW5GQDIAQAcAAoKSBW5GQDIAQAAAA==.Dirtnasty:BAABNQAECn8ZAAIJAAoKECEaBQACAwAJAAoKECEaBQACAwABNQAFFAMIBwAQAJEgAA==.',
Dk='Dknujabes:BAAANQAECggIDwAAAA==.',
Do='Doofus:BAAANQADCgEIAQAAAA==.Doompockets:BAABNQAECn8iAAMdAAkKxgx/iADRAQAdAAkKrgl/iADRAQAeAAMKJg0cRwCrAAAAAA==.',
Dr='Dracara:BAABNQAECn80AAQfAAoK5hZvBQC7AgAfAAoK5hZvBQC7AgAgAAUK4wyRBQAiAQABAAMKBAeAnAGMAAAAAA==.Dracia:BAAANQAECgYIEAAAAA==.Drakunda:BAABNQAECn8eAAQFAAoKJQwoFQCoAQAFAAoKJQwoFQCoAQAYAAQKVgPGxAB9AAAaAAEKAABsEgEAAAABNQAECgoKNAAfAOYWAA==.Dreadz:BAABNQAECn8bAAMWAAcKkBA4NQCaAQAWAAcKJhA4NQCaAQAhAAIKJAmWKgBfAAAAAA==.Drewish:BAABNQAECn8uAAIiAAoKFB9zBwDpAgAiAAoKFB9zBwDpAgAAAA==.Drg:BAAANQADCgQIBAABNQADCgUIBQAGAAAAAA==.Drizzle:BAACNQAFFH8HAAIWAAIK0h/MCgCgAAAWAAIK0h/MCgCgAAA1AAQKf0UAAhYACgoFJNwEAIYDABYACgoFJNwEAIYDAAAA.Drktotem:BAABNQAECn89AAMFAAoKjiMlAwBvAwAFAAoKjiMlAwBvAwAYAAYKtxaCkABfAQAAAA==.Druidia:BAAANQADCgIIAgAAAA==.',
Du='Dulezlok:BAAANQADCgUIBQAAAA==.Dumbdog:BAACNQAFFH8mAAIKAAgKdyGMAADJAgAKAAgKdyGMAADJAgA1AAQKf0wAAgoACgrjIvMDAIcDAAoACgrjIvMDAIcDAAAA.Dumbledwarf:BAAANQADCggICAAAAA==.Dusan:BAABNQAECn87AAIMAAoK8RyZMwCZAgAMAAoK8RyZMwCZAgAAAA==.',
['Dï']='Dïvinity:BAAANQADCgIIAgAAAA==.',
Ea='Ea:BAAANQADCgcICAAAAA==.',
Ec='Echeyaket:BAABNQAECn8tAAMYAAoK/x5YKwBkAgAYAAoK/x5YKwBkAgAaAAIKmRChDwFsAAAAAA==.',
Ed='Edonsian:BAABNQAECn9TAAIEAAoKvBiMPABAAgAEAAoKvBiMPABAAgAAAA==.',
Eg='Egmont:BAAANQADCgUIBwAAAA==.',
El='Elektabuzz:BAAANQADCggIEAABNQAECgoKMQAOAP4fAA==.Elelusion:BAABNQAECn8gAAIaAAoKYx85EQDYAgAaAAoKYx85EQDYAgAAAA==.Eliyah:BAAANQAECgYICAAAAA==.Elliekins:BAABNQAECn8rAAIMAAoKqwdPawCDAQAMAAoKqwdPawCDAQAAAA==.Elçhapo:BAAANQAECgIIAwAAAA==.',
Em='Emergence:BAAANQAECgEIAQAAAA==.',
En='Endlesshour:BAAANQADCgMIAwAAAA==.Endlessly:BAABNQAECn8oAAISAAkK/xLrFwDQAQASAAkK/xLrFwDQAQAAAA==.Enoka:BAABNQAECn88AAIBAAoKoRm4OwBOAgABAAoKoRm4OwBOAgAAAA==.',
Es='Estelá:BAAANQADCgYICgAAAA==.',
Et='Etikwa:BAABNQAECn81AAMKAAoKZQ2wIwC6AQAKAAoKZQ2wIwC6AQALAAUKgAMxaAB3AAAAAA==.',
Eu='Euclid:BAAANQAECgQIBgAAAA==.',
Ev='Evaporate:BAAANQAECgYIBgAAAA==.Evilguard:BAABNQAECn8dAAIRAAgKlA0EXwB2AQARAAgKlA0EXwB2AQAAAA==.',
Ex='Excessive:BAAANQAECgIIAgAAAA==.Exroastbeef:BAAANQADCggICAAAAA==.',
Fa='Falador:BAABNQAECn8XAAIEAAYKPgvv2AA8AQAEAAYKPgvv2AA8AQAAAA==.Fariebubbles:BAAANQAECgUIEgAAAA==.',
Fe='Felene:BAACNQAFFH8IAAIaAAUKAgoCEwDHAAAaAAUKAgoCEwDHAAA1AAQKfy8AAxoACgqYHlApANwCABoACgqYHlApANwCABgAAgrsDscCAWMAAAAA.Fenwell:BAAANQAECgQIBAABNQAECgkJOAAMAOgYAA==.',
Fi='Firitako:BAABNQAECn8aAAMYAAYKpA4SowAuAQAYAAYKpA4SowAuAQAaAAUKXw1wkADTAAAAAA==.',
Fr='Frailey:BAABNQAECn8ZAAMHAAgK6hd0CQDsAQAHAAgK6hd0CQDsAQAdAAMKUgzeJwFvAAAAAA==.Frankiejr:BAAANQAECgMIBwABNQAECgoKNgAOAAkgAA==.Fraubles:BAAANQAECgMIBAAAAA==.Friedpickel:BAAANQADCgYIBwAAAA==.Friter:BAAANQAECgMIAwAAAA==.Frostnite:BAAANQAECgUIEAAAAA==.Frostpoptart:BAABNQAECn8zAAMFAAoKRRrpCQDVAgAFAAoKRRrpCQDVAgAYAAIKQhe5xQB6AAAAAA==.Frozenblade:BAABNQAECn80AAIRAAoK4hO9QQD2AQARAAoK4hO9QQD2AQAAAA==.',
Fu='Furball:BAAANQAECgcIEgABNQAFFAcIFgAdALIRAA==.Furiousgeorg:BAAANQAECgUIDAAAAA==.',
Ga='Gagabooney:BAACNQAFFH8HAAIQAAMKkSBtBwDHAAAQAAMKkSBtBwDHAAA1AAQKfxkAAhAACAouIQgJAJYCABAACAouIQgJAJYCAAAA.Galay:BAAANQAECgcIEgAAAA==.Garabashi:BAAANQADCgcJBwAAAA==.Garrick:BAABNQAECn8mAAQNAAkKXBopCgDYAQANAAgKaBQpCgDYAQAjAAgKOxoGEACeAQAEAAQKCwjoIwGRAAAAAA==.Gazze:BAABNQAECn87AAIJAAoKUgpwKAAuAQAJAAoKUgpwKAAuAQAAAA==.',
Ge='Gemli:BAAANQADCgUIBQAAAA==.Gennissa:BAAANQAECgMIBAAAAA==.Gertog:BAAANQAECgQIBAAAAA==.Gethsemane:BAABNQAECn8lAAMdAAoKBhbeRACEAgAdAAoKBhbeRACEAgAHAAQK6RSgEgAfAQAAAA==.',
Gi='Gigadoot:BAAANQABCgQIAgAAAA==.Gigglez:BAAANQADCgcJCQAAAA==.Gillis:BAAANQADCggIDAAAAA==.',
Gl='Glassdance:BAAANQAECgMIAwAAAA==.',
Gn='Gnryderp:BAAANQADCgUIBQAAAA==.',
Go='Goam:BAAANQADCggIFwAAAA==.Gobiviji:BAAANQAECgYIBgAAAA==.Googrektar:BAAANQAECgQIBAABNQAFFAYIDAABADMQAA==.Goonielama:BAABNQAECn8qAAIRAAoKHCF/DgA7AwARAAoKHCF/DgA7AwABNQAFFAMIBwAQAJEgAA==.Goonietai:BAAANQAECgUICQABNQAFFAYIDAABADMQAA==.',
Gr='Greenterror:BAAANQADCgIIAgAAAA==.Grid:BAAANQAECgMIAwABNQAFFAUICQAdAKwPAA==.Griitz:BAAANQAECgQICAAAAA==.Grimmsheeper:BAACNQAFFH8LAAMBAAYKCRM/KgA5AQABAAUKNxQ/KgA5AQAfAAEKUQ4GEABPAAA1AAQKf0sAAwEACgr6JIEXAOACAAEACgr6JIEXAOACAB8AAgqWHVAjAK0AAAAA.Gryff:BAAANQADCgUJBQAAAA==.',
Gu='Guess:BAAANQAECgQIBAAAAA==.Gurtdk:BAACNQAFFH8kAAQIAAgK7hZIBADtAQAIAAYKwxpIBADtAQARAAEKAACZKABWAAAkAAEKyQPOGwBSAAA1AAQKfzYAAwgACgrwJTALAGEDAAgACgrwJTALAGEDACQAAgrEIc9wAMYAAAAA.',
Gy='Gyat:BAAANQADCgMJAwAAAA==.',
Ha='Hairynujabes:BAABNQAECn8WAAMLAAgK2w09ZQA4AQALAAcKSg09ZQA4AQAJAAIKtBC7agAvAAAAAA==.Hamandcheeze:BAAANQAECgIIAQAAAA==.Hanyuu:BAABNQAECn83AAISAAoKOA/zFgDeAQASAAoKOA/zFgDeAQAAAA==.',
He='Healviji:BAAANQAECgYIBwAAAA==.Heiter:BAABNQAECn8mAAIMAAkKCxg3QwBfAgAMAAkKCxg3QwBfAgABNQAECgoKLQAaAGgbAA==.Hellbound:BAABNQAECn9DAAMdAAoKIhpZRAD2AQAdAAoKqBhZRAD2AQAeAAIK/BMFVQB/AAAAAA==.Hellinhunt:BAACNQAFFH8MAAMCAAkKqQquFwD9AAATAAYKGQeWEgAWAQACAAMKkROuFwD9AAA1AAQKfxoAAxMACgrVIJgiAEIBAAIABwpjIQxlAOIBABMABwo8GpgiAEIBAAAA.',
Ho='Holyekko:BAAANQADCgEIAQAAAA==.Holypants:BAAANQADCgYIBgAAAA==.Honk:BAAANQAECgUIBQABNQAECgkJGgABAMwQAA==.Hornivore:BAAANQADCgcIFQABNQAECgoKQwACAKIZAA==.',
Hy='Hyrja:BAAANQADCgUIBgABNQAECgoKNAAfAOYWAA==.',
['Hâ']='Hâvyr:BAAANQAECgUICAAAAA==.',
Ic='Icefrosting:BAABNQAECn8iAAIBAAoK1BnsPwBAAgABAAoK1BnsPwBAAgABNQAECgoKJAASAIUdAA==.',
Id='Idistroya:BAAANQAECgUICAABNQAECgoKLwACAEUcAA==.',
Ig='Iggnogg:BAAANQAECgQIBwAAAA==.',
Ik='Ikura:BAACNQAFFH8SAAIMAAUKzBKxEgB3AQAMAAUKzBKxEgB3AQA1AAQKfy4ABBUACgpUFoAHAD8BAAwACgpAEdtmAOoBABUACApREIAHAD8BABIAAgrHCFRgADEAAAAA.',
Il='Ilithiya:BAABNQAECn8uAAIWAAoKSySjBACKAwAWAAoKSySjBACKAwAAAA==.Ilk:BAABNQAECn8gAAIFAAkK6QhPHgB8AQAFAAkK6QhPHgB8AQAAAA==.Illududu:BAAANQAECgcIBwABNQAECgoKIAAaAGMfAA==.',
Im='Imangry:BAAANQADCgEIAQAAAA==.',
Is='Isaidnoice:BAAANQADCgYICgAAAA==.Ishiftmyself:BAABNQAECn8WAAILAAoKWQ/7RgDRAQALAAoKWQ/7RgDRAQAAAA==.Ishton:BAACNQAFFH8IAAIOAAUK5AWjGgCsAAAOAAUK5AWjGgCsAAA1AAQKfy8AAg4ACgpHG0RJALkCAA4ACgpHG0RJALkCAAAA.Istompgnomes:BAABNQAECn8VAAIaAAcKYBcBdgC/AQAaAAcKYBcBdgC/AQAAAA==.',
It='Itsnowz:BAAANQADCgQIBAAAAA==.',
Ja='Jacobean:BAAANQADCgQIBAAAAA==.Jasøn:BAAANQADCgcIDgABNQAECgkJIAACAIcMAA==.',
Je='Jecthyr:BAABNQAECn84AAQPAAoKTRm9FgBMAgAPAAoKTRm9FgBMAgAUAAgK6xReCwCWAQAlAAEKjAQNHgAkAAAAAA==.Jefeson:BAAANQAECgYICQAAAA==.Jemhdar:BAAANQAECgEIAQAAAA==.Jermdaga:BAAANQADCgQIBAAAAA==.',
Ji='Jinnasaiquoi:BAABNQAECn8eAAMOAAkKbhkgSABCAgAOAAkKixggSABCAgAbAAQKTRSUQQDwAAAAAA==.Jinnasasquoi:BAAANQAECggICAAAAA==.',
Js='Jsdruid:BAAANQAECgcIDAAAAA==.',
Ka='Kaelosu:BAABNQAECn8xAAIdAAkK3BwALwDKAgAdAAkK3BwALwDKAgAAAA==.Kakum:BAABNQAECn8eAAMZAAoKQR2FDABXAwAZAAoKQR2FDABXAwAOAAEKAABGxQEAAAAAAA==.Kaldrogo:BAAANQAECgcIBQAAAA==.Kalnuggets:BAAANQAECgcIBgAAAA==.Kalrathen:BAABNQAECn83AAMMAAoKJxqmOwB7AgAMAAoKJxqmOwB7AgASAAEKewFQkgAXAAAAAA==.Kanda:BAABNQAECn84AAICAAoKaBrNOwC3AgACAAoKaBrNOwC3AgAAAA==.Karsh:BAABNQAECn8bAAMNAAoK7ARoGAAZAQANAAgKJwVoGAAZAQAEAAQKWwTi9AB3AAAAAA==.Kazadax:BAABNQAECn8nAAIdAAoKdg+1gQDiAQAdAAoKdg+1gQDiAQAAAA==.',
Ke='Kealosu:BAAANQADCggIDgAAAA==.Keen:BAAANQAECgEIAQAAAA==.Keuaakepo:BAABNQAECn8vAAICAAoKRRwzMwDSAgACAAoKRRwzMwDSAgAAAA==.',
Ki='Kienne:BAABNQAECn8uAAICAAoKxBfoWgD8AQACAAoKxBfoWgD8AQAAAA==.Kiljaedra:BAAANQAECgEIAgABNQAECgoKNAAfAOYWAA==.Kinomi:BAAANQADCgYIBgABNQAECgoKFgALAFkPAA==.Kitenna:BAAANQAECggICgAAAA==.',
Kl='Kleenex:BAAANQADCgEIAQAAAA==.',
Ko='Korbanhavoc:BAABNQAECn8XAAIOAAcK4hHMxgCOAQAOAAcK4hHMxgCOAQAAAA==.Korogar:BAAANQAECgUIDQAAAA==.',
Kp='Kpes:BAAANQADCgUJBQAAAA==.',
Kr='Kreamyumyums:BAAANQAECggICwAAAA==.Krisp:BAAANQADCgUICAAAAA==.Krizzl:BAAANQADCgUIBQABNQAFFAcIGwAIAMwgAA==.Kronknar:BAAANQABCgQJBAABNQAECgoKLwAaABEdAA==.Krìzzl:BAABNQAECn8dAAIDAAoKzxV+KABOAgADAAoKzxV+KABOAgABNQAFFAcIGwAIAMwgAA==.',
Ky='Kymira:BAABNQAECn83AAIQAAoKOBpVBwDIAgAQAAoKOBpVBwDIAgAAAA==.',
La='Lace:BAACNQAFFH8JAAQdAAUKrA9rKQB1AAAdAAQKfw1rKQB1AAAHAAEKvwaCFQBFAAAeAAEKFg4oEwBEAAA1AAQKf2wABB0ACgrgJLAJAH8DAB0ACgrSIrAJAH8DAAcABQrbH5AIALoBAB4AAgrzJGARAMEAAAAA.Lanzen:BAAANQADCgEIAQAAAA==.Larrfena:BAABNQAECn9DAAICAAoKohnnSgAlAgACAAoKohnnSgAlAgAAAA==.Lavatory:BAAANQADCgMIBgAAAA==.Lazarou:BAAANQAECgUIBgAAAA==.',
Le='Legsday:BAAANQAECgIIAwAAAA==.Lementz:BAACNQAFFH8OAAIaAAQKVhHPEgBDAQAaAAQKVhHPEgBDAQA1AAQKfyAAAhoACQp4HjEhAAUDABoACQp4HjEhAAUDAAAA.',
Li='Liadres:BAAANQADCgIIAgAAAA==.Liante:BAAANQADCgcIEgABNQAECgUIEgAGAAAAAA==.Libellule:BAAANQABCgQIBAAAAA==.Lilboat:BAAANQAECgEIAQAAAA==.Lillia:BAABNQAECn9FAAIdAAoKvhPePQAMAgAdAAoKvhPePQAMAgAAAA==.Lillybell:BAAANQADCgUIBQAAAA==.Littleboyz:BAAANQADCgcIBwAAAA==.',
Lo='Loop:BAACNQAFFH8IAAIEAAgKagFfJwCAAAAEAAgKagFfJwCAAAA1AAQKfxkAAgQACgoWHpUoAJICAAQACgoWHpUoAJICAAAA.Loopku:BAAANQAECggICwAAAA==.Lorinash:BAAANQADCgYICQAAAA==.Lothelo:BAAANQAECgEIAgABNQAECgoKHgAOAH0bAA==.',
Lu='Lumpia:BAACNQAFFH8KAAMIAAUKYRIGBwDjAAAIAAQKYRIGBwDjAAARAAEKAAASNgAAAAA1AAQKfzAAAwgACgrkHCEvAHQCAAgACgrkHCEvAHQCABEABgpYB6lkAKkAAAAA.',
Lv='Lvel:BAAANQADCgYICgAAAA==.',
['Lë']='Lëeloo:BAAANQAECgcICQABNQAECggIEgAGAAAAAA==.',
Ma='Machinism:BAAANQADCgIIAgABNQADCgcJCAAGAAAAAA==.Maey:BAABNQAECn83AAMBAAoK2xaAjQBkAgABAAoKQBSAjQBkAgAfAAEKASHLOwBQAAAAAA==.Magoobers:BAAANQADCgEIAQAAAA==.Maktah:BAABNQAECn8vAAMaAAoKER0ELwDAAgAaAAoKER0ELwDAAgAFAAEK/AiiNAA+AAAAAA==.Malpractice:BAAANQAECggICgABNQAECgoKFgALAFkPAA==.Maybesinged:BAABNQAECn9GAAIBAAoK4B3cKgCIAgABAAoK4B3cKgCIAgAAAA==.',
Me='Meanboy:BAAANQAECgMIAwAAAA==.Meishra:BAAANQADCgcICQAAAA==.Mentos:BAABNQAECn8+AAQUAAoK8h+HBQA5AwAUAAoK8h+HBQA5AwAPAAIK4xQSQQCYAAAlAAEKCRNJIwA5AAAAAA==.',
Mi='Miltank:BAACNQAFFH8HAAIOAAIKCRhtHwCSAAAOAAIKCRhtHwCSAAA1AAQKf0kAAg4ACgp1JFsJAE4DAA4ACgp1JFsJAE4DAAAA.Minaqt:BAAANQADCgEIAQAAAA==.Minatory:BAABNQAECn8kAAIWAAoKqRlvGACZAgAWAAoKqRlvGACZAgAAAA==.Mionn:BAABNQAECn8xAAMOAAoK/h8KNwB6AgAOAAoK/h8KNwB6AgAZAAEK7gokHwE3AAAAAA==.Misfires:BAAANQABCggIEwAAAA==.',
Ml='Mlleena:BAABNQAECn8fAAIeAAcKLRGAGQCgAQAeAAcKLRGAGQCgAQAAAA==.',
Mo='Moddim:BAAANQADCgUIBQAAAA==.Mogg:BAAANQAECgEIAQAAAA==.Moghoul:BAAANQAECgQIBQAAAA==.Monandwah:BAAANQADCgcIDAAAAA==.Montorgo:BAAANQADCgYIBgAAAA==.Moofi:BAAANQADCggIEQABNQAECggIHgAFADgLAA==.Mooncake:BAABNQAECn8fAAMUAAkKIQdqGgCiAQAUAAkKIQdqGgCiAQAlAAIKhAJWIgBBAAAAAA==.Moonless:BAAANQAECgEIAQABNQAECgoKRwABANMaAA==.Moosiah:BAAANQADCgcIBwAAAA==.Mossfire:BAAANQAECgIIAgABNQAECgkJJgANAFwaAA==.Motoko:BAABNQAECn8gAAMQAAoKvRk/CgByAgAQAAoKvRk/CgByAgAmAAIK3AQBPQAsAAAAAA==.',
Mu='Musesong:BAAANQADCgMIAwAAAA==.',
['Mø']='Møø:BAAANQAECgYICwABNQAECgkJIAACAIcMAA==.Møøfi:BAABNQAECn8eAAIFAAgKOAv1GgBNAQAFAAgKOAv1GgBNAQAAAA==.',
Na='Naianasha:BAABNQAECn8mAAMMAAoKhBqlJwCcAgAMAAoKhBqlJwCcAgAVAAIKqRRsJABIAAAAAA==.Nameless:BAABNQAECn9HAAIBAAoK0xpwLwB3AgABAAoK0xpwLwB3AgAAAA==.Narc:BAABNQAECn8YAAILAAYKUgX3XwCSAAALAAYKUgX3XwCSAAAAAA==.',
Ne='Necroraise:BAAANQADCgIIAgAAAA==.Neeraj:BAABNQAECn8rAAICAAoKqBW3SgAmAgACAAoKqBW3SgAmAgAAAA==.Nevergreen:BAAANQABCgIIAgAAAA==.',
Ni='Nightreaver:BAAANQAECgUIBAABNQAECgoKGwAQAIMhAA==.Nikwillig:BAAANQAECgYICgAAAA==.',
No='Nokzash:BAABNQAECn8kAAIZAAoKsx5HKQDDAgAZAAoKsx5HKQDDAgAAAA==.Noova:BAABNQAECn84AAIBAAoKQh/6SQDuAgABAAoKQh/6SQDuAgAAAA==.',
Ny='Nyang:BAAANQAECgYIDQAAAA==.Nythendrac:BAAANQADCgQIBAABNQAECgoKNAAfAOYWAA==.',
Ob='Obliverat:BAAANQAECggIEgAAAA==.',
Od='Odysseus:BAAANQADCgIIBAAAAA==.',
Oo='Oongaboonga:BAABNQAECn8xAAIEAAgKkh9PSwCnAgAEAAgKkh9PSwCnAgAAAA==.',
Or='Orcaneblast:BAACNQAFFH8MAAIBAAYKMxBxGQAQAQABAAYKMxBxGQAQAQA1AAQKfzwAAwEACgpPILlJAO8CAAEACgpPILlJAO8CACAABwrRF5oCALEBAAAA.Orcsoup:BAABNQAECn8WAAIaAAcKpxtUVgAhAgAaAAcKpxtUVgAhAgABNQAECgoKPQAKAFAdAA==.',
Pa='Paddord:BAAANQADCggICgAAAA==.Paranoià:BAAANQADCgIIAgABNQAECgEIAQAGAAAAAA==.',
Pe='Peewpewpew:BAAANQADCgYIBgAAAA==.Penance:BAAANQAECgcICwAAAA==.Percible:BAAANQAECgIIAgAAAA==.',
Ph='Phoenixphyre:BAAANQADCgMIAwAAAA==.',
Pi='Pivnert:BAABNQAECn8xAAQBAAkKRhqFWgD1AQABAAkKmBiFWgD1AQAfAAIKbBi8LQCPAAAgAAQKhhPABwCFAAAAAA==.',
Pl='Plums:BAAANQAECggICQAAAA==.',
Po='Popdkook:BAAANQADCgYIEgAAAA==.',
Pr='Proko:BAAANQADCggICAAAAA==.',
Ps='Psychopump:BAAANQAECgYIDgAAAA==.',
['Pü']='Pünish:BAACNQAFFH8MAAIIAAUKRhyhDABDAQAIAAUKRhyhDABDAQA1AAQKf2EABAgACgoJJP0GAI4DAAgACgoJJP0GAI4DACQAAwpxFcR7ALgAABEAAQpfBRvSACsAAAAA.',
Qq='Qqpewpew:BAAANQAECggIBAAAAA==.',
Qu='Quinn:BAAANQADCgIJAgABNQAECgoKGwAQAIMhAA==.',
Ra='Rabit:BAAANQADCgUIBQAAAA==.Raelina:BAABNQAECn8lAAMBAAkKhSHdTADnAgABAAkKsx/dTADnAgAfAAIKoCISJwC6AAABNQAFFAkJNwABAFEiAA==.Ragingiscool:BAAANQADCggIDwAAAA==.Rail:BAAANQAECgEIAQAAAA==.Rajank:BAAANQADCgQIBAAAAA==.Rallek:BAABNQAECn8gAAIZAAoKjRB4bADSAQAZAAoKjRB4bADSAQAAAA==.Ranuggul:BAAANQAECgIIAQAAAA==.Rarn:BAAANQADCgMIAwABNQAECgoKOgARAIgeAA==.Ratsrepus:BAAANQADCgcICwAAAA==.Raza:BAAANQAECgQIDAABNQAFFAUIDAAIAEYcAA==.',
Re='Read:BAABNQAECn8cAAILAAcK8RAzOwAtAQALAAcK8RAzOwAtAQAAAA==.Reddawn:BAAANQADCgcIBwAAAA==.Remeras:BAABNQAECn8WAAIOAAoKKhGrlQD4AQAOAAoKKhGrlQD4AQAAAA==.',
Ri='Riken:BAABNQAECn8UAAImAAcKvQ3qJABUAQAmAAcKvQ3qJABUAQAAAA==.Ripblast:BAAANQAECgUIBgABNQAECgoKGwAQAIMhAA==.Ritual:BAABNQAECn85AAIYAAoKzRsIGgDTAgAYAAoKzRsIGgDTAgAAAA==.',
Ro='Roadi:BAAANQAECggIEgAAAA==.Roxer:BAACNQAFFH8FAAIZAAEKCwlxKAA5AAAZAAEKCwlxKAA5AAA1AAQKfygAAhkACgrzERhRACcCABkACgrzERhRACcCAAAA.',
Ru='Rukaa:BAAANQAECgIIAwAAAA==.Rummyy:BAACNQAFFH8GAAIWAAIK7CBvCQDAAAAWAAIK7CBvCQDAAAA1AAQKfycAAxYACgp4HoUQAEICABYACgp4HoUQAEICABcAAQqTDBWPADwAAAAA.',
Ry='Rycken:BAABNQAECn89AAMKAAoKaA7ZKQDQAQAKAAoKaA7ZKQDQAQALAAgKWxjHKQCcAQAAAA==.',
Sa='Saeylva:BAAANQAECggIDwAAAA==.Saosis:BAAANQAECgYIBgAAAA==.Savage:BAAANQADCgIIAgAAAA==.Sayurri:BAAANQADCgEJAQAAAA==.',
Sc='Scribble:BAAANQAECgQICAAAAA==.Sculper:BAABNQAECn8XAAInAAcK6hFBDQB2AQAnAAcK6hFBDQB2AQAAAA==.',
Se='Senica:BAABNQAECn8yAAIMAAoKASMrBQDTAwAMAAoKASMrBQDTAwAAAA==.Seriphina:BAAANQADCggICAAAAA==.',
Sg='Sgornyweaver:BAAANQADCgUJBQAAAA==.',
Sh='Shabbarankzz:BAABNQAECn8+AAIkAAoKvxWrNQADAgAkAAoKvxWrNQADAgAAAA==.Shadetotem:BAABNQAECn8jAAIFAAgKBhDPGQBeAQAFAAgKBhDPGQBeAQAAAA==.Shammyblammy:BAAANQABCgEIAQAAAA==.Sheshotu:BAAANQADCggIFwAAAA==.Shiftor:BAAANQADCggIEgAAAA==.Shinedown:BAAANQADCgMIAwAAAA==.Shmoopy:BAAANQAECgMIAgAAAA==.Shradehn:BAABNQAECn8iAAIXAAoKTBV6JQDKAQAXAAoKTBV6JQDKAQAAAA==.Shutitdown:BAAANQAECgUIBQAAAA==.',
Si='Sindracosa:BAAANQAECgEIAQABNQAECgoKNAAfAOYWAA==.Sisterswede:BAABNQAECn8dAAISAAkK/h1LEwDPAgASAAkK/h1LEwDPAgAAAA==.Sixfingers:BAAANQADCgQIBAAAAA==.Sizzle:BAABNQAECn8aAAIBAAkKzBBAowA7AgABAAkKzBBAowA7AgAAAA==.',
Sm='Smokeahontas:BAABNQAECn8lAAIaAAoKfBCFSACcAQAaAAoKfBCFSACcAQAAAA==.Smokindots:BAAANQAECgcIEgABNQAFFAYIEAAYABYVAA==.Smokingreen:BAAANQADCggICAABNQAFFAYIEAAYABYVAA==.Smokinice:BAAANQADCggICwABNQAFFAYIEAAYABYVAA==.Smokinloud:BAAANQADCgIIAgAAAA==.Smokinmyrrh:BAAANQAECgUIBQABNQAFFAYIEAAYABYVAA==.Smokinmyth:BAAANQADCgcICAAAAA==.Smokinpsalm:BAABNQAECn8XAAIMAAgKzQ+NgQCTAQAMAAgKzQ+NgQCTAQABNQAFFAYIEAAYABYVAA==.Smokintotem:BAACNQAFFH8QAAIYAAYKFhULDgBcAQAYAAYKFhULDgBcAQA1AAQKf0kAAxgACgo0I4MMAFwDABgACgo0I4MMAFwDABoABgqBGllsANsBAAAA.',
Sn='Snawkin:BAAANQADCgEIAQAAAA==.',
Sp='Spaghet:BAEBNQAECn8fAAIaAAkKnh77FQCuAgAaAAkKnh77FQCuAgABNQAFFAcIDQAEAMAPAA==.Sparklnmagic:BAAANQAECgIIAgAAAA==.Spore:BAAANQADCgIIAgAAAA==.',
Sq='Squigboogalo:BAAANQADCgEIAQAAAA==.',
St='Steadyrock:BAABNQAECn8ZAAMLAAoK7xRCNwAzAgALAAoK7xRCNwAzAgAKAAEK8QR4eAAuAAAAAA==.Stemi:BAAANQAECgEIAQAAAA==.Steveirwin:BAAANQADCggJCAAAAA==.Stiffsheets:BAAANQAECgUIBAABNQAECgoKGwAQAIMhAA==.Stiltz:BAAANQADCgEIAQAAAA==.Stormywind:BAABNQAECn8dAAIaAAkKnQhojQCCAQAaAAkKnQhojQCCAQAAAA==.Stormz:BAABNQAECn9DAAILAAoKlxSxIADkAQALAAoKlxSxIADkAQAAAA==.',
Su='Sunblade:BAABNQAECn8YAAIRAAcKGhVyWwCFAQARAAcKGhVyWwCFAQABNQAECgoKRwABANMaAA==.Sundayskoolz:BAAANQADCgUIBQAAAA==.Sundowning:BAAANQAECgcIDAAAAA==.Sunreaver:BAABNQAECn8cAAIZAAoKbxG8QAD+AQAZAAoKbxG8QAD+AQAAAA==.Supercappy:BAAANQAECgIIBQAAAA==.Suraegi:BAAANQAECgIIAgAAAA==.',
Sw='Swabby:BAAANQADCgEIAQAAAA==.Swiftdragon:BAABNQAECn8bAAMQAAoKgyHGBAAlAwAQAAkK6SPGBAAlAwAcAAIK2RPxRgB3AAAAAA==.',
Ta='Taapfer:BAAANQAECgMIAwABNQAECgoKJgABAKQVAA==.Tackyh:BAABNQAECn83AAICAAgKwxxVYwDmAQACAAgKwxxVYwDmAQAAAA==.Takamatsu:BAABNQAECn9AAAMMAAoKVSRnFgAgAwAMAAoKVSRnFgAgAwAVAAMKDA6LGgCWAAAAAA==.Taku:BAAANQAECgQICAAAAA==.Tanktoucher:BAAANQAECggIAQAAAA==.Tar:BAABNQAECn8gAAMCAAkKhwzOuwCMAQACAAgK2gzOuwCMAQATAAMKFAiGZACZAAAAAA==.Taxii:BAABNQAECn85AAMEAAoKHCbNJQAiAwAEAAoKgCPNJQAiAwANAAkKGCbpBgCRAgAAAA==.Taxilan:BAAANQAECgQIAwABNQAECgoKOQAEABwmAA==.',
Te='Tealnujabes:BAAANQAECgYIBwAAAA==.Teapots:BAACNQAFFH8KAAIFAAUKChq5AgAAAQAFAAUKChq5AgAAAQA1AAQKfxUAAgUABQrnI5MYAHABAAUABQrnI5MYAHABAAAA.Tempi:BAAANQABCgMIAwABNQAECgYIBgAGAAAAAA==.Tenpiece:BAAANQADCgMIAwAAAA==.',
Th='Thayelith:BAAANQAECgUIBAAAAA==.Thedeus:BAABNQAECn8eAAIOAAoKfRv8UwCZAgAOAAoKfRv8UwCZAgAAAA==.Thellira:BAAANQADCgEIAQAAAA==.Thermaul:BAABNQAECn9AAAIFAAoKQxw1CgBqAgAFAAoKQxw1CgBqAgAAAA==.Threebeans:BAABNQAECn89AAMKAAoKUB0GDQD+AgAKAAoKUB0GDQD+AgALAAcK9BHwRgDSAQAAAA==.Thromir:BAACNQAFFH8IAAMOAAUKUB68EQA0AQAOAAQK8CC8EQA0AQAZAAMKyA8rGADjAAA1AAQKfzYAAw4ACgrAJf4KAEQDAA4ACgrAJf4KAEQDABkACQoEIDQXAB8DAAAA.Thyrn:BAABNQAECn86AAIRAAoKiB5LFABgAgARAAoKiB5LFABgAgAAAA==.',
Ti='Tirare:BAABNQAECn8pAAIIAAoKlBhJNABZAgAIAAoKlBhJNABZAgAAAA==.',
Tr='Tri:BAABNQAECn82AAIOAAoKCSBOKgCrAgAOAAoKCSBOKgCrAgAAAA==.Tristam:BAAANQAECgEIAQAAAA==.',
Tu='Tuneleitor:BAABNQAECn8sAAIoAAoKzRI0BAAxAgAoAAoKzRI0BAAxAgAAAA==.Turdferguson:BAAANQAECgQIAwABNQAFFAMIBwAQAJEgAA==.Turgrok:BAABNQAECn8oAAMCAAoKzBBsVQAKAgACAAkKzBBsVQAKAgATAAgKUAuoNACoAQAAAA==.',
Tw='Twothang:BAABNQAECn8UAAMRAAgKOAiyagBJAQARAAgKoweyagBJAQAkAAIKMwWlnwBRAAAAAA==.',
Ty='Tyllan:BAABNQAECn9WAAMBAAoK2B8YRgAtAgABAAkKyR0YRgAtAgAfAAMKBh61GAABAQAAAA==.',
['Tâ']='Tâku:BAAANQAECgYICAAAAA==.',
Up='Upgrayedd:BAABNQAECn8ZAAMZAAYKiQYgmgDdAAAZAAYKiQYgmgDdAAAOAAEKAAD+4AEPAAAAAA==.',
Ur='Urugargo:BAAANQABCgYIBgAAAA==.',
Va='Vainhellsing:BAABNQAECn8nAAIXAAgKrwYaSAD0AAAXAAgKrwYaSAD0AAAAAA==.Vanzier:BAABNQAECn8XAAICAAoKpRWHagA+AgACAAoKpRWHagA+AgAAAA==.Vaxis:BAABNQAECn8kAAICAAoKOQ/uggAGAgACAAoKOQ/uggAGAgAAAA==.',
Vi='Vid:BAACNQAFFH8RAAImAAcKQxThAgDmAQAmAAcKQxThAgDmAQA1AAQKfzQAAiYACgpQICMJAPkCACYACgpQICMJAPkCAAAA.',
Vo='Voidillusion:BAAANQAECgMIAwABNQAECgoKIAAaAGMfAA==.Voldoom:BAAANQAECgIIAwAAAA==.',
Wa='Watooie:BAAANQADCgYIBgAAAA==.',
We='Weave:BAAANQABCgIIAgABNQAFFAUICQAdAKwPAA==.Wernov:BAABNQAECn8tAAMaAAoKaBuCMgCwAgAaAAoKaBuCMgCwAgAYAAUK5BA2rAAYAQAAAA==.',
Wh='Whitetail:BAAANQAECgMIAgAAAA==.',
Wi='Wichan:BAABNQAECn87AAIJAAoKexxFDgBAAgAJAAoKexxFDgBAAgAAAA==.Wildsniper:BAAANQABCgIIAgAAAA==.Wildstrike:BAAANQADCgYIBgABNQAECgoKIAAQAL0ZAA==.Wiziviji:BAABNQAECn8mAAIBAAoKLAmgoQBPAQABAAoKLAmgoQBPAQAAAA==.',
Wo='Woodrow:BAAANQADCgcIBwAAAA==.',
Ws='Ws:BAAANQAECgIIAgAAAA==.',
Xa='Xanorea:BAAANQADCgYIBgABNQAECgcIFwAUAO0QAA==.',
Xd='Xdknight:BAAANQABCgIIAwAAAA==.',
Xe='Xerø:BAAANQAECggIDwAAAA==.',
Xr='Xray:BAABNQAECn8jAAMBAAoK9w2vvgAHAgABAAoK9w2vvgAHAgAfAAEKwgmvOwA3AAAAAA==.',
Xt='Xtra:BAAANQAECgMIAwAAAA==.Xtreme:BAAANQAECgIIAQAAAA==.',
Ya='Yamii:BAABNQAECn8uAAMjAAoK2hvbCQAcAgAjAAkKkhzbCQAcAgAEAAgKDhODlABCAQABNQAFFAUICgAIAGESAA==.Yaphetkotto:BAAANQADCgcJCAAAAA==.Yawnk:BAABNQAECn8ZAAMmAAkKAQxVIgDnAAAmAAcKKw5VIgDnAAAcAAYKLw2yPACvAAAAAA==.',
Yu='Yunsky:BAAANQAECgUICwAAAA==.',
Za='Zanber:BAAANQADCgIIAgAAAA==.Zandrakar:BAABNQAECn8+AAQYAAoK0xgzOgB2AgAYAAoK0xgzOgB2AgAFAAEKAACDOAAtAAAaAAEKPQViSQEpAAAAAA==.Zanosuke:BAAANQAECggIEgAAAA==.Zaria:BAABNQAECn8iAAIdAAoKWRCVcgAJAgAdAAoKWRCVcgAJAgAAAA==.Zaryor:BAABNQAECn8WAAMcAAcKIRTjMgB/AQAcAAcKIRTjMgB/AQAQAAQKYhIiIADkAAAAAA==.Zaun:BAAANQAECgUIBQAAAA==.',
Ze='Zentul:BAAANQAECgQIBAAAAA==.Zerica:BAAANQAECgIIAgAAAA==.Zerika:BAACNQAFFH8KAAIMAAUKVgnIFABJAQAMAAUKVgnIFABJAQA1AAQKfzkAAgwACgobI5EPAEkDAAwACgobI5EPAEkDAAAA.',
Zh='Zhaohu:BAAANQADCgYIBgAAAA==.',
Zi='Zigzwag:BAAANQAECgIIBgAAAA==.Zionna:BAAANQAECgYIEQABNQAECgoKFgALAFkPAA==.Zitos:BAABNQAECn9FAAMOAAoKYCQ+BgDIAwAOAAoKYCQ+BgDIAwAZAAEKfghNKgEsAAABNQAECgoKRQAOAGAkAA==.',
Zo='Zomgqq:BAABNQAECn8kAAMFAAoKMhw/CwC9AgAFAAoKMhw/CwC9AgAYAAQK7Q0X0gDDAAAAAA==.',
Zw='Zwagster:BAAANQAECgcIEgAAAA==.',
Zy='Zydis:BAAANQAECgYICgAAAA==.Zyggy:BAABNQAECn8iAAIRAAkKFxW7IADlAQARAAkKFxW7IADlAQAAAA==.Zynfanatic:BAAANQAECgcIDAABNQAECgoKPQAKAFAdAA==.',
['Än']='Ännihilation:BAAANQAECgIIAgAAAA==.',
['Èe']='Èepy:BAAANQAECgEIAQABNQAECgUIBAAGAAAAAA==.',
['És']='Éstéla:BAABNQAECn81AAICAAoKaxZVWABqAgACAAoKaxZVWABqAgAAAA==.',
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
