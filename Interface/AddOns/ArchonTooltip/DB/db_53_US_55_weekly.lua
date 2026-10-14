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

local lookup = {'Rogue-Assassination','Hunter-Marksmanship','DeathKnight-Frost','DeathKnight-Blood','Druid-Guardian','Mage-Frost','Paladin-Holy','Druid-Balance','Druid-Restoration','Warrior-Protection','Warrior-Arms','Paladin-Retribution','Monk-Mistweaver','DemonHunter-Devourer','Mage-Arcane','Hunter-BeastMastery','DeathKnight-Unholy','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Warrior-Fury','Monk-Windwalker','Rogue-Subtlety','Warlock-Affliction','DemonHunter-Havoc','Priest-Discipline','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','Priest-Holy','DemonHunter-Vengeance','Monk-Brewmaster','Paladin-Protection','Priest-Shadow',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abc:BAAANQADCgIIAgAAAA==.',
Ac='Acheniris:BAAANQAECgQIBQAAAA==.',
Ae='Aeviee:BAAANQADCgQJBAAAAA==.',
Ag='Agrippa:BAABNQAECn8aAAIBAAkK0AwzOADvAQABAAkK0AwzOADvAQAAAA==.',
Ah='Ahndhrez:BAAANQAECgUICQAAAA==.',
Ai='Aidric:BAAANQAECgYICQAAAA==.Airwavez:BAACNQAFFH8KAAICAAUKoxegCwCAAQACAAUKoxegCwCAAQA1AAQKfy8AAgIACQq8G4sXAJoCAAIACQq8G4sXAJoCAAAA.',
Ak='Akriel:BAAANQAECgcIDwAAAA==.',
Al='Albrecht:BAAANQAECgMIAwAAAA==.Aldeor:BAAANQAECgIIAgAAAA==.Altra:BAABNQAECn8mAAMDAAkKMxZvLQAvAgADAAkKMxZvLQAvAgAEAAEKAABR2AAkAAAAAA==.Alumit:BAAANQAECgYJDwAAAA==.',
Am='Amoeta:BAABNQAECn8rAAIFAAkKOhszCwC3AgAFAAkKOhszCwC3AgAAAA==.',
An='Andor:BAAANQADCgYIDQAAAA==.Angelique:BAAANQAECgUIDwAAAA==.Angry:BAAANQADCgYICgAAAA==.Angryapples:BAAANQAECgQJBQAAAA==.Annihilation:BAAANQADCgUIBQAAAA==.',
Ap='Approved:BAAANQADCgYIBQAAAA==.',
Ar='Arconos:BAAANQADCgYIDAABNQAFFAUIEwAGAMUbAA==.Arcstorm:BAAANQAECgEIAQAAAA==.',
As='Ashguard:BAAANQADCgUJBQAAAA==.Asomyrh:BAABNQAECn8aAAIHAAgKKA6taADaAQAHAAgKKA6taADaAQAAAA==.',
Au='Aurial:BAAANQADCgMIAwAAAA==.Auriala:BAAANQAECgQIBAAAAA==.',
Ba='Babygirl:BAAANQAECgYICQAAAA==.Bananer:BAAANQAECgQICAAAAA==.Banonzarath:BAAANQADCggICAAAAA==.Barrysoetoro:BAAANQADCgcIDAAAAA==.Baulie:BAAANQAECgQIBAAAAA==.',
Be='Beefstick:BAAANQADCggIHgAAAA==.Bekroh:BAABNQAECn8YAAMIAAcKfhhmRwDKAQAIAAcKfhhmRwDKAQAJAAEKbASpegAlAAAAAA==.Bestt:BAAANQAECgQIBQAAAA==.',
Bi='Bigdaddyd:BAABNQAECn8XAAMKAAcKxxCCIgAxAQALAAYKQQ1n2QA0AQAKAAYK8BCCIgAxAQAAAA==.Bigdonk:BAAANQADCggJCAAAAA==.Bigocagler:BAAANQADCggIFgAAAA==.Bioodlion:BAABNQAECn8iAAIMAAcKZxA3uwCgAQAMAAcKZxA3uwCgAQAAAA==.Bipolar:BAABNQAECn8YAAINAAcKaQTmLQD3AAANAAcKaQTmLQD3AAAAAA==.Bippysmasher:BAABNQAECn8eAAIOAAgKsRZAHwBTAgAOAAgKsRZAHwBTAgAAAA==.Bishmanistic:BAAANQAECgUIDQAAAA==.',
Bl='Blacblood:BAAANQAECgEIAQAAAA==.Blindweiss:BAAANQADCgcIBwABNQAFFAUIEwAGAMUbAA==.Blinkies:BAABNQAECn8UAAIPAAgKdhv7gQB6AgAPAAgKdhv7gQB6AgAAAA==.',
Bo='Bontao:BAACNQAFFH8PAAIQAAUK0hzQCQCpAQAQAAUK0hzQCQCpAQA1AAQKfyoAAhAACQoAH/82AMMCABAACQoAH/82AMMCAAAA.Bontaopanda:BAAANQADCgcIEwABNQAFFAUIDwAQANIcAA==.Boomies:BAAANQADCgQJBAABNQAECggIFAAPAHYbAA==.Borstenne:BAABNQAECn8kAAIRAAkK9iPDCgBkAwARAAkK9iPDCgBkAwAAAA==.Bosco:BAAANQADCgQIBAAAAA==.',
Br='Bresemage:BAAANQAECgQIBAABNQAFFAIIAgASAAAAAQ==.Bresepls:BAAANQAFFAIIAgAAAA==.Breseshh:BAABNQAECn8qAAMTAAkK1iOyCAB6AwATAAkK1iOyCAB6AwAUAAMKIBJZ1QDlAAABNQAFFAIIAgASAAAAAA==.Brickbeard:BAAANQAECgMIAwAAAA==.Brickbow:BAAANQADCgYIBgAAAA==.Brickette:BAAANQAECgcIDQABNQAFFAUIFAAHABUPAA==.Bricklicker:BAAANQAECgMIAwAAAA==.Bricksquad:BAAANQAECgcIDgAAAA==.Brickthrow:BAACNQAFFH8UAAIHAAUKFQ/vDQB+AQAHAAUKFQ/vDQB+AQA1AAQKfycAAwcACQpIHYMgAOoCAAcACQpIHYMgAOoCAAwAAQr5D22VAToAAAAA.',
Bu='Budhistpalm:BAAANQAECgMIAwAAAA==.Burgerburn:BAAANQAECgEIAwAAAA==.',
By='Bytheway:BAAANQAECgYIDgAAAA==.',
['Bé']='Béstt:BAABNQAECn8dAAIUAAkKrRlZKgDUAgAUAAkKrRlZKgDUAgAAAA==.',
Ca='Cadilak:BAABNQAECn8mAAMJAAkKTxn1FgCGAgAJAAkKTxn1FgCGAgAIAAMKGg8VjACgAAAAAA==.Caelesti:BAAANQAECgQIBwAAAA==.Camlin:BAAANQADCggIDgAAAA==.',
Ch='Cheapshotjoe:BAAANQADCgEIAQAAAA==.Chelbur:BAAANQAECgIJAwAAAA==.Chowderhead:BAABNQAECn8gAAMVAAkK6RWMCQBgAgAVAAkKqROMCQBgAgAWAAMKgB7S9gDYAAAAAA==.',
Ci='Cileb:BAABNQAECn8dAAIPAAkKeB7FJgBGAwAPAAkKeB7FJgBGAwAAAA==.Civik:BAAANQAECgMIAwAAAA==.',
Co='Cocio:BAABNQAECn8dAAILAAcKdBTSmwDSAQALAAcKdBTSmwDSAQABNQAECgkJLgALACYaAA==.Conchsniffer:BAABNQAECn83AAMMAAkKHCGNKwAXAwAMAAkKHCGNKwAXAwAHAAEKPQHDOAEVAAAAAA==.Conrack:BAAANQADCggJCAAAAA==.Copperit:BAABNQAECn8ZAAMEAAcK7iO+HQDBAgAEAAcK7iO+HQDBAgADAAEKQh/alwBdAAAAAA==.Cornburglar:BAABNQAECn8uAAMLAAkKJhrORAC4AgALAAkKtRnORAC4AgAXAAIKziB2HwC+AAAAAA==.Corrona:BAEANQADCggJCAABNQAFFAEIAQASAAAAAA==.Cowtaclysmic:BAAANQAECgYIBgAAAA==.',
Cr='Creatlach:BAAANQADCgYIBgABNQAFFAYIFAATAIIVAA==.Crime:BAAANQAECggIDwABNQAFFAIIBQAYAPUaAA==.Crunchwrap:BAAANQAECgUIEwAAAA==.',
Ct='Cthul:BAAANQADCggICAAAAA==.',
Cu='Curseus:BAAANQADCgUIBQAAAA==.',
['Câ']='Câlisse:BAACNQAFFH8FAAIYAAIK9RpjDgCiAAAYAAIK9RpjDgCiAAA1AAQKfzUAAhgACQrqI5wDAJoDABgACQrqI5wDAJoDAAAA.',
Da='Daddiedk:BAABNQAECn8dAAIDAAcKlBq9PADVAQADAAcKlBq9PADVAQAAAA==.Dahealamon:BAAANQAECgIIAgAAAA==.Daiyan:BAAANQADCgMIAwABNQAECgUICwASAAAAAA==.Damncats:BAABNQAECn8pAAIXAAcK6xCQEACaAQAXAAcK6xCQEACaAQAAAA==.Dandinn:BAAANQADCggICAAAAA==.Danielsboone:BAAANQAECgUIEAAAAA==.Daowa:BAAANQABCgEIAQAAAA==.Darkmare:BAABNQAECn8lAAMZAAkKqRYIEQBuAgAZAAkKNxUIEQBuAgABAAIK3wrSjQBvAAAAAA==.Darknemesis:BAAANQAECgQIBAABNQAECgQIBAASAAAAAA==.',
De='Deadhippocow:BAAANQAECgcIEwAAAA==.Dearth:BAEANQAFFAEIAQAAAA==.Deathbane:BAABNQAECn8aAAMVAAgK+w6zMgD6AAAWAAgKNw4BhADYAQAVAAUKxAmzMgD6AAAAAA==.Deathwavez:BAAANQAECggIDgAAAA==.Deckard:BAEANQAECggICAABNQAFFAEIAQASAAAAAA==.Demayy:BAABNQAECn8eAAINAAgKzw59HgCeAQANAAgKzw59HgCeAQAAAA==.Demona:BAAANQAECgUICgAAAA==.Demonix:BAABNQAECn8hAAMWAAcKEB/YTgBkAgAWAAcKmx7YTgBkAgAaAAUKmhzNDACPAQAAAA==.Derptron:BAABNQAECn8cAAIGAAgK9xaVCABSAgAGAAgK9xaVCABSAgAAAA==.',
Di='Diluted:BAAANQADCgQIBAABNQAECgkJLwAPAEwgAA==.Dilutedqt:BAABNQAECn8vAAIPAAkKTCDNLAA1AwAPAAkKTCDNLAA1AwAAAA==.Dilutedret:BAAANQAECgcICwABNQAECgkJLwAPAEwgAA==.Dinobrass:BAABNQAECn8qAAIQAAgKaxhVUwB0AgAQAAgKaxhVUwB0AgAAAA==.Dirge:BAABNQAECn8fAAIRAAkK8BC8RAADAgARAAkK8BC8RAADAgAAAA==.Dirktheshiny:BAABNQAECn8vAAMMAAkK4hmFaABeAgAMAAkK4hmFaABeAgAHAAIKNghIBQFnAAAAAA==.Dirtylöbster:BAABNQAECn8uAAIPAAkKZh6gSwDqAgAPAAkKZh6gSwDqAgAAAA==.Disabel:BAAANQADCggICAAAAA==.Distracto:BAAANQAECggIEAAAAA==.',
Dj='Djinsurgent:BAABNQAECn8YAAMRAAcKThrwRAACAgARAAcKThrwRAACAgAEAAEKIRP8wQBBAAAAAA==.',
Dl='Dltdjr:BAAANQAECgQICwABNQAECgkJLwAPAEwgAA==.',
Do='Donnybrook:BAAANQADCgQIBAAAAA==.Doobysnacks:BAABNQAECn8YAAIEAAcKjyRqIQCnAgAEAAcKjyRqIQCnAgAAAA==.Doolittle:BAAANQAECgIIAgAAAA==.Dorfies:BAAANQADCgcJCAABNQAECggIFAAPAHYbAA==.Dorns:BAAANQADCgEIAQAAAA==.',
Dr='Dragondees:BAAANQADCgYIBAAAAA==.Dralock:BAAANQAECgQIBAABNQAECgMIAwASAAAAAA==.Dreamyeti:BAAANQADCgEIAQAAAA==.Dreats:BAAANQADCgUIBgAAAA==.Drewmee:BAABNQAECn8VAAIMAAgKhgbq2QBgAQAMAAgKhgbq2QBgAQAAAA==.Droovani:BAAANQAECgUICgABNQAECggIFQAMAIYGAA==.Drunkenyeti:BAAANQADCgcIEAAAAA==.',
Du='Duckbeak:BAAANQAECgQIBQAAAA==.Duwork:BAABNQAECn8mAAIIAAkKNBykGAAAAwAIAAkKNBykGAAAAwAAAA==.',
['Dæ']='Dæmona:BAABNQAECn8qAAIbAAkKcRULKQBTAgAbAAkKcRULKQBTAgAAAA==.',
Eb='Ebk:BAAANQAECgcIDgAAAA==.Ebkx:BAAANQAECgIIAgAAAA==.',
El='Eladus:BAAANQAECgYIEQAAAA==.Elesus:BAAANQADCgIJAgABNQAECgkJLAAcANgdAA==.',
Em='Emblaze:BAAANQADCgUIBQAAAA==.Emrys:BAAANQADCggIBwAAAA==.',
En='Enhshaman:BAAANQAECgQICAABNQAFFAcIFgACABQcAA==.',
Ev='Evilinne:BAAANQADCgYIBgAAAA==.',
Fa='Faithpasse:BAABNQAECn8cAAINAAcKAQxeJgBBAQANAAcKAQxeJgBBAQAAAA==.',
Fe='Felondar:BAABNQAECn8aAAIbAAcK/QlwSQB6AQAbAAcK/QlwSQB6AQAAAA==.Ferarro:BAABNQAECn8WAAIRAAgK1B7XJwCZAgARAAgK1B7XJwCZAgAAAA==.',
Fi='Finnadin:BAAANQADCgcIDQAAAA==.Finns:BAAANQAECgYIDQAAAA==.Firulais:BAABNQAECn8eAAIQAAcK7RFejgDpAQAQAAcK7RFejgDpAQAAAA==.Fistuu:BAAANQADCgUIBQAAAA==.',
Fl='Flysky:BAACNQAFFH8UAAIdAAUKrxfhCQCLAQAdAAUKrxfhCQCLAQA1AAQKfycABB0ACQp1I4QGAD8DAB0ACQp1I4QGAD8DAB4ABAqtIIcOAFoBAB8ABQqPGusiAC0BAAAA.',
Fo='Foxsake:BAAANQADCgQIBAAAAA==.',
Fr='Freshpot:BAAANQAECgQIBAAAAA==.Frostwyrm:BAAANQADCgYIBgAAAA==.',
Fu='Fumbles:BAAANQAECgEIAgAAAA==.Futurefist:BAAANQADCggICAAAAA==.',
Ga='Galvis:BAAANQAECggIBwAAAA==.Garduuk:BAABNQAECn8iAAMJAAkKGxy+DQDxAgAJAAkKGxy+DQDxAgAIAAEKAACgnQBhAAAAAA==.',
Ge='Gearth:BAABNQAECn8bAAIgAAcKwhshFQASAgAgAAcKwhshFQASAgAAAA==.Ger:BAAANQADCgYIDAABNQADCggIEAASAAAAAA==.',
Gl='Glucose:BAAANQAECgYIDwAAAA==.',
Go='Gonah:BAAANQAECgUIEgAAAA==.Gotlieb:BAAANQAECgMIBgAAAA==.',
Gr='Gravey:BAABNQAECn8dAAIEAAcKlBvoNQAxAgAEAAcKlBvoNQAxAgAAAA==.Grogger:BAAANQADCgUIBQAAAA==.Grrahtahtah:BAACNQAFFH8WAAICAAcKFByBAwBOAgACAAcKFByBAwBOAgA1AAQKfyoAAwIACQreISUKADIDAAIACQreISUKADIDABAAAQo7EwhHAUkAAAAA.',
Gy='Gymble:BAAANQAECggIAQAAAA==.',
Ha='Hakkim:BAAANQADCggICAAAAA==.Hammerinfred:BAAANQAECgIIAwAAAA==.',
He='Heavyguard:BAAANQABCgIIAgAAAA==.',
Hi='Hidann:BAAANQAECggIBwABNQAECgkJGgAWAD0SAA==.Himeko:BAAANQAECgMICAABNQAFFAUIEwAGAMUbAA==.Hippayman:BAAANQAECgMIBwAAAA==.Hippysmasher:BAAANQAECgcIBwABNQAECggIHgAOALEWAA==.',
Ho='Holyhooters:BAABNQAECn8gAAIMAAkKkhhTTACsAgAMAAkKkhhTTACsAgAAAA==.Holypablo:BAAANQAECgQIBAABNQAECgkJIAAhAMMVAA==.Honour:BAABNQAECn8hAAIMAAgKWhqZYgBuAgAMAAgKWhqZYgBuAgAAAA==.',
Hr='Hrathdemon:BAABNQAECn8sAAMOAAkKqyAzCgA2AwAOAAkKqyAzCgA2AwAbAAIKfRebdwCUAAAAAA==.Hrathion:BAAANQAECgYIDQABNQAECgkJLAAOAKsgAA==.',
Hu='Hupa:BAABNQAECn8iAAIMAAcKZyNHXAB/AgAMAAcKZyNHXAB/AgAAAA==.Hurtsdonut:BAAANQAECgQIDAABNQAECgkJLAAcANgdAA==.Huulis:BAAANQADCggICAAAAA==.',
Ia='Iamheyo:BAAANQAECgcIEgAAAA==.',
Ic='Ickeetard:BAAANQADCgcJBwAAAA==.',
Id='Idiotbreath:BAAANQAECgYIDwAAAA==.',
Ie='Ieatcheeks:BAAANQAECgUIDQAAAA==.Ieyasu:BAEBNQAECn8rAAIIAAkKWhq9KACNAgAIAAkKWhq9KACNAgABNQAECgkJNQAUAAMiAA==.',
Ig='Ignitus:BAAANQAECgQIDAAAAA==.',
Ik='Ikuchi:BAAANQAECgQIBAAAAA==.',
Il='Illidornsina:BAAANQAECgQIBQABNQADCgEIAQASAAAAAA==.Illpownyou:BAAANQADCgcIBwABNQAECgcIFwAfAOAUAA==.',
In='Indigò:BAAANQAECgIIAgAAAA==.Insulinshot:BAAANQAECgIIAwAAAA==.',
Ir='Ironguard:BAAANQABCgMIAwAAAA==.',
It='Itsmagharszn:BAAANQADCgEIAQAAAA==.',
Ja='Jabronipie:BAAANQADCggIBQAAAA==.',
Je='Jessica:BAAANQAECgQICwAAAA==.',
Jh='Jhana:BAAANQADCggIEQAAAA==.',
Jj='Jjooaacchhim:BAAANQAECgQIBgAAAA==.',
Jo='Josh:BAAANQAECgIIAgAAAA==.',
Ju='Junglefever:BAAANQADCgYIBgAAAA==.',
Jy='Jyve:BAABNQAECn8rAAIQAAgKow8oewAVAgAQAAgKow8oewAVAgAAAA==.',
Ka='Kailin:BAAANQAECgIIAgAAAA==.Kailoon:BAAANQADCggICAAAAA==.Kakashi:BAAANQADCgYIDAAAAA==.Kalda:BAAANQAECgIIBAAAAA==.Kamadan:BAAANQAECgMIAwAAAA==.Kamanactali:BAAANQADCggIGQAAAA==.Kamele:BAAANQADCgQIAwABNQAECgUICwASAAAAAA==.Kaneko:BAEANQAECggIEwABNQAECgkJNQAUAAMiAA==.Katalina:BAABNQAECn8tAAMiAAcKIBdaDQDnAQAiAAcKCRdaDQDnAQAbAAYKwBEBUwBBAQAAAA==.',
Ke='Kelstormhoof:BAAANQADCgcIEQABNQAECgQIBAASAAAAAA==.',
Kh='Kham:BAABNQAECn8dAAIXAAkK6R6CAwAdAwAXAAkK6R6CAwAdAwAAAA==.',
Ki='Kialla:BAAANQAECgQIBAABNQAECggIIAAHAC8eAA==.Kirren:BAAANQADCgIIAgAAAA==.',
Kl='Klais:BAAANQADCgQIBQAAAA==.',
Ko='Kokeovrdose:BAAANQABCgQIBAABNQADCgYICgASAAAAAA==.Konet:BAAANQADCgMIAwAAAA==.',
La='Lavashiza:BAAANQAECgYIEQAAAA==.',
Le='Leadzorz:BAAANQAECgIIAgAAAA==.Leedaddydk:BAAANQADCgQIBAAAAA==.Leeoflight:BAAANQABCgQIBQAAAA==.Legday:BAAANQAECgUIBQAAAA==.Lesaelia:BAAANQAECgQIBAAAAA==.',
Li='Lightstorm:BAAANQAECgEIAQAAAA==.Liltotem:BAABNQAECn8qAAMTAAgKxBHBbwC4AQATAAgKxBHBbwC4AQAUAAQK7gfk3gDUAAAAAA==.Linaria:BAAANQADCgUIBQAAAA==.Lizzydk:BAAANQAECgMIAwAAAA==.Lizzymonk:BAABNQAECn8lAAIjAAkKgyF/AwBYAwAjAAkKgyF/AwBYAwAAAA==.',
Lo='Lockdownlol:BAABNQAECn8iAAMCAAcKySL2KAAAAgAQAAYKhCPKcgAoAgACAAYKqx32KAAAAgABNQAECgkJLwAPAEwgAA==.',
Lu='Luluh:BAAANQAECgQIDQAAAA==.',
Ma='Maddog:BAABNQAECn8YAAIVAAcKewvrHwBvAQAVAAcKewvrHwBvAQAAAA==.Maebell:BAAANQAECgYIEAABNQAECgkJLwAPAEwgAA==.Mageslayer:BAABNQAECn8gAAMZAAcKNBheGAAXAgAZAAcKNBheGAAXAgABAAEK5QkwnAA7AAAAAA==.Magicpewfred:BAAANQADCgQIBAAAAA==.Magrun:BAAANQADCgUJCQAAAA==.Maiggee:BAAANQAECgMIAwAAAA==.Matt:BAABNQAECn8qAAIQAAkKliBEGwAqAwAQAAkKliBEGwAqAwAAAA==.Mavrik:BAABNQAECn8gAAMLAAgKiwwqpAC+AQALAAgKLgwqpAC+AQAXAAQKrgpSHwDAAAAAAA==.',
Me='Meatmagic:BAAANQADCgIIAgAAAA==.Megapunk:BAAANQAECgMIAwAAAA==.Melanyie:BAAANQADCgMIAwAAAA==.Melfìce:BAAANQADCgYIBgAAAA==.Meudayr:BAABNQAECn8cAAIFAAkK1htvCQDaAgAFAAkK1htvCQDaAgAAAA==.',
Mi='Millarolly:BAAANQADCggIEAAAAA==.Mischifbomb:BAAANQADCgIIAgAAAA==.Mischifdk:BAAANQADCgIIAgAAAA==.Mischifdots:BAAANQADCgcIDwAAAA==.Mischifgg:BAABNQAECn8ZAAIhAAgKBxQfZADwAQAhAAgKBxQfZADwAQAAAA==.Mischïf:BAAANQADCgYICwAAAA==.Mittenss:BAAANQADCggICQAAAA==.',
Mn='Mndgblnfred:BAAANQADCgEIAQAAAA==.',
Mo='Mojorisinn:BAAANQAECgQIBAAAAA==.Moobear:BAABNQAECn8pAAIFAAgKlyNZBgApAwAFAAgKlyNZBgApAwAAAA==.Moogie:BAABNQAECn8nAAIPAAkKPBvIfwB/AgAPAAkKPBvIfwB/AgAAAA==.Moozlock:BAAANQAECgEIAQAAAA==.Morgiana:BAAANQAECgYIDwABNQAECggIAgASAAAAAA==.Moscovio:BAACNQAFFH8cAAMWAAYKGBTuCwCxAQAWAAUKaRXuCwCxAQAVAAIKdQ5aDwCYAAA1AAQKfy0AAxYACQo1Ia4mAOcCABYACQq8IK4mAOcCABUAAQqtGSRsAEYAAAAA.Mosspaws:BAAANQAECgUICAAAAA==.',
Mt='Mtndewyou:BAABNQAECn8fAAIkAAcKpRTpJAC1AQAkAAcKpRTpJAC1AQAAAA==.',
My='Myrothan:BAAANQAECgQIBwAAAA==.',
Na='Napok:BAAANQAECgUICwAAAA==.',
Ni='Nickimihoj:BAAANQAECgcIBwAAAA==.Nihr:BAAANQAECgUIBgAAAA==.Ninkarrak:BAAANQAECgIIAgAAAA==.',
Nm='Nme:BAABNQAECn8hAAIPAAgKJQqP2wDNAQAPAAgKJQqP2wDNAQAAAA==.',
No='Nocturnos:BAAANQAECgUICwAAAA==.Nonfiction:BAAANQAECgUIBQABNQAECgkJLwAMAOIZAA==.Novamancer:BAAANQAECgEIAQAAAA==.',
Nu='Nuph:BAAANQAECgQIBQAAAA==.',
Ny='Nymage:BAABNQAECn8jAAIGAAgKsRhDCABcAgAGAAgKsRhDCABcAgAAAA==.',
Og='Ogdaddy:BAAANQADCggICAAAAA==.',
Ok='Okaerisan:BAAANQADCgMIAwAAAA==.',
Ol='Olord:BAAANQADCgEIAgAAAA==.',
Op='Ophbel:BAAANQADCgMIAwABNQAECgUICQASAAAAAA==.',
Or='Orack:BAABNQAECn8cAAIJAAcKgRi+JAD6AQAJAAcKgRi+JAD6AQAAAA==.',
Ou='Outlast:BAAANQADCgYIBgAAAA==.',
Ow='Owch:BAAANQABCgIIAgABNQAECgkJHAAFANYbAA==.',
Pa='Panblind:BAACNQAFFH8TAAMOAAUKvx9PBgC3AQAOAAUKvx9PBgC3AQAiAAMKkhkIAwDlAAA1AAQKfycAAw4ACQqJIMkRANsCAA4ACQraHskRANsCACIAAwrlIqkYACMBAAAA.Pandington:BAAANQADCgQIBwAAAA==.Parmageddon:BAABNQAECn8mAAIEAAkKthvyKwBmAgAEAAkKthvyKwBmAgAAAA==.Parmrageiano:BAAANQAECgYICgABNQAECgkJJgAEALYbAA==.',
Pe='Peanought:BAABNQAECn8gAAQDAAgKWgwVTQB7AQADAAgK7wkVTQB7AQAEAAUKigrsigDRAAARAAMKkAngtQB+AAAAAA==.Peetfix:BAABNQAECn8fAAMUAAkKFRgRVwAbAgAUAAgKYxkRVwAbAgATAAQKZRvdnwAyAQAAAA==.Pepsipink:BAAANQAECgEIAQAAAA==.Pets:BAAANQAECgIIAgAAAA==.',
Ph='Phelon:BAAANQAECgYIBgABNQAFFAYIGAAlAJUgAA==.Phèdre:BAEANQAFFAEIAgABNQAFFAYIEQAMAG8SAA==.',
Pi='Picklegrip:BAABNQAECn8bAAILAAcKVRIqsQCdAQALAAcKVRIqsQCdAQAAAA==.Pijak:BAAANQAECgIIAgAAAA==.',
Pl='Planetina:BAAANQADCgcIBwAAAA==.',
Po='Poah:BAABNQAECn8UAAIYAAgKBx8LFgCdAgAYAAgKBx8LFgCdAgAAAA==.Portalcombat:BAAANQAECgIIAgAAAA==.',
Pr='Prettynhealz:BAAANQADCgIIAgAAAA==.Pruflas:BAAANQAECgEIAgAAAA==.',
Ps='Psycodk:BAAANQAECgYICAAAAA==.',
Pu='Pumpin:BAAANQAECgMIBAAAAA==.Punkthor:BAABNQAECn8YAAIjAAcK4xeIDwDzAQAjAAcK4xeIDwDzAQAAAA==.Purgemepappy:BAAANQADCgYIDAAAAA==.Putitinme:BAAANQABCgIIAgAAAA==.',
['Pø']='Pø:BAABNQAECn8YAAIYAAgKJA18LwCXAQAYAAgKJA18LwCXAQAAAA==.',
Qk='Qkn:BAAANQAECgIIAgAAAA==.',
Ra='Raf:BAABNQAECn8ZAAMUAAkKfSMCCwCNAwAUAAkKfSMCCwCNAwATAAIKixVx9wB2AAAAAA==.Ragnor:BAAANQAECgIIAgAAAA==.Ratoncita:BAAANQADCgUIBQAAAA==.Rayzee:BAAANQAECgEIAQAAAA==.',
Re='Reisar:BAAANQADCgMIAwAAAA==.Rennera:BAAANQADCgcIEgAAAA==.Revalation:BAAANQAECgcIEgAAAA==.',
Ri='Riachu:BAAANQAECgUIDQAAAA==.Ribeyejoe:BAAANQAECgQIBgAAAA==.',
Ro='Roadblock:BAAANQAECgcIEwAAAA==.Roboorc:BAAANQABCgEJAQAAAA==.Roken:BAAANQADCggICAAAAA==.Rorymcilroy:BAABNQAECn8VAAMTAAcKbRswVQAPAgATAAcKbRswVQAPAgAUAAMK9Q269QCiAAAAAA==.',
Sa='Sacrament:BAAANQAECggIDAABNQAFFAIIBQAYAPUaAA==.Sagan:BAEANQADCgQIBAABNQAECgcIEAASAAAAAA==.Saifrah:BAAANQADCggICQAAAA==.Sandasa:BAAANQAECgMIBAAAAA==.Sanivanth:BAAANQADCgQIBAAAAA==.Saragos:BAAANQAECgEIAQABNQAFFAUIEwAGAMUbAA==.Saucerdote:BAAANQAECgcIDwAAAA==.Saxon:BAAANQAECgEIAQAAAA==.',
Se='Selenix:BAAANQADCgYIBgAAAA==.Selinfinite:BAABNQAECn8YAAIbAAkKQSEEIACWAgAbAAkKQSEEIACWAgAAAA==.Selkie:BAABNQAECn8UAAIgAAYKHhJAHQCJAQAgAAYKHhJAHQCJAQAAAA==.Sephtis:BAAANQAECggICAAAAA==.Serenitynow:BAAANQAECgQIBAAAAA==.Sevenlions:BAAANQADCgEIAQAAAA==.',
Sg='Sgge:BAAANQADCgYIBgAAAA==.',
Sh='Shadowmaven:BAAANQADCgcIDgAAAA==.Shakakhan:BAABNQAECn8cAAMUAAcKHyG7TwA2AgAUAAYKYyC7TwA2AgATAAEKfg1nEQFBAAABNQAECgkJLwAPAEwgAA==.Shammer:BAEANQADCggIBgABNQAECgkJIgAEAC0eAA==.Shamshielder:BAEBNQAECn8iAAMEAAkKLR4VLABlAgAEAAkKLR4VLABlAgADAAMKIwuImQBZAAAAAA==.Sharick:BAAANQAECgIIAgAAAA==.Shawdrake:BAAANQAECgUIBQABNQAECggIKwATAPESAA==.Shawlee:BAABNQAECn8rAAMTAAgK8RKGagDIAQATAAgK8RKGagDIAQAUAAcKhAxWjwB6AQAAAA==.Shetmage:BAABNQAECn8kAAIPAAkKthLJjQBjAgAPAAkKthLJjQBjAgABNQAFFAUIEQAIAGEWAA==.Shettrah:BAACNQAFFH8RAAIIAAUKYRbmDQCFAQAIAAUKYRbmDQCFAQA1AAQKfykAAggACQrpHDoeANYCAAgACQrpHDoeANYCAAAA.Shottdown:BAAANQADCgUIBQAAAA==.Shwoobs:BAAANQAECgEIAQAAAA==.Shädes:BAAANQADCggICAAAAA==.',
Si='Sigasunanvil:BAAANQAECgQIBAAAAA==.Siickboy:BAAANQAECgIIAgAAAA==.Sijious:BAAANQADCggIHwAAAA==.Silhõuette:BAAANQADCggICAAAAA==.Singularity:BAAANQAECgUIDQABNQAECgkJLwAPAEwgAA==.',
Sk='Skanktank:BAABNQAECn8cAAILAAgKxiAGQQDEAgALAAgKxiAGQQDEAgAAAA==.Skora:BAAANQAECggIAgAAAA==.Skyland:BAAANQADCgcIBwABNQAFFAUIFAAdAK8XAA==.',
Sl='Slinkies:BAAANQADCgYICQABNQAECggIFAAPAHYbAA==.Slipknife:BAABNQAECn8WAAIBAAgKxxS5LwAfAgABAAgKxxS5LwAfAgAAAA==.',
So='Somi:BAABNQAECn8dAAIHAAkK4B3fHgD0AgAHAAkK4B3fHgD0AgAAAA==.',
St='Stabbystab:BAAANQAECgYIDQABNQADCgEIAgASAAAAAA==.Stabybara:BAAANQAECgQIBAABNQAECgYIDwASAAAAAA==.Stankydk:BAAANQAECgcIEgAAAA==.Stankyleg:BAABNQAFFH8OAAMQAAUKzAt0HADLAAACAAQKzAs6EwAHAQAQAAMK/AJ0HADLAAAAAA==.Stewie:BAABNQAECn8XAAIYAAgKOgqVNABsAQAYAAgKOgqVNABsAQAAAA==.Stinkbombs:BAAANQAECgUIBQAAAA==.Stinkies:BAAANQAECgUICQABNQAECggIFAAPAHYbAA==.',
Su='Subrogue:BAAANQAECgQICQABNQAFFAcIFgACABQcAA==.Sunlest:BAAANQADCgcIIAAAAA==.',
Sw='Swaayshooter:BAAANQAECgUIBQABNQAFFAMIBQABAOYRAA==.',
Sy='Sylphrena:BAABNQAECn8lAAIhAAkKfBpkNACTAgAhAAkKfBpkNACTAgAAAA==.Sylvanniia:BAAANQAECgUIBAABNQAFFAcIFgAeAMUXAA==.',
Ta='Tacow:BAAANQAECgUIDAAAAA==.Talethen:BAABNQAECn8XAAQfAAcK4BRmFwDQAQAfAAcK4BRmFwDQAQAeAAUKpgo8FQDZAAAdAAEKZwYvUQAoAAAAAA==.',
Te='Telaragehoof:BAAANQAECgQIBAAAAA==.',
Th='Thedrood:BAABNQAECn8pAAIJAAkKrh1LDgDqAgAJAAkKrh1LDgDqAgAAAA==.Thorfyna:BAAANQADCggICAAAAA==.',
Ti='Tiptronic:BAAANQAECgQIBQAAAA==.',
To='Tohk:BAACNQAFFH8PAAIbAAUKqRzvCACbAQAbAAUKqRzvCACbAQA1AAQKfygAAhsACQqeIV8TAAADABsACQqeIV8TAAADAAAA.Tollee:BAAANQAECgQIBAAAAA==.Tontiamat:BAABNQAECn8mAAIfAAgKtRGeFAAAAgAfAAgKtRGeFAAAAgAAAA==.Tontier:BAAANQAECgUIDAABNQAECggIJgAfALURAA==.Tormero:BAAANQADCgcIBwAAAA==.Totembeans:BAAANQAECgQIBQAAAA==.Touchyfred:BAAANQAECgEIAQAAAA==.Toxicfury:BAAANQABCgUIBAAAAA==.',
Tr='Traash:BAAANQABCgIIAgAAAA==.Treily:BAAANQAECgMIDwAAAA==.Tricket:BAAANQAECgQICAAAAA==.Tristani:BAAANQADCgEIAQAAAA==.Trolloladin:BAAANQADCggJDwAAAA==.Truestorm:BAABNQAECn8eAAIMAAgKBgiOzAB8AQAMAAgKBgiOzAB8AQAAAA==.',
Tu='Tuchi:BAABNQAECn8ZAAIPAAgKTxxltQAXAgAPAAgKTxxltQAXAgAAAA==.',
['Tà']='Tàcobelle:BAAANQAECgQIBAAAAA==.',
Va='Valeah:BAAANQADCgEIAQAAAA==.Vanicton:BAABNQAECn8fAAITAAgKqyFvGQAKAwATAAgKqyFvGQAKAwAAAA==.',
Ve='Ve:BAABNQAECn8cAAMTAAkKjRv1OAB4AgATAAgK+Br1OAB4AgAgAAYKTxgHHACeAQAAAA==.Vegh:BAABNQAECn8qAAIbAAgK8SCiEQAPAwAbAAgK8SCiEQAPAwAAAA==.Velaei:BAAANQAECgEJAQAAAA==.Veldcat:BAAANQAECgYIDAAAAA==.Velddk:BAAANQADCggICAAAAA==.Veriale:BAAANQAECgIIAgAAAA==.Verra:BAABNQAECn8aAAIMAAcKZRO8twCoAQAMAAcKZRO8twCoAQAAAA==.',
Vi='Vitriol:BAAANQAECgMIBAAAAA==.',
Wa='Wampa:BAAANQAECgEIAgAAAA==.Wanderblue:BAAANQAECgMIAwAAAA==.Wangstah:BAABNQAECn8XAAIQAAkKbhCPdAAkAgAQAAkKbhCPdAAkAgAAAA==.Warshaw:BAAANQABCgEIAQABNQAECggIKwATAPESAA==.Wartogoteam:BAABNQAECn81AAILAAkKURs7SACuAgALAAkKURs7SACuAgAAAA==.Waytogoteam:BAAANQADCgMIAwAAAA==.',
We='Weiss:BAACNQAFFH8TAAMGAAUKxRtlBgCpAAAPAAQKnh71JQBPAQAGAAIKaBplBgCpAAA1AAQKfyYAAg8ACQpgIhgsADcDAA8ACQpgIhgsADcDAAAA.',
Wf='Wf:BAABNQAECn8vAAQgAAkKFBGKFQAMAgAgAAgKXxGKFQAMAgATAAYKdwd5wADkAAAUAAEKUg8cMQE0AAAAAA==.',
Wo='Woog:BAAANQADCgYIBgAAAA==.Worsthunterx:BAAANQAFFAEIAgABNQAFFAUIDQAlAGwjAA==.',
Wy='Wyldspirit:BAAANQAECgUIEAAAAA==.Wyreless:BAAANQAECgUIEQABNQAECgkJKwAFADobAA==.',
Ya='Yaass:BAAANQADCggJCAABNQAECgkJLwAgABQRAA==.Yagrum:BAAANQAECgEJAQAAAA==.Yahikko:BAABNQAECn8aAAIWAAkKPRIzdwD5AQAWAAkKPRIzdwD5AQAAAA==.',
Ye='Yem:BAAANQAECggIEQAAAA==.',
Yo='Yoddaa:BAABNQAECn8dAAMcAAkKdhdtDQBcAQAhAAkK3BAATgA3AgAcAAQKhR5tDQBcAQABNQAECgcIIQAWABAfAA==.',
Ze='Zergen:BAAANQADCgYIBgAAAA==.Zetsu:BAAANQAECggIDQABNQAECgkJGgAWAD0SAA==.',
Zh='Zhenya:BAABNQAECn8kAAIPAAkKUw5dvwAEAgAPAAkKUw5dvwAEAgAAAA==.',
Zu='Zuga:BAAANQAECgYICwAAAA==.',
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
