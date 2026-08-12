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

local lookup = {'Warlock-Destruction','Shaman-Elemental','Mage-Frost','Druid-Guardian','Druid-Restoration','Druid-Balance','Unknown-Unknown','Shaman-Restoration','Monk-Mistweaver','Paladin-Retribution','Warlock-Demonology','Paladin-Holy','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Havoc','Monk-Windwalker','Warlock-Affliction','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','DeathKnight-Unholy','Rogue-Outlaw','Monk-Brewmaster','DeathKnight-Blood','Hunter-Marksmanship','Warrior-Protection','DemonHunter-Devourer','Evoker-Preservation','Warrior-Fury','Priest-Shadow','Priest-Holy','Druid-Feral','DeathKnight-Frost','Hunter-Survival','DemonHunter-Vengeance','Mage-Arcane','Warrior-Arms','Priest-Discipline','Paladin-Protection',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=46,date='2026-08-11',data={Ab='Abarlton:BAAALgAFFAEJAQABLgAECggJFAABAPQVAA==.Aberforthd:BAAALgAECgkJCgAAAA==.',
Ac='Acorn:BAABLgAFFH8FAAICAAMJww4PHwCpAAACAAMJww4PHwCpAAAAAA==.',
Ad='Adabeam:BAAALgADCgcJCwAAAA==.Adagio:BAACLgAFFH8FAAIDAAMJKgjbRQCzAAADAAMJKgjbRQCzAAAuAAQKf0QAAgMACQkFHhcmAIMCAAMACQkFHhcmAIMCAAAA.Adetalo:BAABLgAECn8lAAIEAAkJ8Re+DgD5AQAEAAkJ8Re+DgD5AQAAAA==.Adiara:BAAALgAECgMJAwAAAA==.Aditu:BAABLgAECn85AAMFAAkJTx4ADwDdAgAFAAkJTx4ADwDdAgAGAAUJLRGUEQCxAAAAAA==.',
Ae='Aelis:BAAALgADCgcJCAAAAA==.Aemulo:BAAALgAECgUJBwAAAA==.Aerith:BAAALgADCgcJBwAAAA==.Aessone:BAAALgAECgYJCQABLgAFFAQJHwADAEIUAA==.Aetheris:BAAALgAFFAEJBAABLgAFFAMJAQAHAAAAAA==.',
Ag='Agasonex:BAAALgADCgMJAwAAAA==.Aggroholic:BAAALgAECgQJBwABLgADCgYJEAAHAAAAAA==.',
Ai='Airent:BAABLgAECn8vAAMFAAkJrBN+BADkAQAFAAgJshN+BADkAQAGAAgJOhU4CABFAQAAAA==.Aiyana:BAAALgAECgYJDgAAAA==.',
Ak='Akhuahwe:BAAALgADCgUJAQAAAA==.Akiirii:BAAALgAECgEJAQAAAA==.',
Al='Alaestel:BAAALgAECgQJBwAAAA==.Aldo:BAAALgAECgcJDwAAAA==.Alenthele:BAAALgAECgEJAwAAAA==.Aletheia:BAAALgAFFAEJAQAAAA==.Alkaraho:BAAALgAECgMJAwAAAA==.Alleriya:BAAALgAECgEJAQABLgAFFAUJDgAIAH0OAA==.Alleyways:BAACLgAFFH8MAAIJAAQJWCSdFgAkAQAJAAQJWCSdFgAkAQAuAAQKfzwAAgkACQn3JYIBAMcDAAkACQn3JYIBAMcDAAAA.Allurâ:BAAALgADCgEJAQAAAA==.Alzey:BAABLgAECn8oAAIKAAkJjQ+ZawCXAQAKAAkJjQ+ZawCXAQAAAA==.',
Am='Ambeon:BAAALgADCgUJBQAAAA==.Ammathindis:BAAALgAECgYJBgAAAA==.Ammutseba:BAAALgADCggJCAAAAA==.Amplers:BAAALgADCgUJBwAAAA==.',
An='Andyxdd:BAAALgAECgIJAwABLgAFFAkJKgADAHAhAA==.Angelbane:BAAALgADCgQJBAAAAA==.Angina:BAAALgAECgIJBQAAAA==.Annarcis:BAABLgAECn81AAILAAkJXhAbBwCxAQALAAkJXhAbBwCxAQAAAA==.Anotherdk:BAAALgAECgYJBgABLgAECgkJKQAMAKojAA==.Anthiell:BAAALgADCgEJAQAAAA==.Antiman:BAABLgAECn8oAAIKAAkJQgz5awCWAQAKAAkJQgz5awCWAQAAAA==.Anäster:BAAALgAFFAEJAQABLgAFFAUJGAAKABIQAA==.',
Ap='Aplcyder:BAABLgAECn84AAIFAAkJVwy1RwBxAQAFAAkJVwy1RwBxAQAAAA==.',
Ar='Arabisa:BAAALgAECgQJBAAAAA==.Arabloom:BAAALgAECgQJBAAAAA==.Arachnid:BAABLgAECn8yAAIDAAcJsiRFMQCtAgADAAcJsiRFMQCtAgAAAA==.Aragorn:BAAALgADCgkJDQAAAA==.Aratyn:BAABLgAECn8eAAIDAAkJsg9sYAC/AQADAAkJsg9sYAC/AQAAAA==.Ariane:BAAALgAECgIJAgAAAA==.Army:BAAALgAECgQJBwABLgAFFAMJAwAHAAAAAA==.',
As='Asanot:BAAALgAECgUJBQAAAA==.Ascendance:BAAALgAECgEJAQAAAA==.',
At='Atalisk:BAAALgAECgYJBgAAAA==.Ati:BAAALgADCgIJAgAAAA==.',
Au='Audxo:BAAALgADCgMJAwAAAA==.Autumn:BAAALgADCgQJBQAAAA==.',
Ay='Ayayron:BAAALgADCgQJBAAAAA==.',
Ba='Backhawk:BAAALgADCgcJEAAAAA==.Backsurgery:BAABLgAFFH8RAAMNAAgJ9SBjCQALAgANAAgJuh5jCQALAgAOAAIJUyE2DQBhAAAAAA==.Baern:BAAALgAECgIJAgAAAA==.Baerrn:BAABLgAECn8rAAIPAAkJkgy1CQAMAQAPAAkJkgy1CQAMAQAAAA==.Baggins:BAAALgADCgEJAQAAAA==.Baltazaris:BAAALgAECgUJCAAAAA==.Bamboo:BAAALgAECgYJCQABLgAFFAMJCgAQAIAZAA==.Barais:BAAALgADCgYJCQAAAA==.Baricia:BAABLgAECn8dAAIDAAkJIQ2HcgCVAQADAAkJIQ2HcgCVAQAAAA==.Barix:BAAALgAECgEJBAAAAA==.Barnd:BAAALgADCggJDwAAAA==.Barrin:BAABLgAECn9BAAMRAAkJ6Rw2BQA6AgARAAkJ6Rw2BQA6AgALAAUJQgiUvADRAAAAAA==.Bastim:BAAALgAECgQJDAAAAA==.Baussassbich:BAAALgAECgQJBAABLgAECgkJJAALAE4hAA==.Bawnchu:BAAALgAECgQJDAAAAA==.',
Be='Beastmaster:BAACLgAFFH8FAAISAAMJvSBqVgD6AAASAAMJvSBqVgD6AAAuAAQKfzAAAhIACQmpJH8UAK4CABIACQmpJH8UAK4CAAAA.Beatricks:BAAALgAECgQJBQAAAA==.Beefcakell:BAAALgADCgcJDQAAAA==.Beiki:BAAALgAECgcJEAAAAA==.Belthar:BAAALgAECgYJCwAAAA==.Bently:BAABLgAECn8iAAMTAAcJpSHFHwDaAQATAAcJ9R/FHwDaAQAUAAUJGCMtEwCvAQAAAA==.Berexis:BAAALgAECgkJEQAAAA==.',
Bi='Bissafiyah:BAACLgAFFH8rAAIVAAgJVSKTAAB3AgAVAAgJVSKTAAB3AgAuAAQKf2UAAhUACQn4JgUAAKoDABUACQn4JgUAAKoDAAAA.Bittertea:BAAALgADCgEJAQAAAA==.Biznasty:BAAALgAECgEJAwAAAA==.',
Bl='Bloodgon:BAABLgAFFH8HAAIWAAMJUhjRjADwAAAWAAMJUhjRjADwAAAAAA==.Bluetuesday:BAAALgAECgQJBwAAAA==.',
Bo='Bogart:BAAALgAECgEJAQAAAA==.Bohica:BAABLgAECn84AAIIAAkJRhFXPQC5AQAIAAkJRhFXPQC5AQAAAA==.Bonechop:BAAALgAECgEJAgAAAA==.Bootymeat:BAAALgADCgEJAQAAAA==.Bowtox:BAAALgAECgEJAQAAAA==.Boyakasha:BAABLgAECn9HAAIXAAkJkxWOAAAYAgAXAAkJkxWOAAAYAgAAAA==.',
Br='Bratislava:BAAALgAECgYJEAAAAA==.Brelo:BAAALgAECgEJAQAAAA==.Brewfu:BAAALgADCgIJAgAAAA==.Brewpub:BAAALgADCgQJBAAAAA==.Brewsome:BAABLgAECn9BAAQQAAkJQyF8BgDkAgAQAAkJQyF8BgDkAgAYAAkJ1RhjEgAhAgAJAAEJ0xHbtAA7AAAAAA==.Bruceprime:BAAALgAECgkJAQAAAA==.Bryybryy:BAABLgAECn8YAAMZAAkJ6R7RAQB9AgAZAAkJ6R7RAQB9AgAWAAEJ8AvGWQAkAAAAAA==.Bryycelest:BAABLgAECn8jAAIYAAgJ5BptFwDuAQAYAAgJ5BptFwDuAQABLgAECgkJGAAZAOkeAA==.Bryydruid:BAAALgAECgEJAQABLgAECgkJGAAZAOkeAA==.Brz:BAAALgAECgYJEAAAAA==.Brådòn:BAAALgAECgYJEgAAAA==.',
Bu='Bubleherth:BAAALgAECgMJAwABLgAECggJHAAaAGoWAA==.Bucket:BAABLgAECn8wAAIbAAkJEho3CgBPAgAbAAkJEho3CgBPAgAAAA==.Bunkiee:BAAALgADCgkJIQAAAA==.Bunnybane:BAAALgAECgkJEAAAAA==.Burgundy:BAAALgAECgkJCQAAAA==.Burlath:BAAALgADCgMJBgAAAA==.Burny:BAABLgAECn8aAAIDAAcJVCVMJgDZAgADAAcJVCVMJgDZAgABLgAFFAQJDAAJAFgkAA==.Buttadogg:BAAALgAECgcJDwAAAA==.',
By='Byaez:BAAALgADCgQJBAAAAA==.',
['Bè']='Bèth:BAAALgAECgQJAQAAAA==.',
['Bë']='Bëckey:BAAALgADCgIJAgAAAA==.',
Ca='Calyx:BAABLgAECn8xAAIcAAcJTwnCFwDIAAAcAAcJTwnCFwDIAAAAAA==.Canadani:BAAALgAECgcJDQAAAA==.Candorite:BAABLgAECn8dAAMTAAkJbw3aQAAmAQATAAcJzQzaQAAmAQAdAAIJKA6fMABoAAAAAA==.Caphriel:BAABLgAECn8dAAIeAAkJQB3LFwAvAgAeAAkJQB3LFwAvAgAAAA==.Capita:BAABLgAECn8cAAIDAAgJjAmboQA4AQADAAgJjAmboQA4AQAAAA==.Captndave:BAAALgADCgMJAwAAAA==.Carrian:BAAALgAECgEJAgAAAA==.Carsinegan:BAAALgAECgcJDQAAAA==.Cassica:BAABLgAECn8dAAMfAAcJbhlQOAA0AQAfAAcJbhlQOAA0AQAgAAIJ1gnNZgBIAAAAAA==.Catchdezhanz:BAAALgADCgcJBwABLgAECgcJMQAMAJ8WAA==.Catskin:BAABLgAECn8jAAMhAAkJuiBTBAC9AgAhAAgJKiNTBAC9AgAFAAYJ8htBPQCeAQAAAA==.',
Ce='Celivalasha:BAAALgADCgUJBQAAAA==.Cell:BAABLgAECn8jAAIYAAgJTSQqBQA3AwAYAAgJTSQqBQA3AwAAAA==.Cet:BAAALgADCgUJBQABLgAFFAEJAQAHAAAAAA==.',
Ch='Chadvader:BAAALgADCgIJAgAAAA==.Chainlink:BAAALgADCgYJBgAAAA==.Chalee:BAAALgAECgEJAQAAAA==.Chandraskhar:BAAALgADCgIJAgAAAA==.Chanpagne:BAAALgAECgIJAgAAAA==.Charkle:BAABLgAECn8YAAISAAcJWhhiSADIAQASAAcJWhhiSADIAQAAAA==.Chayea:BAAALgADCgEJAQAAAA==.Chicknraptor:BAAALgAECgUJBQAAAA==.Chillylilly:BAABLgAECn8vAAMZAAkJbSV4AgAnAwAZAAkJbSV4AgAnAwAiAAQJ4Ry0EwBBAQAAAA==.Chlorophyll:BAAALgAECgQJBAAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chopsuoy:BAAALgAECgEJAQAAAA==.Chummie:BAABLgAECn8wAAMLAAkJ2h/2GACOAgALAAkJcR/2GACOAgARAAYJdxxDCADHAQAAAA==.',
Ci='Ciandoril:BAABLgAECn8rAAUGAAkJVxeQJACnAQAGAAcJ8heQJACnAQAEAAQJ8BIhCgDkAAAhAAMJHhTVLACyAAAFAAMJ+Q8rjwCXAAAAAA==.Cielcin:BAAALgAFFAMJAwAAAA==.Ciremiih:BAAALgAECgEJAQAAAA==.Citymage:BAACLgAFFH8LAAIDAAUJWAWBcwD4AAADAAUJWAWBcwD4AAAuAAQKfykAAgMACQmbF0JGAAgCAAMACQmbF0JGAAgCAAAA.Cixelsyd:BAAALgADCgYJCwABLgAFFAcJFAAKANMOAA==.',
Cl='Clamchowda:BAABLgAECn8vAAMcAAkJoBsRJwAvAgAcAAkJKxkRJwAvAgAPAAUJUh5wIwCiAQAAAA==.',
Co='Codê:BAABLgAECn8oAAILAAkJAhm1JABMAgALAAkJAhm1JABMAgAAAA==.Coffeecup:BAAALgADCgIJAgAAAA==.Colchagua:BAAALgAECgEJAgAAAA==.Corride:BAABLgAECn8rAAIjAAgJgR8AEQAkAgAjAAgJgR8AEQAkAgAAAA==.Corspar:BAAALgAECgQJBgAAAA==.',
Cr='Crazyeyes:BAAALgADCgYJCQAAAA==.Crimsondeath:BAABLgAECn9JAAIZAAkJVw80BQB5AQAZAAkJVw80BQB5AQAAAA==.Crom:BAAALgAECgIJBAAAAA==.Crutch:BAABLgAECn8mAAMIAAkJyRy9DADzAgAIAAkJyRy9DADzAgAVAAUJCBWQGgAuAQAAAA==.Crystanikus:BAAALgAECgQJBQAAAA==.',
Cu='Cuckenjoyer:BAAALgAECgYJCgAAAA==.',
Cy='Cyclonian:BAAALgAECgEJAgABLgAECgQJBQAHAAAAAA==.Cyprus:BAAALgAECgkJDAAAAA==.',
Da='Daddytrump:BAABLgAECn8eAAIJAAkJPw8kMgCvAQAJAAkJPw8kMgCvAQAAAA==.Daelric:BAAALgAECgYJDgAAAA==.Daender:BAACLgAFFH8GAAISAAIJaxvaegCiAAASAAIJaxvaegCiAAAuAAQKfzAAAxIACQl3JGQIABcDABIACQl3JGQIABcDABoAAQmCGAk7ADUAAAAA.Daenor:BAAALgAECgQJBwAAAA==.Dairydemon:BAACLgAFFH8dAAIkAAQJjAqjBQCrAAAkAAQJjAqjBQCrAAAuAAQKfzgAAyQACQkvEBsMAJYBACQACQkSDxsMAJYBAA8AAQmPDbokAC0AAAAA.Damageus:BAACLgAFFH8VAAMDAAMJ7x+YLQAXAQADAAMJ7x+YLQAXAQAlAAEJ8BsBBgBUAAAuAAQKfx8AAwMACAnqIjkkAOICAAMACAnqIjkkAOICACUAAQlGIGYLAFwAAAAA.Danhausen:BAAALgAECgEJAgAAAA==.Daniryl:BAEBLgAECn8bAAIFAAgJfxW1LAD1AQAFAAgJfxW1LAD1AQAAAA==.Dar:BAAALgAECgQJCwAAAA==.Darcnescoach:BAABLgAECn8YAAImAAcJHRNkBABLAQAmAAcJHRNkBABLAQAAAA==.Darcness:BAABLgAECn8lAAQOAAYJkhmvDABgAQAOAAYJhxavDABgAQANAAUJTxZQOABSAQAXAAEJIRayIQBEAAAAAA==.Darcside:BAABLgAECn9DAAMfAAkJERf1AgAZAgAfAAkJERf1AgAZAgAnAAUJtwV5EwCrAAAAAA==.Darkclouds:BAAALgADCgIJAgAAAA==.Darksoul:BAABLgAECn8UAAILAAkJWwYiiAApAQALAAkJWwYiiAApAQABLgAECgkJGwAnAFUYAA==.Darkxwraith:BAABLgAECn8aAAIMAAcJuhnkCAA2AQAMAAcJuhnkCAA2AQAAAA==.Dashtoolite:BAABLgAECn8eAAIcAAgJNw23bABKAQAcAAgJNw23bABKAQAAAA==.Datsombeech:BAAALgAECgcJBwAAAA==.Datsumbeech:BAABLgAECn8mAAIiAAkJDg60DgCKAQAiAAkJDg60DgCKAQAAAA==.',
Dc='Dcoi:BAAALgADCgQJBAAAAA==.',
De='Deajer:BAAALgADCgYJBwAAAA==.Deathsabeach:BAAALgAECgEJAQAAAA==.Deathvìxen:BAABLgAECn8XAAMfAAgJyAc2PgAYAQAfAAgJyAc2PgAYAQAnAAMJiwYxbgBPAAAAAA==.Debit:BAAALgAECgcJEwAAAA==.Demonhunter:BAACLgAFFH8KAAIcAAQJkiHQPQAwAQAcAAQJkiHQPQAwAQAuAAQKfx0AAhwACAk/JKkKAC4DABwACAk/JKkKAC4DAAAA.Demonwoogie:BAAALgADCgYJBgABLgAECgQJCwAHAAAAAA==.Dendrophilia:BAAALgAECgYJCgAAAA==.Densamin:BAABLgAECn8oAAQKAAkJ+BWpQAAFAgAKAAkJ+BWpQAAFAgAMAAIJugH4hgA9AAAoAAEJ4wuFUwApAAAAAA==.Deviyn:BAAALgADCgIJAgAAAA==.Devourussy:BAAALgADCgkJCQAAAA==.Devra:BAAALgADCggJCAAAAA==.Dexter:BAAALgAECgEJAgAAAA==.Deàdly:BAABLgAECn8ZAAMiAAcJHyFiCAAIAgAiAAcJHyFiCAAIAgAWAAMJghmcJAF+AAAAAA==.',
Dh='Dhaynk:BAAALgAFFAEJAQAAAA==.',
Di='Dietchrist:BAAALgAECggJEwAAAA==.Dilligaf:BAAALgADCggJCAAAAA==.',
Dk='Dkanabiss:BAAALgAECgMJBAAAAA==.Dkinabox:BAAALgAECgUJDQAAAA==.',
Do='Docbaba:BAAALgAFFAEJAgAAAA==.Doh:BAAALgADCgIJAgAAAA==.Doist:BAAALgAECgIJAgAAAA==.Donngaz:BAAALgAECgMJBgAAAA==.Dookey:BAAALgAECgMJAwAAAA==.Doomwood:BAAALgADCgkJAQAAAA==.',
Dr='Drakeskin:BAAALgADCgEJAQAAAA==.Drakir:BAAALgAECgkJAQAAAA==.Dreadgnar:BAAALgAECgEJAgAAAA==.Drewnei:BAAALgADCgkJCQAAAA==.Drewserk:BAABLgAECn8pAAIeAAkJKxxxFQBEAgAeAAkJKxxxFQBEAgAAAA==.Drkxmaniac:BAAALgAECgcJEAABLgAECggJFAABAPQVAA==.Drminnowphd:BAAALgAFFAEJAgAAAA==.Drpiscisphd:BAACLgAFFH8cAAMWAAYJRR4hFgC4AQAWAAYJRR4hFgC4AQAZAAEJdAUSRQAjAAAuAAQKfzEAAxYACQk1Ie4OACQDABYACQk1Ie4OACQDABkABwnDBYIpAPMAAAAA.Drsaltyballz:BAABLgAECn8uAAIOAAkJyiKRAQDwAgAOAAkJyiKRAQDwAgAAAA==.Drugpala:BAAALgAECgIJAgAAAA==.Druji:BAAALgAECggJEwAAAA==.Drumuss:BAAALgADCgEJAQAAAA==.',
Du='Ducat:BAABLgAECn8ZAAIDAAUJRwss7gDGAAADAAUJRwss7gDGAAAAAA==.Dudesk:BAAALgAECgUJBgAAAA==.Duffuna:BAAALgADCgEJAQABLgAFFAMJBQAjADwfAA==.Duffunha:BAACLgAFFH8FAAIjAAMJPB9qCAARAQAjAAMJPB9qCAARAQAuAAQKf0wAAiMACQkIJq4AAHQDACMACQkIJq4AAHQDAAAA.',
Dy='Dye:BAABLgAECn80AAIMAAkJhx6XCAABAwAMAAkJhx6XCAABAwAAAA==.Dyre:BAABLgAECn8nAAIkAAkJXQ9xDQB8AQAkAAkJXQ9xDQB8AQAAAA==.Dyslexic:BAACLgAFFH8GAAIBAAUJnQPeCAALAQABAAUJnQPeCAALAQAuAAQKfyYAAgEACAlzGHsHANwBAAEACAlzGHsHANwBAAEuAAUUBwkUAAoA0w4A.Dyspepsia:BAACLgAFFH8UAAIKAAcJ0w5pFABWAQAKAAcJ0w5pFABWAQAuAAQKfx8AAgoACQmZG08+AAwCAAoACQmZG08+AAwCAAAA.',
['Dô']='Dôngus:BAAALgADCgMJAwABLgAECgQJBQAHAAAAAA==.',
['Dõ']='Dõngus:BAAALgAECgQJBAABLgAECgQJBQAHAAAAAA==.',
['Dö']='Döngus:BAAALgAECgEJAgABLgAECgQJBQAHAAAAAA==.',
Ed='Edie:BAAALgAECgEJBgAAAA==.',
Ei='Eirenn:BAABLgAECn8WAAIQAAkJ9gR0DwCUAAAQAAkJ9gR0DwCUAAAAAA==.',
El='Elayna:BAAALgAECgkJBwAAAA==.Elchulo:BAAALgAECgMJAwAAAA==.Elenaura:BAAALgAECgMJAwAAAA==.Eleren:BAABLgAECn8bAAIcAAgJiBLzWwB0AQAcAAgJiBLzWwB0AQAAAA==.Elimee:BAACLgAFFH8FAAIDAAIJnRAmqACDAAADAAIJnRAmqACDAAAuAAQKfzAAAgMACQmgIUkOAFQDAAMACQmgIUkOAFQDAAAA.Elisestraza:BAABLgAFFH8JAAITAAMJohd5GgDUAAATAAMJohd5GgDUAAABLgAFFAIJBQADAJ0QAA==.Ellasia:BAABLgAECn8WAAIOAAgJJAU3GACyAAAOAAgJJAU3GACyAAAAAA==.Elric:BAACLgAFFH8GAAIKAAIJtAcKnACDAAAKAAIJtAcKnACDAAAuAAQKfzUAAgoACQlMGcY2ACYCAAoACQlMGcY2ACYCAAAA.Elsie:BAAALgAECgcJDgABLgAECgkJKAAMAGwfAA==.Elton:BAAALgAECgYJBgAAAA==.Elunea:BAAALgADCgcJDQAAAA==.Elunemittens:BAAALgADCgYJBgAAAA==.',
Em='Emart:BAABLgAECn8lAAIjAAkJaw69GQDRAQAjAAkJaw69GQDRAQAAAA==.Emozella:BAAALgAECgEJAQAAAA==.',
En='Enatresh:BAABLgAECn8ZAAIDAAgJ5QTKLACiAAADAAgJ5QTKLACiAAAAAA==.',
Ep='Epsilon:BAAALgAECgkJCQAAAA==.',
Er='Erayna:BAABLgAECn87AAIFAAkJsRaMHABiAgAFAAkJsRaMHABiAgAAAA==.Ereillea:BAAALgAECgYJDQAAAA==.',
Es='Essence:BAABLgAECn8WAAMDAAgJmxTpagAAAgADAAgJDBHpagAAAgAlAAQJ1xocDAARAQAAAA==.',
Et='Etherious:BAAALgAECgcJCQABLgAECgkJKAAMAGwfAA==.',
Eu='Euko:BAACLgAFFH8GAAMGAAIJqRSFPACCAAAGAAIJqRSFPACCAAAFAAIJwA5vWABpAAAuAAQKfzUAAwYACQkvIfkIAMMCAAYACQkvIfkIAMMCAAUACAl1FZlmAAABAAAA.',
Ev='Evedk:BAAALgAECgkJBQAAAA==.Evepriest:BAAALgAECgEJAQAAAA==.',
Ex='Exterminatra:BAAALgAECgEJAQAAAA==.',
Fa='Failrogue:BAAALgADCgUJCwAAAA==.Falconclaw:BAAALgAECggJDQAAAA==.Falconplume:BAAALgAECgUJBQAAAA==.Falcontail:BAAALgAECgUJBgAAAA==.Falconwing:BAAALgAECggJCAAAAA==.Falkensnoman:BAABLgAECn8oAAIZAAkJvBWMEwDZAQAZAAkJvBWMEwDZAQAAAA==.Fayedra:BAABLgAECn8eAAIEAAkJbxR+EADhAQAEAAkJbxR+EADhAQAAAA==.Faytaleti:BAAALgAECgUJCQAAAA==.',
Fc='Fcawfe:BAAALgAECgQJBAABLgAECgkJIQAMAEgdAA==.',
Fe='Febee:BAAALgADCgcJAQAAAA==.Feenii:BAACLgAFFH8FAAIVAAMJOQdpCwCnAAAVAAMJOQdpCwCnAAAuAAQKf0MAAhUACQlgHj8BAEYCABUACQlgHj8BAEYCAAAA.Felburst:BAAALgAECgMJAwAAAA==.Feldog:BAAALgADCgkJCQAAAA==.Felfireqt:BAAALgAECgEJAgAAAA==.Fersiam:BAAALgAECgcJAQABLgAECgkJKAAMAGwfAA==.Feydros:BAAALgAECgkJBQAAAA==.',
Fh='Fhaani:BAAALgADCgMJBQAAAA==.',
Fi='Figgyandrii:BAAALgAECgUJBQAAAA==.Fionar:BAAALgADCgIJAgAAAA==.Fizzlelich:BAAALgAECgYJBgAAAA==.',
Fl='Flamesters:BAABLgAFFH8IAAIDAAYJpwgTTABIAQADAAYJpwgTTABIAQAAAA==.Fluffpuff:BAAALgADCgMJAwAAAA==.Fluffyfury:BAAALgADCgEJAQAAAA==.',
Fm='Fmpumps:BAAALgAECgEJAQAAAA==.',
Fo='Forreal:BAAALgADCgYJBgABLgADCgYJEAAHAAAAAA==.Foxdeer:BAABLgAECn8fAAMLAAkJmQjagwAxAQALAAkJmQjagwAxAQARAAMJ4wKhHwB0AAAAAA==.Foxxmccloud:BAAALgAFFAEJAQABLgAFFAMJCwAGAIsdAA==.',
Fr='Frenchtoast:BAAALgAECgUJBwAAAA==.',
Fu='Fufighter:BAAALgADCgQJBAAAAA==.Furyrage:BAAALgAECgEJAgAAAA==.Fuzzyclawz:BAAALgADCgYJBgABLgAECgkJLAAQADMQAA==.',
Ga='Gambachii:BAAALgAECgcJDQAAAA==.Gankss:BAABLgAECn8pAAMMAAkJqiPdAQCYAwAMAAkJqiPdAQCYAwAKAAEJNAHU1QEMAAAAAA==.Gannir:BAAALgAECgIJAgABLgAECgcJEAAHAAAAAA==.Garakddon:BAAALgAECgYJBgABLgAECggJJQAoAP8YAA==.Garryy:BAAALgAECgMJBwAAAA==.',
Ge='Geegandolm:BAAALgADCgkJEwAAAA==.Gemìnì:BAAALgAECgEJAgABLgAECgkJFQAPACoRAA==.Genjaru:BAABLgAECn8mAAMGAAYJRBx2CAA/AQAGAAYJRBx2CAA/AQAFAAMJ2QJ0wABFAAAAAA==.Genndalf:BAAALgADCgcJBwAAAA==.Geostorm:BAAALgAECgEJAQAAAA==.',
Gh='Gharmag:BAAALgAECgEJAQAAAA==.',
Gi='Giramar:BAABLgAECn84AAMfAAgJ5BzoEgA7AgAfAAgJ5BzoEgA7AgAgAAcJhg5JNAA0AQAAAA==.',
Gl='Glagkara:BAAALgAECgMJBwAAAA==.',
Go='Gobbyshamm:BAAALgAECgEJAQAAAA==.Gobsmackers:BAAALgAECgYJBwAAAA==.Goldengooner:BAAALgAFFAMJAwAAAA==.Gomklin:BAAALgADCgcJCAABLgAFFAIJBwAKAMUdAA==.Goobtastic:BAAALgADCgQJBAAAAA==.Goteem:BAAALgAECggJEwAAAA==.Gothitelle:BAAALgAECgIJAwAAAA==.',
Gr='Griffhud:BAABLgAECn8YAAIEAAcJDiEHEQDaAQAEAAcJDiEHEQDaAQAAAA==.Grimrox:BAABLgAECn8lAAICAAkJYxLFJADCAQACAAkJYxLFJADCAQAAAA==.Gripinstine:BAAALgADCgEJAQAAAA==.Grixx:BAAALgADCgUJBQAAAA==.Groupie:BAAALgADCgUJCgABLgAECgcJGAAaANUPAA==.',
Gt='Gtatedk:BAAALgAECgEJAQAAAA==.',
Gu='Guccimain:BAAALgAECgEJAQAAAA==.Guno:BAAALgAECgEJAQAAAA==.Guntera:BAAALgAECgYJDgAAAA==.Guts:BAAALgADCgMJAwAAAA==.',
Gw='Gwendalyn:BAAALgAECgQJBQAAAA==.',
['Gä']='Gäz:BAAALgADCgEJAQAAAA==.',
Ha='Haanit:BAAALgAECgYJBgAAAA==.Halexion:BAAALgADCgIJAgAAAA==.Haomaru:BAABLgAECn8XAAQFAAUJLBliSgBlAQAFAAUJLBliSgBlAQAhAAEJiBBnVAAwAAAGAAEJSAv1lwAoAAAAAA==.Hardcandy:BAABLgAECn8YAAIaAAcJ1Q8zGQDmAAAaAAcJ1Q8zGQDmAAAAAA==.Hardlyevoker:BAAALgADCgEJAQABLgAFFAIJBgAMAOYQAA==.',
He='Hearnê:BAAALgAECgQJBQAAAA==.Heartsoul:BAAALgAECgYJCQAAAA==.Heavyarm:BAAALgADCgcJDwAAAA==.Hellork:BAAALgADCgQJBAAAAA==.Hermosura:BAAALgADCgUJCgAAAA==.Hex:BAAALgAFFAEJAQABLgAFFAEJAwAHAAAAAA==.',
Hi='Hiccups:BAAALgAECgMJBAABLgAFFAUJBQAIAH4LAA==.Himawarí:BAABLgAECn8yAAMbAAkJUBXvDgD7AQAbAAkJgxPvDgD7AQAeAAUJwhoUQQBAAQAAAA==.Hiyank:BAABLgAECn8qAAIYAAkJrCKKBgDRAgAYAAkJrCKKBgDRAgABLgAFFAEJAQAHAAAAAA==.',
Ho='Hoffmin:BAABLgAECn8ZAAMcAAkJxRvAEgDyAAAcAAgJxRvAEgDyAAAPAAIJphK0VgCMAAAAAA==.Holemeister:BAACLgAFFH8TAAIKAAMJpiUKHgAVAQAKAAMJpiUKHgAVAQAuAAQKfzAAAgoACAmhJOINAB8DAAoACAmhJOINAB8DAAAA.Holyamin:BAAALgADCgEJAQAAAA==.Holyfresh:BAAALgADCgEJAQAAAA==.Holymann:BAABLgAECn8mAAIfAAgJ3A2KFgCEAAAfAAgJ3A2KFgCEAAAAAA==.Holyschnikey:BAABLgAECn8xAAIMAAcJnxZTBQCvAQAMAAcJnxZTBQCvAQAAAA==.Holyz:BAABLgAECn85AAMMAAkJpCMeAgCPAwAMAAkJpCMeAgCPAwAKAAEJBhk/bQFKAAAAAA==.Horgable:BAAALgADCgIJAgAAAA==.Horrorpops:BAAALgAECgMJAwABLgAFFAIJBgASAGsbAA==.Hozaki:BAAALgAECgQJBAABLgAECggJFAABAPQVAA==.',
Hu='Hudfin:BAAALgAECgYJCQAAAA==.Hundred:BAAALgAECgIJAgABLgAFFAMJBQACAMMOAA==.Huntinwoogie:BAAALgAECgIJAwABLgAECgQJCwAHAAAAAA==.Hunzul:BAAALgADCgcJCQAAAA==.',
Hy='Hyrule:BAAALgAECgYJBgABLgAFFAMJBQAnAF4aAA==.',
['Hí']='Hílthaen:BAABLgAECn84AAMgAAkJmRbqEwA4AgAgAAkJmRbqEwA4AgAnAAEJMQl5KQAnAAAAAA==.',
Ic='Icebones:BAAALgADCgcJDAABLgAECgQJCQAHAAAAAA==.Icelight:BAAALgAECgQJCQAAAA==.Ichigokisu:BAABLgAECn8WAAIKAAgJaRG0dQCCAQAKAAgJaRG0dQCCAQAAAA==.',
Ih='Ihavenobrain:BAAALgAECgEJAQAAAA==.',
Il='Illiduji:BAAALgADCgMJAwAAAA==.Illy:BAABLgAECn8jAAIcAAkJ+hYELgAPAgAcAAkJ+hYELgAPAgAAAA==.',
Im='Imply:BAAALgAECgMJAwAAAA==.Imposed:BAAALgAECgcJEAAAAA==.',
In='Instantdeath:BAABLgAECn8UAAQBAAgJ9BUnBQATAQABAAUJ7RYnBQATAQALAAUJHgpszwC0AAARAAUJKhOaCQCVAAAAAA==.Invali:BAAALgAECgYJCQAAAA==.',
Io='Iorla:BAAALgADCgcJBwAAAA==.',
Ir='Irônhide:BAAALgAECgEJAQAAAA==.',
Iv='Ivranda:BAAALgADCgkJEgABLgAECgkJHQATAG8NAA==.',
Iz='Iz:BAAALgAFFAEJAQAAAA==.',
Ja='Jaapp:BAAALgAECgMJBgAAAA==.Jahan:BAACLgAFFH8XAAInAAQJuxnGEQAgAQAnAAQJuxnGEQAgAQAuAAQKfy8AAycACQlZIQYGACMDACcACAkiJAYGACMDAB8ABAmAEdBHAPAAAAEuAAUUAQkBAAcAAAAA.Jalisha:BAAALgAECgUJCAAAAA==.Jamie:BAABLgAFFH8IAAIWAAMJhCMDcAAeAQAWAAMJhCMDcAAeAQABLgAFFAkJHgALAD0gAA==.Jaydine:BAAALgADCgYJBgABLgAFFAIJBQADAJ0QAA==.',
Je='Jeder:BAAALgADCgYJCQAAAA==.Jeri:BAAALgAECgYJCAAAAA==.Jerithal:BAAALgAECgMJAwAAAA==.',
Jh='Jhie:BAABLgAECn8pAAIQAAkJYhaqHADJAQAQAAkJYhaqHADJAQAAAA==.',
Ji='Jinro:BAAALgAECgEJAgABLgAECgEJAwAHAAAAAA==.',
Jo='Jodi:BAAALgAECgEJAQAAAA==.',
Ju='Jud:BAAALgAECggJEAAAAA==.Juviâ:BAAALgAECggJCgABLgAECgkJKAAMAGwfAA==.Juxtaposed:BAAALgADCgUJBQAAAA==.',
['Jà']='Jàzz:BAAALgADCgUJCQAAAA==.',
Ka='Kaelora:BAAALgAECggJEgAAAA==.Kaerei:BAABLgAECn8sAAIKAAkJnh75IQB+AgAKAAkJnh75IQB+AgAAAA==.Kaleb:BAACLgAFFH8KAAIPAAQJ+R6aCQBuAQAPAAQJ+R6aCQBuAQAuAAQKfyEAAg8ACAm2IVkLAHECAA8ACAm2IVkLAHECAAAA.Kalferno:BAABLgAECn8aAAIDAAkJiRb3CADjAQADAAkJiRb3CADjAQAAAA==.Kalirkaz:BAACLgAFFH8QAAIFAAUJvgw1EgD7AAAFAAUJvgw1EgD7AAAuAAQKf0QAAwUACQlOHhYCAJgCAAUACQlOHhYCAJgCAAYABQk5BspkAIkAAAAA.Kallipsa:BAAALgAECgMJAwAAAA==.Karasu:BAAALgAECggJCgABLgAECgkJLAAQADMQAA==.Kariel:BAAALgADCgQJBAAAAA==.Karst:BAAALgAECgQJBQABLgAFFAEJAQAHAAAAAA==.Kathria:BAAALgAECgcJEAAAAA==.Kayotica:BAAALgAECgkJEAAAAA==.',
Ke='Keepcrying:BAAALgAECgEJAQAAAA==.Kegendary:BAAALgAECgQJCAAAAA==.Keler:BAAALgAECgEJAQABLgAECgMJBwAHAAAAAA==.Kelideyn:BAAALgAECgYJBgAAAA==.Keládry:BAABLgAECn8XAAIMAAcJHhd8MgCMAQAMAAcJHhd8MgCMAQAAAA==.Keskiyö:BAAALgADCgkJFQABLgAECgkJLAAQADMQAA==.',
Kh='Khaalid:BAAALgAECgEJAwABLgAECgEJAwAHAAAAAA==.Khallock:BAABLgAECn8lAAIRAAgJCRmaDgByAQARAAgJCRmaDgByAQAAAA==.Khamael:BAAALgAECgEJAQAAAA==.',
Ki='Kiemen:BAABLgAECn8oAAMWAAkJHRoONwAjAgAWAAkJHRoONwAjAgAiAAEJbQ4kOwAxAAAAAA==.Kierya:BAAALgAECgEJAgAAAA==.Killerpoison:BAAALgAECgkJBQAAAA==.Killko:BAACLgAFFH8GAAIWAAIJbg+B0QCPAAAWAAIJbg+B0QCPAAAuAAQKfxsAAhYACQn+G/YrAFACABYACQn+G/YrAFACAAAA.Kinki:BAAALgAECgMJAwABLgAECgcJGAAaANUPAA==.Kirisen:BAAALgAECgcJCwAAAA==.Kitan:BAAALgAECgQJBQAAAA==.Kitani:BAAALgADCgkJGAABLgAECgkJeAAnAO0iAA==.',
Ko='Konno:BAAALgAECgQJBAABLgAFFAgJKwAVAFUiAA==.Kooterr:BAAALgADCgUJBQAAAA==.Korbix:BAACLgAFFH8GAAIWAAMJFQz2gABbAAAWAAMJFQz2gABbAAAuAAQKfxcAAhYABglaGxx1AHkBABYABglaGxx1AHkBAAAA.Kotanx:BAAALgAECgEJAQAAAA==.',
Kr='Kragsloor:BAAALgAFFAEJAQAAAA==.Kredorin:BAAALgAECgYJCgAAAA==.Krewella:BAAALgADCgcJBwAAAA==.Krickette:BAAALgAECggJDgABLgAECgkJOwAFALEWAA==.Krihl:BAAALgAECgkJBgAAAA==.Krovmar:BAAALgADCgUJBQAAAA==.Kryoos:BAAALgAECgEJAQAAAA==.',
Ks='Kspanxx:BAAALgAECgMJAwAAAA==.',
Kt='Kthanx:BAAALgAECgQJAgAAAA==.',
Ku='Kungpowgazer:BAABLgAECn8XAAMYAAkJ/R1RCgCOAgAYAAkJ/R1RCgCOAgAQAAEJew8PowAtAAAAAA==.Kunls:BAABLgAECn8eAAIPAAgJrgiELQAWAQAPAAgJrgiELQAWAQAAAA==.Kuraak:BAAALgAECgUJDAAAAA==.Kuraki:BAABLgAECn8eAAIQAAkJbAqSLABcAQAQAAkJbAqSLABcAQAAAA==.Kurasa:BAABLgAECn8sAAMQAAkJMxAeIwCYAQAQAAkJMxAeIwCYAQAJAAQJowH4WgBjAAAAAA==.Kutraz:BAAALgAECgQJBQAAAA==.',
Ky='Kyriea:BAAALgAECgkJCQABLgAFFAMJBQADACoIAA==.',
La='Ladrar:BAABLgAECn8aAAQhAAkJnhZEDAD0AQAhAAgJxhhEDAD0AQAGAAMJQAz1aAB8AAAFAAEJ6ATT7wAgAAAAAA==.Laelina:BAAALgAECgEJAwAAAA==.Laidiemonk:BAAALgADCgYJBgAAAA==.Lanadiel:BAACLgAFFH8GAAIoAAIJyxi6DgCUAAAoAAIJyxi6DgCUAAAuAAQKfzUAAigACQmIIs8CAPoCACgACQmIIs8CAPoCAAAA.Lazz:BAABLgAECn8VAAQjAAgJVyADFQD7AQAjAAgJVyADFQD7AQAaAAQJ5RkJQQBVAQASAAEJAADvVQEAAAABLgAFFAQJDAAJAFgkAA==.',
Le='Legend:BAACLgAFFH8dAAIcAAcJVx5vFgBrAQAcAAcJVx5vFgBrAQAuAAQKfzIAAhwACQm3IDAJAD4DABwACQm3IDAJAD4DAAAA.Lekrotar:BAAALgAECgQJBAAAAA==.Letsyoudie:BAAALgAECgMJAwAAAA==.',
Li='Lian:BAABLgAECn8XAAIJAAYJrgsdagDYAAAJAAYJrgsdagDYAAAAAA==.Lianse:BAAALgAECgEJAQAAAA==.Lichbane:BAABLgAECn81AAIWAAkJmCFEFwC7AgAWAAkJmCFEFwC7AgAAAA==.Licun:BAAALgAECgYJDQAAAA==.Lifexdeath:BAABLgAECn8ZAAMgAAcJ5QbYQgDfAAAgAAcJ5QbYQgDfAAAfAAEJxgM5lwAjAAAAAA==.Lightcell:BAAALgAECgQJBgAAAA==.Liliara:BAABLgAECn80AAISAAkJ3BCPRwDLAQASAAkJ3BCPRwDLAQAAAA==.Lillyfel:BAAALgADCgQJBAAAAA==.Lillyirl:BAAALgAECgUJEQAAAA==.Lillymae:BAAALgAECggJDAAAAA==.Lillyslight:BAAALgADCgYJBgAAAA==.Lillysneak:BAAALgADCgUJCgAAAA==.Lillytae:BAAALgAECgQJBwAAAA==.Lillyzard:BAAALgAECgEJAQAAAA==.Lilmoo:BAAALgAECggJEAAAAA==.Linglang:BAAALgADCgcJBwABLgADCgYJEAAHAAAAAA==.Linkhunter:BAAALgAECgYJBgABLgAFFAMJBQAnAF4aAA==.Linkmônk:BAAALgAECgkJCQABLgAFFAMJBQAnAF4aAA==.Linni:BAABLgAECn8oAAIMAAkJbB+5BQA1AwAMAAkJbB+5BQA1AwAAAA==.Littleava:BAAALgADCgEJAQAAAA==.Lizardwizard:BAAALgAECgQJBAAAAA==.',
Lo='Lockgodtko:BAAALgAECgcJDQAAAA==.Lodise:BAABLgAECn8oAAMRAAkJsw4SCgDAAQARAAkJsw4SCgDAAQALAAEJAAgZHQEyAAAAAA==.Lonful:BAAALgADCgEJAQAAAA==.Lorzz:BAACLgAFFH8bAAIgAAQJUhL9DgC8AAAgAAQJUhL9DgC8AAAuAAQKfzgAAiAACQl0IdkFABoDACAACQl0IdkFABoDAAAA.Lothe:BAABLgAECn8eAAIMAAkJtB43CAAIAwAMAAkJtB43CAAIAwAAAA==.Loveydovey:BAAALgADCgUJBQAAAA==.',
Lu='Lucrio:BAABLgAECn9BAAIWAAkJNhZ1NAAtAgAWAAkJNhZ1NAAtAgAAAA==.Ludlow:BAAALgAECgIJAgABLgAECgkJIQAMAEgdAA==.Ludoe:BAAALgADCgkJMQAAAA==.Luminariah:BAAALgAECgYJEQABLgAECggJEQAHAAAAAA==.Luna:BAAALgAFFAEJAQAAAA==.Lunalai:BAABLgAECn9BAAIEAAkJ3iKBAgAVAwAEAAkJ3iKBAgAVAwAAAA==.Lurim:BAAALgAECgEJBAABLgAECggJIwAoAI8eAA==.Lushy:BAABLgAECn8aAAINAAkJgRgEDgBIAgANAAkJgRgEDgBIAgAAAA==.',
Ly='Lylineth:BAAALgADCgYJBgAAAA==.Lylinette:BAAALgAECgcJEgAAAA==.Lyssandra:BAAALgADCgUJBQAAAA==.',
['Lè']='Lèah:BAAALgAECgQJCAAAAA==.',
['Lí']='Lízandor:BAACLgAFFH8YAAIKAAUJEhDiTgARAQAKAAUJEhDiTgARAQAuAAQKfykAAgoACQmYHF4sAFACAAoACQmYHF4sAFACAAAA.',
['Lû']='Lûsøn:BAAALgAECgEJAQAAAA==.',
Ma='Machotee:BAAALgAECgEJAQAAAA==.Madruskee:BAABLgAECn8sAAIiAAYJQBpxBABCAQAiAAYJQBpxBABCAQAAAA==.Magahpt:BAAALgAECgMJBAAAAA==.Magdea:BAAALgADCgYJBgAAAA==.Mageofdeath:BAAALgAECgYJCAABLgAECggJFAABAPQVAA==.Mageofhonor:BAAALgAECgEJAgAAAA==.Magistroll:BAABLgAECn8cAAIDAAcJXgXt1wDmAAADAAcJXgXt1wDmAAAAAA==.Mairisella:BAAALgAECgIJAgAAAA==.Malabathrum:BAAALgAECgEJAgAAAA==.Maladaptive:BAAALgAECgEJAgAAAA==.Malevohaynk:BAAALgAECgQJBQABLgAFFAEJAQAHAAAAAA==.Mandrallea:BAAALgAECgYJBwAAAA==.Manerva:BAAALgAECgUJCAAAAA==.Maryshelley:BAAALgADCgMJAwAAAA==.Matoo:BAAALgADCgEJAQAAAA==.Mattertusk:BAAALgAECgEJAwAAAA==.Mattincis:BAAALgAFFAMJAQAAAA==.Maurin:BAAALgAFFAEJAgAAAA==.Maximumhonk:BAABLgAECn8nAAIIAAcJiRMUVwBaAQAIAAcJiRMUVwBaAQAAAA==.',
Me='Melfys:BAAALgAECgEJAQAAAA==.Melpómene:BAAALgAECgEJAQABLgAECgkJMgALABEWAA==.Mendelia:BAABLgAECn85AAIoAAkJ1hYMAwC9AQAoAAkJ1hYMAwC9AQAAAA==.Mercus:BAABLgAECn8ZAAMXAAkJ9RgiBgBqAQAXAAYJpBQiBgBqAQANAAgJLxrxMQAUAQAAAA==.Merkstrasza:BAAALgAECggJEQAAAA==.Mervenious:BAABLgAECn8fAAQeAAgJzxDpLgCUAQAeAAgJzxDpLgCUAQAmAAQJ7Q7eTACcAAAbAAMJpQhrOQB/AAAAAA==.Meu:BAAALgAECgkJCwAAAA==.',
Mi='Midasdh:BAACLgAFFH8OAAIcAAUJ0wuUVQDuAAAcAAUJ0wuUVQDuAAAuAAQKfxwAAxwACAmAF5Y+APoBABwACAnfFJY+APoBAA8ABgmOFwMwAE8BAAAA.Midasdk:BAACLgAFFH8NAAIWAAUJEhrDYwAvAQAWAAUJEhrDYwAvAQAuAAQKfxwAAxYABwnMHG9PAAQCABYABwm9GW9PAAQCACIAAwkzEkMmAKAAAAEuAAUUBQkOABwA0wsA.Midasmonk:BAAALgAECgEJAQABLgAFFAUJDgAcANMLAA==.Midasshift:BAAALgAECgcJDwAAAA==.Miladepollo:BAAALgADCgMJAwAAAA==.Milkers:BAAALgAECgEJAQAAAA==.Mindblank:BAAALgAECgQJBAAAAA==.Mindplague:BAABLgAECn9BAAIfAAkJKh/cAQB8AgAfAAkJKh/cAQB8AgAAAA==.Minipincin:BAAALgAECgYJCAAAAA==.Minisicwidit:BAAALgADCgMJAwAAAA==.Miroslava:BAAALgAECgYJBwAAAA==.Mirrorforce:BAABLgAFFH8HAAMnAAMJQg7FHACkAAAnAAMJQg7FHACkAAAfAAEJfgWTKgA0AAAAAA==.Missfire:BAAALgAECgIJAgABLgAECgkJDAAHAAAAAA==.Mistdeeznuts:BAACLgAFFH8OAAIJAAQJpwjkPACyAAAJAAQJpwjkPACyAAAuAAQKfx8AAwkACQmWDOo5AIoBAAkACQmWDOo5AIoBABAAAQmSA/a7AB0AAAAA.',
Mo='Mogwaï:BAAALgAECgcJCwAAAA==.Mokokoma:BAAALgAECgMJBAAAAA==.Moonde:BAAALgAECgkJDwAAAA==.Moonscale:BAABLgAECn80AAIUAAkJHR/2AQC9AgAUAAkJHR/2AQC9AgAAAA==.Moosayer:BAAALgAECgcJDAAAAA==.Moovement:BAAALgAECgMJAwABLgAFFAQJBwAEALYIAA==.Mossed:BAAALgADCgMJAwAAAA==.Moustaccio:BAAALgAECgIJAgAAAA==.',
Ms='Mskelsier:BAAALgAECgUJBQAAAA==.',
Mt='Mtaur:BAAALgADCggJDwAAAA==.',
Mu='Muclor:BAAALgADCgcJBwABLgAFFAMJAwAHAAAAAA==.Muffintop:BAAALgAECgEJAQABLgAECgkJLwAFANkhAA==.Murkyn:BAAALgAECgEJAQAAAA==.Mustang:BAAALgAECgUJBQAAAA==.',
My='Mydadstayed:BAAALgAECgYJCwABLgAECgcJJwAIAIkTAA==.Mythalis:BAAALgAECgQJBQAAAA==.Mythar:BAAALgAECgEJAQAAAA==.Mythsarrond:BAAALgADCgUJBwAAAA==.',
['Mä']='Märändus:BAAALgADCgEJAQAAAA==.',
['Må']='Måzikeen:BAAALgADCgMJAwAAAA==.',
Na='Nardena:BAAALgAECgYJCwAAAA==.Narse:BAABLgAFFH8GAAIgAAIJvwhSLgBeAAAgAAIJvwhSLgBeAAAAAA==.Narz:BAACLgAFFH8VAAISAAMJvQw1NgDQAAASAAMJvQw1NgDQAAAuAAQKfz8AAhIACQk4GWEKANIBABIACQk4GWEKANIBAAAA.Nastianna:BAAALgAECgQJCgAAAA==.Natgeo:BAAALgAECgkJEAABLgAFFAMJBQAnAF4aAA==.Nazumi:BAABLgAECn8oAAIQAAkJ/R5vCADAAgAQAAkJ/R5vCADAAgAAAA==.',
Nd='Ndiz:BAABLgAECn8VAAISAAcJIhwCJwAdAgASAAcJIhwCJwAdAgAAAA==.',
Ne='Necronomikon:BAAALgAECgEJAgAAAA==.Neeva:BAAALgADCgYJEAAAAA==.Nelrya:BAEALgADCgcJDQABLgAFFAUJDQAKALAPAA==.Nephilym:BAAALgAECgEJAQAAAA==.Nerhzul:BAAALgAECgcJDgAAAA==.Nerial:BAAALgAECgEJAQABLgAECgEJAwAHAAAAAA==.Neromoo:BAAALgAECgMJAwABLgAECgkJIQADAEEXAA==.Neruphuyt:BAABLgAECn86AAIGAAgJExRfJwCUAQAGAAgJExRfJwCUAQAAAA==.',
Ni='Niath:BAAALgAECgYJCAAAAA==.Nightbreeze:BAAALgAECgkJCQAAAA==.Nightsniper:BAABLgAECn8VAAISAAkJyBkbRwDMAQASAAkJyBkbRwDMAQAAAA==.Ninfassins:BAAALgADCgIJAgAAAA==.',
No='Norintha:BAAALgADCgEJAQAAAA==.Norolen:BAAALgADCgIJAgAAAA==.Notpillows:BAAALgADCggJCAAAAA==.',
Nu='Nuzzle:BAAALgAECgEJAQABLgAECgkJPQAEACMbAA==.',
Ny='Nyxelle:BAAALgAECgQJBAAAAA==.Nyxiel:BAAALgAECgQJBQABLgAECggJEQAHAAAAAA==.',
['Nä']='Närz:BAAALgAECgQJBAAAAA==.',
['Nò']='Nòvà:BAAALgAECgEJAQABLgAECgkJFQAPACoRAA==.',
Oa='Oak:BAAALgAECgkJEgAAAA==.',
Oc='Occo:BAAALgADCgEJAQAAAA==.',
Og='Ogroc:BAAALgAECgQJBAAAAA==.',
Ok='Okioak:BAABLgAECn8UAAQmAAkJcxKZLQATAQAmAAgJFRKZLQATAQAeAAMJ5BFjgAC8AAAbAAIJpwatQABOAAAAAA==.',
Ol='Olgon:BAACLgAFFH8XAAISAAQJMRDiJwAGAQASAAQJMRDiJwAGAQAuAAQKfzoAAhIACQmvGhkeAHECABIACQmvGhkeAHECAAAA.Olstinkyboot:BAAALgAECgEJAQAAAA==.',
Op='Oprhawinfury:BAABLgAECn8iAAIWAAkJRA7jZgCZAQAWAAkJRA7jZgCZAQAAAA==.',
Or='Orcchop:BAAALgAECgEJBAAAAA==.Orgodemir:BAAALgADCgkJDwAAAA==.Orhamin:BAAALgAFFAIJAwAAAA==.',
Os='Oshani:BAAALgAFFAEJAwAAAA==.',
Ot='Otemoto:BAAALgAECgEJAQABLgAFFAMJBQACAMMOAA==.',
Ou='Ouin:BAAALgAECgUJBQABLgAECgkJLwACAHITAA==.',
Ox='Oxley:BAAALgAECgEJAgAAAA==.',
Pa='Paigor:BAAALgAECgQJBgAAAA==.Pakswagger:BAABLgAECn8XAAMdAAYJFRfoEwCLAQAdAAYJFRfoEwCLAQATAAMJRQS2ewBqAAAAAA==.Pallyberry:BAABLgAECn8xAAIMAAkJZhsZEACYAgAMAAkJZhsZEACYAgAAAA==.Pancake:BAAALgAECgEJAQAAAA==.Pandemonia:BAABLgAECn8zAAMBAAkJ5Q0rFgCYAQABAAgJHgwrFgCYAQALAAkJJw2ibQBgAQAAAA==.Paprika:BAAALgAECgQJBAAAAA==.Parsie:BAAALgAFFAIJAgAAAA==.Patch:BAAALgADCgYJBgAAAA==.Pathibas:BAAALgADCgEJAQABLgAFFAMJBQAeALgZAA==.Pattycakes:BAABLgAECn8jAAIWAAkJLBZoSgDjAQAWAAkJLBZoSgDjAQAAAA==.',
Pe='Pencil:BAACLgAFFH8gAAILAAYJoRu5PABaAQALAAYJoRu5PABaAQAuAAQKfxsABAsACAkwHSM6APIBAAsACAkwHSM6APIBAAEAAwniBj1dAFcAABEAAQkAANAsAEUAAAAA.Pewpewlvltwo:BAACLgAFFH8UAAIVAAQJFgyzBwDoAAAVAAQJFgyzBwDoAAAuAAQKfygAAhUACAnQHmMJACYCABUACAnQHmMJACYCAAAA.Pewthree:BAAALgAECgYJCAABLgAFFAQJFAAVABYMAA==.',
Ph='Pherocious:BAABLgAECn8VAAIaAAUJ6xP/GQDfAAAaAAUJ6xP/GQDfAAAAAA==.',
Pi='Pintsize:BAAALgADCgIJAgAAAA==.Pixeleen:BAAALgAFFAEJAQABLgAFFAUJCgADAKoDAA==.',
Pl='Plaguelis:BAAALgADCgEJAQABLgAFFAMJBQAVADkHAA==.Plexy:BAABLgAFFH8FAAInAAQJQwuEGADDAAAnAAQJQwuEGADDAAABLgAFFAYJDgACAMURAA==.',
Po='Pobble:BAAALgADCgcJBwAAAA==.Pokitz:BAACLgAFFH8LAAIKAAMJyAMrRwCKAAAKAAMJyAMrRwCKAAAuAAQKf1gAAgoACQkGFR4NAJUBAAoACQkGFR4NAJUBAAAA.Poprock:BAAALgAECgEJAQAAAA==.Potus:BAAALgADCgQJBAAAAA==.',
Pr='Primordinor:BAACLgAFFH8HAAICAAMJChNYNgC0AAACAAMJChNYNgC0AAAuAAQKfyoAAwIACQkCHsUOAIICAAIACQkCHsUOAIICAAgABwnTF90yAOcBAAAA.Probnotalive:BAABLgAECn8nAAISAAkJ5RoYHQB2AgASAAkJ5RoYHQB2AgAAAA==.Probnotferal:BAAALgAECgEJAQAAAA==.Probnoturmom:BAABLgAECn8dAAIgAAgJVxt2GAAYAgAgAAgJVxt2GAAYAgAAAA==.',
Qu='Quaektem:BAAALgAECgEJAQAAAA==.Quietus:BAAALgADCgkJFwAAAA==.',
Ra='Raevyn:BAAALgAFFAEJAQAAAA==.Rafaiel:BAAALgAECgQJBAAAAA==.Rakan:BAABLgAECn9BAAImAAkJPh4xBgCdAgAmAAkJPh4xBgCdAgAAAA==.Rakasha:BAAALgADCgkJCQAAAA==.Raktanu:BAAALgADCgkJCQABLgAECgkJcQAmAIEZAA==.Rallick:BAACLgAFFH8fAAIMAAQJAhJ+EwDJAAAMAAQJAhJ+EwDJAAAuAAQKfzEAAgwACQm3GLEQAJECAAwACQm3GLEQAJECAAAA.Ranloth:BAAALgAECgcJBwAAAA==.Ranì:BAACLgAFFH8GAAIbAAIJZwbUJwBcAAAbAAIJZwbUJwBcAAAuAAQKfzUAAhsACQnxFwIRANoBABsACQnxFwIRANoBAAAA.Raptorfarian:BAAALgAECgQJCAABLgAECggJEQAHAAAAAA==.Rathger:BAAALgAECggJEgAAAA==.Ravenscythe:BAAALgADCgEJAQAAAA==.Raydor:BAAALgAECggJDgAAAA==.',
Re='Reb:BAABLgAECn8mAAIfAAkJ6gSiOwAjAQAfAAkJ6gSiOwAjAQAAAA==.Redic:BAAALgAECgMJAwAAAA==.Regis:BAAALgAECgYJBgABLgAFFAMJBwAVAF8KAA==.Rellix:BAAALgADCgUJBQAAAA==.Rendkick:BAAALgADCgcJBwAAAA==.Rendwee:BAABLgAECn88AAIhAAkJuiN5AQAyAwAhAAkJuiN5AQAyAwAAAA==.Reuel:BAAALgAECgYJCgAAAA==.Revlon:BAABLgAECn8ZAAINAAYJeA5pCADzAAANAAYJeA5pCADzAAAAAA==.Rewolf:BAABLgAECn8UAAIIAAkJuhICKQAaAgAIAAkJuhICKQAaAgAAAA==.',
Rh='Rheemus:BAAALgAECgEJAwABLgAFFAIJBgASAGsbAA==.Rhul:BAAALgAECgkJEwAAAA==.',
Ri='Ricflairion:BAABLgAECn8bAAITAAgJTQmVQwAbAQATAAgJTQmVQwAbAQAAAA==.Rimuru:BAAALgAECgMJBgABLgAECgMJBwAHAAAAAA==.Ritko:BAAALgADCgMJAwAAAA==.',
Ro='Robkin:BAAALgAECgIJAQAAAA==.Rodcet:BAACLgAFFH8HAAIKAAIJxR0phwClAAAKAAIJxR0phwClAAAuAAQKfzwAAgoACQnBJXUFAEkDAAoACQnBJXUFAEkDAAAA.Roflcopterr:BAABLgAECn85AAQMAAkJTxyHDQC6AgAMAAkJTxyHDQC6AgAKAAYJ9QcB6QDTAAAoAAEJSAXuWgAZAAAAAA==.Rognan:BAAALgAECgMJAwAAAA==.Roku:BAAALgAECgEJAQAAAA==.Romina:BAAALgADCgEJBAAAAA==.Ronkin:BAAALgAECgUJBwAAAA==.Rookgue:BAACLgAFFH8ZAAIOAAcJYBDkAADIAQAOAAcJYBDkAADIAQAuAAQKf10AAg4ACQnIH3QAAJ8CAA4ACQnIH3QAAJ8CAAAA.Rookoker:BAACLgAFFH8FAAIUAAIJLAUJBgBlAAAUAAIJLAUJBgBlAAAuAAQKfykAAhQACAkiDTADAOcAABQACAkiDTADAOcAAAAA.Rootsafarian:BAAALgADCgcJBwAAAA==.Rossa:BAAALgAECgEJAgAAAA==.Rossdair:BAABLgAECn8UAAMWAAgJDBEEhwBWAQAWAAYJxBYEhwBWAQAZAAIJwALnVABHAAABLgADCgUJCQAHAAAAAA==.Rossperot:BAACLgAFFH8VAAIWAAMJDyQCKwAnAQAWAAMJDyQCKwAnAQAuAAQKfzUAAhYACQmiJP4BABsDABYACQmiJP4BABsDAAAA.Rothschild:BAAALgADCgEJAQAAAA==.Rottenfist:BAAALgAECgEJAQAAAA==.',
Sa='Sabako:BAAALgADCgcJCAAAAA==.Sacra:BAAALgADCgUJBQABLgAFFAEJAQAHAAAAAA==.Saelara:BAAALgADCgcJCgAAAA==.Saelis:BAAALgADCgQJBAAAAA==.Sakaru:BAABLgAECn8bAAIDAAgJTw7ViABlAQADAAgJTw7ViABlAQABLgAECgkJLAAQADMQAA==.Salmoney:BAAALgAECgQJBAAAAA==.Salorin:BAAALgADCgYJCQAAAA==.Samgee:BAACLgAFFH8hAAIKAAQJGhwQMABSAQAKAAQJGhwQMABSAQAuAAQKf0YAAgoACQlgIWwRAAUDAAoACQlgIWwRAAUDAAAA.Sandormu:BAAALgADCgkJCQAAAA==.Sanskara:BAAALgADCgQJBAABLgAFFAEJAQAHAAAAAA==.Saphas:BAAALgAECgMJAwAAAA==.Saynar:BAABLgAECn9GAAIcAAkJHiTNBQAtAwAcAAkJHiTNBQAtAwAAAA==.',
Sc='Scattered:BAABLgAECn8fAAQLAAkJohMidABSAQALAAcJsBIidABSAQABAAMJJBRLQACzAAARAAEJggs9QgAtAAAAAA==.Scooter:BAAALgAECgUJCgAAAA==.Scyx:BAAALgADCgEJAQAAAA==.',
Se='Seba:BAACLgAFFH8fAAIDAAQJQhT6MQACAQADAAQJQhT6MQACAQAuAAQKf0IAAgMACQn8IKEWANECAAMACQn8IKEWANECAAAA.Sebushko:BAAALgADCgMJAQABLgAFFAQJHwADAEIUAA==.Selesne:BAABLgAECn8eAAIXAAkJ+QmPCwBfAQAXAAkJ+QmPCwBfAQAAAA==.Seraphicktwo:BAABLgAECn8zAAMgAAkJdhk5IADBAQAgAAcJnhg5IADBAQAfAAgJXxiPCQAuAQAAAA==.Seriana:BAABLgAECn8WAAIgAAgJfwvfNwAeAQAgAAgJfwvfNwAeAQAAAA==.Sermidas:BAACLgAFFH8KAAMmAAMJqRvJJgDSAAAmAAMJqRvJJgDSAAAeAAIJ3AevGwCYAAAuAAQKfyIAAyYACQk6H7gCAPACACYACQk6H7gCAPACAB4ABwnOFFw0ANgBAAEuAAUUBQkOABwA0wsA.',
Sh='Shadowcutter:BAAALgAECgEJAwABLgAECggJFAABAPQVAA==.Shaggmz:BAABLgAECn9JAAIeAAkJ9RmdAgBMAgAeAAkJ9RmdAgBMAgAAAA==.Shawnkin:BAAALgADCgQJAgAAAA==.Shigglez:BAAALgAECgkJCgAAAA==.Shinakuma:BAAALgAECgUJDgAAAA==.Shinma:BAABLgAECn9EAAIoAAkJiwzZBABVAQAoAAkJiwzZBABVAQAAAA==.Shrubbery:BAABLgAECn8VAAILAAcJ+wM5wQDKAAALAAcJ+wM5wQDKAAAAAA==.Shymary:BAABLgAECn9FAAInAAkJnQx+BgCgAQAnAAkJnQx+BgCgAQAAAA==.',
Si='Siete:BAAALgAECgEJAQABLgAECgQJCQAHAAAAAA==.Silvertip:BAAALgADCggJFQAAAA==.Silëx:BAABLgAECn8wAAIDAAkJMhwCBgBFAgADAAkJMhwCBgBFAgAAAA==.Silëxa:BAAALgAECgYJEQAAAA==.Sindiz:BAAALgAFFAEJAQAAAA==.Sinsanityz:BAAALgAFFAkJAQAAAA==.Sioc:BAAALgAECgEJAQAAAA==.Siouxiesioux:BAAALgADCgYJCgAAAA==.Siyona:BAAALgADCgkJDAAAAA==.',
Sk='Skeith:BAAALgAECgkJCQAAAA==.Skits:BAAALgAECgIJAgAAAA==.Skyrah:BAAALgAECgYJBgAAAA==.Skyrie:BAAALgADCgQJBQAAAA==.',
Sl='Slagbröder:BAAALgADCgcJBwAAAA==.Slimjimz:BAAALgAECgQJBAAAAA==.Slohine:BAAALgAECgUJBQAAAA==.Sludgecrush:BAAALgAECgYJCwAAAA==.Slugondeez:BAACLgAFFH8GAAIMAAIJ5hC1PwBkAAAMAAIJ5hC1PwBkAAAuAAQKfxYAAgwABQkWI38iAPEBAAwABQkWI38iAPEBAAAA.',
Sm='Smacker:BAAALgAFFAMJAwAAAA==.Smallmike:BAAALgAECgIJAgAAAA==.Smitefist:BAAALgAECgIJAgABLgAECgQJBQAHAAAAAA==.Smokiee:BAABLgAECn8ZAAIFAAkJvxBmNADKAQAFAAkJvxBmNADKAQAAAA==.',
Sn='Snacker:BAAALgAECgEJAQABLgAFFAMJAwAHAAAAAA==.Snailtrail:BAABLgAECn8gAAIkAAkJ8wTOFAAIAQAkAAkJ8wTOFAAIAQAAAA==.Snark:BAABLgAECn8dAAIWAAYJrAi2IAC9AAAWAAYJrAi2IAC9AAAAAA==.Snarkkin:BAAALgAECgQJDAABLgAECgYJHQAWAKwIAA==.Snkyturtle:BAACLgAFFH8YAAISAAQJYBMaQAAtAQASAAQJYBMaQAAtAQAuAAQKfzUAAhIACQllFH0/AOQBABIACQllFH0/AOQBAAAA.Snowkim:BAEBLgAECn8bAAIoAAgJmh3yDAD2AQAoAAgJmh3yDAD2AQAAAA==.Snuzzle:BAABLgAECn89AAIEAAkJIxveCQBLAgAEAAkJIxveCQBLAgAAAA==.',
So='Soniic:BAAALgAECgIJAgAAAA==.Soullessfros:BAABLgAECn8nAAIWAAkJ7ROkPgAIAgAWAAkJ7ROkPgAIAgAAAA==.Soullessman:BAAALgADCgQJCAAAAA==.Soupshammich:BAAALgAECgEJAQAAAA==.Sourmash:BAAALgADCgkJCgAAAA==.',
Sp='Spaghet:BAABLgAECn8fAAICAAkJNRkqHgDwAQACAAkJNRkqHgDwAQAAAA==.Sparkleponi:BAAALgAECgQJBQABLgAECgcJMgADALIkAA==.Spillthetea:BAABLgAECn8UAAMJAAkJmQipWwAGAQAJAAkJmQipWwAGAQAQAAEJzgm8lwA4AAAAAA==.Sploot:BAAALgAECggJEgAAAA==.',
Sq='Squibbles:BAAALgAECgEJAQAAAA==.',
Sr='Srasjet:BAABLgAECn8kAAIIAAkJ9h0FCwAHAwAIAAkJ9h0FCwAHAwAAAA==.',
Ss='Ssimba:BAAALgAECggJDQAAAA==.',
St='Stabytha:BAABLgAECn8rAAMNAAkJwxGrAwCdAQANAAkJnhGrAwCdAQAOAAEJ1RdRJQA/AAAAAA==.Stark:BAAALgADCgYJCgAAAA==.Starlight:BAAALgAECgEJAQAAAA==.Stars:BAAALgAFFAEJAQAAAA==.Stealthed:BAABLgAECn8UAAIEAAgJ8x67DAAWAgAEAAgJ8x67DAAWAgAAAA==.Stender:BAAALgAECgcJDAABLgAFFAcJEAAPAMAdAA==.Steàlthed:BAAALgAECgEJAQABLgAECgkJFAAEAPMeAA==.Stormae:BAAALgADCgMJAgAAAA==.Stormcall:BAABLgAECn8tAAIIAAkJ9h01FACqAgAIAAkJ9h01FACqAgAAAA==.Stratusfied:BAAALgAECgQJCQAAAA==.',
Su='Susbandaid:BAAALgADCgYJBgAAAA==.',
Sw='Sweetiefox:BAACLgAFFH8KAAIDAAUJqgOLeQDlAAADAAUJqgOLeQDlAAAuAAQKfx0AAgMACQnYDv4VACsBAAMACQnYDv4VACsBAAAA.Swiss:BAABLgAECn8eAAICAAkJhxCZKgCdAQACAAkJhxCZKgCdAQAAAA==.',
Sy='Syllai:BAAALgAECgYJBgAAAA==.Symboli:BAAALgADCgQJBAAAAA==.Syphus:BAAALgADCgQJBAAAAA==.',
['Sá']='Sáëgárón:BAABLgAECn8ZAAMeAAgJahbCJwC9AQAeAAgJahbCJwC9AQAmAAEJpwX7hgAiAAAAAA==.',
Ta='Ta:BAAALgADCgMJAwAAAA==.Tacyon:BAAALgADCggJFgAAAA==.Taliden:BAABLgAECn8aAAIeAAYJLRNLDQD4AAAeAAYJLRNLDQD4AAAAAA==.Tallera:BAAALgADCgEJAgAAAA==.Talo:BAAALgADCgMJAwAAAA==.Tanddora:BAAALgAECgMJAwAAAA==.Taniyah:BAAALgAECgQJCAAAAA==.Tankinstine:BAAALgAECgUJCwAAAA==.Taraylda:BAABLgAECn8bAAMnAAkJVRgMGgDIAQAnAAgJIhgMGgDIAQAfAAMJdA2JXQChAAAAAA==.Tarful:BAAALgADCgQJBAAAAA==.Tarzand:BAAALgADCgEJAQABLgADCgcJDwAHAAAAAA==.Tazo:BAACLgAFFH8IAAIKAAIJbAwUTQB7AAAKAAIJbAwUTQB7AAAuAAQKfy0AAgoACQmKEPtzAIYBAAoACQmKEPtzAIYBAAAA.Tazu:BAAALgAECgUJBQAAAA==.Taàrna:BAAALgADCgYJBQAAAA==.',
Te='Tearek:BAACLgAFFH8FAAIcAAMJWw/FZgC/AAAcAAMJWw/FZgC/AAAuAAQKfx0AAhwABwlVHF06AN0BABwABwlVHF06AN0BAAAA.Tearik:BAAALgAECgYJBAAAAA==.Tecdor:BAAALgAECgQJBAAAAA==.Temla:BAACLgAFFH8GAAISAAIJMgRGkQB8AAASAAIJMgRGkQB8AAAuAAQKfy8AAhIACQlHFrg7APEBABIACQlHFrg7APEBAAAA.Tenga:BAAALgAECgQJBAAAAA==.Teronfiggy:BAABLgAECn8dAAMWAAkJLQ1LfgBnAQAWAAgJjA5LfgBnAQAZAAEJlgO1GwAuAAAAAA==.',
Tf='Tfirs:BAACLgAFFH8hAAIEAAUJ0BItDQDEAAAEAAUJ0BItDQDEAAAuAAQKfzAAAgQACQnSGZ4OAPsBAAQACQnSGZ4OAPsBAAEuAAEKCQkTAAcAAAAA.',
Th='Thartilidan:BAAALgAECgYJEQABLgAECgkJGgANAIEYAA==.Thegoodboi:BAABLgAECn8VAAIJAAcJFB3EBQDrAQAJAAcJFB3EBQDrAQAAAA==.Theokoles:BAAALgAECgQJBQAAAA==.Thepaladin:BAAALgAECgIJAQAAAA==.Thickblòód:BAAALgAFFAMJAwAAAA==.',
Ti='Tilythia:BAAALgADCgUJBQAAAA==.Tinn:BAAALgADCgEJAQAAAA==.',
To='Tona:BAAALgADCgMJAwAAAA==.Toospookie:BAAALgADCgQJAgAAAA==.Tophu:BAAALgADCgcJBwAAAA==.Torkz:BAAALgAECgMJBwAAAA==.Totem:BAAALgAECgUJBQAAAA==.',
Tr='Trabeajin:BAAALgAECgYJDAAAAA==.Tramplip:BAABLgAECn8+AAIBAAgJMRZ5AgCcAQABAAgJMRZ5AgCcAQAAAA==.Treecloud:BAACLgAFFH8FAAIGAAMJlhVuFwDGAAAGAAMJlhVuFwDGAAAuAAQKf1YAAwYACQnCJMYDACkDAAYACQnCJMYDACkDAAQACQmEFvkNAAMCAAAA.Treferimore:BAAALgADCgkJCQAAAA==.Trevian:BAABLgAECn8cAAIKAAkJfRNsSgDnAQAKAAkJfRNsSgDnAQAAAA==.Trinitee:BAAALgAECgEJAQABLgAECgMJBwAHAAAAAA==.',
Tu='Tub:BAAALgAECgQJBAABLgAFFAQJDAAQAHwLAA==.Tuluxxi:BAACLgAFFH8FAAIIAAMJsxc+IwDCAAAIAAMJsxc+IwDCAAAuAAQKf1IAAggACQnwInsEAG8DAAgACQnwInsEAG8DAAAA.Turbodiesell:BAAALgAECgEJAwAAAA==.Turborunic:BAAALgADCgkJGwAAAA==.Turdfergesun:BAAALgAECgEJAQAAAA==.Turiae:BAACLgAFFH8SAAQTAAYJgCBBIgBPAQATAAQJ/B5BIgBPAQAdAAEJZAGYLAA2AAAUAAEJAADXEQAAAAAuAAQKfy8ABBMACQlVInoEACEDABMACQlVInoEACEDABQABwnZFsgQANEBAB0ABQkhCaQ0AMgAAAAA.Tuskerz:BAAALgAECgEJAwAAAA==.Tusobrinna:BAAALgAECgUJDAAAAA==.Tutter:BAAALgADCgQJBAAAAA==.Tuuldd:BAAALgADCggJCAAAAA==.',
Tw='Twunk:BAAALgAECggJEAAAAA==.',
Ty='Tychuus:BAAALgAFFAIJBAAAAA==.Typhlotic:BAAALgADCgMJAwAAAA==.Tyrennius:BAAALgAECgQJBAAAAA==.Tyrianis:BAABLgAECn8rAAMNAAkJNyGeCgB5AgANAAkJSSCeCgB5AgAOAAMJzh6rEwDFAAAAAA==.',
Tz='Tzxdh:BAAALgAECgUJBQABLgAFFAMJAQAHAAAAAA==.Tzxdruid:BAAALgAECgEJAQABLgAFFAMJAQAHAAAAAA==.',
Ug='Uglymancer:BAABLgAECn8eAAMLAAkJ+RVyMgAPAgALAAkJ+RVyMgAPAgABAAEJAACGVAAAAAAAAA==.',
Uj='Ujimas:BAABLgAECn8ZAAMCAAgJoA9nWgDVAAACAAYJ/BNnWgDVAAAIAAcJRQsCiwDFAAAAAA==.Ujong:BAAALgAECgcJDgABLgAECgcJMgADALIkAA==.',
Un='Unchartedd:BAAALgADCgEJAQAAAA==.Unholynite:BAAALgADCgMJAwABLgADCgYJEAAHAAAAAA==.',
Va='Vaenira:BAAALgADCgUJBgAAAA==.Vako:BAABLgAECn8UAAIVAAQJyRKiIgDiAAAVAAQJyRKiIgDiAAAAAA==.Valdara:BAAALgADCgkJEgAAAA==.Valemon:BAAALgAECgIJAgAAAA==.Vampireshade:BAABLgAECn8/AAIXAAkJ5hAKAQCVAQAXAAkJ5hAKAQCVAQAAAA==.Vanimao:BAABLgAECn81AAQFAAkJdQ+tPACxAQAFAAkJdQ+tPACxAQAGAAcJjwlbRQD3AAAEAAcJrwzqLgDyAAAAAA==.Vankman:BAAALgADCgcJBwAAAA==.Vannaka:BAAALgADCgEJAQAAAA==.',
Vb='Vbull:BAAALgAECgEJAQAAAA==.',
Ve='Vedrolan:BAAALgADCgUJDgABLgAFFAQJEQAoACIhAA==.Velifya:BAAALgADCgMJAwAAAA==.Velindon:BAAALgADCgYJBgAAAA==.Velissari:BAABLgAECn87AAIPAAkJ9RsfAgB6AgAPAAkJ9RsfAgB6AgAAAA==.Velonar:BAAALgADCgEJAQAAAA==.Velouria:BAABLgAECn9bAAQEAAkJQCNVAgAcAwAEAAkJKSNVAgAcAwAGAAgJ6h8SDQDIAgAFAAIJ9QSXwABGAAAAAA==.Venatra:BAAALgAECgYJDwAAAA==.Verudora:BAAALgADCgcJBwAAAA==.Vexira:BAAALgADCgcJBwAAAA==.',
Vi='Violet:BAABLgAECn8gAAIdAAgJJBe/CwAdAgAdAAgJJBe/CwAdAgAAAA==.Violette:BAABLgAECn83AAISAAkJLRPuDQCRAQASAAkJLRPuDQCRAQAAAA==.Visix:BAAALgAECgUJBgAAAA==.Vitt:BAAALgAECgEJAgAAAA==.',
Vo='Voidchacha:BAAALgADCgEJAQAAAA==.Voidlink:BAACLgAFFH8FAAInAAMJXhqzFQDhAAAnAAMJXhqzFQDhAAAuAAQKfy0AAicACQmzFGcbAPMBACcACQmzFGcbAPMBAAAA.Voidmistress:BAABLgAECn8nAAIDAAcJGRggcQCXAQADAAcJGRggcQCXAQAAAA==.Voidpup:BAABLgAECn8oAAIcAAcJYxwqPwDMAQAcAAcJYxwqPwDMAQAAAA==.Volgrimm:BAABLgAECn8bAAIYAAgJKwsYNAAvAQAYAAgJKwsYNAAvAQAAAA==.Volitaire:BAAALgADCgYJBgAAAA==.Volkân:BAAALgAECgUJBQAAAA==.Vonbek:BAAALgAECgMJAwAAAA==.',
Vy='Vynethan:BAAALgAECgEJAgAAAA==.',
['Vé']='Véngence:BAABLgAECn8YAAIWAAcJLRHggABiAQAWAAcJLRHggABiAQAAAA==.',
['Vê']='Vêx:BAAALgADCgYJBgAAAA==.',
Wa='Wabalabalosh:BAAALgADCgkJCQAAAA==.Wabgucci:BAAALgADCgUJBQAAAA==.Wabwum:BAAALgAECgMJAwAAAA==.Wackyrellek:BAAALgAECggJDwAAAA==.Wakaekwondo:BAAALgAECgEJAQAAAA==.Wakarisma:BAAALgAECgEJAQAAAA==.Wakataclysm:BAAALgAECgMJAwAAAA==.Wanda:BAAALgAECgkJDQAAAA==.Wangao:BAABLgAFFH8IAAIYAAMJJAp9PgCtAAAYAAMJJAp9PgCtAAABLgAFFAQJEQAoACIhAA==.Warbluster:BAAALgADCgIJAgAAAA==.Warchylde:BAAALgADCgkJHwAAAA==.Warolderoy:BAACLgAFFH8FAAIeAAMJuBkSFwDlAAAeAAMJuBkSFwDlAAAuAAQKf1MAAh4ACQmlJMEDACwDAB4ACQmlJMEDACwDAAAA.Warshy:BAAALgAECgQJBAAAAA==.',
We='Weedshaman:BAAALgAECgEJAwAAAA==.Weedwax:BAAALgAECgQJBQAAAA==.Weil:BAAALgADCgIJAgAAAA==.',
Wh='Whiinuss:BAABLgAECn8UAAIKAAcJlw25fwB7AQAKAAcJlw25fwB7AQAAAA==.Whytrabbit:BAAALgAECgIJAgAAAA==.',
Wi='Wigglesdeath:BAAALgAECgUJBQAAAA==.',
Wl='Wldeagle:BAAALgAECgQJBQAAAA==.Wldshadow:BAAALgAECgIJAgAAAA==.',
Wo='Woker:BAAALgAECgcJEQABLgAFFAMJBQAVADkHAA==.Woodpig:BAABLgAECn8vAAQFAAkJ2SFfBgBSAwAFAAkJ2SFfBgBSAwAEAAIJVBMfUQBrAAAGAAMJcAo0cQBlAAAAAA==.Woogie:BAAALgAECgQJCwAAAA==.',
Wr='Wrangle:BAAALgADCgEJAQAAAA==.',
Wy='Wyldshade:BAAALgADCgYJCAAAAA==.Wyrm:BAAALgAECgUJBQABLgAECgUJCgAHAAAAAA==.',
Xa='Xaladin:BAABLgAECn8dAAIPAAkJVgypHwB8AQAPAAkJVgypHwB8AQAAAA==.Xantheos:BAAALgAECgEJAgAAAA==.Xathas:BAAALgAECgQJBAAAAA==.',
Xe='Xenna:BAAALgAECggJDAAAAA==.Xeq:BAAALgAECgcJEAAAAA==.',
Xi='Xiaolaopo:BAAALgAECgEJAgAAAA==.Xiata:BAAALgAECgkJEwAAAA==.Xiu:BAAALgAECgUJBgAAAA==.',
Xr='Xrp:BAAALgADCgQJBQAAAA==.',
Xt='Xtragun:BAAALgAECgEJAQABLgAFFAMJAwAHAAAAAA==.',
Ye='Yeoman:BAABLgAECn8uAAMeAAkJJhXGCQAxAQAeAAkJJhXGCQAxAQAbAAQJHwkNDACIAAAAAA==.Yeos:BAAALgAECgQJBAABLgAECgkJLgAeACYVAA==.',
Yg='Yggdralith:BAAALgAECgkJJAAAAQ==.',
Yi='Yiznusin:BAAALgAECgEJAgAAAA==.',
Ym='Yme:BAAALgAECgMJAwAAAA==.',
Yo='Yourdeath:BAAALgAECgkJBAAAAA==.',
Yu='Yunosmall:BAAALgADCgIJAgAAAA==.Yunosmart:BAAALgAECgYJCQAAAA==.Yusleepin:BAAALgADCgcJBwABLgADCgYJEAAHAAAAAA==.',
['Yú']='Yúm:BAAALgAECgEJAgAAAA==.',
Za='Zackoh:BAAALgAECgEJAQAAAA==.Zaen:BAACLgAFFH8eAAILAAQJdxWAIwAIAQALAAQJdxWAIwAIAQAuAAQKfzgAAwsACQkfISkVAKYCAAsACQkfISkVAKYCAAEAAwnUC7NDAKYAAAAA.Zagreus:BAAALgADCgcJCAAAAA==.Zakikaz:BAAALgAECgQJBQABLgAFFAMJAwAHAAAAAA==.Zakkah:BAAALgAECgEJAQABLgAFFAQJDAAJAFgkAA==.Zarkir:BAACLgAFFH8WAAMiAAQJixyRCQBWAQAiAAQJixyRCQBWAQAWAAMJmQwn7AB+AAAuAAQKfyYABCIACQmfJDECAPUCACIACQkqIjECAPUCABYABwnCIe1BAP0BABkABwmtF5oZAIcBAAEuAAQKBgkXAAMApyIA.Zarkìr:BAABLgAECn8XAAIDAAYJpyKQZwAIAgADAAYJpyKQZwAIAgAAAA==.Zaues:BAAALgAECgMJBAAAAA==.',
Ze='Zelily:BAABLgAECn8XAAISAAkJQQiVmgAMAQASAAkJQQiVmgAMAQAAAA==.Zenarri:BAAALgADCgYJBwAAAA==.Zenasdan:BAAALgADCgYJBgAAAA==.Zepha:BAAALgAECgcJDQAAAA==.Zerø:BAAALgAECgIJAgABLgAECgYJFwADAKciAA==.',
Zl='Zlyandien:BAAALgADCggJDwABLgAECgkJGwAnAFUYAA==.',
Zo='Zoomkin:BAAALgAFFAEJAQABLgAFFAMJAwAHAAAAAA==.Zornov:BAABLgAECn8jAAMoAAgJjx4zCwAVAgAoAAgJjx4zCwAVAgAMAAMJJggPcgBuAAAAAA==.Zortt:BAAALgAECgEJAgAAAA==.',
Zu='Zulrich:BAAALgAECgUJBQAAAA==.',
Zv='Zvirae:BAAALgADCgYJDwAAAA==.Zvirax:BAAALgAECgUJCgAAAA==.',
['Ëu']='Ëuni:BAABLgAECn8ZAAISAAgJ6QqBlQAVAQASAAgJ6QqBlQAVAQAAAA==.',
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
