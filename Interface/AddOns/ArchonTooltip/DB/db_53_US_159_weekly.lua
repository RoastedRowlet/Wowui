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

local lookup = {'Unknown-Unknown','Mage-Arcane','Druid-Guardian','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Holy','Druid-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','Priest-Holy','Priest-Discipline','Priest-Shadow','Druid-Balance','Paladin-Retribution','Warrior-Arms','Paladin-Protection','Shaman-Restoration','Warrior-Protection','Mage-Fire','DeathKnight-Blood','DeathKnight-Unholy','Evoker-Devastation','Hunter-Survival','Druid-Feral','Warlock-Demonology','Warlock-Destruction','Evoker-Preservation','Rogue-Outlaw','DemonHunter-Devourer','Monk-Windwalker','Monk-Mistweaver','Mage-Frost','Shaman-Enhancement','Monk-Brewmaster','DeathKnight-Frost','Warlock-Affliction','Warrior-Fury','Evoker-Augmentation',}
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abris:BAAANQAECgEIAQABNQAECgQICQABAAAAAA==.',
Ac='Acekith:BAAANQABCgMIAwABNQAECgQJBgABAAAAAA==.Acense:BAAANQAECgQJBgAAAA==.Acidhunter:BAAANQADCgcIBwAAAA==.Acidlock:BAAANQAECggIEgAAAA==.Acidpriest:BAAANQAECgYIDAAAAA==.',
Ad='Adacey:BAAANQAECgYIEwAAAA==.Adragon:BAAANQADCgQIBAABNQAECgUIDQABAAAAAA==.Adrenalized:BAAANQADCgMIBAAAAA==.',
Ae='Aesuga:BAAANQADCgYIBgAAAA==.',
Ak='Aktras:BAABNQAECn8WAAICAAYKqBEcnwCMAAACAAYKqBEcnwCMAAAAAA==.',
Al='Alaunu:BAABNQAECn8sAAIDAAoKWBEZGADvAQADAAoKWBEZGADvAQAAAA==.Aleas:BAAANQADCgQIBAAAAA==.Alexx:BAAANQAECgQICgAAAA==.Alkaid:BAAANQAECgYIDgAAAA==.Alunariel:BAAANQADCgYIDgAAAA==.',
An='Anari:BAAANQAECgQIBwABNQAECggIDQABAAAAAA==.Anarky:BAAANQAECggIEgAAAA==.Angelcorp:BAAANQAECgIIAgAAAA==.Annebonny:BAAANQAECgUIDAAAAA==.',
Ap='Apsalar:BAAANQADCgcJBwAAAA==.',
Ar='Archdemon:BAABNQAECn9aAAMEAAoKASXiAAAcAwAEAAoKsCTiAAAcAwAFAAkKVx+XAACqAgAAAA==.Arienys:BAAANQADCgYICwAAAA==.Ariis:BAAANQADCgUICQAAAA==.Arkh:BAAANQADCgMIAwAAAA==.Arkhanx:BAAANQADCgUJBQAAAA==.Arkhfu:BAAANQAECgIIAgAAAA==.Arleen:BAAANQADCgEIAQAAAA==.Arquen:BAABNQAECn8mAAIGAAkKeCIZAgAXAwAGAAkKeCIZAgAXAwAAAA==.Artemisia:BAAANQADCgYIFAAAAA==.',
As='Asevenx:BAAANQADCgUICQAAAA==.Ashamane:BAAANQAECgEIAQAAAA==.Asian:BAAANQADCgIIAgAAAA==.Asra:BAAANQAECgYICgAAAA==.Astrov:BAABNQAECn8ZAAIEAAgKyBGxNwDzAQAEAAgKyBGxNwDzAQAAAA==.',
At='Atulmags:BAAANQAECgYICQAAAA==.',
Au='Auani:BAABNQAECn81AAIHAAkK2CBEBwBOAwAHAAkK2CBEBwBOAwAAAA==.Aurelily:BAAANQADCgYJDAAAAA==.Ausia:BAAANQAECgQIBgAAAA==.',
Av='Avann:BAAANQADCgIIAgAAAA==.',
Az='Azazyl:BAAANQADCgQIDwAAAA==.Azzeus:BAAANQAECgMIBgABNQAECgoKJQAIAAAUAA==.Azzfists:BAAANQADCgQIBAABNQAECgoKJQAIAAAUAA==.Azzshot:BAABNQAECn8lAAMIAAoKABQPEQAAAQAJAAcKHhWGgAAMAgAIAAoK7QgPEQAAAQAAAA==.',
Ba='Babyrinsjr:BAABNQAECn8WAAIJAAYK0A+ebwDNAAAJAAYK0A+ebwDNAAAAAA==.Badista:BAAANQADCgIIAgAAAA==.Baile:BAAANQAECgIIAQABNQAECgUIBgABAAAAAA==.Balleont:BAABNQAECn8fAAIJAAkKCRSIWABqAgAJAAkKCRSIWABqAgAAAA==.Barrada:BAABNQAECn8eAAIJAAcKswXOxwByAQAJAAcKswXOxwByAQAAAA==.',
Be='Beefcakeßody:BAAANQADCgYIBgAAAA==.Berea:BAABNQAECn9LAAMKAAgK1AxICQCKAQAKAAgK1AxICQCKAQALAAUKsgM2OwDeAAAAAA==.',
Bl='Blankdemonic:BAAANQABCgYICAAAAA==.Blankwar:BAAANQADCgUIBQAAAA==.Bleedblue:BAABNQAECn8XAAILAAcKcwz0JQCXAQALAAcKcwz0JQCXAQAAAA==.Blitzed:BAAANQADCgIIAgAAAA==.Bloodhaven:BAAANQADCgEIAQAAAA==.',
Bo='Bo:BAABNQAECn81AAIJAAkKrx0RJQACAwAJAAkKrx0RJQACAwAAAA==.Bobbinrobin:BAAANQAECgQIBQABNQAECgkJHgAMAF8UAA==.Borahae:BAAANQAFFAEIAQAAAA==.Borden:BAAANQADCgQJBAAAAA==.',
Br='Bradent:BAAANQAECgcICAAAAA==.Breach:BAAANQAECgIIAwABNQAECgUIBgABAAAAAA==.Brunnhild:BAAANQAECgIIAgAAAA==.Bryxi:BAAANQAECgcICAAAAA==.Brünhilde:BAABNQAECn8nAAQNAAoKug9KWAAZAgANAAoKmA5KWAAZAgAOAAQKAxCeFQDRAAAPAAEKAABJhwAiAAAAAA==.',
Bs='Bstbll:BAACNQAFFH8XAAIHAAcKNhjIAwABAgAHAAcKNhjIAwABAgA1AAQKfywAAwcACgoFHUcSAL0CAAcACgoFHUcSAL0CABAAAQp/FT1KAEUAAAAA.',
Bu='Bubbleheals:BAABNQAECn8vAAMGAAoKIBABcQDFAQAGAAoKIBABcQDFAQARAAUK5gMlxABtAAABNQAFFAMIBQAMAKkHAA==.Bundtcake:BAAANQAECggIBwAAAA==.Burningfist:BAAANQAECgMIDAAAAA==.Buttsnacks:BAABNQAECn8mAAISAAoKUxWIWACCAgASAAoKUxWIWACCAgAAAA==.',
Ca='Caciocavallo:BAAANQAECggIAQABNQAECggIDQABAAAAAA==.Caletha:BAAANQADCgYICwAAAA==.Callistrah:BAAANQAECgUIBwAAAA==.Caltaa:BAABNQAECn81AAITAAkKsCHNBQBRAwATAAkKsCHNBQBRAwAAAA==.Canarah:BAAANQADCgQIBAABNQAECgkJGgAUAJIZAA==.Canverian:BAABNQAECn8WAAIDAAYKrRPjJQBnAQADAAYKrRPjJQBnAQAAAA==.Captsmash:BAABNQAECn8jAAIVAAkKPBvCCgCSAgAVAAkKPBvCCgCSAgAAAA==.Carmedic:BAAANQADCgIIAgAAAA==.Caudel:BAAANQABCgIIAgAAAA==.',
Cd='Cdub:BAAANQAECgYIDQAAAA==.',
Ch='Charcuterie:BAAANQAECgQIDQAAAA==.Chasseurfool:BAABNQAECn8UAAIJAAkKJAlZIQCSAQAJAAkKJAlZIQCSAQAAAA==.Chat:BAACNQAFFH8LAAIMAAQKmw2YBwDbAAAMAAQKmw2YBwDbAAA1AAQKfy4AAgwACgraGRsvAL8CAAwACgraGRsvAL8CAAAA.Chevre:BAABNQAECn8VAAIJAAUKphDS8gAcAQAJAAUKphDS8gAcAQAAAA==.Chezaro:BAABNQAECn8ZAAIRAAgKKAvk6wBEAQARAAgKKAvk6wBEAQAAAA==.Chickenwing:BAABNQAECn8gAAIWAAgKYCAsAQDcAgAWAAgKYCAsAQDcAgAAAA==.Christano:BAABNQAECn8aAAMRAAoKxhj5VwCPAgARAAoKWhj5VwCPAgATAAIK3SGoSgDBAAAAAA==.Christhecold:BAABNQAECn8gAAISAAgKHxrMbgBGAgASAAgKHxrMbgBGAgAAAA==.Chrollo:BAAANQAECgUIEQAAAA==.Chuchu:BAAANQADCgMIAwAAAA==.Chumba:BAAANQAECgYIDgAAAA==.',
Ci='Cinnamilk:BAAANQAECgMIAwABNQAECgkJOwAXADAcAA==.',
Cl='Clamslamm:BAEANQADCgUIBQABNQAECgcIHwAYAJIhAA==.Cloudcrack:BAECNQAFFH8PAAMUAAUKpw39EgAiAQAUAAUKpw39EgAiAQAMAAMKdAqDHADcAAA1AAQKfygAAwwACgrCG/ksAMkCAAwACQo2HPksAMkCABQACQqLHc46AHQCAAAA.',
Co='Cocotaso:BAAANQABCgIIAgAAAA==.Codemon:BAABNQAECn8fAAIZAAcKEBm4FQDwAQAZAAcKEBm4FQDwAQAAAA==.Cole:BAAANQADCgUIBQAAAA==.Cosmoline:BAABNQAECn8jAAIaAAoKmhxxAABxAgAaAAoKmhxxAABxAgABNQAECgcIFAAEAGIRAA==.Cotw:BAAANQAECgIIAgABNQAECgUIDQABAAAAAA==.Coverttops:BAAANQAECgYIEwAAAA==.',
Cp='Cptcharis:BAAANQADCgEIAQAAAA==.',
Cr='Critmyshorts:BAAANQAECgQIBAAAAA==.Critnespears:BAAANQADCgYIBgAAAA==.Crottin:BAAANQAECgEIAQAAAA==.',
Cu='Cubann:BAAANQAECgIIAgAAAA==.',
Cy='Cylrhea:BAAANQAECgUIDwAAAA==.Cynri:BAAANQADCgQIBQABNQAECgIIAgABAAAAAA==.Cyntrill:BAAANQAECgIIBAAAAA==.',
Da='Daboulder:BAAANQAECgEIAQAAAA==.Dadderz:BAAANQADCgYIGQAAAA==.Daedean:BAAANQAECgIIAgABNQAECgUIBgABAAAAAA==.Dagnome:BAAANQADCggICAAAAA==.Dahunter:BAAANQAECgIIAgAAAA==.Dajoel:BAAANQAECgIIAgAAAA==.Dalacia:BAAANQAECggIEwAAAA==.Daphera:BAAANQADCgYIBgAAAA==.Darkhollow:BAAANQADCggIFwAAAA==.Darkhunta:BAAANQADCgQIBAAAAA==.Darknature:BAABNQAECn8hAAIHAAgKhRjiIQAYAgAHAAgKhRjiIQAYAgAAAA==.Darkodin:BAABNQAECn8cAAIYAAcKXgn5cgBLAQAYAAcKXgn5cgBLAQAAAA==.Darkshamy:BAAANQAECgIIAwAAAA==.Darksknightt:BAAANQADCgEIAQAAAA==.Darrad:BAAANQAECgUIBwAAAA==.Datnagadrake:BAACNQAFFH8PAAISAAQKLRf2CADwAAASAAQKLRf2CADwAAA1AAQKf0EAAxIACgroIT4tAAgDABIACgqRID4tAAgDABUABgrdIAgQACgCAAAA.Dawinchy:BAABNQAECn8tAAMHAAoKCBfLGAB3AgAHAAoKCBfLGAB3AgAbAAYKxg5oGwBMAQAAAA==.',
De='Deadlypsycho:BAAANQAECgEIAQAAAA==.Deathavoider:BAAANQADCggIEAAAAA==.Deathawakens:BAAANQADCgEIAQAAAA==.Deathlyill:BAAANQAECgIJAgAAAA==.Decemberr:BAAANQAECgQICQAAAA==.Dekudin:BAABNQAECn8WAAITAAgKiBMpKQCTAQATAAgKiBMpKQCTAQAAAA==.Dellistia:BAAANQADCgYICwAAAA==.Dennywenny:BAAANQAECgUIDAAAAA==.Deric:BAAANQAECgEIAQAAAA==.Desdamona:BAABNQAECn8bAAIJAAYK2AODfAC0AAAJAAYK2AODfAC0AAAAAA==.Destrodemon:BAAANQADCggICAAAAA==.Destropally:BAABNQAECn8gAAIRAAgKIQ8XqwDJAQARAAgKIQ8XqwDJAQAAAA==.Devorick:BAABNQAECn8xAAMcAAkKER0LKwDYAgAcAAkKER0LKwDYAgAdAAIKIhBQVwB5AAAAAA==.',
Di='Diaval:BAAANQAECgQIBAAAAA==.Dih:BAAANQADCgYIBgABNQAECggIJAAdAAsYAA==.Dijarl:BAABNQAECn8fAAIJAAkK7Rm7BACJAgAJAAkK7Rm7BACJAgAAAA==.Dipndots:BAAANQAECgUIBgAAAA==.Dirtyboy:BAAANQADCgIIAgAAAA==.Discórdia:BAAANQAECgMIAwAAAA==.Diyiya:BAABNQAECn8YAAIJAAYKuQoEWgD6AAAJAAYKuQoEWgD6AAAAAA==.',
Do='Doggiestylin:BAAANQAECgMIAwAAAA==.Doorki:BAAANQADCggIDwAAAA==.Dottey:BAABNQAECn8VAAIdAAgKOg59FwCxAQAdAAgKOg59FwCxAQAAAA==.Doubleott:BAAANQAECgEIAQAAAA==.',
Dr='Drael:BAAANQAECgUIBwAAAA==.Draickin:BAABNQAECn8fAAIGAAgKQBbaJwBDAQAGAAgKQBbaJwBDAQAAAA==.Drekle:BAABNQAECn8ZAAMZAAYK5hZtBQA1AQAZAAYK5hZtBQA1AQAeAAQKXQ3mOADOAAABNQAECgkJLAAQADUUAA==.Drelian:BAAANQAECgIIBAAAAA==.Drevy:BAABNQAECn8VAAIfAAgK8BZLBgBwAgAfAAgK8BZLBgBwAgAAAA==.Drewdox:BAAANQADCgUIDAAAAA==.Drewsguy:BAAANQADCgYIGQAAAA==.Drexchan:BAAANQAECgEIAQAAAA==.Drizzlenuts:BAAANQAECggIDwAAAA==.Drrabbít:BAAANQADCgQIBAAAAA==.Drumira:BAAANQADCgMIAwABNQAECgkJHgAPAPEPAA==.Drumk:BAAANQADCgIIAgABNQAECgkJHgAPAPEPAA==.Drumma:BAAANQADCgcIBwAAAA==.Drummer:BAABNQAECn8eAAQPAAkK8Q/BNAB9AQAPAAcKnQzBNAB9AQAOAAUKrhSnDwAwAQANAAUKkgUuvADlAAAAAA==.Drumroleplz:BAAANQAECgQIBAABNQAECgkJHgAPAPEPAA==.',
Dw='Dw:BAABNQAECn8hAAMgAAkKKh2iFwCgAgAgAAkKKh2iFwCgAgAEAAMKqw+LdgCgAAABNQAFFAQIDAAJAPYVAA==.',
['Dà']='Dàddybear:BAAANQAECggIDgAAAA==.',
Ea='Earthsangel:BAAANQAECgQIBgAAAA==.',
Ec='Eclair:BAAANQAECgQICQAAAA==.',
Ed='Edralyia:BAAANQADCgYICwAAAA==.',
Eg='Egwene:BAAANQADCgQIBAAAAA==.',
Ei='Eilaurosa:BAABNQAECn8WAAIKAAgKlgk7RQCyAQAKAAgKlgk7RQCyAQAAAA==.Einnarr:BAAANQAECggIBQAAAA==.',
El='Eldrinne:BAABNQAECn8iAAIWAAgKEATwBQANAQAWAAgKEATwBQANAQAAAA==.Eleblast:BAAANQAECgIIAgAAAA==.Elizavoid:BAABNQAECn8gAAQNAAkKKxswQwBfAgANAAkKKxswQwBfAgAPAAUKUhDRGADBAAAOAAEKLhf7JABEAAAAAA==.Elizawrath:BAAANQADCgIIAgAAAA==.Elkuco:BAAANQAECgEIAQAAAA==.Elmindreyda:BAABNQAECn8WAAILAAYKQBC3JgCRAQALAAYKQBC3JgCRAQAAAA==.Elthiss:BAABNQAECn8vAAIDAAgKaBmxEABVAgADAAgKaBmxEABVAgAAAA==.',
En='Enfer:BAAANQAECgUICAABNQAFFAQICwAMAJsNAA==.Enyfing:BAAANQAECgQIBAAAAA==.',
Er='Erequois:BAAANQADCgEIAQABNQAECgcICAABAAAAAA==.Erianthe:BAABNQAECn8kAAIYAAgKdgascwBIAQAYAAgKdgascwBIAQAAAA==.Eriok:BAAANQABCggIDwAAAA==.Erophien:BAAANQADCgMIBAAAAA==.Erovynael:BAAANQAECgQICAAAAA==.Erovynthalin:BAAANQADCgYIEAAAAA==.Errorwing:BAAANQAECgMIAwAAAA==.',
Es='Eshera:BAAANQADCgIIAgAAAA==.Esherä:BAAANQAECgEIAQAAAA==.',
Ev='Eversong:BAAANQADCgYIDAAAAA==.',
Ex='Exmar:BAAANQAECgcIDAAAAA==.',
Fa='Faewhisker:BAABNQAECn8YAAMhAAkKyw25KQDQAQAhAAkKyw25KQDQAQAiAAQKBQYgOwCZAAAAAA==.Faithfool:BAABNQAECn8fAAIMAAkK3gmSkAB7AQAMAAkK3gmSkAB7AQAAAA==.Falshallnot:BAAANQADCggIDQABNQAECgkJLAAQADUUAA==.Fancyfeet:BAAANQAECgUIBQABNQAECgkJGgALADEUAA==.Fanduelfiend:BAAANQADCgMIAwAAAA==.Fangmonarch:BAAANQADCgUIBQAAAA==.Fashaladd:BAABNQAECn8sAAMQAAkKNRQtGQAYAQAQAAkKNRQtGQAYAQADAAEKAAA1WABIAAAAAA==.',
Fe='Fearios:BAABNQAECn87AAIXAAkKMBwZBQD+AQAXAAkKMBwZBQD+AQAAAA==.Felbeast:BAAANQAECgMIBQAAAA==.Felbound:BAAANQADCgUICQAAAA==.Femboy:BAAANQADCggICAAAAA==.Feorar:BAAANQADCgYJBgAAAA==.Feta:BAAANQAECgYICgABNQAECggIDQABAAAAAA==.',
Fi='Fieldtrip:BAAANQAECgQICgAAAA==.Fiendfyre:BAAANQADCgUIBQAAAA==.Fizzlenuts:BAAANQAECgcIEwABNQAECggIDwABAAAAAA==.',
Fl='Flightless:BAAANQADCggICgAAAA==.',
Fo='Foxi:BAAANQAECgQJBAAAAA==.',
Fr='Frosttbyte:BAABNQAECn83AAMCAAoKwRhRagCpAgACAAoKRBhRagCpAgAjAAEKjB4AOQBaAAAAAA==.Frostytute:BAAANQADCgIIAgAAAA==.',
Fu='Fullmetalass:BAABNQAECn8WAAIJAAkKZxYbjQDwAQAJAAkKZxYbjQDwAQAAAA==.',
Fy='Fyyre:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëiróx:BAAANQADCgIIAgAAAA==.',
Ga='Galistar:BAABNQAECn8VAAIMAAYKlA09TQCpAAAMAAYKlA09TQCpAAAAAA==.Garglelots:BAAANQADCgcIBwABNQAECgkJHgAMAF8UAA==.Garrotxa:BAAANQAECggICgABNQAECggIDQABAAAAAA==.',
Ge='Gevallen:BAAANQAECgYIBwAAAA==.',
Gh='Ghavinental:BAABNQAECn8kAAMMAAcKFBFqgQChAQAMAAcKAQ9qgQChAQAkAAcK7wwMHwBvAQAAAA==.',
Gi='Gil:BAABNQAECn8bAAIgAAkKfx+bFADCAgAgAAkKfx+bFADCAgAAAA==.Gilgamesh:BAAANQAECgUICgABNQAECgkJGwAgAH8fAA==.',
Gl='Glizzard:BAAANQAECgUIDAABNQAECggIGAARAP8eAA==.Glocket:BAAANQAECgMIBgAAAA==.Gloom:BAAANQAECgYIBgAAAA==.',
Gn='Gnolan:BAABNQAECn8dAAMLAAgK4hxOCwCHAQALAAgK4hxOCwCHAQAKAAUKHROXXgA8AQAAAA==.',
Go='Goatspace:BAABNQAECn8eAAQJAAgKOQjRxQB2AQAJAAgK4AfRxQB2AQAIAAUKDQPLXwCnAAAaAAEKAAFjFQAaAAAAAA==.Gomu:BAAANQADCgQIBAAAAA==.Gongagà:BAABNQAECn8kAAIgAAkK/g6jLQDUAQAgAAkK/g6jLQDUAQAAAA==.Goodnoodle:BAAANQAECgEIAQAAAA==.Goodwithabow:BAAANQAECgQICAAAAA==.Goremaster:BAAANQAECgQICgAAAA==.Gothbaddie:BAAANQAECgQIBAABNQAECggIDQABAAAAAA==.Goyum:BAAANQADCgEIAQAAAA==.',
Gr='Grankino:BAABNQAECn8oAAQQAAgK5QsuHwDyAAAbAAUK2xAAHwAiAQAQAAgKqwcuHwDyAAADAAEKiAQDbwAeAAAAAA==.Greedisgood:BAAANQADCgMIAwAAAA==.Greenthumbs:BAAANQADCgYIBgAAAA==.',
Gw='Gwaelphypha:BAABNQAECn8gAAIXAAcKghhaQwDuAQAXAAcKghhaQwDuAQABNQAECgcICAABAAAAAA==.',
Ha='Hakarii:BAAANQADCgEIAQAAAA==.Halder:BAAANQAECgEIAQAAAA==.Hapkido:BAABNQAECn8zAAMlAAoKiSKIAQCvAwAlAAkKGCSIAQCvAwAhAAEKoBdTMQBLAAAAAA==.Hawk:BAAANQAECgMIAwAAAA==.Hazrek:BAABNQAECn8VAAIkAAcKpgviGwClAQAkAAcKpgviGwClAQAAAA==.',
He='Heartattack:BAAANQAECggIAQAAAA==.Hecate:BAABNQAECn8UAAIRAAYKbwQIHgHtAAARAAYKbwQIHgHtAAAAAA==.Heidnik:BAAANQAECgUIBQAAAA==.Heihei:BAAANQAECgYIDAAAAA==.Heneedsumilk:BAAANQADCgYICgAAAA==.Heretic:BAAANQAECgIIAgAAAA==.',
Hi='Hillboy:BAAANQADCggIDgAAAA==.',
Ho='Holydes:BAAANQAECgQIBAABNQAECgYIGwAJANgDAA==.Holytrinityy:BAAANQADCgYIBgAAAA==.Holyzack:BAAANQAECgUIBQAAAA==.Hooch:BAAANQAECgYICgAAAA==.',
Hu='Humboldt:BAAANQAECggIBAABNQAECggIDQABAAAAAA==.Huunaron:BAAANQAECgcIDAABNQAECgoKHwANAAkfAA==.',
['Hé']='Héx:BAACNQAFFH8kAAMCAAcKBBbuDAARAgACAAYKPBnuDAARAgAjAAEKIgmgDgBTAAA1AAQKfxoAAgIACgrBFhqaAEwCAAIACgrBFhqaAEwCAAAA.',
Id='Idylwilde:BAAANQAECgYIEAAAAA==.',
Ie='Ienzo:BAAANQADCgQIBwAAAA==.',
Ih='Iheartoreos:BAABNQAECn8fAAIXAAcKsBKJUQCuAQAXAAcKsBKJUQCuAQAAAA==.',
Il='Ilovefuta:BAAANQAECgUIBQAAAA==.Iloveoreos:BAAANQADCgYIBgAAAA==.',
In='Instakill:BAAANQADCgQIBAAAAA==.Intent:BAAANQADCgMIAwAAAA==.Invictae:BAAANQAECgYIDgAAAA==.',
Io='Iobo:BAACNQAFFH8QAAIgAAcKBByYAwAdAgAgAAcKBByYAwAdAgA1AAQKfyQAAiAACgoCJMcGAGUDACAACgoCJMcGAGUDAAAA.',
Ir='Irk:BAAANQAECgYIDAAAAA==.Ironic:BAAANQADCgYIBgABNQAECgkJMgALAOsgAA==.',
Ja='Jagaerr:BAAANQABCgUICQAAAA==.Jarco:BAEANQAECgEIAQABNQAECgQIBAABAAAAAA==.Jasseca:BAAANQAECgMIBAABNQAECgcICAABAAAAAA==.',
Je='Jeandarc:BAAANQADCggICAAAAA==.Jezäbelle:BAAANQAECgIIAgAAAA==.',
Jo='Joesh:BAAANQABCgcIFQAAAA==.',
Ka='Kaadra:BAAANQAECgUIBQAAAA==.Kaelkin:BAABNQAECn8fAAMNAAkKhBMJUAA0AgANAAkKhBMJUAA0AgAOAAIK6gbDIgBRAAAAAA==.Kaelun:BAAANQADCgcICwABNQAECgkJHwANAIQTAA==.Kaelundrus:BAAANQAECgYIDAABNQAECgkJHwANAIQTAA==.Kainis:BAAANQAECgMICAAAAA==.Kamonorin:BAAANQABCgIIAgAAAA==.Kaotika:BAAANQAECgQIBAAAAA==.Karmus:BAAANQADCgUJCAAAAA==.',
Ke='Keadin:BAAANQADCgYICwAAAA==.Keilas:BAABNQAECn8cAAIbAAYKrBwHEgDfAQAbAAYKrBwHEgDfAQAAAA==.Kerron:BAAANQAECggIAQAAAA==.Keylala:BAAANQAECgQIDQAAAA==.',
Ki='Kickenmage:BAAANQADCgQIBAABNQAECgUIDwABAAAAAA==.Kickentail:BAAANQAECgUIDwAAAA==.Kiegh:BAAANQADCgcIBwAAAA==.Kior:BAAANQADCgYIBwAAAA==.Kirisham:BAAANQADCgMIAwAAAA==.Kiriwar:BAACNQAFFH8FAAISAAIKmxTALQCSAAASAAIKmxTALQCSAAA1AAQKfzMAAhIACgqpHikiADADABIACgqpHikiADADAAAA.Kirlia:BAABNQAECn8iAAIdAAcKxg6dFQDAAQAdAAcKxg6dFQDAAQAAAA==.',
Kl='Klymax:BAAANQAECgcIDAAAAA==.',
Ko='Koretha:BAAANQAECgQIBAABNQAFFAcIFwAHADYYAA==.Kowkowkachoo:BAAANQAECgQIBgAAAA==.',
Kr='Krellis:BAAANQAECgEIAQAAAA==.Krisp:BAABNQAECn8uAAMCAAkKCSK7GAByAwACAAkKCSK7GAByAwAjAAEKrSPWNABnAAAAAA==.Krobelus:BAABNQAECn8kAAIRAAgKZQZt3gBeAQARAAgKZQZt3gBeAQAAAA==.',
Ks='Ksharp:BAAANQADCgYIBgABNQAECgYICQABAAAAAA==.',
Kv='Kvedadormu:BAAANQADCgYIEQAAAA==.Kvedeitrormr:BAAANQAECgEIAQAAAA==.Kvedfróðleik:BAAANQABCgEIAQAAAA==.Kvedærilaz:BAAANQADCgEIAQAAAA==.',
Ky='Kylearean:BAAANQADCgMJAwAAAA==.Kyran:BAAANQAECgIIAgAAAA==.',
['Kè']='Kèrónos:BAAANQAECgUIBwAAAA==.',
['Kì']='Kìllstheweak:BAABNQAECn8jAAMmAAgKawonTACIAQAmAAgKawonTACIAQAXAAEKeQpjXQA8AAAAAA==.',
La='Laeythe:BAAANQAECgQIBAABNQAFFAIIBgANAI0mAA==.Lannah:BAAANQADCgYIDgAAAA==.Lash:BAAANQAECgUIBwAAAA==.',
Lc='Lclc:BAAANQAECgMIBQAAAA==.',
Le='Leafeon:BAABNQAFFH8IAAIHAAYK7wkBCAB1AQAHAAYK7wkBCAB1AQABNQAFFAcIEAAUADkaAA==.Lebrin:BAABNQAECn8VAAIUAAUKHBairQAVAQAUAAUKHBairQAVAQAAAA==.Legaia:BAABNQAECn8xAAISAAkKox80HgA/AwASAAkKox80HgA/AwAAAA==.Legendknewl:BAAANQAECgQIBAAAAA==.Legendoflink:BAAANQAECgQIBAAAAA==.Leliel:BAAANQADCggICAABNQAECgkJKAAGAGcbAA==.Lennyzamwam:BAAANQAECgQIBwAAAA==.Lesindre:BAAANQAECgIIAgABNQAECggIAQABAAAAAA==.Letaria:BAAANQADCgYIBgAAAA==.Lexapro:BAAANQAECgcIDAABNQABCgcIBwABAAAAAA==.',
Li='Lianissa:BAAANQADCggIGwAAAA==.Lillinna:BAAANQAECgQICwAAAA==.Lipidot:BAAANQAECgIIBAAAAA==.Lisea:BAAANQAECgIIAgAAAA==.Lithlina:BAAANQADCgYIBgAAAA==.',
Lo='Loamein:BAAANQAECgcIDQAAAA==.Lockrocks:BAAANQAECgcIEQAAAA==.Lockycharmz:BAAANQAECgIIAgABNQAECgkJOwAXADAcAA==.Lorcán:BAAANQADCgYICwAAAA==.Lorithan:BAAANQADCgIIAgAAAA==.Lormazlezrax:BAABNQAECn8aAAIUAAkKkhmhRQBLAgAUAAkKkhmhRQBLAgAAAA==.',
Lu='Lucernyx:BAAANQAECgIIAgABNQAECgEIAQABAAAAAA==.Luckystars:BAAANQADCgQIBAAAAA==.Luis:BAAANQADCgQIBAAAAA==.Luminara:BAAANQADCgYIBgAAAA==.Lunaera:BAAANQAECgcIDQAAAA==.Lune:BAAANQADCgcIBwABNQAECgUIBQABAAAAAA==.Lunella:BAAANQAECgIIAgABNQAECgUIBQABAAAAAA==.Lunellia:BAAANQAECgUIBQAAAA==.Lunethira:BAAANQADCgMIAwABNQAECgUIBQABAAAAAA==.Lunevra:BAAANQABCgcIBwABNQAECgUIBQABAAAAAA==.Lupi:BAAANQADCggIDwAAAA==.Lurkaburger:BAABNQAECn8ZAAISAAkKthawZwBZAgASAAkKthawZwBZAgAAAA==.',
Ly='Lythindra:BAAANQADCgQIBAAAAA==.',
Ma='Madhatter:BAAANQAECgQIDAAAAA==.Mageistmage:BAACNQAFFH8QAAICAAUKzhccHgCRAQACAAUKzhccHgCRAQA1AAQKfyAAAgIACgonIONDAPwCAAIACgonIONDAPwCAAAA.Magori:BAAANQADCgYIBgAAAA==.Majarl:BAAANQAECgYIEgAAAA==.Maki:BAAANQADCgEIAQABNQAECggIHAAGAMwdAA==.Malegar:BAAANQADCggIFgAAAA==.Malificent:BAAANQAECgQICAAAAA==.Mammajamma:BAABNQAECn8oAAIQAAkKYRZENgA5AgAQAAkKYRZENgA5AgAAAA==.Marsvolta:BAAANQAECgQICAAAAA==.Maruxus:BAABNQAECn80AAIKAAoKxBQaAwAdAgAKAAoKxBQaAwAdAgAAAA==.Marwen:BAAANQADCgYIEQAAAA==.Maulsin:BAAANQADCgUIBQAAAA==.Mavanthia:BAABNQAECn8mAAMSAAkK3BLnEgDCAQASAAkK3BLnEgDCAQAVAAEK0hIWQgA3AAAAAA==.',
Mc='Mcdeathy:BAAANQAECgUIDQAAAA==.Mclardragos:BAABNQAECn8kAAMeAAoKSCEaAQC+AgAeAAoKSCEaAQC+AgAZAAEKAAB2PgAvAAAAAA==.',
Me='Meadõw:BAAANQADCgUIBQAAAA==.Meatshield:BAAANQADCgcIDAAAAA==.Mecharoni:BAABNQAECn8yAAMLAAkK6yClDACqAgALAAgKzx6lDACqAgAKAAcKwSA2IgB0AgAAAA==.Meganaturexl:BAAANQABCgQIBAAAAA==.Mendication:BAAANQAECggIEAAAAA==.Meretrixee:BAAANQADCgIIAgABNQAECgkJMwANAKQVAA==.Meteion:BAAANQAECgQIDAABNQAECggIAQABAAAAAA==.',
Mi='Miacyn:BAAANQAECgIIBQAAAA==.Miladybast:BAABNQAECn8UAAIjAAYKWgcSHAAPAQAjAAYKWgcSHAAPAQAAAA==.Miniwheet:BAAANQAECgQIBAABNQAECgkJOwAXADAcAA==.Minke:BAAANQADCggIHwAAAA==.Mirra:BAABNQAECn8XAAIJAAgK1hGokgDjAQAJAAgK1hGokgDjAQAAAA==.Missdorei:BAAANQADCgUIBQAAAA==.',
Mo='Molai:BAAANQAECggICAAAAA==.Momsrymommy:BAAANQAECgUIDwAAAA==.Montavian:BAAANQADCgMIAwABNQAECgMIAgABAAAAAA==.Moodrian:BAAANQADCggICQABNQAECgkJLAAQADUUAA==.Moonaurora:BAAANQABCgMIAwAAAA==.Moontater:BAAANQADCgYIBgAAAA==.Mordekaiser:BAAANQADCggICAAAAA==.Morionso:BAABNQAECn8cAAITAAcKohpRDAA7AQATAAcKohpRDAA7AQAAAA==.Morphyrinsjr:BAAANQADCgcIBwABNQAECgYIFgAJANAPAA==.Mortarion:BAABNQAECn8zAAQYAAkKOxlvQgASAgAYAAcK5RtvQgASAgAmAAgK4xHWQwC0AQAXAAIKPAmESQBlAAAAAA==.Morwenspring:BAAANQADCgMIAwAAAA==.',
Ms='Mssrbubbles:BAAANQABCggIFQAAAA==.',
Mu='Murdiûs:BAABNQAECn8uAAMhAAoK7B0+EgDLAgAhAAoK7B0+EgDLAgAiAAUKiRYGCQBIAQAAAA==.',
My='Mythbruh:BAEBNQAECn8fAAMYAAcKkiGUSwDmAQAYAAcKhiCUSwDmAQAmAAcKfho2PADdAQAAAA==.',
Na='Nachokru:BAAANQABCgEIAgAAAA==.Nahla:BAAANQAECgIIAgAAAA==.Namrevlis:BAAANQADCgIIAgABNQAECgkJHgAPAPEPAA==.Narl:BAAANQAECgUICAAAAA==.Nayrditation:BAAANQAECgcIDQAAAA==.Nayrlock:BAAANQAECgcICwABNQAECgcIDQABAAAAAA==.',
Nc='Nctee:BAAANQAECgUICgAAAA==.',
Ne='Necropally:BAAANQADCgcIDQAAAA==.Nevermore:BAAANQAECgYIBgAAAA==.',
Ni='Nightsmoke:BAAANQAECgMJBQAAAA==.',
No='Nolabull:BAAANQADCgQIBAAAAA==.Nonattarius:BAABNQAECn8VAAIJAAYKZAjrgACrAAAJAAYKZAjrgACrAAAAAA==.Noraelara:BAAANQAECggIAQAAAA==.Norezfou:BAABNQAECn81AAMNAAkKyRa1PwBsAgANAAkKyRa1PwBsAgAPAAcKkhhvJAANAgAAAA==.Norran:BAAANQADCgMIAwAAAA==.Notalice:BAAANQADCgYIBgABNQAECgQICQABAAAAAA==.Nottartar:BAAANQAECgIJAgAAAA==.',
Nu='Nuker:BAAANQADCgYIEgAAAA==.Nurobi:BAABNQAECn8oAAIQAAoKQQ/2OAAoAgAQAAoKQQ/2OAAoAgAAAA==.',
Od='Odanobunaga:BAABNQAECn8qAAISAAoKLBd4VQCKAgASAAoKLBd4VQCKAgAAAA==.Odyn:BAAANQAECgUIDgAAAA==.',
Oe='Oerrael:BAAANQADCgcIEAAAAA==.',
Or='Oridk:BAABNQAECn8uAAIYAAkK6RvoAwALAgAYAAkK6RvoAwALAgABNQAFFAMIBwAJAJoOAA==.Oripal:BAAANQADCgcICAABNQAFFAMIBwAJAJoOAA==.Oríon:BAACNQAFFH8HAAMJAAMKmg4xGQDyAAAJAAMKmg4xGQDyAAAaAAEK7wudAgBOAAA1AAQKfyoABBoACgrdIckCAP0CABoACQpsHskCAP0CAAgABgrwFSs7AHgBAAkABgobG15NABgBAAAA.',
Ou='Outofrange:BAAANQAECggIAgAAAA==.',
Pa='Pangjang:BAAANQAECgUIBgAAAA==.Pankratease:BAAANQAECgcICQAAAA==.Pankratoes:BAAANQAECgIIAgABNQAECgcICQABAAAAAA==.Pankratos:BAAANQADCgUIBQABNQAECgcICQABAAAAAA==.Papahess:BAABNQAECn8hAAMQAAgKfBVCRQDbAQAQAAgKfBVCRQDbAQADAAMKyQzSSQCFAAAAAA==.Paradias:BAABNQAECn8aAAILAAkKMRSnEwBNAgALAAkKMRSnEwBNAgAAAA==.Pastor:BAAANQADCgQIBAAAAA==.Paxxul:BAAANQADCggICwAAAA==.',
Pe='Peppersham:BAAANQAECgUIDAAAAA==.Petespally:BAAANQAECgUIEgAAAA==.',
Pf='Pfftpfft:BAAANQAECgIIBAAAAA==.',
Ph='Pha:BAABNQAECn8dAAICAAoKIhcibwCfAgACAAoKIhcibwCfAgAAAA==.Phatdanny:BAAANQAECggIDAAAAA==.Phonycheese:BAABNQAECn8tAAMRAAoK5BRpeQA5AgARAAkKfRZpeQA5AgAGAAQK0giYXQCbAAAAAA==.Phur:BAAANQAECgMIAwAAAA==.',
Pi='Pixen:BAABNQAECn9JAAMcAAoK5RmOBAB/AgAcAAoK5RmOBAB/AgAnAAEKAAADMQAzAAAAAA==.',
Po='Pocalypse:BAAANQAECgQIBQAAAA==.Ponkeyfists:BAACNQAFFH8EAAIhAAIKOBvjDgCcAAAhAAIKOBvjDgCcAAA1AAQKfyUAAiEACgpzIf0IAEEDACEACgpzIf0IAEEDAAAA.Portstar:BAABNQAECn8kAAICAAoKeAh01gDaAQACAAoKeAh01gDaAQAAAA==.Powderhorn:BAAANQADCgUIBQAAAA==.',
Pr='Pravium:BAAANQADCgYIBgABNQAECgYIDgABAAAAAA==.Primed:BAABNQAECn80AAIbAAkKtRKADQBDAgAbAAkKtRKADQBDAgAAAA==.Prozac:BAAANQAECgEIAQABNQABCgcIBwABAAAAAA==.',
Pu='Pungla:BAABNQAECn8UAAIhAAoKlRXOGgBoAgAhAAoKlRXOGgBoAgAAAA==.',
Qu='Quelthanos:BAABNQAECn8qAAMRAAkKgRJHGwC1AQARAAkKgRJHGwC1AQAGAAEKfBDGGwE8AAAAAA==.',
Ra='Radical:BAAANQAECgMIBQAAAA==.Ralvick:BAAANQADCgEJAQAAAA==.Ramuun:BAAANQADCgIIAgAAAA==.Randomclown:BAAANQAECgEIAQAAAA==.Rascalfats:BAAANQAECgQIBwABNQAECgYICgABAAAAAA==.Rashii:BAABNQAECn8lAAINAAkKPRTDFgC7AQANAAkKPRTDFgC7AQAAAA==.Rawor:BAAANQAECgQIBAAAAA==.Raworrior:BAABNQAECn8aAAMSAAcKFg3/wAB7AQASAAcKFg3/wAB7AQAoAAEKOAhgNQAwAAAAAA==.',
Re='Reax:BAAANQADCgYIBgAAAA==.Rebaderchi:BAABNQAECn8hAAIgAAkKYhkAGwCAAgAgAAkKYhkAGwCAAgABNQADCgMIAwABAAAAAA==.Reignofpower:BAAANQADCgUIBQAAAA==.Reisswolf:BAAANQAECgMIAwAAAA==.Remoria:BAAANQAECgUIEAAAAA==.Renildan:BAAANQAECgYICgAAAA==.Renmazuo:BAAANQADCgMIAwAAAA==.Rezputan:BAAANQADCggICAAAAA==.',
Rh='Rhavin:BAAANQAECgUIBwAAAA==.Rhodon:BAAANQAECgQIBAAAAA==.Rhohorn:BAAANQADCgIIAgAAAA==.Rholand:BAABNQAECn8qAAISAAoKERlKVACOAgASAAoKERlKVACOAgAAAA==.',
Ri='Rivalt:BAAANQABCgMIAwAAAA==.Riverra:BAAANQADCgcICgAAAA==.Rizzoy:BAABNQAECn8eAAMoAAYKWBirFABVAQAoAAUKaRmrFABVAQASAAUKYxGA4QAmAQAAAA==.',
Ro='Rollo:BAAANQADCgIIBQAAAA==.Roottender:BAAANQADCgcICwAAAA==.Rovyr:BAABNQAECn8pAAMeAAkKIx4MFABtAgAeAAkKIx4MFABtAgApAAEKAAC4JwAlAAAAAA==.Rowinna:BAAANQADCgUIBQAAAA==.',
Ru='Ruckabis:BAABNQAECn8cAAIUAAkKeBXCRQBKAgAUAAkKeBXCRQBKAgAAAA==.',
Ry='Rybearkin:BAAANQADCgMIAwAAAA==.Rylos:BAAANQAECggIEgAAAA==.Ryshadow:BAAANQADCgYICwAAAA==.Ryumi:BAABNQAECn8YAAICAAcK4A81/QCTAQACAAcK4A81/QCTAQAAAA==.',
Sa='Saansula:BAAANQADCgEIAQAAAA==.Sacmaster:BAAANQADCggIDAABNQAECggIJAAdAAsYAA==.Saitamå:BAABNQAECn8kAAIiAAkKxheBFgAUAgAiAAkKxheBFgAUAgAAAA==.Samanaras:BAABNQAECn8fAAMVAAkKHxBiIgA3AQASAAgKrg6EowDEAQAVAAcKTRFiIgA3AQAAAA==.Sangwyn:BAAANQAECgQIBAABNQAECggIHAAGAMwdAA==.Santiago:BAAANQADCgMIAwAAAA==.Saratoga:BAAANQAECgQICwAAAA==.Sarkana:BAABNQAECn8oAAIGAAkKZxsMIwDgAgAGAAkKZxsMIwDgAgAAAA==.Saxonn:BAAANQAECgIIAgAAAA==.Saydis:BAAANQAECgUIDAAAAA==.',
Sc='Scatterbrain:BAAANQADCgcIDAAAAA==.',
Se='Sebattan:BAAANQADCgYIBwAAAA==.Seleinai:BAAANQADCgMIAwABNQAECgkJNQAOAH8dAA==.Seleine:BAABNQAECn81AAIOAAkKfx0lAgAJAwAOAAkKfx0lAgAJAwAAAA==.Seloric:BAABNQAECn8eAAIXAAcKFiHmKwBpAgAXAAcKFiHmKwBpAgAAAA==.Serendrin:BAABNQAECn8wAAIKAAoK4R7HAwAAAgAKAAoK4R7HAwAAAgAAAA==.Sevalandre:BAAANQAECgIIAgABNQAECgcICAABAAAAAA==.',
Sh='Shaaman:BAAANQADCgYIBgAAAA==.Shadowskyz:BAAANQAECgQIDgABNQAFFAMIBQAMAKkHAA==.Shaggimaggi:BAAANQAECgcIEwAAAA==.Shamanis:BAAANQADCgQIBAAAAA==.Shamcheese:BAAANQAECgQIBAABNQAECgoKLQARAOQUAA==.Shamina:BAACNQAFFH8FAAIMAAMKqQfhJQCVAAAMAAMKqQfhJQCVAAA1AAQKfzsAAgwACgp8G/0lAOwCAAwACgp8G/0lAOwCAAAA.Shammlet:BAAANQABCggIEwAAAA==.Shamorex:BAABNQAECn8hAAIMAAgK+xmaTQBAAgAMAAgK+xmaTQBAAgAAAA==.Shatter:BAABNQAECn8YAAIRAAgK/x5BXQCBAgARAAgK/x5BXQCBAgAAAA==.Shax:BAAANQADCggICAABNQAECgkJLgACAAkiAA==.Shlevin:BAAANQADCgcIDAAAAA==.',
Si='Sideshift:BAAANQAECgQIBAABNQAFFAMIBQAMAKkHAA==.Sinara:BAAANQAECgUICQAAAA==.',
Sk='Skaarr:BAAANQADCgQIBQAAAA==.Skibidiheals:BAAANQAECgEIAQAAAA==.Skybear:BAAANQABCgYICAAAAA==.',
Sl='Slash:BAAANQADCgYIBgAAAA==.Slayn:BAABNQAECn8rAAIjAAoK1xWjAQD1AQAjAAoK1xWjAQD1AQAAAA==.Sleinx:BAAANQADCgcIDAABNQAFFAQICwAMAJsNAA==.Slyrak:BAAANQAECgcICwAAAA==.',
Sm='Smitus:BAAANQABCgIIAgAAAA==.',
Sn='Snackie:BAABNQAECn8aAAIUAAcKmxvsIwBVAQAUAAcKmxvsIwBVAQAAAA==.Snooty:BAAANQAECggJAgAAAA==.Snotpig:BAAANQAECggIBwAAAA==.',
So='Sokar:BAAANQAECggICQAAAA==.Sokolovva:BAAANQADCgcIDAAAAA==.Souled:BAAANQADCgUIBQABNQAECgkJMgACAO4SAA==.Sourpunchkid:BAAANQAECgIIAgAAAA==.',
Sp='Spacedemon:BAABNQAECn8ZAAIgAAcKzRDuNQCUAQAgAAcKzRDuNQCUAQAAAA==.Sparroh:BAAANQADCgYIBgAAAA==.Spikedriver:BAABNQAECn8jAAIJAAoKBw56agA+AgAJAAoKBw56agA+AgAAAA==.Spiky:BAAANQADCgMIAwAAAA==.',
St='Stariane:BAABNQAECn8lAAIEAAoK5hpjGQDQAgAEAAoK5hpjGQDQAgAAAA==.Startaker:BAAANQADCggIDwAAAA==.Startaster:BAAANQADCgcIBwAAAA==.Starvoid:BAAANQAECgIIAgAAAA==.Stateofgrace:BAAANQAECgEIAQABNQAECgoKGwAHAHQkAA==.Steeldk:BAAANQAECgIJAgAAAA==.Stella:BAAANQAECgQICAAAAA==.Stonyfist:BAAANQADCgEIAQAAAA==.Stonyy:BAAANQAECgIIAgAAAA==.Stubhorn:BAAANQADCgUICAAAAA==.',
Su='Summers:BAAANQADCgYICwAAAA==.Sumonmyface:BAABNQAECn8kAAMdAAgKCxjPIgBbAQAdAAQKEh7PIgBbAQAcAAUKAxJZxQBAAQAAAA==.Superillbomb:BAAANQADCgYJCQAAAA==.Superold:BAAANQAECgYIDAAAAA==.',
Sw='Swamprot:BAABNQAECn8aAAIYAAcKah+lMwBcAgAYAAcKah+lMwBcAgAAAA==.',
Sy='Syletage:BAAANQADCgYICwAAAA==.Syral:BAAANQADCgYICwAAAA==.Syrel:BAAANQAECgEIBAAAAA==.',
Ta='Tailfordays:BAAANQADCgIIAgAAAA==.Tanky:BAAANQADCgIIAgAAAA==.Tantor:BAAANQADCgEIAQAAAA==.Taylorswift:BAABNQAECn8bAAMHAAoKdCS4CwB+AQAHAAcKtiO4CwB+AQAbAAQKZB3hGgBTAQAAAA==.',
Tc='Tchiratha:BAAANQAECgUICQABNQAECgkJKgARAIESAA==.',
Te='Tednougat:BAAANQADCgYIBgAAAA==.Telain:BAABNQAECn8gAAQGAAgKtAscngBKAQAGAAcKuQgcngBKAQARAAcKZwpd+gAqAQATAAIKSQz9XQBjAAAAAA==.Tensuki:BAAANQADCgQIBAAAAA==.Tesh:BAAANQADCgQIBgAAAA==.',
Th='Thaelynn:BAAANQADCgYIEAAAAA==.Thakilla:BAABNQAECn80AAIQAAkKphJnDgBpAQAQAAkKphJnDgBpAQAAAA==.Thordrik:BAAANQAECgIIAQAAAA==.Thorix:BAAANQAECgUICQAAAA==.Thornhub:BAAANQAECggICgABNQAFFAkJNQAdAHgiAA==.Thrust:BAAANQADCgIIAgABNQABCgcIBwABAAAAAA==.Thrustwood:BAAANQADCgMIAwAAAA==.',
Ti='Tiammanth:BAAANQAECgUICQAAAA==.Tigerbrew:BAAANQADCgUIBQAAAA==.Tigerburn:BAAANQADCgQIBAAAAA==.Tigerdawn:BAAANQADCgYIBgAAAA==.Tikya:BAAANQADCgYIBwAAAA==.Tilsit:BAAANQAECggIDQAAAA==.Timberreaper:BAAANQADCgcICAAAAA==.Tinyz:BAAANQAECgQIBwAAAA==.Tisisme:BAAANQADCgUIBQAAAA==.',
To='Tonythetiger:BAAANQAECgQIBAABNQAECgkJOwAXADAcAA==.',
Tr='Train:BAAANQADCgcIBwAAAA==.Trei:BAAANQADCgIIAgABNQAECgcIDQABAAAAAA==.Trexlot:BAAANQADCgIIAgAAAA==.Trinjal:BAAANQAECgEIAgAAAA==.',
Tu='Tubbylumpkin:BAAANQADCggIDAAAAA==.Tummi:BAAANQADCgcIEAAAAA==.Tumnus:BAAANQAECgEIAQAAAA==.',
Ty='Tyjan:BAAANQAECgIIAwAAAA==.',
['Tâ']='Tâfa:BAAANQADCggICAAAAA==.',
Uh='Uhtred:BAAANQADCgYIBwAAAA==.',
Ul='Ulti:BAABNQAECn8cAAIGAAgKzB0BNACUAgAGAAgKzB0BNACUAgAAAA==.',
Un='Unholyheart:BAAANQAECgIIAgAAAA==.',
Va='Varthios:BAAANQABCgQIBgAAAA==.Varyusha:BAAANQAECgEIAQAAAA==.',
Ve='Velantra:BAAANQAECggICQAAAA==.Venari:BAAANQAECgcIEwAAAA==.',
Vi='Vilelyn:BAAANQAECgUIDwABNQADCgEIAQABAAAAAA==.Viloria:BAABNQAECn8eAAIDAAcKgRaoHgCqAQADAAcKgRaoHgCqAQAAAA==.Vincent:BAAANQADCgQIBAAAAA==.Virrard:BAABNQAECn8fAAIJAAgKDRpOVAB0AgAJAAgKDRpOVAB0AgAAAA==.',
Vl='Vladimor:BAAANQAECgQICQAAAA==.Vladimyrr:BAAANQADCgUJCAAAAA==.',
Vo='Vozrezz:BAAANQAECgUIDgAAAA==.',
['Vë']='Vëda:BAABNQAECn8tAAINAAoKPiDWGwADAwANAAoKPiDWGwADAwAAAA==.',
Wa='Waffle:BAAANQAECgIIAwABNQAFFAUIBQAkAPUSAA==.Warage:BAAANQAECgEIAQAAAA==.Warske:BAAANQAECgMIAwABNQAECgUICAABAAAAAA==.',
Wh='Wheaties:BAAANQAECgYICgABNQAECgkJOwAXADAcAA==.Whizzie:BAABNQAECn8yAAICAAkK7hJ4nwBCAgACAAkK7hJ4nwBCAgAAAA==.Whizzlecrank:BAABNQAECn81AAICAAkKTBR8pQA2AgACAAkKTBR8pQA2AgAAAA==.',
Wi='Wicker:BAABNQAECn8oAAMQAAgK7hK9QwDlAQAQAAcK9xO9QwDlAQAHAAQKQRJhRgD+AAAAAA==.Willpharaoh:BAAANQADCgUICgAAAA==.Wiçker:BAAANQADCgIIAgABNQAECggIKAAQAO4SAA==.',
Wo='Wolford:BAAANQADCgYIBgAAAA==.',
Wr='Wras:BAABNQAECn8VAAIXAAYKJBT8VACgAQAXAAYKJBT8VACgAQAAAA==.Wrectt:BAAANQAECgUIDgABNQAECgYICQABAAAAAA==.',
['Wò']='Wòbbles:BAAANQAECgQIDQABNQAECgYICgABAAAAAA==.',
Xa='Xandrah:BAAANQADCgUJBQAAAA==.Xandrel:BAABNQAECn8lAAIRAAcKCBJcyQCJAQARAAcKCBJcyQCJAQAAAA==.',
Xe='Xed:BAABNQAECn8uAAIMAAcKshgdSwBKAgAMAAcKshgdSwBKAgAAAA==.Xenogears:BAABNQAECn8hAAIIAAkK1Rg9BAC7AQAIAAkK1Rg9BAC7AQAAAA==.',
Xi='Xiansai:BAABNQAECn8mAAIPAAoKWhHbIAAxAgAPAAoKWhHbIAAxAgAAAA==.',
Ya='Yappey:BAAANQAECgcIBwAAAA==.',
Yi='Yippee:BAAANQAECgYIDgAAAA==.',
Yo='Youthinasia:BAAANQAECgUIEAAAAA==.',
Ze='Zerega:BAAANQADCgcIHAABNQAECggISwAKANQMAA==.',
Zh='Zhi:BAAANQAECgMIBQAAAA==.Zhukov:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.',
Zo='Zombiehippo:BAABNQAECn8qAAICAAoKoRa0VwDRAgACAAoKoRa0VwDRAgAAAA==.',
['Áu']='Áutarch:BAAANQAECgYIEAAAAA==.',
['Ðe']='Ðemøn:BAAANQADCggIGQAAAA==.',
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
