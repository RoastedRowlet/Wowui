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

local lookup = {'Priest-Holy','Paladin-Retribution','Hunter-BeastMastery','DemonHunter-Devourer','Unknown-Unknown','Druid-Balance','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Mage-Frost','DeathKnight-Unholy','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Monk-Mistweaver','Shaman-Restoration','DemonHunter-Vengeance','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Warrior-Arms','Druid-Restoration','Warrior-Fury','DeathKnight-Blood','Evoker-Augmentation','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Frost','Druid-Feral','Druid-Guardian','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aaronius:BAABNQAECn8aAAIBAAcKzgFfrACqAAABAAcKzgFfrACqAAAAAA==.',
Ab='Abrahm:BAAANQADCgEIAQAAAA==.',
Ac='Acceptance:BAACNQAFFH8LAAICAAYKxBi4BQBcAQACAAYKxBi4BQBcAQA1AAQKfxsAAgIACgoCHyIaAN4CAAIACgoCHyIaAN4CAAAA.',
Ad='Adoe:BAABNQAECn8oAAIDAAgKWBv5WwDMAQADAAgKWBv5WwDMAQAAAA==.Adora:BAAANQAECgMJBQAAAA==.',
Ag='Agaliarept:BAAANQADCgMIAwAAAA==.Agathos:BAAANQAECgEIAgAAAA==.',
Ai='Aidenator:BAABNQAECn8rAAIEAAkKoxuPEwD4AQAEAAkKoxuPEwD4AQAAAA==.',
Al='Algebradaddy:BAAANQAECggIBQABNQAECggIDgAFAAAAAA==.Allusttriele:BAAANQADCgEIAQAAAA==.Aluni:BAAANQADCgEIAQAAAA==.',
Am='Ammastin:BAAANQADCgEIAQAAAA==.',
An='Andorix:BAAANQAECgQICQAAAA==.Andretta:BAAANQAECgMIAgAAAA==.Angelneko:BAABNQAECn8qAAIGAAcKrAYWTQC9AAAGAAcKrAYWTQC9AAAAAA==.',
Ar='Arinthian:BAAANQAECgQICAAAAA==.Artrian:BAABNQAECn8dAAIBAAgKAxcFSADfAQABAAgKAxcFSADfAQAAAA==.',
At='Atthis:BAAANQADCgEIAQAAAA==.',
Au='Auroraa:BAABNQAECn8WAAIGAAYKYQmNfADaAAAGAAYKYQmNfADaAAAAAA==.Auyniko:BAAANQAECggIDwAAAA==.',
Av='Avalectra:BAAANQAECgEIAQAAAA==.',
Az='Azmodeaz:BAABNQAECn8sAAIHAAgK+Q647wCrAQAHAAgK+Q647wCrAQAAAA==.Azraely:BAAANQADCgcICAAAAA==.Aztrik:BAABNQAECn8iAAQIAAgKYCAZWABOAgAIAAgKTyAZWABOAgAJAAIKCSEwFACeAAAKAAIK8yOKIQBtAAAAAA==.',
Ba='Bajapanti:BAABNQAECn83AAILAAoK+BBNEQD0AQALAAoK+BBNEQD0AQAAAA==.Ballyhøø:BAACNQAFFH8HAAIGAAMKVg/sDgDWAAAGAAMKVg/sDgDWAAA1AAQKfx0AAgYACgraFkwwAF8CAAYACgraFkwwAF8CAAAA.Bandaron:BAAANQAECgQIBAAAAA==.Barload:BAAANQABCggIEAAAAA==.Basutei:BAAANQADCgEIAQAAAA==.Baxstab:BAABNQAECn83AAMMAAoKGxjRCAAwAgAMAAoKGxjRCAAwAgANAAIKMgo+SQBwAAAAAA==.',
Bc='Bcam:BAAANQADCgEIAQAAAA==.',
Be='Beahon:BAAANQADCgEIAQAAAA==.Beelzebrad:BAAANQAECgQIBwAAAA==.Belladeon:BAABNQAECn8mAAMOAAoKchWxCwAEAgAOAAgKuxaxCwAEAgAHAAgK0Qef8wCkAQAAAA==.Betrubt:BAAANQAECgcIDwABNQAECgkJFgAPAFgVAA==.',
Bh='Bhagee:BAAANQADCgUICwAAAA==.',
Bi='Bivouac:BAAANQAECgEIAQAAAA==.',
Bl='Blackpatch:BAABNQAECn87AAMQAAoKZhmLDwA0AgAQAAoKZhmLDwA0AgARAAQKXANuJwCNAAAAAA==.Blacksheep:BAAANQADCggIAQAAAA==.Blaqkid:BAAANQADCgYIBgAAAA==.Blaqsun:BAABNQAECn8zAAISAAoKZBNSKwD7AQASAAoKZBNSKwD7AQAAAA==.Blargg:BAAANQAECgUIBwAAAA==.Bleeda:BAAANQADCggIAQAAAA==.Blightmaker:BAAANQAECgYICgABNQAECgYIDgAFAAAAAA==.Bloomhammer:BAAANQAECgEIAQAAAA==.Blooming:BAABNQAECn81AAITAAgKmiGNHgCYAgATAAgKmiGNHgCYAgAAAA==.',
Bo='Booneboy:BAABNQAECn8eAAQCAAUK6R2TqwDIAQACAAUK6R2TqwDIAQATAAEK/hMp2AA7AAAUAAEKjgnLXQAqAAAAAA==.Botemedel:BAABNQAECn8oAAMUAAkKmhhUEgDHAQAUAAkKmhhUEgDHAQACAAMKzAomIwGAAAABNQAFFAYIDQAVAOcFAA==.Bowtox:BAAANQADCggICgAAAA==.',
Br='Brennor:BAABNQAECn80AAICAAkKuQnQpgBAAQACAAkKuQnQpgBAAQAAAA==.Brewslunt:BAABNQAECn8fAAIWAAoKzhoWDwCPAgAWAAoKzhoWDwCPAgABNQAFFAcIFwAXAPQaAA==.Bronamaly:BAAANQADCgYICAAAAA==.',
Ca='Cabbagehunt:BAAANQADCgcIEwAAAA==.Caeden:BAABNQAECn8sAAIXAAkKBg42VgCIAQAXAAkKBg42VgCIAQAAAA==.Cairyan:BAABNQAECn8mAAIYAAkKNxiQCABsAgAYAAkKNxiQCABsAgAAAA==.Caiya:BAAANQADCgcIDgABNQAECgoKNAANAA8hAA==.Carvil:BAAANQAECgYIBgAAAA==.Castalia:BAABNQAECn8eAAIZAAUKCg0fLgDdAAAZAAUKCg0fLgDdAAAAAA==.Cattilina:BAAANQADCggIEAAAAA==.',
Ce='Celenara:BAACNQAFFH8QAAIHAAYKxg8gEQAwAQAHAAYKxg8gEQAwAQA1AAQKfzAAAwcACgpLHhphALwCAAcACgpLHhphALwCAA4AAgohC584AFsAAAAA.Celendil:BAAANQADCgUIBQABNQAFFAYIEAAHAMYPAA==.Celinne:BAAANQAECgUIBQAAAA==.Celithe:BAAANQAECgUICQAAAA==.',
Ch='Charlereaux:BAAANQAECgEIAgAAAA==.Charmcaster:BAABNQAECn8jAAIHAAkKtBhRXQDUAQAHAAkKtBhRXQDUAQAAAA==.Charmstrike:BAAANQAECggICwAAAA==.Chedissa:BAAANQADCgQIBAABNQADCgYICgAFAAAAAA==.Chleo:BAABNQAECn8fAAIBAAYKKQkKjwDzAAABAAYKKQkKjwDzAAAAAA==.Choco:BAACNQAFFH8dAAIaAAcKBSAmAgCbAgAaAAcKBSAmAgCbAgA1AAQKfzAAAxoACgpHICMJABEDABoACgpHICMJABEDABsAAgpUF9gyAHkAAAAA.Chocolat:BAAANQADCggICQABNQAFFAcIHQAaAAUgAA==.Chocolight:BAAANQAECgIIAgABNQAFFAcIHQAaAAUgAA==.Chudfox:BAAANQADCgEJAQAAAA==.',
Co='Coggler:BAABNQAECn8bAAMcAAcKgBh3EQBmAQAcAAcKgBh3EQBmAQAdAAUKtgwB6wAOAQAAAA==.Conqueror:BAAANQAECgYIBwABNQAECgoKJgAeAKEPAA==.Corcia:BAAANQAECgMIAwAAAA==.',
Cr='Creatlach:BAAANQAECgIIAgABNQAFFAcIFwAXAPQaAA==.Crotchpox:BAAANQADCgQIBAAAAA==.Crualti:BAABNQAECn8aAAMfAAgKnweVIAC2AAAdAAgKXgWi7wABAQAfAAQKegmVIAC2AAAAAA==.',
Cu='Cuppajoe:BAAANQADCgMIAwAAAA==.Cupper:BAAANQADCgEIAQABNQAECgUIGgACAMMHAA==.Curmudge:BAABNQAECn9EAAIeAAoKPRzLCwDOAgAeAAoKPRzLCwDOAgAAAA==.',
Da='Dabtoomuch:BAAANQADCgEIAQAAAA==.Daimhin:BAAANQADCgcIBwAAAA==.Dalectra:BAAANQAECgQICAAAAA==.Darachane:BAAANQAECgQICAAAAA==.Darkpriest:BAAANQAECgIIAgAAAA==.Darovan:BAAANQADCggJEAABNQAECgcIJwAgAOIfAA==.Darthnater:BAABNQAECn8dAAIPAAkKnB1JCgCxAgAPAAkKnB1JCgCxAgAAAA==.Dauglow:BAABNQAECn82AAMDAAoK0A8CTQD2AQADAAoK0A8CTQD2AQALAAEKhwnmhQA4AAAAAA==.',
De='Deathball:BAAANQAECgEIAQAAAA==.Deathstars:BAAANQADCgcIFQAAAA==.Deboss:BAAANQAECggIDgAAAA==.Dellianne:BAAANQADCgEIAQAAAA==.Delritha:BAAANQAECgUICAAAAA==.Deltithrax:BAABNQAECn8qAAMhAAcKkA8ADwBSAQAhAAYKPxEADwBSAQAbAAcKaA2qEQDsAAAAAA==.Demonagent:BAABNQAECn8eAAMYAAcKiBMmEAAQAQAYAAcKiBMmEAAQAQAiAAMKtw5XbwC8AAAAAA==.Desdh:BAACNQAFFH8MAAMiAAQKXBXqEQDWAAAiAAMKXBXqEQDWAAAEAAIK4gerDwBFAAA1AAQKfy8AAyIACgrMIccaAMQCACIACgoSIccaAMQCAAQAAwp8HmAvAOcAAAAA.Devious:BAAANQAECgcIBwABNQAECggINQATAJohAA==.',
Di='Dinö:BAAANQAECgMJBAABNQAECgoKJgADAHYWAA==.',
Dm='Dmnslyer:BAAANQADCggIDQAAAA==.',
Do='Docspades:BAABNQAECn8kAAMBAAcK3hUuZAB2AQABAAcK3hUuZAB2AQAjAAEKXQeIFwArAAAAAA==.Dohane:BAAANQADCgQIBAABNQAECggIFgAEADQQAA==.Domrogue:BAABNQAECn8bAAMNAAkKeBabIwBHAgANAAkKeBabIwBHAgAMAAUKcAVFLwDAAAAAAA==.Dornoch:BAAANQAECgEIAgAAAA==.Douglane:BAAANQABCgYIBgAAAA==.',
Dr='Dramine:BAAANQADCgQIBwAAAA==.Draone:BAABNQAECn8qAAIHAAkK1AqrggB1AQAHAAkK1AqrggB1AQAAAA==.Dreabolic:BAAANQADCgYICwAAAA==.Dreamss:BAABNQAECn8xAAMiAAoKyhTBLwApAgAiAAoKyhTBLwApAgAEAAgKvAY4OQB7AQAAAA==.Drhkillinger:BAAANQAECgYIBwABNQAECgcIHgAYAIgTAA==.Drspades:BAAANQAECgEIAQAAAA==.',
Du='Dugosh:BAAANQADCggIDQAAAA==.Duzz:BAAANQABCggIFwAAAA==.',
['Dé']='Démetal:BAAANQADCggIDgAAAA==.',
Ei='Einherja:BAABNQAECn8gAAQgAAoKnBozNwA+AQAPAAYKexj4aQBqAQAgAAUKAxwzNwA+AQAkAAcKZRG3XAA2AQAAAA==.',
El='Elessaria:BAABNQAECn8eAAIeAAUKEwpuQQDEAAAeAAUKEwpuQQDEAAAAAA==.Elfatheàrt:BAAANQAECgEIAgAAAA==.Elidrus:BAAANQAECgIIAgABNQAECggIFgAIAGcDAA==.',
En='Enodlo:BAAANQADCgUIBgAAAA==.',
Er='Erora:BAABNQAECn8nAAIZAAoKShYGGgB9AgAZAAoKShYGGgB9AgAAAA==.',
Es='Estherras:BAABNQAECn8lAAIDAAcKexQ6bgCcAQADAAcKexQ6bgCcAQAAAA==.',
Fe='Feardotrun:BAABNQAECn8kAAMJAAcKihBZOADfAAAIAAcKihCTrwByAQAJAAQKewtZOADfAAAAAA==.Felicious:BAAANQAECgEIAgAAAA==.',
Fi='Finally:BAAANQAECgEIAgAAAA==.Firemage:BAABNQAECn8zAAMIAAoKOSRxHACCAgAIAAkKOiRxHACCAgAJAAQKuSIAIABwAQAAAA==.Fizzanelf:BAAANQAECgEIAwAAAA==.',
Fl='Flaildelyn:BAAANQAECgEIAQAAAA==.Flokíe:BAAANQADCggICAAAAA==.',
Fo='Fortytwo:BAAANQAECggIEAAAAA==.',
Fr='Freyá:BAAANQAECgEIAgAAAA==.Frostbight:BAABNQAECn8qAAIHAAkKjhcqmgBMAgAHAAkKjhcqmgBMAgAAAA==.Frostied:BAABNQAECn8gAAMgAAkKBCAOGgAGAgAgAAkKeR8OGgAGAgAkAAUKrBoxTQCCAQAAAA==.Frostyduggo:BAABNQAECn8tAAIOAAgKHgyjFgBIAQAOAAgKHgyjFgBIAQAAAA==.',
Fu='Futnuraz:BAAANQAECgEIAgAAAA==.',
Fy='Fyrakkobama:BAAANQAECgYIBgABNQAECggIDgAFAAAAAA==.Fyriat:BAABNQAECn8lAAIOAAcKjAx+EQA0AQAOAAcKjAx+EQA0AQAAAA==.',
Ga='Galathel:BAABNQAECn8xAAMUAAkK+BNGIQAwAQAUAAgKBRNGIQAwAQATAAEK+gsR3wA0AAABNQAECgoKOAAXAD0dAA==.Gavreel:BAAANQAECgQIBQAAAA==.Gazardiel:BAABNQAECn8mAAICAAkK8wV6ygADAQACAAkK8wV6ygADAQAAAA==.',
Ge='Gelinia:BAABNQAECn8tAAMZAAkK/ApPHgBcAQAZAAkK/ApPHgBcAQAjAAEKUwFvMwAYAAAAAA==.Gerrald:BAAANQAECgYIBgABNQAECgoKJgADAHYWAA==.Getafix:BAABNQAECn8YAAIGAAgK1Q0cMQBGAQAGAAgK1Q0cMQBGAQABNQAECgoKOAAXAD0dAA==.',
Gh='Ghozthappenz:BAAANQABCgIIAgABNQAECgkJLgAgAHESAA==.Ghrass:BAAANQADCgQIBQAAAA==.',
Gi='Girthquakes:BAAANQAECgEIAQAAAA==.',
Gl='Glorbo:BAABNQAECn8lAAQTAAcKgh5FKgBPAgATAAcKgh5FKgBPAgACAAEKsBGiXwE9AAAUAAEK4BbYagA9AAAAAA==.',
Go='Goliath:BAABNQAECn8XAAMXAAYKtRVTjQBoAQAXAAYKtRVTjQBoAQASAAUKWBDftAAoAQAAAA==.',
Gr='Gregoron:BAAANQADCgEIAQAAAA==.Grimfelborn:BAACNQAFFH8TAAQIAAYK1AvlEgDkAAAIAAQK7Q3lEgDkAAAJAAIKlwRFBwBxAAAKAAEKAAArEwA6AAA1AAQKfzQABAgACgocG3FNAGwCAAgACgocG3FNAGwCAAkAAgr9F1YUAJ0AAAoAAgqDDzAnAE8AAAAA.Grimosh:BAAANQAECgEIAQAAAA==.Grondosh:BAAANQAECgUIDgAAAA==.Gryphindor:BAABNQAECn8UAAIDAAcKwAkbugCPAQADAAcKwAkbugCPAQAAAA==.',
Ha='Hahwe:BAAANQADCgIIAwABNQAECggIFgAIAGcDAA==.Halarius:BAAANQADCgEIAQAAAA==.Haljo:BAAANQADCgQJBQAAAA==.Hanoverfiste:BAABNQAECn8aAAICAAUKwwdN8gDEAAACAAUKwwdN8gDEAAAAAA==.Hapsburg:BAABNQAECn81AAMWAAkKjRBvEADHAQAWAAkKjRBvEADHAQAQAAgKNAh/LQD4AAAAAA==.Harahel:BAAANQAECgQIBAAAAA==.Havince:BAABNQAECn8sAAIgAAkKtiLjEQBmAgAgAAkKtiLjEQBmAgAAAA==.Hawktuah:BAAANQAECgEIAgAAAA==.Haylee:BAAANQADCgEIAgAAAA==.',
He='Helbreder:BAAANQADCgYIBgAAAA==.Helle:BAAANQAECgIIAgAAAA==.Hercbooyy:BAAANQADCgQIBAABNQAECggIKAATAGQjAA==.Hercboyy:BAABNQAECn8oAAMTAAgKZCN2GgANAwATAAcKgSZ2GgANAwAUAAUKORYCMQDGAAAAAA==.',
Hi='Higgs:BAAANQADCggICwABNQAECgoKMgATAPgbAA==.Higgspally:BAABNQAECn8yAAITAAoK+BuZEQAFAwATAAoK+BuZEQAFAwAAAA==.',
Ho='Holyball:BAABNQAECn84AAICAAoKJB2uJwCcAgACAAoKJB2uJwCcAgAAAA==.Holytalon:BAAANQADCgIIAgAAAA==.Hotak:BAAANQABCgYIBAAAAA==.',
Hu='Hughjahsol:BAAANQADCgIIAgAAAA==.Hukaru:BAAANQADCgEIAQABNQAECgkJLAAgALYiAA==.Huuken:BAAANQAECgQIBAAAAA==.Huulkster:BAAANQADCgQIBAAAAA==.',
Hy='Hydra:BAAANQAECgEJAQAAAA==.',
Il='Ilovehunter:BAAANQADCggICAAAAA==.Ilyndra:BAABNQAECn8qAAIcAAcK+yR1CwCEAgAcAAcK+yR1CwCEAgAAAA==.',
In='Infernella:BAAANQADCgMIAwAAAA==.',
Ir='Ironskin:BAAANQAECgUICwAAAA==.',
Is='Iselilja:BAABNQAECn8iAAMdAAgKmQwkZwCSAQAdAAgKggwkZwCSAQAcAAQK6AhhMgCkAAAAAA==.',
It='Ithea:BAABNQAECn86AAIHAAoK1RndPgAtAgAHAAoK1RndPgAtAgAAAA==.',
Ja='Jackshots:BAAANQADCgIIAgAAAA==.Jaeson:BAEBNQAECn8eAAMIAAkKeQ4HWwCJAQAIAAkKeQ4HWwCJAQAKAAEKBwa4MwAsAAAAAA==.Jakaro:BAACNQAFFH8LAAMJAAUK2wdiEgCHAAAJAAIK/ARiEgCHAAAIAAMKugo0LwBKAAA1AAQKfyMAAwkACQqwFRcrACUBAAgABwoqF31pAGABAAkABQovERcrACUBAAAA.Janklin:BAAANQADCgEIAQABNQAECgoKHAAXAJEbAA==.Javoren:BAAANQADCgcIBwABNQAECgUIBQAFAAAAAA==.',
Je='Jeefgpt:BAAANQAECgEIAQABNQAECggIDgAFAAAAAA==.Jeefrenzy:BAAANQAECggIDgAAAA==.Jeefwrld:BAAANQAECgYICQAAAA==.Jeffers:BAAANQAECgEIAgABNQAECggIDgAFAAAAAA==.Jeffha:BAAANQADCggICAAAAA==.',
Ji='Jiinx:BAABNQAECn8qAAMDAAcK3Ra/gQAJAgADAAcK3Ra/gQAJAgALAAUKrwtMTQD8AAAAAA==.',
Jo='Joap:BAAANQAECgYIBgAAAA==.Joejr:BAABNQAECn83AAMZAAoKsxQmEQAQAgAZAAoKsxQmEQAQAgABAAgKhhT9bQDUAQAAAA==.Jonald:BAABNQAECn8cAAIEAAoK9gt4MwCmAQAEAAoK9gt4MwCmAQAAAA==.',
Jt='Jtizlfrizl:BAABNQAECn8eAAIMAAUKQhUuIwABAQAMAAUKQhUuIwABAQAAAA==.',
Ju='Judge:BAAANQADCggIEQABNQAECggINQATAJohAA==.Juniperz:BAABNQAECn8uAAIgAAkKcRJPKQCNAQAgAAkKcRJPKQCNAQAAAA==.',
Ka='Kaaydenn:BAABNQAECn8mAAQTAAgK8RzjIACJAgATAAcKbh/jIACJAgACAAEKAAC5lAE/AAAUAAEKAABYdwAlAAAAAA==.Kaghro:BAAANQADCgcICAAAAA==.Kalaziel:BAABNQAECn8bAAISAAkK0AZRlAByAQASAAkK0AZRlAByAQAAAA==.Kalimotxo:BAABNQAECn8dAAIiAAoKNRxXEgBmAgAiAAoKNRxXEgBmAgAAAA==.Kamus:BAAANQADCgcIDQAAAA==.Karawyn:BAAANQAECgEIAgABNQADCgQICQAFAAAAAA==.Karelix:BAAANQAECgIIAgAAAA==.Katrichi:BAAANQAECgMIAwAAAA==.Katrishy:BAACNQAFFH8VAAIZAAYKFxQ8BABZAQAZAAYKFxQ8BABZAQA1AAQKfzQAAhkACgruHfQSANMCABkACgruHfQSANMCAAAA.Kayde:BAAANQAECgQICQAAAA==.',
Ke='Keedrid:BAABNQAECn8zAAIPAAoKmB12EgA7AgAPAAoKmB12EgA7AgAAAA==.Kelaeno:BAABNQAECn81AAISAAoKDw0kPQCkAQASAAoKDw0kPQCkAQAAAA==.Kemics:BAAANQAECgMIAwAAAA==.Kev:BAACNQAFFH8OAAITAAMKeRsbFgD/AAATAAMKeRsbFgD/AAA1AAQKfzQAAhMACgryI7IEAKsDABMACgryI7IEAKsDAAAA.',
Ki='Kirima:BAAANQADCggICAAAAA==.Kirmit:BAAANQAECgQIBAAAAA==.',
Kl='Klevege:BAAANQADCgUIBQAAAA==.',
Kn='Knoll:BAAANQAECgIIBAAAAA==.',
Ko='Korta:BAAANQABCggIKgAAAA==.',
Kr='Kreeona:BAABNQAECn84AAIXAAoKPR3kGwCrAgAXAAoKPR3kGwCrAgAAAA==.Kruàlty:BAABNQAECn8dAAMlAAgKXhZvDQBEAgAlAAgKXhZvDQBEAgAGAAMKewgckgCPAAAAAA==.',
Ky='Kyfert:BAAANQAECgQIBgAAAA==.',
La='Laird:BAAANQADCgcICwAAAA==.',
Le='Legreecast:BAAANQAECgEIAgAAAA==.',
Li='Liare:BAACNQAFFH8eAAQKAAcK5RtxAwCmAAAIAAQKxBniGQAnAQAKAAMK5x5xAwCmAAAJAAIKsSDdAwChAAA1AAQKfy8ABAgACgpqJbgKAHcDAAgACgpqJbgKAHcDAAkABgoxHxQXALQBAAoAAwr8InYXANQAAAAA.Liasong:BAAANQAECgQICAAAAA==.Litheliice:BAABNQAECn8zAAIBAAkKMBZZVgAgAgABAAkKMBZZVgAgAgAAAA==.',
Lo='Lodur:BAABNQAECn8jAAIXAAcKgQ1xcAAvAQAXAAcKgQ1xcAAvAQAAAA==.Lonen:BAABNQAECn8fAAImAAcK1BbjGACIAQAmAAcK1BbjGACIAQAAAA==.Losat:BAABNQAECn82AAIcAAoKJQoIEQBsAQAcAAoKJQoIEQBsAQAAAA==.',
Lu='Lukeluke:BAAANQADCgQIBwAAAA==.Luthian:BAAANQAECgQIBQAAAA==.',
Ly='Lyn:BAAANQAECgIIAgAAAA==.',
['Lî']='Lîîght:BAAANQADCggIHgAAAA==.',
Ma='Mac:BAABNQAECn83AAMlAAoKPRXNCQD5AQAlAAoKXxTNCQD5AQAGAAkKmg0OLABoAQAAAA==.Machiato:BAAANQAECgEIAgAAAA==.Mackkie:BAABNQAECn8cAAMWAAYKWhInJQBSAQAWAAYKWhInJQBSAQAQAAYKZQVZSADeAAAAAA==.Madonkadonk:BAABNQAECn8xAAIbAAkKIAhiDQBBAQAbAAkKIAhiDQBBAQAAAA==.Maedai:BAAANQAECgUIDgAAAA==.Maeli:BAAANQAECgEIAQAAAA==.Magladroth:BAAANQADCgEIAQAAAA==.Maldive:BAABNQAECn8sAAQKAAoKpQ80CACSAQAKAAkKNhA0CACSAQAIAAoK+goyvQBSAQAJAAMKnwsMTgCVAAAAAA==.Maligasia:BAAANQADCgIIBQAAAA==.Mallicia:BAABNQAECn9BAAMBAAoKaSIpDwBMAwABAAoKaSIpDwBMAwAZAAgKDQqQIQA+AQAAAA==.Mallika:BAAANQAECgEIAQABNQAECgoKQQABAGkiAA==.Mallistra:BAABNQAECn8kAAIWAAoKmhSTFwAEAgAWAAoKmhSTFwAEAgABNQAECgoKQQABAGkiAA==.Mallwizard:BAAANQAECgUJCgAAAA==.Mandible:BAAANQABCgIIAgAAAA==.Marcille:BAAANQAECgQIBAAAAA==.Martris:BAABNQAECn8WAAICAAcKngRP/wCxAAACAAcKngRP/wCxAAAAAA==.Maryjane:BAAANQAECgMJAwAAAA==.Mashma:BAAANQADCggICAAAAA==.Massoflice:BAAANQAECgYIDwAAAA==.Mawkt:BAAANQADCggIAQAAAA==.Maxblaide:BAAANQAECgYICwAAAA==.',
Me='Melovania:BAAANQADCgIIAgAAAA==.',
Mi='Miami:BAAANQAECgMIBAABNQAFFAcIGAAbAHwaAA==.Milah:BAAANQADCgEIAQAAAA==.Missile:BAAANQAECgQICAABNQAECgcIGgAGAGEgAA==.Misstangy:BAAANQADCgcIFwAAAA==.',
Mo='Moct:BAABNQAECn85AAIUAAoKgSBpBwCwAgAUAAoKgSBpBwCwAgAAAA==.Monikal:BAAANQAECgMIAgAAAA==.',
Mu='Muradox:BAAANQADCgcIBwABNQAECgoKJwAZAEoWAA==.Musashi:BAABNQAECn8+AAIDAAoKjyXXBAC+AwADAAoKjyXXBAC+AwABNQAECgkJLwADAO8mAA==.Muskeg:BAABNQAECn8pAAIgAAgKKxIIVwCXAQAgAAgKKxIIVwCXAQAAAA==.Mustardhunt:BAAANQADCgYICgAAAA==.',
['Mü']='Münchkiné:BAAANQABCggIFwAAAA==.',
Na='Namanari:BAAANQADCgEIAwAAAA==.Naris:BAABNQAECn8WAAIIAAgKZwPeuwCoAAAIAAgKZwPeuwCoAAAAAA==.',
Ne='Necrochade:BAAANQAECgEIAQAAAA==.Neptune:BAABNQAECn8sAAIHAAkKZBmiXwDAAgAHAAkKZBmiXwDAAgAAAA==.',
Ni='Nikra:BAAANQAECgQICAAAAA==.Nishal:BAAANQADCggIGwAAAA==.',
Ny='Nyxaries:BAAANQAECgYIDgAAAA==.',
['Né']='Néwby:BAABNQAECn88AAMmAAoK3R7rBwADAwAmAAoK3R7rBwADAwAlAAcKShA8GAAHAQAAAA==.',
Op='Opalynn:BAAANQAECgEIAQAAAA==.Ophirra:BAAANQADCgEIAQAAAA==.',
Oz='Ozempic:BAAANQAECgQIBAABNQAFFAcIHQAaAAUgAA==.',
Pa='Pablo:BAABNQAECn8jAAICAAoKlRgPZgBpAgACAAoKlRgPZgBpAgAAAA==.Pannacea:BAAANQAECgQIBwABNQAECgoKOAAXAD0dAA==.Patriot:BAAANQAECgIIAQAAAA==.Pawinurbutt:BAAANQADCgQIBAAAAA==.',
Pe='Peppert:BAAANQAECgUICQAAAA==.',
Ph='Phane:BAAANQAECgQIBwAAAA==.',
Po='Pocketheals:BAAANQAECgMIAwAAAA==.Poon:BAAANQAECgQICAAAAA==.',
Pr='Pretzelz:BAAANQADCgcICQAAAA==.',
Pu='Puffer:BAABNQAECn8ZAAIOAAkKzQfJEgAjAQAOAAkKzQfJEgAjAQAAAA==.',
Px='Pxry:BAAANQAECgQIBAAAAA==.',
Py='Pyrrhus:BAAANQAECgQIBAAAAA==.',
Qu='Quam:BAAANQABCggIFgAAAA==.',
Ra='Rabone:BAAANQADCgIJAwAAAA==.Raevyn:BAAANQADCgYIBwAAAA==.Raito:BAABNQAECn8eAAICAAkKHQeIsgArAQACAAkKHQeIsgArAQAAAA==.Rakshasa:BAABNQAECn9HAAQIAAoKTiJiDwBWAwAIAAoKTiJiDwBWAwAJAAMK3w9VRwCqAAAKAAEKIBVUIgBCAAAAAA==.Rano:BAAANQAECgEIAQAAAA==.Rasetsungo:BAABNQAECn8yAAIBAAoKjxYcKgBtAgABAAoKjxYcKgBtAgAAAA==.Raura:BAAANQAECgEIAgAAAA==.Rayala:BAAANQAECggICQAAAA==.',
Re='Redblueblurr:BAAANQAECgYIDgAAAA==.Remi:BAABNQAECn8pAAMBAAoK3RuLJwB8AgABAAoK3RuLJwB8AgAZAAEK+wCSkQAYAAAAAA==.Rev:BAAANQADCgUIBQAAAA==.Reveillark:BAAANQAECgIIAgAAAA==.Revelaiden:BAAANQABCgIIAgABNQAECgkJKwAEAKMbAA==.',
Ri='Rise:BAAANQAECgcIDwAAAA==.',
Ro='Rolan:BAABNQAECn88AAQkAAoKfSWqCwDhAgAkAAoKLCWqCwDhAgAPAAgK2SPFHwDMAgAgAAQKtSOFWwCEAQAAAA==.Rosalian:BAABNQAECn8nAAIeAAkKkhGGIwCLAQAeAAkKkhGGIwCLAQAAAA==.Rotiko:BAABNQAECn8bAAIXAAgKpgXvdgAbAQAXAAgKpgXvdgAbAQAAAA==.Roweene:BAABNQAECn8qAAInAAcK3wObBwCQAAAnAAcK3wObBwCQAAAAAA==.',
['Rá']='Rágnar:BAABNQAECn8uAAMCAAoKkROtdAClAQACAAoKkROtdAClAQAUAAMK0gPyRQBlAAAAAA==.',
Sa='Sabiel:BAABNQAECn8jAAIGAAgKkgZ7QwDmAAAGAAgKkgZ7QwDmAAAAAA==.Sakuta:BAAANQADCgYIBgABNQAECgkJIQAXAOcdAA==.',
Se='Selryth:BAAANQADCgcIBwABNQAECggICwAFAAAAAA==.Serenatee:BAABNQAECn8wAAIZAAkKEQ3gGgCEAQAZAAkKEQ3gGgCEAQAAAA==.',
Sh='Shaedai:BAABNQAECn8iAAMXAAkKKREwQADjAQAXAAkKKREwQADjAQASAAEKPAJKUwEkAAAAAA==.Shagohod:BAAANQADCgQIBAAAAA==.Shakked:BAAANQAECgEIAwAAAA==.Shenanegans:BAAANQADCgEIAQAAAA==.Shinanigans:BAAANQAECgUIBQAAAA==.',
Sk='Skotojar:BAAANQADCgUIBQAAAA==.',
Sn='Snortedgfuel:BAAANQAECgcIEgAAAA==.',
So='Sokroar:BAAANQAECgYICAABNQAFFAYIAQAFAAAAAA==.Solphera:BAAANQADCgUIDAAAAA==.Sonknight:BAAANQAECgUIEgAAAA==.',
Sp='Speedshot:BAAANQADCgUIBwAAAA==.Spicy:BAAANQAECgMIAwAAAA==.Spitefulcrow:BAABNQAECn8lAAIoAAoKCQmSBwBXAQAoAAoKCQmSBwBXAQAAAA==.Spot:BAAANQAECgEIAQAAAA==.',
St='Stardstr:BAAANQADCgMIAwAAAA==.Stealinsoulz:BAAANQADCgYICgAAAA==.Stealsoul:BAAANQADCgIIAgABNQADCgYICgAFAAAAAA==.Sto:BAAANQAECgEIAgAAAA==.Stratof:BAAANQAECgYICwAAAA==.',
Su='Sufferding:BAABNQAECn8iAAIiAAkKeRGkJwCRAQAiAAkKeRGkJwCRAQAAAA==.Suria:BAABNQAECn84AAIeAAoKJCBtBgBKAwAeAAoKJCBtBgBKAwAAAA==.',
Sw='Swytchblade:BAAANQADCggICQAAAA==.',
Sy='Syker:BAAANQADCgIIAgAAAA==.',
Ta='Tahrovin:BAABNQAECn8WAAIEAAgKNBDZNACcAQAEAAgKNBDZNACcAQAAAA==.Talaera:BAAANQADCgEIAQAAAA==.Tavernn:BAAANQABCggILQAAAA==.Taytorchips:BAABNQAECn8yAAMCAAoKewnqwwAOAQACAAkKtgXqwwAOAQATAAUK0wH0EAFVAAAAAA==.',
Th='Thaendrin:BAAANQADCgYICQAAAA==.Thearcane:BAAANQADCgQICAAAAA==.Thedoc:BAAANQAECgUICQAAAA==.Theefjeef:BAAANQAECgYIBQABNQAECggIDgAFAAAAAA==.Thorloim:BAABNQAECn8nAAMXAAgKfyCnRADPAQAXAAgKfyCnRADPAQAVAAMKRA/BKQBuAAAAAA==.Thornx:BAAANQADCgEIAQAAAA==.Throwaway:BAAANQAECgcICAAAAA==.Thundercups:BAABNQAECn8qAAIVAAkKbBSGDwDiAQAVAAkKbBSGDwDiAQAAAA==.',
Ti='Tigersong:BAAANQADCgEIAQAAAA==.Tigerstarr:BAABNQAECn8hAAMkAAoK3hGlNwD4AQAkAAoK3hGlNwD4AQAPAAQKngmxowCzAAAAAA==.Tinyshieva:BAAANQADCgYICQAAAA==.Tizuki:BAAANQAECgQIBAAAAA==.',
To='Tonystandard:BAAANQAECgUICQABNQAFFAUICQAWALcRAA==.',
Tr='Treborlock:BAABNQAECn8xAAMJAAkKDRHBBACDAQAJAAkKDRHBBACDAQAIAAEKmQKSVgEhAAAAAA==.Triplock:BAAANQAECgEJAQAAAA==.Trolcain:BAABNQAECn87AAIPAAoKpyFfCADUAgAPAAoKpyFfCADUAgAAAA==.',
Tw='Twistedspork:BAAANQAECgQICwAAAA==.',
Ul='Ulfal:BAAANQAECgEIAQAAAA==.',
Un='Unbuffed:BAAANQADCgIIAwABNQAECgoKMgATAPgbAA==.',
Ut='Uthon:BAAANQAECgMIAwAAAA==.',
Va='Vaedar:BAAANQAECgEIAQAAAA==.Vagglord:BAAANQAECgQIDwAAAA==.Valha:BAABNQAECn8oAAIiAAkKYg9zLABvAQAiAAkKYg9zLABvAQAAAA==.Vardisk:BAAANQADCgQIBAAAAA==.Varlashard:BAAANQADCggIFQAAAA==.Varteras:BAABNQAECn80AAMKAAkK6hc0BwAuAgAKAAgK2Bc0BwAuAgAIAAYK2QqL8QDnAAAAAA==.',
Ve='Vellron:BAABNQAECn8qAAIDAAoKOAqRXQDHAQADAAoKOAqRXQDHAQAAAA==.Veroque:BAAANQADCgUIBQAAAA==.',
['Và']='Vàsh:BAAANQAECgUICAAAAA==.',
['Vø']='Vødøu:BAABNQAECn8bAAMNAAgKZB/LQACzAQANAAgKIB7LQACzAQAMAAQKABdGYQAwAQAAAA==.',
Wa='Wafflelegend:BAABNQAECn8mAAIiAAgKFiW4CgBaAwAiAAgKFiW4CgBaAwAAAA==.Wardkbriggle:BAABNQAECn8XAAMkAAkKbBrFNQACAgAkAAkKExfFNQACAgAPAAgKsRg0VgC5AQAAAA==.Warint:BAABNQAECn8WAAICAAcK2gWoFgH5AAACAAcK2gWoFgH5AAAAAA==.Wartiger:BAABNQAFFH8GAAIRAAYKKyC8AADWAQARAAYKKyC8AADWAQAAAA==.',
We='Weeble:BAAANQADCgMIBAAAAA==.Welish:BAAANQADCgEIAQAAAA==.',
Wi='Wifi:BAABNQAECn8vAAICAAgK9CTmRAAoAgACAAgK9CTmRAAoAgAAAA==.',
Wo='Wolfdude:BAAANQAECggICQAAAA==.',
Wy='Wydge:BAABNQAECn8lAAIHAAcKrQ9UsgAWAQAHAAcKrQ9UsgAWAQAAAA==.Wyven:BAACNQAFFH8FAAIkAAIKUBZiEACfAAAkAAIKUBZiEACfAAA1AAQKfzQAAw8ACgqqIswPADgDAA8ACQrrIswPADgDACQABApMGrVJADEBAAE1AAMKBwgLAAUAAAAA.',
Xa='Xanddoria:BAABNQAECn80AAMNAAoKDyFKDwDhAgANAAoKEx9KDwDhAgAMAAcKtCImHgCPAgAAAA==.Xaoc:BAABNQAECn8UAAIQAAcKEhV1KgDJAQAQAAcKEhV1KgDJAQAAAA==.',
Xh='Xhared:BAABNQAECn8nAAIgAAcK4h8lOwAYAgAgAAcK4h8lOwAYAgAAAA==.',
Xo='Xochital:BAAANQADCgEIAQAAAA==.',
Ye='Yellodur:BAAANQADCgIIAgAAAA==.Yesenia:BAAANQADCgYICwAAAA==.',
Yu='Yunah:BAAANQADCgYIBgAAAA==.',
Ze='Zephy:BAABNQAECn8ZAAIdAAUKzgkLuQDQAAAdAAUKzgkLuQDQAAAAAA==.',
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
