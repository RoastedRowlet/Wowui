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

local lookup = {'Warlock-Destruction','Druid-Feral','Warrior-Arms','Priest-Shadow','Hunter-BeastMastery','Unknown-Unknown','Mage-Arcane','Priest-Holy','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Subtlety','Monk-Windwalker','Paladin-Holy','Warlock-Demonology','DeathKnight-Blood','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Druid-Balance','Druid-Restoration','Warlock-Affliction','Evoker-Devastation','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer','Warrior-Protection','Hunter-Marksmanship','Rogue-Assassination','Evoker-Augmentation','DemonHunter-Vengeance','Mage-Frost','Mage-Fire','Druid-Guardian','Shaman-Restoration','Shaman-Elemental','Warrior-Fury','Hunter-Survival','Monk-Brewmaster','Priest-Discipline','Shaman-Enhancement',}
local provider = {region='US',realm='Ysera',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aahnna:BAAANQAECgQIBAABNQAECggIFQABAPcEAA==.',
Ab='Ababear:BAAANQAECggIDAABNQAFFAUIBwACADEYAA==.',
Ad='Adeki:BAAANQADCgYIBgAAAA==.Ademai:BAAANQABCgYICgAAAA==.',
Ag='Agakk:BAAANQADCggICAAAAA==.Agentbundles:BAAANQADCgUIBwAAAA==.',
Ah='Ahnna:BAAANQAECgEIAQABNQAECggIFQABAPcEAA==.',
Al='Alarrius:BAABNQAECn89AAIDAAoKBxQuPgDXAQADAAoKBxQuPgDXAQAAAA==.Albedö:BAAANQADCgIIAgABNQAFFAMIBwAEAOEQAA==.Algo:BAAANQAECgIIAwABNQAFFAMIBQAFAKodAA==.Algrubeley:BAAANQABCgUIBQABNQAECgQIEAAGAAAAAA==.Alithirae:BAAANQADCgYICgAAAA==.Allionys:BAABNQAECn8aAAIHAAgKJR+3OgAIAgAHAAgKJR+3OgAIAgAAAA==.Aloris:BAABNQAECn8ZAAIIAAcK9B9nRgCXAQAIAAcK9B9nRgCXAQAAAA==.',
Am='Amanises:BAABNQAECn8yAAMJAAcKhyG8KACWAgAJAAcKhyG8KACWAgAKAAIKJgsUmABkAAABNQAECgkJIgALACcVAA==.Amilara:BAAANQAECgQICAAAAA==.',
An='Anakota:BAAANQABCgEIAQAAAA==.Ananaya:BAAANQAECgQIEAABNQAECgUIDwAGAAAAAA==.Anania:BAAANQAECgUIDwAAAA==.Andinestiri:BAABNQAECn8eAAIFAAgK1QzbagBjAQAFAAgK1QzbagBjAQAAAA==.Andolastrasz:BAAANQAECgQICAAAAA==.Angelic:BAAANQAECgYIDQAAAA==.Anightsong:BAAANQADCgQIBAAAAA==.',
Ao='Ao:BAABNQAECn8yAAIMAAoKDR6GDwDsAgAMAAoKDR6GDwDsAgAAAA==.',
Ap='Apotic:BAABNQAECn8mAAIKAAkKKwTAbADrAAAKAAkKKwTAbADrAAAAAA==.Apuntar:BAAANQADCggIDgAAAA==.',
Aq='Aquamaree:BAAANQAECgEIAQAAAA==.Aquilla:BAACNQAFFH8MAAIFAAcK5wf3CAC6AQAFAAcK5wf3CAC6AQA1AAQKfycAAgUACgqUHx4/AK0CAAUACgqUHx4/AK0CAAAA.',
Ar='Archenea:BAAANQAECgUIBgAAAA==.Archenore:BAAANQADCggIEAAAAA==.Areeza:BAAANQABCgIIAgAAAA==.Argord:BAABNQAECn8iAAINAAcKSg/wYQAcAQANAAcKSg/wYQAcAQAAAA==.Arhianrod:BAAANQADCggICgAAAA==.Ariisa:BAAANQAECgQIBwAAAA==.Around:BAABNQAECn8ZAAMBAAgKJw0aFQByAAAOAAcKAAoKsgBsAQABAAMKYxEaFQByAAAAAA==.Artty:BAEANQAECgQIBAABNQAECgoKOgAPAI8mAA==.',
As='Askip:BAAANQADCgQICgAAAA==.Astrud:BAAANQAECgMIDQAAAA==.Asukka:BAABNQAECn8gAAMQAAoKKSDsIQCCAgAQAAoKKSDsIQCCAgARAAQKWBUiRQDdAAAAAA==.Asëya:BAAANQADCggIDwAAAA==.',
At='Atomique:BAACNQAFFH8iAAISAAYK8wzDBgBMAQASAAYK8wzDBgBMAQA1AAQKf0wAAhIACgpwIkMFAFgDABIACgpwIkMFAFgDAAAA.Attenborough:BAAANQADCgYIBgAAAA==.',
Au='Audiamer:BAAANQAECgEIAQABNQAECgoKKgATAOoHAA==.Augustine:BAAANQABCgIIAgAAAA==.',
Av='Avesa:BAAANQAECgEIAQAAAA==.Avoidant:BAAANQADCggIEgAAAA==.',
Ay='Ayyahuasca:BAAANQABCgIIAgABNQAECgYIFQAOABgGAA==.',
Az='Azazell:BAAANQAECgIIAgAAAA==.Azenea:BAABNQAECn8VAAIBAAgK9wRnIQBmAQABAAgK9wRnIQBmAQAAAA==.',
Ba='Baculum:BAABNQAECn8YAAMKAAcK9hE1XAA4AQAKAAcKfA81XAA4AQAPAAUKgBZBcAA0AQAAAA==.Badmoonrisin:BAAANQAECgMIAwAAAA==.Baieghzieghl:BAAANQADCgcIDgAAAA==.Ballzach:BAAANQAECgIIAgABNQAFFAcIHgAPAB0iAA==.Bandolero:BAAANQAECgUIBQAAAA==.Bazookabob:BAAANQAECggICAABNQAECgkJHgAUAN8dAA==.',
Be='Beangles:BAAANQADCggICAAAAA==.Beckyy:BAAANQADCgcIBwABNQAECgQIBQAGAAAAAA==.Beefstewed:BAAANQADCggIDwAAAA==.Bekkÿ:BAAANQADCgUICQABNQAECgQIBQAGAAAAAA==.Bellaboop:BAAANQADCgYIBgAAAA==.Bellapearl:BAABNQAECn8jAAIOAAoKIg0GfQDuAQAOAAoKIg0GfQDuAQAAAA==.',
Bi='Bigbutter:BAAANQAECgMICgAAAA==.Bittybow:BAAANQAECgQIBQAAAA==.Bittydrood:BAAANQAECgUIDQAAAA==.Bittylexis:BAABNQAECn8dAAIVAAgKIAoBCQAUAQAVAAgKIAoBCQAUAQAAAA==.',
Bl='Blackei:BAAANQADCgEIAQAAAA==.Blaiddgwyn:BAAANQADCgQIBQAAAA==.Blarcedeliu:BAAANQAECgMIBAABNQAECgYIFQAWAE4XAA==.Bleu:BAAANQAECggIDQABNQAECggIGAAXAGUQAA==.Blueaxle:BAAANQADCgEIAQAAAA==.Blur:BAABNQAECn80AAMYAAoKXRjLEABAAgAYAAoKAhjLEABAAgAZAAcKihM3MgCwAQAAAA==.Bluzzy:BAAANQADCgIIAgABNQAECgoKOwAHAOohAA==.Blèu:BAABNQAECn8YAAIXAAgKZRD6HAC2AQAXAAgKZRD6HAC2AQAAAA==.',
Bo='Boggrog:BAAANQAECgQIBwABNQAECgUIFgAaABwQAQ==.Bokan:BAAANQAECgUICwAAAA==.Boneappetit:BAAANQADCgYIBgABNQAECgoKKgATAJkTAA==.Borgasthe:BAAANQADCgEIAQAAAA==.Bovinehymn:BAEANQAECgQIBAABNQAECggIGwANAM0jAA==.Box:BAAANQAECgcICAAAAA==.',
Br='Braggs:BAAANQAECgQIBAAAAA==.Breathe:BAAANQAECgUIBQAAAA==.Brewballs:BAABNQAECn8fAAIXAAcKqgx8FwAFAQAXAAcKqgx8FwAFAQAAAA==.Brewjitzu:BAAANQADCgQIBAAAAA==.',
Bu='Bubbletea:BAAANQADCggIHgAAAA==.Bucket:BAABNQAECn8UAAIZAAcKchBVQgA9AQAZAAcKchBVQgA9AQAAAA==.Bunnicula:BAABNQAECn8kAAQVAAoKXhXNBgA6AgAVAAkKpRXNBgA6AgAOAAMKfAckGgGTAAABAAEKbBN3cAA/AAAAAA==.Bunter:BAAANQAECgEIAQAAAA==.',
['Bö']='Böömer:BAAANQAECgQIDgAAAA==.',
Ca='Caelphia:BAAANQAECgUIDgAAAA==.Caimage:BAABNQAECn8XAAIHAAgKZxIkzwDoAQAHAAgKZxIkzwDoAQAAAA==.Cainnaszun:BAAANQAECgUIBgAAAA==.Cainnaszunn:BAAANQADCggIGwABNQAECgUIBgAGAAAAAA==.Calistini:BAAANQADCgYICgAAAA==.Cameron:BAAANQADCgQIBAAAAA==.Catalight:BAAANQAECgUIBQAAAA==.Catara:BAAANQAECgQIBAAAAA==.Cattform:BAAANQADCggICAAAAA==.Cavall:BAAANQAECgEIAQAAAA==.Caythus:BAACNQAFFH8lAAQOAAgKgiA8BAA1AgAOAAYKrx08BAA1AgABAAIKJiaTAwDdAAAVAAIKkh15BABhAAA1AAQKfzIABAEACgotJsABAGMDAAEACQq4I8ABAGMDAA4ACAq0JgkQAFIDABUAAgrqIeoTAGQAAAAA.Caythuz:BAAANQAECgYICwABNQAFFAgIJQAOAIIgAA==.',
Ce='Celeana:BAAANQAECgEIAQAAAA==.Celencia:BAAANQADCgEIAQAAAA==.Ceryin:BAAANQADCgYICAAAAA==.',
Ch='Chadmcguffin:BAAANQADCgEIAQAAAA==.Chainheal:BAAANQABCgQIBAAAAA==.Chakabad:BAAANQAECgQIDQAAAA==.Chalgah:BAAANQAECgUICQAAAA==.Charnyanya:BAAANQADCggICAABNQAECgcIDQAGAAAAAA==.Cheetò:BAAANQAECgUIBQAAAA==.Chenahala:BAAANQAECgUIDgAAAA==.Chloe:BAAANQADCggICAAAAA==.Chåni:BAABNQAECn9GAAIZAAoKNh9IDAAdAwAZAAoKNh9IDAAdAwAAAA==.',
Ci='Cimerone:BAAANQABCgYICQAAAA==.',
Ck='Ckayz:BAAANQAECgIIAgAAAA==.',
Cl='Clam:BAABNQAECn8gAAMFAAcKfgpscQBTAQAFAAcKfgpscQBTAQAbAAUKegJuXQCwAAAAAA==.Claw:BAABNQAECn8YAAITAAoK0QzsKQA5AQATAAoK0QzsKQA5AQABNQAFFAYIDQAJAF4NAA==.Clisa:BAAANQABCgEIAQAAAA==.',
Co='Co:BAAANQAECgcIEQAAAA==.Coldstonez:BAAANQADCggIEgAAAA==.Conanascus:BAAANQAECgIIAgABNQAECgoKOwAcAL4RAA==.Confessorr:BAAANQADCgYIBQABNQAECgYIFQAOABgGAA==.Corrupteded:BAAANQAECgEIAQAAAA==.',
Cr='Crimsonmana:BAAANQADCgMIAwAAAA==.Crispysock:BAABNQAECn8WAAITAAYKqQv5XQBZAQATAAYKqQv5XQBZAQAAAA==.Crowe:BAAANQAECgQIBgAAAA==.',
Cy='Cynderr:BAABNQAECn8bAAIWAAgKABKEGADAAQAWAAgKABKEGADAAQAAAA==.',
Da='Daisymayhem:BAAANQABCgcICAAAAA==.Dangmart:BAAANQADCgMIAwAAAA==.Daquilla:BAAANQADCgUICgAAAA==.Darkfury:BAAANQAECgUICQAAAA==.Darkisis:BAAANQAECgUIEwAAAA==.Darknara:BAABNQAECn8rAAMPAAoKuBzGIACuAgAPAAkKBR3GIACuAgAJAAYKcBW8KgAqAQAAAA==.Darkterror:BAAANQAECgQIBAABNQAECgUIEwAGAAAAAA==.Darkzy:BAAANQAECgEIAwAAAA==.Dartol:BAAANQAECgMICAAAAA==.Dasubertakem:BAAANQAECgQIBAAAAA==.Dawni:BAABNQAECn8qAAQSAAoKRhP5DACyAQASAAgKFhL5DACyAQAWAAQK+REMEgCxAAAdAAEKiAQWJgAsAAAAAA==.',
Dd='Ddz:BAAANQADCgUIBQAAAA==.',
De='Deathjeff:BAACNQAFFH8FAAIKAAIKexgoDQCZAAAKAAIKexgoDQCZAAA1AAQKfx0AAgoACgqqI2YHAG4DAAoACgqqI2YHAG4DAAAA.Deathsgates:BAAANQAECgUIDgABNQAFFAUIDgAcACQSAA==.Detala:BAAANQAECgEIAQAAAA==.',
Di='Didymus:BAAANQADCgUIBQAAAA==.Diereth:BAAANQABCgIIAgAAAA==.Dimos:BAAANQAECgUIDQAAAA==.Dinoll:BAAANQAECggIEQAAAA==.Dionizius:BAAANQADCgIIAgAAAA==.Dirtwhistle:BAABNQAECn8qAAIaAAkKZSQnAgCaAwAaAAkKZSQnAgCaAwAAAA==.',
Dr='Dracont:BAAANQADCgUIBQABNQAECgUIBgAGAAAAAA==.Dragondh:BAACNQAFFH8KAAIYAAUK1QfFCgC5AAAYAAUK1QfFCgC5AAA1AAQKfysAAhgACgrIGzElAHMCABgACgrIGzElAHMCAAAA.Dranlu:BAAANQAECgEIAQAAAA==.Drazsi:BAAANQAECgUICwAAAA==.Drekkara:BAAANQADCgQIBAABNQAECgMIDQAGAAAAAA==.Drosi:BAABNQAECn8sAAIQAAkK3xGzYACZAQAQAAkK3xGzYACZAQAAAA==.Drovaal:BAAANQADCgUIBQAAAA==.',
Dy='Dyromancer:BAAANQADCgIJAgAAAA==.',
['Då']='Dåmmn:BAAANQAECgEIAQAAAA==.',
Ea='Earthesance:BAAANQAECgIIAwAAAA==.',
Eb='Ebeb:BAAANQAECgcIEQAAAA==.',
Ed='Edgedweenie:BAAANQADCgQIBAAAAA==.',
Ei='Eiwe:BAAANQADCgYICQAAAA==.',
El='Eleanne:BAABNQAECn8lAAMTAAgKexKmTQCqAQATAAcKwhKmTQCqAQAUAAUK8BLoLAD8AAAAAA==.Electricfury:BAAANQAECgUIBQAAAA==.Elementalism:BAAANQADCgQIBAAAAA==.Ellebasi:BAAANQAECgQIBwAAAA==.Ellebazy:BAABNQAECn8dAAIRAAcK/hNOKgCLAQARAAcK/hNOKgCLAQAAAA==.',
Em='Emmri:BAAANQAECgYIDgAAAA==.',
En='Enazen:BAABNQAECn8VAAIWAAYKThf5GwCMAQAWAAYKThf5GwCMAQAAAA==.Enlighthyn:BAABNQAECn8bAAINAAoKwx4oIADuAgANAAoKwx4oIADuAgABNQAFFAUIDAAIAO4dAA==.',
Er='Erlas:BAAANQAECgMIAwAAAA==.Erui:BAAANQAECgUIDgAAAA==.',
Es='Esmeluz:BAAANQADCgMIAwAAAA==.',
Et='Etorion:BAAANQADCggIFQAAAA==.Etrexxig:BAAANQADCgcICwAAAA==.',
Ev='Evilrayne:BAABNQAECn9DAAIHAAoK3hamNgAYAgAHAAoK3hamNgAYAgAAAA==.',
Fa='Failpriest:BAAANQADCgEIAQABNQAECgYIDAAGAAAAAA==.Fanfiction:BAABNQAECn8cAAMSAAoK2xFbGwASAgASAAoK2xFbGwASAgAWAAEKAAD+QQAmAAAAAA==.Fatherfingur:BAAANQADCgMIBAAAAA==.',
Fe='Fearoshimâ:BAAANQAECgQIBAAAAA==.Featara:BAAANQADCgEIAQAAAA==.Feather:BAABNQAECn8WAAITAAkKAxUrPQANAgATAAkKAxUrPQANAgAAAA==.Felmonger:BAAANQAECgQICQAAAA==.Feloak:BAABNQAECn8hAAIeAAkKaQosDQAEAQAeAAkKaQosDQAEAQAAAA==.Feredir:BAAANQAECgQICAAAAA==.',
Fi='Fires:BAABNQAECn8oAAQHAAgKIh+XXADGAgAHAAgKwx6XXADGAgAfAAYKlh0pDgAnAQAgAAEKAABhDQA4AAAAAA==.Fistandilius:BAABNQAECn8eAAIOAAgKWQyEawAnAQAOAAgKWQyEawAnAQAAAA==.',
Fo='Folexper:BAAANQADCggIDwAAAA==.',
Fr='Frostman:BAABNQAECn8rAAMPAAkKLiKZEQAgAwAPAAkKLiKZEQAgAwAKAAEKAADRngBTAAAAAA==.',
Fu='Furryfury:BAABNQAECn9BAAMXAAoKWhowDgCgAgAXAAoKWhowDgCgAgAMAAgKyQocIwAMAQAAAA==.Fusrodah:BAABNQAECn8hAAMSAAgKxxccGQAuAgASAAgKxxccGQAuAgAWAAEKAACsOQBBAAAAAA==.Fuzzyewok:BAABNQAECn8sAAINAAkKwx6mEADMAgANAAkKwx6mEADMAgAAAA==.',
Ga='Gabaghoul:BAABNQAECn8xAAIPAAoKXxwjMABRAgAPAAoKXxwjMABRAgAAAA==.Gameshark:BAABNQAECn8kAAINAAcKaiX1EADJAgANAAcKaiX1EADJAgAAAA==.Gawdzirra:BAAANQAECgcIEAABNQAECggIFAAOALkPAA==.Gaylordgerva:BAAANQAECgEIAQAAAA==.Gaz:BAAANQAFFAEIAQAAAQ==.',
Ge='Geauxaway:BAAANQADCgQIAgAAAA==.George:BAAANQADCggIGQAAAA==.',
Gh='Ghazghküll:BAAANQAECgQIBAAAAA==.Ghulrokk:BAAANQAECgYIBwAAAA==.',
Gi='Gilidan:BAAANQABCgIIAgAAAA==.',
Gl='Gluum:BAAANQAECgQIBAAAAA==.',
Go='Gohibasi:BAAANQAECgQICAAAAA==.Goodfel:BAAANQABCgMIAwAAAA==.Goops:BAAANQADCgEIAQAAAA==.Gorzarpixx:BAAANQAECgEIAQAAAA==.Gossamerfeet:BAABNQAECn8aAAIIAAoKVxI4TwA3AgAIAAoKVxI4TwA3AgAAAA==.',
Gr='Graceosilver:BAAANQAECgUIEAAAAA==.Gregnor:BAABNQAECn8sAAUCAAkKkxMkCQCzAQACAAkKkxMkCQCzAQATAAYKVAYzbAAaAQAhAAQKTgjzRQCbAAAUAAQKmwOaZQBvAAAAAA==.Gremöry:BAABNQAECn8eAAMiAAgKTxNYiAB1AQAiAAgKTxNYiAB1AQAjAAYKwRHKmgBiAQAAAA==.Grimmler:BAAANQABCgEIAQAAAA==.Grippysock:BAAANQAECgIIAgAAAA==.Grover:BAABNQAECn8jAAIQAAkKWBR4ggAjAgAQAAkKWBR4ggAjAgAAAA==.Grumpybunbun:BAABNQAECn8lAAIIAAoKKRKxUwAoAgAIAAoKKRKxUwAoAgAAAA==.Grüm:BAAANQAECgQICAAAAA==.',
Gu='Guldangraham:BAAANQAECggIAgABNQAECggIDwAGAAAAAA==.Guppy:BAAANQADCgYIBgAAAA==.',
Gy='Gyorge:BAAANQADCgUIBQAAAA==.',
['Gå']='Gårrus:BAABNQAECn8sAAIFAAkKRRmZNwACAgAFAAkKRRmZNwACAgAAAA==.',
['Gô']='Gôrbag:BAAANQADCgUIBQAAAA==.',
Ha='Haarl:BAAANQADCgcIBwAAAA==.Hairypotter:BAAANQADCggIFQABNQAECgUIDgAGAAAAAA==.Halazzi:BAAANQAECgEIAgAAAA==.Haldar:BAABNQAECn8ZAAINAAoK1hIzKwD/AQANAAoK1hIzKwD/AQAAAA==.Hallie:BAABNQAECn8UAAIfAAUKqwmdIADkAAAfAAUKqwmdIADkAAAAAA==.Harlu:BAABNQAECn8aAAIjAAYKeQWLdgCzAAAjAAYKeQWLdgCzAAAAAA==.Hartbroke:BAABNQAECn8dAAIQAAYKTRuyoQDeAQAQAAYKTRuyoQDeAQAAAA==.Haunter:BAAANQAECgQIDAABNQAECgkJHgAUAN8dAA==.Hayeon:BAAANQAECgIIAgAAAA==.',
He='Helbourne:BAABNQAECn8eAAIYAAgKihQPMAAnAgAYAAgKihQPMAAnAgAAAA==.',
Hi='Hijjiup:BAAANQADCgQIBAAAAA==.',
Ho='Holybunbun:BAAANQAECggIDAAAAA==.Holyrollerz:BAAANQADCgYIBgAAAA==.Homeydagreat:BAAANQAECgEIAQAAAA==.',
Hu='Huna:BAAANQADCgYIBgABNQAECgUIHgAkAJEWAA==.Hunsx:BAAANQAECgYICQAAAA==.Huntingpups:BAAANQADCggICAAAAA==.',
Hw='Hwanwok:BAABNQAECn8oAAIMAAgKtBUZFgCMAQAMAAgKtBUZFgCMAQAAAA==.',
['Hâ']='Hânzö:BAAANQADCgMIAwAAAA==.',
Ia='Iamwarlock:BAAANQAECgQIBQAAAA==.',
Ic='Icemage:BAAANQAECgMIBgAAAA==.',
Id='Ideal:BAAANQADCgMIBAAAAA==.',
Ig='Ignited:BAAANQAECgQICwAAAA==.',
Il='Ilotei:BAAANQADCgcIBwAAAA==.',
Im='Imadragon:BAABNQAECn8mAAIWAAoKCgw6GADFAQAWAAoKCgw6GADFAQAAAA==.Imbac:BAAANQAECgEIBAAAAA==.Imdeadguy:BAABNQAECn8mAAIaAAkKISDzBgDxAgAaAAkKISDzBgDxAgAAAA==.',
In='Inarian:BAAANQADCgYIBgAAAA==.',
Ir='Irilara:BAAANQADCggIIwAAAA==.Ironhelmhtr:BAAANQAECgQIBQAAAA==.',
Is='Istian:BAAANQADCgQIBgAAAA==.',
Ja='Jaayk:BAABNQAECn8dAAIcAAoKwRlQBQBpAgAcAAoKwRlQBQBpAgAAAA==.Jace:BAAANQAECgIIAgAAAA==.Jazlee:BAABNQAECn8aAAIaAAYK0B0kDgBUAQAaAAYK0B0kDgBUAQAAAA==.',
Je='Jealous:BAAANQAECgEIAQABNQAECgYICwAGAAAAAA==.Jefflock:BAAANQADCgEIAQABNQAECgcIFQAFAF8WAA==.Jezmund:BAABNQAECn8ZAAIUAAUK+RhZNgBpAQAUAAUK+RhZNgBpAQAAAA==.',
Ji='Jinathy:BAABNQAECn8vAAIQAAoKfxDtZQCMAQAQAAoKfxDtZQCMAQAAAA==.Jinxed:BAAANQADCgYIBgAAAA==.',
Jo='Jolyñ:BAABNQAECn8ZAAIIAAgK4RDZcADKAQAIAAgK4RDZcADKAQABNQAECgoKJQAlABYMAA==.',
Ju='Juaranir:BAABNQAECn8kAAIhAAgKxRNqHAC/AQAhAAgKxRNqHAC/AQAAAA==.Judgementall:BAAANQADCgQIBAAAAA==.Juicébòx:BAAANQAECgIIAgAAAA==.Justac:BAAANQAECgQIBwABNQAECgUICAAGAAAAAA==.Justdrood:BAAANQAECgUICAAAAA==.',
Jw='Jwst:BAAANQAECgMIAwAAAA==.',
['Jà']='Jàß:BAABNQAECn8XAAITAAgKzRRPPAATAgATAAgKzRRPPAATAgAAAA==.',
['Já']='Jáß:BAABNQAECn8aAAINAAkKYx7NGgALAwANAAkKYx7NGgALAwAAAA==.',
['Jä']='Jäb:BAAANQAECgcIDgABNQAECgoKHQAjADQTAA==.',
Ka='Kagegari:BAAANQADCgUIBQABNQAFFAQICgAFAJsaAA==.Kahleah:BAAANQADCgcIBAAAAA==.Kaldonor:BAABNQAECn88AAIKAAoKNw9vIgC5AQAKAAoKNw9vIgC5AQAAAA==.Kalenia:BAABNQAECn9DAAIiAAoKvyFNBgBmAwAiAAoKvyFNBgBmAwAAAA==.Kalvayre:BAAANQAECgQICQAAAA==.Kanzoorb:BAABNQAECn8nAAMHAAoKTBymVADXAgAHAAoKTBymVADXAgAfAAEKIBeFKwA7AAAAAA==.Kareshka:BAABNQAFFH8HAAMfAAUKFQ20BADIAAAHAAMKAwcXOwDYAAAfAAMKVRG0BADIAAAAAA==.Karinea:BAEBNQAECn8XAAImAAcK8gUSEwCVAAAmAAcK8gUSEwCVAAAAAA==.Karpana:BAEBNQAECn8yAAMRAAgKgBawLwBhAQAQAAgKqRFm1gBvAQARAAUKbB2wLwBhAQAAAA==.Karreena:BAAANQADCgYIBgAAAA==.Karworg:BAAANQADCggIFQAAAA==.Kashir:BAAANQAECgUIEgAAAA==.Kashira:BAAANQADCggIEgABNQAECgUIEgAGAAAAAA==.Kathelee:BAAANQAECgcIDQAAAA==.Kaythewitch:BAAANQAECgcIBwAAAA==.Kazimirah:BAAANQAECgEIAQAAAA==.Kazrael:BAABNQAECn8UAAMeAAcKXRdFDAAUAQAeAAYKMRtFDAAUAQAZAAEKEAhyRgAyAAAAAA==.',
Ke='Keekat:BAAANQADCggIGAAAAA==.Kevinbeacon:BAEBNQAECn8bAAINAAgKzSPEJADXAgANAAgKzSPEJADXAgAAAA==.',
Kh='Kharnij:BAAANQAECgUIDQAAAA==.Khaíbit:BAAANQADCgYIBgAAAA==.Khonsu:BAABNQAECn8qAAQOAAkK8BWtXgBIAQAOAAgKOBatXgBIAQAVAAIK1RBeEACHAAABAAEKEBOecAA/AAAAAA==.Khryy:BAAANQADCgUIBQABNQADCgUIBQAGAAAAAA==.',
Ki='Kiamei:BAAANQAECgEIAQAAAA==.Kikora:BAAANQADCgcIDQAAAA==.Kissandia:BAAANQADCgcIBwAAAA==.Kittykitty:BAABNQAECn84AAMiAAoKkSA5EADRAgAiAAoKkSA5EADRAgAjAAUKghZ9qABDAQAAAA==.',
Ko='Kolzane:BAECNQAFFH8RAAIFAAcKuCOfAAC5AgAFAAcKuCOfAAC5AgA1AAQKfywAAgUACgpkJm8EAEcDAAUACgpkJm8EAEcDAAAA.',
Kr='Krezz:BAABNQAECn8eAAIaAAgKGhthCQCzAQAaAAgKGhthCQCzAQAAAA==.',
Ku='Kumojo:BAAANQADCggICAAAAA==.Kurna:BAAANQADCgEIAQAAAA==.Kuulas:BAACNQAFFH8MAAIFAAUKYQ+WDgBtAQAFAAUKYQ+WDgBtAQA1AAQKfyEAAgUACgqAG6QwANoCAAUACgqAG6QwANoCAAAA.',
Ky='Kynlyn:BAAANQADCgQICAAAAA==.Kyth:BAABNQAECn8vAAMRAAkKnxi1GAAxAgARAAgK5xu1GAAxAgAQAAIK7gQVrAExAAAAAA==.Kythlock:BAAANQADCgYIBQABNQAECgkJLwARAJ8YAA==.Kythrax:BAAANQADCgUIAwABNQAECgkJLwARAJ8YAA==.Kythtok:BAAANQADCgYICAABNQAECgkJLwARAJ8YAA==.',
La='Lanx:BAAANQAECgIIAgAAAA==.Laquatas:BAABNQAECn8hAAIPAAgK6B12FwDiAQAPAAgK6B12FwDiAQAAAA==.Laylanduin:BAAANQADCgEIAQABNQAFFAIIBQAKAHsYAA==.',
Le='Leadfarmer:BAAANQAECggIBAAAAA==.Lenash:BAAANQAECgIIAgABNQABCgIIBAAGAAAAAA==.',
Li='Lichlighter:BAAANQADCgEIAQAAAA==.Lifebloomer:BAAANQAECgEIAQABNQAFFAcIHgAPAB0iAA==.Lightguard:BAABNQAECn8sAAIQAAkKyRbaOwALAgAQAAkKyRbaOwALAgAAAA==.Likesitruff:BAAANQADCgcICQAAAA==.Lilolock:BAAANQAECgUIEgAAAA==.Littlehell:BAABNQAECn8aAAIiAAkKyBYeSABBAgAiAAkKyBYeSABBAgAAAA==.',
Lo='Lothrik:BAAANQAECgYIEQAAAA==.',
Lu='Lucaafer:BAAANQAECgQIBAABNQAECgoKHQAYAFkVAA==.Luda:BAABNQAECn8UAAIOAAgKuQ92mACqAQAOAAgKuQ92mACqAQAAAA==.Ludaa:BAAANQAECgUIDwABNQAECggIFAAOALkPAA==.Ludahealz:BAAANQADCgEIAQABNQAECggIFAAOALkPAA==.Lunamoonclaw:BAABNQAECn8UAAIbAAcKdAZ2QQBJAQAbAAcKdAZ2QQBJAQAAAA==.Lunaspire:BAAANQADCgIIAgAAAA==.',
Ly='Lyntrax:BAAANQAECgQIBgAAAA==.Lyssandria:BAAANQAECgYICgAAAA==.Lyzoldas:BAABNQAECn8kAAIQAAoKFxI2VgCzAQAQAAoKFxI2VgCzAQAAAA==.',
['Lá']='Lárry:BAAANQADCgUIBwAAAA==.',
['Lö']='Löwryder:BAABNQAECn8UAAIjAAUK9goszwD1AAAjAAUK9goszwD1AAAAAA==.',
Ma='Madness:BAAANQADCgYIBwABNQAECgkJJAAjAH8MAA==.Mae:BAABNQAECn8bAAQSAAgKxBpiCAA/AgASAAgKxBpiCAA/AgAWAAEKtx+aOABKAAAdAAEKEQFVKQAVAAABNQABCgIIAgAGAAAAAA==.Maemura:BAAANQAECgQICAAAAA==.Magdalaiina:BAABNQAECn8hAAINAAYKZiJDIwAwAgANAAYKZiJDIwAwAgAAAA==.Magicdaisee:BAAANQADCgYIBgAAAA==.Magusman:BAAANQAECggICAABNQAECgkJKwAPAC4iAA==.Magîkarp:BAABNQAECn8dAAMXAAkKpBcSDwCOAQAXAAkKpBcSDwCOAQAMAAMKnRDSXgBlAAAAAA==.Malchromatus:BAABNQAECn8nAAMSAAkKZAprJQCTAQASAAkKZAprJQCTAQAWAAcKWwaXIQBCAQAAAA==.Marcosio:BAAANQAECgMICgAAAA==.Marmaladia:BAAANQADCggIDQAAAA==.Marsala:BAABNQAECn8XAAITAAkKaQu9SgC7AQATAAkKaQu9SgC7AQAAAA==.Mavik:BAAANQAECggIAgAAAA==.Maylater:BAAANQAECgMIAwABNQAECgkJIgAMAAMTAA==.',
Me='Mearkman:BAABNQAECn8WAAIFAAUKaRjuzQBlAQAFAAUKaRjuzQBlAQAAAA==.Meatyfajita:BAABNQAECn8oAAINAAoKbiKADABkAwANAAoKbiKADABkAwAAAA==.Megumim:BAAANQADCgQIBAAAAA==.Meinfurion:BAABNQAECn8gAAMUAAgKmRMzLwChAQAUAAcKVBIzLwChAQATAAgKtBRZIACDAQAAAA==.Meinstrom:BAAANQADCggICAABNQAECggIIAAUAJkTAA==.Meladie:BAAANQAECgEIAQAAAA==.Melevolent:BAAANQABCgQIBAAAAA==.Memedecay:BAABNQAECn88AAQJAAoKph78HgDRAgAJAAgKJyL8HgDRAgAKAAoKmBiUEwA+AgAPAAEKAADluwBQAAAAAA==.Memeonhuntër:BAAANQADCgMIAwABNQAECgoKPAAJAKYeAA==.Merit:BAAANQADCggIEAABNQAECgoKNAAYAF0YAA==.Merlinthos:BAABNQAECn8iAAMfAAkKAwc9DwAVAQAHAAgKMAQuFgFnAQAfAAcKVQc9DwAVAQABNQAECgoKOwAcAL4RAA==.Messra:BAAANQADCgMIAwAAAA==.Metaljack:BAABNQAECn8sAAMfAAkKAx7IDADrAQAHAAkKRRuWiABtAgAfAAYKtCDIDADrAQAAAA==.',
Mi='Miasma:BAAANQADCgUIBQABNQAECgQIBAAGAAAAAA==.Midith:BAAANQADCgYIBgAAAA==.Minecraft:BAABNQAECn8oAAIkAAoK8RvLAwBQAgAkAAoK8RvLAwBQAgAAAA==.Mingyue:BAAANQAECgUIBQABNQAECgoKKgATAJkTAA==.Mirajåne:BAACNQAFFH8HAAIEAAMK4RAPDgDzAAAEAAMK4RAPDgDzAAA1AAQKfz8ABAQACgqbHBMPAAEDAAQACgqbHBMPAAEDAAgABgqSFIymACEBACcAAQq6Aq0tACkAAAAA.Mishaweha:BAABNQAECn8eAAIiAAgK6BOELwDmAQAiAAgK6BOELwDmAQAAAA==.Missdowtfire:BAAANQADCgIIAgAAAA==.Mitos:BAAANQAECgEIAQAAAA==.',
Mo='Modar:BAABNQAECn8lAAMiAAoKzRURRwBFAgAiAAoKzRURRwBFAgAjAAMKsgQQ5gDLAAAAAA==.Monkas:BAAANQAECgEIAQAAAA==.Moonhoof:BAAANQADCgIIAgAAAA==.Moonrid:BAAANQADCggIEwAAAA==.Mornanden:BAAANQAECgQIBQAAAA==.',
Mu='Musterd:BAAANQADCgYJDQAAAA==.',
['Må']='Måddløck:BAAANQADCgYIDAAAAA==.',
Na='Nahray:BAAANQADCgQIBAAAAA==.Namaera:BAAANQADCgcIBwAAAA==.Navatath:BAAANQAECgMIBgABNQAFFAcIJwAHAL8kAA==.',
Ne='Neiidra:BAAANQAECgUIBgAAAA==.Nepheleah:BAACNQAFFH8OAAIQAAUKgBmVCgDyAAAQAAUKgBmVCgDyAAA1AAQKfzEAAhAACgqiIqIPAIwDABAACgqiIqIPAIwDAAAA.Nesca:BAABNQAECn8gAAIiAAcKVQ0CWAA5AQAiAAcKVQ0CWAA5AQAAAA==.Nesmoth:BAABNQAECn8WAAIPAAUKSxJrfwD9AAAPAAUKSxJrfwD9AAAAAA==.Ness:BAABNQAECn8iAAMXAAcKHw6lFwADAQAXAAcKHw6lFwADAQAmAAUK4wy9EwCNAAAAAA==.Nessecity:BAAANQADCgYIEAAAAA==.',
Ni='Nicolassaban:BAAANQADCgEIAQAAAA==.Nicolina:BAAANQAECgEIAQAAAA==.Niiborracho:BAABNQAECn8oAAMMAAgKJw59LwCbAQAMAAgKJw59LwCbAQAXAAcKhw3xLQD8AAAAAA==.Niiko:BAABNQAECn8cAAIiAAUK3hmUiQByAQAiAAUK3hmUiQByAQAAAA==.',
No='No:BAAANQADCgUJBQABNQAECgoKMQADAOghAA==.Nobullsheep:BAAANQABCggIBwAAAA==.Nommy:BAAANQAECggIEgABNQAECggILgAFADUbAA==.Norntrox:BAABNQAECn8WAAIZAAYKURCvPQBbAQAZAAYKURCvPQBbAQAAAA==.Nothannah:BAABNQAECn8jAAIUAAkKXRCVJQD3AQAUAAkKXRCVJQD3AQAAAA==.',
Ns='Nsshaman:BAAANQADCgUIBQAAAA==.',
Nu='Nuigi:BAAANQABCgMIAwAAAA==.',
['Nú']='Nút:BAAANQADCgIIAgABNQAECggIGQABACcNAA==.',
Od='Odyssey:BAAANQADCggJCAABNQAECgoKNAAYAF0YAA==.',
Og='Ogreatsxtra:BAAANQAECgUIDQAAAA==.',
Ol='Ol:BAAANQAECgcICwAAAA==.',
On='Onethiccyboi:BAAANQADCgEIAQAAAA==.Onix:BAAANQAECgcICwABNQAECgkJHgAUAN8dAA==.',
Or='Orangecrush:BAAANQAECgUIBAAAAA==.Orctism:BAAANQAECgMIAwAAAA==.',
Ow='Owlsonatotem:BAAANQAECgcIEAAAAA==.',
Oz='Ozhawk:BAAANQAECgUIBwAAAA==.',
Pa='Pakno:BAAANQAECgUIBQAAAA==.Pamely:BAABNQAECn9LAAIQAAoKOCCyGgBZAwAQAAoKOCCyGgBZAwAAAA==.',
Pe='Perices:BAAANQADCgYIBgAAAA==.',
Ph='Pharmit:BAABNQAECn8vAAMVAAkK+SXQAADbAgAVAAkK+SXQAADbAgAOAAEKXSFhMAFbAAAAAA==.Phiarce:BAABNQAECn80AAIEAAoKvht7BwCUAgAEAAoKvht7BwCUAgAAAA==.',
Pl='Pletua:BAAANQAECgYICAAAAA==.',
Po='Porterhouse:BAAANQADCgUIBwAAAA==.Potatoad:BAAANQAECgIIBAAAAA==.',
Pu='Purrfect:BAAANQAECgcIBwAAAA==.',
Pw='Pwags:BAAANQADCgUJBQAAAA==.',
Py='Pyragosa:BAABNQAECn8mAAIHAAoKFxadNwAUAgAHAAoKFxadNwAUAgAAAA==.Pyramys:BAAANQABCgQIAwABNQAECggIIAALAJodAA==.',
['Pâ']='Pândâmoníum:BAAANQAECgQICQAAAA==.',
['På']='Påimon:BAAANQADCggJEAAAAA==.',
Qu='Quintin:BAEANQADCgIJAgABNQAECgoKOgAPAI8mAA==.',
Ra='Racavis:BAAANQADCgMIAwAAAA==.Ralsei:BAAANQAECggICQAAAA==.Ramasey:BAAANQAECgQIBQAAAA==.',
Re='Reach:BAAANQADCgcICwABNQAECggIGQABACcNAA==.Readdyy:BAAANQAECgcIBwAAAA==.Real:BAABNQAECn8fAAIHAAgKvhvJfQCDAgAHAAgKvhvJfQCDAgABNQABCgIIAgAGAAAAAA==.Realia:BAAANQAECgcICAAAAA==.Reda:BAAANQAECgUICwAAAA==.Redangus:BAAANQADCgIIAgABNQAECgYICwAGAAAAAA==.Reikio:BAAANQAECgUIBQAAAA==.Reptar:BAAANQADCgcIBwABNQAFFAYIGQATABQcAA==.Revoke:BAABNQAECn8kAAIQAAgK3gp2mAAiAQAQAAgK3gp2mAAiAQAAAA==.',
Ro='Rocknrolln:BAAANQADCgYIDAAAAA==.Rokubora:BAABNQAECn8zAAMjAAoKpBELLACuAQAjAAoKpBELLACuAQAiAAYKcAvZqwAZAQAAAA==.Rongyi:BAAANQAECgEIAQABNQAECgoKKgATAJkTAA==.Roronoa:BAAANQADCgYICwAAAA==.Roßyn:BAABNQAECn8sAAMEAAoKKROHJwDvAQAEAAkK2hOHJwDvAQAIAAYKWw+tbgAKAQAAAA==.',
Ru='Rubah:BAABNQAECn8fAAINAAgK5xqJGwBnAgANAAgK5xqJGwBnAgAAAA==.Rundail:BAAANQADCgQIBAAAAA==.Ruroni:BAABNQAECn8YAAIFAAgK1A0FmwD6AAAFAAgK1A0FmwD6AAAAAA==.',
Ry='Ryniel:BAAANQAECgUIBgAAAA==.',
['Ré']='Rédundant:BAABNQAECn8WAAIKAAgKEg2NNABNAQAKAAgKEg2NNABNAQABNQAECggIGQABACcNAA==.',
['Rì']='Rìzz:BAABNQAECn8lAAIjAAgKnR0iNQCjAgAjAAgKnR0iNQCjAgAAAA==.',
Sa='Sabrinalee:BAAANQADCgEIAQAAAA==.Saintdeamon:BAAANQADCgYIDAAAAA==.Sak:BAAANQADCgUIBQAAAA==.Salk:BAAANQADCgYIBgAAAA==.Sanasta:BAAANQAECgIIAwABNQAECgUIDwAGAAAAAA==.Sannaggi:BAAANQAECgYIDgAAAA==.Saorymu:BAAANQADCgIIAgAAAA==.Sarahnox:BAABNQAECn8oAAQUAAkKEhpQGwBeAgAUAAkKEhpQGwBeAgAhAAUKQwWzNQCIAAATAAIKRQu+cAAvAAAAAA==.Saramoon:BAABNQAECn8bAAILAAoK/gdxKwBnAQALAAoK/gdxKwBnAQAAAA==.Sarayana:BAAANQABCgMIBAAAAA==.Sargent:BAAANQADCggIGAAAAA==.Saryaa:BAAANQAECgcICwAAAA==.Sashchi:BAABNQAECn8nAAIMAAcKFRJ/IQAaAQAMAAcKFRJ/IQAaAQAAAA==.Sassenach:BAAANQAECgYICwAAAA==.Saudelber:BAAANQAECgUIBgAAAA==.',
Sc='Schanks:BAABNQAECn8WAAIcAAgKkhxNFwDCAgAcAAgKkhxNFwDCAgAAAA==.Scoliosisstu:BAAANQADCggICAAAAA==.Scrotius:BAAANQABCgQIBQAAAA==.',
Se='Sedaelina:BAAANQAECgEIAQABNQAECgkJIwAUAF0QAA==.Sehmet:BAABNQAECn8UAAILAAYKnBOYLQBVAQALAAYKnBOYLQBVAQAAAA==.Sekaï:BAAANQADCgEIAQAAAA==.Seliria:BAABNQAECn8sAAIQAAkKhBNrXQChAQAQAAkKhBNrXQChAQAAAA==.Seoulmate:BAABNQAECn8qAAITAAoKmRO/NgA2AgATAAoKmRO/NgA2AgAAAA==.Sera:BAABNQAECn8YAAIQAAgKkhRligARAgAQAAgKkhRligARAgAAAA==.Severûs:BAAANQAECgEIAQAAAA==.',
Sh='Shadoezz:BAAANQADCgQIBAAAAA==.Shadowk:BAAANQABCgIIAgAAAA==.Shamsicle:BAAANQADCgMIAwAAAA==.Shaye:BAAANQAECgUIEQAAAA==.Shelari:BAAANQADCgEIAQAAAA==.Sherai:BAAANQADCgIIAgAAAA==.Shieldbro:BAAANQADCgEIAQABNQAECggIDwAGAAAAAA==.Shimone:BAAANQADCgEIAQAAAA==.Shinybeef:BAAANQADCgcIFgAAAA==.Shiryo:BAAANQAECgQIBAAAAA==.Shotfoot:BAABNQAECn81AAIFAAoKYBnEIwBWAgAFAAoKYBnEIwBWAgAAAA==.Shwang:BAABNQAECn8XAAIFAAgKIRtVfQA5AQAFAAgKIRtVfQA5AQAAAA==.',
Si='Sihåya:BAAANQAECggIEAAAAA==.Silbergrad:BAAANQAECgEIAQAAAA==.Silentio:BAABNQAECn87AAIcAAoKvhExCQD4AQAcAAoKvhExCQD4AQAAAA==.Silihunt:BAABNQAECn81AAMZAAkK5xU+KAACAgAZAAgKihY+KAACAgAYAAgKrxKpOgDgAQAAAA==.Sinofwrath:BAAANQAECgcIDQAAAA==.Sinsidious:BAAANQAECgYIEQAAAA==.Siwin:BAECNQAFFH8NAAIUAAcKFx/AAgAwAgAUAAcKFx/AAgAwAgA1AAQKfycAAxQACgpDJU0DAJQDABQACgpDJU0DAJQDABMAAgoAAJabAGwAAAAA.',
Sk='Skribb:BAABNQAECn8vAAINAAkKqyHVDwDXAgANAAkKqyHVDwDXAgAAAA==.',
Sl='Slapchóp:BAABNQAECn8kAAIjAAkKzh1CHQARAgAjAAkKzh1CHQARAgAAAA==.',
Sm='Smiley:BAACNQAFFH8WAAIIAAcK3hXyBQDhAQAIAAcK3hXyBQDhAQA1AAQKfyoAAggACgrsG7YtAAwCAAgACgrsG7YtAAwCAAE1AAUUBwoWAAgA3hUA.Smoketron:BAAANQAECgUICQABNQAECgYIDQAGAAAAAA==.Smoko:BAAANQAECgUICQAAAA==.',
Sn='Sneakyboi:BAAANQAECggIDwAAAA==.Snorlax:BAABNQAECn8eAAQUAAkK3x0dFwCIAgAUAAkK3x0dFwCIAgAhAAMKFRa0SACLAAATAAIKYBUuogBYAAAAAA==.Snowsu:BAACNQAFFH8cAAQOAAgK+SA+AwBRAgAOAAYKwyI+AwBRAgABAAIKJiEkBgC/AAAVAAEKiRaXBQBeAAA1AAQKfz4ABA4ACgrjJmIBAOgDAA4ACgrjJmIBAOgDAAEABwrpHdsKAEkCABUAAQqHJuARAHIAAAAA.Snowxstorm:BAABNQAECn8nAAIPAAkKNho4FwDkAQAPAAkKNho4FwDkAQAAAA==.',
So='Soaringeagle:BAAANQABCgYICgAAAA==.Solidvodka:BAABNQAECn8VAAIFAAcKXxaIrgCnAQAFAAcKXxaIrgCnAQAAAA==.Solusrush:BAAANQABCgEIAQAAAA==.Souldecay:BAABNQAECn8pAAIJAAkK/A04HQCLAQAJAAkK/A04HQCLAQAAAA==.',
Sp='Splashzone:BAABNQAECn8dAAIiAAcKiAoenwA5AQAiAAcKiAoenwA5AQAAAA==.',
St='Staqua:BAAANQAECgUIDwAAAA==.Stateomatter:BAABNQAECn8eAAIFAAgKqgsPbABgAQAFAAgKqgsPbABgAQAAAA==.',
Su='Suanni:BAAANQADCgQIBAABNQAECgoKKgATAJkTAA==.Summdari:BAABNQAECn8jAAIeAAgKzRXyCwAMAgAeAAgKzRXyCwAMAgAAAA==.Summrot:BAABNQAECn8gAAMOAAkKig5ZaQAsAQAOAAcKDg5ZaQAsAQABAAMKjQ26RgCsAAAAAA==.Sunfrostt:BAAANQAECgQIDgAAAA==.',
Sy='Syanana:BAAANQADCgYICQAAAA==.Sylvalesta:BAAANQAECgUIDwAAAA==.',
Ta='Tacgnol:BAAANQADCgYIBgAAAA==.Talyon:BAAANQAECgYIEgAAAA==.Tanayla:BAAANQADCgYIBgAAAA==.Tatertotem:BAACNQAFFH8GAAIiAAMKnxiODwDlAAAiAAMKnxiODwDlAAA1AAQKfyQAAyIACgouGtIvAOQBACIACgouGtIvAOQBACgAAwpICjAwAG0AAAAA.',
Td='Tdogx:BAAANQAECgQIBAAAAA==.',
Te='Teal:BAAANQAECgIIBQAAAA==.Tekeeladin:BAAANQAECgQIBAABNQAFFAQICgAFAJsaAA==.Tekeelà:BAABNQAECn8uAAIFAAoKux+FFQCnAgAFAAoKux+FFQCnAgABNQAFFAQICgAFAJsaAA==.Tekelemental:BAABNQAECn8bAAIjAAcKfQ6eXwDuAAAjAAcKfQ6eXwDuAAAAAA==.Tempestra:BAAANQAECgYIDAAAAA==.Tenebria:BAABNQAECn88AAIlAAoKnB6VAQBNAwAlAAoKnB6VAQBNAwAAAA==.Terrorhungry:BAABNQAECn8YAAIDAAgK4gfVjAD2AAADAAgK4gfVjAD2AAAAAA==.',
Th='Thalstrasza:BAABNQAECn8hAAIOAAgKQQyrowCOAQAOAAgKQQyrowCOAQAAAA==.The:BAABNQAECn8VAAIKAAUK4g4hawDyAAAKAAUK4g4hawDyAAAAAA==.Thedevilsown:BAAANQADCgYICgAAAA==.Thedrizzle:BAABNQAECn8jAAMHAAkKlBXO3QDMAQAHAAgK+RPO3QDMAQAfAAIKzxu9LwCCAAAAAA==.Theodiseus:BAAANQADCgUIBQAAAA==.Thugrodent:BAAANQAECggJAQAAAA==.Thundrfury:BAAANQADCgQIBQAAAA==.Thysane:BAAANQADCgEIAQAAAA==.',
Ti='Tibalt:BAAANQAECgIIAwAAAA==.Tietus:BAAANQAECgUIBgAAAA==.',
Tl='Tlanimass:BAABNQAECn8aAAIaAAYKABOOHwBUAQAaAAYKABOOHwBUAQAAAA==.',
To='Tolac:BAAANQADCgEIAQAAAA==.',
Tr='Treeko:BAAANQADCggICAABNQAFFAcICwAOAIQRAA==.Treyna:BAAANQADCgMIAwAAAA==.',
Ts='Tsu:BAABNQAECn8VAAMMAAYKAxFUPgAjAQAMAAUKAxFUPgAjAQAmAAIK2AP2HwAmAAAAAA==.Tsyubaki:BAAANQAECgQICwAAAA==.',
Tu='Tulisse:BAAANQAECgEIAQAAAA==.',
Tw='Twerkngherkn:BAABNQAECn8WAAIHAAkK2w7HhQA3AQAHAAkK2w7HhQA3AQAAAA==.',
Ty='Tybalt:BAABNQAECn82AAIoAAoKyCK8AgB7AwAoAAoKyCK8AgB7AwAAAA==.Tynkxstrazza:BAAANQADCgEIAQAAAA==.Tyrandaz:BAAANQAECggIEQAAAA==.',
Ul='Uldric:BAABNQAECn8eAAIKAAgKMQjNOgAvAQAKAAgKMQjNOgAvAQAAAA==.',
Un='Undeaddude:BAAANQAECgcIDgAAAA==.Unslayable:BAAANQAECgQICgAAAA==.',
Uz='Uzzy:BAAANQAECgQICQAAAA==.',
Va='Valandir:BAABNQAECn8aAAMQAAgK1AyQxgCPAQAQAAgK1AyQxgCPAQARAAMKOgU3XABqAAAAAA==.Valyst:BAAANQAECgQIBgAAAA==.Varya:BAAANQABCgQIBQAAAA==.',
Ve='Veliry:BAAANQADCgYIDwAAAA==.Verbera:BAACNQAFFH8XAAIUAAYKBR4SAwCyAQAUAAYKBR4SAwCyAQA1AAQKfyUAAxQACgoFFU8cAFMCABQACgoFFU8cAFMCABMABgpsBaF7AN0AAAAA.Verrenth:BAAANQAECggIBgABNQAECggIDwAGAAAAAA==.',
Vi='Viduus:BAAANQAECgQICQAAAA==.Vigol:BAAANQADCgQJBAAAAA==.Viri:BAAANQABCgIIAgAAAA==.Vivec:BAAANQADCgMIAwAAAA==.',
Vm='Vmaoh:BAAANQADCggIEAAAAA==.',
Vo='Voidrodent:BAAANQAECggIBgAAAA==.Voidwithin:BAAANQAECgQIBgAAAA==.Voljinforeva:BAAANQADCgQJBgAAAA==.Voltage:BAAANQAECgEIAQAAAA==.',
Vu='Vulfox:BAAANQAECgMIBQABNQAECgkJHAAIAIIYAA==.',
Wa='Wakenbake:BAAANQADCgUIBQAAAA==.Wandiferous:BAAANQAECgYIEwAAAA==.',
Wf='Wfreemen:BAAANQADCgQIBAAAAA==.',
Wh='Who:BAAANQAECgcICwABNQAFFAYIEAAIAB8IAA==.',
Wi='Wickedholi:BAAANQAECgcIBwABNQAFFAcICwAOAIQRAA==.Wickedsmaht:BAACNQAFFH8LAAMOAAcKhBEvGAAzAQAOAAUKUREvGAAzAQABAAIK0BGNDgCZAAA1AAQKf0AABA4ACgp7IusdAA0DAA4ACQpoIOsdAA0DABUABAolIA4GAG0BAAEABArCIc8GABEBAAAA.Widowghast:BAABNQAECn8iAAIHAAgK8hR4vAALAgAHAAgK8hR4vAALAgAAAA==.Wildforge:BAAANQABCgQIBgAAAA==.Willowísp:BAABNQAECn8wAAImAAoKIBzHBgDZAgAmAAoKIBzHBgDZAgAAAA==.Witerally:BAAANQAECgQICgAAAA==.Wiz:BAAANQABCgEIAQABNQAECgkJHgAUAN8dAA==.',
Wo='Woggers:BAAANQADCgYICwAAAA==.',
Wu='Wujo:BAEBNQAECn8bAAMFAAkKrA/zsQCgAQAFAAkKrA/zsQCgAQAbAAEKbAZ3kgAuAAAAAA==.',
Wy='Wynters:BAAANQAECgQIBAAAAA==.',
Xa='Xalthea:BAABNQAECn87AAQZAAoKrxIpEgDIAQAZAAoKrxIpEgDIAQAeAAEKwQj9NgAhAAAYAAcKGgCuowAUAAAAAA==.Xandapriest:BAAANQADCgYICwABNQAFFAUIDgAcACQSAA==.Xanlock:BAAANQADCgUIBwABNQAECgkJJAAhAP8WAA==.',
Xi='Xingyue:BAAANQADCgIIAgABNQAECgoKKgATAJkTAA==.',
Xp='Xpddevour:BAABNQAECn88AAIYAAoKzBdEEQA4AgAYAAoKzBdEEQA4AgAAAA==.',
Xt='Xtena:BAAANQADCgIIAgAAAA==.Xtendron:BAACNQAFFH8IAAIQAAQKuwn7DwDFAAAQAAQKuwn7DwDFAAA1AAQKfzsAAhAACgrzHj0fAJECABAACgrzHj0fAJECAAAA.',
Xu='Xuxo:BAAANQADCgYIBwAAAA==.',
Ya='Yashoda:BAAANQABCggJCAAAAA==.Yawning:BAAANQADCgcIBwABNQAECggIGQABACcNAA==.',
Ye='Yegarmiester:BAAANQAECgcIDAAAAA==.Yenti:BAABNQAECn8XAAIQAAUKPwLSVQGXAAAQAAUKPwLSVQGXAAAAAA==.',
Yu='Yuexi:BAAANQAECgIIAgABNQAECgoKKgATAJkTAA==.',
['Yâ']='Yâni:BAAANQADCgIIAgAAAA==.',
Za='Zaco:BAABNQAECn8eAAIkAAUKkRYYEADrAAAkAAUKkRYYEADrAAAAAA==.Zamochy:BAAANQAECgUIBQAAAA==.Zap:BAAANQAECgcIBgABNQAECgkJHgAUAN8dAA==.Zatapa:BAAANQAECgUICgAAAA==.',
Ze='Zendàya:BAAANQADCgEIAQAAAA==.Zerality:BAAANQAECgYIDgAAAA==.',
Zh='Zhiso:BAAANQABCgYIBwAAAA==.',
Zi='Ziggie:BAABNQAECn8vAAIZAAkKeCQCBwBiAwAZAAkKeCQCBwBiAwAAAA==.Zinovia:BAAANQAECgQIBAAAAA==.',
Zo='Zoltan:BAAANQADCggIIgAAAA==.Zookee:BAABNQAECn8pAAIXAAkKNAv9DgCQAQAXAAkKNAv9DgCQAQAAAA==.',
Zu='Zulizek:BAABNQAECn8sAAIiAAkKvws5QQCSAQAiAAkKvws5QQCSAQAAAA==.',
Zy='Zynister:BAABNQAECn8vAAMKAAoK9x28DgB8AgAKAAoK9x28DgB8AgAPAAUKzRFOgQD2AAAAAA==.',
['Ûr']='Ûrta:BAAANQADCgEIAQAAAA==.',
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
