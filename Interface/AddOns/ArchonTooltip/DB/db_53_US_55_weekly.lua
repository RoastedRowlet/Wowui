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

local lookup = {'Rogue-Assassination','Shaman-Elemental','Paladin-Retribution','Hunter-Marksmanship','DeathKnight-Frost','DeathKnight-Blood','Druid-Guardian','Mage-Frost','Paladin-Holy','DemonHunter-Devourer','Mage-Arcane','Druid-Balance','Druid-Restoration','Warrior-Protection','Warrior-Arms','Monk-Mistweaver','Hunter-BeastMastery','DeathKnight-Unholy','Shaman-Restoration','Priest-Shadow','Priest-Holy','Warlock-Destruction','Warlock-Demonology','Warrior-Fury','Monk-Windwalker','Unknown-Unknown','Rogue-Subtlety','Warlock-Affliction','DemonHunter-Havoc','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','DemonHunter-Vengeance','Druid-Feral','Paladin-Protection','Monk-Brewmaster','Hunter-Survival','Priest-Discipline','Mage-Fire',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abc:BAAANQADCgIIAgAAAA==.',
Ac='Acheniris:BAAANQAECgQICQAAAA==.',
Ae='Aeviee:BAAANQADCgQJBAAAAA==.',
Ag='Aglain:BAAANQAECggIAQAAAA==.Agrippa:BAABNQAECn8gAAIBAAoKhw5VOQDvAQABAAoKhw5VOQDvAQAAAA==.',
Ah='Ahndhrez:BAABNQAECn8mAAICAAoK7B3zEgCyAgACAAoK7B3zEgCyAgAAAA==.',
Ai='Aidric:BAABNQAECn8VAAIDAAcKYREopABFAQADAAcKYREopABFAQAAAA==.Airwavez:BAACNQAFFH8PAAIEAAYKshP9CwB/AQAEAAYKshP9CwB/AQA1AAQKf0UAAgQACgpaG1IKAHQCAAQACgpaG1IKAHQCAAAA.',
Ak='Akriel:BAAANQAECgcIDwAAAA==.',
Al='Albrecht:BAAANQAECgcIDAAAAA==.Aldeor:BAAANQAECgIIAgAAAA==.Altra:BAACNQAFFH8JAAIFAAMKqQVjDwCvAAAFAAMKqQVjDwCvAAA1AAQKfy8AAwUACgo/Fk0uAC8CAAUACgo/Fk0uAC8CAAYAAQoAAF3aACQAAAAA.Alumit:BAAANQAECgYJDwAAAA==.',
Am='Amoeta:BAABNQAECn85AAIHAAoKCx1ICwC4AgAHAAoKCx1ICwC4AgAAAA==.',
An='Andor:BAAANQADCgcIEAAAAA==.Angelique:BAAANQAECgUIDwAAAA==.Angry:BAAANQADCgYICgAAAA==.Angryapples:BAAANQAECgQJBQAAAA==.Annihilation:BAAANQADCgUIBQAAAA==.',
Ap='Approved:BAAANQADCgYIBQAAAA==.',
Ar='Arconos:BAAANQADCgYIDAABNQAFFAcIFQAIAP0WAA==.Arcstorm:BAAANQAECgEIAQAAAA==.',
As='Ashguard:BAAANQADCgcIDAAAAA==.Asomyrh:BAABNQAECn8iAAIJAAkKng37aQDZAQAJAAkKng37aQDZAQAAAA==.',
Au='Aurial:BAAANQADCgMIAwAAAA==.Auriala:BAAANQAECgcIEgAAAA==.',
Az='Azuriae:BAAANQAECgQIBAAAAA==.',
Ba='Babygirl:BAAANQAECgYICQAAAA==.Baelan:BAAANQAECgQIBAAAAA==.Bananer:BAAANQAECgQICAAAAA==.Banonzarath:BAAANQADCggICAAAAA==.Barrysoetoro:BAAANQADCgcIDAAAAA==.Battlemagic:BAAANQAECgYIBgABNQAECgoKKAAKAHkVAA==.Baulie:BAAANQAECgQIBAAAAA==.',
Bb='Bbqlol:BAAANQAECgQICQABNQAECgoKPQALAPYhAA==.',
Be='Beefstick:BAAANQADCggIJgAAAA==.Bekroh:BAABNQAECn8YAAMMAAcKfhglSADKAQAMAAcKfhglSADKAQANAAEKbASufAAlAAAAAA==.Bestt:BAAANQAECgcICwAAAA==.',
Bi='Bigdaddyd:BAABNQAECn8nAAMOAAgK/BF5GwDuAAAPAAgKaA32ggBJAQAOAAcKkhF5GwDuAAAAAA==.Bigdonk:BAAANQADCggJCAAAAA==.Bigfoxlilsox:BAAANQADCgEIAQAAAA==.Bigocagler:BAAANQADCggIFwAAAA==.Bioodlion:BAABNQAECn8qAAIDAAkKgQ4tvgCgAQADAAkKgQ4tvgCgAQAAAA==.Bipolar:BAABNQAECn8oAAIQAAgKqAWsHAAKAQAQAAgKqAWsHAAKAQAAAA==.Bippysmasher:BAABNQAECn8oAAIKAAoKeRWcHwBSAgAKAAoKeRWcHwBSAgAAAA==.Bishmanistic:BAAANQAECgUIDwAAAA==.',
Bl='Blacblood:BAAANQAECgEIAQAAAA==.Blastemis:BAAANQAECgMIBgAAAA==.Blindweiss:BAAANQADCgcIBwABNQAFFAcIFQAIAP0WAA==.Blinkies:BAABNQAECn8ZAAILAAkKvBs9hAB2AgALAAkKvBs9hAB2AgAAAA==.',
Bo='Bontao:BAACNQAFFH8RAAIRAAcKQBQbCgCpAQARAAcKQBQbCgCpAQA1AAQKf0AAAhEACgo1IYoUANgCABEACgo1IYoUANgCAAAA.Bontaopanda:BAAANQADCgcIEwABNQAFFAcIEQARAEAUAA==.Boomies:BAAANQADCgQJBAABNQAECgkJGQALALwbAA==.Borstenne:BAABNQAECn8kAAISAAkK9iPhCgBkAwASAAkK9iPhCgBkAwAAAA==.Bosco:BAAANQADCgQIBAAAAA==.',
Br='Bresemage:BAAANQAECgQIBAABNQAECgoKQAATAF4jAQ==.Bresepls:BAACNQAFFH8FAAIDAAIKAQyLHwCAAAADAAIKAQyLHwCAAAA1AAQKfx0AAwMACQoSGcdlAMkBAAMACArpGsdlAMkBAAkABAqsFkfOAN8AAAE1AAQKCgpAABMAXiMA.Breseshh:BAABNQAECn9AAAMTAAoKXiPtCAB6AwATAAoKXiPtCAB6AwACAAYKNxNsfgDbAAAAAA==.Brickbeard:BAAANQAECgQIAwAAAA==.Brickbow:BAAANQADCgYIBgAAAA==.Brickette:BAAANQAECggIEAABNQAFFAcIFgAJAIENAA==.Bricklicker:BAAANQAECgQIAwAAAA==.Bricksquad:BAAANQAECgcIDgAAAA==.Brickthrow:BAACNQAFFH8WAAIJAAcKgQ1NDgB+AQAJAAcKgQ1NDgB+AQA1AAQKfzoAAwkACgpgIOEVANwCAAkACgpgIOEVANwCAAMAAQr5D/RfAT0AAAAA.Bringdapain:BAAANQAECgUICQAAAA==.',
Bu='Budhistpalm:BAAANQAECgMIAwAAAA==.Burgerburn:BAAANQAECgMICAAAAA==.',
By='Bytheway:BAABNQAECn8YAAIUAAgKThUDKwDPAQAUAAgKThUDKwDPAQAAAA==.',
['Bé']='Béstt:BAABNQAECn8lAAMCAAoKPRr2KgDUAgACAAoKPRr2KgDUAgATAAIKDgj9yABcAAAAAA==.',
Ca='Cadilak:BAACNQAFFH8JAAINAAMK0AwxCwDFAAANAAMK0AwxCwDFAAA1AAQKfzAAAw0ACgp8GUAXAIcCAA0ACgp8GUAXAIcCAAwAAwoaD4qNAKAAAAAA.Caelesti:BAABNQAECn8WAAMUAAkKVg9gIABJAQAUAAgK/wtgIABJAQAVAAIKYgZp/wAtAAAAAA==.Camlin:BAAANQADCggIDgAAAA==.Cassanndra:BAEANQAECggIAwABNQAFFAMIBgADACUKAA==.Catrina:BAEANQAECggIAQABNQAFFAMIBgADACUKAA==.',
Ch='Cheapshotjoe:BAAANQADCgEIAQAAAA==.Chelbur:BAAANQAECgIIAwAAAA==.Chowderhead:BAABNQAECn8tAAMWAAoKvRiTCQBgAgAWAAkKqROTCQBgAgAXAAcKQhb5jgAHAQAAAA==.',
Ci='Cileb:BAABNQAECn8lAAILAAoK+B+qJwBDAwALAAoK+B+qJwBDAwAAAA==.Civik:BAAANQAECgQIAwAAAA==.',
Co='Cocio:BAABNQAECn8dAAIPAAcKdBS6nQDSAQAPAAcKdBS6nQDSAQABNQAECgoKRQAPAIgbAA==.Conchsniffer:BAACNQAFFH8GAAIDAAMKuA+2EgDOAAADAAMKuA+2EgDOAAA1AAQKf0cAAwMACgp/IUIfAMQCAAMACgp/IUIfAMQCAAkAAgrPC0PUAEIAAAAA.Conrack:BAAANQADCggICAAAAA==.Copperit:BAABNQAECn8pAAMGAAkKaSWtAwBCAwAGAAkKaSWtAwBCAwAFAAEKQh8amwBdAAAAAA==.Cornburglar:BAABNQAECn9FAAMPAAoKiBvQMABVAgAPAAoKJBvQMABVAgAYAAIKziDYHwC+AAAAAA==.Corrona:BAEANQAECgMIAgABNQAFFAMIBgADACUKAA==.Cowtaclysmic:BAAANQAECgYIBgAAAA==.',
Cr='Creatlach:BAAANQADCgYIBgABNQAFFAcIFwATAPQaAA==.Crime:BAABNQAECn8jAAIBAAoKoRydBwBQAgABAAoKoRydBwBQAgABNQAFFAIIBwAZANMeAA==.Crunchwrap:BAABNQAECn8UAAIMAAYK+ATtdwDrAAAMAAYK+ATtdwDrAAAAAA==.',
Ct='Cthul:BAAANQADCggICAAAAA==.',
Cu='Curseus:BAAANQAECgEIAQAAAA==.',
['Câ']='Câlisse:BAACNQAFFH8HAAIZAAIK0x6jCgCiAAAZAAIK0x6jCgCiAAA1AAQKf0oAAhkACgqGJLADAJoDABkACgqGJLADAJoDAAAA.',
Da='Daddiedk:BAABNQAECn8dAAIFAAcKlBrcPQDVAQAFAAcKlBrcPQDVAQAAAA==.Dahealamon:BAAANQAECgMIBQAAAA==.Daiyan:BAAANQAECgMIAgABNQAECgcIEgAaAAAAAA==.Damncats:BAABNQAECn8uAAIYAAgKyQ+0EACbAQAYAAgKyQ+0EACbAQAAAA==.Dandinn:BAAANQADCggICAAAAA==.Danielsboone:BAABNQAECn8eAAIRAAUKSxCesAAMAQARAAUKSxCesAAMAQAAAA==.Daowa:BAAANQABCgEIAQAAAA==.Darkmare:BAACNQAFFH8IAAMbAAMKagZiGQB/AAAbAAIKwgZiGQB/AAABAAEKuAUcEAAwAAA1AAQKfy4AAxsACgpXFkERAG0CABsACgoTFUERAG0CAAEAAgrfCtSQAG8AAAAA.Darknemesis:BAAANQAECgQICAABNQAECgUIBwAaAAAAAA==.Darksteps:BAAANQADCgQIBAAAAA==.',
De='Deadhippocow:BAABNQAECn8eAAINAAoK2R24GQBtAgANAAoK2R24GQBtAgAAAA==.Dearth:BAEBNQAECn8VAAIDAAgKgguWFgH6AAADAAgKgguWFgH6AAABNQAFFAMIBgADACUKAA==.Deathbane:BAABNQAECn8eAAMWAAkKjg7fMgD6AAAXAAkK5w3RhQDYAQAWAAUKxAnfMgD6AAAAAA==.Deathwavez:BAABNQAECn8UAAIFAAkKGQwdWQD0AAAFAAkKGQwdWQD0AAAAAA==.Deckard:BAEANQAECggICQABNQAFFAMIBgADACUKAA==.Demayy:BAABNQAECn81AAIQAAoK0BZKCQCEAgAQAAoK0BZKCQCEAgAAAA==.Demona:BAAANQAECgUICgAAAA==.Demonix:BAABNQAECn8yAAMXAAkKaR67KwA0AgAXAAkKFh67KwA0AgAcAAUKmhzrDACPAQAAAA==.Demonshades:BAAANQADCgMIBAAAAA==.Derptron:BAABNQAECn8lAAIIAAoKvRW4CABRAgAIAAoKvRW4CABRAgAAAA==.',
Di='Diluted:BAAANQAECgcIEwABNQAECgoKPQALAPYhAA==.Dilutedqt:BAABNQAECn89AAILAAoK9iGWLQAzAwALAAoK9iGWLQAzAwAAAA==.Dilutedret:BAABNQAECn8aAAMDAAoKJhWMlAD7AQADAAoKJhWMlAD7AQAJAAEKMhbt1ABBAAABNQAECgoKPQALAPYhAA==.Dinobrass:BAABNQAECn9DAAIRAAkKsBvVNQA/AgARAAkKsBvVNQA/AgAAAA==.Dirge:BAABNQAECn8iAAISAAoKiA9zRQADAgASAAoKiA9zRQADAgAAAA==.Dirtylöbster:BAABNQAECn8uAAILAAkKZh6nTADoAgALAAkKZh6nTADoAgAAAA==.Disabel:BAAANQADCggICAAAAA==.Distracto:BAAANQAECggIEAAAAA==.',
Dj='Djinsurgent:BAABNQAECn8oAAMSAAgKzxqBJgB8AQASAAgKcxmBJgB8AQAGAAgKixPFNABKAQAAAA==.',
Dl='Dltdjr:BAAANQAECgUIDQABNQAECgoKPQALAPYhAA==.',
Do='Donnybrook:BAAANQAECgYICwAAAA==.Doobysnacks:BAABNQAECn8oAAIGAAkKxiP8CgDKAgAGAAkKxiP8CgDKAgAAAA==.Doolittle:BAAANQAECgMICgAAAA==.Dorfies:BAAANQADCgcJCAABNQAECgkJGQALALwbAA==.Dorns:BAAANQAECgYICgAAAA==.',
Dr='Dragondees:BAAANQADCgYIBAAAAA==.Dralock:BAAANQAECgQIBAABNQAECgQIAwAaAAAAAA==.Dreamyeti:BAAANQADCgEIAQAAAA==.Dreats:BAAANQAECgMIBAAAAA==.Drewmee:BAABNQAECn8WAAIDAAkKmgZF3QBgAQADAAkKmgZF3QBgAQAAAA==.Droovani:BAAANQAECgUICgABNQAECgkJFgADAJoGAA==.Drunkenyeti:BAAANQADCgcIEAAAAA==.',
Du='Duckbeak:BAAANQAECgQIBQAAAA==.Duwork:BAABNQAECn8tAAIMAAoKeR3zGAAAAwAMAAoKeR3zGAAAAwAAAA==.',
['Dæ']='Dæmona:BAABNQAECn8uAAIdAAoKkxSsKQBTAgAdAAoKkxSsKQBTAgAAAA==.',
Eb='Ebk:BAAANQAECgcIDgAAAA==.Ebkx:BAAANQAECgIIAgAAAA==.',
El='Eladus:BAAANQAECgYIEQAAAA==.Elesus:BAAANQADCgIJAgABNQAECggICgAaAAAAAA==.',
Em='Emblaze:BAAANQADCgUIBQAAAA==.Emrys:BAAANQADCggIBwABNQAECgkJKQARAH8SAA==.',
En='Enhshaman:BAAANQAECggIEAABNQAFFAcIHAAEABQcAA==.',
Ev='Evilinne:BAAANQAECgQIBQAAAA==.',
Fa='Faithpasse:BAABNQAECn8dAAIQAAcKAQzSJgBBAQAQAAcKAQzSJgBBAQAAAA==.',
Fe='Felondar:BAABNQAECn8mAAIdAAoK0gkCLQBsAQAdAAoK0gkCLQBsAQAAAA==.Ferarro:BAABNQAECn8WAAISAAgK1B48KACZAgASAAgK1B48KACZAgAAAA==.',
Fi='Finnadin:BAAANQADCgcIDQAAAA==.Finns:BAABNQAECn8WAAIHAAgKnAuYKwD3AAAHAAgKnAuYKwD3AAAAAA==.Firulais:BAABNQAECn8pAAIRAAkKfxKYWwDNAQARAAkKfxKYWwDNAQAAAA==.Fistuu:BAAANQADCgUIBQAAAA==.',
Fl='Flysky:BAACNQAFFH8WAAIeAAcKSBYdCgCKAQAeAAcKSBYdCgCKAQA1AAQKfzAABB4ACgo5I48GAD4DAB4ACgo5I48GAD4DAB8ABQoHHq0OAFoBACAABQqPGiojACwBAAAA.',
Fo='Foxsake:BAAANQADCgQIBAAAAA==.',
Fr='Freshpot:BAAANQAECgQICAAAAA==.Frostuss:BAAANQAECgIIBAAAAA==.Frostwyrm:BAAANQADCgYIBgAAAA==.Frènchtoast:BAAANQAECgEIAQABNQAECgoKHgANANkdAA==.',
Fu='Fumbles:BAAANQAECgEIAwAAAA==.Furysbane:BAAANQADCgMIAgAAAA==.Futurefist:BAAANQADCggICAAAAA==.',
Ga='Gabtvrdruid:BAAANQADCgEIAQAAAA==.Galvis:BAAANQAECggICgAAAA==.Garduuk:BAABNQAECn8nAAMNAAoKmhv7DQDxAgANAAoKmhv7DQDxAgAMAAMKJBUcWwCKAAAAAA==.',
Ge='Gearth:BAABNQAECn8bAAIhAAcKwhtsFQARAgAhAAcKwhtsFQARAgAAAA==.Ger:BAAANQADCgYIDAABNQAECgoKOAALACcQAA==.',
Gl='Glucose:BAABNQAECn8iAAIXAAoKLhXjPgDnAQAXAAoKLhXjPgDnAQAAAA==.',
Go='Gonah:BAABNQAECn8WAAINAAYKGxXZOABXAQANAAYKGxXZOABXAQAAAA==.Gotlieb:BAAANQAECgMIBgAAAA==.',
Gr='Gravey:BAABNQAECn8dAAIGAAcKlBt0NgAxAgAGAAcKlBt0NgAxAgAAAA==.Grogger:BAAANQADCgUIBQAAAA==.Grrahtahtah:BAACNQAFFH8cAAIEAAcKFByvAwBOAgAEAAcKFByvAwBOAgA1AAQKfy4AAwQACgrIIVgKADEDAAQACgrIIVgKADEDABEAAQo7E0FLAUkAAAAA.',
Gy='Gymble:BAAANQAECggIAQAAAA==.',
Ha='Hakkim:BAAANQADCggICAAAAA==.Hammerinfred:BAAANQAECgQIBwAAAA==.',
He='Heavyguard:BAAANQABCgIIAgAAAA==.Helhunter:BAABNQAECn8YAAIKAAoKdg3jFwDCAQAKAAoKdg3jFwDCAQAAAA==.',
Hi='Hidann:BAAANQAECggIBwABNQAECgoKGwAXAFkSAA==.Himeko:BAAANQAECgQIDAABNQAFFAcIFQAIAP0WAA==.Hippayman:BAAANQAECgQICQAAAA==.Hippysmasher:BAAANQAECggIEAABNQAECgoKKAAKAHkVAA==.',
Ho='Holyhooters:BAABNQAECn8xAAIDAAoKIxvbTQCrAgADAAoKIxvbTQCrAgAAAA==.Holypablo:BAAANQAECgcIEQABNQAECgoKKQAVAG8XAA==.Honour:BAABNQAECn8yAAIDAAoKpBs4PABHAgADAAoKpBs4PABHAgAAAA==.',
Hr='Hrathadin:BAAANQAECggIDQABNQAFFAMIBgAdAOoYAA==.Hrathdemon:BAACNQAFFH8GAAMdAAMK6hjACgDmAAAdAAMKXxTACgDmAAAKAAEK0RuSEwBWAAA1AAQKf0EABAoACgoBIVUKADUDAAoACQqrIFUKADUDAB0ACQqMHd0MALACACIABwoIHy8GAAsCAAAA.Hrathion:BAAANQAECgYIDQABNQAFFAMIBgAdAOoYAA==.Hrathman:BAAANQAECgMIBwABNQAFFAMIBgAdAOoYAA==.',
Hu='Huntermik:BAAANQADCgUIBQAAAA==.Hupa:BAABNQAECn8iAAIDAAcKZyM2XgB+AgADAAcKZyM2XgB+AgAAAA==.Hurtsdonut:BAAANQAECgQIDAABNQAECggICgAaAAAAAA==.Huulis:BAAANQADCggICAAAAA==.',
Ia='Iamheyo:BAABNQAECn8fAAMJAAoKDBMDVwAUAgAJAAoKDBMDVwAUAgADAAUKcxM9BwGmAAAAAA==.',
Ic='Ickeetard:BAAANQADCgcJBwAAAA==.',
Id='Idiotbreath:BAAANQAECgYIDwAAAA==.',
Ie='Ieatcheeks:BAAANQAECgUIEAAAAA==.Ieyasu:BAECNQAFFH8IAAIMAAMKGwaxEQC3AAAMAAMKGwaxEQC3AAA1AAQKfzMAAwwACgoIGzApAI0CAAwACgoIGzApAI0CACMAAQoAAH1OAAAAAAE1AAUUBQgLAAIAdRQA.',
Ig='Ignitus:BAAANQAECgQIDQAAAA==.',
Ik='Ikuchi:BAABNQAECn8bAAIeAAoKKAQnGgAZAQAeAAoKKAQnGgAZAQAAAA==.',
Il='Illidornsina:BAABNQAECn8VAAIdAAYKphKbNQA1AQAdAAYKphKbNQA1AQABNQAECgYICgAaAAAAAA==.Illpownyou:BAAANQADCgcIBwABNQAECggIHwAgAKETAA==.',
In='Indigò:BAAANQAECgIIAgAAAA==.Insulinshot:BAAANQAECgIIAwAAAA==.',
Ir='Ironguard:BAAANQAECgEIAwAAAA==.',
It='Itsmagharszn:BAAANQADCgEIAQAAAA==.',
Ja='Jabronipie:BAAANQADCggIBQAAAA==.Jaliano:BAAANQADCgYIBgABNQAECgkJKwATAAIMAA==.Jameyjasta:BAAANQAECgQIDQAAAA==.',
Je='Jeffblades:BAAANQABCgQIBQAAAA==.Jellyroll:BAAANQAECgQIBAAAAA==.Jessica:BAAANQAECgQIEwAAAA==.',
Jh='Jhana:BAAANQADCggIGQAAAA==.',
Ji='Jingojengo:BAAANQAECgIICQAAAA==.',
Jj='Jjooaacchhim:BAAANQAECgQIEQAAAA==.',
Jo='Josh:BAAANQAECgMIBwAAAA==.',
Ju='Junglefever:BAAANQADCgYIBgAAAA==.',
Jy='Jyve:BAABNQAECn8wAAIRAAkKQhERfQAUAgARAAkKQhERfQAUAgAAAA==.',
Ka='Kadista:BAAANQAECgcICAAAAA==.Kailin:BAAANQAECgMIBQAAAA==.Kailoon:BAAANQADCggICAAAAA==.Kakashi:BAAANQADCgYIDAAAAA==.Kalda:BAAANQAECgMIBgAAAA==.Kamadan:BAAANQAECgMIAwAAAA==.Kamanactali:BAAANQAECgMIBQAAAA==.Kamele:BAAANQAECgEIAQABNQAECgcIEgAaAAAAAA==.Kaneko:BAEBNQAECn8qAAMkAAkKOiNJAwAsAwAkAAkKliJJAwAsAwADAAkKph5AOABVAgABNQAFFAUICwACAHUUAA==.Kardiz:BAAANQADCgUIBQABNQAECggIBAAaAAAAAA==.Katalina:BAABNQAECn88AAMiAAoK/xMVCAC/AQAiAAoK/xMVCAC/AQAdAAYKwBH+UwBBAQAAAA==.',
Ke='Kelstormhoof:BAAANQADCgcIEQABNQAECgUIBwAaAAAAAA==.',
Kh='Kham:BAACNQAFFH8GAAIYAAUKuQthAQDBAAAYAAUKuQthAQDBAAA1AAQKfzMAAhgACgrsIUgCAOoCABgACgrsIUgCAOoCAAAA.',
Ki='Kialla:BAABNQAECn8WAAIVAAoKqRjxGgDSAgAVAAoKqRjxGgDSAgAAAA==.Kirren:BAAANQADCgIIAgAAAA==.',
Kl='Klais:BAAANQADCgQIBQAAAA==.',
Ko='Kokeovrdose:BAAANQABCgQIBAABNQADCgYICgAaAAAAAA==.Konet:BAAANQADCgQIBAAAAA==.Korrath:BAAANQAECgQICAABNQAECgUIBQAaAAAAAA==.',
Ky='Kyle:BAAANQAECgEIAQAAAA==.',
La='Lavashiza:BAAANQAECgYIEQAAAA==.',
Le='Leadzorz:BAAANQAECgMICgAAAA==.Leedaddydk:BAAANQAECgEIAgAAAA==.Leeoflight:BAAANQABCgQIBQAAAA==.Legday:BAAANQAECgUIBgAAAA==.Lesaelia:BAAANQAECgUIDAAAAA==.',
Li='Lightstorm:BAAANQAECgEIAQAAAA==.Liltotem:BAABNQAECn85AAMTAAoKeBKZSgC2AQATAAoKeBKZSgC2AQACAAQK7gd64QDUAAAAAA==.Linaria:BAAANQADCgUIBQAAAA==.Lizzydk:BAAANQAECgMIAwAAAA==.Lizzymonk:BAACNQAFFH8JAAIlAAMK/hmvAwDrAAAlAAMK/hmvAwDrAAA1AAQKfy0AAiUACgraIYoDAFcDACUACgraIYoDAFcDAAAA.',
Lo='Lockdownlol:BAABNQAECn81AAQRAAkKvCKQMwBHAgARAAgK2iOQMwBHAgAEAAcKVh1tKQD/AQAmAAEKAABZEwAAAAABNQAECgoKPQALAPYhAA==.Louisbraille:BAAANQAECgUIBQAAAA==.Lowe:BAAANQAECgEIAwAAAA==.',
Lu='Luluh:BAAANQAECgQIDQAAAA==.',
Ma='Maddog:BAABNQAECn8aAAIWAAgKNgodIABvAQAWAAgKNgodIABvAQAAAA==.Maebell:BAABNQAECn8lAAISAAgKIyKxEABQAgASAAgKIyKxEABQAgABNQAECgoKPQALAPYhAA==.Mageslayer:BAABNQAECn8qAAMbAAkK5RWsGAAWAgAbAAkK5RWsGAAWAgABAAEK5QnRnwA7AAAAAA==.Magicpewfred:BAAANQADCgQIBAAAAA==.Magrun:BAAANQADCgUJCQAAAA==.Mahalleinr:BAAANQAECgEIAwAAAA==.Maiggee:BAAANQAECgcIDAAAAA==.Matt:BAACNQAFFH8JAAIRAAMKig+mEwDRAAARAAMKig+mEwDRAAA1AAQKfzQAAhEACgopIecbACgDABEACgopIecbACgDAAAA.Mavrik:BAABNQAECn81AAMPAAoK/Q3xYwCaAQAPAAoKJg3xYwCaAQAYAAYKTQu0HwDAAAAAAA==.',
Me='Meatmagic:BAAANQAECgUIBwAAAA==.Megapunk:BAAANQAECgQIEQAAAA==.Melanyie:BAAANQADCgMIAwAAAA==.Melfìce:BAAANQADCgYIBgAAAA==.Meudayr:BAEBNQAECn8kAAIHAAoKpBySCQDbAgAHAAoKpBySCQDbAgAAAA==.Meåtheåd:BAAANQADCgcIBwABNQAECgUIBwAaAAAAAA==.',
Mi='Millarolly:BAAANQADCggIEAAAAA==.Mischifbomb:BAAANQAECgIIAgAAAA==.Mischifdk:BAAANQADCgIIAgAAAA==.Mischifdots:BAAANQADCgcIDwAAAA==.Mischifgg:BAABNQAECn8cAAIVAAoKShJvZQDvAQAVAAoKShJvZQDvAQAAAA==.Mischïf:BAAANQADCgYICwAAAA==.Mittensmage:BAAANQADCggICAAAAA==.Mittenss:BAAANQADCggICQAAAA==.',
Mn='Mndgblnfred:BAAANQADCgEIAQAAAA==.',
Mo='Mojorisinn:BAAANQAECgQIBAAAAA==.Moobear:BAABNQAECn9DAAIHAAoK6yPNAwAYAwAHAAoK6yPNAwAYAwAAAA==.Moogie:BAABNQAECn8nAAILAAkKPBt0gQB7AgALAAkKPBt0gQB7AgAAAA==.Mooshades:BAAANQAECgEIAQAAAA==.Moozlock:BAAANQAECgEIAQAAAA==.Morgiana:BAAANQAECgYIDwABNQAECggIBAAaAAAAAA==.Morvaine:BAABNQAECn8UAAIXAAgKgg0hVwCVAQAXAAgKgg0hVwCVAQAAAA==.Moscovio:BAACNQAFFH8mAAMXAAcKIxNTDACqAQAXAAYKdhVTDACqAQAWAAIK1BG6DwCVAAA1AAQKfz8AAxcACgpCI38NAOYCABcACgpCI38NAOYCABYAAQqtGb5sAEYAAAAA.Mosspaws:BAAANQAECgUICAAAAA==.',
Mt='Mtndewyou:BAABNQAECn8oAAIkAAgKHRJ+JQC0AQAkAAgKHRJ+JQC0AQAAAA==.',
Mu='Mutterutters:BAAANQADCgMIAwAAAA==.',
My='Myrothan:BAAANQAECgQICAAAAA==.',
Na='Napok:BAAANQAECgcIEgAAAA==.Nastea:BAAANQADCggICAAAAA==.',
Ni='Nickimihoj:BAAANQAECggIEgAAAA==.Nihr:BAAANQAECgUIBgAAAA==.Ninkarrak:BAAANQAECgMICgAAAA==.Nitalan:BAAANQABCgIIAgAAAA==.',
Nm='Nme:BAABNQAECn8lAAILAAgKcwrt3gDKAQALAAgKcwrt3gDKAQAAAA==.',
No='Nocturnos:BAAANQAECggIEAAAAA==.Nonbeliever:BAABNQAECn83AAMDAAoKRBpfagBdAgADAAoKRBpfagBdAgAJAAMKXg5CugB1AAAAAA==.Nonfiction:BAAANQAECgUIBQABNQAECgoKNwADAEQaAA==.Novamancer:BAAANQAECgEIAQAAAA==.',
Nu='Nuph:BAAANQAECgQIBQAAAA==.',
Ny='Nymage:BAABNQAECn9CAAIIAAoK4RcJBgA2AgAIAAoK4RcJBgA2AgAAAA==.',
Og='Ogdaddy:BAAANQADCggICAAAAA==.',
Ok='Okaerisan:BAAANQADCgMIAwAAAA==.',
Ol='Olord:BAAANQADCgEIAgAAAA==.',
Op='Ophbel:BAAANQADCgMIAwABNQAECgoKJgACAOwdAA==.',
Or='Orack:BAABNQAECn8eAAINAAkKhhYiJQD7AQANAAkKhhYiJQD7AQAAAA==.',
Ou='Outlast:BAAANQADCgYIBgAAAA==.',
Ow='Owch:BAEANQABCgIIAgABNQAECgoKJAAHAKQcAA==.',
Pa='Paleface:BAAANQAECggIBwAAAA==.Pallychango:BAAANQAECgMIAwABNQAECgoKJgACAOwdAA==.Panblind:BAACNQAFFH8VAAMKAAcKIRpuBgC3AQAKAAcKIRpuBgC3AQAiAAMKkhkaAwDlAAA1AAQKfzQAAwoACgrjIQsSANwCAAoACgrgIQsSANwCACIAAwrlIuwYACMBAAAA.Pandington:BAAANQADCgQIBwAAAA==.Parmageddon:BAACNQAFFH8JAAIGAAMKDRAXEwCpAAAGAAMKDRAXEwCpAAA1AAQKfywAAgYACgrmHHUsAGYCAAYACgrmHHUsAGYCAAAA.Parmnhammer:BAAANQAECgcIBwABNQAFFAMICQAGAA0QAA==.Parmrageiano:BAABNQAECn8gAAMOAAgKox1BBwBBAgAOAAgKox1BBwBBAgAPAAUKaxMSpQD7AAABNQAFFAMICQAGAA0QAA==.',
Pe='Peanought:BAABNQAECn8zAAQFAAoKUAxJPQBpAQAFAAoKvwlJPQBpAQAGAAYKOQ0fjADRAAASAAMKkAm6twB+AAAAAA==.Peetfix:BAABNQAECn8mAAMCAAoKghfyVwAbAgACAAoKghfyVwAbAgATAAQKZRuloQAyAQAAAA==.Pepsipink:BAAANQAECgEIAQAAAA==.Pets:BAABNQAECn8YAAMRAAoKJh6TEwDfAgARAAoKJh6TEwDfAgAEAAMK9gyAQQBwAAAAAA==.',
Ph='Phelon:BAAANQAECgYIBgABNQAFFAcIGQAUAA4fAA==.Phèdre:BAEANQAFFAEIAQABNQAFFAcIEgADAMoQAA==.',
Pi='Picklegrip:BAABNQAECn8lAAIPAAgKehMhkgAmAQAPAAgKehMhkgAmAQAAAA==.Pijak:BAAANQAECgMICgAAAA==.',
Pl='Planetina:BAAANQADCgcIBwAAAA==.',
Po='Poah:BAABNQAECn8UAAIZAAgKBx9cFgCcAgAZAAgKBx9cFgCcAgAAAA==.Portalcombat:BAAANQAECgIIAgAAAA==.',
Pr='Prettynhealz:BAAANQADCgIIAgAAAA==.Pruflas:BAAANQAECgEIAgAAAA==.',
Ps='Psycodk:BAAANQAECggICwAAAA==.',
Pu='Puggernaut:BAAANQAECgMICwAAAA==.Pumpin:BAAANQAECgMIBAAAAA==.Punkthor:BAABNQAECn8hAAIlAAgKWBa7DwDyAQAlAAgKWBa7DwDyAQAAAA==.Purgemepappy:BAAANQADCgYIDAAAAA==.Putitinme:BAAANQABCgIIAgAAAA==.',
['Pø']='Pø:BAABNQAECn8yAAIZAAoKWhBMFQDeAQAZAAoKWhBMFQDeAQAAAA==.',
Qk='Qkn:BAAANQAECgIIBgAAAA==.',
Ra='Raf:BAABNQAECn8pAAMCAAoKPCJJCwCNAwACAAoKPCJJCwCNAwATAAQKZhIzvgBuAAAAAA==.Rafraff:BAAANQAECgIIBAABNQAECgoKKQACADwiAA==.Ragnor:BAAANQAECgIIAgAAAA==.Ratoncita:BAAANQADCgUIBQAAAA==.Rayzee:BAAANQAECgEIAQAAAA==.',
Re='Reisar:BAAANQADCgMIAwAAAA==.Rennera:BAAANQAECgEIAgAAAA==.Revalation:BAABNQAECn8gAAMNAAoKkRi2GgBjAgANAAoKkRi2GgBjAgAMAAEKAADHuAAoAAAAAA==.',
Ri='Riachu:BAAANQAECgUIDQAAAA==.Ribeyejoe:BAAANQAECgQIBgAAAA==.',
Ro='Roadblock:BAABNQAECn8dAAIYAAkKeBklDAD7AQAYAAkKeBklDAD7AQAAAA==.Roboorc:BAAANQABCgMIAwAAAA==.Roken:BAAANQADCggICAAAAA==.Rorymcilroy:BAABNQAECn8VAAMTAAcKbRtJVgAPAgATAAcKbRtJVgAPAgACAAMK9Q0P+QChAAAAAA==.',
Ru='Ruddy:BAAANQADCgUIBQABNQAECgcIEgAaAAAAAA==.Ruinguee:BAAANQADCgYIBgAAAA==.',
Sa='Sacrament:BAABNQAECn8oAAIDAAoKAiP5EQAKAwADAAoKAiP5EQAKAwABNQAFFAIIBwAZANMeAA==.Sagan:BAEANQADCgQIBAABNQAECgcIEAAaAAAAAA==.Saifrah:BAAANQADCggICQAAAA==.Sandasa:BAAANQAECgQIBAAAAA==.Sanivanth:BAAANQADCgQIBAAAAA==.Saragos:BAAANQAECgEIAQABNQAFFAcIFQAIAP0WAA==.Saucerdote:BAABNQAECn8ZAAMnAAoKhxIyDQBiAQAnAAkKhREyDQBiAQAUAAcKegrELADnAAAAAA==.Saxon:BAAANQAECgIIAQABNQAECgkJKQARAH8SAA==.',
Se='Selenix:BAAANQADCgYIBgABNQAECgkJNgAVALkYAA==.Selinfinite:BAABNQAECn8bAAIdAAoKTiF8IACWAgAdAAoKTiF8IACWAgAAAA==.Selkie:BAABNQAECn8gAAIhAAcKmRJ3FACGAQAhAAcKmRJ3FACGAQAAAA==.Sephtis:BAABNQAECn8UAAQGAAoKpASvZgCLAAAGAAkKsASvZgCLAAASAAgKKAEK2QA9AAAFAAEKgwNypwAlAAAAAA==.Serenitynow:BAAANQAECgQIBAAAAA==.Sevenlions:BAAANQADCgEIAQAAAA==.',
Sg='Sgge:BAAANQADCgYIBgAAAA==.',
Sh='Shadowmaven:BAAANQAECggIDAAAAA==.Shakakhan:BAABNQAECn8qAAMCAAgKnSLJLwDkAQACAAgKnSLJLwDkAQATAAEKfg2JFAFBAAABNQAECgoKPQALAPYhAA==.Shammer:BAEANQADCggIBgABNQAECgkJIgAGAC0eAA==.Shamshielder:BAEBNQAECn8iAAMGAAkKLR6dLABlAgAGAAkKLR6dLABlAgAFAAMKIwu5nABZAAAAAA==.Sharick:BAAANQAECgUIDgAAAA==.Shawdrake:BAAANQAECgUIBQABNQAECgoKOAATAGgXAA==.Shawlee:BAABNQAECn84AAMTAAoKaBfSLgA2AgATAAoKaBfSLgA2AgACAAgKKgv8kAB6AQAAAA==.Sheph:BAAANQAFFAMIAwAAAA==.Shetmage:BAABNQAECn8zAAILAAoKQxbojwBgAgALAAoKQxbojwBgAgABNQAFFAYIEgAMALsUAA==.Shettrah:BAACNQAFFH8SAAIMAAYKuxQ6DgCFAQAMAAYKuxQ6DgCFAQA1AAQKfzwAAgwACgopIQ0KAOACAAwACgopIQ0KAOACAAAA.Shottdown:BAAANQADCgUIBQAAAA==.Shwoobs:BAAANQAECgEIAQAAAA==.Shädes:BAAANQAECggICwAAAA==.',
Si='Sigasunanvil:BAAANQAECgQIBAAAAA==.Siickboy:BAAANQAECgMIBAAAAA==.Sijious:BAAANQADCggIHwAAAA==.Silhõuette:BAAANQADCggICAAAAA==.Simperhi:BAAANQAECgEIAQAAAA==.Singularity:BAAANQAECgUIDQABNQAECgoKPQALAPYhAA==.',
Sk='Skanktank:BAABNQAECn8gAAIPAAgKxiA3QgDDAgAPAAgKxiA3QgDDAgAAAA==.Skora:BAAANQAECggIBAAAAA==.Skyland:BAAANQADCgcIBwABNQAFFAcIFgAeAEgWAA==.',
Sl='Slicendice:BAAANQAECgEIAgAAAA==.Slinkies:BAAANQADCgYICQABNQAECgkJGQALALwbAA==.Slipknife:BAABNQAECn8dAAIBAAkKABVrMAAgAgABAAkKABVrMAAgAgAAAA==.',
Sm='Smashinppl:BAAANQADCggICAABNQAECgoKSQADADAjAA==.',
Sn='Sneez:BAAANQAECgEIAQAAAA==.',
So='Somi:BAACNQAFFH8GAAIJAAIKbyGKFAC9AAAJAAIKbyGKFAC9AAA1AAQKfyMAAgkACgrhHjUfAPQCAAkACgrhHjUfAPQCAAAA.Sourworms:BAAANQAECgQIBAAAAA==.',
St='Stabbystab:BAAANQAECgYIDQABNQADCgEIAgAaAAAAAA==.Stabybara:BAAANQAECgUICQABNQAECgoKIgAXAC4VAA==.Stankydk:BAABNQAECn8UAAISAAgK0hTVVwCxAQASAAgK0hTVVwCxAQAAAA==.Stankyleg:BAACNQAFFH8QAAMRAAcKYgkeHQDLAAAEAAUKywqYEwAHAQARAAQKPQMeHQDLAAA1AAQKfyAAAgQACQpIFxUXAJsBAAQACQpIFxUXAJsBAAAA.Starhealer:BAAANQAECgcICAAAAA==.Stewie:BAABNQAECn8YAAIZAAkK4wkqNQBsAQAZAAkK4wkqNQBsAQAAAA==.Stinkbombs:BAAANQAECgcICgAAAA==.Stinkies:BAAANQAECgUICQABNQAECgkJGQALALwbAA==.Stunanddone:BAAANQAECgUIEAAAAA==.',
Su='Subrogue:BAAANQAECgQICQABNQAFFAcIHAAEABQcAA==.Sunlest:BAAANQADCgcIJwAAAA==.',
Sw='Swaayshooter:BAAANQAECgUIBwABNQAFFAMIBQABAOYRAA==.',
Sy='Sylphrena:BAACNQAFFH8JAAIVAAMK9xZqGQDtAAAVAAMK9xZqGQDtAAA1AAQKfy0AAhUACgoCGzo1AJMCABUACgoCGzo1AJMCAAAA.Sylvanniia:BAAANQAECgYIEAABNQAFFAgIFwAfABYUAA==.',
Ta='Tacow:BAAANQAECgUIDAAAAA==.Talethen:BAABNQAECn8fAAQgAAgKoROSFwDQAQAgAAgKlxOSFwDQAQAfAAYKVgt0FQDZAAAeAAEKZwYrUgAoAAAAAA==.',
Te='Telaragehoof:BAAANQAECgUIBwAAAA==.',
Th='Thatbox:BAAANQAECgYIDAAAAA==.Thedrood:BAABNQAECn9BAAINAAoKCR/+CwDKAgANAAoKCR/+CwDKAgAAAA==.Thorfyna:BAAANQADCggICAAAAA==.',
Ti='Tiamät:BAAANQAECggICgAAAA==.Tintinnabula:BAABNQAECn8WAAIcAAYK6A48EQA4AQAcAAYK6A48EQA4AQAAAA==.Tiptronic:BAAANQAECgQICQAAAA==.',
To='Tohk:BAACNQAFFH8RAAIdAAcKhBgtCQCaAQAdAAcKhBgtCQCaAQA1AAQKfy0AAh0ACgotH8wTAAADAB0ACgotH8wTAAADAAAA.Tollee:BAAANQAECgQIBAAAAA==.Tontiamat:BAABNQAECn85AAIgAAoK9xKpBwDpAQAgAAoK9xKpBwDpAQAAAA==.Tontier:BAABNQAECn8fAAMjAAkKxRXXCgDeAQAjAAkKxRXXCgDeAQANAAMKLw//WQCgAAABNQAECgoKOQAgAPcSAA==.Tormero:BAAANQADCgcIBwAAAA==.Totembeans:BAAANQAECgQIBQAAAA==.Touchyfred:BAAANQAECgUICAAAAA==.Toxicfury:BAAANQABCgUIBAAAAA==.',
Tr='Traash:BAAANQABCgIIAgAAAA==.Treily:BAAANQAECgMIEQAAAA==.Tricket:BAAANQAECgQICAAAAA==.Tristani:BAAANQAECgEIAQAAAA==.Trolloladin:BAAANQADCggIDwAAAA==.Truestorm:BAABNQAECn8hAAIDAAkK8AekzwB8AQADAAkK8AekzwB8AQAAAA==.',
Tu='Tuchi:BAABNQAECn8ZAAILAAgKTxz1tgAVAgALAAgKTxz1tgAVAgAAAA==.Turak:BAAANQAECgUICAAAAA==.',
['Tà']='Tàcobelle:BAABNQAECn8VAAMEAAgKwxC1IwASAQARAAgKWA7YeQB/AQAEAAYK0gu1IwASAQAAAA==.',
Un='Unpredicted:BAAANQADCgIIAgAAAA==.',
Va='Vanicton:BAABNQAECn8fAAITAAgKqyHeGQAKAwATAAgKqyHeGQAKAwAAAA==.',
Ve='Ve:BAABNQAECn8kAAMTAAoK9BqhOQB4AgATAAkKXxqhOQB4AgAhAAYKTxhbHACeAQAAAA==.Vegh:BAABNQAECn8qAAIdAAgK8SANEgAPAwAdAAgK8SANEgAPAwAAAA==.Velaei:BAAANQAECgEJAQAAAA==.Veldcat:BAAANQAECgYIDAAAAA==.Velddk:BAAANQADCggICAAAAA==.Veriale:BAAANQAECgMIBwAAAA==.Verra:BAABNQAECn8dAAIDAAkK0w+ZugCoAQADAAkK0w+ZugCoAQAAAA==.',
Vi='Vitriol:BAAANQAECgMIBAAAAA==.',
Wa='Wampa:BAAANQAECgEIAgAAAA==.Wanderblue:BAAANQAECgMIAwAAAA==.Wangstah:BAABNQAECn8aAAIRAAkKBRdgdgAjAgARAAkKBRdgdgAjAgAAAA==.Warshaw:BAAANQABCgEIAQABNQAECgoKOAATAGgXAA==.Wartogoteam:BAABNQAECn89AAIPAAoKNRxuSQCtAgAPAAoKNRxuSQCtAgAAAA==.Waytogoteam:BAAANQAECgEIAQAAAA==.',
We='Weiss:BAACNQAFFH8VAAMIAAcK/RaTBgCoAAALAAUKBhn1JgBPAQAIAAMKiheTBgCoAAA1AAQKfzkAAwsACgprI0QtADQDAAsACgprI0QtADQDACgABArJHP4DAAkBAAAA.',
Wf='Wf:BAABNQAECn88AAQhAAoKQxHOFQAMAgAhAAkKihHOFQAMAgATAAoKewXQewANAQACAAEKUg/h5QAxAAAAAA==.',
Wi='Wildshapez:BAAANQAECgIIBQAAAA==.',
Wo='Woog:BAAANQADCgYIBgAAAA==.Worsthunterx:BAAANQAFFAEIAQABNQAFFAYIDwAUANkgAA==.',
Wr='Wreckedu:BAAANQADCgEIAQAAAA==.',
Wy='Wyldspirit:BAABNQAECn8eAAIRAAUK4glhxQDiAAARAAUK4glhxQDiAAAAAA==.Wyreless:BAAANQAECgUIEQABNQAECgoKOQAHAAsdAA==.',
Ya='Yaass:BAAANQADCggJCAABNQAECgoKPAAhAEMRAA==.Yagrum:BAAANQAECgEJAQAAAA==.Yahikko:BAABNQAECn8bAAIXAAoKWRIYeQD4AQAXAAoKWRIYeQD4AQAAAA==.',
Ye='Yem:BAABNQAECn8ZAAQWAAkKeyHaEQDnAQAWAAYKZyLaEQDnAQAXAAYKoyBgZABvAQAcAAIKpgyZIQBtAAAAAA==.',
Yo='Yoddaa:BAABNQAECn8xAAQVAAoKnRtxOwAVAgAVAAoKWRdxOwAVAgAnAAUK5hp7DQBcAQAUAAQKIwxNOACiAAABNQAECgkJMgAXAGkeAA==.Yoverre:BAAANQAECgEIAgAAAA==.',
Ze='Zergen:BAAANQADCgYIBgAAAA==.Zetsu:BAAANQAECggIDwABNQAECgoKGwAXAFkSAA==.',
Zh='Zhenya:BAABNQAECn8tAAILAAoKHxFQwgAAAgALAAoKHxFQwgAAAgAAAA==.',
Zu='Zuga:BAAANQAECgcICwAAAA==.Zuljit:BAAANQAECgEIAQAAAA==.',
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
