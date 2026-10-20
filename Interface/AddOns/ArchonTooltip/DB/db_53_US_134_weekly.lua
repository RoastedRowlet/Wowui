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

local lookup = {'DemonHunter-Devourer','Paladin-Protection','Warlock-Demonology','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Druid-Guardian','Mage-Arcane','Paladin-Retribution','Warlock-Destruction','Unknown-Unknown','Warrior-Arms','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','DeathKnight-Frost','DemonHunter-Havoc','DeathKnight-Unholy','Shaman-Elemental','Druid-Feral','Druid-Balance','Druid-Restoration','Warrior-Protection','Mage-Frost','Paladin-Holy','Evoker-Preservation','Evoker-Devastation','Priest-Discipline','Hunter-Marksmanship','DeathKnight-Blood','DemonHunter-Vengeance','Shaman-Restoration','Evoker-Augmentation','Shaman-Enhancement','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Warrior-Fury','Warlock-Affliction',}
local provider = {region='US',realm='Kilrogg',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abartheris:BAAANQAECgUIBQAAAA==.',
Ac='Acanoffood:BAABNQAECn8sAAIBAAgK2hcTBgCwAQABAAgK2hcTBgCwAQAAAA==.',
Ad='Adelil:BAAANQABCggIGgAAAA==.Adeptus:BAEBNQAECn8YAAICAAgKkhXoIQDTAQACAAgKkhXoIQDTAQAAAA==.',
Ae='Aeliana:BAABNQAECn8WAAIDAAkKkQ0XdAAFAgADAAkKkQ0XdAAFAgAAAA==.Aerilue:BAAANQADCgMIAwAAAA==.',
Ag='Aglet:BAABNQAECn8sAAQEAAoKRg1wTwCBAQAEAAcKQA9wTwCBAQAFAAcKrAlEKgByAQAGAAYK+wrLDgBGAQAAAA==.Agriopas:BAAANQADCgEIAQABNQAECgkJKwAHAN8RAA==.',
Ah='Aharon:BAAANQADCggIFQAAAA==.Aheftyzandy:BAAANQADCgMIAwAAAA==.',
Aj='Ajacz:BAAANQAECgQIBgAAAA==.',
Ak='Akariel:BAAANQAECgMIBQABNQAECgkJGAAIAOcSAA==.',
Al='Alassomorph:BAAANQADCggIEwAAAA==.Alataar:BAAANQADCgMIAwAAAA==.Albus:BAABNQAECn8zAAIIAAoKyh9gNgAcAwAIAAoKyh9gNgAcAwAAAA==.Aldasar:BAAANQADCgEIAQAAAA==.Alexrogan:BAAANQADCgYIBgAAAA==.Aliira:BAAANQABCgIIAgAAAA==.Allayna:BAABNQAECn8kAAIJAAkKQCAjMAAJAwAJAAkKQCAjMAAJAwAAAA==.Aloha:BAAANQAECgEIAQAAAA==.Alrya:BAAANQAECgEJAQAAAA==.Alysaliu:BAABNQAECn8oAAMDAAoKnSBNNwCuAgADAAkKySBNNwCuAgAKAAQK4xY+MAAIAQAAAA==.',
Am='Amishmage:BAAANQAECggIDAABNQAECggIDAALAAAAAA==.Amishpaladin:BAAANQAECggIDAAAAA==.Amory:BAAANQADCggIEAABNQAECgYIDwALAAAAAA==.',
An='Anchor:BAAANQADCgQICAAAAA==.Andja:BAABNQAECn86AAIMAAoKASUlAgADAwAMAAoKASUlAgADAwAAAA==.Andromedae:BAABNQAECn8VAAMNAAcKfgrHJgBkAQANAAcKfgrHJgBkAQAOAAUKdw5rQgAfAQAAAA==.Andurìl:BAAANQADCgcIBwAAAA==.Angela:BAAANQAECgUIBgAAAA==.Angelicshado:BAAANQABCgYIDgAAAA==.',
Ap='Apostasy:BAAANQAECgYIEAABNQAECgkJFAAPAO0OAA==.',
Ar='Arborelai:BAAANQAECgUICgABNQAECgYIBgALAAAAAA==.Arienh:BAAANQABCgYIBQAAAA==.Armorythis:BAAANQAECgEIAQAAAA==.Arngrum:BAAANQAECgUICAAAAA==.Arthrex:BAABNQAECn8UAAIQAAcK7h3KMwAPAgAQAAcK7h3KMwAPAgAAAA==.Arturias:BAAANQADCgcIEwABNQAECgoKLgARAMcdAA==.',
As='Ascendance:BAAANQAECgUIEAABNQAECgkJMQASALQcAA==.Ashiok:BAAANQAECgUIEQABNQAECgoKOQATAEcSAA==.Asmobob:BAABNQAECn8eAAMRAAkKbxTLHQAKAQARAAkKbxTLHQAKAQABAAEKAACNcAAtAAAAAA==.',
At='Athenè:BAAANQAECgIIAgAAAA==.Atröpine:BAAANQADCgUIBgAAAA==.',
Au='Augmentin:BAABNQAECn8zAAQHAAoKVx6xBwCEAQAUAAkKYB7HCQClAgAHAAYK9hyxBwCEAQAVAAMK5hJWiACyAAAAAA==.Autumm:BAAANQADCgcIDQAAAA==.',
Av='Ava:BAABNQAECn8gAAIPAAYKngpeWwD2AAAPAAYKngpeWwD2AAAAAA==.Avanie:BAAANQAECgEIAQAAAA==.',
Ay='Ayhae:BAAANQAECgEIAQAAAA==.',
Az='Azurelock:BAAANQADCgYICwAAAA==.',
Ba='Babycoffee:BAAANQADCgEIAQAAAA==.Backstabath:BAEANQAECgcIEQAAAA==.Bahamutz:BAAANQADCggIDAAAAA==.Bangbangdou:BAAANQAECggIEQAAAA==.Bartlebe:BAAANQAECgQIBAAAAA==.Bastor:BAAANQAECgQIAwAAAA==.',
Be='Bearnekkid:BAAANQADCgYIEAABNQAECgkJMQASALQcAA==.Bearsgomoo:BAABNQAECn8lAAQWAAkK2x9rDQD5AgAWAAkK2x9rDQD5AgAVAAcKJhyPOAAqAgAHAAIK6hoKRACkAAAAAA==.Beneb:BAAANQAECgMIAwAAAA==.Benebeorn:BAACNQAFFH8LAAMBAAQKOBnwAgD5AAABAAQKOBnwAgD5AAARAAMKAAmFEwDAAAA1AAQKfzEAAwEACgr1HWkdAGgCAAEACQqWHWkdAGgCABEAAwoEH9lfAP4AAAAA.Benkinobi:BAAANQAECgQIDAAAAA==.',
Bi='Bichewiche:BAAANQADCgEIAQAAAA==.Bigal:BAAANQADCgcIDAABNQAECgkJHQAPAAcYAA==.Billyjoe:BAAANQADCggIDgAAAA==.Binti:BAAANQABCgQIBAAAAA==.Bittronoxus:BAABNQAECn8yAAIIAAgKcguRRwAtAQAIAAgKcguRRwAtAQAAAA==.',
Bj='Bjoran:BAAANQABCgIIAgAAAA==.',
Bl='Blackheart:BAAANQABCggIDAAAAA==.Blackseraph:BAAANQADCgUIBwAAAA==.Bleys:BAAANQADCgYIEgABNQAECgkJIwAJAAAWAA==.Blinky:BAAANQADCgYICgAAAA==.',
Bo='Bobbysmerica:BAABNQAECn8kAAIXAAgKaiGiAgDTAQAXAAgKaiGiAgDTAQAAAA==.Bockchoy:BAAANQADCgQIBAAAAA==.Bodikhan:BAAANQAECgUIBQAAAA==.Bovix:BAAANQAFFAIIAwABNQAECgkJHwAIAAkbAA==.',
Br='Braeli:BAAANQADCgUIBQAAAA==.Branimir:BAAANQAECgEIAgAAAA==.Braxte:BAABNQAECn8sAAIMAAoKnR9CHgA+AwAMAAoKnR9CHgA+AwAAAA==.Breecy:BAAANQAECgUIEAAAAA==.Britziola:BAAANQAECgUICAABNQAECgYIDwALAAAAAA==.Brozyn:BAAANQADCgUIBQAAAA==.Brusalt:BAAANQAECgQIBAAAAA==.',
Bu='Buggies:BAACNQAFFH8KAAMYAAQKMh0YAgCyAAAYAAIKARkYAgCyAAAIAAIKkyWAHwBpAAA1AAQKfzYAAwgACgqXIkotADQDAAgACgoOIkotADQDABgAAgq7H9IsAJYAAAAA.Buggs:BAAANQAFFAEIAQABNQAFFAQICgAYADIdAA==.Buldozz:BAABNQAECn8sAAIZAAoK8hkxFgCkAQAZAAoK8hkxFgCkAQAAAA==.Burnination:BAABNQAECn8kAAIYAAkKAyT0AwD4AgAYAAkKAyT0AwD4AgAAAA==.Burnzie:BAAANQAECgEIAQAAAA==.Butterfayce:BAABNQAECn8jAAMZAAkKnBbMQABiAgAZAAkKnBbMQABiAgAJAAUKAw+xDQEIAQAAAA==.',
Ca='Cadastrasz:BAABNQAECn9fAAMaAAoKLRfGAQBXAgAaAAoKLRfGAQBXAgAbAAIKTAZmNgBcAAAAAA==.Cae:BAAANQAECgcIDgAAAA==.Camachopres:BAAANQADCgQICQAAAA==.Cameocreme:BAABNQAECn8aAAIPAAcKaA3gpAC8AQAPAAcKaA3gpAC8AQAAAA==.Cantseeyou:BAAANQADCgcIBwAAAA==.',
Ce='Ceenit:BAABNQAECn8nAAMJAAkKHRWRgwAhAgAJAAkKHRWRgwAhAgACAAQKvQYDVgCKAAAAAA==.Celawyn:BAAANQAECgEIAQAAAA==.',
Ch='Chainedfire:BAAANQAECgEIAQAAAA==.Chasefu:BAAANQADCgQIBAABNQAECggIPQAUAEUaAA==.Chasefury:BAAANQADCgMIAwABNQAECggIPQAUAEUaAA==.Chasemon:BAABNQAECn89AAQUAAgKRRp2BQBmAQAVAAcK7BjLQgDqAQAUAAcKoRl2BQBmAQAHAAIKvxj6SACKAAAAAA==.Chaser:BAAANQAECgQIBgABNQAECggIPQAUAEUaAA==.Chasergoonie:BAAANQAECgEIAQABNQAECggIPQAUAEUaAA==.Chasewise:BAABNQAECn8WAAMOAAcKdBTNCQBYAQAOAAcKdBTNCQBYAQAcAAIK3A+uHQB0AAABNQAECggIPQAUAEUaAA==.Chazz:BAAANQADCgcIBwAAAA==.Chaøtical:BAABNQAECn8ZAAMKAAcKZhHoQgC5AAADAAUKfA097QDvAAAKAAMKRRToQgC5AAAAAA==.Chelsilly:BAABNQAECn8qAAINAAkKFBuHFQDFAQANAAkKFBuHFQDFAQAAAA==.Chelsily:BAAANQAECgYIBQAAAA==.Chicosan:BAAANQADCgcIEgAAAA==.Chiledruid:BAAANQADCgMIAwAAAA==.Chowfu:BAAANQADCgEIAQAAAA==.Chrisolski:BAAANQADCgQIBAABNQAECgQIBAALAAAAAA==.',
Co='Corien:BAAANQAECgUICAAAAA==.',
Cr='Crow:BAAANQAECgcIDQABNQAECggIBQALAAAAAQ==.Cryomara:BAAANQADCggICAAAAA==.',
Cu='Cutiepotooti:BAAANQAECgQIBAABNQAECggIIQANAB8TAA==.',
Cy='Cycosis:BAAANQADCgcIDQAAAA==.Cyndraexa:BAAANQAECgUICAAAAA==.Cynia:BAAANQAECgUIEwAAAA==.Cyrene:BAACNQAFFH8rAAMPAAkKeCEpAQCOAgAPAAYK7iYpAQCOAgAdAAcKZiC7AwBMAgA1AAQKfyAAAx0ACQp5IzYIAE0DAB0ACQp5IzYIAE0DAA8ACQqkFDl6ABoCAAAA.',
Da='Daegit:BAAANQABCgIIAQAAAA==.Dagoata:BAAANQAECgYIBwAAAA==.Daizy:BAAANQAECgEIAQAAAA==.Dandien:BAAANQADCgEIAQABNQAECgoKLgARAMcdAA==.Danika:BAAANQABCgQIBAAAAA==.Dariabell:BAAANQAECgcIDQABNQAECgoKLAAEAEwaAA==.Darkless:BAAANQABCgYICgAAAA==.Darthbane:BAAANQAECgQIBQAAAA==.Darthvada:BAABNQAECn8XAAIeAAcKaRTJHAANAQAeAAcKaRTJHAANAQAAAA==.Darthys:BAAANQADCgUIBQAAAA==.Darthzannah:BAAANQABCgYICgAAAA==.',
De='Deirdra:BAAANQADCgUIBQABNQAECgkJIwAJAAAWAA==.Delia:BAAANQADCgcIBwAAAA==.Demonaria:BAABNQAECn8uAAMRAAoKxx2DEwACAwARAAoKAR2DEwACAwAfAAMKoCFjGwADAQAAAA==.Denariah:BAAANQAECgEIAQABNQAECgUIGAAeAHYgAA==.Dernen:BAAANQAECgEIAQAAAA==.Derpnface:BAAANQAECgUIBQAAAA==.Desecration:BAABNQAECn8qAAIBAAoKriLeAwDrAQABAAoKriLeAwDrAQABNQAECgoKLgAgAIEiAA==.',
Di='Diablos:BAAANQABCggIEAAAAA==.Dirgir:BAABNQAECn8bAAIeAAcK4ByYCQCkAQAeAAcK4ByYCQCkAQAAAA==.Disk:BAACNQAFFH8HAAMEAAQKCweUEgC8AAAEAAMKQwKUEgC8AAAFAAMKVgmNDwCTAAA1AAQKfzUABAUACgpmGbUOAI0CAAUACgogF7UOAI0CAAQACQrHE4woAE0CAAYAAgpPBugYAFYAAAAA.Distonia:BAABNQAECn8eAAMgAAcKvSPDEwC2AQAgAAcKvSPDEwC2AQATAAEKAADiPAEvAAAAAA==.',
Dr='Dracheo:BAACNQAFFH8HAAMYAAMKOBl+CACVAAAYAAIKCBN+CACVAAAIAAEKmSUlUwBvAAA1AAQKfzMAAwgACQoyG6p0AJQCAAgACQqLGqp0AJQCABgAAgowFjQxAHcAAAAA.Dragonbrr:BAAANQADCgMIAwABNQAECgUICwALAAAAAA==.Drakmore:BAAANQAECgUICgABNQAECgUIEgALAAAAAA==.Drakonna:BAAANQAECgUIEgAAAA==.Drazz:BAAANQADCgIIAgABNQAECgEJAgALAAAAAA==.Dreammoon:BAAANQABCgYICwAAAA==.Dreygur:BAAANQAECgcIEQAAAA==.Droiden:BAAANQAECgcIEAAAAA==.Droidetté:BAAANQAECgQIBgAAAA==.Droppedbeanz:BAAANQAECgMIAwAAAA==.Drotar:BAABNQAECn8YAAQVAAcKSA+NZAA7AQAVAAYKowyNZAA7AQAWAAMKagRrZAB0AAAUAAEKPw+JQgA1AAAAAA==.',
Du='Dumbdog:BAACNQAFFH8HAAMVAAQKTAmxGQDXAAAVAAMKTAmxGQDXAAAWAAMKUQ2kEgB1AAA1AAQKfx8ABBYACgogH5APAN4CABYACQowH5APAN4CABUAAwpLEn6TAIkAABQAAQp8F4I+AD8AAAE1AAUUBwgZABoAgCAA.Dumichauch:BAACNQAFFH8MAAIWAAQKHg8yBAAjAQAWAAQKHg8yBAAjAQA1AAQKfzYAAhYACgpvGj0UAKgCABYACgpvGj0UAKgCAAAA.',
Eg='Egadwall:BAAANQAECgEIAQAAAA==.Eggars:BAABNQAECn8ZAAMDAAcKaQQLCQG6AAADAAUKfwQLCQG6AAAKAAIKSQSvaQBOAAAAAA==.',
Ei='Eightyhd:BAAANQAECgUICgAAAA==.',
Ek='Ekhor:BAAANQAECgEIAQAAAA==.',
El='Eliuwu:BAAANQADCgcIDQABNQAECgkJJAAJAEAgAA==.Elyrina:BAAANQADCgQIBAABNQAECgkJJAAJAEAgAA==.',
En='Enky:BAAANQAECgQICgAAAA==.Ennuendo:BAAANQADCgIIAgAAAA==.',
Er='Erodoraendra:BAAANQAECgQIBAAAAA==.',
Eu='Euforia:BAAANQABCgMIAwAAAA==.',
Ev='Eviltiger:BAABNQAECn8xAAMdAAoKzBj2JAAlAgAPAAgKXhwEaQBCAgAdAAoK3hD2JAAlAgAAAA==.',
Ew='Ewik:BAABNQAECn8lAAIaAAkK1RyaCgD6AgAaAAkK1RyaCgD6AgAAAA==.',
Fa='Faent:BAAANQAECgcIEAAAAA==.Falimonki:BAAANQAECgUICAAAAA==.Falinora:BAACNQAFFH8MAAIZAAQKbBc8BgBCAQAZAAQKbBc8BgBCAQA1AAQKfz0AAxkACgqYH1IFAIQCABkACgqYH1IFAIQCAAkABAr1DFufAJ8AAAAA.Falstad:BAABNQAECn8qAAIeAAgKCwrNYwBjAQAeAAgKCwrNYwBjAQAAAA==.Fantasticfox:BAABNQAECn9RAAMDAAoKnhT8GgCFAQADAAoKgBT8GgCFAQAKAAQKvBDqCQB/AAAAAA==.Farindor:BAAANQAECgEIAQAAAA==.Fattyx:BAABNQAECn83AAIBAAoKXyODAwCgAwABAAoKXyODAwCgAwAAAA==.',
Fe='Felborn:BAAANQABCgQIBAABNQABCgQIBQALAAAAAA==.Felixs:BAAANQAECgUICQAAAA==.Feodin:BAACNQAFFH8IAAMJAAQKHxoQBwDvAAAJAAMKHxoQBwDvAAAZAAEKWQNDFQBBAAA1AAQKfzcAAgkACgpdI4sTAHgDAAkACgpdI4sTAHgDAAAA.',
Fi='Firetaur:BAAANQADCgcIBwAAAA==.Fistariir:BAAANQADCggICAABNQAECggIFwAcAAMeAA==.Fitzchivalry:BAAANQAECgUIBwAAAA==.',
Fl='Flannigan:BAAANQABCgMIAwABNQABCgQIBQALAAAAAA==.Flatsham:BAAANQAECgYIDQAAAA==.Fleabag:BAAANQADCgMIAwAAAA==.',
Fo='Forcewild:BAABNQAECn8VAAIHAAcK7xqvGwDFAQAHAAcK7xqvGwDFAQAAAA==.',
Fr='Fraeja:BAAANQADCgYIBgAAAA==.Friean:BAABNQAECn8dAAIYAAgKRAfjFwA7AQAYAAgKRAfjFwA7AQAAAA==.Frostitut:BAABNQAECn8jAAIIAAkKSRxqXQDFAgAIAAkKSRxqXQDFAgAAAA==.',
Fu='Furflation:BAAANQAECgQICgAAAA==.Fuzzychunks:BAAANQAECgUICAAAAA==.',
Ga='Gabapentin:BAAANQADCgQIBAABNQAECgoKMwAHAFceAA==.Gano:BAEANQADCggIDgABNQAFFAQICQASAIUQAA==.Garr:BAEANQAECgEIAQABNQAECgcIEQALAAAAAA==.Gazdk:BAABNQAECn8cAAMeAAcKzRmQDwBmAQAeAAcKzRmQDwBmAQASAAEKqAfo9AAiAAAAAA==.',
Ge='Geekgirl:BAAANQAECgIIAQAAAA==.',
Gh='Ghevraxion:BAAANQADCgQIBAAAAA==.',
Gi='Giliandra:BAAANQADCgIIAgAAAA==.Gingerbich:BAAANQAECgEIAQAAAA==.',
Gl='Glitch:BAAANQADCgcICAABNQAECggIHAAgAP0UAA==.',
Gn='Gnomerci:BAAANQAECggIDgABNQAFFAcIKAAPAMQfAA==.',
Go='Goonthar:BAACNQAFFH8GAAIMAAMKJBUGIAAFAQAMAAMKJBUGIAAFAQA1AAQKfyoAAgwACgpUJeQMAJEDAAwACgpUJeQMAJEDAAAA.Gorethak:BAAANQAECgUICAAAAA==.',
Gr='Grindpika:BAAANQADCggICAAAAA==.Grindrage:BAABNQAECn8WAAIMAAgK0x/OVwCEAgAMAAgK0x/OVwCEAgAAAA==.Gripmedaddy:BAABNQAECn8YAAMeAAUKdiD3IAD3AAAeAAUKdiD3IAD3AAASAAEKmQI79AAjAAAAAA==.Grixis:BAAANQAECgEIAQAAAA==.Grollgrr:BAAANQAECgMIBAAAAA==.Grompo:BAAANQAECgEIAQABNQAECgoKIQAIAPAPAA==.Gromps:BAABNQAFFH8HAAMKAAQKWAlMAwCTAAAKAAIKxwdMAwCTAAADAAMKQwoXHABNAAAAAA==.Grompy:BAABNQAECn8hAAMIAAoK8A9EpQA3AgAIAAoK8A9EpQA3AgAYAAIKuAuVQwA8AAAAAA==.Gruffnstuff:BAAANQAECgUICAAAAA==.',
Gu='Gungan:BAAANQADCgUIBQAAAA==.',
Gy='Gyomei:BAAANQADCgUIBQAAAA==.Gyxx:BAAANQADCggICAAAAA==.',
['Gò']='Gòaf:BAABNQAECn8gAAIWAAgKmSSJCQAtAwAWAAgKmSSJCQAtAwAAAA==.',
Ha='Haddice:BAABNQAECn8XAAMYAAcKhQ2kFgBIAQAYAAYK+g+kFgBIAQAIAAUK6AMyaQDqAAAAAA==.Hairyarmpit:BAAANQADCgcICQAAAA==.Hairyteeth:BAAANQAECgUICAAAAA==.Halgrad:BAEANQAECggIBwAAAA==.Hammerdaddy:BAAANQADCgUICQABNQAECgUIGAAeAHYgAA==.Hantoll:BAAANQABCgQIBQAAAA==.Harriedotter:BAAANQADCgYIBQAAAA==.',
He='Heebiejeebie:BAABNQAECn8jAAIDAAoKGRdRBgBMAgADAAoKGRdRBgBMAgAAAA==.Hellaeus:BAABNQAECn8aAAIJAAgKUhWdlAD6AQAJAAgKUhWdlAD6AQAAAA==.Henne:BAEANQAECgIIBgABNQAECggIBwALAAAAAA==.Heswithme:BAAANQADCggIEAAAAA==.',
Hi='Hisokä:BAABNQAECn8sAAIRAAoKFxAsLABBAgARAAoKFxAsLABBAgAAAA==.',
Ho='Holycreambar:BAABNQAECn8kAAIJAAkKoRlSWwCGAgAJAAkKoRlSWwCGAgAAAA==.Hottrikk:BAAANQABCgYIEQAAAA==.',
Hu='Huckanimal:BAAANQAECgEIAQABNQAECgQIBgALAAAAAA==.Huntingale:BAAANQADCgYICwAAAA==.Huntinshift:BAAANQADCgcIEAAAAA==.Hurajin:BAAANQADCgYIFQAAAA==.',
Hy='Hydronir:BAABNQAECn8VAAMTAAkKABx2GABeAQATAAgKOh12GABeAQAgAAMKUxwIRgDYAAABNQAFFAcIGQAaAIAgAA==.Hygelak:BAAANQAECgUIDgAAAA==.Hypaxia:BAAANQAECgUIBwAAAA==.',
Ig='Iggysmalls:BAAANQADCgEIAQAAAA==.',
Im='Immoc:BAAANQADCggIDgAAAA==.Impresario:BAAANQAECgUICAAAAA==.',
In='Infidius:BAAANQADCggIFAAAAA==.Intodeep:BAABNQAECn8dAAIPAAkKBxiZSACTAgAPAAkKBxiZSACTAgAAAA==.',
Ja='Jagons:BAAANQAECgUIDgAAAA==.Jahfar:BAAANQAECgUIDwAAAA==.Janara:BAAANQAECgUIBQAAAA==.',
Je='Jehtadin:BAAANQAECgEIAQABNQAECgkJIwADAGEcAA==.Jehtlock:BAABNQAECn8jAAMDAAkKYRzxLADSAgADAAkKYRzxLADSAgAKAAQKohLOMQD/AAAAAA==.Jehtstab:BAAANQADCgIIAgABNQAECgkJIwADAGEcAA==.',
Ji='Jickson:BAAANQAECgIIAgAAAA==.Jimvisible:BAAANQAECgQIDgAAAA==.',
Jo='Joan:BAAANQAECgQIBgABNQAECgoKMwAIAMofAA==.Johadro:BAAANQAECgEIAQAAAA==.',
Ju='Judgejobrown:BAAANQADCgMIAwAAAA==.Judgenawt:BAAANQAECggICgAAAA==.',
Ka='Kahlanah:BAAANQAECgcIEgAAAA==.Kaiá:BAAANQADCgYIBgAAAA==.Kallum:BAAANQAECgQICQAAAA==.Kaltak:BAAANQADCggIAgAAAA==.Karn:BAABNQAECn8hAAIJAAkK+xQpiwAQAgAJAAkK+xQpiwAQAgAAAA==.Karti:BAAANQAECgQIDAAAAA==.Karzdormi:BAECNQAFFH8NAAMaAAUKuRmoDQA0AQAaAAQKvRaoDQA0AQAbAAIKDRzwCgChAAA1AAQKfy4ABBsACgq6I7ILAKwCABsACAoEI7ILAKwCABoABwpII3QJACsBACEAAgoLHaMZAKQAAAAA.Karzillidari:BAEANQAECggICAABNQAFFAUIDQAaALkZAA==.Karzsera:BAEANQADCggICAABNQAFFAUIDQAaALkZAA==.Kassicker:BAAANQAECgMIAwAAAA==.Kaydie:BAAANQABCgQIBAABNQAECgEIAQALAAAAAA==.Kaylly:BAAANQADCgYIBgABNQAECggINwAVAPcQAA==.Kayyllynt:BAABNQAECn83AAMVAAgK9xDqGwAHAQAVAAgK9xDqGwAHAQAWAAUKRw+NTgDRAAAAAA==.Kayylynnt:BAAANQADCgEIAQABNQAECggINwAVAPcQAA==.Kazmas:BAAANQAECgIIAgABNQAECgUIBwALAAAAAA==.',
Ke='Kegeraetor:BAAANQAFFAEIAQABNQAFFAQICgAeAEIaAA==.Keinthdra:BAABNQAECn8pAAMSAAoK4x3EHADfAgASAAoK4x3EHADfAgAeAAgKphUjVACkAQAAAA==.Keliste:BAAANQADCgMIAwAAAA==.Kennaea:BAAANQADCggIDgABNQAFFAMIBwAYADgZAA==.',
Kh='Khrysais:BAAANQABCgQIBAAAAA==.',
Ki='Kinuye:BAABNQAECn8bAAMiAAYKEBKrHACYAQAiAAYKEBKrHACYAQAgAAEK4wGINQEbAAAAAA==.Kishara:BAAANQADCggICAABNQAFFAQICgAPAOAQAA==.',
Kr='Kraio:BAABNQAECn8ZAAMYAAYK2hwAEQCXAQAYAAUK2hwAEQCXAQAIAAUKjgq+SwEQAQAAAA==.',
La='Lamora:BAAANQADCggICAAAAA==.Lampard:BAAANQAECgYICwAAAA==.Landarios:BAAANQADCgcIDAABNQAECgoKLgARAMcdAA==.Langtry:BAABNQAECn8YAAIIAAkK5xKRSQAoAQAIAAkK5xKRSQAoAQAAAA==.Laraj:BAABNQAECn9AAAIPAAoKPRh4BwBQAgAPAAoKPRh4BwBQAgAAAA==.Larissaqt:BAECNQAFFH8XAAMJAAUKBRPLCwCNAQAJAAUKBRPLCwCNAQACAAQKEAsYAwDHAAA1AAQKf0AAAwkACgrMISsjADcDAAkACQqvISsjADcDAAIABAqCGyUJAGgBAAAA.Latindk:BAAANQADCgYIEwAAAA==.Latinhunter:BAAANQAECgUIDgAAAA==.Latinmonk:BAAANQADCgYIEgAAAA==.Latinshamy:BAAANQAECgUIDgAAAA==.Lavande:BAAANQAECgYIDQABNQAECgoKMwAHAFceAA==.',
Le='League:BAAANQADCgUIBQAAAA==.Leara:BAAANQAECgYIEAABNQAFFAQICgAPAOAQAA==.Legomyagro:BAABNQAECn8qAAMIAAoKJR10LwAtAwAIAAoKJR10LwAtAwAYAAEKDBTfQABDAAAAAA==.Lenipi:BAAANQAECgEIAQAAAA==.Leorohan:BAAANQABCgMIAwAAAA==.Letitgo:BAAANQADCgYIBgAAAA==.Leyez:BAAANQABCgEIAQAAAA==.',
Li='Liftmytail:BAAANQADCggICAABNQAECgkJJQAWANsfAA==.Lightshootx:BAAANQAECgEIAgAAAA==.Lilbessy:BAAANQAECgYIEwAAAA==.Lizy:BAAANQADCgYIBgABNQAECgYIDwALAAAAAA==.Lizzia:BAAANQAECgIIAgAAAA==.',
Lo='Loathe:BAAANQABCggIDwAAAA==.Logrey:BAAANQAECgEIAQABNQAECgUIGAAjAM0iAA==.Lonchainyjr:BAAANQADCgIIAgAAAA==.Loneshott:BAABNQAFFH8FAAMdAAMKQg3dFwDJAAAdAAMKDgvdFwDJAAAPAAIKdwz/JwCYAAAAAA==.Longhealz:BAAANQADCggIDQAAAA==.Loup:BAAANQADCgUICAAAAA==.',
Lu='Lunabellz:BAABNQAECn8hAAIVAAcKaw3FIQDiAAAVAAcKaw3FIQDiAAAAAA==.Lunavia:BAABNQAECn8ZAAIPAAcKVxxvkgDkAQAPAAcKVxxvkgDkAQAAAA==.Lushie:BAAANQADCgQIBAAAAA==.Luvalotbear:BAABNQAECn8WAAIVAAgKNwk3UQCXAQAVAAgKNwk3UQCXAQAAAA==.Luxembourge:BAAANQADCgUIBQAAAA==.',
Ly='Lyceus:BAAANQADCgcIBwAAAA==.Lynch:BAAANQADCgUIBgAAAA==.',
Ma='Maalgus:BAABNQAECn8YAAMjAAUKzSLRAwBgAQAjAAUKzSLRAwBgAQAkAAEKnwHmfAAUAAAAAA==.Mad:BAAANQAECgUIBgAAAA==.Maery:BAAANQAECgIIAwAAAA==.Mahota:BAAANQADCgMIAwAAAA==.Maladash:BAAANQAECgcICAABNQAFFAQICAAJAB8aAA==.Manachi:BAAANQAECgYIBgAAAA==.Mananandict:BAAANQAECgIJAgAAAA==.Marfach:BAAANQAECgUIBQAAAA==.Margoul:BAABNQAECn8YAAIRAAYKHQOoawDKAAARAAYKHQOoawDKAAAAAA==.Marikk:BAAANQABCggIGwAAAA==.Markofpain:BAAANQABCggIEAAAAA==.Mayyhem:BAACNQAFFH8ZAAIaAAcKgCA9AwBkAgAaAAcKgCA9AwBkAgA1AAQKfyoAAxoACgrRI3EEAGkDABoACgrRI3EEAGkDABsABAqdFxsqANgAAAAA.',
Mc='Mcallister:BAAANQAECgYIDwAAAA==.Mcjudgin:BAAANQADCgMIAgABNQAECgoKLAAeALklAA==.Mcsquid:BAAANQADCgUIBQAAAA==.',
Me='Meatbubble:BAAANQAECgcIDQAAAA==.Mechee:BAAANQADCgYIEwAAAA==.Melonballer:BAAANQADCgUIBQAAAA==.Mercý:BAAANQADCgcIEwAAAA==.Mesahella:BAAANQAECgMIAwABNQAECgQIDwALAAAAAA==.Metch:BAAANQAECgUICwAAAA==.',
Mi='Milkncookiee:BAAANQABCgUIBwAAAA==.Mimiker:BAACNQAFFH8GAAIbAAMK2Ar6CQDDAAAbAAMK2Ar6CQDDAAA1AAQKfzIAAxsACQq3IbYFADUDABsACQq3IbYFADUDABoAAgqlAb1LAEcAAAAA.Mimilock:BAAANQAECgUICAABNQAFFAMIBgAbANgKAA==.Minime:BAACNQAFFH8IAAIdAAUKHhcKCwCPAQAdAAUKHhcKCwCPAQA1AAQKfyUAAw8ACgrMH6QUAEsDAA8ACQr+IqQUAEsDAB0ACQpYF+seAFkCAAE1AAUUBwgoAA8AxB8A.Miniobi:BAAANQADCgYIFAAAAA==.Mirabella:BAAANQADCgcIBwAAAA==.Mistikeye:BAAANQAECgEIAQAAAA==.Mizahella:BAAANQAECgQIDwAAAA==.',
Mo='Mobo:BAAANQAECgUICAAAAA==.Mofassa:BAAANQADCgEIAQAAAA==.Mojoso:BAAANQAECgUICwAAAA==.Mokei:BAAANQADCggIDwAAAA==.Mokushi:BAAANQAECgYIBQAAAA==.Mondragore:BAABNQAECn8eAAMlAAgKQxU0BgCJAQAlAAgKQxU0BgCJAQAjAAIK9QgYLABeAAAAAA==.Moonsilver:BAAANQAECggIBAAAAA==.Moriko:BAABNQAECn8oAAIPAAoKHhUNUwB3AgAPAAoKHhUNUwB3AgAAAA==.Mourn:BAACNQAFFH8KAAIeAAQKQhrgBgDmAAAeAAQKQhrgBgDmAAA1AAQKfzYAAh4ACgrpIcYMAEwDAB4ACgrpIcYMAEwDAAAA.',
Mu='Muertomarrow:BAAANQAECgUIDwAAAA==.Mulroth:BAAANQADCggIFAAAAA==.Mustardseed:BAABNQAECn8oAAIDAAkKMA7RcAANAgADAAkKMA7RcAANAgAAAA==.',
Na='Naeblis:BAAANQADCgIIAgABNQAECgQIBgALAAAAAA==.Naliannagoat:BAAANQAECgQIDgAAAA==.Narekstwin:BAAANQADCgYIEAABNQAECgQIBgALAAAAAA==.Narradori:BAAANQAECggIDQAAAA==.Nasrith:BAABNQAECn8jAAIJAAkKABadcABOAgAJAAkKABadcABOAgAAAA==.Nastro:BAAANQAECgMIBAAAAA==.Naughtica:BAABNQAECn8XAAMNAAYK2xOmkwBbAQANAAYK2xOmkwBbAQAOAAMKWxDEIACFAAAAAA==.Navellint:BAABNQAECn8UAAMTAAcKmxBf5ADOAAATAAUKAgRf5ADOAAAgAAQK6wJldABqAAAAAA==.Nawticlaws:BAAANQAECggICwAAAA==.Nawtifox:BAAANQAECgcIEQAAAA==.Nawtilock:BAAANQAECgUIBQAAAA==.Nawtishot:BAACNQAFFH8FAAIPAAMKCBixBQAEAQAPAAMKCBixBQAEAQA1AAQKfygAAg8ACgpHHLcoAPUCAA8ACgpHHLcoAPUCAAAA.',
Ne='Neeb:BAAANQADCgYIBgAAAA==.Nekk:BAABNQAECn8gAAQXAAoK0RYzEQATAgAXAAgKehszEQATAgAMAAQKtwhRegCpAAAmAAEKvA5GMAA/AAAAAA==.',
Ni='Niraleth:BAABNQAECn8cAAMhAAoKEAsQAwApAQAhAAoKEAsQAwApAQAbAAQKrAi4LQCyAAAAAA==.Nitebrite:BAAANQAECgUIBwAAAA==.',
No='Noctolupus:BAAANQADCgEIAQAAAA==.Noimia:BAAANQAECgYIEAABNQAECggIFgAVADcJAA==.Normanosborn:BAAANQADCgIIAgAAAA==.Notfali:BAACNQAFFH8KAAIJAAQKpxkjBQALAQAJAAQKpxkjBQALAQA1AAQKfzUAAgkACgriIfYdAEsDAAkACgriIfYdAEsDAAAA.',
['Nï']='Nïssan:BAAANQAECgQICAAAAA==.',
Ob='Obits:BAAANQAECgIIAgAAAA==.Obscûr:BAAANQAECgUICAAAAA==.',
Od='Oden:BAAANQAECgUIDAAAAA==.',
Ok='Oksanabaiul:BAAANQAECgIIAwABNQAECgoKKAADAJ0gAA==.',
Ol='Oleyander:BAAANQAECgQIDAAAAA==.Olskimonk:BAAANQADCgYIBgABNQAECgQIBAALAAAAAA==.',
Om='Omgitsashami:BAABNQAECn8cAAIgAAgK/RSgJwBEAQAgAAgK/RSgJwBEAQAAAA==.',
Op='Oprawinfury:BAAANQAECgEIAQAAAA==.',
Or='Orcanist:BAABNQAECn8bAAIQAAcKLAx8XgAsAQAQAAcKLAx8XgAsAQAAAA==.Oronarcane:BAAANQADCgcIEQAAAA==.',
Os='Osanyin:BAABNQAECn8ZAAIWAAgKBRfIEwAlAQAWAAgKBRfIEwAlAQAAAA==.',
Pa='Pacoesfu:BAAANQAECggICAAAAA==.Padray:BAACNQAFFH8LAAIOAAQKRg/HBADiAAAOAAQKRg/HBADiAAA1AAQKf0YAAg4ACgodHKwBAGMCAA4ACgodHKwBAGMCAAAA.Pamarolyn:BAAANQADCgYICQAAAA==.Panhia:BAAANQADCgcIEAAAAA==.',
Pe='Pecoes:BAAANQADCgIIAgAAAA==.Pen:BAABNQAECn8mAAIVAAkKSQyKSADIAQAVAAkKSQyKSADIAQAAAA==.Pepperbottom:BAABNQAECn8pAAMDAAoK+g80ZgAoAgADAAoKAg80ZgAoAgAKAAMK/A+sCgB1AAAAAA==.Perforation:BAABNQAECn82AAMPAAkKCiUADQB3AwAPAAkKCiUADQB3AwAdAAEKyRwyLQBcAAABNQAECgoKLgAgAIEiAA==.',
Pf='Pfft:BAAANQAECgUICQABNQAECgkJMQASALQcAA==.',
Ph='Phaedril:BAAANQADCggICAAAAA==.Phaided:BAAANQABCggIFAAAAA==.Phoebere:BAAANQAECgUIDwAAAA==.Phungi:BAAANQAECgcIDgAAAA==.',
Pi='Pineapples:BAAANQAECgEIAQABNQAECgUIBwALAAAAAA==.Pinkleia:BAAANQAECgIIAgAAAA==.Pinocclio:BAABNQAECn8WAAIMAAYKfRUfSwAJAQAMAAYKfRUfSwAJAQAAAA==.',
Po='Pocketwizard:BAAANQADCgYIBgAAAA==.Pomelo:BAAANQAECgUIBwAAAA==.Popeums:BAABNQAECn8ZAAINAAcKhwQAuADwAAANAAcKhwQAuADwAAAAAA==.Poppyqtpi:BAAANQAECgUIDgAAAA==.Poyoh:BAABNQAECn8iAAIWAAkKoR2+DgDnAgAWAAkKoR2+DgDnAgAAAA==.',
Pr='Pravoce:BAAANQAECgMIAwAAAA==.Prescamacho:BAAANQAECgEIAgAAAA==.Prolific:BAEANQAECgYIBgABNQAECgcIEQALAAAAAA==.Prolifichds:BAEANQAECgIIBAABNQAECgcIEQALAAAAAA==.Propane:BAAANQAECgUIBwABNQAECgoKPAANAOUdAA==.',
Pu='Purification:BAABNQAECn8kAAIZAAoKKRyMDQDzAQAZAAoKKRyMDQDzAQABNQAECgoKLgAgAIEiAA==.',
['Pí']='Pínt:BAAANQAECgIIBAAAAA==.',
Ra='Radjason:BAAANQADCggIGQAAAA==.Raeagald:BAAANQADCggIDgABNQAFFAQICgAeAEIaAA==.Raelyni:BAABNQAECn8kAAINAAkKsxJDVgAgAgANAAkKsxJDVgAgAgAAAA==.Rajnagaran:BAAANQAECggIEAAAAA==.Rakion:BAAANQAECggICgAAAA==.Rakkah:BAABNQAECn8XAAIPAAcKaBssjwDrAQAPAAcKaBssjwDrAQAAAA==.Rakkuh:BAAANQADCgYIDgABNQAECgcIFwAPAGgbAA==.Raveniss:BAAANQAECgYICwAAAA==.Rawrie:BAAANQAECgcIDQAAAA==.Raygun:BAAANQADCggIDgABNQAECgYIDwALAAAAAA==.Rayzorevoker:BAAANQADCggJDQAAAA==.Rayzorlock:BAAANQAECgYICQAAAA==.',
Re='Reconetta:BAAANQAECgQIBAAAAA==.Redhilda:BAAANQAECgUIBgAAAA==.Regal:BAAANQADCgcIBwAAAA==.Relyk:BAAANQADCgEIAQAAAA==.',
Rh='Rhymu:BAAANQADCgUIBQAAAA==.',
Ri='Riallis:BAAANQAECggIDwABNQAECgoKOgANALgdAA==.',
Ro='Rogersoner:BAAANQAECgQIBgAAAA==.Rotation:BAABNQAECn8bAAMfAAYK2hVkFQBWAQAfAAYK2hVkFQBWAQARAAUKsgZ5ZwDbAAAAAA==.Rotblade:BAABNQAECn8nAAMGAAgKwRi7BgBbAgAGAAgKwRi7BgBbAgAEAAEKAADvpwAsAAAAAA==.Rottontomato:BAAANQADCgQJBAAAAA==.',
Ru='Rudewenn:BAAANQADCgcIBwAAAA==.Runandhide:BAAANQADCgMJAwAAAA==.Ruukia:BAAANQADCgEIAQAAAA==.',
Ry='Ryanthomas:BAAANQADCgYICwAAAA==.',
Sa='Sammabamma:BAABNQAECn8xAAISAAkKtBwMHQDeAgASAAkKtBwMHQDeAgAAAA==.Sapheer:BAAANQADCgQIBgAAAA==.Saralisa:BAAANQADCgUIBQAAAA==.Sarutobii:BAAANQAECgUIDAAAAA==.Sathenoth:BAAANQADCgcIEwAAAA==.Sañtoro:BAAANQAECgYICgAAAA==.',
Sc='Scy:BAAANQAECgYIEQAAAA==.',
Se='Selos:BAAANQAECgMIBgAAAA==.Seraphae:BAAANQAECgYIBgAAAA==.Serth:BAAANQAECgYIBgAAAA==.Sertraline:BAAANQAECgEIAgABNQAECgoKMwAHAFceAA==.',
Sh='Shadowfarts:BAAANQADCgUIBwAAAA==.Shadowmorn:BAABNQAECn8ZAAITAAkKQwWQkQB4AQATAAkKQwWQkQB4AQAAAA==.Shalako:BAAANQADCgcICwAAAA==.Shambali:BAABNQAECn8mAAMWAAoKFRjLFQCXAgAWAAoKFRjLFQCXAgAVAAEKAABDvgAjAAAAAA==.Shamidozz:BAAANQADCgYIBgABNQAECgoKLAAZAPIZAA==.Shandro:BAABNQAECn8jAAIYAAkK4gg5DwC2AQAYAAkK4gg5DwC2AQAAAA==.Shaniallon:BAABNQAECn8UAAIPAAkK7Q4nYwBPAgAPAAkK7Q4nYwBPAgAAAA==.Sharana:BAAANQADCggICAAAAA==.Shaunï:BAABNQAECn8ZAAIPAAcKRCSqKgDuAgAPAAcKRCSqKgDuAgAAAA==.Shocknawe:BAAANQAECgUICQAAAA==.Showong:BAABNQAECn8hAAMgAAgKkBTFYgDlAQAgAAgKkBTFYgDlAQATAAEKAAB0SAEqAAAAAA==.',
Si='Silentbolts:BAABNQAECn8xAAIIAAkK3xumewCHAgAIAAkK3xumewCHAgABNQAFFAMIBQAVANsKAA==.Silentchill:BAACNQAFFH8FAAIVAAMK2wrxGgDJAAAVAAMK2wrxGgDJAAA1AAQKfzMAAhUACgonIE0OAFgDABUACgonIE0OAFgDAAAA.Silentspirit:BAABNQAECn8WAAMTAAkKTg6qZwDpAQATAAkKTg6qZwDpAQAgAAIKYA7oCwFQAAABNQAFFAMIBQAVANsKAA==.Sinomen:BAAANQAECggIEQABNQAFFAEIAQALAAAAAA==.',
Sk='Skyblue:BAAANQAECgQJBgAAAA==.',
Sm='Smokebull:BAAANQAECgEIAgAAAA==.',
Sn='Snowcake:BAAANQAECgEIAQAAAA==.Snowdayz:BAAANQABCgMIBQAAAA==.',
So='Sonarak:BAABNQAECn8sAAIeAAoKuSWJAAD2AwAeAAoKuSWJAAD2AwAAAA==.Sornafayne:BAAANQAECgEIAQAAAA==.Sorrengail:BAABNQAECn8XAAIgAAUKMyMPFwCeAQAgAAUKMyMPFwCeAQAAAA==.',
Sp='Sparklebilly:BAAANQAECgIIAgAAAA==.Spy:BAAANQAECgYIBgAAAA==.',
St='Stampa:BAAANQAECgYICAAAAA==.Starcloud:BAAANQAECgcIDwAAAA==.Starrie:BAABNQAECn8ZAAMgAAcKkxmPFgCiAQAgAAcKkxmPFgCiAQATAAIK4wPGIAFPAAAAAA==.Steelhoof:BAABNQAECn9BAAIdAAoKrQS1CgA+AQAdAAoKrQS1CgA+AQAAAA==.Steil:BAAANQAECgIIAQAAAA==.Steponmyface:BAAANQAECgQIDgABNQAECgkJJQAWANsfAA==.Stewie:BAAANQAECgEIAQAAAA==.Stonesoul:BAAANQADCgcIBwAAAA==.Stormfury:BAEANQAECgQIAwABNQAECgcIEQALAAAAAA==.Strucker:BAAANQADCgUIBgABNQAECgkJIwAjABEfAA==.Struckerzz:BAAANQAECgUICAAAAA==.Struckophile:BAAANQADCgcIDQAAAA==.Struckrucker:BAABNQAECn8jAAIjAAkKER88BQARAwAjAAkKER88BQARAwAAAA==.',
Su='Succubussi:BAABNQAECn8rAAMDAAkKFBb5VQBUAgADAAkKFBb5VQBUAgAKAAIKew1KXgBpAAAAAA==.Sushie:BAABNQAECn8WAAMNAAkKlBNaTwA2AgANAAkKlBNaTwA2AgAOAAEKAACuhgAjAAABNQAFFAcIFAAZALURAA==.',
Sw='Swipe:BAAANQADCggIDwAAAA==.',
Sy='Synge:BAAANQABCggIGQAAAA==.Synn:BAAANQADCgQIBAABNQAECgEIAQALAAAAAA==.Syrena:BAAANQABCgEJAQAAAA==.Syvina:BAAANQAECgQICAAAAA==.',
Ta='Tabby:BAAANQAECgMIAwAAAA==.Taconight:BAABNQAECn8WAAINAAUKRxAxSwDmAAANAAUKRxAxSwDmAAAAAA==.Tahtanka:BAAANQABCggICAAAAA==.Tallynz:BAAANQAECggIEwAAAA==.Tamaru:BAAANQABCgMIBAAAAA==.Tankornot:BAAANQAECgMIBQAAAA==.Tarasque:BAAANQADCgEIAQABNQAECgEIAQALAAAAAA==.Tarnished:BAABNQAECn8bAAIYAAkKdQSuFwA9AQAYAAkKdQSuFwA9AQAAAA==.Tasil:BAAANQADCgUIBQABNQAECgUICgALAAAAAA==.Tateer:BAABNQAECn8YAAIPAAcKsSUkKwDtAgAPAAcKsSUkKwDtAgAAAA==.Tateerfel:BAAANQADCggICgABNQAECgcIGAAPALElAA==.Tateernugget:BAAANQADCgUICgABNQAECgcIGAAPALElAA==.Tater:BAAANQADCggIBwAAAA==.Tawneestone:BAABNQAECn8sAAIXAAoKAh02BQAlAwAXAAoKAh02BQAlAwAAAA==.',
Te='Teedizzle:BAAANQADCgcIDQAAAA==.Teek:BAAANQAECggICgAAAA==.Telandaraa:BAABNQAECn86AAMNAAoKuB2gIwDfAgANAAoKuB2gIwDfAgAOAAcKoQ7fMwCEAQAAAA==.Telrae:BAAANQAECgMIBAAAAA==.Tempestus:BAAANQABCgYIBwAAAA==.Teuton:BAAANQABCgMIAwAAAA==.',
Th='Theldara:BAACNQAFFH8KAAIPAAQK4BDjBwDqAAAPAAQK4BDjBwDqAAA1AAQKfy8AAg8ACgpDHlIkAAYDAA8ACgpDHlIkAAYDAAAA.Themock:BAAANQAECgUICAAAAA==.Theresjohnny:BAAANQADCgcIEwAAAA==.Thesentinel:BAAANQAECgUIDQABNQAECgkJMQASALQcAA==.Theshift:BAACNQAFFH8FAAINAAMKxRMpDQDmAAANAAMKxRMpDQDmAAA1AAQKfzEAAw0ACgq0HT0eAPgCAA0ACgq0HT0eAPgCABwABApRD5oXALgAAAAA.Thisisjustin:BAAANQAECgIIAgAAAA==.Thoreen:BAAANQAECgMIBAAAAA==.Thrish:BAACNQAFFH8JAAIPAAQKgRzGBwDrAAAPAAQKgRzGBwDrAAA1AAQKfzUAAg8ACgq9IAMmAP8CAA8ACgq9IAMmAP8CAAAA.Thuggies:BAAANQAECgYIBgAAAA==.Thunderfist:BAAANQADCggIEAABNQAFFAQICAAJAB8aAA==.',
Ti='Timothy:BAAANQADCggICAABNQAECgEIAQALAAAAAA==.',
To='Totemiclord:BAABNQAECn85AAITAAoKRxIjEgCFAQATAAoKRxIjEgCFAQAAAA==.Totumdaddy:BAAANQADCgYIBgABNQAECgUIGAAeAHYgAA==.',
Ts='Tsavo:BAAANQAECgEIAQAAAA==.',
Tu='Tukarm:BAAANQADCgUIDQAAAA==.',
Tw='Twixbolt:BAAANQAECgUIDgABNQAECgkJJAAJAKEZAA==.',
Ty='Tyriais:BAABNQAECn8gAAImAAcKtQu8CQDmAAAmAAcKtQu8CQDmAAAAAA==.',
Ub='Ubdead:BAAANQADCgQIBAAAAA==.Ubpriest:BAABNQAECn8aAAINAAYKjBYCIQB/AQANAAYKjBYCIQB/AQAAAA==.',
Ut='Uthrob:BAAANQADCgEIAQAAAA==.',
Va='Valvaa:BAAANQABCgEIAQAAAA==.Vampyre:BAAANQADCgIIAgAAAA==.Vayne:BAACNQAFFH8LAAIMAAQK8AuHDADLAAAMAAQK8AuHDADLAAA1AAQKfzYAAgwACgr9HWYvAAEDAAwACgr9HWYvAAEDAAAA.',
Vi='Vindenna:BAABNQAECn8jAAMOAAoKHxcMIQAvAgAOAAkKHhUMIQAvAgANAAQKrxcPPwAMAQAAAA==.Vinge:BAECNQAFFH8JAAISAAQKhRD5AgDwAAASAAQKhRD5AgDwAAA1AAQKfzMAAhIACgoYIXEWAAcDABIACgoYIXEWAAcDAAAA.Violetxx:BAABNQAECn8ZAAIPAAcKRQcjyABxAQAPAAcKRQcjyABxAQAAAA==.Viral:BAAANQAECgcIBwAAAA==.Viralswine:BAAANQAECgEIAQAAAA==.',
Vl='Vladi:BAAANQAECgYICwAAAA==.',
Vo='Volgrim:BAAANQAECgcICgAAAA==.Voltaic:BAABNQAECn8uAAMgAAoKgSLYDABZAwAgAAoKgSLYDABZAwATAAEKAAAlHgFUAAAAAA==.Vorsort:BAAANQADCgUIBQAAAA==.',
Vr='Vraylaros:BAABNQAECn8sAAIgAAoKWSE9DABeAwAgAAoKWSE9DABeAwAAAA==.',
Vy='Vyrista:BAAANQAECgYIDgAAAA==.Vyrzeth:BAAANQADCgUIBgAAAA==.Vyzualize:BAAANQAECgQIBAAAAA==.',
Wa='Waferblade:BAAANQAECgYIBgAAAA==.Waknipi:BAAANQAECgQIDQAAAA==.Wartooth:BAAANQAECgUICQAAAA==.Wauwen:BAAANQADCgIIAgABNQAECgYIDwALAAAAAA==.Wavecheck:BAAANQAECgMIBAAAAA==.',
We='Weetbix:BAAANQAECgIIAwAAAA==.',
Wh='Wheresjohnny:BAABNQAECn8jAAIeAAkK1xyjJQCPAgAeAAkK1xyjJQCPAgAAAA==.Whiskeyjack:BAAANQAECgIIBAABNQAFFAcIKAAPAMQfAA==.Whiteaug:BAAANQAECgEIAQABNQAFFAcIGQAaAIAgAA==.',
Wi='Wiccked:BAABNQAECn8xAAInAAgKKxXVBgA5AgAnAAgKKxXVBgA5AgAAAA==.Wildheitt:BAABNQAECn8oAAIZAAkKnhwyKADHAgAZAAkKnhwyKADHAgAAAA==.Willsky:BAAANQADCgYIBgAAAA==.Windrange:BAAANQAECgUICAAAAA==.Wintérhoof:BAAANQAECgYIDgABNQAECgcIEQALAAAAAA==.',
Wo='Wonderpally:BAAANQAECgUIDQAAAA==.Woodscale:BAAANQAECgMIBAAAAA==.Wovenbones:BAABNQAECn84AAMSAAkKVRleKgCNAgASAAkKVRleKgCNAgAQAAgK6Q4AQQDCAQAAAA==.',
Xx='Xxthequeenbe:BAAANQADCgIIAgAAAA==.',
Ya='Yar:BAAANQADCgIIAgAAAA==.',
Ye='Yergat:BAACNQAFFH8oAAMPAAcKxB8FBAAdAgAPAAYKwSAFBAAdAgAdAAYKsBq6BQAAAgA1AAQKf0UAAx0ACgpYJKwIAEcDAB0ACgp8I6wIAEcDAA8ACAoIJmQnAPoCAAAA.',
Yu='Yuhon:BAAANQAECgMIAwAAAA==.Yupa:BAABNQAECn8bAAIXAAcKURmqEQAMAgAXAAcKURmqEQAMAgABNQAECgoKKAAPAB4VAA==.Yuzuruhanyu:BAAANQADCgYIBgABNQAECgoKKAADAJ0gAA==.',
Za='Zafira:BAAANQAECgYIDAAAAA==.Zainea:BAACNQAFFH8JAAINAAUKYA3UIADaAAANAAUKYA3UIADaAAA1AAQKfzsAAg0ACgo7HQAkAN0CAA0ACgo7HQAkAN0CAAE1AAQKBggMAAsAAAAA.Zarena:BAAANQAECgEIAQAAAA==.Zattani:BAAANQADCgMIBAABNQAECgUICQALAAAAAA==.',
Ze='Zelblades:BAAANQADCggIDQABNQAECgoKJQAEAGYYAA==.Zelrex:BAABNQAECn8lAAMEAAoKZhhNFgDKAgAEAAoKZhhNFgDKAgAFAAUK6AVLOgDlAAAAAA==.Zephyrà:BAAANQADCgYIBgAAAA==.Zerazer:BAAANQAECgcIDQAAAA==.',
Zh='Zhuntyr:BAAANQAECgUIDAAAAA==.',
Zi='Zierosouls:BAAANQADCgcIDAAAAA==.Ziggedion:BAABNQAECn8jAAIhAAkKoBJ1BwA0AgAhAAkKoBJ1BwA0AgAAAA==.Zindar:BAABNQAECn8aAAMhAAgKQhM9DACVAQAhAAcKvBQ9DACVAQAaAAcK3gVnOwC+AAAAAA==.Zinnfandel:BAAANQABCgQIBAAAAA==.Ziyan:BAAANQAECgIIAgABNQAECggICgALAAAAAA==.',
Zo='Zolpidem:BAAANQADCgYIBwABNQAECgoKMwAHAFceAA==.',
Zu='Zulljyn:BAAANQADCgQIBAAAAA==.',
['Zò']='Zòmi:BAACNQAFFH8JAAITAAMKDyG3FQAfAQATAAMKDyG3FQAfAQA1AAQKfzAAAhMACgolIcoKAJADABMACgolIcoKAJADAAAA.',
['Ár']='Áres:BAABNQAECn8iAAIQAAkKwRLeMwAOAgAQAAkKwRLeMwAOAgAAAA==.',
['Çò']='Çòñstàñtîñè:BAAANQABCgcICwAAAA==.',
['Ït']='Ïtzpäpälötl:BAAANQAECgYIEQAAAA==.',
['Ðr']='Ðrstrange:BAAANQAECgIIAwAAAA==.',
['Ñi']='Ñightwolf:BAAANQADCgQIBAABNQAECgYIBQALAAAAAA==.',
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
