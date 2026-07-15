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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Paladin-Retribution','Paladin-Protection','DeathKnight-Frost','DeathKnight-Blood','Priest-Shadow','Priest-Holy','Paladin-Holy','Shaman-Restoration','Hunter-BeastMastery','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Hunter-Marksmanship','Warrior-Protection','Hunter-Survival','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Fury','Unknown-Unknown','Druid-Guardian','Warlock-Demonology','Evoker-Devastation','Monk-Brewmaster','Rogue-Subtlety','Warrior-Arms','Mage-Arcane','Rogue-Outlaw','Rogue-Assassination','Priest-Discipline',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=46,date='2026-07-12',data={Ab='Abyssara:BAAALgAECgcJEgAAAA==.',
Ac='Acebets:BAAALgAECgEJAQAAAA==.Acedk:BAACLgAFFH8GAAIBAAMJqR+dkQDoAAABAAMJqR+dkQDoAAAuAAQKfxoAAgEACQlPIZoLAD4DAAEACQlPIZoLAD4DAAAA.',
Ad='Adorie:BAAALgAECgIJAwAAAA==.Adun:BAAALgADCgQJBAAAAA==.',
Ae='Aelphe:BAACLgAFFH8GAAICAAMJwBUNDgDZAAACAAMJwBUNDgDZAAAuAAQKfx8ABAIACQmwIe0AAHwDAAIACQmwIe0AAHwDAAMAAQlGB2zTADEAAAQAAQkuAiKOAB8AAAAA.Aelusius:BAACLgAFFH8MAAIFAAMJsh9JBAALAQAFAAMJsh9JBAALAQAuAAQKfz8AAgUACQm2JFgBACsDAAUACQm2JFgBACsDAAAA.Aeón:BAAALgAECgkJEQAAAA==.',
Ag='Aggèn:BAABLgAECn8yAAMGAAkJXR+WGwCeAgAGAAkJEx+WGwCeAgAHAAYJnQ6hBgC9AAAAAA==.',
Aj='Aja:BAAALgAECgMJAwAAAA==.',
Ak='Akashá:BAAALgAECgEJAwAAAA==.Akriksdk:BAACLgAFFH8IAAQIAAUJMSTGAgCqAQAIAAQJjCPGAgCqAQABAAMJMCPgIQAvAQAJAAEJAADCLgAAAAAuAAQKfxYAAgEACQlyJjUBAIsDAAEACQlyJjUBAIsDAAAA.',
Al='Al:BAACLgAFFH8NAAMKAAQJGwo4IADyAAAKAAQJGwo4IADyAAALAAIJbQTeMABVAAAuAAQKfy0AAwoACAnbGEYdANsBAAoACAnbGEYdANsBAAsABwlpEUErAJsBAAAA.Aladrios:BAAALgAECgQJBwAAAA==.Alandarus:BAAALgAECgEJBAAAAA==.Alexanderath:BAAALgAECgUJCAAAAA==.Alexânderson:BAAALgAECgUJDQAAAA==.Alkaline:BAAALgADCggJCAAAAA==.Alkatractite:BAABLgAECn8nAAIGAAgJ4Bu5MQA5AgAGAAgJ4Bu5MQA5AgAAAA==.Allenwalker:BAAALgAECgUJCwAAAA==.Alucarde:BAEALgADCgYJBgABLgAECgkJIAAMAOwXAA==.Alzul:BAAALgADCgUJBQAAAA==.',
Am='Amanita:BAABLgAECn8eAAIDAAkJExUcJQAjAgADAAkJExUcJQAjAgAAAA==.Amasham:BAAALgAECgYJBgAAAA==.Amberness:BAAALgAFFAEJAQABLgAFFAMJBwANACseAA==.Ambersoul:BAAALgAECgEJAQAAAA==.Amira:BAAALgAECgcJDQABLgAFFAUJCQAOAMgeAA==.',
An='Angryanna:BAAALgAECgkJAwAAAA==.Anixa:BAAALgADCgkJCQAAAA==.Anyi:BAABLgAECn8rAAMPAAgJygtwQgApAQAPAAgJygtwQgApAQANAAQJEgL4swBiAAAAAA==.',
Ao='Aoi:BAABLgAECn8zAAMQAAkJKRIyIgCeAQAQAAkJKRIyIgCeAQARAAgJ5gttSABKAQAAAA==.',
Ar='Arrisia:BAABLgAECn8zAAMOAAkJuhB/TgC3AQAOAAkJuhB/TgC3AQASAAIJJwSeOAA9AAAAAA==.Artemissy:BAAALgADCgQJBAAAAA==.Arthedain:BAACLgAFFH8XAAITAAQJlyHnBQBiAQATAAQJlyHnBQBiAQAuAAQKfzMAAhMACQnSI30BAHIDABMACQnSI30BAHIDAAAA.Arthedaine:BAACLgAFFH8vAAIUAAcJHhkpAQDqAQAUAAcJHhkpAQDqAQAuAAQKfzEAAhQACQnKI24EAOcCABQACQnKI24EAOcCAAEuAAUUBAkXABMAlyEA.',
As='Asiea:BAAALgADCgQJBAAAAA==.Assano:BAABLgAECn8VAAMVAAgJWRA4AgBNAQAVAAgJkA84AgBNAQAWAAYJDw6xAwD7AAAAAA==.',
Au='Augmentmyass:BAAALgAFFAEJAQAAAA==.Aushahin:BAAALgAECggJDgABLgAECgkJKQAEAEYWAA==.Autumni:BAABLgAECn8fAAIOAAcJsRhpXgCLAQAOAAcJsRhpXgCLAQAAAA==.Auvry:BAABLgAECn8aAAMXAAcJVhkdEAA5AgAXAAcJVhkdEAA5AgAYAAIJqAlamQAqAAAAAA==.',
Ax='Axel:BAAALgADCgUJBQABLgAECgkJLAAZAN8JAA==.',
Ay='Aymus:BAABLgAECn8YAAQaAAcJ+QK6CAA9AAAbAAcJkgKZ6gBmAAAaAAIJyAO6CAA9AAAcAAMJzAFdggAbAAAAAA==.',
Az='Azliain:BAAALgAECgkJCAAAAA==.',
Ba='Bahamutfang:BAABLgAECn8nAAMGAAkJDwhbjABYAQAGAAkJDwhbjABYAQAHAAUJzATMOwBtAAAAAA==.Bakala:BAABLgAECn83AAMdAAgJEBUNLwCTAQAdAAgJTBMNLwCTAQATAAgJYw0/HgBCAQAAAA==.Bangbang:BAABLgAECn8qAAIOAAkJqBV8TAC8AQAOAAkJqBV8TAC8AQAAAA==.Barath:BAAALgAECgEJAQAAAA==.Bast:BAAALgADCgQJBAAAAA==.',
Be='Beeyou:BAAALgADCgEJAQAAAA==.Belegaer:BAABLgAECn8jAAIMAAkJhw+JKQDBAQAMAAkJhw+JKQDBAQAAAA==.Belenos:BAAALgADCggJHQABLgADCggJHQAeAAAAAA==.Bellamy:BAAALgAECgEJAQAAAA==.Beltway:BAAALgADCgcJCgAAAA==.Bendini:BAACLgAFFH8GAAISAAMJHwsEIACrAAASAAMJHwsEIACrAAAuAAQKfx4AAhIACQnSE3kqANgBABIACQnSE3kqANgBAAAA.Benmaverick:BAABLgAECn8dAAIbAAkJDg/2SQCoAQAbAAkJDg/2SQCoAQAAAA==.',
Bh='Bhe:BAABLgAECn8aAAIFAAgJ5wrcFwBKAQAFAAgJ5wrcFwBKAQAAAA==.',
Bi='Billymayzz:BAAALgADCgIJAgAAAA==.Billÿ:BAAALgAECgYJBwAAAA==.Bishop:BAABLgAECn9IAAILAAkJnBnJAQAyAgALAAkJnBnJAQAyAgAAAA==.',
Bl='Blackbird:BAAALgADCgYJCgAAAA==.',
Bo='Bobe:BAACLgAFFH8NAAMTAAMJDhM0DQCrAAATAAMJDhM0DQCrAAAdAAEJpQYxMQA7AAAuAAQKf0EAAxMACQlGHCgJAGQCABMACQlGHCgJAGQCAB0AAwmkBlCQAFEAAAAA.Bobedruid:BAAALgADCgQJAQAAAA==.Bordok:BAABLgAECn8iAAIIAAkJ2gvQDgCIAQAIAAkJ2gvQDgCIAQAAAA==.Borkuz:BAAALgAECgEJAQAAAA==.Bowfléx:BAAALgAECgEJAQAAAA==.',
Br='Brettdadad:BAAALgAECgIJAwAAAA==.Brighella:BAAALgADCgMJAwAAAA==.Bronxdr:BAAALgADCgQJBAAAAA==.Brows:BAAALgAECgMJBQAAAA==.Bruisewayne:BAAALgADCggJCAAAAA==.Brunco:BAABLgAECn8fAAMOAAkJ0h3XIABjAgAOAAkJ0h3XIABjAgASAAYJyROyFwD1AAAAAA==.Brxndxn:BAAALgADCgUJBQAAAA==.Brëw:BAAALgADCgUJBQAAAA==.Brütäl:BAAALgADCgIJAgAAAA==.',
Bu='Bubbleyo:BAAALgADCgcJCAAAAA==.Bustaheals:BAABLgAECn8lAAMLAAkJlhQIIQC6AQALAAcJ+hYIIQC6AQAKAAcJ9RDiMQBUAQAAAA==.',
Bw='Bwasamdi:BAAALgAFFAEJAQAAAA==.',
Ca='Calypsa:BAAALgADCgMJBAAAAA==.Cantpoly:BAAALgAECgYJBgAAAA==.Captplanet:BAABLgAECn8fAAQCAAkJVBbjDwC4AQACAAYJVxjjDwC4AQADAAgJdgk4YwALAQAEAAYJSgzoSQDkAAAAAA==.Cashartea:BAAALgAECgUJBQAAAA==.Cattleclysm:BAAALgADCgMJAwAAAA==.',
Ce='Ceindra:BAABLgAECn8pAAIFAAkJIyCtAwDEAgAFAAkJIyCtAwDEAgAAAA==.Celestria:BAAALgAECgEJAQAAAA==.Celiñ:BAACLgAFFH8HAAMHAAMJZxSgDwCJAAAHAAMJ7QqgDwCJAAAGAAIJ9xNBmgCFAAAuAAQKfygABAYACQmiIEgbAKACAAYACAmyIkgbAKACAAcABAnRE2o3AIIAAAwAAwnuBPZ2AGAAAAAA.Celîn:BAAALgAECgQJBAABLgAFFAMJBwAHAGcUAA==.Ceronia:BAAALgADCgEJAQAAAA==.',
Ch='Chainstormer:BAAALgAECgUJCQAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chibby:BAAALgAECgQJBAAAAA==.Chuladk:BAABLgAFFH8FAAIBAAMJnwiQuQC1AAABAAMJnwiQuQC1AAAAAA==.Chuyiacon:BAAALgAECgEJAQABLgAFFAMJBQABAJ8IAA==.',
Cl='Cleymour:BAAALgADCgcJDgAAAA==.Cløudstrife:BAAALgAECgEJAQAAAA==.',
Co='Colbalt:BAABLgAECn8UAAIKAAcJdAdKOgAfAQAKAAcJdAdKOgAfAQAAAA==.Cor:BAAALgAECgUJCAAAAA==.Corrosive:BAAALgAECgYJBQAAAA==.Cotilion:BAAALgADCgMJAwAAAA==.',
Cr='Creation:BAABLgAECn9GAAMCAAkJDiL5AwDJAgACAAgJQyP5AwDJAgAfAAkJUxw4CwAvAgABLgAFFAMJDAAFALIfAA==.Crunky:BAABLgAECn8wAAIRAAgJ9hWzIgAJAgARAAgJ9hWzIgAJAgAAAA==.Cruz:BAAALgADCgIJAgAAAA==.',
Cu='Cuddleybunni:BAAALgADCgMJAwAAAA==.Cuddlymethod:BAAALgAECgMJBgAAAA==.',
['Có']='Cól:BAABLgAECn8uAAIZAAkJNh5sMgCpAgAZAAkJNh5sMgCpAgAAAA==.',
Da='Daddydruid:BAAALgAECgEJAQAAAA==.Daddywoof:BAAALgAECgIJAgAAAA==.Dadmike:BAAALgAECgEJAQAAAA==.Daedilus:BAAALgADCgMJAwAAAA==.Dahealzrhere:BAAALgAECgYJCwAAAA==.Dalel:BAACLgAFFH8GAAIbAAYJngxzFgA3AQAbAAYJngxzFgA3AQAuAAQKfx4AAhsACQm4ILgSAK0CABsACQm4ILgSAK0CAAAA.Dameond:BAAALgAECgUJDwAAAA==.David:BAAALgAFFAIJBAABLgAFFAQJCgAUAFYaAA==.',
De='Deadisdead:BAAALgAECgYJDgAAAA==.Deadlyglow:BAAALgADCgcJDAABLgAECgYJCAAeAAAAAA==.Deathkratos:BAAALgADCgYJCQAAAA==.Demiurgos:BAACLgAFFH8HAAMNAAMJfSC6NQALAQANAAMJfSC6NQALAQAFAAMJbwNHEgCjAAAuAAQKfx4AAw0ABwltIc8XAIsCAA0ABwltIc8XAIsCAAUAAwl4EMIsAJMAAAAA.Demonicteli:BAABLgAECn8WAAIcAAkJlxmZEABdAgAcAAkJlxmZEABdAgAAAA==.Demonopii:BAAALgAECgQJCAAAAA==.Denzle:BAAALgAECggJDgAAAA==.Dermot:BAABLgAECn8wAAQVAAgJLiN0AwC6AgAVAAcJZCJ0AwC6AgAgAAYJ+iBseQBGAQAWAAIJCyYHIQBuAAAAAA==.',
Dh='Dhiying:BAAALgAECggJEAAAAA==.',
Di='Dippindots:BAABLgAECn8fAAMEAAgJLBFiLgBoAQAEAAgJLBFiLgBoAQADAAEJZQGJ7AAVAAAAAA==.Divakon:BAAALgADCgkJCgAAAA==.Dixmen:BAABLgAECn8gAAMGAAkJgRlNBwCvAQAGAAgJ4RtNBwCvAQAHAAEJ5Ah7EQAqAAAAAA==.',
Dk='Dkäri:BAAALgAECgYJDQAAAA==.',
Dl='Dlekri:BAAALgAECggJCAABLgAECgkJQgABAEAfAA==.',
Do='Dolemen:BAABLgAECn9EAAIGAAkJzw3FFgDZAAAGAAkJzw3FFgDZAAAAAA==.Domaon:BAABLgAECn8yAAIcAAkJayJhBAADAwAcAAkJayJhBAADAwAAAA==.Domshammy:BAAALgAECggJEwABLgAECgkJMgAcAGsiAA==.Doombunny:BAAALgAECgUJCQABLgAECgkJQAAOAOEXAA==.Doubt:BAABLgAECn8bAAIKAAgJWApJNgA9AQAKAAgJWApJNgA9AQAAAA==.Dozy:BAAALgAFFAEJAQAAAA==.',
Dr='Dranthrax:BAAALgAECgUJEAAAAA==.',
Du='Dullgrim:BAAALgADCgkJEQAAAA==.Dunigan:BAABLgAECn83AAMGAAgJThHlfgBxAQAGAAgJTxDlfgBxAQAHAAYJDg+1JgDgAAAAAA==.Dunigen:BAAALgAECgcJEQAAAA==.Dunstan:BAAALgAECgYJEAAAAA==.Durmet:BAAALgAECgUJBQAAAA==.Dustos:BAAALgADCgIJAgAAAA==.',
Eb='Ebeast:BAABLgAECn9CAAIUAAkJ/RnnDABWAgAUAAkJ/RnnDABWAgAAAA==.Ebingus:BAAALgADCgYJBgAAAA==.',
Ef='Efel:BAAALgAECgcJBwAAAA==.',
Ei='Eifaun:BAEALgAECgUJCQAAAA==.',
El='Elexidor:BAAALgAECgkJDAAAAA==.Elorrna:BAAALgADCgYJBgAAAA==.',
Em='Emberjoy:BAAALgADCgUJBQAAAA==.',
Er='Erathen:BAAALgADCgUJBQAAAA==.',
Ev='Evangelista:BAAALgAECgQJBgAAAA==.',
Ey='Eyeet:BAAALgAECgkJDgAAAA==.',
Fa='Facade:BAABLgAECn8mAAIJAAkJGxMHAwCNAQAJAAkJGxMHAwCNAQAAAA==.Facepalm:BAABLgAECn8fAAIdAAkJdxMxHwD1AQAdAAkJdxMxHwD1AQAAAA==.Faked:BAAALgADCgEJAQABLgAECgYJDAAeAAAAAA==.Falion:BAAALgAECgYJBgAAAA==.Fallensaints:BAAALgAECgYJCwAAAA==.Falshalad:BAABLgAECn8jAAMDAAcJFxzeAgDyAQADAAcJFxzeAgDyAQACAAQJyRO2LACzAAABLgAFFAMJDAAXAJIKAA==.Falyy:BAAALgAECgUJBQAAAA==.',
Fe='Fentak:BAABLgAECn8kAAIIAAkJTg6pAgA+AQAIAAkJTg6pAgA+AQAAAA==.',
Fi='Fierytotes:BAAALgAECgUJCgAAAA==.Finka:BAAALgAECgMJAwAAAA==.',
Fl='Flamedaddy:BAABLgAECn8kAAMNAAcJcxnRLAAFAgANAAcJcxnRLAAFAgAPAAEJgRwzkQBQAAAAAA==.',
Fo='Fog:BAAALgAECgEJAgAAAA==.Forbidenelf:BAAALgAECgEJAgAAAA==.Forgotmymeds:BAABLgAECn9QAAINAAkJ0BtOBADvAQANAAkJ0BtOBADvAQAAAA==.Foxmccloud:BAABLgAECn8vAAMNAAkJEhxcGwBwAgANAAkJEhxcGwBwAgAPAAQJlQTClwBHAAAAAA==.',
Fr='Fruitloop:BAABLgAECn8jAAIZAAkJMB94GADGAgAZAAkJMB94GADGAgAAAA==.',
Fu='Fuil:BAAALgAECgYJDQAAAA==.Furgaler:BAAALgAECgUJCQABLgAFFAYJBgAbAJ4MAA==.',
Fy='Fyznen:BAAALgAECgQJBAAAAA==.',
Ga='Garidrael:BAAALgAECgEJAQAAAA==.Garim:BAAALgADCgcJBwAAAA==.Gaviriard:BAAALgADCgMJAwAAAA==.',
Ge='Gebran:BAAALgAECgUJBQAAAA==.Gellywoo:BAABLgAECn9BAAIdAAkJWR9ZDQCYAgAdAAkJWR9ZDQCYAgAAAA==.Genmaitcha:BAAALgADCgEJAQAAAA==.',
Gh='Ghostofonyx:BAAALgADCgcJFQAAAA==.',
Gi='Girlypop:BAAALgAECgQJBgAAAA==.',
Go='Golaoth:BAABLgAECn8mAAMXAAkJtxdUBwCDAgAXAAkJtxdUBwCDAgAhAAEJCQFdLQAKAAAAAA==.Gooftoo:BAABLgAECn8UAAIDAAcJKB8QLwDwAQADAAcJKB8QLwDwAQAAAA==.',
Gr='Grawn:BAAALgAECgEJAQAAAA==.Greycie:BAAALgADCgkJEwABLgAECggJEgAeAAAAAA==.Greyfax:BAAALgADCgcJDQAAAA==.Greymoon:BAABLgAECn82AAIfAAkJlBggDwDzAQAfAAkJlBggDwDzAQAAAA==.Grimfu:BAAALgAECgYJDQABLgAECgkJIgAGAIEeAA==.',
Gu='Guigondk:BAAALgAFFAcJAQAAAA==.',
Gy='Gyre:BAABLgAECn8dAAIOAAcJ6hBfbABoAQAOAAcJ6hBfbABoAQAAAA==.',
Ha='Haezi:BAAALgAECggJDQABLgAECgkJHwAiAEQUAA==.Hairynips:BAAALgAECgEJAQAAAA==.Happyendings:BAABLgAFFH8GAAIgAAIJyw0WSQBVAAAgAAIJyw0WSQBVAAAAAA==.',
He='Helbafx:BAABLgAECn8YAAIgAAYJMASmFQCIAAAgAAYJMASmFQCIAAAAAA==.',
Hi='Hiroshì:BAAALgAECgEJAQAAAA==.',
Ho='Homewrecker:BAABLgAECn8dAAITAAkJ2hKhGgBkAQATAAkJ2hKhGgBkAQAAAA==.',
Hu='Hunnee:BAAALgADCgkJFAAAAA==.Huské:BAAALgAECgcJDQAAAA==.',
Ic='Icelace:BAAALgAECgEJAQAAAA==.Icemàn:BAABLgAECn8pAAIjAAgJvRBrAgCeAQAjAAgJvRBrAgCeAQAAAA==.',
If='Ifearnobeer:BAABLgAECn81AAMPAAkJggrCOgBLAQAPAAkJggrCOgBLAQANAAIJZwiYxwBGAAAAAA==.',
Ii='Iifelike:BAAALgAECgUJBQABLgAECgkJFQAHAN4PAA==.',
In='Inters:BAAALgAECgUJDgAAAA==.',
Ir='Ironspark:BAAALgAECgcJEgAAAA==.',
Is='Isabel:BAACLgAFFH8QAAIDAAQJTwucOQDHAAADAAQJTwucOQDHAAAuAAQKfxUAAgMACAmEGC0kACoCAAMACAmEGC0kACoCAAAA.Isaetr:BAAALgAECggJDwAAAA==.',
Ja='Jackôdaniels:BAAALgADCgkJDgAAAA==.Jadedrienne:BAAALgADCgUJBQAAAA==.Jadus:BAAALgAECgMJAwAAAA==.Jaiantobea:BAACLgAFFH8HAAINAAYJKhbgCACUAQANAAYJKhbgCACUAQAuAAQKfzEAAg0ACQnfHbQIACYDAA0ACQnfHbQIACYDAAAA.Jake:BAAALgAECgIJAgAAAA==.Jakulista:BAAALgADCgcJFQAAAA==.Jarlaxl:BAAALgADCgYJBgAAAA==.Jashugan:BAAALgADCgQJBAAAAA==.Jawn:BAABLgAECn8iAAIQAAkJ4g4UJACSAQAQAAkJ4g4UJACSAQAAAA==.Jaycie:BAAALgAECggJEgAAAA==.',
Je='Jessuss:BAABLgAECn8xAAIGAAkJdxUUBwC0AQAGAAkJdxUUBwC0AQAAAA==.Jettin:BAAALgADCgIJAgAAAA==.',
Jh='Jha:BAAALgAECgEJAwAAAA==.',
Ju='Jude:BAAALgAECgUJCgAAAA==.Juggernàut:BAAALgAECgYJEAAAAA==.Julïeth:BAAALgAECgEJAQAAAA==.Junipermoon:BAAALgADCggJHQAAAA==.',
Ka='Kajas:BAAALgAECgMJAwAAAA==.Kalahandra:BAACLgAFFH8FAAIDAAMJqQOaTwCDAAADAAMJqQOaTwCDAAAuAAQKfyoAAgMACQnTEIs1AMQBAAMACQnTEIs1AMQBAAAA.Kalebeesd:BAABLgAECn8vAAIbAAkJ5hyeIgBGAgAbAAkJ5hyeIgBGAgAAAA==.Karthdh:BAAALgADCgcJDgABLgADCggJCAAeAAAAAA==.Kasey:BAAALgAECgEJAQAAAA==.Katithianna:BAAALgADCgQJAwAAAA==.Katotan:BAABLgAECn8jAAIDAAgJKhcPBgA2AQADAAgJKhcPBgA2AQAAAA==.Kawk:BAABLgAECn8uAAIHAAkJWx+LBAC7AgAHAAkJWx+LBAC7AgAAAA==.Kazatreshan:BAAALgADCgcJDgAAAA==.Kazragor:BAACLgAFFH8NAAIPAAQJbCKCFAB7AQAPAAQJbCKCFAB7AQAuAAQKfyUAAg8ACAn5I/4OALcCAA8ACAn5I/4OALcCAAAA.',
Ke='Kealestra:BAAALgADCgkJCwAAAA==.Kebob:BAABLgAECn8VAAIHAAkJ3g8fGABdAQAHAAkJ3g8fGABdAQAAAA==.Kenziedadght:BAAALgAECgIJBQAAAA==.Keyboärd:BAABLgAECn8hAAITAAgJ5BwhDgAJAgATAAgJ5BwhDgAJAgAAAA==.',
Ki='Kilo:BAAALgADCgEJAwAAAA==.Kippo:BAECLgAFFH8IAAIZAAUJJgURMwDRAAAZAAUJJgURMwDRAAAuAAQKfyMAAhkACAmWF0BKAFgCABkACAmWF0BKAFgCAAEuAAUUBwkVAAEAthEA.Kittylover:BAAALgAECgYJEAAAAA==.',
Kl='Klazarth:BAACLgAFFH8HAAIKAAMJMReHIgDgAAAKAAMJMReHIgDgAAAuAAQKfx4AAgoACQmqHowNAKoCAAoACQmqHowNAKoCAAAA.',
Ko='Kombat:BAABLgAECn8mAAMdAAkJQh0FFQBHAgAdAAkJQh0FFQBHAgAkAAEJLhh3DgBJAAAAAA==.Korllan:BAABLgAECn8aAAIBAAYJnwskEwDaAAABAAYJnwskEwDaAAAAAA==.Kossnen:BAABLgAECn8XAAIgAAkJhR3XHgBsAgAgAAkJhR3XHgBsAgAAAA==.',
Kr='Krelivus:BAAALgAECgYJCwAAAA==.',
Ku='Kuda:BAABLgAECn8tAAIZAAkJDxQlQwASAgAZAAkJDxQlQwASAgAAAA==.Kuridis:BAAALgAECgEJAQAAAA==.',
Kw='Kwanu:BAABLgAECn8eAAIRAAgJFw1HRABbAQARAAgJFw1HRABbAQAAAA==.',
['Kó']='Kóñä:BAAALgADCgkJDAABLgAECgkJEQAeAAAAAA==.',
La='Lamue:BAAALgAECgIJAgAAAA==.Lantern:BAAALgADCgYJCwAAAA==.Larke:BAAALgAECgUJBwAAAA==.Lasa:BAAALgAECgcJCgABLgAECgcJEAAeAAAAAA==.Lasloo:BAABLgAECn8eAAIGAAYJgBCwkQBPAQAGAAYJgBCwkQBPAQAAAA==.Laylani:BAABLgAECn80AAIHAAkJgRcLAQAyAgAHAAkJgRcLAQAyAgAAAA==.Layllis:BAAALgADCgQJBgAAAA==.',
Le='Legiondary:BAABLgAECn8cAAIbAAkJ8Rc7LgBEAgAbAAkJ8Rc7LgBEAgAAAA==.Lesabor:BAAALgADCgYJBgAAAA==.',
Li='Licknstick:BAAALgAECgUJCAAAAA==.Lir:BAAALgADCgIJAwAAAA==.Lisan:BAABLgAECn8hAAIlAAkJ4RYjAgBMAgAlAAkJ4RYjAgBMAgAAAA==.Lisanalgaib:BAAALgAECgEJAgAAAA==.Littledicey:BAAALgADCgcJCwAAAA==.',
Lo='Lobsterhands:BAAALgAECgEJAQAAAA==.Lokin:BAAALgADCgIJAgAAAA==.Lothan:BAAALgADCgkJCQABLgAECgkJKQAEAEYWAA==.Lotuss:BAABLgAECn8dAAMRAAYJdhmUNwCVAQARAAYJdhmUNwCVAQAQAAEJNgPYwAAXAAABLgAFFAMJDQAPAPQJAA==.',
Lu='Lucien:BAAALgAECgYJEQAAAA==.Luciä:BAABLgAECn8oAAIJAAkJBhKxFQC+AQAJAAkJBhKxFQC+AQAAAA==.Lucymoon:BAAALgAECgYJBQAAAA==.',
Ly='Lynex:BAAALgAECgQJBwAAAA==.',
Ma='Machoman:BAAALgAECgQJBAAAAA==.Madness:BAAALgAECgUJBwAAAA==.Maerion:BAAALgADCgYJBgAAAA==.Magdeth:BAAALgAECgMJBQAAAA==.Magiann:BAAALgADCgEJAQAAAA==.Maiama:BAAALgAECgYJBwAAAA==.Marabelle:BAABLgAECn8cAAIEAAkJCgreMwBJAQAEAAkJCgreMwBJAQAAAA==.Massack:BAABLgAECn8jAAIiAAkJ9xeiEAA3AgAiAAkJ9xeiEAA3AgAAAA==.Mastik:BAAALgAECgEJAQAAAA==.Maximusblood:BAAALgADCgIJAgAAAA==.',
Mc='Mcknight:BAAALgAECgYJBgAAAA==.',
Me='Merex:BAAALgADCgEJAQAAAA==.Mero:BAAALgAECgYJBgAAAA==.Mew:BAAALgADCgEJAQABLgAECggJHwAMAJ0XAA==.',
Mi='Midgetmàniàc:BAAALgAECgMJBAAAAA==.Mikebeard:BAAALgAECgIJBQAAAA==.Mikereport:BAAALgAECgIJAgAAAA==.Misfire:BAAALgAECggJCgABLgAECgkJHgADABMVAA==.',
Mo='Moktar:BAAALgAECgYJBwAAAA==.Moobear:BAAALgADCgQJCwAAAA==.',
Mu='Muldoinit:BAABLgAECn8jAAIQAAkJYhibEwAfAgAQAAkJYhibEwAfAgAAAA==.',
My='Myroslava:BAAALgAECgMJAwAAAA==.Mysticalbeef:BAAALgAECgEJAQAAAA==.Mystrall:BAAALgAECgYJBgAAAA==.',
['Më']='Mërikh:BAAALgADCggJEQABLgAECgUJCwAeAAAAAA==.',
Na='Nadorian:BAAALgAECgEJAQAAAA==.',
Ne='Neb:BAABLgAECn8rAAIMAAgJ/SM1BgAqAwAMAAgJ/SM1BgAqAwAAAA==.Nehemia:BAAALgAECgYJEQAAAA==.Nerilestis:BAAALgAECgEJAQAAAA==.Netherrogue:BAACLgAFFH8NAAMjAAQJiRwYFQBiAQAjAAQJIRsYFQBiAQAmAAMJoRfsCADsAAAuAAQKfyMABCYACQntHe4GANkBACYABglmGu4GANkBACcABQnNHSkJALABACMABgkgFfYmAF8BAAAA.',
Ni='Nicage:BAAALgAECgQJBAABLgAFFAQJEAAZAOMZAA==.Nightdreams:BAAALgADCgcJCQAAAA==.',
Nu='Nuke:BAAALgAECgIJAgABLgAFFAQJBwAEAPUGAA==.',
Ny='Nytelytë:BAAALgAECgYJCQABLgAFFAMJBwAgAG8TAA==.Nytemayer:BAACLgAFFH8HAAIgAAMJbxM7eQDQAAAgAAMJbxM7eQDQAAAuAAQKfysABCAACQmIIGMaAIYCACAACQl+H2MaAIYCABUAAwmYH4szAOkAABYAAQkAAC4pAE0AAAAA.',
['Nö']='Nöx:BAAALgAECgYJBgAAAA==.',
Ob='Obmakare:BAABLgAECn82AAICAAkJCRbsDgDGAQACAAkJCRbsDgDGAQAAAA==.Obonhigh:BAAALgAECgUJBQAAAA==.Oboñ:BAABLgAECn8lAAMWAAgJzw8RDQCLAQAWAAgJzw8RDQCLAQAgAAEJYwPyYgEeAAAAAA==.Obsfuyung:BAABLgAECn83AAIQAAkJuhPoIACmAQAQAAkJuhPoIACmAQAAAA==.',
On='Onkelos:BAAALgAECgEJAwAAAA==.',
Oo='Oopsiez:BAAALgAECgUJBQAAAA==.',
Or='Orcc:BAAALgAECgEJAgAAAA==.',
Pa='Paley:BAAALgAECgYJDQAAAA==.Palpatine:BAAALgAECgIJAgAAAA==.',
Pe='Peopleperson:BAAALgADCgQJAQAAAA==.Performance:BAAALgAECgcJEAAAAA==.Peterturbo:BAAALgAECgQJBAABLgADCgcJDQAeAAAAAA==.',
Pi='Piezoori:BAAALgADCgcJBgAAAA==.Pinji:BAAALgAECgIJAgAAAA==.Pinkky:BAAALgADCgkJCQAAAA==.Pinkypoo:BAABLgAECn8rAAMBAAkJmxbXPAAOAgABAAkJiBPXPAAOAgAJAAYJvBixIwAjAQAAAA==.',
Pl='Plato:BAABLgAECn8vAAQMAAkJdxtDFwBQAgAMAAgJrBtDFwBQAgAGAAIJ9wiwWgFXAAAHAAEJAABOFQAAAAAAAA==.',
Po='Poiet:BAAALgAECgEJAgAAAA==.Poîsonivy:BAABLgAECn8pAAMVAAkJChVkBgD7AQAVAAkJChVkBgD7AQAgAAEJNgFtaQENAAAAAA==.',
Ps='Psyche:BAAALgADCgkJDgAAAA==.Psyrine:BAAALgAECgcJEwAAAA==.',
Py='Pyrokast:BAAALgAECgUJBQAAAA==.Pyrokos:BAACLgAFFH8GAAIZAAMJUBlwfwDYAAAZAAMJUBlwfwDYAAAuAAQKfyEAAhkACAnsIDliABUCABkACAnsIDliABUCAAAA.Pyrö:BAAALgAECgkJCQAAAA==.',
Qu='Qu:BAABLgAECn84AAMkAAkJkiFvBgBlAgAkAAkJkiFvBgBlAgAdAAIJTQowlQBrAAAAAA==.Quellia:BAACLgAFFH8YAAIMAAYJyRjtFgBvAQAMAAYJyRjtFgBvAQAuAAQKfyIAAgwACQn8HdMMALMCAAwACQn8HdMMALMCAAAA.',
Ra='Rangel:BAABLgAECn8YAAIdAAgJ7BArQQBAAQAdAAgJ7BArQQBAAQAAAA==.Rattlesnake:BAAALgADCgYJBgAAAA==.Razziels:BAAALgAECgYJBwAAAA==.',
Re='Redacted:BAAALgADCgMJAwAAAA==.Renägäde:BAAALgAECgYJDwAAAA==.Rexulti:BAAALgAECgEJAQAAAA==.',
Ri='Ricodadawg:BAAALgADCgEJAQAAAA==.Rizen:BAAALgAECgQJBAAAAA==.',
Ro='Roija:BAACLgAFFH8QAAIZAAQJ4xlYVwAuAQAZAAQJ4xlYVwAuAQAuAAQKfygAAhkACQlDJRIKACkDABkACQlDJRIKACkDAAAA.Roshak:BAAALgADCgYJCQAAAA==.',
Ru='Runningbearr:BAAALgAECgMJAwAAAA==.Runningmage:BAAALgADCgcJDAAAAA==.Rurahk:BAACLgAFFH8ZAAIGAAcJtRBaJgBwAQAGAAcJtRBaJgBwAQAuAAQKfzAAAgYACQkJIqIVAOgCAAYACQkJIqIVAOgCAAAA.',
['Rõ']='Rõbb:BAACLgAFFH8HAAIGAAMJVR6mXAD3AAAGAAMJVR6mXAD3AAAuAAQKfywAAgYACQkGIpsOABkDAAYACQkGIpsOABkDAAAA.',
Sa='Sabaak:BAABLgAECn8tAAIGAAkJsSEwGwChAgAGAAkJsSEwGwChAgAAAA==.Sacerdote:BAAALgADCgUJBQAAAA==.Saeriin:BAABLgAECn9DAAIgAAkJJRLQBwBMAQAgAAkJJRLQBwBMAQAAAA==.Saintsnyder:BAABLgAECn8dAAIGAAYJ5xMKpAAxAQAGAAYJ5xMKpAAxAQAAAA==.Saithis:BAABLgAECn8UAAIDAAYJmBBIbgDpAAADAAYJmBBIbgDpAAAAAA==.Saltycrank:BAAALgADCgYJBgAAAA==.Sandew:BAAALgAECgcJEAAAAA==.Sanorasong:BAEBLgAECn8gAAMMAAkJ7Bd3FwBOAgAMAAkJ7Bd3FwBOAgAGAAUJPhQGxwD/AAAAAA==.Saphaa:BAAALgADCgMJAwAAAA==.Sardine:BAAALgAECgcJDAAAAA==.Sarylin:BAABLgAECn8YAAMOAAkJbxoGHgBxAgAOAAkJbxoGHgBxAgASAAQJdQhqYwCzAAAAAA==.Satanshealer:BAAALgADCgYJCQAAAA==.Satansshadow:BAAALgAECgIJAgAAAA==.Sathpriest:BAAALgAECgIJAgAAAA==.Satsuki:BAAALgAECgYJCgAAAA==.',
Sc='Schio:BAABLgAECn82AAIVAAkJLxdjBwDfAQAVAAkJLxdjBwDfAQAAAA==.',
Se='Sean:BAAALgADCgYJBgAAAA==.Seananagíns:BAABLgAFFH8GAAIGAAMJ+wIGOACUAAAGAAMJ+wIGOACUAAAAAA==.Sections:BAAALgADCgkJHAAAAA==.Semilla:BAAALgADCgEJAQAAAA==.Severussnape:BAABLgAECn8jAAMgAAkJqQneYgB5AQAgAAkJnAneYgB5AQAVAAEJ6gpVQwAnAAAAAA==.',
Sh='Shambs:BAACLgAFFH8HAAINAAMJKx4WPwDoAAANAAMJKx4WPwDoAAAuAAQKfxsAAg0ACQnPHikGAA8DAA0ACQnPHikGAA8DAAAA.Shamrorag:BAABLgAECn8bAAMPAAgJLgrSRAAgAQAPAAgJLgrSRAAgAQAFAAMJ2wO2NQBZAAAAAA==.Shehealz:BAAALgAECgIJBAAAAA==.Shinron:BAAALgAECgIJAgAAAA==.Shökan:BAAALgAECgQJBwAAAA==.',
Si='Sighah:BAAALgAECgkJEgAAAA==.Simlockdr:BAAALgADCgYJBgAAAA==.Sinensis:BAABLgAECn8bAAMnAAkJpRWtBQAaAgAnAAkJTBWtBQAaAgAjAAEJnBvzDgBQAAAAAA==.Singood:BAAALgAECgcJBwAAAA==.Sinnecro:BAABLgAECn8aAAIBAAkJ4h5nIADAAgABAAkJ4h5nIADAAgAAAA==.Sinshift:BAAALgADCgUJBQAAAA==.Sinstab:BAAALgAECggJCAAAAA==.',
Sk='Skadoosh:BAAALgAECgUJDQABLgAFFAYJBgAbAJ4MAA==.Skarletbolt:BAAALgAECgUJBQAAAA==.Skarletflame:BAABLgAECn8bAAIcAAkJnRg/DQBRAgAcAAkJnRg/DQBRAgAAAA==.Skinalittleb:BAAALgAECgEJAQAAAA==.',
Sl='Slather:BAABLgAECn8aAAIXAAgJcBAKGADVAQAXAAgJcBAKGADVAQAAAA==.Slaycie:BAABLgAECn8kAAIZAAkJ6hBUdgCNAQAZAAkJ6hBUdgCNAQAAAA==.Slayerdude:BAAALgAECgQJBAAAAA==.Slofinger:BAAALgADCgYJCgAAAA==.',
Sn='Sneeb:BAAALgAECgEJAQAAAA==.Snugglebus:BAABLgAECn8jAAIaAAgJhgd2AwDXAAAaAAgJhgd2AwDXAAAAAA==.',
So='Songli:BAEALgADCgEJAQABLgAECgkJIAAMAOwXAA==.Sorne:BAEBLgAFFH8GAAINAAUJbRMyLgApAQANAAUJbRMyLgApAQABLgAFFAQJEQANAOUjAA==.',
Sp='Spaghett:BAABLgAECn8fAAMiAAkJRBRLJwB2AQAiAAkJphFLJwB2AQAQAAYJJhOlRADtAAAAAA==.Springtotem:BAABLgAECn8pAAIEAAkJRhYGAgAAAgAEAAkJRhYGAgAAAgAAAA==.',
St='Stachel:BAAALgAECgUJBwAAAA==.Stanger:BAABLgAECn8mAAINAAkJPx7xCQAWAwANAAkJPx7xCQAWAwAAAA==.Storaxota:BAABLgAFFH8EAAIBAAMJTR74CQARAgABAAMJTR74CQARAgAAAA==.Stormdk:BAAALgADCgcJCQAAAA==.',
Su='Sumsingwong:BAAALgAECgEJAQAAAA==.Superneo:BAAALgAECgYJBgABLgAFFAMJCgAEAOciAA==.Suvion:BAAALgAECgcJEwABLgAFFAMJDQAPAPQJAA==.',
Sy='Sylinial:BAAALgAECgEJAQAAAA==.Sylvanis:BAAALgAECgUJBwAAAA==.Syrden:BAABLgAECn8WAAIDAAkJ6AvaQACOAQADAAkJ6AvaQACOAQAAAA==.',
Sz='Szadèk:BAAALgAECgYJBwAAAA==.',
['Sÿ']='Sÿphallus:BAABLgAECn8UAAIcAAgJshSyIQBrAQAcAAgJshSyIQBrAQAAAA==.',
Ta='Tael:BAABLgAECn8tAAIdAAkJzR+RCwCvAgAdAAkJzR+RCwCvAgAAAA==.Tagreth:BAAALgADCgQJBAAAAA==.Tangylizard:BAACLgAFFH8ZAAIoAAQJKBOhJgAVAQAoAAQJKBOhJgAVAQAuAAQKfy8ABCgACAliG1UTAEYCACgACAliG1UTAEYCAAsAAQkFFq57ADoAAAoAAQkZDAeOACwAAAAA.Tattoospyder:BAABLgAECn8aAAIDAAcJTwi4dwDPAAADAAcJTwi4dwDPAAAAAA==.Tatyanafour:BAAALgADCgIJAQAAAA==.Tatyanathirt:BAAALgADCgYJBgAAAA==.',
Te='Terrenn:BAAALgADCggJCAAAAA==.Tessla:BAACLgAFFH8NAAIPAAMJ9AkDGQCuAAAPAAMJ9AkDGQCuAAAuAAQKf04AAw8ACQlEHZYNAI8CAA8ACQlEHZYNAI8CAA0AAgm+CHnKAEMAAAAA.Tetragram:BAABLgAECn8fAAMQAAgJdhnvAQDSAQAQAAYJux/vAQDSAQAiAAgJdg94AgBmAQABLgAFFAMJDAAFALIfAA==.',
Th='Thafrggnpope:BAAALgADCgEJAQAAAA==.Thelarï:BAABLgAECn8jAAIOAAkJRgr4VQCiAQAOAAkJRgr4VQCiAQAAAA==.Thellany:BAAALgAECgEJAQAAAA==.Theshiznitz:BAAALgAECgQJBAAAAA==.Thors:BAABLgAECn8iAAIGAAcJgR4ACQCEAQAGAAcJgR4ACQCEAQAAAA==.Thundertoes:BAABLgAECn8jAAMNAAkJexylDgDeAgANAAkJexylDgDeAgAFAAYJChJzHwD+AAAAAA==.Thÿsucc:BAAALgADCgcJBwAAAA==.',
Ti='Tia:BAAALgAECgEJAQAAAA==.Timmy:BAAALgAECgMJCAABLgAECgkJAgAeAAAAAA==.',
To='Tobykick:BAAALgAECgEJAQAAAA==.Tommychong:BAAALgAECgIJAgAAAA==.Tonik:BAABLgAECn8qAAMNAAcJ2RQIPwCyAQANAAcJ2RQIPwCyAQAPAAcJChAaQQAwAQAAAA==.Torgoth:BAABLgAECn8pAAIFAAkJpRTkCQAeAgAFAAkJpRTkCQAeAgAAAA==.Toshido:BAABLgAECn8WAAIOAAYJVxH9oAAAAQAOAAYJVxH9oAAAAQAAAA==.',
Tr='Traetor:BAABLgAECn8kAAIEAAkJDib2AAB7AwAEAAkJDib2AAB7AwAAAA==.Trakker:BAAALgADCgQJBAAAAA==.Trevize:BAABLgAECn8YAAIGAAYJ3Aec5wDUAAAGAAYJ3Aec5wDUAAAAAA==.',
Tt='Ttelloc:BAAALgADCgIJAgAAAA==.',
Tu='Tusiny:BAAALgAECgEJAQAAAA==.',
Ub='Ubully:BAAALgAECgEJAQAAAA==.',
Ul='Ultane:BAABLgAECn8lAAINAAgJrA4KRwCSAQANAAgJrA4KRwCSAQAAAA==.',
Un='Unreal:BAAALgADCgQJBAAAAA==.',
Va='Vaera:BAAALgAECgEJAQAAAA==.Valastae:BAABLgAECn8ZAAIOAAgJYQxSaQBwAQAOAAgJYQxSaQBwAQAAAA==.Valiantaine:BAABLgAECn8wAAMGAAkJXiFzKgB6AgAGAAkJXiFzKgB6AgAMAAkJgg2xPQCCAQABLgAFFAQJGAAbANAcAA==.Valiantaint:BAACLgAFFH8YAAIbAAQJ0Bx8NQBPAQAbAAQJ0Bx8NQBPAQAuAAQKfzAAAhsACQk/HtYVAJUCABsACQk/HtYVAJUCAAAA.Valiantrain:BAAALgAECgEJAgABLgAFFAQJGAAbANAcAA==.Valyulon:BAAALgADCgMJAwABLgAFFAQJGAAbANAcAA==.Vanjin:BAAALgADCgUJBQAAAA==.',
Ve='Vecna:BAAALgAECgYJCAAAAA==.Velherun:BAABLgAECn8dAAIGAAkJYh/zFADFAgAGAAkJYh/zFADFAgAAAA==.Vendeldh:BAABLgAECn8sAAIbAAkJuCPUEgDpAgAbAAkJuCPUEgDpAgAAAA==.Veni:BAAALgAECgYJBgABLgAECgkJOAAkAJIhAA==.Vexxaa:BAABLgAECn8mAAIOAAkJUhFVOgD1AQAOAAkJUhFVOgD1AQAAAA==.',
Vi='Vincentio:BAAALgAECgEJAQAAAA==.Virajr:BAABLgAECn8oAAMjAAgJ0RUAFgDvAQAjAAgJ0RUAFgDvAQAmAAEJvAQAKgAgAAAAAA==.Vishus:BAAALgADCgUJBQAAAA==.Visiôn:BAABLgAECn8bAAIdAAkJ8wcAQQBBAQAdAAkJ8wcAQQBBAQAAAA==.Vissiction:BAABLgAECn8ZAAIbAAkJvxZiLQASAgAbAAkJvxZiLQASAgAAAA==.Vistine:BAACLgAFFH8KAAIHAAMJ0Qx7BgCIAAAHAAMJ0Qx7BgCIAAAuAAQKf1EAAgcACQleEaYCAHYBAAcACQleEaYCAHYBAAEuAAUUAwkNAA8A9AkA.Vitez:BAABLgAECn8WAAMVAAkJrAaAHQC8AAAVAAgJFAeAHQC8AAAgAAIJRAPjGgFNAAAAAA==.',
Vo='Voidscar:BAAALgADCgcJBwAAAA==.',
Wa='Warhurts:BAAALgAECgMJAwAAAA==.Waterbloom:BAAALgADCgMJAwAAAA==.',
We='Weave:BAABLgAECn8iAAIZAAcJUgyKqQAsAQAZAAcJUgyKqQAsAQAAAA==.Wendy:BAABLgAECn8pAAINAAgJ1RiONwDSAQANAAgJ1RiONwDSAQABLgAECgkJHgADABMVAA==.',
Wi='Win:BAACLgAFFH8HAAMEAAQJ9QbBLQDRAAAEAAQJ9QbBLQDRAAADAAEJWQxdLAAwAAAuAAQKfywAAwMABwnjGlolACICAAMABwnjGlolACICAAQABgkMH9cDAHkBAAAA.Winkster:BAACLgAFFH8MAAIGAAUJWRySOQA5AQAGAAUJWRySOQA5AQAuAAQKfzAAAgYACQn4JIEKABMDAAYACQn4JIEKABMDAAAA.',
Xa='Xanadu:BAACLgAFFH8IAAIoAAIJkxMPHACHAAAoAAIJkxMPHACHAAAuAAQKfzoAAigACQl1H8IGABIDACgACQl1H8IGABIDAAAA.Xarinia:BAACLgAFFH8FAAIYAAIJ8geRJABzAAAYAAIJ8geRJABzAAAuAAQKfy0ABBgACQn5EgMeAOcBABgACQn5EgMeAOcBABcABQnjB5QxAOMAACEAAQmQCusGACsAAAAA.',
Xb='Xbear:BAACLgAFFH8GAAIfAAYJSxInBgAbAQAfAAYJSxInBgAbAQAuAAQKfyYAAh8ACQm2HOoHAHICAB8ACQm2HOoHAHICAAEuAAUUBgkVACMAKBcA.',
Xd='Xdynasty:BAACLgAFFH8VAAIjAAYJKBeHEACQAQAjAAYJKBeHEACQAQAuAAQKfycAAyMACQkCJCwMANUCACMACQn/IywMANUCACcABgnDG+UNADwBAAAA.',
Xo='Xo:BAABLgAECn86AAQgAAkJmhmXJgBDAgAgAAkJLxiXJgBDAgAVAAUJGBR5JQAxAQAWAAIJVgtDMAA9AAABLgAFFAQJBwAEAPUGAA==.',
Xy='Xyfarion:BAAALgADCgYJBgAAAA==.Xyril:BAAALgAECgEJAQAAAA==.',
Ya='Yaasnah:BAAALgADCggJCAAAAA==.Yavramor:BAABLgAFFH8FAAIZAAEJBg6IXwBCAAAZAAEJBg6IXwBCAAABLgAFFAcJGQAGALUQAA==.',
Za='Zabazz:BAACLgAFFH8JAAINAAMJAhF+KwB8AAANAAMJAhF+KwB8AAAuAAQKfykAAw0ACQnOEDQ8AL4BAA0ACQnOEDQ8AL4BAA8ABAnJCB+EAGgAAAAA.Zabenir:BAABLgAECn8iAAIKAAkJ7hwuCwCdAgAKAAkJ7hwuCwCdAgAAAA==.Zané:BAAALgAECgEJAgAAAA==.Zapan:BAAALgADCgUJBQAAAA==.',
Ze='Zeverai:BAAALgADCgkJCgAAAA==.',
Zi='Zinic:BAAALgADCgQJAQAAAA==.Ziria:BAAALgADCgQJCwAAAA==.',
Zo='Zonni:BAAALgADCgYJBgAAAA==.Zorusii:BAAALgAECgQJBQABLgAFFAYJBgAbAJ4MAA==.',
['Âi']='Âinzooalgown:BAAALgAECgIJAgAAAA==.',
['Ðe']='Ðexter:BAABLgAECn8ZAAIGAAYJJQn74QDbAAAGAAYJJQn74QDbAAAAAA==.',
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
