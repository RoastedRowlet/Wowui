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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Protection','DeathKnight-Unholy','Mage-Frost','Unknown-Unknown','Shaman-Elemental','Priest-Holy','Druid-Restoration','Monk-Mistweaver','Mage-Arcane','Druid-Balance','Druid-Guardian','Monk-Brewmaster','Monk-Windwalker','Warrior-Fury','Evoker-Preservation','Evoker-Augmentation','Paladin-Holy','Priest-Shadow','DemonHunter-Havoc','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','DemonHunter-Devourer','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Shaman-Restoration','Shaman-Enhancement','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Vengeance','DeathKnight-Blood','Warlock-Destruction','Evoker-Devastation','DeathKnight-Frost','Priest-Discipline','Warrior-Arms','Druid-Feral','Mage-Fire',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Adrador:BAABLgAECn8pAAMBAAgJkiRWAwC4AgABAAgJkiRWAwC4AgACAAIJZxTtEwFvAAAAAA==.Adrenaline:BAACLgAFFH8TAAIDAAUJOB9oCABqAQADAAUJOB9oCABqAQAuAAQKfzkAAgMACQm8JMQBACYDAAMACQm8JMQBACYDAAAA.',
Ae='Aelik:BAACLgAFFH8HAAIEAAMJag/KeQDeAAAEAAMJag/KeQDeAAAuAAQKfygAAgQACAmOHAI3AAACAAQACAmOHAI3AAACAAAA.Aeolian:BAAALgADCgMJAwAAAA==.',
Ah='Ahkimbo:BAAALgADCgUJBQAAAA==.',
Ai='Airolanah:BAAALgAECgUJBQAAAA==.',
Al='Alayssa:BAABLgAECn8sAAIFAAkJXSAhFQDAAgAFAAkJXSAhFQDAAgAAAA==.Alda:BAAALgADCgkJEQAAAA==.Allarius:BAAALgAECgEJAQAAAA==.Allioops:BAAALgADCgUJBQABLgAECgMJBAAGAAAAAA==.Alnima:BAABLgAECn8ZAAIHAAgJzgi5OQBoAQAHAAgJzgi5OQBoAQAAAA==.',
Am='Amilee:BAAALgAECgQJDAAAAA==.Amishhunter:BAAALgADCgEJAQAAAA==.Amoondai:BAACLgAFFH8LAAIIAAMJkiBQEQARAQAIAAMJkiBQEQARAQAuAAQKfywAAggACQnFIY0CAF4DAAgACQnFIY0CAF4DAAAA.Amoondrin:BAABLgAECn8zAAIJAAkJLwk2RABcAQAJAAkJLwk2RABcAQAAAA==.Amplifier:BAAALgADCgUJBQAAAA==.',
An='Analiya:BAAALgADCgIJAgAAAA==.Antichurch:BAAALgADCgEJAQAAAA==.Antisnow:BAAALgAECgIJBAABLgAECgcJCgAGAAAAAA==.Antregon:BAAALgADCgQJBwAAAA==.',
Ar='Araviin:BAAALgAECgcJEwAAAA==.Arazen:BAAALgAECgIJAwAAAA==.Arcillias:BAAALgADCgYJCAABLgAECgYJBgAGAAAAAA==.Arkride:BAAALgAECgEJAQAAAA==.Arnadaz:BAAALgADCgEJAQABLgAFFAMJBwAKAMkWAA==.Arrogance:BAAALgADCgcJBwABLgAECgcJBwAGAAAAAA==.Arthia:BAAALgAECgQJEAAAAA==.Arvidpally:BAAALgADCgkJFQAAAA==.',
As='Ashmehameha:BAAALgADCgQJAgABLgAFFAIJAgAGAAAAAA==.Asinn:BAAALgAECgEJAQAAAA==.Asoosimov:BAAALgADCgEJAQAAAA==.',
At='Atredes:BAAALgAECgYJCAAAAA==.Attima:BAABLgAECn9BAAILAAkJWBHbAgDuAQALAAkJWBHbAgDuAQAAAA==.',
Au='Aurøra:BAAALgADCgMJAwAAAA==.Auspex:BAABLgAECn8nAAMMAAkJgwleLABEAQAMAAkJ6QdeLABEAQANAAgJiQiuKgDBAAAAAA==.',
Av='Avaryn:BAACLgAFFH8TAAIJAAUJDBHWFwBiAQAJAAUJDBHWFwBiAQAuAAQKfzgAAgkACQmZIVkHACcDAAkACQmZIVkHACcDAAAA.',
Az='Azron:BAAALgAECgYJBgABLgAECggJDAAGAAAAAA==.',
Ba='Babavoss:BAAALgAECgkJAQAAAA==.Badarack:BAAALgAECgcJEwABLgAECgkJQAAOABAfAA==.Badaracka:BAAALgAECgYJDAABLgAECgkJQAAOABAfAA==.Badarackie:BAABLgAECn9AAAMOAAkJEB+dCQDvAgAOAAgJ0iGdCQDvAgAPAAkJDhU8FADxAQAAAA==.Badash:BAABLgAECn8rAAMDAAgJBhvEDAD3AQADAAgJBhvEDAD3AQAQAAEJMQSurQAvAAABLgAFFAIJAgAGAAAAAA==.Bahamuth:BAABLgAECn9DAAICAAkJIB23GACRAgACAAkJIB23GACRAgAAAA==.Bakshi:BAAALgAECgEJBAAAAA==.Banký:BAAALgAECgEJAQAAAA==.Barbattos:BAACLgAFFH8OAAIRAAQJoheGEgAzAQARAAQJoheGEgAzAQAuAAQKfzYAAxEACQkOJB8CAD0DABEACQkOJB8CAD0DABIAAQnkJOJqAGEAAAAA.Barnabas:BAAALgADCgYJBgABLgAECgYJBgAGAAAAAA==.Barragon:BAABLgAECn8VAAITAAcJ5g8bLwB3AQATAAcJ5g8bLwB3AQAAAA==.',
Be='Beans:BAAALgAECgQJBAAAAA==.Bearymanalow:BAAALgAECgEJAQAAAA==.Bethollbrew:BAAALgAECgYJDwAAAA==.Bexley:BAABLgAECn8tAAIBAAkJChqsBgBOAgABAAkJChqsBgBOAgAAAA==.',
Bi='Biggerbunny:BAABLgAECn8uAAIUAAgJtxQSHgCtAQAUAAgJtxQSHgCtAQAAAA==.Binkter:BAAALgAECgIJBQABLgAECgIJAgAGAAAAAA==.',
Bl='Blackjax:BAAALgADCgEJAQAAAA==.Blacklok:BAAALgAECgUJEQABLgAECgkJNAAVAEElAA==.Blargle:BAABLgAECn8iAAIWAAgJ0A1fUgB+AQAWAAgJ0A1fUgB+AQAAAA==.Blessedcross:BAAALgADCggJCAAAAA==.Bleubahlz:BAAALgADCgcJBwABLgAECgMJAwAGAAAAAA==.Bloodrake:BAABLgAECn87AAIWAAkJHB6mDQDRAgAWAAkJHB6mDQDRAgAAAA==.Bloodreyne:BAAALgADCgEJAgAAAA==.Bloodseekr:BAAALgADCgQJBAAAAA==.Blueray:BAAALgAECgMJAwAAAA==.',
Bo='Boahan:BAAALgAECgMJBQABLgAECgUJCAAGAAAAAA==.Boggart:BAAALgAECgEJAQABLgAECgUJCAAGAAAAAA==.Bohein:BAAALgADCgEJAQAAAA==.Bolus:BAAALgAECgEJAgAAAA==.Botany:BAAALgAECgcJBwAAAA==.Bownafiedba:BAAALgADCgUJBQAAAA==.',
Br='Braneour:BAABLgAECn8xAAMTAAkJwBoICQDVAgATAAkJwBoICQDVAgACAAMJmgscHAFjAAAAAA==.Brassballz:BAAALgAECgkJCQAAAA==.Browel:BAABLgAECn8aAAMXAAcJWBj4CAC3AQAXAAYJ3Rj4CAC3AQAYAAYJYQ4LjAANAQAAAA==.Bruen:BAAALgAECgYJBwAAAA==.Bryci:BAAALgAECgUJBQAAAA==.',
Bu='Bubbloseven:BAAALgAECgQJCgAAAA==.Budank:BAAALgADCgMJAwAAAA==.Bumm:BAABLgAECn8WAAICAAYJzwhMvADqAAACAAYJzwhMvADqAAAAAA==.Bustybubbles:BAAALgADCgYJBgAAAA==.',
Bz='Bzspy:BAABLgAFFH8LAAIQAAMJzwxLKgDQAAAQAAMJzwxLKgDQAAAAAA==.',
Ca='Caalin:BAAALgAECgEJAgAAAA==.Cabooselul:BAAALgAECgQJCgAAAA==.Calibre:BAABLgAECn8eAAIZAAcJohUgWQBYAQAZAAcJohUgWQBYAQAAAA==.Calyptus:BAABLgAECn8fAAIYAAYJhApVmAD2AAAYAAYJhApVmAD2AAAAAA==.Caprious:BAACLgAFFH8OAAIEAAUJURlQOQBQAQAEAAUJURlQOQBQAQAuAAQKfzYAAgQACQnjJLwGACgDAAQACQnjJLwGACgDAAAA.Capylaura:BAABLgAECn8YAAIWAAYJpQfBiAD8AAAWAAYJpQfBiAD8AAAAAA==.Caratine:BAABLgAECn8XAAIZAAcJDAoVgwDxAAAZAAcJDAoVgwDxAAAAAA==.Cassandrar:BAABLgAECn8yAAQaAAkJGSQIAQA5AwAaAAgJMiQIAQA5AwAbAAYJtiDyGACqAQAcAAEJphRdHAA5AAAAAA==.Cassandraw:BAAALgAECgYJBgABLgAECgkJMgAaABkkAA==.Cat:BAAALgADCgUJBQAAAA==.Cattlelac:BAAALgADCgUJCAAAAA==.Caymus:BAABLgAECn8bAAIJAAcJgAlFWgAIAQAJAAcJgAlFWgAIAQAAAA==.',
Ce='Celìa:BAABLgAECn8kAAIWAAgJHgmWXwBaAQAWAAgJHgmWXwBaAQAAAA==.Cess:BAAALgAECgEJAgAAAA==.',
Ch='Chema:BAABLgAFFH8HAAIKAAMJyRb6JADMAAAKAAMJyRb6JADMAAAAAA==.Chestylarue:BAAALgAECgEJAQABLgAECgYJDgAGAAAAAA==.Chfgaribaldi:BAAALgADCggJDgAAAA==.Chills:BAAALgAECgcJEQAAAA==.Chillymage:BAAALgADCgYJBgAAAA==.Chosen:BAABLgAECn8YAAICAAYJRBdtYgC+AQACAAYJRBdtYgC+AQABLgAFFAUJEgAEAPsgAA==.Chpchop:BAAALgADCgIJAgAAAA==.Christy:BAAALgADCgkJEQAAAA==.Chugg:BAABLgAECn8dAAIdAAgJFwnCVAArAQAdAAgJFwnCVAArAQAAAA==.',
Ci='Ciaphus:BAABLgAECn8nAAICAAkJ0hTjNQAJAgACAAkJ0hTjNQAJAgAAAA==.Cinnamonster:BAAALgAECgYJCQAAAA==.',
Co='Coffeedemon:BAAALgADCgEJAQAAAA==.Coldslappins:BAAALgAECggJCgAAAA==.Contagion:BAAALgAECgYJBQAAAA==.Convoke:BAABLgAECn8eAAIMAAcJDSArFgBeAgAMAAcJDSArFgBeAgAAAA==.',
Cu='Cubcake:BAAALgADCggJCAAAAA==.Curtastrophe:BAABLgAECn89AAIFAAkJHx1WHgCMAgAFAAkJHx1WHgCMAgAAAA==.Curticus:BAAALgADCgQJBAAAAA==.Curtissax:BAAALgAECgIJAgAAAA==.Curtnought:BAAALgADCgIJAgAAAA==.',
['Cé']='Cérnùnnøs:BAAALgAECgEJAQAAAA==.',
Da='Daelanos:BAABLgAECn8cAAIQAAgJPBh0JwCaAQAQAAgJPBh0JwCaAQAAAA==.Dalinar:BAAALgAECgMJCQAAAA==.Daranger:BAAALgADCgEJAQAAAA==.Darska:BAAALgADCgYJBgABLgAECgYJBwAGAAAAAA==.',
De='Deadtauren:BAAALgADCgYJDwAAAA==.Deathdemon:BAAALgAECgUJCQAAAA==.Deathfue:BAAALgAECgEJAwABLgAECgcJCgAGAAAAAA==.Deathisreal:BAAALgADCgMJAwABLgAECgQJCAAGAAAAAA==.Decimated:BAACLgAFFH8SAAIEAAUJ+yAaLQBsAQAEAAUJ+yAaLQBsAQAuAAQKfx4AAgQACQmVIt4UAKoCAAQACQmVIt4UAKoCAAAA.Demon:BAAALgAECgkJDAAAAA==.Demonilla:BAAALgAECgYJBwAAAA==.Dempkiston:BAAALgADCggJCQAAAA==.Denable:BAABLgAECn8cAAIJAAYJ7A8jUQAoAQAJAAYJ7A8jUQAoAQAAAA==.Denogan:BAAALgAECggJDAAAAA==.Deservis:BAAALgAECgUJDgABLgAECgcJHgAZAKIVAA==.Destro:BAABLgAECn8nAAIYAAkJ7w+qOgDXAQAYAAkJ7w+qOgDXAQABLgAECgkJLQAeAAkWAA==.Dethadin:BAAALgADCgcJBwAAAA==.',
Di='Dilaudyd:BAAALgAECgMJBAAAAA==.Dirteemike:BAAALgADCgMJAwAAAA==.Disbeleaf:BAABLgAECn8VAAMJAAYJARl4MwCsAQAJAAYJARl4MwCsAQAMAAUJUSAIJgBuAQAAAA==.Discoflurry:BAAALgAECgcJDgABLgAFFAQJCgADAN8hAA==.Dizzyfist:BAAALgAECgYJCQABLgAECggJDAAGAAAAAA==.',
Do='Dogaz:BAAALgADCgkJDwAAAA==.Dogsoldier:BAAALgADCgIJAgAAAA==.Donori:BAAALgAECgQJDQAAAA==.Dorcath:BAAALgAFFAIJBAABLgAECggJHAAQADwYAA==.',
Dr='Dragan:BAAALgAECgQJDAAAAA==.Dragapult:BAAALgAECggJAwAAAA==.Dragonias:BAABLgAECn8VAAIfAAcJQRPvDgBDAQAfAAcJQRPvDgBDAQAAAA==.Draino:BAAALgADCgUJBQAAAA==.Drakthorn:BAAALgAECgcJCgAAAA==.Dreselwings:BAAALgAECggJCAABLgAFFAgJHgAWAJsfAA==.Drinny:BAABLgAECn8yAAIIAAkJtwigKQBWAQAIAAkJtwigKQBWAQAAAA==.Drqueenisin:BAAALgADCggJEwAAAA==.Druido:BAAALgADCgYJCwAAAA==.',
Du='Duerek:BAAALgAECgUJBgAAAA==.',
['Dè']='Dèaths:BAAALgAECgYJEAAAAA==.',
Ea='Earthangel:BAABLgAECn8cAAIIAAYJQBcjJwBpAQAIAAYJQBcjJwBpAQAAAA==.',
Ed='Edlarel:BAAALgADCgQJBAABLgAECgcJBwAGAAAAAA==.',
Ei='Eine:BAABLgAECn9CAAIWAAkJsxUCJQAjAgAWAAkJsxUCJQAjAgAAAA==.Eitherwind:BAABLgAECn8XAAQgAAYJ2h+cGgCrAQAgAAYJ2h+cGgCrAQAWAAIJchT/qwBsAAAfAAIJNxPOMgA0AAABLgAECggJDAAGAAAAAA==.',
Ek='Ekoh:BAAALgAECgEJAgAAAA==.',
El='Eldergreen:BAABLgAECn8iAAIJAAgJzQkOXQD/AAAJAAgJzQkOXQD/AAAAAA==.Eldest:BAAALgADCgUJBQAAAA==.Elfwine:BAABLgAECn8cAAIUAAYJKA2mOAAJAQAUAAYJKA2mOAAJAQAAAA==.Elindria:BAABLgAECn80AAQVAAkJQSX9AQAsAwAVAAkJHiX9AQAsAwAhAAkJhiFfAQD8AgAZAAUJMxu6ewA0AQAAAA==.Eliora:BAAALgADCgkJCQAAAA==.Elminstir:BAAALgAECgcJDwAAAA==.Elyissia:BAAALgAECgYJDAAAAA==.Elynisa:BAAALgAECgEJAQAAAA==.Elysian:BAABLgAECn84AAQKAAkJcxzuCADYAgAKAAkJcxzuCADYAgAPAAgJaB9/DABWAgAOAAIJyh8hTgCsAAAAAA==.',
Em='Emogo:BAAALgADCgUJCQAAAA==.',
En='Enforcer:BAAALgADCgQJBgAAAA==.Enlightened:BAAALgAECgQJCwAAAA==.Enseral:BAAALgAECgYJCwAAAA==.',
Eo='Eotech:BAAALgAECgQJBAAAAA==.',
Er='Erendora:BAABLgAECn8ZAAIJAAcJDBAwTAA6AQAJAAcJDBAwTAA6AQAAAA==.Erets:BAAALgAECgEJAQAAAA==.Eridar:BAAALgAECgYJBgAAAA==.Erizhal:BAAALgAECgUJEAAAAA==.Erodora:BAAALgADCgEJAQAAAA==.',
Ev='Eva:BAAALgAECgEJAgAAAA==.Eviae:BAABLgAECn8dAAIiAAYJ3gmJLgC6AAAiAAYJ3gmJLgC6AAAAAA==.Evillure:BAABLgAECn8lAAMEAAkJ8hNFNQAGAgAEAAkJ8hNFNQAGAgAiAAUJkgzZMQCmAAAAAA==.',
Fa='Falan:BAABLgAECn8dAAIdAAgJdhI+MADEAQAdAAgJdhI+MADEAQAAAA==.Faputa:BAAALgAECgMJAwAAAA==.Fatherjoe:BAAALgADCgYJBgAAAA==.Fayze:BAEBLgAECn8WAAMaAAcJfiPjAwA+AgAaAAcJSCPjAwA+AgAbAAEJMyVfQgBtAAABLgAFFAIJAwAGAAAAAA==.',
Fe='Felbreaker:BAAALgAECgYJCwAAAA==.Fentril:BAAALgADCgIJAgABLgAECggJDAAGAAAAAA==.Feår:BAABLgAECn8eAAMYAAkJJQxKaQBTAQAYAAgJQgpKaQBTAQAjAAMJ3Q8RSwCMAAAAAA==.',
Fi='Fillianora:BAAALgAECgIJAgAAAA==.Finley:BAAALgAECgQJBQAAAA==.Fircane:BAAALgADCgQJBAAAAA==.Firiel:BAAALgADCgEJAQAAAA==.Fizzle:BAAALgADCggJCAABLgAECgkJIAAJAHAWAA==.',
Fl='Flane:BAAALgAFFAEJAgABLgAFFAYJFgADAB8iAA==.Flem:BAAALgAECgMJBAAAAA==.Flexdruid:BAAALgAECgUJCgAAAA==.',
Fo='Foog:BAAALgAECgYJDQAAAA==.',
Fr='Fragil:BAABLgAECn8rAAIbAAgJ6xwWEQD9AQAbAAgJ6xwWEQD9AQAAAA==.Frostmane:BAACLgAFFH8KAAIEAAQJIhsRRAA+AQAEAAQJIhsRRAA+AQAuAAQKfzkAAwQACQlWJUoDAFoDAAQACQlWJUoDAFoDACIABwn+HMANADECAAAA.Frostynug:BAAALgADCgYJBgAAAA==.',
Fu='Fudge:BAAALgADCgYJBgAAAA==.Furbyn:BAAALgADCgIJAgAAAA==.',
Ga='Galena:BAABLgAECn8XAAIJAAcJtQq8VwARAQAJAAcJtQq8VwARAQAAAA==.Gallamier:BAAALgADCgEJAQAAAA==.Gamerinator:BAAALgADCgcJCwAAAA==.',
Ge='Geshtal:BAAALgAECgQJCgAAAA==.Gets:BAAALgADCgIJAgAAAA==.',
Gi='Girion:BAABLgAECn8dAAIBAAYJkA1eIwDJAAABAAYJkA1eIwDJAAAAAA==.Girliepop:BAAALgAECgEJAQAAAA==.',
Gl='Glaiven:BAECLgAFFH8PAAMZAAUJww4rOgAQAQAZAAQJ0w0rOgAQAQAhAAMJuA/xCQBkAAAuAAQKfy8AAyEACQmVIVIDAIMCABkACQkrH6EdAKACACEACQmXHFIDAIMCAAAA.Glorfinndel:BAAALgADCgQJBAAAAA==.Glyr:BAAALgADCgUJBQAAAA==.',
Go='Gorgrin:BAAALgAECgcJEQAAAA==.Goude:BAAALgADCgIJAgAAAA==.',
Gr='Greenback:BAAALgADCgYJCwAAAA==.Greentotes:BAABLgAECn8vAAMSAAkJ7x+9BgDYAgASAAkJ7x+9BgDYAgAkAAQJdgY1LgCoAAAAAA==.',
Gu='Gunter:BAAALgAECgMJAwABLgAFFAUJEgAEAPsgAA==.Gura:BAAALgADCgEJAQAAAA==.Gurnee:BAAALgADCgcJDQABLgAECggJEAAGAAAAAA==.Guthix:BAAALgAECgUJBgAAAA==.',
['Gê']='Gêm:BAABLgAECn8vAAIRAAgJpBOsDQDQAQARAAgJpBOsDQDQAQAAAA==.',
['Gï']='Gïmlï:BAAALgADCgMJAwAAAA==.',
Ha='Haildydra:BAAALgAECgEJAQABLgAECgcJCgAGAAAAAA==.Halibell:BAAALgAECgYJDAAAAA==.Halnan:BAAALgADCgEJAQABLgAECgcJHgAZAKIVAA==.Harkanum:BAABLgAECn9GAAQkAAkJ9hkpBQDxAQAkAAgJLhgpBQDxAQARAAkJGg22DwCsAQASAAQJrxPwPgDuAAAAAA==.Hartman:BAAALgAECgIJAQAAAA==.Harvester:BAAALgAECgEJAQAAAA==.Hatebreéd:BAAALgAECggJCQAAAA==.',
He='Healinturds:BAAALgAECgYJDAABLgAECgcJHgAZAKIVAA==.Hector:BAABLgAECn8eAAICAAkJfSIAHAB/AgACAAkJfSIAHAB/AgAAAA==.Heelys:BAAALgAECgYJCgAAAA==.Helloagain:BAACLgAFFH8RAAIFAAQJxxh4NgBWAQAFAAQJxxh4NgBWAQAuAAQKfyMAAgUABglqIyFdACMCAAUABglqIyFdACMCAAAA.Herryknutsak:BAAALgAECgEJAQAAAA==.Hestonater:BAAALgADCggJCwAAAA==.Hestra:BAAALgADCgIJAgAAAA==.',
Hi='Hidethetotem:BAABLgAECn8eAAIdAAgJcB3qEQCTAgAdAAgJcB3qEQCTAgAAAA==.Hightops:BAAALgAECggJDgAAAA==.Hikari:BAACLgAFFH8NAAICAAUJLA6KNQAiAQACAAUJLA6KNQAiAQAuAAQKfx4AAgIACQlrHOAsAHACAAIACQlrHOAsAHACAAAA.Hiown:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.',
Ho='Holeliness:BAAALgAECggJEwAAAA==.Holybackshot:BAAALgAECgQJBgAAAA==.Holydisco:BAAALgADCgcJCQAAAA==.Holyhide:BAAALgAECgEJAQAAAA==.Holyspike:BAABLgAECn8XAAIdAAcJ+g+ORwBcAQAdAAcJ+g+ORwBcAQAAAA==.Holytard:BAAALgADCgYJBgAAAA==.Holytaren:BAABLgAECn8UAAITAAgJ3RuFDwB6AgATAAgJ3RuFDwB6AgAAAA==.Holytickles:BAABLgAECn8rAAMUAAkJ4hsCEwBeAgAUAAgJ+hsCEwBeAgAIAAkJMRd7DwBKAgABLgAFFAYJFQAYAJoTAA==.Holytotem:BAAALgAECgEJAQAAAA==.Homerr:BAABLgAECn8aAAIWAAcJZBPNUgB8AQAWAAcJZBPNUgB8AQAAAA==.Honiahaka:BAABLgAECn9DAAIWAAkJBxBVNgDZAQAWAAkJBxBVNgDZAQAAAA==.Hottcakes:BAAALgADCgIJAgABLgAFFAYJFQAYAJoTAA==.',
Hu='Huckster:BAABLgAECn8ZAAIEAAgJhQ4TaAByAQAEAAgJhQ4TaAByAQAAAA==.Humanoidholy:BAABLgAECn8fAAMCAAgJXSQ6CQBIAwACAAgJXSQ6CQBIAwABAAEJbgXWTQAYAAABLgAFFAQJCgAZAJQaAA==.Humanoidhunt:BAAALgAECgIJAwABLgAFFAQJCgAZAJQaAA==.Humanoidvoid:BAACLgAFFH8KAAMZAAQJlBpcOwAMAQAZAAMJ9h1cOwAMAQAVAAMJoBUbEADrAAAuAAQKf04ABBkACQkFI98EACcDABkACQmdIt8EACcDABUACAnlH5cHAIwCACEACAkoCIYRAAcBAAAA.',
Hy='Hydrah:BAAALgAECgEJAQABLgAECgcJCgAGAAAAAA==.',
Ic='Icedtea:BAAALgAECgcJBAAAAA==.Icicle:BAAALgADCgIJAgAAAA==.',
Id='Idunasil:BAAALgAECgEJAQAAAA==.',
Ih='Ihatemustard:BAABLgAECn8hAAIhAAkJwBWxBgD4AQAhAAkJwBWxBgD4AQAAAA==.',
Il='Illethan:BAAALgADCgYJBgAAAA==.Iloveketchup:BAAALgAECgIJBAAAAA==.',
In='Inoru:BAAALgAECgcJCgAAAA==.Insanity:BAAALgAECgUJCgAAAA==.',
Ir='Irmaline:BAABLgAECn8XAAIIAAcJVBT9IgCIAQAIAAcJVBT9IgCIAQAAAA==.',
It='Ithurtshuh:BAAALgAECgQJCAAAAA==.Itsmaam:BAAALgAECgMJBAAAAA==.Itzcannibal:BAACLgAFFH8FAAIWAAIJ6grPYgCNAAAWAAIJ6grPYgCNAAAuAAQKfy4AAxYACQk4G0ofAEECABYACQk4G0ofAEECAB8AAgnVCux5AFoAAAAA.',
Ja='Jabbawockie:BAAALgAECgkJAgAAAA==.Jaekoby:BAAALgAECgIJAwABLgAECggJIQACAEIaAA==.Jakoby:BAAALgAECgUJBgABLgAECggJIQACAEIaAA==.Jandrisel:BAAALgAECgYJCwAAAA==.Jayzich:BAAALgADCgQJBwAAAA==.',
Je='Jeffee:BAAALgAECgIJCQAAAA==.Jequalsjosh:BAABLgAECn87AAIaAAkJsCHVAQC2AgAaAAkJsCHVAQC2AgAAAA==.Jerk:BAAALgAECgQJBAAAAA==.Jerp:BAAALgAECgIJAgAAAA==.Jesper:BAABLgAECn9GAAIdAAkJ5B8LBwAZAwAdAAkJ5B8LBwAZAwAAAA==.Jetz:BAAALgAECgEJAQAAAA==.Jezelle:BAACLgAFFH8RAAIYAAUJDRAYRAAcAQAYAAUJDRAYRAAcAQAuAAQKfyIAAhgACQn0Hg42ADQCABgACQn0Hg42ADQCAAAA.',
Ji='Jilara:BAABLgAECn8pAAICAAgJ2AXZnwAWAQACAAgJ2AXZnwAWAQAAAA==.Jimmyjim:BAABLgAECn8WAAIFAAcJDQx1kQA6AQAFAAcJDQx1kQA6AQAAAA==.Jingying:BAAALgADCgMJAwAAAA==.',
Jo='Johnny:BAAALgADCgQJBAAAAA==.',
Jp='Jpepps:BAABLgAECn8vAAMYAAkJDRPsMgD1AQAYAAkJDRPsMgD1AQAjAAMJxwjoRQCeAAAAAA==.',
Jr='Jrose:BAAALgAECgQJBAAAAA==.',
['Jæ']='Jækobÿ:BAAALgAECgIJAgABLgAECggJIQACAEIaAA==.',
Ka='Kahlanrahl:BAAALgADCgMJAwAAAA==.Kaiatra:BAABLgAECn8WAAIlAAcJbSIHBgAKAgAlAAcJbSIHBgAKAgAAAA==.Kaliguala:BAAALgAECgQJBQAAAA==.Katare:BAAALgAECgMJAwAAAA==.Kaulder:BAAALgADCgUJBQAAAA==.Kaìju:BAABLgAECn8hAAICAAgJGh4yIQBjAgACAAgJGh4yIQBjAgAAAA==.',
Ke='Kellytgt:BAABLgAECn8sAAIZAAkJjBfSIwAiAgAZAAkJjBfSIwAiAgAAAA==.Kev:BAAALgADCgUJBQAAAA==.',
Ki='Kilaura:BAABLgAECn8ZAAImAAgJWRAfHAC/AQAmAAgJWRAfHAC/AQAAAA==.Kilmandaros:BAAALgADCgYJCwAAAA==.Kippi:BAAALgAECgQJCwAAAA==.',
Ko='Korhina:BAABLgAECn9GAAIDAAkJeyaEAABuAwADAAkJeyaEAABuAwAAAA==.Korobas:BAAALgAECgMJAwAAAA==.Koru:BAAALgAECgQJBQABLgAECgQJBgAGAAAAAA==.Kosumi:BAAALgADCggJDQAAAA==.',
Kr='Kronic:BAAALgAECgQJBwAAAA==.',
Ku='Kuroyukihime:BAABLgAECn8wAAIFAAkJqh5VHACXAgAFAAkJqh5VHACXAgAAAA==.Kuwaii:BAABLgAECn8dAAISAAcJuxg5IgCmAQASAAcJuxg5IgCmAQABLgAECggJHgAMAA0gAA==.',
Ky='Kyarina:BAAALgAECgEJAQABLgAECgkJGQAIAEMHAA==.Kylis:BAAALgAECgMJAwAAAA==.Kyna:BAABLgAECn8ZAAIIAAkJQwceMwAWAQAIAAkJQwceMwAWAQAAAA==.Kyross:BAAALgADCgIJAgAAAA==.',
['Ké']='Kéya:BAAALgADCgUJCAAAAA==.',
La='Lashela:BAABLgAECn8UAAIWAAgJxwouWQBrAQAWAAgJxwouWQBrAQAAAA==.Laughter:BAAALgAECgYJEgAAAA==.Laurana:BAAALgADCgIJAgAAAA==.Lazulie:BAAALgAECgYJEAAAAA==.',
Le='Leansipper:BAABLgAFFH8KAAIMAAMJEBYTIQDtAAAMAAMJEBYTIQDtAAAAAA==.Levoker:BAAALgAECgQJBAAAAA==.Lexapayne:BAAALgAECgYJDgABLgAECggJJwAWAGYWAA==.',
Li='Lighthammer:BAAALgADCgEJAQAAAA==.Lilandra:BAAALgAECgYJBgABLgAECgYJBwAGAAAAAA==.Lillianaxe:BAAALgAECgcJEQAAAA==.Lilyvain:BAAALgAECgUJCAAAAA==.Lireal:BAABLgAECn8mAAITAAkJ9yNFAgByAwATAAkJ9yNFAgByAwAAAA==.Listerine:BAAALgAECgcJBwAAAA==.Litercola:BAAALgAECgYJDwAAAA==.Livnod:BAAALgAECgMJCQAAAA==.',
Lo='Loonfabio:BAAALgAECgEJAQABLgAFFAQJEQACACUjAA==.Loosescrew:BAAALgADCgIJAgAAAA==.Lorine:BAABLgAECn87AAIBAAkJbBtDCAAkAgABAAkJbBtDCAAkAgAAAA==.Lowkie:BAAALgADCgIJAgAAAA==.',
Lu='Luckside:BAAALgAECgQJBAABLgAECgkJHgAYACUMAA==.Lunaera:BAAALgADCgkJFAAAAA==.Lunafae:BAAALgADCgYJCQABLgADCgkJFAAGAAAAAA==.Lunafeather:BAAALgADCgYJCgABLgADCgkJFAAGAAAAAA==.Lunara:BAAALgAECgMJBgAAAA==.Lunasnow:BAAALgAECgQJBAAAAA==.Lunchtime:BAAALgAECgEJAQAAAA==.Luxe:BAAALgADCgEJAQAAAA==.',
Ly='Lyntot:BAAALgADCgEJAQAAAA==.',
['Ló']='Lókki:BAAALgAECgUJCAAAAA==.',
Ma='Madwe:BAABLgAECn8hAAMZAAgJrgccfAAAAQAZAAgJcwYcfAAAAQAVAAMJcAagQQBvAAAAAA==.Mageab:BAABLgAFFH8HAAIFAAYJDB2nFQDdAQAFAAYJDB2nFQDdAQAAAA==.Magis:BAAALgADCgkJHAAAAA==.Malzzahar:BAAALgAECgQJBAAAAA==.Manimetal:BAAALgAECgUJCwAAAA==.Materia:BAAALgAECgcJBwAAAA==.',
Me='Meeralax:BAAALgAECgYJEQAAAA==.Melizza:BAAALgADCgMJAwAAAA==.Merckel:BAABLgAECn8rAAIZAAgJOSBNFwBtAgAZAAgJOSBNFwBtAgAAAA==.Merckz:BAAALgAECgUJBQABLgAECggJKwAZADkgAA==.Merks:BAAALgAECgEJAQAAAA==.Metalmonkey:BAAALgAECgQJBAAAAA==.',
Mi='Michello:BAABLgAECn8VAAIWAAcJRh66NQDcAQAWAAcJRh66NQDcAQAAAA==.Mickcowmoose:BAAALgADCgIJAgAAAA==.Millia:BAABLgAECn8fAAIFAAgJaxtFNwAfAgAFAAgJaxtFNwAfAgABLgAECgkJHgACAH0iAA==.Mint:BAABLgAECn8jAAITAAcJiyNKDACmAgATAAcJiyNKDACmAgAAAA==.Mintberrytea:BAAALgAECgQJBAABLgAECgcJIwATAIsjAA==.Mintchaitea:BAAALgAFFAEJAQABLgAECgcJIwATAIsjAA==.Misstress:BAABLgAECn8vAAMMAAgJ+w1xKQBWAQAMAAgJ+w1xKQBWAQANAAEJ/giGWQAlAAAAAA==.Mizen:BAAALgADCgUJCAAAAA==.',
Mo='Mogdor:BAAALgADCgUJBQAAAA==.Monkussy:BAAALgAECgIJAgAAAA==.Moonhunt:BAAALgAECgMJCQAAAA==.Moonly:BAABLgAECn8kAAIgAAkJXgwpFwDLAQAgAAkJXgwpFwDLAQAAAA==.Morrag:BAABLgAECn8cAAMYAAcJ0Qp6eAAzAQAYAAcJzwp6eAAzAQAXAAEJjAZvMgAvAAAAAA==.',
Mu='Murdumurdu:BAAALgAECgUJCAAAAA==.Murkblade:BAAALgADCgYJBgABLgAECgcJHgAZAKIVAA==.Musho:BAAALgADCgYJEgAAAA==.',
My='Myn:BAABLgAECn8VAAIJAAgJOBrQGQBTAgAJAAgJOBrQGQBTAgAAAA==.Myw:BAAALgAECgcJBwABLgAFFAcJIgAdABoXAA==.',
['Mæ']='Mædenless:BAAALgAECgYJCQAAAA==.',
['Mí']='Mísfìt:BAABLgAECn88AAMdAAkJQRmMGgBJAgAdAAkJQRmMGgBJAgAHAAgJEQyCMQBJAQAAAA==.',
Na='Nakaito:BAABLgAECn8XAAIYAAcJrgxodwA1AQAYAAcJrgxodwA1AQABLgAECgkJLQAaAPIXAA==.Narcoleptic:BAACLgAFFH8GAAIRAAMJiAxVGgC+AAARAAMJiAxVGgC+AAAuAAQKfzkABBEACQnqGMMFAJACABEACQnqGMMFAJACABIACAkMEz0nAIYBACQABAmuBVQvAJ0AAAAA.',
Ne='Neocracy:BAAALgADCgYJCwABLgAECggJFAATAN0bAA==.Nex:BAAALgADCgYJCAAAAA==.',
Ni='Niceshield:BAAALgAECgEJAwAAAA==.Nightmarexx:BAACLgAFFH8VAAIbAAUJZh4MEABZAQAbAAUJZh4MEABZAQAuAAQKf04AAhsACAmnIeYHAIcCABsACAmnIeYHAIcCAAAA.Nightsawdy:BAABLgAECn8eAAMWAAgJYRPaWgBmAQAWAAcJaBPaWgBmAQAgAAYJNxHlKAA2AQAAAA==.Nightsnake:BAAALgAECgMJAwAAAA==.Niightstorm:BAABLgAECn8bAAMWAAYJPRycbwAzAQAWAAUJAB2cbwAzAQAgAAQJbBLmNgDTAAAAAA==.Nikwillig:BAAALgAECggJCwAAAA==.Nilveron:BAAALgADCgcJCQAAAA==.Nitefire:BAAALgADCgkJEQAAAA==.',
Nj='Njörðr:BAAALgAECgYJDAAAAA==.',
Nt='Ntadadarknes:BAAALgAECgIJAwABLgAECggJIgAJAM0JAA==.',
Oo='Ooblidoom:BAAALgADCgUJBQABLgAECgYJFgAgABgKAA==.',
Op='Opalinnas:BAABLgAECn8gAAMJAAkJcBbvJwDwAQAJAAkJcBbvJwDwAQAMAAUJeQhxTgCiAAAAAA==.',
Oz='Ozath:BAAALgAECgQJBgAAAA==.',
Pa='Passionfruit:BAAALgAECgUJCgAAAA==.',
Pe='Peachtea:BAAALgAECgQJEAAAAA==.',
Ph='Phatshaman:BAABLgAECn8UAAIHAAgJbQe8QQD8AAAHAAgJbQe8QQD8AAAAAA==.Phæryll:BAAALgADCgUJBgAAAA==.',
Pi='Pirodeath:BAAALgAECgcJCgAAAA==.',
Po='Poisonclaw:BAAALgAECgIJBAAAAA==.Poprotonix:BAABLgAECn8bAAICAAgJrBK8TADCAQACAAgJrBK8TADCAQAAAA==.Pozessedkaos:BAAALgAECgQJBAAAAA==.',
Pr='Praecantrix:BAAALgAECgEJBAAAAA==.Prath:BAAALgADCgEJAQAAAA==.Pray:BAABLgAECn9DAAImAAkJBCTBAQCXAwAmAAkJBCTBAQCXAwAAAA==.Priestyballz:BAAALgAECgYJBgAAAA==.Prodarkangel:BAABLgAECn8bAAMjAAkJIglsEgD0AAAjAAkJIglsEgD0AAAYAAMJaANn7wBbAAAAAA==.',
Pu='Pubis:BAAALgAECgYJDgAAAA==.Puckllane:BAABLgAECn8aAAICAAkJ5RdiQQAhAgACAAkJ5RdiQQAhAgAAAA==.Punkbeer:BAAALgAECgEJAQAAAA==.Punkin:BAAALgAECgMJCQAAAA==.',
Py='Pyre:BAABLgAECn89AAImAAkJSQ+5GQDWAQAmAAkJSQ+5GQDWAQABLgADCgUJBQAGAAAAAA==.',
Qu='Quefstank:BAAALgADCgUJCAAAAA==.Quivver:BAAALgADCgkJDgAAAA==.',
Ra='Rabmaxx:BAABLgAECn8gAAIVAAYJIA59KgDvAAAVAAYJIA59KgDvAAAAAA==.Radren:BAAALgADCgEJAQAAAA==.Rajinazn:BAAALgAECgEJAQAAAA==.Rattchett:BAAALgAECgYJBgAAAA==.Ravenlight:BAABLgAFFH8FAAICAAQJWA6DMwAnAQACAAQJWA6DMwAnAQAAAA==.Ravenwynnd:BAABLgAECn8mAAInAAkJuyILAwDiAgAnAAkJuyILAwDiAgAAAA==.Raynelock:BAABLgAECn8wAAMjAAkJgRAnCACfAQAjAAkJgRAnCACfAQAYAAIJtQcZCQFKAAAAAA==.Raynman:BAABLgAECn9DAAIdAAkJdxUWHgAvAgAdAAkJdxUWHgAvAgAAAA==.Razgriz:BAAALgAECgEJAQAAAA==.Razix:BAABLgAECn8yAAQSAAkJfxTNGgDfAQASAAkJfxTNGgDfAQAkAAYJ6wkJFQCZAAARAAMJYwclPACJAAAAAA==.',
Re='Realist:BAAALgAECgMJBAAAAA==.Reija:BAAALgAECgEJAgAAAA==.Repentance:BAAALgADCgEJAQABLgAECgkJLQAeAAkWAA==.Revealed:BAAALgADCgEJAQAAAA==.Rezzarn:BAAALgAECgEJAQAAAA==.',
Rh='Rhun:BAAALgAECgYJCQAAAA==.Rhyzer:BAABLgAECn8dAAMQAAYJ7BdrMgBbAQAQAAYJ7BdrMgBbAQAnAAEJJQ1bRQAuAAAAAA==.',
Ri='Rileyksufan:BAABLgAECn8VAAIWAAkJhg6lZQBLAQAWAAkJhg6lZQBLAQAAAA==.Rinas:BAABLgAECn80AAMVAAkJqyAGAwAFAwAVAAkJqyAGAwAFAwAZAAIJnw2Q6wA1AAAAAA==.Rivendell:BAAALgAECgEJAgAAAA==.Rivenlynn:BAAALgADCgEJAQAAAA==.',
Ru='Rubioxis:BAAALgADCgYJBgAAAA==.',
Ry='Rymarri:BAAALgADCgkJCQAAAA==.',
Sa='Sabazia:BAACLgAFFH8HAAIiAAIJ7BvsHgCvAAAiAAIJ7BvsHgCvAAAuAAQKfzoAAiIACQkXIFEFALUCACIACQkXIFEFALUCAAAA.Sacrificer:BAAALgAECgMJAwAAAA==.Sairalindë:BAABLgAECn8XAAMWAAgJbgN5hgABAQAWAAgJbgN5hgABAQAfAAMJpAA3hgA2AAAAAA==.Saleath:BAAALgAECgEJAwAAAA==.Salios:BAABLgAFFH8NAAIYAAQJNB6wFwAzAQAYAAQJNB6wFwAzAQAAAA==.Sallydisco:BAAALgAECgMJAwABLgAFFAQJCgADAN8hAA==.Sanctifier:BAAALgAECgQJDQAAAA==.Saraneth:BAAALgAECgEJAQABLgAECgkJJgATAPcjAA==.',
Sc='Scandrel:BAAALgAECgQJBAABLgAFFAUJEgAEAPsgAA==.Scrept:BAAALgAECgUJEQAAAA==.Scynix:BAEBLgAECn8oAAMSAAkJKhdPFwD8AQASAAkJKhdPFwD8AQARAAEJsgFhTgAiAAAAAA==.',
Se='Sedaline:BAAALgAECgQJBgAAAA==.Sephie:BAAALgADCgQJAQAAAQ==.Serenilock:BAAALgADCgMJAwAAAA==.Serfdog:BAAALgADCgcJDAAAAA==.Servoker:BAACLgAFFH8RAAIRAAYJXxt+DACaAQARAAYJXxt+DACaAQAuAAQKfyUAAxIACAnbICEKANQCABIACAnbICEKANQCABEABwkkGrwVAPABAAAA.Setani:BAAALgADCgIJAgAAAA==.',
Sh='Shabzkaw:BAAALgADCgUJBQAAAA==.Shabzyt:BAAALgADCgQJBAAAAA==.Shaienne:BAAALgAECgMJAwAAAA==.Shambussy:BAAALgAECgEJAQAAAA==.Shamfore:BAAALgADCgEJAQAAAA==.Shamrockshak:BAABLgAECn8aAAIdAAYJAyMyGgBMAgAdAAYJAyMyGgBMAgAAAA==.Shaze:BAAALgADCgcJBwAAAA==.Shenuton:BAAALgAECgQJCQAAAA==.Shieldinterd:BAAALgAECgMJAgABLgAECgcJHgAZAKIVAA==.Shiftkicker:BAAALgADCgMJAwAAAA==.Shocktherapy:BAAALgAECgEJAQAAAA==.Shockthêràpy:BAACLgAFFH8GAAIdAAIJ8BCsGgCQAAAdAAIJ8BCsGgCQAAAuAAQKfzAABB0ACQlbGG0nAPMBAB0ACQlbGG0nAPMBAAcAAwkWF4FYAKsAAB4AAQlPCkYrADgAAAAA.Shoes:BAABLgAECn89AAQgAAkJTSWCAQAzAwAgAAkJxiOCAQAzAwAfAAgJIx/cDQDVAgAWAAgJ9SLOHABPAgAAAA==.Shtdruid:BAAALgAECgUJBQAAAA==.Shyanni:BAAALgADCgMJAwAAAA==.Shöçkér:BAAALgAECgQJBAAAAA==.',
Si='Siaana:BAAALgADCgUJBQABLgAFFAIJBwAiAOwbAA==.Sibearian:BAABLgAECn8dAAQNAAcJfBm9EQCVAQANAAcJfBm9EQCVAQAoAAYJ0AqQHQDgAAAMAAIJPwSEdQBNAAAAAA==.Simi:BAABLgAECn8nAAIWAAgJZhaQPADDAQAWAAgJZhaQPADDAQAAAA==.',
Sk='Skrubzz:BAABLgAECn8ZAAMDAAgJIQbpIAA4AQADAAgJIQbpIAA4AQAQAAQJzgKHhwChAAAAAA==.Skôrn:BAABLgAECn8wAAIFAAcJLQ9ogwBUAQAFAAcJLQ9ogwBUAQAAAA==.',
Sl='Sloppynachos:BAABLgAECn8pAAIbAAgJRhdmGgAvAgAbAAgJRhdmGgAvAgAAAA==.Slyman:BAAALgADCgUJBQABLgAECgYJBwAGAAAAAA==.',
Sm='Smithnwesson:BAAALgAECgIJAgAAAA==.Smokesçreen:BAABLgAECn9BAAMVAAkJnR+oBADTAgAVAAkJnR+oBADTAgAZAAUJugXStgCKAAAAAA==.',
Sn='Snowhoof:BAAALgADCgUJBQAAAA==.',
So='Sogerä:BAABLgAECn8XAAIRAAgJIQU9GwAEAQARAAgJIQU9GwAEAQAAAA==.Soonerpride:BAABLgAECn8cAAICAAgJBCN7IQBhAgACAAgJBCN7IQBhAgAAAA==.Sorinmarkov:BAAALgAECgEJAgAAAA==.Source:BAAALgAECgUJCAAAAA==.',
Sp='Spearminttea:BAAALgAECgcJCwAAAA==.Spellumgud:BAAALgAECgQJBgAAAA==.',
Sq='Squiby:BAABLgAECn84AAMUAAkJoCKtBAD0AgAUAAkJoCKtBAD0AgAIAAIJmRX+ZwCNAAAAAA==.Squizzy:BAAALgAECgEJAQAAAA==.',
St='Stabfore:BAABLgAECn8eAAMbAAkJqROMDQAqAgAbAAkJqROMDQAqAgAaAAEJJgR5JQAnAAAAAA==.Standaside:BAAALgAECgIJBAAAAA==.Stinky:BAABLgAECn8XAAIcAAgJkQnKCwAtAQAcAAgJkQnKCwAtAQAAAA==.Stix:BAACLgAFFH8FAAIbAAMJwhN4HQD1AAAbAAMJwhN4HQD1AAAuAAQKfygAAxsACQm3GVISAPABABsACQm3GVISAPABABwABAmnFd4QAMoAAAAA.Stoya:BAAALgAECgQJBgABLgAECgkJJgATAPcjAA==.Stuef:BAABLgAECn82AAIHAAkJGyGtBwDBAgAHAAkJGyGtBwDBAgAAAA==.Stuefagos:BAAALgAECgQJBwAAAA==.Stuefester:BAABLgAECn8gAAMEAAkJNiDsFwCVAgAEAAkJNiDsFwCVAgAiAAcJ4QkHKwDQAAAAAA==.Stueflare:BAAALgAECggJEAAAAA==.Stueflip:BAAALgADCgIJAgAAAA==.Stunsturds:BAABLgAECn8dAAMKAAYJQiA+FgArAgAKAAYJQiA+FgArAgAOAAEJ2AF+mQAaAAABLgAECgcJHgAZAKIVAA==.Stäirs:BAABLgAECn9CAAIQAAkJ5B2rCgCYAgAQAAkJ5B2rCgCYAgAAAA==.',
Su='Summerlily:BAAALgADCgYJBgAAAA==.',
Sv='Svaja:BAAALgADCgkJEQABLgAECgcJFwARAPgGAA==.',
Sy='Sylaria:BAAALgAECgMJCQAAAA==.Syreline:BAAALgAECgEJAgAAAA==.',
['Sá']='Sáble:BAAALgAECgcJEgAAAA==.',
['Sî']='Sîn:BAAALgADCgEJAQABLgAECggJIQAYAOkYAA==.',
['Sï']='Sïn:BAABLgAECn8hAAIYAAgJ6Rg7OADgAQAYAAgJ6Rg7OADgAQAAAA==.',
Ta='Taereachye:BAACLgAFFH8GAAITAAIJriAaFQCYAAATAAIJriAaFQCYAAAuAAQKfxcAAhMABwk5JAYKANMCABMABwk5JAYKANMCAAEuAAUUAwkHAAoAyRYA.Tailon:BAAALgADCgYJBgAAAA==.Taintedlove:BAAALgADCgYJBgAAAA==.Talenelat:BAAALgADCgcJCwAAAA==.Talikas:BAAALgAECggJDgABLgAECgkJLAAZAIwXAA==.Tankin:BAAALgADCgMJAwAAAA==.Tantric:BAAALgAECgIJAgABLgAECgcJBwAGAAAAAA==.Tarathiel:BAAALgADCgQJBAAAAA==.Taurne:BAACLgAFFH8SAAIJAAUJnwqMHQA3AQAJAAUJnwqMHQA3AQAuAAQKfx4AAgkABwmzGYEwAOkBAAkABwmzGYEwAOkBAAAA.',
Te='Technique:BAAALgAECgIJAgAAAA==.Teebags:BAAALgADCgEJAQAAAA==.Teknoman:BAACLgAFFH8HAAIQAAIJ+h4ILwCnAAAQAAIJ+h4ILwCnAAAuAAQKfzoAAhAACQn+IOoHAMICABAACQn+IOoHAMICAAAA.Telmarine:BAAALgAECgMJAwAAAA==.Tempered:BAAALgAECgkJEQAAAA==.Terlemen:BAAALgAECgUJBQAAAA==.Tetsumi:BAAALgADCgYJCQABLgAECggJDAAGAAAAAA==.',
Th='Thaddeus:BAAALgAECgEJAQABLgAFFAQJDQAGAAAAAQ==.Thaitea:BAAALgAECgUJBgAAAA==.Thal:BAAALgAECgMJAwAAAA==.Thalan:BAAALgADCgEJAQAAAA==.Thalindra:BAABLgAECn8cAAIWAAYJFBo9VAB4AQAWAAYJFBo9VAB4AQAAAA==.Tharain:BAAALgADCgkJEQAAAA==.Thebigbeast:BAAALgAECgEJAQABLgAFFAYJFQAYAJoTAA==.Thecurt:BAABLgAECn9BAAIOAAkJnyR8AQBFAwAOAAkJnyR8AQBFAwAAAA==.Thedammed:BAAALgADCgEJAQAAAA==.Theholylight:BAAALgAECgMJBQAAAA==.Thehuzz:BAAALgAECggJDAAAAA==.Thermidor:BAABLgAECn8gAAIgAAkJYBV5CQBLAgAgAAkJYBV5CQBLAgAAAA==.Thorsamie:BAAALgAECgYJBwAAAA==.Thrasios:BAAALgAECgIJAgAAAA==.Thundercunti:BAAALgADCgYJDAAAAA==.',
Ti='Tiamatt:BAAALgADCgIJBAAAAA==.Ticktock:BAAALgAECgIJAgAAAA==.Timaeus:BAAALgAECgYJDgAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Titanlock:BAAALgAECgMJBwAAAA==.',
Tk='Tkdfath:BAAALgAECgYJDgAAAA==.',
To='Torvia:BAAALgAECgMJCQAAAA==.Totemix:BAAALgADCgcJEgAAAA==.Totemsoul:BAAALgAECgEJAQABLgAECgcJCgAGAAAAAA==.',
Tr='Trisinz:BAABLgAECn8fAAIMAAgJVhM1IwCCAQAMAAgJVhM1IwCCAQAAAA==.Trixa:BAAALgADCgMJAwAAAA==.',
Tu='Tuerto:BAAALgAECgYJEgAAAA==.Turbojohnson:BAAALgAECgQJBgAAAA==.Turk:BAABLgAECn9EAAMZAAkJtReYHgBAAgAZAAkJtReYHgBAAgAVAAEJCQ/BcwAxAAAAAA==.Turkish:BAABLgAECn9AAAMEAAkJZBpZKAA9AgAEAAkJZBpZKAA9AgAlAAEJ7gZMLQAqAAAAAA==.Turtledisco:BAACLgAFFH8KAAIDAAQJ3yEoCwBAAQADAAQJ3yEoCwBAAQAuAAQKfycAAgMACQnSH7sDABcDAAMACQnSH7sDABcDAAAA.',
Ty='Tychaa:BAAALgADCgkJEQAAAA==.Tylat:BAAALgADCgEJBAAAAA==.Tyranax:BAACLgAFFH8FAAImAAIJ1wrVLwCGAAAmAAIJ1wrVLwCGAAAuAAQKfzUABCYACQmcGxUIAM8CACYACQmVGhUIAM8CAAgABgnVH1IcAPoBABQABwkxE/woAF8BAAAA.Tyyregade:BAAALgADCgkJCgABLgAECggJDAAGAAAAAA==.',
Uj='Ujimas:BAAALgAECgEJAgAAAA==.',
Ur='Urawizardtui:BAACLgAFFH8RAAIFAAUJGwusUgAiAQAFAAUJGwusUgAiAQAuAAQKfz8ABAUACQmEH8oYAKoCAAUACQmEH8oYAKoCAAsABQmDCGQOAN0AACkAAQk8EKYOADcAAAAA.',
Us='Us:BAAALgAECggJCQAAAA==.',
Uz='Uzzi:BAAALgAECgEJAQAAAA==.',
Va='Vadose:BAABLgAECn8eAAIYAAcJgQqmgQBXAQAYAAcJgQqmgQBXAQABLgAECggJJwAWAGYWAA==.Vales:BAAALgAECgMJAwABLgAECgkJJAAWAP0JAA==.Valsavis:BAABLgAECn8aAAIMAAYJbRTwLgA1AQAMAAYJbRTwLgA1AQAAAA==.Valytrois:BAABLgAECn8UAAIYAAcJXQmysQD1AAAYAAcJXQmysQD1AAAAAA==.Varinix:BAAALgADCgMJBQAAAA==.',
Ve='Veggiebaha:BAAALgADCgIJAgAAAA==.Veiksla:BAABLgAECn8XAAIRAAcJ+Aa0GwD/AAARAAcJ+Aa0GwD/AAAAAA==.Velore:BAAALgADCgcJDAAAAA==.Vengerr:BAAALgAECgQJBgAAAA==.Verace:BAAALgAECgcJAQAAAA==.Verradic:BAAALgAECgYJBgABLgAECggJGQAWAI8KAA==.',
Vi='Vitur:BAABLgAECn9HAAIZAAkJ/iCTEACiAgAZAAkJ/iCTEACiAgAAAA==.',
Vo='Voidhunter:BAABLgAECn8VAAIZAAcJGwoNgAD4AAAZAAcJGwoNgAD4AAAAAA==.Voidweaver:BAAALgAECgMJBQAAAA==.Volaine:BAABLgAECn8dAAMYAAYJOwwwmwDxAAAYAAUJDgswmwDxAAAXAAIJuhRpLgA7AAAAAA==.Volt:BAABLgAECn8tAAIeAAkJCRYuCQD5AQAeAAkJCRYuCQD5AQAAAA==.Volumoso:BAAALgAECgYJBgAAAA==.Volwryn:BAAALgAECgUJCAABLgAECgcJBwAGAAAAAA==.',
Vy='Vynarian:BAABLgAECn8dAAIFAAYJ/xXRhABRAQAFAAYJ/xXRhABRAQAAAA==.',
['Vâ']='Vâljean:BAAALgADCgMJAwAAAA==.',
['Vô']='Vôx:BAAALgAECgEJAQABLgAECggJHwAPAJEYAA==.',
Wa='Warbeard:BAABLgAECn8oAAIQAAkJ8gtJJACuAQAQAAkJ8gtJJACuAQAAAA==.',
Wi='Wizwizx:BAAALgADCgUJBgAAAA==.',
Wr='Wreckbums:BAAALgAFFAIJAwAAAA==.Wreckd:BAABLgAECn8VAAMZAAYJ5hJxcAAbAQAZAAYJgRJxcAAbAQAVAAIJIgzzXQAqAAAAAA==.',
Wy='Wyth:BAAALgAECgQJBQABLgAECgQJBgAGAAAAAA==.',
Xa='Xanthad:BAAALgADCgEJAQAAAA==.',
Xb='Xb:BAAALgADCgkJDgAAAA==.',
Xi='Xitãozinho:BAAALgAECgUJBwAAAA==.',
Xo='Xolair:BAAALgAECgYJDgAAAA==.',
Ya='Yaalia:BAAALgAECgYJEAAAAA==.Yaan:BAABLgAECn8fAAIHAAcJygrgRADwAAAHAAcJygrgRADwAAAAAA==.',
Yo='Yoba:BAAALgAECgMJAwAAAA==.Yoshira:BAAALgADCgQJBAAAAA==.',
['Yö']='Yör:BAAALgAECgEJAQAAAA==.',
Za='Zain:BAABLgAECn9GAAQnAAkJNx3QBQCGAgAnAAkJNx3QBQCGAgAQAAYJGA5fWQBIAQADAAIJKA3GPQBSAAAAAA==.Zandibar:BAABLgAECn8dAAIQAAYJyRvIKACSAQAQAAYJyRvIKACSAQAAAA==.Zaptoasted:BAAALgAECgUJBgAAAA==.Zaroff:BAAALgAECgYJCgAAAA==.',
Ze='Zedadiah:BAAALgADCgEJAQAAAA==.Zelah:BAAALgAECgQJBAAAAA==.Zellezugtail:BAAALgADCgkJFgABLgAECgcJFwAYADsGAA==.Zenessa:BAAALgADCgYJBgAAAA==.',
Zi='Zinder:BAABLgAECn8lAAIFAAkJsQ5hSwDdAQAFAAkJsQ5hSwDdAQAAAA==.',
Zu='Zuggie:BAABLgAECn8XAAIYAAcJOwZPpADhAAAYAAcJOwZPpADhAAAAAA==.Zugtail:BAAALgAECgQJBAABLgAECgcJFwAYADsGAA==.Zurtrinik:BAACLgAFFH8WAAIDAAYJHyJfAgCSAQADAAYJHyJfAgCSAQAuAAQKfyUAAgMACAmZJDwCAE0DAAMACAmZJDwCAE0DAAAA.',
Zy='Zylith:BAAALgAECgYJBgABLgAECgkJLQAeAAkWAA==.',
Zz='Zzonked:BAABLgAECn8pAAMEAAkJCwhRdwBPAQAEAAkJzwZRdwBPAQAiAAIJ/gtGPwBSAAAAAA==.',
['Zê']='Zêp:BAAALgAECgEJAgAAAA==.',
['Zø']='Zøømies:BAABLgAECn8nAAMZAAgJQxiGPAC0AQAZAAgJ4BeGPAC0AQAhAAYJFQ93EgD5AAAAAA==.',
['Är']='Äréa:BAAALgADCgkJCQAAAA==.',
['Äs']='Äshnärd:BAACLgAFFH8GAAIdAAIJLSW3NQDVAAAdAAIJLSW3NQDVAAAuAAQKfzIAAh0ACQlLJIkEAEgDAB0ACQlLJIkEAEgDAAAA.',
['Ða']='Ðar:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðoogle:BAABLgAECn8XAAIHAAcJ5Rm8JwCCAQAHAAcJ5Rm8JwCCAQAAAA==.',
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
