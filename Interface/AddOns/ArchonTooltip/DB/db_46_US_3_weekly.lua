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

local lookup = {'Mage-Frost','Paladin-Retribution','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Unknown-Unknown','Warrior-Fury','Warrior-Arms','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Protection','Hunter-BeastMastery','Warlock-Affliction','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Druid-Feral','Druid-Balance','DeathKnight-Unholy','Warlock-Destruction','Monk-Mistweaver','Priest-Holy','Druid-Restoration','Hunter-Marksmanship','Priest-Shadow','Monk-Brewmaster','Hunter-Survival','Monk-Windwalker','Evoker-Preservation','Priest-Discipline','Paladin-Holy','Shaman-Enhancement','Druid-Guardian','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abeblinkin:BAABLgAECn85AAIBAAkJoyDiDADiAgABAAkJoyDiDADiAgAAAA==.',
Ac='Accursed:BAAALgAECgEJAQAAAA==.',
Ad='Adcrusty:BAAALgAECgEJAQAAAA==.',
Ae='Aegrias:BAABLgAECn8hAAICAAkJER48JwCJAgACAAkJER48JwCJAgAAAA==.Aeledron:BAAALgADCgQJBQAAAA==.Aerodria:BAABLgAECn86AAICAAkJ0ROTNgDeAQACAAkJ0ROTNgDeAQAAAA==.',
Aj='Ajm:BAAALgAFFAIJAwAAAA==.',
Ak='Akarii:BAAALgAECgYJEAAAAA==.Akeno:BAABLgAECn8VAAIDAAgJQCNZAQAYAwADAAgJQCNZAQAYAwAAAA==.Akiaura:BAAALgAECgYJEgAAAA==.Akime:BAAALgAECgYJDwAAAA==.Akudama:BAABLgAECn8cAAMEAAgJihaCGQC6AQAEAAgJihaCGQC6AQAFAAIJqQkFNwBfAAABLgAFFAYJFQAGABYYAA==.',
Al='Alarm:BAAALgADCgEJAQABLgADCgcJCwAHAAAAAA==.Albince:BAAALgADCgIJAgAAAA==.Aldanil:BAAALgAECggJDwAAAA==.Alisae:BAAALgADCgMJAwAAAA==.Alma:BAAALgAECgUJBQAAAA==.Alye:BAAALgAECgcJEAAAAA==.',
Am='Amellis:BAAALgAECgUJBQAAAA==.',
An='Ananac:BAAALgADCgEJAQAAAA==.Andreasham:BAAALgADCgEJAQAAAA==.Andrius:BAAALgAECgEJAQAAAA==.Annisseda:BAACLgAFFH8RAAIIAAUJPRrhCwBZAQAIAAUJPRrhCwBZAQAuAAQKfysAAwgACQmKJCEDAAgDAAgACQmKJCEDAAgDAAkAAQl9IVJAAFsAAAAA.',
Ar='Arktos:BAAALgAECgYJCAAAAA==.Arrhythmia:BAAALgAECggJHAABLgAFFAYJFAAHAAAAAQ==.Articuno:BAAALgAECgQJCwAAAA==.',
As='Ashrak:BAAALgAECgQJBAAAAA==.Astaulis:BAAALgADCgUJCAAAAA==.',
Ax='Axelle:BAAALgAECgUJCwAAAA==.',
Az='Azzy:BAACLgAFFH8XAAIIAAUJHSGqDABUAQAIAAUJHSGqDABUAQAuAAQKfz0AAggACQnlJQgBAFcDAAgACQnlJQgBAFcDAAAA.',
Ba='Babyboomie:BAAALgAECgEJAQAAAA==.Bagagwa:BAAALgADCgcJCAAAAA==.Bal:BAABLgAECn8eAAMKAAgJ7RLKHQDRAQAKAAgJ7RLKHQDRAQALAAYJZg1TdgDgAAAAAA==.Balam:BAAALgADCgEJAQAAAA==.Balana:BAAALgAECgUJCAAAAA==.Bananski:BAABLgAECn8VAAMMAAYJUQ2vJADjAAAMAAUJIA+vJADjAAACAAYJXwYWqwDZAAAAAA==.Bandu:BAAALgADCgEJAgAAAA==.Barkeep:BAABLgAECn8aAAINAAkJaw+WOADMAQANAAkJaw+WOADMAQAAAA==.',
Be='Beeflocks:BAABLgAECn8bAAIOAAgJjhdSCADFAQAOAAgJjhdSCADFAQAAAA==.Bekarn:BAABLgAECn8YAAMPAAcJeAofUwA5AQAPAAcJeAofUwA5AQAQAAMJ7AhzegBaAAAAAA==.Bennafflock:BAAALgAECgUJCwAAAA==.Bergz:BAAALgAECgMJAgAAAA==.',
Bh='Bhp:BAAALgADCgMJAwABLgAECgMJAwAHAAAAAA==.',
Bi='Bigbleu:BAAALgAECgUJCQABLgAECggJJwARAHUdAA==.Bigdraco:BAAALgADCgQJBAAAAA==.Bigpapapump:BAAALgAECgEJAQAAAA==.Bigxthaplug:BAAALgAECgYJCQAAAA==.Bilboswagins:BAABLgAECn8UAAIIAAcJyxwLIwA9AgAIAAcJyxwLIwA9AgAAAA==.Billski:BAAALgAECgcJBwAAAA==.Billyspike:BAABLgAECn8YAAMSAAYJ0RrjDQDVAQASAAYJ0RrjDQDVAQATAAEJkhKsZQA3AAAAAA==.Billyspiked:BAAALgAECgIJAgABLgAECgYJGAASANEaAA==.Billyspikeev:BAAALgADCgYJBgABLgAECgYJGAASANEaAA==.Billyspikepd:BAAALgAECgUJBQABLgAECgYJGAASANEaAA==.Billyspikepr:BAAALgAECgUJCAABLgAECgYJGAASANEaAA==.',
Bl='Blammo:BAAALgADCgcJCQAAAA==.Blobcat:BAAALgAFFAEJAQAAAA==.Blobknight:BAAALgADCgEJAQAAAA==.Blobpally:BAACLgAFFH8NAAICAAQJ0RSqJAA7AQACAAQJ0RSqJAA7AQAuAAQKfyAAAgIABwm7IW0dALoCAAIABwm7IW0dALoCAAAA.Bloodhase:BAABLgAECn8YAAIUAAcJGhHfaQBIAQAUAAcJGhHfaQBIAQAAAA==.Bloodprince:BAAALgAECgMJAwAAAA==.Bluecard:BAACLgAFFH8QAAIGAAUJFhNfMwApAQAGAAUJFhNfMwApAQAuAAQKfywABAYACQl9IREIAOkCAAYACQl9IREIAOkCABUAAwnVGMg5AM0AAA4AAQkXIY0nAFMAAAAA.',
Bo='Bokunh:BAAALgAECgYJEgAAAA==.Boomywhoomy:BAAALgAECgIJBQAAAA==.Bothenheim:BAACLgAFFH8RAAICAAUJ2SNJDACWAQACAAUJ2SNJDACWAQAuAAQKfyYAAgIACQmAIggKAOQCAAIACQmAIggKAOQCAAAA.Bowdaddy:BAAALgADCgcJBwAAAA==.',
Br='Brewsimmons:BAABLgAFFH8LAAIWAAcJ7gvEBwDmAQAWAAcJ7gvEBwDmAQAAAA==.Brüisér:BAABLgAECn8iAAIMAAgJ+RB3EwA7AQAMAAgJ+RB3EwA7AQAAAA==.',
Ca='Callamdrake:BAAALgAECgEJAQAAAA==.Callamsvoid:BAAALgADCgIJAgAAAA==.Camazotz:BAAALgADCgkJCgAAAA==.Capie:BAAALgAECgkJDgAAAA==.Carathea:BAABLgAECn8iAAIXAAgJMSCCDACLAgAXAAgJMSCCDACLAgAAAA==.Carrotbear:BAAALgADCgQJBAAAAA==.Cassiopeià:BAAALgAECgMJAwAAAA==.Caylen:BAACLgAFFH8MAAIYAAUJ8RUCDwCOAQAYAAUJ8RUCDwCOAQAuAAQKfyAAAhgACAm3HkIRAK0CABgACAm3HkIRAK0CAAAA.Cayth:BAACLgAFFH8HAAIGAAMJ9hkCRwD0AAAGAAMJ9hkCRwD0AAAuAAQKfykAAwYACQkZIakFAGIDAAYACQkZIakFAGIDABUAAgkLAx9VAG8AAAAA.',
Ce='Cemie:BAAALgADCgcJBwAAAA==.Centralia:BAAALgADCgYJBwAAAA==.Centri:BAACLgAFFH8QAAIBAAcJSxjtCgDHAQABAAcJSxjtCgDHAQAuAAQKfyQAAgEACQlFJRYaAA8DAAEACQlFJRYaAA8DAAAA.Cerestus:BAAALgADCgMJAwAAAA==.',
Ch='Chadbear:BAAALgAECgcJDgAAAA==.Chadtones:BAAALgAECgQJBAAAAA==.Chimueloh:BAAALgADCgQJBAAAAA==.Chiron:BAAALgADCgIJAgAAAA==.Chowa:BAAALgAECgEJAQAAAA==.Chu:BAAALgAECgEJAQAAAA==.',
Cl='Cleverlev:BAAALgAECgYJEAABLgAFFAUJCAAWAO4WAA==.',
Co='Colivism:BAABLgAECn8kAAIBAAgJpRamXwCAAQABAAgJpRamXwCAAQAAAA==.Colívis:BAAALgAECgQJBQAAAA==.Commodorecdx:BAAALgADCgcJBwAAAA==.Cotali:BAAALgADCgUJBQABLgAECggJIgAXADEgAA==.',
Cr='Crackfiend:BAAALgADCgUJBwAAAA==.Crispi:BAAALgADCgYJBAAAAA==.Cruellev:BAAALgADCgkJEAABLgAFFAUJCAAWAO4WAA==.Crymbrulay:BAAALgAECgYJCAAAAA==.',
Cz='Czernobog:BAAALgAECgMJAwAAAA==.',
Da='Daedrenda:BAAALgAECgMJBAAAAA==.Daeland:BAABLgAECn8jAAIIAAgJSw72JAB/AQAIAAgJSw72JAB/AQAAAA==.',
De='Deathsgrace:BAAALgAECgkJCAAAAA==.Deathtank:BAAALgADCgkJCgAAAA==.Deathtolife:BAAALgAECgQJCAAAAA==.Decima:BAABLgAECn8hAAITAAgJMg4fJABOAQATAAgJMg4fJABOAQAAAA==.Degrance:BAAALgAECgUJBQAAAA==.Demeter:BAACLgAFFH8TAAINAAUJKiFxFQBVAQANAAUJKiFxFQBVAQAuAAQKfyEAAw0ACQlYIuASAKACAA0ACAk6HuASAKACABkABglxILUoAOQBAAAA.Demonpunter:BAAALgAECgYJDwAAAA==.Dewussi:BAACLgAFFH8TAAICAAQJnAn5LQAfAQACAAQJnAn5LQAfAQAuAAQKfyQAAwwABwnfHYENAO8BAAwABwk4GYENAO8BAAIABwlkG/tCALQBAAAA.',
Di='Dinoscarr:BAAALgAECgQJCQAAAA==.',
Dj='Djholy:BAAALgAECgcJDgAAAA==.',
Do='Dotsndash:BAAALgAECgUJBQAAAA==.',
Dp='Dpsshaman:BAAALgAECggJEgABLgAECgkJFQABAPcdAA==.',
Dr='Dreadingfate:BAAALgAECgkJDwAAAA==.Drscholar:BAAALgAECgEJAQAAAA==.Druidpwnz:BAAALgADCgMJAwAAAA==.',
Du='Dungorogue:BAAALgAFFAIJAgAAAA==.Dustln:BAAALgAECgEJAQAAAA==.',
Dy='Dyonne:BAAALgADCgEJAgAAAA==.',
['Dé']='Déwéy:BAAALgAECgIJAgABLgAFFAQJEwACAJwJAA==.',
El='Elbone:BAAALgADCgUJBQAAAA==.Elidia:BAAALgADCgcJBwAAAA==.Elinia:BAABLgAECn8xAAMXAAkJqxFwGAC/AQAXAAgJqRJwGAC/AQAaAAkJrgU4JwA9AQAAAA==.Elivoker:BAAALgAECgYJAwAAAA==.Elmdor:BAAALgAECgcJDQAAAA==.Elyndra:BAAALgAECgMJBAAAAA==.',
En='Enlag:BAAALgAECgMJAwAAAA==.',
Et='Etriganna:BAAALgAECgEJAQAAAA==.',
Ev='Evilwitch:BAAALgADCgEJAQAAAA==.Evistiah:BAAALgAECgEJAQAAAA==.',
Ex='Excentric:BAABLgAECn8ZAAICAAgJcx7dIwAvAgACAAgJcx7dIwAvAgABLgAFFAcJEAABAEsYAA==.Excerpt:BAAALgAECgMJAwABLgAFFAcJEAABAEsYAA==.',
Fa='Falloutman:BAAALgADCgYJBQAAAA==.Farëeya:BAAALgADCgcJDAAAAA==.Fayne:BAAALgADCgUJCgAAAA==.',
Fe='Fernsama:BAAALgAECgYJBgAAAA==.',
Fi='Fishton:BAAALgADCgUJCwAAAA==.',
Fl='Flauros:BAABLgAECn8XAAILAAcJ3w1hYwAOAQALAAcJ3w1hYwAOAQAAAA==.',
Fr='Fraternite:BAAALgAECgcJCgAAAA==.Froackeh:BAAALgAECggJBwAAAA==.Froackie:BAAALgAECgYJEAABLgAECggJBwAHAAAAAA==.Fruto:BAABLgAECn8sAAIbAAgJzhXbFwCsAQAbAAgJzhXbFwCsAQAAAA==.',
Ga='Garzislao:BAAALgAECgQJCAAAAA==.',
Gh='Ghostfox:BAAALgAECgMJAwAAAA==.',
Gi='Giterdonee:BAACLgAFFH8NAAIIAAUJhRpLEQA7AQAIAAUJhRpLEQA7AQAuAAQKfyEAAggACQn9IKEEAF8DAAgACQn9IKEEAF8DAAAA.',
Gl='Gleymoulleon:BAAALgAECgQJBwAAAA==.',
Go='Goblinbeans:BAACLgAFFH8LAAIPAAUJlQiPBQBzAQAPAAUJlQiPBQBzAQAuAAQKfxcAAg8ACAlLFqckAAMCAA8ACAlLFqckAAMCAAEuAAUUBwkLABYA7gsA.Goku:BAAALgAECgQJBAAAAA==.',
Gr='Greenbeans:BAAALgAECgUJCQABLgAFFAcJCwAWAO4LAA==.Grence:BAAALgAECgUJDAABLgAECgcJEwAHAAAAAA==.Grimreaper:BAABLgAECn8dAAMPAAcJNw3xPwBMAQAPAAcJNw3xPwBMAQAQAAQJPwLJewBVAAAAAA==.Groldin:BAAALgAECgQJBAAAAA==.Groshkar:BAAALgADCgcJCwAAAA==.Grumble:BAAALgAECgEJAQAAAA==.',
['Gõ']='Gõtchoo:BAAALgAECgQJDQAAAA==.',
Ha='Hairball:BAABLgAECn8XAAIcAAgJpxCqFAC2AQAcAAgJpxCqFAC2AQAAAA==.Hallona:BAAALgADCgMJAwAAAA==.Hammerthumb:BAAALgADCgEJAQABLgAECgkJIAASABgPAA==.',
Ho='Hotdoggin:BAAALgADCgYJDAAAAA==.',
Hy='Hyara:BAABLgAECn8rAAINAAkJghziDwC8AgANAAkJghziDwC8AgAAAA==.',
['Hì']='Hìm:BAAALgAECgMJBAAAAA==.',
Ib='Ibefarmin:BAAALgAECgEJAQAAAA==.',
Ic='Icecreammen:BAAALgADCgQJBAAAAA==.Icobal:BAAALgADCgYJCAAAAA==.',
Il='Illisa:BAAALgADCgMJAwAAAA==.',
Ir='Irongallo:BAAALgADCgEJAQAAAA==.',
Ja='Jabdis:BAAALgADCgEJAQAAAA==.Jacopo:BAAALgAECgYJDwAAAA==.',
Jo='Jocko:BAAALgAECgMJAwAAAA==.Jordi:BAABLgAECn8sAAINAAkJpR3VDgCTAgANAAkJpR3VDgCTAgAAAA==.',
Ju='Jutti:BAAALgAECgQJCQAAAA==.',
Ka='Kaellen:BAAALgADCgUJBQAAAA==.Kahnman:BAAALgADCgUJBQAAAA==.Kaka:BAAALgAECgcJEwAAAA==.Kalet:BAAALgAECgMJAwAAAA==.Kandinsky:BAAALgADCgIJAgAAAA==.Kanree:BAACLgAFFH8WAAIWAAUJpQdUFAAqAQAWAAUJpQdUFAAqAQAuAAQKfz0AAxYACQkiG0oLAJwCABYACQkiG0oLAJwCAB0AAQknB9F4ACwAAAAA.Kartiri:BAACLgAFFH8QAAMeAAUJzRzwDQBVAQAeAAQJLh3wDQBVAQAEAAMJvwqrOgCAAAAuAAQKfywABB4ACQmQHVoGAN4CAB4ACQmQHVoGAN4CAAQABQmYFeknAEwBAAUABQkPGM0lAPUAAAAA.Kawhi:BAAALgAFFAEJAQAAAA==.',
Ke='Kea:BAACLgAFFH8GAAIfAAMJ6CHsFgArAQAfAAMJ6CHsFgArAQAuAAQKfyYAAh8ACQmJJccAAL0DAB8ACQmJJccAAL0DAAAA.Keicelinis:BAAALgAECgYJDgAAAA==.Keratos:BAAALgADCggJCgAAAA==.',
Kh='Khran:BAAALgADCgIJAgAAAA==.',
Ki='Kickingfluff:BAAALgADCgIJAgAAAA==.Kimjoonsang:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.Kipz:BAAALgADCgQJBAABLgAECgIJAgAHAAAAAA==.Kittyboy:BAAALgADCgUJBQAAAA==.',
Ko='Kookykrook:BAAALgAECgEJAQAAAA==.Korxin:BAACLgAFFH8QAAINAAUJ6hyHEwBcAQANAAUJ6hyHEwBcAQAuAAQKfykAAg0ACQkpI+oEAD8DAA0ACQkpI+oEAD8DAAAA.',
Kr='Kreizikat:BAACLgAFFH8JAAIYAAQJrhTKGQAuAQAYAAQJrhTKGQAuAQAuAAQKfzIAAhgACAnIITQOAMgCABgACAnIITQOAMgCAAAA.Krinn:BAAALgAECgYJCQAAAA==.Krios:BAAALgADCgQJBAAAAA==.',
Ku='Kurquaan:BAAALgAECgcJEAAAAA==.',
Le='Leilar:BAAALgAECgIJAgAAAA==.Levitticus:BAABLgAECn8pAAIgAAgJixsSHgAmAgAgAAgJixsSHgAmAgABLgAFFAUJCAAWAO4WAA==.',
Li='Liale:BAAALgAECgMJBAAAAA==.Lidrel:BAAALgAECgYJBgAAAA==.',
Lo='Loinari:BAAALgAECgUJCQAAAA==.Lokano:BAAALgAECgQJBQAAAA==.',
Lu='Luaru:BAAALgAECgEJAQAAAA==.Ludmylha:BAAALgAECgYJCAAAAA==.Luisda:BAAALgADCgUJBQAAAA==.Lulak:BAAALgAECgMJBgAAAA==.Lull:BAABLgAECn8cAAIVAAgJgAw3DAAtAQAVAAgJgAw3DAAtAQAAAA==.Luthin:BAAALgADCgUJBgAAAA==.',
Ly='Lyadre:BAAALgAECgIJAgAAAA==.Lynai:BAAALgADCgIJAgAAAA==.Lyndis:BAAALgAECgQJBAAAAA==.',
Ma='Madness:BAAALgAECgMJAwAAAA==.Magejaf:BAAALgADCgcJDQABLgAECggJEgAHAAAAAA==.Magidragon:BAAALgAECgcJCwAAAA==.Magoraga:BAAALgADCgYJBgAAAA==.Mandrah:BAAALgADCgQJAgAAAA==.',
Md='Mdavis:BAAALgADCgkJCgAAAA==.',
Me='Melt:BAACLgAFFH8VAAIGAAYJFhi6DQBuAQAGAAYJFhi6DQBuAQAuAAQKfz0AAwYACQlxI5UGAP0CAAYACQlxI5UGAP0CABUABAmoEncsAAwBAAAA.Metons:BAAALgAECgQJBQAAAA==.',
Mi='Midei:BAAALgADCgkJFgAAAA==.Midriffluvr:BAAALgAECgQJBAAAAA==.Mikasa:BAAALgADCgEJAQAAAA==.Mike:BAAALgADCgcJCAAAAA==.Mimosa:BAAALgADCgYJCgABLgAECgYJBgAHAAAAAA==.Misfitdk:BAAALgAECgEJAgAAAA==.Misfitmagi:BAAALgAECgEJAgAAAA==.Mistfox:BAAALgAECgUJBgAAAA==.',
Mo='Mobiouse:BAAALgADCgYJBgAAAA==.Mollieann:BAAALgAECgMJBQAAAA==.Mommon:BAAALgAECgYJCAAAAA==.Moonraisin:BAAALgAECgMJAwAAAA==.Morrighan:BAAALgADCgQJBQAAAA==.',
Mu='Mukdron:BAAALgADCgIJAgAAAA==.',
Na='Nadra:BAAALgAECggJEwAAAA==.Naminé:BAAALgADCgMJAwABLgAECgcJIwALAEweAA==.Nattyrav:BAACLgAFFH8JAAIhAAQJnR0sAwBSAQAhAAQJnR0sAwBSAQAuAAQKfygAAyEACQkWH8ADAO4CACEACQlnHsADAO4CABAABgm+GyAlAGkBAAAA.Nawari:BAAALgAECgIJAwAAAA==.',
Ne='Nemonk:BAABLgAECn86AAMdAAkJ9BXIEQDlAQAdAAkJ9BXIEQDlAQAWAAEJUAMifQAcAAAAAA==.Neryssa:BAACLgAFFH8RAAIGAAYJhByeEACgAQAGAAYJhByeEACgAQAuAAQKfzQAAwYACQnWJIAkAIECAAYACAlWJIAkAIECABUABAkpJPUYAIMBAAAA.',
Ni='Nipz:BAAALgAECgEJAQABLgAECgIJAgAHAAAAAA==.',
No='Nocter:BAABLgAECn8eAAQGAAkJwhxnNwAuAgAGAAcJZhxnNwAuAgAOAAUJUiCTCwCBAQAVAAMJ9g0APgC8AAAAAA==.Noqtir:BAAALgAECgUJBQAAAA==.Not:BAAALgADCgcJAgAAAA==.Noyoo:BAAALgADCgEJAQAAAA==.',
Ny='Nymura:BAAALgAECgYJDwAAAA==.',
['Nä']='Näesthra:BAABLgAECn8kAAIXAAgJdBgsEgAEAgAXAAgJdBgsEgAEAgAAAA==.',
Oa='Oakhugger:BAABLgAECn8gAAMSAAkJGA8BCgDBAQASAAkJGA8BCgDBAQATAAEJAACwfwAAAAAAAA==.',
Ob='Obelisk:BAAALgADCgYJBgAAAA==.Obelix:BAAALgAECgEJAQAAAA==.',
Ok='Okarun:BAABLgAECn8jAAILAAcJTB6OPgCBAQALAAcJTB6OPgCBAQAAAA==.',
Ol='Oldeone:BAAALgAECgMJBAAAAA==.',
Om='Omgega:BAABLgAECn8uAAICAAgJtxmrPwC/AQACAAgJtxmrPwC/AQAAAA==.',
On='Onimeek:BAABLgAECn81AAMKAAkJ0x1EBgCGAgAKAAkJ0x1EBgCGAgALAAIJPAmTzQA7AAAAAA==.',
Or='Oryn:BAAALgAFFAEJAgAAAA==.Oryx:BAAALgAECgEJAgAAAA==.',
Pa='Pallywahwah:BAAALgADCgQJBAAAAA==.Palpitations:BAAALgAECgYJDgAAAA==.Paper:BAAALgAFFAYJFAAAAQ==.Paudetunia:BAAALgADCgIJAgAAAA==.',
Pe='Peacefullev:BAACLgAFFH8IAAIWAAUJ7hbLDQCAAQAWAAUJ7hbLDQCAAQAuAAQKfxwAAxYACAnOHrMIALECABYACAnOHrMIALECAB0AAgnbD65SAGsAAAAA.Penance:BAAALgAECgEJAQAAAA==.Pestilence:BAAALgAECggJDQAAAA==.',
Ph='Phantomthief:BAAALgAECgUJAQAAAA==.Phyllus:BAAALgAECgUJBQAAAA==.',
Pi='Pipeleto:BAABLgAECn8cAAIIAAgJdRnhEQAcAgAIAAgJdRnhEQAcAgAAAA==.',
Po='Poochimus:BAAALgAECggJEwAAAA==.Pookong:BAAALgAECgUJCQAAAA==.Poonslayerxx:BAAALgADCgMJAwAAAA==.',
Pr='Previdius:BAAALgAECgYJCwAAAA==.Priestpwnz:BAAALgAECgYJDgAAAA==.Protomán:BAAALgAECgYJDAAAAA==.Proximity:BAAALgADCgQJBQABLgADCgcJCwAHAAAAAA==.',
Ps='Psychmike:BAAALgAECgEJAQAAAA==.',
Pw='Pwrbttm:BAAALgAECgEJAQABLgAFFAMJBgANAKoJAA==.',
['Pé']='Pépega:BAAALgAECgIJAgAAAA==.',
Ra='Rafferno:BAAALgAECgEJAQAAAA==.',
Re='Redeemedlev:BAACLgAFFH8OAAIfAAQJ7hNzFgAvAQAfAAQJ7hNzFgAvAQAuAAQKfzQAAh8ACQmGIVoDADADAB8ACQmGIVoDADADAAEuAAUUBQkIABYA7hYA.Reds:BAAALgAECgEJAQAAAA==.Relax:BAABLgAECn8YAAILAAYJOh6fNwCbAQALAAYJOh6fNwCbAQAAAA==.',
Rh='Rhesand:BAAALgAECgcJEQAAAA==.Rhëa:BAAALgAECgIJAgAAAA==.',
Ri='Riellus:BAAALgADCgkJFQAAAA==.Riiu:BAABLgAECn8cAAIdAAYJHR19GQCVAQAdAAYJHR19GQCVAQAAAA==.Rindra:BAAALgADCgEJAQAAAA==.Rinkelle:BAAALgAECgYJBgAAAA==.Rixin:BAECLgAFFH8QAAIUAAQJsB09JwBkAQAUAAQJsB09JwBkAQAuAAQKfzsAAhQACQknJloCAF0DABQACQknJloCAF0DAAAA.Rixryu:BAEALgADCgkJFgABLgAFFAQJEAAUALAdAA==.',
Ro='Roaka:BAAALgADCggJCAAAAA==.Rokom:BAACLgAFFH8JAAIIAAMJLBhWHgDvAAAIAAMJLBhWHgDvAAAuAAQKfyQAAggACAnXH28TALICAAgACAnXH28TALICAAAA.Rollster:BAAALgAECgMJAwAAAA==.Rotandroll:BAAALgADCgYJBgABLgAECgEJAQAHAAAAAA==.',
Ru='Ruwey:BAAALgADCgYJCAAAAA==.',
Ry='Ryuk:BAAALgAECgYJEQAAAA==.',
['Rè']='Rèzurrect:BAAALgAECgUJDQAAAA==.',
Sa='Saaratharaxx:BAAALgAECgUJDAAAAA==.Sackhunter:BAABLgAECn8aAAILAAcJEQ5oaQD/AAALAAcJEQ5oaQD/AAAAAA==.Saero:BAAALgAECgcJEwAAAA==.Saluuknir:BAABLgAECn8sAAMEAAgJog0iKABLAQAEAAgJWA0iKABLAQAFAAYJaAeKIwAMAQAAAA==.Saphh:BAAALgAECgcJDgABLgAFFAEJAQAHAAAAAA==.Satrath:BAAALgAFFAIJAwAAAA==.',
Se='Seekae:BAAALgAECgEJAQAAAA==.Sepidasprite:BAAALgADCgEJAQAAAA==.',
Sh='Shaddoot:BAAALgAECgYJBwAAAA==.Shadowbladez:BAAALgAECgEJAQAAAA==.Sheepforfree:BAAALgAECgIJAgAAAA==.Shinishamy:BAAALgADCgEJAQAAAA==.Shirokuma:BAABLgAFFH8RAAIiAAUJuiCFAgCNAQAiAAUJuiCFAgCNAQABLgAECggJFQADAEAjAA==.',
Si='Siera:BAAALgADCgYJBgABLgAECgQJBQAHAAAAAA==.Sigrun:BAAALgADCgIJAgAAAA==.Sipz:BAAALgAECgIJAgAAAA==.',
Sk='Skinbone:BAAALgADCgQJBAAAAA==.',
Sl='Slaty:BAAALgAECgIJAgAAAA==.Slingshotz:BAABLgAECn8ZAAIcAAkJ4RmrBgCWAgAcAAkJ4RmrBgCWAgAAAA==.Slootbag:BAAALgAECggJDgAAAA==.',
Sn='Sneakylev:BAAALgADCgEJAQABLgAFFAUJCAAWAO4WAA==.Sneux:BAAALgADCgcJDQAAAA==.Snuuze:BAACLgAFFH8MAAICAAMJHCG4LQAgAQACAAMJHCG4LQAgAQAuAAQKfyYAAgIACAmWInwjADACAAIACAmWInwjADACAAAA.Snuuzi:BAAALgAECgYJCgABLgAFFAMJDAACABwhAA==.',
So='Soberloki:BAAALgAECgIJAgAAAA==.Solari:BAABLgAECn8XAAMKAAgJVxgVHwDGAQAKAAcJlhUVHwDGAQALAAcJvBVqQAB5AQAAAA==.Solix:BAAALgAECgEJAQAAAA==.Solvi:BAAALgAECgYJDgAAAA==.Sophispapa:BAABLgAECn80AAICAAcJRCArKQAUAgACAAcJRCArKQAUAgAAAA==.Souprage:BAAALgAECgcJDQAAAA==.',
Sp='Spellmaden:BAAALgADCgMJBgABLgAECgcJIwALAEweAA==.Spywar:BAAALgAECgYJBgABLgAECggJHwAQACkXAA==.',
St='Starlighter:BAABLgAECn8nAAMaAAgJ9gqLJQBIAQAaAAgJ9gqLJQBIAQAXAAYJGQWkOADMAAAAAA==.',
Su='Sunshinë:BAAALgAECgEJAQAAAA==.Supressor:BAAALgADCgQJCAABLgAECgIJAgAHAAAAAA==.',
Sy='Sylvester:BAAALgADCgIJAgAAAA==.',
['Sé']='Sérolis:BAAALgADCgEJAQAAAA==.',
Ta='Taehausx:BAACLgAFFH8oAAIbAAgJFiIoAADbAgAbAAgJFiIoAADbAgAuAAQKfzAAAxsACQlSJB8GACUDABsACQlSJB8GACUDAB0AAgk5HvBBAKoAAAAA.Tarmo:BAAALgADCgYJFgAAAA==.',
Te='Telesto:BAAALgAECgIJAgABLgAFFAUJEQACANkjAA==.Templeton:BAAALgADCgMJAwAAAA==.Tenath:BAABLgAECn8WAAIKAAcJthErGgBGAQAKAAcJthErGgBGAQAAAA==.',
Th='Thaleon:BAAALgAECgcJCwAAAA==.Tharella:BAAALgAECgMJAwAAAA==.Thauriel:BAAALgAECgIJAgAAAA==.Thrumple:BAAALgADCgYJCgAAAA==.',
Ti='Tinyterror:BAAALgADCgcJCwAAAA==.Titania:BAABLgAECn8eAAIgAAkJTAa9QAB1AQAgAAkJTAa9QAB1AQAAAA==.',
Tr='Trollztoll:BAAALgAECgIJAgAAAA==.',
Tu='Tuulk:BAAALgADCgIJAgAAAA==.',
Ty='Typical:BAAALgADCgcJCwAAAA==.',
Ug='Uggoorc:BAACLgAFFH8GAAINAAMJqgmgOgDcAAANAAMJqgmgOgDcAAAuAAQKfxgAAg0ABwmTHAdCAIQBAA0ABwmTHAdCAIQBAAAA.',
Un='Unholylord:BAAALgAECggJCAABLgAFFAUJFAAaAGgjAA==.',
Va='Vacalocà:BAAALgAECgYJDAAAAA==.Valerian:BAAALgAECgUJBQAAAA==.Van:BAAALgADCgcJFAAAAA==.Vaultkey:BAAALgADCgIJAwAAAA==.',
Ve='Vegesha:BAAALgAECgEJAgAAAA==.Venin:BAAALgAECgYJBwAAAA==.Vessarind:BAAALgADCgEJAgAAAA==.',
Vi='Vitora:BAAALgAECgYJEQAAAA==.',
Vo='Voidkurn:BAAALgADCgYJCQAAAA==.Von:BAAALgADCgIJAgAAAA==.',
Vy='Vyse:BAAALgADCgYJBgAAAA==.',
Wa='Waally:BAAALgAECgcJEgAAAA==.Wahgwan:BAAALgAECgMJAwAAAA==.Waleran:BAAALgADCgIJAgAAAA==.Warriorbp:BAAALgADCgkJFwAAAA==.Wattz:BAAALgAECgYJBgAAAA==.',
We='Weebsora:BAAALgAECgQJBQAAAA==.',
Wo='Worldtree:BAAALgAECgMJBAAAAA==.',
Xa='Xaelthira:BAAALgAECgYJCgAAAA==.',
Xe='Xerath:BAAALgADCgYJCAAAAA==.',
Xi='Xips:BAAALgADCgMJAwABLgAECgIJAgAHAAAAAA==.',
Xo='Xoru:BAAALgADCgYJBgAAAA==.Xoruk:BAAALgADCgQJBAAAAA==.Xorun:BAAALgAECgEJAQAAAA==.',
Xz='Xzarrion:BAAALgADCgIJAgAAAA==.',
Ya='Yadhi:BAAALgAECgYJEQAAAA==.',
Ye='Yetkin:BAAALgAECgYJDQAAAA==.',
Yi='Yifftron:BAAALgAECgYJBgABLgAECggJGwANAAogAA==.Yimomo:BAABLgAECn8aAAMXAAgJNBYbLgCMAQAXAAgJNBYbLgCMAQAaAAcJtwfqNQDpAAAAAA==.',
Yo='Yoshira:BAAALgAECgMJAwABLgAECgQJBQAHAAAAAA==.',
Za='Zalconn:BAACLgAFFH8GAAMjAAMJiB98EgA2AQAjAAMJ3B58EgA2AQAkAAIJDRfLBgCuAAAuAAQKfycAAyMACAnRJToDAGwDACMACAmFJToDAGwDACQAAQneJrMSAHIAAAAA.Zarrona:BAABLgAECn8YAAIjAAcJkRqfEgC8AQAjAAcJkRqfEgC8AQABLgAECgcJIwALAEweAA==.Zayah:BAAALgAECgYJDwAAAA==.',
Zi='Zivanka:BAAALgADCgQJBAABLgAECgcJDgAHAAAAAA==.',
Zn='Znasty:BAABLgAECn8cAAIjAAYJaSXVDQD6AQAjAAYJaSXVDQD6AQAAAA==.',
Zo='Zombaman:BAAALgADCgMJAwAAAA==.',
Zy='Zyrap:BAAALgAECgMJAwAAAA==.',
['Öw']='Öwö:BAAALgAECgEJAQAAAA==.',
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
