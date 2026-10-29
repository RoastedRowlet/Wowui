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

local lookup = {'Rogue-Assassination','Shaman-Elemental','Hunter-Marksmanship','DeathKnight-Frost','DeathKnight-Blood','Druid-Guardian','Mage-Frost','Paladin-Holy','DemonHunter-Devourer','Mage-Arcane','Druid-Balance','Druid-Restoration','Warrior-Protection','Warrior-Arms','Paladin-Retribution','Monk-Mistweaver','Hunter-BeastMastery','DeathKnight-Unholy','Shaman-Restoration','Priest-Shadow','Priest-Holy','Warlock-Destruction','Warlock-Demonology','Warrior-Fury','Unknown-Unknown','Monk-Windwalker','Rogue-Subtlety','Warlock-Affliction','DemonHunter-Havoc','Priest-Discipline','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','DemonHunter-Vengeance','Paladin-Protection','Monk-Brewmaster','Druid-Feral',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abc:BAAANQADCgIIAgAAAA==.',
Ac='Acheniris:BAAANQAECgQIBwAAAA==.',
Ae='Aeviee:BAAANQADCgQJBAAAAA==.',
Ag='Agrippa:BAABNQAECn8dAAIBAAoKxw1VOQDvAQABAAoKxw1VOQDvAQAAAA==.',
Ah='Ahndhrez:BAABNQAECn8ZAAICAAoK3BqqGAA5AgACAAoK3BqqGAA5AgAAAA==.',
Ai='Aidric:BAAANQAECgYIDgAAAA==.Airwavez:BAACNQAFFH8PAAIDAAYKshOjBgAEAQADAAYKshOjBgAEAQA1AAQKfzwAAgMACgpUG9AHAHsCAAMACgpUG9AHAHsCAAAA.',
Ak='Akriel:BAAANQAECgcIDwAAAA==.',
Al='Albrecht:BAAANQAECgYICgAAAA==.Aldeor:BAAANQAECgIIAgAAAA==.Altra:BAACNQAFFH8IAAIEAAIKkQfVDwB5AAAEAAIKkQfVDwB5AAA1AAQKfywAAwQACgryFU0uAC8CAAQACgryFU0uAC8CAAUAAQoAAF3aACQAAAAA.Alumit:BAAANQAECgYJDwAAAA==.',
Am='Amoeta:BAABNQAECn81AAIGAAoKDhxICwC4AgAGAAoKDhxICwC4AgAAAA==.',
An='Andor:BAAANQADCgcIEAAAAA==.Angelique:BAAANQAECgUIDwAAAA==.Angry:BAAANQADCgYICgAAAA==.Angryapples:BAAANQAECgQJBQAAAA==.Annihilation:BAAANQADCgUIBQAAAA==.',
Ap='Approved:BAAANQADCgYIBQAAAA==.',
Ar='Arconos:BAAANQADCgYIDAABNQAFFAcIFQAHAP0WAA==.Arcstorm:BAAANQAECgEIAQAAAA==.',
As='Ashguard:BAAANQADCgcIDAAAAA==.Asomyrh:BAABNQAECn8iAAIIAAkKng37aQDZAQAIAAkKng37aQDZAQAAAA==.',
Au='Aurial:BAAANQADCgMIAwAAAA==.Auriala:BAAANQAECgcICQAAAA==.',
Az='Azuriae:BAAANQAECgQIBAAAAA==.',
Ba='Babygirl:BAAANQAECgYICQAAAA==.Bananer:BAAANQAECgQICAAAAA==.Banonzarath:BAAANQADCggICAAAAA==.Barrysoetoro:BAAANQADCgcIDAAAAA==.Battlemagic:BAAANQAECgYIBgABNQAECgoKJAAJANwTAA==.Baulie:BAAANQAECgQIBAAAAA==.',
Bb='Bbqlol:BAAANQAECgYIBAABNQAECgoKOgAKAPYhAA==.',
Be='Beefstick:BAAANQADCggIJgAAAA==.Bekroh:BAABNQAECn8YAAMLAAcKfhglSADKAQALAAcKfhglSADKAQAMAAEKbASufAAlAAAAAA==.Bestt:BAAANQAECgQIBgAAAA==.',
Bi='Bigdaddyd:BAABNQAECn8nAAMNAAgK/BHvFAD1AAAOAAgKaA2IaABMAQANAAcKkhHvFAD1AAAAAA==.Bigdonk:BAAANQADCggJCAAAAA==.Bigocagler:BAAANQADCggIFgAAAA==.Bioodlion:BAABNQAECn8qAAIPAAkKgQ4tvgCgAQAPAAkKgQ4tvgCgAQAAAA==.Bipolar:BAABNQAECn8oAAIQAAgKqAWAFgAUAQAQAAgKqAWAFgAUAQAAAA==.Bippysmasher:BAABNQAECn8kAAIJAAoK3BOcHwBSAgAJAAoK3BOcHwBSAgAAAA==.Bishmanistic:BAAANQAECgYIDQAAAA==.',
Bl='Blacblood:BAAANQAECgEIAQAAAA==.Blastemis:BAAANQAECgIIAgAAAA==.Blindweiss:BAAANQADCgcIBwABNQAFFAcIFQAHAP0WAA==.Blinkies:BAABNQAECn8ZAAIKAAkKvBs9hAB2AgAKAAkKvBs9hAB2AgAAAA==.',
Bo='Bontao:BAACNQAFFH8RAAIRAAcKQBQbCgCpAQARAAcKQBQbCgCpAQA1AAQKfzMAAhEACgoWIdA3AMMCABEACgoWIdA3AMMCAAAA.Bontaopanda:BAAANQADCgcIEwABNQAFFAcIEQARAEAUAA==.Boomies:BAAANQADCgQJBAABNQAECgkJGQAKALwbAA==.Borstenne:BAABNQAECn8kAAISAAkK9iPhCgBkAwASAAkK9iPhCgBkAwAAAA==.Bosco:BAAANQADCgQIBAAAAA==.',
Br='Bresemage:BAAANQAECgQIBAABNQAFFAIIBQAPAAEMAQ==.Bresepls:BAACNQAFFH8FAAIPAAIKAQw1GQCCAAAPAAIKAQw1GQCCAAA1AAQKfxgAAw8ACQq0GIdLANQBAA8ACAp+GodLANQBAAgAAwqbGkfOAN8AAAAA.Breseshh:BAABNQAECn84AAMTAAoKXiPtCAB6AwATAAoKXiPtCAB6AwACAAYKNxNpZADgAAABNQAFFAIIBQAPAAEMAA==.Brickbeard:BAAANQAECgQIAwAAAA==.Brickbow:BAAANQADCgYIBgAAAA==.Brickette:BAAANQAECgcIDQABNQAFFAcIFgAIAIENAA==.Bricklicker:BAAANQAECgQIAwAAAA==.Bricksquad:BAAANQAECgcIDgAAAA==.Brickthrow:BAACNQAFFH8WAAIIAAcKgQ1NDgB+AQAIAAcKgQ1NDgB+AQA1AAQKfzAAAwgACgqwH9AgAOsCAAgACgqwH9AgAOsCAA8AAQr5D3abAToAAAAA.Bringdapain:BAAANQAECgUICQAAAA==.',
Bu='Budhistpalm:BAAANQAECgMIAwAAAA==.Burgerburn:BAAANQAECgMIBwAAAA==.',
By='Bytheway:BAABNQAECn8WAAIUAAgKThUDKwDPAQAUAAgKThUDKwDPAQAAAA==.',
['Bé']='Béstt:BAABNQAECn8jAAMCAAoKPRr2KgDUAgACAAoKPRr2KgDUAgATAAEK9gNI0gArAAAAAA==.',
Ca='Cadilak:BAACNQAFFH8IAAIMAAIKow/mCwCBAAAMAAIKow/mCwCBAAA1AAQKfy0AAwwACgp8GUAXAIcCAAwACgp8GUAXAIcCAAsAAwoaD4qNAKAAAAAA.Caelesti:BAABNQAECn8UAAMUAAgKXA8sIAAHAQAUAAcKWgssIAAHAQAVAAIKYgZp/wAtAAAAAA==.Camlin:BAAANQADCggIDgAAAA==.',
Ch='Cheapshotjoe:BAAANQADCgEIAQAAAA==.Chelbur:BAAANQAECgIJAwAAAA==.Chowderhead:BAABNQAECn8pAAMWAAoKVRiTCQBgAgAWAAkKqROTCQBgAgAXAAcKRBXXdAAQAQAAAA==.',
Ci='Cileb:BAABNQAECn8lAAIKAAoK+B+qJwBDAwAKAAoK+B+qJwBDAwAAAA==.Civik:BAAANQAECgMIAwAAAA==.',
Co='Cocio:BAABNQAECn8dAAIOAAcKdBS6nQDSAQAOAAcKdBS6nQDSAQABNQAECgoKPAAOAIYaAA==.Conchsniffer:BAACNQAFFH8GAAIPAAMKuA/4DQDWAAAPAAMKuA/4DQDWAAA1AAQKfz0AAw8ACgpeIGosABYDAA8ACgpeIGosABYDAAgAAQo9AWo8ARUAAAAA.Conrack:BAAANQADCggICAAAAA==.Copperit:BAABNQAECn8lAAMFAAkKQCWVAgBIAwAFAAkKQCWVAgBIAwAEAAEKQh8amwBdAAAAAA==.Cornburglar:BAABNQAECn88AAMOAAoKhhoDRgC4AgAOAAoKIxoDRgC4AgAYAAIKziDYHwC+AAAAAA==.Corrona:BAEANQAECgMIAgABNQAFFAIIAgAZAAAAAA==.Cowtaclysmic:BAAANQAECgYIBgAAAA==.',
Cr='Creatlach:BAAANQADCgYIBgABNQAFFAYIFgATAOMZAA==.Crime:BAABNQAECn8dAAIBAAkKbxseBgBOAgABAAkKbxseBgBOAgABNQAFFAIIBwAaANMeAA==.Crunchwrap:BAABNQAECn8UAAILAAYK+ATtdwDrAAALAAYK+ATtdwDrAAAAAA==.',
Ct='Cthul:BAAANQADCggICAAAAA==.',
Cu='Curseus:BAAANQAECgEIAQAAAA==.',
['Câ']='Câlisse:BAACNQAFFH8HAAIaAAIK0x6SCACpAAAaAAIK0x6SCACpAAA1AAQKf0QAAhoACgqeI7ADAJoDABoACgqeI7ADAJoDAAAA.',
Da='Daddiedk:BAABNQAECn8dAAIEAAcKlBrcPQDVAQAEAAcKlBrcPQDVAQAAAA==.Dahealamon:BAAANQAECgIIAgAAAA==.Daiyan:BAAANQADCgQIBQABNQAECgUIEAAZAAAAAA==.Damncats:BAABNQAECn8uAAIYAAgKyQ+0EACbAQAYAAgKyQ+0EACbAQAAAA==.Dandinn:BAAANQADCggICAAAAA==.Danielsboone:BAABNQAECn8ZAAIRAAUKNg4VmgD8AAARAAUKNg4VmgD8AAAAAA==.Daowa:BAAANQABCgEIAQAAAA==.Darkmare:BAACNQAFFH8HAAMbAAIKqQjHGgBFAAAbAAEKmgvHGgBFAAABAAEKuAUwDQA1AAA1AAQKfysAAxsACgpSFkERAG0CABsACgoPFUERAG0CAAEAAgrfCtSQAG8AAAAA.Darknemesis:BAAANQAECgQICAABNQAECgUIBwAZAAAAAA==.',
De='Deadhippocow:BAABNQAECn8cAAIMAAoKIR24GQBtAgAMAAoKIR24GQBtAgAAAA==.Dearth:BAEBNQAECn8VAAIPAAgKgguWFgH6AAAPAAgKgguWFgH6AAABNQAFFAIIAgAZAAAAAA==.Deathbane:BAABNQAECn8eAAMWAAkKjg7fMgD6AAAXAAkK5w3RhQDYAQAWAAUKxAnfMgD6AAAAAA==.Deathwavez:BAAANQAECggIDwAAAA==.Deckard:BAEANQAECggICAABNQAFFAIIAgAZAAAAAA==.Demayy:BAABNQAECn8sAAIQAAoKDBacBgCPAgAQAAoKDBacBgCPAgAAAA==.Demona:BAAANQAECgUICgAAAA==.Demonix:BAABNQAECn8qAAMXAAkKdR6YNADYAQAXAAkKIR6YNADYAQAcAAUKmhzrDACPAQAAAA==.Demonshades:BAAANQADCgIIAgAAAA==.Derptron:BAABNQAECn8gAAIHAAoK2BS4CABRAgAHAAoK2BS4CABRAgAAAA==.',
Di='Diluted:BAAANQAECgcICwABNQAECgoKOgAKAPYhAA==.Dilutedqt:BAABNQAECn86AAIKAAoK9iGWLQAzAwAKAAoK9iGWLQAzAwAAAA==.Dilutedret:BAABNQAECn8YAAMPAAoKNRSMlAD7AQAPAAoKNRSMlAD7AQAIAAEKMhZ6uwBCAAABNQAECgoKOgAKAPYhAA==.Dinobrass:BAABNQAECn86AAIRAAkKfxjbPADuAQARAAkKfxjbPADuAQAAAA==.Dirge:BAABNQAECn8iAAISAAoKiA9zRQADAgASAAoKiA9zRQADAgAAAA==.Dirktheshiny:BAABNQAECn8zAAMPAAoKjhpfagBdAgAPAAkK4hlfagBdAgAIAAMKXg7noAB1AAAAAA==.Dirtylöbster:BAABNQAECn8uAAIKAAkKZh6nTADoAgAKAAkKZh6nTADoAgAAAA==.Disabel:BAAANQADCggICAAAAA==.Distracto:BAAANQAECggIEAAAAA==.',
Dj='Djinsurgent:BAABNQAECn8oAAMSAAgKzxr/HACMAQASAAgKcxn/HACMAQAFAAgKixPnKABUAQAAAA==.',
Dl='Dltdjr:BAAANQAECgQICwABNQAECgoKOgAKAPYhAA==.',
Do='Donnybrook:BAAANQAECgYICgAAAA==.Doobysnacks:BAABNQAECn8kAAIFAAkKdyK6CADDAgAFAAkKdyK6CADDAgAAAA==.Doolittle:BAAANQAECgMIBwAAAA==.Dorfies:BAAANQADCgcJCAABNQAECgkJGQAKALwbAA==.Dorns:BAAANQAECgQIBAAAAA==.',
Dr='Dragondees:BAAANQADCgYIBAAAAA==.Dralock:BAAANQAECgQIBAABNQAECgMIAwAZAAAAAA==.Dreamyeti:BAAANQADCgEIAQAAAA==.Dreats:BAAANQAECgEIAQAAAA==.Drewmee:BAABNQAECn8WAAIPAAkKmgZF3QBgAQAPAAkKmgZF3QBgAQAAAA==.Droovani:BAAANQAECgUICgABNQAECgkJFgAPAJoGAA==.Drunkenyeti:BAAANQADCgcIEAAAAA==.',
Du='Duckbeak:BAAANQAECgQIBQAAAA==.Duwork:BAABNQAECn8sAAILAAoKJx3zGAAAAwALAAoKJx3zGAAAAwAAAA==.',
['Dæ']='Dæmona:BAABNQAECn8uAAIdAAoKkxSsKQBTAgAdAAoKkxSsKQBTAgAAAA==.',
Eb='Ebk:BAAANQAECgcIDgAAAA==.Ebkx:BAAANQAECgIIAgAAAA==.',
El='Eladus:BAAANQAECgYIEQAAAA==.Elesus:BAAANQADCgIJAgABNQAECgoKOAAeACYeAA==.',
Em='Emblaze:BAAANQADCgUIBQAAAA==.Emrys:BAAANQADCggIBwAAAA==.',
En='Enhshaman:BAAANQAECgQICAABNQAFFAcIHAADABQcAA==.',
Ev='Evilinne:BAAANQAECgQIBAAAAA==.',
Fa='Faithpasse:BAABNQAECn8cAAIQAAcKAQzSJgBBAQAQAAcKAQzSJgBBAQAAAA==.',
Fe='Felondar:BAABNQAECn8dAAIdAAkKhAlnSgB6AQAdAAkKhAlnSgB6AQAAAA==.Ferarro:BAABNQAECn8WAAISAAgK1B48KACZAgASAAgK1B48KACZAgAAAA==.',
Fi='Finnadin:BAAANQADCgcIDQAAAA==.Finns:BAABNQAECn8WAAIGAAgKnAt5IQD9AAAGAAgKnAt5IQD9AAAAAA==.Firulais:BAABNQAECn8hAAIRAAkKGhGikADoAQARAAkKGhGikADoAQAAAA==.Fistuu:BAAANQADCgUIBQAAAA==.',
Fl='Flysky:BAACNQAFFH8WAAIfAAcKSBYdCgCKAQAfAAcKSBYdCgCKAQA1AAQKfy8ABB8ACgrSIo8GAD4DAB8ACgrSIo8GAD4DACAABQoHHq0OAFoBACEABQqPGiojACwBAAAA.',
Fo='Foxsake:BAAANQADCgQIBAAAAA==.',
Fr='Freshpot:BAAANQAECgQICAAAAA==.Frostuss:BAAANQAECgIIAwAAAA==.Frostwyrm:BAAANQADCgYIBgAAAA==.',
Fu='Fumbles:BAAANQAECgEIAwAAAA==.Furysbane:BAAANQADCgMIAgAAAA==.Futurefist:BAAANQADCggICAAAAA==.',
Ga='Gabtvrdruid:BAAANQADCgEIAQAAAA==.Galvis:BAAANQAECggIBwAAAA==.Garduuk:BAABNQAECn8nAAMMAAoKmhv7DQDxAgAMAAoKmhv7DQDxAgALAAMKJBULTQCRAAAAAA==.',
Ge='Gearth:BAABNQAECn8bAAIiAAcKwhtsFQARAgAiAAcKwhtsFQARAgAAAA==.Ger:BAAANQADCgYIDAABNQAECgoKNgAKADAOAA==.',
Gl='Glucose:BAAANQAECgcIDwAAAA==.',
Go='Gonah:BAABNQAECn8WAAIMAAYKGxXZOABXAQAMAAYKGxXZOABXAQAAAA==.Gotlieb:BAAANQAECgMIBgAAAA==.',
Gr='Gravey:BAABNQAECn8dAAIFAAcKlBt0NgAxAgAFAAcKlBt0NgAxAgAAAA==.Grogger:BAAANQADCgUIBQAAAA==.Grrahtahtah:BAACNQAFFH8cAAIDAAcKFByvAwBOAgADAAcKFByvAwBOAgA1AAQKfy0AAwMACgpWIVgKADEDAAMACgpWIVgKADEDABEAAQo7E0FLAUkAAAAA.',
Gy='Gymble:BAAANQAECggIAQAAAA==.',
Ha='Hakkim:BAAANQADCggICAAAAA==.Hammerinfred:BAAANQAECgIIAwAAAA==.',
He='Heavyguard:BAAANQABCgIIAgAAAA==.Helhunter:BAAANQAECggICwAAAA==.',
Hi='Hidann:BAAANQAECggIBwABNQAECgoKGwAXAFkSAA==.Himeko:BAAANQAECgMICQABNQAFFAcIFQAHAP0WAA==.Hippayman:BAAANQAECgQICAAAAA==.Hippysmasher:BAAANQAECggIDwABNQAECgoKJAAJANwTAA==.',
Ho='Holyhooters:BAABNQAECn8uAAIPAAoKSBrbTQCrAgAPAAoKSBrbTQCrAgAAAA==.Holypablo:BAAANQAECgcIDQABNQAECgoKKAAVAAQWAA==.Honour:BAABNQAECn8pAAIPAAoKxBh2ZABtAgAPAAoKxBh2ZABtAgAAAA==.',
Hr='Hrathadin:BAAANQAECggICQABNQAFFAIIBQAdAPsbAA==.Hrathdemon:BAACNQAFFH8FAAMdAAIK+xt3DACWAAAdAAIKKRV3DACWAAAJAAEK0RuSEwBWAAA1AAQKfzgABAkACgoJIFUKADUDAAkACQqrIFUKADUDACMABgp7HjEGALIBAB0ABQrfF0E9ANcAAAAA.Hrathion:BAAANQAECgYIDQABNQAFFAIIBQAdAPsbAA==.Hrathman:BAAANQAECgMIAwABNQAFFAIIBQAdAPsbAA==.',
Hu='Hupa:BAABNQAECn8iAAIPAAcKZyM2XgB+AgAPAAcKZyM2XgB+AgAAAA==.Hurtsdonut:BAAANQAECgQIDAABNQAECgoKOAAeACYeAA==.Huulis:BAAANQADCggICAAAAA==.',
Ia='Iamheyo:BAABNQAECn8dAAMIAAkKKRMDVwAUAgAIAAkKKRMDVwAUAgAPAAUKcxNK4QCqAAAAAA==.',
Ic='Ickeetard:BAAANQADCgcJBwAAAA==.',
Id='Idiotbreath:BAAANQAECgYIDwAAAA==.',
Ie='Ieatcheeks:BAAANQAECgcIDQAAAA==.Ieyasu:BAECNQAFFH8IAAILAAMKGwYVDgC+AAALAAMKGwYVDgC+AAA1AAQKfzEAAgsACgoIGzApAI0CAAsACgoIGzApAI0CAAE1AAUUBAgJAAIAdRQA.',
Ig='Ignitus:BAAANQAECgQIDAAAAA==.',
Ik='Ikuchi:BAAANQAECgYIDgAAAA==.',
Il='Illidornsina:BAAANQAECgUIDgABNQAECgQIBAAZAAAAAA==.Illpownyou:BAAANQADCgcIBwABNQAECggIHwAhAKETAA==.',
In='Indigò:BAAANQAECgIIAgAAAA==.Insulinshot:BAAANQAECgIIAwAAAA==.',
Ir='Ironguard:BAAANQABCgMIAwAAAA==.',
It='Itsmagharszn:BAAANQADCgEIAQAAAA==.',
Ja='Jabronipie:BAAANQADCggIBQAAAA==.Jaliano:BAAANQADCgYIBgABNQAECgkJKwATAAIMAA==.Jameyjasta:BAAANQAECgQIBgAAAA==.',
Je='Jeffblades:BAAANQABCgQIBQAAAA==.Jellyroll:BAAANQAECgQIBAAAAA==.Jessica:BAAANQAECgQIEQAAAA==.',
Jh='Jhana:BAAANQADCggIFwAAAA==.',
Ji='Jingojengo:BAAANQAECgIIBAAAAA==.',
Jj='Jjooaacchhim:BAAANQAECgQIDgAAAA==.',
Jo='Josh:BAAANQAECgIIBAAAAA==.',
Ju='Junglefever:BAAANQADCgYIBgAAAA==.',
Jy='Jyve:BAABNQAECn8vAAIRAAgKow8RfQAUAgARAAgKow8RfQAUAgAAAA==.',
Ka='Kadista:BAAANQAECgcIBgAAAA==.Kailin:BAAANQAECgIIBAAAAA==.Kailoon:BAAANQADCggICAAAAA==.Kakashi:BAAANQADCgYIDAAAAA==.Kalda:BAAANQAECgMIBgAAAA==.Kamadan:BAAANQAECgMIAwAAAA==.Kamanactali:BAAANQAECgIIAgAAAA==.Kaneko:BAEBNQAECn8hAAMPAAkKCyCvIwB4AgAPAAkKph6vIwB4AgAkAAEK+SPaOQBoAAABNQAFFAQICQACAHUUAA==.Kardiz:BAAANQADCgUIBQABNQAECggIAgAZAAAAAA==.Katalina:BAABNQAECn88AAMjAAoK/xOnBQDNAQAjAAoK/xOnBQDNAQAdAAYKwBH+UwBBAQAAAA==.',
Ke='Kelstormhoof:BAAANQADCgcIEQABNQAECgUIBwAZAAAAAA==.',
Kh='Kham:BAACNQAFFH8GAAIYAAUKuQvyAADOAAAYAAUKuQvyAADOAAA1AAQKfyoAAhgACgolISUCAMECABgACgolISUCAMECAAAA.',
Ki='Kialla:BAAANQAECgYICgABNQAECggIIAAIAC8eAA==.Kirren:BAAANQADCgIIAgAAAA==.',
Kl='Klais:BAAANQADCgQIBQAAAA==.',
Ko='Kokeovrdose:BAAANQABCgQIBAABNQADCgYICgAZAAAAAA==.Konet:BAAANQADCgMIAwAAAA==.Korrath:BAAANQAECgUIBAAAAA==.',
La='Lavashiza:BAAANQAECgYIEQAAAA==.',
Le='Leadzorz:BAAANQAECgMIBwAAAA==.Leeoflight:BAAANQABCgQIBQAAAA==.Legday:BAAANQAECgUIBQAAAA==.Lesaelia:BAAANQAECgUIBgAAAA==.',
Li='Lightstorm:BAAANQAECgEIAQAAAA==.Liltotem:BAABNQAECn84AAMTAAoKeBK3NgDCAQATAAoKeBK3NgDCAQACAAQK7gd64QDUAAAAAA==.Linaria:BAAANQADCgUIBQAAAA==.Lizzydk:BAAANQAECgMIAwAAAA==.Lizzymonk:BAACNQAFFH8IAAIlAAIK+BwhBACjAAAlAAIK+BwhBACjAAA1AAQKfysAAiUACgrWIYoDAFcDACUACgrWIYoDAFcDAAAA.',
Lo='Lockdownlol:BAABNQAECn8uAAMRAAkKaiK6OwDyAQADAAcKVh1tKQD/AQARAAgKfCO6OwDyAQABNQAECgoKOgAKAPYhAA==.Louisbraille:BAAANQAECgUIBAAAAA==.',
Lu='Luluh:BAAANQAECgQIDQAAAA==.',
Ma='Maddog:BAABNQAECn8aAAIWAAgKNgodIABvAQAWAAgKNgodIABvAQAAAA==.Maebell:BAABNQAECn8fAAISAAgKQSF6DgA0AgASAAgKQSF6DgA0AgABNQAECgoKOgAKAPYhAA==.Mageslayer:BAABNQAECn8oAAMbAAgKOxesGAAWAgAbAAgKOxesGAAWAgABAAEK5QnRnwA7AAAAAA==.Magicpewfred:BAAANQADCgQIBAAAAA==.Magrun:BAAANQADCgUJCQAAAA==.Mahalleinr:BAAANQAECgEIAgAAAA==.Maiggee:BAAANQAECgcIDAAAAA==.Matt:BAACNQAFFH8IAAIRAAIK8hAzGgCDAAARAAIK8hAzGgCDAAA1AAQKfzEAAhEACgpNH+cbACgDABEACgpNH+cbACgDAAAA.Mavrik:BAABNQAECn8sAAMOAAoKcAynYQBeAQAOAAoKMAynYQBeAQAYAAQKrgq0HwDAAAAAAA==.',
Me='Meatmagic:BAAANQAECgMIAwAAAA==.Megapunk:BAAANQAECgQICgAAAA==.Melanyie:BAAANQADCgMIAwAAAA==.Melfìce:BAAANQADCgYIBgAAAA==.Meudayr:BAABNQAECn8kAAIGAAoKpBySCQDbAgAGAAoKpBySCQDbAgAAAA==.Meåtheåd:BAAANQADCgcIBwABNQAECgMIAwAZAAAAAA==.',
Mi='Millarolly:BAAANQADCggIEAAAAA==.Mischifbomb:BAAANQAECgEIAQAAAA==.Mischifdk:BAAANQADCgIIAgAAAA==.Mischifdots:BAAANQADCgcIDwAAAA==.Mischifgg:BAABNQAECn8aAAIVAAkKyhJvZQDvAQAVAAkKyhJvZQDvAQAAAA==.Mischïf:BAAANQADCgYICwAAAA==.Mittensmage:BAAANQADCggICAAAAA==.Mittenss:BAAANQADCggICQAAAA==.',
Mn='Mndgblnfred:BAAANQADCgEIAQAAAA==.',
Mo='Mojorisinn:BAAANQAECgQIBAAAAA==.Moobear:BAABNQAECn84AAIGAAoK6yOeAgAfAwAGAAoK6yOeAgAfAwAAAA==.Moogie:BAABNQAECn8nAAIKAAkKPBt0gQB7AgAKAAkKPBt0gQB7AgAAAA==.Mooshades:BAAANQADCgYIBgAAAA==.Moozlock:BAAANQAECgEIAQAAAA==.Morgiana:BAAANQAECgYIDwABNQAECggIAgAZAAAAAA==.Morvaine:BAAANQAECgcIDAAAAA==.Moscovio:BAACNQAFFH8mAAMXAAcKIxNTDACqAQAXAAYKdhVTDACqAQAWAAIK1BG6DwCVAAA1AAQKfzYAAxcACgrjIpsnAOYCABcACgrjIpsnAOYCABYAAQqtGb5sAEYAAAAA.Mosspaws:BAAANQAECgUICAAAAA==.',
Mt='Mtndewyou:BAABNQAECn8nAAIkAAgKHRJ+JQC0AQAkAAgKHRJ+JQC0AQAAAA==.',
My='Myrothan:BAAANQAECgQIBwAAAA==.',
Na='Napok:BAAANQAECgUIEAAAAA==.Nastea:BAAANQADCggICAAAAA==.',
Ni='Nickimihoj:BAAANQAECggIDQAAAA==.Nihr:BAAANQAECgUIBgAAAA==.Ninkarrak:BAAANQAECgMIBwAAAA==.Nitalan:BAAANQABCgIIAgAAAA==.',
Nm='Nme:BAABNQAECn8lAAIKAAgKcwrt3gDKAQAKAAgKcwrt3gDKAQAAAA==.',
No='Nocturnos:BAAANQAECgYIDQAAAA==.Nonfiction:BAAANQAECgUIBQABNQAECgoKMwAPAI4aAA==.Novamancer:BAAANQAECgEIAQAAAA==.',
Nu='Nuph:BAAANQAECgQIBQAAAA==.',
Ny='Nymage:BAABNQAECn83AAIHAAoKSRczBAAzAgAHAAoKSRczBAAzAgAAAA==.',
Og='Ogdaddy:BAAANQADCggICAAAAA==.',
Ok='Okaerisan:BAAANQADCgMIAwAAAA==.',
Ol='Olord:BAAANQADCgEIAgAAAA==.',
Op='Ophbel:BAAANQADCgMIAwABNQAECgoKGQACANwaAA==.',
Or='Orack:BAABNQAECn8dAAIMAAgKlhYiJQD7AQAMAAgKlhYiJQD7AQAAAA==.',
Ou='Outlast:BAAANQADCgYIBgAAAA==.',
Ow='Owch:BAAANQABCgIIAgABNQAECgoKJAAGAKQcAA==.',
Pa='Paleface:BAAANQAECggIAgAAAA==.Pallychango:BAAANQAECgMIAwABNQAECgoKGQACANwaAA==.Panblind:BAACNQAFFH8VAAMJAAcKIRpuBgC3AQAJAAcKIRpuBgC3AQAjAAMKkhkaAwDlAAA1AAQKfzAAAwkACgrjIQsSANwCAAkACgrgIQsSANwCACMAAwrlIuwYACMBAAAA.Pandington:BAAANQADCgQIBwAAAA==.Parmageddon:BAACNQAFFH8IAAIFAAIKQRLSFABxAAAFAAIKQRLSFABxAAA1AAQKfysAAgUACgqtHHUsAGYCAAUACgqtHHUsAGYCAAAA.Parmnhammer:BAAANQAECgcIBwABNQAFFAIICAAFAEESAA==.Parmrageiano:BAABNQAECn8YAAMNAAgK4hpyBwDuAQANAAgK4hpyBwDuAQAOAAUKaxMpiQD+AAABNQAFFAIICAAFAEESAA==.',
Pe='Peanought:BAABNQAECn8rAAQEAAkKOAyROgAwAQAEAAkKLAmROgAwAQAFAAYKOQ2iWQCJAAASAAMKkAm6twB+AAAAAA==.Peetfix:BAABNQAECn8jAAMCAAoKURbyVwAbAgACAAoKURbyVwAbAgATAAQKZRuloQAyAQAAAA==.Pepsipink:BAAANQAECgEIAQAAAA==.Pets:BAAANQAECggIDAAAAA==.',
Ph='Phelon:BAAANQAECgYIBgABNQAFFAYIGAAUAJUgAA==.Phèdre:BAEANQAFFAEIAQABNQAFFAcIEgAPAMoQAA==.',
Pi='Picklegrip:BAABNQAECn8hAAIOAAgKeRJMswCcAQAOAAgKeRJMswCcAQAAAA==.Pijak:BAAANQAECgMIBwAAAA==.',
Pl='Planetina:BAAANQADCgcIBwAAAA==.',
Po='Poah:BAABNQAECn8UAAIaAAgKBx9cFgCcAgAaAAgKBx9cFgCcAgAAAA==.Portalcombat:BAAANQAECgIIAgAAAA==.',
Pr='Prettynhealz:BAAANQADCgIIAgAAAA==.Pruflas:BAAANQAECgEIAgAAAA==.',
Ps='Psycodk:BAAANQAECggICwAAAA==.',
Pu='Puggernaut:BAAANQAECgMIBwAAAA==.Pumpin:BAAANQAECgMIBAAAAA==.Punkthor:BAABNQAECn8hAAIlAAgKWBbXCABRAQAlAAgKWBbXCABRAQAAAA==.Purgemepappy:BAAANQADCgYIDAAAAA==.Putitinme:BAAANQABCgIIAgAAAA==.',
['Pø']='Pø:BAABNQAECn8nAAIaAAoKsA6+EQDKAQAaAAoKsA6+EQDKAQAAAA==.',
Qk='Qkn:BAAANQAECgIIAwAAAA==.',
Ra='Raf:BAABNQAECn8oAAMCAAoKwiBJCwCNAwACAAoKwiBJCwCNAwATAAQKZhLEowBwAAAAAA==.Ragnor:BAAANQAECgIIAgAAAA==.Ratoncita:BAAANQADCgUIBQAAAA==.Rayzee:BAAANQAECgEIAQAAAA==.',
Re='Reisar:BAAANQADCgMIAwAAAA==.Rennera:BAAANQADCgcIEgAAAA==.Revalation:BAABNQAECn8gAAMMAAoKkRi2GgBjAgAMAAoKkRi2GgBjAgALAAEKAADHuAAoAAAAAA==.',
Ri='Riachu:BAAANQAECgUIDQAAAA==.Ribeyejoe:BAAANQAECgQIBgAAAA==.',
Ro='Roadblock:BAABNQAECn8ZAAIYAAkKcxglDAD7AQAYAAkKcxglDAD7AQAAAA==.Roboorc:BAAANQABCgMIAwAAAA==.Roken:BAAANQADCggICAAAAA==.Rorymcilroy:BAABNQAECn8VAAMTAAcKbRtJVgAPAgATAAcKbRtJVgAPAgACAAMK9Q0P+QChAAAAAA==.',
Ru='Ruddy:BAAANQADCgUIBQABNQAECgUIEAAZAAAAAA==.',
Sa='Sacrament:BAABNQAECn8eAAIPAAkKvyDrEADwAgAPAAkKvyDrEADwAgABNQAFFAIIBwAaANMeAA==.Sagan:BAEANQADCgQIBAABNQAECgcIEAAZAAAAAA==.Saifrah:BAAANQADCggICQAAAA==.Sandasa:BAAANQAECgQIBAAAAA==.Sanivanth:BAAANQADCgQIBAAAAA==.Saragos:BAAANQAECgEIAQABNQAFFAcIFQAHAP0WAA==.Saucerdote:BAAANQAECggIEQAAAA==.Saxon:BAAANQAECgIIAQAAAA==.',
Se='Selenix:BAAANQADCgYIBgAAAA==.Selinfinite:BAABNQAECn8aAAIdAAoKNSB8IACWAgAdAAoKNSB8IACWAgAAAA==.Selkie:BAABNQAECn8ZAAIiAAYKHhKTHQCJAQAiAAYKHhKTHQCJAQAAAA==.Sephtis:BAABNQAECn8UAAQFAAoKpATmVwCOAAAFAAkKsATmVwCOAAASAAgKKAEK2QA9AAAEAAEKgwOmkQAmAAAAAA==.Serenitynow:BAAANQAECgQIBAAAAA==.Sevenlions:BAAANQADCgEIAQAAAA==.',
Sg='Sgge:BAAANQADCgYIBgAAAA==.',
Sh='Shadowmaven:BAAANQAECgQIBAAAAA==.Shakakhan:BAABNQAECn8lAAMCAAgKiyLdMQCRAQACAAgKiyLdMQCRAQATAAEKfg2JFAFBAAABNQAECgoKOgAKAPYhAA==.Shammer:BAEANQADCggIBgABNQAECgkJIgAFAC0eAA==.Shamshielder:BAEBNQAECn8iAAMFAAkKLR6dLABlAgAFAAkKLR6dLABlAgAEAAMKIwu5nABZAAAAAA==.Sharick:BAAANQAECgQIBgAAAA==.Shawdrake:BAAANQAECgUIBQABNQAECgkJLwATAH8RAA==.Shawlee:BAABNQAECn8vAAMTAAkKfxG9awDIAQATAAkKfxG9awDIAQACAAgKKgv8kAB6AQAAAA==.Sheph:BAAANQAFFAMIAwAAAA==.Shetmage:BAABNQAECn8qAAIKAAoKSRPojwBgAgAKAAoKSRPojwBgAgABNQAFFAYIEgALALsUAA==.Shettrah:BAACNQAFFH8SAAILAAYKuxQ6DgCFAQALAAYKuxQ6DgCFAQA1AAQKfzUAAgsACgpBIJQIAM0CAAsACgpBIJQIAM0CAAAA.Shottdown:BAAANQADCgUIBQAAAA==.Shwoobs:BAAANQAECgEIAQAAAA==.Shädes:BAAANQAECggICQAAAA==.',
Si='Sigasunanvil:BAAANQAECgQIBAAAAA==.Siickboy:BAAANQAECgMIBAAAAA==.Sijious:BAAANQADCggIHwAAAA==.Silhõuette:BAAANQADCggICAAAAA==.Singularity:BAAANQAECgUIDQABNQAECgoKOgAKAPYhAA==.',
Sk='Skanktank:BAABNQAECn8gAAIOAAgKxiA3QgDDAgAOAAgKxiA3QgDDAgAAAA==.Skora:BAAANQAECggIAgAAAA==.Skyland:BAAANQADCgcIBwABNQAFFAcIFgAfAEgWAA==.',
Sl='Slinkies:BAAANQADCgYICQABNQAECgkJGQAKALwbAA==.Slipknife:BAABNQAECn8dAAIBAAkKABVrMAAgAgABAAkKABVrMAAgAgAAAA==.',
Sn='Sneez:BAAANQAECgEIAQABNQAECgoKNwANAA4gAA==.',
So='Somi:BAACNQAFFH8GAAIIAAIKbyFWEADDAAAIAAIKbyFWEADDAAA1AAQKfyMAAggACgrhHjUfAPQCAAgACgrhHjUfAPQCAAAA.Sourworms:BAAANQAECgQIBAAAAA==.',
St='Stabbystab:BAAANQAECgYIDQABNQADCgEIAgAZAAAAAA==.Stabybara:BAAANQAECgUICQABNQAECgcIDwAZAAAAAA==.Stankydk:BAABNQAECn8UAAISAAgK0hTVVwCxAQASAAgK0hTVVwCxAQAAAA==.Stankyleg:BAACNQAFFH8QAAMRAAcKYgkeHQDLAAADAAUKywqYEwAHAQARAAQKPQMeHQDLAAA1AAQKfxwAAgMACQoQFqETAIYBAAMACQoQFqETAIYBAAAA.Starhealer:BAAANQADCggICwAAAA==.Stewie:BAABNQAECn8YAAIaAAkK4wkqNQBsAQAaAAkK4wkqNQBsAQAAAA==.Stinkbombs:BAAANQAECgUIBgAAAA==.Stinkies:BAAANQAECgUICQABNQAECgkJGQAKALwbAA==.Stunanddone:BAAANQAECgYICgAAAA==.',
Su='Subrogue:BAAANQAECgQICQABNQAFFAcIHAADABQcAA==.Sunlest:BAAANQADCgcIJwAAAA==.',
Sw='Swaayshooter:BAAANQAECgUIBwABNQAFFAMIBQABAOYRAA==.',
Sy='Sylphrena:BAACNQAFFH8IAAIVAAIK4h+uGQCvAAAVAAIK4h+uGQCvAAA1AAQKfysAAhUACgoCGzo1AJMCABUACgoCGzo1AJMCAAAA.Sylvanniia:BAAANQAECgYICgABNQAFFAcIFgAgAMUXAA==.',
Ta='Tacow:BAAANQAECgUIDAAAAA==.Talethen:BAABNQAECn8fAAQhAAgKoROSFwDQAQAhAAgKlxOSFwDQAQAgAAYKVgt0FQDZAAAfAAEKZwYrUgAoAAAAAA==.',
Te='Telaragehoof:BAAANQAECgUIBwAAAA==.',
Th='Thatbox:BAAANQAECgUIBgAAAA==.Thedrood:BAABNQAECn83AAIMAAoKLx6GCgCVAgAMAAoKLx6GCgCVAgAAAA==.Thorfyna:BAAANQADCggICAAAAA==.',
Ti='Tintinnabula:BAABNQAECn8VAAIcAAYK6A5NCgD0AAAcAAYK6A5NCgD0AAAAAA==.Tiptronic:BAAANQAECgQICQAAAA==.',
To='Tohk:BAACNQAFFH8RAAIdAAcKhBgtCQCaAQAdAAcKhBgtCQCaAQA1AAQKfy0AAh0ACgotH8wTAAADAB0ACgotH8wTAAADAAAA.Tollee:BAAANQAECgQIBAAAAA==.Tontiamat:BAABNQAECn8xAAIhAAoKUhCjBwCbAQAhAAoKUhCjBwCbAQAAAA==.Tontier:BAABNQAECn8aAAMmAAgKYhFhDABsAQAmAAgKYhFhDABsAQAMAAMKLw//WQCgAAABNQAECgoKMQAhAFIQAA==.Tormero:BAAANQADCgcIBwAAAA==.Totembeans:BAAANQAECgQIBQAAAA==.Touchyfred:BAAANQAECgMIAwAAAA==.Toxicfury:BAAANQABCgUIBAAAAA==.',
Tr='Traash:BAAANQABCgIIAgAAAA==.Treily:BAAANQAECgMIEQAAAA==.Tricket:BAAANQAECgQICAAAAA==.Trolloladin:BAAANQADCggIDwAAAA==.Truestorm:BAABNQAECn8hAAIPAAkK8AekzwB8AQAPAAkK8AekzwB8AQAAAA==.',
Tu='Tuchi:BAABNQAECn8ZAAIKAAgKTxz1tgAVAgAKAAgKTxz1tgAVAgAAAA==.',
['Tà']='Tàcobelle:BAAANQAECgcIDQAAAA==.',
Un='Unpredicted:BAAANQADCgIIAgAAAA==.',
Va='Vanicton:BAABNQAECn8fAAITAAgKqyHeGQAKAwATAAgKqyHeGQAKAwAAAA==.',
Ve='Ve:BAABNQAECn8kAAMTAAoK9BqhOQB4AgATAAkKXxqhOQB4AgAiAAYKTxhbHACeAQAAAA==.Vegh:BAABNQAECn8qAAIdAAgK8SANEgAPAwAdAAgK8SANEgAPAwAAAA==.Velaei:BAAANQAECgEJAQAAAA==.Veldcat:BAAANQAECgYIDAAAAA==.Velddk:BAAANQADCggICAAAAA==.Veriale:BAAANQAECgMIBwAAAA==.Verra:BAABNQAECn8dAAIPAAkK0w+ZugCoAQAPAAkK0w+ZugCoAQAAAA==.',
Vi='Vitriol:BAAANQAECgMIBAAAAA==.',
Wa='Wampa:BAAANQAECgEIAgAAAA==.Wanderblue:BAAANQAECgMIAwAAAA==.Wangstah:BAABNQAECn8ZAAIRAAkKqxNgdgAjAgARAAkKqxNgdgAjAgAAAA==.Warshaw:BAAANQABCgEIAQABNQAECgkJLwATAH8RAA==.Wartogoteam:BAABNQAECn85AAIOAAoKMxpuSQCtAgAOAAoKMxpuSQCtAgAAAA==.Waytogoteam:BAAANQAECgEIAQAAAA==.',
We='Weiss:BAACNQAFFH8VAAMHAAcK/RaTBgCoAAAKAAUKBhn1JgBPAQAHAAMKiheTBgCoAAA1AAQKfy0AAgoACgprI0QtADQDAAoACgprI0QtADQDAAAA.',
Wf='Wf:BAABNQAECn88AAQiAAoKQxHOFQAMAgAiAAkKihHOFQAMAgATAAoKewUuZAARAQACAAEKUg/vwAA4AAAAAA==.',
Wi='Wildshapez:BAAANQAECgIIAwAAAA==.',
Wo='Woog:BAAANQADCgYIBgAAAA==.Worsthunterx:BAAANQAFFAEIAQABNQAFFAYIDwAUANkgAA==.',
Wr='Wreckedu:BAAANQADCgEIAQAAAA==.',
Wy='Wyldspirit:BAABNQAECn8ZAAIRAAUKkAf9wwCqAAARAAUKkAf9wwCqAAAAAA==.Wyreless:BAAANQAECgUIEQABNQAECgoKNQAGAA4cAA==.',
Ya='Yaass:BAAANQADCggJCAABNQAECgoKPAAiAEMRAA==.Yagrum:BAAANQAECgEJAQAAAA==.Yahikko:BAABNQAECn8bAAIXAAoKWRIYeQD4AQAXAAoKWRIYeQD4AQAAAA==.',
Ye='Yem:BAABNQAECn8ZAAQWAAkKeyHaEQDnAQAWAAYKZyLaEQDnAQAXAAYKoyD8SwCBAQAcAAIKpgyZIQBtAAAAAA==.',
Yo='Yoddaa:BAABNQAECn8lAAMeAAoKmBh7DQBcAQAVAAoKPRQxTwA3AgAeAAQKhR57DQBcAQABNQAECgkJKgAXAHUeAA==.',
Ze='Zergen:BAAANQADCgYIBgAAAA==.Zetsu:BAAANQAECggIDgABNQAECgoKGwAXAFkSAA==.',
Zh='Zhenya:BAABNQAECn8qAAIKAAoKRw9QwgAAAgAKAAoKRw9QwgAAAgAAAA==.',
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
