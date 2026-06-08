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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Protection','DeathKnight-Unholy','Mage-Frost','Unknown-Unknown','Shaman-Elemental','Priest-Holy','Druid-Restoration','Monk-Mistweaver','Mage-Arcane','Druid-Balance','Druid-Guardian','Druid-Feral','Monk-Brewmaster','Monk-Windwalker','Warrior-Fury','Evoker-Preservation','Evoker-Augmentation','Paladin-Holy','Rogue-Subtlety','Priest-Shadow','DemonHunter-Havoc','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','DemonHunter-Devourer','Rogue-Assassination','Rogue-Outlaw','Shaman-Restoration','Shaman-Enhancement','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Vengeance','DeathKnight-Blood','Warlock-Destruction','Warrior-Arms','Evoker-Devastation','DeathKnight-Frost','Priest-Discipline','Mage-Fire',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=46,date='2026-06-06',data={Ad='Adrador:BAABLgAECn8sAAMBAAkJeSTSAQAeAwABAAkJeSTSAQAeAwACAAIJZxTtEwFvAAAAAA==.Adrenaline:BAACLgAFFH8cAAIDAAUJQSE+CgBxAQADAAUJQSE+CgBxAQAuAAQKfzkAAgMACQm8JKoCABADAAMACQm8JKoCABADAAAA.',
Ae='Aelik:BAACLgAFFH8MAAIEAAMJhRUfhADtAAAEAAMJhRUfhADtAAAuAAQKfykAAgQACAnwHT41ACICAAQACAnwHT41ACICAAAA.Aeolian:BAAALgADCgYJCQAAAA==.',
Ah='Ahkimbo:BAAALgADCgUJBQAAAA==.',
Ai='Airolanah:BAAALgAECgUJBQAAAA==.',
Al='Alayssa:BAABLgAECn8sAAIFAAkJXSBwGgC1AgAFAAkJXSBwGgC1AgAAAA==.Alda:BAAALgADCgkJEQAAAA==.Allarius:BAAALgAECgEJAQAAAA==.Allioops:BAAALgADCgUJBQABLgAECgMJBAAGAAAAAA==.Alnima:BAACLgAFFH8GAAIHAAMJ/QHvOgCKAAAHAAMJ/QHvOgCKAAAuAAQKfxkAAgcACAnOCLk5AGgBAAcACAnOCLk5AGgBAAAA.',
Am='Amilee:BAAALgAECgUJDwAAAA==.Amishhunter:BAAALgADCgEJAQAAAA==.Amoondai:BAACLgAFFH8PAAIIAAMJkyHtEwAQAQAIAAMJkyHtEwAQAQAuAAQKfy8AAggACQmjIsMCAGgDAAgACQmjIsMCAGgDAAAA.Amoondrin:BAABLgAECn8zAAIJAAkJLwncSgBZAQAJAAkJLwncSgBZAQAAAA==.Amplifier:BAAALgADCgUJBQAAAA==.',
An='Analiya:BAAALgADCgIJAgAAAA==.Antichurch:BAAALgADCgEJAQAAAA==.Antisnow:BAAALgAECgIJBQABLgAECgcJCgAGAAAAAA==.Antregon:BAAALgADCgQJBwAAAA==.',
Ar='Araviin:BAABLgAFFH8FAAIFAAIJKAU2pQB+AAAFAAIJKAU2pQB+AAAAAA==.Arazen:BAAALgAECgIJAwAAAA==.Arcillias:BAAALgADCgYJCAABLgAECgYJBgAGAAAAAA==.Arkride:BAAALgAECgEJAQAAAA==.Arlean:BAAALgAECgIJAgAAAA==.Arnadaz:BAAALgADCgEJAQABLgAFFAQJCAAKAIAVAA==.Arrogance:BAAALgADCgcJBwABLgAECggJCQAGAAAAAA==.Arthia:BAAALgAECgQJEAAAAA==.Arvidpally:BAAALgADCgkJFQAAAA==.',
As='Ashmehameha:BAAALgADCgQJAgABLgAFFAMJBQAEAK4MAA==.Asinn:BAAALgAECgEJAQAAAA==.Asoosimov:BAAALgADCgEJAQAAAA==.',
At='Atredes:BAAALgAFFAIJAwAAAA==.Attima:BAABLgAECn9BAAILAAkJWBF8AwDZAQALAAkJWBF8AwDZAQAAAA==.',
Au='Aubriana:BAAALgADCgQJBAAAAA==.Aurøra:BAAALgADCgMJAwAAAA==.Auspex:BAABLgAECn8rAAMMAAkJxwlLMwA+AQAMAAkJ6QdLMwA+AQANAAkJMAjxKwDtAAAAAA==.',
Av='Avaryn:BAACLgAFFH8XAAIJAAUJTBFcHwBPAQAJAAUJTBFcHwBPAQAuAAQKfzgAAgkACQmZIagIACYDAAkACQmZIagIACYDAAAA.',
Ax='Aximlii:BAAALgAECgEJAQAAAA==.',
Az='Azron:BAAALgAECgYJBwABLgAECggJDgAGAAAAAA==.',
Ba='Babavoss:BAAALgAECgkJAQAAAA==.Badarack:BAAALgAECgcJEwABLgAECgkJHgANAPMjAA==.Badaracka:BAABLgAECn8eAAMNAAkJ8yOCAQA3AwANAAkJ8yOCAQA3AwAOAAQJ0hDZKwCkAAAAAA==.Badarackie:BAABLgAECn9AAAMPAAkJEB+dCQDvAgAPAAgJ0iGdCQDvAgAQAAkJDhXiFwDnAQABLgAECgkJHgANAPMjAA==.Badash:BAABLgAECn8rAAMDAAgJBht4DwDjAQADAAgJBht4DwDjAQARAAEJMQSurQAvAAABLgAFFAMJBQAEAK4MAA==.Bahamuth:BAABLgAECn9DAAICAAkJIB1HIAB8AgACAAkJIB1HIAB8AgAAAA==.Bakshi:BAAALgAECgEJBAAAAA==.Banký:BAAALgAECgEJAQAAAA==.Barbattos:BAACLgAFFH8XAAISAAUJjRQKEgBbAQASAAUJjRQKEgBbAQAuAAQKfzYAAxIACQkOJJECADkDABIACQkOJJECADkDABMAAQnkJCF4AGEAAAAA.Barnabas:BAAALgADCgYJBgABLgAECgYJBgAGAAAAAA==.Barragon:BAABLgAECn8VAAIUAAcJ5g/YNABzAQAUAAcJ5g/YNABzAQAAAA==.',
Be='Beans:BAAALgAECgQJBAAAAA==.Bearymanalow:BAAALgAECgMJBAAAAA==.Belfore:BAAALgAECgEJAQABLgAECgkJJQAVANIUAA==.Bethollbrew:BAAALgAECgYJDwAAAA==.Bexley:BAABLgAECn8tAAIBAAkJChpXCABFAgABAAkJChpXCABFAgAAAA==.',
Bi='Biggerbunny:BAACLgAFFH8HAAIWAAMJ6AcqJQC3AAAWAAMJ6AcqJQC3AAAuAAQKfzAAAhYACAmEFVggALsBABYACAmEFVggALsBAAAA.Binkter:BAAALgAECgIJBQABLgAECgIJAgAGAAAAAA==.',
Bl='Blackjax:BAAALgADCgEJAQAAAA==.Blacklok:BAAALgAECgUJEQABLgAECgkJNAAXAEElAA==.Blanne:BAAALgAECgEJAQAAAA==.Blargle:BAABLgAECn8tAAIYAAgJKQ/2VQCVAQAYAAgJKQ/2VQCVAQAAAA==.Blessedcross:BAAALgAECgMJAwAAAA==.Bleubahlz:BAAALgADCgcJBwABLgAECgMJAwAGAAAAAA==.Blinx:BAAALgAECgQJBAABLgAECggJDgAGAAAAAA==.Bloodrake:BAABLgAECn87AAIYAAkJHB6mDQDRAgAYAAkJHB6mDQDRAgAAAA==.Bloodreyne:BAAALgADCgEJAgAAAA==.Bloodseekr:BAAALgADCgQJBQAAAA==.Blueray:BAAALgAECgYJCAAAAA==.',
Bo='Boahan:BAAALgAECgMJBQABLgAECgUJCAAGAAAAAA==.Boggart:BAAALgAECgEJAQABLgAECgUJCAAGAAAAAA==.Bohein:BAAALgADCgEJAQAAAA==.Bolus:BAAALgAECgQJCAAAAA==.Botany:BAAALgAECgcJBwAAAA==.Bownafiedba:BAAALgADCgUJBQAAAA==.',
Br='Braneour:BAABLgAECn8zAAMUAAkJwBpnCwDMAgAUAAkJwBpnCwDMAgACAAMJVBGxHAGGAAAAAA==.Brassballz:BAAALgAECgkJCQAAAA==.Browel:BAABLgAECn8aAAMZAAcJWBj4CAC3AQAZAAYJ3Rj4CAC3AQAaAAYJYQ4WmQAGAQAAAA==.Bruen:BAAALgAECgYJBwAAAA==.Bryci:BAAALgAECgcJEAAAAA==.',
Bu='Bubbloseven:BAAALgAECgcJEgAAAA==.Budank:BAAALgADCgMJAwAAAA==.Bumm:BAABLgAECn8ZAAICAAYJzwiR1wDbAAACAAYJzwiR1wDbAAAAAA==.Bustybubbles:BAAALgADCgYJBgAAAA==.',
Bz='Bzspy:BAABLgAFFH8LAAIRAAMJzwxGNQDHAAARAAMJzwxGNQDHAAAAAA==.',
Ca='Caalin:BAAALgAECgEJAgAAAA==.Cabooselul:BAAALgAECgQJCwAAAA==.Calibre:BAABLgAECn8eAAIbAAcJohV5ZABSAQAbAAcJohV5ZABSAQAAAA==.Calyptus:BAABLgAECn8fAAIaAAYJhAqLpwDtAAAaAAYJhAqLpwDtAAAAAA==.Caprious:BAACLgAFFH8WAAIEAAUJwxkiRABaAQAEAAUJwxkiRABaAQAuAAQKfzYAAgQACQnjJB8JACEDAAQACQnjJB8JACEDAAAA.Capylaura:BAABLgAECn8ZAAIYAAYJhwiymQD/AAAYAAYJhwiymQD/AAAAAA==.Caratine:BAABLgAECn8aAAIbAAgJkAowegAfAQAbAAgJkAowegAfAQAAAA==.Cassandrar:BAABLgAECn8yAAQcAAkJGSQIAQA5AwAcAAgJMiQIAQA5AwAVAAYJtiBiHQCdAQAdAAEJphQzIQA5AAAAAA==.Cassandraw:BAAALgAECgYJBgABLgAECgkJMgAcABkkAA==.Cat:BAAALgADCgUJBQAAAA==.Cattlelac:BAAALgADCgUJCAAAAA==.Caymus:BAABLgAECn8jAAIJAAgJuAjCWQAhAQAJAAgJuAjCWQAhAQAAAA==.',
Ce='Celìa:BAABLgAECn8nAAIYAAkJdQhHYAB6AQAYAAkJdQhHYAB6AQAAAA==.Cess:BAAALgAECgEJAgAAAA==.',
Ch='Chaoticone:BAAALgADCgYJBgAAAA==.Chema:BAABLgAFFH8IAAIKAAQJgBXMJgAKAQAKAAQJgBXMJgAKAQAAAA==.Chestylarue:BAAALgAECgEJAQABLgAECggJEgAGAAAAAA==.Chfgaribaldi:BAAALgADCggJDgAAAA==.Chills:BAAALgAECgcJEQAAAA==.Chillymage:BAAALgADCgYJBgAAAA==.Chosen:BAABLgAECn8YAAICAAYJRBdtYgC+AQACAAYJRBdtYgC+AQABLgAFFAUJFwAEAPsgAA==.Chpchop:BAAALgADCgIJAgAAAA==.Christy:BAAALgADCgkJEQAAAA==.Chugg:BAABLgAECn8fAAIeAAkJwgjjVQBOAQAeAAkJwgjjVQBOAQAAAA==.',
Ci='Ciaphus:BAABLgAECn8nAAICAAkJ0hQ6QgD1AQACAAkJ0hQ6QgD1AQAAAA==.Cinnamonster:BAAALgAECgcJDgAAAA==.',
Co='Coffeedemon:BAAALgADCgEJAQAAAA==.Coldslappins:BAAALgAECggJCgAAAA==.Contagion:BAAALgAECgYJBQAAAA==.Convoke:BAABLgAECn8eAAIMAAcJDSArFgBeAgAMAAcJDSArFgBeAgAAAA==.Coragrr:BAAALgADCgYJBgAAAA==.',
Cr='Crazycrocey:BAAALgAECgEJAQAAAA==.Cryptonight:BAAALgAECgQJBAAAAA==.',
Cu='Cubcake:BAAALgADCggJCAAAAA==.Curtastrophe:BAABLgAECn89AAIFAAkJHx1JJQCAAgAFAAkJHx1JJQCAAgAAAA==.Curticus:BAAALgADCgQJBAAAAA==.Curtissax:BAAALgAECgIJAgAAAA==.Curtnought:BAAALgADCgIJAgAAAA==.',
['Cé']='Cérnùnnøs:BAAALgAECgEJAQAAAA==.',
Da='Daelanos:BAABLgAECn8cAAIRAAgJPBirLQCTAQARAAgJPBirLQCTAQAAAA==.Dalinar:BAAALgAECgUJCwAAAA==.Daranger:BAAALgADCgEJAQAAAA==.Darska:BAAALgADCgYJBgABLgAECggJDgAGAAAAAA==.',
De='Deadtauren:BAAALgADCgYJDwAAAA==.Deathdemon:BAAALgAECgYJDgAAAA==.Deathfue:BAAALgAECgEJAwABLgAECgcJCgAGAAAAAA==.Deathisreal:BAAALgADCgMJAwABLgAECgUJDQAGAAAAAA==.Deathoof:BAAALgAECgEJAQAAAA==.Decimated:BAACLgAFFH8XAAIEAAUJ+yBHNwB4AQAEAAUJ+yBHNwB4AQAuAAQKfyAAAgQACQkwI64WALYCAAQACQkwI64WALYCAAAA.Degeneracy:BAAALgAECgcJBwAAAA==.Demon:BAAALgAECgkJDQAAAA==.Demonilla:BAAALgAECgcJDwAAAA==.Dempkiston:BAAALgAECgYJCwAAAA==.Denable:BAABLgAECn8kAAIJAAcJSg8sTQBQAQAJAAcJSg8sTQBQAQAAAA==.Denogan:BAAALgAECggJDgAAAA==.Deservis:BAAALgAECgUJDgABLgAECgcJHgAbAKIVAA==.Destro:BAABLgAECn8pAAIaAAkJ7w/hRADHAQAaAAkJ7w/hRADHAQABLgAECgkJMwAfAOIXAA==.Dethadin:BAAALgADCgcJBwAAAA==.',
Di='Dilaudyd:BAAALgAECgMJBAAAAA==.Dirteemike:BAAALgADCgMJAwAAAA==.Disbeleaf:BAABLgAECn8VAAMJAAYJARleOACsAQAJAAYJARleOACsAQAMAAUJUSBtKwBsAQAAAA==.Discoflurry:BAAALgAECgcJDgABLgAFFAQJCgADAN8hAA==.Dizzyfist:BAAALgAECgYJCQABLgAECggJDgAGAAAAAA==.',
Do='Dogaz:BAAALgADCgkJDwAAAA==.Dogsoldier:BAAALgADCgIJAgAAAA==.Donori:BAAALgAECgQJDQAAAA==.Dorcath:BAAALgAFFAIJBAABLgAECggJHAARADwYAA==.',
Dr='Dragan:BAAALgAECgQJEQAAAA==.Dragapult:BAAALgAECggJAwAAAA==.Dragonias:BAABLgAECn8bAAIgAAgJxRWdCgC1AQAgAAgJxRWdCgC1AQAAAA==.Draino:BAAALgADCgUJBQAAAA==.Drakthorn:BAAALgAECgcJCgAAAA==.Dreselwings:BAAALgAECggJCAABLgAFFAgJHgAYAJsfAA==.Drinny:BAABLgAECn8yAAIIAAkJtwg+MAA/AQAIAAkJtwg+MAA/AQAAAA==.Drqueenisin:BAAALgAECgEJAQAAAA==.Druido:BAAALgAECgEJAQAAAA==.',
Du='Duerek:BAAALgAECgUJBgAAAA==.',
['Dè']='Dèaths:BAAALgAECgYJEAAAAA==.',
['Dí']='Dínglebery:BAAALgAECgEJAgAAAA==.',
Ea='Earthangel:BAABLgAECn8kAAIIAAcJHBeSIwCZAQAIAAcJHBeSIwCZAQAAAA==.',
Ed='Edlarel:BAAALgADCgQJBAABLgAECggJCQAGAAAAAA==.',
Ei='Eine:BAABLgAECn9DAAIYAAkJsxXkLQAaAgAYAAkJsxXkLQAaAgAAAA==.Eitherwind:BAABLgAECn8XAAQhAAYJ2h+pHgCiAQAhAAYJ2h+pHgCiAQAYAAIJchT/qwBsAAAgAAIJNxOHOAA0AAABLgAECggJDgAGAAAAAA==.Eivore:BAAALgAECgcJBwAAAA==.',
Ek='Ekoh:BAAALgAECgEJAgAAAA==.',
El='Eldergreen:BAABLgAECn8nAAIJAAgJ2ArYWQAgAQAJAAgJ2ArYWQAgAQAAAA==.Eldest:BAAALgADCgUJBQAAAA==.Elfwine:BAABLgAECn8kAAIWAAcJ2Q0NNQA6AQAWAAcJ2Q0NNQA6AQAAAA==.Elindria:BAABLgAECn80AAQXAAkJQSU2AwAbAwAXAAkJHiU2AwAbAwAiAAkJhiHqAQDtAgAbAAUJMxu6ewA0AQAAAA==.Eliora:BAAALgADCgkJCQAAAA==.Elminstir:BAAALgAECggJEwAAAA==.Elyissia:BAAALgAECgYJDAAAAA==.Elynisa:BAAALgAECgEJAQAAAA==.Elysian:BAABLgAECn84AAQKAAkJcxwFCwDXAgAKAAkJcxwFCwDXAgAQAAgJaB8ODwBNAgAPAAIJyh8NVQCqAAAAAA==.',
Em='Emogo:BAAALgADCgUJCQAAAA==.',
En='Enforcer:BAAALgADCgQJBgAAAA==.Enlightened:BAAALgAECgQJCwAAAA==.Enseral:BAAALgAECgcJEgAAAA==.',
Eo='Eotech:BAAALgAECgQJBAAAAA==.',
Er='Erendora:BAABLgAECn8gAAIJAAgJqQ69RAB0AQAJAAgJqQ69RAB0AQAAAA==.Erets:BAAALgAECgEJAQAAAA==.Eridar:BAAALgAECgYJBgAAAA==.Erizhal:BAAALgAECgUJEAAAAA==.Erodora:BAAALgADCgEJAQAAAA==.',
Es='Esabel:BAAALgAECgkJDwABLgAECgkJLAAFAF0gAA==.',
Ev='Eva:BAAALgAECgEJAgAAAA==.Eviae:BAABLgAECn8lAAIjAAcJ7grlKwDwAAAjAAcJ7grlKwDwAAAAAA==.Evillure:BAABLgAECn8lAAMEAAkJ8hNLPgABAgAEAAkJ8hNLPgABAgAjAAUJkgwpOQCkAAAAAA==.',
Fa='Falan:BAABLgAECn8oAAIeAAkJDhKvKwD9AQAeAAkJDhKvKwD9AQAAAA==.Faputa:BAAALgAECgMJAwAAAA==.Fatherjoe:BAAALgADCgYJBgAAAA==.Fayze:BAEBLgAECn8XAAMcAAcJfiPHBAAyAgAcAAcJSCPHBAAyAgAVAAIJBiGmPQDAAAABLgAFFAIJBAAGAAAAAA==.',
Fe='Felbreaker:BAAALgAECgYJEAAAAA==.Fentril:BAAALgADCgIJAgABLgAECggJDgAGAAAAAA==.Feår:BAABLgAECn8eAAMaAAkJJQwcdwBGAQAaAAgJQgocdwBGAQAkAAMJ3Q8RSwCMAAAAAA==.',
Fi='Fillianora:BAAALgAECgIJAgAAAA==.Finley:BAAALgAECgQJBQAAAA==.Fircane:BAAALgADCgQJBAAAAA==.Firiel:BAAALgADCgEJAQAAAA==.Fizzle:BAAALgADCggJCAABLgAECgkJJQAJAO0ZAA==.',
Fl='Flane:BAAALgAFFAEJAwABLgAFFAgJGgADAHwfAA==.Flem:BAAALgAECgMJBAAAAA==.Flexdruid:BAAALgAECgUJEwAAAA==.',
Fo='Foog:BAABLgAECn8VAAMRAAcJzxj5LgCMAQARAAYJoBr5LgCMAQAlAAQJ1w+CNwDbAAAAAA==.',
Fr='Fragil:BAABLgAECn84AAIVAAgJeyBmCACVAgAVAAgJeyBmCACVAgAAAA==.Frostmane:BAACLgAFFH8UAAMEAAUJ0R88MwCCAQAEAAQJ0R88MwCCAQAjAAEJAACSVAAAAAAuAAQKfzkAAwQACQlWJfcEAFEDAAQACQlWJfcEAFEDACMABwn+HMANADECAAAA.Frostynug:BAAALgADCgYJBgAAAA==.',
Fu='Fudge:BAAALgADCgYJBgAAAA==.Furbyn:BAAALgADCgIJAgAAAA==.',
Ga='Galena:BAABLgAECn8aAAIJAAgJ3wrqUQA9AQAJAAgJ3wrqUQA9AQAAAA==.Gallamier:BAAALgADCgEJAQAAAA==.Gamerinator:BAAALgADCgcJCwAAAA==.Gangreene:BAAALgADCgYJCgAAAA==.Garoanna:BAAALgAECgYJBgABLgAECgkJJAATAFIMAA==.',
Ge='Geshtal:BAAALgAECgQJCwAAAA==.Gets:BAAALgADCgIJAgAAAA==.',
Gi='Girion:BAABLgAECn8lAAIBAAcJbw4mHwAOAQABAAcJbw4mHwAOAQAAAA==.Girliepop:BAAALgAECgEJAQAAAA==.',
Gl='Glaiven:BAECLgAFFH8YAAMbAAUJTxVgOgAnAQAbAAUJTxVgOgAnAQAiAAMJuA/3DABhAAAuAAQKfy8AAyIACQmVITcEAHUCABsACQkrH6EdAKACACIACQmXHDcEAHUCAAAA.Glorfinndel:BAAALgADCgQJBAAAAA==.Glyr:BAAALgADCgUJBQAAAA==.',
Go='Gorgrin:BAAALgAECgcJEQAAAA==.Goude:BAAALgADCgIJAgAAAA==.',
Gr='Greenback:BAAALgADCgYJCwAAAA==.Greentotes:BAEBLgAECn8yAAMTAAkJ7x/uBwDTAgATAAkJ7x/uBwDTAgAmAAUJTxO0EQDiAAABLgAECgIJBAAGAAAAAA==.',
Gu='Gunter:BAAALgAECgMJAwABLgAFFAUJFwAEAPsgAA==.Gura:BAAALgADCgEJAQAAAA==.Gurnee:BAAALgADCgcJDQABLgAECggJEQAGAAAAAA==.Guthix:BAAALgAECgUJBgAAAA==.',
['Gê']='Gêm:BAABLgAECn8/AAISAAkJ8xJVDAAIAgASAAkJ8xJVDAAIAgAAAA==.',
['Gï']='Gïmlï:BAAALgADCgMJAwAAAA==.',
Ha='Haildydra:BAAALgAECgEJAQABLgAECgcJCgAGAAAAAA==.Halibell:BAAALgAECgYJDQAAAA==.Halnan:BAAALgADCgEJAQABLgAECgcJHgAbAKIVAA==.Harkanum:BAABLgAECn9GAAQmAAkJ9hn2BQDqAQAmAAgJLhj2BQDqAQASAAkJGg3BEQClAQATAAQJrxPwPgDuAAAAAA==.Harrow:BAAALgAECgMJAwAAAA==.Hartman:BAAALgAECgQJBQAAAA==.Harvester:BAAALgAECgEJAQAAAA==.Hatebreéd:BAAALgAECggJCQAAAA==.',
He='Healinturds:BAAALgAECgYJDAABLgAECgcJHgAbAKIVAA==.Hector:BAABLgAECn8eAAICAAkJfSJuIwBuAgACAAkJfSJuIwBuAgAAAA==.Heelys:BAAALgAECgYJCgAAAA==.Helloagain:BAACLgAFFH8UAAIFAAQJtRqgQwBVAQAFAAQJtRqgQwBVAQAuAAQKfyQAAgUABglqIyFdACMCAAUABglqIyFdACMCAAAA.Herryknutsak:BAAALgAECgEJAQAAAA==.Hestonater:BAAALgAECgUJBwAAAA==.Hestra:BAAALgADCgIJAgAAAA==.',
Hi='Hidethetotem:BAABLgAECn8pAAMeAAkJlRz2DADlAgAeAAkJlRz2DADlAgAHAAEJHgofpwAnAAAAAA==.Hightops:BAAALgAECggJDgAAAA==.Hikari:BAACLgAFFH8NAAICAAUJLA6BSQAMAQACAAUJLA6BSQAMAQAuAAQKfx4AAgIACQlrHOAsAHACAAIACQlrHOAsAHACAAAA.Hiown:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.',
Ho='Holeliness:BAAALgAECggJEwAAAA==.Holybackshot:BAAALgAECgQJBgAAAA==.Holydisco:BAAALgADCgcJCQAAAA==.Holyhide:BAAALgAECgEJAQAAAA==.Holyspike:BAABLgAECn8aAAIeAAgJphCYQACdAQAeAAgJphCYQACdAQAAAA==.Holytard:BAAALgADCgYJBgAAAA==.Holytaren:BAABLgAECn8UAAIUAAgJ3RuXEgBzAgAUAAgJ3RuXEgBzAgAAAA==.Holytickles:BAABLgAECn8sAAMWAAkJ4hsCEwBeAgAWAAgJ+hsCEwBeAgAIAAkJsBdPEQBLAgABLgAFFAYJGAAaAJoVAA==.Holytotem:BAAALgAECgEJAQAAAA==.Homerr:BAABLgAECn8eAAIYAAgJaREiVQCXAQAYAAgJaREiVQCXAQAAAA==.Honiahaka:BAABLgAECn9DAAIYAAkJBxClQADUAQAYAAkJBxClQADUAQAAAA==.Hottcakes:BAAALgADCgIJAgABLgAFFAYJGAAaAJoVAA==.',
Hu='Huckster:BAABLgAECn8ZAAIEAAgJhQ41dgBvAQAEAAgJhQ41dgBvAQAAAA==.Humanoidholy:BAABLgAECn8fAAMCAAgJXSQ6CQBIAwACAAgJXSQ6CQBIAwABAAEJbgXWTQAYAAABLgAFFAQJEgAXADAjAA==.Humanoidhunt:BAAALgAFFAEJAQABLgAFFAQJEgAXADAjAA==.Humanoidvoid:BAACLgAFFH8SAAMXAAQJMCO7BQCUAQAXAAQJ7SK7BQCUAQAbAAMJ9h3FTQDzAAAuAAQKf1MABBsACQkFI3YGABsDABsACQmdInYGABsDABcACAnlH5AJAIICACIACAkoCIAUAPwAAAAA.',
Hy='Hydrah:BAAALgAECgEJAQABLgAECgcJCgAGAAAAAA==.',
Ic='Icedtea:BAAALgAECgcJBAAAAA==.Icicle:BAAALgADCgIJAgAAAA==.',
Id='Idunasil:BAAALgAECgEJAQAAAA==.',
Ih='Ihatemustard:BAABLgAECn8jAAIiAAkJ6RWRBwD2AQAiAAkJ6RWRBwD2AQAAAA==.',
Il='Illethan:BAAALgADCgYJBgAAAA==.Iloveketchup:BAAALgAFFAEJAQAAAA==.',
In='Inoru:BAABLgAECn8VAAMWAAcJwg6gMwBCAQAWAAcJwg6gMwBCAQAIAAEJpwKYdgAcAAAAAA==.Insanity:BAAALgAECgUJCgAAAA==.',
Ir='Irmaline:BAABLgAECn8aAAIIAAgJkxQQHwC8AQAIAAgJkxQQHwC8AQAAAA==.',
It='Ithurtshuh:BAAALgAECgUJDQAAAA==.Itsmaam:BAAALgAECgMJBAAAAA==.Itzcannibal:BAACLgAFFH8GAAIYAAIJ6goZfgCIAAAYAAIJ6goZfgCIAAAuAAQKfy8AAxgACQk4G98nADQCABgACQk4G98nADQCACAAAgnVCux5AFoAAAAA.',
Ja='Jabbawockie:BAAALgAECgkJAgAAAA==.Jaekoby:BAAALgAECgIJAwABLgAECggJIgACAM0aAA==.Jakoby:BAAALgAECgUJBgABLgAECggJIgACAM0aAA==.Jandrisel:BAAALgAECgYJDwAAAA==.Jarhead:BAAALgAECgEJAgAAAA==.Jayzich:BAAALgADCgQJBwAAAA==.',
Je='Jeffee:BAAALgAECgIJCQAAAA==.Jequalsjosh:BAACLgAFFH8GAAIcAAMJoRyKBgD6AAAcAAMJoRyKBgD6AAAuAAQKfz0AAhwACQkhIiICALsCABwACQkhIiICALsCAAAA.Jerk:BAAALgAECgQJBAAAAA==.Jerp:BAAALgAECgIJAgAAAA==.Jesper:BAABLgAECn9GAAIeAAkJ5B9lCQASAwAeAAkJ5B9lCQASAwAAAA==.Jetz:BAAALgAECgEJAQAAAA==.Jezelle:BAACLgAFFH8RAAIaAAUJDRA/VQAPAQAaAAUJDRA/VQAPAQAuAAQKfyIAAhoACQn0Hg42ADQCABoACQn0Hg42ADQCAAAA.',
Ji='Jilara:BAABLgAECn8xAAICAAgJIQhCpwAgAQACAAgJIQhCpwAgAQAAAA==.Jimmyjim:BAABLgAECn8YAAIFAAgJFwykggBrAQAFAAgJFwykggBrAQAAAA==.Jingying:BAAALgADCgMJAwAAAA==.',
Jo='Johnny:BAAALgADCgQJBAAAAA==.',
Jp='Jpepps:BAABLgAECn8vAAMaAAkJDRNaOwDoAQAaAAkJDRNaOwDoAQAkAAMJxwjoRQCeAAAAAA==.',
Jr='Jrose:BAAALgAECgQJBAAAAA==.',
['Jæ']='Jækobÿ:BAAALgAECgIJAgABLgAECggJIgACAM0aAA==.',
Ka='Kahlanrahl:BAAALgADCgMJAwAAAA==.Kaiatra:BAABLgAECn8ZAAInAAgJzSI5BAB9AgAnAAgJzSI5BAB9AgAAAA==.Kaliguala:BAAALgAECgQJBQAAAA==.Katalaystar:BAAALgAECgIJAgABLgAECgkJJQAJAO0ZAA==.Katare:BAAALgAECgMJAwAAAA==.Kaulder:BAAALgADCgUJBQAAAA==.Kaìju:BAABLgAECn8iAAICAAgJqiHNHgCEAgACAAgJqiHNHgCEAgAAAA==.Kaîju:BAAALgAECgIJAgAAAA==.',
Ke='Kellytgt:BAABLgAECn8zAAIbAAkJpxomGgBtAgAbAAkJpxomGgBtAgAAAA==.Kev:BAAALgADCgUJBQAAAA==.',
Ki='Kilaura:BAABLgAECn8ZAAIoAAgJWRALIgCuAQAoAAgJWRALIgCuAQAAAA==.Kilmandaros:BAAALgADCgYJCwAAAA==.Kippi:BAAALgAECgQJCwAAAA==.',
Kn='Knitebrite:BAAALgAECgIJAgAAAA==.',
Ko='Korhina:BAABLgAECn9GAAIDAAkJeybrAABeAwADAAkJeybrAABeAwAAAA==.Korobas:BAAALgAECgMJAwAAAA==.Koru:BAAALgAECgQJBQABLgAECgQJBgAGAAAAAA==.Kosumi:BAAALgADCggJDQAAAA==.',
Kr='Kronic:BAAALgAECgUJCAAAAA==.',
Ku='Kuroyukihime:BAABLgAECn84AAIFAAkJ/h6aGQC6AgAFAAkJ/h6aGQC6AgAAAA==.Kuwaii:BAABLgAECn8dAAITAAcJuxjqJgCiAQATAAcJuxjqJgCiAQABLgAECggJHgAMAA0gAA==.',
Ky='Kyarina:BAAALgAECgEJAQABLgAECgkJGQAIAEMHAA==.Kylis:BAAALgAECgQJBAAAAA==.Kyna:BAABLgAECn8ZAAIIAAkJQwf6OQACAQAIAAkJQwf6OQACAQAAAA==.Kyross:BAAALgADCgIJAgAAAA==.',
['Ké']='Kéya:BAAALgAECgYJCgAAAA==.',
La='Lashela:BAABLgAECn8WAAIYAAgJ1ApwZwBoAQAYAAgJ1ApwZwBoAQAAAA==.Laughter:BAAALgAECgYJEgAAAA==.Laurana:BAAALgADCgIJAgAAAA==.Lazulie:BAAALgAECgYJEgAAAA==.',
Le='Leansipper:BAABLgAFFH8QAAIMAAQJ6hOyHQAYAQAMAAQJ6hOyHQAYAQAAAA==.Legendäiry:BAAALgAECgEJAQAAAA==.Levoker:BAAALgAECgQJBAAAAA==.Lexapayne:BAAALgAECgYJEgABLgAFFAQJDAAYAOcUAA==.',
Li='Lighthammer:BAAALgADCgEJAQAAAA==.Lilandra:BAAALgAECgYJDwABLgAECggJDgAGAAAAAA==.Lillianaxe:BAABLgAECn8XAAMjAAcJHRgQHgBbAQAjAAYJsBkQHgBbAQAEAAcJAA++igBGAQAAAA==.Lilyvain:BAAALgAECgUJCAAAAA==.Lireal:BAABLgAECn8wAAIUAAkJjiWgAADLAwAUAAkJjiWgAADLAwAAAA==.Listerine:BAAALgAECggJCQAAAA==.Litercola:BAABLgAECn8UAAIIAAYJjgKdUACLAAAIAAYJjgKdUACLAAAAAA==.Livnod:BAAALgAECgQJCgAAAA==.',
Lo='Loonfabio:BAAALgAECgIJAgABLgAFFAUJEwACACUjAA==.Loosescrew:BAAALgADCgIJAgAAAA==.Lorine:BAABLgAECn87AAIBAAkJbBsoCgAdAgABAAkJbBsoCgAdAgAAAA==.Lowkie:BAAALgADCgIJAgAAAA==.',
Lu='Luckside:BAAALgAECgQJBAABLgAECgkJHgAaACUMAA==.Lunara:BAAALgAECgMJBgAAAA==.Lunasnow:BAAALgAECgQJBAAAAA==.Lunchtime:BAAALgAECgEJAQAAAA==.Luxe:BAAALgADCgEJAQAAAA==.',
Ly='Lyntot:BAAALgADCgEJAQAAAA==.',
['Ló']='Lókki:BAAALgAECgUJCAAAAA==.',
Ma='Madwe:BAABLgAECn8hAAMbAAgJrgcujgD2AAAbAAgJcwYujgD2AAAXAAMJcAZBTQBrAAAAAA==.Mageab:BAABLgAFFH8HAAIFAAYJDB36JQDCAQAFAAYJDB36JQDCAQAAAA==.Magis:BAAALgADCgkJHgAAAA==.Malzzahar:BAAALgAECgQJBAAAAA==.Manimetal:BAAALgAECgUJEgAAAA==.Materia:BAAALgAECgcJBwAAAA==.',
Me='Meeralax:BAABLgAECn8WAAIYAAYJJgb1sADQAAAYAAYJJgb1sADQAAAAAA==.Melizza:BAAALgADCgMJAwAAAA==.Merckel:BAACLgAFFH8IAAIbAAMJMhpmUQDoAAAbAAMJMhpmUQDoAAAuAAQKfywAAhsACAk5IHobAGUCABsACAk5IHobAGUCAAAA.Merckz:BAAALgAECgUJBQABLgAFFAMJCAAbADIaAA==.Merks:BAAALgAECgEJAQAAAA==.Metalmonkey:BAAALgAECgYJCQAAAA==.',
Mi='Michello:BAABLgAECn8YAAIYAAgJeB3VLAAeAgAYAAgJeB3VLAAeAgAAAA==.Mickcowmoose:BAAALgADCgIJAgAAAA==.Millia:BAABLgAECn8oAAIFAAgJph4UKQBvAgAFAAgJph4UKQBvAgABLgAECgkJHgACAH0iAA==.Mint:BAABLgAECn8jAAIUAAcJiyOLDgCiAgAUAAcJiyOLDgCiAgAAAA==.Mintberrytea:BAAALgAECgUJBwABLgAECgcJIwAUAIsjAA==.Mintchaitea:BAABLgAECn8VAAIKAAkJTiGmBABZAwAKAAkJTiGmBABZAwABLgAECgcJIwAUAIsjAA==.Misstress:BAABLgAECn81AAMMAAkJGg1DKACAAQAMAAkJGg1DKACAAQANAAEJ/ggzcQAlAAAAAA==.Mizen:BAAALgADCgUJCAAAAA==.',
Mo='Mogdor:BAAALgADCgUJBQAAAA==.Monkussy:BAAALgAECgIJAgAAAA==.Moonhunt:BAAALgAECgQJCgAAAA==.Moonly:BAABLgAECn8mAAIhAAkJYQxqGgDGAQAhAAkJYQxqGgDGAQAAAA==.Morrag:BAABLgAECn8qAAMaAAgJkAomcABVAQAaAAgJkAomcABVAQAZAAEJjAbSPAAuAAAAAA==.',
Mu='Murdumurdu:BAAALgAECgUJCAAAAA==.Murkblade:BAAALgADCgYJBgABLgAECgcJHgAbAKIVAA==.Musho:BAAALgADCgYJEgAAAA==.Mustakrakish:BAAALgAECgEJAQAAAA==.',
My='Myn:BAABLgAECn8XAAIJAAkJwhkzFQCWAgAJAAkJwhkzFQCWAgAAAA==.Myw:BAAALgAECgcJBwABLgAFFAgJLAAeALkWAA==.',
['Mæ']='Mædenless:BAAALgAECgYJCQAAAA==.',
['Mí']='Mísfìt:BAABLgAECn88AAMeAAkJQRnFHwBEAgAeAAkJQRnFHwBEAgAHAAgJEQzaOQBAAQAAAA==.',
Na='Nakaito:BAABLgAECn8aAAIaAAgJ+Ay6aQBkAQAaAAgJ+Ay6aQBkAQABLgAECgkJNgAcAA8bAA==.Narcoleptic:BAACLgAFFH8MAAISAAQJrAxbGgDbAAASAAQJrAxbGgDbAAAuAAQKfz8ABBIACQnqGNYGAIkCABIACQnqGNYGAIkCABMACAmFFiglAKwBACYABAmuBVQvAJ0AAAAA.Nashty:BAAALgAECgEJAQAAAA==.',
Ne='Neocracy:BAAALgADCgYJCwABLgAECggJFAAUAN0bAA==.Nex:BAAALgADCgYJCAAAAA==.',
Ni='Niceshield:BAAALgAECgEJBQAAAA==.Nightmarexx:BAACLgAFFH8VAAIVAAUJZh73FgBJAQAVAAUJZh73FgBJAQAuAAQKf04AAhUACAmnIfEJAHoCABUACAmnIfEJAHoCAAAA.Nightsawdy:BAABLgAECn8qAAMYAAgJQRcrWQCMAQAYAAcJThcrWQCMAQAhAAcJFhEeIwCAAQAAAA==.Nightsnake:BAAALgAECgMJAwAAAA==.Niightstorm:BAABLgAECn8jAAMYAAcJ1hq9OADwAQAYAAcJ1hq9OADwAQAhAAQJbBJOPQDPAAAAAA==.Nikwillig:BAAALgAECggJDQAAAA==.Nilveron:BAAALgADCgcJCQAAAA==.Nitefire:BAAALgADCgkJEQAAAA==.Nitélifé:BAAALgADCgMJAwAAAA==.',
Nj='Njörðr:BAAALgAECgYJDAAAAA==.',
No='Noxmortis:BAAALgAFFAMJAwAAAA==.',
Nt='Ntadadarknes:BAAALgAECgIJAwABLgAECggJJwAJANgKAA==.',
Oo='Ooblidoom:BAAALgADCgUJBQABLgAECgkJSgAmAFkTAA==.',
Op='Opalinnas:BAABLgAECn8lAAMJAAkJ7RlRGAB6AgAJAAkJ7RlRGAB6AgAMAAUJeQg3WACiAAAAAA==.',
Oz='Ozath:BAAALgAECgQJBgAAAA==.',
Pa='Passionfruit:BAAALgAFFAEJAQAAAA==.',
Pe='Peachtea:BAAALgAECgQJEgAAAA==.',
Ph='Phatshaman:BAABLgAECn8UAAIHAAgJbQdrTADzAAAHAAgJbQdrTADzAAAAAA==.Phæryll:BAAALgADCgUJBgAAAA==.',
Pi='Pirodeath:BAAALgAECgcJCgAAAA==.',
Pl='Place:BAAALgAECgIJAgAAAA==.',
Po='Poisonclaw:BAAALgAECgIJBAAAAA==.Poprotonix:BAABLgAECn8fAAICAAgJPxZcSQDgAQACAAgJPxZcSQDgAQAAAA==.Pozessedkaos:BAAALgAECgQJBAAAAA==.',
Pr='Praecantrix:BAAALgAECgEJBAAAAA==.Prath:BAAALgADCgEJAQAAAA==.Pray:BAABLgAECn9DAAIoAAkJBCRVAgCOAwAoAAkJBCRVAgCOAwAAAA==.Priestyballz:BAAALgAECgYJBgAAAA==.Prodarkangel:BAABLgAECn8bAAMkAAkJIgm0FQDsAAAkAAkJIgm0FQDsAAAaAAMJaAOzCAFVAAAAAA==.',
Pu='Pubis:BAAALgAECgYJDgAAAA==.Puckllane:BAABLgAECn8aAAICAAkJ5RdiQQAhAgACAAkJ5RdiQQAhAgAAAA==.Punkbeer:BAAALgAECgEJAQAAAA==.Punkin:BAAALgAECgUJCwAAAA==.',
Py='Pyre:BAABLgAECn89AAIoAAkJSQ9BHwDFAQAoAAkJSQ9BHwDFAQABLgADCgUJBQAGAAAAAA==.',
Qu='Quefstank:BAAALgADCgUJCAAAAA==.Quivver:BAAALgADCgkJDgAAAA==.',
Ra='Rabmaxx:BAABLgAECn8oAAIXAAgJwQ2aIwBIAQAXAAgJwQ2aIwBIAQAAAA==.Radren:BAAALgADCgEJAQAAAA==.Rajinazn:BAAALgAECgYJBgAAAA==.Rattchett:BAAALgAECgYJBgAAAA==.Ravenlight:BAABLgAFFH8FAAICAAQJWA61RwAPAQACAAQJWA61RwAPAQAAAA==.Ravenwynnd:BAABLgAECn8mAAIlAAkJuyIOBADVAgAlAAkJuyIOBADVAgAAAA==.Ravix:BAAALgADCgQJBAAAAA==.Raynelock:BAABLgAECn8wAAMkAAkJgRA0CgCSAQAkAAkJgRA0CgCSAQAaAAIJtQcZCQFKAAAAAA==.Raynman:BAABLgAECn9DAAIeAAkJdxXEIwAqAgAeAAkJdxXEIwAqAgAAAA==.Razgriz:BAAALgAECgEJAQAAAA==.Razix:BAABLgAECn8zAAQTAAkJfxSFHgDbAQATAAkJfxSFHgDbAQAmAAYJ6wmZFwCSAAASAAMJYwclPACJAAAAAA==.',
Re='Realist:BAAALgAECgMJBAAAAA==.Refrigtuitor:BAACLgAFFH8aAAMFAAUJSA5eWwApAQAFAAUJSA5eWwApAQApAAIJuALfBABjAAAuAAQKfz8ABAUACQmEH1weAKACAAUACQmEH1weAKACAAsABQmDCGQOAN0AACkAAQk8EL4RADYAAAAA.Reija:BAAALgAECgEJAgAAAA==.Repentance:BAAALgADCgEJAQABLgAECgkJMwAfAOIXAA==.Revealed:BAAALgADCgEJAQAAAA==.Reyeda:BAAALgADCgUJBQAAAA==.Rezzarn:BAAALgAECgEJAQAAAA==.',
Rh='Rhun:BAAALgAECgYJCQAAAA==.Rhyzer:BAABLgAECn8lAAMRAAcJrhzsHAAAAgARAAcJrhzsHAAAAgAlAAEJJQ1bRQAuAAAAAA==.',
Ri='Rileyksufan:BAABLgAECn8VAAIYAAkJhg4idgBHAQAYAAkJhg4idgBHAQAAAA==.Rinas:BAACLgAFFH8FAAIXAAIJpxe6HACSAAAXAAIJpxe6HACSAAAuAAQKfzYAAxcACQm4IvQCACIDABcACQm4IvQCACIDABsAAgmfDcIFATUAAAAA.Rivendell:BAAALgAECgQJBgAAAA==.Rivenlynn:BAAALgADCgEJAQAAAA==.',
Ru='Rubioxis:BAAALgADCgYJBgAAAA==.',
Ry='Rymarri:BAAALgADCgkJCQAAAA==.',
Sa='Sabazia:BAACLgAFFH8JAAIjAAMJWRpwHQDpAAAjAAMJWRpwHQDpAAAuAAQKfzsAAiMACQkXIPYGAKYCACMACQkXIPYGAKYCAAAA.Sacrificer:BAAALgAECgMJAwAAAA==.Sairalindë:BAABLgAECn8fAAMYAAgJdwfbcQBQAQAYAAgJdwfbcQBQAQAgAAMJpAA3hgA2AAAAAA==.Saleath:BAAALgAECgEJAwAAAA==.Salios:BAABLgAFFH8NAAIaAAQJNB6wFwAzAQAaAAQJNB6wFwAzAQAAAA==.Sallydisco:BAAALgAECgMJAwABLgAFFAQJCgADAN8hAA==.Sanctifier:BAAALgAECgQJDQAAAA==.Saraneth:BAAALgAECgEJAQABLgAECgkJMAAUAI4lAA==.',
Sc='Scandrel:BAAALgAECgQJBAABLgAFFAUJFwAEAPsgAA==.Scrept:BAAALgAECgUJEQAAAA==.Scynix:BAEBLgAECn8pAAMTAAkJdRhwGQADAgATAAkJdRhwGQADAgASAAEJsgFhTgAiAAAAAA==.',
Se='Sedaline:BAAALgAECgQJBgAAAA==.Sephie:BAAALgADCgQJAQAAAQ==.Serenilock:BAAALgADCgMJAwAAAA==.Serfdog:BAAALgADCgcJDAAAAA==.Servoker:BAACLgAFFH8RAAISAAYJXxvWDwCAAQASAAYJXxvWDwCAAQAuAAQKfyUAAxMACAnbICEKANQCABMACAnbICEKANQCABIABwkkGrwVAPABAAAA.Setani:BAAALgADCgIJAgAAAA==.',
Sh='Shabzkaw:BAAALgADCgUJBQAAAA==.Shabzyt:BAAALgADCgQJBAAAAA==.Shaienne:BAAALgAECgMJAwAAAA==.Shambussy:BAAALgAECgEJAQAAAA==.Shamfore:BAAALgADCgEJAQAAAA==.Shamrockshak:BAABLgAECn8hAAIeAAYJAyNTHwBHAgAeAAYJAyNTHwBHAgAAAA==.Shaze:BAAALgADCggJDQAAAA==.Shenuton:BAAALgAECgcJEAAAAA==.Shieldinterd:BAAALgAECgMJAgABLgAECgcJHgAbAKIVAA==.Shiftkicker:BAAALgADCgMJAwAAAA==.Shocktherapy:BAAALgAECgEJAQAAAA==.Shockthêràpy:BAACLgAFFH8JAAIeAAMJjwyRUwCXAAAeAAMJjwyRUwCXAAAuAAQKfzAABB4ACQlbGG0nAPMBAB4ACQlbGG0nAPMBAAcAAwkWFxNkAKkAAB8AAQlPCkYrADgAAAAA.Shoes:BAABLgAECn89AAQhAAkJTSU/AgAlAwAhAAkJxiM/AgAlAwAgAAgJIx/cDQDVAgAYAAgJ9SLuJABDAgAAAA==.Shoresy:BAAALgAECgEJAQAAAA==.Shtdruid:BAAALgAECgcJDAAAAA==.Shyanni:BAAALgADCgMJAwAAAA==.Shöçkér:BAAALgAECgcJDQAAAA==.',
Si='Siaana:BAAALgADCgUJBQABLgAFFAMJCQAjAFkaAA==.Sibearian:BAABLgAECn8eAAQNAAgJ6BikEADNAQANAAgJ6BikEADNAQAOAAYJ0ApdJADTAAAMAAIJPwSEdQBNAAAAAA==.Simi:BAACLgAFFH8MAAIYAAQJ5xR4NQA3AQAYAAQJ5xR4NQA3AQAuAAQKfykAAhgACQmYGSkkAEYCABgACQmYGSkkAEYCAAAA.',
Sk='Skrubzz:BAABLgAECn8ZAAMDAAgJIQbpIAA4AQADAAgJIQbpIAA4AQARAAQJzgKHhwChAAAAAA==.Skôrn:BAABLgAECn8wAAIFAAcJLQ/ikgBMAQAFAAcJLQ/ikgBMAQAAAA==.',
Sl='Sloppynachos:BAABLgAECn8pAAIVAAgJRhdmGgAvAgAVAAgJRhdmGgAvAgAAAA==.Slyman:BAAALgADCgUJBQABLgAECgYJBwAGAAAAAA==.',
Sm='Smithnwesson:BAAALgAECgIJAgAAAA==.Smokesçreen:BAACLgAFFH8LAAIXAAQJpRMRDgAhAQAXAAQJpRMRDgAhAQAuAAQKf0UAAxcACQkEIekEAOwCABcACQkEIekEAOwCABsABQm6BQfLAIkAAAAA.',
Sn='Snowhoof:BAAALgADCgUJBQAAAA==.',
So='Soccerqt:BAAALgAECgUJBQAAAA==.Sogerä:BAABLgAECn8XAAISAAgJIQXBHQADAQASAAgJIQXBHQADAQAAAA==.Soonerpride:BAABLgAECn8cAAICAAgJBCNuKQBRAgACAAgJBCNuKQBRAgAAAA==.Sorinmarkov:BAAALgAFFAIJAgAAAA==.Source:BAAALgAECgUJCAAAAA==.',
Sp='Spearminttea:BAAALgAECgcJCwAAAA==.Spellumgud:BAAALgAECgQJBgAAAA==.',
Sq='Squiby:BAABLgAECn84AAMWAAkJoCI6BgDqAgAWAAkJoCI6BgDqAgAIAAIJmRX+ZwCNAAAAAA==.Squizzy:BAAALgAECgEJAQAAAA==.',
St='Stabfore:BAABLgAECn8lAAMVAAkJ0hQJDwAtAgAVAAkJ0hQJDwAtAgAcAAEJJgR5KgAlAAAAAA==.Standaside:BAAALgAECgIJBAAAAA==.Stinky:BAABLgAECn8XAAIdAAgJkQmtDQApAQAdAAgJkQmtDQApAQAAAA==.Stix:BAACLgAFFH8MAAIVAAQJCh7xEABxAQAVAAQJCh7xEABxAQAuAAQKfysAAxUACQkWGtoSAAICABUACQkWGtoSAAICAB0ABAmnFWQTAMoAAAAA.Stoya:BAAALgAECgQJBgABLgAECgkJMAAUAI4lAA==.Stuef:BAABLgAECn82AAIHAAkJGyGmCQC5AgAHAAkJGyGmCQC5AgAAAA==.Stuefagos:BAAALgAECgQJBwAAAA==.Stuefester:BAABLgAECn8gAAMEAAkJNiCuHQCNAgAEAAkJNiCuHQCNAgAjAAcJ4QlGMQDNAAAAAA==.Stueflare:BAAALgAECggJEAAAAA==.Stueflip:BAAALgADCgIJAgAAAA==.Stunsturds:BAABLgAECn8dAAMKAAYJQiBnGwApAgAKAAYJQiBnGwApAgAPAAEJ2AF+mQAaAAABLgAECgcJHgAbAKIVAA==.Stäirs:BAABLgAECn9CAAIRAAkJ5B0oDgCHAgARAAkJ5B0oDgCHAgAAAA==.',
Su='Summerlily:BAAALgADCgYJBgAAAA==.',
Sv='Svaja:BAAALgADCgkJEQABLgAECggJGgASAAkHAA==.',
Sy='Sylaria:BAAALgAECgUJCwAAAA==.Syreline:BAAALgAECgEJAgAAAA==.',
['Sá']='Sáble:BAACLgAFFH8FAAIBAAMJDAIOEQBmAAABAAMJDAIOEQBmAAAuAAQKfyoAAwEACQlTCcwcACMBAAEACQlNCMwcACMBAAIABwmZCOO9AP8AAAAA.',
['Sí']='Síñ:BAAALgAECgIJAgABLgAECggJIgAaAFIaAA==.',
['Sî']='Sîn:BAAALgADCgEJAQABLgAECggJIgAaAFIaAA==.',
['Sï']='Sïn:BAABLgAECn8iAAIaAAgJUhppOQDvAQAaAAgJUhppOQDvAQAAAA==.',
Ta='Taereachye:BAACLgAFFH8GAAIUAAIJriAaFQCYAAAUAAIJriAaFQCYAAAuAAQKfxcAAhQABwk5JAYKANMCABQABwk5JAYKANMCAAEuAAUUBAkIAAoAgBUA.Tailon:BAAALgADCgYJBgAAAA==.Taintedlove:BAAALgADCgYJBgAAAA==.Talenelat:BAAALgADCgcJCwAAAA==.Talikas:BAAALgAECggJEAABLgAECgkJMwAbAKcaAA==.Tankin:BAAALgADCgMJAwAAAA==.Tantric:BAAALgAECgIJAgABLgAECggJCQAGAAAAAA==.Tarathiel:BAAALgADCgQJBAAAAA==.Taurne:BAACLgAFFH8VAAIJAAYJNwzKGQB9AQAJAAYJNwzKGQB9AQAuAAQKfx4AAgkABwmzGYEwAOkBAAkABwmzGYEwAOkBAAAA.',
Te='Technique:BAAALgAECgIJBAAAAA==.Teebags:BAAALgADCgEJAQAAAA==.Teknoman:BAACLgAFFH8LAAIRAAMJbhkjLQDnAAARAAMJbhkjLQDnAAAuAAQKfzwAAhEACQkIIYAJAMMCABEACQkIIYAJAMMCAAAA.Telmarine:BAAALgAECgMJAwAAAA==.Tempered:BAABLgAECn8YAAMlAAYJMhwqFgChAQAlAAYJMhwqFgChAQARAAQJRRtiYQDGAAAAAA==.Terlemen:BAAALgAECgUJBQAAAA==.Tetsumi:BAAALgADCgYJCQABLgAECggJDgAGAAAAAA==.',
Th='Thaddeus:BAAALgAECgEJAQABLgAFFAQJEQAGAAAAAQ==.Thaitea:BAAALgAECgUJBgAAAA==.Thal:BAAALgAECgMJAwAAAA==.Thalan:BAAALgADCgEJAQAAAA==.Thalindra:BAABLgAECn8kAAIYAAcJUxvGOwDlAQAYAAcJUxvGOwDlAQAAAA==.Tharain:BAAALgADCgkJEQAAAA==.Thebigbeast:BAAALgAFFAIJAgABLgAFFAYJGAAaAJoVAA==.Thecurt:BAABLgAECn9BAAIPAAkJnyQQAgA+AwAPAAkJnyQQAgA+AwAAAA==.Thedammed:BAAALgADCgEJAQAAAA==.Theholylight:BAAALgAECgYJDQAAAA==.Thehuzz:BAAALgAECggJDAAAAA==.Thermidor:BAABLgAECn8gAAIhAAkJYBV5CQBLAgAhAAkJYBV5CQBLAgAAAA==.Thorsamie:BAAALgAECggJDgAAAA==.Thrasios:BAAALgAECgIJAgAAAA==.Thundercunti:BAAALgADCgYJDAABLgAECggJOAAVAHsgAA==.',
Ti='Tiamatt:BAAALgADCgIJBAAAAA==.Ticktock:BAAALgAECgIJAgAAAA==.Timaeus:BAABLgAECn8YAAIRAAcJAQIwfgBrAAARAAcJAQIwfgBrAAAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Titanlock:BAAALgAECgUJCQAAAA==.',
Tk='Tkdfath:BAAALgAECggJEgAAAA==.',
To='Torvia:BAAALgAECgUJCwAAAA==.Totemix:BAAALgADCgcJEgAAAA==.Totemsoul:BAAALgAECgEJAgABLgAECgcJCgAGAAAAAA==.',
Tr='Trisinz:BAABLgAECn8lAAIMAAgJ0RdYHADZAQAMAAgJ0RdYHADZAQAAAA==.Trixa:BAAALgADCgMJAwAAAA==.',
Tu='Tuerto:BAAALgAECgYJEwAAAA==.Turbojohnson:BAAALgAECgQJBgAAAA==.Turk:BAABLgAECn9EAAMbAAkJtRefIwA2AgAbAAkJtRefIwA2AgAXAAEJCQ/BcwAxAAAAAA==.Turkish:BAABLgAECn9AAAMEAAkJZBq/LwA3AgAEAAkJZBq/LwA3AgAnAAEJ7gYqOgAoAAAAAA==.Turtledisco:BAACLgAFFH8KAAIDAAQJ3yGiEAAYAQADAAQJ3yGiEAAYAQAuAAQKfycAAgMACQnSH7sDABcDAAMACQnSH7sDABcDAAAA.',
Ty='Tychaa:BAAALgADCgkJEQAAAA==.Tylat:BAAALgADCgEJBAAAAA==.Tyranax:BAACLgAFFH8FAAIoAAIJ1wrYOAB9AAAoAAIJ1wrYOAB9AAAuAAQKfz0ABCgACQnlG5wJAM0CACgACQneGpwJAM0CAAgABgnVH1IcAPoBABYABwkxE6YvAFkBAAAA.Tyyregade:BAAALgADCgkJCgABLgAECggJDgAGAAAAAA==.',
Uj='Ujimas:BAAALgAECgEJAgAAAA==.',
Us='Us:BAAALgAECggJCQAAAA==.',
Uz='Uzzi:BAAALgAECgEJAQAAAA==.',
Va='Vadose:BAABLgAECn8gAAIaAAcJwQqmgQBXAQAaAAcJwQqmgQBXAQABLgAFFAQJDAAYAOcUAA==.Vales:BAAALgAECgMJAwABLgAFFAMJBQAYAMABAA==.Valsavis:BAABLgAECn8bAAIMAAYJbRQ6NQA0AQAMAAYJbRQ6NQA0AQAAAA==.Valytrois:BAABLgAECn8UAAIaAAcJXQmysQD1AAAaAAcJXQmysQD1AAAAAA==.Varinix:BAAALgADCgMJBQAAAA==.',
Ve='Veggiebaha:BAAALgADCgIJAgAAAA==.Veiksla:BAABLgAECn8aAAMSAAgJCQf8GQAuAQASAAgJCQf8GQAuAQAmAAEJoQNSKQAgAAAAAA==.Velore:BAAALgADCgcJDAAAAA==.Vengerr:BAAALgAECgQJBgAAAA==.Verace:BAAALgAECgcJAQAAAA==.Verradic:BAAALgAECgYJDAABLgAECggJHwAYABQNAA==.',
Vi='Vitur:BAABLgAECn9HAAIbAAkJ/iD3EwCYAgAbAAkJ/iD3EwCYAgAAAA==.',
Vo='Voidhunter:BAABLgAECn8VAAIbAAcJGwpFjwD0AAAbAAcJGwpFjwD0AAAAAA==.Voidweaver:BAAALgAECgMJBQAAAA==.Volaine:BAABLgAECn8lAAMaAAcJuA9WcwBOAQAaAAYJjQ9WcwBOAQAZAAIJuhQROAA4AAAAAA==.Volt:BAABLgAECn8zAAIfAAkJ4hfKCQATAgAfAAkJ4hfKCQATAgAAAA==.Volumoso:BAAALgAECgYJBgAAAA==.Volwryn:BAAALgAECgUJCAABLgAECggJCQAGAAAAAA==.',
Vy='Vynarian:BAABLgAECn8lAAIFAAcJIRVWcACTAQAFAAcJIRVWcACTAQAAAA==.',
['Vâ']='Vâljean:BAAALgADCgMJAwAAAA==.',
['Vô']='Vôx:BAAALgAECgEJAQABLgAECggJIQAQAJEZAA==.',
['Vö']='Vöx:BAAALgAECgEJAQABLgAECggJIQAQAJEZAA==.',
Wa='Warbeard:BAABLgAECn8oAAIRAAkJ8gtrKgCmAQARAAkJ8gtrKgCmAQAAAA==.',
Wi='Wizwizx:BAAALgADCgUJBgAAAA==.',
Wr='Wreckbums:BAABLgAFFH8HAAIEAAMJKBjxfgD2AAAEAAMJKBjxfgD2AAAAAA==.Wreckd:BAABLgAECn8eAAMbAAcJHxdxTgCOAQAbAAcJHxdxTgCOAQAXAAIJIgyBbAAqAAAAAA==.',
Wy='Wyth:BAAALgAECgQJBQABLgAECgQJBgAGAAAAAA==.',
Xa='Xanthad:BAAALgADCgEJAQAAAA==.',
Xb='Xb:BAAALgADCgkJDgAAAA==.',
Xi='Xitãozinho:BAAALgAECgUJBwAAAA==.',
Xo='Xolair:BAAALgAECgYJDgAAAA==.',
Ya='Yaalia:BAABLgAECn8WAAMCAAcJtAVEzgDoAAACAAcJtAVEzgDoAAAUAAIJZwIKowAiAAAAAA==.Yaan:BAABLgAECn8gAAIHAAgJMQriQgAYAQAHAAgJMQriQgAYAQAAAA==.',
Yo='Yoba:BAAALgAECgMJAwAAAA==.Yoshira:BAAALgADCgQJBAAAAA==.',
['Yö']='Yör:BAAALgAECgEJAQAAAA==.',
Za='Zain:BAABLgAECn9GAAQlAAkJNx1VBwB4AgAlAAkJNx1VBwB4AgARAAYJGA5fWQBIAQADAAIJKA0qRgBNAAAAAA==.Zandibar:BAABLgAECn8kAAIRAAcJdh90FwAtAgARAAcJdh90FwAtAgAAAA==.Zaptoasted:BAAALgAECgUJBgAAAA==.Zaroff:BAAALgAECgYJCgAAAA==.',
Ze='Zedadiah:BAAALgADCgEJAQAAAA==.Zelah:BAAALgAECgQJBAAAAA==.Zenessa:BAAALgADCgYJBgAAAA==.',
Zi='Zillah:BAAALgAECgEJAQABLgAECgcJCgAGAAAAAA==.Zinder:BAABLgAECn8oAAIFAAkJsQ59VgDTAQAFAAkJsQ59VgDTAQAAAA==.',
Zu='Zuggie:BAABLgAECn8eAAIaAAgJJQa+nQD+AAAaAAgJJQa+nQD+AAAAAA==.Zugtail:BAAALgAECgQJBwABLgAECggJHgAaACUGAA==.Zurtrinik:BAACLgAFFH8aAAIDAAgJfB+vAwAaAgADAAgJfB+vAwAaAgAuAAQKfyUAAgMACAmZJDwCAE0DAAMACAmZJDwCAE0DAAAA.',
Zy='Zylith:BAAALgAECgYJBwABLgAECgkJMwAfAOIXAA==.',
Zz='Zzonked:BAABLgAECn8pAAMEAAkJCwhYhwBMAQAEAAkJzwZYhwBMAQAjAAIJ/gtGPwBSAAAAAA==.',
['Zê']='Zêp:BAAALgAECgEJAgAAAA==.',
['Zø']='Zøømies:BAABLgAECn8qAAMbAAkJhhcEMgDyAQAbAAkJMBcEMgDyAQAiAAYJFQ91FQDwAAAAAA==.',
['Är']='Äréa:BAAALgADCgkJCQAAAA==.',
['Äs']='Äshnärd:BAACLgAFFH8KAAIeAAMJqyPnJwAtAQAeAAMJqyPnJwAtAQAuAAQKfzQAAh4ACQlUJMoEAF4DAB4ACQlUJMoEAF4DAAAA.',
['Ða']='Ðar:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðoogle:BAABLgAECn8XAAIHAAcJ5RnOLQB9AQAHAAcJ5RnOLQB9AQAAAA==.',
['Ðr']='Ðruidess:BAAALgAECgMJAwAAAA==.',
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
