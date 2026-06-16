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

local lookup = {'Paladin-Retribution','Warlock-Demonology','Druid-Restoration','Unknown-Unknown','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Devastation','Evoker-Preservation','Shaman-Elemental','Shaman-Restoration','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','Hunter-BeastMastery','Priest-Discipline','Evoker-Augmentation','Priest-Holy','Warrior-Fury','Druid-Guardian','Hunter-Survival','Hunter-Marksmanship','Druid-Balance','DemonHunter-Havoc','Mage-Frost','Warlock-Affliction','Monk-Mistweaver','Priest-Shadow','Warlock-Destruction','Druid-Feral','Rogue-Subtlety','Warrior-Arms','Warrior-Protection','DeathKnight-Frost',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abhanfnahwa:BAAALgADCgUJBQAAAA==.Abort:BAABLgAECn8ZAAIBAAcJtR3UUADUAQABAAcJtR3UUADUAQAAAA==.',
Ac='Acbabcaa:BAAALgAECgQJBQAAAA==.Acefighter:BAAALgADCgMJAwAAAA==.Aceon:BAABLgAECn8nAAIBAAgJbBr0PAAOAgABAAgJbBr0PAAOAgAAAA==.Aceonarcher:BAAALgADCgMJAwAAAA==.Aceventurâ:BAAALgAFFAEJAQAAAA==.',
Ad='Adfectia:BAABLgAECn8ZAAICAAkJfwY6egBEAQACAAkJfwY6egBEAQAAAA==.',
Ae='Aelianna:BAABLgAECn8bAAIDAAgJ7hvSGAB8AgADAAgJ7hvSGAB8AgAAAA==.Aelinjr:BAAALgAECgEJAQAAAA==.Aelsa:BAAALgADCgYJCgABLgAECgUJDAAEAAAAAA==.Aelyt:BAABLgAECn8UAAIBAAYJ0h4pVwDDAQABAAYJ0h4pVwDDAQAAAA==.Aesirkin:BAAALgAECgIJBQAAAA==.Aeth:BAABLgAECn8gAAIFAAkJayHcBQDeAgAFAAkJayHcBQDeAgAAAA==.Aethér:BAAALgAFFAEJAQABLgAFFAgJIQADAGgXAA==.',
Ag='Agiel:BAAALgADCgYJBgAAAA==.Agilities:BAAALgADCgYJBgAAAA==.',
Ah='Ahsokä:BAAALgAECgQJBwAAAA==.',
Ak='Akuaku:BAAALgADCgEJAQAAAA==.',
Al='Alareielinda:BAAALgAECgIJAgABLgAECggJEwAEAAAAAA==.Alcool:BAAALgAECgIJAgAAAA==.Alderaan:BAAALgAECgMJAwAAAA==.Alexhya:BAAALgAECgEJAQAAAA==.Alexjones:BAAALgADCgUJBwAAAA==.Alganeth:BAAALgADCggJCAAAAA==.Aliand:BAAALgAECgIJAgAAAA==.Aliande:BAAALgADCgYJCQAAAA==.Alnethir:BAAALgAECgEJAQAAAA==.Aloray:BAAALgADCgcJCwAAAA==.Alordis:BAAALgADCgMJAwAAAA==.Alsou:BAAALgAECgEJAQAAAA==.Alvarah:BAAALgADCgMJAwAAAA==.Alynas:BAABLgAECn8fAAIDAAkJoA8ySABrAQADAAkJoA8ySABrAQAAAA==.Alysona:BAABLgAECn8WAAMGAAgJhhxrQgC9AQAGAAcJDBxrQgC9AQAHAAEJZR+gKQBZAAAAAA==.',
Am='Amahra:BAAALgAECgQJBwAAAA==.Amelio:BAAALgADCgIJAgAAAA==.Amethysztra:BAAALgADCgUJBQAAAA==.Amewow:BAACLgAFFH8KAAIIAAMJwxlbBgDtAAAIAAMJwxlbBgDtAAAuAAQKfyAAAwgACAkLHJMFAAECAAgACAkLHJMFAAECAAkABAnmDygkAMkAAAAA.Amìko:BAAALgAECgMJAwAAAA==.',
An='Anadoria:BAAALgADCgYJBgAAAA==.Analferret:BAABLgAECn8cAAMKAAcJOw6WRAAdAQAKAAcJOw6WRAAdAQALAAMJNAoHhACEAAAAAA==.Anarchy:BAAALgAECgQJBAABLgAECgYJBwAEAAAAAA==.Anastæsia:BAAALgADCgYJBwABLgAECgMJAwAEAAAAAA==.Anda:BAAALgAECgUJCAAAAA==.Angewomon:BAAALgAECgEJAQAAAA==.Anitabidet:BAAALgADCgcJBwAAAA==.Anorakswrath:BAAALgAECgYJDAAAAA==.',
Ap='Apepi:BAAALgADCgcJBwAAAA==.Apolion:BAAALgADCgQJBAAAAA==.Apoundofcake:BAAALgAECgEJAQAAAA==.Appauling:BAAALgADCgYJBgAAAA==.',
Ar='Araspeth:BAAALgADCgYJBgAAAA==.Arcanemonkey:BAAALgAECgkJBQAAAA==.Arclore:BAABLgAECn8WAAQBAAcJHw7v9gC/AAABAAUJkArv9gC/AAAMAAUJyQpcXQC9AAANAAEJYgHzXQARAAAAAA==.Argenor:BAAALgAECgUJCgAAAA==.Ariadni:BAABLgAECn8XAAMLAAgJOA8cRQCVAQALAAgJOA8cRQCVAQAKAAEJLRE/oQA0AAAAAA==.Aricict:BAAALgAECgMJAwAAAA==.Ariella:BAAALgADCgEJAQAAAA==.Arlý:BAAALgAECgMJBQAAAA==.Aruneza:BAABLgAECn84AAIJAAkJfxIBDQD+AQAJAAkJfxIBDQD+AQAAAA==.',
As='Asajj:BAAALgAECgYJEgAAAA==.Asharie:BAAALgADCgEJAQAAAA==.Ashcatchm:BAAALgADCgMJAwABLgAECgcJEQAEAAAAAA==.Ashergon:BAAALgAECgQJBAABLgAECgkJGwALAMQjAA==.Asheriz:BAAALgAECggJEAABLgAECgkJGwALAMQjAA==.Asherous:BAABLgAECn8bAAMLAAkJxCMgCwACAwALAAkJxCMgCwACAwAKAAEJbgxShgA0AAAAAA==.Ashiashi:BAAALgAECgEJAQABLgAECgkJIgABAAYjAA==.Ashomá:BAAALgADCgcJCAAAAA==.Ashtroglide:BAAALgAECggJDgABLgAECgkJGwALAMQjAA==.Ashèr:BAAALgAECggJEAABLgAECgkJGwALAMQjAA==.Askara:BAAALgAECgUJBQAAAA==.Astyria:BAAALgADCgUJBQAAAA==.Aszura:BAAALgADCgUJDwAAAA==.',
Au='Auntieshaman:BAAALgADCgEJAQAAAA==.Auranhis:BAAALgAECgEJAgAAAA==.Auriailas:BAAALgADCgcJCQAAAA==.Autoignition:BAAALgADCgMJAwAAAA==.',
Av='Avidel:BAAALgAECgcJEAAAAA==.Avryn:BAABLgAECn8WAAMOAAgJxhjCGQAxAQAOAAYJkxfCGQAxAQAKAAMJxhuUUQDtAAAAAA==.',
Ay='Ayilime:BAAALgAECgQJBQAAAA==.',
Ba='Badcompanytt:BAAALgADCgIJAgAAAA==.Bakeddh:BAAALgADCgYJCQAAAA==.Ballsaq:BAAALgADCgIJAgAAAA==.Balør:BAAALgAECgMJAwABLgAECgkJMwAPAOYWAA==.Basttet:BAAALgAFFAEJAQAAAA==.Baunílha:BAABLgAECn8pAAIQAAgJ+By9DwBMAgAQAAgJ+By9DwBMAgAAAA==.',
Be='Beanvoid:BAAALgADCgYJBgAAAA==.Beardsaint:BAAALgADCgUJBQAAAA==.Beefini:BAAALgAECgMJAwABLgAECggJIQARADwlAA==.Beenah:BAABLgAECn8aAAISAAgJcAbqgQA2AQASAAgJcAbqgQA2AQAAAA==.Belethiel:BAAALgADCgEJAQAAAA==.Bellinopher:BAAALgADCggJFQABLgAECgkJKQATADsQAA==.Benafflock:BAAALgAECgYJBwAAAA==.Bence:BAAALgAECgMJBAABLgAECgkJMAAUANoaAA==.Benefitheals:BAAALgAECgUJBwAAAA==.Benefitpally:BAAALgAECgQJBwAAAA==.Benefitsham:BAAALgADCgYJBgAAAA==.',
Bi='Bigbibble:BAABLgAECn8aAAIVAAgJ0hTpLQCNAQAVAAgJ0hTpLQCNAQAAAA==.Birdien:BAAALgAECgYJBgAAAA==.',
Bl='Blackrose:BAAALgAECgMJAwAAAA==.Blamson:BAAALgADCgYJCgAAAA==.Blodeuedd:BAAALgAECgYJDAAAAA==.Bloodrain:BAABLgAECn8eAAIWAAgJlAzFPQBNAQAWAAgJlAzFPQBNAQAAAA==.Blubolt:BAAALgAECgUJCwAAAA==.Blueaurora:BAAALgADCgIJAQABLgAECgkJHwADAKAPAA==.',
Bo='Bombmagic:BAAALgADCgMJAwAAAA==.Boomie:BAABLgAFFH8FAAIJAAQJTBXwGAD+AAAJAAQJTBXwGAD+AAAAAA==.Boopty:BAAALgAECgQJBgAAAA==.Booptyboop:BAAALgAECgQJEgAAAA==.Booptydo:BAAALgADCgcJCQAAAA==.Boris:BAAALgAECgEJAQAAAA==.Bowhawk:BAABLgAECn8ZAAISAAYJNgyAowD1AAASAAYJNgyAowD1AAAAAA==.Bozag:BAAALgADCgIJAgAAAA==.',
Br='Braiin:BAAALgAFFAIJBAABLgAFFAgJIQADAGgXAA==.Brakken:BAAALgADCgQJBAAAAA==.Brawll:BAAALgAECgMJBQAAAA==.Brazyn:BAAALgADCgYJBgAAAA==.Brevarda:BAACLgAFFH8JAAILAAMJ4hVzSQDDAAALAAMJ4hVzSQDDAAAuAAQKfzEAAwsACAk6HrEfAE4CAAsACAk6HrEfAE4CAAoABgloDUdVAOEAAAAA.Brewcelee:BAAALgAECgEJAgAAAA==.Brokenmind:BAAALgAECgQJBAABLgAECgcJJAAVAIwZAA==.Brubble:BAAALgADCgMJAwAAAA==.Brugg:BAAALgADCgYJBgAAAA==.',
Bu='Bubbles:BAAALgADCgEJAQAAAA==.Bubblzmgee:BAABLgAECn88AAITAAkJlBTkEQBUAgATAAkJlBTkEQBUAgAAAA==.Buscemi:BAAALgAECgUJCAAAAA==.Bushmommy:BAAALgAFFAEJAQAAAA==.Buttèrs:BAAALgAECggJEAAAAA==.',
Ca='Cadence:BAAALgAECgEJAgAAAA==.Cadin:BAABLgAECn8VAAMLAAkJSxmPDQCvAgALAAkJSxmPDQCvAgAKAAcJYhdfLwCkAQAAAA==.Cakeman:BAAALgADCgUJBQAAAA==.Calehunter:BAAALgAECgYJBgAAAA==.Cameltotem:BAAALgAECgUJBAAAAA==.Capnblood:BAAALgAECgEJAwAAAA==.Capone:BAAALgAECgUJEAAAAA==.Carahz:BAABLgAECn8aAAIXAAcJWg+bKwD9AAAXAAcJWg+bKwD9AAAAAA==.Carindria:BAAALgAECgEJAgAAAA==.Cattiebrie:BAAALgAECgIJAwAAAA==.Caylavana:BAABLgAECn8vAAMYAAgJ5xqiEQAeAgAYAAgJ5xqiEQAeAgASAAIJCxF9rQBpAAAAAA==.',
Ce='Celaylria:BAABLgAECn8UAAIZAAYJ0AxPGgDYAAAZAAYJ0AxPGgDYAAAAAA==.',
Ch='Chabz:BAAALgAECgQJAwAAAA==.Chai:BAABLgAECn8rAAMaAAgJYR12EQBLAgAaAAgJYR12EQBLAgADAAYJ4hh8OQDAAQAAAA==.Chantille:BAAALgAECgYJCAAAAA==.Charmed:BAABLgAECn8UAAIbAAkJRRBtHwB6AQAbAAkJRRBtHwB6AQAAAA==.Charmíng:BAAALgAECgYJDAABLgAFFAQJCAAcAAYhAA==.Cheryll:BAAALgAECgUJBQAAAA==.Chopenhagen:BAAALgAECgIJAgAAAA==.Chunknörris:BAAALgAECgQJBAAAAA==.',
Ci='Cint:BAABLgAECn8cAAIWAAgJQwkxPgBLAQAWAAgJQwkxPgBLAQAAAA==.',
Cl='Clio:BAAALgAFFAIJBAAAAA==.Cloudedjade:BAABLgAECn8cAAINAAgJ7Qd9IwD1AAANAAgJ7Qd9IwD1AAAAAA==.',
Co='Coleybear:BAABLgAECn8XAAICAAgJjARHpQD2AAACAAgJjARHpQD2AAAAAA==.Condewit:BAAALgAECgEJAQAAAA==.Condragos:BAAALgAECgUJBQAAAA==.Copedh:BAAALgAECgQJBAABLgAECgkJMAAFAHgdAA==.Copedk:BAABLgAECn8wAAIFAAkJeB2iCACJAgAFAAkJeB2iCACJAgAAAA==.Copedogg:BAAALgADCgcJDgABLgAECgkJMAAFAHgdAA==.Copemonkk:BAAALgADCgMJAwABLgAECgkJMAAFAHgdAA==.Copepriest:BAAALgADCgkJCQABLgAECgkJMAAFAHgdAA==.Copeshamm:BAAALgAECgUJBQABLgAECgkJMAAFAHgdAA==.Copeslamm:BAAALgAECgUJBQABLgAECgkJMAAFAHgdAA==.Corrode:BAAALgAECggJCQAAAA==.Covertm:BAAALgAECgcJEgAAAA==.Covertw:BAAALgADCgEJAQAAAA==.',
Cr='Craq:BAAALgAECgEJAgAAAA==.Crashedout:BAAALgADCgEJAgAAAA==.Crashknight:BAAALgAECgEJAQABLgAECgQJDAAEAAAAAA==.Crew:BAAALgAECggJCwAAAA==.Cricky:BAAALgAECgIJAgAAAA==.Crims:BAABLgAECn8ZAAIJAAgJ5xbVDQDuAQAJAAgJ5xbVDQDuAQAAAA==.Crinke:BAAALgADCgEJAQAAAA==.',
Cu='Culture:BAAALgAECgYJEAAAAA==.Curdledmilk:BAAALgAECgIJAgAAAA==.',
Cy='Cybeldin:BAABLgAECn81AAIZAAkJEQsFEQBFAQAZAAkJEQsFEQBFAQAAAA==.Cyberdemonxd:BAAALgADCgYJBwABLgAFFAIJBwARAP0NAA==.',
Da='Daadeedaa:BAACLgAFFH8KAAIcAAQJDxfRXQAvAQAcAAQJDxfRXQAvAQAuAAQKfzAAAhwACAkqJMQsAGQCABwACAkqJMQsAGQCAAAA.Daddysparey:BAABLgAECn8zAAIGAAgJ9BeYMwD1AQAGAAgJ9BeYMwD1AQAAAA==.Dagoba:BAAALgAECgMJAgAAAA==.Dakk:BAABLgAECn9EAAIcAAkJpRfVOQAvAgAcAAkJpRfVOQAvAgAAAA==.Dardeathicus:BAACLgAFFH8MAAIRAAQJPR40aAAnAQARAAQJPR40aAAnAQAuAAQKfyAAAhEACQnNIIkoAJgCABEACQnNIIkoAJgCAAAA.Darderyag:BAABLgAECn8sAAIcAAgJNB1fMQBRAgAcAAgJNB1fMQBRAgAAAA==.Darek:BAABLgAECn8YAAIcAAYJlArLzADzAAAcAAYJlArLzADzAAAAAA==.Dariara:BAAALgAECgEJAQAAAA==.Darkbud:BAAALgADCggJEQAAAA==.Darkfeazer:BAAALgADCgEJAQAAAA==.Darkrife:BAAALgAECgQJBQAAAA==.Darmonkicus:BAAALgAFFAIJAgAAAA==.Daymann:BAAALgAECgYJBgAAAA==.Dazzan:BAAALgAECgIJAgAAAA==.',
De='Deadlocks:BAAALgADCgEJAQAAAA==.Deathhold:BAAALgAECgYJBwAAAA==.Debilitation:BAAALgADCgIJAgAAAA==.Dedrys:BAAALgAECgEJAQAAAA==.Deklan:BAAALgAECgEJAwAAAA==.Delsid:BAAALgAECgMJAwAAAA==.Demonsteven:BAAALgADCgcJCgAAAA==.Dependabull:BAAALgADCgYJCQABLgADCgcJBwAEAAAAAA==.Dernis:BAAALgAFFAEJAgAAAA==.Deshaman:BAACLgAFFH8IAAIKAAMJRxAOMwC8AAAKAAMJRxAOMwC8AAAuAAQKfzYAAgoACAmqILIMAJcCAAoACAmqILIMAJcCAAEuAAUUBgkeABIAcx4A.Devilbeast:BAAALgAECgQJDgAAAA==.',
Dh='Dhargo:BAAALgADCgcJBwAAAA==.',
Di='Diablosauz:BAAALgADCgYJBgAAAA==.Dirte:BAAALgADCgYJDQAAAA==.Dirty:BAABLgAECn8eAAIKAAgJ5BOIJQDlAQAKAAgJ5BOIJQDlAQAAAA==.',
Dk='Dkbygorm:BAAALgADCgQJBwAAAA==.',
Do='Doctapheel:BAABLgAECn8YAAIdAAcJcRCdDgBuAQAdAAcJcRCdDgBuAQAAAA==.Dolfi:BAAALgADCggJDAAAAA==.Doomzday:BAAALgAECgQJBgAAAA==.Dorlesette:BAABLgAECn8kAAMeAAkJqwc0TwApAQAeAAkJqwc0TwApAQAPAAIJ7ALUhgA9AAAAAA==.',
Dr='Draiven:BAAALgAECgEJAQAAAA==.Drathmir:BAAALgAFFAEJAQAAAA==.Dravindil:BAAALgAECgkJBgAAAA==.Dreamlesnite:BAABLgAECn8eAAICAAcJZAfkpAD3AAACAAcJZAfkpAD3AAAAAA==.Dreidelman:BAABLgAFFH8FAAIcAAMJDQP7jwC4AAAcAAMJDQP7jwC4AAAAAA==.Drkstar:BAAALgAECgYJDAAAAA==.Drpeeper:BAAALgAECgUJBQAAAA==.Druidcam:BAAALgAECgUJBQABLgAECgkJLQARAEkXAA==.',
Du='Dudeicus:BAAALgAECgYJCQAAAA==.Dunthur:BAAALgADCgYJBgAAAA==.Duoda:BAABLgAFFH8OAAIeAAcJaxteCQBjAgAeAAcJaxteCQBjAgAAAA==.Durto:BAAALgAECgEJAgABLgAECgQJCAAEAAAAAA==.',
Dy='Dylora:BAABLgAECn87AAIeAAkJRBosEgCIAgAeAAkJRBosEgCIAgAAAA==.',
['Dï']='Dïesel:BAAALgAECgIJAgAAAA==.',
['Dó']='Dólores:BAAALgADCgYJBgAAAA==.',
['Dö']='Dödskott:BAAALgADCgkJGAAAAA==.',
Ec='Eclipsa:BAAALgAECggJDwAAAA==.',
Eg='Egregore:BAABLgAECn8YAAIGAAcJ9w/rbgBBAQAGAAcJ9w/rbgBBAQAAAA==.',
El='Elassha:BAAALgAECgEJAQAAAA==.Ellaria:BAABLgAECn80AAMGAAkJgBjbLQAMAgAGAAkJARfbLQAMAgAbAAYJVhjlJQCQAQAAAA==.Elyselyia:BAAALgAECgUJBQAAAA==.Elysindrall:BAABLgAECn8mAAIJAAgJGxaBDAAKAgAJAAgJGxaBDAAKAgAAAA==.',
Em='Emokins:BAABLgAECn87AAIKAAkJ1SSjAgBKAwAKAAkJ1SSjAgBKAwAAAA==.Emouri:BAAALgADCgcJCwAAAA==.',
En='Endesh:BAABLgAECn82AAMUAAkJlQktNgBVAQAUAAkJlQktNgBVAQAIAAMJ7QXKIABKAAAAAA==.Enolah:BAAALgADCgYJCAAAAA==.',
Er='Eradica:BAAALgADCgYJDQAAAA==.Erelo:BAAALgAECgQJBAAAAA==.Erubus:BAACLgAFFH8UAAQPAAQJ0iEHEgCLAQAPAAQJ0iEHEgCLAQAeAAMJPhDYPgCcAAAQAAEJQwGZFAA9AAAuAAQKfxgABA8ACQlsIUQWAFcCAA8ACQlsIUQWAFcCAB4AAgk2E/tWAHMAABAAAQm/Ds95ADcAAAAA.Erubustin:BAAALgAECgUJCwAAAA==.Eryss:BAABLgAECn8bAAISAAgJnAj8eQBGAQASAAgJnAj8eQBGAQAAAA==.',
Es='Escånor:BAAALgAECgYJBwAAAA==.Esmeraldita:BAAALgADCgYJDwAAAA==.',
Ev='Evercleâr:BAAALgADCgkJAgAAAA==.Evoked:BAABLgAECn8fAAMJAAgJzhLFDgDeAQAJAAgJzhLFDgDeAQAIAAUJdAUHHgBcAAAAAA==.',
Ex='Excentric:BAAALgAECgYJCgABLgAFFAcJEQAcAFcZAA==.Expiraman:BAAALgADCgYJBgAAAA==.',
Fa='Faeliel:BAAALgADCgYJBgABLgAFFAUJEwAWAEAbAA==.Faelýn:BAAALgAECggJEwAAAA==.Faessa:BAAALgADCgIJAgAAAA==.Falcone:BAAALgAECgcJBwAAAA==.Fanden:BAAALgADCgYJCQAAAA==.Fartimer:BAAALgADCgYJBgABLgAECgkJGwADAG0VAA==.',
Fd='Fdk:BAAALgAECgUJCQABLgAECggJIAAfAA8fAA==.',
Fe='Feardotcom:BAAALgADCgUJBwAAAA==.Feathering:BAAALgAECgYJEgAAAA==.Fellariene:BAAALgADCgcJCAAAAA==.Fellraiser:BAAALgAECgQJBwAAAA==.Feoralaure:BAAALgADCgQJBAAAAA==.',
Fi='Figjam:BAAALgAECgIJAgABLgAECggJIQAeAN8SAA==.Fistenlick:BAAALgADCgkJEAABLgAECgQJBAAEAAAAAA==.',
Fl='Flashylights:BAAALgAECgIJAwAAAA==.Fluoria:BAAALgAECgQJEgAAAA==.Flurple:BAAALgADCgQJBAAAAA==.Fláreon:BAABLgAECn8ZAAIMAAcJGhk9HQAsAgAMAAcJGhk9HQAsAgAAAA==.',
Fr='Fragarach:BAAALgAECgEJAQAAAA==.Frostynipie:BAAALgADCgMJAwAAAA==.Frutypebblz:BAABLgAECn8oAAIgAAYJdAu1GgDLAAAgAAYJdAu1GgDLAAAAAA==.',
Fu='Furrsure:BAAALgAECgEJAQAAAA==.Fuzznn:BAAALgAECgMJAwABLgABCgIJAgAEAAAAAA==.',
['Fà']='Fàmous:BAABLgAECn8YAAMTAAkJ6BYvHADqAQATAAkJ/hIvHADqAQAVAAIJvB4OYgCoAAAAAA==.',
Ga='Gainful:BAAALgAECgEJAQABLgAFFAQJCAACABsPAA==.Galabris:BAABLgAECn87AAIFAAkJRCQOAgAzAwAFAAkJRCQOAgAzAwAAAA==.Galen:BAAALgAECgEJAwAAAA==.',
Ge='Geranin:BAAALgADCgUJCAAAAA==.Gervire:BAAALgADCgcJCAAAAA==.',
Gh='Ghouldân:BAAALgAECgkJAQAAAA==.Ghoulmania:BAAALgAECgkJDAAAAA==.',
Gi='Gimglich:BAAALgADCgcJBAAAAA==.Gimligrimes:BAAALgADCgEJAQAAAA==.Gington:BAAALgADCgcJBwAAAA==.Ginx:BAAALgAECgEJAQAAAA==.Gitchusum:BAABLgAECn8VAAIYAAkJ9Q4EEwAQAgAYAAkJ9Q4EEwAQAgAAAA==.',
Gl='Glaedry:BAAALgAECgEJAwAAAA==.',
Go='Goose:BAABLgAECn8XAAITAAkJ5hEHJwCXAQATAAkJ5hEHJwCXAQAAAA==.Gorefang:BAAALgAECgEJAQAAAA==.Gormladin:BAABLgAECn8bAAIMAAgJzxT0KwCvAQAMAAgJzxT0KwCvAQAAAA==.',
Gr='Greenbahamut:BAAALgAECgEJAQAAAA==.Gregamesh:BAAALgADCgcJDgAAAA==.Grill:BAAALgAECgMJAwAAAA==.Grimsreaper:BAAALgAECgMJAwAAAA==.Grizzlypouch:BAAALgADCgYJBgAAAA==.Grouchy:BAAALgAECgIJAwABLgAECggJIAAfAA8fAA==.',
Gu='Guillimus:BAAALgADCgcJBgAAAA==.Gultadorn:BAAALgADCgMJAwAAAA==.Guntherus:BAAALgADCgMJAwAAAA==.',
['Gï']='Gïzmö:BAABLgAECn8fAAIhAAgJ2wtgHAAiAQAhAAgJ2wtgHAAiAQAAAA==.',
Ha='Halfang:BAAALgADCgYJEQAAAA==.Handham:BAAALgAECgYJCwAAAA==.Hanroro:BAAALgADCgQJAwAAAA==.Hasheth:BAAALgAECgYJCQAAAA==.Havocfang:BAAALgAECgkJCgAAAA==.Hawkiing:BAAALgADCgQJBAAAAA==.Hazuki:BAAALgAECgQJBAAAAA==.',
He='Helouise:BAAALgADCgQJBAAAAA==.Herbalxur:BAAALgAECgQJCAAAAA==.',
Hi='Hibikase:BAAALgAECgYJBgAAAA==.Hildegarde:BAAALgAECgEJAQABLgAECgYJJwAbANUhAA==.Hitpoints:BAAALgAECgUJEQABLgAECgcJJAAVAIwZAA==.',
Ho='Hobbikeen:BAABLgAECn8iAAMJAAgJ/hy6BgCRAgAJAAgJ/hy6BgCRAgAUAAgJqg7NNABcAQAAAA==.Holyhope:BAABLgAECn8XAAIMAAcJmhM8NwBvAQAMAAcJmhM8NwBvAQAAAA==.Holymana:BAABLgAECn9CAAIBAAkJ5h5PFADHAgABAAkJ5h5PFADHAgAAAA==.Hopet:BAAALgAECgUJBQABLgAFFAMJCgALADEdAA==.Hoshea:BAAALgADCgMJAwAAAA==.Hotandready:BAAALgAECgYJCwAAAA==.Hottyoreo:BAAALgADCgYJCwAAAA==.Howcom:BAAALgADCgcJBwAAAA==.',
Hu='Huffingpaint:BAAALgAECgYJEAABLgAECgYJJwAbANUhAA==.Hundrakor:BAABLgAECn8UAAISAAkJ6hIvNwD8AQASAAkJ6hIvNwD8AQAAAA==.Hunteir:BAAALgAECgMJAwAAAA==.Huntinghawk:BAAALgAECgEJAQABLgAECgYJGQASADYMAA==.Hutzil:BAABLgAECn8lAAMCAAkJuxzHJABKAgACAAkJchvHJABKAgAdAAQJGBoDHQDSAAAAAA==.Hutzilla:BAAALgAECgYJCgAAAA==.',
['Hÿ']='Hÿpothermia:BAAALgAECgMJAwAAAA==.',
Il='Illidianna:BAABLgAECn8hAAMGAAkJjBe0KgAbAgAGAAkJjBe0KgAbAgAbAAIJixJiXABvAAAAAA==.',
Im='Imbluedabdee:BAAALgADCgcJDQAAAA==.Imitlol:BAAALgAFFAEJAQAAAA==.',
In='Inception:BAAALgAECgIJAgAAAA==.',
Ir='Irrefutable:BAAALgADCgQJBAAAAA==.',
It='Itchynyple:BAAALgADCggJCAAAAA==.',
Ja='Jabadabadoo:BAAALgAECgEJAQAAAA==.Jables:BAAALgADCgQJBAABLgAECgkJKgAQAO4lAA==.Jackatak:BAAALgADCgMJAwABLgAECggJIAAfAA8fAA==.Jacoblack:BAAALgADCgMJAwAAAA==.Jacques:BAAALgADCgEJAgAAAA==.Jadin:BAAALgADCgEJAQABLgAECggJIAAfAA8fAA==.Jaefury:BAABLgAECn8hAAIOAAkJoR24BQCAAgAOAAkJoR24BQCAAgAAAA==.Jakes:BAAALgAECgQJBQAAAA==.Jandinga:BAAALgAECgQJBAAAAA==.',
Je='Jeabuschrist:BAAALgADCgYJDAAAAA==.',
Ji='Jimadler:BAAALgADCgMJAwABLgAECgIJAgAEAAAAAA==.Jimbi:BAAALgAFFAIJBAAAAA==.Jiminybilini:BAAALgAFFAIJAQAAAA==.Jimmybull:BAAALgADCgEJAQAAAA==.Jinho:BAAALgAECgEJAQABLgAECgkJHQAiACsiAA==.Jinrop:BAEALgADCgcJBwABLgAECgcJFgAgACMUAA==.',
Jo='Jobuu:BAAALgAECgEJAgAAAA==.Jock:BAAALgAECgQJCAAAAA==.Johnnypopoff:BAABLgAECn8kAAIcAAkJOxS/VQDZAQAcAAkJOxS/VQDZAQAAAA==.Johnwolf:BAAALgAECgQJCQAAAA==.Jojohunts:BAAALgAECgcJDgAAAA==.Jose:BAAALgAECgEJAQABLgAECgkJIAABAAMgAA==.Joshodin:BAAALgAECgEJAQAAAA==.',
Jp='Jpðc:BAAALgAECgYJCgAAAA==.',
Ju='Juanjo:BAAALgADCgcJBwABLgAECgkJMwAcAA4eAA==.Junebugg:BAAALgADCgYJBgAAAA==.Junyubych:BAABLgAECn8XAAIgAAgJdAjKFQD2AAAgAAgJdAjKFQD2AAAAAA==.Justylln:BAAALgAECgYJBgAAAA==.Justzach:BAABLgAECn83AAIPAAkJXhqBDQBeAgAPAAkJXhqBDQBeAgAAAA==.',
['Jà']='Jàccuse:BAABLgAECn8hAAIeAAgJ3xITLQDDAQAeAAgJ3xITLQDDAQAAAA==.Jàrnsaxa:BAAALgADCgEJAQAAAA==.',
['Jò']='Jòhnnypopo:BAABLgAECn8bAAIBAAgJERl6QAADAgABAAgJERl6QAADAgAAAA==.',
Ka='Kadywompus:BAAALgADCgcJBwAAAA==.Kaeladra:BAAALgAFFAEJAQABLgAFFAMJBQAMAHcFAA==.Kagannh:BAAALgADCgYJBgAAAA==.Kailm:BAAALgADCgIJAgABLgAFFAYJDgAWAA4dAA==.Kait:BAAALgAECgIJAgAAAA==.Kalida:BAAALgADCgQJBAAAAA==.Kalniel:BAAALgADCgUJBQAAAA==.Kalorie:BAAALgADCgYJBgABLgAECgYJJwAbANUhAA==.Kassaalaa:BAAALgADCgYJBgAAAA==.Kasume:BAAALgAECgQJBQAAAA==.Kaylastrasza:BAAALgAECgEJAQAAAA==.Kazurend:BAACLgAFFH8bAAIfAAgJKCC2AQChAgAfAAgJKCC2AQChAgAuAAQKfxoAAh8ACAnQI7wFADMDAB8ACAnQI7wFADMDAAAA.',
Ke='Keiadon:BAAALgADCgkJEAAAAA==.Kelavax:BAAALgAECgkJBQAAAA==.Keleira:BAABLgAECn8XAAIcAAgJXhclXADGAQAcAAgJXhclXADGAQAAAA==.Kelemvore:BAAALgAECgEJAQAAAA==.Kericcandere:BAAALgADCgIJAwAAAA==.Kerm:BAEALgAECgEJAgAAAA==.Keyaielenst:BAAALgADCgcJBwAAAA==.',
Kh='Khristina:BAAALgADCgkJDQAAAA==.Khrogh:BAABLgAFFH8FAAIMAAMJdwXDNgCNAAAMAAMJdwXDNgCNAAAAAA==.',
Ki='Kiel:BAABLgAFFH8HAAIbAAQJlhzZFgDmAAAbAAQJlhzZFgDmAAABLgAFFAMJBQAiAE0SAA==.Kindos:BAAALgADCgQJBwAAAA==.Kippo:BAEALgAECgEJAQABLgAFFAYJEwARAMYTAA==.Kiramman:BAAALgAECgUJDAAAAA==.Kirsute:BAAALgADCgYJBgAAAA==.Kirxcy:BAAALgADCgUJCAAAAA==.Kisarrah:BAAALgAECgkJBQAAAA==.Kithiri:BAABLgAECn8dAAITAAYJsAaTRQDvAAATAAYJsAaTRQDvAAAAAA==.',
Kn='Knarn:BAABLgAECn8oAAIYAAkJDB7zDwAyAgAYAAkJDB7zDwAyAgAAAA==.',
Ko='Koralie:BAACLgAFFH8eAAMSAAgJ9hLWAACrAQASAAcJhxTWAACrAQAZAAEJkAl+NABHAAAuAAQKfx4AAxIACAloHW4bAGICABIACAloHW4bAGICABkABQm+D6VcANAAAAAA.Korheo:BAAALgAECgEJAgAAAA==.Kotiria:BAAALgAECgEJAQAAAA==.',
Kr='Krillaxx:BAAALgAECgcJDwAAAA==.Krimzin:BAAALgAFFAIJAgABLgAFFAUJGgASADAhAA==.Krolg:BAAALgAECgcJDgAAAA==.Kromvar:BAAALgAECgQJBwAAAA==.',
Ku='Kungfused:BAAALgADCgUJCAABLgAECgQJBgAEAAAAAA==.Kurisux:BAABLgAFFH8NAAIRAAQJJRtRTQBSAQARAAQJJRtRTQBSAQAAAA==.',
Ky='Kyliekat:BAABLgAECn8UAAIaAAgJaQj2PAAYAQAaAAgJaQj2PAAYAQAAAA==.Kyndlynn:BAAALgAECgQJEAAAAA==.Kyriea:BAAALgAECgEJAQAAAA==.',
La='Lanceelot:BAAALgAECgIJAgAAAA==.Lanel:BAAALgAECgUJCQAAAA==.Lathelous:BAABLgAECn8oAAINAAkJ2SKjAgD/AgANAAkJ2SKjAgD/AgAAAA==.',
Ld='Ldt:BAAALgADCgMJAwAAAA==.',
Le='Leintheir:BAAALgAECgMJAwAAAA==.Leththol:BAAALgADCgkJJQAAAA==.Letyoudie:BAAALgAECgQJCwAAAA==.Levenza:BAABLgAECn8UAAIHAAgJYhRjEABCAQAHAAgJYhRjEABCAQAAAA==.',
Li='Licita:BAAALgAECgUJCgAAAA==.Lideina:BAABLgAECn8lAAIRAAcJDh4TTADbAQARAAcJDh4TTADbAQAAAA==.Lielandra:BAAALgAECgcJCAAAAA==.Lightdinger:BAAALgAECgYJDwAAAA==.Lightt:BAABLgAECn9SAAMVAAkJox02CQDSAgAVAAkJox02CQDSAgAfAAUJNQEQVQBvAAAAAA==.Liightt:BAABLgAECn8iAAIVAAcJqhg8HQDXAQAVAAcJqhg8HQDXAQAAAA==.Lilnug:BAAALgAECgQJDAAAAA==.Lindsey:BAAALgADCgkJDQABLgAECgUJCwAEAAAAAA==.Littlenyne:BAAALgAECgYJDAAAAA==.',
Ll='Llando:BAAALgADCgYJBgAAAA==.Llars:BAABLgAECn8oAAILAAkJrBiRHgBWAgALAAkJrBiRHgBWAgAAAA==.Lleonardo:BAAALgADCgEJAQAAAA==.',
Lo='Lockkjaw:BAAALgAECgEJAQAAAA==.Locknorris:BAAALgADCgUJBgAAAA==.Loghrif:BAAALgAECgQJBAABLgAECgUJBgAEAAAAAA==.Loptear:BAAALgAECgEJAQAAAA==.Loryanna:BAAALgADCgUJCwAAAA==.Louie:BAAALgAFFAEJAQAAAA==.Lovehandless:BAAALgADCgEJAQAAAA==.Lovespell:BAAALgADCgUJBQAAAA==.',
Lu='Lucavian:BAAALgAECggJEQAAAA==.Lucavias:BAAALgAECgMJBQAAAA==.Luckydruidh:BAABLgAECn8hAAMDAAkJ7R0BCwALAwADAAkJ7R0BCwALAwAaAAEJxQ3vewA6AAAAAA==.Luckyevoker:BAAALgADCgcJEgABLgAECgkJIQADAO0dAA==.Luckyjax:BAAALgAECgEJAQAAAA==.Lumenne:BAAALgADCgcJBwAAAA==.Lurien:BAABLgAECn8XAAIbAAkJ3RPoGQCtAQAbAAkJ3RPoGQCtAQAAAA==.Luxilejo:BAAALgADCgYJCwAAAA==.Luxore:BAAALgAECgYJBgABLgAFFAMJCQAUABEPAA==.',
Ly='Lyfebane:BAACLgAFFH8MAAMBAAQJ9wvCTwAKAQABAAQJ9wvCTwAKAQAMAAIJZwlwPgBjAAAuAAQKfzoAAwEACQkYF7Y5ABkCAAEACQkYF7Y5ABkCAAwACAncGMAgAPsBAAAA.Lynnah:BAAALgAECgEJAQAAAA==.',
['Ló']='Lórien:BAAALgADCgEJAQAAAA==.',
['Lø']='Lørs:BAABLgAECn84AAIcAAgJwxW2UwDeAQAcAAgJwxW2UwDeAQAAAA==.Lørz:BAAALgAECgQJBAAAAA==.',
Ma='Machorn:BAAALgADCgcJBwAAAA==.Mageis:BAAALgADCgMJAwAAAA==.Magetree:BAAALgAFFAIJAgABLgAFFAUJDQANAJcZAA==.Mageyoucream:BAAALgAECgYJCgAAAA==.Magnai:BAAALgADCgcJBwAAAA==.Main:BAABLgAECn85AAIBAAkJJgsdeAB8AQABAAkJJgsdeAB8AQAAAA==.Majrmiståke:BAACLgAFFH8JAAIcAAMJRhhpdgDzAAAcAAMJRhhpdgDzAAAuAAQKfxUAAhwACAm3GLA+AB4CABwACAm3GLA+AB4CAAEuAAUUBQkYAAYAyh0A.Malagore:BAAALgAFFAEJAQABLgAECggJFwAUALQVAA==.Malantir:BAAALgAECgYJBgABLgAECggJFwAUALQVAA==.Malec:BAAALgADCggJCAAAAA==.Malicemech:BAAALgAECgEJAQAAAA==.Maliceone:BAABLgAECn8eAAIWAAcJ8AlQSQAfAQAWAAcJ8AlQSQAfAQAAAA==.Malicepaly:BAAALgAECgUJDAAAAA==.Maliceshammy:BAAALgADCgYJEAAAAA==.Manek:BAAALgAECgYJBgABLgAECgkJRAAcAKUXAA==.Mansmilk:BAAALgAECgQJBAAAAA==.Manthra:BAAALgADCgMJAwAAAA==.Mardara:BAAALgAECgYJBgAAAA==.Marraxa:BAAALgADCgYJBgAAAA==.Mattshamon:BAAALgADCgcJBwAAAA==.Max:BAABLgAECn8ZAAICAAkJ5R6IPwDdAQACAAkJ5R6IPwDdAQAAAA==.Mayé:BAABLgAFFH8KAAIaAAYJmhiqEQCLAQAaAAYJmhiqEQCLAQAAAA==.',
Mb='Mbaku:BAAALgAECgcJEQABLgAFFAUJDQAfALEcAA==.',
Mc='Mcgobbtock:BAAALgADCgUJBQAAAA==.',
Me='Melechim:BAAALgADCgkJCQAAAA==.Melinoe:BAABLgAECn8lAAICAAgJfRBaVwCWAQACAAgJfRBaVwCWAQAAAA==.Mentallywet:BAAALgADCgkJCQABLgAECgkJNQABAOgjAA==.Meowdoh:BAABLgAFFH8FAAIXAAQJ4AnjGwCtAAAXAAQJ4AnjGwCtAAAAAA==.Merc:BAAALgAECgUJBQAAAA==.Merithrá:BAAALgAECgIJAgAAAA==.Metalgreymon:BAAALgAECgEJAQAAAA==.',
Mi='Micah:BAACLgAFFH8eAAIJAAcJVhBxBQChAQAJAAcJVhBxBQChAQAuAAQKfyAAAwkACAmPIAgOAFYCAAkACAmPIAgOAFYCABQABQm/GpsyADUBAAAA.Milenad:BAAALgAECgIJAgAAAA==.Minilyfe:BAAALgAECgMJAwAAAA==.Mirelia:BAAALgADCgMJAgAAAA==.Mishosuki:BAABLgAECn8YAAIRAAYJngsLwwD3AAARAAYJngsLwwD3AAAAAA==.Misky:BAAALgADCgEJAQAAAA==.Misscleo:BAABLgAECn80AAIcAAkJexmgJwB6AgAcAAkJexmgJwB6AgAAAA==.Mizzyboii:BAAALgADCgMJAwAAAA==.',
Mk='Mk:BAAALgAECggJDwAAAA==.',
Mn='Mnesarte:BAABLgAECn8XAAIBAAYJZRa5rgAeAQABAAYJZRa5rgAeAQAAAA==.',
Mo='Moanalisa:BAAALgAECgQJCAAAAA==.Mobmagnet:BAAALgAECgkJDwAAAA==.Moi:BAABLgAFFH8IAAIUAAUJBhMZLwADAQAUAAUJBhMZLwADAQABLgAFFAQJDwAcAIsdAA==.Moltres:BAEBLgAFFH8IAAIUAAUJBiUHFgCxAQAUAAUJBiUHFgCxAQABLgAFFAkJMQAUAKskAA==.Moonkist:BAABLgAECn8ZAAMDAAgJ5hqiGgBuAgADAAgJ5hqiGgBuAgAaAAEJRAN6jQAhAAAAAA==.Moonsgrace:BAAALgADCgkJGQAAAA==.Moose:BAACLgAFFH8KAAIRAAMJPSGEbgAfAQARAAMJPSGEbgAfAQAuAAQKfz4AAhEACAlxJFYZAKwCABEACAlxJFYZAKwCAAAA.Morpheos:BAABLgAECn8bAAMDAAkJbRVsTABbAQADAAkJbRVsTABbAQAaAAQJhgeoYACRAAAAAA==.Morroe:BAAALgADCgEJAQAAAA==.Moxci:BAAALgAECgQJBQAAAA==.',
Mu='Mudamudamuda:BAAALgADCgYJDQABLgAFFAUJEwAWAEAbAA==.Muffintop:BAAALgADCgEJAQAAAA==.',
My='Mysticforest:BAAALgAECgQJBAAAAA==.',
Na='Naedise:BAAALgADCgcJFgAAAA==.Narue:BAAALgAECgIJAgAAAA==.Natureswild:BAABLgAECn8gAAMaAAkJkhiUIQDwAQAaAAgJ4xeUIQDwAQADAAMJawrZuQBSAAAAAA==.Navariis:BAAALgAECgUJDwAAAA==.Navillus:BAAALgAECgMJBgABLgAFFAgJJwAJADQQAA==.',
Ne='Necrophyliac:BAAALgAECgYJCwAAAA==.Nelrehim:BAAALgAECgEJAQAAAA==.Nelumbo:BAAALgAFFAcJBAABLgAFFAkJBQAJAEwVAA==.Nephy:BAAALgAECgQJBAAAAA==.Nephyrium:BAAALgAECgUJCAAAAA==.Nephz:BAAALgAECgYJCgAAAA==.Nephzz:BAAALgAECgQJAwAAAA==.Nethery:BAAALgADCgcJCQAAAA==.Nex:BAAALgAECgEJAQAAAA==.Nezrin:BAABLgAECn8VAAMVAAgJLCE5CQDSAgAVAAgJLCE5CQDSAgAfAAEJMxgYeQBIAAAAAA==.',
Ni='Niandilan:BAAALgAECgQJBAAAAA==.Nidon:BAAALgADCgUJBQAAAA==.Niixxi:BAAALgADCgUJBQAAAA==.',
Nm='Nmbrs:BAABLgAECn8gAAMfAAgJDx/KEgA8AgAfAAgJDx/KEgA8AgATAAEJ7AK9XAApAAAAAA==.',
No='Noirheffer:BAACLgAFFH8NAAMNAAUJlxmCCADrAAANAAUJIRGCCADrAAABAAMJ9hTdbADRAAAuAAQKfycAAwEACQnXHvcXANkCAAEACAlDIvcXANkCAA0ABwkXF6wSAJoBAAAA.Noobishdad:BAAALgAECgMJAwAAAA==.Norio:BAAALgADCgcJBwAAAA==.Notafurrie:BAAALgAECgQJBwAAAA==.',
Nu='Nulannatoo:BAAALgAECgUJBQAAAA==.Numz:BAAALgAECgIJAgAAAA==.Nuukeasaur:BAAALgADCgEJAQAAAA==.',
Ny='Nyadari:BAAALgAECgEJAQAAAA==.Nyank:BAAALgADCgUJBAABLgAFFAIJBwARAP0NAA==.Nyphe:BAAALgAECgQJBAAAAA==.Nyrrhi:BAAALgAECgQJCAAAAA==.Nyxiro:BAAALgAECgUJBQAAAA==.',
Oc='Oculus:BAAALgAECgMJAwAAAA==.',
Od='Odysseus:BAAALgADCgkJFgAAAA==.',
Ol='Oleira:BAAALgAECgUJBQAAAA==.Olgann:BAAALgAECggJEgAAAA==.Olguita:BAABLgAFFH8JAAIKAAMJZxI/MADJAAAKAAMJZxI/MADJAAAAAA==.Olivertwìst:BAAALgADCgcJBwAAAA==.',
Om='Omgowned:BAAALgAECgYJCwABLgAECgkJIgACAFwYAA==.Omnipresent:BAAALgAECgcJCgAAAA==.',
On='Onehothealer:BAABLgAECn8aAAIfAAkJIBbsGQAQAgAfAAkJIBbsGQAQAgAAAA==.',
Oo='Oorua:BAAALgADCgkJDwAAAA==.',
Op='Opheliastar:BAACLgAFFH8IAAIfAAMJehCQJADMAAAfAAMJehCQJADMAAAuAAQKfy0AAh8ACQnmE4QdANgBAB8ACQnmE4QdANgBAAAA.',
Ow='Owltoidz:BAAALgAECgEJAgAAAA==.',
Pa='Pad:BAABLgAECn8ZAAMCAAcJpApRlAATAQACAAYJpApRlAATAQAgAAEJAAAzdQAwAAAAAA==.Pahket:BAAALgAECgQJBAAAAA==.Paintballerr:BAAALgADCgEJAQAAAA==.Paladerp:BAABLgAECn82AAMMAAgJGA9nOABoAQAMAAgJGA9nOABoAQABAAcJOxHtlwBCAQAAAA==.Pallyown:BAABLgAFFH8KAAIMAAIJayNLLgC6AAAMAAIJayNLLgC6AAAAAA==.Paprika:BAAALgADCgQJBgAAAA==.Pastorbedtym:BAABLgAECn8YAAIfAAgJeA98NQA/AQAfAAgJeA98NQA/AQAAAA==.Pat:BAAALgAECgMJAwAAAA==.Paulybricks:BAAALgAECgUJBgAAAA==.',
Pe='Pecan:BAAALgAECgcJDgABLgAFFAQJCAAcAAYhAA==.Pewpewbang:BAAALgADCgIJAgAAAA==.',
Ph='Pharla:BAAALgADCgkJEAAAAA==.Phett:BAAALgAFFAEJAQAAAA==.',
Pi='Pichon:BAAALgADCgUJCAAAAA==.Piffi:BAAALgAECgUJBQAAAA==.Pimmscup:BAAALgAECgEJAQAAAA==.Pin:BAAALgAECgcJBgABLgAFFAkJBQAJAEwVAA==.Pirei:BAAALgADCgUJBQAAAA==.Pirozhki:BAAALgADCgYJBgAAAA==.',
Pl='Plagueborn:BAAALgAECgEJAQAAAA==.Plentar:BAAALgADCgkJDgAAAA==.',
Po='Popcorntea:BAAALgAECgEJAgAAAA==.Porgoon:BAAALgAECgQJBQAAAA==.',
Pr='Preferred:BAAALgAECgUJBQAAAA==.Preserved:BAAALgADCgIJAgAAAA==.Prizzma:BAAALgADCgUJBQAAAA==.',
Ps='Psaul:BAAALgAECgYJCwAAAA==.Psychohexane:BAAALgADCgQJBAAAAA==.',
Py='Pyramys:BAAALgADCgYJBgABLgAFFAUJEwAiACwfAA==.',
Qe='Qedesh:BAAALgAECggJCAAAAA==.Qesem:BAAALgADCgUJBQAAAA==.',
Qu='Qualaribou:BAAALgADCgQJBAAAAA==.',
Ra='Raal:BAAALgADCgkJHgAAAA==.Raenostra:BAAALgAECgUJEAAAAA==.Raenya:BAAALgAECgcJDwAAAA==.Ragefather:BAAALgADCgEJAQAAAA==.Rageye:BAAALgADCgcJBwAAAA==.Rainydaze:BAAALgAECggJEwAAAA==.Ramcharger:BAABLgAECn8cAAMHAAgJxxTuCgCrAQAHAAgJxxTuCgCrAQAbAAYJoAzEOwARAQAAAA==.Ranen:BAABLgAECn8gAAIQAAkJ4B2/DQBnAgAQAAkJ4B2/DQBnAgAAAA==.Rashun:BAABLgAECn8UAAIQAAkJZxmVEQA0AgAQAAkJZxmVEQA0AgAAAA==.',
Re='Reanatilax:BAAALgADCgkJDAABLgAECgkJKQATADsQAA==.Redcinnabar:BAABLgAECn8XAAIaAAYJZARgXgCZAAAaAAYJZARgXgCZAAAAAA==.Regisfilia:BAAALgAECgYJCQABLgAECgYJJwAbANUhAA==.Rehtilox:BAAALgAECgMJAwABLgAECgkJKQATADsQAA==.Reilly:BAAALgADCggJFQAAAA==.Rev:BAAALgAECgQJBAAAAA==.Rexxy:BAABLgAECn8XAAMKAAYJgQ5oUQDuAAAKAAYJgQ5oUQDuAAALAAEJcQEBrAAbAAAAAA==.',
Ri='Riju:BAAALgAECgcJDgAAAA==.Rikashae:BAAALgAECgEJAgAAAA==.Rillan:BAAALgADCgMJAwAAAA==.Rinzler:BAAALgAECgcJDwAAAA==.Rissa:BAAALgAECgQJBgAAAA==.',
Rn='Rng:BAAALgAECgQJCwAAAA==.',
Ro='Roachcentral:BAAALgADCgUJBgAAAA==.Roachcity:BAAALgADCgUJBQAAAA==.Rockalock:BAAALgADCgYJBgAAAA==.Rogerz:BAAALgADCgUJBQAAAA==.Roleon:BAAALgAECgQJBAAAAA==.Rollforpi:BAAALgAFFAEJAgABLgAFFAgJIQADAGgXAA==.Ropebunnyana:BAACLgAFFH8RAAMeAAUJ2BpcHQB2AQAeAAUJ2BpcHQB2AQAQAAIJdwgRNQBsAAAuAAQKfysAAh4ACQlEIBQHACsDAB4ACQlEIBQHACsDAAAA.Rowkani:BAAALgADCgkJCQAAAA==.',
Ru='Ruki:BAABLgAECn8nAAMbAAYJ1SFjIABxAQAGAAYJqBxQUgCLAQAbAAUJWyFjIABxAQAAAA==.',
Ry='Ryand:BAAALgAECgUJCQABLgAFFAYJCgAfABcQAA==.',
Sa='Sacra:BAAALgAECgEJAQAAAA==.Salarcyn:BAAALgAECgUJDAAAAA==.Saltydk:BAABLgAFFH8IAAMRAAUJwwg6hAD8AAARAAQJwwg6hAD8AAAFAAEJAABOWgAAAAAAAA==.Samiracy:BAABLgAECn87AAIgAAkJ6B9GAQDeAgAgAAkJ6B9GAQDeAgAAAA==.Sannrin:BAAALgAECgYJDAAAAA==.Santhrin:BAAALgADCggJDgAAAA==.Sapprot:BAAALgADCgcJCQAAAA==.Sarkress:BAAALgADCgkJCQAAAA==.Sataro:BAAALgADCgEJAQAAAA==.',
Se='Seagal:BAAALgADCgEJAgAAAA==.Sebek:BAAALgAECgEJAQAAAA==.Senbatorii:BAABLgAECn8gAAQDAAgJUB1SIgAzAgADAAcJxRxSIgAzAgAaAAgJ8wkRPgATAQAhAAUJewfYKACGAAAAAA==.Seredala:BAAALgADCgUJCwAAAA==.Serendragosa:BAAALgADCgkJCQAAAA==.Sethrow:BAABLgAECn8iAAQCAAkJXBg6IABiAgACAAgJXBg6IABiAgAdAAEJAAB8RwAAAAAgAAEJAAAsUQAAAAAAAA==.Severa:BAAALgAECggJEAAAAA==.',
Sh='Shadowmouse:BAAALgADCgEJAQAAAA==.Shaladora:BAAALgADCgYJBgAAAA==.Shalia:BAAALgADCgMJAwABLgAECgEJAQAEAAAAAA==.Shamaster:BAAALgADCgIJAgAAAA==.Shamwowza:BAAALgAECgQJBgAAAA==.Sharas:BAAALgAECgQJBQAAAA==.Shawarma:BAAALgAECgYJCwAAAA==.Sheltatha:BAAALgAECgEJAQAAAA==.Shengari:BAABLgAECn8nAAIVAAgJbBK9MAB+AQAVAAgJbBK9MAB+AQAAAA==.Shoshanaa:BAAALgAECgMJBgAAAA==.Shotcallà:BAAALgADCgIJAgAAAA==.Shuna:BAAALgAECgUJDQAAAA==.Shyly:BAABLgAECn8XAAIfAAkJqBw8DwBlAgAfAAkJqBw8DwBlAgAAAA==.Shâbs:BAAALgAECgkJAwAAAA==.',
Si='Sikkly:BAAALgADCgcJEQAAAA==.Siley:BAABLgAECn9ZAAIRAAkJOBYRPwAEAgARAAkJOBYRPwAEAgAAAA==.Sin:BAAALgAECgcJCAAAAA==.Siphon:BAAALgADCgYJBgAAAA==.',
Sk='Skarletfaith:BAABLgAECn8UAAIBAAgJ0QWawAAFAQABAAgJ0QWawAAFAQAAAA==.',
Sl='Sloanya:BAABLgAECn85AAMeAAkJXR4ECgD1AgAeAAkJXR4ECgD1AgAQAAYJKxqmJQCqAQAAAA==.',
Sn='Snarffie:BAAALgAECgYJCgAAAA==.',
So='Sokaz:BAAALgADCgYJBgAAAA==.Solanar:BAAALgADCgUJBQAAAA==.Somavan:BAAALgADCgYJBgABLgAECggJLwAYAOcaAA==.Somedruid:BAABLgAECn8xAAIaAAkJDiRvBAAXAwAaAAkJDiRvBAAXAwAAAA==.',
Sp='Sparkyflower:BAAALgADCgEJAQAAAA==.Spiarmf:BAAALgAECgYJBgAAAA==.Spicynes:BAAALgADCgQJBwAAAA==.Spicyness:BAAALgAECgIJAgAAAA==.Spiderdk:BAAALgAECgUJCAABLgAFFAYJHgASAHMeAA==.Spidermonk:BAAALgADCgcJDgABLgAFFAYJHgASAHMeAA==.Spielberg:BAAALgAECgIJAwAAAA==.Spycmchaggis:BAAALgAECgQJBAAAAA==.Spëcter:BAAALgAECgcJCgABLgAECggJEgAEAAAAAA==.Spëcthyr:BAAALgAECggJEgAAAA==.',
Sq='Squishypoo:BAAALgAECgMJBgAAAA==.',
St='Stache:BAAALgAECgEJAQAAAA==.Stoneyfoam:BAAALgAECgYJBgAAAA==.Stormrider:BAAALgADCgkJCQAAAA==.Stratergron:BAAALgAECgcJAQAAAA==.Styless:BAAALgAECgUJBQAAAA==.',
Su='Sugrace:BAAALgAECgYJBgAAAA==.Superdemonzz:BAACLgAFFH8YAAIGAAUJyh3jMABZAQAGAAUJyh3jMABZAQAuAAQKfzcAAwYACQngIRoRALcCAAYACQmqHxoRALcCAAcABwnCH68GACICAAAA.Superevokerz:BAAALgADCgcJDgABLgAFFAUJGAAGAModAA==.Superlockz:BAAALgAFFAIJAgABLgAFFAUJGAAGAModAA==.Superpallyz:BAACLgAFFH8NAAIMAAQJlhOWIQAMAQAMAAQJlhOWIQAMAQAuAAQKfzIAAwwABwlfIU4TAHQCAAwABwlfIU4TAHQCAA0ABQkhEZYrALwAAAEuAAUUBQkYAAYAyh0A.Supershamanz:BAAALgAECgYJCwABLgAFFAUJGAAGAModAA==.Superspidey:BAAALgADCgIJAgAAAA==.Sushiroll:BAABLgAECn8XAAIQAAgJPx5yEgAqAgAQAAgJPx5yEgAqAgAAAA==.',
Sy='Sydnysweeney:BAAALgADCgMJAwAAAA==.Sylentslit:BAAALgADCggJGgAAAA==.Sylveslem:BAAALgAECgkJDAAAAA==.Syphon:BAAALgADCgMJAwAAAA==.',
['Sô']='Sôlmyr:BAAALgADCgIJAgAAAA==.',
Ta='Tacowarr:BAAALgADCgUJBQAAAA==.Taiynn:BAAALgAECgYJDAAAAA==.Taldazlian:BAAALgAECgMJBgAAAA==.Taliesin:BAAALgAECgMJAwAAAA==.Tallon:BAAALgAECgEJAQABLgAFFAYJIAAUAF4dAA==.Tancy:BAAALgAECgMJAwAAAA==.Tantalus:BAABLgAECn8dAAISAAcJfAxCfwA7AQASAAcJfAxCfwA7AQAAAA==.Tarogen:BAAALgADCgUJBQAAAA==.Tashaler:BAAALgADCgEJAQAAAA==.Tasithia:BAAALgAECgQJBAAAAA==.',
Te='Tealet:BAAALgADCgkJEQAAAA==.Teleion:BAAALgAECgEJAQAAAA==.Tellinor:BAABLgAECn8YAAIBAAYJAQrP2QDjAAABAAYJAQrP2QDjAAAAAA==.Temporal:BAAALgAECgEJAQAAAA==.Terrestra:BAAALgADCgMJAwAAAA==.Tervor:BAAALgAECgIJAgAAAA==.',
Th='Thanamoros:BAAALgAECgUJBgABLgAFFAMJCQAUABEPAA==.Thassarian:BAAALgAECgQJBAAAAA==.Thechosenone:BAAALgADCgIJAgAAAA==.Theroach:BAABLgAECn8UAAICAAYJRQllrQDoAAACAAYJRQllrQDoAAAAAA==.Tholdir:BAAALgAECgYJBgAAAA==.Throfin:BAAALgAECgUJCgAAAA==.Thundernight:BAAALgAECgcJAgAAAA==.',
Ti='Tiki:BAAALgAECgUJBwAAAA==.Tinc:BAAALgADCgEJAgAAAA==.Tinkerballa:BAAALgADCgUJBQAAAA==.Tinonova:BAAALgAECgEJAgAAAA==.Titsmgee:BAAALgAECgIJAgAAAA==.',
To='Toadtroll:BAAALgADCgIJAgAAAA==.Toeren:BAACLgAFFH8eAAISAAYJcx7sDgDgAQASAAYJcx7sDgDgAQAuAAQKfzMAAhIACQktIf4IAA8DABIACQktIf4IAA8DAAAA.Tomate:BAAALgADCgQJBAAAAA==.Toph:BAAALgAECgEJAQAAAA==.Torage:BAAALgAECgEJAQAAAA==.Tormented:BAAALgAECgYJEwAAAA==.Townsley:BAAALgAECgYJDQAAAA==.',
Tp='Tpain:BAAALgAECgMJAwAAAA==.',
Tr='Traitoros:BAAALgADCgYJBgAAAA==.Tralectra:BAAALgAECgcJDAAAAA==.Tranquilfist:BAAALgADCgQJBQABLgAECggJFAABANEFAA==.Treemonk:BAAALgADCgYJCgABLgAECgkJIAAaAJIYAA==.Triplecanopy:BAAALgAECgYJBAAAAA==.Trolvere:BAAALgAECgQJBwAAAA==.Trorim:BAAALgADCgYJBgAAAA==.Trïsh:BAAALgAECggJEAABLgAFFAEJAQAEAAAAAA==.',
Tu='Tummy:BAAALgADCgcJEwAAAA==.Turtlesoup:BAAALgADCgYJBgAAAA==.',
Tw='Twëë:BAAALgAECgQJBQAAAA==.',
Ty='Tybonk:BAAALgAECgEJAQAAAA==.Tygragon:BAAALgAECgYJEAAAAA==.Tyinorin:BAAALgAECgUJAQAAAA==.Tylea:BAAALgADCgkJEQAAAA==.',
Tz='Tzipporah:BAAALgAECgYJDQAAAA==.',
Ub='Ubee:BAABLgAECn8cAAIGAAkJ8REKQwC7AQAGAAkJ8REKQwC7AQAAAA==.',
Ug='Uglyelf:BAAALgAECgUJBQAAAA==.',
Ul='Ultimakitty:BAABLgAECn8WAAMDAAcJcRmfPgCVAQADAAYJOhefPgCVAQAaAAYJ6gl5TADVAAAAAA==.',
Un='Uncertainty:BAAALgAECgYJDgABLgAECgYJJwAbANUhAA==.Unchanged:BAAALgADCgYJBgAAAA==.Unholymana:BAAALgAECgEJAQAAAA==.Unknighted:BAAALgADCgEJAQAAAA==.',
Va='Vaellin:BAAALgAECgEJAQAAAA==.Valanyr:BAAALgADCgEJAQAAAA==.Vantrix:BAAALgAECgEJAQABLgAFFAMJCQAUABEPAA==.Varabo:BAABLgAECn8ZAAIcAAcJBhTifwB0AQAcAAcJBhTifwB0AQAAAA==.Varidria:BAAALgAECgYJCwAAAA==.Varolina:BAAALgAECgEJAQAAAA==.',
Ve='Veelá:BAAALgAECgUJBQABLgAECgkJMwAPAOYWAA==.Vehemencê:BAAALgADCgEJAQAAAA==.Velements:BAAALgAECgMJAwABLgAECgkJFQAjAC4XAA==.Velemon:BAACLgAFFH8SAAIkAAQJ9w7sGQDAAAAkAAQJ9w7sGQDAAAAuAAQKfxkAAiQACQn8EfERAOkBACQACQn8EfERAOkBAAAA.Velisen:BAABLgAECn8lAAMBAAcJQQkEygD4AAABAAcJ6AcEygD4AAANAAUJ4gYWMgCFAAAAAA==.Velthala:BAABLgAECn8VAAMjAAkJLhdMEwDEAQAjAAkJjRZMEwDEAQAWAAEJqwwOowAyAAAAAA==.Velystiri:BAAALgADCgcJBgAAAA==.Venedictus:BAAALgADCgMJAwAAAA==.',
Vi='Viergryn:BAAALgAECgEJAgABLgAECgcJJgAQAK0eAA==.Virasdruid:BAABLgAFFH8GAAIDAAIJRwT4YwBQAAADAAIJRwT4YwBQAAAAAA==.Virusmonk:BAAALgAECgEJAwAAAA==.Vitner:BAABLgAECn8gAAMIAAkJ0hjCCgBsAQAIAAYJShnCCgBsAQAUAAkJ6xIWMgBqAQAAAA==.',
Vo='Vosaleana:BAAALgAECgMJAwAAAA==.',
Vr='Vraak:BAACLgAFFH8hAAIDAAgJaBePCABmAgADAAgJaBePCABmAgAuAAQKfycAAwMACAnhG7YrAAECAAMABwmBHbYrAAECABoABwmaIxYgAP4BAAAA.',
Vu='Vulcus:BAAALgAFFAEJAwABLgAFFAgJIQADAGgXAA==.Vulpii:BAAALgADCgYJBQABLgAECgkJQwAbAN4iAA==.',
Vy='Vyndarien:BAAALgADCgIJAgAAAA==.Vyse:BAAALgADCgEJAQAAAA==.Vyttra:BAAALgADCgMJAwAAAA==.',
Wa='Walak:BAAALgADCgMJAwAAAA==.Warpulse:BAAALgADCgkJHgAAAA==.Warwizard:BAAALgADCgMJAwAAAA==.Watcherseye:BAAALgADCggJDwABLgADCgkJCQAEAAAAAA==.Wattlez:BAAALgAECgcJCQAAAA==.Wavewhisper:BAAALgAECgEJAQAAAA==.Wayofthemist:BAAALgAECggJDwAAAA==.',
Wc='Wcreator:BAABLgAECn8qAAIBAAkJWyKOBwAvAwABAAkJWyKOBwAvAwAAAA==.',
We='Weapònized:BAABLgAECn8UAAIGAAYJWg71owDXAAAGAAYJWg71owDXAAAAAA==.Webaldes:BAAALgAECgEJAQAAAA==.',
Wh='Whitestain:BAABLgAECn8bAAIZAAgJfAquFQAIAQAZAAgJfAquFQAIAQAAAA==.',
Wi='Windyskie:BAAALgADCgEJAQAAAA==.Wingman:BAACLgAFFH8aAAIIAAUJxybeAADLAQAIAAUJxybeAADLAQAuAAQKfzQAAggACAmXJpgAAIsDAAgACAmXJpgAAIsDAAAA.',
Wo='Womdalie:BAAALgADCgQJBgAAAA==.Woodey:BAAALgAECgEJAwAAAA==.Wowame:BAAALgAFFAEJAQAAAA==.',
Wy='Wyckedpally:BAAALgAECgcJDAABLgAECggJFwAgAHQIAA==.',
Xa='Xanthös:BAAALgAFFAEJAQABLgAFFAgJIQADAGgXAA==.',
Xe='Xemnastrasza:BAACLgAFFH8JAAQUAAMJEQ+FRACxAAAUAAMJEQ+FRACxAAAJAAIJaQNPJwBVAAAIAAEJ0QNnCwBLAAAuAAQKfxYABBQACAkdFMQhALEBABQACAnSEcQhALEBAAgABAmmCPEtAKsAAAkAAQlrBYZLACsAAAAA.Xenonne:BAACLgAFFH8PAAIGAAYJJhCQNQBGAQAGAAYJJhCQNQBGAQAuAAQKfyEAAwYACAn6GyJCAL4BAAYACAn6GyJCAL4BABsABQl3D3FGANsAAAAA.',
Xo='Xolither:BAABLgAECn8pAAMTAAkJOxAjIwCzAQATAAgJIxAjIwCzAQAVAAQJ1hO3TgD9AAAAAA==.',
Xp='Xpireedk:BAACLgAFFH8TAAMlAAUJ3iVFCABgAQAlAAUJ1CVFCABgAQARAAQJIR6IVgBCAQAuAAQKfxwAAyUACQnGJUMDAF8CACUACQnGJUMDAF8CABEABQnnHrJ1AJoBAAAA.',
Ya='Yamiyoru:BAAALgADCgYJBgABLgADCgcJBwAEAAAAAA==.',
Yo='Yorakk:BAAALgADCgIJAgAAAA==.Yorgo:BAAALgAECgYJDAAAAA==.',
['Yá']='Yáhtzee:BAAALgAECgUJBQAAAA==.',
Za='Zachdemon:BAAALgAECgEJAQABLgAECgkJNwAPAF4aAA==.Zariala:BAABLgAECn8WAAICAAgJnQYEkQAZAQACAAgJnQYEkQAZAQAAAA==.Zatana:BAAALgAECgUJBwAAAA==.',
Ze='Zephymoo:BAABLgAECn9JAAMhAAkJoSHMAgDxAgAhAAkJoSHMAgDxAgAaAAIJfAPbggAtAAAAAA==.Zeromus:BAAALgAECgkJCQAAAA==.Zerri:BAAALgADCgIJAgAAAA==.Zeyana:BAACLgAFFH8VAAMHAAUJ4Rx9AwBSAQAHAAUJ4Rx9AwBSAQAbAAEJVAH+DwBAAAAuAAQKfxkABAcACQnUGtwIAOcBAAcACQnUGtwIAOcBABsABAmVBU1RAKUAAAYAAgk9AMX3AA8AAAAA.',
Zh='Zhengshi:BAABLgAECn8zAAIPAAkJ5hYREgAjAgAPAAkJ5hYREgAjAgAAAA==.',
Zi='Zimmerfilb:BAAALgAECgEJAQAAAA==.Zippittyzap:BAAALgADCgYJCwABLgAECggJFwAgAHQIAA==.',
Zn='Znot:BAAALgADCgEJAgAAAA==.',
Zo='Zoder:BAABLgAECn8WAAIaAAYJ/hFTPQAWAQAaAAYJ/hFTPQAWAQAAAA==.Zoose:BAABLgAECn87AAMWAAkJwSC+BwDiAgAWAAkJwSC+BwDiAgAjAAIJURi7UQCHAAAAAA==.Zosahe:BAAALgAECgMJBAAAAA==.Zoser:BAABLgAECn8qAAIQAAkJ7iW4AQBZAwAQAAkJ7iW4AQBZAwAAAA==.',
Zu='Zuckuss:BAAALgAECgYJAgAAAA==.',
['Ác']='Áceventura:BAAALgAECgcJEwAAAA==.',
['Æl']='Ælthan:BAAALgADCgUJBgAAAA==.',
['Ér']='Érubus:BAAALgAECgMJBQAAAA==.',
['ßu']='ßugs:BAABLgAECn8mAAISAAkJrRzpGACMAgASAAkJrRzpGACMAgAAAA==.',
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
