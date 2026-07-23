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

local lookup = {'Warlock-Destruction','Unknown-Unknown','Mage-Frost','Druid-Guardian','Druid-Restoration','Druid-Balance','Shaman-Restoration','Monk-Mistweaver','Paladin-Retribution','Warlock-Demonology','Paladin-Holy','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Havoc','Monk-Windwalker','Warlock-Affliction','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','DeathKnight-Unholy','Rogue-Outlaw','Monk-Brewmaster','DeathKnight-Blood','Warrior-Protection','DemonHunter-Devourer','Evoker-Preservation','Warrior-Fury','Priest-Shadow','Priest-Holy','Druid-Feral','DeathKnight-Frost','Hunter-Survival','Hunter-Marksmanship','DemonHunter-Vengeance','Mage-Arcane','Warrior-Arms','Priest-Discipline','Paladin-Protection','Shaman-Elemental',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abarlton:BAAALgAFFAEJAQABLgAECggJFAABAPQVAA==.Aberforthd:BAAALgAECgYJBgABLgAECgcJEgACAAAAAA==.',
Ac='Acorn:BAAALgAFFAMJBAAAAA==.',
Ad='Adabeam:BAAALgADCgcJCwAAAA==.Adagio:BAACLgAFFH8FAAIDAAMJKgj5OwC+AAADAAMJKgj5OwC+AAAuAAQKf0QAAgMACQkFHhcmAIMCAAMACQkFHhcmAIMCAAAA.Adetalo:BAABLgAECn8lAAIEAAkJ8Re+DgD5AQAEAAkJ8Re+DgD5AQAAAA==.Adiara:BAAALgAECgMJAwAAAA==.Aditu:BAABLgAECn81AAMFAAkJGB4ADwDdAgAFAAkJGB4ADwDdAgAGAAUJLRHXCwC8AAAAAA==.',
Ae='Aelis:BAAALgADCgcJCAAAAA==.Aemulo:BAAALgAECgUJBwAAAA==.Aerith:BAAALgADCgcJBwAAAA==.Aessone:BAAALgAECgYJCQABLgAFFAQJHQADAEIUAA==.',
Ag='Agasonex:BAAALgADCgMJAwAAAA==.Aggroholic:BAAALgAECgQJBAABLgADCgYJEAACAAAAAA==.',
Ai='Airent:BAABLgAECn8rAAMFAAgJrhS9BACUAQAFAAYJARe9BACUAQAGAAgJehQdBgA+AQAAAA==.Aiyana:BAAALgAECgYJDgAAAA==.',
Ak='Akhuahwe:BAAALgADCgUJAQAAAA==.Akiirii:BAAALgAECgEJAQAAAA==.',
Al='Alaestel:BAAALgAECgQJBwAAAA==.Aldo:BAAALgAECgcJDwAAAA==.Alenthele:BAAALgAECgEJAwAAAA==.Aletheia:BAAALgAFFAEJAQAAAA==.Alkaraho:BAAALgAECgMJAwAAAA==.Alleriya:BAAALgAECgEJAQABLgAFFAUJDgAHAH0OAA==.Alleyways:BAACLgAFFH8MAAIIAAQJWCSnEwApAQAIAAQJWCSnEwApAQAuAAQKfzwAAggACQn3JYIBAMcDAAgACQn3JYIBAMcDAAAA.Alzey:BAABLgAECn8oAAIJAAkJjQ+ZawCXAQAJAAkJjQ+ZawCXAQAAAA==.',
Am='Ambeon:BAAALgADCgUJBQAAAA==.Ammathindis:BAAALgAECgYJBgAAAA==.Ammutseba:BAAALgADCggJCAAAAA==.Amplers:BAAALgADCgUJBwAAAA==.',
An='Ancane:BAAALgAECgYJBgAAAA==.Andyxdd:BAAALgAECgIJAwABLgAFFAkJKgADAHAhAA==.Angelbane:BAAALgADCgQJBAAAAA==.Angina:BAAALgAECgIJBQAAAA==.Annarcis:BAABLgAECn8yAAIKAAgJ7BDjBgB/AQAKAAgJ7BDjBgB/AQAAAA==.Anotherdk:BAAALgAECgYJBgABLgAECgkJKQALAKojAA==.Anthiell:BAAALgADCgEJAQAAAA==.Antiman:BAABLgAECn8oAAIJAAkJQgz5awCWAQAJAAkJQgz5awCWAQAAAA==.Anäster:BAAALgAFFAEJAQABLgAFFAUJGAAJABIQAA==.',
Ap='Aplcyder:BAABLgAECn84AAIFAAkJVwy1RwBxAQAFAAkJVwy1RwBxAQAAAA==.',
Ar='Arabisa:BAAALgAECgQJBAAAAA==.Arabloom:BAAALgAECgEJAQAAAA==.Arachnid:BAABLgAECn8xAAIDAAcJsiRFMQCtAgADAAcJsiRFMQCtAgAAAA==.Aragorn:BAAALgADCgkJDQAAAA==.Aratyn:BAABLgAECn8eAAIDAAkJsg9sYAC/AQADAAkJsg9sYAC/AQAAAA==.Ariane:BAAALgAECgIJAgAAAA==.Army:BAAALgAECgQJBwABLgAFFAMJAwACAAAAAA==.',
As='Asanot:BAAALgAECgUJBQAAAA==.Ascendance:BAAALgAECgEJAQAAAA==.',
At='Atalisk:BAAALgAECgYJBgAAAA==.Ati:BAAALgADCgIJAgAAAA==.',
Au='Audxo:BAAALgADCgMJAwAAAA==.',
Ay='Ayayron:BAAALgADCgQJBAAAAA==.',
Ba='Backhawk:BAAALgADCgcJEAAAAA==.Backsurgery:BAABLgAFFH8QAAMMAAgJ9SBjCQALAgAMAAgJuh5jCQALAgANAAIJUyE2DQBhAAAAAA==.Baern:BAAALgAECgIJAgAAAA==.Baerrn:BAABLgAECn8nAAIOAAkJYQkNMQABAQAOAAkJYQkNMQABAQAAAA==.Baggins:BAAALgADCgEJAQAAAA==.Baltazaris:BAAALgAECgUJCAAAAA==.Bamboo:BAAALgAECgYJCQABLgAFFAMJCgAPAIAZAA==.Baricia:BAABLgAECn8cAAIDAAkJ3wqHcgCVAQADAAkJ3wqHcgCVAQAAAA==.Barix:BAAALgAECgEJBAAAAA==.Barnd:BAAALgADCggJDwAAAA==.Barrin:BAABLgAECn9BAAMQAAkJ6RwqAQDhAQAQAAkJ6RwqAQDhAQAKAAUJQgiUvADRAAAAAA==.Bastim:BAAALgAECgQJDAAAAA==.Baussassbich:BAAALgAECgQJBAABLgAECgkJJAAKAE4hAA==.Bawnchu:BAAALgAECgQJDAAAAA==.',
Be='Beastmaster:BAACLgAFFH8FAAIRAAMJvSBqVgD6AAARAAMJvSBqVgD6AAAuAAQKfy8AAhEACAmYJH8UAK4CABEACAmYJH8UAK4CAAAA.Beefcakell:BAAALgADCgcJDQAAAA==.Beiki:BAAALgAECgcJEAAAAA==.Belthar:BAAALgAECgQJCQAAAA==.Bently:BAABLgAECn8iAAMSAAcJpSHFHwDaAQASAAcJ9R/FHwDaAQATAAUJGCMtEwCvAQAAAA==.Berexis:BAAALgAECgkJEQAAAA==.',
Bi='Bissafiyah:BAACLgAFFH8hAAIUAAgJ6CCTAAB3AgAUAAgJ6CCTAAB3AgAuAAQKf1kAAhQACQn4JgUAAKoDABQACQn4JgUAAKoDAAAA.Biznasty:BAAALgAECgEJAwAAAA==.',
Bl='Bloodgon:BAABLgAFFH8HAAIVAAMJUhjRjADwAAAVAAMJUhjRjADwAAAAAA==.Bluetuesday:BAAALgAECgQJBwAAAA==.',
Bo='Bogart:BAAALgAECgEJAQAAAA==.Bohica:BAABLgAECn84AAIHAAkJRhFXPQC5AQAHAAkJRhFXPQC5AQAAAA==.Bonechop:BAAALgAECgEJAgAAAA==.Bootymeat:BAAALgADCgEJAQAAAA==.Bowtox:BAAALgAECgEJAQAAAA==.Boyakasha:BAABLgAECn9EAAIWAAgJyBOkAACyAQAWAAgJyBOkAACyAQAAAA==.',
Br='Bratislava:BAAALgAECgYJEAAAAA==.Brewfu:BAAALgADCgIJAgAAAA==.Brewpub:BAAALgADCgQJBAAAAA==.Brewsome:BAABLgAECn9BAAQPAAkJQyF8BgDkAgAPAAkJQyF8BgDkAgAXAAkJ1RhjEgAhAgAIAAEJ0xHbtAA7AAAAAA==.Bruceleëroy:BAAALgAECgQJBQAAAA==.Bruceprime:BAAALgAECgkJAQAAAA==.Bryybryy:BAABLgAECn8YAAMYAAkJ6R5DAQCKAgAYAAkJ6R5DAQCKAgAVAAEJ8At6SQAlAAAAAA==.Bryycelest:BAABLgAECn8jAAIXAAgJ5BptFwDuAQAXAAgJ5BptFwDuAQABLgAECgkJGAAYAOkeAA==.Bryydruid:BAAALgAECgEJAQABLgAECgkJGAAYAOkeAA==.Brz:BAAALgAECgYJEAAAAA==.Brådòn:BAAALgAECgYJEgAAAA==.',
Bu='Bucket:BAABLgAECn8wAAIZAAkJEho3CgBPAgAZAAkJEho3CgBPAgAAAA==.Bunkiee:BAAALgADCgkJIQAAAA==.Bunnybane:BAAALgAECgYJEAAAAA==.Burlath:BAAALgADCgMJBgAAAA==.Burny:BAABLgAECn8aAAIDAAcJVCVMJgDZAgADAAcJVCVMJgDZAgABLgAFFAQJDAAIAFgkAA==.Buttadogg:BAAALgAECgcJDwAAAA==.',
['Bè']='Bèth:BAAALgAECgQJAQAAAA==.',
['Bë']='Bëckey:BAAALgADCgIJAgAAAA==.',
Ca='Calyx:BAABLgAECn8xAAIaAAcJTwmEEgDOAAAaAAcJTwmEEgDOAAAAAA==.Canadani:BAAALgAECgcJDQAAAA==.Candorite:BAABLgAECn8dAAMSAAkJbw3aQAAmAQASAAcJzQzaQAAmAQAbAAIJKA6fMABoAAAAAA==.Caphriel:BAABLgAECn8dAAIcAAkJQB3LFwAvAgAcAAkJQB3LFwAvAgAAAA==.Capita:BAABLgAECn8cAAIDAAgJjAmboQA4AQADAAgJjAmboQA4AQAAAA==.Captndave:BAAALgADCgMJAwAAAA==.Carrian:BAAALgAECgEJAgAAAA==.Carsinegan:BAAALgAECgUJCwAAAA==.Cassica:BAABLgAECn8dAAMdAAcJbhlQOAA0AQAdAAcJbhlQOAA0AQAeAAIJ1gnNZgBIAAAAAA==.Catchdezhanz:BAAALgADCgcJBwABLgAECgcJMQALAJ8WAA==.Catskin:BAABLgAECn8jAAMfAAkJuiBTBAC9AgAfAAgJKiNTBAC9AgAFAAYJ8htBPQCeAQAAAA==.',
Ce='Celivalasha:BAAALgADCgUJBQAAAA==.Cell:BAABLgAECn8jAAIXAAgJTSQqBQA3AwAXAAgJTSQqBQA3AwAAAA==.Cet:BAAALgADCgUJBQABLgAFFAEJAQACAAAAAA==.',
Ch='Chadvader:BAAALgADCgIJAgAAAA==.Chainlink:BAAALgADCgYJBgAAAA==.Chalee:BAAALgAECgEJAQAAAA==.Chandraskhar:BAAALgADCgIJAgAAAA==.Chanpagne:BAAALgAECgEJAQAAAA==.Charkle:BAABLgAECn8XAAIRAAcJWhhiSADIAQARAAcJWhhiSADIAQAAAA==.Chayea:BAAALgADCgEJAQAAAA==.Chicknraptor:BAAALgAECgUJBQAAAA==.Chillylilly:BAABLgAECn8vAAMYAAkJbSV4AgAnAwAYAAkJbSV4AgAnAwAgAAQJ4Ry0EwBBAQAAAA==.Chlorophyll:BAAALgAECgQJBAAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chopsuoy:BAAALgAECgEJAQAAAA==.Chummie:BAABLgAECn8wAAMKAAkJ2h/2GACOAgAKAAkJcR/2GACOAgAQAAYJdxxDCADHAQAAAA==.',
Ci='Ciandoril:BAABLgAECn8rAAUEAAkJVxf5BwDqAAAGAAcJ8heQJACnAQAEAAQJ8BL5BwDqAAAfAAMJHhTVLACyAAAFAAMJ+Q8rjwCXAAAAAA==.Cielcin:BAAALgAFFAMJAwAAAA==.Ciremiih:BAAALgAECgEJAQAAAA==.Citymage:BAACLgAFFH8LAAIDAAUJWAWBcwD4AAADAAUJWAWBcwD4AAAuAAQKfykAAgMACQmbF0JGAAgCAAMACQmbF0JGAAgCAAAA.Cixelsyd:BAAALgADCgYJCwABLgAFFAcJFAAJANMOAA==.',
Cl='Clamchowda:BAABLgAECn8vAAMaAAkJoBsRJwAvAgAaAAkJKxkRJwAvAgAOAAUJUh5wIwCiAQAAAA==.',
Co='Codê:BAABLgAECn8oAAIKAAkJAhm1JABMAgAKAAkJAhm1JABMAgAAAA==.Coffeecup:BAAALgADCgIJAgAAAA==.Colchagua:BAAALgAECgEJAgAAAA==.Corride:BAABLgAECn8rAAIhAAgJgR8AEQAkAgAhAAgJgR8AEQAkAgAAAA==.Corspar:BAAALgAECgQJBgAAAA==.',
Cr='Crazyeyes:BAAALgADCgYJCQAAAA==.Crimsondeath:BAABLgAECn9FAAIYAAgJBg/cBAA7AQAYAAgJBg/cBAA7AQAAAA==.Crom:BAAALgAECgIJBAAAAA==.Crutch:BAABLgAECn8mAAMHAAkJyRy9DADzAgAHAAkJyRy9DADzAgAUAAUJCBWQGgAuAQAAAA==.Crystanikus:BAAALgAECgQJBQAAAA==.',
Cu='Cuckenjoyer:BAAALgAECgYJCgAAAA==.',
Cy='Cyclonian:BAAALgAECgEJAgABLgAECgQJBQACAAAAAA==.Cyprus:BAAALgAECgEJAQAAAA==.',
Da='Daddytrump:BAABLgAECn8eAAIIAAkJPw8kMgCvAQAIAAkJPw8kMgCvAQAAAA==.Daelric:BAAALgAECgYJDgAAAA==.Daender:BAACLgAFFH8GAAIRAAIJaxvaegCiAAARAAIJaxvaegCiAAAuAAQKfzAAAxEACQl3JGQIABcDABEACQl3JGQIABcDACIAAQmCGAk7ADUAAAAA.Daenor:BAAALgAECgQJBwAAAA==.Dairydemon:BAACLgAFFH8aAAIjAAQJBwqlBACxAAAjAAQJBwqlBACxAAAuAAQKfzcAAiMACQkSDxsMAJYBACMACQkSDxsMAJYBAAAA.Damageus:BAACLgAFFH8PAAIDAAMJgB+nbgAFAQADAAMJgB+nbgAFAQAuAAQKfx8AAwMACAnqIjkkAOICAAMACAnqIjkkAOICACQAAQlGIDwGAFwAAAAA.Danhausen:BAAALgAECgEJAgAAAA==.Daniryl:BAEBLgAECn8bAAIFAAgJfxW1LAD1AQAFAAgJfxW1LAD1AQAAAA==.Dar:BAAALgAECgQJCwAAAA==.Darcnescoach:BAABLgAECn8YAAIlAAcJHRMNAwBHAQAlAAcJHRMNAwBHAQAAAA==.Darcness:BAABLgAECn8lAAQNAAYJkhmvDABgAQANAAYJhxavDABgAQAMAAUJTxZQOABSAQAWAAEJIRayIQBEAAAAAA==.Darcside:BAABLgAECn9AAAMdAAgJ5BUrAwDNAQAdAAgJ5BUrAwDNAQAmAAUJtwWrDgCwAAAAAA==.Darkclouds:BAAALgADCgIJAgAAAA==.Darksoul:BAABLgAECn8UAAIKAAkJWwYiiAApAQAKAAkJWwYiiAApAQABLgAECgkJGwAmAFUYAA==.Darkxwraith:BAABLgAECn8aAAILAAcJuhlEBgA5AQALAAcJuhlEBgA5AQAAAA==.Dashtoolite:BAABLgAECn8eAAIaAAgJNw23bABKAQAaAAgJNw23bABKAQAAAA==.Datsombeech:BAAALgAECgcJBwAAAA==.Datsumbeech:BAABLgAECn8mAAIgAAkJDg60DgCKAQAgAAkJDg60DgCKAQAAAA==.',
Dc='Dcoi:BAAALgADCgQJBAAAAA==.',
De='Deajer:BAAALgADCgYJBwAAAA==.Deathsabeach:BAAALgAECgEJAQAAAA==.Deathvìxen:BAABLgAECn8XAAMdAAgJyAc2PgAYAQAdAAgJyAc2PgAYAQAmAAMJiwYxbgBPAAAAAA==.Debit:BAAALgAECgcJEwAAAA==.Demonhunter:BAACLgAFFH8KAAIaAAQJkiHQPQAwAQAaAAQJkiHQPQAwAQAuAAQKfx0AAhoACAk/JKkKAC4DABoACAk/JKkKAC4DAAAA.Demonwoogie:BAAALgADCgYJBgABLgAECgQJCwACAAAAAA==.Dendrophilia:BAAALgAECgYJCgAAAA==.Densamin:BAABLgAECn8oAAQJAAkJ+BWpQAAFAgAJAAkJ+BWpQAAFAgALAAIJugH4hgA9AAAnAAEJ4wuFUwApAAAAAA==.Deviyn:BAAALgADCgIJAgAAAA==.Devourussy:BAAALgADCgkJCQAAAA==.Devra:BAAALgADCggJCAAAAA==.Dexter:BAAALgAECgEJAgAAAA==.Deàdly:BAABLgAECn8ZAAMgAAcJHyFiCAAIAgAgAAcJHyFiCAAIAgAVAAMJghmcJAF+AAAAAA==.',
Dh='Dhaynk:BAAALgAFFAEJAQAAAA==.',
Di='Dietchrist:BAAALgAECggJEwAAAA==.Dilligaf:BAAALgADCggJCAAAAA==.',
Dk='Dkanabiss:BAAALgAECgMJBAAAAA==.Dkinabox:BAAALgAECgUJDQAAAA==.',
Do='Docbaba:BAAALgAFFAEJAgAAAA==.Doh:BAAALgADCgIJAgAAAA==.Doist:BAAALgAECgIJAgAAAA==.Donngaz:BAAALgAECgMJBgAAAA==.Dookey:BAAALgAECgMJAwAAAA==.Doomwood:BAAALgADCgkJAQAAAA==.',
Dr='Drakeskin:BAAALgADCgEJAQAAAA==.Drakir:BAAALgAECgkJAQAAAA==.Dreadgnar:BAAALgAECgEJAgAAAA==.Drewnei:BAAALgADCgkJCQAAAA==.Drewserk:BAABLgAECn8pAAIcAAkJKxxxFQBEAgAcAAkJKxxxFQBEAgAAAA==.Drkxmaniac:BAAALgAECgcJEAABLgAECggJFAABAPQVAA==.Drminnowphd:BAAALgAFFAEJAgAAAA==.Drpiscisphd:BAACLgAFFH8cAAMVAAYJRR4QEQDKAQAVAAYJRR4QEQDKAQAYAAEJdAUSRQAjAAAuAAQKfzEAAxUACQk1Ie4OACQDABUACQk1Ie4OACQDABgABwnDBYIpAPMAAAAA.Drsaltyballz:BAABLgAECn8uAAINAAkJyiKRAQDwAgANAAkJyiKRAQDwAgAAAA==.Drugpala:BAAALgAECgIJAgAAAA==.Druji:BAAALgAECggJEwAAAA==.Drumuss:BAAALgADCgEJAQAAAA==.',
Du='Ducat:BAABLgAECn8ZAAIDAAUJRwss7gDGAAADAAUJRwss7gDGAAAAAA==.Dudesk:BAAALgAECgUJBgAAAA==.Duffuna:BAAALgADCgEJAQABLgAFFAMJBQAhADwfAA==.Duffunha:BAACLgAFFH8FAAIhAAMJPB+QBgAdAQAhAAMJPB+QBgAdAQAuAAQKf0wAAiEACQkIJq4AAHQDACEACQkIJq4AAHQDAAAA.',
Dy='Dye:BAABLgAECn80AAILAAkJhx6XCAABAwALAAkJhx6XCAABAwAAAA==.Dyre:BAABLgAECn8nAAIjAAkJXQ9xDQB8AQAjAAkJXQ9xDQB8AQAAAA==.Dyslexic:BAACLgAFFH8GAAIBAAUJnQPeCAALAQABAAUJnQPeCAALAQAuAAQKfyYAAgEACAlzGHsHANwBAAEACAlzGHsHANwBAAEuAAUUBwkUAAkA0w4A.Dyspepsia:BAACLgAFFH8UAAIJAAcJ0w6UDwBiAQAJAAcJ0w6UDwBiAQAuAAQKfx8AAgkACQmZG08+AAwCAAkACQmZG08+AAwCAAAA.',
['Dô']='Dôngus:BAAALgADCgMJAwABLgAECgQJBQACAAAAAA==.',
['Dõ']='Dõngus:BAAALgAECgQJBAABLgAECgQJBQACAAAAAA==.',
['Dö']='Döngus:BAAALgAECgEJAgABLgAECgQJBQACAAAAAA==.',
Ed='Edie:BAAALgAECgEJBgAAAA==.',
Ei='Eirenn:BAABLgAECn8WAAIPAAkJ9gS+CwCaAAAPAAkJ9gS+CwCaAAAAAA==.',
El='Elayna:BAAALgAECgkJBwAAAA==.Elenaura:BAAALgAECgMJAwAAAA==.Eleren:BAABLgAECn8bAAIaAAgJiBLzWwB0AQAaAAgJiBLzWwB0AQAAAA==.Elimee:BAACLgAFFH8FAAIDAAIJnRAmqACDAAADAAIJnRAmqACDAAAuAAQKfzAAAgMACQmgIUkOAFQDAAMACQmgIUkOAFQDAAAA.Elisestraza:BAABLgAFFH8GAAISAAMJfg3gRwCqAAASAAMJfg3gRwCqAAABLgAFFAIJBQADAJ0QAA==.Ellasia:BAABLgAECn8UAAINAAYJzwM3GACyAAANAAYJzwM3GACyAAAAAA==.Elric:BAACLgAFFH8GAAIJAAIJtAcKnACDAAAJAAIJtAcKnACDAAAuAAQKfzUAAgkACQlMGcY2ACYCAAkACQlMGcY2ACYCAAAA.Elsie:BAAALgAECgcJDgABLgAECgkJKAALAGwfAA==.Elton:BAAALgAECgYJBgAAAA==.Elunea:BAAALgADCgcJDQAAAA==.Elunemittens:BAAALgADCgYJBgAAAA==.',
Em='Emart:BAABLgAECn8lAAIhAAkJaw69GQDRAQAhAAkJaw69GQDRAQAAAA==.Emozella:BAAALgAECgEJAQAAAA==.',
En='Enatresh:BAABLgAECn8ZAAIDAAgJ5QR1IQCtAAADAAgJ5QR1IQCtAAAAAA==.',
Ep='Epsilon:BAAALgAECgkJCQAAAA==.',
Er='Erayna:BAABLgAECn86AAIFAAkJsRaMHABiAgAFAAkJsRaMHABiAgAAAA==.Ereillea:BAAALgAECgYJDQAAAA==.',
Es='Essence:BAABLgAECn8WAAMDAAgJmxTpagAAAgADAAgJDBHpagAAAgAkAAQJ1xocDAARAQAAAA==.',
Et='Etherious:BAAALgAECgcJCQABLgAECgkJKAALAGwfAA==.',
Eu='Euko:BAACLgAFFH8GAAMGAAIJqRSFPACCAAAGAAIJqRSFPACCAAAFAAIJwA5vWABpAAAuAAQKfzUAAwYACQkvIfkIAMMCAAYACQkvIfkIAMMCAAUACAl1FZlmAAABAAAA.',
Ev='Evedk:BAAALgAECgkJBQAAAA==.Evepriest:BAAALgAECgEJAQAAAA==.',
Ex='Exterminatra:BAAALgAECgEJAQAAAA==.',
Fa='Failrogue:BAAALgADCgUJCwAAAA==.Falconclaw:BAAALgAECggJDQAAAA==.Falkensnoman:BAABLgAECn8oAAIYAAkJvBWMEwDZAQAYAAkJvBWMEwDZAQAAAA==.Fayedra:BAABLgAECn8eAAIEAAkJbxR+EADhAQAEAAkJbxR+EADhAQAAAA==.Faytaleti:BAAALgAECgUJCQAAAA==.',
Fc='Fcawfe:BAAALgAECgQJBAABLgAECgkJIAALAEgdAA==.',
Fe='Febee:BAAALgADCgcJAQAAAA==.Feenii:BAACLgAFFH8FAAIUAAMJOQdRCQCtAAAUAAMJOQdRCQCtAAAuAAQKfzoAAhQACQlSHdAFAIECABQACQlSHdAFAIECAAAA.Felburst:BAAALgAECgMJAwAAAA==.Feldog:BAAALgADCgkJCQAAAA==.Felfireqt:BAAALgAECgEJAgAAAA==.Fersiam:BAAALgAECgcJAQABLgAECgkJKAALAGwfAA==.Feydros:BAAALgAECgkJBQAAAA==.',
Fh='Fhaani:BAAALgADCgIJAgAAAA==.',
Fi='Figgyandrii:BAAALgAECgUJBQAAAA==.Fionar:BAAALgADCgIJAgAAAA==.Fizzlelich:BAAALgAECgYJBgAAAA==.',
Fl='Flamesters:BAABLgAFFH8IAAIDAAYJpwgTTABIAQADAAYJpwgTTABIAQAAAA==.Fluffpuff:BAAALgADCgMJAwAAAA==.Fluffyfury:BAAALgADCgEJAQAAAA==.',
Fm='Fmpumps:BAAALgAECgEJAQAAAA==.',
Fo='Foxdeer:BAABLgAECn8fAAMKAAkJmQjagwAxAQAKAAkJmQjagwAxAQAQAAMJ4wKhHwB0AAAAAA==.Foxxmccloud:BAAALgAFFAEJAQABLgAFFAMJCwAGAIsdAA==.',
Fr='Frenchtoast:BAAALgAECgUJBwAAAA==.',
Fu='Fufighter:BAAALgADCgQJBAAAAA==.Furyrage:BAAALgAECgEJAQAAAA==.Fuzzyclawz:BAAALgADCgYJBgABLgAECgkJLAAPADMQAA==.',
Ga='Gambachii:BAAALgAECgcJDQAAAA==.Gankss:BAABLgAECn8pAAMLAAkJqiPdAQCYAwALAAkJqiPdAQCYAwAJAAEJNAHU1QEMAAAAAA==.Gannir:BAAALgAECgIJAgABLgAECgcJEAACAAAAAA==.Garakddon:BAAALgAECgYJBgABLgAECggJIAAnANsWAA==.Garryy:BAAALgAECgMJBwAAAA==.',
Ge='Geegandolm:BAAALgADCgkJEwAAAA==.Gemìnì:BAAALgAECgEJAgABLgAECggJFAAOAEQRAA==.Genjaru:BAABLgAECn8mAAMGAAYJRBy1BQBJAQAGAAYJRBy1BQBJAQAFAAMJ2QJ0wABFAAAAAA==.Genndalf:BAAALgADCgcJBwAAAA==.Geostorm:BAAALgAECgEJAQAAAA==.',
Gh='Gharmag:BAAALgAECgEJAQAAAA==.',
Gi='Giramar:BAABLgAECn84AAMdAAgJ5BzoEgA7AgAdAAgJ5BzoEgA7AgAeAAcJhg5JNAA0AQAAAA==.',
Gl='Glagkara:BAAALgAECgMJBwAAAA==.',
Go='Gobbyshamm:BAAALgAECgEJAQAAAA==.Gobsmackers:BAAALgAECgYJBwAAAA==.Goldengooner:BAAALgAFFAMJAwAAAA==.Gomklin:BAAALgADCgcJCAABLgAFFAIJBwAJAMUdAA==.Goobtastic:BAAALgADCgQJBAAAAA==.Goteem:BAAALgAECggJEwAAAA==.Gothitelle:BAAALgAECgIJAwAAAA==.',
Gr='Griffhud:BAABLgAECn8YAAIEAAcJDiEHEQDaAQAEAAcJDiEHEQDaAQAAAA==.Grimrox:BAABLgAECn8lAAIoAAkJYxLFJADCAQAoAAkJYxLFJADCAQAAAA==.Gripinstine:BAAALgADCgEJAQAAAA==.Grixx:BAAALgADCgUJBQAAAA==.Groupie:BAAALgADCgUJCgABLgAECgcJGAAiANUPAA==.',
Gt='Gtatedk:BAAALgAECgEJAQAAAA==.',
Gu='Guccimain:BAAALgAECgEJAQAAAA==.Guntera:BAAALgAECgYJDgAAAA==.Guts:BAAALgADCgMJAwAAAA==.',
Gw='Gwendalyn:BAAALgAECgQJBQAAAA==.',
['Gä']='Gäz:BAAALgADCgEJAQAAAA==.',
Ha='Haanit:BAAALgAECgYJBgAAAA==.Halexion:BAAALgADCgIJAgAAAA==.Haomaru:BAABLgAECn8XAAQFAAUJLBliSgBlAQAFAAUJLBliSgBlAQAfAAEJiBBnVAAwAAAGAAEJSAv1lwAoAAAAAA==.Hardcandy:BAABLgAECn8YAAIiAAcJ1Q8zGQDmAAAiAAcJ1Q8zGQDmAAAAAA==.Hardlyevoker:BAAALgADCgEJAQABLgAFFAIJBgALAOYQAA==.',
He='Heartsoul:BAAALgAECgYJCQAAAA==.Heavyarm:BAAALgADCgcJDwAAAA==.Hellork:BAAALgADCgQJBAAAAA==.Hermosura:BAAALgADCgUJCgAAAA==.Hex:BAAALgAFFAEJAQABLgAFFAEJAwACAAAAAA==.',
Hi='Hiccups:BAAALgAECgMJBAABLgAFFAQJBAACAAAAAA==.Himawarí:BAABLgAECn8yAAMZAAkJUBXvDgD7AQAZAAkJgxPvDgD7AQAcAAUJwhoUQQBAAQAAAA==.Hiyank:BAABLgAECn8qAAIXAAkJrCKKBgDRAgAXAAkJrCKKBgDRAgABLgAFFAEJAQACAAAAAA==.',
Ho='Hoffmin:BAABLgAECn8XAAMaAAkJdBnybABKAQAaAAgJdBnybABKAQAOAAIJphK0VgCMAAAAAA==.Holemeister:BAACLgAFFH8QAAIJAAMJnCNgSQAaAQAJAAMJnCNgSQAaAQAuAAQKfzAAAgkACAmhJOINAB8DAAkACAmhJOINAB8DAAAA.Holyamin:BAAALgADCgEJAQAAAA==.Holyfresh:BAAALgADCgEJAQAAAA==.Holymann:BAABLgAECn8lAAIdAAgJ3A2GEQCFAAAdAAgJ3A2GEQCFAAAAAA==.Holyschnikey:BAABLgAECn8xAAILAAcJnxa/AwCvAQALAAcJnxa/AwCvAQAAAA==.Holyz:BAABLgAECn85AAMLAAkJpCMeAgCPAwALAAkJpCMeAgCPAwAJAAEJBhk/bQFKAAAAAA==.Horgable:BAAALgADCgIJAgAAAA==.Horrorpops:BAAALgAECgMJAwABLgAFFAIJBgARAGsbAA==.Hozaki:BAAALgAECgQJBAABLgAECggJFAABAPQVAA==.',
Hu='Hudfin:BAAALgAECgUJBgAAAA==.Hundred:BAAALgAECgIJAgABLgAFFAMJBAACAAAAAA==.Huntinwoogie:BAAALgAECgIJAwABLgAECgQJCwACAAAAAA==.Hunzul:BAAALgADCgcJCAAAAA==.',
Hy='Hyrule:BAAALgAECgYJBgABLgAFFAMJBQAmAF4aAA==.',
['Hí']='Hílthaen:BAABLgAECn84AAMeAAkJmRbqEwA4AgAeAAkJmRbqEwA4AgAmAAEJMQlyIAAnAAAAAA==.',
Ic='Icebones:BAAALgADCgcJDAABLgAECgQJCQACAAAAAA==.Icelight:BAAALgAECgQJCQAAAA==.Ichigokisu:BAABLgAECn8WAAIJAAgJaRG0dQCCAQAJAAgJaRG0dQCCAQAAAA==.',
Il='Illiduji:BAAALgADCgMJAwAAAA==.Illy:BAABLgAECn8jAAIaAAkJ+hYELgAPAgAaAAkJ+hYELgAPAgAAAA==.',
Im='Imply:BAAALgAECgMJAwAAAA==.Imposed:BAAALgAECgcJEAAAAA==.',
In='Instantdeath:BAABLgAECn8UAAQBAAgJ9BXIAwARAQABAAUJ7RbIAwARAQAKAAUJHgpszwC0AAAQAAUJKhNpBwCXAAAAAA==.Invali:BAAALgAECgYJCQAAAA==.',
Io='Iorla:BAAALgADCgcJBgAAAA==.',
Ir='Irônhide:BAAALgAECgEJAQAAAA==.',
Iv='Ivranda:BAAALgADCgkJEgABLgAECgkJHQASAG8NAA==.',
Iz='Iz:BAAALgAFFAEJAQAAAA==.',
Ja='Jaapp:BAAALgAECgMJBgAAAA==.Jahan:BAACLgAFFH8XAAImAAQJuxmCDgA0AQAmAAQJuxmCDgA0AQAuAAQKfy8AAyYACQlZIQYGACMDACYACAkiJAYGACMDAB0ABAmAEdBHAPAAAAEuAAUUAQkBAAIAAAAA.Jalisha:BAAALgAECgUJCAAAAA==.Jamie:BAABLgAFFH8IAAIVAAMJhCMDcAAeAQAVAAMJhCMDcAAeAQABLgAFFAgJGwAKAAAhAA==.Jaydine:BAAALgADCgYJBgABLgAFFAIJBQADAJ0QAA==.',
Je='Jeri:BAAALgAECgYJCAAAAA==.Jerithal:BAAALgAECgMJAwAAAA==.',
Jh='Jhie:BAABLgAECn8pAAIPAAkJYhaqHADJAQAPAAkJYhaqHADJAQAAAA==.',
Ji='Jinro:BAAALgAECgEJAgABLgAECgEJAwACAAAAAA==.',
Jo='Jodi:BAAALgAECgEJAQAAAA==.',
Ju='Jud:BAAALgAECggJEAAAAA==.Juviâ:BAAALgAECggJCgABLgAECgkJKAALAGwfAA==.Juxtaposed:BAAALgADCgUJBQAAAA==.',
Ka='Kaelora:BAAALgAECgYJCgAAAA==.Kaerei:BAABLgAECn8sAAIJAAkJnh75IQB+AgAJAAkJnh75IQB+AgAAAA==.Kaleb:BAACLgAFFH8KAAIOAAQJ+R6aCQBuAQAOAAQJ+R6aCQBuAQAuAAQKfyEAAg4ACAm2IVkLAHECAA4ACAm2IVkLAHECAAAA.Kalferno:BAABLgAECn8XAAIDAAcJ7BSnDgBFAQADAAcJ7BSnDgBFAQAAAA==.Kalirkaz:BAACLgAFFH8LAAIFAAMJVA0fGwCJAAAFAAMJVA0fGwCJAAAuAAQKfz8AAwUACQk0HeQCABECAAUACQk0HeQCABECAAYABQk5BspkAIkAAAAA.Kallipsa:BAAALgAECgMJAwAAAA==.Karasu:BAAALgAECggJCgABLgAECgkJLAAPADMQAA==.Kariel:BAAALgADCgQJBAAAAA==.Karst:BAAALgAECgQJBQABLgAFFAEJAQACAAAAAA==.Kathria:BAAALgAECgcJEAAAAA==.Kayotica:BAAALgAECgcJDAAAAA==.',
Ke='Keepcrying:BAAALgAECgEJAQAAAA==.Kegendary:BAAALgAECgQJCAAAAA==.Keler:BAAALgAECgEJAQABLgAECgMJBwACAAAAAA==.Kelideyn:BAAALgAECgYJBgAAAA==.Keládry:BAABLgAECn8XAAILAAcJHhd8MgCMAQALAAcJHhd8MgCMAQAAAA==.Keskiyö:BAAALgADCgkJFQABLgAECgkJLAAPADMQAA==.',
Kh='Khaalid:BAAALgAECgEJAwABLgAECgEJAwACAAAAAA==.Khallock:BAABLgAECn8lAAIQAAgJCRmaDgByAQAQAAgJCRmaDgByAQAAAA==.Khamael:BAAALgAECgEJAQAAAA==.',
Ki='Kiemen:BAABLgAECn8oAAMVAAkJHRoONwAjAgAVAAkJHRoONwAjAgAgAAEJbQ4kOwAxAAAAAA==.Kierya:BAAALgAECgEJAgAAAA==.Killerpoison:BAAALgAECgkJBQAAAA==.Killko:BAACLgAFFH8GAAIVAAIJbg+B0QCPAAAVAAIJbg+B0QCPAAAuAAQKfxsAAhUACQn+G/YrAFACABUACQn+G/YrAFACAAAA.Kinki:BAAALgAECgMJAwABLgAECgcJGAAiANUPAA==.Kirisen:BAAALgAECgUJCQAAAA==.Kitan:BAAALgAECgQJBQAAAA==.Kitani:BAAALgADCgkJGAABLgAECgkJbQAmAO0iAA==.',
Ko='Konno:BAAALgAECgQJBAABLgAFFAgJIQAUAOggAA==.Kooterr:BAAALgADCgUJBQAAAA==.Korbix:BAACLgAFFH8GAAIVAAMJFQxGcQBhAAAVAAMJFQxGcQBhAAAuAAQKfxcAAhUABglaGxx1AHkBABUABglaGxx1AHkBAAAA.',
Kr='Kragsloor:BAAALgAFFAEJAQAAAA==.Kredorin:BAAALgAECgYJCgAAAA==.Krewella:BAAALgADCgcJBwAAAA==.Krickette:BAAALgAECgYJBgAAAA==.Krihl:BAAALgAECgkJBgAAAA==.Krovmar:BAAALgADCgUJBQAAAA==.Kryoos:BAAALgAECgEJAQAAAA==.',
Ks='Kspanxx:BAAALgAECgMJAwAAAA==.',
Kt='Kthanx:BAAALgAECgQJAgAAAA==.',
Ku='Kungpowgazer:BAABLgAECn8XAAMXAAkJ/R1RCgCOAgAXAAkJ/R1RCgCOAgAPAAEJew8PowAtAAAAAA==.Kunls:BAABLgAECn8eAAIOAAgJrgiELQAWAQAOAAgJrgiELQAWAQAAAA==.Kuraak:BAAALgAECgQJCAAAAA==.Kuraki:BAABLgAECn8eAAIPAAkJbAqSLABcAQAPAAkJbAqSLABcAQAAAA==.Kurasa:BAABLgAECn8sAAMPAAkJMxAeIwCYAQAPAAkJMxAeIwCYAQAIAAQJowH4WgBjAAAAAA==.Kutraz:BAAALgAECgQJBQAAAA==.',
La='Ladrar:BAABLgAECn8aAAQfAAkJnhZEDAD0AQAfAAgJxhhEDAD0AQAGAAMJQAz1aAB8AAAFAAEJ6ATT7wAgAAAAAA==.Laelina:BAAALgAECgEJAwAAAA==.Laidiemonk:BAAALgADCgYJBgAAAA==.Lanadiel:BAACLgAFFH8GAAInAAIJyxi6DgCUAAAnAAIJyxi6DgCUAAAuAAQKfzUAAicACQmIIs8CAPoCACcACQmIIs8CAPoCAAAA.Lazz:BAABLgAECn8UAAQhAAcJpiEDFQD7AQAhAAcJpiEDFQD7AQAiAAQJ5RkJQQBVAQARAAEJAADvVQEAAAABLgAFFAQJDAAIAFgkAA==.',
Le='Legend:BAACLgAFFH8bAAIaAAYJCh5ANgBLAQAaAAYJCh5ANgBLAQAuAAQKfzIAAhoACQm3IDAJAD4DABoACQm3IDAJAD4DAAAA.Lekrotar:BAAALgAECgQJBAAAAA==.Letsyoudie:BAAALgAECgMJAwAAAA==.',
Li='Lian:BAABLgAECn8XAAIIAAYJrgsdagDYAAAIAAYJrgsdagDYAAAAAA==.Lichbane:BAABLgAECn81AAIVAAkJmCFEFwC7AgAVAAkJmCFEFwC7AgAAAA==.Licun:BAAALgAECgYJDQAAAA==.Lifexdeath:BAABLgAECn8ZAAMeAAcJ5QbYQgDfAAAeAAcJ5QbYQgDfAAAdAAEJxgM5lwAjAAAAAA==.Lightcell:BAAALgAECgQJBgAAAA==.Liliara:BAABLgAECn80AAIRAAkJ3BCPRwDLAQARAAkJ3BCPRwDLAQAAAA==.Lillyfel:BAAALgADCgQJBAAAAA==.Lillyirl:BAAALgAECgUJEQAAAA==.Lillymae:BAAALgAECggJDAAAAA==.Lillyslight:BAAALgADCgYJBgAAAA==.Lillysneak:BAAALgADCgUJCgAAAA==.Lillytae:BAAALgAECgQJBwAAAA==.Lillyzard:BAAALgAECgEJAQAAAA==.Lilmoo:BAAALgAECggJEAAAAA==.Linkhunter:BAAALgAECgYJBgABLgAFFAMJBQAmAF4aAA==.Linni:BAABLgAECn8oAAILAAkJbB+5BQA1AwALAAkJbB+5BQA1AwAAAA==.Lizardwizard:BAAALgAECgQJBAAAAA==.',
Lo='Lockgodtko:BAAALgAECgcJDQAAAA==.Lodise:BAABLgAECn8oAAMQAAkJsw4SCgDAAQAQAAkJsw4SCgDAAQAKAAEJAAgZHQEyAAAAAA==.Lonful:BAAALgADCgEJAQAAAA==.Lorzz:BAACLgAFFH8YAAIeAAQJRhKlDADIAAAeAAQJRhKlDADIAAAuAAQKfzcAAh4ACQk8INkFABoDAB4ACQk8INkFABoDAAAA.Lothe:BAABLgAECn8eAAILAAkJtB43CAAIAwALAAkJtB43CAAIAwAAAA==.',
Lu='Lucrio:BAABLgAECn9BAAIVAAkJNhZ1NAAtAgAVAAkJNhZ1NAAtAgAAAA==.Ludlow:BAAALgAECgIJAgABLgAECgkJIAALAEgdAA==.Ludoe:BAAALgADCgkJMQAAAA==.Luminariah:BAAALgAECgYJEQABLgAECgcJDwACAAAAAA==.Luna:BAAALgAFFAEJAQAAAA==.Lunalai:BAABLgAECn9BAAIEAAkJ3iKBAgAVAwAEAAkJ3iKBAgAVAwAAAA==.Lurim:BAAALgAECgEJBAABLgAECggJIwAnAI8eAA==.Lushy:BAABLgAECn8aAAIMAAkJgRgEDgBIAgAMAAkJgRgEDgBIAgAAAA==.',
Ly='Lylineth:BAAALgADCgYJBgAAAA==.Lylinette:BAAALgAECgcJEgAAAA==.Lyssandra:BAAALgADCgUJBQAAAA==.',
['Lí']='Lízandor:BAACLgAFFH8YAAIJAAUJEhDiTgARAQAJAAUJEhDiTgARAQAuAAQKfykAAgkACQmYHF4sAFACAAkACQmYHF4sAFACAAAA.',
['Lû']='Lûsøn:BAAALgAECgEJAQAAAA==.',
Ma='Machotee:BAAALgAECgEJAQAAAA==.Madruskee:BAABLgAECn8sAAIgAAYJQBonAwA+AQAgAAYJQBonAwA+AQAAAA==.Magahpt:BAAALgAECgMJBAAAAA==.Magdea:BAAALgADCgYJBgAAAA==.Mageofdeath:BAAALgAECgYJCAABLgAECggJFAABAPQVAA==.Mageofhonor:BAAALgAECgEJAgAAAA==.Magistroll:BAABLgAECn8cAAIDAAcJXgXt1wDmAAADAAcJXgXt1wDmAAAAAA==.Mairisella:BAAALgAECgIJAgAAAA==.Malabathrum:BAAALgAECgEJAgAAAA==.Maladaptive:BAAALgAECgEJAgAAAA==.Malevohaynk:BAAALgAECgQJBQABLgAFFAEJAQACAAAAAA==.Mandrallea:BAAALgAECgYJBwAAAA==.Manerva:BAAALgAECgUJAgAAAA==.Maryshelley:BAAALgADCgMJAwAAAA==.Matoo:BAAALgADCgEJAQAAAA==.Mattertusk:BAAALgAECgEJAwAAAA==.Mattincis:BAAALgAFFAMJAQAAAA==.Maurin:BAAALgAFFAEJAgAAAA==.Maximumhonk:BAABLgAECn8nAAIHAAcJiRMUVwBaAQAHAAcJiRMUVwBaAQAAAA==.',
Me='Melfys:BAAALgAECgEJAQAAAA==.Melpómene:BAAALgAECgEJAQABLgAECgkJMgAKABEWAA==.Mendelia:BAABLgAECn81AAInAAkJRhbLAwBIAQAnAAkJRhbLAwBIAQAAAA==.Mercus:BAABLgAECn8ZAAMWAAkJ9RgiBgBqAQAWAAYJpBQiBgBqAQAMAAgJLxrxMQAUAQAAAA==.Merkstrasza:BAAALgAECgcJDwAAAA==.Mervenious:BAABLgAECn8fAAQcAAgJzxDpLgCUAQAcAAgJzxDpLgCUAQAlAAQJ7Q7eTACcAAAZAAMJpQhrOQB/AAAAAA==.Meu:BAAALgAECgkJCwAAAA==.',
Mi='Midasdh:BAACLgAFFH8OAAIaAAUJ0wuUVQDuAAAaAAUJ0wuUVQDuAAAuAAQKfxwAAxoACAmAF5Y+APoBABoACAnfFJY+APoBAA4ABgmOFwMwAE8BAAAA.Midasdk:BAACLgAFFH8NAAIVAAUJEhrDYwAvAQAVAAUJEhrDYwAvAQAuAAQKfxwAAxUABwnMHG9PAAQCABUABwm9GW9PAAQCACAAAwkzEkMmAKAAAAEuAAUUBQkOABoA0wsA.Midasmonk:BAAALgAECgEJAQABLgAFFAUJDgAaANMLAA==.Midasshift:BAAALgAECgcJDwAAAA==.Miladepollo:BAAALgADCgMJAwAAAA==.Milkers:BAAALgAECgEJAQAAAA==.Mindblank:BAAALgAECgQJBAAAAA==.Mindplague:BAABLgAECn9BAAIdAAkJKh9MAQCMAgAdAAkJKh9MAQCMAgAAAA==.Minipincin:BAAALgAECgUJBgAAAA==.Minisicwidit:BAAALgADCgMJAwAAAA==.Miroslava:BAAALgAECgYJBwAAAA==.Mirrorforce:BAAALgAFFAMJBAAAAA==.Mistdeeznuts:BAACLgAFFH8OAAIIAAQJpwjkPACyAAAIAAQJpwjkPACyAAAuAAQKfx8AAwgACQmWDOo5AIoBAAgACQmWDOo5AIoBAA8AAQmSA/a7AB0AAAAA.',
Mo='Mogwaï:BAAALgAECgcJCwAAAA==.Mokokoma:BAAALgAECgMJBAAAAA==.Moonde:BAAALgAECgkJDwAAAA==.Moonscale:BAABLgAECn80AAITAAkJHR/2AQC9AgATAAkJHR/2AQC9AgAAAA==.Moosayer:BAAALgAECgQJBgAAAA==.Moovement:BAAALgAECgMJAwABLgAFFAQJBwAEALYIAA==.Mossed:BAAALgADCgMJAwAAAA==.',
Ms='Mskelsier:BAAALgAECgUJBQAAAA==.',
Mt='Mtaur:BAAALgADCggJDwAAAA==.',
Mu='Muclor:BAAALgADCgcJBwABLgAFFAMJAwACAAAAAA==.Muffintop:BAAALgAECgEJAQABLgAECgkJLwAFANkhAA==.Murkyn:BAAALgAECgEJAQAAAA==.Mustang:BAAALgAECgUJBQAAAA==.',
My='Mydadstayed:BAAALgAECgYJCwABLgAECgcJJwAHAIkTAA==.Mythalis:BAAALgAECgQJBQAAAA==.Mythar:BAAALgAECgEJAQAAAA==.',
['Mä']='Märändus:BAAALgADCgEJAQAAAA==.',
['Må']='Måzikeen:BAAALgADCgMJAwAAAA==.',
Na='Nardena:BAAALgAECgUJAgAAAA==.Narse:BAABLgAFFH8GAAIeAAIJvwhSLgBeAAAeAAIJvwhSLgBeAAAAAA==.Narz:BAACLgAFFH8PAAIRAAMJHgcUNADBAAARAAMJHgcUNADBAAAuAAQKfzgAAhEACQlxFCA1AAgCABEACQlxFCA1AAgCAAAA.Nastianna:BAAALgAECgQJCgAAAA==.Natgeo:BAAALgAECgkJEAABLgAFFAMJBQAmAF4aAA==.Nazumi:BAABLgAECn8oAAIPAAkJ/R5vCADAAgAPAAkJ/R5vCADAAgAAAA==.',
Nd='Ndiz:BAABLgAECn8VAAIRAAcJIhwCJwAdAgARAAcJIhwCJwAdAgAAAA==.',
Ne='Necronomikon:BAAALgAECgEJAgAAAA==.Neeva:BAAALgADCgYJEAAAAA==.Nelrya:BAEALgADCgcJDQABLgAFFAUJDQAJALAPAA==.Nephilym:BAAALgAECgEJAQAAAA==.Nerhzul:BAAALgAECgcJDgAAAA==.Nerial:BAAALgAECgEJAQABLgAECgEJAwACAAAAAA==.Neruphuyt:BAABLgAECn86AAIGAAgJExRfJwCUAQAGAAgJExRfJwCUAQAAAA==.',
Ni='Niath:BAAALgAECgYJBwAAAA==.Nightsniper:BAABLgAECn8VAAIRAAkJyBkbRwDMAQARAAkJyBkbRwDMAQAAAA==.Ninfassins:BAAALgADCgIJAgAAAA==.',
No='Norintha:BAAALgADCgEJAQAAAA==.Norolen:BAAALgADCgIJAgAAAA==.',
Nu='Nuzzle:BAAALgAECgEJAQABLgAECgkJPQAEACMbAA==.',
Ny='Nyxelle:BAAALgAECgQJBAAAAA==.Nyxiel:BAAALgAECgQJBQABLgAECgcJDwACAAAAAA==.',
['Nò']='Nòvà:BAAALgAECgEJAQABLgAECggJFAAOAEQRAA==.',
Oa='Oak:BAAALgAECgkJEgAAAA==.',
Oc='Occo:BAAALgADCgEJAQAAAA==.',
Og='Ogroc:BAAALgAECgQJBAAAAA==.',
Ok='Okioak:BAABLgAECn8UAAQlAAkJcxKZLQATAQAlAAgJFRKZLQATAQAcAAMJ5BFjgAC8AAAZAAIJpwatQABOAAAAAA==.',
Ol='Olgon:BAACLgAFFH8VAAIRAAQJrQ/8IQAKAQARAAQJrQ/8IQAKAQAuAAQKfzoAAhEACQmvGhkeAHECABEACQmvGhkeAHECAAAA.Olstinkyboot:BAAALgAECgEJAQAAAA==.',
Op='Oprhawinfury:BAABLgAECn8iAAIVAAkJRA7jZgCZAQAVAAkJRA7jZgCZAQAAAA==.',
Or='Orcchop:BAAALgAECgEJBAAAAA==.Orgodemir:BAAALgADCgkJDwAAAA==.Orhamin:BAAALgAECgQJAgAAAA==.',
Os='Oshani:BAAALgAFFAEJAwAAAA==.',
Ot='Otemoto:BAAALgAECgEJAQABLgAFFAMJBAACAAAAAA==.',
Ou='Ouin:BAAALgAECgUJBQABLgAECgkJLwAoAHITAA==.',
Ox='Oxley:BAAALgAECgEJAgAAAA==.',
Pa='Paigor:BAAALgAECgQJBgAAAA==.Pakswagger:BAABLgAECn8XAAMbAAYJFRfoEwCLAQAbAAYJFRfoEwCLAQASAAMJRQS2ewBqAAAAAA==.Pallyberry:BAABLgAECn8xAAILAAkJZhsZEACYAgALAAkJZhsZEACYAgAAAA==.Pancake:BAAALgAECgEJAQAAAA==.Pandemonia:BAABLgAECn8zAAMBAAkJ5Q0rFgCYAQABAAgJHgwrFgCYAQAKAAkJJw2ibQBgAQAAAA==.Paprika:BAAALgADCgkJEQAAAA==.Parsie:BAAALgAFFAIJAgAAAA==.Patch:BAAALgADCgYJBgAAAA==.Pathibas:BAAALgADCgEJAQABLgAFFAMJBQAcALgZAA==.Pattycakes:BAABLgAECn8jAAIVAAkJLBZoSgDjAQAVAAkJLBZoSgDjAQAAAA==.',
Pe='Pencil:BAACLgAFFH8gAAIKAAYJoRubHAAeAQAKAAYJoRubHAAeAQAuAAQKfxsABAoACAkwHSM6APIBAAoACAkwHSM6APIBAAEAAwniBj1dAFcAABAAAQkAANAsAEUAAAAA.Pewpewlvltwo:BAACLgAFFH8UAAIUAAQJFgwEBgDwAAAUAAQJFgwEBgDwAAAuAAQKfygAAhQACAnQHmMJACYCABQACAnQHmMJACYCAAAA.Pewthree:BAAALgAECgYJCAABLgAFFAQJFAAUABYMAA==.',
Ph='Pherocious:BAABLgAECn8VAAIiAAUJ6xP/GQDfAAAiAAUJ6xP/GQDfAAAAAA==.',
Pi='Pintsize:BAAALgADCgIJAgAAAA==.',
Pl='Plaguelis:BAAALgADCgEJAQABLgAFFAMJBQAUADkHAA==.Plexy:BAAALgAFFAIJAgABLgAFFAYJDgAoAMURAA==.',
Po='Pobble:BAAALgADCgcJBwAAAA==.Pokitz:BAACLgAFFH8KAAIJAAMJyAMoPQCSAAAJAAMJyAMoPQCSAAAuAAQKf1IAAgkACQnyEuwMAF0BAAkACQnyEuwMAF0BAAAA.Poprock:BAAALgAECgEJAQAAAA==.Potus:BAAALgADCgQJBAAAAA==.',
Pr='Primordinor:BAACLgAFFH8HAAIoAAMJChNYNgC0AAAoAAMJChNYNgC0AAAuAAQKfyoAAygACQkCHsUOAIICACgACQkCHsUOAIICAAcABwnTF90yAOcBAAAA.Probnotalive:BAABLgAECn8nAAIRAAkJ5RoYHQB2AgARAAkJ5RoYHQB2AgAAAA==.Probnotferal:BAAALgAECgEJAQAAAA==.Probnoturmom:BAABLgAECn8dAAIeAAgJVxt2GAAYAgAeAAgJVxt2GAAYAgAAAA==.',
Qu='Quaektem:BAAALgAECgEJAQAAAA==.',
Ra='Raevyn:BAAALgAFFAEJAQAAAA==.Rafaiel:BAAALgAECgQJBAAAAA==.Rakan:BAABLgAECn9BAAIlAAkJPh4xBgCdAgAlAAkJPh4xBgCdAgAAAA==.Rakasha:BAAALgADCgkJCQAAAA==.Raktanu:BAAALgADCgkJCQABLgAECgkJaAAlAIEZAA==.Rallick:BAACLgAFFH8cAAILAAQJAhLnDwDZAAALAAQJAhLnDwDZAAAuAAQKfzEAAgsACQm3GLEQAJECAAsACQm3GLEQAJECAAAA.Ranloth:BAAALgAECgcJBwAAAA==.Ranì:BAACLgAFFH8GAAIZAAIJZwbUJwBcAAAZAAIJZwbUJwBcAAAuAAQKfzUAAhkACQnxFwIRANoBABkACQnxFwIRANoBAAAA.Raptorfarian:BAAALgAECgQJCAABLgAECgcJDwACAAAAAA==.Rathger:BAAALgAECggJEgAAAA==.Ravenscythe:BAAALgADCgEJAQAAAA==.Raydor:BAAALgAECggJDgAAAA==.',
Re='Reb:BAABLgAECn8mAAIdAAkJ6gSiOwAjAQAdAAkJ6gSiOwAjAQAAAA==.Redic:BAAALgAECgMJAwAAAA==.Regis:BAAALgAECgYJBgABLgAFFAMJBwAUAF8KAA==.Rellix:BAAALgADCgUJBQAAAA==.Rendkick:BAAALgADCgcJBwAAAA==.Rendwee:BAABLgAECn88AAIfAAkJuiN5AQAyAwAfAAkJuiN5AQAyAwAAAA==.Reuel:BAAALgAECgYJCgAAAA==.Revlon:BAABLgAECn8ZAAIMAAYJeA5JBgAAAQAMAAYJeA5JBgAAAQAAAA==.Rewolf:BAABLgAECn8UAAIHAAkJuhICKQAaAgAHAAkJuhICKQAaAgAAAA==.',
Rh='Rheemus:BAAALgAECgEJAwABLgAFFAIJBgARAGsbAA==.Rhul:BAAALgAECgcJDwAAAA==.',
Ri='Ricflairion:BAABLgAECn8bAAISAAgJTQmVQwAbAQASAAgJTQmVQwAbAQAAAA==.Rimuru:BAAALgAECgMJBgABLgAECgMJBwACAAAAAA==.',
Ro='Rodcet:BAACLgAFFH8HAAIJAAIJxR0phwClAAAJAAIJxR0phwClAAAuAAQKfzwAAgkACQnBJXUFAEkDAAkACQnBJXUFAEkDAAAA.Roflcopterr:BAABLgAECn85AAQLAAkJTxyHDQC6AgALAAkJTxyHDQC6AgAJAAYJ9QcB6QDTAAAnAAEJSAXuWgAZAAAAAA==.Rognan:BAAALgAECgMJAwAAAA==.Roku:BAAALgAECgEJAQAAAA==.Romina:BAAALgADCgEJBAAAAA==.Ronkin:BAAALgAECgUJAgAAAA==.Rookgue:BAACLgAFFH8YAAINAAYJyRDRAACHAQANAAYJyRDRAACHAQAuAAQKf10AAg0ACQnIH0kAAKwCAA0ACQnIH0kAAKwCAAAA.Rookoker:BAABLgAECn8mAAITAAgJ4QtUDQA4AQATAAgJ4QtUDQA4AQAAAA==.Rootsafarian:BAAALgADCgcJBwAAAA==.Rossa:BAAALgAECgEJAgAAAA==.Rossdair:BAABLgAECn8UAAMVAAgJDBEEhwBWAQAVAAYJxBYEhwBWAQAYAAIJwALnVABHAAABLgADCgUJCQACAAAAAA==.Rossperot:BAACLgAFFH8VAAIVAAMJDyTCJAAzAQAVAAMJDyTCJAAzAQAuAAQKfzUAAhUACQmiJGoBACsDABUACQmiJGoBACsDAAAA.Rothschild:BAAALgADCgEJAQAAAA==.Rottenfist:BAAALgAECgEJAQAAAA==.',
Sa='Sabako:BAAALgADCgcJCAAAAA==.Sacra:BAAALgADCgUJBQABLgAFFAEJAQACAAAAAA==.Saelara:BAAALgADCgcJCgAAAA==.Saelis:BAAALgADCgQJBAAAAA==.Sakaru:BAABLgAECn8bAAIDAAgJTw7ViABlAQADAAgJTw7ViABlAQABLgAECgkJLAAPADMQAA==.Salmoney:BAAALgAECgQJBAAAAA==.Salorin:BAAALgADCgYJCQAAAA==.Samgee:BAACLgAFFH8hAAIJAAQJGhwQMABSAQAJAAQJGhwQMABSAQAuAAQKf0YAAgkACQlgIWwRAAUDAAkACQlgIWwRAAUDAAAA.Sandormu:BAAALgADCgkJCQAAAA==.Saphas:BAAALgAECgMJAwAAAA==.Saynar:BAABLgAECn89AAIaAAkJxCPNBQAtAwAaAAkJxCPNBQAtAwAAAA==.',
Sc='Scattered:BAABLgAECn8fAAQKAAkJohMidABSAQAKAAcJsBIidABSAQABAAMJJBRLQACzAAAQAAEJggs9QgAtAAAAAA==.Scooter:BAAALgAECgUJCgAAAA==.Scyx:BAAALgADCgEJAQAAAA==.',
Se='Seba:BAACLgAFFH8dAAIDAAQJQhQsKgANAQADAAQJQhQsKgANAQAuAAQKf0EAAgMACQm2IKEWANECAAMACQm2IKEWANECAAAA.Sebushko:BAAALgADCgMJAQABLgAFFAQJHQADAEIUAA==.Selesne:BAABLgAECn8eAAIWAAkJ+QmPCwBfAQAWAAkJ+QmPCwBfAQAAAA==.Seraphicktwo:BAABLgAECn8uAAMeAAkJdhk5IADBAQAeAAcJnhg5IADBAQAdAAgJmhf3BwAbAQAAAA==.Seriana:BAABLgAECn8WAAIeAAgJfwvfNwAeAQAeAAgJfwvfNwAeAQAAAA==.Sermidas:BAACLgAFFH8KAAMlAAMJqRvJJgDSAAAlAAMJqRvJJgDSAAAcAAIJ3AevGwCYAAAuAAQKfyIAAyUACQk6H7gCAPACACUACQk6H7gCAPACABwABwnOFFw0ANgBAAEuAAUUBQkOABoA0wsA.',
Sh='Shadowcutter:BAAALgAECgEJAwABLgAECggJFAABAPQVAA==.Shaggmz:BAABLgAECn9FAAIcAAgJshj2AgDrAQAcAAgJshj2AgDrAQAAAA==.Shawnkin:BAAALgADCgQJAgAAAA==.Shigglez:BAAALgAECgkJCQAAAA==.Shinakuma:BAAALgAECgUJDgAAAA==.Shinma:BAABLgAECn9AAAInAAgJGwxPBAAxAQAnAAgJGwxPBAAxAQAAAA==.Shrubbery:BAABLgAECn8VAAIKAAcJ+wM5wQDKAAAKAAcJ+wM5wQDKAAAAAA==.Shymary:BAABLgAECn9BAAImAAgJaQy9BQB6AQAmAAgJaQy9BQB6AQAAAA==.',
Si='Siete:BAAALgAECgEJAQABLgAECgQJCQACAAAAAA==.Silvertip:BAAALgADCggJFQAAAA==.Silëx:BAABLgAECn8sAAIDAAkJExpEBwDOAQADAAkJExpEBwDOAQAAAA==.Silëxa:BAAALgAECgYJEQAAAA==.Sindiz:BAAALgAFFAEJAQAAAA==.Sioc:BAAALgAECgEJAQAAAA==.Siouxiesioux:BAAALgADCgYJCgAAAA==.Siyona:BAAALgADCgkJDAAAAA==.',
Sk='Skeith:BAAALgAECgkJCQAAAA==.Skits:BAAALgAECgIJAgAAAA==.Skyrah:BAAALgAECgYJBgAAAA==.Skyrie:BAAALgADCgQJBQAAAA==.',
Sl='Slagbröder:BAAALgADCgcJBwAAAA==.Slimjimz:BAAALgAECgQJBAAAAA==.Slohine:BAAALgAECgUJBQAAAA==.Sludgecrush:BAAALgAECgYJCwAAAA==.Slugondeez:BAACLgAFFH8GAAILAAIJ5hC1PwBkAAALAAIJ5hC1PwBkAAAuAAQKfxYAAgsABQkWI38iAPEBAAsABQkWI38iAPEBAAAA.',
Sm='Smacker:BAAALgAFFAMJAwAAAA==.Smallmike:BAAALgAECgIJAgAAAA==.Smitefist:BAAALgAECgIJAgABLgAECgQJBQACAAAAAA==.Smokiee:BAABLgAECn8ZAAIFAAkJvxBmNADKAQAFAAkJvxBmNADKAQAAAA==.',
Sn='Snacker:BAAALgAECgEJAQABLgAFFAMJAwACAAAAAA==.Snailtrail:BAABLgAECn8gAAIjAAkJ8wTOFAAIAQAjAAkJ8wTOFAAIAQAAAA==.Snark:BAABLgAECn8dAAIVAAYJrAgeGQDEAAAVAAYJrAgeGQDEAAAAAA==.Snarkkin:BAAALgAECgQJDAABLgAECgYJHQAVAKwIAA==.Snkyturtle:BAACLgAFFH8YAAIRAAQJYBMaQAAtAQARAAQJYBMaQAAtAQAuAAQKfzUAAhEACQllFH0/AOQBABEACQllFH0/AOQBAAAA.Snowkim:BAEBLgAECn8bAAInAAgJmh3yDAD2AQAnAAgJmh3yDAD2AQAAAA==.Snuzzle:BAABLgAECn89AAIEAAkJIxveCQBLAgAEAAkJIxveCQBLAgAAAA==.',
So='Soniic:BAAALgAECgIJAgAAAA==.Soullessfros:BAABLgAECn8nAAIVAAkJ7ROkPgAIAgAVAAkJ7ROkPgAIAgAAAA==.Soullessman:BAAALgADCgQJCAAAAA==.Soupshammich:BAAALgAECgEJAQAAAA==.Sourmash:BAAALgADCgkJCgAAAA==.',
Sp='Spaghet:BAABLgAECn8fAAIoAAkJNRkqHgDwAQAoAAkJNRkqHgDwAQAAAA==.Sparkleponi:BAAALgAECgEJAQABLgAECgcJMQADALIkAA==.Spillthetea:BAABLgAECn8UAAMIAAkJmQipWwAGAQAIAAkJmQipWwAGAQAPAAEJzgm8lwA4AAAAAA==.Sploot:BAAALgAECggJEgAAAA==.',
Sq='Squibbles:BAAALgAECgEJAQAAAA==.',
Sr='Srasjet:BAABLgAECn8kAAIHAAkJ9h0FCwAHAwAHAAkJ9h0FCwAHAwAAAA==.',
Ss='Ssimba:BAAALgAECggJDQAAAA==.',
St='Stabytha:BAABLgAECn8nAAMMAAgJzxH+HgCeAQAMAAgJDhH+HgCeAQANAAEJ1RdRJQA/AAAAAA==.Stark:BAAALgADCgYJCgAAAA==.Starlight:BAAALgAECgEJAQAAAA==.Stars:BAAALgAFFAEJAQAAAA==.Stealthed:BAAALgAECggJEwAAAA==.Stender:BAAALgAECgcJDAABLgAFFAcJEAAOAMAdAA==.Steàlthed:BAAALgAECgEJAQABLgAECggJEwACAAAAAA==.Stormae:BAAALgADCgMJAgAAAA==.Stormcall:BAABLgAECn8rAAIHAAkJ9h01FACqAgAHAAkJ9h01FACqAgAAAA==.Stratusfied:BAAALgAECgQJCQAAAA==.',
Su='Susbandaid:BAAALgADCgYJBgAAAA==.',
Sw='Sweetiefox:BAACLgAFFH8KAAIDAAUJqgOLeQDlAAADAAUJqgOLeQDlAAAuAAQKfx0AAgMACQnYDo0QADEBAAMACQnYDo0QADEBAAAA.Swiss:BAABLgAECn8eAAIoAAkJhxCZKgCdAQAoAAkJhxCZKgCdAQAAAA==.',
Sy='Syllai:BAAALgAECgYJBgAAAA==.Symboli:BAAALgADCgQJBAAAAA==.Syphus:BAAALgADCgQJBAAAAA==.',
['Sá']='Sáëgárón:BAABLgAECn8ZAAMcAAgJahbCJwC9AQAcAAgJahbCJwC9AQAlAAEJpwX7hgAiAAAAAA==.',
Ta='Ta:BAAALgADCgMJAwAAAA==.Tacyon:BAAALgADCggJFgAAAA==.Taliden:BAABLgAECn8aAAIcAAYJLRNlCgD2AAAcAAYJLRNlCgD2AAAAAA==.Tallera:BAAALgADCgEJAgAAAA==.Talo:BAAALgADCgMJAwAAAA==.Tanddora:BAAALgAECgMJAwAAAA==.Taniyah:BAAALgAECgQJCAAAAA==.Tankinstine:BAAALgAECgUJCwAAAA==.Taraylda:BAABLgAECn8bAAMmAAkJVRgMGgDIAQAmAAgJIhgMGgDIAQAdAAMJdA2JXQChAAAAAA==.Tarful:BAAALgADCgQJBAAAAA==.Tarzand:BAAALgADCgEJAQABLgADCgcJDwACAAAAAA==.Tazo:BAACLgAFFH8IAAIJAAIJbAzIQwB/AAAJAAIJbAzIQwB/AAAuAAQKfy0AAgkACQmKEPtzAIYBAAkACQmKEPtzAIYBAAAA.Tazu:BAAALgAECgUJBQAAAA==.Taàrna:BAAALgADCgYJBQAAAA==.',
Te='Tearek:BAACLgAFFH8FAAIaAAMJWw/FZgC/AAAaAAMJWw/FZgC/AAAuAAQKfx0AAhoABwlVHF06AN0BABoABwlVHF06AN0BAAAA.Tearik:BAAALgAECgYJBAAAAA==.Tecdor:BAAALgAECgQJBAAAAA==.Temla:BAACLgAFFH8GAAIRAAIJMgRGkQB8AAARAAIJMgRGkQB8AAAuAAQKfy8AAhEACQlHFrg7APEBABEACQlHFrg7APEBAAAA.Tenga:BAAALgAECgQJBAAAAA==.Teronfiggy:BAABLgAECn8dAAMVAAkJLQ1LfgBnAQAVAAgJjA5LfgBnAQAYAAEJlgNsFAAwAAAAAA==.',
Tf='Tfirs:BAACLgAFFH8hAAIEAAUJ0BISCwDNAAAEAAUJ0BISCwDNAAAuAAQKfzAAAgQACQnSGZ4OAPsBAAQACQnSGZ4OAPsBAAEuAAEKCQkTAAIAAAAA.',
Th='Thartilidan:BAAALgAECgYJEQABLgAECgkJGgAMAIEYAA==.Thegoodboi:BAAALgAFFAIJAgAAAA==.Theokoles:BAAALgAECgQJBQAAAA==.Thepaladin:BAAALgAECgIJAQAAAA==.Thickblòód:BAAALgAFFAIJAgAAAA==.',
Ti='Tilythia:BAAALgADCgUJBQAAAA==.Tinn:BAAALgADCgEJAQAAAA==.',
To='Tona:BAAALgADCgMJAwAAAA==.Toospookie:BAAALgADCgQJAgAAAA==.Tophu:BAAALgADCgcJBwAAAA==.Torkz:BAAALgAECgMJBwAAAA==.Totem:BAAALgAECgUJBQAAAA==.',
Tr='Trabeajin:BAAALgAECgYJDAAAAA==.Tramplip:BAABLgAECn86AAIBAAgJkhS6CQCrAQABAAgJkhS6CQCrAQAAAA==.Treecloud:BAACLgAFFH8FAAIGAAMJlhWFEgDUAAAGAAMJlhWFEgDUAAAuAAQKf00AAwYACQldJMYDACkDAAYACQldJMYDACkDAAQACQmEFvkNAAMCAAAA.Trevian:BAABLgAECn8cAAIJAAkJfRNsSgDnAQAJAAkJfRNsSgDnAQAAAA==.Trinitee:BAAALgAECgEJAQABLgAECgMJBwACAAAAAA==.',
Tu='Tub:BAAALgAECgQJBAABLgAFFAQJDAAPAHwLAA==.Tuluxxi:BAACLgAFFH8FAAIHAAMJshf4HQDLAAAHAAMJshf4HQDLAAAuAAQKf1IAAgcACQnwInsEAG8DAAcACQnwInsEAG8DAAAA.Turbodiesell:BAAALgAECgEJAwAAAA==.Turborunic:BAAALgADCgkJGwAAAA==.Turdfergesun:BAAALgAECgEJAQAAAA==.Turiae:BAACLgAFFH8SAAQSAAYJgCBBIgBPAQASAAQJ/B5BIgBPAQAbAAEJZAGYLAA2AAATAAEJAADXEQAAAAAuAAQKfy8ABBIACQlVInoEACEDABIACQlVInoEACEDABMABwnZFsgQANEBABsABQkhCaQ0AMgAAAAA.Tuskerz:BAAALgAECgEJAwAAAA==.Tusobrinna:BAAALgAECgUJDAAAAA==.Tutter:BAAALgADCgQJBAAAAA==.Tuuldd:BAAALgADCggJCAAAAA==.',
Tw='Twunk:BAAALgAECggJEAAAAA==.',
Ty='Tychuus:BAAALgAFFAIJBAAAAA==.Typhlotic:BAAALgADCgMJAwAAAA==.Tyrennius:BAAALgAECgQJBAAAAA==.Tyrianis:BAABLgAECn8rAAMMAAkJNyGeCgB5AgAMAAkJSSCeCgB5AgANAAMJzh6rEwDFAAAAAA==.',
Tz='Tzxdh:BAAALgAECgUJBQABLgAFFAMJAQACAAAAAA==.Tzxdruid:BAAALgAECgEJAQABLgAFFAMJAQACAAAAAA==.',
Ug='Uglymancer:BAABLgAECn8eAAMKAAkJ+RVyMgAPAgAKAAkJ+RVyMgAPAgABAAEJAACGVAAAAAAAAA==.',
Uj='Ujimas:BAABLgAECn8XAAMoAAcJlBFnWgDVAAAoAAYJ/BNnWgDVAAAHAAYJXQkCiwDFAAAAAA==.Ujong:BAAALgAECgcJDgABLgAECgcJMQADALIkAA==.',
Un='Unchartedd:BAAALgADCgEJAQAAAA==.',
Va='Vaenira:BAAALgADCgUJBgAAAA==.Vako:BAABLgAECn8UAAIUAAQJyRKiIgDiAAAUAAQJyRKiIgDiAAAAAA==.Valdara:BAAALgADCgkJEgAAAA==.Valemon:BAAALgAECgIJAgAAAA==.Vampireshade:BAABLgAECn8/AAIWAAkJ5hDKAACKAQAWAAkJ5hDKAACKAQAAAA==.Vanimao:BAABLgAECn81AAQFAAkJdQ+tPACxAQAFAAkJdQ+tPACxAQAGAAcJjwlbRQD3AAAEAAcJrwzqLgDyAAAAAA==.Vankman:BAAALgADCgcJBwAAAA==.Vannaka:BAAALgADCgEJAQAAAA==.',
Vb='Vbull:BAAALgAECgEJAQAAAA==.',
Ve='Vedrolan:BAAALgADCgUJDgABLgAFFAQJEQAnACIhAA==.Velifya:BAAALgADCgMJAwAAAA==.Velindon:BAAALgADCgYJBgAAAA==.Velissari:BAABLgAECn85AAIOAAgJphsPAgAlAgAOAAgJphsPAgAlAgAAAA==.Velonar:BAAALgADCgEJAQAAAA==.Velouria:BAABLgAECn9SAAQEAAkJ2CJVAgAcAwAEAAkJwCJVAgAcAwAGAAgJ6h8SDQDIAgAFAAIJ9QSXwABGAAAAAA==.Venatra:BAAALgAECgYJDwAAAA==.Verudora:BAAALgADCgcJBwAAAA==.Vexira:BAAALgADCgcJBwAAAA==.',
Vi='Violet:BAABLgAECn8gAAIbAAgJJBe/CwAdAgAbAAgJJBe/CwAdAgAAAA==.Violette:BAABLgAECn83AAIRAAkJLRMZCgCeAQARAAkJLRMZCgCeAQAAAA==.Visix:BAAALgAECgUJBgAAAA==.Vitt:BAAALgAECgEJAgAAAA==.',
Vo='Voidchacha:BAAALgADCgEJAQAAAA==.Voidlink:BAACLgAFFH8FAAImAAMJXhqxEgDoAAAmAAMJXhqxEgDoAAAuAAQKfy0AAiYACQmzFGcbAPMBACYACQmzFGcbAPMBAAAA.Voidmistress:BAABLgAECn8nAAIDAAcJGRggcQCXAQADAAcJGRggcQCXAQAAAA==.Voidpup:BAABLgAECn8oAAIaAAcJYxwqPwDMAQAaAAcJYxwqPwDMAQAAAA==.Volgrimm:BAABLgAECn8bAAIXAAgJKwsYNAAvAQAXAAgJKwsYNAAvAQAAAA==.Volitaire:BAAALgADCgYJBgAAAA==.Volkân:BAAALgAECgUJBQAAAA==.Vonbek:BAAALgAECgMJAwAAAA==.',
Vy='Vynethan:BAAALgAECgEJAgAAAA==.',
['Vé']='Véngence:BAABLgAECn8YAAIVAAcJLRHggABiAQAVAAcJLRHggABiAQAAAA==.',
['Vê']='Vêx:BAAALgADCgYJBgAAAA==.',
Wa='Wabalabalosh:BAAALgADCgkJCQAAAA==.Wabgucci:BAAALgADCgUJBQAAAA==.Wabwum:BAAALgAECgMJAwAAAA==.Wackyrellek:BAAALgAECgcJDAAAAA==.Wakaekwondo:BAAALgAECgEJAQAAAA==.Wakarisma:BAAALgAECgEJAQAAAA==.Wakataclysm:BAAALgAECgMJAwAAAA==.Wanda:BAAALgAECgkJDQAAAA==.Wangao:BAABLgAFFH8IAAIXAAMJJAp9PgCtAAAXAAMJJAp9PgCtAAABLgAFFAQJEQAnACIhAA==.Warbluster:BAAALgADCgIJAgAAAA==.Warchylde:BAAALgADCgkJHQAAAA==.Warolderoy:BAACLgAFFH8FAAIcAAMJuBn9EgDtAAAcAAMJuBn9EgDtAAAuAAQKf0sAAhwACQmlJMEDACwDABwACQmlJMEDACwDAAAA.Warshy:BAAALgAECgQJBAAAAA==.',
We='Weedshaman:BAAALgAECgEJAwAAAA==.Weedwax:BAAALgAECgQJBAAAAA==.Weil:BAAALgADCgIJAgAAAA==.',
Wh='Whiinuss:BAABLgAECn8UAAIJAAcJlw25fwB7AQAJAAcJlw25fwB7AQAAAA==.Whytrabbit:BAAALgAECgIJAgAAAA==.',
Wi='Wigglesdeath:BAAALgAECgUJBQAAAA==.',
Wl='Wldeagle:BAAALgAECgQJBQAAAA==.',
Wo='Woker:BAAALgAECgcJEQABLgAFFAMJBQAUADkHAA==.Woodpig:BAABLgAECn8vAAQFAAkJ2SFfBgBSAwAFAAkJ2SFfBgBSAwAEAAIJVBMfUQBrAAAGAAMJcAo0cQBlAAAAAA==.Woogie:BAAALgAECgQJCwAAAA==.',
Wr='Wrangle:BAAALgADCgEJAQAAAA==.',
Wy='Wyldshade:BAAALgADCgYJCAAAAA==.Wyrm:BAAALgAECgUJBQABLgAECgUJCgACAAAAAA==.',
Xa='Xaladin:BAABLgAECn8dAAIOAAkJVgypHwB8AQAOAAkJVgypHwB8AQAAAA==.Xantheos:BAAALgAECgEJAgAAAA==.Xathas:BAAALgAECgQJBAAAAA==.',
Xe='Xenna:BAAALgAECgYJCgAAAA==.Xeq:BAAALgAECgcJEAAAAA==.',
Xi='Xiata:BAAALgAECgkJEwAAAA==.Xiu:BAAALgAECgUJBgAAAA==.',
Xr='Xrp:BAAALgADCgQJBQAAAA==.',
Xt='Xtragun:BAAALgAECgEJAQABLgAFFAMJAwACAAAAAA==.',
Ye='Yeoman:BAABLgAECn8qAAMcAAkJ6xIxNQB0AQAcAAkJ6xIxNQB0AQAZAAQJHwkuCQCOAAAAAA==.Yeos:BAAALgAECgQJBAABLgAECgkJKgAcAOsSAA==.',
Yg='Yggdralith:BAAALgAECgkJJAAAAQ==.',
Yi='Yiznusin:BAAALgAECgEJAgAAAA==.',
Ym='Yme:BAAALgAECgMJAwAAAA==.',
Yo='Yourdeath:BAAALgAECgkJBAAAAA==.',
Yu='Yunosmall:BAAALgADCgIJAgAAAA==.Yunosmart:BAAALgAECgYJCQAAAA==.',
['Yú']='Yúm:BAAALgAECgEJAQAAAA==.',
Za='Zackoh:BAAALgAECgEJAQAAAA==.Zaen:BAACLgAFFH8bAAIKAAQJdxV/HAAeAQAKAAQJdxV/HAAeAQAuAAQKfzcAAwoACQmdHykVAKYCAAoACQmdHykVAKYCAAEAAwnUC7NDAKYAAAAA.Zagreus:BAAALgADCgcJCAAAAA==.Zakikaz:BAAALgAECgQJBQABLgAFFAMJAwACAAAAAA==.Zakkah:BAAALgAECgEJAQABLgAFFAQJDAAIAFgkAA==.Zarkir:BAACLgAFFH8WAAMgAAQJixyRCQBWAQAgAAQJixyRCQBWAQAVAAMJmQwn7AB+AAAuAAQKfyYABCAACQmfJDECAPUCACAACQkqIjECAPUCABUABwnCIe1BAP0BABgABwmtF5oZAIcBAAEuAAQKBgkXAAMApyIA.Zarkìr:BAABLgAECn8XAAIDAAYJpyKQZwAIAgADAAYJpyKQZwAIAgAAAA==.Zaues:BAAALgAECgMJBAAAAA==.',
Ze='Zelily:BAABLgAECn8XAAIRAAkJQQiVmgAMAQARAAkJQQiVmgAMAQAAAA==.Zenarri:BAAALgADCgYJBwAAAA==.Zenasdan:BAAALgADCgYJBgAAAA==.Zepha:BAAALgAECgcJDQAAAA==.Zerø:BAAALgAECgIJAgABLgAECgYJFwADAKciAA==.',
Zl='Zlyandien:BAAALgADCggJDwABLgAECgkJGwAmAFUYAA==.',
Zo='Zoomkin:BAAALgAFFAEJAQABLgAFFAMJAwACAAAAAA==.Zornov:BAABLgAECn8jAAMnAAgJjx4zCwAVAgAnAAgJjx4zCwAVAgALAAMJJggPcgBuAAAAAA==.Zortt:BAAALgAECgEJAgAAAA==.',
Zu='Zulrich:BAAALgAECgUJBQAAAA==.',
Zv='Zvirax:BAAALgAECgUJAgAAAA==.',
['Ëu']='Ëuni:BAABLgAECn8ZAAIRAAgJ6QqBlQAVAQARAAgJ6QqBlQAVAQAAAA==.',
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
