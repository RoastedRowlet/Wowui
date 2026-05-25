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

local lookup = {'Paladin-Retribution','Warlock-Demonology','Druid-Restoration','Unknown-Unknown','DeathKnight-Blood','DemonHunter-Devourer','Evoker-Devastation','Evoker-Preservation','Shaman-Elemental','Shaman-Restoration','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Monk-Brewmaster','DeathKnight-Unholy','Hunter-BeastMastery','Priest-Discipline','Evoker-Augmentation','Priest-Holy','Warrior-Fury','Druid-Guardian','Hunter-Survival','Druid-Balance','DemonHunter-Havoc','Mage-Frost','Hunter-Marksmanship','Monk-Mistweaver','Monk-Windwalker','Warlock-Destruction','Druid-Feral','Warlock-Affliction','Rogue-Subtlety','Priest-Shadow','DemonHunter-Vengeance','Warrior-Protection','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abhanfnahwa:BAAALgADCgUJBQAAAA==.Abort:BAABLgAECn8ZAAIBAAcJtR0FQgDhAQABAAcJtR0FQgDhAQAAAA==.',
Ac='Acbabcaa:BAAALgAECgIJAgAAAA==.Acefighter:BAAALgADCgMJAwAAAA==.Aceon:BAABLgAECn8iAAIBAAgJRRhESADOAQABAAgJRRhESADOAQAAAA==.Aceonarcher:BAAALgADCgMJAwAAAA==.',
Ad='Adfectia:BAABLgAECn8VAAICAAgJiQZXgAAjAQACAAgJiQZXgAAjAQAAAA==.',
Ae='Aelianna:BAABLgAECn8XAAIDAAgJtBmAGwBGAgADAAgJtBmAGwBGAgAAAA==.Aelinjr:BAAALgAECgEJAQAAAA==.Aelsa:BAAALgADCgYJCgABLgAECgUJCwAEAAAAAA==.Aelyt:BAAALgAECgMJBwAAAA==.Aesirkin:BAAALgAECgIJBQAAAA==.Aeth:BAABLgAECn8gAAIFAAkJayHcBQDeAgAFAAkJayHcBQDeAgAAAA==.Aethér:BAAALgAECgEJAQABLgAFFAYJGwADAP0YAA==.',
Ag='Agiel:BAAALgADCgYJBgAAAA==.Agilities:BAAALgADCgYJBgAAAA==.',
Ah='Ahsokä:BAAALgAECgQJBwAAAA==.',
Ak='Akuaku:BAAALgADCgEJAQAAAA==.',
Al='Alcool:BAAALgAECgIJAgAAAA==.Alderaan:BAAALgAECgMJAwAAAA==.Alexhya:BAAALgAECgEJAQAAAA==.Alexjones:BAAALgADCgUJBwAAAA==.Alganeth:BAAALgADCggJCAAAAA==.Aliand:BAAALgAECgIJAgAAAA==.Aliande:BAAALgADCgUJBQAAAA==.Alleraz:BAAALgADCgEJAQAAAA==.Alnethir:BAAALgAECgEJAQAAAA==.Aloray:BAAALgADCgcJCwAAAA==.Alordis:BAAALgADCgMJAwAAAA==.Alpharetta:BAAALgAECgcJBgAAAA==.Alsou:BAAALgAECgEJAQAAAA==.Alvarah:BAAALgADCgMJAwAAAA==.Alynas:BAABLgAECn8fAAIDAAkJoA/MPwBwAQADAAkJoA/MPwBwAQAAAA==.Alysona:BAABLgAECn8VAAIGAAcJDBy1OADCAQAGAAcJDBy1OADCAQAAAA==.',
Am='Amahra:BAAALgAECgQJBwAAAA==.Amelio:BAAALgADCgIJAgAAAA==.Amewow:BAACLgAFFH8HAAIHAAIJJRqsBgCrAAAHAAIJJRqsBgCrAAAuAAQKfx0AAwcACAmSG9UEAP0BAAcACAmSG9UEAP0BAAgABAnmD0QgAMsAAAAA.Amìko:BAAALgAECgMJAwAAAA==.',
An='Anadoria:BAAALgADCgYJBgAAAA==.Analferret:BAABLgAECn8VAAMJAAYJkQ3iRQDsAAAJAAYJkQ3iRQDsAAAKAAMJNAoHhACEAAAAAA==.Anastæsia:BAAALgADCgYJBwABLgAECgMJAwAEAAAAAA==.Anda:BAAALgAECgUJCAAAAA==.Anitabidet:BAAALgADCgcJBwAAAA==.',
Ap='Apepi:BAAALgADCgcJBwAAAA==.Apolion:BAAALgADCgQJBAAAAA==.Apoundofcake:BAAALgAECgEJAQAAAA==.Appauling:BAAALgADCgYJBgAAAA==.',
Ar='Arclore:BAABLgAECn8WAAQBAAcJHw4P1ADIAAABAAUJkAoP1ADIAAALAAUJyQrAUgDAAAAMAAEJYgFbTwARAAAAAA==.Argenor:BAAALgAECgUJCgAAAA==.Ariadni:BAAALgAECgYJEQAAAA==.Aricict:BAAALgAECgMJAwAAAA==.Arlý:BAAALgAECgMJBQAAAA==.Aruneza:BAABLgAECn8pAAIIAAkJOA5IDwCzAQAIAAkJOA5IDwCzAQAAAA==.',
As='Asajj:BAAALgAECgUJDgAAAA==.Asharie:BAAALgADCgEJAQAAAA==.Ashcatchm:BAAALgADCgMJAwABLgAECgcJEQAEAAAAAA==.Ashergon:BAAALgAECgQJBAABLgAECggJFwAKAAckAA==.Asheriz:BAAALgAECgcJDgABLgAECggJFwAKAAckAA==.Asherous:BAABLgAECn8XAAMKAAgJByRWFwBbAgAKAAgJByRWFwBbAgAJAAEJbgxShgA0AAAAAA==.Ashiashi:BAAALgAECgEJAQABLgAECgkJIAABAKYiAA==.Ashomá:BAAALgADCgcJCAAAAA==.Ashtroglide:BAAALgAECgcJCwABLgAECggJFwAKAAckAA==.Ashèr:BAAALgAECgcJDgABLgAECggJFwAKAAckAA==.Askara:BAAALgADCgcJBwAAAA==.Astyria:BAAALgADCgUJBQAAAA==.Aszura:BAAALgADCgUJDwAAAA==.',
Au='Auntieshaman:BAAALgADCgEJAQAAAA==.Auranhis:BAAALgAECgEJAgAAAA==.Auriailas:BAAALgADCgcJCQAAAA==.Autoignition:BAAALgADCgMJAwAAAA==.',
Av='Avidel:BAAALgAECgcJEAAAAA==.Avryn:BAABLgAECn8VAAMNAAcJqhchFAA3AQANAAYJkxchFAA3AQAJAAIJ9BnkXgCWAAAAAA==.',
Ay='Ayilime:BAAALgAECgQJBQAAAA==.',
Ba='Badcompanytt:BAAALgADCgIJAgAAAA==.Balør:BAAALgAECgMJAwABLgAECgkJKAAOAIcTAA==.',
Be='Beanvoid:BAAALgADCgYJBgAAAA==.Beardsaint:BAAALgADCgUJBQAAAA==.Beefini:BAAALgAECgMJAwABLgAECggJIQAPADwlAA==.Beenah:BAABLgAECn8ZAAIQAAcJ2QV1gQAMAQAQAAcJ2QV1gQAMAQAAAA==.Belethiel:BAAALgADCgEJAQAAAA==.Bellinopher:BAAALgADCggJDQABLgAECgcJIQARAH8RAA==.Benafflock:BAAALgAECgYJBwAAAA==.Bence:BAAALgAECgMJBAABLgAECgkJHQASACoOAA==.Benefitheals:BAAALgAECgUJBwAAAA==.Benefitpally:BAAALgAECgQJBwAAAA==.Benefitsham:BAAALgADCgYJBgAAAA==.',
Bi='Bigbibble:BAABLgAECn8aAAITAAgJ0hTpLQCNAQATAAgJ0hTpLQCNAQAAAA==.Birdien:BAAALgAECgYJBgAAAA==.',
Bl='Blackrose:BAAALgADCgIJAgABLgAECgkJGAAMANIbAA==.Blamson:BAAALgADCgYJCgAAAA==.Bloodrain:BAABLgAECn8bAAIUAAcJfguxPgAiAQAUAAcJfguxPgAiAQAAAA==.Blubolt:BAAALgAECgQJBAAAAA==.',
Bo='Boomie:BAAALgAFFAcJBAAAAA==.Boopty:BAAALgADCgQJAwAAAA==.Booptyboop:BAAALgAECgQJDwAAAA==.Booptydo:BAAALgADCgcJCAAAAA==.Boris:BAAALgAECgEJAQAAAA==.Bowhawk:BAABLgAECn8UAAIQAAUJmQ7ElQDgAAAQAAUJmQ7ElQDgAAAAAA==.Bozag:BAAALgADCgIJAgAAAA==.',
Br='Braiin:BAAALgAFFAIJAwABLgAFFAYJGwADAP0YAA==.Brakken:BAAALgADCgQJBAAAAA==.Brawll:BAAALgAECgEJAgAAAA==.Brazyn:BAAALgADCgYJBgAAAA==.Brevarda:BAACLgAFFH8GAAIKAAIJ3xmjRgCXAAAKAAIJ3xmjRgCXAAAuAAQKfzEAAwoACAk6Hh8ZAFQCAAoACAk6Hh8ZAFQCAAkABgloDStHAOYAAAAA.Brokenmind:BAAALgAECgQJBAABLgAECgUJEQAEAAAAAA==.Brubble:BAAALgADCgMJAwAAAA==.Brugg:BAAALgADCgYJBgAAAA==.',
Bu='Bubbles:BAAALgADCgEJAQAAAA==.Bubblzmgee:BAABLgAECn8sAAIRAAkJEA8xFwDuAQARAAkJEA8xFwDuAQAAAA==.Bushmommy:BAAALgAECgIJAgAAAA==.',
Ca='Cadence:BAAALgAECgEJAgAAAA==.Cadin:BAABLgAECn8VAAMKAAkJSxmPDQCvAgAKAAkJSxmPDQCvAgAJAAcJYhdfLwCkAQAAAA==.Cakeman:BAAALgADCgEJAQAAAA==.Calehunter:BAAALgAECgUJBQAAAA==.Cameltotem:BAAALgAECgMJAwAAAA==.Capnblood:BAAALgAECgEJAgAAAA==.Capone:BAAALgAECgUJCwAAAA==.Carahz:BAABLgAECn8aAAIVAAcJWg9/IAAFAQAVAAcJWg9/IAAFAQAAAA==.Carindria:BAAALgAECgEJAgAAAA==.Cattiebrie:BAAALgAECgEJAQAAAA==.Caylavana:BAABLgAECn8mAAMWAAgJyhZ7EgD7AQAWAAgJyhZ7EgD7AQAQAAIJCxF9rQBpAAAAAA==.',
Ce='Celaylria:BAAALgAECgYJEwAAAA==.',
Ch='Chabz:BAAALgAECgQJAwAAAA==.Chai:BAABLgAECn8rAAMXAAgJZR0EDgBSAgAXAAgJZR0EDgBSAgADAAYJ4hh8OQDAAQABLgAFFAUJFQASAFEcAA==.Chantille:BAAALgAECgEJAQAAAA==.Charmed:BAABLgAECn8UAAIYAAkJRRDMGACEAQAYAAkJRRDMGACEAQAAAA==.Charmíng:BAAALgAECgYJDAABLgAFFAQJCAAZAAYhAA==.Cheryll:BAAALgAECgUJBQAAAA==.Chunknörris:BAAALgADCggJFQAAAA==.',
Ci='Cint:BAABLgAECn8UAAIUAAcJ+AY3SwDwAAAUAAcJ+AY3SwDwAAAAAA==.',
Cl='Clio:BAAALgAFFAIJAwAAAA==.Cloudedjade:BAABLgAECn8bAAIMAAcJ6wiBIQDXAAAMAAcJ6wiBIQDXAAAAAA==.',
Co='Coleybear:BAAALgAECgcJEwAAAA==.Condewit:BAAALgAECgEJAQAAAA==.Condragos:BAAALgAECgUJBQAAAA==.Copedh:BAAALgAECgQJBAABLgAECgkJJgAFACcdAA==.Copedk:BAABLgAECn8mAAIFAAkJJx3LBwB3AgAFAAkJJx3LBwB3AgAAAA==.Copedogg:BAAALgADCgcJDgABLgAECgkJJgAFACcdAA==.Copemonkk:BAAALgADCgMJAwABLgAECgkJJgAFACcdAA==.Copepriest:BAAALgADCgkJCQABLgAECgkJJgAFACcdAA==.Copeshamm:BAAALgAECgUJBQABLgAECgkJJgAFACcdAA==.Corrode:BAAALgAECggJCQAAAA==.Covertm:BAAALgAECgcJEgAAAA==.Covertw:BAAALgADCgEJAQAAAA==.',
Cr='Craq:BAAALgAECgEJAgAAAA==.Crashedout:BAAALgADCgEJAgAAAA==.Crashknight:BAAALgAECgEJAQABLgAECgQJDAAEAAAAAA==.Crew:BAAALgAECgYJCQAAAA==.Cricky:BAAALgAECgEJAQAAAA==.Crims:BAABLgAECn8ZAAIIAAgJ5xYxDADtAQAIAAgJ5xYxDADtAQAAAA==.Crinke:BAAALgADCgEJAQAAAA==.',
Cu='Culture:BAAALgAECgYJEAAAAA==.',
Cy='Cybeldin:BAABLgAECn8rAAIaAAkJdwlsEAAuAQAaAAkJdwlsEAAuAQAAAA==.Cyberdemonxd:BAAALgADCgYJBwABLgAECgkJHQAPAOYQAA==.',
Da='Daadeedaa:BAACLgAFFH8KAAIZAAQJDxcQQQBCAQAZAAQJDxcQQQBCAQAuAAQKfzAAAhkACAkqJLsjAHICABkACAkqJLsjAHICAAAA.Daddysparey:BAABLgAECn8iAAIGAAYJghNeaAAuAQAGAAYJghNeaAAuAQAAAA==.Dagoba:BAAALgAECgMJAgAAAA==.Dakk:BAABLgAECn87AAIZAAkJPxV9OwAQAgAZAAkJPxV9OwAQAgAAAA==.Dardeathicus:BAACLgAFFH8MAAIPAAQJPR63RQA7AQAPAAQJPR63RQA7AQAuAAQKfyAAAg8ACQnNIIkoAJgCAA8ACQnNIIkoAJgCAAAA.Darderyag:BAABLgAECn8dAAIZAAgJtRquOgATAgAZAAgJtRquOgATAgAAAA==.Darek:BAAALgAECgYJEwAAAA==.Dariara:BAAALgAECgEJAQAAAA==.Darkbud:BAAALgADCggJEQAAAA==.Darkfeazer:BAAALgADCgEJAQAAAA==.Darkforge:BAAALgAECgYJBQAAAA==.Darkrife:BAAALgAECgEJAQAAAA==.Darmonkicus:BAAALgAFFAIJAgAAAA==.Daymann:BAAALgAECgYJBgAAAA==.Dazzan:BAAALgADCgUJBQAAAA==.',
De='Deadlocks:BAAALgADCgEJAQAAAA==.Deathhold:BAAALgAECgYJBwAAAA==.Debilitation:BAAALgADCgIJAgAAAA==.Dedrys:BAAALgAECgEJAQAAAA==.Deklan:BAAALgAECgEJAwAAAA==.Delsid:BAAALgAECgMJAwAAAA==.Demonsteven:BAAALgADCgcJCgAAAA==.Dependabull:BAAALgADCgYJCQABLgADCgcJBwAEAAAAAA==.Dernis:BAAALgAECgIJAgAAAA==.Deshaman:BAABLgAECn8jAAIJAAgJDhojFQATAgAJAAgJDhojFQATAgABLgAFFAUJFQAQAJYfAA==.Devilbeast:BAAALgAECgQJDAAAAA==.',
Dh='Dhargo:BAAALgADCgcJBwAAAA==.',
Di='Dirte:BAAALgADCgYJDQAAAA==.Dirty:BAABLgAECn8eAAIJAAgJ5BOIJQDlAQAJAAgJ5BOIJQDlAQAAAA==.',
Dk='Dkbygorm:BAAALgADCgQJBwAAAA==.',
Do='Dolfi:BAAALgADCggJDAAAAA==.Dorlesette:BAABLgAECn8kAAMbAAkJqwcqOwAsAQAbAAkJqwcqOwAsAQAOAAIJ7AKsdwA/AAAAAA==.',
Dr='Dravindil:BAAALgAECgkJBgAAAA==.Dreamlesnite:BAABLgAECn8eAAICAAcJZAfujgAHAQACAAcJZAfujgAHAQAAAA==.Dreidelman:BAAALgAECgIJAwAAAA==.Drkstar:BAAALgAECgYJCwAAAA==.',
Du='Dudeicus:BAAALgAECgUJBQAAAA==.Dunthur:BAAALgADCgYJBgAAAA==.Duoda:BAABLgAFFH8GAAIbAAMJyBN7IADwAAAbAAMJyBN7IADwAAABLgAFFAYJEQAIAMgRAA==.Durto:BAAALgAECgEJAQABLgAECgQJCAAEAAAAAA==.',
Dy='Dylora:BAABLgAECn8rAAIbAAkJuRZqFwAgAgAbAAkJuRZqFwAgAgAAAA==.',
['Dï']='Dïesel:BAAALgAECgIJAgAAAA==.',
['Dó']='Dólores:BAAALgADCgYJBgAAAA==.',
['Dö']='Dödskott:BAAALgADCgkJDwAAAA==.',
Ec='Eclipsa:BAAALgAECgcJBwAAAA==.',
Eg='Egregore:BAABLgAECn8UAAIGAAYJvA6ffgD7AAAGAAYJvA6ffgD7AAAAAA==.',
El='Elassha:BAAALgAECgEJAQAAAA==.Ellaria:BAABLgAECn8pAAMGAAkJGxYmLwDrAQAGAAkJChQmLwDrAQAYAAYJVhjlJQCQAQAAAA==.Elyselyia:BAAALgAECgUJBQAAAA==.Elysindrall:BAABLgAECn8lAAIIAAgJGxbSCgALAgAIAAgJGxbSCgALAgAAAA==.',
Em='Emokins:BAABLgAECn8rAAIJAAkJvCORAwAVAwAJAAkJvCORAwAVAwAAAA==.Emouri:BAAALgADCgQJBQAAAA==.',
En='Endesh:BAABLgAECn8rAAMSAAkJggh+LwBTAQASAAkJggh+LwBTAQAHAAMJ7QXbGwBPAAAAAA==.Enolah:BAAALgADCgMJAwAAAA==.',
Er='Eradica:BAAALgADCgYJDQAAAA==.Erubus:BAACLgAFFH8MAAQOAAMJDyCHHwARAQAOAAMJDyCHHwARAQAbAAIJDxDmMAB9AAAcAAEJQwGZFAA9AAAuAAQKfxcABA4ACQmFIEQWAFcCAA4ACQmFIEQWAFcCABsAAgk2E/tWAHMAABwAAQm/Ds95ADcAAAAA.Eryss:BAABLgAECn8aAAIQAAcJYwjReAAfAQAQAAcJYwjReAAfAQAAAA==.',
Es='Escånor:BAAALgAECgYJBwAAAA==.Esmeraldita:BAAALgADCgYJDwAAAA==.',
Ev='Evercleâr:BAAALgADCgkJAgAAAA==.Evilblixz:BAAALgADCgYJAQAAAA==.Evoked:BAABLgAECn8YAAMIAAYJEwx0GwACAQAIAAYJEwx0GwACAQAHAAUJdAWQGQBiAAAAAA==.',
Ex='Excentric:BAAALgAECgYJCgABLgAFFAcJEAAZAEsYAA==.Expiraman:BAAALgADCgYJBgAAAA==.',
Fa='Faeliel:BAAALgADCgYJBgABLgAFFAUJEwAUAEAbAA==.Faelýn:BAAALgAECgcJEgAAAA==.Faessa:BAAALgADCgIJAgAAAA==.Falcone:BAAALgAECgcJBwAAAA==.Fanden:BAAALgADCgYJCQAAAA==.Fartimer:BAAALgADCgYJBgABLgAECgkJGwADAG0VAA==.',
Fd='Fdk:BAAALgAECgEJAgAAAA==.',
Fe='Feathering:BAAALgAECgYJEgAAAA==.Fellariene:BAAALgADCgcJCAAAAA==.Fellraiser:BAAALgAECgQJBwAAAA==.Feoralaure:BAAALgADCgEJAQAAAA==.',
Fi='Figjam:BAAALgADCgkJCgABLgAECgYJGwAbAIgUAA==.Fistenlick:BAAALgADCgYJBgABLgADCggJCAAEAAAAAA==.',
Fl='Flashylights:BAAALgAECgIJAwAAAA==.Fluoria:BAAALgAECgQJEgAAAA==.Fláreon:BAABLgAECn8ZAAILAAcJGhk9HQAsAgALAAcJGhk9HQAsAgAAAA==.',
Fr='Fragarach:BAAALgAECgEJAQAAAA==.Frostynipie:BAAALgADCgMJAwAAAA==.Frutypebblz:BAABLgAECn8eAAIdAAYJKgosFwDJAAAdAAYJKgosFwDJAAAAAA==.',
Fu='Furrsure:BAAALgAECgEJAQAAAA==.Fuzznn:BAAALgAECgMJAwABLgABCgIJAgAEAAAAAA==.',
['Fà']='Fàmous:BAABLgAECn8YAAMRAAkJ6BZpFQD/AQARAAkJ/hJpFQD/AQATAAIJvB4OYgCoAAAAAA==.',
Ga='Gainful:BAAALgAECgEJAQABLgAECgkJFAACABESAA==.Galabris:BAABLgAECn8rAAIFAAkJnCJeAwDuAgAFAAkJnCJeAwDuAgAAAA==.Galen:BAAALgAECgEJAwAAAA==.',
Ge='Geranin:BAAALgADCgUJCAAAAA==.Gervire:BAAALgADCgcJCAAAAA==.',
Gh='Ghouldân:BAAALgAECgkJAQAAAA==.Ghoulmania:BAAALgAECgkJCwAAAA==.',
Gi='Gimglich:BAAALgADCgcJAwAAAA==.Gimligrimes:BAAALgADCgEJAQAAAA==.Ginx:BAAALgADCgMJBAAAAA==.Gitchusum:BAAALgAECgUJBgAAAA==.',
Gl='Glaedry:BAAALgAECgEJAwAAAA==.',
Go='Goose:BAABLgAECn8XAAIRAAkJ5hF/HwCiAQARAAkJ5hF/HwCiAQAAAA==.Gorefang:BAAALgAECgEJAQAAAA==.Gormladin:BAABLgAECn8aAAILAAcJHhfsLACFAQALAAcJHhfsLACFAQAAAA==.',
Gr='Greenbahamut:BAAALgAECgEJAQAAAA==.Gregamesh:BAAALgADCgcJDgAAAA==.Grill:BAAALgAECgMJAwAAAA==.Grimsreaper:BAAALgADCgkJDgAAAA==.Grizzlypouch:BAAALgADCgYJBgAAAA==.Grouchy:BAAALgAECgIJAwAAAA==.',
Gu='Guillimus:BAAALgADCgcJBgAAAA==.Gultadorn:BAAALgADCgMJAwAAAA==.',
['Gï']='Gïzmö:BAABLgAECn8aAAIeAAYJBAuFHgDYAAAeAAYJBAuFHgDYAAAAAA==.',
Ha='Halfang:BAAALgADCgYJEQAAAA==.Handham:BAAALgAECgYJCgAAAA==.Hanroro:BAAALgADCgQJAwAAAA==.Hasheth:BAAALgAECgYJCQAAAA==.Havocfang:BAAALgAECgkJCQAAAA==.Hawkiing:BAAALgADCgQJBAAAAA==.Hazuki:BAAALgAECgQJBAAAAA==.',
He='Helouise:BAAALgADCgQJBAAAAA==.Herbalxur:BAAALgAECgQJCAAAAA==.',
Hi='Hibikase:BAAALgAECgYJBgAAAA==.Hildegarde:BAAALgAECgEJAQABLgAECgYJGQAGAI0eAA==.Hitpoints:BAAALgAECgUJEQAAAA==.',
Ho='Hobbikeen:BAABLgAECn8iAAMIAAgJ/hx/BQCaAgAIAAgJ/hx/BQCaAgASAAgJqg5wLABlAQAAAA==.Holyhope:BAABLgAECn8XAAILAAcJmhP1LwByAQALAAcJmhP1LwByAQAAAA==.Holymana:BAABLgAECn8qAAIBAAcJMR1BOwD2AQABAAcJMR1BOwD2AQAAAA==.Hoshea:BAAALgADCgMJAwAAAA==.Hottyoreo:BAAALgADCgYJCwAAAA==.Howcom:BAAALgADCgcJBwAAAA==.',
Hu='Huffingpaint:BAAALgAECgYJEAABLgAECgYJGQAGAI0eAA==.Hundrakor:BAABLgAECn8UAAIQAAkJ6hLkKQAMAgAQAAkJ6hLkKQAMAgAAAA==.Huntinghawk:BAAALgAECgEJAQABLgAECgUJFAAQAJkOAA==.Hutzil:BAABLgAECn8kAAMCAAkJehxEHQBbAgACAAkJchtEHQBbAgAfAAMJWRmVGwCXAAAAAA==.Hutzilla:BAAALgAECgIJBAAAAA==.',
['Hÿ']='Hÿpothermia:BAAALgAECgMJAwAAAA==.',
Il='Illidianna:BAABLgAECn8cAAMGAAgJuxjwMQDeAQAGAAgJuxjwMQDeAQAYAAIJixJiXABvAAAAAA==.',
Im='Imbluedabdee:BAAALgADCgQJBAAAAA==.Imitlol:BAAALgAFFAEJAQAAAA==.',
In='Inception:BAAALgADCgkJFAAAAA==.',
Ir='Irrefutable:BAAALgADCgQJBAAAAA==.',
It='Itchynyple:BAAALgADCggJCAAAAA==.',
Ja='Jabadabadoo:BAAALgAECgEJAQAAAA==.Jackatak:BAAALgADCgMJAwAAAA==.Jacoblack:BAAALgADCgMJAwAAAA==.Jadin:BAAALgADCgEJAQAAAA==.Jaefury:BAABLgAECn8cAAINAAkJVhxABgBHAgANAAkJVhxABgBHAgAAAA==.Jakes:BAAALgAECgEJAQAAAA==.Jandinga:BAAALgAECgQJBAAAAA==.',
Ji='Jimadler:BAAALgADCgMJAwABLgAECgIJAgAEAAAAAA==.Jimbi:BAAALgAFFAIJBAAAAA==.Jiminybilini:BAAALgAECgcJBQAAAA==.Jimmybull:BAAALgADCgEJAQAAAA==.Jinho:BAAALgAECgEJAQABLgAECgkJHAAgACsiAA==.Jinrop:BAEALgADCgcJBwABLgAECgcJFgAdACMUAA==.',
Jo='Jobuu:BAAALgAECgEJAgAAAA==.Johnnypopoff:BAABLgAECn8kAAIZAAkJOxTkRgDrAQAZAAkJOxTkRgDrAQAAAA==.Johnwolf:BAAALgAECgQJCQAAAA==.Jojohunts:BAAALgAECgcJCwAAAA==.Joshodin:BAAALgAECgEJAQAAAA==.',
Jp='Jpðc:BAAALgAECgYJCgAAAA==.',
Ju='Juanjo:BAAALgADCgcJBwABLgAECgkJMwAZAA4eAA==.Junyubych:BAAALgAECgYJEgAAAA==.Justylln:BAAALgADCgMJAgAAAA==.Justzach:BAABLgAECn83AAIOAAkJXhr7CgBnAgAOAAkJXhr7CgBnAgAAAA==.',
['Jà']='Jàccuse:BAABLgAECn8bAAIbAAYJiBRlMABnAQAbAAYJiBRlMABnAQAAAA==.Jàrnsaxa:BAAALgADCgEJAQAAAA==.',
['Jò']='Jòhnnypopo:BAAALgAECgcJDQAAAA==.',
Ka='Kadywompus:BAAALgADCgcJBwAAAA==.Kaeladra:BAAALgADCgcJDgAAAA==.Kailm:BAAALgADCgIJAgABLgAFFAUJCwAUADYZAA==.Kait:BAAALgAECgIJAgAAAA==.Kalida:BAAALgADCgQJBAAAAA==.Kalniel:BAAALgADCgUJBQAAAA==.Kalorie:BAAALgADCgYJBgABLgAECgYJGQAGAI0eAA==.Kassaalaa:BAAALgADCgYJBgAAAA==.Kasume:BAAALgAECgQJBQAAAA==.Kaylastrasza:BAAALgAECgEJAQAAAA==.Kazurend:BAACLgAFFH8VAAIhAAcJgiIhAgBDAgAhAAcJgiIhAgBDAgAuAAQKfxoAAiEACAnQI7wFADMDACEACAnQI7wFADMDAAAA.',
Ke='Keiadon:BAAALgADCgkJCQAAAA==.Kelavax:BAAALgAECgkJBQAAAA==.Keleira:BAABLgAECn8WAAIZAAcJPRa/bgCAAQAZAAcJPRa/bgCAAQAAAA==.Kelemvore:BAAALgADCgMJBgAAAA==.Kericcandere:BAAALgADCgIJAwAAAA==.Kerm:BAEALgAECgEJAgAAAA==.Keyaielenst:BAAALgADCgcJBwAAAA==.',
Kh='Khristina:BAAALgADCgkJDQAAAA==.',
Ki='Kiel:BAABLgAFFH8FAAIYAAQJQxqgDwDxAAAYAAQJQxqgDwDxAAABLgAECgYJGQAgAB0gAA==.Kindos:BAAALgADCgQJBwAAAA==.Kippo:BAEALgAECgEJAQABLgAFFAUJDgAPADgRAA==.Kiramman:BAAALgAECgUJCwAAAA==.Kirsute:BAAALgADCgYJBgAAAA==.Kirxcy:BAAALgADCgUJCAAAAA==.Kithiri:BAAALgAECgQJEQAAAA==.',
Kn='Knarn:BAABLgAECn8jAAIWAAgJsx5LFADoAQAWAAgJsx5LFADoAQAAAA==.',
Ko='Koralie:BAACLgAFFH8cAAMQAAcJ3xXWAACrAQAQAAYJVRjWAACrAQAaAAEJkAkaJgBPAAAuAAQKfx4AAxAACAloHW4bAGICABAACAloHW4bAGICABoABQm+D6VcANAAAAAA.Kotiria:BAAALgAECgEJAQAAAA==.',
Kr='Krillaxx:BAAALgAECgcJDwAAAA==.Krimzin:BAAALgAECgcJDgABLgAFFAUJEQAQAAwdAA==.Krolg:BAAALgAECgQJCQAAAA==.Kromvar:BAAALgAECgQJBwAAAA==.',
Ku='Kungfused:BAAALgADCgUJCAABLgAECgQJBgAEAAAAAA==.Kurisux:BAABLgAFFH8IAAIPAAMJ+BTMaQD2AAAPAAMJ+BTMaQD2AAAAAA==.',
Ky='Kyliekat:BAAALgAECgYJEAAAAA==.Kyndlynn:BAAALgAECgQJEAAAAA==.Kyriea:BAAALgAECgEJAQAAAA==.',
La='Lanceelot:BAAALgAECgIJAgAAAA==.Lanel:BAAALgAECgUJCQAAAA==.Lathelous:BAABLgAECn8jAAIMAAgJnSN7AwCyAgAMAAgJnSN7AwCyAgAAAA==.',
Ld='Ldt:BAAALgADCgMJAwAAAA==.',
Le='Leintheir:BAAALgAECgMJAwAAAA==.Leththol:BAAALgADCgkJJQAAAA==.Letyoudie:BAAALgAECgQJCwAAAA==.Levenza:BAABLgAECn8UAAIiAAgJYhRrDQBOAQAiAAgJYhRrDQBOAQAAAA==.',
Li='Licita:BAAALgAECgUJCgAAAA==.Lickingsalt:BAAALgAECgQJBAABLgAFFAEJAQAEAAAAAA==.Lideina:BAABLgAECn8fAAIPAAYJthzZaABwAQAPAAYJthzZaABwAQAAAA==.Lielandra:BAAALgAECgcJCAAAAA==.Lightdinger:BAAALgAECgYJDAAAAA==.Lightt:BAABLgAECn9AAAMTAAgJLB3bDABwAgATAAgJLB3bDABwAgAhAAUJNQEQVQBvAAAAAA==.Liightt:BAABLgAECn8ZAAITAAYJDRKmLgAzAQATAAYJDRKmLgAzAQAAAA==.Lilnug:BAAALgAECgQJDAAAAA==.Lindsey:BAAALgADCgkJDQABLgAECgUJCwAEAAAAAA==.Littlenyne:BAAALgAECgUJCAAAAA==.',
Ll='Llando:BAAALgADCgYJBgAAAA==.Llars:BAABLgAECn8jAAIKAAgJyRohHgAvAgAKAAgJyRohHgAvAgAAAA==.Lleonardo:BAAALgADCgEJAQAAAA==.',
Lo='Lockkjaw:BAAALgAECgEJAQAAAA==.Locknorris:BAAALgADCgUJBgAAAA==.Loghrif:BAAALgAECgQJBAABLgAECgUJBgAEAAAAAA==.Loptear:BAAALgAECgEJAQAAAA==.Loryanna:BAAALgADCgUJCwAAAA==.Louie:BAAALgAECgMJBAAAAA==.Lovehandless:BAAALgADCgEJAQAAAA==.Lovespell:BAAALgADCgUJBQAAAA==.',
Lu='Lucavian:BAAALgAECgcJEAAAAA==.Lucavias:BAAALgAECgMJBQAAAA==.Luckydruidh:BAABLgAECn8VAAMDAAgJqxmEHgAuAgADAAgJqxmEHgAuAgAXAAEJxQ3vewA6AAAAAA==.Luckyevoker:BAAALgADCgcJEgABLgAECggJFQADAKsZAA==.Lurien:BAAALgAECggJEgAAAA==.Luxilejo:BAAALgADCgYJCwAAAA==.',
Ly='Lyfebane:BAABLgAECn82AAMBAAkJGBehLAAsAgABAAkJGBehLAAsAgALAAgJMxhBHAD6AQAAAA==.',
['Ló']='Lórien:BAAALgADCgEJAQAAAA==.',
['Lø']='Lørs:BAABLgAECn8sAAIZAAYJDRQ5lQAzAQAZAAYJDRQ5lQAzAQAAAA==.Lørz:BAAALgAECgQJBAAAAA==.',
Ma='Machorn:BAAALgADCgcJBwAAAA==.Mageis:BAAALgADCgMJAwAAAA==.Magetree:BAAALgAFFAIJAgABLgAFFAQJDAAMAJcZAA==.Mageyoucream:BAAALgAECgIJAgAAAA==.Magnai:BAAALgADCgcJBwAAAA==.Main:BAABLgAECn8wAAIBAAkJHQtsXgCVAQABAAkJHQtsXgCVAQAAAA==.Majrmiståke:BAABLgAFFH8GAAIZAAMJ3Qt9aQDjAAAZAAMJ3Qt9aQDjAAABLgAFFAUJEAAGAKUZAA==.Malagore:BAAALgAFFAEJAQABLgAECggJFwASALQVAA==.Malec:BAAALgADCggJCAAAAA==.Malicemech:BAAALgADCgkJEAAAAA==.Maliceone:BAAALgAECgYJEgAAAA==.Malicepaly:BAAALgAECgQJBQAAAA==.Manek:BAAALgADCgcJCAABLgAECgkJOwAZAD8VAA==.Mansmilk:BAAALgAECgQJBAAAAA==.Mardara:BAAALgAECgYJBgAAAA==.Marraxa:BAAALgADCgYJBgAAAA==.Mattshamon:BAAALgADCgcJBwAAAA==.Max:BAABLgAECn8ZAAICAAkJ5R5cNQDrAQACAAkJ5R5cNQDrAQAAAA==.Mayé:BAAALgAECgYJCwAAAA==.',
Mb='Mbaku:BAAALgAECgYJCwABLgAFFAMJBgAhAMUcAA==.',
Me='Melechim:BAAALgADCgkJCQAAAA==.Melinoe:BAABLgAECn8aAAICAAYJmAx3igAQAQACAAYJmAx3igAQAQAAAA==.Merc:BAAALgAECgUJBQAAAA==.Merithrá:BAAALgAECgIJAgAAAA==.',
Mi='Micah:BAACLgAFFH8dAAIIAAcJVhBxBQChAQAIAAcJVhBxBQChAQAuAAQKfxgAAwgACAnkGggOAFYCAAgACAnkGggOAFYCABIABQm/GpsyADUBAAAA.Milenad:BAAALgAECgIJAgAAAA==.Minilyfe:BAAALgAECgEJAQAAAA==.Mirelia:BAAALgADCgMJAgAAAA==.Mishosuki:BAABLgAECn8YAAIPAAYJngsNpgD6AAAPAAYJngsNpgD6AAAAAA==.Misky:BAAALgADCgEJAQAAAA==.Misscleo:BAABLgAECn8oAAIZAAkJ+BI1QwD2AQAZAAkJ+BI1QwD2AQAAAA==.Mizzyboii:BAAALgADCgMJAwAAAA==.',
Mk='Mk:BAAALgAECggJDwAAAA==.',
Mn='Mnesarte:BAABLgAECn8XAAIBAAYJZRahkgAtAQABAAYJZRahkgAtAQAAAA==.',
Mo='Moanalisa:BAAALgAECgEJAQAAAA==.Moi:BAABLgAFFH8IAAISAAUJBhPoIQAVAQASAAUJBhPoIQAVAQABLgAFFAQJDwAZAIsdAA==.Monkilha:BAABLgAECn8XAAIcAAgJABm3EgAEAgAcAAgJABm3EgAEAgAAAA==.Moonkist:BAABLgAECn8YAAMDAAcJsB1aGwBIAgADAAcJsB1aGwBIAgAXAAEJRAN6jQAhAAAAAA==.Moonsgrace:BAAALgADCgkJEwAAAA==.Moose:BAACLgAFFH8GAAIPAAIJKR8XjQCzAAAPAAIJKR8XjQCzAAAuAAQKfzoAAg8ACAlgI9EXAJYCAA8ACAlgI9EXAJYCAAAA.Morpheos:BAABLgAECn8bAAMDAAkJbRWrRABaAQADAAkJbRWrRABaAQAXAAQJhgfkUgCSAAAAAA==.Morroe:BAAALgADCgEJAQAAAA==.Moxci:BAAALgAECgQJBQAAAA==.',
Mu='Mudamudamuda:BAAALgADCgYJDQABLgAFFAUJEwAUAEAbAA==.Muffintop:BAAALgADCgEJAQAAAA==.',
My='Mysticforest:BAAALgAECgQJBAAAAA==.',
Na='Naedise:BAAALgADCgcJFgAAAA==.Narue:BAAALgAECgIJAgAAAA==.Natureswild:BAABLgAECn8gAAMXAAkJkhiUIQDwAQAXAAgJ4xeUIQDwAQADAAMJawrZuQBSAAAAAA==.Navariis:BAAALgAECgUJCQAAAA==.Navillus:BAAALgAECgMJBgABLgAFFAcJHAAIAOoPAA==.',
Ne='Necrophyliac:BAAALgAECgYJCwAAAA==.Nelrehim:BAAALgADCgQJBgAAAA==.Nephy:BAAALgAECgQJBAAAAA==.Nephyrium:BAAALgAECgUJCAAAAA==.Nephz:BAAALgAECgYJCgAAAA==.Nephzz:BAAALgAECgQJAwAAAA==.Nethery:BAAALgADCgcJCQAAAA==.Nex:BAAALgAECgEJAQAAAA==.Nezrin:BAAALgAECgYJEQAAAA==.',
Ni='Nidon:BAAALgADCgUJBQAAAA==.Niixxi:BAAALgADCgUJBQAAAA==.',
Nm='Nmbrs:BAABLgAECn8fAAMhAAcJrx8GFgD2AQAhAAcJrx8GFgD2AQARAAEJ7AK9XAApAAAAAA==.',
No='Noirheffer:BAACLgAFFH8MAAMMAAQJlxl/BQD/AAAMAAQJIRF/BQD/AAABAAMJ9hR7TADqAAAuAAQKfycAAwEACQnXHvcXANkCAAEACAlDIvcXANkCAAwABwkXF1EPAKEBAAAA.Noobishdad:BAAALgADCgEJAQAAAA==.Norio:BAAALgADCgcJBwAAAA==.',
Nu='Nulannatoo:BAAALgAECgUJBQAAAA==.Nuukeasaur:BAAALgADCgEJAQAAAA==.',
Ny='Nyadari:BAAALgAECgEJAQAAAA==.Nyphe:BAAALgAECgQJBAAAAA==.Nyrrhi:BAAALgAECgQJCAAAAA==.Nyxiro:BAAALgAECgUJBQAAAA==.',
Od='Odysseus:BAAALgADCgkJFgAAAA==.',
Ol='Oleira:BAAALgAECgUJBQAAAA==.Olgann:BAAALgAECgYJDwAAAA==.Olguita:BAAALgAFFAIJBAAAAA==.Olivertwìst:BAAALgADCgcJBwAAAA==.',
Om='Omgowned:BAAALgAECgYJBwABLgAECgkJGQACAPsSAA==.',
On='Onehothealer:BAABLgAECn8aAAIhAAkJIBbsGQAQAgAhAAkJIBbsGQAQAgAAAA==.',
Oo='Oorua:BAAALgADCgkJDwAAAA==.',
Op='Opheliastar:BAABLgAECn8sAAIhAAkJ5hO+FwDlAQAhAAkJ5hO+FwDlAQAAAA==.',
Ow='Owltoidz:BAAALgAECgEJAQAAAA==.',
Pa='Pad:BAABLgAECn8ZAAMCAAcJpAq0fwAlAQACAAYJpAq0fwAlAQAdAAEJAAAzdQAwAAAAAA==.Pahket:BAAALgAECgQJBAAAAA==.Paintballerr:BAAALgADCgEJAQAAAA==.Paladerp:BAABLgAECn82AAMLAAgJGA+6MABtAQALAAgJGA+6MABtAQABAAcJOxHfeABcAQAAAA==.Pallyown:BAABLgAFFH8KAAILAAIJayOvJQDGAAALAAIJayOvJQDGAAAAAA==.Paprika:BAAALgADCgQJBgAAAA==.Pastorbedtym:BAABLgAECn8YAAIhAAgJeA+nLABJAQAhAAgJeA+nLABJAQAAAA==.Pat:BAAALgAECgMJAwAAAA==.Paulybricks:BAAALgAECgUJBgAAAA==.',
Pe='Pecan:BAAALgAECgcJDgABLgAFFAQJCAAZAAYhAA==.Pewpewbang:BAAALgADCgIJAgAAAA==.',
Ph='Pharla:BAAALgADCgkJEAAAAA==.Phett:BAAALgAECgYJDAAAAA==.',
Pi='Pichon:BAAALgADCgUJCAAAAA==.Pimmscup:BAAALgAECgEJAQAAAA==.Pin:BAAALgAECgcJBgABLgAFFAcJBAAEAAAAAA==.Pirei:BAAALgADCgUJBQAAAA==.Pirozhki:BAAALgADCgYJBgAAAA==.',
Pl='Plagueborn:BAAALgAECgEJAQAAAA==.Plentar:BAAALgADCgkJDgAAAA==.',
Po='Popcorntea:BAAALgAECgEJAgAAAA==.Porgoon:BAAALgAECgQJBQAAAA==.',
Pr='Preserved:BAAALgADCgIJAgAAAA==.Prizzma:BAAALgADCgUJBQAAAA==.',
Ps='Psaul:BAAALgAECgYJCwAAAA==.Psychohexane:BAAALgADCgQJBAAAAA==.',
Py='Pyramys:BAAALgADCgYJBgABLgAFFAUJEwAgACwfAA==.',
Qe='Qedeshah:BAAALgAECggJCAAAAA==.Qesem:BAAALgADCgUJBQAAAA==.',
Qu='Qualaribou:BAAALgADCgQJBAAAAA==.',
Ra='Raal:BAAALgADCgkJHgAAAA==.Raenostra:BAAALgAECgUJEAAAAA==.Raenya:BAAALgAECgYJDQAAAA==.Ragefather:BAAALgADCgEJAQAAAA==.Rageye:BAAALgADCgcJBwAAAA==.Rainydaze:BAAALgAECggJEwAAAA==.Ramcharger:BAABLgAECn8cAAMiAAgJxxQACQCyAQAiAAgJxxQACQCyAQAYAAYJoAzEOwARAQAAAA==.Ranen:BAABLgAECn8gAAIcAAkJ4B2WCgB1AgAcAAkJ4B2WCgB1AgAAAA==.Rashun:BAAALgAECggJEwAAAA==.',
Re='Reanatilax:BAAALgADCgMJAwABLgAECgcJIQARAH8RAA==.Redcinnabar:BAAALgAECgQJDQAAAA==.Regisfilia:BAAALgAECgQJBAABLgAECgYJGQAGAI0eAA==.Rehtilox:BAAALgADCgMJAwABLgAECgcJIQARAH8RAA==.Reilly:BAAALgADCggJFQAAAA==.Rev:BAAALgAECgQJBAAAAA==.Rexxy:BAAALgAECgYJEQAAAA==.',
Ri='Riju:BAAALgAECgcJDgAAAA==.Rikashae:BAAALgAECgEJAQAAAA==.Rillan:BAAALgADCgMJAwAAAA==.Rinzler:BAAALgAECgUJCQAAAA==.Rissa:BAAALgADCgcJDQAAAA==.',
Rn='Rng:BAAALgAECgQJCwAAAA==.',
Ro='Roachcentral:BAAALgADCgUJBgAAAA==.Roachcity:BAAALgADCgUJBQAAAA==.Rockalock:BAAALgADCgYJBgAAAA==.Rogerz:BAAALgADCgUJBQAAAA==.Roleon:BAAALgADCggJCAAAAA==.Rollforpi:BAAALgAECgQJBgABLgAFFAYJGwADAP0YAA==.Ropebunnyana:BAACLgAFFH8JAAIbAAQJRhakGgAjAQAbAAQJRhakGgAjAQAuAAQKfysAAhsACQlEIAYFADADABsACQlEIAYFADADAAAA.Rowkani:BAAALgADCgkJCQAAAA==.',
Ru='Ruki:BAABLgAECn8ZAAMGAAYJjR5rTgB4AQAGAAYJdxtrTgB4AQAYAAIJ7B9kOACeAAAAAA==.',
Ry='Ryand:BAAALgAECgUJCQABLgAFFAUJCQAhAK0SAA==.',
Sa='Sacra:BAAALgAECgEJAQAAAA==.Salarcyn:BAAALgAECgUJDAAAAA==.Saltydk:BAABLgAFFH8FAAIPAAQJwwgZXwAPAQAPAAQJwwgZXwAPAQAAAA==.Samiracy:BAABLgAECn8rAAIdAAkJmhkdAwBGAgAdAAkJmhkdAwBGAgAAAA==.Sannrin:BAAALgAECgYJDAAAAA==.Santhrin:BAAALgADCgcJBwAAAA==.Sapprot:BAAALgADCgcJCQAAAA==.Sarkress:BAAALgADCgkJCQAAAA==.',
Se='Seagal:BAAALgADCgEJAgAAAA==.Senbatorii:BAABLgAECn8aAAQDAAYJFB6fJgD4AQADAAYJFB6fJgD4AQAXAAYJOAnMSQCzAAAeAAQJpwfYKACGAAAAAA==.Seredala:BAAALgADCgUJCwAAAA==.Sethrow:BAABLgAECn8ZAAMCAAkJ+xKJNQDqAQACAAgJ+xKJNQDqAQAdAAEJAAAPRgAAAAAAAA==.Severa:BAAALgAECgYJCgAAAA==.',
Sh='Shaladora:BAAALgADCgYJBgAAAA==.Shalia:BAAALgADCgMJAwABLgADCgMJBgAEAAAAAA==.Shamaster:BAAALgADCgIJAgAAAA==.Sharas:BAAALgAECgQJBQAAAA==.Shawarma:BAAALgAECgYJCwAAAA==.Sheltatha:BAAALgAECgEJAQAAAA==.Shengari:BAABLgAECn8iAAITAAgJbBIRJgBxAQATAAgJbBIRJgBxAQAAAA==.Shotcallà:BAAALgADCgIJAgAAAA==.Shuna:BAAALgAECgUJDQAAAA==.Shyly:BAABLgAECn8WAAIhAAkJfhwiDABsAgAhAAkJfhwiDABsAgAAAA==.Shâbs:BAAALgAECgkJAgAAAA==.',
Si='Sikkly:BAAALgADCgcJEQAAAA==.Siley:BAABLgAECn9ZAAIPAAkJOBZPMwAOAgAPAAkJOBZPMwAOAgAAAA==.Sin:BAAALgAECgcJCAAAAA==.Siphon:BAAALgADCgYJBgAAAA==.',
Sk='Skarletfaith:BAAALgAECgcJEwAAAA==.',
Sl='Sloanya:BAABLgAECn85AAMbAAkJXR5oBwD3AgAbAAkJXR5oBwD3AgAcAAYJKxqmJQCqAQAAAA==.',
Sn='Snarffie:BAAALgAECgYJCgAAAA==.',
So='Solanar:BAAALgADCgUJBQAAAA==.Somedruid:BAABLgAECn8sAAIXAAgJiSMiCQCdAgAXAAgJiSMiCQCdAgAAAA==.',
Sp='Spiarmf:BAAALgADCgUJBQAAAA==.Spicynes:BAAALgADCgQJBwAAAA==.Spicyness:BAAALgAECgIJAgAAAA==.Spiderdk:BAAALgAECgUJCAABLgAFFAUJFQAQAJYfAA==.Spidermonk:BAAALgADCgcJDgABLgAFFAUJFQAQAJYfAA==.Spielberg:BAAALgAECgEJAQAAAA==.Spycmchaggis:BAAALgAECgQJBAAAAA==.Spëcter:BAAALgAECgYJBwABLgAECggJEgAEAAAAAA==.Spëcthyr:BAAALgAECggJEgAAAA==.',
Sq='Squishypoo:BAAALgAECgMJBgAAAA==.',
St='Stache:BAAALgAECgEJAQAAAA==.Stoneyfoam:BAAALgAECgYJBgAAAA==.Stormrider:BAAALgADCgkJCQAAAA==.Stratergron:BAAALgAECgcJAQAAAA==.',
Su='Sugrace:BAAALgAECgYJBgAAAA==.Superdemonzz:BAACLgAFFH8QAAIGAAUJpRmnJgBMAQAGAAUJpRmnJgBMAQAuAAQKfy4AAwYACQmqH54MAMYCAAYACQmqH54MAMYCACIABwkHF6UJAKIBAAAA.Superevokerz:BAAALgADCgcJDgABLgAFFAUJEAAGAKUZAA==.Superlockz:BAAALgADCgkJCQABLgAFFAUJEAAGAKUZAA==.Superpallyz:BAACLgAFFH8JAAILAAMJVxV3IwDWAAALAAMJVxV3IwDWAAAuAAQKfy4AAwsABwnOHh8ZABYCAAsABwnOHh8ZABYCAAwABQkhEeYkAL0AAAEuAAUUBQkQAAYApRkA.Supershamanz:BAAALgAECgYJCgABLgAFFAUJEAAGAKUZAA==.Superspidey:BAAALgADCgIJAgAAAA==.Sushiroll:BAABLgAECn8XAAIcAAgJPx7HDgA0AgAcAAgJPx7HDgA0AgAAAA==.',
Sy='Sydnysweeney:BAAALgADCgMJAwAAAA==.Sylentslit:BAAALgADCggJGgAAAA==.Sylveslem:BAAALgAECgkJDAAAAA==.Syphon:BAAALgADCgMJAwAAAA==.',
['Sô']='Sôlmyr:BAAALgADCgIJAgAAAA==.',
Ta='Tacowarr:BAAALgADCgUJBQAAAA==.Taldazlian:BAAALgAECgMJBgAAAA==.Taliesin:BAAALgAECgMJAwAAAA==.Tallon:BAAALgAECgEJAQAAAA==.Tancy:BAAALgAECgMJAwABLgAECgkJMwADAFcZAA==.Tantalus:BAABLgAECn8bAAIQAAYJpw0+fQAWAQAQAAYJpw0+fQAWAQAAAA==.Tarogen:BAAALgADCgUJBQAAAA==.Tashaler:BAAALgADCgEJAQAAAA==.Tasithia:BAAALgAECgQJBAAAAA==.',
Te='Tealet:BAAALgADCgkJEQAAAA==.Teleion:BAAALgAECgEJAQAAAA==.Tellinor:BAABLgAECn8YAAIBAAYJAQp0twDxAAABAAYJAQp0twDxAAAAAA==.Temporal:BAAALgAECgEJAQAAAA==.Terrestra:BAAALgADCgMJAwAAAA==.Tervor:BAAALgADCgEJAQAAAA==.',
Th='Thanamoros:BAAALgAECgUJBgABLgAFFAMJCQASABEPAA==.Thassarian:BAAALgAECgQJBAABLgAECggJIgAiABkfAA==.Thechosenone:BAAALgADCgIJAgAAAA==.Theroach:BAAALgAECgYJEwAAAA==.Tholdir:BAAALgADCggJCAAAAA==.Throfin:BAAALgAECgUJCgAAAA==.Thundernight:BAAALgAECgcJAgAAAA==.',
Ti='Tiki:BAAALgAECgUJBgAAAA==.Tinc:BAAALgADCgEJAgAAAA==.Tinkerballa:BAAALgADCgUJBQAAAA==.Tinonova:BAAALgAECgEJAgAAAA==.Titsmgee:BAAALgAECgIJAgAAAA==.',
To='Toeren:BAACLgAFFH8VAAIQAAUJlh93HQBOAQAQAAUJlh93HQBOAQAuAAQKfyoAAhAACQm0H6MSAJMCABAACQm0H6MSAJMCAAAA.Tomate:BAAALgADCgQJBAAAAA==.Toph:BAAALgAECgEJAQAAAA==.Tormented:BAAALgAECgYJEwAAAA==.Townsley:BAAALgAECgYJDQAAAA==.',
Tp='Tpain:BAAALgADCgIJAgAAAA==.',
Tr='Traitoros:BAAALgADCgYJBgAAAA==.Tralectra:BAAALgAECgcJDAAAAA==.Tranquilfist:BAAALgADCgQJBQABLgAECgcJEwAEAAAAAA==.Treemonk:BAAALgADCgYJCgABLgAECgkJIAAXAJIYAA==.Trolvere:BAAALgAECgQJBwAAAA==.Trorim:BAAALgADCgYJBgAAAA==.Trïsh:BAAALgAECgQJBgABLgAECgYJCQAEAAAAAA==.',
Tu='Tummy:BAAALgADCgcJEwAAAA==.Turtlesoup:BAAALgADCgYJBgAAAA==.',
Tw='Twëë:BAAALgAECgEJAQAAAA==.',
Ty='Tybonk:BAAALgAECgEJAQAAAA==.Tygragon:BAAALgAECgUJDAAAAA==.Tyinorin:BAAALgAECgIJAQAAAA==.Tylea:BAAALgADCgkJEAAAAA==.',
Tz='Tzipporah:BAAALgAECgYJCAAAAA==.',
Ub='Ubee:BAABLgAECn8YAAIGAAkJTxBLOwC5AQAGAAkJTxBLOwC5AQAAAA==.',
Ul='Ultimakitty:BAABLgAECn8WAAMDAAcJcRk2OACUAQADAAYJOhc2OACUAQAXAAYJ6gm+QADYAAAAAA==.',
Un='Uncertainty:BAAALgAECgEJAQABLgAECgYJGQAGAI0eAA==.Unchanged:BAAALgADCgYJBgAAAA==.Unholymana:BAAALgADCgkJFgAAAA==.',
Va='Vaellin:BAAALgAECgEJAQAAAA==.Valanyr:BAAALgADCgEJAQAAAA==.Vantrix:BAAALgAECgEJAQABLgAFFAMJCQASABEPAA==.Varabo:BAABLgAECn8ZAAIZAAcJBhQPbgCCAQAZAAcJBhQPbgCCAQAAAA==.Varolina:BAAALgAECgEJAQAAAA==.',
Ve='Vehemencê:BAAALgADCgEJAQAAAA==.Velements:BAAALgAECgMJAwABLgAECggJEgAEAAAAAA==.Velemon:BAACLgAFFH8SAAIjAAQJ9w5HEQD3AAAjAAQJ9w5HEQD3AAAuAAQKfxgAAiMACAnuE/ERAOkBACMACAnuE/ERAOkBAAAA.Velisen:BAABLgAECn8fAAMBAAYJrwm4wgDhAAABAAYJEQi4wgDhAAAMAAUJ4gYWMgCFAAAAAA==.Velthala:BAAALgAECggJEgAAAA==.Velystiri:BAAALgADCgcJBgAAAA==.Venedictus:BAAALgADCgMJAwAAAA==.',
Vi='Viergryn:BAAALgAECgEJAgABLgAECgcJEwAEAAAAAA==.Virasdruid:BAAALgAFFAIJBAAAAA==.Virusmonk:BAAALgAECgEJAwAAAA==.Vitner:BAABLgAECn8eAAMHAAkJwhiMCQBpAQASAAkJ6xIjKgB0AQAHAAYJMRmMCQBpAQAAAA==.',
Vo='Vosaleana:BAAALgADCgMJAwAAAA==.',
Vr='Vraak:BAACLgAFFH8bAAIDAAYJ/RhNCwDpAQADAAYJ/RhNCwDpAQAuAAQKfycAAwMACAnhG7YrAAECAAMABwmBHbYrAAECABcABwmaIxYgAP4BAAAA.',
Vu='Vulcus:BAAALgAECgUJCQABLgAFFAYJGwADAP0YAA==.Vulpii:BAAALgADCgYJBQABLgAFFAMJBgAfAEAdAA==.',
Vy='Vyndarien:BAAALgADCgIJAgAAAA==.Vyse:BAAALgADCgEJAQAAAA==.Vyttra:BAAALgADCgMJAwAAAA==.',
Wa='Walak:BAAALgADCgMJAwAAAA==.Warpulse:BAAALgADCgkJFQAAAA==.Warwizard:BAAALgADCgMJAwAAAA==.Watcherseye:BAAALgADCggJDwABLgADCgkJCQAEAAAAAA==.Wavewhisper:BAAALgAECgEJAQAAAA==.Wayofthemist:BAAALgAECgcJBwAAAA==.',
Wc='Wcreator:BAABLgAECn8XAAIBAAYJzhwyNgAHAgABAAYJzhwyNgAHAgAAAA==.',
We='Weapònized:BAABLgAECn8UAAIGAAYJWg4SjwDYAAAGAAYJWg4SjwDYAAAAAA==.Webaldes:BAAALgAECgEJAQAAAA==.',
Wh='Whitestain:BAABLgAECn8bAAIaAAgJfApbEgAQAQAaAAgJfApbEgAQAQAAAA==.',
Wi='Windyskie:BAAALgADCgEJAQAAAA==.Wingman:BAACLgAFFH8RAAIHAAQJvCZpAADMAQAHAAQJvCZpAADMAQAuAAQKfzMAAgcACAmXJpgAAIsDAAcACAmXJpgAAIsDAAAA.',
Wo='Womdalie:BAAALgADCgQJBgAAAA==.Woodey:BAAALgADCgEJAQAAAA==.Wowame:BAAALgAFFAEJAQAAAA==.',
Wy='Wyckedpally:BAAALgADCgYJDAAAAA==.',
Xa='Xanthös:BAAALgAFFAEJAQABLgAFFAYJGwADAP0YAA==.',
Xe='Xemnastrasza:BAACLgAFFH8JAAQSAAMJEQ+GMgDJAAASAAMJEQ+GMgDJAAAIAAIJaQMXIQBkAAAHAAEJ0QNnCwBLAAAuAAQKfxYABBIACAkdFMQhALEBABIACAnSEcQhALEBAAcABAmmCPEtAKsAAAgAAQlrBYZLACsAAAAA.Xenonne:BAACLgAFFH8OAAIGAAUJFxOrMQAnAQAGAAUJFxOrMQAnAQAuAAQKfyEAAwYACAn6G+s1AM4BAAYACAn6G+s1AM4BABgABQl3D3FGANsAAAAA.',
Xo='Xolither:BAABLgAECn8hAAMRAAcJfxFRKwBMAQARAAYJlBFRKwBMAQATAAQJ1hO3TgD9AAAAAA==.',
Xp='Xpireedk:BAACLgAFFH8TAAMkAAUJ3iUkAwCFAQAkAAUJ1CUkAwCFAQAPAAQJIR5XOQBQAQAuAAQKfxwAAyQACQnGJUMDAF8CACQACQnGJUMDAF8CAA8ABQnnHrJ1AJoBAAAA.',
Ya='Yamiyoru:BAAALgADCgYJBgABLgADCgcJBwAEAAAAAA==.',
Yo='Yorakk:BAAALgADCgIJAgAAAA==.Yorgo:BAAALgAECgQJCgAAAA==.',
Za='Zachdemon:BAAALgAECgEJAQABLgAECgkJNwAOAF4aAA==.Zariala:BAAALgAECgYJEQAAAA==.Zatana:BAAALgAECgUJBwAAAA==.',
Ze='Zephymoo:BAABLgAECn9JAAMeAAkJoyHVAgDQAgAeAAkJoyHVAgDQAgAXAAIJfAPbggAtAAAAAA==.Zeromus:BAAALgAECgkJCQAAAA==.Zerri:BAAALgADCgIJAgAAAA==.Zeyana:BAACLgAFFH8OAAMiAAQJDxt9AgA8AQAiAAQJDxt9AgA8AQAYAAEJVAH+DwBAAAAuAAQKfxkABCIACQnUGtwIAOcBACIACQnUGtwIAOcBABgABAmVBU1RAKUAAAYAAgk9AMX3AA8AAAAA.',
Zh='Zhengshi:BAABLgAECn8oAAIOAAkJhxNPFQDjAQAOAAkJhxNPFQDjAQAAAA==.',
Zn='Znot:BAAALgADCgEJAQAAAA==.',
Zo='Zoder:BAAALgAECgUJEgAAAA==.Zoose:BAABLgAECn8rAAMUAAkJzh5PCgCeAgAUAAkJzh5PCgCeAgAlAAIJURifQQCLAAAAAA==.Zoser:BAABLgAECn8mAAIcAAkJ7iVHAQBfAwAcAAkJ7iVHAQBfAwAAAA==.',
Zu='Zuckuss:BAAALgAECgQJAgAAAA==.',
['Ác']='Áceventura:BAAALgAECgUJBgAAAA==.',
['Æl']='Ælthan:BAAALgADCgUJBgAAAA==.',
['Ér']='Érubus:BAAALgAECgMJBQAAAA==.',
['ßu']='ßugs:BAABLgAECn8cAAIQAAgJohJOTACQAQAQAAgJohJOTACQAQAAAA==.',
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
