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

local lookup = {'Paladin-Retribution','Druid-Restoration','Unknown-Unknown','DeathKnight-Blood','DemonHunter-Devourer','Evoker-Devastation','Evoker-Preservation','Paladin-Holy','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','DeathKnight-Unholy','Hunter-BeastMastery','Priest-Discipline','Priest-Holy','Warrior-Fury','Druid-Guardian','Hunter-Survival','Druid-Balance','Evoker-Augmentation','Mage-Frost','Hunter-Marksmanship','Monk-Mistweaver','Warlock-Demonology','DemonHunter-Havoc','Monk-Windwalker','Warlock-Destruction','Warlock-Affliction','Shaman-Enhancement','Rogue-Subtlety','Priest-Shadow','DemonHunter-Vengeance','Warrior-Protection','DeathKnight-Frost','Druid-Feral','Warrior-Arms',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abhanfnahwa:BAAALgADCgUJBQAAAA==.Abort:BAABLgAECn8YAAIBAAcJtR0NNADoAQABAAcJtR0NNADoAQAAAA==.',
Ac='Acbabcaa:BAAALgADCgYJCgAAAA==.Acefighter:BAAALgADCgMJAwAAAA==.Aceon:BAABLgAECn8cAAIBAAgJXxZWQAC9AQABAAgJXxZWQAC9AQAAAA==.Aceonarcher:BAAALgADCgMJAwAAAA==.',
Ad='Adfectia:BAAALgAECggJEwAAAA==.',
Ae='Aelianna:BAABLgAECn8XAAICAAgJtBnvFgBIAgACAAgJtBnvFgBIAgAAAA==.Aelinjr:BAAALgAECgEJAQAAAA==.Aelsa:BAAALgADCgYJCgABLgAECgUJCwADAAAAAA==.Aelyt:BAAALgAECgMJBQAAAA==.Aesirkin:BAAALgAECgIJBAAAAA==.Aeth:BAABLgAECn8gAAIEAAkJayHcBQDeAgAEAAkJayHcBQDeAgAAAA==.Aethér:BAAALgAECgEJAQABLgAFFAYJGgACAP0YAA==.',
Ag='Agiel:BAAALgADCgYJBgAAAA==.Agilities:BAAALgADCgYJBgAAAA==.',
Ah='Ahsokä:BAAALgAECgQJBwAAAA==.',
Ak='Akuaku:BAAALgADCgEJAQAAAA==.',
Al='Alcool:BAAALgAECgIJAgAAAA==.Alderaan:BAAALgAECgMJAwAAAA==.Alexhya:BAAALgAECgEJAQAAAA==.Alexjones:BAAALgADCgUJBwAAAA==.Alganeth:BAAALgADCggJCAAAAA==.Aliand:BAAALgAECgIJAgAAAA==.Aliande:BAAALgADCgUJBQAAAA==.Alnethir:BAAALgAECgEJAQAAAA==.Aloray:BAAALgADCgcJCwAAAA==.Alordis:BAAALgADCgMJAwAAAA==.Alpharetta:BAAALgAECgcJBgAAAA==.Alsou:BAAALgAECgEJAQAAAA==.Alvarah:BAAALgADCgMJAwAAAA==.Alynas:BAABLgAECn8fAAICAAkJoA/iNwBvAQACAAkJoA/iNwBvAQAAAA==.Alysona:BAABLgAECn8TAAIFAAYJVxvORABqAQAFAAYJVxvORABqAQAAAA==.',
Am='Amahra:BAAALgAECgQJBwAAAA==.Amelio:BAAALgADCgIJAgAAAA==.Amewow:BAACLgAFFH8FAAIGAAIJJRqOBQCzAAAGAAIJJRqOBQCzAAAuAAQKfxQAAwYACAl3G9YFALQBAAYACAl3G9YFALQBAAcAAgkRDPApAFEAAAAA.',
An='Anadoria:BAAALgADCgYJBgAAAA==.Analferret:BAAALgAECgUJDwAAAA==.Anastæsia:BAAALgADCgYJBwABLgAECgMJAwADAAAAAA==.Anda:BAAALgAECgUJCAAAAA==.Anitabidet:BAAALgADCgcJBwAAAA==.',
Ap='Apepi:BAAALgADCgcJBwAAAA==.Apolion:BAAALgADCgQJBAAAAA==.Apoundofcake:BAAALgAECgEJAQAAAA==.Appauling:BAAALgADCgYJBgAAAA==.',
Ar='Arclore:BAABLgAECn8VAAQIAAYJAQ69SADCAAAIAAUJyAq9SADCAAABAAQJIwzuygCnAAAJAAEJYgGIRQARAAAAAA==.Argenor:BAAALgAECgUJCgAAAA==.Ariadni:BAAALgAECgYJEQAAAA==.Aricict:BAAALgAECgMJAwAAAA==.Arlý:BAAALgAECgMJBQAAAA==.Aruneza:BAABLgAECn8nAAIHAAgJzw7tDwCBAQAHAAgJzw7tDwCBAQAAAA==.',
As='Asajj:BAAALgAECgUJDgAAAA==.Asharie:BAAALgADCgEJAQAAAA==.Ashcatchm:BAAALgADCgMJAwABLgAECgcJEQADAAAAAA==.Ashergon:BAAALgAECgQJBAABLgAECggJFwAKAAckAA==.Asheriz:BAAALgAECgUJCQABLgAECggJFwAKAAckAA==.Asherous:BAABLgAECn8XAAMKAAgJByRWFwBbAgAKAAgJByRWFwBbAgALAAEJbgxShgA0AAAAAA==.Ashiashi:BAAALgAECgEJAQABLgAECgcJHgABAPYjAA==.Ashomá:BAAALgADCgcJCAAAAA==.Ashtroglide:BAAALgAECgUJBQABLgAECggJFwAKAAckAA==.Ashèr:BAAALgAECgcJDgABLgAECggJFwAKAAckAA==.Askara:BAAALgADCgcJBwAAAA==.Aszura:BAAALgADCgUJDwAAAA==.',
Au='Auntieshaman:BAAALgADCgEJAQAAAA==.Auranhis:BAAALgAECgEJAgAAAA==.Auriailas:BAAALgADCgcJCQAAAA==.Autoignition:BAAALgADCgMJAwAAAA==.',
Av='Avidel:BAAALgAECgcJEAAAAA==.Avryn:BAAALgAECgYJEwAAAA==.',
Ay='Ayilime:BAAALgAECgQJBQAAAA==.',
Ba='Badcompanytt:BAAALgADCgIJAgAAAA==.Balør:BAAALgAECgMJAwABLgAECggJJgAMAL8UAA==.',
Be='Beanvoid:BAAALgADCgYJBgAAAA==.Beardsaint:BAAALgADCgUJBQAAAA==.Beefini:BAAALgAECgMJAwABLgAECggJIAANADwlAA==.Beenah:BAABLgAECn8XAAIOAAYJIgYPfgDhAAAOAAYJIgYPfgDhAAAAAA==.Belethiel:BAAALgADCgEJAQAAAA==.Bellinopher:BAAALgADCggJCAABLgAECgcJIAAPAH8RAA==.Benafflock:BAAALgAECgYJBwAAAA==.Bence:BAAALgAECgMJBAAAAA==.Benefitheals:BAAALgAECgUJBwAAAA==.Benefitpally:BAAALgAECgQJBwAAAA==.Benefitsham:BAAALgADCgYJBgAAAA==.',
Bi='Bigbibble:BAABLgAECn8aAAIQAAgJ0hTEHwB9AQAQAAgJ0hTEHwB9AQAAAA==.Birdien:BAAALgAECgYJBgAAAA==.',
Bl='Blackrose:BAAALgADCgIJAgABLgAFFAIJBAADAAAAAA==.Blamson:BAAALgADCgYJCgAAAA==.Bloodrain:BAABLgAECn8UAAIRAAYJ8gxiPQD+AAARAAYJ8gxiPQD+AAAAAA==.',
Bo='Boomie:BAAALgAFFAcJBAAAAA==.Booptyboop:BAAALgAECgQJCwAAAA==.Booptydo:BAAALgADCgYJBgAAAA==.Boris:BAAALgAECgEJAQAAAA==.Bowhawk:BAABLgAECn8UAAIOAAUJmQ7gfQDhAAAOAAUJmQ7gfQDhAAAAAA==.Bozag:BAAALgADCgIJAgAAAA==.',
Br='Braiin:BAAALgAECgUJBgABLgAFFAYJGgACAP0YAA==.Brakken:BAAALgADCgQJBAAAAA==.Bravebolt:BAAALgAECgQJBAAAAA==.Brawll:BAAALgAECgEJAgAAAA==.Brazyn:BAAALgADCgYJBgAAAA==.Brevarda:BAABLgAECn8rAAMKAAgJOR6WEwBbAgAKAAgJOR6WEwBbAgALAAYJaA18PADpAAAAAA==.Brokenmind:BAAALgAECgQJBAABLgAECgUJEQADAAAAAA==.Brubble:BAAALgADCgMJAwAAAA==.Brugg:BAAALgADCgYJBgAAAA==.',
Bu='Bubbles:BAAALgADCgEJAQAAAA==.Bubblzmgee:BAABLgAECn8pAAIPAAgJSw+oGACzAQAPAAgJSw+oGACzAQAAAA==.Bushmommy:BAAALgAECgIJAgAAAA==.',
Ca='Cadence:BAAALgAECgEJAgAAAA==.Cadin:BAABLgAECn8VAAMKAAkJSxmPDQCvAgAKAAkJSxmPDQCvAgALAAcJYhdfLwCkAQAAAA==.Cakeman:BAAALgADCgEJAQAAAA==.Calehunter:BAAALgADCgEJAQAAAA==.Capnblood:BAAALgAECgEJAgAAAA==.Capone:BAAALgAECgUJCgAAAA==.Carahz:BAABLgAECn8YAAISAAYJYg/EHQDcAAASAAYJYg/EHQDcAAAAAA==.Carindria:BAAALgAECgEJAgAAAA==.Cattiebrie:BAAALgAECgEJAQAAAA==.Caylavana:BAABLgAECn8aAAMTAAgJURQ6GQCLAQATAAcJLBQ6GQCLAQAOAAIJCxF9rQBpAAAAAA==.',
Ce='Celaylria:BAAALgAECgYJDgAAAA==.',
Ch='Chabz:BAAALgAECgQJAwAAAA==.Chai:BAABLgAECn8kAAMUAAgJ7hr+EQD2AQAUAAgJ7hr+EQD2AQACAAYJ4hh8OQDAAQABLgAFFAUJFAAVAFEcAA==.Charmed:BAAALgAECgkJEgAAAA==.Charmíng:BAAALgAECgYJDAABLgAFFAMJBgAWAFkgAA==.Cheryll:BAAALgAECgUJBQAAAA==.Chunknörris:BAAALgADCggJCAAAAA==.',
Ci='Cint:BAAALgAECgQJDQAAAA==.',
Cl='Cloudedjade:BAABLgAECn8ZAAIJAAYJXgrpHwC9AAAJAAYJXgrpHwC9AAAAAA==.',
Co='Coleybear:BAAALgAECgYJEQAAAA==.Condewit:BAAALgAECgEJAQAAAA==.Copedk:BAABLgAECn8iAAIEAAgJXxpwCwACAgAEAAgJXxpwCwACAgAAAA==.Copedogg:BAAALgADCgcJDgAAAA==.Copemonkk:BAAALgADCgMJAwAAAA==.Copepriest:BAAALgADCgkJCQAAAA==.Corrode:BAAALgAECggJCQAAAA==.Covertm:BAAALgAECgcJEgAAAA==.Covertw:BAAALgADCgEJAQAAAA==.',
Cr='Craq:BAAALgAECgEJAQAAAA==.Crashedout:BAAALgADCgEJAgAAAA==.Crashknight:BAAALgAECgEJAQABLgAECgQJCwADAAAAAA==.Crew:BAAALgAECgUJCAAAAA==.Crims:BAABLgAECn8ZAAIHAAgJ6BY4CgDyAQAHAAgJ6BY4CgDyAQAAAA==.',
Cu='Culture:BAAALgAECgYJEAAAAA==.',
Cy='Cybeldin:BAABLgAECn8pAAIXAAgJNwqsDgAnAQAXAAgJNwqsDgAnAQAAAA==.Cyberdemonxd:BAAALgADCgUJBgABLgAECgkJGQANAA8QAA==.',
Da='Daadeedaa:BAACLgAFFH8KAAIWAAQJDxdbMgBSAQAWAAQJDxdbMgBSAQAuAAQKfzAAAhYACAkpJH4aAIECABYACAkpJH4aAIECAAAA.Daddysparey:BAABLgAECn8bAAIFAAYJuxLQXAAgAQAFAAYJuxLQXAAgAQAAAA==.Dagoba:BAAALgAECgMJAgAAAA==.Dakk:BAABLgAECn8uAAIWAAgJMheSRADLAQAWAAgJMheSRADLAQAAAA==.Dardeathicus:BAACLgAFFH8MAAINAAQJPR5hMwBMAQANAAQJPR5hMwBMAQAuAAQKfyAAAg0ACQnNIIkoAJgCAA0ACQnNIIkoAJgCAAAA.Darderyag:BAAALgAECggJEwAAAA==.Darek:BAAALgAECgYJEwAAAA==.Dariara:BAAALgAECgEJAQAAAA==.Darkbud:BAAALgADCggJEQAAAA==.Darkfeazer:BAAALgADCgEJAQAAAA==.Darkforge:BAAALgAECgYJBQAAAA==.Darkrife:BAAALgAECgEJAQAAAA==.Darmonkicus:BAAALgAFFAIJAgAAAA==.Dazzan:BAAALgADCgUJBQAAAA==.',
De='Deadlocks:BAAALgADCgEJAQAAAA==.Deathhold:BAAALgAECgYJBwAAAA==.Debilitation:BAAALgADCgIJAgAAAA==.Dedrys:BAAALgAECgEJAQAAAA==.Deklan:BAAALgAECgEJAwAAAA==.Delsid:BAAALgAECgMJAwAAAA==.Demonsteven:BAAALgADCgcJCgAAAA==.Dependabull:BAAALgADCgYJCQABLgADCgcJBwADAAAAAA==.Dernis:BAAALgAECgEJAQAAAA==.Deshaman:BAABLgAECn8bAAILAAgJ/A/BIgB5AQALAAgJ/A/BIgB5AQABLgAFFAQJEQAOAJYfAA==.Devilbeast:BAAALgAECgQJCgAAAA==.',
Dh='Dhargo:BAAALgADCgcJBwAAAA==.',
Di='Dirte:BAAALgADCgYJDQAAAA==.Dirty:BAABLgAECn8eAAILAAgJ5BOIJQDlAQALAAgJ5BOIJQDlAQAAAA==.',
Dk='Dkbygorm:BAAALgADCgQJBwAAAA==.',
Do='Dolfi:BAAALgADCggJDAAAAA==.Dorlesette:BAABLgAECn8kAAMYAAkJqgcTLwAtAQAYAAkJqgcTLwAtAQAMAAIJ7ALSbAA/AAAAAA==.',
Dr='Dravindil:BAAALgAECgkJBgAAAA==.Dreamlesnite:BAABLgAECn8eAAIZAAcJZAc0egAIAQAZAAcJZAc0egAIAQAAAA==.Dreidelman:BAAALgAECgIJAgAAAA==.Drkstar:BAAALgAECgYJDAAAAA==.',
Du='Dunthur:BAAALgADCgYJBgAAAA==.Duoda:BAAALgAFFAMJBAABLgAFFAYJEQAHAMgRAA==.Durto:BAAALgAECgEJAQABLgAECgQJCAADAAAAAA==.',
Dy='Dylora:BAABLgAECn8pAAIYAAgJExeIGADdAQAYAAgJExeIGADdAQAAAA==.',
['Dï']='Dïesel:BAAALgAECgIJAgAAAA==.',
['Dó']='Dólores:BAAALgADCgYJBgAAAA==.',
['Dö']='Dödskott:BAAALgADCgcJBwAAAA==.',
Ec='Eclipsa:BAAALgAECgcJBwAAAA==.',
Eg='Egregore:BAABLgAECn8SAAIFAAYJvA4QbQD2AAAFAAYJvA4QbQD2AAAAAA==.',
El='Elassha:BAAALgAECgEJAQAAAA==.Ellaria:BAABLgAECn8nAAMFAAgJiBV8OQCUAQAFAAgJKxN8OQCUAQAaAAYJVhjlJQCQAQAAAA==.Elyselyia:BAAALgAECgUJBQAAAA==.Elysindrall:BAABLgAECn8mAAIHAAgJHBYSCQAQAgAHAAgJHBYSCQAQAgAAAA==.',
Em='Emokins:BAABLgAECn8pAAILAAgJhSMEBwCtAgALAAgJhSMEBwCtAgAAAA==.',
En='Endesh:BAABLgAECn8pAAMVAAgJ6QjNMAAaAQAVAAgJ6QjNMAAaAQAGAAMJ7QWTGABPAAAAAA==.Enolah:BAAALgADCgMJAwAAAA==.',
Er='Eradica:BAAALgADCgYJDQAAAA==.Erubus:BAACLgAFFH8KAAQMAAMJ5R5/LQC3AAAMAAIJpB9/LQC3AAAYAAIJDxC/JQCHAAAbAAEJQwGZFAA9AAAuAAQKfxcABAwACQmFIEQWAFcCAAwACQmFIEQWAFcCABgAAgk2E/tWAHMAABsAAQm/Ds95ADcAAAAA.Eryss:BAABLgAECn8YAAIOAAYJkgg2egDqAAAOAAYJkgg2egDqAAAAAA==.',
Es='Escånor:BAAALgAECgYJBwAAAA==.Esmeraldita:BAAALgADCgYJDwAAAA==.',
Ev='Evercleâr:BAAALgADCgkJAgAAAA==.Evilblixz:BAAALgADCgYJAQAAAA==.Evoked:BAABLgAECn8YAAMHAAYJEwz/FwAGAQAHAAYJEwz/FwAGAQAGAAUJdAWIFgBiAAAAAA==.',
Ex='Excentric:BAAALgAECgYJCgABLgAFFAcJEAAWAEsYAA==.Expiraman:BAAALgADCgYJBgAAAA==.',
Fa='Faeliel:BAAALgADCgYJBgABLgAFFAUJDwARAH0YAA==.Faelýn:BAAALgAECgYJEAAAAA==.Faessa:BAAALgADCgIJAgAAAA==.Falcone:BAAALgAECgcJBwAAAA==.Fanden:BAAALgADCgYJCQAAAA==.Fartimer:BAAALgADCgYJBgABLgAECgkJGwACAG4VAA==.',
Fd='Fdk:BAAALgAECgEJAgAAAA==.',
Fe='Feathering:BAAALgAECgYJEgAAAA==.Fellariene:BAAALgADCgcJCAAAAA==.Fellraiser:BAAALgAECgQJBwAAAA==.Feoralaure:BAAALgADCgEJAQAAAA==.',
Fi='Figjam:BAAALgADCgkJCgAAAA==.',
Fl='Fluoria:BAAALgAECgQJDgAAAA==.Fláreon:BAABLgAECn8ZAAIIAAcJGhk9HQAsAgAIAAcJGhk9HQAsAgAAAA==.',
Fr='Fragarach:BAAALgAECgEJAQAAAA==.Frostynipie:BAAALgADCgMJAwAAAA==.Frutypebblz:BAABLgAECn8aAAIcAAYJ6ghoFQDAAAAcAAYJ6ghoFQDAAAAAAA==.',
Fu='Furrsure:BAAALgAECgEJAQAAAA==.Fuzznn:BAAALgAECgMJAwABLgABCgIJAgADAAAAAA==.',
['Fà']='Fàmous:BAABLgAECn8YAAMPAAkJ6RZFEQAGAgAPAAkJ/xJFEQAGAgAQAAIJvB4OYgCoAAAAAA==.',
Ga='Gainful:BAAALgAECgEJAQABLgAECgkJFAAZAD8SAA==.Galabris:BAABLgAECn8pAAIEAAgJiSJpBQCVAgAEAAgJiSJpBQCVAgAAAA==.Galen:BAAALgAECgEJAgAAAA==.',
Ge='Geranin:BAAALgADCgUJCAAAAA==.Gervire:BAAALgADCgcJCAAAAA==.',
Gh='Ghouldân:BAAALgADCgMJBQAAAA==.Ghoulmania:BAAALgAECgkJCwAAAA==.',
Gi='Gimglich:BAAALgADCgYJAQAAAA==.Gimligrimes:BAAALgADCgEJAQAAAA==.Ginx:BAAALgADCgMJBAAAAA==.Gitchusum:BAAALgAECgUJBgAAAA==.',
Gl='Glaedry:BAAALgAECgEJAwAAAA==.',
Go='Goose:BAABLgAECn8WAAIPAAgJKxMEIABwAQAPAAgJKxMEIABwAQAAAA==.Gorefang:BAAALgAECgEJAQAAAA==.Gormladin:BAABLgAECn8YAAIIAAYJIBkdLgBUAQAIAAYJIBkdLgBUAQAAAA==.',
Gr='Greenbahamut:BAAALgAECgEJAQAAAA==.Gregamesh:BAAALgADCgcJDgAAAA==.Grill:BAAALgAECgMJAwAAAA==.Grimsreaper:BAAALgADCgkJDgAAAA==.Grizzlypouch:BAAALgADCgYJBgAAAA==.Grouchy:BAAALgAECgEJAQAAAA==.',
Gu='Guillimus:BAAALgADCgcJBgAAAA==.Gultadorn:BAAALgADCgMJAwAAAA==.',
['Gï']='Gïzmö:BAAALgAECgYJEwAAAA==.',
Ha='Halfang:BAAALgADCgYJEQAAAA==.Handham:BAAALgAECgYJCgAAAA==.Hanroro:BAAALgADCgQJAwAAAA==.Hasheth:BAAALgAECgYJCQAAAA==.Havocfang:BAAALgADCgIJAQAAAA==.Hawkiing:BAAALgADCgQJBAAAAA==.Hazuki:BAAALgAECgMJAwAAAA==.',
He='Helouise:BAAALgADCgQJBAAAAA==.Herbalxur:BAAALgAECgQJCAAAAA==.',
Hi='Hibikase:BAAALgAECgYJBgAAAA==.Hildegarde:BAAALgAECgEJAQABLgAECgYJFAAFADceAA==.Hitpoints:BAAALgAECgUJEQAAAA==.',
Ho='Hobbikeen:BAABLgAECn8iAAMHAAgJ/hx0BACgAgAHAAgJ/hx0BACgAgAVAAgJqA5dJgBYAQAAAA==.Holyhope:BAABLgAECn8XAAIIAAcJmhPoKAB3AQAIAAcJmhPoKAB3AQAAAA==.Holymana:BAABLgAECn8eAAIBAAcJNRhmTQCVAQABAAcJNRhmTQCVAQAAAA==.Hoshea:BAAALgADCgMJAwAAAA==.Hottyoreo:BAAALgADCgYJCwAAAA==.Howcom:BAAALgADCgcJBwAAAA==.',
Hu='Huffingpaint:BAAALgAECgYJDgABLgAECgYJFAAFADceAA==.Hundrakor:BAAALgAECgcJDAAAAA==.Huntinghawk:BAAALgAECgEJAQABLgAECgUJFAAOAJkOAA==.Hutzil:BAABLgAECn8gAAMZAAcJhxydOgCwAQAZAAcJKBudOgCwAQAdAAMJWRmVGwCXAAAAAA==.',
['Hÿ']='Hÿpothermia:BAAALgAECgMJAwAAAA==.',
Il='Illidianna:BAABLgAECn8aAAMFAAgJuhfxLQDGAQAFAAgJuhfxLQDGAQAaAAIJixJiXABvAAAAAA==.',
Im='Imitlol:BAAALgAECgYJCQAAAA==.',
In='Inception:BAAALgADCgkJFAAAAA==.',
Ir='Irrefutable:BAAALgADCgQJBAAAAA==.',
It='Itchynyple:BAAALgADCggJCAAAAA==.',
Ja='Jackatak:BAAALgADCgMJAwAAAA==.Jacoblack:BAAALgADCgMJAwAAAA==.Jadin:BAAALgADCgEJAQAAAA==.Jaefury:BAABLgAECn8aAAIeAAgJsxtEBwD7AQAeAAgJsxtEBwD7AQAAAA==.Jakes:BAAALgAECgEJAQAAAA==.Jandinga:BAAALgAECgQJBAAAAA==.',
Ji='Jimadler:BAAALgADCgMJAwABLgAECgIJAgADAAAAAA==.Jimbi:BAAALgAFFAIJAgAAAA==.Jiminybilini:BAAALgAECgcJBQAAAA==.Jimmybull:BAAALgADCgEJAQAAAA==.Jinho:BAAALgAECgEJAQABLgAECgkJFQAfADchAA==.Jinrop:BAEALgADCgcJBwABLgAECgcJFgAcACMUAA==.',
Jo='Jobuu:BAAALgAECgEJAgAAAA==.Johnnypopoff:BAABLgAECn8iAAIWAAgJvhX6UACnAQAWAAgJvhX6UACnAQAAAA==.Johnwolf:BAAALgAECgQJCQAAAA==.Jojohunts:BAAALgAECgYJCgAAAA==.',
Jp='Jpðc:BAAALgAECgYJCgAAAA==.',
Ju='Juanjo:BAAALgADCgcJBwABLgAECgkJMwAWAA8eAA==.Junyubych:BAAALgAECgUJEAAAAA==.Justylln:BAAALgADCgMJAgAAAA==.Justzach:BAABLgAECn83AAIMAAkJWBq8CABxAgAMAAkJWBq8CABxAgAAAA==.',
['Jà']='Jàccuse:BAABLgAECn8UAAIYAAYJGBL8KwBBAQAYAAYJGBL8KwBBAQAAAA==.Jàrnsaxa:BAAALgADCgEJAQAAAA==.',
['Jò']='Jòhnnypopo:BAAALgAECgQJBAAAAA==.',
Ka='Kadywompus:BAAALgADCgcJBwAAAA==.Kaeladra:BAAALgADCgcJDgAAAA==.Kailm:BAAALgADCgIJAgABLgAFFAUJCwARAC8ZAA==.Kait:BAAALgAECgIJAgAAAA==.Kalida:BAAALgADCgQJBAAAAA==.Kalniel:BAAALgADCgUJBQAAAA==.Kassaalaa:BAAALgADCgYJBgAAAA==.Kasume:BAAALgAECgMJAwAAAA==.Kaylastrasza:BAAALgADCgMJAwAAAA==.Kazurend:BAACLgAFFH8SAAIgAAYJHyKcAwDZAQAgAAYJHyKcAwDZAQAuAAQKfxoAAiAACAnQI7wFADMDACAACAnQI7wFADMDAAAA.',
Ke='Kelavax:BAAALgAECgkJBQAAAA==.Keleira:BAABLgAECn8UAAIWAAYJGxfMdABRAQAWAAYJGxfMdABRAQAAAA==.Kelemvore:BAAALgADCgMJBgAAAA==.Kericcandere:BAAALgADCgIJAwAAAA==.Kerm:BAEALgAECgEJAgAAAA==.Keyaielenst:BAAALgADCgcJBwAAAA==.',
Kh='Khristina:BAAALgADCgkJDQAAAA==.',
Ki='Kiel:BAAALgAFFAMJAwABLgAFFAIJAgADAAAAAA==.Kindos:BAAALgADCgQJBwAAAA==.Kippo:BAEALgAECgEJAQABLgAFFAQJBwAWAIoFAA==.Kiramman:BAAALgAECgUJCwAAAA==.Kirsute:BAAALgADCgYJBgAAAA==.Kirxcy:BAAALgADCgUJCAAAAA==.Kithiri:BAAALgAECgQJDgAAAA==.',
Kn='Knarn:BAABLgAECn8hAAITAAgJtB7jDwDuAQATAAgJtB7jDwDuAQAAAA==.',
Ko='Koralie:BAACLgAFFH8aAAMOAAYJkxjWAACrAQAOAAUJUxzWAACrAQAXAAEJkAlxHwBRAAAuAAQKfx4AAw4ACAl/HW4bAGICAA4ACAl/HW4bAGICABcABQm+D6VcANAAAAAA.',
Kr='Krillaxx:BAAALgAECgcJDwAAAA==.Krimzin:BAAALgAECgcJCwABLgAFFAQJDAAOAHIbAA==.Krolg:BAAALgAECgQJCQAAAA==.Kromvar:BAAALgAECgQJBwAAAA==.',
Ku='Kungfused:BAAALgADCgUJCAABLgAECgIJBAADAAAAAA==.Kurisux:BAABLgAFFH8GAAINAAMJ8A8+aADlAAANAAMJ8A8+aADlAAAAAA==.',
Ky='Kyliekat:BAAALgAECgYJCQAAAA==.Kyndlynn:BAAALgAECgQJDwAAAA==.Kyriea:BAAALgAECgEJAQAAAA==.',
La='Lanceelot:BAAALgAECgIJAgAAAA==.Lanel:BAAALgAECgUJCQAAAA==.Lathelous:BAABLgAECn8hAAIJAAgJkyOeAgC0AgAJAAgJkyOeAgC0AgAAAA==.',
Ld='Ldt:BAAALgADCgMJAwAAAA==.',
Le='Leintheir:BAAALgAECgMJAwAAAA==.Leththol:BAAALgADCgkJJQAAAA==.Letyoudie:BAAALgAECgQJCwAAAA==.Levenza:BAAALgAECgcJEgAAAA==.',
Li='Licita:BAAALgAECgUJCgAAAA==.Lideina:BAABLgAECn8bAAINAAYJWxvDYgBZAQANAAYJWxvDYgBZAQAAAA==.Lielandra:BAAALgAECgcJCAAAAA==.Lightt:BAABLgAECn84AAMQAAgJexwfCwBpAgAQAAgJexwfCwBpAgAgAAUJNQEQVQBvAAAAAA==.Liightt:BAAALgAECgUJDwAAAA==.Lilnug:BAAALgAECgQJDAAAAA==.Lindsey:BAAALgADCgkJDQABLgAECgQJBQADAAAAAA==.Littlenyne:BAAALgAECgUJCAAAAA==.',
Ll='Llando:BAAALgADCgYJBgAAAA==.Llars:BAABLgAECn8hAAIKAAgJyRqXFwA4AgAKAAgJyRqXFwA4AgAAAA==.Lleonardo:BAAALgADCgEJAQAAAA==.',
Lo='Lockkjaw:BAAALgADCgEJAQAAAA==.Locknorris:BAAALgADCgUJBgAAAA==.Loghrif:BAAALgAECgQJBAABLgAECgUJBgADAAAAAA==.Loptear:BAAALgAECgEJAQAAAA==.Loryanna:BAAALgADCgUJCwAAAA==.Louie:BAAALgAECgMJBAAAAA==.Lovehandless:BAAALgADCgEJAQAAAA==.Lovespell:BAAALgADCgUJBQAAAA==.',
Lu='Lucavian:BAAALgAECgYJDgAAAA==.Lucavias:BAAALgAECgMJBQAAAA==.Luckydruidh:BAAALgAECgcJEgAAAA==.Luckyevoker:BAAALgADCgcJEgABLgAECgcJEgADAAAAAA==.Lurien:BAAALgAECggJDgAAAA==.Luxilejo:BAAALgADCgYJCwAAAA==.',
Ly='Lyfebane:BAABLgAECn8vAAMBAAkJQRfWIgA0AgABAAkJQRfWIgA0AgAIAAgJMxgWFwAEAgAAAA==.',
['Ló']='Lórien:BAAALgADCgEJAQAAAA==.',
['Lø']='Lørs:BAABLgAECn8lAAIWAAYJKxHujQAhAQAWAAYJKxHujQAhAQAAAA==.Lørz:BAAALgAECgQJBAAAAA==.',
Ma='Machorn:BAAALgADCgcJBwAAAA==.Magetree:BAAALgAECgYJCQABLgAFFAQJDAAJAJcZAA==.Mageyoucream:BAAALgAECgIJAgAAAA==.Magnai:BAAALgADCgcJBwAAAA==.Main:BAABLgAECn8wAAIBAAkJHAuaUACNAQABAAkJHAuaUACNAQAAAA==.Malagore:BAAALgAECgkJEQABLgAECggJFwAVALIVAA==.Malec:BAAALgADCggJCAAAAA==.Malicemech:BAAALgADCgcJBwAAAA==.Maliceone:BAAALgAECgYJEAAAAA==.Malicepaly:BAAALgAECgQJBAAAAA==.Manek:BAAALgADCgcJCAABLgAECggJLgAWADIXAA==.Mansmilk:BAAALgAECgQJBAAAAA==.Mattshamon:BAAALgADCgcJBwAAAA==.Max:BAABLgAECn8ZAAIZAAkJ3h42KgDzAQAZAAkJ3h42KgDzAQAAAA==.Mayé:BAAALgAECgYJBgAAAA==.',
Mb='Mbaku:BAAALgAECgYJCgABLgAECgkJLwAgADkeAA==.',
Me='Melechim:BAAALgADCgkJCQAAAA==.Melinoe:BAAALgAECgYJEwAAAA==.Merc:BAAALgAECgUJBQAAAA==.Merithrá:BAAALgAECgIJAgAAAA==.',
Mi='Micah:BAACLgAFFH8ZAAIHAAcJVRDGBgDcAQAHAAcJVRDGBgDcAQAuAAQKfxgAAwcACAnkGggOAFYCAAcACAnkGggOAFYCABUABQm/GpsyADUBAAAA.Milenad:BAAALgAECgIJAgAAAA==.Mirelia:BAAALgADCgMJAgAAAA==.Mishosuki:BAAALgAECgUJEAAAAA==.Misky:BAAALgADCgEJAQAAAA==.Misscleo:BAABLgAECn8mAAIWAAgJeBGSUwCgAQAWAAgJeBGSUwCgAQAAAA==.Mizzyboii:BAAALgADCgMJAwAAAA==.',
Mk='Mk:BAAALgAECggJDwAAAA==.',
Mn='Mnesarte:BAABLgAECn8XAAIBAAYJZRaGdAA5AQABAAYJZRaGdAA5AQAAAA==.',
Mo='Moi:BAABLgAFFH8IAAIVAAUJBhNOGgApAQAVAAUJBhNOGgApAQABLgAFFAQJDwAWAIsdAA==.Monkilha:BAAALgAECgcJEQAAAA==.Moonkist:BAABLgAECn8WAAMCAAYJKB/jHQAPAgACAAYJKB/jHQAPAgAUAAEJRAN6jQAhAAAAAA==.Moonsgrace:BAAALgADCggJCwAAAA==.Moose:BAABLgAECn80AAINAAgJXyMPGQBtAgANAAgJXyMPGQBtAgAAAA==.Morpheos:BAABLgAECn8bAAMCAAkJbhVAPABbAQACAAkJbhVAPABbAQAUAAQJhgcMRwCZAAAAAA==.Morroe:BAAALgADCgEJAQAAAA==.Moxci:BAAALgAECgQJBQAAAA==.',
Mu='Mudamudamuda:BAAALgADCgYJDQABLgAFFAUJDwARAH0YAA==.Muffintop:BAAALgADCgEJAQAAAA==.',
My='Mysticforest:BAAALgAECgQJBAAAAA==.',
Na='Naedise:BAAALgADCgcJFgAAAA==.Narue:BAAALgAECgIJAgAAAA==.Natureswild:BAABLgAECn8gAAMUAAkJkhiUIQDwAQAUAAgJ4xeUIQDwAQACAAMJawrZuQBSAAAAAA==.Navariis:BAAALgAECgQJBgAAAA==.Navillus:BAAALgAECgMJBgABLgAFFAYJGgAHAMQQAA==.',
Ne='Necrophyliac:BAAALgAECgYJCwAAAA==.Nelrehim:BAAALgADCgQJBgAAAA==.Nephy:BAAALgAECgQJBAAAAA==.Nephyrium:BAAALgADCgUJBQAAAA==.Nephz:BAAALgAECgYJBgAAAA==.Nephzz:BAAALgAECgQJAwAAAA==.Nethery:BAAALgADCgcJCQAAAA==.Nex:BAAALgAECgEJAQAAAA==.Nezrin:BAAALgAECgYJEAAAAA==.',
Ni='Nidon:BAAALgADCgUJBQAAAA==.Niixxi:BAAALgADCgUJBQAAAA==.',
Nm='Nmbrs:BAABLgAECn8cAAMgAAYJ4R/aGQCjAQAgAAYJ4R/aGQCjAQAPAAEJ7AK9XAApAAAAAA==.',
No='Noirheffer:BAACLgAFFH8MAAMJAAQJlxk4BAAEAQAJAAQJIRE4BAAEAQABAAMJ9hQ2PAD1AAAuAAQKfycAAwEACQnXHvcXANkCAAEACAlDIvcXANkCAAkABwkXFy4MAKwBAAAA.Noobishdad:BAAALgADCgEJAQAAAA==.Norio:BAAALgADCgcJBwAAAA==.',
Nu='Nulannatoo:BAAALgAECgUJBQAAAA==.Nuukeasaur:BAAALgADCgEJAQAAAA==.',
Ny='Nyadari:BAAALgAECgEJAQAAAA==.Nyphe:BAAALgAECgQJBAAAAA==.Nyrrhi:BAAALgAECgQJCAAAAA==.Nyxiro:BAAALgAECgUJBQAAAA==.',
Od='Odysseus:BAAALgADCgkJFgAAAA==.',
Ol='Olgann:BAAALgAECgYJCQAAAA==.Olguita:BAAALgAECgQJCQAAAA==.Olivertwìst:BAAALgADCgcJBwAAAA==.',
Om='Omgowned:BAAALgAECgYJBwABLgAECggJFgAZAJwTAA==.',
On='Onehothealer:BAABLgAECn8aAAIgAAkJIBbsGQAQAgAgAAkJIBbsGQAQAgAAAA==.',
Oo='Oorua:BAAALgADCgkJDwAAAA==.',
Op='Opheliastar:BAABLgAECn8sAAIgAAkJ5hN+EgDvAQAgAAkJ5hN+EgDvAQAAAA==.',
Pa='Pad:BAABLgAECn8XAAMZAAYJOAxxfAADAQAZAAUJOAxxfAADAQAcAAEJAAAzdQAwAAAAAA==.Pahket:BAAALgAECgQJBAAAAA==.Paintballerr:BAAALgADCgEJAQAAAA==.Paladerp:BAABLgAECn8vAAMIAAgJGA+XKQBzAQAIAAgJGA+XKQBzAQABAAYJARHAgwAcAQAAAA==.Pallyown:BAABLgAFFH8KAAIIAAIJayOeIADNAAAIAAIJayOeIADNAAAAAA==.Paprika:BAAALgADCgQJBgAAAA==.Pastorbedtym:BAABLgAECn8YAAIgAAgJeQ+lJgBBAQAgAAgJeQ+lJgBBAQAAAA==.Pat:BAAALgAECgMJAwAAAA==.Paulybricks:BAAALgAECgUJBgAAAA==.',
Pe='Pecan:BAAALgAECgcJDgABLgAFFAMJBgAWAFkgAA==.Pewpewbang:BAAALgADCgIJAgAAAA==.',
Ph='Pharla:BAAALgADCgkJEAAAAA==.Phett:BAAALgAECgYJBgAAAA==.',
Pi='Pichon:BAAALgADCgQJBAAAAA==.Pimmscup:BAAALgAECgEJAQAAAA==.Pin:BAAALgAECgcJBgABLgAFFAcJBAADAAAAAA==.Pirei:BAAALgADCgUJBQAAAA==.Pirozhki:BAAALgADCgYJBgAAAA==.',
Pl='Plagueborn:BAAALgAECgEJAQAAAA==.Plentar:BAAALgADCgMJBgAAAA==.',
Po='Popcorntea:BAAALgAECgEJAgAAAA==.Porgoon:BAAALgAECgQJBQAAAA==.',
Pr='Preserved:BAAALgADCgIJAgAAAA==.Prizzma:BAAALgADCgUJBQAAAA==.',
Ps='Psaul:BAAALgAECgYJCwAAAA==.',
Py='Pyramys:BAAALgADCgYJBgAAAA==.',
Qe='Qedeshah:BAAALgAECggJCAAAAA==.Qesem:BAAALgADCgUJBQAAAA==.',
Qu='Qualaribou:BAAALgADCgQJBAAAAA==.',
Ra='Raal:BAAALgADCgkJHgAAAA==.Raenostra:BAAALgAECgUJEAAAAA==.Raenya:BAAALgAECgYJBgAAAA==.Ragefather:BAAALgADCgEJAQAAAA==.Rageye:BAAALgADCgcJBwAAAA==.Rainydaze:BAAALgAECggJEAAAAA==.Ramcharger:BAABLgAECn8WAAMhAAgJfRNtCACWAQAhAAgJfRNtCACWAQAaAAYJoAzEOwARAQAAAA==.Ranen:BAABLgAECn8fAAIbAAkJ3h3aBwCEAgAbAAkJ3h3aBwCEAgAAAA==.Rashun:BAAALgAECggJEQAAAA==.',
Re='Reanatilax:BAAALgADCgIJAgABLgAECgcJIAAPAH8RAA==.Redcinnabar:BAAALgAECgQJDQAAAA==.Rehtilox:BAAALgADCgMJAwABLgAECgcJIAAPAH8RAA==.Reilly:BAAALgADCggJFQAAAA==.Rev:BAAALgAECgQJBAAAAA==.Rexxy:BAAALgAECgYJCgAAAA==.',
Ri='Riju:BAAALgAECgcJDgAAAA==.Rikashae:BAAALgAECgEJAQAAAA==.Rillan:BAAALgADCgMJAwAAAA==.Rinzler:BAAALgAECgIJBAAAAA==.Rissa:BAAALgADCgYJBgAAAA==.',
Rn='Rng:BAAALgAECgQJCwAAAA==.',
Ro='Roachcentral:BAAALgADCgUJBgAAAA==.Roachcity:BAAALgADCgUJBQAAAA==.Rockalock:BAAALgADCgYJBgAAAA==.Roleon:BAAALgADCggJCAAAAA==.Rollforpi:BAAALgAECgIJAgABLgAFFAYJGgACAP0YAA==.Ropebunnyana:BAACLgAFFH8JAAIYAAQJRhYcFAAtAQAYAAQJRhYcFAAtAQAuAAQKfysAAhgACQlEIIgDADkDABgACQlEIIgDADkDAAAA.Rowkani:BAAALgADCgkJCQAAAA==.',
Ru='Ruki:BAABLgAECn8UAAMFAAYJNx4/QgBzAQAFAAYJIhs/QgBzAQAaAAIJ7B8zMACiAAAAAA==.',
Ry='Ryand:BAAALgAECgUJCQABLgAFFAQJCgAfAJAWAA==.',
Sa='Sacra:BAAALgAECgEJAQAAAA==.Salarcyn:BAAALgAECgUJDAAAAA==.Saltydk:BAAALgAFFAQJBAAAAA==.Samiracy:BAABLgAECn8pAAIcAAgJZhixBADeAQAcAAgJZhixBADeAQAAAA==.Sannrin:BAAALgAECgYJDAAAAA==.Santhrin:BAAALgADCgcJBwAAAA==.Sapprot:BAAALgADCgcJCQAAAA==.Sarkress:BAAALgADCgkJCQAAAA==.',
Se='Seagal:BAAALgADCgEJAgAAAA==.Senbatorii:BAAALgAECgYJEwAAAA==.Seredala:BAAALgADCgUJCwAAAA==.Sethrow:BAABLgAECn8WAAMZAAgJnBNlPQCnAQAZAAcJnBNlPQCnAQAcAAEJAABMPgAAAAAAAA==.Severa:BAAALgADCgIJAgAAAA==.',
Sh='Shaladora:BAAALgADCgYJBgAAAA==.Shalia:BAAALgADCgMJAwABLgADCgMJBgADAAAAAA==.Sharas:BAAALgAECgQJBQAAAA==.Shawarma:BAAALgAECgYJCwAAAA==.Sheltatha:BAAALgAECgEJAQAAAA==.Shengari:BAABLgAECn8hAAIQAAgJbBLxHwB8AQAQAAgJbBLxHwB8AQAAAA==.Shotcallà:BAAALgADCgIJAgAAAA==.Shuna:BAAALgAECgUJDAAAAA==.Shyly:BAABLgAECn8VAAIgAAgJRRyfDgAfAgAgAAgJRRyfDgAfAgAAAA==.Shâbs:BAAALgAECgkJAgAAAA==.',
Si='Sikkly:BAAALgADCgcJEQAAAA==.Siley:BAABLgAECn9QAAINAAkJjRXOMgDtAQANAAkJjRXOMgDtAQAAAA==.Sin:BAAALgAECgcJCAAAAA==.Siphon:BAAALgADCgYJBgAAAA==.',
Sk='Skarletfaith:BAAALgAECgYJEQAAAA==.',
Sl='Sloanya:BAABLgAECn85AAMYAAkJXR5tBQD7AgAYAAkJXR5tBQD7AgAbAAYJKxqmJQCqAQAAAA==.',
Sn='Snarffie:BAAALgAECgYJCgAAAA==.',
So='Solanar:BAAALgADCgUJBQAAAA==.Somedruid:BAABLgAECn8kAAIUAAgJWSOWBwCWAgAUAAgJWSOWBwCWAgAAAA==.',
Sp='Spiarmf:BAAALgADCgUJBQAAAA==.Spicynes:BAAALgADCgQJBwAAAA==.Spicyness:BAAALgAECgIJAgAAAA==.Spiderdk:BAAALgAECgUJCAABLgAFFAQJEQAOAJYfAA==.Spidermonk:BAAALgADCgcJDgABLgAFFAQJEQAOAJYfAA==.Spëcter:BAAALgAECgUJBQABLgAECggJEgADAAAAAA==.Spëcthyr:BAAALgAECggJEgAAAA==.',
Sq='Squishypoo:BAAALgAECgMJBgAAAA==.',
St='Stache:BAAALgAECgEJAQAAAA==.Stoneyfoam:BAAALgAECgYJBgAAAA==.Stormrider:BAAALgADCgkJCQAAAA==.',
Su='Sugrace:BAAALgAECgYJBgAAAA==.Superdemonzz:BAACLgAFFH8MAAIFAAQJshapIQBCAQAFAAQJshapIQBCAQAuAAQKfyUAAwUACAm4Ho4VAFYCAAUACAm4Ho4VAFYCACEAAwkJDjAcAGcAAAAA.Superevokerz:BAAALgADCgcJDgABLgAFFAQJDAAFALIWAA==.Superlockz:BAAALgADCgkJCQABLgAFFAQJDAAFALIWAA==.Superpallyz:BAACLgAFFH8JAAIIAAMJVxVoHQDmAAAIAAMJVxVoHQDmAAAuAAQKfy4AAwgABwnOHqIUAB0CAAgABwnOHqIUAB0CAAkABQkhEV8fAMIAAAEuAAUUBAkMAAUAshYA.Supershamanz:BAAALgAECgYJCgABLgAFFAQJDAAFALIWAA==.Superspidey:BAAALgADCgIJAgAAAA==.Sushiroll:BAABLgAECn8XAAIbAAgJPx5aCwBCAgAbAAgJPx5aCwBCAgAAAA==.',
Sy='Sydnysweeney:BAAALgADCgMJAwAAAA==.Sylentslit:BAAALgADCggJGgAAAA==.Sylveslem:BAAALgAECgkJDAAAAA==.Syphon:BAAALgADCgMJAwAAAA==.',
['Sô']='Sôlmyr:BAAALgADCgIJAgAAAA==.',
Ta='Tacowarr:BAAALgADCgUJBQAAAA==.Taldazlian:BAAALgAECgMJBQAAAA==.Taliesin:BAAALgAECgMJAwAAAA==.Tallon:BAAALgAECgEJAQABLgAFFAQJDgAVAJMYAA==.Tancy:BAAALgAECgIJAgAAAA==.Tantalus:BAABLgAECn8UAAIOAAYJpw3sbAAKAQAOAAYJpw3sbAAKAQAAAA==.Tarogen:BAAALgADCgUJBQAAAA==.Tashaler:BAAALgADCgEJAQAAAA==.',
Te='Tealet:BAAALgADCgkJEQAAAA==.Tellinor:BAAALgAECgYJEgAAAA==.Temporal:BAAALgAECgEJAQAAAA==.Terrestra:BAAALgADCgMJAwAAAA==.Tervor:BAAALgADCgEJAQAAAA==.',
Th='Thanamoros:BAAALgAECgUJBgABLgAFFAMJBwAVAKcOAA==.Thassarian:BAAALgAECgQJBAABLgAECggJGgAhAJUcAA==.Thechosenone:BAAALgADCgIJAgAAAA==.Theroach:BAAALgAECgYJEQAAAA==.Throfin:BAAALgAECgUJCgAAAA==.Thundernight:BAAALgAECgcJAgAAAA==.',
Ti='Tiki:BAAALgAECgEJAQAAAA==.Tinc:BAAALgADCgEJAgAAAA==.Tinkerballa:BAAALgADCgUJBQAAAA==.Tinonova:BAAALgAECgEJAgAAAA==.Titsmgee:BAAALgAECgIJAgAAAA==.',
To='Toeren:BAACLgAFFH8RAAIOAAQJlh80EABpAQAOAAQJlh80EABpAQAuAAQKfyIAAg4ACAnCH6EVAIsCAA4ACAnCH6EVAIsCAAAA.Tomate:BAAALgADCgQJBAAAAA==.Toph:BAAALgAECgEJAQAAAA==.Tormented:BAAALgAECgYJEwAAAA==.Townsley:BAAALgAECgYJDQAAAA==.',
Tp='Tpain:BAAALgADCgIJAgAAAA==.',
Tr='Traitoros:BAAALgADCgYJBgAAAA==.Tralectra:BAAALgAECgcJDAAAAA==.Tranquilfist:BAAALgADCgQJBQABLgAECgYJEQADAAAAAA==.Treemonk:BAAALgADCgYJCgABLgAECgkJIAAUAJIYAA==.Trolvere:BAAALgAECgQJBwAAAA==.Trorim:BAAALgADCgYJBgAAAA==.Trïsh:BAAALgAECgMJAwABLgAECgUJBQADAAAAAA==.',
Tu='Tummy:BAAALgADCgcJEwAAAA==.Turtlesoup:BAAALgADCgYJBgAAAA==.',
Ty='Tygragon:BAAALgAECgUJDAAAAA==.Tyinorin:BAAALgAECgIJAQAAAA==.Tylea:BAAALgADCgkJCAAAAA==.',
Tz='Tzipporah:BAAALgAECgYJBwAAAA==.',
Ub='Ubee:BAABLgAECn8WAAIFAAgJQRFWQQB2AQAFAAgJQRFWQQB2AQAAAA==.',
Ul='Ultimakitty:BAAALgAECgYJEQAAAA==.',
Un='Unchanged:BAAALgADCgYJBgAAAA==.Unholymana:BAAALgADCgkJDgAAAA==.',
Va='Vaellin:BAAALgAECgEJAQAAAA==.Valanyr:BAAALgADCgEJAQAAAA==.Vantrix:BAAALgAECgEJAQABLgAFFAMJBwAVAKcOAA==.Varabo:BAAALgAECgcJEwAAAA==.Varolina:BAAALgADCgcJEQAAAA==.',
Ve='Vehemencê:BAAALgADCgEJAQAAAA==.Velements:BAAALgAECgMJAwABLgAECggJEAADAAAAAA==.Velemon:BAACLgAFFH8OAAIiAAQJNQw/DwDvAAAiAAQJNQw/DwDvAAAuAAQKfxgAAiIACAnuE/ERAOkBACIACAnuE/ERAOkBAAAA.Velisen:BAAALgAECgYJEwAAAA==.Velthala:BAAALgAECggJEAAAAA==.Velystiri:BAAALgADCgcJBgAAAA==.Venedictus:BAAALgADCgMJAwAAAA==.',
Vi='Viergryn:BAAALgADCgkJCQABLgAECgcJEQADAAAAAA==.Virasdruid:BAAALgAFFAIJAwAAAA==.Virusmonk:BAAALgAECgEJBAAAAA==.Vitner:BAABLgAECn8dAAMGAAkJwRS1BwB2AQAGAAYJMRm1BwB2AQAVAAgJfhBTNgD/AAAAAA==.',
Vo='Vosaleana:BAAALgADCgMJAwAAAA==.',
Vr='Vraak:BAACLgAFFH8aAAICAAYJ/RjgBwDvAQACAAYJ/RjgBwDvAQAuAAQKfycAAwIACAnhG7YrAAECAAIABwmBHbYrAAECABQABwmaIxYgAP4BAAAA.',
Vu='Vulcus:BAAALgADCgEJAwABLgAFFAYJGgACAP0YAA==.Vulpii:BAAALgADCgYJBQABLgAECgkJNQAcAG0lAA==.',
Vy='Vyndarien:BAAALgADCgIJAgAAAA==.Vyse:BAAALgADCgEJAQAAAA==.Vyttra:BAAALgADCgMJAwAAAA==.',
Wa='Walak:BAAALgADCgMJAwAAAA==.Warpulse:BAAALgADCgkJFQAAAA==.Warwizard:BAAALgADCgMJAwAAAA==.Watcherseye:BAAALgADCggJDwABLgADCgkJCQADAAAAAA==.Wavewhisper:BAAALgAECgEJAQAAAA==.Wayofthemist:BAAALgAECgcJBwAAAA==.',
Wc='Wcreator:BAAALgAECgYJEwAAAA==.',
We='Weapònized:BAAALgAECgYJEwAAAA==.Webaldes:BAAALgAECgEJAQAAAA==.',
Wh='Whitestain:BAABLgAECn8aAAIXAAcJ6QoMEwDpAAAXAAcJ6QoMEwDpAAAAAA==.',
Wi='Windyskie:BAAALgADCgEJAQAAAA==.Wingman:BAACLgAFFH8NAAIGAAQJvCZKAADNAQAGAAQJvCZKAADNAQAuAAQKfy4AAgYACAmXJpgAAIsDAAYACAmXJpgAAIsDAAAA.',
Wo='Womdalie:BAAALgADCgQJBgAAAA==.',
Wy='Wyckedpally:BAAALgADCgYJBgAAAA==.',
Xa='Xanthös:BAAALgAFFAEJAQABLgAFFAYJGgACAP0YAA==.',
Xe='Xemnastrasza:BAACLgAFFH8HAAQVAAMJpw5GKgDWAAAVAAMJpw5GKgDWAAAHAAIJaQOcHQBkAAAGAAEJ0QNnCwBLAAAuAAQKfxYABBUACAkdFMQhALEBABUACAnSEcQhALEBAAYABAmmCPEtAKsAAAcAAQlrBYZLACsAAAAA.Xenonne:BAACLgAFFH8MAAIFAAQJFxMjJwAwAQAFAAQJFxMjJwAwAQAuAAQKfyEAAwUACAkJHKUtAMcBAAUACAkJHKUtAMcBABoABQl3D3FGANsAAAAA.',
Xo='Xolither:BAABLgAECn8gAAMPAAcJfxGvIwBSAQAPAAYJlBGvIwBSAQAQAAQJ1hO3TgD9AAAAAA==.',
Xp='Xpireedk:BAACLgAFFH8RAAMjAAQJ3iU1AQCjAQAjAAQJ1CU1AQCjAQANAAQJIR4eKQBgAQAuAAQKfxwAAyMACQnGJUMDAF8CACMACQnGJUMDAF8CAA0ABQnnHrJ1AJoBAAAA.',
Yo='Yorakk:BAAALgADCgIJAgAAAA==.Yorgo:BAAALgAECgQJBgAAAA==.',
Za='Zariala:BAAALgAECgUJCgAAAA==.Zatana:BAAALgAECgUJBQAAAA==.',
Ze='Zephymoo:BAABLgAECn83AAMkAAkJ/x6jAgC3AgAkAAkJ/x6jAgC3AgAUAAIJfAPbggAtAAAAAA==.Zeromus:BAAALgAECgkJCQAAAA==.Zerri:BAAALgADCgIJAgAAAA==.Zeyana:BAACLgAFFH8GAAMhAAMJahy2AwDwAAAhAAMJahy2AwDwAAAaAAEJVAH+DwBAAAAuAAQKfxkABCEACQnUGtwIAOcBACEACQnUGtwIAOcBABoABAmVBU1RAKUAAAUAAgk9AMX3AA8AAAEuAAUUBAkKAA4AshMA.',
Zh='Zhengshi:BAABLgAECn8mAAIMAAgJvxSSFwCuAQAMAAgJvxSSFwCuAQAAAA==.',
Zn='Znot:BAAALgADCgEJAQAAAA==.',
Zo='Zoder:BAAALgAECgUJEgAAAA==.Zoose:BAABLgAECn8pAAMRAAgJuiBbCwBqAgARAAgJuiBbCwBqAgAlAAIJURjuNACOAAAAAA==.Zoser:BAABLgAECn8fAAIbAAgJ9CW6AwDrAgAbAAgJ9CW6AwDrAgAAAA==.',
['Æl']='Ælthan:BAAALgADCgUJBgAAAA==.',
['Ér']='Érubus:BAAALgAECgMJBQAAAA==.',
['ßu']='ßugs:BAABLgAECn8cAAIOAAgJohJDPQCWAQAOAAgJohJDPQCWAQAAAA==.',
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
