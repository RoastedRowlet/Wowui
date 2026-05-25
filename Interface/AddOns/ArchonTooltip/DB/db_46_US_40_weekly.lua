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

local lookup = {'Unknown-Unknown','Mage-Frost','Druid-Guardian','Druid-Restoration','Druid-Balance','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Rogue-Subtlety','Rogue-Assassination','Monk-Windwalker','Warlock-Affliction','Warlock-Demonology','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','DeathKnight-Unholy','Shaman-Restoration','Rogue-Outlaw','Monk-Brewmaster','Warrior-Protection','DemonHunter-Devourer','Evoker-Preservation','Warrior-Fury','Priest-Shadow','Priest-Holy','Druid-Feral','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Havoc','Hunter-Survival','Hunter-Marksmanship','DemonHunter-Vengeance','Priest-Discipline','Paladin-Protection','Warlock-Destruction','Mage-Arcane','Shaman-Elemental','Warrior-Arms',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abarlton:BAAALgAFFAEJAQABLgAECgcJDAABAAAAAA==.',
Ad='Adabeam:BAAALgADCgcJCwAAAA==.Adagio:BAABLgAECn81AAICAAkJOxurMAA4AgACAAkJOxurMAA4AgAAAA==.Adetalo:BAABLgAECn8kAAIDAAkJ8RdUCgAFAgADAAkJ8RdUCgAFAgAAAA==.Adiara:BAAALgAECgMJAwAAAA==.Aditu:BAABLgAECn8ZAAMEAAcJSBttIAAgAgAEAAcJSBttIAAgAgAFAAQJxA1lTwCfAAAAAA==.',
Ae='Aelis:BAAALgADCgcJCAAAAA==.Aemulo:BAAALgAECgUJBwAAAA==.Aerith:BAAALgADCgcJBwAAAA==.',
Ag='Agasonex:BAAALgADCgMJAwAAAA==.',
Ai='Airent:BAAALgAECgUJDAAAAA==.Aiyana:BAAALgAECgYJDgAAAA==.',
Ak='Akiirii:BAAALgAECgEJAQAAAA==.',
Al='Alaestel:BAAALgAECgQJBwAAAA==.Aldo:BAAALgAECgEJAQAAAA==.Alkaraho:BAAALgAECgMJAwAAAA==.Alleyways:BAACLgAFFH8GAAIGAAMJ1iXQFgBJAQAGAAMJ1iXQFgBJAQAuAAQKfzsAAgYACQn3JeYAAM0DAAYACQn3JeYAAM0DAAAA.Alzey:BAABLgAECn8iAAIHAAgJJA/5bAB0AQAHAAgJJA/5bAB0AQAAAA==.',
Am='Ambeon:BAAALgADCgUJBQAAAA==.Ammathindis:BAAALgADCgcJCQAAAA==.Ammutseba:BAAALgADCggJCAAAAA==.Amplers:BAAALgADCgUJBwAAAA==.',
An='Angelbane:BAAALgADCgQJBAAAAA==.Angina:BAAALgAECgIJAwAAAA==.Annarcis:BAAALgAECgUJCwAAAA==.Anotherdk:BAAALgAECgYJBgABLgAECggJIQAIADsiAA==.Anthiell:BAAALgADCgEJAQAAAA==.Antiman:BAABLgAECn8mAAIHAAgJVAnhgABMAQAHAAgJVAnhgABMAQAAAA==.',
Ap='Aplcyder:BAABLgAECn84AAIEAAkJVwzePQB5AQAEAAkJVwzePQB5AQAAAA==.',
Ar='Arachnid:BAABLgAECn8xAAICAAcJsiRFMQCtAgACAAcJsiRFMQCtAgAAAA==.Aragorn:BAAALgADCgkJDQAAAA==.Aratyn:BAABLgAECn8WAAICAAcJ3w6jigBGAQACAAcJ3w6jigBGAQAAAA==.Army:BAAALgAECgIJAgAAAA==.',
As='Asanot:BAAALgADCgMJAwAAAA==.',
At='Ati:BAAALgADCgIJAgAAAA==.',
Au='Audxo:BAAALgADCgMJAwAAAA==.',
Ay='Ayayron:BAAALgADCgQJBAAAAA==.',
Ba='Backhawk:BAAALgADCgcJEAAAAA==.Backsurgery:BAABLgAFFH8GAAMJAAUJ4xg5EQBSAQAJAAQJ4xg5EQBSAQAKAAEJAAAZEAAAAAAAAA==.Baerrn:BAAALgAECgYJEwAAAA==.Bamboo:BAAALgAECgYJCQABLgAFFAMJCgALAIAZAA==.Baricia:BAABLgAECn8aAAICAAkJWApdXwClAQACAAkJWApdXwClAQAAAA==.Barix:BAAALgAECgEJAwAAAA==.Barnd:BAAALgADCggJDwAAAA==.Barrin:BAABLgAECn8wAAMMAAgJMBztAwA0AgAMAAgJMBztAwA0AgANAAUJQgjSoQDlAAAAAA==.Bastim:BAAALgAECgMJCAAAAA==.Baussassbich:BAAALgAECgQJBAABLgAECgkJJAANAE4hAA==.Bawnchu:BAAALgAECgMJCAAAAA==.',
Be='Beastmaster:BAACLgAFFH8FAAIOAAMJvSDQMwAVAQAOAAMJvSDQMwAVAQAuAAQKfy8AAg4ACAmYJGQNAMECAA4ACAmYJGQNAMECAAAA.Beefcakell:BAAALgADCgcJDQAAAA==.Beiki:BAAALgAECgYJDwAAAA==.Belthar:BAAALgAECgQJCQAAAA==.Bently:BAABLgAECn8iAAMPAAcJpSEfGwDcAQAPAAcJ9R8fGwDcAQAQAAUJGCMtEwCvAQAAAA==.Berexis:BAAALgAECggJDwAAAA==.',
Bi='Bissafiyah:BAACLgAFFH8XAAIRAAYJBCXtAADbAQARAAYJBCXtAADbAQAuAAQKf0kAAhEACQm7JiIAAOkDABEACQm7JiIAAOkDAAAA.Biznasty:BAAALgAECgEJAwAAAA==.',
Bl='Bloodgon:BAABLgAFFH8HAAISAAMJUhiBZAACAQASAAMJUhiBZAACAQAAAA==.Bluetuesday:BAAALgAECgMJBAAAAA==.',
Bo='Bohica:BAABLgAECn84AAITAAkJRhGvMQC9AQATAAkJRhGvMQC9AQAAAA==.Bonechop:BAAALgAECgEJAQAAAA==.Bootymeat:BAAALgADCgEJAQAAAA==.Bowtox:BAAALgAECgEJAQAAAA==.Boyakasha:BAABLgAECn8WAAIUAAYJeQl6DwDgAAAUAAYJeQl6DwDgAAAAAA==.',
Br='Brewfu:BAAALgADCgIJAgAAAA==.Brewpub:BAAALgADCgQJBAAAAA==.Brewsome:BAABLgAECn9BAAQLAAkJQyFdBADzAgALAAkJQyFdBADzAgAVAAkJ1RgbDwArAgAGAAEJ0xH2gwA4AAAAAA==.Bruceprime:BAAALgAECgkJAQAAAA==.Bryybryy:BAAALgAECgUJBQABLgAECggJIwAVAOQaAA==.Bryycelest:BAABLgAECn8jAAIVAAgJ5BqYEwD2AQAVAAgJ5BqYEwD2AQAAAA==.Brz:BAAALgADCgcJBwAAAA==.Brådòn:BAAALgAECgYJDQAAAA==.',
Bu='Bucket:BAABLgAECn8oAAIWAAkJZxW9DAD4AQAWAAkJZxW9DAD4AQAAAA==.Bunkiee:BAAALgADCgkJHQAAAA==.Bunnybane:BAAALgAECgYJEAAAAA==.Burny:BAABLgAECn8aAAICAAcJVCVMJgDZAgACAAcJVCVMJgDZAgAAAA==.Buttadogg:BAAALgAECgcJDwAAAA==.',
['Bë']='Bëckey:BAAALgADCgIJAgAAAA==.',
Ca='Calyx:BAABLgAECn8XAAIXAAYJjgbcnwC3AAAXAAYJjgbcnwC3AAAAAA==.Canadani:BAAALgAECgcJDQAAAA==.Candorite:BAABLgAECn8VAAMPAAcJRgrnTQDLAAAPAAYJVgjnTQDLAAAYAAEJ7gvJNAAyAAAAAA==.Caphriel:BAABLgAECn8dAAIZAAkJQB1lEQBIAgAZAAkJQB1lEQBIAgAAAA==.Capita:BAABLgAECn8cAAICAAgJjAmOiABKAQACAAgJjAmOiABKAQAAAA==.Carsinegan:BAAALgADCgUJCwAAAA==.Cassica:BAABLgAECn8dAAMaAAcJbhn6LQBAAQAaAAcJbhn6LQBAAQAbAAIJ1gm1VwBQAAAAAA==.Catchdezhanz:BAAALgADCgcJBwABLgAECgYJIQAIAJ0UAA==.Catskin:BAABLgAECn8hAAMcAAgJUBsoCgDqAQAcAAYJYiIoCgDqAQAEAAYJ8hvdNQCfAQAAAA==.',
Ce='Celivalasha:BAAALgADCgUJBQAAAA==.Cell:BAABLgAECn8jAAIVAAgJTSQqBQA3AwAVAAgJTSQqBQA3AwAAAA==.Cet:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.',
Ch='Chadvader:BAAALgADCgIJAgAAAA==.Chainlink:BAAALgADCgYJBgAAAA==.Chalee:BAAALgAECgEJAQAAAA==.Chandraskhar:BAAALgADCgIJAgAAAA==.Chanpagne:BAAALgADCgUJBQAAAA==.Charkle:BAAALgAECgYJDAAAAA==.Chayea:BAAALgADCgEJAQAAAA==.Chillylilly:BAABLgAECn8vAAMdAAkJbSV3AQA5AwAdAAkJbSV3AQA5AwAeAAQJ4RwADgBIAQAAAA==.Chlorophyll:BAAALgAECgQJBAAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chummie:BAABLgAECn8uAAMNAAkJrh/vEgCfAgANAAkJRR/vEgCfAgAMAAYJdxxDCADHAQAAAA==.',
Ci='Cielcin:BAAALgAFFAMJAwAAAA==.Ciremiih:BAAALgAECgEJAQAAAA==.Citymage:BAACLgAFFH8GAAICAAQJPASxXwD3AAACAAQJPASxXwD3AAAuAAQKfykAAgIACQmbF9s5ABYCAAIACQmbF9s5ABYCAAAA.Cixelsyd:BAAALgADCgYJCwABLgAFFAUJDAAHAEQEAA==.',
Cl='Clamchowda:BAABLgAECn8vAAMXAAkJoBvWHwA4AgAXAAkJKxnWHwA4AgAfAAUJUh5wIwCiAQAAAA==.',
Co='Codê:BAABLgAECn8mAAINAAgJyRe+NADtAQANAAgJyRe+NADtAQAAAA==.Coffeecup:BAAALgADCgIJAgAAAA==.Corride:BAABLgAECn8rAAIgAAgJgR85DQA3AgAgAAgJgR85DQA3AgAAAA==.Corspar:BAAALgAECgQJBgAAAA==.',
Cr='Crazyeyes:BAAALgADCgMJAwAAAA==.Crimsondeath:BAABLgAECn8XAAIdAAYJOQ6LKgDUAAAdAAYJOQ6LKgDUAAAAAA==.Crutch:BAABLgAECn8eAAMTAAgJBh6UDQDBAgATAAgJBh6UDQDBAgARAAUJJhTEFgARAQAAAA==.Crystanikus:BAAALgAECgQJBQAAAA==.',
Cu='Cuckenjoyer:BAAALgAECgYJCgAAAA==.',
Cy='Cyclonian:BAAALgAECgEJAgABLgAECgQJBQABAAAAAA==.Cyprus:BAAALgAECgEJAQAAAA==.',
Da='Daddytrump:BAABLgAECn8WAAIGAAcJWA4+OAA7AQAGAAcJWA4+OAA7AQAAAA==.Daelric:BAAALgADCgIJAwAAAA==.Daender:BAABLgAECn8sAAMOAAkJWSSTBwAAAwAOAAkJWSSTBwAAAwAhAAEJghgsMgA2AAAAAA==.Daenor:BAAALgAECgQJBQAAAA==.Dairydemon:BAABLgAECn8yAAIiAAgJ0w+vDABeAQAiAAgJ0w+vDABeAQAAAA==.Damageus:BAACLgAFFH8IAAICAAMJfhylXAABAQACAAMJfhylXAABAQAuAAQKfx4AAgIACAnqIjkkAOICAAIACAnqIjkkAOICAAAA.Daniryl:BAEBLgAECn8bAAIEAAgJfxVAJwD0AQAEAAgJfxVAJwD0AQAAAA==.Dar:BAAALgAECgQJCAAAAA==.Darcness:BAABLgAECn8hAAMKAAYJ2BOwDQAtAQAJAAUJTxZQOABSAQAKAAYJLRGwDQAtAQAAAA==.Darcside:BAABLgAECn8UAAIaAAYJuQX0RQDLAAAaAAYJuQX0RQDLAAAAAA==.Darkclouds:BAAALgADCgIJAgAAAA==.Darksoul:BAAALgAECggJEgABLgAECggJGQAjACIYAA==.Darkxwraith:BAABLgAECn8UAAIIAAcJzxfGIADXAQAIAAcJzxfGIADXAQAAAA==.Dashtoolite:BAABLgAECn8YAAIXAAgJ0gtXYQBBAQAXAAgJ0gtXYQBBAQAAAA==.Datsumbeech:BAABLgAECn8cAAIeAAcJTAmDEwD+AAAeAAcJTAmDEwD+AAAAAA==.',
De='Deajer:BAAALgADCgYJBwAAAA==.Deathsabeach:BAAALgAECgEJAQAAAA==.Deathvìxen:BAABLgAECn8WAAMaAAcJMgj7OAAIAQAaAAcJMgj7OAAIAQAjAAMJiwbrVwBUAAAAAA==.Debit:BAAALgAECgcJEwAAAA==.Demonhunter:BAACLgAFFH8KAAIXAAQJkiGpJgBMAQAXAAQJkiGpJgBMAQAuAAQKfx0AAhcACAk/JKkKAC4DABcACAk/JKkKAC4DAAAA.Demonwoogie:BAAALgADCgYJBgABLgAECgQJCwABAAAAAA==.Dendrophilia:BAAALgAECgQJBQAAAA==.Densamin:BAABLgAECn8mAAQHAAgJNRVPVACuAQAHAAgJNRVPVACuAQAIAAIJugHqdgA9AAAkAAEJ4wuNRQApAAAAAA==.Deviyn:BAAALgADCgIJAgAAAA==.Devra:BAAALgADCggJCAAAAA==.Deàdly:BAAALgAECgYJEAAAAA==.',
Di='Dietchrist:BAAALgAECggJEwAAAA==.Dilligaf:BAAALgADCggJCAAAAA==.',
Dk='Dkanabiss:BAAALgAECgMJBAAAAA==.Dkinabox:BAAALgADCgEJAgAAAA==.',
Do='Docbaba:BAAALgAECgUJBAAAAA==.Doist:BAAALgAECgIJAgAAAA==.Donngaz:BAAALgAECgMJBgAAAA==.',
Dr='Dreadgnar:BAAALgAECgEJAQAAAA==.Drewnei:BAAALgADCgkJCQAAAA==.Drewserk:BAABLgAECn8pAAIZAAkJKxyxDwBaAgAZAAkJKxyxDwBaAgAAAA==.Drkxmaniac:BAAALgAECgUJCgABLgAECgcJDAABAAAAAA==.Drminnowphd:BAAALgAFFAEJAQAAAA==.Drpiscisphd:BAACLgAFFH8IAAMSAAQJ0RQgVwAgAQASAAQJ0RQgVwAgAQAdAAEJdAXuMQArAAAuAAQKfy4AAxIACQm2IO4OACQDABIACQm2IO4OACQDAB0ABwnDBYIpAPMAAAAA.Drsaltyballz:BAABLgAECn8uAAIKAAkJyiL5AAAAAwAKAAkJyiL5AAAAAwAAAA==.Drugpala:BAAALgAECgIJAgAAAA==.Druji:BAAALgAECgYJBgAAAA==.Drumuss:BAAALgADCgEJAQAAAA==.',
Du='Ducat:BAAALgAECgUJEgAAAA==.Dudesk:BAAALgAECgUJBgAAAA==.Duffuna:BAAALgADCgEJAQABLgAECgkJQwAgANglAA==.Duffunha:BAABLgAECn9DAAIgAAkJ2CWHAABwAwAgAAkJ2CWHAABwAwAAAA==.',
Dy='Dye:BAABLgAECn8tAAIIAAkJxR3DBwDrAgAIAAkJxR3DBwDrAgAAAA==.Dyre:BAABLgAECn8lAAIiAAgJjw33DgAzAQAiAAgJjw33DgAzAQAAAA==.Dyslexic:BAABLgAECn8lAAIlAAgJKxdLBgDMAQAlAAgJKxdLBgDMAQABLgAFFAUJDAAHAEQEAA==.Dyspepsia:BAACLgAFFH8MAAIHAAUJRAQQEQAdAQAHAAUJRAQQEQAdAQAuAAQKfxsAAgcACQn7FQo2AEoCAAcACQn7FQo2AEoCAAAA.',
['Dô']='Dôngus:BAAALgADCgMJAwABLgAECgQJBQABAAAAAA==.',
['Dõ']='Dõngus:BAAALgAECgEJAQABLgAECgQJBQABAAAAAA==.',
['Dö']='Döngus:BAAALgAECgEJAgABLgAECgQJBQABAAAAAA==.',
Ed='Edie:BAAALgAECgEJAgAAAA==.',
Ei='Eirenn:BAAALgAECgkJBgAAAA==.',
El='Elayna:BAAALgAECgkJBwAAAA==.Elenaura:BAAALgAECgMJAwAAAA==.Eleren:BAABLgAECn8YAAIXAAcJXxGpaQArAQAXAAcJXxGpaQArAQAAAA==.Elimee:BAABLgAECn8wAAICAAkJoCFJDgBUAwACAAkJoCFJDgBUAwAAAA==.Elisestraza:BAAALgAFFAMJBAABLgAECgkJMAACAKAhAA==.Ellasia:BAAALgAECgYJDQAAAA==.Elric:BAABLgAECn81AAIHAAkJTBnxKAA9AgAHAAkJTBnxKAA9AgAAAA==.Elsie:BAAALgAECgcJCwABLgAECggJGQAIAM0cAA==.Elunea:BAAALgADCgcJDQAAAA==.Elunemittens:BAAALgADCgYJBgAAAA==.',
Em='Emart:BAABLgAECn8jAAIgAAgJqw1zHgCKAQAgAAgJqw1zHgCKAQAAAA==.Emozella:BAAALgAECgEJAQAAAA==.',
En='Enatresh:BAAALgAECgcJEAAAAA==.',
Ep='Epsilon:BAAALgAECgkJCQAAAA==.',
Er='Erayna:BAABLgAECn8xAAIEAAkJ8BIeIwAOAgAEAAkJ8BIeIwAOAgAAAA==.Ereillea:BAAALgAECgYJDQAAAA==.',
Es='Essence:BAABLgAECn8WAAMCAAgJmxTpagAAAgACAAgJDBHpagAAAgAmAAQJ1xocDAARAQAAAA==.',
Et='Etherious:BAAALgAECgcJCAABLgAECggJGQAIAM0cAA==.',
Eu='Euko:BAABLgAECn81AAMFAAkJLyFyBgDQAgAFAAkJLyFyBgDQAgAEAAgJdRU3XAACAQAAAA==.',
Ev='Evedk:BAAALgAECgkJBQAAAA==.Evepriest:BAAALgADCgMJAQAAAA==.',
Fa='Failrogue:BAAALgADCgUJCwAAAA==.Falconclaw:BAAALgADCgkJGQAAAA==.Falkensnoman:BAABLgAECn8mAAIdAAgJgBSeFgCDAQAdAAgJgBSeFgCDAQAAAA==.Fayedra:BAABLgAECn8WAAIDAAcJ+xV9EwCAAQADAAcJ+xV9EwCAAQAAAA==.',
Fc='Fcawfe:BAAALgAECgMJAwABLgAECgYJEAABAAAAAA==.',
Fe='Febee:BAAALgADCgcJAQAAAA==.Feenii:BAABLgAECn84AAIRAAkJUh0HBACRAgARAAkJUh0HBACRAgAAAA==.Felburst:BAAALgAECgMJAwAAAA==.Felfireqt:BAAALgAECgEJAgAAAA==.Feydros:BAAALgAECgkJBQAAAA==.',
Fi='Figgyandrii:BAAALgADCgcJBwAAAA==.Fionar:BAAALgADCgIJAgAAAA==.Fizzlelich:BAAALgADCgkJFgAAAA==.',
Fl='Flamesters:BAAALgAFFAEJAQAAAA==.Fluffpuff:BAAALgADCgMJAwAAAA==.',
Fo='Foxdeer:BAABLgAECn8WAAMMAAcJQgOhHwB0AAANAAcJKAOcvwCvAAAMAAMJ4wKhHwB0AAAAAA==.',
Fr='Frenchtoast:BAAALgAECgUJBwAAAA==.',
Fu='Furyrage:BAAALgADCgEJAQAAAA==.Fuzzyclawz:BAAALgADCgMJAwABLgAECgkJLAALADMQAA==.',
Ga='Gambachii:BAAALgAECgcJDQAAAA==.Gankss:BAABLgAECn8hAAMIAAgJOyIGBwD5AgAIAAgJOyIGBwD5AgAHAAEJNAHSiAEMAAAAAA==.Garakddon:BAAALgADCgkJFgABLgAECgcJGwAkADkUAA==.Garryy:BAAALgAECgMJBwAAAA==.',
Ge='Geegandolm:BAAALgADCgkJEwAAAA==.Genjaru:BAAALgAECgYJCgAAAA==.Genndalf:BAAALgADCgcJBwAAAA==.Geostorm:BAAALgAECgEJAQAAAA==.',
Gh='Gharmag:BAAALgAECgEJAQAAAA==.',
Gi='Giramar:BAABLgAECn8lAAMaAAgJmBgfGADiAQAaAAgJmBgfGADiAQAbAAYJjxDBMAAlAQAAAA==.',
Gl='Glagkara:BAAALgAECgIJAgAAAA==.',
Go='Gobbyshamm:BAAALgAECgEJAQAAAA==.Gobsmackers:BAAALgAECgYJBwAAAA==.Gomklin:BAAALgADCgcJCAABLgAFFAIJBQAHAMUdAA==.Goobtastic:BAAALgADCgQJBAAAAA==.Goteem:BAAALgAECggJEwAAAA==.Gothitelle:BAAALgAECgEJAgAAAA==.',
Gr='Griffhud:BAAALgAECgYJEwAAAA==.Grimrox:BAABLgAECn8iAAInAAgJ2BLHJACVAQAnAAgJ2BLHJACVAQAAAA==.Grixx:BAAALgADCgUJBQAAAA==.Groupie:BAAALgADCgUJCgABLgAECgcJGAAhANUPAA==.',
Gt='Gtatedk:BAAALgAECgEJAQAAAA==.',
Gu='Guntera:BAAALgAECgYJDgAAAA==.Guts:BAAALgADCgMJAwAAAA==.',
Gw='Gwendalyn:BAAALgAECgQJBQAAAA==.',
['Gä']='Gäz:BAAALgADCgEJAQAAAA==.',
Ha='Halexion:BAAALgADCgIJAgAAAA==.Haomaru:BAABLgAECn8WAAMEAAUJLBliQgBkAQAEAAUJLBliQgBkAQAFAAEJSAvOfgAoAAAAAA==.Hardcandy:BAABLgAECn8YAAIhAAcJ1Q+zFADyAAAhAAcJ1Q+zFADyAAAAAA==.Hardlyevoker:BAAALgADCgEJAQABLgAFFAIJBgAIAOYQAA==.Hawkìns:BAAALgAECgEJAQAAAA==.',
He='Heartsoul:BAAALgAECgYJCQAAAA==.Heavyarm:BAAALgADCgcJDwAAAA==.Hellork:BAAALgADCgQJBAAAAA==.Hermosura:BAAALgADCgUJCQAAAA==.Hex:BAAALgAECgYJBgAAAA==.',
Hi='Hiccups:BAAALgAECgMJBAABLgAECggJDwABAAAAAA==.Himawarí:BAABLgAECn8WAAIWAAcJPRGWGwAxAQAWAAcJPRGWGwAxAQAAAA==.Hiyank:BAABLgAECn8iAAIVAAgJNSOUCgBtAgAVAAgJNSOUCgBtAgAAAA==.',
Ho='Hoffmin:BAABLgAECn8UAAMXAAcJnRmaWwBRAQAXAAYJnRmaWwBRAQAfAAIJphK0VgCMAAAAAA==.Holemeister:BAACLgAFFH8IAAIHAAMJnCPYKwA4AQAHAAMJnCPYKwA4AQAuAAQKfy8AAgcACAmhJOINAB8DAAcACAmhJOINAB8DAAAA.Holyfresh:BAAALgADCgEJAQAAAA==.Holymann:BAABLgAECn8jAAIaAAcJRQ2uOwD6AAAaAAcJRQ2uOwD6AAAAAA==.Holyschnikey:BAABLgAECn8hAAIIAAYJnRQXNgBOAQAIAAYJnRQXNgBOAQAAAA==.Holyz:BAABLgAECn8uAAMIAAgJ4CIlBgAMAwAIAAgJ4CIlBgAMAwAHAAEJBhnzMwFMAAAAAA==.Horgable:BAAALgADCgIJAgAAAA==.Horrorpops:BAAALgADCgUJBQAAAA==.Hozaki:BAAALgAECgQJBAABLgAECgcJDAABAAAAAA==.',
Hu='Hudfin:BAAALgADCgUJBQAAAA==.Hundred:BAAALgAECgIJAgAAAA==.',
['Hí']='Hílthaen:BAABLgAECn8tAAIbAAgJexYCEwAdAgAbAAgJexYCEwAdAgAAAA==.',
Ic='Icebones:BAAALgADCgcJDAABLgAECgQJCQABAAAAAA==.Icelight:BAAALgAECgQJCQAAAA==.Ichigokisu:BAAALgAECgUJDgAAAA==.',
Il='Illiduji:BAAALgADCgMJAwAAAA==.Illy:BAABLgAECn8jAAIXAAkJ+hb9JQAXAgAXAAkJ+hb9JQAXAgAAAA==.',
Im='Imposed:BAAALgAECgcJEAAAAA==.',
In='Instantdeath:BAAALgAECgcJDAAAAA==.Invali:BAAALgAECgMJAwAAAA==.',
Io='Iorla:BAAALgADCgYJAQAAAA==.',
Ir='Irônhide:BAAALgAECgEJAQAAAA==.',
Iv='Ivranda:BAAALgADCgkJEgABLgAECgcJFQAPAEYKAA==.',
Iz='Iz:BAAALgAECgEJAQAAAA==.',
Ja='Jaapp:BAAALgAECgMJBgAAAA==.Jahan:BAACLgAFFH8FAAIjAAMJRRiSIQDzAAAjAAMJRRiSIQDzAAAuAAQKfy0AAyMACAkiJE4EADEDACMACAkiJE4EADEDABoAAwnIEv1JALgAAAAA.Jamie:BAABLgAFFH8IAAISAAMJhCNESAA3AQASAAMJhCNESAA3AQABLgAFFAcJGAANALkhAA==.Jaydine:BAAALgADCgYJBgABLgAECgkJMAACAKAhAA==.',
Je='Jeri:BAAALgAECgYJBwAAAA==.',
Jh='Jhie:BAAALgAECgUJDQAAAA==.',
Ji='Jinro:BAAALgAECgEJAQABLgABCgMJCQABAAAAAA==.',
Ju='Jud:BAAALgAECggJDwAAAA==.Juviâ:BAAALgAECggJCAABLgAECggJGQAIAM0cAA==.Juxtaposed:BAAALgADCgUJBQAAAA==.',
Ka='Kaelora:BAAALgADCggJEQAAAA==.Kaerei:BAABLgAECn8sAAIHAAkJnh5AGACUAgAHAAkJnh5AGACUAgAAAA==.Kaleb:BAABLgAECn8hAAIfAAgJtiEECACCAgAfAAgJtiEECACCAgAAAA==.Kalfalah:BAABLgAECn8aAAQFAAcJrBJcLgA4AQAFAAcJNBJcLgA4AQAcAAMJHhS7IgC4AAAEAAEJRArpyQAmAAAAAA==.Kalferno:BAAALgAECgQJCgAAAA==.Kalirkaz:BAACLgAFFH8IAAIEAAMJRwcLOgCrAAAEAAMJRwcLOgCrAAAuAAQKfy0AAwQACQmMGkoSAJoCAAQACQmMGkoSAJoCAAUABQk5Bu5UAIoAAAAA.Kallipsa:BAAALgAECgMJAwAAAA==.Karasu:BAAALgAECgIJAgABLgAECgkJLAALADMQAA==.Karst:BAAALgAECgQJBQABLgAFFAMJBQAjAEUYAA==.Kathria:BAAALgAECgcJDQAAAA==.',
Ke='Kegendary:BAAALgAECgQJCAAAAA==.Keler:BAAALgADCgIJAwABLgAECgMJBwABAAAAAA==.Keládry:BAABLgAECn8WAAIIAAYJXhj4KgCSAQAIAAYJXhj4KgCSAQAAAA==.Keskiyö:BAAALgADCgkJFQABLgAECgkJLAALADMQAA==.',
Kh='Khaalid:BAAALgAECgEJAQABLgABCgMJCQABAAAAAA==.Khallock:BAABLgAECn8iAAIMAAYJjRhxDABxAQAMAAYJjRhxDABxAQAAAA==.Khamael:BAAALgAECgEJAQAAAA==.',
Ki='Kiemen:BAABLgAECn8oAAMSAAkJHRp6KwAvAgASAAkJHRp6KwAvAgAeAAEJbQ7sKQA1AAAAAA==.Kierya:BAAALgAECgEJAQAAAA==.Killerpoison:BAAALgAECgkJBQAAAA==.Killko:BAABLgAECn8bAAISAAkJ/huUIgBaAgASAAkJ/huUIgBaAgAAAA==.Kinki:BAAALgAECgMJAwABLgAECgcJGAAhANUPAA==.Kirisen:BAAALgAECgUJCQAAAA==.Kitan:BAAALgAECgQJBQAAAA==.Kitani:BAAALgADCgkJDwABLgAECgYJCQABAAAAAA==.',
Ko='Konno:BAAALgAECgQJBAABLgAFFAYJFwARAAQlAA==.Kooterr:BAAALgADCgUJBQAAAA==.Korbix:BAABLgAECn8XAAISAAYJWhvSYgB/AQASAAYJWhvSYgB/AQAAAA==.',
Kr='Kragsloor:BAAALgAECgEJAQAAAA==.Kredorin:BAAALgAECgYJCgAAAA==.Krewella:BAAALgADCgcJBwAAAA==.Krickette:BAAALgAECgYJBgAAAA==.Krihl:BAAALgAECgkJBgAAAA==.Krovmar:BAAALgADCgUJBQAAAA==.',
Ks='Kspanxx:BAAALgAECgMJAwAAAA==.',
Kt='Kthanx:BAAALgADCgYJBgAAAA==.',
Ku='Kungpowgazer:BAABLgAECn8VAAMVAAgJaB2PDgAyAgAVAAgJaB2PDgAyAgALAAEJew/KgwAvAAAAAA==.Kunls:BAABLgAECn8eAAIfAAgJrgjpIgAlAQAfAAgJrgjpIgAlAQAAAA==.Kuraak:BAAALgADCgYJBgAAAA==.Kuraki:BAABLgAECn8WAAILAAcJtgYePQDeAAALAAcJtgYePQDeAAAAAA==.Kurasa:BAABLgAECn8sAAMLAAkJMxDuGgCtAQALAAkJMxDuGgCtAQAGAAQJowH4WgBjAAAAAA==.Kutraz:BAAALgAECgQJBQAAAA==.',
La='Ladrar:BAAALgAECgcJEQAAAA==.Laelina:BAAALgAECgEJAwAAAA==.Lanadiel:BAABLgAECn81AAIkAAkJiCLLAQAFAwAkAAkJiCLLAQAFAwAAAA==.Lazz:BAABLgAECn8UAAQgAAcJpiHdEAANAgAgAAcJpiHdEAANAgAhAAQJ5RkJQQBVAQAOAAEJAACtFgEAAAAAAA==.',
Le='Legend:BAACLgAFFH8TAAIXAAQJASHdHgBvAQAXAAQJASHdHgBvAQAuAAQKfzIAAhcACQm3IDAJAD4DABcACQm3IDAJAD4DAAAA.Lekrotar:BAAALgAECgQJBAAAAA==.Letsyoudie:BAAALgAECgMJAwAAAA==.',
Li='Lian:BAAALgAECgYJEQAAAA==.Lichbane:BAABLgAECn81AAISAAkJmCFsEADKAgASAAkJmCFsEADKAgAAAA==.Licun:BAAALgAECgYJDQAAAA==.Lifexdeath:BAABLgAECn8ZAAMbAAcJ5QbrNwD4AAAbAAcJ5QbrNwD4AAAaAAEJxgOzegAkAAAAAA==.Lightcell:BAAALgAECgQJBgAAAA==.Liliara:BAABLgAECn80AAIOAAkJ3BC3NgDYAQAOAAkJ3BC3NgDYAQAAAA==.Lillyirl:BAAALgAECgUJDwAAAA==.Lillymae:BAAALgAECgQJBAAAAA==.Lillyslight:BAAALgADCgYJBgAAAA==.Lillysneak:BAAALgADCgUJCgAAAA==.Lillytae:BAAALgAECgQJBwAAAA==.Lillyzard:BAAALgADCgUJCAAAAA==.Lilmoo:BAAALgAECgcJDwAAAA==.Linkhunter:BAAALgAECgYJBgABLgAECgkJLQAjALMUAA==.Linni:BAABLgAECn8ZAAIIAAgJzRxkDgCIAgAIAAgJzRxkDgCIAgAAAA==.Lizardwizard:BAAALgAECgQJBAAAAA==.',
Lo='Lockgodtko:BAAALgAECgcJDQAAAA==.Lodise:BAABLgAECn8gAAMMAAgJgg4/DQBRAQAMAAgJgg4/DQBRAQANAAEJAAgZHQEyAAAAAA==.Lonful:BAAALgADCgEJAQAAAA==.Lorzz:BAACLgAFFH8FAAIbAAMJCg9nGQC/AAAbAAMJCg9nGQC/AAAuAAQKfzEAAhsACAnbIsoFAP0CABsACAnbIsoFAP0CAAAA.Lothe:BAABLgAECn8WAAIIAAcJciAQEAB0AgAIAAcJciAQEAB0AgAAAA==.',
Lu='Lucrio:BAABLgAECn87AAISAAkJNhYJKQA6AgASAAkJNhYJKQA6AgAAAA==.Ludoe:BAAALgADCgkJMQAAAA==.Luminariah:BAAALgAECgMJAwAAAA==.Luna:BAAALgAECgUJDwAAAA==.Lunalai:BAABLgAECn9BAAIDAAkJ3iKUAQAdAwADAAkJ3iKUAQAdAwAAAA==.Lushy:BAAALgAECggJEAAAAA==.',
Ly='Lylineth:BAAALgADCgYJBgAAAA==.Lylinette:BAAALgAECgcJEgAAAA==.Lyssandra:BAAALgADCgUJBQAAAA==.',
['Lí']='Lízandor:BAACLgAFFH8UAAIHAAUJEhAtMQAsAQAHAAUJEhAtMQAsAQAuAAQKfykAAgcACQmYHAQhAGMCAAcACQmYHAQhAGMCAAAA.',
['Lû']='Lûsøn:BAAALgAECgEJAQAAAA==.',
Ma='Madruskee:BAABLgAECn8aAAIeAAYJ/xDvEgAFAQAeAAYJ/xDvEgAFAQAAAA==.Magahpt:BAAALgAECgMJBAAAAA==.Magdea:BAAALgADCgYJBgAAAA==.Mageofdeath:BAAALgAECgMJBAABLgAECgcJDAABAAAAAA==.Magistroll:BAABLgAECn8cAAICAAcJXgUQuwD0AAACAAcJXgUQuwD0AAAAAA==.Malevohaynk:BAAALgAECgQJBQABLgAECggJIgAVADUjAA==.Mandrallea:BAAALgADCgIJAgAAAA==.Maryshelley:BAAALgADCgMJAwAAAA==.Matoo:BAAALgADCgEJAQAAAA==.Maurin:BAAALgAECgYJBgAAAA==.Maximumhonk:BAABLgAECn8hAAITAAYJmxOlRwBcAQATAAYJmxOlRwBcAQAAAA==.',
Me='Melfys:BAAALgAECgEJAQAAAA==.Melquisedec:BAAALgAECgIJAgAAAA==.Mendelia:BAABLgAECn8ZAAIkAAcJtBR5EwBlAQAkAAcJtBR5EwBlAQAAAA==.Mercus:BAABLgAECn8YAAMUAAkJVBgiBgBqAQAUAAYJpBQiBgBqAQAJAAgJeBlUKQAeAQAAAA==.Merkstrasza:BAAALgAECgYJDgAAAA==.Mervenious:BAABLgAECn8UAAQZAAYJQA1URgADAQAZAAYJiAtURgADAQAoAAMJWgt+QACPAAAWAAMJpQhrOQB/AAAAAA==.Meu:BAAALgAECggJBgAAAA==.',
Mi='Midasdh:BAACLgAFFH8OAAIXAAUJ0wuePAAIAQAXAAUJ0wuePAAIAQAuAAQKfxwAAxcACAmAF5Y+APoBABcACAnfFJY+APoBAB8ABgmOFwMwAE8BAAAA.Midasdk:BAACLgAFFH8NAAISAAUJEhrwQABDAQASAAUJEhrwQABDAQAuAAQKfxwAAxIABwnMHG9PAAQCABIABwm9GW9PAAQCAB4AAwkzEkMcAJ8AAAEuAAUUBQkOABcA0wsA.Midasmonk:BAAALgAECgEJAQABLgAFFAUJDgAXANMLAA==.Midasshift:BAAALgAECgcJDwAAAA==.Miladepollo:BAAALgADCgMJAwAAAA==.Mindblank:BAAALgAECgQJBAAAAA==.Mindplague:BAABLgAECn8kAAIaAAcJAiBqFAAGAgAaAAcJAiBqFAAGAgAAAA==.Minipincin:BAAALgAECgEJAQAAAA==.Minisicwidit:BAAALgADCgMJAwAAAA==.Mistdeeznuts:BAABLgAECn8fAAMGAAkJlgzrKgCIAQAGAAkJlgzrKgCIAQALAAEJkgOVmAAeAAAAAA==.',
Mo='Mogwaï:BAAALgAECgYJCAAAAA==.Mokokoma:BAAALgAECgIJAgAAAA==.Moonde:BAAALgAECggJDgAAAA==.Moonscale:BAABLgAECn8sAAIQAAkJdx63AQCrAgAQAAkJdx63AQCrAgAAAA==.Moosayer:BAAALgAECgQJBgAAAA==.Moovement:BAAALgAECgMJAwABLgAECgYJBgABAAAAAA==.Mossed:BAAALgADCgMJAwAAAA==.',
Ms='Mskelsier:BAAALgAECgUJBQAAAA==.',
Mt='Mtaur:BAAALgADCggJDwAAAA==.',
Mu='Muclor:BAAALgADCgcJBwABLgAFFAMJAwABAAAAAA==.Mustang:BAAALgAECgUJBQAAAA==.',
My='Mythalis:BAAALgAECgQJBQAAAA==.',
['Mä']='Märändus:BAAALgADCgEJAQAAAA==.',
['Må']='Måzikeen:BAAALgADCgMJAwAAAA==.',
Na='Narse:BAAALgAFFAIJBAAAAA==.Narz:BAABLgAECn8wAAIOAAkJnBKMMwDkAQAOAAkJnBKMMwDkAQAAAA==.Nastianna:BAAALgAECgQJCgAAAA==.Natgeo:BAAALgAECggJCAABLgAECgkJLQAjALMUAA==.Nazumi:BAABLgAECn8mAAILAAgJWh0VDQBNAgALAAgJWh0VDQBNAgAAAA==.',
Nd='Ndiz:BAABLgAECn8VAAIOAAcJIhwCJwAdAgAOAAcJIhwCJwAdAgAAAA==.',
Ne='Necronomikon:BAAALgADCgEJAQAAAA==.Neeva:BAAALgADCgYJEAAAAA==.Nelrya:BAEALgADCgcJDQABLgAECgkJLQAHAAgdAA==.Nephilym:BAAALgAECgEJAQAAAA==.Nerhzul:BAAALgAECgEJAQAAAA==.Neruphuyt:BAABLgAECn8oAAIFAAgJGQ9UJwBkAQAFAAgJGQ9UJwBkAQAAAA==.',
Ni='Niath:BAAALgAECgEJAgAAAA==.Nightsniper:BAAALgAECggJEwAAAA==.Ninfassins:BAAALgADCgIJAgAAAA==.',
No='Norintha:BAAALgADCgEJAQAAAA==.Norolen:BAAALgADCgIJAgAAAA==.',
Ny='Nyxiel:BAAALgAECgQJBQAAAA==.',
Oa='Oak:BAAALgAECgkJEQAAAA==.',
Oc='Occo:BAAALgADCgEJAQAAAA==.',
Og='Ogroc:BAAALgAECgQJBAAAAA==.',
Ok='Okioak:BAAALgAECggJEQAAAA==.',
Ol='Olgon:BAACLgAFFH8FAAIOAAMJMAKrVQCkAAAOAAMJMAKrVQCkAAAuAAQKfzAAAg4ACAmbGRYvAPYBAA4ACAmbGRYvAPYBAAAA.Olstinkyboot:BAAALgAECgEJAQAAAA==.',
Op='Oprhawinfury:BAABLgAECn8iAAISAAkJRA5KUwCmAQASAAkJRA5KUwCmAQAAAA==.',
Or='Orgodemir:BAAALgADCgkJDwAAAA==.',
Ot='Otemoto:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
Ox='Oxley:BAAALgAECgEJAQAAAA==.',
Pa='Paigor:BAAALgAECgIJAgAAAA==.Pakswagger:BAABLgAECn8XAAMYAAYJFReyEQCKAQAYAAYJFReyEQCKAQAPAAMJRQTPZwBsAAAAAA==.Pallyberry:BAABLgAECn8xAAIIAAkJZhtIDACmAgAIAAkJZhtIDACmAgAAAA==.Pancake:BAAALgAECgEJAQAAAA==.Pandemonia:BAABLgAECn8zAAMlAAkJ5Q0rFgCYAQAlAAgJHgwrFgCYAQANAAkJJw0OWwB3AQAAAA==.Paprika:BAAALgADCgkJEAAAAA==.Parsie:BAAALgAECgcJCQAAAA==.Patch:BAAALgADCgYJBgAAAA==.Pathibas:BAAALgADCgEJAQABLgAECgkJQgAZAHskAA==.Pattycakes:BAABLgAECn8jAAISAAkJLBZRPADtAQASAAkJLBZRPADtAQAAAA==.',
Pe='Pencil:BAACLgAFFH8QAAINAAQJTBtSLABTAQANAAQJTBtSLABTAQAuAAQKfxsABA0ACAkwHRAxAPwBAA0ACAkwHRAxAPwBACUAAwniBj1dAFcAAAwAAQkAANAsAEUAAAAA.Pewpewlvltwo:BAACLgAFFH8FAAIRAAMJDQbPCQDKAAARAAMJDQbPCQDKAAAuAAQKfyUAAhEACAnQHuYGADMCABEACAnQHuYGADMCAAAA.Pewthree:BAAALgAECgYJCAABLgAFFAMJBQARAA0GAA==.',
Ph='Pherocious:BAABLgAECn8VAAIhAAUJ6xPmFQDlAAAhAAUJ6xPmFQDlAAAAAA==.',
Pi='Pintsize:BAAALgADCgIJAgAAAA==.',
Pl='Plaguelis:BAAALgADCgEJAQABLgAECgkJOAARAFIdAA==.Plexy:BAAALgAECgcJCgABLgAFFAEJAQABAAAAAA==.',
Po='Pobble:BAAALgADCgcJBwAAAA==.Pokitz:BAABLgAECn8uAAIHAAgJNg13cwBnAQAHAAgJNg13cwBnAQAAAA==.Poprock:BAAALgAECgEJAQAAAA==.Potus:BAAALgADCgQJBAAAAA==.',
Pr='Primordinor:BAABLgAECn8iAAMTAAgJtxm3KADtAQATAAcJ0xe3KADtAQAnAAgJyxwHHwC9AQAAAA==.Probnotalive:BAABLgAECn8fAAIOAAgJvBcJPwC6AQAOAAgJvBcJPwC6AQAAAA==.Probnotferal:BAAALgAECgEJAQAAAA==.Probnoturmom:BAABLgAECn8dAAIbAAgJVxt2GAAYAgAbAAgJVxt2GAAYAgAAAA==.',
Ra='Raevyn:BAAALgAECgEJAQAAAA==.Rafaiel:BAAALgAECgQJBAAAAA==.Rakan:BAABLgAECn9BAAIoAAkJPh5fBACtAgAoAAkJPh5fBACtAgAAAA==.Rakasha:BAAALgADCgkJCQAAAA==.Rallick:BAACLgAFFH8FAAIIAAMJWg32JwC5AAAIAAMJWg32JwC5AAAuAAQKfy8AAggACAmvGooRAGQCAAgACAmvGooRAGQCAAAA.Ranì:BAABLgAECn81AAIWAAkJ8RfbDAD2AQAWAAkJ8RfbDAD2AQAAAA==.Rathger:BAAALgAECggJEgAAAA==.Ravenscythe:BAAALgADCgEJAQAAAA==.Raydor:BAAALgAECggJDgAAAA==.',
Re='Reb:BAABLgAECn8mAAIaAAkJ6gRxLwA4AQAaAAkJ6gRxLwA4AQAAAA==.Redic:BAAALgAECgMJAwAAAA==.Regis:BAAALgAECgYJBgABLgAECggJJQAGAE0cAA==.Rellix:BAAALgADCgUJBQAAAA==.Rendkick:BAAALgADCgcJBwAAAA==.Rendwee:BAABLgAECn8xAAIcAAkJGCHkAQD7AgAcAAkJGCHkAQD7AgAAAA==.Reuel:BAAALgAECgMJBAAAAA==.Rewolf:BAAALgAECggJEgAAAA==.',
Rh='Rheemus:BAAALgADCgYJBgAAAA==.Rhul:BAAALgAECgUJCQAAAA==.',
Ri='Ricflairion:BAABLgAECn8bAAIPAAgJTQnfNQAwAQAPAAgJTQnfNQAwAQAAAA==.Rimuru:BAAALgAECgEJAwABLgAECgMJBwABAAAAAA==.',
Ro='Roadrunner:BAACLgAFFH8JAAIOAAMJegh8SwDLAAAOAAMJegh8SwDLAAAuAAQKfykAAg4ACQmjDzcyAOcBAA4ACQmjDzcyAOcBAAAA.Rodcet:BAACLgAFFH8FAAIHAAIJxR2NXQC2AAAHAAIJxR2NXQC2AAAuAAQKfzwAAgcACQnBJfACAF0DAAcACQnBJfACAF0DAAAA.Roflcopterr:BAABLgAECn8pAAQIAAgJdBv2DgCBAgAIAAgJdBv2DgCBAgAHAAYJ9Qf3wADjAAAkAAEJSAWGSwAZAAAAAA==.Rognan:BAAALgAECgMJAwAAAA==.Romina:BAAALgADCgEJBAAAAA==.Rookgue:BAABLgAECn8wAAIKAAgJBhZZBgDiAQAKAAgJBhZZBgDiAQAAAA==.Rookoker:BAABLgAECn8aAAIQAAcJ4QgEDgANAQAQAAcJ4QgEDgANAQAAAA==.Rootsafarian:BAAALgADCgcJBwAAAA==.Rossa:BAAALgAECgEJAQAAAA==.Rossdair:BAAALgAECgQJBAABLgADCgUJCQABAAAAAA==.Rossperot:BAACLgAFFH8GAAISAAIJHh0DkACtAAASAAIJHh0DkACtAAAuAAQKfyUAAhIACQmQIAUUALACABIACQmQIAUUALACAAAA.Rothschild:BAAALgADCgEJAQAAAA==.Rottenfist:BAAALgAECgEJAQAAAA==.',
Ru='Ruknar:BAAALgAECgMJAwAAAA==.',
Sa='Sabako:BAAALgADCgcJCAAAAA==.Sacra:BAAALgADCgUJBQABLgAFFAMJBQAjAEUYAA==.Saelara:BAAALgADCgcJCgAAAA==.Saelis:BAAALgADCgQJBAAAAA==.Sakaru:BAABLgAECn8bAAICAAgJTw7icQB5AQACAAgJTw7icQB5AQABLgAECgkJLAALADMQAA==.Salmoney:BAAALgAECgQJBAAAAA==.Salorin:BAAALgADCgYJCQAAAA==.Samgee:BAACLgAFFH8QAAIHAAQJbBL7MQArAQAHAAQJbBL7MQArAQAuAAQKf0QAAgcACQnaIOISALYCAAcACQnaIOISALYCAAAA.Sandormu:BAAALgADCgkJCQAAAA==.Saphas:BAAALgAECgMJAwAAAA==.Saynar:BAABLgAECn86AAIXAAkJxCPYAwA5AwAXAAkJxCPYAwA5AwAAAA==.',
Sc='Scattered:BAABLgAECn8UAAQNAAgJthCgmQDzAAANAAYJHg6gmQDzAAAlAAMJHhRLQACzAAAMAAEJggvXMgAtAAAAAA==.Scooter:BAAALgAECgUJCgAAAA==.Scyx:BAAALgADCgEJAQAAAA==.',
Se='Seba:BAACLgAFFH8IAAICAAMJCgziaADkAAACAAMJCgziaADkAAAuAAQKfzIAAgIACAmBHTwxADUCAAIACAmBHTwxADUCAAAA.Selesne:BAABLgAECn8WAAIUAAcJdAh8DgD0AAAUAAcJdAh8DgD0AAAAAA==.Seraphicktwo:BAABLgAECn8cAAMbAAUJvhrTMAAkAQAbAAUJvhrTMAAkAQAaAAUJBRDlQgDZAAAAAA==.Seriana:BAAALgAECggJEAAAAA==.Sermidas:BAACLgAFFH8KAAMoAAMJqRuqFwDcAAAoAAMJqRuqFwDcAAAZAAIJ3AevGwCYAAAuAAQKfyIAAygACQk6H7gCAPACACgACQk6H7gCAPACABkABwnOFFw0ANgBAAEuAAUUBQkOABcA0wsA.',
Sh='Shadowcutter:BAAALgAECgEJAQABLgAECgcJDAABAAAAAA==.Shaggmz:BAABLgAECn8XAAIZAAYJtxL0NwBBAQAZAAYJtxL0NwBBAQAAAA==.Shinakuma:BAAALgAECgUJDgAAAA==.Shinma:BAABLgAECn8XAAIkAAYJgQRLLgCEAAAkAAYJgQRLLgCEAAAAAA==.Shrubbery:BAABLgAECn8VAAINAAcJ+wMFqgDWAAANAAcJ+wMFqgDWAAAAAA==.Shymary:BAABLgAECn8XAAIjAAYJZwXJOgDwAAAjAAYJZwXJOgDwAAAAAA==.',
Si='Siete:BAAALgAECgEJAQABLgAECgQJCQABAAAAAA==.Silvertip:BAAALgADCggJFQAAAA==.Silëx:BAABLgAECn8YAAICAAcJMhg+XwClAQACAAcJMhg+XwClAQAAAA==.Sioc:BAAALgADCgEJAQAAAA==.Siouxiesioux:BAAALgADCgYJCgAAAA==.Siyona:BAAALgADCgkJDAAAAA==.',
Sk='Skits:BAAALgAECgIJAgAAAA==.Skyrah:BAAALgAECgYJBgAAAA==.Skyrie:BAAALgADCgQJBQAAAA==.',
Sl='Slagbröder:BAAALgADCgcJBwAAAA==.Slohine:BAAALgAECgUJBQAAAA==.Sludgecrush:BAAALgAECgYJCwAAAA==.Slugondeez:BAABLgAFFH8GAAIIAAIJ5hCKMQB6AAAIAAIJ5hCKMQB6AAAAAA==.',
Sm='Smallmike:BAAALgAECgIJAgAAAA==.Smitefist:BAAALgAECgIJAgABLgAECgQJBQABAAAAAA==.Smokiee:BAABLgAECn8XAAIEAAcJ7xElPwBzAQAEAAcJ7xElPwBzAQAAAA==.',
Sn='Snailtrail:BAABLgAECn8YAAIiAAgJpwSrFADbAAAiAAgJpwSrFADbAAAAAA==.Snark:BAAALgAECgYJDgAAAA==.Snarkkin:BAAALgAECgQJDAAAAA==.Snowkim:BAABLgAECn8bAAIkAAgJmh3bCQABAgAkAAgJmh3bCQABAgAAAA==.Snuzzle:BAABLgAECn8tAAIDAAgJ3hufCQAUAgADAAgJ3hufCQAUAgAAAA==.',
So='Soniic:BAAALgAECgIJAgAAAA==.Soullessfros:BAABLgAECn8gAAISAAkJzRAzRADUAQASAAkJzRAzRADUAQAAAA==.Soullessman:BAAALgADCgQJCAAAAA==.Sourmash:BAAALgADCgkJCgAAAA==.',
Sp='Spaghet:BAABLgAECn8fAAInAAkJNRnvFwD5AQAnAAkJNRnvFwD5AQAAAA==.Spillthetea:BAAALgAECggJEgAAAA==.Sploot:BAAALgAECggJEAAAAA==.',
Sq='Squibbles:BAAALgAECgEJAQAAAA==.',
Sr='Srasjet:BAABLgAECn8iAAITAAgJSxyhEQCWAgATAAgJSxyhEQCWAgAAAA==.',
Ss='Ssimba:BAAALgAECggJDQAAAA==.',
St='Stabytha:BAABLgAECn8XAAMJAAcJKBNBJwAtAQAJAAYJOBJBJwAtAQAKAAEJ1RdiHwBBAAAAAA==.Stark:BAAALgADCgYJCgAAAA==.Starlight:BAAALgAECgEJAQAAAA==.Stealthed:BAAALgAECgYJCwAAAA==.Stender:BAAALgAECgMJBQABLgAFFAYJDwAfAK8fAA==.Stormae:BAAALgADCgMJAgAAAA==.Stormcall:BAAALgAECgUJDwAAAA==.Stratusfied:BAAALgAECgMJBQAAAA==.',
Su='Susbandaid:BAAALgADCgYJBgAAAA==.',
Sw='Sweetiefox:BAACLgAFFH8FAAICAAUJhgJQYgDxAAACAAUJhgJQYgDxAAAuAAQKfxgAAgIACQkACqFuAIABAAIACQkACqFuAIABAAAA.Swiss:BAABLgAECn8WAAInAAcJyA/bNgAtAQAnAAcJyA/bNgAtAQAAAA==.',
Sy='Syllai:BAAALgAECgYJBgAAAA==.Symboli:BAAALgADCgQJBAAAAA==.Syphus:BAAALgADCgQJBAAAAA==.',
['Sá']='Sáëgárón:BAABLgAECn8YAAMZAAgJJxPTJwCXAQAZAAgJJxPTJwCXAQAoAAEJpwXRaAAlAAAAAA==.',
Ta='Tacyon:BAAALgADCggJDwAAAA==.Taliden:BAAALgAECgYJDAAAAA==.Tallera:BAAALgADCgEJAgAAAA==.Taniyah:BAAALgAECgQJCAAAAA==.Tankinstine:BAAALgADCgEJAgAAAA==.Taraylda:BAABLgAECn8ZAAMjAAgJIhgMGgDIAQAjAAgJIhgMGgDIAQAaAAIJqgqzXQBhAAAAAA==.Tarful:BAAALgADCgQJBAAAAA==.Tarzand:BAAALgADCgEJAQABLgADCgcJDwABAAAAAA==.Tazo:BAABLgAECn8iAAIHAAcJKxLBeQBaAQAHAAcJKxLBeQBaAQAAAA==.',
Te='Tearek:BAACLgAFFH8FAAIXAAMJWw+gSwDWAAAXAAMJWw+gSwDWAAAuAAQKfxsAAhcABwlVHOcxAN4BABcABwlVHOcxAN4BAAAA.Tearik:BAAALgAECgYJBAAAAA==.Tecdor:BAAALgAECgQJBAAAAA==.Temla:BAABLgAECn8vAAIOAAkJRxYULQD/AQAOAAkJRxYULQD/AQAAAA==.Tenga:BAAALgAECgQJBAAAAA==.Teronfiggy:BAABLgAECn8cAAISAAgJjA6EaABwAQASAAgJjA6EaABwAQAAAA==.',
Tf='Tfirs:BAACLgAFFH8OAAIDAAQJ6wzSDADaAAADAAQJ6wzSDADaAAAuAAQKfy8AAgMACAm+GywHAEsCAAMACAm+GywHAEsCAAEuAAEKCQkSAAEAAAAA.',
Th='Thartilidan:BAAALgAECgYJEQABLgAECggJEAABAAAAAA==.Theokoles:BAAALgAECgQJBQAAAA==.Thepaladin:BAAALgADCgMJAwAAAA==.Thickblòód:BAAALgAFFAEJAQAAAA==.',
Ti='Tilythia:BAAALgADCgUJBQAAAA==.',
To='Tona:BAAALgADCgMJAwAAAA==.Toospookie:BAAALgADCgQJAgAAAA==.Tophu:BAAALgADCgcJBwAAAA==.Torkz:BAAALgADCgEJAgAAAA==.',
Tr='Tramplip:BAABLgAECn8fAAIlAAgJ5g+1CwBWAQAlAAgJ5g+1CwBWAQAAAA==.Treecloud:BAABLgAECn8+AAMFAAkJXSTQAgAqAwAFAAkJXSTQAgAqAwADAAkJhBboCQAOAgAAAA==.Trevian:BAABLgAECn8WAAIHAAcJjRMgbgByAQAHAAcJjRMgbgByAQAAAA==.Trinitee:BAAALgAECgEJAQABLgAECgMJBwABAAAAAA==.',
Tu='Tub:BAAALgAECgQJBAABLgAFFAQJDAALAHwLAA==.Tuluxxi:BAABLgAECn9DAAITAAkJoiHIAwBaAwATAAkJoiHIAwBaAwAAAA==.Turborunic:BAAALgADCgkJGwAAAA==.Turiae:BAACLgAFFH8OAAMPAAUJ1Ro/FwBSAQAPAAQJ1Ro/FwBSAQAQAAEJAADSDQAAAAAuAAQKfy8ABA8ACQlVIocDACgDAA8ACQlVIocDACgDABAABwnZFsgQANEBABgABQkhCaQ0AMgAAAAA.Tuskerz:BAAALgAECgEJAwAAAA==.Tusobrinna:BAAALgAECgUJCAAAAA==.Tutter:BAAALgADCgIJAgAAAA==.Tuuldd:BAAALgADCggJCAAAAA==.',
Tw='Twunk:BAAALgAECggJEAAAAA==.',
Ty='Typhlotic:BAAALgADCgMJAwAAAA==.Tyrennius:BAAALgAECgQJBAAAAA==.Tyrianis:BAABLgAECn8rAAMJAAkJNyGKBwCOAgAJAAkJSSCKBwCOAgAKAAMJzh6rEwDFAAAAAA==.',
Tz='Tzxdh:BAAALgAECgUJBQAAAA==.Tzxdruid:BAAALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ug='Uglymancer:BAABLgAECn8WAAMNAAcJ6hQyVwCBAQANAAcJ6hQyVwCBAQAlAAEJAAD1RwAAAAAAAA==.',
Uj='Ujimas:BAAALgAECgUJEAAAAA==.Ujong:BAAALgAECgYJBgABLgAECgcJMQACALIkAA==.',
Un='Unchartedd:BAAALgADCgEJAQAAAA==.',
Va='Vaenira:BAAALgADCgUJBgAAAA==.Vako:BAAALgADCgEJAQAAAA==.Valdara:BAAALgADCgkJEgAAAA==.Valemon:BAAALgAECgIJAgAAAA==.Vampireshade:BAABLgAECn8tAAIUAAgJ4ghXCwA3AQAUAAgJ4ghXCwA3AQAAAA==.Vanimao:BAABLgAECn8tAAQEAAkJdQ+tPACxAQAEAAkJdQ+tPACxAQADAAcJrwwfIgD5AAAFAAEJ2AardwAwAAAAAA==.Vankman:BAAALgADCgcJBwAAAA==.Vannaka:BAAALgADCgEJAQAAAA==.',
Vb='Vbull:BAAALgAECgEJAQAAAA==.',
Ve='Vedrolan:BAAALgADCgUJDgABLgAFFAMJCAAVACQKAA==.Velifya:BAAALgADCgMJAwAAAA==.Velindon:BAAALgADCgYJBgAAAA==.Velissari:BAAALgAECgYJEgAAAA==.Velonar:BAAALgADCgEJAQAAAA==.Velouria:BAABLgAECn9DAAQDAAkJ2CJ2AQAkAwADAAkJwCJ2AQAkAwAFAAgJ6h8SDQDIAgAEAAIJ9QSXwABGAAAAAA==.Venatra:BAAALgAECgQJBAAAAA==.Verudora:BAAALgADCgcJBwAAAA==.Vexira:BAAALgADCgcJBwAAAA==.',
Vi='Violet:BAABLgAECn8gAAIYAAgJJBfUCQAkAgAYAAgJJBfUCQAkAgAAAA==.Violette:BAABLgAECn8lAAIOAAcJeg8KYQBWAQAOAAcJeg8KYQBWAQAAAA==.Visix:BAAALgADCgMJAwAAAA==.Vitt:BAAALgAECgEJAQAAAA==.',
Vo='Voidchacha:BAAALgADCgEJAQAAAA==.Voidlink:BAABLgAECn8tAAIjAAkJsxRtFAALAgAjAAkJsxRtFAALAgAAAA==.Voidmistress:BAABLgAECn8nAAICAAcJGRi5XQCpAQACAAcJGRi5XQCpAQAAAA==.Voidpup:BAABLgAECn8oAAIXAAcJYxyMNQDPAQAXAAcJYxyMNQDPAQAAAA==.Volgrimm:BAABLgAECn8bAAIVAAgJKwtdLQAzAQAVAAgJKwtdLQAzAQAAAA==.Volitaire:BAAALgADCgYJBgAAAA==.',
Vy='Vynethan:BAAALgAECgEJAgAAAA==.',
['Vé']='Véngence:BAABLgAECn8UAAISAAcJTRDlcgBYAQASAAcJTRDlcgBYAQAAAA==.',
['Vê']='Vêx:BAAALgADCgYJBgAAAA==.',
Wa='Wabalabalosh:BAAALgADCgkJCQAAAA==.Wabgucci:BAAALgADCgUJBQAAAA==.Wabwum:BAAALgAECgMJAwAAAA==.Wakaekwondo:BAAALgAECgEJAQAAAA==.Wakarisma:BAAALgAECgEJAQAAAA==.Wanda:BAAALgAECgkJDAAAAA==.Wangao:BAABLgAFFH8IAAIVAAMJJApQMgC9AAAVAAMJJApQMgC9AAAAAA==.Warbluster:BAAALgADCgIJAgAAAA==.Warchylde:BAAALgADCgkJEAAAAA==.Warolderoy:BAABLgAECn9CAAIZAAkJeySwAgAuAwAZAAkJeySwAgAuAwAAAA==.',
We='Weedshaman:BAAALgAECgEJAwAAAA==.Weedwax:BAAALgAECgQJBAAAAA==.Weil:BAAALgADCgIJAgAAAA==.',
Wh='Whiinuss:BAABLgAECn8UAAIHAAcJlw25fwB7AQAHAAcJlw25fwB7AQAAAA==.Whytrabbit:BAAALgAECgIJAgAAAA==.',
Wi='Wigglesdeath:BAAALgAECgUJBQAAAA==.',
Wl='Wldeagle:BAAALgAECgQJBAAAAA==.',
Wo='Woker:BAAALgAECgQJBAABLgAECgkJOAARAFIdAA==.Woodpig:BAABLgAECn8uAAQEAAkJ2SGfBABZAwAEAAkJ2SGfBABZAwADAAIJVBOsOwBrAAAFAAIJXgbVeQAtAAAAAA==.Woogie:BAAALgAECgQJCwAAAA==.',
Wr='Wrangle:BAAALgADCgEJAQAAAA==.',
Wy='Wyldshade:BAAALgADCgYJCAAAAA==.Wyrm:BAAALgAECgUJBQABLgAECgUJCgABAAAAAA==.',
Xa='Xaladin:BAABLgAECn8VAAIfAAcJ6gnCJwABAQAfAAcJ6gnCJwABAQAAAA==.Xathas:BAAALgAECgQJBAAAAA==.',
Xe='Xenna:BAAALgAECgQJBAAAAA==.Xeq:BAAALgADCgQJBAAAAA==.',
Xi='Xiata:BAAALgAECgcJCQAAAA==.Xiu:BAAALgAECgMJAwAAAA==.',
Xr='Xrp:BAAALgADCgQJBQAAAA==.',
Ye='Yeoman:BAABLgAECn8ZAAIZAAcJSRB3NwBDAQAZAAcJSRB3NwBDAQAAAA==.',
Yg='Yggdralith:BAAALgAECgkJIwAAAQ==.',
Yo='Yourdeath:BAAALgAECgkJBAAAAA==.',
Yu='Yunosmall:BAAALgADCgIJAgAAAA==.Yunosmart:BAAALgAECgYJCQAAAA==.',
Za='Zaen:BAACLgAFFH8FAAINAAMJFQkAZgDLAAANAAMJFQkAZgDLAAAuAAQKfzEAAw0ACAkTH7chAEMCAA0ACAkTH7chAEMCACUAAwnUC7NDAKYAAAAA.Zagreus:BAAALgADCgcJCAAAAA==.Zakikaz:BAAALgAECgMJAwAAAA==.Zarkir:BAACLgAFFH8GAAMeAAMJMBrgCgABAQAeAAMJMBrgCgABAQASAAIJGA2tqwCPAAAuAAQKfyEABB4ACAneImQFACECAB4ABwl4IWQFACECABIABwnCIdY1AAQCAB0ABwmtF5oZAIcBAAEuAAQKBgkXAAIApyIA.Zarkìr:BAABLgAECn8XAAICAAYJpyKQZwAIAgACAAYJpyKQZwAIAgAAAA==.Zaues:BAAALgAECgMJBAAAAA==.',
Ze='Zelily:BAABLgAECn8UAAIOAAgJfgcjfQAWAQAOAAgJfgcjfQAWAQAAAA==.Zenarri:BAAALgADCgYJBwAAAA==.Zenasdan:BAAALgADCgUJBQAAAA==.Zepha:BAAALgAECgYJCwAAAA==.Zerø:BAAALgAECgIJAgABLgAECgYJFwACAKciAA==.',
Zl='Zlyandien:BAAALgADCggJDwABLgAECggJGQAjACIYAA==.',
Zo='Zornov:BAABLgAECn8jAAMkAAgJjx5VCAAiAgAkAAgJjx5VCAAiAgAIAAMJJgjaYwByAAAAAA==.',
Zu='Zulrich:BAAALgAECgUJBQAAAA==.',
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
