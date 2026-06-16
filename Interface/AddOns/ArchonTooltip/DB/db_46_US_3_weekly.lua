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

local lookup = {'Mage-Frost','Paladin-Retribution','Warrior-Arms','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Unknown-Unknown','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Protection','Hunter-BeastMastery','Monk-Brewmaster','Warlock-Affliction','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Druid-Feral','Druid-Balance','DeathKnight-Unholy','Warlock-Destruction','Monk-Mistweaver','Priest-Holy','Druid-Restoration','Mage-Arcane','Hunter-Marksmanship','Hunter-Survival','Rogue-Subtlety','Priest-Shadow','Monk-Windwalker','Evoker-Preservation','Priest-Discipline','Druid-Guardian','Paladin-Holy','Rogue-Outlaw','Shaman-Enhancement','DeathKnight-Frost','DeathKnight-Blood','Mage-Fire',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abeblinkin:BAABLgAECn9BAAIBAAkJhyFCFQDXAgABAAkJhyFCFQDXAgAAAA==.',
Ac='Accursed:BAAALgAECgEJAQAAAA==.',
Ad='Adcrusty:BAAALgAECgEJAQAAAA==.',
Ae='Aegrias:BAABLgAECn8hAAICAAkJEx48JwCJAgACAAkJEx48JwCJAgAAAA==.Aeledron:BAAALgADCgQJBQAAAA==.Aerodria:BAABLgAECn9cAAICAAkJkBZBNwAiAgACAAkJkBZBNwAiAgAAAA==.',
Aj='Ajm:BAABLgAFFH8LAAIDAAQJmxTRGAAYAQADAAQJmxTRGAAYAQAAAA==.',
Ak='Akarii:BAAALgAECgYJEAAAAA==.Akeno:BAABLgAECn8VAAIEAAgJQCNZAQAYAwAEAAgJQCNZAQAYAwAAAA==.Akiaura:BAAALgAECgYJEgAAAA==.Akime:BAAALgAECgYJDwAAAA==.Akudama:BAABLgAECn8tAAMFAAkJnxo2EABlAgAFAAkJnxo2EABlAgAGAAIJqQkFNwBfAAABLgAFFAgJJQAHACQZAA==.',
Al='Alarm:BAAALgADCgEJAQABLgADCgcJCwAIAAAAAA==.Albince:BAAALgADCgIJAgAAAA==.Aldanil:BAAALgAECggJDwAAAA==.Alisae:BAAALgADCgMJAwAAAA==.Alma:BAAALgAECgUJBQAAAA==.Alye:BAAALgAECgcJEAAAAA==.',
Am='Amellis:BAAALgAECgUJBgAAAA==.',
An='Ananac:BAAALgADCgEJAQAAAA==.Andreasham:BAAALgADCgEJAQAAAA==.Andrius:BAAALgAECgQJBQAAAA==.Annisseda:BAACLgAFFH8dAAMJAAYJXh+KCADOAQAJAAYJXh+KCADOAQADAAIJ2xiOPQBLAAAuAAQKfysAAwkACQmLJMUHAOECAAkACQmLJMUHAOECAAMAAQl9Ib1hAFkAAAAA.',
Ar='Aradril:BAAALgADCgcJCwAAAA==.Arktos:BAAALgAECgYJDQAAAA==.Arrhythmia:BAAALgAECgkJJQABLgAFFAgJIgAIAAAAAQ==.Articuno:BAAALgAECgYJEQAAAA==.',
As='Ashrak:BAAALgAECgQJBAAAAA==.Ashér:BAAALgAECgEJAQAAAA==.Astaulis:BAAALgADCgUJCAAAAA==.',
Ax='Axelle:BAAALgAECggJDwAAAA==.',
Az='Azzy:BAACLgAFFH8kAAIJAAgJ2hpBAgBuAgAJAAgJ2hpBAgBuAgAuAAQKfz4AAgkACQnlJXgCAJMDAAkACQnlJXgCAJMDAAAA.',
Ba='Babyboomie:BAAALgAECgUJBwAAAA==.Bagagwa:BAAALgADCgcJCAAAAA==.Bal:BAABLgAECn8kAAQKAAgJVhXKHQDRAQAKAAgJ8xLKHQDRAQALAAYJWQ/IkQD5AAAEAAIJBiGhKABeAAAAAA==.Balam:BAAALgADCgEJAQAAAA==.Balana:BAAALgAECgUJCAAAAA==.Bambudda:BAAALgADCgYJBgAAAA==.Bananski:BAABLgAECn8VAAMMAAYJUQ2vJADjAAAMAAUJIA+vJADjAAACAAYJXwbW8ADGAAAAAA==.Bandu:BAAALgADCgEJAgAAAA==.Barkeep:BAABLgAECn8aAAINAAkJaw+WOADMAQANAAkJaw+WOADMAQAAAA==.Bassoon:BAAALgAECgMJAwABLgAFFAIJBQAOAE4RAA==.',
Be='Beeflocks:BAABLgAECn8dAAIPAAkJBRjKCADUAQAPAAkJBRjKCADUAQAAAA==.Beefpile:BAAALgADCgUJBQAAAA==.Bekarn:BAABLgAECn8YAAMQAAcJeAofUwA5AQAQAAcJeAofUwA5AQARAAMJ7AhzegBaAAAAAA==.Bennafflock:BAAALgAECgUJCwAAAA==.Bergz:BAAALgAECgMJAgAAAA==.',
Bh='Bhp:BAAALgADCgMJAwABLgAECgMJAwAIAAAAAA==.',
Bi='Bigbleu:BAAALgAECgUJCQABLgAECggJJwASAHkdAA==.Bigdh:BAAALgAECgYJDgAAAA==.Bigdraco:BAAALgADCgQJBAAAAA==.Bigpapapump:BAAALgAECgEJAQAAAA==.Bigxthaplug:BAAALgAECgYJCQAAAA==.Bilboswagins:BAABLgAECn8UAAIJAAcJyxwLIwA9AgAJAAcJyxwLIwA9AgAAAA==.Billski:BAAALgAECgcJBwAAAA==.Billyspike:BAABLgAECn8YAAMTAAYJ0RrjDQDVAQATAAYJ0RrjDQDVAQAUAAEJkhJliAA2AAABLgAECgkJEwAIAAAAAA==.Billyspiked:BAAALgAECgIJAgABLgAECgkJEwAIAAAAAA==.Billyspikeev:BAAALgADCgYJBgABLgAECgkJEwAIAAAAAA==.Billyspikepd:BAAALgAECgkJEwAAAA==.Billyspikepr:BAAALgAECgUJCAABLgAECgkJEwAIAAAAAA==.Billyspikerg:BAAALgADCgIJAgABLgAECgkJEwAIAAAAAA==.',
Bl='Blammo:BAAALgADCgcJCQAAAA==.Blobcat:BAAALgAFFAEJAQAAAA==.Blobknight:BAAALgADCgEJAQAAAA==.Blobpally:BAACLgAFFH8NAAICAAQJ0RQaTAARAQACAAQJ0RQaTAARAQAuAAQKfyAAAgIABwm7IW0dALoCAAIABwm7IW0dALoCAAAA.Bloodhase:BAABLgAECn8YAAIVAAcJGxEClAA8AQAVAAcJGxEClAA8AQAAAA==.Bloodprince:BAAALgAECgMJAwAAAA==.Bluecard:BAACLgAFFH8cAAIHAAYJWB6iIADAAQAHAAYJWB6iIADAAQAuAAQKfywABAcACQl+IVUPANACAAcACQl+IVUPANACABYAAwnVGMg5AM0AAA8AAQkXIY0nAFMAAAAA.',
Bo='Bokunh:BAAALgAECgYJEgAAAA==.Boomywhoomy:BAAALgAECgIJBQAAAA==.Bothenheim:BAACLgAFFH8aAAMCAAYJcSNnEQDUAQACAAYJcSNnEQDUAQAMAAIJwAq1EgBgAAAuAAQKfyYAAgIACQmAIoAUAMUCAAIACQmAIoAUAMUCAAAA.Bowdaddy:BAAALgADCgcJBwAAAA==.',
Br='Brewsimmons:BAABLgAFFH8LAAIXAAcJ7wuqGACjAQAXAAcJ7wuqGACjAQAAAA==.Brüisér:BAACLgAFFH8FAAIMAAIJxwb2EwBVAAAMAAIJxwb2EwBVAAAuAAQKfyUAAgwACQluDz8YAFgBAAwACQluDz8YAFgBAAAA.',
Bu='Bublz:BAAALgAECgcJBwAAAA==.Bumpinuglies:BAAALgAECgEJAQAAAA==.',
Ca='Callamdrake:BAAALgAECgEJAQAAAA==.Callamsvoid:BAAALgAECgMJCAAAAA==.Camazotz:BAAALgADCgkJCgAAAA==.Capie:BAAALgAECgkJBwAAAA==.Carathea:BAABLgAECn8iAAIYAAgJMSCCDACLAgAYAAgJMSCCDACLAgAAAA==.Cardstock:BAAALgAECggJCAABLgAFFAgJIgAIAAAAAQ==.Carrotbear:BAAALgADCgQJBAAAAA==.Cassiopeià:BAAALgAECgMJAwAAAA==.Caylen:BAACLgAFFH8YAAIZAAYJJiH1CgA6AgAZAAYJJiH1CgA6AgAuAAQKfyAAAhkACAm3HkIRAK0CABkACAm3HkIRAK0CAAAA.Cayth:BAACLgAFFH8ZAAMHAAUJ1yDhNQBpAQAHAAUJwx3hNQBpAQAPAAEJJR+kFwBdAAAuAAQKfysAAwcACQnMIakFAGIDAAcACQnMIakFAGIDABYAAgkLAx9VAG8AAAAA.',
Ce='Cemie:BAAALgADCgcJBwAAAA==.Centralia:BAAALgADCgYJBwAAAA==.Centri:BAACLgAFFH8RAAIBAAcJVxntCgDHAQABAAcJVxntCgDHAQAuAAQKfyQAAgEACQlGJRYaAA8DAAEACQlGJRYaAA8DAAAA.Cerestus:BAAALgADCgMJAwAAAA==.',
Ch='Chadtones:BAAALgAECgQJBAAAAA==.Chimueloh:BAAALgADCgQJBAAAAA==.Chiron:BAAALgADCgIJAgAAAA==.Chowa:BAAALgAFFAMJAwAAAA==.Chrleone:BAAALgADCgMJAwAAAA==.Chu:BAAALgAECgEJAQAAAA==.',
Cl='Cleverlev:BAABLgAECn8WAAIaAAYJSxLdCQBGAQAaAAYJSxLdCQBGAQABLgAFFAcJFQAXAFQbAA==.',
Co='Colapse:BAAALgAECgEJAQAAAA==.Colivism:BAABLgAECn8kAAIBAAgJpRaleQDeAQABAAgJpRaleQDeAQAAAA==.Colívis:BAAALgAECgQJBQAAAA==.Commodorecdx:BAAALgADCgcJBwAAAA==.Cotali:BAAALgADCgUJBQABLgAECggJIgAYADEgAA==.',
Cr='Crackfiend:BAAALgADCgUJBwAAAA==.Crispi:BAAALgADCgYJBAAAAA==.Cruellev:BAAALgAECgUJCgABLgAFFAcJFQAXAFQbAA==.Crymbrulay:BAAALgAECgYJCAAAAA==.',
Cz='Czernobog:BAAALgAECgMJAwAAAA==.',
Da='Daedrenda:BAAALgAECgMJBAAAAA==.Daeland:BAABLgAECn8yAAIJAAkJ0hDBJADPAQAJAAkJ0hDBJADPAQAAAA==.',
De='Deathsgrace:BAAALgAECgkJCQAAAA==.Deathtank:BAAALgAECgYJCwAAAA==.Deathtolife:BAAALgAECgQJCAAAAA==.Decima:BAABLgAECn8iAAIUAAkJVg21KQCBAQAUAAkJVg21KQCBAQAAAA==.Degrance:BAAALgAECgUJBQAAAA==.Demeter:BAACLgAFFH8ZAAMNAAcJRhhULgBNAQANAAUJfCFULgBNAQAbAAIJ2gX/IQCXAAAuAAQKfyIABA0ACQlYIuASAKACAA0ACAk6HuASAKACABsABglxILUoAOQBABwAAQkoINFSAF8AAAAA.Demonpunter:BAAALgAFFAIJBAABLgAFFAUJGQAHAH4lAA==.Dewussi:BAACLgAFFH8TAAICAAQJnAm/WAD4AAACAAQJnAm/WAD4AAAuAAQKfyQAAwwABwniHYENAO8BAAwABwk4GYENAO8BAAIABwlnG9VnAJ0BAAAA.',
Di='Dinkltn:BAAALgADCgEJAQAAAA==.Dinoscarr:BAAALgAECgQJCQAAAA==.',
Dj='Djholy:BAAALgAECgcJDwAAAA==.',
Do='Dotmaxxing:BAAALgAFFAEJAQAAAA==.Dotsndash:BAAALgAECgUJBQAAAA==.',
Dp='Dpsshaman:BAABLgAECn8cAAIRAAkJ6x5hCgC2AgARAAkJ6x5hCgC2AgAAAA==.',
Dr='Drarmaku:BAAALgAECgIJAgAAAA==.Dreadingfate:BAAALgAECgkJEAAAAA==.Drscholar:BAAALgAECgIJAwAAAA==.Druidpwnz:BAAALgADCgMJAwAAAA==.',
Du='Duber:BAAALgAECgUJBgAAAA==.Dungorogue:BAABLgAECn8vAAIdAAgJcRCRHQCmAQAdAAgJcRCRHQCmAQAAAA==.Dustln:BAAALgAECgEJAQAAAA==.',
Dy='Dyonne:BAAALgADCgEJAgAAAA==.',
['Dé']='Déwéy:BAAALgAECgIJAgABLgAFFAQJEwACAJwJAA==.',
El='Elbone:BAAALgADCgUJBQAAAA==.Elidia:BAAALgADCgcJBwAAAA==.Elinia:BAABLgAECn8zAAMYAAkJqxEMIwCmAQAYAAgJqRIMIwCmAQAeAAkJgQYYNgA8AQAAAA==.Elivoker:BAAALgAECgYJAwAAAA==.Elmdor:BAAALgAECgcJDQAAAA==.Elyndra:BAAALgAFFAEJAQAAAA==.',
En='Eniacoc:BAAALgAECgkJCQAAAA==.Enlag:BAAALgAECgMJAwAAAA==.',
Et='Etriganna:BAAALgAECgEJAQAAAA==.',
Ev='Evilwitch:BAAALgADCgEJAQAAAA==.Evistiah:BAAALgAECgEJAQAAAA==.',
Ex='Excentric:BAABLgAECn8ZAAICAAgJdB7jOwASAgACAAgJdB7jOwASAgABLgAFFAcJEQABAFcZAA==.Excerpt:BAAALgAECgMJAwABLgAFFAcJEQABAFcZAA==.Exortus:BAAALgAFFAMJAwABLgAFFAYJGgACAHEjAA==.',
Fa='Falloutman:BAAALgAECgEJAQAAAA==.Farëeya:BAAALgADCgcJDAAAAA==.Fayne:BAAALgAECgUJCQAAAA==.',
Fe='Fellirane:BAAALgADCgUJBQAAAA==.Fernsama:BAAALgAECgYJCAAAAA==.',
Fi='Fishton:BAAALgADCgUJCwAAAA==.',
Fl='Flauros:BAABLgAECn8XAAILAAcJ4Q0AhQASAQALAAcJ4Q0AhQASAQAAAA==.',
Fr='Fraternite:BAAALgAECgkJDgAAAA==.Froackeh:BAAALgAECggJBwAAAA==.Froackie:BAAALgAECgYJEAABLgAECggJBwAIAAAAAA==.Fruto:BAACLgAFFH8FAAIOAAIJThFcRACKAAAOAAIJThFcRACKAAAuAAQKfzEAAg4ACQnLF6sTABECAA4ACQnLF6sTABECAAAA.',
Ga='Garzislao:BAAALgAECggJEAAAAA==.',
Gh='Ghostfox:BAAALgAECgMJAwAAAA==.',
Gi='Giterdonee:BAACLgAFFH8SAAIJAAcJfBdwCADQAQAJAAcJfBdwCADQAQAuAAQKfyEAAgkACQn9IKEEAF8DAAkACQn9IKEEAF8DAAAA.',
Gl='Gleymoulleon:BAAALgAECgQJBwAAAA==.',
Go='Goblinbeans:BAACLgAFFH8LAAIQAAUJlQiPBQBzAQAQAAUJlQiPBQBzAQAuAAQKfxcAAhAACAlLFqckAAMCABAACAlLFqckAAMCAAEuAAUUBwkLABcA7wsA.Goku:BAAALgAECgQJBAAAAA==.Gothmommy:BAAALgADCgIJAgAAAA==.',
Gr='Greenbeans:BAAALgAECgUJCQABLgAFFAcJCwAXAO8LAA==.Grence:BAAALgAECgUJDAABLgAECgcJEwAIAAAAAA==.Grimreaper:BAABLgAECn8lAAMQAAcJNw1AWwBGAQAQAAcJNw1AWwBGAQARAAQJPwLJewBVAAAAAA==.Griphöök:BAAALgAECgEJAgAAAA==.Groldin:BAAALgAECgQJBgAAAA==.Groshkar:BAAALgADCgcJCwAAAA==.Grumble:BAAALgAFFAEJAQAAAA==.',
['Gõ']='Gõtchoo:BAAALgAFFAMJAwAAAA==.',
Ha='Hairball:BAABLgAECn8eAAIcAAkJNBOsEgAUAgAcAAkJNBOsEgAUAgAAAA==.Hallona:BAAALgADCgMJAwAAAA==.Hammerthumb:BAAALgAECgUJDAABLgAECgkJJAATAFgQAA==.',
Ho='Hotdoggin:BAAALgADCgYJDAAAAA==.',
Hy='Hyara:BAABLgAECn8rAAINAAkJghziDwC8AgANAAkJghziDwC8AgAAAA==.',
['Hì']='Hìm:BAAALgAECgMJBAAAAA==.',
['Hù']='Hùñtarð:BAAALgADCgUJCwAAAA==.',
Ib='Ibefarmin:BAAALgAECgEJAQAAAA==.',
Ic='Icecreammen:BAAALgADCgQJBAAAAA==.Iceshadow:BAACLgAFFH8IAAIXAAMJLhQ2NQDJAAAXAAMJLhQ2NQDJAAAuAAQKfxUAAxcABwnjHg8VAGwCABcABwnjHg8VAGwCAB8AAgkrAse/AA8AAAAA.Icobal:BAAALgADCgYJCAAAAA==.',
Il='Illisa:BAAALgADCgMJAwAAAA==.',
Ir='Irongallo:BAAALgADCgEJAQAAAA==.',
Ja='Jabdis:BAAALgADCgEJAQAAAA==.Jabzulsor:BAAALgAECgEJAQAAAA==.Jacopo:BAABLgAECn8XAAIVAAgJtw5NgQBeAQAVAAgJtw5NgQBeAQAAAA==.',
Jo='Jocko:BAAALgAECgMJAwAAAA==.Jordi:BAABLgAECn80AAINAAkJpR2KGACOAgANAAkJpR2KGACOAgAAAA==.',
Ju='Jutti:BAAALgAECgQJCQAAAA==.',
Ka='Kaellen:BAAALgADCgUJBQAAAA==.Kahnman:BAAALgADCgUJBQAAAA==.Kaka:BAAALgAECgcJEwAAAA==.Kalet:BAAALgAECgMJAwAAAA==.Kaluaruun:BAAALgAECgEJAQAAAA==.Kandinsky:BAAALgADCgIJAgAAAA==.Kanree:BAACLgAFFH8mAAMXAAcJ1wkYHACCAQAXAAcJ1wkYHACCAQAfAAEJ5gbeQwA0AAAuAAQKfz4AAxcACQkiG0oLAJwCABcACQkiG0oLAJwCAB8AAQknB52mACgAAAAA.Kartiri:BAACLgAFFH8aAAMgAAYJ0BcQDQDIAQAgAAYJ0BcQDQDIAQAFAAQJPwz8RgCqAAAuAAQKfy8ABCAACQmRHVoGAN4CACAACQmRHVoGAN4CAAUABQnWFmUzAGMBAAYABQkPGM0lAPUAAAAA.Kawhi:BAAALgAFFAEJAQAAAA==.',
Ke='Kea:BAACLgAFFH8XAAMhAAUJ5iNhEQAAAgAhAAUJ5iNhEQAAAgAYAAIJjBi9IwCYAAAuAAQKfzgAAyEACQnzJfwAANMDACEACQnYJfwAANMDABgAAwlTI3s0AC4BAAAA.Keedoril:BAAALgADCgUJCgAAAA==.Keicelinis:BAABLgAECn8WAAILAAYJ9xIJfQAiAQALAAYJ9xIJfQAiAQAAAA==.Keratos:BAAALgAECgYJCQAAAA==.',
Kh='Khaalid:BAAALgAECgYJCgAAAA==.Khran:BAAALgADCgIJAgAAAA==.',
Ki='Kickingfluff:BAAALgADCgIJAgAAAA==.Kimjoonsang:BAAALgAECgEJAQABLgAECgEJAQAIAAAAAA==.Kipz:BAAALgAECgUJBQAAAA==.Kittyboy:BAAALgADCgUJBQAAAA==.',
Ko='Kookykrook:BAABLgAFFH8IAAIFAAQJrQ8HMgD4AAAFAAQJrQ8HMgD4AAAAAA==.Korxin:BAACLgAFFH8WAAINAAcJDxelDwDZAQANAAcJDxelDwDZAQAuAAQKfysAAg0ACQkpI+oEAD8DAA0ACQkpI+oEAD8DAAAA.',
Kr='Kreizikat:BAACLgAFFH8PAAIZAAUJDxOyIABKAQAZAAUJDxOyIABKAQAuAAQKfzIAAhkACAnJITQOAMgCABkACAnJITQOAMgCAAAA.Krinn:BAAALgAECgYJCQAAAA==.Krios:BAAALgADCgQJBAAAAA==.',
Ku='Kurquaan:BAABLgAECn8XAAMiAAgJVBRhFwCRAQAiAAgJVBRhFwCRAQAUAAQJEwyWVgDKAAAAAA==.',
La='Lanstan:BAAALgAECgQJBAAAAA==.',
Le='Leilar:BAAALgAECgIJAgAAAA==.Leron:BAAALgAECgYJCAAAAA==.Levitticus:BAABLgAECn85AAIjAAkJQh8kBgAqAwAjAAkJQh8kBgAqAwABLgAFFAcJFQAXAFQbAA==.',
Li='Liale:BAAALgAFFAEJAQAAAA==.Lideyn:BAAALgAECgEJAQAAAA==.Lidrel:BAAALgAECgYJBgAAAA==.Lightfury:BAAALgAECgMJAwABLgAECgYJCAAIAAAAAA==.',
Lo='Loinari:BAABLgAECn8WAAIUAAcJ8AQZUwC9AAAUAAcJ8AQZUwC9AAAAAA==.Lokano:BAAALgAECgQJBgAAAA==.',
Lu='Luaru:BAAALgAECgEJAQAAAA==.Ludmylha:BAAALgAFFAEJAQAAAA==.Luisda:BAAALgADCgUJBQAAAA==.Lulak:BAAALgAECgQJCQAAAA==.Lull:BAABLgAECn8tAAMWAAkJ6A4HCwCNAQAWAAkJ6A4HCwCNAQAHAAEJ4QI6XwEdAAAAAA==.Luthin:BAAALgADCgUJBgAAAA==.',
Ly='Lyadre:BAAALgAECgIJAgAAAA==.Lynai:BAAALgADCgIJAgAAAA==.Lyndis:BAAALgAECgQJBAAAAA==.',
Ma='Madness:BAAALgAECgMJAwAAAA==.Magejaf:BAAALgADCgcJDQABLgAECggJGgAPAMoVAA==.Magidragon:BAABLgAECn8UAAIBAAgJpgctqgAnAQABAAgJpgctqgAnAQAAAA==.Mandrah:BAAALgADCgQJBQAAAA==.Maybell:BAAALgAECgMJAwAAAA==.',
Md='Mdavis:BAAALgAECgYJBgAAAA==.',
Me='Melt:BAACLgAFFH8lAAMHAAgJJBn9FAAHAgAHAAcJQhn9FAAHAgAWAAEJchhRGwBbAAAuAAQKfz4AAwcACQl+I50JAAMDAAcACQl+I50JAAMDABYABAmoEncsAAwBAAAA.Mepha:BAAALgAFFAMJBAAAAA==.Metons:BAAALgAECggJDQAAAA==.',
Mi='Midei:BAAALgADCgkJFgAAAA==.Midriffluvr:BAAALgAECgQJBAAAAA==.Mikasa:BAAALgADCgEJAQAAAA==.Mike:BAAALgADCgcJCAAAAA==.Mimosa:BAAALgADCgYJCgABLgAECgYJCAAIAAAAAA==.Mirna:BAAALgAECgMJBgAAAA==.Misfitdk:BAAALgAECgEJBAAAAA==.Misfitdots:BAAALgAECgEJAQAAAA==.Misfitmagi:BAAALgAECgEJBAAAAA==.Misfitmonk:BAAALgAECgEJAgAAAA==.Misfittotem:BAAALgAECgEJAwAAAA==.Mistfox:BAAALgAECgYJDgAAAA==.',
Mo='Mobiouse:BAAALgADCgYJBgAAAA==.Mollieann:BAAALgAECgMJBQAAAA==.Mommon:BAAALgAECgYJCAAAAA==.Moonraisin:BAAALgAECgMJBQAAAA==.Morrighan:BAAALgADCgQJBQAAAA==.',
Mu='Mukdron:BAAALgADCgIJAgAAAA==.',
['Mâ']='Mâlus:BAAALgAECgUJCQAAAA==.',
Na='Nadra:BAAALgAFFAIJAgAAAA==.Naminé:BAAALgADCgMJAwABLgAECggJJgAkABAfAA==.Nattyrav:BAACLgAFFH8NAAIlAAQJJh7dBwA4AQAlAAQJJh7dBwA4AQAuAAQKfygAAyUACQkbH8ADAO4CACUACQlnHsADAO4CABEABgnHGxY3AFgBAAAA.Nawari:BAAALgAECgIJAwAAAA==.',
Ne='Nemonk:BAACLgAFFH8FAAIfAAMJARQ+IgDHAAAfAAMJARQ+IgDHAAAuAAQKf1IAAx8ACQm4G4YKAJgCAB8ACQm4G4YKAJgCABcAAQlQA1PPABwAAAAA.Neryssa:BAACLgAFFH8bAAQHAAgJhhvkDABHAgAHAAgJtRrkDABHAgAWAAEJYRVxHQBXAAAPAAEJpRwaGwBVAAAuAAQKfzoAAwcACQnYJI8IAA8DAAcACAlvJI8IAA8DABYABAkpJPUYAIMBAAAA.',
Ni='Nickjamez:BAAALgADCgYJBgAAAA==.Nipz:BAAALgAECgEJAQABLgAECgUJBQAIAAAAAA==.',
No='Nocter:BAABLgAECn8fAAQHAAkJwhxnNwAuAgAHAAcJZhxnNwAuAgAPAAUJUiCTCwCBAQAWAAMJ9g0APgC8AAAAAA==.Noqtir:BAAALgAECgUJCgAAAA==.Not:BAAALgADCgcJAgAAAA==.Noyoo:BAAALgADCgEJAQAAAA==.',
Nu='Nunca:BAAALgAECgEJAQAAAA==.',
Ny='Nymura:BAABLgAECn8fAAICAAcJ+AcFywD3AAACAAcJ+AcFywD3AAAAAA==.',
['Nä']='Näesthra:BAABLgAECn8kAAIYAAgJdBjkGwDkAQAYAAgJdBjkGwDkAQAAAA==.',
Oa='Oakhugger:BAABLgAECn8kAAMTAAkJWBCYDwC3AQATAAkJWBCYDwC3AQAUAAEJAADrrQAAAAAAAA==.',
Ob='Obelisk:BAAALgADCgYJBgAAAA==.Obelix:BAAALgAECgEJAQAAAA==.',
Ok='Okarun:BAABLgAECn8jAAILAAcJTB5nQQDuAQALAAcJTB5nQQDuAQABLgAECggJJgAkABAfAA==.',
Ol='Oldeone:BAAALgAECgMJBAAAAA==.Olyvivia:BAAALgAFFAIJAgAAAA==.',
Om='Omgega:BAABLgAECn9CAAICAAgJWhuENgAkAgACAAgJWhuENgAkAgAAAA==.',
On='Onichan:BAAALgAECgYJCQABLgAFFAcJFQARAI8ZAA==.Onimeek:BAABLgAECn9NAAMKAAkJEyA5BwC9AgAKAAkJEyA5BwC9AgALAAIJPAn7CQE7AAAAAA==.',
Or='Oryn:BAAALgAFFAEJAwABLgAFFAIJBgABACcVAA==.Oryx:BAAALgAECgEJAwAAAA==.',
Pa='Pallywahwah:BAAALgAFFAEJAQAAAA==.Palpitations:BAAALgAECgcJEAAAAA==.Paper:BAAALgAFFAgJIgAAAQ==.Paudetunia:BAAALgADCgIJAgAAAA==.',
Pe='Peacefullev:BAACLgAFFH8VAAMXAAcJVBtFCgBTAgAXAAcJVBtFCgBTAgAfAAEJKQtfQgA2AAAuAAQKfyYAAxcACAn8HlsOALUCABcACAn8HlsOALUCAB8ABwnDFe8lAIIBAAAA.Pelagius:BAAALgADCgYJBwAAAA==.Penance:BAAALgAECgEJAQAAAA==.Pestilence:BAAALgAECggJDQAAAA==.',
Ph='Phantomthief:BAAALgAECgcJAgAAAA==.Phyllus:BAAALgAFFAIJAgAAAA==.',
Pi='Pictureplane:BAAALgADCgEJAQAAAA==.Pipeleto:BAABLgAECn8cAAIJAAgJzhh+HgD5AQAJAAgJzhh+HgD5AQAAAA==.',
Po='Poochimus:BAABLgAECn8hAAIlAAkJsRN2CgAOAgAlAAkJsRN2CgAOAgAAAA==.Pookong:BAAALgAECgUJCQAAAA==.Poonslayerxx:BAAALgADCgMJAwAAAA==.',
Pr='Previdius:BAAALgAECggJEQAAAA==.Priestpwnz:BAAALgAECgYJDwAAAA==.Protomán:BAAALgAECggJEQAAAA==.Proximity:BAAALgADCgQJBQABLgADCgcJCwAIAAAAAA==.',
Ps='Psychmike:BAAALgAECgEJAQAAAA==.',
Pw='Pwrbttm:BAAALgAECgEJAQABLgAFFAQJEAANACMLAA==.',
['Pé']='Pépega:BAAALgAECgIJAgAAAA==.',
Ra='Rafferno:BAAALgAECgEJAgAAAA==.',
Re='Redeemedlev:BAACLgAFFH8YAAIhAAQJ8xnEIQA4AQAhAAQJ8xnEIQA4AQAuAAQKf0IAAiEACQnkIQUEAFkDACEACQnkIQUEAFkDAAEuAAUUBwkVABcAVBsA.Reds:BAAALgAECgEJAQAAAA==.Relax:BAABLgAECn8YAAILAAYJOh5MUACRAQALAAYJOh5MUACRAQAAAA==.',
Rh='Rhesand:BAABLgAECn8ZAAMFAAgJPATsVADYAAAFAAgJPATsVADYAAAGAAEJjwHXLAAEAAAAAA==.Rhëa:BAAALgAECgMJBAAAAA==.',
Ri='Riellus:BAAALgADCgkJFQAAAA==.Riiu:BAABLgAECn8cAAIfAAYJHR2DJgB+AQAfAAYJHR2DJgB+AQAAAA==.Rindra:BAAALgAECgUJBgAAAA==.Rinkelle:BAAALgAECgYJBgAAAA==.Rixin:BAECLgAFFH8ZAAIVAAgJsBn/DgBVAgAVAAgJsBn/DgBVAgAuAAQKfzwAAhUACQk3JrwFAEsDABUACQk3JrwFAEsDAAAA.Rixryu:BAEALgADCgkJFgABLgAFFAgJGQAVALAZAA==.',
Ro='Roaka:BAAALgADCggJCAAAAA==.Rokom:BAACLgAFFH8LAAIJAAMJ1xjiMgDfAAAJAAMJ1xjiMgDfAAAuAAQKfyQAAgkACAneH28TALICAAkACAneH28TALICAAAA.Rollster:BAAALgAECgQJBAAAAA==.Rotandroll:BAAALgADCgYJBgABLgAECgEJAQAIAAAAAA==.Roxis:BAAALgADCgUJBQAAAA==.',
Ru='Ruwey:BAAALgAECgEJAQAAAA==.',
Ry='Ryuk:BAAALgAECgYJEQAAAA==.',
['Rè']='Rèzurrect:BAAALgAECgUJDgAAAA==.',
Sa='Saaratharaxx:BAAALgAECgUJDAAAAA==.Sackhunter:BAABLgAECn8aAAILAAcJEg6DiQAJAQALAAcJEg6DiQAJAQAAAA==.Saero:BAABLgAECn8UAAIjAAcJbBkVKgC7AQAjAAcJbBkVKgC7AQAAAA==.Sake:BAAALgADCgMJAgABLgAFFAUJFQAfAGkTAA==.Saluuknir:BAACLgAFFH8FAAIFAAIJ7Qd+VABzAAAFAAIJ7Qd+VABzAAAuAAQKfzEAAwUACQmBD3UmAKsBAAUACQlBD3UmAKsBAAYABgloB4ojAAwBAAAA.Saphh:BAABLgAECn8cAAQmAAcJbRyNEwA/AQAVAAcJbBvMZgDBAQAmAAUJ/xmNEwA/AQAnAAQJQRU8NwC1AAABLgAFFAUJFgAmAPodAA==.Satrath:BAABLgAFFH8FAAIBAAIJdglVpwCHAAABAAIJdglVpwCHAAAAAA==.',
Se='Sedalin:BAAALgAECgEJAQAAAA==.Seekae:BAAALgAECgEJAQAAAA==.Sepidasprite:BAAALgADCgEJAQAAAA==.',
Sh='Shaddoot:BAAALgAECgYJBwAAAA==.Shadowbladez:BAAALgAECgEJAQAAAA==.Shadowxd:BAABLgAFFH8HAAIZAAMJOg3ERACcAAAZAAMJOg3ERACcAAAAAA==.Sharky:BAAALgAFFAIJAwABLgAFFAgJIwAoAIUcAA==.Shaulana:BAAALgADCgYJBgAAAA==.Sheepforfree:BAAALgAECgIJAgAAAA==.Shenwu:BAAALgAECgIJAgAAAA==.Shinishamy:BAAALgADCgEJAQAAAA==.Shirokuma:BAABLgAFFH8dAAIiAAYJyyINAwD0AQAiAAYJyyINAwD0AQABLgAECggJFQAEAEAjAA==.',
Si='Siera:BAAALgAECgEJAQABLgAECggJDQAIAAAAAA==.Sigrun:BAAALgADCgIJAgAAAA==.Sipz:BAAALgAECgIJAgABLgAECgUJBQAIAAAAAA==.',
Sk='Skinbone:BAAALgADCgQJBAAAAA==.Skyrius:BAABLgAFFH8GAAIVAAIJ2wkT8AB5AAAVAAIJ2wkT8AB5AAAAAA==.',
Sl='Slaty:BAAALgAECgIJAgAAAA==.Slingshotz:BAABLgAECn8ZAAIcAAkJ4RmrBgCWAgAcAAkJ4RmrBgCWAgAAAA==.Slootbag:BAAALgAECgkJDwAAAA==.',
Sn='Snax:BAAALgAECgIJAgAAAA==.Sneakylev:BAAALgAFFAIJAgABLgAFFAcJFQAXAFQbAA==.Sneux:BAAALgADCgcJDQAAAA==.Snuuze:BAACLgAFFH8PAAICAAMJJiGBSgATAQACAAMJJiGBSgATAQAuAAQKfyoAAgIACAkWI3AlAJECAAIACAkWI3AlAJECAAEuAAUUBgkLAAoAgRYA.Snuuzi:BAAALgAFFAEJAQABLgAFFAYJCwAKAIEWAA==.',
So='Soberloki:BAAALgAECgIJAgAAAA==.Sola:BAAALgAECgEJAQAAAA==.Solari:BAABLgAECn8cAAMLAAkJjRpRJQA1AgALAAkJ1BdRJQA1AgAKAAcJlhUVHwDGAQAAAA==.Sole:BAAALgAECgMJAwAAAA==.Solix:BAAALgAECgEJAQAAAA==.Solune:BAAALgAECgIJAgAAAA==.Solvi:BAAALgAECgYJDgAAAA==.Sophispapa:BAABLgAECn9CAAICAAcJ5SCMOwATAgACAAcJ5SCMOwATAgAAAA==.Souprage:BAABLgAECn8UAAIJAAgJvhDCMQCEAQAJAAgJvhDCMQCEAQAAAA==.',
Sp='Spellmaden:BAAALgADCgMJBgABLgAECggJJgAkABAfAA==.Spywar:BAAALgAECgYJCAABLgAECggJHwARACkXAA==.',
St='Starlighter:BAABLgAECn8qAAMeAAkJiAt/KgB9AQAeAAkJiAt/KgB9AQAYAAYJGQXESgC0AAABLgAFFAIJAgAIAAAAAA==.Starsomave:BAAALgAFFAIJAgAAAA==.Steen:BAAALgADCgEJAQAAAA==.Stinkylev:BAAALgADCgEJAQABLgAFFAcJFQAXAFQbAA==.Strentor:BAAALgAECgEJAQAAAA==.',
Su='Sunshinë:BAAALgAECgEJAgAAAA==.Supressor:BAAALgADCgQJCAABLgAECgIJAgAIAAAAAA==.',
Sy='Sylvester:BAAALgADCgIJAgAAAA==.',
['Sé']='Sérolis:BAAALgADCgEJAQAAAA==.',
Ta='Taehausx:BAACLgAFFH8rAAIOAAgJFiKVAABQAgAOAAgJFiKVAABQAgAuAAQKfzAAAw4ACQlSJB8GACUDAA4ACQlSJB8GACUDAB8AAgk5HqxbAKIAAAAA.Tarmo:BAAALgADCgYJFgAAAA==.',
Te='Telesto:BAAALgAECgIJAgABLgAFFAYJGgACAHEjAA==.Templeton:BAAALgADCgMJAwAAAA==.Tenath:BAABLgAECn8bAAIKAAcJsRK2JwA4AQAKAAcJsRK2JwA4AQAAAA==.',
Th='Thaleon:BAAALgAECgcJDQAAAA==.Tharella:BAAALgAECgYJCwAAAA==.Thauriel:BAAALgAECgUJBwAAAA==.Thrumple:BAAALgADCgYJCgAAAA==.',
Ti='Tipz:BAAALgAECgIJAwABLgAECgUJBQAIAAAAAA==.Titania:BAABLgAECn8eAAIjAAkJTAa9QAB1AQAjAAkJTAa9QAB1AQAAAA==.',
Tr='Trollztoll:BAAALgAECgIJAgAAAA==.',
Tu='Tuulk:BAAALgADCgIJAgAAAA==.',
Ty='Typical:BAAALgADCgcJCwAAAA==.',
Ug='Uggoorc:BAACLgAFFH8QAAINAAQJIwt1SgAQAQANAAQJIwt1SgAQAQAuAAQKfx0AAg0ACAnmHL4uAB0CAA0ACAnmHL4uAB0CAAAA.Uggotroll:BAAALgAECgUJCwABLgAFFAQJEAANACMLAA==.',
Un='Unholylord:BAAALgAECggJDAABLgAFFAcJHgAeAIIiAA==.',
Ut='Uthok:BAAALgADCgcJBwAAAA==.',
Va='Vacalocà:BAABLgAECn8UAAITAAgJUQ3kGABDAQATAAgJUQ3kGABDAQAAAA==.Valerian:BAAALgAECggJDQAAAA==.Validori:BAAALgADCgEJAQAAAA==.Van:BAAALgADCgcJFAAAAA==.Vaultkey:BAAALgADCgIJAwAAAA==.',
Ve='Vegesha:BAAALgAECgEJAgAAAA==.Veinke:BAABLgAECn8WAAIEAAkJ+w45CwClAQAEAAkJ+w45CwClAQAAAA==.Vengefullev:BAAALgADCgUJBwABLgAFFAcJFQAXAFQbAA==.Venin:BAAALgAECgYJCwAAAA==.Vessarind:BAAALgADCgEJAgAAAA==.',
Vi='Vitora:BAAALgAECgYJEQAAAA==.',
Vo='Voidkurn:BAAALgADCgYJCQAAAA==.Von:BAAALgADCgIJAgAAAA==.',
Vy='Vyse:BAAALgADCgYJBgAAAA==.',
Wa='Waally:BAAALgAECgcJEgAAAA==.Wahgwan:BAAALgAECgMJAwAAAA==.Waleran:BAAALgADCgIJAgAAAA==.Warrdaddy:BAAALgAECgQJCgABLgADCgcJBwAIAAAAAA==.Warriorbp:BAAALgADCgkJFwAAAA==.Wattz:BAAALgAECgYJBgAAAA==.',
We='Weebsora:BAAALgAECgYJDgAAAA==.',
Wo='Worldtree:BAAALgAECgYJEAAAAA==.',
Wy='Wynne:BAAALgAECgcJCAAAAA==.',
Xa='Xaelthira:BAAALgAECgYJCgAAAA==.',
Xe='Xerath:BAAALgADCgYJCAAAAA==.',
Xi='Xips:BAAALgADCgMJAwABLgAECgUJBQAIAAAAAA==.',
Xo='Xoru:BAAALgADCgYJBgAAAA==.Xoruk:BAAALgADCgQJBAABLgAFFAIJAgAIAAAAAA==.Xorun:BAAALgAECgEJAQABLgAFFAIJAgAIAAAAAA==.',
Xz='Xzarrion:BAAALgAECgEJAQAAAA==.',
Ya='Yadhi:BAABLgAECn8XAAQOAAYJihZYMgA1AQAOAAUJihZYMgA1AQAXAAYJoBDBTgArAQAfAAUJ3Af4ZQCHAAAAAA==.',
Ye='Yetkin:BAAALgAECgYJDQAAAA==.',
Yi='Yifftron:BAAALgAECgYJBgABLgAECggJGwANAAogAA==.Yimomo:BAABLgAECn8cAAMYAAkJhRUbLgCMAQAYAAkJhRUbLgCMAQAeAAcJtwekTADaAAAAAA==.',
Yo='Yoshira:BAAALgAECgMJAwABLgAECggJDQAIAAAAAA==.',
Yz='Yzra:BAAALgAECgQJBAAAAA==.',
Za='Zalconn:BAACLgAFFH8YAAMdAAUJVyYuDQCzAQAdAAUJVyYuDQCzAQAkAAIJDRf/CwCZAAAuAAQKfysAAx0ACQkcJjoDAGwDAB0ACQnZJToDAGwDACQAAQneJhQbAHEAAAAA.Zarrona:BAABLgAECn8mAAMkAAgJEB8DBQAfAgAkAAcJtR0DBQAfAgAdAAcJkRrPHgCcAQAAAA==.Zayah:BAABLgAECn8XAAIRAAgJyRTkKACkAQARAAgJyRTkKACkAQAAAA==.',
Zi='Zinmaris:BAAALgAFFAIJAgAAAA==.Zivanka:BAAALgAECgcJCgABLgAECgcJDwAIAAAAAA==.',
Zn='Znasty:BAABLgAECn8rAAIdAAgJHCWPBQDYAgAdAAgJHCWPBQDYAgAAAA==.',
Zo='Zombaman:BAAALgADCgMJAwAAAA==.',
Zu='Zuong:BAAALgADCgQJBAAAAA==.',
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
