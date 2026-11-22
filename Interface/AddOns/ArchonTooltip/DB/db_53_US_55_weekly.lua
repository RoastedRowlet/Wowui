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

local lookup = {'Rogue-Assassination','Shaman-Elemental','Paladin-Retribution','Hunter-Marksmanship','DeathKnight-Frost','DeathKnight-Blood','Druid-Guardian','Mage-Frost','Paladin-Holy','DemonHunter-Devourer','Mage-Arcane','Druid-Balance','Druid-Restoration','Shaman-Restoration','Warrior-Arms','Warrior-Protection','Monk-Mistweaver','Hunter-BeastMastery','DeathKnight-Unholy','Priest-Shadow','Priest-Holy','Warlock-Destruction','Warlock-Demonology','Warrior-Fury','Monk-Windwalker','Druid-Feral','Rogue-Subtlety','Unknown-Unknown','Warlock-Affliction','DemonHunter-Havoc','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','DemonHunter-Vengeance','Paladin-Protection','Monk-Brewmaster','Hunter-Survival','Priest-Discipline','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abc:BAAANQADCgIIAgAAAA==.',
Ac='Acheniris:BAAANQAECgUIDQAAAA==.',
Ae='Aeviee:BAAANQADCgQJBAAAAA==.',
Ag='Agrippa:BAABNQAECn8jAAIBAAoKsxBVOQDvAQABAAoKsxBVOQDvAQAAAA==.',
Ah='Ahndhrez:BAABNQAECn8wAAICAAoK7B9xEQDfAgACAAoK7B9xEQDfAgAAAA==.',
Ai='Aidric:BAABNQAECn8fAAIDAAgKUxIhnQCTAQADAAgKUxIhnQCTAQAAAA==.Airwavez:BAACNQAFFH8QAAIEAAcKFxD9CwB/AQAEAAcKFxD9CwB/AQA1AAQKf0kAAgQACgoUHEoMAHYCAAQACgoUHEoMAHYCAAAA.',
Ak='Akriel:BAAANQAECgcIDwAAAA==.',
Al='Albrecht:BAAANQAECgcICgAAAA==.Aldeor:BAAANQAECgIIAgAAAA==.Altra:BAACNQAFFH8LAAMFAAUKqQVaFACpAAAFAAQKqQVaFACpAAAGAAEKAAA6OgAAAAA1AAQKfzIAAwUACgoxF00uAC8CAAUACgoxF00uAC8CAAYAAQoAAF3aACQAAAAA.Alumit:BAAANQAECgYJDwAAAA==.',
Am='Amoeta:BAABNQAECn89AAIHAAoKOB1ICwC4AgAHAAoKOB1ICwC4AgAAAA==.',
An='Andor:BAAANQADCgcIEAAAAA==.Angelique:BAAANQAECgUIDwAAAA==.Angry:BAAANQADCgYICgAAAA==.Angryapples:BAAANQAECgQIBQAAAA==.Annihilation:BAAANQADCgUIBQAAAA==.',
Ap='Approved:BAAANQADCgYIBQAAAA==.',
Ar='Arconos:BAAANQADCgYIDAABNQAFFAcIFQAIAP0WAA==.Arcstorm:BAAANQAECgEIAQAAAA==.',
As='Ashguard:BAAANQADCgcIDAAAAA==.Asomyrh:BAABNQAECn8iAAIJAAkKng37aQDZAQAJAAkKng37aQDZAQAAAA==.',
Au='Aurial:BAAANQADCgMIAwAAAA==.Auriala:BAAANQAECgYIEQAAAA==.',
Az='Azuriae:BAAANQAECgQIBAAAAA==.',
Ba='Babygirl:BAAANQAECgYICQAAAA==.Baelan:BAAANQAECgQIBAAAAA==.Bananer:BAAANQAECgQICAAAAA==.Banonzarath:BAAANQADCggICAAAAA==.Barrysoetoro:BAAANQADCgcIDAAAAA==.Battlemagic:BAAANQAECgYIBgABNQAECgoKLwAKAOgYAA==.Baulie:BAAANQAECgQIBAAAAA==.',
Bb='Bbqlol:BAAANQAECgQIBgABNQAECgoKPgALAPYhAA==.',
Be='Beefstick:BAAANQADCggIJgAAAA==.Bekroh:BAABNQAECn8YAAMMAAcKfhglSADKAQAMAAcKfhglSADKAQANAAEKbASufAAlAAAAAA==.Bestt:BAAANQAECgYICgAAAA==.',
Bi='Bigchomp:BAACNQAFFH8VAAIOAAgKqBwoBABAAgAOAAgKqBwoBABAAgA1AAQKfzEAAw4ACgrYIN4hAOACAA4ACgrYIN4hAOACAAIAAQoAAD8jAUsAAAAA.Bigdaddyd:BAABNQAECn8sAAMPAAoKLBImaQDFAQAPAAoKvQ4maQDFAQAQAAcKkhFlIgDnAAAAAA==.Bigdonk:BAAANQADCggJCAAAAA==.Bigfoxlilsox:BAAANQADCgQIBAAAAA==.Bioodlion:BAABNQAECn8xAAIDAAoKYw8tvgCgAQADAAoKYw8tvgCgAQAAAA==.Bipolar:BAABNQAECn8sAAIRAAoKnQXhHAA7AQARAAoKnQXhHAA7AQAAAA==.Bippysmasher:BAABNQAECn8vAAIKAAoK6BicHwBSAgAKAAoK6BicHwBSAgAAAA==.Bishmanistic:BAAANQAECgYIDgAAAA==.',
Bl='Blacblood:BAAANQAECgEIAQAAAA==.Blastemis:BAAANQAECgMIBAAAAA==.Blindweiss:BAAANQADCgcIBwABNQAFFAcIFQAIAP0WAA==.Blinkies:BAABNQAECn8ZAAILAAkKvBs9hAB2AgALAAkKvBs9hAB2AgAAAA==.',
Bo='Bontao:BAACNQAFFH8RAAISAAcKQBQbCgCpAQASAAcKQBQbCgCpAQA1AAQKf0QAAhIACgpUIqoUAPcCABIACgpUIqoUAPcCAAAA.Bontaopanda:BAAANQADCgcIEwABNQAFFAcIEQASAEAUAA==.Boomies:BAAANQADCgQJBAABNQAECgkJGQALALwbAA==.Borstenne:BAABNQAECn8kAAITAAkK9iPhCgBkAwATAAkK9iPhCgBkAwAAAA==.Bosco:BAAANQADCgQIBAAAAA==.',
Br='Bresemage:BAAANQAECgQIBAABNQAECgoKQQAOAF4jAQ==.Bresepls:BAACNQAFFH8FAAIDAAIKAQwPKAB7AAADAAIKAQwPKAB7AAA1AAQKfyAAAwMACQoSGSKJALoBAAMACArpGiKJALoBAAkABAqsFkfOAN8AAAE1AAQKCgpBAA4AXiMA.Breseshh:BAABNQAECn9BAAMOAAoKXiPtCAB6AwAOAAoKXiPtCAB6AwACAAYKNxNhmADXAAAAAA==.Brickbeard:BAAANQAECgQIAwAAAA==.Brickbow:BAAANQADCgYIBgAAAA==.Brickette:BAAANQAECggIDwABNQAFFAcIFgAJAIENAA==.Bricklicker:BAAANQAECgQIAwAAAA==.Bricksquad:BAAANQAECgcIDgAAAA==.Brickthrow:BAACNQAFFH8WAAIJAAcKgQ1NDgB+AQAJAAcKgQ1NDgB+AQA1AAQKfzsAAwkACgpgINAgAOsCAAkACgpgINAgAOsCAAMAAQr5D3abAToAAAAA.Bringdapain:BAAANQAECggIDAAAAA==.',
Bu='Budhistpalm:BAAANQAECgMIAwAAAA==.Burgerburn:BAAANQAECgMICAAAAA==.',
By='Bytherune:BAAANQADCgUIBQAAAA==.Bytheway:BAABNQAECn8ZAAIUAAkKahQDKwDPAQAUAAkKahQDKwDPAQAAAA==.',
['Bé']='Béstt:BAABNQAECn8lAAMCAAoKPRr2KgDUAgACAAoKPRr2KgDUAgAOAAIKDgh+3gBcAAAAAA==.',
Ca='Cadilak:BAACNQAFFH8LAAMNAAUKEg8oDADyAAANAAQK7wooDADyAAAMAAEKAAAlJwAAAAA1AAQKfzMAAw0ACgp8GUAXAIcCAA0ACgp8GUAXAIcCAAwABArqD4qNAKAAAAAA.Caelesti:BAABNQAECn8aAAMUAAoKiQ7oGADbAQAUAAoKiQ7oGADbAQAVAAIKYgZp/wAtAAAAAA==.Camlin:BAAANQADCggIDgAAAA==.Carrymemommy:BAAANQADCgUIBQAAAA==.Cassanndra:BAEANQAECggIAgABNQAFFAQICgADANYMAA==.',
Ch='Cheapshotjoe:BAAANQADCgEIAQAAAA==.Chelbur:BAAANQAECgIIAwAAAA==.Chowderhead:BAABNQAECn8vAAMWAAoKvRiTCQBgAgAWAAkKqROTCQBgAgAXAAcKQha5pAANAQAAAA==.',
Ci='Cileb:BAABNQAECn8lAAILAAoK+B+qJwBDAwALAAoK+B+qJwBDAwAAAA==.Civik:BAAANQAECgQIAwAAAA==.',
Co='Cocio:BAABNQAECn8dAAIPAAcKdBS6nQDSAQAPAAcKdBS6nQDSAQABNQAECgoKSQAPAOsbAA==.Conchsniffer:BAACNQAFFH8LAAIDAAUKEBTKCwAvAQADAAUKEBTKCwAvAQA1AAQKf1YAAwMACgriIQwdAO0CAAMACgriIQwdAO0CAAkAAgrPC9rsAEAAAAAA.Conrack:BAAANQADCggICAAAAA==.Copperit:BAABNQAECn8wAAMGAAkKayU9BABBAwAGAAkKayU9BABBAwAFAAEKQh8amwBdAAAAAA==.Cornburglar:BAABNQAECn9JAAMPAAoK6xuwPQBLAgAPAAoKiBuwPQBLAgAYAAIKziDYHwC+AAAAAA==.Corrona:BAEANQAECgMIAgABNQAFFAQICgADANYMAA==.Cowtaclysmic:BAAANQAECgYIBgAAAA==.',
Cr='Creatlach:BAAANQADCgYIBgABNQAFFAgIGQAOAAcaAA==.Crime:BAABNQAECn8jAAIBAAoKoRzFCQBBAgABAAoKoRzFCQBBAgABNQAFFAIIBwAZANMeAA==.Crunchwrap:BAABNQAECn8UAAIMAAYK+ATtdwDrAAAMAAYK+ATtdwDrAAAAAA==.',
Ct='Cthul:BAAANQADCggICAAAAA==.',
Cu='Curseus:BAAANQAECgEIAQAAAA==.',
['Câ']='Câlisse:BAACNQAFFH8HAAIZAAIK0x4KDgCaAAAZAAIK0x4KDgCaAAA1AAQKf0sAAhkACgqGJLADAJoDABkACgqGJLADAJoDAAAA.',
Da='Daddiedk:BAABNQAECn8dAAIFAAcKlBrcPQDVAQAFAAcKlBrcPQDVAQAAAA==.Dahealamon:BAAANQAECgQIBQAAAA==.Daiyan:BAAANQAECgQIBQABNQAECgkJIAAaADYOAA==.Damncats:BAABNQAECn82AAIYAAoKNBCkEABxAQAYAAoKNBCkEABxAQAAAA==.Dandinn:BAAANQAECgMIAwAAAA==.Danielsboone:BAABNQAECn8fAAISAAYKTw3NygAcAQASAAYKTw3NygAcAQAAAA==.Daowa:BAAANQABCgEIAQAAAA==.Darkmare:BAACNQAFFH8KAAMbAAUKagarHwB/AAAbAAQKwgarHwB/AAABAAEKuAUgFQAwAAA1AAQKfzEAAxsACgokF0ERAG0CABsACgrhFUERAG0CAAEAAgrfCtSQAG8AAAAA.Darknemesis:BAAANQAECgQICAABNQAECgUIBwAcAAAAAA==.Darksteps:BAAANQADCgQIBAAAAA==.',
De='Deadhippocow:BAABNQAECn8eAAINAAoK2R24GQBtAgANAAoK2R24GQBtAgAAAA==.Dearth:BAEBNQAECn8VAAIDAAgKgguWFgH6AAADAAgKgguWFgH6AAABNQAFFAQICgADANYMAA==.Deathbane:BAABNQAECn8sAAQWAAoKCg7fMgD6AAAXAAoK7w3RhQDYAQAWAAUKxAnfMgD6AAAdAAEKhwhBMAAwAAAAAA==.Deathwavez:BAABNQAECn8UAAIFAAkKGQw1awDwAAAFAAkKGQw1awDwAAAAAA==.Deckard:BAEANQAECggICAABNQAFFAQICgADANYMAA==.Demayy:BAABNQAECn9BAAIRAAoK2RpQBwACAwARAAoK2RpQBwACAwAAAA==.Demona:BAAANQAECgUICgAAAA==.Demonix:BAABNQAECn88AAMXAAoKaR86HgCcAgAXAAoKaR86HgCcAgAdAAUKmhzrDACPAQAAAA==.Demonshades:BAAANQADCgMIBAAAAA==.Derptron:BAABNQAECn8pAAIIAAoKXRa4CABRAgAIAAoKXRa4CABRAgAAAA==.',
Di='Diluted:BAABNQAECn8VAAMBAAkKyxdqHQA7AQAbAAcKmxYGUgC8AQABAAcKuBNqHQA7AQABNQAECgoKPgALAPYhAA==.Dilutedqt:BAABNQAECn8+AAILAAoK9iGWLQAzAwALAAoK9iGWLQAzAwAAAA==.Dilutedret:BAABNQAECn8dAAMDAAoKUReMlAD7AQADAAoKUReMlAD7AQAJAAIKEBFyzgB4AAABNQAECgoKPgALAPYhAA==.Dinobrass:BAACNQAFFH8FAAISAAIKnwyfJACPAAASAAIKnwyfJACPAAA1AAQKf1EAAhIACQrBHGVDAE0CABIACQrBHGVDAE0CAAAA.Dirge:BAABNQAECn8iAAITAAoKiA9zRQADAgATAAoKiA9zRQADAgAAAA==.Dirtylöbster:BAABNQAECn8uAAILAAkKZh6nTADoAgALAAkKZh6nTADoAgAAAA==.Disabel:BAAANQADCggICAAAAA==.Distracto:BAAANQAECggIEAAAAA==.',
Dj='Djinsurgent:BAABNQAECn8sAAMTAAoKeRlbGwAKAgATAAoKsBhbGwAKAgAGAAgKixOTPwBAAQAAAA==.',
Dl='Dltdjr:BAAANQAECgUIDQABNQAECgoKPgALAPYhAA==.',
Do='Donnybrook:BAAANQAECgYICgAAAA==.Doobysnacks:BAABNQAECn8rAAIGAAkKySMzDQDEAgAGAAkKySMzDQDEAgAAAA==.Doolittle:BAAANQAECgYIDQAAAA==.Dorfies:BAAANQADCgcJCAABNQAECgkJGQALALwbAA==.Dorns:BAAANQAECgYICgAAAA==.',
Dr='Dragondees:BAAANQADCgYIBAAAAA==.Dralock:BAAANQAECgQIBAABNQAECgQIAwAcAAAAAA==.Dralshock:BAAANQADCgcIBwAAAA==.Dreamyeti:BAAANQADCgEIAQAAAA==.Dreats:BAAANQAECgMIBAAAAA==.Drewmee:BAABNQAECn8WAAIDAAkKmgZF3QBgAQADAAkKmgZF3QBgAQAAAA==.Droovani:BAAANQAECgUICgABNQAECgkJFgADAJoGAA==.Drunkenyeti:BAAANQADCgcIEAAAAA==.',
Du='Duckbeak:BAAANQAECgQIBQAAAA==.Duwork:BAABNQAECn8xAAIMAAoKFx7zGAAAAwAMAAoKFx7zGAAAAwAAAA==.',
['Dæ']='Dæmona:BAABNQAECn8yAAIeAAoKchasKQBTAgAeAAoKchasKQBTAgAAAA==.',
Eb='Ebk:BAAANQAECgcIDgAAAA==.Ebkx:BAAANQAECgIIAgAAAA==.',
El='Eladus:BAAANQAECgYIEQAAAA==.Elesus:BAAANQADCgIJAgABNQAECggICAAcAAAAAA==.',
Em='Emblaze:BAAANQADCgUIBQAAAA==.Emrys:BAAANQADCggIBwABNQAECgoKLgASANISAA==.',
En='Enhshaman:BAAANQAECggIEAABNQAFFAcIHAAEABQcAA==.',
Ev='Evilinne:BAAANQAECgQIBAAAAA==.',
Ez='Ezmila:BAAANQADCgEIAQAAAA==.',
Fa='Faedari:BAAANQADCgMIAwAAAA==.Faithpasse:BAABNQAECn8oAAIRAAoK2gzYHwAYAQARAAoK2gzYHwAYAQAAAA==.',
Fe='Felondar:BAABNQAECn8uAAIeAAoK1wysLQCmAQAeAAoK1wysLQCmAQAAAA==.Ferarro:BAABNQAECn8WAAITAAgK1B48KACZAgATAAgK1B48KACZAgAAAA==.',
Fi='Findd:BAAANQADCgUIBQAAAA==.Finnadin:BAAANQADCgcIDQAAAA==.Finns:BAABNQAECn8bAAIHAAoK8Q6/HwCFAQAHAAoK8Q6/HwCFAQAAAA==.Firulais:BAABNQAECn8uAAISAAoK0hLaWAAYAgASAAoK0hLaWAAYAgAAAA==.Fistuu:BAAANQADCgUIBQAAAA==.',
Fl='Flysky:BAACNQAFFH8WAAIfAAcKSBYdCgCKAQAfAAcKSBYdCgCKAQA1AAQKfzQABB8ACgo5I48GAD4DAB8ACgo5I48GAD4DACAABQoHHq0OAFoBACEABQqPGiojACwBAAAA.',
Fo='Foxsake:BAAANQADCgQIBAAAAA==.',
Fr='Freshpot:BAAANQAECgQICAAAAA==.Frostuss:BAAANQAECgIIAwAAAA==.Frostwyrm:BAAANQAECgEIAgAAAA==.Frènchtoast:BAAANQAECgEIAQABNQAECgoKHgANANkdAA==.',
Fu='Fumbles:BAAANQAECgEIAwAAAA==.Furysbane:BAAANQAECgEIAQAAAA==.Futurefist:BAAANQADCggICAAAAA==.',
Ga='Gabtvrdruid:BAAANQADCgEIAQAAAA==.Galvis:BAAANQAECggIBwAAAA==.Garduuk:BAABNQAECn8nAAMNAAoKmhv7DQDxAgANAAoKmhv7DQDxAgAMAAMKJBVbZwCKAAAAAA==.',
Ge='Gearth:BAABNQAECn8bAAIiAAcKwhtsFQARAgAiAAcKwhtsFQARAgAAAA==.Ger:BAAANQADCgYIDAABNQAECgoKOAALACcQAA==.',
Gl='Glucose:BAABNQAECn8iAAIXAAoKLhW2TwDlAQAXAAoKLhW2TwDlAQAAAA==.',
Go='Gonah:BAABNQAECn8WAAINAAYKGxXZOABXAQANAAYKGxXZOABXAQAAAA==.Gotlieb:BAAANQAECgMIBgAAAA==.',
Gr='Gravey:BAABNQAECn8dAAIGAAcKlBt0NgAxAgAGAAcKlBt0NgAxAgAAAA==.Grenno:BAAANQAECgcIBwABNQAFFAgIEgATALMWAA==.Grogger:BAAANQADCgUIBQAAAA==.Grraendal:BAAANQADCggIDAAAAA==.Grrahtahtah:BAACNQAFFH8cAAIEAAcKFByvAwBOAgAEAAcKFByvAwBOAgA1AAQKfy4AAwQACgrIIVgKADEDAAQACgrIIVgKADEDABIAAQo7E0FLAUkAAAAA.',
Gy='Gymble:BAAANQAECggIAQAAAA==.',
Ha='Hakkim:BAAANQADCggICAAAAA==.Hammerinfred:BAAANQAECgQIBwAAAA==.',
He='Heamight:BAAANQAECgEIAQAAAA==.Heavyguard:BAAANQABCgIIAgAAAA==.Helhunter:BAABNQAECn8kAAIKAAoKsw7HGwDLAQAKAAoKsw7HGwDLAQAAAA==.',
Hi='Hidann:BAAANQAECggIBwABNQAECgoKGwAXAFkSAA==.Himeko:BAAANQAECgQICQABNQAFFAcIFQAIAP0WAA==.Hippayman:BAAANQAECgYICwAAAA==.Hippysmasher:BAAANQAECggIDwABNQAECgoKLwAKAOgYAA==.',
Ho='Holyhooters:BAABNQAECn8xAAIDAAoKIxvbTQCrAgADAAoKIxvbTQCrAgAAAA==.Holypablo:BAAANQAECgcIDgABNQAECgoKKQAVAG8XAA==.Honour:BAABNQAECn8+AAIDAAoKBBxeQwBfAgADAAoKBBxeQwBfAgAAAA==.',
Hr='Hrathadin:BAAANQAECggIEQABNQAFFAUICAAeAOoYAA==.Hrathdemon:BAACNQAFFH8IAAMeAAUK6hjkDgDYAAAeAAUKXxTkDgDYAAAKAAEK0RuSEwBWAAA1AAQKf0gABB4ACgooIsELAOMCAAoACQqrIFUKADUDAB4ACQrtH8ELAOMCACMABwoIH+wHAAQCAAAA.Hrathion:BAAANQAECgYIDQABNQAFFAUICAAeAOoYAA==.Hrathman:BAAANQAECgQICgABNQAFFAUICAAeAOoYAA==.',
Hu='Huntermik:BAAANQADCgUIBQAAAA==.Hupa:BAABNQAECn8iAAIDAAcKZyM2XgB+AgADAAcKZyM2XgB+AgAAAA==.Hurtsdonut:BAAANQAECgQIDAABNQAECggICAAcAAAAAA==.Huulis:BAAANQADCggICAAAAA==.',
Ia='Iamheyo:BAABNQAECn8pAAMJAAoKChgDVwAUAgAJAAoKChgDVwAUAgADAAUKERaQHwG6AAAAAA==.',
Ic='Ickeetard:BAAANQADCgcJBwAAAA==.',
Id='Idiotbreath:BAAANQAECgYIDwAAAA==.',
Ie='Ieatcheeks:BAAANQAECgUIDQAAAA==.Ieyasu:BAECNQAFFH8MAAIMAAQKkQZxFgC5AAAMAAQKkQZxFgC5AAA1AAQKfzUAAwwACgoIGzApAI0CAAwACgoIGzApAI0CABoAAgpRGVlBAEwAAAAA.',
Ig='Ignitus:BAAANQAECgQIDAAAAA==.',
Ik='Ikuchi:BAABNQAECn8mAAIfAAoKbQaRGABsAQAfAAoKbQaRGABsAQAAAA==.',
Il='Illidornsina:BAABNQAECn8VAAIeAAYKphKkQQAvAQAeAAYKphKkQQAvAQABNQAECgYICgAcAAAAAA==.Illpownyou:BAAANQADCgcIBwABNQAECgoKIwAhAHoSAA==.',
In='Indigò:BAAANQAECgIIAgAAAA==.Infiniti:BAAANQAECgIIAwAAAA==.Insulinshot:BAAANQAECgIIAwAAAA==.',
Ir='Ironguard:BAAANQABCgMIAwAAAA==.',
It='Itsmagharszn:BAAANQADCgEIAQAAAA==.',
Ja='Jabronipie:BAAANQADCggIBQAAAA==.Jaliano:BAAANQADCgYIBgABNQAECgkJKwAOAAIMAA==.Jameyjasta:BAAANQAECgQICgAAAA==.',
Je='Jeffblades:BAAANQABCgQIBQAAAA==.Jellyroll:BAAANQAECgQIBAAAAA==.Jessica:BAAANQAECgQIEQAAAA==.',
Jh='Jhana:BAAANQADCggIGQAAAA==.',
Ji='Jingojengo:BAAANQAECgMICAAAAA==.',
Jj='Jjooaacchhim:BAAANQAECgQIEQAAAA==.',
Jo='Josh:BAAANQAECgQICAAAAA==.',
Ju='Junglefever:BAAANQADCgYIBgAAAA==.',
Jy='Jyve:BAABNQAECn8wAAISAAkKQhERfQAUAgASAAkKQhERfQAUAgAAAA==.',
Ka='Kadista:BAAANQAECgcIBgAAAA==.Kailin:BAAANQAECgMIBQAAAA==.Kailoon:BAAANQADCggICAAAAA==.Kakashi:BAAANQADCgYIDAAAAA==.Kalda:BAAANQAECgMIBgAAAA==.Kamadan:BAAANQAECgMIAwAAAA==.Kamanactali:BAAANQAECgYICAAAAA==.Kamele:BAAANQAECgQIBwABNQAECgkJIAAaADYOAA==.Kaneko:BAEBNQAECn8wAAMkAAkKSSNwBAAgAwAkAAkKliJwBAAgAwADAAkKdx/yLQCqAgABNQAFFAQIDAAMAJEGAA==.Kardiz:BAAANQADCgUIBQABNQAECggIAgAcAAAAAA==.Katalina:BAABNQAECn8+AAMjAAoKvxS6CgCxAQAjAAoK/xO6CgCxAQAeAAcK8xH+UwBBAQAAAA==.',
Ke='Kelstormhoof:BAAANQADCgcIEQABNQAECgUIBwAcAAAAAA==.',
Kh='Kham:BAACNQAFFH8GAAIYAAUKuQvkAQC6AAAYAAUKuQvkAQC6AAA1AAQKfz0AAhgACgrhItwBAB8DABgACgrhItwBAB8DAAAA.',
Ki='Kialla:BAAANQAFFAEIAQAAAA==.Kirren:BAAANQADCgIIAgAAAA==.',
Kl='Klais:BAAANQADCgQIBQAAAA==.',
Ko='Kokeovrdose:BAAANQABCgQIBAABNQADCgYICgAcAAAAAA==.Konet:BAAANQADCgQIBAAAAA==.Korrath:BAAANQAECgQIBgABNQAECgUIBQAcAAAAAA==.',
Ky='Kyle:BAAANQAECgEIAQAAAA==.',
La='Lavashiza:BAAANQAECgYIEQAAAA==.',
Le='Leadzorz:BAAANQAECgUIDAAAAA==.Leedaddydk:BAAANQADCgQIBAAAAA==.Leeoflight:BAAANQABCgQIBQAAAA==.Legday:BAAANQAECgUIBQAAAA==.Lesaelia:BAAANQAECgUICgAAAA==.',
Li='Lightstorm:BAAANQAECgEIAQAAAA==.Liltotem:BAABNQAECn85AAMOAAoKeBLNYACWAQAOAAoKeBLNYACWAQACAAQK7gd64QDUAAAAAA==.Linaria:BAAANQADCgUIBQAAAA==.Lizzydk:BAAANQAECgMIAwAAAA==.Lizzymonk:BAACNQAFFH8LAAIlAAUK/hlQBQDbAAAlAAUK/hlQBQDbAAA1AAQKfzAAAiUACgraIYoDAFcDACUACgraIYoDAFcDAAAA.',
Lo='Lockdownlol:BAABNQAECn86AAQSAAkK+CJTQgBPAgASAAgKISRTQgBPAgAEAAcKVh1tKQD/AQAmAAEKAABjFwAAAAABNQAECgoKPgALAPYhAA==.Lockuup:BAAANQABCgcICgAAAA==.Louisbraille:BAAANQAECgUIBAAAAA==.Lowe:BAAANQADCgIIAgAAAA==.',
Lu='Luluh:BAAANQAECgQIDQAAAA==.',
Ma='Maddog:BAABNQAECn8aAAIWAAgKNgodIABvAQAWAAgKNgodIABvAQAAAA==.Maebell:BAABNQAECn8mAAITAAgKIyIWFQBHAgATAAgKIyIWFQBHAgABNQAECgoKPgALAPYhAA==.Mageslayer:BAABNQAECn8wAAMbAAoKjRWsGAAWAgAbAAkK5RWsGAAWAgABAAIKhQ4CYAA8AAAAAA==.Magicpewfred:BAAANQADCgQIBAAAAA==.Magrun:BAAANQADCgUJCQAAAA==.Mahalleinr:BAAANQAECgEIAgAAAA==.Maiggee:BAAANQAECgYIDAAAAA==.Matt:BAACNQAFFH8LAAISAAUKig8jGQDKAAASAAUKig8jGQDKAAA1AAQKfzcAAhIACgpsIecbACgDABIACgpsIecbACgDAAAA.Mavrik:BAABNQAECn9BAAMYAAoKoBitBgBVAgAYAAoKoBitBgBVAgAPAAoKJg3jeQCYAQAAAA==.',
Me='Meatmagic:BAAANQAECggIDAAAAA==.Megapunk:BAAANQAECgQIDgAAAA==.Melanyie:BAAANQADCgMIAwAAAA==.Melfìce:BAAANQADCgYIBgAAAA==.Meudayr:BAEBNQAECn8kAAIHAAoKpBySCQDbAgAHAAoKpBySCQDbAgAAAA==.Meåtheåd:BAAANQADCgcIBwABNQAECggIDAAcAAAAAA==.',
Mi='Millarolly:BAAANQADCggIHAAAAA==.Mischifbomb:BAAANQAECgIIAgAAAA==.Mischifdk:BAAANQADCgIIAgAAAA==.Mischifdots:BAAANQADCgcIDwAAAA==.Mischifgg:BAABNQAECn8cAAIVAAoKShJvZQDvAQAVAAoKShJvZQDvAQAAAA==.Mischïf:BAAANQADCgYICwAAAA==.Mittensmage:BAAANQADCggICAAAAA==.Mittenss:BAAANQADCggICQAAAA==.',
Mn='Mndgblnfred:BAAANQADCgEIAQAAAA==.',
Mo='Mojorisinn:BAAANQAECgQIBAAAAA==.Moobear:BAABNQAECn9VAAIHAAoKAiQLBAApAwAHAAoKAiQLBAApAwAAAA==.Moogie:BAABNQAECn8nAAILAAkKPBt0gQB7AgALAAkKPBt0gQB7AgAAAA==.Mooshades:BAAANQAECgEIAQAAAA==.Moozlock:BAAANQAECgEIAQAAAA==.Morgiana:BAAANQAECgYIDwABNQAECggIAgAcAAAAAA==.Morvaine:BAABNQAECn8aAAIXAAgKVA6CZgCjAQAXAAgKVA6CZgCjAQAAAA==.Moscovio:BAACNQAFFH8qAAQXAAgKqxJTDACqAQAXAAYKdhVTDACqAQAWAAIK1BG6DwCVAAAdAAEKUxD/EQBUAAA1AAQKfz8AAxcACgpCI0cUANQCABcACgpCI0cUANQCABYAAQqtGb5sAEYAAAAA.Mosspaws:BAAANQAECgUICAAAAA==.',
Mt='Mtndewyou:BAABNQAECn8oAAIkAAgKHRJ+JQC0AQAkAAgKHRJ+JQC0AQAAAA==.',
Mu='Mutterutters:BAAANQADCgMIAwAAAA==.',
My='Myrothan:BAAANQAECgQIBwAAAA==.',
['Mì']='Mìschif:BAAANQADCgUIBQAAAA==.',
Na='Napok:BAABNQAECn8gAAQaAAkKNg4/IAABAQAaAAcKpg4/IAABAQAHAAcKxQvxOQDbAAAMAAIK7QKoqQBEAAAAAA==.Nastea:BAAANQADCggICAAAAA==.',
Ni='Nickimihoj:BAAANQAECggIDgAAAA==.Nihr:BAAANQAECgUIBgAAAA==.Ninkarrak:BAAANQAECgYIDQAAAA==.Nitalan:BAAANQABCgIIAgAAAA==.',
Nm='Nme:BAABNQAECn8lAAILAAgKcwrt3gDKAQALAAgKcwrt3gDKAQAAAA==.',
No='Nocturnos:BAABNQAECn8cAAMXAAoKoBrONQA5AgAXAAoKDxnONQA5AgAdAAUKgBj5EwALAQAAAA==.Nonbeliever:BAABNQAECn83AAMDAAoKRBpfagBdAgADAAoKRBpfagBdAgAJAAMKXg5y0QByAAAAAA==.Nonfiction:BAAANQAECgUIBQABNQAECgoKNwADAEQaAA==.Novamancer:BAAANQAECgEIAQAAAA==.',
Nu='Nuph:BAAANQAECgQIBQAAAA==.',
Ny='Nymage:BAABNQAECn9DAAIIAAoK4RdnCABbAgAIAAoK4RdnCABbAgAAAA==.',
Og='Ogdaddy:BAAANQADCggICAAAAA==.',
Ok='Okaerisan:BAAANQADCgMIAwAAAA==.',
Ol='Olord:BAAANQADCgEIAgAAAA==.',
On='Onlyfinns:BAAANQADCgcIBwAAAA==.',
Op='Ophbel:BAAANQADCgMIAwABNQAECgoKMAACAOwfAA==.',
Or='Orack:BAABNQAECn8gAAINAAoKjxUiJQD7AQANAAoKjxUiJQD7AQAAAA==.',
Ou='Outlast:BAAANQADCgYIBgAAAA==.',
Ow='Owch:BAEANQABCgIIAgABNQAECgoKJAAHAKQcAA==.',
Pa='Paleface:BAAANQAECggIDQAAAA==.Pallychango:BAAANQAECgMIAwABNQAECgoKMAACAOwfAA==.Panblind:BAACNQAFFH8VAAMKAAcKIRpuBgC3AQAKAAcKIRpuBgC3AQAjAAMKkhkaAwDlAAA1AAQKfzsAAwoACgomIxEOAHICAAoACgrjIhEOAHICACMABAp1I+wYACMBAAAA.Pandington:BAAANQADCgQIBwAAAA==.Parmageddon:BAACNQAFFH8LAAIGAAUKDRD0GQCfAAAGAAUKDRD0GQCfAAA1AAQKfy0AAgYACgrmHHUsAGYCAAYACgrmHHUsAGYCAAAA.Parmnhammer:BAAANQAECgcIBwABNQAFFAUICwAGAA0QAA==.Parmrageiano:BAABNQAECn8iAAMQAAkKDh6+BgCTAgAQAAkKDh6+BgCTAgAPAAUKaxM9vgD6AAABNQAFFAUICwAGAA0QAA==.',
Pe='Peanought:BAABNQAECn89AAQFAAoKcQ22QACYAQAFAAoK+gq2QACYAQAGAAcKJg4aZAC3AAATAAMKkAm6twB+AAAAAA==.Peetfix:BAABNQAECn8mAAMCAAoKghfyVwAbAgACAAoKghfyVwAbAgAOAAQKZRuloQAyAQAAAA==.Pepsipink:BAAANQAECgEIAQAAAA==.Pets:BAABNQAECn8YAAMSAAoKJh7AHQDKAgASAAoKJh7AHQDKAgAEAAMK9gz6SAB5AAAAAA==.',
Ph='Phelon:BAAANQAECgYIBgABNQAFFAgIGgAUADYbAA==.Phèdre:BAEANQAFFAIIAwABNQAFFAgIFAADAK4OAA==.',
Pi='Picklegrip:BAABNQAECn8qAAIPAAoKcxJWawC/AQAPAAoKcxJWawC/AQAAAA==.Pijak:BAAANQAECgYIDQAAAA==.',
Pl='Planetina:BAAANQADCgcIBwAAAA==.',
Po='Poah:BAABNQAECn8UAAIZAAgKBx9cFgCcAgAZAAgKBx9cFgCcAgAAAA==.Portalcombat:BAAANQAECgIIAgAAAA==.',
Pr='Prettynhealz:BAAANQADCgIIAgAAAA==.Pruflas:BAAANQAECgEIAgAAAA==.',
Ps='Psycodk:BAAANQAECggICwAAAA==.',
Pu='Puggernaut:BAAANQAECgMICwAAAA==.Pumpin:BAAANQAECgMIBAAAAA==.Punkthor:BAABNQAECn8lAAIlAAoKnRStCQCtAQAlAAoKnRStCQCtAQAAAA==.Purgemepappy:BAAANQADCgYIDAAAAA==.Putitinme:BAAANQABCgIIAgAAAA==.',
['Pø']='Pø:BAABNQAECn87AAIZAAoKPhMQFwABAgAZAAoKPhMQFwABAgAAAA==.',
Qk='Qkn:BAAANQAECgIIAwAAAA==.',
Ra='Raf:BAABNQAECn8rAAMCAAoKPCJJCwCNAwACAAoKPCJJCwCNAwAOAAQKZhI/1gBpAAAAAA==.Rafraff:BAAANQAECgIIAQABNQAECgoKKwACADwiAA==.Ragnor:BAAANQAECgIIAgAAAA==.Ratoncita:BAAANQADCgUIBQAAAA==.Rayzee:BAAANQAECgEIAQAAAA==.',
Re='Reisar:BAAANQADCgMIAwAAAA==.Rennera:BAAANQAECgcICwAAAA==.Revalation:BAABNQAECn8gAAMNAAoKkRi2GgBjAgANAAoKkRi2GgBjAgAMAAEKAADHuAAoAAAAAA==.',
Ri='Riachu:BAAANQAECgUIDQAAAA==.Ribeyejoe:BAAANQAECgQIBgAAAA==.',
Ro='Roadblock:BAABNQAECn8dAAIYAAkKeBklDAD7AQAYAAkKeBklDAD7AQAAAA==.Roboorc:BAAANQABCgMIAwAAAA==.Roken:BAAANQADCggICAAAAA==.Rorymcilroy:BAABNQAECn8VAAMOAAcKbRtJVgAPAgAOAAcKbRtJVgAPAgACAAMK9Q0P+QChAAAAAA==.',
Ru='Ruddy:BAAANQADCgUIBQABNQAECgkJIAAaADYOAA==.Ruinguee:BAAANQADCgYIBgAAAA==.',
Sa='Sacrament:BAABNQAECn8uAAIDAAoKxST5CwBDAwADAAoKxST5CwBDAwABNQAFFAIIBwAZANMeAA==.Sagan:BAEANQADCgQIBAABNQAECgcIEAAcAAAAAA==.Saifrah:BAAANQADCggICQAAAA==.Sandasa:BAAANQAECgQIBAAAAA==.Sanivanth:BAAANQADCgQIBAAAAA==.Saragos:BAAANQAECgEIAQABNQAFFAcIFQAIAP0WAA==.Saucerdote:BAABNQAECn8ZAAMnAAoKhxIyDQBiAQAnAAkKhREyDQBiAQAUAAcKegqYNQDnAAAAAA==.Saxon:BAAANQAECgIIAQABNQAECgoKLgASANISAA==.',
Se='Selenix:BAAANQADCgYIBgABNQAECgoKSAAVAPUbAA==.Selinfinite:BAABNQAECn8bAAIeAAoKTiF8IACWAgAeAAoKTiF8IACWAgAAAA==.Selkie:BAABNQAECn8qAAIiAAgKaRJOEwDiAQAiAAgKaRJOEwDiAQAAAA==.Sephtis:BAABNQAECn8UAAQGAAoKpASzcwCHAAAGAAkKsASzcwCHAAATAAgKKAEK2QA9AAAFAAEKgwPXvgAlAAAAAA==.Serenitynow:BAAANQAECgQIBAAAAA==.Sevenlions:BAAANQADCgEIAQAAAA==.',
Sg='Sgge:BAAANQADCgYIBgAAAA==.',
Sh='Shadowmaven:BAABNQAECn8YAAIBAAoKNw1ZEQCzAQABAAoKNw1ZEQCzAQAAAA==.Shakakhan:BAABNQAECn8uAAMCAAkKUyGXPgDaAQACAAgKnSKXPgDaAQAOAAMKUCLbggArAQABNQAECgoKPgALAPYhAA==.Shammer:BAEANQADCggIBgABNQAECgkJIgAGAC0eAA==.Shamshielder:BAEBNQAECn8iAAMGAAkKLR6dLABlAgAGAAkKLR6dLABlAgAFAAMKIwu5nABZAAAAAA==.Sharick:BAABNQAECn8bAAIoAAoKxxmSAQB4AgAoAAoKxxmSAQB4AgAAAA==.Shawdrake:BAAANQAECgUIBQABNQAECgoKOAAOAGgXAA==.Shawlee:BAABNQAECn84AAMOAAoKaBefPAAjAgAOAAoKaBefPAAjAgACAAgKKgv8kAB6AQAAAA==.Sheph:BAAANQAFFAMIAwAAAA==.Shetmage:BAABNQAECn87AAILAAoK0hfojwBgAgALAAoK0hfojwBgAgABNQAFFAYIEgAMALsUAA==.Shettrah:BAACNQAFFH8SAAIMAAYKuxQ6DgCFAQAMAAYKuxQ6DgCFAQA1AAQKf0MAAgwACgqlIbsKAPMCAAwACgqlIbsKAPMCAAAA.Shottdown:BAAANQADCgUIBQAAAA==.Shwoobs:BAAANQAECgEIAQAAAA==.Shädes:BAABNQAECn8UAAIWAAkKugmrCABBAQAWAAkKugmrCABBAQAAAA==.',
Si='Sigasunanvil:BAAANQAECgQIBAAAAA==.Siickboy:BAAANQAECgMIBAAAAA==.Sijious:BAAANQADCggIHwAAAA==.Silhõuette:BAAANQADCggICAAAAA==.Simperhi:BAAANQABCgEIAQAAAA==.Singularity:BAAANQAECgUIDQABNQAECgoKPgALAPYhAA==.',
Sk='Skanktank:BAABNQAECn8gAAIPAAgKxiA3QgDDAgAPAAgKxiA3QgDDAgAAAA==.Skora:BAAANQAECggIAgAAAA==.Skyland:BAAANQADCgcIBwABNQAFFAcIFgAfAEgWAA==.',
Sl='Slicendice:BAAANQAECgEIAQAAAA==.Slinkies:BAAANQADCgYICQABNQAECgkJGQALALwbAA==.Slipknife:BAABNQAECn8dAAIBAAkKABVrMAAgAgABAAkKABVrMAAgAgAAAA==.',
Sm='Smashinppl:BAAANQAECgQIBAABNQAECgoKWAADAEQjAA==.',
Sn='Sneez:BAAANQAECggICQAAAA==.',
So='Somi:BAACNQAFFH8IAAIJAAQK9Rl7DwBNAQAJAAQK9Rl7DwBNAQA1AAQKfyUAAgkACgrhHjUfAPQCAAkACgrhHjUfAPQCAAAA.Sourworms:BAAANQAECgQIBAAAAA==.',
St='Stabbystab:BAAANQAECgYIDQABNQADCgEIAgAcAAAAAA==.Stabybara:BAAANQAECgUICQABNQAECgoKIgAXAC4VAA==.Stankydk:BAABNQAECn8UAAITAAgK0hTVVwCxAQATAAgK0hTVVwCxAQAAAA==.Stankyleg:BAACNQAFFH8QAAMSAAcKYgkeHQDLAAAEAAUKywqYEwAHAQASAAQKPQMeHQDLAAA1AAQKfyMAAgQACQoMGBIbAKkBAAQACQoMGBIbAKkBAAAA.Starhealer:BAAANQAECgcIBgAAAA==.Stewie:BAABNQAECn8YAAIZAAkK4wkqNQBsAQAZAAkK4wkqNQBsAQAAAA==.Stinkbombs:BAAANQAECgcIBwAAAA==.Stinkies:BAAANQAECgUICQABNQAECgkJGQALALwbAA==.Stunanddone:BAABNQAECn8bAAIbAAkKpAlQaQBvAQAbAAkKpAlQaQBvAQAAAA==.',
Su='Subrogue:BAAANQAECgQICQABNQAFFAcIHAAEABQcAA==.Sunlest:BAAANQADCgcIJwAAAA==.',
Sw='Swaayshooter:BAAANQAECgUIBwABNQAFFAMIBQABAOYRAA==.',
Sy='Sylphrena:BAACNQAFFH8LAAIVAAUKmRW7EgB+AQAVAAUKmRW7EgB+AQA1AAQKfzAAAhUACgpNGzo1AJMCABUACgpNGzo1AJMCAAAA.Sylvanniia:BAABNQAECn8ZAAMSAAgKjx2MWAAZAgASAAgKqBmMWAAZAgAEAAQKihDaOQC5AAABNQAFFAgIFwAgABYUAA==.',
Ta='Tacow:BAAANQAECgUIDAAAAA==.Talethen:BAABNQAECn8jAAQhAAoKehL8DgBUAQAhAAkK1BP8DgBUAQAgAAgKhwt0FQDZAAAfAAEKZwYrUgAoAAAAAA==.',
Te='Telaragehoof:BAAANQAECgUIBwAAAA==.',
Th='Thatbox:BAAANQAECgcIEwAAAA==.Thedrood:BAABNQAECn9JAAINAAoKriAaDQD3AgANAAoKriAaDQD3AgAAAA==.Thorfyna:BAAANQADCggIDwAAAA==.',
Ti='Tiamät:BAAANQAECggICAAAAA==.Tintinnabula:BAABNQAECn8XAAIdAAYK6A48EQA4AQAdAAYK6A48EQA4AQAAAA==.Tiptronic:BAAANQAECgQICQAAAA==.',
To='Tohk:BAACNQAFFH8RAAIeAAcKhBgtCQCaAQAeAAcKhBgtCQCaAQA1AAQKfzEAAh4ACgotH8wTAAADAB4ACgotH8wTAAADAAAA.Tollee:BAAANQAECgQIBAAAAA==.Tontiamat:BAABNQAECn9FAAIhAAoKTxMlCQDqAQAhAAoKTxMlCQDqAQAAAA==.Tontier:BAABNQAECn8kAAMaAAkKJBbGDgDdAQAaAAkKJBbGDgDdAQANAAMKLw//WQCgAAABNQAECgoKRQAhAE8TAA==.Totembeans:BAAANQAECgQIBQAAAA==.Touchyfred:BAAANQAECgUICAAAAA==.Toxicfury:BAAANQABCgUIBAAAAA==.',
Tr='Traash:BAAANQABCgIIAgAAAA==.Treily:BAABNQAECn8VAAISAAYKYQYA7gDUAAASAAYKYQYA7gDUAAAAAA==.Tricket:BAAANQAECgQICAAAAA==.Trolloladin:BAAANQADCggIDwAAAA==.Truestorm:BAABNQAECn8hAAIDAAkK8AekzwB8AQADAAkK8AekzwB8AQAAAA==.',
Tu='Tuchi:BAABNQAECn8ZAAILAAgKTxz1tgAVAgALAAgKTxz1tgAVAgAAAA==.Turak:BAAANQAECgUIBQAAAA==.',
['Tà']='Tàcobelle:BAABNQAECn8hAAMEAAkK/g/NGQC3AQAEAAkKqArNGQC3AQASAAgKWA7FlgCHAQAAAA==.',
Un='Unpredicted:BAAANQADCgIIAgAAAA==.',
Va='Vanicton:BAABNQAECn8fAAIOAAgKqyHeGQAKAwAOAAgKqyHeGQAKAwAAAA==.',
Ve='Ve:BAABNQAECn8kAAMOAAoK9BqhOQB4AgAOAAkKXxqhOQB4AgAiAAYKTxhbHACeAQAAAA==.Vegh:BAABNQAECn8qAAIeAAgK8SANEgAPAwAeAAgK8SANEgAPAwAAAA==.Velaei:BAAANQAECgEJAQAAAA==.Veldcat:BAAANQAECgYIDAAAAA==.Velddk:BAAANQADCggICAAAAA==.Veriale:BAAANQAECgUICQAAAA==.Verra:BAABNQAECn8pAAIDAAoKxBDZhwC8AQADAAoKxBDZhwC8AQAAAA==.',
Vi='Vitriol:BAAANQAECgMIBAAAAA==.Vivid:BAAANQAECgEIAQAAAA==.',
Vo='Voidfang:BAAANQADCgEIAQAAAA==.',
Wa='Wampa:BAAANQAECgEIAgAAAA==.Wanderblue:BAAANQAECgMIAwAAAA==.Wangstah:BAABNQAECn8aAAISAAkKBRdgdgAjAgASAAkKBRdgdgAjAgAAAA==.Warshaw:BAAANQABCgEIAQABNQAECgoKOAAOAGgXAA==.Wartogoteam:BAABNQAECn9BAAIPAAoKWRxuSQCtAgAPAAoKWRxuSQCtAgAAAA==.Waytogoteam:BAAANQAECgEIAQAAAA==.',
We='Weiss:BAACNQAFFH8VAAMIAAcK/RaTBgCoAAALAAUKBhn1JgBPAQAIAAMKiheTBgCoAAA1AAQKfz0AAwsACgprI0QtADQDAAsACgprI0QtADQDACkABwqhHQcCABQCAAAA.',
Wf='Wf:BAABNQAECn89AAQiAAoKQxHOFQAMAgAiAAoK4hDOFQAMAgAOAAoKewXNkwD9AAACAAEKUg9rNQE0AAAAAA==.',
Wi='Wildshapez:BAAANQAECgMIBAAAAA==.',
Wo='Wonghau:BAEANQAECgMIBgABNQAFFAQIDAAMAJEGAA==.Woog:BAAANQADCgYIBgAAAA==.Worsthunterx:BAAANQAFFAEIAQABNQAFFAcIEAAUAFIgAA==.',
Wr='Wreckedu:BAAANQADCgEIAQAAAA==.',
Wy='Wyldspirit:BAABNQAECn8fAAISAAYKnQiG0gANAQASAAYKnQiG0gANAQAAAA==.Wyreless:BAAANQAECgUIEQABNQAECgoKPQAHADgdAA==.',
Ya='Yaass:BAAANQADCggJCAABNQAECgoKPQAiAEMRAA==.Yagrum:BAAANQAECgEJAQAAAA==.Yahikko:BAABNQAECn8bAAIXAAoKWRIYeQD4AQAXAAoKWRIYeQD4AQAAAA==.',
Ye='Yem:BAABNQAECn8ZAAQWAAkKeyHaEQDnAQAWAAYKZyLaEQDnAQAXAAYKoyDwhADaAQAdAAIKpgyZIQBtAAAAAA==.',
Yo='Yoddaa:BAABNQAECn8+AAQVAAoKNx2tLQCPAgAVAAoKOhutLQCPAgAnAAUK5hp7DQBcAQAUAAUKIwzvQgCiAAABNQAECgoKPAAXAGkfAA==.Yoverre:BAAANQAECgIIAQAAAA==.',
Ze='Zergen:BAAANQADCgYIBgAAAA==.Zetsu:BAAANQAECggIDgABNQAECgoKGwAXAFkSAA==.',
Zh='Zhenya:BAACNQAFFH8GAAILAAUKNAF4PwBzAAALAAUKNAF4PwBzAAA1AAQKfy8AAgsACgofEVDCAAACAAsACgofEVDCAAACAAAA.',
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
