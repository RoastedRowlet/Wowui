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

local lookup = {'Priest-Holy','Paladin-Retribution','Hunter-BeastMastery','DemonHunter-Devourer','Unknown-Unknown','Druid-Balance','Priest-Shadow','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Mage-Frost','DeathKnight-Unholy','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Monk-Mistweaver','Shaman-Restoration','DemonHunter-Vengeance','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Warrior-Arms','Druid-Restoration','Warrior-Fury','DeathKnight-Blood','Evoker-Augmentation','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Frost','Druid-Feral','Druid-Guardian','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aaronius:BAABNQAECn8cAAIBAAcK8gEfugCmAAABAAcK8gEfugCmAAAAAA==.',
Ab='Abrahm:BAAANQABCgIIAgAAAA==.',
Ac='Acceptance:BAACNQAFFH8MAAICAAcKyxexBACpAQACAAcKyxexBACpAQA1AAQKfx0AAgIACgpZHwweAOACAAIACgpZHwweAOACAAAA.',
Ad='Adoe:BAABNQAECn8oAAIDAAgKWBsubwAzAgADAAgKWBsubwAzAgAAAA==.Adora:BAAANQAECgMJBwAAAA==.',
Ae='Aeveen:BAAANQAECgEIAQAAAA==.',
Ag='Agaliarept:BAAANQADCgMIAwAAAA==.Agathos:BAAANQAECgIIBAAAAA==.',
Ai='Aidenator:BAABNQAECn8sAAIEAAkKoxssFwDsAQAEAAkKoxssFwDsAQAAAA==.',
Al='Algebradaddy:BAAANQAECggICgABNQAECggIDwAFAAAAAA==.Aluni:BAAANQADCgEIAQAAAA==.',
Am='Ammastin:BAAANQABCgMIAwAAAA==.',
An='Andorix:BAAANQAECgQICQAAAA==.Andretta:BAAANQAECgMIBAAAAA==.Angelneko:BAABNQAECn8sAAIGAAgKfwaFSwDeAAAGAAgKfwaFSwDeAAAAAA==.Annihilaiden:BAAANQAECgEIAgABNQAECgkJLAAEAKMbAA==.',
Ar='Arinthian:BAAANQAECgQICwAAAA==.Artrian:BAABNQAECn8iAAMBAAgKAxdDWADFAQABAAgKAxdDWADFAQAHAAUKAwZvPACsAAAAAA==.',
At='Atthis:BAAANQADCgEIAQAAAA==.',
Au='Auroraa:BAABNQAECn8XAAIGAAcKsAiDVgC0AAAGAAcKsAiDVgC0AAAAAA==.Auyniko:BAAANQAECggIDwAAAA==.',
Av='Avalectra:BAAANQAECgEIAQAAAA==.Avdakedavra:BAAANQAECgEIAQAAAA==.',
Az='Azmodeaz:BAABNQAECn8sAAIIAAgK+Q647wCrAQAIAAgK+Q647wCrAQAAAA==.Azraely:BAAANQADCgcIBwAAAA==.Aztrik:BAABNQAECn8kAAQJAAgKdiIZWABOAgAJAAgKZSIZWABOAgAKAAIKCSG2FgCdAAALAAIK8yOKIQBtAAAAAA==.',
Ba='Bajapanti:BAABNQAECn9AAAIMAAoKWxNSEQAbAgAMAAoKWxNSEQAbAgAAAA==.Ballyhøø:BAACNQAFFH8LAAIGAAQKDxAhEQDaAAAGAAQKDxAhEQDaAAA1AAQKfx4AAgYACgraFkwwAF8CAAYACgraFkwwAF8CAAAA.Banchory:BAAANQAECgQIBAAAAA==.Bandaron:BAAANQAECgQIBAAAAA==.Barload:BAAANQABCggIEAAAAA==.Baxstab:BAABNQAECn87AAMNAAoKHBqUCABRAgANAAoKHBqUCABRAgAOAAIKMgo+SQBwAAAAAA==.',
Be='Beelzebrad:BAAANQAECgQIBwAAAA==.Belladeon:BAABNQAECn8mAAMPAAoKchWxCwAEAgAPAAgKuxaxCwAEAgAIAAgK0Qef8wCkAQAAAA==.Betrubt:BAAANQAECgcIDwABNQAECgkJFgAQAFgVAA==.',
Bh='Bhagee:BAAANQADCgUICgAAAA==.',
Bi='Bivouac:BAAANQAECgEIAQAAAA==.',
Bl='Blackpatch:BAABNQAECn9FAAMRAAoK9BrGDwBMAgARAAoK9BrGDwBMAgASAAQKXANuJwCNAAAAAA==.Blacksheep:BAAANQADCggIAQAAAA==.Blaqkid:BAAANQADCgYIBgAAAA==.Blaqsun:BAABNQAECn86AAITAAoKWRQKLwAJAgATAAoKWRQKLwAJAgAAAA==.Blargg:BAAANQAECgUICQAAAA==.Bleeda:BAAANQADCggIAQAAAA==.Blightmaker:BAAANQAECgYICwABNQAECgYIDwAFAAAAAA==.Bloomhammer:BAAANQAECgEIAQAAAA==.Blooming:BAABNQAECn84AAIUAAoKGx9ECgBzAwAUAAoKGx9ECgBzAwAAAA==.',
Bo='Booneboy:BAABNQAECn8fAAQCAAYKwhyTqwDIAQACAAYKwhyTqwDIAQAUAAEK/hOa5wA6AAAVAAEKjgknZgApAAAAAA==.Botemedel:BAABNQAECn8wAAMVAAkKpBiIFQC+AQACAAkKiQ/YbADjAQAVAAkKmhiIFQC+AQABNQAFFAYIDQAWAOcFAA==.Bowtox:BAAANQADCggICgAAAA==.Bowyourhead:BAAANQAECgEIAQAAAA==.',
Br='Brennor:BAABNQAECn84AAICAAoKLAqDlQCMAQACAAoKLAqDlQCMAQAAAA==.Brewslunt:BAABNQAECn8fAAIXAAoKzhoWDwCPAgAXAAoKzhoWDwCPAgABNQAFFAcIFwAYAPQaAA==.Bronamaly:BAAANQADCgYICAAAAA==.',
Ca='Cabbagehunt:BAAANQADCgcIEwAAAA==.Caeden:BAABNQAECn8yAAIYAAoKOA4bTwC+AQAYAAoKOA4bTwC+AQAAAA==.Cairyan:BAABNQAECn8mAAIZAAkKNxiQCABsAgAZAAkKNxiQCABsAgAAAA==.Caiya:BAAANQADCgcIDgABNQAECgoKPgAOAMghAA==.Carvil:BAAANQAECgYIBgAAAA==.Castalia:BAABNQAECn8fAAIHAAYKdwx2KgAZAQAHAAYKdwx2KgAZAQAAAA==.Cattilina:BAAANQADCggIEAAAAA==.',
Ce='Celenara:BAACNQAFFH8UAAIIAAYKxg/mFQArAQAIAAYKxg/mFQArAQA1AAQKfzEAAwgACgpLHhphALwCAAgACgpLHhphALwCAA8AAgohC584AFsAAAAA.Celendil:BAAANQADCgUIBQABNQAFFAYIFAAIAMYPAA==.Celinne:BAAANQAECgUICQAAAA==.Celithe:BAAANQAECgUICgAAAA==.',
Ch='Charlereaux:BAAANQAECgIIBAAAAA==.Charmcaster:BAABNQAECn8nAAIIAAoK6hfcSQAiAgAIAAoK6hfcSQAiAgAAAA==.Charmstrike:BAAANQAECggIDQAAAA==.Chedissa:BAAANQAECgEIAQABNQAECgEIAQAFAAAAAA==.Cheezle:BAAANQAECgYIAwAAAA==.Chleo:BAABNQAECn8oAAIBAAYKjg2ziwAeAQABAAYKjg2ziwAeAQAAAA==.Choco:BAACNQAFFH8eAAIaAAgKNR0mAgCbAgAaAAgKNR0mAgCbAgA1AAQKfzAAAxoACgpHICMJABEDABoACgpHICMJABEDABsAAgpUF9gyAHkAAAAA.Chocolat:BAAANQADCggICAABNQAFFAgIHgAaADUdAA==.Chocolight:BAAANQAECgIIAgABNQAFFAgIHgAaADUdAA==.Chudfox:BAAANQADCgEJAQAAAA==.',
Ci='Ciney:BAAANQAECgQIBAAAAA==.',
Co='Coggler:BAABNQAECn8dAAMcAAcKgBieFABcAQAcAAcKgBieFABcAQAdAAUKtgwB6wAOAQAAAA==.Conqueror:BAAANQAECgYICAABNQAECgoKLQAeAKEYAA==.Corcia:BAAANQAECgMIBAAAAA==.',
Cr='Creatlach:BAAANQAECgIIAwABNQAFFAcIFwAYAPQaAA==.Crotchpox:BAAANQADCgQIBAAAAA==.Crualti:BAABNQAECn8aAAMfAAgKnweVIAC2AAAdAAgKXgWi7wABAQAfAAQKegmVIAC2AAAAAA==.',
Cu='Cuppajoe:BAAANQADCgMIAwAAAA==.Cupper:BAAANQABCgcJCQABNQAECgYIGwACAGkHAA==.Curmudge:BAABNQAECn9NAAIeAAoKZhwHDgDPAgAeAAoKZhwHDgDPAgAAAA==.',
Cy='Cyonissian:BAAANQADCgEIAQAAAA==.',
Da='Dabtoomuch:BAAANQABCgIIAgAAAA==.Daimhin:BAAANQADCgcIBwAAAA==.Dalectra:BAAANQAECgQICwAAAA==.Darachane:BAAANQAECgQICgAAAA==.Darkpriest:BAAANQAECgIIAgAAAA==.Darovan:BAAANQADCggJEAABNQAECgoKLAAgAEwfAA==.Darthnater:BAABNQAECn8dAAIQAAkKnB1GDACmAgAQAAkKnB1GDACmAgAAAA==.Dauglow:BAABNQAECn86AAMDAAoKWBBGVwAFAgADAAoKWBBGVwAFAgAMAAEKhwnmhQA4AAAAAA==.',
De='Deathball:BAAANQAECgEIAQAAAA==.Deathstars:BAAANQADCgcIEwAAAA==.Deboss:BAAANQAECggIDgAAAA==.Dellianne:BAAANQABCgEIAQAAAA==.Delritha:BAAANQAECgUICwAAAA==.Deltithrax:BAABNQAECn8sAAMhAAgKsQ0ADwBSAQAhAAcKqg4ADwBSAQAbAAcKaA1/EwDqAAAAAA==.Demonagent:BAABNQAECn8gAAMZAAcKiBM3EgAQAQAZAAcKiBM3EgAQAQAiAAMKtw5XbwC8AAAAAA==.Desdh:BAACNQAFFH8MAAMiAAQKXBXqEQDWAAAiAAMKXBXqEQDWAAAEAAIK4gcgEQBFAAA1AAQKfy8AAyIACgrMIccaAMQCACIACgoSIccaAMQCAAQAAwp8HoA0AOIAAAAA.Devious:BAAANQAECgcIBwABNQAECgoKOAAUABsfAA==.',
Di='Dinö:BAAANQAECgMJBAABNQAECgoKLAADAJ4WAA==.',
Dm='Dmnslyer:BAAANQADCggIDQAAAA==.',
Do='Docspades:BAABNQAECn8mAAMBAAgKoRP4ZACYAQABAAgKoRP4ZACYAQAjAAEKXQdhGgArAAAAAA==.Dohane:BAAANQADCgQIBAABNQAECggIFgAEADQQAA==.Domrogue:BAABNQAECn8dAAMOAAkKdBefJQBdAgAOAAkKdBefJQBdAgANAAUKcAUXMgC+AAAAAA==.Dornoch:BAAANQAECgIIBAAAAA==.Douglane:BAAANQABCgYIBgAAAA==.',
Dr='Dramine:BAAANQADCgQIBwAAAA==.Draone:BAABNQAECn8qAAIIAAkK1AqFkAByAQAIAAkK1AqFkAByAQAAAA==.Dreabolic:BAAANQADCgYICwAAAA==.Dreamss:BAABNQAECn8xAAMiAAoKyhTBLwApAgAiAAoKyhTBLwApAgAEAAgKvAY4OQB7AQAAAA==.Drhkillinger:BAAANQAECgYIBwABNQAECgcIIAAZAIgTAA==.Drspades:BAAANQAECgEIAQAAAA==.',
Du='Dugosh:BAAANQADCggIDQAAAA==.Duzz:BAAANQAECgEIAQAAAA==.',
['Dé']='Démetal:BAAANQADCggIDgAAAA==.',
Ei='Einherja:BAABNQAECn8gAAQgAAoKnBpRPgA4AQAQAAYKexj4aQBqAQAgAAUKAxxRPgA4AQAkAAcKZRG3XAA2AQAAAA==.',
El='Elessaria:BAABNQAECn8fAAIeAAYKoAl/QADuAAAeAAYKoAl/QADuAAAAAA==.Elfatheàrt:BAAANQAECgIIBAAAAA==.Elidrus:BAAANQAECgIIAgABNQAECgoKGQAJADwEAA==.',
En='Enodlo:BAAANQADCgUIBQAAAA==.',
Er='Erora:BAABNQAECn8nAAIHAAoKShYGGgB9AgAHAAoKShYGGgB9AgAAAA==.',
Es='Estherras:BAABNQAECn8lAAIDAAcKexSUfACnAQADAAcKexSUfACnAQAAAA==.',
Fe='Feardotrun:BAABNQAECn8mAAMKAAgKjg9ZOADfAAAJAAgKjg8blAAdAQAKAAQKewtZOADfAAAAAA==.Felicious:BAAANQAECgIIBAAAAA==.',
Fi='Finally:BAAANQAECgIIBAAAAA==.Firemage:BAACNQAFFH8FAAMJAAQK0A1+JACTAAAJAAMKiw5+JACTAAAKAAEKWwzsEABKAAA1AAQKfzMAAwkACgo5JB0hAIECAAkACQo6JB0hAIECAAoABAq5IgAgAHABAAAA.Fizzanelf:BAAANQAECgMIBwAAAA==.',
Fl='Flaildelyn:BAAANQAECgEIAQAAAA==.Flokíe:BAAANQADCggICAAAAA==.',
Fo='Fortytwo:BAAANQAECggIEgAAAA==.',
Fr='Freyá:BAAANQAECgEIBAAAAA==.Frostbight:BAABNQAECn8xAAIIAAkKuRhDYADnAQAIAAkKuRhDYADnAQAAAA==.Frostied:BAABNQAECn8iAAMgAAoKph84FABhAgAgAAoKLB84FABhAgAkAAUKrBoxTQCCAQAAAA==.Frostyduggo:BAABNQAECn82AAIPAAoKjwsWDgCVAQAPAAoKjwsWDgCVAQAAAA==.',
Fu='Futnuraz:BAAANQAECgIIBAAAAA==.',
Fy='Fyrakkobama:BAAANQAECgYICAABNQAECggIDwAFAAAAAA==.Fyriat:BAABNQAECn8lAAIPAAcKjAx3FAAxAQAPAAcKjAx3FAAxAQAAAA==.',
Ga='Galathel:BAABNQAECn8zAAMVAAoKwBLEIABSAQAVAAkKwxHEIABSAQAUAAEK+gs87gA0AAABNQAECgoKQgAYAJYdAA==.Gavreel:BAAANQAECgYICQAAAA==.Gazardiel:BAABNQAECn8uAAICAAkK4QeYuABKAQACAAkK4QeYuABKAQAAAA==.',
Ge='Gelinia:BAABNQAECn8uAAMHAAkK5wtDHwB5AQAHAAkK5wtDHwB5AQAjAAEKUwFvMwAYAAAAAA==.Gerrald:BAAANQAECgUICAABNQAECgoKLAADAJ4WAA==.Getafix:BAABNQAECn8ZAAIGAAgK1Q3rNgBFAQAGAAgK1Q3rNgBFAQABNQAECgoKQgAYAJYdAA==.',
Gh='Ghozthappenz:BAAANQAECgIIAgABNQAECgoKMAAgALcRAA==.Ghrass:BAAANQADCgQIBQAAAA==.',
Gi='Girthquakes:BAAANQAECgEIBAAAAA==.',
Gl='Glorbo:BAABNQAECn8lAAQUAAcKgh5oMgBEAgAUAAcKgh5oMgBEAgAVAAEK4BbYagA9AAACAAEKsBGufAE8AAAAAA==.',
Go='Goldstorm:BAAANQAECgEIAQAAAA==.Goliath:BAABNQAECn8XAAMYAAYKtRVTjQBoAQAYAAYKtRVTjQBoAQATAAUKWBDftAAoAQAAAA==.',
Gr='Graythers:BAAANQADCgUIBgAAAA==.Greengodess:BAAANQAECgEIAQAAAA==.Gregoron:BAAANQAECgEIAQAAAA==.Grimfelborn:BAACNQAFFH8XAAQKAAYKAxFUBwCCAAAJAAQKGA9yFQDoAAAKAAIKNQ1UBwCCAAALAAEKAAArEwA6AAA1AAQKfzUABAkACgocG3FNAGwCAAkACgocG3FNAGwCAAoAAgr9F6QWAJ0AAAsAAgqDDzAnAE8AAAAA.Grimosh:BAAANQAECgEIAgAAAA==.Grondosh:BAAANQAECgYIEAAAAA==.Gryphindor:BAABNQAECn8UAAIDAAcKwAkbugCPAQADAAcKwAkbugCPAQAAAA==.',
['Gì']='Gìorgìa:BAAANQAECgEIAwAAAA==.',
Ha='Hahwe:BAAANQADCgIIAgABNQAECgoKGQAJADwEAA==.Haljo:BAAANQADCgQJBAAAAA==.Hanoverfiste:BAABNQAECn8bAAICAAYKaQdq8QDrAAACAAYKaQdq8QDrAAAAAA==.Hapsburg:BAABNQAECn85AAMXAAoKtw8xEQDhAQAXAAoKtw8xEQDhAQARAAgKzwgELwAMAQAAAA==.Harahel:BAAANQAECgQIBgAAAA==.Havince:BAABNQAECn8wAAIgAAoKOCPECgDcAgAgAAoKOCPECgDcAgAAAA==.Hawktuah:BAAANQAECgEIBAAAAA==.Haylee:BAAANQAECgEIAgAAAA==.',
He='Helbreder:BAAANQADCgYIBgAAAA==.Helle:BAAANQAECgIIBAAAAA==.Hercbooyy:BAAANQADCgQIBAABNQAECggIKAAUAGQjAA==.Hercboyy:BAABNQAECn8oAAMUAAgKZCN2GgANAwAUAAcKgSZ2GgANAwAVAAUKORZDNwDAAAAAAA==.',
Hi='Higgs:BAAANQAECgEIAgABNQAECgoKPAAUAPYdAA==.Higgspally:BAABNQAECn88AAIUAAoK9h0mDQBQAwAUAAoK9h0mDQBQAwAAAA==.',
Ho='Holyball:BAABNQAECn9CAAICAAoKPR3oLQCdAgACAAoKPR3oLQCdAgAAAA==.Holytalon:BAAANQADCgIIAgAAAA==.Hotak:BAAANQAECgEIAQAAAA==.',
Hu='Hughjahsol:BAAANQADCgIIAgAAAA==.Hukaru:BAAANQABCgIIAgABNQAECgoKMAAgADgjAA==.Huuken:BAAANQAECgQIBAAAAA==.Huulkster:BAAANQADCgQIBAAAAA==.',
Hy='Hydra:BAAANQAECgEJAQAAAA==.',
Il='Ilovehunter:BAAANQADCggICAAAAA==.Ilyndra:BAABNQAECn8sAAIcAAgKtyNkCQApAgAcAAgKtyNkCQApAgAAAA==.',
In='Infernella:BAAANQADCgMIAwAAAA==.',
Ir='Ironskin:BAAANQAECgUIEAAAAA==.',
Is='Iselilja:BAABNQAECn8iAAMdAAgKmQzDdACPAQAdAAgKggzDdACPAQAcAAQK6AhhMgCkAAAAAA==.',
It='Ithea:BAABNQAECn88AAIIAAoKzBxMMwBqAgAIAAoKzBxMMwBqAgAAAA==.',
Ja='Jackshots:BAAANQADCgIIAgAAAA==.Jaeson:BAEBNQAECn8eAAMJAAkKeQ7sZQCRAQAJAAkKeQ7sZQCRAQALAAEKBwa4MwAsAAAAAA==.Jakaro:BAACNQAFFH8LAAMKAAUK2wdiEgCHAAAKAAIK/ARiEgCHAAAJAAMKugo0NABKAAA1AAQKfycAAwoACQpHFxcrACUBAAkABwpJGbdpAIYBAAoABQovERcrACUBAAAA.Javoren:BAAANQADCgcIBwABNQAECgUIBQAFAAAAAA==.',
Je='Jeefgpt:BAAANQAECgEIAQABNQAECggIDwAFAAAAAA==.Jeefrenzy:BAAANQAECggIDwAAAA==.Jeefwrld:BAAANQAECgYICQAAAA==.Jeffers:BAAANQAECgEIAwABNQAECggIDwAFAAAAAA==.Jeffha:BAAANQADCggICAAAAA==.',
Ji='Jiinx:BAABNQAECn8sAAMDAAgKnRW/gQAJAgADAAgKnRW/gQAJAgAMAAUKrwtMTQD8AAAAAA==.',
Jo='Joap:BAAANQAECgYIBgAAAA==.Joejr:BAABNQAECn83AAMHAAoKsxR1EwAOAgAHAAoKsxR1EwAOAgABAAgKhhT9bQDUAQAAAA==.Jonald:BAABNQAECn8cAAIEAAoK9gt4MwCmAQAEAAoK9gt4MwCmAQAAAA==.',
Jt='Jtizlfrizl:BAABNQAECn8mAAINAAcKoBAzGwBDAQANAAcKoBAzGwBDAQAAAA==.',
Ju='Judge:BAAANQADCggIEQABNQAECgoKOAAUABsfAA==.Juniperz:BAABNQAECn8wAAIgAAoKtxFvJwC0AQAgAAoKtxFvJwC0AQAAAA==.',
Jw='Jwise:BAAANQAECggIAgAAAA==.',
Ka='Kaaydenn:BAABNQAECn8sAAQUAAoKWBxnFAAFAwAUAAkKRh1nFAAFAwACAAEKAAC5lAE/AAAVAAEKAABYdwAlAAAAAA==.Kaghro:BAAANQADCgcICAAAAA==.Kalaziel:BAABNQAECn8iAAITAAoKuwc+dgASAQATAAoKuwc+dgASAQAAAA==.Kalimotxo:BAABNQAECn8fAAIiAAoKnBwbFABuAgAiAAoKnBwbFABuAgAAAA==.Kamus:BAAANQAECgEIAQAAAA==.Karawyn:BAAANQAECgEIAgABNQADCgQICAAFAAAAAA==.Karelix:BAAANQAECgQIBgAAAA==.Katrichi:BAAANQAECgMIBQAAAA==.Katrishy:BAACNQAFFH8ZAAIHAAYK2Rb5BABdAQAHAAYK2Rb5BABdAQA1AAQKfzUAAgcACgruHfQSANMCAAcACgruHfQSANMCAAAA.Kayde:BAAANQAECgQICQAAAA==.',
Ke='Keedrid:BAABNQAECn83AAIQAAoKoCCtDwB3AgAQAAoKoCCtDwB3AgAAAA==.Kelaeno:BAABNQAECn85AAITAAoKKw4TQwCwAQATAAoKKw4TQwCwAQAAAA==.Kemics:BAAANQAECgMIAwAAAA==.Kev:BAACNQAFFH8OAAIUAAMKeRsbFgD/AAAUAAMKeRsbFgD/AAA1AAQKfzQAAhQACgryI7IEAKsDABQACgryI7IEAKsDAAAA.',
Ki='Kirima:BAAANQADCggICAAAAA==.Kirmit:BAAANQAECgQIBwAAAA==.',
Kl='Klevege:BAAANQADCgUIBQAAAA==.',
Kn='Knoll:BAAANQAECgIIBgAAAA==.',
Ko='Korta:BAAANQABCggIKgAAAA==.',
Kr='Kreeona:BAABNQAECn9CAAIYAAoKlh0EGwDLAgAYAAoKlh0EGwDLAgAAAA==.Kruàlty:BAABNQAECn8dAAMlAAgKXhZvDQBEAgAlAAgKXhZvDQBEAgAGAAMKewgckgCPAAAAAA==.',
Ky='Kyfert:BAAANQAECgQIBgAAAA==.',
La='Laird:BAAANQAECgMIAwAAAA==.',
Le='Legreecast:BAAANQAECgIIBAAAAA==.',
Li='Liare:BAACNQAFFH8fAAQLAAcK5RvmAwCyAAAJAAQKxBniGQAnAQALAAMK5x7mAwCyAAAKAAIKsSCTBACgAAA1AAQKfzAABAkACgpqJbgKAHcDAAkACgpqJbgKAHcDAAoABgoxHxQXALQBAAsAAwr8InYXANQAAAAA.Liasong:BAAANQAECggIEAAAAA==.Litheliice:BAABNQAECn83AAIBAAoKJhW8SwD0AQABAAoKJhW8SwD0AQAAAA==.',
Lo='Lodur:BAABNQAECn8jAAIYAAcKgQ1lgAAcAQAYAAcKgQ1lgAAcAQAAAA==.Lonen:BAABNQAECn8fAAImAAcK1BZfHQCCAQAmAAcK1BZfHQCCAQAAAA==.Losat:BAABNQAECn9AAAIcAAoKFgssEwBxAQAcAAoKFgssEwBxAQAAAA==.',
Lu='Luckx:BAAANQAECgEIAQAAAA==.Lukeluke:BAAANQADCgQIBwAAAA==.Luthian:BAAANQAECgQIBQAAAA==.',
Ly='Lyn:BAAANQAECgIIAgAAAA==.',
['Lî']='Lîîght:BAAANQADCggIHgAAAA==.',
Ma='Mac:BAABNQAECn9BAAMlAAoKHRaRCgAWAgAlAAoKHRaRCgAWAgAGAAkKmg04MQBnAQAAAA==.Machiato:BAAANQAECgIIBAAAAA==.Mackkie:BAABNQAECn8eAAMXAAcK/hEnJQBSAQAXAAcK/hEnJQBSAQARAAYKZQVZSADeAAAAAA==.Madonkadonk:BAABNQAECn81AAIbAAoKQwj3DABtAQAbAAoKQwj3DABtAQAAAA==.Maedai:BAAANQAECgUIEwAAAA==.Maeli:BAAANQAECgEIAQAAAA==.Magladroth:BAAANQABCgQJBAAAAA==.Maldive:BAABNQAECn82AAQLAAoKpQ/kCQCZAQALAAkKNhDkCQCZAQAJAAoK+goyvQBSAQAKAAMKnwsMTgCVAAAAAA==.Maligasia:BAAANQADCgIIAwAAAA==.Mallicia:BAABNQAECn9DAAMBAAoKaSIpDwBMAwABAAoKaSIpDwBMAwAHAAgKDQoCJgA9AQAAAA==.Mallika:BAAANQAECgIIAQABNQAECgoKQwABAGkiAA==.Mallistra:BAABNQAECn8lAAIXAAoKmhSTFwAEAgAXAAoKmhSTFwAEAgABNQAECgoKQwABAGkiAA==.Mallwizard:BAAANQAECgUJCwAAAA==.Mandible:BAAANQAECgEIAQAAAA==.Marcille:BAAANQAECgQIBAAAAA==.Martris:BAABNQAECn8YAAICAAcKngTuGQGuAAACAAcKngTuGQGuAAAAAA==.Maryjane:BAAANQAECgMJAwAAAA==.Mashma:BAAANQADCggICAAAAA==.Massoflice:BAAANQAECgYIEAAAAA==.Mawkt:BAAANQADCggIAQAAAA==.Maxblaide:BAAANQAECgYICwAAAA==.',
Me='Melovania:BAAANQADCgIIAgAAAA==.',
Mi='Miami:BAAANQAECgMIBAABNQAFFAEIAQAFAAAAAA==.Milah:BAAANQABCgIIAgAAAA==.Missile:BAAANQAECgQICQABNQAECgcIGgAGAGEgAA==.Misstangy:BAAANQADCgcIFwAAAA==.',
Mo='Moct:BAABNQAECn9DAAIVAAoKXyI0BQAEAwAVAAoKXyI0BQAEAwAAAA==.Monikal:BAAANQAECgMIAgAAAA==.',
Mu='Muradox:BAAANQADCgcIBwABNQAECgoKJwAHAEoWAA==.Musashi:BAABNQAECn8/AAIDAAoKjyXXBAC+AwADAAoKjyXXBAC+AwABNQAECgkJLwADAO8mAA==.Muskeg:BAABNQAECn8rAAIgAAkKzhAuPwA0AQAgAAkKzhAuPwA0AQAAAA==.Mustardhunt:BAAANQADCgYICgAAAA==.',
['Mü']='Münchkiné:BAAANQAECgEIAQAAAA==.',
Na='Namanari:BAAANQABCgIJAgAAAA==.Naris:BAABNQAECn8ZAAIJAAoKPAR3pAD5AAAJAAoKPAR3pAD5AAAAAA==.',
Ne='Necrochade:BAAANQAECgEIAgAAAA==.Neptune:BAABNQAECn8uAAIIAAoKrhiiXwDAAgAIAAoKrhiiXwDAAgAAAA==.',
Ni='Nightstew:BAAANQAECgEIAQAAAA==.Nikra:BAAANQAECgQICAAAAA==.Nishal:BAAANQADCggIGwAAAA==.',
Ny='Nyxaries:BAAANQAECgYIDwAAAA==.',
['Né']='Néwby:BAABNQAECn89AAMmAAoKcR/rBwADAwAmAAoK3R7rBwADAwAlAAgKkRI4FQBaAQAAAA==.',
Op='Opalynn:BAAANQAECgEIAQAAAA==.Ophirra:BAAANQABCgYIDgAAAA==.',
Oz='Ozempic:BAAANQAECgQIBAABNQAFFAgIHgAaADUdAA==.',
Pa='Pablo:BAABNQAECn8mAAICAAoKcBkPZgBpAgACAAoKcBkPZgBpAgAAAA==.Pannacea:BAAANQAECgUIDAABNQAECgoKQgAYAJYdAA==.Patriot:BAAANQAECgIIAwAAAA==.Pawinurbutt:BAAANQADCgQIBAAAAA==.',
Pe='Peppert:BAAANQAECgcIDgAAAA==.',
Ph='Phane:BAAANQAECgQICAAAAA==.',
Po='Pocketheals:BAAANQAECgMIBAAAAA==.Poon:BAAANQAECgQICAAAAA==.',
Pr='Pretzelz:BAAANQADCgcICQAAAA==.',
Pu='Puffer:BAABNQAECn8jAAIPAAoK+AikDwB4AQAPAAoK+AikDwB4AQAAAA==.',
Px='Pxry:BAAANQAECgQIBAAAAA==.',
Py='Pyrrhus:BAAANQAECgQIBAAAAA==.',
Qu='Quam:BAAANQABCggIFgAAAA==.',
Ra='Rabone:BAAANQADCgIJAgAAAA==.Raevyn:BAAANQAECgEIAQAAAA==.Raito:BAABNQAECn8mAAICAAoKnwfcpgBqAQACAAoKnwfcpgBqAQAAAA==.Rakshasa:BAABNQAECn9HAAQJAAoKTiJiDwBWAwAJAAoKTiJiDwBWAwAKAAMK3w9VRwCqAAALAAEKIBWTJwBCAAAAAA==.Rano:BAAANQAECgEIAQAAAA==.Rasetsungo:BAABNQAECn88AAIBAAoKmhZ5MgBiAgABAAoKmhZ5MgBiAgAAAA==.Raura:BAAANQAECgIIBAAAAA==.Rayala:BAAANQAECggICQAAAA==.',
Re='Redblueblurr:BAABNQAECn8UAAICAAcKQQSQMAHRAAACAAcKQQSQMAHRAAAAAA==.Remi:BAABNQAECn8tAAMBAAoKBhwSMABuAgABAAoKBhwSMABuAgAHAAEK+wCSkQAYAAAAAA==.Rev:BAAANQADCgUIBQAAAA==.Reveillark:BAAANQAECgIIAgAAAA==.Revelaiden:BAAANQAECgEIAQABNQAECgkJLAAEAKMbAA==.',
Ri='Rise:BAAANQAECgcIDwAAAA==.',
Ro='Rolan:BAABNQAECn9DAAQkAAoK/CV2CgADAwAkAAoK3yV2CgADAwAQAAgK2SPFHwDMAgAgAAQKwSXqOgBHAQAAAA==.Rosalian:BAABNQAECn8nAAIeAAkKkhGYKACOAQAeAAkKkhGYKACOAQAAAA==.Rotiko:BAABNQAECn8cAAIYAAkKYAWifAAmAQAYAAkKYAWifAAmAQAAAA==.Roweene:BAABNQAECn8sAAInAAgKLgS0BwChAAAnAAgKLgS0BwChAAAAAA==.',
['Rá']='Rágnar:BAABNQAECn8wAAMCAAoKkRMkhACvAQACAAoKkRMkhACvAQAVAAQK/wQpQQCRAAAAAA==.',
Sa='Sabiel:BAABNQAECn8qAAIGAAkKpwdgPAAnAQAGAAkKpwdgPAAnAQAAAA==.Sakuta:BAAANQADCgYIBgABNQAECgkJIQAYAOcdAA==.',
Se='Selryth:BAAANQADCgcIBwABNQAECggIDwAFAAAAAA==.Serenatee:BAABNQAECn8zAAIHAAkKUA4uHQCQAQAHAAkKUA4uHQCQAQAAAA==.',
Sh='Shaedai:BAABNQAECn8mAAMYAAoK8hC4PQAIAgAYAAoK8hC4PQAIAgATAAEKPAJKUwEkAAAAAA==.Shagohod:BAAANQAECgEIAQAAAA==.Shakked:BAAANQAECgEIAwAAAA==.Shinanigans:BAAANQAECgUIBQAAAA==.',
Sk='Skotojar:BAAANQADCgUIBQAAAA==.',
Sn='Snortedgfuel:BAAANQAECgcIEgAAAA==.',
So='Sokroar:BAAANQAECgYICAABNQAFFAYIAQAFAAAAAA==.Solphera:BAAANQADCgUIDAAAAA==.Sonknight:BAABNQAECn8YAAMUAAcKlQaClADrAAAUAAcKlQaClADrAAACAAIKWAEzlwEqAAAAAA==.',
Sp='Speedshot:BAAANQAECgEIAQAAAA==.Spicy:BAAANQAECgUIBwAAAA==.Spitefulcrow:BAABNQAECn8rAAIoAAoKxAlSCABdAQAoAAoKxAlSCABdAQAAAA==.Spot:BAAANQAECgEIAQAAAA==.',
St='Stardstr:BAAANQADCgMIAwAAAA==.Stealinsoulz:BAAANQADCgYICgABNQAECgEIAQAFAAAAAA==.Stealsoul:BAAANQADCgIIAgABNQAECgEIAQAFAAAAAA==.Sto:BAAANQAECgEIAgAAAA==.Stratof:BAAANQAECgcICwAAAA==.',
Su='Sufferding:BAABNQAECn8iAAIiAAkKeREPLQCSAQAiAAkKeREPLQCSAQAAAA==.Suria:BAABNQAECn9CAAIeAAoKeiBKBgBvAwAeAAoKeiBKBgBvAwAAAA==.',
Sw='Swytchblade:BAAANQADCggICQAAAA==.',
Sy='Syker:BAAANQADCgIIAgAAAA==.',
Ta='Tahrovin:BAABNQAECn8WAAIEAAgKNBDZNACcAQAEAAgKNBDZNACcAQAAAA==.Tavernn:BAAANQABCggILQAAAA==.Taytorchips:BAABNQAECn88AAMCAAoK8wlZyAAuAQACAAkKFQZZyAAuAQAUAAUKBQL0EAFVAAAAAA==.',
Th='Thaendrin:BAAANQADCgYICQAAAA==.Thearcane:BAAANQADCgQICAAAAA==.Thedoc:BAAANQAECgUICgAAAA==.Theefjeef:BAAANQAECgYIBQABNQAECggIDwAFAAAAAA==.Thorloim:BAABNQAECn8pAAMYAAkKpR9JPAAPAgAYAAkKpR9JPAAPAgAWAAQKthCcJgC7AAAAAA==.Thornx:BAAANQADCgEIAQAAAA==.Throwaway:BAAANQAECgcICAAAAA==.Thundercups:BAABNQAECn8uAAIWAAoKQBT4DQAhAgAWAAoKQBT4DQAhAgAAAA==.',
Ti='Tiajoe:BAAANQAECggICAAAAA==.Tigerstarr:BAABNQAECn8hAAMkAAoK3hGlNwD4AQAkAAoK3hGlNwD4AQAQAAQKngmxowCzAAAAAA==.Tinyshieva:BAAANQADCgYICQAAAA==.Tizuki:BAAANQAECgQIBAAAAA==.',
To='Tonystandard:BAAANQAECgUICQABNQAFFAYICwAXAN8PAA==.',
Tr='Treborlock:BAABNQAECn85AAMKAAoKKRFNBAC8AQAKAAoKKRFNBAC8AQAJAAEKmQKSVgEhAAAAAA==.Triplock:BAAANQAECgEJAgAAAA==.Trolcain:BAABNQAECn9FAAIQAAoKfSIcBwD7AgAQAAoKfSIcBwD7AgAAAA==.',
Tw='Twistedspork:BAAANQAECgQICwAAAA==.',
Ul='Ulfal:BAAANQAECgEIAQAAAA==.',
Un='Unbuffed:BAAANQAECgEIAQABNQAECgoKPAAUAPYdAA==.',
Ut='Uthon:BAAANQAECgMIBAAAAA==.',
Va='Vaedar:BAAANQAECgEIAgAAAA==.Vagglord:BAAANQAECgQIEQAAAA==.Valha:BAABNQAECn8pAAIiAAoKIA+OKQCrAQAiAAoKIA+OKQCrAQAAAA==.Vardisk:BAAANQADCgQIBAAAAA==.Varlashard:BAAANQADCggIFQAAAA==.Varteras:BAABNQAECn83AAMLAAoKwhc0BwAuAgALAAkKFRc0BwAuAgAJAAcKoA70tQDTAAAAAA==.',
Ve='Vellron:BAABNQAECn8qAAIDAAoKOAolbADPAQADAAoKOAolbADPAQAAAA==.Veroque:BAAANQADCgUIBQAAAA==.',
['Và']='Vàsh:BAAANQAECgUICAAAAA==.',
['Vø']='Vødøu:BAABNQAECn8cAAMOAAkK6R52NwAIAgAOAAkK0x12NwAIAgANAAQKABdGYQAwAQAAAA==.',
Wa='Wafflelegend:BAABNQAECn8mAAIiAAgKFiW4CgBaAwAiAAgKFiW4CgBaAwAAAA==.Wardkbriggle:BAABNQAECn8XAAMkAAkKbBrFNQACAgAkAAkKExfFNQACAgAQAAgKsRg0VgC5AQAAAA==.Warent:BAAANQAECgIIAgAAAA==.Warint:BAABNQAECn8YAAICAAgK/wXa+wDbAAACAAgK/wXa+wDbAAAAAA==.Wartiger:BAABNQAFFH8GAAISAAYKKyAgAQDNAQASAAYKKyAgAQDNAQAAAA==.',
We='Weeble:BAAANQADCgMIAwAAAA==.Welish:BAAANQABCgEIAQAAAA==.',
Wi='Wifi:BAABNQAECn8yAAICAAgKqyXwMACRAgACAAgKqyXwMACRAgAAAA==.',
Wo='Wolfdude:BAAANQAECggIDAAAAA==.',
Wy='Wydge:BAABNQAECn8nAAIIAAgK4Q08sAAyAQAIAAgK4Q08sAAyAQAAAA==.Wyven:BAACNQAFFH8FAAIkAAIKUBZnEwCaAAAkAAIKUBZnEwCaAAA1AAQKfzgAAxAACgq8IswPADgDABAACQrrIswPADgDACQABApwGmFTADABAAE1AAMKBwgKAAUAAAAA.',
Xa='Xanddoria:BAABNQAECn8+AAQOAAoKyCEnEQDlAgAOAAoKEx8nEQDlAgANAAgKOyMmHgCPAgAnAAgKCRZtAgD8AQAAAA==.Xaoc:BAABNQAECn8UAAIRAAcKEhV1KgDJAQARAAcKEhV1KgDJAQAAAA==.',
Xh='Xhared:BAABNQAECn8sAAIgAAoKTB/0FwA3AgAgAAoKTB/0FwA3AgAAAA==.',
Xo='Xochital:BAAANQADCgEIAQAAAA==.',
Ye='Yellodur:BAAANQADCgIIAgAAAA==.Yesenia:BAAANQADCgYICwAAAA==.',
Yu='Yunah:BAAANQADCgYIBgAAAA==.',
Ze='Zephy:BAABNQAECn8aAAIdAAYKcgn4sAADAQAdAAYKcgn4sAADAQAAAA==.',
['Åe']='Åeon:BAAANQAECgQICwAAAA==.',
['Ðr']='Ðráco:BAAANQAECgQIBAAAAA==.',
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
