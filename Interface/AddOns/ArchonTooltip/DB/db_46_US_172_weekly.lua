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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Protection','DeathKnight-Unholy','Mage-Frost','Unknown-Unknown','Shaman-Elemental','Priest-Holy','Druid-Restoration','Monk-Mistweaver','DemonHunter-Devourer','Mage-Arcane','Druid-Balance','Druid-Guardian','Druid-Feral','Monk-Brewmaster','Monk-Windwalker','Warrior-Fury','Evoker-Preservation','Evoker-Augmentation','Paladin-Holy','Rogue-Subtlety','Priest-Shadow','DemonHunter-Havoc','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Rogue-Assassination','Rogue-Outlaw','Shaman-Restoration','Shaman-Enhancement','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Vengeance','DeathKnight-Blood','Warlock-Destruction','Warrior-Arms','Evoker-Devastation','DeathKnight-Frost','Priest-Discipline','Mage-Fire',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=46,date='2026-06-13',data={Ad='Adrador:BAABLgAECn8sAAMBAAkJeST9AQAbAwABAAkJeST9AQAbAwACAAIJZxTtEwFvAAAAAA==.Adrenaline:BAACLgAFFH8hAAIDAAUJ2iJoCQCQAQADAAUJ2iJoCQCQAQAuAAQKfzkAAgMACQm8JAQDAAsDAAMACQm8JAQDAAsDAAAA.',
Ae='Aelik:BAACLgAFFH8PAAIEAAMJbBbrhgD3AAAEAAMJbBbrhgD3AAAuAAQKfykAAgQACAnwHRQ4ABwCAAQACAnwHRQ4ABwCAAAA.Aeolian:BAAALgADCgYJCQAAAA==.',
Ah='Ahkimbo:BAAALgADCgUJBQAAAA==.',
Ai='Airolanah:BAAALgAECgUJBQAAAA==.',
Al='Alayssa:BAABLgAECn8sAAIFAAkJXSAQHACxAgAFAAkJXSAQHACxAgAAAA==.Allarius:BAAALgAECgEJAQAAAA==.Allioops:BAAALgADCgUJBQABLgAECgMJBAAGAAAAAA==.Alnima:BAACLgAFFH8GAAIHAAMJ/QFVQAB/AAAHAAMJ/QFVQAB/AAAuAAQKfxkAAgcACAnOCLk5AGgBAAcACAnOCLk5AGgBAAAA.',
Am='Amilee:BAAALgAECgUJDwAAAA==.Amishhunter:BAAALgADCgEJAQAAAA==.Amoondai:BAACLgAFFH8RAAIIAAMJMSLJFAAXAQAIAAMJMSLJFAAXAQAuAAQKfy8AAggACQmjIgIDAGUDAAgACQmjIgIDAGUDAAAA.Amoondrin:BAABLgAECn8zAAIJAAkJLwkETQBYAQAJAAkJLwkETQBYAQAAAA==.Amplifier:BAAALgADCgUJBQAAAA==.',
An='Analiya:BAAALgADCgMJBAAAAA==.Antichurch:BAAALgADCgEJAQAAAA==.Antisnow:BAAALgAECgIJBQABLgAECgcJCgAGAAAAAA==.Antregon:BAAALgADCgQJBwAAAA==.',
Ar='Araviin:BAABLgAFFH8KAAIFAAMJrAh+rAB+AAAFAAMJrAh+rAB+AAAAAA==.Arazen:BAAALgAECgIJAwAAAA==.Arcillias:BAAALgADCgYJCAABLgAECgYJBwAGAAAAAA==.Arkride:BAAALgAECgEJAQAAAA==.Arlean:BAAALgAECgIJAgAAAA==.Arnadaz:BAAALgADCgEJAQABLgAFFAQJCAAKAIAVAA==.Arrogance:BAAALgADCgcJBwABLgAECggJCQAGAAAAAA==.Arthia:BAAALgAECgQJEAAAAA==.Arvidpally:BAAALgAECgIJAgAAAA==.',
As='Ashmehameha:BAAALgADCgQJAgABLgAFFAMJCAAEANoTAA==.Asinn:BAAALgAECgEJAQAAAA==.Asoosimov:BAAALgADCgEJAQAAAA==.',
At='Atredes:BAABLgAFFH8FAAILAAIJ8AaxhAByAAALAAIJ8AaxhAByAAAAAA==.Attima:BAABLgAECn9BAAIMAAkJWBG3AwDTAQAMAAkJWBG3AwDTAQAAAA==.',
Au='Aubriana:BAAALgADCgQJBAAAAA==.Aurøra:BAAALgADCgMJAwAAAA==.Auspex:BAABLgAECn8rAAMNAAkJxwl4NQA9AQANAAkJ6Qd4NQA9AQAOAAkJMAicLgDtAAAAAA==.',
Av='Avaryn:BAACLgAFFH8cAAIJAAUJhhITIgBAAQAJAAUJhhITIgBAAQAuAAQKfzgAAgkACQmZIRgJACUDAAkACQmZIRgJACUDAAAA.',
Ax='Aximlii:BAAALgAECgIJAgAAAA==.',
Az='Azron:BAAALgAECgcJCAABLgAECggJDgAGAAAAAA==.',
Ba='Babavoss:BAAALgAECgkJAQAAAA==.Badarack:BAAALgAECgcJEwABLgAECgkJIAAOAAUlAA==.Badaracka:BAABLgAECn8gAAMOAAkJBSUoAQBRAwAOAAkJBSUoAQBRAwAPAAQJ0hCHLgCjAAAAAA==.Badarackie:BAABLgAECn9DAAMQAAkJSCGRBwC7AgAQAAkJSCGRBwC7AgARAAkJDhXyGADnAQABLgAECgkJIAAOAAUlAA==.Badash:BAABLgAECn8rAAMDAAgJBhtTEADfAQADAAgJBhtTEADfAQASAAEJMQSurQAvAAABLgAFFAMJCAAEANoTAA==.Bahamuth:BAABLgAECn9DAAICAAkJIB3OIgB5AgACAAkJIB3OIgB5AgAAAA==.Bakshi:BAAALgAECgEJBAAAAA==.Banký:BAAALgAECgEJAQAAAA==.Barbattos:BAACLgAFFH8cAAITAAUJ9xhfEQB3AQATAAUJ9xhfEQB3AQAuAAQKfzYAAxMACQkOJK4CADYDABMACQkOJK4CADYDABQAAQnkJKJ8AGEAAAAA.Barnabas:BAAALgADCgYJBgABLgAECgYJBwAGAAAAAA==.Barragon:BAABLgAECn8VAAIVAAcJ5g90NgByAQAVAAcJ5g90NgByAQAAAA==.',
Be='Beans:BAAALgAECgQJBAAAAA==.Bearymanalow:BAAALgAECgMJBAAAAA==.Belfore:BAAALgAECgEJAQABLgAECgkJJQAWANIUAA==.Bethollbrew:BAAALgAECgYJDwAAAA==.Bexley:BAABLgAECn8tAAIBAAkJChrnCABDAgABAAkJChrnCABDAgAAAA==.',
Bi='Biggerbunny:BAACLgAFFH8HAAIXAAMJ6AfwJwC2AAAXAAMJ6AfwJwC2AAAuAAQKfzAAAhcACAmEFZoiALEBABcACAmEFZoiALEBAAAA.Binkter:BAAALgAECgIJBQABLgAECgIJAgAGAAAAAA==.',
Bl='Blackjax:BAAALgADCgEJAQAAAA==.Blacklok:BAAALgAECgUJEQABLgAECgkJNAAYAEElAA==.Blanne:BAAALgAECgEJAQAAAA==.Blargle:BAABLgAECn8uAAIZAAgJKQ+oWwCNAQAZAAgJKQ+oWwCNAQAAAA==.Blessedcross:BAAALgAECgMJBAAAAA==.Bleubahlz:BAAALgADCgcJBwABLgAECgMJAwAGAAAAAA==.Blinx:BAAALgAECgQJBQABLgAECggJDgAGAAAAAA==.Bloodrake:BAABLgAECn87AAIZAAkJHB6mDQDRAgAZAAkJHB6mDQDRAgAAAA==.Bloodreyne:BAAALgADCgEJAgAAAA==.Bloodseekr:BAAALgADCgcJDgAAAA==.Blueray:BAAALgAECgYJCAAAAA==.',
Bo='Boahan:BAAALgAECgMJBQABLgAECgUJCAAGAAAAAA==.Boggart:BAAALgAECgEJAQABLgAECgUJCAAGAAAAAA==.Bohein:BAAALgADCgEJAQAAAA==.Bolus:BAAALgAECgQJCAAAAA==.Botany:BAAALgAECgcJBwAAAA==.Bownafiedba:BAAALgADCgUJBQAAAA==.',
Br='Braneour:BAABLgAECn85AAMVAAkJwBojDADKAgAVAAkJwBojDADKAgACAAMJVBGOKAGEAAAAAA==.Brassballz:BAAALgAECgkJCQAAAA==.Browel:BAABLgAECn8aAAMaAAcJWBj4CAC3AQAaAAYJ3Rj4CAC3AQAbAAYJYQ5anQADAQAAAA==.Bruen:BAAALgAECgYJBwAAAA==.Bryci:BAAALgAECgcJEAAAAA==.',
Bu='Bubbloseven:BAABLgAECn8UAAMVAAgJGhH0KQC8AQAVAAgJGhH0KQC8AQABAAQJABuoHAAtAQAAAA==.Budank:BAAALgADCgMJAwAAAA==.Bumm:BAABLgAECn8aAAICAAYJzwhf3wDbAAACAAYJzwhf3wDbAAAAAA==.Bustybubbles:BAAALgADCgYJBgAAAA==.',
Bz='Bzspy:BAABLgAFFH8LAAISAAMJzwwfOQDHAAASAAMJzwwfOQDHAAAAAA==.',
Ca='Caalin:BAAALgAECgEJAgAAAA==.Cabooselul:BAAALgAECgQJCwAAAA==.Calibre:BAABLgAECn8eAAILAAcJohWXZwBTAQALAAcJohWXZwBTAQAAAA==.Calyptus:BAABLgAECn8fAAIbAAYJhAowrADqAAAbAAYJhAowrADqAAAAAA==.Caprious:BAACLgAFFH8bAAIEAAUJwxm2TABUAQAEAAUJwxm2TABUAQAuAAQKfzYAAgQACQnjJBEKAB0DAAQACQnjJBEKAB0DAAAA.Capylaura:BAABLgAECn8bAAIZAAcJwAqUfwA7AQAZAAcJwAqUfwA7AQAAAA==.Caratine:BAABLgAECn8cAAILAAgJkAp8fgAfAQALAAgJkAp8fgAfAQAAAA==.Cassandrar:BAABLgAECn8yAAQcAAkJGSQIAQA5AwAcAAgJMiQIAQA5AwAWAAYJtiDUHgCbAQAdAAEJphTSIgA5AAAAAA==.Cassandraw:BAAALgAECgYJBgABLgAECgkJMgAcABkkAA==.Cat:BAAALgADCgUJBQAAAA==.Cattlelac:BAAALgADCgUJCAAAAA==.Caymus:BAABLgAECn8uAAIJAAkJgwhFUgBDAQAJAAkJgwhFUgBDAQAAAA==.',
Ce='Celìa:BAABLgAECn8nAAIZAAkJdQgOZgBzAQAZAAkJdQgOZgBzAQAAAA==.Cess:BAAALgAECgEJAgAAAA==.',
Ch='Chaoticone:BAAALgADCgYJBgAAAA==.Chema:BAABLgAFFH8IAAIKAAQJgBVEKwAIAQAKAAQJgBVEKwAIAQAAAA==.Chestylarue:BAAALgAECgEJAQABLgAECggJEgAGAAAAAA==.Chfgaribaldi:BAAALgADCggJDgAAAA==.Chills:BAAALgAECgcJEQAAAA==.Chillymage:BAAALgADCgYJBgAAAA==.Chosen:BAABLgAECn8YAAICAAYJRBdtYgC+AQACAAYJRBdtYgC+AQABLgAFFAUJFwAEAPsgAA==.Chpchop:BAAALgADCgIJAgAAAA==.Chugg:BAABLgAECn8fAAIeAAkJwghlWQBNAQAeAAkJwghlWQBNAQAAAA==.',
Ci='Ciaphus:BAABLgAECn8nAAICAAkJ0hSRRQDzAQACAAkJ0hSRRQDzAQAAAA==.Cinnamonster:BAAALgAECgcJDgAAAA==.',
Co='Coffeedemon:BAAALgADCgEJAQAAAA==.Coldslappins:BAAALgAECggJEwAAAA==.Contagion:BAAALgAECgYJBQAAAA==.Convoke:BAABLgAECn8eAAINAAcJDSArFgBeAgANAAcJDSArFgBeAgAAAA==.Coragrr:BAAALgADCgcJDQAAAA==.',
Cr='Crazycrocey:BAAALgAECgYJCAAAAA==.Cryptonight:BAAALgAECgQJBAAAAA==.',
Cu='Cubcake:BAAALgADCggJCAAAAA==.Curtastrophe:BAABLgAECn89AAIFAAkJHx0vJwB7AgAFAAkJHx0vJwB7AgAAAA==.Curticus:BAAALgADCgQJBAAAAA==.Curtissax:BAAALgAECgIJAgAAAA==.Curtnought:BAAALgADCgIJAgAAAA==.',
['Cé']='Cérnùnnøs:BAAALgAECgEJAQAAAA==.',
Da='Daelanos:BAABLgAECn8cAAISAAgJPBjoLwCNAQASAAgJPBjoLwCNAQAAAA==.Dalinar:BAAALgAECgUJCwAAAA==.Daranger:BAAALgADCgEJAQAAAA==.Darska:BAAALgADCgYJBgABLgAECggJDgAGAAAAAA==.',
De='Deadtauren:BAAALgADCgYJDwAAAA==.Deathdemon:BAAALgAECgYJDgAAAA==.Deathfue:BAAALgAECgEJAwABLgAECgcJCgAGAAAAAA==.Deathisreal:BAAALgADCgMJAwABLgAECgUJDQAGAAAAAA==.Deathoof:BAAALgAECgIJAgAAAA==.Decimated:BAACLgAFFH8XAAIEAAUJ+yAtPwByAQAEAAUJ+yAtPwByAQAuAAQKfyAAAgQACQkwIzQYALMCAAQACQkwIzQYALMCAAAA.Degeneracy:BAAALgAECgcJCwAAAA==.Demon:BAAALgAECgkJDQAAAA==.Demonilla:BAAALgAECgcJEgAAAA==.Dempkiston:BAAALgAECgYJCwAAAA==.Denable:BAABLgAECn8qAAIJAAcJSg8DTwBQAQAJAAcJSg8DTwBQAQAAAA==.Denogan:BAAALgAECggJDgAAAA==.Deservis:BAAALgAECgUJDgABLgAECgcJHgALAKIVAA==.Destro:BAABLgAECn8pAAIbAAkJ7w8bSQC+AQAbAAkJ7w8bSQC+AQABLgAECgkJMwAfAOIXAA==.Dethadin:BAAALgADCgcJBwAAAA==.',
Di='Dilaudyd:BAAALgAECgMJBAAAAA==.Dirteemike:BAAALgADCgMJAwAAAA==.Disbeleaf:BAACLgAFFH8FAAMNAAMJzhJaOQCLAAANAAIJJBZaOQCLAAAJAAIJegs4WABmAAAuAAQKfxUAAwkABgkBGbE5AKwBAAkABgkBGbE5AKwBAA0ABQlRIEwtAGsBAAAA.Discoflurry:BAAALgAECgcJDgABLgAFFAQJCgADAN8hAA==.Dizzyfist:BAAALgAECgYJCQABLgAECggJDgAGAAAAAA==.',
Do='Dogaz:BAAALgADCgkJDwAAAA==.Dogsoldier:BAAALgADCgIJAgAAAA==.Donori:BAAALgAECgQJDQAAAA==.Dorcath:BAAALgAFFAIJBAABLgAECggJHAASADwYAA==.',
Dr='Dragan:BAAALgAECgQJEQAAAA==.Dragapult:BAAALgAECggJAwAAAA==.Dragonias:BAABLgAECn8dAAIgAAgJ0RXMCgC7AQAgAAgJ0RXMCgC7AQAAAA==.Draino:BAAALgADCgUJBQAAAA==.Drakthorn:BAAALgAECgcJDAAAAA==.Dreselwings:BAAALgAECggJCAABLgAFFAgJHgAZAJsfAA==.Drinny:BAABLgAECn8yAAIIAAkJtwjxMQA+AQAIAAkJtwjxMQA+AQAAAA==.Drqueenisin:BAAALgAECgEJAgAAAA==.Druido:BAAALgAECgQJAQAAAA==.',
Du='Duerek:BAAALgAECgUJBgAAAA==.',
['Dè']='Dèaths:BAAALgAECgYJEAAAAA==.',
['Dí']='Dínglebery:BAAALgAECgYJCAAAAA==.',
Ea='Earthangel:BAABLgAECn8qAAIIAAcJHBcbJQCXAQAIAAcJHBcbJQCXAQAAAA==.',
Ed='Edlarel:BAAALgADCgQJBAABLgAECggJCQAGAAAAAA==.',
Ei='Eine:BAABLgAECn9DAAIZAAkJsxURMQAUAgAZAAkJsxURMQAUAgAAAA==.Eitherwind:BAABLgAECn8XAAQhAAYJ2h+0HwCfAQAhAAYJ2h+0HwCfAQAZAAIJchT/qwBsAAAgAAIJNxO0OgA0AAABLgAECggJDgAGAAAAAA==.Eivore:BAAALgAECgcJBwAAAA==.',
Ek='Ekoh:BAAALgAECgEJAgAAAA==.',
El='Eldergreen:BAABLgAECn8tAAMJAAgJWAyjUwA+AQAJAAgJWAyjUwA+AQANAAIJkwrldwBSAAAAAA==.Eldest:BAAALgADCgUJBQAAAA==.Elfwine:BAABLgAECn8qAAIXAAcJ6g0yNwA2AQAXAAcJ6g0yNwA2AQAAAA==.Elindria:BAABLgAECn80AAQYAAkJQSWpAwAXAwAYAAkJHiWpAwAXAwAiAAkJhiEZAgDsAgALAAUJMxu6ewA0AQAAAA==.Eliora:BAAALgADCgkJCQAAAA==.Elminstir:BAABLgAECn8XAAIFAAgJnhZDZACzAQAFAAgJnhZDZACzAQAAAA==.Elyissia:BAAALgAECgYJDAAAAA==.Elynisa:BAAALgAECgEJAQAAAA==.Elysian:BAABLgAECn84AAQKAAkJcxzGCwDYAgAKAAkJcxzGCwDYAgARAAgJaB/ZDwBLAgAQAAIJyh8BVwCpAAAAAA==.',
Em='Emogo:BAAALgADCgUJCQAAAA==.',
En='Enforcer:BAAALgADCgQJBgAAAA==.Enlightened:BAAALgAECgQJCwAAAA==.Enseral:BAAALgAECgcJEgAAAA==.',
Eo='Eotech:BAAALgAECgQJBAAAAA==.',
Er='Erendora:BAABLgAECn8iAAIJAAkJdg2mPgCVAQAJAAkJdg2mPgCVAQAAAA==.Erets:BAAALgAECgEJAQAAAA==.Eridar:BAAALgAECgYJBgAAAA==.Erizhal:BAAALgAECgUJEAAAAA==.Erodora:BAAALgADCgEJAQAAAA==.',
Es='Esabel:BAAALgAECgkJEgABLgAECgkJLAAFAF0gAA==.',
Ev='Eva:BAAALgAECgEJAgAAAA==.Eviae:BAABLgAECn8rAAIjAAcJBwv2LQDrAAAjAAcJBwv2LQDrAAAAAA==.Evillure:BAABLgAECn8lAAMEAAkJ8hNRQQD8AQAEAAkJ8hNRQQD8AQAjAAUJkgxhOwChAAAAAA==.',
Ez='Ezera:BAAALgAECgUJBQAAAA==.',
Fa='Falan:BAABLgAECn8sAAIeAAkJDhKqLQD8AQAeAAkJDhKqLQD8AQAAAA==.Faputa:BAAALgAECgMJAwAAAA==.Fatherjoe:BAAALgADCgYJBgAAAA==.Fayze:BAEBLgAECn8XAAMcAAcJfiMDBQAwAgAcAAcJSCMDBQAwAgAWAAIJBiFuQAC+AAABLgAFFAIJBAAGAAAAAA==.',
Fe='Felbreaker:BAAALgAECgYJEAAAAA==.Fentril:BAAALgADCgIJAgABLgAECggJDgAGAAAAAA==.Feår:BAABLgAECn8eAAMbAAkJJQzCfAA/AQAbAAgJQgrCfAA/AQAkAAMJ3Q8RSwCMAAAAAA==.',
Fi='Fillianora:BAAALgAECgIJAgAAAA==.Finley:BAAALgAECgQJBQAAAA==.Fircane:BAAALgADCgQJBAAAAA==.Firiel:BAAALgADCgEJAQAAAA==.Fizzle:BAAALgADCggJCAABLgAECgkJJwAJAHYaAA==.',
Fl='Flane:BAAALgAFFAEJBAABLgAFFAgJHgADAHwfAA==.Flem:BAAALgAECgMJBAAAAA==.Flexdruid:BAABLgAECn8XAAMPAAUJzQvsLwCcAAAPAAUJawnsLwCcAAAOAAQJ4whsSQB9AAAAAA==.',
Fo='Foog:BAABLgAECn8XAAMSAAgJwxiIMACKAQASAAYJoBqIMACKAQAlAAUJkRFDKgAfAQAAAA==.',
Fr='Fragil:BAABLgAECn8+AAIWAAgJsCHGDABWAgAWAAgJsCHGDABWAgAAAA==.Frostmane:BAACLgAFFH8aAAMEAAYJEh3eIQDbAQAEAAUJEh3eIQDbAQAjAAEJAADkWgAAAAAuAAQKfzkAAwQACQlWJZYFAEwDAAQACQlWJZYFAEwDACMABwn+HMANADECAAAA.Frostynug:BAAALgADCgYJBgAAAA==.',
Fu='Fudge:BAAALgADCgYJBgAAAA==.Furbyn:BAAALgADCgIJAgAAAA==.',
Ga='Galena:BAABLgAECn8cAAIJAAgJcwumUgBCAQAJAAgJcwumUgBCAQAAAA==.Gallamier:BAAALgADCgEJAQAAAA==.Gamerinator:BAAALgADCgcJCwAAAA==.Gangreene:BAAALgADCgYJCgAAAA==.Garoanna:BAAALgAECgYJBgABLgAECgkJJAAUAFIMAA==.',
Ge='Geshalt:BAAALgAECgEJAQAAAA==.Geshtal:BAAALgAECgQJDAAAAA==.Gets:BAAALgADCgMJBAAAAA==.',
Gi='Girion:BAABLgAECn8rAAIBAAcJYw9sHgAdAQABAAcJYw9sHgAdAQAAAA==.Girliepop:BAAALgAECgEJAQAAAA==.',
Gl='Glaiven:BAECLgAFFH8dAAMLAAUJbBvANwA+AQALAAUJbBvANwA+AQAiAAMJuA8bDgBhAAAuAAQKfy8AAyIACQmVIXgEAHQCAAsACQkrH6EdAKACACIACQmXHHgEAHQCAAAA.Glorfinndel:BAAALgADCgQJBAAAAA==.Glyr:BAAALgADCgUJBQAAAA==.',
Go='Gorgrin:BAAALgAECgcJEwAAAA==.Goude:BAAALgADCgMJBAAAAA==.',
Gr='Greenback:BAAALgADCgYJCwAAAA==.Greentotes:BAEBLgAECn8yAAMUAAkJ7x86CADSAgAUAAkJ7x86CADSAgAmAAUJTxNJEgDhAAABLgAECgIJBAAGAAAAAA==.',
Gu='Gunter:BAAALgAECgMJAwABLgAFFAUJFwAEAPsgAA==.Gura:BAAALgADCgEJAQAAAA==.Gurnee:BAAALgADCgcJDQABLgAECggJEQAGAAAAAA==.Guthix:BAAALgAECgUJBgAAAA==.',
['Gê']='Gêm:BAABLgAECn9GAAITAAkJ8xKiDAAGAgATAAkJ8xKiDAAGAgAAAA==.',
['Gï']='Gïmlï:BAAALgADCgMJAwAAAA==.',
Ha='Haildydra:BAAALgAECgEJAQABLgAECgcJCgAGAAAAAA==.Halibell:BAAALgAECgYJDQAAAA==.Halnan:BAAALgADCgEJAQABLgAECgcJHgALAKIVAA==.Harkanum:BAABLgAECn9GAAQmAAkJ9hlXBgDnAQAmAAgJLhhXBgDnAQATAAkJGg1SEgCgAQAUAAQJrxPwPgDuAAAAAA==.Harrow:BAAALgAECgMJAwAAAA==.Hartman:BAAALgAECgQJBQAAAA==.Harvester:BAAALgAECgEJAQAAAA==.Hatebreéd:BAAALgAECggJCQAAAA==.',
He='Healinturds:BAAALgAECgYJDAABLgAECgcJHgALAKIVAA==.Hector:BAABLgAECn8eAAICAAkJfSL6JQBqAgACAAkJfSL6JQBqAgABLgAECgkJKgAFAOkeAA==.Heelys:BAAALgAECgYJCgAAAA==.Helloagain:BAACLgAFFH8VAAIFAAQJtRq+SwBPAQAFAAQJtRq+SwBPAQAuAAQKfyUAAgUABglqIyFdACMCAAUABglqIyFdACMCAAAA.Herryknutsak:BAAALgAECgEJAQAAAA==.Hestonater:BAAALgAECgUJBwAAAA==.Hestra:BAAALgADCgMJBAAAAA==.Hexidecimal:BAAALgAECgQJBAAAAA==.',
Hi='Hidethetotem:BAABLgAECn8pAAMeAAkJlRzdDQDjAgAeAAkJlRzdDQDjAgAHAAEJHgo+rwAnAAAAAA==.Hightops:BAAALgAECggJDgAAAA==.Hikari:BAACLgAFFH8OAAICAAYJpgzWLwBMAQACAAYJpgzWLwBMAQAuAAQKfx4AAgIACQlrHOAsAHACAAIACQlrHOAsAHACAAAA.Hiown:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.',
Ho='Holeliness:BAAALgAECggJEwAAAA==.Holybackshot:BAAALgAECgQJBgAAAA==.Holydisco:BAAALgADCgcJCQAAAA==.Holyhide:BAAALgAECgEJAQAAAA==.Holyspike:BAABLgAECn8cAAIeAAgJphAxQwCdAQAeAAgJphAxQwCdAQAAAA==.Holytard:BAAALgADCgYJBgAAAA==.Holytaren:BAABLgAECn8UAAIVAAgJ3RuCEwBxAgAVAAgJ3RuCEwBxAgAAAA==.Holytickles:BAABLgAECn8sAAMXAAkJ4hsCEwBeAgAXAAgJ+hsCEwBeAgAIAAkJsBdoEgBIAgABLgAFFAYJGAAbAJoVAA==.Holytotem:BAAALgAECgEJAQAAAA==.Homerr:BAABLgAECn8gAAIZAAgJOxLFUgCmAQAZAAgJOxLFUgCmAQAAAA==.Honiahaka:BAABLgAECn9DAAIZAAkJBxBqRQDNAQAZAAkJBxBqRQDNAQAAAA==.Hottcakes:BAAALgAFFAEJAQABLgAFFAYJGAAbAJoVAA==.',
Hu='Huckster:BAABLgAECn8ZAAIEAAgJhQ6kfABnAQAEAAgJhQ6kfABnAQAAAA==.Humanoidholy:BAABLgAECn8fAAMCAAgJXSQ6CQBIAwACAAgJXSQ6CQBIAwABAAEJbgXWTQAYAAABLgAFFAUJFAAYAJgjAA==.Humanoidhunt:BAAALgAFFAEJAQABLgAFFAUJFAAYAJgjAA==.Humanoidvoid:BAACLgAFFH8UAAQYAAUJmCPTBgCSAQAYAAQJVCPTBgCSAQALAAMJ9h2KUwDtAAAiAAEJAAA+FwAAAAAuAAQKf1MABAsACQkFIwQHABoDAAsACQmdIgQHABoDABgACAnlH1EKAIACACIACAkoCHAVAPwAAAAA.',
Hy='Hydrah:BAAALgAECgEJAQABLgAECgcJCgAGAAAAAA==.',
Ic='Icedtea:BAAALgAECgcJBAAAAA==.Icicle:BAAALgADCgIJAgAAAA==.',
Id='Idunasil:BAAALgAECgEJAQAAAA==.',
Ih='Ihatemustard:BAABLgAECn8jAAIiAAkJ6RUCCAD2AQAiAAkJ6RUCCAD2AQAAAA==.',
Il='Illethan:BAAALgADCgYJBgAAAA==.Iloveketchup:BAAALgAFFAEJAQAAAA==.',
In='Inoru:BAABLgAECn8bAAMXAAcJhRHOMABYAQAXAAcJhRHOMABYAQAIAAEJpwJ7egAcAAAAAA==.Insanity:BAAALgAECgUJCgAAAA==.',
Ir='Irmaline:BAABLgAECn8cAAIIAAgJkxR2IAC6AQAIAAgJkxR2IAC6AQAAAA==.',
It='Ithurtshuh:BAAALgAECgUJDQAAAA==.Itsmaam:BAAALgAECgMJBAAAAA==.Itzcannibal:BAACLgAFFH8GAAIZAAIJ6grbiACDAAAZAAIJ6grbiACDAAAuAAQKfy8AAxkACQk4G+sqAC4CABkACQk4G+sqAC4CACAAAgnVCux5AFoAAAAA.',
Ja='Jabbawockie:BAAALgAECgkJAgAAAA==.Jaekoby:BAAALgAECgIJAwABLgAECggJIgACAM0aAA==.Jakoby:BAAALgAECgUJBgABLgAECggJIgACAM0aAA==.Jandrisel:BAABLgAECn8UAAMNAAYJIwgKUwC9AAANAAYJIwgKUwC9AAAJAAUJtgJ1nQByAAAAAA==.Jarhead:BAAALgAECgEJAgAAAA==.Jayzich:BAAALgADCgQJBwAAAA==.',
Je='Jeffee:BAAALgAECgIJCQAAAA==.Jequalsjosh:BAACLgAFFH8GAAIcAAMJoRwUBwDzAAAcAAMJoRwUBwDzAAAuAAQKfz0AAhwACQkhIk8CALoCABwACQkhIk8CALoCAAAA.Jerk:BAAALgAECgQJBAAAAA==.Jerp:BAAALgAECgIJAgAAAA==.Jesper:BAABLgAECn9GAAIeAAkJ5B8QCgAQAwAeAAkJ5B8QCgAQAwAAAA==.Jetz:BAAALgAECgEJAQAAAA==.Jezelle:BAACLgAFFH8SAAIbAAUJDRB3WwAMAQAbAAUJDRB3WwAMAQAuAAQKfyIAAhsACQn0Hg42ADQCABsACQn0Hg42ADQCAAAA.',
Ji='Jilara:BAABLgAECn85AAICAAkJBgjjkABOAQACAAkJBgjjkABOAQAAAA==.Jimmyjim:BAABLgAECn8ZAAIFAAgJFwyriABiAQAFAAgJFwyriABiAQAAAA==.Jingying:BAAALgADCgMJAwAAAA==.',
Jo='Johnny:BAAALgADCgQJBAAAAA==.',
Jp='Jpepps:BAABLgAECn8vAAMbAAkJDRPSPQDjAQAbAAkJDRPSPQDjAQAkAAMJxwjoRQCeAAAAAA==.',
Jr='Jrose:BAAALgAECgQJBAAAAA==.',
Ju='Jul:BAAALgAECgIJAgAAAA==.',
['Jæ']='Jækobÿ:BAAALgAECgIJAgABLgAECggJIgACAM0aAA==.',
Ka='Kahlanrahl:BAAALgADCgMJAwAAAA==.Kaiatra:BAABLgAECn8bAAInAAgJsSPCAwCeAgAnAAgJsSPCAwCeAgAAAA==.Kaliguala:BAAALgAECgQJBQAAAA==.Katalaystar:BAAALgAECgcJCQABLgAECgkJJwAJAHYaAA==.Katare:BAAALgAECgMJAwAAAA==.Kaulder:BAAALgADCgUJBQAAAA==.Kaìju:BAABLgAECn8iAAICAAgJqiEbIQCBAgACAAgJqiEbIQCBAgAAAA==.Kaîju:BAAALgAECgIJAgAAAA==.',
Ke='Kellytgt:BAABLgAECn8zAAILAAkJpxpJGwBtAgALAAkJpxpJGwBtAgAAAA==.Kev:BAAALgADCgUJBQAAAA==.',
Ki='Kilaura:BAABLgAECn8ZAAIoAAgJWRAPJACsAQAoAAgJWRAPJACsAQAAAA==.Kilmandaros:BAAALgADCgYJCwAAAA==.Kippi:BAAALgAECgQJCwAAAA==.',
Kn='Knitebrite:BAAALgAECgIJAgAAAA==.',
Ko='Korhina:BAABLgAECn9GAAIDAAkJeyYQAQBaAwADAAkJeyYQAQBaAwAAAA==.Korobas:BAAALgAECgMJAwAAAA==.Koru:BAAALgAECgQJBQABLgAECgQJBgAGAAAAAA==.Kosumi:BAAALgADCggJDQAAAA==.',
Kr='Kronic:BAAALgAECgUJCAAAAA==.Kronmon:BAAALgAECgEJAQAAAA==.',
Ku='Kuroyukihime:BAABLgAECn84AAIFAAkJ/h45GwC1AgAFAAkJ/h45GwC1AgAAAA==.Kuwaii:BAABLgAECn8dAAIUAAcJuxgWKAChAQAUAAcJuxgWKAChAQABLgAECggJHgANAA0gAA==.',
Ky='Kyarina:BAAALgAECgEJAQABLgAECgkJGQAIAEMHAA==.Kylis:BAAALgAECgQJBAAAAA==.Kyna:BAABLgAECn8ZAAIIAAkJQwfrOwAAAQAIAAkJQwfrOwAAAQAAAA==.Kyross:BAAALgADCgIJAgAAAA==.',
['Ké']='Kéya:BAAALgAECgYJDQAAAA==.',
La='Lashela:BAABLgAECn8WAAIZAAgJ1ApobQBhAQAZAAgJ1ApobQBhAQAAAA==.Laughter:BAABLgAECn8UAAMSAAcJBAjwXADdAAASAAcJywbwXADdAAADAAQJMAZuNQCbAAAAAA==.Laurana:BAAALgADCgIJAgAAAA==.Lazulie:BAAALgAECgYJEwAAAA==.',
Le='Leansipper:BAABLgAFFH8QAAINAAQJ6hNtIAAVAQANAAQJ6hNtIAAVAQAAAA==.Levoker:BAAALgAECgQJBAAAAA==.Lexapayne:BAAALgAECgYJEgABLgAFFAQJEAAZAOcUAA==.',
Li='Lighthammer:BAAALgADCgEJAQAAAA==.Lilandra:BAAALgAECgYJDwABLgAECggJDgAGAAAAAA==.Lillianaxe:BAABLgAECn8XAAMjAAcJHRhMHwBYAQAjAAYJsBlMHwBYAQAEAAcJAA+9kQBAAQAAAA==.Lilyvain:BAAALgAECgUJCAAAAA==.Lireal:BAABLgAECn8wAAIVAAkJjiWyAADJAwAVAAkJjiWyAADJAwAAAA==.Listerine:BAAALgAECggJCQAAAA==.Litercola:BAABLgAECn8UAAIIAAYJjgJ5UwCJAAAIAAYJjgJ5UwCJAAAAAA==.Livnod:BAAALgAECgQJCgAAAA==.',
Lo='Loonfabio:BAAALgAECgIJAgABLgAFFAUJEwACACUjAA==.Loosescrew:BAAALgADCgMJBAAAAA==.Lorine:BAABLgAECn87AAIBAAkJbBu0CgAbAgABAAkJbBu0CgAbAgAAAA==.Lowkie:BAAALgADCgIJAgAAAA==.',
Lu='Luckside:BAAALgAECgQJBAABLgAECgkJHgAbACUMAA==.Lunara:BAAALgAECgMJBgAAAA==.Lunasnow:BAAALgAECgQJBAAAAA==.Lunchtime:BAAALgAECgEJAQAAAA==.Luxe:BAAALgADCgEJAQAAAA==.',
Ly='Lyntot:BAAALgADCgEJAQAAAA==.',
['Ló']='Lókki:BAAALgAECgUJCAAAAA==.',
Ma='Madwe:BAABLgAECn8hAAMLAAgJrgcPkwD2AAALAAgJcwYPkwD2AAAYAAMJcAarUQBrAAAAAA==.Mageab:BAABLgAFFH8QAAIFAAgJZiC1BwC5AgAFAAgJZiC1BwC5AgAAAA==.Magis:BAAALgADCgkJHgAAAA==.Malzzahar:BAAALgAECgQJBAAAAA==.Manimetal:BAABLgAECn8WAAICAAUJiwWWHgGQAAACAAUJiwWWHgGQAAAAAA==.Materia:BAAALgAECgcJBwAAAA==.',
Me='Meeralax:BAABLgAECn8WAAIZAAYJJgbtuADNAAAZAAYJJgbtuADNAAAAAA==.Melizza:BAAALgADCgMJAwAAAA==.Merckel:BAACLgAFFH8IAAILAAMJMhruVwDhAAALAAMJMhruVwDhAAAuAAQKfywAAgsACAk5ILMcAGUCAAsACAk5ILMcAGUCAAAA.Merckz:BAAALgAECgUJBQABLgAFFAMJCAALADIaAA==.Merks:BAAALgAFFAEJAQAAAA==.Metalmonkey:BAAALgAECgYJCgAAAA==.',
Mi='Michello:BAABLgAECn8ZAAIZAAgJaB4kKgAxAgAZAAgJaB4kKgAxAgAAAA==.Mickcowmoose:BAAALgADCgIJAgAAAA==.Millia:BAABLgAECn8qAAIFAAkJ6R6pFgDPAgAFAAkJ6R6pFgDPAgAAAA==.Mint:BAABLgAECn8jAAIVAAcJiyNJDwCgAgAVAAcJiyNJDwCgAgAAAA==.Mintberrytea:BAAALgAECgUJBwABLgAECgcJIwAVAIsjAA==.Mintchaitea:BAABLgAECn8XAAIKAAkJTiEJBQBZAwAKAAkJTiEJBQBZAwABLgAECgcJIwAVAIsjAA==.Misstress:BAABLgAECn85AAMNAAkJHA7eKQCAAQANAAkJKQ3eKQCAAQAOAAQJ0w6XOQC6AAAAAA==.Mizen:BAAALgADCgUJCAAAAA==.',
Mo='Mogdor:BAAALgADCgUJBQAAAA==.Monkussy:BAAALgAECgIJAgAAAA==.Moonhunt:BAAALgAECgQJCgAAAA==.Moonly:BAACLgAFFH8FAAIhAAMJHQNoKACQAAAhAAMJHQNoKACQAAAuAAQKfyYAAiEACQlhDKUbAMABACEACQlhDKUbAMABAAAA.Morrag:BAABLgAECn8yAAMbAAgJjAzZagBmAQAbAAgJjAzZagBmAQAaAAEJjAaCQAAuAAAAAA==.',
Mu='Murdumurdu:BAAALgAECgUJCAAAAA==.Murkblade:BAAALgADCgYJBgABLgAECgcJHgALAKIVAA==.Musho:BAAALgADCgYJEgAAAA==.Mustakrakish:BAAALgAECgEJAQAAAA==.',
My='Myn:BAABLgAECn8XAAIJAAkJwhnlFQCWAgAJAAkJwhnlFQCWAgAAAA==.Myw:BAAALgAECgcJBwABLgAFFAgJLAAeALkWAA==.',
['Mæ']='Mædenless:BAAALgAECgYJCQAAAA==.',
['Mí']='Mísfìt:BAABLgAECn88AAMeAAkJQRk8IQBEAgAeAAkJQRk8IQBEAgAHAAgJEQxrPAA/AQAAAA==.',
Na='Nakaito:BAABLgAECn8cAAIbAAgJ+AxobgBdAQAbAAgJ+AxobgBdAQABLgAECgkJNwAcAA8bAA==.Narcoleptic:BAACLgAFFH8QAAITAAQJfA/5GQDtAAATAAQJfA/5GQDtAAAuAAQKf0EABBMACQnqGEYHAIECABMACQnqGEYHAIECABQACAmFFocmAKsBACYABQkQCFQvAJ0AAAAA.Nashty:BAAALgAECgEJAQAAAA==.',
Ne='Neocracy:BAAALgADCgYJCwABLgAECggJFAAVAN0bAA==.Nex:BAAALgADCgYJCAAAAA==.',
Ni='Niceshield:BAAALgAECgEJBQAAAA==.Nightmarexx:BAACLgAFFH8VAAIWAAUJZh5lGQBDAQAWAAUJZh5lGQBDAQAuAAQKf04AAhYACAmnIYkKAHgCABYACAmnIYkKAHgCAAAA.Nightsawdy:BAABLgAECn8rAAMZAAgJQRd1XgCGAQAZAAcJThd1XgCGAQAhAAcJFhGNJAB5AQAAAA==.Nightsnake:BAAALgAECgMJAwAAAA==.Niightstorm:BAABLgAECn8pAAMZAAcJQBx0NAAHAgAZAAcJQBx0NAAHAgAhAAQJbBLxPgDNAAAAAA==.Nikwillig:BAAALgAECggJDQAAAA==.Nilveron:BAAALgADCgcJCQAAAA==.Nitélifé:BAAALgADCgMJAwAAAA==.',
Nj='Njörðr:BAAALgAECgYJDAAAAA==.',
No='Nocturnum:BAABLgAFFH8IAAIWAAMJhQ6dKADeAAAWAAMJhQ6dKADeAAABLgAFFAQJFQAFALUaAA==.Noxmortis:BAAALgAFFAMJBAAAAA==.',
Nt='Ntadadarknes:BAAALgAECgIJAwABLgAECggJLQAJAFgMAA==.',
Oo='Ooblidoom:BAAALgAECgEJAQABLgAECgkJUAAmAIITAA==.',
Op='Opalinnas:BAABLgAECn8nAAMJAAkJdhrKFgCNAgAJAAkJdhrKFgCNAgANAAUJeQiiWwCiAAAAAA==.',
Oz='Ozath:BAAALgAECgQJBgAAAA==.',
Pa='Passionfruit:BAAALgAFFAEJAQAAAA==.',
Pe='Peachtea:BAAALgAECgQJEgAAAA==.',
Ph='Phatshaman:BAABLgAECn8UAAIHAAgJbQfGTwDzAAAHAAgJbQfGTwDzAAAAAA==.Phæryll:BAAALgADCgUJBgAAAA==.',
Pi='Pirodeath:BAAALgAECgcJCgAAAA==.',
Pl='Place:BAAALgAECgIJAgAAAA==.',
Po='Poisonclaw:BAAALgAECgIJBAAAAA==.Poprotonix:BAABLgAECn8fAAICAAgJPxZGTQDdAQACAAgJPxZGTQDdAQAAAA==.Pozessedkaos:BAAALgAECgQJBAAAAA==.',
Pr='Praecantrix:BAAALgAECgEJBQAAAA==.Prath:BAAALgADCgEJAQAAAA==.Pray:BAABLgAECn9DAAIoAAkJBCSGAgCNAwAoAAkJBCSGAgCNAwAAAA==.Priestyballz:BAAALgAECgYJBgAAAA==.Prodarkangel:BAABLgAECn8bAAMkAAkJIgnpFgDoAAAkAAkJIgnpFgDoAAAbAAMJaAMBFAFRAAAAAA==.',
Pu='Pubis:BAAALgAECgYJDgAAAA==.Puckllane:BAABLgAECn8aAAICAAkJ5RdiQQAhAgACAAkJ5RdiQQAhAgAAAA==.Punkbeer:BAAALgAECgEJAQAAAA==.Punkin:BAAALgAECgUJCwAAAA==.',
Py='Pyre:BAABLgAECn89AAIoAAkJSQ9LIQDBAQAoAAkJSQ9LIQDBAQABLgADCgUJBQAGAAAAAA==.',
Qu='Quefstank:BAAALgADCgUJCAAAAA==.',
Ra='Rabmaxx:BAABLgAECn8tAAIYAAgJ1w/yHwB1AQAYAAgJ1w/yHwB1AQAAAA==.Radren:BAAALgADCgEJAQAAAA==.Rajinazn:BAAALgAECgYJBgAAAA==.Rattchett:BAAALgAECgYJBgAAAA==.Ravenlight:BAABLgAFFH8FAAICAAQJWA7FTgAMAQACAAQJWA7FTgAMAQAAAA==.Ravenwynnd:BAABLgAECn8mAAIlAAkJuyJmBADSAgAlAAkJuyJmBADSAgAAAA==.Ravix:BAAALgADCgQJBAAAAA==.Raynelock:BAABLgAECn8wAAMkAAkJgRD+CgCOAQAkAAkJgRD+CgCOAQAbAAIJtQcZCQFKAAAAAA==.Raynman:BAABLgAECn9DAAIeAAkJdxWDJQApAgAeAAkJdxWDJQApAgAAAA==.Razgriz:BAAALgAECgEJAQAAAA==.Razix:BAABLgAECn8zAAQUAAkJfxSmHwDZAQAUAAkJfxSmHwDZAQAmAAYJ6wmtGACOAAATAAMJYwclPACJAAAAAA==.',
Re='Realist:BAAALgAECgMJBAAAAA==.Refrigtuitor:BAACLgAFFH8fAAMFAAUJrQ4yYAArAQAFAAUJrQ4yYAArAQApAAIJuAK3BQBjAAAuAAQKfz8ABAUACQmEHzQgAJsCAAUACQmEHzQgAJsCAAwABQmDCGQOAN0AACkAAQk8EAUTADYAAAAA.Reija:BAAALgAECgEJAgAAAA==.Repentance:BAAALgADCgEJAQABLgAECgkJMwAfAOIXAA==.Revealed:BAAALgADCgEJAQAAAA==.Reyeda:BAAALgADCgUJBQAAAA==.Rezzarn:BAAALgAECgEJAQAAAA==.',
Rh='Rhun:BAAALgAECgYJCQAAAA==.Rhyzer:BAABLgAECn8rAAMSAAcJCR+nGAAnAgASAAcJCR+nGAAnAgAlAAEJJQ1bRQAuAAAAAA==.',
Ri='Rileyksufan:BAABLgAECn8VAAIZAAkJhg66fABBAQAZAAkJhg66fABBAQAAAA==.Rinas:BAACLgAFFH8FAAIYAAIJpxfGHwCSAAAYAAIJpxfGHwCSAAAuAAQKfzYAAxgACQm4ImADAB4DABgACQm4ImADAB4DAAsAAgmfDf0PATUAAAAA.Rivendell:BAAALgAECgQJBgAAAA==.Rivenlynn:BAAALgADCgEJAQAAAA==.',
Ru='Rubioxis:BAAALgADCgYJBgAAAA==.',
Ry='Rymarri:BAAALgADCgkJCQAAAA==.',
Sa='Sabazia:BAACLgAFFH8MAAIjAAMJMhsdHwDpAAAjAAMJMhsdHwDpAAAuAAQKfzsAAiMACQkXIIQHAKACACMACQkXIIQHAKACAAAA.Sacrificer:BAAALgAECgMJAwAAAA==.Sairalindë:BAABLgAECn8fAAMZAAgJdwdQeABKAQAZAAgJdwdQeABKAQAgAAMJpAA3hgA2AAAAAA==.Saleath:BAAALgAECgEJAwAAAA==.Salios:BAABLgAFFH8NAAIbAAQJNB6wFwAzAQAbAAQJNB6wFwAzAQAAAA==.Sallydisco:BAAALgAECgMJAwABLgAFFAQJCgADAN8hAA==.Sanctifier:BAAALgAECgQJDQAAAA==.Saraneth:BAAALgAECgEJAQABLgAECgkJMAAVAI4lAA==.',
Sc='Scandrel:BAAALgAECgQJBAABLgAFFAUJFwAEAPsgAA==.Scrept:BAAALgAFFAEJAQAAAA==.Scynix:BAEBLgAECn8pAAMUAAkJdRheGgACAgAUAAkJdRheGgACAgATAAEJsgFhTgAiAAAAAA==.',
Se='Sedaline:BAAALgAECgQJBgAAAA==.Sephie:BAAALgADCgQJAQAAAQ==.Serenas:BAAALgAECgQJBAABLgAFFAEJAQAGAAAAAA==.Serenilock:BAAALgADCgMJAwAAAA==.Serfdog:BAAALgADCgcJDAAAAA==.Servoker:BAACLgAFFH8TAAITAAYJXxtkEACIAQATAAYJXxtkEACIAQAuAAQKfyUAAxQACAnbICEKANQCABQACAnbICEKANQCABMABwkkGrwVAPABAAAA.Setani:BAAALgADCgIJAgAAAA==.',
Sh='Shabzkaw:BAAALgADCgUJBQAAAA==.Shabzyt:BAAALgADCgQJBAAAAA==.Shaddows:BAAALgAECggJCAAAAA==.Shaienne:BAAALgAECgMJAwAAAA==.Shambussy:BAAALgAECgEJAQAAAA==.Shamfore:BAAALgADCgEJAQAAAA==.Shamrockshak:BAACLgAFFH8GAAIeAAIJKSb2QADbAAAeAAIJKSb2QADbAAAuAAQKfyEAAh4ABgkDI+kgAEYCAB4ABgkDI+kgAEYCAAAA.Shaze:BAAALgADCggJEAAAAA==.Shenuton:BAABLgAECn8VAAICAAgJXgiHowAvAQACAAgJXgiHowAvAQAAAA==.Shieldinterd:BAAALgAECgMJAgABLgAECgcJHgALAKIVAA==.Shiftkicker:BAAALgADCgMJAwAAAA==.Shocktherapy:BAAALgAECgEJAQAAAA==.Shockthêràpy:BAACLgAFFH8JAAIeAAMJjwzeWQCTAAAeAAMJjwzeWQCTAAAuAAQKfzAABB4ACQlbGG0nAPMBAB4ACQlbGG0nAPMBAAcAAwkWF4BoAKkAAB8AAQlPCkYrADgAAAAA.Shoes:BAABLgAECn89AAQhAAkJTSWFAgAfAwAhAAkJxiOFAgAfAwAgAAgJIx/cDQDVAgAZAAgJ9SLOJwA8AgAAAA==.Shoresy:BAAALgAECgEJAQAAAA==.Shtdruid:BAAALgAECgcJDAAAAA==.Shyanni:BAAALgADCgMJAwAAAA==.Shöçkér:BAAALgAECgcJEwAAAA==.',
Si='Siaana:BAAALgADCgUJBQABLgAFFAMJDAAjADIbAA==.Sibearian:BAABLgAECn8fAAQOAAgJ6BjBEQDNAQAOAAgJ6BjBEQDNAQAPAAYJ0ApxJgDSAAANAAIJPwSEdQBNAAAAAA==.Simi:BAACLgAFFH8QAAIZAAQJ5xRUPAAuAQAZAAQJ5xRUPAAuAQAuAAQKfykAAhkACQmYGb4mAEECABkACQmYGb4mAEECAAAA.',
Sk='Skrubzz:BAABLgAECn8ZAAMDAAgJIQbpIAA4AQADAAgJIQbpIAA4AQASAAQJzgKHhwChAAAAAA==.Skôrn:BAABLgAECn8wAAIFAAcJLQ+5mABEAQAFAAcJLQ+5mABEAQAAAA==.',
Sl='Sloppynachos:BAABLgAECn8pAAIWAAgJRhdmGgAvAgAWAAgJRhdmGgAvAgAAAA==.Slyman:BAAALgADCgUJBQABLgAECgYJBwAGAAAAAA==.',
Sm='Smithnwesson:BAAALgAECgIJAgAAAA==.Smokesçreen:BAACLgAFFH8PAAIYAAQJpRMuEAAfAQAYAAQJpRMuEAAfAQAuAAQKf0UAAxgACQkEIWgFAOgCABgACQkEIWgFAOgCAAsABQm6BWXSAIkAAAAA.',
Sn='Snowhoof:BAAALgADCgUJBQAAAA==.',
So='Soccerqt:BAAALgAECgYJBgAAAA==.Sogerä:BAABLgAECn8XAAITAAgJIQUfHwD5AAATAAgJIQUfHwD5AAAAAA==.Soonerpride:BAABLgAECn8cAAICAAgJBCMLLABOAgACAAgJBCMLLABOAgAAAA==.Sorinmarkov:BAAALgAFFAIJAgAAAA==.Source:BAAALgAECgUJCAAAAA==.',
Sp='Spearminttea:BAAALgAECgcJCwAAAA==.Spellbreakr:BAAALgAECgQJBwAAAA==.Spellumgud:BAAALgAECgQJBgAAAA==.Spinturnum:BAAALgAECgIJAgABLgAFFAQJFQAFALUaAA==.',
Sq='Squiby:BAABLgAECn84AAMXAAkJoCK7BgDlAgAXAAkJoCK7BgDlAgAIAAIJmRX+ZwCNAAAAAA==.Squizzy:BAAALgAECgEJAQAAAA==.',
St='Stabfore:BAABLgAECn8lAAMWAAkJ0hTSDwArAgAWAAkJ0hTSDwArAgAcAAEJJgQOLAAlAAAAAA==.Standaside:BAAALgAECgIJBAAAAA==.Steellidan:BAAALgADCgEJAQAAAA==.Stinky:BAABLgAECn8XAAIdAAgJkQkyDgApAQAdAAgJkQkyDgApAQAAAA==.Stix:BAACLgAFFH8QAAIWAAQJCh7WEwBlAQAWAAQJCh7WEwBlAQAuAAQKfy0AAxYACQl6HOQMAFUCABYACQl6HOQMAFUCAB0ABAmnFQ4UAMsAAAAA.Stoya:BAAALgAECgYJCgABLgAECgkJMAAVAI4lAA==.Stuef:BAABLgAECn82AAIHAAkJGyFUCgC3AgAHAAkJGyFUCgC3AgAAAA==.Stuefagos:BAAALgAECgQJBwAAAA==.Stuefester:BAABLgAECn8gAAMEAAkJNiDPHwCIAgAEAAkJNiDPHwCIAgAjAAcJ4Ql9MwDJAAAAAA==.Stueflare:BAAALgAECggJEAAAAA==.Stueflip:BAAALgADCgIJAgAAAA==.Stunsturds:BAABLgAECn8dAAMKAAYJQiBQHQApAgAKAAYJQiBQHQApAgAQAAEJ2AF+mQAaAAABLgAECgcJHgALAKIVAA==.Stäirs:BAABLgAECn9CAAISAAkJ5B0eDwCBAgASAAkJ5B0eDwCBAgAAAA==.',
Su='Summerlily:BAAALgADCgYJBgAAAA==.',
Sy='Sylaria:BAAALgAECgUJCwAAAA==.Syreline:BAAALgAECgEJAgAAAA==.',
['Sá']='Sáble:BAACLgAFFH8FAAIBAAMJDAKwEgBgAAABAAMJDAKwEgBgAAAuAAQKfzAAAwEACQn6CfsdACEBAAIACAnNCGalACwBAAEACQlNCPsdACEBAAAA.',
['Sí']='Síñ:BAAALgAECgIJAgABLgAECggJIgAbAFIaAA==.',
['Sî']='Sîn:BAAALgADCgEJAQABLgAECggJIgAbAFIaAA==.',
['Sï']='Sïn:BAABLgAECn8iAAIbAAgJUhorPADpAQAbAAgJUhorPADpAQAAAA==.',
Ta='Taereachye:BAACLgAFFH8HAAIVAAMJ3xc7LQDBAAAVAAMJ3xc7LQDBAAAuAAQKfxcAAhUABwk5JAYKANMCABUABwk5JAYKANMCAAEuAAUUBAkIAAoAgBUA.Tailon:BAAALgADCgYJBgAAAA==.Taintedlove:BAAALgADCgYJBgAAAA==.Talenelat:BAAALgADCgcJCwAAAA==.Talikas:BAAALgAECggJEAABLgAECgkJMwALAKcaAA==.Tankin:BAAALgADCgMJAwAAAA==.Tantric:BAAALgAECgIJAgABLgAECggJCQAGAAAAAA==.Tarathiel:BAAALgADCgQJBAAAAA==.Taurne:BAACLgAFFH8WAAIJAAYJNwzDHQBjAQAJAAYJNwzDHQBjAQAuAAQKfx4AAgkABwmzGYEwAOkBAAkABwmzGYEwAOkBAAAA.',
Te='Technique:BAAALgAECgIJBAAAAA==.Teebags:BAAALgADCgEJAQAAAA==.Teknoman:BAACLgAFFH8OAAISAAMJ5xtILwDsAAASAAMJ5xtILwDsAAAuAAQKfzwAAhIACQkIIWUKAL0CABIACQkIIWUKAL0CAAAA.Telmarine:BAAALgAECgMJAwAAAA==.Tempered:BAABLgAECn8YAAMlAAYJMhwpFwCfAQAlAAYJMhwpFwCfAQASAAQJRRstZQDFAAAAAA==.Terlemen:BAAALgAECgUJBQAAAA==.Tetsumi:BAAALgADCgYJCQABLgAECggJDgAGAAAAAA==.',
Th='Thaddeus:BAAALgAECgEJAQABLgAFFAUJEgAGAAAAAQ==.Thaitea:BAAALgAECgUJBgAAAA==.Thal:BAAALgAECgMJAwAAAA==.Thalan:BAAALgADCgEJAQAAAA==.Thalindra:BAABLgAECn8qAAIZAAcJdBzWNwD6AQAZAAcJdBzWNwD6AQAAAA==.Thebigbeast:BAAALgAFFAIJBAABLgAFFAYJGAAbAJoVAA==.Thecurt:BAABLgAECn9BAAIQAAkJnyQ3AgA7AwAQAAkJnyQ3AgA7AwAAAA==.Thedammed:BAAALgADCgEJAQAAAA==.Theholylight:BAAALgAECgYJDQAAAA==.Thehuzz:BAAALgAECggJDAAAAA==.Thermidor:BAABLgAECn8gAAIhAAkJYBV5CQBLAgAhAAkJYBV5CQBLAgAAAA==.Thorsamie:BAAALgAECggJDgAAAA==.Thrasios:BAAALgAECgIJAgAAAA==.Thundercunti:BAAALgADCgYJDAABLgAECggJPgAWALAhAA==.',
Ti='Tiamatt:BAAALgADCgIJBAAAAA==.Ticktock:BAAALgAECgIJAgAAAA==.Timaeus:BAABLgAECn8YAAISAAcJAQL3ggBqAAASAAcJAQL3ggBqAAAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Titanlock:BAAALgAECgUJCQAAAA==.',
Tk='Tkdfath:BAAALgAECggJEgAAAA==.',
To='Torvia:BAAALgAECgUJCwAAAA==.Totemix:BAAALgADCgcJEgAAAA==.Totemsoul:BAAALgAECgEJAwABLgAECgcJCgAGAAAAAA==.',
Tr='Trisinz:BAABLgAECn8lAAINAAgJ0RehHQDYAQANAAgJ0RehHQDYAQAAAA==.Trixa:BAAALgADCgMJAwAAAA==.',
Tu='Tuerto:BAAALgAECgYJEwAAAA==.Turbojohnson:BAAALgAECgQJBgAAAA==.Turk:BAABLgAECn9EAAMLAAkJtRcbJQA3AgALAAkJtRcbJQA3AgAYAAEJCQ/BcwAxAAAAAA==.Turkish:BAABLgAECn9AAAMEAAkJZBraMQA0AgAEAAkJZBraMQA0AgAnAAEJ7gZcPgAnAAAAAA==.Turtledisco:BAACLgAFFH8KAAIDAAQJ3yG1EgAKAQADAAQJ3yG1EgAKAQAuAAQKfycAAgMACQnSH7sDABcDAAMACQnSH7sDABcDAAAA.',
Ty='Tylat:BAAALgADCgEJBQAAAA==.Tyranax:BAACLgAFFH8FAAIoAAIJ1wouPQB9AAAoAAIJ1wouPQB9AAAuAAQKfz0ABCgACQnlGy4KAMsCACgACQneGi4KAMsCAAgABgnVH1IcAPoBABcABwkxEyIyAFEBAAAA.Tyyregade:BAAALgADCgkJCgABLgAECggJDgAGAAAAAA==.',
Uj='Ujimas:BAAALgAECgEJAgAAAA==.',
Us='Us:BAAALgAECggJCQAAAA==.',
Uz='Uzzi:BAAALgAECgEJAQAAAA==.',
Va='Vadose:BAABLgAECn8gAAIbAAcJwQqmgQBXAQAbAAcJwQqmgQBXAQABLgAFFAQJEAAZAOcUAA==.Vales:BAAALgAECgYJCQABLgAFFAMJBQAZAMABAA==.Valsavis:BAABLgAECn8dAAINAAgJkxRIIgCzAQANAAgJkxRIIgCzAQAAAA==.Valytrois:BAABLgAECn8UAAIbAAcJXQmysQD1AAAbAAcJXQmysQD1AAAAAA==.Varinix:BAAALgADCgMJBQAAAA==.',
Ve='Veggiebaha:BAAALgADCgIJAgAAAA==.Veiksla:BAABLgAECn8cAAMTAAgJUge5GgAsAQATAAgJUge5GgAsAQAmAAEJoQOrKgAgAAAAAA==.Velore:BAAALgADCgcJDAAAAA==.Vengerr:BAAALgAECgUJBgAAAA==.Verace:BAAALgAECgcJAQAAAA==.Verradic:BAAALgAECgcJEwABLgAECggJIAAZANINAA==.',
Vi='Vitur:BAABLgAECn9HAAILAAkJ/iDlFACZAgALAAkJ/iDlFACZAgAAAA==.',
Vo='Voidhunter:BAABLgAECn8VAAILAAcJGwrdkwD0AAALAAcJGwrdkwD0AAAAAA==.Voidweaver:BAAALgAECgMJBQAAAA==.Volaine:BAABLgAECn8rAAMbAAcJ3xHycABXAQAbAAYJ3xHycABXAQAaAAIJuhTJOwA3AAAAAA==.Volt:BAABLgAECn8zAAIfAAkJ4hdjCgAQAgAfAAkJ4hdjCgAQAgAAAA==.Volumoso:BAAALgAECgYJBgAAAA==.Volwryn:BAAALgAECgUJCAABLgAECggJCQAGAAAAAA==.',
Vy='Vynarian:BAABLgAECn8rAAIFAAcJIRVZdQCLAQAFAAcJIRVZdQCLAQAAAA==.',
['Vâ']='Vâljean:BAAALgADCgMJAwAAAA==.',
['Vô']='Vôx:BAAALgAECgEJAQABLgAECggJIQARAJEZAA==.',
['Vö']='Vöx:BAAALgAECgEJAQABLgAECggJIQARAJEZAA==.',
Wa='Warbeard:BAABLgAECn8oAAISAAkJ8guLLACgAQASAAkJ8guLLACgAQAAAA==.',
Wi='Wizwizx:BAAALgADCgUJBgAAAA==.',
Wr='Wreckbums:BAABLgAFFH8MAAIEAAMJkR/9iQDxAAAEAAMJkR/9iQDxAAAAAA==.Wreckd:BAABLgAECn8iAAMLAAcJnhhsRQCzAQALAAcJnhhsRQCzAQAYAAIJIgzYcgAqAAAAAA==.',
Wy='Wyth:BAAALgAECgQJBQABLgAECgQJBgAGAAAAAA==.',
Xa='Xanthad:BAAALgADCgEJAQAAAA==.',
Xi='Xitãozinho:BAAALgAECgUJBwAAAA==.',
Xo='Xolair:BAAALgAECgYJDgAAAA==.',
Ya='Yaalia:BAABLgAECn8cAAMCAAcJtAXW1gDnAAACAAcJtAXW1gDnAAAVAAIJZwIKowAiAAAAAA==.Yaan:BAABLgAECn8gAAIHAAgJMQr2RQAYAQAHAAgJMQr2RQAYAQAAAA==.',
Yo='Yoba:BAAALgAECgMJAwAAAA==.Yoshira:BAAALgADCgQJBAAAAA==.',
['Yö']='Yör:BAAALgAECgEJAQAAAA==.',
Za='Zain:BAABLgAECn9GAAQlAAkJNx3NBwB2AgAlAAkJNx3NBwB2AgASAAYJGA5fWQBIAQADAAIJKA3cSABNAAAAAA==.Zandibar:BAABLgAECn8qAAISAAcJWCCDFgA5AgASAAcJWCCDFgA5AgAAAA==.Zaptoasted:BAAALgAECgUJBgAAAA==.Zaroff:BAAALgAECgYJCgAAAA==.',
Ze='Zedadiah:BAAALgADCgEJAQAAAA==.Zelah:BAAALgAECgQJBAAAAA==.Zenessa:BAAALgADCgYJBgAAAA==.',
Zi='Zillah:BAAALgAECgEJAQABLgAECgcJCgAGAAAAAA==.Zinder:BAABLgAECn8oAAIFAAkJsQ7TWwDHAQAFAAkJsQ7TWwDHAQAAAA==.',
Zu='Zuggie:BAABLgAECn8gAAIbAAgJJQbAowD4AAAbAAgJJQbAowD4AAAAAA==.Zugtail:BAAALgAECgYJDgABLgAECggJIAAbACUGAA==.Zurtrinik:BAACLgAFFH8eAAIDAAgJfB8GBAAnAgADAAgJfB8GBAAnAgAuAAQKfyUAAgMACAmZJDwCAE0DAAMACAmZJDwCAE0DAAAA.',
Zy='Zylith:BAAALgAECgYJCgABLgAECgkJMwAfAOIXAA==.',
Zz='Zzonked:BAABLgAECn8pAAMEAAkJCwjojQBHAQAEAAkJzwbojQBHAQAjAAIJ/gtGPwBSAAAAAA==.',
['Zê']='Zêp:BAAALgAECgEJAgAAAA==.',
['Zø']='Zøømies:BAABLgAECn8xAAMLAAkJhhesLwAFAgALAAkJUhesLwAFAgAiAAYJFQ+BFgDvAAAAAA==.',
['Är']='Äréa:BAAALgADCgkJCQAAAA==.',
['Äs']='Äshnärd:BAACLgAFFH8KAAIeAAMJqyNgLAApAQAeAAMJqyNgLAApAQAuAAQKfzQAAh4ACQlUJD8FAFwDAB4ACQlUJD8FAFwDAAAA.',
['Ða']='Ðar:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðoogle:BAABLgAECn8ZAAIHAAcJlRvqKwCTAQAHAAcJlRvqKwCTAQAAAA==.',
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
