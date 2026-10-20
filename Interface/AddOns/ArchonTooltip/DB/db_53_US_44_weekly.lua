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

local lookup = {'Mage-Arcane','Hunter-BeastMastery','Rogue-Subtlety','Warrior-Arms','Unknown-Unknown','Warlock-Affliction','DeathKnight-Unholy','Shaman-Restoration','Druid-Guardian','Druid-Restoration','Druid-Balance','Priest-Holy','Warrior-Fury','Paladin-Retribution','Evoker-Preservation','DeathKnight-Blood','Priest-Shadow','Hunter-Marksmanship','Priest-Discipline','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Holy','Paladin-Protection','Monk-Windwalker','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Mage-Fire','DemonHunter-Vengeance','Druid-Feral','Shaman-Enhancement','Shaman-Elemental','Warrior-Protection','DeathKnight-Frost','Evoker-Devastation','Evoker-Augmentation','Monk-Mistweaver','Hunter-Survival',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abobadrin:BAAANQADCgcIDgAAAA==.Abrakadaver:BAABNQAECn8iAAIBAAoKuxTqVgAPAQABAAoKuxTqVgAPAQAAAA==.',
Ac='Acceb:BAAANQADCgQJBAAAAA==.',
Ad='Adventureux:BAABNQAECn8oAAICAAoKZxh6PAC0AgACAAoKZxh6PAC0AgAAAA==.',
Ae='Aedx:BAABNQAECn8oAAIDAAkKIxWrEgBZAgADAAkKIxWrEgBZAgAAAA==.Aerolorea:BAAANQADCgYICQAAAA==.',
Al='Alastar:BAABNQAECn8ZAAIEAAgK6h72XAB1AgAEAAgK6h72XAB1AgABNQAFFAIIAwAFAAAAAA==.Alexmage:BAAANQADCgYIBgABNQADCgcICAAFAAAAAA==.Alios:BAAANQAECgQIBAAAAA==.Alphasalt:BAAANQADCgcIBwABNQAECgYIFQAGADAYAA==.Alucard:BAAANQAECgYIDwAAAA==.Alunadoom:BAABNQAECn8YAAICAAcK0AUPygBtAQACAAcK0AUPygBtAQAAAA==.Alvera:BAACNQAFFH8KAAIHAAQK6BdICwBZAQAHAAQK6BdICwBZAQA1AAQKfzMAAgcACgrKJI0HAIgDAAcACgrKJI0HAIgDAAAA.',
Am='Ambellìna:BAAANQADCgIIAwABNQAECgEIAQAFAAAAAA==.',
An='Ancestor:BAABNQAECn8qAAIIAAoKRxQ5FwCdAQAIAAoKRxQ5FwCdAQAAAA==.Angechi:BAEANQADCgIJAgABNQAECgoKFgAJAMANAA==.Angrydk:BAAANQAECgMIBAAAAA==.Antisocial:BAABNQAECn8uAAIHAAoKziAuEgAmAwAHAAoKziAuEgAmAwABNQAECgoKLgAHAM4gAA==.',
Ar='Arielordril:BAAANQADCgEIAQAAAA==.Arm:BAABNQAECn9GAAQKAAoKSRqIAgCkAgAKAAoKSRqIAgCkAgALAAYKmAyMZgAzAQAJAAIKehMZUgBaAAAAAA==.Armee:BAABNQAECn8eAAIMAAoKRhipVwAbAgAMAAoKRhipVwAbAgAAAA==.Armz:BAAANQADCgEIAQAAAA==.',
As='Astrael:BAABNQAECn8VAAIBAAkKwheMSQApAQABAAkKwheMSQApAQAAAA==.Aszea:BAAANQAECgMIBgAAAA==.',
At='Attewode:BAAANQAECgEIAQAAAA==.',
Ax='Axas:BAAANQADCgIIAgAAAA==.Axra:BAABNQAECn8fAAINAAoK3A4kDQDmAQANAAoK3A4kDQDmAQAAAA==.',
Ay='Ayda:BAAANQAECgEIAQAAAA==.',
Az='Azairius:BAAANQADCggIGAAAAA==.Azzman:BAAANQADCgMIAwAAAA==.Azóg:BAABNQAECn8WAAIHAAgK2A7IVwCxAQAHAAgK2A7IVwCxAQAAAA==.',
Ba='Balsin:BAABNQAECn8oAAIOAAoKSSP4EwB2AwAOAAoKSSP4EwB2AwAAAA==.Bambii:BAAANQADCgUICgAAAA==.Bangungot:BAAANQAECgUIBgABNQAFFAgIFgAPABEVAA==.Barlaf:BAABNQAECn84AAICAAoKABvkNgDGAgACAAoKABvkNgDGAgABNQAECgMIAwAFAAAAAA==.Batou:BAAANQAECgUICAAAAA==.',
Be='Beeski:BAAANQADCgcIFwAAAA==.Beeto:BAACNQAFFH8KAAIOAAQKzgtHGgDWAAAOAAQKzgtHGgDWAAA1AAQKfywAAg4ACgraFvOTAPwBAA4ACgraFvOTAPwBAAAA.Belyndris:BAABNQAECn8iAAIMAAoKLhl+GACvAQAMAAoKLhl+GACvAQAAAA==.Benbear:BAEBNQAECn8WAAIJAAoKwA2SEAAJAQAJAAoKwA2SEAAJAQAAAA==.Benlian:BAEBNQAECn8lAAIQAAgKDhG1UgCqAQAQAAgKDhG1UgCqAQABNQAECgoKFgAJAMANAA==.',
Bl='Blighty:BAAANQAECgcIDQAAAA==.Blâze:BAACNQAFFH8UAAIBAAYKcBiKBQBQAQABAAYKcBiKBQBQAQA1AAQKfyUAAgEACgpSHP56AIgCAAEACgpSHP56AIgCAAAA.',
Bo='Bombardi:BAAANQAECgMIAwAAAA==.Bonknsmash:BAABNQAECn8fAAIEAAgKJhTYjQD6AQAEAAgKJhTYjQD6AQAAAA==.Boof:BAABNQAECn8nAAMRAAoKrRUQHQBaAgARAAkKjBUQHQBaAgAMAAEKvCBvgQBgAAAAAA==.Boregut:BAAANQAECggICAAAAA==.',
Br='Brewdock:BAAANQADCgEIAQAAAA==.Bronxor:BAABNQAECn8oAAISAAoKrxQvDwAQAQASAAoKrxQvDwAQAQAAAA==.',
Bu='Bubbleoshift:BAAANQAECgQIBAABNQAECggIFAALACYPAA==.Bushgarden:BAAANQADCgYIBwABNQADCgYICwAFAAAAAA==.Buzsmash:BAAANQAECgYIBgAAAA==.Buzzbuzz:BAAANQAECgMIBQABNQAECgkJGgABAMwQAA==.',
['Bó']='Bóba:BAACNQAFFH8dAAIPAAcKUiKlAQC8AgAPAAcKUiKlAQC8AgA1AAQKfygAAg8ACQrCI+QFAEwDAA8ACQrCI+QFAEwDAAAA.',
['Bö']='Böba:BAABNQAECn8ZAAQMAAkKkCQ+DABhAwAMAAkKkCQ+DABhAwATAAYKCyBpBgAnAgARAAEKAABOeQA1AAABNQAFFAcIHQAPAFIiAA==.',
Ca='Cadroyd:BAABNQAECn8jAAMKAAoKoRuIAwBdAgAKAAkKmhqIAwBdAgALAAMKQgVJnwBhAAAAAA==.Caelin:BAABNQAECn88AAMUAAoKlxLXNQAAAgAUAAkKlxLXNQAAAgAVAAYKNgwkGQDkAAAAAA==.Cailand:BAABNQAECn8iAAIEAAcKxRZqhwAJAgAEAAcKxRZqhwAJAgAAAA==.Caishana:BAABNQAECn8xAAIIAAoKaCDVDgBMAwAIAAoKaCDVDgBMAwAAAA==.Cambium:BAAANQAECgYIEAAAAA==.Camerbunne:BAAANQADCgYIEAAAAA==.Catdude:BAAANQAECgQIBgAAAA==.',
Ce='Cecil:BAAANQADCgYIBwAAAA==.Celebrate:BAAANQAECgEIAQAAAA==.',
Ch='Chaddingus:BAAANQAECggIDwAAAA==.Chopadk:BAABNQAECn8hAAIQAAkKsA8YUwCoAQAQAAkKsA8YUwCoAQAAAA==.Chumlëy:BAAANQAECgEIAQAAAA==.',
Cl='Clash:BAAANQADCgYIDgAAAA==.Clique:BAABNQAECn8mAAIWAAgKAR0PEwC7AQAWAAgKAR0PEwC7AQAAAA==.',
Cn='Cnc:BAAANQAECgEIAQAAAA==.',
Co='Coheedkil:BAAANQAECgEIAQAAAA==.Coldbreeze:BAABNQAECn8eAAIBAAcK8wfqFgFmAQABAAcK8wfqFgFmAQAAAA==.Collateral:BAAANQAECgQIBAAAAA==.Colomel:BAABNQAECn8UAAIBAAgKOAqWAwGIAQABAAgKOAqWAwGIAQAAAA==.Comegetsum:BAAANQADCgYIFAAAAA==.Compaktdisc:BAAANQADCgYIBgABNQAECggIFAALACYPAA==.Conqbine:BAAANQAECgQIBAAAAA==.Corg:BAAANQAECgUICQAAAA==.Countchocula:BAABNQAECn8UAAIBAAgKMg5RKgBxAQABAAgKMg5RKgBxAQAAAA==.',
Cr='Crimmi:BAAANQAECgYIDwAAAA==.Critzilla:BAAANQAECgYIBQAAAA==.',
Cu='Cuddy:BAAANQADCgYICgAAAA==.',
Cy='Cybuster:BAAANQADCgUJBQABNQAECgoKMgABAI8dAA==.Cyndle:BAABNQAECn8xAAIIAAoKFAuLdQCrAQAIAAoKFAuLdQCrAQAAAA==.',
Da='Daddythicc:BAABNQAECn8lAAIBAAoKEgrdZwDtAAABAAoKEgrdZwDtAAAAAA==.Darnwrath:BAAANQAECgYIBgAAAA==.Darrkness:BAAANQADCgYIBgAAAA==.',
De='Deadgirljd:BAAANQAECgQIBQAAAA==.Deadillusion:BAAANQADCgUIBQABNQAECgYICgAFAAAAAA==.Deathpockets:BAAANQAECgMIBAAAAA==.Deran:BAABNQAECn8rAAMOAAgK8hvFHQCrAQAOAAgKSxvFHQCrAQAXAAYKZRp9LQBxAQAAAA==.',
Di='Diante:BAAANQAECgMIBgAAAA==.Dimple:BAAANQAECgIJAgAAAA==.Dirtmonkgirt:BAABNQAECn8bAAIYAAgKERcjCACNAQAYAAgKERcjCACNAQAAAA==.Dirtnasty:BAAANQAECgUICAABNQAFFAIIBgAZALIiAA==.',
Dk='Dknujabes:BAAANQAECggIDwAAAA==.',
Do='Doofus:BAAANQADCgEIAQAAAA==.Doompockets:BAABNQAECn8iAAMaAAkKxgx/iADRAQAaAAkKrgl/iADRAQAbAAMKJg0cRwCrAAAAAA==.',
Dr='Dracara:BAABNQAECn8tAAQcAAoK5hZvBQC7AgAcAAoK5hZvBQC7AgAdAAUK4wyRBQAiAQABAAMKBAeAnAGMAAAAAA==.Dracia:BAAANQAECgYIEAAAAA==.Drakulya:BAAANQADCgEIAQAAAA==.Drakunda:BAAANQAECggICwABNQAECgoKLQAcAOYWAA==.Dreadz:BAABNQAECn8bAAMVAAcKkBA4NQCaAQAVAAcKJhA4NQCaAQAeAAIKJAmWKgBfAAAAAA==.Drewish:BAABNQAECn8nAAIfAAoKGR1zBwDpAgAfAAoKGR1zBwDpAgAAAA==.Drg:BAAANQADCgQIBAABNQADCgUIBQAFAAAAAA==.Drizzle:BAABNQAECn8sAAIVAAoKpCLcBACGAwAVAAoKpCLcBACGAwAAAA==.Drktotem:BAABNQAECn8rAAMgAAoKcSElAwBvAwAgAAoKcSElAwBvAwAIAAYKtxaCkABfAQAAAA==.Druidia:BAAANQADCgIIAgAAAA==.',
Du='Dulezlok:BAAANQADCgUIBQAAAA==.Dumbdog:BAACNQAFFH8kAAIKAAcK7yKMAADJAgAKAAcK7yKMAADJAgA1AAQKf0AAAgoACgqWIvMDAIcDAAoACgqWIvMDAIcDAAAA.Dumbledwarf:BAAANQADCggICQAAAA==.Dusan:BAABNQAECn8uAAIMAAkKFR3eEwDTAQAMAAkKFR3eEwDTAQAAAA==.',
['Dï']='Dïvinity:BAAANQADCgIIAgAAAA==.',
Ea='Ea:BAAANQADCgcICQAAAA==.',
Ec='Echeyaket:BAABNQAECn8eAAMIAAkKRxvKQABdAgAIAAkKRxvKQABdAgAhAAIKmRChDwFsAAAAAA==.',
Ed='Edonsian:BAABNQAECn85AAIEAAoKORZgMgBHAQAEAAoKORZgMgBHAQAAAA==.',
Eg='Egmont:BAAANQADCgUIBwAAAA==.',
El='Elektabuzz:BAAANQADCggIEgABNQAECgoKHgAOAEkaAA==.Elelusion:BAAANQAECgYICgAAAA==.Elliekins:BAABNQAECn8ZAAIMAAkKewdBJgBmAQAMAAkKewdBJgBmAQAAAA==.Elçhapo:BAAANQAECgIIAwAAAA==.',
En='Endlesshour:BAAANQADCgMIAwAAAA==.Endlessly:BAAANQAECgYICwAAAA==.Enoka:BAABNQAECn8oAAIBAAoKaBfnBwBNAgABAAoKaBfnBwBNAgAAAA==.',
Es='Estelá:BAAANQADCgYIBwAAAA==.',
Et='Etikwa:BAABNQAECn8hAAIKAAkK7QxrCgCQAQAKAAkK7QxrCgCQAQAAAA==.',
Eu='Euclid:BAAANQAECgMIAwAAAA==.',
Ev='Evilguard:BAABNQAECn8dAAIQAAgKlA0EXwB2AQAQAAgKlA0EXwB2AQAAAA==.',
Ex='Excessive:BAAANQAECgIIAgAAAA==.Exroastbeef:BAAANQADCggICQAAAA==.',
Fa='Falador:BAABNQAECn8XAAIEAAYKPgvv2AA8AQAEAAYKPgvv2AA8AQAAAA==.Fariebubbles:BAAANQAECgMIBgAAAA==.',
Fe='Felene:BAABNQAECn8kAAMhAAoKcxxQKQDcAgAhAAoKcxxQKQDcAgAIAAIK7A7HAgFjAAAAAA==.Fenwell:BAAANQADCgcIBwAAAA==.',
Fi='Firitako:BAAANQAECgYIEAAAAA==.',
Fr='Frailey:BAABNQAECn8UAAMGAAcKzxd0CQDsAQAGAAcKzxd0CQDsAQAaAAIKnQ/eJwFvAAAAAA==.Frankiejr:BAAANQAECgIIAwABNQAECgcIHwAOALQiAA==.Fraubles:BAAANQAECgMIBAAAAA==.Friedpickel:BAAANQADCgYIBwAAAA==.Friter:BAAANQADCggICQAAAA==.Frostnite:BAAANQAECgQICAAAAA==.Frostpoptart:BAABNQAECn8qAAMgAAkKxxrpCQDVAgAgAAkKxxrpCQDVAgAIAAIKQhcnZgCIAAAAAA==.Frozenblade:BAABNQAECn8mAAIQAAoKiBK9QQD2AQAQAAoKiBK9QQD2AQAAAA==.',
Fu='Furball:BAAANQAECgUIBQABNQAFFAYIEAAaAHERAA==.Furiousgeorg:BAAANQAECgUIDAAAAA==.',
Ga='Gagabooney:BAABNQAFFH8GAAIZAAIKsiJtBwDHAAAZAAIKsiJtBwDHAAAAAA==.Garabashi:BAAANQADCgcJBwAAAA==.Garrick:BAABNQAECn8UAAMiAAgKPhjHAwCkAQAiAAcKzRrHAwCkAQAEAAQKCwjoIwGRAAAAAA==.Gazze:BAABNQAECn8uAAIJAAkKtgiUDwAUAQAJAAkKtgiUDwAUAQAAAA==.',
Ge='Gemli:BAAANQADCgUIBQAAAA==.Gennissa:BAAANQAECgMIBAAAAA==.Gethsemane:BAABNQAECn8iAAMaAAkKLBbeRACEAgAaAAkKLBbeRACEAgAGAAQK6RSgEgAfAQAAAA==.',
Gh='Ghostrida:BAAANQADCgEIAQAAAA==.',
Gi='Gigadoot:BAAANQADCgEIAQAAAA==.Gigglez:BAAANQADCgcJCQAAAA==.Gillis:BAAANQADCggIDwAAAA==.',
Gl='Glassdance:BAAANQAECgEIAQAAAA==.',
Gn='Gnryderp:BAAANQADCgUIBQAAAA==.',
Go='Goam:BAAANQADCggIGQAAAA==.Goldenboii:BAAANQADCgEIAgAAAA==.Googrektar:BAAANQAECgQIBAABNQAFFAMICAABAFkUAA==.Goonielama:BAABNQAECn8oAAIQAAkKYyB/DgA7AwAQAAkKYyB/DgA7AwABNQAFFAIIBgAZALIiAA==.Goonietai:BAAANQAECgUICQABNQAFFAMICAABAFkUAA==.',
Gr='Graus:BAAANQADCgEIAQAAAA==.Greenterror:BAAANQADCgIIAgAAAA==.Grid:BAAANQAECgQIBAABNQAECgoKUAAaAI0kAA==.Griitz:BAAANQAECgQICAAAAA==.Grimmsheeper:BAACNQAFFH8KAAIBAAUKNxQ/KgA5AQABAAUKNxQ/KgA5AQA1AAQKfzEAAgEACgoHIgNFAPkCAAEACgoHIgNFAPkCAAAA.Gryff:BAAANQADCgUJBQAAAA==.',
Gu='Guess:BAAANQAECgQIBAAAAA==.Gurtdk:BAACNQAFFH8hAAQHAAcKLxpIBADtAQAHAAUKyB9IBADtAQAQAAEKAACZKABWAAAjAAEKyQPOGwBSAAA1AAQKfy0AAgcACgp5JTALAGEDAAcACgp5JTALAGEDAAAA.',
Gy='Gyat:BAAANQADCgMJBAAAAA==.',
Ha='Hairynujabes:BAABNQAECn8UAAMLAAgKYgw9ZQA4AQALAAcKSg09ZQA4AQAJAAIK2Ad/PQAsAAAAAA==.Hamandcheeze:BAAANQAECgIIAgAAAA==.Hanyuu:BAABNQAECn8kAAIRAAoKSAhvEQAEAQARAAoKSAhvEQAEAQAAAA==.',
He='Heiter:BAABNQAECn8mAAIMAAkKCxg3QwBfAgAMAAkKCxg3QwBfAgAAAA==.Hellbound:BAABNQAECn8vAAMaAAoK/BaQXgA8AgAaAAoKgBWQXgA8AgAbAAIKBRQFVQB/AAAAAA==.Hellinhunt:BAABNQAFFH8IAAMCAAcKyQyuFwD9AAASAAQKRQiWEgAWAQACAAMKkROuFwD9AAAAAA==.',
Ho='Holyekko:BAAANQADCgEIAQAAAA==.Holypants:BAAANQADCgYIBgAAAA==.Honk:BAAANQAECgUIBQABNQAECgkJGgABAMwQAA==.Hornivore:BAAANQADCgcIFQABNQAECgoKMQACADUXAA==.',
Hy='Hyrja:BAAANQADCgUIBwABNQAECgoKLQAcAOYWAA==.',
Ic='Icefrosting:BAABNQAECn8XAAIBAAkKaBjtBQB0AgABAAkKaBjtBQB0AgAAAA==.',
Id='Idistroya:BAAANQAECgUICAABNQAECgoKIwACAO8ZAA==.',
Ig='Iggnogg:BAAANQAECgMIBAAAAA==.',
Ik='Ikura:BAACNQAFFH8SAAIMAAUKzBKMBgB1AQAMAAUKzBKMBgB1AQA1AAQKfyUABBMACgoAEj0NAGEBAAwACQqDD9tmAOoBABMABwoyDT0NAGEBABEAAgrHCOI0ADEAAAAA.',
Il='Ilithiya:BAABNQAECn8iAAIVAAoKJCGjBACKAwAVAAoKJCGjBACKAwAAAA==.Ilk:BAABNQAECn8ZAAIgAAcKKQpPHgB8AQAgAAcKKQpPHgB8AQAAAA==.Illududu:BAAANQAECgEIAQABNQAECgYICgAFAAAAAA==.',
Im='Imangry:BAAANQADCgEIAQAAAA==.',
Is='Isaidnoice:BAAANQADCgYICwAAAA==.Ishiftmyself:BAABNQAECn8UAAILAAgKJg/7RgDRAQALAAgKJg/7RgDRAQAAAA==.Ishton:BAABNQAECn8lAAIOAAoKZRhESQC5AgAOAAoKZRhESQC5AgAAAA==.Istompgnomes:BAABNQAECn8VAAIhAAcKYBcBdgC/AQAhAAcKYBcBdgC/AQAAAA==.',
It='Itsnowz:BAAANQADCgQIBQAAAA==.',
Ja='Jacobean:BAAANQADCgQIBAAAAA==.Jasøn:BAAANQADCgcIDwABNQAECgkJHwACADQMAA==.',
Je='Jecthyr:BAABNQAECn8mAAMPAAoKSRqACQAqAQAPAAkK4RiACQAqAQAkAAQKkhNADQCNAAAAAA==.Jefeson:BAAANQAECgYICQAAAA==.Jemhdar:BAAANQAECgEIAQAAAA==.Jermdaga:BAAANQADCgQIBAAAAA==.',
Ji='Jinnasaiquoi:BAAANQAECgcIDQAAAA==.',
Js='Jsdruid:BAAANQAECgYIBgAAAA==.',
Ka='Kaelosu:BAABNQAECn8xAAIaAAkK3BwALwDKAgAaAAkK3BwALwDKAgAAAA==.Kakum:BAAANQAECgUIBwAAAA==.Kaldrogo:BAAANQADCggIFQAAAA==.Kalnuggets:BAAANQAECgcIBgAAAA==.Kalrathen:BAABNQAECn8uAAMMAAoKcRiUIgB3AQAMAAoKcRiUIgB3AQARAAEKewFQkgAXAAAAAA==.Kanda:BAABNQAECn8vAAICAAoKaBrNOwC3AgACAAoKaBrNOwC3AgAAAA==.Karsh:BAABNQAECn8YAAMNAAgKJwVoGAAZAQANAAgKJwVoGAAZAQAEAAIKOgRHqwBWAAAAAA==.Kazadax:BAABNQAECn8bAAIaAAkKkAy1gQDiAQAaAAkKkAy1gQDiAQAAAA==.',
Ke='Kealosu:BAAANQADCggIDgAAAA==.Keen:BAAANQAECgEIAQAAAA==.Keuaakepo:BAABNQAECn8jAAICAAoK7xkzMwDSAgACAAoK7xkzMwDSAgAAAA==.',
Ki='Kienne:BAABNQAECn8iAAICAAkKBxLphQD/AQACAAkKBxLphQD/AQAAAA==.Kiljaedra:BAAANQAECgEIAgABNQAECgoKLQAcAOYWAA==.Kinomi:BAAANQADCgYIBgABNQAECggIFAALACYPAA==.Kitenna:BAAANQAECgMIAwAAAA==.',
Kl='Kleenex:BAAANQADCgEIAQAAAA==.',
Ko='Korbanhavoc:BAABNQAECn8XAAIOAAcK4hHMxgCOAQAOAAcK4hHMxgCOAQAAAA==.Korogar:BAAANQAECgMICAAAAA==.',
Kp='Kpes:BAAANQADCgUJBQAAAA==.',
Kr='Kreamyumyums:BAAANQAECgUICgAAAA==.Krisp:BAAANQADCgUICAAAAA==.Krizzl:BAAANQADCgUIBQABNQAFFAYIFAAHALEmAA==.Kronknar:BAAANQADCgEIAQABNQAECgoKKwAhAGobAA==.',
Ky='Kymira:BAABNQAECn8uAAIZAAoKOBpVBwDIAgAZAAoKOBpVBwDIAgAAAA==.',
La='Lace:BAABNQAECn9QAAMaAAoKjSSwCQB/AwAaAAoKfyKwCQB/AwAbAAIK8yQ1BQDWAAAAAA==.Lanzen:BAAANQADCgEIAQAAAA==.Larrfena:BAABNQAECn8xAAICAAoKNRdAVwBtAgACAAoKNRdAVwBtAgAAAA==.Lavatory:BAAANQADCgEIAgAAAA==.Lazarou:BAAANQAECgUIBgAAAA==.',
Le='Legsday:BAAANQAECgIIAgAAAA==.Lementz:BAACNQAFFH8OAAIhAAQKVhHPEgBDAQAhAAQKVhHPEgBDAQA1AAQKfyAAAiEACQp4HjEhAAUDACEACQp4HjEhAAUDAAAA.',
Li='Liadres:BAAANQADCgIIAgAAAA==.Liante:BAAANQADCgcIFAABNQAECgMIBgAFAAAAAA==.Libellule:BAAANQADCgEIAQAAAA==.Lilboat:BAAANQAECgEIAQAAAA==.Lillia:BAABNQAECn8uAAIaAAkK/hBBEQC5AQAaAAkK/hBBEQC5AQAAAA==.Lillybell:BAAANQADCgUIBQAAAA==.Littleboyz:BAAANQADCgcIBwAAAA==.',
Lo='Loop:BAABNQAFFH8IAAIEAAgKagG+EgCHAAAEAAgKagG+EgCHAAAAAA==.Loopku:BAAANQAECggICAAAAA==.Lorinash:BAAANQADCgYICQAAAA==.Lothelo:BAAANQAECgEIAgABNQAECggIFAAOAAMdAA==.',
Lu='Lumpia:BAABNQAECn8hAAMHAAoKkxohLwB0AgAHAAoKkxohLwB0AgAQAAIKuwWvvQBNAAAAAA==.',
Lv='Lvel:BAAANQADCgYICgAAAA==.',
['Lë']='Lëeloo:BAAANQAECgYIBgABNQAECgoKNgAaAGMeAA==.',
Ma='Machinism:BAAANQADCgIIAgABNQADCgcJCAAFAAAAAA==.Maey:BAABNQAECn8vAAMBAAoKZxZlTAAjAQABAAoKzBNlTAAjAQAcAAEKASHLOwBQAAAAAA==.Magoobers:BAAANQADCgEIAQAAAA==.Maktah:BAABNQAECn8rAAMhAAoKahsELwDAAgAhAAoKahsELwDAAgAgAAEK/AiiNAA+AAAAAA==.Malpractice:BAAANQAECgUIBgABNQAECggIFAALACYPAA==.Maybesinged:BAABNQAECn8yAAIBAAoKYhkmKQB1AQABAAoKYhkmKQB1AQAAAA==.',
Me='Meanboy:BAAANQAECgMIAwAAAA==.Meishra:BAAANQADCgcICQAAAA==.Mentos:BAABNQAECn8zAAQkAAoKjx+HBQA5AwAkAAoKjx+HBQA5AwAPAAIK4xQSQQCYAAAlAAEKCRNJIwA5AAAAAA==.',
Mi='Midgetninja:BAAANQAECgEIAQABNQAECgoKFgAZAGkeAA==.Miltank:BAABNQAECn8wAAIOAAoK6BxFPgDaAgAOAAoK6BxFPgDaAgAAAA==.Minaqt:BAAANQADCgEIAQAAAA==.Minatory:BAABNQAECn8kAAIVAAoKqRlvGACZAgAVAAoKqRlvGACZAgAAAA==.Mionn:BAABNQAECn8eAAMOAAoKSRqqawBaAgAOAAkKEhyqawBaAgAWAAEK7gokHwE3AAAAAA==.Misfires:BAAANQADCgEIAgAAAA==.',
Ml='Mlleena:BAABNQAECn8fAAIbAAcKLRFzAwAPAQAbAAcKLRFzAwAPAQAAAA==.',
Mo='Moddim:BAAANQADCgUIBQAAAA==.Modotz:BAAANQADCgEIAQAAAA==.Mogg:BAAANQAECgEIAQAAAA==.Moghoul:BAAANQAECgQIBQAAAA==.Montorgo:BAAANQADCgYIBwAAAA==.Moofi:BAAANQADCggIDgABNQAECggIFwAgAP8IAA==.Mooncake:BAABNQAECn8fAAMkAAkKIQdqGgCiAQAkAAkKIQdqGgCiAQAlAAIKhAJWIgBBAAAAAA==.Moosiah:BAAANQADCgcIBwAAAA==.Mossfire:BAAANQAECgEIAgABNQAECggIFAAiAD4YAA==.Motoko:BAABNQAECn8cAAMZAAkKXho/CgByAgAZAAkKXho/CgByAgAmAAEKQALEVAAgAAAAAA==.',
Mu='Musesong:BAAANQADCgMIAwAAAA==.',
['Mø']='Møø:BAAANQAECgYIBgABNQAECgkJHwACADQMAA==.Møøfi:BAABNQAECn8XAAIgAAgK/wiCEQDrAAAgAAgK/wiCEQDrAAAAAA==.',
Na='Naianasha:BAAANQAECggIDwAAAA==.Nameless:BAABNQAECn82AAIBAAoKUBAqmABQAgABAAoKUBAqmABQAgAAAA==.Narc:BAAANQAECgUIEQAAAA==.',
Ne='Necroraise:BAAANQADCgIIAgAAAA==.Neeraj:BAABNQAECn8iAAICAAkKOhVqGAC4AQACAAkKOhVqGAC4AQAAAA==.Nevergreen:BAAANQABCgIIAgAAAA==.',
Ni='Nightreaver:BAAANQAECgQIBgABNQAECgoKFgAZAGkeAA==.Nippiest:BAAANQADCgEIAQAAAA==.',
No='Nokzash:BAABNQAECn8XAAIWAAoK6BtHKQDDAgAWAAoK6BtHKQDDAgAAAA==.Noova:BAABNQAECn8uAAIBAAoKfR5DEwDMAQABAAoKfR5DEwDMAQAAAA==.',
Ny='Nyang:BAAANQAECgYIDQAAAA==.Nythendrac:BAAANQADCgQIBAABNQAECgoKLQAcAOYWAA==.',
Ob='Obliverat:BAAANQAECggIEQAAAA==.',
Od='Odysseus:BAAANQADCgIIBQAAAA==.',
Oo='Oongaboonga:BAABNQAECn8sAAIEAAgKPB2zFgCuAQAEAAgKPB2zFgCuAQAAAA==.',
Or='Orcaneblast:BAACNQAFFH8IAAIBAAMKWRS7HACIAAABAAMKWRS7HACIAAA1AAQKfy4AAgEACgovHblJAO8CAAEACgovHblJAO8CAAAA.Orcsoup:BAABNQAECn8WAAIhAAcKpxtUVgAhAgAhAAcKpxtUVgAhAgABNQAECgoKKQAKAC4bAA==.',
Pa='Paddord:BAAANQADCggIDAAAAA==.Pandemnik:BAAANQAECgUIBwAAAA==.Paranoià:BAAANQADCgIIAgABNQAECgEIAQAFAAAAAA==.',
Pe='Penance:BAAANQAECgYICwAAAA==.Percible:BAAANQADCgYIBwAAAA==.',
Ph='Phoeniex:BAAANQAECgEIAQABNQAECgoKFgAZAGkeAA==.',
Pi='Pivnert:BAABNQAECn8kAAQBAAcKgRxEGwCiAQABAAcKRBpEGwCiAQAcAAIKbBi8LQCPAAAdAAIKVxjZCACJAAAAAA==.',
Pl='Plums:BAAANQAECggIBwAAAA==.',
Po='Popdkook:BAAANQADCgYIFQAAAA==.',
Pr='Proko:BAAANQADCggICQAAAA==.',
Ps='Psychopump:BAAANQAECggIDgAAAA==.',
['Pü']='Pünish:BAACNQAFFH8MAAIHAAUKRhyhDABDAQAHAAUKRhyhDABDAQA1AAQKf00ABAcACgp9I/0GAI4DAAcACgp9I/0GAI4DACMAAwpxFcR7ALgAABAAAQpfBRvSACsAAAAA.',
Qq='Qqpewpew:BAAANQAECggIBAAAAA==.',
Qu='Quinn:BAAANQADCgIJAgABNQAECgoKFgAZAGkeAA==.',
Ra='Rabit:BAAANQADCgUIBQAAAA==.Raelina:BAABNQAECn8lAAMBAAkKhSHdTADnAgABAAkKsx/dTADnAgAcAAIKoCISJwC6AAABNQAFFAkJJgABAJwdAA==.Ragingiscool:BAAANQADCggIDwAAAA==.Rail:BAAANQAECgEIAQAAAA==.Rajank:BAAANQADCgQIBAAAAA==.Rallek:BAABNQAECn8eAAIWAAgKLRF4bADSAQAWAAgKLRF4bADSAQAAAA==.Ranuggul:BAAANQAECgEIAQAAAA==.Rarn:BAAANQADCgMIAwABNQAECgkJKgAQAD4bAA==.Ratsrepus:BAAANQADCgcICwAAAA==.Raza:BAAANQAECgQIDAABNQAFFAUIDAAHAEYcAA==.',
Re='Read:BAAANQAECgQIDQAAAA==.Reddawn:BAAANQADCgcICAAAAA==.Remeras:BAAANQAECggIEgAAAA==.',
Ri='Riggymortus:BAAANQADCgEIAgAAAA==.Riken:BAABNQAECn8UAAImAAcKvQ3qJABUAQAmAAcKvQ3qJABUAQAAAA==.Ripblast:BAAANQAECgEIAQABNQAECgoKFgAZAGkeAA==.',
Ro='Roadi:BAAANQAECgUIBgABNQAECgoKNgAaAGMeAA==.Roxer:BAABNQAECn8hAAIWAAoKGhH4IgBYAQAWAAoKGhH4IgBYAQAAAA==.',
Ru='Rukaa:BAAANQAECgIIAwAAAA==.Rummyy:BAABNQAECn8WAAMVAAkKZBspFgCyAgAVAAkKZBspFgCyAgAUAAEKkwwVjwA8AAAAAA==.',
Ry='Rycken:BAABNQAECn8sAAMKAAoKSA3ZKQDQAQAKAAoKSA3ZKQDQAQALAAgKUhjHBgDLAQAAAA==.',
Sa='Saeylva:BAAANQAECgQIBwAAAA==.Saosis:BAAANQAECgYIBgAAAA==.Savage:BAAANQADCgIIAgAAAA==.Sayurri:BAAANQADCgEJAQAAAA==.',
Sc='Scribble:BAAANQAECgQICAAAAA==.Sculper:BAAANQAECgYIEAAAAA==.',
Se='Senica:BAABNQAECn8cAAIMAAoKNyD5AQBjAwAMAAoKNyD5AQBjAwAAAA==.Seriphina:BAAANQADCggICAAAAA==.',
Sg='Sgornyweaver:BAAANQADCgUJBQAAAA==.',
Sh='Shabbarankzz:BAABNQAECn8xAAIjAAoKmxBeEwBsAQAjAAoKmxBeEwBsAQAAAA==.Shadetotem:BAABNQAECn8iAAIgAAcKqxErCgBTAQAgAAcKqxErCgBTAQAAAA==.Shammyblammy:BAAANQADCgEIAQAAAA==.Sheshotu:BAAANQADCggIFwAAAA==.Shiftor:BAAANQADCggIEgAAAA==.Shinedown:BAAANQADCgMIAwAAAA==.Shmoopy:BAAANQAECgIIAgAAAA==.Shradehn:BAABNQAECn8ZAAIUAAkK5RXMLAA9AgAUAAkK5RXMLAA9AgAAAA==.Shutitdown:BAAANQAECgUIBQAAAA==.',
Si='Sisterswede:BAABNQAECn8dAAIRAAkK/h1LEwDPAgARAAkK/h1LEwDPAgAAAA==.Sizzle:BAABNQAECn8aAAIBAAkKzBBAowA7AgABAAkKzBBAowA7AgAAAA==.',
Sm='Smokeahontas:BAAANQAECgQIDQAAAA==.Smokindots:BAAANQAECgcIEAABNQAFFAQICwAIAD8SAA==.Smokingreen:BAAANQADCggICQABNQAFFAQICwAIAD8SAA==.Smokinmyrrh:BAAANQAECgUIBQABNQAFFAQICwAIAD8SAA==.Smokinmyth:BAAANQADCgcICAAAAA==.Smokinpsalm:BAAANQAECgcIEgABNQAFFAQICwAIAD8SAA==.Smokintotem:BAACNQAFFH8LAAIIAAQKPxJwCgDYAAAIAAQKPxJwCgDYAAA1AAQKfzcAAwgACgorIoMMAFwDAAgACgorIoMMAFwDACEABgqBGllsANsBAAAA.',
Sn='Snawkin:BAAANQADCgEIAQAAAA==.',
Sp='Spaghet:BAEANQAECgYIDAABNQAFFAUICgAEADYSAA==.Sparklnmagic:BAAANQAECgEIAQAAAA==.Spore:BAAANQADCgIIAgAAAA==.',
Sq='Squigboogalo:BAAANQADCgEIAQAAAA==.',
St='Steadyrock:BAABNQAECn8ZAAMLAAoK7xRCNwAzAgALAAoK7xRCNwAzAgAKAAEK8QR4eAAuAAAAAA==.Stemi:BAAANQAECgEIAQAAAA==.Steveirwin:BAAANQADCggJCQAAAA==.Stiffsheets:BAAANQAECgUIBQABNQAECgoKFgAZAGkeAA==.Stiltz:BAAANQADCgEIAQAAAA==.Stormywind:BAABNQAECn8ZAAIhAAgKaQdojQCCAQAhAAgKaQdojQCCAQAAAA==.Stormz:BAABNQAECn8vAAILAAoKaxGKDQBzAQALAAoKaxGKDQBzAQAAAA==.',
Su='Sunblade:BAABNQAECn8VAAIQAAcKGhVyWwCFAQAQAAcKGhVyWwCFAQABNQAECgoKNgABAFAQAA==.Sundayskoolz:BAAANQADCgUIBQAAAA==.Sundowning:BAAANQAECgUIBQAAAA==.Sunreaver:BAAANQAECggIDQAAAA==.Supercappy:BAAANQAECgEIAQAAAA==.Suraegi:BAAANQAECgIIAgAAAA==.',
Sw='Swabby:BAAANQADCgEIAQAAAA==.Swiftdragon:BAABNQAECn8WAAMZAAoKaR7GBAAlAwAZAAgK6iPGBAAlAwAYAAIK5g0bLABlAAAAAA==.',
Ta='Taapfer:BAAANQAECgMIAwABNQAECgoKIgABALsUAA==.Tackyh:BAABNQAECn8iAAICAAcKmxx8dwAgAgACAAcKmxx8dwAgAgAAAA==.Takamatsu:BAABNQAECn8wAAMMAAkKXiRDBQCxAgAMAAkKXiRDBQCxAgATAAMKDA6LGgCWAAAAAA==.Taku:BAAANQAECgIIBAAAAA==.Tanktoucher:BAAANQAECggIAQAAAA==.Tar:BAABNQAECn8fAAMCAAkKNAzOuwCMAQACAAcKsw3OuwCMAQASAAMKFAiGZACZAAAAAA==.Taxii:BAABNQAECn8sAAMEAAoKKSXNJQAiAwAEAAkKTCLNJQAiAwANAAgKJSXpBgCRAgAAAA==.',
Te='Tealnujabes:BAAANQAECgYIBwAAAA==.Teapots:BAAANQAFFAIIAwAAAA==.Tempi:BAAANQABCgMIAwABNQAECgYIBgAFAAAAAA==.Tenpiece:BAAANQADCgMIAwAAAA==.',
Th='Thayelith:BAAANQAECgUIBAAAAA==.Thedeus:BAABNQAECn8UAAIOAAgKAx38UwCZAgAOAAgKAx38UwCZAgAAAA==.Thellira:BAAANQADCgEIAQAAAA==.Thermaul:BAABNQAECn8yAAIgAAoKbRl0AwDmAQAgAAoKbRl0AwDmAQAAAA==.Threebeans:BAABNQAECn8pAAMKAAoKLhsGDQD+AgAKAAoKLhsGDQD+AgALAAcKrBHwRgDSAQAAAA==.Thromir:BAACNQAFFH8HAAMOAAQKGR28EQA0AQAOAAMKbiC8EQA0AQAWAAMKyA8rGADjAAA1AAQKfyQAAxYACgobHTQXAB8DABYACQoEIDQXAB8DAA4ABwoJJpQYAMEBAAAA.Thyrn:BAABNQAECn8qAAIQAAkKPhuCIgChAgAQAAkKPhuCIgChAgAAAA==.',
Ti='Tirare:BAABNQAECn8iAAIHAAgKvRpJNABZAgAHAAgKvRpJNABZAgAAAA==.',
Tr='Tri:BAABNQAECn8fAAIOAAcKtCI3HACxAQAOAAcKtCI3HACxAQAAAA==.Tristam:BAAANQAECgEIAQAAAA==.',
Tu='Tuneleitor:BAABNQAECn8fAAInAAoKwxCWAQC1AQAnAAoKwxCWAQC1AQAAAA==.Turdferguson:BAAANQADCgcIBwABNQAFFAIIBgAZALIiAA==.Turgrok:BAABNQAECn8XAAMSAAgKUAuoNACoAQASAAgKUAuoNACoAQACAAEKeQZg0QA4AAAAAA==.',
Tw='Twill:BAAANQAECgEIAQAAAA==.Twothang:BAABNQAECn8UAAMQAAgKOAiyagBJAQAQAAgKoweyagBJAQAjAAIKMwWlnwBRAAAAAA==.',
Ty='Tyllan:BAABNQAECn8yAAMBAAoKjx3LMgBaAQABAAkKiRvLMgBaAQAcAAMKMB0RCQD6AAAAAA==.',
['Tâ']='Tâku:BAAANQADCggIHgAAAA==.',
Up='Upgrayedd:BAAANQAECgQIBQAAAA==.',
Va='Vainhellsing:BAAANQAECgUIEgAAAA==.Vanzier:BAAANQAECggIEgAAAA==.Vaxis:BAABNQAECn8gAAICAAoKAg7uggAGAgACAAoKAg7uggAGAgAAAA==.',
Vi='Vid:BAACNQAFFH8QAAImAAYKpxbhAgDmAQAmAAYKpxbhAgDmAQA1AAQKfyoAAiYACgrxHSMJAPkCACYACgrxHSMJAPkCAAAA.',
Vo='Voidillusion:BAAANQAECgMIBQABNQAECgYICgAFAAAAAA==.',
Wa='Watooie:BAAANQADCgYIBgAAAA==.',
We='Weave:BAAANQADCgEIAQABNQAECgoKUAAaAI0kAA==.Wernov:BAABNQAECn8kAAMhAAkKNhuCMgCwAgAhAAkKNhuCMgCwAgAIAAUK5BA2rAAYAQABNQAECgkJJgAMAAsYAA==.',
Wh='Whitetail:BAAANQAECgIIAgAAAA==.',
Wi='Wichan:BAABNQAECn8nAAIJAAoKexo3DgCAAgAJAAoKexo3DgCAAgAAAA==.Wildsniper:BAAANQAECgEIAQAAAA==.Wildstrike:BAAANQADCgYIBwABNQAECgkJHAAZAF4aAA==.Wiziviji:BAAANQAECgcIDgAAAA==.',
Wo='Woodrow:BAAANQADCgcICAAAAA==.',
Ws='Ws:BAAANQAECgIIAgAAAA==.',
Xa='Xanorea:BAAANQADCgYIBgABNQAECgcIFwAkAO0QAA==.',
Xd='Xdknight:BAAANQADCgEIAQAAAA==.',
Xe='Xerø:BAAANQAECgUICAAAAA==.',
Xr='Xray:BAABNQAECn8fAAIBAAkKHA6vvgAHAgABAAkKHA6vvgAHAgAAAA==.',
Xt='Xtra:BAAANQAECgMIAwAAAA==.Xtreme:BAAANQADCggIDQAAAA==.',
Xw='Xwarf:BAAANQADCgEIAQAAAA==.',
Ya='Yamii:BAABNQAECn8aAAMiAAoKPhqvDgBBAgAiAAgK2huvDgBBAgAEAAUK0g81dgCwAAABNQAECgoKIQAHAJMaAA==.Yaphetkotto:BAAANQADCgcJCAAAAA==.Yawnk:BAABNQAECn8VAAMmAAkKswnqMQDaAAAmAAcKiAvqMQDaAAAYAAYKDwrfIACmAAAAAA==.',
Yu='Yunsky:BAAANQAECgIIBQAAAA==.',
Za='Zanber:BAAANQADCgIIAwAAAA==.Zandrakar:BAABNQAECn8vAAQIAAoKWxczOgB2AgAIAAoKWxczOgB2AgAgAAEKAACDOAAtAAAhAAEKPQViSQEpAAAAAA==.Zanosuke:BAAANQAECggIEgAAAA==.Zaria:BAABNQAECn8eAAIaAAkKpBGVcgAJAgAaAAkKpBGVcgAJAgAAAA==.Zaryor:BAABNQAECn8WAAMYAAcKIRTjMgB/AQAYAAcKIRTjMgB/AQAZAAQKYhIiIADkAAAAAA==.Zaun:BAAANQAECgUIBQAAAA==.',
Ze='Zentul:BAAANQAECgQIBAAAAA==.Zerica:BAAANQAECgIIAgAAAA==.Zerika:BAABNQAECn8wAAIMAAoKxSFcCABiAgAMAAoKxSFcCABiAgAAAA==.',
Zh='Zhaohu:BAAANQADCgYIBgAAAA==.',
Zi='Zigzwag:BAAANQAECgIIBgAAAA==.Zionna:BAAANQAECgcIEAABNQAECggIFAALACYPAA==.Zitos:BAABNQAECn88AAMOAAoKYCQ+BgDIAwAOAAoKYCQ+BgDIAwAWAAEKfghNKgEsAAABNQAECgoKPAAOAGAkAA==.',
Zo='Zomgqq:BAABNQAECn8bAAMgAAoKqhg/CwC9AgAgAAoKqhg/CwC9AgAIAAQK7Q0X0gDDAAAAAA==.',
Zw='Zwagster:BAAANQAECgUIBgAAAA==.',
Zy='Zydis:BAAANQAECgUICgAAAA==.Zyggy:BAAANQAECgcIEAAAAA==.Zynfanatic:BAAANQAECgcIDAABNQAECgoKKQAKAC4bAA==.',
['Än']='Ännihilation:BAAANQAECgIIAgAAAA==.',
['Èe']='Èepy:BAAANQAECgEIAQABNQAECgUIBQAFAAAAAA==.',
['És']='Éstéla:BAABNQAECn8nAAICAAoKORRVWABqAgACAAoKORRVWABqAgAAAA==.',
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
