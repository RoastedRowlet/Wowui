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

local lookup = {'Mage-Arcane','Hunter-BeastMastery','Rogue-Subtlety','Warrior-Arms','Shaman-Enhancement','Unknown-Unknown','Warlock-Affliction','DeathKnight-Unholy','Druid-Guardian','Druid-Restoration','Druid-Balance','Priest-Holy','Warrior-Fury','Paladin-Retribution','Evoker-Devastation','Monk-Brewmaster','DeathKnight-Blood','Priest-Shadow','Hunter-Marksmanship','Evoker-Preservation','Priest-Discipline','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Restoration','Paladin-Holy','Shaman-Elemental','Paladin-Protection','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Mage-Fire','DemonHunter-Vengeance','Druid-Feral','Warrior-Protection','DeathKnight-Frost','Evoker-Augmentation','Monk-Mistweaver','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abobadrin:BAAANQADCgcIDgAAAA==.Abrakadaver:BAABNQAECn8mAAIBAAoKpBXesAAhAgABAAoKpBXesAAhAgAAAA==.',
Ac='Acceb:BAAANQADCgQJBAAAAA==.',
Ad='Adventureux:BAACNQAFFH8KAAICAAUK9BOSFQDkAAACAAUK9BOSFQDkAAA1AAQKfzIAAgIACgppGno8ALQCAAIACgppGno8ALQCAAAA.',
Ae='Aedx:BAABNQAECn8oAAIDAAkKIxWrEgBZAgADAAkKIxWrEgBZAgAAAA==.Aerolorea:BAAANQADCgYICQAAAA==.',
Ai='Aiblul:BAAANQAECgQIBAAAAA==.',
Al='Alastar:BAABNQAECn8ZAAIEAAgK6h72XAB1AgAEAAgK6h72XAB1AgABNQAFFAUICgAFAAoaAA==.Alexmage:BAAANQADCgYIBgABNQADCgcIBwAGAAAAAA==.Alios:BAAANQAECgQIBAAAAA==.Alphasalt:BAAANQADCgcIBwABNQAECgYIFgAHADAYAA==.Alucard:BAAANQAECgYIDwAAAA==.Alunadoom:BAABNQAECn8wAAICAAoKAwdCvgA1AQACAAoKAwdCvgA1AQAAAA==.Alvera:BAACNQAFFH8KAAIIAAQK6BdICwBZAQAIAAQK6BdICwBZAQA1AAQKfz0AAggACgpCJY0HAIgDAAgACgpCJY0HAIgDAAAA.',
Am='Ambellìna:BAAANQADCgIIAgABNQAECgEIAQAGAAAAAA==.',
An='Angechi:BAEANQADCgIJAgABNQAECgoKJgAJANMWAA==.Angrydk:BAAANQAECgUIEgAAAA==.Annoying:BAAANQAECgUICwAAAA==.Antisocial:BAABNQAECn8uAAIIAAoKziAuEgAmAwAIAAoKziAuEgAmAwABNQAECgoKLgAIAM4gAA==.',
Ar='Arm:BAABNQAECn9cAAQKAAoKJB3BDQDuAgAKAAoKJB3BDQDuAgALAAYKVw+MZgAzAQAJAAQKzA7yWwBcAAAAAA==.Armee:BAABNQAECn8iAAIMAAoKIRqpVwAbAgAMAAoKIRqpVwAbAgAAAA==.Armz:BAAANQABCgEIAQAAAA==.',
As='Astrael:BAACNQAFFH8HAAIBAAUK0ApVKwDJAAABAAUK0ApVKwDJAAA1AAQKfxoAAgEACQqYGKS2ABYCAAEACQqYGKS2ABYCAAAA.Aszea:BAABNQAECn8UAAILAAUK9w0nVQDKAAALAAUK9w0nVQDKAAAAAA==.',
At='Attewode:BAAANQAECgEIAQAAAA==.',
Ax='Axas:BAAANQADCgcICwAAAA==.Axra:BAABNQAECn8pAAINAAoK0A8kDQDmAQANAAoK0A8kDQDmAQAAAA==.',
Ay='Ayda:BAAANQADCgIIAQAAAA==.',
Az='Azairius:BAAANQADCggIGAAAAA==.Azzman:BAAANQADCgMIAwAAAA==.Azóg:BAABNQAECn8xAAIIAAoKBxZeFwAxAgAIAAoKBxZeFwAxAgAAAA==.',
Ba='Balsin:BAABNQAECn8uAAIOAAoKuiP4EwB2AwAOAAoKuiP4EwB2AwAAAA==.Bambii:BAAANQADCgUIBwAAAA==.Bangungot:BAAANQAECgUIBgABNQAFFAkJIwAPADUhAA==.Barlaf:BAABNQAECn9PAAICAAoKWB7kNgDGAgACAAoKWB7kNgDGAgABNQAECgMIAwAGAAAAAA==.Batou:BAAANQAECgUICAAAAA==.',
Be='Beeski:BAAANQADCggIHQAAAA==.Beeto:BAACNQAFFH8YAAIOAAYKBRXdCgA6AQAOAAYKBRXdCgA6AQA1AAQKfzQAAg4ACgp+GVNjAAsCAA4ACgp+GVNjAAsCAAAA.Bellflower:BAAANQAECgQIAwABNQAECgoKGwAQAIMhAA==.Belyndris:BAABNQAECn8oAAIMAAoK1RldRABaAgAMAAoK1RldRABaAgAAAA==.Benbear:BAEBNQAECn8mAAIJAAoK0xbNEgANAgAJAAoK0xbNEgANAgAAAA==.Benlian:BAEBNQAECn8uAAIRAAkKEBM+OwBUAQARAAkKEBM+OwBUAQABNQAECgoKJgAJANMWAA==.',
Bi='Bishtease:BAAANQAECgMIAwABNQAECgoKRQACAKIZAA==.',
Bl='Blighty:BAAANQAECgcIDQAAAA==.Bloran:BAAANQADCgIIAgAAAA==.Blâze:BAACNQAFFH8bAAIBAAcKiR1YDQCoAQABAAcKiR1YDQCoAQA1AAQKfzAAAgEACgoII6cbANQCAAEACgoII6cbANQCAAAA.',
Bo='Bombardi:BAAANQAECgMIAwAAAA==.Bonknsmash:BAABNQAECn8fAAIEAAgKJhTYjQD6AQAEAAgKJhTYjQD6AQAAAA==.Boof:BAABNQAECn8nAAMSAAoKrRUQHQBaAgASAAkKjBUQHQBaAgAMAAEKvCAE5ABUAAAAAA==.Boregut:BAAANQAECggICAAAAA==.',
Br='Brewdock:BAAANQABCgIIAgAAAA==.Bronxor:BAABNQAECn8vAAMTAAoK2xaYIQBAAgATAAoKMhaYIQBAAgACAAEKhxcmOAFNAAAAAA==.',
Bu='Bubbleoshift:BAAANQAECgcICAABNQAECgoKFgALAFkPAA==.Bushgarden:BAAANQADCgYIBwABNQADCgYICgAGAAAAAA==.Buzsmash:BAAANQAECgYIBgAAAA==.Buzzbuzz:BAAANQAECgMIBQABNQAECgkJGgABAMwQAA==.',
['Bó']='Bóba:BAACNQAFFH8gAAIUAAkKwiKlAQC8AgAUAAkKwiKlAQC8AgA1AAQKfzIAAxQACgruI+QFAEwDABQACgruI+QFAEwDAA8ABgoaI4cJAOABAAAA.',
['Bö']='Böba:BAABNQAECn8eAAQMAAkKkCQ+DABhAwAMAAkKkCQ+DABhAwAVAAkK0yBpBgAnAgASAAEKAABOeQA1AAABNQAFFAkJIAAUAMIiAA==.',
Ca='Cadroyd:BAABNQAECn89AAQKAAoK+R5ZBwBpAwAKAAoK+R5ZBwBpAwALAAQKHA7PXQCqAAAJAAEKAADPjQAAAAAAAA==.Caelin:BAACNQAFFH8KAAMWAAQKUgZSCwCmAAAWAAQKKQRSCwCmAAAXAAEKZgiSHAA8AAA1AAQKf1YAAxcACgpTE9c1AAACABcACQpTE9c1AAACABYACApqDkAoAFcBAAAA.Cailand:BAABNQAECn8uAAIEAAoKmxXYYQDaAQAEAAoKmxXYYQDaAQAAAA==.Caishana:BAABNQAECn9EAAIYAAoKmiOLBwChAwAYAAoKmiOLBwChAwAAAA==.Cambium:BAAANQAECgYIEQAAAA==.Camerbunne:BAAANQADCgYIEQAAAA==.Caramel:BAAANQAECgMIBQAAAA==.Catdude:BAAANQAECgUICwAAAA==.',
Ce='Cecil:BAAANQADCgYIBgAAAA==.Celebrate:BAAANQADCgMIAwAAAA==.',
Ch='Chaddingus:BAAANQAECggIEAAAAA==.Chopadk:BAABNQAECn8hAAIRAAkKsA8YUwCoAQARAAkKsA8YUwCoAQAAAA==.',
Cl='Clash:BAAANQADCgYIDgAAAA==.Clique:BAABNQAECn8uAAIZAAkKbRy7NwCFAgAZAAkKbRy7NwCFAgAAAA==.',
Cn='Cnc:BAAANQAECgEIAQAAAA==.',
Co='Coheedkil:BAAANQAECgEIAQAAAA==.Coldbreeze:BAABNQAECn8eAAIBAAcK8wfqFgFmAQABAAcK8wfqFgFmAQAAAA==.Collateral:BAAANQAECgQIBAAAAA==.Colomel:BAABNQAECn8UAAIBAAgKOAqWAwGIAQABAAgKOAqWAwGIAQAAAA==.Comegetsum:BAAANQADCgYIEQAAAA==.Compaktdisc:BAAANQADCgYIBgABNQAECgoKFgALAFkPAA==.Conqbine:BAAANQAECgQIAwAAAA==.Corg:BAAANQAECgYICwAAAA==.Countchocula:BAABNQAECn8rAAIBAAkKGhQiVAAWAgABAAkKGhQiVAAWAgAAAA==.',
Cr='Crimmi:BAABNQAECn8dAAIIAAkKwQhSOgAtAQAIAAkKwQhSOgAtAQAAAA==.Critzilla:BAAANQAECgYIBQAAAA==.',
Cu='Cuddy:BAAANQADCgYICgAAAA==.',
Cy='Cybuster:BAAANQADCgUJBQABNQAECgoKVgABANgfAA==.Cyndle:BAABNQAECn86AAIYAAoK4gyLdQCrAQAYAAoK4gyLdQCrAQAAAA==.',
Da='Daddythicc:BAABNQAECn8sAAIBAAoKowpy5QC+AQABAAoKowpy5QC+AQAAAA==.Darnwrath:BAAANQAECgYIBgAAAA==.Darrkness:BAAANQADCgYIBgAAAA==.',
De='Deadgirljd:BAAANQAECgQICQAAAA==.Deadillusion:BAAANQADCgUIBQABNQAECgoKIQAaAGMfAA==.Deathpockets:BAAANQAECgMIBAAAAA==.Deran:BAABNQAECn81AAMOAAoKkx4YQQBnAgAOAAoKFR4YQQBnAgAbAAcK4Bd9LQBxAQAAAA==.',
Di='Diante:BAABNQAECn8UAAIRAAUKdgVhcACRAAARAAUKdgVhcACRAAAAAA==.Dimple:BAAANQAECgIJAgAAAA==.Dirtmonkgirt:BAABNQAECn8dAAIcAAoKSBXxGwDIAQAcAAoKSBXxGwDIAQAAAA==.Dirtnasty:BAABNQAECn8aAAIJAAoKECGgBQD/AgAJAAoKECGgBQD/AgABNQAFFAMIBwAQAJEgAA==.',
Dk='Dknujabes:BAAANQAECggIDwAAAA==.',
Do='Doofus:BAAANQADCgEIAQAAAA==.Doompockets:BAABNQAECn8iAAMdAAkKxgx/iADRAQAdAAkKrgl/iADRAQAeAAMKJg0cRwCrAAAAAA==.',
Dr='Dracara:BAABNQAECn80AAQfAAoK5hZvBQC7AgAfAAoK5hZvBQC7AgAgAAUK4wyRBQAiAQABAAMKBAeAnAGMAAAAAA==.Dracia:BAAANQAECgYIEAAAAA==.Drakulya:BAAANQABCgQIBAAAAA==.Drakunda:BAABNQAECn8iAAQFAAoKig3zFQC2AQAFAAoKig3zFQC2AQAYAAQKVgOAzgB6AAAaAAEKAADyHgEAAAABNQAECgoKNAAfAOYWAA==.Dreadz:BAABNQAECn8bAAMWAAcKkBA4NQCaAQAWAAcKJhA4NQCaAQAhAAIKJAmWKgBfAAAAAA==.Drewish:BAABNQAECn8uAAIiAAoKFB9zBwDpAgAiAAoKFB9zBwDpAgAAAA==.Drg:BAAANQADCgQIBAABNQADCgUIBQAGAAAAAA==.Drizzle:BAACNQAFFH8HAAIWAAIK0h/ACwCeAAAWAAIK0h/ACwCeAAA1AAQKf0UAAhYACgoFJNwEAIYDABYACgoFJNwEAIYDAAAA.Drktotem:BAABNQAECn89AAMFAAoKjiMlAwBvAwAFAAoKjiMlAwBvAwAYAAYKtxaCkABfAQAAAA==.Druidia:BAAANQADCgIIAgAAAA==.',
Du='Dulezlok:BAAANQADCgUIBQAAAA==.Dumbdog:BAACNQAFFH8oAAIKAAkKYR+MAADJAgAKAAkKYR+MAADJAgA1AAQKf0wAAgoACgrjIvMDAIcDAAoACgrjIvMDAIcDAAAA.Dumbledwarf:BAAANQADCggICAAAAA==.Dusan:BAABNQAECn87AAIMAAoK8RyZMwCZAgAMAAoK8RyZMwCZAgAAAA==.',
['Dï']='Dïvinity:BAAANQADCgIIAgAAAA==.',
Ea='Ea:BAAANQADCgcICAAAAA==.',
Ec='Echeyaket:BAABNQAECn8vAAMYAAoK/x7zLwBhAgAYAAoK/x7zLwBhAgAaAAIKmRChDwFsAAAAAA==.',
Ed='Edonsian:BAABNQAECn9UAAIEAAoKvBhtQQA+AgAEAAoKvBhtQQA+AgAAAA==.',
Eg='Egmont:BAAANQADCgUIBwAAAA==.',
El='Elektabuzz:BAAANQADCggIEAABNQAECgoKNwAOAL0gAA==.Elelusion:BAABNQAECn8hAAIaAAoKYx/5EgDTAgAaAAoKYx/5EgDTAgAAAA==.Eliyah:BAAANQAECgYICwAAAA==.Elliekins:BAABNQAECn8rAAIMAAoKqwfXdQB5AQAMAAoKqwfXdQB5AQAAAA==.Elçhapo:BAAANQAECgIIAwAAAA==.',
Em='Emergence:BAAANQAECgEIAQAAAA==.',
En='Endlesshour:BAAANQADCgMIAwAAAA==.Endlessly:BAABNQAECn8zAAISAAoK0xQCEwAsAgASAAoK0xQCEwAsAgAAAA==.Enoka:BAABNQAECn9AAAIBAAoK3xlcPwBPAgABAAoK3xlcPwBPAgAAAA==.',
Es='Estelá:BAAANQADCgYICgAAAA==.',
Et='Etikwa:BAABNQAECn81AAMKAAoKZQ03JwC4AQAKAAoKZQ03JwC4AQALAAUKgAOAbQB2AAAAAA==.',
Eu='Euclid:BAAANQAECgQIBgAAAA==.',
Ev='Evaporate:BAAANQAECgYIBgAAAA==.Evilguard:BAABNQAECn8dAAIRAAgKlA0EXwB2AQARAAgKlA0EXwB2AQAAAA==.',
Ex='Excessive:BAAANQAECgIIAgAAAA==.Exroastbeef:BAAANQADCggICAAAAA==.',
Fa='Falador:BAABNQAECn8XAAIEAAYKPgvv2AA8AQAEAAYKPgvv2AA8AQAAAA==.Fariebubbles:BAABNQAECn8UAAIKAAUKbhYDNwA/AQAKAAUKbhYDNwA/AQAAAA==.',
Fe='Felene:BAACNQAFFH8IAAIaAAUKAgr6FADHAAAaAAUKAgr6FADHAAA1AAQKfy8AAxoACgqYHlApANwCABoACgqYHlApANwCABgAAgrsDscCAWMAAAAA.Fenwell:BAAANQAECgQIBAABNQAECgkJPgAMANQZAA==.',
Fi='Firitako:BAABNQAECn8bAAMYAAYKpA4SowAuAQAYAAYKpA4SowAuAQAaAAUKXw1UmgDTAAAAAA==.',
Fr='Frailey:BAABNQAECn8ZAAMHAAgK6hd0CQDsAQAHAAgK6hd0CQDsAQAdAAMKUgzeJwFvAAAAAA==.Frankiejr:BAAANQAECgUIDAABNQAECgoKOQAOANIgAA==.Fraubles:BAAANQAECgMIBAAAAA==.Friedpickel:BAAANQADCgYIBwAAAA==.Friter:BAAANQAECgMIAwAAAA==.Frostnite:BAAANQAECgUIEAAAAA==.Frostpoptart:BAABNQAECn8zAAMFAAoKRRrpCQDVAgAFAAoKRRrpCQDVAgAYAAIKQhfszgB5AAAAAA==.Frozenblade:BAABNQAECn81AAIRAAoKEBS9QQD2AQARAAoKEBS9QQD2AQAAAA==.',
Fu='Furball:BAAANQAECgcIEgABNQAFFAcIFgAdALIRAA==.Furiousgeorg:BAAANQAECgUIDAAAAA==.',
Ga='Gagabooney:BAACNQAFFH8HAAIQAAMKkSBtBwDHAAAQAAMKkSBtBwDHAAA1AAQKfxkAAhAACAouIQgJAJYCABAACAouIQgJAJYCAAAA.Galay:BAAANQAECgcIEwAAAA==.Garabashi:BAAANQADCgcJBwAAAA==.Garrick:BAABNQAECn8qAAQNAAkKXBqOCwDSAQANAAgKaBSOCwDSAQAjAAgKOxrqEQCZAQAEAAQKCwjoIwGRAAAAAA==.Gazze:BAABNQAECn87AAIJAAoKUgpjLAArAQAJAAoKUgpjLAArAQAAAA==.',
Ge='Gemli:BAAANQADCgUIBQAAAA==.Gennissa:BAAANQAECgMIBAAAAA==.Gertog:BAAANQAECgQIBAAAAA==.Gethsemane:BAABNQAECn8lAAMdAAoKBhbeRACEAgAdAAoKBhbeRACEAgAHAAQK6RSgEgAfAQAAAA==.',
Gi='Gigadoot:BAAANQABCgQIAgAAAA==.Gigglez:BAAANQADCgcJCQAAAA==.Gillis:BAAANQADCggIDAAAAA==.',
Gl='Glassdance:BAAANQAECgMIAwAAAA==.',
Gn='Gnryderp:BAAANQADCgUIBQAAAA==.',
Go='Goam:BAAANQADCggIFwAAAA==.Googrektar:BAAANQAECgQIBAABNQAFFAYIDAABADMQAA==.Goonielama:BAABNQAECn8qAAIRAAoKHCF/DgA7AwARAAoKHCF/DgA7AwABNQAFFAMIBwAQAJEgAA==.Goonietai:BAAANQAECgUICQABNQAFFAYIDAABADMQAA==.',
Gr='Greenterror:BAAANQADCgIIAgAAAA==.Grid:BAAANQAECgMIAwABNQAFFAUICQAdAKwPAA==.Griitz:BAAANQAECgQICAAAAA==.Grimmsheeper:BAACNQAFFH8LAAMBAAYKCRM/KgA5AQABAAUKNxQ/KgA5AQAfAAEKUQ7MEQBPAAA1AAQKf1IAAwEACgoKJeQVAPECAAEACgoKJeQVAPECAB8AAgqWHQ4mAK4AAAAA.Gryff:BAAANQADCgUJBQAAAA==.',
Gu='Guess:BAAANQAECgQIBAAAAA==.Gurtdk:BAACNQAFFH8lAAQIAAkKgBRIBADtAQAIAAYKwxpIBADtAQARAAEKAACZKABWAAAkAAIK2gSZHgBMAAA1AAQKfz8AAwgACgpbJjALAGEDAAgACgrwJTALAGEDACQACAqOI34OAOACAAAA.',
Gy='Gyat:BAAANQADCgMJAwAAAA==.',
Ha='Hairynujabes:BAABNQAECn8WAAMLAAgK2w09ZQA4AQALAAcKSg09ZQA4AQAJAAIKtBAWcQAuAAAAAA==.Hamandcheeze:BAAANQAECgIIAQAAAA==.Hanyuu:BAABNQAECn83AAISAAoKOA+uGADeAQASAAoKOA+uGADeAQAAAA==.',
He='Healviji:BAAANQAECgYIBwAAAA==.Heiter:BAABNQAECn8mAAIMAAkKCxg3QwBfAgAMAAkKCxg3QwBfAgABNQAECgoKLQAaAGgbAA==.Hellbound:BAABNQAECn9DAAMdAAoKIhrQSgDzAQAdAAoKqBjQSgDzAQAeAAIK/BMFVQB/AAAAAA==.Hellinhunt:BAACNQAFFH8MAAMCAAkKqQquFwD9AAATAAYKGQeWEgAWAQACAAMKkROuFwD9AAA1AAQKfxoAAxMACgrVIEklAD8BAAIABwpjIXtyANsBABMABwo8GkklAD8BAAAA.',
Ho='Holyekko:BAAANQADCgEIAQAAAA==.Holypants:BAAANQADCgYIBgAAAA==.Honk:BAAANQAECgUIBQABNQAECgkJGgABAMwQAA==.Hornivore:BAAANQADCgcIFQABNQAECgoKRQACAKIZAA==.',
Hy='Hyrja:BAAANQADCgUIBgABNQAECgoKNAAfAOYWAA==.',
['Hâ']='Hâvyr:BAAANQAECggIEQAAAA==.',
Ic='Icefrosting:BAABNQAECn8iAAIBAAoK1Bk6RQA9AgABAAoK1Bk6RQA9AgABNQAECgoKJAASAIUdAA==.',
Id='Idistroya:BAAANQAECgUICAABNQAECgoKMgACAEUcAA==.',
Ig='Iggnogg:BAAANQAECgQICwAAAA==.',
Ik='Ikura:BAACNQAFFH8SAAIMAAUKzBKxEgB3AQAMAAUKzBKxEgB3AQA1AAQKfy4ABBUACgpUFnUIADMBAAwACgpAEdtmAOoBABUACApREHUIADMBABIAAgrHCEJmADEAAAAA.',
Il='Ilithiya:BAABNQAECn8uAAIWAAoKSySjBACKAwAWAAoKSySjBACKAwAAAA==.Ilk:BAABNQAECn8hAAIFAAoKqQhPHgB8AQAFAAoKqQhPHgB8AQAAAA==.Illududu:BAAANQAECgcIBwABNQAECgoKIQAaAGMfAA==.',
Im='Imangry:BAAANQADCgEIAQAAAA==.',
Is='Isaidnoice:BAAANQADCgYICgAAAA==.Ishiftmyself:BAABNQAECn8WAAILAAoKWQ/7RgDRAQALAAoKWQ/7RgDRAQAAAA==.Ishton:BAACNQAFFH8IAAIOAAUK5AX+HQCqAAAOAAUK5AX+HQCqAAA1AAQKfy8AAg4ACgpHG0RJALkCAA4ACgpHG0RJALkCAAAA.Istompgnomes:BAABNQAECn8VAAIaAAcKYBcBdgC/AQAaAAcKYBcBdgC/AQAAAA==.',
It='Itsnowz:BAAANQADCgQIBAAAAA==.',
Ja='Jacobean:BAAANQADCgQIBAAAAA==.Jasøn:BAAANQADCgcIDgABNQAECgkJIAACAIcMAA==.',
Je='Jecthyr:BAABNQAECn84AAQUAAoKTRm9FgBMAgAUAAoKTRm9FgBMAgAPAAgK6xQrDACVAQAlAAEKjAT1HwAiAAAAAA==.Jefeson:BAAANQAECgYICQAAAA==.Jemhdar:BAAANQAECgEIAQAAAA==.Jermdaga:BAAANQADCgQIBAAAAA==.',
Ji='Jinnasaiquoi:BAABNQAECn8eAAMOAAkKbhl/UAA6AgAOAAkKixh/UAA6AgAbAAQKTRSUQQDwAAAAAA==.Jinnasasquoi:BAAANQAECggICAAAAA==.',
Js='Jsdruid:BAAANQAECgcIDAAAAA==.',
Ka='Kaelosu:BAABNQAECn8xAAIdAAkK3BwALwDKAgAdAAkK3BwALwDKAgAAAA==.Kakum:BAABNQAECn8gAAMZAAoKQR2XDgBNAwAZAAoKQR2XDgBNAwAOAAEKAABH2AEAAAAAAA==.Kaldrogo:BAAANQAECgcIBQAAAA==.Kalnuggets:BAAANQAECgcIBgAAAA==.Kalrathen:BAABNQAECn83AAMMAAoKJxqmOwB7AgAMAAoKJxqmOwB7AgASAAEKewFQkgAXAAAAAA==.Kanda:BAABNQAECn84AAICAAoKaBrNOwC3AgACAAoKaBrNOwC3AgAAAA==.Karsh:BAABNQAECn8bAAMNAAoK7ARoGAAZAQANAAgKJwVoGAAZAQAEAAQKWwRA/wB2AAAAAA==.Kazadax:BAABNQAECn8nAAIdAAoKdg+1gQDiAQAdAAoKdg+1gQDiAQAAAA==.',
Ke='Kealosu:BAAANQADCggIDgAAAA==.Keen:BAAANQAECgEIAQAAAA==.Keuaakepo:BAABNQAECn8yAAICAAoKRRwzMwDSAgACAAoKRRwzMwDSAgAAAA==.',
Ki='Kienne:BAABNQAECn8uAAICAAoKxBcvZgD4AQACAAoKxBcvZgD4AQAAAA==.Kiljaedra:BAAANQAECgEIAgABNQAECgoKNAAfAOYWAA==.Kinomi:BAAANQADCgYIBgABNQAECgoKFgALAFkPAA==.Kitenna:BAAANQAECggIDAAAAA==.',
Kl='Kleenex:BAAANQADCgEIAQAAAA==.',
Ko='Korbanhavoc:BAABNQAECn8XAAIOAAcK4hHMxgCOAQAOAAcK4hHMxgCOAQAAAA==.Korogar:BAAANQAECgUIDQAAAA==.',
Kp='Kpes:BAAANQADCgUJBQAAAA==.',
Kr='Kreamyumyums:BAAANQAECggICwAAAA==.Krisp:BAAANQADCgUICAAAAA==.Krizzl:BAAANQADCgUIBQABNQAFFAcIGwAIAMwgAA==.Kronknar:BAAANQABCgQJBAABNQAECgoKLwAaABEdAA==.Krìzzl:BAABNQAECn8dAAIDAAoKzxUHLQBKAgADAAoKzxUHLQBKAgABNQAFFAcIGwAIAMwgAA==.',
Ky='Kymira:BAABNQAECn83AAIQAAoKOBpVBwDIAgAQAAoKOBpVBwDIAgAAAA==.',
La='Lace:BAACNQAFFH8JAAQdAAUKrA+KLQByAAAdAAQKfw2KLQByAAAHAAEKvwbjGQBFAAAeAAEKFg6BFABDAAA1AAQKf2wABB0ACgrgJLAJAH8DAB0ACgrSIrAJAH8DAAcABQrbH50JALYBAB4AAgrzJAITAMAAAAAA.Lanzen:BAAANQADCgEIAQAAAA==.Larrfena:BAABNQAECn9FAAICAAoKohm+UgAnAgACAAoKohm+UgAnAgAAAA==.Lavatory:BAAANQADCgMIBgAAAA==.Lazarou:BAAANQAECgUIBgAAAA==.',
Le='Legsday:BAAANQAECgIIAwAAAA==.Lementz:BAACNQAFFH8OAAIaAAQKVhHPEgBDAQAaAAQKVhHPEgBDAQA1AAQKfycAAhoACgr3HjEhAAUDABoACgr3HjEhAAUDAAAA.',
Li='Liadres:BAAANQADCgIIAgAAAA==.Liante:BAAANQADCgcIEgABNQAECgUIFAARAHYFAA==.Libellule:BAAANQABCgQIBAAAAA==.Lilboat:BAAANQAECgEIAQAAAA==.Lillia:BAABNQAECn9MAAIdAAoKvhOUQgAOAgAdAAoKvhOUQgAOAgAAAA==.Lillybell:BAAANQADCgUIBQAAAA==.Littleboyz:BAAANQADCgcIBwAAAA==.',
Lo='Loop:BAACNQAFFH8IAAIEAAgKagFaKwCAAAAEAAgKagFaKwCAAAA1AAQKfxkAAgQACgoWHkstAIkCAAQACgoWHkstAIkCAAAA.Loopku:BAAANQAECggICwAAAA==.Lorinash:BAAANQADCgYICQAAAA==.Lothelo:BAAANQAECgEIAgABNQAECgoKHgAOAH0bAA==.',
Lu='Lumpia:BAACNQAFFH8KAAMIAAUKYRIDCADbAAAIAAQKYRIDCADbAAARAAEKAAC4OQAAAAA1AAQKfzAAAwgACgrkHCEvAHQCAAgACgrkHCEvAHQCABEABgpYB51pAKYAAAAA.',
Lv='Lvel:BAAANQADCgYICgAAAA==.',
['Lë']='Lëeloo:BAAANQAECgcICQABNQAECggIEgAGAAAAAA==.',
Ma='Machinism:BAAANQADCgIIAgABNQADCgcJCAAGAAAAAA==.Maey:BAABNQAECn83AAMBAAoK2xaAjQBkAgABAAoKQBSAjQBkAgAfAAEKASHLOwBQAAAAAA==.Magoobers:BAAANQADCgEIAQAAAA==.Maktah:BAABNQAECn8vAAMaAAoKER0ELwDAAgAaAAoKER0ELwDAAgAFAAEK/AiiNAA+AAAAAA==.Malpractice:BAAANQAECggICgABNQAECgoKFgALAFkPAA==.Maybesinged:BAABNQAECn9GAAIBAAoK4B18LwCCAgABAAoK4B18LwCCAgAAAA==.',
Me='Meanboy:BAAANQAECgMIAwAAAA==.Meishra:BAAANQADCgcICQAAAA==.Mentos:BAABNQAECn8+AAQPAAoK8h+HBQA5AwAPAAoK8h+HBQA5AwAUAAIK4xQSQQCYAAAlAAEKCRNJIwA5AAAAAA==.',
Mi='Miltank:BAACNQAFFH8HAAIOAAIKCRgLIwCPAAAOAAIKCRgLIwCPAAA1AAQKf0kAAg4ACgp1JFgLAEcDAA4ACgp1JFgLAEcDAAAA.Minaqt:BAAANQADCgEIAQAAAA==.Minatory:BAABNQAECn8kAAIWAAoKqRlvGACZAgAWAAoKqRlvGACZAgAAAA==.Mionn:BAABNQAECn83AAMOAAoKvSDMNACQAgAOAAoKvSDMNACQAgAZAAEK7gokHwE3AAAAAA==.Misfires:BAAANQABCggIEwAAAA==.',
Ml='Mlleena:BAABNQAECn8fAAIeAAcKLRGAGQCgAQAeAAcKLRGAGQCgAQAAAA==.',
Mo='Moddim:BAAANQADCgUIBQAAAA==.Modotz:BAAANQADCgEIAQAAAA==.Mogg:BAAANQAECgEIAQAAAA==.Moghoul:BAAANQAECgQIBQAAAA==.Monandwah:BAAANQADCggIFAAAAA==.Montorgo:BAAANQADCgYIBgAAAA==.Moofi:BAAANQADCggIEQABNQAECggIHgAFADgLAA==.Mooncake:BAABNQAECn8fAAMPAAkKIQdqGgCiAQAPAAkKIQdqGgCiAQAlAAIKhAJWIgBBAAAAAA==.Moonless:BAAANQAECgEIAQABNQAECgoKRwABANMaAA==.Moosiah:BAAANQADCgcIBwAAAA==.Mossfire:BAAANQAECgUIBgABNQAECgkJKgANAFwaAA==.Motoko:BAABNQAECn8gAAMQAAoKvRk/CgByAgAQAAoKvRk/CgByAgAmAAIK3AQEQAAqAAAAAA==.',
Mu='Musesong:BAAANQADCgMIAwAAAA==.',
['Mø']='Møø:BAAANQAECgYICwABNQAECgkJIAACAIcMAA==.Møøfi:BAABNQAECn8eAAIFAAgKOAsfHQBLAQAFAAgKOAsfHQBLAQAAAA==.',
Na='Naianasha:BAABNQAECn8uAAMMAAoKoBtgKACtAgAMAAoKoBtgKACtAgAVAAUKLBKmCwDZAAAAAA==.Nameless:BAABNQAECn9HAAIBAAoK0xo/NAByAgABAAoK0xo/NAByAgAAAA==.Narc:BAABNQAECn8aAAILAAcKLQUrXgCpAAALAAcKLQUrXgCpAAAAAA==.',
Ne='Necroraise:BAAANQADCgIIAgAAAA==.Neeraj:BAABNQAECn8rAAICAAoKqBUhVAAkAgACAAoKqBUhVAAkAgAAAA==.Nevergreen:BAAANQABCgIIAgAAAA==.',
Ni='Nightreaver:BAAANQAECgUIBAABNQAECgoKGwAQAIMhAA==.Nikwillig:BAAANQAECgYICwAAAA==.',
No='Nokzash:BAABNQAECn8kAAIZAAoKsx5HKQDDAgAZAAoKsx5HKQDDAgAAAA==.Noova:BAABNQAECn84AAIBAAoKQh/6SQDuAgABAAoKQh/6SQDuAgAAAA==.',
Ny='Nyang:BAAANQAECgYIDQAAAA==.Nythendrac:BAAANQADCgQIBAABNQAECgoKNAAfAOYWAA==.',
Ob='Obliverat:BAAANQAECggIEgAAAA==.',
Od='Odysseus:BAAANQADCgIIBAAAAA==.',
Oo='Oongaboonga:BAABNQAECn8xAAIEAAgKkh9PSwCnAgAEAAgKkh9PSwCnAgAAAA==.',
Or='Orcaneblast:BAACNQAFFH8MAAIBAAYKMxBtHgAGAQABAAYKMxBtHgAGAQA1AAQKfzwAAwEACgpPILlJAO8CAAEACgpPILlJAO8CACAABwrRF/YCAK4BAAAA.Orcsoup:BAABNQAECn8WAAIaAAcKpxtUVgAhAgAaAAcKpxtUVgAhAgABNQAECgoKPQAKAFAdAA==.Orcviji:BAAANQAECgYIBgAAAA==.',
Pa='Paddord:BAAANQADCggICgAAAA==.Paranoià:BAAANQADCgIIAgABNQAECgEIAQAGAAAAAA==.',
Pe='Peewpewpew:BAAANQADCgYIBgAAAA==.Penance:BAAANQAECgcICwAAAA==.Percible:BAAANQAECgIIAgAAAA==.',
Ph='Phoenixphyre:BAAANQADCgUIBQAAAA==.',
Pi='Pivnert:BAABNQAECn8xAAQBAAkKRhp6YgDxAQABAAkKmBh6YgDxAQAfAAIKbBi8LQCPAAAgAAQKhhO6CACCAAAAAA==.',
Pl='Plums:BAAANQAECggICQAAAA==.',
Po='Popdkook:BAAANQADCgYIEgAAAA==.',
Pr='Proko:BAAANQADCggICAAAAA==.',
Ps='Psychopump:BAAANQAECgYIDgAAAA==.',
['Pü']='Pünish:BAACNQAFFH8NAAIIAAYKJRjkBgDuAAAIAAYKJRjkBgDuAAA1AAQKf2EABAgACgoJJP0GAI4DAAgACgoJJP0GAI4DACQAAwpxFcR7ALgAABEAAQpfBRvSACsAAAAA.',
Qq='Qqpewpew:BAAANQAECggIBAAAAA==.',
Qu='Quinn:BAAANQADCgIJAgABNQAECgoKGwAQAIMhAA==.',
Ra='Rabit:BAAANQADCgUIBQAAAA==.Raelina:BAABNQAECn8lAAMBAAkKhSHdTADnAgABAAkKsx/dTADnAgAfAAIKoCISJwC6AAABNQAFFAkJPgABANoiAA==.Ragingiscool:BAAANQADCggIDwAAAA==.Rail:BAAANQAECgEIAQAAAA==.Rajank:BAAANQADCgQIBAAAAA==.Rallek:BAABNQAECn8gAAIZAAoKjRB4bADSAQAZAAoKjRB4bADSAQAAAA==.Ranuggul:BAAANQAECgIIAQAAAA==.Rarn:BAAANQADCgMIAwABNQAECgoKPgARAK8fAA==.Ratsrepus:BAAANQADCgcICwAAAA==.Raza:BAAANQAECgQIDAABNQAFFAYIDQAIACUYAA==.',
Re='Read:BAABNQAECn8cAAILAAcK8RBWPwAsAQALAAcK8RBWPwAsAQAAAA==.Reddawn:BAAANQADCgcIBwAAAA==.Remeras:BAABNQAECn8WAAIOAAoKKhGrlQD4AQAOAAoKKhGrlQD4AQAAAA==.',
Ri='Riken:BAABNQAECn8UAAImAAcKvQ3qJABUAQAmAAcKvQ3qJABUAQAAAA==.Ripblast:BAAANQAECgUIBgABNQAECgoKGwAQAIMhAA==.Ritual:BAABNQAECn85AAIYAAoKzRuGHQDOAgAYAAoKzRuGHQDOAgAAAA==.',
Ro='Roadi:BAAANQAECggIEgAAAA==.Roxer:BAACNQAFFH8FAAIZAAEKCwkQKwA5AAAZAAEKCwkQKwA5AAA1AAQKfygAAhkACgrzERhRACcCABkACgrzERhRACcCAAAA.',
Ru='Rukaa:BAAANQAECgIIAwAAAA==.Rummyy:BAACNQAFFH8KAAIWAAQKQx/4BQAQAQAWAAQKQx/4BQAQAQA1AAQKfygAAxYACgrCHvAQAEsCABYACgrCHvAQAEsCABcAAQqTDBWPADwAAAAA.',
Ry='Rycken:BAABNQAECn89AAMKAAoKaA7ZKQDQAQAKAAoKaA7ZKQDQAQALAAgKWxhLLQCZAQAAAA==.',
Sa='Saeylva:BAABNQAECn8WAAIWAAgKegXkNADzAAAWAAgKegXkNADzAAAAAA==.Saosis:BAAANQAECgYIBgAAAA==.Savage:BAAANQADCgIIAgAAAA==.Sayurri:BAAANQADCgEJAQAAAA==.',
Sc='Scribble:BAAANQAECgQICAAAAA==.Scuddy:BAAANQAECgEIAQAAAA==.Sculper:BAABNQAECn8XAAInAAcK6hFBDQB2AQAnAAcK6hFBDQB2AQAAAA==.',
Se='Senica:BAABNQAECn8zAAIMAAoKASNMBgDOAwAMAAoKASNMBgDOAwAAAA==.Seriphina:BAAANQADCggICAAAAA==.',
Sg='Sgornyweaver:BAAANQADCgUJBQAAAA==.',
Sh='Shabbarankzz:BAABNQAECn8+AAIkAAoKvxWrNQADAgAkAAoKvxWrNQADAgAAAA==.Shadetotem:BAABNQAECn8pAAIFAAkKJA9mFwCeAQAFAAkKJA9mFwCeAQAAAA==.Shammyblammy:BAAANQABCgEIAQAAAA==.Sheshotu:BAAANQADCggIFwAAAA==.Shiftor:BAAANQADCggIEgAAAA==.Shinedown:BAAANQADCgMIAwAAAA==.Shmoopy:BAAANQAECgMIAgAAAA==.Shradehn:BAABNQAECn8iAAIXAAoKTBXzKADGAQAXAAoKTBXzKADGAQAAAA==.Shutitdown:BAAANQAECgUIBQAAAA==.',
Si='Sindracosa:BAAANQAECgEIAQABNQAECgoKNAAfAOYWAA==.Sisterswede:BAABNQAECn8dAAISAAkK/h1LEwDPAgASAAkK/h1LEwDPAgAAAA==.Sixfingers:BAAANQADCgQIBAAAAA==.Sizzle:BAABNQAECn8aAAIBAAkKzBBAowA7AgABAAkKzBBAowA7AgAAAA==.',
Sm='Smokeahontas:BAABNQAECn8pAAIaAAoK3BDFRgC6AQAaAAoK3BDFRgC6AQAAAA==.Smokindots:BAAANQAECgcIEgABNQAFFAYIEAAYABYVAA==.Smokingreen:BAAANQADCggICAABNQAFFAYIEAAYABYVAA==.Smokinice:BAAANQADCggICwABNQAFFAYIEAAYABYVAA==.Smokinloud:BAAANQADCgIIAgAAAA==.Smokinmyrrh:BAAANQAECgUIBQABNQAFFAYIEAAYABYVAA==.Smokinmyth:BAAANQADCgcICAAAAA==.Smokinpsalm:BAABNQAECn8XAAIMAAgKzQ+NgQCTAQAMAAgKzQ+NgQCTAQABNQAFFAYIEAAYABYVAA==.Smokintotem:BAACNQAFFH8QAAIYAAYKFhUXEABcAQAYAAYKFhUXEABcAQA1AAQKf0oAAxgACgo0I4MMAFwDABgACgo0I4MMAFwDABoABgqBGllsANsBAAAA.',
Sn='Snawkin:BAAANQADCgEIAQAAAA==.',
Sp='Spaghet:BAEBNQAECn8fAAIaAAkKnh5PGACoAgAaAAkKnh5PGACoAgABNQAFFAcIDQAEAMAPAA==.Sparklnmagic:BAAANQAECgIIAgAAAA==.Spore:BAAANQADCgIIAgAAAA==.',
Sq='Squigboogalo:BAAANQADCgEIAQAAAA==.',
St='Starweaver:BAAANQAECgEIAQAAAA==.Steadyrock:BAABNQAECn8ZAAMLAAoK7xRCNwAzAgALAAoK7xRCNwAzAgAKAAEK8QR4eAAuAAAAAA==.Stemi:BAAANQAECgEIAQAAAA==.Steveirwin:BAAANQADCggJCAAAAA==.Stiffsheets:BAAANQAECgQIBAABNQAECgoKGwAQAIMhAA==.Stiltz:BAAANQADCgEIAQAAAA==.Stormywind:BAABNQAECn8dAAIaAAkKnQhojQCCAQAaAAkKnQhojQCCAQAAAA==.Stormz:BAABNQAECn9GAAILAAoK4hTUIQDvAQALAAoK4hTUIQDvAQAAAA==.',
Su='Sunblade:BAABNQAECn8ZAAIRAAgKIxRyWwCFAQARAAgKIxRyWwCFAQABNQAECgoKRwABANMaAA==.Sundayskoolz:BAAANQADCgUIBQAAAA==.Sundowning:BAAANQAECgcIDAAAAA==.Sunreaver:BAABNQAECn8hAAIZAAoKJROdPAAlAgAZAAoKJROdPAAlAgAAAA==.Supercappy:BAAANQAECgIIBQAAAA==.Suraegi:BAAANQAECgIIAgAAAA==.',
Sw='Swabby:BAAANQADCgEIAQAAAA==.Swiftdragon:BAABNQAECn8bAAMQAAoKgyHGBAAlAwAQAAkK6SPGBAAlAwAcAAIK2RMYSwB3AAAAAA==.',
Ta='Taapfer:BAAANQAECgMIAwABNQAECgoKJgABAKQVAA==.Tackyh:BAABNQAECn85AAICAAgKzB1ebADpAQACAAgKzB1ebADpAQAAAA==.Takamatsu:BAABNQAECn9EAAMMAAoKVSRnFgAgAwAMAAoKVSRnFgAgAwAVAAMKDA6LGgCWAAAAAA==.Taku:BAAANQAECgQICAAAAA==.Tanktoucher:BAAANQAECggIAQAAAA==.Tar:BAABNQAECn8gAAMCAAkKhwzOuwCMAQACAAgK2gzOuwCMAQATAAMKFAiGZACZAAAAAA==.Taxii:BAABNQAECn89AAMEAAoKHCbNJQAiAwAEAAoKgCPNJQAiAwANAAkKGCbpBgCRAgAAAA==.Taxilan:BAAANQAECgQIAwABNQAECgoKPQAEABwmAA==.',
Te='Tealnujabes:BAAANQAECgYIBwAAAA==.Teapots:BAACNQAFFH8KAAIFAAUKChotAwD7AAAFAAUKChotAwD7AAA1AAQKfxUAAgUABQrnI74aAGwBAAUABQrnI74aAGwBAAAA.Tempi:BAAANQABCgMIAwABNQAECgYIBgAGAAAAAA==.Tenpiece:BAAANQADCgMIAwAAAA==.',
Th='Thayelith:BAAANQAECgUIBAAAAA==.Thedeus:BAABNQAECn8eAAIOAAoKfRv8UwCZAgAOAAoKfRv8UwCZAgAAAA==.Thellira:BAAANQADCgEIAQAAAA==.Thermaul:BAABNQAECn9AAAIFAAoKQxxUCwBlAgAFAAoKQxxUCwBlAgAAAA==.Threebeans:BAABNQAECn89AAMKAAoKUB0GDQD+AgAKAAoKUB0GDQD+AgALAAcK9BHwRgDSAQAAAA==.Thromir:BAACNQAFFH8IAAMOAAUKUB68EQA0AQAOAAQK8CC8EQA0AQAZAAMKyA8rGADjAAA1AAQKfzYAAw4ACgrAJVwNADsDAA4ACgrAJVwNADsDABkACQoEIDQXAB8DAAAA.Thyrn:BAABNQAECn8+AAIRAAoKrx8YFABuAgARAAoKrx8YFABuAgAAAA==.',
Ti='Tirare:BAABNQAECn8pAAIIAAoKlBhJNABZAgAIAAoKlBhJNABZAgAAAA==.',
Tr='Tri:BAABNQAECn85AAIOAAoK0iAILACxAgAOAAoK0iAILACxAgAAAA==.Tristam:BAAANQAECgEIAQAAAA==.',
Tu='Tuneleitor:BAABNQAECn8sAAIoAAoKzRK0BAAxAgAoAAoKzRK0BAAxAgAAAA==.Turdferguson:BAAANQAFFAEIAQABNQAFFAMIBwAQAJEgAA==.Turgrok:BAABNQAECn8yAAMCAAoKghNIRwBCAgACAAoKghNIRwBCAgATAAgKUAuoNACoAQAAAA==.',
Tw='Twothang:BAABNQAECn8UAAMRAAgKOAiyagBJAQARAAgKoweyagBJAQAkAAIKMwWlnwBRAAAAAA==.',
Ty='Tyllan:BAABNQAECn9WAAMBAAoK2B9FTQAnAgABAAkKyR1FTQAnAgAfAAMKBh6JGwD8AAAAAA==.Tyllen:BAAANQAECgMIAwABNQAECgoKVgABANgfAA==.',
['Tâ']='Tâku:BAAANQAECgYICQAAAA==.',
Up='Upgrayedd:BAABNQAECn8aAAMZAAYKiQYUpADXAAAZAAYKiQYUpADXAAAOAAEKAAD+4AEPAAAAAA==.',
Ur='Urugargo:BAAANQABCgYIBgAAAA==.',
Va='Vainhellsing:BAABNQAECn8nAAIXAAgKrwZSTQDyAAAXAAgKrwZSTQDyAAAAAA==.Vanzier:BAABNQAECn8XAAICAAoKpRWHagA+AgACAAoKpRWHagA+AgAAAA==.Vaxis:BAABNQAECn8kAAICAAoKOQ/uggAGAgACAAoKOQ/uggAGAgAAAA==.',
Vi='Vid:BAACNQAFFH8RAAImAAcKQxThAgDmAQAmAAcKQxThAgDmAQA1AAQKfzQAAiYACgpQICMJAPkCACYACgpQICMJAPkCAAAA.',
Vo='Voidillusion:BAAANQAECgMIAwABNQAECgoKIQAaAGMfAA==.Voldoom:BAAANQAECgIIAwAAAA==.',
Wa='Watooie:BAAANQADCgYIBgAAAA==.',
We='Weave:BAAANQABCgIIAgABNQAFFAUICQAdAKwPAA==.Wernov:BAABNQAECn8tAAMaAAoKaBuCMgCwAgAaAAoKaBuCMgCwAgAYAAUK5BA2rAAYAQAAAA==.',
Wh='Whitetail:BAAANQAECgEIAgAAAA==.',
Wi='Wichan:BAABNQAECn87AAIJAAoKexzuDwA4AgAJAAoKexzuDwA4AgAAAA==.Wildsniper:BAAANQABCgIIAgAAAA==.Wildstrike:BAAANQADCgYIBgABNQAECgoKIAAQAL0ZAA==.Wiziviji:BAABNQAECn8nAAIBAAoKLAkFqwBOAQABAAoKLAkFqwBOAQAAAA==.',
Wo='Woodrow:BAAANQADCgcIBwAAAA==.',
Ws='Ws:BAAANQAECgIIAgAAAA==.',
Xa='Xanorea:BAAANQADCgYIBgABNQAECgcIFwAPAO0QAA==.',
Xd='Xdknight:BAAANQABCgIIAwAAAA==.',
Xe='Xerø:BAAANQAECggIDwAAAA==.',
Xr='Xray:BAABNQAECn8nAAMBAAoKFQ6vvgAHAgABAAoKFQ6vvgAHAgAfAAEKwgmzPwA3AAAAAA==.',
Xt='Xtra:BAAANQAECgMIAwAAAA==.Xtreme:BAAANQAECgIIAQAAAA==.',
Ya='Yamii:BAABNQAECn8uAAMjAAoK2hsJCwAXAgAjAAkKkhwJCwAXAgAEAAgKDhPDngBAAQABNQAFFAUICgAIAGESAA==.Yaphetkotto:BAAANQADCgcJCAAAAA==.Yawnk:BAABNQAECn8ZAAMmAAkKAQxPJADlAAAmAAcKKw5PJADlAAAcAAYKLw1wQACvAAAAAA==.',
Yu='Yunsky:BAAANQAECgUIDQAAAA==.',
Za='Zanber:BAAANQADCgIIAgAAAA==.Zandrakar:BAABNQAECn9CAAQYAAoK0xgzOgB2AgAYAAoK0xgzOgB2AgAFAAEKAACDOAAtAAAaAAEKPQViSQEpAAAAAA==.Zanosuke:BAAANQAECggIEgAAAA==.Zaria:BAABNQAECn8mAAIdAAoKVRKVcgAJAgAdAAoKVRKVcgAJAgAAAA==.Zaryor:BAABNQAECn8WAAMcAAcKIRTjMgB/AQAcAAcKIRTjMgB/AQAQAAQKYhIiIADkAAAAAA==.Zaun:BAAANQAECgUIBQAAAA==.',
Ze='Zentul:BAAANQAECgQIBAAAAA==.Zerica:BAAANQAECgIIAgAAAA==.Zerika:BAACNQAFFH8KAAIMAAUKVgm6FwBBAQAMAAUKVgm6FwBBAQA1AAQKfzkAAgwACgobI5EPAEkDAAwACgobI5EPAEkDAAAA.',
Zh='Zhaohu:BAAANQADCgYIBgAAAA==.',
Zi='Zigzwag:BAAANQAECgIIBgAAAA==.Zionna:BAAANQAECgYIEQABNQAECgoKFgALAFkPAA==.Zitos:BAABNQAECn9FAAMOAAoKYCQ+BgDIAwAOAAoKYCQ+BgDIAwAZAAEKfghNKgEsAAABNQAECgoKRQAOAGAkAA==.',
Zo='Zomgqq:BAACNQAFFH8FAAIFAAQKgBBgBADSAAAFAAQKgBBgBADSAAA1AAQKfyQAAwUACgoyHD8LAL0CAAUACgoyHD8LAL0CABgABArtDRfSAMMAAAAA.',
Zw='Zwagster:BAAANQAECgcIEgAAAA==.',
Zy='Zydis:BAAANQAECgYICgAAAA==.Zyggy:BAABNQAECn8iAAIRAAkKFxWUIwDeAQARAAkKFxWUIwDeAQAAAA==.Zynfanatic:BAAANQAECgcIDAABNQAECgoKPQAKAFAdAA==.',
['Än']='Ännihilation:BAAANQAECgIIAgAAAA==.',
['Èe']='Èepy:BAAANQAECgEIAQABNQAECgUIBAAGAAAAAA==.',
['És']='Éstéla:BAABNQAECn82AAICAAoKaxZVWABqAgACAAoKaxZVWABqAgAAAA==.',
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
