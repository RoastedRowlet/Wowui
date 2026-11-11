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

local lookup = {'Rogue-Assassination','Shaman-Elemental','Paladin-Retribution','Hunter-Marksmanship','DeathKnight-Frost','DeathKnight-Blood','Druid-Guardian','Mage-Frost','Paladin-Holy','DemonHunter-Devourer','Mage-Arcane','Druid-Balance','Druid-Restoration','Shaman-Restoration','Warrior-Arms','Warrior-Protection','Monk-Mistweaver','Hunter-BeastMastery','DeathKnight-Unholy','Priest-Shadow','Priest-Holy','Warlock-Destruction','Warlock-Demonology','Warrior-Fury','Monk-Windwalker','Druid-Feral','Rogue-Subtlety','Unknown-Unknown','Warlock-Affliction','DemonHunter-Havoc','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','DemonHunter-Vengeance','Paladin-Protection','Monk-Brewmaster','Hunter-Survival','Priest-Discipline','Mage-Fire',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abc:BAAANQADCgIIAgAAAA==.',
Ac='Acheniris:BAAANQAECgQICwAAAA==.',
Ae='Aeviee:BAAANQAECgEIAQAAAA==.',
Ag='Aglain:BAAANQAECggIAQAAAA==.Agrippa:BAABNQAECn8iAAIBAAoKsxBVOQDvAQABAAoKsxBVOQDvAQAAAA==.',
Ah='Ahndhrez:BAABNQAECn8wAAICAAoK7B/kDwDkAgACAAoK7B/kDwDkAgAAAA==.',
Ai='Aidric:BAABNQAECn8cAAIDAAcKZBMKqABoAQADAAcKZBMKqABoAQAAAA==.Airwavez:BAACNQAFFH8PAAIEAAYKshP9CwB/AQAEAAYKshP9CwB/AQA1AAQKf0YAAgQACgoUHDsLAHwCAAQACgoUHDsLAHwCAAAA.',
Ak='Akriel:BAAANQAECgcIEQAAAA==.',
Al='Albrecht:BAAANQAECgcIDAAAAA==.Aldeor:BAAANQAECgIIAgAAAA==.Altra:BAACNQAFFH8LAAMFAAUKqQUBEgCrAAAFAAQKqQUBEgCrAAAGAAEKAACNNgAAAAA1AAQKfzEAAwUACgoxF00uAC8CAAUACgoxF00uAC8CAAYAAQoAAF3aACQAAAAA.Alumit:BAAANQAECgYJEwAAAA==.',
Am='Amoeta:BAABNQAECn89AAIHAAoKOB1ICwC4AgAHAAoKOB1ICwC4AgAAAA==.',
An='Andor:BAAANQADCgcIEAAAAA==.Angelique:BAAANQAECgUIEAAAAA==.Angry:BAAANQADCgYICgAAAA==.Angryapples:BAAANQAECgQJBwAAAA==.Annihilation:BAAANQADCgUIBQAAAA==.',
Ap='Approved:BAAANQADCgYIBQAAAA==.',
Ar='Arconos:BAAANQADCgYIDAABNQAFFAcIFQAIAP0WAA==.Arcstorm:BAAANQAECgEIAgAAAA==.',
As='Ashguard:BAAANQADCgcIDAAAAA==.Asomyrh:BAABNQAECn8iAAIJAAkKng37aQDZAQAJAAkKng37aQDZAQAAAA==.',
Au='Aurial:BAAANQADCgMIAwAAAA==.Auriala:BAAANQAECgYIEQAAAA==.',
Az='Azuriae:BAAANQAECgQIBAAAAA==.',
Ba='Babygirl:BAAANQAECgYICgAAAA==.Baelan:BAAANQAECgQIBAAAAA==.Bananer:BAAANQAECgQICwAAAA==.Banonzarath:BAAANQADCggICAAAAA==.Barrysoetoro:BAAANQADCgcIDAAAAA==.Battlemagic:BAAANQAECgYIBgABNQAECgoKKwAKAOQWAA==.Baulie:BAAANQAECgQIBwAAAA==.',
Bb='Bbqlol:BAAANQAECgQIBgABNQAECgoKPQALAPYhAA==.',
Be='Beefstick:BAAANQADCggIJgAAAA==.Bekroh:BAABNQAECn8YAAMMAAcKfhglSADKAQAMAAcKfhglSADKAQANAAEKbASufAAlAAAAAA==.Bestt:BAAANQAECgYICQAAAA==.',
Bi='Bigchomp:BAACNQAFFH8TAAIOAAcKzB8oBABAAgAOAAcKzB8oBABAAgA1AAQKfy4AAw4ACgq+IN4hAOACAA4ACgq+IN4hAOACAAIAAQoAAD8jAUsAAAAA.Bigdaddyd:BAABNQAECn8oAAMPAAkK8RHqeQCBAQAPAAkKBA7qeQCBAQAQAAcKkhG3HwDnAAAAAA==.Bigdonk:BAAANQADCggJCAAAAA==.Bigfoxlilsox:BAAANQADCgQIBAAAAA==.Bioodlion:BAABNQAECn8sAAIDAAkKgQ4tvgCgAQADAAkKgQ4tvgCgAQAAAA==.Bipolar:BAABNQAECn8pAAIRAAkKigV5HQAgAQARAAkKigV5HQAgAQAAAA==.Bippysmasher:BAABNQAECn8rAAIKAAoK5BacHwBSAgAKAAoK5BacHwBSAgAAAA==.Bishmanistic:BAAANQAECgYIEQAAAA==.',
Bl='Blacblood:BAAANQAECgEIAgAAAA==.Blastemis:BAAANQAECgMIBAAAAA==.Blindweiss:BAAANQADCgcIBwABNQAFFAcIFQAIAP0WAA==.Blinkies:BAABNQAECn8ZAAILAAkKvBs9hAB2AgALAAkKvBs9hAB2AgAAAA==.',
Bo='Bontao:BAACNQAFFH8RAAISAAcKQBQbCgCpAQASAAcKQBQbCgCpAQA1AAQKf0EAAhIACgo1IZ8aAM0CABIACgo1IZ8aAM0CAAAA.Bontaopanda:BAAANQAECgEIAQABNQAFFAcIEQASAEAUAA==.Boomies:BAAANQADCgQJBAABNQAECgkJGQALALwbAA==.Borstenne:BAABNQAECn8kAAITAAkK9iPhCgBkAwATAAkK9iPhCgBkAwAAAA==.Bosco:BAAANQADCgQIBAAAAA==.',
Br='Bresemage:BAAANQAECgQIBAABNQAFFAUIBQAOAD0bAQ==.Bresepls:BAACNQAFFH8FAAIDAAIKAQxfJAB9AAADAAIKAQxfJAB9AAA1AAQKfyAAAwMACQoSGU57AMIBAAMACArpGk57AMIBAAkABAqsFkfOAN8AAAE1AAUUBQgFAA4APRsA.Breseshh:BAACNQAFFH8FAAIOAAUKPRtWFQD1AAAOAAUKPRtWFQD1AAA1AAQKf0EAAw4ACgpeI+0IAHoDAA4ACgpeI+0IAHoDAAIABgo3Ex2OANgAAAAA.Brickbeard:BAAANQAECgQIBAAAAA==.Brickbow:BAAANQADCgYIBgAAAA==.Brickette:BAAANQAECggIEAABNQAFFAcIFgAJAIENAA==.Bricklicker:BAAANQAECgQIBAAAAA==.Bricksquad:BAAANQAECgcIDgAAAA==.Brickthrow:BAACNQAFFH8WAAIJAAcKgQ1NDgB+AQAJAAcKgQ1NDgB+AQA1AAQKfzsAAwkACgpgIG0bAM0CAAkACgpgIG0bAM0CAAMAAQr5D2p/AToAAAAA.Bringdapain:BAAANQAECgUICQAAAA==.',
Bu='Budhistpalm:BAAANQAECgMIAwAAAA==.Burgerburn:BAAANQAECgMICAAAAA==.',
By='Bytherune:BAAANQADCgUIBQAAAA==.Bytheway:BAABNQAECn8ZAAIUAAkKahQDKwDPAQAUAAkKahQDKwDPAQAAAA==.',
['Bé']='Béstt:BAABNQAECn8lAAMCAAoKPRr2KgDUAgACAAoKPRr2KgDUAgAOAAIKDgjl1QBcAAAAAA==.',
Ca='Cadilak:BAACNQAFFH8LAAMNAAUKEg/mCgDyAAANAAQK7wrmCgDyAAAMAAEKAAC+JAAAAAA1AAQKfzIAAw0ACgp8GUAXAIcCAA0ACgp8GUAXAIcCAAwAAwoaD4qNAKAAAAAA.Caelesti:BAABNQAECn8XAAMUAAkK8wu2HgB/AQAUAAkK8wu2HgB/AQAVAAIKYgZp/wAtAAAAAA==.Camlin:BAAANQADCggIDgAAAA==.Carrymemommy:BAAANQADCgUIBQAAAA==.Cassanndra:BAEANQAECggIAwABNQAFFAMIBgADACUKAA==.',
Ch='Cheapshotjoe:BAAANQADCgEIAQAAAA==.Chelbur:BAAANQAECgIIBAAAAA==.Chowderhead:BAABNQAECn8vAAMWAAoKvRiTCQBgAgAWAAkKqROTCQBgAgAXAAcKQhZnmgAPAQAAAA==.',
Ci='Cileb:BAABNQAECn8lAAILAAoK+B+qJwBDAwALAAoK+B+qJwBDAwAAAA==.Civik:BAAANQAECgQIBAAAAA==.',
Co='Cocio:BAABNQAECn8dAAIPAAcKdBS6nQDSAQAPAAcKdBS6nQDSAQABNQAECgoKRwAPAKwbAA==.Conchsniffer:BAACNQAFFH8KAAIDAAQKEBSdCQA1AQADAAQKEBSdCQA1AQA1AAQKf04AAwMACgreIbEfANkCAAMACgreIbEfANkCAAkAAgrPCzPjAEEAAAAA.Conrack:BAAANQADCggICAAAAA==.Copperit:BAABNQAECn8sAAMGAAkKayXdAwBFAwAGAAkKayXdAwBFAwAFAAEKQh8amwBdAAAAAA==.Cornburglar:BAABNQAECn9HAAMPAAoKrBteOQBMAgAPAAoKSRteOQBMAgAYAAIKziDYHwC+AAAAAA==.Corrona:BAEANQAECgMIAgABNQAFFAMIBgADACUKAA==.Cowtaclysmic:BAAANQAECgYIBgAAAA==.',
Cr='Creatlach:BAAANQADCgYIBgABNQAFFAcIFwAOAPQaAA==.Crime:BAABNQAECn8jAAIBAAoKoRz8CABGAgABAAoKoRz8CABGAgABNQAFFAIIBwAZANMeAA==.Crunchwrap:BAABNQAECn8UAAIMAAYK+ATtdwDrAAAMAAYK+ATtdwDrAAAAAA==.',
Ct='Cthul:BAAANQADCggICAAAAA==.',
Cu='Curseus:BAAANQAECgEIAQAAAA==.',
['Câ']='Câlisse:BAACNQAFFH8HAAIZAAIK0x5ODACgAAAZAAIK0x5ODACgAAA1AAQKf0sAAhkACgqGJLADAJoDABkACgqGJLADAJoDAAAA.',
Da='Daddiedk:BAABNQAECn8dAAIFAAcKlBrcPQDVAQAFAAcKlBrcPQDVAQAAAA==.Dahealamon:BAAANQAECgMIBAAAAA==.Daiyan:BAAANQAECgQIBQABNQAECggIGQAaAFsOAA==.Damncats:BAABNQAECn8zAAIYAAoKIBAeDwBxAQAYAAoKIBAeDwBxAQAAAA==.Dandinn:BAAANQADCggICAAAAA==.Danielsboone:BAABNQAECn8fAAISAAYKTw39vAAdAQASAAYKTw39vAAdAQAAAA==.Daowa:BAAANQAECgEIAQAAAA==.Darkmare:BAACNQAFFH8KAAMbAAUKagbIHAB/AAAbAAQKwgbIHAB/AAABAAEKuAX0EgAwAAA1AAQKfzAAAxsACgokF0ERAG0CABsACgrhFUERAG0CAAEAAgrfCtSQAG8AAAAA.Darknemesis:BAAANQAECgQICAABNQAECgUIBwAcAAAAAA==.Darksteps:BAAANQADCgQIBAAAAA==.',
De='Deadhippocow:BAABNQAECn8eAAINAAoK2R24GQBtAgANAAoK2R24GQBtAgAAAA==.Dearth:BAEBNQAECn8VAAIDAAgKgguWFgH6AAADAAgKgguWFgH6AAABNQAFFAMIBgADACUKAA==.Deathbane:BAABNQAECn8lAAQWAAoKCg7fMgD6AAAXAAoK7w3RhQDYAQAWAAUKxAnfMgD6AAAdAAEKhwgALQAwAAAAAA==.Deathwavez:BAABNQAECn8UAAIFAAkKGQxFYwD0AAAFAAkKGQxFYwD0AAAAAA==.Deckard:BAEANQAECggICAABNQAFFAMIBgADACUKAA==.Demayy:BAABNQAECn89AAIRAAoKmBitCADDAgARAAoKmBitCADDAgAAAA==.Demona:BAAANQAECgUICgAAAA==.Demonix:BAABNQAECn86AAMXAAoK8B4pHACaAgAXAAoK8B4pHACaAgAdAAUKmhzrDACPAQAAAA==.Demonshades:BAAANQADCgMIBAAAAA==.Derptron:BAABNQAECn8pAAIIAAoKXRa4CABRAgAIAAoKXRa4CABRAgAAAA==.',
Di='Diluted:BAABNQAECn8UAAMBAAkKyxelGwBAAQAbAAcKmxYMSgC+AQABAAcKuBOlGwBAAQABNQAECgoKPQALAPYhAA==.Dilutedqt:BAABNQAECn89AAILAAoK9iGWLQAzAwALAAoK9iGWLQAzAwAAAA==.Dilutedret:BAABNQAECn8cAAMDAAoKExeMlAD7AQADAAoKExeMlAD7AQAJAAIKEBGuxQB5AAABNQAECgoKPQALAPYhAA==.Dinobrass:BAABNQAECn9NAAISAAkKQhymPABNAgASAAkKQhymPABNAgAAAA==.Dirge:BAABNQAECn8iAAITAAoKiA9zRQADAgATAAoKiA9zRQADAgAAAA==.Dirtylöbster:BAABNQAECn8uAAILAAkKZh6nTADoAgALAAkKZh6nTADoAgAAAA==.Disabel:BAAANQADCggICAAAAA==.Distracto:BAAANQAECggIEAAAAA==.',
Dj='Djinsurgent:BAABNQAECn8oAAMTAAgKzxq/RQABAgATAAgKcxm/RQABAgAGAAgKixPVOgBIAQAAAA==.',
Dl='Dltdjr:BAAANQAECgUIDgABNQAECgoKPQALAPYhAA==.',
Do='Donnybrook:BAAANQAECgYICgAAAA==.Doobysnacks:BAABNQAECn8rAAIGAAkKySMhDADKAgAGAAkKySMhDADKAgAAAA==.Doolittle:BAAANQAECgUIDAAAAA==.Dorfies:BAAANQADCgcJCAABNQAECgkJGQALALwbAA==.Dorns:BAAANQAECgYICgAAAA==.',
Dr='Dragondees:BAAANQADCgYIBAAAAA==.Dralock:BAAANQAECgQIBQABNQAECgQIBAAcAAAAAA==.Dreamyeti:BAAANQADCgEIAQAAAA==.Dreats:BAAANQAECgMIBAAAAA==.Drewmee:BAABNQAECn8WAAIDAAkKmgZF3QBgAQADAAkKmgZF3QBgAQAAAA==.Droovani:BAAANQAECgUICwABNQAECgkJFgADAJoGAA==.Drunkenyeti:BAAANQAECgEIAQAAAA==.',
Du='Duckbeak:BAAANQAECgQICQAAAA==.Duwork:BAABNQAECn8xAAIMAAoKFx7zGAAAAwAMAAoKFx7zGAAAAwAAAA==.',
['Dæ']='Dæmona:BAABNQAECn8yAAIeAAoKchasKQBTAgAeAAoKchasKQBTAgAAAA==.',
Eb='Ebk:BAAANQAECgcIDwAAAA==.Ebkx:BAAANQAECgIIBgAAAA==.',
El='Eladus:BAAANQAECgYIEQAAAA==.Elesus:BAAANQAECgEIAQABNQAECggICAAcAAAAAA==.',
Em='Emblaze:BAAANQADCgUIBQAAAA==.Emrys:BAAANQADCggIBwABNQAECgoKLAASANISAA==.',
En='Enhshaman:BAAANQAECggIEAABNQAFFAcIHAAEABQcAA==.',
Ev='Evilinne:BAAANQAECgQIBAAAAA==.',
Ez='Ezmila:BAAANQADCgEIAQAAAA==.',
Fa='Faedari:BAAANQADCgMIAwAAAA==.Faithpasse:BAABNQAECn8hAAIRAAkK+QrSJgBBAQARAAkK+QrSJgBBAQAAAA==.',
Fe='Felondar:BAABNQAECn8uAAIeAAoK1wy5KQCqAQAeAAoK1wy5KQCqAQAAAA==.Ferarro:BAABNQAECn8WAAITAAgK1B48KACZAgATAAgK1B48KACZAgAAAA==.',
Fi='Findd:BAAANQADCgUIBQAAAA==.Finnadin:BAAANQADCgcIDQAAAA==.Finns:BAABNQAECn8XAAIHAAkKbQw4KQApAQAHAAkKbQw4KQApAQAAAA==.Firulais:BAABNQAECn8sAAISAAoK0hIfTwAbAgASAAoK0hIfTwAbAgAAAA==.Fistuu:BAAANQAECgEIAQAAAA==.',
Fl='Flysky:BAACNQAFFH8WAAIfAAcKSBYdCgCKAQAfAAcKSBYdCgCKAQA1AAQKfzEABB8ACgo5I48GAD4DAB8ACgo5I48GAD4DACAABQoHHq0OAFoBACEABQqPGiojACwBAAAA.',
Fo='Foxsake:BAAANQADCgQIBAAAAA==.',
Fr='Freshpot:BAAANQAECgQICAAAAA==.Frostuss:BAAANQAECgIIAwAAAA==.Frostwyrm:BAAANQADCgYIBgAAAA==.Frènchtoast:BAAANQAECgEIAQABNQAECgoKHgANANkdAA==.',
Fu='Fumbles:BAAANQAECgEIAwAAAA==.Furysbane:BAAANQADCgMIAgAAAA==.Futurefist:BAAANQADCggICAAAAA==.',
Ga='Gabtvrdruid:BAAANQADCgEIAQAAAA==.Galvis:BAAANQAECggICAAAAA==.Garduuk:BAABNQAECn8nAAMNAAoKmhv7DQDxAgANAAoKmhv7DQDxAgAMAAMKJBVdYgCKAAAAAA==.',
Ge='Gearth:BAABNQAECn8bAAIiAAcKwhtsFQARAgAiAAcKwhtsFQARAgAAAA==.Ger:BAAANQADCgYIDAABNQAECgoKOAALACcQAA==.',
Gl='Glucose:BAABNQAECn8iAAIXAAoKLhVoSADpAQAXAAoKLhVoSADpAQAAAA==.',
Go='Gonah:BAABNQAECn8WAAINAAYKGxXZOABXAQANAAYKGxXZOABXAQAAAA==.Gotlieb:BAAANQAECgMICAAAAA==.',
Gr='Gravey:BAABNQAECn8dAAIGAAcKlBt0NgAxAgAGAAcKlBt0NgAxAgAAAA==.Grogger:BAAANQADCgUIBQAAAA==.Grraendal:BAAANQADCgUIBQAAAA==.Grrahtahtah:BAACNQAFFH8cAAIEAAcKFByvAwBOAgAEAAcKFByvAwBOAgA1AAQKfy4AAwQACgrIIVgKADEDAAQACgrIIVgKADEDABIAAQo7E0FLAUkAAAAA.',
Gy='Gymble:BAAANQAECggIAQAAAA==.',
Ha='Hakkim:BAAANQADCggICAAAAA==.Hammerinfred:BAAANQAECgQIBwAAAA==.',
He='Heamight:BAAANQADCgcIBwAAAA==.Heavyguard:BAAANQABCgIIAgAAAA==.Helhunter:BAABNQAECn8gAAIKAAoKsw6aGQDPAQAKAAoKsw6aGQDPAQAAAA==.',
Hi='Hidann:BAAANQAECggIBwABNQAECgoKGwAXAFkSAA==.Himeko:BAAANQAECgQICwABNQAFFAcIFQAIAP0WAA==.Hippayman:BAAANQAECgQICwAAAA==.Hippysmasher:BAAANQAECggIDwABNQAECgoKKwAKAOQWAA==.',
Ho='Holyhooters:BAABNQAECn8xAAIDAAoKIxvbTQCrAgADAAoKIxvbTQCrAgAAAA==.Holypablo:BAAANQAECgcIDgABNQAECgoKKQAVAG8XAA==.Honour:BAABNQAECn86AAIDAAoKBBzLOwBpAgADAAoKBBzLOwBpAgAAAA==.',
Hr='Hrathadin:BAAANQAECggIDgABNQAFFAUICAAeAOoYAA==.Hrathdemon:BAACNQAFFH8IAAMeAAUK6hgPDQDYAAAeAAUKXxQPDQDYAAAKAAEK0RuSEwBWAAA1AAQKf0MABB4ACgqrIXoLANoCAAoACQqrIFUKADUDAB4ACQpwH3oLANoCACMABwoIHzkHAAYCAAAA.Hrathion:BAAANQAECgYIDQABNQAFFAUICAAeAOoYAA==.Hrathman:BAAANQAECgQICAABNQAFFAUICAAeAOoYAA==.',
Hu='Huntermik:BAAANQADCgUIBQAAAA==.Hupa:BAABNQAECn8iAAIDAAcKZyM2XgB+AgADAAcKZyM2XgB+AgAAAA==.Hurtsdonut:BAAANQAECgQIDAABNQAECggICAAcAAAAAA==.Huulis:BAAANQADCggICAAAAA==.',
Ia='Iamheyo:BAABNQAECn8lAAMJAAoKChgDVwAUAgAJAAoKChgDVwAUAgADAAUKcxONNgHIAAAAAA==.',
Ic='Ickeetard:BAAANQADCgcJBwAAAA==.',
Id='Idiotbreath:BAAANQAECgYIEAAAAA==.',
Ie='Ieatcheeks:BAAANQAECgUIEQAAAA==.Ieyasu:BAECNQAFFH8MAAIMAAQKkQb+EwC7AAAMAAQKkQb+EwC7AAA1AAQKfzUAAwwACgoIGzApAI0CAAwACgoIGzApAI0CABoAAgpRGR88AEwAAAE1AAUUBQgMAAIAdRQA.',
Ig='Ignitus:BAAANQAECgQIDgAAAA==.',
Ik='Ikuchi:BAABNQAECn8gAAIfAAoKYQb1FgBtAQAfAAoKYQb1FgBtAQAAAA==.',
Il='Illidornsina:BAABNQAECn8VAAIeAAYKphK6PAAyAQAeAAYKphK6PAAyAQABNQAECgYICgAcAAAAAA==.Illpownyou:BAAANQADCgcIBwABNQAECggIHwAhAKETAA==.',
In='Indigò:BAAANQAECgIIAgAAAA==.Infiniti:BAAANQAECgIIAgAAAA==.Insulinshot:BAAANQAECgIIBAAAAA==.',
Ir='Ironguard:BAAANQABCgMIAwAAAA==.',
It='Itsmagharszn:BAAANQADCgEIAQAAAA==.',
Ja='Jabronipie:BAAANQADCggIBQAAAA==.Jaliano:BAAANQADCgYIBgABNQAECgkJKwAOAAIMAA==.Jameyjasta:BAAANQAECgQICgAAAA==.',
Je='Jeffblades:BAAANQABCgQIBQAAAA==.Jellyroll:BAAANQAECgQIBAAAAA==.Jessica:BAAANQAECgQIEwAAAA==.',
Jh='Jhana:BAAANQAECgEIAQAAAA==.',
Ji='Jingojengo:BAAANQAECgIIBwAAAA==.',
Jj='Jjooaacchhim:BAAANQAECgQIEQAAAA==.',
Jo='Josh:BAAANQAECgMIBwAAAA==.',
Ju='Junglefever:BAAANQADCgYIBgAAAA==.',
Jy='Jyve:BAABNQAECn8wAAISAAkKQhERfQAUAgASAAkKQhERfQAUAgAAAA==.',
Ka='Kadista:BAAANQAECgcIBgAAAA==.Kailin:BAAANQAECgMIBQAAAA==.Kailoon:BAAANQADCggICAAAAA==.Kakashi:BAAANQADCgYIDAAAAA==.Kalda:BAAANQAECgMIBgAAAA==.Kamadan:BAAANQAECgMIAwAAAA==.Kamanactali:BAAANQAECgUIBwAAAA==.Kamele:BAAANQAECgQIBAABNQAECggIGQAaAFsOAA==.Kaneko:BAEBNQAECn8uAAMkAAkKSSP/AwAjAwAkAAkKliL/AwAjAwADAAkKtB79QABYAgABNQAFFAUIDAACAHUUAA==.Kardiz:BAAANQADCgUIBQABNQAECggIAgAcAAAAAA==.Katalina:BAABNQAECn89AAMjAAoK/xOoCQCzAQAjAAoK/xOoCQCzAQAeAAYKwBH+UwBBAQAAAA==.',
Ke='Kelstormhoof:BAAANQADCgcIEQABNQAECgUIBwAcAAAAAA==.',
Kh='Kham:BAACNQAFFH8GAAIYAAUKuQumAQC9AAAYAAUKuQumAQC9AAA1AAQKfzwAAhgACgrhIqEBACUDABgACgrhIqEBACUDAAAA.',
Ki='Kialla:BAAANQAFFAEIAQAAAA==.Kirren:BAAANQADCgIIAgAAAA==.',
Kl='Klais:BAAANQADCgQIBQAAAA==.',
Ko='Kokeovrdose:BAAANQABCgQIBAABNQADCgYICgAcAAAAAA==.Konet:BAAANQADCgQIBAAAAA==.Korrath:BAAANQAECgQIBgABNQAECgUIBwAcAAAAAA==.',
Ky='Kyle:BAAANQAECgEIAQAAAA==.',
La='Lavashiza:BAAANQAECgYIEgAAAA==.',
Le='Leadzorz:BAAANQAECgQICwAAAA==.Leedaddydk:BAAANQAECgEIAQAAAA==.Leeoflight:BAAANQABCgQIBQAAAA==.Legday:BAAANQAECgUIBQAAAA==.Lesaelia:BAAANQAECgUICwAAAA==.',
Li='Lightstorm:BAAANQAECgEIAgAAAA==.Liltotem:BAABNQAECn85AAMOAAoKeBKcWACbAQAOAAoKeBKcWACbAQACAAQK7gd64QDUAAAAAA==.Linaria:BAAANQADCgUIBQAAAA==.Lizzydk:BAAANQAECgMIAwAAAA==.Lizzymonk:BAACNQAFFH8LAAIlAAUK/hmEBADjAAAlAAUK/hmEBADjAAA1AAQKfy8AAiUACgraIYoDAFcDACUACgraIYoDAFcDAAAA.',
Lo='Lockdownlol:BAABNQAECn84AAQSAAkK+CKEOQBWAgASAAgKISSEOQBWAgAEAAcKVh1tKQD/AQAmAAEKAACUFQAAAAABNQAECgoKPQALAPYhAA==.Louisbraille:BAAANQAECgUIBAAAAA==.Lowe:BAAANQADCgIIAgAAAA==.',
Lu='Luluh:BAAANQAECgQIDwAAAA==.',
Ma='Maddog:BAABNQAECn8aAAIWAAgKNgodIABvAQAWAAgKNgodIABvAQAAAA==.Maebell:BAABNQAECn8lAAITAAgKIyLIEwBFAgATAAgKIyLIEwBFAgABNQAECgoKPQALAPYhAA==.Mageslayer:BAABNQAECn8tAAMbAAoKQhWsGAAWAgAbAAkK5RWsGAAWAgABAAIKWA2TXwA5AAAAAA==.Magicpewfred:BAAANQADCgQIBAAAAA==.Magrun:BAAANQADCgUJCQAAAA==.Mahalleinr:BAAANQAECgEIAgAAAA==.Maiggee:BAAANQAECgcIDgAAAA==.Matt:BAACNQAFFH8LAAISAAUKig+aFgDMAAASAAUKig+aFgDMAAA1AAQKfzYAAhIACgpsIecbACgDABIACgpsIecbACgDAAAA.Mavrik:BAABNQAECn89AAMYAAoKkxf+BwAXAgAYAAkKJhn+BwAXAgAPAAoKJg0VcQCZAQAAAA==.',
Me='Meatmagic:BAAANQAECggIDAAAAA==.Megapunk:BAAANQAECgQIDgAAAA==.Melanyie:BAAANQADCgMIAwAAAA==.Melfìce:BAAANQADCgYIBgAAAA==.Meudayr:BAEBNQAECn8kAAIHAAoKpBySCQDbAgAHAAoKpBySCQDbAgAAAA==.Meåtheåd:BAAANQADCgcIBwABNQAECggIDAAcAAAAAA==.',
Mi='Millarolly:BAAANQADCggIFQAAAA==.Mischifbomb:BAAANQAECgIIAgAAAA==.Mischifdk:BAAANQAECgEIAQAAAA==.Mischifdots:BAAANQAECgEIAwAAAA==.Mischifgg:BAABNQAECn8cAAIVAAoKShJvZQDvAQAVAAoKShJvZQDvAQAAAA==.Mischïf:BAAANQADCgYICwAAAA==.Mittensmage:BAAANQADCggICAAAAA==.Mittenss:BAAANQADCggICQAAAA==.',
Mn='Mndgblnfred:BAAANQADCgEIAQAAAA==.',
Mo='Mojorisinn:BAAANQAECgQIBAAAAA==.Moobear:BAABNQAECn9MAAIHAAoK6yN8BAAVAwAHAAoK6yN8BAAVAwAAAA==.Moogie:BAABNQAECn8nAAILAAkKPBt0gQB7AgALAAkKPBt0gQB7AgAAAA==.Mooshades:BAAANQAECgEIAQAAAA==.Moozlock:BAAANQAECgEIAQAAAA==.Morgiana:BAAANQAECgYIEgABNQAECggIAgAcAAAAAA==.Morvaine:BAABNQAECn8aAAIXAAgKVA5bXgCmAQAXAAgKVA5bXgCmAQAAAA==.Moscovio:BAACNQAFFH8oAAQXAAgKNxJTDACqAQAXAAYKdhVTDACqAQAWAAIK1BG6DwCVAAAdAAEKnQ3xDwBVAAA1AAQKfz8AAxcACgpCI3QRANwCABcACgpCI3QRANwCABYAAQqtGb5sAEYAAAAA.Mosspaws:BAAANQAECgUICAAAAA==.',
Mt='Mtndewyou:BAABNQAECn8oAAIkAAgKHRJ+JQC0AQAkAAgKHRJ+JQC0AQAAAA==.',
Mu='Mutterutters:BAAANQADCgMIAwAAAA==.',
My='Myrothan:BAAANQAECgQICQAAAA==.',
['Mì']='Mìschif:BAAANQADCgUIBQAAAA==.',
Na='Napok:BAABNQAECn8ZAAQaAAgKWw4lIgDSAAAHAAYKxQsgNgDbAAAaAAYK+Q4lIgDSAAAMAAIK7QKoqQBEAAAAAA==.Nastea:BAAANQADCggICAAAAA==.',
Ni='Nickimihoj:BAAANQAECggIDgAAAA==.Nihr:BAAANQAECgUIBwAAAA==.Ninkarrak:BAAANQAECgUIDAAAAA==.Nitalan:BAAANQABCgIIAgAAAA==.',
Nm='Nme:BAABNQAECn8lAAILAAgKcwrt3gDKAQALAAgKcwrt3gDKAQAAAA==.',
No='Nocturnos:BAABNQAECn8cAAMXAAoKoBp2MAA+AgAXAAoKDxl2MAA+AgAdAAUKgBj5EwALAQAAAA==.Nonbeliever:BAABNQAECn83AAMDAAoKRBpfagBdAgADAAoKRBpfagBdAgAJAAMKXg5zxwB1AAAAAA==.Nonfiction:BAAANQAECgUIBQABNQAECgoKNwADAEQaAA==.Novamancer:BAAANQAECgEIAgAAAA==.',
Nu='Nuph:BAAANQAECgQIBwAAAA==.',
Ny='Nymage:BAABNQAECn9DAAIIAAoK4RdnCABbAgAIAAoK4RdnCABbAgAAAA==.',
Ok='Okaerisan:BAAANQADCgMIAwAAAA==.',
Ol='Olord:BAAANQADCgEIAgAAAA==.',
Op='Ophbel:BAAANQADCgMIAwABNQAECgoKMAACAOwfAA==.',
Or='Orack:BAABNQAECn8eAAINAAkKhhYiJQD7AQANAAkKhhYiJQD7AQAAAA==.',
Ou='Outlast:BAAANQADCgYIBgAAAA==.',
Ow='Owch:BAEANQABCgIIAgABNQAECgoKJAAHAKQcAA==.',
Pa='Paleface:BAAANQAECggIDQAAAA==.Pallychango:BAAANQAECgMIAwABNQAECgoKMAACAOwfAA==.Panblind:BAACNQAFFH8VAAMKAAcKIRpuBgC3AQAKAAcKIRpuBgC3AQAjAAMKkhkaAwDlAAA1AAQKfzgAAwoACgr5IgsSANwCAAoACgq2IgsSANwCACMABAp1I+wYACMBAAAA.Pandington:BAAANQADCgQIBwAAAA==.Parmageddon:BAACNQAFFH8LAAIGAAUKDRCrFgCmAAAGAAUKDRCrFgCmAAA1AAQKfy0AAgYACgrmHHUsAGYCAAYACgrmHHUsAGYCAAAA.Parmnhammer:BAAANQAECgcIBwABNQAFFAUICwAGAA0QAA==.Parmrageiano:BAABNQAECn8hAAMQAAgKdR5RCABIAgAQAAgKdR5RCABIAgAPAAUKaxO1tAD6AAABNQAFFAUICwAGAA0QAA==.',
Pe='Peanought:BAABNQAECn86AAQFAAoKKA3ROgCdAQAFAAoK+grROgCdAQAGAAYKOQ0fjADRAAATAAMKkAm6twB+AAAAAA==.Peetfix:BAABNQAECn8mAAMCAAoKghfyVwAbAgACAAoKghfyVwAbAgAOAAQKZRuloQAyAQAAAA==.Pepsipink:BAAANQAECgEIAQAAAA==.Pets:BAABNQAECn8YAAMSAAoKJh5jGQDTAgASAAoKJh5jGQDTAgAEAAMK9gznRAB6AAAAAA==.',
Ph='Phelon:BAAANQAECgYIBgABNQAFFAcIGQAUAA4fAA==.Phèdre:BAEANQAFFAEIAQABNQAFFAcIEgADAMoQAA==.',
Pi='Picklegrip:BAABNQAECn8mAAIPAAgKQBRMswCcAQAPAAgKQBRMswCcAQAAAA==.Pijak:BAAANQAECgUIDAAAAA==.',
Pl='Planetina:BAAANQADCgcIBwAAAA==.',
Po='Poah:BAABNQAECn8UAAIZAAgKBx9cFgCcAgAZAAgKBx9cFgCcAgAAAA==.Portalcombat:BAAANQAECgIIAwAAAA==.',
Pr='Prettynhealz:BAAANQADCgIIAgAAAA==.Pruflas:BAAANQAECgEIBAAAAA==.',
Ps='Psycodk:BAAANQAECggIDAAAAA==.',
Pu='Puggernaut:BAAANQAECgMICwAAAA==.Pumpin:BAAANQAECgMIBAAAAA==.Punkthor:BAABNQAECn8hAAIlAAgKWBa7DwDyAQAlAAgKWBa7DwDyAQAAAA==.Purgemepappy:BAAANQADCgYIDAAAAA==.Putitinme:BAAANQAECgEIAQAAAA==.',
['Pø']='Pø:BAABNQAECn87AAIZAAoKPhMzFQACAgAZAAoKPhMzFQACAgAAAA==.',
Qk='Qkn:BAAANQAECgIIAwAAAA==.',
Ra='Raf:BAABNQAECn8rAAMCAAoKPCJJCwCNAwACAAoKPCJJCwCNAwAOAAQKZhKQzQBqAAAAAA==.Rafraff:BAAANQAECgIIAQABNQAECgoKKwACADwiAA==.Ragnor:BAAANQAECgIIAgAAAA==.Ratoncita:BAAANQADCgUIBQAAAA==.Rayzee:BAAANQAECgEIAgAAAA==.',
Re='Reisar:BAAANQADCgMIAwAAAA==.Rennera:BAAANQAECgUIBQAAAA==.Revalation:BAABNQAECn8gAAMNAAoKkRi2GgBjAgANAAoKkRi2GgBjAgAMAAEKAADHuAAoAAAAAA==.',
Ri='Riachu:BAAANQAECgUIDwAAAA==.Ribeyejoe:BAAANQAECgQIBgAAAA==.',
Ro='Roadblock:BAABNQAECn8dAAIYAAkKeBklDAD7AQAYAAkKeBklDAD7AQAAAA==.Roboorc:BAAANQAECgEIAwAAAA==.Roken:BAAANQADCggICAAAAA==.Rorymcilroy:BAABNQAECn8VAAMOAAcKbRtJVgAPAgAOAAcKbRtJVgAPAgACAAMK9Q0P+QChAAAAAA==.',
Ru='Ruddy:BAAANQADCgUIBQABNQAECggIGQAaAFsOAA==.Ruinguee:BAAANQADCgYIBgAAAA==.',
Sa='Sacrament:BAABNQAECn8uAAIDAAoKxSTrCQBKAwADAAoKxSTrCQBKAwABNQAFFAIIBwAZANMeAA==.Sagan:BAEANQADCgQIBAABNQAECggIFAAVAJMeAA==.Saifrah:BAAANQADCggICQAAAA==.Sandasa:BAAANQAECgQIBQAAAA==.Sanivanth:BAAANQADCgQIBAAAAA==.Saragos:BAAANQAECgEIAQABNQAFFAcIFQAIAP0WAA==.Saucerdote:BAABNQAECn8ZAAMnAAoKhxIyDQBiAQAnAAkKhREyDQBiAQAUAAcKegroMQDnAAAAAA==.Saxon:BAAANQAECgIIAgABNQAECgoKLAASANISAA==.',
Se='Selenix:BAAANQADCgYIBgABNQAECgoKPwAVAIkYAA==.Selinfinite:BAABNQAECn8bAAIeAAoKTiF8IACWAgAeAAoKTiF8IACWAgAAAA==.Selkie:BAABNQAECn8nAAIiAAcK4RP1FACsAQAiAAcK4RP1FACsAQAAAA==.Sephtis:BAABNQAECn8UAAQGAAoKpAQUbgCLAAAGAAkKsAQUbgCLAAATAAgKKAEK2QA9AAAFAAEKgwNatQAlAAAAAA==.Serenitynow:BAAANQAECgQIBAAAAA==.Sevenlions:BAAANQADCgEIAQAAAA==.',
Sg='Sgge:BAAANQADCgYIBgAAAA==.',
Sh='Shadowmaven:BAAANQAECgYIEgAAAA==.Shakakhan:BAABNQAECn8tAAMCAAkKUyFfOADeAQACAAgKnSJfOADeAQAOAAMK5yDYfgAgAQABNQAECgoKPQALAPYhAA==.Shammer:BAEANQADCggIBgABNQAECgkJIgAGAC0eAA==.Shamshielder:BAEBNQAECn8iAAMGAAkKLR6dLABlAgAGAAkKLR6dLABlAgAFAAMKIwu5nABZAAAAAA==.Sharick:BAAANQAECgcIEAAAAA==.Shawdrake:BAAANQAECgUIBQABNQAECgoKOAAOAGgXAA==.Shawlee:BAABNQAECn84AAMOAAoKaBf/NgAoAgAOAAoKaBf/NgAoAgACAAgKKgv8kAB6AQAAAA==.Sheph:BAAANQAFFAMIAwAAAA==.Shetmage:BAABNQAECn83AAILAAoKQxbojwBgAgALAAoKQxbojwBgAgABNQAFFAYIEgAMALsUAA==.Shettrah:BAACNQAFFH8SAAIMAAYKuxQ6DgCFAQAMAAYKuxQ6DgCFAQA1AAQKf0MAAgwACgqlIdcJAPYCAAwACgqlIdcJAPYCAAAA.Shottdown:BAAANQADCgUIBQAAAA==.Shwoobs:BAAANQAECgEIAwAAAA==.Shädes:BAABNQAECn8UAAIWAAkKugmaBwBFAQAWAAkKugmaBwBFAQAAAA==.',
Si='Sigasunanvil:BAAANQAECgQIBQAAAA==.Siickboy:BAAANQAECgMIBAAAAA==.Sijious:BAAANQADCggIHwAAAA==.Silhõuette:BAAANQADCggICAAAAA==.Simperhi:BAAANQABCgEIAQAAAA==.Singularity:BAAANQAECgUIEgABNQAECgoKPQALAPYhAA==.',
Sk='Skanktank:BAABNQAECn8gAAIPAAgKxiA3QgDDAgAPAAgKxiA3QgDDAgAAAA==.Skora:BAAANQAECggIAgAAAA==.Skyland:BAAANQADCgcIBwABNQAFFAcIFgAfAEgWAA==.',
Sl='Slicendice:BAAANQAECgEIAQAAAA==.Slinkies:BAAANQADCgYICQABNQAECgkJGQALALwbAA==.Slipknife:BAABNQAECn8dAAIBAAkKABVrMAAgAgABAAkKABVrMAAgAgAAAA==.',
Sm='Smashinppl:BAAANQAECgQIBAABNQAECgoKUgADADAjAA==.',
Sn='Sneez:BAAANQAECggICQAAAA==.',
So='Somi:BAACNQAFFH8IAAIJAAQK9RnHDQBPAQAJAAQK9RnHDQBPAQA1AAQKfyUAAgkACgrhHjUfAPQCAAkACgrhHjUfAPQCAAAA.Sourworms:BAAANQAECgQIBAAAAA==.',
St='Stabbystab:BAAANQAECgYIDwABNQADCgEIAgAcAAAAAA==.Stabybara:BAAANQAECgUICQABNQAECgoKIgAXAC4VAA==.Stankydk:BAABNQAECn8UAAITAAgK0hTVVwCxAQATAAgK0hTVVwCxAQAAAA==.Stankyleg:BAACNQAFFH8QAAMSAAcKYgkeHQDLAAAEAAUKywqYEwAHAQASAAQKPQMeHQDLAAA1AAQKfyAAAgQACQpIFxgbAJQBAAQACQpIFxgbAJQBAAAA.Starhealer:BAAANQAECgcIBgAAAA==.Stewie:BAABNQAECn8YAAIZAAkK4wkqNQBsAQAZAAkK4wkqNQBsAQAAAA==.Stinkbombs:BAAANQAECgcICQAAAA==.Stinkies:BAAANQAECgUICQABNQAECgkJGQALALwbAA==.Stunanddone:BAAANQAECgUIEQAAAA==.',
Su='Subrogue:BAAANQAECgQICQABNQAFFAcIHAAEABQcAA==.Sunlest:BAAANQADCgcIJwAAAA==.',
Sw='Swaayshooter:BAAANQAECgUIBwABNQAFFAMIBQABAOYRAA==.',
Sy='Sylphrena:BAACNQAFFH8LAAIVAAUKmRU9EACGAQAVAAUKmRU9EACGAQA1AAQKfy8AAhUACgpNGzo1AJMCABUACgpNGzo1AJMCAAAA.Sylvanniia:BAAANQAECgYIDgAAAA==.Sylvas:BAAANQAECgEIAQAAAA==.',
Ta='Tacow:BAAANQAECgUIDQAAAA==.Talethen:BAABNQAECn8fAAQhAAgKoROSFwDQAQAhAAgKlxOSFwDQAQAgAAYKVgt0FQDZAAAfAAEKZwYrUgAoAAAAAA==.',
Te='Telaragehoof:BAAANQAECgUIBwAAAA==.',
Th='Thatbox:BAAANQAECgYIEQAAAA==.Thedrood:BAABNQAECn9FAAINAAoK1h8wDQDfAgANAAoK1h8wDQDfAgAAAA==.Thorfyna:BAAANQADCggICAAAAA==.',
Ti='Tiamät:BAAANQAECggICAAAAA==.Tintinnabula:BAABNQAECn8XAAIdAAYK6A48EQA4AQAdAAYK6A48EQA4AQAAAA==.Tiptronic:BAAANQAECgQICQAAAA==.',
To='Tohk:BAACNQAFFH8RAAIeAAcKhBgtCQCaAQAeAAcKhBgtCQCaAQA1AAQKfy4AAh4ACgotH8wTAAADAB4ACgotH8wTAAADAAAA.Tollee:BAAANQAECgQIBAAAAA==.Tontiamat:BAABNQAECn9BAAIhAAoKOxN3CADqAQAhAAoKOxN3CADqAQAAAA==.Tontier:BAABNQAECn8hAAMaAAkKxRWCDQDVAQAaAAkKxRWCDQDVAQANAAMKLw//WQCgAAABNQAECgoKQQAhADsTAA==.Tormero:BAAANQAECgEIAQAAAA==.Totembeans:BAAANQAECgQIBwAAAA==.Touchyfred:BAAANQAECgUICAAAAA==.Toxicfury:BAAANQABCgUIBAAAAA==.',
Tr='Traash:BAAANQABCgIIAgAAAA==.Treily:BAABNQAECn8VAAISAAYKYQax4ADUAAASAAYKYQax4ADUAAAAAA==.Tricket:BAAANQAECgQICgAAAA==.Trolloladin:BAAANQADCggIDwAAAA==.Truestorm:BAABNQAECn8hAAIDAAkK8AekzwB8AQADAAkK8AekzwB8AQAAAA==.',
Tu='Tuchi:BAABNQAECn8ZAAILAAgKTxz1tgAVAgALAAgKTxz1tgAVAgAAAA==.Turak:BAAANQAECgUIBwAAAA==.',
['Tà']='Tàcobelle:BAABNQAECn8ZAAMEAAkK/g+nIQBKAQASAAgKWA6EiQCIAQAEAAcKngunIQBKAQAAAA==.',
Un='Unpredicted:BAAANQADCgIIAgAAAA==.',
Va='Vanicton:BAABNQAECn8fAAIOAAgKqyHeGQAKAwAOAAgKqyHeGQAKAwAAAA==.',
Ve='Ve:BAABNQAECn8kAAMOAAoK9BqhOQB4AgAOAAkKXxqhOQB4AgAiAAYKTxhbHACeAQAAAA==.Vegh:BAABNQAECn8qAAIeAAgK8SANEgAPAwAeAAgK8SANEgAPAwAAAA==.Velaei:BAAANQAECgEJAQAAAA==.Veldcat:BAAANQAECgYIDAAAAA==.Velddk:BAAANQADCggICAAAAA==.Velerai:BAAANQAECgEIAwAAAA==.Veriale:BAAANQAECgQICAAAAA==.Verra:BAABNQAECn8gAAIDAAkKWBKZugCoAQADAAkKWBKZugCoAQAAAA==.',
Vi='Vitriol:BAAANQAECgMIBQAAAA==.Vivid:BAAANQAECgEIAQAAAA==.',
Wa='Wampa:BAAANQAECgEIAgAAAA==.Wanderblue:BAAANQAECgMIAwAAAA==.Wangstah:BAABNQAECn8aAAISAAkKBRdgdgAjAgASAAkKBRdgdgAjAgAAAA==.Warshaw:BAAANQABCgEIAQABNQAECgoKOAAOAGgXAA==.Wartogoteam:BAABNQAECn9BAAIPAAoKWRxuSQCtAgAPAAoKWRxuSQCtAgAAAA==.Waytogoteam:BAAANQAECgEIAQAAAA==.',
We='Weiss:BAACNQAFFH8VAAMIAAcK/RaTBgCoAAALAAUKBhn1JgBPAQAIAAMKiheTBgCoAAA1AAQKfzoAAwsACgprI0QtADQDAAsACgprI0QtADQDACgABArJHO8EAAABAAAA.',
Wf='Wf:BAABNQAECn88AAQiAAoKQxHOFQAMAgAiAAkKihHOFQAMAgAOAAoKewUmiwD/AAACAAEKUg9rNQE0AAAAAA==.',
Wi='Wildshapez:BAAANQAECgMIBAAAAA==.',
Wo='Wonghau:BAEANQAECgMIAwABNQAFFAUIDAACAHUUAA==.Woog:BAAANQADCgYIBgAAAA==.Worsthunterx:BAAANQAFFAEIAQABNQAFFAcIEAAUAFIgAA==.',
Wr='Wreckedu:BAAANQADCgEIAQAAAA==.',
Wy='Wyldspirit:BAABNQAECn8fAAISAAYKnQh5xAAOAQASAAYKnQh5xAAOAQAAAA==.Wyreless:BAAANQAECgUIEwABNQAECgoKPQAHADgdAA==.',
Ya='Yaass:BAAANQADCggJCAABNQAECgoKPAAiAEMRAA==.Yagrum:BAAANQAECgEJAQAAAA==.Yahikko:BAABNQAECn8bAAIXAAoKWRIYeQD4AQAXAAoKWRIYeQD4AQAAAA==.',
Ye='Yem:BAABNQAECn8ZAAQWAAkKeyHaEQDnAQAWAAYKZyLaEQDnAQAXAAYKoyDwhADaAQAdAAIKpgyZIQBtAAAAAA==.',
Yo='Yoddaa:BAABNQAECn83AAQVAAoKnxucPQAvAgAVAAoKiRicPQAvAgAnAAUK5hp7DQBcAQAUAAQKIwyWPgCiAAABNQAECgoKOgAXAPAeAA==.Yoverre:BAAANQAECgIIAQAAAA==.',
Ze='Zergen:BAAANQADCgYIBgAAAA==.Zetsu:BAAANQAECggIDwABNQAECgoKGwAXAFkSAA==.',
Zh='Zhenya:BAACNQAFFH8GAAILAAUKNAEQOgB4AAALAAUKNAEQOgB4AAA1AAQKfy8AAgsACgofEVDCAAACAAsACgofEVDCAAACAAAA.',
Zu='Zuga:BAAANQAECgcIDQAAAA==.',
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
