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

local lookup = {'Unknown-Unknown','Warlock-Affliction','Rogue-Outlaw','Mage-Arcane','Druid-Guardian','Warrior-Fury','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','Monk-Brewmaster','Priest-Holy','Priest-Discipline','Priest-Shadow','Druid-Balance','Paladin-Retribution','Warrior-Arms','Paladin-Protection','Shaman-Restoration','Warrior-Protection','Mage-Fire','DeathKnight-Blood','DeathKnight-Unholy','Evoker-Devastation','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Druid-Feral','Evoker-Preservation','DemonHunter-Devourer','Monk-Windwalker','Monk-Mistweaver','Mage-Frost','Shaman-Enhancement','DeathKnight-Frost','Evoker-Augmentation',}
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abris:BAAANQAECgEIAgABNQAECgcIEQABAAAAAA==.',
Ac='Acekith:BAAANQABCgMIAwABNQAECgQJBgABAAAAAA==.Acense:BAAANQAECgQJBgAAAA==.Acidhunter:BAAANQADCgcIBwAAAA==.Acidlock:BAABNQAECn8WAAICAAgK4xFOCQDvAQACAAgK4xFOCQDvAQAAAA==.Acidpriest:BAAANQAECgYIDgAAAA==.',
Ad='Adacey:BAABNQAECn8YAAIDAAgKGQ4NBQAVAQADAAgKGQ4NBQAVAQAAAA==.Adragon:BAAANQADCgQIBAABNQAECgYIEAABAAAAAA==.Adrenalized:BAAANQADCgMIBAAAAA==.',
Ae='Aendrin:BAAANQAECgEIAQAAAA==.Aesuga:BAAANQADCgYIBgAAAA==.',
Af='Afteraction:BAAANQADCgQIBQAAAA==.',
Ak='Aktras:BAABNQAECn8bAAIEAAYK9hFwxwDvAAAEAAYK9hFwxwDvAAAAAA==.',
Al='Alaunu:BAABNQAECn82AAIFAAoKaBEZGADvAQAFAAoKaBEZGADvAQAAAA==.Aleas:BAAANQADCgQIBAAAAA==.Alexx:BAAANQAECgQICgAAAA==.Alkaid:BAAANQAECgYIDgAAAA==.Alric:BAAANQAECgQIBQAAAA==.',
An='Anari:BAAANQAECgQIBwABNQAECggIDQABAAAAAA==.Anarky:BAABNQAECn8UAAIGAAgKgAG0MAA9AAAGAAgKgAG0MAA9AAAAAA==.Angelcorp:BAAANQAECgMIAwAAAA==.Annebonny:BAAANQAECgUIDAAAAA==.Anthrfinpete:BAAANQAECggICAABNQAECggIKQAHAPMjAA==.',
Ap='Apsalar:BAAANQADCgcJBwAAAA==.',
Ar='Archdemon:BAABNQAECn9bAAMIAAoKASV+AwC6AwAIAAoKsCR+AwC6AwAJAAkKVx9HBABtAgAAAA==.Arienys:BAAANQADCgYICwAAAA==.Ariis:BAAANQADCgUICQAAAA==.Arkh:BAAANQADCgMIAwAAAA==.Arkhanx:BAAANQADCgUJBQAAAA==.Arkhfu:BAAANQAECgIIAgAAAA==.Arleen:BAAANQAECgMIAgAAAA==.Arquen:BAABNQAECn8wAAIHAAoK0yIECgBiAwAHAAoK0yIECgBiAwAAAA==.',
As='Asevenx:BAAANQADCggIEQAAAA==.Ashamane:BAAANQAECgEIAgAAAA==.Asian:BAAANQADCgIIAgAAAA==.Asra:BAAANQAECgYICgAAAA==.Astrov:BAABNQAECn8iAAIIAAoKNhKxNwDzAQAIAAoKNhKxNwDzAQAAAA==.',
At='Atulmags:BAAANQAECgYICQAAAA==.',
Au='Auani:BAABNQAECn85AAIKAAoKPCBEBwBOAwAKAAoKPCBEBwBOAwAAAA==.Aurelily:BAAANQADCgYJDAAAAA==.Ausia:BAAANQAECgUIBwAAAA==.',
Av='Avann:BAAANQADCgIIAgAAAA==.',
Az='Azazyl:BAAANQAECgMIAwAAAA==.Azzeus:BAAANQAECgUICwABNQAECgoKKQALAO8YAA==.Azzfists:BAAANQADCgQIBAABNQAECgoKKQALAO8YAA==.Azzshot:BAABNQAECn8pAAMLAAoK7xiGgAAMAgALAAgKWRmGgAAMAgAMAAoKkgmDOgB8AQAAAA==.',
Ba='Babyrinsjr:BAABNQAECn8iAAILAAcK/Q8MmQA8AQALAAcK/Q8MmQA8AQAAAA==.Badista:BAAANQADCgIIAgAAAA==.Baile:BAAANQAECgIIAQABNQAECgQIAwABAAAAAA==.Balleont:BAABNQAECn8qAAILAAoKehOIWABqAgALAAoKehOIWABqAgAAAA==.Barrada:BAABNQAECn8nAAILAAgK8wbOxwByAQALAAgK8wbOxwByAQAAAA==.',
Be='Beefcakeßody:BAAANQADCgYIBgAAAA==.Berea:BAABNQAECn9dAAMNAAoK0xEtFgBfAQAOAAoK+w40NADsAQANAAgK1AwtFgBfAQAAAA==.',
Bi='Birgi:BAAANQAECggICAAAAA==.',
Bl='Blankdemonic:BAAANQABCgYICAAAAA==.Blankwar:BAAANQADCgUIBQAAAA==.Bleedblue:BAABNQAECn8eAAIOAAgKmAv0JQCXAQAOAAgKmAv0JQCXAQAAAA==.Blitzed:BAAANQADCgIIAgAAAA==.Bloodhaven:BAAANQADCgEIAQAAAA==.',
Bo='Bo:BAABNQAECn85AAILAAoKzRsRJQACAwALAAoKzRsRJQACAwAAAA==.Bobbinrobin:BAAANQAECgcIDQABNQAECgoKJAAPANAUAA==.Borahae:BAAANQAFFAEIAQABNQAFFAIIBQAHAKADAA==.Borden:BAAANQADCgQJBAAAAA==.',
Br='Bradent:BAAANQAECggIEAAAAA==.Breach:BAAANQAECgQIAwAAAA==.Brunnhild:BAAANQAECgIIAgAAAA==.Bryxi:BAABNQAECn8aAAIQAAkKlh0sBABZAgAQAAkKlh0sBABZAgAAAA==.Brünhilde:BAABNQAECn8xAAQRAAoKPxVKWAAZAgARAAoKHRRKWAAZAgASAAQKAxCeFQDRAAATAAEKAABJhwAiAAAAAA==.',
Bs='Bstbll:BAACNQAFFH8XAAIKAAcKNhjIAwABAgAKAAcKNhjIAwABAgA1AAQKfzgAAwoACgreH0wOAJ8CAAoACgreH0wOAJ8CABQAAQp/FTt7ADUAAAAA.',
Bu='Bubbleheals:BAABNQAECn86AAMHAAoKbBHzOAACAgAHAAoKbBHzOAACAgAVAAUK5gOsPAFhAAABNQAFFAUICQAPAIoLAA==.Bundtcake:BAAANQAECggIBwAAAA==.Burningfist:BAAANQAECgQIDQAAAA==.Buttsnacks:BAABNQAECn8mAAIWAAoKUxWIWACCAgAWAAoKUxWIWACCAgAAAA==.',
Ca='Caciocavallo:BAAANQAECggIAQABNQAECggIDQABAAAAAA==.Callistrah:BAAANQAECgUIBwAAAA==.Caltaa:BAABNQAECn85AAIXAAoK0iLNBQBRAwAXAAoK0iLNBQBRAwAAAA==.Canarah:BAAANQADCgQIBAABNQAECgkJGgAYAJIZAA==.Canverian:BAABNQAECn8iAAIFAAcKuRPFJgAXAQAFAAcKuRPFJgAXAQAAAA==.Captsmash:BAABNQAECn81AAMZAAoKtxzIBgBTAgAZAAoKtxzIBgBTAgAWAAUK9QaJvwDCAAAAAA==.Carmedic:BAAANQADCgIIAgAAAA==.',
Cd='Cdub:BAAANQAECgYIDQAAAA==.',
Ce='Cenarial:BAAANQADCgMIAwAAAA==.',
Ch='Charcuterie:BAAANQAECgQIDQAAAA==.Chasseurfool:BAABNQAECn8hAAILAAkKhwn3egB8AQALAAkKhwn3egB8AQAAAA==.Chat:BAACNQAFFH8PAAIPAAQKGRKnDgDdAAAPAAQKGRKnDgDdAAA1AAQKfzoAAg8ACgqYHC4iADUCAA8ACgqYHC4iADUCAAAA.Chevre:BAABNQAECn8VAAILAAUKphDS8gAcAQALAAUKphDS8gAcAQAAAA==.Chezaro:BAABNQAECn8mAAIVAAgK1A3rlgBeAQAVAAgK1A3rlgBeAQAAAA==.Chickenwing:BAABNQAECn8pAAIaAAoKyR8sAQDcAgAaAAoKyR8sAQDcAgAAAA==.Christano:BAABNQAECn8oAAMVAAoK2x/9LQCAAgAVAAoKbx/9LQCAAgAXAAMKRyD8NgCnAAAAAA==.Christhecold:BAABNQAECn8gAAIWAAgKHxrMbgBGAgAWAAgKHxrMbgBGAgAAAA==.Chrollo:BAAANQAECgUIEQAAAA==.Chuchu:BAAANQADCgMIAwAAAA==.Chumba:BAAANQAECgYIDgAAAA==.',
Ci='Cinnamilk:BAAANQAECggIBwABNQAECgkJSQAbADAcAA==.',
Cl='Clamslamm:BAEANQADCgUIBQABNQAECgcIHwAcAJIhAA==.Cloudcrack:BAECNQAFFH8PAAMYAAUKpw39EgAiAQAYAAUKpw39EgAiAQAPAAMKdAqDHADcAAA1AAQKfzEAAxgACgp+I1wFAKwDABgACQrDI1wFAKwDAA8ACQo2HPksAMkCAAAA.',
Co='Cocotaso:BAAANQABCgIIAgAAAA==.Codemon:BAABNQAECn8rAAIdAAkKDhflCgB+AQAdAAkKDhflCgB+AQAAAA==.Cole:BAAANQADCgUIBQAAAA==.Cosmoline:BAABNQAECn8jAAIeAAoKmhw+BACoAgAeAAoKmhw+BACoAgABNQAECgcIFAAIAGIRAA==.Cotw:BAAANQAECgIIAgABNQAECgYIEAABAAAAAA==.Coverttops:BAABNQAECn8ZAAQfAAgKBApcKQAwAQAfAAcKPQlcKQAwAQACAAQKJApkFQCgAAAgAAIKgQQQNQFPAAAAAA==.',
Cp='Cptcharis:BAAANQADCgEIAQAAAA==.',
Cr='Critmyshorts:BAAANQAECgYICgAAAA==.Critnespears:BAAANQADCgYIBgAAAA==.Crottin:BAAANQAECgQIAwAAAA==.',
Cu='Cubann:BAAANQAECgIIAgAAAA==.',
Cy='Cylrhea:BAAANQAECgUIDwAAAA==.Cynri:BAAANQADCgQIBQABNQAECgIIAgABAAAAAA==.Cyntrill:BAAANQAECgUICQAAAA==.',
Da='Daboulder:BAAANQAECgEIAQAAAA==.Dadderz:BAAANQADCgYIGQAAAA==.Daedean:BAAANQAECgIIAgABNQAECgQIAwABAAAAAA==.Dagnome:BAAANQADCggICAAAAA==.Dahunter:BAAANQAECgIIAgAAAA==.Dajoel:BAAANQAECgIIAgAAAA==.Dalacia:BAABNQAECn8eAAIYAAoKkRVFXgD0AQAYAAoKkRVFXgD0AQAAAA==.Daphera:BAAANQADCgcIDAAAAA==.Darkforceray:BAAANQABCgQIBAAAAA==.Darkhollow:BAAANQADCggIIgAAAA==.Darkhunta:BAAANQADCgQIBAAAAA==.Darknature:BAABNQAECn8jAAIKAAgKhRjiIQAYAgAKAAgKhRjiIQAYAgAAAA==.Darkodin:BAABNQAECn8hAAIcAAgKtgrSOAAKAQAcAAgKtgrSOAAKAQAAAA==.Darkshamy:BAAANQAECgMICAAAAA==.Darksknightt:BAAANQADCgEIAQAAAA==.Darkspriest:BAAANQADCgIIAgAAAA==.Darrad:BAAANQAECgUIBwAAAA==.Datnagadrake:BAACNQAFFH8RAAIWAAYKcRUxCACEAQAWAAYKcRUxCACEAQA1AAQKf08AAxYACgoUI5UXANcCABYACgrfIpUXANcCABkABgrdIAgQACgCAAAA.Dawinchy:BAABNQAECn8uAAMKAAoKaxnLGAB3AgAKAAoKaxnLGAB3AgAhAAYKxg5oGwBMAQAAAA==.',
De='Deadlypsycho:BAAANQAECgEIAQAAAA==.Deathavoider:BAAANQADCggIEAAAAA==.Deathawakens:BAAANQADCgEIAQAAAA==.Deathlyill:BAAANQAECgIJAgAAAA==.Decemberr:BAAANQAECgQICQAAAA==.Dekudin:BAABNQAECn8dAAIXAAgKtBTfIAAzAQAXAAgKtBTfIAAzAQAAAA==.Dellistia:BAAANQADCgcIDAAAAA==.Dennywenny:BAAANQAECgUIDAAAAA==.Deric:BAAANQAECgEIAQAAAA==.Desdamona:BAABNQAECn8cAAILAAcK2QP1zADTAAALAAcK2QP1zADTAAAAAA==.Destrodemon:BAAANQADCggICAAAAA==.Destropally:BAABNQAECn8hAAIVAAkK0w4XqwDJAQAVAAkK0w4XqwDJAQAAAA==.Devorick:BAABNQAECn89AAMgAAoKxBsLKwDYAgAgAAoKxBsLKwDYAgAfAAIKIhBQVwB5AAAAAA==.Deyeraa:BAAANQADCgUIBQAAAA==.',
Di='Diaval:BAAANQAECgQICAAAAA==.Dih:BAAANQADCgYIBgABNQAECgkJJwAfAHQWAA==.Dijarl:BAABNQAECn8uAAILAAkK5CCuEQDrAgALAAkK5CCuEQDrAgAAAA==.Dipndots:BAAANQAECgUICAAAAA==.Dirtyboy:BAAANQADCgIIAgAAAA==.Discórdia:BAAANQAECgMIAwAAAA==.Divineplea:BAAANQADCgcIBwAAAA==.Diyiya:BAABNQAECn8aAAILAAcK+wngqgAYAQALAAcK+wngqgAYAQAAAA==.',
Do='Doggiestylin:BAAANQAECgQIBwAAAA==.Doorki:BAAANQAECggICwAAAA==.Dottey:BAABNQAECn8cAAIfAAkKtBPRCAAQAQAfAAkKtBPRCAAQAQAAAA==.Doubleott:BAAANQAECgEIAQAAAA==.',
Dr='Drael:BAAANQAECgUIBwAAAA==.Draickin:BAABNQAECn8fAAIHAAgKQBauZADqAQAHAAgKQBauZADqAQAAAA==.Drekle:BAABNQAECn8mAAMiAAoKShDcEACzAQAiAAkK/g3cEACzAQAdAAgKiRR2CwBvAQAAAA==.Drelian:BAAANQAECgUICQAAAA==.Drevy:BAABNQAECn8VAAIDAAgK8BZLBgBwAgADAAgK8BZLBgBwAgAAAA==.Drewdox:BAAANQADCgYIDgAAAA==.Drexchan:BAAANQAECgEIAQAAAA==.Drizzlenuts:BAABNQAECn8fAAMYAAoKNhsGEQAKAwAYAAoKNhsGEQAKAwAPAAEK/QHqVgEiAAAAAA==.Drrabbít:BAAANQADCgQIBAAAAA==.Drumira:BAAANQADCgMIAwABNQAECgkJHgATAPEPAA==.Drumk:BAAANQADCgIIAgABNQAECgkJHgATAPEPAA==.Drumma:BAAANQADCggIFQAAAA==.Drummer:BAABNQAECn8eAAQTAAkK8Q/BNAB9AQATAAcKnQzBNAB9AQASAAUKrhSnDwAwAQARAAUKkgUuvADlAAAAAA==.Drumroleplz:BAAANQAECgQIBAABNQAECgkJHgATAPEPAA==.',
Dw='Dw:BAACNQAFFH8FAAIjAAIKqw6wEACNAAAjAAIKqw6wEACNAAA1AAQKfy8AAyMACgpZHFQQACgCACMACgpZHFQQACgCAAgAAwqrD4t2AKAAAAE1AAUUBQgRAAsA8xsA.',
['Dà']='Dàddybear:BAABNQAECn8eAAILAAcKbws5owAnAQALAAcKbws5owAnAQAAAA==.',
Ea='Earthsangel:BAAANQAECgUIBwAAAA==.',
Ec='Echonox:BAAANQAECgcIDgAAAA==.Eclair:BAAANQAECgQICQAAAA==.',
Ed='Edralyia:BAAANQADCgcIDAAAAA==.',
Eg='Egwene:BAAANQADCgQIBAAAAA==.',
Ei='Eilaurosa:BAABNQAECn8WAAINAAgKlgk7RQCyAQANAAgKlgk7RQCyAQAAAA==.Einnarr:BAAANQAECggIDQAAAA==.',
El='Eldrinne:BAABNQAECn8iAAIaAAgKEATwBQANAQAaAAgKEATwBQANAQAAAA==.Eleblast:BAAANQAECgIIAgAAAA==.Elizavoid:BAABNQAECn8hAAQRAAkKKxswQwBfAgARAAkKKxswQwBfAgATAAUKUhCZNgCqAAASAAEKLhf7JABEAAAAAA==.Elizawrath:BAAANQADCgIIAgAAAA==.Elkuco:BAAANQAECgEIAQAAAA==.Elmindreyda:BAABNQAECn8oAAIOAAoKVQ0BUgBtAQAOAAoKVQ0BUgBtAQAAAA==.Elthiss:BAABNQAECn87AAMFAAkK5hmxEABVAgAFAAkK5hmxEABVAgAhAAEKWhUNNgBGAAAAAA==.',
En='Enfer:BAABNQAECn8YAAIIAAgKcQtMLQBqAQAIAAgKcQtMLQBqAQABNQAFFAQIDwAPABkSAA==.Enyfing:BAAANQAECgUIBgAAAA==.',
Er='Erequois:BAAANQADCgEIAQABNQAECgkJGgAQAJYdAA==.Erianthe:BAABNQAECn8mAAIcAAgK8gascwBIAQAcAAgK8gascwBIAQAAAA==.Eriok:BAAANQABCggIDwAAAA==.Erophien:BAAANQADCgMIBAAAAA==.Eroryn:BAAANQAECgUIDAAAAA==.Erovynthalin:BAAANQADCgYIEAAAAA==.Errorwing:BAAANQAFFAEIAQAAAA==.',
Es='Eshera:BAAANQADCgIIAgAAAA==.Esherä:BAAANQAECgEIAQAAAA==.',
Ev='Eversong:BAAANQADCgYIDAAAAA==.',
Ex='Exmar:BAAANQAECggIDAAAAA==.',
Ey='Eyesopen:BAAANQAECgcIDAABNQAECgoKIgAKAK4lAA==.',
Fa='Faewhisker:BAABNQAECn8YAAMkAAkKyw25KQDQAQAkAAkKyw25KQDQAQAlAAQKBQYgOwCZAAAAAA==.Faithfool:BAABNQAECn8mAAIPAAoKbwqSkAB7AQAPAAoKbwqSkAB7AQAAAA==.Falshallnot:BAAANQAECgQIBAABNQAECgoKJgAiAEoQAA==.Fancyfeet:BAAANQAECgUIBQABNQAECgkJGgAOADEUAA==.Fanduelfiend:BAAANQADCgMIAwAAAA==.Fangmonarch:BAAANQADCgUIBQAAAA==.Fashaladd:BAABNQAECn8wAAQUAAkKNRQPPwACAgAUAAkKNRQPPwACAgAFAAEKAAA1WABIAAAKAAEKXxMfZAA5AAABNQAECgoKJgAiAEoQAA==.',
Fe='Fearios:BAABNQAECn9JAAIbAAkKMByfGADoAgAbAAkKMByfGADoAgAAAA==.Felbeast:BAAANQAECgMIBQAAAA==.Felbound:BAAANQADCgUICQAAAA==.Femboy:BAAANQADCggICAAAAA==.Feorar:BAAANQADCgYJBgAAAA==.Feta:BAAANQAECgYICgABNQAECggIDQABAAAAAA==.',
Fi='Fieldtrip:BAABNQAECn8aAAIRAAYKEBtQTQDKAQARAAYKEBtQTQDKAQAAAA==.Fiendfyre:BAAANQADCgUIBQAAAA==.Finneous:BAAANQADCgMIAwAAAA==.Fizzlenuts:BAABNQAECn8ZAAIlAAgK6xUiFgAaAgAlAAgK6xUiFgAaAgABNQAECgoKHwAYADYbAA==.',
Fl='Flaspios:BAAANQADCgcIBwAAAA==.Flightless:BAAANQADCggICgAAAA==.',
Fo='Foxi:BAAANQAECgQJBAAAAA==.',
Fr='Frosttbyte:BAACNQAFFH8GAAIEAAIKaQybMQCJAAAEAAIKaQybMQCJAAA1AAQKfz0AAwQACgqNGVFqAKkCAAQACgoQGVFqAKkCACYAAQqMHgA5AFoAAAAA.Frostytute:BAAANQADCgIIAgAAAA==.',
Fu='Fullmetalass:BAABNQAECn8WAAILAAkKZxYbjQDwAQALAAkKZxYbjQDwAQAAAA==.',
Fy='Fyyre:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëiróx:BAAANQADCgIIAgAAAA==.',
Ga='Galistar:BAABNQAECn8hAAIPAAcKRwxXfADgAAAPAAcKRwxXfADgAAAAAA==.Garglelots:BAAANQAECgcIBwABNQAECgoKJAAPANAUAA==.Garrotxa:BAAANQAECggICwABNQAECggIDQABAAAAAA==.',
Ge='Gevallen:BAAANQAECgcICgAAAA==.',
Gh='Ghavinental:BAABNQAECn8kAAMPAAcKFBFqgQChAQAPAAcKAQ9qgQChAQAnAAcK7wwMHwBvAQAAAA==.',
Gi='Gil:BAABNQAECn8iAAIjAAoKIR6bFADCAgAjAAoKIR6bFADCAgAAAA==.Gilgamesh:BAAANQAECgUICgABNQAECgoKIgAjACEeAA==.',
Gl='Glizzard:BAAANQAECgUIDAABNQAECggIGAAVAP8eAA==.Glocket:BAAANQAECgIICAAAAA==.Gloom:BAAANQAECgYIBgAAAA==.',
Gn='Gnolan:BAABNQAECn8oAAMOAAoKwxoEEgBiAgAOAAoKwxoEEgBiAgANAAUKHROXXgA8AQAAAA==.',
Go='Goatspace:BAABNQAECn8nAAQeAAoK3gpBCAA4AQALAAkK2wfRxQB2AQAeAAYK4ApBCAA4AQAMAAUKDQPLXwCnAAAAAA==.Gomu:BAAANQADCgQIBAAAAA==.Gongagà:BAABNQAECn8kAAIjAAkK/g6jLQDUAQAjAAkK/g6jLQDUAQAAAA==.Goodnoodle:BAAANQAECgEIAgAAAA==.Goodwithabow:BAAANQAECgQICAAAAA==.Goremaster:BAAANQAECgQICgAAAA==.Gothbaddie:BAAANQAECgQIBAABNQAECggIDQABAAAAAA==.Goyum:BAAANQADCgEIAQAAAA==.',
Gr='Grankino:BAABNQAECn8zAAQhAAgKPQwAHwAiAQAhAAUK2xAAHwAiAQAUAAgKAwhiRQDcAAAFAAEKiAQDbwAeAAAAAA==.Grapenuts:BAAANQAECgEIAQABNQAECgkJSQAbADAcAA==.Greedisgood:BAAANQADCgMIAwAAAA==.Greenthumbs:BAAANQADCgYIBgAAAA==.',
Gw='Gwaelphypha:BAABNQAECn8gAAIbAAcKghhaQwDuAQAbAAcKghhaQwDuAQABNQAECgkJGgAQAJYdAA==.',
Ha='Hakarii:BAAANQADCgEIAQAAAA==.Halder:BAAANQAECgEIAQAAAA==.Hapkido:BAABNQAECn8/AAMQAAoKSiOIAQCvAwAQAAoKSiOIAQCvAwAkAAIK3RKNPwCBAAAAAA==.Hawk:BAAANQAECgMIAwAAAA==.Hazrek:BAABNQAECn8VAAInAAcKpgviGwClAQAnAAcKpgviGwClAQAAAA==.',
He='Heartattack:BAAANQAECggIBQAAAA==.Hecate:BAABNQAECn8VAAIVAAcKrwQIHgHtAAAVAAcKrwQIHgHtAAAAAA==.Heidnik:BAAANQAECgUIBQAAAA==.Heihei:BAAANQAECggIEAAAAA==.Heneedsumilk:BAAANQADCgYICgAAAA==.Heretic:BAAANQAECgIIAgAAAA==.Hermanater:BAAANQADCggIDgABNQAECgcIKAAXAKIaAA==.',
Hi='Hillboy:BAAANQADCggIDgAAAA==.',
Ho='Holydes:BAAANQAECgQIBAABNQAECgcIHAALANkDAA==.Holyfrejoles:BAAANQAECggICAAAAA==.Holyground:BAAANQAECgEIAQABNQAECgoKIgAKAK4lAA==.Holytrinityy:BAAANQADCgYIBgAAAA==.Holyzack:BAAANQAECgUIBQAAAA==.Hooch:BAAANQAECggIDwAAAA==.',
Hu='Humboldt:BAAANQAECggIBgABNQAECggIDQABAAAAAA==.Huunaron:BAABNQAECn8VAAMVAAgK7QwU7gBAAQAVAAgK7QwU7gBAAQAHAAMKxhKQAAF6AAAAAA==.',
['Hé']='Héx:BAACNQAFFH8nAAMEAAgK/xLuDAARAgAEAAYKPBnuDAARAgAmAAIKhQagDgBTAAA1AAQKfysAAyYACgqCH6oGABwCACYABwoTIKoGABwCAAQACgryGaBqAK8BAAAA.',
Id='Idylwilde:BAABNQAECn8hAAIUAAcK/wm9RADfAAAUAAcK/wm9RADfAAAAAA==.',
Ie='Ienzo:BAAANQADCgQIBwAAAA==.',
Ih='Iheartoreos:BAABNQAECn8gAAIbAAgKYhKJUQCuAQAbAAgKYhKJUQCuAQAAAA==.',
Il='Ilovefuta:BAAANQAECgUICQAAAA==.Iloveoreos:BAAANQADCgYIBgAAAA==.',
In='Instakill:BAAANQADCgQIBAAAAA==.Intent:BAAANQADCgMIAwAAAA==.Invictae:BAAANQAECgcIEQAAAA==.',
Io='Iobo:BAACNQAFFH8QAAIjAAcKBByYAwAdAgAjAAcKBByYAwAdAgA1AAQKfycAAyMACgoCJMcGAGUDACMACgoCJMcGAGUDAAgAAgpEHmlRAKkAAAAA.',
Ir='Irk:BAABNQAECn8cAAIOAAgK9xWOQAC0AQAOAAgK9xWOQAC0AQAAAA==.Ironic:BAAANQADCgYIBgABNQAECgoKPwAOAKshAA==.',
Ja='Jagaerr:BAAANQABCgUICQAAAA==.Jarco:BAEANQAECgEIAQABNQAFFAYIDQADABwaAA==.Jargan:BAAANQADCggIDAABNQAECgoKJwAeAN4KAA==.Jasseca:BAAANQAECgMIBAABNQAECgkJGgAQAJYdAA==.',
Je='Jeandarc:BAAANQADCggICAAAAA==.Jezäbelle:BAAANQAECgYICAAAAA==.',
Jo='Joesh:BAAANQABCgcIFgAAAA==.',
Jt='Jtetue:BAAANQAECgQIBAAAAA==.',
Ka='Kaadra:BAAANQAECgUIBQAAAA==.Kaanon:BAAANQADCgEIAQAAAA==.Kaelkin:BAABNQAECn8qAAQRAAoKURMJUAA0AgARAAoKURMJUAA0AgATAAUKQw3INwClAAASAAIK6gbDIgBRAAAAAA==.Kaellar:BAAANQADCgMIAwABNQAECgoKKgARAFETAA==.Kaelun:BAAANQAECgIIBAABNQAECgoKKgARAFETAA==.Kaelundrus:BAABNQAECn8YAAMYAAoK0xZESwCzAQAYAAgKAhRESwCzAQAPAAYKShmMfgCoAQABNQAECgoKKgARAFETAA==.Kainis:BAAANQAECgUIEgAAAA==.Kamonorin:BAAANQABCgIIAgAAAA==.Kaotika:BAAANQAECgcIDAAAAA==.Karmus:BAAANQADCgUJCAAAAA==.',
Ke='Keadin:BAAANQADCgcIDAAAAA==.Keilas:BAABNQAECn8cAAIhAAYKrBwHEgDfAQAhAAYKrBwHEgDfAQAAAA==.Kerron:BAAANQAECggIAQAAAA==.Keylala:BAABNQAECn8cAAIfAAcKagrADADWAAAfAAcKagrADADWAAAAAA==.',
Ki='Kickenmage:BAAANQADCgQIBAABNQAECgYIGAALAKYGAA==.Kickentail:BAABNQAECn8YAAILAAYKpgY13wBCAQALAAYKpgY13wBCAQAAAA==.Kiegh:BAAANQADCgcIBwAAAA==.Kior:BAAANQADCgYIBwAAAA==.Kirisham:BAAANQADCgMIAwAAAA==.Kiriwar:BAACNQAFFH8HAAIWAAQKCRfALQCSAAAWAAQKCRfALQCSAAA1AAQKfzsAAhYACgp2IikiADADABYACgp2IikiADADAAAA.Kirlia:BAABNQAECn8vAAIfAAgKww2dFQDAAQAfAAgKww2dFQDAAQAAAA==.',
Kl='Klymax:BAAANQAECgcIDAAAAA==.',
Ko='Koretha:BAAANQAECgQICAABNQAFFAcIFwAKADYYAA==.Kowkowkachoo:BAAANQAECgYIDwAAAA==.',
Kr='Krellis:BAAANQAECgEIAQAAAA==.Krisp:BAABNQAECn8vAAMEAAkKtCK7GAByAwAEAAkKtCK7GAByAwAmAAEKrSPWNABnAAAAAA==.Krobelus:BAABNQAECn8mAAIVAAgKZQZt3gBeAQAVAAgKZQZt3gBeAQAAAA==.Kruggs:BAAANQADCgYIBgAAAA==.',
Ks='Ksharp:BAAANQADCgYIBgABNQAECgcIDQABAAAAAA==.',
Kv='Kvedadormu:BAAANQADCgYIEQAAAA==.Kvedeitrormr:BAAANQAECgEIAQAAAA==.Kvedfróðleik:BAAANQABCgEIAQAAAA==.Kvedærilaz:BAAANQADCgEIAQAAAA==.',
Ky='Kylearean:BAAANQAECgQIAwAAAA==.Kyran:BAAANQAECgIIAgAAAA==.',
['Kè']='Kèrónos:BAAANQAECgUIBwAAAA==.',
['Kì']='Kìllstheweak:BAABNQAECn8nAAMoAAoKOgknTACIAQAoAAoKOgknTACIAQAbAAIKTAiCeQBeAAAAAA==.',
La='Laeythe:BAEANQAECgQIBAABNQAFFAIIBgARAI0mAA==.Lannah:BAAANQADCgYIDgAAAA==.Lash:BAAANQAECgYIBwAAAA==.',
Lc='Lclc:BAAANQAECgYICgAAAA==.',
Le='Leafeon:BAACNQAFFH8IAAIKAAYK7wkBCAB1AQAKAAYK7wkBCAB1AQA1AAQKfyAAAgoACgpaJFcEAIADAAoACgpaJFcEAIADAAE1AAUUBwgQABgAORoA.Lebrin:BAABNQAECn8WAAIYAAUKZhqirQAVAQAYAAUKZhqirQAVAQAAAA==.Legaia:BAABNQAECn8xAAIWAAkKox80HgA/AwAWAAkKox80HgA/AwAAAA==.Legendknewl:BAAANQAECgQIBAAAAA==.Legendoflink:BAAANQAECgUIBgAAAA==.Lelana:BAAANQADCgcIBwAAAA==.Leliel:BAAANQADCggICAABNQAECgoKLQAHAJcaAA==.Lennyzamwam:BAAANQAECgQIBwAAAA==.Lesindre:BAAANQAECgcICAABNQAECggIAgABAAAAAA==.Letaria:BAAANQADCgYIBgAAAA==.Lexapro:BAAANQAECgcIDQABNQABCgcIBwABAAAAAA==.',
Li='Lianissa:BAAANQADCggIGwAAAA==.Lillinna:BAAANQAECgYIEAAAAA==.Lipidot:BAAANQAECgIIBAAAAA==.Lisea:BAAANQAECgIIAgAAAA==.Lithlina:BAAANQADCgYIBgAAAA==.',
Lo='Loamein:BAAANQAECgcIDQAAAA==.Lockrocks:BAABNQAECn8YAAIgAAgKCRM6cABOAQAgAAgKCRM6cABOAQAAAA==.Lockycharmz:BAAANQAECgUIBwABNQAECgkJSQAbADAcAA==.Lorcán:BAAANQADCgcIDAAAAA==.Lorithan:BAAANQADCgIIAgAAAA==.Lormazlezrax:BAABNQAECn8aAAIYAAkKkhmhRQBLAgAYAAkKkhmhRQBLAgAAAA==.',
Lu='Lucernyx:BAAANQAECgIIAgABNQAECgEIAgABAAAAAA==.Luckystars:BAAANQADCgQIBAAAAA==.Luis:BAAANQADCgQIBAAAAA==.Luminara:BAAANQADCgYIBgAAAA==.Lunaera:BAABNQAECn8aAAILAAkKwxCeXADKAQALAAkKwxCeXADKAQAAAA==.Lune:BAAANQADCgcIBwABNQAECggIDAABAAAAAA==.Lunella:BAAANQAECgIIAgABNQAECggIDAABAAAAAA==.Lunellia:BAAANQAECggIDAAAAA==.Lunethira:BAAANQAECgMIBQABNQAECggIDAABAAAAAA==.Lunevra:BAAANQABCgcIBwABNQAECggIDAABAAAAAA==.Lupi:BAAANQADCggIDwAAAA==.Lurkaburger:BAABNQAECn8ZAAIWAAkKthawZwBZAgAWAAkKthawZwBZAgAAAA==.',
Ly='Lythindra:BAAANQADCgQIBAAAAA==.',
Ma='Madhatter:BAABNQAECn8YAAMoAAUKFwWndwDFAAAoAAUK7wSndwDFAAAbAAEK+gRLnwAjAAAAAA==.Mageistmage:BAACNQAFFH8SAAMEAAcKUBUcHgCRAQAEAAYKXhUcHgCRAQAmAAEKGRWrCwBcAAA1AAQKfzMAAwQACgrHI5AeAK0CAAQACgrHI5AeAK0CACYAAQqZHBItAFYAAAAA.Magori:BAAANQADCgYIBgAAAA==.Majarl:BAAANQAECgYIEgAAAA==.Maki:BAAANQADCgEIAQABNQAECgkJKgAHAKgeAA==.Malegar:BAAANQADCggIFgAAAA==.Malificent:BAAANQAECgQICAAAAA==.Mammajamma:BAABNQAECn8oAAIUAAkKYRZENgA5AgAUAAkKYRZENgA5AgAAAA==.Marsvolta:BAAANQAECgQICAAAAA==.Maruxus:BAABNQAECn9CAAINAAoKTBeQCgAEAgANAAoKTBeQCgAEAgAAAA==.Maulsin:BAAANQADCgUIBQAAAA==.Mavanthia:BAABNQAECn8sAAMWAAkK/hIHYQCjAQAWAAkK/hIHYQCjAQAZAAEK0hIWQgA3AAAAAA==.Mayyonnaise:BAAANQAECgIIAQAAAA==.',
Mc='Mcdeathy:BAAANQAECgYIEAAAAA==.Mclardragos:BAABNQAECn8qAAMiAAoK0CI4BQBYAwAiAAoK0CI4BQBYAwAdAAEKAAB2PgAvAAAAAA==.',
Me='Meadõw:BAAANQADCgUIBQAAAA==.Meatshield:BAAANQADCgcIDAAAAA==.Mecharoni:BAABNQAECn8/AAMOAAoKqyGlDACqAgAOAAkK+h+lDACqAgANAAcKwSA2IgB0AgAAAA==.Medreaux:BAAANQAECggIAgAAAA==.Meganaturexl:BAAANQABCgQIBAAAAA==.Mendication:BAAANQAECgcIEQAAAA==.Meretrixee:BAAANQADCgIIAgABNQAECgoKRgARAHUYAA==.Meteion:BAABNQAECn8bAAMgAAcKNhqtWQCNAQAgAAcKNhqtWQCNAQAfAAEKAACYeAA1AAABNQAECggIAgABAAAAAA==.',
Mi='Miacyn:BAAANQAECgMIBgAAAA==.Midnitte:BAAANQAECgEIAQAAAA==.Miladybast:BAABNQAECn8aAAImAAcKpwYSHAAPAQAmAAcKpwYSHAAPAQAAAA==.Miniwheet:BAAANQAECgYICAABNQAECgkJSQAbADAcAA==.Minke:BAAANQADCggIHwAAAA==.Mirra:BAABNQAECn8eAAILAAgK3xKokgDjAQALAAgK3xKokgDjAQAAAA==.Missdorei:BAAANQADCgUIBQAAAA==.',
Mo='Molai:BAAANQAECggICAAAAA==.Mommades:BAAANQADCgYIBgABNQAECgcIHAALANkDAA==.Momsrymommy:BAABNQAECn8bAAIVAAYKtxJrwgCXAQAVAAYKtxJrwgCXAQAAAA==.Montavian:BAAANQADCggICwABNQAECgIIAgABAAAAAA==.Moodrian:BAAANQADCggICQABNQAECgoKJgAiAEoQAA==.Moonaurora:BAAANQABCgMIAwAAAA==.Moontater:BAAANQADCgYIBgAAAA==.Mordekaiser:BAAANQADCggICAAAAA==.Morgul:BAAANQAECgQICAAAAA==.Morionso:BAABNQAECn8oAAIXAAcKoholIQDbAQAXAAcKoholIQDbAQAAAA==.Morphyrinsjr:BAAANQADCgcIBwABNQAECgcIIgALAP0PAA==.Mortarion:BAABNQAECn83AAQcAAoKXRdvQgASAgAcAAcK5RtvQgASAgAoAAkKzhDWQwC0AQAbAAIKPAmpeQBdAAAAAA==.Morwenspring:BAAANQADCgMIAwAAAA==.',
Ms='Mssrbubbles:BAAANQABCggIFQAAAA==.',
Mu='Murdiûs:BAABNQAECn8/AAMkAAoK7B0+EgDLAgAkAAoK7B0+EgDLAgAlAAoKIxfLCACVAgAAAA==.',
My='Mythbruh:BAEBNQAECn8fAAMcAAcKkiGUSwDmAQAcAAcKhiCUSwDmAQAoAAcKfho2PADdAQAAAA==.',
Na='Nachokru:BAAANQABCgEIAgAAAA==.Nahla:BAAANQAECgIIAgAAAA==.Namrevlis:BAAANQADCgIIAgABNQAECgkJHgATAPEPAA==.Narl:BAAANQAECgUICAAAAA==.Nayrditation:BAAANQAECgcIDQAAAA==.Nayrlock:BAAANQAECgcICwABNQAECgcIDQABAAAAAA==.',
Nc='Nctee:BAAANQAECgUICgAAAA==.',
Ne='Nearn:BAAANQAECgIIAgAAAA==.Necropally:BAAANQADCgcIDQAAAA==.Nevermore:BAAANQAECgYIBgAAAA==.',
Ni='Nightsmoke:BAAANQAECgMJBQAAAA==.Nilious:BAAANQADCgIIAgAAAA==.',
No='Nolabull:BAAANQADCgQIBAAAAA==.Nonattarius:BAABNQAECn8bAAILAAcK2gcP3wBDAQALAAcK2gcP3wBDAQAAAA==.Noraelara:BAAANQAECggIAQABNQAECggIAgABAAAAAA==.Norezfou:BAABNQAECn85AAMRAAoK5xa1PwBsAgARAAoK5xa1PwBsAgATAAcKkhhvJAANAgAAAA==.Norran:BAAANQADCgMIAwAAAA==.Notalice:BAAANQAECgIIAgABNQAECgcIEQABAAAAAA==.Nottartar:BAAANQAECgIJAgAAAA==.',
Nu='Nuker:BAAANQADCgYIEgAAAA==.Nurobi:BAABNQAECn85AAIUAAoKfxGFIQC8AQAUAAoKfxGFIQC8AQAAAA==.',
Oa='Oaksong:BAAANQADCgQIBAAAAA==.',
Od='Odanobunaga:BAACNQAFFH8GAAIWAAIKLQikJAB2AAAWAAIKLQikJAB2AAA1AAQKfy4AAhYACgq/F3hVAIoCABYACgq/F3hVAIoCAAAA.Odyn:BAABNQAECn8VAAIVAAcKBQ9KyAAGAQAVAAcKBQ9KyAAGAQAAAA==.',
Oe='Oerrael:BAAANQADCgcIEAAAAA==.',
Or='Oridk:BAABNQAECn87AAIcAAoKWBu0EQBEAgAcAAoKWBu0EQBEAgABNQAFFAUIDAALAN0ZAA==.Oripal:BAAANQAECgIIAgABNQAFFAUIDAALAN0ZAA==.Oríon:BAACNQAFFH8MAAMLAAUK3RktDgD5AAALAAQK3RktDgD5AAAeAAIK7wudAgBOAAA1AAQKfzQABB4ACgoJI8kCAP0CAB4ACQpsHskCAP0CAAwABgrwFSs7AHgBAAsABgqBIj9+AHUBAAAA.',
Ou='Outofrange:BAAANQAECggIBgAAAA==.',
Pa='Pangjang:BAAANQAECgUICwAAAA==.Pankratease:BAAANQAECgcICQAAAA==.Pankratoes:BAAANQAECgIIAgABNQAECgcICQABAAAAAA==.Pankratos:BAAANQADCgUIBQABNQAECgcICQABAAAAAA==.Papahess:BAABNQAECn8hAAMUAAgKfBVCRQDbAQAUAAgKfBVCRQDbAQAFAAMKyQzSSQCFAAAAAA==.Paradias:BAABNQAECn8aAAIOAAkKMRSnEwBNAgAOAAkKMRSnEwBNAgAAAA==.Pastaladan:BAAANQADCgQIBAAAAA==.Pastor:BAAANQAECgQIBgAAAA==.Paxxul:BAAANQADCggICwAAAA==.',
Pe='Peppersham:BAABNQAECn8eAAMPAAcKmxSFWQA/AQAPAAcKmxSFWQA/AQAYAAYKoQvNswAHAQAAAA==.Petespally:BAABNQAECn8pAAMHAAgK8yNYDQA2AwAHAAgK8yNYDQA2AwAXAAEKAACTbgA0AAAAAA==.',
Pf='Pfftpfft:BAAANQAECgYICQAAAA==.',
Ph='Pha:BAABNQAECn8gAAIEAAoKrRgibwCfAgAEAAoKrRgibwCfAgAAAA==.Phatdanny:BAAANQAECggIDAAAAA==.Phonycheese:BAABNQAECn8wAAMVAAoK5BRpeQA5AgAVAAkKfRZpeQA5AgAHAAQK0giJsACPAAAAAA==.Phur:BAAANQAECgMIAwAAAA==.',
Pi='Pixen:BAABNQAECn9dAAMgAAoKKhz3GwCEAgAgAAoKKhz3GwCEAgACAAEKAAADMQAzAAAAAA==.',
Po='Pocalypse:BAAANQAECgQIBQAAAA==.Ponkeyfists:BAACNQAFFH8IAAIkAAQK5BoeCADRAAAkAAQK5BoeCADRAAA1AAQKfywAAiQACgp6I/0IAEEDACQACgp6I/0IAEEDAAAA.Portstar:BAABNQAECn8wAAIEAAoKVwt01gDaAQAEAAoKVwt01gDaAQAAAA==.Powderhorn:BAAANQADCgUIBQAAAA==.',
Pr='Pravium:BAAANQADCgYIBgABNQAECgcIEQABAAAAAA==.Primed:BAABNQAECn83AAIhAAkKTxOADQBDAgAhAAkKTxOADQBDAgAAAA==.Prozac:BAAANQAECgEIAQABNQABCgcIBwABAAAAAA==.',
Pu='Pungla:BAABNQAECn8UAAIkAAoKlRXOGgBoAgAkAAoKlRXOGgBoAgAAAA==.',
['Pî']='Pîper:BAAANQADCgQIBAAAAA==.',
Qu='Quelthanos:BAABNQAECn80AAMVAAkKFRXVbgCzAQAVAAkKFRXVbgCzAQAHAAEKfBDGGwE8AAAAAA==.Quesoblanco:BAAANQABCgQIBAAAAA==.',
Ra='Racob:BAAANQAECgMIAwABNQAECgQIAwABAAAAAA==.Radical:BAAANQAECgMIBQAAAA==.Ralvick:BAAANQADCgEJAQAAAA==.Ramuun:BAAANQADCgIIAgAAAA==.Randomclown:BAAANQAECgEIAQAAAA==.Rascalfats:BAAANQAECgQICwABNQAECggIDwABAAAAAA==.Rashii:BAABNQAECn8pAAIRAAkKrxSMSADdAQARAAkKrxSMSADdAQAAAA==.Rawor:BAAANQAECgQIBAAAAA==.Raworrior:BAABNQAECn8hAAMWAAgKCA3/wAB7AQAWAAgKCA3/wAB7AQAGAAEKOAhgNQAwAAAAAA==.Razera:BAAANQADCgcIBwAAAA==.',
Re='Reax:BAAANQADCgYIBgAAAA==.Rebaderchi:BAABNQAECn8hAAIjAAkKYhkAGwCAAgAjAAkKYhkAGwCAAgABNQADCgMIAwABAAAAAA==.Reignofpower:BAAANQADCgUIBQAAAA==.Reisswolf:BAAANQAECgMIAwAAAA==.Remoria:BAAANQAECgUIEAAAAA==.Renildan:BAAANQAECgYICgAAAA==.Renmazuo:BAAANQADCgMIAwAAAA==.Rezputan:BAAANQAECgcICgAAAA==.',
Rh='Rhavin:BAAANQAECgcICAAAAA==.Rhodon:BAAANQAECggIEAAAAA==.Rhohorn:BAAANQAECggICgAAAA==.Rholand:BAABNQAECn8zAAMWAAoK6RtKVACOAgAWAAoKphtKVACOAgAZAAEKpR1pMQBXAAAAAA==.Rhovid:BAAANQAECgQIBAAAAA==.',
Ri='Rivalt:BAAANQABCgQIBQAAAA==.Riverra:BAAANQADCgcICgAAAA==.Rizzoy:BAABNQAECn8kAAMGAAcKXRarFABVAQAGAAUKaRmrFABVAQAWAAYKzBKA4QAmAQAAAA==.',
Ro='Rollo:BAAANQAECgQIBAAAAA==.Roottender:BAAANQADCgcICwAAAA==.Rovyr:BAABNQAECn8uAAMiAAoKgx4MFABtAgAiAAoKgx4MFABtAgApAAEKAAC4JwAlAAAAAA==.Rowinna:BAAANQADCgUIBQAAAA==.',
Ru='Ruckabis:BAABNQAECn8cAAIYAAkKeBXCRQBKAgAYAAkKeBXCRQBKAgAAAA==.',
Ry='Rybearkin:BAAANQADCgMIAwAAAA==.Rylos:BAABNQAECn8dAAIcAAgKbAl/LgBEAQAcAAgKbAl/LgBEAQAAAA==.Ryshadow:BAAANQADCgYICwAAAA==.Ryumi:BAABNQAECn8ZAAIEAAcKexA1/QCTAQAEAAcKexA1/QCTAQAAAA==.',
Sa='Saansula:BAAANQADCgEIAQAAAA==.Sacmaster:BAAANQADCggIDAABNQAECgkJJwAfAHQWAA==.Saintagur:BAAANQABCgMIAQAAAA==.Saitamå:BAABNQAECn8kAAIlAAkKxheBFgAUAgAlAAkKxheBFgAUAgAAAA==.Samanaras:BAABNQAECn8rAAMZAAkKxxA0GgD7AAAWAAgKrg6EowDEAQAZAAcKOBI0GgD7AAAAAA==.Sangwyn:BAAANQAECgYICwABNQAECgkJKgAHAKgeAA==.Santiago:BAAANQAECgIIAgAAAA==.Saratoga:BAAANQAECgQICwAAAA==.Sarkana:BAABNQAECn8tAAIHAAoKlxoMIwDgAgAHAAoKlxoMIwDgAgAAAA==.Saxonn:BAAANQAECgIIAgAAAA==.Saydis:BAABNQAECn8YAAILAAYKowXd7gAkAQALAAYKowXd7gAkAQAAAA==.',
Sc='Scarletthot:BAAANQAECgIIAQAAAA==.Scatterbrain:BAAANQADCgcIDAAAAA==.',
Se='Sebattan:BAAANQADCgYIBwAAAA==.Seleinai:BAAANQADCgMIAwABNQAECgkJNQASAH8dAA==.Seleine:BAABNQAECn81AAISAAkKfx0lAgAJAwASAAkKfx0lAgAJAwAAAA==.Seloric:BAABNQAECn8qAAIbAAkKQR8iIADNAQAbAAkKQR8iIADNAQAAAA==.Serendrin:BAABNQAECn9HAAINAAoKnyE/AwD3AgANAAoKnyE/AwD3AgAAAA==.Sevalandre:BAAANQAECgIIAgABNQAECgkJGgAQAJYdAA==.',
Sh='Shaaman:BAAANQADCgYIBgAAAA==.Shadowskyz:BAAANQAECgQIDgABNQAFFAUICQAPAIoLAA==.Shaggimaggi:BAABNQAECn8aAAMbAAgK7RPTMABgAQAbAAgK7RPTMABgAQAcAAEKZgFsiQAcAAAAAA==.Shamanis:BAAANQADCgQIBAAAAA==.Shamcheese:BAAANQAECgQIBAABNQAECgoKMAAVAOQUAA==.Shamina:BAACNQAFFH8JAAIPAAUKigszCQAYAQAPAAUKigszCQAYAQA1AAQKf0wAAw8ACgoaHsITAKsCAA8ACgoaHsITAKsCACcAAQoYGmcsAE4AAAAA.Shammlet:BAAANQABCggIEwAAAA==.Shamorex:BAABNQAECn8hAAIPAAgK+xmaTQBAAgAPAAgK+xmaTQBAAgAAAA==.Shatter:BAABNQAECn8YAAIVAAgK/x5BXQCBAgAVAAgK/x5BXQCBAgAAAA==.Shax:BAAANQADCggICAABNQAECgkJLwAEALQiAA==.Shiftit:BAAANQAECgMIBQABNQAFFAIIBgAEAGkMAA==.Shlevin:BAAANQADCgcIDAAAAA==.Shockyoface:BAAANQABCgUIBQAAAA==.',
Si='Sideshift:BAAANQAECgQIBAABNQAFFAUICQAPAIoLAA==.Sinara:BAAANQAECgUICQAAAA==.',
Sk='Skaarr:BAAANQADCgQIBQAAAA==.Skibidiheals:BAAANQAECgEIAQAAAA==.Skybear:BAAANQABCgYICQAAAA==.',
Sl='Slash:BAAANQADCgYIBgAAAA==.Slayn:BAABNQAECn86AAImAAoKdhllBgAnAgAmAAoKdhllBgAnAgAAAA==.Sleebo:BAAANQAECgQICQAAAA==.Sleinx:BAAANQADCggIDQABNQAFFAQIDwAPABkSAA==.Slyrak:BAABNQAECn8XAAMdAAoKoxQtCADWAQAdAAkK2BYtCADWAQAiAAEKbQl+TgAzAAAAAA==.',
Sm='Smitus:BAAANQABCgIIAgAAAA==.',
Sn='Snackie:BAABNQAECn8mAAIYAAkKhh1NJwBeAgAYAAkKhh1NJwBeAgAAAA==.Snooty:BAAANQAECggJAgAAAA==.Snotpig:BAAANQAECggIBwAAAA==.',
So='Sokar:BAAANQAECggICQAAAA==.Sokolovva:BAAANQADCgcIDAAAAA==.Souled:BAAANQADCgUIBQABNQAECgkJMgAEAO4SAA==.Sourpunchkid:BAAANQAECgYIBwAAAA==.',
Sp='Spacedemon:BAABNQAECn8dAAIjAAkKtg3uNQCUAQAjAAkKtg3uNQCUAQAAAA==.Sparroh:BAAANQADCgYIBgAAAA==.Spikedriver:BAABNQAECn8nAAILAAoKHQ56agA+AgALAAoKHQ56agA+AgAAAA==.Spiky:BAAANQADCgMIAwAAAA==.',
St='Stariane:BAABNQAECn8uAAIIAAoK9hpjGQDQAgAIAAoK9hpjGQDQAgAAAA==.Starie:BAAANQAECgEIAQAAAA==.Startaker:BAAANQADCggIDwAAAA==.Startaster:BAAANQADCgcIBwAAAA==.Starvoid:BAAANQAECgYICAAAAA==.Stateofgrace:BAAANQAECggICgABNQAECgoKIgAKAK4lAA==.Steeldk:BAAANQAECgIJAgAAAA==.Stella:BAAANQAECgQICAAAAA==.Stonyfist:BAAANQADCgEIAQAAAA==.Stonyy:BAAANQAECgIIAgAAAA==.Stubhorn:BAAANQADCgUICAAAAA==.',
Su='Summers:BAAANQADCgcIDAAAAA==.Sumonmyface:BAABNQAECn8nAAMfAAkKdBbPIgBbAQAfAAQKEh7PIgBbAQAgAAYKvhBZxQBAAQAAAA==.Superillbomb:BAAANQADCgYJCQAAAA==.Superold:BAABNQAECn8VAAILAAgKzAxNZwCtAQALAAgKzAxNZwCtAQAAAA==.',
Sw='Swamprot:BAABNQAECn8hAAIcAAgKhh2lMwBcAgAcAAgKhh2lMwBcAgAAAA==.',
Sy='Sydoom:BAAANQABCgEIAQAAAA==.Syletage:BAAANQADCgYICwAAAA==.Syral:BAAANQADCgcIDAAAAA==.Syrel:BAAANQAECgEIBAAAAA==.',
Ta='Tailfordays:BAAANQADCgIIAgAAAA==.Tanky:BAAANQADCgIIAgAAAA==.Tantor:BAAANQADCgEIAQAAAA==.Tarragon:BAAANQADCgcIBwAAAA==.Taurnator:BAAANQAECgIIAgAAAA==.Taylorswift:BAABNQAECn8iAAMKAAoKriXeFwAJAgAKAAcKdyXeFwAJAgAhAAQKZB3hGgBTAQAAAA==.',
Tc='Tchiratha:BAAANQAECgYIEgABNQAECgkJNAAVABUVAA==.',
Te='Tednougat:BAAANQADCgYIBgAAAA==.Telain:BAABNQAECn8pAAQHAAoKQQocngBKAQAHAAkKxwccngBKAQAVAAcKrQtd+gAqAQAXAAIKSQz9XQBjAAAAAA==.Tensuki:BAAANQADCgQIBAAAAA==.Tesh:BAAANQADCgQIBgAAAA==.',
Th='Thaelynn:BAAANQADCggIHAAAAA==.Thakilla:BAABNQAECn9HAAIUAAoKBxRKGwD4AQAUAAoKBxRKGwD4AQAAAA==.Theolodin:BAAANQAECgIIAgAAAA==.Thordrik:BAAANQAECgIIAQAAAA==.Thorix:BAAANQAECgYICQAAAA==.Thornhub:BAAANQAECggIDAABNQAFFAoKPAAfAJUiAA==.Thrust:BAAANQAECgUICgABNQABCgcIBwABAAAAAA==.Thrustwood:BAAANQADCgMIAwAAAA==.',
Ti='Tiammanth:BAAANQAECgYICQAAAA==.Tigerbrew:BAAANQADCgUIBQAAAA==.Tigerburn:BAAANQADCgQIBAAAAA==.Tigerdawn:BAAANQADCgYIBgAAAA==.Tigerluna:BAAANQADCgQIBAAAAA==.Tikya:BAAANQADCgYIBwAAAA==.Tilsit:BAAANQAECggIDQAAAA==.Timberreaper:BAAANQADCgcICAAAAA==.Tinyz:BAAANQAECgQICQAAAA==.Tisisme:BAAANQADCgUIBQAAAA==.',
To='Tonythetiger:BAAANQAECgYICgABNQAECgkJSQAbADAcAA==.',
Tr='Train:BAAANQADCgcIBwAAAA==.Trampadin:BAAANQABCgQIBAAAAA==.Trei:BAAANQADCgIIAgABNQAECgcIDQABAAAAAA==.Trexlot:BAAANQADCgIIAgAAAA==.Trinjal:BAAANQAECgEIAgAAAA==.',
Tu='Tubbylumpkin:BAAANQADCggIDAAAAA==.Tummi:BAAANQADCgcIEAAAAA==.Tumnus:BAAANQAECgEIAQAAAA==.',
Ty='Tyjan:BAAANQAECgIIAwAAAA==.',
['Tâ']='Tâfa:BAAANQADCggICAAAAA==.',
Uh='Uhtred:BAAANQADCgYIBwAAAA==.',
Ul='Ulti:BAABNQAECn8qAAMHAAkKqB4BNACUAgAHAAkKqB4BNACUAgAXAAIKfQY0YwAhAAAAAA==.',
Un='Unholydevil:BAAANQAECgIIAgAAAA==.Unholyheart:BAAANQAECgIIAgAAAA==.',
Va='Varyusha:BAAANQAECgEIAQAAAA==.',
Ve='Velantra:BAAANQAECggIDQAAAA==.Venari:BAABNQAECn8cAAIeAAkKixb5AwAkAgAeAAkKixb5AwAkAgAAAA==.',
Vi='Vilelyn:BAABNQAECn8ZAAMlAAkKAxf0EgCWAQAlAAkKAxf0EgCWAQAkAAUK0wifPQCNAAABNQADCgEIAQABAAAAAA==.Viloria:BAABNQAECn8lAAIFAAgKthaoHgCqAQAFAAgKthaoHgCqAQAAAA==.Vincent:BAAANQADCgQIBAAAAA==.Virrard:BAABNQAECn8kAAILAAoK7BdOVAB0AgALAAoK7BdOVAB0AgAAAA==.',
Vl='Vladimor:BAAANQAECgcIEQAAAA==.Vladimyrr:BAAANQADCgUJCAAAAA==.',
Vo='Voslaarum:BAAANQADCgEIAQABNQAECgYIEAABAAAAAA==.Vozrezz:BAABNQAECn8ZAAMlAAcKRh5cEADJAQAlAAcKRh5cEADJAQAkAAUKlhTcUwCgAAAAAA==.',
Vu='Vualake:BAAANQADCgQIBQAAAA==.',
['Vë']='Vëda:BAABNQAECn84AAIRAAoKPiDWGwADAwARAAoKPiDWGwADAwAAAA==.',
Wa='Waffle:BAAANQAECgIIAwABNQAFFAUIBQAnAPUSAA==.Warage:BAAANQAECgEIAQAAAA==.Warske:BAAANQAECgQIBwABNQAECgUICAABAAAAAA==.',
Wh='Wheaties:BAAANQAECgYICgABNQAECgkJSQAbADAcAA==.Whizzie:BAABNQAECn8yAAIEAAkK7hJ4nwBCAgAEAAkK7hJ4nwBCAgAAAA==.Whizzlecrank:BAABNQAECn81AAIEAAkKTBR8pQA2AgAEAAkKTBR8pQA2AgAAAA==.',
Wi='Wicker:BAABNQAECn8rAAMUAAkKtRW9QwDlAQAUAAcK9xO9QwDlAQAKAAUKHxJhRgD+AAAAAA==.Willpharaoh:BAAANQADCgUICgAAAA==.Wiçker:BAAANQADCgIIAgABNQAECgkJKwAUALUVAA==.',
Wo='Wolford:BAAANQADCgYIBgAAAA==.',
Wr='Wras:BAABNQAECn8hAAIbAAcK3BMpPAAnAQAbAAcK3BMpPAAnAQAAAA==.Wrectt:BAAANQAECgUIDgABNQAECgcIDQABAAAAAA==.',
['Wò']='Wòbbles:BAAANQAECgYIDQABNQAECggIDwABAAAAAA==.',
Xa='Xandrah:BAAANQADCgUJBQAAAA==.Xandrel:BAABNQAECn8sAAIVAAkK4Q7KpABEAQAVAAkK4Q7KpABEAQAAAA==.',
Xe='Xed:BAABNQAECn82AAIPAAcKmRodSwBKAgAPAAcKmRodSwBKAgAAAA==.Xenogears:BAABNQAECn8pAAIMAAkKFhq2HgBbAgAMAAkKFhq2HgBbAgAAAA==.',
Xi='Xiansai:BAABNQAECn8wAAITAAoKlBLbIAAxAgATAAoKlBLbIAAxAgAAAA==.',
Ya='Yappey:BAAANQAECgcIBwAAAA==.',
Yi='Yippee:BAABNQAECn8iAAIPAAoKgh6JEwCtAgAPAAoKgh6JEwCtAgAAAA==.',
Yo='Youthinasia:BAABNQAECn8XAAMMAAcKLwyCRAA0AQAMAAcKLwyCRAA0AQALAAEKOwW4NAEuAAAAAA==.',
Ze='Zerega:BAAANQADCgcIHAABNQAECgoKXQANANMRAA==.',
Zh='Zhi:BAAANQAECgUIBgAAAA==.Zhukov:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.',
Zo='Zombiehippo:BAABNQAECn84AAIEAAoKTBmHOgA7AgAEAAoKTBmHOgA7AgAAAA==.',
['Áu']='Áutarch:BAABNQAECn8VAAIWAAgKMQf53AAyAQAWAAgKMQf53AAyAQAAAA==.',
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
