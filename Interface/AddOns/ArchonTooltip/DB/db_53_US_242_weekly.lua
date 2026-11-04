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

local lookup = {'Warlock-Destruction','Druid-Feral','Warrior-Arms','Druid-Balance','Hunter-BeastMastery','Unknown-Unknown','Mage-Arcane','Priest-Holy','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Elemental','Priest-Shadow','Monk-Windwalker','Paladin-Holy','Warlock-Demonology','DeathKnight-Blood','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Druid-Restoration','Warlock-Affliction','Evoker-Devastation','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Marksmanship','Rogue-Assassination','Evoker-Augmentation','Warrior-Protection','DemonHunter-Vengeance','Mage-Frost','Mage-Fire','Shaman-Enhancement','Druid-Guardian','Shaman-Restoration','Rogue-Outlaw','Warrior-Fury','Hunter-Survival','Monk-Brewmaster','Priest-Discipline','Rogue-Subtlety',}
local provider = {region='US',realm='Ysera',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aahnna:BAAANQAECgQICAABNQAECggIGQABAMoFAA==.',
Ab='Ababear:BAAANQAECggIEAABNQAFFAcIDAACACoXAA==.Abamnal:BAAANQADCgMIAwAAAA==.',
Ad='Adeki:BAAANQADCgYIBgAAAA==.Ademai:BAAANQABCgYICgAAAA==.',
Ag='Agakk:BAAANQADCggICAAAAA==.Agentbundles:BAAANQADCgUIBwAAAA==.',
Ah='Aharyah:BAAANQADCggICAAAAA==.Ahnna:BAAANQAECgEIAQABNQAECggIGQABAMoFAA==.',
Al='Alarrius:BAABNQAECn9HAAIDAAoKzBdkMgBOAgADAAoKzBdkMgBOAgAAAA==.Albedö:BAAANQAECgMIAwABNQAFFAQIDQAEAJEYAA==.Algo:BAAANQAECgIIAwABNQAFFAMIBQAFAKodAA==.Algrubeley:BAAANQABCgUIBQABNQAECgQIEAAGAAAAAA==.Alithirae:BAAANQADCgYICgAAAA==.Allionys:BAABNQAECn8cAAIHAAkKrR/NMgBXAgAHAAkKrR/NMgBXAgAAAA==.Aloris:BAABNQAECn8ZAAIIAAcK9B8TYwD3AQAIAAcK9B8TYwD3AQAAAA==.',
Am='Amanises:BAABNQAECn82AAMJAAgKWiDvFAAdAgAJAAgKWiDvFAAdAgAKAAIKJgsUmABkAAAAAA==.Amilara:BAABNQAECn8WAAILAAYK6QZwnQCZAAALAAYK6QZwnQCZAAAAAA==.',
An='Anakota:BAAANQABCgEIAQAAAA==.Ananaya:BAABNQAECn8cAAIFAAYKhhSJpAAkAQAFAAYKhhSJpAAkAQABNQAECgcIGgAMAFoPAA==.Anania:BAABNQAECn8aAAIMAAcKWg9rKQD9AAAMAAcKWg9rKQD9AAAAAA==.Andinestiri:BAABNQAECn8gAAIFAAgKcg3ylgDaAQAFAAgKcg3ylgDaAQAAAA==.Andolastrasz:BAAANQAECgUICAAAAA==.Angelic:BAAANQAECgYIDQAAAA==.Anightsong:BAAANQADCgQIBAAAAA==.',
Ao='Ao:BAABNQAECn82AAINAAoKDR6GDwDsAgANAAoKDR6GDwDsAgAAAA==.',
Ap='Apotic:BAABNQAECn8mAAIKAAkKKwTAbADrAAAKAAkKKwTAbADrAAAAAA==.Apuntar:BAAANQADCggIDgAAAA==.',
Aq='Aquamaree:BAAANQAECgEIAQAAAA==.Aquilla:BAACNQAFFH8MAAIFAAcK5wf3CAC6AQAFAAcK5wf3CAC6AQA1AAQKfygAAgUACgrnHx4/AK0CAAUACgrnHx4/AK0CAAAA.',
Ar='Archenea:BAAANQAECgUIBgAAAA==.Archenore:BAAANQADCggIEAAAAA==.Areeza:BAAANQABCgIIAgAAAA==.Argord:BAABNQAECn8iAAIOAAcKSg8nfAAQAQAOAAcKSg8nfAAQAQAAAA==.Arhianrod:BAAANQADCggICgAAAA==.Ariisa:BAAANQAECgYIDwAAAA==.Around:BAABNQAECn8aAAMBAAgKJw2NGwBvAAAPAAcKAAoKsgBsAQABAAMKYxGNGwBvAAAAAA==.Artty:BAEANQAECgYICQABNQAECgoKQQAQAKUmAA==.',
As='Askip:BAAANQADCgQICgAAAA==.Astrud:BAABNQAECn8aAAIHAAYKsRIGxwDwAAAHAAYKsRIGxwDwAAAAAA==.Asukka:BAABNQAECn8iAAMRAAoKQiIELACIAgARAAoKQiIELACIAgASAAQKWBUiRQDdAAAAAA==.Asëya:BAAANQADCggIDwAAAA==.',
At='Atomique:BAACNQAFFH8kAAITAAcKHAzRBgCdAQATAAcKHAzRBgCdAQA1AAQKf04AAhMACgpwIkMFAFgDABMACgpwIkMFAFgDAAAA.Attenborough:BAAANQADCgYIBgAAAA==.',
Au='Audiamer:BAAANQAECgIIAQABNQAECgoKNQAEAKsLAA==.Augustine:BAAANQABCgIIAgAAAA==.',
Av='Avesa:BAAANQAECgEIAQAAAA==.Avoidant:BAAANQADCggIEgAAAA==.',
Ay='Ayyahuasca:BAAANQABCgIIAgABNQAECgkJGQAEAMEGAA==.',
Az='Azazell:BAAANQAECgIIAgAAAA==.Azenea:BAABNQAECn8ZAAIBAAgKygVnIQBmAQABAAgKygVnIQBmAQAAAA==.',
Ba='Baculum:BAABNQAECn8ZAAMKAAgKURE1XAA4AQAKAAgKMQ81XAA4AQAQAAUKgBZBcAA0AQAAAA==.Badmoonrisin:BAAANQAECgMIAwAAAA==.Baieghzieghl:BAAANQADCgcIDgAAAA==.Bakulu:BAAANQAECgEIAQAAAA==.Ballzach:BAAANQAECgIIAgABNQAFFAgIIAAQAIQgAA==.Bandolero:BAAANQAECgUIBQAAAA==.Bazookabob:BAAANQAECggICwABNQAECgkJHgAUAN8dAA==.',
Be='Beangles:BAAANQADCggICAAAAA==.Beckyy:BAAANQADCgcIBwABNQAECgQIBQAGAAAAAA==.Beefstewed:BAAANQADCggIDwAAAA==.Bekkÿ:BAAANQADCgUICQABNQAECgQIBQAGAAAAAA==.Bellaboop:BAAANQADCgYIBgAAAA==.Bellapearl:BAABNQAECn8qAAIPAAoKTA6HYAB5AQAPAAoKTA6HYAB5AQAAAA==.',
Bi='Bigbutter:BAAANQAFFAIIAgAAAA==.Bittybow:BAAANQAECgQIBQAAAA==.Bittydrood:BAAANQAECgUIDQAAAA==.Bittylexis:BAABNQAECn8iAAIVAAkKqwmnDAAmAQAVAAkKqwmnDAAmAQAAAA==.',
Bl='Blackei:BAAANQADCgEIAQAAAA==.Blaiddgwyn:BAAANQADCgQIBQAAAA==.Blarcedeliu:BAAANQAECgMIBAABNQAECgYIFQAWAE4XAA==.Bleu:BAAANQAECggIDQABNQAECggIGAAXAGUQAA==.Blueaxle:BAAANQADCgEIAQAAAA==.Blur:BAABNQAECn84AAMYAAoKNhkOFgA2AgAYAAoK2xgOFgA2AgAZAAcKihM3MgCwAQAAAA==.Bluzzy:BAAANQADCgIIAgABNQAECgoKQwAHABIiAA==.Blèu:BAABNQAECn8YAAIXAAgKZRD6HAC2AQAXAAgKZRD6HAC2AQAAAA==.',
Bo='Boggrog:BAAANQAECgQICAAAAQ==.Bokan:BAAANQAECgUIEAAAAA==.Boneappetit:BAAANQADCgYIBgABNQAECgoKMAAEAMYUAA==.Borgasthe:BAAANQADCgEIAQAAAA==.Bovinehymn:BAEANQAECgQICAABNQAECgkJHQAOABMkAA==.Box:BAAANQAECgcICQAAAA==.',
Br='Braggs:BAAANQAECgQIBAAAAA==.Breathe:BAAANQAECgUIBQAAAA==.Brewballs:BAABNQAECn8lAAIXAAgKrwuoGgAiAQAXAAgKrwuoGgAiAQAAAA==.Brewjitzu:BAAANQADCgQIBAAAAA==.',
Bu='Bubbletea:BAAANQADCggIHgAAAA==.Bucket:BAABNQAECn8WAAIZAAgKqxBAKwAGAQAZAAgKqxBAKwAGAQAAAA==.Bunnicula:BAABNQAECn8lAAQVAAoKXhXNBgA6AgAVAAkKpRXNBgA6AgAPAAMKfAckGgGTAAABAAEKbBN3cAA/AAAAAA==.Bunter:BAAANQAECgIIAwAAAA==.',
['Bö']='Böömer:BAAANQAECgUIDgAAAA==.',
Ca='Caelphia:BAAANQAECgUIDgAAAA==.Caimage:BAABNQAECn8XAAIHAAgKZxIkzwDoAQAHAAgKZxIkzwDoAQAAAA==.Cainnaszun:BAAANQAECgYICwAAAA==.Cainnaszunn:BAAANQADCggIGwABNQAECgYICwAGAAAAAA==.Calistini:BAAANQADCgYICgAAAA==.Cameron:BAAANQADCgQIBAAAAA==.Catalight:BAAANQAFFAEIAQAAAA==.Catara:BAAANQAECgQIBAAAAA==.Cattform:BAAANQADCggICAAAAA==.Cavall:BAAANQAECgEIAQAAAA==.Caythus:BAACNQAFFH8lAAQPAAgKgiA8BAA1AgAPAAYKrx08BAA1AgABAAIKJiaTAwDdAAAVAAIKkh3ZBgBqAAA1AAQKfzMABAEACgrKJsABAGMDAAEACQq4I8ABAGMDAA8ACAq0JgkQAFIDABUAAgrXJl8ZAHQAAAAA.Caythuz:BAAANQAECgYICwABNQAFFAgIJQAPAIIgAA==.',
Ce='Celeana:BAAANQAECgEIAQAAAA==.Celencia:BAAANQADCgEIAQAAAA==.Ceryin:BAAANQADCgYICAAAAA==.',
Ch='Chadmcguffin:BAAANQADCgEIAQAAAA==.Chainheal:BAAANQABCgQIBAAAAA==.Chakabad:BAAANQAECgUIEgAAAA==.Chalgah:BAAANQAECgYIDgAAAA==.Charnyanya:BAAANQADCggICAABNQAECgcIDQAGAAAAAA==.Cheetò:BAAANQAECgUIBwAAAA==.Chenahala:BAAANQAECgUIEwAAAA==.Chloe:BAAANQADCggICAAAAA==.Chåni:BAABNQAECn9MAAIZAAoKNh9IDAAdAwAZAAoKNh9IDAAdAwAAAA==.',
Ci='Cimerone:BAAANQABCgYICQAAAA==.',
Ck='Ckayz:BAAANQAECgIIAgAAAA==.',
Cl='Clam:BAABNQAECn8gAAMFAAcKfgpHlgBBAQAFAAcKfgpHlgBBAQAaAAUKegJuXQCwAAAAAA==.Claw:BAABNQAECn8ZAAIEAAoK0QxfNQAtAQAEAAoK0QxfNQAtAQABNQAFFAYIDQAJAF4NAA==.Clisa:BAAANQABCgEIAQAAAA==.',
Co='Co:BAAANQAECggIEQAAAA==.Coldstonez:BAAANQADCggIEgAAAA==.Conanascus:BAAANQAECgIIAgABNQAECgoKQQAbAA0UAA==.Confessorr:BAAANQADCgYIBQABNQAECgkJGQAEAMEGAA==.Corrupteded:BAAANQAECgEIAQAAAA==.',
Cr='Crimsonmana:BAAANQADCgMIAwAAAA==.Crispysock:BAABNQAECn8WAAIEAAYKqQv5XQBZAQAEAAYKqQv5XQBZAQAAAA==.Crowe:BAAANQAECgQIBgAAAA==.',
Cy='Cynderr:BAABNQAECn8gAAIWAAgKABKEGADAAQAWAAgKABKEGADAAQAAAA==.',
Da='Daisymayhem:BAAANQABCgcICAAAAA==.Damagedgoods:BAAANQADCggICgAAAA==.Dangmart:BAAANQAECgEIAQAAAA==.Daquilla:BAAANQADCgUICgAAAA==.Darkfury:BAAANQAECgUIDgAAAA==.Darkisis:BAABNQAECn8ZAAIHAAYKLgfi2wDJAAAHAAYKLgfi2wDJAAAAAA==.Darknara:BAABNQAECn8uAAMQAAoK4B3GIACuAgAQAAkKBR3GIACuAgAJAAYKUxntLwA8AQAAAA==.Darkterror:BAAANQAECgQIBAABNQAECgYIGQAHAC4HAA==.Darkzy:BAAANQAECgEIAwAAAA==.Dartol:BAAANQAECgUIDAAAAA==.Dasubertakem:BAAANQAECgQIBAAAAA==.Dawni:BAABNQAECn8wAAQTAAoKgRMGEQCwAQATAAgKYBIGEQCwAQAWAAUK+RHkFQCsAAAcAAEKiAQWJgAsAAAAAA==.',
Dd='Ddz:BAAANQADCgUIBQAAAA==.',
De='Deathjeff:BAACNQAFFH8GAAIKAAIKexggEQCVAAAKAAIKexggEQCVAAA1AAQKfyYAAgoACgqqI2YHAG4DAAoACgqqI2YHAG4DAAAA.Deathsgates:BAAANQAECgUIDgABNQAFFAUIDgAbACQSAA==.Detala:BAAANQAECgEIAgAAAA==.Dethkeela:BAAANQADCgUIBQABNQAFFAUIDQAFAH8eAA==.',
Di='Didymus:BAAANQADCgUIBQAAAA==.Diereth:BAAANQABCgIIAgAAAA==.Dimos:BAAANQAECgUIDQAAAA==.Dinoll:BAAANQAECggIEQAAAA==.Dionizius:BAAANQADCgIIAgAAAA==.Dirtwhistle:BAABNQAECn8qAAIdAAkKZSQnAgCaAwAdAAkKZSQnAgCaAwAAAA==.',
Dr='Draconnt:BAAANQADCgYIBgABNQAECgYICwAGAAAAAA==.Dracont:BAAANQADCgUIBQABNQAECgYICwAGAAAAAA==.Dragondh:BAACNQAFFH8KAAIYAAUK1QfKDQC3AAAYAAUK1QfKDQC3AAA1AAQKfywAAhgACgrIGzElAHMCABgACgrIGzElAHMCAAAA.Dranlu:BAAANQAECgEIAgAAAA==.Drazsi:BAABNQAECn8WAAIBAAgKrAUwDwDCAAABAAgKrAUwDwDCAAAAAA==.Drekkara:BAAANQADCgQIBAABNQAECgYIGgAHALESAA==.Drosi:BAABNQAECn8xAAIRAAoKoxPFWwDkAQARAAoKoxPFWwDkAQAAAA==.Drovaal:BAAANQADCgUIBQAAAA==.',
Dy='Dyromancer:BAAANQADCgIJAgAAAA==.',
['Då']='Dåmmn:BAAANQAECgEIAQAAAA==.',
Ea='Earthesance:BAAANQAECgIIAwAAAA==.',
Eb='Ebeb:BAAANQAECggIEQAAAA==.',
Ed='Edgedweenie:BAAANQADCgQIBAAAAA==.',
Ei='Eiwe:BAAANQADCgYICQAAAA==.',
El='Eleanne:BAABNQAECn8sAAMEAAgKexKmTQCqAQAEAAcKwhKmTQCqAQAUAAUKfxSdNAAMAQAAAA==.Electricfury:BAAANQAECgUIBQAAAA==.Elementalism:BAAANQADCgQIBAAAAA==.Ellebasi:BAAANQAECgYIDAAAAA==.Ellebazy:BAABNQAECn8dAAISAAcK/hNOKgCLAQASAAcK/hNOKgCLAQAAAA==.',
Em='Emmri:BAAANQAECgYIDgAAAA==.Emoryax:BAAANQABCgEIAQAAAA==.',
En='Enazen:BAABNQAECn8VAAIWAAYKThf5GwCMAQAWAAYKThf5GwCMAQAAAA==.Enlighthyn:BAABNQAECn8cAAIOAAoK3x4oIADuAgAOAAoK3x4oIADuAgABNQAFFAUIDAAIAO4dAA==.',
Er='Erlas:BAAANQAECgMIAwAAAA==.Erui:BAAANQAECgUIEwAAAA==.',
Es='Esmeluz:BAAANQADCgMIAwAAAA==.',
Et='Etorion:BAAANQADCggIFwAAAA==.Etrexxig:BAAANQADCgcICwAAAA==.',
Ev='Evilrayne:BAABNQAECn9NAAIHAAoKwxkPNQBPAgAHAAoKwxkPNQBPAgAAAA==.',
Fa='Failpriest:BAAANQADCgEIAgABNQAECgYIDAAGAAAAAA==.Fanfiction:BAABNQAECn8cAAMTAAoK2xFbGwASAgATAAoK2xFbGwASAgAWAAEKAAD+QQAmAAAAAA==.Fatherfingur:BAAANQAECgMIAwAAAA==.',
Fe='Fearoshimâ:BAAANQAECgQIBwAAAA==.Featara:BAAANQADCgEIAQAAAA==.Feather:BAABNQAECn8cAAIEAAoK4BQrPQANAgAEAAoK4BQrPQANAgAAAA==.Felmonger:BAAANQAECgQICgAAAA==.Feloak:BAABNQAECn8hAAIeAAkKaQorEQABAQAeAAkKaQorEQABAQAAAA==.Feredir:BAABNQAECn8VAAIFAAYKkhLVrwAOAQAFAAYKkhLVrwAOAQAAAA==.',
Fi='Fires:BAABNQAECn8sAAQHAAgKIh+XXADGAgAHAAgKwx6XXADGAgAfAAYKlh2bFwA+AQAgAAEKAABhDQA4AAAAAA==.Fistandilius:BAABNQAECn8fAAIPAAgKYg0NeAA8AQAPAAgKYg0NeAA8AQAAAA==.',
Fo='Folexper:BAAANQADCggIDwAAAA==.',
Fr='Frostman:BAABNQAECn8uAAMQAAoKdyGZEQAgAwAQAAoKdyGZEQAgAwAKAAEKAADRngBTAAAAAA==.',
Fu='Furryfury:BAABNQAECn9HAAMXAAoK0BswDgCgAgAXAAoK0BswDgCgAgANAAgKyQp4KwAHAQAAAA==.Fusrodah:BAABNQAECn8kAAMTAAkKQhkcGQAuAgATAAgKHRkcGQAuAgAWAAIKeBYdHwBFAAAAAA==.Fuzzyewok:BAABNQAECn8xAAIOAAoKyxxsFADpAgAOAAoKyxxsFADpAgAAAA==.',
Ga='Gabaghoul:BAABNQAECn87AAIQAAoKXxzQFgApAgAQAAoKXxzQFgApAgAAAA==.Gameshark:BAABNQAECn8rAAIOAAcK5yXPEgD5AgAOAAcK5yXPEgD5AgAAAA==.Gawdzirra:BAAANQAECgcIEAABNQAECgoKGQAHAKEVAA==.Gaylordgerva:BAAANQAECgEIAQAAAA==.Gaz:BAAANQAFFAEIAQAAAQ==.',
Ge='Geauxaway:BAAANQADCgQIAgAAAA==.George:BAAANQADCggIGQAAAA==.',
Gh='Ghazghküll:BAAANQAECgQIBAAAAA==.Ghulrokk:BAAANQAECgYICAAAAA==.',
Gi='Gilidan:BAAANQABCgIIAgAAAA==.',
Gl='Gluum:BAAANQAECgQIBAAAAA==.',
Go='Gohibasi:BAAANQAECgYIEAAAAA==.Goodfel:BAAANQABCgMIAwAAAA==.Goops:BAAANQADCgEIAQAAAA==.Gormlaif:BAAANQADCgUIBQAAAA==.Gorzarpixx:BAAANQAECgEIAQAAAA==.Gossamerfeet:BAABNQAECn8aAAIIAAoKVxI4TwA3AgAIAAoKVxI4TwA3AgAAAA==.',
Gr='Graceosilver:BAABNQAECn8UAAIhAAUKMgH2MwBCAAAhAAUKMgH2MwBCAAAAAA==.Gregnor:BAABNQAECn8xAAUCAAoKeBROCgDsAQACAAoKeBROCgDsAQAEAAYKVAYzbAAaAQAiAAQKTgjzRQCbAAAUAAQKmwOaZQBvAAAAAA==.Gremöry:BAABNQAECn8fAAMjAAgKSRNYiAB1AQAjAAgKSRNYiAB1AQALAAYKTxTKmgBiAQAAAA==.Grimmler:BAAANQABCgEIAQAAAA==.Grippysock:BAAANQAECgIIAgAAAA==.Grover:BAABNQAECn8mAAIRAAoKpRN4ggAjAgARAAoKpRN4ggAjAgAAAA==.Grumpybunbun:BAABNQAECn8zAAIIAAoKihfDJQCHAgAIAAoKihfDJQCHAgAAAA==.Grüm:BAABNQAECn8VAAIQAAYKrBuuNABLAQAQAAYKrBuuNABLAQAAAA==.',
Gu='Guldangraham:BAAANQAECggIAgABNQAECggIFAAkAI8aAA==.Guppy:BAAANQADCgYIBgAAAA==.',
Gy='Gyorge:BAAANQADCgUIBQAAAA==.',
['Gå']='Gårrus:BAABNQAECn81AAIFAAkKuxliSQABAgAFAAkKuxliSQABAgAAAA==.',
['Gô']='Gôrbag:BAAANQADCgUIBQAAAA==.',
Ha='Haarl:BAAANQADCgcIBwAAAA==.Hairypotter:BAAANQAECgEIAQABNQAECgUIEwAGAAAAAA==.Halazzi:BAAANQAECgEIAgAAAA==.Haldar:BAABNQAECn8gAAIOAAoK1hKGNgANAgAOAAoK1hKGNgANAgAAAA==.Hallie:BAABNQAECn8WAAIfAAYKagmdIADkAAAfAAYKagmdIADkAAAAAA==.Harlu:BAABNQAECn8gAAILAAcK5wUGewDjAAALAAcK5wUGewDjAAAAAA==.Hartbroke:BAABNQAECn8jAAIRAAcKCxophwB+AQARAAcKCxophwB+AQAAAA==.Haunter:BAAANQAECgQIDAABNQAECgkJHgAUAN8dAA==.Hayeon:BAAANQAECgMIAgAAAA==.',
He='Helbourne:BAABNQAECn8gAAIYAAkKzhToJgCXAQAYAAkKzhToJgCXAQAAAA==.',
Hi='Hijjiup:BAAANQADCgQIBAAAAA==.',
Ho='Holybunbun:BAAANQAECggIEQAAAA==.Holyrollerz:BAAANQADCgYIBgAAAA==.Homeydagreat:BAAANQAECgEIAQAAAA==.',
Hu='Huna:BAAANQADCgYIBgABNQAECgUIHwAlAIIXAA==.Hunsx:BAAANQAECggICgAAAA==.Huntingpups:BAAANQADCggICAAAAA==.',
Hw='Hwanwok:BAABNQAECn8qAAINAAkKdRSdFwC/AQANAAkKdRSdFwC/AQAAAA==.',
['Hâ']='Hânzö:BAAANQADCgMIAwAAAA==.',
Ia='Iamwarlock:BAAANQAECgQICgAAAA==.',
Ic='Icemage:BAAANQAECgMIBgAAAA==.',
Id='Ideal:BAAANQAECgEIAQAAAA==.',
Ig='Ignited:BAABNQAECn8aAAIHAAYKiAnH6wCvAAAHAAYKiAnH6wCvAAAAAA==.',
Il='Ilotei:BAAANQADCgcIBwAAAA==.',
Im='Imadragon:BAABNQAECn8qAAIWAAoKCgw6GADFAQAWAAoKCgw6GADFAQAAAA==.Imbac:BAAANQAECgEIBAAAAA==.Imdeadguy:BAABNQAECn8pAAIdAAoKFyDzBgDxAgAdAAoKFyDzBgDxAgAAAA==.',
In='Inarian:BAAANQADCgYIBgAAAA==.',
Ir='Irilara:BAAANQADCggIIwAAAA==.Ironhelmhtr:BAAANQAECgQIBQAAAA==.',
Is='Istian:BAAANQADCgQIBgAAAA==.',
Ja='Jaayk:BAABNQAECn8nAAIbAAoKiSBVAwD0AgAbAAoKiSBVAwD0AgAAAA==.Jace:BAAANQAECgMIAwAAAA==.Jazlee:BAABNQAECn8gAAIdAAcKPxzbDgCQAQAdAAcKPxzbDgCQAQAAAA==.',
Je='Jealous:BAAANQAECgEIAQABNQAECgcIDAAGAAAAAA==.Jefflock:BAAANQADCgEIAQABNQAECgcIFQAFAF8WAA==.Jezmund:BAABNQAECn8ZAAIUAAUK+RhZNgBpAQAUAAUK+RhZNgBpAQAAAA==.',
Ji='Jinathy:BAABNQAECn8yAAIRAAoKxRFXgwCFAQARAAoKxRFXgwCFAQAAAA==.Jinxed:BAAANQADCgYIBgAAAA==.',
Jo='Jolyñ:BAABNQAECn8jAAIIAAoKFBNwMwA8AgAIAAoKFBNwMwA8AgABNQAECgoKLgAmAOgNAA==.',
Ju='Juaranir:BAABNQAECn8rAAIiAAgK4BVIGgB6AQAiAAgK4BVIGgB6AQAAAA==.Judgementall:BAAANQADCgQIBAAAAA==.Juicébòx:BAAANQAECgIIAgAAAA==.Justac:BAAANQAECgQIBwABNQAECgUICAAGAAAAAA==.Justdrood:BAAANQAECgUICAAAAA==.',
Jw='Jwst:BAAANQAECgMIAwAAAA==.',
['Jà']='Jàß:BAABNQAECn8bAAIEAAgK/xRPPAATAgAEAAgK/xRPPAATAgAAAA==.',
['Já']='Jáß:BAABNQAECn8aAAIOAAkKYx7NGgALAwAOAAkKYx7NGgALAwAAAA==.',
['Jä']='Jäb:BAABNQAECn8WAAIFAAkKpR5aRgAJAgAFAAkKpR5aRgAJAgAAAA==.',
Ka='Kahleah:BAAANQADCgcIBAAAAA==.Kaieni:BAAANQADCgUIBQAAAA==.Kaldonor:BAABNQAECn9GAAIKAAoKNw8/KgDPAQAKAAoKNw8/KgDPAQAAAA==.Kalenia:BAABNQAECn9KAAIjAAoKvyGaCABxAwAjAAoKvyGaCABxAwAAAA==.Kalvayre:BAAANQAECgUIDQAAAA==.Kanzoorb:BAABNQAECn8pAAMHAAoKKx2mVADXAgAHAAoKKx2mVADXAgAfAAEKIBdoNQA6AAAAAA==.Kareshka:BAABNQAFFH8HAAMfAAUKFQ20BADIAAAHAAMKAwcXOwDYAAAfAAMKVRG0BADIAAAAAA==.Karinea:BAEBNQAECn8XAAInAAcK8gWMFwCNAAAnAAcK8gWMFwCNAAAAAA==.Karpana:BAEBNQAECn81AAMSAAkKVRSwLwBhAQARAAkKLhBm1gBvAQASAAUKbB2wLwBhAQAAAA==.Karreena:BAAANQADCgYIBgAAAA==.Karworg:BAAANQADCggIFQAAAA==.Kashir:BAABNQAECn8UAAMWAAYKOxp+EAAAAQAWAAYKOxp+EAAAAQATAAEK6CHrRwBiAAAAAA==.Kashira:BAAANQADCggIEgABNQAECgYIFAAWADsaAA==.Kathelee:BAAANQAECgcIDQAAAA==.Kaythewitch:BAAANQAECgcIBwAAAA==.Kazimirah:BAAANQAECgEIAQAAAA==.Kazrael:BAABNQAECn8ZAAMeAAcKrhciDgAwAQAeAAYKlhsiDgAwAQAZAAEKEAiOTwAyAAAAAA==.',
Ke='Keekat:BAAANQADCggIGAAAAA==.Kevinbeacon:BAEBNQAECn8dAAIOAAkKEyTEJADXAgAOAAkKEyTEJADXAgAAAA==.',
Kh='Kharnij:BAABNQAECn8XAAMRAAYKZQ232gDoAAARAAYKZQ232gDoAAAOAAIK8wJBGQFBAAAAAA==.Khaíbit:BAAANQADCgYIBgAAAA==.Khonsu:BAABNQAECn8uAAQPAAoKSxQEdQBDAQAPAAgKOBYEdQBDAQAVAAQKJg4jFACwAAABAAEKEBOecAA/AAAAAA==.Khryy:BAAANQADCgUIBQABNQADCgUIBQAGAAAAAA==.',
Ki='Kiamei:BAAANQAECgEIAQAAAA==.Kikora:BAAANQADCgcIDQAAAA==.Kissandia:BAAANQAECgcIBwAAAA==.Kittykitty:BAABNQAECn88AAMjAAoKkSDmEAALAwAjAAoKkSDmEAALAwALAAUKghZ9qABDAQAAAA==.',
Ko='Kolzane:BAECNQAFFH8RAAIFAAcKuCOfAAC5AgAFAAcKuCOfAAC5AgA1AAQKfy0AAgUACgplJmAJACwDAAUACgplJmAJACwDAAAA.',
Kr='Krezz:BAABNQAECn8gAAIdAAkK6BpRCgDrAQAdAAkK6BpRCgDrAQAAAA==.',
Ku='Kumojo:BAAANQADCggICAAAAA==.Kurna:BAAANQADCgEIAQAAAA==.Kuulas:BAACNQAFFH8MAAIFAAUKYQ+WDgBtAQAFAAUKYQ+WDgBtAQA1AAQKfyEAAgUACgp0G6QwANoCAAUACgp0G6QwANoCAAAA.',
Ky='Kynlyn:BAAANQADCgYIDgAAAA==.Kyth:BAABNQAECn84AAMSAAoKDRi1GAAxAgASAAgK6Ru1GAAxAgARAAMKdwyuMgFtAAAAAA==.Kythlock:BAAANQADCgYIBQABNQAECgoKOAASAA0YAA==.Kythrax:BAAANQAECgQIBAABNQAECgoKOAASAA0YAA==.Kythtok:BAAANQAECgUIBQABNQAECgoKOAASAA0YAA==.',
La='Lanx:BAAANQAECgIIAgAAAA==.Laquatas:BAABNQAECn8jAAIQAAgKWh6mJwCCAgAQAAgKWh6mJwCCAgAAAA==.Laylanduin:BAAANQADCgEIAQABNQAFFAIIBgAKAHsYAA==.',
Le='Leadfarmer:BAAANQAECggIBAAAAA==.Lenash:BAAANQAECgIIAgABNQABCgIIBAAGAAAAAA==.',
Li='Lichlighter:BAAANQADCgEIAQAAAA==.Lifebloomer:BAAANQAECgEIAQABNQAFFAgIIAAQAIQgAA==.Lightguard:BAABNQAECn82AAIRAAkK/hguRAAqAgARAAkK/hguRAAqAgAAAA==.Likesitruff:BAAANQADCgcICQAAAA==.Lilolock:BAAANQAECgUIEgAAAA==.Littlehell:BAABNQAECn8nAAIjAAkKQxraKwBGAgAjAAkKQxraKwBGAgAAAA==.Liuying:BAAANQAECgYIBgABNQAECgoKMAAEAMYUAA==.',
Lo='Lothrik:BAABNQAECn8UAAQMAAgK9AtBLQDjAAAMAAcKYgdBLQDjAAAIAAEKYgGg6wAhAAAoAAEKBAKtMgAcAAAAAA==.',
Lu='Lucaafer:BAAANQAECgcICgABNQAECgkJHwANAOkTAA==.Luda:BAABNQAECn8UAAIPAAgKuQ92mACqAQAPAAgKuQ92mACqAQABNQAECgoKGQAHAKEVAA==.Ludaa:BAABNQAECn8ZAAIHAAoKoRWaOwA3AgAHAAoKoRWaOwA3AgAAAA==.Ludahealz:BAAANQADCgEIAQABNQAECgoKGQAHAKEVAA==.Lunamoonclaw:BAABNQAECn8UAAIaAAcKdAZ2QQBJAQAaAAcKdAZ2QQBJAQAAAA==.Lunaspire:BAAANQADCgIIAgAAAA==.',
Ly='Lyntrax:BAAANQAECgQIBgAAAA==.Lyssandria:BAABNQAECn8VAAMfAAoK2wmmGwAUAQAfAAgKoAqmGwAUAQAHAAQK8QaTGQFnAAAAAA==.Lyzoldas:BAABNQAECn8mAAIRAAoKFxI5eQCbAQARAAoKFxI5eQCbAQAAAA==.',
['Lö']='Löwryder:BAABNQAECn8WAAILAAYKjAkAkgCvAAALAAYKjAkAkgCvAAAAAA==.',
Ma='Madness:BAAANQADCgYIBwABNQAECgkJKwALALEMAA==.Mae:BAABNQAECn8dAAQTAAgKxBqYCwAzAgATAAgKxBqYCwAzAgAWAAEKtx+aOABKAAAcAAEKEQFVKQAVAAABNQABCgIIAgAGAAAAAA==.Maemura:BAABNQAECn8VAAIFAAYK7wicygDYAAAFAAYK7wicygDYAAAAAA==.Magdalaiina:BAABNQAECn8nAAIOAAcK2h9XKABbAgAOAAcK2h9XKABbAgAAAA==.Magicdaisee:BAAANQADCgYIBgAAAA==.Magusman:BAAANQAECggICAABNQAECgoKLgAQAHchAA==.Magîkarp:BAABNQAECn8eAAMXAAkKvhiUEwCLAQAXAAkKvhiUEwCLAQANAAMKnRDSXgBlAAAAAA==.Malchromatus:BAABNQAECn8qAAMTAAoKYQxrJQCTAQATAAoKYQxrJQCTAQAWAAcKWwaXIQBCAQAAAA==.Marcosio:BAAANQAECgUIDQAAAA==.Marmaladia:BAAANQADCggIDQAAAA==.Marsala:BAABNQAECn8XAAIEAAkKaQu9SgC7AQAEAAkKaQu9SgC7AQAAAA==.Mavik:BAAANQAECggIAgAAAA==.Maylater:BAAANQAECgMIAwABNQAECgkJKAANAAMTAA==.',
Me='Mearkman:BAABNQAECn8WAAIFAAUKaRjuzQBlAQAFAAUKaRjuzQBlAQAAAA==.Meatyfajita:BAABNQAECn8rAAIOAAoKsSWADABkAwAOAAoKsSWADABkAwAAAA==.Megumim:BAAANQADCgQIBAAAAA==.Meinfurion:BAABNQAECn8iAAMEAAkK5hOlIgCyAQAEAAkK5hOlIgCyAQAUAAgK+BAzLwChAQAAAA==.Meinstrom:BAAANQADCggICAABNQAECgkJIgAEAOYTAA==.Meladie:BAAANQAECgEIAQAAAA==.Melevolent:BAAANQABCgQIBAAAAA==.Melon:BAAANQADCggICAAAAA==.Memedecay:BAABNQAECn9GAAQJAAoKwR78HgDRAgAJAAgKJyL8HgDRAgAKAAoKmBj+GwA2AgAQAAIKKxDluwBQAAAAAA==.Memeonhuntër:BAAANQADCgMIAwABNQAECgoKRgAJAMEeAA==.Merit:BAAANQADCggIEAABNQAECgoKOAAYADYZAA==.Merlinthos:BAABNQAECn8oAAMfAAoKygjLDACCAQAfAAoKyAjLDACCAQAHAAgKMAQuFgFnAQABNQAECgoKQQAbAA0UAA==.Messra:BAAANQADCgMIAwAAAA==.Metaljack:BAABNQAECn8xAAMfAAoKwh2UCQDLAQAHAAkK6huWiABtAgAfAAcKKx+UCQDLAQAAAA==.',
Mi='Miasma:BAAANQADCgUIBQABNQAECgQIBAAGAAAAAA==.Midith:BAAANQADCgYIBgAAAA==.Mikasa:BAAANQADCgMIAwAAAA==.Minecraft:BAABNQAECn8rAAIlAAoK8RvMBQA8AgAlAAoK8RvMBQA8AgAAAA==.Mingyue:BAAANQAECgUIBQABNQAECgoKMAAEAMYUAA==.Mirajåne:BAACNQAFFH8HAAIMAAMK4RAPDgDzAAAMAAMK4RAPDgDzAAA1AAQKf0AABAwACgqbHBMPAAEDAAwACgqbHBMPAAEDAAgABgpYFYymACEBACgAAQq6Aq0tACkAAAE1AAUUBAgNAAQAkRgA.Mishaweha:BAABNQAECn8fAAIjAAgK6BOCQgDZAQAjAAgK6BOCQgDZAQAAAA==.Missdowtfire:BAAANQADCgIIAgAAAA==.Mitos:BAAANQAECgEIAwAAAA==.',
Mo='Modar:BAABNQAECn8lAAMjAAoKzRURRwBFAgAjAAoKzRURRwBFAgALAAMKsgQQ5gDLAAAAAA==.Monkas:BAAANQAECgEIAQAAAA==.Moonhoof:BAAANQADCgIIAgAAAA==.Moonrid:BAAANQADCggIEwAAAA==.Mornanden:BAAANQAECgQIBQAAAA==.',
Mu='Murdafest:BAAANQAFFAEIAQAAAA==.Musterd:BAAANQADCgYJDQAAAA==.',
['Må']='Måddløck:BAAANQADCgYIDAAAAA==.',
Na='Nahray:BAAANQADCgQIBAAAAA==.Namaera:BAAANQADCgcIBwAAAA==.Navatath:BAAANQAECgMIBgABNQAFFAcIKAAHAL8kAA==.',
Ne='Neiidra:BAAANQAECgUICAAAAA==.Nepheleah:BAACNQAFFH8OAAIRAAUKgBkTDwDmAAARAAUKgBkTDwDmAAA1AAQKfzMAAhEACgqiIqIPAIwDABEACgqiIqIPAIwDAAAA.Nesca:BAABNQAECn8iAAIjAAcKVQ0BcAAwAQAjAAcKVQ0BcAAwAQAAAA==.Nesmoth:BAABNQAECn8YAAIQAAYKcQ8IWgCzAAAQAAYKcQ8IWgCzAAAAAA==.Ness:BAABNQAECn8oAAMXAAgKlg0jGgApAQAXAAgKlg0jGgApAQAnAAUKkQ9lFQCmAAAAAA==.Nessecity:BAAANQADCgYIEAAAAA==.',
Ni='Nicolassaban:BAAANQADCgEIAQAAAA==.Nicolina:BAAANQAECgUIBAAAAA==.Niiborracho:BAABNQAECn8vAAMNAAgKJw59LwCbAQANAAgKJw59LwCbAQAXAAcKIw7xLQD8AAAAAA==.Niiko:BAABNQAECn8fAAIjAAUKwxqUiQByAQAjAAUKwxqUiQByAQAAAA==.Nirviana:BAAANQADCgYIBgAAAA==.',
No='No:BAAANQADCgUJBQABNQAECgoKMQADAOghAA==.Nobullsheep:BAAANQABCggIBwAAAA==.Nommy:BAAANQAECggIEgABNQAECggIMgAFADUbAA==.Norntrox:BAABNQAECn8WAAIZAAYKURCvPQBbAQAZAAYKURCvPQBbAQAAAA==.Nothannah:BAABNQAECn8kAAIUAAoK2A+VJQD3AQAUAAoK2A+VJQD3AQAAAA==.',
Ns='Nsshaman:BAAANQADCgUIBQAAAA==.',
Nu='Nuigi:BAAANQABCgMIAwAAAA==.',
['Nú']='Nút:BAAANQADCgIIAgABNQAECggIGgABACcNAA==.',
Od='Odyssey:BAAANQADCggJCAABNQAECgoKOAAYADYZAA==.',
Og='Ogreatsxtra:BAAANQAECgUIDQAAAA==.',
Ol='Ol:BAAANQAECggICwAAAA==.',
On='Onethiccyboi:BAAANQADCgEIAQAAAA==.Onix:BAAANQAECgcICwABNQAECgkJHgAUAN8dAA==.',
Or='Orangecrush:BAAANQAECgUIBAAAAA==.Orctism:BAAANQAECgMIAwAAAA==.',
Ow='Owlsonatotem:BAAANQAECgcIEAAAAA==.',
Oz='Ozhawk:BAAANQAECgUIBwAAAA==.',
Pa='Pakno:BAAANQAECgYIBwAAAA==.Pamely:BAABNQAECn9RAAIRAAoKoyCyGgBZAwARAAoKoyCyGgBZAwAAAA==.',
Pe='Perices:BAAANQADCgYIBgAAAA==.',
Ph='Pharmit:BAABNQAECn80AAMVAAoK0yUTAQAKAwAVAAoK0yUTAQAKAwAPAAEKXSFhMAFbAAAAAA==.Phiarce:BAABNQAECn84AAIMAAoK+RuUCgCNAgAMAAoK+RuUCgCNAgAAAA==.',
Pl='Pletua:BAAANQAECgYICAAAAA==.',
Po='Porterhouse:BAAANQADCgUIBwAAAA==.Potatoad:BAAANQAECgIIBAAAAA==.',
Pu='Purrfect:BAAANQAECgcIDgAAAA==.',
Pw='Pwags:BAAANQADCgUJBQAAAA==.',
Py='Pyragosa:BAABNQAECn8vAAIHAAoKuRaaPwAqAgAHAAoKuRaaPwAqAgAAAA==.Pyramys:BAAANQABCgQIAwABNQAECggIIAApAJodAA==.',
['Pâ']='Pândâmoníum:BAAANQAECgUICgAAAA==.',
['På']='Påimon:BAAANQADCggJEAAAAA==.',
Qu='Quintin:BAEANQADCgIJAgABNQAECgoKQQAQAKUmAA==.',
Ra='Rabmaxx:BAABNQAECn8mAAIYAAkK6gTuVwAqAQAYAAkK6gTuVwAqAQAAAA==.Racavis:BAAANQADCgMIAwAAAA==.Ralsei:BAAANQAECggIDwAAAA==.Ramasey:BAAANQAECgQIBQAAAA==.',
Re='Reach:BAAANQADCgcICwABNQAECggIGgABACcNAA==.Readdyy:BAAANQAECgcIBwAAAA==.Real:BAABNQAECn8fAAIHAAgKvhvJfQCDAgAHAAgKvhvJfQCDAgABNQABCgIIAgAGAAAAAA==.Realia:BAAANQAECgcICAAAAA==.Reda:BAABNQAECn8UAAQFAAgKexJ2jwBPAQAmAAYKkg64CQCQAQAFAAcKpRN2jwBPAQAaAAMKdgTiQwBpAAAAAA==.Redangus:BAAANQADCgIIAgABNQAECgYIEAAGAAAAAA==.Redkidd:BAAANQADCgUIBQAAAA==.Reikio:BAAANQAECgUIBQAAAA==.Reptar:BAAANQADCgcIBwABNQAFFAYIGQAEABQcAA==.Revoke:BAABNQAECn8rAAIRAAgKrAsctQAnAQARAAgKrAsctQAnAQAAAA==.',
Ro='Rocknrolln:BAAANQADCgcIEgAAAA==.Rokubora:BAABNQAECn89AAMLAAoKAhPBKwD4AQALAAoKAhPBKwD4AQAjAAgKAQzieAAVAQAAAA==.Rongyi:BAAANQAECgEIAQABNQAECgoKMAAEAMYUAA==.Roronoa:BAAANQADCgYICwAAAA==.Roßyn:BAABNQAECn8tAAMMAAoKKROHJwDvAQAMAAkK2hOHJwDvAQAIAAYK4BBngwAUAQAAAA==.',
Ru='Rubah:BAABNQAECn8hAAIOAAgK5xr3KABXAgAOAAgK5xr3KABXAgAAAA==.Rundail:BAAANQADCgQIBAAAAA==.Ruroni:BAABNQAECn8YAAIFAAgK1A1iyQBvAQAFAAgK1A1iyQBvAQAAAA==.',
Ry='Ryniel:BAAANQAECgUIBwAAAA==.',
['Ré']='Rédundant:BAABNQAECn8WAAIKAAgKEg1GRQBDAQAKAAgKEg1GRQBDAQABNQAECggIGgABACcNAA==.',
['Rì']='Rìzz:BAABNQAECn8lAAILAAgKnR0iNQCjAgALAAgKnR0iNQCjAgAAAA==.',
Sa='Sabrinalee:BAAANQADCgEIAQAAAA==.Saintdeamon:BAAANQADCgYIDAAAAA==.Sak:BAAANQADCgUIBQAAAA==.Salk:BAAANQADCgYIBgAAAA==.Sanasta:BAAANQAECgIIAwABNQAECgcIGgAMAFoPAA==.Sannaggi:BAAANQAECgYIDgAAAA==.Saorymu:BAAANQADCgIIAgAAAA==.Sarahnox:BAABNQAECn8vAAQUAAkKyB2WFQApAgAUAAkKyB2WFQApAgAiAAUKQwVgQgCEAAAEAAIKRQsXggAqAAAAAA==.Saramoon:BAABNQAECn8fAAIpAAoKEQhxKwBnAQApAAoKEQhxKwBnAQAAAA==.Sarayana:BAAANQABCgMIBAAAAA==.Sargent:BAAANQADCggIGAAAAA==.Saryaa:BAAANQAECgcICwAAAA==.Sashchi:BAABNQAECn8nAAINAAcKFRJ6MwB6AQANAAcKFRJ6MwB6AQAAAA==.Sassenach:BAABNQAECn8XAAILAAYKlBO2dQDwAAALAAYKlBO2dQDwAAAAAA==.Saudelber:BAAANQAECgUICAAAAA==.',
Sc='Schanks:BAABNQAECn8WAAIbAAgKkhxNFwDCAgAbAAgKkhxNFwDCAgAAAA==.Scoliosisstu:BAAANQADCggICAAAAA==.Scrotius:BAAANQABCgQIBQAAAA==.',
Se='Sedaelina:BAAANQAECgIIAgABNQAECgoKJAAUANgPAA==.Sehmet:BAABNQAECn8ZAAIpAAYKnBOYLQBVAQApAAYKnBOYLQBVAQAAAA==.Sekaï:BAAANQADCgEIAQAAAA==.Seliria:BAABNQAECn8xAAIRAAoKVhPeYQDTAQARAAoKVhPeYQDTAQAAAA==.Seoulmate:BAABNQAECn8wAAIEAAoKxhS/NgA2AgAEAAoKxhS/NgA2AgAAAA==.Sera:BAABNQAECn8YAAIRAAgKkhRligARAgARAAgKkhRligARAgAAAA==.Severûs:BAAANQAECgEIAQAAAA==.',
Sh='Shadoezz:BAAANQADCgQIBAAAAA==.Shadowhaunt:BAAANQADCgIIAgABNQAECgMIBAAGAAAAAA==.Shadowk:BAAANQABCgIIAgAAAA==.Shamsicle:BAAANQADCgMIAwAAAA==.Shaye:BAABNQAECn8VAAMVAAYKrQNFHABhAAAPAAYKmQNj3wBnAAAVAAUKLQJFHABhAAAAAA==.Shelari:BAAANQADCgEIAQAAAA==.Sherai:BAAANQADCgIIAgAAAA==.Shieldbro:BAAANQADCgEIAQABNQAECggIFAAkAI8aAA==.Shimone:BAAANQADCgEIAQAAAA==.Shinybeef:BAAANQADCgcIFgAAAA==.Shiryo:BAAANQAECgQIBAAAAA==.Shotfoot:BAABNQAECn89AAIFAAoKFRpcKQBuAgAFAAoKFRpcKQBuAgAAAA==.Shwang:BAABNQAECn8YAAIFAAgKjhvqnQAyAQAFAAgKjhvqnQAyAQAAAA==.',
Si='Sihåya:BAABNQAECn8ZAAIIAAoKqAaqjABwAQAIAAoKqAaqjABwAQAAAA==.Silbergrad:BAAANQAECgEIAQAAAA==.Silentio:BAABNQAECn9BAAIbAAoKDRS+CgABAgAbAAoKDRS+CgABAgAAAA==.Silihunt:BAABNQAECn83AAQZAAkK5xU+KAACAgAZAAgKihY+KAACAgAYAAgKrxKpOgDgAQAeAAIKDgg9KwAsAAAAAA==.Sinofwrath:BAAANQAECggIDQAAAA==.Sinsidious:BAABNQAECn8WAAIJAAkK+gqwKwBWAQAJAAkK+gqwKwBWAQAAAA==.Siwin:BAECNQAFFH8NAAIUAAcKFx/AAgAwAgAUAAcKFx/AAgAwAgA1AAQKfygAAxQACgqeJU0DAJQDABQACgqeJU0DAJQDAAQAAgoAAJabAGwAAAAA.',
Sk='Skribb:BAABNQAECn8vAAIOAAkKqyF8GADGAgAOAAkKqyF8GADGAgAAAA==.',
Sl='Slapchóp:BAABNQAECn8nAAILAAkKZR6sJQAdAgALAAkKZR6sJQAdAgAAAA==.',
Sm='Smiley:BAACNQAFFH8WAAIIAAcK3hXbCADeAQAIAAcK3hXbCADeAQA1AAQKfy0AAwgACgrsGxdDAF8CAAgACgrsGxdDAF8CAAwAAgrOFWI7AJEAAAE1AAUUBwoWAAgA3hUA.Smoketron:BAAANQAECgcICwAAAA==.Smoko:BAAANQAECgcIDwAAAA==.Smooshie:BAAANQADCgQIBAAAAA==.',
Sn='Sneakyboi:BAABNQAECn8UAAQkAAgKjxrXDACDAQAkAAYKBhnXDACDAQAbAAUKXBkDUQB5AQApAAEKbR1SqgBYAAAAAA==.Snorlax:BAABNQAECn8eAAQUAAkK3x0dFwCIAgAUAAkK3x0dFwCIAgAiAAMKFRa0SACLAAAEAAIKYBUuogBYAAAAAA==.Snowsu:BAACNQAFFH8cAAQPAAgK+SA+AwBRAgAPAAYKwyI+AwBRAgABAAIKJiEkBgC/AAAVAAEKiRb4CgBWAAA1AAQKfz8ABA8ACgrjJmIBAOgDAA8ACgrjJmIBAOgDAAEABwrpHdsKAEkCABUAAQqHJpUaAGwAAAAA.Snowxstorm:BAABNQAECn8sAAIQAAoKPBv/FAA/AgAQAAoKPBv/FAA/AgAAAA==.',
So='Soaringeagle:BAAANQABCgYICgAAAA==.Solidvodka:BAABNQAECn8VAAIFAAcKXxaIrgCnAQAFAAcKXxaIrgCnAQAAAA==.Solusrush:BAAANQABCgEIAQAAAA==.Souldecay:BAABNQAECn8uAAIJAAoKqw/9GwDTAQAJAAoKqw/9GwDTAQAAAA==.',
Sp='Splashzone:BAABNQAECn8dAAIjAAcKiAoenwA5AQAjAAcKiAoenwA5AQAAAA==.',
St='Staqua:BAABNQAECn8XAAIQAAYKphCKTQDdAAAQAAYKphCKTQDdAAAAAA==.Stateomatter:BAABNQAECn8gAAIFAAgKIgx9lwDZAQAFAAgKIgx9lwDZAQAAAA==.',
Su='Suanni:BAAANQADCgQIBAABNQAECgoKMAAEAMYUAA==.Summdari:BAABNQAECn8jAAIeAAgKzRXyCwAMAgAeAAgKzRXyCwAMAgAAAA==.Summrot:BAABNQAECn8iAAMPAAkKig5FhQAdAQAPAAcKDg5FhQAdAQABAAMKjQ26RgCsAAAAAA==.Sunfrostt:BAAANQAECgUIDwAAAA==.',
Sy='Syanana:BAAANQADCgYICQAAAA==.Sylvalesta:BAABNQAECn8XAAIFAAYKQQe1ygDYAAAFAAYKQQe1ygDYAAAAAA==.',
Ta='Tacgnol:BAAANQADCgYIBgAAAA==.Talyon:BAABNQAECn8YAAIZAAkKgBezJwAGAgAZAAkKgBezJwAGAgAAAA==.Tanayla:BAAANQADCgYIBgAAAA==.Tatertotem:BAACNQAFFH8JAAIjAAMKrBsVEgD6AAAjAAMKrBsVEgD6AAA1AAQKfycAAyMACgrnGqEvADECACMACgrnGqEvADECACEAAwpICjAwAG0AAAAA.',
Td='Tdogx:BAAANQAECgQIBAAAAA==.',
Te='Teal:BAAANQAECgIIBgAAAA==.Tekeeladin:BAAANQAECgQIBAABNQAFFAUIDQAFAH8eAA==.Tekeelà:BAABNQAECn8zAAIFAAoKNCCrFwDGAgAFAAoKNCCrFwDGAgABNQAFFAUIDQAFAH8eAA==.Tekelemental:BAABNQAECn8bAAILAAcKfQ5vlABxAQALAAcKfQ5vlABxAQAAAA==.Tempestra:BAAANQAECgYIDAAAAA==.Tenebria:BAABNQAECn88AAImAAoKnB6VAQBNAwAmAAoKnB6VAQBNAwAAAA==.Terrorhungry:BAABNQAECn8gAAIDAAkKmwhaiwA1AQADAAkKmwhaiwA1AQAAAA==.',
Th='Thalstrasza:BAABNQAECn8hAAIPAAgKQQyrowCOAQAPAAgKQQyrowCOAQAAAA==.The:BAABNQAECn8VAAIKAAUK4g4hawDyAAAKAAUK4g4hawDyAAAAAA==.Thedevilsown:BAAANQADCgYICgAAAA==.Thedrizzle:BAABNQAECn8jAAMHAAkKlBXO3QDMAQAHAAgK+RPO3QDMAQAfAAIKzxu9LwCCAAAAAA==.Theodiseus:BAAANQADCgUIBQAAAA==.Thugrodent:BAAANQAECggJAQAAAA==.Thundrfury:BAAANQADCgQIBQAAAA==.Thysane:BAAANQADCgEIAQAAAA==.',
Ti='Tibalt:BAAANQAECggIAwAAAA==.Tietus:BAAANQAECgUICAAAAA==.',
Tl='Tlanimass:BAABNQAECn8aAAIdAAYKABOOHwBUAQAdAAYKABOOHwBUAQAAAA==.',
To='Tolac:BAAANQADCgEIAQAAAA==.',
Tr='Treeko:BAAANQADCggICAABNQAFFAcICwAPAIQRAA==.Treyna:BAAANQADCgMIAwAAAA==.',
Ts='Tsu:BAABNQAECn8VAAMNAAYKAxFUPgAjAQANAAUKAxFUPgAjAQAnAAIK2ANpJQAmAAAAAA==.Tsyubaki:BAAANQAECgQICwAAAA==.',
Tu='Tulisse:BAAANQAECgEIAQAAAA==.',
Tw='Twerkngherkn:BAABNQAECn8YAAIHAAkKcQ8FoAA4AQAHAAkKcQ8FoAA4AQAAAA==.',
Ty='Tybalt:BAABNQAECn82AAIhAAoKtiK8AgB7AwAhAAoKtiK8AgB7AwAAAA==.Tynkxstrazza:BAAANQADCgEIAQAAAA==.Tyrandaz:BAAANQAECggIEQAAAA==.',
Ul='Uldric:BAABNQAECn8gAAIKAAkKxAh7PwBeAQAKAAkKxAh7PwBeAQAAAA==.',
Un='Undeaddude:BAABNQAECn8cAAIVAAoKJw71BQDaAQAVAAoKJw71BQDaAQAAAA==.Unslayable:BAAANQAECgQICgAAAA==.',
Uz='Uzzy:BAAANQAECgUIDgAAAA==.',
Va='Valandir:BAABNQAECn8aAAMRAAgK1AyQxgCPAQARAAgK1AyQxgCPAQASAAMKOgU3XABqAAAAAA==.Valyst:BAAANQAECgYICwAAAA==.Varya:BAAANQABCgQIBQAAAA==.',
Ve='Veliry:BAAANQADCgYIDwAAAA==.Verbera:BAACNQAFFH8YAAIUAAcKChsjAwDyAQAUAAcKChsjAwDyAQA1AAQKfy8AAxQACgpuIR8GAFQDABQACgpuIR8GAFQDAAQABgpsBaF7AN0AAAAA.Verrenth:BAAANQAECggIBgABNQAECggIFAAkAI8aAA==.',
Vi='Viduus:BAAANQAECgUIDAAAAA==.Vigol:BAAANQADCgQJBAAAAA==.Viri:BAAANQABCgIIAgAAAA==.Vivec:BAAANQADCgMIAwAAAA==.',
Vm='Vmaoh:BAAANQADCggIEAAAAA==.',
Vo='Voidrodent:BAAANQAECggIBgAAAA==.Voidwithin:BAAANQAECgQIBgAAAA==.Voljinforeva:BAAANQADCgQJBgAAAA==.Voltage:BAAANQAECgEIAQAAAA==.',
Vu='Vulfox:BAAANQAECgMIBQABNQAECgkJIAAIAGYaAA==.',
Wa='Wakenbake:BAAANQADCgUIBQAAAA==.Wandiferous:BAAANQAECgYIEwAAAA==.Warwickk:BAAANQABCgIIAgABNQAECgMIBAAGAAAAAA==.',
Wf='Wfreemen:BAAANQADCgQIBAAAAA==.',
Wh='Who:BAAANQAECgcICwABNQAFFAYIFQAIAMUIAA==.',
Wi='Wickedholi:BAAANQAECgcIBwABNQAFFAcICwAPAIQRAA==.Wickedsmaht:BAACNQAFFH8LAAMPAAcKhBEvGAAzAQAPAAUKUREvGAAzAQABAAIK0BGNDgCZAAA1AAQKf0YABA8ACgqOIusdAA0DAA8ACQpoIOsdAA0DABUABApLICMKAFwBAAEABArCIZsIABQBAAAA.Widowghast:BAABNQAECn8oAAIHAAgK8hR4vAALAgAHAAgK8hR4vAALAgAAAA==.Wildforge:BAAANQABCgQIBgAAAA==.Willowísp:BAABNQAECn80AAInAAoKHR3HBgDZAgAnAAoKHR3HBgDZAgAAAA==.Witerally:BAAANQAECgYIDgAAAA==.Wiz:BAAANQABCgEIAQABNQAECgkJHgAUAN8dAA==.',
Wo='Woggers:BAAANQADCgYICwAAAA==.',
Wu='Wujo:BAEBNQAECn8cAAMFAAkKrA/zsQCgAQAFAAkKrA/zsQCgAQAaAAEKbAZ3kgAuAAAAAA==.',
Wy='Wynters:BAAANQAECgQIBAAAAA==.',
Xa='Xalthea:BAABNQAECn9EAAQZAAoKTxSOFQDeAQAZAAoKTxSOFQDeAQAeAAEKwQj9NgAhAAAYAAcKGgCuowAUAAAAAA==.Xandapriest:BAAANQADCggIEwABNQAFFAUIDgAbACQSAA==.Xanlock:BAAANQADCgUIBwABNQAECgkJJAAiAP8WAA==.',
Xi='Xingyue:BAAANQADCgIIAgABNQAECgoKMAAEAMYUAA==.',
Xp='Xpddevour:BAABNQAECn9FAAIYAAoKfBqREgBjAgAYAAoKfBqREgBjAgAAAA==.',
Xq='Xquoria:BAAANQAECgUIAwAAAA==.',
Xt='Xtena:BAAANQADCgIIAgAAAA==.Xtendron:BAACNQAFFH8IAAIRAAQKuwn+FAC+AAARAAQKuwn+FAC+AAA1AAQKf0QAAhEACgrxIBQVAPkCABEACgrxIBQVAPkCAAAA.',
Xu='Xui:BAAANQADCgYIBgAAAA==.Xuxo:BAAANQADCgYIBwAAAA==.',
Ya='Yashoda:BAAANQABCggJCAAAAA==.',
Ye='Yegarmiester:BAAANQAECgcIDAAAAA==.Yenti:BAABNQAECn8XAAIRAAUKPwLSVQGXAAARAAUKPwLSVQGXAAAAAA==.',
Yu='Yuexi:BAAANQAECgIIAgABNQAECgoKMAAEAMYUAA==.',
['Yâ']='Yâni:BAAANQADCgIIAgAAAA==.',
Za='Zaco:BAABNQAECn8fAAIlAAUKghfYEwD5AAAlAAUKghfYEwD5AAAAAA==.Zamochy:BAAANQAECgYIBQAAAA==.Zap:BAAANQAECgYIBgABNQAECgkJHgAUAN8dAA==.Zatapa:BAAANQAECgUICgAAAA==.',
Ze='Zendàya:BAAANQADCgEIAQAAAA==.Zerality:BAAANQAECgYIDgAAAA==.',
Zh='Zhiso:BAAANQABCgYIBwAAAA==.',
Zi='Ziggie:BAABNQAECn83AAIZAAoKgiQCBwBiAwAZAAoKgiQCBwBiAwAAAA==.Zinovia:BAAANQAECgQIBAAAAA==.',
Zo='Zoltan:BAAANQADCggIIgAAAA==.Zookee:BAABNQAECn8uAAIXAAoKBwxYEQC0AQAXAAoKBwxYEQC0AQAAAA==.',
Zu='Zulizek:BAABNQAECn81AAIjAAkKCwxsVACPAQAjAAkKCwxsVACPAQAAAA==.',
Zy='Zynister:BAABNQAECn85AAMKAAoKFyA3DQDNAgAKAAoKFyA3DQDNAgAQAAUKzRFOgQD2AAAAAA==.',
['Ûr']='Ûrta:BAAANQADCgIIAQAAAA==.',
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
