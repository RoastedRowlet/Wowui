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

local lookup = {'DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Hunter-BeastMastery','Priest-Discipline','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Monk-Mistweaver','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Priest-Holy','Mage-Arcane','Druid-Balance','Evoker-Devastation','Evoker-Preservation','Paladin-Holy','Priest-Shadow','DemonHunter-Devourer','Unknown-Unknown','DemonHunter-Havoc','DeathKnight-Frost','Hunter-Marksmanship','DemonHunter-Vengeance','Shaman-Elemental','Warrior-Protection','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','Monk-Windwalker','Druid-Feral','Druid-Guardian','Rogue-Outlaw','Shaman-Enhancement','Shaman-Restoration','Monk-Brewmaster','Mage-Fire','Hunter-Survival',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Absofsteels:BAABNQAECn8mAAMBAAcK0hWgMgBHAQABAAcK0hWgMgBHAQACAAMKtQcDsABrAAAAAA==.',
Ac='Acaric:BAABNQAECn8cAAIDAAgKVAdpFwBAAQADAAgKVAdpFwBAAQAAAA==.',
Ad='Adrielon:BAAANQADCggIEQAAAA==.Adøra:BAACNQAFFH8IAAIEAAMKmAh9FwDFAAAEAAMKmAh9FwDFAAA1AAQKf1kAAgQACgrMHuAlAP8CAAQACgrMHuAlAP8CAAAA.',
Ae='Aegea:BAAANQAECgIIAgABNQAECgoKPQAFAA4ZAA==.',
Ag='Agumon:BAABNQAECn8aAAICAAgKPxwBKgCjAQACAAgKPxwBKgCjAQAAAA==.',
Ai='Aircann:BAAANQADCggICAAAAA==.',
Al='Alchemist:BAAANQADCgUICQAAAA==.Alistair:BAAANQADCgUIBQAAAA==.Alluriel:BAAANQAECgIIBgAAAA==.Alonas:BAAANQAECgYICAABNQAECgkJKwAGAAQYAA==.Altharoth:BAABNQAECn8xAAMHAAoKFBv/XACBAgAHAAoKFBv/XACBAgAIAAEKzAypcQAuAAAAAA==.Altherion:BAAANQAECgIIAQAAAA==.',
Am='Amique:BAAANQAECgEIAQAAAA==.Amira:BAAANQADCgYIDwABNQAFFAYIDAAJAPIXAA==.Amorfox:BAAANQADCgcIBwAAAA==.Amormage:BAAANQAECgUIEQAAAA==.Amphitrite:BAAANQAECggIEAABNQAFFAYIDAAJAPIXAA==.',
An='Anabolicrage:BAAANQAECgIIAgAAAA==.Angmar:BAAANQAECgEIAQABNQAECgoKLgAKAB8dAA==.Anteiku:BAAANQAECgIIBAAAAA==.Anteikudeath:BAAANQADCgEIAQAAAA==.',
Ap='Applemoose:BAABNQAECn8pAAQLAAoKlx44XACsAQALAAkKPh84XACsAQAMAAIKhBgNUQCMAAANAAEK8BVmKQBGAAAAAA==.',
Ar='Aragrar:BAAANQAECgQIBQAAAA==.Arauial:BAABNQAECn8pAAIOAAkKMh+sNACVAgAOAAkKMh+sNACVAgAAAA==.Arcanis:BAABNQAECn85AAMPAAoKpBeLqAAxAgAPAAoKbxeLqAAxAgADAAIKBxftLwCBAAAAAA==.Aribella:BAACNQAFFH8HAAIEAAQKSQkGFwDJAAAEAAQKSQkGFwDJAAA1AAQKfy8AAgQACgqrEvVgAFUCAAQACgqrEvVgAFUCAAAA.Arizae:BAAANQAECgUIDgAAAA==.Arizann:BAABNQAECn8uAAMKAAoKHx07CABDAwAKAAoKHx07CABDAwAQAAUKzRHcYwA+AQAAAA==.Arobotev:BAABNQAECn85AAMRAAkKThFZCwCXAQARAAkKThFZCwCXAQASAAEK7QE2PQAgAAAAAA==.',
As='Astaren:BAAANQADCgcIEAAAAA==.Astiria:BAAANQAECgMIAwAAAA==.Asuran:BAABNQAECn8ZAAIGAAkK0RWwcQCXAQAGAAkK0RWwcQCXAQAAAA==.',
At='Atiya:BAACNQAFFH8HAAITAAUK7RKuCgCNAQATAAUK7RKuCgCNAQA1AAQKfzQAAhMACgo8IsEDAOADABMACgo8IsEDAOADAAAA.',
Az='Azaris:BAABNQAECn8hAAMUAAoK6RMIIwAaAgAUAAkK1xMIIwAaAgAOAAIK3wdQ9gBBAAAAAA==.',
Ba='Babykraze:BAABNQAECn8bAAIEAAcK1w3poQDCAQAEAAcK1w3poQDCAQAAAA==.Backshotz:BAAANQADCgMIAQAAAA==.Baelrog:BAABNQAECn8aAAMTAAgK4ga0kAD1AAATAAgK4ga0kAD1AAAHAAUKVgQsPAHAAAAAAA==.Baiene:BAABNQAECn8VAAQMAAkKwBKkCAAtAQAMAAgKwBKkCAAtAQALAAQKgAZ6DAGzAAANAAIKUAtsIQBuAAAAAA==.Baiken:BAAANQAECgEIAQAAAA==.Baldheadelf:BAAANQAECggICAAAAA==.Bandalar:BAABNQAECn8lAAIVAAgKYxdSIwAvAgAVAAgKYxdSIwAvAgAAAA==.Banerino:BAAANQADCgIIAgAAAA==.Barkathemoon:BAAANQABCggICAABNQAECgIIBQAWAAAAAA==.Barnabust:BAAANQAECgcICwAAAA==.Barricaded:BAAANQAECgEIAQAAAA==.Bashems:BAAANQAECgEJBAAAAA==.Baston:BAAANQADCgIIAgAAAA==.Battlebuns:BAAANQAECgEIAQAAAA==.',
Be='Bearypie:BAAANQAECggICAAAAA==.Beastums:BAABNQAECn87AAIEAAkKqxSXXgBaAgAEAAkKqxSXXgBaAgAAAA==.',
Bi='Bigbôotyjudy:BAAANQADCgIIAgAAAA==.Bigchungus:BAAANQADCggICQAAAA==.Bingbong:BAAANQADCgEIAQAAAA==.',
Bl='Blacken:BAAANQADCgQIBgAAAA==.Bleak:BAAANQAECgEIAQAAAA==.Blindmonk:BAAANQAECggIAwAAAA==.Blite:BAAANQADCgcIFAAAAA==.Bloodmary:BAABNQAECn8lAAIHAAoKEAwojgCbAQAHAAoKEAwojgCbAQAAAA==.Bloodor:BAAANQAECgYIBgAAAA==.Bloöm:BAABNQAECn9GAAIKAAoKJyMzBQBvAwAKAAoKJyMzBQBvAwAAAA==.Bluetsunami:BAABNQAECn8eAAIXAAcK+QLyYgCEAAAXAAcK+QLyYgCEAAAAAA==.',
Bm='Bmaazi:BAABNQAECn8pAAMSAAgK2RpzDwD9AQASAAgK2RpzDwD9AQARAAUKYgRMLADAAAAAAA==.',
Bo='Bonerina:BAAANQAECgQICQAAAA==.Boomadk:BAACNQAFFH8KAAIYAAUKyRLTCAAnAQAYAAUKyRLTCAAnAQA1AAQKf0sAAhgACgoSJGwKAEcDABgACgoSJGwKAEcDAAAA.Boppybone:BAAANQAECgIIAgAAAA==.',
Br='Bradburn:BAAANQADCgYIDAAAAA==.Bradkink:BAAANQAECgEIAgAAAA==.Brasserz:BAABNQAECn8jAAMEAAgKeRO0uwCMAQAEAAgKeRO0uwCMAQAZAAEKAABJlAAsAAAAAA==.Breezybone:BAABNQAECn83AAIDAAoKHB0cBADzAgADAAoKHB0cBADzAgAAAA==.Briaela:BAAANQADCgIIAgAAAA==.Brice:BAAANQADCgYICgAAAA==.Briochebun:BAABNQAECn8cAAIHAAkKRxUYeQA6AgAHAAkKRxUYeQA6AgAAAA==.',
Bw='Bwangifer:BAABNQAECn86AAIaAAkK2RtJBgAsAgAaAAkK2RtJBgAsAgAAAA==.',
['Bë']='Bëcky:BAABNQAECn8wAAQHAAoKxyXlGgDuAgAHAAoKxyXlGgDuAgATAAYKYxL4kQBpAQAIAAIKWyEWNwDBAAAAAA==.',
Ca='Calabera:BAAANQADCgYIBgAAAA==.Caloren:BAABNQAECn8qAAIEAAoKliRWDQB0AwAEAAoKliRWDQB0AwABNQAECgkJNAAVADkcAA==.Camerarius:BAAANQAECgEIAQAAAA==.Cannala:BAAANQADCgcIFAAAAA==.Cargae:BAAANQADCgcIFAAAAA==.Caso:BAAANQADCgMIBAABNQAECgUIDwAWAAAAAA==.',
Ce='Cellysia:BAABNQAECn8zAAMOAAoKKQSclQACAQAOAAoKKQSclQACAQAUAAIKFgPCdQA7AAAAAA==.Ceramyth:BAAANQAECgEIAQAAAA==.Ceres:BAABNQAECn87AAIMAAkKwxZbBAC6AQAMAAkKwxZbBAC6AQAAAA==.Cesara:BAABNQAECn9KAAMUAAoKsRryEQDfAgAUAAoKsRryEQDfAgAOAAMKFwiKvgCbAAAAAA==.',
Ch='Chal:BAABNQAECn8qAAIHAAcKxAl+6QBJAQAHAAcKxAl+6QBJAQAAAA==.Chaplin:BAAANQAECgMIBQABNQAECggIHAAbAMEMAA==.Chasterra:BAAANQAECgEIAQABNQAECgoKSAAKAAQfAA==.Chbribs:BAAANQAECgcIEgAAAA==.Chestypanda:BAAANQADCgQIBAAAAA==.Chillypepper:BAAANQAECgQIBAAAAA==.Chiptewth:BAAANQABCgYICQAAAA==.Chiron:BAAANQADCgEIAQAAAA==.',
Co='Coldsteel:BAAANQAECgEIAgAAAA==.Columbina:BAABNQAECn8lAAIVAAoK7hSjKAD/AQAVAAoK7hSjKAD/AQAAAA==.Cooperhowerd:BAAANQADCgcIEgAAAA==.Corky:BAAANQADCgEIAQABNQAECgoKLgAKAB8dAA==.Corn:BAAANQADCgIIAgABNQAECgcIEAAWAAAAAA==.',
Cp='Cptredbeardd:BAAANQADCgYIDgAAAA==.',
Cr='Crackmonger:BAACNQAFFH8FAAIGAAIKLxXkLACWAAAGAAIKLxXkLACWAAA1AAQKfyMAAgYACQquGh9ZAIACAAYACQquGh9ZAIACAAAA.Crackundead:BAACNQAFFH8IAAIYAAMKJA75FgCIAAAYAAMKJA75FgCIAAA1AAQKfzwAAhgACgrTGechAH4CABgACgrTGechAH4CAAAA.Crapdragon:BAAANQAECgUICAAAAA==.',
Cy='Cyphr:BAABNQAECn85AAIKAAkKch0gEwB/AgAKAAkKch0gEwB/AgAAAA==.Cyrinx:BAABNQAECn8aAAMKAAkKIAjMUgCZAAAKAAgKwQTMUgCZAAAQAAcKQANNkgCOAAAAAA==.',
Da='Daen:BAAANQADCggICAAAAA==.Dagravytrain:BAAANQAECgUJCAAAAA==.Dain:BAAANQADCgYIDAAAAA==.Dalend:BAABNQAECn8gAAMGAAoKLRxgSQATAgAGAAoKyxtgSQATAgAcAAIKUhs0NACVAAAAAA==.Damerot:BAABNQAECn8rAAMdAAoK2hWJCAAJAgAdAAoK2hWJCAAJAgAcAAEK2getRQAoAAAAAA==.Dangerous:BAABNQAECn8fAAIeAAgKVBC7FwBfAQAeAAgKVBC7FwBfAQAAAA==.Danpal:BAAANQADCggICQAAAA==.Dansharo:BAAANQADCgMIAwAAAA==.Darc:BAAANQAECgQIBAAAAA==.Darnnix:BAAANQAECgUICwAAAA==.Darthrevin:BAABNQAECn8iAAMfAAkKPA5EJACmAQAfAAkKOw1EJACmAQAeAAYKMAhnYAAzAQAAAA==.Dawnsingers:BAAANQAECgEIAgAAAA==.',
De='Deadbeard:BAABNQAECn9dAAQYAAoK0SXhAgC4AwAYAAoK0SXhAgC4AwACAAcKpB6xSQDRAQABAAQKASTDeAA3AQAAAA==.Deathbash:BAAANQADCgEIAQAAAA==.Deathdream:BAAANQAECgUIBgAAAA==.Deathrar:BAAANQADCgcICwAAAA==.Deathviix:BAAANQAECgUICgAAAA==.Debased:BAABNQAECn8rAAIBAAkKbxS4IgC2AQABAAkKbxS4IgC2AQAAAA==.Demini:BAAANQADCgYIDQAAAA==.Demisê:BAABNQAECn9YAAICAAoKExyQFgBFAgACAAoKExyQFgBFAgAAAA==.Demonn:BAAANQAECggIEwAAAA==.Derbygirl:BAAANQADCgYIDQAAAA==.Desperation:BAABNQAECn8WAAIIAAkKOhNUKACbAQAIAAkKOhNUKACbAQAAAA==.Desso:BAABNQAECn8bAAIgAAgKqRI2IQB8AQAgAAgKqRI2IQB8AQAAAA==.Detraz:BAAANQABCgEIAQAAAA==.Devilskin:BAAANQADCgUICgAAAA==.',
Di='Dillinger:BAAANQAECgcIDgAAAA==.Dingodgaf:BAABNQAECn89AAIHAAkK6QgMuQBJAQAHAAkK6QgMuQBJAQAAAA==.',
Dj='Djinnjuicy:BAABNQAECn8dAAIPAAcKpQivHAFcAQAPAAcKpQivHAFcAQAAAA==.',
Do='Dodo:BAAANQAECgQICgAAAA==.Dorianmyth:BAABNQAECn8aAAIIAAgKRAecOAAnAQAIAAgKRAecOAAnAQAAAA==.',
Dr='Dragonshammy:BAAANQADCgMIAwABNQAECgoKNwATAMggAA==.Drazzi:BAAANQAECgEIAQAAAA==.Dreamclaw:BAABNQAECn8pAAMhAAoKhw8/FQBaAQAhAAoKnw4/FQBaAQAiAAQKkwpgRQCeAAAAAA==.Drippindots:BAACNQAFFH8IAAMLAAQKIBstKgC1AAALAAMKiR8tKgC1AAAMAAEKThJzEABLAAA1AAQKf0kAAwsACgrqInoLAHEDAAsACgqSInoLAHEDAAwAAQr8JNoeAG4AAAAA.Driztette:BAAANQAECgYIDAAAAA==.Drnewport:BAAANQADCggIEwAAAA==.Drokash:BAAANQAECgYIBgAAAA==.Drystine:BAABNQAECn8dAAIXAAkKrA9MTABuAQAXAAkKrA9MTABuAQAAAA==.',
Dy='Dyronebiggum:BAAANQADCggIDAAAAA==.Dyxie:BAAANQAECgIIAgAAAA==.',
['Dí']='Dín:BAAANQAECgcIEQAAAA==.',
Ec='Ectharienne:BAAANQAECgEIAQAAAA==.',
Ee='Eedeeweewee:BAAANQADCgcIFAAAAA==.',
Eg='Eggs:BAAANQADCgEIAQAAAA==.',
Ei='Eillaura:BAABNQAECn9EAAIOAAoKfxsNOABIAgAOAAoKfxsNOABIAgAAAA==.',
El='Electroshokk:BAAANQAECgIIAgABNQAECgQIBQAWAAAAAA==.Elemag:BAAANQAECgUIBwAAAA==.Eleredra:BAAANQADCgYIBgABNQAECgoKKQAUAPYRAA==.Eleyna:BAAANQAECgEIAQAAAA==.Elipsis:BAACNQAFFH8IAAIOAAQK6BrcFgAuAQAOAAQK6BrcFgAuAQA1AAQKfzYAAg4ACgqiJFcHAIoDAA4ACgqiJFcHAIoDAAAA.Elm:BAABNQAECn8gAAMQAAoKOxIiQQD0AQAQAAoKOxIiQQD0AQAKAAIK6gxuaABjAAAAAA==.Elybella:BAAANQADCgMIAwABNQAFFAUICAASAEsWAA==.Elycia:BAAANQAECgYICQABNQAFFAUICAASAEsWAA==.Elyenora:BAACNQAFFH8IAAISAAUKSxaPCQBkAQASAAUKSxaPCQBkAQA1AAQKfywAAhIACgrxFw8WAFUCABIACgrxFw8WAFUCAAAA.',
En='Enquea:BAAANQAECgYIDwABNQAECgoKLgAKAB8dAA==.Enricco:BAAANQAECgEIAQAAAA==.',
Er='Eraeste:BAAANQAECgEIAQAAAA==.Ereko:BAABNQAECn8mAAIEAAgKLA1opQC7AQAEAAgKLA1opQC7AQAAAA==.Eriss:BAABNQAECn8qAAIPAAoK5hBsZADcAQAPAAoK5hBsZADcAQAAAA==.Erythorbic:BAABNQAECn8rAAMMAAgKUBpTGACTAAALAAcKdxg5dwBiAQAMAAMKXxtTGACTAAAAAA==.',
Es='Estralage:BAAANQADCgUICwAAAA==.',
Ev='Evictor:BAAANQAECgEIAQABNQAECgkJGgAgAC8SAA==.',
Fa='Fanaticism:BAAANQAECgMIBAAAAA==.Fangs:BAAANQAECggIDgABNQAECgkJHQAMAMUZAA==.Faranth:BAABNQAECn8hAAIEAAkK6xZDYwDmAQAEAAkK6xZDYwDmAQAAAA==.Fatman:BAAANQAECgIIBQABNQAECgUIBwAWAAAAAA==.',
Fe='Feer:BAAANQADCgQICAAAAA==.Feldron:BAAANQAECggIEQAAAA==.',
Ff='Ffugher:BAAANQAECgUICgAAAA==.Ffugme:BAABNQAECn8yAAMIAAoKlQkwOAAqAQAIAAoKVAkwOAAqAQAHAAYKiQXQCgHEAAAAAA==.Ffugnutz:BAAANQADCgQIBAAAAA==.Ffugoff:BAABNQAECn8dAAIbAAYK+AvZgAD4AAAbAAYK+AvZgAD4AAAAAA==.Ffugtard:BAABNQAECn8qAAIEAAkKoxAKjgB+AQAEAAkKoxAKjgB+AQAAAA==.Ffugyou:BAAANQADCggICwAAAA==.',
Fi='Finnian:BAABNQAECn8sAAITAAkKNxJwRADvAQATAAkKNxJwRADvAQAAAA==.Fio:BAAANQAECgYICgAAAA==.Firiona:BAABNQAECn8gAAMOAAoK1BoPIgC/AgAOAAkK2xkPIgC/AgAUAAUKDRRSOQC7AAABNQAECgoKJgAhAMAeAA==.',
Fl='Flinn:BAAANQADCgIIAgAAAA==.Flowers:BAABNQAECn8qAAIVAAcKrR+FIABJAgAVAAcKrR+FIABJAgAAAA==.Fläva:BAAANQAECgcICQAAAA==.',
Fo='Foot:BAAANQADCgYICgAAAA==.Forfuncasual:BAABNQAECn8iAAIjAAkKJxyABQCTAgAjAAkKJxyABQCTAgAAAA==.Foxhound:BAABNQAECn8pAAIgAAcKTA2ONgBhAQAgAAcKTA2ONgBhAQAAAA==.',
Fr='Fracture:BAAANQADCggICAABNQAECggINAAkAFgJAA==.Fresca:BAAANQADCgEIAQAAAA==.Friendlyhoss:BAAANQADCgIIAgAAAA==.Frostypie:BAAANQADCggIEAAAAA==.',
Fu='Funkyfungi:BAAANQAECgIIAgAAAA==.Furyswarm:BAAANQAECggICQAAAA==.',
['Fö']='Föx:BAAANQADCgYIBgAAAA==.',
Ga='Gaius:BAAANQAECgQICAABNQAECgUIBQAWAAAAAA==.Gawdcomplex:BAABNQAECn8bAAITAAcKYQzHiwB5AQATAAcKYQzHiwB5AQAAAA==.',
Ge='Gernaj:BAAANQADCgcICwAAAA==.',
Gh='Ghostfrudge:BAAANQAECgEIAQAAAA==.Ghostfudge:BAABNQAECn80AAQIAAoK1htkDgC1AgAIAAkKtB9kDgC1AgAHAAIKqwEKpwEZAAATAAEKywD5CQEJAAAAAA==.Ghostlyfudge:BAAANQAECgMIAwAAAA==.',
Gi='Ginny:BAABNQAECn8hAAIIAAgKJgoELwDuAAAIAAgKJgoELwDuAAAAAA==.Ginsan:BAAANQADCgEIAQAAAA==.Ginthalos:BAAANQAECgMIAwAAAA==.',
Go='Golaru:BAAANQABCgIIAgAAAA==.',
Gr='Gramthyr:BAAANQADCgcIFAAAAA==.Grep:BAAANQADCgMIAwAAAA==.Greygor:BAABNQAECn8VAAIdAAYKHwWhIgB6AAAdAAYKHwWhIgB6AAAAAA==.Grotok:BAAANQAECgIIBAABNQAECggIJQAEAF0VAA==.',
Gu='Gumer:BAABNQAECn8kAAMlAAkKrAzvmwBAAQAlAAkKrAzvmwBAAQAbAAUK0QIj7wC4AAAAAA==.Gurgatron:BAABNQAECn8kAAMeAAoKqhJIDAD7AQAeAAoKqhJIDAD7AQAjAAIK4QX4GABVAAABNQAECgoKQwAcAF8mAA==.Guulen:BAAANQADCgIIAgAAAA==.',
['Gá']='Gárd:BAAANQAECgYIBgAAAA==.',
Ha='Halygos:BAAANQAECgQICgAAAA==.Hariffug:BAAANQADCgcIBwAAAA==.Hasklaufien:BAABNQAECn8UAAMdAAkK2RkICgAvAgAdAAgKkBsICgAvAgAGAAMKKxGQEgG3AAAAAA==.',
He='Healinside:BAAANQAECgYIDgABNQAECgoKNwATAMggAA==.Hellvina:BAAANQADCggICAAAAA==.Hermie:BAAANQABCggICAAAAA==.',
Hi='Hinderberg:BAAANQAECgIIBAAAAA==.',
Ho='Holdor:BAABNQAECn8XAAMBAAYKqw3OQQD1AAABAAYKqw3OQQD1AAACAAQKdQPdgABfAAAAAA==.Holÿdiver:BAAANQABCgYIBAABNQAECgoKKQALAJceAA==.Horde:BAAANQADCgIIAgAAAA==.Horizons:BAAANQAECgUICQAAAA==.',
Hu='Huntsum:BAABNQAECn8lAAMEAAgKXRVJfAAVAgAEAAcKrBdJfAAVAgAZAAYKhgxbOwCkAAAAAA==.',
Ia='Iahsotgievhu:BAAANQADCgcICAAAAA==.Iamspeed:BAAANQABCgEIAQAAAA==.',
Ic='Iceblocklulz:BAAANQAECgEIAgAAAA==.Icedsoul:BAABNQAECn8aAAMDAAcKuQnMHwDrAAADAAYKuQnMHwDrAAAPAAMKrAGargFkAAAAAA==.Iceflame:BAAANQADCgYIBgABNQAECgcIKQAKAMsbAA==.',
Ig='Iggey:BAABNQAECn8lAAIGAAoKzRHOlwDhAQAGAAoKzRHOlwDhAQAAAA==.',
Ik='Ikkaku:BAAANQADCggIDQAAAA==.',
Il='Ilandras:BAABNQAECn8hAAIVAAkKExY9JAAlAgAVAAkKExY9JAAlAgAAAA==.Illadus:BAABNQAECn8bAAIVAAgKDgwxPwBRAQAVAAgKDgwxPwBRAQAAAA==.Illiviix:BAAANQADCgcIHgAAAA==.',
In='Indra:BAABNQAECn8yAAIHAAoKYh1mSwCzAgAHAAoKYh1mSwCzAgAAAA==.Intoxicated:BAAANQAECgQICwAAAA==.',
Ir='Iranna:BAACNQAFFH8XAAMeAAcK4CM7AgB6AQAeAAUK/yQ7AgB6AQAfAAMKyyH3EABsAAA1AAQKfzIAAx4ACgpiJR4NABwDAB4ACgpdJR4NABwDAB8ACAqUI2kiAHACAAAA.',
It='Itsredbelow:BAAANQAECgEIBgAAAA==.',
Iz='Izlaz:BAAANQADCggICAAAAA==.',
Ja='Jacrispy:BAAANQAECgIJAwAAAA==.Jaggedace:BAABNQAECn81AAQYAAoKJweuRgBmAQAYAAoKxQauRgBmAQACAAYKvgR3igDWAAABAAQKQQfkXACHAAAAAA==.Janaki:BAABNQAECn9IAAMKAAoKBB8RCABHAwAKAAoKBB8RCABHAwAQAAYKiQhccAAJAQAAAA==.',
Je='Jedione:BAAANQAECgEIAQAAAA==.Jellyfish:BAABNQAECn8ZAAIHAAgKWBIhswBUAQAHAAgKWBIhswBUAQAAAA==.',
Ji='Jibbtotem:BAAANQADCgYIDQABNQAECgkJHwAUAI8WAA==.Jivanos:BAAANQAECgEIAwAAAA==.',
Jo='Joexotick:BAAANQABCgMIBQAAAA==.Jonnyquestt:BAABNQAECn8nAAIHAAgKXA3qtQCyAQAHAAgKXA3qtQCyAQAAAA==.',
Ju='Junlock:BAAANQAECgYICgABNQAFFAgIGAAVAMMWAA==.Junrush:BAACNQAFFH8YAAIVAAgKwxZzAQDeAQAVAAgKwxZzAQDeAQA1AAQKfzcAAxUACgpHI3YJALMCABUACgpHI3YJALMCABoAAQoAAMcvAD8AAAAA.Junshot:BAAANQAECgEIAQABNQAFFAgIGAAVAMMWAA==.',
Ka='Kalea:BAAANQABCgIIBAAAAA==.Kalietha:BAABNQAECn8XAAMMAAkKaAccSACnAAALAAkKUgWX0QAmAQAMAAMK3gwcSACnAAAAAA==.Karaizula:BAABNQAECn8rAAMlAAoKgQ/qTADHAQAlAAoKgQ/qTADHAQAbAAQKTwFGBgGBAAAAAA==.Kasdeya:BAAANQADCgYIBwAAAA==.Kassandrah:BAAANQADCgUIBQAAAA==.Katsuko:BAABNQAECn8zAAICAAoKBRZCIgDZAQACAAoKBRZCIgDZAQAAAA==.Kattnirra:BAABNQAECn8oAAIEAAoKSAvXewCoAQAEAAoKSAvXewCoAQAAAA==.Katze:BAABNQAECn8mAAIEAAkKRhEzZABNAgAEAAkKRhEzZABNAgAAAA==.Kaylé:BAAANQAECgMIAwAAAA==.',
Ke='Keepper:BAAANQAECgMIBwAAAA==.Kenj:BAABNQAECn8zAAIOAAoKdCPuBgCOAwAOAAoKdCPuBgCOAwABNQAFFAcIEwAKAMUcAA==.Kenjurr:BAABNQAECn8fAAMSAAkKTB/HBgA6AwASAAkKTB/HBgA6AwARAAIKOAtdNQBiAAABNQAFFAcIEwAKAMUcAA==.Kenslynn:BAABNQAECn84AAIOAAoKphykKQDCAgAOAAoKphykKQDCAgAAAA==.Ketheric:BAAANQADCgEIAQABNQAECgkJHQAMAMUZAA==.',
Ki='Kiannor:BAABNQAECn8sAAIgAAkK3wc6KAA/AQAgAAkK3wc6KAA/AQAAAA==.Killahaseo:BAABNQAECn8rAAIHAAoKeiH0SQC3AgAHAAoKeiH0SQC3AgAAAA==.Killmoedee:BAABNQAECn88AAMIAAoKwyLDCQCOAgAIAAoKwyLDCQCOAgAHAAMKCQXEZwFOAAAAAA==.Kishibe:BAAANQAECgUIDQAAAA==.Kiss:BAAANQAECggIEwABNQAFFAkJMAAlAHEjAA==.Kitwryn:BAAANQADCgcIFAAAAA==.',
Kl='Klexios:BAAANQAECgQIDAAAAA==.',
Ko='Koopa:BAAANQAECgcIEQAAAA==.',
Kr='Kraulhoof:BAAANQAECgEIAQABNQAECgQIBQAWAAAAAA==.Kronohs:BAAANQAECgIIAwAAAA==.Krymson:BAAANQADCgcIBwAAAA==.',
Ku='Kui:BAABNQAECn82AAImAAkKWB5tBABlAgAmAAkKWB5tBABlAgAAAA==.Kuneia:BAAANQAECgEIAQABNQAECgoKSAAKAAQfAA==.Kurakka:BAAANQADCgEIAQAAAA==.Kuyna:BAAANQADCgYIDgAAAA==.',
Ky='Kylohendrix:BAAANQAECgQIBQAAAA==.',
['Kö']='Köz:BAAANQAECgQIBAAAAA==.',
La='Laetri:BAAANQAECgQIBQAAAA==.Lailiia:BAABNQAECn8hAAIJAAcKFBJtHwCVAQAJAAcKFBJtHwCVAQABNQAECggIEgAWAAAAAA==.Laindrin:BAAANQAECgMIAQAAAA==.Lavendarlace:BAAANQADCgYIDAAAAA==.Lawrence:BAAANQADCggICAAAAA==.Lazloo:BAABNQAECn81AAIGAAkK1yRqJgAfAwAGAAkK1yRqJgAfAwAAAA==.Lazymidget:BAABNQAECn8YAAIZAAkKYgduOQCFAQAZAAkKYgduOQCFAQAAAA==.Lazytok:BAAANQAECgQIBgAAAA==.',
Le='Leftÿ:BAABNQAECn9IAAIYAAoKsB0fEgD8AgAYAAoKsB0fEgD8AgAAAA==.Legindkiller:BAAANQADCgcIFAAAAA==.Lenie:BAABNQAECn8bAAQOAAkKLSG2FwAIAwAOAAgK5iK2FwAIAwAUAAIKigpjWQA9AAAFAAEKVwnvMgAbAAABNQAFFAcIFAACAFogAA==.Levoyon:BAABNQAECn8fAAIkAAkKiQaZGABvAQAkAAkKiQaZGABvAQAAAA==.Lexibelle:BAABNQAECn86AAILAAoKnw03WgCyAQALAAoKnw03WgCyAQAAAA==.Lexsing:BAAANQABCgEIAQAAAA==.',
Lf='Lfty:BAAANQADCggIEAABNQAECgoKSAAYALAdAA==.',
Li='Lianthael:BAAANQAECgcICAABNQAECggIJQAEAF0VAA==.Lightace:BAABNQAECn86AAMHAAoKTA7inAB+AQAHAAoKvwninAB+AQAIAAYKNRKjNQDIAAAAAA==.Lightbunny:BAAANQAECggIEgAAAA==.Lightlicious:BAAANQADCgQIBAAAAA==.Lincia:BAAANQAECgUICQAAAA==.Linkkil:BAAANQAECgYIDQAAAA==.Liv:BAAANQADCgMIAwABNQAECgkJGAAOAFAXAA==.',
Lo='Loastotem:BAAANQADCgIIAgAAAA==.Lobos:BAABNQAECn8yAAILAAoKyQ9OdQACAgALAAoKyQ9OdQACAgAAAA==.Lockrah:BAAANQADCgcIEgAAAA==.Lorvinion:BAAANQAECgUIBwAAAA==.Lostdraco:BAAANQAECgcIEwAAAA==.Lostdream:BAABNQAECn9BAAMXAAoKcgooNgBYAQAXAAoKcgooNgBYAQAaAAgKhAWCHgDaAAAAAA==.Loun:BAABNQAECn8jAAImAAgKsxw+BwDkAQAmAAgKsxw+BwDkAQAAAA==.',
Lu='Luiss:BAABNQAECn8cAAIHAAYKDAe7HQGpAAAHAAYKDAe7HQGpAAAAAA==.Luminism:BAABNQAECn8gAAMTAAoKiRrSPgBpAgATAAoKiRrSPgBpAgAHAAEKAACCjgFGAAABNQAECgkJGwAJAMIVAA==.Luvlycruelty:BAABNQAECn8YAAQLAAgKPQkHkwAgAQALAAgK4QgHkwAgAQAMAAIKOAYuZgBXAAANAAEKAAA/MgAwAAAAAA==.',
Ly='Lycos:BAAANQABCgQIBAAAAA==.Lyn:BAEBNQAECn85AAImAAoKaCZmAADvAwAmAAoKaCZmAADvAwAAAA==.',
['Lê']='Lêônà:BAAANQAECgEIAgAAAA==.',
Ma='Maazi:BAAANQADCgYIBgAAAA==.Mackenziiee:BAABNQAECn9DAAIEAAoK/BgROwC5AgAEAAoK/BgROwC5AgAAAA==.Magerick:BAAANQAECgYIDgAAAA==.Magicwater:BAAANQAECgEIAgABNQAECgoKNQAHAGgkAA==.Magtaki:BAAANQADCgEJAQAAAA==.Mainline:BAAANQAECgUIDQAAAA==.Maizepriest:BAABNQAECn8tAAIUAAkKPyAODgBmAgAUAAkKPyAODgBmAgAAAA==.Maliaa:BAAANQAECgIIBQAAAA==.Malloryrose:BAAANQADCgcIBwAAAA==.Mandrison:BAABNQAECn8cAAIGAAkKKA8jWgDdAQAGAAkKKA8jWgDdAQAAAA==.Masfima:BAAANQADCgIIAgAAAA==.Maxz:BAAANQAECgEIAQAAAA==.',
Mc='Mcstàbby:BAAANQABCgMIAwAAAA==.',
Me='Meerkat:BAAANQAECgQIBwAAAA==.Mellowblink:BAABNQAECn8YAAIPAAYKmBWJAAGNAQAPAAYKmBWJAAGNAQABNQAECgoKJgAhAMAeAA==.Mellowlink:BAABNQAECn85AAMfAAkKKB/6DQCXAgAfAAkKKB/6DQCXAgAeAAEKURJYYAA4AAABNQAECgoKJgAhAMAeAA==.',
Mi='Migglet:BAAANQAECgMIAwAAAA==.Mightyshoe:BAAANQAECgEIAQAAAA==.Miirya:BAAANQADCgYIAwAAAA==.Milkybar:BAAANQAECggIEQAAAA==.Mimi:BAACNQAFFH8+AAMEAAoKqSVPAgBYAgAZAAkKLSTpAQBaAgAEAAYKMSZPAgBYAgA1AAQKfzIAAxkACgrEJoEGAGgDABkACgpkJoEGAGgDAAQACApFJj8mAP4CAAAA.Miramage:BAAANQADCgcIBwABNQAECggIFwAfAPQVAA==.Miravus:BAABNQAECn8XAAMfAAgK9BV2ZABfAQAfAAYKgBR2ZABfAQAeAAUK2hXNWABWAQAAAA==.Mirlanda:BAAANQAECgIIBQAAAA==.Misttie:BAABNQAECn8qAAImAAoKiR2iAwCQAgAmAAoKiR2iAwCQAgABNQAFFAQICAAOAOgaAA==.Mitcheoff:BAAANQAECgQIEQAAAA==.',
Mo='Moisturizer:BAAANQAECgUIDAAAAA==.Moltenkam:BAAANQADCgEIAQAAAA==.Monkerick:BAAANQADCgQIBwAAAA==.Mooningyall:BAAANQAECgQICQAAAA==.Mowte:BAAANQADCgYIEgAAAA==.',
Mu='Murkoobi:BAAANQAECgEIAQAAAA==.Mursk:BAAANQAECgQIAQAAAA==.',
My='Mystrial:BAAANQABCgcICwAAAA==.Mystáke:BAAANQAECggIEAAAAA==.',
['Mó']='Mómo:BAAANQADCgMIAwAAAA==.Móus:BAAANQADCgIIAgABNQAECgkJKQAlAMsWAA==.',
Na='Narbus:BAABNQAECn8UAAIQAAUKBQ4acAAKAQAQAAUKBQ4acAAKAQAAAA==.Narcissus:BAAANQADCgUIDgAAAA==.Naromancer:BAABNQAECn9AAAIPAAkKOCIBNQBkAgAPAAkKOCIBNQBkAgAAAA==.Nathadon:BAABNQAECn9FAAIUAAoKLSBICQBKAwAUAAoKLSBICQBKAwAAAA==.Nautrium:BAAANQAECgQICQAAAA==.',
Ne='Necrotis:BAAANQADCgcIFAAAAA==.Nekhraros:BAABNQAECn8dAAMMAAkKxRmPMAAGAQALAAYKHhYwogCRAQAMAAMKox6PMAAGAQAAAA==.Nergál:BAAANQADCgYIBQABNQADCggICAAWAAAAAA==.Nevelia:BAAANQAECggIEgAAAA==.Neytfury:BAAANQADCgUIBQAAAA==.Neyti:BAAANQADCgIIAgAAAA==.Neytvengy:BAAANQAECgMIAwAAAA==.Nezukô:BAAANQADCgUICQAAAA==.',
Ni='Nienna:BAAANQAECgMIBgABNQAECgoKLgAKAB8dAA==.Nightwulf:BAAANQADCgIIAgAAAA==.Nikkikynz:BAAANQABCgIIAgAAAA==.Nikkisan:BAAANQAECgEIAQAAAA==.Nixk:BAAANQAECgYIEgAAAA==.',
No='Noapte:BAAANQAECgEIAQAAAA==.Noixi:BAABNQAECn8rAAMDAAgKRwtPFQAnAQADAAgKRwtPFQAnAQAPAAcKTAYU4wDUAAAAAA==.Noras:BAABNQAECn8aAAIgAAkKLxLyJgDqAQAgAAkKLxLyJgDqAQAAAA==.Nordicslayer:BAAANQAECgEIAQAAAA==.Notagnoblin:BAECNQAFFH8gAAICAAcKVSZ/AgA7AgACAAcKVSZ/AgA7AgA1AAQKfzoAAgIACgqmJj0CAGMDAAIACgqmJj0CAGMDAAAA.Notrick:BAAANQAECgUICwAAAA==.',
Nu='Nuffsaid:BAAANQADCgUIBgAAAA==.',
Ny='Nyko:BAAANQADCgUIBgAAAA==.',
Oa='Oaklyn:BAAANQADCgUIBQAAAA==.',
Ob='Obolisq:BAAANQADCgIIAgAAAA==.Obsidious:BAAANQAECgYICQAAAA==.',
Od='Oddsoul:BAAANQAECgIIAwAAAA==.',
Og='Ogrelurd:BAABNQAECn9OAAMGAAoK+B3VJgCaAgAGAAoK+B3VJgCaAgAdAAEKAABWPAAAAAAAAA==.',
Ol='Oliveia:BAAANQADCgQIBAAAAA==.',
Op='Opalfox:BAAANQADCgEIAQAAAA==.Ophelia:BAABNQAECn9HAAQNAAoKnCBdCwC2AQALAAgK0x+5QAADAgANAAYKHyFdCwC2AQAMAAIK6xKWVACBAAAAAA==.',
Or='Orakwa:BAABNQAECn8VAAMGAAkKoBGqjwD1AQAGAAkKoBGqjwD1AQAdAAQKshEfGwD1AAAAAA==.',
Os='Osteroth:BAAANQADCggIEQAAAA==.',
Pa='Pachez:BAAANQAECgIIAgAAAA==.Paladont:BAAANQAECgUIDwAAAA==.Pallinda:BAABNQAECn83AAMTAAoKyCDpEQAeAwATAAoKyCDpEQAeAwAHAAYKoQ4s6wBFAQAAAA==.Palmogant:BAAANQAECgYIEQAAAA==.Panztide:BAAANQADCgcICAABNQAECgoKLQAhAIISAA==.Pappyoblues:BAAANQAECgEIBAAAAA==.Patt:BAAANQADCgUIBQAAAA==.',
Pe='Pendulumlaw:BAACNQAFFH8RAAIGAAYK3whWFgDlAAAGAAYK3whWFgDlAAA1AAQKfzEAAgYACgpkGT1nAFoCAAYACgpkGT1nAFoCAAAA.Pennypacker:BAAANQAECgUICwABNQAECgoKLgAKAB8dAA==.Pepe:BAAANQADCgEIAQAAAA==.',
Ph='Phinn:BAABNQAECn8qAAIQAAcKkwnYTADYAAAQAAcKkwnYTADYAAAAAA==.Phoel:BAAANQADCgUIDAAAAA==.Phoopanchu:BAABNQAECn8XAAIJAAgKOQwaGQBYAQAJAAgKOQwaGQBYAQAAAA==.',
Pi='Pimikoh:BAAANQAECgQIBQAAAA==.Pinkbuns:BAABNQAECn8kAAIDAAgK2h2kCQA4AgADAAgK2h2kCQA4AgAAAA==.',
Pn='Pneuma:BAABNQAECn8eAAIaAAgKmRyNCADVAQAaAAgKmRyNCADVAQAAAA==.',
Po='Pollonius:BAAANQADCgQIBAAAAA==.Poncho:BAAANQADCgIIAgAAAA==.Popsy:BAAANQAECgUIBQAAAA==.',
Pr='Praxel:BAAANQAECgUIBQAAAA==.Prenton:BAABNQAECn86AAIGAAkKBxldXADWAQAGAAkKBxldXADWAQAAAA==.Prepotente:BAAANQAECgMIBQABNQAECgoKJgAhAMAeAA==.Prideflag:BAAANQADCggICAAAAA==.Priestin:BAAANQAECgMIBAAAAA==.Profundity:BAAANQAECgEIAQABNQAECgoKLgAKAB8dAA==.',
Ps='Psyduck:BAABNQAFFH8FAAIGAAUKfAszFwBpAQAGAAUKfAszFwBpAQABNQAFFAoKPgAHAGklAA==.',
Pu='Punie:BAABNQAECn8mAAIbAAgKfRZQVgAhAgAbAAgKfRZQVgAhAgAAAA==.Punkte:BAAANQAECgUIBwAAAA==.Puzzykat:BAAANQADCgYIBgAAAA==.',
Pv='Pvptankin:BAAANQAECgEIAQABNQAECggIEAAWAAAAAA==.',
['Pä']='Päg:BAAANQADCgEIAQABNQAECgoKSAAYALAdAA==.',
Qe='Qeini:BAABNQAECn8sAAIFAAgKUgyYBwA9AQAFAAgKUgyYBwA9AQAAAA==.',
Ra='Radrin:BAAANQADCgcIEwAAAA==.Rafoff:BAAANQAECgcIDAAAAA==.Ragnarax:BAABNQAECn8kAAIGAAoKeR+KKACSAgAGAAoKeR+KKACSAgAAAA==.Rahll:BAAANQADCgIIAgAAAA==.Raikami:BAAANQAECgQIBAAAAA==.Rancoramble:BAAANQAECgYIDAAAAA==.Randis:BAABNQAECn85AAIBAAgKIQ/tLgBfAQABAAgKIQ/tLgBfAQAAAA==.Raysonna:BAAANQAECgYIEgAAAA==.',
Re='Recapitator:BAAANQADCggICwAAAA==.Rengår:BAAANQAECgUIBQAAAA==.Reo:BAAANQAECgMIAwAAAA==.Reticent:BAAANQAECgYIDAAAAA==.Reversewally:BAAANQAECgcIEQAAAA==.Rexhà:BAAANQAECgQICQAAAA==.Rexiis:BAABNQAECn8mAAILAAkKZg4NeQBdAQALAAkKZg4NeQBdAQAAAA==.Reyth:BAAANQAECgQIDQAAAA==.',
Rh='Rhuby:BAABNQAECn82AAICAAgKLBbYOwBEAQACAAgKLBbYOwBEAQAAAA==.',
Ri='Rimos:BAAANQAECggIEAAAAA==.Riptîde:BAAANQAECgcIDAAAAA==.Rivening:BAAANQAECgQIDAAAAA==.',
Rk='Rk:BAAANQADCgYICAAAAA==.',
Ro='Rochelle:BAAANQAECgEIAQAAAA==.Rocknlock:BAABNQAECn8mAAILAAgK/wLRwQC6AAALAAgK/wLRwQC6AAAAAA==.Roeyth:BAAANQADCggICAAAAA==.Rokki:BAABNQAECn9BAAIPAAkKYgnd7ACxAQAPAAkKYgnd7ACxAQAAAA==.Roostor:BAAANQAECgEIAgAAAA==.Rosael:BAAANQAECgEIAQAAAA==.Roundhouse:BAABNQAECn8eAAImAAgKpBrlDQAZAgAmAAgKpBrlDQAZAgAAAA==.',
Ru='Rubbmytotems:BAAANQAECgYIEwAAAA==.Rubicôn:BAAANQABCgYICAABNQAFFAcIHAAPAK0ZAA==.Rubmyoysters:BAAANQADCgEIAQAAAA==.Ruleti:BAABNQAECn8tAAIEAAoKuRo1PwCtAgAEAAoKuRo1PwCtAgAAAA==.Rumí:BAAANQADCggJIgAAAA==.Rundeep:BAAANQABCgYICgAAAA==.Russell:BAAANQADCgcIFAAAAA==.',
Ry='Ryukia:BAAANQAECgEIAQAAAA==.',
Sa='Sabado:BAAANQAECgMIBgAAAA==.Safewerd:BAEBNQAECn8VAAIJAAgKrAsIIgDqAAAJAAgKrAsIIgDqAAAAAA==.Saitama:BAAANQAECgYICgABNQAECgkJMgAGACoWAA==.Sangriel:BAABNQAECn8nAAICAAkKyA+rZwBUAQACAAkKyA+rZwBUAQAAAA==.Saraceleste:BAAANQAECgYICgAAAA==.Sarafinmae:BAAANQAECgUICAAAAA==.Sarahfi:BAAANQAECgIJAgABNQAECgcIGwAiABsXAA==.Saralanna:BAABNQAECn81AAILAAoKhQ1XUgDKAQALAAoKhQ1XUgDKAQAAAA==.Sarasophie:BAAANQADCggIIAAAAA==.Sarefina:BAAANQAECgQIDAAAAA==.Sathenazarke:BAABNQAECn8WAAIRAAoKXx6zCADsAgARAAoKXx6zCADsAgABNQAFFAcIFwAeAOAjAA==.',
Sc='Schism:BAAANQAECgMIBAAAAA==.Schmingus:BAAANQADCgIIAgAAAA==.Scoban:BAACNQAFFH8QAAITAAYKuBnwCgCuAQATAAYKuBnwCgCuAQA1AAQKfxsAAhMACQoRHng2AIoCABMACQoRHng2AIoCAAAA.',
Se='Seaworld:BAABNQAECn8mAAQhAAoKwB6RBADOAgAhAAkKwB6RBADOAgAQAAcKMRCwTQDVAAAiAAEKJhUsaAA0AAAAAA==.Selènè:BAAANQAECggICgABNQAFFAQICAAOAOgaAA==.Seraphine:BAAANQABCgIIAgAAAA==.Seraphnite:BAAANQADCgIIAgAAAA==.Seriousjakk:BAAANQADCgEIAQABNQADCgQIBwAWAAAAAA==.',
Sh='Shadeebear:BAAANQAECgEIAQAAAA==.Shadowtax:BAAANQAECgEIBQAAAA==.Shan:BAABNQAECn8XAAIlAAgKsAmnkgBZAQAlAAgKsAmnkgBZAQAAAA==.Shaohlin:BAAANQAECgEIAQAAAA==.Shaqfu:BAAANQADCgcIFAAAAA==.Shavemybush:BAAANQADCgcJBwAAAA==.Shayy:BAABNQAECn89AAIFAAoKDhnnAwCeAgAFAAoKDhnnAwCeAgAAAA==.Sheve:BAAANQAECgQIDAABNQAECgkJNQAlAEkjAA==.Shevee:BAAANQAECgMIBQABNQAECgkJNQAlAEkjAA==.Shigure:BAABNQAECn8jAAMDAAoKpwqHFgBKAQAPAAoKrAgW0wDgAQADAAcKOQqHFgBKAQAAAA==.Sholin:BAABNQAECn8fAAImAAkKmyCgCACfAgAmAAkKmyCgCACfAgAAAA==.Shomea:BAAANQAECgUIDAAAAA==.Shugz:BAAANQADCgcIEwAAAA==.Shumai:BAAANQAECgcIDgAAAA==.',
Si='Sigons:BAAANQABCgYICAAAAA==.Sikotick:BAABNQAECn8kAAIKAAkKaRdRLQCxAQAKAAkKaRdRLQCxAQAAAA==.Sikxrapture:BAAANQADCgYIBgAAAA==.Siliconista:BAACNQAFFH8JAAIPAAQKORdDJADdAAAPAAQKORdDJADdAAA1AAQKf00AAw8ACgrbJEgVAH4DAA8ACgooJEgVAH4DAAMABwrgJKkLAAUCAAAA.Simbelmyne:BAAANQAECgUIBgABNQAECgoKLgAKAB8dAA==.Sinabunz:BAAANQAECgEIAQAAAA==.',
Sk='Skitrit:BAAANQAECgEIAQABNQAECgoKLQAEALkaAA==.Skyjin:BAAANQADCgYJCQAAAA==.',
Sl='Slammurai:BAAANQADCgcICwAAAA==.Slew:BAAANQAECgMIBwAAAA==.Slippie:BAAANQAECgEIAQAAAA==.Slippinwater:BAABNQAECn81AAIHAAoKaCSsHQBMAwAHAAoKaCSsHQBMAwAAAA==.Sllew:BAABNQAECn9OAAMBAAoK3hxOGQD1AgABAAkKax1OGQD1AgAYAAoK6xVhIAA4AgAAAA==.Slylent:BAAANQAECgIIAQAAAA==.Slyyce:BAABNQAECn8UAAIGAAkKyRXhnADUAQAGAAkKyRXhnADUAQAAAA==.',
Sm='Smoulder:BAAANQAECgIIBQAAAA==.',
Sn='Snigles:BAABNQAECn8kAAIfAAoKbQlTKgBxAQAfAAoKbQlTKgBxAQAAAA==.Snowlily:BAAANQAECgQIDAABNQAECgoKKQAUAPYRAA==.Snurp:BAAANQAECgUIDQABNQAECgoKKQAZAPYgAA==.',
So='Softnsquishy:BAAANQAECgEIBAAAAA==.Solmarrow:BAABNQAECn8YAAQDAAcKmggwGAA4AQADAAcKRggwGAA4AQAPAAQKaAQchAG8AAAnAAEKFAbKDQA0AAAAAA==.',
Sp='Spagoni:BAAANQADCggICAAAAA==.Spanksbar:BAAANQADCggIFAAAAA==.Spartos:BAABNQAECn8tAAMGAAgKxBvhTAAGAgAGAAgKxBvhTAAGAgAcAAIKUA/lMwBhAAAAAA==.Spazzlixx:BAAANQAECgUIBQAAAA==.Speedy:BAABNQAECn8mAAIEAAYKwwMDCQH1AAAEAAYKwwMDCQH1AAAAAA==.Speedyspeed:BAAANQADCgQIBQAAAA==.Spokes:BAAANQADCgYICQABNQAECggIAwAWAAAAAA==.Sposi:BAABNQAECn8gAAMCAAkKxiErGwDVAgACAAkKxiErGwDVAgAYAAIKzwzujgBwAAAAAA==.Sprinkle:BAAANQAECggJCQABNQAECggIEgAWAAAAAA==.',
Sr='Srimrithyu:BAAANQADCgYIEwAAAA==.',
Ss='Sselionn:BAAANQAECgUIEAAAAA==.',
St='Stomps:BAABNQAECn8jAAIcAAkK/hccEAAnAgAcAAkK/hccEAAnAgAAAA==.Stoneweaver:BAAANQADCgYIBgABNQAECgcIKQAKAMsbAA==.Stonezef:BAABNQAECn8lAAIPAAkKkAzf+ACbAQAPAAkKkAzf+ACbAQAAAA==.',
Su='Suffocation:BAAANQADCgYIBwAAAA==.Sumasuka:BAAANQADCgcIDQAAAA==.Sungdihhwoo:BAAANQADCgQIBwAAAA==.Susann:BAABNQAECn8pAAIlAAkKyxZyaQDQAQAlAAkKyxZyaQDQAQAAAA==.',
Sy='Syravia:BAAANQAECgYIEwAAAA==.',
['Sò']='Sòlushan:BAAANQAECgEIAQABNQAECgoKKwAHAKEbAA==.',
Ta='Tahoa:BAAANQABCgQIBwAAAA==.Talarin:BAAANQAECgIIBQAAAA==.Talayro:BAAANQADCgIIAgAAAA==.Tameka:BAABNQAECn83AAIEAAoKHhrFNQDKAgAEAAoKHhrFNQDKAgAAAA==.Tardis:BAAANQAECgcIBwABNQAECgoKJgAOAOcXAA==.Tatersdh:BAEANQAECgYIDAABNQAFFAcIIAACAFUmAA==.Tavinrayn:BAAANQAECgYIDwAAAA==.',
Te='Teera:BAAANQAECgIIAgABNQAECgoKIAAQADsSAA==.Tekesh:BAABNQAECn8XAAIEAAgKxSQMPgCwAgAEAAgKxSQMPgCwAgAAAA==.Teksham:BAAANQADCgYIEgAAAA==.Telarin:BAABNQAECn8yAAMEAAgKzxzhXwDvAQAEAAgKQBzhXwDvAQAoAAcKdxPABwDtAQAAAA==.Tenebrefigo:BAAANQAECgEIAQABNQAECgoKQwAcAF8mAA==.Teremup:BAAANQAECgIIAQAAAA==.Tezrian:BAAANQADCgYJCgABNQAECgoKJgAhAMAeAA==.',
Th='Thebigdawg:BAAANQAECgEIAQAAAA==.Theladyboy:BAABNQAECn8pAAMaAAgKoBeDDABwAQAaAAgKoBeDDABwAQAXAAMKtgrieQCRAAAAAA==.Thomss:BAABNQAECn8xAAIEAAkKdBO5awA7AgAEAAkKdBO5awA7AgAAAA==.Thraiene:BAAANQAECgUIEgABNQAECgkJFQAMAMASAA==.Thrawn:BAAANQAECgMIAwAAAA==.Throhk:BAAANQADCgcIFQAAAA==.Thrumgar:BAAANQAECgEIAgAAAA==.',
Ti='Tiamut:BAAANQADCgQIBAAAAA==.Tigercla:BAAANQADCggICAAAAA==.Tigerliley:BAAANQAECgQIDAABNQAECgoKKQAUAPYRAA==.Tinneas:BAAANQAECgEIAQAAAA==.',
To='Tomás:BAABNQAECn8cAAIbAAgKwQxVjACFAQAbAAgKwQxVjACFAQAAAA==.Topg:BAAANQADCggIEwAAAA==.Torstai:BAABNQAECn8aAAINAAgKjgmwDwBTAQANAAgKjgmwDwBTAQAAAA==.Totemic:BAAANQAECgEIAQAAAA==.Toxic:BAABNQAECn9DAAMfAAoKSSF3CgDNAgAfAAkKnB93CgDNAgAeAAYKsR1QOQDwAQAAAA==.Toyun:BAAANQADCgMIAwAAAA==.',
Tr='Trap:BAAANQADCgQIBAAAAA==.Trueshöt:BAABNQAECn8uAAMZAAkKIxX0MADGAQAZAAgKpBH0MADGAQAoAAgKcxTUBwB4AQAAAA==.',
Ts='Tserendolgor:BAAANQAECgYIDgABNQAECgoKJgAhAMAeAA==.',
Tu='Tukker:BAAANQADCgYIBgABNQAECgoKQwAcAF8mAA==.',
Ty='Tyedindis:BAAANQAECgEIAgAAAA==.Tyresious:BAABNQAECn8cAAIHAAoKAhZslwD1AQAHAAoKAhZslwD1AQAAAA==.',
Ut='Utherrex:BAAANQAECgMIBwABNQAECgkJJgALAGYOAA==.',
Va='Vahaghn:BAABNQAECn9FAAIGAAoKUSMAEwBwAwAGAAoKUSMAEwBwAwAAAA==.Valcerus:BAAANQAECgUIDgAAAA==.Valedus:BAABNQAECn8xAAIHAAoK1SFJOQDrAgAHAAoK1SFJOQDrAgAAAA==.',
Ve='Veelete:BAAANQADCgcICwABNQAECggILAATADAjAA==.Vengeancedh:BAABNQAECn8ZAAICAAgK9Bs+IQDhAQACAAgK9Bs+IQDhAQAAAA==.Veroya:BAAANQAECgEIAgAAAA==.Vespra:BAAANQADCgYIBgAAAA==.Veylara:BAAANQADCgIIAgAAAA==.',
Vi='Viix:BAAANQADCgUIBQAAAA==.Vinno:BAAANQAECgEIBQAAAA==.Virr:BAABNQAECn8bAAIiAAcKGxe2JABIAQAiAAcKGxe2JABIAQAAAA==.',
Vo='Volcker:BAABNQAECn85AAIIAAgKegl8LQD3AAAIAAgKegl8LQD3AAAAAA==.Volthreal:BAAANQADCggICAABNQAECgoKQwAcAF8mAA==.Voltuk:BAABNQAECn9DAAQcAAoKXyb6AABsAwAcAAoKXyb6AABsAwAdAAMKiQrgJQCAAAAGAAEK2wmIHQE4AAAAAA==.',
Wa='Wadoralock:BAAANQAECggICwABNQAFFAMICAAEAJgIAA==.Walrustusk:BAAANQAECgcICQAAAA==.Wariius:BAAANQAECgIIAwAAAA==.Warwarb:BAAANQAECgcIDQABNQAECgoKMgALAJEVAA==.Wasabijack:BAAANQADCgcJCgAAAA==.Waterliliy:BAABNQAECn8pAAQUAAoK9hGWKADkAQAUAAoK9hGWKADkAQAFAAIKPQuSIABdAAAOAAIKhAEz9wA/AAAAAA==.Wayhn:BAAANQADCgYIBwAAAA==.',
Wh='Whatcrap:BAAANQAECgIIAgAAAA==.Whathehay:BAAANQADCgQIBAAAAA==.',
Wi='Wickedmon:BAAANQADCgMIAwAAAA==.Windfurypie:BAAANQADCggICQAAAA==.',
Wo='Wolfbish:BAAANQAECgUICgAAAA==.Wongidan:BAAANQAECggIDgAAAA==.',
['Wý']='Wýler:BAAANQADCgIIAgABNQADCggICAAWAAAAAA==.',
Xa='Xacious:BAABNQAECn8YAAIOAAgK9xHPcABxAQAOAAgK9xHPcABxAQAAAA==.',
Xh='Xhuri:BAAANQADCgYIBgAAAA==.',
['Xë']='Xëna:BAABNQAECn8pAAMKAAcKyxsxJQCsAQAKAAcKyxsxJQCsAQAQAAIKSwSCpwBJAAAAAA==.',
Yo='Yorllik:BAAANQAECgUIDgAAAA==.',
Yt='Yt:BAABNQAECn8fAAIVAAoKzhJzGADdAQAVAAoKzhJzGADdAQAAAA==.',
Yu='Yueguanghua:BAAANQADCgUIBQAAAA==.Yuzuha:BAAANQADCgIIAgAAAA==.',
Ze='Zeddicus:BAAANQAECgQIBQAAAA==.Zendragon:BAABNQAECn83AAMIAAoK+iN4BQD9AgAIAAoK+iN4BQD9AgAHAAcK2w1T7gDwAAABNQAECgoKQwAcAF8mAA==.',
Zh='Zhorvan:BAAANQADCggIGQABNQAECggIGgAIAEQHAA==.',
Zi='Zilstar:BAAANQAECgUIBgAAAA==.',
Zo='Zoomy:BAAANQADCggICAAAAA==.',
Zu='Zuggondeez:BAAANQAECgUIBQABNQAECggIJQAEAF0VAA==.Zuggsalot:BAAANQAECgIIAQAAAA==.',
['Âr']='Ârtëmïs:BAABNQAECn8WAAIEAAcKIQfj4AA/AQAEAAcKIQfj4AA/AQAAAA==.',
['Åp']='Åpollo:BAACNQAFFH8MAAIJAAYK8hcWBACjAQAJAAYK8hcWBACjAQA1AAQKfx8AAgkACgqIG9wQAHECAAkACgqIG9wQAHECAAAA.',
['Ðe']='Ðeja:BAAANQAECgYICQABNQAECgcIGwAiABsXAA==.',
['Òm']='Òmgitsbwòng:BAABNQAECn8bAAIZAAgKGgq0NACoAQAZAAgKGgq0NACoAQABNQAECggIDgAWAAAAAA==.',
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
