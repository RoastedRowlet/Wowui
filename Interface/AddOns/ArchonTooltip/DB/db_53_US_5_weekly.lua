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

local lookup = {'Druid-Balance','Mage-Arcane','Paladin-Retribution','Unknown-Unknown','Priest-Holy','Priest-Shadow','Druid-Feral','Priest-Discipline','Shaman-Elemental','DemonHunter-Vengeance','DemonHunter-Devourer','Mage-Fire','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','DeathKnight-Blood','Shaman-Restoration','Evoker-Devastation','Druid-Restoration','Warrior-Arms','DeathKnight-Frost','Monk-Windwalker','Monk-Brewmaster','Paladin-Holy','DeathKnight-Unholy','Rogue-Assassination','Druid-Guardian','Warlock-Destruction','Warlock-Demonology','Rogue-Outlaw','Shaman-Enhancement','Warrior-Protection','Warlock-Affliction','Evoker-Preservation','Monk-Mistweaver','Rogue-Subtlety','Mage-Frost','Hunter-Survival','Warrior-Fury','DemonHunter-Havoc','Evoker-Augmentation',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Accost:BAAANQADCgcIDQAAAA==.Achendron:BAAANQADCgUIBQABNQAFFAgIIAABAOAfAA==.Acronica:BAAANQAECgUIEgAAAA==.',
Ad='Addilynn:BAAANQABCgEIAQAAAA==.Adralion:BAAANQAECgEIAQAAAA==.',
Ak='Akassa:BAAANQADCgcICwAAAA==.Aknologia:BAAANQAECgUICwABNQAECgoKGwACAPcOAA==.',
Al='Alecto:BAABNQAECn8zAAIDAAoKcggxtQBmAQADAAoKcggxtQBmAQAAAA==.Allele:BAAANQAECgMIAwAAAA==.Allet:BAAANQADCggIFwABNQAECggIEwAEAAAAAA==.',
Am='Amarah:BAACNQAFFH8FAAIFAAQKTgYKIQDkAAAFAAQKTgYKIQDkAAA1AAQKf0cAAwUACgqxIMAYABEDAAUACgqxIMAYABEDAAYAAQoAAON3AAAAAAAA.Amazome:BAABNQAECn8cAAIHAAoKzBkVCQBXAgAHAAoKzBkVCQBXAgAAAA==.Ameilie:BAACNQAFFH8LAAMFAAQK1h+5EwBxAQAFAAQK1h+5EwBxAQAIAAIK9QXfAQBwAAA1AAQKf0kABAgACgoXIXMDAEsCAAUACgrCIMYdAPoCAAgACQqbGHMDAEsCAAYAAQoACqBgADoAAAAA.',
An='Anapuwae:BAABNQAECn8UAAIJAAYKSA0CqwA+AQAJAAYKSA0CqwA+AQAAAA==.Animehero:BAABNQAECn8qAAMKAAoKVR2gBQDRAgAKAAgKHCCgBQDRAgALAAYKsRc8IACfAQAAAA==.',
Ar='Arcant:BAABNQAECn8sAAMCAAoKzRkAbwDTAQACAAoKzRkAbwDTAQAMAAEKQQwnDQA6AAAAAA==.Ardicov:BAAANQADCgYICwAAAA==.Argadin:BAAANQAECgcICwABNQAECgoKMAANAG0iAA==.Arglock:BAAANQAECggIEAABNQAECgoKMAANAG0iAA==.Argrekh:BAABNQAECn8wAAMNAAoKbSLQCgCHAwANAAoKbSLQCgCHAwAOAAEKQQ/phgA3AAAAAA==.Argreks:BAAANQAECgQIBgABNQAECgoKMAANAG0iAA==.Argrekt:BAAANQAECgIIAgABNQAECgoKMAANAG0iAA==.Aridol:BAAANQADCgYIBgAAAA==.Arigön:BAAANQAECgEIAQAAAA==.Aronna:BAAANQADCgYICAAAAA==.Arosea:BAAANQADCgYIBgAAAA==.Arthaslk:BAACNQAFFH8GAAIDAAUKvhqAGwC6AAADAAUKvhqAGwC6AAA1AAQKf1MAAwMACgrmJekCAOYDAAMACgrmJekCAOYDAA8ABAoMD6RKAHoAAAAA.Aryssol:BAAANQAECgIIAgAAAA==.',
At='Ate:BAABNQAECn8rAAIQAAgKoBJIMQCHAQAQAAgKoBJIMQCHAQAAAA==.Atlette:BAAANQAECggIEAAAAA==.Attman:BAACNQAFFH8YAAIRAAUKDxhbDwBnAQARAAUKDxhbDwBnAQA1AAQKf1EAAxEACgoIJLYPAEYDABEACgoIJLYPAEYDAAkABArVEneMAPMAAAAA.',
Au='Auradawn:BAAANQADCgcIDwAAAA==.',
Ba='Backwater:BAAANQAECgQIBAABNQAECggIEwAEAAAAAA==.Badhands:BAAANQAECgIIAgAAAA==.Baeator:BAAANQAECgEIAQABNQAFFAcIGAASAO0PAA==.Barneystins:BAAANQABCgEIAgABNQADCgQIBAAEAAAAAA==.',
Be='Bearmane:BAACNQAFFH8KAAIBAAQK3B84DwALAQABAAQK3B84DwALAQA1AAQKfzQAAwEACgoyI58OAFUDAAEACgoyI58OAFUDABMAAgoSDgRlAGUAAAAA.Beastarsfan:BAABNQAECn8oAAIJAAoKnyOPCwCLAwAJAAoKnyOPCwCLAwAAAA==.Behmow:BAABNQAECn9LAAIUAAoKvCa8BABqAwAUAAoKvCa8BABqAwAAAA==.Belithel:BAAANQAECgQIBgABNQAECgoKLgAJAGcaAA==.Bencreepin:BAABNQAECn8eAAMQAAcK2hA5TgAFAQAQAAYK2hA5TgAFAQAVAAMKCwj2nABYAAAAAA==.Bergastad:BAAANQAECgQICAABNQAECgoKOAAWAC8XAA==.Bernoulli:BAABNQAECn83AAMXAAoK6RdrBgAeAgAXAAoK6RdrBgAeAgAWAAEKAABmcAAAAAAAAA==.Bettyford:BAAANQAECggIBgAAAA==.',
Bi='Bigspitter:BAAANQADCgYIBgABNQAECgoKOAACAHAlAA==.Bis:BAAANQADCgUJBQABNQAECgkJFgACAD0cAA==.',
Bl='Blessedxx:BAAANQAECgUIBgAAAA==.Bloodboo:BAAANQADCgQIBAAAAA==.Bloodyhpally:BAACNQAFFH8fAAIYAAkKGhZDAwBoAgAYAAkKGhZDAwBoAgA1AAQKfy4AAxgACgrSHmArALoCABgACgrSHmArALoCAAMAAgoXD4lmAXsAAAAA.',
Bo='Boopsnoopems:BAABNQAECn8hAAIPAAYKzw99PQC1AAAPAAYKzw99PQC1AAAAAA==.Borderline:BAAANQAECgUIBQABNQAFFAUIDgAWAFoEAA==.',
Br='Bradcrit:BAAANQAECgIIAQAAAA==.',
Bu='Bubble:BAABNQAECn8aAAMYAAcKUgfJuQAJAQAYAAYKIAfJuQAJAQADAAUKgggXJAHjAAAAAA==.Bulldoser:BAAANQADCgQIBAAAAA==.Burrfoot:BAAANQAECgIIAwAAAA==.Bustah:BAAANQAECgcIEgABNQAECggIFwAZAMQbAA==.',
Bw='Bwoodmorgan:BAAANQAECgYIDgAAAA==.',
By='Byron:BAAANQAECgQIBgAAAA==.',
Ca='Calene:BAACNQAFFH8MAAIaAAgKTQ0kBQDkAQAaAAgKTQ0kBQDkAQA1AAQKf1MAAhoACgonJOoDAPkCABoACgonJOoDAPkCAAAA.Candy:BAAANQAECgMIBQAAAA==.Cannedcorn:BAAANQAECgIIAgAAAA==.Caperusin:BAAANQAECgUICAAAAA==.Casare:BAAANQADCgYIFgAAAA==.Cayde:BAAANQADCgYJBgABNQAFFAUICgAOAGcNAA==.',
Ce='Celestinee:BAAANQAECgYIEwAAAA==.Celyda:BAAANQAECgUICAAAAA==.Cenarian:BAAANQABCgUIBwAAAA==.',
Ch='Chabotloe:BAAANQAECgQIBgAAAA==.Chape:BAABNQAECn8dAAMYAAkKvhcQPgBsAgAYAAkKvhcQPgBsAgADAAYK/BBE7wA+AQABNQABCgEIAQAEAAAAAA==.Chence:BAAANQADCgYIBgABNQAECgoKOAAWAC8XAA==.Chochalinda:BAABNQAECn8dAAMHAAgKvxHBFgCNAQAHAAcKXBDBFgCNAQAbAAUK8xTfLQArAQAAAA==.',
Ci='Cinderlee:BAABNQAECn8VAAIcAAYKNgWvGACbAAAcAAYKNgWvGACbAAAAAA==.',
Co='Colexn:BAABNQAECn8lAAQVAAkKwBZnOgDoAQAVAAkKwBZnOgDoAQAZAAIKMhDJwQBnAAAQAAEKAAB2wwAAAAAAAA==.Cong:BAACNQAFFH8FAAIUAAQK3ghxIAD/AAAUAAQK3ghxIAD/AAA1AAQKfycAAhQACgqnG/MnABoDABQACgqnG/MnABoDAAAA.Corg:BAAANQADCgYIBgAAAA==.Cornchipz:BAABNQAECn8bAAICAAoK9w5e0ADlAQACAAoK9w5e0ADlAQAAAA==.',
Cr='Crapsack:BAAANQABCgEIAQAAAA==.Croski:BAAANQADCgEIAQAAAA==.Cryonidus:BAAANQAECgEIAQAAAA==.',
Cu='Curves:BAAANQAECgEIAQAAAA==.',
Cy='Cypressa:BAAANQADCgQIBAAAAA==.',
Da='Daangalanng:BAABNQAECn8qAAIYAAoKDhepRABTAgAYAAoKDhepRABTAgAAAA==.Dabberoni:BAAANQAECgEIAgAAAA==.Daegra:BAABNQAECn8pAAIaAAoKXByaDwAEAwAaAAoKXByaDwAEAwAAAA==.Dankkush:BAAANQADCgQIBAAAAA==.Darkacedia:BAABNQAECn8vAAMdAAkKihXHTQBrAgAdAAkKihXHTQBrAgAcAAMKKwp9TwCRAAAAAA==.Darkzetta:BAAANQAECgIIAgABNQAFFAYIDAAGAKoLAA==.Datbish:BAAANQAECgIIAgAAAA==.',
De='Deadlift:BAABNQAECn8wAAIZAAoKkhwwDwCMAgAZAAoKkhwwDwCMAgAAAA==.Deadlyhoof:BAAANQAECgMIAwAAAA==.Dealosed:BAABNQAECn8ZAAMaAAgKphkIKwA+AgAaAAgKeRkIKwA+AgAeAAQKDhXyEQDsAAAAAA==.Deathawolf:BAAANQAECgEIAQAAAA==.Deathbyaoe:BAAANQAECggIEAAAAA==.Deathkilera:BAAANQADCgUIBwAAAA==.Defy:BAAANQADCgYIBgAAAA==.Delenn:BAABNQAECn8XAAIHAAgKZxrsDQA6AgAHAAgKZxrsDQA6AgAAAA==.Demonclawz:BAAANQAECgYIBgAAAA==.Demonnyaa:BAAANQADCgcIBwAAAA==.Deneb:BAAANQADCgIIAgABNQAECgkJHAAGALggAA==.Derzy:BAAANQADCgIIAgAAAA==.Dewygirl:BAAANQADCgcICgAAAA==.',
Dh='Dhuumystic:BAAANQADCgEIAQAAAA==.',
Di='Disastapyre:BAAANQAECgIIAgABNQAFFAQIBQAfAFgIAA==.Disastasmite:BAAANQADCgIIBAABNQAFFAQIBQAfAFgIAA==.Dive:BAABNQAECn8WAAICAAkKPRyyYwC3AgACAAkKPRyyYwC3AgAAAA==.',
Do='Doogru:BAABNQAECn9HAAIgAAoK7RvUCQA2AgAgAAoK7RvUCQA2AgAAAA==.Doogtwo:BAAANQADCggIHAABNQAECgoKRwAgAO0bAA==.Doryndoran:BAAANQAECgQIBQAAAA==.Dorynhashots:BAAANQADCgUIBQAAAA==.Dotproduct:BAAANQADCgEIAQABNQADCgIIAgAEAAAAAA==.Dotsrock:BAABNQAECn87AAMhAAoKmhXNBQAdAgAhAAoKmhXNBQAdAgAdAAUKcQfxCgG2AAAAAA==.Dovah:BAAANQADCgIIAgAAAA==.',
Dr='Dragoneggs:BAABNQAECn8jAAMSAAoKBBkXDQCRAgASAAoKBBkXDQCRAgAiAAoKBQp2HwDdAQAAAA==.Dragonforce:BAAANQADCggIEgAAAA==.Drakonutz:BAAANQAECgYIDwAAAA==.Draxx:BAAANQAECggIDQABNQAECggIEgAEAAAAAA==.Drañzer:BAAANQAECgEIAgAAAA==.Dreammachine:BAAANQAECgcIBwAAAA==.Drjoel:BAAANQADCgcIEQAAAA==.Drunkenutz:BAABNQAECn8ZAAQWAAkK7g0FQQCrAAAXAAUKLxCcIQDQAAAWAAUKPgwFQQCrAAAjAAQKcA+vLACeAAAAAA==.Drâx:BAAANQAECggICgABNQAECggIEgAEAAAAAA==.Dräx:BAAANQAECggIEgAAAA==.',
Dw='Dwallen:BAAANQADCgIIAgAAAA==.Dwightschrut:BAAANQADCgQIBAAAAA==.',
['Dä']='Dälf:BAAANQAECgIIAgABNQAFFAcICQAPABsVAA==.',
Ea='Earthshocker:BAABNQAECn8jAAMJAAoKzxOyNAADAgAJAAoKzxOyNAADAgARAAEKXAD/FQENAAAAAA==.',
Ed='Edirii:BAAANQABCgIIAgAAAA==.',
El='Elenix:BAAANQAECgcIAQAAAA==.Elki:BAAANQADCgQIBgAAAA==.Elmesia:BAABNQAECn8UAAICAAcKTQjwGAFiAQACAAcKTQjwGAFiAQAAAA==.Eloris:BAABNQAECn8lAAILAAgK7RxGHABzAgALAAgK7RxGHABzAgAAAA==.Elpato:BAAANQADCgcIBwABNQAECgoKOAACAHAlAA==.Elthyn:BAAANQAECggIDwAAAA==.Elvar:BAAANQAECgEIAQAAAA==.',
Em='Emachine:BAAANQADCggICAABNQAECgIIAgAEAAAAAA==.Emeraldrin:BAAANQADCgIIAgAAAA==.Emz:BAABNQAECn89AAIeAAkK7yBTAQCZAgAeAAkK7yBTAQCZAgAAAA==.',
En='Eniar:BAAANQAECgQIBgAAAA==.',
Er='Erakk:BAAANQADCgEIAgAAAA==.Erianda:BAAANQABCgQIBAAAAA==.Eric:BAABNQAECn8eAAIUAAgKNBqiegAoAgAUAAgKNBqiegAoAgAAAA==.Eroninja:BAAANQAECgYICAABNQAECgoKLgAJAGcaAA==.Erín:BAABNQAECn8wAAIdAAcKxxLQhgBRAQAdAAcKxxLQhgBRAQAAAA==.',
Es='Estropajo:BAAANQAECgEIAQAAAA==.',
Eu='Eurong:BAACNQAFFH8HAAIBAAQKsxE4FgAGAQABAAQKsxE4FgAGAQA1AAQKfzcAAgEACgoCIyUJAAoDAAEACgoCIyUJAAoDAAAA.',
Ez='Ezynuff:BAABNQAECn8ZAAMJAAgKtQlKzAD6AAAJAAcKjgdKzAD6AAARAAUKxwt+sAC6AAAAAA==.',
Fa='Faner:BAAANQADCgEIAgABNQAECgEIAQAEAAAAAA==.Fapple:BAAANQAECgUICQABNQAECgoKPAAiACMjAA==.Fatesworn:BAAANQADCgcIBwAAAA==.Faïry:BAABNQAECn9AAAINAAoKSSQdCABLAwANAAoKSSQdCABLAwAAAA==.',
Fe='Feaughoeren:BAABNQAECn8vAAMfAAoKxAvlEgDoAQAfAAoKxAvlEgDoAQARAAkKpQUxdwBNAQAAAA==.Felwyrm:BAABNQAECn8sAAIdAAkKgRd4UABjAgAdAAkKgRd4UABjAgABNQAFFAUIDgAWAFoEAA==.Feralina:BAAANQABCgIIAgAAAA==.Feralshmeral:BAAANQABCgQIBAABNQAECgoKIgANAKAhAA==.',
Fo='Foxi:BAAANQADCggIEQABNQAECgkJGgAFAHocAA==.',
Fr='Frank:BAAANQAECggIEAAAAA==.Freakbeast:BAAANQAECgcIEgABNQAECgoKJwAeAFYjAA==.Fries:BAEANQAECggICwABNQAECggIDwAEAAAAAA==.',
Fu='Fullkidney:BAACNQAFFH8KAAIaAAQKeB4fCgBfAQAaAAQKeB4fCgBfAQA1AAQKfyAAAhoACQrbIqAJAEIDABoACQrbIqAJAEIDAAAA.Funch:BAABNQAECn8xAAIhAAoKXhUhBQB4AgAhAAoKXhUhBQB4AgAAAA==.',
Ga='Gaefaeryn:BAACNQAFFH8KAAIGAAQKow5nDADRAAAGAAQKow5nDADRAAA1AAQKfyoAAwYACgq0GX0bAGwCAAYACgq0GX0bAGwCAAgAAQqaAQ0yAB8AAAAA.Gainzz:BAAANQAECgEIAQAAAA==.Garonnaa:BAABNQAECn84AAIQAAoKChvdEgB8AgAQAAoKChvdEgB8AgAAAA==.Garthel:BAABNQAECn84AAIWAAoKLxfJEgA2AgAWAAoKLxfJEgA2AgAAAA==.',
Ge='Genetiks:BAAANQADCgYIDAAAAA==.',
Gh='Ghari:BAABNQAECn8uAAIZAAcK4xE3NwA/AQAZAAcK4xE3NwA/AQAAAA==.',
Gi='Gingerlock:BAABNQAECn84AAIdAAoKlBxyLABdAgAdAAoKlBxyLABdAgAAAA==.Gingershaman:BAAANQAECgUIBQAAAA==.Giyuu:BAAANQADCgUIBQAAAA==.',
Gn='Gnoblin:BAAANQADCggIFgAAAA==.',
Gr='Greka:BAABNQAECn8iAAIJAAcKKwvPbgA8AQAJAAcKKwvPbgA8AQAAAA==.Greylooms:BAAANQADCgcIBwAAAA==.Griplock:BAABNQAECn9SAAMQAAoKHQ8HMACOAQAQAAoK1gwHMACOAQAVAAIKQRFfkwB4AAAAAA==.',
Gu='Gutz:BAAANQAECgUICwAAAA==.',
['Gö']='Gözër:BAAANQADCgMIAwABNQAECgYIBgAEAAAAAA==.',
Ha='Happyfriend:BAAANQAECgEIAQABNQAFFAUIDgAWAFoEAA==.Haruko:BAAANQADCggICAAAAA==.',
He='Healalle:BAAANQADCgYICwABNQAECgkJFwAgAPMdAA==.Healhole:BAABNQAECn81AAMRAAoKZyFREwAwAwARAAoKZyFREwAwAwAJAAMKbhFO7gC6AAAAAA==.Heimdall:BAAANQAECgEIAgAAAA==.Heàl:BAABNQAECn8cAAMGAAkKuCDoDwD3AgAGAAkKuCDoDwD3AgAIAAEKwxQ0JgA+AAAAAA==.',
Hi='Hidolo:BAAANQADCgYIDAAAAA==.',
Ho='Holizq:BAAANQAECgQIBAAAAA==.',
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
It='Itiswhatitiz:BAABNQAECn9IAAINAAoKRRziNgBvAgANAAoKRRziNgBvAgAAAA==.Itsybityshiv:BAABNQAECn81AAIkAAoKshgKDwCJAgAkAAoKshgKDwCJAgAAAA==.',
Ja='Jackspanko:BAAANQAECgEIAQAAAA==.Jakarr:BAAANQADCgUICQAAAA==.Jams:BAAANQAECgUIBQAAAA==.',
Je='Jeabuss:BAAANQADCgUIBQAAAA==.Jerricho:BAAANQAECgcIDQAAAA==.',
Jh='Jhani:BAABNQAECn8nAAIlAAkKUwb6GQAOAQAlAAkKUwb6GQAOAQAAAA==.',
Ji='Jiu:BAABNQAECn8cAAIFAAkKiBsVJgDTAgAFAAkKiBsVJgDTAgABNQAECggIFwAZAMQbAA==.',
Jo='Joethemage:BAABNQAECn82AAICAAoKSB3lRAD6AgACAAoKSB3lRAD6AgAAAA==.Jormojo:BAAANQAECgMIAwAAAA==.',
Ju='Jungol:BAAANQADCgUICQAAAA==.',
['Jå']='Jådê:BAAANQAECgMIAwABNQAFFAYIDAAGAKoLAA==.',
Ka='Kairupaws:BAAANQAECgUIBQAAAA==.Kallip:BAAANQADCggICAAAAA==.Kamin:BAAANQAECgYIBgABNQAECgkJIgACAMgbAA==.Katamaran:BAAANQAECgMIBAABNQAFFAYIDAAGAKoLAA==.Kaykaypally:BAABNQAECn8oAAIDAAkKNBIffADVAQADAAkKNBIffADVAQAAAA==.Kazbirt:BAAANQADCgIIAgAAAA==.',
Ke='Kellan:BAAANQADCggIFgAAAA==.',
Kh='Khybyr:BAAANQADCgMIAwAAAA==.',
Ki='Kidata:BAABNQAECn8mAAIjAAoKlxVCFgAYAgAjAAoKlxVCFgAYAgAAAA==.Kindaprepped:BAAANQADCgQIBAAAAA==.Kinji:BAABNQAECn8uAAIJAAoKZxrkSABTAgAJAAoKZxrkSABTAgAAAA==.Kinn:BAAANQADCggICAABNQAECgoKNwAXAOkXAA==.',
Ko='Konfu:BAABNQAECn8ZAAMWAAoKiw+/HAC/AQAWAAkKiw+/HAC/AQAjAAIKpgViPAA8AAAAAA==.Kormega:BAAANQAECgUIBQAAAA==.Korral:BAAANQADCggIDQAAAA==.',
Kr='Krispies:BAAANQAECgUIDQAAAA==.Kristysavage:BAABNQAECn9KAAMmAAoKoCI9AQBtAwAmAAoKoCI9AQBtAwANAAMKoBzkBQGnAAAAAA==.Krul:BAAANQAECgUIBQAAAA==.',
Ku='Kulaesca:BAACNQAFFH8RAAIdAAUKLhZXEAAvAQAdAAUKLhZXEAAvAQA1AAQKfzAAAx0ACgqiHKVHAHwCAB0ACgqiHKVHAHwCABwAAQrtAOWHAB0AAAAA.',
Ky='Kynar:BAACNQAFFH8fAAMVAAkKox5rAgAmAgAVAAkKox5rAgAmAgAQAAYKngfuEABIAQA1AAQKfzAAAxUACgpZJkQKAEkDABUACgpZJkQKAEkDABAAAwqHE7qWALEAAAAA.Kyua:BAAANQAECgUIBAAAAA==.',
La='Ladragona:BAAANQADCggICAAAAA==.Laguna:BAAANQAECgQIBAABNQAECgoKNgAFAJ0XAA==.Lambshot:BAABNQAECn8vAAMOAAoKTxsuEQAsAgAOAAoKGxguEQAsAgANAAgK6xYAdgAkAgAAAA==.Lambsy:BAACNQAFFH8kAAQUAAkK9xIZBwBPAgAUAAkK9xIZBwBPAgAnAAEKAAAaBgBIAAAgAAEKAACwCQA9AAA1AAQKf0sAAxQACgpsJVsJAEUDABQACgpoJVsJAEUDACcAAwpvIq8dAMMAAAAA.Lanamama:BAAANQAECgEIAQABNQAECgIIAgAEAAAAAA==.Lanana:BAAANQADCgMIAwABNQAECgIIAgAEAAAAAA==.',
Le='Ledsole:BAAANQABCgIIAgAAAA==.Lerat:BAABNQAECn87AAISAAoKZR/NAwC0AgASAAoKZR/NAwC0AgAAAA==.',
Li='Lightfoot:BAAANQAECgIIAgAAAA==.Lightwarden:BAAANQADCgQIBAAAAA==.Lilyy:BAACNQAFFH8LAAMlAAQKexFHBADUAAAlAAQKexFHBADUAAACAAIKAAokTgCKAAA1AAQKfy4AAyUACgqqHYgGAJcCACUACApFH4gGAJcCAAIACQp8F4JzAJcCAAAA.Lisanalgaib:BAABNQAECn8uAAIDAAkKORWrjwCtAQADAAkKORWrjwCtAQAAAA==.Lizzimcguire:BAACNQAFFH8RAAISAAUKhiENAQB/AQASAAUKhiENAQB/AQA1AAQKf0EAAhIACgpqJXgBALYDABIACgpqJXgBALYDAAAA.',
Lo='Lobobare:BAABNQAECn8fAAITAAgK2x0hHABVAgATAAgK2x0hHABVAgAAAA==.Loraen:BAABNQAECn8lAAICAAkKWgWMoABjAQACAAkKWgWMoABjAQAAAA==.Lostep:BAAANQAECgEIAQABNQAFFAkJIgARAJgYAA==.',
Lu='Lunarmon:BAAANQADCgUIBQAAAA==.Lunchable:BAABNQAECn8mAAMRAAoKex2bJgCUAgARAAoKex2bJgCUAgAJAAcKzBV7gACjAQAAAA==.',
Ma='Maevora:BAABNQAECn8ZAAIGAAcKawSBTQDeAAAGAAcKawSBTQDeAAAAAA==.Makaroni:BAAANQAECgUICgAAAA==.Malbèc:BAAANQAECgcIBwAAAA==.Manticus:BAAANQADCgYICAAAAA==.Marni:BAABNQAECn8cAAMFAAgK3hKzcgDEAQAFAAgK3hKzcgDEAQAGAAIKAAAIdAAAAAABNQAECgoKKwADAOEhAA==.Marsrover:BAAANQAECgIIAgABNQAFFAkJIwAUAHccAA==.Martel:BAAANQADCgQIBAAAAA==.Matroxx:BAACNQAFFH8SAAIWAAcKNRcSBwCLAQAWAAcKNRcSBwCLAQA1AAQKf0gAAhYACgrKJL8FABUDABYACgrKJL8FABUDAAAA.',
Me='Medinduceyuh:BAAANQADCgEIAQAAAA==.Meenoi:BAABNQAECn8XAAIZAAgKxBtHRQAEAgAZAAgKxBtHRQAEAgAAAA==.Mellotots:BAAANQABCgIIBAAAAA==.Metatron:BAAANQADCgIIAgAAAA==.',
Mi='Miadas:BAAANQAECgMIAwABNQAECgkJQgAHAAshAA==.Mika:BAAANQAECgMIAwABNQAFFAQIBQAFAE4GAA==.Milire:BAAANQABCgMIAgAAAA==.Mimikyu:BAAANQABCgYIBgAAAA==.Minìwheats:BAAANQADCgMIAwAAAA==.',
Mo='Moardotsnow:BAABNQAECn8xAAQcAAoKaCUwGACrAQAdAAcKoCXpVgBRAgAcAAQKCiUwGACrAQAhAAEKxB7kJwBKAAAAAA==.Moby:BAAANQAECgcIDAAAAA==.Moistmender:BAAANQAECggIEwAAAA==.Mortiana:BAAANQADCggICAAAAA==.',
Mu='Murriar:BAAANQAECggICQABNQAECgoKMAAoABQhAA==.Murridan:BAABNQAECn8wAAIoAAoKFCFtDgDDAgAoAAoKFCFtDgDDAgAAAA==.',
My='Mykaela:BAAANQAECgEIAQAAAA==.',
['Më']='Mëow:BAABNQAECn8XAAMbAAgKYwX7VwBlAAAbAAYKygL7VwBlAAAHAAMKtAdmPABdAAAAAA==.',
Na='Naausi:BAAANQADCgMIAwAAAA==.Namiyu:BAAANQADCgcIBwAAAA==.Nara:BAAANQAECgQIBAAAAA==.Narrath:BAAANQADCgMJAwAAAA==.Nayalaah:BAAANQAECgEIAQAAAA==.',
Ne='Nehpets:BAAANQADCgUIBQAAAA==.Nektzalla:BAABNQAECn8iAAIRAAoK6RlpLQBuAgARAAoK6RlpLQBuAgAAAA==.Nephelym:BAABNQAECn8gAAMFAAgKQA9ZcwDCAQAFAAgKQA9ZcwDCAQAIAAIKrAKOJABHAAAAAA==.Nerv:BAAANQADCgMIBQAAAA==.',
Ni='Nicolasmage:BAAANQABCgQIBQAAAA==.Nirina:BAABNQAECn8hAAINAAYK7wmt4ADwAAANAAYK7wmt4ADwAAAAAA==.',
No='Nohtil:BAAANQADCgcIHAAAAA==.Notstephen:BAABNQAECn8lAAMFAAoK6Ay3dQC7AQAFAAoK6Ay3dQC7AQAGAAQKCxBIWACpAAAAAA==.Nourishnutz:BAAANQADCgYIBgAAAA==.',
Nu='Nukefury:BAACNQAFFH8FAAIfAAQKWAieBADHAAAfAAQKWAieBADHAAA1AAQKfyQAAh8ACQrkHYYIAJwCAB8ACQrkHYYIAJwCAAAA.Nut:BAABNQAECn8UAAIcAAUKoBIjJwA+AQAcAAUKoBIjJwA+AQABNQAECggIKwAQAKASAA==.',
Nw='Nwalliance:BAAANQAECgEIAQAAAA==.',
['Nö']='Nötprepared:BAAANQAECgUIBAABNQAECgUICQAEAAAAAA==.',
Oi='Oiflar:BAABNQAECn8mAAIiAAoK+BgXCwB7AgAiAAoK+BgXCwB7AgABNQAECgoKPAAiACMjAA==.',
Ol='Olangi:BAAANQAECgEIAQAAAA==.',
Om='Omnidh:BAAANQADCggIEAABNQAFFAUIEQAWAKEfAA==.Omnipotent:BAAANQAECgUIBQAAAA==.',
On='Onepavo:BAABNQAECn9DAAIkAAoKJBOFRADsAQAkAAoKJBOFRADsAQAAAA==.',
Oo='Oogie:BAAANQADCgYIBgAAAA==.Oogrikusk:BAAANQADCgIIAgAAAA==.Oottedenttoo:BAAANQADCgQIBAAAAA==.',
Op='Oppose:BAABNQAECn8YAAQHAAgKwhS+GwAvAQABAAcKbA2qVACGAQAHAAYK6BO+GwAvAQATAAQK9wxEUwC7AAAAAA==.',
Or='Orexion:BAABNQAECn8jAAInAAgKGwtAEgCAAQAnAAgKGwtAEgCAAQAAAA==.Oriavis:BAAANQAECgMIAwAAAA==.Ormagöden:BAABNQAECn8pAAIVAAoKMw2QQwC1AQAVAAoKMw2QQwC1AQAAAA==.',
Ov='Overpower:BAAANQADCgYIBgAAAA==.',
Pa='Pagoda:BAABNQAECn8ZAAIBAAgKYwzyPgAuAQABAAgKYwzyPgAuAQAAAA==.Palladean:BAAANQAECgIIAwAAAA==.Palphen:BAAANQAECgcJDAABNQAECgoKJQAFAOgMAA==.Panako:BAAANQAECgUICQAAAA==.Pastasauce:BAABNQAECn8dAAIDAAYK3wnl/QAjAQADAAYK3wnl/QAjAQAAAA==.',
Pe='Pegero:BAAANQADCgYIDQABNQAFFAMIBQANAFgXAA==.Penelohpe:BAABNQAECn8iAAICAAkKyBt4fQCDAgACAAkKyBt4fQCDAgAAAA==.',
Ph='Phatt:BAAANQAECgMIAwAAAA==.Phoenixdrac:BAAANQADCggICQAAAA==.Phoon:BAECNQAFFH8NAAMdAAQKzxvsFgA+AQAdAAQKzxvsFgA+AQAcAAEKKRG4HgBLAAA1AAQKfzcABB0ACgpoI1M8AJ4CAB0ACAovI1M8AJ4CABwABAqiIXAkAE8BACEAAQpJDj4uADcAAAAA.Phoondk:BAEANQAECgUICAABNQAFFAQIDQAdAM8bAA==.',
Pi='Piggy:BAABNQAECn8lAAIRAAoKFwgLhQAlAQARAAoKFwgLhQAlAQAAAA==.Pita:BAAANQABCgYIBgAAAA==.Pitaya:BAAANQAECggIDgAAAA==.Pizzadriver:BAACNQAFFH8jAAMUAAkKdxwXBACZAgAUAAkKdxwXBACZAgAnAAEKAADIBQBLAAA1AAQKfzYAAxQACgouJqcHAFEDABQACgomJqcHAFEDACcAAQo9JuEnAG4AAAAA.',
Pl='Plaguefist:BAAANQADCgcIBwABNQADCggIEgAEAAAAAA==.Plata:BAABNQAECn8mAAIUAAkKhBUAbAC9AQAUAAkKhBUAbAC9AQAAAA==.',
Po='Poosicat:BAAANQABCgYIBgAAAA==.Poosycat:BAAANQADCgMIAQAAAA==.',
Pr='Praytroxx:BAABNQAECn8UAAIGAAcKmRK0KQA3AQAGAAcKmRK0KQA3AQABNQAFFAcIEgAWADUXAA==.Premonitions:BAAANQAECgYIBgAAAA==.Premune:BAABNQAECn82AAIYAAoKWyGaLgCsAgAYAAoKWyGaLgCsAgAAAA==.Prion:BAABNQAECn8cAAQoAAoKSxVSMAAlAgAoAAoKnhNSMAAlAgALAAEKlRTlaABAAAAKAAEKOgt4NAAqAAAAAA==.',
Pu='Pucco:BAAANQADCgIIAgAAAA==.Purpleflurp:BAAANQAECggICgAAAA==.Putrav:BAAANQAECgYICAAAAA==.',
Py='Pyrena:BAAANQADCgEIAQAAAA==.Pyroclasm:BAAANQAECgUICgAAAA==.Pyrrha:BAAANQADCgMIAwAAAA==.',
Qu='Quigly:BAAANQADCgIIAgAAAA==.',
Ra='Ragingfluids:BAABNQAECn8pAAMnAAoKNBZSEgB+AQAUAAoKohV/cACxAQAnAAYKnBRSEgB+AQAAAA==.Rahdek:BAAANQADCgMIAwAAAA==.Raine:BAACNQAFFH8iAAIRAAkKmBgyBAA/AgARAAkKmBgyBAA/AgA1AAQKfy0AAxEACgrGFRpSAB4CABEACgrGFRpSAB4CAAkACAqxGslPAJkBAAAA.Raistlin:BAAANQADCgEIAQAAAA==.Ralfio:BAABNQAECn88AAMiAAoKIyN0BgACAwAiAAoKIyN0BgACAwApAAEKAACVJAAzAAAAAA==.Ralfiosky:BAAANQAECgMIAwABNQAECgoKPAAiACMjAA==.Rasq:BAABNQAECn8VAAMbAAkK9QUqLAA3AQAbAAkK9QUqLAA3AQABAAEKAACnzAAUAAAAAA==.Rat:BAABNQAECn8XAAIaAAkKNCGiCABOAwAaAAkKNCGiCABOAwAAAA==.Raudykill:BAAANQAECgcIBgAAAA==.Rayaray:BAAANQADCgYICgAAAA==.Raynith:BAABNQAECn9CAAUHAAkKCyGXDQD0AQABAAkK2h1eLQByAgAHAAcK0yGXDQD0AQAbAAMK4xFbVwBmAAATAAEKPBnhbQBKAAAAAA==.Rayraye:BAAANQADCgcICQAAAA==.Raytard:BAAANQADCgcIBwAAAA==.',
Rd='Rdyoshy:BAAANQADCgUIBQAAAA==.',
Re='Readycheck:BAABNQAECn9GAAQBAAoKghSDHwADAgABAAoKghSDHwADAgAbAAcKyQg3MAAaAQATAAIKqA73ZQBiAAAAAA==.Reflex:BAAANQAECgIIAgAAAA==.Regirock:BAAANQABCgMIAwAAAA==.Rellek:BAAANQAECgIIAgAAAA==.Remulous:BAABNQAECn8aAAINAAgKBRNpjQDvAQANAAgKBRNpjQDvAQAAAA==.Resist:BAAANQADCgYIBgAAAA==.Retallica:BAABNQAECn8vAAIDAAoK4A9mdQDjAQADAAoK4A9mdQDjAQAAAA==.Revali:BAACNQAFFH8KAAIOAAUKZw3BDQBhAQAOAAUKZw3BDQBhAQA1AAQKf0wAAw0ACgq3IMsxANcCAA0ACgp0HcsxANcCAA4ACgrEGUkYAJUCAAAA.Revelaen:BAAANQAECgcIDwABNQAFFAUICgAOAGcNAA==.',
Ri='Rick:BAACNQAFFH8NAAIOAAMKwxx8FAD5AAAOAAMKwxx8FAD5AAA1AAQKfzMAAw4ACgr8ImUGAOUCAA4ACgq/ImUGAOUCAA0ABApOIHIDAf4AAAAA.',
Rm='Rmagep:BAAANQAECgUICwAAAA==.',
Ro='Roadhouse:BAAANQAECgQIBwAAAA==.Roman:BAAANQAECgYIDAABNQAFFAUICAAiAMsfAA==.Roshango:BAAANQADCgYIBgAAAA==.Rosinator:BAAANQAECggIAQAAAA==.Rotgus:BAAANQAECgEIAQAAAA==.Rouk:BAABNQAECn8eAAIUAAoKjBxqKACeAgAUAAoKjBxqKACeAgABNQAECgoKKwADALsmAA==.Rowgar:BAABNQAECn8jAAIQAAoKmxr0IgDjAQAQAAoKmxr0IgDjAQAAAA==.',
Ru='Rubenslik:BAABNQAECn80AAICAAoKqSEQLAA3AwACAAoKqSEQLAA3AwAAAA==.',
Sa='Saelyn:BAAANQADCggIBgAAAA==.Saephora:BAABNQAECn8eAAIlAAcKuwanHgD2AAAlAAcKuwanHgD2AAAAAA==.Saggypants:BAABNQAECn8fAAIBAAoKXBS+LwBjAgABAAoKXBS+LwBjAgAAAA==.Sakurai:BAAANQAECgEIAQABNQAECgIIAgAEAAAAAA==.Salamander:BAAANQAECgUJCgAAAA==.Salazzle:BAAANQADCgQIBAAAAA==.Sammel:BAAANQAECgUIEAAAAA==.Sanari:BAAANQADCgUIBwABNQAECgoKLgAJAGcaAA==.Sandilla:BAAANQADCggICAABNQAECgoKIgAJAIokAA==.Sangwine:BAAANQADCgYIBgAAAA==.Sapphica:BAAANQAECgEIAgAAAA==.Sargus:BAAANQADCgUICAAAAA==.Sathreina:BAABNQAECn84AAIDAAoKDRhqdABFAgADAAoKDRhqdABFAgAAAA==.Sativva:BAAANQAECgIIAgABNQAECgoKIgAJAIokAA==.',
Sc='Scaries:BAABNQAECn8gAAIXAAoK4RlTBwDIAgAXAAoK4RlTBwDIAgAAAA==.Scootko:BAABNQAECn8fAAIDAAkKCiXsQQDPAgADAAkKCiXsQQDPAgAAAA==.Scuss:BAAANQADCggICAAAAA==.',
Se='Sego:BAAANQAECgcICQAAAA==.Sekimaru:BAAANQAECgIIAgAAAA==.Senli:BAAANQAECgEIAQAAAA==.Severson:BAABNQAECn8bAAIOAAgKXAxfNACrAQAOAAgKXAxfNACrAQAAAA==.Sey:BAAANQADCgYIBgAAAA==.',
Sh='Shadowapoke:BAAANQADCgUIBQABNQAECgEIAQAEAAAAAA==.Shadowisbad:BAABNQAECn8qAAIGAAoKehhYHABiAgAGAAoKehhYHABiAgAAAA==.Shadvoker:BAABNQAECn8iAAMiAAgKzx2iDgC/AgAiAAgKzx2iDgC/AgASAAIK1BHUMwBvAAAAAA==.Shamaneggs:BAABNQAECn8uAAMRAAoKKSCxDwA/AwARAAoKKSCxDwA/AwAfAAMKshBOKQDRAAAAAA==.Shamatroxx:BAABNQAECn8tAAIfAAkKchwcEQBXAgAfAAkKchwcEQBXAgABNQAFFAcIEgAWADUXAA==.Shamberry:BAABNQAECn8aAAIfAAgKBRWDEQBRAgAfAAgKBRWDEQBRAgAAAA==.Shambles:BAAANQADCgYICQAAAA==.Sheilla:BAABNQAECn8ZAAMQAAgKcRLadQAgAQAQAAcKohTadQAgAQAZAAUKtwcJlADbAAAAAA==.Shieldslamer:BAABNQAECn8bAAIUAAkKfggCggCCAQAUAAkKfggCggCCAQAAAA==.Shieldwalle:BAABNQAECn8XAAIgAAkK8x0KCwCMAgAgAAkK8x0KCwCMAgAAAA==.Shinobukocho:BAAANQADCgQJBAAAAA==.Shlock:BAAANQAECgYICwAAAA==.Shotigolova:BAAANQADCgcIEgAAAA==.',
Si='Sidesalad:BAAANQAECgQIBgAAAA==.Sidric:BAABNQAECn8/AAIBAAoKfRFlIQDzAQABAAoKfRFlIQDzAQAAAA==.Siena:BAAANQADCggIDgAAAA==.Silre:BAABNQAECn8eAAMhAAcKAwyLEQAzAQAhAAcKewuLEQAzAQAcAAUKWweiHgB0AAAAAA==.Sim:BAABNQAECn8mAAIUAAkKLiSvFQBjAwAUAAkKLiSvFQBjAwABNQAECgoKIgAJAIokAA==.Singularité:BAAANQAECggIEgABNQAFFAgIDAAaAE0NAA==.Sipplex:BAAANQAECgYIDgAAAA==.',
Sl='Slander:BAAANQAECgQJBAABNQAECgUJCgAEAAAAAA==.Slanderous:BAAANQADCgEJAQABNQAECgUJCgAEAAAAAA==.Slappee:BAAANQAECgYIBwAAAA==.Slappeey:BAAANQAECgUICAABNQAECgYIBwAEAAAAAA==.',
Sn='Snuudle:BAAANQAECgcIDwABNQAECgkJHAAdABwXAA==.',
So='Solokills:BAAANQADCgMIAwABNQAFFAMIBQANAFgXAA==.Sophia:BAAANQAECgcIEgAAAA==.Soundtrack:BAAANQADCgYICQABNQAECgIIAgAEAAAAAA==.Soyshine:BAAANQADCgYIBgAAAA==.',
Sp='Spaceman:BAACNQAFFH8OAAIWAAUKWgQBCgDVAAAWAAUKWgQBCgDVAAA1AAQKfyYAAhYACgopFWoWAAkCABYACgopFWoWAAkCAAAA.',
Sq='Squab:BAABNQAECn8cAAIBAAkKaR6+GQD6AgABAAkKaR6+GQD6AgAAAA==.Squanchy:BAAANQADCgYJCAAAAA==.',
St='Stabbywixx:BAAANQAECgIIAgAAAA==.Stabsalot:BAAANQADCgMIAwAAAA==.Starwnd:BAABNQAECn8UAAIdAAcKlheaggDfAQAdAAcKlheaggDfAQABNQAFFAYIDgApAMcOAA==.Sterìs:BAAANQAECgEIAQAAAA==.Stillcreepin:BAAANQAECgIIAwAAAA==.Stompy:BAAANQAECgQIBAABNQAFFAYIDAAGAKoLAA==.Storienn:BAABNQAECn8aAAQYAAgKshECeACwAQAYAAgKshECeACwAQADAAUKWREQIgHmAAAPAAMKBw0UUQChAAAAAA==.Stormzpaly:BAAANQAECgYIEQAAAA==.',
Su='Suküna:BAAANQADCggIFwAAAA==.Sunbur:BAAANQADCgYICgAAAA==.Sunglo:BAAANQAECgUIBwAAAA==.Surch:BAAANQADCgEIAQAAAA==.',
Sw='Swaption:BAABNQAECn87AAIRAAoKDSMYDABkAwARAAoKDSMYDABkAwAAAA==.Sweetie:BAAANQADCgEIAQAAAA==.',
Sy='Synathia:BAAANQAECgcICAAAAA==.Syrelia:BAABNQAECn9WAAICAAoK9BmxOQBhAgACAAoK9BmxOQBhAgAAAA==.',
['Só']='Sónny:BAAANQABCgIIAgAAAA==.',
Ta='Tablescraps:BAAANQADCgYIBQABNQADCgIIAgAEAAAAAA==.Talonstrykz:BAAANQADCgUIBQAAAA==.Tassarosea:BAAANQAECgcIBwABNQAFFAUIEQASAIYhAA==.Tauloe:BAABNQAECn8ZAAIJAAYKTAjokADoAAAJAAYKTAjokADoAAAAAA==.Tayna:BAABNQAECn8dAAIGAAgKAAwGKQA8AQAGAAgKAAwGKQA8AQAAAA==.',
Te='Tenderoni:BAAANQADCgEIAQAAAA==.',
Th='Thatsmyhorse:BAAANQADCgIIAgAAAA==.Thatsograven:BAAANQADCgQIBAABNQAFFAgIIAABAOAfAA==.Thomosaurus:BAAANQADCggIDAAAAA==.Thraly:BAAANQADCgYIBwAAAA==.Thunk:BAABNQAECn8iAAIJAAoKiiTACwCJAwAJAAoKiiTACwCJAwAAAA==.',
Ti='Timdawg:BAABNQAECn8XAAMlAAkKLCFXDAD2AQAlAAcK0SNXDAD2AQACAAUKahLJQAEhAQABNQAFFAkJIwAdAIAaAA==.Timmolate:BAACNQAFFH8jAAQdAAkKgBr9BgD6AQAdAAcKGRz9BgD6AQAcAAIKwRfpCgCjAAAhAAIKRAkmDQBLAAA1AAQKfz4ABB0ACgrLJZUWAMYCAB0ACQo1JJUWAMYCABwACAoMGQULAEcCACEAAQoqJkUhAG0AAAAA.Tiramisubear:BAAANQAECggIDgAAAA==.Tircaps:BAAANQADCgUIBQAAAA==.',
To='Tomcruise:BAAANQAECgIIAgAAAA==.Tomotostein:BAACNQAFFH8LAAIDAAUK5gx0GgDAAAADAAUK5gx0GgDAAAA1AAQKfzEAAgMACgoCG4JbAB4CAAMACgoCG4JbAB4CAAAA.Tornado:BAAANQABCgQICQABNQADCgQIBAAEAAAAAA==.',
Tr='Trilla:BAAANQAECgcIDgAAAA==.Tristîtia:BAABNQAECn8ZAAMGAAkK/A4nJAAQAgAGAAkK/A4nJAAQAgAFAAIKCwki5gB1AAAAAA==.Trulu:BAAANQAECgEIAQAAAA==.',
Ts='Tsukikyo:BAAANQADCgQIBAAAAA==.Tsuma:BAAANQADCgUIBQAAAA==.Tsume:BAAANQAECgcIEgAAAA==.',
Tt='Ttomas:BAABNQAECn8VAAMOAAkKuh9oOwB2AQANAAYKbCI8mQDVAQAOAAcKlhRoOwB2AQAAAA==.',
Ty='Tyrinn:BAABNQAECn8lAAIQAAoKgxHvKAC4AQAQAAoKgxHvKAC4AQAAAA==.Tyv:BAABNQAECn9MAAICAAoK1BKuWwADAgACAAoK1BKuWwADAgAAAA==.',
Ul='Ulmerideavus:BAAANQADCgcIBwAAAA==.',
Un='Unclejoey:BAAANQAECgMIAwABNQAECgoKPAAiACMjAA==.',
Up='Updatè:BAAANQAECgMIBAABNQAECgkJHAAGALggAA==.',
Ur='Urgent:BAAANQAECgUIBgAAAA==.',
Uz='Uzì:BAAANQADCgIIAgAAAA==.',
Va='Vainatetosix:BAAANQAECgUICQAAAA==.Vallodon:BAABNQAECn8kAAICAAkKHCISTgDlAgACAAkKHCISTgDlAgAAAA==.Vantablack:BAAANQABCgIIAgABNQADCgQIBAAEAAAAAA==.Vanwolfy:BAABNQAECn8fAAIgAAoK+hI9FQDUAQAgAAoK+hI9FQDUAQAAAA==.Vaylorian:BAABNQAECn8ZAAQPAAYK8hEiMAD8AAAPAAYK8hEiMAD8AAAYAAIKJQr/4QBUAAADAAIK+gU6hgFRAAAAAA==.',
Ve='Velectran:BAAANQADCgcIEAABNQAECgoKVgACAPQZAA==.Velorian:BAAANQADCgQIBwAAAA==.Velveeta:BAAANQAECgMIAwAAAA==.Veragon:BAAANQADCgcIBwAAAA==.',
Vf='Vfacer:BAAANQADCgEIAQAAAA==.',
Vi='Vikav:BAAANQAECgIIAgAAAA==.Vikimg:BAABNQAECn8bAAIFAAoKoBabVgAfAgAFAAoKoBabVgAfAgAAAA==.Violet:BAAANQADCgEIAQAAAA==.',
Vo='Voodoomike:BAAANQAECgQIBAAAAA==.Vortash:BAAANQADCgUIBwAAAA==.',
Vy='Vynle:BAAANQAECgEIAQAAAA==.',
Wa='Warheimer:BAABNQAECn8ZAAMZAAoKzg6LXwCRAQAZAAoKzg6LXwCRAQAQAAQKVgZpoQCUAAAAAA==.Warrgodx:BAABNQAECn9YAAMUAAoK1yTsDwCAAwAUAAoK1yTsDwCAAwAnAAEKygioMwA0AAABNQAFFAUIBgADAL4aAA==.',
Wh='Whoknows:BAAANQADCgIIAgAAAA==.',
Wo='Woogi:BAAANQADCgUIBQAAAA==.',
Wr='Wrongwookie:BAABNQAECn8uAAIJAAoKPBkpRwBaAgAJAAoKPBkpRwBaAgAAAA==.',
Ya='Yapper:BAAANQADCgMIAwAAAA==.',
Yo='Yolanda:BAAANQAECgIIAgAAAA==.Yoyohunty:BAABNQAECn8WAAImAAkKmw+JCADHAQAmAAkKmw+JCADHAQAAAA==.',
Yt='Ytix:BAAANQAECgEIAQAAAA==.',
Yu='Yumekoo:BAAANQAECgIIAgAAAA==.',
Za='Zabada:BAABNQAECn8aAAINAAYKYxD81gAEAQANAAYKYxD81gAEAQAAAA==.Zaldrea:BAAANQAECgcICQABNQAFFAYIDAAGAKoLAA==.Zandrea:BAAANQAECgcIEQABNQAFFAYIDAAGAKoLAA==.Zariee:BAAANQABCgIIAwAAAA==.',
Ze='Zehz:BAABNQAECn8aAAIVAAkKZAFhkgByAAAVAAkKZAFhkgByAAAAAA==.Zemsen:BAABNQAECn8nAAICAAkKoh3yawCmAgACAAkKoh3yawCmAgAAAA==.Zentrea:BAAANQAECggIDQABNQAFFAYIDAAGAKoLAA==.Zenyea:BAABNQAECn8jAAIRAAoKUhSHNwA8AgARAAoKUhSHNwA8AgABNQAFFAYIDAAGAKoLAA==.Zetta:BAACNQAFFH8MAAIGAAYKqgswCQB0AQAGAAYKqgswCQB0AQA1AAQKfzIAAgYACgq7HkENAIYCAAYACgq7HkENAIYCAAAA.',
Zo='Zome:BAABNQAECn9VAAMkAAoKoR0bHACkAgAkAAoKoR0bHACkAgAaAAEKlAM4pgAwAAAAAA==.Zorojoro:BAAANQAECgYIDgAAAA==.',
Zy='Zyndrael:BAABNQAECn8rAAIDAAoK4SHkLAAUAwADAAoK4SHkLAAUAwAAAA==.',
['Èl']='Èlytz:BAAANQADCgYICQAAAA==.',
['Êl']='Êlytz:BAAANQADCggJCAAAAA==.',
['ßl']='ßlue:BAAANQAECgYICwAAAA==.',
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
