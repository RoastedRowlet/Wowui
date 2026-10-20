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

local lookup = {'Mage-Arcane','Hunter-BeastMastery','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Hunter-Marksmanship','Mage-Frost','Unknown-Unknown','Paladin-Holy','Druid-Balance','Druid-Restoration','Monk-Brewmaster','Priest-Discipline','Priest-Holy','Shaman-Elemental','Priest-Shadow','Evoker-Preservation','Rogue-Subtlety','Shaman-Restoration','Paladin-Retribution','DemonHunter-Havoc','DeathKnight-Unholy','Rogue-Assassination','Shaman-Enhancement','Evoker-Devastation','DemonHunter-Devourer','DeathKnight-Frost','Evoker-Augmentation','Druid-Feral','Warrior-Arms','Warrior-Fury','Monk-Windwalker','Monk-Mistweaver','Rogue-Outlaw','Paladin-Protection','Warrior-Protection','Warlock-Affliction','Druid-Guardian','DemonHunter-Vengeance','Hunter-Survival','Mage-Fire',}
local provider = {region='US',realm='Ghostlands',name='US',type='weekly',zone=53,date='2026-10-20',data={Ad='Adobo:BAAANQADCgYIDQAAAA==.Adofian:BAAANQADCgcIEwABNQAECggIKQABAJQSAA==.',
Af='Afflicted:BAAANQADCgYIBgABNQAFFAcIEAACAFYcAA==.Aft:BAACNQAFFH8SAAIDAAUK0iGFCADXAQADAAUK0iGFCADXAQA1AAQKfy0AAgMACgoNIdQHAH8DAAMACgoNIdQHAH8DAAAA.',
Ai='Aislin:BAAANQAECgQIBgAAAQ==.',
Ak='Akrikan:BAAANQAECgEIAQAAAA==.Akumu:BAABNQAECn8qAAMEAAkKbhwdDwDKAQAEAAkKbhwdDwDKAQAFAAIKehj+VAB/AAAAAA==.',
Al='Alarkin:BAACNQAFFH8bAAMCAAYK7Bb/BQDxAQACAAYKBhb/BQDxAQAGAAUKzRTqDABwAQA1AAQKfzwAAwYACgrtJK4IAEcDAAYACQopIa4IAEcDAAIACQrNJIggABUDAAAA.Alasmira:BAAANQAECgEIAQAAAA==.Alastalta:BAAANQAECgIIAgAAAA==.Alcarde:BAABNQAECn8nAAIHAAoKmhVjBwB6AgAHAAoKmhVjBwB6AgAAAA==.Aldoan:BAAANQAECgIIBAAAAA==.Aleza:BAAANQADCgEIAQAAAA==.Alialeman:BAAANQAECgEIAQAAAA==.Alistiri:BAAANQAECgUICwAAAA==.Alix:BAAANQAECgMIBwAAAA==.Alleth:BAAANQADCgEIAQABNQADCgYICgAIAAAAAA==.Allforge:BAAANQAECgYIEAAAAA==.Almina:BAABNQAECn8YAAICAAcK+AXsYgDlAAACAAcK+AXsYgDlAAAAAA==.Alpal:BAACNQAFFH8bAAIJAAYKBBlkAwCgAQAJAAYKBBlkAwCgAQA1AAQKfz0AAgkACgr5IdIOAFQDAAkACgr5IdIOAFQDAAAA.',
Am='Ambs:BAABNQAECn8ZAAIBAAcKYBaFvQAJAgABAAcKYBaFvQAJAgAAAA==.',
An='Analyse:BAAANQAECgEIAgAAAA==.Andalya:BAABNQAECn8hAAMKAAcK/gGjhQC7AAAKAAcK/gGjhQC7AAALAAcK+QPMLACEAAAAAA==.Andaria:BAAANQAECgQIBgAAAA==.Andarial:BAAANQAECgMIAwAAAA==.Angharrad:BAAANQADCgcICQAAAA==.',
Ao='Aonani:BAAANQADCgcIFAAAAA==.',
Ap='Aprix:BAAANQAECgYJDgAAAA==.',
Ar='Araara:BAAANQADCgUIBQAAAA==.Aralyn:BAAANQADCgcIDQAAAA==.Ardat:BAAANQADCgYIBgAAAA==.Arejay:BAAANQAECgQICAAAAA==.Argeth:BAAANQAECgEIAQAAAA==.Arshika:BAABNQAECn8dAAIHAAgKaxaXCABVAgAHAAgKaxaXCABVAgAAAA==.Artek:BAAANQADCgMIAwAAAA==.Arthan:BAAANQADCgYIBwAAAA==.Arthonix:BAAANQAECgUJCwAAAA==.Arthurleywin:BAAANQAECgUIEwAAAA==.Arvis:BAAANQAECgQICAAAAA==.',
As='Asamia:BAACNQAFFH8YAAIMAAcKnhukAABwAgAMAAcKnhukAABwAgA1AAQKfyMAAgwACgo1IaQEACoDAAwACgo1IaQEACoDAAAA.Ashaki:BAABNQAECn8kAAMNAAkKnhcYBgA1AgANAAgK/RYYBgA1AgAOAAgKRgvBFwCzAQAAAA==.Asmodéus:BAAANQADCgUIBQABNQAECgcIEQAIAAAAAA==.Astå:BAAANQAECggICAABNQAECgoKKwAPAFwdAA==.',
At='Athyná:BAAANQADCgIIAgAAAA==.',
Au='Auralius:BAAANQADCggIGQAAAA==.Auroramoon:BAABNQAECn8cAAIMAAcKeBHvBQAaAQAMAAcKeBHvBQAaAQAAAA==.',
Av='Avana:BAAANQADCgIIAgAAAA==.Avis:BAAANQAECgQIBQAAAA==.',
Aw='Awake:BAABNQAECn8dAAMQAAkK2RHUIwATAgAQAAkK2RHUIwATAgANAAEKkAK2MAAjAAAAAA==.',
Ax='Axionar:BAAANQAECggIEgAAAA==.',
Az='Azurend:BAABNQAECn8jAAIRAAgKQRfhAwC/AQARAAgKQRfhAwC/AQAAAA==.Azázél:BAAANQAECgcIEQAAAA==.',
['Aí']='Aízen:BAABNQAECn8dAAIBAAkK9xB6owA6AgABAAkK9xB6owA6AgABNQAECgoKKwAPAFwdAA==.',
Ba='Badtimeboy:BAAANQAECgEIAgAAAA==.Baffle:BAAANQADCggIGQABNQAECgoKNQASAEQiAA==.Bahula:BAABNQAECn8lAAITAAgK0A7LcAC5AQATAAgK0A7LcAC5AQAAAA==.Bainehuln:BAABNQAECn8ZAAICAAgKPRhzJwB8AQACAAgKPRhzJwB8AQAAAA==.Bastianos:BAABNQAECn8eAAMJAAcK1xxKHgByAQAJAAcK1xxKHgByAQAUAAIKuQfD8gA6AAAAAA==.Batsom:BAAANQABCgEIAQAAAA==.Battlecheeks:BAAANQADCgQIBAABNQAECgcIDgAIAAAAAA==.',
Be='Beastafied:BAAANQAECgEIAgAAAA==.Bellapearl:BAAANQAECgUIDwAAAA==.Bellmont:BAAANQAECgcICwAAAA==.Belron:BAAANQAECgMIBgABNQAECgoKNgAVAHMOAA==.Bernes:BAABNQAECn8mAAMDAAoKrB5CCwCRAQAWAAkK9RZVPAAvAgADAAgK4B5CCwCRAQAAAA==.',
Bi='Biffle:BAAANQAECggIDgABNQAECgoKNQASAEQiAA==.Bigteef:BAAANQADCgUICQAAAA==.Bioz:BAAANQAECgUIBgAAAA==.Birdhouse:BAABNQAECn8hAAMQAAkK4x3EBQCgAQAQAAgKahzEBQCgAQAOAAEKmQX5ngAxAAAAAA==.',
Bl='Blackthornn:BAACNQAFFH8ZAAMXAAYKOhvmAwASAgAXAAYKOhvmAwASAgASAAMKawfNCgCEAAA1AAQKfz0AAxcACgpVIcMFAHYDABcACQroIsMFAHYDABIAAwrJF+AdAPcAAAAA.Blastin:BAAANQADCggICgAAAA==.Blastofel:BAAANQADCgUIBQAAAA==.Blindape:BAAANQAECgEIAQAAAA==.Bloodcircus:BAAANQAECggICgAAAA==.Bloodorphan:BAAANQADCgIIAgABNQAECgoKOgAYAF4jAA==.Bloodreign:BAAANQADCgYIBgAAAA==.Bloodworm:BAAANQAECgYIDgABNQAFFAcIEAACAFYcAA==.Blottros:BAABNQAECn8XAAMKAAgKmQ03WQBvAQAKAAcKIQ83WQBvAQALAAUKbwT/XgCKAAAAAA==.Blottzilla:BAACNQAFFH8bAAIRAAYKRBFMCAC6AQARAAYKRBFMCAC6AQA1AAQKfz8AAxEACgrDH3YIABwDABEACgrDH3YIABwDABkAAQq0FH44AEoAAAAA.Bluestreak:BAAANQAECgEIBAAAAA==.',
Bo='Bobbyray:BAAANQADCggIDAAAAA==.Bobertbigg:BAABNQAECn8zAAIJAAoKohwwGwAJAwAJAAoKohwwGwAJAwAAAA==.Booda:BAAANQADCggIDQAAAA==.Boomheals:BAAANQAECgEIAQAAAA==.Boratt:BAAANQAECgUICgAAAA==.Bowbuttkick:BAACNQAFFH8QAAMCAAcKVhxuAwAuAgACAAYKGiFuAwAuAgAGAAUKkw8HEQAsAQA1AAQKfx0AAwIACgrnJCsiAA4DAAIACgrnJCsiAA4DAAYAAgoHFIVzAGoAAAAA.Bowjangles:BAEANQAECgQICAABNQAECggIIQAIAAAAAA==.Boxiebrown:BAABNQAECn8mAAICAAoKzxawYwBOAgACAAoKzxawYwBOAgAAAA==.',
Br='Bralae:BAABNQAECn8YAAIaAAcKTSMRGACcAgAaAAcKTSMRGACcAgAAAA==.Breaya:BAAANQADCgYIDAAAAA==.Brewskiez:BAAANQADCggIDwAAAA==.Bricktop:BAAANQADCgIIAgAAAA==.Broachy:BAAANQAECgEIAQAAAA==.Brokuo:BAACNQAFFH8TAAMWAAcKphupBQDJAQAWAAUKEx6pBQDJAQAbAAUKLR2GCQBSAQA1AAQKfycAAxYACgq1JOIgAMYCABYACQrVI+IgAMYCABsACQpHIFQcAKcCAAAA.Broon:BAAANQADCgYIDQAAAA==.Brucellosis:BAABNQAECn8vAAMWAAoKOhsnBgDQAQAWAAoKOhsnBgDQAQAbAAEKvQ6CqgA4AAAAAA==.Brâgak:BAAANQADCgcIDQAAAA==.',
Bu='Bubbawoodkin:BAAANQAECgUIBgAAAA==.Buffpres:BAAANQAECgQIBAABNQAECgUIDAAIAAAAAA==.Butchkween:BAAANQADCggIEAABNQAECgoKJwAcAMcQAA==.Buzzlez:BAACNQAFFH8ZAAIOAAYKYxgZBgCAAQAOAAYKYxgZBgCAAQA1AAQKfz0AAg4ACgqTI7cDALMDAA4ACgqTI7cDALMDAAAA.',
Ca='Camspally:BAAANQAECgMJBAAAAA==.Candyquartz:BAAANQADCgMIAwAAAA==.Carkleaschah:BAAANQADCgYICwABNQAECgQIBAAIAAAAAA==.Cat:BAAANQABCgIIAgAAAA==.',
Ch='Chaddrique:BAAANQAECgEIAgAAAA==.Chadgolas:BAAANQADCgIIAgAAAA==.Chadimir:BAAANQAECgQIBwAAAA==.Chahae:BAACNQAFFH8NAAMWAAUKFyUEAwASAgAWAAUKFyUEAwASAgAbAAEKQQcrIQA5AAA1AAQKfzkAAxYACgrhJYoFAKADABYACgrhJYoFAKADABsAAQrWJW2aAF4AAAAA.Channintotem:BAEANQAECgEIAQABNQAECgcIKAAUAOQgAA==.Cheerwine:BAABNQAECn8iAAMdAAkK/glgFwCDAQAdAAkK/glgFwCDAQALAAcKPxBPFAAiAQAAAA==.Cheezits:BAAANQAECgcICwAAAA==.Chinnook:BAAANQADCgYIBgAAAA==.Chronicle:BAAANQAECggIDAAAAA==.',
Cl='Clapdo:BAECNQAFFH8PAAMeAAUKXyC/FwBiAQAeAAUKXyC/FwBiAQAfAAEKAABeBQBPAAA1AAQKfyUAAx4ACgq3JJshADIDAB4ACgq3JJshADIDAB8AAQoAADEwAD8AAAAA.Clinician:BAABNQAECn8dAAMOAAoKvxTPNwCJAgAOAAoKvxTPNwCJAgAQAAYKvQ4fPgA7AQAAAA==.Clowncar:BAAANQAECgEIAQAAAA==.',
Co='Commandor:BAAANQAECgEIAwAAAA==.Congolense:BAAANQAECgYIDAAAAA==.Corbzz:BAAANQAECgMIAwAAAA==.Cougrogue:BAAANQAECgQIDQAAAA==.Cowacusrex:BAAANQAECgMIAQAAAA==.',
Cp='Cptrisky:BAAANQABCgIIAgAAAA==.',
Cr='Crazzenburns:BAABNQAECn8fAAQgAAgKFRhZJgDwAQAgAAgKFRhZJgDwAQAhAAMKeQ3OOwCUAAAMAAEK+g9zMgAtAAAAAA==.Creamer:BAABNQAECn8eAAMTAAoKsA5/ZQDcAQATAAoKsA5/ZQDcAQAPAAEK1QiFNwEyAAAAAA==.Crunchin:BAABNQAECn8uAAMUAAkKGBeJmwDsAQAUAAgK1BWJmwDsAQAJAAkK8AVpfQChAQAAAA==.',
Cu='Cutedwarfxd:BAACNQAFFH8TAAIDAAcKbSOXAwBWAgADAAcKbSOXAwBWAgA1AAQKfygAAgMACgpHJi0FAJ8DAAMACgpHJi0FAJ8DAAAA.',
Da='Dajariel:BAAANQAECgEIAgAAAA==.Dakkadakka:BAAANQAECggICgAAAA==.Damane:BAAANQADCgYICwABNQAECgUICAAIAAAAAA==.Danìel:BAACNQAFFH8bAAIVAAYKbRYlAgBkAQAVAAYKbRYlAgBkAQA1AAQKfzwAAxUACgoXIsAIAHEDABUACgoXIsAIAHEDABoACApvFT4uAM8BAAAA.Darkarts:BAAANQADCgIIAgAAAA==.Darkmoore:BAAANQADCgUIBQAAAA==.Dartwo:BAABNQAECn8aAAIPAAcKRhDLJgAhAQAPAAcKRhDLJgAhAQAAAA==.',
De='Deadalicious:BAAANQAECgYIDQABNQAECgoKNgAVAHMOAA==.Deathspoons:BAACNQAFFH8gAAIDAAcKTxqtAgB3AgADAAcKTxqtAgB3AgA1AAQKfzIAAwMACgrsIrwNAEIDAAMACgrsIrwNAEIDABYAAQpKIZbKAFcAAAAA.Delecto:BAABNQAECn8ZAAIiAAYK6BsyCQD+AQAiAAYK6BsyCQD+AQAAAA==.Delmônico:BAAANQADCgYIDQAAAA==.Delushoni:BAAANQADCgUIBQAAAA==.Dendalaus:BAACNQAFFH8aAAMSAAYKsRx6BADlAQASAAUKlxl6BADlAQAXAAEK/SXUBgBjAAA1AAQKfzkAAxIACgpDJp8LALoCABIABwpdI58LALoCABcABQroJZMPAEgBAAAA.Derkamental:BAAANQAECgIIAgAAAA==.Devora:BAEANQADCggICAABNQAECgcIKAAUAOQgAA==.Dextersmash:BAAANQAECgYICQAAAA==.',
Di='Digallo:BAAANQAECgUIBwAAAA==.Dimsumbun:BAABNQAECn8iAAIEAAkKjgueLwA5AQAEAAkKjgueLwA5AQAAAA==.Dingledorf:BAAANQAECgYIEwAAAA==.Dinklebahmp:BAABNQAFFH8IAAIjAAYKXRBaBACQAQAjAAYKXRBaBACQAQABNQAFFAYIEwAkADceAA==.Dinoxeye:BAABNQAECn8ZAAIWAAcKeAT/igD4AAAWAAcKeAT/igD4AAAAAA==.Discosdead:BAAANQADCgUIBQABNQAECgEIAgAIAAAAAA==.',
Do='Donut:BAAANQAECgQIBAAAAA==.',
Dr='Draacarys:BAAANQAECgEIAQAAAA==.Dragonpandas:BAAANQAECgEIAQABNQAECgkJMgAWAPQjAA==.Dramonk:BAACNQAFFH8LAAIgAAYKSAyXCQA3AQAgAAYKSAyXCQA3AQA1AAQKfycAAiAACgpwIFYPAO4CACAACgpwIFYPAO4CAAAA.Drizzett:BAABNQAECn8VAAIGAAcKKQMFGgC7AAAGAAcKKQMFGgC7AAAAAA==.Dro:BAAANQAECgEIAQAAAA==.Drogbar:BAAANQAECgEIAQAAAA==.Druinlock:BAAANQADCgUIBQAAAA==.Druiske:BAAANQAECgUICQAAAA==.',
Du='Dustydrewid:BAAANQADCgEIAQAAAA==.',
Dy='Dyre:BAAANQAECggICgAAAA==.',
Ei='Eir:BAABNQAECn8uAAIJAAoKfw0iWwAHAgAJAAoKfw0iWwAHAgAAAA==.',
El='Elefury:BAAANQAECgEIAQAAAA==.Ellsnarl:BAAANQADCgYIBgAAAA==.',
Em='Emeraldjin:BAABNQAECn81AAIhAAoKRiPYAAA6AwAhAAoKRiPYAAA6AwAAAA==.',
En='Ensera:BAABNQAECn8WAAQRAAcK8gj9MQAKAQARAAYK1Aj9MQAKAQAcAAQKtAsrFwDBAAAZAAIKUwYXOwA5AAAAAA==.',
Er='Eraesong:BAAANQADCgMIAwAAAA==.Erielyn:BAABNQAECn8cAAIaAAkK8RQgIgA5AgAaAAkK8RQgIgA5AgAAAA==.Ernet:BAABNQAECn8pAAIBAAgKlBJLugAPAgABAAgKlBJLugAPAgAAAA==.',
Eu='Eugenekrabs:BAAANQADCgYIBgAAAA==.',
Ex='Extraho:BAABNQAECn8wAAIOAAgKkCN9CQBOAgAOAAgKkCN9CQBOAgAAAA==.',
Ez='Ezo:BAAANQAECgEIAQAAAA==.',
Fa='Fabled:BAACNQAFFH8TAAQFAAcKBhqABwC2AAAEAAUKjBfSFQBIAQAFAAIK9SCABwC2AAAlAAEKAAAFCQBdAAA1AAQKfycAAwUACgq5ItkEANUCAAUACAoMINkEANUCAAQABgrPH3iWAK4BAAAA.Faeyice:BAABNQAECn8eAAISAAcKWQUEJADUAAASAAcKWQUEJADUAAAAAA==.Fat:BAAANQADCgMIAwAAAA==.',
Fe='Fearmachine:BAAANQADCggIFAABNQAECggIEgAIAAAAAA==.Feyden:BAAANQAECgUIDwAAAA==.',
Ff='Ffxivcatgirl:BAAANQADCgQIBAABNQAFFAcIEwADAG0jAA==.',
Fi='Fielton:BAAANQAECgQIBwABNQAECgoKHgAUAIkiAA==.Fiiryazell:BAAANQAECgEIAgAAAA==.Fijasdkanda:BAAANQAECgEIAQAAAA==.Fijaswarerth:BAACNQAFFH8KAAIkAAYKUhx+AQDHAQAkAAYKUhx+AQDHAQA1AAQKfysAAyQACgpsJdwAANQDACQACgpsJdwAANQDAB4ABAqoFmenAFwAAAAA.Fijaswitcher:BAABNQAECn8WAAIlAAgKOxU8BwAtAgAlAAgKOxU8BwAtAgAAAA==.Fimbulvargr:BAABNQAECn8lAAIDAAcKpg6UIwDpAAADAAcKpg6UIwDpAAAAAA==.Finiith:BAAANQAECgUJCAABNQAFFAYIGwACAOwWAA==.Finîth:BAAANQAECgUIDAABNQAFFAYIGwACAOwWAA==.Firebrands:BAAANQAECgIIAgAAAA==.Firedragön:BAAANQAECgMIAwAAAA==.Firelordz:BAAANQADCgQIBAAAAA==.',
Fl='Flogdanoggin:BAAANQADCgcIBwAAAA==.Flogurnoggin:BAAANQADCggIBQAAAA==.Fluffly:BAAANQADCggICAAAAA==.Fluffyokami:BAABNQAECn8kAAMdAAgKyRqkDABYAgAdAAgKyRqkDABYAgAKAAEKYgr3UgAzAAAAAA==.Flyingrodent:BAABNQAECn8pAAMZAAkKcSCREwAWAgAZAAYK7R2REwAWAgARAAgKsBOrIwCoAQAAAA==.',
Fo='Foneer:BAABNQAECn8lAAIgAAgK4g1EMACVAQAgAAgK4g1EMACVAQAAAA==.Forestsky:BAABNQAECn8hAAIVAAgKYxc0DQCFAQAVAAgKYxc0DQCFAQAAAA==.',
Fr='Freezepop:BAABNQAECn8vAAIBAAoKAyGyJwBDAwABAAoKAyGyJwBDAwAAAA==.Frenchieboi:BAAANQAECgUIDQABNQAECgoKGwAEACoLAA==.Frenchielock:BAABNQAECn8bAAMEAAoKKgu0EAC9AQAEAAkKKgu0EAC9AQAFAAQKzQPfQgC5AAAAAA==.Frenchthyr:BAAANQAECgUIDgABNQAECgoKGwAEACoLAA==.Frostbeast:BAAANQADCgEIAQAAAA==.',
Ga='Gaden:BAAANQAECgQIBwAAAA==.Galdiian:BAAANQAECgUIDwAAAA==.Gatebtch:BAAANQAFFAEIAQAAAA==.Gawdspet:BAACNQAFFH8HAAMFAAMK0w0CFABsAAAEAAIKkBGfMQCTAAAFAAIKWwMCFABsAAA1AAQKfzUAAwQACgqNHvc/AJICAAQACQpzHPc/AJICAAUABAptGX0rACIBAAAA.',
Gh='Ghosi:BAABNQAECn8jAAMjAAoKPBhRFwBAAgAjAAoKPBhRFwBAAgAUAAEKeglXqgEyAAAAAA==.',
Gl='Glaivier:BAAANQAECgQICwAAAA==.Glitchhunt:BAAANQAECgcICAAAAA==.',
Go='Goodtimeboy:BAAANQADCgYIBwAAAA==.Goregrind:BAACNQAFFH8WAAQbAAYKhiDJAQBmAQAWAAUKvh+0BgCyAQAbAAQKDxnJAQBmAQADAAEKAAA1OQAgAAA1AAQKfyoAAxYACgqeI10MAFcDABYACQoCJF0MAFcDABsAAQrlIJBSAGoAAAAA.Gorehound:BAAANQAECgQIBgAAAA==.Gorgeous:BAAANQADCgIIAgAAAA==.Gorius:BAAANQADCggILgAAAA==.Gotooguy:BAAANQADCgUIBQAAAA==.',
Gr='Grampman:BAAANQAECgYIBgAAAA==.Gremory:BAABNQAECn8jAAMKAAgKjhezCwCGAQAKAAgKExezCwCGAQAmAAIKrh4uRgCaAAAAAA==.Grimholt:BAAANQAECgEIAQAAAA==.',
Gu='Guldank:BAAANQAECgUIEQAAAA==.Guretta:BAABNQAECn8lAAIkAAcKXBUnCAA0AQAkAAcKXBUnCAA0AQAAAA==.',
Gw='Gwynhwyvar:BAABNQAECn8UAAIOAAYKOwfiWgC+AAAOAAYKOwfiWgC+AAAAAA==.',
Ha='Haeneros:BAABNQAECn8aAAInAAgKnRNYEQCbAQAnAAgKnRNYEQCbAQAAAA==.Handmemytank:BAAANQAECgQIBgABNQAFFAUIDAACANEbAA==.Harumi:BAAANQAECgYIEwAAAA==.',
He='Healeta:BAAANQAECgMIBgAAAA==.Hearo:BAAANQAECgEIAwAAAA==.Heavyhead:BAAANQAECgYIBwAAAA==.Heavypudding:BAAANQAECgUIDQAAAA==.Hedgehog:BAABNQAECn86AAMhAAoKfw+hDAALAQAhAAoKfw+hDAALAQAgAAYK9Qa/HQC8AAAAAA==.Heightning:BAAANQAECgQICQAAAA==.Heisenberf:BAACNQAFFH8ZAAMBAAYKfg8VFADXAQABAAYKfg8VFADXAQAHAAEKxRciBwBWAAA1AAQKfz0AAwEACgpxIWIxACkDAAEACgpOIWIxACkDAAcAAQrsHPQ6AFMAAAAA.Hextrathicc:BAABNQAECn89AAIEAAoK+BvLBQBZAgAEAAoK+BvLBQBZAgAAAA==.',
Ho='Holybuttkick:BAABNQAECn8jAAQjAAoKABwiHgD4AQAjAAYKvyAiHgD4AQAJAAoKHxUiJQBOAQAUAAEK4xa7kQFCAAABNQAFFAcIEAACAFYcAA==.Honorius:BAAANQAECgYICwAAAA==.Hoozurdaddy:BAABNQAECn8iAAIPAAkKTRWvTQBAAgAPAAkKTRWvTQBAAgAAAA==.',
Ia='Iamdownhere:BAAANQABCgYICgAAAA==.',
Ic='Iceicelady:BAAANQADCgMIAwAAAA==.',
Ig='Igamm:BAAANQADCgYIDAAAAA==.Ignatius:BAAANQAECgQIBwAAAA==.Igniting:BAABNQAECn8tAAIBAAoKYxjgWQDMAgABAAoKYxjgWQDMAgABNQAECgQICwAIAAAAAA==.',
Ik='Ikillyoutoo:BAAANQAECgcIEAAAAA==.Ikki:BAAANQAECggJCgAAAA==.',
Il='Illuzions:BAAANQAECgYICwAAAA==.',
Im='Impdh:BAAANQAECgIIAgABNQAFFAcIEwAJAJwjAA==.Impenetrable:BAAANQAECgMIAwAAAA==.Impression:BAACNQAFFH8TAAMJAAcKnCOKAgCCAgAJAAYKtiOKAgCCAgAjAAEKwQ+vBgBUAAA1AAQKfyMAAgkACgpwJgABAOUDAAkACgpwJgABAOUDAAAA.Imprison:BAAANQAECgIIAwABNQAFFAcIEwAJAJwjAA==.',
In='Incarnated:BAABNQAECn8ZAAMJAAoKlBuiHwDxAgAJAAoKlBuiHwDxAgAUAAEKAADflQE+AAAAAA==.Incursion:BAABNQAECn8mAAMJAAkKKRP6WQALAgAJAAkKKRP6WQALAgAUAAYK4Qg8AwEaAQAAAA==.Inelor:BAAANQAECgEIAgABNQAECgcIGAAaAE0jAA==.Insayn:BAAANQADCgIIAgABNQAECgkJKAAUAK0lAA==.Inviçtus:BAAANQAECgQIBQAAAA==.',
Io='Ioboryu:BAAANQAECgMIBAABNQAFFAcIEAAaAAQcAA==.',
Ir='Ironwolf:BAABNQAECn85AAIkAAoKSg7iAwChAQAkAAoKSg7iAwChAQAAAA==.',
Ja='Jacedark:BAAANQAECgEIAQAAAA==.Jademoot:BAABNQAECn8hAAIhAAgK4BhQFAA2AgAhAAgK4BhQFAA2AgAAAA==.Jadis:BAAANQADCgUIBQAAAA==.Jaeaoria:BAAANQABCgIIAQAAAA==.Jandren:BAAANQAECgEIAgAAAA==.Jaxblack:BAAANQADCggIEAAAAA==.Jaxurbate:BAAANQAECgIJAwAAAA==.Jaylaah:BAAANQAECgQIBgAAAA==.Jayvlyn:BAABNQAECn8UAAIPAAcKsQ0ZGQBbAQAPAAcKsQ0ZGQBbAQAAAA==.',
Je='Jessex:BAAANQAECgEIBAAAAA==.',
Ji='Jiinn:BAAANQAECgUICgAAAA==.',
Jj='Jjman:BAAANQAECgYIBwABNQAECgoKHgAUAIkiAA==.Jjuicyfruit:BAAANQADCgcIGAAAAA==.',
Jo='Jodirty:BAAANQADCgYIBgAAAA==.Joftokal:BAABNQAECn8tAAIPAAkKwRNUCgDDAQAPAAkKwRNUCgDDAQAAAA==.Jokesonme:BAAANQAECgMICQAAAA==.Jonebonejovi:BAAANQADCgIIAgAAAA==.Jorabna:BAAANQADCgYICgAAAA==.Joyboy:BAABNQAECn8eAAIJAAoKkSAkFwAgAwAJAAoKkSAkFwAgAwAAAA==.',
Ju='Jumbodab:BAAANQAECgUIBQAAAA==.Junpana:BAAANQAECgYIBwAAAA==.',
Ka='Kakiso:BAABNQAECn8hAAMjAAkKCRRKIgDQAQAjAAgKGRZKIgDQAQAUAAYKCwwhFgH6AAAAAA==.Kalanash:BAAANQADCgUIBQAAAA==.Kalim:BAAANQADCgIIAgAAAA==.Kaloneras:BAAANQADCgYICAAAAA==.Kasuke:BAAANQADCgEIAQAAAA==.Kattle:BAACNQAFFH8KAAIYAAYKfxxmAQALAgAYAAYKfxxmAQALAgA1AAQKfzgAAhgACgrQI28DAGcDABgACgrQI28DAGcDAAAA.Katzingah:BAAANQAECgQIBAAAAA==.',
Ke='Kellistus:BAAANQADCgUICQAAAA==.Keyrasky:BAAANQAECgMIAwAAAA==.',
Kh='Khailyn:BAAANQADCgIJAgAAAA==.',
Ki='Kikuu:BAABNQAECn8oAAIjAAkKDyElDQDJAgAjAAkKDyElDQDJAgAAAA==.Killadin:BAAANQAECgEIAQAAAA==.Kin:BAAANQADCggICwAAAA==.Kincaid:BAAANQAECgIIBAAAAA==.Kiradanna:BAABNQAECn80AAIaAAoKzR1eDQAPAwAaAAoKzR1eDQAPAwAAAA==.Kiroa:BAABNQAECn8YAAIDAAUKJAlrMQCwAAADAAUKJAlrMQCwAAAAAA==.Kiyoshiru:BAAANQADCgUIBQAAAA==.',
Kl='Kloud:BAAANQAECggIAgABNQAECggIBgAIAAAAAA==.',
Kn='Knoks:BAABNQAECn8nAAMEAAoK9BfmFACjAQAEAAgKtBXmFACjAQAFAAMKnxjJCQCBAAAAAA==.Knotty:BAAANQAECgcIDgAAAA==.',
Ko='Koff:BAACNQAFFH8PAAIhAAUKnyUAAgAgAgAhAAUKnyUAAgAgAgA1AAQKfyAAAiEACgo/JeMCAIoDACEACgo/JeMCAIoDAAAA.Koino:BAAANQAECgUIBQAAAA==.Koreshei:BAAANQAECgUICQAAAA==.Koressita:BAAANQADCgYIBgAAAA==.',
Kr='Krixxus:BAAANQAECgQICQABNQAECgUICwAIAAAAAA==.',
Ku='Kuni:BAAANQAECgYIJAAAAQ==.Kurius:BAAANQAECgQICwAAAA==.',
Ky='Kylian:BAAANQAECggIEAABNQAECgoKNAAaAM0dAA==.',
La='Lamynx:BAABNQAECn8XAAMXAAYK/wWRZQAdAQAXAAYK/wWRZQAdAQAiAAEKAABjHgAiAAAAAA==.Larinstore:BAAANQAECggIAwAAAA==.Lazydragon:BAABNQAECn8oAAQUAAgKOA8iNwBcAQAUAAgKOA8iNwBcAQAJAAIKUgftBwFnAAAjAAIKQAiRZgBIAAAAAA==.',
Le='Lelouch:BAABNQAECn8YAAIEAAgK+gxgSwDxAAAEAAgK+gxgSwDxAAABNQAECgoKKwAPAFwdAA==.Leomidas:BAAANQAECgEIAQAAAA==.Leone:BAAANQAECgQIBAABNQAECgkJKgAEAG4cAA==.',
Li='Liberation:BAABNQAECn8YAAIaAAcK8xeqMAC8AQAaAAcK8xeqMAC8AQAAAA==.Lichhorde:BAAANQAECgEIAgAAAA==.Lileda:BAAANQAECgMIAgAAAA==.Lilgirlblue:BAABNQAECn8fAAICAAkKgg6OhAACAgACAAkKgg6OhAACAgAAAA==.Lilreggie:BAAANQADCggIFAAAAA==.Lilvoids:BAABNQAECn8xAAMFAAoKbwxLIgBfAQAFAAcKCwlLIgBfAQAEAAgKrQosZQC4AAAAAA==.Lineste:BAABNQAECn8gAAIBAAgKmx5qEQDbAQABAAgKmx5qEQDbAQAAAA==.Lion:BAAANQAECgYIEgAAAA==.',
Ll='Llyolis:BAAANQAECgUICwAAAA==.',
Lo='Lockdeeznutz:BAAANQADCggIDAAAAA==.Loldie:BAABNQAECn8WAAMFAAgKHgNtQQC+AAAEAAgKHgOS5QD+AAAFAAYKNgJtQQC+AAAAAA==.Lonepanda:BAACNQAFFH8TAAIkAAYKNx4JAQD/AQAkAAYKNx4JAQD/AQA1AAQKfzcAAiQACgrpI4QBALgDACQACgrpI4QBALgDAAAA.Lorwynx:BAABNQAECn8xAAIBAAkKTiC5LQAyAwABAAkKTiC5LQAyAwAAAA==.',
Lu='Luciliv:BAAANQADCgYIBgABNQAECgkJKAAUAK0lAA==.Lunado:BAAANQADCgUIBwAAAA==.Lupinaea:BAAANQAECgMIBAAAAA==.',
Lv='Lvcifur:BAAANQABCgQIBAAAAA==.',
Ma='Mabellah:BAAANQAECgYIDgAAAA==.Madara:BAAANQAECggICAABNQAECgoKKwAPAFwdAA==.Maemikyu:BAABNQAECn9fAAIOAAoK8yTmAgC9AwAOAAoK8yTmAgC9AwAAAA==.Magebuttkick:BAAANQAECgEIAQABNQAFFAcIEAACAFYcAA==.Magusultimis:BAABNQAECn8dAAIHAAgKDAVaGAA2AQAHAAgKDAVaGAA2AQAAAA==.Mahöshöjo:BAAANQAECgQIDAAAAA==.Maintank:BAAANQAECgUIEAAAAA==.Makepoop:BAABNQAECn8qAAIQAAkKZiGcCwAsAwAQAAkKZiGcCwAsAwAAAA==.Maloa:BAAANQAECgEIAQAAAA==.Manbomanbo:BAAANQAECgQIBQABNQAECggIBAAIAAAAAA==.Marianita:BAABNQAECn8fAAMVAAoK8x6DFgDoAgAVAAoK8x6DFgDoAgAaAAEKAAB5awA3AAAAAA==.Maureen:BAAANQADCgUIBQAAAA==.',
Me='Mediarahan:BAAANQAECgMICQAAAA==.Melfist:BAABNQAECn8YAAMgAAgKBhRbNQBqAQAgAAgKBhRbNQBqAQAhAAMKaQa4QABzAAAAAA==.Melphis:BAAANQADCgcIBwAAAA==.Melysse:BAABNQAECn8YAAInAAkK0xFDDQDtAQAnAAkK0xFDDQDtAQAAAA==.Mendocino:BAAANQAECgEIAQAAAA==.Mereo:BAABNQAECn8aAAIgAAcK9RSEDQBHAQAgAAcK9RSEDQBHAQABNQAECgoKKwAPAFwdAA==.',
Mi='Mikiko:BAABNQAECn8yAAIPAAkKOQ1mLQAIAQAPAAkKOQ1mLQAIAQAAAA==.Mikto:BAAANQAECgEIAQAAAA==.Millcreek:BAABNQAECn8jAAILAAgKuQyuDQBiAQALAAgKuQyuDQBiAQAAAA==.Milliananeko:BAAANQAECgQIBQABNQAECgkJFwAjAOcFAA==.Miracat:BAAANQAECgUIDAAAAA==.Missindragon:BAABNQAECn8tAAITAAkKTSCzBwBLAgATAAkKTSCzBwBLAgAAAA==.',
Mo='Moarass:BAAANQADCggIEAABNQAECgoKJwALAIIVAA==.Moomoohead:BAAANQAECgQIBgABNQAECgcIDgAIAAAAAA==.Morberto:BAAANQABCggICgAAAA==.Morianne:BAAANQADCgQIBAAAAA==.Mormel:BAABNQAECn8eAAIdAAcKHhCNCAAfAQAdAAcKHhCNCAAfAQAAAA==.Morticus:BAABNQAECn8eAAMFAAgKmQZLBgDAAAAFAAcKIgdLBgDAAAAEAAYKAgNPDwGtAAAAAA==.',
Ms='Msthea:BAABNQAECn8cAAMdAAcKKBFEGwBOAQAdAAcKKBFEGwBOAQALAAMKEQbmLwBwAAAAAA==.',
My='Mythicc:BAAANQADCgUIAgABNQADCggIDQAIAAAAAA==.',
['Mä']='Mälina:BAAANQAECgMICAAAAA==.',
Na='Narial:BAAANQADCgIIAQAAAA==.Narrthas:BAAANQAECgUIDAAAAA==.Narru:BAACNQAFFH8QAAICAAYKYxzABQD3AQACAAYKYxzABQD3AQA1AAQKfzMABAIACgomIykGAK4DAAIACgomIykGAK4DAAYABQrEC7ZRAOMAACgABAoaC8UOALAAAAAA.',
Ne='Nebyula:BAABNQAECn8cAAIOAAcKMRVnJABvAQAOAAcKMRVnJABvAQAAAA==.',
Ni='Nightswitchh:BAAANQAECgcIBwAAAA==.Nizuno:BAAANQADCgYIBgAAAA==.',
No='Norieka:BAABNQAECn8cAAIUAAcKDBQpSwAuAQAUAAcKDBQpSwAuAQAAAA==.Norvasc:BAAANQADCgEIAQAAAA==.Noskillidan:BAAANQAECgUIBwABNQAFFAYIGQABAH4PAA==.Notknoks:BAAANQADCggICAAAAA==.',
Nu='Numinous:BAAANQAECgMIBgABNQAECgkJKgAeALoWAA==.',
Ny='Nykoleus:BAAANQAECgYICgAAAA==.Nylokar:BAAANQADCgQIBAAAAA==.Nyteofsin:BAAANQABCgYICwAAAA==.',
Oa='Oatbarrel:BAAANQADCgcIDwAAAA==.Oatbreaker:BAAANQADCgYICgAAAA==.',
Od='Odell:BAAANQAECgEIAQAAAA==.',
Og='Oggoat:BAAANQAECgUICgAAAA==.',
Oi='Oignon:BAAANQADCggICAAAAA==.',
Ol='Olive:BAAANQAECgcIDgAAAA==.',
Oz='Ozyy:BAAANQAECgEIAQAAAA==.',
Pa='Painindaazz:BAAANQADCgYIEgAAAA==.Paligator:BAAANQADCgcIDQAAAA==.Pallyfraud:BAAANQADCgIIAgAAAA==.Pallygranny:BAEBNQAECn8oAAIUAAcK5CCzXwB6AgAUAAcK5CCzXwB6AgAAAA==.Pawptart:BAAANQABCgQIBAAAAA==.',
Ph='Phyntom:BAAANQAECgMIBwAAAA==.',
Pi='Pibbs:BAACNQAFFH8HAAIBAAUKgBSvHQCUAQABAAUKgBSvHQCUAQA1AAQKfyoAAgEACgq9Iv0oAHUBAAEACgq9Iv0oAHUBAAAA.',
Pl='Plaguepanda:BAABNQAECn8yAAQWAAkK9COXGQDzAgAWAAkKUiKXGQDzAgAbAAkKPx+vFADnAgADAAEKFRoFywAzAAAAAA==.Platinumcas:BAAANQAECgIIAgAAAA==.Pluribus:BAAANQADCgcIDgAAAA==.',
Po='Poohonroids:BAAANQAECgYIDgAAAA==.Poppatroll:BAAANQADCggIEgAAAA==.',
Pr='Priestpvp:BAAANQAECgEIAQAAAA==.Priva:BAAANQADCggICgAAAA==.Protagoras:BAAANQAECgEIBAAAAA==.',
['Pä']='Pänz:BAABNQAECn8fAAMdAAkKAwwgFAC6AQAdAAkKAwwgFAC6AQAmAAEKHwfsZwAmAAAAAA==.',
Ra='Rafig:BAACNQAFFH8bAAIBAAYKnCXMBAB9AgABAAYKnCXMBAB9AgA1AAQKfz0AAgEACgrzJQ0CAO0DAAEACgrzJQ0CAO0DAAAA.Ragefyre:BAAANQAECgIJBAAAAA==.Ralii:BAAANQADCgUIBQAAAA==.Ralobii:BAAANQAECgcJDwABNQADCgUIBQAIAAAAAA==.Ramellis:BAAANQADCgMIAwAAAA==.Ramses:BAACNQAFFH8OAAMPAAYKPgjRCADFAAAPAAUK4QTRCADFAAATAAEK2wCmGQA6AAA1AAQKfy8AAw8ACgr+FJ5PADkCAA8ACgr+FJ5PADkCABMACQqLDwZsAMcBAAAA.Ratbasterd:BAAANQAECggICAAAAA==.Rats:BAAANQAECgIIAgAAAA==.Rayve:BAAANQAECgEIAQAAAA==.Rayy:BAABNQAECn8fAAIVAAkKwyBzDQA8AwAVAAkKwyBzDQA8AwAAAA==.Razgar:BAAANQAECgMIBAAAAA==.',
Re='Reeji:BAAANQAECgMIAwAAAA==.Reinerbraun:BAAANQADCgcICAAAAA==.Renade:BAABNQAECn8rAAIXAAkKEhe5KQBGAgAXAAkKEhe5KQBGAgAAAA==.Rexx:BAAANQADCgMIAwAAAA==.Reywhite:BAAANQAECgEIAgABNQAECgQICQAIAAAAAA==.',
Rh='Rhazzah:BAAANQAECgQICAAAAA==.',
Ri='Rigidsxz:BAAANQADCgUIBQAAAA==.Riskymonk:BAAANQADCgIIAgAAAA==.Riskyshammy:BAABNQAECn87AAMTAAoKwRuEJgDKAgATAAoKwRuEJgDKAgAPAAEKAAC+SAEqAAAAAA==.Riteaid:BAAANQAECgQICwAAAA==.Ritual:BAAANQAECgQIBAABNQAECgkJKAAUAK0lAA==.',
Ro='Robe:BAAANQAECgMIBQABNQAECgkJFwAjAOcFAA==.Rolexor:BAAANQADCgEIAQAAAA==.Ronok:BAABNQAECn8YAAMfAAgKNwunHADiAAAeAAgKZwiQtACZAQAfAAQKwQ2nHADiAAAAAA==.Rorthach:BAAANQAECgEIAQAAAA==.Roru:BAABNQAECn9RAAMEAAoKcBWhFgCaAQAEAAoKcBWhFgCaAQAFAAQK5gIhUwCFAAAAAA==.Roseire:BAAANQAECgQICQAAAA==.Rosethebrute:BAABNQAECn8tAAIeAAgKhR4tTwCcAgAeAAgKhR4tTwCcAgAAAA==.Rosetheholy:BAABNQAECn8WAAIQAAgKew71LAC+AQAQAAgKew71LAC+AQABNQAECggILQAeAIUeAA==.Rougeloving:BAABNQAECn8YAAISAAkKdRkmEQBuAgASAAkKdRkmEQBuAgAAAA==.',
Ru='Ruler:BAABNQAECn8YAAIgAAkKjBzSFACuAgAgAAkKjBzSFACuAgAAAA==.Ruli:BAABNQAECn9EAAICAAoKvh8eCQA0AgACAAoKvh8eCQA0AgAAAA==.Rusticdiino:BAAANQADCgEIAQABNQAECgoKKAAPANwdAA==.',
Ry='Ryshin:BAABNQAECn8wAAMXAAkKehXYKABLAgAXAAkKehXYKABLAgASAAUKaQb6NQAJAQAAAA==.',
['Rø']='Rørs:BAAANQADCgcIBwAAAA==.',
Sa='Sabeck:BAABNQAECn8eAAIUAAoKiSJBJgAsAwAUAAoKiSJBJgAsAwAAAA==.Safi:BAAANQAECgEIAQAAAA==.Saltine:BAEBNQAECn8WAAMhAAYKWh3GAwDoAQAhAAYKWh3GAwDoAQAgAAIK3AvdYABcAAABNQAECggIIQAIAAAAAA==.Sanctano:BAAANQAECgcIDwAAAA==.Saneras:BAAANQAECgUIEAAAAA==.Sapdo:BAEANQAFFAIIAgABNQAFFAUIDwAeAF8gAA==.Sarshia:BAAANQADCgYJCAAAAA==.Sayn:BAABNQAECn8oAAIUAAkKrSWgCAC3AwAUAAkKrSWgCAC3AwAAAA==.',
Sc='Schultzies:BAABNQAECn8uAAMNAAoKLx8vAwDLAgANAAgKyB4vAwDLAgAOAAoKPBscFwC4AQAAAA==.Scorchdk:BAAANQADCggIDQAAAA==.',
Sd='Sdog:BAAANQAECgUIBgAAAA==.',
Se='Seanboyydwar:BAAANQAECgMIAgAAAA==.Seanboyymage:BAACNQAFFH8KAAIBAAMKHRLWGwCOAAABAAMKHRLWGwCOAAA1AAQKfzwAAgEACQrcHnY1AB8DAAEACQrcHnY1AB8DAAAA.Seina:BAABNQAECn8mAAIeAAgKXhf7GQCeAQAeAAgKXhf7GQCeAQAAAA==.Sensei:BAAANQAECgEIAQAAAA==.Sephirofl:BAAANQAECgQIDAAAAA==.Seulrene:BAABNQAECn8mAAIWAAgKIyDGGwDlAgAWAAgKIyDGGwDlAgAAAA==.Seyna:BAAANQADCgcICgABNQAECgcIFgARAPIIAA==.',
Sh='Shake:BAAANQAECgIIAgAAAA==.Shambella:BAAANQAECgYICgAAAA==.Shamlaw:BAABNQAECn8eAAITAAgKnhhIVgAPAgATAAgKnhhIVgAPAgAAAA==.Shammydavis:BAAANQAECgIIAwAAAA==.Shampayn:BAAANQAECgUIDwAAAA==.Shankiee:BAAANQAECgEIAQAAAA==.Shanti:BAABNQAECn8fAAMgAAcKHgjLGQDaAAAgAAcKHgjLGQDaAAAhAAMKwwFiRwBMAAAAAA==.Shhuffle:BAABNQAECn81AAMSAAoKRCLwAQCBAgASAAoKjSHwAQCBAgAXAAgKbx2NIQB4AgAAAA==.Shieldmommy:BAAANQAECgUICQABNQAFFAYIGQABAH4PAA==.Shiv:BAAANQAECgYIDgAAAA==.Shockuse:BAAANQAECgcIDQAAAA==.Shodoch:BAAANQADCgYIGAAAAA==.Shorukin:BAAANQAECgQIBQAAAA==.Shupasins:BAABNQAECn87AAQTAAoKtB8UGQAOAwATAAoKtB8UGQAOAwAPAAgKrhi8XQAJAgAYAAYK8RZBGADkAQAAAA==.Shyamablue:BAABNQAECn8ZAAImAAgKXwcBLgAqAQAmAAgKXwcBLgAqAQAAAA==.',
Si='Silvercas:BAABNQAECn8mAAISAAoKlRWCEgBcAgASAAoKlRWCEgBcAgAAAA==.Simpleyfire:BAABNQAECn8oAAMPAAoK3B2NGwAkAwAPAAoK3B2NGwAkAwATAAcKyREUgwCDAQAAAA==.',
Sk='Skullet:BAABNQAECn8eAAIeAAkKwg1yQQAgAQAeAAkKwg1yQQAgAQAAAA==.Skurmpls:BAAANQADCgcICgABNQAECgYIEAAIAAAAAA==.Skândranon:BAAANQAECgEIAQAAAA==.',
Sl='Slamjam:BAABNQAFFH8IAAIeAAUKRBfcAwBiAQAeAAUKRBfcAwBiAQABNQAFFAYIEwAQAKwhAA==.Slimshadyy:BAAANQADCgQIBQAAAA==.Slurpee:BAABNQAECn8hAAIBAAcKBBHtfgDDAAABAAcKBBHtfgDDAAAAAA==.',
Sm='Smooth:BAABNQAECn82AAMBAAoK5hdpWwDJAgABAAoKpRdpWwDJAgAHAAQKNhK5JADIAAAAAA==.',
Sn='Snaphance:BAABNQAECn8gAAIXAAcK6w9NEABCAQAXAAcK6w9NEABCAQAAAA==.Sneekypete:BAAANQAECgEIAQAAAA==.Sniffer:BAAANQAECgYIDQAAAA==.Sniparcat:BAAANQADCgYIDgAAAA==.Snipercat:BAABNQAECn8jAAIeAAoKNRRVbgBIAgAeAAoKNRRVbgBIAgAAAA==.Snuffles:BAABNQAECn8kAAIUAAcKbh7xaQBeAgAUAAcKbh7xaQBeAgAAAA==.Snøkie:BAAANQADCgcIDQAAAA==.',
So='Solange:BAAANQADCgYIBgAAAA==.Sorscha:BAAANQAECgEIAgAAAA==.Soupforsale:BAAANQABCgQIBQAAAA==.',
Sp='Spammy:BAABNQAECn8ZAAMJAAkKwhRVSABFAgAJAAkKwhRVSABFAgAUAAEKlAgkqQEzAAAAAA==.Sparlyy:BAACNQAFFH8TAAMQAAYKrCHdBwCUAQAQAAQKYSTdBwCUAQAOAAIK0SSBIADcAAA1AAQKfzUAAxAACgp0JgQBAOMDABAACgp0JgQBAOMDAA4AAgqnFO/fAIoAAAAA.Spectrality:BAAANQAECgEIAgABNQAECgkJFwAjAOcFAA==.',
Ss='Sswordy:BAACNQAFFH8bAAICAAYK1xdQBgDsAQACAAYK1xdQBgDsAQA1AAQKf1gAAgIACgqOInUFALcDAAIACgqOInUFALcDAAAA.Sswordyvani:BAAANQAECgEIAQABNQAFFAYIGwACANcXAA==.',
St='Stephhunt:BAAANQAECgQIBwAAAA==.Stimulus:BAABNQAECn8oAAMOAAgKBwy2LwA/AQAOAAgKBwy2LwA/AQANAAUKnQK1GQCeAAAAAA==.Stinkynuuts:BAAANQADCggIHwAAAA==.Stompy:BAAANQAECgEIBAAAAA==.Stormcloak:BAAANQADCggIDgAAAA==.Stormfang:BAAANQAECgUICAAAAA==.',
Su='Sumbadvoodoo:BAAANQAECgMICAAAAA==.Sunkist:BAAANQAECgYIDwAAAA==.Sunwing:BAAANQADCgUJBQAAAA==.Sureina:BAAANQAECgYIEAAAAA==.Surlym:BAABNQAECn8xAAIhAAoK5CJsAgCZAwAhAAoK5CJsAgCZAwAAAA==.',
Sw='Swash:BAAANQADCggIFgAAAA==.Sweatshirtz:BAAANQAECgEIAQABNQAFFAQICAAZAEkNAA==.Sweetbrag:BAAANQAECgYIBwAAAA==.Switchglaive:BAABNQAECn82AAMVAAoKcw51EwBPAQAVAAoKaw51EwBPAQAnAAcK7QchGgAUAQAAAA==.',
Sy='Sylphie:BAAANQAECgIIAgAAAA==.Symphemon:BAABNQAECn8pAAMaAAkKpw5GKwDnAQAaAAkKFQ5GKwDnAQAVAAgK7wr/SgB3AQAAAA==.Syseloris:BAABNQAECn8iAAMnAAkKSRtMCABzAgAnAAkKSRtMCABzAgAVAAUK/g8hVwAuAQAAAA==.Sythion:BAACNQAFFH8IAAIZAAQKSQ3UAgB9AAAZAAQKSQ3UAgB9AAA1AAQKfyoAAxkACgqrGBULALcCABkACgqrGBULALcCABEABwqUEFslAJQBAAAA.',
['Sâ']='Sâlisbury:BAAANQADCgYIDAAAAA==.',
['Së']='Sëphy:BAAANQAECgEIAQAAAA==.',
Ta='Taediris:BAAANQADCgYIDgAAAA==.Taliiha:BAAANQAECgUICAAAAA==.Tanao:BAAANQAECgUIDgAAAA==.',
Te='Teenieween:BAAANQADCgIIAgAAAA==.Tengenuzui:BAAANQADCgEIAQAAAA==.Tenshi:BAAANQAECgcICAAAAA==.Terravesh:BAAANQADCgIIAgAAAA==.',
Th='Thewarfox:BAAANQAECgEIBAAAAA==.Thopegor:BAAANQAECgIIAwAAAA==.Thundergunt:BAAANQAECgcIBwABNQAECgoKMwAJAKIcAA==.',
Ti='Tianjin:BAAANQAECgIIAwAAAA==.Tickslap:BAAANQAECgQIBAAAAA==.Timid:BAAANQADCgIIAgAAAA==.Tintaglia:BAABNQAECn8jAAIUAAgKGhLrQQBCAQAUAAgKGhLrQQBCAQAAAA==.Tiqtaqto:BAAANQADCgIIAgAAAA==.Tivali:BAAANQADCgIIAgAAAA==.',
To='Toaster:BAABNQAECn8XAAMpAAcKbgeKAQAHAQApAAcKbgeKAQAHAQABAAIKQQD4wgE6AAAAAA==.Tober:BAAANQADCgcIFQAAAA==.Toni:BAAANQADCgcIDwAAAA==.Toodles:BAAANQADCgUIBQAAAA==.',
Tr='Tripscicle:BAAANQAECgEIAQAAAA==.Triskin:BAAANQAECgEIAwAAAA==.Trust:BAABNQAECn8tAAICAAkKAhZmDwD1AQACAAkKAhZmDwD1AQAAAA==.',
Tu='Tunawhale:BAAANQAECgMICQAAAA==.',
Tw='Twickenham:BAAANQADCgMIAwAAAA==.',
Ty='Tyloriavis:BAAANQAECgUIEAAAAA==.',
['Tä']='Tämpicö:BAAANQADCgUIBQAAAA==.',
Ul='Ulfberht:BAAANQADCggIDwAAAA==.Ulfin:BAAANQADCgUIBQABNQAECgcIGAAaAE0jAA==.Ultramind:BAAANQADCgUIBQAAAA==.',
Um='Umbras:BAAANQADCgIIAgAAAA==.',
Un='Unaware:BAAANQADCgYIBgABNQAECgYIDAAIAAAAAA==.Uncletouchie:BAAANQADCgIIAgAAAA==.Unáware:BAAANQADCgUIBQAAAA==.',
Va='Vaeliir:BAAANQADCggIEQAAAA==.Valára:BAAANQABCgYIBAAAAA==.',
Ve='Vesani:BAAANQADCgQIBAAAAA==.',
Vi='Vinfuriating:BAAANQAECgEIAQAAAA==.Vinsamo:BAAANQADCgcIBwAAAA==.Violentjudge:BAABNQAECn8pAAIUAAkKwxlOHgCpAQAUAAkKwxlOHgCpAQAAAA==.Violla:BAABNQAECn8cAAICAAgKlB8XFgDFAQACAAgKlB8XFgDFAQAAAA==.Virgocelest:BAABNQAECn8XAAMjAAkK5wWjGwCzAAAjAAkK5wWjGwCzAAAUAAIKagLXmQE7AAAAAA==.Viridion:BAAANQAECgUIDAAAAA==.Vivax:BAAANQAECgUICQAAAA==.',
Vo='Vonmack:BAAANQAECgEIAQAAAA==.Voorheez:BAAANQAECggICAAAAA==.Vorlos:BAAANQAECgcIDQABNQAECgoKJgADAKweAA==.',
Vr='Vreeg:BAABNQAECn8gAAIWAAcKBBAOaABxAQAWAAcKBBAOaABxAQAAAA==.',
Wh='Whiteflag:BAACNQAFFH8FAAIUAAQKnhcbDwBbAQAUAAQKnhcbDwBbAQA1AAQKfzkAAhQACgpBJqAGAMUDABQACgpBJqAGAMUDAAAA.Whoopington:BAAANQAECggIEgAAAA==.Whyamialive:BAACNQAFFH8aAAIDAAYKhSRmAgCDAgADAAYKhSRmAgCDAgA1AAQKfzwAAgMACgrQJpMAAPQDAAMACgrQJpMAAPQDAAAA.',
Wi='Wickedwolfin:BAAANQADCgYIBwAAAA==.Wiffles:BAAANQAECgUIBgABNQAFFAYIFgAbAIYgAA==.Willowes:BAEANQADCggICAABNQAFFAUIEgAOAHMVAA==.Willowest:BAEANQAECgQIBwABNQAFFAUIEgAOAHMVAA==.Willowing:BAEBNQAECn8dAAQEAAoKjRhOUQBhAgAEAAkK5RdOUQBhAgAFAAIKtBlcTwCRAAAlAAEKLgLxNAAnAAABNQAFFAUIEgAOAHMVAA==.Willowish:BAECNQAFFH8SAAIOAAUKcxWTEACOAQAOAAUKcxWTEACOAQA1AAQKfzsAAw4ACgqaI74HAIYDAA4ACgqaI74HAIYDABAAAQoGCNl9AC4AAAAA.Willowly:BAEANQAECgQIBgABNQAFFAUIEgAOAHMVAA==.Winterz:BAABNQAECn8dAAIBAAkK/BcxZgCxAgABAAkK/BcxZgCxAgAAAA==.Wiskii:BAABNQAECn8jAAIjAAgKphnqBwB+AQAjAAgKphnqBwB+AQAAAA==.Wizerds:BAAANQADCgQIBAABNQAECgkJFwAjAOcFAA==.',
Wo='Woopecushion:BAAANQADCgIIAgAAAA==.Worio:BAAANQADCgcIDwAAAA==.',
Wy='Wyrda:BAAANQAECgEIBQAAAA==.Wytenha:BAAANQAECggIEAABNQAFFAYIGwAgAAIRAA==.Wytnarthom:BAAANQAECgcICwABNQAFFAYIGwAgAAIRAA==.Wytohne:BAACNQAFFH8bAAMgAAYKAhHcBQC5AQAgAAYKAhHcBQC5AQAMAAEKfQJmCwA8AAA1AAQKfzwAAyAACgrnHdIMAAwDACAACgrnHdIMAAwDAAwAAQoAAIkwADkAAAAA.',
Xa='Xaree:BAABNQAECn8jAAIhAAgKRR74AgARAgAhAAgKRR74AgARAgAAAA==.Xariá:BAAANQADCgYIFAABNQAECgcIFgARAPIIAA==.',
Xc='Xcat:BAACNQAFFH8FAAIUAAQKagcUFQAKAQAUAAQKagcUFQAKAQA1AAQKfyIAAhQACgoJF1GGABsCABQACgoJF1GGABsCAAAA.',
Xd='Xdrake:BAAANQADCggICAAAAA==.',
Xy='Xydros:BAAANQABCggJDwAAAA==.Xymer:BAAANQAECgQIDAAAAA==.',
Yi='Yim:BAABNQAECn8lAAIUAAkKNh+zNwDwAgAUAAkKNh+zNwDwAgAAAA==.Yismypetdead:BAAANQAECgUICQABNQAECgUICwAIAAAAAA==.',
Yo='Yorshka:BAABNQAECn83AAIOAAoKfRiQOACGAgAOAAoKfRiQOACGAgAAAA==.',
Yw='Ywach:BAABNQAECn8ZAAMCAAkKpxHuQgAvAQACAAkKBRDuQgAvAQAGAAIKrhMLNQBDAAABNQAECgoKKwAPAFwdAA==.',
['Yú']='Yúno:BAABNQAECn8rAAIPAAoKXB3CGgAoAwAPAAoKXB3CGgAoAwAAAA==.',
Za='Zaffhavoc:BAAANQADCgYIBgABNQADCggIDAAIAAAAAA==.Zaffylizen:BAAANQADCgYIBgABNQADCggIDAAIAAAAAA==.Zako:BAAANQADCgMIAwABNQAECgQIDAAIAAAAAA==.Zalliea:BAAANQAECgcIDQAAAA==.Zaraki:BAAANQAECgMIAwAAAA==.',
Ze='Zeff:BAAANQAECgMICQAAAA==.',
Zi='Zieph:BAAANQAECgEIAQAAAA==.',
Zn='Znåp:BAAANQADCgQIBAAAAA==.',
Zo='Zompt:BAAANQAECgIICgAAAA==.Zorndk:BAAANQAECgYICwAAAA==.',
Zy='Zymar:BAAANQADCgMIAwABNQAECgQIDAAIAAAAAA==.',
['Ðë']='Ðëxx:BAAANQADCgQIBAAAAA==.',
['Õn']='Õni:BAACNQAFFH8NAAIDAAUK6Ax4EABPAQADAAUK6Ax4EABPAQA1AAQKfxQAAgMACQpzGT0tAGECAAMACQpzGT0tAGECAAAA.',
['Ön']='Öni:BAACNQAFFH8HAAIkAAMKWSDJAwAMAQAkAAMKWSDJAwAMAQA1AAQKfy0AAiQACQpcJCEDAHIDACQACQpcJCEDAHIDAAAA.',
['Øm']='Ømêgá:BAABNQAECn8hAAMBAAoKSQM8IQFUAQABAAoKSQM8IQFUAQApAAEKdAH8DwAYAAAAAA==.',
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
