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

local lookup = {'Warlock-Demonology','Unknown-Unknown','Warlock-Affliction','Rogue-Outlaw','Mage-Arcane','Druid-Guardian','Warrior-Fury','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Monk-Brewmaster','Priest-Holy','Priest-Discipline','Priest-Shadow','Druid-Balance','Paladin-Retribution','Shaman-Elemental','Shaman-Enhancement','Warrior-Arms','Paladin-Protection','Shaman-Restoration','Warrior-Protection','Mage-Fire','DeathKnight-Blood','DeathKnight-Unholy','Evoker-Devastation','Hunter-Survival','Warlock-Destruction','Druid-Feral','Evoker-Preservation','DemonHunter-Devourer','Evoker-Augmentation','Monk-Windwalker','Monk-Mistweaver','Mage-Frost','DeathKnight-Frost',}
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abris:BAAANQAECgEIAwABNQAECgkJGwABAIgTAA==.',
Ac='Acekith:BAAANQABCgMIAwABNQAECgQJCAACAAAAAA==.Acense:BAAANQAECgQJCAAAAA==.Acidhunter:BAAANQADCgcIBwAAAA==.Acidlock:BAABNQAECn8ZAAIDAAgKbBJOCQDvAQADAAgKbBJOCQDvAQAAAA==.Acidpriest:BAAANQAECgYIDgAAAA==.',
Ad='Adacey:BAABNQAECn8YAAIEAAgKGQ5uBQAVAQAEAAgKGQ5uBQAVAQAAAA==.Adragon:BAAANQADCgQIBAABNQAECgYIEgACAAAAAA==.Adrenalized:BAAANQADCgMIBAAAAA==.',
Ae='Aendrin:BAAANQAECgEIAQAAAA==.Aesuga:BAAANQADCgYIBgAAAA==.',
Af='Afteraction:BAAANQAECgMIAwAAAA==.',
Ak='Aktras:BAABNQAECn8cAAIFAAYK9hHr2QDmAAAFAAYK9hHr2QDmAAAAAA==.',
Al='Alaunu:BAABNQAECn87AAIGAAoKaBEZGADvAQAGAAoKaBEZGADvAQAAAA==.Aleas:BAAANQADCgQIBAAAAA==.Alexx:BAAANQAECgQIDQAAAA==.Alkaid:BAAANQAECgYIEAAAAA==.Alric:BAAANQAECgQIBgAAAA==.',
An='Anari:BAAANQAECgQIBwABNQAECggIDQACAAAAAA==.Anarky:BAABNQAECn8UAAIHAAgKgAG0MAA9AAAHAAgKgAG0MAA9AAAAAA==.Angelcorp:BAAANQAECgMIAwAAAA==.Annebonny:BAAANQAECgUIDwAAAA==.Anorak:BAAANQAECgEIAQAAAA==.Anthrfinpete:BAAANQAECggICQABNQAECgkJMwAIAB0kAA==.',
Ap='Apsalar:BAAANQADCgcJBwAAAA==.',
Ar='Archdemon:BAABNQAECn9bAAMJAAoKASV+AwC6AwAJAAoKsCR+AwC6AwAKAAkKVx9EBQDeAgAAAA==.Arienys:BAAANQADCgYIEAAAAA==.Arigosa:BAAANQAECgEIAgAAAA==.Ariis:BAAANQADCgUICQAAAA==.Arkh:BAAANQADCgMIAwAAAA==.Arkhanx:BAAANQADCgUJBQAAAA==.Arkhfu:BAAANQAECgIIAwAAAA==.Arleen:BAAANQAECgUIBQAAAA==.Arquen:BAABNQAECn8wAAIIAAoK0yJkDABYAwAIAAoK0yJkDABYAwAAAA==.Artemisia:BAAANQAECgEIAQAAAA==.',
As='Asevenx:BAAANQADCggIEQAAAA==.Ashamane:BAAANQAECgEIBAAAAA==.Asheril:BAAANQAECgEIAgAAAA==.Asian:BAAANQADCgIIAgAAAA==.Asra:BAAANQAECgYIDQAAAA==.Astrov:BAABNQAECn8mAAIJAAoKUxOxNwDzAQAJAAoKUxOxNwDzAQAAAA==.',
At='Atulmags:BAAANQAECgYIDAAAAA==.',
Au='Auani:BAABNQAECn89AAILAAoKcCBEBwBOAwALAAoKcCBEBwBOAwAAAA==.Aurelily:BAAANQADCgYJDAAAAA==.Ausia:BAAANQAECgUIBwAAAA==.',
Av='Avann:BAAANQADCgIIAgAAAA==.',
Az='Azazyl:BAAANQAECgUIBgAAAA==.Azzeus:BAAANQAECgUIDAABNQAECgoKLQAMAO8YAA==.Azzfists:BAAANQADCgQIBAABNQAECgoKLQAMAO8YAA==.Azzshot:BAABNQAECn8tAAMMAAoK7xiGgAAMAgAMAAgKWRmGgAAMAgANAAoKkgmDOgB8AQAAAA==.',
Ba='Babyrinsjr:BAABNQAECn8jAAIMAAgKiA6XlwBpAQAMAAgKiA6XlwBpAQAAAA==.Badista:BAAANQADCgIIAgAAAA==.Baile:BAAANQAECgIIAgABNQAECgQIBQACAAAAAA==.Balleont:BAABNQAECn8qAAIMAAoKehOIWABqAgAMAAoKehOIWABqAgAAAA==.Barrada:BAABNQAECn8nAAIMAAgK8wbOxwByAQAMAAgK8wbOxwByAQAAAA==.',
Be='Beefcakeßody:BAAANQADCgYIBgAAAA==.Berea:BAABNQAECn9lAAMOAAoKXhInGABbAQAPAAoKWhFPNQARAgAOAAgK1AwnGABbAQAAAA==.',
Bi='Birgi:BAAANQAECggICAAAAA==.',
Bl='Blankdemonic:BAAANQAECgEIAQAAAA==.Blankwar:BAAANQADCgUIBQAAAA==.Bleedblue:BAABNQAECn8hAAIPAAoKNQv0JQCXAQAPAAoKNQv0JQCXAQAAAA==.Blitzed:BAAANQADCgIIAgAAAA==.Bloodhaven:BAAANQADCgEIAQAAAA==.',
Bo='Bo:BAABNQAECn89AAIMAAoK2BsRJQACAwAMAAoK2BsRJQACAwAAAA==.Bobbinrobin:BAABNQAECn8XAAIPAAgKsQ8STgCuAQAPAAgKsQ8STgCuAQAAAA==.Borahae:BAAANQAFFAEIAQABNQAFFAIIBQAIAKADAA==.Borden:BAAANQADCgQJBAAAAA==.',
Br='Bradent:BAABNQAECn8VAAIMAAkKwwI1+QARAQAMAAkKwwI1+QARAQAAAA==.Breach:BAAANQAECgQIBQAAAA==.Brunnhild:BAAANQAECgIIAwAAAA==.Bryxi:BAABNQAECn8aAAIQAAkKlh3CBABWAgAQAAkKlh3CBABWAgAAAA==.Brünhilde:BAABNQAECn80AAQRAAoKPxVKWAAZAgARAAoKHRRKWAAZAgASAAQKAxCeFQDRAAATAAEKAABJhwAiAAAAAA==.',
Bs='Bstbll:BAACNQAFFH8XAAILAAcKNhjIAwABAgALAAcKNhjIAwABAgA1AAQKfzkAAwsACgreHyYRAJwCAAsACgreHyYRAJwCABQAAQp/FU2EADQAAAAA.',
Bu='Bubbleheals:BAABNQAECn86AAMIAAoKbBFgQwD0AQAIAAoKbBFgQwD0AQAVAAUK5gPuWQFfAAABNQAFFAUICQAWAIoLAA==.Bundtcake:BAAANQAECggICAAAAA==.Burningfist:BAABNQAECn8XAAIXAAQKvgwnJwDvAAAXAAQKvgwnJwDvAAAAAA==.Buttsnacks:BAABNQAECn8mAAIYAAoKUxWIWACCAgAYAAoKUxWIWACCAgAAAA==.',
Ca='Caciocavallo:BAAANQAECggIAQABNQAECggIDQACAAAAAA==.Calar:BAAANQAECgUIBgAAAA==.Callistrah:BAAANQAECgUIBwAAAA==.Caltaa:BAABNQAECn89AAIZAAoKayPNBQBRAwAZAAoKayPNBQBRAwAAAA==.Canarah:BAAANQADCgQIBAABNQAECgkJGgAaAJIZAA==.Canverian:BAABNQAECn8jAAIGAAgKRxWAIABnAQAGAAgKRxWAIABnAQAAAA==.Captinwrath:BAAANQAECgEIAQAAAA==.Captsmash:BAABNQAECn87AAMbAAoKwBwBCABRAgAbAAoKwBwBCABRAgAYAAUK9QbgzgDCAAAAAA==.Carmedic:BAAANQADCgIIAgAAAA==.Caudel:BAAANQAECgEIAwAAAA==.',
Cd='Cdub:BAAANQAECgYIDwAAAA==.',
Ce='Cenarial:BAAANQAECgEIAQAAAA==.',
Ch='Charcuterie:BAAANQAECgQIDQAAAA==.Chasseurfool:BAABNQAECn8hAAIMAAkKhwkSiwCFAQAMAAkKhwkSiwCFAQAAAA==.Chat:BAACNQAFFH8QAAIWAAUKMw5TCwAOAQAWAAUKMw5TCwAOAQA1AAQKf0IAAhYACgqzHJ8kAEQCABYACgqzHJ8kAEQCAAAA.Chevre:BAABNQAECn8VAAIMAAUKphDS8gAcAQAMAAUKphDS8gAcAQAAAA==.Chezaro:BAABNQAECn8sAAIVAAkKnw3IjACeAQAVAAkKnw3IjACeAQAAAA==.Chickenwing:BAABNQAECn8tAAIcAAoKTiEsAQDcAgAcAAoKTiEsAQDcAgAAAA==.Christano:BAABNQAECn8qAAMVAAoK2x8qOQByAgAVAAoKbx8qOQByAgAZAAMKRyAmPQCjAAAAAA==.Christhecold:BAABNQAECn8gAAIYAAgKHxrMbgBGAgAYAAgKHxrMbgBGAgAAAA==.Chrollo:BAAANQAECgUIEgAAAA==.Chuchu:BAAANQADCgMIAwAAAA==.Chumba:BAAANQAECgYIDwAAAA==.',
Ci='Cinnamilk:BAAANQAECggICQABNQAECgkJTwAdAPQfAA==.',
Cl='Clamslamm:BAEANQADCgUIBQABNQAECgcIHwAeAJIhAA==.Cloudcrack:BAECNQAFFH8RAAMaAAcKbhD9EgAiAQAaAAcKbhD9EgAiAQAWAAMKdAqDHADcAAA1AAQKfzEAAxoACgp+I5wGAKIDABoACQrDI5wGAKIDABYACQo2HPksAMkCAAAA.',
Co='Cocotaso:BAAANQABCgIIAgABNQAECgEIAQACAAAAAA==.Codemon:BAABNQAECn8rAAIfAAkKDhdiDAB7AQAfAAkKDhdiDAB7AQAAAA==.Cole:BAAANQADCgUIBQAAAA==.Cosmoline:BAABNQAECn8jAAIgAAoKmhw+BACoAgAgAAoKmhw+BACoAgABNQAECgcIFAAJAGIRAA==.Cotw:BAAANQAECgIIAgABNQAECgYIEgACAAAAAA==.Coverttops:BAABNQAECn8ZAAQhAAgKBApcKQAwAQAhAAcKPQlcKQAwAQADAAQKJAo4GQCgAAABAAIKgQQQNQFPAAAAAA==.',
Cp='Cptcharis:BAAANQADCgEIAQAAAA==.',
Cr='Critmyshorts:BAAANQAECgYIDwAAAA==.Critnespears:BAAANQADCgYIBgAAAA==.Crottin:BAAANQAECgQIAwAAAA==.Crystaltitan:BAAANQADCgQIBAAAAA==.',
Cu='Cubann:BAAANQAECgIIAgAAAA==.',
Cy='Cylrhea:BAAANQAECgUIDwAAAA==.Cynri:BAAANQADCgQIBQABNQAECgIIAgACAAAAAA==.Cyntrill:BAAANQAECgUICgAAAA==.',
Da='Daboulder:BAAANQAECgEIAgAAAA==.Dadderz:BAAANQAECgEIAQAAAA==.Daedean:BAAANQAECgIIAwABNQAECgQIBQACAAAAAA==.Dagnome:BAAANQADCggICAAAAA==.Dahunter:BAAANQAECgIIAgAAAA==.Dajoel:BAAANQAECgIIAwAAAA==.Dalacia:BAABNQAECn8eAAIaAAoKkRVFXgD0AQAaAAoKkRVFXgD0AQAAAA==.Daphera:BAAANQADCgcIEgAAAA==.Darkforceray:BAAANQABCgQIBAAAAA==.Darkhollow:BAAANQADCggIIgAAAA==.Darkhunta:BAAANQADCgQIBAAAAA==.Darknature:BAABNQAECn8jAAILAAgKhRjiIQAYAgALAAgKhRjiIQAYAgAAAA==.Darkodin:BAABNQAECn8hAAIeAAgKtgqJPgAHAQAeAAgKtgqJPgAHAQAAAA==.Darkshamy:BAAANQAECgQICQAAAA==.Darksknightt:BAAANQADCgEIAQAAAA==.Darkspriest:BAAANQAECgMIAwAAAA==.Darrad:BAAANQAECgUICQAAAA==.Datnagadrake:BAACNQAFFH8RAAIYAAYKcRXuCgB/AQAYAAYKcRXuCgB/AQA1AAQKf1AAAxgACgoUI5wcAMwCABgACgrfIpwcAMwCABsABgrdIAgQACgCAAAA.Dawinchy:BAABNQAECn8uAAMLAAoKaxnLGAB3AgALAAoKaxnLGAB3AgAiAAYKxg5oGwBMAQAAAA==.',
De='Deadlypsycho:BAAANQAECgEIAwAAAA==.Deathavoider:BAAANQADCggIEAAAAA==.Deathawakens:BAAANQADCgEIAQAAAA==.Deathlyill:BAAANQAECgIJAgAAAA==.Decemberr:BAAANQAECgQICQAAAA==.Dekudin:BAABNQAECn8fAAIZAAoKuRIXGgCLAQAZAAoKuRIXGgCLAQAAAA==.Dellistia:BAAANQADCgcIEQAAAA==.Dennywenny:BAAANQAECgUIDgAAAA==.Deric:BAAANQAECgEIAQAAAA==.Desdamona:BAABNQAECn8hAAIMAAcK2QOv3wDWAAAMAAcK2QOv3wDWAAAAAA==.Destrodemon:BAAANQADCggICAAAAA==.Destropally:BAABNQAECn8hAAIVAAkK0w4XqwDJAQAVAAkK0w4XqwDJAQAAAA==.Devorick:BAABNQAECn9DAAMBAAoKBBwyIwB3AgABAAoKBBwyIwB3AgAhAAIKIhBQVwB5AAAAAA==.Deyeraa:BAAANQADCgUIBQAAAA==.',
Di='Diaval:BAAANQAECgQICQAAAA==.Dih:BAAANQADCgYIBgABNQAECgkJJwAhAHQWAA==.Dijarl:BAABNQAECn8wAAIMAAkK8SEuEAAJAwAMAAkK8SEuEAAJAwAAAA==.Dipndots:BAAANQAECgUICAAAAA==.Dirtyboy:BAAANQADCgIIAgAAAA==.Discórdia:BAAANQAECgMIAwAAAA==.Dissention:BAAANQAECgEIAQAAAA==.Divineplea:BAAANQADCgcIBwAAAA==.Diyiya:BAABNQAECn8aAAIMAAcK+wl+wAAWAQAMAAcK+wl+wAAWAQAAAA==.',
Do='Doggiestylin:BAAANQAECgQICAAAAA==.Doorki:BAAANQAECggIDgAAAA==.Dottey:BAABNQAECn8dAAIhAAkKUBShCQAZAQAhAAkKUBShCQAZAQAAAA==.Doubleott:BAAANQAECgEIAgAAAA==.',
Dr='Drael:BAAANQAECgUIDAAAAA==.Draickin:BAABNQAECn8lAAIIAAkKyxSuZADqAQAIAAkKyxSuZADqAQAAAA==.Drekle:BAABNQAECn8oAAMjAAoKShAMEwCwAQAjAAkK/g0MEwCwAQAfAAgKuxThDABvAQAAAA==.Drelian:BAAANQAECgUICQAAAA==.Drevy:BAABNQAECn8VAAIEAAgK8BZLBgBwAgAEAAgK8BZLBgBwAgAAAA==.Drewdox:BAAANQADCgYIDgAAAA==.Drewsguy:BAAANQAECgEIAQAAAA==.Drexchan:BAAANQAECgEIAgAAAA==.Drizzlenuts:BAABNQAECn8fAAMaAAoKNht6FQD4AgAaAAoKNht6FQD4AgAWAAEK/QHqVgEiAAAAAA==.Drrabbít:BAAANQADCgQIBAAAAA==.Drumira:BAAANQAECgEIAQABNQAECgkJHgATAPEPAA==.Drumk:BAAANQADCgIIAgABNQAECgkJHgATAPEPAA==.Drumma:BAAANQADCggIFQAAAA==.Drummer:BAABNQAECn8eAAQTAAkK8Q/BNAB9AQATAAcKnQzBNAB9AQASAAUKrhSnDwAwAQARAAUKkgUuvADlAAAAAA==.Drumroleplz:BAAANQAECgQIBQABNQAECgkJHgATAPEPAA==.',
Dw='Dw:BAACNQAFFH8FAAIkAAIKqw6wEACNAAAkAAIKqw6wEACNAAA1AAQKfzYAAyQACgpZHK0RADECACQACgpZHK0RADECAAkAAwqrD4t2AKAAAAE1AAUUBQgRAAwA8xsA.',
['Dà']='Dàddybear:BAABNQAECn8iAAIMAAcKkAzLsQAzAQAMAAcKkAzLsQAzAQAAAA==.',
Ea='Earthsangel:BAAANQAECgUIBwAAAA==.',
Ec='Echonox:BAABNQAECn8WAAIVAAcKCRfJhQCsAQAVAAcKCRfJhQCsAQAAAA==.Eclair:BAAANQAECgQICQAAAA==.',
Ed='Edralyia:BAAANQADCgcIEQAAAA==.',
Eg='Egwene:BAAANQADCgQIBAAAAA==.',
Ei='Eilaurosa:BAABNQAECn8WAAIOAAgKlgk7RQCyAQAOAAgKlgk7RQCyAQAAAA==.Einnarr:BAABNQAECn8WAAIVAAoKVh1MIgDOAgAVAAoKVh1MIgDOAgAAAA==.',
El='Eldrinne:BAABNQAECn8iAAIcAAgKEATwBQANAQAcAAgKEATwBQANAQAAAA==.Eleblast:BAAANQAECgIIAgAAAA==.Elizavoid:BAABNQAECn8hAAQRAAkKKxswQwBfAgARAAkKKxswQwBfAgATAAUKUhDaPACqAAASAAEKLhf7JABEAAAAAA==.Elizawrath:BAAANQADCgIIAgAAAA==.Elkuco:BAAANQAECgEIAQAAAA==.Elmindreyda:BAABNQAECn8uAAIPAAoKkA3AWgCAAQAPAAoKkA3AWgCAAQAAAA==.Elthiss:BAABNQAECn9DAAMGAAoKxBlbEQANAgAGAAoKxBlbEQANAgAiAAEKWhWsPgBDAAAAAA==.',
En='Enfer:BAABNQAECn8ZAAIJAAgKcQvoMgBtAQAJAAgKcQvoMgBtAQABNQAFFAUIEAAWADMOAA==.Enyfing:BAAANQAECgUIBgAAAA==.',
Ep='Ephraìm:BAAANQAECgEIAQAAAA==.',
Er='Erequois:BAAANQADCgEIAQABNQAECgkJGgAQAJYdAA==.Erianthe:BAABNQAECn8qAAIeAAoKeQescwBIAQAeAAoKeQescwBIAQAAAA==.Eriok:BAAANQAECgEIAQAAAA==.Erophien:BAAANQADCgMIBAAAAA==.Eroryn:BAAANQAECgUIDgAAAA==.Erovynthalin:BAAANQADCgYIEAAAAA==.Errorwing:BAABNQAECn8WAAIlAAoKJRY9BQAhAgAlAAoKJRY9BQAhAgAAAA==.',
Es='Eshera:BAAANQADCgIIAgAAAA==.Esherä:BAAANQAECgEIAgAAAA==.',
Ev='Eversong:BAAANQADCgYIDAAAAA==.',
Ex='Exmar:BAAANQAECggIDgAAAA==.',
Ey='Eyesopen:BAAANQAECgYIEQABNQAECgoKJAALAK4lAA==.',
Fa='Faewhisker:BAABNQAECn8YAAMmAAkKyw25KQDQAQAmAAkKyw25KQDQAQAnAAQKBQYgOwCZAAAAAA==.Faithfool:BAABNQAECn8mAAIWAAoKbwqSkAB7AQAWAAoKbwqSkAB7AQAAAA==.Falshallnot:BAAANQAECgQIBAABNQAECgoKKAAjAEoQAA==.Fancyfeet:BAAANQAECgUIBQABNQAECgkJGgAPADEUAA==.Fanduelfiend:BAAANQADCgMIAwAAAA==.Fangmonarch:BAAANQADCgUIBQAAAA==.Fashaladd:BAABNQAECn8wAAQUAAkKNRQPPwACAgAUAAkKNRQPPwACAgAGAAEKAAA1WABIAAALAAEKXxOmbQA5AAABNQAECgoKKAAjAEoQAA==.',
Fe='Fearios:BAABNQAECn9PAAIdAAkK9B+fGADoAgAdAAkK9B+fGADoAgAAAA==.Felbeast:BAAANQAECgMIBQAAAA==.Felbound:BAAANQADCgUICQAAAA==.Femboy:BAAANQADCggICAAAAA==.Feorar:BAAANQAECgEIAQAAAA==.Feta:BAAANQAECgYICgABNQAECggIDQACAAAAAA==.',
Fi='Fieldtrip:BAABNQAECn8gAAIRAAYKEBvpWgC8AQARAAYKEBvpWgC8AQAAAA==.Fiendfyre:BAAANQADCgUIBQAAAA==.Fistedwaffle:BAAANQAECgEIAQAAAA==.Fizzlenuts:BAABNQAECn8ZAAInAAgK6xUiFgAaAgAnAAgK6xUiFgAaAgABNQAECgoKHwAaADYbAA==.',
Fl='Flaspios:BAAANQADCgcIBwAAAA==.Flightless:BAAANQADCggICgAAAA==.',
Fo='Foxi:BAAANQAECgQJBAAAAA==.',
Fr='Frosttbyte:BAACNQAFFH8GAAIFAAIKaQyVNwCGAAAFAAIKaQyVNwCGAAA1AAQKfz8AAwUACgqNGVFqAKkCAAUACgoQGVFqAKkCACgAAQqMHgA5AFoAAAAA.Frostytute:BAAANQADCgIIAgAAAA==.',
Fu='Fullmetalass:BAABNQAECn8WAAIMAAkKZxYbjQDwAQAMAAkKZxYbjQDwAQAAAA==.',
Fy='Fyyre:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëiróx:BAAANQADCgIIAgAAAA==.',
Ga='Galistar:BAABNQAECn8kAAIWAAgKUgzScQAdAQAWAAgKUgzScQAdAQAAAA==.Garglelots:BAAANQAECgYICQABNQAECggIFwAPALEPAA==.Garrotxa:BAAANQAECggICwABNQAECggIDQACAAAAAA==.',
Ge='Gevallen:BAAANQAECgcICwAAAA==.',
Gh='Ghavinental:BAABNQAECn8mAAMWAAkKsQ5qgQChAQAWAAcKAQ9qgQChAQAXAAkKlQsMHwBvAQAAAA==.',
Gi='Gil:BAABNQAECn8mAAIkAAoKtx6bFADCAgAkAAoKtx6bFADCAgAAAA==.Gilgamesh:BAAANQAECgUIDAABNQAECgoKJgAkALceAA==.',
Gl='Glizzard:BAAANQAECgUIDgABNQAECggIGAAVAP8eAA==.Glocket:BAAANQAECgIIDgAAAA==.Gloom:BAAANQAECgYIBgAAAA==.',
Gn='Gnolan:BAABNQAECn8vAAMPAAoKEhsEEgBiAgAPAAoKEhsEEgBiAgAOAAUKHROXXgA8AQAAAA==.',
Go='Goatspace:BAABNQAECn8rAAQgAAoK3gqyCQArAQAMAAkK2wfRxQB2AQAgAAYK4AqyCQArAQANAAUKDQPLXwCnAAAAAA==.Gomu:BAAANQADCgQIBAAAAA==.Gongagà:BAABNQAECn8kAAIkAAkK/g6jLQDUAQAkAAkK/g6jLQDUAQAAAA==.Goodnoodle:BAAANQAECgEIAgAAAA==.Goodwithabow:BAAANQAECgQICQAAAA==.Goremaster:BAAANQAECgQICwAAAA==.Gothbaddie:BAAANQAECgQIBAABNQAECggIDQACAAAAAA==.Goyum:BAAANQADCgEIAQAAAA==.',
Gr='Grankino:BAABNQAECn85AAQiAAgKPQwAHwAiAQAiAAUK2xAAHwAiAQAUAAgKagh2SgDjAAAGAAEKiAQDbwAeAAAAAA==.Grapenuts:BAAANQAECgMIAwABNQAECgkJTwAdAPQfAA==.Greedisgood:BAAANQADCgMIAwAAAA==.Greenthumbs:BAAANQADCgYIBgAAAA==.',
Gw='Gwaelphypha:BAABNQAECn8gAAIdAAcKghhaQwDuAQAdAAcKghhaQwDuAQABNQAECgkJGgAQAJYdAA==.',
Ha='Hakarii:BAAANQADCgEIAQAAAA==.Halder:BAAANQAECgEIAQAAAA==.Hapkido:BAABNQAECn9DAAMQAAoKHCSIAQCvAwAQAAoKHCSIAQCvAwAmAAIK3RJ+RQB+AAAAAA==.Hauwitzer:BAAANQAECgEIAgAAAA==.Hawk:BAAANQAECgMIBQAAAA==.Hazrek:BAABNQAECn8VAAIXAAcKpgviGwClAQAXAAcKpgviGwClAQAAAA==.',
He='Heartattack:BAAANQAECggIBQAAAA==.Hecate:BAABNQAECn8aAAMVAAcKGQUIHgHtAAAVAAcKrwQIHgHtAAAZAAIKHwacZgApAAAAAA==.Heidnik:BAAANQAECgUIBgAAAA==.Heihei:BAABNQAECn8UAAMOAAoKCA2LJgD4AAAOAAoKbAyLJgD4AAAPAAIKrgp0sAB0AAAAAA==.Heneedsumilk:BAAANQADCgYICgAAAA==.Heretic:BAAANQAECgIIAwAAAA==.Hermanater:BAAANQADCggIDgABNQAECgcILgAZAKIaAA==.',
Hi='Hillboy:BAAANQADCggIDgAAAA==.',
Ho='Holydes:BAAANQAECgQIBQABNQAECgcIIQAMANkDAA==.Holyfrejoles:BAAANQAECggICAAAAA==.Holyground:BAAANQAECgEIAQABNQAECgoKJAALAK4lAA==.Holytrinityy:BAAANQADCgYIBgAAAA==.Holyzack:BAAANQAECgUIBQAAAA==.Hooch:BAABNQAECn8UAAIMAAcKYBM6nwBZAQAMAAcKYBM6nwBZAQAAAA==.',
Hu='Humboldt:BAAANQAECggIBgABNQAECggIDQACAAAAAA==.Huunaron:BAABNQAECn8XAAMVAAoKbwy9qgBjAQAVAAoKbwy9qgBjAQAIAAMKxhKQAAF6AAAAAA==.',
['Hé']='Héx:BAACNQAFFH8pAAMFAAgKeRbuDAARAgAFAAYKlxvuDAARAgAoAAIKPgxaBgChAAA1AAQKfywAAygACgqCH2IIABMCAAUACgryGRqaAEwCACgABwoTIGIIABMCAAAA.',
Id='Idylwilde:BAABNQAECn8oAAIUAAcK/wmpSgDiAAAUAAcK/wmpSgDiAAAAAA==.',
Ie='Ienzo:BAAANQADCgQIBwAAAA==.',
Ih='Iheartoreos:BAABNQAECn8gAAIdAAgKYhKJUQCuAQAdAAgKYhKJUQCuAQAAAA==.',
Il='Ilovefuta:BAAANQAECgUICQAAAA==.Iloveoreos:BAAANQADCgYIBgAAAA==.',
In='Instakill:BAAANQADCgQIBAAAAA==.Intent:BAAANQAECgEIAQAAAA==.Invictae:BAABNQAECn8aAAQRAAkKPBNwZACaAQARAAkKPBNwZACaAQATAAMKRAkLXACVAAASAAEK1ALaMAAiAAAAAA==.',
Io='Iobo:BAACNQAFFH8SAAMkAAgKlRiYAwAdAgAkAAcKBByYAwAdAgAJAAIKbAdhGABPAAA1AAQKfygAAyQACgoCJMcGAGUDACQACgoCJMcGAGUDAAkAAgpEHuhYAKsAAAAA.',
Ir='Irk:BAABNQAECn8gAAIPAAgK9xVuSwC4AQAPAAgK9xVuSwC4AQAAAA==.Ironic:BAAANQADCgYIBgABNQAECgoKQgAPAKshAA==.',
Ja='Jagaerr:BAAANQABCgUICQAAAA==.Jagare:BAAANQAECgEIAQAAAA==.Jarco:BAEANQAECgEIAQABNQAFFAcIDgAEANQWAA==.Jargan:BAAANQADCggIDAABNQAECgoKKwAgAN4KAA==.Jasseca:BAAANQAECgMIBQABNQAECgkJGgAQAJYdAA==.',
Je='Jeandarc:BAAANQADCggICAAAAA==.Jezäbelle:BAAANQAECgYIDgAAAA==.',
Jo='Joesh:BAAANQABCgcIFgAAAA==.',
Jt='Jtetue:BAAANQAECgUICAAAAA==.',
Ka='Kaadra:BAAANQAECgUIBQAAAA==.Kaanon:BAAANQAECgUIBQAAAA==.Kaelkin:BAABNQAECn8tAAQRAAoKQxQJUAA0AgARAAoKQxQJUAA0AgATAAUKQw0TPgClAAASAAIK6gbDIgBRAAAAAA==.Kaellar:BAAANQADCgMIAwABNQAECgoKLQARAEMUAA==.Kaelun:BAAANQAECgIIBAABNQAECgoKLQARAEMUAA==.Kaelundrus:BAABNQAECn8YAAMWAAoKBRGMfgCoAQAWAAYKShmMfgCoAQAaAAgKAhS4VwCeAQABNQAECgoKLQARAEMUAA==.Kainis:BAABNQAECn8XAAINAAUKXgMXPwCUAAANAAUKXgMXPwCUAAAAAA==.Kamonorin:BAAANQABCgIIAgAAAA==.Kaotika:BAAANQAECgcIDAAAAA==.Karmus:BAAANQADCgUJCAAAAA==.',
Ke='Keadin:BAAANQADCgcIEQAAAA==.Keilas:BAABNQAECn8iAAIiAAcKXhwHEgDfAQAiAAcKXhwHEgDfAQAAAA==.Kerron:BAAANQAECggIAQAAAA==.Keylala:BAABNQAECn8dAAIhAAcKagoUDwDRAAAhAAcKagoUDwDRAAAAAA==.',
Ki='Kickenmage:BAAANQADCgQIBAABNQAECgYIGwAMAKYGAA==.Kickentail:BAABNQAECn8bAAIMAAYKpgY13wBCAQAMAAYKpgY13wBCAQAAAA==.Kiegh:BAAANQADCgcIBwAAAA==.Kior:BAAANQAECgEIAQAAAA==.Kirisham:BAAANQADCgMIAwAAAA==.Kiriwar:BAACNQAFFH8HAAIYAAQKCRfALQCSAAAYAAQKCRfALQCSAAA1AAQKfzsAAhgACgp2IikiADADABgACgp2IikiADADAAAA.Kirlia:BAABNQAECn8yAAIhAAgKww2dFQDAAQAhAAgKww2dFQDAAQAAAA==.',
Kl='Klymax:BAAANQAECgcIDAAAAA==.',
Ko='Koretha:BAAANQAECgQIDgABNQAFFAcIFwALADYYAA==.Korvano:BAAANQAECgEIAQAAAA==.Kowkowkachoo:BAAANQAECgYIEQAAAA==.',
Kr='Krellis:BAAANQAECgEIAQAAAA==.Krisp:BAABNQAECn8vAAMFAAkKtCK7GAByAwAFAAkKtCK7GAByAwAoAAEKrSPWNABnAAAAAA==.Krispies:BAAANQAECgEIAQABNQAECgkJTwAdAPQfAA==.Krobelus:BAABNQAECn8qAAIVAAoKUQdt3gBeAQAVAAoKUQdt3gBeAQAAAA==.Kruggs:BAAANQADCgYIBgAAAA==.',
Ks='Ksharp:BAAANQADCgYIBgABNQAECgcIDQACAAAAAA==.',
Kv='Kvedadormu:BAAANQADCgYIEQAAAA==.Kvedeitrormr:BAAANQAECgEIAwAAAA==.Kvedfróðleik:BAAANQABCgEIAQAAAA==.Kvedærilaz:BAAANQADCgEIAQAAAA==.',
Ky='Kylearean:BAAANQAECgMIBQAAAA==.Kyran:BAAANQAECgIIAgAAAA==.',
['Kè']='Kèrónos:BAAANQAECgUIDAAAAA==.',
['Kì']='Kìllstheweak:BAABNQAECn8rAAMpAAoKfAknTACIAQApAAoKfAknTACIAQAdAAIKTAjcggBbAAAAAA==.',
La='Ladrone:BAAANQABCgEIAQAAAA==.Laeythe:BAEANQAECgQIBgABNQAFFAIIBgARAI0mAA==.Lannah:BAAANQADCgYIDgAAAA==.Lash:BAAANQAECgUIDAAAAA==.',
Lc='Lclc:BAAANQAECgYICgAAAA==.',
Le='Leafeon:BAACNQAFFH8JAAILAAcKlQsBCAB1AQALAAcKlQsBCAB1AQA1AAQKfyIAAgsACgpaJFcEAIADAAsACgpaJFcEAIADAAE1AAUUBwgQABoAORoA.Lebrin:BAABNQAECn8WAAIaAAUKZhqirQAVAQAaAAUKZhqirQAVAQAAAA==.Legaia:BAABNQAECn8xAAIYAAkKox80HgA/AwAYAAkKox80HgA/AwAAAA==.Legendknewl:BAAANQAECgQIBAAAAA==.Legendoflink:BAAANQAECgUIBgAAAA==.Lelana:BAAANQADCgcIBwAAAA==.Leliel:BAAANQAECgEIAQABNQAECgoKMgAIAM0aAA==.Lennyzamwam:BAAANQAECgQIBwAAAA==.Lesindre:BAAANQAECgYIDQABNQAECggIAgACAAAAAA==.Letaria:BAAANQADCgYIBgAAAA==.Lexapro:BAAANQAECgcIEAABNQABCgcIBwACAAAAAA==.',
Li='Lianissa:BAAANQAECgEIAwAAAA==.Lillinna:BAAANQAECgcIEgAAAA==.Lipidot:BAAANQAECgIIBAAAAA==.Lisea:BAAANQAECgIIAgAAAA==.Lithlina:BAAANQADCgYIBgAAAA==.',
Lo='Loamein:BAAANQAECgcIDQAAAA==.Lockrocks:BAABNQAECn8aAAIBAAoKkhCyVgC8AQABAAoKkhCyVgC8AQAAAA==.Lockycharmz:BAAANQAECggICwABNQAECgkJTwAdAPQfAA==.Lorcán:BAAANQADCgcIEQAAAA==.Lorithan:BAAANQADCgIIAgAAAA==.Lormazlezrax:BAABNQAECn8aAAIaAAkKkhmhRQBLAgAaAAkKkhmhRQBLAgAAAA==.',
Lu='Lucernyx:BAAANQAECgIIAwABNQAECgEIBAACAAAAAA==.Luckystars:BAAANQADCgQIBAAAAA==.Luis:BAAANQADCgQIBAAAAA==.Luminara:BAAANQADCgYIBgAAAA==.Lunaera:BAABNQAECn8aAAIMAAkKwxBycADEAQAMAAkKwxBycADEAQAAAA==.Lunajoy:BAAANQAECgIIAQAAAA==.Lune:BAAANQADCgcIBwABNQAECggIDQACAAAAAA==.Lunella:BAAANQAECgIIBAABNQAECggIDQACAAAAAA==.Lunellia:BAAANQAECggIDQAAAA==.Lunethira:BAAANQAECgMIBQABNQAECggIDQACAAAAAA==.Lunevra:BAAANQABCgcIBwABNQAECggIDQACAAAAAA==.Lupi:BAAANQADCggIDwAAAA==.Lurkaburger:BAABNQAECn8ZAAIYAAkKthawZwBZAgAYAAkKthawZwBZAgAAAA==.',
Ly='Lythindra:BAAANQADCgQIBAAAAA==.',
Ma='Madhatter:BAABNQAECn8YAAMpAAUKFwWndwDFAAApAAUK7wSndwDFAAAdAAEK+gRfqQAjAAAAAA==.Mageistmage:BAACNQAFFH8SAAMFAAcKUBUcHgCRAQAFAAYKXhUcHgCRAQAoAAEKGRVoDgBTAAA1AAQKfzMAAwUACgrHIw0lAKACAAUACgrHIw0lAKACACgAAQqZHP8xAFYAAAAA.Magori:BAAANQADCgYIBgAAAA==.Majarl:BAAANQAECgYIEgAAAA==.Maki:BAAANQADCgEIAQABNQAECgkJKwAIAKgeAA==.Malegar:BAAANQADCggIFgAAAA==.Malificent:BAAANQAECgQICAAAAA==.Mammajamma:BAABNQAECn8oAAIUAAkKYRZENgA5AgAUAAkKYRZENgA5AgAAAA==.Marsvolta:BAAANQAECgQICAAAAA==.Maruxus:BAABNQAECn9GAAIOAAoKTBf1CwABAgAOAAoKTBf1CwABAgAAAA==.Marwen:BAAANQAECgEIAQAAAA==.Maulsin:BAAANQADCgUIBQAAAA==.Mavanthia:BAABNQAECn8uAAMYAAkK/hKvbQCiAQAYAAkK/hKvbQCiAQAbAAEK0hIWQgA3AAAAAA==.Mayyonnaise:BAAANQAECgIIAQAAAA==.',
Mc='Mcdeathy:BAAANQAECgYIEgAAAA==.Mclardragos:BAABNQAECn8uAAMjAAoK0CI4BQBYAwAjAAoK0CI4BQBYAwAfAAEKAAB2PgAvAAAAAA==.',
Me='Meadõw:BAAANQADCgUIBQAAAA==.Meatshield:BAAANQADCgcIDAAAAA==.Mecharoni:BAABNQAECn9CAAMPAAoKqyGlDACqAgAPAAkK+h+lDACqAgAOAAcKwSA2IgB0AgAAAA==.Medreaux:BAAANQAECggIAgABNQAECggIAgACAAAAAA==.Meganaturexl:BAAANQAECgEIAQAAAA==.Megapallyxl:BAAANQAECgEIAwAAAA==.Megashamxl:BAAANQAECgIIAgAAAA==.Mendication:BAAANQAECgcIEwAAAA==.Meretrixee:BAAANQADCgIIAgABNQAECgoKUAARAH8YAA==.Meteion:BAABNQAECn8bAAMBAAcKNhqBagCEAQABAAcKNhqBagCEAQAhAAEKAACYeAA1AAABNQAECggIAgACAAAAAA==.',
Mi='Miacyn:BAAANQAECgYIEAAAAA==.Midnitte:BAAANQAECgEIAQAAAA==.Miladybast:BAABNQAECn8gAAIoAAcKpwYSHAAPAQAoAAcKpwYSHAAPAQAAAA==.Miniwheet:BAAANQAECgYICAABNQAECgkJTwAdAPQfAA==.Minke:BAAANQADCggIHwAAAA==.Mirra:BAABNQAECn8gAAIMAAoKtRDGaADYAQAMAAoKtRDGaADYAQAAAA==.Mirrielle:BAAANQABCgcIBwAAAA==.Missdorei:BAAANQADCgUIBQAAAA==.',
Mo='Molai:BAAANQAECggICAAAAA==.Mommades:BAAANQADCgYIBgABNQAECgcIIQAMANkDAA==.Momsrymommy:BAABNQAECn8bAAIVAAYKtxJrwgCXAQAVAAYKtxJrwgCXAQAAAA==.Montavian:BAAANQAECgMIAwABNQAECgIIBQACAAAAAA==.Moodrian:BAAANQADCggICQABNQAECgoKKAAjAEoQAA==.Moonaurora:BAAANQABCgMIAwAAAA==.Moontater:BAAANQADCgYIBgAAAA==.Mordekaiser:BAAANQADCggICAAAAA==.Morgul:BAAANQAECgQIDQAAAA==.Morionso:BAABNQAECn8uAAIZAAcKoholIQDbAQAZAAcKoholIQDbAQAAAA==.Morphyrinsjr:BAAANQAECgcICQABNQAECggIIwAMAIgOAA==.Mortarion:BAABNQAECn87AAQeAAoKchdvQgASAgAeAAcK5RtvQgASAgApAAkKMhHWQwC0AQAdAAIKPAm0gQBdAAAAAA==.Morwenspring:BAAANQADCgMIAwAAAA==.',
Ms='Mssrbubbles:BAAANQABCggIFQAAAA==.',
Mu='Murdiûs:BAABNQAECn9FAAMmAAoK7B0+EgDLAgAmAAoK7B0+EgDLAgAnAAoKdxiKCQCmAgAAAA==.',
My='Mythbruh:BAEBNQAECn8fAAMeAAcKkiGUSwDmAQAeAAcKhiCUSwDmAQApAAcKfho2PADdAQAAAA==.',
Na='Nachokru:BAAANQABCgEIAgAAAA==.Nahla:BAAANQAECgIIAgAAAA==.Namrevlis:BAAANQADCgIIAgABNQAECgkJHgATAPEPAA==.Narl:BAAANQAECgUIDAAAAA==.Nayrditation:BAAANQAECgcIDgAAAA==.Nayrlock:BAAANQAECgcIDAABNQAECgcIDgACAAAAAA==.',
Nc='Nctee:BAAANQAECgUIDgAAAA==.',
Ne='Nearn:BAAANQAECgIIAgAAAA==.Necropally:BAAANQADCgcIDQAAAA==.Nevermore:BAAANQAECgYIBgAAAA==.',
Ni='Nightsmoke:BAAANQAECgMJBgAAAA==.Nilious:BAAANQADCgIIAgAAAA==.',
No='Nolabull:BAAANQADCgQIBAAAAA==.Nonattarius:BAABNQAECn8cAAIMAAgK0AeGyQAEAQAMAAgK0AeGyQAEAQAAAA==.Noraelara:BAAANQAECggIAgAAAA==.Norezfou:BAABNQAECn89AAMRAAoK5xa1PwBsAgARAAoK5xa1PwBsAgATAAgK6RZvJAANAgAAAA==.Norran:BAAANQADCgMIAwAAAA==.Notalice:BAAANQAECgIIAgABNQAECgkJGwABAIgTAA==.Nottartar:BAAANQAECgIJAgAAAA==.',
Nu='Nuker:BAAANQADCgYIEgAAAA==.Nurobi:BAABNQAECn89AAIUAAoKMhKFJADEAQAUAAoKMhKFJADEAQAAAA==.',
Oa='Oaksong:BAAANQADCgQIBAAAAA==.',
Od='Odanobunaga:BAACNQAFFH8HAAIYAAMKLQjAKQByAAAYAAMKLQjAKQByAAA1AAQKfy8AAhgACgoGGXhVAIoCABgACgoGGXhVAIoCAAAA.Odyn:BAABNQAECn8aAAIVAAcKrA900gAeAQAVAAcKrA900gAeAQAAAA==.',
Oe='Oerrael:BAAANQADCgcIEAAAAA==.',
Or='Oridk:BAABNQAECn89AAIeAAoKZR1wEgBWAgAeAAoKZR1wEgBWAgABNQAFFAYIDgAMAEscAA==.Oripal:BAAANQAECgIIAgABNQAFFAYIDgAMAEscAA==.Oríon:BAACNQAFFH8OAAMMAAYKSxyABwBfAQAMAAUKSxyABwBfAQAgAAIK7wudAgBOAAA1AAQKfzQABCAACgoJI8kCAP0CACAACQpsHskCAP0CAA0ABgrwFSs7AHgBAAwABgqBIv+UAG8BAAAA.',
Ou='Outofrange:BAAANQAECggICAAAAA==.',
Pa='Pangjang:BAAANQAECgUIDwAAAA==.Pankratease:BAAANQAECgcIDAAAAA==.Pankratoes:BAAANQAECgIIAgABNQAECgcIDAACAAAAAA==.Pankratos:BAAANQADCgUIBQABNQAECgcIDAACAAAAAA==.Papahess:BAABNQAECn8nAAMUAAkK0RNCRQDbAQAUAAkK0RNCRQDbAQAGAAMKyQzSSQCFAAAAAA==.Paradias:BAABNQAECn8aAAIPAAkKMRSnEwBNAgAPAAkKMRSnEwBNAgAAAA==.Pastaladan:BAAANQADCgQIBAAAAA==.Pastor:BAAANQAECgUICgAAAA==.Paxxul:BAAANQADCggICwAAAA==.',
Pe='Peppersham:BAABNQAECn8iAAMWAAkK0hJKQwCvAQAWAAkK0hJKQwCvAQAaAAYKoQvNswAHAQAAAA==.Petespally:BAABNQAECn8zAAMIAAkKHSRdBwCdAwAIAAkKHSRdBwCdAwAZAAEKAACTbgA0AAAAAA==.',
Pf='Pfftpfft:BAAANQAECggIDAAAAA==.',
Ph='Pha:BAABNQAECn8gAAIFAAoKrRgibwCfAgAFAAoKrRgibwCfAgAAAA==.Phatdanny:BAAANQAECggIEAAAAA==.Phonycheese:BAABNQAECn8wAAMVAAoK5BRpeQA5AgAVAAkKfRZpeQA5AgAIAAQK0ggvuwCSAAAAAA==.Phur:BAAANQAECgMIAwAAAA==.',
Pi='Pixen:BAABNQAECn9nAAMBAAoK2hwvHwCLAgABAAoK2hwvHwCLAgADAAEKAAADMQAzAAAAAA==.',
Po='Pocalypse:BAAANQAECgQIBwAAAA==.Ponkeyfists:BAACNQAFFH8IAAImAAQK5BqeCQDOAAAmAAQK5BqeCQDOAAA1AAQKfywAAiYACgp6I/0IAEEDACYACgp6I/0IAEEDAAAA.Portstar:BAABNQAECn81AAIFAAoK0wt01gDaAQAFAAoK0wt01gDaAQAAAA==.Powderhorn:BAAANQADCgUIBQAAAA==.',
Pr='Pravium:BAAANQADCgYIBgABNQAECgkJGgARADwTAA==.Primed:BAABNQAECn87AAIiAAoKzBOADQBDAgAiAAoKzBOADQBDAgAAAA==.Prozac:BAAANQAECgEIAgABNQABCgcIBwACAAAAAA==.',
Pu='Pungla:BAABNQAECn8UAAImAAoKlRXOGgBoAgAmAAoKlRXOGgBoAgAAAA==.',
['Pî']='Pîper:BAAANQADCgQIBAAAAA==.',
Qu='Quelthanos:BAABNQAECn85AAMVAAoKrRZjTgAwAgAVAAoKrRZjTgAwAgAIAAEKfBDGGwE8AAAAAA==.Quesoblanco:BAAANQABCgQIBAAAAA==.',
Ra='Racob:BAAANQAECgMIBAABNQAECgQIBQACAAAAAA==.Radical:BAAANQAECgMICAAAAA==.Ralvick:BAAANQADCgEJAQAAAA==.Ramuun:BAAANQADCgIIAgAAAA==.Randomclown:BAAANQAECgEIAQAAAA==.Rascalfats:BAAANQAECgQIDwABNQAECggIFAAMAGATAA==.Rashii:BAABNQAECn8pAAIRAAkKrxR5VQDPAQARAAkKrxR5VQDPAQAAAA==.Rawor:BAAANQAECgQIBAAAAA==.Raworrior:BAABNQAECn8hAAMYAAgKCA3/wAB7AQAYAAgKCA3/wAB7AQAHAAEKOAhgNQAwAAAAAA==.Razera:BAAANQADCgcIBwAAAA==.',
Re='Reax:BAAANQADCgYIBgAAAA==.Rebaderchi:BAABNQAECn8hAAIkAAkKYhkAGwCAAgAkAAkKYhkAGwCAAgABNQADCgMIAwACAAAAAA==.Reignofpower:BAAANQADCgUIBQAAAA==.Reisswolf:BAAANQAECgMIAwAAAA==.Remoria:BAAANQAECgYIEQAAAA==.Renildan:BAAANQAECgYIDwAAAA==.Renmazuo:BAAANQADCgMIAwAAAA==.Rezputan:BAAANQAECggIEgAAAA==.',
Rh='Rhavin:BAAANQAECgYICgAAAA==.Rhodon:BAABNQAECn8UAAMpAAkKPQxkTQBJAQApAAgKDApkTQBJAQAdAAIK7w+mcgB9AAAAAA==.Rhohorn:BAAANQAECggIDAAAAA==.Rholand:BAABNQAECn83AAMYAAoKTRxKVACOAgAYAAoKphtKVACOAgAbAAEKxyAjNABgAAAAAA==.Rhovid:BAAANQAECgQIBAAAAA==.',
Ri='Rivalt:BAAANQAECgEIAwAAAA==.Riverra:BAAANQADCgcICgAAAA==.Rizzoy:BAABNQAECn8kAAMHAAcKXRarFABVAQAHAAUKaRmrFABVAQAYAAYKzBKA4QAmAQAAAA==.',
Ro='Rollo:BAAANQAECgQICAAAAA==.Roottender:BAAANQADCgcICwAAAA==.Rostain:BAAANQAECgEIAQAAAA==.Rovyr:BAABNQAECn8uAAMjAAoKgx4MFABtAgAjAAoKgx4MFABtAgAlAAEKAAC4JwAlAAAAAA==.Rowinna:BAAANQADCgUIBQAAAA==.',
Ru='Ruckabis:BAABNQAECn8cAAIaAAkKeBXCRQBKAgAaAAkKeBXCRQBKAgAAAA==.',
Ry='Rybearkin:BAAANQADCgMIAwAAAA==.Rykker:BAAANQAECgEIAQAAAA==.Rylos:BAABNQAECn8jAAIeAAgKMQpAMABXAQAeAAgKMQpAMABXAQAAAA==.Ryshadow:BAAANQADCgYICwAAAA==.Ryumi:BAABNQAECn8hAAIFAAoKDw01/QCTAQAFAAoKDw01/QCTAQAAAA==.',
Sa='Saansula:BAAANQADCgEIAQAAAA==.Sacmaster:BAAANQADCggIDAABNQAECgkJJwAhAHQWAA==.Saintagur:BAAANQABCgMIAQAAAA==.Saitamå:BAABNQAECn8kAAInAAkKxheBFgAUAgAnAAkKxheBFgAUAgAAAA==.Samanaras:BAABNQAECn8rAAMbAAkKxxCLHgDzAAAYAAgKrg6EowDEAQAbAAcKOBKLHgDzAAAAAA==.Sangwyn:BAAANQAECgYIDAABNQAECgkJKwAIAKgeAA==.Santiago:BAAANQAECgIIAgAAAA==.Saratoga:BAAANQAECgQICwAAAA==.Sarkana:BAABNQAECn8yAAMIAAoKzRoMIwDgAgAIAAoKzRoMIwDgAgAVAAEKSQZSngEkAAAAAA==.Saxonn:BAAANQAECgIIAgAAAA==.Saydis:BAABNQAECn8ZAAIMAAcKuwfd7gAkAQAMAAcKuwfd7gAkAQAAAA==.',
Sc='Scarletthot:BAAANQAECgEIBQAAAA==.Scatterbrain:BAAANQADCgcIEgAAAA==.Schuftt:BAAANQAECgEIAQAAAA==.Scryy:BAAANQAECgEIAQABNQAECgQIBQACAAAAAA==.',
Se='Sebattan:BAAANQADCgYIBwAAAA==.Seleinai:BAAANQADCgMIAwABNQAECgoKOQASAFkcAA==.Seleine:BAABNQAECn85AAISAAoKWRwlAgAJAwASAAoKWRwlAgAJAwAAAA==.Seloric:BAABNQAECn8qAAIdAAkKQR/mKwBpAgAdAAkKQR/mKwBpAgAAAA==.Serendrin:BAABNQAECn9MAAIOAAoKuCGqAwD6AgAOAAoKuCGqAwD6AgAAAA==.Sevalandre:BAAANQAECgIIAgABNQAECgkJGgAQAJYdAA==.',
Sh='Shaaman:BAAANQADCgYIBgAAAA==.Shadowskyz:BAAANQAECgQIEAABNQAFFAUICQAWAIoLAA==.Shaggimaggi:BAABNQAECn8gAAMdAAkKdBPlLACRAQAdAAkKdBPlLACRAQAeAAEKZgG8kgAcAAAAAA==.Shalaara:BAAANQAECgEIAgAAAA==.Shamanis:BAAANQADCgQIBAAAAA==.Shamcheese:BAAANQAECgQIBAABNQAECgoKMAAVAOQUAA==.Shamcow:BAAANQADCgcICQAAAA==.Shamina:BAACNQAFFH8JAAIWAAUKigscCwARAQAWAAUKigscCwARAQA1AAQKf1AAAxYACgo4HmUWAKoCABYACgo4HmUWAKoCABcAAQoYGmgwAEwAAAAA.Shammlet:BAAANQABCggIEwAAAA==.Shamorex:BAABNQAECn8nAAIWAAkKpBmaTQBAAgAWAAkKpBmaTQBAAgAAAA==.Shatter:BAABNQAECn8YAAIVAAgK/x5BXQCBAgAVAAgK/x5BXQCBAgAAAA==.Shax:BAAANQADCggICAABNQAECgkJLwAFALQiAA==.Shiftit:BAAANQAECgMIBQABNQAFFAIIBgAFAGkMAA==.Shlevin:BAAANQADCgcIDAAAAA==.Shockyoface:BAAANQABCgUIBQAAAA==.',
Si='Sideshift:BAAANQAECgQIBAABNQAFFAUICQAWAIoLAA==.Sinara:BAAANQAECgUICQAAAA==.',
Sk='Skaarr:BAAANQADCgQIBQAAAA==.Skibidiheals:BAAANQAECgEIAQAAAA==.Skybear:BAAANQABCgYICQAAAA==.',
Sl='Slash:BAAANQADCgYIBgAAAA==.Slayn:BAABNQAECn9GAAIoAAoKcBqbBgBIAgAoAAoKcBqbBgBIAgAAAA==.Sleebo:BAAANQAECgUIDgAAAA==.Sleinx:BAAANQADCggIDQABNQAFFAUIEAAWADMOAA==.Slyrak:BAABNQAECn8aAAMfAAoKoxQ/CQDUAQAfAAkK2BY/CQDUAQAjAAMKJworMABnAAAAAA==.',
Sm='Smitus:BAAANQAECgEIAgAAAA==.',
Sn='Snackie:BAABNQAECn8mAAIaAAkKhh2ZLwBMAgAaAAkKhh2ZLwBMAgAAAA==.Snooty:BAAANQAECggJAgAAAA==.Snotpig:BAAANQAECggIBwAAAA==.',
So='Sokar:BAAANQAECggIDQAAAA==.Sokolovva:BAAANQADCgcIDAAAAA==.Souled:BAAANQADCgUIBQABNQAECgkJMgAFAO4SAA==.Sourpunchkid:BAAANQAECgYIDAAAAA==.',
Sp='Spacedemon:BAABNQAECn8dAAIkAAkKtg3uNQCUAQAkAAkKtg3uNQCUAQAAAA==.Sparroh:BAAANQADCgYIBgAAAA==.Spikedriver:BAABNQAECn8oAAIMAAoKHQ56agA+AgAMAAoKHQ56agA+AgAAAA==.Spiky:BAAANQADCgMIAwAAAA==.',
St='Stariane:BAABNQAECn8vAAIJAAoK9hpjGQDQAgAJAAoK9hpjGQDQAgAAAA==.Starie:BAAANQAECgIIAgAAAA==.Startaker:BAAANQADCggIDwAAAA==.Startaster:BAAANQADCgcIBwAAAA==.Starvoid:BAAANQAECgYICAAAAA==.Stateofgrace:BAAANQAECggICwABNQAECgoKJAALAK4lAA==.Steeldk:BAAANQAECgIJAgAAAA==.Stella:BAAANQAECgQICAAAAA==.Stonyfist:BAAANQADCgEIAQAAAA==.Stonyy:BAAANQAECgIIAwAAAA==.Stubhorn:BAAANQADCgUICAAAAA==.',
Su='Summers:BAAANQADCgcIEQAAAA==.Sumonmyface:BAABNQAECn8nAAMhAAkKdBbPIgBbAQAhAAQKEh7PIgBbAQABAAYKvhBZxQBAAQAAAA==.Superillbomb:BAAANQADCgYJCQAAAA==.Superold:BAABNQAECn8VAAIMAAgKzAyxdgC1AQAMAAgKzAyxdgC1AQAAAA==.',
Sw='Swamprot:BAABNQAECn8hAAIeAAgKhh2lMwBcAgAeAAgKhh2lMwBcAgAAAA==.',
Sy='Sydoom:BAAANQABCgEIAQAAAA==.Sylara:BAAANQAECgIIAQAAAA==.Syletage:BAAANQADCgYICwAAAA==.Syral:BAAANQADCgcIEQAAAA==.Syrel:BAAANQAECgEICAAAAA==.',
Ta='Taelinn:BAAANQAECgEIAQAAAA==.Tailfordays:BAAANQADCgIIAgAAAA==.Tanky:BAAANQADCgIIAgAAAA==.Tantor:BAAANQADCgEIAQAAAA==.Tarragon:BAAANQADCgcIBwAAAA==.Taurnator:BAAANQAECgIIAgAAAA==.Taylorswift:BAABNQAECn8kAAMLAAoKriU3HAAIAgALAAcKdyU3HAAIAgAiAAQKZB3hGgBTAQAAAA==.',
Tc='Tchiratha:BAABNQAECn8XAAMaAAgKfg8TgwAUAQAaAAcKYw4TgwAUAQAWAAYKgwNwnwCzAAABNQAECgoKOQAVAK0WAA==.',
Te='Tednougat:BAAANQADCgYIBgAAAA==.Telain:BAABNQAECn8tAAQIAAoKeQocngBKAQAIAAkKBQgcngBKAQAVAAgKGQtd+gAqAQAZAAIKSQz9XQBjAAAAAA==.Tensuki:BAAANQADCgQIBAAAAA==.Tesh:BAAANQADCgQIBgAAAA==.',
Th='Thaelynn:BAAANQADCggIHAAAAA==.Thakilla:BAABNQAECn9RAAIUAAoKBhYNGgAnAgAUAAoKBhYNGgAnAgAAAA==.Theolodin:BAAANQAECgIIAgAAAA==.Thordrik:BAAANQAECgIIAQAAAA==.Thorix:BAAANQAECgYICgAAAA==.Thornhub:BAAANQAECggIDQABNQAFFAoKPwAhAJUiAA==.Thrust:BAAANQAECgUIDgABNQABCgcIBwACAAAAAA==.Thrustwood:BAAANQADCgMIAwAAAA==.',
Ti='Tiammanth:BAAANQAECgUIDAAAAA==.Tigerbrew:BAAANQADCgUIBQAAAA==.Tigerburn:BAAANQADCgQIBAAAAA==.Tigerdawn:BAAANQADCgYIBgAAAA==.Tigerluna:BAAANQADCgQIBAAAAA==.Tikya:BAAANQADCgYIBwAAAA==.Tilsit:BAAANQAECggIDQAAAA==.Timberreaper:BAAANQADCgcICAAAAA==.Tinyz:BAAANQAECgQICQAAAA==.Tisisme:BAAANQADCgUIBQAAAA==.',
To='Tonythetiger:BAAANQAECgYICgABNQAECgkJTwAdAPQfAA==.',
Tr='Train:BAAANQADCgcIBwAAAA==.Trampadin:BAAANQABCgQIBAAAAA==.Trei:BAAANQADCgIIAgABNQAECgcIDgACAAAAAA==.Trexlot:BAAANQADCgIIAgAAAA==.Trinjal:BAAANQAECgEIAgAAAA==.',
Tu='Tubbylumpkin:BAAANQADCggIDAAAAA==.Tummi:BAAANQADCgcIEAAAAA==.Tumnus:BAAANQAECgEIAgAAAA==.',
Ty='Tyjan:BAAANQAECgIIAwAAAA==.',
['Tâ']='Tâfa:BAAANQADCggICAAAAA==.',
Uh='Uhtred:BAAANQADCgYIBwAAAA==.',
Ul='Ulti:BAABNQAECn8rAAMIAAkKqB4BNACUAgAIAAkKqB4BNACUAgAZAAIKfQYFbAAgAAAAAA==.',
Un='Unholydevil:BAAANQAECgIIAgAAAA==.Unholyheart:BAAANQAECgIIAgAAAA==.',
Va='Varthios:BAAANQAECgEIAwAAAA==.Varyusha:BAAANQAECgEIAQAAAA==.',
Ve='Velantra:BAAANQAECggIEQAAAA==.Venari:BAABNQAECn8iAAIgAAkKihfxAwBAAgAgAAkKihfxAwBAAgAAAA==.',
Vi='Vilelyn:BAABNQAECn8lAAMnAAoKlBexCgCDAgAnAAoKlBexCgCDAgAmAAUK0wgKQgCSAAABNQADCgEIAQACAAAAAA==.Viloria:BAABNQAECn8lAAIGAAgKthaoHgCqAQAGAAgKthaoHgCqAQAAAA==.Vincent:BAAANQADCgQIBAAAAA==.Viridia:BAAANQADCggICAAAAA==.Virrard:BAABNQAECn8kAAIMAAoK7BdOVAB0AgAMAAoK7BdOVAB0AgAAAA==.',
Vl='Vladimor:BAABNQAECn8bAAMBAAkKiBPPYwCXAQABAAgK8hXPYwCXAQADAAEKDAVJLgAoAAAAAA==.Vladimyrr:BAAANQADCgUJCAAAAA==.',
Vo='Voslaarum:BAAANQADCgEIAQABNQAECgYIEgACAAAAAA==.Vozrezz:BAABNQAECn8ZAAMnAAcKRh7REgDCAQAnAAcKRh7REgDCAQAmAAUKlhTcUwCgAAAAAA==.',
Vu='Vualake:BAAANQADCgQIBQAAAA==.',
['Vë']='Vëda:BAABNQAECn89AAIRAAoKPiDWGwADAwARAAoKPiDWGwADAwAAAA==.',
Wa='Waffle:BAAANQAECgIIAwABNQAFFAUIBQAXAPUSAA==.Warage:BAAANQAECgEIAQAAAA==.Warske:BAAANQAECggIDAAAAA==.',
We='Wellembrowed:BAAANQAECgEIAgAAAA==.',
Wh='Wheaties:BAAANQAECgYICgABNQAECgkJTwAdAPQfAA==.Whizzie:BAABNQAECn8yAAIFAAkK7hJ4nwBCAgAFAAkK7hJ4nwBCAgAAAA==.Whizzlecrank:BAABNQAECn81AAIFAAkKTBR8pQA2AgAFAAkKTBR8pQA2AgAAAA==.',
Wi='Wicker:BAABNQAECn8rAAMUAAkKtRW9QwDlAQAUAAcK9xO9QwDlAQALAAUKHxJhRgD+AAAAAA==.Willpharaoh:BAAANQADCgUICgAAAA==.Wiçker:BAAANQADCgIIAgABNQAECgkJKwAUALUVAA==.',
Wo='Wolford:BAAANQADCgYIBgAAAA==.',
Wr='Wras:BAABNQAECn8iAAIdAAgKAROUNwBYAQAdAAgKAROUNwBYAQAAAA==.Wrectt:BAAANQAECgUIEQABNQAECgcIDQACAAAAAA==.',
['Wò']='Wòbbles:BAAANQAECgQIEAABNQAECggIFAAMAGATAA==.',
Xa='Xandrah:BAAANQADCgUJBQAAAA==.Xandrel:BAABNQAECn8sAAIVAAkK4Q7MtABRAQAVAAkK4Q7MtABRAQAAAA==.',
Xe='Xed:BAABNQAECn88AAIWAAcKmRodSwBKAgAWAAcKmRodSwBKAgAAAA==.Xenogears:BAABNQAECn8qAAINAAkKyhq2HgBbAgANAAkKyhq2HgBbAgAAAA==.',
Xi='Xiansai:BAABNQAECn8xAAITAAoKlBLbIAAxAgATAAoKlBLbIAAxAgAAAA==.',
Ya='Yappey:BAAANQAECgcICAAAAA==.',
Yi='Yippee:BAABNQAECn8iAAIWAAoKgh79FgClAgAWAAoKgh79FgClAgAAAA==.',
Yo='Youthinasia:BAABNQAECn8XAAMNAAcKLwyCRAA0AQANAAcKLwyCRAA0AQAMAAEKOwWaRwEuAAAAAA==.',
Za='Zakilan:BAAANQADCgUIBQABNQADCgcICQACAAAAAA==.',
Ze='Zerega:BAAANQADCgcIHAABNQAECgoKZQAOAF4SAA==.',
Zh='Zhi:BAAANQAECgUIBgAAAA==.Zhukov:BAAANQADCgYIBgABNQADCggIDwACAAAAAA==.',
Zo='Zombiehippo:BAABNQAECn86AAIFAAoKZBm0VwDRAgAFAAoKZBm0VwDRAgAAAA==.',
['Áu']='Áutarch:BAABNQAECn8VAAIYAAgKMQf53AAyAQAYAAgKMQf53AAyAQAAAA==.',
['Ðe']='Ðemøn:BAAANQADCggIHAAAAA==.',
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
