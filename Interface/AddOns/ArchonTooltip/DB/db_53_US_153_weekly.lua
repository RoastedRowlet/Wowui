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
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Absofsteels:BAABNQAECn8nAAMBAAgK7xSXLACDAQABAAgK7xSXLACDAQACAAMKtQcDsABrAAAAAA==.',
Ac='Acaric:BAABNQAECn8gAAIDAAoK9gZpFwBAAQADAAoK9gZpFwBAAQAAAA==.',
Ad='Adrielon:BAAANQADCggIEQAAAA==.Adøra:BAACNQAFFH8IAAIEAAMKmAgRGgDCAAAEAAMKmAgRGgDCAAA1AAQKf1kAAgQACgrMHuAlAP8CAAQACgrMHuAlAP8CAAAA.',
Ae='Aegea:BAAANQAECgIIAgABNQAECgoKPQAFAA4ZAA==.',
Ag='Agumon:BAABNQAECn8aAAICAAgKPxx/LQCdAQACAAgKPxx/LQCdAQAAAA==.',
Ai='Aircann:BAAANQADCggICAAAAA==.',
Al='Alchemist:BAAANQADCgUICQAAAA==.Alistair:BAAANQADCgUIBQAAAA==.Alluriel:BAAANQAECgIIBAAAAA==.Alonas:BAAANQAECgYICAABNQAECgkJNgAGAAUZAA==.Altharoth:BAABNQAECn8xAAMHAAoKFBv/XACBAgAHAAoKFBv/XACBAgAIAAEKzAypcQAuAAAAAA==.Altherion:BAAANQAECgIIAQAAAA==.',
Am='Amique:BAAANQABCgIIAgAAAA==.Amira:BAAANQADCgYIDwABNQAFFAYIDAAJAPIXAA==.Amorfox:BAAANQADCgcIBwAAAA==.Amormage:BAAANQAECgUIEAAAAA==.Amphitrite:BAAANQAECggIEAABNQAFFAYIDAAJAPIXAA==.',
An='Anabolicrage:BAAANQAECgIIAgAAAA==.Angmar:BAAANQAECgEIAQABNQAECgoKLwAKAB8dAA==.Anteiku:BAAANQAECgIIBAAAAA==.Anteikudeath:BAAANQADCgEIAQAAAA==.',
Ap='Applemoose:BAABNQAECn8tAAQLAAoKaB9tXAC/AQALAAkKLCBtXAC/AQAMAAIKhBgNUQCMAAANAAEK8BVmKQBGAAAAAA==.',
Ar='Aragrar:BAAANQAECgQIBQAAAA==.Arauial:BAABNQAECn8uAAIOAAoK0iCsNACVAgAOAAoK0iCsNACVAgAAAA==.Arcanis:BAABNQAECn86AAMPAAoKpBeLqAAxAgAPAAoKbxeLqAAxAgADAAIKBxftLwCBAAAAAA==.Aribella:BAACNQAFFH8HAAIEAAQKSQmRGQDHAAAEAAQKSQmRGQDHAAA1AAQKfy8AAgQACgqrEvVgAFUCAAQACgqrEvVgAFUCAAAA.Arizae:BAAANQAECgUIDgAAAA==.Arizann:BAABNQAECn8vAAMKAAoKHx1CCQBAAwAKAAoKHx1CCQBAAwAQAAYKMxDcYwA+AQAAAA==.Arobotev:BAABNQAECn88AAMRAAkKehEADACaAQARAAkKehEADACaAQASAAEK7QH9PwAgAAAAAA==.',
As='Astaren:BAAANQADCgcIEAAAAA==.Astiria:BAAANQAECgMIAwAAAA==.Asuran:BAABNQAECn8ZAAIGAAkK0RXmegCVAQAGAAkK0RXmegCVAQAAAA==.',
At='Atiya:BAACNQAFFH8HAAITAAUK7RJwDACFAQATAAUK7RJwDACFAQA1AAQKfzUAAhMACgo8Im8EANoDABMACgo8Im8EANoDAAAA.',
Az='Azaris:BAABNQAECn8hAAMUAAoK6RMIIwAaAgAUAAkK1xMIIwAaAgAOAAIK3wdQ9gBBAAAAAA==.',
Ba='Babykraze:BAABNQAECn8bAAIEAAcK1w3poQDCAQAEAAcK1w3poQDCAQAAAA==.Backshotz:BAAANQADCgMIAQAAAA==.Baelrog:BAABNQAECn8aAAMTAAgK4gYAmwDtAAATAAgK4gYAmwDtAAAHAAUKVgQsPAHAAAAAAA==.Baiene:BAABNQAECn8VAAQMAAkKwBLICQAqAQAMAAgKwBLICQAqAQALAAQKgAZ6DAGzAAANAAIKUAtsIQBuAAAAAA==.Baiken:BAAANQAECgEIAQAAAA==.Baldheadelf:BAAANQAECggICAAAAA==.Bandalar:BAABNQAECn8lAAIVAAgKYxdSIwAvAgAVAAgKYxdSIwAvAgAAAA==.Banerino:BAAANQADCgIIAgAAAA==.Barkathemoon:BAAANQABCggICAABNQAECgIIAgAWAAAAAA==.Barnabust:BAAANQAECgYICwAAAA==.Barricaded:BAAANQAECgIIAgAAAA==.Bashems:BAAANQAECgEJAQAAAA==.Baston:BAAANQADCgIIAgAAAA==.',
Be='Bearypie:BAAANQAECggICAAAAA==.Beastums:BAABNQAECn8+AAIEAAkK9BWXXgBaAgAEAAkK9BWXXgBaAgAAAA==.',
Bi='Bigbôotyjudy:BAAANQADCgIIAgAAAA==.Bigchungus:BAAANQADCggICQAAAA==.Bingbong:BAAANQADCgEIAQAAAA==.',
Bl='Blacken:BAAANQADCgQIBgAAAA==.Bleak:BAAANQADCgQIBAAAAA==.Blindmonk:BAAANQAECggIAwAAAA==.Blite:BAAANQADCgcIFAAAAA==.Bloodmary:BAABNQAECn8lAAIHAAoKEAxJmwCWAQAHAAoKEAxJmwCWAQAAAA==.Bloodor:BAAANQAECgYIBgAAAA==.Bloöm:BAABNQAECn9GAAIKAAoKJyMzBQBvAwAKAAoKJyMzBQBvAwAAAA==.Bluetsunami:BAABNQAECn8jAAIXAAcK+QK+aACCAAAXAAcK+QK+aACCAAAAAA==.',
Bm='Bmaazi:BAABNQAECn8pAAMSAAgK2RqjEAD9AQASAAgK2RqjEAD9AQARAAUKYgRMLADAAAAAAA==.',
Bo='Bonerina:BAAANQAECgQICQAAAA==.Boomadk:BAACNQAFFH8KAAIYAAUKyRKyCgAjAQAYAAUKyRKyCgAjAQA1AAQKf0sAAhgACgoSJGwKAEcDABgACgoSJGwKAEcDAAAA.Boppybone:BAAANQAECgIIAgAAAA==.',
Br='Bradburn:BAAANQADCgYIDAAAAA==.Bradkink:BAAANQAECgEIAQAAAA==.Brasserz:BAABNQAECn8oAAMEAAkK0xPTswBKAQAEAAkK0xPTswBKAQAZAAEKAABJlAAsAAAAAA==.Breezybone:BAABNQAECn83AAIDAAoKHB0cBADzAgADAAoKHB0cBADzAgAAAA==.Briaela:BAAANQADCgIIAgAAAA==.Brice:BAAANQADCgYICgAAAA==.Briochebun:BAABNQAECn8cAAIHAAkKRxUYeQA6AgAHAAkKRxUYeQA6AgAAAA==.',
Bw='Bwangifer:BAABNQAECn89AAIaAAkKYByJBgA3AgAaAAkKYByJBgA3AgAAAA==.',
['Bë']='Bëcky:BAABNQAECn86AAQHAAoKxyWwBABxAwAHAAoKxyWwBABxAwATAAYKYxL4kQBpAQAIAAIKWyEUOwDAAAAAAA==.',
Ca='Calabera:BAAANQADCggIDgAAAA==.Caloren:BAABNQAECn8qAAIEAAoKliRWDQB0AwAEAAoKliRWDQB0AwABNQAECgoKNgAVAMgaAA==.Camerarius:BAAANQAECgEIAQAAAA==.Cannala:BAAANQADCgcIFAAAAA==.Cargae:BAAANQADCgcIFAAAAA==.Caso:BAAANQADCgMIBAABNQAECgUICwAWAAAAAA==.',
Ce='Cellysia:BAABNQAECn82AAMOAAoKSAS4nAAGAQAOAAoKSAS4nAAGAQAUAAIKFgPCdQA7AAAAAA==.Ceres:BAABNQAECn8+AAIMAAkK4BbLBAC7AQAMAAkK4BbLBAC7AQAAAA==.Cesara:BAABNQAECn9KAAMUAAoKsRryEQDfAgAUAAoKsRryEQDfAgAOAAMKFwieyACYAAAAAA==.',
Ch='Chal:BAABNQAECn8rAAIHAAgK1Al+6QBJAQAHAAgK1Al+6QBJAQAAAA==.Chaplin:BAAANQAECgMIBAABNQAECggIHQAbAMEMAA==.Chbribs:BAAANQAECgcIEAAAAA==.Chestypanda:BAAANQADCgQIBAAAAA==.Chillypepper:BAAANQAECgQIBAAAAA==.Chiptewth:BAAANQABCgYICQAAAA==.Chiron:BAAANQADCgEIAQAAAA==.',
Co='Coldsteel:BAAANQADCggIKAAAAA==.Columbina:BAABNQAECn8pAAIVAAoKIhWjKAD/AQAVAAoKIhWjKAD/AQAAAA==.Cooperhowerd:BAAANQADCgcIEgAAAA==.Corky:BAAANQADCgEIAQABNQAECgoKLwAKAB8dAA==.Corn:BAAANQADCgIIAgABNQAECgcIEAAWAAAAAA==.',
Cp='Cptredbeardd:BAAANQADCgYIDgAAAA==.',
Cr='Crackmonger:BAACNQAFFH8FAAIGAAIKLxXkLACWAAAGAAIKLxXkLACWAAA1AAQKfyMAAgYACQquGh9ZAIACAAYACQquGh9ZAIACAAAA.Crackundead:BAACNQAFFH8IAAIYAAMKJA75FgCIAAAYAAMKJA75FgCIAAA1AAQKfz0AAhgACgrTGechAH4CABgACgrTGechAH4CAAAA.Crapdragon:BAAANQAECgUIBgAAAA==.',
Cy='Cyphr:BAABNQAECn88AAIKAAkKuB41EgClAgAKAAkKuB41EgClAgAAAA==.Cyrinx:BAABNQAECn8eAAMKAAoKngt7TwC9AAAKAAgK9AV7TwC9AAAQAAgKBQTndQBhAAAAAA==.',
Da='Daen:BAAANQADCggICAAAAA==.Dagravytrain:BAAANQAECgUIBgAAAA==.Dain:BAAANQADCgYIDAAAAA==.Dalend:BAABNQAECn8gAAMGAAoKLRxKUAAOAgAGAAoKyxtKUAAOAgAcAAIKUhs0NACVAAAAAA==.Damerot:BAABNQAECn8xAAMdAAoK2hVTCQAMAgAdAAoK2hVTCQAMAgAcAAEK2gcOSgAoAAAAAA==.Dangerous:BAABNQAECn8lAAIeAAgKIRIEGABoAQAeAAgKIRIEGABoAQAAAA==.Danpal:BAAANQADCggICQAAAA==.Dansharo:BAAANQADCgMIAwAAAA==.Darc:BAAANQAECgQIBAAAAA==.Darnnix:BAAANQAECgUICwAAAA==.Darthrevin:BAABNQAECn8iAAMfAAkKPA5EJACmAQAfAAkKOw1EJACmAQAeAAYKMAhnYAAzAQAAAA==.Dawnsingers:BAAANQADCggIFgAAAA==.',
De='Deadbeard:BAABNQAECn9dAAQYAAoK0SXhAgC4AwAYAAoK0SXhAgC4AwACAAcKpB6xSQDRAQABAAQKASTDeAA3AQAAAA==.Deathbash:BAAANQADCgEIAQAAAA==.Deathdream:BAAANQAECgUIBgAAAA==.Deathrar:BAAANQADCgcICwAAAA==.Deathviix:BAAANQAECgUICgAAAA==.Debased:BAABNQAECn8vAAIBAAoKexR0HAAAAgABAAoKexR0HAAAAgAAAA==.Demini:BAAANQADCgYIDQAAAA==.Demisê:BAABNQAECn9YAAICAAoKExyhGABAAgACAAoKExyhGABAAgAAAA==.Demonn:BAAANQAECggIEwAAAA==.Derbygirl:BAAANQADCgYIDQAAAA==.Desperation:BAABNQAECn8WAAIIAAkKOhNUKACbAQAIAAkKOhNUKACbAQAAAA==.Desso:BAABNQAECn8cAAIgAAkK9xIvHQC6AQAgAAkK9xIvHQC6AQAAAA==.Detraz:BAAANQABCgEIAQAAAA==.Devilskin:BAAANQADCgUICgAAAA==.',
Di='Dillinger:BAAANQAECggIDQAAAA==.Dingodgaf:BAABNQAECn9GAAIHAAkK6Qg5wwBNAQAHAAkK6Qg5wwBNAQAAAA==.',
Dj='Djinnjuicy:BAABNQAECn8dAAIPAAcKpQivHAFcAQAPAAcKpQivHAFcAQAAAA==.',
Do='Dodo:BAAANQAECgQICgAAAA==.Dorianmyth:BAABNQAECn8aAAIIAAgKRAecOAAnAQAIAAgKRAecOAAnAQAAAA==.',
Dr='Dragonshammy:BAAANQADCgMIAwABNQAECgoKPgATAJEhAA==.Drazzi:BAAANQAECgEIAQAAAA==.Dreamclaw:BAABNQAECn8pAAMhAAoKhw8RGABXAQAhAAoKnw4RGABXAQAiAAQKkwpgRQCeAAAAAA==.Drendar:BAAANQAECgYIBgAAAA==.Drippindots:BAACNQAFFH8IAAMLAAQKIBstKgC1AAALAAMKiR8tKgC1AAAMAAEKThLoEQBKAAA1AAQKf0kAAwsACgrqInoLAHEDAAsACgqSInoLAHEDAAwAAQr8JPIgAG0AAAAA.Driztette:BAAANQAECgYICgAAAA==.Drnewport:BAAANQADCggIEwAAAA==.Drokash:BAAANQAECgYIBgAAAA==.Drystine:BAABNQAECn8hAAIXAAkKqRBMTABuAQAXAAkKqRBMTABuAQAAAA==.',
Dy='Dyronebiggum:BAAANQADCggIDAAAAA==.Dyxie:BAAANQAECgIIAgAAAA==.',
['Dí']='Dín:BAAANQAECgcIEQAAAA==.',
Ec='Ectharienne:BAAANQABCgMIAwAAAA==.',
Ee='Eedeeweewee:BAAANQADCgcIFAAAAA==.',
Eg='Eggs:BAAANQADCgEIAQAAAA==.',
Ei='Eillaura:BAABNQAECn9EAAIOAAoKfxu8PgA/AgAOAAoKfxu8PgA/AgAAAA==.',
El='Electroshokk:BAAANQAECgIIAgABNQAECgQIBQAWAAAAAA==.Elemag:BAAANQAECgcICQAAAA==.Eleredra:BAAANQADCgYIBgABNQAECgoKLQAUALsUAA==.Elipsis:BAACNQAFFH8IAAIOAAQK6Bq3GQAoAQAOAAQK6Bq3GQAoAQA1AAQKfzYAAg4ACgqiJFcHAIoDAA4ACgqiJFcHAIoDAAAA.Elm:BAABNQAECn8kAAMQAAoK2hIiQQD0AQAQAAoK2hIiQQD0AQAKAAIK6gxuaABjAAAAAA==.Elybella:BAAANQADCgMIAwABNQAFFAUICAASAEsWAA==.Elycia:BAAANQAECgYIBwABNQAFFAUICAASAEsWAA==.Elyenora:BAACNQAFFH8IAAISAAUKSxbWCgBgAQASAAUKSxbWCgBgAQA1AAQKfy0AAhIACgrxFw8WAFUCABIACgrxFw8WAFUCAAAA.Elylbrook:BAAANQADCgIIAgAAAA==.',
En='Enquea:BAAANQAECgYICgABNQAECgoKLwAKAB8dAA==.Enricco:BAAANQAECgEIAQAAAA==.',
Er='Eraeste:BAAANQABCgQIAwAAAA==.Ereko:BAABNQAECn8uAAIEAAkK7gzUjgCZAQAEAAkK7gzUjgCZAQAAAA==.Eriss:BAABNQAECn8qAAIPAAoK5hClawDbAQAPAAoK5hClawDbAQAAAA==.Erythorbic:BAABNQAECn8zAAMLAAkK4hp0WgDFAQALAAgKDhl0WgDFAQAMAAMKJBzeFgCmAAAAAA==.',
Es='Estralage:BAAANQADCgUICwAAAA==.',
Ev='Evictor:BAAANQAECgEIAQABNQAECgoKHQAgAHYTAA==.',
Fa='Fanaticism:BAAANQAECgMIAwAAAA==.Fangs:BAAANQAECggIDgABNQAECgkJHQAMAMUZAA==.Faranth:BAABNQAECn8lAAIEAAkKVBrBUAArAgAEAAkKVBrBUAArAgAAAA==.Fatman:BAAANQAECgIIBQABNQAECgcICQAWAAAAAA==.',
Fe='Feer:BAAANQADCgQICAAAAA==.Feldron:BAAANQAECggIEQAAAA==.',
Ff='Ffugher:BAAANQAECgUICgAAAA==.Ffugme:BAABNQAECn8yAAMIAAoKlQkwOAAqAQAIAAoKVAkwOAAqAQAHAAYKiQVkGgHCAAAAAA==.Ffugnutz:BAAANQADCgQIBAAAAA==.Ffugoff:BAABNQAECn8dAAIbAAYK+Au1igD3AAAbAAYK+Au1igD3AAAAAA==.Ffugturd:BAABNQAECn8qAAIEAAkKoxB7mwB9AQAEAAkKoxB7mwB9AQAAAA==.Ffugyou:BAAANQADCggICwAAAA==.',
Fi='Finnian:BAABNQAECn8uAAITAAkKWRM3SADyAQATAAkKWRM3SADyAQAAAA==.Fio:BAAANQAECgYICQAAAA==.Firiona:BAABNQAECn8qAAMOAAoK2xywHwDhAgAOAAkKHBywHwDhAgAUAAUKDRRkPQC7AAABNQAECgoKLAAhACsgAA==.',
Fl='Flinn:BAAANQADCgIIAgAAAA==.Flowers:BAABNQAECn8wAAIVAAcKrR+FIABJAgAVAAcKrR+FIABJAgAAAA==.Fläva:BAAANQAECgcIDAAAAA==.',
Fo='Foot:BAAANQADCgYICgAAAA==.Forfuncasual:BAABNQAECn8iAAIjAAkKJxyABQCTAgAjAAkKJxyABQCTAgAAAA==.Foxhound:BAABNQAECn8qAAIgAAgKsgzMKwA7AQAgAAgKsgzMKwA7AQAAAA==.',
Fr='Fracture:BAAANQADCggICAABNQAECggINAAkAFgJAA==.Fresca:BAAANQADCgEIAQAAAA==.Friendlyhoss:BAAANQADCgIIAgAAAA==.Frostypie:BAAANQADCggIEAAAAA==.',
Fu='Funkyfungi:BAAANQAECgIIAgAAAA==.Furyswarm:BAAANQAECggIBgAAAA==.',
['Fö']='Föx:BAAANQADCgYIBgAAAA==.',
Ga='Gaius:BAAANQAECgQICAABNQAECgUIBQAWAAAAAA==.Gawdcomplex:BAABNQAECn8bAAITAAcKYQzHiwB5AQATAAcKYQzHiwB5AQAAAA==.',
Ge='Gernaj:BAAANQADCgcICwAAAA==.',
Gh='Ghostfrudge:BAAANQADCggICAAAAA==.Ghostfudge:BAABNQAECn80AAQIAAoK1htkDgC1AgAIAAkKtB9kDgC1AgAHAAIKqwE8uQEZAAATAAEKywCaEwEJAAAAAA==.Ghostlyfudge:BAAANQAECgMIBAAAAA==.',
Gi='Ginny:BAABNQAECn8iAAIIAAkKyQldLAAUAQAIAAkKyQldLAAUAQAAAA==.Ginsan:BAAANQADCgEIAQAAAA==.Ginthalos:BAAANQAECgMIAwAAAA==.',
Go='Golaru:BAAANQABCgIIAgAAAA==.',
Gr='Gramthyr:BAAANQADCgcIFAAAAA==.Grep:BAAANQADCgMIAwAAAA==.Greygor:BAABNQAECn8VAAIdAAYKHwXmJQB6AAAdAAYKHwXmJQB6AAAAAA==.Grotok:BAAANQAECgIIAgABNQAECggIJQAEAF0VAA==.',
Gu='Gumer:BAABNQAECn8pAAMlAAoKEQ/vmwBAAQAlAAkKrAzvmwBAAQAbAAcKAwUj7wC4AAAAAA==.Gurgatron:BAABNQAECn8mAAMeAAoK7BI0DQD5AQAeAAoK7BI0DQD5AQAjAAIK4QX4GABVAAABNQAECgoKSwAcAGMmAA==.Guulen:BAAANQADCgIIAgAAAA==.',
['Gá']='Gárd:BAAANQAECgYIBgAAAA==.',
Ha='Halygos:BAAANQAECgQIBwAAAA==.Hariffug:BAAANQADCgcIBwAAAA==.Hasklaufien:BAABNQAECn8VAAMdAAkK2RkICgAvAgAdAAgKkBsICgAvAgAGAAMKKxGQEgG3AAAAAA==.',
He='Healinside:BAAANQAECgYIEgABNQAECgoKPgATAJEhAA==.Hellvina:BAAANQADCggICAAAAA==.Hermie:BAAANQABCggICAAAAA==.',
Hi='Hinderberg:BAAANQAECgQIBgAAAA==.',
Ho='Holdor:BAABNQAECn8XAAMBAAYKqw1GRQD0AAABAAYKqw1GRQD0AAACAAQKdQOphwBbAAAAAA==.Holÿdiver:BAAANQABCgYIBAABNQAECgoKLQALAGgfAA==.Horde:BAAANQADCgIIAgAAAA==.Horizons:BAAANQAECgUICgAAAA==.',
Hu='Huntsum:BAABNQAECn8lAAMEAAgKXRVJfAAVAgAEAAcKrBdJfAAVAgAZAAYKhgwGPwCjAAAAAA==.',
Ia='Iahsotgievhu:BAAANQADCgcICAAAAA==.Iamspeed:BAAANQABCgEIAQAAAA==.',
Ic='Iceblocklulz:BAAANQADCgMIAwAAAA==.Icedsoul:BAABNQAECn8aAAMDAAcKuQnMHwDrAAADAAYKuQnMHwDrAAAPAAMKrAGargFkAAAAAA==.Iceflame:BAAANQADCgYIBgABNQAECggIKgAKAEYbAA==.',
Ig='Iggey:BAABNQAECn8lAAIGAAoKzRHOlwDhAQAGAAoKzRHOlwDhAQAAAA==.',
Ik='Ikkaku:BAAANQADCggIDQAAAA==.',
Il='Ilandras:BAABNQAECn8hAAIVAAkKExY9JAAlAgAVAAkKExY9JAAlAgAAAA==.Illadus:BAABNQAECn8dAAIVAAkKrQtVMQAOAQAVAAkKrQtVMQAOAQAAAA==.Illiviix:BAAANQADCgcIHgAAAA==.',
In='Indra:BAABNQAECn8zAAIHAAoKYh1mSwCzAgAHAAoKYh1mSwCzAgAAAA==.Intoxicated:BAAANQAECgMICAAAAA==.',
Ir='Iranna:BAACNQAFFH8XAAMeAAcK4CPLAgBzAQAeAAUK/yTLAgBzAQAfAAMKyyH3EABsAAA1AAQKfzIAAx4ACgpiJR4NABwDAB4ACgpdJR4NABwDAB8ACAqUI2UlAG8CAAAA.',
It='Itsredbelow:BAAANQAECgEIBAAAAA==.',
Iz='Izlaz:BAAANQADCggICAAAAA==.',
Ja='Jacrispy:BAAANQAECgIJAwAAAA==.Jaggedace:BAABNQAECn81AAQYAAoKJwc/TQBiAQAYAAoKxQY/TQBiAQACAAYKvgR3igDWAAABAAQKQQcWYQCHAAAAAA==.Janaki:BAABNQAECn9IAAMKAAoKBB8NCQBEAwAKAAoKBB8NCQBEAwAQAAYKiQhccAAJAQAAAA==.',
Je='Jellyfish:BAABNQAECn8ZAAIHAAgKWBJHwgBPAQAHAAgKWBJHwgBPAQAAAA==.',
Ji='Jibbtotem:BAAANQADCgYIDQABNQAECgkJHwAUAI8WAA==.Jivanos:BAAANQADCgUIBQAAAA==.',
Jo='Joexotick:BAAANQABCgMIBQAAAA==.Jonnyquestt:BAABNQAECn8nAAIHAAgKXA3qtQCyAQAHAAgKXA3qtQCyAQAAAA==.',
Ju='Junlock:BAAANQAECgYICgABNQAFFAgIGAAVAMMWAA==.Junrush:BAACNQAFFH8YAAIVAAgKwxYAAgDGAQAVAAgKwxYAAgDGAQA1AAQKfzwAAxUACgpeI0sEACQDABUACgpeI0sEACQDABoAAQoAAMcvAD8AAAAA.Junshot:BAAANQAECgEIAQABNQAFFAgIGAAVAMMWAA==.',
Ka='Kalea:BAAANQABCgIIBAAAAA==.Kalietha:BAABNQAECn8XAAMMAAkKaAccSACnAAALAAkKUgWX0QAmAQAMAAMK3gwcSACnAAAAAA==.Karaizula:BAABNQAECn8rAAMlAAoKgQ81VADCAQAlAAoKgQ81VADCAQAbAAQKTwFGBgGBAAAAAA==.Kasdeya:BAAANQADCgYIBwAAAA==.Kassandrah:BAAANQADCgUIBQAAAA==.Katsuko:BAABNQAECn8zAAICAAoKBRYaJQDSAQACAAoKBRYaJQDSAQAAAA==.Kattnirra:BAABNQAECn8rAAIEAAoK7wxGfwC8AQAEAAoK7wxGfwC8AQAAAA==.Katze:BAABNQAECn8mAAIEAAkKRhEzZABNAgAEAAkKRhEzZABNAgAAAA==.Kaylé:BAAANQAECgMIAwAAAA==.',
Ke='Keepper:BAAANQAECgMIBwAAAA==.Kenj:BAABNQAECn8zAAIOAAoKdCPuBgCOAwAOAAoKdCPuBgCOAwABNQAFFAcIEwAKAMUcAA==.Kenjurr:BAABNQAECn8fAAMSAAkKTB/HBgA6AwASAAkKTB/HBgA6AwARAAIKOAtdNQBiAAABNQAFFAcIEwAKAMUcAA==.Kenslynn:BAABNQAECn88AAIOAAoKphykKQDCAgAOAAoKphykKQDCAgAAAA==.Ketheric:BAAANQADCgEIAQABNQAECgkJHQAMAMUZAA==.',
Ki='Kiannor:BAABNQAECn8vAAIgAAkKZggkKgBHAQAgAAkKZggkKgBHAQAAAA==.Killahaseo:BAABNQAECn8rAAIHAAoKeiH0SQC3AgAHAAoKeiH0SQC3AgAAAA==.Killmoedee:BAABNQAECn9FAAMIAAoKVCOhAwAzAwAIAAoKVCOhAwAzAwAHAAMKCQXteAFNAAAAAA==.Kishibe:BAAANQAECgUIDQAAAA==.Kiss:BAAANQAECggIEwABNQAFFAkJMwAlAAQkAA==.Kitwryn:BAAANQADCgcIFAAAAA==.',
Kl='Klexios:BAAANQAECgQIDAAAAA==.',
Ko='Koopa:BAAANQAECgcIEAAAAA==.',
Kr='Kraulhoof:BAAANQAECgEIAQABNQAECgQIBQAWAAAAAA==.Kronohs:BAAANQAECgIIAwAAAA==.Krymson:BAAANQADCgcIBwAAAA==.',
Ku='Kui:BAABNQAECn85AAImAAkK3R6pBABtAgAmAAkK3R6pBABtAgAAAA==.Kuneia:BAAANQADCgQIBAABNQAECgoKSAAKAAQfAA==.Kurakka:BAAANQADCgEIAQAAAA==.Kuyna:BAAANQADCgYIDgAAAA==.',
Ky='Kylohendrix:BAAANQAECgQIBAAAAA==.',
['Kö']='Köz:BAAANQAECgQIBAAAAA==.',
La='Laetri:BAAANQAECgQIBAAAAA==.Lailiia:BAABNQAECn8hAAIJAAcKFBJtHwCVAQAJAAcKFBJtHwCVAQABNQAECggIEgAWAAAAAA==.Laindrin:BAAANQAECgQIBgAAAA==.Lavendarlace:BAAANQADCgYIDAAAAA==.Lawrence:BAAANQADCggICAAAAA==.Lazloo:BAABNQAECn84AAIGAAkKjSVfIQC+AgAGAAkKjSVfIQC+AgAAAA==.Lazymidget:BAABNQAECn8YAAIZAAkKYgduOQCFAQAZAAkKYgduOQCFAQAAAA==.Lazytok:BAAANQAECgQIBwAAAA==.',
Le='Leftÿ:BAABNQAECn9IAAIYAAoKsB0fEgD8AgAYAAoKsB0fEgD8AgAAAA==.Legindkiller:BAAANQADCgcIFAAAAA==.Lenie:BAABNQAECn8bAAQOAAkKLSFBGwD/AgAOAAgK5iJBGwD/AgAUAAIKigoHXwA9AAAFAAEKVwnvMgAbAAABNQAFFAcIFAACAFogAA==.Levoyon:BAABNQAECn8fAAIkAAkKiQakGgBuAQAkAAkKiQakGgBuAQAAAA==.Lexibelle:BAABNQAECn9AAAILAAoKnw1RYgCvAQALAAoKnw1RYgCvAQAAAA==.Lexsing:BAAANQABCgEIAQAAAA==.',
Lf='Lfty:BAAANQADCggIEAABNQAECgoKSAAYALAdAA==.',
Li='Lianthael:BAAANQAECgcICAABNQAECggIJQAEAF0VAA==.Lightace:BAABNQAECn86AAMHAAoKTA4JqwB5AQAHAAoKvwkJqwB5AQAIAAYKNRIKPQAMAQAAAA==.Lightbunny:BAAANQAECggIEQAAAA==.Lightlicious:BAAANQADCgQIBAAAAA==.Lincia:BAAANQAECgUIBwAAAA==.Linkkil:BAAANQAECgYICwAAAA==.Liv:BAAANQADCgMIAwABNQAECgkJGAAOAFAXAA==.',
Lo='Loastotem:BAAANQADCgIIAgAAAA==.Lobos:BAABNQAECn8yAAILAAoKyQ9OdQACAgALAAoKyQ9OdQACAgAAAA==.Lockrah:BAAANQADCgcIEgAAAA==.Lorvinion:BAAANQAECgUICwAAAA==.Lostdraco:BAAANQAECgcIDgAAAA==.Lostdream:BAABNQAECn9BAAMXAAoKcgq7OgBWAQAXAAoKcgq7OgBWAQAaAAgKhAWCHgDaAAAAAA==.Loun:BAABNQAECn8kAAImAAkKQhuEBgAbAgAmAAkKQhuEBgAbAgAAAA==.',
Lu='Luiss:BAABNQAECn8cAAIHAAYKDAd/LQGnAAAHAAYKDAd/LQGnAAAAAA==.Luminism:BAABNQAECn8iAAMTAAoKxxrSPgBpAgATAAoKxxrSPgBpAgAHAAEKAACCjgFGAAABNQAECgoKHQAJAGYVAA==.Luvlycruelty:BAABNQAECn8YAAQLAAgKPQmwnAAeAQALAAgK4QiwnAAeAQAMAAIKOAYuZgBXAAANAAEKAAA/MgAwAAAAAA==.',
Ly='Lycos:BAAANQABCgQIBAAAAA==.Lyn:BAEBNQAECn85AAImAAoKaCZmAADvAwAmAAoKaCZmAADvAwAAAA==.',
['Lê']='Lêônà:BAAANQABCggICAAAAA==.',
Ma='Maazi:BAAANQADCgYIBgAAAA==.Mackenziiee:BAABNQAECn9DAAIEAAoK/BgROwC5AgAEAAoK/BgROwC5AgAAAA==.Magerick:BAAANQAECgYIDgAAAA==.Magicwater:BAAANQADCggICwABNQAECgoKNQAHAGgkAA==.Magtaki:BAAANQADCgEJAQAAAA==.Mainline:BAAANQAECgUICgAAAA==.Maizepriest:BAABNQAECn8tAAIUAAkKPyA2DwBmAgAUAAkKPyA2DwBmAgAAAA==.Maliaa:BAAANQAECgIIAgAAAA==.Malloryrose:BAAANQADCgcIBwAAAA==.Mandrison:BAABNQAECn8cAAIGAAkKKA+gYQDaAQAGAAkKKA+gYQDaAQAAAA==.Masfima:BAAANQADCgIIAgAAAA==.Maxz:BAAANQADCggIHAAAAA==.',
Mc='Mcstàbby:BAAANQABCgMIAwAAAA==.',
Me='Meerkat:BAAANQAECgQIBAAAAA==.Mellowblink:BAABNQAECn8YAAIPAAYKmBWJAAGNAQAPAAYKmBWJAAGNAQABNQAECgoKLAAhACsgAA==.Mellowlink:BAABNQAECn8/AAMfAAkKix9OGAC8AgAfAAkKix9OGAC8AgAeAAEKURKbYgA4AAABNQAECgoKLAAhACsgAA==.',
Mi='Migglet:BAAANQAECgMIAwAAAA==.Miirya:BAAANQADCgYIAwAAAA==.Milkybar:BAAANQAECggIEQAAAA==.Mimi:BAACNQAFFH9IAAMEAAoKQCYOAQBAAgAZAAkKLSSmAgBOAgAEAAcKhyYOAQBAAgA1AAQKfzIAAxkACgrEJoEGAGgDABkACgpkJoEGAGgDAAQACApFJj8mAP4CAAAA.Mirabar:BAAANQADCgEIAQAAAA==.Miramage:BAAANQADCgcIBwABNQAECggIFwAfAPQVAA==.Miravus:BAABNQAECn8XAAMfAAgK9BWVbgBeAQAfAAYKgBSVbgBeAQAeAAUK2hXNWABWAQAAAA==.Mirlanda:BAAANQAECgIIBwAAAA==.Misttie:BAABNQAECn8qAAImAAoKiR0FBACQAgAmAAoKiR0FBACQAgABNQAFFAQICAAOAOgaAA==.Mitcheoff:BAAANQAECgQIDgAAAA==.',
Mo='Moisturizer:BAAANQAECgUICwAAAA==.Moltenkam:BAAANQADCgEIAQAAAA==.Monkerick:BAAANQADCgQIBwAAAA==.Mooningyall:BAAANQAECgQICQAAAA==.Mowte:BAAANQADCgYIEgAAAA==.',
Mu='Murkoobi:BAAANQAECgEIAQAAAA==.',
My='Mystrial:BAAANQABCgcICwAAAA==.Mystáke:BAAANQAECggIDgAAAA==.',
['Mó']='Mómo:BAAANQADCgMIAwAAAA==.Móus:BAAANQADCgIIAgABNQAECgoKLQAlAD8VAA==.',
Na='Narbus:BAABNQAECn8UAAIQAAUKBQ4acAAKAQAQAAUKBQ4acAAKAQAAAA==.Narcissus:BAAANQADCgUIDgAAAA==.Naromancer:BAABNQAECn9IAAIPAAoKYSH0GQDdAgAPAAoKYSH0GQDdAgAAAA==.Nathadon:BAABNQAECn9FAAIUAAoKLSBICQBKAwAUAAoKLSBICQBKAwAAAA==.Nautrium:BAAANQAECgQIBwAAAA==.',
Ne='Necrotis:BAAANQADCgcIFAAAAA==.Nekhraros:BAABNQAECn8dAAMMAAkKxRmPMAAGAQALAAYKHhYwogCRAQAMAAMKox6PMAAGAQAAAA==.Nergál:BAAANQADCgYIBQABNQADCggICAAWAAAAAA==.Nessä:BAAANQAECgMIAwAAAA==.Nevelia:BAAANQAECggIEgAAAA==.Neytfury:BAAANQADCgUIBQAAAA==.Neyti:BAAANQADCgIIAgAAAA==.Neytvengy:BAAANQAECgMIAwAAAA==.Nezukô:BAAANQADCgUICQAAAA==.',
Ni='Nienna:BAAANQAECgMIBAABNQAECgoKLwAKAB8dAA==.Nightwulf:BAAANQADCgIIAgAAAA==.Nikkikynz:BAAANQABCgIIAgAAAA==.Nikkisan:BAAANQADCgYIGAAAAA==.Nixk:BAAANQAECgYIEAAAAA==.',
No='Noapte:BAAANQAECgEIAQAAAA==.Noixi:BAABNQAECn8rAAMDAAgKRwvRFwAlAQADAAgKRwvRFwAlAQAPAAcKTAYL7QDUAAAAAA==.Noras:BAABNQAECn8dAAIgAAoKdhPyJgDqAQAgAAoKdhPyJgDqAQAAAA==.Nordicslayer:BAAANQAECgEIAQAAAA==.Notagnoblin:BAECNQAFFH8hAAICAAcKVSZ3AwA2AgACAAcKVSZ3AwA2AgA1AAQKfzoAAgIACgqmJvACAMMDAAIACgqmJvACAMMDAAAA.Notrick:BAAANQAECgUICAAAAA==.',
Nu='Nuffsaid:BAAANQADCgUIBgAAAA==.',
Ny='Nyko:BAAANQADCgUIBgAAAA==.',
Oa='Oaklyn:BAAANQADCgUIBQAAAA==.',
Ob='Obolisq:BAAANQADCgIIAgAAAA==.Obsidious:BAAANQAECgYICQAAAA==.',
Od='Oddsoul:BAAANQAECgIIAwAAAA==.',
Og='Ogrelurd:BAABNQAECn9OAAMGAAoK+B2MKgCVAgAGAAoK+B2MKgCVAgAdAAEKAACeQQAAAAAAAA==.',
Ol='Oliveia:BAAANQADCgUIBQAAAA==.',
Op='Opalfox:BAAANQADCgEIAQAAAA==.Ophelia:BAABNQAECn9QAAQLAAoKRyFNNwA0AgALAAgK3SBNNwA0AgANAAYKHyFdCwC2AQAMAAIK6xKWVACBAAAAAA==.',
Or='Orakwa:BAABNQAECn8VAAMGAAkKoBGqjwD1AQAGAAkKoBGqjwD1AQAdAAQKshEfGwD1AAAAAA==.',
Os='Osteroth:BAAANQADCggIEQAAAA==.',
Pa='Pachez:BAAANQAECgIIAgAAAA==.Paladont:BAAANQAECgUICwAAAA==.Pallinda:BAABNQAECn8+AAMTAAoKkSHxEQAtAwATAAoKkSHxEQAtAwAHAAYKoQ4s6wBFAQAAAA==.Palmogant:BAAANQAECgYIEQAAAA==.Panztide:BAAANQADCgcICAABNQAECgoKMQAhAK8SAA==.Pappyoblues:BAAANQAECgEIAgAAAA==.Patt:BAAANQADCgUIBQAAAA==.',
Pe='Pendulumlaw:BAACNQAFFH8RAAIGAAYK3wggGgBGAQAGAAYK3wggGgBGAQA1AAQKfzEAAgYACgpkGT1nAFoCAAYACgpkGT1nAFoCAAAA.Pennypacker:BAAANQAECgUICQABNQAECgoKLwAKAB8dAA==.Pepe:BAAANQADCgEIAQAAAA==.',
Ph='Phinn:BAABNQAECn8xAAIQAAkKCglOPgAxAQAQAAkKCglOPgAxAQAAAA==.Phoel:BAAANQADCgUIDAAAAA==.Phoopanchu:BAABNQAECn8XAAIJAAgKOQwyGwBRAQAJAAgKOQwyGwBRAQAAAA==.',
Pi='Pimikoh:BAAANQAECgQIBAAAAA==.Pinkbuns:BAABNQAECn8lAAIDAAkKrRykCQA4AgADAAkKrRykCQA4AgAAAA==.',
Pn='Pneuma:BAABNQAECn8eAAIaAAgKmRyWCQDSAQAaAAgKmRyWCQDSAQAAAA==.',
Po='Pollonius:BAAANQADCgQIBAAAAA==.Poncho:BAAANQADCgIIAgAAAA==.Popsy:BAAANQAECgUIBQAAAA==.',
Pr='Praxel:BAAANQAECgUIBQAAAA==.Prenton:BAABNQAECn9DAAIGAAoKARkPRQAyAgAGAAoKARkPRQAyAgAAAA==.Prepotente:BAAANQAECgMIBAABNQAECgoKLAAhACsgAA==.Prideflag:BAAANQADCggICAAAAA==.Priestin:BAAANQAECgMIAwAAAA==.Pristin:BAAANQADCgQIBAAAAA==.Profundity:BAAANQAECgEIAQABNQAECgoKLwAKAB8dAA==.',
Ps='Psyduck:BAABNQAFFH8FAAIGAAUKfAszFwBpAQAGAAUKfAszFwBpAQABNQAFFAoKSAAHADYmAA==.',
Pu='Punie:BAABNQAECn8mAAIbAAgKfRZQVgAhAgAbAAgKfRZQVgAhAgAAAA==.Punkte:BAAANQAECgUIDAAAAA==.Puzzykat:BAAANQADCgYIBgAAAA==.',
Pv='Pvptankin:BAAANQAECgEIAQABNQAECggIEQAWAAAAAA==.',
['Pä']='Päg:BAAANQADCgEIAQABNQAECgoKSAAYALAdAA==.',
Qe='Qeini:BAABNQAECn8yAAIFAAgKDQ28BwBNAQAFAAgKDQ28BwBNAQAAAA==.',
Ra='Radrin:BAAANQAECgUIBQAAAA==.Rafoff:BAAANQAECgcICgAAAA==.Ragnarax:BAABNQAECn8kAAIGAAoKeR/GLACMAgAGAAoKeR/GLACMAgAAAA==.Rahll:BAAANQADCgIIAgAAAA==.Raikami:BAAANQAECgQIBAAAAA==.Rancoramble:BAAANQAECgYICwAAAA==.Randis:BAABNQAECn9BAAIBAAkKURDTJgCqAQABAAkKURDTJgCqAQAAAA==.Raysonna:BAAANQAECgYIEgAAAA==.',
Re='Recapitator:BAAANQAECgIIAgAAAA==.Rengår:BAAANQAECgUIBAAAAA==.Reo:BAAANQAECgMIAwAAAA==.Reticent:BAAANQAECgUICgAAAA==.Reversewally:BAAANQAECgcIEAAAAA==.Rexhà:BAAANQAECgQICwAAAA==.Rexiis:BAABNQAECn8sAAILAAkKzw88ewBtAQALAAkKzw88ewBtAQAAAA==.Reyth:BAAANQAECgQICwAAAA==.',
Rh='Rhuby:BAABNQAECn8+AAICAAkKSRbeLQCaAQACAAkKSRbeLQCaAQAAAA==.',
Ri='Rimos:BAAANQAECggIDQAAAA==.Riptîde:BAAANQAECgcIDAAAAA==.Rivening:BAAANQAECgQICAAAAA==.',
Rk='Rk:BAAANQADCgYICAAAAA==.',
Ro='Rochelle:BAAANQAECgEIAQAAAA==.Rocknlock:BAABNQAECn8sAAILAAkKCgOzwADQAAALAAkKCgOzwADQAAAAAA==.Roeyth:BAAANQADCggICAAAAA==.Rokki:BAABNQAECn9BAAIPAAkKYgnd7ACxAQAPAAkKYgnd7ACxAQAAAA==.Roostor:BAAANQAECgIIAQAAAA==.Rosael:BAAANQADCgQJBAAAAA==.Roundhouse:BAABNQAECn8eAAImAAgKpBrlDQAZAgAmAAgKpBrlDQAZAgAAAA==.',
Ru='Rubbmytotems:BAAANQAECgYIEAAAAA==.Rubicôn:BAAANQABCgYICAABNQAFFAcIHAAPAK0ZAA==.Rubmyoysters:BAAANQADCgEIAQAAAA==.Ruleti:BAABNQAECn8tAAIEAAoKuRo1PwCtAgAEAAoKuRo1PwCtAgAAAA==.Rumí:BAAANQADCggIIgAAAA==.Rundeep:BAAANQABCgYICgAAAA==.Russell:BAAANQADCgcIFAAAAA==.',
Sa='Sabado:BAAANQAECgMIAwAAAA==.Safewerd:BAEBNQAECn8XAAIJAAkKiwvnIAANAQAJAAkKiwvnIAANAQAAAA==.Saitama:BAAANQAECgYICQABNQAECgkJMgAGACoWAA==.Sangriel:BAABNQAECn8sAAICAAoKEA+rZwBUAQACAAoKEA+rZwBUAQAAAA==.Saraceleste:BAAANQAECgYICgAAAA==.Sarafinmae:BAAANQAECgUIBwAAAA==.Sarahfi:BAAANQAECgIJAgABNQAECgcIGwAiABsXAA==.Saralanna:BAABNQAECn88AAILAAoK6A2cVADWAQALAAoK6A2cVADWAQAAAA==.Sarasophie:BAAANQADCggIIAAAAA==.Sarefina:BAAANQAECgQICQAAAA==.Sathenazarke:BAABNQAECn8WAAIRAAoKXx6zCADsAgARAAoKXx6zCADsAgABNQAFFAcIFwAeAOAjAA==.',
Sc='Schism:BAAANQAECgMIBAAAAA==.Schmingus:BAAANQADCgIIAgAAAA==.Scoban:BAACNQAFFH8QAAITAAYKuBnwCgCuAQATAAYKuBnwCgCuAQA1AAQKfxsAAhMACQoRHng2AIoCABMACQoRHng2AIoCAAAA.',
Se='Seaworld:BAABNQAECn8sAAQhAAoKKyAIBADzAgAhAAkKKyAIBADzAgAQAAcKMRCKUgDUAAAiAAEKJhWZbgAzAAAAAA==.Selènè:BAAANQAECggIDQABNQAFFAQICAAOAOgaAA==.Seraphine:BAAANQABCgIIAgAAAA==.Seraphnite:BAAANQADCgIIAgAAAA==.Seriousjakk:BAAANQADCgEIAQABNQADCgQIBwAWAAAAAA==.',
Sh='Shadeebear:BAAANQADCgEIAQAAAA==.Shadowtax:BAAANQADCgYIBgAAAA==.Shan:BAAANQAECgcIEwAAAA==.Shaohlin:BAAANQAECgEIAQAAAA==.Shaqfu:BAAANQADCgcIFAAAAA==.Shavemybush:BAAANQADCgcJBwAAAA==.Shayy:BAABNQAECn89AAIFAAoKDhnnAwCeAgAFAAoKDhnnAwCeAgAAAA==.Sheve:BAAANQAECgQIEAABNQAECgoKOQAlANkiAA==.Shevee:BAAANQAECggIDgABNQAECgoKOQAlANkiAA==.Shigure:BAABNQAECn8jAAMDAAoKpwqHFgBKAQAPAAoKrAgW0wDgAQADAAcKOQqHFgBKAQAAAA==.Sholin:BAABNQAECn8kAAImAAoKjR+gCACfAgAmAAoKjR+gCACfAgAAAA==.Shomea:BAAANQAECgUIDAAAAA==.Shugz:BAAANQADCgcIEwAAAA==.Shumai:BAAANQAECgcIDgAAAA==.',
Si='Sigons:BAAANQABCgYICAAAAA==.Sikotick:BAABNQAECn8nAAIKAAkKaRdRLQCxAQAKAAkKaRdRLQCxAQAAAA==.Sikxrapture:BAAANQADCgYIBgAAAA==.Siliconista:BAACNQAFFH8JAAIPAAQKORf8KADUAAAPAAQKORf8KADUAAA1AAQKf00AAw8ACgrbJEgVAH4DAA8ACgooJEgVAH4DAAMABwrgJKkLAAUCAAAA.Simbelmyne:BAAANQAECgUIBgABNQAECgoKLwAKAB8dAA==.',
Sk='Skitrit:BAAANQAECgEIAQABNQAECgoKLQAEALkaAA==.Skyjin:BAAANQADCgYJCQAAAA==.',
Sl='Slammurai:BAAANQADCgcICwAAAA==.Slavon:BAAANQAECgcIBgAAAA==.Slew:BAAANQAECgMIBgAAAA==.Slippie:BAAANQADCgQIBAAAAA==.Slippinwater:BAABNQAECn81AAIHAAoKaCSsHQBMAwAHAAoKaCSsHQBMAwAAAA==.Sllew:BAABNQAECn9XAAMBAAoKYR1OGQD1AgABAAkKax1OGQD1AgAYAAoK8xe1HQBcAgAAAA==.Slylent:BAAANQAECgIIAQAAAA==.Slyyce:BAABNQAECn8UAAIGAAkKyRXhnADUAQAGAAkKyRXhnADUAQAAAA==.',
Sm='Smoulder:BAAANQAECgIIBwAAAA==.',
Sn='Snigles:BAABNQAECn8pAAIfAAoKgwlTKgBxAQAfAAoKgwlTKgBxAQAAAA==.Snowlily:BAAANQAECgQIDAABNQAECgoKLQAUALsUAA==.Snurp:BAAANQAECgUIDAABNQAECgoKMgAZAPYgAA==.',
So='Softnsquishy:BAAANQAECgEIAgAAAA==.Solarflare:BAAANQADCgEIAQAAAA==.Solmarrow:BAABNQAECn8YAAQDAAcKmggwGAA4AQADAAcKRggwGAA4AQAPAAQKaAQchAG8AAAnAAEKFAbKDQA0AAAAAA==.',
Sp='Spagoni:BAAANQADCggICAAAAA==.Spanksbar:BAAANQADCggIFAAAAA==.Spartos:BAABNQAECn8tAAMGAAgKxBvJSwAcAgAGAAgKxBvJSwAcAgAcAAIKUA+hNwBgAAAAAA==.Spazzlixx:BAAANQAECgUIBQAAAA==.Speedy:BAABNQAECn8sAAIEAAcKWQUG2QAAAQAEAAcKWQUG2QAAAQAAAA==.Speedyspeed:BAAANQADCgQIBQAAAA==.Spokes:BAAANQADCgYICQABNQAECggIAwAWAAAAAA==.Sposi:BAABNQAECn8gAAMCAAkKxiErGwDVAgACAAkKxiErGwDVAgAYAAIKzwwfmABtAAAAAA==.Sprinkle:BAAANQAECggJCQABNQAECggIEQAWAAAAAA==.',
Sr='Srimrithyu:BAAANQADCgYIEwAAAA==.',
Ss='Sselionn:BAAANQAECgUIDgAAAA==.',
St='Stomps:BAABNQAECn8nAAIcAAoKcRccEAAnAgAcAAoKcRccEAAnAgAAAA==.Stoneweaver:BAAANQADCgYIBgABNQAECggIKgAKAEYbAA==.Stonezef:BAABNQAECn8qAAIPAAoKeQzf+ACbAQAPAAoKeQzf+ACbAQAAAA==.',
Su='Suffocation:BAAANQADCgYIBwAAAA==.Sumasuka:BAAANQADCggIHAAAAA==.Sungdihhwoo:BAAANQADCgQIBwAAAA==.Susann:BAABNQAECn8tAAIlAAoKPxVeVgC6AQAlAAoKPxVeVgC6AQAAAA==.',
Sy='Syravia:BAAANQAECgYIEwAAAA==.',
['Sò']='Sòlushan:BAAANQAECgEIAQABNQAFFAIIBQAHADcbAA==.',
Ta='Tahoa:BAAANQABCgQIBwAAAA==.Talarin:BAAANQAECgIIBwAAAA==.Talayro:BAAANQADCgYIBwAAAA==.Tameka:BAABNQAECn83AAIEAAoKHhrFNQDKAgAEAAoKHhrFNQDKAgAAAA==.Tardis:BAAANQAECgcIBwABNQAECgoKJgAOAOcXAA==.Tatersdh:BAEANQAECgYIDAABNQAFFAcIIQACAFUmAA==.Tavinrayn:BAAANQAECgYIDAAAAA==.',
Te='Teera:BAAANQAECgIIAgABNQAECgoKJAAQANoSAA==.Tekesh:BAABNQAECn8YAAIEAAkKCiT4OgBjAgAEAAkKCiT4OgBjAgAAAA==.Teksham:BAAANQADCgYIEgAAAA==.Telarin:BAABNQAECn81AAMEAAkKghuMUQAqAgAEAAkKCBuMUQAqAgAoAAcKdxPABwDtAQAAAA==.Tenebrefigo:BAAANQAECgEIAQABNQAECgoKSwAcAGMmAA==.Teremup:BAAANQAECgIIAQAAAA==.Tezrian:BAAANQADCgYJCgABNQAECgoKLAAhACsgAA==.',
Th='Thebigdawg:BAAANQADCggICQAAAA==.Theladyboy:BAABNQAECn8pAAMaAAgKoBfqDQBuAQAaAAgKoBfqDQBuAQAXAAMKtgrieQCRAAAAAA==.Thomss:BAABNQAECn8zAAIEAAoKfhO5awA7AgAEAAoKfhO5awA7AgAAAA==.Thraiene:BAAANQAECgUIDwABNQAECgkJFQAMAMASAA==.Thrawn:BAAANQAECgMIAwAAAA==.Throhk:BAAANQADCgcIFQAAAA==.Thrumgar:BAAANQAECgEIAgAAAA==.',
Ti='Tiamut:BAAANQADCgQIBAAAAA==.Tigercla:BAAANQADCggICAAAAA==.Tigerliley:BAAANQAECgQIDAABNQAECgoKLQAUALsUAA==.Tinneas:BAAANQAECgEIAQAAAA==.Tished:BAAANQABCgUICAAAAA==.',
To='Tomás:BAABNQAECn8dAAIbAAgKwQxVjACFAQAbAAgKwQxVjACFAQAAAA==.Topg:BAAANQADCggIEwAAAA==.Torstai:BAABNQAECn8aAAINAAgKjgmwDwBTAQANAAgKjgmwDwBTAQAAAA==.Totemic:BAAANQADCggIEgAAAA==.Toxic:BAABNQAECn9JAAMfAAoKdCF3CgDNAgAfAAkKzB93CgDNAgAeAAYKsR1QOQDwAQAAAA==.Toyun:BAAANQADCgMIAwAAAA==.',
Tr='Trap:BAAANQADCgQIBAAAAA==.Trueshöt:BAABNQAECn8xAAMoAAoKuhWuBgDLAQAoAAkKZhWuBgDLAQAZAAgKpBH0MADGAQAAAA==.',
Ts='Tserendolgor:BAAANQAECgYIDAABNQAECgoKLAAhACsgAA==.',
Tu='Tukker:BAAANQADCgYIBgABNQAECgoKSwAcAGMmAA==.',
Ty='Tyedindis:BAAANQADCgEIAQAAAA==.Tyresious:BAABNQAECn8gAAIHAAoKxBhslwD1AQAHAAoKxBhslwD1AQAAAA==.',
Ut='Utherrex:BAAANQAECgcIDAABNQAECgkJLAALAM8PAA==.',
Va='Vahaghn:BAABNQAECn9FAAIGAAoKUSMAEwBwAwAGAAoKUSMAEwBwAwAAAA==.Valcerus:BAAANQAECgUIDgAAAA==.Valedus:BAABNQAECn8xAAIHAAoK1SFJOQDrAgAHAAoK1SFJOQDrAgAAAA==.',
Ve='Veelete:BAAANQADCgcICwABNQAECggILAATADAjAA==.Vengeancedh:BAABNQAECn8dAAICAAkKOhyEGQA3AgACAAkKOhyEGQA3AgAAAA==.Veroya:BAAANQAECgEIAQAAAA==.Vespra:BAAANQADCgYIBgAAAA==.Veylara:BAAANQADCgIIAgAAAA==.',
Vi='Viix:BAAANQADCgUIBQAAAA==.Vinno:BAAANQAECgEIAgAAAA==.Virr:BAABNQAECn8bAAIiAAcKGxf6KABBAQAiAAcKGxf6KABBAQAAAA==.',
Vo='Volcker:BAABNQAECn9BAAIIAAkKGwwJJQBGAQAIAAkKGwwJJQBGAQAAAA==.Volthreal:BAAANQADCggICAABNQAECgoKSwAcAGMmAA==.Voltuk:BAABNQAECn9LAAQcAAoKYyZ3AACIAwAcAAoKYyZ3AACIAwAdAAMKiQrgJQCAAAAGAAEK2wkmKQE3AAAAAA==.',
Wa='Wadoralock:BAAANQAECggIDQABNQAFFAMICAAEAJgIAA==.Walrustusk:BAAANQAECgcIBwAAAA==.Wariius:BAAANQAECgIIAgAAAA==.Warwarb:BAAANQAECgcICwABNQAECgoKNAALAE4XAA==.Wasabijack:BAAANQADCgcJCgAAAA==.Waterliliy:BAABNQAECn8tAAQUAAoKuxQ3IQB+AQAUAAoKuxQ3IQB+AQAFAAIKPQuSIABdAAAOAAIKhAEz9wA/AAAAAA==.Wayhn:BAAANQAECgMIAwAAAA==.',
Wh='Whatcrap:BAAANQAECgIIAgAAAA==.Whathehay:BAAANQADCgQIBAAAAA==.',
Wi='Wickedmon:BAAANQADCgMIAwAAAA==.Windfurypie:BAAANQADCggICQAAAA==.',
Wo='Wolfbish:BAAANQAECgUICAAAAA==.Wongidan:BAAANQAECggIDgAAAA==.',
['Wý']='Wýler:BAAANQADCgIIAgABNQADCggICAAWAAAAAA==.',
Xa='Xacious:BAABNQAECn8YAAIOAAgK9xHbegBpAQAOAAgK9xHbegBpAQAAAA==.',
Xh='Xhuri:BAAANQADCgYIBgAAAA==.',
['Xë']='Xëna:BAABNQAECn8qAAMKAAgKRhscIQDxAQAKAAgKRhscIQDxAQAQAAIKSwSCpwBJAAAAAA==.',
Yo='Yorllik:BAAANQAECgUIDgAAAA==.',
Yt='Yt:BAABNQAECn8nAAIVAAoKiBQiFgAJAgAVAAoKiBQiFgAJAgAAAA==.',
Yu='Yueguanghua:BAAANQADCgUIBQAAAA==.Yuzuha:BAAANQADCgIIAgAAAA==.',
Ze='Zeddicus:BAAANQAECgQIBAAAAA==.Zendragon:BAABNQAECn84AAMIAAoK+iMNBgD5AgAIAAoK+iMNBgD5AgAHAAgKXwwy5QAVAQABNQAECgoKSwAcAGMmAA==.',
Zh='Zhorvan:BAAANQADCggIGQABNQAECggIGgAIAEQHAA==.',
Zi='Zilstar:BAAANQAECgUIBQAAAA==.',
Zo='Zoomy:BAAANQADCggICAAAAA==.',
Zu='Zuggondeez:BAAANQAECgUIBQABNQAECggIJQAEAF0VAA==.Zuggsalot:BAAANQAECgIIAQAAAA==.',
['Âr']='Ârtëmïs:BAABNQAECn8WAAIEAAcKIQfj4AA/AQAEAAcKIQfj4AA/AQAAAA==.',
['Åp']='Åpollo:BAACNQAFFH8MAAIJAAYK8hcWBACjAQAJAAYK8hcWBACjAQA1AAQKfyAAAgkACgqIG9wQAHECAAkACgqIG9wQAHECAAAA.',
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
