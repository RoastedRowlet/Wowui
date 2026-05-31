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

local lookup = {'Unknown-Unknown','Mage-Frost','Druid-Guardian','Druid-Restoration','Druid-Balance','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Havoc','Monk-Windwalker','Warlock-Affliction','Warlock-Demonology','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','DeathKnight-Unholy','Shaman-Restoration','Rogue-Outlaw','Monk-Brewmaster','Warrior-Protection','DemonHunter-Devourer','Evoker-Preservation','Warrior-Fury','Priest-Shadow','Priest-Holy','Druid-Feral','DeathKnight-Blood','DeathKnight-Frost','Hunter-Survival','Hunter-Marksmanship','DemonHunter-Vengeance','Priest-Discipline','Paladin-Protection','Warlock-Destruction','Mage-Arcane','Shaman-Elemental','Warrior-Arms',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abarlton:BAAALgAFFAEJAQABLgAECgcJDAABAAAAAA==.',
Ad='Adabeam:BAAALgADCgcJCwAAAA==.Adagio:BAABLgAECn8+AAICAAkJGR2HKQBeAgACAAkJGR2HKQBeAgAAAA==.Adetalo:BAABLgAECn8lAAIDAAkJ8Rf0CwACAgADAAkJ8Rf0CwACAgAAAA==.Adiara:BAAALgAECgMJAwAAAA==.Aditu:BAABLgAECn8gAAMEAAgJoht8FwB3AgAEAAgJoht8FwB3AgAFAAQJxA1KVQCfAAAAAA==.',
Ae='Aelis:BAAALgADCgcJCAAAAA==.Aemulo:BAAALgAECgUJBwAAAA==.Aerith:BAAALgADCgcJBwAAAA==.',
Ag='Agasonex:BAAALgADCgMJAwAAAA==.Aggroholic:BAAALgADCgMJAwABLgADCgYJEAABAAAAAA==.',
Ai='Airent:BAAALgAECgYJEQAAAA==.Aiyana:BAAALgAECgYJDgAAAA==.',
Ak='Akiirii:BAAALgAECgEJAQAAAA==.',
Al='Alaestel:BAAALgAECgQJBwAAAA==.Aldo:BAAALgAECgEJAQAAAA==.Aletheia:BAAALgAECgMJAwAAAA==.Alkaraho:BAAALgAECgMJAwAAAA==.Alleyways:BAACLgAFFH8JAAIGAAMJ7yUAGwBHAQAGAAMJ7yUAGwBHAQAuAAQKfzwAAgYACQn3JRoBAMkDAAYACQn3JRoBAMkDAAAA.Alzey:BAABLgAECn8jAAIHAAkJnA4uYQCVAQAHAAkJnA4uYQCVAQAAAA==.',
Am='Ambeon:BAAALgADCgUJBQAAAA==.Ammathindis:BAAALgADCgcJCQAAAA==.Ammutseba:BAAALgADCggJCAAAAA==.Amplers:BAAALgADCgUJBwAAAA==.',
An='Angelbane:BAAALgADCgQJBAAAAA==.Angina:BAAALgAECgIJAwAAAA==.Annarcis:BAAALgAECgYJEAAAAA==.Anotherdk:BAAALgAECgYJBgABLgAECgkJIgAIAG8iAA==.Anthiell:BAAALgADCgEJAQAAAA==.Antiman:BAABLgAECn8mAAIHAAgJVAlulAAvAQAHAAgJVAlulAAvAQAAAA==.',
Ap='Aplcyder:BAABLgAECn84AAIEAAkJVwzPQQB3AQAEAAkJVwzPQQB3AQAAAA==.',
Ar='Arachnid:BAABLgAECn8xAAICAAcJsiRFMQCtAgACAAcJsiRFMQCtAgAAAA==.Aragorn:BAAALgADCgkJDQAAAA==.Aratyn:BAABLgAECn8aAAICAAgJxBB1cAB/AQACAAgJxBB1cAB/AQAAAA==.Army:BAAALgAECgIJAwAAAA==.',
As='Asanot:BAAALgAECgUJBQAAAA==.',
At='Ati:BAAALgADCgIJAgAAAA==.',
Au='Audxo:BAAALgADCgMJAwAAAA==.',
Ay='Ayayron:BAAALgADCgQJBAAAAA==.',
Ba='Backhawk:BAAALgADCgcJEAAAAA==.Backsurgery:BAABLgAFFH8IAAMJAAYJMhzhEABgAQAJAAQJ6RrhEABgAQAKAAIJUyEUCwBmAAAAAA==.Baerrn:BAABLgAECn8aAAILAAgJigfmKgACAQALAAgJigfmKgACAQAAAA==.Baltazaris:BAAALgADCgQJBAAAAA==.Bamboo:BAAALgAECgYJCQABLgAFFAMJCgAMAIAZAA==.Baricia:BAABLgAECn8cAAICAAkJ3wqjZwCUAQACAAkJ3wqjZwCUAQAAAA==.Barix:BAAALgAECgEJAwAAAA==.Barnd:BAAALgADCggJDwAAAA==.Barrin:BAABLgAECn81AAMNAAgJvxxJBAA4AgANAAgJvxxJBAA4AgAOAAUJQghJrADfAAAAAA==.Bastim:BAAALgAECgMJCAAAAA==.Baussassbich:BAAALgAECgQJBAAAAA==.Bawnchu:BAAALgAECgMJCAAAAA==.',
Be='Beastmaster:BAACLgAFFH8FAAIPAAMJvSBDQAALAQAPAAMJvSBDQAALAQAuAAQKfy8AAg8ACAmYJG0QALgCAA8ACAmYJG0QALgCAAAA.Beefcakell:BAAALgADCgcJDQAAAA==.Beiki:BAAALgAECgYJDwAAAA==.Belthar:BAAALgAECgQJCQAAAA==.Bently:BAABLgAECn8iAAMQAAcJpSFFHQDTAQAQAAcJ9R9FHQDTAQARAAUJGCMtEwCvAQAAAA==.Berexis:BAAALgAECgkJEQAAAA==.',
Bi='Bissafiyah:BAACLgAFFH8ZAAISAAcJiCOSAAA8AgASAAcJiCOSAAA8AgAuAAQKf0kAAhIACQm7JiIAAOkDABIACQm7JiIAAOkDAAAA.Biznasty:BAAALgAECgEJAwAAAA==.',
Bl='Bloodgon:BAABLgAFFH8HAAITAAMJUhh6cQD7AAATAAMJUhh6cQD7AAAAAA==.Bluetuesday:BAAALgAECgMJBAAAAA==.',
Bo='Bogart:BAAALgAECgEJAQAAAA==.Bohica:BAABLgAECn84AAIUAAkJRhEyNgC8AQAUAAkJRhEyNgC8AQAAAA==.Bonechop:BAAALgAECgEJAQAAAA==.Bootymeat:BAAALgADCgEJAQAAAA==.Bowtox:BAAALgAECgEJAQAAAA==.Boyakasha:BAABLgAECn8cAAIVAAYJGQsEEADwAAAVAAYJGQsEEADwAAAAAA==.',
Br='Brewfu:BAAALgADCgIJAgAAAA==.Brewpub:BAAALgADCgQJBAAAAA==.Brewsome:BAABLgAECn9BAAQMAAkJQyE3BQDsAgAMAAkJQyE3BQDsAgAWAAkJ1Rh+EAAmAgAGAAEJ0xEelgA5AAAAAA==.Bruceprime:BAAALgAECgkJAQAAAA==.Bryybryy:BAAALgAECggJDAABLgAECggJIwAWAOQaAA==.Bryycelest:BAABLgAECn8jAAIWAAgJ5BpEFQDyAQAWAAgJ5BpEFQDyAQAAAA==.Brz:BAAALgADCgcJBwAAAA==.Brådòn:BAAALgAECgYJDQAAAA==.',
Bu='Bucket:BAABLgAECn8wAAIXAAkJEhpnCABgAgAXAAkJEhpnCABgAgAAAA==.Bunkiee:BAAALgADCgkJHQAAAA==.Bunnybane:BAAALgAECgYJEAAAAA==.Burny:BAABLgAECn8aAAICAAcJVCVMJgDZAgACAAcJVCVMJgDZAgAAAA==.Buttadogg:BAAALgAECgcJDwAAAA==.',
['Bë']='Bëckey:BAAALgADCgIJAgAAAA==.',
Ca='Calyx:BAABLgAECn8dAAIYAAYJIgc3pwC2AAAYAAYJIgc3pwC2AAAAAA==.Canadani:BAAALgAECgcJDQAAAA==.Candorite:BAABLgAECn8ZAAMQAAgJwQzsTgDMAAAQAAYJuQvsTgDMAAAZAAIJKA6rLABrAAAAAA==.Caphriel:BAABLgAECn8dAAIaAAkJQB0hFAA8AgAaAAkJQB0hFAA8AgAAAA==.Capita:BAABLgAECn8cAAICAAgJjAnKmAAtAQACAAgJjAnKmAAtAQAAAA==.Captndave:BAAALgADCgMJAwAAAA==.Carsinegan:BAAALgADCgUJCwAAAA==.Cassica:BAABLgAECn8dAAMbAAcJbhlZJwCdAQAbAAcJbhlZJwCdAQAcAAIJ1gm4XABPAAAAAA==.Catchdezhanz:BAAALgADCgcJBwABLgAECgYJJgAIANUUAA==.Catskin:BAABLgAECn8hAAMdAAgJUBtTCwDkAQAdAAYJYiJTCwDkAQAEAAYJ8hsXOQCfAQAAAA==.',
Ce='Celivalasha:BAAALgADCgUJBQAAAA==.Cell:BAABLgAECn8jAAIWAAgJTSQqBQA3AwAWAAgJTSQqBQA3AwAAAA==.Cet:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.',
Ch='Chadvader:BAAALgADCgIJAgAAAA==.Chainlink:BAAALgADCgYJBgAAAA==.Chalee:BAAALgAECgEJAQAAAA==.Chandraskhar:BAAALgADCgIJAgAAAA==.Chanpagne:BAAALgAECgEJAQAAAA==.Charkle:BAAALgAECgYJDgAAAA==.Chayea:BAAALgADCgEJAQAAAA==.Chillylilly:BAABLgAECn8vAAMeAAkJbSXXAQAzAwAeAAkJbSXXAQAzAwAfAAQJ4RwiEABAAQAAAA==.Chlorophyll:BAAALgAECgQJBAAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chuckydoll:BAAALgAECgEJAQAAAA==.Chummie:BAABLgAECn8uAAMOAAkJrh+AFQCYAgAOAAkJRR+AFQCYAgANAAYJdxxDCADHAQAAAA==.',
Ci='Cielcin:BAAALgAFFAMJAwAAAA==.Ciremiih:BAAALgAECgEJAQAAAA==.Citymage:BAACLgAFFH8KAAICAAUJWAUJYgAJAQACAAUJWAUJYgAJAQAuAAQKfykAAgIACQmbF4g+AAoCAAIACQmbF4g+AAoCAAAA.Cixelsyd:BAAALgADCgYJCwABLgAFFAYJDgAHABcGAA==.',
Cl='Clamchowda:BAABLgAECn8vAAMYAAkJoBu9IgAxAgAYAAkJKxm9IgAxAgALAAUJUh5wIwCiAQAAAA==.',
Co='Codê:BAABLgAECn8mAAIOAAgJyRelOQDmAQAOAAgJyRelOQDmAQAAAA==.Coffeecup:BAAALgADCgIJAgAAAA==.Corride:BAABLgAECn8rAAIgAAgJgR/kDgAwAgAgAAgJgR/kDgAwAgAAAA==.Corspar:BAAALgAECgQJBgAAAA==.',
Cr='Crazyeyes:BAAALgADCgMJAwAAAA==.Crimsondeath:BAABLgAECn8dAAIeAAYJ6g4wLADfAAAeAAYJ6g4wLADfAAAAAA==.Crutch:BAABLgAECn8fAAMUAAkJyRyPCgD3AgAUAAkJyRyPCgD3AgASAAUJJhSIGQARAQAAAA==.Crystanikus:BAAALgAECgQJBQAAAA==.',
Cu='Cuckenjoyer:BAAALgAECgYJCgAAAA==.',
Cy='Cyclonian:BAAALgAECgEJAgABLgAECgQJBQABAAAAAA==.Cyprus:BAAALgAECgEJAQAAAA==.',
Da='Daddytrump:BAABLgAECn8aAAIGAAgJ+Q2RNgBoAQAGAAgJ+Q2RNgBoAQAAAA==.Daelric:BAAALgAECgMJAwAAAA==.Daender:BAACLgAFFH8GAAIPAAIJaxvnXwCsAAAPAAIJaxvnXwCsAAAuAAQKfy0AAw8ACQloJP0FACMDAA8ACQloJP0FACMDACEAAQmCGEw1ADYAAAAA.Daenor:BAAALgAECgQJBgAAAA==.Dairydemon:BAACLgAFFH8HAAIiAAMJwwWxCQCJAAAiAAMJwwWxCQCJAAAuAAQKfzcAAiIACQkSD4AKAJ8BACIACQkSD4AKAJ8BAAAA.Damageus:BAACLgAFFH8IAAICAAMJfhywZwD1AAACAAMJfhywZwD1AAAuAAQKfx4AAgIACAnqIjkkAOICAAIACAnqIjkkAOICAAAA.Daniryl:BAEBLgAECn8bAAIEAAgJfxWcKQD0AQAEAAgJfxWcKQD0AQAAAA==.Dar:BAAALgAECgQJCAAAAA==.Darcness:BAABLgAECn8hAAMKAAYJ2BOfDgApAQAJAAUJTxZQOABSAQAKAAYJLRGfDgApAQAAAA==.Darcside:BAABLgAECn8aAAIbAAYJhgjqRgDMAAAbAAYJhgjqRgDMAAAAAA==.Darkclouds:BAAALgADCgIJAgAAAA==.Darksoul:BAAALgAECggJEgABLgAECggJGQAjACIYAA==.Darkxwraith:BAABLgAECn8UAAIIAAcJzxeJIwDUAQAIAAcJzxeJIwDUAQAAAA==.Dashtoolite:BAABLgAECn8YAAIYAAgJ0gsEbAAxAQAYAAgJ0gsEbAAxAQAAAA==.Datsumbeech:BAABLgAECn8jAAIfAAgJMQwWEABBAQAfAAgJMQwWEABBAQAAAA==.',
De='Deajer:BAAALgADCgYJBwAAAA==.Deathsabeach:BAAALgAECgEJAQAAAA==.Deathvìxen:BAABLgAECn8XAAMbAAgJyAdCNwAVAQAbAAgJyAdCNwAVAQAjAAMJiwbXTABgAAAAAA==.Debit:BAAALgAECgcJEwAAAA==.Demonhunter:BAACLgAFFH8KAAIYAAQJkiEBLgBCAQAYAAQJkiEBLgBCAQAuAAQKfx0AAhgACAk/JKkKAC4DABgACAk/JKkKAC4DAAAA.Demonwoogie:BAAALgADCgYJBgABLgAECgQJCwABAAAAAA==.Dendrophilia:BAAALgAECgYJCgAAAA==.Densamin:BAABLgAECn8mAAQHAAgJNRVyXgCbAQAHAAgJNRVyXgCbAQAIAAIJugE2fQA9AAAkAAEJ4wtASwApAAAAAA==.Deviyn:BAAALgADCgIJAgAAAA==.Devourussy:BAAALgADCgkJCQAAAA==.Devra:BAAALgADCggJCAAAAA==.Dexter:BAAALgAECgEJAgAAAA==.Deàdly:BAABLgAECn8XAAMfAAcJLSHVBgAIAgAfAAcJLSHVBgAIAgATAAMJghnvBAGEAAAAAA==.',
Di='Dietchrist:BAAALgAECggJEwAAAA==.Dilligaf:BAAALgADCggJCAAAAA==.',
Dk='Dkanabiss:BAAALgAECgMJBAAAAA==.Dkinabox:BAAALgADCgEJAgAAAA==.',
Do='Docbaba:BAAALgAFFAEJAQAAAA==.Doh:BAAALgADCgIJAgAAAA==.Doist:BAAALgAECgIJAgAAAA==.Donngaz:BAAALgAECgMJBgAAAA==.',
Dr='Drakir:BAAALgAECgkJAQAAAA==.Dreadgnar:BAAALgAECgEJAgAAAA==.Drewnei:BAAALgADCgkJCQAAAA==.Drewserk:BAABLgAECn8pAAIaAAkJKxxKEgBOAgAaAAkJKxxKEgBOAgAAAA==.Drkxmaniac:BAAALgAECgUJCgABLgAECgcJDAABAAAAAA==.Drminnowphd:BAAALgAFFAEJAQAAAA==.Drpiscisphd:BAACLgAFFH8NAAMTAAUJ3B/LLwB4AQATAAUJ3B/LLwB4AQAeAAEJdAW/OAAlAAAuAAQKfy4AAxMACQm2IO4OACQDABMACQm2IO4OACQDAB4ABwnDBYIpAPMAAAAA.Drsaltyballz:BAABLgAECn8uAAIKAAkJyiI/AQD3AgAKAAkJyiI/AQD3AgAAAA==.Drugpala:BAAALgAECgIJAgAAAA==.Druji:BAAALgAECggJDQAAAA==.Drumuss:BAAALgADCgEJAQAAAA==.',
Du='Ducat:BAABLgAECn8WAAICAAUJsAmV5QCwAAACAAUJsAmV5QCwAAAAAA==.Dudesk:BAAALgAECgUJBgAAAA==.Duffuna:BAAALgADCgEJAQABLgAECgkJTAAgAAgmAA==.Duffunha:BAABLgAECn9MAAIgAAkJCCZnAAB/AwAgAAkJCCZnAAB/AwAAAA==.',
Dy='Dye:BAABLgAECn80AAIIAAkJhx4gBwAHAwAIAAkJhx4gBwAHAwAAAA==.Dyre:BAABLgAECn8lAAIiAAgJjw1KEAAsAQAiAAgJjw1KEAAsAQAAAA==.Dyslexic:BAACLgAFFH8FAAIlAAQJbwTuCADjAAAlAAQJbwTuCADjAAAuAAQKfyUAAiUACAkrFzYHAMYBACUACAkrFzYHAMYBAAEuAAUUBgkOAAcAFwYA.Dyspepsia:BAACLgAFFH8OAAIHAAYJFwYVLgA4AQAHAAYJFwYVLgA4AQAuAAQKfx0AAgcACQmUGdg/AO8BAAcACQmUGdg/AO8BAAAA.',
['Dô']='Dôngus:BAAALgADCgMJAwABLgAECgQJBQABAAAAAA==.',
['Dõ']='Dõngus:BAAALgAECgEJAQABLgAECgQJBQABAAAAAA==.',
['Dö']='Döngus:BAAALgAECgEJAgABLgAECgQJBQABAAAAAA==.',
Ed='Edie:BAAALgAECgEJAwAAAA==.',
Ei='Eirenn:BAAALgAECgkJBgAAAA==.',
El='Elayna:BAAALgAECgkJBwAAAA==.Elenaura:BAAALgAECgMJAwAAAA==.Eleren:BAABLgAECn8YAAIYAAcJXxHIcgAhAQAYAAcJXxHIcgAhAQAAAA==.Elimee:BAABLgAECn8wAAICAAkJoCFJDgBUAwACAAkJoCFJDgBUAwAAAA==.Elisestraza:BAABLgAFFH8FAAIQAAMJSQ1TOgC7AAAQAAMJSQ1TOgC7AAABLgAECgkJMAACAKAhAA==.Ellasia:BAAALgAECgYJEgAAAA==.Elric:BAACLgAFFH8GAAIHAAIJtAfagACGAAAHAAIJtAfagACGAAAuAAQKfzUAAgcACQlMGeIuACwCAAcACQlMGeIuACwCAAAA.Elsie:BAAALgAECgcJCwABLgAECggJHwAIAEIeAA==.Elunea:BAAALgADCgcJDQAAAA==.Elunemittens:BAAALgADCgYJBgAAAA==.',
Em='Emart:BAABLgAECn8jAAIgAAgJqw37IACHAQAgAAgJqw37IACHAQAAAA==.Emozella:BAAALgAECgEJAQAAAA==.',
En='Enatresh:BAAALgAECgcJEQAAAA==.',
Ep='Epsilon:BAAALgAECgkJCQAAAA==.',
Er='Erayna:BAABLgAECn86AAIEAAkJsRYYGgBiAgAEAAkJsRYYGgBiAgAAAA==.Ereillea:BAAALgAECgYJDQAAAA==.',
Es='Essence:BAABLgAECn8WAAMCAAgJmxTpagAAAgACAAgJDBHpagAAAgAmAAQJ1xocDAARAQAAAA==.',
Et='Etherious:BAAALgAECgcJCQABLgAECggJHwAIAEIeAA==.',
Eu='Euko:BAACLgAFFH8GAAMFAAIJqRSYMgCCAAAFAAIJqRSYMgCCAAAEAAIJwA63SgB8AAAuAAQKfzUAAwUACQkvIV0HAM0CAAUACQkvIV0HAM0CAAQACAl1FbFgAAEBAAAA.',
Ev='Evedk:BAAALgAECgkJBQAAAA==.Evepriest:BAAALgAECgEJAQAAAA==.',
Fa='Failrogue:BAAALgADCgUJCwAAAA==.Falconclaw:BAAALgADCgkJGwAAAA==.Falkensnoman:BAABLgAECn8mAAIeAAgJgBQZGQB9AQAeAAgJgBQZGQB9AQAAAA==.Fayedra:BAABLgAECn8aAAIDAAgJ1xXyEAC4AQADAAgJ1xXyEAC4AQAAAA==.',
Fc='Fcawfe:BAAALgAECgQJBAAAAA==.',
Fe='Febee:BAAALgADCgcJAQAAAA==.Feenii:BAABLgAECn86AAISAAkJUh3ABACLAgASAAkJUh3ABACLAgAAAA==.Felburst:BAAALgAECgMJAwAAAA==.Felfireqt:BAAALgAECgEJAgAAAA==.Feydros:BAAALgAECgkJBQAAAA==.',
Fi='Figgyandrii:BAAALgAECgUJBQAAAA==.Fionar:BAAALgADCgIJAgAAAA==.Fizzlelich:BAAALgADCgkJHgAAAA==.',
Fl='Flamesters:BAABLgAFFH8GAAICAAUJjAMmZwD3AAACAAUJjAMmZwD3AAAAAA==.Fluffpuff:BAAALgADCgMJAwAAAA==.',
Fm='Fmpumps:BAAALgAECgEJAQAAAA==.',
Fo='Foxdeer:BAABLgAECn8dAAMOAAgJvQg7dwBAAQAOAAgJvQg7dwBAAQANAAMJ4wKhHwB0AAAAAA==.',
Fr='Frenchtoast:BAAALgAECgUJBwAAAA==.',
Fu='Furyrage:BAAALgADCgEJAQAAAA==.Fuzzyclawz:BAAALgADCgMJAwABLgAECgkJLAAMADMQAA==.',
Ga='Gambachii:BAAALgAECgcJDQAAAA==.Gankss:BAABLgAECn8iAAMIAAkJbyIvAwBgAwAIAAkJbyIvAwBgAwAHAAEJNAGSpgEMAAAAAA==.Garakddon:BAAALgADCgkJFgABLgAECgcJHAAkADkUAA==.Garryy:BAAALgAECgMJBwAAAA==.',
Ge='Geegandolm:BAAALgADCgkJEwAAAA==.Genjaru:BAAALgAECgYJEAAAAA==.Genndalf:BAAALgADCgcJBwAAAA==.Geostorm:BAAALgAECgEJAQAAAA==.',
Gh='Gharmag:BAAALgAECgEJAQAAAA==.',
Gi='Giramar:BAABLgAECn8sAAMbAAgJnRnrFgD2AQAbAAgJnRnrFgD2AQAcAAYJjxCiNAAaAQAAAA==.',
Gl='Glagkara:BAAALgAECgIJAgAAAA==.',
Go='Gobbyshamm:BAAALgAECgEJAQAAAA==.Gobsmackers:BAAALgAECgYJBwAAAA==.Gomklin:BAAALgADCgcJCAABLgAFFAIJBwAHAMUdAA==.Goobtastic:BAAALgADCgQJBAAAAA==.Goteem:BAAALgAECggJEwAAAA==.Gothitelle:BAAALgAECgEJAgAAAA==.',
Gr='Griffhud:BAAALgAECgYJEwAAAA==.Grimrox:BAABLgAECn8kAAInAAkJYxKlHwDMAQAnAAkJYxKlHwDMAQAAAA==.Grixx:BAAALgADCgUJBQAAAA==.Groupie:BAAALgADCgUJCgABLgAECgcJGAAhANUPAA==.',
Gt='Gtatedk:BAAALgAECgEJAQAAAA==.',
Gu='Guntera:BAAALgAECgYJDgAAAA==.Guts:BAAALgADCgMJAwAAAA==.',
Gw='Gwendalyn:BAAALgAECgQJBQAAAA==.',
['Gä']='Gäz:BAAALgADCgEJAQAAAA==.',
Ha='Halexion:BAAALgADCgIJAgAAAA==.Haomaru:BAABLgAECn8XAAQEAAUJLBnkRQBkAQAEAAUJLBnkRQBkAQAdAAEJiBDMRQAwAAAFAAEJSAvRiAAoAAAAAA==.Hardcandy:BAABLgAECn8YAAIhAAcJ1Q89FgDvAAAhAAcJ1Q89FgDvAAAAAA==.Hardlyevoker:BAAALgADCgEJAQABLgAFFAIJBgAIAOYQAA==.Hawkìns:BAAALgAECgEJAQAAAA==.',
He='Heartsoul:BAAALgAECgYJCQAAAA==.Heavyarm:BAAALgADCgcJDwAAAA==.Hellork:BAAALgADCgQJBAAAAA==.Hermosura:BAAALgADCgUJCgAAAA==.Hex:BAAALgAECgYJBgAAAA==.',
Hi='Hiccups:BAAALgAECgMJBAABLgAECgkJEgABAAAAAA==.Himawarí:BAABLgAECn8aAAIXAAgJng+BGgBOAQAXAAgJng+BGgBOAQAAAA==.Hiyank:BAABLgAECn8jAAIWAAkJrCJeBgDFAgAWAAkJrCJeBgDFAgAAAA==.',
Ho='Hoffmin:BAABLgAECn8UAAMYAAcJnRnXYgBJAQAYAAYJnRnXYgBJAQALAAIJphK0VgCMAAAAAA==.Holemeister:BAACLgAFFH8IAAIHAAMJnCO6MwAsAQAHAAMJnCO6MwAsAQAuAAQKfy8AAgcACAmhJOINAB8DAAcACAmhJOINAB8DAAAA.Holyfresh:BAAALgADCgEJAQAAAA==.Holymann:BAABLgAECn8jAAIbAAcJRQ3kQADnAAAbAAcJRQ3kQADnAAAAAA==.Holyschnikey:BAABLgAECn8mAAIIAAYJ1RTiOQBMAQAIAAYJ1RTiOQBMAQAAAA==.Holyz:BAABLgAECn82AAMIAAkJpCOMAQCWAwAIAAkJpCOMAQCWAwAHAAEJBhkrSAFLAAAAAA==.Horgable:BAAALgADCgIJAgAAAA==.Horrorpops:BAAALgADCgUJBQAAAA==.Hozaki:BAAALgAECgQJBAABLgAECgcJDAABAAAAAA==.',
Hu='Hudfin:BAAALgADCgUJBQAAAA==.Hundred:BAAALgAECgIJAgAAAA==.Huntinwoogie:BAAALgADCgUJBQABLgAECgQJCwABAAAAAA==.',
['Hí']='Hílthaen:BAABLgAECn80AAIcAAgJ4hZqFAAcAgAcAAgJ4hZqFAAcAgAAAA==.',
Ic='Icebones:BAAALgADCgcJDAABLgAECgQJCQABAAAAAA==.Icelight:BAAALgAECgQJCQAAAA==.Ichigokisu:BAAALgAECgUJDgAAAA==.',
Il='Illiduji:BAAALgADCgMJAwAAAA==.Illy:BAABLgAECn8jAAIYAAkJ+hZLKQAPAgAYAAkJ+hZLKQAPAgAAAA==.',
Im='Imposed:BAAALgAECgcJEAAAAA==.',
In='Instantdeath:BAAALgAECgcJDAAAAA==.Invali:BAAALgAECgUJCAAAAA==.',
Io='Iorla:BAAALgADCgYJAQAAAA==.',
Ir='Irônhide:BAAALgAECgEJAQAAAA==.',
Iv='Ivranda:BAAALgADCgkJEgABLgAECggJGQAQAMEMAA==.',
Iz='Iz:BAAALgAECgEJAQAAAA==.',
Ja='Jaapp:BAAALgAECgMJBgAAAA==.Jahan:BAACLgAFFH8IAAIjAAMJsRkhJQDwAAAjAAMJsRkhJQDwAAAuAAQKfy8AAyMACQlZIfYEACUDACMACAkiJPYEACUDABsABAmAEc0+APEAAAEuAAQKAwkDAAEAAAAA.Jamie:BAABLgAFFH8IAAITAAMJhCPHVAAtAQATAAMJhCPHVAAtAQABLgAFFAgJGQAOAAAhAA==.Jaydine:BAAALgADCgYJBgABLgAECgkJMAACAKAhAA==.',
Je='Jeri:BAAALgAECgYJBwAAAA==.',
Jh='Jhie:BAABLgAECn8UAAIMAAcJ/hLlJgBnAQAMAAcJ/hLlJgBnAQAAAA==.',
Ji='Jinro:BAAALgAECgEJAgABLgAECgEJAgABAAAAAA==.',
Ju='Jud:BAAALgAECggJEAAAAA==.Juviâ:BAAALgAECggJCQABLgAECggJHwAIAEIeAA==.Juxtaposed:BAAALgADCgUJBQAAAA==.',
Ka='Kaelora:BAAALgAECgMJAwAAAA==.Kaerei:BAABLgAECn8sAAIHAAkJnh7zGwCFAgAHAAkJnh7zGwCFAgAAAA==.Kaleb:BAABLgAECn8hAAILAAgJtiE9CQB7AgALAAgJtiE9CQB7AgAAAA==.Kalfalah:BAABLgAECn8hAAQFAAcJdRfaIgCZAQAFAAcJEBfaIgCZAQAdAAMJHhSyJgCxAAAEAAEJRAqA0wAmAAAAAA==.Kalferno:BAAALgAECgQJCgAAAA==.Kalirkaz:BAACLgAFFH8IAAIEAAMJRweXQAChAAAEAAMJRweXQAChAAAuAAQKfy4AAwQACQnyGpwSAKYCAAQACQnyGpwSAKYCAAUABQk5Bh9bAIoAAAAA.Kallipsa:BAAALgAECgMJAwAAAA==.Karasu:BAAALgAECggJCgABLgAECgkJLAAMADMQAA==.Karst:BAAALgAECgQJBQABLgAECgMJAwABAAAAAA==.Kathria:BAAALgAECgcJDQAAAA==.',
Ke='Keepcrying:BAAALgAECgEJAQAAAA==.Kegendary:BAAALgAECgQJCAAAAA==.Keler:BAAALgAECgEJAQABLgAECgMJBwABAAAAAA==.Kelideyn:BAAALgAECgYJBgAAAA==.Keládry:BAABLgAECn8WAAIIAAYJXhhRLgCOAQAIAAYJXhhRLgCOAQAAAA==.Keskiyö:BAAALgADCgkJFQABLgAECgkJLAAMADMQAA==.',
Kh='Khaalid:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.Khallock:BAABLgAECn8iAAINAAYJjRhxDABxAQANAAYJjRhxDABxAQAAAA==.Khamael:BAAALgAECgEJAQAAAA==.',
Ki='Kiemen:BAABLgAECn8oAAMTAAkJHRpZMAApAgATAAkJHRpZMAApAgAfAAEJbQ7VLwA1AAAAAA==.Kierya:BAAALgAECgEJAgAAAA==.Killerpoison:BAAALgAECgkJBQAAAA==.Killko:BAACLgAFFH8GAAITAAIJbg8csACTAAATAAIJbg8csACTAAAuAAQKfxsAAhMACQn+G2cmAFUCABMACQn+G2cmAFUCAAAA.Kinki:BAAALgAECgMJAwABLgAECgcJGAAhANUPAA==.Kirisen:BAAALgAECgUJCQAAAA==.Kitan:BAAALgAECgQJBQAAAA==.Kitani:BAAALgADCgkJGAABLgAECgkJOAAjAIAcAA==.',
Ko='Konno:BAAALgAECgQJBAABLgAFFAcJGQASAIgjAA==.Kooterr:BAAALgADCgUJBQAAAA==.Korbix:BAABLgAECn8XAAITAAYJWhuOagB8AQATAAYJWhuOagB8AQAAAA==.',
Kr='Kragsloor:BAAALgAECgEJAQAAAA==.Kredorin:BAAALgAECgYJCgAAAA==.Krewella:BAAALgADCgcJBwAAAA==.Krickette:BAAALgAECgYJBgAAAA==.Krihl:BAAALgAECgkJBgAAAA==.Krovmar:BAAALgADCgUJBQAAAA==.',
Ks='Kspanxx:BAAALgAECgMJAwAAAA==.',
Kt='Kthanx:BAAALgAECgMJAQAAAA==.',
Ku='Kungpowgazer:BAABLgAECn8VAAMWAAgJaB3bDwAuAgAWAAgJaB3bDwAuAgAMAAEJew+yjwAvAAAAAA==.Kunls:BAABLgAECn8eAAILAAgJrgixJgAfAQALAAgJrgixJgAfAQAAAA==.Kuraak:BAAALgADCgYJBgAAAA==.Kuraki:BAABLgAECn8aAAIMAAgJgAolLwA0AQAMAAgJgAolLwA0AQAAAA==.Kurasa:BAABLgAECn8sAAMMAAkJMxAKHgCnAQAMAAkJMxAKHgCnAQAGAAQJowH4WgBjAAAAAA==.Kutraz:BAAALgAECgQJBQAAAA==.',
La='Ladrar:BAAALgAECgcJEQAAAA==.Laelina:BAAALgAECgEJAwAAAA==.Lanadiel:BAACLgAFFH8GAAIkAAIJyxjuCwCdAAAkAAIJyxjuCwCdAAAuAAQKfzUAAiQACQmIIjMCAAEDACQACQmIIjMCAAEDAAAA.Lazz:BAABLgAECn8UAAQgAAcJpiHmEgAEAgAgAAcJpiHmEgAEAgAhAAQJ5RkJQQBVAQAPAAEJAACcLQEAAAAAAA==.',
Le='Legend:BAACLgAFFH8VAAIYAAUJASF7JgBiAQAYAAUJASF7JgBiAQAuAAQKfzIAAhgACQm3IDAJAD4DABgACQm3IDAJAD4DAAAA.Lekrotar:BAAALgAECgQJBAAAAA==.Letsyoudie:BAAALgAECgMJAwAAAA==.',
Li='Lian:BAAALgAECgYJEQAAAA==.Lichbane:BAABLgAECn81AAITAAkJmCEBEwDEAgATAAkJmCEBEwDEAgAAAA==.Licun:BAAALgAECgYJDQAAAA==.Lifexdeath:BAABLgAECn8ZAAMcAAcJ5Qb6OwDuAAAcAAcJ5Qb6OwDuAAAbAAEJxgNUhAAkAAAAAA==.Lightcell:BAAALgAECgQJBgAAAA==.Liliara:BAABLgAECn80AAIPAAkJ3BBlPADXAQAPAAkJ3BBlPADXAQAAAA==.Lillyirl:BAAALgAECgUJEQAAAA==.Lillymae:BAAALgAECggJDAAAAA==.Lillyslight:BAAALgADCgYJBgAAAA==.Lillysneak:BAAALgADCgUJCgAAAA==.Lillytae:BAAALgAECgQJBwAAAA==.Lillyzard:BAAALgAECgEJAQAAAA==.Lilmoo:BAAALgAECgcJDwAAAA==.Linkhunter:BAAALgAECgYJBgABLgAECgkJLQAjALMUAA==.Linni:BAABLgAECn8fAAIIAAgJQh55DACzAgAIAAgJQh55DACzAgAAAA==.Lizardwizard:BAAALgAECgQJBAAAAA==.',
Lo='Lockgodtko:BAAALgAECgcJDQAAAA==.Lodise:BAABLgAECn8hAAMNAAkJLw4iCwCLAQANAAkJLw4iCwCLAQAOAAEJAAgZHQEyAAAAAA==.Lonful:BAAALgADCgEJAQAAAA==.Lorzz:BAACLgAFFH8IAAIcAAMJCg8YHQCsAAAcAAMJCg8YHQCsAAAuAAQKfzYAAhwACQk8ILEEACUDABwACQk8ILEEACUDAAAA.Lothe:BAABLgAECn8aAAIIAAgJxh60DACwAgAIAAgJxh60DACwAgAAAA==.',
Lu='Lucrio:BAABLgAECn87AAITAAkJNharLQA1AgATAAkJNharLQA1AgAAAA==.Ludoe:BAAALgADCgkJMQAAAA==.Luminariah:BAAALgAECgYJCQAAAA==.Luna:BAAALgAECgUJEgAAAA==.Lunalai:BAABLgAECn9BAAIDAAkJ3iLpAQAbAwADAAkJ3iLpAQAbAwAAAA==.Lurim:BAAALgAECgEJAQABLgAECggJIwAkAI8eAA==.Lushy:BAAALgAECgkJEgAAAA==.',
Ly='Lylineth:BAAALgADCgYJBgAAAA==.Lylinette:BAAALgAECgcJEgAAAA==.Lyssandra:BAAALgADCgUJBQAAAA==.',
['Lí']='Lízandor:BAACLgAFFH8XAAIHAAUJEhDHOwAdAQAHAAUJEhDHOwAdAQAuAAQKfykAAgcACQmYHIclAFYCAAcACQmYHIclAFYCAAAA.',
['Lû']='Lûsøn:BAAALgAECgEJAQAAAA==.',
Ma='Madruskee:BAABLgAECn8fAAIfAAYJDBcsDwBPAQAfAAYJDBcsDwBPAQAAAA==.Magahpt:BAAALgAECgMJBAAAAA==.Magdea:BAAALgADCgYJBgAAAA==.Mageofdeath:BAAALgAECgMJBAABLgAECgcJDAABAAAAAA==.Mageofhonor:BAAALgAECgEJAQAAAA==.Magistroll:BAABLgAECn8cAAICAAcJXgWHzADXAAACAAcJXgWHzADXAAAAAA==.Maladaptive:BAAALgAECgEJAQAAAA==.Malevohaynk:BAAALgAECgQJBQABLgAECgkJIwAWAKwiAA==.Mandrallea:BAAALgADCgIJAgAAAA==.Maryshelley:BAAALgADCgMJAwAAAA==.Matoo:BAAALgADCgEJAQAAAA==.Maurin:BAAALgAECgYJBgAAAA==.Maximumhonk:BAABLgAECn8mAAIUAAYJmxMBTgBbAQAUAAYJmxMBTgBbAQAAAA==.',
Me='Melfys:BAAALgAECgEJAQAAAA==.Melquisedec:BAAALgAECgIJAgAAAA==.Mendelia:BAABLgAECn8gAAIkAAgJUxRODwCzAQAkAAgJUxRODwCzAQAAAA==.Mercus:BAABLgAECn8ZAAMVAAkJ9RgiBgBqAQAVAAYJpBQiBgBqAQAJAAgJLxpmLAAcAQAAAA==.Merkstrasza:BAAALgAECgYJDgAAAA==.Mervenious:BAABLgAECn8WAAQaAAcJjgzpPgA0AQAaAAcJHwvpPgA0AQAoAAMJWgtrRwCPAAAXAAMJpQhrOQB/AAAAAA==.Meu:BAAALgAECggJBgAAAA==.',
Mi='Midasdh:BAACLgAFFH8OAAIYAAUJ0wtVRQD+AAAYAAUJ0wtVRQD+AAAuAAQKfxwAAxgACAmAF5Y+APoBABgACAnfFJY+APoBAAsABgmOFwMwAE8BAAAA.Midasdk:BAACLgAFFH8NAAITAAUJEhoFTAA7AQATAAUJEhoFTAA7AQAuAAQKfxwAAxMABwnMHG9PAAQCABMABwm9GW9PAAQCAB8AAwkzEk4fAJ8AAAEuAAUUBQkOABgA0wsA.Midasmonk:BAAALgAECgEJAQABLgAFFAUJDgAYANMLAA==.Midasshift:BAAALgAECgcJDwAAAA==.Miladepollo:BAAALgADCgMJAwAAAA==.Mindblank:BAAALgAECgQJBAAAAA==.Mindplague:BAABLgAECn8oAAIbAAcJAiCjFgD4AQAbAAcJAiCjFgD4AQAAAA==.Minipincin:BAAALgAECgEJAQAAAA==.Minisicwidit:BAAALgADCgMJAwAAAA==.Miroslava:BAAALgAECgEJAQAAAA==.Mistdeeznuts:BAACLgAFFH8FAAIGAAIJAAR9QwBUAAAGAAIJAAR9QwBUAAAuAAQKfx8AAwYACQmWDKIwAIgBAAYACQmWDKIwAIgBAAwAAQmSA7umAB4AAAAA.',
Mo='Mogwaï:BAAALgAECgYJCAAAAA==.Mokokoma:BAAALgAECgMJBAAAAA==.Moonde:BAAALgAECgkJDwAAAA==.Moonscale:BAABLgAECn80AAIRAAkJHR+aAQDGAgARAAkJHR+aAQDGAgAAAA==.Moosayer:BAAALgAECgQJBgAAAA==.Moovement:BAAALgAECgMJAwABLgAECgYJBgABAAAAAA==.Mossed:BAAALgADCgMJAwAAAA==.',
Ms='Mskelsier:BAAALgAECgUJBQAAAA==.',
Mt='Mtaur:BAAALgADCggJDwAAAA==.',
Mu='Muclor:BAAALgADCgcJBwABLgAFFAMJAwABAAAAAA==.Mustang:BAAALgAECgUJBQAAAA==.',
My='Mythalis:BAAALgAECgQJBQAAAA==.',
['Mä']='Märändus:BAAALgADCgEJAQAAAA==.',
['Må']='Måzikeen:BAAALgADCgMJAwAAAA==.',
Na='Narse:BAABLgAFFH8GAAIcAAIJvwjyJwBhAAAcAAIJvwjyJwBhAAAAAA==.Narz:BAABLgAECn82AAIPAAkJoRLYNQDuAQAPAAkJoRLYNQDuAQAAAA==.Nastianna:BAAALgAECgQJCgAAAA==.Natgeo:BAAALgAECgkJEAABLgAECgkJLQAjALMUAA==.Nazumi:BAABLgAECn8mAAIMAAgJWh2GDgBKAgAMAAgJWh2GDgBKAgAAAA==.',
Nd='Ndiz:BAABLgAECn8VAAIPAAcJIhwCJwAdAgAPAAcJIhwCJwAdAgAAAA==.',
Ne='Necronomikon:BAAALgADCgEJAQAAAA==.Neeva:BAAALgADCgYJEAAAAA==.Nelrya:BAEALgADCgcJDQABLgAFFAQJCAAHANwOAA==.Nephilym:BAAALgAECgEJAQAAAA==.Nerhzul:BAAALgAECgcJCAAAAA==.Neruphuyt:BAABLgAECn8xAAIFAAgJVhLeIwCSAQAFAAgJVhLeIwCSAQAAAA==.',
Ni='Niath:BAAALgAECgEJAgAAAA==.Nightsniper:BAABLgAECn8VAAIPAAkJyBnnPADVAQAPAAkJyBnnPADVAQAAAA==.Ninfassins:BAAALgADCgIJAgAAAA==.',
No='Norintha:BAAALgADCgEJAQAAAA==.Norolen:BAAALgADCgIJAgAAAA==.',
Ny='Nyxiel:BAAALgAECgQJBQAAAA==.',
Oa='Oak:BAAALgAECgkJEgAAAA==.',
Oc='Occo:BAAALgADCgEJAQAAAA==.',
Og='Ogroc:BAAALgAECgQJBAAAAA==.',
Ok='Okioak:BAAALgAECgkJEgAAAA==.',
Ol='Olgon:BAACLgAFFH8KAAIPAAQJug1TNgAoAQAPAAQJug1TNgAoAQAuAAQKfzoAAg8ACQmvGtoXAIACAA8ACQmvGtoXAIACAAAA.Olstinkyboot:BAAALgAECgEJAQAAAA==.',
Op='Oprhawinfury:BAABLgAECn8iAAITAAkJRA5yWgCjAQATAAkJRA5yWgCjAQAAAA==.',
Or='Orgodemir:BAAALgADCgkJDwAAAA==.',
Ot='Otemoto:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
Ou='Ouin:BAAALgAECgEJAQABLgAECgkJLwAnAHITAA==.',
Ox='Oxley:BAAALgAECgEJAgAAAA==.',
Pa='Paigor:BAAALgAECgIJAgAAAA==.Pakswagger:BAABLgAECn8XAAMZAAYJFRe6EgCKAQAZAAYJFRe6EgCKAQAQAAMJRQR0dABVAAAAAA==.Pallyberry:BAABLgAECn8xAAIIAAkJZhvmDQCgAgAIAAkJZhvmDQCgAgAAAA==.Pancake:BAAALgAECgEJAQAAAA==.Pandemonia:BAABLgAECn8zAAMlAAkJ5Q0rFgCYAQAlAAgJHgwrFgCYAQAOAAkJJw0BYgBxAQAAAA==.Paprika:BAAALgADCgkJEAAAAA==.Parsie:BAAALgAECgcJCQAAAA==.Patch:BAAALgADCgYJBgAAAA==.Pathibas:BAAALgADCgEJAQABLgAECgkJSwAaAKUkAA==.Pattycakes:BAABLgAECn8jAAITAAkJLBYPQgDpAQATAAkJLBYPQgDpAQAAAA==.',
Pe='Pencil:BAACLgAFFH8UAAIOAAQJTBv5MABZAQAOAAQJTBv5MABZAQAuAAQKfxsABA4ACAkwHe00APgBAA4ACAkwHe00APgBACUAAwniBj1dAFcAAA0AAQkAANAsAEUAAAAA.Pewpewlvltwo:BAACLgAFFH8IAAISAAMJCAceDADJAAASAAMJCAceDADJAAAuAAQKfygAAhIACAnQHvcHAC4CABIACAnQHvcHAC4CAAAA.Pewthree:BAAALgAECgYJCAABLgAFFAMJCAASAAgHAA==.',
Ph='Pherocious:BAABLgAECn8VAAIhAAUJ6xOGFwDhAAAhAAUJ6xOGFwDhAAAAAA==.',
Pi='Pintsize:BAAALgADCgIJAgAAAA==.',
Pl='Plaguelis:BAAALgADCgEJAQABLgAECgkJOgASAFIdAA==.Plexy:BAAALgAECgcJCgABLgAFFAEJAQABAAAAAA==.',
Po='Pobble:BAAALgADCgcJBwAAAA==.Pokitz:BAABLgAECn84AAIHAAkJBw1nZwCHAQAHAAkJBw1nZwCHAQAAAA==.Poprock:BAAALgAECgEJAQAAAA==.Potus:BAAALgADCgQJBAAAAA==.',
Pr='Primordinor:BAACLgAFFH8FAAInAAMJ8BJ2KgDJAAAnAAMJ8BJ2KgDJAAAuAAQKfyMAAycACQlVHRUWABwCACcACQlVHRUWABwCABQABwnTFwUtAOoBAAAA.Probnotalive:BAABLgAECn8gAAIPAAkJuhhvKwAZAgAPAAkJuhhvKwAZAgAAAA==.Probnotferal:BAAALgAECgEJAQAAAA==.Probnoturmom:BAABLgAECn8dAAIcAAgJVxt2GAAYAgAcAAgJVxt2GAAYAgAAAA==.',
Ra='Raevyn:BAAALgAECgEJAQAAAA==.Rafaiel:BAAALgAECgQJBAAAAA==.Rakan:BAABLgAECn9BAAIoAAkJPh4jBQCjAgAoAAkJPh4jBQCjAgAAAA==.Rakasha:BAAALgADCgkJCQAAAA==.Rallick:BAACLgAFFH8IAAIIAAMJWg2ULACxAAAIAAMJWg2ULACxAAAuAAQKfzEAAggACQm3GIQOAJcCAAgACQm3GIQOAJcCAAAA.Ranì:BAACLgAFFH8GAAIXAAIJZwZFIQBnAAAXAAIJZwZFIQBnAAAuAAQKfzUAAhcACQnxF4EOAOoBABcACQnxF4EOAOoBAAAA.Rathger:BAAALgAECggJEgAAAA==.Ravenscythe:BAAALgADCgEJAQAAAA==.Raydor:BAAALgAECggJDgAAAA==.',
Re='Reb:BAABLgAECn8mAAIbAAkJ6gSNNgAZAQAbAAkJ6gSNNgAZAQAAAA==.Redic:BAAALgAECgMJAwAAAA==.Regis:BAAALgAECgYJBgABLgAECggJJgAGAKAdAA==.Rellix:BAAALgADCgUJBQAAAA==.Rendkick:BAAALgADCgcJBwAAAA==.Rendwee:BAABLgAECn83AAIdAAkJryJ5AQAbAwAdAAkJryJ5AQAbAwAAAA==.Reuel:BAAALgAECgUJCQAAAA==.Rewolf:BAAALgAECggJEgAAAA==.',
Rh='Rheemus:BAAALgADCgYJBgAAAA==.Rhul:BAAALgAECgUJCQAAAA==.',
Ri='Ricflairion:BAABLgAECn8bAAIQAAgJTQn/PQARAQAQAAgJTQn/PQARAQAAAA==.Rimuru:BAAALgAECgEJAwABLgAECgMJBwABAAAAAA==.',
Ro='Roadrunner:BAACLgAFFH8NAAIPAAQJeAuqOwAaAQAPAAQJeAuqOwAaAQAuAAQKfzEAAg8ACQkLE7c7ANkBAA8ACQkLE7c7ANkBAAAA.Rodcet:BAACLgAFFH8HAAIHAAIJxR0obACrAAAHAAIJxR0obACrAAAuAAQKfzwAAgcACQnBJdQDAE8DAAcACQnBJdQDAE8DAAAA.Roflcopterr:BAABLgAECn8wAAQIAAgJghzrDwCFAgAIAAgJghzrDwCFAgAHAAYJ9QeI1ADOAAAkAAEJSAWlUQAZAAAAAA==.Rognan:BAAALgAECgMJAwAAAA==.Romina:BAAALgADCgEJBAAAAA==.Rookgue:BAACLgAFFH8FAAIKAAQJJAc/BQAWAQAKAAQJJAc/BQAWAQAuAAQKfzcAAgoACAkJFgcHANsBAAoACAkJFgcHANsBAAAA.Rookoker:BAABLgAECn8aAAIRAAcJ4QgNDwAJAQARAAcJ4QgNDwAJAQAAAA==.Rootsafarian:BAAALgADCgcJBwAAAA==.Rossa:BAAALgAECgEJAQAAAA==.Rossdair:BAAALgAECgYJCQABLgADCgUJCQABAAAAAA==.Rossperot:BAACLgAFFH8HAAITAAIJzx+2lgDAAAATAAIJzx+2lgDAAAAuAAQKfykAAhMACQmCIYgPAN4CABMACQmCIYgPAN4CAAAA.Rothschild:BAAALgADCgEJAQAAAA==.Rottenfist:BAAALgAECgEJAQAAAA==.',
Ru='Ruknar:BAAALgAECgMJAwAAAA==.',
Sa='Sabako:BAAALgADCgcJCAAAAA==.Sacra:BAAALgADCgUJBQABLgAECgMJAwABAAAAAA==.Saelara:BAAALgADCgcJCgAAAA==.Saelis:BAAALgADCgQJBAAAAA==.Sakaru:BAABLgAECn8bAAICAAgJTw6ffQBiAQACAAgJTw6ffQBiAQABLgAECgkJLAAMADMQAA==.Salmoney:BAAALgAECgQJBAAAAA==.Salorin:BAAALgADCgYJCQAAAA==.Samgee:BAACLgAFFH8UAAIHAAQJ+hYbLAA+AQAHAAQJ+hYbLAA+AQAuAAQKf0YAAgcACQlgIT0UALQCAAcACQlgIT0UALQCAAAA.Sandormu:BAAALgADCgkJCQAAAA==.Saphas:BAAALgAECgMJAwAAAA==.Saynar:BAABLgAECn89AAIYAAkJxCOPBAAwAwAYAAkJxCOPBAAwAwAAAA==.',
Sc='Scattered:BAABLgAECn8bAAQOAAkJohM1agBcAQAOAAcJsBI1agBcAQAlAAMJJBRLQACzAAANAAEJggv8OAAtAAAAAA==.Scooter:BAAALgAECgUJCgAAAA==.Scyx:BAAALgADCgEJAQAAAA==.',
Se='Seba:BAACLgAFFH8LAAICAAMJ1QxNcgDdAAACAAMJ1QxNcgDdAAAuAAQKfzkAAgIACQlOIPoUAMYCAAIACQlOIPoUAMYCAAAA.Sebushko:BAAALgADCgMJAQABLgAFFAMJCwACANUMAA==.Selesne:BAABLgAECn8aAAIVAAgJeAhVDQAjAQAVAAgJeAhVDQAjAQAAAA==.Seraphicktwo:BAABLgAECn8gAAMcAAYJ7BjcJACHAQAcAAYJ7BjcJACHAQAbAAUJBRDdRwDJAAAAAA==.Seriana:BAABLgAECn8WAAIcAAgJfwu/MQAsAQAcAAgJfwu/MQAsAQAAAA==.Sermidas:BAACLgAFFH8KAAMoAAMJqRv9HADZAAAoAAMJqRv9HADZAAAaAAIJ3AevGwCYAAAuAAQKfyIAAygACQk6H7gCAPACACgACQk6H7gCAPACABoABwnOFFw0ANgBAAEuAAUUBQkOABgA0wsA.',
Sh='Shadowcutter:BAAALgAECgEJAwABLgAECgcJDAABAAAAAA==.Shaggmz:BAABLgAECn8dAAIaAAYJjxTVNwBSAQAaAAYJjxTVNwBSAQAAAA==.Shigglez:BAAALgADCgEJAQAAAA==.Shinakuma:BAAALgAECgUJDgAAAA==.Shinma:BAABLgAECn8dAAIkAAYJQAY2LwCSAAAkAAYJQAY2LwCSAAAAAA==.Shrubbery:BAABLgAECn8VAAIOAAcJ+wNWswDTAAAOAAcJ+wNWswDTAAAAAA==.Shymary:BAABLgAECn8dAAIjAAYJcwVdQgDUAAAjAAYJcwVdQgDUAAAAAA==.',
Si='Siete:BAAALgAECgEJAQABLgAECgQJCQABAAAAAA==.Silvertip:BAAALgADCggJFQAAAA==.Silëx:BAABLgAECn8ZAAICAAgJXRcEUADUAQACAAgJXRcEUADUAQAAAA==.Sioc:BAAALgADCgEJAQAAAA==.Siouxiesioux:BAAALgADCgYJCgAAAA==.Siyona:BAAALgADCgkJDAAAAA==.',
Sk='Skits:BAAALgAECgIJAgAAAA==.Skyrah:BAAALgAECgYJBgAAAA==.Skyrie:BAAALgADCgQJBQAAAA==.',
Sl='Slagbröder:BAAALgADCgcJBwAAAA==.Slohine:BAAALgAECgUJBQAAAA==.Sludgecrush:BAAALgAECgYJCwAAAA==.Slugondeez:BAACLgAFFH8GAAIIAAIJ5hAKNwBxAAAIAAIJ5hAKNwBxAAAuAAQKfxYAAggABQkWIwYfAPQBAAgABQkWIwYfAPQBAAAA.',
Sm='Smallmike:BAAALgAECgIJAgAAAA==.Smitefist:BAAALgAECgIJAgABLgAECgQJBQABAAAAAA==.Smokiee:BAABLgAECn8XAAIEAAcJ7xGYQgB0AQAEAAcJ7xGYQgB0AQAAAA==.',
Sn='Snailtrail:BAABLgAECn8ZAAIiAAkJTgQqEwABAQAiAAkJTgQqEwABAQAAAA==.Snark:BAAALgAECgYJEwAAAA==.Snarkkin:BAAALgAECgQJDAABLgAECgYJEwABAAAAAA==.Snowkim:BAABLgAECn8bAAIkAAgJmh0hCwD8AQAkAAgJmh0hCwD8AQAAAA==.Snuzzle:BAABLgAECn80AAIDAAgJ3hsnCwARAgADAAgJ3hsnCwARAgAAAA==.',
So='Soniic:BAAALgAECgIJAgAAAA==.Soullessfros:BAABLgAECn8mAAITAAkJ7RM7NgASAgATAAkJ7RM7NgASAgAAAA==.Soullessman:BAAALgADCgQJCAAAAA==.Sourmash:BAAALgADCgkJCgAAAA==.',
Sp='Spaghet:BAABLgAECn8fAAInAAkJNRlvGgD2AQAnAAkJNRlvGgD2AQAAAA==.Spillthetea:BAAALgAECggJEgAAAA==.Sploot:BAAALgAECggJEAAAAA==.',
Sq='Squibbles:BAAALgAECgEJAQAAAA==.',
Sr='Srasjet:BAABLgAECn8iAAIUAAgJSxzoEwCTAgAUAAgJSxzoEwCTAgAAAA==.',
Ss='Ssimba:BAAALgAECggJDQAAAA==.',
St='Stabytha:BAABLgAECn8YAAMJAAgJIhGIJABWAQAJAAcJBBCIJABWAQAKAAEJ1RfRIQA+AAAAAA==.Stark:BAAALgADCgYJCgAAAA==.Starlight:BAAALgAECgEJAQAAAA==.Stealthed:BAAALgAECgcJDQAAAA==.Stender:BAAALgAECgcJDAABLgAFFAYJDwALAK8fAA==.Stormae:BAAALgADCgMJAgAAAA==.Stormcall:BAABLgAECn8WAAIUAAcJoRxRIAA0AgAUAAcJoRxRIAA0AgAAAA==.Stratusfied:BAAALgAECgMJBQAAAA==.',
Su='Susbandaid:BAAALgADCgYJBgAAAA==.',
Sw='Sweetiefox:BAACLgAFFH8JAAICAAUJIwPnZwD0AAACAAUJIwPnZwD0AAAuAAQKfxgAAgIACQkACi55AGsBAAIACQkACi55AGsBAAAA.Swiss:BAABLgAECn8aAAInAAgJ2A9tMABkAQAnAAgJ2A9tMABkAQAAAA==.',
Sy='Syllai:BAAALgAECgYJBgAAAA==.Symboli:BAAALgADCgQJBAAAAA==.Syphus:BAAALgADCgQJBAAAAA==.',
['Sá']='Sáëgárón:BAABLgAECn8YAAMaAAgJJxN7KwCSAQAaAAgJJxN7KwCSAQAoAAEJpwXPcwAlAAAAAA==.',
Ta='Tacyon:BAAALgADCggJDwAAAA==.Taliden:BAAALgAECgYJDAAAAA==.Tallera:BAAALgADCgEJAgAAAA==.Taniyah:BAAALgAECgQJCAAAAA==.Tankinstine:BAAALgADCgEJAgAAAA==.Taraylda:BAABLgAECn8ZAAMjAAgJIhgMGgDIAQAjAAgJIhgMGgDIAQAbAAIJqgpDYwBgAAAAAA==.Tarful:BAAALgADCgQJBAAAAA==.Tarzand:BAAALgADCgEJAQABLgADCgcJDwABAAAAAA==.Tazo:BAABLgAECn8pAAIHAAgJ4RCaZgCIAQAHAAgJ4RCaZgCIAQAAAA==.',
Te='Tearek:BAACLgAFFH8FAAIYAAMJWw8kVQDMAAAYAAMJWw8kVQDMAAAuAAQKfx0AAhgABwlVHDQ1ANsBABgABwlVHDQ1ANsBAAAA.Tearik:BAAALgAECgYJBAAAAA==.Tecdor:BAAALgAECgQJBAAAAA==.Temla:BAACLgAFFH8GAAIPAAIJMgSTdACDAAAPAAIJMgSTdACDAAAuAAQKfy8AAg8ACQlHFiwyAP0BAA8ACQlHFiwyAP0BAAAA.Tenga:BAAALgAECgQJBAAAAA==.Teronfiggy:BAABLgAECn8cAAITAAgJjA5XcQBtAQATAAgJjA5XcQBtAQAAAA==.',
Tf='Tfirs:BAACLgAFFH8SAAIDAAQJKQ9+DwDeAAADAAQJKQ9+DwDeAAAuAAQKfy8AAgMACAm+GywHAEsCAAMACAm+GywHAEsCAAEuAAEKCQkSAAEAAAAA.',
Th='Thartilidan:BAAALgAECgYJEQABLgAECgkJEgABAAAAAA==.Thegoodboi:BAAALgAECgEJAQAAAA==.Theokoles:BAAALgAECgQJBQAAAA==.Thepaladin:BAAALgADCgMJAwAAAA==.Thickblòód:BAAALgAFFAEJAQAAAA==.',
Ti='Tilythia:BAAALgADCgUJBQAAAA==.',
To='Tona:BAAALgADCgMJAwAAAA==.Toospookie:BAAALgADCgQJAgAAAA==.Tophu:BAAALgADCgcJBwAAAA==.Torkz:BAAALgADCgEJAgAAAA==.',
Tr='Tramplip:BAABLgAECn8lAAIlAAgJoRAuDABeAQAlAAgJoRAuDABeAQAAAA==.Treecloud:BAABLgAECn9HAAMFAAkJXSQNAwAvAwAFAAkJXSQNAwAvAwADAAkJhBaSCwAJAgAAAA==.Trevian:BAABLgAECn8aAAIHAAgJtBNLWgClAQAHAAgJtBNLWgClAQAAAA==.Trinitee:BAAALgAECgEJAQABLgAECgMJBwABAAAAAA==.',
Tu='Tub:BAAALgAECgQJBAABLgAFFAQJDAAMAHwLAA==.Tuluxxi:BAABLgAECn9MAAIUAAkJ8CJcAwB1AwAUAAkJ8CJcAwB1AwAAAA==.Turbodiesell:BAAALgAECgEJAgAAAA==.Turborunic:BAAALgADCgkJGwAAAA==.Turiae:BAACLgAFFH8OAAMQAAUJ1Ro/HABFAQAQAAQJ1Ro/HABFAQARAAEJAAA7DwAAAAAuAAQKfy8ABBAACQlVItQDAB0DABAACQlVItQDAB0DABEABwnZFsgQANEBABkABQkhCaQ0AMgAAAAA.Tuskerz:BAAALgAECgEJAwAAAA==.Tusobrinna:BAAALgAECgUJDAAAAA==.Tutter:BAAALgADCgIJAgAAAA==.Tuuldd:BAAALgADCggJCAAAAA==.',
Tw='Twunk:BAAALgAECggJEAAAAA==.',
Ty='Tychuus:BAAALgAECgYJBgAAAA==.Typhlotic:BAAALgADCgMJAwAAAA==.Tyrennius:BAAALgAECgQJBAAAAA==.Tyrianis:BAABLgAECn8rAAMJAAkJNyG8CACEAgAJAAkJSSC8CACEAgAKAAMJzh6rEwDFAAAAAA==.',
Tz='Tzxdh:BAAALgAECgUJBQAAAA==.Tzxdruid:BAAALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ug='Uglymancer:BAABLgAECn8aAAMOAAgJqheBOwDfAQAOAAgJqheBOwDfAQAlAAEJAACUTAAAAAAAAA==.',
Uj='Ujimas:BAAALgAECgUJEAAAAA==.Ujong:BAAALgAECgYJCwABLgAECgcJMQACALIkAA==.',
Un='Unchartedd:BAAALgADCgEJAQAAAA==.',
Va='Vaenira:BAAALgADCgUJBgAAAA==.Vako:BAAALgAECgQJCgAAAA==.Valdara:BAAALgADCgkJEgAAAA==.Valemon:BAAALgAECgIJAgAAAA==.Vampireshade:BAABLgAECn80AAIVAAgJ3ApZCwBMAQAVAAgJ3ApZCwBMAQAAAA==.Vanimao:BAABLgAECn81AAQEAAkJdQ+tPACxAQAEAAkJdQ+tPACxAQAFAAcJjwmLPgD4AAADAAcJrwzoJgD3AAAAAA==.Vankman:BAAALgADCgcJBwAAAA==.Vannaka:BAAALgADCgEJAQAAAA==.',
Vb='Vbull:BAAALgAECgEJAQAAAA==.',
Ve='Vedrolan:BAAALgADCgUJDgABLgAFFAMJCAAWACQKAA==.Velifya:BAAALgADCgMJAwAAAA==.Velindon:BAAALgADCgYJBgAAAA==.Velissari:BAABLgAECn8XAAILAAYJ7xV4IgBAAQALAAYJ7xV4IgBAAQAAAA==.Velonar:BAAALgADCgEJAQAAAA==.Velouria:BAABLgAECn9MAAQDAAkJ2CLFAQAiAwADAAkJwCLFAQAiAwAFAAgJ6h8SDQDIAgAEAAIJ9QSXwABGAAAAAA==.Venatra:BAAALgAECgQJBQAAAA==.Verudora:BAAALgADCgcJBwAAAA==.Vexira:BAAALgADCgcJBwAAAA==.',
Vi='Violet:BAABLgAECn8gAAIZAAgJJBeOCgAkAgAZAAgJJBeOCgAkAgAAAA==.Violette:BAABLgAECn8oAAIPAAcJeg+qawBTAQAPAAcJeg+qawBTAQAAAA==.Visix:BAAALgAECgMJAwAAAA==.Vitt:BAAALgAECgEJAgAAAA==.',
Vo='Voidchacha:BAAALgADCgEJAQAAAA==.Voidlink:BAABLgAECn8tAAIjAAkJsxS1FgAAAgAjAAkJsxS1FgAAAgAAAA==.Voidmistress:BAABLgAECn8nAAICAAcJGRgIZQCaAQACAAcJGRgIZQCaAQAAAA==.Voidpup:BAABLgAECn8oAAIYAAcJYxyJOQDJAQAYAAcJYxyJOQDJAQAAAA==.Volgrimm:BAABLgAECn8bAAIWAAgJKwtFMAAwAQAWAAgJKwtFMAAwAQAAAA==.Volitaire:BAAALgADCgYJBgAAAA==.Volkân:BAAALgADCgUJBQAAAA==.Vonbek:BAAALgAECgMJAwAAAA==.',
Vy='Vynethan:BAAALgAECgEJAgAAAA==.',
['Vé']='Véngence:BAABLgAECn8XAAITAAcJKBHGdABlAQATAAcJKBHGdABlAQAAAA==.',
['Vê']='Vêx:BAAALgADCgYJBgAAAA==.',
Wa='Wabalabalosh:BAAALgADCgkJCQAAAA==.Wabgucci:BAAALgADCgUJBQAAAA==.Wabwum:BAAALgAECgMJAwAAAA==.Wakaekwondo:BAAALgAECgEJAQAAAA==.Wakarisma:BAAALgAECgEJAQAAAA==.Wanda:BAAALgAECgkJDAAAAA==.Wangao:BAABLgAFFH8IAAIWAAMJJAoJNwC1AAAWAAMJJAoJNwC1AAAAAA==.Warbluster:BAAALgADCgIJAgAAAA==.Warchylde:BAAALgADCgkJEAAAAA==.Warolderoy:BAABLgAECn9LAAIaAAkJpSSnAgA5AwAaAAkJpSSnAgA5AwAAAA==.',
We='Weedshaman:BAAALgAECgEJAwAAAA==.Weedwax:BAAALgAECgQJBAAAAA==.Weil:BAAALgADCgIJAgAAAA==.',
Wh='Whiinuss:BAABLgAECn8UAAIHAAcJlw25fwB7AQAHAAcJlw25fwB7AQAAAA==.Whytrabbit:BAAALgAECgIJAgAAAA==.',
Wi='Wigglesdeath:BAAALgAECgUJBQAAAA==.',
Wl='Wldeagle:BAAALgAECgQJBAAAAA==.',
Wo='Woker:BAAALgAECgcJCwABLgAECgkJOgASAFIdAA==.Woodpig:BAABLgAECn8vAAQEAAkJ2SFmBQBWAwAEAAkJ2SFmBQBWAwADAAIJVBNwRABqAAAFAAMJcAqyZgBkAAAAAA==.Woogie:BAAALgAECgQJCwAAAA==.',
Wr='Wrangle:BAAALgADCgEJAQAAAA==.',
Wy='Wyldshade:BAAALgADCgYJCAAAAA==.Wyrm:BAAALgAECgUJBQABLgAECgUJCgABAAAAAA==.',
Xa='Xaladin:BAABLgAECn8ZAAILAAgJMwvHIgA9AQALAAgJMwvHIgA9AQAAAA==.Xantheos:BAAALgAECgEJAgAAAA==.Xathas:BAAALgAECgQJBAAAAA==.',
Xe='Xenna:BAAALgAECgQJBAAAAA==.Xeq:BAAALgAECgUJBQAAAA==.',
Xi='Xiata:BAAALgAECggJEQAAAA==.Xiu:BAAALgAECgMJAwAAAA==.',
Xr='Xrp:BAAALgADCgQJBQAAAA==.',
Ye='Yeoman:BAABLgAECn8eAAIaAAcJ8hItMwBpAQAaAAcJ8hItMwBpAQAAAA==.',
Yg='Yggdralith:BAAALgAECgkJJAAAAQ==.',
Yi='Yiznusin:BAAALgAECgEJAgAAAA==.',
Yo='Yourdeath:BAAALgAECgkJBAAAAA==.',
Yu='Yunosmall:BAAALgADCgIJAgAAAA==.Yunosmart:BAAALgAECgYJCQAAAA==.',
Za='Zackoh:BAAALgAECgEJAQAAAA==.Zaen:BAACLgAFFH8JAAIOAAMJWQx8bADSAAAOAAMJWQx8bADSAAAuAAQKfzYAAw4ACQmdH/cRALACAA4ACQmdH/cRALACACUAAwnUC7NDAKYAAAAA.Zagreus:BAAALgADCgcJCAAAAA==.Zakikaz:BAAALgAECgQJBQAAAA==.Zarkir:BAACLgAFFH8JAAMfAAMJXBwHDQAEAQAfAAMJXBwHDQAEAQATAAIJGA2cwgCHAAAuAAQKfyYABB8ACQmfJIsBAPgCAB8ACQkpIosBAPgCABMABwnCIc06AAECAB4ABwmtF5oZAIcBAAEuAAQKBgkXAAIApyIA.Zarkìr:BAABLgAECn8XAAICAAYJpyKQZwAIAgACAAYJpyKQZwAIAgAAAA==.Zaues:BAAALgAECgMJBAAAAA==.',
Ze='Zelily:BAABLgAECn8UAAIPAAgJfgceiAAVAQAPAAgJfgceiAAVAQAAAA==.Zenarri:BAAALgADCgYJBwAAAA==.Zenasdan:BAAALgADCgYJBgAAAA==.Zepha:BAAALgAECgYJCwAAAA==.Zerø:BAAALgAECgIJAgABLgAECgYJFwACAKciAA==.',
Zl='Zlyandien:BAAALgADCggJDwABLgAECggJGQAjACIYAA==.',
Zo='Zornov:BAABLgAECn8jAAMkAAgJjx58CQAeAgAkAAgJjx58CQAeAgAIAAMJJgg5aQByAAAAAA==.',
Zu='Zulrich:BAAALgAECgUJBQAAAA==.',
['Ëu']='Ëuni:BAABLgAECn8YAAIPAAcJYwvGggAgAQAPAAcJYwvGggAgAQAAAA==.',
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
