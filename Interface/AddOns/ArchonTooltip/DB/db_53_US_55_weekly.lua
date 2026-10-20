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

local lookup = {'Rogue-Assassination','Hunter-Marksmanship','DeathKnight-Frost','DeathKnight-Blood','Druid-Guardian','Mage-Frost','Paladin-Holy','Druid-Balance','Druid-Restoration','Warrior-Protection','Warrior-Arms','Paladin-Retribution','Monk-Mistweaver','DemonHunter-Devourer','Mage-Arcane','Hunter-BeastMastery','DeathKnight-Unholy','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Warrior-Fury','Monk-Windwalker','Rogue-Subtlety','Warlock-Affliction','DemonHunter-Havoc','Priest-Discipline','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','Priest-Holy','DemonHunter-Vengeance','Paladin-Protection','Monk-Brewmaster','Priest-Shadow',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abc:BAAANQADCgIIAgAAAA==.',
Ac='Acheniris:BAAANQAECgQIBQAAAA==.',
Ae='Aeviee:BAAANQADCgQJBAAAAA==.',
Ag='Agrippa:BAABNQAECn8dAAIBAAoKxw1VOQDvAQABAAoKxw1VOQDvAQAAAA==.',
Ah='Ahndhrez:BAAANQAECggIEAAAAA==.',
Ai='Aidric:BAAANQAECgYICQAAAA==.Airwavez:BAACNQAFFH8OAAICAAUKoxf9CwB/AQACAAUKoxf9CwB/AQA1AAQKfzMAAgIACgp4GuAXAJkCAAIACgp4GuAXAJkCAAAA.',
Ak='Akriel:BAAANQAECgcIDwAAAA==.',
Al='Albrecht:BAAANQAECgMIAwAAAA==.Aldeor:BAAANQAECgIIAgAAAA==.Altra:BAACNQAFFH8GAAIDAAIKCwRMCwBrAAADAAIKCwRMCwBrAAA1AAQKfykAAwMACgp0FE0uAC8CAAMACgp0FE0uAC8CAAQAAQoAAF3aACQAAAAA.Alumit:BAAANQAECgYJDwAAAA==.',
Am='Amoeta:BAABNQAECn8xAAIFAAoKGxtICwC4AgAFAAoKGxtICwC4AgAAAA==.',
An='Andor:BAAANQADCgYIDwAAAA==.Angelique:BAAANQAECgUIDwAAAA==.Angry:BAAANQADCgYICgAAAA==.Angryapples:BAAANQAECgQJBQAAAA==.Annihilation:BAAANQADCgUIBQAAAA==.',
Ap='Approved:BAAANQADCgYIBQAAAA==.',
Ar='Arconos:BAAANQADCgYIDAABNQAFFAYIFAAGAEkYAA==.Arcstorm:BAAANQAECgEIAQAAAA==.',
As='Ashguard:BAAANQADCgcIDAAAAA==.Asomyrh:BAABNQAECn8eAAIHAAkKOQ37aQDZAQAHAAkKOQ37aQDZAQAAAA==.',
Au='Aurial:BAAANQADCgMIAwAAAA==.Auriala:BAAANQAECgYICgAAAA==.',
Az='Azuriae:BAAANQAECgQIBAAAAA==.',
Ba='Babygirl:BAAANQAECgYICQAAAA==.Bananer:BAAANQAECgQICAAAAA==.Banonzarath:BAAANQADCggICAAAAA==.Barrysoetoro:BAAANQADCgcIDAAAAA==.Baulie:BAAANQAECgQIBAAAAA==.',
Be='Beefstick:BAAANQADCggIJgAAAA==.Bekroh:BAABNQAECn8YAAMIAAcKfhglSADKAQAIAAcKfhglSADKAQAJAAEKbASufAAlAAAAAA==.Bestt:BAAANQAECgQIBgAAAA==.',
Bi='Bigdaddyd:BAABNQAECn8fAAMKAAgKiRCgCgAGAQALAAcKeQzf2wA0AQAKAAcKkhGgCgAGAQAAAA==.Bigdonk:BAAANQADCggJCAAAAA==.Bigocagler:BAAANQADCggIFgAAAA==.Bioodlion:BAABNQAECn8mAAIMAAkKag4tvgCgAQAMAAkKag4tvgCgAQAAAA==.Bipolar:BAABNQAECn8gAAINAAgKWgWCDQD9AAANAAgKWgWCDQD9AAAAAA==.Bippysmasher:BAABNQAECn8iAAIOAAoKMBOcHwBSAgAOAAoKMBOcHwBSAgAAAA==.Bishmanistic:BAAANQAECgYIDQAAAA==.',
Bl='Blacblood:BAAANQAECgEIAQAAAA==.Blastemis:BAAANQAECgEIAgAAAA==.Blindweiss:BAAANQADCgcIBwABNQAFFAYIFAAGAEkYAA==.Blinkies:BAABNQAECn8XAAIPAAkKixo9hAB2AgAPAAkKixo9hAB2AgAAAA==.',
Bo='Bontao:BAACNQAFFH8QAAIQAAYKjBgbCgCpAQAQAAYKjBgbCgCpAQA1AAQKfy4AAhAACgqXH9A3AMMCABAACgqXH9A3AMMCAAAA.Bontaopanda:BAAANQADCgcIEwABNQAFFAYIEAAQAIwYAA==.Boomies:BAAANQADCgQJBAABNQAECgkJFwAPAIsaAA==.Borstenne:BAABNQAECn8kAAIRAAkK9iPhCgBkAwARAAkK9iPhCgBkAwAAAA==.Bosco:BAAANQADCgQIBAAAAA==.',
Br='Bresemage:BAAANQAECgQIBAABNQAFFAIIBAASAAAAAQ==.Bresepls:BAAANQAFFAIIBAAAAA==.Breseshh:BAABNQAECn8xAAMTAAkK5iPtCAB6AwATAAkK5iPtCAB6AwAUAAMKIBID2ADkAAABNQAFFAIIBAASAAAAAA==.Brickbeard:BAAANQAECgQIAwAAAA==.Brickbow:BAAANQADCgYIBgAAAA==.Brickette:BAAANQAECgcIDQABNQAFFAYIFQAHABsNAA==.Bricklicker:BAAANQAECgQIAwAAAA==.Bricksquad:BAAANQAECgcIDgAAAA==.Brickthrow:BAACNQAFFH8VAAIHAAYKGw1NDgB+AQAHAAYKGw1NDgB+AQA1AAQKfysAAwcACgqwH9AgAOsCAAcACgqwH9AgAOsCAAwAAQr5D3abAToAAAAA.Bringdapain:BAAANQAECgUIBQAAAA==.',
Bu='Budhistpalm:BAAANQAECgMIAwAAAA==.Burgerburn:BAAANQAECgMIBgAAAA==.',
By='Bytheway:BAAANQAECgYIDgAAAA==.',
['Bé']='Béstt:BAABNQAECn8fAAIUAAoKAxn2KgDUAgAUAAoKAxn2KgDUAgAAAA==.',
Ca='Cadilak:BAACNQAFFH8GAAIJAAIKUAsUCACDAAAJAAIKUAsUCACDAAA1AAQKfyoAAwkACgp8GUAXAIcCAAkACgp8GUAXAIcCAAgAAwoaD4qNAKAAAAAA.Caelesti:BAAANQAECgUICwAAAA==.Camlin:BAAANQADCggIDgAAAA==.Catrina:BAEANQAECggIAQABNQAECgoKKAAMAKMZAA==.',
Ch='Cheapshotjoe:BAAANQADCgEIAQAAAA==.Chelbur:BAAANQAECgIJAwAAAA==.Chowderhead:BAABNQAECn8hAAMVAAoKGxWTCQBgAgAVAAkKqROTCQBgAgAWAAQK+xb3+QDYAAAAAA==.',
Ci='Cileb:BAABNQAECn8hAAIPAAoKZB6qJwBDAwAPAAoKZB6qJwBDAwAAAA==.Civik:BAAANQAECgMIAwAAAA==.',
Co='Cocio:BAABNQAECn8dAAILAAcKdBS6nQDSAQALAAcKdBS6nQDSAQABNQAECgoKNQALAI4ZAA==.Conchsniffer:BAABNQAECn86AAMMAAoKtR9qLAAWAwAMAAoKtR9qLAAWAwAHAAEKPQFqPAEVAAAAAA==.Conrack:BAAANQADCggJCAAAAA==.Copperit:BAABNQAECn8dAAMEAAkKQyQ3CAC1AQAEAAkKQyQ3CAC1AQADAAEKQh8amwBdAAAAAA==.Cornburglar:BAABNQAECn81AAMLAAoKjhkDRgC4AgALAAoKKxkDRgC4AgAXAAIKziDYHwC+AAAAAA==.Corrona:BAEANQAECgMIAgABNQAECgoKKAAMAKMZAA==.Cowtaclysmic:BAAANQAECgYIBgAAAA==.',
Cr='Creatlach:BAAANQADCgYIBgABNQAFFAYIFgATAOMZAA==.Crime:BAABNQAECn8XAAIBAAkKqBn5AgAlAgABAAkKqBn5AgAlAgABNQAFFAIIBwAYANMeAA==.Crunchwrap:BAABNQAECn8UAAIIAAYK+ATtdwDrAAAIAAYK+ATtdwDrAAAAAA==.',
Ct='Cthul:BAAANQADCggICAAAAA==.',
Cu='Curseus:BAAANQADCgUIBQAAAA==.',
['Câ']='Câlisse:BAACNQAFFH8HAAIYAAIK0x5aBQC1AAAYAAIK0x5aBQC1AAA1AAQKfzwAAhgACgqeI7ADAJoDABgACgqeI7ADAJoDAAAA.',
Da='Daddiedk:BAABNQAECn8dAAIDAAcKlBrcPQDVAQADAAcKlBrcPQDVAQAAAA==.Dahealamon:BAAANQAECgIIAgAAAA==.Daiyan:BAAANQADCgMIAwABNQAECgYIDAASAAAAAA==.Damncats:BAABNQAECn8uAAIXAAgKyQ+0EACbAQAXAAgKyQ+0EACbAQAAAA==.Dandinn:BAAANQADCggICAAAAA==.Danielsboone:BAABNQAECn8UAAIQAAUKngyDeAC8AAAQAAUKngyDeAC8AAAAAA==.Daowa:BAAANQABCgEIAQAAAA==.Darkmare:BAACNQAFFH8FAAMZAAIKqQjCDgBJAAAZAAEKmgvCDgBJAAABAAEKuAU1IgBCAAA1AAQKfygAAxkACgqZFUERAG0CABkACgpWFEERAG0CAAEAAgrfCtSQAG8AAAAA.Darknemesis:BAAANQAECgQIBAABNQAECgUIBwASAAAAAA==.',
De='Deadhippocow:BAABNQAECn8bAAIJAAoKIR03BgDtAQAJAAoKIR03BgDtAQAAAA==.Dearth:BAEBNQAECn8VAAIMAAgKgguPmQCoAAAMAAgKgguPmQCoAAABNQAECgoKKAAMAKMZAA==.Deathbane:BAABNQAECn8dAAMVAAkKjg7fMgD6AAAWAAkK5w3RhQDYAQAVAAUKxAnfMgD6AAAAAA==.Deathwavez:BAAANQAECggIDwAAAA==.Deckard:BAEANQAECggICQABNQAECgoKKAAMAKMZAA==.Demayy:BAABNQAECn8iAAINAAkKAA/MHgCeAQANAAkKAA/MHgCeAQAAAA==.Demona:BAAANQAECgUICgAAAA==.Demonix:BAABNQAECn8oAAMWAAgKbR4vCQATAgAWAAgKDB4vCQATAgAaAAUKmhzrDACPAQAAAA==.Derptron:BAABNQAECn8cAAIGAAgK9xa4CABRAgAGAAgK9xa4CABRAgAAAA==.',
Di='Diluted:BAAANQAECgcIBwABNQAECgoKNgAPADghAA==.Dilutedqt:BAABNQAECn82AAIPAAoKOCHeFADCAQAPAAoKOCHeFADCAQAAAA==.Dilutedret:BAAANQAECgcIDwABNQAECgoKNgAPADghAA==.Dinobrass:BAABNQAECn8zAAIQAAkKbhcNEADvAQAQAAkKbhcNEADvAQAAAA==.Dirge:BAABNQAECn8iAAIRAAoKiA9zRQADAgARAAoKiA9zRQADAgAAAA==.Dirktheshiny:BAABNQAECn8zAAMMAAoKjhpfagBdAgAMAAkK4hlfagBdAgAHAAMKXg7tZwB/AAAAAA==.Dirtylöbster:BAABNQAECn8uAAIPAAkKZh6nTADoAgAPAAkKZh6nTADoAgAAAA==.Disabel:BAAANQADCggICAAAAA==.Distracto:BAAANQAECggIEAAAAA==.',
Dj='Djinsurgent:BAABNQAECn8gAAMEAAgKzxpjDQB7AQARAAcKThq/RQABAgAEAAgKixNjDQB7AQAAAA==.',
Dl='Dltdjr:BAAANQAECgQICwABNQAECgoKNgAPADghAA==.',
Do='Donnybrook:BAAANQAECgYIBgAAAA==.Doobysnacks:BAABNQAECn8cAAIEAAkKDyLTIQCmAgAEAAkKDyLTIQCmAgAAAA==.Doolittle:BAAANQAECgIIBAAAAA==.Dorfies:BAAANQADCgcJCAABNQAECgkJFwAPAIsaAA==.Dorns:BAAANQADCggICQAAAA==.',
Dr='Dragondees:BAAANQADCgYIBAAAAA==.Dralock:BAAANQAECgQIBAABNQAECgMIAwASAAAAAA==.Dreamyeti:BAAANQADCgEIAQAAAA==.Dreats:BAAANQAECgEIAQAAAA==.Drewmee:BAABNQAECn8VAAIMAAgKhgZF3QBgAQAMAAgKhgZF3QBgAQAAAA==.Droovani:BAAANQAECgUICgABNQAECggIFQAMAIYGAA==.Drunkenyeti:BAAANQADCgcIEAAAAA==.',
Du='Duckbeak:BAAANQAECgQIBQAAAA==.Duwork:BAABNQAECn8rAAIIAAoKfBy/BwC7AQAIAAoKfBy/BwC7AQAAAA==.',
['Dæ']='Dæmona:BAABNQAECn8uAAIbAAoKkxSsKQBTAgAbAAoKkxSsKQBTAgAAAA==.',
Eb='Ebk:BAAANQAECgcIDgAAAA==.Ebkx:BAAANQAECgIIAgAAAA==.',
El='Eladus:BAAANQAECgYIEQAAAA==.Elesus:BAAANQADCgIJAgABNQAECgoKMQAcAA8cAA==.',
Em='Emblaze:BAAANQADCgUIBQAAAA==.Emrys:BAAANQADCggIBwAAAA==.',
En='Enhshaman:BAAANQAECgQICAABNQAFFAcIGwACABQcAA==.',
Ev='Evilinne:BAAANQADCgYIBgAAAA==.',
Fa='Faithpasse:BAABNQAECn8cAAINAAcKAQzSJgBBAQANAAcKAQzSJgBBAQAAAA==.',
Fe='Felondar:BAABNQAECn8cAAIbAAkKhAlnSgB6AQAbAAkKhAlnSgB6AQAAAA==.Ferarro:BAABNQAECn8WAAIRAAgK1B48KACZAgARAAgK1B48KACZAgAAAA==.',
Fi='Finnadin:BAAANQADCgcIDQAAAA==.Finns:BAAANQAECgYIDQAAAA==.Firulais:BAABNQAECn8fAAIQAAgKTxKikADoAQAQAAgKTxKikADoAQAAAA==.Fistuu:BAAANQADCgUIBQAAAA==.',
Fl='Flysky:BAACNQAFFH8VAAIdAAYKMxgdCgCKAQAdAAYKMxgdCgCKAQA1AAQKfysABB0ACgq5Io8GAD4DAB0ACgq5Io8GAD4DAB4ABAqtIK0OAFoBAB8ABQqPGiojACwBAAAA.',
Fo='Foxsake:BAAANQADCgQIBAAAAA==.',
Fr='Freshpot:BAAANQAECgQICAAAAA==.Frostuss:BAAANQAECgMIAwAAAA==.Frostwyrm:BAAANQADCgYIBgAAAA==.',
Fu='Fumbles:BAAANQAECgEIAwAAAA==.Furysbane:BAAANQADCgMIAgAAAA==.Futurefist:BAAANQADCggICAAAAA==.',
Ga='Gabtvrdruid:BAAANQADCgEIAQAAAA==.Galvis:BAAANQAECggICQAAAA==.Garduuk:BAABNQAECn8mAAMJAAoKmhv7DQDxAgAJAAoKmhv7DQDxAgAIAAIKSw4bSgBFAAAAAA==.',
Ge='Gearth:BAABNQAECn8bAAIgAAcKwhtsFQARAgAgAAcKwhtsFQARAgAAAA==.Ger:BAAANQADCgYIDAABNQAECggIJwAPAAYPAA==.',
Gl='Glucose:BAAANQAECgcIEAAAAA==.',
Go='Gonah:BAABNQAECn8VAAIJAAYKQhTZOABXAQAJAAYKQhTZOABXAQAAAA==.Gotlieb:BAAANQAECgMIBgAAAA==.',
Gr='Gravey:BAABNQAECn8dAAIEAAcKlBt0NgAxAgAEAAcKlBt0NgAxAgAAAA==.Grogger:BAAANQADCgUIBQAAAA==.Grrahtahtah:BAACNQAFFH8bAAICAAcKFByvAwBOAgACAAcKFByvAwBOAgA1AAQKfysAAwIACgrSIFgKADEDAAIACgrSIFgKADEDABAAAQo7E0FLAUkAAAAA.',
Gy='Gymble:BAAANQAECggIAQAAAA==.',
Ha='Hakkim:BAAANQADCggICAAAAA==.Hammerinfred:BAAANQAECgIIAwAAAA==.',
He='Heavyguard:BAAANQABCgIIAgAAAA==.Helhunter:BAAANQAECgUIBQAAAA==.',
Hi='Hidann:BAAANQAECggIBwABNQAECgoKGwAWAFkSAA==.Himeko:BAAANQAECgQICgABNQAFFAYIFAAGAEkYAA==.Hippayman:BAAANQAECgQIBwAAAA==.Hippysmasher:BAAANQAECggIEAABNQAECgoKIgAOADATAA==.',
Ho='Holyhooters:BAABNQAECn8oAAIMAAoKBBi4IwCVAQAMAAoKBBi4IwCVAQAAAA==.Holypablo:BAAANQAECgQICQABNQAECgoKJgAhABEUAA==.Honour:BAABNQAECn8lAAIMAAkKlRh2ZABtAgAMAAkKlRh2ZABtAgAAAA==.',
Hr='Hrathdemon:BAABNQAECn81AAQiAAoKiR/OAQDYAQAOAAkKqyBVCgA1AwAiAAYKex7OAQDYAQAbAAUKORTAJgDVAAAAAA==.Hrathion:BAAANQAECgYIDQABNQAECgoKNQAiAIkfAA==.',
Hu='Hupa:BAABNQAECn8iAAIMAAcKZyM2XgB+AgAMAAcKZyM2XgB+AgAAAA==.Hurtsdonut:BAAANQAECgQIDAABNQAECgoKMQAcAA8cAA==.Huulis:BAAANQADCggICAAAAA==.',
Ia='Iamheyo:BAABNQAECn8bAAMHAAkKKRMDVwAUAgAHAAkKKRMDVwAUAgAMAAUKcxPqjQC4AAAAAA==.',
Ic='Ickeetard:BAAANQADCgcJBwAAAA==.',
Id='Idiotbreath:BAAANQAECgYIDwAAAA==.',
Ie='Ieatcheeks:BAAANQAECgcIDwAAAA==.Ieyasu:BAECNQAFFH8FAAIIAAIK0gUDDQCIAAAIAAIK0gUDDQCIAAA1AAQKfy4AAggACgpiFzApAI0CAAgACgpiFzApAI0CAAAA.',
Ig='Ignitus:BAAANQAECgUIDQAAAA==.',
Ik='Ikuchi:BAAANQAECgQICQAAAA==.',
Il='Illidornsina:BAAANQAECgQICgABNQADCggICQASAAAAAA==.Illpownyou:BAAANQADCgcIBwABNQAECggIGAAfAJcTAA==.',
In='Indigò:BAAANQAECgIIAgAAAA==.Insulinshot:BAAANQAECgIIAwAAAA==.',
Ir='Ironguard:BAAANQAECgEIAQAAAA==.',
It='Itsmagharszn:BAAANQADCgEIAQAAAA==.',
Ja='Jabronipie:BAAANQADCggIBQAAAA==.Jaliano:BAAANQADCgYIBgABNQAECggIIwATACINAA==.Jameyjasta:BAAANQAECgQIBgAAAA==.',
Je='Jeffblades:BAAANQABCgQIBQAAAA==.Jellyroll:BAAANQAECgQIBAAAAA==.Jessica:BAAANQAECgUIDQAAAA==.',
Jh='Jhana:BAAANQADCggIEQAAAA==.',
Ji='Jingojengo:BAAANQAECgIIAwAAAA==.',
Jj='Jjooaacchhim:BAAANQAECgQICgAAAA==.',
Jo='Josh:BAAANQAECgIIBAAAAA==.',
Ju='Junglefever:BAAANQADCgYIBgAAAA==.',
Jy='Jyve:BAABNQAECn8tAAIQAAgKow8RfQAUAgAQAAgKow8RfQAUAgAAAA==.',
Ka='Kadista:BAAANQAECgYIBwAAAA==.Kailin:BAAANQAECgIIBAAAAA==.Kailoon:BAAANQADCggICAAAAA==.Kakashi:BAAANQADCgYIDAAAAA==.Kalda:BAAANQAECgMIBgAAAA==.Kamadan:BAAANQAECgMIAwAAAA==.Kamanactali:BAAANQAECgIIAgAAAA==.Kamele:BAAANQAECgEIAQABNQAECgYIDAASAAAAAA==.Kaneko:BAEBNQAECn8bAAMMAAkKex4MCwAvAgAMAAkKFh0MCwAvAgAjAAEK+SP6JgBsAAABNQAFFAIIBQAIANIFAA==.Katalina:BAABNQAECn8zAAMiAAcKIBdZBgAcAQAbAAYKwBH+UwBBAQAiAAcKCRdZBgAcAQAAAA==.',
Ke='Kelstormhoof:BAAANQADCgcIEQABNQAECgUIBwASAAAAAA==.',
Kh='Kham:BAABNQAECn8hAAIXAAoKsx6GAwAdAwAXAAoKsx6GAwAdAwAAAA==.',
Ki='Kialla:BAAANQAECgYICQABNQAECggIIAAHAC8eAA==.Kirren:BAAANQADCgIIAgAAAA==.',
Kl='Klais:BAAANQADCgQIBQAAAA==.',
Ko='Kokeovrdose:BAAANQABCgQIBAABNQADCgYICgASAAAAAA==.Konet:BAAANQADCgMIAwAAAA==.',
La='Lavashiza:BAAANQAECgYIEQAAAA==.',
Le='Leadzorz:BAAANQAECgIIBAAAAA==.Leedaddydk:BAAANQADCgQIBAAAAA==.Leeoflight:BAAANQABCgQIBQAAAA==.Legday:BAAANQAECgUIBQAAAA==.Lesaelia:BAAANQAECgUIBQAAAA==.',
Li='Lightstorm:BAAANQAECgEIAQAAAA==.Liltotem:BAABNQAECn8uAAMTAAoKmxAgcQC4AQATAAoKmxAgcQC4AQAUAAQK7gd64QDUAAAAAA==.Linaria:BAAANQADCgUIBQAAAA==.Lizzydk:BAAANQAECgMIAwAAAA==.Lizzymonk:BAACNQAFFH8GAAIkAAIKphvJAgCZAAAkAAIKphvJAgCZAAA1AAQKfygAAiQACgqtIYoDAFcDACQACgqtIYoDAFcDAAAA.',
Lo='Lockdownlol:BAABNQAECn8oAAMQAAgKSiI6IgCPAQACAAcKVh1tKQD/AQAQAAcKiyM6IgCPAQABNQAECgoKNgAPADghAA==.Louisbraille:BAAANQAECgUIBQAAAA==.Lowe:BAAANQAECgEIAQAAAA==.',
Lu='Luluh:BAAANQAECgQIDQAAAA==.',
Ma='Maddog:BAABNQAECn8aAAIVAAgKNgodIABvAQAVAAgKNgodIABvAQAAAA==.Maebell:BAABNQAECn8ZAAIRAAcKbx9RBgDLAQARAAcKbx9RBgDLAQABNQAECgoKNgAPADghAA==.Mageslayer:BAABNQAECn8nAAMZAAgKERfiCQCXAQAZAAgKERfiCQCXAQABAAEK5QnRnwA7AAAAAA==.Magicpewfred:BAAANQADCgQIBAAAAA==.Magrun:BAAANQADCgUJCQAAAA==.Mahalleinr:BAAANQAECgEIAQAAAA==.Maiggee:BAAANQAECgUIBgAAAA==.Matt:BAACNQAFFH8GAAIQAAIK8hBwEQCAAAAQAAIK8hBwEQCAAAA1AAQKfy4AAhAACgpsHucbACgDABAACgpsHucbACgDAAAA.Mavrik:BAABNQAECn8iAAMLAAkKIgwJpgC+AQALAAkK0gsJpgC+AQAXAAQKrgq0HwDAAAAAAA==.',
Me='Meatmagic:BAAANQADCgIIAgAAAA==.Megapunk:BAAANQAECgMIBgAAAA==.Melanyie:BAAANQADCgMIAwAAAA==.Melfìce:BAAANQADCgYIBgAAAA==.Meudayr:BAABNQAECn8gAAIFAAoK5huSCQDbAgAFAAoK5huSCQDbAgAAAA==.',
Mi='Millarolly:BAAANQADCggIEAAAAA==.Mischifbomb:BAAANQADCgQIBQAAAA==.Mischifdk:BAAANQADCgIIAgAAAA==.Mischifdots:BAAANQADCgcIDwAAAA==.Mischifgg:BAABNQAECn8ZAAIhAAgKBxRvZQDvAQAhAAgKBxRvZQDvAQAAAA==.Mischïf:BAAANQADCgYICwAAAA==.Mittensmage:BAAANQADCggICAAAAA==.Mittenss:BAAANQADCggICQAAAA==.',
Mn='Mndgblnfred:BAAANQADCgEIAQAAAA==.',
Mo='Mojorisinn:BAAANQAECgQIBAAAAA==.Moobear:BAABNQAECn8wAAIFAAkKPyBpAgAyAgAFAAkKPyBpAgAyAgAAAA==.Moogie:BAABNQAECn8nAAIPAAkKPBt0gQB7AgAPAAkKPBt0gQB7AgAAAA==.Moozlock:BAAANQAECgEIAQAAAA==.Morgiana:BAAANQAECgYIDwABNQAECggIAwASAAAAAA==.Morvaine:BAAANQAECgUIBQAAAA==.Moscovio:BAACNQAFFH8hAAMWAAcKXhFTDACqAQAWAAYKrBFTDACqAQAVAAIKdQ66DwCVAAA1AAQKfy4AAxYACgqPIZsnAOYCABYACgokIZsnAOYCABUAAQqtGb5sAEYAAAAA.Mosspaws:BAAANQAECgUICAAAAA==.',
Mt='Mtndewyou:BAABNQAECn8mAAIjAAgKHRJ+JQC0AQAjAAgKHRJ+JQC0AQAAAA==.',
My='Myrothan:BAAANQAECgUICAAAAA==.',
Na='Napok:BAAANQAECgYIDAAAAA==.Nastea:BAAANQADCggICAAAAA==.',
Ni='Nickimihoj:BAAANQAECggIDQAAAA==.Nihr:BAAANQAECgUIBgAAAA==.Ninkarrak:BAAANQAECgIIBAAAAA==.Nitalan:BAAANQABCgIIAgAAAA==.',
Nm='Nme:BAABNQAECn8hAAIPAAgKJQrt3gDKAQAPAAgKJQrt3gDKAQAAAA==.',
No='Nocturnos:BAAANQAECgUIDAAAAA==.Nonfiction:BAAANQAECgUIBQABNQAECgoKMwAMAI4aAA==.Novamancer:BAAANQAECgEIAQAAAA==.',
Nu='Nuph:BAAANQAECgQIBQAAAA==.',
Ny='Nymage:BAABNQAECn8uAAIGAAoKMxfvAABKAgAGAAoKMxfvAABKAgAAAA==.',
Og='Ogdaddy:BAAANQADCggICAAAAA==.',
Ok='Okaerisan:BAAANQADCgMIAwAAAA==.',
Ol='Olord:BAAANQADCgEIAgAAAA==.',
Op='Ophbel:BAAANQADCgMIAwABNQAECggIEAASAAAAAA==.',
Or='Orack:BAABNQAECn8cAAIJAAcKgRgiJQD7AQAJAAcKgRgiJQD7AQAAAA==.',
Ou='Outlast:BAAANQADCgYIBgAAAA==.',
Ow='Owch:BAAANQABCgIIAgABNQAECgoKIAAFAOYbAA==.',
Pa='Paleface:BAAANQAECggIAgAAAA==.Panblind:BAACNQAFFH8UAAMOAAYKKRtuBgC3AQAOAAYKKRtuBgC3AQAiAAMKkhkaAwDlAAA1AAQKfysAAw4ACgpwIDYIAIsBAA4ACgqjHzYIAIsBACIAAwrlIuwYACMBAAAA.Pandington:BAAANQADCgQIBwAAAA==.Parmageddon:BAACNQAFFH8GAAIEAAIK2AztDgBuAAAEAAIK2AztDgBuAAA1AAQKfykAAgQACgrbG3UsAGYCAAQACgrbG3UsAGYCAAAA.Parmrageiano:BAAANQAECggIEAABNQAFFAIIBgAEANgMAA==.',
Pe='Peanought:BAABNQAECn8oAAQDAAkKPwvHGABKAQADAAkKLAnHGABKAQAEAAUKigofjADRAAARAAMKkAm6twB+AAAAAA==.Peetfix:BAABNQAECn8jAAMTAAoKaxuloQAyAQATAAQKZRuloQAyAQAUAAoKURZXKQAYAQAAAA==.Pepsipink:BAAANQAECgEIAQAAAA==.Pets:BAAANQAECgMIBgAAAA==.',
Ph='Phelon:BAAANQAECgYIBgABNQAFFAYIGAAlAJUgAA==.Phèdre:BAEANQAFFAEIAQABNQAFFAcIEgAMAMoQAA==.',
Pi='Picklegrip:BAABNQAECn8fAAILAAgKeRJMswCcAQALAAgKeRJMswCcAQAAAA==.Pijak:BAAANQAECgIIBAAAAA==.',
Pl='Planetina:BAAANQADCgcIBwAAAA==.',
Po='Poah:BAABNQAECn8UAAIYAAgKBx9cFgCcAgAYAAgKBx9cFgCcAgAAAA==.Portalcombat:BAAANQAECgIIAgAAAA==.',
Pr='Prettynhealz:BAAANQADCgIIAgAAAA==.Pruflas:BAAANQAECgEIAgAAAA==.',
Ps='Psycodk:BAAANQAECgYICAAAAA==.',
Pu='Puggernaut:BAAANQAECgQIBQAAAA==.Pumpin:BAAANQAECgMIBAAAAA==.Punkthor:BAABNQAECn8ZAAIkAAgKWBa7DwDyAQAkAAgKWBa7DwDyAQAAAA==.Purgemepappy:BAAANQADCgYIDAAAAA==.Putitinme:BAAANQABCgIIAgAAAA==.',
['Pø']='Pø:BAABNQAECn8ZAAIYAAgKJA0FMACXAQAYAAgKJA0FMACXAQAAAA==.',
Qk='Qkn:BAAANQAECgMIBAAAAA==.',
Ra='Raf:BAABNQAECn8bAAMUAAoKwiBJCwCNAwAUAAoKwiBJCwCNAwATAAIKixVC+gB2AAAAAA==.Rafraff:BAAANQAECgEIAQABNQAECgoKGwAUAMIgAA==.Ragnor:BAAANQAECgIIAgAAAA==.Ratoncita:BAAANQADCgUIBQAAAA==.Rayzee:BAAANQAECgEIAQAAAA==.',
Re='Reisar:BAAANQADCgMIAwAAAA==.Rennera:BAAANQADCgcIEgAAAA==.Revalation:BAABNQAECn8cAAMJAAkKdBoJCAC9AQAJAAkKdBoJCAC9AQAIAAEKAADHuAAoAAAAAA==.',
Ri='Riachu:BAAANQAECgUIDQAAAA==.Ribeyejoe:BAAANQAECgQIBgAAAA==.',
Ro='Roadblock:BAABNQAECn8VAAIXAAgKgBglDAD7AQAXAAgKgBglDAD7AQAAAA==.Roboorc:BAAANQABCgMIAwAAAA==.Roken:BAAANQADCggICAAAAA==.Rorymcilroy:BAABNQAECn8VAAMTAAcKbRtJVgAPAgATAAcKbRtJVgAPAgAUAAMK9Q0P+QChAAAAAA==.',
Ru='Ruddy:BAAANQADCgUIBQABNQAECgYIDAASAAAAAA==.',
Sa='Sacrament:BAABNQAECn8UAAIMAAkK0RqrCABWAgAMAAkK0RqrCABWAgABNQAFFAIIBwAYANMeAA==.Sagan:BAEANQADCgQIBAABNQAECgcIEAASAAAAAA==.Saifrah:BAAANQADCggICQAAAA==.Sandasa:BAAANQAECgQIBAAAAA==.Sanivanth:BAAANQADCgQIBAAAAA==.Saragos:BAAANQAECgEIAQABNQAFFAYIFAAGAEkYAA==.Saucerdote:BAAANQAECggIEQAAAA==.Saxon:BAAANQAECgEIAQAAAA==.',
Se='Selenix:BAAANQADCgYIBgAAAA==.Selinfinite:BAABNQAECn8YAAIbAAkKQSF8IACWAgAbAAkKQSF8IACWAgAAAA==.Selkie:BAABNQAECn8UAAIgAAYKHhKTHQCJAQAgAAYKHhKTHQCJAQAAAA==.Sephtis:BAAANQAECggIEgAAAA==.Serenitynow:BAAANQAECgQIBAAAAA==.Sevenlions:BAAANQADCgEIAQAAAA==.',
Sg='Sgge:BAAANQADCgYIBgAAAA==.',
Sh='Shadowmaven:BAAANQADCgcIEgAAAA==.Shakakhan:BAABNQAECn8hAAMUAAcKXiBYJAArAQAUAAcKXiBYJAArAQATAAEKfg2JFAFBAAABNQAECgoKNgAPADghAA==.Shammer:BAEANQADCggIBgABNQAECgkJIgAEAC0eAA==.Shamshielder:BAEBNQAECn8iAAMEAAkKLR6dLABlAgAEAAkKLR6dLABlAgADAAMKIwu5nABZAAAAAA==.Sharick:BAAANQAECgIIAwAAAA==.Shawdrake:BAAANQAECgUIBQABNQAECgkJLgATAH8RAA==.Shawlee:BAABNQAECn8uAAMTAAkKfxG9awDIAQATAAkKfxG9awDIAQAUAAgKKgv8kAB6AQAAAA==.Sheph:BAAANQAFFAIIAgAAAA==.Shetmage:BAABNQAECn8mAAIPAAkKTRPojwBgAgAPAAkKTRPojwBgAgABNQAFFAUIEQAIAGEWAA==.Shettrah:BAACNQAFFH8RAAIIAAUKYRY6DgCFAQAIAAUKYRY6DgCFAQA1AAQKfysAAggACgqhGZIeANUCAAgACgqhGZIeANUCAAAA.Shottdown:BAAANQADCgUIBQAAAA==.Shwoobs:BAAANQAECgEIAQAAAA==.Shädes:BAAANQAECggICQAAAA==.',
Si='Sigasunanvil:BAAANQAECgQIBAAAAA==.Siickboy:BAAANQAECgMIBAAAAA==.Sijious:BAAANQADCggIHwAAAA==.Silhõuette:BAAANQADCggICAAAAA==.Simperhi:BAAANQAECgEIAQAAAA==.Singularity:BAAANQAECgUIDQABNQAECgoKNgAPADghAA==.',
Sk='Skanktank:BAABNQAECn8gAAILAAgKxiA3QgDDAgALAAgKxiA3QgDDAgAAAA==.Skora:BAAANQAECggIAwAAAA==.Skyland:BAAANQADCgcIBwABNQAFFAYIFQAdADMYAA==.',
Sl='Slinkies:BAAANQADCgYICQABNQAECgkJFwAPAIsaAA==.Slipknife:BAABNQAECn8ZAAIBAAgKpxVrMAAgAgABAAgKpxVrMAAgAgAAAA==.',
So='Somi:BAABNQAECn8gAAIHAAoKxx41HwD0AgAHAAoKxx41HwD0AgAAAA==.',
St='Stabbystab:BAAANQAECgYIDQABNQADCgEIAgASAAAAAA==.Stabybara:BAAANQAECgUICQABNQAECgcIEAASAAAAAA==.Stankydk:BAABNQAECn8UAAIRAAgK0hTVVwCxAQARAAgK0hTVVwCxAQAAAA==.Stankyleg:BAACNQAFFH8PAAMQAAYKyQkeHQDLAAACAAQKzAuYEwAHAQAQAAQKPQMeHQDLAAA1AAQKfxcAAgIACQrIFGcMACwBAAIACQrIFGcMACwBAAAA.Starhealer:BAAANQADCgMIAwAAAA==.Stewie:BAABNQAECn8XAAIYAAgKOgoqNQBsAQAYAAgKOgoqNQBsAQAAAA==.Stinkbombs:BAAANQAECgUIBQAAAA==.Stinkies:BAAANQAECgUICQABNQAECgkJFwAPAIsaAA==.Stunanddone:BAAANQAECgEIAQAAAA==.',
Su='Subrogue:BAAANQAECgQICQABNQAFFAcIGwACABQcAA==.Sunlest:BAAANQADCgcIJwAAAA==.',
Sw='Swaayshooter:BAAANQAECgUIBwABNQAFFAMIBQABAOYRAA==.',
Sy='Sylphrena:BAACNQAFFH8GAAIhAAIKSB4aEgCfAAAhAAIKSB4aEgCfAAA1AAQKfygAAiEACgrvGjo1AJMCACEACgrvGjo1AJMCAAAA.Sylvanniia:BAAANQAECgcICQABNQAFFAcIFgAeAMUXAA==.',
Ta='Tacow:BAAANQAECgUIDAAAAA==.Talethen:BAABNQAECn8YAAQfAAgKlxOSFwDQAQAfAAgKlxOSFwDQAQAeAAUKpgp0FQDZAAAdAAEKZwYrUgAoAAAAAA==.',
Te='Telaragehoof:BAAANQAECgUIBwAAAA==.',
Th='Thedrood:BAABNQAECn8tAAIJAAoKNR2DDgDqAgAJAAoKNR2DDgDqAgAAAA==.Thorfyna:BAAANQADCggICAAAAA==.',
Ti='Tiptronic:BAAANQAECgQICQAAAA==.',
To='Tohk:BAACNQAFFH8QAAIbAAYKKBotCQCaAQAbAAYKKBotCQCaAQA1AAQKfykAAhsACQqeIcwTAAADABsACQqeIcwTAAADAAAA.Tollee:BAAANQAECgQIBAAAAA==.Tontiamat:BAABNQAECn8oAAIfAAkKShDJFAAAAgAfAAkKShDJFAAAAgAAAA==.Tontier:BAAANQAECgcIEAABNQAECgkJKAAfAEoQAA==.Tormero:BAAANQADCgcIBwAAAA==.Totembeans:BAAANQAECgQIBQAAAA==.Touchyfred:BAAANQAECgMIAwAAAA==.Toxicfury:BAAANQABCgUIBAAAAA==.',
Tr='Traash:BAAANQABCgIIAgAAAA==.Treily:BAAANQAECgMIEQAAAA==.Tricket:BAAANQAECgQICAAAAA==.Tristani:BAAANQAECgEIAQAAAA==.Trolloladin:BAAANQADCggIDwAAAA==.Truestorm:BAABNQAECn8hAAIMAAkK8AekzwB8AQAMAAkK8AekzwB8AQAAAA==.',
Tu='Tuchi:BAABNQAECn8ZAAIPAAgKTxz1tgAVAgAPAAgKTxz1tgAVAgAAAA==.Turak:BAAANQAECgEIAQAAAA==.',
['Tà']='Tàcobelle:BAAANQAECgcICwAAAA==.',
Va='Vanicton:BAABNQAECn8fAAITAAgKqyHeGQAKAwATAAgKqyHeGQAKAwAAAA==.',
Ve='Ve:BAABNQAECn8gAAMTAAoKmBmhOQB4AgATAAkK2xihOQB4AgAgAAYKTxhbHACeAQAAAA==.Vegh:BAABNQAECn8qAAIbAAgK8SANEgAPAwAbAAgK8SANEgAPAwAAAA==.Velaei:BAAANQAECgEJAQAAAA==.Veldcat:BAAANQAECgYIDAAAAA==.Velddk:BAAANQADCggICAAAAA==.Veriale:BAAANQAECgIIBAAAAA==.Verra:BAABNQAECn8cAAIMAAgKEhGZugCoAQAMAAgKEhGZugCoAQAAAA==.',
Vi='Vitriol:BAAANQAECgMIBAAAAA==.',
Wa='Wampa:BAAANQAECgEIAgAAAA==.Wanderblue:BAAANQAECgMIAwAAAA==.Wangstah:BAABNQAECn8XAAIQAAkKbhBgdgAjAgAQAAkKbhBgdgAjAgAAAA==.Warshaw:BAAANQABCgEIAQABNQAECgkJLgATAH8RAA==.Wartogoteam:BAABNQAECn85AAILAAoKMxpuSQCtAgALAAoKMxpuSQCtAgAAAA==.Waytogoteam:BAAANQADCgMIAwAAAA==.',
We='Weiss:BAACNQAFFH8UAAMGAAYKSRiTBgCoAAAPAAUKBhn1JgBPAQAGAAIKaBqTBgCoAAA1AAQKfyoAAg8ACgprI0QtADQDAA8ACgprI0QtADQDAAAA.',
Wf='Wf:BAABNQAECn8zAAQgAAoKQxHOFQAMAgAgAAkKihHOFQAMAgATAAYKdweTwgDkAAAUAAEKUg8okQA4AAAAAA==.',
Wi='Wildshapez:BAAANQAECgIIAgAAAA==.',
Wo='Woog:BAAANQADCgYIBgAAAA==.Worsthunterx:BAAANQAFFAEIAQABNQAFFAYIDwAlANkgAA==.',
Wr='Wreckedu:BAAANQADCgEIAQAAAA==.',
Wy='Wyldspirit:BAABNQAECn8UAAIQAAUKkAcr+AATAQAQAAUKkAcr+AATAQAAAA==.Wyreless:BAAANQAECgUIEQABNQAECgoKMQAFABsbAA==.',
Ya='Yaass:BAAANQADCggJCAABNQAECgoKMwAgAEMRAA==.Yagrum:BAAANQAECgEJAQAAAA==.Yahikko:BAABNQAECn8bAAIWAAoKWRIYeQD4AQAWAAoKWRIYeQD4AQAAAA==.',
Ye='Yem:BAABNQAECn8VAAQWAAkKQCEvGACSAQAVAAUK1CHaEQDnAQAWAAYKoyAvGACSAQAaAAIKpgyZIQBtAAAAAA==.',
Yo='Yoddaa:BAABNQAECn8eAAMcAAkKdhd7DQBcAQAhAAkK3BAxTwA3AgAcAAQKhR57DQBcAQABNQAECggIKAAWAG0eAA==.Yoverre:BAAANQAECgEIAQAAAA==.',
Ze='Zergen:BAAANQADCgYIBgAAAA==.Zetsu:BAAANQAECggIDwABNQAECgoKGwAWAFkSAA==.',
Zh='Zhenya:BAABNQAECn8mAAIPAAoK+w1QwgAAAgAPAAoK+w1QwgAAAgAAAA==.',
Zu='Zuga:BAAANQAECgcICwAAAA==.',
['Ôb']='Ôbelix:BAAANQADCggICAAAAA==.',
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
