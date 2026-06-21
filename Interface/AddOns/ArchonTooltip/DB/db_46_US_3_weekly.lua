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

local lookup = {'Mage-Frost','Paladin-Retribution','Warrior-Arms','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Unknown-Unknown','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Protection','Hunter-BeastMastery','Monk-Brewmaster','Warlock-Affliction','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Druid-Feral','Druid-Balance','DeathKnight-Unholy','Warlock-Destruction','Monk-Mistweaver','Priest-Holy','Druid-Restoration','Druid-Guardian','Mage-Arcane','Hunter-Marksmanship','Hunter-Survival','Rogue-Subtlety','Priest-Shadow','Monk-Windwalker','Evoker-Preservation','Priest-Discipline','Paladin-Holy','Rogue-Outlaw','Shaman-Enhancement','DeathKnight-Blood','DeathKnight-Frost','Mage-Fire',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abeblinkin:BAABLgAECn9BAAIBAAkJhyHKFQDWAgABAAkJhyHKFQDWAgAAAA==.',
Ac='Accursed:BAAALgAECgEJAQAAAA==.',
Ad='Adcrusty:BAAALgAECgEJAQAAAA==.',
Ae='Aegrias:BAABLgAECn8hAAICAAkJEx48JwCJAgACAAkJEx48JwCJAgAAAA==.Aeledron:BAAALgADCgQJBQAAAA==.Aerodria:BAABLgAECn9cAAICAAkJkBYrOAAhAgACAAkJkBYrOAAhAgAAAA==.',
Aj='Ajm:BAABLgAFFH8LAAIDAAQJmxQBGgAWAQADAAQJmxQBGgAWAQAAAA==.',
Ak='Akarii:BAAALgAECgYJEAAAAA==.Akeno:BAABLgAECn8VAAIEAAgJQCNZAQAYAwAEAAgJQCNZAQAYAwAAAA==.Akiaura:BAAALgAECgYJEgAAAA==.Akime:BAAALgAECgYJDwAAAA==.Akudama:BAABLgAECn8tAAMFAAkJnxptEABkAgAFAAkJnxptEABkAgAGAAIJqQkFNwBfAAABLgAFFAgJKgAHACQZAA==.',
Al='Alarm:BAAALgADCgEJAQABLgADCgcJCwAIAAAAAA==.Albince:BAAALgADCgIJAgAAAA==.Aldanil:BAAALgAECggJEAAAAA==.Alisae:BAAALgADCgMJAwAAAA==.Alma:BAAALgAECgUJBQAAAA==.Alye:BAAALgAECgcJEAAAAA==.',
Am='Amellis:BAAALgAECgUJCQAAAA==.',
An='Ananac:BAAALgADCgEJAQAAAA==.Andreasham:BAAALgADCgEJAQAAAA==.Andrius:BAAALgAECgQJBQAAAA==.Annisseda:BAACLgAFFH8eAAMJAAYJXh9RCQDKAQAJAAYJXh9RCQDKAQADAAIJ2xgaQABKAAAuAAQKfysAAwkACQmLJPsHAN8CAAkACQmLJPsHAN8CAAMAAQl9ITJkAFkAAAAA.',
Ar='Aradril:BAAALgADCgcJCwAAAA==.Arktos:BAAALgAECgYJDQAAAA==.Arrhythmia:BAAALgAECgkJJQABLgAFFAgJJQAIAAAAAQ==.Articuno:BAAALgAECgYJEQAAAA==.',
As='Ashrak:BAAALgAECgQJBAAAAA==.Ashér:BAAALgAECgEJAQAAAA==.Astaulis:BAAALgADCgUJCAAAAA==.',
Ax='Axelle:BAAALgAECggJDwAAAA==.',
Az='Azzy:BAACLgAFFH8pAAIJAAgJ2hqVAgBsAgAJAAgJ2hqVAgBsAgAuAAQKfz4AAgkACQnlJXgCAJMDAAkACQnlJXgCAJMDAAAA.',
Ba='Babyboomie:BAAALgAECgUJBwAAAA==.Bagagwa:BAAALgADCgcJCAAAAA==.Bal:BAABLgAECn8kAAQKAAgJVhXKHQDRAQAKAAgJ8xLKHQDRAQALAAYJWQ/BkwD5AAAEAAIJBiFOKQBeAAAAAA==.Balam:BAAALgADCgEJAQAAAA==.Balana:BAAALgAECgUJCAAAAA==.Bambudda:BAAALgADCgYJBgAAAA==.Bananski:BAABLgAECn8VAAMMAAYJUQ2vJADjAAAMAAUJIA+vJADjAAACAAYJXwa09QDEAAAAAA==.Bandu:BAAALgADCgEJAgAAAA==.Barkeep:BAABLgAECn8aAAINAAkJaw+WOADMAQANAAkJaw+WOADMAQAAAA==.Bassoon:BAAALgAECgMJAwABLgAFFAIJBQAOAE4RAA==.',
Be='Beeflocks:BAABLgAECn8eAAIPAAkJTBpABwD/AQAPAAkJTBpABwD/AQAAAA==.Beefpile:BAAALgADCgUJBQAAAA==.Bekarn:BAABLgAECn8YAAMQAAcJeAofUwA5AQAQAAcJeAofUwA5AQARAAMJ7AhzegBaAAAAAA==.Benafflock:BAAALgAECgMJAwAAAA==.Bennafflock:BAAALgAECgUJCwAAAA==.Bergz:BAAALgAECgMJAgAAAA==.',
Bh='Bhp:BAAALgADCgMJAwABLgAECgMJAwAIAAAAAA==.',
Bi='Bigbleu:BAAALgAECgUJCQABLgAECggJJwASAHkdAA==.Bigdh:BAAALgAECgYJDgAAAA==.Bigdraco:BAAALgADCgQJBAAAAA==.Bigpapapump:BAAALgAECgEJAQAAAA==.Bigxthaplug:BAAALgAECgYJCQAAAA==.Bilboswagins:BAABLgAECn8UAAIJAAcJyxwLIwA9AgAJAAcJyxwLIwA9AgAAAA==.Billski:BAAALgAECgcJCAAAAA==.Billyspike:BAABLgAECn8YAAMTAAYJ0RrjDQDVAQATAAYJ0RrjDQDVAQAUAAEJkhKoigA2AAABLgAECgkJEwAIAAAAAA==.Billyspiked:BAAALgAECgIJAgABLgAECgkJEwAIAAAAAA==.Billyspikeev:BAAALgADCgYJBgABLgAECgkJEwAIAAAAAA==.Billyspikepd:BAAALgAECgkJEwAAAA==.Billyspikepr:BAAALgAECgUJCAABLgAECgkJEwAIAAAAAA==.Billyspikerg:BAAALgADCgIJAgABLgAECgkJEwAIAAAAAA==.',
Bl='Blammo:BAAALgADCgcJCQAAAA==.Blobcat:BAABLgAECn8XAAIUAAcJJBvZAABsAQAUAAcJJBvZAABsAQAAAA==.Blobknight:BAAALgADCgEJAQAAAA==.Blobpally:BAACLgAFFH8NAAICAAQJ0RQKTwAQAQACAAQJ0RQKTwAQAQAuAAQKfyAAAgIABwm7IW0dALoCAAIABwm7IW0dALoCAAAA.Bloodhase:BAABLgAECn8YAAIVAAcJGxFtlwA6AQAVAAcJGxFtlwA6AQAAAA==.Bloodprince:BAAALgAECgMJAwAAAA==.Bluecard:BAACLgAFFH8dAAIHAAYJjR73IwC9AQAHAAYJjR73IwC9AQAuAAQKfywABAcACQl+IcYPAM4CAAcACQl+IcYPAM4CABYAAwnVGMg5AM0AAA8AAQkXIY0nAFMAAAAA.',
Bo='Bokunh:BAAALgAECgYJEgAAAA==.Boomywhoomy:BAAALgAECgIJBQAAAA==.Bothenheim:BAACLgAFFH8bAAMCAAYJcSN8EwDQAQACAAYJcSN8EwDQAQAMAAMJQQxREwBfAAAuAAQKfyYAAgIACQmAIgQVAMQCAAIACQmAIgQVAMQCAAAA.Bowdaddy:BAAALgADCgcJBwAAAA==.Boxtribution:BAAALgAECgMJBQAAAA==.Boxxman:BAAALgAECgcJAQAAAA==.',
Br='Breakdown:BAAALgAECgEJAQAAAA==.Brewsimmons:BAABLgAFFH8NAAIXAAcJ7ws5GgCjAQAXAAcJ7ws5GgCjAQAAAA==.Brüisér:BAACLgAFFH8FAAIMAAIJxwbIFABUAAAMAAIJxwbIFABUAAAuAAQKfyUAAgwACQluD5IYAFgBAAwACQluD5IYAFgBAAAA.',
Bu='Bublz:BAAALgAECgcJBwAAAA==.Bumpinuglies:BAAALgAECgEJAQAAAA==.',
Ca='Callamdrake:BAAALgAECgEJAQAAAA==.Callamsvoid:BAAALgAECgMJCAAAAA==.Camazotz:BAAALgADCgkJCgAAAA==.Capie:BAAALgAECgkJEAAAAA==.Carathea:BAABLgAECn8iAAIYAAgJMSCCDACLAgAYAAgJMSCCDACLAgAAAA==.Cardstock:BAAALgAECggJCAABLgAFFAgJJQAIAAAAAQ==.Carrotbear:BAAALgADCgQJBAAAAA==.Cassiopeià:BAAALgAECgMJAwAAAA==.Caylen:BAACLgAFFH8ZAAIZAAYJJiGvCwA4AgAZAAYJJiGvCwA4AgAuAAQKfyAAAhkACAm3HkIRAK0CABkACAm3HkIRAK0CAAAA.Cayth:BAACLgAFFH8ZAAMHAAUJ0CDoOABnAQAHAAUJux3oOABnAQAPAAEJJR+oGABcAAAuAAQKfysAAwcACQnMIakFAGIDAAcACQnMIakFAGIDABYAAgkLAx9VAG8AAAAA.',
Ce='Cemie:BAAALgADCgcJBwAAAA==.Centralia:BAAALgADCgYJBwAAAA==.Centri:BAACLgAFFH8RAAIBAAcJVxntCgDHAQABAAcJVxntCgDHAQAuAAQKfyQAAgEACQlGJRYaAA8DAAEACQlGJRYaAA8DAAAA.Cerestus:BAAALgADCgMJAwAAAA==.',
Ch='Chadbear:BAABLgAECn8UAAMaAAgJ/BM8GQCFAQAaAAgJ/BM8GQCFAQATAAMJwQm6NAAwAAAAAA==.Chadtones:BAAALgAECgQJBAAAAA==.Chimueloh:BAAALgADCgQJBAAAAA==.Chiron:BAAALgADCgIJAgAAAA==.Chowa:BAAALgAFFAMJAwAAAA==.Chrleone:BAAALgAECgIJAgAAAA==.Chu:BAAALgAECgEJAQAAAA==.',
Cl='Cleverlev:BAABLgAECn8aAAIbAAYJ/RQQBwBDAQAbAAYJ/RQQBwBDAQABLgAFFAcJFQAXAFQbAA==.',
Co='Colapse:BAAALgAECgEJAQAAAA==.Colivism:BAABLgAECn8kAAIBAAgJpRaleQDeAQABAAgJpRaleQDeAQAAAA==.Colívis:BAAALgAECgQJBQAAAA==.Commodorecdx:BAAALgADCgcJBwAAAA==.Cotali:BAAALgADCgUJBQABLgAECggJIgAYADEgAA==.',
Cr='Crackfiend:BAAALgADCgUJBwAAAA==.Crispi:BAAALgADCgYJBAAAAA==.Cruellev:BAAALgAECgUJCgABLgAFFAcJFQAXAFQbAA==.Crymbrulay:BAAALgAECgYJCAAAAA==.',
Cz='Czernobog:BAAALgAECgMJAwAAAA==.',
Da='Daedrenda:BAAALgAECgMJBAAAAA==.Daeland:BAABLgAECn8yAAIJAAkJ0hDjJQDJAQAJAAkJ0hDjJQDJAQAAAA==.Dakky:BAAALgAFFAMJAQAAAA==.',
De='Deathsgrace:BAAALgAECgkJCQAAAA==.Deathtank:BAAALgAECgYJDwAAAA==.Deathtolife:BAAALgAECgQJCAAAAA==.Decima:BAABLgAECn8lAAIUAAkJng2yKgB/AQAUAAkJng2yKgB/AQAAAA==.Degrance:BAAALgAECgUJBQAAAA==.Demeter:BAACLgAFFH8ZAAMNAAcJRhh2MQBMAQANAAUJfCF2MQBMAQAcAAIJ2gWKIwCSAAAuAAQKfyIABA0ACQlYIuASAKACAA0ACAk6HuASAKACABwABglxILUoAOQBAB0AAQkoIMxTAF8AAAAA.Demonpunter:BAAALgAFFAIJBAABLgAFFAUJGQAHAH4lAA==.Dewussi:BAACLgAFFH8TAAICAAQJnAn0WwD4AAACAAQJnAn0WwD4AAAuAAQKfyQAAwwABwniHYENAO8BAAwABwk4GYENAO8BAAIABwlnG3FpAJwBAAAA.',
Di='Diablita:BAAALgAECgEJAQAAAA==.Dinkltn:BAAALgAECgMJAwAAAA==.Dinoscarr:BAAALgAECgQJCQAAAA==.',
Dj='Djholy:BAAALgAECgcJDwAAAA==.',
Do='Dotmaxxing:BAAALgAFFAEJAQAAAA==.Dotsndash:BAAALgAECgUJBQAAAA==.',
Dp='Dpsshaman:BAABLgAECn8cAAIRAAkJ6x6fCgC1AgARAAkJ6x6fCgC1AgAAAA==.',
Dr='Drarmaku:BAAALgAECgIJAgAAAA==.Dreadingfate:BAAALgAECgkJEAAAAA==.Drscholar:BAAALgAECgIJAwAAAA==.Druidpwnz:BAAALgADCgMJAwAAAA==.',
Du='Duber:BAAALgAECgUJBgAAAA==.Dungorogue:BAABLgAECn8wAAIeAAgJcRAGHgClAQAeAAgJcRAGHgClAQAAAA==.Dustln:BAAALgAECgEJAQAAAA==.',
Dy='Dyonne:BAAALgADCgEJAgAAAA==.',
['Dé']='Déwéy:BAAALgAECgIJAgABLgAFFAQJEwACAJwJAA==.',
El='Elbone:BAAALgADCgUJBQAAAA==.Elidia:BAAALgADCgcJBwAAAA==.Elinia:BAABLgAECn8zAAMYAAkJqxGlIwClAQAYAAgJqRKlIwClAQAfAAkJgQbNNwA2AQAAAA==.Elivoker:BAAALgAECgYJAwAAAA==.Elmdor:BAAALgAECgcJDQAAAA==.Elyndra:BAAALgAFFAEJAQAAAA==.',
En='Eniacoc:BAAALgAECgkJCQAAAA==.Enlag:BAAALgAECgMJAwAAAA==.',
Et='Etriganna:BAAALgAECgEJAQAAAA==.',
Ev='Evilwitch:BAAALgADCgEJAQAAAA==.Evistiah:BAAALgAECgEJAQAAAA==.',
Ex='Excentric:BAABLgAECn8ZAAICAAgJdB6YPQAOAgACAAgJdB6YPQAOAgABLgAFFAcJEQABAFcZAA==.Excerpt:BAAALgAECgMJAwABLgAFFAcJEQABAFcZAA==.Exortus:BAAALgAFFAMJAwABLgAFFAYJGwACAHEjAA==.',
Fa='Falloutman:BAAALgAECgEJAQAAAA==.Farëeya:BAAALgADCgcJDAAAAA==.Fayne:BAAALgAECgUJCQAAAA==.',
Fe='Fellirane:BAAALgADCgUJBQAAAA==.Fernsama:BAAALgAECgYJCAAAAA==.',
Fi='Fishton:BAAALgADCgUJCwAAAA==.',
Fl='Flauros:BAABLgAECn8XAAILAAcJ4Q3khgASAQALAAcJ4Q3khgASAQAAAA==.',
Fr='Fraternite:BAAALgAECgkJDgAAAA==.Froackeh:BAAALgAECggJBwAAAA==.Froackie:BAAALgAECgYJEAABLgAECggJBwAIAAAAAA==.Fruto:BAACLgAFFH8FAAIOAAIJThGqRQCKAAAOAAIJThGqRQCKAAAuAAQKfzEAAg4ACQnLF/ATABACAA4ACQnLF/ATABACAAAA.',
Ga='Gabriellad:BAAALgAECgQJCQAAAA==.Garzislao:BAAALgAECggJEAAAAA==.',
Gh='Ghostfox:BAAALgAECgMJAwAAAA==.',
Gi='Giterdonee:BAACLgAFFH8VAAIJAAcJfBcCCQDPAQAJAAcJfBcCCQDPAQAuAAQKfyEAAgkACQn9IKEEAF8DAAkACQn9IKEEAF8DAAAA.',
Gl='Gleymoulleon:BAAALgAECgQJBwAAAA==.',
Go='Goblinbeans:BAACLgAFFH8LAAIQAAUJlQiPBQBzAQAQAAUJlQiPBQBzAQAuAAQKfxcAAhAACAlLFqckAAMCABAACAlLFqckAAMCAAEuAAUUBwkNABcA7wsA.Goku:BAAALgAECgQJBAAAAA==.Gothmommy:BAAALgADCgIJAgAAAA==.',
Gr='Greenbeans:BAAALgAECgUJCQABLgAFFAcJDQAXAO8LAA==.Grence:BAAALgAECgUJDAABLgAECgcJEwAIAAAAAA==.Grimreaper:BAABLgAECn8lAAMQAAcJNw3IXABGAQAQAAcJNw3IXABGAQARAAQJPwLJewBVAAAAAA==.Griphöök:BAAALgAECgEJAgAAAA==.Groldin:BAAALgAECgQJBgAAAA==.Groshkar:BAAALgADCgcJCwAAAA==.Grumble:BAAALgAFFAEJAQAAAA==.',
['Gõ']='Gõtchoo:BAAALgAFFAMJAwAAAA==.',
Ha='Hairball:BAABLgAECn8hAAIdAAkJGxQVEwAOAgAdAAkJGxQVEwAOAgAAAA==.Hallona:BAAALgADCgMJAwAAAA==.Hammerthumb:BAAALgAECgUJDAABLgAFFAIJBgATAPkHAA==.',
Ho='Hotdoggin:BAAALgADCgYJDAAAAA==.',
Hy='Hyara:BAABLgAECn8rAAINAAkJghziDwC8AgANAAkJghziDwC8AgAAAA==.',
['Hì']='Hìm:BAAALgAECgMJBAAAAA==.',
['Hù']='Hùñtarð:BAAALgADCgUJCwAAAA==.',
Ib='Ibefarmin:BAAALgAECgEJAQAAAA==.',
Ic='Icecreammen:BAAALgADCgQJBAAAAA==.Iceshadow:BAACLgAFFH8JAAIXAAMJLhTVNwDIAAAXAAMJLhTVNwDIAAAuAAQKfxYAAxcABwnjHq8VAG0CABcABwnjHq8VAG0CACAAAgkrAp/DAA8AAAAA.Icobal:BAAALgADCgYJCAAAAA==.',
Il='Illisa:BAAALgADCgMJAwAAAA==.',
Ir='Irongallo:BAAALgADCgEJAQAAAA==.',
Ja='Jabdis:BAAALgADCgEJAQAAAA==.Jabzulsor:BAAALgAECgEJAQAAAA==.Jacopo:BAABLgAECn8XAAIVAAgJtw40hABbAQAVAAgJtw40hABbAQAAAA==.',
Je='Jeffster:BAAALgAFFAIJAgAAAA==.',
Jo='Jocko:BAAALgAECgMJAwAAAA==.Jordi:BAABLgAECn84AAINAAkJ3B12GQCNAgANAAkJ3B12GQCNAgAAAA==.',
Ju='Jutti:BAAALgAECgQJCQAAAA==.',
Ka='Kaellen:BAAALgADCgUJBQAAAA==.Kahnman:BAAALgADCgUJBQAAAA==.Kaka:BAAALgAECgcJEwAAAA==.Kalet:BAAALgAECgMJAwAAAA==.Kaluaruun:BAAALgAECgEJAQAAAA==.Kandinsky:BAAALgADCgIJAgAAAA==.Kanree:BAACLgAFFH8rAAMXAAcJ7wkTBAD6AAAXAAcJ7wkTBAD6AAAgAAEJ5gYJRgA0AAAuAAQKfz4AAxcACQkiG0oLAJwCABcACQkiG0oLAJwCACAAAQknB7CpACgAAAAA.Kartiri:BAACLgAFFH8aAAMhAAYJ0BeGDQDHAQAhAAYJ0BeGDQDHAQAFAAQJPwxLSQCmAAAuAAQKfy8ABCEACQmRHVoGAN4CACEACQmRHVoGAN4CAAUABQnWFm00AGEBAAYABQkPGM0lAPUAAAAA.Kawhi:BAAALgAFFAEJAQAAAA==.',
Ke='Kea:BAACLgAFFH8YAAMiAAUJ5iNfEgD9AQAiAAUJ5iNfEgD9AQAYAAIJjBiqJACXAAAuAAQKfzwAAyIACQkNJr0AAOEDACIACQkNJr0AAOEDABgAAwlTI1w1AC4BAAAA.Keedoril:BAAALgADCgUJCgAAAA==.Keicelinis:BAABLgAECn8WAAILAAYJ9xLHfgAiAQALAAYJ9xLHfgAiAQAAAA==.Keratos:BAAALgAECgYJCQAAAA==.',
Kh='Khaalid:BAAALgAECgYJCgAAAA==.Khran:BAAALgADCgIJAgAAAA==.',
Ki='Kickingfluff:BAAALgADCgIJAgAAAA==.Kimjoonsang:BAAALgAECgEJAQABLgAECgEJAQAIAAAAAA==.Kipz:BAAALgAECgUJBQAAAA==.Kittyboy:BAAALgADCgUJBQAAAA==.',
Ko='Kookykrook:BAABLgAFFH8IAAIFAAQJrQ8xNADyAAAFAAQJrQ8xNADyAAAAAA==.Korxin:BAACLgAFFH8ZAAINAAcJDxeOEQDXAQANAAcJDxeOEQDXAQAuAAQKfysAAg0ACQkpI+oEAD8DAA0ACQkpI+oEAD8DAAAA.',
Kr='Kreizikat:BAACLgAFFH8PAAIZAAUJDxPLIQBKAQAZAAUJDxPLIQBKAQAuAAQKfzIAAhkACAnJITQOAMgCABkACAnJITQOAMgCAAAA.Krinn:BAAALgAECgYJCQAAAA==.Krios:BAAALgADCgQJBAAAAA==.',
Ku='Kurquaan:BAABLgAECn8XAAMaAAgJVBQJGACRAQAaAAgJVBQJGACRAQAUAAQJEwyWVgDKAAAAAA==.',
La='Lanstan:BAAALgAECgQJBAAAAA==.',
Le='Leilar:BAAALgAECgIJAgAAAA==.Leron:BAAALgAECgYJCAAAAA==.Levitticus:BAABLgAECn85AAIjAAkJQh9MBgAoAwAjAAkJQh9MBgAoAwABLgAFFAcJFQAXAFQbAA==.',
Li='Liale:BAAALgAFFAEJAQAAAA==.Lideyn:BAAALgAECgEJAQAAAA==.Lidrel:BAAALgAECgYJBgAAAA==.Lightfury:BAAALgAECgMJAwABLgAECgYJCAAIAAAAAA==.',
Lo='Loinari:BAABLgAECn8WAAIUAAcJ8AR5VAC9AAAUAAcJ8AR5VAC9AAAAAA==.Lokano:BAAALgAECgUJBwAAAA==.',
Lu='Luaru:BAAALgAECgEJAQAAAA==.Ludmylha:BAAALgAFFAEJAQAAAA==.Luisda:BAAALgADCgUJBQAAAA==.Lulak:BAAALgAECgQJCQAAAA==.Lull:BAABLgAECn8tAAMWAAkJ6A5ICwCMAQAWAAkJ6A5ICwCMAQAHAAEJ4QLaYwEdAAAAAA==.Luthin:BAAALgADCgUJBgAAAA==.',
Ly='Lyadre:BAAALgAECgIJAgAAAA==.Lynai:BAAALgADCgIJAgAAAA==.Lyndis:BAAALgAECgQJBAAAAA==.',
Ma='Madness:BAAALgAECgMJAwAAAA==.Magejaf:BAAALgADCgcJDQABLgAECggJGgAPAMoVAA==.Magidragon:BAABLgAECn8ZAAIBAAkJCQ4VAwAsAQABAAkJCQ4VAwAsAQAAAA==.Mandrah:BAAALgADCgQJBQAAAA==.Maybell:BAAALgAECgQJBwAAAA==.',
Md='Mdavis:BAAALgAECgYJBgAAAA==.',
Me='Melt:BAACLgAFFH8qAAMHAAgJJBmyAgB8AQAHAAcJQhmyAgB8AQAWAAEJchgqHABbAAAuAAQKfz4AAwcACQl+I/8JAAEDAAcACQl+I/8JAAEDABYABAmoEncsAAwBAAAA.Mepha:BAABLgAFFH8FAAIVAAMJ7QhKsADCAAAVAAMJ7QhKsADCAAAAAA==.Metons:BAAALgAECggJDQAAAA==.',
Mi='Midei:BAAALgADCgkJFgAAAA==.Midriffluvr:BAAALgAECgQJBAAAAA==.Mikasa:BAAALgADCgEJAQAAAA==.Mike:BAAALgADCgcJCAAAAA==.Mimosa:BAAALgADCgYJCgABLgAECgYJCAAIAAAAAA==.Mirna:BAAALgAECgMJBgAAAA==.Misfitdk:BAAALgAECgEJBAAAAA==.Misfitdots:BAAALgAECgEJAQAAAA==.Misfitmagi:BAAALgAECgEJBAAAAA==.Misfitmonk:BAAALgAECgEJAgAAAA==.Misfittotem:BAAALgAECgEJAwAAAA==.Mistfox:BAAALgAECgYJDgAAAA==.',
Mo='Mobiouse:BAAALgADCgYJBgAAAA==.Mollieann:BAAALgAECgMJBQAAAA==.Mommon:BAAALgAECgYJCAAAAA==.Moonraisin:BAAALgAECgMJBQAAAA==.Morrighan:BAAALgADCgQJBQAAAA==.',
Mu='Mukdron:BAAALgADCgIJAgAAAA==.',
['Mâ']='Mâlus:BAAALgAECgYJDwAAAA==.',
Na='Nadra:BAAALgAFFAIJAgAAAA==.Naminé:BAAALgADCgMJAwABLgAECggJJgAkABAfAA==.Nattyrav:BAACLgAFFH8QAAIlAAQJuR6qAAAQAQAlAAQJuR6qAAAQAQAuAAQKfygAAyUACQkbH8ADAO4CACUACQlnHsADAO4CABEABgnHG/o3AFgBAAAA.Nawari:BAAALgAECgIJAwAAAA==.',
Ne='Nemonk:BAACLgAFFH8HAAIgAAMJARR5IwDHAAAgAAMJARR5IwDHAAAuAAQKf1oAAyAACQkeH0AGAOgCACAACQkeH0AGAOgCABcAAQlQA1bWABwAAAAA.Neryssa:BAACLgAFFH8bAAQHAAgJhhviDgBFAgAHAAgJtRriDgBFAgAWAAEJYRVRHgBXAAAPAAEJpRwxHABVAAAuAAQKfzoAAwcACQnYJOkIAAwDAAcACAlvJOkIAAwDABYABAkpJPUYAIMBAAAA.',
Ni='Nickjamez:BAAALgADCgYJBgAAAA==.Nipz:BAAALgAECgEJAQABLgAECgUJBQAIAAAAAA==.',
No='Nocter:BAABLgAECn8fAAQHAAkJwhxnNwAuAgAHAAcJZhxnNwAuAgAPAAUJUiCTCwCBAQAWAAMJ9g0APgC8AAAAAA==.Noqtir:BAAALgAECgUJCgAAAA==.Not:BAAALgADCgcJAgAAAA==.Noyoo:BAAALgADCgEJAQAAAA==.',
Nu='Nunca:BAAALgAECgEJAQAAAA==.',
Ny='Nymura:BAABLgAECn8iAAICAAgJLQrUpwArAQACAAgJLQrUpwArAQAAAA==.',
['Nä']='Näesthra:BAABLgAECn8kAAIYAAgJdBhoHADjAQAYAAgJdBhoHADjAQAAAA==.',
Oa='Oakhugger:BAACLgAFFH8GAAITAAIJ+QeAAQB6AAATAAIJ+QeAAQB6AAAuAAQKfyQAAxMACQlYENsPALkBABMACQlYENsPALkBABQAAQkAAEWxAAAAAAAA.',
Ob='Obelisk:BAAALgADCgYJBgAAAA==.Obelix:BAAALgAECgEJAQAAAA==.',
Ok='Okarun:BAABLgAECn8jAAILAAcJTB5nQQDuAQALAAcJTB5nQQDuAQABLgAECggJJgAkABAfAA==.',
Ol='Oldeone:BAAALgAECgMJBAAAAA==.Olyvivia:BAAALgAFFAIJBAAAAA==.',
Om='Omgega:BAABLgAECn9DAAICAAgJWhuWNwAjAgACAAgJWhuWNwAjAgAAAA==.',
On='Onichan:BAAALgAECgYJCQABLgAFFAcJFQARAI8ZAA==.Onimeek:BAABLgAECn9NAAMKAAkJEyBqBwC7AgAKAAkJEyBqBwC7AgALAAIJPAlYDgE7AAAAAA==.',
Or='Oryn:BAAALgAFFAEJAwABLgAFFAIJBgABACcVAA==.Oryx:BAAALgAECgEJAwAAAA==.',
Pa='Pallywahwah:BAAALgAFFAEJAQAAAA==.Palpitations:BAAALgAECgcJEAAAAA==.Paper:BAAALgAFFAgJJQAAAQ==.Paudetunia:BAAALgADCgIJAgAAAA==.',
Pe='Peacefullev:BAACLgAFFH8VAAMXAAcJVBtgCwBRAgAXAAcJVBtgCwBRAgAgAAEJKQuHRAA2AAAuAAQKfyYAAxcACAn8HrIOALUCABcACAn8HrIOALUCACAABwnDFYwmAIEBAAAA.Pelagius:BAAALgADCgYJBwAAAA==.Penance:BAAALgAECgEJAQAAAA==.Pestilence:BAAALgAECggJDQAAAA==.',
Ph='Phantomthief:BAAALgAECgcJAgAAAA==.Phyllus:BAAALgAFFAIJAgAAAA==.',
Pi='Pictureplane:BAAALgADCgEJAQAAAA==.Pipeleto:BAABLgAECn8cAAIJAAgJzhj0HgD3AQAJAAgJzhj0HgD3AQAAAA==.',
Po='Poochimus:BAABLgAECn8hAAIlAAkJsROxCgAOAgAlAAkJsROxCgAOAgAAAA==.Pookong:BAAALgAECgUJCQAAAA==.Poonslayerxx:BAAALgADCgMJAwAAAA==.',
Pr='Previdius:BAAALgAECggJEQAAAA==.Priestpwnz:BAAALgAECgYJDwAAAA==.Protomán:BAAALgAECggJEQAAAA==.Proximity:BAAALgADCgQJBQABLgADCgcJCwAIAAAAAA==.',
Ps='Psychmike:BAAALgAECgEJAQAAAA==.',
Pw='Pwrbttm:BAAALgAECgEJAQABLgAFFAQJEQANACMLAA==.',
['Pé']='Pépega:BAAALgAECgIJAgAAAA==.',
Ra='Rafferno:BAAALgAECgEJAgAAAA==.',
Re='Redeemedlev:BAACLgAFFH8bAAIiAAQJ8xkwIgA+AQAiAAQJ8xkwIgA+AQAuAAQKf0IAAiIACQnkIScEAFcDACIACQnkIScEAFcDAAEuAAUUBwkVABcAVBsA.Reds:BAAALgAECgEJAQAAAA==.Relax:BAABLgAECn8YAAILAAYJOh5eUQCRAQALAAYJOh5eUQCRAQAAAA==.',
Rh='Rhesand:BAABLgAECn8ZAAMFAAgJPAS8VgDXAAAFAAgJPAS8VgDXAAAGAAEJjwGoLQAEAAAAAA==.Rhëa:BAAALgAECgMJBAAAAA==.',
Ri='Riellus:BAAALgADCgkJFQAAAA==.Riiu:BAABLgAECn8cAAIgAAYJHR0vJwB9AQAgAAYJHR0vJwB9AQABLgAFFAMJCAACAKgaAA==.Rindra:BAAALgAECgUJBwAAAA==.Rinkelle:BAAALgAECgYJBgAAAA==.Rixin:BAECLgAFFH8eAAMVAAgJLBxJEQBTAgAVAAgJLBxJEQBTAgAmAAEJAACGCgAAAAAuAAQKfzwAAhUACQk3JgYGAEkDABUACQk3JgYGAEkDAAAA.Rixryu:BAEALgADCgkJFgABLgAFFAgJHgAVACwcAA==.',
Ro='Roaka:BAAALgADCggJCAAAAA==.Rokom:BAACLgAFFH8LAAIJAAMJ1xiGNADfAAAJAAMJ1xiGNADfAAAuAAQKfyQAAgkACAneH28TALICAAkACAneH28TALICAAAA.Rollster:BAAALgAECgQJBAAAAA==.Rotandroll:BAAALgADCgYJBgABLgAECgEJAQAIAAAAAA==.',
Ru='Ruwey:BAAALgAECgEJAQAAAA==.',
Ry='Ryuk:BAAALgAECgYJEQAAAA==.',
['Rè']='Rèzurrect:BAAALgAECgUJDgAAAA==.',
Sa='Saaratharaxx:BAAALgAECgUJDAAAAA==.Sackhunter:BAABLgAECn8aAAILAAcJEg6SiwAJAQALAAcJEg6SiwAJAQAAAA==.Saero:BAABLgAECn8UAAIjAAcJbBmSKgC7AQAjAAcJbBmSKgC7AQAAAA==.Sake:BAAALgADCgMJAgABLgAFFAUJFQAgAGkTAA==.Saluuknir:BAACLgAFFH8FAAIFAAIJ7QcIVwBwAAAFAAIJ7QcIVwBwAAAuAAQKfzEAAwUACQmBD/omAKoBAAUACQlBD/omAKoBAAYABgloB4ojAAwBAAAA.Saphh:BAABLgAECn8dAAQnAAcJbRzkEwA/AQAVAAcJbBvMZgDBAQAnAAUJ/xnkEwA/AQAmAAQJQRX2NwC1AAABLgAFFAYJGQAnALUYAA==.Satrath:BAABLgAFFH8FAAIBAAIJdgkgqgCAAAABAAIJdgkgqgCAAAAAAA==.',
Se='Sedalin:BAAALgAECgEJAQAAAA==.Seekae:BAAALgAECgEJAQAAAA==.Sepidasprite:BAAALgADCgEJAQAAAA==.',
Sh='Shaddoot:BAAALgAFFAIJAgAAAA==.Shadowbladez:BAAALgAECgEJAQAAAA==.Shadowxd:BAABLgAFFH8IAAIZAAMJig5fRgCcAAAZAAMJig5fRgCcAAAAAA==.Sharky:BAAALgAFFAIJAwABLgAFFAgJJAAoAIUcAA==.Shaulana:BAAALgADCgYJBgAAAA==.Sheepforfree:BAAALgAECgIJAgAAAA==.Shenwu:BAAALgAECgQJBQAAAA==.Shinishamy:BAAALgADCgEJAQAAAA==.Shirokuma:BAABLgAFFH8eAAIaAAYJyyJaAwDxAQAaAAYJyyJaAwDxAQABLgAECggJFQAEAEAjAA==.Shorty:BAAALgADCgUJBQAAAA==.',
Si='Siera:BAAALgAECgEJAQABLgAECggJDQAIAAAAAA==.Sigrun:BAAALgADCgIJAgAAAA==.Sipz:BAAALgAECgIJAgABLgAECgUJBQAIAAAAAA==.',
Sk='Skinbone:BAAALgADCgQJBAAAAA==.Skyrius:BAABLgAFFH8GAAIVAAIJ2wk9+AB1AAAVAAIJ2wk9+AB1AAAAAA==.',
Sl='Slaty:BAAALgAECgIJAgAAAA==.Slingshotz:BAABLgAECn8ZAAIdAAkJ4RmrBgCWAgAdAAkJ4RmrBgCWAgAAAA==.Slootbag:BAAALgAECgkJDwAAAA==.',
Sn='Snax:BAAALgAECgIJAgAAAA==.Sneakylev:BAABLgAFFH8FAAIeAAMJPwtUAwDrAAAeAAMJPwtUAwDrAAABLgAFFAcJFQAXAFQbAA==.Sneux:BAAALgADCgcJDQAAAA==.Snuuze:BAACLgAFFH8PAAICAAMJJiFETgASAQACAAMJJiFETgASAQAuAAQKfyoAAgIACAkWI3AlAJECAAIACAkWI3AlAJECAAEuAAUUBgkLAAoAgRYA.Snuuzi:BAAALgAFFAEJAQABLgAFFAYJCwAKAIEWAA==.',
So='Soberloki:BAAALgAECgIJAgAAAA==.Sola:BAAALgAECgEJAQAAAA==.Solari:BAABLgAECn8cAAMLAAkJjRrxJQA2AgALAAkJ1BfxJQA2AgAKAAcJlhUVHwDGAQAAAA==.Sole:BAAALgAECgMJAwAAAA==.Solix:BAAALgAECgEJAQAAAA==.Solune:BAAALgAECgIJAwAAAA==.Solvi:BAAALgAECgYJDgAAAA==.Sophispapa:BAABLgAECn9CAAICAAcJ5SCjPAASAgACAAcJ5SCjPAASAgAAAA==.Souprage:BAABLgAECn8UAAIJAAgJvhAoMwB+AQAJAAgJvhAoMwB+AQAAAA==.',
Sp='Spellmaden:BAAALgADCgMJBgABLgAECggJJgAkABAfAA==.Spywar:BAAALgAECgYJCAABLgAECggJHwARACkXAA==.',
St='Starlighter:BAABLgAECn8qAAMfAAkJiAveKwB2AQAfAAkJiAveKwB2AQAYAAYJGQXPSwC0AAABLgAFFAIJAgAIAAAAAA==.Starsomave:BAAALgAFFAIJAgAAAA==.Steen:BAAALgAECgMJAwAAAA==.Stinkylev:BAAALgAFFAEJAQABLgAFFAcJFQAXAFQbAA==.Strentor:BAAALgAECgEJAQAAAA==.',
Su='Sunshinë:BAAALgAECgEJAgAAAA==.Supressor:BAAALgADCgQJCAABLgAECgIJAgAIAAAAAA==.',
Sy='Sylvester:BAAALgADCgIJAgAAAA==.',
['Sé']='Sérolis:BAAALgADCgEJAQAAAA==.',
Ta='Taehausx:BAACLgAFFH86AAIOAAkJDyYRAABzAwAOAAkJDyYRAABzAwAuAAQKfzAAAw4ACQlSJB8GACUDAA4ACQlSJB8GACUDACAAAgk5HjddAKIAAAAA.Tarmo:BAAALgADCgYJFgAAAA==.',
Te='Telesto:BAAALgAECgIJAgABLgAFFAYJGwACAHEjAA==.Templeton:BAAALgADCgMJAwAAAA==.Tenath:BAABLgAECn8bAAIKAAcJsRK0KAA3AQAKAAcJsRK0KAA3AQAAAA==.',
Th='Thaleon:BAAALgAECgcJDgAAAA==.Tharella:BAAALgAECgYJCwAAAA==.Thauriel:BAAALgAECgYJCAAAAA==.Thrumple:BAAALgADCgYJCgAAAA==.',
Ti='Tipz:BAAALgAECgIJAwABLgAECgUJBQAIAAAAAA==.Titania:BAABLgAECn8eAAIjAAkJTAa9QAB1AQAjAAkJTAa9QAB1AQAAAA==.',
Tr='Trollztoll:BAAALgAECgIJAgAAAA==.',
Tu='Tuulk:BAAALgADCgIJAgAAAA==.',
Ty='Typical:BAAALgADCgcJCwAAAA==.',
Ug='Uggoorc:BAACLgAFFH8RAAINAAQJIwvHTQAQAQANAAQJIwvHTQAQAQAuAAQKfx8AAg0ACAnmHAMwABwCAA0ACAnmHAMwABwCAAAA.Uggotroll:BAAALgAECgUJCwABLgAFFAQJEQANACMLAA==.',
Un='Unholylord:BAAALgAECggJDAABLgAFFAgJIQAfAGkgAA==.',
Ut='Uthok:BAAALgADCgcJBwAAAA==.',
Va='Vacalocà:BAABLgAECn8UAAITAAgJUQ1gGQBEAQATAAgJUQ1gGQBEAQAAAA==.Valerian:BAAALgAECggJDQAAAA==.Validori:BAAALgADCgEJAQAAAA==.Van:BAAALgAECggJCAAAAA==.Vaultkey:BAAALgADCgIJAwAAAA==.',
Ve='Vegesha:BAAALgAECgEJAgAAAA==.Veinke:BAABLgAECn8VAAIEAAkJ+w5gCwClAQAEAAkJ+w5gCwClAQAAAA==.Vengefullev:BAAALgADCgUJBwABLgAFFAcJFQAXAFQbAA==.Venin:BAAALgAECgYJCwAAAA==.Vessarind:BAAALgADCgEJAgAAAA==.',
Vi='Vitora:BAAALgAECgYJEQAAAA==.',
Vo='Voidkurn:BAAALgADCgYJCQAAAA==.Von:BAAALgADCgIJAgAAAA==.',
Vy='Vyse:BAAALgADCgYJBgAAAA==.',
Wa='Waally:BAAALgAECgcJEgAAAA==.Wahgwan:BAAALgAECgMJAwAAAA==.Waleran:BAAALgADCgIJAgAAAA==.Warrdaddy:BAAALgAECgUJDAABLgADCgcJBwAIAAAAAA==.Warriorbp:BAAALgADCgkJFwAAAA==.Wattz:BAAALgAECgYJBgAAAA==.',
We='Weebsora:BAAALgAECgYJEgAAAA==.',
Wo='Worldtree:BAABLgAECn8WAAIQAAYJnw+GZQArAQAQAAYJnw+GZQArAQAAAA==.',
Wy='Wynne:BAAALgAECgcJCAAAAA==.',
Xa='Xaelthira:BAAALgAECgYJCgAAAA==.',
Xe='Xerath:BAAALgADCgYJCAAAAA==.',
Xi='Xips:BAAALgADCgMJAwABLgAECgUJBQAIAAAAAA==.',
Xo='Xoru:BAAALgADCgYJBgAAAA==.Xoruk:BAAALgADCgQJBAABLgAFFAIJAgAIAAAAAA==.Xorun:BAAALgAECgEJAQABLgAFFAIJAgAIAAAAAA==.',
Xz='Xzarrion:BAAALgAECgEJAQAAAA==.',
Ya='Yadhi:BAABLgAECn8XAAQOAAYJihbkMgA1AQAOAAUJihbkMgA1AQAXAAYJoBCeUAAsAQAgAAUJ3AdEaACFAAAAAA==.',
Ye='Yetkin:BAAALgAECgYJDQAAAA==.',
Yi='Yifftron:BAAALgAECgYJBgABLgAECggJGwANAAogAA==.Yimomo:BAABLgAECn8cAAMYAAkJhRUbLgCMAQAYAAkJhRUbLgCMAQAfAAcJtwcJTgDYAAAAAA==.',
Yo='Yoshira:BAAALgAECgMJAwABLgAECggJDQAIAAAAAA==.',
Yz='Yzra:BAAALgAECgQJBQAAAA==.',
Za='Zalconn:BAACLgAFFH8YAAMeAAUJVyZBDgCwAQAeAAUJVyZBDgCwAQAkAAIJDRdyDACZAAAuAAQKfysAAx4ACQkcJjoDAGwDAB4ACQnZJToDAGwDACQAAQneJoIbAHEAAAAA.Zarrona:BAABLgAECn8mAAMkAAgJEB8ZBQAeAgAkAAcJtR0ZBQAeAgAeAAcJkRpQHwCbAQAAAA==.Zayah:BAABLgAECn8XAAIRAAgJyRSMKQCkAQARAAgJyRSMKQCkAQAAAA==.',
Zi='Zinmaris:BAAALgAFFAIJAgAAAA==.Zivanka:BAAALgAECgcJCgABLgAECgcJDwAIAAAAAA==.',
Zn='Znasty:BAABLgAECn8tAAIeAAkJBSSoAgAuAwAeAAkJBSSoAgAuAwAAAA==.',
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
