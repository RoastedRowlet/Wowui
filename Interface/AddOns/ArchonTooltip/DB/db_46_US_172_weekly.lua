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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Protection','DeathKnight-Unholy','Mage-Frost','Unknown-Unknown','Shaman-Elemental','Priest-Holy','Druid-Restoration','Shaman-Restoration','Monk-Mistweaver','DemonHunter-Devourer','Mage-Arcane','Druid-Balance','Druid-Guardian','Druid-Feral','Monk-Brewmaster','Monk-Windwalker','Warrior-Fury','Evoker-Preservation','Evoker-Augmentation','Paladin-Holy','Rogue-Subtlety','Priest-Shadow','DemonHunter-Havoc','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Rogue-Assassination','Rogue-Outlaw','DeathKnight-Frost','Shaman-Enhancement','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Vengeance','DeathKnight-Blood','Warlock-Destruction','Warrior-Arms','Evoker-Devastation','Priest-Discipline','Mage-Fire',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=46,date='2026-07-05',data={Ad='Adrador:BAABLgAECn86AAMBAAkJ1SSrAQAsAwABAAkJ1SSrAQAsAwACAAIJZxTtEwFvAAAAAA==.Adrenaline:BAACLgAFFH8iAAIDAAYJxh4hCgCOAQADAAYJxh4hCgCOAQAuAAQKfzkAAgMACQm8JBgDAAkDAAMACQm8JBgDAAkDAAAA.',
Ae='Aelik:BAACLgAFFH8PAAIEAAMJbBasigD0AAAEAAMJbBasigD0AAAuAAQKfykAAgQACAnwHb84ABwCAAQACAnwHb84ABwCAAAA.Aeolian:BAAALgADCgYJCQAAAA==.',
Ah='Ahkimbo:BAAALgADCgUJBQAAAA==.',
Ai='Aiika:BAAALgAECgkJCQAAAA==.Airolanah:BAAALgAECgUJBQAAAA==.',
Al='Alayssa:BAABLgAECn8tAAIFAAkJXSCxHACwAgAFAAkJXSCxHACwAgAAAA==.Alda:BAAALgAECgQJAgAAAA==.Allarius:BAAALgAECgEJAQAAAA==.Allioops:BAAALgADCgUJBQABLgAECgMJBAAGAAAAAA==.Alnima:BAACLgAFFH8GAAIHAAMJ/QGWQgB/AAAHAAMJ/QGWQgB/AAAuAAQKfxkAAgcACAnOCLk5AGgBAAcACAnOCLk5AGgBAAAA.',
Am='Amilee:BAAALgAECgYJEQAAAA==.Amishhunter:BAAALgADCgEJAQAAAA==.Amoondai:BAACLgAFFH8YAAIIAAMJMSKVCADfAAAIAAMJMSKVCADfAAAuAAQKfy8AAggACQmjIhADAGQDAAgACQmjIhADAGQDAAAA.Amoondrin:BAABLgAECn8zAAIJAAkJLwnVTQBXAQAJAAkJLwnVTQBXAQAAAA==.Amplifier:BAAALgADCgUJBQAAAA==.',
An='Analiya:BAAALgADCgMJBAAAAA==.Antichurch:BAAALgADCgEJAQAAAA==.Antisnow:BAAALgAECgIJBQABLgAECgcJCgAGAAAAAA==.Antregon:BAAALgADCgQJBwAAAA==.',
Ar='Araviin:BAABLgAFFH8TAAIFAAQJJg9nHQAlAQAFAAQJJg9nHQAlAQAAAA==.Arazen:BAAALgAECgIJAwAAAA==.Arcillias:BAAALgAECgEJAQABLgAFFAUJFgAKAG8TAA==.Arkride:BAAALgAECgEJAQAAAA==.Arlean:BAAALgAECgIJAgAAAA==.Arnadaz:BAAALgADCgEJAQABLgAFFAQJCAALAIAVAA==.Arrogance:BAAALgADCgcJBwABLgAECggJCQAGAAAAAA==.Arthia:BAAALgAECgQJEAAAAA==.Arvidpally:BAAALgAECgUJCwAAAA==.',
As='Ashmehameha:BAAALgADCgQJAgABLgAFFAMJCAAEANoTAA==.Asinn:BAAALgAECgEJAQAAAA==.Asoosimov:BAAALgADCgEJAQAAAA==.',
At='Atredes:BAABLgAFFH8KAAIMAAMJ5wZGKgCeAAAMAAMJ5wZGKgCeAAAAAA==.Attima:BAABLgAECn9BAAINAAkJWBHOAwDSAQANAAkJWBHOAwDSAQAAAA==.',
Au='Aubriana:BAAALgADCgQJBAAAAA==.Aurøra:BAAALgADCgMJAwAAAA==.Auspex:BAABLgAECn8rAAMOAAkJxwnfNgA6AQAOAAkJ6QffNgA6AQAPAAkJMAjVLwDtAAAAAA==.',
Av='Avaryn:BAACLgAFFH8dAAIJAAYJMhA4IwBAAQAJAAYJMhA4IwBAAQAuAAQKfzgAAgkACQmZIUQJACUDAAkACQmZIUQJACUDAAAA.',
Ax='Aximlii:BAAALgAECgIJAgAAAA==.',
Az='Azron:BAAALgAECgcJCAABLgAECggJDgAGAAAAAA==.',
Ba='Babavoss:BAAALgAECgkJAQAAAA==.Badarack:BAAALgAECgcJEwABLgAFFAMJBgAPAOohAA==.Badaracka:BAACLgAFFH8GAAIPAAMJ6iFbDQAlAQAPAAMJ6iFbDQAlAQAuAAQKfzAAAw8ACQmMJTUBAFADAA8ACQl7JTUBAFADABAABgnDIt0AAPoBAAAA.Badarackie:BAABLgAECn9DAAMRAAkJSCG2BwC6AgARAAkJSCG2BwC6AgASAAkJDhVsGQDmAQABLgAFFAMJBgAPAOohAA==.Badash:BAABLgAECn8rAAMDAAgJBhueEADeAQADAAgJBhueEADeAQATAAEJMQSurQAvAAABLgAFFAMJCAAEANoTAA==.Bahamuth:BAABLgAECn9DAAICAAkJIB15IwB3AgACAAkJIB15IwB3AgAAAA==.Bakshi:BAAALgAECgEJBAAAAA==.Balder:BAAALgAFFAEJAQABLgAFFAYJGAAGAAAAAQ==.Banký:BAAALgAECgEJAQABLgAECgEJAgAGAAAAAA==.Barbattos:BAACLgAFFH8dAAIUAAYJvhjmEQB3AQAUAAYJvhjmEQB3AQAuAAQKfzYAAxQACQkOJLcCADUDABQACQkOJLcCADUDABUAAQnkJNR+AGEAAAAA.Barnabas:BAAALgADCgYJBgABLgAFFAUJFgAKAG8TAA==.Barragon:BAABLgAECn8VAAIWAAcJ5g8SNwByAQAWAAcJ5g8SNwByAQAAAA==.',
Be='Bealzeboss:BAAALgAECgYJBgAAAA==.Beans:BAAALgAECgQJBAAAAA==.Bearymanalow:BAAALgAECgMJBAAAAA==.Belfore:BAAALgAECgEJAQABLgAECgkJJgAXACgVAA==.Bestea:BAAALgAECgEJAQAAAA==.Bethollbrew:BAAALgAECgYJDwAAAA==.Bexley:BAABLgAECn8tAAIBAAkJChoUCQBCAgABAAkJChoUCQBCAgAAAA==.',
Bi='Biggerbunny:BAACLgAFFH8LAAIYAAMJfQjaEQB6AAAYAAMJfQjaEQB6AAAuAAQKfzAAAhgACAmEFTcjAK8BABgACAmEFTcjAK8BAAAA.Binkter:BAAALgAECgIJBQABLgAECgIJAgAGAAAAAA==.',
Bl='Blackjax:BAAALgADCgEJAQAAAA==.Blacklok:BAAALgAECgUJEQABLgAECgkJNAAZAEElAA==.Blanne:BAAALgAECgEJAQAAAA==.Blargle:BAABLgAECn8uAAIaAAgJKQ9+XQCNAQAaAAgJKQ9+XQCNAQAAAA==.Blessedcross:BAAALgAECgMJBAAAAA==.Bleubahlz:BAAALgADCgcJBwABLgAECgMJAwAGAAAAAA==.Blinx:BAAALgAECgQJBwABLgAECggJDgAGAAAAAA==.Bloodrake:BAABLgAECn87AAIaAAkJHB6mDQDRAgAaAAkJHB6mDQDRAgAAAA==.Bloodreyne:BAAALgADCgEJAgAAAA==.Bloodseekr:BAAALgADCgcJEwAAAA==.Blueray:BAAALgAECgYJCAAAAA==.',
Bo='Boahan:BAAALgAECgMJBQABLgAECgUJCAAGAAAAAA==.Boggart:BAAALgAECgEJAQABLgAECgUJCAAGAAAAAA==.Bohein:BAAALgADCgEJAQAAAA==.Bolus:BAAALgAECgQJCAAAAA==.Botany:BAAALgAECgcJBwAAAA==.Bownafiedba:BAAALgADCgUJBQAAAA==.',
Br='Braneour:BAABLgAECn85AAMWAAkJwBpYDADJAgAWAAkJwBpYDADJAgACAAMJVBEVLQGDAAAAAA==.Brassballz:BAAALgAECgkJCQAAAA==.Browel:BAABLgAECn8aAAMbAAcJWBj4CAC3AQAbAAYJ3Rj4CAC3AQAcAAYJYQ5/nQADAQAAAA==.Bruen:BAAALgAECgYJBwAAAA==.Bryci:BAAALgAECgcJEAAAAA==.',
Bu='Bubbloseven:BAABLgAECn8UAAMWAAgJGhGEKgC7AQAWAAgJGhGEKgC7AQABAAQJABsVHQAsAQAAAA==.Budank:BAAALgADCgMJAwAAAA==.Bumm:BAABLgAECn8aAAICAAYJzwgB5ADZAAACAAYJzwgB5ADZAAAAAA==.Bustybubbles:BAAALgADCgYJBgAAAA==.',
Bz='Bzspy:BAABLgAFFH8NAAITAAMJ3gx1GgCOAAATAAMJ3gx1GgCOAAAAAA==.',
Ca='Caalin:BAAALgAECgEJAgAAAA==.Cabooselul:BAAALgAECgQJCwAAAA==.Calibre:BAABLgAECn8eAAIMAAcJohXoaABUAQAMAAcJohXoaABUAQAAAA==.Calyptus:BAABLgAECn8fAAIcAAYJhApkrgDnAAAcAAYJhApkrgDnAAAAAA==.Caprious:BAACLgAFFH8bAAIEAAUJwxkoUABRAQAEAAUJwxkoUABRAQAuAAQKfzYAAgQACQnjJGsKABwDAAQACQnjJGsKABwDAAAA.Capylaura:BAABLgAECn8bAAIaAAcJwAocggA7AQAaAAcJwAocggA7AQAAAA==.Caratine:BAABLgAECn8kAAIMAAkJwQyDewApAQAMAAkJwQyDewApAQAAAA==.Cassandrar:BAABLgAECn8yAAQdAAkJGSQIAQA5AwAdAAgJMiQIAQA5AwAXAAYJtiBlHwCbAQAeAAEJphSJIwA6AAAAAA==.Cassandraw:BAAALgAECgYJBgABLgAECgkJMgAdABkkAA==.Cat:BAAALgADCgUJBQAAAA==.Cattlelac:BAAALgADCgUJCAAAAA==.Caymus:BAABLgAECn8/AAIJAAkJcgxHBQArAQAJAAkJcgxHBQArAQAAAA==.',
Ce='Celìa:BAABLgAECn81AAIaAAkJkwk6EQD1AAAaAAkJkwk6EQD1AAAAAA==.Cess:BAAALgAECgEJAgAAAA==.',
Ch='Chaoticone:BAAALgADCgYJBgAAAA==.Chema:BAABLgAFFH8IAAILAAQJgBVzLQAIAQALAAQJgBVzLQAIAQAAAA==.Chestylarue:BAAALgAECgEJAQABLgAECggJEgAGAAAAAA==.Chfgaribaldi:BAAALgAECgEJAQAAAA==.Chifore:BAAALgAECgUJBgAAAA==.Chills:BAAALgAECgcJEQAAAA==.Chillymage:BAAALgADCgYJBgAAAA==.Chosen:BAABLgAECn8YAAICAAYJRBdtYgC+AQACAAYJRBdtYgC+AQABLgAFFAYJHQAEAJ8fAA==.Chpchop:BAAALgADCgIJAgAAAA==.Christy:BAAALgAECgQJAgAAAA==.Chugg:BAABLgAECn8fAAIKAAkJwgjyWgBNAQAKAAkJwgjyWgBNAQAAAA==.',
Ci='Ciaphus:BAABLgAECn8nAAICAAkJ0hRnRwDwAQACAAkJ0hRnRwDwAQAAAA==.Cinnamonster:BAAALgAECgcJDgAAAA==.',
Co='Coffeedemon:BAAALgADCgEJAQAAAA==.Coldslappins:BAABLgAECn8dAAIFAAgJyhNwDgAPAQAFAAgJyhNwDgAPAQAAAA==.Contagion:BAAALgAECgYJBQAAAA==.Convoke:BAABLgAECn8eAAIOAAcJDSArFgBeAgAOAAcJDSArFgBeAgAAAA==.Coragrr:BAAALgAECgEJAQAAAA==.',
Cr='Crazycrocey:BAAALgAECgYJCAAAAA==.Cryptonight:BAAALgAECgQJBAAAAA==.',
Cu='Cubcake:BAAALgADCggJCAAAAA==.Curtastrophe:BAABLgAECn89AAIFAAkJHx3jJwB7AgAFAAkJHx3jJwB7AgAAAA==.Curticus:BAAALgADCgQJBAAAAA==.Curtissax:BAAALgAECgIJAgAAAA==.Curtnought:BAAALgADCgIJAgAAAA==.',
['Cé']='Cérnùnnøs:BAAALgAECgEJAQAAAA==.',
Da='Daelanos:BAABLgAECn8cAAITAAgJPBigMACLAQATAAgJPBigMACLAQAAAA==.Dalinar:BAAALgAECgYJDAAAAA==.Damson:BAAALgADCgcJBwAAAA==.Daranger:BAAALgADCgEJAQAAAA==.Darska:BAAALgADCgYJBgABLgAECggJDgAGAAAAAA==.',
De='Deadtauren:BAAALgADCgYJDwAAAA==.Deathdemon:BAAALgAECgYJDgAAAA==.Deathfue:BAAALgAECgIJBAABLgAECgcJCgAGAAAAAA==.Deathisreal:BAAALgADCgMJAwABLgAECgYJBgAGAAAAAA==.Deathoof:BAAALgAFFAIJAgAAAA==.Decimated:BAACLgAFFH8dAAMEAAYJnx9fHAA1AQAEAAYJnx9fHAA1AQAfAAEJMgUnFAA/AAAuAAQKfyAAAgQACQkwI74YALICAAQACQkwI74YALICAAAA.Degeneracy:BAAALgAECgcJCwAAAA==.Demon:BAAALgAECgkJDgAAAA==.Demonblaze:BAABLgAFFH8GAAIZAAIJxhhwDACbAAAZAAIJxhhwDACbAAAAAA==.Demonilla:BAAALgAECggJEwAAAA==.Dempkiston:BAAALgAECgYJCwAAAA==.Denable:BAABLgAECn8uAAIJAAgJVA+NTwBRAQAJAAgJVA+NTwBRAQAAAA==.Denogan:BAAALgAECggJDgAAAA==.Deservis:BAAALgAECgUJDgABLgAECgcJHgAMAKIVAA==.Destro:BAABLgAECn8pAAIcAAkJ7w+uSQC9AQAcAAkJ7w+uSQC9AQABLgAECgkJMwAgAOIXAA==.Dethadin:BAAALgADCgcJBwAAAA==.',
Di='Dilaudyd:BAAALgAECgQJBQAAAA==.Dirteemike:BAAALgADCgMJAwAAAA==.Disbeleaf:BAACLgAFFH8FAAMOAAMJzhIGOwCLAAAOAAIJJBYGOwCLAAAJAAIJegsZWgBmAAAuAAQKfxUAAwkABgkBGRg6AK0BAAkABgkBGRg6AK0BAA4ABQlRIPctAGsBAAAA.Discoflurry:BAAALgAECgcJDgABLgAFFAQJCgADAN8hAA==.Dizzyfist:BAAALgAECgYJCQABLgAECggJDgAGAAAAAA==.',
Do='Dogaz:BAAALgAECgEJAQAAAA==.Dogsoldier:BAAALgADCgIJAgAAAA==.Dollyinho:BAAALgAECgEJAQAAAA==.Donori:BAAALgAECgQJDQAAAA==.Dorcath:BAAALgAFFAIJBAABLgAECggJHAATADwYAA==.',
Dr='Dragan:BAAALgAECgQJEgAAAA==.Dragapult:BAAALgAECggJAwAAAA==.Dragonias:BAABLgAECn8mAAIhAAkJwhewCgDCAQAhAAkJwhewCgDCAQAAAA==.Draino:BAAALgADCgUJBQAAAA==.Drakthorn:BAAALgAECgcJDAAAAA==.Dreselwings:BAAALgAECggJCAABLgAFFAgJHgAaAJsfAA==.Drinny:BAABLgAECn8yAAIIAAkJtwjDMgA+AQAIAAkJtwjDMgA+AQAAAA==.Drqueenisin:BAAALgAECgYJCQAAAA==.Druido:BAAALgAECgQJAwAAAA==.',
Du='Duerek:BAAALgAECgUJBgAAAA==.',
['Dè']='Dèaths:BAAALgAECgYJEAAAAA==.',
['Dí']='Dínglebery:BAAALgAECgYJCAAAAA==.',
Ea='Earthangel:BAABLgAECn8xAAIIAAgJ4xXwBAAqAQAIAAgJ4xXwBAAqAQAAAA==.',
Ed='Edlarel:BAAALgADCgQJBAABLgAECggJCQAGAAAAAA==.',
Ei='Eine:BAABLgAECn9DAAIaAAkJsxVAMgATAgAaAAkJsxVAMgATAgAAAA==.Eitherwind:BAABLgAECn8XAAQiAAYJ2h/YHwCdAQAiAAYJ2h/YHwCdAQAaAAIJchT/qwBsAAAhAAIJNxOYOwA0AAABLgAECggJDgAGAAAAAA==.Eivore:BAAALgAECgcJBwAAAA==.',
Ek='Ekoh:BAAALgAECgEJAgAAAA==.',
El='Eldergreen:BAABLgAECn8vAAMJAAkJQQuCVAA+AQAJAAkJQQuCVAA+AQAOAAIJkwrxeQBSAAAAAA==.Eldest:BAAALgADCgUJBQAAAA==.Elfwine:BAABLgAECn8xAAIYAAgJjQ/ABQAQAQAYAAgJjQ/ABQAQAQAAAA==.Elindria:BAABLgAECn80AAQZAAkJQSXWAwAUAwAZAAkJHiXWAwAUAwAjAAkJhiElAgDrAgAMAAUJMxu6ewA0AQAAAA==.Eliora:BAAALgADCgkJCQAAAA==.Elitist:BAABLgAFFH8KAAIEAAQJbw5jHwAjAQAEAAQJbw5jHwAjAQAAAA==.Elminstir:BAABLgAECn8XAAIFAAgJnhYCZgCxAQAFAAgJnhYCZgCxAQAAAA==.Elyissia:BAAALgAECgYJDAAAAA==.Elynisa:BAAALgAECgEJAQAAAA==.Elysian:BAABLgAECn84AAQLAAkJcxwVDADYAgALAAkJcxwVDADYAgASAAgJaB8iEABKAgARAAIJyh/pVwCpAAAAAA==.',
Em='Emogo:BAAALgADCgUJCQAAAA==.',
En='Enforcer:BAAALgADCgQJBgAAAA==.Enlightened:BAAALgAECgQJCwAAAA==.Enseral:BAABLgAECn8WAAIVAAcJMQpXSwD/AAAVAAcJMQpXSwD/AAAAAA==.',
Eo='Eotech:BAAALgAECgQJBAAAAA==.',
Er='Erastas:BAAALgADCggJCwAAAA==.Erendora:BAABLgAECn8iAAIJAAkJdg1YPwCUAQAJAAkJdg1YPwCUAQAAAA==.Erets:BAAALgAECgEJAQAAAA==.Eridar:BAAALgAECgYJBgAAAA==.Erizhal:BAAALgAECgUJEAAAAA==.Erodora:BAAALgADCgEJAQAAAA==.',
Es='Esabel:BAAALgAECgkJEgABLgAECgkJLQAFAF0gAA==.',
Ev='Eva:BAAALgAECgEJAgAAAA==.Eviae:BAABLgAECn8yAAIkAAgJkwkfBgC9AAAkAAgJkwkfBgC9AAAAAA==.Evillure:BAABLgAECn8lAAMEAAkJ8hNqQgD7AQAEAAkJ8hNqQgD7AQAkAAUJkgw3PACgAAAAAA==.',
Ez='Ezera:BAAALgAECgUJBQAAAA==.',
Fa='Falan:BAABLgAECn8wAAIKAAkJqhKGLgD8AQAKAAkJqhKGLgD8AQAAAA==.Faputa:BAAALgAECgMJAwAAAA==.Fatherjoe:BAAALgADCgYJBgAAAA==.Fayze:BAEBLgAECn8XAAMdAAcJfiMSBQAwAgAdAAcJSCMSBQAwAgAXAAIJBiGeQQC+AAABLgAFFAIJBAAGAAAAAA==.',
Fe='Fedor:BAAALgAECgkJBQAAAA==.Felbreaker:BAAALgAECgYJEAAAAA==.Fentril:BAAALgADCgIJAgABLgAECggJDgAGAAAAAA==.Feår:BAABLgAECn8fAAMcAAkJjQwjfwA7AQAcAAgJuAojfwA7AQAlAAMJ3Q8RSwCMAAAAAA==.',
Fi='Fillianora:BAAALgAECgIJAgAAAA==.Finley:BAAALgAECgQJBQAAAA==.Fircane:BAAALgADCgQJBAAAAA==.Firiel:BAAALgAECgMJAwAAAA==.Fizzle:BAAALgADCggJCAABLgAECgkJKAAJAHYaAA==.',
Fl='Flane:BAAALgAFFAEJBAABLgAFFAgJIAADAHwfAA==.Flem:BAAALgAECgMJBAAAAA==.Flexdruid:BAABLgAECn8cAAMQAAYJFg0mMQCcAAAQAAYJLgsmMQCcAAAPAAQJ4wheSwB9AAAAAA==.',
Fo='Foog:BAABLgAECn8YAAMTAAgJwxj+MACJAQATAAYJoBr+MACJAQAmAAYJGRMdKwAfAQAAAA==.',
Fr='Fragil:BAACLgAFFH8FAAIXAAIJqBatFACgAAAXAAIJqBatFACgAAAuAAQKf0QAAhcACAl+Il8BAN8BABcACAl+Il8BAN8BAAAA.Frostmane:BAACLgAFFH8dAAMEAAgJaRuGJADbAQAEAAcJaRuGJADbAQAkAAEJAAAZXgAAAAAuAAQKfzsAAwQACQlWJeEFAEoDAAQACQlWJeEFAEoDACQABwn+HMANADECAAAA.Frostynug:BAAALgADCgYJBgAAAA==.',
Fu='Fudge:BAAALgADCgYJBgAAAA==.Furbyn:BAAALgADCgIJAgAAAA==.',
Ga='Galena:BAABLgAECn8nAAMJAAkJuw+fBwDXAAAJAAkJuw+fBwDXAAAOAAEJghFWFAA1AAAAAA==.Gallamier:BAAALgADCgEJAQAAAA==.Gamerinator:BAAALgADCgcJCwAAAA==.Gangreene:BAAALgADCgYJCgAAAA==.Gapesmoothie:BAAALgADCgYJBgAAAA==.Garoanna:BAAALgAECgYJBgABLgAECgkJJAAVAFIMAA==.',
Ge='Geshalt:BAAALgAECgEJAQAAAA==.Geshtal:BAAALgAECgQJDAAAAA==.Gets:BAAALgADCgMJBAAAAA==.',
Gi='Girion:BAABLgAECn8yAAIBAAgJxQ4jBADuAAABAAgJxQ4jBADuAAAAAA==.Girliepop:BAAALgAECgEJAQAAAA==.',
Gl='Glaiven:BAECLgAFFH8eAAMMAAYJpRZqOgA7AQAMAAYJpRZqOgA7AQAjAAMJuA+bDgBhAAAuAAQKfy8AAyMACQmVIY0EAHQCAAwACQkrH6EdAKACACMACQmXHI0EAHQCAAAA.Glorfinndel:BAAALgADCgQJBAAAAA==.Glyr:BAAALgADCgUJBQAAAA==.',
Gn='Gnopower:BAAALgAECgQJBAAAAA==.',
Go='Gorgrin:BAABLgAECn8cAAIbAAkJyRRCCwCpAQAbAAkJyRRCCwCpAQAAAA==.Goude:BAAALgADCgMJBAAAAA==.',
Gr='Greenback:BAAALgADCgYJCwAAAA==.Greentotes:BAEBLgAECn8yAAMVAAkJ7x9dCADRAgAVAAkJ7x9dCADRAgAnAAUJTxOYEgDhAAABLgAFFAUJBQALAIEBAA==.',
Gu='Gunter:BAAALgAECgMJAwABLgAFFAYJHQAEAJ8fAA==.Gura:BAAALgADCgEJAQAAAA==.Gurnee:BAAALgADCgcJDQABLgAECggJEQAGAAAAAA==.Guthix:BAAALgAECgUJBgAAAA==.',
['Gê']='Gêm:BAABLgAECn9JAAIUAAkJ8xLHDAAGAgAUAAkJ8xLHDAAGAgAAAA==.',
['Gï']='Gïmlï:BAAALgADCgMJAwAAAA==.',
Ha='Haildydra:BAAALgAECgIJAgABLgAECgcJCgAGAAAAAA==.Halibell:BAAALgAECgYJDQAAAA==.Halnan:BAAALgADCgEJAQABLgAECgcJHgAMAKIVAA==.Harkanum:BAABLgAECn9GAAQnAAkJ9hlxBgDnAQAnAAgJLhhxBgDnAQAUAAkJGg2GEgCgAQAVAAQJrxPwPgDuAAAAAA==.Harrow:BAAALgAECgYJDQAAAA==.Harvester:BAAALgAECgEJAQAAAA==.Hatebreéd:BAAALgAECggJCQAAAA==.',
He='Healinturds:BAAALgAECgYJDAABLgAECgcJHgAMAKIVAA==.Hector:BAABLgAECn8eAAICAAkJfSKuJgBpAgACAAkJfSKuJgBpAgABLgAECgkJLAAFAPIfAA==.Heelys:BAAALgAECgYJCgAAAA==.Helloagain:BAACLgAFFH8bAAIFAAQJ5huZHwAYAQAFAAQJ5huZHwAYAQAuAAQKfyUAAgUABglqIyFdACMCAAUABglqIyFdACMCAAAA.Heparin:BAAALgAECgIJAgAAAA==.Herryknutsak:BAAALgAECgEJAQAAAA==.Hestonater:BAAALgAECgUJBwAAAA==.Hestra:BAAALgADCgMJBAAAAA==.Hexidecimal:BAAALgAECgQJBQAAAA==.',
Hi='Hidethetotem:BAABLgAECn8yAAMKAAkJDB5KDgDiAgAKAAkJDB5KDgDiAgAHAAEJHgoqGwApAAAAAA==.Hightops:BAAALgAECggJDgAAAA==.Hikari:BAACLgAFFH8OAAICAAYJpgw7MgBLAQACAAYJpgw7MgBLAQAuAAQKfx4AAgIACQlrHOAsAHACAAIACQlrHOAsAHACAAAA.Hiown:BAAALgAECgEJAgAAAA==.',
Ho='Holeliness:BAAALgAECggJEwAAAA==.Holybackshot:BAAALgAECgQJBgAAAA==.Holydisco:BAAALgADCgcJCQAAAA==.Holyhide:BAAALgAECgEJAQAAAA==.Holyrebel:BAAALgAECgYJBgAAAA==.Holyspike:BAABLgAECn8lAAIKAAkJGxJGRACdAQAKAAkJGxJGRACdAQAAAA==.Holytard:BAAALgADCgYJBgAAAA==.Holytaren:BAABLgAECn8UAAIWAAgJ3RvVEwBwAgAWAAgJ3RvVEwBwAgAAAA==.Holytickles:BAABLgAECn8sAAMYAAkJ4hsCEwBeAgAYAAgJ+hsCEwBeAgAIAAkJsBewEgBIAgABLgAFFAcJHgAcAFQWAA==.Holytotem:BAAALgAECgEJAQAAAA==.Homerr:BAABLgAECn8pAAIaAAkJ+BRxSADIAQAaAAkJ+BRxSADIAQAAAA==.Honiahaka:BAABLgAECn9DAAIaAAkJBxDcRgDNAQAaAAkJBxDcRgDNAQAAAA==.Hottcakes:BAAALgAFFAEJAQABLgAFFAcJHgAcAFQWAA==.',
Hu='Huckster:BAABLgAECn8ZAAIEAAgJhQ52fwBkAQAEAAgJhQ52fwBkAQAAAA==.Humanoidholy:BAABLgAECn8fAAMCAAgJXSQ6CQBIAwACAAgJXSQ6CQBIAwABAAEJbgXWTQAYAAABLgAFFAUJFAAZAJgjAA==.Humanoidhunt:BAAALgAFFAIJAgABLgAFFAUJFAAZAJgjAA==.Humanoidvoid:BAACLgAFFH8UAAQZAAUJmCOTBwCOAQAZAAQJVCOTBwCOAQAMAAMJ9h18VgDrAAAjAAEJAAAjGAAAAAAuAAQKf1MABAwACQkFIz8HABoDAAwACQmdIj8HABoDABkACAnlH5QKAH8CACMACAkoCMMVAPwAAAAA.',
Hy='Hydrah:BAAALgAECgEJAQABLgAECgcJCgAGAAAAAA==.Hydrasoul:BAAALgAECgcJCAABLgAECgcJCgAGAAAAAA==.',
['Hö']='Hölyçow:BAAALgAECgEJAQAAAA==.',
Ic='Icedtea:BAAALgAECgcJBAAAAA==.Icicle:BAAALgADCgIJAgAAAA==.',
Id='Idunasil:BAAALgAECgEJAgAAAA==.',
Ih='Ihatemustard:BAABLgAECn8jAAIjAAkJ6RUfCAD2AQAjAAkJ6RUfCAD2AQAAAA==.',
Il='Illethan:BAAALgADCgYJBgAAAA==.Iloveketchup:BAAALgAFFAEJAQAAAA==.',
In='Inclination:BAAALgAECgEJAQAAAA==.Inoru:BAABLgAECn8bAAMYAAcJhRFRMQBXAQAYAAcJhRFRMQBXAQAIAAEJpwJjfAAcAAAAAA==.Insanity:BAAALgAECgUJCgAAAA==.Invidious:BAAALgAECgEJAwAAAA==.',
Ir='Irmaline:BAABLgAECn8lAAMIAAkJ8RZzHQDZAQAIAAkJ8RZzHQDZAQAYAAEJFRiaFABCAAAAAA==.',
It='Ithurtshuh:BAAALgAECgUJDQABLgAECgYJBgAGAAAAAA==.Itsmaam:BAAALgAECgMJBAAAAA==.Itzcannibal:BAACLgAFFH8GAAIaAAIJ6go1jgCDAAAaAAIJ6go1jgCDAAAuAAQKfy8AAxoACQk4G/4rAC0CABoACQk4G/4rAC0CACEAAgnVCux5AFoAAAAA.',
Ja='Jabbawockie:BAAALgAECgkJAwAAAA==.Jaekoby:BAAALgAECgIJAwABLgAECggJIgACAM0aAA==.Jakoby:BAAALgAECgUJBgABLgAECggJIgACAM0aAA==.Jandrisel:BAABLgAECn8cAAMOAAcJQgstBwDZAAAOAAcJQgstBwDZAAAJAAUJtgLxngByAAAAAA==.Jarhead:BAAALgAECgEJAgAAAA==.Jayzich:BAAALgADCgQJBwAAAA==.',
Je='Jeffee:BAAALgAECgIJCQAAAA==.Jequalsjosh:BAACLgAFFH8IAAIdAAMJoRxHBwDuAAAdAAMJoRxHBwDuAAAuAAQKfz0AAh0ACQkhIlgCALsCAB0ACQkhIlgCALsCAAAA.Jerk:BAAALgAFFAMJBAAAAA==.Jerp:BAAALgAECgIJAgAAAA==.Jesper:BAABLgAECn9GAAIKAAkJ5B9nCgAQAwAKAAkJ5B9nCgAQAwAAAA==.Jetz:BAAALgAECgEJAQAAAA==.Jezelle:BAACLgAFFH8WAAIcAAYJ0w2rGgD8AAAcAAYJ0w2rGgD8AAAuAAQKfyIAAhwACQn0Hg42ADQCABwACQn0Hg42ADQCAAAA.',
Ji='Jilara:BAABLgAECn86AAICAAkJBghBkwBMAQACAAkJBghBkwBMAQAAAA==.Jimmyjim:BAABLgAECn8iAAIFAAkJahC8FADNAAAFAAkJahC8FADNAAAAAA==.Jingying:BAAALgAECgQJBAAAAA==.',
Jo='Johnny:BAAALgADCgQJBAAAAA==.',
Jp='Jpepps:BAABLgAECn8vAAMcAAkJDRNjPwDfAQAcAAkJDRNjPwDfAQAlAAMJxwjoRQCeAAAAAA==.',
Jr='Jrose:BAAALgAECgQJBAAAAA==.',
Ju='Jul:BAAALgAECgIJAgAAAA==.',
['Jæ']='Jækobÿ:BAAALgAECgIJAgABLgAECggJIgACAM0aAA==.',
Ka='Kahlanrahl:BAAALgADCgMJAwAAAA==.Kaiatra:BAABLgAECn8mAAIfAAkJ2yOfAwCoAgAfAAkJ2yOfAwCoAgAAAA==.Kalasandria:BAAALgAECgEJAQAAAA==.Kaliguala:BAAALgAECgQJBgAAAA==.Katalaystar:BAAALgAECgcJEQABLgAECgkJKAAJAHYaAA==.Katare:BAAALgAECgMJAwAAAA==.Kaulder:BAAALgADCgUJBQAAAA==.Kaìju:BAABLgAECn8jAAICAAkJGyHYIQB/AgACAAkJGyHYIQB/AgAAAA==.Kaîju:BAAALgAECgIJAgAAAA==.',
Ke='Kellytgt:BAACLgAFFH8FAAIMAAMJYgz5agC2AAAMAAMJYgz5agC2AAAuAAQKfzkAAgwACQkAHKkUAJ0CAAwACQkAHKkUAJ0CAAAA.Kev:BAAALgADCgUJBQAAAA==.',
Kh='Khai:BAAALgAECgkJAQAAAA==.',
Ki='Kilaura:BAABLgAECn8ZAAIoAAgJWRAQJQCnAQAoAAgJWRAQJQCnAQAAAA==.Killian:BAAALgAECgEJAQAAAA==.Kilmandaros:BAAALgADCgcJEQAAAA==.Kippi:BAAALgAECgQJCwAAAA==.',
Kn='Knitebrite:BAAALgAECgIJAgAAAA==.',
Ko='Korhina:BAABLgAECn9GAAIDAAkJeyYfAQBZAwADAAkJeyYfAQBZAwAAAA==.Korobas:BAAALgAECgMJAwAAAA==.Koru:BAAALgAECgQJBQABLgAECgQJBgAGAAAAAA==.Kosumi:BAAALgADCggJDQAAAA==.',
Kr='Kronic:BAAALgAECgYJDQAAAA==.Kronmon:BAAALgAECgEJAQAAAA==.',
Ku='Kuroyukihime:BAABLgAECn84AAIFAAkJ/h7hGwC0AgAFAAkJ/h7hGwC0AgAAAA==.Kuwaii:BAABLgAECn8dAAIVAAcJuxjjKACfAQAVAAcJuxjjKACfAQABLgAECggJHgAOAA0gAA==.',
Ky='Kyarina:BAAALgAECgEJAQABLgAECgkJGQAIAEMHAA==.Kylis:BAAALgAECgQJBAAAAA==.Kyna:BAABLgAECn8ZAAIIAAkJQwfUPAAAAQAIAAkJQwfUPAAAAQAAAA==.Kyross:BAAALgADCgIJAgAAAA==.',
['Ké']='Kéya:BAAALgAECgYJDQAAAA==.',
La='Lashela:BAABLgAECn8XAAIaAAkJwgt+bwBhAQAaAAkJwgt+bwBhAQAAAA==.Laughter:BAABLgAECn8aAAMTAAkJUQj4WADrAAATAAkJZwf4WADrAAADAAQJMAZuNQCbAAAAAA==.Laurana:BAAALgADCgIJAgAAAA==.Laylah:BAAALgADCgIJAgAAAA==.Lazulie:BAABLgAECn8UAAIoAAYJdxKbMgBPAQAoAAYJdxKbMgBPAQAAAA==.',
Le='Leansipper:BAABLgAFFH8RAAIOAAUJ6hOEIQAUAQAOAAUJ6hOEIQAUAQAAAA==.Levoker:BAAALgAECgQJBAAAAA==.Lexapayne:BAAALgAECgYJEgABLgAFFAQJGAAaADcVAA==.',
Li='Lighthammer:BAAALgADCgEJAQAAAA==.Lilandra:BAAALgAECgYJDwABLgAECggJDgAGAAAAAA==.Lilcrocey:BAAALgAECgEJAQAAAA==.Lillianaxe:BAABLgAECn8XAAMkAAcJHRjEHwBWAQAkAAYJsBnEHwBWAQAEAAcJAA9NlAA+AQAAAA==.Lilyvain:BAAALgAECgUJCAAAAA==.Lireal:BAACLgAFFH8FAAIWAAMJRCMmDQDLAAAWAAMJRCMmDQDLAAAuAAQKfzYAAhYACQmOJbsAAMgDABYACQmOJbsAAMgDAAAA.Listerine:BAAALgAECggJCQAAAA==.Litercola:BAABLgAECn8UAAIIAAYJjgKsVACJAAAIAAYJjgKsVACJAAAAAA==.Livnod:BAAALgAECgUJCwAAAA==.',
Lo='Loddeye:BAAALgAECgYJCQABLgAECgkJLwAJAEELAA==.Loonfabio:BAAALgAECgIJAgABLgAFFAUJFAACACUjAA==.Loosescrew:BAAALgADCgMJBAAAAA==.Lorine:BAABLgAECn87AAIBAAkJbBvpCgAbAgABAAkJbBvpCgAbAgAAAA==.Lowkie:BAAALgADCgIJAgAAAA==.',
Lu='Luckside:BAAALgAECgQJBAABLgAECgkJHwAcAI0MAA==.Lunara:BAAALgAECgMJBgAAAA==.Lunasnow:BAAALgAECgQJBAAAAA==.Lunchtime:BAAALgAECgEJAQAAAA==.Luxe:BAAALgADCgEJAQAAAA==.',
Ly='Lyntot:BAAALgADCgEJAQAAAA==.',
['Ló']='Lókki:BAAALgAECgUJCAAAAA==.',
Ma='Madwe:BAABLgAECn8hAAMMAAgJrgdHlQD2AAAMAAgJcwZHlQD2AAAZAAMJcAbKUwBpAAAAAA==.Maelora:BAAALgADCgEJAQAAAA==.Mageab:BAABLgAFFH8QAAIFAAgJZiDYCACxAgAFAAgJZiDYCACxAgAAAA==.Magis:BAAALgADCgkJHgAAAA==.Malzzahar:BAAALgAECgQJBAAAAA==.Manimetal:BAABLgAECn8WAAICAAUJiwVNJQGNAAACAAUJiwVNJQGNAAAAAA==.Materia:BAAALgAECgcJBwAAAA==.',
Me='Meeralax:BAABLgAECn8WAAIaAAYJJgaKvADNAAAaAAYJJgaKvADNAAAAAA==.Melizza:BAAALgADCgMJAwAAAA==.Merckel:BAACLgAFFH8IAAIMAAMJMhroWgDfAAAMAAMJMhroWgDfAAAuAAQKfywAAgwACAk5IDYdAGUCAAwACAk5IDYdAGUCAAAA.Merckz:BAAALgAECgUJBQABLgAFFAMJCAAMADIaAA==.Merks:BAAALgAFFAEJAQAAAA==.Metalmonkey:BAAALgAECgYJCwAAAA==.',
Mi='Michello:BAABLgAECn8iAAIaAAkJ8B6hJwBBAgAaAAkJ8B6hJwBBAgAAAA==.Mickcowmoose:BAAALgADCgIJAgAAAA==.Millia:BAABLgAECn8sAAIFAAkJ8h87FwDOAgAFAAkJ8h87FwDOAgAAAA==.Mint:BAABLgAECn8jAAIWAAcJiyOMDwCfAgAWAAcJiyOMDwCfAgAAAA==.Mintberrytea:BAAALgAECgUJBwABLgAECgcJIwAWAIsjAA==.Mintchaitea:BAABLgAECn8jAAILAAkJ/iEpBQBYAwALAAkJ/iEpBQBYAwABLgAECgcJIwAWAIsjAA==.Misstress:BAABLgAECn9BAAMOAAkJcRDwJACkAQAOAAkJGhDwJACkAQAPAAQJ0w77OgC6AAAAAA==.Mizen:BAAALgADCgUJCAAAAA==.',
Mo='Mogdor:BAAALgADCgUJBQAAAA==.Monkussy:BAAALgAECgIJAgAAAA==.Moonhunt:BAAALgAECgUJCwAAAA==.Moonly:BAACLgAFFH8GAAIiAAMJwAROKQCQAAAiAAMJwAROKQCQAAAuAAQKfyYAAiIACQlhDDAcALsBACIACQlhDDAcALsBAAAA.Morrag:BAABLgAECn89AAMcAAkJWw6NBQBlAQAcAAkJWw6NBQBlAQAbAAEJjAYbQgAuAAAAAA==.',
Mu='Murdumurdu:BAAALgAECgUJCAAAAA==.Murkblade:BAAALgADCgYJBgABLgAECgcJHgAMAKIVAA==.Murphee:BAAALgAECgEJAgAAAA==.Musho:BAAALgADCgYJEgAAAA==.Mustakrakish:BAAALgAECgEJAQAAAA==.',
My='Myn:BAABLgAECn8XAAIJAAkJwhk2FgCWAgAJAAkJwhk2FgCWAgAAAA==.Myw:BAAALgAECgcJBwABLgAFFAgJLAAKALkWAA==.',
['Mæ']='Mædenless:BAAALgAECgYJCQAAAA==.',
['Mí']='Mísfìt:BAABLgAECn88AAMKAAkJQRnXIQBEAgAKAAkJQRnXIQBEAgAHAAgJEQyZPQA/AQAAAA==.',
Na='Nakaito:BAABLgAECn8cAAIcAAgJ+AyPcABZAQAcAAgJ+AyPcABZAQABLgAECgkJPwAdAA8bAA==.Narcoleptic:BAACLgAFFH8YAAIUAAUJjBOVBgAYAQAUAAUJjBOVBgAYAQAuAAQKf0QABBQACQkcGWUHAIECABQACQkcGWUHAIECABUACAmFFg0nAKoBACcABQkQCFQvAJ0AAAAA.Nashty:BAAALgAECgEJAQAAAA==.Nazalzin:BAAALgAECgMJAwAAAA==.',
Ne='Neocracy:BAAALgADCgYJCwABLgAECggJFAAWAN0bAA==.Nex:BAAALgADCgYJCAAAAA==.',
Ni='Niceshield:BAAALgAECgEJBgAAAA==.Nightmarexx:BAACLgAFFH8VAAIXAAUJZh5dGgBDAQAXAAUJZh5dGgBDAQAuAAQKf04AAhcACAmnIb8KAHgCABcACAmnIb8KAHgCAAAA.Nightsawdy:BAABLgAECn80AAMaAAgJTB01CAB7AQAaAAcJ3R01CAB7AQAiAAcJfBIpJQB0AQAAAA==.Nightsnake:BAAALgAECgMJAwAAAA==.Niightstorm:BAABLgAECn8pAAMaAAcJQBzhNQAGAgAaAAcJQBzhNQAGAgAiAAQJbBL7PwDIAAAAAA==.Nikwillig:BAAALgAECggJDQAAAA==.Nilveron:BAAALgADCgcJCQAAAA==.Nitefire:BAAALgAECgQJAgAAAA==.Nitélifé:BAAALgAECgEJAgAAAA==.',
Nj='Njörðr:BAAALgAECgYJEgAAAA==.',
No='Nocturnum:BAABLgAFFH8IAAIXAAMJhQ7XKQDeAAAXAAMJhQ7XKQDeAAABLgAFFAQJGwAFAOYbAA==.Noxmortis:BAAALgAFFAMJBAAAAA==.',
Nt='Ntadadarknes:BAAALgAECgIJBAABLgAECgkJLwAJAEELAA==.',
Oo='Ooblidoom:BAAALgAECgEJAQABLgAECgkJUAAnAIITAA==.',
Op='Opalinnas:BAABLgAECn8oAAMJAAkJdhooFwCNAgAJAAkJdhooFwCNAgAOAAUJeQgqXQCiAAAAAA==.',
Oz='Ozath:BAAALgAECgQJBgAAAA==.',
Pa='Pallyandtank:BAAALgAFFAEJAQAAAA==.Passionfruit:BAAALgAFFAEJAQAAAA==.',
Pe='Peachtea:BAAALgAECgQJEgAAAA==.',
Ph='Phatshaman:BAABLgAECn8UAAIHAAgJbQeDUQDyAAAHAAgJbQeDUQDyAAAAAA==.Phæryll:BAAALgADCgUJBgAAAA==.',
Pi='Pirodeath:BAAALgAECgcJCgAAAA==.',
Pl='Place:BAAALgAECgIJAgAAAA==.',
Po='Poisonclaw:BAAALgAECgIJBAAAAA==.Poprotonix:BAABLgAECn8fAAICAAgJPxZuTgDcAQACAAgJPxZuTgDcAQAAAA==.Pozessedkaos:BAAALgAECgQJBAAAAA==.',
Pr='Praecantrix:BAAALgAECgEJBQAAAA==.Prath:BAAALgADCgEJAQAAAA==.Pray:BAABLgAECn9DAAIoAAkJBCSbAgCKAwAoAAkJBCSbAgCKAwAAAA==.Priestyballz:BAAALgAECgYJBgAAAA==.Prodarkangel:BAABLgAECn8bAAMlAAkJIgl1FwDnAAAlAAkJIgl1FwDnAAAcAAMJaAOeGAFPAAAAAA==.',
Pu='Pubis:BAAALgAECgYJDgAAAA==.Puckllane:BAABLgAECn8aAAICAAkJ5RdiQQAhAgACAAkJ5RdiQQAhAgAAAA==.Punkbeer:BAAALgAECgEJAQAAAA==.Punkin:BAAALgAECgUJCwAAAA==.',
Py='Pyre:BAABLgAECn89AAIoAAkJSQ+vIgC5AQAoAAkJSQ+vIgC5AQABLgADCgUJBQAGAAAAAA==.Pyroth:BAAALgAECgEJAQAAAA==.',
['Pó']='Pó:BAAALgADCgIJBAABLgAECgkJHwAcAI0MAA==.',
Qu='Quefstank:BAAALgADCgUJCAAAAA==.Quivver:BAAALgAECgQJAgAAAA==.',
Ra='Rabmaxx:BAABLgAECn84AAIZAAkJRhFfAwBbAQAZAAkJRhFfAwBbAQAAAA==.Radren:BAAALgADCgEJAQAAAA==.Rajinazn:BAAALgAECgYJBgAAAA==.Rattchett:BAAALgAECgYJBgAAAA==.Ravenlight:BAABLgAFFH8FAAICAAQJWA7UUQAMAQACAAQJWA7UUQAMAQAAAA==.Ravenwynnd:BAABLgAECn8mAAImAAkJuyKIBADRAgAmAAkJuyKIBADRAgAAAA==.Ravix:BAAALgADCgQJBAAAAA==.Raynelock:BAABLgAECn8wAAMlAAkJgRA0CwCNAQAlAAkJgRA0CwCNAQAcAAIJtQcZCQFKAAAAAA==.Raynman:BAABLgAECn9DAAIKAAkJdxVAJgApAgAKAAkJdxVAJgApAgAAAA==.Razgriz:BAAALgAECgEJAQAAAA==.Razix:BAABLgAECn8zAAQVAAkJfxRYIADWAQAVAAkJfxRYIADWAQAnAAYJ6wkZGQCOAAAUAAMJYwclPACJAAAAAA==.',
Re='Realist:BAAALgAECgMJBAAAAA==.Refrigtuitor:BAACLgAFFH8gAAMFAAYJxw0YYwAcAQAFAAYJxw0YYwAcAQApAAIJuAIZBgBiAAAuAAQKfz8ABAUACQmEH+AgAJsCAAUACQmEH+AgAJsCAA0ABQmDCGQOAN0AACkAAQk8EK4TADYAAAAA.Reija:BAAALgAECgEJAgAAAA==.Repentance:BAAALgADCgEJAQABLgAECgkJMwAgAOIXAA==.Revealed:BAAALgADCgEJAQAAAA==.Reyeda:BAAALgADCgUJBQAAAA==.Rezzarn:BAAALgAECgEJAQAAAA==.',
Rh='Rhun:BAAALgAECgYJCQAAAA==.Rhyzer:BAABLgAECn8yAAMTAAgJDB5aAgDEAQATAAgJDB5aAgDEAQAmAAEJJQ1bRQAuAAAAAA==.',
Ri='Rileyksufan:BAABLgAECn8VAAIaAAkJhg4yfwBBAQAaAAkJhg4yfwBBAQAAAA==.Rinas:BAACLgAFFH8FAAIZAAIJpxcnIQCSAAAZAAIJpxcnIQCSAAAuAAQKfzYAAxkACQm4IpQDABwDABkACQm4IpQDABwDAAwAAgmfDckUATUAAAAA.Rivendell:BAAALgAECgQJBgAAAA==.Rivenlynn:BAAALgADCgEJAQAAAA==.',
Ro='Rolando:BAAALgAECgEJAgABLgAECgcJHwATAGYiAA==.Root:BAAALgAECgYJDAABLgAFFAQJEAAEAFweAA==.',
Ru='Rubioxis:BAAALgADCgYJBgAAAA==.',
Ry='Rymarri:BAAALgADCgkJCQAAAA==.',
Sa='Sabazia:BAACLgAFFH8NAAIkAAMJMhsqIADmAAAkAAMJMhsqIADmAAAuAAQKfzsAAiQACQkXILkHAJ0CACQACQkXILkHAJ0CAAAA.Sacrificer:BAAALgAECgMJAwAAAA==.Sairalindë:BAABLgAECn8oAAMaAAkJrAjbEwDYAAAaAAkJrAjbEwDYAAAhAAMJpAA3hgA2AAAAAA==.Saleath:BAAALgAECgEJAwAAAA==.Salios:BAABLgAFFH8NAAIcAAQJNB6wFwAzAQAcAAQJNB6wFwAzAQAAAA==.Sallydisco:BAAALgAECgMJAwABLgAFFAQJCgADAN8hAA==.Sanctifier:BAAALgAECgQJDQAAAA==.Saraneth:BAAALgAECgEJAQABLgAFFAMJBQAWAEQjAA==.',
Sc='Scandrel:BAAALgAECgQJBAABLgAFFAYJHQAEAJ8fAA==.Scrept:BAAALgAFFAEJAQAAAA==.Scynix:BAEBLgAECn8pAAMVAAkJdRijGgABAgAVAAkJdRijGgABAgAUAAEJsgFhTgAiAAAAAA==.',
Se='Sedaline:BAAALgAECgQJBgAAAA==.Sephie:BAAALgADCgQJAQAAAQ==.Serenas:BAAALgAECgQJBAABLgAFFAEJAQAGAAAAAA==.Serenilock:BAAALgADCgMJAwAAAA==.Serfdog:BAAALgADCgcJDAAAAA==.Servoker:BAACLgAFFH8VAAIUAAYJXxvgEACIAQAUAAYJXxvgEACIAQAuAAQKfyUAAxUACAnbICEKANQCABUACAnbICEKANQCABQABwkkGrwVAPABAAAA.Setani:BAAALgADCgIJAgAAAA==.',
Sh='Shabzkaw:BAAALgADCgUJBQAAAA==.Shabzyt:BAAALgADCgQJBAAAAA==.Shaddows:BAAALgAECgkJEwAAAA==.Shaienne:BAAALgAECgMJAwAAAA==.Shambussy:BAAALgAECgEJAQAAAA==.Shamfore:BAAALgADCgUJBgAAAA==.Shamrockshak:BAACLgAFFH8GAAIKAAIJKSYXQwDbAAAKAAIJKSYXQwDbAAAuAAQKfyIAAgoABwmMIKMhAEUCAAoABwmMIKMhAEUCAAAA.Shaze:BAAALgADCggJEAAAAA==.Shenuton:BAABLgAECn8XAAICAAgJlgrCpgAtAQACAAgJlgrCpgAtAQAAAA==.Shieldinterd:BAAALgAECgMJAgABLgAECgcJHgAMAKIVAA==.Shiftkicker:BAAALgADCgMJAwAAAA==.Shocktherapy:BAAALgAECgEJAQAAAA==.Shockthêràpy:BAACLgAFFH8JAAIKAAMJjwxsXACTAAAKAAMJjwxsXACTAAAuAAQKfzAABAoACQlbGG0nAPMBAAoACQlbGG0nAPMBAAcAAwkWFxZqAKkAACAAAQlPCkYrADgAAAAA.Shoes:BAABLgAECn89AAQiAAkJTSWdAgAdAwAiAAkJxiOdAgAdAwAhAAgJIx/cDQDVAgAaAAgJ9SLVKAA7AgAAAA==.Shoresy:BAAALgAECgEJAgAAAA==.Shtdruid:BAAALgAECgcJDAAAAA==.Shyanni:BAAALgADCgMJAwAAAA==.Shöçkér:BAAALgAECgcJEwAAAA==.',
Si='Siaana:BAAALgADCgUJBQABLgAFFAMJDQAkADIbAA==.Sibearian:BAABLgAECn8fAAQPAAgJ6Bg6EgDNAQAPAAgJ6Bg6EgDNAQAQAAYJ0ApYJwDSAAAOAAIJPwSEdQBNAAABLgAFFAIJAgAGAAAAAA==.Simi:BAACLgAFFH8YAAIaAAQJNxXXFAAxAQAaAAQJNxXXFAAxAQAuAAQKfy0AAhoACQm1GdAnAEACABoACQm1GdAnAEACAAAA.',
Sk='Skrubzz:BAABLgAECn8ZAAMDAAgJIQbpIAA4AQADAAgJIQbpIAA4AQATAAQJzgKHhwChAAAAAA==.Skôrn:BAABLgAECn8wAAIFAAcJLQ8JmwBDAQAFAAcJLQ8JmwBDAQAAAA==.',
Sl='Sloppynachos:BAABLgAECn8pAAIXAAgJRhdmGgAvAgAXAAgJRhdmGgAvAgAAAA==.Slyman:BAAALgADCgUJBQABLgAECgYJBwAGAAAAAA==.',
Sm='Smithnwesson:BAAALgAECgIJAgAAAA==.Smokesçreen:BAACLgAFFH8UAAIZAAQJ/BNmCADdAAAZAAQJ/BNmCADdAAAuAAQKf0UAAxkACQkEIZoFAOYCABkACQkEIZoFAOYCAAwABQm6BcXVAIkAAAAA.',
Sn='Snowhoof:BAAALgADCgUJBQAAAA==.',
So='Soccerqt:BAAALgAECgYJBgAAAA==.Sogerä:BAABLgAECn8XAAIUAAgJIQWJHwD5AAAUAAgJIQWJHwD5AAAAAA==.Soonerpride:BAABLgAECn8cAAICAAgJBCPzLABNAgACAAgJBCPzLABNAgAAAA==.Sorinmarkov:BAAALgAFFAIJAgAAAA==.Source:BAAALgAECgUJCAABLgAECgkJHgAHAIQPAA==.',
Sp='Spearminttea:BAAALgAECgcJCwAAAA==.Spellbreakr:BAABLgAFFH8KAAIFAAYJjwx7FQBlAQAFAAYJjwx7FQBlAQAAAA==.Spellumgud:BAAALgAECgQJBgAAAA==.Sprockette:BAAALgAECgMJBgAAAA==.',
Sq='Squiby:BAABLgAECn84AAMYAAkJoCLkBgDjAgAYAAkJoCLkBgDjAgAIAAIJmRX+ZwCNAAAAAA==.Squizzy:BAAALgAECgEJAQAAAA==.',
St='Stabfore:BAABLgAECn8mAAMXAAkJKBVIEAAqAgAXAAkJKBVIEAAqAgAdAAEJJgTILAAlAAAAAA==.Standaside:BAAALgAECgIJBAAAAA==.Steellidan:BAAALgADCgEJAQAAAA==.Stinky:BAABLgAECn8XAAIeAAgJkQl3DgAlAQAeAAgJkQl3DgAlAQAAAA==.Stix:BAACLgAFFH8UAAIXAAQJih7lFABkAQAXAAQJih7lFABkAQAuAAQKfy0AAxcACQl6HCsNAFQCABcACQl6HCsNAFQCAB4ABAmnFTIUAMsAAAAA.Stoya:BAAALgAECgYJCgABLgAFFAMJBQAWAEQjAA==.Stuef:BAABLgAECn82AAIHAAkJGyGPCgC2AgAHAAkJGyGPCgC2AgAAAA==.Stuefagos:BAAALgAECgQJBwAAAA==.Stuefester:BAABLgAECn8gAAMEAAkJNiBQIACIAgAEAAkJNiBQIACIAgAkAAcJ4QmFNADHAAAAAA==.Stueflare:BAAALgAECggJEAAAAA==.Stueflip:BAAALgADCgIJAgAAAA==.Stunsturds:BAABLgAECn8dAAMLAAYJQiAVHgApAgALAAYJQiAVHgApAgARAAEJ2AF+mQAaAAABLgAECgcJHgAMAKIVAA==.Stäirs:BAABLgAECn9CAAITAAkJ5B1tDwB/AgATAAkJ5B1tDwB/AgAAAA==.',
Su='Summerlily:BAAALgADCgYJBgAAAA==.',
Sv='Svaja:BAAALgAECgIJAQABLgAECgkJJAAUAOwLAA==.',
Sy='Sylaria:BAEALgAECgYJDAAAAA==.Syreline:BAAALgAECgEJAgAAAA==.',
['Sá']='Sáble:BAACLgAFFH8FAAIBAAMJDAJkEwBfAAABAAMJDAJkEwBfAAAuAAQKfzAAAwEACQn6CWUeACEBAAIACAnNCCGpACkBAAEACQlNCGUeACEBAAAA.',
['Sí']='Síñ:BAAALgAECgMJBAABLgAECggJIgAcAFIaAA==.',
['Sî']='Sîn:BAAALgADCgEJAQABLgAECggJIgAcAFIaAA==.',
['Sï']='Sïn:BAABLgAECn8iAAIcAAgJUhq+PADpAQAcAAgJUhq+PADpAQAAAA==.',
['Sý']='Sýlver:BAAALgAECgQJBQAAAA==.',
Ta='Taereachye:BAACLgAFFH8HAAIWAAMJ3xdeLgDAAAAWAAMJ3xdeLgDAAAAuAAQKfxcAAhYABwk5JAYKANMCABYABwk5JAYKANMCAAEuAAUUBAkIAAsAgBUA.Tailon:BAAALgADCgYJBgAAAA==.Taintedlove:BAAALgADCgYJBgAAAA==.Talenelat:BAAALgADCgcJCwAAAA==.Talikas:BAAALgAECggJEAABLgAFFAMJBQAMAGIMAA==.Tankin:BAAALgADCgMJAwAAAA==.Tantric:BAAALgAECgIJAgABLgAECggJCQAGAAAAAA==.Tarathiel:BAAALgADCgQJBAAAAA==.Tarpalantir:BAAALgAECgcJCgAAAA==.Taurne:BAACLgAFFH8XAAIJAAcJGQwPHwBhAQAJAAcJGQwPHwBhAQAuAAQKfx4AAgkABwmzGYEwAOkBAAkABwmzGYEwAOkBAAAA.',
Te='Technique:BAAALgAECgIJBQAAAA==.Teebags:BAAALgADCgEJAQAAAA==.Teknoman:BAACLgAFFH8SAAMTAAMJ5xvSMADsAAATAAMJ5xvSMADsAAADAAEJVQFpGQAjAAAuAAQKfz0AAhMACQkIIacKALsCABMACQkIIacKALsCAAAA.Telmarine:BAAALgAECgMJAwAAAA==.Tempered:BAABLgAECn8YAAMmAAYJMhyaFwCeAQAmAAYJMhyaFwCeAQATAAQJRRvLZQDFAAAAAA==.Terlemen:BAAALgAECgUJBQAAAA==.Tetsumi:BAAALgADCgYJCQABLgAECggJDgAGAAAAAA==.',
Th='Thaddeus:BAAALgAECgEJAQABLgAFFAYJGAAGAAAAAQ==.Thaitea:BAAALgAECgUJBgAAAA==.Thal:BAAALgAECgMJAwAAAA==.Thalan:BAAALgADCgEJAQAAAA==.Thalindra:BAABLgAECn8uAAIaAAgJ6hpnOQD4AQAaAAgJ6hpnOQD4AQAAAA==.Tharain:BAAALgAECgQJAgAAAA==.Thebigbeast:BAABLgAFFH8IAAIBAAIJ4hWNBQCDAAABAAIJ4hWNBQCDAAABLgAFFAcJHgAcAFQWAA==.Thecurt:BAABLgAECn9BAAIRAAkJnyRKAgA7AwARAAkJnyRKAgA7AwAAAA==.Thedammed:BAAALgADCgEJAQAAAA==.Theholylight:BAAALgAECgYJDQAAAA==.Thehuzz:BAABLgAECn8YAAMKAAkJPREzCQAdAQAKAAgJpQ8zCQAdAQAgAAEJjgkHDwApAAAAAA==.Thermidor:BAABLgAECn8gAAIiAAkJYBV5CQBLAgAiAAkJYBV5CQBLAgAAAA==.Thorsamie:BAAALgAECggJDgAAAA==.Thrasios:BAAALgAECgIJAgABLgAFFAIJBgAZAMYYAA==.Thundercunti:BAAALgADCgYJDAABLgAFFAIJBQAXAKgWAA==.Thyralizen:BAAALgADCgQJBAAAAA==.',
Ti='Tiamatt:BAAALgADCgIJBAAAAA==.Ticktock:BAAALgAECgIJAgAAAA==.Timaeus:BAABLgAECn8XAAITAAcJAQIuhQBpAAATAAcJAQIuhQBpAAAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Titanlock:BAAALgAECgYJCgAAAA==.',
Tk='Tkdfath:BAAALgAECggJEgAAAA==.',
To='Torvia:BAAALgAECgYJDAAAAA==.Totemix:BAAALgADCgcJEgAAAA==.Totemsoul:BAAALgAECgEJAwABLgAECgcJCgAGAAAAAA==.',
Tr='Trisinz:BAABLgAECn8lAAIOAAgJ0RcEHgDYAQAOAAgJ0RcEHgDYAQAAAA==.Trixa:BAAALgADCgMJAwAAAA==.',
Tu='Tuerto:BAABLgAECn8VAAIaAAYJpg96lgATAQAaAAYJpg96lgATAQAAAA==.Turbojohnson:BAAALgAECgQJBgAAAA==.Turk:BAABLgAECn9EAAMMAAkJtRefJQA3AgAMAAkJtRefJQA3AgAZAAEJCQ/BcwAxAAAAAA==.Turkish:BAABLgAECn9AAAMEAAkJZBqBMgA0AgAEAAkJZBqBMgA0AgAfAAEJ7gYcQQAlAAAAAA==.Turtledisco:BAACLgAFFH8KAAIDAAQJ3yGtEwAHAQADAAQJ3yGtEwAHAQAuAAQKfycAAgMACQnSH7sDABcDAAMACQnSH7sDABcDAAAA.',
Ty='Tychaa:BAAALgAECgQJAgAAAA==.Tylat:BAAALgADCgEJBQAAAA==.Tyranax:BAACLgAFFH8FAAIoAAIJ1wo2PwB8AAAoAAIJ1wo2PwB8AAAuAAQKfz0ABCgACQnlG2gKAMkCACgACQneGmgKAMkCAAgABgnVH1IcAPoBABgABwkxE2gzAEwBAAAA.Tyyregade:BAAALgADCgkJCgABLgAECggJDgAGAAAAAA==.',
Uj='Ujimas:BAAALgAECgEJAgAAAA==.',
Us='Us:BAAALgAECggJCQAAAA==.',
Uz='Uzzi:BAAALgAECgEJAQAAAA==.',
Va='Vadose:BAABLgAECn8gAAIcAAcJwQqmgQBXAQAcAAcJwQqmgQBXAQABLgAFFAQJGAAaADcVAA==.Vales:BAAALgAECgYJEAABLgAFFAMJBQAaAMABAA==.Valsavis:BAABLgAECn8gAAIOAAgJkxSrIgC0AQAOAAgJkxSrIgC0AQAAAA==.Valytrois:BAABLgAECn8VAAIcAAcJlwmysQD1AAAcAAcJlwmysQD1AAAAAA==.Vanra:BAAALgAECgkJBQAAAA==.Varinix:BAAALgADCgMJBQAAAA==.',
Ve='Veggiebaha:BAAALgADCgIJAgAAAA==.Veiksla:BAABLgAECn8kAAMUAAkJ7AsIGgA4AQAUAAgJwAgIGgA4AQAnAAIJSAjHAwBXAAAAAA==.Velore:BAAALgADCgcJDAAAAA==.Vengerr:BAAALgAECgUJBgAAAA==.Verace:BAAALgAECgcJAQAAAA==.Verradic:BAABLgAECn8aAAMcAAgJsQf/DADIAAAcAAgJNAf/DADIAAAlAAUJ4AXKJgB/AAAAAA==.',
Vi='Vitur:BAABLgAECn9KAAIMAAkJWSGXFACeAgAMAAkJWSGXFACeAgAAAA==.',
Vo='Voidhunter:BAABLgAECn8VAAIMAAcJGwrplQD1AAAMAAcJGwrplQD1AAAAAA==.Voidweaver:BAAALgAECgMJBQAAAA==.Volaine:BAABLgAECn8xAAMcAAgJXhS0CQAAAQAcAAcJ4hO0CQAAAQAbAAMJABZ9CgBAAAAAAA==.Volt:BAABLgAECn8zAAIgAAkJ4heeCgAQAgAgAAkJ4heeCgAQAgAAAA==.Volumoso:BAAALgAECgYJBgAAAA==.Volwryn:BAAALgAECgUJCAABLgAECggJCQAGAAAAAA==.',
Vy='Vynarian:BAABLgAECn8tAAIFAAgJfBPsdgCLAQAFAAgJfBPsdgCLAQAAAA==.',
['Vâ']='Vâljean:BAAALgADCgMJAwAAAA==.',
['Vô']='Vôx:BAAALgAECgIJAgABLgAECgkJIgASAIoYAA==.',
['Vö']='Vöx:BAAALgAECgEJAQABLgAECgkJIgASAIoYAA==.',
Wa='Warbeard:BAABLgAECn8oAAITAAkJ8gvrLQCZAQATAAkJ8gvrLQCZAQAAAA==.',
We='Wetasstotem:BAAALgAECgEJAQABLgAFFAcJHgAcAFQWAA==.',
Wi='Wizwizx:BAAALgADCgUJBgAAAA==.',
Wr='Wreckbums:BAABLgAFFH8PAAIEAAMJiB9FLgDjAAAEAAMJiB9FLgDjAAAAAA==.Wreckd:BAABLgAECn8iAAMMAAcJnhhkRgC0AQAMAAcJnhhkRgC0AQAZAAIJIgxtdQAqAAAAAA==.',
Wy='Wyth:BAAALgAECgQJBQABLgAECgQJBgAGAAAAAA==.',
Xa='Xanthad:BAAALgADCgEJAQAAAA==.',
Xb='Xb:BAAALgAECgQJAgAAAA==.',
Xi='Xitãozinho:BAAALgAECgUJBwAAAA==.',
Xo='Xolair:BAAALgAECgYJDgAAAA==.',
Ya='Yaalia:BAABLgAECn8gAAMCAAcJbgYUIQB0AAACAAcJbgYUIQB0AAAWAAIJZwIKowAiAAAAAA==.Yaan:BAABLgAECn8gAAIHAAgJMQpKRwAXAQAHAAgJMQpKRwAXAQAAAA==.Yalane:BAAALgAECgQJBAAAAA==.',
Yo='Yoba:BAAALgAECgMJAwAAAA==.Yoshira:BAAALgADCgQJBAAAAA==.',
['Yö']='Yör:BAAALgAECgEJAQAAAA==.',
Za='Zain:BAABLgAECn9GAAQmAAkJNx35BwB2AgAmAAkJNx35BwB2AgATAAYJGA5fWQBIAQADAAIJKA0SSgBNAAAAAA==.Zandibar:BAABLgAECn8xAAITAAgJTB+QAgC3AQATAAgJTB+QAgC3AQAAAA==.Zaptoasted:BAAALgAECgUJBgAAAA==.Zaroff:BAAALgAECgYJCgAAAA==.',
Ze='Zedadiah:BAAALgADCgEJAQAAAA==.Zelah:BAAALgAECgQJBAAAAA==.Zellezugtail:BAAALgAECgQJBAABLgAECgkJKwAcAGUKAA==.Zenessa:BAAALgADCgYJBgAAAA==.',
Zi='Zillah:BAAALgAECgEJAQABLgAECgcJCgAGAAAAAA==.Zinder:BAABLgAECn8oAAIFAAkJsQ48XQDHAQAFAAkJsQ48XQDHAQAAAA==.',
Zu='Zuggie:BAABLgAECn8rAAIcAAkJZQrSgQA1AQAcAAkJZQrSgQA1AQAAAA==.Zugtail:BAABLgAECn8YAAIVAAYJUwMqCgCFAAAVAAYJUwMqCgCFAAABLgAECgkJKwAcAGUKAA==.Zurtrinik:BAACLgAFFH8gAAIDAAgJfB+JBAAiAgADAAgJfB+JBAAiAgAuAAQKfyUAAgMACAmZJDwCAE0DAAMACAmZJDwCAE0DAAAA.',
Zy='Zylith:BAAALgAECgYJCwABLgAECgkJMwAgAOIXAA==.Zyntalla:BAAALgAECgUJBQAAAA==.',
Zz='Zzonked:BAABLgAECn8pAAMEAAkJCwjCkABEAQAEAAkJzwbCkABEAQAkAAIJ/gtGPwBSAAAAAA==.',
['Zê']='Zêp:BAAALgAECgEJAgAAAA==.',
['Zø']='Zøømies:BAABLgAECn8xAAMMAAkJhhdDMAAFAgAMAAkJUhdDMAAFAgAjAAYJFQ/XFgDvAAAAAA==.',
['Är']='Äréa:BAAALgADCgkJCQAAAA==.',
['Äs']='Äshnärd:BAACLgAFFH8OAAIKAAMJqyOMLgAoAQAKAAMJqyOMLgAoAQAuAAQKfzQAAgoACQlUJHEFAFwDAAoACQlUJHEFAFwDAAAA.',
['Ða']='Ðar:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðoogle:BAABLgAECn8iAAMHAAkJ8RgjJQDAAQAHAAkJ8RgjJQDAAQAKAAIJjR4EEACnAAABLgAECgMJBgAGAAAAAA==.',
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
