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

local lookup = {'Druid-Balance','Mage-Arcane','Paladin-Retribution','Unknown-Unknown','Priest-Holy','Priest-Shadow','Druid-Feral','Priest-Discipline','Shaman-Elemental','DemonHunter-Vengeance','DemonHunter-Devourer','Mage-Fire','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','DeathKnight-Blood','Shaman-Restoration','Evoker-Devastation','Druid-Restoration','Warrior-Arms','DeathKnight-Frost','Monk-Brewmaster','Monk-Windwalker','Paladin-Holy','DeathKnight-Unholy','Rogue-Assassination','Druid-Guardian','Warlock-Destruction','Warlock-Demonology','Rogue-Outlaw','Shaman-Enhancement','Warrior-Protection','Warlock-Affliction','Evoker-Preservation','Monk-Mistweaver','Rogue-Subtlety','Mage-Frost','Hunter-Survival','Warrior-Fury','DemonHunter-Havoc','Evoker-Augmentation',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Accost:BAAANQADCgcIDQAAAA==.Achendron:BAAANQADCgUIBQABNQAFFAgIIAABAOAfAA==.Acronica:BAAANQAECgUIEgAAAA==.',
Ad='Addilynn:BAAANQABCgEIAQAAAA==.',
Ak='Akassa:BAAANQADCgcICwAAAA==.Aknologia:BAAANQAECgUICwABNQAECgoKGwACAPcOAA==.',
Al='Alecto:BAABNQAECn8xAAIDAAoKcgj6pgBqAQADAAoKcgj6pgBqAQAAAA==.Allele:BAAANQAECgMIAwAAAA==.Allet:BAAANQADCggIFwABNQAECggIEwAEAAAAAA==.',
Am='Amarah:BAACNQAFFH8FAAIFAAQKTgYYHQDsAAAFAAQKTgYYHQDsAAA1AAQKf0MAAwUACgo5IEMeANcCAAUACgo5IEMeANcCAAYAAQoAAP1wAAAAAAAA.Amazome:BAABNQAECn8cAAIHAAoKzBn6BwBcAgAHAAoKzBn6BwBcAgAAAA==.Ameilie:BAACNQAFFH8LAAMFAAQK1h8bEQB4AQAFAAQK1h8bEQB4AQAIAAIK9QWtAQB1AAA1AAQKf0kABAgACgoXISYDAE4CAAUACgrCIMYdAPoCAAgACQqbGCYDAE4CAAYAAQoACuBaADoAAAAA.',
An='Anapuwae:BAABNQAECn8UAAIJAAYKSA0CqwA+AQAJAAYKSA0CqwA+AQAAAA==.Animehero:BAABNQAECn8qAAMKAAoKVR2gBQDRAgAKAAgKHCCgBQDRAgALAAYKsRdwHQClAQAAAA==.',
Ar='Arcant:BAABNQAECn8sAAMCAAoKzRmlZwDUAQACAAoKzRmlZwDUAQAMAAEKQQzPCwA6AAAAAA==.Ardicov:BAAANQADCgYICwAAAA==.Argadin:BAAANQAECgcICAABNQAECgoKMAANAG0iAA==.Arglock:BAAANQAECgYIBwABNQAECgoKMAANAG0iAA==.Argrekh:BAABNQAECn8wAAMNAAoKbSLQCgCHAwANAAoKbSLQCgCHAwAOAAEKQQ/phgA3AAAAAA==.Argreks:BAAANQAECgYIBgABNQAECgoKMAANAG0iAA==.Argrekt:BAAANQAECgIIAgABNQAECgoKMAANAG0iAA==.Aridol:BAAANQADCgYIBgAAAA==.Arigön:BAAANQADCgYICAAAAA==.Aronna:BAAANQADCgYICAAAAA==.Arosea:BAAANQADCgYIBgAAAA==.Arthaslk:BAACNQAFFH8GAAIDAAUKvhpFGAC+AAADAAUKvhpFGAC+AAA1AAQKf1MAAwMACgrmJekCAOYDAAMACgrmJekCAOYDAA8ABAoMD/BFAHsAAAAA.Aryssol:BAAANQAECgIIAgAAAA==.',
At='Ate:BAABNQAECn8nAAIQAAgKfBBMMQB5AQAQAAgKfBBMMQB5AQAAAA==.Atlette:BAAANQAECgMIAwAAAA==.Attman:BAACNQAFFH8UAAIRAAUKDBY7DgBZAQARAAUKDBY7DgBZAQA1AAQKf1AAAxEACgoIJLYPAEYDABEACgoIJLYPAEYDAAkABArVElmCAPQAAAAA.',
Au='Auradawn:BAAANQADCgcIDwAAAA==.',
Ba='Backwater:BAAANQAECgQIBAABNQAECggIEwAEAAAAAA==.Badhands:BAAANQAECgIIAgAAAA==.Baeator:BAAANQAECgEIAQABNQAFFAcIGAASAO0PAA==.Barneystins:BAAANQABCgEIAgABNQADCgQIBAAEAAAAAA==.',
Be='Bearmane:BAACNQAFFH8KAAIBAAQK3B+4DAASAQABAAQK3B+4DAASAQA1AAQKfzQAAwEACgoyI58OAFUDAAEACgoyI58OAFUDABMAAgoSDgVfAGYAAAAA.Beastarsfan:BAABNQAECn8oAAIJAAoKnyOPCwCLAwAJAAoKnyOPCwCLAwAAAA==.Behmow:BAABNQAECn9LAAIUAAoKvCboAwBvAwAUAAoKvCboAwBvAwAAAA==.Belithel:BAAANQAECgQIBgABNQAECgoKJwAJAHgYAA==.Bencreepin:BAABNQAECn8eAAMQAAcK2hD0SAALAQAQAAYK2hD0SAALAQAVAAMKCwj2nABYAAAAAA==.Bernoulli:BAABNQAECn83AAMWAAoK6RfpBQAeAgAWAAoK6RfpBQAeAgAXAAEKAADoagAAAAAAAA==.',
Bi='Bigspitter:BAAANQADCgYIBgABNQAECgoKOAACAHAlAA==.Bis:BAAANQADCgUJBQABNQAECgkJFgACAD0cAA==.',
Bl='Blessedxx:BAAANQAECgUIBgAAAA==.Bloodboo:BAAANQADCgQIBAAAAA==.Bloodyhpally:BAACNQAFFH8fAAIYAAkKGhZDAwBoAgAYAAkKGhZDAwBoAgA1AAQKfy4AAxgACgrSHmArALoCABgACgrSHmArALoCAAMAAgoXD4lmAXsAAAAA.',
Bo='Boopsnoopems:BAABNQAECn8gAAIPAAYKzw96OQC1AAAPAAYKzw96OQC1AAAAAA==.Borderline:BAAANQAECgUIBQABNQAFFAUIDgAXAFoEAA==.',
Br='Bradcrit:BAAANQAECgIIAQAAAA==.',
Bu='Bubble:BAABNQAECn8aAAMYAAcKUgfJuQAJAQAYAAYKIAfJuQAJAQADAAUKgggXJAHjAAAAAA==.Bulldoser:BAAANQADCgQIBAAAAA==.Burrfoot:BAAANQAECgIIAwAAAA==.Bustah:BAAANQAECgcIEgABNQAECggIFwAZAMQbAA==.',
Bw='Bwoodmorgan:BAAANQAECgYIDgAAAA==.',
By='Byron:BAAANQAECgQIBgAAAA==.',
Ca='Calene:BAACNQAFFH8MAAIaAAgKUg0kBQDkAQAaAAgKUg0kBQDkAQA1AAQKf1MAAhoACgonJI8DAP8CABoACgonJI8DAP8CAAAA.Candy:BAAANQAECgMIBQAAAA==.Cannedcorn:BAAANQAECgIIAgAAAA==.Caperusin:BAAANQAECgUICAAAAA==.Casare:BAAANQADCgYIFgAAAA==.Cayde:BAAANQADCgYJBgABNQAFFAUICgAOAGcNAA==.',
Ce='Celestinee:BAAANQAECgYIEwAAAA==.Celyda:BAAANQAECgUICAAAAA==.Cenarian:BAAANQABCgUIBwAAAA==.',
Ch='Chabotloe:BAAANQAECgMIBQAAAA==.Chape:BAABNQAECn8dAAMYAAkKvhcQPgBsAgAYAAkKvhcQPgBsAgADAAYK/BBE7wA+AQABNQABCgEIAQAEAAAAAA==.Chence:BAAANQADCgYIBgAAAA==.Chochalinda:BAABNQAECn8dAAMHAAgKvxHBFgCNAQAHAAcKXBDBFgCNAQAbAAUK8xTfLQArAQAAAA==.',
Ci='Cinderlee:BAABNQAECn8VAAIcAAYKNgXBFgCdAAAcAAYKNgXBFgCdAAAAAA==.',
Co='Colexn:BAABNQAECn8lAAQVAAkKwBZnOgDoAQAVAAkKwBZnOgDoAQAZAAIKMhDJwQBnAAAQAAEKAAAHvAAAAAAAAA==.Cong:BAACNQAFFH8FAAIUAAQK3ghxIAD/AAAUAAQK3ghxIAD/AAA1AAQKfycAAhQACgqnG/MnABoDABQACgqnG/MnABoDAAAA.Corg:BAAANQADCgYIBgAAAA==.Cornchipz:BAABNQAECn8bAAICAAoK9w5e0ADlAQACAAoK9w5e0ADlAQAAAA==.',
Cr='Crapsack:BAAANQABCgEIAQAAAA==.Croski:BAAANQADCgEIAQAAAA==.Cryonidus:BAAANQAECgEIAQAAAA==.',
Cu='Curves:BAAANQAECgEIAQAAAA==.',
Cy='Cypressa:BAAANQADCgQIBAAAAA==.',
Da='Daangalanng:BAABNQAECn8pAAIYAAoKyBapRABTAgAYAAoKyBapRABTAgAAAA==.Dabberoni:BAAANQAECgEIAgAAAA==.Daegra:BAABNQAECn8pAAIaAAoKXByaDwAEAwAaAAoKXByaDwAEAwAAAA==.Dankkush:BAAANQADCgQIBAAAAA==.Darkacedia:BAABNQAECn8vAAMdAAkKihXHTQBrAgAdAAkKihXHTQBrAgAcAAMKKwp9TwCRAAAAAA==.Darkzetta:BAAANQAECgIIAgABNQAFFAYIDAAGAKoLAA==.Datbish:BAAANQAECgIIAgAAAA==.',
De='Deadlift:BAABNQAECn8tAAIZAAoKKByBEABtAgAZAAoKKByBEABtAgAAAA==.Deadlyhoof:BAAANQAECgMIAwAAAA==.Dealosed:BAABNQAECn8ZAAMaAAgKphkIKwA+AgAaAAgKeRkIKwA+AgAeAAQKDhXyEQDsAAAAAA==.Deathawolf:BAAANQAECgEIAQAAAA==.Deathbyaoe:BAAANQAECggICAAAAA==.Deathkilera:BAAANQADCgUIBwAAAA==.Defy:BAAANQADCgYIBgAAAA==.Delenn:BAABNQAECn8XAAIHAAgKZxrsDQA6AgAHAAgKZxrsDQA6AgAAAA==.Demonclawz:BAAANQAECgYIBgAAAA==.Demonnyaa:BAAANQADCgcIBwAAAA==.Deneb:BAAANQADCgIIAgABNQAECgkJFwAGAIYgAA==.Derzy:BAAANQADCgIIAgAAAA==.Dewygirl:BAAANQADCgcICgAAAA==.',
Dh='Dhuumystic:BAAANQADCgEIAQAAAA==.',
Di='Disastapyre:BAAANQAECgIIAgABNQAFFAQIBQAfAFgIAA==.Disastasmite:BAAANQADCgIIBAABNQAFFAQIBQAfAFgIAA==.Dive:BAABNQAECn8WAAICAAkKPRyyYwC3AgACAAkKPRyyYwC3AgAAAA==.',
Do='Doogru:BAABNQAECn9DAAIgAAoK7Ru/CAA7AgAgAAoK7Ru/CAA7AgAAAA==.Doogtwo:BAAANQADCggIHAABNQAECgoKQwAgAO0bAA==.Doryndoran:BAAANQAECgQIBQAAAA==.Dorynhashots:BAAANQADCgUIBQAAAA==.Dotproduct:BAAANQADCgEIAQABNQADCgIIAgAEAAAAAA==.Dotsrock:BAABNQAECn80AAMhAAoK7hS3BQAOAgAhAAoK7hS3BQAOAgAdAAUKcQcM4QB9AAAAAA==.Dovah:BAAANQADCgIIAgAAAA==.',
Dr='Dragoneggs:BAABNQAECn8jAAMSAAoKBBkXDQCRAgASAAoKBBkXDQCRAgAiAAoKBQp2HwDdAQAAAA==.Dragonforce:BAAANQADCggIEgAAAA==.Drakonutz:BAAANQAECgYIDwAAAA==.Draxx:BAAANQAECggIDQABNQAECggIEgAEAAAAAA==.Drañzer:BAAANQAECgEIAgAAAA==.Dreammachine:BAAANQAECgcIBwAAAA==.Drjoel:BAAANQADCgcIEQAAAA==.Drunkenutz:BAABNQAECn8ZAAQXAAkK7g09PQCsAAAWAAUKLxCcIQDQAAAXAAUKPgw9PQCsAAAjAAQKcA9TKgCdAAAAAA==.Drâx:BAAANQAECggICgABNQAECggIEgAEAAAAAA==.Dräx:BAAANQAECggIEgAAAA==.',
Dw='Dwallen:BAAANQADCgIIAgAAAA==.Dwightschrut:BAAANQADCgQIBAAAAA==.',
['Dä']='Dälf:BAAANQAECgIIAgABNQAFFAcICQAPABsVAA==.',
Ea='Earthshocker:BAABNQAECn8iAAMJAAoKzxMFMAAEAgAJAAoKzxMFMAAEAgARAAEKXAA4DAENAAAAAA==.',
Ed='Edirii:BAAANQABCgIIAgAAAA==.',
El='Elenix:BAAANQAECgcIAQAAAA==.Elki:BAAANQADCgQIBgAAAA==.Elmesia:BAABNQAECn8UAAICAAcKTQjwGAFiAQACAAcKTQjwGAFiAQAAAA==.Eloris:BAABNQAECn8lAAILAAgK7RxGHABzAgALAAgK7RxGHABzAgAAAA==.Elpato:BAAANQADCgcIBwABNQAECgoKOAACAHAlAA==.Elthyn:BAAANQAECggIDwAAAA==.Elvar:BAAANQAECgEIAQAAAA==.',
Em='Emachine:BAAANQADCggICAABNQAECgIIAgAEAAAAAA==.Emeraldrin:BAAANQADCgIIAgAAAA==.Emz:BAABNQAECn89AAIeAAkK7yA1AQCdAgAeAAkK7yA1AQCdAgAAAA==.',
En='Eniar:BAAANQAECgQIBgAAAA==.',
Er='Erakk:BAAANQADCgEIAgAAAA==.Erianda:BAAANQABCgQIBAAAAA==.Eric:BAABNQAECn8eAAIUAAgKNBqiegAoAgAUAAgKNBqiegAoAgAAAA==.Eroninja:BAAANQAECgYICAABNQAECgoKJwAJAHgYAA==.Erín:BAABNQAECn8qAAIdAAcKbBEzgwBEAQAdAAcKbBEzgwBEAQAAAA==.',
Es='Estropajo:BAAANQAECgEIAQAAAA==.',
Eu='Eurong:BAACNQAFFH8HAAIBAAQKsxE4FgAGAQABAAQKsxE4FgAGAQA1AAQKfzcAAgEACgoCI00IAA0DAAEACgoCI00IAA0DAAAA.',
Ez='Ezynuff:BAAANQAECgYIEgAAAA==.',
Fa='Faner:BAAANQADCgEIAgABNQAECgEIAQAEAAAAAA==.Fapple:BAAANQAECgUICQABNQAECgoKOQAiACMjAA==.Fatesworn:BAAANQADCgcIBwAAAA==.Faïry:BAABNQAECn9AAAINAAoKSSSrBgBRAwANAAoKSSSrBgBRAwAAAA==.',
Fe='Feaughoeren:BAABNQAECn8nAAMfAAoK5AofEgDcAQAfAAoK5AofEgDcAQARAAkKpQWabgBRAQAAAA==.Felwyrm:BAABNQAECn8sAAIdAAkKgRd4UABjAgAdAAkKgRd4UABjAgABNQAFFAUIDgAXAFoEAA==.Feralina:BAAANQABCgIIAgAAAA==.Feralshmeral:BAAANQABCgQIBAABNQAECgoKIgANAKAhAA==.',
Fo='Foxi:BAAANQADCggIEQABNQAECgkJGgAFAHocAA==.',
Fr='Frank:BAAANQAECggIEAAAAA==.Freakbeast:BAAANQAECgcIEgABNQAECgoKJwAeAFYjAA==.Fries:BAEANQAECggICwABNQAECggIDwAEAAAAAA==.',
Fu='Fullkidney:BAACNQAFFH8KAAIaAAQKeB4fCgBfAQAaAAQKeB4fCgBfAQA1AAQKfyAAAhoACQrbIqAJAEIDABoACQrbIqAJAEIDAAAA.Funch:BAABNQAECn8qAAIhAAoKChUhBQB4AgAhAAoKChUhBQB4AgAAAA==.',
Ga='Gaefaeryn:BAACNQAFFH8KAAIGAAQKow4KCwDRAAAGAAQKow4KCwDRAAA1AAQKfykAAwYACgq1GX0bAGwCAAYACgq1GX0bAGwCAAgAAQqaAQ0yAB8AAAAA.Gainzz:BAAANQAECgEIAQAAAA==.Garonnaa:BAABNQAECn80AAIQAAoKRxoZEwBuAgAQAAoKRxoZEwBuAgAAAA==.Garthel:BAABNQAECn81AAIXAAoKxBVEEwAcAgAXAAoKxBVEEwAcAgAAAA==.',
Ge='Genetiks:BAAANQADCgYIDAAAAA==.',
Gh='Ghari:BAABNQAECn8uAAIZAAcK4xHbMwBAAQAZAAcK4xHbMwBAAQAAAA==.',
Gi='Gingerlock:BAABNQAECn84AAIdAAoKlBxCJwBkAgAdAAoKlBxCJwBkAgAAAA==.Gingershaman:BAAANQAECgUIBQAAAA==.Giyuu:BAAANQADCgUIBQAAAA==.',
Gn='Gnoblin:BAAANQADCggIFgAAAA==.',
Gr='Greka:BAABNQAECn8hAAIJAAYKHgutewAFAQAJAAYKHgutewAFAQAAAA==.Greylooms:BAAANQADCgcIBwAAAA==.Griplock:BAABNQAECn9KAAMQAAoKHQ9eLQCPAQAQAAoKzQxeLQCPAQAVAAIKQRGiiwB4AAAAAA==.',
Gu='Gutz:BAAANQAECgUICwAAAA==.',
['Gö']='Gözër:BAAANQADCgMIAwABNQAECgYIBgAEAAAAAA==.',
Ha='Happyfriend:BAAANQAECgEIAQABNQAFFAUIDgAXAFoEAA==.Haruko:BAAANQADCggICAAAAA==.',
He='Healalle:BAAANQADCgYICwABNQAECgkJFwAgAPMdAA==.Healhole:BAABNQAECn81AAMRAAoKZyFREwAwAwARAAoKZyFREwAwAwAJAAMKbhFO7gC6AAAAAA==.Heimdall:BAAANQAECgEIAgAAAA==.Heàl:BAABNQAECn8XAAMGAAkKhiDoDwD3AgAGAAkKhiDoDwD3AgAIAAEKwxQ0JgA+AAAAAA==.',
Hi='Hidolo:BAAANQADCgYIDAAAAA==.',
Hr='Hruwa:BAAANQADCgMIAwABNQAECgEIAQAEAAAAAA==.',
Hu='Hunterishard:BAAANQAECgQIBAABNQAECgYIBwAEAAAAAA==.',
Hy='Hylaina:BAAANQADCgYJCgAAAA==.',
['Hô']='Hôlÿ:BAAANQADCggIDgAAAA==.',
Ia='Iamamonk:BAAANQADCgEIAQAAAA==.',
Ik='Ikerous:BAAANQADCgMIAwAAAA==.',
Il='Ilysa:BAAANQABCgQIBAAAAA==.',
Im='Imadwagon:BAAANQADCgcIAgAAAA==.Imcolorblind:BAAANQADCgIIAgAAAA==.Imhammered:BAAANQAECgYIDgAAAA==.',
Io='Ioun:BAAANQADCgMIAwAAAA==.Iounn:BAAANQADCgcIBwABNQAECgoKJgAjAJcVAA==.',
Ir='Ironpally:BAAANQAECgMIAgAAAA==.',
Is='Isatku:BAAANQAECgEIAQAAAA==.',
It='Itiswhatitiz:BAABNQAECn8+AAINAAoKMBuaMwBoAgANAAoKMBuaMwBoAgAAAA==.Itsybityshiv:BAABNQAECn81AAIkAAoKshgKDwCJAgAkAAoKshgKDwCJAgAAAA==.',
Ja='Jackspanko:BAAANQAECgEIAQAAAA==.Jakarr:BAAANQADCgUICQAAAA==.Jams:BAAANQAECgUIBQAAAA==.',
Je='Jeabuss:BAAANQADCgUIBQAAAA==.Jerricho:BAAANQAECgcICgAAAA==.',
Jh='Jhani:BAABNQAECn8lAAIlAAgKoQb+GAD9AAAlAAgKoQb+GAD9AAAAAA==.',
Ji='Jiu:BAABNQAECn8cAAIFAAkKiBsVJgDTAgAFAAkKiBsVJgDTAgABNQAECggIFwAZAMQbAA==.',
Jo='Joethemage:BAABNQAECn82AAICAAoKSB3lRAD6AgACAAoKSB3lRAD6AgAAAA==.Jormojo:BAAANQAECgMIAwAAAA==.',
Ju='Jungol:BAAANQADCgUICQAAAA==.',
Ka='Kairupaws:BAAANQAECgUIBQAAAA==.Kallip:BAAANQADCggICAAAAA==.Kamin:BAAANQAECgYIBgABNQAECgkJIgACAMgbAA==.Katamaran:BAAANQAECgMIBAABNQAFFAYIDAAGAKoLAA==.Kaykaypally:BAABNQAECn8lAAIDAAkK0REtdQDQAQADAAkK0REtdQDQAQAAAA==.Kazbirt:BAAANQADCgIIAgAAAA==.',
Ke='Kellan:BAAANQADCggIFgAAAA==.',
Kh='Khybyr:BAAANQADCgMIAwAAAA==.',
Ki='Kidata:BAABNQAECn8mAAIjAAoKlxVCFgAYAgAjAAoKlxVCFgAYAgAAAA==.Kindaprepped:BAAANQADCgQIBAAAAA==.Kinji:BAABNQAECn8nAAIJAAoKeBjkSABTAgAJAAoKeBjkSABTAgAAAA==.Kinn:BAAANQADCggICAABNQAECgoKNwAWAOkXAA==.',
Ko='Konfu:BAAANQAECgcICgAAAA==.Kormega:BAAANQAECgUIBQAAAA==.Korral:BAAANQADCggIDQAAAA==.',
Kr='Krispies:BAAANQAECgUIDQAAAA==.Kristysavage:BAABNQAECn9EAAMmAAoK3yE9AQBtAwAmAAoK0CA9AQBtAwANAAMKoBwq9wCpAAAAAA==.Krul:BAAANQAECgUIBQAAAA==.',
Ku='Kulaesca:BAACNQAFFH8RAAIdAAUKLhY4DQA3AQAdAAUKLhY4DQA3AQA1AAQKfy8AAx0ACgomG6VHAHwCAB0ACgomG6VHAHwCABwAAQrtAOWHAB0AAAAA.',
Ky='Kynar:BAACNQAFFH8fAAMVAAkKox5rAgAmAgAVAAkKox5rAgAmAgAQAAYKngfuEABIAQA1AAQKfzAAAxUACgpZJkQKAEkDABUACgpZJkQKAEkDABAAAwqHE7qWALEAAAAA.Kyua:BAAANQAECgUIBAAAAA==.',
La='Ladragona:BAAANQADCggICAAAAA==.Laguna:BAAANQAECgQIBAABNQAECgoKNgAFAJ0XAA==.Lambshot:BAABNQAECn8vAAMOAAoKTxsAEAAvAgAOAAoKGxgAEAAvAgANAAgK6xYAdgAkAgAAAA==.Lambsy:BAACNQAFFH8kAAQUAAkK9xIZBwBPAgAUAAkK9xIZBwBPAgAnAAEKAAAaBgBIAAAgAAEKAACwCQA9AAA1AAQKf0UAAxQACgpsJRoIAEsDABQACgpoJRoIAEsDACcAAwpnIQEcALkAAAAA.Lanamama:BAAANQAECgEIAQABNQAECgIIAgAEAAAAAA==.Lanana:BAAANQADCgMIAwABNQAECgIIAgAEAAAAAA==.',
Le='Ledsole:BAAANQABCgIIAgAAAA==.Lerat:BAABNQAECn87AAISAAoKZR91AwC1AgASAAoKZR91AwC1AgAAAA==.',
Li='Lightfoot:BAAANQADCgcIBwAAAA==.Lightwarden:BAAANQADCgQIBAAAAA==.Lilyy:BAACNQAFFH8LAAMlAAQKexGcAwDUAAAlAAQKexGcAwDUAAACAAIKAAokTgCKAAA1AAQKfy4AAyUACgqqHYgGAJcCACUACApFH4gGAJcCAAIACQp8F4JzAJcCAAAA.Lisanalgaib:BAABNQAECn8mAAIDAAgKPBX1lgD2AQADAAgKPBX1lgD2AQAAAA==.Lizzimcguire:BAACNQAFFH8RAAISAAUKhiHbAACMAQASAAUKhiHbAACMAQA1AAQKfz0AAhIACgo9JXgBALYDABIACgo9JXgBALYDAAAA.',
Lo='Lobobare:BAABNQAECn8fAAITAAgK2x0hHABVAgATAAgK2x0hHABVAgAAAA==.Loraen:BAABNQAECn8hAAICAAgKMAUXqgA+AQACAAgKMAUXqgA+AQAAAA==.Lostep:BAAANQAECgEIAQABNQAFFAkJIgARAJgYAA==.',
Lu='Lunarmon:BAAANQADCgUIBQAAAA==.Lunchable:BAABNQAECn8iAAMRAAoKEh+3PwD/AQARAAgKZx63PwD/AQAJAAcKzBV7gACjAQAAAA==.',
Ma='Maevora:BAABNQAECn8ZAAIGAAcKawSBTQDeAAAGAAcKawSBTQDeAAAAAA==.Makaroni:BAAANQAECgUIBQAAAA==.Manticus:BAAANQADCgYICAAAAA==.Marni:BAABNQAECn8cAAMFAAgK3hKzcgDEAQAFAAgK3hKzcgDEAQAGAAIKAABJbQAAAAABNQAECgoKKwADAOEhAA==.Marsrover:BAAANQAECgIIAgABNQAFFAkJIwAUAHccAA==.Martel:BAAANQADCgQIBAAAAA==.Matroxx:BAACNQAFFH8SAAIXAAcKNRcSBwCLAQAXAAcKNRcSBwCLAQA1AAQKf0gAAhcACgrKJDMFABgDABcACgrKJDMFABgDAAAA.',
Me='Medinduceyuh:BAAANQADCgEIAQAAAA==.Meenoi:BAABNQAECn8XAAIZAAgKxBtHRQAEAgAZAAgKxBtHRQAEAgAAAA==.Mellotots:BAAANQABCgIIBAAAAA==.Metatron:BAAANQADCgIIAgAAAA==.',
Mi='Miadas:BAAANQAECgMIAwABNQAECgkJQQAHAAshAA==.Mika:BAAANQAECgMIAwABNQAFFAQIBQAFAE4GAA==.Milire:BAAANQABCgMIAgAAAA==.Mimikyu:BAAANQABCgYIBgAAAA==.Minìwheats:BAAANQADCgMIAwAAAA==.',
Mo='Moardotsnow:BAABNQAECn8xAAQcAAoKaCUwGACrAQAdAAcKoCXpVgBRAgAcAAQKCiUwGACrAQAhAAEKxB6VJABLAAAAAA==.Moby:BAAANQAECgcIDAAAAA==.Moistmender:BAAANQAECggIEwAAAA==.Mortiana:BAAANQADCggICAAAAA==.',
Mu='Murriar:BAAANQAECggICQABNQAECgoKMAAoABQhAA==.Murridan:BAABNQAECn8wAAIoAAoKFCH7DADGAgAoAAoKFCH7DADGAgAAAA==.',
My='Mykaela:BAAANQAECgEIAQAAAA==.',
['Më']='Mëow:BAAANQAECgQIDQAAAA==.',
Na='Naausi:BAAANQADCgMIAwAAAA==.Namiyu:BAAANQADCgcIBwAAAA==.Nara:BAAANQAECgQIBAAAAA==.Narrath:BAAANQADCgMJAwAAAA==.Nayalaah:BAAANQAECgEIAQAAAA==.',
Ne='Nehpets:BAAANQADCgUIBQAAAA==.Nektzalla:BAABNQAECn8iAAIRAAoK6RkcKAB2AgARAAoK6RkcKAB2AgAAAA==.Nephelym:BAABNQAECn8gAAMFAAgKQA9ZcwDCAQAFAAgKQA9ZcwDCAQAIAAIKrAKOJABHAAAAAA==.Nerv:BAAANQADCgMIBQAAAA==.',
Ni='Nicolasmage:BAAANQABCgQIBQAAAA==.Nirina:BAABNQAECn8gAAINAAYK7wlf0wDwAAANAAYK7wlf0wDwAAAAAA==.',
No='Nohtil:BAAANQADCgcIHAAAAA==.Notstephen:BAABNQAECn8lAAMFAAoK6Ay3dQC7AQAFAAoK6Ay3dQC7AQAGAAQKCxBIWACpAAAAAA==.Nourishnutz:BAAANQADCgYIBgAAAA==.',
Nu='Nukefury:BAACNQAFFH8FAAIfAAQKWAg4BADLAAAfAAQKWAg4BADLAAA1AAQKfyQAAh8ACQrkHZwHAKECAB8ACQrkHZwHAKECAAAA.Nut:BAABNQAECn8UAAIcAAUKoBIjJwA+AQAcAAUKoBIjJwA+AQABNQAECggIJwAQAHwQAA==.',
Nw='Nwalliance:BAAANQAECgEIAQAAAA==.',
['Nö']='Nötprepared:BAAANQAECgUIBAABNQAECgUICQAEAAAAAA==.',
Oi='Oiflar:BAABNQAECn8fAAIiAAoKTBaDDgARAgAiAAoKTBaDDgARAgABNQAECgoKOQAiACMjAA==.',
Ol='Olangi:BAAANQAECgEIAQAAAA==.',
Om='Omnidh:BAAANQADCggIEAABNQAFFAUIEQAXAKEfAA==.Omnipotent:BAAANQAECgUIBQAAAA==.',
On='Onepavo:BAABNQAECn8xAAIkAAoKhhIBQwDZAQAkAAoKhhIBQwDZAQAAAA==.',
Oo='Oogie:BAAANQADCgYIBgAAAA==.Oogrikusk:BAAANQADCgIIAgAAAA==.Oottedenttoo:BAAANQADCgQIBAAAAA==.',
Op='Oppose:BAABNQAECn8YAAQHAAgKwhSiGAAxAQABAAcKbA2qVACGAQAHAAYK6BOiGAAxAQATAAQK9wxEUwC7AAAAAA==.',
Or='Orexion:BAABNQAECn8jAAInAAgKGwtAEgCAAQAnAAgKGwtAEgCAAQAAAA==.Oriavis:BAAANQAECgMIAwAAAA==.Ormagöden:BAABNQAECn8pAAIVAAoKMw2QQwC1AQAVAAoKMw2QQwC1AQAAAA==.',
Ov='Overpower:BAAANQADCgYIBgAAAA==.',
Pa='Pagoda:BAABNQAECn8XAAIBAAgKYwzcOgAvAQABAAgKYwzcOgAvAQAAAA==.Palladean:BAAANQAECgIIAwAAAA==.Palphen:BAAANQAECgcJDAABNQAECgoKJQAFAOgMAA==.Panako:BAAANQAECgUICQAAAA==.Pastasauce:BAABNQAECn8dAAIDAAYK3wnl/QAjAQADAAYK3wnl/QAjAQAAAA==.',
Pe='Pegero:BAAANQADCgYIDQABNQAFFAMIBQANAFgXAA==.Penelohpe:BAABNQAECn8iAAICAAkKyBt4fQCDAgACAAkKyBt4fQCDAgAAAA==.',
Ph='Phatt:BAAANQAECgMIAwAAAA==.Phoenixdrac:BAAANQADCggICQAAAA==.Phoon:BAECNQAFFH8NAAMdAAQKzxvsFgA+AQAdAAQKzxvsFgA+AQAcAAEKKRG4HgBLAAA1AAQKfzcABB0ACgpoI1M8AJ4CAB0ACAovI1M8AJ4CABwABAqiIXAkAE8BACEAAQpJDkMrADcAAAAA.Phoondk:BAEANQAECgUICAABNQAFFAQIDQAdAM8bAA==.',
Pi='Piggy:BAABNQAECn8lAAIRAAoKFwj9fAAlAQARAAoKFwj9fAAlAQAAAA==.Pita:BAAANQABCgYIBgAAAA==.Pitaya:BAAANQAECggICAAAAA==.Pizzadriver:BAACNQAFFH8jAAMUAAkKdxwXBACZAgAUAAkKdxwXBACZAgAnAAEKAADIBQBLAAA1AAQKfzUAAxQACgouJnoGAFcDABQACgomJnoGAFcDACcAAQo9JuEnAG4AAAAA.',
Pl='Plaguefist:BAAANQADCgcIBwABNQADCggIEgAEAAAAAA==.Plata:BAABNQAECn8dAAIUAAkKIRCelABCAQAUAAkKIRCelABCAQAAAA==.',
Po='Poosicat:BAAANQABCgYIBgAAAA==.Poosycat:BAAANQADCgMIAQAAAA==.',
Pr='Praytroxx:BAABNQAECn8UAAIGAAcKmRLPJgA3AQAGAAcKmRLPJgA3AQABNQAFFAcIEgAXADUXAA==.Premonitions:BAAANQAECgYIBgAAAA==.Premune:BAABNQAECn82AAIYAAoKWyGaLgCsAgAYAAoKWyGaLgCsAgAAAA==.Prion:BAABNQAECn8aAAQoAAoKSxVSMAAlAgAoAAoKnhNSMAAlAgALAAEKlRTlaABAAAAKAAEKOgt4NAAqAAAAAA==.',
Pu='Pucco:BAAANQADCgIIAgAAAA==.Purpleflurp:BAAANQAECggICgAAAA==.Putrav:BAAANQAECgYICAAAAA==.',
Py='Pyrena:BAAANQADCgEIAQAAAA==.Pyroclasm:BAAANQAECgUICgAAAA==.Pyrrha:BAAANQADCgMIAwAAAA==.',
Qu='Quigly:BAAANQADCgIIAgAAAA==.',
Ra='Ragingfluids:BAABNQAECn8pAAMnAAoKNBZSEgB+AQAUAAoKohUBaACyAQAnAAYKnBRSEgB+AQAAAA==.Rahdek:BAAANQADCgMIAwAAAA==.Raine:BAACNQAFFH8iAAIRAAkKmBgyBAA/AgARAAkKmBgyBAA/AgA1AAQKfy0AAxEACgrGFRpSAB4CABEACgrGFRpSAB4CAAkACAqxGnpIAJwBAAAA.Raistlin:BAAANQADCgEIAQAAAA==.Ralfio:BAABNQAECn85AAMiAAoKIyPaBQAEAwAiAAoKIyPaBQAEAwApAAEKAACVJAAzAAAAAA==.Rasq:BAABNQAECn8VAAMbAAkK9QUqLAA3AQAbAAkK9QUqLAA3AQABAAEKAACnzAAUAAAAAA==.Rat:BAABNQAECn8XAAIaAAkKNCGiCABOAwAaAAkKNCGiCABOAwAAAA==.Raudykill:BAAANQAECgcIBgAAAA==.Rayaray:BAAANQADCgYIBgAAAA==.Raynith:BAABNQAECn9BAAUHAAkKCyHrCwD2AQABAAkK2h1eLQByAgAHAAcK0yHrCwD2AQAbAAMK4xHfUQBoAAATAAEKPBntZwBKAAAAAA==.Rayraye:BAAANQADCgcICQAAAA==.Raytard:BAAANQADCgcIBwAAAA==.',
Rd='Rdyoshy:BAAANQADCgUIBQAAAA==.',
Re='Readycheck:BAABNQAECn8+AAQBAAoK8RPLJADCAQABAAoK8RPLJADCAQAbAAcKyQg3MAAaAQATAAIKqA4CYABjAAAAAA==.Reflex:BAAANQAECgIIAgAAAA==.Regirock:BAAANQABCgMIAwAAAA==.Rellek:BAAANQAECgIIAgAAAA==.Remulous:BAABNQAECn8VAAINAAgKBRNpjQDvAQANAAgKBRNpjQDvAQAAAA==.Resist:BAAANQADCgYIBgAAAA==.Retallica:BAABNQAECn8rAAIDAAoKXA8FbgDgAQADAAoKXA8FbgDgAQAAAA==.Revali:BAACNQAFFH8KAAIOAAUKZw3BDQBhAQAOAAUKZw3BDQBhAQA1AAQKf0wAAw0ACgq3IMsxANcCAA0ACgp0HcsxANcCAA4ACgrEGUkYAJUCAAAA.Revelaen:BAAANQAECgcIDwABNQAFFAUICgAOAGcNAA==.',
Ri='Rick:BAACNQAFFH8NAAIOAAMKwxywEAC/AAAOAAMKwxywEAC/AAA1AAQKfzMAAw4ACgr8IrYFAOsCAA4ACgq/IrYFAOsCAA0ABApOIHIDAf4AAAAA.',
Rm='Rmagep:BAAANQAECgUICwAAAA==.',
Ro='Roadhouse:BAAANQAECgQIBwAAAA==.Roman:BAAANQAECgYIDAABNQAFFAUICAAiAMsfAA==.Roshango:BAAANQADCgYIBgAAAA==.Rosinator:BAAANQAECggIAQAAAA==.Rotgus:BAAANQAECgEIAQAAAA==.Rouk:BAABNQAECn8eAAIUAAoKjBxpJAClAgAUAAoKjBxpJAClAgABNQAECgoKKwADALsmAA==.Rowgar:BAABNQAECn8jAAIQAAoKmxoqIADqAQAQAAoKmxoqIADqAQAAAA==.',
Ru='Rubenslik:BAABNQAECn80AAICAAoKqSEQLAA3AwACAAoKqSEQLAA3AwAAAA==.',
Sa='Saelyn:BAAANQADCggIBgAAAA==.Saephora:BAABNQAECn8eAAIlAAcKuwanHgD2AAAlAAcKuwanHgD2AAAAAA==.Saggypants:BAABNQAECn8fAAIBAAoKXBS+LwBjAgABAAoKXBS+LwBjAgAAAA==.Sakurai:BAAANQAECgEIAQABNQAECgIIAgAEAAAAAA==.Salamander:BAAANQAECgUJCgAAAA==.Salazzle:BAAANQADCgQIBAAAAA==.Sammel:BAAANQAECgUIEAAAAA==.Sanari:BAAANQADCgUIBwABNQAECgoKJwAJAHgYAA==.Sandilla:BAAANQADCggICAABNQAECgoKIgAJAIokAA==.Sangwine:BAAANQADCgYIBgAAAA==.Sapphica:BAAANQAECgEIAgAAAA==.Sargus:BAAANQADCgUICAAAAA==.Sathreina:BAABNQAECn84AAIDAAoKDRhqdABFAgADAAoKDRhqdABFAgAAAA==.Sativva:BAAANQAECgIIAgABNQAECgoKIgAJAIokAA==.',
Sc='Scaries:BAABNQAECn8gAAIWAAoK4RlTBwDIAgAWAAoK4RlTBwDIAgAAAA==.Scootko:BAABNQAECn8fAAIDAAkKCiXsQQDPAgADAAkKCiXsQQDPAgAAAA==.Scuss:BAAANQADCggICAAAAA==.',
Se='Sego:BAAANQAECgUIBwAAAA==.Sekimaru:BAAANQAECgIIAgAAAA==.Senli:BAAANQAECgEIAQAAAA==.Severson:BAABNQAECn8bAAIOAAgKXAxfNACrAQAOAAgKXAxfNACrAQAAAA==.Sey:BAAANQADCgYIBgAAAA==.',
Sh='Shadowapoke:BAAANQADCgUIBQABNQAECgEIAQAEAAAAAA==.Shadowisbad:BAABNQAECn8qAAIGAAoKehhYHABiAgAGAAoKehhYHABiAgAAAA==.Shadvoker:BAABNQAECn8iAAMiAAgKzx2iDgC/AgAiAAgKzx2iDgC/AgASAAIK1BHUMwBvAAAAAA==.Shamaneggs:BAABNQAECn8uAAMRAAoKKSCoDQBFAwARAAoKKSCoDQBFAwAfAAMKshBOKQDRAAAAAA==.Shamatroxx:BAABNQAECn8tAAIfAAkKcRwcEQBXAgAfAAkKcRwcEQBXAgABNQAFFAcIEgAXADUXAA==.Shamberry:BAABNQAECn8aAAIfAAgKBRWDEQBRAgAfAAgKBRWDEQBRAgAAAA==.Shambles:BAAANQADCgYICQAAAA==.Sheilla:BAABNQAECn8ZAAMQAAgKcRLadQAgAQAQAAcKohTadQAgAQAZAAUKtwcJlADbAAAAAA==.Shieldslamer:BAABNQAECn8VAAIUAAkKyQYXhQBmAQAUAAkKyQYXhQBmAQAAAA==.Shieldwalle:BAABNQAECn8XAAIgAAkK8x0KCwCMAgAgAAkK8x0KCwCMAgAAAA==.Shinobukocho:BAAANQADCgQJBAAAAA==.Shlock:BAAANQAECgYICwAAAA==.Shotigolova:BAAANQADCgcIEgAAAA==.',
Si='Sidesalad:BAAANQAECgQIBgAAAA==.Sidric:BAABNQAECn8/AAIBAAoKfREAHwD0AQABAAoKfREAHwD0AQAAAA==.Siena:BAAANQADCggIDgAAAA==.Silre:BAABNQAECn8eAAMhAAcKAwyLEQAzAQAhAAcKewuLEQAzAQAcAAUKWwekHAB1AAAAAA==.Sim:BAABNQAECn8mAAIUAAkKLiSvFQBjAwAUAAkKLiSvFQBjAwABNQAECgoKIgAJAIokAA==.Singularité:BAAANQAECggIEgABNQAFFAgIDAAaAFINAA==.Sipplex:BAAANQAECgYIDgAAAA==.',
Sl='Slander:BAAANQAECgQJBAABNQAECgUJCgAEAAAAAA==.Slanderous:BAAANQADCgEJAQABNQAECgUJCgAEAAAAAA==.Slappee:BAAANQAECgYIBwAAAA==.Slappeey:BAAANQAECgUICAABNQAECgYIBwAEAAAAAA==.',
Sn='Snuudle:BAAANQAECgcIDwABNQAECgkJHAAdABwXAA==.',
So='Solokills:BAAANQADCgMIAwABNQAFFAMIBQANAFgXAA==.Sophia:BAAANQAECgcIEgAAAA==.Soundtrack:BAAANQADCgYICQABNQAECgIIAgAEAAAAAA==.Soyshine:BAAANQADCgYIBgAAAA==.',
Sp='Spaceman:BAACNQAFFH8OAAIXAAUKWgTNCADbAAAXAAUKWgTNCADbAAA1AAQKfx4AAhcACgqJES4pANUBABcACgqJES4pANUBAAAA.',
Sq='Squab:BAABNQAECn8cAAIBAAkKaR6+GQD6AgABAAkKaR6+GQD6AgAAAA==.Squanchy:BAAANQADCgYJCAAAAA==.',
St='Stabbywixx:BAAANQAECgIIAgAAAA==.Starwnd:BAABNQAECn8UAAIdAAcKlheaggDfAQAdAAcKlheaggDfAQABNQAFFAYIDgApAMcOAA==.Sterìs:BAAANQAECgEIAQAAAA==.Stillcreepin:BAAANQAECgIIAwAAAA==.Stompy:BAAANQAECgQIBAABNQAFFAYIDAAGAKoLAA==.Storienn:BAABNQAECn8aAAQYAAgKshECeACwAQAYAAgKshECeACwAQADAAUKWREQIgHmAAAPAAMKBw0UUQChAAAAAA==.Stormzpaly:BAAANQAECgYIEQAAAA==.',
Su='Suküna:BAAANQADCggIFwAAAA==.Sunbur:BAAANQADCgYICgAAAA==.Sunglo:BAAANQAECgUIBwAAAA==.Surch:BAAANQADCgEIAQAAAA==.',
Sw='Swaption:BAABNQAECn83AAIRAAoKDSNGCgBqAwARAAoKDSNGCgBqAwAAAA==.Sweetie:BAAANQADCgEIAQAAAA==.',
Sy='Synathia:BAAANQAECgEIAQAAAA==.Syrelia:BAABNQAECn9SAAICAAoKyxlxNgBfAgACAAoKyxlxNgBfAgAAAA==.',
['Só']='Sónny:BAAANQABCgIIAgAAAA==.',
Ta='Tablescraps:BAAANQADCgYIBQABNQADCgIIAgAEAAAAAA==.Talonstrykz:BAAANQADCgUIBQAAAA==.Tassarosea:BAAANQAECgcIBwABNQAFFAUIEQASAIYhAA==.Tauloe:BAABNQAECn8ZAAIJAAYKTAgxhwDoAAAJAAYKTAgxhwDoAAAAAA==.Tayna:BAABNQAECn8bAAIGAAgKAAwdJgA8AQAGAAgKAAwdJgA8AQAAAA==.',
Te='Tenderoni:BAAANQADCgEIAQAAAA==.',
Th='Thatsmyhorse:BAAANQADCgIIAgAAAA==.Thatsograven:BAAANQADCgQIBAABNQAFFAgIIAABAOAfAA==.Thomosaurus:BAAANQADCggIDAAAAA==.Thraly:BAAANQADCgYIBwAAAA==.Thunk:BAABNQAECn8iAAIJAAoKiiTACwCJAwAJAAoKiiTACwCJAwAAAA==.',
Ti='Timdawg:BAABNQAECn8XAAMlAAkKLCFXDAD2AQAlAAcK0SNXDAD2AQACAAUKahLJQAEhAQABNQAFFAkJIwAdAIAaAA==.Timmolate:BAACNQAFFH8jAAQdAAkKgBr9BgD6AQAdAAcKGRz9BgD6AQAcAAIKwRfpCgCjAAAhAAIKRAkmDQBLAAA1AAQKfz4ABB0ACgrLJfUTAMsCAB0ACQo1JPUTAMsCABwACAoMGQULAEcCACEAAQoqJpweAG4AAAAA.Tiramisubear:BAAANQAECggIDgAAAA==.Tircaps:BAAANQADCgUIBQAAAA==.',
To='Tomcruise:BAAANQAECgIIAgAAAA==.Tomotostein:BAACNQAFFH8LAAIDAAUK5gxdFwDDAAADAAUK5gxdFwDDAAA1AAQKfzEAAgMACgoCG1dSACQCAAMACgoCG1dSACQCAAAA.Tornado:BAAANQABCgQICQABNQADCgQIBAAEAAAAAA==.',
Tr='Trilla:BAAANQAECgcIDgAAAA==.Tristîtia:BAABNQAECn8ZAAMGAAkK/A4nJAAQAgAGAAkK/A4nJAAQAgAFAAIKCwki5gB1AAAAAA==.Trulu:BAAANQAECgEIAQAAAA==.',
Ts='Tsukikyo:BAAANQADCgQIBAAAAA==.Tsuma:BAAANQADCgUIBQAAAA==.Tsume:BAAANQAECgcIEgAAAA==.',
Tt='Ttomas:BAABNQAECn8VAAMOAAkKuh9oOwB2AQANAAYKbCI8mQDVAQAOAAcKlhRoOwB2AQAAAA==.',
Ty='Tyrinn:BAABNQAECn8lAAIQAAoKgxFTJQDBAQAQAAoKgxFTJQDBAQAAAA==.Tyv:BAABNQAECn9GAAICAAoKwxLQVQACAgACAAoKwxLQVQACAgAAAA==.',
Ul='Ulmerideavus:BAAANQADCgcIBwAAAA==.',
Up='Updatè:BAAANQAECgEIAQABNQAECgkJFwAGAIYgAA==.',
Ur='Urgent:BAAANQAECgIIAgAAAA==.',
Uz='Uzì:BAAANQADCgIIAgAAAA==.',
Va='Vainatetosix:BAAANQAECgUICQAAAA==.Vallodon:BAABNQAECn8kAAICAAkKHCISTgDlAgACAAkKHCISTgDlAgAAAA==.Vantablack:BAAANQABCgIIAgABNQADCgQIBAAEAAAAAA==.Vanwolfy:BAABNQAECn8eAAIgAAoK+hI9FQDUAQAgAAoK+hI9FQDUAQAAAA==.Vaylorian:BAABNQAECn8ZAAQPAAYK8hGPLAD9AAAPAAYK8hGPLAD9AAAYAAIKJQoP2QBUAAADAAIK+gU6hgFRAAAAAA==.',
Ve='Velectran:BAAANQADCgcIEAABNQAECgoKUgACAMsZAA==.Velorian:BAAANQADCgQIBwAAAA==.Velveeta:BAAANQAECgMIAwAAAA==.Veragon:BAAANQADCgcIBwAAAA==.',
Vf='Vfacer:BAAANQADCgEIAQAAAA==.',
Vi='Vikav:BAAANQAECgIIAgAAAA==.Vikimg:BAABNQAECn8bAAIFAAoKoBabVgAfAgAFAAoKoBabVgAfAgAAAA==.Violet:BAAANQADCgEIAQAAAA==.',
Vo='Voodoomike:BAAANQAECgQIBAAAAA==.Vortash:BAAANQADCgUIBwAAAA==.',
Vy='Vynle:BAAANQAECgEIAQAAAA==.',
Wa='Warheimer:BAABNQAECn8ZAAMZAAoKzg6LXwCRAQAZAAoKzg6LXwCRAQAQAAQKVgZpoQCUAAAAAA==.Warrgodx:BAABNQAECn9YAAMUAAoK1ySzDQAhAwAUAAoK1ySzDQAhAwAnAAEKygioMwA0AAABNQAFFAUIBgADAL4aAA==.',
Wh='Whoknows:BAAANQADCgIIAgAAAA==.',
Wo='Woogi:BAAANQADCgUIBQAAAA==.',
Wr='Wrongwookie:BAABNQAECn8uAAIJAAoKPBkpRwBaAgAJAAoKPBkpRwBaAgAAAA==.',
Ya='Yapper:BAAANQADCgMIAwAAAA==.',
Yo='Yolanda:BAAANQAECgIIAgAAAA==.Yoyohunty:BAABNQAECn8WAAImAAkKmw+JCADHAQAmAAkKmw+JCADHAQAAAA==.',
Yt='Ytix:BAAANQAECgEIAQAAAA==.',
Yu='Yumekoo:BAAANQAECgIIAgAAAA==.',
Za='Zabada:BAABNQAECn8YAAINAAYK3w2ezgD6AAANAAYK3w2ezgD6AAAAAA==.Zaldrea:BAAANQAECgcICQABNQAFFAYIDAAGAKoLAA==.Zandrea:BAAANQAECggIEQABNQAFFAYIDAAGAKoLAA==.Zariee:BAAANQABCgIIAwAAAA==.',
Ze='Zehz:BAABNQAECn8aAAIVAAkKZAFhkgByAAAVAAkKZAFhkgByAAAAAA==.Zemsen:BAABNQAECn8nAAICAAkKoh3yawCmAgACAAkKoh3yawCmAgAAAA==.Zentrea:BAAANQAECgQIBQABNQAFFAYIDAAGAKoLAA==.Zenyea:BAABNQAECn8iAAIRAAoKUhREMgA/AgARAAoKUhREMgA/AgABNQAFFAYIDAAGAKoLAA==.Zetta:BAACNQAFFH8MAAIGAAYKqgswCQB0AQAGAAYKqgswCQB0AQA1AAQKfzIAAgYACgq7HkwMAIYCAAYACgq7HkwMAIYCAAAA.',
Zo='Zome:BAABNQAECn9PAAMkAAoKjBy5HQCMAgAkAAoKjBy5HQCMAgAaAAEKlAM4pgAwAAAAAA==.Zorojoro:BAAANQAECgYIDgAAAA==.',
Zy='Zyndrael:BAABNQAECn8rAAIDAAoK4SHkLAAUAwADAAoK4SHkLAAUAwAAAA==.',
['Èl']='Èlytz:BAAANQADCgYICQAAAA==.',
['Êl']='Êlytz:BAAANQADCggJCAAAAA==.',
['ßl']='ßlue:BAAANQAECgYICgAAAA==.',
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
