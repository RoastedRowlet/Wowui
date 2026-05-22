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

local lookup = {'Unknown-Unknown','Mage-Frost','Druid-Guardian','Druid-Restoration','Druid-Balance','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Warlock-Affliction','Warlock-Demonology','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','Shaman-Restoration','Monk-Windwalker','Monk-Brewmaster','Warrior-Protection','Warrior-Fury','Priest-Shadow','Priest-Holy','Druid-Feral','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Hunter-Survival','Hunter-Marksmanship','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','DeathKnight-Unholy','Warlock-Destruction','Mage-Arcane','Paladin-Protection','Shaman-Elemental','Rogue-Outlaw','Evoker-Preservation','Warrior-Arms',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abarlton:BAAALgAFFAEJAQABLgAECgcJDAABAAAAAA==.',
Ad='Adabeam:BAAALgADCgcJCwAAAA==.Adagio:BAABLgAECn81AAICAAkJOxtJKAA3AgACAAkJOxtJKAA3AgAAAA==.Adetalo:BAABLgAECn8kAAIDAAkJ9RcrCAAIAgADAAkJ9RcrCAAIAgAAAA==.Adiara:BAAALgAECgMJAwAAAA==.Aditu:BAABLgAECn8UAAMEAAYJ7hr4JwDKAQAEAAYJ7hr4JwDKAQAFAAMJ9RDNXQCrAAAAAA==.',
Ae='Aelis:BAAALgADCgcJCAAAAA==.Aemulo:BAAALgAECgUJBwAAAA==.Aerith:BAAALgADCgcJBwAAAA==.',
Ag='Agasonex:BAAALgADCgMJAwAAAA==.',
Ai='Airent:BAAALgAECgUJCwAAAA==.Aiyana:BAAALgAECgYJDgAAAA==.',
Ak='Akiirii:BAAALgAECgEJAQAAAA==.',
Al='Alaestel:BAAALgAECgQJBwAAAA==.Aldo:BAAALgADCgYJEQAAAA==.Alkaraho:BAAALgAECgMJAwAAAA==.Alleyways:BAABLgAECn8xAAIGAAkJ9yV+AADTAwAGAAkJ9yV+AADTAwAAAA==.Alzey:BAABLgAECn8fAAIHAAgJjA1wZABcAQAHAAgJjA1wZABcAQAAAA==.',
Am='Ambeon:BAAALgADCgUJBQAAAA==.Ammathindis:BAAALgADCgcJCQAAAA==.Ammutseba:BAAALgADCggJCAAAAA==.Amplers:BAAALgADCgUJBwAAAA==.',
An='Angelbane:BAAALgADCgQJBAAAAA==.Angina:BAAALgAECgIJAwAAAA==.Annarcis:BAAALgAECgUJCgAAAA==.Anotherdk:BAAALgAECgYJBgABLgAECggJHQAIALkhAA==.Anthiell:BAAALgADCgEJAQAAAA==.Antiman:BAABLgAECn8gAAIHAAgJjAiNdAA5AQAHAAgJjAiNdAA5AQAAAA==.',
Ap='Aplcyder:BAABLgAECn8vAAIEAAkJEwxfPQBVAQAEAAkJEwxfPQBVAQAAAA==.',
Ar='Arachnid:BAABLgAECn8xAAICAAcJsiRFMQCtAgACAAcJsiRFMQCtAgAAAA==.Aragorn:BAAALgADCgkJDQAAAA==.Aratyn:BAAALgAECgYJDwAAAA==.',
At='Ati:BAAALgADCgIJAgAAAA==.',
Au='Audxo:BAAALgADCgMJAwAAAA==.',
Ay='Ayayron:BAAALgADCgQJBAAAAA==.',
Ba='Backhawk:BAAALgADCgcJEAAAAA==.Backsurgery:BAAALgAFFAQJBAAAAA==.Baerrn:BAAALgAECgUJDgAAAA==.Bamboo:BAAALgAECgYJCQAAAA==.Baricia:BAABLgAECn8aAAICAAkJWApbUQCmAQACAAkJWApbUQCmAQAAAA==.Barix:BAAALgAECgEJAwAAAA==.Barnd:BAAALgADCggJDwAAAA==.Barrin:BAABLgAECn8pAAMJAAgJ9hpvBQDHAQAJAAgJ9hpvBQDHAQAKAAUJQgh0iwDmAAAAAA==.Bastim:BAAALgAECgMJBQAAAA==.Baussassbich:BAAALgAECgQJBAABLgAECgkJJAAKAEkhAA==.Bawnchu:BAAALgAECgMJBQAAAA==.',
Be='Beastmaster:BAACLgAFFH8FAAILAAMJvSBDJAAsAQALAAMJvSBDJAAsAQAuAAQKfy8AAgsACAmYJEYJAM8CAAsACAmYJEYJAM8CAAAA.Beefcakell:BAAALgADCgcJDQAAAA==.Beiki:BAAALgAECgUJCgAAAA==.Belthar:BAAALgAECgQJCQAAAA==.Bently:BAABLgAECn8iAAMMAAcJoyHbFQDfAQAMAAcJ8h/bFQDfAQANAAUJGCMtEwCvAQAAAA==.Berexis:BAAALgAECggJDwAAAA==.',
Bi='Bissafiyah:BAACLgAFFH8XAAIOAAYJBCVxAAD1AQAOAAYJBCVxAAD1AQAuAAQKf0gAAg4ACQl1JSIAAOkDAA4ACQl1JSIAAOkDAAAA.Biznasty:BAAALgAECgEJAwAAAA==.',
Bl='Bloodgon:BAAALgAFFAIJBAAAAA==.Bluetuesday:BAAALgAECgMJAwAAAA==.',
Bo='Bohica:BAABLgAECn84AAIPAAkJRxGRKADDAQAPAAkJRxGRKADDAQAAAA==.Bonechop:BAAALgADCgYJBgAAAA==.Bootymeat:BAAALgADCgEJAQAAAA==.Bowtox:BAAALgAECgEJAQAAAA==.Boyakasha:BAAALgAECgYJEAAAAA==.',
Br='Brewfu:BAAALgADCgIJAgAAAA==.Brewpub:BAAALgADCgQJBAAAAA==.Brewsome:BAABLgAECn84AAMQAAkJXyDPBADOAgAQAAkJESDPBADOAgARAAkJ1Bg1DAA2AgAAAA==.Bruceprime:BAAALgAECgkJAQAAAA==.Bryybryy:BAAALgAECgUJBQABLgAECggJIgARAOQaAA==.Bryycelest:BAABLgAECn8iAAIRAAgJ5BppEAD8AQARAAgJ5BppEAD8AQAAAA==.Brådòn:BAAALgAECgYJDQAAAA==.',
Bu='Bucket:BAABLgAECn8jAAISAAgJyRHMFADAAQASAAgJyRHMFADAAQAAAA==.Bunkiee:BAAALgADCgkJHQAAAA==.Bunnybane:BAAALgAECgYJEAAAAA==.Burny:BAABLgAECn8aAAICAAcJVCVMJgDZAgACAAcJVCVMJgDZAgAAAA==.Buttadogg:BAAALgAECgcJDwAAAA==.',
['Bè']='Bèth:BAAALgADCgkJCQAAAA==.',
['Bë']='Bëckey:BAAALgADCgIJAgAAAA==.',
Ca='Calyx:BAAALgAECgYJEQAAAA==.Canadani:BAAALgAECgcJDQAAAA==.Candorite:BAAALgAECgYJDwAAAA==.Caphriel:BAABLgAECn8dAAITAAkJPh1IDABeAgATAAkJPh1IDABeAgAAAA==.Capita:BAABLgAECn8cAAICAAgJjAmmdgBNAQACAAgJjAmmdgBNAQAAAA==.Carsinegan:BAAALgADCgUJCwAAAA==.Cassica:BAABLgAECn8dAAMUAAcJbhlYJQBJAQAUAAcJbhlYJQBJAQAVAAIJ1glXTwBQAAAAAA==.Catchdezhanz:BAAALgADCgcJBwABLgAECgYJHAAIAJcUAA==.Catskin:BAABLgAECn8bAAMEAAgJZB6wLgChAQAEAAYJ8RuwLgChAQAWAAUJjSOkDACNAQAAAA==.',
Ce='Celivalasha:BAAALgADCgUJBQAAAA==.Cell:BAABLgAECn8jAAIRAAgJTSQqBQA3AwARAAgJTSQqBQA3AwAAAA==.Cet:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.',
Ch='Chadvader:BAAALgADCgIJAgAAAA==.Chainlink:BAAALgADCgYJBgAAAA==.Chalee:BAAALgAECgEJAQAAAA==.Chanpagne:BAAALgADCgUJBQAAAA==.Charkle:BAAALgAECgQJBgAAAA==.Chayea:BAAALgADCgEJAQAAAA==.Chillylilly:BAABLgAECn8qAAMXAAkJbCXqAABIAwAXAAkJbCXqAABIAwAYAAQJixmnDwD5AAAAAA==.Chlorophyll:BAAALgAECgQJBAAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chummie:BAABLgAECn8oAAMKAAkJrR9pDQCvAgAKAAkJRB9pDQCvAgAJAAYJdxxDCADHAQAAAA==.',
Ci='Cielcin:BAAALgAFFAMJAwAAAA==.Ciremiih:BAAALgAECgEJAQAAAA==.Citymage:BAABLgAECn8mAAICAAkJmxeHMgANAgACAAkJmxeHMgANAgAAAA==.Cixelsyd:BAAALgADCgYJCwABLgAFFAUJDAAHAEQEAA==.',
Cl='Clamchowda:BAABLgAECn8vAAMZAAkJjhsIGQA9AgAZAAkJGRkIGQA9AgAaAAUJUh5wIwCiAQAAAA==.',
Co='Codê:BAABLgAECn8gAAIKAAgJkhZKNwC8AQAKAAgJkhZKNwC8AQAAAA==.Coffeecup:BAAALgADCgIJAgAAAA==.Corride:BAABLgAECn8mAAIbAAcJxyDlCQBAAgAbAAcJxyDlCQBAAgAAAA==.Corspar:BAAALgAECgEJAgAAAA==.',
Cr='Crazyeyes:BAAALgADCgMJAwAAAA==.Crimsondeath:BAAALgAECgYJEQAAAA==.Crutch:BAABLgAECn8bAAMPAAcJQyCFFwA5AgAPAAYJlyGFFwA5AgAOAAUJJhQ2EgAZAQAAAA==.Crystanikus:BAAALgAECgQJBQAAAA==.',
Cu='Cuckenjoyer:BAAALgAECgYJCgAAAA==.',
Cy='Cyclonian:BAAALgAECgEJAgABLgAECgIJAgABAAAAAA==.Cyprus:BAAALgAECgEJAQAAAA==.',
Da='Daddytrump:BAAALgAECgYJDwAAAA==.Daelric:BAAALgADCgIJAwAAAA==.Daender:BAABLgAECn8sAAMLAAkJWCROBAAZAwALAAkJWCROBAAZAwAcAAEJghihLAA4AAAAAA==.Daenor:BAAALgAECgEJAwAAAA==.Dairydemon:BAABLgAECn8uAAIdAAgJRw4uDQArAQAdAAgJRw4uDQArAQAAAA==.Damageus:BAACLgAFFH8FAAICAAMJfhw1TgANAQACAAMJfhw1TgANAQAuAAQKfx0AAgIACAnpIjkkAOICAAIACAnpIjkkAOICAAAA.Daniryl:BAEBLgAECn8bAAIEAAgJfxW3IQD0AQAEAAgJfxW3IQD0AQAAAA==.Dar:BAAALgAECgQJBwAAAA==.Darcness:BAABLgAECn8hAAMeAAYJ2BN8CwA1AQAeAAYJLRF8CwA1AQAfAAUJTxanKAD0AAAAAA==.Darcside:BAAALgAECgYJDgAAAA==.Darkclouds:BAAALgADCgIJAgAAAA==.Darksoul:BAAALgAECgcJEAABLgAECgcJFwAgAAMaAA==.Darkxwraith:BAABLgAECn8UAAIIAAcJzxcHGwDfAQAIAAcJzxcHGwDfAQAAAA==.Dashtoolite:BAABLgAECn8VAAIZAAcJcAm/dADkAAAZAAcJcAm/dADkAAAAAA==.Datsumbeech:BAABLgAECn8XAAIYAAcJAgiDDwD7AAAYAAcJAgiDDwD7AAAAAA==.',
De='Deajer:BAAALgADCgYJBwAAAA==.Deathsabeach:BAAALgAECgEJAQAAAA==.Deathvìxen:BAAALgAECgYJEQAAAA==.Debit:BAAALgAECgcJEwAAAA==.Demonhunter:BAACLgAFFH8KAAIZAAQJkiHCGwBbAQAZAAQJkiHCGwBbAQAuAAQKfx0AAhkACAk/JKkKAC4DABkACAk/JKkKAC4DAAAA.Demonwoogie:BAAALgADCgYJBgABLgAECgQJCwABAAAAAA==.Dendrophilia:BAAALgAECgEJAgAAAA==.Densamin:BAABLgAECn8gAAMHAAgJNRWURgCqAQAHAAgJNRWURgCqAQAIAAEJxwHLfwAfAAAAAA==.Deviyn:BAAALgADCgIJAgAAAA==.Devra:BAAALgADCggJCAAAAA==.Deàdly:BAAALgAECgYJDAAAAA==.',
Di='Dietchrist:BAAALgAECggJEwAAAA==.Dilligaf:BAAALgADCggJCAAAAA==.',
Dk='Dkanabiss:BAAALgAECgMJBAAAAA==.Dkinabox:BAAALgADCgEJAgAAAA==.',
Do='Docbaba:BAAALgAECgUJBAAAAA==.Doist:BAAALgAECgIJAgABLgAECgYJFAAQAF8OAA==.Donngaz:BAAALgAECgMJBgAAAA==.',
Dr='Drewnei:BAAALgADCgkJCQAAAA==.Drewserk:BAABLgAECn8kAAITAAkJ3RoODgBIAgATAAkJ3RoODgBIAgAAAA==.Drkxmaniac:BAAALgAECgUJCgABLgAECgcJDAABAAAAAA==.Drminnowphd:BAAALgAFFAEJAQAAAA==.Drpiscisphd:BAABLgAECn8sAAMhAAkJtiDuDgAkAwAhAAkJtiDuDgAkAwAXAAcJwwWCKQDzAAABLgAFFAEJAQABAAAAAA==.Drsaltyballz:BAABLgAECn8uAAIeAAkJyiKxAAATAwAeAAkJyiKxAAATAwAAAA==.Drugpala:BAAALgAECgIJAgAAAA==.Druji:BAAALgAECgEJAQAAAA==.Drumuss:BAAALgADCgEJAQAAAA==.',
Du='Ducat:BAAALgAECgUJDQAAAA==.Dudesk:BAAALgAECgQJBAAAAA==.Duffuna:BAAALgADCgEJAQABLgAECgkJOgAbANglAA==.Duffunha:BAABLgAECn86AAIbAAkJ2CVRAAB5AwAbAAkJ2CVRAAB5AwAAAA==.',
Dy='Dye:BAABLgAECn8oAAIIAAkJahxuBwDUAgAIAAkJahxuBwDUAgAAAA==.Dyre:BAABLgAECn8gAAIdAAgJIwz5DAAuAQAdAAgJIwz5DAAuAQAAAA==.Dyslexic:BAABLgAECn8gAAIiAAgJKxdDBQDKAQAiAAgJKxdDBQDKAQABLgAFFAUJDAAHAEQEAA==.Dyspepsia:BAACLgAFFH8MAAIHAAUJRAQQEQAdAQAHAAUJRAQQEQAdAQAuAAQKfxsAAgcACQn7FQo2AEoCAAcACQn7FQo2AEoCAAAA.',
['Dô']='Dôngus:BAAALgADCgMJAwABLgAECgIJAgABAAAAAA==.',
['Dõ']='Dõngus:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
['Dö']='Döngus:BAAALgADCgEJAQABLgAECgIJAgABAAAAAA==.',
Ed='Edie:BAAALgAECgEJAgAAAA==.',
Ei='Eirenn:BAAALgAECgkJBgAAAA==.',
El='Elayna:BAAALgAECgkJBwAAAA==.Elenaura:BAAALgAECgMJAwAAAA==.Eleren:BAABLgAECn8XAAIZAAYJnxJ9ZwBsAQAZAAYJnxJ9ZwBsAQAAAA==.Elimee:BAABLgAECn8uAAICAAkJYyBJDgBUAwACAAkJYyBJDgBUAwAAAA==.Elisestraza:BAAALgAECgUJBgABLgAECgkJLgACAGMgAA==.Ellasia:BAAALgAECgUJCAAAAA==.Elric:BAABLgAECn81AAIHAAkJSxnpHwBEAgAHAAkJSxnpHwBEAgAAAA==.Elsie:BAAALgAECgUJCgABLgAECgYJDQABAAAAAA==.Elunea:BAAALgADCgcJDQAAAA==.Elunemittens:BAAALgADCgYJBgAAAA==.',
Em='Emart:BAABLgAECn8dAAIbAAgJXw0wGgCCAQAbAAgJXw0wGgCCAQAAAA==.Emozella:BAAALgAECgEJAQAAAA==.',
En='Enatresh:BAAALgAECgcJDwAAAA==.',
Ep='Epsilon:BAAALgAECgkJCQAAAA==.',
Er='Erayna:BAABLgAECn8uAAIEAAkJ8BIxHgAMAgAEAAkJ8BIxHgAMAgAAAA==.Ereillea:BAAALgAECgYJDQAAAA==.',
Es='Essence:BAABLgAECn8WAAMCAAgJmxTpagAAAgACAAgJDBHpagAAAgAjAAQJ1xocDAARAQAAAA==.',
Eu='Euko:BAABLgAECn81AAMFAAkJLyGjBADZAgAFAAkJLyGjBADZAgAEAAgJdRXJUQABAQAAAA==.',
Ev='Evedk:BAAALgAECgkJBQAAAA==.Evepriest:BAAALgADCgMJAQAAAA==.',
Fa='Failrogue:BAAALgADCgUJCwAAAA==.Falconclaw:BAAALgADCgkJGAAAAA==.Falkensnoman:BAABLgAECn8gAAIXAAgJEhMxFAB5AQAXAAgJEhMxFAB5AQAAAA==.Fayedra:BAAALgAECgYJDwAAAA==.',
Fc='Fcawfe:BAAALgAECgMJAwABLgAECgYJCwABAAAAAA==.',
Fe='Febee:BAAALgADCgcJAQAAAA==.Feenii:BAABLgAECn8yAAIOAAkJUR2GAgCrAgAOAAkJUR2GAgCrAgAAAA==.Felburst:BAAALgAECgMJAwAAAA==.Felfireqt:BAAALgAECgEJAgAAAA==.',
Fi='Figgyandrii:BAAALgADCgcJBwAAAA==.Fionar:BAAALgADCgIJAgAAAA==.Fizzlelich:BAAALgADCgkJEwAAAA==.',
Fl='Flamesters:BAAALgAECgIJAwAAAA==.Fluffpuff:BAAALgADCgMJAwAAAA==.',
Fo='Foxdeer:BAAALgAECgcJEgAAAA==.',
Fr='Frenchtoast:BAAALgAECgUJBwAAAA==.',
Fu='Furyrage:BAAALgADCgEJAQAAAA==.Fuzzyclawz:BAAALgADCgMJAwABLgAECgkJJwAQADIQAA==.',
Ga='Gambachii:BAAALgAECgcJDQAAAA==.Gankss:BAABLgAECn8dAAIIAAgJuSFJBgDpAgAIAAgJuSFJBgDpAgAAAA==.Garakddon:BAAALgADCgkJFgABLgAECgcJGwAkADkUAA==.Garryy:BAAALgAECgMJBwAAAA==.',
Ge='Geegandolm:BAAALgADCgkJEwAAAA==.Genjaru:BAAALgAECgYJCgAAAA==.Genndalf:BAAALgADCgcJBwAAAA==.Geostorm:BAAALgAECgEJAQAAAA==.',
Gh='Gharmag:BAAALgAECgEJAQAAAA==.',
Gi='Giramar:BAABLgAECn8hAAMUAAgJmRgjFADdAQAUAAgJmRgjFADdAQAVAAYJjxCKKgArAQAAAA==.',
Go='Gobbyshamm:BAAALgAECgEJAQAAAA==.Gobsmackers:BAAALgAECgYJBwAAAA==.Gomklin:BAAALgADCgcJCAABLgAECgkJPAAHAMElAA==.Goobtastic:BAAALgADCgQJBAAAAA==.Goteem:BAAALgAECggJEwAAAA==.Gothitelle:BAAALgAECgEJAgAAAA==.',
Gr='Griffhud:BAAALgAECgYJDgAAAA==.Grimrox:BAABLgAECn8WAAIlAAcJGQ9vLgAuAQAlAAcJGQ9vLgAuAQAAAA==.Grixx:BAAALgADCgUJBQAAAA==.Groupie:BAAALgADCgUJCgABLgAECgcJGAAcANUPAA==.',
Gt='Gtatedk:BAAALgAECgEJAQAAAA==.',
Gu='Guntera:BAAALgAECgYJDgAAAA==.Guts:BAAALgADCgMJAwAAAA==.',
Gw='Gwendalyn:BAAALgAECgQJBQAAAA==.',
['Gä']='Gäz:BAAALgADCgEJAQAAAA==.',
Ha='Halexion:BAAALgADCgIJAgAAAA==.Haomaru:BAABLgAECn8VAAIEAAUJLBk7OgBkAQAEAAUJLBk7OgBkAQAAAA==.Hardcandy:BAABLgAECn8YAAIcAAcJ1Q/3EQD2AAAcAAcJ1Q/3EQD2AAAAAA==.Hardlyevoker:BAAALgADCgEJAQABLgAFFAIJBgAIAOYQAA==.Hawkìns:BAAALgAECgEJAQAAAA==.',
He='Heartsoul:BAAALgAECgYJCQAAAA==.Heavyarm:BAAALgADCgcJDwAAAA==.Hellork:BAAALgADCgQJBAAAAA==.Hermosura:BAAALgADCgUJCQAAAA==.Hex:BAAALgAECgYJBgAAAA==.',
Hi='Hiccups:BAAALgAECgMJBAABLgAECgUJBwABAAAAAA==.Himawarí:BAAALgAECgYJDwAAAA==.Hiyank:BAABLgAECn8dAAIRAAgJGCCRDAAwAgARAAgJGCCRDAAwAgAAAA==.',
Ho='Hoffmin:BAABLgAECn8TAAMZAAcJBBjwVwAtAQAZAAYJBBjwVwAtAQAaAAIJphK0VgCMAAAAAA==.Holemeister:BAACLgAFFH8FAAIHAAMJgCO/JAA6AQAHAAMJgCO/JAA6AQAuAAQKfy8AAgcACAmdJOINAB8DAAcACAmdJOINAB8DAAAA.Holyfresh:BAAALgADCgEJAQAAAA==.Holymann:BAABLgAECn8fAAIUAAcJ1wx+NQA/AQAUAAcJ1wx+NQA/AQAAAA==.Holyschnikey:BAABLgAECn8cAAIIAAYJlxQfLwBPAQAIAAYJlxQfLwBPAQAAAA==.Holyz:BAABLgAECn8hAAIIAAgJCyFXBwDWAgAIAAgJCyFXBwDWAgAAAA==.Horgable:BAAALgADCgIJAgAAAA==.Horrorpops:BAAALgADCgUJBQAAAA==.Hozaki:BAAALgAECgQJBAABLgAECgcJDAABAAAAAA==.',
Hu='Hudfin:BAAALgADCgUJBQAAAA==.Hundred:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.',
['Hí']='Hílthaen:BAABLgAECn8oAAIVAAgJCRWREQALAgAVAAgJCRWREQALAgAAAA==.',
Ic='Icebones:BAAALgADCgcJDAABLgAECgQJCQABAAAAAA==.Icelight:BAAALgAECgQJCQAAAA==.Ichigokisu:BAAALgAECgQJCQAAAA==.',
Il='Illiduji:BAAALgADCgMJAwAAAA==.Illy:BAABLgAECn8jAAIZAAkJ+hZyHgAZAgAZAAkJ+hZyHgAZAgAAAA==.',
Im='Imposed:BAAALgAECgcJEAAAAA==.',
In='Instantdeath:BAAALgAECgcJDAAAAA==.Invali:BAAALgAECgMJAwAAAA==.',
Io='Iorla:BAAALgADCgEJAQAAAA==.',
Ir='Irônhide:BAAALgAECgEJAQAAAA==.',
Iv='Ivranda:BAAALgADCgkJEgABLgAECgYJDwABAAAAAA==.',
Iz='Iz:BAAALgAECgEJAQAAAA==.',
Ja='Jaapp:BAAALgAECgMJBgAAAA==.Jahan:BAACLgAFFH8FAAIgAAMJRRi/GwD4AAAgAAMJRBi/GwD4AAAuAAQKfy0AAyAACAkiJCwDADgDACAACAkiJCwDADgDABQAAwnIEgQ/ALwAAAAA.Jamie:BAABLgAFFH8FAAIhAAIJ3Bt6ewCuAAAhAAIJ3Bt6ewCuAAABLgAFFAcJFAAKAFAgAA==.Jaydine:BAAALgADCgYJBgABLgAECgkJLgACAGMgAA==.',
Je='Jeri:BAAALgAECgEJAQAAAA==.',
Jh='Jhie:BAAALgAECgUJCQAAAA==.',
Ju='Jud:BAAALgAECggJDwAAAA==.Juviâ:BAAALgAECgMJAgABLgAECgYJDQABAAAAAA==.Juxtaposed:BAAALgADCgUJBQAAAA==.',
Ka='Kaelora:BAAALgADCggJCgAAAA==.Kaerei:BAABLgAECn8nAAIHAAkJnh69EQCfAgAHAAkJnh69EQCfAgAAAA==.Kaleb:BAABLgAECn8bAAIaAAgJtiEfBgCKAgAaAAgJtiEfBgCKAgAAAA==.Kalfalah:BAABLgAECn8ZAAQFAAcJrBLTJQBBAQAFAAcJNBLTJQBBAQAWAAMJHhSrHAC9AAAEAAEJRArXtwAmAAAAAA==.Kalferno:BAAALgAECgQJCQAAAA==.Kalirkaz:BAACLgAFFH8FAAIEAAMJ4gWNNwCQAAAEAAMJ4gWNNwCQAAAuAAQKfy0AAwQACQmLGgMPAJsCAAQACQmLGgMPAJsCAAUABQk5BhtJAJEAAAAA.Kallipsa:BAAALgAECgMJAwAAAA==.Karasu:BAAALgAECgIJAgABLgAECgkJJwAQADIQAA==.Karst:BAAALgAECgQJBQABLgAFFAMJBQAgAEUYAA==.Kathria:BAAALgAECgcJDAAAAA==.',
Ke='Kegendary:BAAALgAECgQJBQAAAA==.Keler:BAAALgADCgIJAwABLgAECgMJBwABAAAAAA==.Keládry:BAAALgAECgYJEgAAAA==.Keskiyö:BAAALgADCgkJFQABLgAECgkJJwAQADIQAA==.',
Kh='Khallock:BAABLgAECn8dAAIJAAYJjRhxDABxAQAJAAYJjRhxDABxAQAAAA==.Khamael:BAAALgAECgEJAQAAAA==.',
Ki='Kiemen:BAABLgAECn8gAAIhAAkJsBd3MQDyAQAhAAkJsBd3MQDyAQAAAA==.Killerpoison:BAAALgAECgkJBQAAAA==.Killko:BAABLgAECn8bAAIhAAkJ/hunGQBpAgAhAAkJ/hunGQBpAgAAAA==.Kinki:BAAALgAECgMJAwABLgAECgcJGAAcANUPAA==.Kirisen:BAAALgAECgUJCQAAAA==.Kitan:BAAALgAECgQJBQAAAA==.Kitani:BAAALgADCgkJDwABLgAECggJJwAVAGgcAA==.',
Ko='Konno:BAAALgAECgQJBAABLgAFFAYJFwAOAAQlAA==.Kooterr:BAAALgADCgUJBQAAAA==.Korbix:BAAALgAFFAEJAQAAAA==.',
Kr='Kragsloor:BAAALgADCgYJBgAAAA==.Kredorin:BAAALgAECgYJCgAAAA==.Krewella:BAAALgADCgcJBwAAAA==.Krihl:BAAALgAECgkJBgAAAA==.Krovmar:BAAALgADCgUJBQAAAA==.',
Ks='Kspanxx:BAAALgAECgMJAwAAAA==.',
Kt='Kthanx:BAAALgADCgYJBgAAAA==.',
Ku='Kungpowgazer:BAAALgAECgcJEgAAAA==.Kunls:BAABLgAECn8WAAIaAAcJvAcYIwD4AAAaAAcJvAcYIwD4AAAAAA==.Kuraki:BAAALgAECgYJDwAAAA==.Kurasa:BAABLgAECn8nAAMQAAkJMhDMFgCtAQAQAAkJMhDMFgCtAQAGAAQJowH4WgBjAAAAAA==.Kutraz:BAAALgAECgQJBQAAAA==.',
La='Ladrar:BAAALgAECgYJDQAAAA==.Laelina:BAAALgAECgEJAwAAAA==.Lanadiel:BAABLgAECn81AAIkAAkJhyIqAQAOAwAkAAkJhyIqAQAOAwAAAA==.Lazz:BAAALgAECgYJEgAAAA==.',
Le='Legend:BAACLgAFFH8PAAIZAAQJASGiFgB3AQAZAAQJASGiFgB3AQAuAAQKfysAAhkACQkeIDAJAD4DABkACQkeIDAJAD4DAAAA.Lekrotar:BAAALgAECgQJBAAAAA==.Letsyoudie:BAAALgAECgMJAwAAAA==.',
Li='Lian:BAAALgAECgUJDAAAAA==.Lichbane:BAABLgAECn81AAIhAAkJlyFXCwDbAgAhAAkJlyFXCwDbAgAAAA==.Licun:BAAALgAECgYJDQAAAA==.Lifexdeath:BAABLgAECn8ZAAMVAAcJ5QZlMQD8AAAVAAcJ5QZlMQD8AAAUAAEJxgOrawAlAAAAAA==.Lightcell:BAAALgAECgQJBgAAAA==.Liliara:BAABLgAECn80AAILAAkJ3RDJKgDhAQALAAkJ3RDJKgDhAQAAAA==.Lillyirl:BAAALgAECgQJCgAAAA==.Lillymae:BAAALgADCgYJCAAAAA==.Lillyslight:BAAALgADCgYJBgAAAA==.Lillysneak:BAAALgADCgUJCgAAAA==.Lillytae:BAAALgAECgQJBwAAAA==.Lillyzard:BAAALgADCgUJCAAAAA==.Lilmoo:BAAALgAECgYJDQAAAA==.Linkhunter:BAAALgAECgYJBgABLgAECgkJJQAgADwUAA==.Linni:BAAALgAECgYJDQAAAA==.Lizardwizard:BAAALgAECgQJBAAAAA==.',
Lo='Lodise:BAABLgAECn8dAAMJAAcJIQ8NDQAcAQAJAAcJIQ8NDQAcAQAKAAEJAAgZHQEyAAAAAA==.Lonful:BAAALgADCgEJAQAAAA==.Lorzz:BAACLgAFFH8FAAIVAAMJCg8LFQDEAAAVAAMJCg8LFQDEAAAuAAQKfzEAAhUACAncIjMEAAgDABUACAncIjMEAAgDAAAA.Lothe:BAAALgAECgYJDwAAAA==.',
Lu='Lucrio:BAABLgAECn8yAAIhAAkJWBAQOADZAQAhAAkJWBAQOADZAQAAAA==.Ludoe:BAAALgADCgkJMQAAAA==.Luna:BAAALgAECgUJDAAAAA==.Lunalai:BAABLgAECn84AAIDAAkJpCDrAQDrAgADAAkJpCDrAQDrAgAAAA==.Lushy:BAAALgAECgcJDQAAAA==.',
Ly='Lylineth:BAAALgADCgYJBgAAAA==.Lylinette:BAAALgAECgcJEgAAAA==.Lyssandra:BAAALgADCgUJBQAAAA==.',
['Lí']='Lízandor:BAACLgAFFH8QAAIHAAUJtAtNKgArAQAHAAUJtAtNKgArAQAuAAQKfykAAgcACQmwHNgXAHUCAAcACQmwHNgXAHUCAAAA.',
['Lû']='Lûsøn:BAAALgAECgEJAQAAAA==.',
Ma='Madruskee:BAABLgAECn8XAAIYAAYJ/xD/DQAVAQAYAAYJ/xD/DQAVAQAAAA==.Magahpt:BAAALgAECgMJBAAAAA==.Magdea:BAAALgADCgYJBgAAAA==.Mageofdeath:BAAALgAECgMJBAABLgAECgcJDAABAAAAAA==.Magistroll:BAABLgAECn8cAAICAAcJXgW9ogD8AAACAAcJXgW9ogD8AAAAAA==.Malevohaynk:BAAALgAECgQJBQABLgAECggJHQARABggAA==.Manerva:BAAALgADCgkJCQAAAA==.Maryshelley:BAAALgADCgMJAwAAAA==.Matoo:BAAALgADCgEJAQAAAA==.Maurin:BAAALgAECgYJBgAAAA==.Maximumhonk:BAABLgAECn8cAAIPAAYJKwybVAD5AAAPAAYJKwybVAD5AAAAAA==.',
Me='Melquisedec:BAAALgAECgIJAgAAAA==.Mendelia:BAABLgAECn8UAAIkAAYJZRRfFgAbAQAkAAYJZRRfFgAbAQAAAA==.Mercus:BAABLgAECn8VAAMmAAgJZhgiBgBqAQAmAAYJpBQiBgBqAQAfAAcJvRnMNQBhAQAAAA==.Merkstrasza:BAAALgAECgUJCwAAAA==.Mervenious:BAAALgAECgYJCAAAAA==.Meu:BAAALgAECggJBgAAAA==.',
Mi='Midasdh:BAACLgAFFH8OAAIZAAUJ0wsLMgAPAQAZAAUJ0wsLMgAPAQAuAAQKfxwAAxkACAmAF5Y+APoBABkACAnfFJY+APoBABoABgmOFwMwAE8BAAAA.Midasdk:BAACLgAFFH8NAAIhAAUJGBqVPAA+AQAhAAUJGBqVPAA+AQAuAAQKfxkAAyEABwnKHG9PAAQCACEABwm9GW9PAAQCABgAAwkvEkMVAKkAAAEuAAUUBQkOABkA0wsA.Midasmonk:BAAALgAECgEJAQABLgAFFAUJDgAZANMLAA==.Miladepollo:BAAALgADCgMJAwAAAA==.Mindblank:BAAALgAECgQJBAAAAA==.Mindplague:BAABLgAECn8WAAIUAAYJQh+2HACKAQAUAAYJQh+2HACKAQAAAA==.Minipincin:BAAALgAECgEJAQAAAA==.Minisicwidit:BAAALgADCgMJAwAAAA==.Mistdeeznuts:BAABLgAECn8YAAMGAAkJCwofKgBOAQAGAAkJCwofKgBOAQAQAAEJkgNihAAgAAAAAA==.',
Mo='Mogwaï:BAAALgAECgUJBgAAAA==.Mokokoma:BAAALgADCgQJBAAAAA==.Moonde:BAAALgAECgYJCwAAAA==.Moonscale:BAABLgAECn8oAAINAAkJeB42AQC8AgANAAkJeB42AQC8AgAAAA==.Moosayer:BAAALgAECgQJBgAAAA==.Mossed:BAAALgADCgMJAwAAAA==.',
Ms='Mskelsier:BAAALgAECgUJBQAAAA==.',
Mt='Mtaur:BAAALgADCggJDwAAAA==.',
Mu='Muclor:BAAALgADCgcJBwABLgAFFAMJAwABAAAAAA==.Mustang:BAAALgADCgcJCQAAAA==.',
My='Mythalis:BAAALgAECgQJBQAAAA==.',
['Mä']='Märändus:BAAALgADCgEJAQAAAA==.',
['Må']='Måzikeen:BAAALgADCgMJAwAAAA==.',
Na='Nardena:BAAALgADCggJCQAAAA==.Narse:BAAALgAFFAIJAgAAAA==.Narz:BAABLgAECn8mAAILAAgJ1hL3PwCMAQALAAgJ1hL3PwCMAQAAAA==.Nastianna:BAAALgAECgQJCgAAAA==.Natgeo:BAAALgAECggJCAABLgAECgkJJQAgADwUAA==.Nazumi:BAABLgAECn8gAAIQAAgJIxwDDAA2AgAQAAgJIxwDDAA2AgAAAA==.',
Nd='Ndiz:BAABLgAECn8VAAILAAcJIhwCJwAdAgALAAcJIhwCJwAdAgAAAA==.',
Ne='Necronomikon:BAAALgADCgEJAQAAAA==.Neeva:BAAALgADCgYJEAAAAA==.Nelrya:BAEALgADCgcJDQABLgAECggJKwAHABQgAA==.Neruphuyt:BAABLgAECn8gAAIFAAYJxxEzLgANAQAFAAYJxxEzLgANAQAAAA==.',
Ni='Niath:BAAALgAECgEJAgAAAA==.Nightsniper:BAAALgAECggJEwAAAA==.Ninfassins:BAAALgADCgIJAgAAAA==.',
No='Norintha:BAAALgADCgEJAQAAAA==.Norolen:BAAALgADCgIJAgAAAA==.',
Ny='Nyxiel:BAAALgAECgQJBQAAAA==.',
Oa='Oak:BAAALgAECgkJEAAAAA==.',
Oc='Occo:BAAALgADCgEJAQAAAA==.',
Og='Ogroc:BAAALgAECgQJBAAAAA==.',
Ok='Okioak:BAAALgAECgYJDgAAAA==.',
Ol='Olgon:BAACLgAFFH8FAAILAAMJMAIYRACtAAALAAMJMAIYRACtAAAuAAQKfywAAgsACAkXGUsnAPIBAAsACAkXGUsnAPIBAAAA.Olstinkyboot:BAAALgAECgEJAQAAAA==.',
On='Onehotdruid:BAAALgAECgcJDwABLgAFFAUJDgAZANMLAA==.',
Op='Oprhawinfury:BAABLgAECn8iAAIhAAkJQw7MRACtAQAhAAkJQw7MRACtAQAAAA==.',
Or='Orgodemir:BAAALgADCgkJDwAAAA==.',
Ot='Otemoto:BAAALgAECgEJAQAAAA==.',
Pa='Paigor:BAAALgAECgIJAgAAAA==.Pakswagger:BAABLgAECn8XAAMnAAYJFRc8DwCNAQAnAAYJFRc8DwCNAQAMAAMJRQQDWgBtAAAAAA==.Pallyberry:BAABLgAECn8xAAIIAAkJZhu6CAC6AgAIAAkJZhu6CAC6AgAAAA==.Pancake:BAAALgAECgEJAQAAAA==.Pandemonia:BAABLgAECn8zAAMiAAkJ5A0rFgCYAQAiAAgJHgwrFgCYAQAKAAkJJg1lTgBxAQAAAA==.Paprika:BAAALgADCgkJEAAAAA==.Parsie:BAAALgAECgcJCQAAAA==.Patch:BAAALgADCgYJBgAAAA==.Pathibas:BAAALgADCgEJAQABLgAECgkJOQATAHEkAA==.Pattycakes:BAABLgAECn8hAAIhAAgJmRbQSACgAQAhAAgJmRbQSACgAQAAAA==.',
Pe='Pencil:BAACLgAFFH8MAAIKAAQJIBoWIQBYAQAKAAQJIBoWIQBYAQAuAAQKfxsABAoACAkpHT4nAAICAAoACAkpHT4nAAICACIAAwniBj1dAFcAAAkAAQkAANAsAEUAAAAA.Pewpewlvltwo:BAACLgAFFH8FAAIOAAMJDQZyBwDPAAAOAAMJDQZyBwDPAAAuAAQKfyUAAg4ACAnQHssEAE4CAA4ACAnQHssEAE4CAAAA.Pewthree:BAAALgAECgYJCAABLgAFFAMJBQAOAA0GAA==.',
Ph='Pherocious:BAABLgAECn8VAAIcAAUJ6xO0EgDtAAAcAAUJ6xO0EgDtAAAAAA==.',
Pi='Pintsize:BAAALgADCgIJAgAAAA==.',
Pl='Plaguelis:BAAALgADCgEJAQABLgAECgkJMgAOAFEdAA==.Plexy:BAAALgAECgcJCgAAAA==.',
Po='Pobble:BAAALgADCgcJBwAAAA==.Pokitz:BAABLgAECn8fAAIHAAYJSg4gkAAGAQAHAAYJSg4gkAAGAQAAAA==.Poprock:BAAALgADCgIJAgAAAA==.Potus:BAAALgADCgQJBAAAAA==.',
Pr='Primordinor:BAABLgAECn8fAAMlAAgJyxybGADLAQAlAAgJyxybGADLAQAPAAYJrBq+KADCAQAAAA==.Probnotalive:BAABLgAECn8dAAILAAgJfxeKMwC8AQALAAgJfxeKMwC8AQAAAA==.Probnotferal:BAAALgADCgIJAgAAAA==.Probnoturmom:BAABLgAECn8bAAIVAAcJrR12GAAYAgAVAAcJrR12GAAYAgAAAA==.',
Ra='Raevyn:BAAALgAECgEJAQAAAA==.Rakan:BAABLgAECn84AAIoAAkJmRxeBACIAgAoAAkJmRxeBACIAgAAAA==.Rakasha:BAAALgADCgkJCQAAAA==.Rallick:BAACLgAFFH8FAAIIAAMJWg1xIQDHAAAIAAMJWg1xIQDHAAAuAAQKfy8AAggACAmvGvUNAGsCAAgACAmvGvUNAGsCAAAA.Ranì:BAABLgAECn81AAISAAkJ8BcBCgAJAgASAAkJ8BcBCgAJAgAAAA==.Rathger:BAAALgAECggJEgAAAA==.Ravenscythe:BAAALgADCgEJAQAAAA==.Raydor:BAAALgAECggJDgAAAA==.',
Re='Reb:BAABLgAECn8dAAIUAAkJnwSXKgAoAQAUAAkJnwSXKgAoAQAAAA==.Redic:BAAALgAECgMJAwAAAA==.Regis:BAAALgAECgYJBgABLgAECggJJQAGAE4cAA==.Rellix:BAAALgADCgUJBQAAAA==.Rendkick:BAAALgADCgcJBwAAAA==.Rendwee:BAABLgAECn8oAAIWAAkJsiDJAQDkAgAWAAkJsiDJAQDkAgAAAA==.Reuel:BAAALgAECgMJBAAAAA==.Rewolf:BAAALgAECgcJEAAAAA==.',
Rh='Rheemus:BAAALgADCgYJBgAAAA==.Rhul:BAAALgAECgUJCQAAAA==.',
Ri='Ricflairion:BAABLgAECn8aAAIMAAgJTAkLLwAkAQAMAAgJTAkLLwAkAQAAAA==.Rimuru:BAAALgAECgEJAQABLgAECgMJBwABAAAAAA==.',
Ro='Roadrunner:BAACLgAFFH8GAAILAAIJfgfCUwCMAAALAAIJfgfCUwCMAAAuAAQKfykAAgsACQmjDzcyAOcBAAsACQmjDzcyAOcBAAAA.Rodcet:BAABLgAECn88AAIHAAkJwSXAAQBkAwAHAAkJwSXAAQBkAwAAAA==.Roflcopterr:BAABLgAECn8kAAQIAAgJARf4FQAPAgAIAAgJARf4FQAPAgAHAAYJ9QfhoADpAAAkAAEJSAU6QgAZAAAAAA==.Rognan:BAAALgAECgIJAgAAAA==.Romina:BAAALgADCgEJBAAAAA==.Ronkin:BAAALgADCgkJCQAAAA==.Rookgue:BAABLgAECn8qAAIeAAgJthQiBgC+AQAeAAgJthQiBgC+AQAAAA==.Rookoker:BAABLgAECn8UAAINAAYJ5AY5DwDRAAANAAYJ5AY5DwDRAAAAAA==.Rootsafarian:BAAALgADCgcJBwAAAA==.Rossa:BAAALgADCgEJAQAAAA==.Rossdair:BAAALgAECgMJAwABLgADCgUJCQABAAAAAA==.Rossperot:BAABLgAECn8jAAIhAAkJjyCtDgC7AgAhAAkJjyCtDgC7AgAAAA==.Rothschild:BAAALgADCgEJAQAAAA==.Rottenfist:BAAALgAECgEJAQAAAA==.',
Sa='Sabako:BAAALgADCgcJCAAAAA==.Sacra:BAAALgADCgUJBQABLgAFFAMJBQAgAEUYAA==.Saelara:BAAALgADCgcJCgAAAA==.Saelis:BAAALgADCgQJBAAAAA==.Sakaru:BAABLgAECn8bAAICAAgJTw5AYwB3AQACAAgJTw5AYwB3AQABLgAECgkJJwAQADIQAA==.Salmoney:BAAALgAECgQJBAAAAA==.Salorin:BAAALgADCgYJCQAAAA==.Samgee:BAACLgAFFH8OAAIHAAQJbBLoJAA6AQAHAAQJbBLoJAA6AQAuAAQKfz4AAgcACQmuIGwRAAUDAAcACQmuIGwRAAUDAAAA.Sandormu:BAAALgADCgkJCQAAAA==.Saphas:BAAALgAECgMJAwAAAA==.Saynar:BAABLgAECn8yAAIZAAkJviIjBAAdAwAZAAkJviIjBAAdAwAAAA==.',
Sc='Scattered:BAABLgAECn8UAAQKAAgJtRB5iADrAAAKAAYJHQ55iADrAAAiAAMJHhRLQACzAAAJAAEJggvQJwAtAAAAAA==.Scooter:BAAALgAECgUJCgAAAA==.Scyx:BAAALgADCgEJAQAAAA==.',
Se='Seba:BAACLgAFFH8FAAICAAMJdQfVYwDRAAACAAMJdQfVYwDRAAAuAAQKfzIAAgIACAmBHd4lAEMCAAIACAmBHd4lAEMCAAAA.Selesne:BAAALgAECgYJDwAAAA==.Seraphicktwo:BAABLgAECn8cAAMVAAUJvhpgKgAsAQAVAAUJvhpgKgAsAQAUAAUJBRDjOADbAAAAAA==.Seriana:BAAALgAECggJEAAAAA==.Sermidas:BAACLgAFFH8KAAMoAAMJqRupEADoAAAoAAMJqRupEADoAAATAAIJ3AevGwCYAAAuAAQKfyIAAygACQk6H7gCAPACACgACQk6H7gCAPACABMABwnOFFw0ANgBAAEuAAUUBQkOABkA0wsA.',
Sh='Shadowcutter:BAAALgADCgkJDgABLgAECgcJDAABAAAAAA==.Shaggmz:BAAALgAECgYJEQAAAA==.Shinakuma:BAAALgAECgUJDQAAAA==.Shinma:BAAALgAECgYJEQAAAA==.Shrubbery:BAABLgAECn8VAAIKAAcJ+wPwlQDRAAAKAAcJ+wPwlQDRAAAAAA==.Shymary:BAAALgAECgYJEQAAAA==.',
Si='Siete:BAAALgAECgEJAQABLgAECgQJCQABAAAAAA==.Silvertip:BAAALgADCggJFQAAAA==.Silëx:BAABLgAECn8UAAICAAYJnxmHZAB0AQACAAYJnxmHZAB0AQAAAA==.Siouxiesioux:BAAALgADCgYJCgAAAA==.Siyona:BAAALgADCgkJDAAAAA==.',
Sk='Skits:BAAALgAECgIJAgAAAA==.Skyrah:BAAALgAECgYJBgAAAA==.Skyrie:BAAALgADCgQJBQAAAA==.',
Sl='Slagbröder:BAAALgADCgYJBgAAAA==.Slohine:BAAALgAECgUJBQAAAA==.Sludgecrush:BAAALgAECgYJCwAAAA==.Slugondeez:BAABLgAFFH8GAAIIAAIJ5hA2KgCFAAAIAAIJ5hA2KgCFAAAAAA==.',
Sm='Smallmike:BAAALgAECgIJAgAAAA==.Smitefist:BAAALgAECgIJAgAAAA==.Smokiee:BAAALgAECgYJEQAAAA==.',
Sn='Snailtrail:BAABLgAECn8VAAIdAAcJ4QRCFQCxAAAdAAcJ4QRCFQCxAAAAAA==.Snark:BAAALgAECgYJCQAAAA==.Snarkkin:BAAALgAECgQJDAAAAA==.Snowkim:BAABLgAECn8bAAIkAAgJmh2eBwALAgAkAAgJmh2eBwALAgAAAA==.Snuzzle:BAABLgAECn8oAAIDAAgJ3xtkCAACAgADAAgJ3xtkCAACAgAAAA==.',
So='Soniic:BAAALgAECgIJAgAAAA==.Soullessfros:BAABLgAECn8gAAIhAAkJzBCjOADXAQAhAAkJzBCjOADXAQAAAA==.Soullessman:BAAALgADCgQJCAAAAA==.Sourmash:BAAALgADCgkJCgAAAA==.',
Sp='Spaghet:BAABLgAECn8fAAIlAAkJNBnBEgAFAgAlAAkJNBnBEgAFAgAAAA==.Spillthetea:BAAALgAECgcJEAAAAA==.Sploot:BAAALgAECggJEAAAAA==.',
Sq='Squibbles:BAAALgAECgEJAQAAAA==.',
Sr='Srasjet:BAABLgAECn8dAAIPAAgJuxqvEQBuAgAPAAgJuxqvEQBuAgAAAA==.',
Ss='Ssimba:BAAALgAECgcJCwAAAA==.',
St='Stabytha:BAAALgAECgYJEgAAAA==.Stark:BAAALgADCgYJCgAAAA==.Starlight:BAAALgAECgEJAQAAAA==.Stealthed:BAAALgAECgUJBQAAAA==.Stender:BAAALgAECgMJAwABLgAFFAUJDQAaANwgAA==.Stormae:BAAALgADCgMJAgAAAA==.Stormcall:BAAALgAECgUJCgAAAA==.Stratusfied:BAAALgAECgMJBQAAAA==.',
Su='Susbandaid:BAAALgADCgYJBgAAAA==.',
Sw='Sweetiefox:BAAALgAECgkJDgAAAA==.Swiss:BAAALgAECgYJDwAAAA==.',
Sy='Syllai:BAAALgAECgYJBgAAAA==.Symboli:BAAALgADCgQJBAAAAA==.Syphus:BAAALgADCgQJBAAAAA==.',
['Sá']='Sáëgárón:BAABLgAECn8YAAMTAAgJMBO8IACcAQATAAgJMBO8IACcAQAoAAEJpwXWVgAmAAAAAA==.',
Ta='Tacyon:BAAALgADCggJDwAAAA==.Taliden:BAAALgAECgYJDAAAAA==.Tallera:BAAALgADCgEJAgAAAA==.Taniyah:BAAALgAECgQJCAAAAA==.Tankinstine:BAAALgADCgEJAgAAAA==.Taraylda:BAABLgAECn8XAAMgAAcJAxoMGgDIAQAgAAcJAxoMGgDIAQAUAAIJqgpaUQBjAAAAAA==.Tarful:BAAALgADCgQJBAAAAA==.Tarzand:BAAALgADCgEJAQABLgADCgcJDwABAAAAAA==.Tazo:BAABLgAECn8bAAIHAAcJFxCXbABKAQAHAAcJFxCXbABKAQAAAA==.',
Te='Tearek:BAABLgAECn8WAAIZAAcJVBybKADgAQAZAAcJVBybKADgAQAAAA==.Tecdor:BAAALgAECgQJBAAAAA==.Temla:BAABLgAECn8vAAILAAkJSBaCIQAPAgALAAkJSBaCIQAPAgAAAA==.Tenga:BAAALgAECgQJBAAAAA==.Teronfiggy:BAABLgAECn8cAAIhAAgJjA4DWAB1AQAhAAgJjA4DWAB1AQAAAA==.',
Tf='Tfirs:BAACLgAFFH8KAAIDAAQJVwzVCADcAAADAAQJVwzVCADcAAAuAAQKfy4AAgMACAm+GywHAEsCAAMACAm+GywHAEsCAAEuAAEKCQkSAAEAAAAA.',
Th='Thartilidan:BAAALgAECgYJEQABLgAECgcJDQABAAAAAA==.Theokoles:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Thepaladin:BAAALgADCgMJAwAAAA==.Thickblòód:BAAALgAFFAEJAQAAAA==.',
Ti='Tilythia:BAAALgADCgUJBQAAAA==.',
To='Tona:BAAALgADCgMJAwAAAA==.Toospookie:BAAALgADCgQJAgAAAA==.Tophu:BAAALgADCgcJBwAAAA==.Torkz:BAAALgADCgEJAgAAAA==.',
Tr='Tramplip:BAABLgAECn8fAAIiAAgJ5A+yCQBYAQAiAAgJ5A+yCQBYAQAAAA==.Treecloud:BAABLgAECn81AAIFAAkJXSTyAQAzAwAFAAkJXSTyAQAzAwAAAA==.Trevian:BAAALgAECgYJDwAAAA==.',
Tu='Tub:BAAALgAECgQJBAABLgAFFAQJDAAQAHwLAA==.Tuluxxi:BAABLgAECn86AAIPAAkJoiF3AgBiAwAPAAkJoiF3AgBiAwAAAA==.Turborunic:BAAALgADCgkJGwAAAA==.Turiae:BAACLgAFFH8JAAIMAAQJ9BUdFwA5AQAMAAQJ9BUdFwA5AQAuAAQKfygABAwACQnXHycFANwCAAwACQnKHycFANwCAA0ABwnZFsgQANEBACcABQkhCaQ0AMgAAAAA.Tuskerz:BAAALgAECgEJAgAAAA==.Tusobrinna:BAAALgAECgUJBgAAAA==.Tutter:BAAALgADCgIJAgAAAA==.Tuuldd:BAAALgADCggJCAAAAA==.',
Tw='Twunk:BAAALgAECggJEAAAAA==.',
Ty='Typhlotic:BAAALgADCgMJAwAAAA==.Tyrennius:BAAALgAECgQJBAAAAA==.Tyrianis:BAABLgAECn8rAAMfAAkJNyGZBACvAgAfAAkJSSCZBACvAgAeAAMJzh6rEwDFAAAAAA==.',
Tz='Tzxdh:BAAALgAECgUJBQAAAA==.',
Ug='Uglymancer:BAAALgAECgYJDwAAAA==.',
Uj='Ujimas:BAAALgAECgUJEAAAAA==.',
Un='Unchartedd:BAAALgADCgEJAQAAAA==.',
Va='Vaenira:BAAALgADCgUJBgAAAA==.Valdara:BAAALgADCgkJEgAAAA==.Valemon:BAAALgAECgIJAgAAAA==.Vampireshade:BAABLgAECn8oAAImAAgJNQh1CQA4AQAmAAgJNQh1CQA4AQAAAA==.Vanimao:BAABLgAECn8oAAQEAAkJtg+tPACxAQAEAAgJqRCtPACxAQADAAcJrwzyGQD/AAAFAAEJ1AYIcwAlAAAAAA==.Vankman:BAAALgADCgcJBwAAAA==.Vannaka:BAAALgADCgEJAQAAAA==.',
Vb='Vbull:BAAALgAECgEJAQAAAA==.',
Ve='Vedrolan:BAAALgADCgUJDgABLgAFFAIJBgARAGQNAA==.Velifya:BAAALgADCgMJAwAAAA==.Velindon:BAAALgADCgYJBgAAAA==.Velissari:BAAALgAECgYJDQAAAA==.Velonar:BAAALgADCgEJAQAAAA==.Velouria:BAABLgAECn86AAQDAAkJoSItAQAbAwADAAkJaiItAQAbAwAFAAgJ5h8SDQDIAgAEAAIJ9QSXwABGAAAAAA==.Venatra:BAAALgAECgMJAwAAAA==.Verudora:BAAALgADCgcJBwAAAA==.Vexira:BAAALgADCgcJBwAAAA==.',
Vi='Violet:BAABLgAECn8gAAInAAgJJBclCAAoAgAnAAgJJBclCAAoAgAAAA==.Violette:BAABLgAECn8fAAILAAcJVA5sUwBOAQALAAcJVA5sUwBOAQAAAA==.Visix:BAAALgADCgMJAwAAAA==.',
Vo='Voidchacha:BAAALgADCgEJAQAAAA==.Voidlink:BAABLgAECn8lAAIgAAkJPBTIEAANAgAgAAkJPBTIEAANAgAAAA==.Voidmistress:BAABLgAECn8nAAICAAcJGRjYTwCqAQACAAcJGRjYTwCqAQAAAA==.Voidpup:BAABLgAECn8oAAIZAAcJYhz6KgDUAQAZAAcJYhz6KgDUAQAAAA==.Volgrimm:BAABLgAECn8bAAIRAAgJKwuTJwA2AQARAAgJKwuTJwA2AQAAAA==.Volitaire:BAAALgADCgYJBgAAAA==.',
Vy='Vynethan:BAAALgAECgEJAgAAAA==.',
['Vé']='Véngence:BAAALgAECgcJDwAAAA==.',
['Vê']='Vêx:BAAALgADCgYJBgAAAA==.',
Wa='Wabalabalosh:BAAALgADCgkJCQAAAA==.Wabgucci:BAAALgADCgUJBQAAAA==.Wabwum:BAAALgAECgMJAwAAAA==.Wakaekwondo:BAAALgAECgEJAQAAAA==.Wakarisma:BAAALgAECgEJAQAAAA==.Wanda:BAAALgAECgkJCwAAAA==.Wangao:BAABLgAFFH8GAAIRAAIJZA1ENwCCAAARAAIJZA1ENwCCAAAAAA==.Warbluster:BAAALgADCgIJAgAAAA==.Warchylde:BAAALgADCgkJEAAAAA==.Warolderoy:BAABLgAECn85AAITAAkJcSQlAgAmAwATAAkJcSQlAgAmAwAAAA==.',
We='Weedshaman:BAAALgAECgEJAwAAAA==.Weedwax:BAAALgAECgQJBAAAAA==.Weil:BAAALgADCgIJAgAAAA==.',
Wh='Whiinuss:BAABLgAECn8UAAIHAAcJlw25fwB7AQAHAAcJlw25fwB7AQAAAA==.Whytrabbit:BAAALgAECgIJAgAAAA==.',
Wi='Wigglesdeath:BAAALgADCgQJBAAAAA==.',
Wl='Wldeagle:BAAALgAECgQJBAAAAA==.',
Wo='Woker:BAAALgAECgEJAQABLgAECgkJMgAOAFEdAA==.Woodpig:BAABLgAECn8uAAQEAAkJ2SGJAwBcAwAEAAkJ2SGJAwBcAwADAAIJVBNCLgBsAAAFAAIJXgYyawAtAAAAAA==.Woogie:BAAALgAECgQJCwAAAA==.',
Wr='Wrangle:BAAALgADCgEJAQAAAA==.',
Wy='Wyldshade:BAAALgADCgYJCAAAAA==.Wyrm:BAAALgAECgUJBQABLgAECgUJCgABAAAAAA==.',
Xa='Xaladin:BAAALgAECgYJDgAAAA==.Xathas:BAAALgAECgQJBAAAAA==.',
Xe='Xenna:BAAALgAECgQJBAAAAA==.Xeq:BAAALgADCgMJAwAAAA==.',
Xi='Xiata:BAAALgAECgYJBgAAAA==.Xiu:BAAALgAECgMJAwAAAA==.',
Xr='Xrp:BAAALgADCgIJAwAAAA==.',
Ye='Yeoman:BAABLgAECn8UAAITAAYJEhL7NQAgAQATAAYJEhL7NQAgAQAAAA==.',
Yg='Yggdralith:BAAALgAECgkJHAAAAQ==.',
Yo='Yourdeath:BAAALgAECgkJBAAAAA==.',
Yu='Yunosmall:BAAALgADCgIJAgAAAA==.Yunosmart:BAAALgAECgMJBAAAAA==.',
Za='Zaen:BAACLgAFFH8FAAIKAAMJFQmwVgDQAAAKAAMJFQmwVgDQAAAuAAQKfzEAAwoACAkSH/kZAE0CAAoACAkSH/kZAE0CACIAAwnUC7NDAKYAAAAA.Zagreus:BAAALgADCgcJCAAAAA==.Zarkir:BAACLgAFFH8FAAMYAAMJmBaOBwD5AAAYAAMJmBaOBwD5AAAhAAIJGA0LkACaAAAuAAQKfx8ABBgACAneIrgDADECABgABwl5IbgDADECACEABwnAITwqABACABcABwmtF5oZAIcBAAEuAAQKBgkXAAIApyIA.Zarkìr:BAABLgAECn8XAAICAAYJpyKQZwAIAgACAAYJpyKQZwAIAgAAAA==.Zaues:BAAALgAECgMJBAAAAA==.',
Ze='Zelily:BAAALgAECggJDwAAAA==.Zenarri:BAAALgADCgYJBwAAAA==.Zepha:BAAALgAECgYJCwAAAA==.',
Zl='Zlyandien:BAAALgADCggJDwABLgAECgcJFwAgAAMaAA==.',
Zo='Zornov:BAABLgAECn8jAAMkAAgJkh6aBgAoAgAkAAgJkh6aBgAoAgAIAAMJJggHWQBzAAAAAA==.',
Zu='Zulrich:BAAALgADCgYJBgAAAA==.',
Zv='Zvirax:BAAALgADCgkJCQAAAA==.',
['Ëu']='Ëuni:BAAALgAECgYJEQAAAA==.',
['Ðe']='Ðemôns:BAAALgAECgEJAQAAAA==.',
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
