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

local lookup = {'Paladin-Retribution','Warlock-Demonology','Druid-Restoration','Unknown-Unknown','DeathKnight-Blood','Priest-Holy','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Devastation','Evoker-Preservation','Shaman-Elemental','Shaman-Restoration','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','Hunter-BeastMastery','Priest-Discipline','Evoker-Augmentation','Warrior-Fury','Druid-Guardian','Hunter-Survival','Hunter-Marksmanship','Druid-Balance','DemonHunter-Havoc','Mage-Frost','Monk-Mistweaver','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Druid-Feral','Rogue-Subtlety','Warrior-Arms','Warrior-Protection','DeathKnight-Frost',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abhanfnahwa:BAAALgADCgUJBQAAAA==.Abort:BAABLgAECn8ZAAIBAAcJtR0UUgDTAQABAAcJtR0UUgDTAQAAAA==.',
Ac='Acbabcaa:BAAALgAECgUJBQAAAA==.Acefighter:BAAALgAECgEJAQAAAA==.Aceon:BAABLgAECn8vAAIBAAkJeBnkCQBLAQABAAkJeBnkCQBLAQAAAA==.Aceonarcher:BAAALgADCgMJAwAAAA==.Aceventurâ:BAAALgAFFAEJAQAAAA==.',
Ad='Adfectia:BAABLgAECn8bAAICAAkJBgffewBBAQACAAkJBgffewBBAQAAAA==.',
Ae='Aelianna:BAABLgAECn8fAAIDAAkJ4h4hGQB8AgADAAkJ4h4hGQB8AgAAAA==.Aelinjr:BAAALgAECgEJAQAAAA==.Aelsa:BAAALgADCgYJCgABLgAECgUJDAAEAAAAAA==.Aelyt:BAABLgAECn8gAAIBAAYJPyEhBQDIAQABAAYJPyEhBQDIAQAAAA==.Aesirkin:BAAALgAECgIJBQAAAA==.Aeth:BAABLgAECn8gAAIFAAkJayHcBQDeAgAFAAkJbCHcBQDeAgAAAA==.Aethér:BAAALgAFFAEJAQABLgAFFAgJIgADAGgXAA==.',
Ag='Agiel:BAAALgADCgYJBgAAAA==.Agilities:BAAALgADCgYJBgAAAA==.',
Ah='Ahsokä:BAAALgAECgUJCAAAAA==.',
Ak='Akuaku:BAAALgADCgEJAQAAAA==.',
Al='Alandraís:BAAALgAFFAIJAgAAAA==.Alareielinda:BAAALgAECgIJAgABLgAECgkJFAAGAH8HAA==.Alcool:BAAALgAECgIJAgAAAA==.Alderaan:BAAALgAECgMJAwAAAA==.Alexhya:BAAALgAECgEJAQAAAA==.Alexjones:BAAALgADCgUJBwAAAA==.Alganeth:BAAALgADCggJCAAAAA==.Alheren:BAAALgADCgIJAgAAAA==.Aliand:BAAALgAECgIJAgAAAA==.Aliande:BAAALgADCgYJCQAAAA==.Alnethir:BAAALgAECgEJAQAAAA==.Aloray:BAAALgADCgcJCwAAAA==.Alordis:BAAALgADCgMJAwAAAA==.Alsou:BAAALgAECgEJAQAAAA==.Alvarah:BAAALgADCgMJAwAAAA==.Alynas:BAABLgAECn8fAAIDAAkJoA+9SABsAQADAAkJoA+9SABsAQAAAA==.Alysona:BAABLgAECn8WAAMHAAgJhhxMQwC+AQAHAAcJDBxMQwC+AQAIAAEJZR9bKgBZAAAAAA==.',
Am='Amahra:BAAALgAECgQJBwAAAA==.Amelio:BAAALgADCgIJAgAAAA==.Amethysztra:BAAALgADCgUJBQAAAA==.Amewow:BAACLgAFFH8KAAIJAAMJwxmQBgDrAAAJAAMJwxmQBgDrAAAuAAQKfyAAAwkACAkLHLIFAAECAAkACAkLHLIFAAECAAoABAnmD50kAMkAAAAA.Amìko:BAAALgAECgQJBwAAAA==.',
An='Anadoria:BAAALgADCgYJBgAAAA==.Analferret:BAABLgAECn8cAAMLAAcJOw7jRQAcAQALAAcJOw7jRQAcAQAMAAMJNAoHhACEAAAAAA==.Anarchy:BAAALgAECgYJCQABLgAECgYJBwAEAAAAAA==.Anastæsia:BAAALgADCgYJBwABLgAECgMJAwAEAAAAAA==.Anda:BAAALgAECgUJCAAAAA==.Anedict:BAAALgADCgIJAgAAAA==.Angewomon:BAAALgAECgEJAQAAAA==.Anitabidet:BAAALgADCgcJBwAAAA==.Anorakswrath:BAAALgAECgcJDgAAAA==.',
Ap='Apepi:BAAALgADCgcJBwAAAA==.Apolion:BAAALgADCgQJBAAAAA==.Apoundofcake:BAAALgAECgEJAQAAAA==.Appauling:BAAALgADCgYJBgAAAA==.',
Ar='Araspeth:BAAALgADCgYJBgAAAA==.Arcanemonkey:BAAALgAECgkJBQAAAA==.Arclore:BAABLgAECn8WAAQBAAcJHw5u/AC8AAABAAUJkApu/AC8AAANAAUJyAqWXgC7AAAOAAEJYgGCXwARAAAAAA==.Argenor:BAAALgAECgUJCgAAAA==.Ariadni:BAABLgAECn8XAAMMAAgJOA8nRgCVAQAMAAgJOA8nRgCVAQALAAEJLRF5pAA0AAAAAA==.Aricict:BAAALgAECgMJAwAAAA==.Ariella:BAAALgADCgEJAQAAAA==.Arithor:BAAALgAECgQJBAAAAA==.Arlý:BAAALgAECgMJBQAAAA==.Aruneza:BAABLgAECn85AAIKAAkJfxIoDQD/AQAKAAkJfxIoDQD/AQAAAA==.',
As='Asajj:BAAALgAECgYJEgAAAA==.Asharie:BAAALgADCgEJAQAAAA==.Ashcatchm:BAAALgADCgMJAwABLgAECgcJEQAEAAAAAA==.Ashergon:BAAALgAECgQJBAABLgAECgkJGwAMAMQjAA==.Asheriz:BAAALgAECggJEAABLgAECgkJGwAMAMQjAA==.Asherous:BAABLgAECn8bAAMMAAkJxCN5CwABAwAMAAkJxCN5CwABAwALAAEJbgxShgA0AAAAAA==.Ashiashi:BAAALgAECgEJAQABLgAECgkJIgABAAYjAA==.Ashomá:BAAALgADCgcJCAAAAA==.Ashtroglide:BAAALgAECggJDgABLgAECgkJGwAMAMQjAA==.Ashèr:BAAALgAECggJEAABLgAECgkJGwAMAMQjAA==.Askara:BAAALgAECgUJBQAAAA==.Astyria:BAAALgAECgQJBAAAAA==.Aszura:BAAALgADCgUJDwAAAA==.',
Au='Auranhis:BAAALgAECgEJAgAAAA==.Auriailas:BAAALgADCgcJCQAAAA==.Autoignition:BAAALgADCgMJAwAAAA==.',
Av='Avidel:BAAALgAECgcJEAAAAA==.Avryn:BAABLgAECn8WAAMPAAgJxhhYGgAwAQAPAAYJkxdYGgAwAQALAAMJxhv9UgDtAAAAAA==.',
Ay='Ayilime:BAAALgAECgQJBQAAAA==.',
Ba='Badcompanytt:BAAALgADCgIJAgAAAA==.Bakeddh:BAAALgADCgYJCQAAAA==.Balør:BAAALgAECgMJAwABLgAECgkJNAAQAOYWAA==.Basementcat:BAAALgAECgQJBAAAAA==.Bashfury:BAAALgADCgIJAgAAAA==.Basttet:BAAALgAFFAEJAQAAAA==.Baunílha:BAABLgAECn8pAAIRAAgJ+BwEEABMAgARAAgJ+BwEEABMAgAAAA==.Bawbags:BAAALgAECgYJCQAAAA==.',
Be='Beanvoid:BAAALgADCgYJBgAAAA==.Beardsaint:BAAALgADCgUJBQAAAA==.Beefini:BAAALgAECgMJAwABLgAECggJIQASADwlAA==.Beenah:BAABLgAECn8aAAITAAgJcAZwhAA2AQATAAgJcAZwhAA2AQAAAA==.Belethiel:BAAALgADCgEJAQAAAA==.Bellinopher:BAAALgADCggJFQABLgAECgkJOAAUAEYTAA==.Benafflock:BAAALgAECgYJBwAAAA==.Bence:BAAALgAECgMJBAABLgAECgkJMwAVAF8bAA==.Benefitheals:BAAALgAECgUJBwAAAA==.Benefitpally:BAAALgAECgQJBwAAAA==.Benefitsham:BAAALgADCgYJBgAAAA==.',
Bi='Bigbibble:BAABLgAECn8aAAIGAAgJ0hTpLQCNAQAGAAgJ0hTpLQCNAQAAAA==.Birdien:BAAALgAECgYJBgAAAA==.',
Bl='Blackrose:BAAALgAECgMJAwABLgAFFAIJBQAOADELAA==.Blamson:BAAALgADCgYJCgAAAA==.Blodeuedd:BAAALgAECgYJDwAAAA==.Bloodrain:BAABLgAECn8hAAIWAAkJHg2kPwBGAQAWAAkJHg2kPwBGAQAAAA==.Blubolt:BAAALgAECgUJCwAAAA==.Blueaurora:BAAALgADCgIJAQABLgAECgkJHwADAKAPAA==.',
Bo='Bombmagic:BAAALgADCgMJAwAAAA==.Boomie:BAABLgAFFH8FAAIKAAQJTBWDGQD+AAAKAAQJTBWDGQD+AAAAAA==.Boopty:BAAALgAECgcJEAAAAA==.Booptyboop:BAAALgAECgQJEgAAAA==.Booptydo:BAAALgADCgcJCQAAAA==.Boris:BAAALgAECgEJAQAAAA==.Bowhawk:BAABLgAECn8ZAAITAAYJNgy5pgD1AAATAAYJNgy5pgD1AAAAAA==.Bozag:BAAALgADCgIJAgAAAA==.',
Br='Braiin:BAAALgAFFAIJBAABLgAFFAgJIgADAGgXAA==.Brakken:BAAALgAECgEJAQAAAA==.Brawll:BAAALgAECgMJBQAAAA==.Brazyn:BAAALgADCgYJBgAAAA==.Brevarda:BAACLgAFFH8JAAIMAAMJ4hXtSwDCAAAMAAMJ4hXtSwDCAAAuAAQKf0EAAwwACAmoIO8BAGACAAwACAmoIO8BAGACAAsABgloDaRWAOAAAAAA.Brewcelee:BAAALgAECgQJBQAAAA==.Brokenmind:BAAALgAECgQJBAABLgAECgkJLQAGAHYZAA==.Brubble:BAAALgADCgMJAwAAAA==.Brugg:BAAALgADCgYJBgAAAA==.',
Bu='Bubbles:BAAALgADCgEJAQAAAA==.Bubblzmgee:BAABLgAECn9HAAIUAAkJpBZdEgBRAgAUAAkJpBZdEgBRAgAAAA==.Burgermeat:BAAALgAECgQJBwAAAA==.Buscemi:BAAALgAECgYJCgAAAA==.Bushmommy:BAAALgAFFAEJAQAAAA==.Buttèrs:BAABLgAECn8YAAIMAAgJ9xY7CQAcAQAMAAgJ9xY7CQAcAQAAAA==.',
Ca='Cadence:BAAALgAECgEJAgAAAA==.Cadin:BAABLgAECn8VAAMMAAkJSxmPDQCvAgAMAAkJSxmPDQCvAgALAAcJYhdfLwCkAQAAAA==.Cakeman:BAAALgADCgUJBQAAAA==.Calehunter:BAAALgAECgYJBgAAAA==.Cameltotem:BAAALgAECgUJCAAAAA==.Capnblood:BAAALgAECgEJAwAAAA==.Capone:BAAALgAECgUJEAAAAA==.Carahz:BAABLgAECn8aAAIXAAcJWg+7LAD8AAAXAAcJWg+7LAD8AAAAAA==.Carindria:BAAALgAECgEJAgAAAA==.Cattiebrie:BAAALgAECgMJAwAAAA==.Caylavana:BAACLgAFFH8MAAIYAAQJwhBwBQAVAQAYAAQJwhBwBQAVAQAuAAQKfzAAAxgACAnnGrQRAB0CABgACAnnGrQRAB0CABMAAgkLEX2tAGkAAAAA.',
Ce='Celaylria:BAABLgAECn8kAAIZAAgJsRE/AQBeAQAZAAgJsRE/AQBeAQAAAA==.',
Ch='Chabz:BAAALgAECgQJAwAAAA==.Chai:BAABLgAECn8rAAMaAAgJYR2+EQBLAgAaAAgJYR2+EQBLAgADAAYJ4hh8OQDAAQABLgAFFAcJGgAVABcdAA==.Chantille:BAAALgAECgYJDQAAAA==.Charmed:BAABLgAECn8UAAIbAAkJRRBiIAB2AQAbAAkJRRBiIAB2AQAAAA==.Charmíng:BAAALgAECgYJDAABLgAFFAQJCAAcAAYhAA==.Cheryll:BAAALgAECgUJBQAAAA==.Chopenhagen:BAAALgAECgMJBAABLgAFFAQJDAAYAMIQAA==.Chunknörris:BAAALgAECgUJCwAAAA==.',
Ci='Cint:BAABLgAECn8cAAIWAAgJQwnRPwBFAQAWAAgJQwnRPwBFAQAAAA==.',
Cl='Clio:BAABLgAFFH8FAAIdAAIJcxo2RACSAAAdAAIJcxo2RACSAAAAAA==.Cloudedjade:BAABLgAECn8cAAIOAAgJ7Qf8IwD1AAAOAAgJ7Qf8IwD1AAAAAA==.Clydè:BAAALgAECgYJBgAAAA==.',
Co='Coleybear:BAABLgAECn8aAAICAAgJKQVHngACAQACAAgJKQVHngACAQAAAA==.Condewit:BAAALgAECgUJBgAAAA==.Condragos:BAAALgAECgUJBQAAAA==.Copedh:BAAALgAECgQJBAABLgAECgkJMwAFAB8eAA==.Copedk:BAABLgAECn8zAAIFAAkJHx7XCACGAgAFAAkJHx7XCACGAgAAAA==.Copedogg:BAAALgADCgcJDgABLgAECgkJMwAFAB8eAA==.Copemonkk:BAAALgADCgMJAwABLgAECgkJMwAFAB8eAA==.Copepriest:BAAALgADCgkJCQABLgAECgkJMwAFAB8eAA==.Copeshamm:BAAALgAECgUJBQABLgAECgkJMwAFAB8eAA==.Copeslamm:BAAALgAECgUJBQABLgAECgkJMwAFAB8eAA==.Corrode:BAAALgAECggJCQAAAA==.Covertm:BAAALgAECgcJEgAAAA==.Covertw:BAAALgADCgEJAQAAAA==.',
Cr='Craq:BAAALgAECgEJAgAAAA==.Crashedout:BAAALgADCgEJAgAAAA==.Crashknight:BAAALgAECgEJAQABLgAECgQJDAAEAAAAAA==.Crew:BAAALgAFFAEJAQAAAA==.Cricky:BAAALgAECgIJAwAAAA==.Crims:BAABLgAECn8ZAAIKAAgJ5xYDDgDuAQAKAAgJ5xYDDgDuAQAAAA==.Crinke:BAAALgADCgEJAQAAAA==.',
Cu='Culture:BAAALgAECgYJEAAAAA==.Curdledmilk:BAAALgAECgIJAgAAAA==.',
Cy='Cybeldin:BAABLgAECn82AAIZAAkJEQtAEQBGAQAZAAkJEQtAEQBGAQAAAA==.Cyberdemonxd:BAAALgADCgYJBwABLgAFFAIJCgASAJQQAA==.',
Da='Daadeedaa:BAACLgAFFH8KAAIcAAQJDxfZYAAgAQAcAAQJDxfZYAAgAQAuAAQKfzAAAhwACAkqJHwtAGMCABwACAkqJHwtAGMCAAAA.Daddysparey:BAABLgAECn85AAIHAAkJNxk8NAD1AQAHAAkJNxk8NAD1AQAAAA==.Dagoba:BAAALgAECgMJAgAAAA==.Dakk:BAABLgAECn9EAAIcAAkJpRfUOgAuAgAcAAkJpRfUOgAuAgAAAA==.Dardeathicus:BAACLgAFFH8MAAISAAQJPR4ibAAjAQASAAQJPR4ibAAjAQAuAAQKfyAAAhIACQnNIIkoAJgCABIACQnNIIkoAJgCAAEuAAUUBgkQABIA8RQA.Darderyag:BAACLgAFFH8HAAIcAAMJBxCSgADWAAAcAAMJBxCSgADWAAAuAAQKfy4AAhwACAk0HR4yAFACABwACAk0HR4yAFACAAAA.Darek:BAABLgAECn8YAAIcAAYJlApYzwDzAAAcAAYJlApYzwDzAAAAAA==.Dariara:BAAALgAECgEJAQAAAA==.Darilynann:BAAALgAECgQJBAAAAA==.Darilynns:BAAALgAECgEJAQAAAA==.Darkbud:BAAALgADCggJEQAAAA==.Darkfeazer:BAAALgADCgEJAQAAAA==.Darkrife:BAAALgAECgUJDAAAAA==.Darmonkicus:BAAALgAFFAIJAgAAAA==.Daymann:BAAALgAECgYJBgAAAA==.Dazzan:BAAALgAECgYJCgAAAA==.',
De='Deadlocks:BAAALgADCgEJAQAAAA==.Deathhold:BAAALgAECgYJBwAAAA==.Debilitation:BAAALgADCgIJAgAAAA==.Dedrys:BAAALgAECgEJAQAAAA==.Deeply:BAAALgAECgcJDgAAAA==.Deklan:BAAALgAECgEJAwAAAA==.Delsid:BAAALgAECgMJAwAAAA==.Demonsteven:BAAALgADCgcJCgAAAA==.Dependabull:BAAALgADCgYJCQABLgADCgcJBwAEAAAAAA==.Dernis:BAAALgAFFAEJAgAAAA==.Deshaman:BAACLgAFFH8MAAILAAMJbxaqEQDKAAALAAMJbxaqEQDKAAAuAAQKfzYAAgsACAmpIAQNAJUCAAsACAmpIAQNAJUCAAEuAAUUBwkhABMAnR8A.Devilbeast:BAAALgAECgQJDgAAAA==.',
Dh='Dhargo:BAAALgADCgcJBwAAAA==.',
Di='Diablosauz:BAAALgADCgYJBgAAAA==.Dirte:BAAALgADCgYJDQAAAA==.Dirty:BAABLgAECn8eAAILAAgJ5BOIJQDlAQALAAgJ5BOIJQDlAQAAAA==.',
Dk='Dkbygorm:BAAALgADCgQJBwAAAA==.',
Do='Doctapheel:BAABLgAECn8cAAIeAAcJlBEWDwBsAQAeAAcJlBEWDwBsAQAAAA==.Dolfi:BAAALgADCggJDAAAAA==.Doomzday:BAAALgAECgQJBgAAAA==.Dorlesette:BAABLgAECn8kAAMdAAkJqwdGUQAqAQAdAAkJqwdGUQAqAQAQAAIJ7AI/iAA9AAAAAA==.',
Dr='Draiven:BAAALgAECgEJAQAAAA==.Drathmir:BAAALgAFFAEJAQAAAA==.Dravindil:BAAALgAECgkJBgAAAA==.Dreamlesnite:BAABLgAECn8eAAICAAcJZAf7pgDzAAACAAcJZAf7pgDzAAAAAA==.Dreidelman:BAABLgAFFH8FAAIcAAMJDQPmkwCsAAAcAAMJDQPmkwCsAAAAAA==.Drkstar:BAAALgAECgYJDgAAAA==.Drpeeper:BAAALgAECgUJBQAAAA==.Druidcam:BAAALgAECgUJBQABLgAECgkJLQASAEkXAA==.Druvisept:BAAALgAECgIJAgAAAA==.',
Du='Dudeicus:BAAALgAECgYJCQAAAA==.Dunthur:BAAALgADCgYJBgAAAA==.Duoda:BAABLgAFFH8RAAIdAAcJaxthCgBhAgAdAAcJaxthCgBhAgAAAA==.Durto:BAAALgAECgEJAgABLgAECgQJCAAEAAAAAA==.',
Dy='Dylora:BAABLgAECn88AAIdAAkJRBqbEgCJAgAdAAkJRBqbEgCJAgAAAA==.',
['Dï']='Dïesel:BAAALgAECgIJAgAAAA==.',
['Dó']='Dólores:BAAALgADCgYJBgAAAA==.',
['Dö']='Dödskott:BAAALgADCgkJGAAAAA==.',
Ec='Eclipsa:BAAALgAECggJDwAAAA==.',
Eg='Egregore:BAABLgAECn8ZAAIHAAgJWhFucABCAQAHAAgJWhFucABCAQAAAA==.',
El='Elassha:BAAALgAECgEJAQAAAA==.Ellaria:BAABLgAECn81AAMHAAkJgBhxLgANAgAHAAkJARdxLgANAgAbAAYJVhjlJQCQAQAAAA==.Elluna:BAAALgADCgEJAQAAAA==.Elyselyia:BAAALgAECgUJBQAAAA==.Elysindrall:BAABLgAECn8mAAIKAAgJGxanDAAKAgAKAAgJGxanDAAKAgAAAA==.',
Em='Emokins:BAEBLgAECn88AAILAAkJOyW+AgBJAwALAAkJOyW+AgBJAwAAAA==.Emouri:BAAALgADCgcJCwAAAA==.',
En='Endesh:BAABLgAECn82AAMVAAkJlQk9NwBSAQAVAAkJlQk9NwBSAQAJAAMJ7QVVIQBKAAAAAA==.Enolah:BAAALgADCgYJCAAAAA==.Enyos:BAAALgAECgEJAgAAAA==.',
Ep='Epiduralrot:BAACLgAFFH8SAAQfAAYJbBPZDQDGAAAfAAQJLAjZDQDGAAACAAMJYhBYhAC9AAAeAAIJlyBVDwCYAAAuAAQKfyYABAIACAneHrguAFICAAIACAleG7guAFICAB8ABAn1GWAiAEMBAB4AAwlJIsUSAAABAAAA.',
Er='Eradica:BAAALgADCgYJDQAAAA==.Erelo:BAAALgAECgQJBAAAAA==.Erreita:BAAALgADCgQJBAAAAA==.Erubus:BAACLgAFFH8XAAQQAAUJ0iEvEwCKAQAQAAUJ0iEvEwCKAQAdAAMJ1RLGQQCcAAARAAEJQwGZFAA9AAAuAAQKfxkABBAACQlsIUQWAFcCABAACQlsIUQWAFcCAB0AAgk2E/tWAHMAABEAAQm/Ds95ADcAAAAA.Erubuss:BAAALgAECgUJBQAAAA==.Erubustin:BAAALgAECgUJDAAAAA==.Eryss:BAABLgAECn8bAAITAAgJnAhbfABGAQATAAgJnAhbfABGAQAAAA==.',
Es='Escånor:BAAALgAECgYJBwAAAA==.Esmeraldita:BAAALgADCgYJDwAAAA==.',
Ev='Evercleâr:BAAALgADCgkJAgAAAA==.Evoked:BAABLgAECn8fAAMKAAgJzhLzDgDeAQAKAAgJzhLzDgDeAQAJAAUJdAWEHgBcAAAAAA==.',
Ex='Excentric:BAAALgAECgYJCgABLgAFFAkJIAAcAC4YAA==.Expiraman:BAAALgADCgYJBgAAAA==.',
Fa='Faeliel:BAAALgADCgYJBgABLgAFFAUJEwAWAEAbAA==.Faelýn:BAAALgAECggJEwAAAA==.Faessa:BAAALgADCgIJAgAAAA==.Falcone:BAAALgAECgcJBwAAAA==.Fanden:BAAALgADCgYJCQAAAA==.Fartimer:BAAALgADCgYJBgABLgAECgkJGwADAG0VAA==.',
Fd='Fdk:BAAALgAECgUJCQABLgAECggJIAAgAA8fAA==.',
Fe='Feardotcom:BAAALgADCgYJCwAAAA==.Feathering:BAAALgAECgYJEgAAAA==.Fellariene:BAAALgADCgcJCAAAAA==.Fellraiser:BAAALgAECgQJBwAAAA==.Feoralaure:BAAALgADCgQJBAAAAA==.',
Fi='Figjam:BAAALgAECgIJAgABLgAECgkJJAAdAAkSAA==.Fistenlick:BAAALgAECgQJBwAAAA==.',
Fl='Flashylights:BAAALgAECgIJAwAAAA==.Fluoria:BAAALgAECgQJEgAAAA==.Flurple:BAAALgADCgQJBAAAAA==.Fláreon:BAABLgAECn8ZAAINAAcJGhk9HQAsAgANAAcJGhk9HQAsAgAAAA==.',
Fr='Fragarach:BAAALgAECgEJAQAAAA==.Frostynipie:BAAALgADCgMJAwAAAA==.Frutypebblz:BAABLgAECn8oAAIfAAYJdAtIGwDLAAAfAAYJdAtIGwDLAAAAAA==.',
Fu='Furrsure:BAAALgAECgUJCAAAAA==.Fuzznn:BAAALgAECgMJAwABLgABCgIJAgAEAAAAAA==.',
['Fà']='Fàmous:BAABLgAECn8YAAMUAAkJ6BZlHQDiAQAUAAkJ/hJlHQDiAQAGAAIJvB4OYgCoAAAAAA==.',
Ga='Gainful:BAAALgAECgQJBQABLgAFFAQJDAACAHMVAA==.Galabris:BAABLgAECn88AAIFAAkJRCQnAgAxAwAFAAkJRCQnAgAxAwAAAA==.Galen:BAAALgAECgEJAwAAAA==.Gazzik:BAAALgAECgYJCAAAAA==.',
Ge='Geranin:BAAALgADCgUJCAAAAA==.Gervire:BAAALgADCgcJCAAAAA==.',
Gh='Ghouldân:BAAALgAECgkJAQAAAA==.Ghoulmania:BAAALgAECgkJDgAAAA==.',
Gi='Gimglich:BAAALgADCgcJCgAAAA==.Gimligrimes:BAAALgADCgEJAQAAAA==.Gington:BAAALgAECgMJAwAAAA==.Ginx:BAAALgAECgEJAQAAAA==.Gitchusum:BAABLgAECn8VAAIYAAkJ9Q6AEwAKAgAYAAkJ9Q6AEwAKAgAAAA==.',
Gl='Glaedry:BAAALgAECgEJAwAAAA==.',
Go='Goose:BAABLgAECn8XAAIUAAkJ5hH3JwCTAQAUAAkJ5hH3JwCTAQAAAA==.Gorefang:BAAALgAECgEJAQAAAA==.Gormladin:BAABLgAECn8bAAINAAgJzxR6LACvAQANAAgJzxR6LACvAQAAAA==.',
Gr='Greenbahamut:BAAALgAECgEJAQAAAA==.Gregamesh:BAAALgADCgcJDgAAAA==.Grill:BAAALgAECgMJAwAAAA==.Grimsreaper:BAAALgAECgMJAwAAAA==.Grizzlypouch:BAAALgADCgYJBgAAAA==.Grouchy:BAAALgAECgIJAwABLgAECggJIAAgAA8fAA==.',
Gu='Guillimus:BAAALgADCgcJBgAAAA==.Gultadorn:BAAALgAECgEJAQAAAA==.Guntherus:BAAALgADCgMJAwAAAA==.',
Gw='Gwynn:BAAALgAECgEJAQAAAA==.',
['Gï']='Gïzmö:BAABLgAECn8gAAIhAAkJAQz3HAAjAQAhAAkJAQz3HAAjAQAAAA==.',
Ha='Halfang:BAAALgADCgYJEQAAAA==.Halphas:BAAALgADCgYJBgAAAA==.Handham:BAAALgAECgYJCwAAAA==.Hanoe:BAAALgAECgcJAQAAAA==.Hanroro:BAAALgADCgQJAwAAAA==.Hasheth:BAAALgAECgYJCQAAAA==.Hawkiing:BAAALgADCgQJBAAAAA==.Hazuki:BAAALgAECgQJBAAAAA==.',
He='Helouise:BAAALgADCgQJBAAAAA==.Herbalxur:BAAALgAECgQJCAAAAA==.',
Hi='Hibikase:BAAALgAECgYJCAAAAA==.Hildegarde:BAAALgAECgEJAgABLgAECgcJLwAbAP0eAA==.Hitpoints:BAABLgAECn8ZAAMOAAgJ4g4WLAC9AAAOAAYJEBMWLAC9AAABAAMJYARgNQBEAAABLgAECgkJLQAGAHYZAA==.',
Ho='Hobbikeen:BAABLgAECn8iAAMKAAgJ/hzbBgCRAgAKAAgJ/hzbBgCRAgAVAAgJqg71NQBZAQAAAA==.Holyhands:BAAALgAECgkJAQAAAA==.Holyhope:BAABLgAECn8XAAINAAcJmhPTNwBuAQANAAcJmhPTNwBuAQABLgAECggJRQAMALQeAA==.Holymana:BAABLgAECn9LAAIBAAkJ2B8MAwA/AgABAAkJ2B8MAwA/AgAAAA==.Hopet:BAAALgAECgUJBQABLgAFFAQJEgAMAJ8cAA==.Hoshea:BAAALgADCgMJAwAAAA==.Hotandready:BAAALgAECgYJEAAAAA==.Hottyoreo:BAAALgADCgYJCwAAAA==.Howcom:BAAALgAECgIJAgABLgAECggJRQAMALQeAA==.',
Hu='Huffingpaint:BAAALgAECgYJEwABLgAECgcJLwAbAP0eAA==.Hukak:BAAALgAECgQJBgAAAA==.Hundrakor:BAABLgAECn8UAAITAAkJ6hJ5OAD8AQATAAkJ6hJ5OAD8AQAAAA==.Hunteir:BAAALgAECgMJAwAAAA==.Huntinghawk:BAAALgAECgEJAQABLgAECgYJGQATADYMAA==.Hutzil:BAABLgAECn8mAAMCAAkJaB3bJQBGAgACAAkJchvbJQBGAgAeAAUJwxvDHQDSAAAAAA==.Hutzilla:BAAALgAECgYJCgAAAA==.',
['Hÿ']='Hÿpothermia:BAAALgAECgMJAwAAAA==.',
Ia='Iakopa:BAABLgAFFH8LAAILAAUJ7xZqCgAqAQALAAUJ7xZqCgAqAQAAAA==.',
Il='Illidianna:BAABLgAECn8hAAMHAAkJjBczKwAcAgAHAAkJjBczKwAcAgAbAAIJixJiXABvAAAAAA==.',
Im='Imbluedabdee:BAAALgADCgcJDQAAAA==.Imitlol:BAAALgAFFAEJAQAAAA==.',
In='Inception:BAAALgAECgIJAgAAAA==.',
Ir='Iranûk:BAAALgADCgYJBgAAAA==.Irrefutable:BAAALgADCgQJBAAAAA==.Irwinn:BAAALgAECgMJAwAAAA==.',
It='Itchynyple:BAAALgADCggJCAAAAA==.',
Ja='Jabadabadoo:BAAALgAECgEJAQAAAA==.Jables:BAAALgADCgQJBAABLgAECgkJLAARAO4lAA==.Jackatak:BAAALgADCgMJAwABLgAECggJIAAgAA8fAA==.Jacoblack:BAAALgADCgMJAwAAAA==.Jacques:BAAALgAECgMJAwAAAA==.Jadin:BAAALgADCgEJAQABLgAECggJIAAgAA8fAA==.Jaefury:BAABLgAECn8iAAIPAAkJoR3fBQB/AgAPAAkJoR3fBQB/AgAAAA==.Jakes:BAAALgAECgQJBgAAAA==.Jandinga:BAAALgAECgQJBAAAAA==.',
Je='Jeabuschrist:BAAALgAECgEJAQAAAA==.',
Ji='Jimadler:BAAALgADCgMJAwABLgAECgYJBwAEAAAAAA==.Jimbi:BAAALgAFFAIJBAAAAA==.Jiminybilini:BAAALgAFFAIJAQAAAA==.Jimmybull:BAAALgADCgEJAQAAAA==.Jinho:BAAALgAECgEJAQABLgAECgkJJgAiAEcWAA==.Jinrop:BAEALgADCgcJBwABLgAECgcJFgAfACMUAA==.',
Jo='Jobuu:BAAALgAECgEJAgAAAA==.Jock:BAAALgAECgQJCAAAAA==.Johnnypopoff:BAABLgAECn8kAAIcAAkJOxQpVwDYAQAcAAkJOxQpVwDYAQAAAA==.Johnwolf:BAAALgAECgQJCQAAAA==.Jojohunts:BAAALgAECgcJDgAAAA==.Jose:BAAALgAECgEJAQABLgAECgkJIAABAAMgAA==.Joshodin:BAAALgAECgEJAQAAAA==.',
Jp='Jpðc:BAAALgAECgYJCgAAAA==.',
Ju='Juanjo:BAAALgADCgcJBwABLgAECgkJMwAcAA4eAA==.Junebugg:BAAALgADCgYJBgAAAA==.Junyubych:BAABLgAECn8hAAMfAAgJJwpFFgD1AAAfAAgJdAhFFgD1AAACAAYJZAjQDQC+AAAAAA==.Justylln:BAAALgAECgYJCQAAAA==.Justzach:BAABLgAECn83AAIQAAkJXhq3DQBdAgAQAAkJXhq3DQBdAgAAAA==.',
['Jà']='Jàccuse:BAABLgAECn8kAAIdAAkJCRIJLgDFAQAdAAkJCRIJLgDFAQAAAA==.Jàrnsaxa:BAAALgADCgEJAQAAAA==.',
['Jò']='Jòhnnypopo:BAABLgAECn8eAAIBAAkJ0xqJQQACAgABAAkJ0xqJQQACAgAAAA==.',
Ka='Kadywompus:BAAALgADCgcJBwAAAA==.Kaeladra:BAAALgAFFAEJAQABLgAFFAMJBQANAHcFAA==.Kagannh:BAAALgADCgYJBgAAAA==.Kailm:BAAALgADCgIJAgABLgAFFAYJDgAWAA4dAA==.Kaimilla:BAAALgADCgIJAgAAAA==.Kait:BAAALgAECgIJAgAAAA==.Kalida:BAAALgADCgQJBAAAAA==.Kalniel:BAAALgADCgUJBQAAAA==.Kalorie:BAAALgADCgYJBgABLgAECgcJLwAbAP0eAA==.Kassaalaa:BAAALgADCgYJBgAAAA==.Kasumeli:BAAALgAECgQJBQAAAA==.Kaylastrasza:BAAALgAECgEJAQAAAA==.Kazoo:BAAALgADCgYJBgABLgADCgYJBgAEAAAAAA==.Kazurend:BAACLgAFFH8iAAIgAAgJGSHCAQCpAgAgAAgJGSHCAQCpAgAuAAQKfxoAAiAACAnQI7wFADMDACAACAnQI7wFADMDAAAA.',
Ke='Keiadon:BAAALgAECgYJCwAAAA==.Kelavax:BAAALgAECgkJBQAAAA==.Keleira:BAABLgAECn8XAAIcAAgJXhdvXQDGAQAcAAgJXhdvXQDGAQAAAA==.Kelemvore:BAAALgAECgEJAQAAAA==.Kericcandere:BAAALgADCgIJAwAAAA==.Kerm:BAEALgAECgEJAgAAAA==.Keyaielenst:BAAALgADCgcJBwAAAA==.',
Kh='Khristina:BAAALgADCgkJEAAAAA==.Khrogh:BAABLgAFFH8FAAINAAMJdwUCOACNAAANAAMJdwUCOACNAAAAAA==.',
Ki='Kiel:BAABLgAFFH8HAAIbAAQJlhy0FwDlAAAbAAQJlhy0FwDlAAABLgAFFAMJBwAiAJsYAA==.Kindos:BAAALgADCgQJBwAAAA==.Kippo:BAEALgAECgEJAQABLgAFFAcJFQASALYRAA==.Kiramman:BAAALgAECgUJDAAAAA==.Kirsute:BAAALgADCgYJBgAAAA==.Kirxcy:BAAALgADCgUJCAAAAA==.Kisarrah:BAAALgAECgkJCgAAAA==.Kithiri:BAABLgAECn8dAAIUAAYJsAZsRwDpAAAUAAYJsAZsRwDpAAAAAA==.',
Kn='Knarn:BAABLgAECn8oAAIYAAkJDB5REAAsAgAYAAkJDB5REAAsAgAAAA==.',
Ko='Koralie:BAACLgAFFH8mAAMTAAgJ+BTWAACrAQATAAcJ3hbWAACrAQAZAAEJkAkONgBHAAAuAAQKfx4AAxMACAloHW4bAGICABMACAloHW4bAGICABkABQm+D6VcANAAAAAA.Korheo:BAAALgAECgEJAgAAAA==.',
Kr='Krillaxx:BAAALgAECgcJDwAAAA==.Krimzin:BAAALgAFFAMJAwABLgAFFAUJGwATADAhAA==.Krolg:BAAALgAECgcJDgAAAA==.Kromvar:BAAALgAECgQJBwAAAA==.',
Ku='Kungfused:BAAALgADCgUJCAABLgAECgQJBgAEAAAAAA==.Kurisux:BAABLgAFFH8NAAISAAQJJRvDUABQAQASAAQJJRvDUABQAQAAAA==.',
Ky='Kyliekat:BAABLgAECn8VAAIaAAkJYwrlPQAYAQAaAAkJYwrlPQAYAQAAAA==.Kyndlynn:BAAALgAECgQJEAAAAA==.Kyriea:BAAALgAECgEJAQAAAA==.',
La='Lanceelot:BAAALgAECgIJAgAAAA==.Lanel:BAAALgAFFAEJAQAAAA==.Lathelous:BAABLgAECn8oAAIOAAkJ2SK3AgD+AgAOAAkJ2SK3AgD+AgAAAA==.',
Ld='Ldt:BAAALgADCgMJAwAAAA==.',
Le='Leintheir:BAAALgAECgMJAwAAAA==.Leththol:BAAALgADCgkJJQAAAA==.Letyoudie:BAAALgAECgQJCwAAAA==.Levenza:BAABLgAECn8UAAIIAAgJYhSpEABCAQAIAAgJYhSpEABCAQAAAA==.',
Li='Lichnight:BAAALgADCgUJBQAAAA==.Licita:BAAALgAECgUJCgAAAA==.Lickingsalt:BAAALgAECgQJBAAAAQ==.Lideina:BAABLgAECn8lAAISAAcJDh4aTQDbAQASAAcJDh4aTQDbAQAAAA==.Lielandra:BAAALgAECgcJCAAAAA==.Lightdinger:BAAALgAFFAIJAgAAAA==.Lightt:BAABLgAECn9WAAMGAAkJLx91CQDRAgAGAAkJLx91CQDRAgAgAAUJNQEQVQBvAAAAAA==.Liightt:BAABLgAECn8iAAIGAAcJqhjIHQDWAQAGAAcJqhjIHQDWAQAAAA==.Lilnug:BAAALgAECgQJDAAAAA==.Lindsey:BAAALgADCgkJDQABLgAECgUJCwAEAAAAAA==.Littlenyne:BAAALgAECggJEgAAAA==.',
Ll='Llando:BAAALgADCgYJBgAAAA==.Llars:BAABLgAECn8oAAIMAAkJrBgqHwBVAgAMAAkJrBgqHwBVAgAAAA==.Lleonardo:BAAALgADCgEJAQAAAA==.',
Lo='Lockkjaw:BAAALgAECgEJAQAAAA==.Locknorris:BAAALgADCgUJBgAAAA==.Loghrif:BAAALgAECgQJBAABLgAECgUJBgAEAAAAAA==.Loptear:BAAALgAECgEJAQAAAA==.Loryanna:BAAALgADCgUJCwAAAA==.Louie:BAAALgAFFAMJBAAAAA==.Lovebank:BAAALgAECgMJAwAAAA==.Lovehandless:BAAALgADCgEJAQAAAA==.Lovespell:BAAALgADCgUJBQAAAA==.',
Lu='Lucavian:BAAALgAECggJEQAAAA==.Lucavias:BAAALgAECgMJBQAAAA==.Luckydruidh:BAABLgAECn8hAAMDAAkJ7R01CwALAwADAAkJ7R01CwALAwAaAAEJxQ3vewA6AAAAAA==.Luckyevoker:BAAALgADCgcJEgABLgAECgkJIQADAO0dAA==.Luckyjax:BAAALgAECgEJAQAAAA==.Lumenne:BAAALgAECgIJAgAAAA==.Lurien:BAABLgAECn8YAAIbAAkJbhV+GgCsAQAbAAkJbhV+GgCsAQAAAA==.Luxilejo:BAAALgADCgYJCwAAAA==.Luxore:BAAALgAECgYJDAABLgAFFAUJCwALAO8WAA==.',
Ly='Lyfebane:BAACLgAFFH8SAAMBAAQJ8A1YGQD3AAABAAQJ8A1YGQD3AAANAAIJZwnXPwBjAAAuAAQKfzoAAwEACQkYF5M6ABkCAAEACQkYF5M6ABkCAA0ACAncGDIhAPoBAAAA.Lynnah:BAAALgAECgEJAQAAAA==.',
['Ló']='Lórien:BAAALgADCgEJAQAAAA==.',
['Lø']='Lørs:BAABLgAECn9BAAIcAAkJYxYmDAAtAQAcAAkJYxYmDAAtAQAAAA==.Lørz:BAAALgAECgQJBAAAAA==.',
Ma='Machorn:BAAALgADCgcJBwAAAA==.Mageis:BAAALgADCgMJAwAAAA==.Magetree:BAAALgAFFAIJAgABLgAFFAYJDgAOAFsXAA==.Mageyoucream:BAAALgAECgYJCgAAAA==.Magnai:BAAALgADCgcJBwAAAA==.Main:BAABLgAECn87AAIBAAkJKwuieQB7AQABAAkJKwuieQB7AQAAAA==.Majrmiståke:BAACLgAFFH8OAAIcAAQJQxduUQA6AQAcAAQJQxduUQA6AQAuAAQKfxsAAhwACAk9HdYqAG8CABwACAk9HdYqAG8CAAEuAAUUBgkaAAcACRwA.Malagore:BAAALgAFFAEJAQABLgAECggJFwAVALQVAA==.Malantir:BAAALgAECgYJBgABLgAECggJFwAVALQVAA==.Malec:BAAALgADCggJCAAAAA==.Malicemech:BAAALgAECgEJAQAAAA==.Maliceone:BAABLgAECn8hAAIWAAcJPwvoSgAaAQAWAAcJPwvoSgAaAQAAAA==.Malicepaly:BAAALgAECgUJEAAAAA==.Maliceshammy:BAAALgADCgYJEAAAAA==.Manek:BAAALgAECgYJBgABLgAECgkJRAAcAKUXAA==.Mansmilk:BAAALgAECgQJBAAAAA==.Manthra:BAAALgADCgMJAwAAAA==.Mardara:BAAALgAFFAEJAQAAAA==.Marraxa:BAAALgAECgMJBgAAAA==.Maräjade:BAAALgAECgEJAQAAAA==.Mattshamon:BAAALgADCgcJBwAAAA==.Max:BAABLgAECn8ZAAICAAkJ5R4DQADdAQACAAkJ5R4DQADdAQAAAA==.Mayé:BAABLgAFFH8MAAIaAAcJqBfUEgCIAQAaAAcJqBfUEgCIAQAAAA==.',
Mb='Mbaku:BAAALgAECgcJEQABLgAFFAYJDgAgAO4aAA==.',
Mc='Mcgobbtock:BAAALgAECgEJAgAAAA==.',
Me='Melechim:BAAALgADCgkJCQAAAA==.Melinoe:BAABLgAECn8mAAICAAkJLBFHWQCRAQACAAkJLBFHWQCRAQAAAA==.Mentallywet:BAAALgAECgQJBwABLgAFFAIJCQABAEQhAA==.Meowdoh:BAABLgAFFH8FAAIXAAQJ4AnfHQCnAAAXAAQJ4AnfHQCnAAAAAA==.Merc:BAAALgAECgUJBQAAAA==.Merithrá:BAAALgAECgIJAgAAAA==.Metalgreymon:BAAALgAECgEJAQAAAA==.',
Mi='Micah:BAACLgAFFH8iAAMKAAgJwg5xBQChAQAKAAgJwg5xBQChAQAVAAMJ7QtiFgDCAAAuAAQKfyAAAwoACAmPIAgOAFYCAAoACAmPIAgOAFYCABUABQm/GpsyADUBAAAA.Milenad:BAAALgAECgIJAgAAAA==.Milkandhoney:BAAALgADCgEJAQABLgAECgkJLQAGAHYZAA==.Minilyfe:BAAALgAECgMJAwAAAA==.Mirelia:BAAALgADCgMJAgAAAA==.Mishosuki:BAABLgAECn8ZAAISAAYJBA3jxgD1AAASAAYJBA3jxgD1AAAAAA==.Misky:BAAALgADCgEJAQAAAA==.Misscleo:BAABLgAECn86AAIcAAkJQhp9BgCcAQAcAAkJQhp9BgCcAQAAAA==.Mizzyboii:BAAALgADCgMJAwAAAA==.',
Mk='Mk:BAAALgAECggJDwAAAA==.',
Mn='Mnesarte:BAABLgAECn8XAAIBAAYJZRbTsgAbAQABAAYJZRbTsgAbAQAAAA==.',
Mo='Moanalisa:BAAALgAECgQJCgAAAA==.Mobmagnet:BAABLgAFFH8FAAIIAAMJog2CAwCtAAAIAAMJog2CAwCtAAAAAA==.Moi:BAABLgAFFH8IAAIVAAUJBhNtMQD8AAAVAAUJBhNtMQD8AAABLgAFFAQJDwAcAIsdAA==.Moltres:BAEBLgAFFH8IAAIVAAUJBiVfFwCuAQAVAAUJBiVfFwCuAQABLgAFFAkJHwAVAK8jAA==.Moonkist:BAABLgAECn8ZAAMDAAgJ5hoqGwBsAgADAAgJ5hoqGwBsAgAaAAEJRAN6jQAhAAAAAA==.Moonsgrace:BAAALgADCgkJGQAAAA==.Moose:BAACLgAFFH8MAAISAAMJPSEccgAbAQASAAMJPSEccgAbAQAuAAQKf0kAAhIACAlDJVYDABcCABIACAlDJVYDABcCAAAA.Morpheos:BAABLgAECn8bAAMDAAkJbRVMTQBaAQADAAkJbRVMTQBaAQAaAAQJhgdEYgCRAAAAAA==.Morroe:BAAALgADCgEJAQAAAA==.Moxci:BAAALgAECgQJBQAAAA==.',
Mu='Mudamudamuda:BAAALgADCgYJDQABLgAFFAUJEwAWAEAbAA==.Muffintop:BAAALgAECgQJBAAAAA==.',
My='Mysticforest:BAAALgAECgQJBAAAAA==.',
Na='Naedise:BAAALgADCgcJFgAAAA==.Narue:BAAALgAECgIJAgAAAA==.Natureswild:BAABLgAECn8gAAMaAAkJkhiUIQDwAQAaAAgJ4xeUIQDwAQADAAMJawrZuQBSAAAAAA==.Navariis:BAAALgAECgUJEgAAAA==.Navillus:BAAALgAECgMJBgABLgAFFAgJKQAKADQQAA==.',
Ne='Necrophyliac:BAAALgAECgYJCwAAAA==.Nelrehim:BAAALgAECgEJAQAAAA==.Nelumbo:BAAALgAFFAcJBAABLgAFFAkJBQAKAEwVAA==.Nephy:BAAALgAECgQJBAAAAA==.Nephyrium:BAAALgAECgUJCAAAAA==.Nephz:BAAALgAECgYJCgAAAA==.Nephzz:BAAALgAECgQJAwAAAA==.Nethery:BAAALgADCgcJCQAAAA==.Nex:BAAALgAECgEJAQAAAA==.Nezrin:BAABLgAECn8VAAMGAAgJLCFzCQDSAgAGAAgJLCFzCQDSAgAgAAEJMBhVewBIAAAAAA==.',
Ni='Niandilan:BAAALgAECgQJBAAAAA==.Nidon:BAAALgADCgUJBQAAAA==.Niixxi:BAAALgADCgUJBQAAAA==.',
Nm='Nmbrs:BAABLgAECn8gAAMgAAgJDx/tEgA6AgAgAAgJDx/tEgA6AgAUAAEJ7AK9XAApAAAAAA==.',
No='Noirheffer:BAACLgAFFH8OAAMOAAYJWxfcCADpAAAOAAYJlhDcCADpAAABAAMJ9hSqcADQAAAuAAQKfycAAwEACQnXHvcXANkCAAEACAlDIvcXANkCAA4ABwkXF/oSAJkBAAAA.Nokua:BAAALgAECgUJBQABLgAECggJIQAfACcKAA==.Noobishdad:BAAALgAECgMJAwAAAA==.Norio:BAAALgADCgcJBwAAAA==.Norrva:BAAALgAECgkJCQAAAA==.Notafurrie:BAAALgAECgQJBwAAAA==.',
Nu='Nulannatoo:BAAALgAECgUJBQAAAA==.Numz:BAAALgAECgIJAwAAAA==.Nuukeasaur:BAAALgADCgEJAQAAAA==.',
Ny='Nyadari:BAAALgAECgEJAQAAAA==.Nyank:BAAALgAECgEJAQABLgAFFAIJCgASAJQQAA==.Nyphe:BAAALgAECgQJBAAAAA==.Nyrrhi:BAAALgAECgQJCAAAAA==.Nyxiro:BAAALgAECgUJBQAAAA==.',
Oc='Oculus:BAAALgAECgMJAwAAAA==.',
Od='Odysseus:BAAALgAECgEJAQAAAA==.',
Ol='Oleira:BAAALgAECgUJBQAAAA==.Olgann:BAAALgAECgkJEwAAAA==.Olguita:BAABLgAFFH8JAAILAAMJZxIMMgDIAAALAAMJZxIMMgDIAAAAAA==.Olivertwìst:BAAALgADCgcJBwAAAA==.',
Om='Omgowned:BAAALgAECgYJCwABLgAECgkJIgACAFwYAA==.Omnipresent:BAAALgAECgcJCgAAAA==.',
On='Onehothealer:BAABLgAECn8aAAIgAAkJIBbsGQAQAgAgAAkJIBbsGQAQAgAAAA==.',
Oo='Oorua:BAAALgADCgkJDwAAAA==.',
Op='Opheliastar:BAACLgAFFH8MAAIgAAMJXhMoEACXAAAgAAMJXhMoEACXAAAuAAQKfy0AAiAACQnmEzMeANQBACAACQnmEzMeANQBAAAA.',
Ow='Owltoidz:BAAALgAECgEJAgAAAA==.',
Pa='Pace:BAAALgAECgUJCwAAAA==.Pad:BAABLgAECn8ZAAMCAAcJpAqnlgAPAQACAAYJpAqnlgAPAQAfAAEJAAAzdQAwAAAAAA==.Pahket:BAAALgAECgQJBAAAAA==.Paintballerr:BAAALgADCgEJAQAAAA==.Paladerp:BAABLgAECn82AAMNAAgJGA9rOQBmAQANAAgJGA9rOQBmAQABAAcJOxEKmgBBAQAAAA==.Pallyown:BAABLgAFFH8KAAINAAIJayOELwC5AAANAAIJayOELwC5AAAAAA==.Paprika:BAAALgADCgQJBgAAAA==.Parox:BAAALgADCgUJBgAAAA==.Pastorbedtym:BAABLgAECn8YAAIgAAgJeA+1NgA7AQAgAAgJeA+1NgA7AQAAAA==.Pat:BAAALgAECgMJAwAAAA==.Paulybricks:BAAALgAECgUJBgAAAA==.',
Pe='Pecan:BAAALgAECgcJDgABLgAFFAQJCAAcAAYhAA==.Pewpewbang:BAAALgADCgIJAgAAAA==.',
Ph='Phanomimama:BAAALgAECgEJAQABLgAECgkJOQAZACcRAA==.Pharla:BAAALgADCgkJEAAAAA==.Phelement:BAAALgADCgMJAwAAAA==.Phett:BAABLgAFFH8GAAIWAAMJMB1vDQD6AAAWAAMJMB1vDQD6AAAAAA==.',
Pi='Pichon:BAAALgADCgUJCAAAAA==.Piffi:BAAALgAECgUJBQAAAA==.Pimmscup:BAAALgAECgUJCAAAAA==.Pin:BAAALgAECgcJBgABLgAFFAkJBQAKAEwVAA==.Pirei:BAAALgADCgUJBQAAAA==.Pirozhki:BAAALgADCgYJBgAAAA==.',
Pl='Plagueborn:BAAALgAECgEJAQAAAA==.Plentar:BAAALgADCgkJDgAAAA==.',
Po='Popcorntea:BAAALgAECgEJAgAAAA==.Porgoon:BAAALgAECgQJBQAAAA==.',
Pr='Preferred:BAAALgAECgUJBQAAAA==.Preserved:BAAALgADCgIJAgAAAA==.Prizzma:BAAALgADCgUJBQAAAA==.',
Ps='Psaul:BAAALgAECgYJCwAAAA==.Psychohexane:BAAALgADCgQJBAAAAA==.',
Py='Pyramys:BAAALgADCgYJBgABLgAFFAUJEwAiACwfAA==.',
Qe='Qedesh:BAAALgAECggJCAAAAA==.Qesem:BAAALgADCgUJBQAAAA==.',
Qu='Qualaribou:BAAALgADCgQJBAAAAA==.',
Ra='Raal:BAAALgADCgkJHgAAAA==.Raenostra:BAABLgAECn8UAAMbAAUJcAU+DABlAAAbAAQJcAU+DABlAAAHAAUJVgL2/ABPAAAAAA==.Raenya:BAABLgAECn8aAAIBAAgJcAj5DAAdAQABAAgJcAj5DAAdAQAAAA==.Ragefather:BAAALgADCgEJAQAAAA==.Rageye:BAAALgADCgcJBwAAAA==.Rainydaze:BAABLgAECn8UAAIGAAkJfwdxOgAOAQAGAAkJfwdxOgAOAQAAAA==.Ramcharger:BAABLgAECn8gAAMIAAgJzBUYCwCrAQAIAAgJzBUYCwCrAQAbAAYJoAzEOwARAQAAAA==.Ranen:BAABLgAECn8gAAIRAAkJ4B0EDgBnAgARAAkJ4B0EDgBnAgAAAA==.Rashun:BAABLgAECn8UAAIRAAkJZxnZEQA0AgARAAkJZxnZEQA0AgAAAA==.Rayvin:BAAALgADCgYJDAAAAA==.',
Re='Reanatilax:BAAALgADCgkJFQABLgAECgkJOAAUAEYTAA==.Redcinnabar:BAABLgAECn8XAAIaAAYJZAT7XwCZAAAaAAYJZAT7XwCZAAAAAA==.Regisfilia:BAAALgAECgYJCQABLgAECgcJLwAbAP0eAA==.Rehtilox:BAAALgAECgMJAwABLgAECgkJOAAUAEYTAA==.Reilly:BAAALgADCggJFQAAAA==.Rev:BAAALgAECgQJBAAAAA==.Rexxy:BAABLgAECn8kAAMLAAgJrRRDAwCHAQALAAgJrRRDAwCHAQAMAAEJcQEBrAAbAAAAAA==.',
Ri='Riju:BAAALgAECgcJDgAAAA==.Rikamira:BAAALgADCgEJAQAAAA==.Rikashae:BAAALgAECgEJAgAAAA==.Rillan:BAAALgADCgMJAwAAAA==.Rinzler:BAAALgAECggJEQAAAA==.Rissa:BAAALgAECggJDQAAAA==.',
Rn='Rng:BAAALgAECgQJCwAAAA==.',
Ro='Roachcentral:BAAALgADCgUJBgAAAA==.Roachcity:BAAALgADCgUJBQAAAA==.Rockalock:BAAALgADCgYJBgAAAA==.Rogerz:BAAALgADCgUJBQAAAA==.Roguefordays:BAAALgAECgUJBQAAAA==.Roleon:BAAALgAECgQJBAABLgAECgQJBwAEAAAAAA==.Rollforpi:BAAALgAFFAEJAgABLgAFFAgJIgADAGgXAA==.Ropebunnyana:BAACLgAFFH8WAAMdAAYJRBkFCwB4AQAdAAYJRBkFCwB4AQARAAIJdwjVNgBsAAAuAAQKfysAAh0ACQlEIEIHACsDAB0ACQlEIEIHACsDAAAA.Rowkani:BAAALgADCgkJCQAAAA==.',
Ru='Ruki:BAABLgAECn8vAAMbAAcJ/R7tAgCAAQAHAAcJbBtXUwCMAQAbAAYJeyHtAgCAAQAAAA==.Runehelm:BAAALgAECgQJBAAAAA==.',
Ry='Ryand:BAAALgAECgUJCQABLgAFFAcJKwAiADwbAA==.',
Sa='Sacra:BAAALgAECgEJAQAAAA==.Salarcyn:BAAALgAECgUJDAAAAA==.Sallypally:BAAALgAECgYJBgAAAA==.Saltydk:BAABLgAFFH8QAAMSAAYJ8RSWEQCKAQASAAUJ8RSWEQCKAQAFAAEJAACCXQAAAAAAAA==.Samiracy:BAABLgAECn88AAIfAAkJ6B9VAQDcAgAfAAkJ6B9VAQDcAgAAAA==.Sanazureset:BAAALgAECggJCAAAAA==.Sannrin:BAAALgAECgYJDAAAAA==.Santhrin:BAAALgAECgMJAwAAAA==.Sapprot:BAAALgADCgcJCQAAAA==.Sarkress:BAAALgADCgkJCQAAAA==.Sataro:BAAALgADCgEJAQAAAA==.',
Sc='Schwãrtz:BAAALgADCgEJAQAAAA==.',
Se='Seagal:BAAALgADCgEJAgAAAA==.Sebek:BAAALgAECgEJAgAAAA==.Senbatorii:BAABLgAECn8hAAQDAAkJohuvIgA0AgADAAgJ8hqvIgA0AgAaAAgJ8wn4PgATAQAhAAUJfAfYKACGAAAAAA==.Senestra:BAAALgAECgIJAgAAAA==.Seredala:BAAALgADCgUJCwAAAA==.Serendragosa:BAAALgAECgMJAwAAAA==.Sethrow:BAABLgAECn8iAAQCAAkJXBjLIABgAgACAAgJXBjLIABgAgAeAAEJAABbSQAAAAAfAAEJAACfUgAAAAAAAA==.Severa:BAAALgAECgkJEgAAAA==.',
Sh='Shadowmouse:BAAALgADCgEJAQAAAA==.Shaladora:BAAALgADCgYJBgAAAA==.Shalia:BAAALgADCgMJAwABLgAECgEJAQAEAAAAAA==.Shamaster:BAAALgADCgIJAgAAAA==.Shambamtymam:BAAALgAECgEJAQAAAA==.Shamwowza:BAABLgAECn8WAAMMAAYJeg8OCAA2AQAMAAYJeg8OCAA2AQALAAIJqQHMsAAoAAAAAA==.Sharas:BAAALgAECgQJBQAAAA==.Shawarma:BAAALgAECgYJCwAAAA==.Sheltatha:BAAALgAECgEJAQAAAA==.Shengari:BAABLgAECn8nAAIGAAgJbBK9MAB+AQAGAAgJbBK9MAB+AQAAAA==.Shenma:BAAALgAECgEJAQAAAA==.Shoshanaa:BAAALgAECgYJDgAAAA==.Shotcallà:BAAALgADCgIJAgAAAA==.Shuna:BAAALgAECgUJDQAAAA==.Shyly:BAABLgAECn8XAAIgAAkJqBxnDwBkAgAgAAkJqBxnDwBkAgAAAA==.Shâbs:BAAALgAFFAIJAgAAAA==.Shâmbâmtymâm:BAAALgAECgQJBAAAAA==.',
Si='Sikkly:BAAALgADCgcJEQAAAA==.Siley:BAABLgAECn9ZAAISAAkJOBaLQAABAgASAAkJOBaLQAABAgAAAA==.Sin:BAAALgAECgcJCAAAAA==.Siphon:BAAALgADCgYJBgAAAA==.',
Sk='Skarletfaith:BAABLgAECn8UAAIBAAgJ0QWKxAACAQABAAgJ0QWKxAACAQAAAA==.',
Sl='Sloanya:BAABLgAECn85AAMdAAkJXR45CgD1AgAdAAkJXR45CgD1AgARAAYJKxqmJQCqAQAAAA==.',
Sn='Snarffie:BAAALgAECgYJCgAAAA==.',
So='Sokaz:BAAALgADCgYJBgAAAA==.Solanar:BAAALgADCgUJBQAAAA==.Somavan:BAAALgADCgcJDQABLgAFFAQJDAAYAMIQAA==.Somedruid:BAABLgAECn8xAAIaAAkJDiSJBAAWAwAaAAkJDiSJBAAWAwAAAA==.',
Sp='Sparkyflower:BAAALgADCgEJAQAAAA==.Spiarmf:BAAALgAECgYJBgAAAA==.Spicynes:BAAALgAECgQJAQAAAA==.Spicyness:BAAALgAECgMJBQAAAA==.Spiderdk:BAAALgAECgUJCAABLgAFFAcJIQATAJ0fAA==.Spidermonk:BAAALgAFFAIJAwABLgAFFAcJIQATAJ0fAA==.Spielberg:BAAALgAECgIJAwAAAA==.Spycmchaggis:BAAALgAECgQJBAAAAA==.Spëcter:BAAALgAECgcJCgABLgAECggJEgAEAAAAAA==.Spëcthyr:BAAALgAECggJEgAAAA==.',
Sq='Squishypoo:BAAALgAECgMJBgAAAA==.',
St='Stache:BAAALgAECgEJAQAAAA==.Starkiller:BAAALgAECgEJAQABLgAECgYJDgAEAAAAAA==.Stoneyfoam:BAAALgAECgYJBgAAAA==.Stormrider:BAAALgADCgkJCQAAAA==.Stratergron:BAAALgAECgcJAQAAAA==.Strañger:BAAALgAFFAEJAgABLgAFFAIJBgAQANgLAA==.Styless:BAAALgAECgUJBQAAAA==.',
Su='Sugrace:BAAALgAECgYJBgAAAA==.Superdemonzz:BAACLgAFFH8aAAIHAAYJCRxvMwBXAQAHAAYJCRxvMwBXAQAuAAQKfz0AAwcACQlcImsRALcCAAcACQknIGsRALcCAAgABwnCH84GACICAAAA.Superevokerz:BAAALgADCgcJDgABLgAFFAYJGgAHAAkcAA==.Superlockz:BAABLgAFFH8LAAICAAUJzAoVGQAHAQACAAUJzAoVGQAHAQABLgAFFAYJGgAHAAkcAA==.Superpallyz:BAACLgAFFH8UAAINAAQJoxqaCwDlAAANAAQJoxqaCwDlAAAuAAQKfzQAAw0ABwlfIZsTAHMCAA0ABwlfIZsTAHMCAA4ABQkhES8sALwAAAEuAAUUBgkaAAcACRwA.Supershamanz:BAAALgAECgYJCwABLgAFFAYJGgAHAAkcAA==.Superspidey:BAAALgADCgIJAgAAAA==.Sushiroll:BAABLgAECn8XAAIRAAgJPx6+EgApAgARAAgJPx6+EgApAgABLgAFFAkJFwAcAEYiAA==.',
Sw='Swipeleft:BAAALgAECgEJAQAAAA==.',
Sy='Sydnysweeney:BAAALgADCgMJAwAAAA==.Sylentslit:BAAALgADCggJGgAAAA==.Sylveslem:BAAALgAECgkJDAAAAA==.Syphon:BAAALgADCgMJAwAAAA==.Syrohk:BAAALgAECgEJAQAAAA==.',
['Sô']='Sôlmyr:BAAALgADCgIJAgAAAA==.',
Ta='Tacowarr:BAAALgADCgUJBQAAAA==.Taiynn:BAAALgAECgYJDwAAAA==.Taldazlian:BAAALgAECgMJBgAAAA==.Taliesin:BAAALgAECgMJAwAAAA==.Tallon:BAAALgAECgEJAQABLgAFFAYJIAAVAF4dAA==.Tancy:BAAALgAECgMJAwABLgAFFAQJEgADAC0MAA==.Tantalus:BAABLgAECn8eAAITAAgJ2Qu7gQA7AQATAAgJ2Qu7gQA7AQAAAA==.Tarogen:BAAALgADCgUJBQAAAA==.Tashaler:BAAALgADCgEJAQAAAA==.Tasithia:BAAALgAECgQJBAAAAA==.',
Te='Tealet:BAAALgADCgkJEQAAAA==.Teleion:BAAALgAECgEJAQAAAA==.Tellinor:BAABLgAECn8YAAIBAAYJAQqi3gDgAAABAAYJAQqi3gDgAAAAAA==.Temporal:BAAALgAECgEJAQAAAA==.Tendroni:BAAALgAFFAEJAgAAAA==.Terrestra:BAAALgADCgMJAwAAAA==.Tervor:BAAALgAECgMJAwAAAA==.',
Th='Thanamoros:BAAALgAECgUJBgABLgAFFAUJCwALAO8WAA==.Thassarian:BAAALgAECgQJBAABLgAECggJIwAIABkfAA==.Thechosenone:BAAALgADCgIJAgAAAA==.Theroach:BAABLgAECn8UAAICAAYJRQmerwDlAAACAAYJRQmerwDlAAAAAA==.Tholdir:BAAALgAECgYJBgAAAA==.Throfin:BAAALgAECgUJCgAAAA==.Thundernight:BAAALgAECgcJAgAAAA==.',
Ti='Tiki:BAAALgAECgUJBwAAAA==.Tinc:BAAALgADCgEJAgAAAA==.Tinkerballa:BAAALgADCgUJBQAAAA==.Tinonova:BAAALgAECgEJAgAAAA==.Titsmgee:BAAALgAECgIJAgAAAA==.',
Tl='Tlcbm:BAAALgAECgYJBgAAAA==.',
To='Toadtroll:BAAALgADCgIJAgAAAA==.Toeren:BAACLgAFFH8hAAITAAcJnR/fEADdAQATAAcJnR/fEADdAQAuAAQKfzUAAhMACQktIWMJAA4DABMACQktIWMJAA4DAAAA.Tomate:BAAALgADCgQJBAAAAA==.Toph:BAAALgAECgEJAQAAAA==.Torage:BAAALgAECgEJAgAAAA==.Tormented:BAAALgAECgYJEwAAAA==.Townsley:BAAALgAECgYJDQAAAA==.',
Tp='Tpain:BAAALgAECgMJAwAAAA==.',
Tr='Traitoros:BAAALgADCgYJBgAAAA==.Tralectra:BAAALgAECgcJDAAAAA==.Tranquilfist:BAAALgADCgQJBQABLgAECggJFAABANEFAA==.Treemonk:BAAALgADCgYJCgABLgAECgkJIAAaAJIYAA==.Trenity:BAAALgAECgUJCAAAAA==.Triomphe:BAAALgAECgEJAQAAAA==.Triplecanopy:BAAALgAECgcJBQAAAA==.Trolvere:BAAALgAECgQJBwAAAA==.Trorim:BAAALgADCgYJBgAAAA==.Truewarchief:BAAALgAECgEJAQAAAA==.Trïsh:BAAALgAFFAEJAQABLgAFFAMJBwAHAAQEAA==.',
Tu='Tummy:BAAALgADCgcJEwAAAA==.Turtlesoup:BAAALgADCgYJBgAAAA==.',
Tw='Twëë:BAAALgAECgQJBQAAAA==.',
Ty='Tybonk:BAAALgAECgEJAQAAAA==.Tygragon:BAAALgAECgYJEAAAAA==.Tyinorin:BAAALgAECgYJAQAAAA==.Tylea:BAAALgADCgkJEQAAAA==.',
Tz='Tzipporah:BAAALgAECggJDwAAAA==.',
['Tä']='Täryn:BAAALgADCgYJBgAAAA==.',
Ub='Ubee:BAABLgAECn8cAAIHAAkJ8RH5QwC8AQAHAAkJ8RH5QwC8AQAAAA==.',
Ud='Udderjustice:BAAALgAECgIJAgAAAA==.',
Ug='Uglyelf:BAAALgAECgYJBgAAAA==.',
Ul='Ultimakitty:BAABLgAECn8WAAMDAAcJcRkJPwCVAQADAAYJOhcJPwCVAQAaAAYJ6gmuTQDWAAAAAA==.',
Un='Uncertainty:BAAALgAECgYJDwABLgAECgcJLwAbAP0eAA==.Unchanged:BAAALgADCgYJBgAAAA==.Unholymana:BAAALgAECgIJAgAAAA==.Unknighted:BAAALgAECgYJBgAAAA==.',
Ur='Ur:BAAALgAECgEJAQAAAA==.',
Va='Vaellin:BAAALgAECgEJAQAAAA==.Valanyr:BAAALgADCgEJAQAAAA==.Valgemon:BAAALgAECgQJBAAAAA==.Vantrix:BAAALgAECgEJAQABLgAFFAUJCwALAO8WAA==.Varabo:BAABLgAECn8dAAIcAAgJhhXagQB0AQAcAAgJhhXagQB0AQAAAA==.Varidria:BAAALgAECgYJDwAAAA==.Varolina:BAAALgAECgEJAgAAAA==.',
Ve='Veelá:BAAALgAECgUJBQABLgAECgkJNAAQAOYWAA==.Vehemencê:BAAALgADCgEJAQAAAA==.Velements:BAAALgAECgMJAwABLgAECgkJFQAjAC4XAA==.Velemon:BAACLgAFFH8SAAIkAAQJ9w7mGgDAAAAkAAQJ9w7mGgDAAAAuAAQKfxkAAiQACQn8EfERAOkBACQACQn8EfERAOkBAAAA.Velielys:BAAALgADCgcJBwAAAA==.Velisen:BAABLgAECn8lAAMBAAcJQQn/zQD2AAABAAcJ6Af/zQD2AAAOAAUJ4gYWMgCFAAAAAA==.Velthala:BAABLgAECn8VAAMjAAkJLhfBEwDDAQAjAAkJjRbBEwDDAQAWAAEJqwx+ogAyAAAAAA==.Velystiri:BAAALgADCgcJBgAAAA==.Venedictus:BAAALgADCgMJAwAAAA==.',
Vi='Viergryn:BAAALgAECgEJAgABLgAECggJLgARAJYeAA==.Views:BAAALgAECgcJBwAAAA==.Virasdruid:BAABLgAFFH8GAAIDAAIJRwTOZQBQAAADAAIJRwTOZQBQAAAAAA==.Virusmonk:BAAALgAECgEJAwAAAA==.Vitner:BAABLgAECn8gAAMJAAkJ0hjmCgBrAQAJAAYJShnmCgBrAQAVAAkJ6xLUMgBpAQABLgAFFAMJCAAXANQYAA==.',
Vo='Vosaleana:BAAALgAECgQJBAAAAA==.',
Vr='Vraak:BAACLgAFFH8iAAIDAAgJaBdSCQBjAgADAAgJaBdSCQBjAgAuAAQKfycAAwMACAnhG7YrAAECAAMABwmBHbYrAAECABoABwmaIxYgAP4BAAAA.',
Vu='Vudujam:BAAALgAECgcJEAAAAA==.Vulcus:BAAALgAFFAEJBAABLgAFFAgJIgADAGgXAA==.Vulpii:BAAALgADCgYJBQABLgAFFAQJFAAeADYgAA==.',
Vy='Vyndarien:BAAALgADCgIJAgAAAA==.Vyse:BAAALgADCgEJAQAAAA==.Vyttra:BAAALgADCgMJAwAAAA==.',
Wa='Walak:BAAALgADCgMJAwAAAA==.Warpulse:BAAALgAECgIJAgAAAA==.Warwizard:BAAALgADCgMJAwAAAA==.Watcherseye:BAAALgADCggJDwABLgADCgkJCQAEAAAAAA==.Wattlez:BAAALgAECgcJCQAAAA==.Wavewhisper:BAAALgAECgEJAQAAAA==.Wayofthemist:BAAALgAECggJDwAAAA==.',
Wc='Wcreator:BAABLgAECn8vAAIBAAkJWyLnBwAtAwABAAkJWyLnBwAtAwAAAA==.',
We='Weapònized:BAABLgAECn8UAAIHAAYJWg5CpgDYAAAHAAYJWg5CpgDYAAAAAA==.Webaldes:BAAALgAECgEJAQAAAA==.',
Wh='Whitestain:BAABLgAECn8bAAIZAAgJfAoRFgAIAQAZAAgJfAoRFgAIAQAAAA==.',
Wi='Windyskie:BAAALgADCgEJAQAAAA==.Wingman:BAACLgAFFH8aAAIJAAUJxyb4AADKAQAJAAUJxyb4AADKAQAuAAQKfzQAAgkACAmXJpgAAIsDAAkACAmXJpgAAIsDAAAA.',
Wo='Womdalie:BAAALgADCgQJBgAAAA==.Woodey:BAAALgAECgEJAwAAAA==.Wowame:BAAALgAFFAEJAQAAAA==.',
Wy='Wyckedpally:BAAALgAECggJDwABLgAECggJIQAfACcKAA==.',
Xa='Xanthös:BAAALgAFFAEJAQABLgAFFAgJIgADAGgXAA==.',
Xe='Xemnastrasza:BAACLgAFFH8JAAQVAAMJEQ/VRgCtAAAVAAMJEQ/VRgCtAAAKAAIJaQMrKABVAAAJAAEJ0QNnCwBLAAAuAAQKfxYABBUACAkdFMQhALEBABUACAnSEcQhALEBAAkABAmmCPEtAKsAAAoAAQlrBYZLACsAAAEuAAUUBQkLAAsA7xYA.Xenonne:BAACLgAFFH8PAAIHAAYJJhDYNwBFAQAHAAYJJhDYNwBFAQAuAAQKfyEAAwcACAn6Gy9DAL4BAAcACAn6Gy9DAL4BABsABQl3D3FGANsAAAAA.',
Xo='Xolither:BAABLgAECn84AAMUAAkJRhOaGgD7AQAUAAkJeRKaGgD7AQAGAAUJmhO3TgD9AAAAAA==.',
Xp='Xpireedk:BAACLgAFFH8TAAMlAAUJ3iUECQBdAQAlAAUJ1CUECQBdAQASAAQJIR4DWwA9AQAuAAQKfxwAAyUACQnGJUMDAF8CACUACQnGJUMDAF8CABIABQnnHrJ1AJoBAAAA.',
Ya='Yamiyoru:BAAALgADCgYJBgABLgADCgcJBwAEAAAAAA==.',
Ye='Yelar:BAAALgAECgEJAQAAAA==.',
Yo='Yorakk:BAAALgADCgIJAgAAAA==.Yorgo:BAAALgAECgYJDQAAAA==.',
['Yá']='Yáhtzee:BAAALgAECgUJBQAAAA==.',
Za='Zachdemon:BAAALgAECgMJBAABLgAECgkJNwAQAF4aAA==.Zariala:BAABLgAECn8XAAICAAkJ7QabkgAWAQACAAkJ7QabkgAWAQAAAA==.Zatana:BAAALgAECgUJBwAAAA==.',
Ze='Zephymoo:BAACLgAFFH8GAAMhAAMJqxWvAwDdAAAhAAMJqxWvAwDdAAAaAAEJoQYpIQA1AAAuAAQKf0oAAyEACQkzIt8CAPECACEACQkzIt8CAPECABoAAgl8A9uCAC0AAAAA.Zeromus:BAAALgAECgkJCQAAAA==.Zerri:BAAALgADCgIJAgAAAA==.Zeyana:BAACLgAFFH8aAAMIAAYJohmvAwBRAQAIAAYJohmvAwBRAQAbAAEJVAH+DwBAAAAuAAQKfxkABAgACQnUGtwIAOcBAAgACQnUGtwIAOcBABsABAmVBU1RAKUAAAcAAgk9AMX3AA8AAAAA.',
Zh='Zhengshi:BAABLgAECn80AAIQAAkJ5hZPEgAjAgAQAAkJ5hZPEgAjAgAAAA==.',
Zi='Zimmerfilb:BAAALgAECgEJAQAAAA==.Zippittyzap:BAAALgAECgMJAwABLgAECggJIQAfACcKAA==.',
Zn='Znot:BAAALgADCgEJAgAAAA==.',
Zo='Zoder:BAABLgAECn8aAAIaAAcJ1xOpLABzAQAaAAcJ1xOpLABzAQAAAA==.Zoose:BAABLgAECn88AAMWAAkJwSALCADfAgAWAAkJwSALCADfAgAjAAIJURi4UwCHAAAAAA==.Zosahe:BAAALgAECgMJBAAAAA==.Zoser:BAABLgAECn8sAAIRAAkJ7iXSAQBXAwARAAkJ7iXSAQBXAwAAAA==.',
Zu='Zuckuss:BAAALgAECgcJAgAAAA==.',
['Ác']='Áceventura:BAAALgAECgcJEwAAAA==.',
['Æl']='Ælthan:BAAALgAECgEJAQAAAA==.',
['Ér']='Érubus:BAAALgAECgMJBQAAAA==.',
['Ôr']='Ôrdra:BAAALgADCgIJAgAAAA==.',
['ßu']='ßugs:BAABLgAECn8rAAITAAkJ1B3bGQCKAgATAAkJ1B3bGQCKAgAAAA==.',
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
