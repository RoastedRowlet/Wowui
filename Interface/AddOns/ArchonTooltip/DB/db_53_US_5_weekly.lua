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

local lookup = {'Druid-Balance','Mage-Arcane','Paladin-Retribution','Unknown-Unknown','Priest-Holy','Priest-Discipline','Shaman-Elemental','DemonHunter-Vengeance','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','DeathKnight-Blood','Shaman-Restoration','Evoker-Devastation','Warrior-Arms','Monk-Brewmaster','Monk-Windwalker','Paladin-Holy','DeathKnight-Unholy','Rogue-Assassination','Druid-Feral','Druid-Guardian','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','Priest-Shadow','Rogue-Outlaw','Warrior-Protection','Warlock-Affliction','Evoker-Preservation','Monk-Mistweaver','Rogue-Subtlety','Mage-Frost','Hunter-Survival','Warrior-Fury','Druid-Restoration','DemonHunter-Havoc','Evoker-Augmentation','Shaman-Enhancement',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Accost:BAAANQADCgcIDQAAAA==.Achendron:BAAANQADCgUIBQABNQAFFAgIIAABAOAfAA==.Acronica:BAAANQAECgUIEgAAAA==.',
Ad='Addilynn:BAAANQABCgEIAQAAAA==.',
Ak='Akassa:BAAANQADCgcICwAAAA==.Aknologia:BAAANQAECgUICwABNQAECgoKGwACAPcOAA==.',
Al='Alecto:BAABNQAECn8ZAAIDAAkKlAZuaAD1AAADAAkKlAZuaAD1AAAAAA==.Allele:BAAANQAECgMIAwAAAA==.Allet:BAAANQADCggIFwABNQAECgcIDAAEAAAAAA==.',
Am='Amarah:BAABNQAECn8zAAIFAAoK4h7bDwD6AQAFAAoK4h7bDwD6AQAAAA==.Ameilie:BAABNQAECn9AAAMFAAoK0B/GHQD6AgAFAAoK0B/GHQD6AgAGAAgKUBX1AQBVAQAAAA==.',
An='Anapuwae:BAABNQAECn8UAAIHAAYKSA0CqwA+AQAHAAYKSA0CqwA+AQAAAA==.Animehero:BAABNQAECn8kAAMIAAoKYxygBQDRAgAIAAgKHCCgBQDRAgAJAAIKNhFrJgCBAAAAAA==.',
Ar='Arcant:BAABNQAECn8iAAICAAkK/hnBswAcAgACAAkK/hnBswAcAgAAAA==.Ardicov:BAAANQADCgYICwAAAA==.Argadin:BAAANQAECgUIBgABNQAECgoKKgAKANIhAA==.Arglock:BAAANQADCgcIBwABNQAECgoKKgAKANIhAA==.Argrekh:BAABNQAECn8qAAMKAAoK0iHQCgCHAwAKAAoK0iHQCgCHAwALAAEKQQ/phgA3AAAAAA==.Argreks:BAAANQADCgEIAgABNQAECgoKKgAKANIhAA==.Argrekt:BAAANQAECgIIAgABNQAECgoKKgAKANIhAA==.Aridol:BAAANQADCgYIBgAAAA==.Arigön:BAAANQADCgYICAAAAA==.Aronna:BAAANQADCgYICAAAAA==.Arosea:BAAANQADCgYIBgAAAA==.Arthaslk:BAABNQAECn9OAAMDAAoKtyW6AABmAwADAAoKtyW6AABmAwAMAAIKBAlJYgBUAAAAAA==.Aryssol:BAAANQADCggIEAAAAA==.',
At='Ate:BAABNQAECn8fAAINAAgK5g8zEQBYAQANAAgK5g8zEQBYAQAAAA==.Atlette:BAAANQAECgMIAwAAAA==.Attman:BAACNQAFFH8JAAIOAAQKbxHuFwDhAAAOAAQKbxHuFwDhAAA1AAQKf0AAAw4ACgrkIX8DANwCAA4ACgrkIX8DANwCAAcAAgpwFjFTAJoAAAAA.',
Au='Auradawn:BAAANQADCgcIDwAAAA==.',
Ba='Backwater:BAAANQADCggIDwABNQAECgcIDAAEAAAAAA==.Badhands:BAAANQAECgIIAgAAAA==.Baeator:BAAANQAECgEIAQABNQAFFAcIGAAPAO0PAA==.Balho:BAAANQABCgEIAgAAAA==.Barneystins:BAAANQABCgEIAgABNQADCgQIBAAEAAAAAA==.',
Be='Bearmane:BAABNQAECn8sAAIBAAoKYSKfDgBVAwABAAoKYSKfDgBVAwAAAA==.Beastarsfan:BAABNQAECn8lAAIHAAoK+CKPCwCLAwAHAAoK+CKPCwCLAwAAAA==.Behmow:BAABNQAECn8wAAIQAAoKMia2BwC1AwAQAAoKMia2BwC1AwAAAA==.Belithel:BAAANQAECgQIBgABNQAECgkJHgAHAIgXAA==.Bencreepin:BAAANQAECgUIEgAAAA==.Bernoulli:BAABNQAECn8lAAMRAAkK0BK0EADfAQARAAkK0BK0EADfAQASAAEKAADaQQAAAAAAAA==.',
Bi='Bigspitter:BAAANQADCgYIBgABNQAECgoKMQACAJckAA==.Bis:BAAANQADCgUJBQABNQAECgkJFgACAD0cAA==.',
Bl='Blessedxx:BAAANQAECgUIBgAAAA==.Bloodboo:BAAANQADCgQIBAAAAA==.Bloodyhpally:BAACNQAFFH8cAAITAAgKmBdDAwBoAgATAAgKmBdDAwBoAgA1AAQKfyUAAxMACgpcF2ArALoCABMACgpcF2ArALoCAAMAAgoXD4lmAXsAAAAA.',
Bo='Boopsnoopems:BAABNQAECn8VAAIMAAUKkg4KRgDYAAAMAAUKkg4KRgDYAAAAAA==.Borderline:BAAANQAECgUIBQABNQAFFAQIBwASAF4CAA==.',
Br='Bradcrit:BAAANQAECgEIAQAAAA==.',
Bu='Bubble:BAABNQAECn8VAAMTAAcKEAfJuQAJAQATAAYKIAfJuQAJAQADAAUKgggXJAHjAAAAAA==.Bulldoser:BAAANQADCgQIBAAAAA==.Burrfoot:BAAANQAECgIIAwAAAA==.Bustah:BAAANQAECgcIEgABNQAECggIFwAUAMQbAA==.',
Bw='Bwoodmorgan:BAAANQAECgYIDgAAAA==.',
By='Byron:BAAANQAECgQIBAAAAA==.',
Ca='Calene:BAACNQAFFH8LAAIVAAcKIA8kBQDkAQAVAAcKIA8kBQDkAQA1AAQKf0IAAhUACgp0ITYJAEYDABUACgp0ITYJAEYDAAAA.Candy:BAAANQAECgMIBQAAAA==.Cannedcorn:BAAANQAECgIIAgAAAA==.Caperusin:BAAANQAECgUICAAAAA==.Casare:BAAANQADCgYIFgAAAA==.Cayde:BAAANQADCgYJBgABNQAFFAUICgALAGcNAA==.',
Ce='Celestinee:BAAANQAECgYIEgAAAA==.Celyda:BAAANQAECgUICAAAAA==.',
Ch='Chabotloe:BAAANQAECgMIBQAAAA==.Chape:BAABNQAECn8dAAMTAAkKvhcQPgBsAgATAAkKvhcQPgBsAgADAAYK/BBE7wA+AQAAAA==.Chence:BAAANQADCgYIBgAAAA==.Chochalinda:BAABNQAECn8dAAMWAAgKvxGBBwA1AQAWAAcKXBCBBwA1AQAXAAUK8xTfLQArAQAAAA==.',
Ci='Cinderlee:BAAANQAECgUICQAAAA==.',
Co='Colexn:BAABNQAECn8dAAMYAAcK7hhnOgDoAQAYAAcK7hhnOgDoAQAUAAIKMhDJwQBnAAAAAA==.Cong:BAACNQAFFH8FAAIQAAQK3ghxIAD/AAAQAAQK3ghxIAD/AAA1AAQKfyQAAhAACQoVHvMnABoDABAACQoVHvMnABoDAAAA.Corg:BAAANQADCgYIBgAAAA==.Cornchipz:BAABNQAECn8bAAICAAoK9w5e0ADlAQACAAoK9w5e0ADlAQAAAA==.',
Cr='Crapsack:BAAANQABCgEIAQAAAA==.Croski:BAAANQADCgEIAQAAAA==.Cryonidus:BAAANQAECgEIAQAAAA==.',
Cu='Curves:BAAANQAECgEIAQAAAA==.',
Cy='Cypressa:BAAANQADCgQIBAAAAA==.',
Da='Daangalanng:BAABNQAECn8cAAITAAoKAxapRABTAgATAAoKAxapRABTAgAAAA==.Dabberoni:BAAANQAECgEIAQAAAA==.Daegra:BAABNQAECn8pAAIVAAoKXByaDwAEAwAVAAoKXByaDwAEAwAAAA==.Dankkush:BAAANQADCgQIBAAAAA==.Darkacedia:BAABNQAECn8vAAMZAAkKihXHTQBrAgAZAAkKihXHTQBrAgAaAAMKKwp9TwCRAAAAAA==.Darkzetta:BAAANQAECgIIAgABNQAFFAUICwAbAIUOAA==.Datbish:BAAANQAECgIIAgAAAA==.',
De='Deadlift:BAAANQAECgYIEgAAAA==.Deadlyhoof:BAAANQADCgUIBQAAAA==.Dealosed:BAABNQAECn8ZAAMVAAgKphkIKwA+AgAVAAgKeRkIKwA+AgAcAAQKDhXyEQDsAAAAAA==.Deathawolf:BAAANQAECgEIAQAAAA==.Deathkilera:BAAANQADCgUIBwAAAA==.Defy:BAAANQADCgYIBgAAAA==.Delenn:BAABNQAECn8XAAIWAAgKZxrsDQA6AgAWAAgKZxrsDQA6AgAAAA==.Demonclawz:BAAANQAECgYIBgAAAA==.Demonnyaa:BAAANQADCgcIBwAAAA==.Denor:BAAANQABCgEIAwAAAA==.Derzy:BAAANQADCgIIAgAAAA==.Dewygirl:BAAANQADCgcICgAAAA==.',
Dh='Dhuumystic:BAAANQADCgEIAQAAAA==.',
Di='Disastapyre:BAAANQAECgIIAgABNQAFFAIIBwANAH0GAA==.Disastasmite:BAAANQADCgIIBAABNQAFFAIIBwANAH0GAA==.Dive:BAABNQAECn8WAAICAAkKPRyyYwC3AgACAAkKPRyyYwC3AgAAAA==.',
Do='Doogru:BAABNQAECn8wAAIdAAkKChlSAwCzAQAdAAkKChlSAwCzAQAAAA==.Doogtwo:BAAANQADCggIHAABNQAECgkJMAAdAAoZAA==.Doryndoran:BAAANQAECgQIBQAAAA==.Dorynhashots:BAAANQADCgUIBQAAAA==.Dotproduct:BAAANQADCgEIAQABNQADCgIIAgAEAAAAAA==.Dotsrock:BAABNQAECn8gAAMeAAoKrxGGAgBZAQAeAAkKMhOGAgBZAQAZAAUKcQdLfACKAAAAAA==.Dovah:BAAANQADCgIIAgAAAA==.',
Dr='Dragoneggs:BAABNQAECn8iAAMPAAoKBBkXDQCRAgAPAAoKBBkXDQCRAgAfAAkK9Ql2HwDdAQAAAA==.Dragonforce:BAAANQADCggIEgAAAA==.Drakonutz:BAAANQAECgYIDwAAAA==.Draxx:BAAANQAECggICgAAAA==.Drañzer:BAAANQAECgEIAgAAAA==.Dreammachine:BAAANQAECgcIBwAAAA==.Drjoel:BAAANQADCgcIEQAAAA==.Drunkenutz:BAABNQAECn8ZAAQSAAkK7g1GHQC/AAARAAUKLxCcIQDQAAASAAUKPgxGHQC/AAAgAAQKcA9XEwCzAAAAAA==.Dräx:BAAANQAECggIEgAAAA==.',
Dw='Dwallen:BAAANQADCgIIAgAAAA==.Dwightschrut:BAAANQADCgQIBAAAAA==.',
['Dä']='Dälf:BAAANQAECgIIAgABNQAFFAcICQAMABsVAA==.',
Ea='Earthshocker:BAAANQAECgYIDAAAAA==.',
Ed='Edirii:BAAANQABCgIIAgAAAA==.',
El='Elenix:BAAANQAECgcIAQAAAA==.Elki:BAAANQADCgQIBgAAAA==.Elmesia:BAAANQAECgYIEgAAAA==.Eloris:BAABNQAECn8lAAIJAAgK7RxGHABzAgAJAAgK7RxGHABzAgAAAA==.Elpato:BAAANQADCgcIBwABNQAECgoKMQACAJckAA==.Elthyn:BAAANQAECgQIBwAAAA==.Elvar:BAAANQAECgEIAQAAAA==.',
Em='Emachine:BAAANQADCggICAABNQAECgIIAgAEAAAAAA==.Emeraldrin:BAAANQADCgEIAQAAAA==.Emz:BAABNQAECn8yAAIcAAkKCCBZAAA1AgAcAAkKCCBZAAA1AgAAAA==.',
En='Eniar:BAAANQAECgMIBgAAAA==.',
Er='Erakk:BAAANQADCgEIAgAAAA==.Erianda:BAAANQABCgQIBAAAAA==.Eric:BAABNQAECn8cAAIQAAcK5RyiegAoAgAQAAcK5RyiegAoAgAAAA==.Eroninja:BAAANQAECgIIAwABNQAECgkJHgAHAIgXAA==.Erín:BAABNQAECn8ZAAIZAAUKzxAKZQC4AAAZAAUKzxAKZQC4AAAAAA==.',
Eu='Eurong:BAACNQAFFH8HAAIBAAQKsxE4FgAGAQABAAQKsxE4FgAGAQA1AAQKfyMAAgEACgpsGX4PAF4BAAEACgpsGX4PAF4BAAAA.',
Ez='Ezynuff:BAAANQAECgYIDAAAAA==.',
Fa='Faner:BAAANQADCgEIAQABNQAECgEIAQAEAAAAAA==.Fapple:BAAANQAECgQIBwABNQAECgoKMAAfAKkfAA==.Fatesworn:BAAANQADCgcIBwAAAA==.Faïry:BAABNQAECn8qAAIKAAoKviFPCwAaAgAKAAoKviFPCwAaAgAAAA==.',
Fe='Feaughoeren:BAAANQAECgYICwAAAA==.Felwyrm:BAABNQAECn8nAAIZAAkKgRd4UABjAgAZAAkKgRd4UABjAgABNQAFFAQIBwASAF4CAA==.Feralina:BAAANQABCgIIAgAAAA==.Feralshmeral:BAAANQABCgQIBAABNQAECgkJHwAKABEiAA==.',
Fo='Foragh:BAAANQAECgcIDgABNQAECggIHwAfAGQTAA==.Foxi:BAAANQADCggIEQABNQAECgcIEwAEAAAAAA==.',
Fr='Frank:BAAANQAECggIDwAAAA==.Freakbeast:BAAANQAECgYJEgABNQAECgoKHAAcAK8gAA==.Fries:BAEANQAECgcICwABNQAECggIDwAEAAAAAA==.',
Fu='Fullkidney:BAACNQAFFH8KAAIVAAQKeB4fCgBfAQAVAAQKeB4fCgBfAQA1AAQKfyAAAhUACQrbIqAJAEIDABUACQrbIqAJAEIDAAAA.Funch:BAABNQAECn8mAAIeAAoKZxIhBQB4AgAeAAoKZxIhBQB4AgAAAA==.',
Ga='Gaefaeryn:BAACNQAFFH8HAAIbAAQKyAzJBADiAAAbAAQKyAzJBADiAAA1AAQKfyMAAxsACgpOFH0bAGwCABsACgpOFH0bAGwCAAYAAQqaAQ0yAB8AAAAA.Garonnaa:BAABNQAECn8hAAINAAoKUBRXBgDZAQANAAoKUBRXBgDZAQAAAA==.Garthel:BAABNQAECn8kAAISAAoKbRCECwBcAQASAAoKbRCECwBcAQAAAA==.',
Ge='Genetiks:BAAANQADCgYIDAAAAA==.',
Gh='Ghari:BAABNQAECn8jAAIUAAcKlxByHQD+AAAUAAcKlxByHQD+AAAAAA==.',
Gi='Gingerlock:BAABNQAECn8lAAIZAAoKKRmZGwCCAQAZAAoKKRmZGwCCAQAAAA==.Gingershaman:BAAANQAECgEIAQAAAA==.Giyuu:BAAANQADCgUIBQAAAA==.',
Gn='Gnoblin:BAAANQADCggIFgAAAA==.',
Gr='Greka:BAAANQAECgUIEQAAAA==.Greylooms:BAAANQADCgcIBwAAAA==.Griplock:BAABNQAECn8xAAMNAAoK6AwFJgDdAAANAAgKdQwFJgDdAAAYAAIKQA5hVwBcAAAAAA==.',
Gu='Gutz:BAAANQAECgMIAwAAAA==.',
['Gö']='Gözër:BAAANQADCgMIAwABNQAECgYIBgAEAAAAAA==.',
Ha='Happyfriend:BAAANQAECgEIAQABNQAFFAQIBwASAF4CAA==.Haruko:BAAANQADCggICAAAAA==.',
He='Healalle:BAAANQADCgYICwABNQAECgkJFwAdAPMdAA==.Healhole:BAABNQAECn8xAAMOAAoKZyFREwAwAwAOAAoKZyFREwAwAwAHAAMKbhFO7gC6AAAAAA==.Heimdall:BAAANQAECgEIAQAAAA==.Heàl:BAAANQAECggIDwAAAA==.',
Hi='Hidolo:BAAANQADCgYIDAAAAA==.',
Hu='Hunterishard:BAAANQAECgQIBAABNQAECgUIBgAEAAAAAA==.',
Hy='Hylaina:BAAANQADCgYJCgAAAA==.',
['Hô']='Hôlÿ:BAAANQADCggIDgAAAA==.',
Ia='Iamamonk:BAAANQADCgEIAQAAAA==.',
Ik='Ikerous:BAAANQADCgMIAwAAAA==.',
Il='Ilysa:BAAANQABCgQIBAAAAA==.',
Im='Imadwagon:BAAANQADCgcIAgAAAA==.Imcolorblind:BAAANQADCgIIAgAAAA==.Imhammered:BAAANQAECgYIDgAAAA==.',
Io='Ioun:BAAANQADCgMIAwAAAA==.Iounn:BAAANQADCgcIBwABNQAECggIIgAgAJkXAA==.',
Is='Isatku:BAAANQAECgEIAQAAAA==.',
It='Itiswhatitiz:BAABNQAECn8tAAIKAAgKIB2NOQC9AgAKAAgKIB2NOQC9AgAAAA==.Itsybityshiv:BAABNQAECn8tAAIhAAoKXxQKDwCJAgAhAAoKXxQKDwCJAgAAAA==.',
Ja='Jakarr:BAAANQADCgQIBAAAAA==.Jams:BAAANQAECgUIBQAAAA==.',
Je='Jeabuss:BAAANQADCgUIBQAAAA==.Jella:BAAANQADCgQIBAAAAA==.',
Jh='Jhani:BAABNQAECn8XAAIiAAcKsAapCgDcAAAiAAcKsAapCgDcAAAAAA==.',
Ji='Jiu:BAABNQAECn8cAAIFAAkKiBsVJgDTAgAFAAkKiBsVJgDTAgABNQAECggIFwAUAMQbAA==.',
Jo='Joethemage:BAABNQAECn8rAAICAAoK5Br9BgBeAgACAAoK5Br9BgBeAgAAAA==.Jormojo:BAAANQAECgMIAwAAAA==.',
Ju='Jungol:BAAANQADCgUICQAAAA==.',
Ka='Kallip:BAAANQADCggICAAAAA==.Kamin:BAAANQAECgYIBgABNQAECgkJIgACAMgbAA==.Katamaran:BAAANQAECgMIBAABNQAFFAUICwAbAIUOAA==.Kaykaypally:BAABNQAECn8YAAIDAAcKnxCBvgCgAQADAAcKnxCBvgCgAQAAAA==.',
Ke='Kellan:BAAANQADCggIFgAAAA==.',
Kh='Khybyr:BAAANQADCgMIAwAAAA==.',
Ki='Kidata:BAABNQAECn8iAAIgAAgKmRdCFgAYAgAgAAgKmRdCFgAYAgAAAA==.Kindaprepped:BAAANQADCgQIBAAAAA==.Kinji:BAABNQAECn8eAAIHAAkKiBfkSABTAgAHAAkKiBfkSABTAgAAAA==.Kinn:BAAANQADCggICAABNQAECgkJJQARANASAA==.',
Ko='Konfu:BAAANQADCgcIEQAAAA==.Kormega:BAAANQAECgUIBQAAAA==.Korral:BAAANQADCggIDQAAAA==.',
Kr='Krispies:BAAANQAECgUIDQAAAA==.Kristysavage:BAABNQAECn8yAAMjAAoKNx49AQBtAwAjAAoKWh09AQBtAwAKAAIK+RuXKwGZAAAAAA==.',
Ku='Kulaesca:BAACNQAFFH8MAAIZAAMKjBeUBwDzAAAZAAMKjBeUBwDzAAA1AAQKfyoAAxkACgoOGaVHAHwCABkACgoOGaVHAHwCABoAAQrtAOWHAB0AAAAA.',
Ky='Kynar:BAACNQAFFH8dAAMYAAgKxx1rAgAmAgAYAAcKxx1rAgAmAgANAAYKngfuEABIAQA1AAQKfykAAxgACgoRJkQKAEkDABgACgoRJkQKAEkDAA0AAwqHE7qWALEAAAAA.Kyua:BAAANQAECgEIAQAAAA==.',
La='Ladragona:BAAANQADCggICAAAAA==.Lambshot:BAABNQAECn8aAAMKAAkKERMAdgAkAgAKAAgK1RIAdgAkAgALAAcKixMwNwCVAQAAAA==.Lambsy:BAACNQAFFH8gAAQQAAgKXhUZBwBPAgAQAAgKXhUZBwBPAgAkAAEKAAAaBgBIAAAdAAEKAACwCQA9AAA1AAQKfzEAAxAACgrBI7cQAHsDABAACgq9I7cQAHsDACQAAwoCE/8hAKgAAAAA.Lanamama:BAAANQAECgEIAQABNQAECgIIAgAEAAAAAA==.Lanana:BAAANQADCgMIAwABNQAECgIIAgAEAAAAAA==.',
Le='Lerat:BAABNQAECn8sAAIPAAoKYxxlBwALAwAPAAoKYxxlBwALAwAAAA==.',
Li='Lightwarden:BAAANQADCgQIBAAAAA==.Lilyy:BAACNQAFFH8HAAMiAAIKuRLDBwCdAAAiAAIKuRLDBwCdAAACAAIKAAokTgCKAAA1AAQKfy0AAyIACgqYHYgGAJcCACIACAoxH4gGAJcCAAIACQp8F4JzAJcCAAAA.Lisanalgaib:BAABNQAECn8iAAIDAAgKPBUNQgBCAQADAAgKPBUNQgBCAQAAAA==.Lizzimcguire:BAACNQAFFH8IAAIPAAMKrR3eAAD+AAAPAAMKrR3eAAD+AAA1AAQKfzEAAg8ACgo9JXgBALYDAA8ACgo9JXgBALYDAAAA.',
Lo='Lobobare:BAABNQAECn8fAAIlAAgK2x0hHABVAgAlAAgK2x0hHABVAgAAAA==.Loraen:BAAANQAECgUIEgAAAA==.',
Lu='Lunarmon:BAAANQADCgUIBQAAAA==.Lunchable:BAABNQAECn8bAAMHAAgKuBd7gACjAQAHAAYKzBV7gACjAQAOAAYKWiLFJgBIAQAAAA==.',
Ma='Maevora:BAABNQAECn8ZAAIbAAcKawSBTQDeAAAbAAcKawSBTQDeAAAAAA==.Makaroni:BAAANQAECgUIBQAAAA==.Manticus:BAAANQADCgYICAAAAA==.Maomaoo:BAABNQAECn8WAAMNAAgKuA7adQAgAQANAAcKKhDadQAgAQAUAAUKtwcJlADbAAAAAA==.Marni:BAAANQAECgYIDwABNQAECgoKIQADAGwdAA==.Marsrover:BAAANQAECgIIAgABNQAFFAgIHwAQAD0eAA==.Martel:BAAANQADCgQIBAAAAA==.Mashunit:BAAANQABCgIIAgAAAA==.Matroxx:BAACNQAFFH8RAAISAAYKIxkSBwCLAQASAAYKIxkSBwCLAQA1AAQKfzIAAhIACgpxIyQHAF4DABIACgpxIyQHAF4DAAAA.',
Me='Medinduceyuh:BAAANQADCgEIAQAAAA==.Meenoi:BAABNQAECn8XAAIUAAgKxBtHRQAEAgAUAAgKxBtHRQAEAgAAAA==.Mellotots:BAAANQABCgIIBAAAAA==.Metatron:BAAANQADCgIIAgAAAA==.',
Mi='Miadas:BAAANQAECgMIAwABNQAECgkJLwAWAA8gAA==.Mimikyu:BAAANQABCgYIBgAAAA==.Minìwheats:BAAANQADCgMIAwAAAA==.',
Mo='Moardotsnow:BAABNQAECn8tAAMZAAoKwSS1EwCpAQAaAAQKCiUwGACrAQAZAAcKlSS1EwCpAQAAAA==.Moby:BAAANQAECgQIBQAAAA==.Moistmender:BAAANQAECgcIDAAAAA==.Mortiana:BAAANQADCggICAAAAA==.',
Mu='Murriar:BAAANQAECggICQABNQAECgoKIAAmAGUbAA==.Murridan:BAABNQAECn8gAAImAAoKZRusBgDjAQAmAAoKZRusBgDjAQAAAA==.',
My='Mykaela:BAAANQAECgEIAQAAAA==.',
['Më']='Mëow:BAAANQAECgMIBAAAAA==.',
Na='Namiyu:BAAANQADCgcIBwAAAA==.Narrath:BAAANQADCgMJAwAAAA==.Nayalaah:BAAANQAECgEIAQAAAA==.',
Ne='Nehpets:BAAANQADCgUIBQAAAA==.Nephelym:BAABNQAECn8gAAMFAAgKQA9ZcwDCAQAFAAgKQA9ZcwDCAQAGAAIKrAKOJABHAAAAAA==.Nerv:BAAANQADCgMIBQAAAA==.',
Ni='Nicolasmage:BAAANQABCgMIAwAAAA==.Nirina:BAABNQAECn8VAAIKAAUK9AZQjgCQAAAKAAUK9AZQjgCQAAAAAA==.',
No='Nohtil:BAAANQADCgUIFQAAAA==.Notstephen:BAABNQAECn8eAAMFAAoKYwi3dQC7AQAFAAoKYwi3dQC7AQAbAAQKCxAbIQCDAAAAAA==.Nourishnutz:BAAANQADCgYIBgAAAA==.',
Nu='Nukefury:BAAANQAFFAEIAQABNQAFFAIIBwANAH0GAA==.Nut:BAABNQAECn8UAAIaAAUKoBIjJwA+AQAaAAUKoBIjJwA+AQABNQAECggIHwANAOYPAA==.',
Nw='Nwalliance:BAAANQAECgEIAQAAAA==.',
['Nö']='Nötprepared:BAAANQAECgUIBAABNQAECgUICQAEAAAAAA==.',
Oi='Oiflar:BAABNQAECn8UAAIfAAgKNhmTIQDBAQAfAAgKNhmTIQDBAQABNQAECgoKMAAfAKkfAA==.',
Ol='Olangi:BAAANQAECgEIAQAAAA==.',
Om='Omnidh:BAAANQADCggIEAABNQAFFAQICwASAKEfAA==.Omnipotent:BAAANQAECgUIBQAAAA==.',
On='Onepavo:BAABNQAECn8ZAAIhAAcKLRODIQDAAQAhAAcKLRODIQDAAQAAAA==.',
Oo='Oogie:BAAANQADCgYIBgAAAA==.Oogrikusk:BAAANQADCgIIAgAAAA==.Oottedenttoo:BAAANQADCgQIBAAAAA==.',
Op='Oppose:BAAANQAECgcICwAAAA==.',
Or='Orexion:BAABNQAECn8jAAIkAAgKGwtAEgCAAQAkAAgKGwtAEgCAAQAAAA==.Ormagöden:BAABNQAECn8jAAIYAAgKJA6QQwC1AQAYAAgKJA6QQwC1AQAAAA==.',
Ov='Overpower:BAAANQADCgYIBgAAAA==.',
Pa='Pagoda:BAAANQAECgUIDgAAAA==.Palladean:BAAANQAECgIIAwAAAA==.Palphen:BAAANQAECgcJDAABNQAECgoKHgAFAGMIAA==.Panako:BAAANQAECgUICQAAAA==.Pastasauce:BAABNQAECn8dAAIDAAYK3wnl/QAjAQADAAYK3wnl/QAjAQAAAA==.',
Pe='Pegero:BAAANQADCgYIDQAAAA==.Penelohpe:BAABNQAECn8iAAICAAkKyBt4fQCDAgACAAkKyBt4fQCDAgAAAA==.',
Ph='Phatt:BAAANQAECgMIAwAAAA==.Phoenixdrac:BAAANQADCggICQAAAA==.Phoon:BAECNQAFFH8NAAMZAAQKzxvGCADhAAAZAAQKzxvGCADhAAAaAAEKKRG4HgBLAAA1AAQKfy0ABBkACgpHIlM8AJ4CABkACArlIVM8AJ4CABoABAqiIXAkAE8BAB4AAQpJDlUSAEAAAAAA.Phoondk:BAEANQAECgUICAABNQAFFAQIDQAZAM8bAA==.',
Pi='Piggy:BAAANQAECgMIBwAAAA==.Pita:BAAANQABCgYIBgAAAA==.Pizzadriver:BAACNQAFFH8fAAMQAAgKPR4XBACZAgAQAAgKPR4XBACZAgAkAAEKAADIBQBLAAA1AAQKfykAAxAACgpJJTUaAE8DABAACgpBJTUaAE8DACQAAQo9JuEnAG4AAAAA.',
Pl='Plaguefist:BAAANQADCgcIBwABNQADCggIEgAEAAAAAA==.Plata:BAAANQAECgUIDAAAAA==.',
Po='Poosicat:BAAANQABCgYIBgAAAA==.Poosycat:BAAANQADCgMIAQAAAA==.',
Pr='Praytroxx:BAAANQAECgQIDAABNQAFFAYIEQASACMZAA==.Premonitions:BAAANQAECgYIBgAAAA==.Premune:BAABNQAECn8wAAITAAoKBx6aLgCsAgATAAoKBx6aLgCsAgAAAA==.Prion:BAABNQAECn8XAAQmAAoKExRSMAAlAgAmAAoKZhJSMAAlAgAJAAEKlRTlaABAAAAIAAEKOgt4NAAqAAAAAA==.',
Pu='Pucco:BAAANQADCgIIAgAAAA==.Putrav:BAAANQAECgYICAAAAA==.',
Py='Pyrena:BAAANQADCgEIAQAAAA==.Pyroclasm:BAAANQAECgUICgAAAA==.Pyrrha:BAAANQADCgMIAwAAAA==.',
Qu='Quigly:BAAANQADCgIIAgAAAA==.',
Ra='Ragingfluids:BAABNQAECn8iAAMkAAkKRBFSEgB+AQAQAAkKMhDBfgAeAgAkAAYKnBRSEgB+AQAAAA==.Rahdek:BAAANQADCgMIAwAAAA==.Raine:BAACNQAFFH8fAAIOAAgKhhcyBAA/AgAOAAgKhhcyBAA/AgA1AAQKfyMAAw4ACgqFFBpSAB4CAA4ACgqFFBpSAB4CAAcABApeFqzYAOMAAAAA.Raistlin:BAAANQADCgEIAQAAAA==.Ralfio:BAABNQAECn8wAAMfAAoKqR/UAwDCAQAfAAoKqR/UAwDCAQAnAAEKAACVJAAzAAAAAA==.Rasq:BAABNQAECn8VAAMXAAkK9QUqLAA3AQAXAAkK9QUqLAA3AQABAAEKAACnzAAUAAAAAA==.Rat:BAABNQAECn8XAAIVAAkKNCGiCABOAwAVAAkKNCGiCABOAwAAAA==.Raudykill:BAAANQAECgQIAgAAAA==.Rayaray:BAAANQADCgYIBgAAAA==.Raynith:BAABNQAECn8vAAQWAAkKDyBWAwCoAQABAAcK3R5eLQByAgAWAAcKgiBWAwCoAQAXAAIK4hFKTgBrAAAAAA==.Rayraye:BAAANQADCgIIAgAAAA==.',
Rd='Rdyoshy:BAAANQADCgUIBQAAAA==.',
Re='Readycheck:BAABNQAECn8qAAMBAAoKpBAuFgAsAQABAAoKCRAuFgAsAQAXAAcKyQg3MAAaAQAAAA==.Reflex:BAAANQAECgIIAgAAAA==.Regirock:BAAANQABCgMIBAAAAA==.Rellek:BAAANQAECgIIAgAAAA==.Remulous:BAAANQAECgYIDgAAAA==.Resist:BAAANQADCgYIBgAAAA==.Retallica:BAABNQAECn8UAAIDAAcKqwl46gBHAQADAAcKqwl46gBHAQAAAA==.Revali:BAACNQAFFH8KAAILAAUKZw3BDQBhAQALAAUKZw3BDQBhAQA1AAQKfzcAAwoACgorHssxANcCAAoACQoBHssxANcCAAsACgrEGUkYAJUCAAAA.Revelaen:BAAANQAECgcIDwABNQAFFAUICgALAGcNAA==.',
Ri='Rick:BAACNQAFFH8KAAILAAMKwxx8FAD5AAALAAMKwxx8FAD5AAA1AAQKfx8AAwsACgo6InkTAMUCAAsACgr9IXkTAMUCAAoABApOIHIDAf4AAAAA.',
Rm='Rmagep:BAAANQAECgUICwAAAA==.',
Ro='Roadhouse:BAAANQAECgQIBwAAAA==.Roman:BAAANQAECgYIDAABNQAECgkJPAAfAF4kAA==.Roshango:BAAANQADCgYIBgAAAA==.Rosinator:BAAANQAECggIAQAAAA==.Rotgus:BAAANQAECgEIAQAAAA==.Rouk:BAABNQAECn8UAAIQAAcKux6pCgATAgAQAAcKux6pCgATAgABNQAECgoKHAADAIQmAA==.Rowgar:BAABNQAECn8ZAAINAAkKmxmNLgBaAgANAAkKmxmNLgBaAgAAAA==.',
Ru='Rubenslik:BAABNQAECn8vAAICAAoKsCAQLAA3AwACAAoKsCAQLAA3AwAAAA==.',
Sa='Saelyn:BAAANQADCggIBgAAAA==.Saephora:BAAANQAECgYIEAAAAA==.Saggypants:BAABNQAECn8bAAIBAAoK5BK+LwBjAgABAAoK5BK+LwBjAgAAAA==.Sakurai:BAAANQAECgEIAQABNQAECgEIAgAEAAAAAA==.Salamander:BAAANQAECgUJCgAAAA==.Salazzle:BAAANQADCgQIBAAAAA==.Sammel:BAAANQAECgUIEAAAAA==.Sanari:BAAANQADCgUIBwABNQAECgkJHgAHAIgXAA==.Sandilla:BAAANQADCggICAABNQAECgoKGQAHAEUiAA==.Sangwine:BAAANQADCgYIBgAAAA==.Sapphica:BAAANQAECgEIAQAAAA==.Sathreina:BAABNQAECn8qAAIDAAoKABSrLwBxAQADAAoKABSrLwBxAQAAAA==.',
Sc='Scaries:BAABNQAECn8gAAIRAAoK4RlTBwDIAgARAAoK4RlTBwDIAgAAAA==.Scariesdwarf:BAAANQADCgYICgAAAA==.Scootko:BAABNQAECn8cAAIDAAgKOSLsQQDPAgADAAgKOSLsQQDPAgAAAA==.Scuss:BAAANQADCggICAAAAA==.',
Se='Sefers:BAAANQADCgEIAQAAAA==.Sego:BAAANQAECgIIAQAAAA==.Sekimaru:BAAANQAECgEIAgAAAA==.Senli:BAAANQAECgEIAQAAAA==.Severson:BAABNQAECn8bAAILAAgKXAxfNACrAQALAAgKXAxfNACrAQAAAA==.Sey:BAAANQADCgYIBgAAAA==.',
Sh='Shadowapoke:BAAANQADCgUIBQABNQAECgEIAQAEAAAAAA==.Shadowisbad:BAABNQAECn8oAAIbAAoKWBhYHABiAgAbAAoKWBhYHABiAgAAAA==.Shadvoker:BAABNQAECn8iAAMfAAgKzx2iDgC/AgAfAAgKzx2iDgC/AgAPAAIK1BHUMwBvAAAAAA==.Shamaneggs:BAABNQAECn8cAAMOAAkKiRkAFgClAQAOAAkKiRkAFgClAQAoAAMKshBOKQDRAAAAAA==.Shamatroxx:BAABNQAECn8bAAIoAAcK9R0cEQBXAgAoAAcK9R0cEQBXAgABNQAFFAYIEQASACMZAA==.Shamberry:BAAANQAECggIEgAAAA==.Shambles:BAAANQADCgYICQAAAA==.Shieldwalle:BAABNQAECn8XAAIdAAkK8x0KCwCMAgAdAAkK8x0KCwCMAgAAAA==.Shinobukocho:BAAANQADCgQJBAAAAA==.Shotigolova:BAAANQADCgcIDgAAAA==.',
Si='Sidesalad:BAAANQAECgQIBQAAAA==.Sidric:BAABNQAECn8tAAIBAAkKJA0rDACBAQABAAkKJA0rDACBAQAAAA==.Siena:BAAANQADCgYIBgAAAA==.Silre:BAAANQAECgUICwAAAA==.Sim:BAABNQAECn8kAAIQAAkKLiSvFQBjAwAQAAkKLiSvFQBjAwABNQAECgoKGQAHAEUiAA==.Singularité:BAAANQAECggIEgABNQAFFAcICwAVACAPAA==.Sipplex:BAAANQAECgEIAQAAAA==.',
Sl='Slander:BAAANQAECgQJBAABNQAECgUJCgAEAAAAAA==.Slanderous:BAAANQADCgEJAQABNQAECgUJCgAEAAAAAA==.Slappee:BAAANQAECgUIBgAAAA==.',
Sn='Snuudle:BAAANQAECgcIDwABNQAECgkJHAAZABwXAA==.',
So='Solokills:BAAANQADCgMIAwABNQADCgYIDQAEAAAAAA==.Sophia:BAAANQAECgcIEgAAAA==.Soundtrack:BAAANQADCgYICQABNQAECgIIAgAEAAAAAA==.Soyshine:BAAANQADCgYIBgAAAA==.',
Sp='Spaceman:BAACNQAFFH8HAAISAAQKXgLYBgCIAAASAAQKXgLYBgCIAAA1AAQKfxQAAhIACgqdDi4pANUBABIACgqdDi4pANUBAAAA.',
Sq='Squab:BAABNQAECn8cAAIBAAkKaR6+GQD6AgABAAkKaR6+GQD6AgAAAA==.Squanchy:BAAANQADCgYJCAAAAA==.',
St='Stabbywixx:BAAANQAECgIIAgAAAA==.Starwnd:BAABNQAECn8UAAIZAAcKlheaggDfAQAZAAcKlheaggDfAQABNQAFFAUIDAAnANgQAA==.Sterìs:BAAANQAECgEIAQAAAA==.Stillcreepin:BAAANQAECgEIAQAAAA==.Storienn:BAAANQAECgYIEQAAAA==.Stormzpaly:BAAANQAECgYIEQAAAA==.',
Su='Suküna:BAAANQADCggIFwAAAA==.Sunbur:BAAANQADCgYICgAAAA==.Sunglo:BAAANQAECgUIBwAAAA==.Surch:BAAANQADCgEIAQAAAA==.',
Sw='Swaption:BAABNQAECn8kAAIOAAkKTyOMAgASAwAOAAkKTyOMAgASAwAAAA==.Sweetie:BAAANQADCgEIAQAAAA==.',
Sy='Syrelia:BAABNQAECn80AAICAAoKTRT/hwBuAgACAAoKTRT/hwBuAgAAAA==.',
['Só']='Sónny:BAAANQABCgIIAgAAAA==.',
Ta='Tablescraps:BAAANQABCggICAABNQADCgIIAgAEAAAAAA==.Tassarosea:BAAANQAECgcIBwABNQAFFAMICAAPAK0dAA==.Tauloe:BAAANQAECgUICgAAAA==.Tayna:BAAANQAECgUIEAAAAA==.',
Te='Tenderoni:BAAANQADCgEIAQAAAA==.',
Th='Thatsmyhorse:BAAANQADCgIIAgAAAA==.Thatsograven:BAAANQADCgQIBAABNQAFFAgIIAABAOAfAA==.Thomosaurus:BAAANQADCggIDAAAAA==.Thraly:BAAANQADCgYIBwAAAA==.Thunk:BAABNQAECn8ZAAIHAAoKRSLACwCJAwAHAAoKRSLACwCJAwAAAA==.',
Ti='Timdawg:BAAANQAECggIEAABNQAFFAgIHwAZAEEZAA==.Timmolate:BAACNQAFFH8fAAQZAAgKQRn9BgD6AQAZAAYKoRr9BgD6AQAaAAIKwRfpCgCjAAAeAAIKRAkiBABaAAA1AAQKfykAAxoACgpVIwULAEcCABkACAryHRxYAE4CABoACAoMGQULAEcCAAAA.Tiramisubear:BAAANQAECggICQAAAA==.Tircaps:BAAANQADCgUIBQAAAA==.',
To='Tomcruise:BAAANQAECgIIAgAAAA==.Tomotostein:BAACNQAFFH8HAAIDAAQKVQTcCgC5AAADAAQKVQTcCgC5AAA1AAQKfyUAAgMACgqiFUhsAFkCAAMACgqiFUhsAFkCAAAA.Tornado:BAAANQABCgQICQABNQADCgQIBAAEAAAAAA==.',
Tr='Trilla:BAAANQAECgQIBAAAAA==.Tristîtia:BAABNQAECn8ZAAMbAAkK/A4nJAAQAgAbAAkK/A4nJAAQAgAFAAIKCwki5gB1AAAAAA==.Trulu:BAAANQADCgQIBQAAAA==.',
Ts='Tsukikyo:BAAANQADCgQIBAAAAA==.Tsuma:BAAANQABCgIIAgAAAA==.Tsume:BAAANQAECgQIDAAAAA==.',
Tt='Ttomas:BAAANQAECggIEQAAAA==.',
Ty='Tyrinn:BAAANQAECggIEgAAAA==.Tyv:BAABNQAECn8xAAICAAkKkQ8KEgDXAQACAAkKkQ8KEgDXAQAAAA==.',
Up='Updatè:BAAANQAECgEIAQABNQAECggIDwAEAAAAAA==.',
Ur='Urgent:BAAANQADCgEIAQAAAA==.',
Uz='Uzì:BAAANQADCgIIAgAAAA==.',
Va='Vainatetosix:BAAANQAECgUICQAAAA==.Vallodon:BAABNQAECn8kAAICAAkKHCISTgDlAgACAAkKHCISTgDlAgAAAA==.Vantablack:BAAANQABCgIIAgABNQADCgQIBAAEAAAAAA==.Vanwolfy:BAABNQAECn8XAAIdAAoKExE9FQDUAQAdAAoKExE9FQDUAQAAAA==.Vaylorian:BAAANQAECgUICwAAAA==.',
Ve='Velectran:BAAANQADCgUICgABNQAECgoKNAACAE0UAA==.Velorian:BAAANQADCgMIAwAAAA==.Velveeta:BAAANQAECgMIAwAAAA==.Veragon:BAAANQADCgcIBwAAAA==.',
Vf='Vfacer:BAAANQADCgEIAQAAAA==.',
Vi='Vikav:BAAANQAECgIIAgAAAA==.Vikimg:BAABNQAECn8YAAIFAAoKuRV0LQBHAQAFAAoKuRV0LQBHAQAAAA==.Violet:BAAANQADCgEIAQAAAA==.',
Vo='Voodoomike:BAAANQAECgQIBAAAAA==.Vortash:BAAANQADCgUIBwAAAA==.',
Vy='Vynle:BAAANQAECgEIAQAAAA==.',
Wa='Warheimer:BAABNQAECn8YAAMUAAkKBQ+LXwCRAQAUAAkKBQ+LXwCRAQANAAQKVgZpoQCUAAAAAA==.Warrgodx:BAABNQAECn9LAAMQAAoKuSD0AwCvAgAQAAoKuSD0AwCvAgAkAAEKygioMwA0AAABNQAECgoKTgADALclAA==.',
Wh='Whoknows:BAAANQADCgIIAgAAAA==.',
Wo='Woogi:BAAANQADCgUIBQAAAA==.',
Wr='Wrongwookie:BAABNQAECn8oAAIHAAoKUxcpRwBaAgAHAAoKUxcpRwBaAgAAAA==.',
Ya='Yapper:BAAANQADCgMIAwAAAA==.',
Yo='Yolanda:BAAANQAECgIIAgAAAA==.Yoyohunty:BAAANQAECgcIBwAAAA==.',
Yt='Ytix:BAAANQAECgEIAQAAAA==.',
Yu='Yumekoo:BAAANQADCgIIAgAAAA==.',
Za='Zabada:BAAANQAECgUIBQAAAA==.Zaldrea:BAAANQAECgMIAwABNQAFFAUICwAbAIUOAA==.Zandrea:BAAANQAECgYIDwABNQAFFAUICwAbAIUOAA==.Zariee:BAAANQABCgIIAwAAAA==.',
Ze='Zehz:BAABNQAECn8aAAIYAAkKZAFhkgByAAAYAAkKZAFhkgByAAAAAA==.Zemsen:BAABNQAECn8nAAICAAkKoh3yawCmAgACAAkKoh3yawCmAgAAAA==.Zentrea:BAAANQAECgQIBAABNQAFFAUICwAbAIUOAA==.Zenyea:BAABNQAECn8WAAIOAAgKpQrCiwBsAQAOAAgKpQrCiwBsAQABNQAFFAUICwAbAIUOAA==.Zetta:BAACNQAFFH8LAAIbAAUKhQ4wCQB0AQAbAAUKhQ4wCQB0AQA1AAQKfyYAAhsACgq9F8kWAKQCABsACgq9F8kWAKQCAAAA.',
Zo='Zome:BAABNQAECn80AAMhAAoKjxZ5AwAjAgAhAAoKjxZ5AwAjAgAVAAEKlAM4pgAwAAAAAA==.Zorojoro:BAAANQAECgUIBQAAAA==.',
Zy='Zyndrael:BAABNQAECn8hAAIDAAoKbB3kLAAUAwADAAoKbB3kLAAUAwAAAA==.',
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
