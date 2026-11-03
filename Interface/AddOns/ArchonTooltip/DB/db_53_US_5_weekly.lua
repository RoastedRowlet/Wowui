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

local lookup = {'Druid-Balance','Mage-Arcane','Paladin-Retribution','Unknown-Unknown','Priest-Holy','Priest-Shadow','Druid-Feral','Priest-Discipline','Shaman-Elemental','DemonHunter-Vengeance','DemonHunter-Devourer','Mage-Fire','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','DeathKnight-Blood','Shaman-Restoration','Evoker-Devastation','Druid-Restoration','Warrior-Arms','DeathKnight-Frost','Monk-Brewmaster','Monk-Windwalker','Paladin-Holy','DeathKnight-Unholy','Rogue-Assassination','Druid-Guardian','Warlock-Destruction','Warlock-Demonology','Rogue-Outlaw','Warrior-Protection','Warlock-Affliction','Evoker-Preservation','Monk-Mistweaver','Shaman-Enhancement','Rogue-Subtlety','Mage-Frost','Hunter-Survival','Warrior-Fury','DemonHunter-Havoc','Evoker-Augmentation',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Accost:BAAANQADCgcIDQAAAA==.Achendron:BAAANQADCgUIBQABNQAFFAgIIAABAOAfAA==.Acronica:BAAANQAECgUIEgAAAA==.',
Ad='Addilynn:BAAANQABCgEIAQAAAA==.',
Ak='Akassa:BAAANQADCgcICwAAAA==.Aknologia:BAAANQAECgUICwABNQAECgoKGwACAPcOAA==.',
Al='Alecto:BAABNQAECn8oAAIDAAkKAghItgAlAQADAAkKAghItgAlAQAAAA==.Allele:BAAANQAECgMIAwAAAA==.Allet:BAAANQADCggIFwABNQAECgcIEQAEAAAAAA==.',
Am='Amarah:BAACNQAFFH8FAAIFAAQKTgYmGQDwAAAFAAQKTgYmGQDwAAA1AAQKfz8AAwUACgriHmIdAMACAAUACgriHmIdAMACAAYAAQoAACRnAAAAAAAA.Amazome:BAABNQAECn8WAAIHAAoKNhSXCQD+AQAHAAoKNhSXCQD+AQAAAA==.Ameilie:BAACNQAFFH8KAAMFAAQK+R7WEQBNAQAFAAQK+R7WEQBNAQAIAAIK9QV1AQB2AAA1AAQKf0gABAgACgo/IKkCAE4CAAUACgrjH8YdAPoCAAgACQqbGKkCAE4CAAYAAQoACrpSADoAAAAA.',
An='Anapuwae:BAABNQAECn8UAAIJAAYKSA0CqwA+AQAJAAYKSA0CqwA+AQAAAA==.Animehero:BAABNQAECn8qAAMKAAoKVR2gBQDRAgAKAAgKHCCgBQDRAgALAAYKsRddGQCwAQAAAA==.',
Ar='Arcant:BAABNQAECn8sAAMCAAoKzRn/WADgAQACAAoKzRn/WADgAQAMAAEKQQzKCQA6AAAAAA==.Ardicov:BAAANQADCgYICwAAAA==.Argadin:BAAANQAECgcICAABNQAECgoKLwANAG0iAA==.Arglock:BAAANQAECgUIBAABNQAECgoKLwANAG0iAA==.Argrekh:BAABNQAECn8vAAMNAAoKbSLQCgCHAwANAAoKbSLQCgCHAwAOAAEKQQ/phgA3AAAAAA==.Argreks:BAAANQAECgIIAwABNQAECgoKLwANAG0iAA==.Argrekt:BAAANQAECgIIAgABNQAECgoKLwANAG0iAA==.Aridol:BAAANQADCgYIBgAAAA==.Arigön:BAAANQADCgYICAAAAA==.Aronna:BAAANQADCgYICAAAAA==.Arosea:BAAANQADCgYIBgAAAA==.Arthaslk:BAACNQAFFH8FAAIDAAQKUxksIwCTAAADAAQKUxksIwCTAAA1AAQKf1IAAwMACgrmJekCAOYDAAMACgrmJekCAOYDAA8ABAoTD3s/AH8AAAAA.Aryssol:BAAANQAECgIIAgAAAA==.',
At='Ate:BAABNQAECn8jAAIQAAgKfBA7LQB0AQAQAAgKfBA7LQB0AQAAAA==.Atlette:BAAANQAECgMIAwAAAA==.Attman:BAACNQAFFH8QAAIRAAUK6RXwCwBYAQARAAUK6RXwCwBYAQA1AAQKf0wAAxEACgoIJFQMAEADABEACgoIJFQMAEADAAkAAwrLEqGOALYAAAAA.',
Au='Auradawn:BAAANQADCgcIDwAAAA==.',
Ba='Backwater:BAAANQAECgQIBAABNQAECgcIEQAEAAAAAA==.Badhands:BAAANQAECgIIAgAAAA==.Baeator:BAAANQAECgEIAQABNQAFFAcIGAASAO0PAA==.Barneystins:BAAANQABCgEIAgABNQADCgQIBAAEAAAAAA==.',
Be='Bearmane:BAACNQAFFH8JAAIBAAQK1x9tCgAUAQABAAQK1x9tCgAUAQA1AAQKfzMAAwEACgrdIp8OAFUDAAEACgrdIp8OAFUDABMAAgoSDm5XAGMAAAAA.Beastarsfan:BAABNQAECn8oAAIJAAoKnyOPCwCLAwAJAAoKnyOPCwCLAwAAAA==.Behmow:BAABNQAECn9JAAIUAAoKvCblAgB2AwAUAAoKvCblAgB2AwAAAA==.Belithel:BAAANQAECgQIBgABNQAECgoKJwAJAHgYAA==.Bencreepin:BAABNQAECn8YAAMQAAYKyRFCWwCvAAAQAAUKyRFCWwCvAAAVAAMKCwj2nABYAAAAAA==.Bernoulli:BAABNQAECn8uAAMWAAoKoxajBQAEAgAWAAoKoxajBQAEAgAXAAEKAAADYwAAAAAAAA==.',
Bi='Bigspitter:BAAANQADCgYIBgABNQAECgoKOAACAHAlAA==.Bis:BAAANQADCgUJBQABNQAECgkJFgACAD0cAA==.',
Bl='Blessedxx:BAAANQAECgUIBgAAAA==.Bloodboo:BAAANQADCgQIBAAAAA==.Bloodyhpally:BAACNQAFFH8eAAIYAAgK1xdDAwBoAgAYAAgK1xdDAwBoAgA1AAQKfy4AAxgACgrSHh8gAI0CABgACgrSHh8gAI0CAAMAAgoXD4lmAXsAAAAA.',
Bo='Boopsnoopems:BAABNQAECn8cAAIPAAYKzw8JOQCdAAAPAAYKzw8JOQCdAAAAAA==.Borderline:BAAANQAECgUIBQABNQAFFAUIDgAXAFoEAA==.',
Br='Bradcrit:BAAANQAECgIIAQAAAA==.',
Bu='Bubble:BAABNQAECn8WAAMYAAcKEAfJuQAJAQAYAAYKIAfJuQAJAQADAAUKgggXJAHjAAAAAA==.Bulldoser:BAAANQADCgQIBAAAAA==.Burrfoot:BAAANQAECgIIAwAAAA==.Bustah:BAAANQAECgcIEgABNQAECggIFwAZAMQbAA==.',
Bw='Bwoodmorgan:BAAANQAECgYIDgAAAA==.',
By='Byron:BAAANQAECgQIBgAAAA==.',
Ca='Calene:BAACNQAFFH8LAAIaAAcKIA8kBQDkAQAaAAcKIA8kBQDkAQA1AAQKf1MAAhoACgonJOACAAkDABoACgonJOACAAkDAAAA.Candy:BAAANQAECgMIBQAAAA==.Cannedcorn:BAAANQAECgIIAgAAAA==.Caperusin:BAAANQAECgUICAAAAA==.Casare:BAAANQADCgYIFgAAAA==.Cayde:BAAANQADCgYJBgABNQAFFAUICgAOAGcNAA==.',
Ce='Celestinee:BAAANQAECgYIEwAAAA==.Celyda:BAAANQAECgUICAAAAA==.Cenarian:BAAANQABCgUIBwAAAA==.',
Ch='Chabotloe:BAAANQAECgMIBQAAAA==.Chape:BAABNQAECn8dAAMYAAkKvhcQPgBsAgAYAAkKvhcQPgBsAgADAAYK/BBE7wA+AQABNQABCgEIAQAEAAAAAA==.Chence:BAAANQADCgYIBgAAAA==.Chochalinda:BAABNQAECn8dAAMHAAgKvxHBFgCNAQAHAAcKXBDBFgCNAQAbAAUK8xTfLQArAQAAAA==.',
Ci='Cinderlee:BAABNQAECn8UAAIcAAYKKAUEFACfAAAcAAYKKAUEFACfAAAAAA==.',
Co='Colexn:BAABNQAECn8lAAQVAAkKwBZnOgDoAQAVAAkKwBZnOgDoAQAZAAIKMhDJwQBnAAAQAAEKAACwsAAAAAAAAA==.Cong:BAACNQAFFH8FAAIUAAQK3ghxIAD/AAAUAAQK3ghxIAD/AAA1AAQKfycAAhQACgqnG/MnABoDABQACgqnG/MnABoDAAAA.Corg:BAAANQADCgYIBgAAAA==.Cornchipz:BAABNQAECn8bAAICAAoK9w5e0ADlAQACAAoK9w5e0ADlAQAAAA==.',
Cr='Crapsack:BAAANQABCgEIAQAAAA==.Croski:BAAANQADCgEIAQAAAA==.Cryonidus:BAAANQAECgEIAQAAAA==.',
Cu='Curves:BAAANQAECgEIAQAAAA==.',
Cy='Cypressa:BAAANQADCgQIBAAAAA==.',
Da='Daangalanng:BAABNQAECn8oAAIYAAoKyBapRABTAgAYAAoKyBapRABTAgAAAA==.Dabberoni:BAAANQAECgEIAgAAAA==.Daegra:BAABNQAECn8pAAIaAAoKXByaDwAEAwAaAAoKXByaDwAEAwAAAA==.Dankkush:BAAANQADCgQIBAAAAA==.Darkacedia:BAABNQAECn8vAAMdAAkKihXHTQBrAgAdAAkKihXHTQBrAgAcAAMKKwp9TwCRAAAAAA==.Darkzetta:BAAANQAECgIIAgABNQAFFAYIDAAGAKoLAA==.Datbish:BAAANQAECgIIAgAAAA==.',
De='Deadlift:BAABNQAECn8kAAIZAAoKpBixFAAhAgAZAAoKpBixFAAhAgAAAA==.Deadlyhoof:BAAANQAECgMIAwAAAA==.Dealosed:BAABNQAECn8ZAAMaAAgKphkIKwA+AgAaAAgKeRkIKwA+AgAeAAQKDhXyEQDsAAAAAA==.Deathawolf:BAAANQAECgEIAQAAAA==.Deathkilera:BAAANQADCgUIBwAAAA==.Defy:BAAANQADCgYIBgAAAA==.Delenn:BAABNQAECn8XAAIHAAgKZxrsDQA6AgAHAAgKZxrsDQA6AgAAAA==.Demonclawz:BAAANQAECgYIBgAAAA==.Demonnyaa:BAAANQADCgcIBwAAAA==.Deneb:BAAANQADCgIIAgABNQAECgkJFgAGAIYgAA==.Derzy:BAAANQADCgIIAgAAAA==.Dewygirl:BAAANQADCgcICgAAAA==.',
Dh='Dhuumystic:BAAANQADCgEIAQAAAA==.',
Di='Disastapyre:BAAANQAECgIIAgABNQAFFAMICAAQAM8HAA==.Disastasmite:BAAANQADCgIIBAABNQAFFAMICAAQAM8HAA==.Dive:BAABNQAECn8WAAICAAkKPRyyYwC3AgACAAkKPRyyYwC3AgAAAA==.',
Do='Doogru:BAABNQAECn9DAAIfAAoK7RseBwBHAgAfAAoK7RseBwBHAgAAAA==.Doogtwo:BAAANQADCggIHAABNQAECgoKQwAfAO0bAA==.Doryndoran:BAAANQAECgQIBQAAAA==.Dorynhashots:BAAANQADCgUIBQAAAA==.Dotproduct:BAAANQADCgEIAQABNQADCgIIAgAEAAAAAA==.Dotsrock:BAABNQAECn8uAAMgAAoKZxNiBQDwAQAgAAoKZxNiBQDwAQAdAAUKcQeX0QB/AAAAAA==.Dovah:BAAANQADCgIIAgAAAA==.',
Dr='Dragoneggs:BAABNQAECn8jAAMSAAoKBBkXDQCRAgASAAoKBBkXDQCRAgAhAAoKBQp2HwDdAQAAAA==.Dragonforce:BAAANQADCggIEgAAAA==.Drakonutz:BAAANQAECgYIDwAAAA==.Draxx:BAAANQAECggIDAAAAA==.Drañzer:BAAANQAECgEIAgAAAA==.Dreammachine:BAAANQAECgcIBwAAAA==.Drjoel:BAAANQADCgcIEQAAAA==.Drunkenutz:BAABNQAECn8ZAAQXAAkK7g1POACsAAAWAAUKLxCcIQDQAAAXAAUKPgxPOACsAAAiAAQKcA+/JgCiAAAAAA==.Drâx:BAAANQAECggICQAAAA==.Dräx:BAAANQAECggIEgAAAA==.',
Dw='Dwallen:BAAANQADCgIIAgAAAA==.Dwightschrut:BAAANQADCgQIBAAAAA==.',
['Dä']='Dälf:BAAANQAECgIIAgABNQAFFAcICQAPABsVAA==.',
Ea='Earthshocker:BAABNQAECn8aAAMJAAkKpBHgRQCDAQAJAAgKhBPgRQCDAQARAAEKXACO/AANAAAAAA==.',
Ed='Edirii:BAAANQABCgIIAgAAAA==.',
El='Elenix:BAAANQAECgcIAQAAAA==.Elki:BAAANQADCgQIBgAAAA==.Elmesia:BAABNQAECn8UAAICAAcKTQjwGAFiAQACAAcKTQjwGAFiAQAAAA==.Eloris:BAABNQAECn8lAAILAAgK7RxGHABzAgALAAgK7RxGHABzAgAAAA==.Elpato:BAAANQADCgcIBwABNQAECgoKOAACAHAlAA==.Elthyn:BAAANQAECggIDwAAAA==.Elvar:BAAANQAECgEIAQAAAA==.',
Em='Emachine:BAAANQADCggICAABNQAECgIIAgAEAAAAAA==.Emeraldrin:BAAANQADCgEIAQAAAA==.Emz:BAABNQAECn85AAIeAAkKlyA4AQCEAgAeAAkKlyA4AQCEAgAAAA==.',
En='Eniar:BAAANQAECgMIBgAAAA==.',
Er='Erakk:BAAANQADCgEIAgAAAA==.Erianda:BAAANQABCgQIBAAAAA==.Eric:BAABNQAECn8cAAIUAAcK5RyiegAoAgAUAAcK5RyiegAoAgAAAA==.Eroninja:BAAANQAECgIIAwABNQAECgoKJwAJAHgYAA==.Erín:BAABNQAECn8kAAIdAAYK9RHojwAFAQAdAAYK9RHojwAFAQAAAA==.',
Eu='Eurong:BAACNQAFFH8HAAIBAAQKsxE4FgAGAQABAAQKsxE4FgAGAQA1AAQKfzcAAgEACgoCI9sGABUDAAEACgoCI9sGABUDAAAA.',
Ez='Ezynuff:BAAANQAECgYIEgAAAA==.',
Fa='Faner:BAAANQADCgEIAgABNQAECgEIAQAEAAAAAA==.Fapple:BAAANQAECgUICQABNQAECgoKNwAhACMjAA==.Fatesworn:BAAANQADCgcIBwAAAA==.Faïry:BAABNQAECn84AAINAAoKfCL6EQDpAgANAAoKfCL6EQDpAgAAAA==.',
Fe='Feaughoeren:BAABNQAECn8fAAMjAAoK9AkVFACNAQAjAAkKYQkVFACNAQARAAkKpQUtYABkAQAAAA==.Felwyrm:BAABNQAECn8sAAIdAAkKgRd4UABjAgAdAAkKgRd4UABjAgABNQAFFAUIDgAXAFoEAA==.Feralina:BAAANQABCgIIAgAAAA==.Feralshmeral:BAAANQABCgQIBAABNQAECgoKIQANAKAhAA==.',
Fo='Foxi:BAAANQADCggIEQABNQAECgkJGgAFAHocAA==.',
Fr='Frank:BAAANQAECggIEAAAAA==.Freakbeast:BAAANQAECgYJEgABNQAECgoKJgAeAMciAA==.Fries:BAEANQAECggICwABNQAECggIDwAEAAAAAA==.',
Fu='Fullkidney:BAACNQAFFH8KAAIaAAQKeB4fCgBfAQAaAAQKeB4fCgBfAQA1AAQKfyAAAhoACQrbIqAJAEIDABoACQrbIqAJAEIDAAAA.Funch:BAABNQAECn8qAAIgAAoKChUhBQB4AgAgAAoKChUhBQB4AgAAAA==.',
Ga='Gaefaeryn:BAACNQAFFH8KAAIGAAQKow6MCQDWAAAGAAQKow6MCQDWAAA1AAQKfycAAwYACgogFn0bAGwCAAYACgogFn0bAGwCAAgAAQqaAQ0yAB8AAAAA.Gainzz:BAAANQAECgEIAQAAAA==.Garonnaa:BAABNQAECn8wAAIQAAoKGxlnFQA5AgAQAAoKGxlnFQA5AgAAAA==.Garthel:BAABNQAECn8zAAIXAAoKbBRtEgAHAgAXAAoKbBRtEgAHAgAAAA==.',
Ge='Genetiks:BAAANQADCgYIDAAAAA==.',
Gh='Ghari:BAABNQAECn8tAAIZAAcK4hHdLgBDAQAZAAcK4hHdLgBDAQAAAA==.',
Gi='Gingerlock:BAABNQAECn82AAIdAAoKlBwpIQBpAgAdAAoKlBwpIQBpAgAAAA==.Gingershaman:BAAANQAECgUIBQAAAA==.Giyuu:BAAANQADCgUIBQAAAA==.',
Gn='Gnoblin:BAAANQADCggIFgAAAA==.',
Gr='Greka:BAABNQAECn8bAAIJAAUKvgvbhQDKAAAJAAUKvgvbhQDKAAAAAA==.Greylooms:BAAANQADCgcIBwAAAA==.Griplock:BAABNQAECn9BAAMQAAoKAQ5EQQARAQAQAAkK+AtEQQARAQAVAAIKQREsfwB5AAAAAA==.',
Gu='Gutz:BAAANQAECgUICwAAAA==.',
['Gö']='Gözër:BAAANQADCgMIAwABNQAECgYIBgAEAAAAAA==.',
Ha='Happyfriend:BAAANQAECgEIAQABNQAFFAUIDgAXAFoEAA==.Haruko:BAAANQADCggICAAAAA==.',
He='Healalle:BAAANQADCgYICwABNQAECgkJFwAfAPMdAA==.Healhole:BAABNQAECn81AAMRAAoKZyFREwAwAwARAAoKZyFREwAwAwAJAAMKbhFO7gC6AAAAAA==.Heimdall:BAAANQAECgEIAgAAAA==.Heàl:BAABNQAECn8WAAMGAAkKhiDoDwD3AgAGAAkKhiDoDwD3AgAIAAEKwxQ0JgA+AAAAAA==.',
Hi='Hidolo:BAAANQADCgYIDAAAAA==.',
Hr='Hruwa:BAAANQADCgMIAwABNQAECgEIAQAEAAAAAA==.',
Hu='Hunterishard:BAAANQAECgQIBAABNQAECgYIBwAEAAAAAA==.',
Hy='Hylaina:BAAANQADCgYJCgAAAA==.',
['Hô']='Hôlÿ:BAAANQADCggIDgAAAA==.',
Ia='Iamamonk:BAAANQADCgEIAQAAAA==.',
Ik='Ikerous:BAAANQADCgMIAwAAAA==.',
Il='Ilysa:BAAANQABCgQIBAAAAA==.',
Im='Imadwagon:BAAANQADCgcIAgAAAA==.Imcolorblind:BAAANQADCgIIAgAAAA==.Imhammered:BAAANQAECgYIDgAAAA==.',
Io='Ioun:BAAANQADCgMIAwAAAA==.Iounn:BAAANQADCgcIBwABNQAECgoKJgAiAJcVAA==.',
Ir='Ironpally:BAAANQAECgIIAgAAAA==.',
Is='Isatku:BAAANQAECgEIAQAAAA==.',
It='Itiswhatitiz:BAABNQAECn82AAINAAkKrhuNOQC9AgANAAkKrhuNOQC9AgAAAA==.Itsybityshiv:BAABNQAECn81AAIkAAoKshgKDwCJAgAkAAoKshgKDwCJAgAAAA==.',
Ja='Jakarr:BAAANQADCgUICQAAAA==.Jams:BAAANQAECgUIBQAAAA==.',
Je='Jeabuss:BAAANQADCgUIBQAAAA==.Jella:BAAANQAECgIIAQAAAA==.Jerricho:BAAANQAECgQIBwAAAA==.',
Jh='Jhani:BAABNQAECn8eAAIlAAgKoQa2FQD+AAAlAAgKoQa2FQD+AAAAAA==.',
Ji='Jiu:BAABNQAECn8cAAIFAAkKiBsVJgDTAgAFAAkKiBsVJgDTAgABNQAECggIFwAZAMQbAA==.',
Jo='Joethemage:BAABNQAECn82AAICAAoKSB3lRAD6AgACAAoKSB3lRAD6AgAAAA==.Jormojo:BAAANQAECgMIAwAAAA==.',
Ju='Jungol:BAAANQADCgUICQAAAA==.',
Ka='Kairupaws:BAAANQADCgYIBgAAAA==.Kallip:BAAANQADCggICAAAAA==.Kamin:BAAANQAECgYIBgABNQAECgkJIgACAMgbAA==.Katamaran:BAAANQAECgMIBAABNQAFFAYIDAAGAKoLAA==.Kaykaypally:BAABNQAECn8iAAIDAAgKvxAZiwB1AQADAAgKvxAZiwB1AQAAAA==.Kazbirt:BAAANQADCgIIAgAAAA==.',
Ke='Kellan:BAAANQADCggIFgAAAA==.',
Kh='Khybyr:BAAANQADCgMIAwAAAA==.',
Ki='Kidata:BAABNQAECn8mAAIiAAoKlxVCFgAYAgAiAAoKlxVCFgAYAgAAAA==.Kindaprepped:BAAANQADCgQIBAAAAA==.Kinji:BAABNQAECn8nAAIJAAoKeBjkSABTAgAJAAoKeBjkSABTAgAAAA==.Kinn:BAAANQADCggICAABNQAECgoKLgAWAKMWAA==.',
Ko='Konfu:BAAANQAECgYIBQAAAA==.Kormega:BAAANQAECgUIBQAAAA==.Korral:BAAANQADCggIDQAAAA==.',
Kr='Krispies:BAAANQAECgUIDQAAAA==.Kristysavage:BAABNQAECn8+AAMmAAoKiyE9AQBtAwAmAAoKriA9AQBtAwANAAIK+RuXKwGZAAAAAA==.Krul:BAAANQAECgUIBQAAAA==.',
Ku='Kulaesca:BAACNQAFFH8RAAIdAAUKLhYJCgA+AQAdAAUKLhYJCgA+AQA1AAQKfy0AAx0ACgrFGaVHAHwCAB0ACgrFGaVHAHwCABwAAQrtAOWHAB0AAAAA.',
Ky='Kynar:BAACNQAFFH8dAAMVAAgKxx1rAgAmAgAVAAcKxx1rAgAmAgAQAAYKngfuEABIAQA1AAQKfy8AAxUACgpZJkQKAEkDABUACgpZJkQKAEkDABAAAwqHE7qWALEAAAAA.Kyua:BAAANQAECgUIBAAAAA==.',
La='Ladragona:BAAANQADCggICAAAAA==.Laguna:BAAANQAECgQIBAABNQAECgoKMgAFAJ0XAA==.Lambshot:BAABNQAECn8oAAMOAAoKIReNDwATAgANAAgK1RIAdgAkAgAOAAoKXhaNDwATAgAAAA==.Lambsy:BAACNQAFFH8iAAQUAAgKXhUZBwBPAgAUAAgKXhUZBwBPAgAnAAEKAAAaBgBIAAAfAAEKAACwCQA9AAA1AAQKf0EAAxQACgpsJWwGAFMDABQACgpoJWwGAFMDACcAAwoCE/8hAKgAAAAA.Lanamama:BAAANQAECgEIAQABNQAECgIIAgAEAAAAAA==.Lanana:BAAANQADCgMIAwABNQAECgIIAgAEAAAAAA==.',
Le='Ledsole:BAAANQABCgIIAgAAAA==.Lerat:BAABNQAECn85AAISAAoKZR8FAwC5AgASAAoKZR8FAwC5AgAAAA==.',
Li='Lightfoot:BAAANQADCgcIBwAAAA==.Lightwarden:BAAANQADCgQIBAAAAA==.Lilyy:BAACNQAFFH8KAAMlAAMKexHnAgDYAAAlAAMKexHnAgDYAAACAAIKAAokTgCKAAA1AAQKfy4AAyUACgqqHYgGAJcCACUACApFH4gGAJcCAAIACQp8F4JzAJcCAAAA.Lisanalgaib:BAABNQAECn8iAAIDAAgKPBX1lgD2AQADAAgKPBX1lgD2AQAAAA==.Lizzimcguire:BAACNQAFFH8QAAISAAQKNCRGAQA4AQASAAQKNCRGAQA4AQA1AAQKfzkAAhIACgo9JXgBALYDABIACgo9JXgBALYDAAAA.',
Lo='Lobobare:BAABNQAECn8fAAITAAgK2x0hHABVAgATAAgK2x0hHABVAgAAAA==.Loraen:BAABNQAECn8fAAICAAcKtASYtQAQAQACAAcKtASYtQAQAQAAAA==.Lostep:BAAANQAECgEIAQABNQAFFAgIIAARAIYXAA==.',
Lu='Lunarmon:BAAANQADCgUIBQAAAA==.Lunchable:BAABNQAECn8gAAMRAAgKmh/hVAAUAgARAAcK/B7hVAAUAgAJAAYKzBV7gACjAQAAAA==.',
Ma='Maevora:BAABNQAECn8ZAAIGAAcKawSBTQDeAAAGAAcKawSBTQDeAAAAAA==.Makaroni:BAAANQAECgUIBQAAAA==.Manticus:BAAANQADCgYICAAAAA==.Marni:BAABNQAECn8cAAMFAAgK3hKzcgDEAQAFAAgK3hKzcgDEAQAGAAIKAAC4YwAAAAABNQAECgoKKwADAOEhAA==.Marsrover:BAAANQAECgIIAgABNQAFFAgIIQAUAD0eAA==.Martel:BAAANQADCgQIBAAAAA==.Matroxx:BAACNQAFFH8SAAIXAAcKNRcSBwCLAQAXAAcKNRcSBwCLAQA1AAQKf0MAAhcACgrKJPIEABADABcACgrKJPIEABADAAAA.',
Me='Medinduceyuh:BAAANQADCgEIAQAAAA==.Meenoi:BAABNQAECn8XAAIZAAgKxBtHRQAEAgAZAAgKxBtHRQAEAgAAAA==.Mellotots:BAAANQABCgIIBAAAAA==.Metatron:BAAANQADCgIIAgAAAA==.',
Mi='Miadas:BAAANQAECgMIAwABNQAECgkJPQAHAA8gAA==.Mika:BAAANQAECgMIAwABNQAFFAQIBQAFAE4GAA==.Mimikyu:BAAANQABCgYIBgAAAA==.Minìwheats:BAAANQADCgMIAwAAAA==.',
Mo='Moardotsnow:BAABNQAECn8xAAQcAAoKaCUwGACrAQAdAAcKoCXpVgBRAgAcAAQKCiUwGACrAQAgAAEKxB5MHwBPAAAAAA==.Moby:BAAANQAECgcIDAAAAA==.Moistmender:BAAANQAECgcIEQAAAA==.Mortiana:BAAANQADCggICAAAAA==.',
Mu='Murriar:BAAANQAECggICQABNQAECgoKMAAoABQhAA==.Murridan:BAABNQAECn8wAAIoAAoKFCH4CgDOAgAoAAoKFCH4CgDOAgAAAA==.',
My='Mykaela:BAAANQAECgEIAQAAAA==.',
['Më']='Mëow:BAAANQAECgUICgAAAA==.',
Na='Naausi:BAAANQADCgMIAwAAAA==.Namiyu:BAAANQADCgcIBwAAAA==.Narrath:BAAANQADCgMJAwAAAA==.Nayalaah:BAAANQAECgEIAQAAAA==.',
Ne='Nehpets:BAAANQADCgUIBQAAAA==.Nektzalla:BAABNQAECn8gAAIRAAkK4BqDKgBNAgARAAkK4BqDKgBNAgAAAA==.Nephelym:BAABNQAECn8gAAMFAAgKQA9ZcwDCAQAFAAgKQA9ZcwDCAQAIAAIKrAKOJABHAAAAAA==.Nerv:BAAANQADCgMIBQAAAA==.',
Ni='Nicolasmage:BAAANQABCgQIBQAAAA==.Nirina:BAABNQAECn8cAAINAAYKSwi6zQDRAAANAAYKSwi6zQDRAAAAAA==.',
No='Nohtil:BAAANQADCgYIGwAAAA==.Notstephen:BAABNQAECn8lAAMFAAoK6Ay3dQC7AQAFAAoK6Ay3dQC7AQAGAAQKCxBIWACpAAAAAA==.Nourishnutz:BAAANQADCgYIBgAAAA==.',
Nu='Nukefury:BAABNQAECn8fAAIjAAkKZB0oBwCUAgAjAAkKZB0oBwCUAgABNQAFFAMICAAQAM8HAA==.Nut:BAABNQAECn8UAAIcAAUKoBIjJwA+AQAcAAUKoBIjJwA+AQABNQAECggIIwAQAHwQAA==.',
Nw='Nwalliance:BAAANQAECgEIAQAAAA==.',
['Nö']='Nötprepared:BAAANQAECgUIBAABNQAECgUICQAEAAAAAA==.',
Oi='Oiflar:BAABNQAECn8fAAIhAAoKTBbIDAATAgAhAAoKTBbIDAATAgABNQAECgoKNwAhACMjAA==.',
Ol='Olangi:BAAANQAECgEIAQAAAA==.',
Om='Omnidh:BAAANQADCggIEAABNQAFFAUIDwAXAKEfAA==.Omnipotent:BAAANQAECgUIBQAAAA==.',
On='Onepavo:BAABNQAECn8pAAIkAAoKOhF2QQCwAQAkAAoKOhF2QQCwAQAAAA==.',
Oo='Oogie:BAAANQADCgYIBgAAAA==.Oogrikusk:BAAANQADCgIIAgAAAA==.Oottedenttoo:BAAANQADCgQIBAAAAA==.',
Op='Oppose:BAABNQAECn8VAAQHAAgKwhRcFAA4AQABAAcKbA2qVACGAQAHAAYK6BNcFAA4AQATAAQK9wxEUwC7AAAAAA==.',
Or='Orexion:BAABNQAECn8jAAInAAgKGwtAEgCAAQAnAAgKGwtAEgCAAQAAAA==.Oriavis:BAAANQAECgMIAwAAAA==.Ormagöden:BAABNQAECn8pAAIVAAoKMw2QQwC1AQAVAAoKMw2QQwC1AQAAAA==.',
Ov='Overpower:BAAANQADCgYIBgAAAA==.',
Pa='Pagoda:BAABNQAECn8UAAIBAAgKYwzVNAAwAQABAAgKYwzVNAAwAQAAAA==.Palladean:BAAANQAECgIIAwAAAA==.Palphen:BAAANQAECgcJDAABNQAECgoKJQAFAOgMAA==.Panako:BAAANQAECgUICQAAAA==.Pastasauce:BAABNQAECn8dAAIDAAYK3wnl/QAjAQADAAYK3wnl/QAjAQAAAA==.',
Pe='Pegero:BAAANQADCgYIDQABNQAFFAMIBQANAFgXAA==.Penelohpe:BAABNQAECn8iAAICAAkKyBt4fQCDAgACAAkKyBt4fQCDAgAAAA==.',
Ph='Phatt:BAAANQAECgMIAwAAAA==.Phoenixdrac:BAAANQADCggICQAAAA==.Phoon:BAECNQAFFH8NAAMdAAQKzxvsFgA+AQAdAAQKzxvsFgA+AQAcAAEKKRG4HgBLAAA1AAQKfzcABB0ACgpoI1M8AJ4CAB0ACAovI1M8AJ4CABwABAqiIXAkAE8BACAAAQpJDvQlADcAAAAA.Phoondk:BAEANQAECgUICAABNQAFFAQIDQAdAM8bAA==.',
Pi='Piggy:BAABNQAECn8bAAIRAAoKXgeAeAAXAQARAAoKXgeAeAAXAQAAAA==.Pita:BAAANQABCgYIBgAAAA==.Pizzadriver:BAACNQAFFH8hAAMUAAgKPR4XBACZAgAUAAgKPR4XBACZAgAnAAEKAADIBQBLAAA1AAQKfzQAAxQACgouJukEAGADABQACgomJukEAGADACcAAQo9JuEnAG4AAAAA.',
Pl='Plaguefist:BAAANQADCgcIBwABNQADCggIEgAEAAAAAA==.Plata:BAABNQAECn8XAAIUAAgKqQ4oqAD0AAAUAAgKqQ4oqAD0AAAAAA==.',
Po='Poosicat:BAAANQABCgYIBgAAAA==.Poosycat:BAAANQADCgMIAQAAAA==.',
Pr='Praytroxx:BAAANQAECgQIDgABNQAFFAcIEgAXADUXAA==.Premonitions:BAAANQAECgYIBgAAAA==.Premune:BAABNQAECn82AAIYAAoKWyGaLgCsAgAYAAoKWyGaLgCsAgAAAA==.Prion:BAABNQAECn8aAAQoAAoKSxVSMAAlAgAoAAoKnhNSMAAlAgALAAEKlRTlaABAAAAKAAEKOgt4NAAqAAAAAA==.',
Pu='Pucco:BAAANQADCgIIAgAAAA==.Purpleflurp:BAAANQAECggIBwAAAA==.Putrav:BAAANQAECgYICAAAAA==.',
Py='Pyrena:BAAANQADCgEIAQAAAA==.Pyroclasm:BAAANQAECgUICgAAAA==.Pyrrha:BAAANQADCgMIAwAAAA==.',
Qu='Quigly:BAAANQADCgIIAgAAAA==.',
Ra='Ragingfluids:BAABNQAECn8pAAMnAAoKNBZSEgB+AQAUAAoKohWSWwC0AQAnAAYKnBRSEgB+AQAAAA==.Rahdek:BAAANQADCgMIAwAAAA==.Raine:BAACNQAFFH8gAAIRAAgKhhcyBAA/AgARAAgKhhcyBAA/AgA1AAQKfy0AAxEACgrGFRpSAB4CABEACgrGFRpSAB4CAAkACAqxGnM9AKMBAAAA.Raistlin:BAAANQADCgEIAQAAAA==.Ralfio:BAABNQAECn83AAMhAAoKIyMZCQARAwAhAAoKIyMZCQARAwApAAEKAACVJAAzAAAAAA==.Rasq:BAABNQAECn8VAAMbAAkK9QUqLAA3AQAbAAkK9QUqLAA3AQABAAEKAACnzAAUAAAAAA==.Rat:BAABNQAECn8XAAIaAAkKNCGiCABOAwAaAAkKNCGiCABOAwAAAA==.Raudykill:BAAANQAECgcIBgAAAA==.Rayaray:BAAANQADCgYIBgAAAA==.Raynith:BAABNQAECn89AAQHAAkKDyABEAB4AQABAAkK2h2gHwDNAQAHAAcKgiABEAB4AQAbAAMK4xF4SQBpAAAAAA==.Rayraye:BAAANQADCgIIAgAAAA==.Raytard:BAAANQADCgcIBwAAAA==.',
Rd='Rdyoshy:BAAANQADCgUIBQAAAA==.',
Re='Readycheck:BAABNQAECn82AAQBAAoKWxKPNgA3AgABAAoKvxGPNgA3AgAbAAcKyQg3MAAaAQATAAEK1xKTZQA1AAAAAA==.Reflex:BAAANQAECgIIAgAAAA==.Regirock:BAAANQABCgMIAwAAAA==.Rellek:BAAANQAECgIIAgAAAA==.Remulous:BAABNQAECn8VAAINAAgKBRNpjQDvAQANAAgKBRNpjQDvAQAAAA==.Resist:BAAANQADCgYIBgAAAA==.Retallica:BAABNQAECn8jAAIDAAkKPQ22jAByAQADAAkKPQ22jAByAQAAAA==.Revali:BAACNQAFFH8KAAIOAAUKZw3BDQBhAQAOAAUKZw3BDQBhAQA1AAQKf0AAAw0ACgqNIMsxANcCAA0ACgooHcsxANcCAA4ACgrEGUkYAJUCAAAA.Revelaen:BAAANQAECgcIDwABNQAFFAUICgAOAGcNAA==.',
Ri='Rick:BAACNQAFFH8NAAIOAAMKwxybDQDCAAAOAAMKwxybDQDCAAA1AAQKfzIAAw4ACgr8IqkEAPcCAA4ACgq/IqkEAPcCAA0ABApOIHIDAf4AAAAA.',
Rm='Rmagep:BAAANQAECgUICwAAAA==.',
Ro='Roadhouse:BAAANQAECgQIBwAAAA==.Roman:BAAANQAECgYIDAABNQAFFAUICAAhAMsfAA==.Roshango:BAAANQADCgYIBgAAAA==.Rosinator:BAAANQAECggIAQAAAA==.Rotgus:BAAANQAECgEIAQAAAA==.Rouk:BAABNQAECn8UAAIUAAcKvR6bVQDIAQAUAAcKvR6bVQDIAQABNQAECgoKJQADAKcmAA==.Rowgar:BAABNQAECn8jAAIQAAoKmxosHADxAQAQAAoKmxosHADxAQAAAA==.',
Ru='Rubenslik:BAABNQAECn80AAICAAoKqSEQLAA3AwACAAoKqSEQLAA3AwAAAA==.',
Sa='Saelyn:BAAANQADCggIBgAAAA==.Saephora:BAABNQAECn8eAAIlAAcKuwanHgD2AAAlAAcKuwanHgD2AAAAAA==.Saggypants:BAABNQAECn8fAAIBAAoKXBS+LwBjAgABAAoKXBS+LwBjAgAAAA==.Sakurai:BAAANQAECgEIAQABNQAECgIIAgAEAAAAAA==.Salamander:BAAANQAECgUJCgAAAA==.Salazzle:BAAANQADCgQIBAAAAA==.Sammel:BAAANQAECgUIEAAAAA==.Sanari:BAAANQADCgUIBwABNQAECgoKJwAJAHgYAA==.Sandilla:BAAANQADCggICAABNQAECgoKIQAJAEMkAA==.Sangwine:BAAANQADCgYIBgAAAA==.Sapphica:BAAANQAECgEIAgAAAA==.Sargus:BAAANQADCgUIBQAAAA==.Sathreina:BAABNQAECn83AAIDAAoKHBjYXADhAQADAAoKHBjYXADhAQAAAA==.Sativva:BAAANQAECgIIAgABNQAECgoKIQAJAEMkAA==.',
Sc='Scaries:BAABNQAECn8gAAIWAAoK4RlTBwDIAgAWAAoK4RlTBwDIAgAAAA==.Scootko:BAABNQAECn8fAAIDAAkKCiXsQQDPAgADAAkKCiXsQQDPAgAAAA==.Scuss:BAAANQADCggICAAAAA==.',
Se='Sego:BAAANQAECgUIBAAAAA==.Sekimaru:BAAANQAECgIIAgAAAA==.Senli:BAAANQAECgEIAQAAAA==.Severson:BAABNQAECn8bAAIOAAgKXAxfNACrAQAOAAgKXAxfNACrAQAAAA==.Sey:BAAANQADCgYIBgAAAA==.',
Sh='Shadowapoke:BAAANQADCgUIBQABNQAECgEIAQAEAAAAAA==.Shadowisbad:BAABNQAECn8qAAIGAAoKehhYHABiAgAGAAoKehhYHABiAgAAAA==.Shadvoker:BAABNQAECn8iAAMhAAgKzx2iDgC/AgAhAAgKzx2iDgC/AgASAAIK1BHUMwBvAAAAAA==.Shamaneggs:BAABNQAECn8uAAMRAAoKKSAHCwBRAwARAAoKKSAHCwBRAwAjAAMKshBOKQDRAAAAAA==.Shamatroxx:BAABNQAECn8pAAIjAAkKTBzVDgDtAQAjAAkKTBzVDgDtAQABNQAFFAcIEgAXADUXAA==.Shamberry:BAABNQAECn8aAAIjAAgKBRWDEQBRAgAjAAgKBRWDEQBRAgAAAA==.Shambles:BAAANQADCgYICQAAAA==.Sheilla:BAABNQAECn8YAAMQAAgKbBLadQAgAQAQAAcKnBTadQAgAQAZAAUKtwcJlADbAAAAAA==.Shieldslamer:BAAANQAECggICwAAAA==.Shieldwalle:BAABNQAECn8XAAIfAAkK8x0KCwCMAgAfAAkK8x0KCwCMAgAAAA==.Shinobukocho:BAAANQADCgQJBAAAAA==.Shlock:BAAANQAECgQIBAAAAA==.Shotigolova:BAAANQADCgcIEgAAAA==.',
Si='Sidesalad:BAAANQAECgQIBgAAAA==.Sidric:BAABNQAECn89AAIBAAoKQxGZGwD1AQABAAoKQxGZGwD1AQAAAA==.Siena:BAAANQADCgYIBgAAAA==.Silre:BAABNQAECn8YAAMgAAYKOw2LEQAzAQAgAAYKkQyLEQAzAQAcAAUKWweNGQB2AAAAAA==.Sim:BAABNQAECn8mAAIUAAkKLiSvFQBjAwAUAAkKLiSvFQBjAwABNQAECgoKIQAJAEMkAA==.Singularité:BAAANQAECggIEgABNQAFFAcICwAaACAPAA==.Sipplex:BAAANQAECgYIDAAAAA==.',
Sl='Slander:BAAANQAECgQJBAABNQAECgUJCgAEAAAAAA==.Slanderous:BAAANQADCgEJAQABNQAECgUJCgAEAAAAAA==.Slappee:BAAANQAECgYIBwAAAA==.Slappeey:BAAANQAECgUICAABNQAECgYIBwAEAAAAAA==.',
Sn='Snuudle:BAAANQAECgcIDwABNQAECgkJHAAdABwXAA==.',
So='Solokills:BAAANQADCgMIAwABNQAFFAMIBQANAFgXAA==.Sophia:BAAANQAECgcIEgAAAA==.Soundtrack:BAAANQADCgYICQABNQAECgIIAgAEAAAAAA==.Soyshine:BAAANQADCgYIBgAAAA==.',
Sp='Spaceman:BAACNQAFFH8OAAIXAAUKWgRtBwDeAAAXAAUKWgRtBwDeAAA1AAQKfxkAAhcACgrbDy4pANUBABcACgrbDy4pANUBAAAA.',
Sq='Squab:BAABNQAECn8cAAIBAAkKaR6+GQD6AgABAAkKaR6+GQD6AgAAAA==.Squanchy:BAAANQADCgYJCAAAAA==.',
St='Stabbywixx:BAAANQAECgIIAgAAAA==.Starwnd:BAABNQAECn8UAAIdAAcKlheaggDfAQAdAAcKlheaggDfAQABNQAFFAYIDgApAMcOAA==.Sterìs:BAAANQAECgEIAQAAAA==.Stillcreepin:BAAANQAECgIIAwAAAA==.Stompy:BAAANQAECgQIBAABNQAFFAYIDAAGAKoLAA==.Storienn:BAAANQAECgcIEwAAAA==.Stormzpaly:BAAANQAECgYIEQAAAA==.',
Su='Suküna:BAAANQADCggIFwAAAA==.Sunbur:BAAANQADCgYICgAAAA==.Sunglo:BAAANQAECgUIBwAAAA==.Surch:BAAANQADCgEIAQAAAA==.',
Sw='Swaption:BAABNQAECn81AAIRAAoKDSNJCAB2AwARAAoKDSNJCAB2AwAAAA==.Sweetie:BAAANQADCgEIAQAAAA==.',
Sy='Syrelia:BAABNQAECn9IAAICAAoKchhMNgBKAgACAAoKchhMNgBKAgAAAA==.',
['Só']='Sónny:BAAANQABCgIIAgAAAA==.',
Ta='Tablescraps:BAAANQADCgUIBQABNQADCgIIAgAEAAAAAA==.Talonstrykz:BAAANQADCgUIBQAAAA==.Tassarosea:BAAANQAECgcIBwABNQAFFAQIEAASADQkAA==.Tauloe:BAABNQAECn8VAAIJAAYK7AaCfwDYAAAJAAYK7AaCfwDYAAAAAA==.Tayna:BAABNQAECn8YAAIGAAgKAAykIQA9AQAGAAgKAAykIQA9AQAAAA==.',
Te='Tenderoni:BAAANQADCgEIAQAAAA==.',
Th='Thatsmyhorse:BAAANQADCgIIAgAAAA==.Thatsograven:BAAANQADCgQIBAABNQAFFAgIIAABAOAfAA==.Thomosaurus:BAAANQADCggIDAAAAA==.Thraly:BAAANQADCgYIBwAAAA==.Thunk:BAABNQAECn8hAAIJAAoKQyTACwCJAwAJAAoKQyTACwCJAwAAAA==.',
Ti='Timdawg:BAABNQAECn8XAAMlAAkKLCFXDAD2AQAlAAcK0SNXDAD2AQACAAUKahLJQAEhAQABNQAFFAgIIQAdAEEZAA==.Timmolate:BAACNQAFFH8hAAQdAAgKQRn9BgD6AQAdAAYKoRr9BgD6AQAcAAIKwRfpCgCjAAAgAAIKRAkmDQBLAAA1AAQKfzgABB0ACgrLJSIRAMoCAB0ACQo1JCIRAMoCABwACAoMGQULAEcCACAAAQoqJiQaAG8AAAAA.Tiramisubear:BAAANQAECggICgAAAA==.Tircaps:BAAANQADCgUIBQAAAA==.',
To='Tomcruise:BAAANQAECgIIAgAAAA==.Tomotostein:BAACNQAFFH8LAAIDAAUK5gzZEwDGAAADAAUK5gzZEwDGAAA1AAQKfzAAAgMACgoCG+9DACsCAAMACgoCG+9DACsCAAAA.Tornado:BAAANQABCgQICQABNQADCgQIBAAEAAAAAA==.',
Tr='Trilla:BAAANQAECgcIDgAAAA==.Tristîtia:BAABNQAECn8ZAAMGAAkK/A4nJAAQAgAGAAkK/A4nJAAQAgAFAAIKCwki5gB1AAAAAA==.Trulu:BAAANQAECgEIAQAAAA==.',
Ts='Tsukikyo:BAAANQADCgQIBAAAAA==.Tsuma:BAAANQADCgUIBQAAAA==.Tsume:BAAANQAECgcIEgAAAA==.',
Tt='Ttomas:BAABNQAECn8VAAMOAAkKuh9oOwB2AQANAAYKbCI8mQDVAQAOAAcKlhRoOwB2AQAAAA==.',
Ty='Tyrinn:BAABNQAECn8lAAIQAAoKgxH8IADGAQAQAAoKgxH8IADGAQAAAA==.Tyv:BAABNQAECn8/AAICAAoKphGaUAD3AQACAAoKphGaUAD3AQAAAA==.',
Ul='Ulmerideavus:BAAANQADCgcIBwAAAA==.',
Up='Updatè:BAAANQAECgEIAQABNQAECgkJFgAGAIYgAA==.',
Ur='Urgent:BAAANQAECgIIAQAAAA==.',
Uz='Uzì:BAAANQADCgIIAgAAAA==.',
Va='Vainatetosix:BAAANQAECgUICQAAAA==.Vallodon:BAABNQAECn8kAAICAAkKHCISTgDlAgACAAkKHCISTgDlAgAAAA==.Vantablack:BAAANQABCgIIAgABNQADCgQIBAAEAAAAAA==.Vanwolfy:BAABNQAECn8dAAIfAAoK+hI9FQDUAQAfAAoK+hI9FQDUAQAAAA==.Vaylorian:BAABNQAECn8YAAQPAAYK8hFiJwABAQAPAAYK8hFiJwABAQAYAAIKJQoryQBZAAADAAIK+gU6hgFRAAAAAA==.',
Ve='Velorian:BAAANQADCgQIBwAAAA==.Velveeta:BAAANQAECgMIAwAAAA==.Veragon:BAAANQADCgcIBwAAAA==.',
Vf='Vfacer:BAAANQADCgEIAQAAAA==.',
Vi='Vikav:BAAANQAECgIIAgAAAA==.Vikimg:BAABNQAECn8bAAIFAAoKoBabVgAfAgAFAAoKoBabVgAfAgAAAA==.Violet:BAAANQADCgEIAQAAAA==.',
Vo='Voodoomike:BAAANQAECgQIBAAAAA==.Vortash:BAAANQADCgUIBwAAAA==.',
Vy='Vynle:BAAANQAECgEIAQAAAA==.',
Wa='Warheimer:BAABNQAECn8ZAAMZAAoKzg6LXwCRAQAZAAoKzg6LXwCRAQAQAAQKVgZpoQCUAAAAAA==.Warrgodx:BAABNQAECn9WAAMUAAoKbyTsDwCAAwAUAAoKbyTsDwCAAwAnAAEKygioMwA0AAABNQAFFAQIBQADAFMZAA==.',
Wh='Whoknows:BAAANQADCgIIAgAAAA==.',
Wo='Woogi:BAAANQADCgUIBQAAAA==.',
Wr='Wrongwookie:BAABNQAECn8uAAIJAAoKPBkpRwBaAgAJAAoKPBkpRwBaAgAAAA==.',
Ya='Yapper:BAAANQADCgMIAwAAAA==.',
Yo='Yolanda:BAAANQAECgIIAgAAAA==.Yoyohunty:BAAANQAECgYICwAAAA==.',
Yt='Ytix:BAAANQAECgEIAQAAAA==.',
Yu='Yumekoo:BAAANQAECgIIAgAAAA==.',
Za='Zabada:BAABNQAECn8VAAINAAYK3w26uQD7AAANAAYK3w26uQD7AAAAAA==.Zaldrea:BAAANQAECgcICAABNQAFFAYIDAAGAKoLAA==.Zandrea:BAAANQAECggIEQABNQAFFAYIDAAGAKoLAA==.Zariee:BAAANQABCgIIAwAAAA==.',
Ze='Zehz:BAABNQAECn8aAAIVAAkKZAFhkgByAAAVAAkKZAFhkgByAAAAAA==.Zemsen:BAABNQAECn8nAAICAAkKoh3yawCmAgACAAkKoh3yawCmAgAAAA==.Zentrea:BAAANQAECgQIBQABNQAFFAYIDAAGAKoLAA==.Zenyea:BAABNQAECn8iAAIRAAoKUhSoKgBMAgARAAoKUhSoKgBMAgABNQAFFAYIDAAGAKoLAA==.Zetta:BAACNQAFFH8MAAIGAAYKqgswCQB0AQAGAAYKqgswCQB0AQA1AAQKfzIAAgYACgq7HrQKAIsCAAYACgq7HrQKAIsCAAAA.',
Zo='Zome:BAABNQAECn9MAAMkAAoKhhwRGgCIAgAkAAoKhhwRGgCIAgAaAAEKlAM4pgAwAAAAAA==.Zorojoro:BAAANQAECgYIDgAAAA==.',
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
