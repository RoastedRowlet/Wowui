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

local lookup = {'Priest-Holy','Paladin-Retribution','Hunter-BeastMastery','DemonHunter-Devourer','Druid-Balance','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Mage-Frost','DeathKnight-Unholy','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Monk-Mistweaver','Shaman-Restoration','DemonHunter-Vengeance','Priest-Shadow','Unknown-Unknown','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Warrior-Arms','Druid-Restoration','Warrior-Fury','DeathKnight-Blood','Evoker-Augmentation','DemonHunter-Havoc','DeathKnight-Frost','Druid-Feral','Priest-Discipline','Druid-Guardian','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aaronius:BAABNQAECn8WAAIBAAcKagEjlwChAAABAAcKagEjlwChAAAAAA==.',
Ab='Abrahm:BAAANQABCgIIAgAAAA==.',
Ac='Acceptance:BAABNQAFFH8FAAICAAUK3g6FDgDSAAACAAUK3g6FDgDSAAAAAA==.',
Ad='Adoe:BAABNQAECn8hAAIDAAcKfRwubwAzAgADAAcKfRwubwAzAgAAAA==.Adora:BAAANQAECgMJBwAAAA==.',
Ae='Aeveen:BAAANQAECgEIAQAAAA==.',
Ag='Agaliarept:BAAANQADCgMIAwAAAA==.Agathos:BAAANQAECgEIAQAAAA==.',
Ai='Aidenator:BAABNQAECn8jAAIEAAgKmh38EwCtAQAEAAgKmh38EwCtAQAAAA==.',
Al='Aluni:BAAANQADCgEIAQAAAA==.',
Am='Ammastin:BAAANQABCgMIAwAAAA==.',
An='Andorix:BAAANQAECgQICAAAAA==.Andretta:BAAANQAECgMIBQAAAA==.Angelneko:BAABNQAECn8mAAIFAAcKrAboQADBAAAFAAcKrAboQADBAAAAAA==.Annihilaiden:BAAANQAECgIIBQABNQAECggIIwAEAJodAA==.',
Ar='Arinthian:BAAANQAECgUIDAAAAA==.Artrian:BAABNQAECn8dAAIBAAgKAxfHMgDyAQABAAgKAxfHMgDyAQAAAA==.',
At='Atetoomuch:BAAANQAECgEIAQAAAA==.Atthis:BAAANQADCgEIAQAAAA==.',
Au='Auroraa:BAABNQAECn8WAAIFAAYKYQnbTQCOAAAFAAYKYQnbTQCOAAAAAA==.Auyniko:BAAANQAECggIDwAAAA==.',
Av='Avalectra:BAAANQAECgEIAQAAAA==.Avdakedavra:BAAANQAECgEIAQAAAA==.',
Az='Azmodeaz:BAABNQAECn8sAAIGAAgK+Q647wCrAQAGAAgK+Q647wCrAQAAAA==.Azraely:BAAANQADCgcIBwAAAA==.Aztrik:BAABNQAECn8fAAQHAAgKJB8ZWABOAgAHAAcKKB8ZWABOAgAIAAIKCSEmDwClAAAJAAIK8yNaFABhAAAAAA==.',
Ba='Bajapanti:BAABNQAECn8uAAIKAAoKzg/ODQDyAQAKAAoKzg/ODQDyAQAAAA==.Ballyhøø:BAACNQAFFH8FAAIFAAIKHQzEEQCOAAAFAAIKHQzEEQCOAAA1AAQKfxwAAgUACgpKFkwwAF8CAAUACgpKFkwwAF8CAAAA.Bandaron:BAAANQAECgQIBAAAAA==.Barload:BAAANQAECgEIAQAAAA==.Baxstab:BAABNQAECn8yAAMLAAkKoxa1CQDtAQALAAkKoxa1CQDtAQAMAAIKMgo+SQBwAAAAAA==.',
Be='Beelzebrad:BAAANQAECgQIBAAAAA==.Belladeon:BAABNQAECn8mAAMNAAoKchWxCwAEAgANAAgKuxaxCwAEAgAGAAgK0Qef8wCkAQAAAA==.Betrubt:BAAANQAECgcIEQABNQAECgkJFgAOAFgVAA==.',
Bh='Bhagee:BAAANQADCgUICgAAAA==.',
Bi='Bivouac:BAAANQAECgEIAQAAAA==.',
Bl='Blackpatch:BAABNQAECn8xAAMPAAkKWRnjGAB/AgAPAAkKWRnjGAB/AgAQAAQKXANuJwCNAAAAAA==.Blacksheep:BAAANQADCggIAQAAAA==.Blaqkid:BAAANQADCgYIBgAAAA==.Blaqsun:BAABNQAECn8pAAIRAAkKZQ9RNgB9AQARAAkKZQ9RNgB9AQAAAA==.Blargg:BAAANQAECgUICQAAAA==.Bleeda:BAAANQADCggIAQAAAA==.Blightmaker:BAAANQAECgcIBwAAAA==.Bloomhammer:BAAANQAECgEIAQAAAA==.Blooming:BAABNQAECn8uAAISAAgKBR43JwAWAgASAAgKBR43JwAWAgAAAA==.',
Bo='Booneboy:BAABNQAECn8ZAAQCAAUK6R2TqwDIAQACAAUK6R2TqwDIAQASAAEK/hPcvQA9AAATAAEKjgmXTwAsAAAAAA==.Botemedel:BAABNQAECn8lAAITAAkKmhjhDADXAQATAAkKmhjhDADXAQABNQAFFAUIDAAUADEGAA==.Bowtox:BAAANQADCggICgAAAA==.Bowyourhead:BAAANQAECgEIAQAAAA==.',
Br='Brennor:BAABNQAECn8xAAICAAgKnAgKnQAaAQACAAgKnAgKnQAaAQAAAA==.Brewslunt:BAABNQAECn8fAAIVAAoKzhoWDwCPAgAVAAoKzhoWDwCPAgABNQAFFAYIFgAWAOMZAA==.Bronamaly:BAAANQADCgYICAAAAA==.',
Ca='Cabbagehunt:BAAANQADCgcIEwAAAA==.Caeden:BAABNQAECn8sAAIWAAkKBg5/QQCRAQAWAAkKBg5/QQCRAQAAAA==.Cairyan:BAABNQAECn8mAAIXAAkKNxiQCABsAgAXAAkKNxiQCABsAgAAAA==.Caiya:BAAANQADCgcIDgABNQAECgkJKwAMADIhAA==.Cassin:BAAANQAECgIIAgAAAA==.Castalia:BAABNQAECn8ZAAIYAAUK/Ax/JQDaAAAYAAUK/Ax/JQDaAAAAAA==.Cattilina:BAAANQADCggIEAAAAA==.',
Ce='Celenara:BAACNQAFFH8LAAIGAAQK7xLGFgDtAAAGAAQK7xLGFgDtAAA1AAQKfyoAAwYACgo6HhphALwCAAYACgo6HhphALwCAA0AAgohC584AFsAAAAA.Celendil:BAAANQADCgUIBQABNQAFFAQICwAGAO8SAA==.Celinne:BAAANQADCgUIBQAAAA==.Celithe:BAAANQAECgUICgAAAA==.',
Ch='Charlereaux:BAAANQAECgEIAQAAAA==.Charmcaster:BAABNQAECn8fAAIGAAgKLhj9YgCGAQAGAAgKLhj9YgCGAQAAAA==.Charmstrike:BAAANQAECggIDQAAAA==.Chedissa:BAAANQAECgEIAQABNQAECgEIAQAZAAAAAA==.Chleo:BAABNQAECn8aAAIBAAYKxgfnegDmAAABAAYKxgfnegDmAAAAAA==.Choco:BAACNQAFFH8dAAIaAAcKBSAmAgCbAgAaAAcKBSAmAgCbAgA1AAQKfy8AAxoACgrkHyMJABEDABoACgrkHyMJABEDABsAAgpUF9gyAHkAAAAA.Chocolat:BAAANQADCggICAABNQAFFAcIHQAaAAUgAA==.Chocolight:BAAANQAECgIIAgABNQAFFAcIHQAaAAUgAA==.Chudfox:BAAANQADCgEJAQAAAA==.',
Co='Coggler:BAABNQAECn8VAAMcAAYK3xQAGgCVAQAcAAYK3xQAGgCVAQAdAAUKtgwB6wAOAQAAAA==.Conqueror:BAAANQAECgYICQABNQAECgoKHAAeAEMOAA==.Corcia:BAAANQAECgIIAwAAAA==.',
Cr='Creatlach:BAAANQAECgIIAwABNQAFFAYIFgAWAOMZAA==.Crotchpox:BAAANQADCgQIBAAAAA==.Crualti:BAABNQAECn8aAAMfAAgKnweVIAC2AAAfAAQKegmVIAC2AAAdAAgKXgXqrACyAAAAAA==.',
Cu='Cuppajoe:BAAANQADCgMIAwAAAA==.Cupper:BAAANQABCgcJCQABNQAECgUIFQACALUGAA==.Curmudge:BAABNQAECn87AAIeAAoKSBgDDgBNAgAeAAoKSBgDDgBNAgAAAA==.',
Da='Dabtoomuch:BAAANQABCgIIAgAAAA==.Daimhin:BAAANQADCgcIBwAAAA==.Dalectra:BAAANQAECgQICwAAAA==.Darachane:BAAANQAECgQIBgAAAA==.Darkpriest:BAAANQAECgIIAgAAAA==.Darovan:BAAANQADCggJEAABNQAECgcIJwAgAOIfAA==.Darthnater:BAABNQAECn8dAAIOAAkKnB3UBgDGAgAOAAkKnB3UBgDGAgAAAA==.Dauglow:BAABNQAECn8xAAMDAAgKhBDjdgAiAgADAAgKhBDjdgAiAgAKAAEKhwnmhQA4AAAAAA==.',
De='Deathball:BAAANQAECgEIAQAAAA==.Deathstars:BAAANQADCgcIEwAAAA==.Deboss:BAAANQAECggIDgAAAA==.Dellianne:BAAANQABCgEIAQAAAA==.Delritha:BAAANQAECgUICwAAAA==.Deltithrax:BAABNQAECn8mAAMhAAcKkA8ADwBSAQAhAAYKPxEADwBSAQAbAAcKaA0mDgD2AAAAAA==.Demonagent:BAABNQAECn8YAAMXAAYKzxXnFABeAQAXAAYKzxXnFABeAQAiAAMKtw5XbwC8AAAAAA==.Desdh:BAACNQAFFH8MAAMiAAQKXBXqEQDWAAAiAAMKXBXqEQDWAAAEAAIK4gcHDQBJAAA1AAQKfy8AAyIACgrMIccaAMQCACIACgoSIccaAMQCAAQAAwp8HiomAPYAAAAA.Devious:BAAANQAECgYIBwABNQAECggILgASAAUeAA==.',
Di='Dinö:BAAANQAECgMJBAABNQAECgoKIAADAGkWAA==.',
Dm='Dmnslyer:BAAANQADCggIDQAAAA==.',
Do='Docspades:BAABNQAECn8jAAIBAAcK3hUSSgCJAQABAAcK3hUSSgCJAQAAAA==.Dohane:BAAANQADCgQIBAABNQAECggIFQAEADQQAA==.Domrogue:BAAANQAECggIDwAAAA==.Dornoch:BAAANQAECgEIAQAAAA==.',
Dr='Dramine:BAAANQADCgQIBwAAAA==.Draone:BAABNQAECn8qAAIGAAkK1AotZQCAAQAGAAkK1AotZQCAAQAAAA==.Dreabolic:BAAANQADCgYICwAAAA==.Dreamss:BAABNQAECn8xAAMiAAoKyhTBLwApAgAiAAoKyhTBLwApAgAEAAgKvAY4OQB7AQAAAA==.Drhkillinger:BAAANQAECgYICAABNQAECgYIGAAXAM8VAA==.Drspades:BAAANQAECgEIAQAAAA==.',
Du='Dugosh:BAAANQADCggIDAAAAA==.Duzz:BAAANQAECgEIAwAAAA==.',
['Dé']='Démetal:BAAANQADCggIDgAAAA==.',
Ei='Einherja:BAABNQAECn8cAAQgAAoKTRpzLgA1AQAOAAYKexj4aQBqAQAjAAcKZRG3XAA2AQAgAAUK8hpzLgA1AQAAAA==.',
El='Elessaria:BAABNQAECn8ZAAIeAAUKGAkyNwDAAAAeAAUKGAkyNwDAAAAAAA==.Elfatheàrt:BAAANQAECgEIAQAAAA==.Elidrus:BAAANQADCgYICgABNQAECggIEQAZAAAAAA==.Elsen:BAAANQAECgEIAQAAAA==.',
En='Enodlo:BAAANQADCgUIBQAAAA==.',
Er='Erora:BAABNQAECn8nAAIYAAoKShYGGgB9AgAYAAoKShYGGgB9AgAAAA==.Eryndor:BAAANQAECgEIAQABNQAECggIEQAZAAAAAA==.',
Es='Estherras:BAABNQAECn8eAAIDAAYK6hRAcgBRAQADAAYK6hRAcgBRAQAAAA==.',
Fe='Feardotrun:BAABNQAECn8gAAMIAAcKihBZOADfAAAHAAcKihCTrwByAQAIAAQKewtZOADfAAAAAA==.Felicious:BAAANQAECgEIAQAAAA==.',
Fi='Finally:BAAANQAECgEIAQAAAA==.Firemage:BAABNQAECn8xAAMHAAoKOSQLEQCgAgAHAAkKOiQLEQCgAgAIAAQKuSIAIABwAQAAAA==.Fizzanelf:BAAANQAECgEIBAAAAA==.',
Fl='Flaildelyn:BAAANQAECgEIAQAAAA==.Flokíe:BAAANQADCggICAAAAA==.',
Fo='Fortytwo:BAAANQAECggIEwAAAA==.',
Fr='Freyá:BAAANQAECgEIBAAAAA==.Friendo:BAABNQAECn8tAAMFAAkKmg2mIQB3AQAFAAkKmg2mIQB3AQAkAAEK8AjPSAAoAAAAAA==.Frostbight:BAABNQAECn8mAAIGAAkKvhYqmgBMAgAGAAkKvhYqmgBMAgAAAA==.Frostied:BAABNQAECn8ZAAMgAAkKTx8yFgDvAQAgAAkKsh4yFgDvAQAjAAUKbxkxTQCCAQAAAA==.Frostyduggo:BAABNQAECn8qAAINAAcKKg2jFgBIAQANAAcKKg2jFgBIAQAAAA==.',
Fu='Futnuraz:BAAANQAECgEIAQAAAA==.',
Fy='Fyrakkobama:BAAANQAECgYICAABNQAECggIDgAZAAAAAA==.Fyriat:BAABNQAECn8eAAINAAYKoQ0FGgAlAQANAAYKoQ0FGgAlAQAAAA==.',
Ga='Galathel:BAABNQAECn8pAAMTAAkKpxOmGwAfAQATAAgKBROmGwAfAQASAAEK1geBzAAvAAABNQAECgkJLgAWABMdAA==.Gavreel:BAAANQAECgQIBAAAAA==.Gazardiel:BAABNQAECn8fAAICAAkK8wX9oAATAQACAAkK8wX9oAATAQAAAA==.',
Ge='Gelinia:BAABNQAECn8lAAMYAAgKHQuGIQD7AAAYAAgKHQuGIQD7AAAlAAEKUwFvMwAYAAAAAA==.Gerrald:BAAANQADCgUIBAABNQAECgoKIAADAGkWAA==.Getafix:BAAANQAECgYIEQABNQAECgkJLgAWABMdAA==.',
Gh='Ghozthappenz:BAAANQAECgIIBAABNQAECggIJgAgAAERAA==.Ghrass:BAAANQADCgQIBQAAAA==.',
Gi='Girthquakes:BAAANQAECgEIBAAAAA==.',
Gl='Glorbo:BAABNQAECn8eAAQSAAYKcR8UKwD/AQASAAYKcR8UKwD/AQACAAEKsBHFNwE9AAATAAEK4BbYagA9AAAAAA==.',
Go='Goldstorm:BAAANQAECgEIAQAAAA==.Goliath:BAABNQAECn8XAAMWAAYKtRVTjQBoAQAWAAYKtRVTjQBoAQARAAUKWBDftAAoAQAAAA==.',
Gr='Greengodess:BAAANQAECgEIAQAAAA==.Gregoron:BAAANQAECgEIAQAAAA==.Grimfelborn:BAACNQAFFH8OAAQIAAUK9QqZBQB5AAAHAAMKqw1nHACEAAAIAAIKlwSZBQB5AAAJAAEKAAArEwA6AAA1AAQKfy4ABAcACgpSGnFNAGwCAAcACgpSGnFNAGwCAAkAAQoAADAnAE8AAAgAAQoTFTwgAE0AAAAA.Grimosh:BAAANQAECgEIAgAAAA==.Grondosh:BAAANQAECgYICgAAAA==.Gryphindor:BAABNQAECn8UAAIDAAcKwAkbugCPAQADAAcKwAkbugCPAQAAAA==.',
['Gì']='Gìorgìa:BAAANQAECgEIAwAAAA==.',
Ha='Hahwe:BAAANQADCgIIAgABNQAECggIEQAZAAAAAA==.Haljo:BAAANQADCgQJBAAAAA==.Hanoverfiste:BAABNQAECn8VAAICAAUKtQb93gCtAAACAAUKtQb93gCtAAAAAA==.Hapsburg:BAABNQAECn8xAAMVAAgKFw6+FAAtAQAVAAgKFw6+FAAtAQAPAAgKNAjkJAD9AAAAAA==.Harahel:BAAANQAECgQIBAAAAA==.Havince:BAABNQAECn8oAAIgAAgKbiIqGQDkAgAgAAgKbiIqGQDkAgAAAA==.Hawktuah:BAAANQAECgEIBAAAAA==.Haylee:BAAANQAECgEIAgAAAA==.',
He='Helbreder:BAAANQADCgYIBgAAAA==.Helle:BAAANQAECgIIBAAAAA==.Hercboyy:BAABNQAECn8kAAMSAAgKZCN2GgANAwASAAcKgSZ2GgANAwATAAEKAAADYgBVAAAAAA==.',
Hi='Higgs:BAAANQAECgEIAgABNQAECgkJLQASAA4cAA==.Higgspally:BAABNQAECn8tAAISAAkKDhxJEADRAgASAAkKDhxJEADRAgAAAA==.',
Ho='Holyball:BAABNQAECn8vAAICAAoKBRriNgAdAgACAAoKBRriNgAdAgAAAA==.Holytalon:BAAANQADCgIIAgAAAA==.Hotak:BAAANQAECgEIAQAAAA==.',
Hu='Hughjahsol:BAAANQADCgIIAgAAAA==.Hukaru:BAAANQABCgIIAgABNQAECggIKAAgAG4iAA==.Huuken:BAAANQAECgQIBAAAAA==.Huulkster:BAAANQADCgQIBAAAAA==.',
Hy='Hydra:BAAANQAECgEJAQAAAA==.',
Il='Ilovehunter:BAAANQADCggICAAAAA==.Ilyndra:BAABNQAECn8mAAIcAAcK+yR1CwCEAgAcAAcK+yR1CwCEAgAAAA==.',
In='Infernella:BAAANQADCgMIAwAAAA==.',
Ir='Ironskin:BAAANQAECgUIEwAAAA==.',
Is='Iselilja:BAABNQAECn8aAAMdAAcKGg2tZwBOAQAdAAcK/wytZwBOAQAcAAQK6AhhMgCkAAAAAA==.',
It='Ithea:BAABNQAECn81AAIGAAoKzxiNOgAJAgAGAAoKzxiNOgAJAgAAAA==.',
Ja='Jackshots:BAAANQADCgIIAgAAAA==.Jaeson:BAEBNQAECn8aAAMHAAgK0g0+VgBgAQAHAAgK0g0+VgBgAQAJAAEKBwa4MwAsAAAAAA==.Jakaro:BAACNQAFFH8KAAMIAAQK2gdiEgCHAAAIAAIK/ARiEgCHAAAHAAIKlg0bQABLAAA1AAQKfx4AAwgACQoWExcrACUBAAgABQovERcrACUBAAcABwqyE7R1AA4BAAAA.Javoren:BAAANQADCgcIBwABNQAECgUIBQAZAAAAAA==.',
Je='Jeefgpt:BAAANQAECgEIAQABNQAECggIDgAZAAAAAA==.Jeefrenzy:BAAANQAECggIDgAAAA==.Jeefwrld:BAAANQAECgYICQAAAA==.Jeffers:BAAANQAECgEIAwABNQAECggIDgAZAAAAAA==.Jeffha:BAAANQADCggICAAAAA==.',
Ji='Jiinx:BAABNQAECn8mAAMDAAcK3Ra/gQAJAgADAAcK3Ra/gQAJAgAKAAUKrwtMTQD8AAAAAA==.',
Jo='Joap:BAAANQAECgYIBgAAAA==.Joejr:BAABNQAECn8tAAMBAAkKiRT9bQDUAQABAAgKhhT9bQDUAQAYAAgKpBYnEwCYAQAAAA==.Jonald:BAABNQAECn8cAAIEAAoK9gt4MwCmAQAEAAoK9gt4MwCmAQAAAA==.',
Jt='Jtizlfrizl:BAABNQAECn8ZAAILAAUKJxTDIAD+AAALAAUKJxTDIAD+AAAAAA==.',
Ju='Judge:BAAANQADCgEIAQABNQAECggILgASAAUeAA==.Juniperz:BAABNQAECn8mAAIgAAgKAREwLgA3AQAgAAgKAREwLgA3AQAAAA==.',
Jw='Jwise:BAAANQAECggIAgAAAA==.',
Ka='Kaaydenn:BAABNQAECn8gAAQSAAgKIRsgHABiAgASAAcKXB0gHABiAgACAAEKAAC5lAE/AAATAAEKAABYdwAlAAAAAA==.Kaghro:BAAANQADCgcICAAAAA==.Kalaziel:BAABNQAECn8XAAIRAAkKLAZRlAByAQARAAkKLAZRlAByAQAAAA==.Kalierix:BAABNQAECn8bAAIiAAoKqhoIDgBsAgAiAAoKqhoIDgBsAgAAAA==.Kamus:BAAANQAECgEIAQAAAA==.Karawyn:BAAANQAECgEIAgABNQADCgQICAAZAAAAAA==.Karelix:BAAANQADCgMIBwAAAA==.Katrichi:BAAANQAECgIIBQAAAA==.Katrishy:BAACNQAFFH8QAAIYAAUKdBNeBgD1AAAYAAUKdBNeBgD1AAA1AAQKfy4AAhgACgoqHPQSANMCABgACgoqHPQSANMCAAAA.Kayde:BAAANQAECgQICQAAAA==.',
Ke='Keedrid:BAABNQAECn8tAAIOAAkKdB1qJwCdAgAOAAkKdB1qJwCdAgAAAA==.Kelaeno:BAABNQAECn8rAAIRAAkKDg2GNwB3AQARAAkKDg2GNwB3AQAAAA==.Kev:BAACNQAFFH8NAAISAAMKeRsbFgD/AAASAAMKeRsbFgD/AAA1AAQKfzAAAhIACgryI7IEAKsDABIACgryI7IEAKsDAAAA.',
Ki='Kirima:BAAANQADCggICAAAAA==.Kirmit:BAAANQAECgQIBwAAAA==.',
Kl='Klevege:BAAANQADCgUIBQAAAA==.',
Kn='Knoll:BAAANQAECgIIBgAAAA==.',
Ko='Korta:BAAANQAECgEIAQAAAA==.',
Kr='Kreeona:BAABNQAECn8uAAIWAAkKEx31GwBiAgAWAAkKEx31GwBiAgAAAA==.Kruàlty:BAABNQAECn8dAAMkAAgKXhZvDQBEAgAkAAgKXhZvDQBEAgAFAAMKewgckgCPAAAAAA==.',
La='Laird:BAAANQADCgcICwAAAA==.',
Le='Legreecast:BAAANQAECgEIAQAAAA==.',
Li='Liare:BAACNQAFFH8cAAQJAAYKpiBuAQC3AAAHAAMKNyLiGQAnAQAJAAMK5x5uAQC3AAAIAAIKsSCdAgCuAAA1AAQKfy0ABAcACgpqJbgKAHcDAAcACgpqJbgKAHcDAAgABgoxHxQXALQBAAkAAgqZJXYXANQAAAAA.Liasong:BAAANQAECgUICwAAAA==.Litheliice:BAABNQAECn8xAAIBAAgKYRdZVgAgAgABAAgKYRdZVgAgAgAAAA==.',
Lo='Lodur:BAABNQAECn8cAAIWAAYKUA6DaQABAQAWAAYKUA6DaQABAQAAAA==.Lonen:BAABNQAECn8YAAImAAYKVxaQGgA3AQAmAAYKVxaQGgA3AQAAAA==.Losat:BAABNQAECn8sAAIcAAkKJAhbEQAkAQAcAAkKJAhbEQAkAQAAAA==.',
Lu='Luckx:BAAANQAECgEIAgAAAA==.Lukeluke:BAAANQADCgQIBwAAAA==.Luthian:BAAANQAECgEIAQAAAA==.',
Ly='Lyn:BAAANQAECgIIAgAAAA==.',
['Lî']='Lîîght:BAAANQADCggIHgAAAA==.',
Ma='Machiato:BAAANQAECgEIAQAAAA==.Mackkie:BAABNQAECn8cAAMVAAYKWhInJQBSAQAVAAYKWhInJQBSAQAPAAYKZQVZSADeAAAAAA==.Madonkadonk:BAABNQAECn8tAAIbAAgK4QdKDAAbAQAbAAgK4QdKDAAbAQAAAA==.Maedai:BAAANQAECgUIEwAAAA==.Maeli:BAAANQAECgEIAQAAAA==.Magladroth:BAAANQABCgQJBAAAAA==.Maldive:BAABNQAECn8qAAQJAAkKBhE6BAC/AQAJAAkKNhA6BAC/AQAHAAgKsQsyvQBSAQAIAAMKnwsMTgCVAAAAAA==.Maligasia:BAAANQADCgIIAwAAAA==.Mallicia:BAABNQAECn85AAMBAAoK/CEpDwBMAwABAAoK/CEpDwBMAwAYAAgKDQqOGQBEAQAAAA==.Mallika:BAAANQAECgEIAQABNQAECgoKOQABAPwhAA==.Mallistra:BAABNQAECn8iAAIVAAoKbROTFwAEAgAVAAoKbROTFwAEAgABNQAECgoKOQABAPwhAA==.Mallwizard:BAAANQAECgUJCwAAAA==.Mandible:BAAANQAECgEIAQAAAA==.Marcille:BAAANQAECgQIBAAAAA==.Martris:BAAANQAECgYIEgAAAA==.Maryjane:BAAANQAECgMJAwAAAA==.Mashma:BAAANQADCggICAAAAA==.Massoflice:BAAANQAECgYIEAAAAA==.Mawkt:BAAANQADCggIAQAAAA==.Maxblaide:BAAANQAECgYICQAAAA==.Maxentia:BAAANQAECgEIAQAAAA==.',
Me='Melovania:BAAANQADCgIIAgAAAA==.',
Mi='Miami:BAAANQAECgMIBAABNQAFFAcIFwAbAHwaAA==.Milah:BAAANQABCgIIAgAAAA==.Missile:BAAANQAECgQIDAABNQAECgcIGQAFAFsgAA==.Misstangy:BAAANQADCgcIFwAAAA==.',
Mo='Moct:BAABNQAECn8vAAITAAkK0h96CgDzAgATAAkK0h96CgDzAgAAAA==.Monikal:BAAANQAECgIIAgAAAA==.',
Mu='Muradox:BAAANQADCgcIBwABNQAECgoKJwAYAEoWAA==.Musashi:BAABNQAECn88AAIDAAoKmSTXBAC+AwADAAoKmSTXBAC+AwABNQAECgkJLwADAO8mAA==.Muskeg:BAABNQAECn8iAAIgAAgKKxIIVwCXAQAgAAgKKxIIVwCXAQAAAA==.Mustardhunt:BAAANQADCgYICgAAAA==.',
['Mü']='Münchkiné:BAAANQAECgEIAQAAAA==.',
Na='Namanari:BAAANQABCgIJAgAAAA==.Naris:BAAANQAECggIEQAAAA==.',
Ne='Necrochade:BAAANQAECgEIAgAAAA==.Neptune:BAABNQAECn8sAAIGAAkKZBmiXwDAAgAGAAkKZBmiXwDAAgAAAA==.',
Ni='Nightstew:BAAANQAECgEIAQAAAA==.Nikra:BAAANQAECgQICAAAAA==.Nishal:BAAANQADCggIGwAAAA==.',
Ny='Nyxaries:BAAANQAECgYIEQABNQAECgcIBwAZAAAAAA==.',
['Né']='Néwby:BAABNQAECn80AAMmAAoKAh5WBgCPAgAmAAoKAh5WBgCPAgAkAAQKdA57GwClAAAAAA==.',
Op='Opalynn:BAAANQAECgEIAQAAAA==.Ophirra:BAAANQABCgYIDgAAAA==.',
Oz='Ozempic:BAAANQAECgQIBAABNQAFFAcIHQAaAAUgAA==.',
Pa='Pablo:BAABNQAECn8cAAICAAoK6xcPZgBpAgACAAoK6xcPZgBpAgAAAA==.Pannacea:BAAANQAECgUIBwABNQAECgkJLgAWABMdAA==.Patriot:BAAANQAECgEIBAAAAA==.Pawinurbutt:BAAANQADCgQIBAAAAA==.',
Pe='Peppert:BAAANQAECgUIDQAAAA==.',
Ph='Phane:BAAANQAECgUICAAAAA==.',
Po='Pocketheals:BAAANQAECgMIBAAAAA==.Poon:BAAANQAECgQICAAAAA==.',
Pr='Pretzelz:BAAANQADCgQIAwAAAA==.',
Pu='Puffer:BAABNQAECn8ZAAINAAkKzQfwDQAqAQANAAkKzQfwDQAqAQAAAA==.',
Px='Pxry:BAAANQAECgQIBAAAAA==.',
Py='Pyrrhus:BAAANQAECgQIBAAAAA==.',
Qu='Quam:BAAANQAECgEIAgAAAA==.',
Ra='Rabone:BAAANQADCgIJAgAAAA==.Raevyn:BAAANQAECgEIAQAAAA==.Raito:BAABNQAECn8YAAICAAkKowXRsAD3AAACAAkKowXRsAD3AAAAAA==.Rakshasa:BAABNQAECn8+AAQHAAoKMSJiDwBWAwAHAAoKMSJiDwBWAwAIAAMK3w9VRwCqAAAJAAEKIBWZGABHAAAAAA==.Rano:BAAANQAECgEIAQAAAA==.Rasetsungo:BAABNQAECn8oAAIBAAkKGRbvKwAWAgABAAkKGRbvKwAWAgAAAA==.Raura:BAAANQAECgEIAQAAAA==.Rayala:BAAANQAECggICQAAAA==.',
Re='Redblueblurr:BAAANQAECgUIEQAAAA==.Remi:BAABNQAECn8iAAMBAAoK3RtOGQCWAgABAAoK3RtOGQCWAgAYAAEK+wCSkQAYAAAAAA==.Rev:BAAANQADCgUIBQAAAA==.Reveillark:BAAANQAECgIIAgAAAA==.Revelaiden:BAAANQAECgEIAQABNQAECggIIwAEAJodAA==.',
Ri='Rise:BAAANQAECgcIEAAAAA==.',
Ro='Rolan:BAABNQAECn83AAQjAAoKZiUfCQDVAgAjAAoK8CQfCQDVAgAOAAgK2SPFHwDMAgAgAAQKtSOFWwCEAQAAAA==.Ronnic:BAAANQAECgEIAgAAAA==.Rosalian:BAABNQAECn8gAAIeAAgKixKVHgBrAQAeAAgKixKVHgBrAQAAAA==.Rotiko:BAABNQAECn8bAAIWAAgKpgW5XwAeAQAWAAgKpgW5XwAeAQAAAA==.Roweene:BAABNQAECn8mAAInAAcKvgOgEgDbAAAnAAcKvgOgEgDbAAAAAA==.',
['Rá']='Rágnar:BAABNQAECn8nAAMCAAoKzRB6eABhAQACAAoKzRB6eABhAQATAAEKLAKqVgAbAAAAAA==.',
Sa='Sabiel:BAABNQAECn8bAAIFAAYKLwjLRQCtAAAFAAYKLwjLRQCtAAAAAA==.Sakuta:BAAANQADCgYIBgABNQAECgkJIQAWAOcdAA==.',
Se='Serenatee:BAABNQAECn8sAAIYAAgKqAy3GABOAQAYAAgKqAy3GABOAQAAAA==.',
Sh='Shaedai:BAABNQAECn8eAAMWAAgKfg9BTQBgAQAWAAgKfg9BTQBgAQARAAEKPAJKUwEkAAAAAA==.Shagohod:BAAANQAECgEIAQAAAA==.Shakked:BAAANQAECgEIAwAAAA==.Shinanigans:BAAANQAECgEIAQAAAA==.',
Sk='Skotojar:BAAANQADCgUIBQAAAA==.',
Sn='Snortedgfuel:BAAANQAECgcIEgAAAA==.',
So='Sokroar:BAAANQAECgYICQABNQAFFAYIAQAZAAAAAA==.Solphera:BAAANQADCgUIDAAAAA==.Sonknight:BAAANQAECgQIDQAAAA==.',
Sp='Speedshot:BAAANQAECgEIAQAAAA==.Spitefulcrow:BAABNQAECn8fAAIoAAoK0Qh9CADJAQAoAAoK0Qh9CADJAQAAAA==.Spot:BAAANQAECgEIAQAAAA==.',
St='Stardstr:BAAANQADCgMIAwAAAA==.Stealinsoulz:BAAANQADCgYICgABNQAECgEIAQAZAAAAAA==.Stealsoul:BAAANQADCgIIAgABNQAECgEIAQAZAAAAAA==.Sto:BAAANQAECgEIAgAAAA==.Stratof:BAAANQAECgYIBgAAAA==.',
Su='Sufferding:BAABNQAECn8iAAIiAAkKeRFUHQCvAQAiAAkKeRFUHQCvAQAAAA==.Suria:BAABNQAECn8wAAIeAAkKqiAnBgAKAwAeAAkKqiAnBgAKAwAAAA==.',
Sw='Swytchblade:BAAANQADCggICQAAAA==.',
Sy='Syker:BAAANQADCgIIAgAAAA==.',
Ta='Tahrovin:BAABNQAECn8VAAIEAAgKNBDZNACcAQAEAAgKNBDZNACcAQAAAA==.Tavernn:BAAANQAECgEIAgAAAA==.Taytorchips:BAABNQAECn8qAAMCAAkKOAVbqwAAAQACAAkKOAVbqwAAAQASAAQKZAH0EAFVAAAAAA==.',
Th='Thaendrin:BAAANQADCgYICQAAAA==.Thearcane:BAAANQADCgQIBwAAAA==.Thedoc:BAAANQAECgUICwAAAA==.Theefjeef:BAAANQAECgYIBQABNQAECggIDgAZAAAAAA==.Thorloim:BAABNQAECn8jAAMWAAgKKyA3WwD+AQAWAAcKch83WwD+AQAUAAMKRA8EJABxAAAAAA==.Thornx:BAAANQADCgEIAQAAAA==.Throwaway:BAAANQAECgcICAAAAA==.Thundercups:BAABNQAECn8mAAIUAAgKixUVDgCuAQAUAAgKixUVDgCuAQAAAA==.',
Ti='Tigerstarr:BAABNQAECn8dAAMjAAoKMBClNwD4AQAjAAoKMBClNwD4AQAOAAQKngmxowCzAAAAAA==.Tinyshieva:BAAANQADCgYICAAAAA==.Tizuki:BAAANQAECgQIBAAAAA==.',
To='Tonystandard:BAAANQAECgUICQABNQAFFAQICAAVAPESAA==.',
Tr='Treborlock:BAABNQAECn8pAAMIAAkKGhCgAwCEAQAIAAkKGhCgAwCEAQAHAAEKmQKSVgEhAAAAAA==.Triplock:BAAANQAECgEJAgAAAA==.Trolcain:BAABNQAECn8xAAIOAAoKpx0+CgB8AgAOAAoKpx0+CgB8AgAAAA==.',
Tw='Twistedspork:BAAANQAECgQIBwAAAA==.',
Un='Unbuffed:BAAANQAECgEIAQABNQAECgkJLQASAA4cAA==.',
Va='Vaedar:BAAANQAECgEIAgAAAA==.Vagglord:BAAANQAECgQIEQAAAA==.Valha:BAABNQAECn8kAAIiAAgKxg4XPgDJAQAiAAgKxg4XPgDJAQAAAA==.Vardisk:BAAANQADCgQIBAAAAA==.Varlashard:BAAANQADCggIFQAAAA==.Varteras:BAABNQAECn8wAAMJAAgKrRY0BwAuAgAJAAgKrRY0BwAuAgAHAAUKXAaL8QDnAAAAAA==.',
Ve='Vellron:BAABNQAECn8gAAIDAAkKggkRWwCMAQADAAkKggkRWwCMAQAAAA==.Veroque:BAAANQADCgUIBQAAAA==.',
['Và']='Vàsh:BAAANQAECgUICAAAAA==.',
['Vø']='Vødøu:BAABNQAECn8bAAMMAAgKZB+zMACxAQAMAAgKIB6zMACxAQALAAQKABdGYQAwAQAAAA==.',
Wa='Wafflelegend:BAABNQAECn8mAAIiAAgKFiW4CgBaAwAiAAgKFiW4CgBaAwAAAA==.Wardkbriggle:BAABNQAECn8XAAMjAAkKbBrFNQACAgAjAAkKExfFNQACAgAOAAgKsRg0VgC5AQAAAA==.Warint:BAABNQAECn8VAAICAAcK2gWoFgH5AAACAAcK2gWoFgH5AAAAAA==.Wartiger:BAABNQAFFH8GAAIQAAYKKyBrAADfAQAQAAYKKyBrAADfAQAAAA==.',
We='Weeble:BAAANQADCgMIAwAAAA==.Welish:BAAANQABCgEIAQAAAA==.',
Wi='Wifi:BAABNQAECn8oAAICAAgKvSQZMwAtAgACAAgKvSQZMwAtAgAAAA==.',
Wo='Wolfdude:BAAANQAECggIDQAAAA==.',
Wy='Wydge:BAABNQAECn8hAAIGAAcKqg8HDAF5AQAGAAcKqg8HDAF5AQAAAA==.Wyven:BAABNQAECn8wAAMOAAoKwyHMDwA4AwAOAAkK6yLMDwA4AwAjAAQKeRgCPgAhAQABNQADCgcICgAZAAAAAA==.',
Xa='Xanddoria:BAABNQAECn8rAAMMAAkKMiFBFQB2AgALAAcKtCImHgCPAgAMAAkK7h5BFQB2AgAAAA==.Xaoc:BAABNQAECn8UAAIPAAcKEhV1KgDJAQAPAAcKEhV1KgDJAQAAAA==.',
Xh='Xhared:BAABNQAECn8nAAIgAAcK4h8lOwAYAgAgAAcK4h8lOwAYAgAAAA==.',
Xo='Xochital:BAAANQADCgEIAQAAAA==.',
Ye='Yesenia:BAAANQADCgYICwAAAA==.',
Yu='Yunah:BAAANQADCgYIBgAAAA==.',
Ze='Zephy:BAABNQAECn8UAAIdAAUK6gjfpQDAAAAdAAUK6gjfpQDAAAAAAA==.',
['Åe']='Åeon:BAAANQAECgQICwAAAA==.',
['Ðr']='Ðráco:BAAANQAECgQIBQAAAA==.',
['ßu']='ßullzeye:BAAANQADCgcIBwAAAA==.',
['Ÿu']='Ÿunalessca:BAAANQAECgYIDwAAAA==.',
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
