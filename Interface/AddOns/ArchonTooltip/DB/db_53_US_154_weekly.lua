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

local lookup = {'Mage-Arcane','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Monk-Windwalker','Hunter-BeastMastery','DeathKnight-Blood','Evoker-Devastation','Priest-Shadow','Unknown-Unknown','Shaman-Restoration','Warlock-Affliction','Mage-Frost','DemonHunter-Devourer','Shaman-Elemental','Rogue-Outlaw','Warrior-Protection','Druid-Guardian','Rogue-Assassination','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Warrior-Arms','Warrior-Fury','DemonHunter-Vengeance','DeathKnight-Frost','Druid-Balance','Druid-Feral','Priest-Holy','DemonHunter-Havoc','DeathKnight-Unholy','Mage-Fire','Druid-Restoration','Shaman-Enhancement','Priest-Discipline','Evoker-Augmentation','Evoker-Preservation','Hunter-Marksmanship','Rogue-Subtlety','Hunter-Survival',}
local provider = {region='US',realm='Mannoroth',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aadda:BAACNQAFFH8QAAIBAAUKrxOkEADaAAABAAUKrxOkEADaAAA1AAQKfzEAAgEACgpNHBlBAAMDAAEACgpNHBlBAAMDAAAA.',
Ab='Abcdpal:BAACNQAFFH8RAAQCAAcKGhxkBAAgAgACAAYKiRxkBAAgAgADAAEKYhpYDwBQAAAEAAEKngAHMAAyAAA1AAQKfx0AAgIACgqrIv0bALIBAAIACgqrIv0bALIBAAAA.Abena:BAAANQAECgcICwAAAA==.Abighoul:BAAANQADCgYICAABNQAECgkJKAAFAAEeAA==.Abowolf:BAAANQAECggICAABNQAECgoKKAAGAIsgAA==.Abusive:BAABNQAECn8hAAIHAAkKfB0XHgDBAgAHAAkKfB0XHgDBAgAAAA==.',
Ac='Acat:BAAANQAECgYICwAAAA==.Ackamaracus:BAAANQADCgYIDgAAAA==.',
Ae='Aeice:BAAANQAECgIIAgAAAA==.Aerogosa:BAACNQAFFH8OAAIIAAUKjxqOBQBfAQAIAAUKjxqOBQBfAQA1AAQKfzkAAggACgplImUAAMwCAAgACgplImUAAMwCAAAA.Aeyonce:BAAANQADCgcIBwAAAA==.',
Af='Affrika:BAAANQADCgEIAQAAAA==.',
Ag='Agogagog:BAABNQAECn8qAAIJAAoK5Q7yCwA+AQAJAAoK5Q7yCwA+AQAAAA==.',
Ah='Ahlaris:BAAANQADCgcIBwABNQAECgMIAwAKAAAAAA==.',
Ai='Aicam:BAAANQAECgEIAQAAAA==.',
Ak='Akashani:BAAANQABCggICAAAAA==.Akaza:BAAANQAECggIDgAAAA==.',
Al='Alanalanalan:BAAANQAECgEIAQAAAA==.Alarg:BAAANQADCgIIAgABNQAECgkJGAALAEUiAA==.Alatide:BAABNQAECn8YAAILAAkKRSJsFwAXAwALAAkKRSJsFwAXAwAAAA==.Alcani:BAAANQADCgYIBgAAAA==.Aleena:BAAANQADCgcICgAAAA==.Alleriaa:BAAANQADCggIDAAAAA==.Alphakuup:BAAANQADCgYICQABNQAECgkJKAAMAHQTAA==.Altazar:BAABNQAECn8xAAMNAAoKTBZOAQAYAgANAAkKHhdOAQAYAgABAAgKvxCVxwD2AQAAAA==.Alxath:BAABNQAECn8YAAIOAAgKNCDDGQCMAgAOAAgKNCDDGQCMAgAAAA==.',
Am='Amaryste:BAAANQAECgEIAQAAAA==.Amidalah:BAABNQAECn8YAAIGAAkKchgxQQCnAgAGAAkKchgxQQCnAgAAAA==.Amizlia:BAAANQADCgEIAQAAAA==.Amorinaron:BAACNQAFFH8FAAIBAAQKDARUMwD5AAABAAQKDARUMwD5AAA1AAQKf0oAAgEACgoWIvoPAJMDAAEACgoWIvoPAJMDAAAA.',
An='Anansi:BAAANQAECgIIAwABNQAFFAcIHwAIANYkAA==.Andrés:BAAANQADCgUIBgAAAA==.Andsong:BAAANQADCgUIBQABNQAECgYIEQAKAAAAAA==.Anfalas:BAABNQAECn9AAAIPAAoK0yBJFABQAwAPAAoK0yBJFABQAwAAAA==.Anic:BAABNQAECn8tAAIGAAoKbRkmDAASAgAGAAoKbRkmDAASAgAAAA==.Anikora:BAAANQADCgcIDAAAAA==.Anjelika:BAAANQAECgUIEgAAAA==.Anklestabber:BAABNQAECn84AAIQAAoKPh01AACCAgAQAAoKPh01AACCAgAAAA==.Annathema:BAAANQADCgQIBAAAAA==.Anser:BAAANQAECgQIBAAAAA==.Anthlina:BAAANQADCgUIBwAAAA==.Antmt:BAAANQAECgIIAgAAAA==.',
Ap='Aprilthehag:BAAANQADCgYIBgAAAA==.',
Ar='Aracelis:BAAANQADCgYIBgAAAA==.Archicrash:BAAANQAECgQIBQAAAA==.Archipal:BAAANQAECgEIAQAAAA==.Archipriest:BAAANQAECgEIAQAAAA==.Archnash:BAAANQAECgIIAQAAAA==.Archomen:BAAANQADCgQIBAABNQAECgQICQAKAAAAAA==.Arcwave:BAAANQAECgIIAgAAAA==.Arcyon:BAABNQAECn8UAAIDAAcKGQViQQDxAAADAAcKGQViQQDxAAAAAA==.Arethi:BAACNQAFFH8ZAAIRAAUKjSWzAAAqAgARAAUKjSWzAAAqAgA1AAQKfygAAhEACgrOIzYDAG8DABEACgrOIzYDAG8DAAAA.Arial:BAAANQADCgYIBgABNQAECgYIDgAKAAAAAA==.Arleos:BAABNQAECn85AAIEAAoKBBsZCQAyAgAEAAoKBBsZCQAyAgAAAA==.Arroyo:BAAANQADCggIMgAAAA==.Artemasz:BAAANQAECgUIEgAAAA==.',
As='Asagiri:BAAANQADCgMIAwAAAA==.Asrelle:BAABNQAECn8ZAAIDAAkKARHkKACWAQADAAkKARHkKACWAQAAAA==.Astaumin:BAAANQADCgYICgAAAA==.Asterrin:BAAANQAECgIIBAAAAA==.Astralfrog:BAAANQAECgQIBgAAAA==.',
At='Ateelasham:BAAANQAECgYIEgAAAA==.Atrophied:BAAANQAECgIIAwABNQAECgoKPgASAJ4gAA==.',
Au='Audeline:BAAANQAECgQIDAAAAA==.Augmented:BAAANQABCgYICgABNQAECgoKPQAEACsmAA==.Auraelia:BAAANQADCgEIAQAAAA==.Aurilia:BAAANQADCggICwAAAA==.Aurôra:BAAANQAECgYICwAAAA==.',
Av='Avran:BAABNQAECn8xAAIOAAoKoxvEAgAcAgAOAAoKoxvEAgAcAgAAAA==.',
Az='Aziala:BAABNQAECn8XAAMNAAoKZR+TBgCWAgANAAkKZR+TBgCWAgABAAUKIAw8SAEWAQABNQAECgoKMgAIAGsiAA==.Azreluna:BAABNQAECn84AAITAAoKng00BADvAQATAAoKng00BADvAQAAAA==.',
Ba='Backstabr:BAAANQAECgYIDwAAAA==.Backyard:BAAANQADCgQIBAAAAA==.Badwords:BAAANQADCgYICAAAAA==.Bajablight:BAAANQAECgMIAwAAAA==.Bajiggitee:BAABNQAECn83AAIHAAoKTBh6JwCDAgAHAAoKTBh6JwCDAgAAAA==.Ballsakz:BAAANQAECgYICQABNQAECggIDQAKAAAAAA==.Bananarosin:BAABNQAECn8hAAQMAAcKkAnOGwCiAAAUAAYK8Arl0wAiAQAVAAQKCwPaSAClAAAMAAMKvAPOGwCiAAAAAA==.Banlers:BAAANQADCgYIFAAAAA==.Banmedaddy:BAAANQADCggIFAABNQABCgIJAgAKAAAAAA==.Baradoon:BAABNQAECn8WAAIPAAcKgRnpXwACAgAPAAcKgRnpXwACAgAAAA==.Barbamage:BAAANQADCgYICAABNQAECgoKJQALAGIWAA==.Bazrameet:BAABNQAECn8jAAIBAAoK7RHfMgBaAQABAAoK7RHfMgBaAQABNQAFFAUICAAIADYMAA==.',
Be='Bealzhunter:BAAANQADCgUIBgAAAA==.Beasthunter:BAAANQABCgUIBwAAAA==.Bela:BAAANQADCgcIBwAAAA==.Bellion:BAAANQAECgMIBgAAAA==.Beo:BAACNQAFFH8IAAIWAAUKzxIgBgA3AQAWAAUKzxIgBgA3AQA1AAQKfyYAAhYACQpjGv4QAG8CABYACQpjGv4QAG8CAAAA.',
Bi='Bigbluetaco:BAABNQAECn8zAAQXAAoK0hhjXAB3AgAXAAoKmBhjXAB3AgARAAcKIxL9IABFAQAYAAIKNggMLQBPAAAAAA==.Bigchug:BAABNQAECn8vAAIFAAoKOCDJCQA1AwAFAAoKOCDJCQA1AwAAAA==.Biggirlsonly:BAAANQAECgUICwABNQAFFAcIHwAIANYkAA==.Bigglob:BAAANQAECgUIBwAAAA==.Bigyahu:BAAANQADCgYIBgAAAA==.Bitelo:BAAANQADCggICAABNQADCggICAAKAAAAAA==.',
Bl='Blast:BAAANQADCgIIAgAAAA==.Blatt:BAAANQAECgIIAwAAAA==.Blech:BAABNQAECn8zAAIBAAkKoQ9YrAApAgABAAkKoQ9YrAApAgAAAA==.Blíght:BAAANQADCgIIAgAAAA==.',
Bo='Bookerneg:BAABNQAECn8VAAIBAAcKcxP64ADHAQABAAcKcxP64ADHAQAAAA==.Boomslang:BAAANQAECgQICwAAAA==.Borlen:BAABNQAECn8YAAIHAAcKiBakRwDaAQAHAAcKiBakRwDaAQAAAA==.Bouncyball:BAAANQAECgMIBQABNQAECgUICgAKAAAAAA==.Boxofcookies:BAAANQAECgQIBAAAAA==.',
Br='Braids:BAAANQAECgIIAwAAAA==.Brassfeather:BAAANQAECgQICwAAAA==.Brewcifer:BAAANQADCgMIAwAAAA==.Brezzath:BAAANQADCggICAAAAA==.Brezzid:BAAANQADCgYICwABNQAECgoKMQAZAKsLAA==.Brezzon:BAABNQAECn8xAAIZAAoKqwuJBABPAQAZAAoKqwuJBABPAQAAAA==.Brizzletwo:BAABNQAECn8oAAILAAoKlwpjGgCJAQALAAoKlwpjGgCJAQAAAA==.Brozzath:BAAANQAECgYICgABNQAECgoKMQAZAKsLAA==.Bryanka:BAAANQADCggICgAAAA==.Brystal:BAAANQAECggIEAAAAA==.Brättie:BAAANQAECggIDAAAAA==.Bróx:BAABNQAECn8gAAIXAAkK1haBXAB2AgAXAAkK1haBXAB2AgAAAA==.',
Bu='Bubbajoe:BAAANQAECgIIAgABNQAFFAcIHwAIANYkAA==.Bubbajr:BAAANQAECgYIDgAAAA==.Bubbleloaf:BAAANQADCggICAAAAA==.Bullsac:BAAANQADCgIIAQAAAA==.Bungholio:BAAANQAECgYICwAAAA==.Burgy:BAABNQAECn8hAAMVAAkKJhfsDwD/AQAVAAcKbxfsDwD/AQAUAAYKMhBwOQAeAQABNQAECgkJLgAHAB4PAA==.Burgydk:BAABNQAECn8uAAMHAAkKHg9uXwB0AQAHAAkKUw1uXwB0AQAaAAUKYA/AOQC7AAAAAA==.Buttfancy:BAABNQAECn8sAAIbAAoKOxeZCgCTAQAbAAoKOxeZCgCTAQAAAA==.',
['Bï']='Bïgbear:BAAANQAECggIBAAAAA==.Bïgblood:BAAANQAECgcIAQABNQAECggIBAAKAAAAAA==.Bïgdot:BAAANQAECgcIBwABNQAECggIBAAKAAAAAA==.',
Ca='Cainbanw:BAAANQADCgUICAAAAA==.Caliery:BAAANQABCgEIAQAAAA==.Calivaris:BAAANQAECgQIBAAAAA==.Calmpressure:BAABNQAECn8XAAIFAAkKOB+rDAAOAwAFAAkKOB+rDAAOAwAAAA==.Capnsparrow:BAAANQAECgUICQAAAA==.Captncheese:BAAANQAECgEIAgAAAA==.Cargy:BAAANQADCgcJCQAAAA==.Carshas:BAAANQADCggIDgAAAA==.Cas:BAAANQAECgMIBQAAAA==.Cassielee:BAAANQAECgQIDAAAAA==.Catabop:BAAANQAECgYIEgABNQAECgoKMAALAN8fAA==.Cataclysmicu:BAAANQAECgQIBwAAAA==.Catastorm:BAABNQAECn8wAAILAAoK3x9SGQANAwALAAoK3x9SGQANAwAAAA==.Catavoker:BAAANQAECgUIEAABNQAECgoKMAALAN8fAA==.Catsthunder:BAAANQAECgYIDQABNQAECgoKWAAXAHMhAA==.Caustic:BAABNQAECn8fAAMUAAoK9x3LIABsAQAUAAgKeR3LIABsAQAVAAIKcB/pRwCoAAAAAA==.Caveatemptor:BAACNQAFFH8GAAIbAAMKrg+hGADkAAAbAAMKrg+hGADkAAA1AAQKfx8AAhsACArNIKsrAH0CABsACArNIKsrAH0CAAAA.',
Ce='Celaina:BAAANQAECgYIDQAAAA==.',
Cg='Cgreen:BAAANQAECgQIBQAAAA==.',
Ch='Chainhappy:BAAANQAECgYICwAAAA==.Chaotiç:BAAANQAECgUIBQAAAA==.Cheezybread:BAAANQADCgUIBQAAAA==.Chesshire:BAAANQAECgYICQAAAA==.Chillfactor:BAAANQAECgcIDwAAAA==.Chimeric:BAABNQAECn8+AAMSAAoKniDmAQBfAgASAAoKniDmAQBfAgAcAAYKjwg4IgD/AAAAAA==.Chiridrake:BAAANQAECgEIAgAAAA==.Chlover:BAAANQAECgUIEgAAAA==.Chmap:BAAANQADCggJFQABNQAECgcIGAAdAKoiAA==.Chontosh:BAAANQAECgUIDwAAAA==.Chozenfate:BAAANQADCggIEQAAAA==.Chronuwu:BAAANQAECgYICwAAAA==.',
Ci='Cindymccain:BAABNQAECn8cAAIaAAgK+BONOQDtAQAaAAgK+BONOQDtAQAAAA==.',
Cl='Clearsight:BAAANQAECgUICQABNQAECgoKWAALAOUjAA==.Clemfandengo:BAAANQAECgYICwAAAA==.Cloudyshroom:BAAANQADCgQIBAAAAA==.',
Co='Cogs:BAAANQADCggIDgAAAA==.Cometh:BAAANQADCggIEAAAAA==.Compute:BAACNQAFFH8HAAIaAAIKPxSqCQCJAAAaAAIKPxSqCQCJAAA1AAQKf0YAAhoACgonH2wNACgDABoACgonH2wNACgDAAE1AAQKCAgQAAoAAAAA.Corursa:BAAANQAECgYICAABNQAECgYIDgAKAAAAAA==.Cozmowaffle:BAAANQADCgIIAgAAAA==.',
Cr='Critterr:BAAANQADCgEIAQAAAA==.Cronauer:BAAANQAECgUIEQAAAA==.Cryofrog:BAAANQADCgYICwAAAA==.',
Ct='Cthulusfiend:BAAANQAECgcIDwABNQAFFAcIHwAIANYkAA==.',
Cu='Cuppicakies:BAAANQADCgUIBwAAAA==.Cursyn:BAAANQAECgIIAgAAAA==.',
Da='Dabbington:BAABNQAECn8eAAMdAAoKiw2yIQB8AQAdAAoKiw2yIQB8AQAJAAQKZAUEYACCAAAAAA==.Daddilock:BAAANQAECgQIDQAAAA==.Daddyfatslap:BAACNQAFFH8GAAICAAIKGB9JHQC8AAACAAIKGB9JHQC8AAA1AAQKfyQAAgIACApVI8YHAGgCAAIACApVI8YHAGgCAAAA.Daggerz:BAABNQAECn8mAAITAAoKqx0wGwCkAgATAAoKqx0wGwCkAgAAAA==.Daguitas:BAABNQAECn8vAAITAAkK4BEDDABqAQATAAkK4BEDDABqAQAAAA==.Dahood:BAAANQAECgIIBQAAAA==.Danasty:BAAANQAECgQICQAAAA==.Danidakiesh:BAAANQAECgMIBgAAAA==.Daralina:BAAANQABCgIIAgAAAA==.Darbreezius:BAABNQAECn8nAAQUAAoKIR5jHQAPAwAUAAoK9R1jHQAPAwAMAAQKZRvNEABAAQAVAAIKBBkWTwCSAAAAAA==.Daribow:BAAANQADCgcICwAAAA==.Darkcoffee:BAABNQAECn8sAAMZAAoKWBZOBABXAQAeAAcKrRkAOADxAQAZAAkKxA9OBABXAQAAAA==.Darkvalk:BAAANQADCgIIAwAAAA==.Daroc:BAAANQAECggIDAAAAA==.Darvax:BAAANQAECgEIAQAAAA==.Datacenter:BAAANQAECggIEAAAAA==.Dattz:BAAANQAECgIIAgAAAA==.Dawgan:BAAANQAECgQIDAAAAA==.',
De='Deadlyfrog:BAAANQADCgcIDAAAAA==.Deamionn:BAAANQAECgQIBgAAAA==.Deathbauchs:BAAANQADCgcICwAAAA==.Deathlylove:BAAANQABCgYIBgAAAA==.Deathtreader:BAAANQADCggICAAAAA==.Delsym:BAABNQAECn8WAAINAAgKsgPpCwDKAAANAAgKsgPpCwDKAAAAAA==.Demoinc:BAACNQAFFH8FAAIYAAQK0gTzAQDyAAAYAAQK0gTzAQDyAAA1AAQKfzEAAxgACgr1GicHAIoCABgACQptHCcHAIoCABcABgpTEIvQAFIBAAAA.Denathus:BAAANQADCgYIDwAAAA==.Denovo:BAAANQADCggICAABNQAFFAMIBgAbAK4PAA==.Desipator:BAAANQAECgMIAwAAAA==.Destinyløl:BAABNQAECn8jAAIGAAkKbxH5GQCxAQAGAAkKbxH5GQCxAQAAAA==.',
Di='Di:BAAANQAECgUICAABNQAECgkJFAAHAHwbAA==.Diabolix:BAAANQADCgQIBwAAAA==.Dilo:BAABNQAECn8UAAIHAAkKfBurGwDRAgAHAAkKfBurGwDRAgAAAA==.Distortion:BAAANQAECgUIBQABNQAECgoKKAAbAPwcAA==.Divalatina:BAACNQAFFH8cAAIEAAcKzQeOCgC0AQAEAAcKzQeOCgC0AQA1AAQKfzAAAgQACgo1GMpSACICAAQACgo1GMpSACICAAAA.Divinefrog:BAAANQAECgQIBAAAAA==.',
Dj='Djmax:BAAANQADCgIIAgAAAA==.',
Dk='Dkthae:BAABNQAECn8yAAIHAAoKHx3SEAAmAwAHAAoKHx3SEAAmAwAAAA==.',
Dl='Dlxanomaly:BAABNQAECn8uAAIBAAoKaBiUCQAxAgABAAoKaBiUCQAxAgAAAA==.',
Do='Doeurden:BAAANQADCgYIBgAAAA==.Donttouchme:BAAANQADCgcIDAAAAA==.Doohickey:BAABNQAECn8aAAMRAAcKpQ4oIwAwAQARAAYKTw4oIwAwAQAXAAYK5Qih/ADjAAAAAA==.Dotsdaddy:BAAANQADCggJDwAAAA==.Doubledeez:BAAANQADCgIIAgAAAA==.Doubledz:BAAANQADCggIFQAAAA==.',
Dr='Dracslaya:BAAANQADCgcIDQAAAA==.Dragonaire:BAAANQADCgUIDQAAAA==.Dragondzntz:BAAANQAECgYIDQAAAA==.Dragonfrog:BAAANQADCgMIAwAAAA==.Dreamyeyes:BAABNQAECn8fAAIMAAcKmBGwCgDIAQAMAAcKmBGwCgDIAQAAAA==.Dregoth:BAAANQAECggIBQAAAA==.Drerein:BAAANQAECgYIDgAAAA==.Drägonfrog:BAAANQADCgQIBgAAAA==.',
Du='Dubz:BAAANQAECggIDAAAAA==.Dundeal:BAAANQADCgcIBwAAAA==.Dunkel:BAABNQAECn8uAAMfAAoKOxZ8NgBNAgAfAAoKOxZ8NgBNAgAaAAIK1w3smQBgAAAAAA==.Dupichu:BAABNQAECn8vAAIHAAoKjRrkIACtAgAHAAoKjRrkIACtAgAAAA==.',
Dy='Dyane:BAAANQADCggIEwAAAA==.Dynasti:BAAANQADCgMIAwAAAA==.',
Ea='Eataa:BAAANQAECgIIBAAAAA==.',
Eb='Ebonhammer:BAAANQADCgIIAgAAAA==.',
Ed='Edgyteiva:BAABNQAFFH8GAAIeAAQKygnqBQDXAAAeAAQKygnqBQDXAAAAAA==.',
Eg='Egrilo:BAAANQADCggICAAAAA==.',
Ei='Eileithyia:BAABNQAECn8cAAIOAAgKDwyIFAALAQAOAAgKDwyIFAALAQAAAA==.',
El='Elekastra:BAAANQAECgMIBAAAAA==.Ellonan:BAAANQADCggICwABNQAFFAQICQADAD4TAA==.Ellz:BAAANQAECgYIEAAAAA==.Elyndor:BAAANQADCgUIBQAAAA==.',
Em='Emopally:BAABNQAECn8qAAMfAAgKBhN4EwBBAQAfAAgKBhN4EwBBAQAaAAYK0g3lXQAvAQAAAA==.Emopower:BAAANQAECgUICwAAAA==.',
En='Enderr:BAABNQAECn8oAAIFAAkKAR6KDgD3AgAFAAkKAR6KDgD3AgAAAA==.Enegma:BAAANQADCgYICgAAAA==.Energètic:BAAANQADCgIIAgAAAA==.Enzini:BAAANQAECgQIBQAAAA==.',
Er='Erashi:BAAANQAECgQJBAAAAA==.',
Et='Eternalpain:BAAANQAECgIIAgAAAA==.',
Eu='Eupraxia:BAAANQAECggIDQAAAA==.',
Ev='Eviale:BAAANQAECgYICgAAAA==.Evilnight:BAAANQABCgQICwAAAA==.',
Fa='Falculan:BAAANQADCgEIAQAAAA==.Fallen:BAABNQAECn8UAAIfAAYKIxOfeAA3AQAfAAYKIxOfeAA3AQABNQABCgIJAgAKAAAAAA==.Fatherchung:BAAANQAECgQIBgAAAA==.Fayotbeanz:BAAANQABCgYIDAAAAA==.',
Fe='Felwyth:BAAANQAECgIIAgABNQAECgoKIwAYACgVAA==.Ferdinanna:BAAANQAECgUIBgAAAA==.Feythe:BAAANQAECggIDwABNQAECgkJKAAFAAEeAA==.',
Fi='Finneas:BAAANQADCgEIAQAAAA==.Fireworkxz:BAAANQAECgEIAgAAAA==.Fishhawk:BAAANQAECgYICgAAAA==.',
Fl='Flarehammer:BAABNQAECn8wAAMCAAoKMiD/IQCbAQACAAoK8h//IQCbAQADAAQKuhG7RgDUAAAAAA==.Flogh:BAABNQAECn8eAAIgAAgKKRYFAgBUAgAgAAgKKRYFAgBUAgAAAA==.',
Fo='Fomanshi:BAACNQAFFH8IAAIIAAUKNgwnBwAfAQAIAAUKNgwnBwAfAQA1AAQKf0AAAggACgpfHMYAAGUCAAgACgpfHMYAAGUCAAAA.Forleaf:BAAANQAECgQIBAAAAA==.Forsierra:BAAANQADCgEIAQAAAA==.Foxiji:BAAANQAECgIIAgAAAA==.',
Fr='Frexadin:BAAANQADCgYIBwAAAA==.Frexican:BAABNQAECn8xAAIGAAoKuhXFCAA5AgAGAAoKuhXFCAA5AgAAAA==.Fright:BAAANQAECgUIDQAAAA==.Frogleggs:BAAANQABCgQIBgAAAA==.Frogshock:BAAANQADCgUIBQAAAA==.',
Fu='Fupabean:BAAANQADCgcIBwAAAA==.Fure:BAAANQAECgYICwAAAA==.Fuupa:BAAANQADCgIIAgAAAA==.',
['Fí']='Fíg:BAAANQADCgYIBgAAAA==.',
['Fö']='Förbindelse:BAAANQAECgEIAQAAAA==.',
Ga='Gangdat:BAAANQAECgMIBwAAAA==.Garur:BAAANQAECgQIDAAAAA==.',
Ge='Genridge:BAAANQADCgYIDAAAAA==.Getowned:BAAANQADCggICwAAAA==.Gewl:BAAANQAECgcIDQABNQAECgkJKAAFAAEeAA==.',
Gh='Ghostmain:BAAANQADCggIEAAAAA==.',
Gi='Gilani:BAAANQAECgEIAQAAAA==.',
Gl='Glp:BAAANQAECggICQAAAA==.Glunt:BAAANQADCggICAABNQAECgkJFAAHAHwbAA==.',
Go='Gorpy:BAACNQAFFH8UAAQUAAgKcyKLBAAtAgAUAAYKcSSLBAAtAgAVAAIKyCBiBwC2AAAMAAEKch8zBwBnAAA1AAQKfy8ABBQACgosJqQOAFsDABQACQrsJaQOAFsDABUABwpvHOkJAFgCAAwAAQrTHmQnAE4AAAAA.Gotrott:BAAANQADCgEIAQAAAA==.',
Gr='Gravybones:BAAANQADCgcIFAAAAA==.Grayparse:BAAANQADCgQIBAAAAA==.Greenjesh:BAACNQAFFH8FAAIBAAQKVwsMLwAYAQABAAQKVwsMLwAYAQA1AAQKfyQAAgEACgrqF+FZAMwCAAEACgrqF+FZAMwCAAAA.Greensheesh:BAACNQAFFH8GAAIBAAMKOAyHEADbAAABAAMKOAyHEADbAAA1AAQKfysAAgEACQoxG0uCAHoCAAEACQoxG0uCAHoCAAE1AAUUBAgFAAEAVwsA.Greypilgram:BAAANQAECgMIBQAAAA==.Grimstank:BAAANQADCggJFQAAAA==.Grizzlygerm:BAAANQADCgUIBQAAAA==.Grizzlyoné:BAAANQAECgIIAwAAAA==.Gronck:BAAANQAFFAIIAwAAAA==.Grumbleface:BAACNQAFFH8WAAIEAAcKhBFFCADfAQAEAAcKhBFFCADfAQA1AAQKfycAAgQACgpxHqEUAC8DAAQACgpxHqEUAC8DAAAA.Grumbletron:BAABNQAECn8lAAIdAAkKph6RJwDMAgAdAAkKph6RJwDMAgAAAA==.Gröver:BAAANQAECgIIAgABNQAECgkJFAAHAHwbAA==.',
Gs='Gstatus:BAABNQAECn8YAAIPAAgKLQzIdwC7AQAPAAgKLQzIdwC7AQAAAA==.',
Gu='Gumbotron:BAAANQADCggICwAAAA==.Gunel:BAAANQAECgYICwAAAA==.',
Ha='Haawee:BAABNQAECn8gAAQCAAoKiRGXQQBDAQACAAoKiRGXQQBDAQADAAEKOQmFOQAuAAAEAAEK5gJkNAEjAAAAAA==.Haelresursus:BAAANQAECgQIBAABNQAECgoKNwABALIcAA==.Hailcthulhu:BAABNQAECn8ZAAIOAAcKBx5eJgATAgAOAAcKBx5eJgATAgAAAA==.Handcuffs:BAAANQAECgMJAwAAAA==.Handorn:BAAANQAECgQIBwABNQAFFAMICQAMAGkQAA==.Hanwha:BAAANQAECgYICwAAAA==.Harrower:BAABNQAECn8cAAIOAAcKfRnrEwAQAQAOAAcKfRnrEwAQAQAAAA==.Haze:BAAANQAECggIEQAAAA==.Hazzkul:BAABNQAECn87AAIGAAoKuCUEBADIAwAGAAoKuCUEBADIAwAAAA==.',
He='Healness:BAABNQAECn8gAAILAAkKkSHoFAAmAwALAAkKkSHoFAAmAwAAAA==.Helasam:BAAANQAECgIIAwAAAA==.Hellbourné:BAAANQAECgEIAQAAAA==.Helloboys:BAABNQAECn8oAAIUAAkKBBIpXwA6AgAUAAkKBBIpXwA6AgAAAA==.Helnome:BAAANQAECgQIBgABNQAECgQIDAAKAAAAAA==.Henzo:BAAANQABCgEIAQAAAA==.Herbavor:BAAANQAECgMIBQAAAA==.Hermes:BAABNQAECn8/AAMUAAoKzh2PCgAAAgAUAAkKox6PCgAAAgAVAAQKFBIGOADhAAAAAA==.Hermestrisme:BAAANQAECgEIBAAAAA==.',
Hi='Hiemultis:BAAANQADCggIGQAAAA==.',
Ho='Hogroxx:BAAANQADCgYIBgAAAA==.Holexplorer:BAABNQAECn8yAAIXAAkKNCPvIgAtAwAXAAkKNCPvIgAtAwAAAA==.Holytrashie:BAAANQAECgUIDwAAAA==.Honeybadger:BAABNQAECn8rAAQhAAkKbBihCACwAQAhAAkKbBihCACwAQAcAAUK5hlwGAB0AQAbAAUKJRgbXwBUAQAAAA==.Honnybuns:BAAANQAECgYIBwAAAA==.Hoofsmack:BAAANQADCggICgAAAA==.Hordeji:BAAANQAECgUIBQAAAA==.Hordeslayer:BAAANQADCgUICAAAAA==.Hornyvalk:BAAANQADCgEIAQAAAA==.',
Hs='Hsk:BAABNQAECn8dAAMNAAoK+xsXCABnAgANAAoK+xsXCABnAgABAAQKZg0cYQHyAAAAAA==.',
Hu='Hugostiglitx:BAAANQAECgIIAwAAAA==.Hulkaholic:BAABNQAECn8tAAMPAAoKOyDkBAArAgAPAAoKOyDkBAArAgAiAAMKww25KwCrAAAAAA==.Hulkclap:BAAANQABCgMIAwAAAA==.Hulkdemon:BAAANQABCgUIBwAAAA==.Hulkhunts:BAAANQABCgUIDAAAAA==.',
['Hÿ']='Hÿphy:BAAANQAECgIIAgAAAA==.',
Ia='Ianthor:BAAANQADCgUIBQAAAA==.',
Ic='Icecat:BAAANQAECgYIDwAAAA==.',
Il='Ilian:BAAANQADCgQICwAAAA==.Illionecho:BAAANQABCgUIBQAAAA==.',
In='Indoo:BAAANQABCgcIBQAAAA==.Innothule:BAAANQADCgUIBQAAAA==.Inseratum:BAAANQAECgEIAgAAAA==.Intrepidus:BAAANQADCgEIAQABNQAECgcICgAKAAAAAA==.Inê:BAABNQAECn8tAAMTAAkKsBS3BwCgAQATAAkKsBS3BwCgAQAQAAMK0g+YFACqAAAAAA==.',
Iq='Iqbal:BAAANQADCgEIAQABNQAECgoKKAAbAPwcAA==.',
Ir='Iriedraco:BAAANQABCgIIAgAAAA==.Irielite:BAAANQABCgQIBAAAAA==.',
Is='Ishaa:BAAANQAECgYICwAAAA==.',
It='Ithanksource:BAABNQAECn8nAAIEAAoKwhvQBwBJAgAEAAoKwhvQBwBJAgAAAA==.',
Iv='Ivincentl:BAAANQADCgUIBQAAAA==.',
Ix='Ixgangrxi:BAAANQADCgQIBAAAAA==.',
Ja='Jackassmcgee:BAAANQADCgEIAQAAAA==.Jackiep:BAAANQAECgQIAwAAAA==.Jadethunder:BAAANQADCgEIAQABNQAECgQIBwAKAAAAAA==.Jake:BAAANQAECgEIAQAAAA==.Jalana:BAAANQAECgEIAQAAAA==.Jankie:BAABNQAECn8hAAIeAAoKVRtpCwCZAQAeAAoKVRtpCwCZAQAAAA==.Jarnar:BAAANQAECgQIBAAAAA==.Jaxsin:BAAANQADCgEIAQAAAA==.',
Je='Jearemy:BAAANQADCgEIAQAAAA==.Jekster:BAAANQADCgEIAQAAAA==.Jenawolf:BAAANQAECgEIAQABNQAECgoKKAAGAIsgAA==.Jerva:BAABNQAECn8YAAMUAAoKuQ7+ZQApAgAUAAoKuQ7+ZQApAgAVAAEKSQI8hwAgAAABNQAFFAQICQALAMcYAA==.',
Ji='Jingburger:BAABNQAECn8lAAIDAAkKDRFAIgDQAQADAAkKDRFAIgDQAQABNQAECgkJLQATALAUAA==.Jinnosuke:BAAANQAECgYICwAAAA==.',
Jo='Joecelin:BAAANQAECgMIAwAAAA==.Johhnyp:BAACNQAFFH8FAAIJAAIKrxBwEwCTAAAJAAIKrxBwEwCTAAA1AAQKfxUAAgkACQrCE4wgADQCAAkACQrCE4wgADQCAAAA.Johnathanwow:BAAANQAECgQJBwAAAA==.Johnnytotem:BAABNQAECn8dAAMPAAkKchgWQgBtAgAPAAkKchgWQgBtAgALAAcKfAOYuwD0AAABNQAFFAIIBQAJAK8QAA==.Jonastus:BAAANQADCgQIBAAAAA==.Jonermar:BAAANQAECgcIBwAAAA==.',
Ju='Judgemental:BAAANQADCgUIBgAAAA==.Jurbil:BAAANQADCggICAAAAA==.Justicé:BAAANQAECgQIBgAAAA==.',
Jy='Jykyl:BAABNQAECn8nAAMcAAgKDBjPCwBtAgAcAAgKDBjPCwBtAgASAAIKChgTSQCJAAAAAA==.',
['Jê']='Jêkyl:BAAANQADCgEIAQAAAA==.',
Ka='Kaidoazure:BAAANQAECgMIBQABNQAECgUICwAKAAAAAA==.Kaipod:BAAANQAECgUJCgAAAA==.Kanrok:BAABNQAFFH8LAAILAAQKDR+TBAB7AQALAAQKDR+TBAB7AQAAAA==.Kaorrii:BAAANQAECgYICQAAAA==.Karlaia:BAAANQADCgEIAQAAAA==.Kattána:BAAANQAECgUIBwABNQAECgcIHwAEAK4SAA==.Kauthoon:BAAANQADCgQJBwAAAA==.Kaykotta:BAAANQADCgYIFgAAAA==.Kazademon:BAABNQAECn8vAAIOAAoKcw9QBgCrAQAOAAoKcw9QBgCrAQAAAA==.Kazmo:BAABNQAECn8oAAIMAAkKdBMkAwA9AQAMAAkKdBMkAwA9AQAAAA==.',
Ke='Kegheimer:BAAANQAECgIIAgABNQAECggIHwAcALQeAA==.Keigis:BAAANQAECgMIBgAAAA==.Kelko:BAAANQADCgUIBQAAAA==.Kensington:BAAANQAECgUICgABNQAECgoKNAAHAEkiAA==.Keyalovar:BAACNQAFFH8IAAIdAAcKwBOAAQBGAgAdAAcKwBOAAQBGAgA1AAQKf8oBAh0ACQqJJmIAABQEAB0ACQqJJmIAABQEAAAA.Keìra:BAAANQADCgYIBwAAAA==.',
Ki='Kimbecky:BAAANQADCgQJBQAAAA==.Kimchii:BAAANQAECgQIBgAAAA==.Kiritoo:BAAANQABCgQIBAAAAA==.Kishukae:BAABNQAECn8xAAIHAAoKlyRrAQDhAgAHAAoKlyRrAQDhAgAAAA==.Kishukun:BAAANQAECgEIAQABNQAECgoKMQAHAJckAA==.Kislosladkiy:BAAANQAECggIEAAAAA==.',
Kl='Klassik:BAAANQAECgUIDAAAAA==.',
Kn='Knitbeaniex:BAAANQAECgEIAQABNQAECgEIAgAKAAAAAA==.Knobsnob:BAABNQAECn8zAAQjAAoKpCFgBgAqAgAdAAoKDB0wJADcAgAjAAYKViFgBgAqAgAJAAMKqA4hZABvAAAAAA==.',
Kr='Kragden:BAAANQAECgQIBAABNQAECggIHwAcALQeAA==.Krasius:BAAANQAECgEIAQAAAA==.Kriztina:BAAANQAECgUICAAAAA==.Krizu:BAAANQADCggIDgAAAA==.Kronkk:BAAANQAECgQIBAAAAA==.Kropie:BAABNQAECn8aAAIBAAgKqhKowQABAgABAAgKqhKowQABAgAAAA==.Krågden:BAAANQAECgYICAABNQAECggIHwAcALQeAA==.',
Ku='Kunfuzion:BAABNQAECn8VAAIBAAcKpQb5GQFhAQABAAcKpQb5GQFhAQABNQAECgUIDAAKAAAAAA==.',
Ky='Kynga:BAAANQADCgUIBwABNQAECgIIAwAKAAAAAA==.Kynrinola:BAAANQABCgIIAgAAAA==.',
La='Ladrian:BAABNQAECn8dAAQUAAkKMBEjoQCUAQAUAAcKiBAjoQCUAQAVAAIKMgsHYABlAAAMAAEK7RsrJgBUAAAAAA==.Landoresh:BAAANQAECgQIDQAAAA==.Langers:BAAANQADCgEIAQAAAA==.Larabee:BAAANQADCgQIBAAAAA==.Larenieth:BAAANQAECgEIAQAAAA==.Larrykpinga:BAAANQAECgYIDAAAAA==.Larüd:BAABNQAECn8pAAILAAoKCxr2KQC7AgALAAoKCxr2KQC7AgAAAA==.Lasmon:BAABNQAECn8wAAIUAAgKaRBmgADlAQAUAAgKaRBmgADlAQAAAA==.',
Le='Legallyblind:BAABNQAECn8oAAIZAAkK3CT9AAC4AwAZAAkK3CT9AAC4AwAAAA==.Legit:BAAANQAECgMIBAAAAA==.',
Li='Lightblessed:BAAANQADCgcJBwABNQAECgoKIwANAOEVAA==.Lightsauce:BAAANQAECgQIBAAAAA==.Lightsmisery:BAAANQADCgYIDAAAAA==.Lillithx:BAAANQAECgMJAwAAAA==.Lillucy:BAAANQAECgcIEAAAAA==.Lilpa:BAAANQAECgUIBwABNQAECgkJLQATALAUAA==.Lilpä:BAAANQAECgcIDQABNQAECgkJLQATALAUAA==.Lindarenne:BAAANQADCgUIBQAAAA==.Lindree:BAABNQAECn8YAAQUAAgK2gzHrwBxAQAUAAYKCQ3HrwBxAQAMAAEK+QmZKwBAAAAVAAEK/A6cdAA6AAAAAA==.Lineria:BAAANQAECgcIBwAAAA==.Liquidfire:BAAANQADCgYIBgAAAA==.Lirang:BAAANQAECgYIEgAAAA==.Littlewashu:BAAANQABCgUIBwAAAA==.Livlife:BAAANQAECgcICAABNQAFFAQIBwAhAAwNAA==.Lizardfistin:BAACNQAFFH8fAAMIAAcK1iRJAADUAgAIAAcK1iRJAADUAgAkAAUK3x5JBACdAQA1AAQKfyYABAgACgrsJDoEAFsDAAgACgrsJDoEAFsDACQAAQoXIDYhAE0AACUAAQqKDcFNADgAAAAA.',
Lo='Loads:BAAANQAECggIBAAAAA==.Lockñlol:BAAANQABCgQIBAAAAA==.Logilock:BAAANQADCgQIAgAAAA==.Loni:BAAANQAECgQIEAAAAA==.Loonaimp:BAAANQAECgMJBQAAAA==.Lorthos:BAAANQABCgIIAgAAAA==.Lotús:BAACNQAFFH8FAAImAAIK0BbXBwCiAAAmAAIK0BbXBwCiAAA1AAQKfzIAAyYACgqXJCoNAAoDACYACQpGJCoNAAoDAAYAAgotJiIXAdQAAAAA.',
Lu='Lucithalle:BAAANQADCgYIBgAAAA==.Lumenox:BAACNQAFFH8JAAIDAAQKPhOaAgDbAAADAAQKPhOaAgDbAAA1AAQKf0MAAwMACgoDH9kAANoCAAMACgoDH9kAANoCAAIAAQqcB/PxADsAAAAA.Luminarria:BAABNQAECn8cAAIXAAcKpAqhVgDtAAAXAAcKpAqhVgDtAAAAAA==.Luminisong:BAABNQAECn8eAAIBAAgKcQy1WgAIAQABAAgKcQy1WgAIAQAAAA==.Lupomic:BAAANQAECgYIDgAAAA==.Lushice:BAAANQABCgIIAgAAAA==.',
Ma='Maeivalla:BAABNQAECn8mAAIdAAoKLBPMTQA7AgAdAAoKLBPMTQA7AgAAAA==.Magdaliana:BAABNQAECn+FAAImAAkKZySBAAAkAwAmAAkKZySBAAAkAwAAAA==.Mageler:BAABNQAECn8gAAMBAAoKJBV0sAAiAgABAAkKJhV0sAAiAgANAAEKGBUBQABEAAAAAA==.Magicpurro:BAABNQAECn8XAAIBAAoK5iIrIgBTAwABAAoK5iIrIgBTAwABNQAFFAcIHwAIANYkAA==.Maiajayde:BAAANQABCgIIAgAAAA==.Malicebane:BAAANQADCgQIBAAAAA==.Mallory:BAAANQAECggICwAAAA==.Malma:BAAANQADCgYIBgAAAA==.Mancane:BAABNQAECn83AAIBAAoKshzUDwDpAQABAAoKshzUDwDpAQAAAA==.Manstyle:BAAANQAECggIDwAAAA==.Margolis:BAAANQADCggICgABNQAFFAgIFAAUAHMiAA==.Margrathwin:BAABNQAECn8YAAIPAAgKrBD6cgDIAQAPAAgKrBD6cgDIAQAAAA==.Mari:BAAANQAECgEIAgAAAA==.Marxman:BAABNQAECn8WAAMmAAkK2hBFJAArAgAmAAkK2hBFJAArAgAGAAEK8AlkUAFCAAABNQAFFAYIFgAmAMgYAA==.Maseratix:BAAANQAECgQICQAAAA==.Mask:BAAANQADCgUIBQAAAA==.Masokhist:BAAANQABCggIEgAAAA==.Mauchs:BAAANQADCgUICQAAAA==.Maxthegreat:BAAANQABCgYIBgAAAA==.',
Me='Meedar:BAABNQAECn8bAAIdAAoKQw6cIACBAQAdAAoKQw6cIACBAQAAAA==.Meganite:BAAANQAECgEIAQAAAA==.Melaniatrump:BAAANQADCgEIAQAAAA==.Meningitis:BAAANQAECgEIAQABNQABCggICAAKAAAAAA==.Metara:BAAANQAECgYICAAAAA==.',
Mi='Miahas:BAAANQADCgMIAwAAAA==.Mikecoxwoll:BAABNQAECn8yAAMeAAoKwRHHCQCqAQAeAAoKwRHHCQCqAQAOAAMK3QHNZABWAAAAAA==.Milkmountain:BAAANQADCgIIAwAAAA==.Milkymoo:BAAANQADCggIEQAAAA==.Minalina:BAABNQAECn8cAAMEAAkKvg1VfACkAQAEAAkKvg1VfACkAQADAAIKpgKLZwBFAAAAAA==.Minalinapr:BAAANQAECggIDQAAAA==.Minalinaria:BAABNQAECn8VAAISAAkKLwu1JgBgAQASAAkKLwu1JgBgAQAAAA==.Mindedz:BAABNQAECn8vAAIPAAoKDBotNACoAgAPAAoKDBotNACoAgAAAA==.Minnow:BAABNQAECn8qAAIUAAkKwwsHPAAXAQAUAAkKwwsHPAAXAQAAAA==.Miren:BAABNQAECn9YAAILAAoK5SNzAADwAwALAAoK5SNzAADwAwAAAA==.Mirrorjade:BAAANQAECgYIAgABNQAECgkJFwAMANcmAA==.Mittsmitts:BAAANQAECgUIEgAAAA==.',
Mo='Mochiberry:BAAANQAECggIAgAAAA==.Moistbuns:BAABNQAECn8YAAMhAAgKpxELMwCCAQAhAAgKpxELMwCCAQAbAAEKkgHBwgAfAAAAAA==.Molatova:BAABNQAECn8gAAIGAAgKOBc8ZQBKAgAGAAgKOBc8ZQBKAgAAAA==.Moltael:BAAANQAECgQIBAABNQAECgoKMAAGAIslAA==.Moozart:BAAANQAECgMIBgABNQAECgoKLgAeAIYaAA==.Mooze:BAAANQAECgQIBAAAAA==.Morgia:BAAANQADCgUIBQAAAA==.Morgiana:BAAANQAECgQICgAAAA==.Morigann:BAAANQAECgIIAwAAAA==.Mortiferia:BAABNQAECn89AAIdAAoKPyDZCABZAgAdAAoKPyDZCABZAgAAAA==.Mortzx:BAAANQAECgQIBAABNQAECgUIBQAKAAAAAA==.Motown:BAACNQAFFH8IAAQUAAMKihn2KwCoAAAUAAIKNhf2KwCoAAAVAAEK8A5gCgBNAAAMAAEKAADrDABMAAA1AAQKfygABAwACgrrH8cBACwDAAwACgrwHscBACwDABUABQoWHzgUAM4BABQABApjGOVZAM4AAAAA.',
Ms='Msunohana:BAAANQADCgIIAgAAAA==.',
Mu='Mundane:BAAANQADCggICAAAAA==.Muyo:BAAANQADCgEIAQAAAA==.Muzzlefaulf:BAAANQABCgIIAgAAAA==.',
Mw='Mwooq:BAAANQADCgYICAAAAA==.',
My='Mystics:BAABNQAECn84AAInAAoKOx83AgBtAgAnAAoKOx83AgBtAgAAAA==.Mystiklight:BAAANQADCgUIBQABNQAECgQIBwAKAAAAAA==.Mythomagic:BAABNQAECn81AAIBAAoKtRo6BwBaAgABAAoKtRo6BwBaAgAAAA==.',
Na='Naebchi:BAAANQADCgUIBQAAAA==.Nahjiky:BAAANQADCgYIEQAAAA==.Naissaia:BAAANQAECgMIAwAAAA==.Nakotak:BAAANQABCgQICAAAAA==.Nanalady:BAAANQADCggICAAAAA==.Nastyjob:BAAANQAECgYIDgAAAA==.Natendo:BAAANQAECggICAAAAA==.Nazgar:BAAANQADCgUJBQAAAA==.',
Ne='Necronips:BAAANQADCgIIAgAAAA==.Neurosis:BAAANQADCggIIwAAAA==.Nezzthena:BAAANQADCgEIAQAAAA==.',
Ni='Niari:BAAANQAECgcICgAAAA==.Nibelung:BAABNQAECn8kAAMbAAgK5yNtGgD1AgAbAAgK5yNtGgD1AgAhAAEK2x8AAAAAAAAAAA==.Nikale:BAABNQAECn8fAAIcAAgKtB6QBACAAQAcAAgKtB6QBACAAQAAAA==.',
No='Nordy:BAAANQAECgcIEQAAAA==.Normadin:BAABNQAECn8hAAQCAAgK+BMNpgDUAQACAAgK+BMNpgDUAQADAAcKogUfPwD/AAAEAAIK0grUBwFoAAAAAA==.Norsefolk:BAAANQADCgIIAgAAAA==.Norseroch:BAAANQADCgYJCgABNQADCgIIAgAKAAAAAA==.',
Nv='Nvd:BAABNQAECn8dAAMOAAkKBx7jGwB3AgAOAAkKJR3jGwB3AgAeAAUKrRpfRQCbAQABNQAFFAIIAgAKAAAAAA==.',
Ny='Nyan:BAABNQAECn8YAAIcAAkKVRi8BwDhAgAcAAkKVRi8BwDhAgABNQAECgoKPQAEACsmAA==.Nysonnia:BAAANQAECgYIEwABNQAECgoKPQAEACsmAA==.',
Ob='Obsidianfire:BAAANQADCgcICwABNQAECgQIBwAKAAAAAA==.',
Od='Odonn:BAAANQAECgMIAwAAAA==.Odìnsôn:BAAANQADCggIIAAAAA==.',
Of='Ofcpenjr:BAAANQADCgQIBAAAAA==.',
Om='Omegafortswl:BAAANQAECgEIAQAAAA==.Omeni:BAAANQAECgQICQAAAA==.',
On='Oneozmouse:BAAANQABCgIIAgAAAA==.Oneshockiboi:BAAANQADCgMIAwAAAA==.Onewish:BAAANQADCgIIAgAAAA==.',
Oo='Oogi:BAAANQAECgQIBwAAAA==.Oogiie:BAAANQAECgYICQAAAA==.',
Or='Orbits:BAAANQAECgUIBQAAAA==.Oric:BAABNQAECn89AAIEAAoKKyYUAAALBAAEAAoKKyYUAAALBAAAAA==.',
Os='Oscargrouch:BAAANQAECggIEAABNQAECgkJFAAHAHwbAA==.',
Pa='Paledeath:BAAANQAECgIIAwABNQAECgQIBgAKAAAAAA==.Pallverize:BAAANQADCggICAAAAA==.Pannmann:BAAANQAECgcIEgAAAA==.Panzerhunt:BAABNQAECn8YAAMGAAkKvA8KJwB+AQAGAAkKyQwKJwB+AQAmAAYKDw6cQQBJAQABNQAECgoKKgACAPIdAA==.Panzerpala:BAABNQAECn8qAAICAAoK8h0cRQDFAgACAAoK8h0cRQDFAgAAAA==.Panzersham:BAABNQAECn8ZAAIiAAgK9BCcCABqAQAiAAgK9BCcCABqAQABNQAECgoKKgACAPIdAA==.Paperdaen:BAABNQAECn8dAAIEAAkKAhhRFwCbAQAEAAkKAhhRFwCbAQAAAA==.Papertanuon:BAAANQABCgQIBAABNQAECgkJHQAEAAIYAA==.Parkle:BAAANQADCggIJgAAAA==.Pastore:BAABNQAECn8iAAIbAAkKXg0kQgDuAQAbAAkKXg0kQgDuAQAAAA==.',
Pe='Peku:BAAANQAECgQIBQAAAA==.Pelee:BAAANQABCgIIAgAAAA==.Pelos:BAAANQADCgEIAQAAAA==.Peonmè:BAAANQAECgMIBAAAAA==.',
Pf='Pfeffernusse:BAACNQAFFH8WAAMmAAYKyBioCwCEAQAmAAUKvB6oCwCEAQAGAAIK7AadIwClAAA1AAQKfyEAAiYACgrMHl4KAEIBACYACgrMHl4KAEIBAAAA.',
Ph='Phalluic:BAAANQADCggIDgAAAA==.Philmage:BAAANQAECggIDAABNQAECgkJHQAJADAdAA==.Philpriest:BAABNQAECn8dAAMJAAkKMB1qFADBAgAJAAkKMB1qFADBAgAdAAMKLBKszgC4AAAAAA==.',
Pl='Plagued:BAAANQAECgQIBwABNQABCgIJAgAKAAAAAA==.Plagueis:BAAANQADCgMIAwAAAA==.',
Po='Pochaccob:BAACNQAFFH8IAAIhAAQKAg4bDQDeAAAhAAQKAg4bDQDeAAA1AAQKfycAAiEACgorHQUFABUCACEACgorHQUFABUCAAAA.Pokeysticks:BAAANQAECgMIBQAAAA==.Polymorph:BAAANQAECgEIAQAAAA==.Poncia:BAABNQAECn8nAAILAAgKYBvECwALAgALAAgKYBvECwALAgAAAA==.Potr:BAAANQADCgMIAwAAAA==.',
Pr='Pragmax:BAABNQAECn8gAAIbAAoKDRHeMwBHAgAbAAoKDRHeMwBHAgAAAA==.Praynation:BAAANQAECgIIAwAAAA==.Prediction:BAAANQAECgEIAgAAAA==.Pressbuttons:BAAANQAECggIDwABNQAECgkJFwAFADgfAA==.',
Pu='Puffcodan:BAAANQAECgEIAwAAAA==.Pugcival:BAAANQADCgUIBQAAAA==.Punîshër:BAAANQAECgUIBwAAAA==.Puppenance:BAAANQADCgUIBQAAAA==.Purgatoriwlf:BAABNQAECn8oAAMGAAoKiyBWNgDIAgAGAAoKiyBWNgDIAgAmAAcKHRJvNACqAQAAAA==.Purplehayz:BAAANQADCgYICwAAAA==.',
Py='Pyrogale:BAAANQAECgYIDQAAAA==.',
['Pó']='Póe:BAAANQAFFAEIAQABNQAFFAQIBwAHAJALAA==.',
Ql='Qlimax:BAAANQAECgEJAQAAAA==.',
Qu='Quadzilla:BAAANQAECgQICAAAAA==.Quem:BAAANQAECgcIBQABNQAECgkJFwAMANcmAA==.',
Ra='Rachet:BAAANQADCggIIgAAAA==.Ragnalock:BAAANQAECgQICQAAAA==.Ragnir:BAAANQAECgUICwAAAA==.Rainbowtits:BAAANQAECgMIAwAAAA==.Raker:BAAANQABCgcIDAAAAA==.Rarh:BAAANQADCgYICQAAAA==.Rathlokor:BAAANQADCgMJAwAAAA==.Rathlore:BAAANQADCgUIBQAAAA==.Rathorn:BAAANQAECgUIDgAAAA==.Rawdawgan:BAAANQADCgYIBwAAAA==.Rawrbotz:BAAANQAECgIIAwAAAA==.Razeneth:BAAANQAECggIBgAAAA==.',
Re='Rebelj:BAAANQAECgMIAgAAAA==.Rebornqt:BAAANQADCgIIAgAAAA==.Reforsaken:BAABNQAECn8uAAInAAoKSBm6CwC5AgAnAAoKSBm6CwC5AgAAAA==.Regicespice:BAAANQAECgMIAwAAAA==.Relarian:BAABNQAECn8hAAImAAkKfAy9CABYAQAmAAkKfAy9CABYAQAAAA==.Releimus:BAAANQAECggIEgAAAA==.Rentera:BAAANQADCggICAAAAA==.Revengeance:BAABNQAECn84AAIDAAoKTRcDAwABAgADAAoKTRcDAwABAgAAAA==.',
Ri='Rihhzen:BAAANQAECgIIAgAAAA==.Ripnfade:BAAANQADCggIDwAAAA==.Riptide:BAAANQAECgIIAgAAAA==.Rissler:BAAANQADCgUICQAAAA==.Rithallie:BAAANQAECgQIBAAAAA==.',
Rm='Rmplstilskin:BAAANQAECgUIBAABNQAECgcIGgARAKUOAA==.',
Ro='Roanoke:BAAANQAECgUICAAAAA==.Rocketsauce:BAAANQAECgUICgAAAA==.Romcrom:BAAANQAECgYICwAAAA==.Rommagicus:BAAANQADCggIDQABNQAECgYICwAKAAAAAA==.Rosalíe:BAAANQADCgQIBAAAAA==.Rougetoon:BAAANQADCggICAABNQAECgoKIQAEADwgAA==.Rouxnic:BAAANQADCgEIAQAAAA==.Roxen:BAABNQAECn8xAAIPAAoKkhsVBwD3AQAPAAoKkhsVBwD3AQAAAA==.',
Ru='Rubyhart:BAAANQADCgYIBgAAAA==.Rukenji:BAACNQAFFH8TAAIdAAcKlRXACAD+AQAdAAcKlRXACAD+AQA1AAQKfy8AAx0ACgrzHXgfAPICAB0ACgq/HXgfAPICACMABArLHAsSAAYBAAAA.Runehulk:BAAANQABCgQIBAAAAA==.Runíc:BAAANQADCgEIAQAAAA==.Rustycooch:BAAANQADCgEIAQABNQAECgoKNgALADglAA==.',
Ry='Ryuunosuke:BAABNQAECn84AAMlAAoKVRLRCgAVAQAlAAoKVRLRCgAVAQAkAAMK5RFdCQB0AAAAAA==.',
Sa='Sabers:BAAANQAECgcIDgAAAA==.Sabriinaa:BAAANQABCgMIBAAAAA==.Sabrinachi:BAAANQABCgIIAgAAAA==.Sabrinadin:BAAANQABCgQIBQAAAA==.Sadako:BAAANQAECgEIAQAAAA==.Sakkraa:BAACNQAFFH8JAAIMAAMKaRAcAQCXAAAMAAMKaRAcAQCXAAA1AAQKf08AAwwACgrrHdcAAHwDAAwACgrrHdcAAHwDABQAAQoAABhBATUAAAAA.Salla:BAAANQAECgMIAwAAAA==.Sandrawolf:BAAANQAECggICAABNQAECgoKKAAGAIsgAA==.Sannea:BAAANQADCgYIBwAAAA==.Saponite:BAAANQADCgIIAgAAAA==.Sarumon:BAABNQAECn8qAAQVAAkKiBy4AwAEAQAUAAcKWRleLQBAAQAVAAUKyh64AwAEAQAMAAEKyBXQKABIAAAAAA==.',
Sc='Schwimdy:BAABNQAECn8XAAIaAAkK9wfAGgBAAQAaAAkK9wfAGgBAAQAAAA==.Scrappey:BAAANQADCgYIBgAAAA==.',
Se='Secondlife:BAAANQAECgIIAgAAAA==.Secwolf:BAAANQAECggIEgABNQAECgoKKAAGAIsgAA==.Seeingeyedog:BAABNQAECn8kAAILAAkKiRpfRwBEAgALAAkKiRpfRwBEAgAAAA==.Seeya:BAAANQAECgIIBAAAAA==.Seiracon:BAAANQADCgEIAQAAAA==.Seraphicfrog:BAAANQADCgMIAwAAAA==.Sevenseconds:BAAANQADCgcIDQAAAA==.Sewerclam:BAAANQADCgQIBAAAAA==.',
Sh='Shadowscythe:BAAANQAECgYIEgAAAA==.Shadowzar:BAAANQAECgMIBQABNQAECgYIEgAKAAAAAA==.Shalissa:BAAANQAECgEIAQAAAA==.Shampann:BAAANQADCgEIAQAAAA==.Shanablack:BAAANQADCgUIBQAAAA==.Sharish:BAAANQABCggIBwAAAA==.Shaundel:BAABNQAECn89AAILAAgKzRomRwBFAgALAAgKzRomRwBFAgAAAA==.Shavocadoos:BAAANQADCggICAAAAA==.Shestrain:BAAANQADCgUIBgAAAA==.Shezmu:BAABNQAECn8nAAIHAAoKOyIkEQAkAwAHAAoKOyIkEQAkAwAAAA==.Shiftinman:BAAANQADCgMIAwAAAA==.Shiftintime:BAAANQADCgQIBAABNQAFFAUIEAAeACkgAA==.Shlorp:BAAANQADCgIIAgAAAA==.Shoopa:BAAANQAECgQIDQAAAA==.Shoopah:BAABNQAECn8nAAIBAAoKDBrYQwD8AgABAAoKDBrYQwD8AgAAAA==.Shoopslice:BAAANQAECgYIBwAAAA==.Shoopsmash:BAAANQAECggICgAAAA==.Short:BAABNQAECn82AAInAAoKPg2mCgCOAQAnAAoKPg2mCgCOAQAAAA==.Shunned:BAAANQAECgMIAwAAAA==.Shyok:BAAANQADCgEJAQAAAA==.Shädøwreeper:BAAANQAECgMIAwAAAA==.',
Si='Sicuro:BAAANQAECgUIBwAAAA==.Siduiss:BAAANQAECgQIBgAAAA==.Silmar:BAAANQADCgQIBAABNQAECgQIDAAKAAAAAA==.Silvrfoxx:BAAANQAECgYICwAAAA==.Silvänus:BAABNQAECn8zAAMhAAoKeSKtBwBIAwAhAAoKeSKtBwBIAwAbAAEKIwbfswAwAAAAAA==.Simsha:BAABNQAECn8VAAMLAAQK1xpMoQAzAQALAAQK1xpMoQAzAQAPAAQKRAj/7AC9AAAAAA==.',
Sk='Skinnylejend:BAABNQAECn8hAAMJAAoKrRgnGgB8AgAJAAkK1BcnGgB8AgAdAAMKRRYsUQDWAAABNQAFFAQIBgAeAMoJAA==.Skipperty:BAABNQAECn8bAAICAAkKagc0agDxAAACAAkKagc0agDxAAAAAA==.Skizzy:BAAANQADCgMIAwAAAA==.Skmoon:BAAANQADCgIIAgAAAA==.Skãr:BAAANQADCgYIBgAAAA==.',
Sl='Sloimmortal:BAAANQABCgQIBAAAAA==.',
Sm='Smiley:BAABNQAECn8eAAIFAAoK0xeMJQD3AQAFAAoK0xeMJQD3AQAAAA==.Smokedmeats:BAAANQADCgIIAgAAAA==.',
Sn='Snac:BAAANQAECgIJAwAAAA==.Snackrifice:BAAANQAECgMIAwAAAA==.Snacs:BAAANQADCgMIAwAAAA==.Sndancekd:BAABNQAECn8jAAICAAoKUxyyNgD0AgACAAoKUxyyNgD0AgAAAA==.Sneakybeanz:BAAANQAECgYIEQAAAA==.',
So='Sollan:BAAANQABCgUIBAAAAA==.Someperson:BAAANQAECgcICAAAAA==.Somoner:BAABNQAECn83AAMVAAoKQyFIAQCHAwAVAAoKQyFIAQCHAwAMAAEKAAB4LwA3AAAAAA==.Sompal:BAAANQAECggIDgABNQAECgoKNwAVAEMhAA==.Sourfaust:BAAANQABCgQIBAAAAA==.',
Sp='Sparklz:BAAANQADCgcIBwAAAA==.Sparksizzle:BAABNQAECn8hAAMBAAkK4BJlpgA1AgABAAkK4BJlpgA1AgAgAAMKpQWICACWAAAAAA==.Spiseyy:BAAANQADCgYIBgAAAA==.Spitfel:BAABNQAECn8YAAQVAAkKXyAwCAB8AgAVAAkK7xcwCAB8AgAUAAUK/h4fvgBQAQAMAAEKSRw3KgBEAAABNQAFFAcIGwAbAC4eAA==.Spitfirex:BAACNQAFFH8bAAIbAAcKLh6KAQDVAQAbAAcKLh6KAQDVAQA1AAQKfxkABBsACQpjGWM2ADgCABsACQpMGGM2ADgCABwAAgoTFwYvAJoAACEAAgofCkIyAGgAAAAA.Spreadshecat:BAABNQAECn8VAAIBAAgKNxHwzQDqAQABAAgKNxHwzQDqAQABNQAECgoKJwAEAMIbAA==.',
St='Standsinfire:BAAANQADCgcIBwAAAA==.Starofeos:BAAANQADCgcIDAAAAA==.Stoix:BAAANQADCgUIAgAAAA==.Stompymunk:BAAANQAECgQICgAAAA==.Stopzîlla:BAABNQAECn8xAAInAAoK7RGPCACpAQAnAAoK7RGPCACpAQAAAA==.Strûmpet:BAAANQAECgQIBAAAAA==.',
Su='Sugrdadi:BAAANQAECgMIBQAAAA==.',
Sy='Syleine:BAAANQAECggICQAAAA==.Sylmar:BAAANQAECgQIDAAAAA==.Syndora:BAABNQAECn8tAAIhAAkKVR9aEQDIAgAhAAkKVR9aEQDIAgAAAA==.',
Ta='Tacoboss:BAAANQAECgEIAQAAAA==.Taerun:BAAANQAECgMIBgAAAA==.Tahu:BAABNQAECn8oAAMbAAoK/BwWEwAvAwAbAAkKUSAWEwAvAwAhAAgK3AusDQBiAQAAAA==.Takal:BAAANQAECgEIAQAAAA==.Talorn:BAAANQADCgUIBwAAAA==.Talreth:BAABNQAECn8bAAINAAcK2hlLCgAmAgANAAcK2hlLCgAmAgAAAA==.Tappnlock:BAAANQABCgIIAgABNQAECgoKKAANABwTAA==.',
Te='Teake:BAAANQAECgIIAgAAAA==.Teddymoove:BAAANQADCgYIBgAAAA==.Teddyruxpin:BAAANQADCgcIBwAAAA==.Teddytotems:BAABNQAECn8tAAIPAAkKvBPjEgCAAQAPAAkKvBPjEgCAAQAAAA==.Teessel:BAAANQAECgQIBQAAAA==.Telemarketer:BAAANQAECggIEQAAAA==.Tempted:BAAANQAECgMIAwAAAA==.Tenebrisol:BAAANQAECgQIBQAAAA==.Ternal:BAAANQAECgQIBgAAAA==.Terrato:BAAANQAECgEIAQAAAA==.Terrorize:BAABNQAECn8YAAMUAAkKix2ZFwAqAwAUAAkKix2ZFwAqAwAVAAEKhyC+ZgBVAAAAAA==.Terrorley:BAAANQAECgYIEwAAAA==.Terrous:BAACNQAFFH8QAAMfAAUKygqcEAAAAQAfAAQKygqcEAAAAQAHAAEKAABGQQAOAAA1AAQKfykAAh8ACgo0GNoyAGACAB8ACgo0GNoyAGACAAAA.Tetranutra:BAAANQADCgQIBAAAAA==.',
Th='Thakur:BAABNQAECn8eAAMEAAoKcwskaADfAQAEAAoKcwskaADfAQACAAIKlAGXqwExAAAAAA==.Thatgùy:BAAANQAECgIIAgAAAA==.Theoslight:BAABNQAECn8UAAIEAAUKHxuEHQB2AQAEAAUKHxuEHQB2AQAAAA==.Thepain:BAAANQADCgQIBAAAAA==.Thepetmaster:BAAANQADCgUICgABNQAECgQIBgAKAAAAAA==.Thiccaxe:BAAANQAECgUIDgAAAA==.Thighler:BAAANQAECgcIEgAAAA==.Thordenson:BAAANQABCgIIAgAAAA==.Thrandorinil:BAAANQADCgQIBgAAAA==.Thraxia:BAAANQABCgQIBAAAAA==.Threxon:BAABNQAECn8hAAIeAAoKAxtBHQCvAgAeAAoKAxtBHQCvAgAAAA==.Thrine:BAAANQAECgQIBgAAAA==.Thunderfire:BAAANQAECgQIBwAAAA==.',
Ti='Tiaway:BAAANQABCggICAAAAA==.Timepally:BAAANQADCgYIBgAAAA==.Tinytimothy:BAAANQADCgIIAgAAAA==.',
To='Tokajok:BAACNQAFFH8JAAIZAAUKJgdXAwDPAAAZAAUKJgdXAwDPAAA1AAQKfzoAAw4ACgocHP8WAKcCAA4ACArVHf8WAKcCABkABQo6FLkHAPkAAAAA.Tokash:BAAANQADCggICQABNQAFFAUICQAZACYHAA==.Tokashi:BAABNQAECn8YAAIHAAkKsBC3SgDMAQAHAAkKsBC3SgDMAQABNQAFFAUICQAZACYHAA==.Tokeadin:BAABNQAECn8pAAIEAAkKDRNhEwC4AQAEAAkKDRNhEwC4AQAAAA==.Tokzillu:BAAANQADCgUIBQAAAA==.Tomaki:BAAANQADCgcJCgAAAA==.Topazd:BAAANQAECgQICAAAAA==.Toriimage:BAAANQAECgMIBAABNQAFFAEIAQAKAAAAAA==.Toriisneaky:BAAANQAFFAEIAQAAAA==.Toughluck:BAAANQAECgUICgAAAA==.',
Tr='Trackervalk:BAAANQADCgUIDAAAAA==.Traellissa:BAAANQAECgQIDAAAAA==.Treeady:BAAANQAECgMJAgAAAA==.Trenbölöne:BAABNQAECn8sAAIXAAkKBx1gPQDTAgAXAAkKBx1gPQDTAgAAAA==.Treyrin:BAABNQAECn8lAAICAAgKTRyacABOAgACAAgKTRyacABOAgAAAA==.Tritonia:BAAANQAECggICgAAAA==.Tritonian:BAACNQAFFH8aAAIDAAcK3yKQAADKAgADAAcK3yKQAADKAgA1AAQKfzAAAgMACgpzJtkAAOIDAAMACgpzJtkAAOIDAAAA.Trixio:BAABNQAECn8WAAMTAAkKdh8hMAAiAgATAAgKAyEhMAAiAgAnAAEKlxRFRwBJAAAAAA==.Trollmother:BAAANQADCggICAAAAA==.Trolloutcast:BAAANQAECgQICAABNQAFFAgIFAAUAHMiAA==.Tröut:BAAANQAECgQIBAAAAA==.',
Tu='Turtle:BAACNQAFFH8bAAIEAAYK5BOdBwDtAQAEAAYK5BOdBwDtAQA1AAQKfzgAAgQACgpsHecfAPACAAQACgpsHecfAPACAAAA.',
Tw='Twelph:BAAANQAECgMIBwABNQAECgUICgAKAAAAAA==.Twizzlestick:BAAANQABCgUIBQAAAA==.',
Ty='Tyluwu:BAABNQAECn8hAAIFAAgK9x7GFQCjAgAFAAgK9x7GFQCjAgAAAA==.Tyranis:BAAANQAECgQIBgAAAA==.Tyzz:BAAANQAECgEIAgAAAA==.',
['Tì']='Tìtân:BAAANQADCgcIBwAAAA==.',
['Tÿ']='Tÿ:BAABNQAECn8hAAMGAAoKTiFFFQBIAwAGAAoKTiFFFQBIAwAmAAIK/wjCdwBfAAAAAA==.',
Ud='Uddercleanse:BAAANQADCgYIBgABNQAECgoKMwAjAKQhAA==.',
Um='Umbrianna:BAABNQAECn82AAIeAAoK9AXjFgA3AQAeAAoK9AXjFgA3AQAAAA==.',
Un='Undeadashyra:BAAANQADCgYIBgAAAA==.Unstablemagi:BAAANQADCgYIBgAAAA==.',
Uv='Uvulabean:BAAANQAECgUIEAAAAA==.',
Uw='Uwuclapmexd:BAAANQADCgMJAwAAAA==.Uwuhunterxd:BAACNQAFFH8GAAImAAIKXwfdHwBzAAAmAAIKXwfdHwBzAAA1AAQKfzMAAyYACgr0GH8WAKcCACYACgpuGH8WAKcCAAYAAQpeIgBDAVoAAAAA.',
Va='Vaelowyn:BAAANQAECgcICwAAAA==.Vaelthyr:BAAANQADCggIEAABNQAFFAQICQADAD4TAA==.Vakar:BAABNQAECn8UAAIBAAcKygZ6iAC0AAABAAcKygZ6iAC0AAAAAA==.Valck:BAABNQAECn8XAAMMAAkK1ybLAACBAwAUAAkKlyYNBwCVAwAMAAgK8SXLAACBAwAAAA==.Valkorath:BAAANQAECgUIBQAAAA==.Valkyriee:BAAANQADCgMIBgAAAA==.Varninn:BAAANQADCgcIEAAAAA==.Vasha:BAAANQAECgYIDgAAAA==.',
Ve='Ventee:BAAANQAECgUIEQAAAA==.Vergere:BAAANQAECgIIAwAAAA==.Veritass:BAAANQAECgQIBQAAAA==.Verymelon:BAAANQAECgEIAQAAAA==.',
Vi='Vincentv:BAAANQADCgYIBgAAAA==.Virtuositee:BAAANQAECgMIAwABNQAECgoKNwAHAEwYAA==.Vitadin:BAAANQAECgQICQAAAA==.',
Vo='Voidaddict:BAAANQAECgMIAwABNQAFFAcIHwAIANYkAA==.Voidseeker:BAAANQABCgMIAwAAAA==.',
Vr='Vraugashan:BAAANQAECgcICgAAAA==.Vrice:BAAANQADCgIIAgAAAA==.',
['Vá']='Váprak:BAAANQADCgcICAAAAA==.',
Wa='Walmage:BAAANQADCgYIBgAAAA==.Wannabe:BAAANQABCgUIBQABNQAECgoKIQAGAE4hAA==.Warbuck:BAAANQADCgUIBAAAAA==.Warlas:BAAANQAECgEIAQAAAA==.Warthog:BAAANQAECgYIBgAAAA==.',
We='Wesson:BAABNQAECn8eAAIoAAgKyx3oAwC+AgAoAAgKyx3oAwC+AgAAAA==.',
Wh='Whompie:BAAANQABCgEIAQAAAA==.',
Wi='Winning:BAABNQAECn8yAAIGAAoKWiBwAwCyAgAGAAoKWiBwAwCyAgAAAA==.Wireless:BAABNQAECn84AAMnAAoKlBT2CACjAQATAAoK9xF2JABlAgAnAAgKNRH2CACjAQAAAA==.',
Wo='Wokker:BAAANQADCggIFAAAAA==.',
Wq='Wqwq:BAAANQADCgEIAQAAAA==.',
Wu='Wuköng:BAABNQAECn8eAAMFAAcKJQ16NQBpAQAFAAcKJQ16NQBpAQAWAAIKRAwSTAA1AAAAAA==.Wulfgarr:BAAANQAECgEIAQAAAA==.',
Xa='Xau:BAAANQAECgYICQAAAA==.Xaveak:BAAANQAECgMIAQAAAA==.',
Xe='Xeorc:BAAANQADCgcIBwAAAA==.Xeum:BAABNQAECn8rAAMdAAoKuBfMMgCdAgAdAAoKuBfMMgCdAgAJAAEKcQaKfwAsAAAAAA==.',
Xg='Xgirlfriend:BAAANQAECgQICwAAAA==.',
Xh='Xhar:BAABNQAECn8yAAIBAAoKCBPpCwASAgABAAoKCBPpCwASAgAAAA==.Xhyros:BAABNQAECn8yAAIIAAoKayLRAwBlAwAIAAoKayLRAwBlAwAAAA==.',
Xi='Xiahou:BAABNQAECn8zAAIBAAoKcCEKAwDSAgABAAoKcCEKAwDSAgAAAA==.',
Xo='Xoothette:BAAANQADCgcIBwABNQAFFAgIFAAUAHMiAA==.',
Ya='Yahnari:BAAANQADCgMIAwAAAA==.',
Ye='Yel:BAACNQAFFH8PAAIIAAYKjBhxAgD0AQAIAAYKjBhxAgD0AQA1AAQKfy8AAggACgpEI4ECAI0DAAgACgpEI4ECAI0DAAAA.',
Yu='Yuanfen:BAABNQAECn8ZAAIOAAYKLQ86GADrAAAOAAYKLQ86GADrAAAAAA==.Yunaraz:BAAANQADCgEIAQAAAA==.Yungshrimpy:BAAANQADCgYIBgAAAA==.',
Za='Zaffira:BAAANQAECgYIEAAAAA==.Zamlen:BAABNQAECn8uAAIBAAkKGRn/IgCHAQABAAkKGRn/IgCHAQAAAA==.Zaq:BAABNQAECn8hAAQaAAkKZQ4OFwBTAQAaAAkKZQ4OFwBTAQAHAAQKqwXamgCmAAAfAAEKAAAb4gAyAAAAAA==.Zaradissa:BAAANQAECggIBQAAAA==.Zargan:BAAANQAECgQIDAAAAA==.Zargstrike:BAAANQADCggIDQABNQAECgQIDAAKAAAAAA==.Zazie:BAABNQAECn8sAAIHAAkKAhciGwAXAQAHAAkKAhciGwAXAQAAAA==.',
Ze='Zedicuzz:BAABNQAECn8gAAIaAAgKLhApSwCNAQAaAAgKLhApSwCNAQAAAA==.Zeesala:BAAANQADCgUIBwABNQAECgoKPQAEACsmAA==.Zemms:BAAANQADCggICAAAAA==.',
Zi='Zinbad:BAAANQADCgYIBgAAAA==.Zippbang:BAAANQADCgEIAQAAAA==.Zithazar:BAAANQADCgIIAgAAAA==.Zivyrial:BAABNQAECn8gAAIOAAoKXyEjBADgAQAOAAoKXyEjBADgAQAAAA==.',
Zo='Zowa:BAAANQAECgMIAwAAAA==.',
Zu='Zugzugzugzug:BAACNQAFFH8GAAIaAAUKTSDvAwDlAQAaAAUKTSDvAwDlAQA1AAQKfzoABBoACgqOIs4AAPADABoACgqOIs4AAPADAB8ABApaJBReAJcBAAcAAwo4I+18AAYBAAAA.Zuken:BAAANQAECgQIBAAAAA==.Zuriki:BAAANQADCgMIAwAAAA==.',
['År']='Årdentmeta:BAAANQAECgYIDQABNQAECgYIDgAKAAAAAA==.',
['Ñe']='Ñemo:BAABNQAECn8hAAMGAAgKByOHLwDeAgAGAAgKByOHLwDeAgAmAAMKVhCuagCDAAAAAA==.',
['Ør']='Øreo:BAAANQADCggIGQAAAA==.',
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
