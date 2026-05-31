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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Protection','DeathKnight-Unholy','Mage-Frost','Unknown-Unknown','Shaman-Elemental','Priest-Holy','Druid-Restoration','Monk-Mistweaver','Mage-Arcane','Druid-Balance','Druid-Guardian','Monk-Brewmaster','Druid-Feral','Monk-Windwalker','Warrior-Fury','Evoker-Preservation','Evoker-Augmentation','Paladin-Holy','Rogue-Subtlety','Priest-Shadow','DemonHunter-Havoc','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','DemonHunter-Devourer','Rogue-Assassination','Rogue-Outlaw','Shaman-Restoration','Shaman-Enhancement','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Vengeance','DeathKnight-Blood','Warlock-Destruction','Evoker-Devastation','DeathKnight-Frost','Priest-Discipline','Warrior-Arms','Mage-Fire',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=46,date='2026-05-30',data={Ad='Adrador:BAABLgAECn8sAAMBAAkJeSSUAQAiAwABAAkJeSSUAQAiAwACAAIJZxTtEwFvAAAAAA==.Adrenaline:BAACLgAFFH8XAAIDAAUJQSGgCAB9AQADAAUJQSGgCAB9AQAuAAQKfzkAAgMACQm8JD0CABoDAAMACQm8JD0CABoDAAAA.',
Ae='Aelik:BAACLgAFFH8HAAIEAAMJag8YiwDSAAAEAAMJag8YiwDSAAAuAAQKfygAAgQACAmOHMM8APsBAAQACAmOHMM8APsBAAAA.Aeolian:BAAALgADCgYJCQAAAA==.',
Ah='Ahkimbo:BAAALgADCgUJBQAAAA==.',
Ai='Airolanah:BAAALgAECgUJBQAAAA==.',
Al='Alayssa:BAABLgAECn8sAAIFAAkJXSBTGACyAgAFAAkJXSBTGACyAgAAAA==.Alda:BAAALgADCgkJEQAAAA==.Allarius:BAAALgAECgEJAQAAAA==.Allioops:BAAALgADCgUJBQABLgAECgMJBAAGAAAAAA==.Alnima:BAABLgAECn8ZAAIHAAgJzgi5OQBoAQAHAAgJzgi5OQBoAQAAAA==.',
Am='Amilee:BAAALgAECgUJDQAAAA==.Amishhunter:BAAALgADCgEJAQAAAA==.Amoondai:BAACLgAFFH8MAAIIAAMJByGCEgARAQAIAAMJByGCEgARAQAuAAQKfy0AAggACQnFISMDAFQDAAgACQnFISMDAFQDAAAA.Amoondrin:BAABLgAECn8zAAIJAAkJLwlnSABaAQAJAAkJLwlnSABaAQAAAA==.Amplifier:BAAALgADCgUJBQAAAA==.',
An='Analiya:BAAALgADCgIJAgAAAA==.Antichurch:BAAALgADCgEJAQAAAA==.Antisnow:BAAALgAECgIJBQABLgAECgcJCgAGAAAAAA==.Antregon:BAAALgADCgQJBwAAAA==.',
Ar='Araviin:BAAALgAFFAIJBAAAAA==.Arazen:BAAALgAECgIJAwAAAA==.Arcillias:BAAALgADCgYJCAABLgAECgYJBgAGAAAAAA==.Arkride:BAAALgAECgEJAQAAAA==.Arlean:BAAALgAECgIJAgAAAA==.Arnadaz:BAAALgADCgEJAQABLgAFFAMJBwAKAMkWAA==.Arrogance:BAAALgADCgcJBwABLgAECggJCQAGAAAAAA==.Arthia:BAAALgAECgQJEAAAAA==.Arvidpally:BAAALgADCgkJFQAAAA==.',
As='Ashmehameha:BAAALgADCgQJAgABLgAFFAMJBQAEAK4MAA==.Asinn:BAAALgAECgEJAQAAAA==.Asoosimov:BAAALgADCgEJAQAAAA==.',
At='Atredes:BAAALgAECgYJCAAAAA==.Attima:BAABLgAECn9BAAILAAkJWBE6AwDjAQALAAkJWBE6AwDjAQAAAA==.',
Au='Aurøra:BAAALgADCgMJAwAAAA==.Auspex:BAABLgAECn8rAAMMAAkJxwkyMABCAQAMAAkJ6QcyMABCAQANAAkJMAiZJwDzAAAAAA==.',
Av='Avaryn:BAACLgAFFH8XAAIJAAUJTBHeGwBaAQAJAAUJTBHeGwBaAQAuAAQKfzgAAgkACQmZISwIACcDAAkACQmZISwIACcDAAAA.',
Az='Azron:BAAALgAECgYJBgABLgAECggJDQAGAAAAAA==.',
Ba='Babavoss:BAAALgAECgkJAQAAAA==.Badarack:BAAALgAECgcJEwABLgAECgkJQAAOABAfAA==.Badaracka:BAABLgAECn8VAAMNAAkJXiOWAQAsAwANAAkJXiOWAQAsAwAPAAQJ0hDPKACkAAABLgAECgkJQAAOABAfAA==.Badarackie:BAABLgAECn9AAAMOAAkJEB+dCQDvAgAOAAgJ0iGdCQDvAgAQAAkJDhVjFgDsAQAAAA==.Badash:BAABLgAECn8rAAMDAAgJBhtsDgDrAQADAAgJBhtsDgDrAQARAAEJMQSurQAvAAABLgAFFAMJBQAEAK4MAA==.Bahamuth:BAABLgAECn9DAAICAAkJIB1GHQB+AgACAAkJIB1GHQB+AgAAAA==.Bakshi:BAAALgAECgEJBAAAAA==.Banký:BAAALgAECgEJAQAAAA==.Barbattos:BAACLgAFFH8SAAISAAQJohe7FAApAQASAAQJohe7FAApAQAuAAQKfzYAAxIACQkOJGkCADoDABIACQkOJGkCADoDABMAAQnkJORyAFkAAAAA.Barnabas:BAAALgADCgYJBgABLgAECgYJBgAGAAAAAA==.Barragon:BAABLgAECn8VAAIUAAcJ5g+tMgB0AQAUAAcJ5g+tMgB0AQAAAA==.',
Be='Beans:BAAALgAECgQJBAAAAA==.Bearymanalow:BAAALgAECgMJBAAAAA==.Belfore:BAAALgADCgcJBwABLgAECgkJHgAVAKkTAA==.Bethollbrew:BAAALgAECgYJDwAAAA==.Bexley:BAABLgAECn8tAAIBAAkJChqlBwBJAgABAAkJChqlBwBJAgAAAA==.',
Bi='Biggerbunny:BAABLgAECn8vAAIWAAgJhBWNHgCyAQAWAAgJhBWNHgCyAQAAAA==.Binkter:BAAALgAECgIJBQABLgAECgIJAgAGAAAAAA==.',
Bl='Blackjax:BAAALgADCgEJAQAAAA==.Blacklok:BAAALgAECgUJEQABLgAECgkJNAAXAEElAA==.Blanne:BAAALgADCgYJBgAAAA==.Blargle:BAABLgAECn8oAAIYAAgJ0A35WQB+AQAYAAgJ0A35WQB+AQAAAA==.Blessedcross:BAAALgADCggJCAAAAA==.Bleubahlz:BAAALgADCgcJBwABLgAECgMJAwAGAAAAAA==.Bloodrake:BAABLgAECn87AAIYAAkJHB6mDQDRAgAYAAkJHB6mDQDRAgAAAA==.Bloodreyne:BAAALgADCgEJAgAAAA==.Bloodseekr:BAAALgADCgQJBQAAAA==.Blueray:BAAALgAECgYJCAAAAA==.',
Bo='Boahan:BAAALgAECgMJBQABLgAECgUJCAAGAAAAAA==.Boggart:BAAALgAECgEJAQABLgAECgUJCAAGAAAAAA==.Bohein:BAAALgADCgEJAQAAAA==.Bolus:BAAALgAECgMJBQAAAA==.Botany:BAAALgAECgcJBwAAAA==.Bownafiedba:BAAALgADCgUJBQAAAA==.',
Br='Braneour:BAABLgAECn8yAAMUAAkJwBp1CgDQAgAUAAkJwBp1CgDQAgACAAMJmgsGNQFaAAAAAA==.Brassballz:BAAALgAECgkJCQAAAA==.Browel:BAABLgAECn8aAAMZAAcJWBj4CAC3AQAZAAYJ3Rj4CAC3AQAaAAYJYQ4SkwALAQAAAA==.Bruen:BAAALgAECgYJBwAAAA==.Bryci:BAAALgAECgcJDQAAAA==.',
Bu='Bubbloseven:BAAALgAECgYJEAAAAA==.Budank:BAAALgADCgMJAwAAAA==.Bumm:BAABLgAECn8YAAICAAYJzwh50ADTAAACAAYJzwh50ADTAAAAAA==.Bustybubbles:BAAALgADCgYJBgAAAA==.',
Bz='Bzspy:BAABLgAFFH8LAAIRAAMJzwwoMADNAAARAAMJzwwoMADNAAAAAA==.',
Ca='Caalin:BAAALgAECgEJAgAAAA==.Cabooselul:BAAALgAECgQJCwAAAA==.Calibre:BAABLgAECn8eAAIbAAcJohUDXwBTAQAbAAcJohUDXwBTAQAAAA==.Calyptus:BAABLgAECn8fAAIaAAYJhAoroQDyAAAaAAYJhAoroQDyAAAAAA==.Caprious:BAACLgAFFH8SAAIEAAUJwxlyPwBSAQAEAAUJwxlyPwBSAQAuAAQKfzYAAgQACQnjJBUIACQDAAQACQnjJBUIACQDAAAA.Capylaura:BAABLgAECn8ZAAIYAAYJhwjpkAADAQAYAAYJhwjpkAADAQAAAA==.Caratine:BAABLgAECn8XAAIbAAcJDAoZjwDjAAAbAAcJDAoZjwDjAAAAAA==.Cassandrar:BAABLgAECn8yAAQcAAkJGSQIAQA5AwAcAAgJMiQIAQA5AwAVAAYJtiCpGwChAQAdAAEJphQgHwA5AAAAAA==.Cassandraw:BAAALgAECgYJBgABLgAECgkJMgAcABkkAA==.Cat:BAAALgADCgUJBQAAAA==.Cattlelac:BAAALgADCgUJCAAAAA==.Caymus:BAABLgAECn8cAAIJAAcJgAmqXgAIAQAJAAcJgAmqXgAIAQAAAA==.',
Ce='Celìa:BAABLgAECn8nAAIYAAkJdQjfWQB+AQAYAAkJdQjfWQB+AQAAAA==.Cess:BAAALgAECgEJAgAAAA==.',
Ch='Chaoticone:BAAALgADCgYJBgAAAA==.Chema:BAABLgAFFH8HAAIKAAMJyRaqKwDGAAAKAAMJyRaqKwDGAAAAAA==.Chestylarue:BAAALgAECgEJAQABLgAECggJEgAGAAAAAA==.Chfgaribaldi:BAAALgADCggJDgAAAA==.Chills:BAAALgAECgcJEQAAAA==.Chillymage:BAAALgADCgYJBgAAAA==.Chosen:BAABLgAECn8YAAICAAYJRBdtYgC+AQACAAYJRBdtYgC+AQABLgAFFAUJFwAEAPsgAA==.Chpchop:BAAALgADCgIJAgAAAA==.Christy:BAAALgADCgkJEQAAAA==.Chugg:BAABLgAECn8fAAIeAAkJwggnUQBPAQAeAAkJwggnUQBPAQAAAA==.',
Ci='Ciaphus:BAABLgAECn8nAAICAAkJ0hSFPgDzAQACAAkJ0hSFPgDzAQAAAA==.Cinnamonster:BAAALgAECgcJDgAAAA==.',
Co='Coffeedemon:BAAALgADCgEJAQAAAA==.Coldslappins:BAAALgAECggJCgAAAA==.Contagion:BAAALgAECgYJBQAAAA==.Convoke:BAABLgAECn8eAAIMAAcJDSArFgBeAgAMAAcJDSArFgBeAgAAAA==.',
Cr='Crazycrocey:BAAALgAECgEJAQAAAA==.',
Cu='Cubcake:BAAALgADCggJCAAAAA==.Curtastrophe:BAABLgAECn89AAIFAAkJHx2UIgB9AgAFAAkJHx2UIgB9AgAAAA==.Curticus:BAAALgADCgQJBAAAAA==.Curtissax:BAAALgAECgIJAgAAAA==.Curtnought:BAAALgADCgIJAgAAAA==.',
['Cé']='Cérnùnnøs:BAAALgAECgEJAQAAAA==.',
Da='Daelanos:BAABLgAECn8cAAIRAAgJPBhCKwCUAQARAAgJPBhCKwCUAQAAAA==.Dalinar:BAAALgAECgQJCgAAAA==.Daranger:BAAALgADCgEJAQAAAA==.Darska:BAAALgADCgYJBgABLgAECggJCwAGAAAAAA==.',
De='Deadtauren:BAAALgADCgYJDwAAAA==.Deathdemon:BAAALgAECgYJDgAAAA==.Deathfue:BAAALgAECgEJAwABLgAECgcJCgAGAAAAAA==.Deathisreal:BAAALgADCgMJAwABLgAECgUJDAAGAAAAAA==.Decimated:BAACLgAFFH8XAAIEAAUJ+yDILQB9AQAEAAUJ+yDILQB9AQAuAAQKfyAAAgQACQkwI6MUALkCAAQACQkwI6MUALkCAAAA.Demon:BAAALgAECgkJDQAAAA==.Demonilla:BAAALgAECgcJDgAAAA==.Dempkiston:BAAALgAECgUJBQAAAA==.Denable:BAABLgAECn8cAAIJAAYJ7A/7VAApAQAJAAYJ7A/7VAApAQAAAA==.Denogan:BAAALgAECggJDQAAAA==.Deservis:BAAALgAECgUJDgABLgAECgcJHgAbAKIVAA==.Destro:BAABLgAECn8nAAIaAAkJ7w+HQADOAQAaAAkJ7w+HQADOAQABLgAECgkJMwAfAOIXAA==.Dethadin:BAAALgADCgcJBwAAAA==.',
Di='Dilaudyd:BAAALgAECgMJBAAAAA==.Dirteemike:BAAALgADCgMJAwAAAA==.Disbeleaf:BAABLgAECn8VAAMJAAYJARliNgCsAQAJAAYJARliNgCsAQAMAAUJUSBVKQBsAQAAAA==.Discoflurry:BAAALgAECgcJDgABLgAFFAQJCgADAN8hAA==.Dizzyfist:BAAALgAECgYJCQABLgAECggJDQAGAAAAAA==.',
Do='Dogaz:BAAALgADCgkJDwAAAA==.Dogsoldier:BAAALgADCgIJAgAAAA==.Donori:BAAALgAECgQJDQAAAA==.Dorcath:BAAALgAFFAIJBAABLgAECggJHAARADwYAA==.',
Dr='Dragan:BAAALgAECgQJDwAAAA==.Dragapult:BAAALgAECggJAwAAAA==.Dragonias:BAABLgAECn8YAAIgAAcJ5hbJDAB/AQAgAAcJ5hbJDAB/AQAAAA==.Draino:BAAALgADCgUJBQAAAA==.Drakthorn:BAAALgAECgcJCgAAAA==.Dreselwings:BAAALgAECggJCAABLgAFFAgJHgAYAJsfAA==.Drinny:BAABLgAECn8yAAIIAAkJtwgcLQBLAQAIAAkJtwgcLQBLAQAAAA==.Drqueenisin:BAAALgAECgEJAQAAAA==.Druido:BAAALgAECgEJAQAAAA==.',
Du='Duerek:BAAALgAECgUJBgAAAA==.',
['Dè']='Dèaths:BAAALgAECgYJEAAAAA==.',
['Dí']='Dínglebery:BAAALgAECgEJAgAAAA==.',
Ea='Earthangel:BAABLgAECn8cAAIIAAYJQBcoKgBhAQAIAAYJQBcoKgBhAQAAAA==.',
Ed='Edlarel:BAAALgADCgQJBAABLgAECggJCQAGAAAAAA==.',
Ei='Eine:BAABLgAECn9DAAIYAAkJsxXrKQAgAgAYAAkJsxXrKQAgAgAAAA==.Eitherwind:BAABLgAECn8XAAQhAAYJ2h8bHQClAQAhAAYJ2h8bHQClAQAYAAIJchT/qwBsAAAgAAIJNxP7NQA0AAABLgAECggJDQAGAAAAAA==.Eivore:BAAALgAECgcJBwAAAA==.',
Ek='Ekoh:BAAALgAECgEJAgAAAA==.',
El='Eldergreen:BAABLgAECn8iAAIJAAgJzQlYYQD/AAAJAAgJzQlYYQD/AAAAAA==.Eldest:BAAALgADCgUJBQAAAA==.Elfwine:BAABLgAECn8cAAIWAAYJKA1tPwDuAAAWAAYJKA1tPwDuAAAAAA==.Elindria:BAABLgAECn80AAQXAAkJQSWZAgAjAwAXAAkJHiWZAgAjAwAiAAkJhiGyAQD0AgAbAAUJMxu6ewA0AQAAAA==.Eliora:BAAALgADCgkJCQAAAA==.Elminstir:BAAALgAECggJEAAAAA==.Elyissia:BAAALgAECgYJDAAAAA==.Elynisa:BAAALgAECgEJAQAAAA==.Elysian:BAABLgAECn84AAQKAAkJcxwWCgDYAgAKAAkJcxwWCgDYAgAQAAgJaB/7DQBSAgAOAAIJyh8MUgCrAAAAAA==.',
Em='Emogo:BAAALgADCgUJCQAAAA==.',
En='Enforcer:BAAALgADCgQJBgAAAA==.Enlightened:BAAALgAECgQJCwAAAA==.Enseral:BAAALgAECgcJEgAAAA==.',
Eo='Eotech:BAAALgAECgQJBAAAAA==.',
Er='Erendora:BAABLgAECn8gAAIJAAgJqQ56QgB0AQAJAAgJqQ56QgB0AQAAAA==.Erets:BAAALgAECgEJAQAAAA==.Eridar:BAAALgAECgYJBgAAAA==.Erizhal:BAAALgAECgUJEAAAAA==.Erodora:BAAALgADCgEJAQAAAA==.',
Es='Esabel:BAAALgAECgkJCQABLgAECgkJLAAFAF0gAA==.',
Ev='Eva:BAAALgAECgEJAgAAAA==.Eviae:BAABLgAECn8dAAIjAAYJ3gmZMgC4AAAjAAYJ3gmZMgC4AAAAAA==.Evillure:BAABLgAECn8lAAMEAAkJ8hOxOgACAgAEAAkJ8hOxOgACAgAjAAUJkgwiNgClAAAAAA==.',
Fa='Falan:BAABLgAECn8jAAIeAAkJhBEuKwD0AQAeAAkJhBEuKwD0AQAAAA==.Faputa:BAAALgAECgMJAwAAAA==.Fatherjoe:BAAALgADCgYJBgAAAA==.Fayze:BAEBLgAECn8XAAMcAAcJfiNxBAA3AgAcAAcJSCNxBAA3AgAVAAIJBiGOOgDCAAABLgAFFAIJBAAGAAAAAA==.',
Fe='Felbreaker:BAAALgAECgYJDAAAAA==.Fentril:BAAALgADCgIJAgABLgAECggJDQAGAAAAAA==.Feår:BAABLgAECn8eAAMaAAkJJQyYcQBMAQAaAAgJQgqYcQBMAQAkAAMJ3Q8RSwCMAAAAAA==.',
Fi='Fillianora:BAAALgAECgIJAgAAAA==.Finley:BAAALgAECgQJBQAAAA==.Fircane:BAAALgADCgQJBAAAAA==.Firiel:BAAALgADCgEJAQAAAA==.Fizzle:BAAALgADCggJCAABLgAECgkJIAAJAHAWAA==.',
Fl='Flane:BAAALgAFFAEJAwABLgAFFAcJGAADADEfAA==.Flem:BAAALgAECgMJBAAAAA==.Flexdruid:BAAALgAECgUJDgAAAA==.',
Fo='Foog:BAAALgAECgYJEwAAAA==.',
Fr='Fragil:BAABLgAECn8xAAIVAAgJ/xy/DABDAgAVAAgJ/xy/DABDAgAAAA==.Frostmane:BAACLgAFFH8QAAMEAAUJsxxrMQB0AQAEAAQJsxxrMQB0AQAjAAEJAADbTAAAAAAuAAQKfzkAAwQACQlWJTQEAFQDAAQACQlWJTQEAFQDACMABwn+HMANADECAAAA.Frostynug:BAAALgADCgYJBgAAAA==.',
Fu='Fudge:BAAALgADCgYJBgAAAA==.Furbyn:BAAALgADCgIJAgAAAA==.',
Ga='Galena:BAABLgAECn8XAAIJAAcJtQoAXAARAQAJAAcJtQoAXAARAQAAAA==.Gallamier:BAAALgADCgEJAQAAAA==.Gamerinator:BAAALgADCgcJCwAAAA==.',
Ge='Geshtal:BAAALgAECgQJCwAAAA==.Gets:BAAALgADCgIJAgAAAA==.',
Gi='Girion:BAABLgAECn8dAAIBAAYJkA1NJgDIAAABAAYJkA1NJgDIAAAAAA==.Girliepop:BAAALgAECgEJAQAAAA==.',
Gl='Glaiven:BAECLgAFFH8TAAMbAAUJrxSfMwAuAQAbAAQJvxOfMwAuAQAiAAMJuA+ICwBkAAAuAAQKfy8AAyIACQmVIdADAHsCABsACQkrH6EdAKACACIACQmXHNADAHsCAAAA.Glorfinndel:BAAALgADCgQJBAAAAA==.Glyr:BAAALgADCgUJBQAAAA==.',
Go='Gorgrin:BAAALgAECgcJEQAAAA==.Goude:BAAALgADCgIJAgAAAA==.',
Gr='Greenback:BAAALgADCgYJCwAAAA==.Greentotes:BAEBLgAECn8vAAMTAAkJ7x9cBwDMAgATAAkJ7x9cBwDMAgAlAAQJdgY1LgCoAAABLgAECgIJBAAGAAAAAA==.',
Gu='Gunter:BAAALgAECgMJAwABLgAFFAUJFwAEAPsgAA==.Gura:BAAALgADCgEJAQAAAA==.Gurnee:BAAALgADCgcJDQABLgAECggJEQAGAAAAAA==.Guthix:BAAALgAECgUJBgAAAA==.',
['Gê']='Gêm:BAABLgAECn84AAISAAkJ8xLdCwAHAgASAAkJ8xLdCwAHAgAAAA==.',
['Gï']='Gïmlï:BAAALgADCgMJAwAAAA==.',
Ha='Haildydra:BAAALgAECgEJAQABLgAECgcJCgAGAAAAAA==.Halibell:BAAALgAECgYJDQAAAA==.Halnan:BAAALgADCgEJAQABLgAECgcJHgAbAKIVAA==.Harkanum:BAABLgAECn9GAAQlAAkJ9hmgBQDvAQAlAAgJLhigBQDvAQASAAkJGg0XEQClAQATAAQJrxPwPgDuAAAAAA==.Hartman:BAAALgAECgMJAgAAAA==.Harvester:BAAALgAECgEJAQAAAA==.Hatebreéd:BAAALgAECggJCQAAAA==.',
He='Healinturds:BAAALgAECgYJDAABLgAECgcJHgAbAKIVAA==.Hector:BAABLgAECn8eAAICAAkJfSIWIABwAgACAAkJfSIWIABwAgAAAA==.Heelys:BAAALgAECgYJCgAAAA==.Helloagain:BAACLgAFFH8RAAIFAAQJxxh6QABMAQAFAAQJxxh6QABMAQAuAAQKfyMAAgUABglqIyFdACMCAAUABglqIyFdACMCAAAA.Herryknutsak:BAAALgAECgEJAQAAAA==.Hestonater:BAAALgAECgEJAgAAAA==.Hestra:BAAALgADCgIJAgAAAA==.',
Hi='Hidethetotem:BAABLgAECn8hAAMeAAkJIRuRDwC+AgAeAAkJIRuRDwC+AgAHAAEJHgrXngAnAAAAAA==.Hightops:BAAALgAECggJDgAAAA==.Hikari:BAACLgAFFH8NAAICAAUJLA4XQAAUAQACAAUJLA4XQAAUAQAuAAQKfx4AAgIACQlrHOAsAHACAAIACQlrHOAsAHACAAAA.Hiown:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.',
Ho='Holeliness:BAAALgAECggJEwAAAA==.Holybackshot:BAAALgAECgQJBgAAAA==.Holydisco:BAAALgADCgcJCQAAAA==.Holyhide:BAAALgAECgEJAQAAAA==.Holyspike:BAABLgAECn8XAAIeAAcJ+g8TTgBbAQAeAAcJ+g8TTgBbAQAAAA==.Holytard:BAAALgADCgYJBgAAAA==.Holytaren:BAABLgAECn8UAAIUAAgJ3RtgEQB1AgAUAAgJ3RtgEQB1AgAAAA==.Holytickles:BAABLgAECn8sAAMWAAkJ4hsCEwBeAgAWAAgJ+hsCEwBeAgAIAAkJsBe3DwBWAgABLgAFFAYJFQAaAJoTAA==.Holytotem:BAAALgAECgEJAQAAAA==.Homerr:BAABLgAECn8bAAIYAAcJZBOOXQB0AQAYAAcJZBOOXQB0AQAAAA==.Honiahaka:BAABLgAECn9DAAIYAAkJBxCpOwDZAQAYAAkJBxCpOwDZAQAAAA==.Hottcakes:BAAALgADCgIJAgABLgAFFAYJFQAaAJoTAA==.',
Hu='Huckster:BAABLgAECn8ZAAIEAAgJhQ6YcABvAQAEAAgJhQ6YcABvAQAAAA==.Humanoidholy:BAABLgAECn8fAAMCAAgJXSQ6CQBIAwACAAgJXSQ6CQBIAwABAAEJbgXWTQAYAAABLgAFFAQJDgAXAPYhAA==.Humanoidhunt:BAAALgAFFAEJAQABLgAFFAQJDgAXAPYhAA==.Humanoidvoid:BAACLgAFFH8OAAMXAAQJ9iE0BQCIAQAXAAQJYCE0BQCIAQAbAAMJ9h1vRQD+AAAuAAQKf1MABBsACQkFI7sFAB4DABsACQmdIrsFAB4DABcACAnlH7wIAIYCACIACAkoCDgTAAABAAAA.',
Hy='Hydrah:BAAALgAECgEJAQABLgAECgcJCgAGAAAAAA==.',
Ic='Icedtea:BAAALgAECgcJBAAAAA==.Icicle:BAAALgADCgIJAgAAAA==.',
Id='Idunasil:BAAALgAECgEJAQAAAA==.',
Ih='Ihatemustard:BAABLgAECn8jAAIiAAkJ6RUPBwD+AQAiAAkJ6RUPBwD+AQAAAA==.',
Il='Illethan:BAAALgADCgYJBgAAAA==.Iloveketchup:BAAALgAECgcJDAAAAA==.',
In='Inoru:BAAALgAECgcJDwAAAA==.Insanity:BAAALgAECgUJCgAAAA==.',
Ir='Irmaline:BAABLgAECn8XAAIIAAcJVBQbJgB+AQAIAAcJVBQbJgB+AQAAAA==.',
It='Ithurtshuh:BAAALgAECgUJDAAAAA==.Itsmaam:BAAALgAECgMJBAAAAA==.Itzcannibal:BAACLgAFFH8GAAIYAAIJ6goxcQCMAAAYAAIJ6goxcQCMAAAuAAQKfy8AAxgACQk4Gy8kADsCABgACQk4Gy8kADsCACAAAgnVCux5AFoAAAAA.',
Ja='Jabbawockie:BAAALgAECgkJAgAAAA==.Jaekoby:BAAALgAECgIJAwABLgAECggJIgACAM0aAA==.Jakoby:BAAALgAECgUJBgABLgAECggJIgACAM0aAA==.Jandrisel:BAAALgAECgYJCwAAAA==.Jarhead:BAAALgAECgEJAgAAAA==.Jayzich:BAAALgADCgQJBwAAAA==.',
Je='Jeffee:BAAALgAECgIJCQAAAA==.Jequalsjosh:BAABLgAECn88AAIcAAkJ9iEDAgC5AgAcAAkJ9iEDAgC5AgAAAA==.Jerk:BAAALgAECgQJBAAAAA==.Jerp:BAAALgAECgIJAgAAAA==.Jesper:BAABLgAECn9GAAIeAAkJ5B97CAAVAwAeAAkJ5B97CAAVAwAAAA==.Jetz:BAAALgAECgEJAQAAAA==.Jezelle:BAACLgAFFH8RAAIaAAUJDRDvTAAaAQAaAAUJDRDvTAAaAQAuAAQKfyIAAhoACQn0Hg42ADQCABoACQn0Hg42ADQCAAAA.',
Ji='Jilara:BAABLgAECn8tAAICAAgJfwZWrAAIAQACAAgJfwZWrAAIAQAAAA==.Jimmyjim:BAABLgAECn8WAAIFAAcJDQzYngAiAQAFAAcJDQzYngAiAQAAAA==.Jingying:BAAALgADCgMJAwAAAA==.',
Jo='Johnny:BAAALgADCgQJBAAAAA==.',
Jp='Jpepps:BAABLgAECn8vAAMaAAkJDRMfOADtAQAaAAkJDRMfOADtAQAkAAMJxwjoRQCeAAAAAA==.',
Jr='Jrose:BAAALgAECgQJBAAAAA==.',
['Jæ']='Jækobÿ:BAAALgAECgIJAgABLgAECggJIgACAM0aAA==.',
Ka='Kahlanrahl:BAAALgADCgMJAwAAAA==.Kaiatra:BAABLgAECn8WAAImAAcJbSIZBwD/AQAmAAcJbSIZBwD/AQAAAA==.Kaliguala:BAAALgAECgQJBQAAAA==.Katare:BAAALgAECgMJAwAAAA==.Kaulder:BAAALgADCgUJBQAAAA==.Kaìju:BAABLgAECn8iAAICAAgJqiHIGwCGAgACAAgJqiHIGwCGAgAAAA==.Kaîju:BAAALgAECgIJAgAAAA==.',
Ke='Kellytgt:BAABLgAECn8zAAIbAAkJpxo5GABwAgAbAAkJpxo5GABwAgAAAA==.Kev:BAAALgADCgUJBQAAAA==.',
Ki='Kilaura:BAABLgAECn8ZAAInAAgJWRBeHwCvAQAnAAgJWRBeHwCvAQAAAA==.Kilmandaros:BAAALgADCgYJCwAAAA==.Kippi:BAAALgAECgQJCwAAAA==.',
Ko='Korhina:BAABLgAECn9GAAIDAAkJeyawAABlAwADAAkJeyawAABlAwAAAA==.Korobas:BAAALgAECgMJAwAAAA==.Koru:BAAALgAECgQJBQABLgAECgQJBgAGAAAAAA==.Kosumi:BAAALgADCggJDQAAAA==.',
Kr='Kronic:BAAALgAECgUJCAAAAA==.',
Ku='Kuroyukihime:BAABLgAECn84AAIFAAkJ/h5qFwC3AgAFAAkJ/h5qFwC3AgAAAA==.Kuwaii:BAABLgAECn8dAAITAAcJuxirJACdAQATAAcJuxirJACdAQABLgAECggJHgAMAA0gAA==.',
Ky='Kyarina:BAAALgAECgEJAQABLgAECgkJGQAIAEMHAA==.Kylis:BAAALgAECgQJBAAAAA==.Kyna:BAABLgAECn8ZAAIIAAkJQwelNgAOAQAIAAkJQwelNgAOAQAAAA==.Kyross:BAAALgADCgIJAgAAAA==.',
['Ké']='Kéya:BAAALgAECgYJCgAAAA==.',
La='Lashela:BAABLgAECn8VAAIYAAgJxwqBYQBqAQAYAAgJxwqBYQBqAQAAAA==.Laughter:BAAALgAECgYJEgAAAA==.Laurana:BAAALgADCgIJAgAAAA==.Lazulie:BAAALgAECgYJEgAAAA==.',
Le='Leansipper:BAABLgAFFH8NAAIMAAMJ1ReWJADeAAAMAAMJ1ReWJADeAAAAAA==.Levoker:BAAALgAECgQJBAAAAA==.Lexapayne:BAAALgAECgYJDgABLgAFFAQJCAAYANISAA==.',
Li='Lighthammer:BAAALgADCgEJAQAAAA==.Lilandra:BAAALgAECgYJDAABLgAECggJCwAGAAAAAA==.Lillianaxe:BAAALgAECgcJEQAAAA==.Lilyvain:BAAALgAECgUJCAAAAA==.Lireal:BAABLgAECn8nAAIUAAkJBSRdAgB3AwAUAAkJBSRdAgB3AwAAAA==.Listerine:BAAALgAECggJCQAAAA==.Litercola:BAAALgAECgcJEwAAAA==.Livnod:BAAALgAECgMJCQAAAA==.',
Lo='Loonfabio:BAAALgAECgIJAgABLgAFFAQJEgACACUjAA==.Loosescrew:BAAALgADCgIJAgAAAA==.Lorine:BAABLgAECn87AAIBAAkJbBthCQAgAgABAAkJbBthCQAgAgAAAA==.Lowkie:BAAALgADCgIJAgAAAA==.',
Lu='Luckside:BAAALgAECgQJBAABLgAECgkJHgAaACUMAA==.Lunafae:BAAALgADCgYJCQABLgADCgkJFQAGAAAAAA==.Lunafeather:BAAALgADCgYJCgABLgADCgkJFQAGAAAAAA==.Lunara:BAAALgAECgMJBgAAAA==.Lunasnow:BAAALgAECgQJBAAAAA==.Lunchtime:BAAALgAECgEJAQAAAA==.Luxe:BAAALgADCgEJAQAAAA==.',
Ly='Lyntot:BAAALgADCgEJAQAAAA==.',
['Ló']='Lókki:BAAALgAECgUJCAAAAA==.',
Ma='Madwe:BAABLgAECn8hAAMbAAgJrgfliADwAAAbAAgJcwbliADwAAAXAAMJcAbSRwBtAAAAAA==.Mageab:BAABLgAFFH8HAAIFAAYJDB3CHQDNAQAFAAYJDB3CHQDNAQAAAA==.Magis:BAAALgADCgkJHgAAAA==.Malzzahar:BAAALgAECgQJBAAAAA==.Manimetal:BAAALgAECgUJEAAAAA==.Materia:BAAALgAECgcJBwAAAA==.',
Me='Meeralax:BAABLgAECn8WAAIYAAYJJgaspwDTAAAYAAYJJgaspwDTAAAAAA==.Melizza:BAAALgADCgMJAwAAAA==.Merckel:BAACLgAFFH8GAAIbAAIJjxkUZQCaAAAbAAIJjxkUZQCaAAAuAAQKfywAAhsACAk5INkZAGUCABsACAk5INkZAGUCAAAA.Merckz:BAAALgAECgUJBQABLgAFFAIJBgAbAI8ZAA==.Merks:BAAALgAECgEJAQAAAA==.Metalmonkey:BAAALgAECgQJBAAAAA==.',
Mi='Michello:BAABLgAECn8VAAIYAAcJRh4MPQDVAQAYAAcJRh4MPQDVAQAAAA==.Mickcowmoose:BAAALgADCgIJAgAAAA==.Millia:BAABLgAECn8mAAIFAAgJER4GKQBgAgAFAAgJER4GKQBgAgABLgAECgkJHgACAH0iAA==.Mint:BAABLgAECn8jAAIUAAcJiyOXDQCjAgAUAAcJiyOXDQCjAgAAAA==.Mintberrytea:BAAALgAECgUJBwABLgAECgcJIwAUAIsjAA==.Mintchaitea:BAAALgAFFAEJAQABLgAECgcJIwAUAIsjAA==.Misstress:BAABLgAECn81AAMMAAkJGg2/JQCFAQAMAAkJGg2/JQCFAQANAAEJ/giGZwAlAAAAAA==.Mizen:BAAALgADCgUJCAAAAA==.',
Mo='Mogdor:BAAALgADCgUJBQAAAA==.Monkussy:BAAALgAECgIJAgAAAA==.Moonhunt:BAAALgAECgMJCQAAAA==.Moonly:BAABLgAECn8mAAIhAAkJYQz7GADJAQAhAAkJYQz7GADJAQAAAA==.Morrag:BAABLgAECn8iAAMaAAcJ0QrRfwAvAQAaAAcJzwrRfwAvAQAZAAEJjAbmOAAuAAAAAA==.',
Mu='Murdumurdu:BAAALgAECgUJCAAAAA==.Murkblade:BAAALgADCgYJBgABLgAECgcJHgAbAKIVAA==.Musho:BAAALgADCgYJEgAAAA==.Mustakrakish:BAAALgAECgEJAQAAAA==.',
My='Myn:BAABLgAECn8VAAIJAAgJOBrmGwBTAgAJAAgJOBrmGwBTAgAAAA==.Myw:BAAALgAECgcJBwABLgAFFAgJKAAeALkWAA==.',
['Mæ']='Mædenless:BAAALgAECgYJCQAAAA==.',
['Mí']='Mísfìt:BAABLgAECn88AAMeAAkJQRmfHQBGAgAeAAkJQRmfHQBGAgAHAAgJEQzHNQBHAQAAAA==.',
Na='Nakaito:BAABLgAECn8XAAIaAAcJrgz0fwAvAQAaAAcJrgz0fwAvAQABLgAECgkJNgAcAA8bAA==.Narcoleptic:BAACLgAFFH8IAAISAAMJSA06HAC8AAASAAMJSA06HAC8AAAuAAQKfz0ABBIACQnqGIQGAIkCABIACQnqGIQGAIkCABMACAn1FDclAJoBACUABAmuBVQvAJ0AAAAA.',
Ne='Neocracy:BAAALgADCgYJCwABLgAECggJFAAUAN0bAA==.Nex:BAAALgADCgYJCAAAAA==.',
Ni='Niceshield:BAAALgAECgEJBAAAAA==.Nightmarexx:BAACLgAFFH8VAAIVAAUJZh7xEwBNAQAVAAUJZh7xEwBNAQAuAAQKf04AAhUACAmnIRMJAH4CABUACAmnIRMJAH4CAAAA.Nightsawdy:BAABLgAECn8mAAMYAAgJQRemUgCSAQAYAAcJThemUgCSAQAhAAYJqxLCKABJAQAAAA==.Nightsnake:BAAALgAECgMJAwAAAA==.Niightstorm:BAABLgAECn8bAAMYAAYJPRwmfAAtAQAYAAUJAB0mfAAtAQAhAAQJbBL+OgDPAAAAAA==.Nikwillig:BAAALgAECggJDQAAAA==.Nilveron:BAAALgADCgcJCQAAAA==.Nitefire:BAAALgADCgkJEQAAAA==.Nitélifé:BAAALgADCgMJAwAAAA==.',
Nj='Njörðr:BAAALgAECgYJDAAAAA==.',
No='Noxmortis:BAAALgAECgYJBgAAAA==.',
Nt='Ntadadarknes:BAAALgAECgIJAwABLgAECggJIgAJAM0JAA==.',
Oo='Ooblidoom:BAAALgADCgUJBQABLgAECgkJRAAlAFkTAA==.',
Op='Opalinnas:BAABLgAECn8gAAMJAAkJcBbkKgDtAQAJAAkJcBbkKgDtAQAMAAUJeQhLVACiAAAAAA==.',
Oz='Ozath:BAAALgAECgQJBgAAAA==.',
Pa='Passionfruit:BAAALgAECgUJCgAAAA==.',
Pe='Peachtea:BAAALgAECgQJEAAAAA==.',
Ph='Phatshaman:BAABLgAECn8UAAIHAAgJbQcxRwD7AAAHAAgJbQcxRwD7AAAAAA==.Phæryll:BAAALgADCgUJBgAAAA==.',
Pi='Pirodeath:BAAALgAECgcJCgAAAA==.',
Po='Poisonclaw:BAAALgAECgIJBAAAAA==.Poprotonix:BAABLgAECn8eAAICAAgJPxZNRQDeAQACAAgJPxZNRQDeAQAAAA==.Pozessedkaos:BAAALgAECgQJBAAAAA==.',
Pr='Praecantrix:BAAALgAECgEJBAAAAA==.Prath:BAAALgADCgEJAQAAAA==.Pray:BAABLgAECn9DAAInAAkJBCQKAgCLAwAnAAkJBCQKAgCLAwAAAA==.Priestyballz:BAAALgAECgYJBgAAAA==.Prodarkangel:BAABLgAECn8bAAMkAAkJIgldFADuAAAkAAkJIgldFADuAAAaAAMJaAPP/gBXAAAAAA==.',
Pu='Pubis:BAAALgAECgYJDgAAAA==.Puckllane:BAABLgAECn8aAAICAAkJ5RdiQQAhAgACAAkJ5RdiQQAhAgAAAA==.Punkbeer:BAAALgAECgEJAQAAAA==.Punkin:BAAALgAECgQJCgAAAA==.',
Py='Pyre:BAABLgAECn89AAInAAkJSQ+zHQC9AQAnAAkJSQ+zHQC9AQABLgADCgUJBQAGAAAAAA==.',
Qu='Quefstank:BAAALgADCgUJCAAAAA==.Quivver:BAAALgADCgkJDgAAAA==.',
Ra='Rabmaxx:BAABLgAECn8mAAIXAAYJuA+ULAD4AAAXAAYJuA+ULAD4AAAAAA==.Radren:BAAALgADCgEJAQAAAA==.Rajinazn:BAAALgAECgEJAQAAAA==.Rattchett:BAAALgAECgYJBgAAAA==.Ravenlight:BAABLgAFFH8FAAICAAQJWA5HPgAYAQACAAQJWA5HPgAYAQAAAA==.Ravenwynnd:BAABLgAECn8mAAIoAAkJuyKmAwDZAgAoAAkJuyKmAwDZAgAAAA==.Ravix:BAAALgADCgQJBAAAAA==.Raynelock:BAABLgAECn8wAAMkAAkJgRBjCQCVAQAkAAkJgRBjCQCVAQAaAAIJtQcZCQFKAAAAAA==.Raynman:BAABLgAECn9DAAIeAAkJdxVpIQAtAgAeAAkJdxVpIQAtAgAAAA==.Razgriz:BAAALgAECgEJAQAAAA==.Razix:BAABLgAECn8zAAQTAAkJfxTMHADWAQATAAkJfxTMHADWAQAlAAYJ6wmnFgCVAAASAAMJYwclPACJAAAAAA==.',
Re='Realist:BAAALgAECgMJBAAAAA==.Refrigtuitor:BAACLgAFFH8VAAMFAAUJGwviXAAYAQAFAAUJGwviXAAYAQApAAIJuALdAwBkAAAuAAQKfz8ABAUACQmEHxkcAJ0CAAUACQmEHxkcAJ0CAAsABQmDCGQOAN0AACkAAQk8EDkQADcAAAAA.Reija:BAAALgAECgEJAgAAAA==.Repentance:BAAALgADCgEJAQABLgAECgkJMwAfAOIXAA==.Revealed:BAAALgADCgEJAQAAAA==.Rezzarn:BAAALgAECgEJAQAAAA==.',
Rh='Rhun:BAAALgAECgYJCQAAAA==.Rhyzer:BAABLgAECn8dAAMRAAYJ7BcXNwBWAQARAAYJ7BcXNwBWAQAoAAEJJQ1bRQAuAAAAAA==.',
Ri='Rileyksufan:BAABLgAECn8VAAIYAAkJhg6+bgBMAQAYAAkJhg6+bgBMAQAAAA==.Rinas:BAACLgAFFH8FAAIXAAIJpxdSGQCTAAAXAAIJpxdSGQCTAAAuAAQKfzYAAxcACQm4ImQCACoDABcACQm4ImQCACoDABsAAgmfDUT5ADUAAAAA.Rivendell:BAAALgAECgQJBgAAAA==.Rivenlynn:BAAALgADCgEJAQAAAA==.',
Ru='Rubioxis:BAAALgADCgYJBgAAAA==.',
Ry='Rymarri:BAAALgADCgkJCQAAAA==.',
Sa='Sabazia:BAACLgAFFH8IAAIjAAIJ7Bv2IgCqAAAjAAIJ7Bv2IgCqAAAuAAQKfzsAAiMACQkXID4GAKwCACMACQkXID4GAKwCAAAA.Sacrificer:BAAALgAECgMJAwAAAA==.Sairalindë:BAABLgAECn8XAAMYAAgJbgNQkgAAAQAYAAgJbgNQkgAAAQAgAAMJpAA3hgA2AAAAAA==.Saleath:BAAALgAECgEJAwAAAA==.Salios:BAABLgAFFH8NAAIaAAQJNB6wFwAzAQAaAAQJNB6wFwAzAQAAAA==.Sallydisco:BAAALgAECgMJAwABLgAFFAQJCgADAN8hAA==.Sanctifier:BAAALgAECgQJDQAAAA==.Saraneth:BAAALgAECgEJAQABLgAECgkJJwAUAAUkAA==.',
Sc='Scandrel:BAAALgAECgQJBAABLgAFFAUJFwAEAPsgAA==.Scrept:BAAALgAECgUJEQAAAA==.Scynix:BAEBLgAECn8pAAMTAAkJdRjuGAD2AQATAAkJdRjuGAD2AQASAAEJsgFhTgAiAAAAAA==.',
Se='Sedaline:BAAALgAECgQJBgAAAA==.Sephie:BAAALgADCgQJAQAAAQ==.Serenilock:BAAALgADCgMJAwAAAA==.Serfdog:BAAALgADCgcJDAAAAA==.Servoker:BAACLgAFFH8RAAISAAYJXxt+DgCNAQASAAYJXxt+DgCNAQAuAAQKfyUAAxMACAnbICEKANQCABMACAnbICEKANQCABIABwkkGrwVAPABAAAA.Setani:BAAALgADCgIJAgAAAA==.',
Sh='Shabzkaw:BAAALgADCgUJBQAAAA==.Shabzyt:BAAALgADCgQJBAAAAA==.Shaienne:BAAALgAECgMJAwAAAA==.Shambussy:BAAALgAECgEJAQAAAA==.Shamfore:BAAALgADCgEJAQAAAA==.Shamrockshak:BAABLgAECn8aAAIeAAYJAyMoHQBJAgAeAAYJAyMoHQBJAgAAAA==.Shaze:BAAALgADCggJDQAAAA==.Shenuton:BAAALgAECgYJDAAAAA==.Shieldinterd:BAAALgAECgMJAgABLgAECgcJHgAbAKIVAA==.Shiftkicker:BAAALgADCgMJAwAAAA==.Shocktherapy:BAAALgAECgEJAQAAAA==.Shockthêràpy:BAACLgAFFH8GAAIeAAIJ8BCsGgCQAAAeAAIJ8BCsGgCQAAAuAAQKfzAABB4ACQlbGG0nAPMBAB4ACQlbGG0nAPMBAAcAAwkWF3FfAKoAAB8AAQlPCkYrADgAAAAA.Shoes:BAABLgAECn89AAQhAAkJTSXjAQAqAwAhAAkJxiPjAQAqAwAgAAgJIx/cDQDVAgAYAAgJ9SJ1IQBJAgAAAA==.Shoresy:BAAALgAECgEJAQAAAA==.Shtdruid:BAAALgAECgcJDAAAAA==.Shyanni:BAAALgADCgMJAwAAAA==.Shöçkér:BAAALgAECgYJCQAAAA==.',
Si='Siaana:BAAALgADCgUJBQABLgAFFAIJCAAjAOwbAA==.Sibearian:BAABLgAECn8eAAQNAAgJ6Bg6DwDRAQANAAgJ6Bg6DwDRAQAPAAYJ0AqiIQDUAAAMAAIJPwSEdQBNAAAAAA==.Simi:BAACLgAFFH8IAAIYAAQJ0hK0PAAWAQAYAAQJ0hK0PAAWAQAuAAQKfygAAhgACQlwF5ArABgCABgACQlwF5ArABgCAAAA.',
Sk='Skrubzz:BAABLgAECn8ZAAMDAAgJIQbpIAA4AQADAAgJIQbpIAA4AQARAAQJzgKHhwChAAAAAA==.Skôrn:BAABLgAECn8wAAIFAAcJLQ9kkQA6AQAFAAcJLQ9kkQA6AQAAAA==.',
Sl='Sloppynachos:BAABLgAECn8pAAIVAAgJRhdmGgAvAgAVAAgJRhdmGgAvAgAAAA==.Slyman:BAAALgADCgUJBQABLgAECgYJBwAGAAAAAA==.',
Sm='Smithnwesson:BAAALgAECgIJAgAAAA==.Smokesçreen:BAACLgAFFH8HAAIXAAMJ3w7rFADKAAAXAAMJ3w7rFADKAAAuAAQKf0QAAxcACQl2IMgEAOACABcACQl2IMgEAOACABsABQm6BcHEAH8AAAAA.',
Sn='Snowhoof:BAAALgADCgUJBQAAAA==.',
So='Sogerä:BAABLgAECn8XAAISAAgJIQW1HAAEAQASAAgJIQW1HAAEAQAAAA==.Soonerpride:BAABLgAECn8cAAICAAgJBCPqJQBUAgACAAgJBCPqJQBUAgAAAA==.Sorinmarkov:BAAALgAECgQJBgAAAA==.Source:BAAALgAECgUJCAAAAA==.',
Sp='Spearminttea:BAAALgAECgcJCwAAAA==.Spellumgud:BAAALgAECgQJBgAAAA==.',
Sq='Squiby:BAABLgAECn84AAMWAAkJoCKABQDlAgAWAAkJoCKABQDlAgAIAAIJmRX+ZwCNAAAAAA==.Squizzy:BAAALgAECgEJAQAAAA==.',
St='Stabfore:BAABLgAECn8eAAMVAAkJqROJDwAdAgAVAAkJqROJDwAdAgAcAAEJJgRwKAAlAAAAAA==.Standaside:BAAALgAECgIJBAAAAA==.Stinky:BAABLgAECn8XAAIdAAgJkQnyDAArAQAdAAgJkQnyDAArAQAAAA==.Stix:BAACLgAFFH8IAAIVAAMJWRZeHwD8AAAVAAMJWRZeHwD8AAAuAAQKfyoAAxUACQm3GUMUAOcBABUACQm3GUMUAOcBAB0ABAmnFWMSAMkAAAAA.Stoya:BAAALgAECgQJBgABLgAECgkJJwAUAAUkAA==.Stuef:BAABLgAECn82AAIHAAkJGyHGCAC9AgAHAAkJGyHGCAC9AgAAAA==.Stuefagos:BAAALgAECgQJBwAAAA==.Stuefester:BAABLgAECn8gAAMEAAkJNiBhGwCPAgAEAAkJNiBhGwCPAgAjAAcJ4QmqLgDPAAAAAA==.Stueflare:BAAALgAECggJEAAAAA==.Stueflip:BAAALgADCgIJAgAAAA==.Stunsturds:BAABLgAECn8dAAMKAAYJQiAsGQApAgAKAAYJQiAsGQApAgAOAAEJ2AF+mQAaAAABLgAECgcJHgAbAKIVAA==.Stäirs:BAABLgAECn9CAAIRAAkJ5B3FDACLAgARAAkJ5B3FDACLAgAAAA==.',
Su='Summerlily:BAAALgADCgYJBgAAAA==.',
Sv='Svaja:BAAALgADCgkJEQABLgAECgcJFwASAPgGAA==.',
Sy='Sylaria:BAAALgAECgQJCgAAAA==.Syreline:BAAALgAECgEJAgAAAA==.',
['Sá']='Sáble:BAABLgAECn8kAAMBAAkJOwjFHgAEAQABAAkJ9gXFHgAEAQACAAcJhQiUtwD3AAAAAA==.',
['Sí']='Síñ:BAAALgAECgIJAgABLgAECggJIgAaAFIaAA==.',
['Sî']='Sîn:BAAALgADCgEJAQABLgAECggJIgAaAFIaAA==.',
['Sï']='Sïn:BAABLgAECn8iAAIaAAgJUhqvNgDyAQAaAAgJUhqvNgDyAQAAAA==.',
Ta='Taereachye:BAACLgAFFH8GAAIUAAIJriAaFQCYAAAUAAIJriAaFQCYAAAuAAQKfxcAAhQABwk5JAYKANMCABQABwk5JAYKANMCAAEuAAUUAwkHAAoAyRYA.Tailon:BAAALgADCgYJBgAAAA==.Taintedlove:BAAALgADCgYJBgAAAA==.Talenelat:BAAALgADCgcJCwAAAA==.Talikas:BAAALgAECggJEAABLgAECgkJMwAbAKcaAA==.Tankin:BAAALgADCgMJAwAAAA==.Tantric:BAAALgAECgIJAgABLgAECggJCQAGAAAAAA==.Tarathiel:BAAALgADCgQJBAAAAA==.Taurne:BAACLgAFFH8TAAIJAAUJnwpoIgArAQAJAAUJnwpoIgArAQAuAAQKfx4AAgkABwmzGYEwAOkBAAkABwmzGYEwAOkBAAAA.',
Te='Technique:BAAALgAECgIJBAAAAA==.Teebags:BAAALgADCgEJAQAAAA==.Teknoman:BAACLgAFFH8IAAIRAAIJ+h4YNQCmAAARAAIJ+h4YNQCmAAAuAAQKfzsAAhEACQn+ID8JALsCABEACQn+ID8JALsCAAAA.Telmarine:BAAALgAECgMJAwAAAA==.Tempered:BAABLgAECn8UAAMoAAYJLhpuGQB3AQAoAAYJWBluGQB3AQARAAQJRRsjXADHAAAAAA==.Terlemen:BAAALgAECgUJBQAAAA==.Tetsumi:BAAALgADCgYJCQABLgAECggJDQAGAAAAAA==.',
Th='Thaddeus:BAAALgAECgEJAQABLgAFFAQJDgAGAAAAAQ==.Thaitea:BAAALgAECgUJBgAAAA==.Thal:BAAALgAECgMJAwAAAA==.Thalan:BAAALgADCgEJAQAAAA==.Thalindra:BAABLgAECn8cAAIYAAYJFBr/XgBwAQAYAAYJFBr/XgBwAQAAAA==.Tharain:BAAALgADCgkJEQAAAA==.Thebigbeast:BAAALgAECgEJAQABLgAFFAYJFQAaAJoTAA==.Thecurt:BAABLgAECn9BAAIOAAkJnyTRAQBAAwAOAAkJnyTRAQBAAwAAAA==.Thedammed:BAAALgADCgEJAQAAAA==.Theholylight:BAAALgAECgYJDQAAAA==.Thehuzz:BAAALgAECggJDAAAAA==.Thermidor:BAABLgAECn8gAAIhAAkJYBV5CQBLAgAhAAkJYBV5CQBLAgAAAA==.Thorsamie:BAAALgAECggJCwAAAA==.Thrasios:BAAALgAECgIJAgAAAA==.Thundercunti:BAAALgADCgYJDAAAAA==.',
Ti='Tiamatt:BAAALgADCgIJBAAAAA==.Ticktock:BAAALgAECgIJAgAAAA==.Timaeus:BAAALgAECgYJEwAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Titanlock:BAAALgAECgQJCAAAAA==.',
Tk='Tkdfath:BAAALgAECggJEgAAAA==.',
To='Torvia:BAAALgAECgQJCgAAAA==.Totemix:BAAALgADCgcJEgAAAA==.Totemsoul:BAAALgAECgEJAQABLgAECgcJCgAGAAAAAA==.',
Tr='Trisinz:BAABLgAECn8lAAIMAAgJ0RexGgDcAQAMAAgJ0RexGgDcAQAAAA==.Trixa:BAAALgADCgMJAwAAAA==.',
Tu='Tuerto:BAAALgAECgYJEwAAAA==.Turbojohnson:BAAALgAECgQJBgAAAA==.Turk:BAABLgAECn9EAAMbAAkJtRdiIQA5AgAbAAkJtRdiIQA5AgAXAAEJCQ/BcwAxAAAAAA==.Turkish:BAABLgAECn9AAAMEAAkJZBqRLAA5AgAEAAkJZBqRLAA5AgAmAAEJ7ga1MwApAAAAAA==.Turtledisco:BAACLgAFFH8KAAIDAAQJ3yEyDgArAQADAAQJ3yEyDgArAQAuAAQKfycAAgMACQnSH7sDABcDAAMACQnSH7sDABcDAAAA.',
Ty='Tychaa:BAAALgADCgkJEQAAAA==.Tylat:BAAALgADCgEJBAAAAA==.Tyranax:BAACLgAFFH8FAAInAAIJ1wpnMwCDAAAnAAIJ1wpnMwCDAAAuAAQKfz0ABCcACQnlG6QIAM4CACcACQneGqQIAM4CAAgABgnVH1IcAPoBABYABwkxE7otAEoBAAAA.Tyyregade:BAAALgADCgkJCgABLgAECggJDQAGAAAAAA==.',
Uj='Ujimas:BAAALgAECgEJAgAAAA==.',
Us='Us:BAAALgAECggJCQAAAA==.',
Uz='Uzzi:BAAALgAECgEJAQAAAA==.',
Va='Vadose:BAABLgAECn8fAAIaAAcJsgqmgQBXAQAaAAcJsgqmgQBXAQABLgAFFAQJCAAYANISAA==.Vales:BAAALgAECgMJAwABLgAFFAMJBQAYAMABAA==.Valsavis:BAABLgAECn8bAAIMAAYJbRS/MgA1AQAMAAYJbRS/MgA1AQAAAA==.Valytrois:BAABLgAECn8UAAIaAAcJXQmysQD1AAAaAAcJXQmysQD1AAAAAA==.Varinix:BAAALgADCgMJBQAAAA==.',
Ve='Veggiebaha:BAAALgADCgIJAgAAAA==.Veiksla:BAABLgAECn8XAAISAAcJ+AYdHQD/AAASAAcJ+AYdHQD/AAAAAA==.Velore:BAAALgADCgcJDAAAAA==.Vengerr:BAAALgAECgQJBgAAAA==.Verace:BAAALgAECgcJAQAAAA==.Verradic:BAAALgAECgYJBgABLgAECggJHwAYABQNAA==.',
Vi='Vitur:BAABLgAECn9HAAIbAAkJ/iCuEgCZAgAbAAkJ/iCuEgCZAgAAAA==.',
Vo='Voidhunter:BAABLgAECn8VAAIbAAcJGwrphwDyAAAbAAcJGwrphwDyAAAAAA==.Voidweaver:BAAALgAECgMJBQAAAA==.Volaine:BAABLgAECn8dAAMaAAYJOwxepADsAAAaAAUJDgtepADsAAAZAAIJuhSsNAA5AAAAAA==.Volt:BAABLgAECn8zAAIfAAkJ4hfsCAAZAgAfAAkJ4hfsCAAZAgAAAA==.Volumoso:BAAALgAECgYJBgAAAA==.Volwryn:BAAALgAECgUJCAABLgAECggJCQAGAAAAAA==.',
Vy='Vynarian:BAABLgAECn8dAAIFAAYJ/xXUigBHAQAFAAYJ/xXUigBHAQAAAA==.',
['Vâ']='Vâljean:BAAALgADCgMJAwAAAA==.',
['Vô']='Vôx:BAAALgAECgEJAQABLgAECggJIQAQAJEZAA==.',
['Vö']='Vöx:BAAALgAECgEJAQABLgAECggJIQAQAJEZAA==.',
Wa='Warbeard:BAABLgAECn8oAAIRAAkJ8gsxKACmAQARAAkJ8gsxKACmAQAAAA==.',
Wi='Wizwizx:BAAALgADCgUJBgAAAA==.',
Wr='Wreckbums:BAABLgAFFH8FAAIEAAIJZCPsjgDNAAAEAAIJZCPsjgDNAAAAAA==.Wreckd:BAABLgAECn8YAAMbAAcJghIVYgBLAQAbAAcJLRIVYgBLAQAXAAIJIgxdZwAqAAAAAA==.',
Wy='Wyth:BAAALgAECgQJBQABLgAECgQJBgAGAAAAAA==.',
Xa='Xanthad:BAAALgADCgEJAQAAAA==.',
Xb='Xb:BAAALgADCgkJDgAAAA==.',
Xi='Xitãozinho:BAAALgAECgUJBwAAAA==.',
Xo='Xolair:BAAALgAECgYJDgAAAA==.',
Ya='Yaalia:BAAALgAECgYJEAAAAA==.Yaan:BAABLgAECn8gAAIHAAgJMQqaPgAdAQAHAAgJMQqaPgAdAQAAAA==.',
Yo='Yoba:BAAALgAECgMJAwAAAA==.Yoshira:BAAALgADCgQJBAAAAA==.',
['Yö']='Yör:BAAALgAECgEJAQAAAA==.',
Za='Zain:BAABLgAECn9GAAQoAAkJNx2zBgB8AgAoAAkJNx2zBgB8AgARAAYJGA5fWQBIAQADAAIJKA3xQgBOAAAAAA==.Zandibar:BAABLgAECn8dAAIRAAYJyRudLACNAQARAAYJyRudLACNAQAAAA==.Zaptoasted:BAAALgAECgUJBgAAAA==.Zaroff:BAAALgAECgYJCgAAAA==.',
Ze='Zedadiah:BAAALgADCgEJAQAAAA==.Zelah:BAAALgAECgQJBAAAAA==.Zenessa:BAAALgADCgYJBgAAAA==.',
Zi='Zinder:BAABLgAECn8oAAIFAAkJsQ5NUgDNAQAFAAkJsQ5NUgDNAQAAAA==.',
Zu='Zuggie:BAABLgAECn8bAAIaAAcJOwajpQDqAAAaAAcJOwajpQDqAAAAAA==.Zugtail:BAAALgAECgQJBAABLgAECgcJGwAaADsGAA==.Zurtrinik:BAACLgAFFH8YAAIDAAcJMR9fAgCSAQADAAcJMR9fAgCSAQAuAAQKfyUAAgMACAmZJDwCAE0DAAMACAmZJDwCAE0DAAAA.',
Zy='Zylith:BAAALgAECgYJBgABLgAECgkJMwAfAOIXAA==.',
Zz='Zzonked:BAABLgAECn8pAAMEAAkJCwjfgABMAQAEAAkJzwbfgABMAQAjAAIJ/gtGPwBSAAAAAA==.',
['Zê']='Zêp:BAAALgAECgEJAgAAAA==.',
['Zø']='Zøømies:BAABLgAECn8qAAMbAAkJhhcYLwD1AQAbAAkJMBcYLwD1AQAiAAYJFQ8mFADzAAAAAA==.',
['Är']='Äréa:BAAALgADCgkJCQAAAA==.',
['Äs']='Äshnärd:BAACLgAFFH8HAAIeAAIJLSUIPQDUAAAeAAIJLSUIPQDUAAAuAAQKfzMAAh4ACQlLJIkFAEYDAB4ACQlLJIkFAEYDAAAA.',
['Ða']='Ðar:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðoogle:BAABLgAECn8XAAIHAAcJ5RlLKwCAAQAHAAcJ5RlLKwCAAQAAAA==.',
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
