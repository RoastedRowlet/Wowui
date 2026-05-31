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

local lookup = {'Paladin-Retribution','Warlock-Demonology','Druid-Restoration','Unknown-Unknown','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Devastation','Evoker-Preservation','Shaman-Elemental','Shaman-Restoration','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Monk-Brewmaster','DeathKnight-Unholy','Hunter-BeastMastery','Priest-Discipline','Evoker-Augmentation','Priest-Holy','Warrior-Fury','Druid-Guardian','Hunter-Survival','Hunter-Marksmanship','Druid-Balance','DemonHunter-Havoc','Mage-Frost','Monk-Mistweaver','Monk-Windwalker','Warlock-Destruction','Druid-Feral','Warlock-Affliction','Rogue-Subtlety','Priest-Shadow','Warrior-Protection','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abhanfnahwa:BAAALgADCgUJBQAAAA==.Abort:BAABLgAECn8ZAAIBAAcJtR3iRwDXAQABAAcJtR3iRwDXAQAAAA==.',
Ac='Acbabcaa:BAAALgAECgQJBAAAAA==.Acefighter:BAAALgADCgMJAwAAAA==.Aceon:BAABLgAECn8nAAIBAAgJbBpJNQATAgABAAgJbBpJNQATAgAAAA==.Aceonarcher:BAAALgADCgMJAwAAAA==.',
Ad='Adfectia:BAABLgAECn8XAAICAAkJbQYOcABPAQACAAkJbQYOcABPAQAAAA==.',
Ae='Aelianna:BAABLgAECn8bAAIDAAgJ7hudFgB/AgADAAgJ7hudFgB/AgAAAA==.Aelinjr:BAAALgAECgEJAQAAAA==.Aelsa:BAAALgADCgYJCgABLgAECgUJDAAEAAAAAA==.Aelyt:BAAALgAECgQJDgAAAA==.Aesirkin:BAAALgAECgIJBQAAAA==.Aeth:BAABLgAECn8gAAIFAAkJayHcBQDeAgAFAAkJayHcBQDeAgAAAA==.Aethér:BAAALgAECgEJAQABLgAFFAcJHQADAOgYAA==.',
Ag='Agiel:BAAALgADCgYJBgAAAA==.Agilities:BAAALgADCgYJBgAAAA==.',
Ah='Ahsokä:BAAALgAECgQJBwAAAA==.',
Ak='Akuaku:BAAALgADCgEJAQAAAA==.',
Al='Alcool:BAAALgAECgIJAgAAAA==.Alderaan:BAAALgAECgMJAwAAAA==.Alexhya:BAAALgAECgEJAQAAAA==.Alexjones:BAAALgADCgUJBwAAAA==.Alganeth:BAAALgADCggJCAAAAA==.Aliand:BAAALgAECgIJAgAAAA==.Aliande:BAAALgADCgUJBQAAAA==.Alleraz:BAAALgADCgEJAQAAAA==.Alnethir:BAAALgAECgEJAQAAAA==.Aloray:BAAALgADCgcJCwAAAA==.Alordis:BAAALgADCgMJAwAAAA==.Alsou:BAAALgAECgEJAQAAAA==.Alvarah:BAAALgADCgMJAwAAAA==.Alynas:BAABLgAECn8fAAIDAAkJoA+0QwBuAQADAAkJoA+0QwBuAQAAAA==.Alysona:BAABLgAECn8WAAMGAAgJhhz8PAC8AQAGAAcJDBz8PAC8AQAHAAEJZR9DJQBaAAAAAA==.',
Am='Amahra:BAAALgAECgQJBwAAAA==.Amelio:BAAALgADCgIJAgAAAA==.Amethysztra:BAAALgADCgUJBQAAAA==.Amewow:BAACLgAFFH8IAAIIAAIJJRpuBwCrAAAIAAIJJRpuBwCrAAAuAAQKfx8AAwgACAmSG0oFAPsBAAgACAmSG0oFAPsBAAkABAnmD/whAMsAAAAA.Amìko:BAAALgAECgMJAwAAAA==.',
An='Anadoria:BAAALgADCgYJBgAAAA==.Analferret:BAABLgAECn8VAAMKAAYJkQ1SSwDrAAAKAAYJkQ1SSwDrAAALAAMJNAoHhACEAAAAAA==.Anastæsia:BAAALgADCgYJBwABLgAECgMJAwAEAAAAAA==.Anda:BAAALgAECgUJCAAAAA==.Anitabidet:BAAALgADCgcJBwAAAA==.',
Ap='Apepi:BAAALgADCgcJBwAAAA==.Apolion:BAAALgADCgQJBAAAAA==.Apoundofcake:BAAALgAECgEJAQAAAA==.Appauling:BAAALgADCgYJBgAAAA==.',
Ar='Arclore:BAABLgAECn8WAAQMAAcJzxB9VwC/AAAMAAUJyQp9VwC/AAABAAUJkArK5QC4AAANAAEJYgHDVQARAAAAAA==.Argenor:BAAALgAECgUJCgAAAA==.Ariadni:BAABLgAECn8UAAILAAgJpA1+QgCHAQALAAgJpA1+QgCHAQAAAA==.Aricict:BAAALgAECgMJAwAAAA==.Ariella:BAAALgADCgEJAQAAAA==.Arlý:BAAALgAECgMJBQAAAA==.Aruneza:BAABLgAECn8xAAIJAAkJew85DwDGAQAJAAkJew85DwDGAQAAAA==.',
As='Asajj:BAAALgAECgYJEgAAAA==.Asharie:BAAALgADCgEJAQAAAA==.Ashcatchm:BAAALgADCgMJAwABLgAECgcJEQAEAAAAAA==.Ashergon:BAAALgAECgQJBAABLgAECggJGgALAHQkAA==.Asheriz:BAAALgAECggJDwABLgAECggJGgALAHQkAA==.Asherous:BAABLgAECn8aAAMLAAgJdCQrEQCuAgALAAgJdCQrEQCuAgAKAAEJbgxShgA0AAAAAA==.Ashiashi:BAAALgAECgEJAQABLgAECgkJIgABAAYjAA==.Ashomá:BAAALgADCgcJCAAAAA==.Ashtroglide:BAAALgAECggJDgABLgAECggJGgALAHQkAA==.Ashèr:BAAALgAECggJDwABLgAECggJGgALAHQkAA==.Askara:BAAALgAECgUJBQAAAA==.Astyria:BAAALgADCgUJBQAAAA==.Aszura:BAAALgADCgUJDwAAAA==.',
Au='Auntieshaman:BAAALgADCgEJAQAAAA==.Auranhis:BAAALgAECgEJAgAAAA==.Auriailas:BAAALgADCgcJCQAAAA==.Autoignition:BAAALgADCgMJAwAAAA==.',
Av='Avidel:BAAALgAECgcJEAAAAA==.Avryn:BAABLgAECn8WAAMOAAgJxhiiFgA1AQAOAAYJkxeiFgA1AQAKAAMJxhsaSgDwAAAAAA==.',
Ay='Ayilime:BAAALgAECgQJBQAAAA==.',
Ba='Badcompanytt:BAAALgADCgIJAgAAAA==.Bakeddh:BAAALgADCgMJAwAAAA==.Balør:BAAALgAECgMJAwABLgAECgkJMQAPAIgVAA==.',
Be='Beanvoid:BAAALgADCgYJBgAAAA==.Beardsaint:BAAALgADCgUJBQAAAA==.Beefini:BAAALgAECgMJAwABLgAECggJIQAQADwlAA==.Beenah:BAABLgAECn8aAAIRAAgJcAYidAA/AQARAAgJcAYidAA/AQAAAA==.Belethiel:BAAALgADCgEJAQAAAA==.Bellinopher:BAAALgADCggJFAABLgAECgkJKQASADwQAA==.Benafflock:BAAALgAECgYJBwAAAA==.Bence:BAAALgAECgMJBAABLgAECgkJJgATAJwWAA==.Benefitheals:BAAALgAECgUJBwAAAA==.Benefitpally:BAAALgAECgQJBwAAAA==.Benefitsham:BAAALgADCgYJBgAAAA==.',
Bi='Bigbibble:BAABLgAECn8aAAIUAAgJ0hTpLQCNAQAUAAgJ0hTpLQCNAQAAAA==.Birdien:BAAALgAECgYJBgAAAA==.',
Bl='Blackrose:BAAALgADCgIJAgABLgAECgkJGAANANIbAA==.Blamson:BAAALgADCgYJCgAAAA==.Bloodrain:BAABLgAECn8eAAIVAAgJmQzQNwBSAQAVAAgJmQzQNwBSAQAAAA==.Blubolt:BAAALgAECgQJBAAAAA==.',
Bo='Boomie:BAABLgAFFH8FAAIJAAQJTBUYFgASAQAJAAQJTBUYFgASAQAAAA==.Boopty:BAAALgADCgUJBAAAAA==.Booptyboop:BAAALgAECgQJEAAAAA==.Booptydo:BAAALgADCgcJCAAAAA==.Boris:BAAALgAECgEJAQAAAA==.Bowhawk:BAABLgAECn8XAAIRAAYJNgzSkgD/AAARAAYJNgzSkgD/AAAAAA==.Bozag:BAAALgADCgIJAgAAAA==.',
Br='Braiin:BAAALgAFFAIJBAABLgAFFAcJHQADAOgYAA==.Brakken:BAAALgADCgQJBAAAAA==.Brawll:BAAALgAECgMJBQAAAA==.Brazyn:BAAALgADCgYJBgAAAA==.Brevarda:BAACLgAFFH8GAAILAAIJ3xmbUACTAAALAAIJ3xmbUACTAAAuAAQKfzEAAwsACAk6HvYbAFECAAsACAk6HvYbAFECAAoABgloDbZMAOYAAAAA.Brokenmind:BAAALgAECgQJBAABLgAECgYJIAAUAOwYAA==.Brubble:BAAALgADCgMJAwAAAA==.Brugg:BAAALgADCgYJBgAAAA==.',
Bu='Bubbles:BAAALgADCgEJAQAAAA==.Bubblzmgee:BAABLgAECn82AAISAAkJihFkFQAPAgASAAkJihFkFQAPAgAAAA==.Bushmommy:BAAALgAFFAEJAQAAAA==.',
Ca='Cadence:BAAALgAECgEJAgAAAA==.Cadin:BAABLgAECn8VAAMLAAkJSxmPDQCvAgALAAkJSxmPDQCvAgAKAAcJYhdfLwCkAQAAAA==.Cakeman:BAAALgADCgUJBQAAAA==.Calehunter:BAAALgAECgYJBgAAAA==.Cameltotem:BAAALgAECgUJBAAAAA==.Capnblood:BAAALgAECgEJAgAAAA==.Capone:BAAALgAECgUJEAAAAA==.Carahz:BAABLgAECn8aAAIWAAcJWg99JQAAAQAWAAcJWg99JQAAAQAAAA==.Carindria:BAAALgAECgEJAgAAAA==.Cattiebrie:BAAALgAECgIJAwAAAA==.Caylavana:BAABLgAECn8qAAMXAAgJnBfUEwD7AQAXAAgJnBfUEwD7AQARAAIJCxF9rQBpAAAAAA==.',
Ce='Celaylria:BAABLgAECn8UAAIYAAYJ0AylFwDgAAAYAAYJ0AylFwDgAAAAAA==.',
Ch='Chabz:BAAALgAECgQJAwAAAA==.Chai:BAABLgAECn8rAAMZAAgJYR2SDwBPAgAZAAgJYR2SDwBPAgADAAYJ4hh8OQDAAQABLgAFFAUJFQATAFEcAA==.Chantille:BAAALgAECgEJAgAAAA==.Charmed:BAABLgAECn8UAAIaAAkJRRDcGwB8AQAaAAkJRRDcGwB8AQAAAA==.Charmíng:BAAALgAECgYJDAABLgAFFAQJCAAbAAYhAA==.Cheryll:BAAALgAECgUJBQAAAA==.Chunknörris:BAAALgAECgQJBAAAAA==.',
Ci='Cint:BAABLgAECn8aAAIVAAgJXQivPAA9AQAVAAgJXQivPAA9AQAAAA==.',
Cl='Clio:BAAALgAFFAIJBAAAAA==.Cloudedjade:BAABLgAECn8cAAINAAgJ7QczIAD4AAANAAgJ7QczIAD4AAAAAA==.',
Co='Coleybear:BAABLgAECn8UAAICAAgJgAQlmwD9AAACAAgJgAQlmwD9AAAAAA==.Condewit:BAAALgAECgEJAQAAAA==.Condragos:BAAALgAECgUJBQAAAA==.Copedh:BAAALgAECgQJBAABLgAECgkJLgAFAFkdAA==.Copedk:BAABLgAECn8uAAIFAAkJWR27BwCKAgAFAAkJWR27BwCKAgAAAA==.Copedogg:BAAALgADCgcJDgABLgAECgkJLgAFAFkdAA==.Copemonkk:BAAALgADCgMJAwABLgAECgkJLgAFAFkdAA==.Copepriest:BAAALgADCgkJCQABLgAECgkJLgAFAFkdAA==.Copeshamm:BAAALgAECgUJBQABLgAECgkJLgAFAFkdAA==.Corrode:BAAALgAECggJCQAAAA==.Covertm:BAAALgAECgcJEgAAAA==.Covertw:BAAALgADCgEJAQAAAA==.',
Cr='Craq:BAAALgAECgEJAgAAAA==.Crashedout:BAAALgADCgEJAgAAAA==.Crashknight:BAAALgAECgEJAQABLgAECgQJDAAEAAAAAA==.Crew:BAAALgAECgYJCQAAAA==.Cricky:BAAALgAECgEJAQAAAA==.Crims:BAABLgAECn8ZAAIJAAgJ5xYmDQDtAQAJAAgJ5xYmDQDtAQAAAA==.Crinke:BAAALgADCgEJAQAAAA==.',
Cu='Culture:BAAALgAECgYJEAAAAA==.',
Cy='Cybeldin:BAABLgAECn8zAAIYAAkJlwrdDwBDAQAYAAkJlwrdDwBDAQAAAA==.Cyberdemonxd:BAAALgADCgYJBwABLgAECgkJJAAQAHQSAA==.',
Da='Daadeedaa:BAACLgAFFH8KAAIbAAQJDxeBTgAzAQAbAAQJDxeBTgAzAQAuAAQKfzAAAhsACAkqJPAnAGQCABsACAkqJPAnAGQCAAAA.Daddysparey:BAABLgAECn8pAAIGAAgJhhU+PAC/AQAGAAgJhhU+PAC/AQAAAA==.Dagoba:BAAALgAECgMJAgAAAA==.Dakk:BAABLgAECn8/AAIbAAkJphcONAAwAgAbAAkJphcONAAwAgAAAA==.Dardeathicus:BAACLgAFFH8MAAIQAAQJPR6ZUwAuAQAQAAQJPR6ZUwAuAQAuAAQKfyAAAhAACQnNIIkoAJgCABAACQnNIIkoAJgCAAAA.Darderyag:BAABLgAECn8fAAIbAAgJHRu6OAAfAgAbAAgJHRu6OAAfAgAAAA==.Darek:BAABLgAECn8XAAIbAAYJlAobxADkAAAbAAYJlAobxADkAAAAAA==.Dariara:BAAALgAECgEJAQAAAA==.Darkbud:BAAALgADCggJEQAAAA==.Darkfeazer:BAAALgADCgEJAQAAAA==.Darkforge:BAAALgAECgYJBQAAAA==.Darkrife:BAAALgAECgQJBQAAAA==.Darmonkicus:BAAALgAFFAIJAgAAAA==.Daymann:BAAALgAECgYJBgAAAA==.Dazzan:BAAALgADCgUJBQAAAA==.',
De='Deadlocks:BAAALgADCgEJAQAAAA==.Deathhold:BAAALgAECgYJBwAAAA==.Debilitation:BAAALgADCgIJAgAAAA==.Dedrys:BAAALgAECgEJAQAAAA==.Deklan:BAAALgAECgEJAwAAAA==.Delsid:BAAALgAECgMJAwAAAA==.Demonsteven:BAAALgADCgcJCgAAAA==.Dependabull:BAAALgADCgYJCQABLgADCgcJBwAEAAAAAA==.Dernis:BAAALgAECgIJAwAAAA==.Deshaman:BAACLgAFFH8GAAIKAAMJoQ0rLADBAAAKAAMJoQ0rLADBAAAuAAQKfykAAgoACAk1GzEVACYCAAoACAk1GzEVACYCAAEuAAUUBQkYABEA4CAA.Devilbeast:BAAALgAECgQJDgAAAA==.',
Dh='Dhargo:BAAALgADCgcJBwAAAA==.',
Di='Dirte:BAAALgADCgYJDQAAAA==.Dirty:BAABLgAECn8eAAIKAAgJ5BOIJQDlAQAKAAgJ5BOIJQDlAQAAAA==.',
Dk='Dkbygorm:BAAALgADCgQJBwAAAA==.',
Do='Doctapheel:BAAALgAECgEJAgAAAA==.Dolfi:BAAALgADCggJDAAAAA==.Doomzday:BAAALgAECgEJAQAAAA==.Dorlesette:BAABLgAECn8kAAMcAAkJqwfPQwApAQAcAAkJqwfPQwApAQAPAAIJ7AK8fQA/AAAAAA==.',
Dr='Draiven:BAAALgAECgEJAQAAAA==.Dravindil:BAAALgAECgkJBgAAAA==.Dreamlesnite:BAABLgAECn8eAAICAAcJZAd9mAACAQACAAcJZAd9mAACAQAAAA==.Dreidelman:BAAALgAFFAIJAgAAAA==.Drkstar:BAAALgAECgYJCwAAAA==.',
Du='Dudeicus:BAAALgAECgUJBQAAAA==.Dunthur:BAAALgADCgYJBgAAAA==.Duoda:BAABLgAFFH8HAAIcAAQJSRdCGgBOAQAcAAQJSRdCGgBOAQABLgAFFAYJEQAJAMgRAA==.Durto:BAAALgAECgEJAgABLgAECgQJCAAEAAAAAA==.',
Dy='Dylora:BAABLgAECn80AAIcAAkJZBc6GAAxAgAcAAkJZBc6GAAxAgAAAA==.',
['Dï']='Dïesel:BAAALgAECgIJAgAAAA==.',
['Dó']='Dólores:BAAALgADCgYJBgAAAA==.',
['Dö']='Dödskott:BAAALgADCgkJDwAAAA==.',
Ec='Eclipsa:BAAALgAECgcJBwAAAA==.',
Eg='Egregore:BAABLgAECn8WAAIGAAcJ9A5xcQAkAQAGAAcJ9A5xcQAkAQAAAA==.',
El='Elassha:BAAALgAECgEJAQAAAA==.Ellaria:BAABLgAECn8yAAMGAAkJahjLKQANAgAGAAkJ6xbLKQANAgAaAAYJVhjlJQCQAQAAAA==.Elyselyia:BAAALgAECgUJBQAAAA==.Elysindrall:BAABLgAECn8lAAIJAAgJGxasCwAMAgAJAAgJGxasCwAMAgAAAA==.',
Em='Emokins:BAABLgAECn80AAIKAAkJPSS1AgA7AwAKAAkJPSS1AgA7AwAAAA==.Emouri:BAAALgADCgcJCwAAAA==.',
En='Endesh:BAABLgAECn80AAMTAAkJjwmkMgBJAQATAAkJjwmkMgBJAQAIAAMJ7QXMHQBPAAAAAA==.Enolah:BAAALgADCgMJAwAAAA==.',
Er='Eradica:BAAALgADCgYJDQAAAA==.Erelo:BAAALgADCgYJCAAAAA==.Erubus:BAACLgAFFH8PAAQPAAMJgCGJHAApAQAPAAMJgCGJHAApAQAcAAIJDxDzOwBuAAAdAAEJQwGZFAA9AAAuAAQKfxcABA8ACQmFIEQWAFcCAA8ACQmFIEQWAFcCABwAAgk2E/tWAHMAAB0AAQm/Ds95ADcAAAAA.Erubustin:BAAALgAECgQJBAAAAA==.Eryss:BAABLgAECn8bAAIRAAgJnAjAbABQAQARAAgJnAjAbABQAQAAAA==.',
Es='Escånor:BAAALgAECgYJBwAAAA==.Esmeraldita:BAAALgADCgYJDwAAAA==.',
Ev='Evercleâr:BAAALgADCgkJAgAAAA==.Evoked:BAABLgAECn8fAAMJAAgJzhKzDQDiAQAJAAgJzhKzDQDiAQAIAAUJdAVRGwBhAAAAAA==.',
Ex='Excentric:BAAALgAECgYJCgABLgAFFAcJEAAbAEsYAA==.Expiraman:BAAALgADCgYJBgAAAA==.',
Fa='Faeliel:BAAALgADCgYJBgABLgAFFAUJEwAVAEAbAA==.Faelýn:BAAALgAECggJEwAAAA==.Faessa:BAAALgADCgIJAgAAAA==.Falcone:BAAALgAECgcJBwAAAA==.Fanden:BAAALgADCgYJCQAAAA==.Fartimer:BAAALgADCgYJBgABLgAECgkJGwADAG0VAA==.',
Fd='Fdk:BAAALgAECgUJCAAAAA==.',
Fe='Feathering:BAAALgAECgYJEgAAAA==.Fellariene:BAAALgADCgcJCAAAAA==.Fellraiser:BAAALgAECgQJBwAAAA==.Feoralaure:BAAALgADCgEJAQAAAA==.',
Fi='Figjam:BAAALgAECgIJAgABLgAECggJHgAcAN0SAA==.Fistenlick:BAAALgADCgkJCQABLgAECgQJBAAEAAAAAA==.',
Fl='Flashylights:BAAALgAECgIJAwAAAA==.Fluoria:BAAALgAECgQJEgAAAA==.Flurple:BAAALgADCgQJBAAAAA==.Fláreon:BAABLgAECn8ZAAIMAAcJGhk9HQAsAgAMAAcJGhk9HQAsAgAAAA==.',
Fr='Fragarach:BAAALgAECgEJAQAAAA==.Frostynipie:BAAALgADCgMJAwAAAA==.Frutypebblz:BAABLgAECn8jAAIeAAYJKgqUGQDDAAAeAAYJKgqUGQDDAAAAAA==.',
Fu='Furrsure:BAAALgAECgEJAQAAAA==.Fuzznn:BAAALgAECgMJAwABLgABCgIJAgAEAAAAAA==.',
['Fà']='Fàmous:BAABLgAECn8YAAMSAAkJ6BaWGQDjAQASAAkJ/hKWGQDjAQAUAAIJvB4OYgCoAAAAAA==.',
Ga='Gainful:BAAALgAECgEJAQABLgAECgkJFAACABESAA==.Galabris:BAABLgAECn80AAIFAAkJRCSZAQA8AwAFAAkJRCSZAQA8AwAAAA==.Galen:BAAALgAECgEJAwAAAA==.',
Ge='Geranin:BAAALgADCgUJCAAAAA==.Gervire:BAAALgADCgcJCAAAAA==.',
Gh='Ghouldân:BAAALgAECgkJAQAAAA==.Ghoulmania:BAAALgAECgkJCwAAAA==.',
Gi='Gimglich:BAAALgADCgcJAwAAAA==.Gimligrimes:BAAALgADCgEJAQAAAA==.Ginx:BAAALgADCgMJBAAAAA==.Gitchusum:BAAALgAECgUJBgAAAA==.',
Gl='Glaedry:BAAALgAECgEJAwAAAA==.',
Go='Goose:BAABLgAECn8XAAISAAkJ5hEbIgCZAQASAAkJ5hEbIgCZAQAAAA==.Gorefang:BAAALgAECgEJAQAAAA==.Gormladin:BAABLgAECn8bAAIMAAgJzxScKACxAQAMAAgJzxScKACxAQAAAA==.',
Gr='Greenbahamut:BAAALgAECgEJAQAAAA==.Gregamesh:BAAALgADCgcJDgAAAA==.Grill:BAAALgAECgMJAwAAAA==.Grimsreaper:BAAALgADCgkJDgAAAA==.Grizzlypouch:BAAALgADCgYJBgAAAA==.Grouchy:BAAALgAECgIJAwAAAA==.',
Gu='Guillimus:BAAALgADCgcJBgAAAA==.Gultadorn:BAAALgADCgMJAwAAAA==.Guntherus:BAAALgADCgMJAwAAAA==.',
['Gï']='Gïzmö:BAABLgAECn8bAAIfAAcJ4AouHgDwAAAfAAcJ4AouHgDwAAAAAA==.',
Ha='Halfang:BAAALgADCgYJEQAAAA==.Handham:BAAALgAECgYJCgAAAA==.Hanroro:BAAALgADCgQJAwAAAA==.Hasheth:BAAALgAECgYJCQAAAA==.Havocfang:BAAALgAECgkJCgAAAA==.Hawkiing:BAAALgADCgQJBAAAAA==.Hazuki:BAAALgAECgQJBAAAAA==.',
He='Helouise:BAAALgADCgQJBAAAAA==.Herbalxur:BAAALgAECgQJCAAAAA==.',
Hi='Hibikase:BAAALgAECgYJBgAAAA==.Hildegarde:BAAALgAECgEJAQABLgAECgYJHgAGAL4fAA==.Hitpoints:BAAALgAECgUJEQABLgAECgYJIAAUAOwYAA==.',
Ho='Hobbikeen:BAABLgAECn8iAAMJAAgJ/hwFBgCZAgAJAAgJ/hwFBgCZAgATAAgJqg6wMQBPAQAAAA==.Holyhope:BAABLgAECn8XAAIMAAcJmhN4MwBwAQAMAAcJmhN4MwBwAQAAAA==.Holymana:BAABLgAECn8yAAIBAAcJsh6AOQAEAgABAAcJsh6AOQAEAgAAAA==.Hopet:BAAALgAECgUJBQABLgAECgkJNwALAHMjAA==.Hoshea:BAAALgADCgMJAwAAAA==.Hottyoreo:BAAALgADCgYJCwAAAA==.Howcom:BAAALgADCgcJBwAAAA==.',
Hu='Huffingpaint:BAAALgAECgYJEAABLgAECgYJHgAGAL4fAA==.Hundrakor:BAABLgAECn8UAAIRAAkJ6hLxLgAKAgARAAkJ6hLxLgAKAgAAAA==.Huntinghawk:BAAALgAECgEJAQABLgAECgYJFwARADYMAA==.Hutzil:BAABLgAECn8lAAMCAAkJuxzNIABTAgACAAkJchvNIABTAgAgAAQJGBpTGQDTAAAAAA==.Hutzilla:BAAALgAECgYJCgAAAA==.',
['Hÿ']='Hÿpothermia:BAAALgAECgMJAwAAAA==.',
Il='Illidianna:BAABLgAECn8fAAMGAAkJjBeVJgAdAgAGAAkJjBeVJgAdAgAaAAIJixJiXABvAAAAAA==.',
Im='Imbluedabdee:BAAALgADCgQJBwAAAA==.Imitlol:BAAALgAFFAEJAQAAAA==.',
In='Inception:BAAALgADCgkJFAAAAA==.',
Ir='Irrefutable:BAAALgADCgQJBAAAAA==.',
It='Itchynyple:BAAALgADCggJCAAAAA==.',
Ja='Jabadabadoo:BAAALgAECgEJAQAAAA==.Jables:BAAALgADCgQJBAABLgAECgkJJgAdAO4lAA==.Jackatak:BAAALgADCgMJAwAAAA==.Jacoblack:BAAALgADCgMJAwAAAA==.Jadin:BAAALgADCgEJAQAAAA==.Jaefury:BAABLgAECn8cAAIOAAkJVhwfBwBFAgAOAAkJVhwfBwBFAgAAAA==.Jakes:BAAALgAECgQJBQAAAA==.Jandinga:BAAALgAECgQJBAAAAA==.',
Je='Jeabuschrist:BAAALgADCgYJBgAAAA==.',
Ji='Jimadler:BAAALgADCgMJAwABLgAECgIJAgAEAAAAAA==.Jimbi:BAAALgAFFAIJBAAAAA==.Jiminybilini:BAAALgAECgcJBQAAAA==.Jimmybull:BAAALgADCgEJAQAAAA==.Jinho:BAAALgAECgEJAQABLgAECgkJHQAhACsiAA==.Jinrop:BAEALgADCgcJBwABLgAECgcJFgAeACMUAA==.',
Jo='Jobuu:BAAALgAECgEJAgAAAA==.Jock:BAAALgAECgQJCAAAAA==.Johnnypopoff:BAABLgAECn8kAAIbAAkJOxQNUQDRAQAbAAkJOxQNUQDRAQAAAA==.Johnwolf:BAAALgAECgQJCQAAAA==.Jojohunts:BAAALgAECgcJDQAAAA==.Joshodin:BAAALgAECgEJAQAAAA==.',
Jp='Jpðc:BAAALgAECgYJCgAAAA==.',
Ju='Juanjo:BAAALgADCgcJBwABLgAECgkJMwAbAA4eAA==.Junyubych:BAABLgAECn8UAAIeAAYJigiQGwC1AAAeAAYJigiQGwC1AAAAAA==.Justylln:BAAALgAECgYJBgAAAA==.Justzach:BAABLgAECn83AAIPAAkJXhodDABiAgAPAAkJXhodDABiAgAAAA==.',
['Jà']='Jàccuse:BAABLgAECn8eAAIcAAgJ3RK8JgDDAQAcAAgJ3RK8JgDDAQAAAA==.Jàrnsaxa:BAAALgADCgEJAQAAAA==.',
['Jò']='Jòhnnypopo:BAABLgAECn8VAAIBAAgJDxfLQADsAQABAAgJDxfLQADsAQAAAA==.',
Ka='Kadywompus:BAAALgADCgcJBwAAAA==.Kaeladra:BAAALgAECgIJAgABLgAECgQJBQAEAAAAAA==.Kailm:BAAALgADCgIJAgABLgAFFAYJDgAVAA4dAA==.Kait:BAAALgAECgIJAgAAAA==.Kalida:BAAALgADCgQJBAAAAA==.Kalniel:BAAALgADCgUJBQAAAA==.Kalorie:BAAALgADCgYJBgABLgAECgYJHgAGAL4fAA==.Kassaalaa:BAAALgADCgYJBgAAAA==.Kasume:BAAALgAECgQJBQAAAA==.Kaylastrasza:BAAALgAECgEJAQAAAA==.Kazurend:BAACLgAFFH8VAAIiAAcJgiIyAwAvAgAiAAcJgiIyAwAvAgAuAAQKfxoAAiIACAnQI7wFADMDACIACAnQI7wFADMDAAAA.',
Ke='Keiadon:BAAALgADCgkJCQAAAA==.Kelavax:BAAALgAECgkJBQAAAA==.Keleira:BAABLgAECn8XAAIbAAgJXhdtVwC+AQAbAAgJXhdtVwC+AQAAAA==.Kelemvore:BAAALgAECgEJAQAAAA==.Kericcandere:BAAALgADCgIJAwAAAA==.Kerm:BAEALgAECgEJAgAAAA==.Keyaielenst:BAAALgADCgcJBwAAAA==.',
Kh='Khristina:BAAALgADCgkJDQAAAA==.Khrogh:BAAALgAECgQJBQAAAA==.',
Ki='Kiel:BAABLgAFFH8HAAIaAAQJlhyCEAD7AAAaAAQJlhyCEAD7AAABLgAFFAMJBQAhAE0SAA==.Kindos:BAAALgADCgQJBwAAAA==.Kippo:BAEALgAECgEJAQABLgAFFAUJCAAbACYFAA==.Kiramman:BAAALgAECgUJDAAAAA==.Kirsute:BAAALgADCgYJBgAAAA==.Kirxcy:BAAALgADCgUJCAAAAA==.Kithiri:BAABLgAECn8XAAISAAYJZQauPwDhAAASAAYJZQauPwDhAAAAAA==.',
Kn='Knarn:BAABLgAECn8mAAIXAAkJEx07DgA5AgAXAAkJEx07DgA5AgAAAA==.',
Ko='Koralie:BAACLgAFFH8cAAMRAAcJ3xXWAACrAQARAAYJVRjWAACrAQAYAAEJkAlqKwBKAAAuAAQKfx4AAxEACAloHW4bAGICABEACAloHW4bAGICABgABQm+D6VcANAAAAAA.Kotiria:BAAALgAECgEJAQAAAA==.',
Kr='Krillaxx:BAAALgAECgcJDwAAAA==.Krimzin:BAAALgAECgcJDwABLgAFFAUJFgARAHwgAA==.Krolg:BAAALgAECgQJCQAAAA==.Kromvar:BAAALgAECgQJBwAAAA==.',
Ku='Kungfused:BAAALgADCgUJCAABLgAECgQJBgAEAAAAAA==.Kurisux:BAABLgAFFH8MAAIQAAQJJRv7OQBeAQAQAAQJJRv7OQBeAQAAAA==.',
Ky='Kyliekat:BAAALgAECgcJEQAAAA==.Kyndlynn:BAAALgAECgQJEAAAAA==.Kyriea:BAAALgAECgEJAQAAAA==.',
La='Lanceelot:BAAALgAECgIJAgAAAA==.Lanel:BAAALgAECgUJCQAAAA==.Lathelous:BAABLgAECn8mAAINAAkJ2SInAgAFAwANAAkJ2SInAgAFAwAAAA==.',
Ld='Ldt:BAAALgADCgMJAwAAAA==.',
Le='Leintheir:BAAALgAECgMJAwAAAA==.Leththol:BAAALgADCgkJJQAAAA==.Letyoudie:BAAALgAECgQJCwAAAA==.Levenza:BAABLgAECn8UAAIHAAgJYhSUDgBKAQAHAAgJYhSUDgBKAQAAAA==.',
Li='Licita:BAAALgAECgUJCgAAAA==.Lideina:BAABLgAECn8lAAIQAAcJDh5oRQDfAQAQAAcJDh5oRQDfAQAAAA==.Lielandra:BAAALgAECgcJCAAAAA==.Lightdinger:BAAALgAECgYJDQAAAA==.Lightt:BAABLgAECn9AAAMUAAgJLB2BDgBmAgAUAAgJLB2BDgBmAgAiAAUJNQEQVQBvAAAAAA==.Liightt:BAABLgAECn8bAAIUAAcJhhM2JgB9AQAUAAcJhhM2JgB9AQAAAA==.Lilnug:BAAALgAECgQJDAAAAA==.Lindsey:BAAALgADCgkJDQABLgAECgUJCwAEAAAAAA==.Littlenyne:BAAALgAECgYJDAAAAA==.',
Ll='Llando:BAAALgADCgYJBgAAAA==.Llars:BAABLgAECn8mAAILAAkJSxgYHABRAgALAAkJSxgYHABRAgAAAA==.Lleonardo:BAAALgADCgEJAQAAAA==.',
Lo='Lockkjaw:BAAALgAECgEJAQAAAA==.Locknorris:BAAALgADCgUJBgAAAA==.Loghrif:BAAALgAECgQJBAAAAA==.Loptear:BAAALgAECgEJAQAAAA==.Loryanna:BAAALgADCgUJCwAAAA==.Louie:BAAALgAECgMJBAAAAA==.Lovehandless:BAAALgADCgEJAQAAAA==.Lovespell:BAAALgADCgUJBQAAAA==.',
Lu='Lucavian:BAAALgAECggJEQAAAA==.Lucavias:BAAALgAECgMJBQAAAA==.Luckydruidh:BAABLgAECn8bAAMDAAkJOxwUDQDiAgADAAkJOxwUDQDiAgAZAAEJxQ3vewA6AAAAAA==.Luckyevoker:BAAALgADCgcJEgABLgAECgkJGwADADscAA==.Luckyjax:BAAALgAECgEJAQAAAA==.Lurien:BAABLgAECn8XAAIaAAkJ3ROQFgCyAQAaAAkJ3ROQFgCyAQAAAA==.Luxilejo:BAAALgADCgYJCwAAAA==.',
Ly='Lyfebane:BAACLgAFFH8FAAMBAAIJsgWChQB/AAABAAIJsgWChQB/AAAMAAIJZwkeNwBxAAAuAAQKfzYAAwEACQkYF6YyAB0CAAEACQkYF6YyAB0CAAwACAkzGKUeAPcBAAAA.',
['Ló']='Lórien:BAAALgADCgEJAQAAAA==.',
['Lø']='Lørs:BAABLgAECn83AAIbAAgJ5xQtTwDWAQAbAAgJ5xQtTwDWAQAAAA==.Lørz:BAAALgAECgQJBAAAAA==.',
Ma='Machorn:BAAALgADCgcJBwAAAA==.Mageis:BAAALgADCgMJAwAAAA==.Magetree:BAAALgAFFAIJAgABLgAFFAUJDQANAJcZAA==.Mageyoucream:BAAALgAECgMJBQAAAA==.Magnai:BAAALgADCgcJBwAAAA==.Main:BAABLgAECn85AAIBAAkJJgvSbgB2AQABAAkJJgvSbgB2AQAAAA==.Majrmiståke:BAABLgAFFH8HAAIbAAMJDw9jcQDfAAAbAAMJDw9jcQDfAAABLgAFFAUJEwAGAAgbAA==.Malagore:BAAALgAFFAEJAQABLgAECggJFwATALQVAA==.Malantir:BAAALgAECgYJBgABLgAECggJFwATALQVAA==.Malec:BAAALgADCggJCAAAAA==.Malicemech:BAAALgADCgkJEAAAAA==.Maliceone:BAABLgAECn8VAAIVAAYJYQl6UADvAAAVAAYJYQl6UADvAAAAAA==.Malicepaly:BAAALgAECgUJBwAAAA==.Maliceshammy:BAAALgADCgYJCgAAAA==.Manek:BAAALgAECgYJBgABLgAECgkJPwAbAKYXAA==.Mansmilk:BAAALgAECgQJBAAAAA==.Mardara:BAAALgAECgYJBgAAAA==.Marraxa:BAAALgADCgYJBgAAAA==.Mattshamon:BAAALgADCgcJBwAAAA==.Max:BAABLgAECn8ZAAICAAkJ5R4yOgDlAQACAAkJ5R4yOgDlAQAAAA==.Mayé:BAABLgAFFH8EAAIZAAQJeA5jHwD+AAAZAAQJeA5jHwD+AAAAAA==.',
Mb='Mbaku:BAAALgAECgYJCwABLgAFFAUJCwAiALEcAA==.',
Me='Melechim:BAAALgADCgkJCQAAAA==.Melinoe:BAABLgAECn8gAAICAAgJWw/pVQCPAQACAAgJWw/pVQCPAQAAAA==.Meowdoh:BAABLgAFFH8FAAIWAAQJ4AnhEwC+AAAWAAQJ4AnhEwC+AAAAAA==.Merc:BAAALgAECgUJBQAAAA==.Merithrá:BAAALgAECgIJAgAAAA==.',
Mi='Micah:BAACLgAFFH8eAAIJAAcJVhBxBQChAQAJAAcJVhBxBQChAQAuAAQKfxsAAwkACAnkGggOAFYCAAkACAnkGggOAFYCABMABQm/GpsyADUBAAAA.Milenad:BAAALgAECgIJAgAAAA==.Minilyfe:BAAALgAECgMJAwAAAA==.Mirelia:BAAALgADCgMJAgAAAA==.Mishosuki:BAABLgAECn8YAAIQAAYJngtKsgD6AAAQAAYJngtKsgD6AAAAAA==.Misky:BAAALgADCgEJAQAAAA==.Misscleo:BAABLgAECn8xAAIbAAkJDxgZKQBgAgAbAAkJDxgZKQBgAgAAAA==.Mizzyboii:BAAALgADCgMJAwAAAA==.',
Mk='Mk:BAAALgAECggJDwAAAA==.',
Mn='Mnesarte:BAABLgAECn8XAAIBAAYJZRZ+nwAdAQABAAYJZRZ+nwAdAQAAAA==.',
Mo='Moanalisa:BAAALgAECgEJAwAAAA==.Moi:BAABLgAFFH8IAAITAAUJBhNVJwAIAQATAAUJBhNVJwAIAQABLgAFFAQJDwAbAIsdAA==.Moltres:BAEALgAFFAUJBAABLgAFFAkJIQATAJckAA==.Monkilha:BAABLgAECn8YAAIdAAgJABmUFAAAAgAdAAgJABmUFAAAAgAAAA==.Moonkist:BAABLgAECn8ZAAMDAAgJ5hpIGABxAgADAAgJ5hpIGABxAgAZAAEJRAN6jQAhAAAAAA==.Moonsgrace:BAAALgADCgkJGQAAAA==.Moose:BAACLgAFFH8HAAIQAAIJrSDjmgC3AAAQAAIJrSDjmgC3AAAuAAQKfzsAAhAACAlxJJEVALMCABAACAlxJJEVALMCAAAA.Morpheos:BAABLgAECn8bAAMDAAkJbRU/SABbAQADAAkJbRU/SABbAQAZAAQJhgfsWACSAAAAAA==.Morroe:BAAALgADCgEJAQAAAA==.Moxci:BAAALgAECgQJBQAAAA==.',
Mu='Mudamudamuda:BAAALgADCgYJDQABLgAFFAUJEwAVAEAbAA==.Muffintop:BAAALgADCgEJAQAAAA==.',
My='Mysticforest:BAAALgAECgQJBAAAAA==.',
Na='Naedise:BAAALgADCgcJFgAAAA==.Narue:BAAALgAECgIJAgAAAA==.Natureswild:BAABLgAECn8gAAMZAAkJkhiUIQDwAQAZAAgJ4xeUIQDwAQADAAMJawrZuQBSAAAAAA==.Navariis:BAAALgAECgUJDQAAAA==.Navillus:BAAALgAECgMJBgABLgAFFAcJIAAJAIYQAA==.',
Ne='Necrophyliac:BAAALgAECgYJCwAAAA==.Nelrehim:BAAALgAECgEJAQAAAA==.Nelumbo:BAAALgAFFAQJBAABLgAFFAcJBQAJAEwVAA==.Nephy:BAAALgAECgQJBAAAAA==.Nephyrium:BAAALgAECgUJCAAAAA==.Nephz:BAAALgAECgYJCgAAAA==.Nephzz:BAAALgAECgQJAwAAAA==.Nethery:BAAALgADCgcJCQAAAA==.Nex:BAAALgAECgEJAQAAAA==.Nezrin:BAAALgAECgcJEgAAAA==.',
Ni='Niandilan:BAAALgAECgQJBAAAAA==.Nidon:BAAALgADCgUJBQAAAA==.Niixxi:BAAALgADCgUJBQAAAA==.',
Nm='Nmbrs:BAABLgAECn8gAAMiAAgJDx+REAA5AgAiAAgJDx+REAA5AgASAAEJ7AK9XAApAAAAAA==.',
No='Noirheffer:BAACLgAFFH8NAAMNAAUJlxmxBgD8AAANAAUJIRGxBgD8AAABAAMJ9hTZWQDaAAAuAAQKfycAAwEACQnXHvcXANkCAAEACAlDIvcXANkCAA0ABwkXF9MQAJ4BAAAA.Noobishdad:BAAALgAECgMJAwAAAA==.Norio:BAAALgADCgcJBwAAAA==.Notafurrie:BAAALgAECgQJBAAAAA==.',
Nu='Nulannatoo:BAAALgAECgUJBQAAAA==.Numz:BAAALgAECgEJAQAAAA==.Nuukeasaur:BAAALgADCgEJAQAAAA==.',
Ny='Nyadari:BAAALgAECgEJAQAAAA==.Nyphe:BAAALgAECgQJBAAAAA==.Nyrrhi:BAAALgAECgQJCAAAAA==.Nyxiro:BAAALgAECgUJBQAAAA==.',
Oc='Oculus:BAAALgAECgMJAwAAAA==.',
Od='Odysseus:BAAALgADCgkJFgAAAA==.',
Ol='Oleira:BAAALgAECgUJBQAAAA==.Olgann:BAAALgAECggJEgAAAA==.Olguita:BAABLgAFFH8FAAIKAAMJZxJWJwDcAAAKAAMJZxJWJwDcAAAAAA==.Olivertwìst:BAAALgADCgcJBwAAAA==.',
Om='Omgowned:BAAALgAECgYJCwABLgAECgkJIQACAOUWAA==.Omnipresent:BAAALgAECgEJAQAAAA==.',
On='Onehothealer:BAABLgAECn8aAAIiAAkJIBbsGQAQAgAiAAkJIBbsGQAQAgAAAA==.',
Oo='Oorua:BAAALgADCgkJDwAAAA==.',
Op='Opheliastar:BAACLgAFFH8FAAIiAAMJDAieIQDAAAAiAAMJDAieIQDAAAAuAAQKfy0AAiIACQnmE1waANcBACIACQnmE1waANcBAAAA.',
Ow='Owltoidz:BAAALgAECgEJAgAAAA==.',
Pa='Pad:BAABLgAECn8ZAAMCAAcJpAqFiAAfAQACAAYJpAqFiAAfAQAeAAEJAAAzdQAwAAAAAA==.Pahket:BAAALgAECgQJBAAAAA==.Paintballerr:BAAALgADCgEJAQAAAA==.Paladerp:BAABLgAECn82AAMMAAgJGA9gNABrAQAMAAgJGA9gNABrAQABAAcJOxHpiQBBAQAAAA==.Pallyown:BAABLgAFFH8KAAIMAAIJayPUKQDBAAAMAAIJayPUKQDBAAAAAA==.Paprika:BAAALgADCgQJBgAAAA==.Pastorbedtym:BAABLgAECn8YAAIiAAgJeA8RMAA8AQAiAAgJeA8RMAA8AQAAAA==.Pat:BAAALgAECgMJAwAAAA==.Paulybricks:BAAALgAECgUJBgAAAA==.',
Pe='Pecan:BAAALgAECgcJDgABLgAFFAQJCAAbAAYhAA==.Pewpewbang:BAAALgADCgIJAgAAAA==.',
Ph='Pharla:BAAALgADCgkJEAAAAA==.Phett:BAAALgAFFAEJAQAAAA==.',
Pi='Pichon:BAAALgADCgUJCAAAAA==.Piffi:BAAALgAECgQJBAAAAA==.Pimmscup:BAAALgAECgEJAQAAAA==.Pin:BAAALgAECgcJBgABLgAFFAcJBQAJAEwVAA==.Pirei:BAAALgADCgUJBQAAAA==.Pirozhki:BAAALgADCgYJBgAAAA==.',
Pl='Plagueborn:BAAALgAECgEJAQAAAA==.Plentar:BAAALgADCgkJDgAAAA==.',
Po='Popcorntea:BAAALgAECgEJAgAAAA==.Porgoon:BAAALgAECgQJBQAAAA==.',
Pr='Preserved:BAAALgADCgIJAgAAAA==.Prizzma:BAAALgADCgUJBQAAAA==.',
Ps='Psaul:BAAALgAECgYJCwAAAA==.Psychohexane:BAAALgADCgQJBAAAAA==.',
Py='Pyramys:BAAALgADCgYJBgABLgAFFAUJEwAhACwfAA==.',
Qe='Qedeshah:BAAALgAECggJCAAAAA==.Qesem:BAAALgADCgUJBQAAAA==.',
Qu='Qualaribou:BAAALgADCgQJBAAAAA==.',
Ra='Raal:BAAALgADCgkJHgAAAA==.Raenostra:BAAALgAECgUJEAAAAA==.Raenya:BAAALgAECgcJDwAAAA==.Ragefather:BAAALgADCgEJAQAAAA==.Rageye:BAAALgADCgcJBwAAAA==.Rainydaze:BAAALgAECggJEwAAAA==.Ramcharger:BAABLgAECn8cAAMHAAgJxxTNCQCuAQAHAAgJxxTNCQCuAQAaAAYJoAzEOwARAQAAAA==.Ranen:BAABLgAECn8gAAIdAAkJ4B0SDABuAgAdAAkJ4B0SDABuAgAAAA==.Rashun:BAAALgAECggJEwAAAA==.',
Re='Reanatilax:BAAALgADCgMJAwABLgAECgkJKQASADwQAA==.Redcinnabar:BAAALgAECgYJEgAAAA==.Regisfilia:BAAALgAECgYJCQABLgAECgYJHgAGAL4fAA==.Rehtilox:BAAALgADCgMJAwABLgAECgkJKQASADwQAA==.Reilly:BAAALgADCggJFQAAAA==.Rev:BAAALgAECgQJBAAAAA==.Rexxy:BAAALgAECgYJEQAAAA==.',
Ri='Riju:BAAALgAECgcJDgAAAA==.Rikashae:BAAALgAECgEJAQAAAA==.Rillan:BAAALgADCgMJAwAAAA==.Rinzler:BAAALgAECgUJCQAAAA==.Rissa:BAAALgAECgMJAwAAAA==.',
Rn='Rng:BAAALgAECgQJCwAAAA==.',
Ro='Roachcentral:BAAALgADCgUJBgAAAA==.Roachcity:BAAALgADCgUJBQAAAA==.Rockalock:BAAALgADCgYJBgAAAA==.Rogerz:BAAALgADCgUJBQAAAA==.Roleon:BAAALgAECgQJBAAAAA==.Rollforpi:BAAALgAECgQJBgABLgAFFAcJHQADAOgYAA==.Ropebunnyana:BAACLgAFFH8LAAIcAAUJiBVLGABiAQAcAAUJiBVLGABiAQAuAAQKfysAAhwACQlEIN8FAC0DABwACQlEIN8FAC0DAAAA.Rowkani:BAAALgADCgkJCQAAAA==.',
Ru='Ruki:BAABLgAECn8eAAMGAAYJvh9UTACJAQAGAAYJqBxUTACJAQAaAAIJ7B92PQCdAAAAAA==.',
Ry='Ryand:BAAALgAECgUJCQABLgAFFAUJFgAhAP4iAA==.',
Sa='Sacra:BAAALgAECgEJAQAAAA==.Salarcyn:BAAALgAECgUJDAAAAA==.Saltydk:BAABLgAFFH8GAAMQAAUJwwjzbQADAQAQAAQJwwjzbQADAQAFAAEJAABgTAAAAAAAAA==.Samiracy:BAABLgAECn80AAIeAAkJHh8vAQDVAgAeAAkJHh8vAQDVAgAAAA==.Sannrin:BAAALgAECgYJDAAAAA==.Santhrin:BAAALgADCgcJBwAAAA==.Sapprot:BAAALgADCgcJCQAAAA==.Sarkress:BAAALgADCgkJCQAAAA==.',
Se='Seagal:BAAALgADCgEJAgAAAA==.Senbatorii:BAABLgAECn8dAAQDAAgJUR3KHwA1AgADAAcJxRzKHwA1AgAZAAcJXgpBQQDsAAAfAAQJpwfYKACGAAAAAA==.Seredala:BAAALgADCgUJCwAAAA==.Sethrow:BAABLgAECn8hAAQCAAkJ5RaRIgBKAgACAAgJ5RaRIgBKAgAgAAEJAACiPgAAAAAeAAEJAACsSgAAAAAAAA==.Severa:BAAALgAECggJDQAAAA==.',
Sh='Shaladora:BAAALgADCgYJBgAAAA==.Shalia:BAAALgADCgMJAwABLgAECgEJAQAEAAAAAA==.Shamaster:BAAALgADCgIJAgAAAA==.Sharas:BAAALgAECgQJBQAAAA==.Shawarma:BAAALgAECgYJCwAAAA==.Sheltatha:BAAALgAECgEJAQAAAA==.Shengari:BAABLgAECn8nAAIUAAgJbBK9MAB+AQAUAAgJbBK9MAB+AQAAAA==.Shotcallà:BAAALgADCgIJAgAAAA==.Shuna:BAAALgAECgUJDQAAAA==.Shyly:BAABLgAECn8XAAIiAAkJqBxLDQBkAgAiAAkJqBxLDQBkAgAAAA==.Shâbs:BAAALgAECgkJAgAAAA==.',
Si='Sikkly:BAAALgADCgcJEQAAAA==.Siley:BAABLgAECn9ZAAIQAAkJOBZFOAALAgAQAAkJOBZFOAALAgAAAA==.Sin:BAAALgAECgcJCAAAAA==.Siphon:BAAALgADCgYJBgAAAA==.',
Sk='Skarletfaith:BAABLgAECn8UAAIBAAgJ0QXdsgD+AAABAAgJ0QXdsgD+AAAAAA==.',
Sl='Sloanya:BAABLgAECn85AAMcAAkJXR5sCAD2AgAcAAkJXR5sCAD2AgAdAAYJKxqmJQCqAQAAAA==.',
Sn='Snarffie:BAAALgAECgYJCgAAAA==.',
So='Solanar:BAAALgADCgUJBQAAAA==.Somedruid:BAABLgAECn8vAAIZAAkJvyN8BAAKAwAZAAkJvyN8BAAKAwAAAA==.',
Sp='Spiarmf:BAAALgADCgUJBQAAAA==.Spicynes:BAAALgADCgQJBwAAAA==.Spicyness:BAAALgAECgIJAgAAAA==.Spiderdk:BAAALgAECgUJCAABLgAFFAUJGAARAOAgAA==.Spidermonk:BAAALgADCgcJDgABLgAFFAUJGAARAOAgAA==.Spielberg:BAAALgAECgEJAgAAAA==.Spycmchaggis:BAAALgAECgQJBAAAAA==.Spëcter:BAAALgAECgcJCgABLgAECggJEgAEAAAAAA==.Spëcthyr:BAAALgAECggJEgAAAA==.',
Sq='Squishypoo:BAAALgAECgMJBgAAAA==.',
St='Stache:BAAALgAECgEJAQAAAA==.Stoneyfoam:BAAALgAECgYJBgAAAA==.Stormrider:BAAALgADCgkJCQAAAA==.Stratergron:BAAALgAECgcJAQAAAA==.',
Su='Sugrace:BAAALgAECgYJBgAAAA==.Superdemonzz:BAACLgAFFH8TAAIGAAUJCBsJKQBWAQAGAAUJCBsJKQBWAQAuAAQKfzQAAwYACQnEH4UOALwCAAYACQmqH4UOALwCAAcABwkAHHIHAPIBAAAA.Superevokerz:BAAALgADCgcJDgABLgAFFAUJEwAGAAgbAA==.Superlockz:BAAALgADCgkJCQABLgAFFAUJEwAGAAgbAA==.Superpallyz:BAACLgAFFH8MAAIMAAMJvhWWJwDQAAAMAAMJvhWWJwDQAAAuAAQKfzEAAwwABwnOHkYbABQCAAwABwnOHkYbABQCAA0ABQkhEdgnAL0AAAEuAAUUBQkTAAYACBsA.Supershamanz:BAAALgAECgYJCgABLgAFFAUJEwAGAAgbAA==.Superspidey:BAAALgADCgIJAgAAAA==.Sushiroll:BAABLgAECn8XAAIdAAgJPx5dEAAwAgAdAAgJPx5dEAAwAgAAAA==.',
Sy='Sydnysweeney:BAAALgADCgMJAwAAAA==.Sylentslit:BAAALgADCggJGgAAAA==.Sylveslem:BAAALgAECgkJDAAAAA==.Syphon:BAAALgADCgMJAwAAAA==.',
['Sô']='Sôlmyr:BAAALgADCgIJAgAAAA==.',
Ta='Tacowarr:BAAALgADCgUJBQAAAA==.Taiynn:BAAALgAECgYJBgAAAA==.Taldazlian:BAAALgAECgMJBgAAAA==.Taliesin:BAAALgAECgMJAwAAAA==.Tallon:BAAALgAECgEJAQABLgAFFAUJFwATALobAA==.Tancy:BAAALgAECgMJAwABLgAECgkJMwADAFcZAA==.Tantalus:BAABLgAECn8dAAIRAAcJfAxicQBFAQARAAcJfAxicQBFAQAAAA==.Tarogen:BAAALgADCgUJBQAAAA==.Tashaler:BAAALgADCgEJAQAAAA==.Tasithia:BAAALgAECgQJBAAAAA==.',
Te='Tealet:BAAALgADCgkJEQAAAA==.Teleion:BAAALgAECgEJAQAAAA==.Tellinor:BAABLgAECn8YAAIBAAYJAQp9ygDcAAABAAYJAQp9ygDcAAAAAA==.Temporal:BAAALgAECgEJAQAAAA==.Terrestra:BAAALgADCgMJAwAAAA==.Tervor:BAAALgADCgYJBwAAAA==.',
Th='Thanamoros:BAAALgAECgUJBgABLgAFFAMJCQATABEPAA==.Thassarian:BAAALgAECgQJBAABLgAECggJIgAHABkfAA==.Thechosenone:BAAALgADCgIJAgAAAA==.Theroach:BAAALgAECgYJEwAAAA==.Tholdir:BAAALgAECgYJBgAAAA==.Throfin:BAAALgAECgUJCgAAAA==.Thundernight:BAAALgAECgcJAgAAAA==.',
Ti='Tiki:BAAALgAECgUJBwAAAA==.Tinc:BAAALgADCgEJAgAAAA==.Tinkerballa:BAAALgADCgUJBQAAAA==.Tinonova:BAAALgAECgEJAgAAAA==.Titsmgee:BAAALgAECgIJAgAAAA==.',
To='Toeren:BAACLgAFFH8YAAIRAAUJ4CABGQB0AQARAAUJ4CABGQB0AQAuAAQKfzAAAhEACQm8IHQIAAQDABEACQm8IHQIAAQDAAAA.Tomate:BAAALgADCgQJBAAAAA==.Toph:BAAALgAECgEJAQAAAA==.Tormented:BAAALgAECgYJEwAAAA==.Townsley:BAAALgAECgYJDQAAAA==.',
Tp='Tpain:BAAALgAECgMJAwAAAA==.',
Tr='Traitoros:BAAALgADCgYJBgAAAA==.Tralectra:BAAALgAECgcJDAAAAA==.Tranquilfist:BAAALgADCgQJBQABLgAECggJFAABANEFAA==.Treemonk:BAAALgADCgYJCgABLgAECgkJIAAZAJIYAA==.Trolvere:BAAALgAECgQJBwAAAA==.Trorim:BAAALgADCgYJBgAAAA==.Trïsh:BAAALgAECgQJCAABLgAECgYJCQAEAAAAAA==.',
Tu='Tummy:BAAALgADCgcJEwAAAA==.Turtlesoup:BAAALgADCgYJBgAAAA==.',
Tw='Twëë:BAAALgAECgQJBQAAAA==.',
Ty='Tybonk:BAAALgAECgEJAQAAAA==.Tygragon:BAAALgAECgYJEAAAAA==.Tyinorin:BAAALgAECgUJAQAAAA==.Tylea:BAAALgADCgkJEQAAAA==.',
Tz='Tzipporah:BAAALgAECgYJCAAAAA==.',
Ub='Ubee:BAABLgAECn8YAAIGAAkJTxCbQACwAQAGAAkJTxCbQACwAQAAAA==.',
Ul='Ultimakitty:BAABLgAECn8WAAMDAAcJcRlKOwCUAQADAAYJOhdKOwCUAQAZAAYJ6gnkRQDYAAAAAA==.',
Un='Uncertainty:BAAALgAECgQJBAABLgAECgYJHgAGAL4fAA==.Unchanged:BAAALgADCgYJBgAAAA==.Unholymana:BAAALgADCgkJFgAAAA==.',
Va='Vaellin:BAAALgAECgEJAQAAAA==.Valanyr:BAAALgADCgEJAQAAAA==.Vantrix:BAAALgAECgEJAQABLgAFFAMJCQATABEPAA==.Varabo:BAABLgAECn8ZAAIbAAcJBhSZcwB4AQAbAAcJBhSZcwB4AQAAAA==.Varolina:BAAALgAECgEJAQAAAA==.',
Ve='Vehemencê:BAAALgADCgEJAQAAAA==.Velements:BAAALgAECgMJAwABLgAECgkJEwAEAAAAAA==.Velemon:BAACLgAFFH8SAAIjAAQJ9w5RFADlAAAjAAQJ9w5RFADlAAAuAAQKfxgAAiMACAnuE/ERAOkBACMACAnuE/ERAOkBAAAA.Velisen:BAABLgAECn8iAAMBAAcJEwlMvADwAAABAAcJugdMvADwAAANAAUJ4gYWMgCFAAAAAA==.Velthala:BAAALgAECgkJEwAAAA==.Velystiri:BAAALgADCgcJBgAAAA==.Venedictus:BAAALgADCgMJAwAAAA==.',
Vi='Viergryn:BAAALgAECgEJAgABLgAECgcJGQAdAPQYAA==.Virasdruid:BAABLgAFFH8FAAIDAAIJRwTsVwBaAAADAAIJRwTsVwBaAAAAAA==.Virusmonk:BAAALgAECgEJAwAAAA==.Vitner:BAABLgAECn8eAAMIAAkJwhhJCgBnAQATAAkJ6xKPLABtAQAIAAYJMRlJCgBnAQAAAA==.',
Vo='Vosaleana:BAAALgAECgMJAwAAAA==.',
Vr='Vraak:BAACLgAFFH8dAAIDAAcJ6BhTCAA+AgADAAcJ6BhTCAA+AgAuAAQKfycAAwMACAnhG7YrAAECAAMABwmBHbYrAAECABkABwmaIxYgAP4BAAAA.',
Vu='Vulcus:BAAALgAFFAEJAQABLgAFFAcJHQADAOgYAA==.Vulpii:BAAALgADCgYJBQABLgAFFAQJCgAgAPcZAA==.',
Vy='Vyndarien:BAAALgADCgIJAgAAAA==.Vyse:BAAALgADCgEJAQAAAA==.Vyttra:BAAALgADCgMJAwAAAA==.',
Wa='Walak:BAAALgADCgMJAwAAAA==.Warpulse:BAAALgADCgkJFQAAAA==.Warwizard:BAAALgADCgMJAwAAAA==.Watcherseye:BAAALgADCggJDwABLgADCgkJCQAEAAAAAA==.Wavewhisper:BAAALgAECgEJAQAAAA==.Wayofthemist:BAAALgAECggJDwAAAA==.',
Wc='Wcreator:BAABLgAECn8dAAIBAAgJWx/vGwCFAgABAAgJWx/vGwCFAgAAAA==.',
We='Weapònized:BAABLgAECn8UAAIGAAYJWg4vmwDMAAAGAAYJWg4vmwDMAAAAAA==.Webaldes:BAAALgAECgEJAQAAAA==.',
Wh='Whitestain:BAABLgAECn8bAAIYAAgJfAqUEwAPAQAYAAgJfAqUEwAPAQAAAA==.',
Wi='Windyskie:BAAALgADCgEJAQAAAA==.Wingman:BAACLgAFFH8WAAIIAAUJwSZ/AADRAQAIAAUJwSZ/AADRAQAuAAQKfzMAAggACAmXJpgAAIsDAAgACAmXJpgAAIsDAAAA.',
Wo='Womdalie:BAAALgADCgQJBgAAAA==.Woodey:BAAALgAECgEJAgAAAA==.Wowame:BAAALgAFFAEJAQAAAA==.',
Wy='Wyckedpally:BAAALgADCgYJDAAAAA==.',
Xa='Xanthös:BAAALgAFFAEJAQABLgAFFAcJHQADAOgYAA==.',
Xe='Xemnastrasza:BAACLgAFFH8JAAQTAAMJEQ+FOQC+AAATAAMJEQ+FOQC+AAAJAAIJaQN/IwBkAAAIAAEJ0QNnCwBLAAAuAAQKfxYABBMACAkdFMQhALEBABMACAnSEcQhALEBAAgABAmmCPEtAKsAAAkAAQlrBYZLACsAAAAA.Xenonne:BAACLgAFFH8OAAIGAAUJFxNXOwAZAQAGAAUJFxNXOwAZAQAuAAQKfyEAAwYACAn6G0k7AMMBAAYACAn6G0k7AMMBABoABQl3D3FGANsAAAAA.',
Xo='Xolither:BAABLgAECn8pAAMSAAkJPBDCHgC0AQASAAgJIxDCHgC0AQAUAAQJ1hO3TgD9AAAAAA==.',
Xp='Xpireedk:BAACLgAFFH8TAAMkAAUJ3iXbBAB1AQAkAAUJ1CXbBAB1AQAQAAQJIR7jQwBJAQAuAAQKfxwAAyQACQnGJUMDAF8CACQACQnGJUMDAF8CABAABQnnHrJ1AJoBAAAA.',
Ya='Yamiyoru:BAAALgADCgYJBgABLgADCgcJBwAEAAAAAA==.',
Yo='Yorakk:BAAALgADCgIJAgAAAA==.Yorgo:BAAALgAECgYJDAAAAA==.',
Za='Zachdemon:BAAALgAECgEJAQABLgAECgkJNwAPAF4aAA==.Zariala:BAABLgAECn8UAAICAAgJYwX6jQAVAQACAAgJYwX6jQAVAQAAAA==.Zatana:BAAALgAECgUJBwAAAA==.',
Ze='Zephymoo:BAABLgAECn9JAAMfAAkJoSESAgD6AgAfAAkJoSESAgD6AgAZAAIJfAPbggAtAAAAAA==.Zeromus:BAAALgAECgkJCQAAAA==.Zerri:BAAALgADCgIJAgAAAA==.Zeyana:BAACLgAFFH8OAAMHAAQJDxsuAwA1AQAHAAQJDxsuAwA1AQAaAAEJVAH+DwBAAAAuAAQKfxkABAcACQnUGtwIAOcBAAcACQnUGtwIAOcBABoABAmVBU1RAKUAAAYAAgk9AMX3AA8AAAAA.',
Zh='Zhengshi:BAABLgAECn8xAAIPAAkJiBVfEwAFAgAPAAkJiBVfEwAFAgAAAA==.',
Zn='Znot:BAAALgADCgEJAgAAAA==.',
Zo='Zoder:BAABLgAECn8WAAIZAAYJ/hFZOAAXAQAZAAYJ/hFZOAAXAQAAAA==.Zoose:BAABLgAECn80AAMVAAkJFSAxCADLAgAVAAkJFSAxCADLAgAlAAIJURjQSACJAAAAAA==.Zoser:BAABLgAECn8mAAIdAAkJ7iWIAQBaAwAdAAkJ7iWIAQBaAwAAAA==.',
Zu='Zuckuss:BAAALgAECgUJAgAAAA==.',
['Ác']='Áceventura:BAAALgAECgcJEwAAAA==.',
['Æl']='Ælthan:BAAALgADCgUJBgAAAA==.',
['Ér']='Érubus:BAAALgAECgMJBQAAAA==.',
['ßu']='ßugs:BAABLgAECn8gAAIRAAkJ5ha+IwA9AgARAAkJ5ha+IwA9AgAAAA==.',
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
