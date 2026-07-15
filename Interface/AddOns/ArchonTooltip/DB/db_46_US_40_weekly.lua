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

local lookup = {'Warlock-Destruction','Mage-Frost','Druid-Guardian','Druid-Restoration','Druid-Balance','Unknown-Unknown','Shaman-Restoration','Monk-Mistweaver','Paladin-Retribution','Warlock-Demonology','Paladin-Holy','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Havoc','Monk-Windwalker','Warlock-Affliction','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','DeathKnight-Unholy','Rogue-Outlaw','Monk-Brewmaster','DeathKnight-Blood','Warrior-Protection','DemonHunter-Devourer','Evoker-Preservation','Warrior-Fury','Priest-Shadow','Priest-Holy','Druid-Feral','DeathKnight-Frost','Hunter-Survival','Hunter-Marksmanship','DemonHunter-Vengeance','Mage-Arcane','Warrior-Arms','Priest-Discipline','Paladin-Protection','Shaman-Elemental',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=46,date='2026-07-12',data={Ab='Abarlton:BAAALgAFFAEJAQABLgAECggJFAABAPQVAA==.',
Ac='Acorn:BAAALgAFFAEJAQAAAA==.',
Ad='Adabeam:BAAALgADCgcJCwAAAA==.Adagio:BAACLgAFFH8FAAICAAMJKgjNNgC/AAACAAMJKgjNNgC/AAAuAAQKf0QAAgIACQkFHhcmAIMCAAIACQkFHhcmAIMCAAAA.Adetalo:BAABLgAECn8lAAIDAAkJ8Re+DgD5AQADAAkJ8Re+DgD5AQAAAA==.Adiara:BAAALgAECgMJAwAAAA==.Aditu:BAABLgAECn81AAMEAAkJGB4ADwDdAgAEAAkJGB4ADwDdAgAFAAUJLRECCgDBAAAAAA==.',
Ae='Aelis:BAAALgADCgcJCAAAAA==.Aemulo:BAAALgAECgUJBwAAAA==.Aerith:BAAALgADCgcJBwAAAA==.Aessone:BAAALgAECgYJCQABLgAFFAQJHQACAEIUAA==.',
Ag='Agasonex:BAAALgADCgMJAwAAAA==.Aggroholic:BAAALgAECgQJBAABLgADCgYJEAAGAAAAAA==.',
Ai='Airent:BAABLgAECn8rAAMEAAgJrhQcBACVAQAEAAYJARccBACVAQAFAAgJehQ6BQBAAQAAAA==.Aiyana:BAAALgAECgYJDgAAAA==.',
Ak='Akhuahwe:BAAALgADCgUJAQAAAA==.Akiirii:BAAALgAECgEJAQAAAA==.',
Al='Alaestel:BAAALgAECgQJBwAAAA==.Aldo:BAAALgAECgcJDwAAAA==.Alenthele:BAAALgAECgEJAwAAAA==.Aletheia:BAAALgAFFAEJAQAAAA==.Alkaraho:BAAALgAECgMJAwAAAA==.Alleriya:BAAALgAECgEJAQABLgAFFAUJDgAHAH0OAA==.Alleyways:BAACLgAFFH8MAAIIAAQJWCSIEQAsAQAIAAQJWCSIEQAsAQAuAAQKfzwAAggACQn3JYIBAMcDAAgACQn3JYIBAMcDAAAA.Alzey:BAABLgAECn8oAAIJAAkJjQ+ZawCXAQAJAAkJjQ+ZawCXAQAAAA==.',
Am='Ambeon:BAAALgADCgUJBQAAAA==.Ammathindis:BAAALgAECgYJBgAAAA==.Ammutseba:BAAALgADCggJCAAAAA==.Amplers:BAAALgADCgUJBwAAAA==.',
An='Ancane:BAAALgAECgYJBgAAAA==.Andyxdd:BAAALgAECgIJAwABLgAFFAkJKgACAHAhAA==.Angelbane:BAAALgADCgQJBAAAAA==.Angina:BAAALgAECgIJBQAAAA==.Annarcis:BAABLgAECn8yAAIKAAgJ7BAIBgB/AQAKAAgJ7BAIBgB/AQAAAA==.Anotherdk:BAAALgAECgYJBgABLgAECgkJKQALAKojAA==.Anthiell:BAAALgADCgEJAQAAAA==.Antiman:BAABLgAECn8oAAIJAAkJQgz5awCWAQAJAAkJQgz5awCWAQAAAA==.Anäster:BAAALgAFFAEJAQABLgAFFAUJGAAJABIQAA==.',
Ap='Aplcyder:BAABLgAECn84AAIEAAkJVwy1RwBxAQAEAAkJVwy1RwBxAQAAAA==.',
Ar='Arabisa:BAAALgAECgQJBAAAAA==.Arachnid:BAABLgAECn8xAAICAAcJsiRFMQCtAgACAAcJsiRFMQCtAgAAAA==.Aragorn:BAAALgADCgkJDQAAAA==.Aratyn:BAABLgAECn8eAAICAAkJsg9sYAC/AQACAAkJsg9sYAC/AQAAAA==.Ariane:BAAALgAECgIJAgAAAA==.Army:BAAALgAECgQJBwAAAA==.',
As='Asanot:BAAALgAECgUJBQAAAA==.Ascendance:BAAALgAECgEJAQAAAA==.',
At='Atalisk:BAAALgAECgYJBgAAAA==.Ati:BAAALgADCgIJAgAAAA==.',
Au='Audxo:BAAALgADCgMJAwAAAA==.',
Ay='Ayayron:BAAALgADCgQJBAAAAA==.',
Ba='Backhawk:BAAALgADCgcJEAAAAA==.Backsurgery:BAABLgAFFH8QAAMMAAgJ9SBjCQALAgAMAAgJuh5jCQALAgANAAIJUyE2DQBhAAAAAA==.Baern:BAAALgAECgIJAgAAAA==.Baerrn:BAABLgAECn8nAAIOAAkJYQkNMQABAQAOAAkJYQkNMQABAQAAAA==.Baggins:BAAALgADCgEJAQAAAA==.Baltazaris:BAAALgAECgUJCAAAAA==.Bamboo:BAAALgAECgYJCQABLgAFFAMJCgAPAIAZAA==.Baricia:BAABLgAECn8cAAICAAkJ3wqHcgCVAQACAAkJ3wqHcgCVAQAAAA==.Barix:BAAALgAECgEJBAAAAA==.Barnd:BAAALgADCggJDwAAAA==.Barrin:BAABLgAECn88AAMQAAkJbxw2BQA6AgAQAAkJbxw2BQA6AgAKAAUJQgiUvADRAAAAAA==.Bastim:BAAALgAECgQJDAAAAA==.Baussassbich:BAAALgAECgQJBAABLgAECgkJJAAKAE4hAA==.Bawnchu:BAAALgAECgQJDAAAAA==.',
Be='Beastmaster:BAACLgAFFH8FAAIRAAMJvSBqVgD6AAARAAMJvSBqVgD6AAAuAAQKfy8AAhEACAmYJH8UAK4CABEACAmYJH8UAK4CAAAA.Beefcakell:BAAALgADCgcJDQAAAA==.Beiki:BAAALgAECgcJEAAAAA==.Belthar:BAAALgAECgQJCQAAAA==.Bently:BAABLgAECn8iAAMSAAcJpSHFHwDaAQASAAcJ9R/FHwDaAQATAAUJGCMtEwCvAQAAAA==.Berexis:BAAALgAECgkJEQAAAA==.',
Bi='Bissafiyah:BAACLgAFFH8hAAIUAAgJ6CCTAAB3AgAUAAgJ6CCTAAB3AgAuAAQKf1kAAhQACQn4JgUAAKoDABQACQn4JgUAAKoDAAAA.Biznasty:BAAALgAECgEJAwAAAA==.',
Bl='Bloodgon:BAABLgAFFH8HAAIVAAMJUhjRjADwAAAVAAMJUhjRjADwAAAAAA==.Bluetuesday:BAAALgAECgQJBwAAAA==.',
Bo='Bogart:BAAALgAECgEJAQAAAA==.Bohica:BAABLgAECn84AAIHAAkJRhFXPQC5AQAHAAkJRhFXPQC5AQAAAA==.Bonechop:BAAALgAECgEJAgAAAA==.Bootymeat:BAAALgADCgEJAQAAAA==.Bowtox:BAAALgAECgEJAQAAAA==.Boyakasha:BAABLgAECn9EAAIWAAgJyBOQAACwAQAWAAgJyBOQAACwAQAAAA==.',
Br='Bratislava:BAAALgAECgYJEAAAAA==.Brewfu:BAAALgADCgIJAgAAAA==.Brewpub:BAAALgADCgQJBAAAAA==.Brewsome:BAABLgAECn9BAAQPAAkJQyF8BgDkAgAPAAkJQyF8BgDkAgAXAAkJ1RhjEgAhAgAIAAEJ0xHbtAA7AAAAAA==.Bruceleëroy:BAAALgAECgQJBQAAAA==.Bruceprime:BAAALgAECgkJAQAAAA==.Bryybryy:BAABLgAECn8YAAMYAAkJ6R4UAQCLAgAYAAkJ6R4UAQCLAgAVAAEJ8AtWQgAlAAAAAA==.Bryycelest:BAABLgAECn8jAAIXAAgJ5BptFwDuAQAXAAgJ5BptFwDuAQABLgAECgkJGAAYAOkeAA==.Bryydruid:BAAALgAECgEJAQABLgAECgkJGAAYAOkeAA==.Brz:BAAALgAECgYJEAAAAA==.Brådòn:BAAALgAECgYJEQAAAA==.',
Bu='Bucket:BAABLgAECn8wAAIZAAkJEho3CgBPAgAZAAkJEho3CgBPAgAAAA==.Bunkiee:BAAALgADCgkJIQAAAA==.Bunnybane:BAAALgAECgYJEAAAAA==.Burlath:BAAALgADCgMJAwAAAA==.Burny:BAABLgAECn8aAAICAAcJVCVMJgDZAgACAAcJVCVMJgDZAgABLgAFFAQJDAAIAFgkAA==.Buttadogg:BAAALgAECgcJDwAAAA==.',
['Bè']='Bèth:BAAALgAECgQJAgAAAA==.',
['Bë']='Bëckey:BAAALgADCgIJAgAAAA==.',
Ca='Calyx:BAABLgAECn8xAAIaAAcJTwn+DwDTAAAaAAcJTwn+DwDTAAAAAA==.Canadani:BAAALgAECgcJDQAAAA==.Candorite:BAABLgAECn8dAAMSAAkJbw3aQAAmAQASAAcJzQzaQAAmAQAbAAIJKA6fMABoAAAAAA==.Caphriel:BAABLgAECn8dAAIcAAkJQB3LFwAvAgAcAAkJQB3LFwAvAgAAAA==.Capita:BAABLgAECn8cAAICAAgJjAmboQA4AQACAAgJjAmboQA4AQAAAA==.Captndave:BAAALgADCgMJAwAAAA==.Carrian:BAAALgAECgEJAgAAAA==.Carsinegan:BAAALgAECgUJBgAAAA==.Cassica:BAABLgAECn8dAAMdAAcJbhlQOAA0AQAdAAcJbhlQOAA0AQAeAAIJ1gnNZgBIAAAAAA==.Catchdezhanz:BAAALgADCgcJBwABLgAECgcJMQALAJ8WAA==.Catskin:BAABLgAECn8jAAMfAAkJuiBTBAC9AgAfAAgJKiNTBAC9AgAEAAYJ8htBPQCeAQAAAA==.',
Ce='Celivalasha:BAAALgADCgUJBQAAAA==.Cell:BAABLgAECn8jAAIXAAgJTSQqBQA3AwAXAAgJTSQqBQA3AwAAAA==.Cet:BAAALgADCgUJBQABLgAECgEJAQAGAAAAAA==.',
Ch='Chadvader:BAAALgADCgIJAgAAAA==.Chainlink:BAAALgADCgYJBgAAAA==.Chalee:BAAALgAECgEJAQAAAA==.Chandraskhar:BAAALgADCgIJAgAAAA==.Chanpagne:BAAALgAECgEJAQAAAA==.Charkle:BAABLgAECn8WAAIRAAcJWhhiSADIAQARAAcJWhhiSADIAQAAAA==.Chayea:BAAALgADCgEJAQAAAA==.Chicknraptor:BAAALgAECgUJBQAAAA==.Chillylilly:BAABLgAECn8vAAMYAAkJbSV4AgAnAwAYAAkJbSV4AgAnAwAgAAQJ4Ry0EwBBAQAAAA==.Chlorophyll:BAAALgAECgQJBAAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chopsuoy:BAAALgAECgEJAQAAAA==.Chummie:BAABLgAECn8wAAMKAAkJ2h/2GACOAgAKAAkJcR/2GACOAgAQAAYJdxxDCADHAQAAAA==.',
Ci='Ciandoril:BAABLgAECn8rAAUDAAkJVxfpBgDrAAAFAAcJ8heQJACnAQADAAQJ8BLpBgDrAAAfAAMJHhTVLACyAAAEAAMJ+Q8rjwCXAAAAAA==.Cielcin:BAAALgAFFAMJAwAAAA==.Ciremiih:BAAALgAECgEJAQAAAA==.Citymage:BAACLgAFFH8LAAICAAUJWAWBcwD4AAACAAUJWAWBcwD4AAAuAAQKfykAAgIACQmbF0JGAAgCAAIACQmbF0JGAAgCAAAA.Cixelsyd:BAAALgADCgYJCwABLgAFFAcJDwAJAMsGAA==.',
Cl='Clamchowda:BAABLgAECn8vAAMaAAkJoBsRJwAvAgAaAAkJKxkRJwAvAgAOAAUJUh5wIwCiAQAAAA==.',
Co='Codê:BAABLgAECn8oAAIKAAkJAhm1JABMAgAKAAkJAhm1JABMAgAAAA==.Coffeecup:BAAALgADCgIJAgAAAA==.Colchagua:BAAALgAECgEJAgAAAA==.Corride:BAABLgAECn8rAAIhAAgJgR8AEQAkAgAhAAgJgR8AEQAkAgAAAA==.Corspar:BAAALgAECgQJBgAAAA==.',
Cr='Crazyeyes:BAAALgADCgYJCQAAAA==.Crimsondeath:BAABLgAECn9FAAIYAAgJBg9TBAA1AQAYAAgJBg9TBAA1AQAAAA==.Crom:BAAALgAECgIJBAAAAA==.Crutch:BAABLgAECn8mAAMHAAkJyRy9DADzAgAHAAkJyRy9DADzAgAUAAUJCBWQGgAuAQAAAA==.Crystanikus:BAAALgAECgQJBQAAAA==.',
Cu='Cuckenjoyer:BAAALgAECgYJCgAAAA==.',
Cy='Cyclonian:BAAALgAECgEJAgABLgAECgQJBQAGAAAAAA==.Cyprus:BAAALgAECgEJAQAAAA==.',
Da='Daddytrump:BAABLgAECn8eAAIIAAkJPw8kMgCvAQAIAAkJPw8kMgCvAQAAAA==.Daelric:BAAALgAECgYJDgAAAA==.Daender:BAACLgAFFH8GAAIRAAIJaxvaegCiAAARAAIJaxvaegCiAAAuAAQKfzAAAxEACQl3JGQIABcDABEACQl3JGQIABcDACIAAQmCGAk7ADUAAAAA.Daenor:BAAALgAECgQJBwAAAA==.Dairydemon:BAACLgAFFH8XAAIjAAQJBwoaBACwAAAjAAQJBwoaBACwAAAuAAQKfzcAAiMACQkSDxsMAJYBACMACQkSDxsMAJYBAAAA.Damageus:BAACLgAFFH8OAAICAAMJgB+nbgAFAQACAAMJgB+nbgAFAQAuAAQKfx8AAwIACAnqIjkkAOICAAIACAnqIjkkAOICACQAAQlGIMYEAFwAAAAA.Danhausen:BAAALgAECgEJAgAAAA==.Daniryl:BAEBLgAECn8bAAIEAAgJfxW1LAD1AQAEAAgJfxW1LAD1AQAAAA==.Dar:BAAALgAECgQJCwAAAA==.Darcnescoach:BAABLgAECn8YAAIlAAcJHROhAgBIAQAlAAcJHROhAgBIAQAAAA==.Darcness:BAABLgAECn8lAAQNAAYJkhmvDABgAQANAAYJhxavDABgAQAMAAUJTxZQOABSAQAWAAEJIRayIQBEAAAAAA==.Darcside:BAABLgAECn9AAAMdAAgJ5BWpAgDKAQAdAAgJ5BWpAgDKAQAmAAUJtwWEDACyAAAAAA==.Darkclouds:BAAALgADCgIJAgAAAA==.Darksoul:BAABLgAECn8UAAIKAAkJWwYiiAApAQAKAAkJWwYiiAApAQABLgAECgkJGwAmAFUYAA==.Darkxwraith:BAABLgAECn8aAAILAAcJuhmABQAyAQALAAcJuhmABQAyAQAAAA==.Dashtoolite:BAABLgAECn8eAAIaAAgJNw23bABKAQAaAAgJNw23bABKAQAAAA==.Datsombeech:BAAALgAECgcJBwAAAA==.Datsumbeech:BAABLgAECn8mAAIgAAkJDg60DgCKAQAgAAkJDg60DgCKAQAAAA==.',
Dc='Dcoi:BAAALgADCgQJBAAAAA==.',
De='Deajer:BAAALgADCgYJBwAAAA==.Deathsabeach:BAAALgAECgEJAQAAAA==.Deathvìxen:BAABLgAECn8XAAMdAAgJyAc2PgAYAQAdAAgJyAc2PgAYAQAmAAMJiwYxbgBPAAAAAA==.Debit:BAAALgAECgcJEwAAAA==.Demonhunter:BAACLgAFFH8KAAIaAAQJkiHQPQAwAQAaAAQJkiHQPQAwAQAuAAQKfx0AAhoACAk/JKkKAC4DABoACAk/JKkKAC4DAAAA.Demonwoogie:BAAALgADCgYJBgABLgAECgQJCwAGAAAAAA==.Dendrophilia:BAAALgAECgYJCgAAAA==.Densamin:BAABLgAECn8oAAQJAAkJ+BWpQAAFAgAJAAkJ+BWpQAAFAgALAAIJugH4hgA9AAAnAAEJ4wuFUwApAAAAAA==.Deviyn:BAAALgADCgIJAgAAAA==.Devourussy:BAAALgADCgkJCQAAAA==.Devra:BAAALgADCggJCAAAAA==.Dexter:BAAALgAECgEJAgAAAA==.Deàdly:BAABLgAECn8ZAAMgAAcJHyFiCAAIAgAgAAcJHyFiCAAIAgAVAAMJghmcJAF+AAAAAA==.',
Dh='Dhaynk:BAAALgAFFAEJAQAAAA==.',
Di='Dietchrist:BAAALgAECggJEwAAAA==.Dilligaf:BAAALgADCggJCAAAAA==.',
Dk='Dkanabiss:BAAALgAECgMJBAAAAA==.Dkinabox:BAAALgAECgUJCwAAAA==.',
Do='Docbaba:BAAALgAFFAEJAgAAAA==.Doh:BAAALgADCgIJAgAAAA==.Doist:BAAALgAECgIJAgAAAA==.Donngaz:BAAALgAECgMJBgAAAA==.Dookey:BAAALgAECgMJAwAAAA==.Doomwood:BAAALgADCgkJAQAAAA==.',
Dr='Drakeskin:BAAALgADCgEJAQAAAA==.Drakir:BAAALgAECgkJAQAAAA==.Dreadgnar:BAAALgAECgEJAgAAAA==.Drewnei:BAAALgADCgkJCQAAAA==.Drewserk:BAABLgAECn8pAAIcAAkJKxxxFQBEAgAcAAkJKxxxFQBEAgAAAA==.Drkxmaniac:BAAALgAECgcJEAABLgAECggJFAABAPQVAA==.Drminnowphd:BAAALgAFFAEJAQAAAA==.Drpiscisphd:BAACLgAFFH8cAAMVAAYJRR4dDgDTAQAVAAYJRR4dDgDTAQAYAAEJdAUSRQAjAAAuAAQKfzEAAxUACQk1Ie4OACQDABUACQk1Ie4OACQDABgABwnDBYIpAPMAAAAA.Drsaltyballz:BAABLgAECn8uAAINAAkJyiKRAQDwAgANAAkJyiKRAQDwAgAAAA==.Drugpala:BAAALgAECgIJAgAAAA==.Druji:BAAALgAECggJEwAAAA==.Drumuss:BAAALgADCgEJAQAAAA==.',
Du='Ducat:BAABLgAECn8ZAAICAAUJRwss7gDGAAACAAUJRwss7gDGAAAAAA==.Dudesk:BAAALgAECgUJBgAAAA==.Duffuna:BAAALgADCgEJAQABLgAFFAMJBQAhADwfAA==.Duffunha:BAACLgAFFH8FAAIhAAMJPB+8BQAiAQAhAAMJPB+8BQAiAQAuAAQKf0wAAiEACQkIJq4AAHQDACEACQkIJq4AAHQDAAAA.',
Dy='Dye:BAABLgAECn80AAILAAkJhx6XCAABAwALAAkJhx6XCAABAwAAAA==.Dyre:BAABLgAECn8nAAIjAAkJXQ9xDQB8AQAjAAkJXQ9xDQB8AQAAAA==.Dyslexic:BAACLgAFFH8GAAIBAAUJnQPeCAALAQABAAUJnQPeCAALAQAuAAQKfyYAAgEACAlzGHsHANwBAAEACAlzGHsHANwBAAEuAAUUBwkPAAkAywYA.Dyspepsia:BAACLgAFFH8PAAIJAAcJywYQEQAdAQAJAAcJywYQEQAdAQAuAAQKfx8AAgkACQmZG08+AAwCAAkACQmZG08+AAwCAAAA.',
['Dô']='Dôngus:BAAALgADCgMJAwABLgAECgQJBQAGAAAAAA==.',
['Dõ']='Dõngus:BAAALgAECgQJBAABLgAECgQJBQAGAAAAAA==.',
['Dö']='Döngus:BAAALgAECgEJAgABLgAECgQJBQAGAAAAAA==.',
Ed='Edie:BAAALgAECgEJBgAAAA==.',
Ei='Eirenn:BAAALgAECgkJDQAAAA==.',
El='Elayna:BAAALgAECgkJBwAAAA==.Elenaura:BAAALgAECgMJAwAAAA==.Eleren:BAABLgAECn8bAAIaAAgJiBLzWwB0AQAaAAgJiBLzWwB0AQAAAA==.Elimee:BAACLgAFFH8FAAICAAIJnRAmqACDAAACAAIJnRAmqACDAAAuAAQKfzAAAgIACQmgIUkOAFQDAAIACQmgIUkOAFQDAAAA.Elisestraza:BAABLgAFFH8GAAISAAMJfg3gRwCqAAASAAMJfg3gRwCqAAABLgAFFAIJBQACAJ0QAA==.Ellasia:BAABLgAECn8UAAINAAYJzwM3GACyAAANAAYJzwM3GACyAAAAAA==.Elric:BAACLgAFFH8GAAIJAAIJtAcKnACDAAAJAAIJtAcKnACDAAAuAAQKfzUAAgkACQlMGcY2ACYCAAkACQlMGcY2ACYCAAAA.Elsie:BAAALgAECgcJDgABLgAECgkJKAALAGwfAA==.Elton:BAAALgAECgYJBgAAAA==.Elunea:BAAALgADCgcJDQAAAA==.Elunemittens:BAAALgADCgYJBgAAAA==.',
Em='Emart:BAABLgAECn8lAAIhAAkJaw69GQDRAQAhAAkJaw69GQDRAQAAAA==.Emozella:BAAALgAECgEJAQAAAA==.',
En='Enatresh:BAABLgAECn8ZAAICAAgJ5QQPHQCvAAACAAgJ5QQPHQCvAAAAAA==.',
Ep='Epsilon:BAAALgAECgkJCQAAAA==.',
Er='Erayna:BAABLgAECn86AAIEAAkJsRaMHABiAgAEAAkJsRaMHABiAgAAAA==.Ereillea:BAAALgAECgYJDQAAAA==.',
Es='Essence:BAABLgAECn8WAAMCAAgJmxTpagAAAgACAAgJDBHpagAAAgAkAAQJ1xocDAARAQAAAA==.',
Et='Etherious:BAAALgAECgcJCQABLgAECgkJKAALAGwfAA==.',
Eu='Euko:BAACLgAFFH8GAAMFAAIJqRSFPACCAAAFAAIJqRSFPACCAAAEAAIJwA5vWABpAAAuAAQKfzUAAwUACQkvIfkIAMMCAAUACQkvIfkIAMMCAAQACAl1FZlmAAABAAAA.',
Ev='Evedk:BAAALgAECgkJBQAAAA==.Evepriest:BAAALgAECgEJAQAAAA==.',
Fa='Failrogue:BAAALgADCgUJCwAAAA==.Falconclaw:BAAALgAECggJDQAAAA==.Falkensnoman:BAABLgAECn8oAAIYAAkJvBWMEwDZAQAYAAkJvBWMEwDZAQAAAA==.Fayedra:BAABLgAECn8eAAIDAAkJbxR+EADhAQADAAkJbxR+EADhAQAAAA==.Faytaleti:BAAALgAECgQJBAAAAA==.',
Fc='Fcawfe:BAAALgAECgQJBAABLgAECgkJHQALAJ0cAA==.',
Fe='Febee:BAAALgADCgcJAQAAAA==.Feenii:BAACLgAFFH8FAAIUAAMJOQcQCACzAAAUAAMJOQcQCACzAAAuAAQKfzoAAhQACQlSHdAFAIECABQACQlSHdAFAIECAAAA.Felburst:BAAALgAECgMJAwAAAA==.Feldog:BAAALgADCgkJCQAAAA==.Felfireqt:BAAALgAECgEJAgAAAA==.Fersiam:BAAALgAECgcJAQABLgAECgkJKAALAGwfAA==.Feydros:BAAALgAECgkJBQAAAA==.',
Fh='Fhaani:BAAALgADCgIJAgAAAA==.',
Fi='Figgyandrii:BAAALgAECgUJBQAAAA==.Fionar:BAAALgADCgIJAgAAAA==.Fizzlelich:BAAALgAECgYJBgAAAA==.',
Fl='Flamesters:BAABLgAFFH8IAAICAAYJpwgTTABIAQACAAYJpwgTTABIAQAAAA==.Fluffpuff:BAAALgADCgMJAwAAAA==.Fluffyfury:BAAALgADCgEJAQAAAA==.',
Fm='Fmpumps:BAAALgAECgEJAQAAAA==.',
Fo='Foxdeer:BAABLgAECn8fAAMKAAkJmQjagwAxAQAKAAkJmQjagwAxAQAQAAMJ4wKhHwB0AAAAAA==.Foxxmccloud:BAAALgAFFAEJAQABLgAFFAMJCwAFAIsdAA==.',
Fr='Frenchtoast:BAAALgAECgUJBwAAAA==.',
Fu='Fufighter:BAAALgADCgQJBAAAAA==.Furyrage:BAAALgAECgEJAQAAAA==.Fuzzyclawz:BAAALgADCgYJBgABLgAECgkJLAAPADMQAA==.',
Ga='Gambachii:BAAALgAECgcJDQAAAA==.Gankss:BAABLgAECn8pAAMLAAkJqiPdAQCYAwALAAkJqiPdAQCYAwAJAAEJNAHU1QEMAAAAAA==.Gannir:BAAALgAECgIJAgABLgAECgcJEAAGAAAAAA==.Garakddon:BAAALgAECgYJBgABLgAECggJIAAnANsWAA==.Garryy:BAAALgAECgMJBwAAAA==.',
Ge='Geegandolm:BAAALgADCgkJEwAAAA==.Gemìnì:BAAALgAECgEJAgABLgAECggJFAAOAEQRAA==.Genjaru:BAABLgAECn8mAAMFAAYJRBzEBABPAQAFAAYJRBzEBABPAQAEAAMJ2QJ0wABFAAAAAA==.Genndalf:BAAALgADCgcJBwAAAA==.Geostorm:BAAALgAECgEJAQAAAA==.',
Gh='Gharmag:BAAALgAECgEJAQAAAA==.',
Gi='Giramar:BAABLgAECn84AAMdAAgJ5BzoEgA7AgAdAAgJ5BzoEgA7AgAeAAcJhg5JNAA0AQAAAA==.',
Gl='Glagkara:BAAALgAECgMJBwAAAA==.',
Go='Gobbyshamm:BAAALgAECgEJAQAAAA==.Gobsmackers:BAAALgAECgYJBwAAAA==.Gomklin:BAAALgADCgcJCAABLgAFFAIJBwAJAMUdAA==.Goobtastic:BAAALgADCgQJBAAAAA==.Goteem:BAAALgAECggJEwAAAA==.Gothitelle:BAAALgAECgIJAwAAAA==.',
Gr='Griffhud:BAABLgAECn8YAAIDAAcJDiEHEQDaAQADAAcJDiEHEQDaAQAAAA==.Grimrox:BAABLgAECn8lAAIoAAkJYxLFJADCAQAoAAkJYxLFJADCAQAAAA==.Grixx:BAAALgADCgUJBQAAAA==.Groupie:BAAALgADCgUJCgABLgAECgcJGAAiANUPAA==.',
Gt='Gtatedk:BAAALgAECgEJAQAAAA==.',
Gu='Guccimain:BAAALgAECgEJAQAAAA==.Guntera:BAAALgAECgYJDgAAAA==.Guts:BAAALgADCgMJAwAAAA==.',
Gw='Gwendalyn:BAAALgAECgQJBQAAAA==.',
['Gä']='Gäz:BAAALgADCgEJAQAAAA==.',
Ha='Haanit:BAAALgAECgYJBgAAAA==.Halexion:BAAALgADCgIJAgAAAA==.Haomaru:BAABLgAECn8XAAQEAAUJLBliSgBlAQAEAAUJLBliSgBlAQAfAAEJiBBnVAAwAAAFAAEJSAv1lwAoAAAAAA==.Hardcandy:BAABLgAECn8YAAIiAAcJ1Q8zGQDmAAAiAAcJ1Q8zGQDmAAAAAA==.Hardlyevoker:BAAALgADCgEJAQABLgAFFAIJBgALAOYQAA==.',
He='Heartsoul:BAAALgAECgYJCQAAAA==.Heavyarm:BAAALgADCgcJDwAAAA==.Hellork:BAAALgADCgQJBAAAAA==.Hermosura:BAAALgADCgUJCgAAAA==.Hex:BAAALgAFFAEJAQABLgAFFAEJAwAGAAAAAA==.',
Hi='Hiccups:BAAALgAECgMJBAABLgAFFAMJAwAGAAAAAA==.Himawarí:BAABLgAECn8yAAMZAAkJUBXvDgD7AQAZAAkJgxPvDgD7AQAcAAUJwhoUQQBAAQAAAA==.Hiyank:BAABLgAECn8qAAIXAAkJrCKKBgDRAgAXAAkJrCKKBgDRAgABLgAFFAEJAQAGAAAAAA==.',
Ho='Hoffmin:BAABLgAECn8XAAMaAAkJdBnybABKAQAaAAgJdBnybABKAQAOAAIJphK0VgCMAAAAAA==.Holemeister:BAACLgAFFH8PAAIJAAMJnCNgSQAaAQAJAAMJnCNgSQAaAQAuAAQKfzAAAgkACAmhJOINAB8DAAkACAmhJOINAB8DAAAA.Holyamin:BAAALgADCgEJAQAAAA==.Holyfresh:BAAALgADCgEJAQAAAA==.Holymann:BAABLgAECn8lAAIdAAgJ3A05DwCFAAAdAAgJ3A05DwCFAAAAAA==.Holyschnikey:BAABLgAECn8xAAILAAcJnxY+AwCpAQALAAcJnxY+AwCpAQAAAA==.Holyz:BAABLgAECn85AAMLAAkJpCMeAgCPAwALAAkJpCMeAgCPAwAJAAEJBhk/bQFKAAAAAA==.Horgable:BAAALgADCgIJAgAAAA==.Horrorpops:BAAALgAECgMJAwABLgAFFAIJBgARAGsbAA==.Hozaki:BAAALgAECgQJBAABLgAECggJFAABAPQVAA==.',
Hu='Hudfin:BAAALgAECgQJBQAAAA==.Hundred:BAAALgAECgIJAgABLgAFFAEJAQAGAAAAAA==.Huntinwoogie:BAAALgAECgIJAwABLgAECgQJCwAGAAAAAA==.Hunzul:BAAALgADCgcJCAAAAA==.',
Hy='Hyrule:BAAALgAECgYJBgABLgAFFAMJBQAmAF4aAA==.',
['Hí']='Hílthaen:BAABLgAECn84AAMeAAkJmRbqEwA4AgAeAAkJmRbqEwA4AgAmAAEJMQllHAApAAAAAA==.',
Ic='Icebones:BAAALgADCgcJDAABLgAECgQJCQAGAAAAAA==.Icelight:BAAALgAECgQJCQAAAA==.Ichigokisu:BAABLgAECn8WAAIJAAgJaRG0dQCCAQAJAAgJaRG0dQCCAQAAAA==.',
Il='Illiduji:BAAALgADCgMJAwAAAA==.Illy:BAABLgAECn8jAAIaAAkJ+hYELgAPAgAaAAkJ+hYELgAPAgAAAA==.',
Im='Imply:BAAALgAECgMJAwAAAA==.Imposed:BAAALgAECgcJEAAAAA==.',
In='Instantdeath:BAABLgAECn8UAAQBAAgJ9BU0AwARAQABAAUJ7RY0AwARAQAKAAUJHgpszwC0AAAQAAUJKhONBgCYAAAAAA==.Invali:BAAALgAECgYJCQAAAA==.',
Io='Iorla:BAAALgADCgcJBgAAAA==.',
Ir='Irônhide:BAAALgAECgEJAQAAAA==.',
Iv='Ivranda:BAAALgADCgkJEgABLgAECgkJHQASAG8NAA==.',
Iz='Iz:BAAALgAECgEJAQAAAA==.',
Ja='Jaapp:BAAALgAECgMJBgAAAA==.Jahan:BAACLgAFFH8XAAImAAQJuxkiDQA2AQAmAAQJuxkiDQA2AQAuAAQKfy8AAyYACQlZIQYGACMDACYACAkiJAYGACMDAB0ABAmAEdBHAPAAAAEuAAUUAQkBAAYAAAAA.Jalisha:BAAALgAECgUJCAAAAA==.Jamie:BAABLgAFFH8IAAIVAAMJhCMDcAAeAQAVAAMJhCMDcAAeAQABLgAFFAgJGwAKAAAhAA==.Jaydine:BAAALgADCgYJBgABLgAFFAIJBQACAJ0QAA==.',
Je='Jeri:BAAALgAECgYJCAAAAA==.Jerithal:BAAALgAECgMJAwAAAA==.',
Jh='Jhie:BAABLgAECn8pAAIPAAkJYhaqHADJAQAPAAkJYhaqHADJAQAAAA==.',
Ji='Jinro:BAAALgAECgEJAgABLgAECgEJAwAGAAAAAA==.',
Jo='Jodi:BAAALgAECgEJAQAAAA==.',
Ju='Jud:BAAALgAECggJEAAAAA==.Juviâ:BAAALgAECggJCgABLgAECgkJKAALAGwfAA==.Juxtaposed:BAAALgADCgUJBQAAAA==.',
Ka='Kaelora:BAAALgAECgYJCQAAAA==.Kaerei:BAABLgAECn8sAAIJAAkJnh75IQB+AgAJAAkJnh75IQB+AgAAAA==.Kaleb:BAACLgAFFH8KAAIOAAQJ+R6aCQBuAQAOAAQJ+R6aCQBuAQAuAAQKfyEAAg4ACAm2IVkLAHECAA4ACAm2IVkLAHECAAAA.Kalferno:BAABLgAECn8XAAICAAcJ7BR1DABIAQACAAcJ7BR1DABIAQAAAA==.Kalirkaz:BAACLgAFFH8LAAIEAAMJVA2MGACLAAAEAAMJVA2MGACLAAAuAAQKfz8AAwQACQk0HYkCAA0CAAQACQk0HYkCAA0CAAUABQk5BspkAIkAAAAA.Kallipsa:BAAALgAECgMJAwAAAA==.Karasu:BAAALgAECggJCgABLgAECgkJLAAPADMQAA==.Kariel:BAAALgADCgQJBAAAAA==.Karst:BAAALgAECgQJBQABLgAFFAEJAQAGAAAAAA==.Kathria:BAAALgAECgcJEAAAAA==.Kayotica:BAAALgAECgcJDAAAAA==.',
Ke='Keepcrying:BAAALgAECgEJAQAAAA==.Kegendary:BAAALgAECgQJCAAAAA==.Keler:BAAALgAECgEJAQABLgAECgMJBwAGAAAAAA==.Kelideyn:BAAALgAECgYJBgAAAA==.Keládry:BAABLgAECn8XAAILAAcJHhd8MgCMAQALAAcJHhd8MgCMAQAAAA==.Keskiyö:BAAALgADCgkJFQABLgAECgkJLAAPADMQAA==.',
Kh='Khaalid:BAAALgAECgEJAwABLgAECgEJAwAGAAAAAA==.Khallock:BAABLgAECn8lAAIQAAgJCRmaDgByAQAQAAgJCRmaDgByAQAAAA==.Khamael:BAAALgAECgEJAQAAAA==.',
Ki='Kiemen:BAABLgAECn8oAAMVAAkJHRoONwAjAgAVAAkJHRoONwAjAgAgAAEJbQ4kOwAxAAAAAA==.Kierya:BAAALgAECgEJAgAAAA==.Killerpoison:BAAALgAECgkJBQAAAA==.Killko:BAACLgAFFH8GAAIVAAIJbg+B0QCPAAAVAAIJbg+B0QCPAAAuAAQKfxsAAhUACQn+G/YrAFACABUACQn+G/YrAFACAAAA.Kinki:BAAALgAECgMJAwABLgAECgcJGAAiANUPAA==.Kirisen:BAAALgAECgUJCQAAAA==.Kitan:BAAALgAECgQJBQAAAA==.Kitani:BAAALgADCgkJGAABLgAECgkJagAmANYiAA==.',
Ko='Konno:BAAALgAECgQJBAABLgAFFAgJIQAUAOggAA==.Kooterr:BAAALgADCgUJBQAAAA==.Korbix:BAACLgAFFH8GAAIVAAMJFQztZgBlAAAVAAMJFQztZgBlAAAuAAQKfxcAAhUABglaGxx1AHkBABUABglaGxx1AHkBAAAA.',
Kr='Kragsloor:BAAALgAFFAEJAQAAAA==.Kredorin:BAAALgAECgYJCgAAAA==.Krewella:BAAALgADCgcJBwAAAA==.Krickette:BAAALgAECgYJBgAAAA==.Krihl:BAAALgAECgkJBgAAAA==.Krovmar:BAAALgADCgUJBQAAAA==.Kryoos:BAAALgAECgEJAQAAAA==.',
Ks='Kspanxx:BAAALgAECgMJAwAAAA==.',
Kt='Kthanx:BAAALgAECgQJAgAAAA==.',
Ku='Kungpowgazer:BAABLgAECn8XAAMXAAkJ/R1RCgCOAgAXAAkJ/R1RCgCOAgAPAAEJew8PowAtAAAAAA==.Kunls:BAABLgAECn8eAAIOAAgJrgiELQAWAQAOAAgJrgiELQAWAQAAAA==.Kuraak:BAAALgAECgQJBwAAAA==.Kuraki:BAABLgAECn8eAAIPAAkJbAqSLABcAQAPAAkJbAqSLABcAQAAAA==.Kurasa:BAABLgAECn8sAAMPAAkJMxAeIwCYAQAPAAkJMxAeIwCYAQAIAAQJowH4WgBjAAAAAA==.Kutraz:BAAALgAECgQJBQAAAA==.',
La='Ladrar:BAABLgAECn8aAAQfAAkJnhZEDAD0AQAfAAgJxhhEDAD0AQAFAAMJQAz1aAB8AAAEAAEJ6ATT7wAgAAAAAA==.Laelina:BAAALgAECgEJAwAAAA==.Laidiemonk:BAAALgADCgYJBgAAAA==.Lanadiel:BAACLgAFFH8GAAInAAIJyxi6DgCUAAAnAAIJyxi6DgCUAAAuAAQKfzUAAicACQmIIs8CAPoCACcACQmIIs8CAPoCAAAA.Lazz:BAABLgAECn8UAAQhAAcJpiEDFQD7AQAhAAcJpiEDFQD7AQAiAAQJ5RkJQQBVAQARAAEJAADvVQEAAAABLgAFFAQJDAAIAFgkAA==.',
Le='Legend:BAACLgAFFH8aAAIaAAYJCh6SGgATAQAaAAYJCh6SGgATAQAuAAQKfzIAAhoACQm3IDAJAD4DABoACQm3IDAJAD4DAAAA.Lekrotar:BAAALgAECgQJBAAAAA==.Letsyoudie:BAAALgAECgMJAwAAAA==.',
Li='Lian:BAABLgAECn8XAAIIAAYJrgsdagDYAAAIAAYJrgsdagDYAAAAAA==.Lichbane:BAABLgAECn81AAIVAAkJmCFEFwC7AgAVAAkJmCFEFwC7AgAAAA==.Licun:BAAALgAECgYJDQAAAA==.Lifexdeath:BAABLgAECn8ZAAMeAAcJ5QbYQgDfAAAeAAcJ5QbYQgDfAAAdAAEJxgM5lwAjAAAAAA==.Lightcell:BAAALgAECgQJBgAAAA==.Liliara:BAABLgAECn80AAIRAAkJ3BCPRwDLAQARAAkJ3BCPRwDLAQAAAA==.Lillyirl:BAAALgAECgUJEQAAAA==.Lillymae:BAAALgAECggJDAAAAA==.Lillyslight:BAAALgADCgYJBgAAAA==.Lillysneak:BAAALgADCgUJCgAAAA==.Lillytae:BAAALgAECgQJBwAAAA==.Lillyzard:BAAALgAECgEJAQAAAA==.Lilmoo:BAAALgAECggJEAAAAA==.Linkhunter:BAAALgAECgYJBgABLgAFFAMJBQAmAF4aAA==.Linni:BAABLgAECn8oAAILAAkJbB+5BQA1AwALAAkJbB+5BQA1AwAAAA==.Lizardwizard:BAAALgAECgQJBAAAAA==.',
Lo='Lockgodtko:BAAALgAECgcJDQAAAA==.Lodise:BAABLgAECn8oAAMQAAkJsw4SCgDAAQAQAAkJsw4SCgDAAQAKAAEJAAgZHQEyAAAAAA==.Lonful:BAAALgADCgEJAQAAAA==.Lorzz:BAACLgAFFH8YAAIeAAQJRhI5CwDLAAAeAAQJRhI5CwDLAAAuAAQKfzcAAh4ACQk8INkFABoDAB4ACQk8INkFABoDAAAA.Lothe:BAABLgAECn8eAAILAAkJtB43CAAIAwALAAkJtB43CAAIAwAAAA==.',
Lu='Lucrio:BAABLgAECn9BAAIVAAkJNhZ1NAAtAgAVAAkJNhZ1NAAtAgAAAA==.Ludlow:BAAALgAECgIJAgABLgAECgkJHQALAJ0cAA==.Ludoe:BAAALgADCgkJMQAAAA==.Luminariah:BAAALgAECgYJEQABLgAECgcJDwAGAAAAAA==.Luna:BAAALgAFFAEJAQAAAA==.Lunalai:BAABLgAECn9BAAIDAAkJ3iKBAgAVAwADAAkJ3iKBAgAVAwAAAA==.Lurim:BAAALgAECgEJBAABLgAECggJIwAnAI8eAA==.Lushy:BAABLgAECn8aAAIMAAkJgRgEDgBIAgAMAAkJgRgEDgBIAgAAAA==.',
Ly='Lylineth:BAAALgADCgYJBgAAAA==.Lylinette:BAAALgAECgcJEgAAAA==.Lyssandra:BAAALgADCgUJBQAAAA==.',
['Lí']='Lízandor:BAACLgAFFH8YAAIJAAUJEhDiTgARAQAJAAUJEhDiTgARAQAuAAQKfykAAgkACQmYHF4sAFACAAkACQmYHF4sAFACAAAA.',
['Lû']='Lûsøn:BAAALgAECgEJAQAAAA==.',
Ma='Machotee:BAAALgAECgEJAQAAAA==.Madruskee:BAABLgAECn8sAAIgAAYJQBqjAgA/AQAgAAYJQBqjAgA/AQAAAA==.Magahpt:BAAALgAECgMJBAAAAA==.Magdea:BAAALgADCgYJBgAAAA==.Mageofdeath:BAAALgAECgYJCAABLgAECggJFAABAPQVAA==.Mageofhonor:BAAALgAECgEJAgAAAA==.Magistroll:BAABLgAECn8cAAICAAcJXgXt1wDmAAACAAcJXgXt1wDmAAAAAA==.Mairisella:BAAALgAECgIJAgAAAA==.Malabathrum:BAAALgAECgEJAgAAAA==.Maladaptive:BAAALgAECgEJAgAAAA==.Malevohaynk:BAAALgAECgQJBQABLgAFFAEJAQAGAAAAAA==.Mandrallea:BAAALgAECgYJBwAAAA==.Manerva:BAAALgAECgUJAgAAAA==.Maryshelley:BAAALgADCgMJAwAAAA==.Matoo:BAAALgADCgEJAQAAAA==.Mattertusk:BAAALgAECgEJAwAAAA==.Mattincis:BAAALgAFFAMJAQAAAA==.Maurin:BAAALgAFFAEJAgAAAA==.Maximumhonk:BAABLgAECn8nAAIHAAcJiRMUVwBaAQAHAAcJiRMUVwBaAQAAAA==.',
Me='Melfys:BAAALgAECgEJAQAAAA==.Melpómene:BAAALgAECgEJAQABLgAECgkJLgAKAMATAA==.Mendelia:BAABLgAECn81AAInAAkJRhZEAwBJAQAnAAkJRhZEAwBJAQAAAA==.Mercus:BAABLgAECn8ZAAMWAAkJ9RgiBgBqAQAWAAYJpBQiBgBqAQAMAAgJLxrxMQAUAQAAAA==.Merkstrasza:BAAALgAECgcJDwAAAA==.Mervenious:BAABLgAECn8fAAQcAAgJzxDpLgCUAQAcAAgJzxDpLgCUAQAlAAQJ7Q7eTACcAAAZAAMJpQhrOQB/AAAAAA==.Meu:BAAALgAECgkJCwAAAA==.',
Mi='Midasdh:BAACLgAFFH8OAAIaAAUJ0wuUVQDuAAAaAAUJ0wuUVQDuAAAuAAQKfxwAAxoACAmAF5Y+APoBABoACAnfFJY+APoBAA4ABgmOFwMwAE8BAAAA.Midasdk:BAACLgAFFH8NAAIVAAUJEhrDYwAvAQAVAAUJEhrDYwAvAQAuAAQKfxwAAxUABwnMHG9PAAQCABUABwm9GW9PAAQCACAAAwkzEkMmAKAAAAEuAAUUBQkOABoA0wsA.Midasmonk:BAAALgAECgEJAQABLgAFFAUJDgAaANMLAA==.Midasshift:BAAALgAECgcJDwAAAA==.Miladepollo:BAAALgADCgMJAwAAAA==.Milkers:BAAALgAECgEJAQAAAA==.Mindblank:BAAALgAECgQJBAAAAA==.Mindplague:BAABLgAECn9BAAIdAAkJKh8ZAQCMAgAdAAkJKh8ZAQCMAgAAAA==.Minipincin:BAAALgAECgUJBgAAAA==.Minisicwidit:BAAALgADCgMJAwAAAA==.Miroslava:BAAALgAECgYJBwAAAA==.Mirrorforce:BAAALgAFFAEJAQAAAA==.Mistdeeznuts:BAACLgAFFH8OAAIIAAQJpwjkPACyAAAIAAQJpwjkPACyAAAuAAQKfx8AAwgACQmWDOo5AIoBAAgACQmWDOo5AIoBAA8AAQmSA/a7AB0AAAAA.',
Mo='Mogwaï:BAAALgAECgcJCwAAAA==.Mokokoma:BAAALgAECgMJBAAAAA==.Moonde:BAAALgAECgkJDwAAAA==.Moonscale:BAABLgAECn80AAITAAkJHR/2AQC9AgATAAkJHR/2AQC9AgAAAA==.Moosayer:BAAALgAECgQJBgAAAA==.Moovement:BAAALgAECgMJAwABLgAFFAIJAwAGAAAAAA==.Mossed:BAAALgADCgMJAwAAAA==.',
Ms='Mskelsier:BAAALgAECgUJBQAAAA==.',
Mt='Mtaur:BAAALgADCggJDwAAAA==.',
Mu='Muclor:BAAALgADCgcJBwABLgAFFAMJAwAGAAAAAA==.Muffintop:BAAALgAECgEJAQABLgAECgkJLwAEANkhAA==.Murkyn:BAAALgAECgEJAQAAAA==.Mustang:BAAALgAECgUJBQAAAA==.',
My='Mydadstayed:BAAALgAECgYJCwABLgAECgcJJwAHAIkTAA==.Mythalis:BAAALgAECgQJBQAAAA==.Mythar:BAAALgAECgEJAQAAAA==.',
['Mä']='Märändus:BAAALgADCgEJAQAAAA==.',
['Må']='Måzikeen:BAAALgADCgMJAwAAAA==.',
Na='Nardena:BAAALgAECgUJAwAAAA==.Narse:BAABLgAFFH8GAAIeAAIJvwhSLgBeAAAeAAIJvwhSLgBeAAAAAA==.Narz:BAACLgAFFH8NAAIRAAMJGAeALgDGAAARAAMJGAeALgDGAAAuAAQKfzgAAhEACQlxFCA1AAgCABEACQlxFCA1AAgCAAAA.Nastianna:BAAALgAECgQJCgAAAA==.Natgeo:BAAALgAECgkJEAABLgAFFAMJBQAmAF4aAA==.Nazumi:BAABLgAECn8oAAIPAAkJ/R5vCADAAgAPAAkJ/R5vCADAAgAAAA==.',
Nd='Ndiz:BAABLgAECn8VAAIRAAcJIhwCJwAdAgARAAcJIhwCJwAdAgAAAA==.',
Ne='Necronomikon:BAAALgAECgEJAQAAAA==.Neeva:BAAALgADCgYJEAAAAA==.Nelrya:BAEALgADCgcJDQABLgAFFAUJDQAJALAPAA==.Nephilym:BAAALgAECgEJAQAAAA==.Nerhzul:BAAALgAECgcJDgAAAA==.Nerial:BAAALgAECgEJAQABLgAECgEJAwAGAAAAAA==.Neruphuyt:BAABLgAECn86AAIFAAgJExTQBgAMAQAFAAgJExTQBgAMAQAAAA==.',
Ni='Niath:BAAALgAECgYJBwAAAA==.Nightsniper:BAABLgAECn8VAAIRAAkJyBkbRwDMAQARAAkJyBkbRwDMAQAAAA==.Ninfassins:BAAALgADCgIJAgAAAA==.',
No='Norintha:BAAALgADCgEJAQAAAA==.Norolen:BAAALgADCgIJAgAAAA==.',
Nu='Nuzzle:BAAALgAECgEJAQABLgAECgkJPQADACMbAA==.',
Ny='Nyxelle:BAAALgAECgQJBAAAAA==.Nyxiel:BAAALgAECgQJBQABLgAECgcJDwAGAAAAAA==.',
['Nò']='Nòvà:BAAALgAECgEJAQABLgAECggJFAAOAEQRAA==.',
Oa='Oak:BAAALgAECgkJEgAAAA==.',
Oc='Occo:BAAALgADCgEJAQAAAA==.',
Og='Ogroc:BAAALgAECgQJBAAAAA==.',
Ok='Okioak:BAABLgAECn8UAAQlAAkJcxKZLQATAQAlAAgJFRKZLQATAQAcAAMJ5BFjgAC8AAAZAAIJpwatQABOAAAAAA==.',
Ol='Olgon:BAACLgAFFH8SAAIRAAQJrQ87KgDXAAARAAQJrQ87KgDXAAAuAAQKfzoAAhEACQmvGhkeAHECABEACQmvGhkeAHECAAAA.Olstinkyboot:BAAALgAECgEJAQAAAA==.',
Op='Oprhawinfury:BAABLgAECn8iAAIVAAkJRA7jZgCZAQAVAAkJRA7jZgCZAQAAAA==.',
Or='Orcchop:BAAALgAECgEJBAAAAA==.Orgodemir:BAAALgADCgkJDwAAAA==.Orhamin:BAAALgAECgMJAwAAAA==.',
Os='Oshani:BAAALgAFFAEJAwAAAA==.',
Ot='Otemoto:BAAALgAECgEJAQABLgAFFAEJAQAGAAAAAA==.',
Ou='Ouin:BAAALgAECgUJBQABLgAECgkJLwAoAHITAA==.',
Ox='Oxley:BAAALgAECgEJAgAAAA==.',
Pa='Paigor:BAAALgAECgQJBgAAAA==.Pakswagger:BAABLgAECn8XAAMbAAYJFRfoEwCLAQAbAAYJFRfoEwCLAQASAAMJRQS2ewBqAAAAAA==.Pallyberry:BAABLgAECn8xAAILAAkJZhsZEACYAgALAAkJZhsZEACYAgAAAA==.Pancake:BAAALgAECgEJAQAAAA==.Pandemonia:BAABLgAECn8zAAMBAAkJ5Q0rFgCYAQABAAgJHgwrFgCYAQAKAAkJJw2ibQBgAQAAAA==.Paprika:BAAALgADCgkJEQAAAA==.Parsie:BAAALgAFFAIJAgAAAA==.Patch:BAAALgADCgYJBgAAAA==.Pathibas:BAAALgADCgEJAQABLgAFFAMJBQAcALgZAA==.Pattycakes:BAABLgAECn8jAAIVAAkJLBZoSgDjAQAVAAkJLBZoSgDjAQAAAA==.',
Pe='Pencil:BAACLgAFFH8gAAIKAAYJoRsbGQAjAQAKAAYJoRsbGQAjAQAuAAQKfxsABAoACAkwHSM6APIBAAoACAkwHSM6APIBAAEAAwniBj1dAFcAABAAAQkAANAsAEUAAAAA.Pewpewlvltwo:BAACLgAFFH8UAAIUAAQJFgwTBQD2AAAUAAQJFgwTBQD2AAAuAAQKfygAAhQACAnQHmMJACYCABQACAnQHmMJACYCAAAA.Pewthree:BAAALgAECgYJCAABLgAFFAQJFAAUABYMAA==.',
Ph='Pherocious:BAABLgAECn8VAAIiAAUJ6xP/GQDfAAAiAAUJ6xP/GQDfAAAAAA==.',
Pi='Pintsize:BAAALgADCgIJAgAAAA==.',
Pl='Plaguelis:BAAALgADCgEJAQABLgAFFAMJBQAUADkHAA==.Plexy:BAAALgAECgcJCgABLgAFFAYJDgAoAMURAA==.',
Po='Pobble:BAAALgADCgcJBwAAAA==.Pokitz:BAACLgAFFH8HAAIJAAMJiQKKOQCQAAAJAAMJiQKKOQCQAAAuAAQKf08AAgkACQkYEQRSANMBAAkACQkYEQRSANMBAAAA.Poprock:BAAALgAECgEJAQAAAA==.Potus:BAAALgADCgQJBAAAAA==.',
Pr='Primordinor:BAACLgAFFH8HAAIoAAMJChNYNgC0AAAoAAMJChNYNgC0AAAuAAQKfyoAAygACQkCHsUOAIICACgACQkCHsUOAIICAAcABwnTF90yAOcBAAAA.Probnotalive:BAABLgAECn8nAAIRAAkJ5RoYHQB2AgARAAkJ5RoYHQB2AgAAAA==.Probnotferal:BAAALgAECgEJAQAAAA==.Probnoturmom:BAABLgAECn8dAAIeAAgJVxt2GAAYAgAeAAgJVxt2GAAYAgAAAA==.',
Ra='Raevyn:BAAALgAFFAEJAQAAAA==.Rafaiel:BAAALgAECgQJBAAAAA==.Rakan:BAABLgAECn9BAAIlAAkJPh4xBgCdAgAlAAkJPh4xBgCdAgAAAA==.Rakasha:BAAALgADCgkJCQAAAA==.Raktanu:BAAALgADCgkJCQABLgAECgkJYgAlAIEZAA==.Rallick:BAACLgAFFH8ZAAILAAQJkBE8DgDbAAALAAQJkBE8DgDbAAAuAAQKfzEAAgsACQm3GLEQAJECAAsACQm3GLEQAJECAAAA.Ranloth:BAAALgAECgcJBwAAAA==.Ranì:BAACLgAFFH8GAAIZAAIJZwbUJwBcAAAZAAIJZwbUJwBcAAAuAAQKfzUAAhkACQnxFwIRANoBABkACQnxFwIRANoBAAAA.Raptorfarian:BAAALgAECgQJCAABLgAECgcJDwAGAAAAAA==.Rathger:BAAALgAECggJEgAAAA==.Ravenscythe:BAAALgADCgEJAQAAAA==.Raydor:BAAALgAECggJDgAAAA==.',
Re='Reb:BAABLgAECn8mAAIdAAkJ6gSiOwAjAQAdAAkJ6gSiOwAjAQAAAA==.Redic:BAAALgAECgMJAwAAAA==.Regis:BAAALgAECgYJBgABLgAFFAMJBwAUAF8KAA==.Rellix:BAAALgADCgUJBQAAAA==.Rendkick:BAAALgADCgcJBwAAAA==.Rendwee:BAABLgAECn88AAIfAAkJuiN5AQAyAwAfAAkJuiN5AQAyAwAAAA==.Reuel:BAAALgAECgYJCgAAAA==.Revlon:BAABLgAECn8ZAAIMAAYJeA5DBQAOAQAMAAYJeA5DBQAOAQAAAA==.Rewolf:BAABLgAECn8UAAIHAAkJuhICKQAaAgAHAAkJuhICKQAaAgAAAA==.',
Rh='Rheemus:BAAALgAECgEJAwABLgAFFAIJBgARAGsbAA==.Rhul:BAAALgAECgcJDwAAAA==.',
Ri='Ricflairion:BAABLgAECn8bAAISAAgJTQmVQwAbAQASAAgJTQmVQwAbAQAAAA==.Rimuru:BAAALgAECgMJBgABLgAECgMJBwAGAAAAAA==.',
Ro='Robkin:BAAALgAECgEJAQAAAA==.Rodcet:BAACLgAFFH8HAAIJAAIJxR0phwClAAAJAAIJxR0phwClAAAuAAQKfzwAAgkACQnBJXUFAEkDAAkACQnBJXUFAEkDAAAA.Roflcopterr:BAABLgAECn85AAQLAAkJTxyHDQC6AgALAAkJTxyHDQC6AgAJAAYJ9QcB6QDTAAAnAAEJSAXuWgAZAAAAAA==.Rognan:BAAALgAECgMJAwAAAA==.Roku:BAAALgAECgEJAQAAAA==.Romina:BAAALgADCgEJBAAAAA==.Ronkin:BAAALgAECgUJAgAAAA==.Rookgue:BAACLgAFFH8YAAINAAYJyRChAACQAQANAAYJyRChAACQAQAuAAQKf1cAAg0ACQkSH2YAADcCAA0ACQkSH2YAADcCAAAA.Rookoker:BAABLgAECn8iAAITAAgJxglUDQA4AQATAAgJxglUDQA4AQAAAA==.Rootsafarian:BAAALgADCgcJBwAAAA==.Rossa:BAAALgAECgEJAgAAAA==.Rossdair:BAABLgAECn8UAAMVAAgJDBEEhwBWAQAVAAYJxBYEhwBWAQAYAAIJwALnVABHAAABLgADCgUJCQAGAAAAAA==.Rossperot:BAACLgAFFH8SAAIVAAMJwCI5JgAaAQAVAAMJwCI5JgAaAQAuAAQKfzUAAhUACQmiJCQBAC4DABUACQmiJCQBAC4DAAAA.Rothschild:BAAALgADCgEJAQAAAA==.Rottenfist:BAAALgAECgEJAQAAAA==.',
Sa='Sabako:BAAALgADCgcJCAAAAA==.Sacra:BAAALgADCgUJBQABLgAFFAEJAQAGAAAAAA==.Saelara:BAAALgADCgcJCgAAAA==.Saelis:BAAALgADCgQJBAAAAA==.Sakaru:BAABLgAECn8bAAICAAgJTw7ViABlAQACAAgJTw7ViABlAQABLgAECgkJLAAPADMQAA==.Salmoney:BAAALgAECgQJBAAAAA==.Salorin:BAAALgADCgYJCQAAAA==.Samgee:BAACLgAFFH8gAAIJAAQJGhwQMABSAQAJAAQJGhwQMABSAQAuAAQKf0YAAgkACQlgIWwRAAUDAAkACQlgIWwRAAUDAAAA.Sandormu:BAAALgADCgkJCQAAAA==.Saphas:BAAALgAECgMJAwAAAA==.Saynar:BAABLgAECn89AAIaAAkJxCPNBQAtAwAaAAkJxCPNBQAtAwAAAA==.',
Sc='Scattered:BAABLgAECn8fAAQKAAkJohMidABSAQAKAAcJsBIidABSAQABAAMJJBRLQACzAAAQAAEJggs9QgAtAAAAAA==.Scooter:BAAALgAECgUJCgAAAA==.Scyx:BAAALgADCgEJAQAAAA==.',
Se='Seba:BAACLgAFFH8dAAICAAQJQhT9JQAPAQACAAQJQhT9JQAPAQAuAAQKf0EAAgIACQm2IKEWANECAAIACQm2IKEWANECAAAA.Sebushko:BAAALgADCgMJAQABLgAFFAQJHQACAEIUAA==.Selesne:BAABLgAECn8eAAIWAAkJ+QmPCwBfAQAWAAkJ+QmPCwBfAQAAAA==.Seraphicktwo:BAABLgAECn8tAAMeAAkJdhk5IADBAQAeAAcJnhg5IADBAQAdAAgJmhfRBgAZAQAAAA==.Seriana:BAABLgAECn8WAAIeAAgJfwvfNwAeAQAeAAgJfwvfNwAeAQAAAA==.Sermidas:BAACLgAFFH8KAAMlAAMJqRvJJgDSAAAlAAMJqRvJJgDSAAAcAAIJ3AevGwCYAAAuAAQKfyIAAyUACQk6H7gCAPACACUACQk6H7gCAPACABwABwnOFFw0ANgBAAEuAAUUBQkOABoA0wsA.',
Sh='Shadowcutter:BAAALgAECgEJAwABLgAECggJFAABAPQVAA==.Shaggmz:BAABLgAECn9FAAIcAAgJshh7AgDsAQAcAAgJshh7AgDsAQAAAA==.Shawnkin:BAAALgADCgQJAgAAAA==.Shigglez:BAAALgAECgkJCQAAAA==.Shinakuma:BAAALgAECgUJDgAAAA==.Shinma:BAABLgAECn9AAAInAAgJGwyuAwAzAQAnAAgJGwyuAwAzAQAAAA==.Shrubbery:BAABLgAECn8VAAIKAAcJ+wM5wQDKAAAKAAcJ+wM5wQDKAAAAAA==.Shymary:BAABLgAECn9BAAImAAgJaQwjBQBrAQAmAAgJaQwjBQBrAQAAAA==.',
Si='Siete:BAAALgAECgEJAQABLgAECgQJCQAGAAAAAA==.Silvertip:BAAALgADCggJFQAAAA==.Silëx:BAABLgAECn8sAAICAAkJExr2BQDVAQACAAkJExr2BQDVAQAAAA==.Silëxa:BAAALgAECgYJEQAAAA==.Sindiz:BAAALgAFFAEJAQAAAA==.Sioc:BAAALgAECgEJAQAAAA==.Siouxiesioux:BAAALgADCgYJCgAAAA==.Siyona:BAAALgADCgkJDAAAAA==.',
Sk='Skeith:BAAALgAECgkJCQAAAA==.Skits:BAAALgAECgIJAgAAAA==.Skyrah:BAAALgAECgYJBgAAAA==.Skyrie:BAAALgADCgQJBQAAAA==.',
Sl='Slagbröder:BAAALgADCgcJBwAAAA==.Slohine:BAAALgAECgUJBQAAAA==.Sludgecrush:BAAALgAECgYJCwAAAA==.Slugondeez:BAACLgAFFH8GAAILAAIJ5hC1PwBkAAALAAIJ5hC1PwBkAAAuAAQKfxYAAgsABQkWI38iAPEBAAsABQkWI38iAPEBAAAA.',
Sm='Smacker:BAAALgAFFAEJAQAAAA==.Smallmike:BAAALgAECgIJAgAAAA==.Smitefist:BAAALgAECgIJAgABLgAECgQJBQAGAAAAAA==.Smokiee:BAABLgAECn8ZAAIEAAkJvxBmNADKAQAEAAkJvxBmNADKAQAAAA==.',
Sn='Snacker:BAAALgAECgEJAQAAAA==.Snailtrail:BAABLgAECn8gAAIjAAkJ8wTOFAAIAQAjAAkJ8wTOFAAIAQAAAA==.Snark:BAABLgAECn8dAAIVAAYJrAjrFQDEAAAVAAYJrAjrFQDEAAAAAA==.Snarkkin:BAAALgAECgQJDAABLgAECgYJHQAVAKwIAA==.Snkyturtle:BAACLgAFFH8YAAIRAAQJYBMaQAAtAQARAAQJYBMaQAAtAQAuAAQKfzUAAhEACQllFH0/AOQBABEACQllFH0/AOQBAAAA.Snowkim:BAEBLgAECn8bAAInAAgJmh3yDAD2AQAnAAgJmh3yDAD2AQAAAA==.Snuzzle:BAABLgAECn89AAIDAAkJIxveCQBLAgADAAkJIxveCQBLAgAAAA==.',
So='Soniic:BAAALgAECgIJAgAAAA==.Soullessfros:BAABLgAECn8nAAIVAAkJ7ROkPgAIAgAVAAkJ7ROkPgAIAgAAAA==.Soullessman:BAAALgADCgQJCAAAAA==.Soupshammich:BAAALgAECgEJAQAAAA==.Sourmash:BAAALgADCgkJCgAAAA==.',
Sp='Spaghet:BAABLgAECn8fAAIoAAkJNRkqHgDwAQAoAAkJNRkqHgDwAQAAAA==.Sparkleponi:BAAALgAECgEJAQABLgAECgcJMQACALIkAA==.Spillthetea:BAABLgAECn8UAAMIAAkJmQipWwAGAQAIAAkJmQipWwAGAQAPAAEJzgm8lwA4AAAAAA==.Sploot:BAAALgAECggJEgAAAA==.',
Sq='Squibbles:BAAALgAECgEJAQAAAA==.',
Sr='Srasjet:BAABLgAECn8kAAIHAAkJ9h0FCwAHAwAHAAkJ9h0FCwAHAwAAAA==.',
Ss='Ssimba:BAAALgAECggJDQAAAA==.',
St='Stabytha:BAABLgAECn8nAAMMAAgJzxE9BgDtAAAMAAgJDhE9BgDtAAANAAEJ1RdRJQA/AAAAAA==.Stark:BAAALgADCgYJCgAAAA==.Starlight:BAAALgAECgEJAQAAAA==.Stars:BAAALgAFFAEJAQAAAA==.Stealthed:BAAALgAECggJEwAAAA==.Stender:BAAALgAECgcJDAABLgAFFAYJDwAOAK8fAA==.Steàlthed:BAAALgAECgEJAQABLgAECggJEwAGAAAAAA==.Stormae:BAAALgADCgMJAgAAAA==.Stormcall:BAABLgAECn8rAAIHAAkJ9h01FACqAgAHAAkJ9h01FACqAgAAAA==.Stratusfied:BAAALgAECgQJCQAAAA==.',
Su='Susbandaid:BAAALgADCgYJBgAAAA==.',
Sw='Sweetiefox:BAACLgAFFH8KAAICAAUJqgOLeQDlAAACAAUJqgOLeQDlAAAuAAQKfx0AAgIACQnYDicOADQBAAIACQnYDicOADQBAAAA.Swiss:BAABLgAECn8eAAIoAAkJhxCZKgCdAQAoAAkJhxCZKgCdAQAAAA==.',
Sy='Syllai:BAAALgAECgYJBgAAAA==.Symboli:BAAALgADCgQJBAAAAA==.Syphus:BAAALgADCgQJBAAAAA==.',
['Sá']='Sáëgárón:BAABLgAECn8ZAAMcAAgJahbCJwC9AQAcAAgJahbCJwC9AQAlAAEJpwX7hgAiAAAAAA==.',
Ta='Ta:BAAALgADCgMJAwAAAA==.Tacyon:BAAALgADCggJFgAAAA==.Taliden:BAABLgAECn8aAAIcAAYJLRMyCQD2AAAcAAYJLRMyCQD2AAAAAA==.Tallera:BAAALgADCgEJAgAAAA==.Talo:BAAALgADCgMJAwAAAA==.Taniyah:BAAALgAECgQJCAAAAA==.Tankinstine:BAAALgAECgUJCwAAAA==.Taraylda:BAABLgAECn8bAAMmAAkJVRgMGgDIAQAmAAgJIhgMGgDIAQAdAAMJdA2JXQChAAAAAA==.Tarful:BAAALgADCgQJBAAAAA==.Tarzand:BAAALgADCgEJAQABLgADCgcJDwAGAAAAAA==.Tazo:BAACLgAFFH8IAAIJAAIJbAwIPQCGAAAJAAIJbAwIPQCGAAAuAAQKfy0AAgkACQmKEPtzAIYBAAkACQmKEPtzAIYBAAAA.Tazu:BAAALgAECgUJBQAAAA==.Taàrna:BAAALgADCgYJBQAAAA==.',
Te='Tearek:BAACLgAFFH8FAAIaAAMJWw/FZgC/AAAaAAMJWw/FZgC/AAAuAAQKfx0AAhoABwlVHF06AN0BABoABwlVHF06AN0BAAAA.Tearik:BAAALgAECgYJBAAAAA==.Tecdor:BAAALgAECgQJBAAAAA==.Temla:BAACLgAFFH8GAAIRAAIJMgRGkQB8AAARAAIJMgRGkQB8AAAuAAQKfy8AAhEACQlHFrg7APEBABEACQlHFrg7APEBAAAA.Tenga:BAAALgAECgQJBAAAAA==.Teronfiggy:BAABLgAECn8dAAMVAAkJLQ1LfgBnAQAVAAgJjA5LfgBnAQAYAAEJlgNQEgAwAAAAAA==.',
Tf='Tfirs:BAACLgAFFH8dAAIDAAUJ7hBvCwC9AAADAAUJ7hBvCwC9AAAuAAQKfzAAAgMACQnSGZ4OAPsBAAMACQnSGZ4OAPsBAAEuAAEKCQkTAAYAAAAA.',
Th='Thartilidan:BAAALgAECgYJEQABLgAECgkJGgAMAIEYAA==.Thegoodboi:BAAALgAFFAIJAgAAAA==.Theokoles:BAAALgAECgQJBQAAAA==.Thepaladin:BAAALgAECgIJAQAAAA==.Thickblòód:BAAALgAFFAEJAQAAAA==.',
Ti='Tilythia:BAAALgADCgUJBQAAAA==.Tinn:BAAALgADCgEJAQAAAA==.',
To='Tona:BAAALgADCgMJAwAAAA==.Toospookie:BAAALgADCgQJAgAAAA==.Tophu:BAAALgADCgcJBwAAAA==.Torkz:BAAALgAECgMJBwAAAA==.Totem:BAAALgAECgUJBQAAAA==.',
Tr='Trabeajin:BAAALgAECgYJDAAAAA==.Tramplip:BAABLgAECn86AAIBAAgJkhS6CQCrAQABAAgJkhS6CQCrAQAAAA==.Treecloud:BAACLgAFFH8FAAIFAAMJlhVJEADWAAAFAAMJlhVJEADWAAAuAAQKf00AAwUACQldJMYDACkDAAUACQldJMYDACkDAAMACQmEFvkNAAMCAAAA.Trevian:BAABLgAECn8cAAIJAAkJfRNsSgDnAQAJAAkJfRNsSgDnAQAAAA==.Trinitee:BAAALgAECgEJAQABLgAECgMJBwAGAAAAAA==.',
Tu='Tub:BAAALgAECgQJBAABLgAFFAQJDAAPAHwLAA==.Tuluxxi:BAACLgAFFH8FAAIHAAMJsheAGgDQAAAHAAMJsheAGgDQAAAuAAQKf1IAAgcACQnwInsEAG8DAAcACQnwInsEAG8DAAAA.Turbodiesell:BAAALgAECgEJAwAAAA==.Turborunic:BAAALgADCgkJGwAAAA==.Turdfergesun:BAAALgAECgEJAQAAAA==.Turiae:BAACLgAFFH8SAAQSAAYJgCBBIgBPAQASAAQJ/B5BIgBPAQAbAAEJZAGYLAA2AAATAAEJAADXEQAAAAAuAAQKfy8ABBIACQlVInoEACEDABIACQlVInoEACEDABMABwnZFsgQANEBABsABQkhCaQ0AMgAAAAA.Tuskerz:BAAALgAECgEJAwAAAA==.Tusobrinna:BAAALgAECgUJDAAAAA==.Tutter:BAAALgADCgQJBAAAAA==.Tuuldd:BAAALgADCggJCAAAAA==.',
Tw='Twunk:BAAALgAECggJEAAAAA==.',
Ty='Tychuus:BAAALgAFFAIJBAAAAA==.Typhlotic:BAAALgADCgMJAwAAAA==.Tyrennius:BAAALgAECgQJBAAAAA==.Tyrianis:BAABLgAECn8rAAMMAAkJNyGeCgB5AgAMAAkJSSCeCgB5AgANAAMJzh6rEwDFAAAAAA==.',
Tz='Tzxdh:BAAALgAECgUJBQABLgAFFAMJAQAGAAAAAA==.Tzxdruid:BAAALgAECgEJAQABLgAFFAMJAQAGAAAAAA==.',
Ug='Uglymancer:BAABLgAECn8eAAMKAAkJ+RVyMgAPAgAKAAkJ+RVyMgAPAgABAAEJAACGVAAAAAAAAA==.',
Uj='Ujimas:BAABLgAECn8XAAMoAAcJlBFnWgDVAAAoAAYJ/BNnWgDVAAAHAAYJXQkCiwDFAAAAAA==.Ujong:BAAALgAECgcJDgABLgAECgcJMQACALIkAA==.',
Un='Unchartedd:BAAALgADCgEJAQAAAA==.',
Va='Vaenira:BAAALgADCgUJBgAAAA==.Vako:BAABLgAECn8UAAIUAAQJyRKiIgDiAAAUAAQJyRKiIgDiAAAAAA==.Valdara:BAAALgADCgkJEgAAAA==.Valemon:BAAALgAECgIJAgAAAA==.Vampireshade:BAABLgAECn8/AAIWAAkJ5hCuAACJAQAWAAkJ5hCuAACJAQAAAA==.Vanimao:BAABLgAECn81AAQEAAkJdQ+tPACxAQAEAAkJdQ+tPACxAQAFAAcJjwlbRQD3AAADAAcJrwzqLgDyAAAAAA==.Vankman:BAAALgADCgcJBwAAAA==.Vannaka:BAAALgADCgEJAQAAAA==.',
Vb='Vbull:BAAALgAECgEJAQAAAA==.',
Ve='Vedrolan:BAAALgADCgUJDgABLgAFFAQJEQAnACIhAA==.Velifya:BAAALgADCgMJAwAAAA==.Velindon:BAAALgADCgYJBgAAAA==.Velissari:BAABLgAECn85AAIOAAgJphvDAQAfAgAOAAgJphvDAQAfAgAAAA==.Velonar:BAAALgADCgEJAQAAAA==.Velouria:BAABLgAECn9SAAQDAAkJ2CJVAgAcAwADAAkJwCJVAgAcAwAFAAgJ6h8SDQDIAgAEAAIJ9QSXwABGAAAAAA==.Venatra:BAAALgAECgYJDwAAAA==.Verudora:BAAALgADCgcJBwAAAA==.Vexira:BAAALgADCgcJBwAAAA==.',
Vi='Violet:BAABLgAECn8gAAIbAAgJJBe/CwAdAgAbAAgJJBe/CwAdAgAAAA==.Violette:BAABLgAECn83AAIRAAkJLROHCACbAQARAAkJLROHCACbAQAAAA==.Visix:BAAALgAECgUJBgAAAA==.Vitt:BAAALgAECgEJAgAAAA==.',
Vo='Voidchacha:BAAALgADCgEJAQAAAA==.Voidlink:BAACLgAFFH8FAAImAAMJXhocEQDqAAAmAAMJXhocEQDqAAAuAAQKfy0AAiYACQmzFGcbAPMBACYACQmzFGcbAPMBAAAA.Voidmistress:BAABLgAECn8nAAICAAcJGRggcQCXAQACAAcJGRggcQCXAQAAAA==.Voidpup:BAABLgAECn8oAAIaAAcJYxwqPwDMAQAaAAcJYxwqPwDMAQAAAA==.Volgrimm:BAABLgAECn8bAAIXAAgJKwsYNAAvAQAXAAgJKwsYNAAvAQAAAA==.Volitaire:BAAALgADCgYJBgAAAA==.Volkân:BAAALgAECgQJBAAAAA==.Vonbek:BAAALgAECgMJAwAAAA==.',
Vy='Vynethan:BAAALgAECgEJAgAAAA==.',
['Vé']='Véngence:BAABLgAECn8YAAIVAAcJLRHggABiAQAVAAcJLRHggABiAQAAAA==.',
['Vê']='Vêx:BAAALgADCgYJBgAAAA==.',
Wa='Wabalabalosh:BAAALgADCgkJCQAAAA==.Wabgucci:BAAALgADCgUJBQAAAA==.Wabwum:BAAALgAECgMJAwAAAA==.Wackyrellek:BAAALgAECgQJCQAAAA==.Wakaekwondo:BAAALgAECgEJAQAAAA==.Wakarisma:BAAALgAECgEJAQAAAA==.Wakataclysm:BAAALgAECgMJAwAAAA==.Wanda:BAAALgAECgkJDQAAAA==.Wangao:BAABLgAFFH8IAAIXAAMJJAp9PgCtAAAXAAMJJAp9PgCtAAABLgAFFAQJEQAnACIhAA==.Warbluster:BAAALgADCgIJAgAAAA==.Warchylde:BAAALgADCgkJFgAAAA==.Warolderoy:BAACLgAFFH8FAAIcAAMJuBnHEADxAAAcAAMJuBnHEADxAAAuAAQKf0sAAhwACQmlJMEDACwDABwACQmlJMEDACwDAAAA.Warshy:BAAALgAECgQJBAAAAA==.',
We='Weedshaman:BAAALgAECgEJAwAAAA==.Weedwax:BAAALgAECgQJBAAAAA==.Weil:BAAALgADCgIJAgAAAA==.',
Wh='Whiinuss:BAABLgAECn8UAAIJAAcJlw25fwB7AQAJAAcJlw25fwB7AQAAAA==.Whytrabbit:BAAALgAECgIJAgAAAA==.',
Wi='Wigglesdeath:BAAALgAECgUJBQAAAA==.',
Wl='Wldeagle:BAAALgAECgQJBQAAAA==.',
Wo='Woker:BAAALgAECgcJEQABLgAFFAMJBQAUADkHAA==.Woodpig:BAABLgAECn8vAAQEAAkJ2SFfBgBSAwAEAAkJ2SFfBgBSAwADAAIJVBMfUQBrAAAFAAMJcAo0cQBlAAAAAA==.Woogie:BAAALgAECgQJCwAAAA==.',
Wr='Wrangle:BAAALgADCgEJAQAAAA==.',
Wy='Wyldshade:BAAALgADCgYJCAAAAA==.Wyrm:BAAALgAECgUJBQABLgAECgUJCgAGAAAAAA==.',
Xa='Xaladin:BAABLgAECn8dAAIOAAkJVgypHwB8AQAOAAkJVgypHwB8AQAAAA==.Xantheos:BAAALgAECgEJAgAAAA==.Xathas:BAAALgAECgQJBAAAAA==.',
Xe='Xenna:BAAALgAECgYJCgAAAA==.Xeq:BAAALgAECgcJEAAAAA==.',
Xi='Xiata:BAAALgAECgkJEwAAAA==.Xiu:BAAALgAECgUJBgAAAA==.',
Xr='Xrp:BAAALgADCgQJBQAAAA==.',
Xt='Xtragun:BAAALgAECgEJAQAAAA==.',
Ye='Yeoman:BAABLgAECn8qAAMcAAkJ6xIxNQB0AQAcAAkJ6xIxNQB0AQAZAAQJHwn4BwCRAAAAAA==.Yeos:BAAALgAECgQJBAABLgAECgkJKgAcAOsSAA==.',
Yg='Yggdralith:BAAALgAECgkJJAAAAQ==.',
Yi='Yiznusin:BAAALgAECgEJAgAAAA==.',
Ym='Yme:BAAALgAECgMJAwAAAA==.',
Yo='Yourdeath:BAAALgAECgkJBAAAAA==.',
Yu='Yunosmall:BAAALgADCgIJAgAAAA==.Yunosmart:BAAALgAECgYJCQAAAA==.',
Za='Zackoh:BAAALgAECgEJAQAAAA==.Zaen:BAACLgAFFH8ZAAIKAAQJdxX1GAAkAQAKAAQJdxX1GAAkAQAuAAQKfzcAAwoACQmdHykVAKYCAAoACQmdHykVAKYCAAEAAwnUC7NDAKYAAAAA.Zagreus:BAAALgADCgcJCAAAAA==.Zakikaz:BAAALgAECgQJBQAAAA==.Zakkah:BAAALgAECgEJAQABLgAFFAQJDAAIAFgkAA==.Zarkir:BAACLgAFFH8WAAMgAAQJixyRCQBWAQAgAAQJixyRCQBWAQAVAAMJmQwn7AB+AAAuAAQKfyYABCAACQmfJDECAPUCACAACQkqIjECAPUCABUABwnCIe1BAP0BABgABwmtF5oZAIcBAAEuAAQKBgkXAAIApyIA.Zarkìr:BAABLgAECn8XAAICAAYJpyKQZwAIAgACAAYJpyKQZwAIAgAAAA==.Zaues:BAAALgAECgMJBAAAAA==.',
Ze='Zelily:BAABLgAECn8XAAIRAAkJQQiVmgAMAQARAAkJQQiVmgAMAQAAAA==.Zenarri:BAAALgADCgYJBwAAAA==.Zenasdan:BAAALgADCgYJBgAAAA==.Zepha:BAAALgAECgcJDQAAAA==.Zerø:BAAALgAECgIJAgABLgAECgYJFwACAKciAA==.',
Zl='Zlyandien:BAAALgADCggJDwABLgAECgkJGwAmAFUYAA==.',
Zo='Zoomkin:BAAALgAFFAEJAQABLgAFFAMJAwAGAAAAAA==.Zornov:BAABLgAECn8jAAMnAAgJjx4zCwAVAgAnAAgJjx4zCwAVAgALAAMJJggPcgBuAAAAAA==.Zortt:BAAALgAECgEJAgAAAA==.',
Zu='Zulrich:BAAALgAECgUJBQAAAA==.',
Zv='Zvirax:BAAALgAECgUJAwAAAA==.',
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
