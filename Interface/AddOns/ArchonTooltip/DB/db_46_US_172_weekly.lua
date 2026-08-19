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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Paladin-Protection','Paladin-Retribution','Warrior-Protection','Mage-Frost','Unknown-Unknown','Shaman-Elemental','Priest-Holy','Druid-Restoration','Shaman-Restoration','Monk-Mistweaver','DemonHunter-Devourer','Mage-Arcane','Druid-Balance','Druid-Guardian','Druid-Feral','Monk-Brewmaster','Monk-Windwalker','Warrior-Fury','Evoker-Preservation','Evoker-Augmentation','Paladin-Holy','Rogue-Subtlety','Priest-Shadow','DemonHunter-Havoc','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Vengeance','DeathKnight-Blood','Warlock-Destruction','Warrior-Arms','Evoker-Devastation','Priest-Discipline','Mage-Fire',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=46,date='2026-08-18',data={Ac='Acedk:BAACLgAFFH8dAAMBAAYJnx/kQgBvAQABAAYJnx/kQgBvAQACAAEJMgUwIAA2AAAuAAQKfyAAAgEACQkwI74YALICAAEACQkwI74YALICAAAA.',
Ad='Adrador:BAABLgAECn8+AAMDAAkJ2iSrAQAsAwADAAkJ2iSrAQAsAwAEAAMJ8hVLVABIAAAAAA==.Adrenaline:BAACLgAFFH8jAAIFAAcJVBshCgCOAQAFAAcJVBshCgCOAQAuAAQKfz4AAgUACQkdJRgDAAkDAAUACQkdJRgDAAkDAAAA.',
Ae='Aelik:BAACLgAFFH8SAAIBAAMJ+hzkQgDXAAABAAMJ+hzkQgDXAAAuAAQKfykAAgEACAnwHb84ABwCAAEACAnwHb84ABwCAAAA.Aeolian:BAAALgAECgUJBQAAAA==.',
Ah='Ahkimbo:BAAALgADCgUJBQAAAA==.',
Ai='Airolanah:BAAALgAECgUJBQAAAA==.',
Al='Alayssa:BAABLgAECn8tAAIGAAkJXSCxHACwAgAGAAkJXSCxHACwAgAAAA==.Alda:BAAALgAECgQJAgAAAA==.Allarius:BAAALgAECgEJAQAAAA==.Allioops:BAAALgADCgUJBQABLgAECgMJBAAHAAAAAA==.Alnima:BAACLgAFFH8GAAIIAAMJ/QGWQgB/AAAIAAMJ/QGWQgB/AAAuAAQKfxkAAggACAnOCLk5AGgBAAgACAnOCLk5AGgBAAAA.Alteera:BAAALgAECgEJAQABLgAECggJEQAHAAAAAA==.',
Am='Amilee:BAAALgAECgcJEgAAAA==.Amishhunter:BAAALgADCgEJAQAAAA==.Amoondai:BAACLgAFFH8eAAIJAAQJDyHGBwBKAQAJAAQJDyHGBwBKAQAuAAQKfy8AAgkACQmjIhADAGQDAAkACQmjIhADAGQDAAAA.Amoondrin:BAABLgAECn8zAAIKAAkJLwnVTQBXAQAKAAkJLwnVTQBXAQAAAA==.Amplifier:BAAALgADCgUJBQAAAA==.',
An='Analiya:BAAALgADCgMJBAAAAA==.Anghkooey:BAAALgAECgUJBwAAAA==.Antichurch:BAAALgADCgEJAQAAAA==.Antisnow:BAAALgAECgIJBQABLgAECgcJCgAHAAAAAA==.Antregon:BAAALgADCgQJBwAAAA==.',
Ar='Araviin:BAABLgAFFH8XAAIGAAQJURI3KwAjAQAGAAQJURI3KwAjAQAAAA==.Arazen:BAAALgAECgIJAwAAAA==.Arcillias:BAAALgAECgEJAQABLgAFFAYJFwALANIRAA==.Aristrina:BAAALgAECgIJAgAAAA==.Arkride:BAAALgAECgEJAQAAAA==.Arlean:BAAALgAECgIJAgAAAA==.Arnadaz:BAAALgADCgEJAQABLgAFFAQJCAAMAIAVAA==.Arrogance:BAAALgADCgcJBwABLgAECggJCQAHAAAAAA==.Arthia:BAAALgAECgQJEAAAAA==.Arvidpally:BAAALgAECgkJEgAAAA==.',
As='Ashmehameha:BAAALgADCgQJAgABLgAFFAMJCAABANoTAA==.Asinn:BAAALgAECgEJAQAAAA==.Asoosimov:BAAALgADCgEJAQAAAA==.',
At='Atredes:BAABLgAFFH8MAAINAAMJsQlqOACVAAANAAMJsQlqOACVAAAAAA==.Attima:BAABLgAECn9BAAIOAAkJWBHOAwDSAQAOAAkJWBHOAwDSAQAAAA==.',
Au='Aubriana:BAAALgADCgQJBAAAAA==.Aurøra:BAAALgADCgMJAwAAAA==.Auspex:BAABLgAECn8rAAMPAAkJxwnfNgA6AQAPAAkJ6QffNgA6AQAQAAkJMAjVLwDtAAAAAA==.',
Av='Avaryn:BAACLgAFFH8eAAIKAAcJQw44IwBAAQAKAAcJQw44IwBAAQAuAAQKfz0AAgoACQmZIUQJACUDAAoACQmZIUQJACUDAAAA.',
Ax='Aximlii:BAAALgAECgIJAgAAAA==.',
Az='Azron:BAAALgAECgcJCAABLgAECggJDgAHAAAAAA==.',
Ba='Baako:BAAALgADCgEJAgAAAA==.Babavoss:BAAALgAECgkJAQAAAA==.Badarack:BAAALgAECgcJEwABLgAFFAMJCQAQAOohAA==.Badaracka:BAACLgAFFH8JAAMQAAMJ6iFbDQAlAQAQAAMJ6iFbDQAlAQARAAMJ1ByMBAAEAQAuAAQKfz4AAxAACQl7JTUBAFADABAACQkMJTUBAFADABEACQlyJE0AAEQDAAAA.Badarackie:BAABLgAECn9DAAMSAAkJSCG2BwC6AgASAAkJSCG2BwC6AgATAAkJDhVsGQDmAQABLgAFFAMJCQAQAOohAA==.Badash:BAABLgAECn8rAAMFAAgJBhueEADeAQAFAAgJBhueEADeAQAUAAEJMQSurQAvAAABLgAFFAMJCAABANoTAA==.Bahamuth:BAABLgAECn9DAAIEAAkJIB15IwB3AgAEAAkJIB15IwB3AgAAAA==.Bakshi:BAAALgAECgEJBAAAAA==.Balder:BAAALgAFFAMJBwABLgAFFAYJHgAHAAAAAQ==.Banký:BAAALgAECgEJAQABLgAECgEJAwAHAAAAAA==.Barbattos:BAACLgAFFH8eAAIVAAcJXxjmEQB3AQAVAAcJXxjmEQB3AQAuAAQKfzoAAxUACQkOJLcCADUDABUACQkOJLcCADUDABYAAgm4HNR+AGEAAAAA.Barnabas:BAAALgADCgYJDAABLgAFFAYJFwALANIRAA==.Barragon:BAABLgAECn8VAAIXAAcJ5g8SNwByAQAXAAcJ5g8SNwByAQAAAA==.',
Bd='Bdyrk:BAAALgAECgYJBgABLgAFFAMJCQAQAOohAA==.',
Be='Bealzeboss:BAAALgAECgYJBgAAAA==.Beans:BAAALgAECgQJBAAAAA==.Bearymanalow:BAAALgAECgMJBQAAAA==.Belfore:BAAALgAECgEJAQABLgAECgkJJgAYACgVAA==.Bestea:BAAALgAECgEJAQAAAA==.Bethollbrew:BAAALgAECgYJDwAAAA==.Bexley:BAABLgAECn8tAAIDAAkJChoUCQBCAgADAAkJChoUCQBCAgAAAA==.',
Bi='Biggerbunny:BAACLgAFFH8NAAIZAAMJrwgqKQC2AAAZAAMJrwgqKQC2AAAuAAQKfzAAAhkACAmEFTcjAK8BABkACAmEFTcjAK8BAAAA.Binkter:BAAALgAECgIJBQABLgAECgIJAgAHAAAAAA==.',
Bl='Blackjax:BAAALgADCgEJAQAAAA==.Blacklok:BAAALgAECgUJEQABLgAECgkJNAAaAEElAA==.Blanne:BAAALgAECgEJAQAAAA==.Blargle:BAABLgAECn8uAAIbAAgJKQ9+XQCNAQAbAAgJKQ9+XQCNAQAAAA==.Blegh:BAABLgAFFH8GAAIEAAMJIgoARgCOAAAEAAMJIgoARgCOAAABLgAFFAcJEAAbADQZAA==.Blessedcross:BAAALgAECgMJBAAAAA==.Bleubahlz:BAAALgADCgcJBwABLgAECgMJAwAHAAAAAA==.Blinx:BAAALgAECgQJBwABLgAECggJDgAHAAAAAA==.Bloodrake:BAABLgAECn87AAIbAAkJHB6mDQDRAgAbAAkJHB6mDQDRAgAAAA==.Bloodreyne:BAAALgADCgEJAgAAAA==.Bloodseekr:BAAALgADCgcJEwAAAA==.Blueray:BAAALgAECgYJCAAAAA==.',
Bo='Boahan:BAAALgAECgMJBQABLgAECgUJCAAHAAAAAA==.Boggart:BAAALgAECgEJAQABLgAECgUJCAAHAAAAAA==.Bohein:BAAALgADCgEJAQAAAA==.Bolus:BAAALgAECgQJCAAAAA==.Botany:BAAALgAECgcJBwAAAA==.Bownafiedba:BAAALgADCgUJBQAAAA==.',
Br='Braneour:BAACLgAFFH8FAAMEAAMJhwW+QgCYAAAEAAMJhwW+QgCYAAAXAAIJOQQiQgBcAAAuAAQKfzkAAxcACQnAGlgMAMkCABcACQnAGlgMAMkCAAQAAwlUERUtAYMAAAAA.Brassballz:BAAALgAECgkJCQAAAA==.Browel:BAABLgAECn8aAAMcAAcJWBj4CAC3AQAcAAYJ3Rj4CAC3AQAdAAYJYQ5/nQADAQAAAA==.Bruen:BAAALgAECgYJBwAAAA==.Bryci:BAAALgAECgcJEAAAAA==.',
Bu='Bubbloseven:BAABLgAECn8UAAMXAAgJGhGEKgC7AQAXAAgJGhGEKgC7AQADAAQJABsVHQAsAQAAAA==.Budank:BAAALgADCgMJAwAAAA==.Bumm:BAABLgAECn8eAAIEAAYJ1xGrIgDUAAAEAAYJ1xGrIgDUAAAAAA==.Bustybubbles:BAAALgADCgYJBgAAAA==.',
Bz='Bzspy:BAABLgAFFH8PAAIUAAMJ3hR4IwCcAAAUAAMJ3hR4IwCcAAAAAA==.',
['Bö']='Bösergeist:BAAALgAECgMJAwAAAA==.',
Ca='Caalin:BAAALgAECgEJAgAAAA==.Cabooselul:BAAALgAECgQJCwAAAA==.Calibre:BAABLgAECn8eAAINAAcJohXoaABUAQANAAcJohXoaABUAQAAAA==.Calyptus:BAABLgAECn8fAAIdAAYJhApkrgDnAAAdAAYJhApkrgDnAAAAAA==.Caprious:BAACLgAFFH8bAAIBAAUJwxkoUABRAQABAAUJwxkoUABRAQAuAAQKfzYAAgEACQnjJGsKABwDAAEACQnjJGsKABwDAAAA.Capylaura:BAABLgAECn8bAAIbAAcJwAocggA7AQAbAAcJwAocggA7AQAAAA==.Caratine:BAABLgAECn8uAAINAAkJ4A6FCgBUAQANAAkJ4A6FCgBUAQAAAA==.Cassandrah:BAAALgAECgcJBwABLgAECgkJMgAeABkkAA==.Cassandrar:BAABLgAECn8yAAQeAAkJGSQIAQA5AwAeAAgJMiQIAQA5AwAYAAYJtiBlHwCbAQAfAAEJphSJIwA6AAAAAA==.Cassandraw:BAAALgAECgYJBgABLgAECgkJMgAeABkkAA==.Cat:BAAALgADCgUJBQAAAA==.Cattlelac:BAAALgADCgUJCAAAAA==.Caymus:BAABLgAECn9LAAIKAAkJ5Q7oBgB6AQAKAAkJ5Q7oBgB6AQAAAA==.',
Ce='Celìa:BAABLgAECn85AAIbAAkJkwmJGwAGAQAbAAkJkwmJGwAGAQAAAA==.Cess:BAAALgAECgEJAgAAAA==.Cevíche:BAAALgAECgQJBAAAAA==.',
Ch='Chaoticone:BAAALgADCgYJBgAAAA==.Chema:BAABLgAFFH8IAAIMAAQJgBVzLQAIAQAMAAQJgBVzLQAIAQAAAA==.Chestylarue:BAAALgAECgEJAQABLgAECggJFQAbAIgOAA==.Chfgaribaldi:BAAALgAECgEJAQAAAA==.Chifore:BAAALgAECgUJBgAAAA==.Chills:BAAALgAECgcJEQAAAA==.Chillymage:BAAALgADCgYJBgAAAA==.Chosen:BAABLgAECn8YAAIEAAYJRBdtYgC+AQAEAAYJRBdtYgC+AQABLgAFFAYJHQABAJ8fAA==.Chpchop:BAAALgADCgIJAgAAAA==.Christy:BAAALgAECgQJAgAAAA==.Chugg:BAABLgAECn8fAAILAAkJwgjyWgBNAQALAAkJwgjyWgBNAQAAAA==.',
Ci='Ciaphus:BAABLgAECn8nAAIEAAkJ0hRnRwDwAQAEAAkJ0hRnRwDwAQAAAA==.Cinnamonster:BAAALgAECgcJDgAAAA==.',
Cl='Clogs:BAAALgAECgcJBwAAAA==.',
Co='Coffeedemon:BAAALgADCgEJAQAAAA==.Coldslappins:BAABLgAECn8lAAIGAAgJRxXpDwBqAQAGAAgJRxXpDwBqAQAAAA==.Contagion:BAAALgAECgYJBQAAAA==.Convoke:BAABLgAECn8eAAIPAAcJDSArFgBeAgAPAAcJDSArFgBeAgAAAA==.Coragrr:BAAALgAECgcJCgAAAA==.',
Cr='Crazycrocey:BAAALgAECgYJCAAAAA==.Cryptonight:BAAALgAECgQJBAAAAA==.',
Cu='Cubcake:BAAALgADCggJCAAAAA==.Curtastrophe:BAABLgAECn89AAIGAAkJHx3jJwB7AgAGAAkJHx3jJwB7AgAAAA==.Curticus:BAAALgADCgQJBAAAAA==.Curtissax:BAAALgAECgIJAgAAAA==.Curtnought:BAAALgADCgIJAgAAAA==.',
['Cé']='Cérnùnnøs:BAAALgAECgEJAQAAAA==.',
Da='Daelanos:BAABLgAECn8dAAIUAAkJGxagMACLAQAUAAkJGxagMACLAQAAAA==.Dalinar:BAAALgAECgcJDQAAAA==.Damson:BAAALgADCgcJDgAAAA==.Daranger:BAAALgADCgEJAQAAAA==.Darska:BAAALgADCgYJBgABLgAECggJDgAHAAAAAA==.',
De='Deadtauren:BAAALgADCgYJDwAAAA==.Deathdemon:BAAALgAECgYJDgAAAA==.Deathfue:BAAALgAECgIJBAABLgAECgcJCgAHAAAAAA==.Deathisreal:BAAALgADCgMJAwABLgAECgYJDwAHAAAAAA==.Deathoof:BAAALgAFFAIJAgAAAA==.Degeneracy:BAAALgAECgcJCwAAAA==.Demon:BAAALgAECgkJDgAAAA==.Demonblaze:BAABLgAFFH8GAAIaAAIJxhhnFACFAAAaAAIJxhhnFACFAAAAAA==.Demonilla:BAAALgAECggJEwAAAA==.Dempkiston:BAAALgAECgYJCwAAAA==.Denogan:BAAALgAECggJDgAAAA==.Deservis:BAAALgAECgUJDgABLgAECgcJHgANAKIVAA==.Destro:BAABLgAECn8pAAIdAAkJ7w+uSQC9AQAdAAkJ7w+uSQC9AQABLgAECgkJMwAgAOIXAA==.Dethadin:BAAALgADCgcJBwAAAA==.',
Di='Dilaudyd:BAAALgAECgUJBgAAAA==.Dirteemike:BAAALgADCgMJAwAAAA==.Disbeleaf:BAACLgAFFH8FAAMPAAMJzhIGOwCLAAAPAAIJJBYGOwCLAAAKAAIJegsZWgBmAAAuAAQKfxUAAwoABgkBGRg6AK0BAAoABgkBGRg6AK0BAA8ABQlRIPctAGsBAAAA.Discoflurry:BAAALgAECgcJDgABLgAFFAQJCgAFAN8hAA==.Dizzyfist:BAAALgAECgYJCQABLgAECggJDgAHAAAAAA==.',
Dn='Dntblink:BAAALgAECgEJAQAAAA==.',
Do='Dogaz:BAAALgAECgYJBwAAAA==.Dogsoldier:BAAALgADCgIJAgAAAA==.Dollyinho:BAAALgAECgYJBwAAAA==.Donori:BAAALgAECgQJDQAAAA==.Dorcath:BAAALgAFFAIJBAABLgAECgkJHQAUABsWAA==.',
Dr='Dragan:BAAALgAECgQJEgAAAA==.Dragapult:BAAALgAECggJAwAAAA==.Dragonias:BAABLgAECn8mAAIhAAkJwhewCgDCAQAhAAkJwhewCgDCAQAAAA==.Draino:BAAALgADCgUJBQAAAA==.Drakthorn:BAAALgAECgcJDAAAAA==.Dreselwings:BAAALgAECggJCAABLgAFFAgJHgAbAJsfAA==.Drinny:BAABLgAECn8yAAIJAAkJtwjDMgA+AQAJAAkJtwjDMgA+AQAAAA==.Drqueenisin:BAABLgAECn8UAAIKAAYJSwo5DQDYAAAKAAYJSwo5DQDYAAAAAA==.Druido:BAAALgAECgQJAwAAAA==.',
Du='Duerek:BAAALgAECgUJBgAAAA==.',
['Dè']='Dèaths:BAAALgAECgYJEAAAAA==.',
['Dí']='Dínglebery:BAAALgAECgYJCAAAAA==.',
Ea='Earthangel:BAABLgAECn83AAIJAAkJJxdNBQCnAQAJAAkJJxdNBQCnAQAAAA==.',
Ed='Edlarel:BAAALgADCgQJBAABLgAECggJCQAHAAAAAA==.',
Ef='Efon:BAAALgAECgYJBgABLgAECgkJLQAGAF0gAA==.',
Ei='Eine:BAABLgAECn9HAAIbAAkJsxVAMgATAgAbAAkJsxVAMgATAgAAAA==.Eitherwind:BAABLgAECn8XAAQiAAYJ2h/YHwCdAQAiAAYJ2h/YHwCdAQAbAAIJchT/qwBsAAAhAAIJNxOYOwA0AAABLgAECggJDgAHAAAAAA==.Eivore:BAAALgAECgcJBwAAAA==.',
Ek='Ekoh:BAAALgAECgEJAgAAAA==.',
El='Eldergreen:BAABLgAECn8vAAMKAAkJQQuCVAA+AQAKAAkJQQuCVAA+AQAPAAIJkwrxeQBSAAAAAA==.Eldest:BAAALgADCgUJBQAAAA==.Elfwine:BAABLgAECn80AAIZAAkJUw/vCQAmAQAZAAkJUw/vCQAmAQAAAA==.Elindria:BAABLgAECn80AAQaAAkJQSXWAwAUAwAaAAkJHiXWAwAUAwAjAAkJhiElAgDrAgANAAUJMxu6ewA0AQAAAA==.Eliora:BAAALgADCgkJCQAAAA==.Elitist:BAABLgAFFH8PAAIBAAQJaxXuJwA1AQABAAQJaxXuJwA1AQAAAA==.Elminstir:BAABLgAECn8XAAIGAAgJnhYCZgCxAQAGAAgJnhYCZgCxAQAAAA==.Elyissia:BAAALgAECgcJDQAAAA==.Elynisa:BAAALgAECgEJAQAAAA==.Elysian:BAABLgAECn84AAQMAAkJcxwVDADYAgAMAAkJcxwVDADYAgATAAgJaB8iEABKAgASAAIJyh/pVwCpAAAAAA==.',
Em='Emogo:BAAALgADCgUJCQAAAA==.',
En='Enforcer:BAAALgADCgQJBgAAAA==.Enlightened:BAAALgAECgQJCwAAAA==.Enseral:BAABLgAECn8WAAIWAAcJMQpXSwD/AAAWAAcJMQpXSwD/AAAAAA==.',
Eo='Eotech:BAAALgAECgQJBAAAAA==.',
Er='Erastas:BAAALgADCggJDwAAAA==.Erendora:BAABLgAECn8iAAIKAAkJdg1YPwCUAQAKAAkJdg1YPwCUAQAAAA==.Erets:BAAALgAECgEJAQAAAA==.Eridar:BAAALgAECgYJBgAAAA==.Erizhal:BAAALgAECgUJEAAAAA==.Erodora:BAAALgADCgEJAQAAAA==.',
Es='Esabel:BAABLgAECn8VAAMiAAkJThU3EwANAgAiAAkJOhU3EwANAgAbAAQJrxWlkgAaAQABLgAECgkJLQAGAF0gAA==.',
Ev='Eva:BAAALgAECgEJAgAAAA==.Eviae:BAABLgAECn84AAIkAAkJmwmKCAD9AAAkAAkJmwmKCAD9AAAAAA==.Evillure:BAABLgAECn8lAAMBAAkJ8hNqQgD7AQABAAkJ8hNqQgD7AQAkAAUJkgw3PACgAAAAAA==.',
Ez='Ezera:BAAALgAECgUJBQAAAA==.',
Fa='Falan:BAABLgAECn8xAAILAAkJqhKGLgD8AQALAAkJqhKGLgD8AQAAAA==.Faputa:BAAALgAECgMJAwAAAA==.Fatherjoe:BAAALgADCgYJBgAAAA==.Fayze:BAEBLgAECn8XAAMeAAcJfiMSBQAwAgAeAAcJSCMSBQAwAgAYAAIJBiGeQQC+AAABLgAFFAIJBAAHAAAAAA==.',
Fe='Fedor:BAAALgAECgkJBQAAAA==.Felbreaker:BAAALgAECgYJEAAAAA==.Felfore:BAAALgADCgcJBwAAAA==.Fentril:BAAALgADCgIJAgABLgAECggJDgAHAAAAAA==.Feår:BAABLgAECn8fAAMdAAkJjQwjfwA7AQAdAAgJuAojfwA7AQAlAAMJ3Q8RSwCMAAAAAA==.',
Fi='Fillianora:BAAALgAECgIJAgAAAA==.Finley:BAAALgAECgQJBQAAAA==.Fircane:BAAALgADCgQJBAAAAA==.Firiel:BAAALgAECgMJAwAAAA==.Fizzle:BAAALgADCggJCAABLgAECgkJKAAKAHYaAA==.',
Fl='Flane:BAAALgAFFAEJBAABLgAFFAkJIwAFABwdAA==.Flem:BAAALgAECgMJBAAAAA==.Flexdruid:BAABLgAECn8cAAMRAAYJFg0mMQCcAAARAAYJLgsmMQCcAAAQAAQJ4wheSwB9AAAAAA==.',
Fo='Foog:BAABLgAECn8YAAMUAAgJwxj+MACJAQAUAAYJoBr+MACJAQAmAAYJGRMdKwAfAQAAAA==.',
Fr='Fragil:BAACLgAFFH8HAAIYAAIJnh00GQC2AAAYAAIJnh00GQC2AAAuAAQKf0sAAhgACQmnIoMBAG0CABgACQmnIoMBAG0CAAAA.Fritter:BAAALgAECgMJAwAAAA==.Frostmane:BAACLgAFFH8jAAMBAAgJLR+GJADbAQABAAcJLR+GJADbAQAkAAMJIxNAGwCDAAAuAAQKfzsAAwEACQlWJeEFAEoDAAEACQlWJeEFAEoDACQABwn+HMANADECAAAA.Frostynug:BAAALgADCgYJBgAAAA==.',
Fu='Fudge:BAAALgADCgYJBgAAAA==.Furbyn:BAAALgADCgIJAgAAAA==.',
Ga='Galena:BAABLgAECn83AAMKAAkJLhWJBADjAQAKAAkJLhWJBADjAQAPAAEJghGIJgAyAAAAAA==.Gallamier:BAAALgADCgEJAQAAAA==.Gamerinator:BAAALgADCgcJCwAAAA==.Gangreene:BAAALgADCgYJCgAAAA==.Gapesmoothie:BAAALgADCgYJBgAAAA==.Garoanna:BAAALgAECgYJBgABLgAFFAIJBQAeAHcDAA==.',
Ge='Geshalt:BAAALgAECgEJAQAAAA==.Geshtal:BAAALgAECgQJDAAAAA==.Gets:BAAALgADCgMJBAAAAA==.',
Gi='Girion:BAABLgAECn84AAIDAAkJew7OBgASAQADAAkJew7OBgASAQAAAA==.Girliepop:BAAALgAECgEJAQAAAA==.',
Gl='Glaiven:BAECLgAFFH8fAAMNAAcJfhNqOgA7AQANAAcJfhNqOgA7AQAjAAMJuA+bDgBhAAAuAAQKfy8AAyMACQmVIY0EAHQCAA0ACQkrH6EdAKACACMACQmXHI0EAHQCAAAA.Glorfinndel:BAAALgADCgQJBAAAAA==.Glyr:BAAALgAECgcJBwAAAA==.',
Gn='Gnopower:BAAALgAECgYJCgAAAA==.',
Go='Gorgrin:BAABLgAECn8gAAIcAAkJdhURAwBqAQAcAAkJdhURAwBqAQAAAA==.Goude:BAAALgADCgMJBAAAAA==.',
Gr='Gredic:BAEALgAECgQJBQABLgAFFAcJHwANAH4TAA==.Greenback:BAAALgADCgYJCwAAAA==.Greentotes:BAEBLgAECn8yAAMWAAkJ7x9dCADRAgAWAAkJ7x9dCADRAgAnAAUJTxOYEgDhAAABLgAFFAUJBQAMAIEBAA==.',
Gu='Gunter:BAAALgAECgMJAwABLgAFFAYJHQABAJ8fAA==.Gura:BAAALgADCgEJAQAAAA==.Gurnee:BAAALgADCgcJDQABLgAECggJEQAHAAAAAA==.Guthix:BAAALgAECgUJBgAAAA==.',
['Gê']='Gêm:BAABLgAECn9JAAIVAAkJ8xLHDAAGAgAVAAkJ8xLHDAAGAgAAAA==.',
['Gï']='Gïmlï:BAAALgADCgMJAwAAAA==.',
Ha='Haildydra:BAAALgAECgIJAgABLgAECgcJCgAHAAAAAA==.Halibell:BAAALgAECgYJDQAAAA==.Halnan:BAAALgADCgEJAQABLgAECgcJHgANAKIVAA==.Harkanum:BAABLgAECn9GAAQnAAkJ9hlxBgDnAQAnAAgJLhhxBgDnAQAVAAkJGg2GEgCgAQAWAAQJrxPwPgDuAAAAAA==.Harrow:BAABLgAECn8VAAIGAAgJhAo8FwAhAQAGAAgJhAo8FwAhAQAAAA==.Harvester:BAAALgAECgEJAQAAAA==.Hatebreéd:BAAALgAECggJCQAAAA==.',
He='Healinturds:BAAALgAECgYJDAABLgAECgcJHgANAKIVAA==.Hector:BAABLgAECn8eAAIEAAkJfSKuJgBpAgAEAAkJfSKuJgBpAgABLgAECgkJLAAGAPIfAA==.Heelys:BAAALgAECgYJCgAAAA==.Helloagain:BAACLgAFFH8bAAIGAAQJ5hsATABIAQAGAAQJ5hsATABIAQAuAAQKfyUAAgYABglqIyFdACMCAAYABglqIyFdACMCAAAA.Heparin:BAAALgAECgIJAgAAAA==.Herryknutsak:BAAALgAECgEJAQAAAA==.Hestonater:BAAALgAECgUJBwAAAA==.Hestra:BAAALgADCgMJBAAAAA==.',
Hi='Hidethetotem:BAABLgAECn8zAAMLAAkJ8h5KDgDiAgALAAkJ8h5KDgDiAgAIAAEJHgq+MAAjAAAAAA==.Hightops:BAAALgAECggJDgAAAA==.Hikari:BAACLgAFFH8QAAIEAAgJrAw7MgBLAQAEAAgJrAw7MgBLAQAuAAQKfx4AAgQACQlrHOAsAHACAAQACQlrHOAsAHACAAAA.Hiown:BAAALgAECgEJAwAAAA==.',
Ho='Holeliness:BAAALgAECggJEwAAAA==.Holybackshot:BAAALgAECgQJBgAAAA==.Holydisco:BAAALgADCgcJCQAAAA==.Holyhide:BAAALgAECgEJAQAAAA==.Holyrebel:BAAALgAECgYJBgABLgAECgYJDwAHAAAAAA==.Holyspike:BAABLgAECn81AAILAAkJmRTLBwDSAQALAAkJmRTLBwDSAQAAAA==.Holytard:BAAALgADCgYJBgAAAA==.Holytaren:BAABLgAECn8UAAIXAAgJ3RvVEwBwAgAXAAgJ3RvVEwBwAgAAAA==.Holytickles:BAABLgAECn8tAAMZAAkJ4hsCEwBeAgAZAAgJ+hsCEwBeAgAJAAkJsBewEgBIAgABLgAFFAkJKgAdAKgWAA==.Holytotem:BAAALgAECgEJAQAAAA==.Homerr:BAABLgAECn8pAAIbAAkJ+BRxSADIAQAbAAkJ+BRxSADIAQAAAA==.Honiahaka:BAABLgAECn9DAAIbAAkJBxDcRgDNAQAbAAkJBxDcRgDNAQAAAA==.Hottcakes:BAAALgAFFAMJBAABLgAFFAkJKgAdAKgWAA==.',
Hu='Huckster:BAABLgAECn8ZAAIBAAgJhQ52fwBkAQABAAgJhQ52fwBkAQAAAA==.Humanoidholy:BAABLgAECn8fAAMEAAgJXSQ6CQBIAwAEAAgJXSQ6CQBIAwADAAEJbgXWTQAYAAABLgAFFAIJAgAHAAAAAA==.Humanoidhunt:BAAALgAFFAIJAgAAAA==.Humanoidvoid:BAACLgAFFH8UAAQaAAUJmCOTBwCOAQAaAAQJVCOTBwCOAQANAAMJ9h18VgDrAAAjAAEJAAAjGAAAAAAuAAQKf1UABA0ACQkFIz8HABoDAA0ACQmdIj8HABoDABoACQkAIJQKAH8CACMACAkoCMMVAPwAAAEuAAUUAgkCAAcAAAAA.',
Hy='Hydrah:BAAALgAECgEJAQABLgAECgcJCgAHAAAAAA==.Hydrasoul:BAAALgAECgcJCAABLgAECgcJCgAHAAAAAA==.',
['Há']='Hánk:BAAALgADCgEJAQABLgAECgkJHwAdAI0MAA==.',
['Hó']='Hóód:BAAALgADCggJEQAAAA==.',
['Hö']='Hölyçow:BAAALgAECgUJBgAAAA==.',
Ic='Icedtea:BAAALgAECgcJBAAAAA==.Icicle:BAAALgADCgIJAgAAAA==.',
Id='Idunasil:BAAALgAECgEJAgAAAA==.',
Ih='Ihatemustard:BAABLgAECn8jAAIjAAkJ6RUfCAD2AQAjAAkJ6RUfCAD2AQAAAA==.',
Il='Illethan:BAAALgADCgYJBgAAAA==.Iloveketchup:BAAALgAFFAEJAQAAAA==.',
In='Inclination:BAAALgAECgEJAQAAAA==.Inoru:BAABLgAECn8dAAMZAAgJWxRRMQBXAQAZAAgJWxRRMQBXAQAJAAEJpwJjfAAcAAAAAA==.Insanity:BAAALgAECgUJCgAAAA==.Invidious:BAAALgAECgEJBAAAAA==.',
Ir='Irmaline:BAABLgAECn8rAAMJAAkJaxpNAgBkAgAJAAkJaxpNAgBkAgAZAAEJFRgbJQA/AAAAAA==.',
It='Ithurtshuh:BAAALgAECgYJDwAAAA==.Itsmaam:BAAALgAECgMJBAAAAA==.Itzcannibal:BAACLgAFFH8GAAIbAAIJ6go1jgCDAAAbAAIJ6go1jgCDAAAuAAQKfy8AAxsACQk4G/4rAC0CABsACQk4G/4rAC0CACEAAgnVCux5AFoAAAAA.',
Ja='Jabbawockie:BAAALgAECgkJAwAAAA==.Jaekoby:BAAALgAECgIJAwABLgAECggJIgAEAM0aAA==.Jakoby:BAAALgAECgUJBgABLgAECggJIgAEAM0aAA==.Jandrisel:BAABLgAECn8cAAMPAAcJQgtgEAC/AAAPAAcJQgtgEAC/AAAKAAUJtgLxngByAAAAAA==.Jarhead:BAAALgAECgEJAgAAAA==.Jayzich:BAAALgADCgQJBwAAAA==.',
Je='Jeffee:BAAALgAECgIJCQAAAA==.Jennifleur:BAAALgAECgIJAgAAAA==.Jenx:BAAALgADCgEJAQAAAA==.Jequalsjosh:BAACLgAFFH8IAAIeAAMJoRxHBwDuAAAeAAMJoRxHBwDuAAAuAAQKfz0AAh4ACQkhIlgCALsCAB4ACQkhIlgCALsCAAAA.Jerk:BAABLgAFFH8HAAINAAMJPRW8LADIAAANAAMJPRW8LADIAAAAAA==.Jerp:BAAALgAECgIJAgAAAA==.Jesper:BAABLgAECn9GAAILAAkJ5B9nCgAQAwALAAkJ5B9nCgAQAwAAAA==.Jetz:BAAALgAECgEJAQAAAA==.Jezelle:BAACLgAFFH8WAAIdAAYJ0w1zLgDOAAAdAAYJ0w1zLgDOAAAuAAQKfyIAAh0ACQn0Hg42ADQCAB0ACQn0Hg42ADQCAAAA.',
Ji='Jilara:BAABLgAECn86AAIEAAkJBghBkwBMAQAEAAkJBghBkwBMAQAAAA==.Jimmyjim:BAABLgAECn8mAAIGAAkJahD6GQALAQAGAAkJahD6GQALAQAAAA==.Jingying:BAAALgAECgQJBAAAAA==.',
Jo='Jockko:BAAALgAECgkJCQAAAA==.Johnny:BAAALgADCgQJBAAAAA==.',
Jp='Jpepps:BAABLgAECn8vAAMdAAkJDRNjPwDfAQAdAAkJDRNjPwDfAQAlAAMJxwjoRQCeAAAAAA==.',
Jr='Jrose:BAAALgAECgQJBAAAAA==.',
Ju='Jul:BAAALgAECgIJAgAAAA==.',
['Jæ']='Jækobÿ:BAAALgAECgIJAgABLgAECggJIgAEAM0aAA==.',
Ka='Kagan:BAAALgADCgMJAwAAAA==.Kahlanrahl:BAAALgADCgMJAwAAAA==.Kaiatra:BAABLgAECn82AAICAAkJ/iPvAADIAgACAAkJ/iPvAADIAgAAAA==.Kalasandria:BAAALgAECgEJAQAAAA==.Kaliguala:BAAALgAECgQJBgAAAA==.Katalaystar:BAAALgAECgcJEQABLgAECgkJKAAKAHYaAA==.Katare:BAAALgAECgMJAwAAAA==.Kaulder:BAAALgADCgUJBQAAAA==.Kaìju:BAABLgAECn8jAAIEAAkJGyHYIQB/AgAEAAkJGyHYIQB/AgAAAA==.Kaîju:BAAALgAECgIJAgAAAA==.',
Ke='Kellytgt:BAACLgAFFH8FAAINAAMJYgz5agC2AAANAAMJYgz5agC2AAAuAAQKfzkAAg0ACQkAHKkUAJ0CAA0ACQkAHKkUAJ0CAAAA.Kev:BAAALgADCgUJBQAAAA==.',
Kh='Khai:BAAALgAECgkJAQAAAA==.',
Ki='Kilaura:BAABLgAECn8ZAAIoAAgJWRAQJQCnAQAoAAgJWRAQJQCnAQAAAA==.Killian:BAAALgAECgEJAQAAAA==.Kilmandaros:BAAALgAECgEJAQAAAA==.Kippi:BAAALgAECgQJCwAAAA==.Kithara:BAAALgAECgMJAwAAAA==.',
Kn='Knitebrite:BAAALgAECgIJAgAAAA==.',
Ko='Korbix:BAAALgADCgQJBAABLgAECgkJSwAKAOUOAA==.Korhina:BAABLgAECn9NAAIFAAkJeyYfAQBZAwAFAAkJeyYfAQBZAwAAAA==.Korobas:BAAALgAECgMJAwAAAA==.Koru:BAAALgAECgQJBQABLgAECgQJBgAHAAAAAA==.Kosumi:BAAALgADCggJDQAAAA==.',
Kr='Kronic:BAABLgAECn8VAAIiAAcJJRK0BAAzAQAiAAcJJRK0BAAzAQAAAA==.Kronmon:BAAALgAECgEJAQAAAA==.',
Ku='Kudria:BAAALgAECgQJDAAAAA==.Kuroyukihime:BAABLgAECn84AAIGAAkJ/h7hGwC0AgAGAAkJ/h7hGwC0AgAAAA==.Kuwaii:BAABLgAECn8dAAIWAAcJuxjjKACfAQAWAAcJuxjjKACfAQABLgAECggJHgAPAA0gAA==.',
Ky='Kyarina:BAAALgAECgEJAQABLgAECgkJGQAJAEMHAA==.Kylis:BAAALgAECgQJBAAAAA==.Kyna:BAABLgAECn8ZAAIJAAkJQwfUPAAAAQAJAAkJQwfUPAAAAQAAAA==.Kyross:BAAALgADCgIJAgAAAA==.',
['Ká']='Kárma:BAAALgAECgMJAwABLgAECgkJHwAdAI0MAA==.',
['Ké']='Kéya:BAAALgAECgYJDQAAAA==.',
La='Lashela:BAABLgAECn8XAAIbAAkJwgt+bwBhAQAbAAkJwgt+bwBhAQAAAA==.Laughter:BAABLgAECn8eAAMFAAkJaQhBDACFAAAUAAkJZwf4WADrAAAFAAUJTQdBDACFAAAAAA==.Laurana:BAAALgADCgIJAgAAAA==.Laylah:BAAALgADCgIJAgAAAA==.Lazulie:BAABLgAECn8UAAIoAAYJdxKbMgBPAQAoAAYJdxKbMgBPAQAAAA==.',
Le='Leansipper:BAABLgAFFH8RAAIPAAUJ6hOEIQAUAQAPAAUJ6hOEIQAUAQAAAA==.Levoker:BAAALgAECgQJBAAAAA==.Lexapayne:BAAALgAECgYJEgABLgAFFAQJGAAbADcVAA==.',
Li='Lighthammer:BAAALgAECgUJBgAAAA==.Lilandra:BAAALgAECgYJDwABLgAECggJDgAHAAAAAA==.Lilcrocey:BAAALgAECgEJAQAAAA==.Lillianaxe:BAABLgAECn8XAAMkAAcJHRjEHwBWAQAkAAYJsBnEHwBWAQABAAcJAA9NlAA+AQAAAA==.Lilyvain:BAAALgAECgUJCAAAAA==.Lireal:BAACLgAFFH8FAAIXAAMJRCMSFADDAAAXAAMJRCMSFADDAAAuAAQKfzYAAhcACQmOJbsAAMgDABcACQmOJbsAAMgDAAAA.Listerine:BAAALgAECggJCQAAAA==.Litercola:BAABLgAECn8UAAIJAAYJjgKsVACJAAAJAAYJjgKsVACJAAAAAA==.Livnod:BAAALgAECgYJDAAAAA==.',
Lo='Loddeye:BAAALgAECgYJCQABLgAECgkJLwAKAEELAA==.Loonfabio:BAAALgAECgIJAgABLgAFFAYJGgAEAAwiAA==.Loosescrew:BAAALgADCgMJBAAAAA==.Lorethe:BAAALgAECgEJAQAAAA==.Lorine:BAABLgAECn87AAIDAAkJbBvpCgAbAgADAAkJbBvpCgAbAgAAAA==.Lowkie:BAAALgADCgIJAgAAAA==.',
Lu='Luckside:BAAALgAECgQJBAABLgAECgkJHwAdAI0MAA==.Lunara:BAAALgAECgMJBgAAAA==.Lunasnow:BAAALgAECgQJBAAAAA==.Lunchtime:BAAALgAECgEJAQAAAA==.Luxe:BAAALgADCgEJAQAAAA==.',
Ly='Lyntot:BAAALgADCgEJAQAAAA==.',
['Ló']='Lókki:BAAALgAECgUJCAAAAA==.',
Ma='Madwe:BAABLgAECn8hAAMNAAgJrgdHlQD2AAANAAgJcwZHlQD2AAAaAAMJcAbKUwBpAAAAAA==.Maelora:BAAALgADCgEJAQAAAA==.Mageab:BAABLgAFFH8QAAIGAAgJZiDYCACxAgAGAAgJZiDYCACxAgAAAA==.Magis:BAAALgADCgkJHgAAAA==.Malzzahar:BAAALgAECgQJBAAAAA==.Mamo:BAAALgAECgQJBAAAAA==.Manimetal:BAABLgAECn8WAAIEAAUJiwVNJQGNAAAEAAUJiwVNJQGNAAAAAA==.Materia:BAAALgAECgcJBwAAAA==.Maxxpitt:BAAALgAECgkJCQAAAA==.Mazuma:BAAALgAECgEJAQAAAA==.',
Me='Meeralax:BAABLgAECn8WAAIbAAYJJgaKvADNAAAbAAYJJgaKvADNAAAAAA==.Melizza:BAAALgADCgMJAwAAAA==.Merckel:BAACLgAFFH8IAAINAAMJMhroWgDfAAANAAMJMhroWgDfAAAuAAQKfy4AAg0ACQmyHzYdAGUCAA0ACQmyHzYdAGUCAAAA.Merckz:BAAALgAECgUJBQABLgAFFAMJCAANADIaAA==.Merks:BAAALgAFFAEJAQAAAA==.Metalmonkey:BAAALgAECgcJDwAAAA==.Meylinn:BAAALgADCggJCAAAAA==.',
Mi='Michello:BAABLgAECn8yAAIbAAkJ+x+eBACBAgAbAAkJ+x+eBACBAgAAAA==.Mickcowmoose:BAAALgADCgIJAgAAAA==.Millia:BAABLgAECn8sAAIGAAkJ8h87FwDOAgAGAAkJ8h87FwDOAgAAAA==.Mint:BAABLgAECn8jAAIXAAcJiyOMDwCfAgAXAAcJiyOMDwCfAgAAAA==.Mintberrytea:BAAALgAECgUJBwABLgAECgcJIwAXAIsjAA==.Mintchaitea:BAABLgAECn8jAAIMAAkJ/iEpBQBYAwAMAAkJ/iEpBQBYAwABLgAECgcJIwAXAIsjAA==.Misstress:BAABLgAECn9BAAMPAAkJcRDwJACkAQAPAAkJGhDwJACkAQAQAAQJ0w77OgC6AAAAAA==.Mizen:BAAALgADCgUJCAAAAA==.',
Mo='Mogdor:BAAALgADCgUJBQAAAA==.Monkussy:BAAALgAECgIJAgAAAA==.Monoxide:BAAALgADCgkJCQABLgAECgkJKAAgAMQjAA==.Moonhunt:BAAALgAECgYJDAAAAA==.Moonly:BAACLgAFFH8GAAIiAAMJwAROKQCQAAAiAAMJwAROKQCQAAAuAAQKfyYAAiIACQlhDDAcALsBACIACQlhDDAcALsBAAAA.Morrag:BAABLgAECn9NAAMdAAkJGhNkBgDMAQAdAAkJ1xJkBgDMAQAcAAIJXAsEEwA2AAAAAA==.',
Mu='Murdumurdu:BAAALgAECgUJCAAAAA==.Murkblade:BAAALgADCgYJBgABLgAECgcJHgANAKIVAA==.Murphee:BAAALgAECgMJBAAAAA==.Musho:BAAALgADCgYJEgAAAA==.Mustakrakish:BAAALgAECgEJAQAAAA==.',
My='Myn:BAABLgAECn8XAAIKAAkJwhk2FgCWAgAKAAkJwhk2FgCWAgAAAA==.Myrandee:BAAALgADCgEJAQAAAA==.Myw:BAAALgAECgcJBwABLgAFFAkJNQALAJEXAA==.',
['Mæ']='Mædenless:BAAALgAECgYJCQAAAA==.',
['Mí']='Mísfìt:BAABLgAECn88AAMLAAkJQRnXIQBEAgALAAkJQRnXIQBEAgAIAAgJEQyZPQA/AQAAAA==.',
Na='Nakaito:BAABLgAECn8cAAIdAAgJ+AyPcABZAQAdAAgJ+AyPcABZAQABLgAECgkJPwAeAA8bAA==.Narcoleptic:BAACLgAFFH8hAAIVAAYJuhEmCQA5AQAVAAYJuhEmCQA5AQAuAAQKf0sABBUACQmoGRUBAEgCABUACQmoGRUBAEgCABYACAmFFg0nAKoBACcABQkQCFQvAJ0AAAAA.Nashty:BAAALgAECgEJAQAAAA==.Naturaljuice:BAAALgAECgUJCgABLgAFFAkJKgAdAKgWAA==.Nazalzin:BAAALgAECgMJAwAAAA==.',
Ne='Neocracy:BAAALgADCgYJCwABLgAECggJFAAXAN0bAA==.Neuron:BAAALgAECgcJCgABLgAECgkJSwAKAOUOAA==.Nex:BAAALgADCgYJCAAAAA==.',
Ni='Niceshield:BAAALgAECgEJBgAAAA==.Nightmarexx:BAACLgAFFH8VAAIYAAUJZh5dGgBDAQAYAAUJZh5dGgBDAQAuAAQKf04AAhgACAmnIb8KAHgCABgACAmnIb8KAHgCAAAA.Nightsawdy:BAABLgAECn88AAMbAAkJSCEiBACcAgAbAAkJSCEiBACcAgAiAAgJTRQpJQB0AQAAAA==.Nightsnake:BAAALgAECgMJAwAAAA==.Niightstorm:BAABLgAECn8qAAMbAAcJpx3hNQAGAgAbAAcJpx3hNQAGAgAiAAQJbBL7PwDIAAAAAA==.Nikwillig:BAAALgAECggJDQAAAA==.Nilveron:BAAALgADCgcJCQAAAA==.Nitefire:BAAALgAECgQJAgAAAA==.Nitelight:BAAALgADCgYJAwAAAA==.Nitélifé:BAAALgAECgYJEgAAAA==.',
Nj='Njörðr:BAABLgAECn8XAAINAAYJMA1vFgDSAAANAAYJMA1vFgDSAAAAAA==.',
No='Nocturnum:BAABLgAFFH8IAAIYAAMJhQ7XKQDeAAAYAAMJhQ7XKQDeAAABLgAFFAQJGwAGAOYbAA==.Noxmortis:BAAALgAFFAMJBAAAAA==.',
Nt='Ntadadarknes:BAAALgAECgIJBAABLgAECgkJLwAKAEELAA==.',
Oo='Ooblidoom:BAAALgAECgEJAQABLgAECgkJVAAnAIITAA==.',
Op='Opalinnas:BAABLgAECn8oAAMKAAkJdhooFwCNAgAKAAkJdhooFwCNAgAPAAUJeQgqXQCiAAAAAA==.',
Oz='Ozath:BAAALgAECgQJBgAAAA==.',
Pa='Pallyandtank:BAAALgAFFAEJAQAAAA==.Passionfruit:BAAALgAFFAMJBAAAAA==.',
Pe='Peachtea:BAABLgAECn8VAAIXAAQJhB9VCQAtAQAXAAQJhB9VCQAtAQAAAA==.',
Ph='Phatshaman:BAABLgAECn8UAAIIAAgJbQeDUQDyAAAIAAgJbQeDUQDyAAAAAA==.Phæryll:BAAALgADCgUJBgAAAA==.',
Pi='Pirodeath:BAAALgAECgcJCgAAAA==.',
Pl='Place:BAAALgAECgIJAgAAAA==.',
Po='Poisonclaw:BAAALgAECgIJBAAAAA==.Poprotonix:BAABLgAECn8fAAIEAAgJPxZuTgDcAQAEAAgJPxZuTgDcAQAAAA==.Pozessedkaos:BAAALgAECgQJBAAAAA==.',
Pr='Praecantrix:BAAALgAECgEJBQAAAA==.Prath:BAAALgADCgEJAQAAAA==.Pray:BAABLgAECn9DAAIoAAkJBCSbAgCKAwAoAAkJBCSbAgCKAwAAAA==.Prepotenté:BAAALgAECgQJCQAAAA==.Priestyballz:BAAALgAECgYJBgAAAA==.Prodarkangel:BAABLgAECn8bAAMlAAkJIgl1FwDnAAAlAAkJIgl1FwDnAAAdAAMJaAOeGAFPAAAAAA==.',
Pu='Pubis:BAAALgAECgYJDgAAAA==.Puckllane:BAABLgAECn8aAAIEAAkJ5RdiQQAhAgAEAAkJ5RdiQQAhAgAAAA==.Punkbeer:BAAALgAECgEJAQAAAA==.Punkin:BAAALgAECgUJCwAAAA==.',
Py='Pyre:BAABLgAECn89AAIoAAkJSQ+vIgC5AQAoAAkJSQ+vIgC5AQABLgAECgcJBwAHAAAAAA==.Pyroth:BAAALgAECgEJAQAAAA==.',
['Pó']='Pó:BAAALgADCgIJBAABLgAECgkJHwAdAI0MAA==.',
['Pü']='Püff:BAAALgAECgMJAwABLgAFFAYJFwALANIRAA==.',
Qu='Quefstank:BAAALgADCgUJCAAAAA==.Quivver:BAAALgAECgQJAgAAAA==.',
Ra='Rabmaxx:BAABLgAECn9IAAIaAAkJKxikAgA3AgAaAAkJKxikAgA3AgAAAA==.Radren:BAAALgADCgEJAQAAAA==.Rajinazn:BAAALgAECgYJBgAAAA==.Rattchett:BAAALgAECgYJBgAAAA==.Ravenlight:BAABLgAFFH8FAAIEAAQJWA7UUQAMAQAEAAQJWA7UUQAMAQAAAA==.Ravenwynnd:BAABLgAECn8tAAImAAkJuyKIBADRAgAmAAkJuyKIBADRAgAAAA==.Raynelock:BAABLgAECn8wAAMlAAkJgRA0CwCNAQAlAAkJgRA0CwCNAQAdAAIJtQcZCQFKAAAAAA==.Raynman:BAABLgAECn9DAAILAAkJdxVAJgApAgALAAkJdxVAJgApAgAAAA==.Razgriz:BAAALgAECgEJAQAAAA==.Razix:BAABLgAECn8zAAQWAAkJfxRYIADWAQAWAAkJfxRYIADWAQAnAAYJ6wkZGQCOAAAVAAMJYwclPACJAAAAAA==.',
Re='Realist:BAAALgAECgMJBAAAAA==.Refrigtuitor:BAACLgAFFH8hAAMGAAcJVgwYYwAcAQAGAAcJVgwYYwAcAQApAAIJuAIZBgBiAAAuAAQKfz8ABAYACQmEH+AgAJsCAAYACQmEH+AgAJsCAA4ABQmDCGQOAN0AACkAAQk8EK4TADYAAAAA.Reija:BAAALgAECgEJAgAAAA==.Repentance:BAAALgADCgEJAQABLgAECgkJMwAgAOIXAA==.Revealed:BAAALgADCgEJAQAAAA==.Reyeda:BAAALgADCgUJBQAAAA==.Rezzarn:BAAALgAECgEJAQAAAA==.',
Rh='Rhun:BAAALgAECgYJCQAAAA==.Rhyzer:BAABLgAECn83AAMUAAkJ/h31AgArAgAUAAkJ/h31AgArAgAmAAEJJQ1bRQAuAAAAAA==.',
Ri='Ridgge:BAAALgADCgEJAQAAAA==.Rileyksufan:BAABLgAECn8VAAIbAAkJhg4yfwBBAQAbAAkJhg4yfwBBAQAAAA==.Rinas:BAACLgAFFH8FAAIaAAIJpxcnIQCSAAAaAAIJpxcnIQCSAAAuAAQKfzYAAxoACQm4IpQDABwDABoACQm4IpQDABwDAA0AAgmfDckUATUAAAAA.Rivendell:BAAALgAECgQJBgAAAA==.Rivenlynn:BAAALgADCgEJAQAAAA==.',
Ro='Rolando:BAAALgAECgUJBgABLgAECgkJIwAUAC4hAA==.Root:BAACLgAFFH8IAAIQAAMJQx3qCQD1AAAQAAMJQx3qCQD1AAAuAAQKfxgAAhAACAlTHo4BAF4CABAACAlTHo4BAF4CAAEuAAUUBAkSAAEAXB4A.',
Ru='Rubioxis:BAAALgADCgYJBgAAAA==.',
Ry='Rymarri:BAAALgADCgkJCQAAAA==.',
Sa='Sabazia:BAACLgAFFH8QAAIkAAMJXBwqIADmAAAkAAMJXBwqIADmAAAuAAQKfzsAAiQACQkXILkHAJ0CACQACQkXILkHAJ0CAAAA.Sable:BAACLgAFFH8FAAIDAAMJDAJkEwBfAAADAAMJDAJkEwBfAAAuAAQKfzAAAwMACQn6CWUeACEBAAQACAnNCCGpACkBAAMACQlNCGUeACEBAAAA.Sacrificer:BAAALgAECgMJAwAAAA==.Sairalindë:BAABLgAECn8oAAMbAAkJrAiSIwDPAAAbAAkJrAiSIwDPAAAhAAMJpAA3hgA2AAAAAA==.Saleath:BAAALgAECgEJAwAAAA==.Salios:BAABLgAFFH8NAAIdAAQJNB6wFwAzAQAdAAQJNB6wFwAzAQAAAA==.Sallydisco:BAAALgAECgMJAwABLgAFFAQJCgAFAN8hAA==.Sanctifier:BAAALgAECgQJDQAAAA==.Saraneth:BAAALgAECgEJAQABLgAFFAMJBQAXAEQjAA==.',
Sc='Scandrel:BAAALgAECgQJBAABLgAFFAYJHQABAJ8fAA==.Scrept:BAAALgAFFAEJAQAAAA==.Scynix:BAEBLgAECn8pAAMWAAkJdRijGgABAgAWAAkJdRijGgABAgAVAAEJsgFhTgAiAAAAAA==.',
Se='Sedaline:BAAALgAECgQJBgAAAA==.Sephie:BAAALgADCgQJAQAAAQ==.Serenas:BAAALgAECgQJBAABLgAFFAEJAQAHAAAAAA==.Serenilock:BAAALgADCgMJAwAAAA==.Sereth:BAAALgADCgQJBAAAAA==.Serfdog:BAAALgADCgcJDAAAAA==.Servoker:BAACLgAFFH8YAAIVAAgJyhqbCQAoAQAVAAgJyhqbCQAoAQAuAAQKfycAAxYACQnHIiEKANQCABYACQnHIiEKANQCABUABwkkGrwVAPABAAAA.Setani:BAAALgADCgIJAgAAAA==.',
Sh='Shabzkaw:BAAALgADCgUJBQAAAA==.Shabzyt:BAAALgADCgQJBAAAAA==.Shaddows:BAABLgAECn8XAAIZAAkJwRFqBADIAQAZAAkJwRFqBADIAQAAAA==.Shaienne:BAAALgAECgkJCwAAAA==.Shambussy:BAAALgAECgEJAQAAAA==.Shamfore:BAAALgADCgUJBgAAAA==.Shamrockshak:BAACLgAFFH8GAAILAAIJKSYXQwDbAAALAAIJKSYXQwDbAAAuAAQKfyMAAwsACAl0IKMhAEUCAAsABwmMIKMhAEUCAAgAAQnWEdUqADcAAAAA.Shaze:BAAALgADCggJEAAAAA==.Shenuton:BAABLgAECn8cAAIEAAkJkA9YEwBGAQAEAAkJkA9YEwBGAQAAAA==.Shieldinterd:BAAALgAECgMJAgABLgAECgcJHgANAKIVAA==.Shiftkicker:BAAALgADCgMJAwAAAA==.Shocktherapy:BAAALgAECgEJAQAAAA==.Shockthêràpy:BAACLgAFFH8JAAILAAMJjwxsXACTAAALAAMJjwxsXACTAAAuAAQKfzQABAsACQlbGG0nAPMBAAsACQlbGG0nAPMBAAgABgl+GsQJADMBACAAAQlPCkYrADgAAAAA.Shoes:BAABLgAECn89AAQiAAkJTSWdAgAdAwAiAAkJxiOdAgAdAwAhAAgJIx/cDQDVAgAbAAgJ9SLVKAA7AgAAAA==.Shoresy:BAAALgAECgEJAgAAAA==.Shtdruid:BAAALgAECgcJDAAAAA==.Shyanni:BAAALgADCgMJAwAAAA==.Shöçkér:BAAALgAECgcJEwAAAA==.',
Si='Siaana:BAAALgADCgUJBQABLgAFFAMJEAAkAFwcAA==.Sibearian:BAABLgAECn8hAAQQAAkJkxk6EgDNAQAQAAkJkxk6EgDNAQARAAYJ0ApYJwDSAAAPAAIJPwSEdQBNAAABLgAFFAIJAgAHAAAAAA==.Simi:BAACLgAFFH8YAAIbAAQJNxWMJAAVAQAbAAQJNxWMJAAVAQAuAAQKfzUAAhsACQkVHoQHABcCABsACQkVHoQHABcCAAAA.',
Sk='Skrubzz:BAABLgAECn8ZAAMFAAgJIQbpIAA4AQAFAAgJIQbpIAA4AQAUAAQJzgKHhwChAAAAAA==.Skôrn:BAABLgAECn8wAAIGAAcJLQ8JmwBDAQAGAAcJLQ8JmwBDAQAAAA==.',
Sl='Sloppynachos:BAABLgAECn8pAAIYAAgJRhdmGgAvAgAYAAgJRhdmGgAvAgAAAA==.Slyman:BAAALgADCgUJBQABLgAECgYJBwAHAAAAAA==.',
Sm='Smithnwesson:BAAALgAECgMJAwAAAA==.Smokesçreen:BAACLgAFFH8UAAIaAAQJ/BNBEQAZAQAaAAQJ/BNBEQAZAQAuAAQKf00ABBoACQkEIZoFAOYCABoACQkEIZoFAOYCACMABwm4FQsCAJkBAA0ABQm6BcXVAIkAAAAA.',
Sn='Snowhoof:BAAALgADCgUJBQAAAA==.',
So='Soccerqt:BAAALgAECgYJBgAAAA==.Sogerä:BAABLgAECn8XAAIVAAgJIQWJHwD5AAAVAAgJIQWJHwD5AAAAAA==.Soonerpride:BAABLgAECn8cAAIEAAgJBCPzLABNAgAEAAgJBCPzLABNAgAAAA==.Sorinmarkov:BAAALgAFFAIJAgAAAA==.Source:BAAALgAECgUJCAABLgAECgkJHgAIAIQPAA==.',
Sp='Spearminttea:BAAALgAECgcJCwAAAA==.Spellbreakr:BAABLgAFFH8MAAIGAAcJbwyPGwCVAQAGAAcJbwyPGwCVAQAAAA==.Spellumgud:BAAALgAECgQJBgAAAA==.Sprockette:BAAALgAECgYJDQAAAA==.',
Sq='Squiby:BAABLgAECn8/AAMZAAkJoCLkBgDjAgAZAAkJoCLkBgDjAgAJAAcJDiHMAQCaAgAAAA==.Squizzy:BAAALgAECgEJAQAAAA==.',
St='Stabfore:BAABLgAECn8mAAMYAAkJKBVIEAAqAgAYAAkJKBVIEAAqAgAeAAEJJgTILAAlAAAAAA==.Standaside:BAAALgAECgIJBAAAAA==.Steellidan:BAAALgADCgEJAQAAAA==.Stinky:BAABLgAECn8XAAIfAAgJkQl3DgAlAQAfAAgJkQl3DgAlAQAAAA==.Stix:BAACLgAFFH8WAAIYAAQJih7lFABkAQAYAAQJih7lFABkAQAuAAQKfy0AAxgACQl6HCsNAFQCABgACQl6HCsNAFQCAB8ABAmnFTIUAMsAAAAA.Stoya:BAAALgAECgYJCgABLgAFFAMJBQAXAEQjAA==.Stuef:BAABLgAECn82AAIIAAkJGyGPCgC2AgAIAAkJGyGPCgC2AgAAAA==.Stuefagos:BAAALgAECgQJBwAAAA==.Stuefester:BAABLgAECn8nAAMBAAkJNiBQIACIAgABAAkJNiBQIACIAgAkAAcJyRrLAwDPAQAAAA==.Stueflare:BAAALgAECggJEAAAAA==.Stueflip:BAAALgADCgIJAgAAAA==.Stunsturds:BAABLgAECn8dAAMMAAYJQiAVHgApAgAMAAYJQiAVHgApAgASAAEJ2AF+mQAaAAABLgAECgcJHgANAKIVAA==.Stäirs:BAABLgAECn9CAAIUAAkJ5B1tDwB/AgAUAAkJ5B1tDwB/AgAAAA==.',
Su='Summerlily:BAAALgADCgYJBgAAAA==.',
Sv='Svaja:BAAALgAECgIJAQABLgAECgkJJAAVAOwLAA==.Sveika:BAAALgAECgcJEAABLgAECgkJJAAVAOwLAA==.',
Sy='Sylaria:BAEALgAECgcJDQAAAA==.Syreline:BAAALgAECgEJAgAAAA==.',
['Sí']='Síñ:BAAALgAECgMJBAABLgAECggJIgAdAFIaAA==.',
['Sî']='Sîn:BAAALgADCgEJAQABLgAECggJIgAdAFIaAA==.',
['Sï']='Sïn:BAABLgAECn8iAAIdAAgJUhq+PADpAQAdAAgJUhq+PADpAQAAAA==.',
['Sý']='Sýlver:BAAALgAECgQJCgAAAA==.',
Ta='Taereachye:BAACLgAFFH8HAAIXAAMJ3xdeLgDAAAAXAAMJ3xdeLgDAAAAuAAQKfxcAAhcABwk5JAYKANMCABcABwk5JAYKANMCAAEuAAUUBAkIAAwAgBUA.Tailon:BAAALgADCgYJBgAAAA==.Taintedlove:BAAALgADCgYJBgAAAA==.Talenelat:BAAALgADCgcJCwAAAA==.Talikas:BAAALgAECggJEAABLgAFFAMJBQANAGIMAA==.Tankin:BAAALgADCgMJAwAAAA==.Tantric:BAAALgAECgIJAgABLgAECggJCQAHAAAAAA==.Tarathiel:BAAALgADCgQJBAAAAA==.Tarpalantir:BAABLgAECn8fAAIFAAgJYggFBwD8AAAFAAgJYggFBwD8AAAAAA==.Taurne:BAACLgAFFH8ZAAIKAAcJaA8PHwBhAQAKAAcJaA8PHwBhAQAuAAQKfx8AAwoACAn7FoEwAOkBAAoABwmzGYEwAOkBAA8AAQmnBCgvABIAAAAA.',
Te='Technique:BAAALgAECgIJBgAAAA==.Teebags:BAAALgADCgEJAQAAAA==.Teknoman:BAACLgAFFH8XAAMUAAMJ5xtTGgDRAAAUAAMJ5xtTGgDRAAAFAAIJQAeaGQBYAAAuAAQKf0IAAhQACQnvIacKALsCABQACQnvIacKALsCAAAA.Telmarine:BAAALgAECgMJAwAAAA==.Tempered:BAACLgAFFH8GAAMmAAMJnwwIGACPAAAmAAIJ9w8IGACPAAAUAAIJ5ApdKgB1AAAuAAQKfxgAAyYABgkyHJoXAJ4BACYABgkyHJoXAJ4BABQABAlFG8tlAMUAAAEuAAUUBAkWABgAih4A.Terlemen:BAAALgAECgUJBQAAAA==.Tetsumi:BAAALgADCgYJCQABLgAECggJDgAHAAAAAA==.',
Th='Thaddeus:BAAALgAECgEJAQABLgAFFAYJHgAHAAAAAQ==.Thaitea:BAAALgAECgUJBgAAAA==.Thal:BAAALgAECgMJAwAAAA==.Thalan:BAAALgADCgEJAQAAAA==.Thalindra:BAABLgAECn80AAIbAAkJWhtnOQD4AQAbAAkJWhtnOQD4AQAAAA==.Tharain:BAAALgAECgYJCAAAAA==.Thebigbeast:BAABLgAFFH8KAAIDAAIJ4hVXCgB0AAADAAIJ4hVXCgB0AAABLgAFFAkJKgAdAKgWAA==.Thecurt:BAABLgAECn9BAAISAAkJnyRKAgA7AwASAAkJnyRKAgA7AwAAAA==.Thedammed:BAAALgADCgEJAQAAAA==.Theholylight:BAAALgAECgYJDQAAAA==.Thehuzz:BAABLgAECn8YAAMLAAkJPRE5EgAVAQALAAgJpQ85EgAVAQAgAAEJjgnqGgAjAAAAAA==.Thermidor:BAABLgAECn8gAAIiAAkJYBV5CQBLAgAiAAkJYBV5CQBLAgAAAA==.Thorsamie:BAAALgAECggJDgAAAA==.Thrasios:BAAALgAECgIJAgABLgAFFAIJBgAaAMYYAA==.Thundercunti:BAAALgADCgYJDAABLgAFFAIJBwAYAJ4dAA==.Thyralizen:BAAALgADCgQJBAAAAA==.',
Ti='Tiamatt:BAAALgADCgIJBAAAAA==.Ticktock:BAAALgAECgIJAgAAAA==.Timaeus:BAABLgAECn8XAAIUAAcJAQIuhQBpAAAUAAcJAQIuhQBpAAAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Titanlock:BAAALgAECgcJCwAAAA==.',
Tk='Tkdfath:BAABLgAECn8VAAIbAAgJiA4DZQB7AQAbAAgJiA4DZQB7AQAAAA==.',
To='Torvia:BAAALgAECgcJDQAAAA==.Totemix:BAAALgADCgcJEgAAAA==.Totemsoul:BAAALgAECgEJAwABLgAECgcJCgAHAAAAAA==.',
Tr='Trisinz:BAABLgAECn8lAAIPAAgJ0RcEHgDYAQAPAAgJ0RcEHgDYAQAAAA==.Trixa:BAAALgADCgMJAwAAAA==.',
Tu='Tuerto:BAABLgAECn8VAAIbAAYJpg96lgATAQAbAAYJpg96lgATAQAAAA==.Turbojohnson:BAAALgAECgQJBgAAAA==.Turk:BAABLgAECn9EAAMNAAkJtRefJQA3AgANAAkJtRefJQA3AgAaAAEJCQ/BcwAxAAAAAA==.Turkish:BAABLgAECn9AAAMBAAkJZBqBMgA0AgABAAkJZBqBMgA0AgACAAEJ7gYcQQAlAAAAAA==.Turtledisco:BAACLgAFFH8KAAIFAAQJ3yGtEwAHAQAFAAQJ3yGtEwAHAQAuAAQKfycAAgUACQnSH7sDABcDAAUACQnSH7sDABcDAAAA.',
Ty='Tychaa:BAAALgAECgQJAgAAAA==.Tylat:BAAALgADCgEJBQAAAA==.Tyranax:BAACLgAFFH8FAAIoAAIJ1wo2PwB8AAAoAAIJ1wo2PwB8AAAuAAQKfz0ABCgACQnlG2gKAMkCACgACQneGmgKAMkCAAkABgnVH1IcAPoBABkABwkxE2gzAEwBAAAA.Tyyregade:BAAALgADCgkJCgABLgAECggJDgAHAAAAAA==.',
Uj='Ujimas:BAAALgAECgEJAgAAAA==.',
Us='Us:BAAALgAECggJCQAAAA==.',
Uz='Uzzi:BAAALgAECgEJAQAAAA==.',
Va='Vadose:BAABLgAECn8gAAIdAAcJwQqmgQBXAQAdAAcJwQqmgQBXAQABLgAFFAQJGAAbADcVAA==.Vales:BAAALgAECgYJEAABLgAFFAMJBQAbAMABAA==.Valsavis:BAABLgAECn8gAAIPAAgJkxSrIgC0AQAPAAgJkxSrIgC0AQAAAA==.Valytrois:BAABLgAECn8VAAIdAAcJlwmysQD1AAAdAAcJlwmysQD1AAAAAA==.Vanra:BAAALgAECgkJBQAAAA==.Varinix:BAAALgADCgMJBQAAAA==.',
Ve='Veggiebaha:BAAALgADCgIJAgAAAA==.Veiksla:BAABLgAECn8kAAMVAAkJ7AsIGgA4AQAVAAgJwAgIGgA4AQAnAAIJSAjOBwBMAAAAAA==.Velore:BAAALgADCgcJDAAAAA==.Vengerr:BAAALgAECgUJBgAAAA==.Verace:BAAALgAECgcJAQAAAA==.Verradic:BAABLgAECn8aAAMdAAgJsQcZGAC2AAAdAAgJNAcZGAC2AAAlAAUJ4AXKJgB/AAAAAA==.',
Vi='Vitur:BAABLgAECn9NAAINAAkJEiKXFACeAgANAAkJEiKXFACeAgAAAA==.',
Vo='Voidhunter:BAABLgAECn8VAAINAAcJGwrplQD1AAANAAcJGwrplQD1AAAAAA==.Voidweaver:BAAALgAECgMJBQAAAA==.Volaine:BAABLgAECn83AAMdAAkJXRQrDAA+AQAdAAgJkRMrDAA+AQAcAAMJVxcNEABNAAAAAA==.Volt:BAABLgAECn8zAAIgAAkJ4heeCgAQAgAgAAkJ4heeCgAQAgAAAA==.Volumoso:BAAALgAECgYJBgAAAA==.Volwryn:BAAALgAECgUJCAABLgAECggJCQAHAAAAAA==.Vorarephilia:BAAALgAECgEJAQAAAA==.',
Vy='Vynarian:BAABLgAECn8zAAIGAAkJ4xYeGQARAQAGAAkJ4xYeGQARAQAAAA==.',
['Vâ']='Vâljean:BAAALgADCgMJAwAAAA==.',
['Vô']='Vôx:BAAALgAECgIJAgABLgAECgkJIgATAIoYAA==.',
['Vö']='Vöx:BAAALgAECgEJAQABLgAECgkJIgATAIoYAA==.',
Wa='Walkure:BAAALgAECgcJCwAAAA==.Warbeard:BAABLgAECn8oAAIUAAkJ8gvrLQCZAQAUAAkJ8gvrLQCZAQAAAA==.',
We='Wetasstotem:BAAALgAECgEJAQABLgAFFAkJKgAdAKgWAA==.',
Wi='Wizwizx:BAAALgADCgUJBgAAAA==.',
Wr='Wreckbums:BAABLgAFFH8PAAIBAAMJiB/tcwAZAQABAAMJiB/tcwAZAQAAAA==.Wreckd:BAACLgAFFH8HAAINAAMJlRCmMAC0AAANAAMJlRCmMAC0AAAuAAQKfyIAAw0ABwmeGGRGALQBAA0ABwmeGGRGALQBABoAAgkiDG11ACoAAAEuAAUUBAkWABgAih4A.',
Wy='Wyth:BAAALgAECgQJBQABLgAECgQJBgAHAAAAAA==.',
Xa='Xanthad:BAAALgADCgEJAQAAAA==.',
Xb='Xb:BAAALgAECgQJAgAAAA==.',
Xi='Xitãozinho:BAAALgAECgUJBwAAAA==.',
Xo='Xolair:BAAALgAECgYJDgAAAA==.',
Ya='Yaalia:BAABLgAECn8mAAMEAAkJGQmpHgDtAAAEAAkJGQmpHgDtAAAXAAQJyQMqHABFAAAAAA==.Yaan:BAABLgAECn8gAAIIAAgJMQpKRwAXAQAIAAgJMQpKRwAXAQAAAA==.Yalane:BAAALgAECgQJBwAAAA==.',
Yo='Yoba:BAAALgAECgMJAwAAAA==.Yoshira:BAAALgADCgQJBAAAAA==.',
['Yö']='Yör:BAAALgAECgEJAQAAAA==.',
Za='Zain:BAABLgAECn9GAAQmAAkJNx35BwB2AgAmAAkJNx35BwB2AgAUAAYJGA5fWQBIAQAFAAIJKA0SSgBNAAAAAA==.Zandibar:BAABLgAECn82AAIUAAkJhR44AwAXAgAUAAkJhR44AwAXAgAAAA==.Zaptoasted:BAAALgAECgUJBgAAAA==.Zariea:BAAALgAFFAIJAgABLgAFFAMJEgABAPocAA==.Zarinisong:BAAALgAECgYJDAAAAA==.Zaroff:BAAALgAECgYJCgAAAA==.',
Ze='Zedadiah:BAAALgADCgEJAQAAAA==.Zelah:BAAALgAECgQJBAAAAA==.Zellezugtail:BAAALgAECgUJCgABLgAECgkJLQAdAGUKAA==.Zenessa:BAAALgADCgYJBgAAAA==.',
Zi='Zillah:BAAALgAECgEJAQABLgAECgcJCgAHAAAAAA==.Zinder:BAABLgAECn8oAAIGAAkJsQ48XQDHAQAGAAkJsQ48XQDHAQAAAA==.Zinfandell:BAAALgAECgEJAgABLgAECgkJSwAKAOUOAA==.',
Zu='Zuggie:BAABLgAECn8tAAIdAAkJZQrSgQA1AQAdAAkJZQrSgQA1AQAAAA==.Zugtail:BAABLgAECn8rAAIWAAcJ5gQMDgCWAAAWAAcJ5gQMDgCWAAABLgAECgkJLQAdAGUKAA==.Zurtrinik:BAACLgAFFH8jAAIFAAkJHB2JBAAiAgAFAAkJHB2JBAAiAgAuAAQKfycAAgUACQnMIzwCAE0DAAUACQnMIzwCAE0DAAAA.',
Zy='Zylith:BAAALgAECgYJCwABLgAECgkJMwAgAOIXAA==.Zyntalla:BAAALgAECgUJBQAAAA==.',
Zz='Zzonked:BAABLgAECn8pAAMBAAkJCwjCkABEAQABAAkJzwbCkABEAQAkAAIJ/gtGPwBSAAAAAA==.',
['Zê']='Zêp:BAAALgAECgEJAgAAAA==.',
['Zø']='Zøømies:BAABLgAECn8xAAMNAAkJhhdDMAAFAgANAAkJUhdDMAAFAgAjAAYJFQ/XFgDvAAAAAA==.',
['Är']='Äréa:BAAALgADCgkJCQAAAA==.',
['Äs']='Äshnärd:BAACLgAFFH8TAAILAAMJqyMzHADsAAALAAMJqyMzHADsAAAuAAQKfzkAAgsACQlUJHEFAFwDAAsACQlUJHEFAFwDAAAA.',
['Ða']='Ðar:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðoogle:BAABLgAECn8oAAQgAAkJ9hnYAgCiAQAIAAkJ8RgjJQDAAQAgAAYJAB3YAgCiAQALAAIJjR6qHQCjAAABLgAECgYJDQAHAAAAAA==.',
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
