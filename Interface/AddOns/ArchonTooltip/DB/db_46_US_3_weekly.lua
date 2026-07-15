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

local lookup = {'Mage-Frost','Paladin-Retribution','Warrior-Arms','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Unknown-Unknown','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Protection','Hunter-BeastMastery','Monk-Brewmaster','Warlock-Affliction','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Druid-Feral','Druid-Balance','DeathKnight-Unholy','Warlock-Destruction','Monk-Mistweaver','Priest-Holy','Druid-Restoration','Druid-Guardian','Mage-Arcane','Hunter-Marksmanship','Hunter-Survival','Rogue-Subtlety','Priest-Shadow','Monk-Windwalker','Evoker-Preservation','Priest-Discipline','Paladin-Holy','Rogue-Outlaw','Shaman-Enhancement','DeathKnight-Frost','DeathKnight-Blood',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=46,date='2026-07-12',data={Ab='Abeblinkin:BAABLgAECn9NAAIBAAkJkSIdAgDdAgABAAkJkSIdAgDdAgAAAA==.',
Ac='Accursed:BAAALgAECgEJAQAAAA==.',
Ad='Adcrusty:BAAALgAECgEJAQAAAA==.',
Ae='Aegrias:BAABLgAECn8hAAICAAkJEx48JwCJAgACAAkJEx48JwCJAgAAAA==.Aeledron:BAAALgADCgQJBQAAAA==.Aerodria:BAABLgAECn9pAAICAAkJCxiGBgDGAQACAAkJCxiGBgDGAQAAAA==.',
Aj='Ajm:BAABLgAFFH8LAAIDAAQJmxT6GQAWAQADAAQJmxT6GQAWAQAAAA==.',
Ak='Akarii:BAAALgAECgYJEAAAAA==.Akeno:BAABLgAECn8VAAIEAAgJQCNZAQAYAwAEAAgJQCNZAQAYAwAAAA==.Akiaura:BAAALgAECgYJEgAAAA==.Akime:BAAALgAECgYJDwAAAA==.Akudama:BAABLgAECn8tAAMFAAkJnxprEABkAgAFAAkJnxprEABkAgAGAAIJqQkFNwBfAAABLgAFFAgJLgAHACQZAA==.',
Al='Alarm:BAAALgADCgEJAQABLgADCgcJCwAIAAAAAA==.Albince:BAAALgADCgIJAgAAAA==.Aldanil:BAAALgAECggJEAAAAA==.Aligh:BAAALgAECgEJAQAAAA==.Alisae:BAAALgADCgMJAwAAAA==.Alma:BAAALgAECgUJBQAAAA==.Alye:BAAALgAECgcJEAAAAA==.',
Am='Amellis:BAAALgAECgUJCQAAAA==.',
An='Ananac:BAAALgADCgEJAQAAAA==.Andreasham:BAAALgADCgEJAQAAAA==.Andrius:BAAALgAECgQJBQAAAA==.Annisseda:BAACLgAFFH8fAAMJAAcJDh1ECQDKAQAJAAYJXh9ECQDKAQADAAMJKxXIEgCFAAAuAAQKfysAAwkACQmLJP0HAN8CAAkACQmLJP0HAN8CAAMAAQl9ITFkAFkAAAAA.',
Ar='Aradril:BAAALgADCgcJCwAAAA==.Arktos:BAAALgAECgYJDQAAAA==.Arrhythmia:BAAALgAECgkJJQABLgAFFAgJKAAIAAAAAQ==.Articuno:BAAALgAECgYJEQAAAA==.',
As='Ashrak:BAAALgAECgQJBAAAAA==.Ashér:BAAALgAECgEJAQAAAA==.Astaulis:BAAALgADCgUJCAAAAA==.',
Ax='Axelle:BAAALgAECggJDwAAAA==.',
Az='Azzy:BAACLgAFFH8uAAIJAAgJ2hqUAgBsAgAJAAgJ2hqUAgBsAgAuAAQKfz4AAgkACQnlJXgCAJMDAAkACQnlJXgCAJMDAAAA.',
Ba='Babyboomie:BAAALgAECgUJBwAAAA==.Bagagwa:BAAALgADCgcJCAAAAA==.Bal:BAABLgAECn8kAAQKAAgJVhXKHQDRAQAKAAgJ8xLKHQDRAQALAAYJWQ/EkwD5AAAEAAIJBiFQKQBeAAAAAA==.Balam:BAAALgADCgEJAQAAAA==.Balana:BAAALgAECgUJCAAAAA==.Bambudda:BAAALgAFFAIJAgAAAA==.Bananski:BAABLgAECn8VAAMMAAYJUQ2vJADjAAAMAAUJIA+vJADjAAACAAYJXwa49QDEAAAAAA==.Bandu:BAAALgADCgEJAgAAAA==.Barkeep:BAABLgAECn8aAAINAAkJaw+WOADMAQANAAkJaw+WOADMAQAAAA==.Bassoon:BAAALgAECgMJAwABLgAFFAIJBQAOAE4RAA==.',
Be='Beeflocks:BAABLgAECn8iAAIPAAkJMhxABwD/AQAPAAkJMhxABwD/AQAAAA==.Beefpile:BAAALgADCgUJBQAAAA==.Bekarn:BAABLgAECn8YAAMQAAcJeAofUwA5AQAQAAcJeAofUwA5AQARAAMJ7AhzegBaAAAAAA==.Benafflock:BAAALgAECgMJAwAAAA==.Bennafflock:BAAALgAECgUJCwAAAA==.Bergz:BAAALgAECgMJAgAAAA==.',
Bh='Bhp:BAAALgADCgMJAwABLgAECgMJAwAIAAAAAA==.',
Bi='Bigbleu:BAAALgAECgUJCQABLgAECggJJwASAHkdAA==.Bigdh:BAAALgAECgYJDgAAAA==.Bigdraco:BAAALgADCgQJBAAAAA==.Bigpapapump:BAAALgAECgEJAQAAAA==.Bigxthaplug:BAAALgAECgYJCQAAAA==.Bilboswagins:BAABLgAECn8UAAIJAAcJyxwLIwA9AgAJAAcJyxwLIwA9AgAAAA==.Billski:BAAALgAECgcJCQAAAA==.Billyspike:BAABLgAECn8YAAMTAAYJ0RrjDQDVAQATAAYJ0RrjDQDVAQAUAAEJkhKtigA2AAABLgAECgkJEwAIAAAAAA==.Billyspiked:BAAALgAECgIJAgABLgAECgkJEwAIAAAAAA==.Billyspikedh:BAAALgADCgMJAwABLgAECgkJEwAIAAAAAA==.Billyspikeev:BAAALgADCgYJBgABLgAECgkJEwAIAAAAAA==.Billyspikepd:BAAALgAECgkJEwAAAA==.Billyspikepr:BAAALgAECggJEgABLgAECgkJEwAIAAAAAA==.Billyspikerg:BAAALgADCgIJAgABLgAECgkJEwAIAAAAAA==.',
Bl='Blammo:BAAALgADCgcJCQAAAA==.Blobcat:BAABLgAECn8cAAIUAAcJSx/9AgCtAQAUAAcJSx/9AgCtAQAAAA==.Blobknight:BAAALgADCgEJAQAAAA==.Blobpally:BAACLgAFFH8NAAICAAQJ0RT9TgAQAQACAAQJ0RT9TgAQAQAuAAQKfyAAAgIABwm7IW0dALoCAAIABwm7IW0dALoCAAAA.Bloodhase:BAACLgAFFH8IAAIVAAQJLBiIKgAIAQAVAAQJLBiIKgAIAQAuAAQKfxgAAhUABwkbEW2XADoBABUABwkbEW2XADoBAAAA.Bloodprince:BAAALgAECgMJAwAAAA==.Bluecard:BAACLgAFFH8eAAIHAAcJRxzIIwC9AQAHAAcJRxzIIwC9AQAuAAQKfywABAcACQl+IcYPAM4CAAcACQl+IcYPAM4CABYAAwnVGMg5AM0AAA8AAQkXIY0nAFMAAAAA.',
Bo='Bokunh:BAAALgAECgYJEgAAAA==.Bookofmoon:BAAALgAECgUJBQAAAA==.Boomywhoomy:BAAALgAECgIJBQAAAA==.Bootstrap:BAAALgAECgkJCQAAAA==.Bothenheim:BAACLgAFFH8cAAMCAAcJVSFsEwDQAQACAAcJVSFsEwDQAQAMAAMJQQxSEwBfAAAuAAQKfyYAAgIACQmAIgYVAMQCAAIACQmAIgYVAMQCAAAA.Bowdaddy:BAAALgADCgcJBwAAAA==.Boxtribution:BAAALgAECgMJBQAAAA==.Boxxman:BAAALgAECgcJAQAAAA==.',
Br='Breakdown:BAAALgAECgIJAgAAAA==.Brewsimmons:BAABLgAFFH8XAAIXAAkJzhKCBQAxAgAXAAkJzhKCBQAxAgAAAA==.Brüisér:BAACLgAFFH8FAAIMAAIJxwbJFABUAAAMAAIJxwbJFABUAAAuAAQKfyUAAgwACQluD5IYAFgBAAwACQluD5IYAFgBAAAA.',
Bu='Bublz:BAAALgAECgcJBwAAAA==.Bumpinuglies:BAAALgAECgEJAQAAAA==.',
Ca='Callamdrake:BAAALgAECgEJAQAAAA==.Callamsvoid:BAAALgAECgMJCAAAAA==.Camazotz:BAAALgADCgkJCgAAAA==.Capie:BAAALgAECgkJEAAAAA==.Carathea:BAABLgAECn8iAAIYAAgJMSCCDACLAgAYAAgJMSCCDACLAgAAAA==.Cardstock:BAAALgAECggJCAABLgAFFAgJKAAIAAAAAQ==.Carrotbear:BAAALgADCgQJBAAAAA==.Cassiopeià:BAAALgAECgMJAwAAAA==.Caylen:BAACLgAFFH8aAAIZAAcJhB6tCwA4AgAZAAcJhB6tCwA4AgAuAAQKfyAAAhkACAm3HkIRAK0CABkACAm3HkIRAK0CAAAA.Cayth:BAACLgAFFH8aAAMHAAUJ0CDCOABnAQAHAAUJux3COABnAQAPAAEJJR+qGABcAAAuAAQKfysAAwcACQnMIakFAGIDAAcACQnMIakFAGIDABYAAgkLAx9VAG8AAAAA.',
Ce='Cemie:BAAALgADCgcJBwAAAA==.Centralia:BAAALgADCgYJBwAAAA==.Centri:BAACLgAFFH8kAAIBAAkJlxqRAwDQAgABAAkJlxqRAwDQAgAuAAQKfyQAAgEACQlGJRYaAA8DAAEACQlGJRYaAA8DAAAA.Cerestus:BAAALgADCgMJAwAAAA==.',
Ch='Chadbear:BAABLgAECn8VAAMaAAgJRBU8GQCFAQAaAAgJRBU8GQCFAQATAAMJwQm6NAAwAAAAAA==.Chadtones:BAAALgAECgQJBAAAAA==.Chimueloh:BAAALgADCgQJBAAAAA==.Chiron:BAAALgADCgIJAgAAAA==.Chowa:BAAALgAFFAMJAwAAAA==.Chrleone:BAAALgAECgIJAwAAAA==.Chu:BAAALgAECgEJAQAAAA==.',
Cl='Cleverlev:BAABLgAECn8aAAIbAAYJ/RQQBwBDAQAbAAYJ/RQQBwBDAQABLgAFFAgJFgAXAPgaAA==.',
Co='Colapse:BAAALgAECgEJAQAAAA==.Colivism:BAABLgAECn8kAAIBAAgJpRaleQDeAQABAAgJpRaleQDeAQAAAA==.Colívis:BAAALgAECgQJBQAAAA==.Commodorecdx:BAAALgADCgcJBwAAAA==.Cotali:BAAALgADCgUJBQABLgAECggJIgAYADEgAA==.',
Cr='Crackfiend:BAAALgADCgUJBwAAAA==.Crispi:BAAALgADCgYJBAAAAA==.Cruellev:BAABLgAECn8UAAIPAAUJyA5PBADiAAAPAAUJyA5PBADiAAABLgAFFAgJFgAXAPgaAA==.Crymbrulay:BAAALgAECgYJCAAAAA==.',
Cu='Cuurtis:BAAALgADCgEJAQAAAA==.',
Cz='Czernobog:BAAALgAECgMJAwAAAA==.',
Da='Daedrenda:BAAALgAECgMJBAAAAA==.Daeland:BAABLgAECn8yAAIJAAkJ0hDjJQDJAQAJAAkJ0hDjJQDJAQAAAA==.Dakky:BAAALgAFFAMJAQAAAA==.Dandakian:BAAALgAECgEJAgAAAA==.',
De='Deadwrs:BAAALgADCgIJAgAAAA==.Deathbruiser:BAAALgAECgQJBAAAAA==.Deathsgrace:BAAALgAECgkJCQAAAA==.Deathtank:BAAALgAFFAIJBAAAAA==.Deathtolife:BAAALgAECgQJCAAAAA==.Decima:BAABLgAECn8pAAIUAAkJ4A0+BgAdAQAUAAkJ4A0+BgAdAQAAAA==.Degrance:BAAALgAECgUJBQAAAA==.Demeter:BAACLgAFFH8fAAQNAAcJ8Bh0MQBMAQANAAUJfCF0MQBMAQAcAAIJ2gWBIwCSAAAdAAEJ/iODEABqAAAuAAQKfyIABA0ACQlYIuASAKACAA0ACAk6HuASAKACABwABglxILUoAOQBAB0AAQkoIM9TAF8AAAAA.Demonpunter:BAAALgAFFAIJBAABLgAFFAgJHQAHAMYfAA==.Dewussi:BAACLgAFFH8TAAICAAQJnAnpWwD4AAACAAQJnAnpWwD4AAAuAAQKfyQAAwwABwniHYENAO8BAAwABwk4GYENAO8BAAIABwlnG29pAJwBAAAA.',
Di='Diablita:BAAALgAECgEJAQAAAA==.Dicethrower:BAAALgAECgQJBAAAAA==.Dinkltn:BAAALgAECgUJCgAAAA==.Dinoscarr:BAAALgAECgYJDwAAAA==.Dixiinormis:BAAALgAECgkJCQABLgAECgkJTQABAJEiAA==.',
Dj='Djholy:BAAALgAECgcJDwABLgAECgcJEAAIAAAAAA==.',
Do='Dotmaxxing:BAAALgAFFAEJAgAAAA==.Dotsndash:BAAALgAECgUJBQAAAA==.',
Dp='Dpsshaman:BAABLgAECn8cAAIRAAkJ6x6fCgC1AgARAAkJ6x6fCgC1AgAAAA==.',
Dr='Drarmaku:BAAALgAECgIJAgAAAA==.Dreadingfate:BAAALgAECgkJEAAAAA==.Drscholar:BAAALgAECgIJAwAAAA==.Druidpwnz:BAAALgADCgMJAwAAAA==.',
Du='Duber:BAAALgAECgUJBgAAAA==.Dungorogue:BAABLgAECn8wAAIeAAgJcRAJHgClAQAeAAgJcRAJHgClAQAAAA==.Dustln:BAAALgAECgEJAQAAAA==.',
Dy='Dyonne:BAAALgADCgEJAgAAAA==.',
['Dé']='Déwéy:BAAALgAECgIJAgABLgAFFAQJEwACAJwJAA==.',
El='Elbone:BAAALgADCgUJBQAAAA==.Elidia:BAAALgADCgcJBwAAAA==.Elinia:BAABLgAECn8zAAMYAAkJqxGpIwClAQAYAAgJqRKpIwClAQAfAAkJgQbSNwA2AQAAAA==.Elivoker:BAAALgAECgYJAwAAAA==.Elmdor:BAAALgAECgcJDQAAAA==.Elyndra:BAAALgAFFAEJAQAAAA==.',
En='Eniacoc:BAAALgAECgkJCQAAAA==.Enlag:BAAALgAECgMJAwAAAA==.',
Et='Etriganna:BAAALgAECgEJAQAAAA==.',
Ev='Evilwitch:BAAALgADCgEJAQAAAA==.Evistiah:BAAALgAECgEJAQAAAA==.',
Ex='Excentric:BAABLgAECn8ZAAICAAgJdB6XPQAOAgACAAgJdB6XPQAOAgABLgAFFAkJJAABAJcaAA==.Excerpt:BAAALgAECgMJAwABLgAFFAkJJAABAJcaAA==.Exortus:BAAALgAFFAMJAwABLgAFFAcJHAACAFUhAA==.',
Fa='Falloutman:BAAALgAECgEJAQAAAA==.Farther:BAAALgAECgUJBwABLgAFFAQJBgAWANIKAA==.Farëeya:BAAALgADCgcJDAAAAA==.Fayne:BAAALgAECgUJCQAAAA==.',
Fe='Fellirane:BAAALgADCgUJBQAAAA==.Fernsama:BAAALgAECgYJCAAAAA==.',
Fi='Fishton:BAAALgADCgUJCwAAAA==.',
Fl='Flauros:BAABLgAECn8XAAILAAcJ4Q3khgASAQALAAcJ4Q3khgASAQAAAA==.',
Fr='Fraternite:BAAALgAECgkJDgAAAA==.Froackeh:BAAALgAECggJBwAAAA==.Froackie:BAAALgAECgYJEAABLgAECggJBwAIAAAAAA==.Fruto:BAACLgAFFH8FAAIOAAIJThGdRQCKAAAOAAIJThGdRQCKAAAuAAQKfzEAAg4ACQnLF/ETABACAA4ACQnLF/ETABACAAAA.',
Ga='Gabriellad:BAAALgAFFAIJBAAAAA==.Garzislao:BAAALgAECggJEAAAAA==.',
Gh='Ghostfox:BAAALgAECgMJAwAAAA==.',
Gi='Giterdonee:BAACLgAFFH8cAAIJAAgJKxb2CADPAQAJAAgJKxb2CADPAQAuAAQKfyEAAgkACQn9IKEEAF8DAAkACQn9IKEEAF8DAAAA.',
Gl='Gleymoulleon:BAAALgAECgQJBwAAAA==.',
Go='Goblinbeans:BAACLgAFFH8LAAIQAAUJlQiPBQBzAQAQAAUJlQiPBQBzAQAuAAQKfxcAAhAACAlLFqckAAMCABAACAlLFqckAAMCAAEuAAUUCQkXABcAzhIA.Goku:BAAALgAECgQJBAAAAA==.Gotchoo:BAAALgAFFAEJAgABLgAFFAMJAwAIAAAAAA==.Gothmommy:BAAALgADCgIJAgAAAA==.',
Gr='Greenbeans:BAAALgAECgUJCQABLgAFFAkJFwAXAM4SAA==.Grence:BAAALgAECgUJDAABLgAECgcJEwAIAAAAAA==.Grimreaper:BAABLgAECn8lAAMQAAcJNw3OXABGAQAQAAcJNw3OXABGAQARAAQJPwLJewBVAAAAAA==.Griphöök:BAAALgAECgEJAgAAAA==.Groldin:BAAALgAECgQJBgAAAA==.Groshkar:BAAALgADCgcJCwAAAA==.Grumble:BAAALgAFFAEJAQAAAA==.',
['Gõ']='Gõtchoo:BAAALgAFFAMJAwAAAA==.',
Ha='Hairball:BAABLgAECn8iAAIdAAkJkRQTEwAOAgAdAAkJkRQTEwAOAgAAAA==.Hallona:BAAALgADCgMJAwAAAA==.Hammerthumb:BAAALgAECgUJDAABLgAFFAIJBgATAPkHAA==.Hanniy:BAAALgAECgIJAQABLgAECgIJAgAIAAAAAA==.Happydavis:BAAALgADCgUJBQAAAA==.',
Ho='Hotdoggin:BAAALgADCgYJDAAAAA==.',
Hy='Hyara:BAABLgAECn8rAAINAAkJghziDwC8AgANAAkJghziDwC8AgAAAA==.',
['Hì']='Hìm:BAAALgAECgMJBAAAAA==.',
['Hù']='Hùñtarð:BAAALgADCgYJEQAAAA==.',
Ib='Ibefarmin:BAAALgAECgEJAQAAAA==.',
Ic='Icecreammen:BAAALgADCgQJBAAAAA==.Iceshadow:BAACLgAFFH8MAAIXAAQJ/RTjHQCqAAAXAAQJ/RTjHQCqAAAuAAQKfxYAAxcABwnjHq0VAG0CABcABwnjHq0VAG0CACAAAgkrAqLDAA8AAAAA.Icobal:BAAALgADCgYJCAAAAA==.',
Il='Illisa:BAAALgADCgMJAwAAAA==.',
Ir='Irongallo:BAAALgADCgEJAQAAAA==.',
Ix='Ixtlipactzin:BAAALgAECgIJAgAAAA==.',
Ja='Jabdis:BAAALgADCgEJAQAAAA==.Jabzulsor:BAAALgAECgEJAQAAAA==.Jacopo:BAABLgAECn8XAAIVAAgJtw43hABbAQAVAAgJtw43hABbAQAAAA==.',
Je='Jeffster:BAAALgAFFAIJBAAAAA==.',
Jo='Jocko:BAAALgAECgMJAwAAAA==.Jordi:BAABLgAECn89AAINAAkJ2B51GQCNAgANAAkJ2B51GQCNAgAAAA==.',
Ju='Jutti:BAAALgAECgQJDAAAAA==.',
Ka='Kaellen:BAAALgADCgUJBQAAAA==.Kahnman:BAAALgADCgUJBQAAAA==.Kaka:BAAALgAECgcJEwAAAA==.Kalet:BAAALgAECgMJAwAAAA==.Kaluaruun:BAAALgAECgEJAQAAAA==.Kandinsky:BAAALgADCgIJAgAAAA==.Kanree:BAACLgAFFH8vAAMXAAcJrQrKHQCCAQAXAAcJrQrKHQCCAQAgAAEJ5gYIRgA0AAAuAAQKfz4AAxcACQkiG0oLAJwCABcACQkiG0oLAJwCACAAAQknB7KpACgAAAAA.Kartiri:BAACLgAFFH8bAAMhAAcJnxZ8DQDHAQAhAAYJ0Bd8DQDHAQAFAAUJ4g1TSQCmAAAuAAQKfy8ABCEACQmRHVoGAN4CACEACQmRHVoGAN4CAAUABQnWFm80AGEBAAYABQkPGM0lAPUAAAAA.Kawhi:BAAALgAFFAEJAQAAAA==.',
Ke='Kea:BAACLgAFFH8hAAMiAAUJ5iP7BwDJAQAiAAUJ5iP7BwDJAQAYAAIJvRqrJACXAAAuAAQKfzwAAyIACQkNJr0AAOEDACIACQkNJr0AAOEDABgAAwlTI2A1AC4BAAAA.Keedoril:BAAALgADCgUJCgAAAA==.Keicelinis:BAABLgAECn8WAAILAAYJ9xLIfgAiAQALAAYJ9xLIfgAiAQAAAA==.Keratos:BAAALgAECgYJCQAAAA==.',
Kh='Khaalid:BAAALgAECgYJCgAAAA==.Khran:BAAALgADCgIJAgAAAA==.',
Ki='Kickingfluff:BAAALgADCgIJAgAAAA==.Kimjoonsang:BAAALgAECgEJAQABLgAECgEJAQAIAAAAAA==.Kipz:BAAALgAECgUJBQAAAA==.Kittyboy:BAAALgADCgUJBQAAAA==.',
Ko='Kookykrook:BAABLgAFFH8IAAIFAAQJrQ8yNADyAAAFAAQJrQ8yNADyAAAAAA==.Korxin:BAACLgAFFH8gAAINAAgJuRSKEQDXAQANAAgJuRSKEQDXAQAuAAQKfysAAg0ACQkpI+oEAD8DAA0ACQkpI+oEAD8DAAAA.Kozmikfrost:BAAALgADCgEJAQAAAA==.',
Kr='Kreizikat:BAACLgAFFH8PAAIZAAUJDxPFIQBKAQAZAAUJDxPFIQBKAQAuAAQKfzIAAhkACAnJITQOAMgCABkACAnJITQOAMgCAAAA.Krinn:BAAALgAECgYJCQAAAA==.Krios:BAAALgADCgQJBAAAAA==.',
Ku='Kurquaan:BAABLgAECn8aAAMaAAkJgxMJGACRAQAaAAkJgxMJGACRAQAUAAQJEwyWVgDKAAAAAA==.',
La='Lanstan:BAAALgAECgQJBAAAAA==.',
Le='Leilar:BAAALgAECgIJAwAAAA==.Leron:BAAALgAECgYJCAAAAA==.Levitticus:BAACLgAFFH8GAAIjAAMJ2R1+IwAEAQAjAAMJ2R1+IwAEAQAuAAQKfzkAAiMACQlCH0sGACgDACMACQlCH0sGACgDAAEuAAUUCAkWABcA+BoA.',
Li='Liale:BAAALgAFFAEJAQAAAA==.Lideyn:BAAALgAECgIJAgAAAA==.Lidrel:BAAALgAECgYJBgAAAA==.Lightbreath:BAAALgAECgEJAQAAAA==.Lightfury:BAAALgAECgQJBwABLgAECgYJCAAIAAAAAA==.Limone:BAAALgADCgUJBQAAAA==.',
Lo='Loinari:BAABLgAECn8cAAIUAAcJyQhDDACaAAAUAAcJyQhDDACaAAAAAA==.Lokano:BAAALgAECgUJBwAAAA==.',
Lu='Luaru:BAAALgAECgEJAQAAAA==.Ludmylha:BAAALgAFFAEJAQAAAA==.Luisda:BAAALgADCgUJBQAAAA==.Lulak:BAAALgAECgQJCQAAAA==.Lull:BAABLgAECn8tAAMWAAkJ6A5ICwCMAQAWAAkJ6A5ICwCMAQAHAAEJ4QLaYwEdAAAAAA==.Luthin:BAAALgADCgUJBgAAAA==.',
Ly='Lyadre:BAAALgAECgIJAgAAAA==.Lynai:BAAALgADCgIJAgAAAA==.Lyndis:BAAALgAECgQJBAAAAA==.',
Ma='Madness:BAAALgAECgMJAwAAAA==.Magejaf:BAAALgADCgcJDQABLgAECggJHwAPAIgXAA==.Magidragon:BAABLgAECn8eAAIBAAkJcA94CACSAQABAAkJcA94CACSAQAAAA==.Mandrah:BAAALgADCgQJBQAAAA==.Maybell:BAAALgAECgQJBwAAAA==.',
Md='Mdavis:BAAALgAECgcJBwAAAA==.',
Me='Melt:BAACLgAFFH8uAAMHAAgJJBmQFwAEAgAHAAcJQhmQFwAEAgAWAAEJchgiHABbAAAuAAQKfz4AAwcACQl+I/8JAAEDAAcACQl+I/8JAAEDABYABAmoEncsAAwBAAAA.Mepha:BAABLgAFFH8KAAIVAAQJYwxSPQDMAAAVAAQJYwxSPQDMAAAAAA==.Metons:BAAALgAECggJDQAAAA==.Metroboofin:BAAALgAECgMJAQAAAA==.',
Mi='Midei:BAAALgADCgkJFgAAAA==.Midriffluvr:BAAALgAECgQJBwAAAA==.Mikasa:BAAALgADCgEJAQAAAA==.Mike:BAACLgAFFH8GAAIWAAQJ0gokAwD6AAAWAAQJ0gokAwD6AAAuAAQKfxUAAxYABwkGIOIAAPIBABYABgkFIuIAAPIBAA8ABAlICiAGAKcAAAAA.Mimosa:BAAALgADCgYJCgABLgAECgYJCAAIAAAAAA==.Mirna:BAAALgAECgMJBgAAAA==.Misfitdh:BAAALgAECgEJAQAAAA==.Misfitdk:BAAALgAECgEJBAAAAA==.Misfitdots:BAAALgAECgEJAQAAAA==.Misfitmagi:BAAALgAECgEJBAAAAA==.Misfitmonk:BAAALgAECgEJAgAAAA==.Misfittotem:BAAALgAECgEJAwAAAA==.Missfire:BAAALgAECgkJCQAAAA==.Missðirect:BAAALgAECgEJAQABLgAFFAIJAwAIAAAAAA==.Mistfox:BAAALgAECggJEgAAAA==.',
Mo='Mobiouse:BAAALgADCgYJBgAAAA==.Mollieann:BAAALgAECgQJBgAAAA==.Mommon:BAAALgAECgYJCAAAAA==.Moonraisin:BAAALgAECgMJBQAAAA==.Morrighan:BAAALgADCgQJBQAAAA==.',
Mu='Mukdron:BAAALgADCgIJAgAAAA==.',
['Mâ']='Mâlus:BAAALgAECgYJEwAAAA==.',
Na='Nadra:BAAALgAFFAIJAgAAAA==.Naminé:BAAALgADCgMJAwABLgAFFAQJCAAkAH0WAA==.Nattyrav:BAACLgAFFH8XAAIlAAUJ/BwCAgBjAQAlAAUJ/BwCAgBjAQAuAAQKfygAAyUACQkbH8ADAO4CACUACQlnHsADAO4CABEABgnHG/03AFgBAAAA.Nawari:BAAALgAECgIJAwAAAA==.',
Ne='Nemonk:BAACLgAFFH8OAAIgAAMJpx2CBwD+AAAgAAMJpx2CBwD+AAAuAAQKf1oAAyAACQkeH0AGAOgCACAACQkeH0AGAOgCABcAAQlQA1bWABwAAAAA.Neryssa:BAACLgAFFH8bAAQHAAgJhhvODgBFAgAHAAgJtRrODgBFAgAWAAEJYRVKHgBXAAAPAAEJpRwyHABVAAAuAAQKfzoAAwcACQnYJOkIAAwDAAcACAlvJOkIAAwDABYABAkpJPUYAIMBAAAA.',
Ni='Nickjamez:BAAALgADCgYJBgAAAA==.Nimh:BAAALgADCgUJCQAAAA==.Nipz:BAAALgAECgEJAQABLgAECgUJBQAIAAAAAA==.',
No='Nocter:BAABLgAECn8hAAQHAAkJPx1nNwAuAgAHAAcJ9RxnNwAuAgAPAAUJUiCTCwCBAQAWAAMJ9g0APgC8AAAAAA==.Noqtir:BAAALgAECgUJCgAAAA==.Not:BAAALgADCgcJAgAAAA==.Noyoo:BAAALgADCgEJAQAAAA==.',
Nu='Nunca:BAAALgAECgEJAQAAAA==.',
Ny='Nymura:BAABLgAECn8kAAICAAgJQgrTpwArAQACAAgJQgrTpwArAQAAAA==.',
['Nä']='Näesthra:BAABLgAECn8kAAIYAAgJdBhpHADjAQAYAAgJdBhpHADjAQAAAA==.',
Oa='Oakhugger:BAACLgAFFH8GAAITAAIJ+QdqCQBpAAATAAIJ+QdqCQBpAAAuAAQKfyQAAxMACQlYEN0PALkBABMACQlYEN0PALkBABQAAQkAAE2xAAAAAAAA.',
Ob='Obelisk:BAAALgADCgYJBgAAAA==.Obelix:BAAALgAECgEJAQAAAA==.',
Ok='Okarun:BAABLgAECn8jAAILAAcJTB5nQQDuAQALAAcJTB5nQQDuAQABLgAFFAQJCAAkAH0WAA==.',
Ol='Oldeone:BAAALgAECgMJBAAAAA==.Olillivia:BAAALgADCgIJAQAAAA==.Olyvivia:BAABLgAFFH8GAAImAAIJuwInEQBnAAAmAAIJuwInEQBnAAAAAA==.',
Om='Omgega:BAABLgAECn9EAAICAAgJWhuTNwAjAgACAAgJWhuTNwAjAgAAAA==.',
On='Onichan:BAAALgAECgYJCQABLgAFFAgJFgARAAYZAA==.Onimeek:BAABLgAECn9VAAMKAAkJEyBqBwC7AgAKAAkJEyBqBwC7AgALAAIJPAleDgE7AAAAAA==.',
Or='Oragar:BAAALgAECgQJBAAAAA==.Oryn:BAAALgAFFAEJAwABLgAFFAIJBgABACcVAA==.Oryx:BAAALgAECgEJAwAAAA==.',
Pa='Pallywahwah:BAAALgAFFAEJAQAAAA==.Palpitations:BAAALgAECgcJEAAAAA==.Paper:BAAALgAFFAgJKAAAAQ==.Paudetunia:BAAALgADCgIJAgAAAA==.',
Pe='Peacefullev:BAACLgAFFH8WAAMXAAgJ+BpdCwBRAgAXAAgJ+BpdCwBRAgAgAAEJKQuFRAA2AAAuAAQKfyYAAxcACAn8Hq4OALUCABcACAn8Hq4OALUCACAABwnDFY4mAIEBAAAA.Peiko:BAAALgADCgIJAgAAAA==.Pelagius:BAAALgADCgYJBwAAAA==.Penance:BAAALgAECgEJAQAAAA==.Pestilence:BAAALgAECggJDQAAAA==.Pewpewpew:BAAALgAECgYJBgAAAA==.',
Ph='Phantomthief:BAAALgAECggJAwAAAA==.Phyllus:BAAALgAFFAIJAwAAAA==.',
Pi='Pictureplane:BAAALgADCgEJAQAAAA==.Pipeleto:BAACLgAFFH8PAAIJAAMJxhjiEQDnAAAJAAMJxhjiEQDnAAAuAAQKfxwAAgkACAnOGPUeAPcBAAkACAnOGPUeAPcBAAAA.',
Po='Poochimus:BAABLgAECn8hAAIlAAkJsROxCgAOAgAlAAkJsROxCgAOAgAAAA==.Pookong:BAAALgAECgUJCQAAAA==.Poonslayerxx:BAAALgADCgMJAwAAAA==.',
Pr='Previdius:BAAALgAECggJEQAAAA==.Priestpwnz:BAAALgAECgYJDwAAAA==.Protomán:BAABLgAECn8XAAIHAAkJ9RVLBgB1AQAHAAkJ9RVLBgB1AQAAAA==.Proximity:BAAALgADCgQJBQABLgADCgcJCwAIAAAAAA==.',
Ps='Psychmike:BAAALgAECgEJAQAAAA==.',
Pw='Pwrbttm:BAAALgAECgEJAQABLgAFFAUJEgANACMLAA==.',
['Pé']='Pépega:BAAALgAECgIJAgAAAA==.',
Ra='Rafferno:BAAALgAECgEJAgAAAA==.',
Re='Redeemedlev:BAACLgAFFH8jAAIiAAUJ9xYFDQA5AQAiAAUJ9xYFDQA5AQAuAAQKf0IAAiIACQnkISYEAFcDACIACQnkISYEAFcDAAEuAAUUCAkWABcA+BoA.Reds:BAAALgAECgEJAQAAAA==.Relax:BAABLgAECn8YAAILAAYJOh5ZUQCRAQALAAYJOh5ZUQCRAQAAAA==.',
Rh='Rhesand:BAABLgAECn8ZAAMFAAgJPAS8VgDXAAAFAAgJPAS8VgDXAAAGAAEJjwGoLQAEAAAAAA==.Rhëa:BAAALgAECgMJBAAAAA==.',
Ri='Riellus:BAAALgADCgkJFQAAAA==.Riiu:BAABLgAECn8cAAIgAAYJHR0wJwB9AQAgAAYJHR0wJwB9AQABLgAFFAMJCgACADMbAA==.Rindra:BAAALgAECgUJCAAAAA==.Rinkelle:BAAALgAECgYJBgAAAA==.Rixin:BAECLgAFFH8hAAMVAAgJhBxBEQBTAgAVAAgJhBxBEQBTAgAnAAEJAAAeKgAAAAAuAAQKfzwAAhUACQk3JgYGAEkDABUACQk3JgYGAEkDAAAA.Rixryu:BAEALgADCgkJFgABLgAFFAgJIQAVAIQcAA==.',
Ro='Roaka:BAAALgADCggJCAAAAA==.Rokom:BAACLgAFFH8LAAIJAAMJ1xh/NADfAAAJAAMJ1xh/NADfAAAuAAQKfyQAAgkACAneH28TALICAAkACAneH28TALICAAAA.Rollster:BAAALgAECgQJBAAAAA==.Rotandroll:BAAALgADCgYJBgABLgAECgEJAQAIAAAAAA==.',
Ru='Runed:BAAALgAECgEJAQAAAA==.Ruwey:BAAALgAECgEJAQAAAA==.',
Ry='Ryuk:BAAALgAECgYJEQAAAA==.',
['Rè']='Rèzurrect:BAAALgAECgUJDgAAAA==.',
Sa='Saaratharaxx:BAAALgAECgUJDAAAAA==.Sackhunter:BAABLgAECn8aAAILAAcJEg6ViwAJAQALAAcJEg6ViwAJAQAAAA==.Saero:BAABLgAECn8UAAIjAAcJbBmUKgC7AQAjAAcJbBmUKgC7AQAAAA==.Sake:BAAALgAECgUJBQABLgAFFAUJGgAgAHEUAA==.Salla:BAAALgAECgUJBQAAAA==.Saluuknir:BAACLgAFFH8FAAIFAAIJ7QcLVwBwAAAFAAIJ7QcLVwBwAAAuAAQKfzEAAwUACQmBD/smAKoBAAUACQlBD/smAKoBAAYABgloB4ojAAwBAAAA.Saphh:BAABLgAECn8gAAQnAAcJkBzkBQDsAAAVAAcJbBvMZgDBAQAmAAUJ/xnlEwA/AQAnAAQJAxvkBQDsAAABLgAFFAYJHQAmAM0ZAA==.Satrath:BAABLgAFFH8FAAIBAAIJdgkSqgCAAAABAAIJdgkSqgCAAAABLgAFFAUJCAAeAD4iAA==.',
Se='Sedalin:BAAALgAECgEJAQAAAA==.Seekae:BAAALgAECgEJAQAAAA==.Sepidasprite:BAAALgADCgEJAQAAAA==.Setoplek:BAAALgAECgEJAQAAAA==.',
Sh='Shaddoot:BAAALgAFFAIJBAAAAA==.Shadowangel:BAAALgAFFAEJAQAAAA==.Shadowbladez:BAAALgAECgEJAQAAAA==.Shadowxd:BAABLgAFFH8LAAMZAAMJFxBaRgCcAAAZAAMJFxBaRgCcAAAaAAEJGwgAAAAAAAAAAA==.Sharky:BAAALgAFFAIJAwABLgAFFAkJLgAbACUdAA==.Shaulana:BAAALgADCgYJBgAAAA==.Sheepforfree:BAAALgAECgIJAgAAAA==.Shenwu:BAAALgAFFAIJAgAAAA==.Shinishamy:BAAALgADCgEJAQAAAA==.Shirokuma:BAABLgAFFH8fAAIaAAcJlR5aAwDxAQAaAAcJlR5aAwDxAQABLgAECggJFQAEAEAjAA==.Shorty:BAAALgADCgYJEAAAAA==.',
Si='Siera:BAAALgAECgEJAgABLgAECggJDQAIAAAAAA==.Sigrun:BAAALgADCgIJAgAAAA==.Sipz:BAAALgAECgIJAgABLgAECgUJBQAIAAAAAA==.',
Sk='Skinbone:BAAALgADCgQJBAAAAA==.Skyrius:BAABLgAFFH8GAAIVAAIJ2wk7+AB1AAAVAAIJ2wk7+AB1AAAAAA==.',
Sl='Slaty:BAAALgAECgIJAgAAAA==.Slingshotz:BAABLgAECn8ZAAIdAAkJ4RmrBgCWAgAdAAkJ4RmrBgCWAgAAAA==.Slootbag:BAAALgAECgkJDwAAAA==.',
Sn='Snax:BAAALgAECgIJAgAAAA==.Sneakylev:BAACLgAFFH8JAAIeAAQJtxDdCgA3AQAeAAQJtxDdCgA3AQAuAAQKfxkAAh4ACAlxG9YTAAUCAB4ACAlxG9YTAAUCAAEuAAUUCAkWABcA+BoA.Sneux:BAAALgADCgcJDQAAAA==.Snuuze:BAACLgAFFH8PAAICAAMJJiEzTgASAQACAAMJJiEzTgASAQAuAAQKfyoAAgIACAkWI3AlAJECAAIACAkWI3AlAJECAAEuAAUUBgkLAAoAgRYA.Snuuzi:BAAALgAFFAEJAQABLgAFFAYJCwAKAIEWAA==.',
So='Soberloki:BAAALgAECgIJAgAAAA==.Sola:BAAALgAECgEJAQAAAA==.Solari:BAABLgAECn8cAAMLAAkJjRrtJQA2AgALAAkJ1BftJQA2AgAKAAcJlhUVHwDGAQAAAA==.Sole:BAAALgAECgMJAwAAAA==.Solix:BAAALgAECgEJAQAAAA==.Solpra:BAAALgAECgEJAQAAAA==.Solune:BAAALgAECgIJAwAAAA==.Solvi:BAAALgAECgYJDgAAAA==.Sophispapa:BAABLgAECn9CAAICAAcJ5SChPAASAgACAAcJ5SChPAASAgAAAA==.Souprage:BAABLgAECn8UAAIJAAgJvhApMwB+AQAJAAgJvhApMwB+AQAAAA==.',
Sp='Spellmaden:BAAALgADCgMJBgABLgAFFAQJCAAkAH0WAA==.Spywar:BAAALgAECgYJCAABLgAECggJHwARACkXAA==.',
St='Starlighter:BAABLgAECn8qAAMfAAkJiAvhKwB2AQAfAAkJiAvhKwB2AQAYAAYJGQXVSwC0AAABLgAFFAIJAgAIAAAAAA==.Starsomave:BAAALgAFFAIJAgAAAA==.Steen:BAAALgAECgQJBwAAAA==.Stinkylev:BAACLgAFFH8KAAImAAUJTw1sBgATAQAmAAUJTw1sBgATAQAuAAQKfxwAAiYACQkcH4AAAO4CACYACQkcH4AAAO4CAAEuAAUUCAkWABcA+BoA.Strentor:BAAALgAECgQJBQAAAA==.',
Su='Sunshinë:BAAALgAECgEJAgAAAA==.Supressor:BAAALgADCgQJCAABLgAECgIJAgAIAAAAAA==.',
Sy='Sylvester:BAAALgADCgIJAgAAAA==.',
['Sé']='Sérolis:BAAALgADCgEJAQAAAA==.',
Ta='Taehausx:BAACLgAFFH9SAAIOAAkJ4CYCAACmAwAOAAkJ4CYCAACmAwAuAAQKfzAAAw4ACQlSJB8GACUDAA4ACQlSJB8GACUDACAAAgk5HjZdAKIAAAAA.Tarmo:BAAALgADCgYJFgAAAA==.',
Te='Telesto:BAAALgAECgIJAgABLgAFFAcJHAACAFUhAA==.Templeton:BAAALgADCgMJAwAAAA==.Tenath:BAABLgAECn8bAAIKAAcJsRK5KAA3AQAKAAcJsRK5KAA3AQAAAA==.',
Th='Thaleon:BAAALgAECgcJDgAAAA==.Tharella:BAAALgAECgYJCwAAAA==.Tharion:BAAALgAFFAEJAQAAAA==.Thauriel:BAAALgAECgYJCAAAAA==.Thrumple:BAAALgADCgYJCgAAAA==.',
Ti='Tipz:BAAALgAECgIJAwABLgAECgUJBQAIAAAAAA==.Titania:BAABLgAECn8eAAIjAAkJTAa9QAB1AQAjAAkJTAa9QAB1AQAAAA==.',
Tr='Trollztoll:BAAALgAECgIJAgAAAA==.',
Tu='Tuulk:BAAALgADCgIJAgAAAA==.',
Ty='Typical:BAAALgADCgcJCwAAAA==.',
Ug='Uggoorc:BAACLgAFFH8SAAINAAUJIwvGTQAQAQANAAUJIwvGTQAQAQAuAAQKfykAAg0ACQkQHl0IAJ4BAA0ACQkQHl0IAJ4BAAAA.Uggotroll:BAAALgAECgUJCwABLgAFFAUJEgANACMLAA==.Ugrin:BAAALgAECgEJAQAAAA==.',
Un='Unholylord:BAAALgAECggJDAABLgAFFAgJIQAfAGkgAA==.',
Ut='Uthok:BAAALgADCgcJBwAAAA==.',
Va='Vacalocà:BAABLgAECn8UAAITAAgJUQ1iGQBEAQATAAgJUQ1iGQBEAQAAAA==.Valerian:BAAALgAECggJDgAAAA==.Validori:BAAALgADCgEJAQAAAA==.Van:BAAALgAECgkJEQAAAA==.Vaultkey:BAAALgADCgIJAwAAAA==.',
Ve='Vegesha:BAAALgAECgEJAgAAAA==.Veinke:BAABLgAECn8VAAIEAAkJ+w5gCwClAQAEAAkJ+w5gCwClAQAAAA==.Vengefullev:BAAALgAECgQJCQABLgAFFAgJFgAXAPgaAA==.Venin:BAAALgAECgYJCwAAAA==.Vessarind:BAAALgADCgEJAgAAAA==.',
Vi='Vitora:BAAALgAECgYJEQAAAA==.',
Vo='Voidkurn:BAAALgADCgYJCQAAAA==.Von:BAAALgADCgIJAgAAAA==.',
Vy='Vyse:BAAALgADCgYJBgAAAA==.',
Wa='Waally:BAAALgAECgcJEgAAAA==.Wahgwan:BAAALgAECgMJAwAAAA==.Waleran:BAAALgADCgIJAgAAAA==.Warrdaddy:BAAALgAECgYJEgABLgADCgcJBwAIAAAAAA==.Warriorbp:BAAALgADCgkJFwAAAA==.Wattz:BAAALgAECgYJBgAAAA==.',
We='Weebsora:BAACLgAFFH8FAAILAAQJwg93HQD+AAALAAQJwg93HQD+AAAuAAQKfxMAAgsABwn1G2pLAKQBAAsABwn1G2pLAKQBAAAA.Weeple:BAAALgADCgkJCQAAAA==.',
Wo='Worldtree:BAABLgAECn8XAAIQAAcJFxCMZQArAQAQAAcJFxCMZQArAQAAAA==.',
Wy='Wynne:BAAALgAECggJCwAAAA==.',
Xa='Xaelthira:BAAALgAECgYJCgAAAA==.',
Xe='Xerath:BAAALgADCgYJCAAAAA==.',
Xi='Xips:BAAALgADCgMJAwABLgAECgUJBQAIAAAAAA==.',
Xo='Xoru:BAAALgADCgYJBgAAAA==.Xoruk:BAAALgADCgQJBAABLgAFFAIJAgAIAAAAAA==.Xorun:BAAALgAECgEJAQABLgAFFAIJAgAIAAAAAA==.',
Xz='Xzarrion:BAAALgAECgEJAQAAAA==.',
Ya='Yadhi:BAABLgAECn8XAAQOAAYJihbpMgA1AQAOAAUJihbpMgA1AQAXAAYJoBCgUAAsAQAgAAUJ3AdDaACFAAAAAA==.',
Ye='Yetkin:BAAALgAECgYJDQAAAA==.',
Yi='Yifftron:BAAALgAECgYJBgABLgAECggJGwANAAogAA==.Yimomo:BAABLgAECn8cAAMYAAkJhRUbLgCMAQAYAAkJhRUbLgCMAQAfAAcJtwcMTgDYAAAAAA==.',
Yo='Yoshira:BAAALgAECgMJAwABLgAECggJDQAIAAAAAA==.',
Yv='Yveltal:BAAALgAECggJCQAAAA==.',
Yz='Yzra:BAAALgAECgQJBgAAAA==.',
Za='Zahndrekh:BAAALgADCgUJBQAAAA==.Zalconn:BAACLgAFFH8cAAMeAAUJVyY4DgCwAQAeAAUJVyY4DgCwAQAkAAIJDRdxDACZAAAuAAQKfysAAx4ACQkcJjoDAGwDAB4ACQnZJToDAGwDACQAAQneJoEbAHEAAAAA.Zarrona:BAACLgAFFH8IAAIkAAQJfRbuAQAhAQAkAAQJfRbuAQAhAQAuAAQKfyYAAyQACAkRHxkFAB4CACQABwm2HRkFAB4CAB4ABwmRGlEfAJsBAAAA.Zayah:BAABLgAECn8aAAIRAAgJLxaMKQCkAQARAAgJLxaMKQCkAQAAAA==.',
Zi='Zinmaris:BAAALgAFFAIJAgAAAA==.Zivanka:BAAALgAECgcJEAAAAA==.',
Zn='Znasty:BAABLgAECn8tAAIeAAkJBSSoAgAuAwAeAAkJBSSoAgAuAwAAAA==.',
Zo='Zombaman:BAAALgADCgMJAwAAAA==.',
Zu='Zuong:BAAALgADCgQJBAAAAA==.',
Zy='Zyrap:BAAALgAECgMJAwAAAA==.',
['Öw']='Öwö:BAAALgAFFAEJAQAAAA==.',
['Üw']='Üwü:BAAALgAFFAEJAQAAAA==.',
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
