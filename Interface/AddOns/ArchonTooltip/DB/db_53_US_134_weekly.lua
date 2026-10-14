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

local lookup = {'DemonHunter-Devourer','Paladin-Protection','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Druid-Guardian','Unknown-Unknown','Mage-Arcane','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','DemonHunter-Havoc','DeathKnight-Unholy','Shaman-Elemental','Druid-Feral','Druid-Balance','Hunter-BeastMastery','Druid-Restoration','Warrior-Protection','Mage-Frost','Paladin-Holy','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Hunter-Marksmanship','DemonHunter-Vengeance','Shaman-Restoration','DeathKnight-Blood','Priest-Discipline','Evoker-Augmentation','Monk-Mistweaver','Monk-Brewmaster','Warrior-Fury','DeathKnight-Frost','Priest-Shadow','Warlock-Affliction',}
local provider = {region='US',realm='Kilrogg',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abartheris:BAAANQAECgEIAQAAAA==.',
Ac='Acanoffood:BAABNQAECn8kAAIBAAgKShUkIQBAAgABAAgKShUkIQBAAgAAAA==.',
Ad='Adeptus:BAEBNQAECn8WAAICAAcK7hhqIQDVAQACAAcK7hhqIQDVAQAAAA==.',
Ae='Aeliana:BAAANQAECggIEwAAAA==.Aerilue:BAAANQADCgMIAwAAAA==.',
Ag='Aglet:BAABNQAECn8oAAQDAAkKRw4dTgCBAQADAAYKgBEdTgCBAQAEAAcKrAnEKQByAQAFAAYK+wq7DgBGAQAAAA==.Agriopas:BAAANQADCgEIAQABNQAECggIKAAGAMgRAA==.',
Ah='Aharon:BAAANQADCggIFQAAAA==.Aheftyzandy:BAAANQADCgMIAwAAAA==.',
Aj='Ajacz:BAAANQAECgQIBgAAAA==.',
Ak='Akariel:BAAANQAECgMIBQABNQAECggIEQAHAAAAAA==.',
Al='Alassomorph:BAAANQADCggIEwAAAA==.Alataar:BAAANQADCgMIAwAAAA==.Albus:BAABNQAECn8vAAIIAAkKsSGBNQAeAwAIAAkKsSGBNQAeAwAAAA==.Aldasar:BAAANQADCgEIAQAAAA==.Alexrogan:BAAANQADCgYIBgAAAA==.Aliira:BAAANQABCgIIAgAAAA==.Allayna:BAABNQAECn8jAAIJAAkKQCAmLwAKAwAJAAkKQCAmLwAKAwAAAA==.Aloha:BAAANQAECgEIAQAAAA==.Alrya:BAAANQAECgEJAQAAAA==.Alysaliu:BAABNQAECn8kAAMKAAkK/iAmNgCvAgAKAAgKQSEmNgCvAgALAAQK4xYFMAAIAQAAAA==.',
Am='Amishmage:BAAANQAECgMIBAABNQAECggIDAAHAAAAAA==.Amishpaladin:BAAANQAECggIDAAAAA==.Amory:BAAANQADCggIDgABNQAECgYIDAAHAAAAAA==.',
An='Anchor:BAAANQADCgQICAAAAA==.Andja:BAABNQAECn8xAAIMAAkKOCR5BgC/AwAMAAkKOCR5BgC/AwAAAA==.Andromedae:BAAANQAECgUIDgAAAA==.Andurìl:BAAANQADCgcIBwAAAA==.Angela:BAAANQAECgUIBgAAAA==.Angelicshado:BAAANQABCgYIDgAAAA==.',
Ap='Apostasy:BAAANQAECgYIEAABNQAECggIEgAHAAAAAA==.',
Ar='Arborelai:BAAANQAECgUICgAAAA==.Arienh:BAAANQABCgYIBQAAAA==.Armorythis:BAAANQAECgEIAQAAAA==.Arngrum:BAAANQAECgMIBAAAAA==.Arthrex:BAAANQAECgUIDAAAAA==.Arturias:BAAANQADCgcIEwABNQAECgkJKwANAFIfAA==.',
As='Ascendance:BAAANQAECgUIDAABNQAECgkJLAAOAN0bAA==.Ashiok:BAAANQAECgUIDQABNQAECggIMQAPAIwTAA==.Asmobob:BAABNQAECn8ZAAMNAAcKnRaZOQDiAQANAAcKnRaZOQDiAQABAAEKAADBbgAtAAAAAA==.',
At='Athenè:BAAANQAECgEIAQAAAA==.Atröpine:BAAANQADCgUIBgAAAA==.',
Au='Augmentin:BAABNQAECn8sAAQQAAkKWx6pCQClAgAQAAgKrR6pCQClAgAGAAUKVB5MGgDOAQARAAMKPhD2hgCyAAAAAA==.Autumm:BAAANQADCgcIDQAAAA==.',
Av='Ava:BAABNQAECn8aAAISAAYKkArhygBnAQASAAYKkArhygBnAQAAAA==.Avanie:BAAANQAECgEIAQAAAA==.',
Ay='Ayhae:BAAANQAECgEIAQAAAA==.',
Az='Azurelock:BAAANQADCgYICwAAAA==.',
Ba='Babycoffee:BAAANQADCgEIAQAAAA==.Backstabath:BAEANQAECgcIEQAAAA==.Bahamutz:BAAANQADCggIDAAAAA==.Bangbangdou:BAAANQAECgcIEQAAAA==.Bartlebe:BAAANQAECgQIBAAAAA==.Bastor:BAAANQAECgIIAgAAAA==.',
Be='Bearnekkid:BAAANQADCgYIEAABNQAECgkJLAAOAN0bAA==.Bearsgomoo:BAABNQAECn8hAAQTAAgKKyEwDQD5AgATAAgKKyEwDQD5AgARAAcKJhziNwArAgAGAAIK6hqoQgCkAAAAAA==.Beneb:BAAANQAECgMIAwAAAA==.Benebeorn:BAACNQAFFH8HAAMNAAMKchAUEwDAAAANAAMKAAkUEwDAAAABAAIKQhPeDwCUAAA1AAQKfy0AAwEACQrvHgsdAGgCAAEACAqqHgsdAGgCAA0AAwoEH8NeAP4AAAAA.Benkinobi:BAAANQAECgQIBwAAAA==.',
Bi='Bichewiche:BAAANQADCgEIAQAAAA==.Bigal:BAAANQADCgcIDAABNQAECgkJHQASAAcYAA==.Billyjoe:BAAANQADCggIDgAAAA==.Binti:BAAANQABCgQIBAAAAA==.Bittronoxus:BAABNQAECn8rAAIIAAcKvQzM8ACmAQAIAAcKvQzM8ACmAQAAAA==.',
Bj='Bjoran:BAAANQABCgIIAgAAAA==.',
Bl='Blackheart:BAAANQABCggIDAAAAA==.Blackseraph:BAAANQADCgUIBwAAAA==.Bleys:BAAANQADCgYIEgABNQAECgkJIwAJAAAWAA==.Blinky:BAAANQADCgYICgAAAA==.',
Bo='Bobbysmerica:BAABNQAECn8cAAIUAAgK2yCOBgD5AgAUAAgK2yCOBgD5AgAAAA==.Bockchoy:BAAANQADCgQIBAAAAA==.Bodikhan:BAAANQAECgQIBAAAAA==.Bovix:BAAANQAFFAIIAwABNQAECgkJHwAIAAkbAA==.',
Br='Braeli:BAAANQADCgUIBQAAAA==.Branimir:BAAANQADCgQIBAAAAA==.Braxte:BAABNQAECn8oAAIMAAkKTCDEHQA/AwAMAAkKTCDEHQA/AwAAAA==.Breecy:BAAANQAECgUIEAAAAA==.Britziola:BAAANQAECgIIAwABNQAECgYIDAAHAAAAAA==.Brozyn:BAAANQADCgUIBQAAAA==.Brusalt:BAAANQAECgQIBAAAAA==.',
Bu='Buggies:BAACNQAFFH8GAAMVAAMK+hWPCACTAAAVAAIKLQ6PCACTAAAIAAEKkyWsUQBvAAA1AAQKfzIAAwgACQrrIj0sADYDAAgACQpOIj0sADYDABUAAgq7H0csAJYAAAAA.Buggs:BAAANQAFFAEIAQABNQAFFAMIBgAVAPoVAA==.Buldozz:BAABNQAECn8mAAIWAAkKdhpGKwC4AgAWAAkKdhpGKwC4AgAAAA==.Burnination:BAABNQAECn8hAAIVAAcKsyTqAwD4AgAVAAcKsyTqAwD4AgAAAA==.Burnzie:BAAANQAECgEIAQAAAA==.Butterfayce:BAABNQAECn8jAAMWAAkKnBbvPwBiAgAWAAkKnBbvPwBiAgAJAAUKAw+fCQEIAQAAAA==.',
Ca='Cadastrasz:BAABNQAECn9RAAMXAAkK9hSyEgCAAgAXAAkK9hSyEgCAAgAYAAIKTAbnNQBcAAAAAA==.Cae:BAAANQAECgcIDgAAAA==.Camachopres:BAAANQADCgQICQAAAA==.Cameocreme:BAABNQAECn8VAAISAAcKaA2IogC9AQASAAcKaA2IogC9AQAAAA==.Cantseeyou:BAAANQADCgcIBwAAAA==.',
Ce='Ceenit:BAABNQAECn8jAAMJAAgKKxU2gQAhAgAJAAgKKxU2gQAhAgACAAQKvQYUVQCKAAAAAA==.Celawyn:BAAANQAECgEIAQAAAA==.',
Ch='Chainedfire:BAAANQAECgEIAQAAAA==.Chasefu:BAAANQADCgQIBAABNQAECgcINgAQAPMXAA==.Chasefury:BAAANQADCgMIAwABNQAECgcINgAQAPMXAA==.Chasemon:BAABNQAECn82AAQQAAcK8xfZEAD2AQAQAAYKaxnZEAD2AQARAAcKpBYuQgDrAQAGAAIKvxhqRwCJAAAAAA==.Chaser:BAAANQAECgQIBAABNQAECgcINgAQAPMXAA==.Chasergoonie:BAAANQAECgEIAQABNQAECgcINgAQAPMXAA==.Chasewise:BAAANQAECgUIDQABNQAECgcINgAQAPMXAA==.Chazz:BAAANQADCgcIBwAAAA==.Chaøtical:BAABNQAECn8XAAMLAAYKFxODQgC5AAAKAAQK6g5z6gDvAAALAAMKRRSDQgC5AAAAAA==.Chelsilly:BAABNQAECn8jAAIZAAgK3xsrNACUAgAZAAgK3xsrNACUAgAAAA==.Chelsily:BAAANQAECgUIBQAAAA==.Chicosan:BAAANQADCgcIEgAAAA==.Chowfu:BAAANQADCgEIAQAAAA==.Chrisolski:BAAANQADCgQIBAABNQAECgQIBAAHAAAAAA==.',
Co='Corien:BAAANQAECgMIBAAAAA==.',
Cr='Crow:BAAANQAECgcIDQAAAQ==.Cryomara:BAAANQADCggICAAAAA==.',
Cu='Cutiepotooti:BAAANQAECgQIBAABNQAECgYIGwAZAGUUAA==.',
Cy='Cycosis:BAAANQADCgcIDQAAAA==.Cyndraexa:BAAANQAECgMIBAAAAA==.Cynia:BAAANQAECgUIDgAAAA==.Cyrene:BAACNQAFFH8pAAMSAAgKpyMNAQCPAgASAAYK7iYNAQCPAgAaAAYKziKIAwBNAgA1AAQKfyAAAxoACQp5IxIIAE4DABoACQp5IxIIAE4DABIACQqkFFJ4ABsCAAAA.',
Da='Daegit:BAAANQABCgIIAQAAAA==.Dagoata:BAAANQAECgIIAgAAAA==.Daizy:BAAANQAECgEIAQAAAA==.Dandien:BAAANQADCgEIAQABNQAECgkJKwANAFIfAA==.Danika:BAAANQABCgQIBAAAAA==.Dariabell:BAAANQAECgYICAABNQAECgkJJAADAO8bAA==.Darkless:BAAANQABCgYICgAAAA==.Darthbane:BAAANQAECgEIAQAAAA==.Darthvada:BAAANQAECgUIDgAAAA==.Darthys:BAAANQADCgUIBQAAAA==.Darthzannah:BAAANQABCgYICgAAAA==.',
De='Deirdra:BAAANQADCgUIBQABNQAECgkJIwAJAAAWAA==.Delia:BAAANQADCgcIBwAAAA==.Demonaria:BAABNQAECn8rAAMNAAkKUh8jEwACAwANAAkKcB4jEwACAwAbAAMKoCEWGwADAQAAAA==.Denariah:BAAANQAECgEIAQABNQAECgUIEwAHAAAAAA==.Dernen:BAAANQAECgEIAQAAAA==.Derpnface:BAAANQAECgEIAQAAAA==.Desecration:BAABNQAECn8jAAIBAAkKPCKtBwBVAwABAAkKPCKtBwBVAwABNQAECgkJJgAcALQhAA==.Devilsautho:BAAANQADCggIFwAAAA==.',
Di='Diablos:BAAANQABCggIEAAAAA==.Dirgir:BAABNQAECn8UAAIdAAYK0x1jPgAEAgAdAAYK0x1jPgAEAgAAAA==.Disk:BAACNQAFFH8FAAMDAAMKCwcdEgC8AAADAAMKQwIdEgC8AAAEAAIKVglMDwCTAAA1AAQKfzEABAQACQodG5oOAI0CAAQACQqFGJoOAI0CAAMACQrHE78nAE0CAAUAAgpPBrYYAFYAAAAA.Distonia:BAABNQAECn8ZAAMcAAYKDSRZQgBUAgAcAAYKDSRZQgBUAgAPAAEKAACNOAEvAAAAAA==.',
Dr='Dracheo:BAACNQAFFH8HAAMVAAMKOBlMCACVAAAVAAIKCBNMCACVAAAIAAEKmSWpUQBvAAA1AAQKfzMAAwgACQoyG4lzAJYCAAgACQqLGolzAJYCABUAAgowFqowAHcAAAAA.Dragonbrr:BAAANQADCgMIAwABNQAECgQICwAHAAAAAA==.Drakmore:BAAANQAECgUIBwABNQAECgUIEgAHAAAAAA==.Drakonna:BAAANQAECgUIEgAAAA==.Drazz:BAAANQADCgIIAgABNQAECgEJAgAHAAAAAA==.Dreammoon:BAAANQABCgYICwAAAA==.Dreygur:BAAANQAECgcIDQAAAA==.Droiden:BAAANQAECgcIDQAAAA==.Droidetté:BAAANQAECgQIBgAAAA==.Droppedbeanz:BAAANQAECgIIAgAAAA==.Drotar:BAAANQAECgYIEgAAAA==.',
Du='Dumbdog:BAACNQAFFH8GAAMRAAMKTAk+GQDXAAARAAMKTAk+GQDXAAATAAIKagxGEgB1AAA1AAQKfxwABBMACQoEH1oPAN0CABMACQoEH1oPAN0CABEAAgpCEuGRAIoAABAAAQp8F/A8AD8AAAE1AAUUBggYABcAGyMA.Dumichauch:BAACNQAFFH8IAAITAAMKExIcDADvAAATAAMKExIcDADvAAA1AAQKfzIAAhMACQpRGwEUAKcCABMACQpRGwEUAKcCAAAA.',
Eg='Egadwall:BAAANQAECgEIAQAAAA==.Eggars:BAABNQAECn8XAAMKAAYKBQXcBQG6AAAKAAQKwQXcBQG6AAALAAIKSQQgaQBOAAAAAA==.',
Ei='Eightyhd:BAAANQAECgUICgAAAA==.',
Ek='Ekhor:BAAANQAECgEIAQAAAA==.',
El='Eliuwu:BAAANQADCgcIDQABNQAECgkJIwAJAEAgAA==.Elyrina:BAAANQADCgQIBAABNQAECgkJIwAJAEAgAA==.',
En='Enky:BAAANQAECgQICgAAAA==.Ennuendo:BAAANQADCgIIAgAAAA==.',
Er='Erodoraendra:BAAANQAECgQIBAAAAA==.',
Eu='Euforia:BAAANQABCgMIAwAAAA==.',
Ev='Eviltiger:BAABNQAECn8vAAMaAAkKhxmPJAAlAgASAAgKXhx/ZwBDAgAaAAkKdhCPJAAlAgAAAA==.',
Ew='Ewik:BAABNQAECn8lAAIXAAkK1RxwCgD7AgAXAAkK1RxwCgD7AgAAAA==.',
Fa='Faent:BAAANQAECgUICgAAAA==.Falimonki:BAAANQAECgUICAAAAA==.Falinora:BAACNQAFFH8IAAIWAAMKVhvlFQD8AAAWAAMKVhvlFQD8AAA1AAQKfzMAAxYACQrMHYIcAAADABYACQrMHYIcAAADAAkABAr1DGYbAeoAAAAA.Falstad:BAABNQAECn8oAAIdAAgKCwoJYwBjAQAdAAgKCwoJYwBjAQAAAA==.Fantasticfox:BAABNQAECn9DAAMKAAkKjBUfSgBxAgAKAAkKaRUfSgBxAgALAAQKvBB1OADeAAAAAA==.Farindor:BAAANQABCgcICAAAAA==.Fattyx:BAABNQAECn8vAAIBAAkKoiRxAwCgAwABAAkKoiRxAwCgAwAAAA==.',
Fe='Felborn:BAAANQABCgQIBAABNQABCgQIBQAHAAAAAA==.Felixs:BAAANQAECgMIBAAAAA==.Feodin:BAABNQAECn8zAAIJAAkKGyQQEwB5AwAJAAkKGyQQEwB5AwAAAA==.',
Fi='Firetaur:BAAANQADCgcIBwAAAA==.Fistariir:BAAANQADCggICAABNQAECggIFwAeAAMeAA==.Fitzchivalry:BAAANQAECgQIBAAAAA==.',
Fl='Flannigan:BAAANQABCgMIAwABNQABCgQIBQAHAAAAAA==.Flatsham:BAAANQAECgUIBgAAAA==.Fleabag:BAAANQADCgMJAwAAAA==.',
Fo='Forcewild:BAAANQAECgUIEgAAAA==.',
Fr='Fraeja:BAAANQADCgYIBgAAAA==.Friean:BAABNQAECn8XAAIVAAcKowaoFwA7AQAVAAcKowaoFwA7AQAAAA==.Frostitut:BAABNQAECn8jAAIIAAkKSRxiWwDJAgAIAAkKSRxiWwDJAgAAAA==.',
Fu='Furflation:BAAANQAECgQICgAAAA==.Fuzzychunks:BAAANQAECgMIBAAAAA==.',
Ga='Gabapentin:BAAANQADCgQIBAABNQAECgkJLAAQAFseAA==.Gano:BAEANQADCggIDgABNQAFFAMIBQAOAF8HAA==.Garr:BAEANQAECgEIAQABNQAECgcIEQAHAAAAAA==.Gazdk:BAABNQAECn8VAAMdAAcKihiiTgC4AQAdAAYK6xuiTgC4AQAOAAEKqAce8gAiAAAAAA==.',
Ge='Geekgirl:BAAANQADCgUIBQAAAA==.',
Gh='Ghevraxion:BAAANQADCgQIBAAAAA==.',
Gi='Giliandra:BAAANQADCgIIAgAAAA==.Gingerbich:BAAANQAECgEIAQAAAA==.',
Gl='Glitch:BAAANQADCgcICAABNQAECggIGAAcAJAUAA==.',
Gn='Gnomerci:BAAANQAECggIBgABNQAFFAcIIgASAD0eAA==.',
Go='Goonthar:BAABNQAECn8kAAIMAAkKRCWIDACSAwAMAAkKRCWIDACSAwAAAA==.Gorethak:BAAANQAECgMIBAAAAA==.',
Gr='Grindpika:BAAANQADCggICAAAAA==.Grindrage:BAAANQAECgcIEwAAAA==.Gripmedaddy:BAAANQAECgUIEwAAAA==.Grollgrr:BAAANQAECgIIBAAAAA==.Grompo:BAAANQAECgEIAQABNQAECgkJGwAIAPcQAA==.Gromps:BAAANQAFFAMIAwAAAA==.Grompy:BAABNQAECn8bAAMIAAkK9xAhowA6AgAIAAkK9xAhowA6AgAVAAEKVwu9QgA8AAAAAA==.Gruffnstuff:BAAANQAECgMIBAAAAA==.',
Gu='Gungan:BAAANQADCgUIBQAAAA==.',
Gy='Gyomei:BAAANQADCgUIBQAAAA==.Gyxx:BAAANQADCggICAAAAA==.',
['Gò']='Gòaf:BAABNQAECn8dAAITAAgKYyNPCQAtAwATAAgKYyNPCQAtAwAAAA==.',
Ha='Haddice:BAAANQAECgUIDgAAAA==.Hairyarmpit:BAAANQADCgQIBAAAAA==.Hairyteeth:BAAANQAECgUICAAAAA==.Halgrad:BAEANQAECggIBQAAAA==.Hammerdaddy:BAAANQADCgUICQABNQAECgUIEwAHAAAAAA==.Hantoll:BAAANQABCgQIBQAAAA==.Harriedotter:BAAANQABCgIIAgAAAA==.',
He='Heebiejeebie:BAAANQAFFAEIAQAAAA==.Hellaeus:BAAANQAECgcIEwAAAA==.Henne:BAEANQAECgIIBQABNQAECggIBQAHAAAAAA==.Heswithme:BAAANQADCggIEAAAAA==.',
Hi='Hisokä:BAABNQAECn8oAAINAAkK5hGBKwBCAgANAAkK5hGBKwBCAgAAAA==.',
Ho='Holycreambar:BAABNQAECn8gAAIJAAgK9BpMWQCIAgAJAAgK9BpMWQCIAgAAAA==.Hottrikk:BAAANQABCgYIEQAAAA==.',
Hu='Huckanimal:BAAANQAECgEIAQABNQAECgQIBgAHAAAAAA==.Huntingale:BAAANQADCgYICwAAAA==.Huntinshift:BAAANQADCgcIEAAAAA==.Hurajin:BAAANQADCgYIEgAAAA==.',
Hy='Hydronir:BAAANQAECgcICwABNQAFFAYIGAAXABsjAA==.Hygelak:BAAANQAECgUICQAAAA==.Hypaxia:BAAANQAECgUIBwAAAA==.',
Ig='Iggysmalls:BAAANQADCgEIAQAAAA==.',
Im='Immoc:BAAANQADCggIDgAAAA==.Impresario:BAAANQAECgUICAAAAA==.',
In='Infidius:BAAANQADCggIFAAAAA==.Intodeep:BAABNQAECn8dAAISAAkKBxhdRwCUAgASAAkKBxhdRwCUAgAAAA==.',
Ja='Jagons:BAAANQAECgUIDgAAAA==.Jahfar:BAAANQAECgUICQAAAA==.Janara:BAAANQAECgQIBAAAAA==.',
Je='Jehtadin:BAAANQADCgcIBwABNQAECgkJIwAKAGEcAA==.Jehtlock:BAABNQAECn8jAAMKAAkKYRzeKwDTAgAKAAkKYRzeKwDTAgALAAQKohKYMQD/AAAAAA==.Jehtstab:BAAANQADCgIIAgABNQAECgkJIwAKAGEcAA==.',
Ji='Jickson:BAAANQAECgIIAgAAAA==.Jimvisible:BAAANQAECgQIDgAAAA==.',
Jo='Joan:BAAANQAECgIIAwABNQAECgkJLwAIALEhAA==.Johadro:BAAANQAECgEIAQAAAA==.',
Ju='Judgejobrown:BAAANQADCgMIAwAAAA==.Judgenawt:BAAANQAECgYIBgAAAA==.',
Ka='Kahlanah:BAAANQAECgYICwAAAA==.Kaiá:BAAANQADCgYIBgAAAA==.Kallum:BAAANQAECgQICQAAAA==.Kaltak:BAAANQADCggIAgAAAA==.Karn:BAABNQAECn8hAAIJAAkK+xTLiAAQAgAJAAkK+xTLiAAQAgAAAA==.Karti:BAAANQAECgQICAAAAA==.Karzdormi:BAECNQAFFH8NAAMXAAUKuRlpDQA0AQAXAAQKvRZpDQA0AQAYAAIKDRy+CgClAAA1AAQKfyoABBgACQqQI5MLAK0CABgACAoEI5MLAK0CABcABgpKHfwaABUCAB8AAgoLHVoZAKQAAAAA.Karzsera:BAEANQADCggICAABNQAFFAUIDQAXALkZAA==.Kassicker:BAAANQAECgMIAwAAAA==.Kaylly:BAAANQADCgYIBgABNQAECgcIMAARANERAA==.Kayyllynt:BAABNQAECn8wAAMRAAcK0RHqTwCaAQARAAcK0RHqTwCaAQATAAQKeQ++TQDQAAAAAA==.Kayylynnt:BAAANQADCgEIAQABNQAECgcIMAARANERAA==.Kazmas:BAAANQAECgIIAgABNQAECgUIBQAHAAAAAA==.',
Ke='Kegeraetor:BAAANQAFFAEIAQABNQAFFAMIBgAdAKkWAA==.Keinthdra:BAABNQAECn8hAAMOAAkKph2PHADfAgAOAAkKph2PHADfAgAdAAcKWhVtUwCkAQAAAA==.Keliste:BAAANQADCgMIAwAAAA==.Kennaea:BAAANQADCggIDgABNQAFFAMIBwAVADgZAA==.',
Kh='Khrysais:BAAANQABCgQIBAAAAA==.',
Ki='Kinuye:BAAANQAECgUIEgAAAA==.Kishara:BAAANQADCggICAABNQAFFAMIBgASADkKAA==.',
Kr='Kraio:BAAANQAECgUIEgAAAA==.',
La='Lamora:BAAANQADCggICAAAAA==.Lampard:BAAANQAECgYICwAAAA==.Landarios:BAAANQADCgcIDAABNQAECgkJKwANAFIfAA==.Langtry:BAAANQAECggIEQAAAA==.Laraj:BAABNQAECn83AAISAAkK9xbgPgCsAgASAAkK9xbgPgCsAgAAAA==.Larissaqt:BAECNQAFFH8TAAIJAAUKBRN6CwCNAQAJAAUKBRN6CwCNAQA1AAQKfzwAAgkACQqvIYMiADgDAAkACQqvIYMiADgDAAAA.Latindk:BAAANQADCgYIEwAAAA==.Latinhunter:BAAANQAECgUIDgAAAA==.Latinmonk:BAAANQADCgYIEgAAAA==.Latinshamy:BAAANQAECgUIDgAAAA==.Lavande:BAAANQAECgUICwABNQAECgkJLAAQAFseAA==.',
Le='League:BAAANQADCgUIBQAAAA==.Leara:BAAANQAECgUICgABNQAFFAMIBgASADkKAA==.Legomyagro:BAABNQAECn8mAAMIAAkKXx7+LgAvAwAIAAkKXx7+LgAvAwAVAAEKDBQOQABDAAAAAA==.Lenipi:BAAANQAECgEIAQAAAA==.Leorohan:BAAANQABCgMIAwAAAA==.Letitgo:BAAANQADCgYIBgAAAA==.Leyez:BAAANQABCgEIAQAAAA==.',
Li='Liftmytail:BAAANQADCggICAABNQAECggIIQATACshAA==.Lightshootx:BAAANQAECgEIAgAAAA==.Lilbessy:BAAANQAECgUIDgAAAA==.Lizzia:BAAANQAECgIIAgAAAA==.',
Lo='Loathe:BAAANQABCggIDwAAAA==.Logrey:BAAANQAECgEIAQABNQAECgUIEwAHAAAAAA==.Lonchainyjr:BAAANQADCgIIAgAAAA==.Loneshott:BAABNQAFFH8FAAMaAAMKQg1rFwDJAAAaAAMKDgtrFwDJAAASAAIKdwwaJwCYAAAAAA==.Loup:BAAANQADCgQIBAAAAA==.',
Lu='Lunabellz:BAAANQAECgUIDwAAAA==.Lunavia:BAABNQAECn8XAAISAAYKVx3fjwDmAQASAAYKVx3fjwDmAQAAAA==.Lushie:BAAANQADCgQIBAAAAA==.Luvalotbear:BAAANQAECgcIEAAAAA==.Luxembourge:BAAANQADCgUIBQAAAA==.',
Ly='Lyceus:BAAANQADCgcIBwAAAA==.Lynch:BAAANQADCgUIBgAAAA==.',
Ma='Maalgus:BAAANQAECgUIEwAAAA==.Mad:BAAANQAECgUIBgAAAA==.Maery:BAAANQAECgEIAQAAAA==.Mahota:BAAANQADCgMIAwAAAA==.Maladash:BAAANQAECgIIAgABNQAECgkJMwAJABskAA==.Manachi:BAAANQADCggICAAAAA==.Mananandict:BAAANQAECgIJAgAAAA==.Marfach:BAAANQAECgUIBQAAAA==.Margoul:BAABNQAECn8YAAINAAYKHQNQagDKAAANAAYKHQNQagDKAAAAAA==.Marikk:BAAANQABCggIGwAAAA==.Mayyhem:BAACNQAFFH8YAAIXAAYKGyMSAwBkAgAXAAYKGyMSAwBkAgA1AAQKfyMAAxcACQrCJF8EAGkDABcACQrCJF8EAGkDABgAAwr0EcMpANgAAAAA.',
Mc='Mcallister:BAAANQAECgYIDAAAAA==.Mcjudgin:BAAANQADCgMIAgABNQAECgkJKAAdAK8mAA==.Mcsquid:BAAANQADCgUIBQAAAA==.',
Me='Meatbubble:BAAANQAECgUIBwAAAA==.Mechee:BAAANQADCgYIEwAAAA==.Melonballer:BAAANQADCgUIBQAAAA==.Mercý:BAAANQADCgcIEwAAAA==.Metch:BAAANQAECgUICwAAAA==.',
Mi='Milkncookiee:BAAANQABCgUIBwAAAA==.Mimiker:BAACNQAFFH8GAAIYAAMK2ArMCQDHAAAYAAMK2ArMCQDHAAA1AAQKfzIAAxgACQq3IZoFADYDABgACQq3IZoFADYDABcAAgqlAcNKAEgAAAAA.Mimilock:BAAANQAECgUICAABNQAFFAMIBgAYANgKAA==.Minime:BAACNQAFFH8IAAIaAAUKHheyCgCPAQAaAAUKHheyCgCPAQA1AAQKfyMAAxIACQqgIwwUAE0DABIACQr+IgwUAE0DABoACAr4GZUeAFkCAAE1AAUUBwgiABIAPR4A.Miniobi:BAAANQADCgYIFAAAAA==.Mirabella:BAAANQADCgcIBwAAAA==.Mistikeye:BAAANQAECgEIAQAAAA==.Mizahella:BAAANQAECgQIDwAAAA==.',
Mo='Mobo:BAAANQAECgMIBAAAAA==.Mofassa:BAAANQADCgEIAQAAAA==.Mojoso:BAAANQAECgUICwAAAA==.Mokei:BAAANQADCggIDwAAAA==.Mokushi:BAAANQAECgUIBQAAAA==.Mondragore:BAABNQAECn8YAAMgAAcKJxQ2HAC8AQAgAAcKJxQ2HAC8AQAhAAIK9QiZKwBeAAAAAA==.Moriko:BAABNQAECn8mAAISAAkKgBbRUQB4AgASAAkKgBbRUQB4AgAAAA==.Mourn:BAACNQAFFH8GAAIdAAMKqRZoFwDpAAAdAAMKqRZoFwDpAAA1AAQKfzIAAh0ACQo3IpoMAEwDAB0ACQo3IpoMAEwDAAAA.',
Mu='Muertomarrow:BAAANQAECgUIDQAAAA==.Mulroth:BAAANQADCggIFAAAAA==.Mustardseed:BAABNQAECn8oAAIKAAkKMA4vbwANAgAKAAkKMA4vbwANAgAAAA==.',
Na='Naeblis:BAAANQADCgIIAgABNQAECgQIBgAHAAAAAA==.Naliannagoat:BAAANQAECgQICgAAAA==.Narekstwin:BAAANQADCgYIEAABNQAECgQIBgAHAAAAAA==.Narradori:BAAANQAECggIDQAAAA==.Nasrith:BAABNQAECn8jAAIJAAkKABYhbwBOAgAJAAkKABYhbwBOAgAAAA==.Nastro:BAAANQAECgEIAQAAAA==.Naughtica:BAAANQAECgUIEgAAAA==.Navellint:BAAANQAECgUICwAAAA==.Nawticlaws:BAAANQAECgEIAgAAAA==.Nawtifox:BAAANQAECgUICQAAAA==.Nawtishot:BAABNQAECn8kAAISAAkKpR7aJwD3AgASAAkKpR7aJwD3AgAAAA==.',
Ne='Neeb:BAAANQADCgYIBgAAAA==.Nekk:BAABNQAECn8bAAQUAAgK+hkGEQATAgAUAAcKIx0GEQATAgAMAAIK9AhzNgFfAAAiAAEKvA6fLwA/AAAAAA==.',
Ni='Niraleth:BAAANQAECgcIEQAAAA==.Nitebrite:BAAANQAECgUIBwAAAA==.',
No='Noctolupus:BAAANQADCgEIAQAAAA==.Noimia:BAAANQAECgYJEAABNQAECgcIEAAHAAAAAA==.Normanosborn:BAAANQADCgIIAgAAAA==.Notfali:BAACNQAFFH8GAAIJAAMKPBYBFgD3AAAJAAMKPBYBFgD3AAA1AAQKfzEAAgkACQpHI2YdAEwDAAkACQpHI2YdAEwDAAAA.',
['Nï']='Nïssan:BAAANQAECgQICAAAAA==.',
Ob='Obits:BAAANQAECgIIAgAAAA==.Obscûr:BAAANQAECgMIBAAAAA==.',
Od='Oden:BAAANQAECgUICAAAAA==.',
Ok='Oksanabaiul:BAAANQAECgIIAwABNQAECgkJJAAKAP4gAA==.',
Ol='Oleyander:BAAANQAECgQICQAAAA==.Olskimonk:BAAANQADCgYIBgABNQAECgQIBAAHAAAAAA==.',
Om='Omgitsashami:BAABNQAECn8YAAIcAAgKkBT5XAD1AQAcAAgKkBT5XAD1AQAAAA==.',
Op='Oprawinfury:BAAANQADCgYIDAAAAA==.',
Or='Orcanist:BAABNQAECn8ZAAIjAAYKHQ6fXAAsAQAjAAYKHQ6fXAAsAQAAAA==.Oronarcane:BAAANQADCgcIEQAAAA==.',
Os='Osanyin:BAAANQAECgYIEQAAAA==.',
Pa='Pacoesfu:BAAANQAECggICAAAAA==.Padray:BAACNQAFFH8HAAIkAAMK/AzSDgDhAAAkAAMK/AzSDgDhAAA1AAQKfzwAAiQACQoUHvQNAAwDACQACQoUHvQNAAwDAAAA.Pamarolyn:BAAANQADCgYICQAAAA==.Panhia:BAAANQADCgcIEAAAAA==.',
Pe='Pecoes:BAAANQADCgIIAgAAAA==.Pen:BAABNQAECn8hAAIRAAgKsAzLRwDIAQARAAgKsAzLRwDIAQAAAA==.Pepperbottom:BAABNQAECn8hAAMKAAkKAxDKZAAoAgAKAAkKAxDKZAAoAgALAAMKWwZaUQCKAAAAAA==.Perforation:BAABNQAECn8vAAMSAAgK/iXMDAB3AwASAAgK/iXMDAB3AwAaAAEKIBwCewBRAAABNQAECgkJJgAcALQhAA==.',
Pf='Pfft:BAAANQAECgUICQABNQAECgkJLAAOAN0bAA==.',
Ph='Phaedril:BAAANQADCggICAAAAA==.Phaided:BAAANQABCggIFAAAAA==.Phoebere:BAAANQAECgUIDAAAAA==.Phungi:BAAANQAECgUICwAAAA==.',
Pi='Pinkleia:BAAANQAECgIIAgAAAA==.Pinocclio:BAAANQAECgQIDgAAAA==.',
Po='Pocketwizard:BAAANQADCgYIBgAAAA==.Pomelo:BAAANQAECgUIBQAAAA==.Popeums:BAABNQAECn8XAAIZAAYKJwTftQDwAAAZAAYKJwTftQDwAAAAAA==.Poppyqtpi:BAAANQAECgUIDgAAAA==.Poyoh:BAABNQAECn8iAAITAAkKoR2TDgDnAgATAAkKoR2TDgDnAgAAAA==.',
Pr='Pravoce:BAAANQAECgEIAQAAAA==.Prescamacho:BAAANQAECgEIAgAAAA==.Prolific:BAEANQABCgYIBwABNQAECgcIEQAHAAAAAA==.Prolifichds:BAEANQAECgEIAgABNQAECgcIEQAHAAAAAA==.Propane:BAAANQAECgUIBwABNQAECgkJOAAZAHEdAA==.',
Pu='Purification:BAABNQAECn8eAAIWAAkKqxwNHgD3AgAWAAkKqxwNHgD3AgABNQAECgkJJgAcALQhAA==.',
['Pí']='Pínt:BAAANQAECgIIBAAAAA==.',
Ra='Radjason:BAAANQADCggIGQAAAA==.Raeagald:BAAANQADCggIDgABNQAFFAMIBgAdAKkWAA==.Raelyni:BAABNQAECn8jAAIZAAkKOBIpVQAgAgAZAAkKOBIpVQAgAgAAAA==.Rajnagaran:BAAANQAECgYICQAAAA==.Rakion:BAAANQAECgYIBgAAAA==.Rakkah:BAABNQAECn8XAAISAAcKaBv6jADsAQASAAcKaBv6jADsAQAAAA==.Rakkuh:BAAANQADCgYIDgABNQAECgcIFwASAGgbAA==.Raveniss:BAAANQAECgUIBQAAAA==.Rawrie:BAAANQAECgYICgAAAA==.Raygun:BAAANQADCgYIBgABNQAECgYIDAAHAAAAAA==.Rayzorevoker:BAAANQADCggJDQAAAA==.Rayzorlock:BAAANQAECgYICQAAAA==.',
Re='Reconetta:BAAANQAECgQIBAAAAA==.Redhilda:BAAANQAECgQIBQAAAA==.Regal:BAAANQADCgcIBwAAAA==.Relyk:BAAANQADCgEIAQAAAA==.',
Rh='Rhymu:BAAANQADCgUIBQAAAA==.',
Ri='Riallis:BAAANQAECgcIDAABNQAECgkJNAAZAFEfAA==.',
Ro='Rogersoner:BAAANQAECgQIBgAAAA==.Rotation:BAABNQAECn8bAAMbAAYK2hUdFQBWAQAbAAYK2hUdFQBWAQANAAUKsgY6ZgDbAAAAAA==.Rotblade:BAABNQAECn8jAAMFAAgKixizBgBbAgAFAAgKixizBgBbAgADAAEKAAAgpAAsAAAAAA==.Rottontomato:BAAANQADCgQJBAAAAA==.',
Ru='Rudewenn:BAAANQADCgcIBwAAAA==.Runandhide:BAAANQADCgMJAwAAAA==.Ruukia:BAAANQADCgEIAQAAAA==.',
Ry='Ryanthomas:BAAANQADCgYICwAAAA==.',
Sa='Sammabamma:BAABNQAECn8sAAIOAAkK3RvPHADdAgAOAAkK3RvPHADdAgAAAA==.Sapheer:BAAANQADCgQIBgAAAA==.Saralisa:BAAANQADCgUIBQAAAA==.Sarutobii:BAAANQAECgQIBAAAAA==.Sathenoth:BAAANQADCgcIEwAAAA==.Sañtoro:BAAANQAECgUIBgAAAA==.',
Sc='Scy:BAAANQAECgUIDAAAAA==.',
Se='Sertraline:BAAANQAECgEIAQABNQAECgkJLAAQAFseAA==.',
Sh='Shadowmorn:BAABNQAECn8YAAIPAAgK2QXGjwB5AQAPAAgK2QXGjwB5AQAAAA==.Shalako:BAAANQADCgcICwAAAA==.Shambali:BAABNQAECn8lAAMTAAkKRBmDFQCWAgATAAkKRBmDFQCWAgARAAEKAAAZvAAjAAAAAA==.Shamidozz:BAAANQADCgYIBgABNQAECgkJJgAWAHYaAA==.Shandro:BAABNQAECn8jAAIVAAkK4ggSDwC2AQAVAAkK4ggSDwC2AQAAAA==.Shaniallon:BAAANQAECggIEgAAAA==.Sharana:BAAANQADCggICAAAAA==.Shaunï:BAAANQAECgYIEAAAAA==.Shocknawe:BAAANQAECgUIBQAAAA==.Showong:BAABNQAECn8fAAMcAAgK+hOnYQDlAQAcAAgK+hOnYQDlAQAPAAEKAADrQwEqAAAAAA==.',
Si='Silentbolts:BAABNQAECn8uAAIIAAkK3xvleQCKAgAIAAkK3xvleQCKAgABNQAECgkJLwARAIMiAA==.Silentchill:BAABNQAECn8vAAIRAAkKgyIPDgBYAwARAAkKgyIPDgBYAwAAAA==.Silentspirit:BAABNQAECn8WAAMPAAkKTg5VZgDqAQAPAAkKTg5VZgDqAQAcAAIKYA7KCAFQAAABNQAECgkJLwARAIMiAA==.Sinomen:BAAANQAECggIEQABNQAFFAEIAQAHAAAAAA==.',
Sk='Skyblue:BAAANQAECgQJBgAAAA==.',
Sm='Smokebull:BAAANQAECgEIAgAAAA==.',
Sn='Snowdayz:BAAANQABCgMIBQAAAA==.',
So='Sonarak:BAABNQAECn8oAAIdAAkKryaIAAD3AwAdAAkKryaIAAD3AwAAAA==.Sornafayne:BAAANQAECgEIAQAAAA==.Sorrengail:BAAANQAECgUIEgAAAA==.',
Sp='Sparklebilly:BAAANQAECgIIAgAAAA==.Spy:BAAANQAECgYIBgAAAA==.',
St='Stampa:BAAANQAECgIIAgAAAA==.Starcloud:BAAANQAECgYIDgAAAA==.Starrie:BAAANQAECgYIDgAAAA==.Steelhoof:BAABNQAECn84AAIaAAkKEATvOgB0AQAaAAkKEATvOgB0AQAAAA==.Steil:BAAANQAECgEIAQAAAA==.Steponmyface:BAAANQAECgQICgABNQAECggIIQATACshAA==.Stewie:BAAANQADCgcICQABNQADCggICAAHAAAAAA==.Stonesoul:BAAANQADCgcIBwAAAA==.Stormfury:BAEANQAECgIIAgABNQAECgcIEQAHAAAAAA==.Strucker:BAAANQADCgUIBgABNQAECgkJIwAhABEfAA==.Struckerzz:BAAANQAECgUICAAAAA==.Struckophile:BAAANQADCgcIDQAAAA==.Struckrucker:BAABNQAECn8jAAIhAAkKER8vBQARAwAhAAkKER8vBQARAwAAAA==.',
Su='Succubussi:BAABNQAECn8rAAMKAAkKFBZ6VABVAgAKAAkKFBZ6VABVAgALAAIKew3CXQBpAAAAAA==.Sushie:BAABNQAECn8WAAMZAAkKlBMuTgA2AgAZAAkKlBMuTgA2AgAkAAEKAADshAAjAAABNQAFFAYIEwAWAJsRAA==.',
Sw='Swipe:BAAANQADCggIDwAAAA==.',
Sy='Synge:BAAANQABCggIGQAAAA==.Synn:BAAANQADCgQIBAABNQAECgEIAQAHAAAAAA==.Syrena:BAAANQABCgEJAQAAAA==.Syvina:BAAANQAECgMIBAAAAA==.',
Ta='Tabby:BAAANQADCgUIBgAAAA==.Taconight:BAAANQAECgUIEQAAAA==.Tahtanka:BAAANQABCggICAAAAA==.Tallynz:BAAANQAECgUICQAAAA==.Tamaru:BAAANQABCgMIBAAAAA==.Tankornot:BAAANQAECgIIAgAAAA==.Tarasque:BAAANQADCgEIAQAAAA==.Tarlgreyhair:BAAANQADCggIKAAAAA==.Tarnished:BAABNQAECn8aAAIVAAgKCwV6FwA9AQAVAAgKCwV6FwA9AQAAAA==.Tasil:BAAANQADCgUIBQABNQAECgUICgAHAAAAAA==.Tateer:BAAANQAECgYIEAAAAA==.Tateerfel:BAAANQADCggICgABNQAECgYIEAAHAAAAAA==.Tateernugget:BAAANQADCgUICgABNQAECgYIEAAHAAAAAA==.Tater:BAAANQADCgQIBAAAAA==.Tawneestone:BAABNQAECn8oAAIUAAkKcR8kBQAlAwAUAAkKcR8kBQAlAwAAAA==.',
Te='Teedizzle:BAAANQADCgcIDQAAAA==.Teek:BAAANQAECgUJCgAAAA==.Telandaraa:BAABNQAECn80AAMZAAkKUR/4IgDfAgAZAAkKUR/4IgDfAgAkAAcKoQ5jMwCEAQAAAA==.Telrae:BAAANQAECgMIBAAAAA==.Tempestus:BAAANQABCgYIBwAAAA==.Teuton:BAAANQABCgMIAwAAAA==.',
Th='Theldara:BAACNQAFFH8GAAISAAMKOQqEGQDqAAASAAMKOQqEGQDqAAA1AAQKfysAAhIACQq4HqkjAAYDABIACQq4HqkjAAYDAAAA.Themock:BAAANQAECgMIBAAAAA==.Theresjohnny:BAAANQADCgcIEwAAAA==.Thesentinel:BAAANQAECgUIDQABNQAECgkJLAAOAN0bAA==.Theshift:BAABNQAECn8uAAMZAAkKpR6xHQD4AgAZAAkKpR6xHQD4AgAeAAQKUQ9eFwC4AAAAAA==.Thisisjustin:BAAANQAECgIIAgAAAA==.Thoreen:BAAANQAECgEIAQAAAA==.Thrish:BAACNQAFFH8FAAISAAMKgBiyFQAJAQASAAMKgBiyFQAJAQA1AAQKfzEAAhIACQoBIYAlAP8CABIACQoBIYAlAP8CAAAA.Thuggies:BAAANQADCggICAAAAA==.Thunderfist:BAAANQADCggIEAABNQAECgkJMwAJABskAA==.',
Ti='Timothy:BAAANQADCggICAAAAA==.',
To='Totemiclord:BAABNQAECn8xAAIPAAgKjBMPYwD0AQAPAAgKjBMPYwD0AQAAAA==.Totumdaddy:BAAANQADCgYIBgABNQAECgUIEwAHAAAAAA==.',
Ts='Tsavo:BAAANQAECgEIAQAAAA==.',
Tu='Tukarm:BAAANQADCgUIDQAAAA==.',
Tw='Twixbolt:BAAANQAECgQICgABNQAECggIIAAJAPQaAA==.',
Ty='Tyriais:BAABNQAECn8aAAIiAAYKTQ0FFQBJAQAiAAYKTQ0FFQBJAQAAAA==.',
Ub='Ubdead:BAAANQADCgQIBAAAAA==.Ubpriest:BAAANQAECgUIEAAAAA==.',
Ut='Uthrob:BAAANQADCgEIAQAAAA==.',
Va='Valvaa:BAAANQABCgEIAQAAAA==.Vampyre:BAAANQADCgIIAgAAAA==.Vayne:BAACNQAFFH8HAAIMAAMKeAj8JgDBAAAMAAMKeAj8JgDBAAA1AAQKfzIAAgwACQoKIJAuAAEDAAwACQoKIJAuAAEDAAAA.',
Vi='Vindenna:BAABNQAECn8cAAMkAAkK5hi0IAAwAgAkAAgKLRe0IAAwAgAZAAIKQQju4QB5AAAAAA==.Vinge:BAECNQAFFH8FAAIOAAMKXwfwEwDGAAAOAAMKXwfwEwDGAAA1AAQKfy8AAg4ACQpDIj4WAAcDAA4ACQpDIj4WAAcDAAAA.Violetxx:BAABNQAECn8YAAISAAcKRQeaxQByAQASAAcKRQeaxQByAQAAAA==.Viral:BAAANQAECgUIBQAAAA==.Viralswine:BAAANQAECgEIAQAAAA==.',
Vl='Vladi:BAAANQAECgYICQAAAA==.',
Vo='Volgrim:BAAANQAECgEIAQAAAA==.Voltaic:BAABNQAECn8mAAMcAAkKtCGgDABaAwAcAAkKtCGgDABaAwAPAAEKAAALGgFUAAAAAA==.Vorsort:BAAANQADCgUIBQAAAA==.',
Vr='Vraylaros:BAABNQAECn8oAAIcAAkKxSEDDABfAwAcAAkKxSEDDABfAwAAAA==.',
Vy='Vyrista:BAAANQAECgUICwAAAA==.Vyrzeth:BAAANQADCgUIBgAAAA==.Vyzualize:BAAANQAECgQIBAAAAA==.',
Wa='Wae:BAAANQAECgIIAwAAAA==.Waferblade:BAAANQAECgYIBgAAAA==.Waknipi:BAAANQAECgQIDQAAAA==.Wartooth:BAAANQAECgUICQAAAA==.Wauwen:BAAANQADCgIIAgABNQAECgYIDAAHAAAAAA==.Way:BAAANQAECgYICQAAAA==.Waycaps:BAACNQAFFH8IAAIbAAMKgxjQAgD1AAAbAAMKgxjQAgD1AAA1AAQKfykAAxsACQolIjQCAGYDABsACQolIjQCAGYDAA0ABQqHFAFSAEcBAAAA.',
We='Weetbix:BAAANQAECgIIAwAAAA==.',
Wh='Wheresjohnny:BAABNQAECn8jAAIdAAkK1xwyJQCPAgAdAAkK1xwyJQCPAgAAAA==.Whiteaug:BAAANQAECgEIAQABNQAFFAYIGAAXABsjAA==.',
Wi='Wiccked:BAABNQAECn8tAAIlAAgKKxXIBgA5AgAlAAgKKxXIBgA5AgAAAA==.Wildheitt:BAABNQAECn8kAAIWAAkKNRvmJwDHAgAWAAkKNRvmJwDHAgAAAA==.Willsky:BAAANQADCgYIBgAAAA==.Windrange:BAAANQAECgUICAAAAA==.Wintérhoof:BAAANQAECgUICAABNQAECgcIDQAHAAAAAA==.',
Wo='Wonderpally:BAAANQAECgQICAAAAA==.Woodscale:BAAANQAECgEIAQAAAA==.Wovenbones:BAABNQAECn84AAMOAAkKVRkHKgCNAgAOAAkKVRkHKgCNAgAjAAgK6Q7iPwDDAQAAAA==.',
Xx='Xxthequeenbe:BAAANQADCgIIAgAAAA==.',
Ya='Yar:BAAANQADCgIIAgAAAA==.',
Ye='Yergat:BAACNQAFFH8iAAMSAAcKPR7YAwAdAgASAAYK2B7YAwAdAgAaAAYKsBqPBQAAAgA1AAQKf0QAAxoACQr3JX0IAEgDABoACQr7JH0IAEgDABIACAoIJqEmAPsCAAAA.',
Yu='Yuhon:BAAANQAECgMIAwAAAA==.Yupa:BAABNQAECn8bAAIUAAcKURlvEQANAgAUAAcKURlvEQANAgABNQAECgkJJgASAIAWAA==.Yuzuruhanyu:BAAANQADCgYIBgABNQAECgkJJAAKAP4gAA==.',
Za='Zafira:BAAANQAECgYIDAAAAA==.Zainea:BAACNQAFFH8HAAIZAAMK2gsYIADaAAAZAAMK2gsYIADaAAA1AAQKfzcAAhkACQpaHlojAN0CABkACQpaHlojAN0CAAE1AAQKBggMAAcAAAAA.Zarena:BAAANQAECgEIAQAAAA==.Zattani:BAAANQADCgMIBAABNQAECgQICAAHAAAAAA==.',
Ze='Zelblades:BAAANQADCggIDQABNQAECgkJHwADAL8aAA==.Zelrex:BAABNQAECn8fAAMDAAkKvxoAFgDIAgADAAkKvxoAFgDIAgAEAAUK6AWKOQDlAAAAAA==.Zephyrà:BAAANQADCgYIBgAAAA==.Zerazer:BAAANQAECgYICAAAAA==.',
Zh='Zhuntyr:BAAANQAECgUIBwAAAA==.',
Zi='Zierosouls:BAAANQADCgcIDAAAAA==.Ziggedion:BAABNQAECn8jAAIfAAkKoBJiBwA0AgAfAAkKoBJiBwA0AgAAAA==.Zindar:BAABNQAECn8XAAMfAAYKExcbDACVAQAfAAYKExcbDACVAQAXAAUKXQTgOgC+AAAAAA==.Zinnfandel:BAAANQABCgQIBAAAAA==.Ziyan:BAAANQAECgIIAgABNQAECgYIBgAHAAAAAA==.',
Zo='Zolpidem:BAAANQADCgYIBwABNQAECgkJLAAQAFseAA==.',
Zu='Zulljyn:BAAANQADCgQIBAAAAA==.',
['Zò']='Zòmi:BAACNQAFFH8JAAIPAAMKDyE1FQAgAQAPAAMKDyE1FQAgAQA1AAQKfy0AAg8ACQoMI50KAJADAA8ACQoMI50KAJADAAAA.',
['Ár']='Áres:BAABNQAECn8iAAIjAAkKwRLvMgAOAgAjAAkKwRLvMgAOAgAAAA==.',
['Çò']='Çòñstàñtîñè:BAAANQABCgcICwAAAA==.',
['Ït']='Ïtzpäpälötl:BAAANQAECgYIEQAAAA==.',
['Ðr']='Ðrstrange:BAAANQAECgIIAwAAAA==.',
['Ñi']='Ñightwolf:BAAANQADCgEIAQABNQAECgUIBQAHAAAAAA==.',
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
