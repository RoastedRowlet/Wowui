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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Paladin-Retribution','Paladin-Protection','Priest-Shadow','Priest-Holy','Paladin-Holy','Shaman-Restoration','Warlock-Demonology','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Protection','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Fury','Unknown-Unknown','DeathKnight-Frost','Druid-Guardian','Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Evoker-Devastation','Monk-Brewmaster','Rogue-Subtlety','Warrior-Arms','Mage-Arcane','Rogue-Outlaw','Rogue-Assassination','Priest-Discipline',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abyssara:BAAALgAECgcJEgAAAA==.',
Ac='Acebets:BAAALgAECgEJAQAAAA==.Acedk:BAACLgAFFH8GAAIBAAMJqR+dkQDoAAABAAMJqR+dkQDoAAAuAAQKfxoAAgEACQlPIZoLAD4DAAEACQlPIZoLAD4DAAAA.',
Ad='Adorie:BAAALgAECgIJAwAAAA==.Adun:BAAALgADCgQJBAAAAA==.',
Ae='Aelphe:BAACLgAFFH8GAAICAAMJwBUNDgDZAAACAAMJwBUNDgDZAAAuAAQKfx8ABAIACQmwIe0AAHwDAAIACQmwIe0AAHwDAAMAAQlGB2zTADEAAAQAAQkuAiKOAB8AAAAA.Aelusius:BAACLgAFFH8KAAIFAAMJNR4EBAAAAQAFAAMJNR4EBAAAAQAuAAQKfz4AAgUACQn4IlgBACsDAAUACQn4IlgBACsDAAAA.Aeón:BAAALgAECgkJEQAAAA==.',
Ag='Aggèn:BAABLgAECn8xAAMGAAkJRR+WGwCeAgAGAAkJ/B6WGwCeAgAHAAYJnQ5JBQC+AAAAAA==.',
Aj='Aja:BAAALgAECgIJAgAAAA==.',
Ak='Akashá:BAAALgAECgEJAwAAAA==.Akriksdk:BAABLgAECn8WAAIBAAkJciY1AQCLAwABAAkJciY1AQCLAwAAAA==.',
Al='Al:BAACLgAFFH8NAAMIAAQJGwo4IADyAAAIAAQJGwo4IADyAAAJAAIJbQTeMABVAAAuAAQKfy0AAwgACAnbGEYdANsBAAgACAnbGEYdANsBAAkABwlpEUErAJsBAAAA.Aladrios:BAAALgAECgMJBQAAAA==.Alandarus:BAAALgAECgEJBAAAAA==.Alexanderath:BAAALgAECgQJBwAAAA==.Alexânderson:BAAALgAECgUJDQAAAA==.Alkaline:BAAALgADCggJCAAAAA==.Alkatractite:BAABLgAECn8nAAIGAAgJ4Bu5MQA5AgAGAAgJ4Bu5MQA5AgAAAA==.Allenwalker:BAAALgAECgUJCwAAAA==.Alucarde:BAEALgADCgYJBgABLgAECgkJIAAKAOwXAA==.Alzul:BAAALgADCgUJBQAAAA==.',
Am='Amanita:BAABLgAECn8eAAIDAAkJExUcJQAjAgADAAkJExUcJQAjAgAAAA==.Amasham:BAAALgAECgYJBgAAAA==.Amberness:BAAALgAFFAEJAQABLgAFFAMJBwALACseAA==.Ambersoul:BAAALgAECgEJAQAAAA==.Amira:BAAALgAECgcJDQABLgAFFAMJBQAMAG4PAA==.',
An='Angryanna:BAAALgAECgIJAgAAAA==.Anixa:BAAALgADCgkJCQAAAA==.Anyi:BAABLgAECn8rAAMNAAgJygtwQgApAQANAAgJygtwQgApAQALAAQJEgL4swBiAAAAAA==.',
Ao='Aoi:BAABLgAECn8yAAMOAAgJxBIyIgCeAQAOAAgJxBIyIgCeAQAPAAgJ5gttSABKAQAAAA==.',
Ar='Arrisia:BAABLgAECn8yAAMQAAgJKRJ/TgC3AQAQAAgJKRJ/TgC3AQARAAIJJwSeOAA9AAAAAA==.Artemissy:BAAALgADCgQJBAAAAA==.Arthedain:BAACLgAFFH8XAAISAAQJlyHHBABqAQASAAQJlyHHBABqAQAuAAQKfzMAAhIACQnSI30BAHIDABIACQnSI30BAHIDAAAA.Arthedaine:BAACLgAFFH8qAAITAAcJQBcKAQDTAQATAAcJQBcKAQDTAQAuAAQKfzEAAhMACQnKI24EAOcCABMACQnKI24EAOcCAAEuAAUUBAkXABIAlyEA.',
As='Asiea:BAAALgADCgQJBAAAAA==.Assano:BAAALgAECgYJCAAAAA==.',
Au='Augmentmyass:BAAALgAFFAEJAQAAAA==.Aushahin:BAAALgAECggJDgABLgAECgkJIAAEAAESAA==.Autumni:BAABLgAECn8fAAIQAAcJsRhpXgCLAQAQAAcJsRhpXgCLAQAAAA==.Auvry:BAABLgAECn8aAAMUAAcJVhkdEAA5AgAUAAcJVhkdEAA5AgAVAAIJqAlamQAqAAAAAA==.',
Ax='Axel:BAAALgADCgUJBQABLgAECgkJLAAWAN8JAA==.',
Ay='Aymus:BAABLgAECn8YAAQXAAcJ+QJNBwA9AAAYAAcJkgKZ6gBmAAAXAAIJyANNBwA9AAAZAAMJzAFdggAbAAAAAA==.',
Az='Azliain:BAAALgAECgkJCAAAAA==.',
Ba='Bahamutfang:BAABLgAECn8mAAMGAAkJDwhbjABYAQAGAAkJDwhbjABYAQAHAAUJzATMOwBtAAAAAA==.Bakala:BAABLgAECn83AAMaAAgJEBUNLwCTAQAaAAgJTBMNLwCTAQASAAgJYw0/HgBCAQAAAA==.Bangbang:BAABLgAECn8qAAIQAAkJqBV8TAC8AQAQAAkJqBV8TAC8AQAAAA==.Barath:BAAALgADCgkJCwAAAA==.Bast:BAAALgADCgQJBAAAAA==.',
Be='Beeyou:BAAALgADCgEJAQAAAA==.Belegaer:BAABLgAECn8jAAIKAAkJhw+JKQDBAQAKAAkJhw+JKQDBAQAAAA==.Belenos:BAAALgADCggJHQABLgADCggJHQAbAAAAAA==.Bellamy:BAAALgAECgEJAQAAAA==.Beltway:BAAALgADCgcJCgAAAA==.Bendini:BAACLgAFFH8GAAIRAAMJHwsEIACrAAARAAMJHwsEIACrAAAuAAQKfx4AAhEACQnSE3kqANgBABEACQnSE3kqANgBAAAA.Benmaverick:BAABLgAECn8dAAIYAAkJDg/2SQCoAQAYAAkJDg/2SQCoAQAAAA==.',
Bh='Bhe:BAABLgAECn8aAAIFAAgJ5wrcFwBKAQAFAAgJ5wrcFwBKAQAAAA==.',
Bi='Billymayzz:BAAALgADCgIJAgAAAA==.Bishop:BAABLgAECn89AAIJAAkJ9RjOAgCmAQAJAAkJ9RjOAgCmAQAAAA==.',
Bl='Blackbird:BAAALgADCgYJCgAAAA==.',
Bo='Bobe:BAACLgAFFH8KAAMSAAMJhA9zDwB2AAASAAIJ8xNzDwB2AAAaAAEJpQZIKwA+AAAuAAQKf0EAAxIACQlGHCgJAGQCABIACQlGHCgJAGQCABoAAwmkBlCQAFEAAAAA.Bobedruid:BAAALgADCgQJAQAAAA==.Bordok:BAABLgAECn8iAAIcAAkJ2gvQDgCIAQAcAAkJ2gvQDgCIAQAAAA==.Borkuz:BAAALgAECgEJAQAAAA==.Bowfléx:BAAALgAECgEJAQAAAA==.',
Br='Brettdadad:BAAALgAECgIJAwAAAA==.Brighella:BAAALgADCgMJAwAAAA==.Bronxdr:BAAALgADCgQJBAAAAA==.Brows:BAAALgAECgMJBQAAAA==.Bruisewayne:BAAALgADCggJCAAAAA==.Brunco:BAABLgAECn8fAAMQAAkJ0h3XIABjAgAQAAkJ0h3XIABjAgARAAYJyROyFwD1AAAAAA==.Brxndxn:BAAALgADCgUJBQAAAA==.Brëw:BAAALgADCgUJBQAAAA==.Brütäl:BAAALgADCgIJAgAAAA==.',
Bu='Bubbleyo:BAAALgADCgcJCAAAAA==.Bustaheals:BAABLgAECn8lAAMJAAkJlhQIIQC6AQAJAAcJ+hYIIQC6AQAIAAcJ9RDiMQBUAQAAAA==.',
Bw='Bwasamdi:BAAALgAFFAEJAQAAAA==.',
Ca='Calypsa:BAAALgADCgMJBAAAAA==.Cantpoly:BAAALgAECgYJBgAAAA==.Captplanet:BAABLgAECn8fAAQCAAkJVBbjDwC4AQACAAYJVxjjDwC4AQADAAgJdgk4YwALAQAEAAYJSgzoSQDkAAAAAA==.Cashartea:BAAALgAECgUJBQAAAA==.Cattleclysm:BAAALgADCgMJAwAAAA==.',
Ce='Ceindra:BAABLgAECn8pAAIFAAkJIyCtAwDEAgAFAAkJIyCtAwDEAgAAAA==.Celiñ:BAACLgAFFH8HAAMHAAMJZxSgDwCJAAAHAAMJ7QqgDwCJAAAGAAIJ9xNBmgCFAAAuAAQKfygABAYACQmiIEgbAKACAAYACAmyIkgbAKACAAcABAnRE2o3AIIAAAoAAwnuBPZ2AGAAAAAA.Celîn:BAAALgAECgQJBAABLgAFFAMJBwAHAGcUAA==.Ceronia:BAAALgADCgEJAQAAAA==.',
Ch='Chainstormer:BAAALgAECgUJCQAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chibby:BAAALgAECgQJBAAAAA==.Chuladk:BAABLgAFFH8FAAIBAAMJnwiQuQC1AAABAAMJnwiQuQC1AAAAAA==.Chuyiacon:BAAALgAECgEJAQABLgAFFAMJBQABAJ8IAA==.',
Cl='Cleymour:BAAALgADCgcJDgAAAA==.Cløudstrife:BAAALgAECgEJAQAAAA==.',
Co='Colbalt:BAABLgAECn8UAAIIAAcJdAdKOgAfAQAIAAcJdAdKOgAfAQAAAA==.Cor:BAAALgAECgUJCAAAAA==.Corrosive:BAAALgAECgYJBQAAAA==.Cotilion:BAAALgADCgMJAwAAAA==.',
Cr='Creation:BAABLgAECn9EAAMCAAgJWiP5AwDJAgACAAgJQyP5AwDJAgAdAAgJSxw4CwAvAgABLgAFFAMJCgAFADUeAA==.Crunky:BAABLgAECn8wAAIPAAgJ9hWzIgAJAgAPAAgJ9hWzIgAJAgAAAA==.Cruz:BAAALgADCgIJAgAAAA==.',
Cu='Cuddleybunni:BAAALgADCgMJAwAAAA==.Cuddlymethod:BAAALgAECgMJBgAAAA==.',
['Có']='Cól:BAABLgAECn8uAAIWAAkJNh5sMgCpAgAWAAkJNh5sMgCpAgAAAA==.',
Da='Daddydruid:BAAALgAECgEJAQAAAA==.Daddywoof:BAAALgAECgIJAgAAAA==.Dadmike:BAAALgAECgEJAQAAAA==.Daedilus:BAAALgADCgMJAwAAAA==.Dahealzrhere:BAAALgAECgYJCwAAAA==.Dalel:BAACLgAFFH8GAAIYAAYJngzAEgA9AQAYAAYJngzAEgA9AQAuAAQKfx0AAhgACQm4ILgSAK0CABgACQm4ILgSAK0CAAAA.Dameond:BAAALgAECgUJDwAAAA==.David:BAAALgAFFAIJAgABLgAFFAQJCQATAHsZAA==.',
De='Deadisdead:BAAALgAECgYJDgAAAA==.Deadlyglow:BAAALgADCgcJDAABLgAECgYJCAAbAAAAAA==.Deathkratos:BAAALgADCgYJCQAAAA==.Demiurgos:BAACLgAFFH8HAAMLAAMJfSC6NQALAQALAAMJfSC6NQALAQAFAAMJbwNHEgCjAAAuAAQKfx4AAwsABwltIc8XAIsCAAsABwltIc8XAIsCAAUAAwl4EMIsAJMAAAAA.Demonicteli:BAABLgAECn8WAAIZAAkJlxmZEABdAgAZAAkJlxmZEABdAgAAAA==.Demonopii:BAAALgAECgQJCAAAAA==.Denzle:BAAALgAECggJDgAAAA==.Dermot:BAABLgAECn8wAAQeAAgJLiN0AwC6AgAeAAcJZCJ0AwC6AgAMAAYJ+iBseQBGAQAfAAIJCyYHIQBuAAAAAA==.',
Dh='Dhiying:BAAALgAECggJEAAAAA==.',
Di='Dippindots:BAABLgAECn8fAAMEAAgJLBFiLgBoAQAEAAgJLBFiLgBoAQADAAEJZQGJ7AAVAAAAAA==.Divakon:BAAALgADCgkJCgAAAA==.Dixmen:BAABLgAECn8fAAMGAAkJXxm0BQCzAQAGAAgJ4Ru0BQCzAQAHAAEJ0we6DgAoAAAAAA==.',
Dk='Dkäri:BAAALgAECgYJDQAAAA==.',
Dl='Dlekri:BAAALgAECggJCAABLgAECgkJPgABABwfAA==.',
Do='Dolemen:BAABLgAECn9EAAIGAAkJzw2JEgDcAAAGAAkJzw2JEgDcAAAAAA==.Domaon:BAABLgAECn8wAAIZAAkJ+SFhBAADAwAZAAkJ+SFhBAADAwAAAA==.Domshammy:BAAALgAECggJEwABLgAECgkJMAAZAPkhAA==.Doombunny:BAAALgAECgUJCQABLgAECgkJQAAQAOEXAA==.Doubt:BAABLgAECn8bAAIIAAgJWApJNgA9AQAIAAgJWApJNgA9AQAAAA==.',
Dr='Dranthrax:BAAALgAECgUJEAAAAA==.',
Du='Dullgrim:BAAALgADCgkJEQAAAA==.Dunigan:BAABLgAECn82AAMGAAgJThHlfgBxAQAGAAgJTxDlfgBxAQAHAAYJDg+1JgDgAAAAAA==.Dunigen:BAAALgAECgcJEAAAAA==.Dunstan:BAAALgAECgYJDwAAAA==.Durmet:BAAALgAECgUJBQAAAA==.Dustos:BAAALgADCgIJAgAAAA==.',
Eb='Ebeast:BAABLgAECn9CAAITAAkJ/RnnDABWAgATAAkJ/RnnDABWAgAAAA==.Ebingus:BAAALgADCgYJBgAAAA==.',
Ei='Eifaun:BAEALgAECgUJCQAAAA==.',
El='Elexidor:BAAALgAECgkJDAAAAA==.Elorrna:BAAALgADCgYJBgAAAA==.',
Em='Emberjoy:BAAALgADCgUJBQAAAA==.',
Er='Erathen:BAAALgADCgUJBQAAAA==.',
Ev='Evangelista:BAAALgAECgQJBgAAAA==.',
Ey='Eyeet:BAAALgAECgkJDgAAAA==.',
Fa='Facade:BAABLgAECn8mAAIgAAkJGxNtAgCMAQAgAAkJGxNtAgCMAQAAAA==.Facepalm:BAABLgAECn8fAAIaAAkJdxMxHwD1AQAaAAkJdxMxHwD1AQAAAA==.Faked:BAAALgADCgEJAQABLgAECgYJDAAbAAAAAA==.Falion:BAAALgAECgYJBgAAAA==.Fallensaints:BAAALgAECgYJCwAAAA==.Falshalad:BAABLgAECn8jAAMDAAcJFxxZAgDzAQADAAcJFxxZAgDzAQACAAQJyRO2LACzAAABLgAFFAIJCQAUAIwKAA==.Falyy:BAAALgADCgQJBAAAAA==.',
Fe='Fentak:BAABLgAECn8eAAIcAAkJnAvOFQArAQAcAAkJnAvOFQArAQAAAA==.',
Fi='Fierytotes:BAAALgAECgUJCgAAAA==.Finka:BAAALgAECgMJAwAAAA==.',
Fl='Flamedaddy:BAABLgAECn8kAAMLAAcJcxnRLAAFAgALAAcJcxnRLAAFAgANAAEJgRwzkQBQAAAAAA==.',
Fo='Fog:BAAALgAECgEJAgAAAA==.Forgotmymeds:BAABLgAECn9QAAILAAkJ0BtZAwDtAQALAAkJ0BtZAwDtAQAAAA==.Foxmccloud:BAABLgAECn8uAAMLAAgJVRtcGwBwAgALAAgJVRtcGwBwAgANAAQJlQTClwBHAAAAAA==.',
Fr='Fruitloop:BAABLgAECn8jAAIWAAkJMB94GADGAgAWAAkJMB94GADGAgAAAA==.',
Fu='Fuil:BAAALgAECgYJDQAAAA==.Furgaler:BAAALgAECgUJCQABLgAFFAYJBgAYAJ4MAA==.',
Fy='Fyznen:BAAALgAECgQJBAAAAA==.',
Ga='Garidrael:BAAALgAECgEJAQAAAA==.Garim:BAAALgADCgcJBwAAAA==.Gaviriard:BAAALgADCgMJAwAAAA==.',
Ge='Gebran:BAAALgAECgEJAQAAAA==.Gellywoo:BAABLgAECn9BAAIaAAkJWR9ZDQCYAgAaAAkJWR9ZDQCYAgAAAA==.Genmaitcha:BAAALgADCgEJAQAAAA==.',
Gh='Ghostofonyx:BAAALgADCgcJFQAAAA==.',
Gi='Girlypop:BAAALgAECgQJBgAAAA==.',
Go='Golaoth:BAABLgAECn8lAAMUAAkJtxdUBwCDAgAUAAkJtxdUBwCDAgAhAAEJCQFdLQAKAAAAAA==.Gooftoo:BAABLgAECn8UAAIDAAcJKB8QLwDwAQADAAcJKB8QLwDwAQAAAA==.',
Gr='Grawn:BAAALgAECgEJAQAAAA==.Greycie:BAAALgADCgkJEwABLgAECggJEgAbAAAAAA==.Greyfax:BAAALgADCgcJDQAAAA==.Greymoon:BAABLgAECn81AAIdAAgJGhkgDwDzAQAdAAgJGhkgDwDzAQAAAA==.Grimfu:BAAALgAECgYJDAABLgAECgkJHQAGAEoeAA==.',
Gu='Guigondk:BAAALgAFFAcJAQAAAA==.',
Gy='Gyre:BAABLgAECn8dAAIQAAcJ6hBfbABoAQAQAAcJ6hBfbABoAQAAAA==.',
Ha='Haezi:BAAALgAECggJDQABLgAECgkJHwAiAEQUAA==.Happyendings:BAABLgAFFH8FAAIMAAIJ7QjUSQBKAAAMAAIJ7QjUSQBKAAAAAA==.',
He='Helbafx:BAABLgAECn8WAAIMAAYJMAQ6EgCJAAAMAAYJMAQ6EgCJAAAAAA==.',
Hi='Hiroshì:BAAALgAECgEJAQAAAA==.',
Ho='Homewrecker:BAABLgAECn8cAAISAAgJ2RKhGgBkAQASAAgJ2RKhGgBkAQAAAA==.',
Hu='Hunnee:BAAALgADCgkJFAAAAA==.Huské:BAAALgAECgcJDQAAAA==.',
Ic='Icelace:BAAALgAECgEJAQAAAA==.Icemàn:BAABLgAECn8eAAIjAAgJwQ4fAgCKAQAjAAgJwQ4fAgCKAQAAAA==.',
If='Ifearnobeer:BAABLgAECn81AAMNAAkJggrCOgBLAQANAAkJggrCOgBLAQALAAIJZwiYxwBGAAAAAA==.',
Ii='Iifelike:BAAALgAECgUJBQABLgAECgkJFQAHAN4PAA==.',
In='Inters:BAAALgAECgUJDgAAAA==.',
Ir='Ironspark:BAAALgAECgcJEgAAAA==.',
Is='Isabel:BAACLgAFFH8QAAIDAAQJTwucOQDHAAADAAQJTwucOQDHAAAuAAQKfxUAAgMACAmEGC0kACoCAAMACAmEGC0kACoCAAAA.Isaetr:BAAALgAECggJDwAAAA==.',
Ja='Jackôdaniels:BAAALgADCgkJDgAAAA==.Jadedrienne:BAAALgADCgUJBQAAAA==.Jadus:BAAALgAECgMJAwAAAA==.Jaiantobea:BAACLgAFFH8HAAILAAYJKhawBgCeAQALAAYJKhawBgCeAQAuAAQKfzEAAgsACQnfHbQIACYDAAsACQnfHbQIACYDAAAA.Jake:BAAALgAECgIJAgAAAA==.Jakulista:BAAALgADCgcJFQAAAA==.Jashugan:BAAALgADCgQJBAAAAA==.Jawn:BAABLgAECn8iAAIOAAkJ4g4UJACSAQAOAAkJ4g4UJACSAQAAAA==.Jaycie:BAAALgAECggJEgAAAA==.',
Je='Jessuss:BAABLgAECn8sAAIGAAkJGhXOBQCvAQAGAAkJGhXOBQCvAQAAAA==.',
Jh='Jha:BAAALgAECgEJAwAAAA==.',
Ju='Jude:BAAALgAECgUJCgAAAA==.Juggernàut:BAAALgAECgYJEAAAAA==.Julïeth:BAAALgAECgEJAQAAAA==.Junipermoon:BAAALgADCggJHQAAAA==.',
Ka='Kajas:BAAALgAECgMJAwAAAA==.Kalahandra:BAACLgAFFH8FAAIDAAMJqQOaTwCDAAADAAMJqQOaTwCDAAAuAAQKfyoAAgMACQnTEIs1AMQBAAMACQnTEIs1AMQBAAAA.Kalebeesd:BAABLgAECn8vAAIYAAkJ5hyeIgBGAgAYAAkJ5hyeIgBGAgAAAA==.Karthdh:BAAALgADCgcJDgABLgADCggJCAAbAAAAAA==.Kasey:BAAALgAECgEJAQAAAA==.Katithianna:BAAALgADCgQJAwAAAA==.Katotan:BAABLgAECn8jAAIDAAgJKhf2BAA5AQADAAgJKhf2BAA5AQAAAA==.Kawk:BAABLgAECn8uAAIHAAkJWx+LBAC7AgAHAAkJWx+LBAC7AgAAAA==.Kazatreshan:BAAALgADCgcJDgAAAA==.Kazragor:BAACLgAFFH8NAAINAAQJbCKCFAB7AQANAAQJbCKCFAB7AQAuAAQKfyUAAg0ACAn5I/4OALcCAA0ACAn5I/4OALcCAAAA.',
Ke='Kealestra:BAAALgADCgkJCwAAAA==.Kebob:BAABLgAECn8VAAIHAAkJ3g8fGABdAQAHAAkJ3g8fGABdAQAAAA==.Kenziedadght:BAAALgAECgIJBQAAAA==.Keyboärd:BAABLgAECn8hAAISAAgJ5BwhDgAJAgASAAgJ5BwhDgAJAgAAAA==.',
Ki='Kilo:BAAALgADCgEJAwAAAA==.Kippo:BAECLgAFFH8IAAIWAAUJJgURMwDRAAAWAAUJJgURMwDRAAAuAAQKfyMAAhYACAmWF0BKAFgCABYACAmWF0BKAFgCAAEuAAUUBwkVAAEAthEA.Kittylover:BAAALgAECgYJCwAAAA==.',
Kl='Klazarth:BAACLgAFFH8HAAIIAAMJMReHIgDgAAAIAAMJMReHIgDgAAAuAAQKfx4AAggACQmqHowNAKoCAAgACQmqHowNAKoCAAAA.',
Ko='Kombat:BAABLgAECn8kAAMaAAkJvBwFFQBHAgAaAAkJvBwFFQBHAgAkAAEJLhhnDABJAAAAAA==.Korllan:BAABLgAECn8XAAIBAAYJjwqRDwDhAAABAAYJjwqRDwDhAAAAAA==.Kossnen:BAABLgAECn8XAAIMAAkJhR3XHgBsAgAMAAkJhR3XHgBsAgAAAA==.',
Kr='Krelivus:BAAALgAECgYJCwAAAA==.',
Ku='Kuda:BAABLgAECn8sAAIWAAkJDxQlQwASAgAWAAkJDxQlQwASAgAAAA==.Kuridis:BAAALgAECgEJAQAAAA==.',
Kw='Kwanu:BAABLgAECn8eAAIPAAgJFw1HRABbAQAPAAgJFw1HRABbAQAAAA==.',
['Kó']='Kóñä:BAAALgADCgkJDAABLgAECgkJEQAbAAAAAA==.',
La='Lamue:BAAALgAECgIJAgAAAA==.Lantern:BAAALgADCgYJCwAAAA==.Larke:BAAALgAECgUJBwAAAA==.Lasa:BAAALgAECgcJCgABLgAECgcJEAAbAAAAAA==.Lasloo:BAABLgAECn8eAAIGAAYJgBCwkQBPAQAGAAYJgBCwkQBPAQAAAA==.Laylani:BAABLgAECn8qAAIHAAkJcxR5AgBRAQAHAAkJcxR5AgBRAQAAAA==.Layllis:BAAALgADCgQJBgAAAA==.',
Le='Legiondary:BAABLgAECn8cAAIYAAkJ8Rc7LgBEAgAYAAkJ8Rc7LgBEAgAAAA==.Lesabor:BAAALgADCgYJBgAAAA==.',
Li='Licknstick:BAAALgAECgUJCAAAAA==.Lir:BAAALgADCgIJAwAAAA==.Lisan:BAABLgAECn8hAAIlAAkJ4RYjAgBMAgAlAAkJ4RYjAgBMAgAAAA==.Lisanalgaib:BAAALgAECgEJAgAAAA==.Littledicey:BAAALgADCgcJCwAAAA==.',
Lo='Lokin:BAAALgADCgIJAgAAAA==.Lothan:BAAALgADCgkJCQABLgAECgkJIAAEAAESAA==.Lotuss:BAABLgAECn8dAAMPAAYJdhm7CgAJAQAPAAYJdhm7CgAJAQAOAAEJNgPYwAAXAAABLgAFFAMJDQANAPQJAA==.',
Lu='Lucien:BAAALgAECgYJEQAAAA==.Luciä:BAABLgAECn8nAAIgAAkJBhKxFQC+AQAgAAkJBhKxFQC+AQAAAA==.Lucymoon:BAAALgAECgYJBQAAAA==.',
Ly='Lynex:BAAALgAECgQJBwAAAA==.',
Ma='Machoman:BAAALgAECgQJBAAAAA==.Madness:BAAALgAECgUJBwAAAA==.Magdeth:BAAALgAECgMJBQAAAA==.Magiann:BAAALgADCgEJAQAAAA==.Maiama:BAAALgAECgYJBwAAAA==.Marabelle:BAABLgAECn8cAAIEAAkJCgreMwBJAQAEAAkJCgreMwBJAQAAAA==.Massack:BAABLgAECn8jAAIiAAkJ9xeiEAA3AgAiAAkJ9xeiEAA3AgAAAA==.Mastik:BAAALgAECgEJAQAAAA==.Maximusblood:BAAALgADCgIJAgAAAA==.',
Mc='Mcknight:BAAALgAECgYJBgAAAA==.',
Me='Merex:BAAALgADCgEJAQAAAA==.Mero:BAAALgAECgYJBgAAAA==.Mew:BAAALgADCgEJAQABLgAECggJHwAKAJ0XAA==.',
Mi='Midgetmàniàc:BAAALgAECgMJBAAAAA==.Mikebeard:BAAALgAECgIJBQAAAA==.Mikereport:BAAALgAECgIJAgAAAA==.Misfire:BAAALgAECggJCgABLgAECgkJHgADABMVAA==.',
Mo='Moktar:BAAALgAECgYJBwAAAA==.Moobear:BAAALgADCgQJCwAAAA==.',
Mu='Muldoinit:BAABLgAECn8jAAIOAAkJYhibEwAfAgAOAAkJYhibEwAfAgAAAA==.',
My='Myroslava:BAAALgAECgMJAwAAAA==.Mysticalbeef:BAAALgAECgEJAQAAAA==.Mystrall:BAAALgAECgYJBgAAAA==.',
['Më']='Mërikh:BAAALgADCggJEQABLgAECgUJCwAbAAAAAA==.',
Na='Nadorian:BAAALgAECgEJAQAAAA==.',
Ne='Neb:BAABLgAECn8mAAIKAAgJ/SM1BgAqAwAKAAgJ/SM1BgAqAwAAAA==.Nehemia:BAAALgAECgYJEQAAAA==.Nerilestis:BAAALgAECgEJAQAAAA==.Netherrogue:BAACLgAFFH8NAAMjAAQJiRwYFQBiAQAjAAQJIRsYFQBiAQAmAAMJoRfsCADsAAAuAAQKfyMABCYACQntHe4GANkBACYABglmGu4GANkBACcABQnNHSkJALABACMABgkgFfYmAF8BAAAA.',
Ni='Nicage:BAAALgAECgQJBAABLgAFFAQJEAAWAOMZAA==.Nightdreams:BAAALgADCgcJCQAAAA==.',
Ny='Nytelytë:BAAALgAECgYJCQABLgAFFAMJBwAMAG8TAA==.Nytemayer:BAACLgAFFH8HAAIMAAMJbxM7eQDQAAAMAAMJbxM7eQDQAAAuAAQKfysABAwACQmIIGMaAIYCAAwACQl+H2MaAIYCAB4AAwmYH4szAOkAAB8AAQkAAC4pAE0AAAAA.',
['Nö']='Nöx:BAAALgAECgYJBQAAAA==.',
Ob='Obmakare:BAABLgAECn81AAICAAgJlhXsDgDGAQACAAgJlhXsDgDGAQAAAA==.Obonhigh:BAAALgAECgUJBQAAAA==.Oboñ:BAABLgAECn8lAAMfAAgJzw8RDQCLAQAfAAgJzw8RDQCLAQAMAAEJYwPyYgEeAAAAAA==.Obsfuyung:BAABLgAECn80AAIOAAgJ6RToIACmAQAOAAgJ6RToIACmAQAAAA==.',
On='Onkelos:BAAALgAECgEJAwAAAA==.',
Oo='Oopsiez:BAAALgAECgQJBAAAAA==.',
Or='Orcc:BAAALgAECgEJAgAAAA==.',
Pa='Paley:BAAALgAECgYJDQAAAA==.Palpatine:BAAALgAECgIJAgAAAA==.',
Pe='Peopleperson:BAAALgADCgQJAQAAAA==.Performance:BAAALgAECgcJEAAAAA==.Peterturbo:BAAALgAECgQJBAABLgADCgcJDQAbAAAAAA==.',
Pi='Piezoori:BAAALgADCgcJBgAAAA==.Pinji:BAAALgAECgIJAgAAAA==.Pinkky:BAAALgADCgkJCQAAAA==.Pinkypoo:BAABLgAECn8rAAMBAAkJmxbXPAAOAgABAAkJiBPXPAAOAgAgAAYJvBixIwAjAQAAAA==.',
Pl='Plato:BAABLgAECn8vAAQKAAkJdxtDFwBQAgAKAAgJrBtDFwBQAgAGAAIJ9wiwWgFXAAAHAAEJAADFEQAAAAAAAA==.',
Po='Poiet:BAAALgAECgEJAgAAAA==.Poîsonivy:BAABLgAECn8oAAMeAAkJChVkBgD7AQAeAAkJChVkBgD7AQAMAAEJNgFtaQENAAAAAA==.',
Ps='Psyche:BAAALgADCgkJDgAAAA==.Psyrine:BAAALgAECgYJDgAAAA==.',
Py='Pyrokast:BAAALgAECgUJBQAAAA==.Pyrokos:BAACLgAFFH8GAAIWAAMJUBlwfwDYAAAWAAMJUBlwfwDYAAAuAAQKfyEAAhYACAnsIDliABUCABYACAnsIDliABUCAAAA.Pyrö:BAAALgAECgkJCQAAAA==.',
Qu='Qu:BAABLgAECn84AAMkAAkJkiFvBgBlAgAkAAkJkiFvBgBlAgAaAAIJTQowlQBrAAAAAA==.Quellia:BAACLgAFFH8XAAIKAAUJWhvtFgBvAQAKAAUJWhvtFgBvAQAuAAQKfyIAAgoACQn8HdMMALMCAAoACQn8HdMMALMCAAAA.',
Ra='Rangel:BAABLgAECn8YAAIaAAgJ7BArQQBAAQAaAAgJ7BArQQBAAQAAAA==.Rattlesnake:BAAALgADCgYJBgAAAA==.Razziels:BAAALgAECgYJBwAAAA==.',
Re='Redacted:BAAALgADCgMJAwAAAA==.Renägäde:BAAALgAECgYJDwAAAA==.Rexulti:BAAALgAECgEJAQAAAA==.',
Ri='Ricodadawg:BAAALgADCgEJAQAAAA==.Rizen:BAAALgAECgQJBAAAAA==.',
Ro='Roija:BAACLgAFFH8QAAIWAAQJ4xlYVwAuAQAWAAQJ4xlYVwAuAQAuAAQKfygAAhYACQlDJRIKACkDABYACQlDJRIKACkDAAAA.Roshak:BAAALgADCgYJCQAAAA==.',
Ru='Runningbearr:BAAALgAECgMJAwAAAA==.Runningmage:BAAALgADCgcJDAAAAA==.Rurahk:BAACLgAFFH8YAAIGAAYJEhJaJgBwAQAGAAYJEhJaJgBwAQAuAAQKfy4AAgYACAkEIaIVAOgCAAYACAkEIaIVAOgCAAAA.',
['Rõ']='Rõbb:BAACLgAFFH8HAAIGAAMJVR6mXAD3AAAGAAMJVR6mXAD3AAAuAAQKfywAAgYACQkGIpsOABkDAAYACQkGIpsOABkDAAAA.',
Sa='Sabaak:BAABLgAECn8sAAIGAAgJZCEwGwChAgAGAAgJZCEwGwChAgAAAA==.Sacerdote:BAAALgADCgUJBQAAAA==.Saeriin:BAABLgAECn9DAAIMAAkJJRJxBgBMAQAMAAkJJRJxBgBMAQAAAA==.Saintsnyder:BAABLgAECn8dAAIGAAYJ5xMKpAAxAQAGAAYJ5xMKpAAxAQAAAA==.Saithis:BAABLgAECn8UAAIDAAYJmBBIbgDpAAADAAYJmBBIbgDpAAAAAA==.Saltycrank:BAAALgADCgYJBgAAAA==.Sandew:BAAALgAECgcJEAAAAA==.Sanorasong:BAEBLgAECn8gAAMKAAkJ7Bd3FwBOAgAKAAkJ7Bd3FwBOAgAGAAUJPhQGxwD/AAAAAA==.Saphaa:BAAALgADCgMJAwAAAA==.Sardine:BAAALgAECgcJDAAAAA==.Sarylin:BAABLgAECn8YAAMQAAkJbxoGHgBxAgAQAAkJbxoGHgBxAgARAAQJdQhqYwCzAAAAAA==.Satanshealer:BAAALgADCgYJCQAAAA==.Satansshadow:BAAALgAECgIJAgAAAA==.Sathpriest:BAAALgAECgIJAgAAAA==.Satsuki:BAAALgAECgYJCgAAAA==.',
Sc='Schio:BAABLgAECn81AAIeAAgJ9xZjBwDfAQAeAAgJ9xZjBwDfAQAAAA==.',
Se='Sean:BAAALgADCgYJBgAAAA==.Seananagíns:BAAALgAFFAIJAwAAAA==.Sections:BAAALgADCgkJHAAAAA==.Semilla:BAAALgADCgEJAQAAAA==.Severussnape:BAABLgAECn8jAAMMAAkJqQneYgB5AQAMAAkJnAneYgB5AQAeAAEJ6gpVQwAnAAAAAA==.',
Sh='Shambs:BAACLgAFFH8HAAILAAMJKx4WPwDoAAALAAMJKx4WPwDoAAAuAAQKfxsAAgsACQnPHikGAA8DAAsACQnPHikGAA8DAAAA.Shamrorag:BAABLgAECn8bAAMNAAgJLgrSRAAgAQANAAgJLgrSRAAgAQAFAAMJ2wO2NQBZAAAAAA==.Shehealz:BAAALgAECgEJAgAAAA==.Shinron:BAAALgAECgIJAgAAAA==.Shökan:BAAALgAECgQJBwAAAA==.',
Si='Sighah:BAAALgAECgkJEgAAAA==.Simlockdr:BAAALgADCgYJBgAAAA==.Sinensis:BAABLgAECn8bAAMnAAkJpRWtBQAaAgAnAAkJTBWtBQAaAgAjAAEJnBttDABRAAAAAA==.Singood:BAAALgAECgcJBwAAAA==.Sinnecro:BAABLgAECn8aAAIBAAkJ4h5nIADAAgABAAkJ4h5nIADAAgAAAA==.Sinshift:BAAALgADCgUJBQAAAA==.Sinstab:BAAALgAECggJCAAAAA==.',
Sk='Skadoosh:BAAALgAECgUJDQABLgAFFAYJBgAYAJ4MAA==.Skarletbolt:BAAALgAECgUJBQAAAA==.Skarletflame:BAABLgAECn8aAAIZAAkJnRg/DQBRAgAZAAkJnRg/DQBRAgAAAA==.Skinalittleb:BAAALgAECgEJAQAAAA==.',
Sl='Slather:BAABLgAECn8aAAIUAAgJcBAKGADVAQAUAAgJcBAKGADVAQAAAA==.Slaycie:BAABLgAECn8jAAIWAAgJtBBUdgCNAQAWAAgJtBBUdgCNAQAAAA==.Slayerdude:BAAALgAECgEJAQAAAA==.Slofinger:BAAALgADCgYJCgAAAA==.',
Sn='Sneeb:BAAALgAECgEJAQAAAA==.Snugglebus:BAABLgAECn8dAAIXAAgJXQUNAwDBAAAXAAgJXQUNAwDBAAAAAA==.',
So='Songli:BAEALgADCgEJAQABLgAECgkJIAAKAOwXAA==.Sorne:BAEBLgAFFH8GAAILAAUJbRMyLgApAQALAAUJbRMyLgApAQABLgAFFAQJEQALAOUjAA==.',
Sp='Spaghett:BAABLgAECn8fAAMiAAkJRBRLJwB2AQAiAAkJphFLJwB2AQAOAAYJJhOlRADtAAAAAA==.Springtotem:BAABLgAECn8gAAIEAAkJARKKJACnAQAEAAkJARKKJACnAQAAAA==.',
St='Stachel:BAAALgAECgUJBwAAAA==.Stanger:BAABLgAECn8mAAILAAkJPx7xCQAWAwALAAkJPx7xCQAWAwAAAA==.Storaxota:BAAALgAFFAgJBAAAAA==.Stormdk:BAAALgADCgcJCQAAAA==.',
Su='Superneo:BAAALgAECgYJBgABLgAFFAMJCgAEAOciAA==.Suvion:BAAALgAECgcJEwABLgAFFAMJDQANAPQJAA==.',
Sy='Sylinial:BAAALgAECgEJAQAAAA==.Sylvanis:BAAALgAECgUJBwAAAA==.Syrden:BAABLgAECn8WAAIDAAkJ6AvaQACOAQADAAkJ6AvaQACOAQAAAA==.',
Sz='Szadèk:BAAALgAECgYJBwAAAA==.',
['Sÿ']='Sÿphallus:BAABLgAECn8SAAIZAAgJshSyIQBrAQAZAAgJshSyIQBrAQAAAA==.',
Ta='Tael:BAABLgAECn8tAAIaAAkJzR+RCwCvAgAaAAkJzR+RCwCvAgAAAA==.Tagreth:BAAALgADCgQJBAAAAA==.Tangylizard:BAACLgAFFH8ZAAIoAAQJKBOhJgAVAQAoAAQJKBOhJgAVAQAuAAQKfy8ABCgACAliG1UTAEYCACgACAliG1UTAEYCAAkAAQkFFq57ADoAAAgAAQkZDAeOACwAAAAA.Tattoospyder:BAABLgAECn8aAAIDAAcJTwi4dwDPAAADAAcJTwi4dwDPAAAAAA==.Tatyanafour:BAAALgADCgIJAQAAAA==.Tatyanathirt:BAAALgADCgYJBgAAAA==.',
Te='Terrenn:BAAALgADCggJCAAAAA==.Tessla:BAACLgAFFH8NAAINAAMJ9AkKFQCwAAANAAMJ9AkKFQCwAAAuAAQKf0wAAw0ACQmvHJYNAI8CAA0ACQmvHJYNAI8CAAsAAgm+CHnKAEMAAAAA.Tetragram:BAAALgAECgYJDgABLgAFFAMJCgAFADUeAA==.',
Th='Thafrggnpope:BAAALgADCgEJAQAAAA==.Thelarï:BAABLgAECn8jAAIQAAkJRgr4VQCiAQAQAAkJRgr4VQCiAQAAAA==.Thellany:BAAALgAECgEJAQAAAA==.Theshiznitz:BAAALgAECgQJBAAAAA==.Thors:BAABLgAECn8dAAIGAAcJSh43MgBZAgAGAAcJSh43MgBZAgAAAA==.Thundertoes:BAABLgAECn8jAAMLAAkJexylDgDeAgALAAkJexylDgDeAgAFAAYJChJzHwD+AAAAAA==.Thÿsucc:BAAALgADCgcJBwAAAA==.',
Ti='Tia:BAAALgAECgEJAQAAAA==.Timmy:BAAALgAECgMJCAABLgAECgkJAgAbAAAAAA==.',
To='Tommychong:BAAALgAECgIJAgAAAA==.Tonik:BAABLgAECn8qAAMLAAcJ2RQIPwCyAQALAAcJ2RQIPwCyAQANAAcJChAaQQAwAQAAAA==.Torgoth:BAABLgAECn8oAAIFAAkJpRTkCQAeAgAFAAkJpRTkCQAeAgAAAA==.Toshido:BAABLgAECn8VAAIQAAYJWhD9oAAAAQAQAAYJWhD9oAAAAQAAAA==.',
Tr='Traetor:BAABLgAECn8kAAIEAAkJDib2AAB7AwAEAAkJDib2AAB7AwAAAA==.Trakker:BAAALgADCgQJBAAAAA==.Trevize:BAABLgAECn8YAAIGAAYJ3Aec5wDUAAAGAAYJ3Aec5wDUAAAAAA==.',
Tt='Ttelloc:BAAALgADCgIJAgAAAA==.',
Tu='Tusiny:BAAALgAECgEJAQAAAA==.',
Ub='Ubully:BAAALgAECgEJAQAAAA==.',
Ul='Ultane:BAABLgAECn8lAAILAAgJrA4KRwCSAQALAAgJrA4KRwCSAQAAAA==.',
Un='Unreal:BAAALgADCgQJBAAAAA==.',
Va='Vaera:BAAALgAECgEJAQAAAA==.Valastae:BAABLgAECn8ZAAIQAAgJYQxSaQBwAQAQAAgJYQxSaQBwAQAAAA==.Valiantaine:BAABLgAECn8wAAMGAAkJXiFzKgB6AgAGAAkJXiFzKgB6AgAKAAkJgg2xPQCCAQABLgAFFAQJGAAYANAcAA==.Valiantaint:BAACLgAFFH8YAAIYAAQJ0Bx8NQBPAQAYAAQJ0Bx8NQBPAQAuAAQKfzAAAhgACQk/HtYVAJUCABgACQk/HtYVAJUCAAAA.Valiantrain:BAAALgAECgEJAgABLgAFFAQJGAAYANAcAA==.Valyulon:BAAALgADCgMJAwABLgAFFAQJGAAYANAcAA==.Vanjin:BAAALgADCgUJBQAAAA==.',
Ve='Vecna:BAAALgAECgYJCAAAAA==.Velherun:BAABLgAECn8dAAIGAAkJYh/zFADFAgAGAAkJYh/zFADFAgAAAA==.Vendeldh:BAABLgAECn8sAAIYAAkJuCPUEgDpAgAYAAkJuCPUEgDpAgAAAA==.Veni:BAAALgAECgYJBgAAAA==.Vexxaa:BAABLgAECn8lAAIQAAkJUhFVOgD1AQAQAAkJUhFVOgD1AQAAAA==.',
Vi='Vincentio:BAAALgAECgEJAQAAAA==.Virajr:BAABLgAECn8oAAMjAAgJ0RUAFgDvAQAjAAgJ0RUAFgDvAQAmAAEJvAQAKgAgAAAAAA==.Vishus:BAAALgADCgUJBQAAAA==.Visiôn:BAABLgAECn8bAAIaAAkJ8wcAQQBBAQAaAAkJ8wcAQQBBAQAAAA==.Vissiction:BAABLgAECn8ZAAIYAAkJvxZiLQASAgAYAAkJvxZiLQASAgAAAA==.Vistine:BAACLgAFFH8JAAIHAAMJ0QxFBQCLAAAHAAMJ0QxFBQCLAAAuAAQKf0wAAgcACQleEQwCAHcBAAcACQleEQwCAHcBAAEuAAUUAwkNAA0A9AkA.Vitez:BAABLgAECn8WAAMeAAkJrAaAHQC8AAAeAAgJFAeAHQC8AAAMAAIJRAPjGgFNAAAAAA==.',
Vo='Voidscar:BAAALgADCgcJBwAAAA==.',
Wa='Warhurts:BAAALgAECgMJAwAAAA==.Waterbloom:BAAALgADCgMJAwAAAA==.',
We='Weave:BAABLgAECn8iAAIWAAcJUgyKqQAsAQAWAAcJUgyKqQAsAQAAAA==.Wendy:BAABLgAECn8pAAILAAgJ1RiONwDSAQALAAgJ1RiONwDSAQABLgAECgkJHgADABMVAA==.',
Wi='Win:BAACLgAFFH8HAAMEAAQJ9QbBLQDRAAAEAAQJ9QbBLQDRAAADAAEJWQy9JwAwAAAuAAQKfywAAwMABwnjGlolACICAAMABwnjGlolACICAAQABgkMHxMDAH4BAAAA.Winkster:BAACLgAFFH8MAAIGAAUJWRySOQA5AQAGAAUJWRySOQA5AQAuAAQKfzAAAgYACQn4JIEKABMDAAYACQn4JIEKABMDAAAA.',
Xa='Xanadu:BAACLgAFFH8IAAIoAAIJkxOMGACIAAAoAAIJkxOMGACIAAAuAAQKfzgAAigACQlMHsIGABIDACgACQlMHsIGABIDAAAA.Xarinia:BAACLgAFFH8FAAIVAAIJ8gfZHwB4AAAVAAIJ8gfZHwB4AAAuAAQKfysAAxUACQkNEgMeAOcBABUACQkNEgMeAOcBABQABQnjB5QxAOMAAAAA.',
Xb='Xbear:BAACLgAFFH8GAAIdAAYJSxLjBAAiAQAdAAYJSxLjBAAiAQAuAAQKfyUAAh0ACQm2HOoHAHICAB0ACQm2HOoHAHICAAEuAAUUBgkVACMAKBcA.',
Xd='Xdynasty:BAACLgAFFH8VAAIjAAYJKBeHEACQAQAjAAYJKBeHEACQAQAuAAQKfycAAyMACQkCJCwMANUCACMACQn/IywMANUCACcABgnDG+UNADwBAAAA.',
Xo='Xo:BAABLgAECn86AAQMAAkJmhmXJgBDAgAMAAkJLxiXJgBDAgAeAAUJGBR5JQAxAQAfAAIJVgtDMAA9AAABLgAFFAQJBwAEAPUGAA==.',
Xy='Xyfarion:BAAALgADCgYJBgAAAA==.Xyril:BAAALgAECgEJAQAAAA==.',
Ya='Yaasnah:BAAALgADCggJCAAAAA==.Yavramor:BAAALgAFFAEJAwABLgAFFAYJGAAGABISAA==.',
Za='Zabazz:BAACLgAFFH8JAAILAAMJAhGfJQB/AAALAAMJAhGfJQB/AAAuAAQKfykAAwsACQnOEDQ8AL4BAAsACQnOEDQ8AL4BAA0ABAnJCB+EAGgAAAAA.Zabenir:BAABLgAECn8iAAIIAAkJ7hwuCwCdAgAIAAkJ7hwuCwCdAgAAAA==.Zané:BAAALgAECgEJAgAAAA==.Zapan:BAAALgADCgUJBQAAAA==.',
Ze='Zeverai:BAAALgADCgkJCgAAAA==.',
Zi='Ziria:BAAALgADCgQJCwAAAA==.',
Zo='Zonni:BAAALgADCgYJBgAAAA==.Zorusii:BAAALgAECgQJBQABLgAFFAYJBgAYAJ4MAA==.',
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
