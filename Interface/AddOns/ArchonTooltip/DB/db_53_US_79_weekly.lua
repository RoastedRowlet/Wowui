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

local lookup = {'Priest-Holy','Paladin-Retribution','Hunter-BeastMastery','DemonHunter-Devourer','DemonHunter-Vengeance','Unknown-Unknown','Druid-Balance','Priest-Shadow','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Mage-Frost','DeathKnight-Unholy','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Monk-Mistweaver','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Warrior-Arms','Druid-Restoration','Warrior-Fury','DeathKnight-Blood','Evoker-Augmentation','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Frost','Druid-Guardian','Druid-Feral','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aaronius:BAABNQAECn8cAAIBAAcK8gGOwACqAAABAAcK8gGOwACqAAAAAA==.',
Ab='Abrahm:BAAANQABCgIIAgAAAA==.',
Ac='Acceptance:BAACNQAFFH8MAAICAAcKyxdTBgChAQACAAcKyxdTBgChAQA1AAQKfyEAAgIACgpZHyshANwCAAIACgpZHyshANwCAAAA.',
Ad='Adoe:BAABNQAECn8wAAIDAAkKUxpdWgAVAgADAAkKUxpdWgAVAgAAAA==.Adora:BAAANQAECgMJBQAAAA==.',
Ae='Aeveen:BAAANQAECgUIBQAAAA==.',
Ag='Agaliarept:BAAANQAECgMIAwAAAA==.Agathos:BAAANQAECgMIBwAAAA==.',
Ai='Aidenator:BAABNQAECn80AAMEAAoKQhtdEgA4AgAEAAoKQhtdEgA4AgAFAAUKSAODIgB1AAAAAA==.',
Al='Algebradaddy:BAAANQAECggICgABNQAECggIDgAGAAAAAA==.Aluni:BAAANQADCgEIAQAAAA==.',
Am='Ammastin:BAAANQABCgMIAwAAAA==.',
An='Andorix:BAAANQAECgQICQAAAA==.Andretta:BAAANQAECgMIAgAAAA==.Angelneko:BAABNQAECn8tAAIHAAkKswb8RgAHAQAHAAkKswb8RgAHAQAAAA==.',
Ar='Arinthian:BAAANQAECgQICAAAAA==.Artrian:BAABNQAECn8iAAMBAAgKAxduXQDJAQABAAgKAxduXQDJAQAIAAUKAwa4QACsAAAAAA==.',
At='Atthis:BAAANQADCgEIAQAAAA==.',
Au='Auroraa:BAABNQAECn8XAAIHAAcKsAhQWwC0AAAHAAcKsAhQWwC0AAAAAA==.Auyniko:BAAANQAECggIDwAAAA==.',
Av='Avalectra:BAAANQAECgEIAQAAAA==.',
Az='Azmodeaz:BAABNQAECn8sAAIJAAgK+Q647wCrAQAJAAgK+Q647wCrAQAAAA==.Azraely:BAAANQADCgcIBwAAAA==.Aztrik:BAABNQAECn8kAAQKAAgKdiIZWABOAgAKAAgKZSIZWABOAgALAAIKCSFzGACcAAAMAAIK8yOKIQBtAAAAAA==.',
Ba='Bajapanti:BAABNQAECn9HAAINAAoKXxTbEQAjAgANAAoKXxTbEQAjAgAAAA==.Ballyhøø:BAACNQAFFH8MAAIHAAUKDxB/EwDYAAAHAAUKDxB/EwDYAAA1AAQKfx4AAgcACgraFkwwAF8CAAcACgraFkwwAF8CAAAA.Banchory:BAAANQAECgUICAAAAA==.Bandaron:BAAANQAECgQIBAAAAA==.Barload:BAAANQABCggIEAAAAA==.Baxstab:BAABNQAECn9AAAMOAAoKyxrWCABZAgAOAAoKyxrWCABZAgAPAAIKMgo+SQBwAAAAAA==.',
Be='Beelzebrad:BAAANQAECgQIBwAAAA==.Belladeon:BAABNQAECn8mAAMQAAoKchWxCwAEAgAQAAgKuxaxCwAEAgAJAAgK0Qef8wCkAQAAAA==.Betrubt:BAAANQAECgcIDwABNQAECgkJFgARAFgVAA==.',
Bg='Bgeefiddy:BAAANQAECgMIAwAAAA==.',
Bh='Bhagee:BAAANQADCgUICgAAAA==.',
Bi='Bivouac:BAAANQAECgEIAQAAAA==.',
Bl='Blackpatch:BAABNQAECn9PAAMSAAoKDBvwDwBdAgASAAoKDBvwDwBdAgATAAQKXANuJwCNAAAAAA==.Blacksheep:BAAANQADCggIAQAAAA==.Blaqkid:BAAANQADCgYIBgAAAA==.Blaqsun:BAABNQAECn86AAIUAAoKWRQoNAAFAgAUAAoKWRQoNAAFAgAAAA==.Blargg:BAAANQAECgUIBwAAAA==.Bleeda:BAAANQADCggIAQAAAA==.Blightmaker:BAAANQAECgcIEAAAAA==.Bloomhammer:BAAANQAECgEIAQAAAA==.Blooming:BAABNQAECn86AAIVAAoKIB9FCwByAwAVAAoKIB9FCwByAwAAAA==.',
Bo='Booneboy:BAABNQAECn8fAAQCAAYKwhyTqwDIAQACAAYKwhyTqwDIAQAVAAEK/hMB8gA4AAAWAAEKjgmfawApAAAAAA==.Botemedel:BAABNQAECn8wAAMWAAkKpBjoFwC6AQACAAkKiQ/ZdwDeAQAWAAkKmhjoFwC6AQABNQAFFAYIDQAXAOcFAA==.Bowtox:BAAANQADCggICgAAAA==.',
Br='Brennor:BAABNQAECn89AAICAAoKXApAnwCPAQACAAoKXApAnwCPAQAAAA==.Brewslunt:BAABNQAECn8fAAIYAAoKzhoWDwCPAgAYAAoKzhoWDwCPAgABNQAFFAgIGQAZAAcaAA==.Bronamaly:BAAANQADCgYICAAAAA==.',
Ca='Cabbagehunt:BAAANQADCggIFQAAAA==.Caeden:BAABNQAECn87AAIZAAoKgxEvRwD3AQAZAAoKgxEvRwD3AQAAAA==.Cairyan:BAABNQAECn8oAAIFAAoKwRaQCABsAgAFAAoKwRaQCABsAgAAAA==.Caiya:BAAANQADCggIFgABNQAECgoKSAAOAH4jAA==.Carvil:BAAANQAECgYIBgAAAA==.Castalia:BAABNQAECn8fAAIIAAYKdwzGLQAZAQAIAAYKdwzGLQAZAQAAAA==.Cattilina:BAAANQADCggIEAAAAA==.',
Ce='Celenara:BAACNQAFFH8VAAIJAAYKKRIuGQAqAQAJAAYKKRIuGQAqAQA1AAQKfzEAAwkACgpLHhphALwCAAkACgpLHhphALwCABAAAgohC584AFsAAAAA.Celendil:BAAANQADCgUIBQABNQAFFAYIFQAJACkSAA==.Celinne:BAAANQAECgUICQAAAA==.Celithe:BAAANQAECgUICQAAAA==.',
Ch='Charlereaux:BAAANQAECgMIBwAAAA==.Charmcaster:BAABNQAECn8pAAIJAAoK6hemTwAhAgAJAAoK6hemTwAhAgAAAA==.Charmstrike:BAAANQAECgcIDgAAAA==.Chedissa:BAAANQADCgQIBAABNQADCgYICgAGAAAAAA==.Cheezle:BAAANQAECgYIAwAAAA==.Chleo:BAABNQAECn8uAAIBAAgK5AriewBmAQABAAgK5AriewBmAQAAAA==.Choco:BAACNQAFFH8eAAIaAAgKNR0mAgCbAgAaAAgKNR0mAgCbAgA1AAQKfzAAAxoACgpHICMJABEDABoACgpHICMJABEDABsAAgpUF9gyAHkAAAAA.Chocolat:BAAANQADCggICAABNQAFFAgIHgAaADUdAA==.Chocolight:BAAANQAECgIIAgABNQAFFAgIHgAaADUdAA==.Chudfox:BAAANQADCgEJAQAAAA==.',
Ci='Ciney:BAAANQAECgcIBwAAAA==.',
Co='Coggler:BAABNQAECn8jAAMcAAgK/xjNEACqAQAcAAgK/xjNEACqAQAdAAUKtgwB6wAOAQAAAA==.Conqueror:BAAANQAECgYIBwABNQAECgoKLwAeAEEZAA==.Corcia:BAAANQAECgMIAwAAAA==.',
Cr='Creatlach:BAAANQAECgIIAgABNQAFFAgIGQAZAAcaAA==.Criofan:BAAANQADCgYIBgAAAA==.Crotchpox:BAAANQADCgQIBAAAAA==.Crualti:BAABNQAECn8aAAMfAAgKnweVIAC2AAAdAAgKXgWi7wABAQAfAAQKegmVIAC2AAAAAA==.',
Cu='Cuppajoe:BAAANQADCgMIAwAAAA==.Cupper:BAAANQABCgcJCQABNQAECgYIGwACAGkHAA==.Curmudge:BAABNQAECn9WAAIeAAoKoxwtDwDVAgAeAAoKoxwtDwDVAgAAAA==.',
Cy='Cyonissian:BAAANQADCgEIAQAAAA==.',
Da='Dabtoomuch:BAAANQABCgIIAgAAAA==.Daimhin:BAAANQADCgcIBwAAAA==.Dalectra:BAAANQAECgQICAAAAA==.Darachane:BAAANQAECgUIEQAAAA==.Darkpriest:BAAANQAECgIIAgAAAA==.Darovan:BAAANQADCggJEAABNQAECgoKLwAgAA0gAA==.Darthnater:BAABNQAECn8dAAIRAAkKnB2JDQCiAgARAAkKnB2JDQCiAgAAAA==.Dauglow:BAABNQAECn8/AAMDAAoKYREjWQAYAgADAAoKYREjWQAYAgANAAEKhwnmhQA4AAAAAA==.',
De='Deathball:BAAANQAECgEIAQAAAA==.Deathstars:BAAANQADCggIFQAAAA==.Deboss:BAAANQAECggIDgAAAA==.Dellianne:BAAANQABCgEIAQAAAA==.Delritha:BAAANQAECgUICAAAAA==.Deltithrax:BAABNQAECn8tAAMhAAkKFg0ADwBSAQAhAAgKzA0ADwBSAQAbAAcKaA29FADqAAAAAA==.Demonagent:BAABNQAECn8mAAMFAAgKlBM+DwBTAQAFAAgKlBM+DwBTAQAiAAMKtw5XbwC8AAAAAA==.Desdh:BAACNQAFFH8MAAMiAAQKXBXqEQDWAAAiAAMKXBXqEQDWAAAEAAIK4gdHEgBBAAA1AAQKfy8AAyIACgrMIccaAMQCACIACgoSIccaAMQCAAQAAwp8Hro3AN8AAAAA.Devious:BAAANQAECggIEAABNQAECgoKOgAVACAfAA==.',
Di='Dinö:BAAANQAECgMJBAABNQAECgoKMgADAAcXAA==.',
Dm='Dmnslyer:BAAANQADCggIDQAAAA==.',
Do='Docspades:BAABNQAECn8nAAMBAAkKShKKXgDFAQABAAkKShKKXgDFAQAjAAEKXQcDHAArAAAAAA==.Dohane:BAAANQADCgQIBAABNQAECggIFgAEADQQAA==.Domrogue:BAABNQAECn8gAAMPAAkKfBifJQBuAgAPAAkKfBifJQBuAgAOAAUKcAUrNAC7AAAAAA==.Dornoch:BAAANQAECgMIBwAAAA==.Douglane:BAAANQABCgYIBgAAAA==.',
Dr='Dramine:BAAANQADCgQIBwAAAA==.Draone:BAABNQAECn8qAAIJAAkK1AqsmQBxAQAJAAkK1AqsmQBxAQAAAA==.Dreabolic:BAAANQADCgYICwAAAA==.Dreamss:BAABNQAECn8xAAMiAAoKyhTBLwApAgAiAAoKyhTBLwApAgAEAAgKvAY4OQB7AQAAAA==.Drhkillinger:BAAANQAECgYIBwABNQAECggIJgAFAJQTAA==.Drspades:BAAANQAECgEIAQAAAA==.',
Du='Dugosh:BAAANQADCggIDQAAAA==.Duzz:BAAANQABCggIFwAAAA==.',
['Dé']='Démetal:BAAANQADCggIDgAAAA==.',
Ei='Einherja:BAABNQAECn8jAAQgAAoKcBspNgBuAQAgAAUKYCApNgBuAQARAAYKexj4aQBqAQAkAAcKZRG3XAA2AQAAAA==.',
El='Elessaria:BAABNQAECn8fAAIeAAYKoAlkRQDtAAAeAAYKoAlkRQDtAAAAAA==.Elfatheàrt:BAAANQAECgMIBwAAAA==.Elidrus:BAAANQAECgIIAgABNQAECgoKGQAKADwEAA==.',
En='Enodlo:BAAANQADCgUIBQAAAA==.',
Er='Erora:BAABNQAECn8nAAIIAAoKShYGGgB9AgAIAAoKShYGGgB9AgAAAA==.',
Es='Estherras:BAABNQAECn8tAAIDAAgK1xUIZAD9AQADAAgK1xUIZAD9AQAAAA==.',
Fe='Feardotrun:BAABNQAECn8nAAMLAAkK+w5ZOADfAAAKAAkK+w5jiABNAQALAAQKewtZOADfAAAAAA==.Felicious:BAAANQAECgMIBwAAAA==.',
Fi='Filleesclave:BAAANQADCggICAAAAA==.Finally:BAAANQAECgMIBwAAAA==.Firemage:BAACNQAFFH8HAAMKAAQKkRUwIwCjAAAKAAMKJRgwIwCjAAALAAEKahBpEABNAAA1AAQKfzMAAwoACgo5JFYnAOcCAAoACQo6JFYnAOcCAAsABAq5IgAgAHABAAAA.Fizzanelf:BAAANQAECgMICAAAAA==.',
Fl='Flaildelyn:BAAANQAECgEIAQAAAA==.Flokíe:BAAANQADCggICAAAAA==.',
Fo='Fortytwo:BAAANQAECggIEAAAAA==.',
Fr='Freyá:BAAANQAECgEIAgAAAA==.Frostbight:BAABNQAECn8xAAIJAAkKuRgeZwDmAQAJAAkKuRgeZwDmAQAAAA==.Frostied:BAABNQAECn8jAAMgAAoKaCE/EgCEAgAgAAoK7yA/EgCEAgAkAAUKrBoxTQCCAQAAAA==.Frostyduggo:BAABNQAECn82AAIQAAoKjwvMDwCSAQAQAAoKjwvMDwCSAQAAAA==.',
Fu='Futnuraz:BAAANQAECgMIBwAAAA==.',
Fy='Fyrakkobama:BAAANQAECgYIBgABNQAECggIDgAGAAAAAA==.Fyriat:BAABNQAECn8tAAIQAAgKCA7rEACAAQAQAAgKCA7rEACAAQAAAA==.',
Ga='Galathel:BAABNQAECn81AAMWAAoKKBU/HwB0AQAWAAkKgxQ/HwB0AQAVAAEK+gtl9wA0AAABNQAECgoKTAAZAJYdAA==.Gavreel:BAAANQAECgYICQAAAA==.Gazardiel:BAABNQAECn81AAICAAkKPAgdwgBPAQACAAkKPAgdwgBPAQAAAA==.',
Ge='Gelinia:BAABNQAECn82AAMIAAoKbAx3GwC8AQAIAAoKbAx3GwC8AQAjAAEKUwFvMwAYAAAAAA==.Gerrald:BAAANQAECgcICQABNQAECgoKMgADAAcXAA==.Getafix:BAABNQAECn8eAAMHAAkKrQ7nMQB7AQAHAAkKKA7nMQB7AQAlAAEKVBV1aQA/AAABNQAECgoKTAAZAJYdAA==.',
Gh='Ghozthappenz:BAAANQAECgMIBQABNQAECgoKOQAgANkTAA==.Ghrass:BAAANQADCgQIBQAAAA==.',
Gi='Girthquakes:BAAANQAECgIIAQAAAA==.',
Gl='Glorbo:BAABNQAECn8tAAQVAAgK/R5LJACjAgAVAAgK/R5LJACjAgACAAUKAA/B+wDwAAAWAAEK4BbYagA9AAAAAA==.',
Go='Goliath:BAABNQAECn8XAAMZAAYKtRVTjQBoAQAZAAYKtRVTjQBoAQAUAAUKWBDftAAoAQAAAA==.',
Gr='Graythers:BAAANQADCggIDQAAAA==.Gregoron:BAAANQABCgYIBgAAAA==.Grimfelborn:BAACNQAFFH8YAAQLAAYKAxEiCACAAAAKAAQKGA9HGQDhAAALAAIKNQ0iCACAAAAMAAIKpwnRGABJAAA1AAQKfzUABAoACgocG3FNAGwCAAoACgocG3FNAGwCAAsAAgr9FyoYAJ4AAAwAAgqDDzAnAE8AAAAA.Grimosh:BAAANQAECgEIAQAAAA==.Grondosh:BAAANQAECgYIDwAAAA==.Gryphindor:BAABNQAECn8UAAIDAAcKwAkbugCPAQADAAcKwAkbugCPAQAAAA==.',
Ha='Hahwe:BAAANQADCgIIAgABNQAECgoKGQAKADwEAA==.Haljo:BAAANQADCgQJBAAAAA==.Hanoverfiste:BAABNQAECn8bAAICAAYKaQdIAAHpAAACAAYKaQdIAAHpAAAAAA==.Hapsburg:BAABNQAECn8+AAMYAAoK1A8FEwDXAQAYAAoK1A8FEwDXAQASAAgK5wmXMAAYAQAAAA==.Harahel:BAAANQAECgUICwAAAA==.Havince:BAABNQAECn81AAIgAAoKOCPrCQDwAgAgAAoKOCPrCQDwAgAAAA==.Hawktuah:BAAANQAECgEIAgAAAA==.Haylee:BAAANQABCgIIAgAAAA==.',
He='Helbreder:BAAANQADCgYIBgAAAA==.Helle:BAAANQAECgIIAgAAAA==.Hercbooyy:BAAANQADCgQIBAABNQAECggIKAAVAGQjAA==.Hercboyy:BAABNQAECn8oAAMVAAgKZCN2GgANAwAVAAcKgSZ2GgANAwAWAAUKORbWOwC9AAAAAA==.',
Hi='Higgs:BAAANQADCggICQABNQAECgoKRQAVALEeAA==.Higgspally:BAABNQAECn9FAAMVAAoKsR4qDQBcAwAVAAoKsR4qDQBcAwACAAMKIw+rSwGAAAAAAA==.Hikaru:BAAANQAECgEIAQAAAA==.',
Ho='Holyball:BAABNQAECn9MAAICAAoKrx0GLACxAgACAAoKrx0GLACxAgAAAA==.Holytalon:BAAANQADCgIIAgAAAA==.Hotak:BAAANQABCgYIBAAAAA==.',
Hu='Hughjahsol:BAAANQADCgIIAgAAAA==.Hukaru:BAAANQABCgIIAgABNQAECgoKNQAgADgjAA==.Huuken:BAAANQAECgQIBAAAAA==.Huulkster:BAAANQADCgQIBAAAAA==.',
Hy='Hydra:BAAANQAECgEJAQAAAA==.',
Il='Ilovehunter:BAAANQADCggICAAAAA==.Ilyndra:BAABNQAECn8tAAIcAAkKKSM7BwCCAgAcAAkKKSM7BwCCAgAAAA==.',
In='Infernella:BAAANQADCgMIAwAAAA==.',
Ir='Ironskin:BAAANQAECgUICwAAAA==.',
Is='Iselilja:BAABNQAECn8lAAMdAAkK8AygaADHAQAdAAkK3AygaADHAQAcAAQK6AhhMgCkAAAAAA==.',
It='Ithea:BAABNQAECn89AAIJAAoKPyCsIQC5AgAJAAoKPyCsIQC5AgAAAA==.',
Ja='Jackshots:BAAANQADCgIIAgAAAA==.Jaeson:BAEBNQAECn8eAAMKAAkKeQ75bQCPAQAKAAkKeQ75bQCPAQAMAAEKBwa4MwAsAAAAAA==.Jakaro:BAACNQAFFH8MAAMLAAYK6wliEgCHAAAKAAQKNQ16JQCbAAALAAIK/ARiEgCHAAA1AAQKfycAAwsACQpHFxcrACUBAAoABwpJGRFzAIIBAAsABQovERcrACUBAAAA.Javoren:BAAANQADCgcIBwABNQAECgUIBQAGAAAAAA==.',
Je='Jeefgpt:BAAANQAECgEIAQABNQAECggIDgAGAAAAAA==.Jeefrenzy:BAAANQAECggIDgAAAA==.Jeefwrld:BAAANQAECgYICQAAAA==.Jeffers:BAAANQAECgEIAgABNQAECggIDgAGAAAAAA==.Jeffha:BAAANQADCggICAAAAA==.',
Ji='Jiinx:BAABNQAECn8tAAMDAAkKuhVjegDHAQADAAkKuhVjegDHAQANAAUKrwtMTQD8AAAAAA==.',
Jo='Joap:BAAANQAECgYIBgAAAA==.Joejr:BAABNQAECn83AAMIAAoKsxQUFQAOAgAIAAoKsxQUFQAOAgABAAgKhhT9bQDUAQAAAA==.Jonald:BAABNQAECn8cAAIEAAoK9gt4MwCmAQAEAAoK9gt4MwCmAQAAAA==.',
Jt='Jtizlfrizl:BAABNQAECn8mAAIOAAcKoBDSHAA/AQAOAAcKoBDSHAA/AQAAAA==.',
Ju='Judge:BAAANQADCggIEQABNQAECgoKOgAVACAfAA==.Juniperz:BAABNQAECn85AAIgAAoK2RPgJQDNAQAgAAoK2RPgJQDNAQAAAA==.',
Ka='Kaaydenn:BAABNQAECn8tAAQVAAoKWBwpFwD+AgAVAAkKRh0pFwD+AgACAAEKAAC5lAE/AAAWAAEKAABYdwAlAAAAAA==.Kaghro:BAAANQADCgcICAAAAA==.Kalaziel:BAABNQAECn8oAAIUAAoKHghRlAByAQAUAAoKHghRlAByAQAAAA==.Kalimotxo:BAABNQAECn8gAAIiAAoKnBwYFgBqAgAiAAoKnBwYFgBqAgAAAA==.Kamus:BAAANQADCgcIDAAAAA==.Karawyn:BAAANQAECgEIAgABNQADCgQICAAGAAAAAA==.Karelix:BAAANQAECgcIDAAAAA==.Katrichi:BAAANQAECgMIAwAAAA==.Katrishy:BAACNQAFFH8aAAMIAAYK2RYPBgBaAQAIAAYK2RYPBgBaAQABAAEKBgNIOQA/AAA1AAQKfzUAAggACgruHfQSANMCAAgACgruHfQSANMCAAAA.Kayde:BAAANQAECgQICQAAAA==.',
Ke='Keedrid:BAABNQAECn89AAIRAAoKoCBvDQCjAgARAAoKoCBvDQCjAgAAAA==.Kelaeno:BAABNQAECn85AAIUAAoKKw5jSQCwAQAUAAoKKw5jSQCwAQAAAA==.Kemics:BAAANQAECgMIAwAAAA==.Kev:BAACNQAFFH8OAAIVAAMKeRsbFgD/AAAVAAMKeRsbFgD/AAA1AAQKfzQAAhUACgryI7IEAKsDABUACgryI7IEAKsDAAAA.',
Ki='Kirima:BAAANQADCggICAAAAA==.Kirmit:BAAANQAECgQIBAAAAA==.',
Kl='Klevege:BAAANQADCgUIBQAAAA==.',
Kn='Knoll:BAAANQAECgIIBAAAAA==.',
Kr='Kreeona:BAABNQAECn9MAAIZAAoKlh39HQDLAgAZAAoKlh39HQDLAgAAAA==.Kruàlty:BAABNQAECn8dAAMmAAgKXhZvDQBEAgAmAAgKXhZvDQBEAgAHAAMKewgckgCPAAAAAA==.',
Ky='Kyfert:BAAANQAECgYICwAAAA==.',
La='Laird:BAAANQAECgMIAwAAAA==.',
Le='Legreecast:BAAANQAECgMIBwAAAA==.',
Li='Liare:BAACNQAFFH8fAAQMAAcK5RvmAwCyAAAKAAQKxBniGQAnAQAMAAMK5x7mAwCyAAALAAIKsSBECACwAAA1AAQKfzAABAoACgpqJbgKAHcDAAoACgpqJbgKAHcDAAsABgoxHxQXALQBAAwAAwr8InYXANQAAAAA.Liasong:BAAANQAECggIEAAAAA==.Litheliice:BAABNQAECn88AAIBAAoKeBULUwDuAQABAAoKeBULUwDuAQAAAA==.',
Lo='Lodur:BAABNQAECn8rAAIZAAgKdRDdWACxAQAZAAgKdRDdWACxAQAAAA==.Lonen:BAABNQAECn8iAAIlAAgKahe7FwDOAQAlAAgKahe7FwDOAQAAAA==.Losat:BAABNQAECn9KAAIcAAoKFgv/FABxAQAcAAoKFgv/FABxAQAAAA==.',
Lu='Luckx:BAAANQABCggIHwAAAA==.Lukeluke:BAAANQADCgQIBwAAAA==.Luthian:BAAANQAECgQIBQAAAA==.',
Ly='Lyn:BAAANQAECgIIAgAAAA==.',
['Lî']='Lîîght:BAAANQADCggIHgAAAA==.',
Ma='Mac:BAABNQAECn9LAAMmAAoKVBjmCQBCAgAmAAoKVBjmCQBCAgAHAAkKmg0DNQBnAQAAAA==.Machiato:BAAANQAECgMIBwAAAA==.Mackkie:BAABNQAECn8fAAMYAAgKhBAnJQBSAQAYAAgKhBAnJQBSAQASAAYKZQVZSADeAAAAAA==.Madonkadonk:BAABNQAECn86AAIbAAoKZwivDQBwAQAbAAoKZwivDQBwAQAAAA==.Maedai:BAAANQAECgUIDgAAAA==.Maeli:BAAANQAECgEIAQAAAA==.Magladroth:BAAANQABCgQJBAAAAA==.Maldive:BAABNQAECn8/AAQMAAoK6Q82CwCTAQAKAAoKDgwVZgCkAQAMAAkKNhA2CwCTAQALAAMKnwsMTgCVAAAAAA==.Maligasia:BAAANQADCgIIAwAAAA==.Mallicia:BAABNQAECn9FAAMBAAoK9SIpDwBMAwABAAoK9SIpDwBMAwAIAAgKDQrrKAA9AQAAAA==.Mallika:BAAANQAECgIIAQABNQAECgoKRQABAPUiAA==.Mallistra:BAABNQAECn8lAAIYAAoKmhSTFwAEAgAYAAoKmhSTFwAEAgABNQAECgoKRQABAPUiAA==.Mallwizard:BAAANQAECgUJCgAAAA==.Mandible:BAAANQABCgIIAgAAAA==.Marcille:BAAANQAECgQIBAAAAA==.Martris:BAABNQAECn8eAAICAAgKAgWqDgHTAAACAAgKAgWqDgHTAAAAAA==.Maryjane:BAAANQAECgMJAwAAAA==.Mashma:BAAANQADCggICAAAAA==.Massoflice:BAAANQAECgYIDwAAAA==.Mawkt:BAAANQADCggIAQAAAA==.Maxblaide:BAAANQAECgYICwAAAA==.',
Me='Melovania:BAAANQADCgIIAgAAAA==.',
Mi='Miami:BAAANQAECgMIBAABNQAFFAcIGAAbAHwaAA==.Milah:BAAANQABCgIIAgAAAA==.Missile:BAAANQAECgQICAABNQAECgcIGgAHAGEgAA==.Misstangy:BAAANQADCgcIFwAAAA==.',
Mo='Moct:BAABNQAECn9NAAIWAAoK6yJcBAAiAwAWAAoK6yJcBAAiAwAAAA==.Mocton:BAAANQADCgEIAQAAAA==.Monikal:BAAANQAECgMIAgAAAA==.',
Mu='Muradox:BAAANQADCgcIBwABNQAECgoKJwAIAEoWAA==.Musashi:BAABNQAECn8/AAIDAAoKjyXXBAC+AwADAAoKjyXXBAC+AwABNQAECgkJLwADAO8mAA==.Muskeg:BAABNQAECn8tAAIgAAkKzhDUQwAuAQAgAAkKzhDUQwAuAQAAAA==.Mustardhunt:BAAANQADCgYICgAAAA==.',
['Mü']='Münchkiné:BAAANQABCggIFwAAAA==.',
Na='Namanari:BAAANQABCgIJAgAAAA==.Naris:BAABNQAECn8ZAAIKAAoKPARZrgD3AAAKAAoKPARZrgD3AAAAAA==.',
Ne='Necrochade:BAAANQAECgEIAQAAAA==.Neptune:BAABNQAECn8wAAIJAAoKrhiiXwDAAgAJAAoKrhiiXwDAAgAAAA==.',
Ni='Nikra:BAAANQAECgQICAAAAA==.Nishal:BAAANQADCggIGwAAAA==.',
Ny='Nyxaries:BAAANQAECgYIDgABNQAECgcIEAAGAAAAAA==.',
['Né']='Néwby:BAABNQAECn8+AAMlAAoKcR/rBwADAwAlAAoK3R7rBwADAwAmAAkKoxMWEgCmAQAAAA==.',
Oa='Oatmealgobln:BAAANQAECgQIBAAAAA==.',
Op='Opalynn:BAAANQAECgEIAQAAAA==.Ophirra:BAAANQABCgYIDgAAAA==.',
Oz='Ozempic:BAAANQAECgQIBAABNQAFFAgIHgAaADUdAA==.',
Pa='Pablo:BAABNQAECn8mAAICAAoKcBkPZgBpAgACAAoKcBkPZgBpAgAAAA==.Pannacea:BAAANQAECggIDwABNQAECgoKTAAZAJYdAA==.Patriot:BAAANQAECgIIAQAAAA==.Pawinurbutt:BAAANQADCgQIBAAAAA==.',
Pe='Peppert:BAAANQAECgcICwAAAA==.',
Ph='Phane:BAAANQAECgQIBwAAAA==.',
Po='Pocketheals:BAAANQAECgMIAwAAAA==.Poon:BAAANQAECgQICAAAAA==.',
Pr='Pretzelz:BAAANQADCgcICQAAAA==.',
Pu='Puffer:BAABNQAECn8jAAIQAAoK+AiBEQB2AQAQAAoK+AiBEQB2AQAAAA==.',
Px='Pxry:BAAANQAECgQIBAAAAA==.',
Py='Pyrophoric:BAAANQAECgMIBAAAAA==.Pyrrhus:BAAANQAECgQIBAAAAA==.',
Qu='Quam:BAAANQABCggIFgAAAA==.',
Ra='Rabone:BAAANQADCgIJAgAAAA==.Raevyn:BAAANQADCgYIBgAAAA==.Raito:BAABNQAECn8sAAICAAoKvgfRsgBrAQACAAoKvgfRsgBrAQAAAA==.Rakshasa:BAABNQAECn9PAAQKAAoKTiJiDwBWAwAKAAoKTiJiDwBWAwALAAMK3w9VRwCqAAAMAAEKIBVaKwA/AAAAAA==.Rano:BAAANQAECgEIAQAAAA==.Rasetsungo:BAABNQAECn9GAAIBAAoKJhibLwCGAgABAAoKJhibLwCGAgAAAA==.Raura:BAAANQAECgMIBwAAAA==.Rayala:BAAANQAECggICQAAAA==.',
Re='Redblueblurr:BAABNQAECn8UAAICAAcKQQSQMAHRAAACAAcKQQSQMAHRAAAAAA==.Remi:BAABNQAECn8zAAMBAAoKChy4MQB7AgABAAoKChy4MQB7AgAIAAEK+wCSkQAYAAAAAA==.Rev:BAAANQADCgUIBQAAAA==.Reveillark:BAAANQAECgIIAgAAAA==.Revelaiden:BAAANQABCgIIAgABNQAECgoKNAAEAEIbAA==.',
Ri='Rise:BAAANQAECgcIDwAAAA==.',
Ro='Rolan:BAABNQAECn9EAAQkAAoK/CW3CwD9AgAkAAoK3yW3CwD9AgARAAgK2SPFHwDMAgAgAAQKwSVtPgBFAQAAAA==.Rosalian:BAABNQAECn8vAAIeAAoKyhTqGQBAAgAeAAoKyhTqGQBAAgAAAA==.Rotiko:BAABNQAECn8gAAIZAAoKAwWUegBDAQAZAAoKAwWUegBDAQAAAA==.Roweene:BAABNQAECn8tAAInAAkK/gQjBwDHAAAnAAkK/gQjBwDHAAAAAA==.',
['Rá']='Rágnar:BAABNQAECn8yAAMCAAoKkROykACqAQACAAoKkROykACqAQAWAAQK/wRrRQCRAAAAAA==.',
Sa='Sabiel:BAABNQAECn8wAAIHAAoKswfCOABQAQAHAAoKswfCOABQAQAAAA==.Sakuta:BAAANQADCgYIBgABNQAECgkJIQAZAOcdAA==.',
Se='Selryth:BAAANQADCgcIBwABNQAECggICwAGAAAAAA==.Serenatee:BAABNQAECn84AAIIAAoKmg0eGwDAAQAIAAoKmg0eGwDAAQAAAA==.',
Sh='Shaedai:BAABNQAECn8rAAMZAAoK8hCAQwAFAgAZAAoK8hCAQwAFAgAUAAEKPAJKUwEkAAAAAA==.Shagohod:BAAANQADCgQIBAAAAA==.Shakked:BAAANQAECgEIAwAAAA==.Shinanigans:BAAANQAECgUIBQAAAA==.Shoogen:BAAANQADCggICAAAAA==.',
Sk='Skotojar:BAAANQADCgUIBQAAAA==.',
Sn='Snortedgfuel:BAAANQAECgcIEgAAAA==.',
So='Sokroar:BAAANQAECgYICAABNQAFFAYIAQAGAAAAAA==.Solphera:BAAANQADCgUIDAAAAA==.Sonknight:BAABNQAECn8fAAMVAAgKJwZUkAAJAQAVAAgKJwZUkAAJAQACAAMKWAEjqQEqAAAAAA==.Sonwarlock:BAAANQADCgYIBwAAAA==.',
Sp='Speedshot:BAAANQADCgUIBgAAAA==.Spicy:BAAANQAECgUIBwAAAA==.Spitefulcrow:BAABNQAECn8tAAIoAAoKBQrUCABmAQAoAAoKBQrUCABmAQAAAA==.Spot:BAAANQAECgEIAQAAAA==.',
St='Stardstr:BAAANQADCgMIAwAAAA==.Stealinsoulz:BAAANQADCgYICgAAAA==.Stealsoul:BAAANQADCgIIAgABNQADCgYICgAGAAAAAA==.Sto:BAAANQAECgEIAgAAAA==.Stratof:BAAANQAECgcICwAAAA==.',
Su='Sufferding:BAABNQAECn8iAAIiAAkKeRETMQCPAQAiAAkKeRETMQCPAQAAAA==.Suria:BAABNQAECn9MAAIeAAoKjCDzBgBxAwAeAAoKjCDzBgBxAwAAAA==.',
Sw='Swytchblade:BAAANQADCggICQAAAA==.',
Sy='Syker:BAAANQADCgIIAgAAAA==.',
Ta='Tahrovin:BAABNQAECn8WAAIEAAgKNBDZNACcAQAEAAgKNBDZNACcAQAAAA==.Tavernn:BAAANQABCggILQAAAA==.Taytorchips:BAABNQAECn9GAAMCAAoKtwaOuwBbAQACAAoKtwaOuwBbAQAVAAUKBQL0EAFVAAAAAA==.',
Th='Thaendrin:BAAANQADCgYICQAAAA==.Thearcane:BAAANQADCgQICAAAAA==.Thedoc:BAAANQAECgUICQAAAA==.Theefjeef:BAAANQAECgYIBQABNQAECggIDgAGAAAAAA==.Thorloim:BAABNQAECn8qAAMZAAoKlx9ELwBkAgAZAAoKlx9ELwBkAgAXAAQKthARKQC7AAAAAA==.Thornx:BAAANQADCgEIAQAAAA==.Throwaway:BAAANQAECgcICAAAAA==.Thundercups:BAABNQAECn8zAAIXAAoKyBSbDgArAgAXAAoKyBSbDgArAgAAAA==.',
Ti='Tiajoe:BAABNQAECn8UAAQbAAoK9gzGCwCiAQAbAAoK9gzGCwCiAQAaAAcKlwNSJQDXAAAhAAEKAAAeIgAAAAAAAA==.Tigerstarr:BAABNQAECn8hAAMkAAoK3hGlNwD4AQAkAAoK3hGlNwD4AQARAAQKngmxowCzAAAAAA==.Tinyshieva:BAAANQADCgYICQAAAA==.Tizuki:BAAANQAECgQIBAAAAA==.',
To='Tonystandard:BAAANQAECgUICQABNQAFFAYICwAYAN8PAA==.',
Tr='Treborlock:BAABNQAECn9DAAMLAAoKSBGXBADGAQALAAoKSBGXBADGAQAKAAEKmQKSVgEhAAAAAA==.Triplock:BAAANQAECgEJAQAAAA==.Trolcain:BAABNQAECn9PAAIRAAoKuiIuBwACAwARAAoKuiIuBwACAwAAAA==.',
Tw='Twistedspork:BAAANQAECgQIDwAAAA==.',
Ul='Ulfal:BAAANQAECgEIAQAAAA==.',
Un='Unbuffed:BAAANQADCgIIAgABNQAECgoKRQAVALEeAA==.',
Ut='Uthon:BAAANQAECgMIBAAAAA==.',
Va='Vaedar:BAAANQAECgEIAQAAAA==.Vagglord:BAAANQAECgQIDwAAAA==.Valha:BAABNQAECn8pAAIiAAoKIA9oLQCoAQAiAAoKIA9oLQCoAQAAAA==.Vardisk:BAAANQADCgQIBAAAAA==.Varlashard:BAAANQADCggIFQAAAA==.Varteras:BAABNQAECn88AAMMAAoKwhc0BwAuAgAMAAkKFRc0BwAuAgAKAAcKoA7uvwDSAAAAAA==.',
Ve='Vellron:BAABNQAECn80AAIDAAoKYwq4cwDYAQADAAoKYwq4cwDYAQAAAA==.Veroque:BAAANQADCgUIBQAAAA==.',
['Và']='Vàsh:BAAANQAECgUICAAAAA==.',
['Vø']='Vødøu:BAABNQAECn8dAAMPAAkK6R6/PQAGAgAPAAkK0x2/PQAGAgAOAAQKABdGYQAwAQAAAA==.',
Wa='Wafflelegend:BAABNQAECn8mAAIiAAgKFiW4CgBaAwAiAAgKFiW4CgBaAwAAAA==.Wardkbriggle:BAABNQAECn8XAAMkAAkKbBrFNQACAgAkAAkKExfFNQACAgARAAgKsRg0VgC5AQAAAA==.Warent:BAAANQAECgIIAgAAAA==.Warint:BAABNQAECn8ZAAICAAkKowYb7wAFAQACAAkKowYb7wAFAQAAAA==.Wartiger:BAABNQAFFH8GAAITAAYKKyC7AQC/AQATAAYKKyC7AQC/AQAAAA==.',
We='Weeble:BAAANQADCgMIAwAAAA==.Welish:BAAANQABCgEIAQAAAA==.',
Wi='Wifi:BAABNQAECn8yAAICAAgKqyUQNgCMAgACAAgKqyUQNgCMAgAAAA==.',
Wo='Wolfdude:BAAANQAECggICQAAAA==.',
Wy='Wydge:BAABNQAECn8oAAIJAAkK6gyRowBdAQAJAAkK6gyRowBdAQAAAA==.Wyven:BAACNQAFFH8HAAMgAAIKGR4bHQCLAAAkAAIKUBYPFgCUAAAgAAIK6xcbHQCLAAA1AAQKfzgAAxEACgq8IswPADgDABEACQrrIswPADgDACQABApwGg1aAC4BAAE1AAMKBwgKAAYAAAAA.',
Xa='Xanddoria:BAABNQAECn9IAAQOAAoKfiOCAgAwAwAOAAoKfiOCAgAwAwAPAAoKEx+vEgDiAgAnAAgKCRajAgD4AQAAAA==.Xaoc:BAABNQAECn8UAAISAAcKEhV1KgDJAQASAAcKEhV1KgDJAQAAAA==.',
Xh='Xhared:BAABNQAECn8vAAIgAAoKDSCeFgBUAgAgAAoKDSCeFgBUAgAAAA==.',
Xo='Xochital:BAAANQADCgEIAQAAAA==.',
Ye='Yellodur:BAAANQADCgIIAgAAAA==.Yesenia:BAAANQADCgcIDAAAAA==.',
Yu='Yunah:BAAANQADCgYIBgAAAA==.',
Ze='Zephy:BAABNQAECn8aAAIdAAYKcgnqugABAQAdAAYKcgnqugABAQAAAA==.',
['Åe']='Åeon:BAAANQAECgQICQAAAA==.',
['Ðr']='Ðráco:BAAANQAECgQIBAAAAA==.',
['ßu']='ßullzeye:BAAANQADCgcIBwAAAA==.',
['Ÿu']='Ÿunalessca:BAAANQAECgYICwAAAA==.',
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
