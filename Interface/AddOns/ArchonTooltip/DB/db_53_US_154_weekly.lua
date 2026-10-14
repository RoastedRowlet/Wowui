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

local lookup = {'Mage-Arcane','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Monk-Windwalker','Hunter-BeastMastery','DeathKnight-Blood','Evoker-Devastation','Priest-Shadow','Unknown-Unknown','Shaman-Restoration','Warlock-Affliction','Mage-Frost','DemonHunter-Devourer','Shaman-Elemental','Rogue-Outlaw','Warrior-Protection','Druid-Guardian','Rogue-Assassination','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Warrior-Arms','Warrior-Fury','DemonHunter-Vengeance','DeathKnight-Frost','Druid-Balance','Druid-Feral','DemonHunter-Havoc','DeathKnight-Unholy','Mage-Fire','Priest-Holy','Druid-Restoration','Shaman-Enhancement','Priest-Discipline','Evoker-Augmentation','Evoker-Preservation','Hunter-Marksmanship','Rogue-Subtlety','Hunter-Survival',}
local provider = {region='US',realm='Mannoroth',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aadda:BAACNQAFFH8LAAIBAAMKYRZYNADuAAABAAMKYRZYNADuAAA1AAQKfy0AAgEACQq9HiFAAAUDAAEACQq9HiFAAAUDAAAA.',
Ab='Abcdpal:BAACNQAFFH8RAAQCAAcKGhwTBAAlAgACAAYKiRwTBAAlAgADAAEKYhoZDwBQAAAEAAEKngBLLwAyAAA1AAQKfxgAAgIACQodIms5AOgCAAIACQodIms5AOgCAAAA.Abena:BAAANQAECgcICgAAAA==.Abighoul:BAAANQADCgYICAABNQAECgkJJQAFAAEeAA==.Abowolf:BAAANQAECggICAABNQAECgkJJAAGAEogAA==.Abusive:BAABNQAECn8gAAIHAAkKex26HQDBAgAHAAkKex26HQDBAgAAAA==.',
Ac='Acat:BAAANQAECgYICwAAAA==.Ackamaracus:BAAANQADCgYICQAAAA==.',
Ae='Aeice:BAAANQAECgIIAgAAAA==.Aerogosa:BAACNQAFFH8NAAIIAAQK3x6PBQBhAQAIAAQK3x6PBQBhAQA1AAQKfzAAAggACQqKIxYCAJoDAAgACQqKIxYCAJoDAAAA.Aeyonce:BAAANQADCgcIBwAAAA==.',
Af='Affrika:BAAANQADCgEIAQAAAA==.',
Ag='Agogagog:BAABNQAECn8kAAIJAAgKhhBcKQDaAQAJAAgKhhBcKQDaAQAAAA==.',
Ah='Ahlaris:BAAANQADCgcIBwABNQAECgMIAwAKAAAAAA==.',
Ai='Aicam:BAAANQAECgEIAQAAAA==.',
Ak='Akashani:BAAANQABCggICAAAAA==.Akaza:BAAANQAECgYICgAAAA==.',
Al='Alanalanalan:BAAANQAECgEIAQAAAA==.Alarg:BAAANQADCgIIAgABNQAECggIFQALAFUjAA==.Alatide:BAABNQAECn8VAAILAAgKVSMSFwAXAwALAAgKVSMSFwAXAwAAAA==.Alcani:BAAANQADCgYIBgAAAA==.Aleena:BAAANQADCgcICgAAAA==.Alleriaa:BAAANQADCggIDAAAAA==.Alphakuup:BAAANQADCgYICQABNQAECggIIgAMAP0VAA==.Altazar:BAABNQAECn8nAAMNAAkK0BIxEwByAQABAAgKvxDzxQD3AQANAAUKbhUxEwByAQAAAA==.Alxath:BAABNQAECn8YAAIOAAgKNCBoGQCNAgAOAAgKNCBoGQCNAgAAAA==.',
Am='Amaryste:BAAANQAECgEIAQAAAA==.Amidalah:BAABNQAECn8YAAIGAAkKchggQACoAgAGAAkKchggQACoAgAAAA==.Amizlia:BAAANQADCgEIAQAAAA==.Amorinaron:BAACNQAFFH8FAAIBAAQKDAQnMgD5AAABAAQKDAQnMgD5AAA1AAQKf0gAAgEACQonI5QPAJQDAAEACQonI5QPAJQDAAAA.',
An='Anansi:BAAANQAECgIIAgABNQAFFAcIHgAIANYkAA==.Andrés:BAAANQADCgUIBgAAAA==.Andsong:BAAANQADCgUIBQABNQAECgYIEQAKAAAAAA==.Anfalas:BAABNQAECn8+AAIPAAkKCCLxEwBQAwAPAAkKCCLxEwBQAwAAAA==.Anic:BAABNQAECn8lAAIGAAkKgxl0KAD1AgAGAAkKgxl0KAD1AgAAAA==.Anikora:BAAANQADCgcIDAAAAA==.Anjelika:BAAANQAECgUIDwAAAA==.Anklestabber:BAABNQAECn8vAAIQAAkKNR9iAgA0AwAQAAkKNR9iAgA0AwAAAA==.Annathema:BAAANQADCgQIBAAAAA==.Anser:BAAANQAECgQIBAAAAA==.Anthlina:BAAANQADCgUIBwAAAA==.',
Ap='Aprilthehag:BAAANQADCgYIBgAAAA==.',
Ar='Archicrash:BAAANQAECgQIBQAAAA==.Archipal:BAAANQADCgMIAwAAAA==.Archnash:BAAANQAECgIIAQAAAA==.Archomen:BAAANQADCgQIBAABNQAECgQICQAKAAAAAA==.Arcwave:BAAANQAECgIIAgAAAA==.Arcyon:BAAANQAECgYIEQAAAA==.Arethi:BAACNQAFFH8UAAIRAAUKjSWqAAAqAgARAAUKjSWqAAAqAgA1AAQKfyQAAhEACQodJCQDAHADABEACQodJCQDAHADAAAA.Arial:BAAANQADCgYIBgABNQAECgQICQAKAAAAAA==.Arleos:BAABNQAECn8wAAIEAAkKZRwTJQDUAgAEAAkKZRwTJQDUAgAAAA==.Arroyo:BAAANQADCggIKgAAAA==.Artemasz:BAAANQAECgUIEAAAAA==.',
As='Asrelle:BAABNQAECn8ZAAIDAAkKARF8KACWAQADAAkKARF8KACWAQAAAA==.Astaumin:BAAANQADCgYICgAAAA==.Asterrin:BAAANQAECgIIAwAAAA==.Astralfrog:BAAANQAECgQIBgAAAA==.',
At='Ateelasham:BAAANQAECgYICwAAAA==.Atrophied:BAAANQAECgIIAwABNQAECgkJNwASACIhAA==.',
Au='Audeline:BAAANQAECgQICAAAAA==.Augmented:BAAANQABCgYICgABNQAECgkJNwAEANcmAA==.Auraelia:BAAANQADCgEIAQAAAA==.Aurilia:BAAANQADCggICwAAAA==.Aurôra:BAAANQAECgUICwAAAA==.',
Av='Avran:BAABNQAECn8oAAIOAAkKxRzYDgD8AgAOAAkKxRzYDgD8AgAAAA==.',
Az='Aziala:BAAANQAECggIEwABNQAECgkJLAAIACEiAA==.Azreluna:BAABNQAECn8vAAITAAkKhg7DLQAqAgATAAkKhg7DLQAqAgAAAA==.',
Ba='Backstabr:BAAANQAECgYICgAAAA==.Backyard:BAAANQADCgQIBAAAAA==.Badwords:BAAANQADCgYICAAAAA==.Bajablight:BAAANQAECgIIAgAAAA==.Bajiggitee:BAABNQAECn81AAIHAAkKfxf8JgCEAgAHAAkKfxf8JgCEAgAAAA==.Ballsakz:BAAANQAECgYICQAAAA==.Bananarosin:BAABNQAECn8hAAQMAAcKkAmRGwCiAAAUAAYK8Apu0QAiAQAVAAQKCwNtSAClAAAMAAMKvAORGwCiAAAAAA==.Banlers:BAAANQADCgYIFAAAAA==.Banmedaddy:BAAANQADCggIFAABNQABCgIJAgAKAAAAAA==.Baradoon:BAABNQAECn8WAAIPAAcKgRlmXgADAgAPAAcKgRlmXgADAgAAAA==.Barbamage:BAAANQADCgYICAABNQAECgkJHAALAEITAA==.Bazrameet:BAABNQAECn8cAAIBAAkKBhLFtgAUAgABAAkKBhLFtgAUAgABNQAFFAQIBwAIAPENAA==.',
Be='Bealzhunter:BAAANQADCgUIBgAAAA==.Beasthunter:BAAANQABCgUIBwAAAA==.Bela:BAAANQADCgcIBwAAAA==.Bellion:BAAANQAECgMIBgAAAA==.Beo:BAACNQAFFH8HAAIWAAQKoBYDBgA3AQAWAAQKoBYDBgA3AQA1AAQKfyUAAhYACQqSGcAQAG8CABYACQqSGcAQAG8CAAAA.',
Bi='Bigbluetaco:BAABNQAECn8xAAQXAAkKVxkpWwB3AgAXAAkKFBkpWwB3AgARAAcKIxKAIABFAQAYAAIKNghwLABPAAAAAA==.Bigchug:BAABNQAECn8rAAIFAAkK2CGaCQA1AwAFAAkK2CGaCQA1AwAAAA==.Biggirlsonly:BAAANQAECgUICwABNQAFFAcIHgAIANYkAA==.Bigglob:BAAANQAECgMIAwAAAA==.Bigyahu:BAAANQADCgYIBgAAAA==.Bitelo:BAAANQADCggICAABNQADCggICAAKAAAAAA==.',
Bl='Blast:BAAANQADCgIIAgAAAA==.Blatt:BAAANQAECgEIAQAAAA==.Blech:BAABNQAECn8zAAIBAAkKoQ/uqQAtAgABAAkKoQ/uqQAtAgAAAA==.',
Bo='Bookerneg:BAAANQAECgYIDwAAAA==.Boomslang:BAAANQAECgQICwAAAA==.Borlen:BAABNQAECn8YAAIHAAcKiBbLRgDbAQAHAAcKiBbLRgDbAQAAAA==.Bouncyball:BAAANQAECgIIAgABNQAECgQICAAKAAAAAA==.Boxofcookies:BAAANQAECgQIBAAAAA==.',
Br='Braids:BAAANQAECgIIAwAAAA==.Brassfeather:BAAANQAECgQICgAAAA==.Brewcifer:BAAANQADCgMIAwAAAA==.Brezzath:BAAANQADCggICAAAAA==.Brezzid:BAAANQADCgYICwABNQAECggIKAAZAGUOAA==.Brezzon:BAABNQAECn8oAAIZAAgKZQ5DEQCYAQAZAAgKZQ5DEQCYAQAAAA==.Brizzletwo:BAABNQAECn8fAAILAAgK6AtniABxAQALAAgK6AtniABxAQAAAA==.Brozzath:BAAANQAECgYICgABNQAECggIKAAZAGUOAA==.Bryanka:BAAANQADCggICgAAAA==.Brystal:BAAANQAECgYICAAAAA==.Brättie:BAAANQAECgUIBwAAAA==.Bróx:BAABNQAECn8fAAIXAAkK1hagWwB2AgAXAAkK1hagWwB2AgAAAA==.',
Bu='Bubbajoe:BAAANQAECgIIAgABNQAFFAcIHgAIANYkAA==.Bubbajr:BAAANQAECgYICAAAAA==.Bungholio:BAAANQAECgQIBwAAAA==.Burgy:BAABNQAECn8bAAMVAAgKXRTNDwD/AQAVAAcKDhbNDwD/AQAUAAUK2Aft7gDnAAABNQAECggIJgAHAGYPAA==.Burgydk:BAABNQAECn8mAAMHAAgKZg+fXgB0AQAHAAcKww6fXgB0AQAaAAIKQw01kABwAAAAAA==.Buttfancy:BAABNQAECn8lAAIbAAkKLhVqKwB7AgAbAAkKLhVqKwB7AgAAAA==.',
['Bï']='Bïgbear:BAAANQAECggIAwAAAA==.Bïgblood:BAAANQAECgcIAQABNQAECggIAwAKAAAAAA==.Bïgdot:BAAANQAECgcIBwABNQAECggIAwAKAAAAAA==.',
Ca='Cainbanw:BAAANQADCgUICAAAAA==.Caliery:BAAANQABCgEIAQAAAA==.Calivaris:BAAANQAECgQIBAAAAA==.Calmpressure:BAABNQAECn8WAAIFAAgKQyN6DAAOAwAFAAgKQyN6DAAOAwAAAA==.Capnsparrow:BAAANQAECgQICQAAAA==.Captncheese:BAAANQAECgEIAgAAAA==.Cargy:BAAANQADCgcJCQAAAA==.Carshas:BAAANQADCggIDgAAAA==.Cas:BAAANQAECgMIBQAAAA==.Cassielee:BAAANQAECgQICAAAAA==.Catabop:BAAANQAECgQIDwABNQAECgkJKgALAFsgAA==.Cataclysmicu:BAAANQAECgEIAQAAAA==.Catastorm:BAABNQAECn8qAAILAAkKWyDqGAANAwALAAkKWyDqGAANAwAAAA==.Catavoker:BAAANQAECgQIDwABNQAECgkJKgALAFsgAA==.Catsthunder:BAAANQAECgMIAwABNQAECgkJUwAXAAoiAA==.Caustic:BAABNQAECn8bAAMUAAkK6h/gTwBiAgAUAAcKGyDgTwBiAgAVAAIKcB9mRwCoAAAAAA==.Caveatemptor:BAACNQAFFH8GAAIbAAMKrg8tGADkAAAbAAMKrg8tGADkAAA1AAQKfx8AAhsACArNIC8rAH0CABsACArNIC8rAH0CAAAA.',
Ce='Celaina:BAAANQAECgUIBwAAAA==.',
Ch='Chainhappy:BAAANQAECgYICwAAAA==.Chaotiç:BAAANQADCgIIAgAAAA==.Cheezybread:BAAANQADCgUIBQAAAA==.Chesshire:BAAANQAECgYICQAAAA==.Chillfactor:BAAANQAECgYIBgAAAA==.Chimeric:BAABNQAECn83AAMSAAkKIiEEBABtAwASAAkKIiEEBABtAwAcAAYKjwiLIQACAQAAAA==.Chiridrake:BAAANQAECgEIAQAAAA==.Chlover:BAAANQAECgUIDQAAAA==.Chmap:BAAANQADCggJFQABNQAECgYIEAAKAAAAAA==.Chontosh:BAAANQAECgUIDwAAAA==.Chozenfate:BAAANQADCggIEQAAAA==.Chronuwu:BAAANQAECgcICwAAAA==.',
Ci='Cindymccain:BAABNQAECn8aAAIaAAgK+BN0OADtAQAaAAgK+BN0OADtAQAAAA==.',
Cl='Clearsight:BAAANQAECgUICQABNQAECgkJPQALAOEhAA==.Clemfandengo:BAAANQAECgYICwAAAA==.',
Co='Cogs:BAAANQADCggICAAAAA==.Cometh:BAAANQADCggIEAAAAA==.Compute:BAACNQAFFH8FAAIaAAIKdxG7FwB9AAAaAAIKdxG7FwB9AAA1AAQKf0MAAhoACQpKIf8MACoDABoACQpKIf8MACoDAAE1AAQKCAgQAAoAAAAA.Corursa:BAAANQAECgYICAABNQAECgYIDgAKAAAAAA==.Cozmowaffle:BAAANQADCgIIAgAAAA==.',
Cr='Critterr:BAAANQADCgEIAQAAAA==.Cronauer:BAAANQAECgUIEQAAAA==.Cryofrog:BAAANQADCgYICwAAAA==.',
Ct='Cthulusfiend:BAAANQAECgYICgABNQAFFAcIHgAIANYkAA==.',
Cu='Cuppicakies:BAAANQADCgUIBwAAAA==.Cursyn:BAAANQAECgIIAgAAAA==.',
Da='Dabbington:BAAANQAECgYIEgAAAA==.Daddilock:BAAANQAECgQICgAAAA==.Daddyfatslap:BAACNQAFFH8GAAICAAIKGB+OHAC8AAACAAIKGB+OHAC8AAA1AAQKfx0AAgIACAr4IucmACgDAAIACAr4IucmACgDAAAA.Daggerz:BAABNQAECn8hAAITAAgKqx6LGgClAgATAAgKqx6LGgClAgAAAA==.Daguitas:BAABNQAECn8oAAITAAgKww8VQgC8AQATAAgKww8VQgC8AQAAAA==.Dahood:BAAANQAECgIIAwAAAA==.Danasty:BAAANQAECgQIBQAAAA==.Danidakiesh:BAAANQAECgMIBgAAAA==.Daralina:BAAANQABCgIIAgAAAA==.Darbreezius:BAABNQAECn8lAAQUAAkKMh18HAARAwAUAAkKAB18HAARAwAMAAQKZRudEABAAQAVAAIKBBmqTgCSAAAAAA==.Daribow:BAAANQADCgcICwAAAA==.Darkcoffee:BAABNQAECn8jAAMZAAkKQxQcEwB3AQAdAAYK/BpYNwDxAQAZAAkKQQocEwB3AQAAAA==.Darkvalk:BAAANQADCgIIAwAAAA==.Daroc:BAAANQAECggICwAAAA==.Darvax:BAAANQAECgEIAQAAAA==.Datacenter:BAAANQAECggIEAAAAA==.Dattz:BAAANQAECgIIAgAAAA==.Dawgan:BAAANQAECgQICgAAAA==.',
De='Deadlyfrog:BAAANQADCgcIDAAAAA==.Deamionn:BAAANQAECgQIBgAAAA==.Deathbauchs:BAAANQADCgcICwAAAA==.Deathlylove:BAAANQABCgYIBgAAAA==.Deathtreader:BAAANQADCggICAAAAA==.Delsym:BAAANQAECgQICgAAAA==.Demoinc:BAACNQAFFH8FAAIYAAQK0gTwAQDyAAAYAAQK0gTwAQDyAAA1AAQKfywAAxgACQpmGhwHAIkCABgACAoGHBwHAIkCABcABgpTEEPOAFIBAAAA.Denathus:BAAANQADCgYIDwAAAA==.Denovo:BAAANQADCggICAABNQAFFAMIBgAbAK4PAA==.Desipator:BAAANQAECgMIAwAAAA==.Destinyløl:BAAANQAECgYIEQAAAA==.',
Di='Di:BAAANQAECgUIBwABNQAECggIEAAKAAAAAA==.Diabolix:BAAANQADCgQIBwAAAA==.Dilo:BAAANQAECggIEAAAAA==.Distortion:BAAANQAECgQIBAABNQAECgkJHwAbAFEgAA==.Divalatina:BAACNQAFFH8aAAIEAAYKcwhJCgC0AQAEAAYKcwhJCgC0AQA1AAQKfy4AAgQACQpTF61RACMCAAQACQpTF61RACMCAAAA.Divinefrog:BAAANQAECgQIBAAAAA==.',
Dj='Djmax:BAAANQADCgIIAgAAAA==.',
Dk='Dkthae:BAABNQAECn8tAAIHAAkKYh+dEAAmAwAHAAkKYh+dEAAmAwAAAA==.',
Dl='Dlxanomaly:BAABNQAECn8lAAIBAAgKZhzBdQCSAgABAAgKZhzBdQCSAgAAAA==.',
Do='Doeurden:BAAANQADCgYIBgAAAA==.Donttouchme:BAAANQADCgcIDAAAAA==.Doohickey:BAAANQAECgUIEAABNQAECgYICwAKAAAAAA==.Dotsdaddy:BAAANQADCggJDwAAAA==.Doubledeez:BAAANQADCgIIAgAAAA==.Doubledz:BAAANQADCggIFQAAAA==.',
Dr='Dracslaya:BAAANQADCgcIDQAAAA==.Dragonaire:BAAANQADCgQIBwAAAA==.Dragondzntz:BAAANQAECgYIDQAAAA==.Dragonfrog:BAAANQADCgMIAwAAAA==.Dreamyeyes:BAABNQAECn8eAAIMAAcKmBGbCgDIAQAMAAcKmBGbCgDIAQAAAA==.Drerein:BAAANQAECgUIDgAAAA==.Drägonfrog:BAAANQADCgQIBgAAAA==.',
Du='Dubz:BAAANQAECggIDAAAAA==.Dundeal:BAAANQADCgcIBwAAAA==.Dungals:BAAANQADCgcIBwAAAA==.Dunkel:BAABNQAECn8qAAMeAAkKHxnxNQBNAgAeAAkKHxnxNQBNAgAaAAIK1w3ElgBgAAAAAA==.Dupichu:BAABNQAECn8pAAIHAAkKuBp3IACtAgAHAAkKuBp3IACtAgAAAA==.',
Dy='Dyane:BAAANQADCggIEwAAAA==.',
Ea='Eataa:BAAANQAECgIIBAAAAA==.',
Eb='Ebonhammer:BAAANQADCgIIAgAAAA==.',
Ed='Edgyteiva:BAAANQAFFAIIAgAAAA==.',
Eg='Egrilo:BAAANQADCggICAAAAA==.',
Ei='Eileithyia:BAAANQAECgcIEgAAAA==.',
El='Elekastra:BAAANQAECgIIAgAAAA==.Ellonan:BAAANQADCggICwABNQAFFAMIBgADAA4LAA==.Ellz:BAAANQAECgYIEAAAAA==.Elyndor:BAAANQADCgUIBQAAAA==.',
Em='Emopally:BAABNQAECn8kAAMeAAgKBhOpSwDjAQAeAAgKBhOpSwDjAQAaAAYK0g0PXAAvAQAAAA==.Emopower:BAAANQAECgUICwAAAA==.',
En='Enderr:BAABNQAECn8lAAIFAAkKAR5bDgD3AgAFAAkKAR5bDgD3AgAAAA==.Enegma:BAAANQADCgYICgAAAA==.Energètic:BAAANQADCgIIAgAAAA==.Enzini:BAAANQAECgQIBQAAAA==.',
Er='Erashi:BAAANQAECgQJBAAAAA==.',
Eu='Eupraxia:BAAANQAECggICAABNQAECggIDwAKAAAAAA==.',
Ev='Eviale:BAAANQAECgYIBgAAAA==.',
Fa='Falculan:BAAANQADCgEIAQAAAA==.Fallen:BAAANQAECgUIEQABNQABCgIJAgAKAAAAAA==.Fatherchung:BAAANQAECgQIBgAAAA==.Fayotbeanz:BAAANQABCgYIDAAAAA==.',
Fe='Felwyth:BAAANQAECgIIAgABNQAECgkJHwAYAB8VAA==.Ferdinanna:BAAANQAECgIIAgAAAA==.Feythe:BAAANQAECggIDwABNQAECgkJJQAFAAEeAA==.',
Fi='Finneas:BAAANQADCgEIAQAAAA==.Fireworkxz:BAAANQAECgEIAgAAAA==.Fishhawk:BAAANQAECgUICQAAAA==.',
Fl='Flarehammer:BAABNQAECn8pAAMCAAkK4yDvQwDGAgACAAgKjiLvQwDGAgADAAQKuhHoRQDUAAAAAA==.Flogh:BAABNQAECn8cAAIfAAgKKRYAAgBUAgAfAAgKKRYAAgBUAgAAAA==.',
Fo='Fomanshi:BAACNQAFFH8HAAIIAAQK8Q0nBwAgAQAIAAQK8Q0nBwAgAQA1AAQKfzcAAggACQrKHSIJAOACAAgACQrKHSIJAOACAAAA.Forleaf:BAAANQAECgQIBAAAAA==.Forsierra:BAAANQADCgEIAQAAAA==.Foxiji:BAAANQAECgIIAgAAAA==.',
Fr='Frexadin:BAAANQADCgYIBwAAAA==.Frexican:BAABNQAECn8oAAIGAAgKZxnYXABcAgAGAAgKZxnYXABcAgAAAA==.Fright:BAAANQAECgUIDQAAAA==.Frogleggs:BAAANQABCgQIBgAAAA==.Frogshock:BAAANQADCgUIBQAAAA==.',
Fu='Fupabean:BAAANQADCgcIBwAAAA==.Fure:BAAANQAECgYIBgAAAA==.Fuupa:BAAANQADCgIIAgAAAA==.',
['Fí']='Fíg:BAAANQADCgYIBgAAAA==.',
['Fö']='Förbindelse:BAAANQAECgEIAQAAAA==.',
Ga='Gangdat:BAAANQAECgMIBQAAAA==.Garur:BAAANQAECgQICAAAAA==.',
Ge='Genridge:BAAANQADCgYIDAAAAA==.Getowned:BAAANQADCgYIBgAAAA==.Gewl:BAAANQAECgUIBgABNQAECgkJJQAFAAEeAA==.',
Gh='Ghostmain:BAAANQADCgcICQAAAA==.',
Gi='Gilani:BAAANQAECgEIAQAAAA==.',
Gl='Glp:BAAANQAECgcICAAAAA==.Glunt:BAAANQADCggICAABNQAECggIEAAKAAAAAA==.',
Go='Gorpy:BAACNQAFFH8UAAQUAAgKcyJuBAAzAgAUAAYKcSRuBAAzAgAVAAIKyCB+BwC3AAAMAAEKch8JBwBnAAA1AAQKfy4ABBQACQqOJkgOAFsDABQACApUJkgOAFsDABUABwpvHN8JAFkCAAwAAQrTHgMnAE4AAAAA.Gotrott:BAAANQADCgEIAQAAAA==.',
Gr='Gravybones:BAAANQADCgcIFAAAAA==.Grayparse:BAAANQADCgQIBAAAAA==.Greenjesh:BAACNQAFFH8FAAIBAAQKVwvpLQAYAQABAAQKVwvpLQAYAQA1AAQKfyMAAgEACQq7GKhXANECAAEACQq7GKhXANECAAAA.Greensheesh:BAABNQAECn8oAAIBAAkKtBn6fwB+AgABAAkKtBn6fwB+AgABNQAFFAQIBQABAFcLAA==.Greypilgram:BAAANQAECgMIBAAAAA==.Grimstank:BAAANQADCggJFQAAAA==.Grizzlygerm:BAAANQADCgUIBQAAAA==.Grizzlyoné:BAAANQAECgIIAwAAAA==.Gronck:BAAANQAFFAIIAwAAAA==.Grumbleface:BAACNQAFFH8UAAIEAAYK0BEKCADfAQAEAAYK0BEKCADfAQA1AAQKfyQAAgQACQrkIE4UAC8DAAQACQrkIE4UAC8DAAAA.Grumbletron:BAABNQAECn8hAAIgAAgKfR7YJgDNAgAgAAgKfR7YJgDNAgAAAA==.Gröver:BAAANQAECgIIAgABNQAECggIEAAKAAAAAA==.',
Gs='Gstatus:BAABNQAECn8YAAIPAAgKLQwAdgC7AQAPAAgKLQwAdgC7AQAAAA==.',
Gu='Gumbotron:BAAANQADCggICAAAAA==.Gunel:BAAANQAECgYICwAAAA==.',
Ha='Haawee:BAAANQAECggIEgAAAA==.Haelresursus:BAAANQAECgQIBAABNQAECgkJMAABAFIeAA==.Hailcthulhu:BAABNQAECn8ZAAIOAAcKBx7pJQATAgAOAAcKBx7pJQATAgAAAA==.Handcuffs:BAAANQAECgMJAwAAAA==.Handorn:BAAANQAECgQIBwABNQAFFAMIBwAMAGkQAA==.Hanwha:BAAANQAECgYICwAAAA==.Harrower:BAABNQAECn8XAAIOAAcKfRl/KQDzAQAOAAcKfRl/KQDzAQAAAA==.Haze:BAAANQAECggIEQAAAA==.Hazzkul:BAABNQAECn8xAAIGAAkKJSbwAwDJAwAGAAkKJSbwAwDJAwAAAA==.',
He='Healness:BAABNQAECn8gAAILAAkKkSGIFAAnAwALAAkKkSGIFAAnAwAAAA==.Helasam:BAAANQAECgIIAwAAAA==.Hellbourné:BAAANQAECgEIAQAAAA==.Helloboys:BAABNQAECn8oAAIUAAkKBBLBXQA6AgAUAAkKBBLBXQA6AgAAAA==.Helnome:BAAANQAECgQIBAABNQAECgQICgAKAAAAAA==.Henzo:BAAANQABCgEIAQAAAA==.Herbavor:BAAANQAECgMIBQAAAA==.Hermes:BAABNQAECn81AAMUAAkKgSDhHQALAwAUAAgKCiLhHQALAwAVAAQK2hHJNwDhAAAAAA==.Hermestrisme:BAAANQAECgEIAwAAAA==.',
Hi='Hiemultis:BAAANQADCggIGQAAAA==.',
Ho='Hogroxx:BAAANQADCgYIBgAAAA==.Holexplorer:BAABNQAECn8uAAIXAAgKRSRCIgAtAwAXAAgKRSRCIgAtAwAAAA==.Holytrashie:BAAANQAECgUIDAAAAA==.Honeybadger:BAABNQAECn8kAAQhAAgKgheSHwArAgAhAAgKgheSHwArAgAcAAUK5hkwGAB0AQAbAAUKJRgxXgBUAQAAAA==.Honnybuns:BAAANQABCgUIBQAAAA==.Hoofsmack:BAAANQADCggICgAAAA==.Hordeji:BAAANQAECgUIBQAAAA==.Hordeslayer:BAAANQADCgUICAAAAA==.Hornyvalk:BAAANQADCgEIAQAAAA==.',
Hs='Hsk:BAABNQAECn8bAAMNAAgKfh70BwBoAgANAAgKfh70BwBoAgABAAQKZg0fXgHyAAAAAA==.',
Hu='Hugostiglitx:BAAANQAECgIIAwAAAA==.Hulkaholic:BAABNQAECn8nAAMPAAkKgCKiDgBzAwAPAAkKgCKiDgBzAwAiAAMKww0oKwCrAAAAAA==.Hulkclap:BAAANQABCgMIAwAAAA==.Hulkdemon:BAAANQABCgUIBwAAAA==.Hulkhunts:BAAANQABCgUIDAAAAA==.',
['Hÿ']='Hÿphy:BAAANQAECgIIAgAAAA==.',
Ia='Ianthor:BAAANQADCgUIBQAAAA==.',
Ic='Icecat:BAAANQAECgYIDwAAAA==.',
Il='Ilian:BAAANQADCgQICwAAAA==.Illionecho:BAAANQABCgUIBQAAAA==.',
In='Indoo:BAAANQABCgcIBQAAAA==.Innothule:BAAANQADCgUIBQAAAA==.Inseratum:BAAANQAECgEIAQAAAA==.Intrepidus:BAAANQADCgEIAQABNQAECgYICgAKAAAAAA==.Inê:BAABNQAECn8mAAMTAAgKqBTqLgAjAgATAAgKqBTqLgAjAgAQAAMK0g9tFACqAAAAAA==.',
Iq='Iqbal:BAAANQADCgEIAQABNQAECgkJHwAbAFEgAA==.',
Ir='Iriedraco:BAAANQABCgIIAgAAAA==.Irielite:BAAANQABCgQIBAAAAA==.',
Is='Ishaa:BAAANQAECgYICwAAAA==.',
It='Ithanksource:BAABNQAECn8fAAIEAAkKGRxXHQD8AgAEAAkKGRxXHQD8AgAAAA==.',
Iv='Ivincentl:BAAANQADCgUIBQAAAA==.',
Ix='Ixgangrxi:BAAANQADCgQIBAAAAA==.',
Ja='Jackassmcgee:BAAANQADCgEIAQAAAA==.Jackiep:BAAANQAECgQIAgAAAA==.Jadethunder:BAAANQADCgEIAQABNQAECgQIBwAKAAAAAA==.Jake:BAAANQAECgEIAQAAAA==.Jalana:BAAANQAECgEIAQAAAA==.Jankie:BAABNQAECn8aAAIdAAgKFB04IgCGAgAdAAgKFB04IgCGAgAAAA==.Jarnar:BAAANQAECgQIBAAAAA==.Jaxsin:BAAANQADCgEIAQAAAA==.',
Je='Jearemy:BAAANQADCgEIAQAAAA==.Jekster:BAAANQADCgEIAQAAAA==.Jerva:BAAANQAECggIEgABNQAFFAQICAALAAkVAA==.',
Ji='Jingburger:BAABNQAECn8gAAIDAAgKMxLAIQDSAQADAAgKMxLAIQDSAQABNQAECggIJgATAKgUAA==.Jinnosuke:BAAANQAECgQICgAAAA==.',
Jo='Joecelin:BAAANQAECgMIAwAAAA==.Johhnyp:BAAANQAFFAIIBAAAAA==.Johnathanwow:BAAANQAECgQJBwAAAA==.Johnnytotem:BAABNQAECn8dAAMPAAkKchhnQQBtAgAPAAkKchhnQQBtAgALAAcKfAOkuQD0AAABNQAFFAIIBAAKAAAAAA==.Jonastus:BAAANQADCgQIBAAAAA==.Jonermar:BAAANQAECgcIBwAAAA==.',
Ju='Judgemental:BAAANQADCgUIBgAAAA==.Jurbil:BAAANQADCggICAAAAA==.Justicé:BAAANQAECgQIBgAAAA==.',
Jy='Jykyl:BAABNQAECn8nAAMcAAgKDBisCwBtAgAcAAgKDBisCwBtAgASAAIKChiDRwCJAAAAAA==.',
['Jê']='Jêkyl:BAAANQADCgEIAQAAAA==.',
Ka='Kaidoazure:BAAANQAECgMIBQABNQAECgUIBwAKAAAAAA==.Kaipod:BAAANQAECgUJCgAAAA==.Kanrok:BAABNQAFFH8HAAILAAQKgxqzDgBdAQALAAQKgxqzDgBdAQAAAA==.Kaorrii:BAAANQAECgYICQAAAA==.Karlaia:BAAANQADCgEIAQAAAA==.Kattána:BAAANQAECgUIBwABNQAECgcIHAAEAK4SAA==.Kauthoon:BAAANQADCgQJBwAAAA==.Kaykotta:BAAANQADCgYIFgAAAA==.Kazademon:BAABNQAECn8mAAIOAAgKnxHnJwABAgAOAAgKnxHnJwABAgAAAA==.Kazmo:BAABNQAECn8iAAIMAAcK/RW/CQDhAQAMAAcK/RW/CQDhAQAAAA==.',
Ke='Kegheimer:BAAANQAECgIIAgABNQAECggIGgAcAEkdAA==.Keigis:BAAANQAECgMIBgAAAA==.Kelko:BAAANQADCgUIBQAAAA==.Kensington:BAAANQAECgUICgABNQAECgkJLwAHAB0jAA==.Keyalovar:BAABNQAECn+QAQIgAAgKBSdUBACqAwAgAAgKBSdUBACqAwAAAA==.Keìra:BAAANQADCgYIBwAAAA==.',
Kh='Khalgon:BAAANQADCggICAABNQAECggIAgAKAAAAAA==.',
Ki='Kimbecky:BAAANQADCgQJBQAAAA==.Kimchii:BAAANQAECgQIBgAAAA==.Kiritoo:BAAANQABCgQIBAAAAA==.Kishukae:BAABNQAECn8pAAIHAAgKgiRGDABPAwAHAAgKgiRGDABPAwAAAA==.Kishukun:BAAANQADCgYIBgABNQAECggIKQAHAIIkAA==.Kislosladkiy:BAAANQAECggIEAAAAA==.',
Kl='Klassik:BAAANQAECgUIDAAAAA==.',
Kn='Knitbeaniex:BAAANQAECgEIAQABNQAECgEIAgAKAAAAAA==.Knobsnob:BAABNQAECn8sAAQjAAkKQCJMBgAqAgAgAAgKyiCOIwDcAgAjAAYKViFMBgAqAgAJAAIKuwfjYgBvAAAAAA==.',
Kr='Kragden:BAAANQAECgQIBAABNQAECggIGgAcAEkdAA==.Krasius:BAAANQAECgEIAQAAAA==.Kriztina:BAAANQAECgUICAAAAA==.Krizu:BAAANQADCggIDgAAAA==.Kronkk:BAAANQAECgQIBAAAAA==.Kropie:BAABNQAECn8aAAIBAAgKqhL/vwACAgABAAgKqhL/vwACAgAAAA==.Krågden:BAAANQAECgUIBgABNQAECggIGgAcAEkdAA==.',
Ku='Kunfuzion:BAAANQAECgYIEgABNQAECgUIDAAKAAAAAA==.',
Ky='Kynga:BAAANQADCgUIBwABNQAECgIIAwAKAAAAAA==.Kynrinola:BAAANQABCgIIAgAAAA==.',
La='Ladrian:BAABNQAECn8bAAQUAAkKMBHwngCUAQAUAAcKiBDwngCUAQAVAAIKMguEXwBlAAAMAAEK7RvFJQBUAAAAAA==.Landoresh:BAAANQAECgMIBwAAAA==.Langers:BAAANQADCgEIAQAAAA==.Larabee:BAAANQADCgQIBAAAAA==.Larenieth:BAAANQAECgEIAQAAAA==.Larrykpinga:BAAANQAECgYIDAAAAA==.Larüd:BAABNQAECn8lAAILAAkKvhqCKQC7AgALAAkKvhqCKQC7AgAAAA==.Lasmon:BAABNQAECn8uAAIUAAgKaRCffgDlAQAUAAgKaRCffgDlAQAAAA==.',
Le='Legallyblind:BAABNQAECn8nAAIZAAkK3CT8AAC4AwAZAAkK3CT8AAC4AwAAAA==.Legit:BAAANQAECgMIBAAAAA==.',
Li='Lightblessed:BAAANQADCgcJBwABNQAECgkJHAANAOkVAA==.Lightsauce:BAAANQAECgQIBAAAAA==.Lightsmisery:BAAANQADCgYIDAAAAA==.Lillithx:BAAANQAECgMJAwAAAA==.Lillucy:BAAANQAECgcIBwAAAA==.Lilpa:BAAANQAECgUIBQABNQAECggIJgATAKgUAA==.Lilpä:BAAANQAECgcIDQABNQAECggIJgATAKgUAA==.Lindarenne:BAAANQADCgUIBQAAAA==.Lindree:BAAANQAECgcIEgAAAA==.Lineria:BAAANQADCgEIAQAAAA==.Liquidfire:BAAANQADCgYIBgAAAA==.Lirang:BAAANQAECgYIDQAAAA==.Littlewashu:BAAANQABCgUIBwAAAA==.Livlife:BAAANQAECgcICAABNQAECgkJFQAhAIEYAA==.Lizardfistin:BAACNQAFFH8eAAMIAAcK1iREAADVAgAIAAcK1iREAADVAgAkAAUK3x4pBACeAQA1AAQKfyMABAgACQqNJR4EAFwDAAgACQqNJR4EAFwDACQAAQoXIM4gAE0AACUAAQqKDcxMADgAAAAA.',
Lo='Loads:BAAANQAECggIBAAAAA==.Lockñlol:BAAANQABCgQIBAAAAA==.Logilock:BAAANQADCgQIAgAAAA==.Loni:BAAANQAECgQIDgAAAA==.Loonaimp:BAAANQAECgMJBQAAAA==.Lorthos:BAAANQABCgIIAgAAAA==.Lotús:BAABNQAECn8uAAMmAAkKwyTzDAALAwAmAAgKbCTzDAALAwAGAAIKLSaTEwHVAAAAAA==.',
Lu='Lucithalle:BAAANQADCgYIBgAAAA==.Lumenox:BAACNQAFFH8GAAIDAAMKDgsZCgCmAAADAAMKDgsZCgCmAAA1AAQKfzcAAwMACQrQHMYJAP4CAAMACQrQHMYJAP4CAAIAAQp+AmnEASIAAAAA.Luminarria:BAABNQAECn8XAAIXAAcKwwmFvwB5AQAXAAcKwwmFvwB5AQAAAA==.Luminisong:BAABNQAECn8YAAIBAAcKfgv27wCnAQABAAcKfgv27wCnAQAAAA==.Lupomic:BAAANQAECgQICQAAAA==.Lushice:BAAANQABCgIIAgAAAA==.',
Ma='Maeivalla:BAABNQAECn8lAAIgAAkKZxShTAA8AgAgAAkKZxShTAA8AgAAAA==.Magdaliana:BAABNQAECn9sAAImAAgK5CVZBQB6AwAmAAgK5CVZBQB6AwAAAA==.Mageler:BAABNQAECn8dAAMBAAkKXRflrQAlAgABAAgKvhflrQAlAgANAAEKGBU1PwBEAAAAAA==.Magicpurro:BAABNQAECn8WAAIBAAkKOSN/IQBVAwABAAkKOSN/IQBVAwABNQAFFAcIHgAIANYkAA==.Maiajayde:BAAANQABCgIIAgAAAA==.Malicebane:BAAANQADCgQIBAAAAA==.Mallory:BAAANQAECggICwAAAA==.Malma:BAAANQADCgYIBgAAAA==.Mancane:BAABNQAECn8wAAIBAAkKUh7tVgDSAgABAAkKUh7tVgDSAgAAAA==.Manstyle:BAAANQAECggICAAAAA==.Margolis:BAAANQADCggICgABNQAFFAgIFAAUAHMiAA==.Margrathwin:BAABNQAECn8YAAIPAAgKrBBgcQDIAQAPAAgKrBBgcQDIAQAAAA==.Mari:BAAANQAECgEIAQAAAA==.Marxman:BAABNQAECn8WAAMmAAkK2hDVIwAsAgAmAAkK2hDVIwAsAgAGAAEK8AlkSwFDAAABNQAFFAYIFQAmAMgYAA==.Maseratix:BAAANQAECgMIBAAAAA==.Mask:BAAANQADCgUIBQAAAA==.Masokhist:BAAANQABCggIEgAAAA==.Mauchs:BAAANQADCgUICQAAAA==.Maxthegreat:BAAANQABCgYIBgAAAA==.',
Me='Meedar:BAAANQAECgcIEgAAAA==.Meganite:BAAANQADCgYIIAAAAA==.Melaniatrump:BAAANQADCgEIAQAAAA==.Meningitis:BAAANQAECgEIAQABNQABCggICAAKAAAAAA==.Metara:BAAANQAECgIIAgAAAA==.',
Mi='Miahas:BAAANQADCgMIAwAAAA==.Mikecoxwoll:BAABNQAECn8pAAMdAAgKkRW9MwAKAgAdAAgKkRW9MwAKAgAOAAMK3QFIYwBWAAAAAA==.Milkmountain:BAAANQADCgIIAwAAAA==.Milkymoo:BAAANQADCgcIDAAAAA==.Minalina:BAAANQAECggIEwAAAA==.Minalinapr:BAAANQAECggIDQAAAA==.Minalinaria:BAAANQAECggIDwAAAA==.Mindedz:BAABNQAECn8rAAIPAAkKZhthMwCoAgAPAAkKZhthMwCoAgAAAA==.Minnow:BAABNQAECn8kAAIUAAgK8wqElwCmAQAUAAgK8wqElwCmAQAAAA==.Miren:BAABNQAECn89AAILAAkK4SEaCwBmAwALAAkK4SEaCwBmAwAAAA==.Mirrorjade:BAAANQAECgYIAgABNQAECggIFgAMAN4mAA==.Mittsmitts:BAAANQAECgUIDgAAAA==.',
Mo='Mochiberry:BAAANQAECggIAgAAAA==.Moistbuns:BAABNQAECn8VAAMhAAcKGhB7MgCCAQAhAAcKGhB7MgCCAQAbAAEKkgGOwAAfAAAAAA==.Molatova:BAABNQAECn8cAAIGAAgKMhebYwBMAgAGAAgKMhebYwBMAgAAAA==.Moozart:BAAANQAECgMIBQABNQAECgkJKgAdABgaAA==.Mooze:BAAANQAECgQIBAAAAA==.Morgiana:BAAANQAECgQICgAAAA==.Morigann:BAAANQAECgIIAgAAAA==.Mortiferia:BAABNQAECn80AAIgAAkKXSHTEgAzAwAgAAkKXSHTEgAzAwAAAA==.Mortzx:BAAANQAECgQIBAAAAA==.Motown:BAACNQAFFH8GAAQUAAMKNheMKgCuAAAUAAIKNheMKgCuAAAMAAEKAACcDABMAAAVAAEKJAorHwBKAAA1AAQKfyQABAwACQpJIsQBACwDAAwACQoqIcQBACwDABUABQoWHxIUAM4BABQABAqdFhTDAEABAAAA.',
Mu='Mundane:BAAANQADCggICAAAAA==.Muyo:BAAANQADCgEIAQAAAA==.Muzzlefaulf:BAAANQABCgIIAgAAAA==.',
Mw='Mwooq:BAAANQADCgYICAAAAA==.',
My='Mystics:BAABNQAECn8vAAInAAkKeR89BQA2AwAnAAkKeR89BQA2AwAAAA==.Mystiklight:BAAANQADCgUIBQABNQAECgQIBwAKAAAAAA==.Mythomagic:BAABNQAECn8sAAIBAAkKcRp4XQDFAgABAAkKcRp4XQDFAgAAAA==.',
Na='Naebchi:BAAANQADCgUIBQAAAA==.Nahjiky:BAAANQADCgYIEQAAAA==.Naissaia:BAAANQAECgMIAwAAAA==.Nakotak:BAAANQABCgQICAAAAA==.Nanalady:BAAANQADCggICAAAAA==.Nastyjob:BAAANQAECgYIDgAAAA==.Natendo:BAAANQAECggIBQAAAA==.Nazgar:BAAANQADCgUJBQAAAA==.',
Ne='Necronips:BAAANQADCgIIAgAAAA==.Neurosis:BAAANQADCggIIwAAAA==.Nezzthena:BAAANQADCgEIAQAAAA==.',
Ni='Niari:BAAANQAECgYICgAAAA==.Nibelung:BAABNQAECn8kAAMbAAgK5yMnGgD1AgAbAAgK5yMnGgD1AgAhAAEK2x8AAAAAAAAAAA==.Nikale:BAABNQAECn8aAAIcAAgKSR3CCgCGAgAcAAgKSR3CCgCGAgAAAA==.',
No='Nordy:BAAANQAECgUICwAAAA==.Normadin:BAABNQAECn8hAAQCAAgK+BOGowDUAQACAAgK+BOGowDUAQADAAcKogVoPgD/AAAEAAIK0greBAFoAAAAAA==.Norsefolk:BAAANQADCgIIAgAAAA==.Norseroch:BAAANQADCgYJCgABNQADCgIIAgAKAAAAAA==.',
Nv='Nvd:BAABNQAECn8cAAMOAAkKBx6HGwB4AgAOAAkKJR2HGwB4AgAdAAUKrRqARACcAQABNQAFFAEIAQAKAAAAAA==.',
Ny='Nyan:BAABNQAECn8YAAIcAAkKVRicBwDhAgAcAAkKVRicBwDhAgABNQAECgkJNwAEANcmAA==.Nysonnia:BAAANQAECgYIEwABNQAECgkJNwAEANcmAA==.',
Ob='Obsidianfire:BAAANQADCgQIBAABNQAECgQIBwAKAAAAAA==.',
Od='Odonn:BAAANQAECgMIAwAAAA==.Odìnsôn:BAAANQADCggIIAAAAA==.',
Om='Omegafortswl:BAAANQADCgcIHQAAAA==.Omeni:BAAANQAECgQICQAAAA==.',
On='Oneshockiboi:BAAANQADCgMIAwAAAA==.Onewish:BAAANQADCgIIAgAAAA==.',
Oo='Oogi:BAAANQAECgIIAwAAAA==.Oogiie:BAAANQAECgUICAAAAA==.',
Or='Orbits:BAAANQAECgUIBAAAAA==.Oric:BAABNQAECn83AAIEAAkK1yYVAAALBAAEAAkK1yYVAAALBAAAAA==.',
Os='Oscargrouch:BAAANQAECggIDQABNQAECggIEAAKAAAAAA==.',
Pa='Paledeath:BAAANQAECgEIAQABNQAECgQIBgAKAAAAAA==.Pallverize:BAAANQADCggICAAAAA==.Pannmann:BAAANQAECgcIEgAAAA==.Panzerhunt:BAAANQAECggIDQABNQAECgkJKAACAM8dAA==.Panzerpala:BAABNQAECn8oAAICAAkKzx3DQwDGAgACAAkKzx3DQwDGAgAAAA==.Panzersham:BAAANQAECggIEQABNQAECgkJKAACAM8dAA==.Paperdaen:BAABNQAECn8WAAIEAAgKNBZ6TQAxAgAEAAgKNBZ6TQAxAgAAAA==.Papertanuon:BAAANQABCgQIBAABNQAECggIFgAEADQWAA==.Parkle:BAAANQADCggIHgAAAA==.Pastore:BAABNQAECn8eAAIbAAkKvguNQQDuAQAbAAkKvguNQQDuAQAAAA==.',
Pe='Pelee:BAAANQABCgIIAgAAAA==.Pelos:BAAANQADCgEIAQAAAA==.Peonmè:BAAANQAECgMIBAAAAA==.',
Pf='Pfeffernusse:BAACNQAFFH8VAAMmAAYKyBhbCwCEAQAmAAUKvB5bCwCEAQAGAAIK7AbXIgClAAA1AAQKfx0AAiYACQqcICccAG8CACYACQqcICccAG8CAAAA.',
Ph='Phalluic:BAAANQADCggIDgAAAA==.Philmage:BAAANQAECggIDAABNQAECgkJHQAJADAdAA==.Philpriest:BAABNQAECn8dAAMJAAkKMB02FADBAgAJAAkKMB02FADBAgAgAAMKLBItzAC4AAAAAA==.',
Pl='Plagued:BAAANQAECgQIBwABNQABCgIJAgAKAAAAAA==.Plagueis:BAAANQADCgMIAwAAAA==.',
Po='Pochaccob:BAACNQAFFH8GAAIhAAMKbw7KDADeAAAhAAMKbw7KDADeAAA1AAQKfyEAAiEACQqeGjkSALsCACEACQqeGjkSALsCAAAA.Pokeysticks:BAAANQAECgMIBQAAAA==.Poncia:BAABNQAECn8gAAILAAgKahpwQwBQAgALAAgKahpwQwBQAgAAAA==.',
Pr='Pragmax:BAABNQAECn8aAAIbAAkKuBFmMwBHAgAbAAkKuBFmMwBHAgAAAA==.Praynation:BAAANQAECgIIAwAAAA==.Prediction:BAAANQAECgEIAgAAAA==.Pressbuttons:BAAANQAECggIDQABNQAECggIFgAFAEMjAA==.',
Pu='Puffcodan:BAAANQAECgEIAwAAAA==.Pugcival:BAAANQADCgUIBQAAAA==.Punîshër:BAAANQAECgUIBwAAAA==.Puppenance:BAAANQADCgUIBQAAAA==.Purgatoriwlf:BAABNQAECn8kAAMGAAkKSiBDNQDJAgAGAAkKSiBDNQDJAgAmAAcKHRLeMwCrAQAAAA==.Purplehayz:BAAANQADCgYICwAAAA==.',
Py='Pyrogale:BAAANQAECgUICAAAAA==.',
['Pó']='Póe:BAAANQAFFAEIAQABNQAFFAMIBgAHAJALAA==.',
Ql='Qlimax:BAAANQAECgEJAQAAAA==.',
Qu='Quadzilla:BAAANQAECgQICAAAAA==.Quem:BAAANQAECgcIBQABNQAECggIFgAMAN4mAA==.',
Ra='Rachet:BAAANQADCgcIHAAAAA==.Ragnalock:BAAANQAECgQICQAAAA==.Ragnir:BAAANQAECgUIBwAAAA==.Rainbowtits:BAAANQAECgMIAwAAAA==.Raker:BAAANQABCgcIDAAAAA==.Rarh:BAAANQADCgYICQAAAA==.Rathlokor:BAAANQADCgMJAwAAAA==.Rathlore:BAAANQADCgUIBQAAAA==.Rathorn:BAAANQAECgUIDgAAAA==.Rawdawgan:BAAANQADCgYIBwAAAA==.Rawrbotz:BAAANQAECgIIAgAAAA==.Razeneth:BAAANQAECggIBgAAAA==.',
Re='Rebelj:BAAANQAECgIIAQAAAA==.Rebornqt:BAAANQADCgIIAgAAAA==.Reforsaken:BAABNQAECn8tAAInAAkK0RmTCwC6AgAnAAkK0RmTCwC6AgAAAA==.Regicespice:BAAANQAECgIIAgAAAA==.Relarian:BAABNQAECn8aAAImAAgKsQw0MQDAAQAmAAgKsQw0MQDAAQAAAA==.Releimus:BAAANQAECgcIDwAAAA==.Rentera:BAAANQADCggICAAAAA==.Revengeance:BAABNQAECn8vAAIDAAkK6xdRFABfAgADAAkK6xdRFABfAgAAAA==.',
Ri='Rihhzen:BAAANQAECgIIAgAAAA==.Ripnfade:BAAANQADCggIDwAAAA==.Riptide:BAAANQAECgIIAgAAAA==.Rissler:BAAANQADCgUICQAAAA==.Rithallie:BAAANQAECgQIBAAAAA==.',
Rm='Rmplstilskin:BAAANQAECgUIBAABNQAECgYICwAKAAAAAA==.',
Ro='Roanoke:BAAANQAECgQIBQAAAA==.Rocketsauce:BAAANQAECgUICgAAAA==.Romcrom:BAAANQAECgYICwAAAA==.Rommagicus:BAAANQADCggIDQABNQAECgYICwAKAAAAAA==.Rosalíe:BAAANQADCgQIBAAAAA==.Rougetoon:BAAANQADCggICAABNQAECgkJHQAEANwiAA==.Rouxnic:BAAANQADCgEIAQAAAA==.Roxen:BAABNQAECn8pAAIPAAkKUxxxJQDsAgAPAAkKUxxxJQDsAgAAAA==.',
Ru='Rubyhart:BAAANQADCgYIBgAAAA==.Rukenji:BAACNQAFFH8RAAIgAAYKthZsCAD/AQAgAAYKthZsCAD/AQA1AAQKfysAAyAACQrGIN0eAPICACAACQqMIN0eAPICACMABArLHPIRAAYBAAAA.Runehulk:BAAANQABCgQIBAAAAA==.Runíc:BAAANQADCgEIAQAAAA==.Rustycooch:BAAANQADCgEIAQABNQAECgkJMgALAHEkAA==.',
Ry='Ryuunosuke:BAABNQAECn8vAAIlAAkKdBMVGAA4AgAlAAkKdBMVGAA4AgAAAA==.',
Sa='Sabers:BAAANQAECgcJDgAAAA==.Sabriinaa:BAAANQABCgMIBAAAAA==.Sabrinachi:BAAANQABCgIIAgAAAA==.Sabrinadin:BAAANQABCgQIBQAAAA==.Sadako:BAAANQAECgEIAQAAAA==.Sakkraa:BAACNQAFFH8HAAIMAAMKaRBlAgDpAAAMAAMKaRBlAgDpAAA1AAQKf0kAAwwACQpyINMAAH0DAAwACQpyINMAAH0DABQAAQoAAFI9ATUAAAAA.Salla:BAAANQAECgMIAwAAAA==.Sandrawolf:BAAANQAECggICAABNQAECgkJJAAGAEogAA==.Sannea:BAAANQADCgYIBwAAAA==.Saponite:BAAANQADCgIIAgAAAA==.Sarumon:BAABNQAECn8hAAQVAAgKxRv9GwCMAQAUAAYK5xZqoACQAQAVAAUKAR79GwCMAQAMAAEKyBVnKABIAAAAAA==.',
Sc='Schwimdy:BAAANQAECgUIDQAAAA==.Scrappey:BAAANQADCgYIBgAAAA==.',
Se='Secondlife:BAAANQADCgQIBAAAAA==.Secwolf:BAAANQAECggIEAABNQAECgkJJAAGAEogAA==.Seeingeyedog:BAABNQAECn8iAAILAAgKRhuARgBEAgALAAgKRhuARgBEAgAAAA==.Seeya:BAAANQAECgIIAgAAAA==.Seiracon:BAAANQADCgEIAQAAAA==.Seraphicfrog:BAAANQADCgMIAwAAAA==.Sevenseconds:BAAANQADCgcIDQAAAA==.Sewerclam:BAAANQADCgQIBAAAAA==.',
Sh='Shadowscythe:BAAANQAECgYIDgAAAA==.Shadowzar:BAAANQAECgMIBQABNQAECgYIDgAKAAAAAA==.Shampann:BAAANQADCgEIAQAAAA==.Shanablack:BAAANQADCgUIBQAAAA==.Sharish:BAAANQABCggIBwAAAA==.Shaundel:BAABNQAECn89AAILAAgKzRpHRgBFAgALAAgKzRpHRgBFAgAAAA==.Shavocadoos:BAAANQADCggICAAAAA==.Shestrain:BAAANQADCgUIBgAAAA==.Shezmu:BAABNQAECn8jAAIHAAkKbiHlEAAkAwAHAAkKbiHlEAAkAwAAAA==.Shiftinman:BAAANQADCgMIAwAAAA==.Shiftintime:BAAANQADCgQIBAABNQAFFAQIDAAdACkgAA==.Shlorp:BAAANQADCgIIAgAAAA==.Shoopa:BAAANQAECgQICgAAAA==.Shoopah:BAABNQAECn8jAAIBAAkK0BvxQQABAwABAAkK0BvxQQABAwAAAA==.Shoopsmash:BAAANQAECgcIBwAAAA==.Short:BAABNQAECn8tAAInAAgKWQ+YGwD2AQAnAAgKWQ+YGwD2AQAAAA==.Shunned:BAAANQAECgMIAwAAAA==.Shyok:BAAANQADCgEJAQAAAA==.Shädøwreeper:BAAANQAECgMIAwAAAA==.',
Si='Sicuro:BAAANQAECgQIBAAAAA==.Siduiss:BAAANQAECgQIBgAAAA==.Silvrfoxx:BAAANQAECgYICwAAAA==.Silvänus:BAABNQAECn8vAAMhAAkKoSGOBwBIAwAhAAkKoSGOBwBIAwAbAAEKIwbYsQAwAAAAAA==.Simsha:BAABNQAECn8VAAMLAAQK1xqEnwAzAQALAAQK1xqEnwAzAQAPAAQKRAjK6QC9AAAAAA==.',
Sk='Skinnylejend:BAABNQAECn8eAAMJAAkK1BfrGQB8AgAJAAkK1BfrGQB8AgAgAAIKfhGb2wCNAAAAAA==.Skipperty:BAAANQAECggIDAAAAA==.Skizzy:BAAANQADCgMIAwAAAA==.Skmoon:BAAANQADCgIIAgAAAA==.Skãr:BAAANQADCgYIBgAAAA==.',
Sl='Sloimmortal:BAAANQABCgQIBAAAAA==.',
Sm='Smiley:BAABNQAECn8aAAIFAAgKlxgRJQD3AQAFAAgKlxgRJQD3AQAAAA==.Smokedmeats:BAAANQADCgIIAgAAAA==.',
Sn='Snac:BAAANQAECgIJAwAAAA==.Snackrifice:BAAANQAECgMIAwAAAA==.Snacs:BAAANQADCgMIAwAAAA==.Sndancekd:BAABNQAECn8fAAICAAgKbSGKNQD1AgACAAgKbSGKNQD1AgAAAA==.Sneakybeanz:BAAANQAECgUICwAAAA==.Snorkle:BAAANQAECggICQAAAA==.',
So='Sollan:BAAANQABCgUIBAAAAA==.Someperson:BAAANQAECgYIBwAAAA==.Somoner:BAABNQAECn8zAAMVAAkK0SJCAQCHAwAVAAkK0SJCAQCHAwAMAAEKAAAALwA3AAAAAA==.Sompal:BAAANQAECgYIDAABNQAECgkJMwAVANEiAA==.',
Sp='Sparklz:BAAANQADCgcIBwAAAA==.Sparksizzle:BAABNQAECn8hAAMBAAkK4BLNowA4AgABAAkK4BLNowA4AgAfAAMKpQVpCACWAAAAAA==.Spiseyy:BAAANQADCgYIBgAAAA==.Spitfel:BAABNQAECn8YAAQVAAkKXyAkCAB8AgAVAAkK7xckCAB8AgAUAAUK/h7UuwBQAQAMAAEKSRzQKQBEAAABNQAFFAcIFgAbAJUcAA==.Spitfirex:BAACNQAFFH8WAAIbAAcKlRzlBABVAgAbAAcKlRzlBABVAgA1AAQKfxYAAxsACAo1Gt41ADgCABsACAr2GN41ADgCABwAAgoTFzguAJoAAAAA.Spreadshecat:BAABNQAECn8VAAIBAAgKNxEYzADrAQABAAgKNxEYzADrAQABNQAECgkJHwAEABkcAA==.',
St='Standsinfire:BAAANQADCgcIBwAAAA==.Starofeos:BAAANQADCgUIBQAAAA==.Stoix:BAAANQADCgUIAgAAAA==.Stompymunk:BAAANQAECgQIBgAAAA==.Stopzîlla:BAABNQAECn8oAAInAAgK7xSjFgApAgAnAAgK7xSjFgApAgAAAA==.Strûmpet:BAAANQAECgQIBAAAAA==.',
Su='Sugrdadi:BAAANQAECgMIBQAAAA==.',
Sy='Syleine:BAAANQAECggICAAAAA==.Sylmar:BAAANQAECgQICgAAAA==.Syndora:BAABNQAECn8pAAIhAAgKpB8KEQDIAgAhAAgKpB8KEQDIAgAAAA==.',
Ta='Tacoboss:BAAANQAECgEIAQAAAA==.Taerun:BAAANQAECgIIBQAAAA==.Tahu:BAABNQAECn8fAAMbAAkKUSDPEgAvAwAbAAkKUSDPEgAvAwAhAAIKAwwpaQBaAAAAAA==.Takal:BAAANQADCgYICwAAAA==.Talorn:BAAANQADCgUIBwAAAA==.Talreth:BAAANQAECgYIEwAAAA==.Tappnlock:BAAANQABCgIIAgABNQAECggIJAANADEUAA==.',
Te='Teake:BAAANQAECgIIAgAAAA==.Teddymoove:BAAANQADCgYIBgAAAA==.Teddyruxpin:BAAANQADCgcIBwAAAA==.Teddytotems:BAABNQAECn8mAAIPAAgK8xPGVwAZAgAPAAgK8xPGVwAZAgAAAA==.Teessel:BAAANQADCgcIDQAAAA==.Telemarketer:BAAANQAECggIDgAAAA==.Tempted:BAAANQAECgMIAwAAAA==.Tenebrisol:BAAANQAECgQIBAAAAA==.Ternal:BAAANQAECgQIBgAAAA==.Terrato:BAAANQAECgEIAQAAAA==.Terrorize:BAABNQAECn8WAAMUAAgKBCIWFwAqAwAUAAgKBCIWFwAqAwAVAAEKhyAZZgBVAAAAAA==.Terrorley:BAAANQAECgYIDQAAAA==.Terrous:BAACNQAFFH8OAAMeAAUKYQpeEAAAAQAeAAQKYQpeEAAAAQAHAAEKAABcQAAOAAA1AAQKfyYAAh4ACQpuG2oyAF8CAB4ACQpuG2oyAF8CAAAA.Tetranutra:BAAANQADCgQIBAAAAA==.',
Th='Thakur:BAABNQAECn8dAAMEAAkKWQwAZwDfAQAEAAkKWQwAZwDfAQACAAIKlAFfpQExAAAAAA==.Thatgùy:BAAANQAECgIIAgAAAA==.Theoslight:BAAANQAECgUIDwAAAA==.Thepain:BAAANQADCgQIBAAAAA==.Thepetmaster:BAAANQADCgUICgABNQAECgQIBgAKAAAAAA==.Thiccaxe:BAAANQAECgUICQAAAA==.Thighler:BAAANQAECgcIEQAAAA==.Thordenson:BAAANQABCgIIAgAAAA==.Thrandorinil:BAAANQADCgQIBgAAAA==.Thraxia:BAAANQABCgQIBAAAAA==.Threxon:BAABNQAECn8dAAIdAAkK4xrKHACwAgAdAAkK4xrKHACwAgAAAA==.Thrine:BAAANQAECgQIBQAAAA==.Thunderfire:BAAANQAECgQIBwAAAA==.',
Ti='Tiaway:BAAANQABCggICAAAAA==.Timepally:BAAANQADCgYIBgAAAA==.Tinytimothy:BAAANQADCgIIAgAAAA==.',
To='Tokajok:BAACNQAFFH8IAAIZAAQK9wZGAwDPAAAZAAQK9wZGAwDPAAA1AAQKfzEAAw4ACQokHq8WAKgCAA4ACArVHa8WAKgCABkAAwoeFxwiAK0AAAAA.Tokash:BAAANQADCggICQABNQAFFAQICAAZAPcGAA==.Tokashi:BAABNQAECn8XAAIHAAkKsBAqSgDMAQAHAAkKsBAqSgDMAQABNQAFFAQICAAZAPcGAA==.Tokeadin:BAABNQAECn8hAAIEAAcKuhRlcwC6AQAEAAcKuhRlcwC6AQAAAA==.Tokzillu:BAAANQADCgUIBQAAAA==.Tomaki:BAAANQADCgcJCgAAAA==.Topazd:BAAANQAECgQIBAAAAA==.Toriimage:BAAANQAECgEIAQABNQAECgUIDgAKAAAAAA==.Toriisneaky:BAAANQAECgUIDgAAAA==.Toughluck:BAAANQAECgQICAAAAA==.',
Tr='Trackervalk:BAAANQADCgUIDAAAAA==.Traellissa:BAAANQAECgMIBgAAAA==.Treeady:BAAANQAECgMJAgAAAA==.Trenbölöne:BAABNQAECn8rAAIXAAkKtRw5PADUAgAXAAkKtRw5PADUAgAAAA==.Treyrin:BAABNQAECn8iAAICAAcKch9pbgBPAgACAAcKch9pbgBPAgAAAA==.Tritonia:BAAANQAECggICgAAAA==.Tritonian:BAACNQAFFH8ZAAIDAAcK3yKMAADKAgADAAcK3yKMAADKAgA1AAQKfywAAgMACQq+JtYAAOIDAAMACQq+JtYAAOIDAAAA.Trixio:BAABNQAECn8VAAITAAgKAyE+LwAhAgATAAgKAyE+LwAhAgAAAA==.Trollmother:BAAANQADCggICAAAAA==.Trolloutcast:BAAANQAECgQICAABNQAFFAgIFAAUAHMiAA==.Tröut:BAAANQAECgQIBAAAAA==.',
Tu='Turtle:BAACNQAFFH8WAAIEAAYKPBJeBwDtAQAEAAYKPBJeBwDtAQA1AAQKfzUAAgQACQohHX4fAPACAAQACQohHX4fAPACAAAA.',
Tw='Twelph:BAAANQAECgIIBAABNQAECgQICAAKAAAAAA==.Twizzlestick:BAAANQABCgUIBQAAAA==.',
Ty='Tyluwu:BAABNQAECn8hAAIFAAgK9x5zFQCkAgAFAAgK9x5zFQCkAgAAAA==.Tyranis:BAAANQAECgQIBgAAAA==.Tyzz:BAAANQAECgEIAgAAAA==.',
['Tì']='Tìtân:BAAANQADCgcIBwAAAA==.',
['Tÿ']='Tÿ:BAABNQAECn8eAAMGAAkKzCDOFABJAwAGAAgKwyTOFABJAwAmAAIK/wgxdgBfAAAAAA==.',
Ud='Uddercleanse:BAAANQADCgYIBgABNQAECgkJLAAjAEAiAA==.',
Um='Umbrianna:BAABNQAECn8tAAIdAAgKvgbFSwBsAQAdAAgKvgbFSwBsAQAAAA==.',
Un='Undeadashyra:BAAANQADCgYIBgAAAA==.Unstablemagi:BAAANQADCgYIBgAAAA==.',
Uv='Uvulabean:BAAANQAECgUICwAAAA==.',
Uw='Uwuclapmexd:BAAANQADCgMJAwAAAA==.Uwuhunterxd:BAACNQAFFH8FAAImAAIK3wVXHwBzAAAmAAIK3wVXHwBzAAA1AAQKfy4AAyYACQoQGyUWAKgCACYACQp3GiUWAKgCAAYAAQpeIrc+AVoAAAAA.',
Va='Vaelowyn:BAAANQAECgYICwAAAA==.Vaelthyr:BAAANQADCggIEAABNQAFFAMIBgADAA4LAA==.Vakar:BAAANQAECgUIEQAAAA==.Valck:BAABNQAECn8WAAMMAAgK3ibHAACBAwAUAAgKlSboBgCVAwAMAAgK8SXHAACBAwAAAA==.Valkorath:BAAANQAECgUIBQAAAA==.Valkyriee:BAAANQADCgMIAwAAAA==.Varninn:BAAANQADCgcIEAAAAA==.Varonos:BAAANQAECggIDwAAAA==.Vasha:BAAANQAECgYIDgAAAA==.',
Ve='Ventee:BAAANQAECgUIEQAAAA==.Vergere:BAAANQAECgIIAwAAAA==.Veritass:BAAANQAECgIIAgAAAA==.Verymelon:BAAANQAECgEIAQAAAA==.',
Vi='Vincentv:BAAANQADCgYIBgAAAA==.Virtuositee:BAAANQAECgMIAwABNQAECgkJNQAHAH8XAA==.Vitadin:BAAANQAECgQICQAAAA==.',
Vo='Voidaddict:BAAANQAECgMIAwABNQAFFAcIHgAIANYkAA==.Voidseeker:BAAANQABCgMIAwAAAA==.',
Vr='Vraugashan:BAAANQAECgcICgAAAA==.Vrice:BAAANQADCgIIAgAAAA==.',
['Vá']='Váprak:BAAANQADCgcICAAAAA==.',
Wa='Walmage:BAAANQADCgYIBgAAAA==.Wannabe:BAAANQABCgUIBQABNQAECgkJHgAGAMwgAA==.Warbuck:BAAANQADCgUIBAAAAA==.Warlas:BAAANQAECgEIAQAAAA==.Warthog:BAAANQAECgYIBgAAAA==.',
We='Wesson:BAABNQAECn8eAAIoAAgKyx3hAwC+AgAoAAgKyx3hAwC+AgAAAA==.',
Wh='Whompie:BAAANQABCgEIAQAAAA==.',
Wi='Winning:BAABNQAECn8pAAIGAAkKqB3SJQD+AgAGAAkKqB3SJQD+AgAAAA==.Wireless:BAABNQAECn8wAAMTAAkKUhO8IwBlAgATAAkKUhO8IwBlAgAnAAcK1QcQKgBvAQAAAA==.',
Wo='Wokker:BAAANQADCggIFAAAAA==.',
Wq='Wqwq:BAAANQADCgEIAQAAAA==.',
Wu='Wuköng:BAAANQAECgYIEwAAAA==.',
Xa='Xau:BAAANQAECgYIBwAAAA==.',
Xe='Xeorc:BAAANQADCgcIBwAAAA==.Xeum:BAABNQAECn8lAAMgAAkKShj6MQCdAgAgAAkKShj6MQCdAgAJAAEKcQbYfQAsAAAAAA==.',
Xg='Xgirlfriend:BAAANQAECgQICwAAAA==.',
Xh='Xhar:BAABNQAECn8pAAIBAAkK/xOkiQBrAgABAAkK/xOkiQBrAgAAAA==.Xhyros:BAABNQAECn8sAAIIAAkKISKxAwBmAwAIAAkKISKxAwBmAwAAAA==.',
Xi='Xiahou:BAABNQAECn8qAAIBAAkK5iIQGgBtAwABAAkK5iIQGgBtAwAAAA==.',
Xo='Xoothette:BAAANQADCgcIBwABNQAFFAgIFAAUAHMiAA==.',
Ya='Yahnari:BAAANQADCgMIAwAAAA==.',
Ye='Yel:BAACNQAFFH8PAAIIAAYKjBhqAgD1AQAIAAYKjBhqAgD1AQA1AAQKfy0AAggACQpkJGkCAI4DAAgACQpkJGkCAI4DAAAA.',
Yu='Yuanfen:BAAANQAECgUIDgAAAA==.Yunaraz:BAAANQADCgEIAQAAAA==.Yungshrimpy:BAAANQADCgYIBgAAAA==.',
Za='Zaffira:BAAANQAECgYIEAAAAA==.Zamlen:BAABNQAECn8oAAIBAAgKrBYfjABmAgABAAgKrBYfjABmAgAAAA==.Zaq:BAABNQAECn8ZAAQaAAcKUwxNUwBbAQAaAAcKUwxNUwBbAQAHAAQKqwV4mQCmAAAeAAEKAACW3wAyAAAAAA==.Zaradissa:BAAANQAECggIBAAAAA==.Zargan:BAAANQAECgQIDAAAAA==.Zargstrike:BAAANQADCggIDQABNQAECgQIDAAKAAAAAA==.Zazie:BAABNQAECn8nAAIHAAkKAhecNgAtAgAHAAkKAhecNgAtAgAAAA==.',
Ze='Zedicuzz:BAABNQAECn8bAAIaAAcKvhHLSQCNAQAaAAcKvhHLSQCNAQAAAA==.Zeesala:BAAANQADCgUIBwABNQAECgkJNwAEANcmAA==.Zemms:BAAANQADCggICAAAAA==.',
Zi='Zinbad:BAAANQADCgYIBgAAAA==.Zippbang:BAAANQADCgEIAQAAAA==.Zithazar:BAAANQADCgIIAgAAAA==.Zivyrial:BAABNQAECn8ZAAIOAAkKDyEXEwDPAgAOAAkKDyEXEwDPAgAAAA==.',
Zo='Zowa:BAAANQAECgMIAwAAAA==.',
Zu='Zugzugzugzug:BAACNQAFFH8GAAIaAAUKTSCwAwDmAQAaAAUKTSCwAwDmAQA1AAQKfzIABBoACQp9JsYAAPADABoACQp9JsYAAPADAB4ABApaJBNdAJcBAAcAAwo4I8Z7AAYBAAAA.Zuken:BAAANQAECgQIBAAAAA==.Zuriki:BAAANQADCgMIAwAAAA==.',
['År']='Årdentmeta:BAAANQAECgQICQABNQAECgYIDgAKAAAAAA==.',
['Ñe']='Ñemo:BAABNQAECn8hAAMGAAgKByOSLgDfAgAGAAgKByOSLgDfAgAmAAMKVhBEaQCDAAAAAA==.',
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
