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

local lookup = {'Warlock-Demonology','Unknown-Unknown','Warlock-Affliction','Rogue-Outlaw','DeathKnight-Blood','Mage-Arcane','Druid-Guardian','Warrior-Fury','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Monk-Brewmaster','Priest-Holy','Priest-Discipline','Priest-Shadow','Druid-Balance','Paladin-Retribution','Shaman-Elemental','Shaman-Enhancement','Warrior-Arms','Shaman-Restoration','Paladin-Protection','Warrior-Protection','Mage-Fire','DeathKnight-Unholy','Evoker-Devastation','Hunter-Survival','Warlock-Destruction','Druid-Feral','Evoker-Preservation','DemonHunter-Devourer','Evoker-Augmentation','Monk-Windwalker','Monk-Mistweaver','Mage-Frost','DeathKnight-Frost',}
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abris:BAAANQAECgEIAgABNQAECgkJGwABAIgTAA==.',
Ac='Acekith:BAAANQABCgMIAwABNQAECgQJBgACAAAAAA==.Acense:BAAANQAECgQJBgAAAA==.Acidhunter:BAAANQADCgcIBwAAAA==.Acidlock:BAABNQAECn8dAAIDAAgKdBNOCQDvAQADAAgKdBNOCQDvAQAAAA==.Acidpriest:BAAANQAECggIEwAAAA==.',
Ad='Adacey:BAABNQAECn8cAAIEAAkKxg3RBABGAQAEAAkKxg3RBABGAQAAAA==.Adragon:BAAANQADCgQIBAABNQAECgcIFgAFALwPAA==.Adrenalized:BAAANQADCgMIBAAAAA==.',
Ae='Aendrin:BAAANQAECgEIAQAAAA==.Aesuga:BAAANQADCgYIBgAAAA==.',
Af='Afteraction:BAAANQAECgQIBgAAAA==.',
Ak='Aktras:BAABNQAECn8eAAIGAAcKMhHwwQAjAQAGAAcKMhHwwQAjAQAAAA==.',
Al='Alaunu:BAABNQAECn87AAIHAAoKaBEZGADvAQAHAAoKaBEZGADvAQAAAA==.Aleas:BAAANQADCgQIBAAAAA==.Alexx:BAAANQAECgQICgAAAA==.Alkaid:BAAANQAECgYIDgAAAA==.Alric:BAAANQAECgUICwAAAA==.',
An='Anari:BAAANQAECgQIBwABNQAECggIDQACAAAAAA==.Anarky:BAABNQAECn8UAAIIAAgKgAG0MAA9AAAIAAgKgAG0MAA9AAAAAA==.Angelcorp:BAAANQAECgMIAwAAAA==.Annebonny:BAAANQAECgUIDAAAAA==.Anthrfinpete:BAAANQAECggIDAABNQAECgoKOgAJAPsjAA==.',
Ap='Apsalar:BAAANQADCgcJBwAAAA==.',
Ar='Archdemon:BAABNQAECn9bAAMKAAoKASV+AwC6AwAKAAoKsCR+AwC6AwALAAkKVx9EBQDeAgAAAA==.Arienys:BAAANQADCgYIEAAAAA==.Arigosa:BAAANQADCgcIDgAAAA==.Ariis:BAAANQADCgUICQAAAA==.Arkh:BAAANQADCgMIAwAAAA==.Arkhanx:BAAANQADCgUJBQAAAA==.Arkhfu:BAAANQAECgIIAgAAAA==.Arleen:BAAANQAECgUIBQAAAA==.Arquen:BAABNQAECn8wAAIJAAoK0yJADgBRAwAJAAoK0yJADgBRAwAAAA==.Artemisia:BAAANQADCggIHgAAAA==.',
As='Asevenx:BAAANQADCggIEQAAAA==.Ashamane:BAAANQAECgEIAgAAAA==.Asheril:BAAANQADCgcIEAAAAA==.Asian:BAAANQADCgIIAgAAAA==.Asra:BAAANQAECgYICgAAAA==.Astrov:BAABNQAECn8mAAIKAAoKUxOxNwDzAQAKAAoKUxOxNwDzAQAAAA==.',
At='Atulmags:BAAANQAECgYICQAAAA==.',
Au='Auani:BAABNQAECn9BAAIMAAoKASJEBwBOAwAMAAoKASJEBwBOAwAAAA==.Aurelily:BAAANQADCgYJDAAAAA==.Ausia:BAAANQAECgUIBwAAAA==.',
Av='Avann:BAAANQADCgIIAgAAAA==.',
Az='Azazyl:BAAANQAECgUIBgAAAA==.Azzeus:BAAANQAECgUICwABNQAECgoKLQANAO8YAA==.Azzfists:BAAANQADCgQIBAABNQAECgoKLQANAO8YAA==.Azzshot:BAABNQAECn8tAAMNAAoK7xiGgAAMAgANAAgKWRmGgAAMAgAOAAoKkgmDOgB8AQAAAA==.',
Ba='Babyrinsjr:BAABNQAECn8kAAINAAkKSw4jiwChAQANAAkKSw4jiwChAQAAAA==.Badista:BAAANQADCgIIAgAAAA==.Baile:BAAANQAECgIIAQABNQAECgQIAwACAAAAAA==.Balleont:BAABNQAECn8qAAINAAoKehOIWABqAgANAAoKehOIWABqAgAAAA==.Barrada:BAABNQAECn8rAAINAAgKNAeQuQA/AQANAAgKNAeQuQA/AQAAAA==.',
Be='Beefcakeßody:BAAANQADCgYIBgAAAA==.Berea:BAABNQAECn9rAAMPAAoKaBK0GQBXAQAQAAoKnBEAOgAUAgAPAAgK1Ay0GQBXAQAAAA==.',
Bi='Birgi:BAAANQAECggICAAAAA==.',
Bl='Blankdemonic:BAAANQABCgYICAAAAA==.Blankwar:BAAANQADCgUIBQAAAA==.Bleedblue:BAABNQAECn8hAAIQAAoKNQv0JQCXAQAQAAoKNQv0JQCXAQAAAA==.Blitzed:BAAANQADCgIIAgAAAA==.Bloodhaven:BAAANQADCgEIAQAAAA==.',
Bo='Bo:BAABNQAECn9BAAINAAoKBRwRJQACAwANAAoKBRwRJQACAwAAAA==.Bobbinrobin:BAABNQAECn8aAAIQAAgKShEoTwDGAQAQAAgKShEoTwDGAQAAAA==.Borahae:BAAANQAFFAEIAQABNQAFFAIIBQAJAKADAA==.Borden:BAAANQADCgQJBAAAAA==.',
Br='Bradent:BAABNQAECn8VAAINAAkKwwI1+QARAQANAAkKwwI1+QARAQAAAA==.Breach:BAAANQAECgQIAwAAAA==.Brunnhild:BAAANQAECgIIAgAAAA==.Bryxi:BAABNQAECn8aAAIRAAkKlh0rBQBWAgARAAkKlh0rBQBWAgAAAA==.Brünhilde:BAABNQAECn83AAQSAAoKbxVKWAAZAgASAAoKTRRKWAAZAgATAAQKAxCeFQDRAAAUAAEKAABJhwAiAAAAAA==.',
Bs='Bstbll:BAACNQAFFH8ZAAIMAAgK6hbIAwABAgAMAAgK6hbIAwABAgA1AAQKfzkAAwwACgreH0cSAL0CAAwACgreH0cSAL0CABUAAQp/FXuKADQAAAAA.',
Bu='Bubbleheals:BAABNQAECn86AAMJAAoKbBGiSwDlAQAJAAoKbBGiSwDlAQAWAAUK5gNRagFfAAABNQAFFAUICQAXAIoLAA==.Bundtcake:BAAANQAECggIBwAAAA==.Burningfist:BAABNQAECn8XAAIYAAQKvgwnJwDvAAAYAAQKvgwnJwDvAAAAAA==.Buttsnacks:BAABNQAECn8mAAIZAAoKUxWIWACCAgAZAAoKUxWIWACCAgAAAA==.',
Ca='Caciocavallo:BAAANQAECggIAQABNQAECggIDQACAAAAAA==.Calambar:BAAANQAECgUIDgAAAA==.Calar:BAABNQAECn8fAAIaAAoK5xgEHADYAgAaAAoK5xgEHADYAgAAAA==.Callistrah:BAAANQAECgUIBwAAAA==.Caltaa:BAABNQAECn9CAAIbAAoKIyTNBQBRAwAbAAoKIyTNBQBRAwAAAA==.Canarah:BAAANQADCgQIBAABNQAECgkJGgAaAJIZAA==.Canverian:BAABNQAECn8kAAIHAAkKARbpGgCuAQAHAAkKARbpGgCuAQAAAA==.Captsmash:BAABNQAECn87AAMcAAoKwBzzCABNAgAcAAoKwBzzCABNAgAZAAUK9QbJ2ADCAAAAAA==.Carmedic:BAAANQADCgIIAgAAAA==.',
Cd='Cdub:BAAANQAECgYIDQAAAA==.',
Ce='Cenarial:BAAANQADCgMIAwAAAA==.',
Ch='Charcuterie:BAAANQAECgQIDQAAAA==.Chasseurfool:BAABNQAECn8hAAINAAkKhwmWmACDAQANAAkKhwmWmACDAQAAAA==.Chat:BAACNQAFFH8QAAIXAAUKMw4aDQAMAQAXAAUKMw4aDQAMAQA1AAQKf0IAAhcACgqzHBsvAL8CABcACgqzHBsvAL8CAAAA.Chevre:BAABNQAECn8VAAINAAUKphDS8gAcAQANAAUKphDS8gAcAQAAAA==.Chezaro:BAABNQAECn8xAAIWAAkKHg+PgwDFAQAWAAkKHg+PgwDFAQAAAA==.Chickenwing:BAABNQAECn8wAAIdAAoKTiEsAQDcAgAdAAoKTiEsAQDcAgAAAA==.Christano:BAABNQAECn8qAAMWAAoK2x8kQQBmAgAWAAoKbx8kQQBmAgAbAAMKRyDCQQChAAAAAA==.Christhecold:BAABNQAECn8gAAIZAAgKHxrMbgBGAgAZAAgKHxrMbgBGAgAAAA==.Chrollo:BAAANQAECgUIEQAAAA==.Chuchu:BAAANQADCgMIAwAAAA==.Chumba:BAAANQAECgYIDgAAAA==.',
Ci='Cinnamilk:BAAANQAECggIBwABNQAECgoKWQAFAPcgAA==.',
Cl='Clamslamm:BAEANQADCgUIBQABNQAECgcIHwAeAJIhAA==.Cloudcrack:BAECNQAFFH8RAAMaAAcKbhD9EgAiAQAaAAcKbhD9EgAiAQAXAAMKdAqDHADcAAA1AAQKfzEAAxoACgp+I6cHAJ8DABoACQrDI6cHAJ8DABcACQo2HPksAMkCAAAA.',
Co='Cocoapuffs:BAAANQAECgQIBAABNQAECgoKWQAFAPcgAA==.Cocotaso:BAAANQABCgIIAgAAAA==.Codemon:BAABNQAECn8rAAIfAAkKDhc6DQB6AQAfAAkKDhc6DQB6AQAAAA==.Cole:BAAANQADCgUIBQAAAA==.Cosmoline:BAABNQAECn8jAAIgAAoKmhw+BACoAgAgAAoKmhw+BACoAgABNQAECgcIFAAKAGIRAA==.Cotw:BAAANQAECgIIAgABNQAECgcIFgAFALwPAA==.Coverttops:BAABNQAECn8ZAAQhAAgKBApcKQAwAQAhAAcKPQlcKQAwAQADAAQKJAqwGwCeAAABAAIKgQQQNQFPAAAAAA==.',
Cp='Cptcharis:BAAANQADCgEIAQAAAA==.',
Cr='Critmyshorts:BAAANQAECgYIDgAAAA==.Critnespears:BAAANQAECgMIAwABNQAECgcIDgACAAAAAA==.Crottin:BAAANQAECgQIAwAAAA==.Crystaltitan:BAAANQADCgQIBAAAAA==.',
Cu='Cubann:BAAANQAECgIIAgAAAA==.',
Cy='Cylrhea:BAAANQAECgUIDwAAAA==.Cynri:BAAANQADCgQIBQABNQAECgIIAgACAAAAAA==.Cyntrill:BAAANQAECgUICQAAAA==.',
Da='Daboulder:BAAANQAECgEIAQAAAA==.Dadderz:BAAANQADCggIJwAAAA==.Daedean:BAAANQAECgIIAgABNQAECgQIAwACAAAAAA==.Dagnome:BAAANQADCggICAAAAA==.Dahunter:BAAANQAECgIIAgAAAA==.Dajoel:BAAANQAECgIIAgAAAA==.Dalacia:BAABNQAECn8eAAIaAAoKkRVFXgD0AQAaAAoKkRVFXgD0AQAAAA==.Daphera:BAAANQADCgcIEgAAAA==.Darkforceray:BAAANQABCgQIBAAAAA==.Darkhollow:BAAANQAECgMIAwAAAA==.Darkhunta:BAAANQADCgQIBAAAAA==.Darknature:BAABNQAECn8jAAIMAAgKhRjiIQAYAgAMAAgKhRjiIQAYAgAAAA==.Darkodin:BAABNQAECn8lAAIeAAgK4wvnNQBGAQAeAAgK4wvnNQBGAQAAAA==.Darkshamy:BAAANQAECgQICQAAAA==.Darksknightt:BAAANQADCgEIAQAAAA==.Darkspriest:BAAANQAECgQIBwAAAA==.Darrad:BAAANQAECgUIBwAAAA==.Datnagadrake:BAACNQAFFH8RAAIZAAYKcRWgDQBzAQAZAAYKcRWgDQBzAQA1AAQKf1AAAxkACgoUI90fAMYCABkACgrfIt0fAMYCABwABgrdIAgQACgCAAAA.Dawinchy:BAABNQAECn8uAAMMAAoKaxnLGAB3AgAMAAoKaxnLGAB3AgAiAAYKxg5oGwBMAQAAAA==.',
De='Deadlypsycho:BAAANQAECgEIAQAAAA==.Deathavoider:BAAANQADCggIEAAAAA==.Deathawakens:BAAANQADCgEIAQAAAA==.Deathlyill:BAAANQAECgIJAgAAAA==.Decemberr:BAAANQAECgQICQAAAA==.Dekudin:BAABNQAECn8fAAIbAAoKuRLZHACKAQAbAAoKuRLZHACKAQAAAA==.Dellistia:BAAANQADCgcIEQAAAA==.Dennywenny:BAAANQAECgUIDAAAAA==.Deric:BAAANQAECgEIAQAAAA==.Desdamona:BAABNQAECn8iAAINAAcK6ANj7ADXAAANAAcK6ANj7ADXAAAAAA==.Destrodemon:BAAANQADCggICAAAAA==.Destropally:BAABNQAECn8hAAIWAAkK0w4XqwDJAQAWAAkK0w4XqwDJAQAAAA==.Devorick:BAABNQAECn9NAAMBAAoKBBwLKwDYAgABAAoKBBwLKwDYAgAhAAIKIhBQVwB5AAAAAA==.Deyeraa:BAAANQADCgUIBQAAAA==.',
Di='Diaval:BAAANQAECgQICAAAAA==.Dih:BAAANQADCgYIBgABNQAECgkJJwAhAHQWAA==.Dijarl:BAABNQAECn8zAAINAAkK8SHBEgACAwANAAkK8SHBEgACAwAAAA==.Dipndots:BAAANQAECgUICAAAAA==.Dirtyboy:BAAANQADCgIIAgAAAA==.Discórdia:BAAANQAECgMIAwAAAA==.Divineplea:BAAANQADCgcIBwAAAA==.Diyiya:BAABNQAECn8aAAINAAcK+wl2zgAVAQANAAcK+wl2zgAVAQAAAA==.',
Do='Doggiestylin:BAAANQAECgQICAAAAA==.Doorki:BAAANQAECggIDgAAAA==.Dottey:BAABNQAECn8dAAIhAAkKUBSmCgAaAQAhAAkKUBSmCgAaAQAAAA==.Doubleott:BAAANQAECgEIAQAAAA==.',
Dr='Drael:BAAANQAECgUIBwAAAA==.Draickin:BAABNQAECn8qAAIJAAoKqxOuZADqAQAJAAoKqxOuZADqAQAAAA==.Drekle:BAABNQAECn8tAAMjAAoKShCYFACuAQAjAAkK/g2YFACuAQAfAAgKQxVaDQB3AQABNQAECgkJMAAVADUUAA==.Drelian:BAAANQAECgUICQAAAA==.Drevy:BAABNQAECn8VAAIEAAgK8BZLBgBwAgAEAAgK8BZLBgBwAgAAAA==.Drewdox:BAAANQADCgYIDgAAAA==.Drewsguy:BAAANQADCggILQAAAA==.Drexchan:BAAANQAECgEIAQAAAA==.Drizzlenuts:BAABNQAECn8mAAMaAAoKNhtqGADzAgAaAAoKNhtqGADzAgAXAAEK/QHqVgEiAAAAAA==.Drrabbít:BAAANQADCgQIBAAAAA==.Drumira:BAAANQADCgMIAwABNQAECgkJHgAUAPEPAA==.Drumk:BAAANQADCgIIAgABNQAECgkJHgAUAPEPAA==.Drumma:BAAANQADCggIFQAAAA==.Drummer:BAABNQAECn8eAAQUAAkK8Q/BNAB9AQAUAAcKnQzBNAB9AQATAAUKrhSnDwAwAQASAAUKkgUuvADlAAAAAA==.Drumroleplz:BAAANQAECgQIBAABNQAECgkJHgAUAPEPAA==.',
Dw='Dw:BAACNQAFFH8FAAIkAAIKqw6wEACNAAAkAAIKqw6wEACNAAA1AAQKfzYAAyQACgpZHKIXAKACACQACgpZHKIXAKACAAoAAwqrD4t2AKAAAAE1AAUUBQgSAA0A8xsA.',
['Dà']='Dàddybear:BAABNQAECn8iAAINAAcKkAzovwAyAQANAAcKkAzovwAyAQAAAA==.',
Ea='Earthsangel:BAAANQAECgUIBwAAAA==.',
Ec='Echonox:BAABNQAECn8ZAAIWAAgKnhjjZgADAgAWAAgKnhjjZgADAgAAAA==.Eclair:BAAANQAECgQICQAAAA==.',
Ed='Edralyia:BAAANQADCgcIEQAAAA==.',
Eg='Egwene:BAAANQADCgQIBAAAAA==.',
Ei='Eilaurosa:BAABNQAECn8WAAIPAAgKlgk7RQCyAQAPAAgKlgk7RQCyAQAAAA==.Einnarr:BAABNQAECn8WAAIWAAoKVh00JwDEAgAWAAoKVh00JwDEAgAAAA==.',
El='Eldrinne:BAABNQAECn8iAAIdAAgKEATwBQANAQAdAAgKEATwBQANAQAAAA==.Eleblast:BAAANQAECgIIAgAAAA==.Elizavoid:BAABNQAECn8hAAQSAAkKKxswQwBfAgASAAkKKxswQwBfAgAUAAUKUhAiQQCqAAATAAEKLhf7JABEAAAAAA==.Elizawrath:BAAANQADCgIIAgAAAA==.Elkuco:BAAANQAECgEIAQAAAA==.Elmindreyda:BAABNQAECn81AAIQAAoKLw6jUADBAQAQAAoKLw6jUADBAQAAAA==.Elthiss:BAABNQAECn9MAAMHAAoKIBuBDABwAgAHAAoKIBuBDABwAgAiAAIKWhUyRABDAAAAAA==.',
En='Enfer:BAABNQAECn8ZAAIKAAgKcQtrNwBqAQAKAAgKcQtrNwBqAQABNQAFFAUIEAAXADMOAA==.Enyfing:BAAANQAECgUICQAAAA==.',
Er='Erequois:BAAANQADCgEIAQABNQAECgkJGgARAJYdAA==.Erianthe:BAABNQAECn8uAAIeAAoKyQescwBIAQAeAAoKyQescwBIAQAAAA==.Eriok:BAAANQABCggIDwAAAA==.Erophien:BAAANQADCgMIBAAAAA==.Eroryn:BAAANQAECgUIDAAAAA==.Erovynthalin:BAAANQADCgYIEAAAAA==.Errorwing:BAACNQAFFH8GAAIlAAMKQQmtCQC4AAAlAAMKQQmtCQC4AAA1AAQKfxYAAiUACgolFpQFACECACUACgolFpQFACECAAAA.',
Es='Eshera:BAAANQADCgIIAgAAAA==.Esherä:BAAANQAECgEIAQAAAA==.',
Ev='Eversong:BAAANQADCgYIDAAAAA==.',
Ex='Exmar:BAAANQAECggIDQAAAA==.',
Ey='Eyesopen:BAAANQAECgYIEQABNQAECgoKJAAMAK4lAA==.',
Fa='Faewhisker:BAABNQAECn8YAAMmAAkKyw25KQDQAQAmAAkKyw25KQDQAQAnAAQKBQYgOwCZAAAAAA==.Faithfool:BAABNQAECn8mAAIXAAoKbwqSkAB7AQAXAAoKbwqSkAB7AQAAAA==.Falshallnot:BAAANQAECgQIBAABNQAECgkJMAAVADUUAA==.Fancyfeet:BAAANQAECgUIBQABNQAECgkJGgAQADEUAA==.Fanduelfiend:BAAANQADCgMIAwAAAA==.Fangmonarch:BAAANQADCgUIBQAAAA==.Fashaladd:BAABNQAECn8wAAQVAAkKNRQPPwACAgAVAAkKNRQPPwACAgAHAAEKAAA1WABIAAAMAAEKXxPtcwA5AAAAAA==.',
Fe='Fearios:BAABNQAECn9ZAAIFAAoK9yCKCwDZAgAFAAoK9yCKCwDZAgAAAA==.Felbeast:BAAANQAECgMIBQAAAA==.Felbound:BAAANQADCgUICQAAAA==.Femboy:BAAANQADCggICAAAAA==.Feorar:BAAANQADCgYJBgAAAA==.Feta:BAAANQAECgYICgABNQAECggIDQACAAAAAA==.',
Fi='Fieldtrip:BAABNQAECn8nAAISAAcKUBmQSgAOAgASAAcKUBmQSgAOAgAAAA==.Fiendfyre:BAAANQADCgUIBQAAAA==.Fizzlenuts:BAABNQAECn8ZAAInAAgK6xUiFgAaAgAnAAgK6xUiFgAaAgABNQAECgoKJgAaADYbAA==.',
Fl='Flaspios:BAAANQADCgcIBwAAAA==.Flightless:BAAANQADCggICgAAAA==.',
Fo='Foxi:BAAANQAECgQJBAAAAA==.',
Fr='Fries:BAAANQADCggICAAAAA==.Frosttbyte:BAACNQAFFH8GAAIGAAIKaQzQPACCAAAGAAIKaQzQPACCAAA1AAQKf0IAAwYACgpHGlFqAKkCAAYACgrKGVFqAKkCACgAAQqMHgA5AFoAAAAA.Frostytute:BAAANQADCgIIAgAAAA==.',
Fu='Fullmetalass:BAABNQAECn8WAAINAAkKZxYbjQDwAQANAAkKZxYbjQDwAQAAAA==.',
Fy='Fyyre:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëiróx:BAAANQADCgIIAgAAAA==.',
Ga='Galistar:BAABNQAECn8mAAIXAAkKsAytaABNAQAXAAkKsAytaABNAQAAAA==.Garglelots:BAAANQAECgYICQABNQAECggIGgAQAEoRAA==.Garrotxa:BAAANQAECggICwABNQAECggIDQACAAAAAA==.',
Ge='Gevallen:BAAANQAECgcICgAAAA==.',
Gh='Ghavinental:BAABNQAECn8mAAMXAAkKsQ5qgQChAQAXAAcKAQ9qgQChAQAYAAkKlQsMHwBvAQAAAA==.',
Gi='Gil:BAABNQAECn8qAAIkAAoKah+bFADCAgAkAAoKah+bFADCAgAAAA==.Gilgamesh:BAAANQAECgUICgABNQAECgoKKgAkAGofAA==.',
Gl='Glizzard:BAAANQAECgUIDAABNQAECggIGAAWAP8eAA==.Glocket:BAAANQAECgIICQAAAA==.Gloom:BAAANQAECgYIBgAAAA==.',
Gn='Gnolan:BAABNQAECn81AAMQAAoK4RsvLwBBAgAQAAoK4RsvLwBBAgAPAAUKHROXXgA8AQAAAA==.',
Go='Goatspace:BAABNQAECn8tAAQgAAoKagszCgAxAQANAAkK2wfRxQB2AQAgAAYKvwszCgAxAQAOAAUKDQPLXwCnAAAAAA==.Gomu:BAAANQADCgQIBAAAAA==.Gongagà:BAABNQAECn8kAAIkAAkK/g6jLQDUAQAkAAkK/g6jLQDUAQAAAA==.Goodnoodle:BAAANQAECgEIAgAAAA==.Goodwithabow:BAAANQAECgQICAAAAA==.Gorben:BAAANQAECgIIAgAAAA==.Goremaster:BAAANQAECgQICgAAAA==.Gothbaddie:BAAANQAECgQIBAABNQAECggIDQACAAAAAA==.Goyum:BAAANQADCgEIAQAAAA==.',
Gr='Grankino:BAABNQAECn9BAAQiAAgKsA0AHwAiAQAiAAUK2xAAHwAiAQAVAAgK4Qm/QgAcAQAHAAIKNQdTYwBMAAAAAA==.Grapenuts:BAAANQAECgMIAwABNQAECgoKWQAFAPcgAA==.Greedisgood:BAAANQADCgMIAwAAAA==.Greenthumbs:BAAANQADCgYIBgAAAA==.',
Gw='Gwaelphypha:BAABNQAECn8gAAIFAAcKghhaQwDuAQAFAAcKghhaQwDuAQABNQAECgkJGgARAJYdAA==.',
Ha='Hakarii:BAAANQADCgEIAQAAAA==.Halder:BAAANQAECgEIAQAAAA==.Hapkido:BAABNQAECn9HAAMRAAoKgCSIAQCvAwARAAoKgCSIAQCvAwAmAAIK3RKpSQB+AAAAAA==.Hauwitzer:BAAANQADCgcIDAAAAA==.Hawk:BAAANQAECgMIAwAAAA==.Hazrek:BAABNQAECn8VAAIYAAcKpgviGwClAQAYAAcKpgviGwClAQAAAA==.',
He='Heartattack:BAAANQAECggIBQAAAA==.Hecate:BAABNQAECn8bAAMWAAcKHAUIHgHtAAAWAAcKsQQIHgHtAAAbAAIKHwYPbAApAAAAAA==.Heidnik:BAAANQAECgUIBQAAAA==.Heihei:BAABNQAECn8UAAMPAAoKCA0pKAD1AAAPAAoKbAwpKAD1AAAQAAIKrgoDvAB0AAAAAA==.Heneedsumilk:BAAANQADCgYICgAAAA==.Heretic:BAAANQAECgIIAgAAAA==.Hermanater:BAAANQADCggIDgABNQAECgcILgAbAKIaAA==.',
Hi='Hillboy:BAAANQADCggIDgAAAA==.',
Ho='Holydes:BAAANQAECgQIBAABNQAECgcIIgANAOgDAA==.Holyfrejoles:BAAANQAECggICAAAAA==.Holyground:BAAANQAECgEIAQABNQAECgoKJAAMAK4lAA==.Holytrinityy:BAAANQADCgYIBgAAAA==.Holyzack:BAAANQAECgUIBQAAAA==.Hooch:BAABNQAECn8UAAINAAcKYBO6rABZAQANAAcKYBO6rABZAQAAAA==.',
Hu='Humboldt:BAAANQAECggIBgABNQAECggIDQACAAAAAA==.Huunaron:BAABNQAECn8XAAMWAAoKbwz4uABgAQAWAAoKbwz4uABgAQAJAAMKxhKQAAF6AAAAAA==.',
['Hé']='Héx:BAACNQAFFH8pAAMGAAgKeRbuDAARAgAGAAYKlxvuDAARAgAoAAIKPgyFBwCfAAA1AAQKfy0AAygACgoNIJAJAA8CAAYACgp9GhqaAEwCACgABwoTIJAJAA8CAAAA.',
Id='Idylwilde:BAABNQAECn8uAAMVAAgKwQkuRAAUAQAVAAgKwQkuRAAUAQAHAAQKWwJNYwBMAAAAAA==.',
Ie='Ienzo:BAAANQADCgQIBwAAAA==.',
Ih='Iheartoreos:BAABNQAECn8hAAIFAAkKUxGJUQCuAQAFAAkKUxGJUQCuAQAAAA==.',
Il='Ilovefuta:BAAANQAECgUICQAAAA==.Iloveoreos:BAAANQADCgYIBgAAAA==.',
In='Instakill:BAAANQADCgQIBAAAAA==.Intent:BAAANQADCgMIAwAAAA==.Invictae:BAABNQAECn8jAAQSAAoKWhatKwCaAgASAAoKWhatKwCaAgAUAAMKRAkLXACVAAATAAEK1ALaMAAiAAAAAA==.',
Io='Iobo:BAACNQAFFH8SAAMkAAgKlRiYAwAdAgAkAAcKBByYAwAdAgAKAAIKbAeKGgBOAAA1AAQKfygAAyQACgoCJMcGAGUDACQACgoCJMcGAGUDAAoAAgpEHipeAKsAAAAA.',
Ir='Irk:BAABNQAECn8kAAIQAAgKmhahTwDFAQAQAAgKmhahTwDFAQAAAA==.Ironic:BAAANQADCgYIBgABNQAECgoKRQAQAK4hAA==.',
Ja='Jagaerr:BAAANQABCgUICQAAAA==.Jarco:BAEANQAECgEIAQABNQAFFAcIDgAEANQWAA==.Jargan:BAAANQAECgEIAQABNQAECgoKLQAgAGoLAA==.Jasseca:BAAANQAECgMIBAABNQAECgkJGgARAJYdAA==.',
Je='Jeandarc:BAAANQADCggICAAAAA==.Jezäbelle:BAAANQAECgYIDQAAAA==.',
Jo='Joesh:BAAANQABCgcIFgAAAA==.',
Jt='Jtetue:BAAANQAECgUIDAAAAA==.',
Ka='Kaadra:BAAANQAECgUIBQAAAA==.Kaanon:BAAANQAECgYICgAAAA==.Kaelkin:BAABNQAECn8tAAQSAAoKQxQJUAA0AgASAAoKQxQJUAA0AgAUAAUKQw1nQgClAAATAAIK6gbDIgBRAAAAAA==.Kaellar:BAAANQADCgMIAwABNQAECgoKLQASAEMUAA==.Kaelun:BAAANQAECgIIBAABNQAECgoKLQASAEMUAA==.Kaelundrus:BAABNQAECn8YAAMXAAoKBRGMfgCoAQAXAAYKShmMfgCoAQAaAAgKAhThXwCZAQABNQAECgoKLQASAEMUAA==.Kainis:BAABNQAECn8YAAIOAAUKXgOYQgCUAAAOAAUKXgOYQgCUAAAAAA==.Kamonorin:BAAANQABCgIIAgAAAA==.Kaotika:BAAANQAECgcIDQAAAA==.Karmus:BAAANQADCgUJCAAAAA==.',
Ke='Keadin:BAAANQADCgcIEQAAAA==.Keilas:BAABNQAECn8rAAIiAAkK3hq6CgAvAgAiAAkK3hq6CgAvAgAAAA==.Kerron:BAAANQAECggIAQAAAA==.Keylala:BAABNQAECn8eAAIhAAgKAAxSCwAMAQAhAAgKAAxSCwAMAQAAAA==.',
Ki='Kickenmage:BAAANQADCgQIBAABNQAECgYIIQANAKYGAA==.Kickentail:BAABNQAECn8hAAINAAYKpgY13wBCAQANAAYKpgY13wBCAQAAAA==.Kiegh:BAAANQADCgcIBwAAAA==.Kior:BAAANQADCgYIBwAAAA==.Kirisham:BAAANQADCgMIAwAAAA==.Kiriwar:BAACNQAFFH8HAAIZAAQKCRfALQCSAAAZAAQKCRfALQCSAAA1AAQKfzsAAhkACgp2IikiADADABkACgp2IikiADADAAAA.Kirlia:BAABNQAECn81AAIhAAkKmw2dFQDAAQAhAAkKmw2dFQDAAQAAAA==.',
Kl='Klymax:BAAANQAECgcIDAAAAA==.',
Ko='Koretha:BAAANQAECgQIEgABNQAFFAgIGQAMAOoWAA==.Kowkowkachoo:BAAANQAECgYIEQAAAA==.',
Kr='Krellis:BAAANQAECgEIAQAAAA==.Krisp:BAABNQAECn8vAAMGAAkKtCK7GAByAwAGAAkKtCK7GAByAwAoAAEKrSPWNABnAAAAAA==.Krispies:BAAANQAECgYIBgABNQAECgoKWQAFAPcgAA==.Krobelus:BAABNQAECn8uAAIWAAoK1Adt3gBeAQAWAAoK1Adt3gBeAQAAAA==.Kruggs:BAAANQADCgYIBgAAAA==.',
Ks='Ksharp:BAAANQADCgYIBgABNQAECgcIDgACAAAAAA==.',
Kv='Kvedadormu:BAAANQADCgYIEQAAAA==.Kvedeitrormr:BAAANQAECgEIAQAAAA==.Kvedfróðleik:BAAANQABCgEIAQAAAA==.Kvedærilaz:BAAANQADCgEIAQAAAA==.',
Ky='Kylearean:BAAANQAECgMIBwAAAA==.Kyran:BAAANQAECgIIAgAAAA==.',
['Kè']='Kèrónos:BAAANQAECgUIBwAAAA==.',
['Kì']='Kìllstheweak:BAABNQAECn8vAAMpAAoK4wonTACIAQApAAoK4wonTACIAQAFAAIKTAjgiQBYAAAAAA==.',
La='Ladrone:BAAANQABCgEIAQAAAA==.Laeythe:BAEANQAECgQIBAABNQAFFAIIBgASAI0mAA==.Lannah:BAAANQADCgYIDgAAAA==.Lash:BAAANQAECgUIBwAAAA==.',
Lc='Lclc:BAAANQAECgYICgAAAA==.',
Le='Leafeon:BAACNQAFFH8JAAIMAAcKlQsBCAB1AQAMAAcKlQsBCAB1AQA1AAQKfyIAAgwACgpaJFcEAIADAAwACgpaJFcEAIADAAE1AAUUBwgQABoAORoA.Lebrin:BAABNQAECn8WAAIaAAUKZhqirQAVAQAaAAUKZhqirQAVAQAAAA==.Legaia:BAABNQAECn81AAIZAAoKoR40HgA/AwAZAAoKoR40HgA/AwAAAA==.Legendknewl:BAAANQAECgQIBAAAAA==.Legendoflink:BAAANQAECgUIBgAAAA==.Lelana:BAAANQADCgcIBwAAAA==.Leliel:BAAANQADCggICAABNQAECgoKMgAJAM0aAA==.Lennyzamwam:BAAANQAECgQIBwAAAA==.Lesindre:BAAANQAECgYIDAABNQAECggIAgACAAAAAA==.Letaria:BAAANQADCgYIBgAAAA==.Lexapro:BAAANQAECgcIDQABNQABCgcIBwACAAAAAA==.',
Li='Lianissa:BAAANQADCggIGwAAAA==.Lillinna:BAAANQAECgcIEQAAAA==.Lipidot:BAAANQAECgIIBAAAAA==.Lisea:BAAANQAECgIIAgAAAA==.Lithlina:BAAANQADCgYIBgAAAA==.',
Lo='Loamein:BAAANQAECgcIDQAAAA==.Lockrocks:BAABNQAECn8aAAIBAAoKkhAJXwC4AQABAAoKkhAJXwC4AQAAAA==.Lockycharmz:BAAANQAECggICgABNQAECgoKWQAFAPcgAA==.Lorcán:BAAANQADCgcIEQAAAA==.Lorithan:BAAANQADCgIIAgAAAA==.Lormazlezrax:BAABNQAECn8aAAIaAAkKkhmhRQBLAgAaAAkKkhmhRQBLAgAAAA==.',
Lu='Lucernyx:BAAANQAECgIIAgABNQAECgEIAgACAAAAAA==.Luckystars:BAAANQADCgQIBAAAAA==.Luis:BAAANQADCgQIBAAAAA==.Luminara:BAAANQADCgYIBgAAAA==.Lunaera:BAABNQAECn8aAAINAAkKwxCffADCAQANAAkKwxCffADCAQAAAA==.Lunajoy:BAAANQADCgEIAQAAAA==.Lune:BAAANQADCgcIBwABNQAECggIDAACAAAAAA==.Lunella:BAAANQAECgIIAgABNQAECggIDAACAAAAAA==.Lunellia:BAAANQAECggIDAAAAA==.Lunethira:BAAANQAECgMIBQABNQAECggIDAACAAAAAA==.Lunevra:BAAANQABCgcIBwABNQAECggIDAACAAAAAA==.Lupi:BAAANQADCggIDwAAAA==.Lurkaburger:BAABNQAECn8ZAAIZAAkKthawZwBZAgAZAAkKthawZwBZAgAAAA==.',
Ly='Lythindra:BAAANQADCgQIBAAAAA==.',
Ma='Maddog:BAAANQAECgMIAwAAAA==.Madhatter:BAABNQAECn8bAAMpAAcK5gWccwDUAAApAAcKzQWccwDUAAAFAAEK+gRCsQAgAAAAAA==.Mageistmage:BAACNQAFFH8SAAMGAAcKUBUcHgCRAQAGAAYKXhUcHgCRAQAoAAEKGRULEABTAAA1AAQKfzMAAwYACgrHI3spAJkCAAYACgrHI3spAJkCACgAAQqZHDw2AFMAAAAA.Magori:BAAANQADCgYIBgAAAA==.Majarl:BAAANQAECgYIEgAAAA==.Maki:BAAANQADCgEIAQABNQAECgkJLAAJAM4eAA==.Malegar:BAAANQADCggIFgAAAA==.Malificent:BAAANQAECgQICAAAAA==.Mammajamma:BAABNQAECn8oAAIVAAkKYRZENgA5AgAVAAkKYRZENgA5AgAAAA==.Marsvolta:BAAANQAECgQICAAAAA==.Maruxus:BAABNQAECn9KAAIPAAoKTBf1DAD9AQAPAAoKTBf1DAD9AQAAAA==.Marwen:BAAANQADCggIJQAAAA==.Masque:BAAANQAECggIBwAAAA==.Maulsin:BAAANQADCgUIBQAAAA==.Mavanthia:BAABNQAECn8uAAMZAAkK/hLTdgCgAQAZAAkK/hLTdgCgAQAcAAEK0hIWQgA3AAAAAA==.Mayyonnaise:BAAANQAECgIIAQAAAA==.',
Mc='Mcdeathy:BAABNQAECn8WAAIFAAcKvA8NVADtAAAFAAcKvA8NVADtAAAAAA==.Mclardragos:BAABNQAECn8uAAMjAAoK0CI4BQBYAwAjAAoK0CI4BQBYAwAfAAEKAAB2PgAvAAAAAA==.',
Me='Meadõw:BAAANQADCgUIBQAAAA==.Meatshield:BAAANQADCgcIDAAAAA==.Mecharoni:BAABNQAECn9FAAMQAAoKriGlDACqAgAQAAkK/R+lDACqAgAPAAcKwSA2IgB0AgAAAA==.Medreaux:BAAANQAECggIAgAAAA==.Meganaturexl:BAAANQABCgQIBAAAAA==.Meghatron:BAAANQAECgEIAQAAAA==.Mendication:BAAANQAECgcIEQAAAA==.Meretrixee:BAAANQADCgIIAgABNQAECgoKUAASAH8YAA==.Meteion:BAABNQAECn8bAAMBAAcKNhqudAB+AQABAAcKNhqudAB+AQAhAAEKAACYeAA1AAABNQAECggIAgACAAAAAA==.',
Mi='Miacyn:BAAANQAECggIDwAAAA==.Midnitte:BAAANQAECgEIAQAAAA==.Miladybast:BAABNQAECn8gAAIoAAcKpwYSHAAPAQAoAAcKpwYSHAAPAQAAAA==.Miniwheet:BAAANQAECgYICAABNQAECgoKWQAFAPcgAA==.Minke:BAAANQADCggIHwAAAA==.Mirra:BAABNQAECn8gAAINAAoKtRCPdADWAQANAAoKtRCPdADWAQAAAA==.Mirrielle:BAAANQABCgcIBwAAAA==.Missdorei:BAAANQADCgUIBQAAAA==.',
Mo='Molai:BAAANQAECggICAAAAA==.Mommades:BAAANQADCgYIBgABNQAECgcIIgANAOgDAA==.Momsrymommy:BAABNQAECn8bAAIWAAYKtxJrwgCXAQAWAAYKtxJrwgCXAQAAAA==.Montavian:BAAANQAECgMIAwABNQAECgIIAgACAAAAAA==.Moodrian:BAAANQADCggICQABNQAECgkJMAAVADUUAA==.Moonaurora:BAAANQABCgMIAwAAAA==.Moontater:BAAANQADCgYIBgAAAA==.Mordekaiser:BAAANQADCggICAAAAA==.Morgul:BAAANQAECgYIEwAAAA==.Morionso:BAABNQAECn8uAAIbAAcKoholIQDbAQAbAAcKoholIQDbAQAAAA==.Morphyrinsjr:BAAANQAECgcICQABNQAECgkJJAANAEsOAA==.Mortarion:BAABNQAECn8/AAQeAAoKBBlvQgASAgAeAAcK5RtvQgASAgApAAkKZxTWQwC0AQAFAAIKPAn5hwBbAAAAAA==.Morwenspring:BAAANQADCgMIAwAAAA==.',
Ms='Mssrbubbles:BAAANQABCggIFQAAAA==.',
Mu='Murdiûs:BAABNQAECn9GAAMmAAoK7B0+EgDLAgAmAAoK7B0+EgDLAgAnAAoKdxhlCgCiAgAAAA==.',
My='Mythbruh:BAEBNQAECn8fAAMeAAcKkiGUSwDmAQAeAAcKhiCUSwDmAQApAAcKfho2PADdAQAAAA==.',
Na='Nachokru:BAAANQABCgEIAgAAAA==.Nahla:BAAANQAECgIIAgAAAA==.Namrevlis:BAAANQADCgIIAgABNQAECgkJHgAUAPEPAA==.Narl:BAAANQAECgUICAAAAA==.Nayrditation:BAAANQAECgcIDQAAAA==.Nayrlock:BAAANQAECgcICwABNQAECgcIDQACAAAAAA==.',
Nc='Nctee:BAAANQAECgYIDAAAAA==.',
Ne='Nearn:BAAANQAECgIIAgAAAA==.Necropally:BAAANQADCgcIDQAAAA==.Nevermore:BAAANQAECgYIBgAAAA==.',
Ni='Nightsmoke:BAAANQAECgMJBQAAAA==.Nilious:BAAANQADCgIIAgAAAA==.',
No='Nolabull:BAAANQADCgQIBAAAAA==.Nonattarius:BAABNQAECn8dAAINAAkK/gfKvgA0AQANAAkK/gfKvgA0AQAAAA==.Noraelara:BAAANQAECggIAQABNQAECggIAgACAAAAAA==.Norezfou:BAABNQAECn9BAAMSAAoKGRm1PwBsAgASAAoKGRm1PwBsAgAUAAgK6RZvJAANAgAAAA==.Norran:BAAANQADCgMIAwAAAA==.Notalice:BAAANQAECgIIAgABNQAECgkJGwABAIgTAA==.Nottartar:BAAANQAECgIJAgAAAA==.',
Nu='Nuker:BAAANQADCgYIEgAAAA==.Nurobi:BAABNQAECn9BAAIVAAoKchPGJADWAQAVAAoKchPGJADWAQAAAA==.',
Oa='Oaksong:BAAANQADCgQIBAAAAA==.',
Od='Odanobunaga:BAACNQAFFH8HAAIZAAMKLQjMLQByAAAZAAMKLQjMLQByAAA1AAQKfy8AAhkACgoGGXhVAIoCABkACgoGGXhVAIoCAAAA.Odyn:BAABNQAECn8bAAIWAAcK2Q/z3wAdAQAWAAcK2Q/z3wAdAQAAAA==.',
Oe='Oerrael:BAAANQADCgcIEAAAAA==.',
Or='Oridk:BAABNQAECn8+AAIeAAoKZR3oEwBTAgAeAAoKZR3oEwBTAgABNQAFFAYIDgANAEscAA==.Origen:BAAANQADCggICAAAAA==.Oripal:BAAANQAECgIIAgABNQAFFAYIDgANAEscAA==.Oríon:BAACNQAFFH8OAAMNAAYKSxw9CQBaAQANAAUKSxw9CQBaAQAgAAIK7wudAgBOAAA1AAQKfzQABCAACgoJI8kCAP0CACAACQpsHskCAP0CAA4ABgrwFSs7AHgBAA0ABgqBIpCkAGoBAAAA.',
Ou='Outofrange:BAAANQAECggICAAAAA==.',
Pa='Pangjang:BAAANQAECgUIEwAAAA==.Pankratease:BAAANQAECgcICQAAAA==.Pankratoes:BAAANQAECgIIAgABNQAECgcICQACAAAAAA==.Pankratos:BAAANQADCgUIBQABNQAECgcICQACAAAAAA==.Papahess:BAABNQAECn8sAAMVAAoK/hPQKwCjAQAVAAoK/hPQKwCjAQAHAAMKyQzSSQCFAAAAAA==.Paradias:BAABNQAECn8aAAIQAAkKMRSnEwBNAgAQAAkKMRSnEwBNAgAAAA==.Pastaladan:BAAANQADCgQIBAAAAA==.Pastor:BAAANQAECgUIDgAAAA==.Paxxul:BAAANQADCggICwAAAA==.',
Pe='Peppersham:BAABNQAECn8mAAMXAAoKJhPdOQDtAQAXAAoKJhPdOQDtAQAaAAYKoQvNswAHAQAAAA==.Petespally:BAABNQAECn86AAMJAAoK+yMIAwD8AwAJAAoK+yMIAwD8AwAbAAEKAACTbgA0AAAAAA==.',
Pf='Pfftpfft:BAAANQAECggIDAAAAA==.',
Ph='Pha:BAABNQAECn8gAAIGAAoKrRgibwCfAgAGAAoKrRgibwCfAgAAAA==.Phatdanny:BAAANQAECggIDAAAAA==.Phonycheese:BAABNQAECn8wAAMWAAoK5BRpeQA5AgAWAAkKfRZpeQA5AgAJAAQK0giXxACQAAAAAA==.Phur:BAAANQAECgMIAwAAAA==.',
Pi='Pixen:BAABNQAECn9nAAMBAAoK2hz2IwCCAgABAAoK2hz2IwCCAgADAAEKAAADMQAzAAAAAA==.',
Po='Pocalypse:BAAANQAECgQIBQAAAA==.Ponkeyfists:BAACNQAFFH8IAAImAAQK5BrNCgDJAAAmAAQK5BrNCgDJAAA1AAQKfywAAiYACgp6I/0IAEEDACYACgp6I/0IAEEDAAAA.Portstar:BAABNQAECn81AAIGAAoK0wt01gDaAQAGAAoK0wt01gDaAQAAAA==.Powderhorn:BAAANQADCgUIBQAAAA==.',
Pr='Pravium:BAAANQADCgYIBgABNQAECgoKIwASAFoWAA==.Primed:BAABNQAECn8/AAIiAAoKRBSADQBDAgAiAAoKRBSADQBDAgAAAA==.Prozac:BAAANQAECgEIAQABNQABCgcIBwACAAAAAA==.',
Pu='Pungla:BAABNQAECn8UAAImAAoKlRXOGgBoAgAmAAoKlRXOGgBoAgAAAA==.',
['Pî']='Pîper:BAAANQADCgcIBwAAAA==.',
Qu='Quelthanos:BAABNQAECn9BAAMWAAoKvhciTABGAgAWAAoKvhciTABGAgAJAAEKfBDGGwE8AAAAAA==.Quesoblanco:BAAANQABCgQIBAAAAA==.',
Ra='Racob:BAAANQAECgMIBAABNQAECgQIAwACAAAAAA==.Radical:BAAANQAECgMIBQAAAA==.Ralvick:BAAANQADCgEJAQAAAA==.Ramuun:BAAANQADCgIIAgAAAA==.Randomclown:BAAANQAECgEIAQAAAA==.Rascalfats:BAAANQAECgQICwABNQAECggIFAANAGATAA==.Rashii:BAABNQAECn8pAAISAAkKrxSiXgAFAgASAAkKrxSiXgAFAgAAAA==.Rawor:BAAANQAECgQIBAAAAA==.Raworrior:BAABNQAECn8lAAMZAAgKCA3XnwA+AQAZAAgKCA3XnwA+AQAIAAEKOAhgNQAwAAAAAA==.Razera:BAAANQADCgcIBwAAAA==.',
Re='Reax:BAAANQADCgYIBgAAAA==.Rebaderchi:BAABNQAECn8hAAIkAAkKYhkAGwCAAgAkAAkKYhkAGwCAAgABNQADCgMIAwACAAAAAA==.Reignofpower:BAAANQADCgUIBQAAAA==.Reisswolf:BAAANQAECgMIAwAAAA==.Remoria:BAABNQAECn8VAAIPAAcKkBKWHgAzAQAPAAcKkBKWHgAzAQAAAA==.Renildan:BAAANQAECgYIDQAAAA==.Renmazuo:BAAANQADCgMIAwAAAA==.Rezputan:BAAANQAECggIEgAAAA==.',
Rh='Rhavin:BAAANQAECgYICAAAAA==.Rhodon:BAABNQAECn8UAAMpAAkKPQwbVABFAQApAAgKDAobVABFAQAFAAIK7w9YdwB8AAAAAA==.Rhohorn:BAAANQAECggIDAAAAA==.Rholand:BAABNQAECn87AAMZAAoKjR1KVACOAgAZAAoK5hxKVACOAgAcAAEKxyDtNwBfAAAAAA==.Rhovid:BAAANQAECgQIBAAAAA==.',
Ri='Rivalt:BAAANQABCgQIBQAAAA==.Riverra:BAAANQADCgcICgAAAA==.Rizzoy:BAABNQAECn8kAAMIAAcKXRarFABVAQAIAAUKaRmrFABVAQAZAAYKzBKA4QAmAQAAAA==.',
Ro='Rollo:BAAANQAECgQIDAAAAA==.Roottender:BAAANQAECgIIAgAAAA==.Rostain:BAAANQAECgIIAgAAAA==.Rovyr:BAABNQAECn8uAAMjAAoKgx4MFABtAgAjAAoKgx4MFABtAgAlAAEKAAC4JwAlAAAAAA==.Rowinna:BAAANQADCgUIBQAAAA==.',
Ru='Ruckabis:BAABNQAECn8cAAIaAAkKeBXCRQBKAgAaAAkKeBXCRQBKAgAAAA==.',
Ry='Rybearkin:BAAANQADCgMIAwAAAA==.Rylos:BAABNQAECn8mAAIeAAgK0ArOMQBgAQAeAAgK0ArOMQBgAQAAAA==.Ryshadow:BAAANQADCgYICwAAAA==.Ryumi:BAABNQAECn8hAAIGAAoKDw01/QCTAQAGAAoKDw01/QCTAQAAAA==.',
Sa='Saansula:BAAANQADCgEIAQAAAA==.Sacmaster:BAAANQADCggIDAABNQAECgkJJwAhAHQWAA==.Saintagur:BAAANQABCgMIAQAAAA==.Saitamå:BAABNQAECn8kAAInAAkKxheBFgAUAgAnAAkKxheBFgAUAgAAAA==.Samanaras:BAABNQAECn8rAAMcAAkKxxA4IQDyAAAZAAgKrg6EowDEAQAcAAcKOBI4IQDyAAAAAA==.Sangwyn:BAAANQAECgYIDwABNQAECgkJLAAJAM4eAA==.Santiago:BAAANQAECgIIAgAAAA==.Saratoga:BAAANQAECgQICwAAAA==.Sarkana:BAABNQAECn8yAAMJAAoKzRoMIwDgAgAJAAoKzRoMIwDgAgAWAAEKSQYEsAEkAAAAAA==.Saxonn:BAAANQAECgIIAgAAAA==.Saydis:BAABNQAECn8aAAINAAgKUQgn2QAAAQANAAgKUQgn2QAAAQAAAA==.',
Sc='Scarletthot:BAAANQAECgIIAwAAAA==.Scatterbrain:BAAANQADCgcIEgAAAA==.',
Se='Sebattan:BAAANQADCgYIBwAAAA==.Seleinai:BAAANQADCgMIAwABNQAECgoKOQATAFkcAA==.Seleine:BAABNQAECn85AAITAAoKWRwlAgAJAwATAAoKWRwlAgAJAwAAAA==.Seloric:BAABNQAECn8qAAIFAAkKQR/mKwBpAgAFAAkKQR/mKwBpAgAAAA==.Serendrin:BAABNQAECn9YAAIPAAoKhSL0AgAcAwAPAAoKhSL0AgAcAwAAAA==.Sevalandre:BAAANQAECgIIAgABNQAECgkJGgARAJYdAA==.',
Sh='Shaaman:BAAANQADCgYIBgAAAA==.Shadowskyz:BAAANQAECgQIDgABNQAFFAUICQAXAIoLAA==.Shaggimaggi:BAABNQAECn8lAAMFAAoK1BOCIwDfAQAFAAoK1BOCIwDfAQAeAAEKZgExmQAcAAAAAA==.Shamanis:BAAANQADCgQIBAAAAA==.Shamcheese:BAAANQAECgQIBAABNQAECgoKMAAWAOQUAA==.Shamcow:BAAANQADCgcICwAAAA==.Shamina:BAACNQAFFH8JAAIXAAUKigvhDAAPAQAXAAUKigvhDAAPAQA1AAQKf1AAAxcACgo4HsMYAKQCABcACgo4HsMYAKQCABgAAQoYGm4zAEsAAAAA.Shammlet:BAAANQABCggIEwAAAA==.Shamorex:BAABNQAECn8sAAIXAAoKxBn6OQDsAQAXAAoKxBn6OQDsAQAAAA==.Shatter:BAABNQAECn8YAAIWAAgK/x5BXQCBAgAWAAgK/x5BXQCBAgAAAA==.Shax:BAAANQADCggICAABNQAECgkJLwAGALQiAA==.Shiftit:BAAANQAECgMIBQABNQAFFAIIBgAGAGkMAA==.Shlevin:BAAANQADCgcIDAAAAA==.Shockyoface:BAAANQABCgUIBQAAAA==.',
Si='Sideshift:BAAANQAECgQIBAABNQAFFAUICQAXAIoLAA==.Sinara:BAAANQAECgUICQAAAA==.',
Sk='Skaarr:BAAANQADCgQIBQAAAA==.Skibidiheals:BAAANQAECgEIAQAAAA==.Skybear:BAAANQABCgYICQAAAA==.',
Sl='Slash:BAAANQADCgYIBgAAAA==.Slayn:BAABNQAECn9NAAIoAAoKextvBgBhAgAoAAoKextvBgBhAgAAAA==.Sleebo:BAAANQAECgYIEgAAAA==.Sleinx:BAAANQADCggIDQABNQAFFAUIEAAXADMOAA==.Slyrak:BAABNQAECn8eAAMfAAoKoxTrCQDTAQAfAAkK2BbrCQDTAQAjAAUKIAuVJwDEAAAAAA==.',
Sm='Smitus:BAAANQABCgIIAgAAAA==.',
Sn='Snackie:BAABNQAECn8qAAMaAAoK8x0WIwCpAgAaAAoK8x0WIwCpAgAXAAEKNQjc/QA2AAAAAA==.Snooty:BAAANQAECggJAgAAAA==.Snotpig:BAAANQAECggIBwAAAA==.',
So='Sokar:BAAANQAECggICgAAAA==.Sokolovva:BAAANQADCgcIDAAAAA==.Souled:BAAANQADCgUIBQABNQAECgkJMgAGAO4SAA==.Sourpunchkid:BAAANQAECgYIBwAAAA==.',
Sp='Spacedemon:BAABNQAECn8dAAIkAAkKtg3uNQCUAQAkAAkKtg3uNQCUAQAAAA==.Spacepaly:BAAANQAECgQIBAAAAA==.Sparroh:BAAANQADCgYIBgAAAA==.Spikedriver:BAABNQAECn8oAAINAAoKHQ56agA+AgANAAoKHQ56agA+AgAAAA==.Spiky:BAAANQADCgMIAwAAAA==.',
St='Stariane:BAABNQAECn8vAAIKAAoK9hpjGQDQAgAKAAoK9hpjGQDQAgAAAA==.Starie:BAAANQAECgMIAwAAAA==.Startaker:BAAANQADCggIDwAAAA==.Startaster:BAAANQADCgcIBwAAAA==.Starvoid:BAAANQAECgYICAAAAA==.Stateofgrace:BAAANQAECggICwABNQAECgoKJAAMAK4lAA==.Steeldk:BAAANQAECgIJAgAAAA==.Stella:BAAANQAECgQICAAAAA==.Stonyfist:BAAANQADCgEIAQAAAA==.Stonyy:BAAANQAECgIIAgAAAA==.Stormhaven:BAAANQADCggICAAAAA==.Stubhorn:BAAANQADCgUICAAAAA==.',
Su='Summers:BAAANQADCgcIEQAAAA==.Sumonmyface:BAABNQAECn8nAAMhAAkKdBbPIgBbAQAhAAQKEh7PIgBbAQABAAYKvhBZxQBAAQAAAA==.Superillbomb:BAAANQADCgYJCQAAAA==.Superold:BAABNQAECn8VAAINAAgKzAwRgwCzAQANAAgKzAwRgwCzAQAAAA==.',
Sw='Swamprot:BAABNQAECn8lAAIeAAgKhh2lMwBcAgAeAAgKhh2lMwBcAgAAAA==.',
Sy='Sydoom:BAAANQABCgEIAQAAAA==.Syletage:BAAANQADCgYICwAAAA==.Syral:BAAANQADCgcIEQAAAA==.Syrel:BAAANQAECgEIBAAAAA==.',
Ta='Tailfordays:BAAANQADCgIIAgAAAA==.Tanky:BAAANQADCgIIAgAAAA==.Tantor:BAAANQADCgEIAQAAAA==.Tarragon:BAAANQADCgcIBwAAAA==.Taurnator:BAAANQAECgIIAgAAAA==.Taylorswift:BAABNQAECn8kAAMMAAoKriUVHwAGAgAMAAcKdyUVHwAGAgAiAAQKZB3hGgBTAQAAAA==.',
Tc='Tchiratha:BAABNQAECn8YAAMaAAkK7g5gewBBAQAaAAgK5A1gewBBAQAXAAYKgwOIqQCzAAABNQAECgoKQQAWAL4XAA==.',
Te='Tednougat:BAAANQADCgYIBgAAAA==.Telain:BAABNQAECn8tAAQJAAoKeQocngBKAQAJAAkKBQgcngBKAQAWAAgKGQtd+gAqAQAbAAIKSQz9XQBjAAAAAA==.Tensuki:BAAANQADCgQIBAAAAA==.Tesh:BAAANQADCgQIBgAAAA==.',
Th='Thaelynn:BAAANQADCggIHAAAAA==.Thakilla:BAABNQAECn9RAAIVAAoKBhYcHAAlAgAVAAoKBhYcHAAlAgAAAA==.Thordrik:BAAANQAECgIIAQAAAA==.Thorix:BAAANQAECgYICQAAAA==.Thornhub:BAAANQAECggIDgABNQAFFAoKQgAhAJUiAA==.Thrust:BAAANQAECgUIDgABNQABCgcIBwACAAAAAA==.Thrustwood:BAAANQADCgMIAwAAAA==.',
Ti='Tiammanth:BAAANQAECgYIDgAAAA==.Tigerbrew:BAAANQADCgUIBQAAAA==.Tigerburn:BAAANQADCgQIBAAAAA==.Tigerdawn:BAAANQADCgYIBgAAAA==.Tigerluna:BAAANQADCgQIBAAAAA==.Tikya:BAAANQADCgYIBwAAAA==.Tilsit:BAAANQAECggIDQAAAA==.Timberreaper:BAAANQADCgcICAAAAA==.Tinyz:BAAANQAECgQICQAAAA==.Tisisme:BAAANQADCgUIBQAAAA==.',
To='Tonythetiger:BAAANQAECgYICgABNQAECgoKWQAFAPcgAA==.Toucansham:BAAANQAECgIIAgABNQAECgoKWQAFAPcgAA==.',
Tr='Train:BAAANQADCgcIBwAAAA==.Trampadin:BAAANQABCgQIBAAAAA==.Trei:BAAANQADCgIIAgABNQAECgcIDQACAAAAAA==.Trexlot:BAAANQADCgIIAgAAAA==.Trinjal:BAAANQAECgEIAgAAAA==.',
Tu='Tubbylumpkin:BAAANQADCggIDAAAAA==.Tummi:BAAANQADCgcIEAAAAA==.Tumnus:BAAANQAECgEIAQAAAA==.',
Ty='Tyjan:BAAANQAECgIIAwAAAA==.',
['Tâ']='Tâfa:BAAANQADCggICAAAAA==.',
Uh='Uhtred:BAAANQADCgYIBwAAAA==.',
Ul='Ulti:BAABNQAECn8sAAMJAAkKzh4BNACUAgAJAAkKzh4BNACUAgAbAAIKfQaqcQAgAAAAAA==.',
Un='Unholydevil:BAAANQAECgUIBwAAAA==.Unholyheart:BAAANQAECgIIAgAAAA==.',
Va='Varthios:BAAANQABCgQIBgAAAA==.Varyusha:BAAANQAECgEIAQAAAA==.',
Ve='Velantra:BAAANQAECggIDgAAAA==.Venari:BAABNQAECn8mAAIgAAkKXBg6BABIAgAgAAkKXBg6BABIAgAAAA==.',
Vi='Vilelyn:BAABNQAECn8sAAMnAAoKlBfBCwB9AgAnAAoKlBfBCwB9AgAmAAYKFwrcNAD6AAABNQADCgEIAQACAAAAAA==.Viloria:BAABNQAECn8pAAIHAAgKthaoHgCqAQAHAAgKthaoHgCqAQAAAA==.Vincent:BAAANQADCgQIBAAAAA==.Viridia:BAAANQADCggICAAAAA==.Virrard:BAABNQAECn8kAAINAAoK7BdOVAB0AgANAAoK7BdOVAB0AgAAAA==.',
Vl='Vladimor:BAABNQAECn8bAAMBAAkKiBNWbQCRAQABAAgK8hVWbQCRAQADAAEKDAW1MQAoAAAAAA==.Vladimyrr:BAAANQADCgUJCAAAAA==.',
Vo='Voslaarum:BAAANQADCgEIAQABNQAECgcIFgAFALwPAA==.Vozrezz:BAABNQAECn8ZAAMnAAcKRh5TFAC/AQAnAAcKRh5TFAC/AQAmAAUKlhTcUwCgAAAAAA==.',
Vu='Vualake:BAAANQAECgYIBgAAAA==.',
['Vë']='Vëda:BAABNQAECn89AAISAAoKPiDWGwADAwASAAoKPiDWGwADAwAAAA==.',
Wa='Waffle:BAAANQAECgIIAwABNQAFFAcICAAYAIYSAA==.Warage:BAAANQAECgEIAQAAAA==.Warske:BAAANQAECgYIDgAAAA==.',
Wh='Wheaties:BAAANQAECgYICgABNQAECgoKWQAFAPcgAA==.Whizzie:BAABNQAECn8yAAIGAAkK7hJ4nwBCAgAGAAkK7hJ4nwBCAgAAAA==.Whizzlecrank:BAABNQAECn81AAIGAAkKTBR8pQA2AgAGAAkKTBR8pQA2AgAAAA==.',
Wi='Wicker:BAABNQAECn8rAAMVAAkKtRW9QwDlAQAVAAcK9xO9QwDlAQAMAAUKHxJhRgD+AAAAAA==.Willpharaoh:BAAANQADCgUICgAAAA==.Wiçker:BAAANQADCgIIAgABNQAECgkJKwAVALUVAA==.',
Wo='Wolford:BAAANQADCgYIBgAAAA==.',
Wr='Wras:BAABNQAECn8jAAIFAAkKBhJiMwB8AQAFAAkKBhJiMwB8AQAAAA==.Wrectt:BAAANQAECgUIDgABNQAECgcIDgACAAAAAA==.',
['Wò']='Wòbbles:BAAANQAECgQIDQABNQAECggIFAANAGATAA==.',
Xa='Xandrah:BAAANQADCgUJBQAAAA==.Xandrel:BAABNQAECn8sAAIWAAkK4Q7qwwBMAQAWAAkK4Q7qwwBMAQAAAA==.',
Xe='Xed:BAABNQAECn8+AAIXAAgKbRkdSwBKAgAXAAgKbRkdSwBKAgAAAA==.Xenogears:BAABNQAECn8rAAIOAAkKyhq2HgBbAgAOAAkKyhq2HgBbAgAAAA==.',
Xi='Xiansai:BAABNQAECn8xAAIUAAoKlBLbIAAxAgAUAAoKlBLbIAAxAgAAAA==.',
Ya='Yappey:BAAANQAECgcIBwAAAA==.',
Yi='Yippee:BAABNQAECn8iAAIXAAoKgh5WGQCgAgAXAAoKgh5WGQCgAgAAAA==.',
Yo='Youthinasia:BAABNQAECn8bAAMOAAgKZwyCRAA0AQAOAAcKLwyCRAA0AQANAAUKgghR4QDuAAAAAA==.',
Za='Zakilan:BAAANQADCgUIBgABNQADCgcICwACAAAAAA==.',
Ze='Zerega:BAAANQADCgcIHAABNQAECgoKawAPAGgSAA==.',
Zh='Zhi:BAAANQAECgUIBgAAAA==.Zhukov:BAAANQADCgYIBgABNQADCggIDwACAAAAAA==.',
Zo='Zombiehippo:BAABNQAECn86AAIGAAoKZBm0VwDRAgAGAAoKZBm0VwDRAgAAAA==.',
['Áu']='Áutarch:BAABNQAECn8ZAAIZAAgKkwf53AAyAQAZAAgKkwf53AAyAQAAAA==.',
['Ðe']='Ðemøn:BAAANQAECgMIAwAAAA==.',
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
