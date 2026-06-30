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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Paladin-Retribution','Paladin-Protection','Priest-Shadow','Priest-Holy','Paladin-Holy','Shaman-Restoration','Hunter-BeastMastery','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Hunter-Marksmanship','Warrior-Protection','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Fury','Unknown-Unknown','DeathKnight-Frost','Druid-Guardian','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DeathKnight-Blood','Evoker-Devastation','Monk-Brewmaster','Rogue-Subtlety','Warrior-Arms','Mage-Arcane','Rogue-Outlaw','Rogue-Assassination','Priest-Discipline',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abyssara:BAAALgAECgcJEgAAAA==.',
Ac='Acebets:BAAALgAECgEJAQAAAA==.Acedk:BAACLgAFFH8GAAIBAAMJqR+dkQDoAAABAAMJqR+dkQDoAAAuAAQKfxoAAgEACQlPIZoLAD4DAAEACQlPIZoLAD4DAAAA.',
Ad='Adorie:BAAALgAECgIJAwAAAA==.Adun:BAAALgADCgQJBAAAAA==.',
Ae='Aelphe:BAACLgAFFH8GAAICAAMJwBUNDgDZAAACAAMJwBUNDgDZAAAuAAQKfx8ABAIACQmwIe0AAHwDAAIACQmwIe0AAHwDAAMAAQlGB2zTADEAAAQAAQkuAiKOAB8AAAAA.Aelusius:BAACLgAFFH8JAAIFAAMJWh00AwDoAAAFAAMJWh00AwDoAAAuAAQKfz4AAgUACQn4IlgBACsDAAUACQn4IlgBACsDAAAA.Aeón:BAAALgAECgkJEAAAAA==.',
Ag='Aggèn:BAABLgAECn8sAAMGAAkJlh6WGwCeAgAGAAkJlh6WGwCeAgAHAAQJQQsMQwBVAAAAAA==.',
Aj='Aja:BAAALgAECgIJAgAAAA==.',
Ak='Akashá:BAAALgAECgEJAgAAAA==.Akriksdk:BAABLgAECn8WAAIBAAkJciY1AQCLAwABAAkJciY1AQCLAwAAAA==.',
Al='Al:BAACLgAFFH8NAAMIAAQJGwo4IADyAAAIAAQJGwo4IADyAAAJAAIJbQTeMABVAAAuAAQKfy0AAwgACAnbGEYdANsBAAgACAnbGEYdANsBAAkABwlpEUErAJsBAAAA.Aladrios:BAAALgAECgMJBQAAAA==.Alandarus:BAAALgAECgEJAgAAAA==.Alexanderath:BAAALgAECgQJBwAAAA==.Alexânderson:BAAALgAECgUJDQAAAA==.Alkaline:BAAALgADCggJCAAAAA==.Alkatractite:BAABLgAECn8nAAIGAAgJ4Bu5MQA5AgAGAAgJ4Bu5MQA5AgAAAA==.Allenwalker:BAAALgAECgUJCwAAAA==.Alucarde:BAEALgADCgYJBgABLgAECgkJIAAKAOwXAA==.Alzul:BAAALgADCgUJBQAAAA==.',
Am='Amanita:BAABLgAECn8cAAIDAAkJqRMcJQAjAgADAAkJqRMcJQAjAgAAAA==.Amasham:BAAALgAECgYJBgAAAA==.Amberness:BAAALgAFFAEJAQABLgAFFAMJBwALACseAA==.Ambersoul:BAAALgAECgEJAQAAAA==.Amira:BAAALgAECgcJDQABLgAFFAQJCAAMAMgeAA==.',
An='Anixa:BAAALgADCgkJCQAAAA==.Anyi:BAABLgAECn8rAAMNAAgJygtwQgApAQANAAgJygtwQgApAQALAAQJEgL4swBiAAAAAA==.',
Ao='Aoi:BAABLgAECn8yAAMOAAgJxBIyIgCeAQAOAAgJxBIyIgCeAQAPAAgJ5gttSABKAQAAAA==.',
Ar='Arrisia:BAABLgAECn8yAAMMAAgJKRJ/TgC3AQAMAAgJKRJ/TgC3AQAQAAIJJwSeOAA9AAAAAA==.Artemissy:BAAALgADCgQJBAAAAA==.Arthedain:BAACLgAFFH8UAAIRAAQJiSEgDABsAQARAAQJiSEgDABsAQAuAAQKfzIAAhEACQnSI30BAHIDABEACQnSI30BAHIDAAAA.Arthedaine:BAACLgAFFH8kAAISAAUJWiCJAgBDAQASAAUJWiCJAgBDAQAuAAQKfzEAAhIACQnKI24EAOcCABIACQnKI24EAOcCAAEuAAUUBAkUABEAiSEA.',
As='Asiea:BAAALgADCgQJBAAAAA==.',
Au='Augmentmyass:BAAALgAFFAEJAQAAAA==.Aushahin:BAAALgAECggJDgABLgAECgkJHwAEAAESAA==.Autumni:BAABLgAECn8fAAIMAAcJsRhpXgCLAQAMAAcJsRhpXgCLAQAAAA==.Auvry:BAABLgAECn8aAAMTAAcJVhkdEAA5AgATAAcJVhkdEAA5AgAUAAIJqAlamQAqAAAAAA==.',
Ax='Axel:BAAALgADCgUJBQABLgAECgkJLAAVAN8JAA==.',
Ay='Aymus:BAABLgAECn8YAAQWAAcJ+QI7BQA9AAAXAAcJkgKZ6gBmAAAWAAIJyAM7BQA9AAAYAAMJzAFdggAbAAAAAA==.',
Az='Azliain:BAAALgAECgkJCAAAAA==.',
Ba='Bahamutfang:BAABLgAECn8mAAMGAAkJDwhbjABYAQAGAAkJDwhbjABYAQAHAAUJzATMOwBtAAAAAA==.Bakala:BAABLgAECn83AAMZAAgJEBUNLwCTAQAZAAgJTBMNLwCTAQARAAgJYw0/HgBCAQAAAA==.Bangbang:BAABLgAECn8qAAIMAAkJqBV8TAC8AQAMAAkJqBV8TAC8AQAAAA==.Barath:BAAALgADCgYJBgAAAA==.Bast:BAAALgADCgQJBAAAAA==.',
Be='Beeyou:BAAALgADCgEJAQAAAA==.Belegaer:BAABLgAECn8jAAIKAAkJhw+JKQDBAQAKAAkJhw+JKQDBAQAAAA==.Belenos:BAAALgADCggJHQABLgADCggJHQAaAAAAAA==.Bellamy:BAAALgAECgEJAQAAAA==.Beltway:BAAALgADCgcJCgAAAA==.Bendini:BAACLgAFFH8GAAIQAAMJHwsEIACrAAAQAAMJHwsEIACrAAAuAAQKfx4AAhAACQnSE3kqANgBABAACQnSE3kqANgBAAAA.Benmaverick:BAABLgAECn8dAAIXAAkJDg/2SQCoAQAXAAkJDg/2SQCoAQAAAA==.',
Bh='Bhe:BAABLgAECn8aAAIFAAgJ5wrcFwBKAQAFAAgJ5wrcFwBKAQAAAA==.',
Bi='Billymayzz:BAAALgADCgIJAgAAAA==.Bishop:BAABLgAECn84AAIJAAkJ+RjFFAAvAgAJAAkJ+RjFFAAvAgAAAA==.',
Bl='Blackbird:BAAALgADCgYJCgAAAA==.',
Bo='Bobe:BAACLgAFFH8IAAMRAAMJhA/TCgB/AAARAAIJ8xPTCgB/AAAZAAEJpQYAAAAAAAAuAAQKf0EAAxEACQlGHCgJAGQCABEACQlGHCgJAGQCABkAAwmkBlCQAFEAAAAA.Bobedruid:BAAALgADCgQJAQAAAA==.Bordok:BAABLgAECn8iAAIbAAkJ2gvQDgCIAQAbAAkJ2gvQDgCIAQAAAA==.Borkuz:BAAALgAECgEJAQAAAA==.Bowfléx:BAAALgAECgEJAQAAAA==.',
Br='Brettdadad:BAAALgAECgIJAwAAAA==.Brighella:BAAALgADCgMJAwAAAA==.Bronxdr:BAAALgADCgQJBAAAAA==.Brows:BAAALgAECgMJBQAAAA==.Bruisewayne:BAAALgADCggJCAAAAA==.Brunco:BAABLgAECn8fAAMMAAkJ0h3XIABjAgAMAAkJ0h3XIABjAgAQAAYJyROyFwD1AAAAAA==.Brxndxn:BAAALgADCgUJBQAAAA==.Brëw:BAAALgADCgUJBQAAAA==.Brütäl:BAAALgADCgIJAgAAAA==.',
Bu='Bubbleyo:BAAALgADCgcJCAAAAA==.Bustaheals:BAABLgAECn8lAAMJAAkJlhQIIQC6AQAJAAcJ+hYIIQC6AQAIAAcJ9RDiMQBUAQAAAA==.',
Bw='Bwasamdi:BAAALgAFFAEJAQAAAA==.',
Ca='Calypsa:BAAALgADCgMJBAAAAA==.Cantpoly:BAAALgAECgYJBgAAAA==.Captplanet:BAABLgAECn8fAAQCAAkJVBbjDwC4AQACAAYJVxjjDwC4AQADAAgJdgk4YwALAQAEAAYJSgzoSQDkAAAAAA==.Cashartea:BAAALgAECgUJBQAAAA==.Cattleclysm:BAAALgADCgMJAwAAAA==.',
Ce='Ceindra:BAABLgAECn8pAAIFAAkJIyCtAwDEAgAFAAkJIyCtAwDEAgAAAA==.Celiñ:BAACLgAFFH8HAAMHAAMJZxSgDwCJAAAHAAMJ7QqgDwCJAAAGAAIJ9xNBmgCFAAAuAAQKfygABAYACQmiIEgbAKACAAYACAmyIkgbAKACAAcABAnRE2o3AIIAAAoAAwnuBPZ2AGAAAAAA.Celîn:BAAALgAECgQJBAABLgAFFAMJBwAHAGcUAA==.Ceronia:BAAALgADCgEJAQAAAA==.',
Ch='Chainstormer:BAAALgAECgUJCQAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chibby:BAAALgAECgQJBAAAAA==.Chuladk:BAABLgAFFH8FAAIBAAMJnwiQuQC1AAABAAMJnwiQuQC1AAAAAA==.Chuyiacond:BAAALgAECgEJAQAAAA==.',
Cl='Cleymour:BAAALgADCgcJDgAAAA==.Cløudstrife:BAAALgAECgEJAQAAAA==.',
Co='Colbalt:BAABLgAECn8UAAIIAAcJdAdKOgAfAQAIAAcJdAdKOgAfAQAAAA==.Cor:BAAALgAECgUJCAAAAA==.Corrosive:BAAALgAECgYJBQAAAA==.Cotilion:BAAALgADCgMJAwAAAA==.',
Cr='Creation:BAABLgAECn9EAAMCAAgJWiP5AwDJAgACAAgJQyP5AwDJAgAcAAgJSxw4CwAvAgABLgAFFAMJCQAFAFodAA==.Crunky:BAABLgAECn8wAAIPAAgJ9hWzIgAJAgAPAAgJ9hWzIgAJAgAAAA==.',
Cu='Cuddleybunni:BAAALgADCgMJAwAAAA==.Cuddlymethod:BAAALgAECgMJBgAAAA==.',
['Có']='Cól:BAABLgAECn8uAAIVAAkJNh5sMgCpAgAVAAkJNh5sMgCpAgAAAA==.',
Da='Daddydruid:BAAALgAECgEJAQAAAA==.Daddywoof:BAAALgAECgIJAgAAAA==.Dadmike:BAAALgAECgEJAQAAAA==.Daedilus:BAAALgADCgMJAwAAAA==.Dahealzrhere:BAAALgAECgYJCwAAAA==.Dalel:BAABLgAECn8dAAIXAAkJuCC4EgCtAgAXAAkJuCC4EgCtAgAAAA==.Dameond:BAAALgAECgUJDwAAAA==.David:BAAALgAECgMJAwABLgAFFAQJCQASAHsZAA==.',
De='Deadisdead:BAAALgAECgYJDgAAAA==.Deadlyglow:BAAALgADCgcJDAABLgAECgYJCAAaAAAAAA==.Deathkratos:BAAALgADCgYJCQAAAA==.Demiurgos:BAACLgAFFH8HAAMLAAMJfSC6NQALAQALAAMJfSC6NQALAQAFAAMJbwNHEgCjAAAuAAQKfx4AAwsABwltIc8XAIsCAAsABwltIc8XAIsCAAUAAwl4EMIsAJMAAAAA.Demonicteli:BAABLgAECn8WAAIYAAkJlxmZEABdAgAYAAkJlxmZEABdAgAAAA==.Demonopii:BAAALgAECgQJCAAAAA==.Denzle:BAAALgAECggJDgAAAA==.Dermot:BAABLgAECn8wAAQdAAgJLiN0AwC6AgAdAAcJZCJ0AwC6AgAeAAYJ+iBseQBGAQAfAAIJCyYHIQBuAAAAAA==.',
Dh='Dhiying:BAAALgAECggJEAAAAA==.',
Di='Dippindots:BAABLgAECn8fAAMEAAgJLBFiLgBoAQAEAAgJLBFiLgBoAQADAAEJZQGJ7AAVAAAAAA==.Divakon:BAAALgADCgkJCgAAAA==.Dixmen:BAABLgAECn8fAAMGAAkJUxmxAwC5AQAGAAgJ4RuxAwC5AQAHAAEJdAcyCgAtAAAAAA==.',
Dk='Dkäri:BAAALgAECgYJDQAAAA==.',
Dl='Dlekri:BAAALgAECggJCAABLgAECgkJNQABANscAA==.',
Do='Dolemen:BAABLgAECn9EAAIGAAkJ2g0IDADlAAAGAAkJ2g0IDADlAAAAAA==.Domaon:BAABLgAECn8wAAIYAAkJ+SFhBAADAwAYAAkJ+SFhBAADAwAAAA==.Domshammy:BAAALgAECggJEwABLgAECgkJMAAYAPkhAA==.Doombunny:BAAALgAECgUJCQABLgAECgkJQAAMAOEXAA==.Doubt:BAABLgAECn8bAAIIAAgJWApJNgA9AQAIAAgJWApJNgA9AQAAAA==.',
Dr='Dranthrax:BAAALgAECgUJEAAAAA==.',
Du='Dullgrim:BAAALgADCgkJEAAAAA==.Dunigan:BAABLgAECn81AAMGAAgJThHlfgBxAQAGAAgJTxDlfgBxAQAHAAYJDg+1JgDgAAAAAA==.Dunigen:BAAALgAECgcJCgAAAA==.Dunstan:BAAALgAECgYJDwAAAA==.Durmet:BAAALgAECgUJBQAAAA==.Dustos:BAAALgADCgIJAgAAAA==.',
Eb='Ebeast:BAABLgAECn9CAAISAAkJphnnDABWAgASAAkJphnnDABWAgAAAA==.Ebingus:BAAALgADCgYJBgAAAA==.',
Ei='Eifaun:BAEALgAECgUJCQAAAA==.',
El='Elexidor:BAAALgAECgkJDAAAAA==.Elorrna:BAAALgADCgYJBgAAAA==.',
Em='Emberjoy:BAAALgADCgUJBQAAAA==.',
Er='Erathen:BAAALgADCgUJBQAAAA==.',
Ev='Evangelista:BAAALgAECgQJBgAAAA==.',
Ey='Eyeet:BAAALgAECgkJCQAAAA==.',
Fa='Facade:BAABLgAECn8lAAIgAAkJBROoAQCLAQAgAAkJBROoAQCLAQAAAA==.Facepalm:BAABLgAECn8fAAIZAAkJdxMxHwD1AQAZAAkJdxMxHwD1AQAAAA==.Faked:BAAALgADCgEJAQABLgAECgYJDAAaAAAAAA==.Falion:BAAALgAECgYJBgAAAA==.Fallensaints:BAAALgAECgYJCwAAAA==.Falshalad:BAABLgAECn8jAAMDAAcJHBx+AQD7AQADAAcJHBx+AQD7AQACAAQJyRO2LACzAAABLgAFFAIJBwATAFcJAA==.Falyy:BAAALgADCgQJBAAAAA==.',
Fe='Fentak:BAABLgAECn8eAAIbAAkJnAvOFQArAQAbAAkJnAvOFQArAQAAAA==.',
Fi='Fierytotes:BAAALgAECgUJCQAAAA==.Finka:BAAALgAECgMJAwAAAA==.',
Fl='Flamedaddy:BAABLgAECn8kAAMLAAcJcxnRLAAFAgALAAcJcxnRLAAFAgANAAEJgRwzkQBQAAAAAA==.',
Fo='Fog:BAAALgAECgEJAgAAAA==.Forgotmymeds:BAABLgAECn9QAAILAAkJ0BsbAgD8AQALAAkJ0BsbAgD8AQAAAA==.Foxmccloud:BAABLgAECn8uAAMLAAgJVRtcGwBwAgALAAgJVRtcGwBwAgANAAQJlQTClwBHAAAAAA==.',
Fr='Fruitloop:BAABLgAECn8jAAIVAAkJMB94GADGAgAVAAkJMB94GADGAgAAAA==.',
Fu='Fuil:BAAALgAECgYJDQAAAA==.Furgaler:BAAALgAECgUJCQABLgAECgkJHQAXALggAA==.',
Fy='Fyznen:BAAALgAECgQJBAAAAA==.',
Ga='Garidrael:BAAALgAECgEJAQAAAA==.Garim:BAAALgADCgcJBwAAAA==.Gaviriard:BAAALgADCgMJAwAAAA==.',
Ge='Gebran:BAAALgAECgEJAQAAAA==.Gellywoo:BAABLgAECn9BAAIZAAkJdB9ZDQCYAgAZAAkJdB9ZDQCYAgAAAA==.Genmaitcha:BAAALgADCgEJAQAAAA==.',
Gh='Ghostofonyx:BAAALgADCgcJFQAAAA==.',
Gi='Girlypop:BAAALgAECgQJBgAAAA==.',
Go='Golaoth:BAABLgAECn8lAAMTAAkJtxdUBwCDAgATAAkJtxdUBwCDAgAhAAEJCQFdLQAKAAAAAA==.Gooftoo:BAABLgAECn8UAAIDAAcJKB8QLwDwAQADAAcJKB8QLwDwAQAAAA==.',
Gr='Grawn:BAAALgADCgUJBgAAAA==.Greycie:BAAALgADCgkJEwABLgAECggJEgAaAAAAAA==.Greyfax:BAAALgADCgcJDQAAAA==.Greymoon:BAABLgAECn81AAIcAAgJGhkgDwDzAQAcAAgJGhkgDwDzAQAAAA==.Grimfu:BAAALgAECgYJCAABLgAECgkJHQAGAEoeAA==.',
Gu='Guigondk:BAAALgAFFAcJAQAAAA==.',
Gy='Gyre:BAABLgAECn8dAAIMAAcJ6hBfbABoAQAMAAcJ6hBfbABoAQAAAA==.',
Ha='Haezi:BAAALgAECggJDQABLgAECgkJHwAiAEQUAA==.Happyendings:BAABLgAFFH8FAAIeAAIJ7QidNgBNAAAeAAIJ7QidNgBNAAAAAA==.',
He='Helbafx:BAAALgAECgcJEAAAAA==.',
Hi='Hiroshì:BAAALgAECgEJAQAAAA==.',
Ho='Homewrecker:BAABLgAECn8cAAIRAAgJ2RKhGgBkAQARAAgJ2RKhGgBkAQAAAA==.',
Hu='Hunnee:BAAALgADCgkJFAAAAA==.Huské:BAAALgAECgcJCAAAAA==.',
Ic='Icelace:BAAALgAECgEJAQAAAA==.Icemàn:BAABLgAECn8aAAIjAAcJ0A02AgBBAQAjAAcJ0A02AgBBAQAAAA==.',
If='Ifearnobeer:BAABLgAECn81AAMNAAkJggrCOgBLAQANAAkJggrCOgBLAQALAAIJZwiYxwBGAAAAAA==.',
Ii='Iifelike:BAAALgAECgUJBQABLgAECgkJFQAHAN4PAA==.',
In='Inters:BAAALgAECgUJDgAAAA==.',
Ir='Ironspark:BAAALgAECgcJEgAAAA==.',
Is='Isabel:BAACLgAFFH8QAAIDAAQJTwucOQDHAAADAAQJTwucOQDHAAAuAAQKfxUAAgMACAmEGC0kACoCAAMACAmEGC0kACoCAAAA.Isaetr:BAAALgAECggJDwAAAA==.',
Ja='Jackôdaniels:BAAALgADCgkJDgAAAA==.Jadus:BAAALgAECgMJAwAAAA==.Jaiantobea:BAABLgAECn8xAAILAAkJ3x20CAAmAwALAAkJ3x20CAAmAwAAAA==.Jake:BAAALgAECgIJAgAAAA==.Jakulista:BAAALgADCgcJFQAAAA==.Jashugan:BAAALgADCgQJBAAAAA==.Jawn:BAABLgAECn8iAAIOAAkJ4g4UJACSAQAOAAkJ4g4UJACSAQAAAA==.Jaycie:BAAALgAECggJEgAAAA==.',
Je='Jessuss:BAABLgAECn8mAAIGAAkJDxOBcACNAQAGAAkJDxOBcACNAQAAAA==.',
Jh='Jha:BAAALgAECgEJAQAAAA==.',
Ju='Jude:BAAALgAECgUJCgAAAA==.Juggernàut:BAAALgAECgYJEAAAAA==.Julïeth:BAAALgAECgEJAQAAAA==.Junipermoon:BAAALgADCggJHQAAAA==.',
Ka='Kajas:BAAALgAECgMJAwAAAA==.Kalahandra:BAACLgAFFH8FAAIDAAMJqQOaTwCDAAADAAMJqQOaTwCDAAAuAAQKfyoAAgMACQnTEIs1AMQBAAMACQnTEIs1AMQBAAAA.Kalebeesd:BAABLgAECn8uAAIXAAgJXByeIgBGAgAXAAgJXByeIgBGAgAAAA==.Karthdh:BAAALgADCgcJDgABLgADCggJCAAaAAAAAA==.Kasey:BAAALgAECgEJAQAAAA==.Katithianna:BAAALgADCgQJAwAAAA==.Katotan:BAABLgAECn8jAAIDAAgJKhdLAwA9AQADAAgJKhdLAwA9AQAAAA==.Kawk:BAABLgAECn8uAAIHAAkJWx+LBAC7AgAHAAkJWx+LBAC7AgAAAA==.Kazatreshan:BAAALgADCgcJDgAAAA==.Kazragor:BAACLgAFFH8NAAINAAQJbCKCFAB7AQANAAQJbCKCFAB7AQAuAAQKfyUAAg0ACAn5I/4OALcCAA0ACAn5I/4OALcCAAAA.',
Ke='Kealestra:BAAALgADCgYJBgAAAA==.Kebob:BAABLgAECn8VAAIHAAkJ3g8fGABdAQAHAAkJ3g8fGABdAQAAAA==.Kenziedadght:BAAALgAECgIJBQAAAA==.Keyboärd:BAABLgAECn8hAAIRAAgJ5BwhDgAJAgARAAgJ5BwhDgAJAgAAAA==.',
Ki='Kilo:BAAALgADCgEJAwAAAA==.Kippo:BAECLgAFFH8IAAIVAAUJJgURMwDRAAAVAAUJJgURMwDRAAAuAAQKfyMAAhUACAmWF0BKAFgCABUACAmWF0BKAFgCAAEuAAUUBwkVAAEAthEA.Kittylover:BAAALgAECgYJBgAAAA==.',
Kl='Klazarth:BAACLgAFFH8HAAIIAAMJMReHIgDgAAAIAAMJMReHIgDgAAAuAAQKfx4AAggACQmqHowNAKoCAAgACQmqHowNAKoCAAAA.',
Ko='Kombat:BAABLgAECn8iAAMZAAgJjB0FFQBHAgAZAAgJjB0FFQBHAgAkAAEJLhjyCABJAAAAAA==.Korllan:BAAALgAECgUJDgAAAA==.Kossnen:BAABLgAECn8WAAIeAAkJTh3XHgBsAgAeAAkJTh3XHgBsAgAAAA==.',
Kr='Krelivus:BAAALgAECgYJCwAAAA==.',
Ku='Kuda:BAABLgAECn8sAAIVAAkJDxQlQwASAgAVAAkJDxQlQwASAgAAAA==.Kuridis:BAAALgAECgEJAQAAAA==.',
Kw='Kwanu:BAABLgAECn8eAAIPAAgJFw1HRABbAQAPAAgJFw1HRABbAQAAAA==.',
['Kó']='Kóñä:BAAALgADCgkJDAABLgAECgkJEAAaAAAAAA==.',
La='Lamue:BAAALgAECgIJAgAAAA==.Lantern:BAAALgADCgYJCwAAAA==.Larke:BAAALgAECgUJBwAAAA==.Lasa:BAAALgAECgYJCQABLgAECgcJEAAaAAAAAA==.Lasloo:BAABLgAECn8eAAIGAAYJgBCwkQBPAQAGAAYJgBCwkQBPAQAAAA==.Laylani:BAABLgAECn8iAAIHAAkJ+RGADwDLAQAHAAkJ+RGADwDLAQAAAA==.Layllis:BAAALgADCgQJBgAAAA==.',
Le='Legiondary:BAABLgAECn8cAAIXAAkJ8Rc7LgBEAgAXAAkJ8Rc7LgBEAgAAAA==.Lesabor:BAAALgADCgYJBgAAAA==.',
Li='Licknstick:BAAALgAECgUJCAAAAA==.Lir:BAAALgADCgIJAwAAAA==.Lisan:BAABLgAECn8hAAIlAAkJ4RYjAgBMAgAlAAkJ4RYjAgBMAgAAAA==.Lisanalgaib:BAAALgAECgEJAgAAAA==.Littledicey:BAAALgADCgcJCwAAAA==.',
Lo='Lokin:BAAALgADCgIJAgAAAA==.Lothan:BAAALgADCgkJCQABLgAECgkJHwAEAAESAA==.Lotuss:BAABLgAECn8dAAMPAAYJexlQBwAHAQAPAAYJexlQBwAHAQAOAAEJNgPYwAAXAAABLgAFFAMJDAANAIwJAA==.',
Lu='Lucien:BAAALgAECgYJEQAAAA==.Luciä:BAABLgAECn8nAAIgAAkJBhKxFQC+AQAgAAkJBhKxFQC+AQAAAA==.Lucymoon:BAAALgAECgYJBQAAAA==.',
Ly='Lynex:BAAALgAECgQJBwAAAA==.',
Ma='Machoman:BAAALgAECgQJBAAAAA==.Madness:BAAALgAECgMJAwAAAA==.Magdeth:BAAALgAECgMJAwAAAA==.Magiann:BAAALgADCgEJAQAAAA==.Maiama:BAAALgAECgYJBwAAAA==.Marabelle:BAABLgAECn8cAAIEAAkJCgreMwBJAQAEAAkJCgreMwBJAQAAAA==.Massack:BAABLgAECn8jAAIiAAkJ9xeiEAA3AgAiAAkJ9xeiEAA3AgAAAA==.Mastik:BAAALgAECgEJAQAAAA==.Maximusblood:BAAALgADCgIJAgAAAA==.',
Mc='Mcknight:BAAALgAECgYJBgAAAA==.',
Me='Merex:BAAALgADCgEJAQAAAA==.Mero:BAAALgAECgYJBgAAAA==.Mew:BAAALgADCgEJAQABLgAECggJHwAKAJ0XAA==.',
Mi='Midgetmàniàc:BAAALgAECgMJBAAAAA==.Mikebeard:BAAALgAECgIJBQAAAA==.Mikereport:BAAALgAECgIJAgAAAA==.Misfire:BAAALgAECggJCgABLgAECgkJHAADAKkTAA==.',
Mo='Moktar:BAAALgAECgYJBwAAAA==.Moobear:BAAALgADCgQJCwAAAA==.',
Mu='Muldoinit:BAABLgAECn8jAAIOAAkJYhibEwAfAgAOAAkJYhibEwAfAgAAAA==.',
My='Myroslava:BAAALgAECgMJAwAAAA==.Mystrall:BAAALgAECgYJBgAAAA==.',
['Më']='Mërikh:BAAALgADCggJEQABLgAECgUJCwAaAAAAAA==.',
Na='Nadorian:BAAALgAECgEJAQAAAA==.',
Ne='Neb:BAABLgAECn8mAAIKAAgJ/SM1BgAqAwAKAAgJ/SM1BgAqAwAAAA==.Nehemia:BAAALgAECgYJEQAAAA==.Nerilestis:BAAALgAECgEJAQAAAA==.Netherrogue:BAACLgAFFH8NAAMjAAQJiRwYFQBiAQAjAAQJIRsYFQBiAQAmAAMJoRfsCADsAAAuAAQKfyMABCYACQntHe4GANkBACYABglmGu4GANkBACcABQnNHSkJALABACMABgkgFfYmAF8BAAAA.',
Ni='Nicage:BAAALgAECgQJBAABLgAFFAQJEAAVAOMZAA==.Nightdreams:BAAALgADCgcJCQAAAA==.',
Ny='Nytelytë:BAAALgAECgYJCQABLgAFFAMJBwAeAG8TAA==.Nytemayer:BAACLgAFFH8HAAIeAAMJbxM7eQDQAAAeAAMJbxM7eQDQAAAuAAQKfysABB4ACQmIIGMaAIYCAB4ACQl+H2MaAIYCAB0AAwmYH4szAOkAAB8AAQkAAC4pAE0AAAAA.',
['Nö']='Nöx:BAAALgADCgEJAQAAAA==.',
Ob='Obmakare:BAABLgAECn81AAICAAgJlhXsDgDGAQACAAgJlhXsDgDGAQAAAA==.Obonhigh:BAAALgAECgUJBQAAAA==.Oboñ:BAABLgAECn8lAAMfAAgJzw8RDQCLAQAfAAgJzw8RDQCLAQAeAAEJYwPyYgEeAAAAAA==.Obsfuyung:BAABLgAECn8zAAIOAAgJlhToIACmAQAOAAgJlhToIACmAQAAAA==.',
On='Onkelos:BAAALgAECgEJAwAAAA==.',
Oo='Oopsiez:BAAALgAECgQJBAAAAA==.',
Or='Orcc:BAAALgAECgEJAgAAAA==.',
Pa='Paley:BAAALgAECgYJCgAAAA==.Palpatine:BAAALgAECgIJAgAAAA==.',
Pe='Peopleperson:BAAALgADCgQJAQAAAA==.Performance:BAAALgAECgcJEAAAAA==.Peterturbo:BAAALgAECgQJBAABLgADCgcJDQAaAAAAAA==.',
Pi='Piezoori:BAAALgADCgcJBgAAAA==.Pinji:BAAALgAECgIJAgAAAA==.Pinkky:BAAALgADCgkJCQAAAA==.Pinkypoo:BAABLgAECn8rAAMBAAkJmxbXPAAOAgABAAkJiBPXPAAOAgAgAAYJvBixIwAjAQAAAA==.',
Pl='Plato:BAABLgAECn8vAAQKAAkJdxtDFwBQAgAKAAgJrBtDFwBQAgAGAAIJ9wiwWgFXAAAHAAEJAAC1DAAAAAAAAA==.',
Po='Poiet:BAAALgAECgEJAgAAAA==.Poîsonivy:BAABLgAECn8oAAMdAAkJChVkBgD7AQAdAAkJChVkBgD7AQAeAAEJNgFtaQENAAAAAA==.',
Ps='Psyche:BAAALgADCgkJDgAAAA==.Psyrine:BAAALgAECgUJCgAAAA==.',
Py='Pyrokast:BAAALgAECgUJBQAAAA==.Pyrokos:BAACLgAFFH8GAAIVAAMJUBlwfwDYAAAVAAMJUBlwfwDYAAAuAAQKfyEAAhUACAnsIDliABUCABUACAnsIDliABUCAAAA.Pyrö:BAAALgAECgkJCQAAAA==.',
Qu='Qu:BAABLgAECn84AAMkAAkJkiFvBgBlAgAkAAkJkiFvBgBlAgAZAAIJTQowlQBrAAAAAA==.Quellia:BAACLgAFFH8XAAIKAAUJWhvtFgBvAQAKAAUJWhvtFgBvAQAuAAQKfyIAAgoACQn8HdMMALMCAAoACQn8HdMMALMCAAAA.',
Ra='Rangel:BAABLgAECn8YAAIZAAgJ7BArQQBAAQAZAAgJ7BArQQBAAQAAAA==.Rattlesnake:BAAALgADCgYJBgAAAA==.Razziels:BAAALgAECgYJBwAAAA==.',
Re='Redacted:BAAALgADCgMJAwAAAA==.Renägäde:BAAALgAECgYJDwAAAA==.Rexulti:BAAALgAECgEJAQAAAA==.',
Ri='Ricodadawg:BAAALgADCgEJAQAAAA==.Rizen:BAAALgAECgQJBAAAAA==.',
Ro='Roija:BAACLgAFFH8QAAIVAAQJ4xlYVwAuAQAVAAQJ4xlYVwAuAQAuAAQKfygAAhUACQlDJRIKACkDABUACQlDJRIKACkDAAAA.Roshak:BAAALgADCgYJCQAAAA==.',
Ru='Runningbearr:BAAALgADCgYJCgAAAA==.Runningmage:BAAALgADCgcJDAAAAA==.Rurahk:BAACLgAFFH8XAAIGAAYJtBFaJgBwAQAGAAYJtBFaJgBwAQAuAAQKfy4AAgYACAkEIaIVAOgCAAYACAkEIaIVAOgCAAAA.',
['Rõ']='Rõbb:BAACLgAFFH8HAAIGAAMJVR6mXAD3AAAGAAMJVR6mXAD3AAAuAAQKfywAAgYACQkGIpsOABkDAAYACQkGIpsOABkDAAAA.',
Sa='Sabaak:BAABLgAECn8sAAIGAAgJZCEwGwChAgAGAAgJZCEwGwChAgAAAA==.Sacerdote:BAAALgADCgUJBQAAAA==.Saeriin:BAABLgAECn9DAAIeAAkJJRLwAwBeAQAeAAkJJRLwAwBeAQAAAA==.Saintsnyder:BAABLgAECn8dAAIGAAYJ5xMKpAAxAQAGAAYJ5xMKpAAxAQAAAA==.Saithis:BAABLgAECn8UAAIDAAYJmBBIbgDpAAADAAYJmBBIbgDpAAAAAA==.Saltycrank:BAAALgADCgYJBgAAAA==.Sandew:BAAALgAECgcJEAAAAA==.Sanorasong:BAEBLgAECn8gAAMKAAkJ7Bd3FwBOAgAKAAkJ7Bd3FwBOAgAGAAUJPhQGxwD/AAAAAA==.Saphaa:BAAALgADCgEJAQAAAA==.Sardine:BAAALgAECgcJDAAAAA==.Sarylin:BAABLgAECn8YAAMMAAkJbxoGHgBxAgAMAAkJbxoGHgBxAgAQAAQJdQhqYwCzAAAAAA==.Satanshealer:BAAALgADCgYJCQAAAA==.Satansshadow:BAAALgAECgEJAQAAAA==.Sathpriest:BAAALgAECgIJAgAAAA==.Satsuki:BAAALgAECgYJCgAAAA==.',
Sc='Schio:BAABLgAECn81AAIdAAgJ9xZjBwDfAQAdAAgJ9xZjBwDfAQAAAA==.',
Se='Sean:BAAALgADCgYJBgAAAA==.Seananagíns:BAAALgAFFAIJAgAAAA==.Sections:BAAALgADCgkJHAAAAA==.Semilla:BAAALgADCgEJAQAAAA==.Severussnape:BAABLgAECn8jAAMeAAkJqQneYgB5AQAeAAkJnAneYgB5AQAdAAEJ6gpVQwAnAAAAAA==.',
Sh='Shambs:BAACLgAFFH8HAAILAAMJKx4WPwDoAAALAAMJKx4WPwDoAAAuAAQKfxsAAgsACQnPHikGAA8DAAsACQnPHikGAA8DAAAA.Shamrorag:BAABLgAECn8bAAMNAAgJLgrSRAAgAQANAAgJLgrSRAAgAQAFAAMJ2wO2NQBZAAAAAA==.Shehealz:BAAALgAECgEJAgAAAA==.Shinron:BAAALgAECgEJAQAAAA==.Shökan:BAAALgAECgQJBwAAAA==.',
Si='Sighah:BAAALgAECgkJEgAAAA==.Simlockdr:BAAALgADCgYJBgAAAA==.Sinensis:BAABLgAECn8bAAMnAAkJpRWtBQAaAgAnAAkJTBWtBQAaAgAjAAEJnBvxCABTAAAAAA==.Singood:BAAALgAECgcJBwAAAA==.Sinnecro:BAABLgAECn8aAAIBAAkJ4h5nIADAAgABAAkJ4h5nIADAAgAAAA==.Sinshift:BAAALgADCgUJBQAAAA==.Sinstab:BAAALgAECggJCAAAAA==.',
Sk='Skadoosh:BAAALgAECgUJCgABLgAECgkJHQAXALggAA==.Skarletbolt:BAAALgAECgUJBQAAAA==.Skarletflame:BAABLgAECn8aAAIYAAkJnRg/DQBRAgAYAAkJnRg/DQBRAgAAAA==.Skinalittleb:BAAALgAECgEJAQAAAA==.',
Sl='Slather:BAABLgAECn8aAAITAAgJcBAKGADVAQATAAgJcBAKGADVAQAAAA==.Slaycie:BAABLgAECn8jAAIVAAgJtBBUdgCNAQAVAAgJtBBUdgCNAQAAAA==.Slayerdude:BAAALgAECgEJAQAAAA==.Slofinger:BAAALgADCgYJCgAAAA==.',
Sn='Sneeb:BAAALgAECgEJAQAAAA==.Snugglebus:BAABLgAECn8WAAIWAAcJAQXKGwC9AAAWAAcJAQXKGwC9AAAAAA==.',
So='Songli:BAEALgADCgEJAQABLgAECgkJIAAKAOwXAA==.Sorne:BAEBLgAFFH8GAAILAAUJbRMyLgApAQALAAUJbRMyLgApAQABLgAFFAMJDwALAGwlAA==.',
Sp='Spaghett:BAABLgAECn8fAAMiAAkJRBRLJwB2AQAiAAkJphFLJwB2AQAOAAYJJhOlRADtAAAAAA==.Springtotem:BAABLgAECn8fAAIEAAkJARKKJACnAQAEAAkJARKKJACnAQAAAA==.',
St='Stachel:BAAALgAECgUJBwAAAA==.Stanger:BAABLgAECn8mAAILAAkJPx7xCQAWAwALAAkJPx7xCQAWAwAAAA==.Storaxota:BAAALgAFFAgJBAAAAA==.Stormdk:BAAALgADCgcJCQAAAA==.',
Su='Superneo:BAAALgAECgYJBgABLgAFFAMJCgAEAOciAA==.Suvion:BAAALgAECgcJEwABLgAFFAMJDAANAIwJAA==.',
Sy='Sylinial:BAAALgAECgEJAQAAAA==.Sylvanis:BAAALgAECgUJBwAAAA==.Syrden:BAABLgAECn8WAAIDAAkJ6AvaQACOAQADAAkJ6AvaQACOAQAAAA==.',
Sz='Szadèk:BAAALgAECgYJBwAAAA==.',
['Sÿ']='Sÿphallus:BAABLgAECn8SAAIYAAgJshSyIQBrAQAYAAgJshSyIQBrAQAAAA==.',
Ta='Tael:BAABLgAECn8tAAIZAAkJzR+RCwCvAgAZAAkJzR+RCwCvAgAAAA==.Tagreth:BAAALgADCgQJBAAAAA==.Tangylizard:BAACLgAFFH8ZAAIoAAQJKBOhJgAVAQAoAAQJKBOhJgAVAQAuAAQKfy8ABCgACAliG1UTAEYCACgACAliG1UTAEYCAAkAAQkFFq57ADoAAAgAAQkZDAeOACwAAAAA.Tattoospyder:BAABLgAECn8aAAIDAAcJTwi4dwDPAAADAAcJTwi4dwDPAAAAAA==.Tatyanafour:BAAALgADCgIJAQAAAA==.Tatyanathirt:BAAALgADCgYJBgAAAA==.',
Te='Terrenn:BAAALgADCggJCAAAAA==.Tessla:BAACLgAFFH8MAAINAAMJjAmHDgC1AAANAAMJjAmHDgC1AAAuAAQKf0wAAw0ACQmvHJYNAI8CAA0ACQmvHJYNAI8CAAsAAgm+CHnKAEMAAAAA.Tetragram:BAAALgAECgUJBgABLgAFFAMJCQAFAFodAA==.',
Th='Thafrggnpope:BAAALgADCgEJAQAAAA==.Thelarï:BAABLgAECn8jAAIMAAkJRgr4VQCiAQAMAAkJRgr4VQCiAQAAAA==.Thellany:BAAALgAECgEJAQAAAA==.Theshiznitz:BAAALgAECgQJBAAAAA==.Thors:BAABLgAECn8dAAIGAAcJSh43MgBZAgAGAAcJSh43MgBZAgAAAA==.Thundertoes:BAABLgAECn8jAAMLAAkJexylDgDeAgALAAkJexylDgDeAgAFAAYJChJzHwD+AAAAAA==.Thÿsucc:BAAALgADCgcJBwAAAA==.',
Ti='Tia:BAAALgAECgEJAQAAAA==.Timmy:BAAALgAECgMJCAABLgAECgkJAgAaAAAAAA==.',
To='Tommychong:BAAALgAECgIJAgAAAA==.Tonik:BAABLgAECn8qAAMLAAcJ2RQIPwCyAQALAAcJ2RQIPwCyAQANAAcJChAaQQAwAQAAAA==.Torgoth:BAABLgAECn8oAAIFAAkJpRTkCQAeAgAFAAkJpRTkCQAeAgAAAA==.Toshido:BAABLgAECn8VAAIMAAYJWhD9oAAAAQAMAAYJWhD9oAAAAQAAAA==.',
Tr='Traetor:BAABLgAECn8kAAIEAAkJDib2AAB7AwAEAAkJDib2AAB7AwAAAA==.Trakker:BAAALgADCgQJBAAAAA==.Trevize:BAABLgAECn8YAAIGAAYJ3Aec5wDUAAAGAAYJ3Aec5wDUAAAAAA==.',
Tt='Ttelloc:BAAALgADCgIJAgAAAA==.',
Tu='Tusiny:BAAALgAECgEJAQAAAA==.',
Ub='Ubully:BAAALgAECgEJAQAAAA==.',
Ul='Ultane:BAABLgAECn8lAAILAAgJrA4KRwCSAQALAAgJrA4KRwCSAQAAAA==.',
Un='Unreal:BAAALgADCgQJBAAAAA==.',
Va='Vaera:BAAALgAECgEJAQAAAA==.Valastae:BAABLgAECn8ZAAIMAAgJYQxSaQBwAQAMAAgJYQxSaQBwAQAAAA==.Valiantaine:BAABLgAECn8wAAMGAAkJXiFzKgB6AgAGAAkJXiFzKgB6AgAKAAkJgg2xPQCCAQABLgAFFAQJGAAXANAcAA==.Valiantaint:BAACLgAFFH8YAAIXAAQJ0Bx8NQBPAQAXAAQJ0Bx8NQBPAQAuAAQKfzAAAhcACQk/HtYVAJUCABcACQk/HtYVAJUCAAAA.Valiantrain:BAAALgAECgEJAgABLgAFFAQJGAAXANAcAA==.Valyulon:BAAALgADCgMJAwABLgAFFAQJGAAXANAcAA==.Vanjin:BAAALgADCgUJBQAAAA==.',
Ve='Vecna:BAAALgAECgYJCAAAAA==.Velherun:BAABLgAECn8dAAIGAAkJYh/zFADFAgAGAAkJYh/zFADFAgAAAA==.Vendeldh:BAABLgAECn8sAAIXAAkJuCPUEgDpAgAXAAkJuCPUEgDpAgAAAA==.Veni:BAAALgAECgYJBgAAAA==.Vexxaa:BAABLgAECn8lAAIMAAkJUhFVOgD1AQAMAAkJUhFVOgD1AQAAAA==.',
Vi='Vincentio:BAAALgAECgEJAQAAAA==.Virajr:BAABLgAECn8oAAMjAAgJ0RUAFgDvAQAjAAgJ0RUAFgDvAQAmAAEJvAQAKgAgAAAAAA==.Vishus:BAAALgADCgUJBQAAAA==.Visiôn:BAABLgAECn8bAAIZAAkJ8wcAQQBBAQAZAAkJ8wcAQQBBAQAAAA==.Vissiction:BAABLgAECn8ZAAIXAAkJvxZiLQASAgAXAAkJvxZiLQASAgAAAA==.Vistine:BAACLgAFFH8JAAIHAAMJywyRAwCMAAAHAAMJywyRAwCMAAAuAAQKf0wAAgcACQleEWEBAH4BAAcACQleEWEBAH4BAAEuAAUUAwkMAA0AjAkA.Vitez:BAABLgAECn8WAAMdAAkJrAaAHQC8AAAdAAgJFAeAHQC8AAAeAAIJRAPjGgFNAAAAAA==.',
Vo='Voidscar:BAAALgADCgcJBwAAAA==.',
Wa='Warhurts:BAAALgAECgMJAwAAAA==.Waterbloom:BAAALgADCgMJAwAAAA==.',
We='Weave:BAABLgAECn8iAAIVAAcJUgyKqQAsAQAVAAcJUgyKqQAsAQAAAA==.Wendy:BAABLgAECn8pAAILAAgJ1RiONwDSAQALAAgJ1RiONwDSAQABLgAECgkJHAADAKkTAA==.',
Wi='Win:BAACLgAFFH8HAAMEAAQJ9QbBLQDRAAAEAAQJ9QbBLQDRAAADAAEJaAwAAAAAAAAuAAQKfycAAwMABwnjGlolACICAAMABwnjGlolACICAAQABglzHdcCAEcBAAAA.Winkster:BAACLgAFFH8MAAIGAAUJWRySOQA5AQAGAAUJWRySOQA5AQAuAAQKfzAAAgYACQn4JIEKABMDAAYACQn4JIEKABMDAAAA.',
Xa='Xanadu:BAACLgAFFH8HAAIoAAIJkxP/EQCJAAAoAAIJkxP/EQCJAAAuAAQKfzgAAigACQlMHsIGABIDACgACQlMHsIGABIDAAAA.Xarinia:BAABLgAECn8rAAMUAAkJDRIDHgDnAQAUAAkJDRIDHgDnAQATAAUJ4weUMQDjAAAAAA==.',
Xb='Xbear:BAABLgAECn8lAAIcAAkJthzqBwByAgAcAAkJthzqBwByAgABLgAFFAYJFQAjACgXAA==.',
Xd='Xdynasty:BAACLgAFFH8VAAIjAAYJKBeHEACQAQAjAAYJKBeHEACQAQAuAAQKfycAAyMACQkCJCwMANUCACMACQn/IywMANUCACcABgnDG+UNADwBAAAA.',
Xo='Xo:BAABLgAECn86AAQeAAkJmhmXJgBDAgAeAAkJLxiXJgBDAgAdAAUJGBR5JQAxAQAfAAIJVgtDMAA9AAABLgAFFAQJBwAEAPUGAA==.',
Xy='Xyfarion:BAAALgADCgYJBgAAAA==.Xyril:BAAALgAECgEJAQAAAA==.',
Ya='Yaasnah:BAAALgADCggJCAAAAA==.',
Za='Zabazz:BAACLgAFFH8HAAILAAMJAhEVGgCBAAALAAMJAhEVGgCBAAAuAAQKfykAAwsACQnOEDQ8AL4BAAsACQnOEDQ8AL4BAA0ABAnJCB+EAGgAAAAA.Zabenir:BAABLgAECn8iAAIIAAkJ7hwuCwCdAgAIAAkJ7hwuCwCdAgAAAA==.Zané:BAAALgAECgEJAgAAAA==.Zapan:BAAALgADCgUJBQAAAA==.',
Ze='Zeverai:BAAALgADCgkJCgAAAA==.',
Zi='Ziria:BAAALgADCgQJCwAAAA==.',
Zo='Zonni:BAAALgADCgYJBgAAAA==.Zorusii:BAAALgAECgQJBQABLgAECgkJHQAXALggAA==.',
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
