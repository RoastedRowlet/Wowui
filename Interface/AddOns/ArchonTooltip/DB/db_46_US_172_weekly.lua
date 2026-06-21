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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Protection','DeathKnight-Unholy','Mage-Frost','Unknown-Unknown','Shaman-Elemental','Priest-Holy','Druid-Restoration','Monk-Mistweaver','DemonHunter-Devourer','Mage-Arcane','Druid-Balance','Druid-Guardian','Druid-Feral','Monk-Brewmaster','Monk-Windwalker','Warrior-Fury','Evoker-Preservation','Evoker-Augmentation','Paladin-Holy','Rogue-Subtlety','Priest-Shadow','DemonHunter-Havoc','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Rogue-Assassination','Rogue-Outlaw','Shaman-Restoration','DeathKnight-Frost','Shaman-Enhancement','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Vengeance','DeathKnight-Blood','Warlock-Destruction','Warrior-Arms','Evoker-Devastation','Priest-Discipline','Mage-Fire',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=46,date='2026-06-20',data={Ad='Adrador:BAABLgAECn8zAAMBAAkJqCSrAQAsAwABAAkJqCSrAQAsAwACAAIJZxTtEwFvAAAAAA==.Adrenaline:BAACLgAFFH8hAAIDAAUJ2iIlCgCOAQADAAUJ2iIlCgCOAQAuAAQKfzkAAgMACQm8JBgDAAkDAAMACQm8JBgDAAkDAAAA.',
Ae='Aelik:BAACLgAFFH8PAAIEAAMJbBa2igD0AAAEAAMJbBa2igD0AAAuAAQKfykAAgQACAnwHb04ABwCAAQACAnwHb04ABwCAAAA.Aeolian:BAAALgADCgYJCQAAAA==.',
Ah='Ahkimbo:BAAALgADCgUJBQAAAA==.',
Ai='Airolanah:BAAALgAECgUJBQAAAA==.',
Al='Alayssa:BAABLgAECn8tAAIFAAkJXSCzHACwAgAFAAkJXSCzHACwAgAAAA==.Alda:BAAALgAECgQJAgAAAA==.Allarius:BAAALgAECgEJAQAAAA==.Allioops:BAAALgADCgUJBQABLgAECgMJBAAGAAAAAA==.Alnima:BAACLgAFFH8GAAIHAAMJ/QGZQgB/AAAHAAMJ/QGZQgB/AAAuAAQKfxkAAgcACAnOCLk5AGgBAAcACAnOCLk5AGgBAAAA.',
Am='Amilee:BAAALgAECgUJDwAAAA==.Amishhunter:BAAALgADCgEJAQAAAA==.Amoondai:BAACLgAFFH8RAAIIAAMJMSKHFQAVAQAIAAMJMSKHFQAVAQAuAAQKfy8AAggACQmjIhEDAGQDAAgACQmjIhEDAGQDAAAA.Amoondrin:BAABLgAECn8zAAIJAAkJLwnXTQBXAQAJAAkJLwnXTQBXAQAAAA==.Amplifier:BAAALgADCgUJBQAAAA==.',
An='Analiya:BAAALgADCgMJBAAAAA==.Antichurch:BAAALgADCgEJAQAAAA==.Antisnow:BAAALgAECgIJBQABLgAECgcJCgAGAAAAAA==.Antregon:BAAALgADCgQJBwAAAA==.',
Ar='Araviin:BAABLgAFFH8LAAIFAAMJbQrVigDEAAAFAAMJbQrVigDEAAAAAA==.Arazen:BAAALgAECgIJAwAAAA==.Arcillias:BAAALgADCgYJCAABLgAECgYJBwAGAAAAAA==.Arkride:BAAALgAECgEJAQAAAA==.Arlean:BAAALgAECgIJAgAAAA==.Arnadaz:BAAALgADCgEJAQABLgAFFAQJCAAKAIAVAA==.Arrogance:BAAALgADCgcJBwABLgAECggJCQAGAAAAAA==.Arthia:BAAALgAECgQJEAAAAA==.Arvidpally:BAAALgAECgQJBgAAAA==.',
As='Ashmehameha:BAAALgADCgQJAgABLgAFFAMJCAAEANoTAA==.Asinn:BAAALgAECgEJAQAAAA==.Asoosimov:BAAALgADCgEJAQAAAA==.',
At='Atredes:BAABLgAFFH8FAAILAAIJ8AYhiAByAAALAAIJ8AYhiAByAAAAAA==.Attima:BAABLgAECn9BAAIMAAkJWBHOAwDSAQAMAAkJWBHOAwDSAQAAAA==.',
Au='Aubriana:BAAALgADCgQJBAAAAA==.Aurøra:BAAALgADCgMJAwAAAA==.Auspex:BAABLgAECn8rAAMNAAkJxwncNgA6AQANAAkJ6QfcNgA6AQAOAAkJMAjVLwDtAAAAAA==.',
Av='Avaryn:BAACLgAFFH8cAAIJAAUJhhI/IwBAAQAJAAUJhhI/IwBAAQAuAAQKfzgAAgkACQmZIUQJACUDAAkACQmZIUQJACUDAAAA.',
Ax='Aximlii:BAAALgAECgIJAgAAAA==.',
Az='Azron:BAAALgAECgcJCAABLgAECggJDgAGAAAAAA==.',
Ba='Babavoss:BAAALgAECgkJAQAAAA==.Badarack:BAAALgAECgcJEwABLgAFFAMJBgAOAOohAA==.Badaracka:BAACLgAFFH8GAAIOAAMJ6iFaDQAlAQAOAAMJ6iFaDQAlAQAuAAQKfyQAAw4ACQkFJTUBAFADAA4ACQkFJTUBAFADAA8ABAnSEJYvAKQAAAAA.Badarackie:BAABLgAECn9DAAMQAAkJSCG2BwC6AgAQAAkJSCG2BwC6AgARAAkJDhVrGQDmAQABLgAFFAMJBgAOAOohAA==.Badash:BAABLgAECn8rAAMDAAgJBhufEADeAQADAAgJBhufEADeAQASAAEJMQSurQAvAAABLgAFFAMJCAAEANoTAA==.Bahamuth:BAABLgAECn9DAAICAAkJIB15IwB3AgACAAkJIB15IwB3AgAAAA==.Bakshi:BAAALgAECgEJBAAAAA==.Banký:BAAALgAECgEJAQAAAA==.Barbattos:BAACLgAFFH8cAAITAAUJ9xjuEQB3AQATAAUJ9xjuEQB3AQAuAAQKfzYAAxMACQkOJLcCADUDABMACQkOJLcCADUDABQAAQnkJNF+AGEAAAAA.Barnabas:BAAALgADCgYJBgABLgAECgYJBwAGAAAAAA==.Barragon:BAABLgAECn8VAAIVAAcJ5g8RNwByAQAVAAcJ5g8RNwByAQAAAA==.',
Be='Beans:BAAALgAECgQJBAAAAA==.Bearymanalow:BAAALgAECgMJBAAAAA==.Belfore:BAAALgAECgEJAQABLgAECgkJJgAWACgVAA==.Bethollbrew:BAAALgAECgYJDwAAAA==.Bexley:BAABLgAECn8tAAIBAAkJChoTCQBCAgABAAkJChoTCQBCAgAAAA==.',
Bi='Biggerbunny:BAACLgAFFH8JAAIXAAMJ6Ac8BABvAAAXAAMJ6Ac8BABvAAAuAAQKfzAAAhcACAmEFTUjAK8BABcACAmEFTUjAK8BAAAA.Binkter:BAAALgAECgIJBQABLgAECgIJAgAGAAAAAA==.',
Bl='Blackjax:BAAALgADCgEJAQAAAA==.Blacklok:BAAALgAECgUJEQABLgAECgkJNAAYAEElAA==.Blanne:BAAALgAECgEJAQAAAA==.Blargle:BAABLgAECn8uAAIZAAgJKQ+BXQCNAQAZAAgJKQ+BXQCNAQAAAA==.Blessedcross:BAAALgAECgMJBAAAAA==.Bleubahlz:BAAALgADCgcJBwABLgAECgMJAwAGAAAAAA==.Blinx:BAAALgAECgQJBwABLgAECggJDgAGAAAAAA==.Bloodrake:BAABLgAECn87AAIZAAkJHB6mDQDRAgAZAAkJHB6mDQDRAgAAAA==.Bloodreyne:BAAALgADCgEJAgAAAA==.Bloodseekr:BAAALgADCgcJDgAAAA==.Blueray:BAAALgAECgYJCAAAAA==.',
Bo='Boahan:BAAALgAECgMJBQABLgAECgUJCAAGAAAAAA==.Boggart:BAAALgAECgEJAQABLgAECgUJCAAGAAAAAA==.Bohein:BAAALgADCgEJAQAAAA==.Bolus:BAAALgAECgQJCAAAAA==.Botany:BAAALgAECgcJBwAAAA==.Bownafiedba:BAAALgADCgUJBQAAAA==.',
Br='Braneour:BAABLgAECn85AAMVAAkJwBpYDADJAgAVAAkJwBpYDADJAgACAAMJVBEQLQGDAAAAAA==.Brassballz:BAAALgAECgkJCQAAAA==.Browel:BAABLgAECn8aAAMaAAcJWBj4CAC3AQAaAAYJ3Rj4CAC3AQAbAAYJYQ59nQADAQAAAA==.Bruen:BAAALgAECgYJBwAAAA==.Bryci:BAAALgAECgcJEAAAAA==.',
Bu='Bubbloseven:BAABLgAECn8UAAMVAAgJGhGCKgC7AQAVAAgJGhGCKgC7AQABAAQJABsVHQAsAQAAAA==.Budank:BAAALgADCgMJAwAAAA==.Bumm:BAABLgAECn8aAAICAAYJzwj64wDZAAACAAYJzwj64wDZAAAAAA==.Bustybubbles:BAAALgADCgYJBgAAAA==.',
Bz='Bzspy:BAABLgAFFH8LAAISAAMJzwzhOgDHAAASAAMJzwzhOgDHAAAAAA==.',
Ca='Caalin:BAAALgAECgEJAgAAAA==.Cabooselul:BAAALgAECgQJCwAAAA==.Calibre:BAABLgAECn8eAAILAAcJohXnaABUAQALAAcJohXnaABUAQAAAA==.Calyptus:BAABLgAECn8fAAIbAAYJhApkrgDnAAAbAAYJhApkrgDnAAAAAA==.Caprious:BAACLgAFFH8bAAIEAAUJwxkrUABRAQAEAAUJwxkrUABRAQAuAAQKfzYAAgQACQnjJGsKABwDAAQACQnjJGsKABwDAAAA.Capylaura:BAABLgAECn8bAAIZAAcJwAocggA7AQAZAAcJwAocggA7AQAAAA==.Caratine:BAABLgAECn8fAAILAAgJtAuDewApAQALAAgJtAuDewApAQAAAA==.Cassandrar:BAABLgAECn8yAAQcAAkJGSQIAQA5AwAcAAgJMiQIAQA5AwAWAAYJtiBkHwCbAQAdAAEJphSKIwA6AAAAAA==.Cassandraw:BAAALgAECgYJBgABLgAECgkJMgAcABkkAA==.Cat:BAAALgADCgUJBQAAAA==.Cattlelac:BAAALgADCgUJCAAAAA==.Caymus:BAABLgAECn8zAAIJAAkJ8gg3UgBGAQAJAAkJ8gg3UgBGAQAAAA==.',
Ce='Celìa:BAABLgAECn8uAAIZAAkJLwnEYACFAQAZAAkJLwnEYACFAQAAAA==.Cess:BAAALgAECgEJAgAAAA==.',
Ch='Chaoticone:BAAALgADCgYJBgAAAA==.Chema:BAABLgAFFH8IAAIKAAQJgBVvLQAIAQAKAAQJgBVvLQAIAQAAAA==.Chestylarue:BAAALgAECgEJAQABLgAECggJEgAGAAAAAA==.Chfgaribaldi:BAAALgADCggJDgAAAA==.Chifore:BAAALgAECgEJAQAAAA==.Chills:BAAALgAECgcJEQAAAA==.Chillymage:BAAALgADCgYJBgAAAA==.Chosen:BAABLgAECn8YAAICAAYJRBdtYgC+AQACAAYJRBdtYgC+AQABLgAFFAUJHAAEAPsgAA==.Chpchop:BAAALgADCgIJAgAAAA==.Christy:BAAALgAECgQJAgAAAA==.Chugg:BAABLgAECn8fAAIeAAkJwgjsWgBNAQAeAAkJwgjsWgBNAQAAAA==.',
Ci='Ciaphus:BAABLgAECn8nAAICAAkJ0hRpRwDwAQACAAkJ0hRpRwDwAQAAAA==.Cinnamonster:BAAALgAECgcJDgAAAA==.',
Co='Coffeedemon:BAAALgADCgEJAQAAAA==.Coldslappins:BAABLgAECn8YAAIFAAgJZROdWwDLAQAFAAgJZROdWwDLAQAAAA==.Contagion:BAAALgAECgYJBQAAAA==.Convoke:BAABLgAECn8eAAINAAcJDSArFgBeAgANAAcJDSArFgBeAgAAAA==.Coragrr:BAAALgADCgcJDQAAAA==.',
Cr='Crazycrocey:BAAALgAECgYJCAAAAA==.Cryptonight:BAAALgAECgQJBAAAAA==.',
Cu='Cubcake:BAAALgADCggJCAAAAA==.Curtastrophe:BAABLgAECn89AAIFAAkJHx3nJwB7AgAFAAkJHx3nJwB7AgAAAA==.Curticus:BAAALgADCgQJBAAAAA==.Curtissax:BAAALgAECgIJAgAAAA==.Curtnought:BAAALgADCgIJAgAAAA==.',
['Cé']='Cérnùnnøs:BAAALgAECgEJAQAAAA==.',
Da='Daelanos:BAABLgAECn8cAAISAAgJPBidMACLAQASAAgJPBidMACLAQABLgAFFAIJBAAGAAAAAA==.Dalinar:BAAALgAECgUJCwAAAA==.Daranger:BAAALgADCgEJAQAAAA==.Darska:BAAALgADCgYJBgABLgAECggJDgAGAAAAAA==.',
De='Deadtauren:BAAALgADCgYJDwAAAA==.Deathdemon:BAAALgAECgYJDgAAAA==.Deathfue:BAAALgAECgEJAwABLgAECgcJCgAGAAAAAA==.Deathisreal:BAAALgADCgMJAwABLgAECgUJDQAGAAAAAA==.Deathoof:BAAALgAECgIJAgABLgAECggJHwAOAOgYAA==.Decimated:BAACLgAFFH8cAAMEAAUJ+yDrQgBvAQAEAAUJ+yDrQgBvAQAfAAEJMgVNBQBCAAAuAAQKfyAAAgQACQkwI74YALICAAQACQkwI74YALICAAAA.Degeneracy:BAAALgAECgcJCwAAAA==.Demon:BAAALgAECgkJDgAAAA==.Demonblaze:BAAALgAFFAIJBAAAAA==.Demonilla:BAAALgAECgcJEgAAAA==.Dempkiston:BAAALgAECgYJCwAAAA==.Denable:BAABLgAECn8qAAIJAAcJSg+QTwBRAQAJAAcJSg+QTwBRAQAAAA==.Denogan:BAAALgAECggJDgAAAA==.Deservis:BAAALgAECgUJDgABLgAECgcJHgALAKIVAA==.Destro:BAABLgAECn8pAAIbAAkJ7w+sSQC9AQAbAAkJ7w+sSQC9AQABLgAECgkJMwAgAOIXAA==.Dethadin:BAAALgADCgcJBwAAAA==.',
Di='Dilaudyd:BAAALgAECgMJBAAAAA==.Dirteemike:BAAALgADCgMJAwAAAA==.Disbeleaf:BAACLgAFFH8FAAMNAAMJzhINOwCLAAANAAIJJBYNOwCLAAAJAAIJegscWgBmAAAuAAQKfxUAAwkABgkBGRw6AK0BAAkABgkBGRw6AK0BAA0ABQlRIPQtAGsBAAAA.Discoflurry:BAAALgAECgcJDgABLgAFFAQJCgADAN8hAA==.Dizzyfist:BAAALgAECgYJCQABLgAECggJDgAGAAAAAA==.',
Do='Dogaz:BAAALgAECgEJAQAAAA==.Dogsoldier:BAAALgADCgIJAgAAAA==.Donori:BAAALgAECgQJDQAAAA==.Dorcath:BAAALgAFFAIJBAAAAA==.',
Dr='Dragan:BAAALgAECgQJEQAAAA==.Dragapult:BAAALgAECggJAwAAAA==.Dragonias:BAABLgAECn8hAAIhAAgJOxawCgDCAQAhAAgJOxawCgDCAQAAAA==.Draino:BAAALgADCgUJBQAAAA==.Drakthorn:BAAALgAECgcJDAAAAA==.Dreselwings:BAAALgAECggJCAABLgAFFAgJHgAZAJsfAA==.Drinny:BAABLgAECn8yAAIIAAkJtwi8MgA+AQAIAAkJtwi8MgA+AQAAAA==.Drqueenisin:BAAALgAECgIJAwAAAA==.Druido:BAAALgAECgQJAwAAAA==.',
Du='Duerek:BAAALgAECgUJBgAAAA==.',
['Dè']='Dèaths:BAAALgAECgYJEAAAAA==.',
['Dí']='Dínglebery:BAAALgAECgYJCAAAAA==.',
Ea='Earthangel:BAABLgAECn8tAAIIAAcJHBe3JQCXAQAIAAcJHBe3JQCXAQAAAA==.',
Ed='Edlarel:BAAALgADCgQJBAABLgAECggJCQAGAAAAAA==.',
Ei='Eine:BAABLgAECn9DAAIZAAkJsxVCMgATAgAZAAkJsxVCMgATAgAAAA==.Eitherwind:BAABLgAECn8XAAQiAAYJ2h/XHwCdAQAiAAYJ2h/XHwCdAQAZAAIJchT/qwBsAAAhAAIJNxOcOwA0AAABLgAECggJDgAGAAAAAA==.Eivore:BAAALgAECgcJBwAAAA==.',
Ek='Ekoh:BAAALgAECgEJAgAAAA==.',
El='Eldergreen:BAABLgAECn8vAAMJAAkJPQuHVAA+AQAJAAkJPQuHVAA+AQANAAIJkwrweQBSAAAAAA==.Eldest:BAAALgADCgUJBQAAAA==.Elfwine:BAABLgAECn8tAAIXAAcJ6g0MOAA1AQAXAAcJ6g0MOAA1AQAAAA==.Elindria:BAABLgAECn80AAQYAAkJQSXYAwAUAwAYAAkJHiXYAwAUAwAjAAkJhiElAgDrAgALAAUJMxu6ewA0AQAAAA==.Eliora:BAAALgADCgkJCQAAAA==.Elitist:BAAALgAFFAMJAwAAAA==.Elminstir:BAABLgAECn8XAAIFAAgJnhYBZgCxAQAFAAgJnhYBZgCxAQAAAA==.Elyissia:BAAALgAECgYJDAAAAA==.Elynisa:BAAALgAECgEJAQAAAA==.Elysian:BAABLgAECn84AAQKAAkJcxwXDADYAgAKAAkJcxwXDADYAgARAAgJaB8iEABKAgAQAAIJyh/pVwCpAAAAAA==.',
Em='Emogo:BAAALgADCgUJCQAAAA==.',
En='Enforcer:BAAALgADCgQJBgAAAA==.Enlightened:BAAALgAECgQJCwAAAA==.Enseral:BAAALgAECgcJEgAAAA==.',
Eo='Eotech:BAAALgAECgQJBAAAAA==.',
Er='Erastas:BAAALgADCgQJBAAAAA==.Erendora:BAABLgAECn8iAAIJAAkJdg1aPwCUAQAJAAkJdg1aPwCUAQAAAA==.Erets:BAAALgAECgEJAQAAAA==.Eridar:BAAALgAECgYJBgAAAA==.Erizhal:BAAALgAECgUJEAAAAA==.Erodora:BAAALgADCgEJAQAAAA==.',
Es='Esabel:BAAALgAECgkJEgABLgAECgkJLQAFAF0gAA==.',
Ev='Eva:BAAALgAECgEJAgAAAA==.Eviae:BAABLgAECn8uAAIkAAcJBwv2LgDoAAAkAAcJBwv2LgDoAAAAAA==.Evillure:BAABLgAECn8lAAMEAAkJ8hNnQgD7AQAEAAkJ8hNnQgD7AQAkAAUJkgw1PACgAAAAAA==.',
Ez='Ezera:BAAALgAECgUJBQAAAA==.',
Fa='Falan:BAABLgAECn8tAAIeAAkJDhKELgD8AQAeAAkJDhKELgD8AQAAAA==.Faputa:BAAALgAECgMJAwAAAA==.Fatherjoe:BAAALgADCgYJBgAAAA==.Fayze:BAEBLgAECn8XAAMcAAcJfiMSBQAwAgAcAAcJSCMSBQAwAgAWAAIJBiGbQQC+AAABLgAFFAIJBAAGAAAAAA==.',
Fe='Felbreaker:BAAALgAECgYJEAAAAA==.Fentril:BAAALgADCgIJAgABLgAECggJDgAGAAAAAA==.Feår:BAABLgAECn8eAAMbAAkJJQwffwA7AQAbAAgJQgoffwA7AQAlAAMJ3Q8RSwCMAAAAAA==.',
Fi='Fillianora:BAAALgAECgIJAgAAAA==.Finley:BAAALgAECgQJBQAAAA==.Fircane:BAAALgADCgQJBAAAAA==.Firiel:BAAALgAECgMJAwAAAA==.Fizzle:BAAALgADCggJCAABLgAECgkJJwAJAHYaAA==.',
Fl='Flane:BAAALgAFFAEJBAABLgAFFAgJIAADAHwfAA==.Flem:BAAALgAECgMJBAAAAA==.Flexdruid:BAABLgAECn8YAAMPAAYJ3QolMQCcAAAPAAYJ9QglMQCcAAAOAAQJ4whbSwB9AAAAAA==.',
Fo='Foog:BAABLgAECn8YAAMSAAgJwxj6MACJAQASAAYJoBr6MACJAQAmAAYJGRMcKwAfAQAAAA==.',
Fr='Fragil:BAABLgAECn8/AAIWAAgJiyIODQBWAgAWAAgJiyIODQBWAgAAAA==.Frostmane:BAACLgAFFH8bAAMEAAYJEh2ZJADbAQAEAAUJEh2ZJADbAQAkAAEJAAAaXgAAAAAuAAQKfzsAAwQACQlWJeEFAEoDAAQACQlWJeEFAEoDACQABwn+HMANADECAAAA.Frostynug:BAAALgADCgYJBgAAAA==.',
Fu='Fudge:BAAALgADCgYJBgAAAA==.Furbyn:BAAALgADCgIJAgAAAA==.',
Ga='Galena:BAABLgAECn8iAAIJAAgJyRAQSgBmAQAJAAgJyRAQSgBmAQAAAA==.Gallamier:BAAALgADCgEJAQAAAA==.Gamerinator:BAAALgADCgcJCwAAAA==.Gangreene:BAAALgADCgYJCgAAAA==.Garoanna:BAAALgAECgYJBgABLgAFFAIJAgAGAAAAAA==.',
Ge='Geshalt:BAAALgAECgEJAQAAAA==.Geshtal:BAAALgAECgQJDAAAAA==.Gets:BAAALgADCgMJBAAAAA==.',
Gi='Girion:BAABLgAECn8uAAIBAAcJYw/SHgAdAQABAAcJYw/SHgAdAQAAAA==.Girliepop:BAAALgAECgEJAQAAAA==.',
Gl='Glaiven:BAECLgAFFH8dAAMLAAUJbBt2OgA7AQALAAUJbBt2OgA7AQAjAAMJuA+aDgBhAAAuAAQKfy8AAyMACQmVIY0EAHQCAAsACQkrH6EdAKACACMACQmXHI0EAHQCAAAA.Glorfinndel:BAAALgADCgQJBAAAAA==.Glyr:BAAALgADCgUJBQAAAA==.',
Go='Gorgrin:BAABLgAECn8XAAIaAAgJQhRBCwCpAQAaAAgJQhRBCwCpAQAAAA==.Goude:BAAALgADCgMJBAAAAA==.',
Gr='Greenback:BAAALgADCgYJCwAAAA==.Greentotes:BAEBLgAECn8yAAMUAAkJ7x9eCADRAgAUAAkJ7x9eCADRAgAnAAUJTxOYEgDhAAABLgAECgIJBAAGAAAAAA==.',
Gu='Gunter:BAAALgAECgMJAwABLgAFFAUJHAAEAPsgAA==.Gura:BAAALgADCgEJAQAAAA==.Gurnee:BAAALgADCgcJDQABLgAECggJEQAGAAAAAA==.Guthix:BAAALgAECgUJBgAAAA==.',
['Gê']='Gêm:BAABLgAECn9IAAITAAkJ8xLGDAAGAgATAAkJ8xLGDAAGAgAAAA==.',
['Gï']='Gïmlï:BAAALgADCgMJAwAAAA==.',
Ha='Haildydra:BAAALgAECgEJAQABLgAECgcJCgAGAAAAAA==.Halibell:BAAALgAECgYJDQAAAA==.Halnan:BAAALgADCgEJAQABLgAECgcJHgALAKIVAA==.Harkanum:BAABLgAECn9GAAQnAAkJ9hlxBgDnAQAnAAgJLhhxBgDnAQATAAkJGg2GEgCgAQAUAAQJrxPwPgDuAAAAAA==.Harrow:BAAALgAECgMJAwAAAA==.Hartman:BAAALgAECgQJBQAAAA==.Harvester:BAAALgAECgEJAQAAAA==.Hatebreéd:BAAALgAECggJCQAAAA==.',
He='Healinturds:BAAALgAECgYJDAABLgAECgcJHgALAKIVAA==.Hector:BAABLgAECn8eAAICAAkJfSKuJgBpAgACAAkJfSKuJgBpAgABLgAECgkJKwAFAJcfAA==.Heelys:BAAALgAECgYJCgAAAA==.Helloagain:BAACLgAFFH8XAAIFAAQJtRodTABIAQAFAAQJtRodTABIAQAuAAQKfyUAAgUABglqIyFdACMCAAUABglqIyFdACMCAAAA.Herryknutsak:BAAALgAECgEJAQAAAA==.Hestonater:BAAALgAECgUJBwAAAA==.Hestra:BAAALgADCgMJBAAAAA==.Hexidecimal:BAAALgAECgQJBAAAAA==.',
Hi='Hidethetotem:BAABLgAECn8rAAMeAAkJRR1KDgDiAgAeAAkJRR1KDgDiAgAHAAEJHgr1BwAuAAAAAA==.Hightops:BAAALgAECggJDgAAAA==.Hikari:BAACLgAFFH8OAAICAAYJpgxMMgBLAQACAAYJpgxMMgBLAQAuAAQKfx4AAgIACQlrHOAsAHACAAIACQlrHOAsAHACAAAA.Hiown:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.',
Ho='Holeliness:BAAALgAECggJEwAAAA==.Holybackshot:BAAALgAECgQJBgAAAA==.Holydisco:BAAALgADCgcJCQAAAA==.Holyhide:BAAALgAECgEJAQAAAA==.Holyspike:BAABLgAECn8gAAIeAAgJphBDRACdAQAeAAgJphBDRACdAQAAAA==.Holytard:BAAALgADCgYJBgAAAA==.Holytaren:BAABLgAECn8UAAIVAAgJ3RvWEwBwAgAVAAgJ3RvWEwBwAgAAAA==.Holytickles:BAABLgAECn8sAAMXAAkJ4hsCEwBeAgAXAAgJ+hsCEwBeAgAIAAkJsBewEgBIAgABLgAFFAYJGAAbAJoVAA==.Holytotem:BAAALgAECgEJAQAAAA==.Homerr:BAABLgAECn8kAAIZAAgJpBNxSADIAQAZAAgJpBNxSADIAQAAAA==.Honiahaka:BAABLgAECn9DAAIZAAkJBxDbRgDNAQAZAAkJBxDbRgDNAQAAAA==.Hottcakes:BAAALgAFFAEJAQABLgAFFAYJGAAbAJoVAA==.',
Hu='Huckster:BAABLgAECn8ZAAIEAAgJhQ51fwBkAQAEAAgJhQ51fwBkAQAAAA==.Humanoidholy:BAABLgAECn8fAAMCAAgJXSQ6CQBIAwACAAgJXSQ6CQBIAwABAAEJbgXWTQAYAAABLgAFFAUJFAAYAJgjAA==.Humanoidhunt:BAAALgAFFAIJAgABLgAFFAUJFAAYAJgjAA==.Humanoidvoid:BAACLgAFFH8UAAQYAAUJmCOTBwCOAQAYAAQJVCOTBwCOAQALAAMJ9h2MVgDrAAAjAAEJAAAiGAAAAAAuAAQKf1MABAsACQkFI0AHABoDAAsACQmdIkAHABoDABgACAnlH5UKAH8CACMACAkoCMMVAPwAAAAA.',
Hy='Hydrah:BAAALgAECgEJAQABLgAECgcJCgAGAAAAAA==.',
['Hö']='Hölyçow:BAAALgADCgEJAQAAAA==.',
Ic='Icedtea:BAAALgAECgcJBAAAAA==.Icicle:BAAALgADCgIJAgAAAA==.',
Id='Idunasil:BAAALgAECgEJAQAAAA==.',
Ih='Ihatemustard:BAABLgAECn8jAAIjAAkJ6RUfCAD2AQAjAAkJ6RUfCAD2AQAAAA==.',
Il='Illethan:BAAALgADCgYJBgAAAA==.Iloveketchup:BAAALgAFFAEJAQAAAA==.',
In='Inclination:BAAALgADCgEJAQAAAA==.Inoru:BAABLgAECn8bAAMXAAcJhRFPMQBXAQAXAAcJhRFPMQBXAQAIAAEJpwJdfAAcAAAAAA==.Insanity:BAAALgAECgUJCgAAAA==.Invidious:BAAALgAECgEJAQAAAA==.',
Ir='Irmaline:BAABLgAECn8gAAIIAAgJvBVxHQDZAQAIAAgJvBVxHQDZAQAAAA==.',
It='Ithurtshuh:BAAALgAECgUJDQAAAA==.Itsmaam:BAAALgAECgMJBAAAAA==.Itzcannibal:BAACLgAFFH8GAAIZAAIJ6go2jgCDAAAZAAIJ6go2jgCDAAAuAAQKfy8AAxkACQk4G/8rAC0CABkACQk4G/8rAC0CACEAAgnVCux5AFoAAAAA.',
Ja='Jabbawockie:BAAALgAECgkJAgAAAA==.Jaekoby:BAAALgAECgIJAwABLgAECggJIgACAM0aAA==.Jakoby:BAAALgAECgUJBgABLgAECggJIgACAM0aAA==.Jandrisel:BAABLgAECn8WAAMNAAcJhgnOSADpAAANAAcJhgnOSADpAAAJAAUJtgLxngByAAAAAA==.Jarhead:BAAALgAECgEJAgAAAA==.Jayzich:BAAALgADCgQJBwAAAA==.',
Je='Jeffee:BAAALgAECgIJCQAAAA==.Jequalsjosh:BAACLgAFFH8IAAIcAAMJoRyFAACxAAAcAAMJoRyFAACxAAAuAAQKfz0AAhwACQkhIlgCALsCABwACQkhIlgCALsCAAAA.Jerk:BAAALgAECgQJBAAAAA==.Jerp:BAAALgAECgIJAgAAAA==.Jesper:BAABLgAECn9GAAIeAAkJ5B9pCgAQAwAeAAkJ5B9pCgAQAwAAAA==.Jetz:BAAALgAECgEJAQAAAA==.Jezelle:BAACLgAFFH8SAAIbAAUJDRDaXQAMAQAbAAUJDRDaXQAMAQAuAAQKfyIAAhsACQn0Hg42ADQCABsACQn0Hg42ADQCAAAA.',
Ji='Jilara:BAABLgAECn86AAICAAkJBghDkwBMAQACAAkJBghDkwBMAQAAAA==.Jimmyjim:BAABLgAECn8dAAIFAAgJswwgiABnAQAFAAgJswwgiABnAQAAAA==.Jingying:BAAALgAECgQJBAAAAA==.',
Jo='Johnny:BAAALgADCgQJBAAAAA==.',
Jp='Jpepps:BAABLgAECn8vAAMbAAkJDRNgPwDfAQAbAAkJDRNgPwDfAQAlAAMJxwjoRQCeAAAAAA==.',
Jr='Jrose:BAAALgAECgQJBAAAAA==.',
Ju='Jul:BAAALgAECgIJAgAAAA==.',
['Jæ']='Jækobÿ:BAAALgAECgIJAgABLgAECggJIgACAM0aAA==.',
Ka='Kahlanrahl:BAAALgADCgMJAwAAAA==.Kaiatra:BAABLgAECn8hAAIfAAgJPySfAwCoAgAfAAgJPySfAwCoAgAAAA==.Kalasandria:BAAALgAECgEJAQAAAA==.Kaliguala:BAAALgAECgQJBQAAAA==.Katalaystar:BAAALgAECgcJCQABLgAECgkJJwAJAHYaAA==.Katare:BAAALgAECgMJAwAAAA==.Kaulder:BAAALgADCgUJBQAAAA==.Kaìju:BAABLgAECn8iAAICAAgJqiHXIQB/AgACAAgJqiHXIQB/AgAAAA==.Kaîju:BAAALgAECgIJAgAAAA==.',
Ke='Kellytgt:BAACLgAFFH8FAAILAAMJYgzECwB+AAALAAMJYgzECwB+AAAuAAQKfzkAAgsACQkAHKoUAJ0CAAsACQkAHKoUAJ0CAAAA.Kev:BAAALgADCgUJBQAAAA==.',
Ki='Kilaura:BAABLgAECn8ZAAIoAAgJWRANJQCnAQAoAAgJWRANJQCnAQAAAA==.Killian:BAAALgAECgEJAQAAAA==.Kilmandaros:BAAALgADCgYJCwAAAA==.Kippi:BAAALgAECgQJCwAAAA==.',
Kn='Knitebrite:BAAALgAECgIJAgAAAA==.',
Ko='Korhina:BAABLgAECn9GAAIDAAkJeyYfAQBZAwADAAkJeyYfAQBZAwAAAA==.Korobas:BAAALgAECgMJAwAAAA==.Koru:BAAALgAECgQJBQABLgAECgQJBgAGAAAAAA==.Kosumi:BAAALgADCggJDQAAAA==.',
Kr='Kronic:BAAALgAECgUJCAAAAA==.Kronmon:BAAALgAECgEJAQAAAA==.',
Ku='Kuroyukihime:BAABLgAECn84AAIFAAkJ/h7jGwC0AgAFAAkJ/h7jGwC0AgAAAA==.Kuwaii:BAABLgAECn8dAAIUAAcJuxjiKACfAQAUAAcJuxjiKACfAQABLgAECggJHgANAA0gAA==.',
Ky='Kyarina:BAAALgAECgEJAQABLgAECgkJGQAIAEMHAA==.Kylis:BAAALgAECgQJBAAAAA==.Kyna:BAABLgAECn8ZAAIIAAkJQwfPPAAAAQAIAAkJQwfPPAAAAQAAAA==.Kyross:BAAALgADCgIJAgAAAA==.',
['Ké']='Kéya:BAAALgAECgYJDQAAAA==.',
La='Lashela:BAABLgAECn8XAAIZAAkJwwuDbwBhAQAZAAkJwwuDbwBhAQAAAA==.Laughter:BAABLgAECn8YAAMSAAgJpQfyWADrAAASAAgJmQbyWADrAAADAAQJMAZuNQCbAAAAAA==.Laurana:BAAALgADCgIJAgAAAA==.Laylah:BAAALgADCgIJAgAAAA==.Lazulie:BAAALgAECgYJEwAAAA==.',
Le='Leansipper:BAABLgAFFH8QAAINAAQJ6hOJIQAUAQANAAQJ6hOJIQAUAQAAAA==.Levoker:BAAALgAECgQJBAAAAA==.Lexapayne:BAAALgAECgYJEgABLgAFFAQJEgAZAOcUAA==.',
Li='Lighthammer:BAAALgADCgEJAQAAAA==.Lilandra:BAAALgAECgYJDwABLgAECggJDgAGAAAAAA==.Lillianaxe:BAABLgAECn8XAAMkAAcJHRjDHwBWAQAkAAYJsBnDHwBWAQAEAAcJAA9LlAA+AQAAAA==.Lilyvain:BAAALgAECgUJCAAAAA==.Lireal:BAABLgAECn8wAAIVAAkJjiW8AADIAwAVAAkJjiW8AADIAwAAAA==.Listerine:BAAALgAECggJCQAAAA==.Litercola:BAABLgAECn8UAAIIAAYJjgKmVACJAAAIAAYJjgKmVACJAAAAAA==.Livnod:BAAALgAECgQJCgAAAA==.',
Lo='Loonfabio:BAAALgAECgIJAgABLgAFFAUJEwACACUjAA==.Loosescrew:BAAALgADCgMJBAAAAA==.Lorine:BAABLgAECn87AAIBAAkJbBvpCgAbAgABAAkJbBvpCgAbAgAAAA==.Lowkie:BAAALgADCgIJAgAAAA==.',
Lu='Luckside:BAAALgAECgQJBAABLgAECgkJHgAbACUMAA==.Lunara:BAAALgAECgMJBgAAAA==.Lunasnow:BAAALgAECgQJBAAAAA==.Lunchtime:BAAALgAECgEJAQAAAA==.Luxe:BAAALgADCgEJAQAAAA==.',
Ly='Lyntot:BAAALgADCgEJAQAAAA==.',
['Ló']='Lókki:BAAALgAECgUJCAAAAA==.',
Ma='Madwe:BAABLgAECn8hAAMLAAgJrgdElQD2AAALAAgJcwZElQD2AAAYAAMJcAbJUwBpAAAAAA==.Mageab:BAABLgAFFH8QAAIFAAgJZiDfCACxAgAFAAgJZiDfCACxAgAAAA==.Magis:BAAALgADCgkJHgAAAA==.Malzzahar:BAAALgAECgQJBAAAAA==.Manimetal:BAABLgAECn8WAAICAAUJiwVGJQGNAAACAAUJiwVGJQGNAAAAAA==.Materia:BAAALgAECgcJBwAAAA==.',
Me='Meeralax:BAABLgAECn8WAAIZAAYJJgaFvADNAAAZAAYJJgaFvADNAAAAAA==.Melizza:BAAALgADCgMJAwAAAA==.Merckel:BAACLgAFFH8IAAILAAMJMhr0WgDfAAALAAMJMhr0WgDfAAAuAAQKfywAAgsACAk5IDgdAGUCAAsACAk5IDgdAGUCAAAA.Merckz:BAAALgAECgUJBQABLgAFFAMJCAALADIaAA==.Merks:BAAALgAFFAEJAQAAAA==.Metalmonkey:BAAALgAECgYJCwAAAA==.',
Mi='Michello:BAABLgAECn8dAAIZAAgJzh6jJwBBAgAZAAgJzh6jJwBBAgAAAA==.Mickcowmoose:BAAALgADCgIJAgAAAA==.Millia:BAABLgAECn8rAAIFAAkJlx8+FwDOAgAFAAkJlx8+FwDOAgAAAA==.Mint:BAABLgAECn8jAAIVAAcJiyONDwCfAgAVAAcJiyONDwCfAgAAAA==.Mintberrytea:BAAALgAECgUJBwABLgAECgcJIwAVAIsjAA==.Mintchaitea:BAABLgAECn8YAAIKAAkJTiEqBQBYAwAKAAkJTiEqBQBYAwABLgAECgcJIwAVAIsjAA==.Misstress:BAABLgAECn9AAAMNAAkJMBDtJACkAQANAAkJ2Q/tJACkAQAOAAQJ0w77OgC6AAAAAA==.Mizen:BAAALgADCgUJCAAAAA==.',
Mo='Mogdor:BAAALgADCgUJBQAAAA==.Monkussy:BAAALgAECgIJAgAAAA==.Moonhunt:BAAALgAECgQJCgAAAA==.Moonly:BAACLgAFFH8FAAIiAAMJHQNLKQCQAAAiAAMJHQNLKQCQAAAuAAQKfyYAAiIACQlhDDEcALsBACIACQlhDDEcALsBAAAA.Morrag:BAABLgAECn85AAMbAAgJYw/XAQAsAQAbAAgJYw/XAQAsAQAaAAEJjAYdQgAuAAAAAA==.',
Mu='Murdumurdu:BAAALgAECgUJCAAAAA==.Murkblade:BAAALgADCgYJBgABLgAECgcJHgALAKIVAA==.Murphee:BAAALgAECgEJAgAAAA==.Musho:BAAALgADCgYJEgAAAA==.Mustakrakish:BAAALgAECgEJAQAAAA==.',
My='Myn:BAABLgAECn8XAAIJAAkJwhk2FgCWAgAJAAkJwhk2FgCWAgAAAA==.Myw:BAAALgAECgcJBwABLgAFFAgJLAAeALkWAA==.',
['Mæ']='Mædenless:BAAALgAECgYJCQAAAA==.',
['Mí']='Mísfìt:BAABLgAECn88AAMeAAkJQRnWIQBEAgAeAAkJQRnWIQBEAgAHAAgJEQyXPQA/AQAAAA==.',
Na='Nakaito:BAABLgAECn8cAAIbAAgJ+AyOcABZAQAbAAgJ+AyOcABZAQABLgAECgkJOAAcAA8bAA==.Narcoleptic:BAACLgAFFH8TAAITAAQJFBBcAgClAAATAAQJFBBcAgClAAAuAAQKf0EABBMACQnqGGYHAIECABMACQnqGGYHAIECABQACAmFFgwnAKoBACcABQkQCFQvAJ0AAAAA.Nashty:BAAALgAECgEJAQAAAA==.',
Ne='Neocracy:BAAALgADCgYJCwABLgAECggJFAAVAN0bAA==.Nex:BAAALgADCgYJCAAAAA==.',
Ni='Niceshield:BAAALgAECgEJBgAAAA==.Nightmarexx:BAACLgAFFH8VAAIWAAUJZh5iGgBDAQAWAAUJZh5iGgBDAQAuAAQKf04AAhYACAmnIb0KAHgCABYACAmnIb0KAHgCAAAA.Nightsawdy:BAABLgAECn8vAAMZAAgJEhkOAwA6AQAiAAcJFhEpJQB0AQAZAAcJVBoOAwA6AQAAAA==.Nightsnake:BAAALgAECgMJAwAAAA==.Niightstorm:BAABLgAECn8pAAMZAAcJQBziNQAGAgAZAAcJQBziNQAGAgAiAAQJbBL6PwDIAAAAAA==.Nikwillig:BAAALgAECggJDQAAAA==.Nilveron:BAAALgADCgcJCQAAAA==.Nitefire:BAAALgAECgQJAgAAAA==.Nitélifé:BAAALgADCgMJAwAAAA==.',
Nj='Njörðr:BAAALgAECgYJDgAAAA==.',
No='Nocturnum:BAABLgAFFH8IAAIWAAMJhQ7aKQDeAAAWAAMJhQ7aKQDeAAABLgAFFAQJFwAFALUaAA==.Noxmortis:BAAALgAFFAMJBAAAAA==.',
Nt='Ntadadarknes:BAAALgAECgIJAwABLgAECgkJLwAJAD0LAA==.',
Oo='Ooblidoom:BAAALgAECgEJAQABLgAECgkJUAAnAIITAA==.',
Op='Opalinnas:BAABLgAECn8nAAMJAAkJdhooFwCNAgAJAAkJdhooFwCNAgANAAUJeQglXQCiAAAAAA==.',
Oz='Ozath:BAAALgAECgQJBgAAAA==.',
Pa='Passionfruit:BAAALgAFFAEJAQAAAA==.',
Pe='Peachtea:BAAALgAECgQJEgAAAA==.',
Ph='Phatshaman:BAABLgAECn8UAAIHAAgJbQeBUQDyAAAHAAgJbQeBUQDyAAAAAA==.Phæryll:BAAALgADCgUJBgAAAA==.',
Pi='Pirodeath:BAAALgAECgcJCgAAAA==.',
Pl='Place:BAAALgAECgIJAgAAAA==.',
Po='Poisonclaw:BAAALgAECgIJBAAAAA==.Poprotonix:BAABLgAECn8fAAICAAgJPxZxTgDcAQACAAgJPxZxTgDcAQAAAA==.Pozessedkaos:BAAALgAECgQJBAAAAA==.',
Pr='Praecantrix:BAAALgAECgEJBQAAAA==.Prath:BAAALgADCgEJAQAAAA==.Pray:BAABLgAECn9DAAIoAAkJBCScAgCKAwAoAAkJBCScAgCKAwAAAA==.Priestyballz:BAAALgAECgYJBgAAAA==.Prodarkangel:BAABLgAECn8bAAMlAAkJIglzFwDnAAAlAAkJIglzFwDnAAAbAAMJaAOcGAFPAAAAAA==.',
Pu='Pubis:BAAALgAECgYJDgAAAA==.Puckllane:BAABLgAECn8aAAICAAkJ5RdiQQAhAgACAAkJ5RdiQQAhAgAAAA==.Punkbeer:BAAALgAECgEJAQAAAA==.Punkin:BAAALgAECgUJCwAAAA==.',
Py='Pyre:BAABLgAECn89AAIoAAkJSQ+rIgC5AQAoAAkJSQ+rIgC5AQABLgADCgUJBQAGAAAAAA==.Pyroth:BAAALgAECgEJAQAAAA==.',
['Pó']='Pó:BAAALgADCgIJBAABLgAECgkJHgAbACUMAA==.',
Qu='Quefstank:BAAALgADCgUJCAAAAA==.Quivver:BAAALgAECgQJAgAAAA==.',
Ra='Rabmaxx:BAABLgAECn8tAAIYAAgJ1w+1IABzAQAYAAgJ1w+1IABzAQAAAA==.Radren:BAAALgADCgEJAQAAAA==.Rajinazn:BAAALgAECgYJBgAAAA==.Rattchett:BAAALgAECgYJBgAAAA==.Ravenlight:BAABLgAFFH8FAAICAAQJWA7hUQAMAQACAAQJWA7hUQAMAQAAAA==.Ravenwynnd:BAABLgAECn8mAAImAAkJuyKIBADRAgAmAAkJuyKIBADRAgAAAA==.Ravix:BAAALgADCgQJBAAAAA==.Raynelock:BAABLgAECn8wAAMlAAkJgRA0CwCNAQAlAAkJgRA0CwCNAQAbAAIJtQcZCQFKAAAAAA==.Raynman:BAABLgAECn9DAAIeAAkJdxU+JgApAgAeAAkJdxU+JgApAgAAAA==.Razgriz:BAAALgAECgEJAQAAAA==.Razix:BAABLgAECn8zAAQUAAkJfxRZIADWAQAUAAkJfxRZIADWAQAnAAYJ6wkZGQCOAAATAAMJYwclPACJAAAAAA==.',
Re='Realist:BAAALgAECgMJBAAAAA==.Refrigtuitor:BAACLgAFFH8fAAMFAAUJrQ41YwAcAQAFAAUJrQ41YwAcAQApAAIJuAIZBgBiAAAuAAQKfz8ABAUACQmEH+EgAJsCAAUACQmEH+EgAJsCAAwABQmDCGQOAN0AACkAAQk8EK4TADYAAAAA.Reija:BAAALgAECgEJAgAAAA==.Repentance:BAAALgADCgEJAQABLgAECgkJMwAgAOIXAA==.Revealed:BAAALgADCgEJAQAAAA==.Reyeda:BAAALgADCgUJBQAAAA==.Rezzarn:BAAALgAECgEJAQAAAA==.',
Rh='Rhun:BAAALgAECgYJCQAAAA==.Rhyzer:BAABLgAECn8uAAMSAAcJCR8bGQAlAgASAAcJCR8bGQAlAgAmAAEJJQ1bRQAuAAAAAA==.',
Ri='Rileyksufan:BAABLgAECn8VAAIZAAkJhg41fwBBAQAZAAkJhg41fwBBAQAAAA==.Rinas:BAACLgAFFH8FAAIYAAIJpxchIQCSAAAYAAIJpxchIQCSAAAuAAQKfzYAAxgACQm4IpYDABwDABgACQm4IpYDABwDAAsAAgmfDcIUATUAAAAA.Rivendell:BAAALgAECgQJBgAAAA==.Rivenlynn:BAAALgADCgEJAQAAAA==.',
Ru='Rubioxis:BAAALgADCgYJBgAAAA==.',
Ry='Rymarri:BAAALgADCgkJCQAAAA==.',
Sa='Sabazia:BAACLgAFFH8NAAIkAAMJMhsvIADmAAAkAAMJMhsvIADmAAAuAAQKfzsAAiQACQkXILwHAJ0CACQACQkXILwHAJ0CAAAA.Sacrificer:BAAALgAECgMJAwAAAA==.Sairalindë:BAABLgAECn8hAAMZAAkJbweuegBKAQAZAAkJbweuegBKAQAhAAMJpAA3hgA2AAAAAA==.Saleath:BAAALgAECgEJAwAAAA==.Salios:BAABLgAFFH8NAAIbAAQJNB6wFwAzAQAbAAQJNB6wFwAzAQAAAA==.Sallydisco:BAAALgAECgMJAwABLgAFFAQJCgADAN8hAA==.Sanctifier:BAAALgAECgQJDQAAAA==.Saraneth:BAAALgAECgEJAQABLgAECgkJMAAVAI4lAA==.',
Sc='Scandrel:BAAALgAECgQJBAABLgAFFAUJHAAEAPsgAA==.Scrept:BAAALgAFFAEJAQAAAA==.Scynix:BAEBLgAECn8pAAMUAAkJdRikGgABAgAUAAkJdRikGgABAgATAAEJsgFhTgAiAAAAAA==.',
Se='Sedaline:BAAALgAECgQJBgAAAA==.Sephie:BAAALgADCgQJAQAAAQ==.Serenas:BAAALgAECgQJBAABLgAFFAEJAQAGAAAAAA==.Serenilock:BAAALgADCgMJAwAAAA==.Serfdog:BAAALgADCgcJDAAAAA==.Servoker:BAACLgAFFH8VAAITAAYJXxvnEACIAQATAAYJXxvnEACIAQAuAAQKfyUAAxQACAnbICEKANQCABQACAnbICEKANQCABMABwkkGrwVAPABAAAA.Setani:BAAALgADCgIJAgAAAA==.',
Sh='Shabzkaw:BAAALgADCgUJBQAAAA==.Shabzyt:BAAALgADCgQJBAAAAA==.Shaddows:BAAALgAECggJDwAAAA==.Shaienne:BAAALgAECgMJAwAAAA==.Shambussy:BAAALgAECgEJAQAAAA==.Shamfore:BAAALgADCgEJAQAAAA==.Shamrockshak:BAACLgAFFH8GAAIeAAIJKSYWQwDbAAAeAAIJKSYWQwDbAAAuAAQKfyEAAh4ABgkDI6IhAEUCAB4ABgkDI6IhAEUCAAAA.Shaze:BAAALgADCggJEAAAAA==.Shenuton:BAABLgAECn8VAAICAAgJXgjCpgAtAQACAAgJXgjCpgAtAQAAAA==.Shieldinterd:BAAALgAECgMJAgABLgAECgcJHgALAKIVAA==.Shiftkicker:BAAALgADCgMJAwAAAA==.Shocktherapy:BAAALgAECgEJAQAAAA==.Shockthêràpy:BAACLgAFFH8JAAIeAAMJjwxtXACTAAAeAAMJjwxtXACTAAAuAAQKfzAABB4ACQlbGG0nAPMBAB4ACQlbGG0nAPMBAAcAAwkWFxNqAKkAACAAAQlPCkYrADgAAAAA.Shoes:BAABLgAECn89AAQiAAkJTSWeAgAdAwAiAAkJxiOeAgAdAwAhAAgJIx/cDQDVAgAZAAgJ9SLXKAA7AgAAAA==.Shoresy:BAAALgAECgEJAgAAAA==.Shtdruid:BAAALgAECgcJDAAAAA==.Shyanni:BAAALgADCgMJAwAAAA==.Shöçkér:BAAALgAECgcJEwAAAA==.',
Si='Siaana:BAAALgADCgUJBQABLgAFFAMJDQAkADIbAA==.Sibearian:BAABLgAECn8fAAQOAAgJ6Bg6EgDNAQAOAAgJ6Bg6EgDNAQAPAAYJ0ApXJwDSAAANAAIJPwSEdQBNAAAAAA==.Simi:BAACLgAFFH8SAAIZAAQJ5xRoPwAuAQAZAAQJ5xRoPwAuAQAuAAQKfykAAhkACQmYGdEnAEACABkACQmYGdEnAEACAAAA.',
Sk='Skrubzz:BAABLgAECn8ZAAMDAAgJIQbpIAA4AQADAAgJIQbpIAA4AQASAAQJzgKHhwChAAAAAA==.Skôrn:BAABLgAECn8wAAIFAAcJLQ8HmwBDAQAFAAcJLQ8HmwBDAQAAAA==.',
Sl='Sloppynachos:BAABLgAECn8pAAIWAAgJRhdmGgAvAgAWAAgJRhdmGgAvAgAAAA==.Slyman:BAAALgADCgUJBQABLgAECgYJBwAGAAAAAA==.',
Sm='Smithnwesson:BAAALgAECgIJAgAAAA==.Smokesçreen:BAACLgAFFH8PAAIYAAQJpRM/EQAZAQAYAAQJpRM/EQAZAQAuAAQKf0UAAxgACQkEIZgFAOYCABgACQkEIZgFAOYCAAsABQm6BcTVAIkAAAAA.',
Sn='Snowhoof:BAAALgADCgUJBQAAAA==.',
So='Soccerqt:BAAALgAECgYJBgAAAA==.Sogerä:BAABLgAECn8XAAITAAgJIQWIHwD5AAATAAgJIQWIHwD5AAAAAA==.Soonerpride:BAABLgAECn8cAAICAAgJBCP3LABNAgACAAgJBCP3LABNAgAAAA==.Sorinmarkov:BAAALgAFFAIJAgAAAA==.Source:BAAALgAECgUJCAAAAA==.',
Sp='Spearminttea:BAAALgAECgcJCwAAAA==.Spellbreakr:BAAALgAECgYJCgAAAA==.Spellumgud:BAAALgAECgQJBgAAAA==.Spinturnum:BAAALgAECgcJDAABLgAFFAQJFwAFALUaAA==.Sprockette:BAAALgADCgYJBgAAAA==.',
Sq='Squiby:BAABLgAECn84AAMXAAkJoCLkBgDjAgAXAAkJoCLkBgDjAgAIAAIJmRX+ZwCNAAAAAA==.Squizzy:BAAALgAECgEJAQAAAA==.',
St='Stabfore:BAABLgAECn8mAAMWAAkJKBVHEAAqAgAWAAkJKBVHEAAqAgAcAAEJJgTGLAAlAAAAAA==.Standaside:BAAALgAECgIJBAAAAA==.Steellidan:BAAALgADCgEJAQAAAA==.Stinky:BAABLgAECn8XAAIdAAgJkQl4DgAlAQAdAAgJkQl4DgAlAQAAAA==.Stix:BAACLgAFFH8SAAIWAAQJCh7tFABkAQAWAAQJCh7tFABkAQAuAAQKfy0AAxYACQl6HCkNAFQCABYACQl6HCkNAFQCAB0ABAmnFTIUAMsAAAAA.Stoya:BAAALgAECgYJCgABLgAECgkJMAAVAI4lAA==.Stuef:BAABLgAECn82AAIHAAkJGyGPCgC2AgAHAAkJGyGPCgC2AgAAAA==.Stuefagos:BAAALgAECgQJBwAAAA==.Stuefester:BAABLgAECn8gAAMEAAkJNiBQIACIAgAEAAkJNiBQIACIAgAkAAcJ4QmDNADHAAAAAA==.Stueflare:BAAALgAECggJEAAAAA==.Stueflip:BAAALgADCgIJAgAAAA==.Stunsturds:BAABLgAECn8dAAMKAAYJQiAWHgApAgAKAAYJQiAWHgApAgAQAAEJ2AF+mQAaAAABLgAECgcJHgALAKIVAA==.Stäirs:BAABLgAECn9CAAISAAkJ5B1uDwB/AgASAAkJ5B1uDwB/AgAAAA==.',
Su='Summerlily:BAAALgADCgYJBgAAAA==.',
Sv='Svaja:BAAALgAECgIJAQABLgAECggJHwATAMAIAA==.',
Sy='Sylaria:BAAALgAECgUJCwAAAA==.Syreline:BAAALgAECgEJAgAAAA==.',
['Sá']='Sáble:BAACLgAFFH8FAAIBAAMJDAJiEwBfAAABAAMJDAJiEwBfAAAuAAQKfzAAAwEACQn6CWUeACEBAAIACAnNCCCpACkBAAEACQlNCGUeACEBAAAA.',
['Sí']='Síñ:BAAALgAECgIJAgABLgAECggJIgAbAFIaAA==.',
['Sî']='Sîn:BAAALgADCgEJAQABLgAECggJIgAbAFIaAA==.',
['Sï']='Sïn:BAABLgAECn8iAAIbAAgJUhq8PADpAQAbAAgJUhq8PADpAQAAAA==.',
Ta='Taereachye:BAACLgAFFH8HAAIVAAMJ3xdcLgDAAAAVAAMJ3xdcLgDAAAAuAAQKfxcAAhUABwk5JAYKANMCABUABwk5JAYKANMCAAEuAAUUBAkIAAoAgBUA.Tailon:BAAALgADCgYJBgAAAA==.Taintedlove:BAAALgADCgYJBgAAAA==.Talenelat:BAAALgADCgcJCwAAAA==.Talikas:BAAALgAECggJEAABLgAFFAMJBQALAGIMAA==.Tankin:BAAALgADCgMJAwAAAA==.Tantric:BAAALgAECgIJAgABLgAECggJCQAGAAAAAA==.Tarathiel:BAAALgADCgQJBAAAAA==.Tarpalantir:BAAALgAECgQJBAAAAA==.Taurne:BAACLgAFFH8WAAIJAAYJNwwTHwBhAQAJAAYJNwwTHwBhAQAuAAQKfx4AAgkABwmzGYEwAOkBAAkABwmzGYEwAOkBAAAA.',
Te='Technique:BAAALgAECgIJBAAAAA==.Teebags:BAAALgADCgEJAQAAAA==.Teknoman:BAACLgAFFH8QAAMSAAMJ5xvUMADsAAASAAMJ5xvUMADsAAADAAEJVQGyBgAmAAAuAAQKfz0AAhIACQkIIaUKALsCABIACQkIIaUKALsCAAAA.Telmarine:BAAALgAECgMJAwAAAA==.Tempered:BAABLgAECn8YAAMmAAYJMhyZFwCeAQAmAAYJMhyZFwCeAQASAAQJRRvGZQDFAAAAAA==.Terlemen:BAAALgAECgUJBQAAAA==.Tetsumi:BAAALgADCgYJCQABLgAECggJDgAGAAAAAA==.',
Th='Thaddeus:BAAALgAECgEJAQABLgAFFAUJFgAGAAAAAQ==.Thaitea:BAAALgAECgUJBgAAAA==.Thal:BAAALgAECgMJAwAAAA==.Thalan:BAAALgADCgEJAQAAAA==.Thalindra:BAABLgAECn8qAAIZAAcJdBxoOQD4AQAZAAcJdBxoOQD4AQAAAA==.Tharain:BAAALgAECgQJAgAAAA==.Thebigbeast:BAABLgAFFH8GAAIBAAIJcRVKAQB1AAABAAIJcRVKAQB1AAABLgAFFAYJGAAbAJoVAA==.Thecurt:BAABLgAECn9BAAIQAAkJnyRKAgA7AwAQAAkJnyRKAgA7AwAAAA==.Thedammed:BAAALgADCgEJAQAAAA==.Theholylight:BAAALgAECgYJDQAAAA==.Thehuzz:BAABLgAECn8XAAIeAAgJpQ8gAgAjAQAeAAgJpQ8gAgAjAQAAAA==.Thermidor:BAABLgAECn8gAAIiAAkJYBV5CQBLAgAiAAkJYBV5CQBLAgAAAA==.Thorsamie:BAAALgAECggJDgAAAA==.Thrasios:BAAALgAECgIJAgABLgAFFAIJBAAGAAAAAA==.Thundercunti:BAAALgADCgYJDAABLgAECggJPwAWAIsiAA==.',
Ti='Tiamatt:BAAALgADCgIJBAAAAA==.Ticktock:BAAALgAECgIJAgAAAA==.Timaeus:BAABLgAECn8XAAISAAcJAQIqhQBpAAASAAcJAQIqhQBpAAAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Titanlock:BAAALgAECgUJCQAAAA==.',
Tk='Tkdfath:BAAALgAECggJEgAAAA==.',
To='Torvia:BAAALgAECgUJCwAAAA==.Totemix:BAAALgADCgcJEgAAAA==.Totemsoul:BAAALgAECgEJAwABLgAECgcJCgAGAAAAAA==.',
Tr='Trisinz:BAABLgAECn8lAAINAAgJ0RcBHgDYAQANAAgJ0RcBHgDYAQAAAA==.Trixa:BAAALgADCgMJAwAAAA==.',
Tu='Tuerto:BAABLgAECn8VAAIZAAYJpg95lgATAQAZAAYJpg95lgATAQAAAA==.Turbojohnson:BAAALgAECgQJBgAAAA==.Turk:BAABLgAECn9EAAMLAAkJtReiJQA3AgALAAkJtReiJQA3AgAYAAEJCQ/BcwAxAAAAAA==.Turkish:BAABLgAECn9AAAMEAAkJZBp/MgA0AgAEAAkJZBp/MgA0AgAfAAEJ7gYcQQAlAAAAAA==.Turtledisco:BAACLgAFFH8KAAIDAAQJ3yGoEwAHAQADAAQJ3yGoEwAHAQAuAAQKfycAAgMACQnSH7sDABcDAAMACQnSH7sDABcDAAAA.',
Ty='Tychaa:BAAALgAECgQJAgAAAA==.Tylat:BAAALgADCgEJBQAAAA==.Tyranax:BAACLgAFFH8FAAIoAAIJ1wo6PwB8AAAoAAIJ1wo6PwB8AAAuAAQKfz0ABCgACQnlG2gKAMkCACgACQneGmgKAMkCAAgABgnVH1IcAPoBABcABwkxE2QzAEwBAAAA.Tyyregade:BAAALgADCgkJCgABLgAECggJDgAGAAAAAA==.',
Uj='Ujimas:BAAALgAECgEJAgAAAA==.',
Us='Us:BAAALgAECggJCQAAAA==.',
Uz='Uzzi:BAAALgAECgEJAQAAAA==.',
Va='Vadose:BAABLgAECn8gAAIbAAcJwQqmgQBXAQAbAAcJwQqmgQBXAQABLgAFFAQJEgAZAOcUAA==.Vales:BAAALgAECgYJEAABLgAFFAMJBQAZAMABAA==.Valsavis:BAABLgAECn8eAAINAAgJkxSmIgC0AQANAAgJkxSmIgC0AQAAAA==.Valytrois:BAABLgAECn8VAAIbAAcJlwmysQD1AAAbAAcJlwmysQD1AAAAAA==.Varinix:BAAALgADCgMJBQAAAA==.',
Ve='Veggiebaha:BAAALgADCgIJAgAAAA==.Veiksla:BAABLgAECn8fAAMTAAgJwAgIGgA4AQATAAgJwAgIGgA4AQAnAAEJoQNhKwAgAAAAAA==.Velore:BAAALgADCgcJDAAAAA==.Vengerr:BAAALgAECgUJBgAAAA==.Verace:BAAALgAECgcJAQAAAA==.Verradic:BAABLgAECn8VAAMlAAgJ1wXIJgB/AAAbAAgJyASdvADRAAAlAAUJ4AXIJgB/AAAAAA==.',
Vi='Vitur:BAABLgAECn9IAAILAAkJ/iCZFACeAgALAAkJ/iCZFACeAgAAAA==.',
Vo='Voidhunter:BAABLgAECn8VAAILAAcJGwrmlQD1AAALAAcJGwrmlQD1AAAAAA==.Voidweaver:BAAALgAECgMJBQAAAA==.Volaine:BAABLgAECn8tAAMbAAcJ7hLScQBWAQAbAAYJ7hLScQBWAQAaAAIJuhTmPQA2AAAAAA==.Volt:BAABLgAECn8zAAIgAAkJ4heeCgAQAgAgAAkJ4heeCgAQAgAAAA==.Volumoso:BAAALgAECgYJBgAAAA==.Volwryn:BAAALgAECgUJCAABLgAECggJCQAGAAAAAA==.',
Vy='Vynarian:BAABLgAECn8rAAIFAAcJIRXsdgCLAQAFAAcJIRXsdgCLAQAAAA==.',
['Vâ']='Vâljean:BAAALgADCgMJAwAAAA==.',
['Vô']='Vôx:BAAALgAECgEJAQABLgAECggJIQARAJEZAA==.',
['Vö']='Vöx:BAAALgAECgEJAQABLgAECggJIQARAJEZAA==.',
Wa='Warbeard:BAABLgAECn8oAAISAAkJ8gvqLQCZAQASAAkJ8gvqLQCZAQAAAA==.',
Wi='Wizwizx:BAAALgADCgUJBgAAAA==.',
Wr='Wreckbums:BAABLgAFFH8MAAIEAAMJiB/zcwAZAQAEAAMJiB/zcwAZAQAAAA==.Wreckd:BAABLgAECn8iAAMLAAcJnhhjRgC0AQALAAcJnhhjRgC0AQAYAAIJIgxqdQAqAAAAAA==.',
Wy='Wyth:BAAALgAECgQJBQABLgAECgQJBgAGAAAAAA==.',
Xa='Xanthad:BAAALgADCgEJAQAAAA==.',
Xb='Xb:BAAALgAECgQJAgAAAA==.',
Xi='Xitãozinho:BAAALgAECgUJBwAAAA==.',
Xo='Xolair:BAAALgAECgYJDgAAAA==.',
Ya='Yaalia:BAABLgAECn8fAAMCAAcJMQZD2wDkAAACAAcJMQZD2wDkAAAVAAIJZwIKowAiAAAAAA==.Yaan:BAABLgAECn8gAAIHAAgJMQpJRwAXAQAHAAgJMQpJRwAXAQAAAA==.Yalane:BAAALgAECgQJBAAAAA==.',
Yo='Yoba:BAAALgAECgMJAwAAAA==.Yoshira:BAAALgADCgQJBAAAAA==.',
['Yö']='Yör:BAAALgAECgEJAQAAAA==.',
Za='Zain:BAABLgAECn9GAAQmAAkJNx35BwB2AgAmAAkJNx35BwB2AgASAAYJGA5fWQBIAQADAAIJKA0PSgBNAAAAAA==.Zandibar:BAABLgAECn8tAAISAAcJWCDvFgA3AgASAAcJWCDvFgA3AgAAAA==.Zaptoasted:BAAALgAECgUJBgAAAA==.Zaroff:BAAALgAECgYJCgAAAA==.',
Ze='Zedadiah:BAAALgADCgEJAQAAAA==.Zelah:BAAALgAECgQJBAAAAA==.Zellezugtail:BAAALgAECgQJBAABLgAECggJJgAbAGEKAA==.Zenessa:BAAALgADCgYJBgAAAA==.',
Zi='Zillah:BAAALgAECgEJAQABLgAECgcJCgAGAAAAAA==.Zinder:BAABLgAECn8oAAIFAAkJsQ49XQDHAQAFAAkJsQ49XQDHAQAAAA==.',
Zu='Zuggie:BAABLgAECn8mAAIbAAgJYQrPgQA1AQAbAAgJYQrPgQA1AQAAAA==.Zugtail:BAAALgAECgYJEwABLgAECggJJgAbAGEKAA==.Zurtrinik:BAACLgAFFH8gAAIDAAgJfB+NBAAiAgADAAgJfB+NBAAiAgAuAAQKfyUAAgMACAmZJDwCAE0DAAMACAmZJDwCAE0DAAAA.',
Zy='Zylith:BAAALgAECgYJCwABLgAECgkJMwAgAOIXAA==.Zyntalla:BAAALgAECgMJAwAAAA==.',
Zz='Zzonked:BAABLgAECn8pAAMEAAkJCwjDkABEAQAEAAkJzwbDkABEAQAkAAIJ/gtGPwBSAAAAAA==.',
['Zê']='Zêp:BAAALgAECgEJAgAAAA==.',
['Zø']='Zøømies:BAABLgAECn8xAAMLAAkJhhdHMAAFAgALAAkJUhdHMAAFAgAjAAYJFQ/XFgDvAAAAAA==.',
['Är']='Äréa:BAAALgADCgkJCQAAAA==.',
['Äs']='Äshnärd:BAACLgAFFH8MAAIeAAMJqyOBBQC7AAAeAAMJqyOBBQC7AAAuAAQKfzQAAh4ACQlUJHIFAFsDAB4ACQlUJHIFAFsDAAAA.',
['Ða']='Ðar:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðoogle:BAABLgAECn8fAAMHAAgJwxglJQDAAQAHAAgJwxglJQDAAQAeAAIJjR7vAwCpAAABLgADCgYJBgAGAAAAAA==.',
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
