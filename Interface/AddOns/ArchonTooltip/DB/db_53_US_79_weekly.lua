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

local lookup = {'Hunter-BeastMastery','DemonHunter-Devourer','Druid-Balance','Paladin-Holy','Mage-Arcane','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Mage-Frost','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Paladin-Retribution','Paladin-Protection','Shaman-Enhancement','Monk-Mistweaver','Shaman-Restoration','DemonHunter-Vengeance','Priest-Shadow','Unknown-Unknown','Evoker-Preservation','Evoker-Devastation','Warrior-Arms','Warrior-Fury','Druid-Restoration','DeathKnight-Blood','Evoker-Augmentation','DemonHunter-Havoc','Priest-Holy','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Priest-Discipline','Warrior-Protection','Druid-Guardian','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aaronius:BAAANQAECgYIEgAAAA==.',
Ab='Abrahm:BAAANQABCgIIAgAAAA==.',
Ac='Acceptance:BAAANQAECggICwAAAA==.',
Ad='Adoe:BAABNQAECn8bAAIBAAcKCxrxJgB+AQABAAcKCxrxJgB+AQAAAA==.Adora:BAAANQAECgMJBQAAAA==.',
Ag='Agaliarept:BAAANQADCgMIAwAAAA==.Agathos:BAAANQADCggIFQAAAA==.',
Ai='Aidenator:BAABNQAECn8cAAICAAgK0BqiBQC4AQACAAgK0BqiBQC4AQAAAA==.',
Al='Aluni:BAAANQADCgEIAQAAAA==.',
Am='Ammastin:BAAANQABCgMIAwAAAA==.',
An='Andorix:BAAANQAECgQIBgAAAA==.Andretta:BAAANQAECgMIAgAAAA==.Angelneko:BAABNQAECn8mAAIDAAcKrAbSJADTAAADAAcKrAbSJADTAAAAAA==.',
Ar='Arinthian:BAAANQAECgUICAAAAA==.Artrian:BAAANQAECggIEgAAAA==.',
At='Atetoomuch:BAAANQABCgYIBgAAAA==.Atthis:BAAANQADCgEIAQAAAA==.',
Au='Auroraa:BAAANQAECgUIDgAAAA==.Auyniko:BAAANQAECgcIBwABNQAECgkJHwAEALEfAA==.',
Av='Avalectra:BAAANQAECgEIAQAAAA==.',
Az='Azmodeaz:BAABNQAECn8sAAIFAAgK+Q6GWQAKAQAFAAgK+Q6GWQAKAQAAAA==.Azraely:BAAANQADCgcIBwAAAA==.Aztrik:BAABNQAECn8eAAQGAAgKXB4uBgDCAAAHAAcKOB4ZWABOAgAGAAIKCSEuBgDCAAAIAAIK8yOLCwBtAAAAAA==.',
Ba='Bajapanti:BAABNQAECn8kAAIJAAkKfw7kBQCOAQAJAAkKfw7kBQCOAQAAAA==.Ballyhøø:BAABNQAECn8WAAIDAAkKnRRMMABfAgADAAkKnRRMMABfAgAAAA==.Bandaron:BAAANQAECgEIAQAAAA==.Barload:BAAANQABCggIEAAAAA==.Baxstab:BAABNQAECn8qAAMKAAgKThaoBgCvAQAKAAgKThaoBgCvAQALAAIKMgo+SQBwAAAAAA==.',
Be='Belladeon:BAABNQAECn8iAAMMAAoKchWxCwAEAgAMAAgKuxaxCwAEAgAFAAgK0Qef8wCkAQAAAA==.Betrubt:BAAANQAECggIBwAAAA==.',
Bh='Bhagee:BAAANQADCgUICgAAAA==.',
Bl='Blackpatch:BAABNQAECn8oAAMNAAkKWRnBAwDyAQANAAkKWRnBAwDyAQAOAAQKXANuJwCNAAAAAA==.Blacksheep:BAAANQADCggIAQAAAA==.Blaqkid:BAAANQADCgYIBgAAAA==.Blaqsun:BAABNQAECn8gAAIPAAgKZg+ViACOAQAPAAgKZg+ViACOAQAAAA==.Blargg:BAAANQAECgUIBwAAAA==.Bleeda:BAAANQADCggIAQAAAA==.Bloomhammer:BAAANQAECgEIAQAAAA==.Blooming:BAABNQAECn8nAAIEAAgKbB3iDQDvAQAEAAgKbB3iDQDvAQAAAA==.',
Bo='Booneboy:BAABNQAECn8UAAMQAAUK6R2TqwDIAQAQAAUK6R2TqwDIAQARAAEKjgm3OQAuAAAAAA==.Botemedel:BAABNQAECn8eAAIRAAgKmxaRHgD0AQARAAgKmxaRHgD0AQABNQAFFAQIBwASAAkFAA==.Bowtox:BAAANQADCggICgAAAA==.',
Br='Brennor:BAABNQAECn8qAAIQAAgKVwg6UQAiAQAQAAgKVwg6UQAiAQAAAA==.Brewslunt:BAABNQAECn8fAAITAAoKzhoWDwCPAgATAAoKzhoWDwCPAgABNQAFFAYIFgAUAOMZAA==.Bronamaly:BAAANQADCgYICAAAAA==.',
Ca='Cabbagehunt:BAAANQADCgcIEwAAAA==.Caeden:BAABNQAECn8lAAIUAAgKFw6OJABSAQAUAAgKFw6OJABSAQAAAA==.Cairyan:BAABNQAECn8mAAIVAAkKNxiQCABsAgAVAAkKNxiQCABsAgAAAA==.Caiya:BAAANQADCgcIBwABNQAECgkJIgALAF8gAA==.Cassin:BAAANQADCgcICgAAAA==.Castalia:BAABNQAECn8UAAIWAAUKnwyFGwCtAAAWAAUKnwyFGwCtAAAAAA==.Cattilina:BAAANQADCggIEAAAAA==.',
Ce='Celenara:BAACNQAFFH8LAAIFAAQK7xIADQDzAAAFAAQK7xIADQDzAAA1AAQKfyoAAwUACgo6HhphALwCAAUACgo6HhphALwCAAwAAgohC584AFsAAAAA.Celendil:BAAANQADCgUIBQABNQAFFAQICwAFAO8SAA==.Celinne:BAAANQADCgUIBQAAAA==.Celithe:BAAANQAECgIIBQAAAA==.',
Ch='Charlereaux:BAAANQADCggICQAAAA==.Charmcaster:BAABNQAECn8fAAIFAAgKLhjVFwCxAQAFAAgKLhjVFwCxAQAAAA==.Charmstrike:BAAANQAECgMIBAAAAA==.Chedissa:BAAANQADCgQIBAABNQADCgYICgAXAAAAAA==.Chleo:BAAANQAECgQIEwAAAA==.Choco:BAACNQAFFH8dAAIYAAcKBSAmAgCbAgAYAAcKBSAmAgCbAgA1AAQKfywAAxgACQrOISMJABEDABgACQrOISMJABEDABkAAgpUF9gyAHkAAAAA.Chocolat:BAAANQADCggICAABNQAFFAcIHQAYAAUgAA==.Chudfox:BAAANQADCgEJAQAAAA==.',
Co='Coggler:BAAANQAECgUIDAAAAA==.Conqueror:BAAANQAECgQIBwABNQAECggIEQAXAAAAAA==.Corcia:BAAANQAECgIIAgAAAA==.',
Cr='Creatlach:BAAANQAECgIIAgABNQAFFAYIFgAUAOMZAA==.Crotchpox:BAAANQADCgQIBAAAAA==.Crualti:BAABNQAECn8aAAMaAAgKnwc/bADCAAAaAAgKXgU/bADCAAAbAAQKegmVIAC2AAAAAA==.',
Cu='Cuppajoe:BAAANQADCgMIAwAAAA==.Cupper:BAAANQABCgcJCQABNQAECgUIEAAXAAAAAA==.Curmudge:BAABNQAECn8zAAIcAAoK0xdVAwBqAgAcAAoK0xdVAwBqAgAAAA==.',
Da='Dabtoomuch:BAAANQABCgIIAgAAAA==.Dalectra:BAAANQAECgQICAAAAA==.Darachane:BAAANQAECgQIBgAAAA==.Darkpriest:BAAANQAECgIIAgAAAA==.Darovan:BAAANQADCggJEAABNQAECgcIJwAdAOIfAA==.Darthnater:BAAANQAFFAEIAQAAAA==.Dauglow:BAABNQAECn8qAAMBAAgKhBD2HACkAQABAAgKhBD2HACkAQAJAAEKhwnmhQA4AAAAAA==.',
De='Deathball:BAAANQAECgEIAQAAAA==.Deathstars:BAAANQADCgcIEwAAAA==.Deboss:BAAANQAECggIDgAAAA==.Dellianne:BAAANQABCgEIAQAAAA==.Delritha:BAAANQAECgUICAAAAA==.Deltithrax:BAABNQAECn8mAAMZAAcKkA8aBwAKAQAeAAYKPxEADwBSAQAZAAcKaA0aBwAKAQAAAA==.Demonagent:BAAANQAECgUIDgAAAA==.Desdh:BAACNQAFFH8MAAMfAAQKXBViCACUAAAfAAMKXBViCACUAAACAAIK4gdpCQBJAAA1AAQKfy8AAx8ACgrMIccaAMQCAB8ACgoSIccaAMQCAAIAAwp8HhsTABcBAAAA.Devious:BAAANQAECgYIBgABNQAECggIJwAEAGwdAA==.',
Di='Dinö:BAAANQAECgMJBAABNQAECgkJHQABAHcRAA==.',
Dm='Dmnslyer:BAAANQADCggIDQAAAA==.',
Do='Docspades:BAABNQAECn8jAAIgAAcK3hXkFwCzAQAgAAcK3hXkFwCzAQAAAA==.Dohane:BAAANQADCgQIBAABNQAECgYIDAAXAAAAAA==.Domrogue:BAAANQAECgUIBwAAAA==.Dornoch:BAAANQADCggIHAAAAA==.',
Dr='Dramine:BAAANQADCgQIBwAAAA==.Draone:BAABNQAECn8hAAIFAAkK7QmcBgGCAQAFAAkK7QmcBgGCAQAAAA==.Dreabolic:BAAANQADCgYICwAAAA==.Dreamss:BAABNQAECn8tAAMfAAoKKxOyFQA+AQACAAgKvAY4OQB7AQAfAAkKLhSyFQA+AQAAAA==.Drhkillinger:BAAANQAECgUIBQABNQAECgUIDgAXAAAAAA==.Drspades:BAAANQAECgEIAQAAAA==.',
Du='Dugosh:BAAANQADCggICwAAAA==.Duzz:BAAANQABCggIFwAAAA==.',
['Dé']='Démetal:BAAANQADCggIDgAAAA==.',
Ei='Einherja:BAABNQAECn8YAAQhAAoKVhf4aQBqAQAhAAYKexj4aQBqAQAiAAcKZRG3XAA2AQAdAAIKDhpoVABOAAAAAA==.',
El='Elessaria:BAABNQAECn8UAAIcAAUK8QdkJwCkAAAcAAUK8QdkJwCkAAAAAA==.Elfatheàrt:BAAANQADCggIHAAAAA==.Elidrus:BAAANQADCgYICgABNQAECggIDQAXAAAAAA==.',
En='Enodlo:BAAANQADCgUIBQAAAA==.',
Er='Erora:BAABNQAECn8lAAIWAAoKShYGGgB9AgAWAAoKShYGGgB9AgAAAA==.',
Es='Estherras:BAABNQAECn8YAAIBAAYKnxPkMwBVAQABAAYKnxPkMwBVAQAAAA==.',
Fe='Feardotrun:BAABNQAECn8fAAMGAAcKihBZOADfAAAGAAQKewtZOADfAAAHAAcKihBzZAC6AAAAAA==.Felicious:BAAANQADCggIHAAAAA==.',
Fi='Finally:BAAANQADCggIHAAAAA==.Firemage:BAABNQAECn8nAAMHAAoKUyBWJwDnAgAHAAgKGR9WJwDnAgAGAAQKuSIAIABwAQAAAA==.Fizzanelf:BAAANQAECgEIAQAAAA==.',
Fl='Flaildelyn:BAAANQAECgEIAQAAAA==.Flokíe:BAAANQADCggICAAAAA==.',
Fo='Fortytwo:BAAANQAECggIEAAAAA==.',
Fr='Freyá:BAAANQAECgEIAgAAAA==.Friendo:BAABNQAECn8kAAMDAAkKZAqHDgBoAQADAAkKZAqHDgBoAQAjAAEK8AjPSAAoAAAAAA==.Frostbight:BAABNQAECn8jAAIFAAgKaBYqmgBMAgAFAAgKaBYqmgBMAgAAAA==.Frostied:BAABNQAECn8ZAAMdAAkKTx9nAwA+AgAdAAkKsh5nAwA+AgAiAAUKbxkxTQCCAQAAAA==.',
Fu='Futnuraz:BAAANQADCggIFQAAAA==.',
Fy='Fyrakkobama:BAAANQAECgYIBgABNQAECggIDQAXAAAAAA==.Fyriat:BAABNQAECn8YAAIMAAYKjAvPCAD/AAAMAAYKjAvPCAD/AAAAAA==.',
Ga='Galathel:BAABNQAECn8nAAIRAAgKBROECwBEAQARAAgKBROECwBEAQABNQAECgkJJQAUALkbAA==.Gazardiel:BAABNQAECn8XAAIQAAYK5QSqlwCqAAAQAAYK5QSqlwCqAAAAAA==.',
Ge='Gelinia:BAABNQAECn8eAAMWAAcKdgy0EgD3AAAWAAcKdgy0EgD3AAAkAAEKUwFvMwAYAAAAAA==.Gerrald:BAAANQADCgUIBAABNQAECgkJHQABAHcRAA==.Getafix:BAAANQAECgUICQABNQAECgkJJQAUALkbAA==.',
Gh='Ghrass:BAAANQADCgQIBQAAAA==.',
Gi='Girthquakes:BAAANQAECgEIAQAAAA==.',
Gl='Glorbo:BAABNQAECn8YAAQEAAYKsh26GACTAQAEAAYKsh26GACTAQAQAAEKsBHg5QBDAAARAAEK4BbYagA9AAAAAA==.',
Go='Goldstorm:BAAANQADCggIDwAAAA==.Goliath:BAABNQAECn8XAAMUAAYKtRVTjQBoAQAUAAYKtRVTjQBoAQAPAAUKWBDftAAoAQAAAA==.',
Gr='Gregoron:BAAANQABCgYIBgAAAA==.Grimfelborn:BAACNQAFFH8KAAQGAAQK9QqsAwCCAAAHAAIKqw1RMgCRAAAGAAIKlwSsAwCCAAAIAAEKAAArEwA6AAA1AAQKfyoABAcACgqhGHFNAGwCAAcACgqWF3FNAGwCAAgAAQoAADAnAE8AAAYAAQoTFdYRAE0AAAAA.Grimosh:BAAANQAECgEIAQAAAA==.Grondosh:BAAANQAECgUICAAAAA==.Gryphindor:BAABNQAECn8UAAIBAAcKwAkbugCPAQABAAcKwAkbugCPAQAAAA==.',
['Gì']='Gìorgìa:BAAANQABCgIIAwAAAA==.',
Ha='Hahwe:BAAANQADCgIIAgABNQAECggIDQAXAAAAAA==.Haljo:BAAANQADCgQJBAAAAA==.Hanoverfiste:BAAANQAECgUIEAAAAA==.Hapsburg:BAABNQAECn8qAAMTAAgKFw4NCgA2AQATAAgKFw4NCgA2AQANAAcKIggRPQAuAQAAAA==.Harahel:BAAANQAECgQIBAAAAA==.Havince:BAABNQAECn8hAAIdAAgKbiKDBAASAgAdAAgKbiKDBAASAgAAAA==.Hawktuah:BAAANQAECgEIAgAAAA==.Haylee:BAAANQABCgIIAgAAAA==.',
He='Helle:BAAANQAECgIIAgAAAA==.Hercboyy:BAABNQAECn8iAAMEAAgKZCN2GgANAwAEAAcKgSZ2GgANAwARAAEKAAADYgBVAAAAAA==.',
Hi='Higgs:BAAANQADCggICQABNQAECgkJJAAEAJUUAA==.Higgspally:BAABNQAECn8kAAIEAAkKlRTbEwC0AQAEAAkKlRTbEwC0AQAAAA==.',
Ho='Holyball:BAABNQAECn8nAAIQAAoKOhVPFADaAQAQAAoKOhVPFADaAQAAAA==.Holytalon:BAAANQADCgIIAgAAAA==.Hotak:BAAANQABCgYIBAAAAA==.',
Hu='Hughjahsol:BAAANQADCgIIAgAAAA==.Hukaru:BAAANQABCgIIAgABNQAECggIIQAdAG4iAA==.Huuken:BAAANQAECgQIBAAAAA==.Huulkster:BAAANQADCgQIBAAAAA==.',
Hy='Hydra:BAAANQAECgEJAQAAAA==.',
Il='Ilovehunter:BAAANQADCggICAAAAA==.Ilyndra:BAABNQAECn8mAAIlAAcK+yRUAgDoAQAlAAcK+yRUAgDoAQAAAA==.',
In='Infernella:BAAANQADCgMIAwAAAA==.',
Ir='Ironskin:BAAANQAECgQICgAAAA==.',
Is='Iselilja:BAAANQAECgYIEgAAAA==.',
It='Ithea:BAABNQAECn80AAIFAAoKzxgcCABJAgAFAAoKzxgcCABJAgAAAA==.',
Ja='Jackshots:BAAANQADCgIIAgAAAA==.Jaeson:BAEBNQAECn8VAAMHAAgKqAz+HwBvAQAHAAgKqAz+HwBvAQAIAAEKBwa4MwAsAAAAAA==.Jakaro:BAACNQAFFH8KAAMGAAQK2gdiEgCHAAAGAAIK/ARiEgCHAAAHAAIKlg0bQABLAAA1AAQKfxoAAwYACAq1ERcrACUBAAcABgrjEZuoAIIBAAYABQovERcrACUBAAAA.Javoren:BAAANQADCgcIBwAAAA==.',
Je='Jeefgpt:BAAANQAECgEIAQABNQAECggIDQAXAAAAAA==.Jeefrenzy:BAAANQAECggIDQAAAA==.Jeefwrld:BAAANQAECgYICQAAAA==.Jeffers:BAAANQAECgEIAgABNQAECggIDQAXAAAAAA==.Jeffha:BAAANQADCggICAAAAA==.',
Ji='Jiinx:BAABNQAECn8mAAMBAAcK3RbYMQBbAQABAAcK3RbYMQBbAQAJAAUKrwtMTQD8AAAAAA==.',
Jo='Joap:BAAANQAECgYIBgAAAA==.Joejr:BAABNQAECn8nAAMgAAkKURT9bQDUAQAgAAgKhhT9bQDUAQAWAAgKuRWNBAC5AQAAAA==.Jonald:BAABNQAECn8cAAICAAoK9gt4MwCmAQACAAoK9gt4MwCmAQAAAA==.',
Jt='Jtizlfrizl:BAABNQAECn8UAAIKAAUKJxSZJwCxAAAKAAUKJxSZJwCxAAAAAA==.',
Ju='Juniperz:BAABNQAECn8fAAIdAAgKmA/MFwArAQAdAAgKmA/MFwArAQAAAA==.',
Ka='Kaaydenn:BAABNQAECn8ZAAQEAAYKJR15HQB2AQAEAAUKqyB5HQB2AQAQAAEKAAC5lAE/AAARAAEKAABYdwAlAAAAAA==.Kaghro:BAAANQADCgcICAAAAA==.Kalaziel:BAABNQAECn8UAAIPAAkK6QVRlAByAQAPAAkK6QVRlAByAQAAAA==.Kalierix:BAAANQAECggIDwAAAA==.Kamus:BAAANQADCgcIDAAAAA==.Karawyn:BAAANQAECgEIAgABNQADCgQICAAXAAAAAA==.Karelix:BAAANQADCgIIBAAAAA==.Katrichi:BAAANQAECgIIAwAAAA==.Katrishy:BAACNQAFFH8MAAIWAAQK5hHGBADiAAAWAAQK5hHGBADiAAA1AAQKfyoAAhYACgq1G/QSANMCABYACgq1G/QSANMCAAAA.Kayde:BAAANQAECgQICQAAAA==.',
Ke='Keedrid:BAABNQAECn8lAAIhAAkKYRxqJwCdAgAhAAkKYRxqJwCdAgAAAA==.Kelaeno:BAABNQAECn8iAAIPAAkKaAxaJwAfAQAPAAkKaAxaJwAfAQAAAA==.Kev:BAACNQAFFH8MAAIEAAMKeRsbFgD/AAAEAAMKeRsbFgD/AAA1AAQKfycAAgQACgoWI7IEAKsDAAQACgoWI7IEAKsDAAAA.',
Ki='Kirima:BAAANQADCggICAAAAA==.Kirmit:BAAANQAECgQIBAAAAA==.',
Kl='Klevege:BAAANQADCgUIBQAAAA==.',
Kn='Knoll:BAAANQAECgIIBAAAAA==.',
Kr='Kreeona:BAABNQAECn8lAAIUAAkKuRtBBwBVAgAUAAkKuRtBBwBVAgAAAA==.Kruàlty:BAABNQAECn8dAAMjAAgKXhZvDQBEAgAjAAgKXhZvDQBEAgADAAMKewgckgCPAAAAAA==.',
La='Laird:BAAANQADCgcICwAAAA==.',
Le='Legreecast:BAAANQADCgcIGgAAAA==.',
Li='Liare:BAACNQAFFH8bAAQIAAYKpiCvAADCAAAHAAMKNyLiGQAnAQAIAAMK5x6vAADCAAAGAAIKsSByAQC6AAA1AAQKfywABAcACgrHJLgKAHcDAAcACgrHJLgKAHcDAAYABgoxHxQXALQBAAgAAgqZJXYXANQAAAAA.Liasong:BAAANQAECgUIBQAAAA==.Litheliice:BAABNQAECn8qAAIgAAgKhRZlKABdAQAgAAgKhRZlKABdAQAAAA==.',
Lo='Lodur:BAABNQAECn8WAAIUAAYKUA6kNgAKAQAUAAYKUA6kNgAKAQAAAA==.Lonen:BAAANQAECgYIEgAAAA==.Losat:BAABNQAECn8jAAIlAAkKaQeZCAArAQAlAAkKaQeZCAArAQAAAA==.',
Lu='Lukeluke:BAAANQADCgQIBwAAAA==.',
Ly='Lyn:BAAANQAECgIIAgAAAA==.',
['Lî']='Lîîght:BAAANQADCggIHgAAAA==.',
Ma='Machiato:BAAANQADCggIEAAAAA==.Mackkie:BAABNQAECn8cAAMTAAYKWhInJQBSAQATAAYKWhInJQBSAQANAAYKZQVZSADeAAAAAA==.Madonkadonk:BAABNQAECn8mAAIZAAgKrQfhBQApAQAZAAgKrQfhBQApAQAAAA==.Maedai:BAAANQAECgUIDgAAAA==.Maeli:BAAANQAECgEIAQAAAA==.Magladroth:BAAANQABCgQJBAAAAA==.Maldive:BAABNQAECn8hAAQIAAkK/g+ABAAMAQAIAAgKXg+ABAAMAQAHAAgKsQuHaACyAAAGAAMKnwsMTgCVAAAAAA==.Maligasia:BAAANQADCgIIAwAAAA==.Mallicia:BAABNQAECn8vAAIgAAoK/CEpDwBMAwAgAAoK/CEpDwBMAwAAAA==.Mallika:BAAANQAECgEIAQABNQAECgoKLwAgAPwhAA==.Mallistra:BAABNQAECn8iAAITAAoKbROmBQCbAQATAAoKbROmBQCbAQABNQAECgoKLwAgAPwhAA==.Mallwizard:BAAANQAECgUJCgAAAA==.Mandible:BAAANQABCgIIAgAAAA==.Martris:BAAANQAECgQICQAAAA==.Maryjane:BAAANQAECgMJAwAAAA==.Mashma:BAAANQADCggICAAAAA==.Massoflice:BAAANQAECgYIDwAAAA==.Mawkt:BAAANQADCggIAQAAAA==.Maxblaide:BAAANQAECgIIAgAAAA==.Maxentia:BAAANQADCggIEAAAAA==.',
Me='Melovania:BAAANQADCgIIAgAAAA==.',
Mi='Miami:BAAANQAECgMIBAABNQAFFAcIFwAZAHwaAA==.Milah:BAAANQABCgIIAgAAAA==.Missile:BAAANQAECgQIBQAAAA==.Misstangy:BAAANQADCgcIFwAAAA==.',
Mo='Moct:BAABNQAECn8mAAIRAAkK0h/tAQBLAgARAAkK0h/tAQBLAgAAAA==.Monikal:BAAANQAECgIIAgAAAA==.',
Mu='Musashi:BAABNQAECn8zAAIBAAoKHiTXBAC+AwABAAoKHiTXBAC+AwABNQAECgkJLwABAO8mAA==.Muskeg:BAABNQAECn8hAAIdAAgKKxIIVwCXAQAdAAgKKxIIVwCXAQAAAA==.Mustardhunt:BAAANQADCgYICgAAAA==.',
['Mü']='Münchkiné:BAAANQABCggIFQAAAA==.',
Na='Namanari:BAAANQABCgIJAgAAAA==.Naris:BAAANQAECggIDQAAAA==.',
Ne='Necrochade:BAAANQAECgEIAQAAAA==.Neptune:BAABNQAECn8oAAIFAAkKbBeiXwDAAgAFAAkKbBeiXwDAAgAAAA==.',
Ni='Nikra:BAAANQAECgQICAAAAA==.Nishal:BAAANQADCggIGwAAAA==.',
Ny='Nyxaries:BAAANQAECgUICQAAAA==.',
['Né']='Néwby:BAABNQAECn8rAAMmAAoKvB3rBwADAwAmAAoKvB3rBwADAwAjAAQKdA4KDwC3AAAAAA==.',
Op='Opalynn:BAAANQAECgEIAQAAAA==.Ophirra:BAAANQABCgYIDgAAAA==.',
Oz='Ozempic:BAAANQAECgQIBAABNQAFFAcIHQAYAAUgAA==.',
Pa='Pablo:BAABNQAECn8YAAIQAAoKjBYPZgBpAgAQAAoKjBYPZgBpAgAAAA==.Pannacea:BAAANQAECgQIBAABNQAECgkJJQAUALkbAA==.Patriot:BAAANQADCggIDAAAAA==.Pawinurbutt:BAAANQADCgQIBAAAAA==.',
Pe='Peppert:BAAANQAECgUICQAAAA==.',
Ph='Phane:BAAANQAECgQIBwAAAA==.',
Po='Pocketheals:BAAANQAECgMIAwAAAA==.Poon:BAAANQAECgQICAAAAA==.',
Pr='Pretzelz:BAAANQADCgQIAwAAAA==.',
Pu='Puffer:BAAANQAECgYIDgAAAA==.',
Px='Pxry:BAAANQAECgQIBAAAAA==.',
Py='Pyrrhus:BAAANQAECgQIBAAAAA==.',
Qu='Quam:BAAANQABCggIFgAAAA==.',
Ra='Rabone:BAAANQADCgIJAgAAAA==.Raevyn:BAAANQADCgYIBgAAAA==.Raito:BAAANQAECggIDgAAAA==.Rakshasa:BAABNQAECn82AAQHAAoKaCFiDwBWAwAHAAkKKiNiDwBWAwAGAAMK3w9VRwCqAAAIAAEKIBXUDwBMAAAAAA==.Rano:BAAANQAECgEIAQAAAA==.Rasetsungo:BAABNQAECn8fAAIgAAkKchKVDQASAgAgAAkKchKVDQASAgAAAA==.Raura:BAAANQADCggIHAAAAA==.Rayala:BAAANQAECggICQAAAA==.',
Re='Redblueblurr:BAAANQAECgUIDQAAAA==.Remi:BAABNQAECn8ZAAMgAAgKcx1lCgA+AgAgAAgKcx1lCgA+AgAWAAEK+wCSkQAYAAAAAA==.Rev:BAAANQADCgUIBQAAAA==.Reveillark:BAAANQAECgIIAgAAAA==.Revelaiden:BAAANQABCgIIAgABNQAECggIHAACANAaAA==.',
Ri='Rise:BAAANQAECgcIDwAAAA==.',
Ro='Rolan:BAABNQAECn8vAAQiAAoKYSUyFgDaAgAiAAkK9yQyFgDaAgAhAAgK2SPFHwDMAgAdAAQKtSOFWwCEAQAAAA==.Ronnic:BAAANQABCggIIQAAAA==.Rosalian:BAABNQAECn8aAAIcAAgKixLdCwB8AQAcAAgKixLdCwB8AQAAAA==.Rotiko:BAAANQAECgYIEQAAAA==.Roweene:BAABNQAECn8mAAInAAcKvgMlBQCbAAAnAAcKvgMlBQCbAAAAAA==.',
['Rá']='Rágnar:BAABNQAECn8jAAIQAAoKzRD1LAB5AQAQAAoKzRD1LAB5AQAAAA==.',
Sa='Sabiel:BAABNQAECn8VAAIDAAYKqAYFNgCEAAADAAYKqAYFNgCEAAAAAA==.Sakuta:BAAANQADCgYIBgABNQAECgkJIQAUAOcdAA==.',
Se='Serenatee:BAABNQAECn8lAAIWAAgKiwxcCQBeAQAWAAgKiwxcCQBeAQAAAA==.',
Sh='Shaedai:BAABNQAECn8XAAMUAAgKMQ8aHwBtAQAUAAgKMQ8aHwBtAQAPAAEKPAJKUwEkAAAAAA==.Shagohod:BAAANQADCgQIBAAAAA==.Shakked:BAAANQAECgEIAwAAAA==.',
Sk='Skotojar:BAAANQADCgUIBQAAAA==.',
Sn='Snortedgfuel:BAAANQAECgcIEgAAAA==.',
So='Sokroar:BAAANQAECgYICAABNQAFFAYIAQAXAAAAAA==.Solphera:BAAANQADCgUIDAAAAA==.Sonknight:BAAANQAECgQICAAAAA==.',
Sp='Speedshot:BAAANQADCgUIBgAAAA==.Spitefulcrow:BAABNQAECn8ZAAIoAAgKaAl9CADJAQAoAAgKaAl9CADJAQAAAA==.',
St='Stardstr:BAAANQADCgMIAwAAAA==.Stealinsoulz:BAAANQADCgYICgAAAA==.Stealsoul:BAAANQADCgIIAgABNQADCgYICgAXAAAAAA==.Sto:BAAANQAECgEIAgAAAA==.Stratof:BAAANQAECgYIBgAAAA==.',
Su='Sufferding:BAABNQAECn8bAAIfAAkKFQ2dIgDsAAAfAAkKFQ2dIgDsAAAAAA==.Suria:BAABNQAECn8nAAIcAAkKoR+FAQANAwAcAAkKoR+FAQANAwAAAA==.',
Sw='Swytchblade:BAAANQADCggIAQAAAA==.',
Sy='Syker:BAAANQADCgIIAgAAAA==.',
Ta='Tahrovin:BAAANQAECgYIDAAAAA==.Tavernn:BAAANQABCggIJgAAAA==.Taytorchips:BAABNQAECn8kAAMQAAkKDQUGcwDgAAAQAAkKDQUGcwDgAAAEAAMKNwH0EAFVAAAAAA==.',
Th='Thaendrin:BAAANQADCgYICQAAAA==.Thearcane:BAAANQADCgQIBwAAAA==.Thedoc:BAAANQAECgUICQAAAA==.Theefjeef:BAAANQAECgYIBQABNQAECggIDQAXAAAAAA==.Thorloim:BAABNQAECn8jAAMUAAgKKyA3WwD+AQAUAAcKch83WwD+AQASAAMKRA8FGgB/AAAAAA==.Thornx:BAAANQADCgEIAQAAAA==.Throwaway:BAAANQAECgcICAAAAA==.Thundercups:BAABNQAECn8fAAISAAgK0hQbBADMAQASAAgK0hQbBADMAQAAAA==.',
Ti='Tigerstarr:BAABNQAECn8dAAMiAAoKMBClNwD4AQAiAAoKMBClNwD4AQAhAAQKngmxowCzAAAAAA==.Tinyshieva:BAAANQADCgYICAAAAA==.Tizuki:BAAANQAECgQIBAAAAA==.',
To='Tonystandard:BAAANQAECgUICQABNQAECgcIEAAXAAAAAA==.',
Tr='Treborlock:BAABNQAECn8iAAMGAAkK5g2bAQB5AQAGAAkK5g2bAQB5AQAHAAEKmQKSVgEhAAAAAA==.Triplock:BAAANQAECgEJAQAAAA==.Trolcain:BAABNQAECn8oAAIhAAoKdBx4AQCVAgAhAAoKdBx4AQCVAgAAAA==.',
Tw='Twistedspork:BAAANQAECgMIAwAAAA==.',
Un='Unbuffed:BAAANQADCgIIAgABNQAECgkJJAAEAJUUAA==.',
Va='Vaedar:BAAANQAECgEIAQAAAA==.Vagglord:BAAANQAECgQIDwAAAA==.Valha:BAABNQAECn8kAAIfAAgKxg4kGQApAQAfAAgKxg4kGQApAQAAAA==.Vardisk:BAAANQADCgQIBAAAAA==.Varlashard:BAAANQADCggIDwAAAA==.Varteras:BAABNQAECn8pAAMIAAgKqhUrAQDGAQAIAAgKqhUrAQDGAQAHAAUKXAaL8QDnAAAAAA==.',
Ve='Vellron:BAABNQAECn8XAAIBAAgKbghmvwCEAQABAAgKbghmvwCEAQAAAA==.Veroque:BAAANQADCgUIBQAAAA==.',
['Và']='Vàsh:BAAANQAECgUICAAAAA==.',
['Vø']='Vødøu:BAABNQAECn8aAAMLAAgKZB+5BAD7AQALAAgKIB65BAD7AQAKAAQKABdGYQAwAQAAAA==.',
Wa='Wafflelegend:BAABNQAECn8mAAIfAAgKFiW4CgBaAwAfAAgKFiW4CgBaAwAAAA==.Wardkbriggle:BAABNQAECn8XAAMiAAkKbBrFNQACAgAiAAkKExfFNQACAgAhAAgKsRg0VgC5AQAAAA==.Warint:BAABNQAECn8VAAIQAAcK2gVoiwC7AAAQAAcK2gVoiwC7AAAAAA==.Wartiger:BAAANQAECgMIAwAAAA==.',
We='Weeble:BAAANQADCgMIAwAAAA==.Welish:BAAANQABCgEIAQAAAA==.',
Wi='Wifi:BAABNQAECn8gAAIQAAgK7iEQEAD7AQAQAAgK7iEQEAD7AQAAAA==.',
Wo='Wolfdude:BAAANQAECggICQAAAA==.',
Wy='Wydge:BAABNQAECn8hAAIFAAcKqg8HDAF5AQAFAAcKqg8HDAF5AQAAAA==.Wyven:BAABNQAECn8sAAMhAAoKkCHMDwA4AwAhAAkK6yLMDwA4AwAiAAQKqRLhIgAXAQABNQADCgcICgAXAAAAAA==.',
Xa='Xanddoria:BAABNQAECn8iAAMLAAkKXyBsBQDoAQAKAAcKtCImHgCPAgALAAgKOBlsBQDoAQAAAA==.Xaoc:BAABNQAECn8UAAINAAcKEhV1KgDJAQANAAcKEhV1KgDJAQAAAA==.',
Xh='Xhared:BAABNQAECn8nAAIdAAcK4h/1DgBsAQAdAAcK4h/1DgBsAQAAAA==.',
Xo='Xochital:BAAANQADCgEIAQAAAA==.',
Ye='Yesenia:BAAANQADCgUIBQAAAA==.',
Yu='Yunah:BAAANQADCgYIBgAAAA==.',
Ze='Zephy:BAAANQAECgQIDwAAAA==.',
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
