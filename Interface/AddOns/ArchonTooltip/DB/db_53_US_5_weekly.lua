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

local lookup = {'Druid-Balance','Mage-Arcane','Paladin-Retribution','Unknown-Unknown','Priest-Holy','Priest-Shadow','Priest-Discipline','Shaman-Elemental','DemonHunter-Vengeance','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','DeathKnight-Blood','Shaman-Restoration','Evoker-Devastation','Warrior-Arms','Monk-Brewmaster','Monk-Windwalker','Paladin-Holy','DeathKnight-Unholy','Rogue-Assassination','Druid-Feral','Druid-Guardian','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','Rogue-Outlaw','Shaman-Enhancement','Warrior-Protection','Warlock-Affliction','Evoker-Preservation','Monk-Mistweaver','Rogue-Subtlety','Mage-Frost','Hunter-Survival','Warrior-Fury','Druid-Restoration','DemonHunter-Havoc','Evoker-Augmentation',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Accost:BAAANQADCgcIDQAAAA==.Achendron:BAAANQADCgUIBQABNQAFFAgIIAABAOAfAA==.Acronica:BAAANQAECgUIEgAAAA==.',
Ad='Addilynn:BAAANQABCgEIAQAAAA==.',
Ak='Akassa:BAAANQADCgcICwAAAA==.Aknologia:BAAANQAECgUICwABNQAECgoKGwACAPcOAA==.',
Al='Alecto:BAABNQAECn8gAAIDAAkKnQbZ6QBIAQADAAkKnQbZ6QBIAQAAAA==.Allele:BAAANQAECgMIAwAAAA==.Allet:BAAANQADCggIFwABNQAECgYIDQAEAAAAAA==.',
Am='Amarah:BAABNQAECn82AAMFAAoK4h4bKgDBAgAFAAoK4h4bKgDBAgAGAAEKAABEVgAAAAAAAA==.Amazome:BAAANQAECgYIBwAAAA==.Ameilie:BAABNQAECn9FAAMHAAoKPyDMAQBSAgAFAAoK4x/GHQD6AgAHAAkKmxjMAQBSAgAAAA==.',
An='Anapuwae:BAABNQAECn8UAAIIAAYKSA0CqwA+AQAIAAYKSA0CqwA+AQAAAA==.Animehero:BAABNQAECn8qAAMJAAoKVR2gBQDRAgAJAAgKHCCgBQDRAgAKAAYKsRdAEgDHAQAAAA==.',
Ar='Arcant:BAABNQAECn8oAAICAAkK/hm1WACiAQACAAkK/hm1WACiAQAAAA==.Ardicov:BAAANQADCgYICwAAAA==.Argadin:BAAANQAECgcICAABNQAECgoKLwALAG0iAA==.Arglock:BAAANQAECgQIAgABNQAECgoKLwALAG0iAA==.Argrekh:BAABNQAECn8vAAMLAAoKbSLQCgCHAwALAAoKbSLQCgCHAwAMAAEKQQ/phgA3AAAAAA==.Argreks:BAAANQADCgEIAgABNQAECgoKLwALAG0iAA==.Argrekt:BAAANQAECgIIAgABNQAECgoKLwALAG0iAA==.Aridol:BAAANQADCgYIBgAAAA==.Arigön:BAAANQADCgYICAAAAA==.Aronna:BAAANQADCgYICAAAAA==.Arosea:BAAANQADCgYIBgAAAA==.Arthaslk:BAACNQAFFH8FAAIDAAQKUxksIwCTAAADAAQKUxksIwCTAAA1AAQKf1AAAwMACgrmJekCAOYDAAMACgrmJekCAOYDAA0AAgoECUliAFQAAAAA.Aryssol:BAAANQAECgIIAgAAAA==.',
At='Ate:BAABNQAECn8hAAIOAAgKfBCLLAA/AQAOAAgKfBCLLAA/AQAAAA==.Atlette:BAAANQAECgMIAwAAAA==.Attman:BAACNQAFFH8MAAIPAAUK3BNUCQBYAQAPAAUK3BNUCQBYAQA1AAQKf0kAAw8ACgpKI8wIADYDAA8ACgpKI8wIADYDAAgAAwrLEp9yALwAAAAA.',
Au='Auradawn:BAAANQADCgcIDwAAAA==.',
Ba='Backwater:BAAANQADCggIDwABNQAECgYIDQAEAAAAAA==.Badhands:BAAANQAECgIIAgAAAA==.Baeator:BAAANQAECgEIAQABNQAFFAcIGAAQAO0PAA==.Barneystins:BAAANQABCgEIAgABNQADCgQIBAAEAAAAAA==.',
Be='Bearmane:BAACNQAFFH8GAAIBAAMKOB2gDwCqAAABAAMKOB2gDwCqAAA1AAQKfzAAAgEACgp9Ip8OAFUDAAEACgp9Ip8OAFUDAAAA.Beastarsfan:BAABNQAECn8oAAIIAAoKnyOPCwCLAwAIAAoKnyOPCwCLAwAAAA==.Behmow:BAABNQAECn9AAAIRAAoKsSaXAQB8AwARAAoKsSaXAQB8AwAAAA==.Belithel:BAAANQAECgQIBgABNQAECgkJIwAIABgZAA==.Bencreepin:BAAANQAECgUIEgAAAA==.Bernoulli:BAABNQAECn8uAAMSAAoKoxYJBAAVAgASAAoKoxYJBAAVAgATAAEKAABuVgAAAAAAAA==.',
Bi='Bigspitter:BAAANQADCgYIBgABNQAECgoKNQACAHAlAA==.Bis:BAAANQADCgUJBQABNQAECgkJFgACAD0cAA==.',
Bl='Blessedxx:BAAANQAECgUIBgAAAA==.Bloodboo:BAAANQADCgQIBAAAAA==.Bloodyhpally:BAACNQAFFH8dAAIUAAgK1xdDAwBoAgAUAAgK1xdDAwBoAgA1AAQKfy0AAxQACgpvHoUWAJACABQACgpvHoUWAJACAAMAAgoXD4lmAXsAAAAA.',
Bo='Boopsnoopems:BAABNQAECn8WAAINAAYKzw8hLwCcAAANAAYKzw8hLwCcAAAAAA==.Borderline:BAAANQAECgUIBQABNQAFFAQICQATAL4EAA==.',
Br='Bradcrit:BAAANQAECgEIAQAAAA==.',
Bu='Bubble:BAABNQAECn8VAAMUAAcKEAfJuQAJAQAUAAYKIAfJuQAJAQADAAUKgggXJAHjAAAAAA==.Bulldoser:BAAANQADCgQIBAAAAA==.Burrfoot:BAAANQAECgIIAwAAAA==.Bustah:BAAANQAECgcIEgABNQAECggIFwAVAMQbAA==.',
Bw='Bwoodmorgan:BAAANQAECgYIDgAAAA==.',
By='Byron:BAAANQAECgQIBgAAAA==.',
Ca='Calene:BAACNQAFFH8LAAIWAAcKIA8kBQDkAQAWAAcKIA8kBQDkAQA1AAQKf0kAAhYACgrpI0cEAJcCABYACgrpI0cEAJcCAAAA.Candy:BAAANQAECgMIBQAAAA==.Cannedcorn:BAAANQAECgIIAgAAAA==.Caperusin:BAAANQAECgUICAAAAA==.Casare:BAAANQADCgYIFgAAAA==.Cayde:BAAANQADCgYJBgABNQAFFAUICgAMAGcNAA==.',
Ce='Celestinee:BAAANQAECgYIEwAAAA==.Celyda:BAAANQAECgUICAAAAA==.Cenarian:BAAANQABCgUIBwAAAA==.',
Ch='Chabotloe:BAAANQAECgMIBQAAAA==.Chape:BAABNQAECn8dAAMUAAkKvhcQPgBsAgAUAAkKvhcQPgBsAgADAAYK/BBE7wA+AQAAAA==.Chence:BAAANQADCgYIBgAAAA==.Chochalinda:BAABNQAECn8dAAMXAAgKvxFUEQAZAQAYAAUK8xTfLQArAQAXAAcKXBBUEQAZAQAAAA==.',
Ci='Cinderlee:BAAANQAECgUIDgAAAA==.',
Co='Colexn:BAABNQAECn8kAAQZAAkKmxbOLAB4AQAZAAkKmxbOLAB4AQAVAAIKMhDJwQBnAAAOAAEKAAAInAAAAAAAAA==.Cong:BAACNQAFFH8FAAIRAAQK3ghxIAD/AAARAAQK3ghxIAD/AAA1AAQKfycAAhEACgqnG/MnABoDABEACgqnG/MnABoDAAAA.Corg:BAAANQADCgYIBgAAAA==.Cornchipz:BAABNQAECn8bAAICAAoK9w5e0ADlAQACAAoK9w5e0ADlAQAAAA==.',
Cr='Crapsack:BAAANQABCgEIAQAAAA==.Croski:BAAANQADCgEIAQAAAA==.Cryonidus:BAAANQAECgEIAQAAAA==.',
Cu='Curves:BAAANQAECgEIAQAAAA==.',
Cy='Cypressa:BAAANQADCgQIBAAAAA==.',
Da='Daangalanng:BAABNQAECn8mAAIUAAoKyBbYKgABAgAUAAoKyBbYKgABAgAAAA==.Dabberoni:BAAANQAECgEIAgAAAA==.Daegra:BAABNQAECn8pAAIWAAoKXByaDwAEAwAWAAoKXByaDwAEAwAAAA==.Dankkush:BAAANQADCgQIBAAAAA==.Darkacedia:BAABNQAECn8vAAMaAAkKihXHTQBrAgAaAAkKihXHTQBrAgAbAAMKKwp9TwCRAAAAAA==.Darkzetta:BAAANQAECgIIAgABNQAFFAYIDAAGAKoLAA==.Datbish:BAAANQAECgIIAgAAAA==.',
De='Deadlift:BAABNQAECn8cAAIVAAkKlRiRFwDBAQAVAAkKlRiRFwDBAQAAAA==.Deadlyhoof:BAAANQAECgMIAwAAAA==.Dealosed:BAABNQAECn8ZAAMWAAgKphkIKwA+AgAWAAgKeRkIKwA+AgAcAAQKDhXyEQDsAAAAAA==.Deathawolf:BAAANQAECgEIAQAAAA==.Deathkilera:BAAANQADCgUIBwAAAA==.Defy:BAAANQADCgYIBgAAAA==.Delenn:BAABNQAECn8XAAIXAAgKZxrsDQA6AgAXAAgKZxrsDQA6AgAAAA==.Demonclawz:BAAANQAECgYIBgAAAA==.Demonnyaa:BAAANQADCgcIBwAAAA==.Derzy:BAAANQADCgIIAgAAAA==.Dewygirl:BAAANQADCgcICgAAAA==.',
Dh='Dhuumystic:BAAANQADCgEIAQAAAA==.',
Di='Disastapyre:BAAANQAECgIIAgABNQAECgkJGAAdAHwcAA==.Disastasmite:BAAANQADCgIIBAABNQAECgkJGAAdAHwcAA==.Dive:BAABNQAECn8WAAICAAkKPRyyYwC3AgACAAkKPRyyYwC3AgAAAA==.',
Do='Doogru:BAABNQAECn85AAIeAAkKgxu3CADFAQAeAAkKgxu3CADFAQAAAA==.Doogtwo:BAAANQADCggIHAABNQAECgkJOQAeAIMbAA==.Doryndoran:BAAANQAECgQIBQAAAA==.Dorynhashots:BAAANQADCgUIBQAAAA==.Dotproduct:BAAANQADCgEIAQABNQADCgIIAgAEAAAAAA==.Dotsrock:BAABNQAECn8oAAMfAAoK3BKnAgAcAgAfAAoK3BKnAgAcAgAaAAUKcQcauACBAAAAAA==.Dovah:BAAANQADCgIIAgAAAA==.',
Dr='Dragoneggs:BAABNQAECn8iAAMQAAoKBBkXDQCRAgAQAAoKBBkXDQCRAgAgAAkK9Ql2HwDdAQAAAA==.Dragonforce:BAAANQADCggIEgAAAA==.Drakonutz:BAAANQAECgYIDwAAAA==.Draxx:BAAANQAECggICgAAAA==.Drañzer:BAAANQAECgEIAgAAAA==.Dreammachine:BAAANQAECgcIBwAAAA==.Drjoel:BAAANQADCgcIEQAAAA==.Drunkenutz:BAABNQAECn8ZAAQTAAkK7g0rLwCxAAASAAUKLxCcIQDQAAATAAUKPgwrLwCxAAAhAAQKcA9WIAClAAAAAA==.Drâx:BAAANQAECggICAAAAA==.Dräx:BAAANQAECggIEgAAAA==.',
Dw='Dwallen:BAAANQADCgIIAgAAAA==.Dwightschrut:BAAANQADCgQIBAAAAA==.',
['Dä']='Dälf:BAAANQAECgIIAgABNQAFFAcICQANABsVAA==.',
Ea='Earthshocker:BAAANQAECgcIDgAAAA==.',
Ed='Edirii:BAAANQABCgIIAgAAAA==.',
El='Elenix:BAAANQAECgcIAQAAAA==.Elki:BAAANQADCgQIBgAAAA==.Elmesia:BAABNQAECn8UAAICAAcKTQjwGAFiAQACAAcKTQjwGAFiAQAAAA==.Eloris:BAABNQAECn8lAAIKAAgK7RxGHABzAgAKAAgK7RxGHABzAgAAAA==.Elpato:BAAANQADCgcIBwABNQAECgoKNQACAHAlAA==.Elthyn:BAAANQAECgYIDAAAAA==.Elvar:BAAANQAECgEIAQAAAA==.',
Em='Emachine:BAAANQADCggICAABNQAECgIIAgAEAAAAAA==.Emeraldrin:BAAANQADCgEIAQAAAA==.Emz:BAABNQAECn81AAIcAAkKFyDeAACMAgAcAAkKFyDeAACMAgAAAA==.',
En='Eniar:BAAANQAECgMIBgAAAA==.',
Er='Erakk:BAAANQADCgEIAgAAAA==.Erianda:BAAANQABCgQIBAAAAA==.Eric:BAABNQAECn8cAAIRAAcK5RyiegAoAgARAAcK5RyiegAoAgAAAA==.Eroninja:BAAANQAECgIIAwABNQAECgkJIwAIABgZAA==.Erín:BAABNQAECn8fAAIaAAYK5BCugAD0AAAaAAYK5BCugAD0AAAAAA==.',
Eu='Eurong:BAACNQAFFH8HAAIBAAQKsxE4FgAGAQABAAQKsxE4FgAGAQA1AAQKfy0AAgEACgpVIYsHAOECAAEACgpVIYsHAOECAAAA.',
Ez='Ezynuff:BAAANQAECgYIDAAAAA==.',
Fa='Faner:BAAANQADCgEIAgABNQAECgEIAQAEAAAAAA==.Fapple:BAAANQAECgUICQABNQAECgoKMwAgAFEgAA==.Fatesworn:BAAANQADCgcIBwAAAA==.Faïry:BAABNQAECn8xAAILAAoKbiJSEgC9AgALAAoKbiJSEgC9AgAAAA==.',
Fe='Feaughoeren:BAAANQAECggIEwAAAA==.Felwyrm:BAABNQAECn8nAAIaAAkKgRd4UABjAgAaAAkKgRd4UABjAgABNQAFFAQICQATAL4EAA==.Feralina:BAAANQABCgIIAgAAAA==.Feralshmeral:BAAANQABCgQIBAABNQAECgoKIAALAPEgAA==.',
Fo='Foxi:BAAANQADCggIEQABNQAECgcIEwAEAAAAAA==.',
Fr='Frank:BAAANQAECggIEAAAAA==.Freakbeast:BAAANQAECgYJEgABNQAECgoKIAAcAIwiAA==.Fries:BAEANQAECggICwABNQAECggIDwAEAAAAAA==.',
Fu='Fullkidney:BAACNQAFFH8KAAIWAAQKeB4fCgBfAQAWAAQKeB4fCgBfAQA1AAQKfyAAAhYACQrbIqAJAEIDABYACQrbIqAJAEIDAAAA.Funch:BAABNQAECn8mAAIfAAoKZxIhBQB4AgAfAAoKZxIhBQB4AgAAAA==.',
Ga='Gaefaeryn:BAACNQAFFH8KAAIGAAQKow54BwDhAAAGAAQKow54BwDhAAA1AAQKfyQAAwYACgr7FH0bAGwCAAYACgr7FH0bAGwCAAcAAQqaAQ0yAB8AAAAA.Gainzz:BAAANQAECgEIAQAAAA==.Garonnaa:BAABNQAECn8qAAIOAAoKPRcvFAAIAgAOAAoKPRcvFAAIAgAAAA==.Garthel:BAABNQAECn8rAAITAAoKjxNpIwALAgATAAoKjxNpIwALAgAAAA==.',
Ge='Genetiks:BAAANQADCgYIDAAAAA==.',
Gh='Ghari:BAABNQAECn8lAAIVAAcKlxD2NADuAAAVAAcKlxD2NADuAAAAAA==.',
Gi='Gingerlock:BAABNQAECn8tAAIaAAoKKhnuNwCsAgAaAAoKKhnuNwCsAgAAAA==.Gingershaman:BAAANQAECgUIBQAAAA==.Giyuu:BAAANQADCgUIBQAAAA==.',
Gn='Gnoblin:BAAANQADCggIFgAAAA==.',
Gr='Greka:BAABNQAECn8WAAIIAAUKJwtqbgDGAAAIAAUKJwtqbgDGAAAAAA==.Greylooms:BAAANQADCgcIBwAAAA==.Griplock:BAABNQAECn85AAMOAAoKAQ72WgCHAQAOAAgK7Az2WgCHAQAZAAIKQRFLawB9AAAAAA==.',
Gu='Gutz:BAAANQAECgMIAwAAAA==.',
['Gö']='Gözër:BAAANQADCgMIAwABNQAECgYIBgAEAAAAAA==.',
Ha='Happyfriend:BAAANQAECgEIAQABNQAFFAQICQATAL4EAA==.Haruko:BAAANQADCggICAAAAA==.',
He='Healalle:BAAANQADCgYICwABNQAECgkJFwAeAPMdAA==.Healhole:BAABNQAECn81AAMPAAoKZyFREwAwAwAPAAoKZyFREwAwAwAIAAMKbhFO7gC6AAAAAA==.Heimdall:BAAANQAECgEIAgAAAA==.Heàl:BAAANQAECggIDwAAAA==.',
Hi='Hidolo:BAAANQADCgYIDAAAAA==.',
Hr='Hruwa:BAAANQADCgMIAwABNQAECgEIAQAEAAAAAA==.',
Hu='Hunterishard:BAAANQAECgQIBAABNQAECgYIBwAEAAAAAA==.',
Hy='Hylaina:BAAANQADCgYJCgAAAA==.',
['Hô']='Hôlÿ:BAAANQADCggIDgAAAA==.',
Ia='Iamamonk:BAAANQADCgEIAQAAAA==.',
Ik='Ikerous:BAAANQADCgMIAwAAAA==.',
Il='Ilysa:BAAANQABCgQIBAAAAA==.',
Im='Imadwagon:BAAANQADCgcIAgAAAA==.Imcolorblind:BAAANQADCgIIAgAAAA==.Imhammered:BAAANQAECgYIDgAAAA==.',
Io='Ioun:BAAANQADCgMIAwAAAA==.Iounn:BAAANQADCgcIBwABNQAECgoKJgAhAJcVAA==.',
Is='Isatku:BAAANQAECgEIAQAAAA==.',
It='Itiswhatitiz:BAABNQAECn82AAILAAkKrhuNOQC9AgALAAkKrhuNOQC9AgAAAA==.Itsybityshiv:BAABNQAECn8zAAIiAAoKshgKDwCJAgAiAAoKshgKDwCJAgAAAA==.',
Ja='Jakarr:BAAANQADCgQIBAAAAA==.Jams:BAAANQAECgUIBQAAAA==.',
Je='Jeabuss:BAAANQADCgUIBQAAAA==.Jella:BAAANQADCgQIBAAAAA==.',
Jh='Jhani:BAABNQAECn8XAAIjAAcKsAZOHgD6AAAjAAcKsAZOHgD6AAAAAA==.',
Ji='Jiu:BAABNQAECn8cAAIFAAkKiBsVJgDTAgAFAAkKiBsVJgDTAgABNQAECggIFwAVAMQbAA==.',
Jo='Joethemage:BAABNQAECn80AAICAAoKSB02JgBdAgACAAoKSB02JgBdAgAAAA==.Jormojo:BAAANQAECgMIAwAAAA==.',
Ju='Jungol:BAAANQADCgUICQAAAA==.',
Ka='Kairupaws:BAAANQADCgYIBgAAAA==.Kallip:BAAANQADCggICAAAAA==.Kamin:BAAANQAECgYIBgABNQAECgkJIgACAMgbAA==.Katamaran:BAAANQAECgQIBAABNQAFFAYIDAAGAKoLAA==.Kaykaypally:BAABNQAECn8aAAIDAAgKuBCBvgCgAQADAAgKuBCBvgCgAQAAAA==.Kazbirt:BAAANQADCgIIAgAAAA==.',
Ke='Kellan:BAAANQADCggIFgAAAA==.',
Kh='Khybyr:BAAANQADCgMIAwAAAA==.',
Ki='Kidata:BAABNQAECn8mAAIhAAoKlxVCFgAYAgAhAAoKlxVCFgAYAgAAAA==.Kindaprepped:BAAANQADCgQIBAAAAA==.Kinji:BAABNQAECn8jAAIIAAkKGBnkSABTAgAIAAkKGBnkSABTAgAAAA==.Kinn:BAAANQADCggICAABNQAECgoKLgASAKMWAA==.',
Ko='Konfu:BAAANQAECgEIAQAAAA==.Kormega:BAAANQAECgUIBQAAAA==.Korral:BAAANQADCggIDQAAAA==.',
Kr='Krispies:BAAANQAECgUIDQAAAA==.Kristysavage:BAABNQAECn83AAMkAAoKSyE9AQBtAwAkAAoKbiA9AQBtAwALAAIK+RuXKwGZAAAAAA==.Krul:BAAANQAECgUIBQAAAA==.',
Ku='Kulaesca:BAACNQAFFH8RAAIaAAUKLhbaBgBAAQAaAAUKLhbaBgBAAQA1AAQKfysAAxoACgoOGaVHAHwCABoACgoOGaVHAHwCABsAAQrtAOWHAB0AAAAA.',
Ky='Kynar:BAACNQAFFH8dAAMZAAgKxx1rAgAmAgAZAAcKxx1rAgAmAgAOAAYKngfuEABIAQA1AAQKfy4AAxkACgpZJkQKAEkDABkACgpZJkQKAEkDAA4AAwqHE7qWALEAAAAA.Kyua:BAAANQAECgEIAQAAAA==.',
La='Ladragona:BAAANQADCggICAAAAA==.Lambshot:BAABNQAECn8jAAMMAAoKXRQfDQD/AQALAAgK1RIAdgAkAgAMAAoKlRMfDQD/AQAAAA==.Lambsy:BAACNQAFFH8hAAQRAAgKXhUZBwBPAgARAAgKXhUZBwBPAgAlAAEKAAAaBgBIAAAeAAEKAACwCQA9AAA1AAQKfzgAAxEACgofJbcQAHsDABEACgobJbcQAHsDACUAAwoCE/8hAKgAAAAA.Lanamama:BAAANQAECgEIAQABNQAECgIIAgAEAAAAAA==.Lanana:BAAANQADCgMIAwABNQAECgIIAgAEAAAAAA==.',
Le='Ledsole:BAAANQABCgIIAgAAAA==.Lerat:BAABNQAECn8yAAIQAAoKTR9lBwALAwAQAAoKTR9lBwALAwAAAA==.',
Li='Lightwarden:BAAANQADCgQIBAAAAA==.Lilyy:BAACNQAFFH8KAAMjAAMKexHEAQDlAAAjAAMKexHEAQDlAAACAAIKAAokTgCKAAA1AAQKfy4AAyMACgqqHYgGAJcCACMACApFH4gGAJcCAAIACQp8F4JzAJcCAAAA.Lisanalgaib:BAABNQAECn8iAAIDAAgKPBX1lgD2AQADAAgKPBX1lgD2AQAAAA==.Lizzimcguire:BAACNQAFFH8MAAIQAAQKESEjAQAfAQAQAAQKESEjAQAfAQA1AAQKfzYAAhAACgo9JXgBALYDABAACgo9JXgBALYDAAAA.',
Lo='Lobobare:BAABNQAECn8fAAImAAgK2x0hHABVAgAmAAgK2x0hHABVAgAAAA==.Loraen:BAABNQAECn8YAAICAAYKlATNtQDcAAACAAYKlATNtQDcAAAAAA==.Lostep:BAAANQAECgEIAQABNQAFFAgIHwAPAIYXAA==.',
Lu='Lunarmon:BAAANQADCgUIBQAAAA==.Lunchable:BAABNQAECn8gAAMPAAgKmh8CNQDKAQAPAAcK/B4CNQDKAQAIAAYKzBV7gACjAQAAAA==.',
Ma='Maevora:BAABNQAECn8ZAAIGAAcKawSBTQDeAAAGAAcKawSBTQDeAAAAAA==.Makaroni:BAAANQAECgUIBQAAAA==.Manticus:BAAANQADCgYICAAAAA==.Maomaoo:BAABNQAECn8XAAMOAAgKQhLadQAgAQAOAAcKahTadQAgAQAVAAUKtwcJlADbAAAAAA==.Marni:BAAANQAECgYIEwABNQAECgoKJgADAKshAA==.Marsrover:BAAANQAECgIIAgABNQAFFAgIIAARAD0eAA==.Martel:BAAANQADCgQIBAAAAA==.Matroxx:BAACNQAFFH8SAAITAAcKNRcSBwCLAQATAAcKNRcSBwCLAQA1AAQKfzsAAhMACgp0JAgEAAYDABMACgp0JAgEAAYDAAAA.',
Me='Medinduceyuh:BAAANQADCgEIAQAAAA==.Meenoi:BAABNQAECn8XAAIVAAgKxBtHRQAEAgAVAAgKxBtHRQAEAgAAAA==.Mellotots:BAAANQABCgIIBAAAAA==.Metatron:BAAANQADCgIIAgAAAA==.',
Mi='Miadas:BAAANQAECgMIAwABNQAECgkJOQAXAA8gAA==.Mimikyu:BAAANQABCgYIBgAAAA==.Minìwheats:BAAANQADCgMIAwAAAA==.',
Mo='Moardotsnow:BAABNQAECn8xAAQbAAoKaCUwGACrAQAaAAcKoCXsPQCxAQAbAAQKCiUwGACrAQAfAAEKxB5SFQBaAAAAAA==.Moby:BAAANQAECgcIDAAAAA==.Moistmender:BAAANQAECgYIDQAAAA==.Mortiana:BAAANQADCggICAAAAA==.',
Mu='Murriar:BAAANQAECggICQABNQAECgoKKgAnAAMhAA==.Murridan:BAABNQAECn8qAAInAAoKAyH/BgDqAgAnAAoKAyH/BgDqAgAAAA==.',
My='Mykaela:BAAANQAECgEIAQAAAA==.',
['Më']='Mëow:BAAANQAECgQICAAAAA==.',
Na='Naausi:BAAANQADCgMIAwAAAA==.Namiyu:BAAANQADCgcIBwAAAA==.Narrath:BAAANQADCgMJAwAAAA==.Nayalaah:BAAANQAECgEIAQAAAA==.',
Ne='Nehpets:BAAANQADCgUIBQAAAA==.Nektzalla:BAABNQAECn8ZAAIPAAkK5RdDMgDXAQAPAAkK5RdDMgDXAQAAAA==.Nephelym:BAABNQAECn8gAAMFAAgKQA9ZcwDCAQAFAAgKQA9ZcwDCAQAHAAIKrAKOJABHAAAAAA==.Nerv:BAAANQADCgMIBQAAAA==.',
Ni='Nicolasmage:BAAANQABCgQIBQAAAA==.Nirina:BAABNQAECn8WAAILAAYKSwhrtQDEAAALAAYKSwhrtQDEAAAAAA==.',
No='Nohtil:BAAANQADCgYIGwAAAA==.Notstephen:BAABNQAECn8iAAMFAAoKFQq3dQC7AQAFAAoKFQq3dQC7AQAGAAQKCxCPNAB8AAAAAA==.Nourishnutz:BAAANQADCgYIBgAAAA==.',
Nu='Nukefury:BAABNQAECn8YAAIdAAkKfBwPBQCZAgAdAAkKfBwPBQCZAgAAAA==.Nut:BAABNQAECn8UAAIbAAUKoBIjJwA+AQAbAAUKoBIjJwA+AQABNQAECggIIQAOAHwQAA==.',
Nw='Nwalliance:BAAANQAECgEIAQAAAA==.',
['Nö']='Nötprepared:BAAANQAECgUIBAABNQAECgUICQAEAAAAAA==.',
Oi='Oiflar:BAABNQAECn8eAAIgAAoKTBbRCgDxAQAgAAoKTBbRCgDxAQABNQAECgoKMwAgAFEgAA==.',
Ol='Olangi:BAAANQAECgEIAQAAAA==.',
Om='Omnidh:BAAANQADCggIEAABNQAFFAUIDQATAKEfAA==.Omnipotent:BAAANQAECgUIBQAAAA==.',
On='Onepavo:BAABNQAECn8gAAIiAAcKbRSDIQDAAQAiAAcKbRSDIQDAAQAAAA==.',
Oo='Oogie:BAAANQADCgYIBgAAAA==.Oogrikusk:BAAANQADCgIIAgAAAA==.Oottedenttoo:BAAANQADCgQIBAAAAA==.',
Op='Oppose:BAAANQAECgYICwAAAA==.',
Or='Orexion:BAABNQAECn8jAAIlAAgKGwtAEgCAAQAlAAgKGwtAEgCAAQAAAA==.Oriavis:BAAANQADCgYIBgAAAA==.Ormagöden:BAABNQAECn8pAAIZAAoKMw2QQwC1AQAZAAoKMw2QQwC1AQAAAA==.',
Ov='Overpower:BAAANQADCgYIBgAAAA==.',
Pa='Pagoda:BAAANQAECgYIEgAAAA==.Palladean:BAAANQAECgIIAwAAAA==.Palphen:BAAANQAECgcJDAABNQAECgoKIgAFABUKAA==.Panako:BAAANQAECgUICQAAAA==.Pastasauce:BAABNQAECn8dAAIDAAYK3wnl/QAjAQADAAYK3wnl/QAjAQAAAA==.',
Pe='Pegero:BAAANQADCgYIDQABNQAFFAMIBQALAFgXAA==.Penelohpe:BAABNQAECn8iAAICAAkKyBt4fQCDAgACAAkKyBt4fQCDAgAAAA==.',
Ph='Phatt:BAAANQAECgMIAwAAAA==.Phoenixdrac:BAAANQADCggICQAAAA==.Phoon:BAECNQAFFH8NAAMaAAQKzxuYDwDWAAAaAAQKzxuYDwDWAAAbAAEKKRG4HgBLAAA1AAQKfzYABBoACgpoI7snABUCABoACAovI7snABUCABsABAqiIXAkAE8BAB8AAQpJDhIbAD4AAAAA.Phoondk:BAEANQAECgUICAABNQAFFAQIDQAaAM8bAA==.',
Pi='Piggy:BAAANQAECggIDwAAAA==.Pita:BAAANQABCgYIBgAAAA==.Pizzadriver:BAACNQAFFH8gAAMRAAgKPR4XBACZAgARAAgKPR4XBACZAgAlAAEKAADIBQBLAAA1AAQKfzMAAxEACgouJlACAHIDABEACgomJlACAHIDACUAAQo9JuEnAG4AAAAA.',
Pl='Plaguefist:BAAANQADCgcIBwABNQADCggIEgAEAAAAAA==.Plata:BAAANQAECgcIEwAAAA==.',
Po='Poosicat:BAAANQABCgYIBgAAAA==.Poosycat:BAAANQADCgMIAQAAAA==.',
Pr='Praytroxx:BAAANQAECgQIDAABNQAFFAcIEgATADUXAA==.Premonitions:BAAANQAECgYIBgAAAA==.Premune:BAABNQAECn82AAIUAAoKWyFeGgBwAgAUAAoKWyFeGgBwAgAAAA==.Prion:BAABNQAECn8ZAAQnAAoKSxVSMAAlAgAnAAoKnhNSMAAlAgAKAAEKlRTlaABAAAAJAAEKOgt4NAAqAAAAAA==.',
Pu='Pucco:BAAANQADCgIIAgAAAA==.Putrav:BAAANQAECgYICAAAAA==.',
Py='Pyrena:BAAANQADCgEIAQAAAA==.Pyroclasm:BAAANQAECgUICgAAAA==.Pyrrha:BAAANQADCgMIAwAAAA==.',
Qu='Quigly:BAAANQADCgIIAgAAAA==.',
Ra='Ragingfluids:BAABNQAECn8lAAMlAAoKTxJSEgB+AQARAAoKvRHBfgAeAgAlAAYKnBRSEgB+AQAAAA==.Rahdek:BAAANQADCgMIAwAAAA==.Raine:BAACNQAFFH8fAAIPAAgKhhcyBAA/AgAPAAgKhhcyBAA/AgA1AAQKfywAAw8ACgrGFRpSAB4CAA8ACgrGFRpSAB4CAAgACAqxGpgrALEBAAAA.Raistlin:BAAANQADCgEIAQAAAA==.Ralfio:BAABNQAECn8zAAMgAAoKUSAZCQARAwAgAAoKUSAZCQARAwAoAAEKAACVJAAzAAAAAA==.Rasq:BAABNQAECn8VAAMYAAkK9QUqLAA3AQAYAAkK9QUqLAA3AQABAAEKAACnzAAUAAAAAA==.Rat:BAABNQAECn8XAAIWAAkKNCGiCABOAwAWAAkKNCGiCABOAwAAAA==.Raudykill:BAAANQAECgQIAgAAAA==.Rayaray:BAAANQADCgYIBgAAAA==.Raynith:BAABNQAECn85AAQXAAkKDyC1CgCPAQABAAkK2h3jGADNAQAXAAcKgiC1CgCPAQAYAAMK4xGAOwBuAAAAAA==.Rayraye:BAAANQADCgIIAgAAAA==.',
Rd='Rdyoshy:BAAANQADCgUIBQAAAA==.',
Re='Readycheck:BAABNQAECn8wAAQBAAoKbRGPNgA3AgABAAoK0RCPNgA3AgAYAAcKyQg3MAAaAQAmAAEK1xLYVgA4AAAAAA==.Reflex:BAAANQAECgIIAgAAAA==.Regirock:BAAANQABCgMIAwAAAA==.Rellek:BAAANQAECgIIAgAAAA==.Remulous:BAAANQAECgcIDgAAAA==.Resist:BAAANQADCgYIBgAAAA==.Retallica:BAABNQAECn8YAAIDAAcKqQp46gBHAQADAAcKqQp46gBHAQAAAA==.Revali:BAACNQAFFH8KAAIMAAUKZw3BDQBhAQAMAAUKZw3BDQBhAQA1AAQKfz4AAwsACgorH8sxANcCAAsACgrFG8sxANcCAAwACgrEGUkYAJUCAAAA.Revelaen:BAAANQAECgcIDwABNQAFFAUICgAMAGcNAA==.',
Ri='Rick:BAACNQAFFH8NAAIMAAMKwxzaCQDMAAAMAAMKwxzaCQDMAAA1AAQKfykAAwwACgqbIiYGAKMCAAwACgpeIiYGAKMCAAsABApOIHIDAf4AAAAA.',
Rm='Rmagep:BAAANQAECgUICwAAAA==.',
Ro='Roadhouse:BAAANQAECgQIBwAAAA==.Roman:BAAANQAECgYIDAABNQAFFAQIBQAgAAoeAA==.Roshango:BAAANQADCgYIBgAAAA==.Rosinator:BAAANQAECggIAQAAAA==.Rotgus:BAAANQAECgEIAQAAAA==.Rouk:BAABNQAECn8UAAIRAAcKvR7OPwDRAQARAAcKvR7OPwDRAQABNQAECgoKJAADAKQmAA==.Rowgar:BAABNQAECn8jAAIOAAoKmxqxFAACAgAOAAoKmxqxFAACAgAAAA==.',
Ru='Rubenslik:BAABNQAECn8wAAICAAoKsCAQLAA3AwACAAoKsCAQLAA3AwAAAA==.',
Sa='Saelyn:BAAANQADCggIBgAAAA==.Saephora:BAABNQAECn8ZAAIjAAcKsAWnHgD2AAAjAAcKsAWnHgD2AAAAAA==.Saggypants:BAABNQAECn8fAAIBAAoKXBS+LwBjAgABAAoKXBS+LwBjAgAAAA==.Sakurai:BAAANQAECgEIAQABNQAECgEIAgAEAAAAAA==.Salamander:BAAANQAECgUJCgAAAA==.Salazzle:BAAANQADCgQIBAAAAA==.Sammel:BAAANQAECgUIEAAAAA==.Sanari:BAAANQADCgUIBwABNQAECgkJIwAIABgZAA==.Sandilla:BAAANQADCggICAABNQAECgoKGwAIAMkiAA==.Sangwine:BAAANQADCgYIBgAAAA==.Sapphica:BAAANQAECgEIAQAAAA==.Sathreina:BAABNQAECn8wAAIDAAoKzRU5VQC2AQADAAoKzRU5VQC2AQAAAA==.Sativva:BAAANQAECgIIAgABNQAECgoKGwAIAMkiAA==.',
Sc='Scaries:BAABNQAECn8gAAISAAoK4RlTBwDIAgASAAoK4RlTBwDIAgAAAA==.Scootko:BAABNQAECn8eAAIDAAkKCiXsQQDPAgADAAkKCiXsQQDPAgAAAA==.Scuss:BAAANQADCggICAAAAA==.',
Se='Sefers:BAAANQADCgEIAQAAAA==.Sego:BAAANQAECgIIAwAAAA==.Sekimaru:BAAANQAECgEIAgAAAA==.Senli:BAAANQAECgIIAQAAAA==.Severson:BAABNQAECn8bAAIMAAgKXAxfNACrAQAMAAgKXAxfNACrAQAAAA==.Sey:BAAANQADCgYIBgAAAA==.',
Sh='Shadowapoke:BAAANQADCgUIBQABNQAECgEIAQAEAAAAAA==.Shadowisbad:BAABNQAECn8qAAIGAAoKehhYHABiAgAGAAoKehhYHABiAgAAAA==.Shadvoker:BAABNQAECn8iAAMgAAgKzx2iDgC/AgAgAAgKzx2iDgC/AgAQAAIK1BHUMwBvAAAAAA==.Shamaneggs:BAABNQAECn8lAAMPAAoKKSA6CQAuAwAPAAoKKSA6CQAuAwAdAAMKshBOKQDRAAAAAA==.Shamatroxx:BAABNQAECn8jAAIdAAkKbBuzCwDjAQAdAAkKbBuzCwDjAQABNQAFFAcIEgATADUXAA==.Shamberry:BAABNQAECn8WAAIdAAgKvRSDEQBRAgAdAAgKvRSDEQBRAgAAAA==.Shambles:BAAANQADCgYICQAAAA==.Shieldwalle:BAABNQAECn8XAAIeAAkK8x0KCwCMAgAeAAkK8x0KCwCMAgAAAA==.Shinobukocho:BAAANQADCgQJBAAAAA==.Shotigolova:BAAANQADCgcIEgAAAA==.',
Si='Sidesalad:BAAANQAECgQIBgAAAA==.Sidric:BAABNQAECn81AAIBAAoKnRD9FQD0AQABAAoKnRD9FQD0AQAAAA==.Siena:BAAANQADCgYIBgAAAA==.Silre:BAAANQAECgUIEAAAAA==.Sim:BAABNQAECn8lAAIRAAkKLiSvFQBjAwARAAkKLiSvFQBjAwABNQAECgoKGwAIAMkiAA==.Singularité:BAAANQAECggIEgABNQAFFAcICwAWACAPAA==.Sipplex:BAAANQAECgYICAAAAA==.',
Sl='Slander:BAAANQAECgQJBAABNQAECgUJCgAEAAAAAA==.Slanderous:BAAANQADCgEJAQABNQAECgUJCgAEAAAAAA==.Slappee:BAAANQAECgYIBwAAAA==.Slappeey:BAAANQAECgQIBAABNQAECgYIBwAEAAAAAA==.',
Sn='Snuudle:BAAANQAECgcIDwABNQAECgkJHAAaABwXAA==.',
So='Solokills:BAAANQADCgMIAwABNQAFFAMIBQALAFgXAA==.Sophia:BAAANQAECgcIEgAAAA==.Soundtrack:BAAANQADCgYICQABNQAECgIIAgAEAAAAAA==.Soyshine:BAAANQADCgYIBgAAAA==.',
Sp='Spaceman:BAACNQAFFH8JAAITAAQKvgSZCACpAAATAAQKvgSZCACpAAA1AAQKfxgAAhMACgrbDy4pANUBABMACgrbDy4pANUBAAAA.',
Sq='Squab:BAABNQAECn8cAAIBAAkKaR6+GQD6AgABAAkKaR6+GQD6AgAAAA==.Squanchy:BAAANQADCgYJCAAAAA==.',
St='Stabbywixx:BAAANQAECgIIAgAAAA==.Starwnd:BAABNQAECn8UAAIaAAcKlheaggDfAQAaAAcKlheaggDfAQABNQAFFAYIDgAoAMcOAA==.Sterìs:BAAANQAECgEIAQAAAA==.Stillcreepin:BAAANQAECgEIAQAAAA==.Storienn:BAAANQAECgcIEwAAAA==.Stormzpaly:BAAANQAECgYIEQAAAA==.',
Su='Suküna:BAAANQADCggIFwAAAA==.Sunbur:BAAANQADCgYICgAAAA==.Sunglo:BAAANQAECgUIBwAAAA==.Surch:BAAANQADCgEIAQAAAA==.',
Sw='Swaption:BAABNQAECn8yAAIPAAoK1CGQBgBhAwAPAAoK1CGQBgBhAwAAAA==.Sweetie:BAAANQADCgEIAQAAAA==.',
Sy='Syrelia:BAABNQAECn8+AAICAAoKIxdFMQAsAgACAAoKIxdFMQAsAgAAAA==.',
['Só']='Sónny:BAAANQABCgIIAgAAAA==.',
Ta='Tablescraps:BAAANQABCggICAABNQADCgIIAgAEAAAAAA==.Tassarosea:BAAANQAECgcIBwABNQAFFAQIDAAQABEhAA==.Tauloe:BAAANQAECgUIDwAAAA==.Tayna:BAABNQAECn8WAAIGAAcKNgxnHwANAQAGAAcKNgxnHwANAQAAAA==.',
Te='Tenderoni:BAAANQADCgEIAQAAAA==.',
Th='Thatsmyhorse:BAAANQADCgIIAgAAAA==.Thatsograven:BAAANQADCgQIBAABNQAFFAgIIAABAOAfAA==.Thomosaurus:BAAANQADCggIDAAAAA==.Thraly:BAAANQADCgYIBwAAAA==.Thunk:BAABNQAECn8bAAIIAAoKySLACwCJAwAIAAoKySLACwCJAwAAAA==.',
Ti='Timdawg:BAABNQAECn8VAAMjAAkK6CBXDAD2AQAjAAcKgSNXDAD2AQACAAUKahLJQAEhAQABNQAFFAgIIAAaAEEZAA==.Timmolate:BAACNQAFFH8gAAQaAAgKQRn9BgD6AQAaAAYKoRr9BgD6AQAbAAIKwRfpCgCjAAAfAAIKRAlLCABXAAA1AAQKfzMABBoACgoMJXwNAL4CABoACQqtI3wNAL4CABsACAoMGQULAEcCAB8AAQr9IFYUAGEAAAAA.Tiramisubear:BAAANQAECggICgAAAA==.Tircaps:BAAANQADCgUIBQAAAA==.',
To='Tomcruise:BAAANQAECgIIAgAAAA==.Tomotostein:BAACNQAFFH8LAAIDAAUK5gwQDwDNAAADAAUK5gwQDwDNAAA1AAQKfycAAgMACgqCGEhsAFkCAAMACgqCGEhsAFkCAAAA.Tornado:BAAANQABCgQICQABNQADCgQIBAAEAAAAAA==.',
Tr='Trilla:BAAANQAECgQICAAAAA==.Tristîtia:BAABNQAECn8ZAAMGAAkK/A4nJAAQAgAGAAkK/A4nJAAQAgAFAAIKCwki5gB1AAAAAA==.Trulu:BAAANQAECgEIAQAAAA==.',
Ts='Tsukikyo:BAAANQADCgQIBAAAAA==.Tsuma:BAAANQABCgIIAgAAAA==.Tsume:BAAANQAECgYIDQAAAA==.',
Tt='Ttomas:BAAANQAECggIEwAAAA==.',
Ty='Tyrinn:BAABNQAECn8YAAIOAAkK6g/HKgBJAQAOAAkK6g/HKgBJAQAAAA==.Tyv:BAABNQAECn84AAICAAoKthAHPwD5AQACAAoKthAHPwD5AQAAAA==.',
Ul='Ulmerideavus:BAAANQADCgcIBwAAAA==.',
Up='Updatè:BAAANQAECgEIAQABNQAECggIDwAEAAAAAA==.',
Ur='Urgent:BAAANQADCgMIBAAAAA==.',
Uz='Uzì:BAAANQADCgIIAgAAAA==.',
Va='Vainatetosix:BAAANQAECgUICQAAAA==.Vallodon:BAABNQAECn8kAAICAAkKHCISTgDlAgACAAkKHCISTgDlAgAAAA==.Vantablack:BAAANQABCgIIAgABNQADCgQIBAAEAAAAAA==.Vanwolfy:BAABNQAECn8aAAIeAAoKUxI9FQDUAQAeAAoKUxI9FQDUAQAAAA==.Vaylorian:BAAANQAECgUIEAAAAA==.',
Ve='Velectran:BAAANQADCgUICgABNQAECgoKPgACACMXAA==.Velorian:BAAANQADCgQIBwAAAA==.Velveeta:BAAANQAECgMIAwAAAA==.Veragon:BAAANQADCgcIBwAAAA==.',
Vf='Vfacer:BAAANQADCgEIAQAAAA==.',
Vi='Vikav:BAAANQAECgIIAgAAAA==.Vikimg:BAABNQAECn8bAAIFAAoKoBabVgAfAgAFAAoKoBabVgAfAgAAAA==.Violet:BAAANQADCgEIAQAAAA==.',
Vo='Voodoomike:BAAANQAECgQIBAAAAA==.Vortash:BAAANQADCgUIBwAAAA==.',
Vy='Vynle:BAAANQAECgEIAQAAAA==.',
Wa='Warheimer:BAABNQAECn8YAAMVAAkKBQ+LXwCRAQAVAAkKBQ+LXwCRAQAOAAQKVgZpoQCUAAAAAA==.Warrgodx:BAABNQAECn9QAAMRAAoKaiSrCgASAwARAAoKaiSrCgASAwAlAAEKygioMwA0AAABNQAFFAQIBQADAFMZAA==.',
Wh='Whoknows:BAAANQADCgIIAgAAAA==.',
Wo='Woogi:BAAANQADCgUIBQAAAA==.',
Wr='Wrongwookie:BAABNQAECn8uAAIIAAoKPBlyKwCxAQAIAAoKPBlyKwCxAQAAAA==.',
Ya='Yapper:BAAANQADCgMIAwAAAA==.',
Yo='Yolanda:BAAANQAECgIIAgAAAA==.Yoyohunty:BAAANQAECgYICQAAAA==.',
Yt='Ytix:BAAANQAECgEIAQAAAA==.',
Yu='Yumekoo:BAAANQADCgIIAgAAAA==.',
Za='Zabada:BAAANQAECgQIBwAAAA==.Zaldrea:BAAANQAECgcICAABNQAFFAYIDAAGAKoLAA==.Zandrea:BAAANQAECgcIEAABNQAFFAYIDAAGAKoLAA==.Zariee:BAAANQABCgIIAwAAAA==.',
Ze='Zehz:BAABNQAECn8aAAIZAAkKZAFhkgByAAAZAAkKZAFhkgByAAAAAA==.Zemsen:BAABNQAECn8nAAICAAkKoh3yawCmAgACAAkKoh3yawCmAgAAAA==.Zentrea:BAAANQAECgQIBQABNQAFFAYIDAAGAKoLAA==.Zenyea:BAABNQAECn8YAAIPAAkKhw7CiwBsAQAPAAkKhw7CiwBsAQABNQAFFAYIDAAGAKoLAA==.Zetta:BAACNQAFFH8MAAIGAAYKqgswCQB0AQAGAAYKqgswCQB0AQA1AAQKfzEAAgYACgqEHekHAIgCAAYACgqEHekHAIgCAAAA.',
Zo='Zome:BAABNQAECn9CAAMiAAoKhhzzEwCDAgAiAAoKhhzzEwCDAgAWAAEKlAM4pgAwAAAAAA==.Zorojoro:BAAANQAECgYICgAAAA==.',
Zy='Zyndrael:BAABNQAECn8mAAIDAAoKqyHkLAAUAwADAAoKqyHkLAAUAwAAAA==.',
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
