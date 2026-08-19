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

local lookup = {'Mage-Frost','Paladin-Retribution','Paladin-Protection','Warrior-Arms','Monk-Brewmaster','DemonHunter-Vengeance','DemonHunter-Devourer','Druid-Guardian','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Unknown-Unknown','Warrior-Fury','DemonHunter-Havoc','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Affliction','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Druid-Feral','Druid-Balance','Priest-Shadow','Paladin-Holy','Priest-Discipline','Warlock-Destruction','Priest-Holy','Druid-Restoration','Mage-Fire','Mage-Arcane','Hunter-Marksmanship','Hunter-Survival','Rogue-Subtlety','Monk-Windwalker','Evoker-Preservation','Rogue-Outlaw','Shaman-Enhancement',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=46,date='2026-08-18',data={Ab='Abeblinkin:BAABLgAECn9NAAIBAAkJkSJsAwDNAgABAAkJkSJsAwDNAgAAAA==.',
Ac='Accursed:BAAALgAECgEJAQAAAA==.',
Ad='Adcrusty:BAAALgAECgEJAQAAAA==.',
Ae='Aegrias:BAABLgAECn8hAAICAAkJEx48JwCJAgACAAkJEx48JwCJAgAAAA==.Aeledron:BAAALgADCgQJBQAAAA==.Aerodria:BAABLgAECn9yAAMCAAkJqhjnCgC8AQACAAkJCxjnCgC8AQADAAUJ0xTcBQAvAQAAAA==.',
Ag='Agwang:BAAALgAECgEJAQAAAA==.',
Aj='Ajm:BAABLgAFFH8LAAIEAAQJmxT6GQAWAQAEAAQJmxT6GQAWAQAAAA==.',
Ak='Akarii:BAAALgAECgYJEAABLgAECgYJFwAFAIoWAA==.Akeno:BAACLgAFFH8HAAMGAAYJ1Q1dBQC1AAAGAAMJaBNdBQC1AAAHAAQJMQj9MwCmAAAuAAQKfxUAAgYACAlAI1kBABgDAAYACAlAI1kBABgDAAEuAAUUCAkhAAgAhCEA.Akiaura:BAAALgAECgYJEgAAAA==.Akime:BAAALgAECgYJDwAAAA==.Akudama:BAABLgAECn8tAAMJAAkJnxprEABkAgAJAAkJnxprEABkAgAKAAIJqQkFNwBfAAABLgAFFAkJMAALALQXAA==.',
Al='Alarm:BAAALgADCgEJAQABLgADCgcJCwAMAAAAAA==.Albince:BAAALgADCgIJAgAAAA==.Aldanil:BAAALgAECggJEAAAAA==.Aligh:BAAALgAECgEJAQAAAA==.Alisae:BAAALgADCgMJAwAAAA==.Alma:BAAALgAECgUJBQAAAA==.Alye:BAAALgAECgcJEAAAAA==.',
Am='Amellis:BAAALgAECgUJCQAAAA==.',
An='Ananac:BAAALgADCgEJAQAAAA==.Andreasham:BAAALgADCgEJAQAAAA==.Annisseda:BAACLgAFFH8mAAMNAAgJ/B4/BgDaAQANAAgJ/B4/BgDaAQAEAAQJHxlwDgDiAAAuAAQKfysAAw0ACQmLJP0HAN8CAA0ACQmLJP0HAN8CAAQAAQl9ITFkAFkAAAAA.',
Ar='Aradril:BAAALgADCgcJCwAAAA==.Arrhythmia:BAAALgAECgkJJQABLgAFFAkJKgAMAAAAAQ==.',
As='Ashrak:BAAALgAECgQJBAAAAA==.Ashér:BAAALgAECgEJAQAAAA==.Astaulis:BAAALgADCgUJCAAAAA==.',
Ax='Axelle:BAAALgAECgkJEAAAAA==.',
Az='Azzy:BAACLgAFFH8wAAINAAkJ1R2UAgBsAgANAAkJ1R2UAgBsAgAuAAQKfz4AAg0ACQnlJXgCAJMDAA0ACQnlJXgCAJMDAAAA.',
Ba='Babyboomie:BAAALgAECgUJBwAAAA==.Bagagwa:BAAALgADCgcJCAAAAA==.Bal:BAABLgAECn8kAAQOAAgJVhXKHQDRAQAOAAgJ8xLKHQDRAQAHAAYJWQ/EkwD5AAAGAAIJBiFQKQBeAAAAAA==.Balam:BAAALgADCgEJAQAAAA==.Balana:BAAALgAECgUJCAAAAA==.Bambudda:BAAALgAFFAIJAgAAAA==.Bananski:BAABLgAECn8VAAMDAAYJUQ2vJADjAAADAAUJIA+vJADjAAACAAYJXwa49QDEAAAAAA==.Bandu:BAAALgADCgEJAgAAAA==.Barkeep:BAABLgAECn8aAAIPAAkJaw+WOADMAQAPAAkJaw+WOADMAQAAAA==.Bassoon:BAAALgAECgMJAwABLgAFFAIJBQAFAE4RAA==.',
Be='Beast:BAACLgAFFH8rAAQQAAgJ5h1EBADBAQAQAAYJwB5EBADBAQARAAYJJh2MKgC+AQASAAEJAADvUQAAAAAuAAQKfygAAxEACAloI5AYAOgCABEACAloI5AYAOgCABAAAgkxJZAHANwAAAAA.Beeflocks:BAABLgAECn8jAAITAAkJMhxABwD/AQATAAkJMhxABwD/AQAAAA==.Beefpile:BAAALgADCgUJBQAAAA==.Bekarn:BAABLgAECn8YAAMUAAcJeAofUwA5AQAUAAcJeAofUwA5AQAVAAMJ7AhzegBaAAAAAA==.Benafflock:BAAALgAECgMJAwAAAA==.Bennafflock:BAAALgAECgUJCwAAAA==.Bergz:BAAALgAECgMJAgAAAA==.',
Bh='Bhp:BAAALgADCgMJAwABLgAECgMJAwAMAAAAAA==.',
Bi='Bigbleu:BAAALgAECgUJCQABLgAECgYJEgAMAAAAAA==.Bigdh:BAAALgAECgYJDgAAAA==.Bigdraco:BAAALgADCgQJBAAAAA==.Biggums:BAAALgADCgMJAwAAAA==.Biglev:BAAALgADCgMJAwABLgAFFAkJGQAWAJgaAA==.Bigpapapump:BAAALgAECgEJAQAAAA==.Bigxthaplug:BAAALgAECgYJCQAAAA==.Bilboswagins:BAABLgAECn8UAAINAAcJyxwLIwA9AgANAAcJyxwLIwA9AgAAAA==.Billski:BAAALgAECgcJCQAAAA==.Billyspike:BAABLgAECn8YAAMXAAYJ0RrjDQDVAQAXAAYJ0RrjDQDVAQAYAAEJkhKtigA2AAABLgAECgkJFAAZAEYdAA==.Billyspiked:BAAALgAECgIJAgABLgAECgkJFAAZAEYdAA==.Billyspikedh:BAAALgADCgMJAwABLgAECgkJFAAZAEYdAA==.Billyspikeev:BAAALgADCgYJBgABLgAECgkJFAAZAEYdAA==.Billyspikepd:BAABLgAECn8UAAMCAAkJBxTFTgDbAQACAAkJBxTFTgDbAQAaAAEJ7wILlgAqAAABLgAECgkJFAAZAEYdAA==.Billyspikepr:BAABLgAECn8UAAMZAAkJRh3eAwDlAQAZAAkJRh3eAwDlAQAbAAEJZRg+UQBHAAAAAA==.Billyspikerg:BAAALgADCgIJAgABLgAECgkJFAAZAEYdAA==.',
Bl='Blammo:BAAALgADCgcJCQAAAA==.Blobcat:BAABLgAECn8fAAIYAAcJsx8cBQCqAQAYAAcJsx8cBQCqAQAAAA==.Blobknight:BAAALgAECgIJAgAAAA==.Blobpally:BAACLgAFFH8NAAICAAQJ0RT9TgAQAQACAAQJ0RT9TgAQAQAuAAQKfyAAAgIABwm7IW0dALoCAAIABwm7IW0dALoCAAAA.Bloodhase:BAACLgAFFH8IAAIRAAQJLBhHOQDyAAARAAQJLBhHOQDyAAAuAAQKfxgAAhEABwkbEW2XADoBABEABwkbEW2XADoBAAAA.Bloodprince:BAAALgAECgMJAwAAAA==.Bloodreign:BAAALgAECgQJBQABLgAECgYJFwAFAIoWAA==.Bluecantsee:BAAALgAECgEJAQAAAA==.Bluecard:BAACLgAFFH8lAAILAAgJ8Bq7CgAWAgALAAgJ8Bq7CgAWAgAuAAQKfywABAsACQl+IcYPAM4CAAsACQl+IcYPAM4CABwAAwnVGMg5AM0AABMAAQkXIY0nAFMAAAAA.',
Bo='Bokunh:BAAALgAECgYJEgAAAA==.Bookofmoon:BAAALgAECgUJBQAAAA==.Boomywhoomy:BAAALgAECgIJBQAAAA==.Bootstrap:BAAALgAECgkJCQAAAA==.Booya:BAAALgAECgEJAQAAAA==.Bothenheim:BAACLgAFFH8hAAMCAAgJQx5sEwDQAQACAAgJQx5sEwDQAQADAAMJQQxSEwBfAAAuAAQKfyYAAgIACQmAIgYVAMQCAAIACQmAIgYVAMQCAAAA.Bowdaddy:BAAALgADCgcJBwAAAA==.Boxtribution:BAAALgAECgMJBQAAAA==.Boxxman:BAAALgAECgcJAQAAAA==.',
Br='Breakdown:BAAALgAECgIJAgAAAA==.Brewsimmons:BAABLgAFFH8iAAIWAAkJHxpjAgD+AgAWAAkJHxpjAgD+AgAAAA==.Brüisér:BAACLgAFFH8FAAIDAAIJxwbJFABUAAADAAIJxwbJFABUAAAuAAQKfyUAAgMACQluD5IYAFgBAAMACQluD5IYAFgBAAAA.',
Bu='Buber:BAABLgAECn8XAAIHAAYJThbIfgAiAQAHAAYJThbIfgAiAQAAAA==.Bublz:BAAALgAECgcJBwAAAA==.Bumpinuglies:BAAALgAECgEJAQAAAA==.',
Ca='Callamdrake:BAAALgAECgEJAQAAAA==.Callamsvoid:BAAALgAECgMJCAAAAA==.Camazotz:BAAALgAECgUJBwAAAA==.Capie:BAAALgAECgkJEAAAAA==.Carathea:BAABLgAECn8iAAIdAAgJMSCCDACLAgAdAAgJMSCCDACLAgAAAA==.Cardstock:BAAALgAECggJCAABLgAFFAkJKgAMAAAAAQ==.Carrotbear:BAAALgADCgQJBAAAAA==.Carveina:BAAALgADCgEJAQAAAA==.Cassiopeià:BAAALgAECgMJAwAAAA==.Caylen:BAACLgAFFH8hAAIeAAgJPxzsBABIAgAeAAgJPxzsBABIAgAuAAQKfyAAAh4ACAm3HkIRAK0CAB4ACAm3HkIRAK0CAAAA.Cayth:BAACLgAFFH8aAAMLAAUJ0CDCOABnAQALAAUJux3COABnAQATAAEJJR+qGABcAAAuAAQKfzAABAsACQn7IakFAGIDAAsACQn7IakFAGIDABwAAgkLAx9VAG8AABMAAQnKHO0OAFYAAAAA.',
Ce='Cemie:BAAALgADCgcJBwAAAA==.Centralia:BAAALgADCgYJBwAAAA==.Centri:BAACLgAFFH86AAMBAAkJ9SA/AgAjAwABAAkJ9SA/AgAjAwAfAAMJvhdIBACRAAAuAAQKfyQAAgEACQlGJRYaAA8DAAEACQlGJRYaAA8DAAAA.Cerestus:BAAALgADCgMJAwAAAA==.',
Ch='Chadbear:BAABLgAECn8VAAMIAAgJRBU8GQCFAQAIAAgJRBU8GQCFAQAXAAMJwQm6NAAwAAAAAA==.Chadtones:BAAALgAECgYJCgAAAA==.Chimueloh:BAAALgADCgQJBAAAAA==.Chiron:BAAALgADCgIJAgAAAA==.Chowa:BAAALgAFFAMJAwAAAA==.Chrleone:BAAALgAECgIJAwAAAA==.Chu:BAAALgAECgEJAQAAAA==.',
Cl='Cladiuss:BAAALgADCgIJAgAAAA==.Cleverlev:BAABLgAECn8gAAIgAAYJBiCyAQCZAQAgAAYJBiCyAQCZAQABLgAFFAkJGQAWAJgaAA==.',
Co='Colapse:BAAALgAECgEJAQAAAA==.Colivism:BAABLgAECn8kAAIBAAgJpRaleQDeAQABAAgJpRaleQDeAQAAAA==.Colívis:BAAALgAECgQJBQAAAA==.Commodorecdx:BAAALgADCgcJBwAAAA==.Cotali:BAAALgADCgUJBQABLgAECggJIgAdADEgAA==.',
Cr='Crackfiend:BAAALgADCgUJBwAAAA==.Crispi:BAAALgADCgYJBAAAAA==.Cruellev:BAABLgAECn8XAAITAAUJ1RO8BQD4AAATAAUJ1RO8BQD4AAABLgAFFAkJGQAWAJgaAA==.Crymbrulay:BAAALgAECgYJCAAAAA==.',
Cu='Cuurtis:BAAALgADCgEJAQAAAA==.',
Cz='Czernobog:BAAALgAECgMJAwAAAA==.',
Da='Daedrenda:BAAALgAECgMJBAAAAA==.Daeland:BAABLgAECn8yAAINAAkJ0hDjJQDJAQANAAkJ0hDjJQDJAQAAAA==.Dakky:BAAALgAFFAUJAQAAAA==.Dandakian:BAAALgAECgEJAgAAAA==.',
De='Deadwrs:BAAALgAECgEJAQAAAA==.Deathbruiser:BAAALgAECgQJBAAAAA==.Deathsgrace:BAAALgAECgkJCQAAAA==.Deathtank:BAAALgAFFAIJBAAAAA==.Deathtolife:BAAALgAECgQJCAAAAA==.Decima:BAABLgAECn8pAAIYAAkJ4A2XCwAEAQAYAAkJ4A2XCwAEAQAAAA==.Degrance:BAAALgAECgUJBQAAAA==.Demeter:BAACLgAFFH8fAAQPAAcJ8Bh0MQBMAQAPAAUJfCF0MQBMAQAhAAIJ2gWBIwCSAAAiAAEJ/iMrFQBiAAAuAAQKfyIABA8ACQlYIuASAKACAA8ACAk6HuASAKACACEABglxILUoAOQBACIAAQkoIM9TAF8AAAAA.Demonpunter:BAAALgAFFAIJBAABLgAFFAgJKAALAGYgAA==.Dewussi:BAACLgAFFH8TAAICAAQJnAnpWwD4AAACAAQJnAnpWwD4AAAuAAQKfyQAAwMABwniHYENAO8BAAMABwk4GYENAO8BAAIABwlnG29pAJwBAAAA.',
Di='Diablita:BAAALgAECgEJAQAAAA==.Dicethrower:BAAALgAECgQJBwAAAA==.Dinkltn:BAAALgAECgUJCgAAAA==.Dinoscarr:BAAALgAECgYJDwAAAA==.Dixiinormis:BAAALgAECgkJEgABLgAECgkJTQABAJEiAA==.',
Dj='Djholy:BAAALgAECgcJDwABLgAECgcJEAAMAAAAAA==.',
Do='Dotmaxxing:BAAALgAFFAEJAgAAAA==.Dotsndash:BAAALgAECgkJCgAAAA==.',
Dp='Dpsshaman:BAABLgAECn8cAAIVAAkJ6x6fCgC1AgAVAAkJ6x6fCgC1AgAAAA==.',
Dr='Drarmaku:BAAALgAECgIJAgAAAA==.Dreadingfate:BAAALgAECgkJEAAAAA==.Drscholar:BAAALgAECgIJAwAAAA==.Druidpwnz:BAAALgADCgMJAwAAAA==.',
Du='Duber:BAAALgAECgUJBgABLgAECgYJFwAHAE4WAA==.Dungorogue:BAABLgAECn8wAAIjAAgJcRAJHgClAQAjAAgJcRAJHgClAQAAAA==.Dustln:BAAALgAECgEJAQAAAA==.',
Dy='Dyonne:BAAALgADCgEJAgAAAA==.',
['Dé']='Déwéy:BAAALgAECgIJAgABLgAFFAQJEwACAJwJAA==.',
Ea='Eargox:BAAALgAECgUJBQAAAA==.',
El='Elbone:BAAALgADCgUJBQAAAA==.Elidia:BAAALgADCgcJBwAAAA==.Elinia:BAABLgAECn8zAAMdAAkJqxGpIwClAQAdAAgJqRKpIwClAQAZAAkJgQbSNwA2AQAAAA==.Elivoker:BAAALgAECgYJAwAAAA==.Elmdor:BAAALgAECgcJDQAAAA==.Elyndra:BAAALgAFFAEJAQAAAA==.',
En='Eniacoc:BAAALgAECgkJCQAAAA==.Enlag:BAAALgAECgMJAwAAAA==.',
Et='Etriganna:BAAALgAECgEJAQAAAA==.',
Ev='Evilwitch:BAAALgADCgEJAQAAAA==.Evistiah:BAAALgAECgEJAQAAAA==.',
Ex='Excentric:BAACLgAFFH8HAAICAAUJaSGIDwCJAQACAAUJaSGIDwCJAQAuAAQKfxkAAgIACAl0Hpc9AA4CAAIACAl0Hpc9AA4CAAEuAAUUCQk6AAEA9SAA.Excerpt:BAAALgAECgMJAwABLgAFFAkJOgABAPUgAA==.Exortus:BAAALgAFFAMJAwABLgAFFAgJIQACAEMeAA==.',
Fa='Falloutman:BAAALgAECgEJAQAAAA==.Farther:BAABLgAECn8YAAIPAAcJaR8uBwAkAgAPAAcJaR8uBwAkAgABLgAFFAEJAQAMAAAAAA==.Farëeya:BAAALgADCgcJDAAAAA==.Fayne:BAAALgAECgUJCQAAAA==.',
Fe='Fellirane:BAAALgADCgUJBQAAAA==.Fernsama:BAAALgAECgYJCAABLgAECgYJCgAMAAAAAA==.',
Fi='Fishton:BAAALgADCgUJCwAAAA==.',
Fl='Flauros:BAABLgAECn8XAAIHAAcJ4Q3khgASAQAHAAcJ4Q3khgASAQAAAA==.',
Fo='Fonk:BAACLgAFFH8IAAIcAAQJqAzyBADyAAAcAAQJqAzyBADyAAAuAAQKfxUAAxwABwkGIJMBAPMBABwABgkFIpMBAPMBABMABAlICmUJAJoAAAEuAAUUAQkBAAwAAAAA.',
Fr='Fraternite:BAAALgAECgkJDgAAAA==.Froackeh:BAAALgAECggJBwAAAA==.Froackie:BAAALgAECgYJEAABLgAECggJBwAMAAAAAA==.Fruto:BAACLgAFFH8FAAIFAAIJThGdRQCKAAAFAAIJThGdRQCKAAAuAAQKfzEAAgUACQnLF/ETABACAAUACQnLF/ETABACAAAA.',
Fu='Furricane:BAAALgAECgEJAQAAAA==.',
Ga='Gabriellad:BAAALgAFFAIJBAAAAA==.Garzislao:BAAALgAECggJEAAAAA==.',
Gh='Ghostfox:BAAALgAECgMJAwAAAA==.',
Gi='Giterdonee:BAACLgAFFH8cAAINAAgJKxb2CADPAQANAAgJKxb2CADPAQAuAAQKfyEAAg0ACQn9IKEEAF8DAA0ACQn9IKEEAF8DAAAA.',
Gl='Gleymoulleon:BAAALgAECgQJBwAAAA==.',
Go='Goblinbeans:BAACLgAFFH8LAAIUAAUJlQiPBQBzAQAUAAUJlQiPBQBzAQAuAAQKfxcAAhQACAlLFqckAAMCABQACAlLFqckAAMCAAEuAAUUCQkiABYAHxoA.Goku:BAAALgAECgQJBAAAAA==.Gotchoo:BAAALgAFFAEJAgABLgAFFAMJAwAMAAAAAA==.Gothmommy:BAABLgAECn8UAAIbAAkJJxnuAQCiAgAbAAkJJxnuAQCiAgAAAA==.',
Gr='Greenbeans:BAAALgAECgUJCQABLgAFFAkJIgAWAB8aAA==.Grence:BAAALgAECgUJDAABLgAECgcJEwAMAAAAAA==.Grimreaper:BAABLgAECn8lAAMUAAcJNw3OXABGAQAUAAcJNw3OXABGAQAVAAQJPwLJewBVAAAAAA==.Griphöök:BAAALgAECgEJAgAAAA==.Groldin:BAAALgAECgQJBgAAAA==.Groshkar:BAAALgADCgcJCwAAAA==.Grumble:BAAALgAFFAEJAQAAAA==.',
['Gõ']='Gõtchoo:BAAALgAFFAMJAwAAAA==.',
Ha='Hairball:BAABLgAECn8iAAIiAAkJkRQTEwAOAgAiAAkJkRQTEwAOAgAAAA==.Hallona:BAAALgADCgMJAwAAAA==.Hammerthumb:BAAALgAECgUJDAABLgAFFAIJBgAXAPkHAA==.Hanniy:BAAALgAECgIJAQABLgAECgIJAgAMAAAAAA==.Happydavis:BAAALgADCgUJBQAAAA==.Hardstyle:BAAALgAECgEJAQAAAA==.',
Ho='Hotdoggin:BAAALgADCgYJDAAAAA==.Hotpocket:BAAALgAECgIJAgAAAA==.',
Hy='Hyara:BAABLgAECn8rAAIPAAkJghziDwC8AgAPAAkJghziDwC8AgAAAA==.',
['Hì']='Hìm:BAAALgAECgMJBAAAAA==.',
['Hù']='Hùñtarð:BAAALgAECgMJAwAAAA==.',
Ib='Ibefarmin:BAAALgAECgEJAQAAAA==.',
Ic='Icecreammen:BAAALgADCgQJBAAAAA==.Iceshadow:BAACLgAFFH8NAAIWAAQJ/RRxJACjAAAWAAQJ/RRxJACjAAAuAAQKfxYAAxYABwnjHq0VAG0CABYABwnjHq0VAG0CACQAAgkrAqLDAA8AAAAA.Icobal:BAAALgADCgYJCAAAAA==.',
Il='Illisa:BAAALgADCgMJAwAAAA==.',
In='Inubis:BAAALgAECgIJAgAAAA==.',
Ir='Irongallo:BAAALgADCgEJAQAAAA==.',
Ix='Ixtlipactzin:BAAALgAECgIJAgAAAA==.',
Ja='Jabdis:BAAALgADCgEJAQAAAA==.Jabzulsor:BAAALgAECgEJAQAAAA==.Jacopo:BAABLgAECn8XAAIRAAgJtw43hABbAQARAAgJtw43hABbAQAAAA==.',
Je='Jeffster:BAAALgAFFAIJBAAAAA==.',
Jo='Jocko:BAAALgAECgMJAwAAAA==.Jordi:BAABLgAECn89AAIPAAkJ2B51GQCNAgAPAAkJ2B51GQCNAgAAAA==.',
Ju='Justinfox:BAAALgADCgEJAQAAAA==.Jutti:BAAALgAECgQJDAAAAA==.',
Ka='Kaellen:BAAALgADCgUJBQAAAA==.Kahnman:BAAALgADCgUJBQAAAA==.Kaka:BAAALgAECgcJEwAAAA==.Kalet:BAAALgAECgMJAwAAAA==.Kandinsky:BAAALgADCgIJAgAAAA==.Kanree:BAACLgAFFH8xAAMWAAkJ2gjKHQCCAQAWAAkJ2gjKHQCCAQAkAAEJ5gYIRgA0AAAuAAQKfz4AAxYACQkiG0oLAJwCABYACQkiG0oLAJwCACQAAQknB7KpACgAAAAA.Kartiri:BAACLgAFFH8iAAMlAAgJEBh8DQDHAQAlAAYJ0Bd8DQDHAQAJAAgJPhW1CwCkAQAuAAQKfy8ABCUACQmRHVoGAN4CACUACQmRHVoGAN4CAAkABQnWFm80AGEBAAoABQkPGM0lAPUAAAAA.Katigirl:BAAALgAECgQJCQAAAA==.Kawhi:BAAALgAFFAEJAQAAAA==.',
Ke='Kea:BAACLgAFFH8jAAMbAAYJViA5CwC2AQAbAAUJ5iM5CwC2AQAdAAMJrBapFAB4AAAuAAQKfzwAAxsACQkNJr0AAOEDABsACQkNJr0AAOEDAB0AAwlTI2A1AC4BAAAA.Keedoril:BAAALgADCgUJCgAAAA==.Keratos:BAAALgAECgYJCQAAAA==.',
Kh='Khaalid:BAAALgAECgYJCgABLgAECgYJFwAFAIoWAA==.Khran:BAAALgADCgIJAgAAAA==.',
Ki='Kickingfluff:BAAALgADCgIJAgAAAA==.Kimjoonsang:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.Kincane:BAAALgADCgMJAwAAAA==.Kipz:BAAALgAECgYJBgAAAA==.Kittyboy:BAAALgADCgUJBQAAAA==.',
Ko='Kookykrook:BAABLgAFFH8IAAIJAAQJrQ8yNADyAAAJAAQJrQ8yNADyAAAAAA==.Korxin:BAACLgAFFH8gAAIPAAgJuRSKEQDXAQAPAAgJuRSKEQDXAQAuAAQKfysAAg8ACQkpI+oEAD8DAA8ACQkpI+oEAD8DAAAA.Kozmikfrost:BAAALgADCgEJAQAAAA==.',
Kr='Kreizikat:BAACLgAFFH8PAAIeAAUJDxPFIQBKAQAeAAUJDxPFIQBKAQAuAAQKfzIAAh4ACAnJITQOAMgCAB4ACAnJITQOAMgCAAEuAAUUBgkJABYAjxIA.Krinn:BAAALgAECgYJCQAAAA==.Krios:BAAALgADCgQJBAAAAA==.',
Ku='Kurnhaspios:BAAALgADCgQJBwAAAA==.Kurquaan:BAABLgAECn8aAAMIAAkJgxMJGACRAQAIAAkJgxMJGACRAQAYAAQJEwyWVgDKAAAAAA==.',
La='Lanstan:BAAALgAECgQJBAAAAA==.Lanstyn:BAAALgAECgQJBAABLgAECgYJFwAFAIoWAA==.',
Le='Leanfiend:BAAALgAECgUJBQAAAA==.Leilar:BAAALgAECgIJAwAAAA==.Leron:BAAALgAECgYJCAAAAA==.Levitticus:BAACLgAFFH8GAAIaAAMJ2R1+IwAEAQAaAAMJ2R1+IwAEAQAuAAQKfzkAAhoACQlCH0sGACgDABoACQlCH0sGACgDAAEuAAUUCQkZABYAmBoA.',
Li='Liale:BAAALgAFFAEJAQAAAA==.Lideyn:BAAALgAECgIJAgAAAA==.Lidrel:BAAALgAECgYJBgAAAA==.Lightbreath:BAAALgAECgEJAQAAAA==.Lightfury:BAAALgAECgYJCgAAAA==.Limone:BAAALgAECgEJAQAAAA==.',
Lo='Loinari:BAABLgAECn8mAAIYAAcJbAyxDgDSAAAYAAcJbAyxDgDSAAAAAA==.Lokano:BAAALgAECgUJBwAAAA==.',
Lu='Luaru:BAAALgAECgEJAQAAAA==.Ludmylha:BAAALgAFFAEJAQAAAA==.Luisda:BAAALgAECgIJAgAAAA==.Lulak:BAAALgAECgQJCQAAAA==.Lull:BAABLgAECn8tAAMcAAkJ6A5ICwCMAQAcAAkJ6A5ICwCMAQALAAEJ4QLaYwEdAAAAAA==.Lushil:BAAALgAFFAMJAwAAAA==.Luthin:BAAALgADCgUJBgAAAA==.',
Ly='Lyadre:BAAALgAECgIJAgAAAA==.Lynai:BAAALgADCgIJAgAAAA==.Lyndis:BAAALgAECgQJBAAAAA==.',
Ma='Madness:BAAALgAECgMJAwAAAA==.Magejaf:BAAALgADCgcJDQABLgAECggJIAATALIYAA==.Magidragon:BAABLgAECn8eAAIBAAkJcA/wDQCFAQABAAkJcA/wDQCFAQAAAA==.Mandrah:BAAALgADCgQJBQAAAA==.Maybell:BAAALgAECgQJCgAAAA==.',
Md='Mdavis:BAAALgAECgcJBwAAAA==.',
Me='Melt:BAACLgAFFH8wAAMLAAkJtBeQFwAEAgALAAgJmReQFwAEAgAcAAEJchgiHABbAAAuAAQKfz4AAwsACQl+I/8JAAEDAAsACQl+I/8JAAEDABwABAmoEncsAAwBAAAA.Mepha:BAABLgAFFH8LAAIRAAUJIAzkMgAIAQARAAUJIAzkMgAIAQAAAA==.Metons:BAAALgAECggJDQAAAA==.Metroboofin:BAAALgAECgMJAQAAAA==.',
Mi='Midei:BAAALgADCgkJFgAAAA==.Midriffluvr:BAAALgAECgQJBwAAAA==.Mikasa:BAAALgADCgEJAQAAAA==.Mike:BAAALgAFFAEJAQAAAA==.Mimosa:BAAALgADCgYJCgABLgAECgYJCgAMAAAAAA==.Mirna:BAAALgAECgMJBgAAAA==.Misfitdh:BAAALgAECgEJAQAAAA==.Misfitdk:BAAALgAECgEJBAAAAA==.Misfitdots:BAAALgAECgEJAQAAAA==.Misfitmagi:BAAALgAECgEJBAAAAA==.Misfitmonk:BAAALgAECgEJAgAAAA==.Misfitmorph:BAAALgAECgEJAQAAAA==.Misfitorc:BAAALgAECgEJAQAAAA==.Misfittotem:BAAALgAECgEJAwAAAA==.Misfitx:BAAALgAECgEJAgAAAA==.Missfire:BAAALgAECgkJCQAAAA==.Missðirect:BAAALgAECgEJAQABLgAFFAIJAwAMAAAAAA==.Mistfox:BAAALgAECggJEgAAAA==.',
Mo='Mobiouse:BAAALgADCgYJBgAAAA==.Mollieann:BAAALgAECgQJBgAAAA==.Mommon:BAAALgAECgYJCAAAAA==.Moonraisin:BAAALgAECgMJBQAAAA==.Morrighan:BAAALgADCgQJBQAAAA==.',
Mu='Mukdron:BAAALgADCgIJAgAAAA==.',
['Mâ']='Mâlus:BAAALgAECgYJEwAAAA==.',
['Mä']='Märs:BAAALgAECgMJBQAAAA==.',
Na='Nadra:BAAALgAFFAIJAgAAAA==.Naminé:BAAALgAECgEJAQABLgAFFAQJCAAmAH0WAA==.Nattyrav:BAACLgAFFH8XAAInAAUJ/BzcAwBJAQAnAAUJ/BzcAwBJAQAuAAQKfygAAycACQkbH8ADAO4CACcACQlnHsADAO4CABUABgnHG/03AFgBAAAA.Nawari:BAAALgAECgIJAwAAAA==.',
Ne='Nemonk:BAACLgAFFH8OAAIkAAMJpx1QCwDxAAAkAAMJpx1QCwDxAAAuAAQKf1oAAyQACQkeH0AGAOgCACQACQkeH0AGAOgCABYAAQlQA1bWABwAAAAA.Nerfling:BAAALgADCgYJBgAAAA==.Neryssa:BAACLgAFFH8cAAQLAAkJ8BjODgBFAgALAAkJORjODgBFAgAcAAEJYRVKHgBXAAATAAEJpRwyHABVAAAuAAQKfzoAAwsACQnYJOkIAAwDAAsACAlvJOkIAAwDABwABAkpJPUYAIMBAAAA.Nezarec:BAAALgADCgIJAgAAAA==.',
Ni='Nickjamez:BAAALgADCgYJBgAAAA==.Nimh:BAAALgADCgUJCgAAAA==.Nipz:BAAALgAECgEJAQABLgAECgYJBgAMAAAAAA==.',
No='Nocter:BAABLgAECn8hAAQLAAkJPx1nNwAuAgALAAcJ9RxnNwAuAgATAAUJUiCTCwCBAQAcAAMJ9g0APgC8AAAAAA==.Noqtir:BAAALgAECgUJCgAAAA==.Not:BAAALgADCgcJAgAAAA==.Noyoo:BAAALgADCgEJAQAAAA==.',
Nu='Nunca:BAAALgAECgEJAQAAAA==.',
Ny='Nymura:BAABLgAECn8kAAICAAgJQgrTpwArAQACAAgJQgrTpwArAQAAAA==.',
['Nä']='Näesthra:BAABLgAECn8kAAIdAAgJdBhpHADjAQAdAAgJdBhpHADjAQAAAA==.',
Oa='Oakhugger:BAACLgAFFH8GAAIXAAIJ+QfcDABiAAAXAAIJ+QfcDABiAAAuAAQKfyQAAxcACQlYEN0PALkBABcACQlYEN0PALkBABgAAQkAAE2xAAAAAAAA.',
Ob='Obelisk:BAAALgADCgYJBgAAAA==.Obelix:BAAALgAECgEJAQAAAA==.',
Ok='Okarun:BAABLgAECn8jAAIHAAcJTB5nQQDuAQAHAAcJTB5nQQDuAQABLgAFFAQJCAAmAH0WAA==.',
Ol='Oldeone:BAAALgAECgMJBAAAAA==.Olillivia:BAAALgADCgIJAQAAAA==.Olyvivia:BAABLgAFFH8GAAIQAAIJuwKCFwBgAAAQAAIJuwKCFwBgAAAAAA==.',
Om='Omgega:BAABLgAECn9EAAICAAgJWhuTNwAjAgACAAgJWhuTNwAjAgAAAA==.',
On='Onichan:BAAALgAECgYJCQABLgAFFAkJJwAVAOcdAA==.Onimeek:BAABLgAECn9eAAMOAAkJHSBqBwC7AgAOAAkJHSBqBwC7AgAHAAIJPAleDgE7AAAAAA==.',
Or='Oragar:BAAALgAECgQJBAAAAA==.Oryn:BAAALgAFFAEJAwABLgAFFAIJBgABACcVAA==.Oryx:BAAALgAECgEJBAAAAA==.',
Pa='Pallywahwah:BAAALgAFFAEJAQAAAA==.Palpitations:BAAALgAECgcJEAAAAA==.Paper:BAAALgAFFAkJKgAAAQ==.Paudetunia:BAAALgADCgIJAgAAAA==.Pazrael:BAAALgADCgEJAQAAAA==.',
Pe='Peacefullev:BAACLgAFFH8ZAAMWAAkJmBpdCwBRAgAWAAkJmBpdCwBRAgAkAAEJKQuFRAA2AAAuAAQKfyoAAxYACQlsI64OALUCABYACQlsI64OALUCACQABwnDFY4mAIEBAAAA.Peiko:BAAALgADCgIJAgAAAA==.Pelagius:BAAALgADCgYJBwAAAA==.Penance:BAAALgAECgEJAQAAAA==.Pestilence:BAAALgAECggJDQAAAA==.Pewpewpew:BAAALgAECgYJCgAAAA==.',
Ph='Phantomthief:BAAALgAECggJAwAAAA==.Phyllus:BAAALgAFFAIJAwAAAA==.',
Pi='Pictureplane:BAAALgADCgEJAQAAAA==.Pipe:BAAALgAFFAEJAQAAAA==.Pipeleto:BAACLgAFFH8VAAINAAQJWhhZDgAzAQANAAQJWhhZDgAzAQAuAAQKfx0AAg0ACQmJGPUeAPcBAA0ACQmJGPUeAPcBAAAA.',
Po='Poochimus:BAABLgAECn8hAAInAAkJsROxCgAOAgAnAAkJsROxCgAOAgAAAA==.Pookong:BAAALgAECgUJCQAAAA==.Poonslayerxx:BAAALgADCgMJAwAAAA==.',
Pr='Previdius:BAAALgAECggJEQAAAA==.Priestpwnz:BAAALgAECgYJDwAAAA==.Protomán:BAABLgAECn8bAAILAAkJHxYyCACRAQALAAkJHxYyCACRAQAAAA==.Proximity:BAAALgADCgQJBQABLgADCgcJCwAMAAAAAA==.',
Ps='Psychmike:BAAALgAECgEJAQAAAA==.',
Pw='Pwrbttm:BAAALgAECgEJAQABLgAFFAUJEgAPACMLAA==.',
['Pé']='Pépega:BAAALgAECgIJAgAAAA==.',
Ra='Rafferno:BAAALgAECgEJAgAAAA==.',
Re='Redeemedlev:BAACLgAFFH8kAAIbAAYJrRREDgBrAQAbAAYJrRREDgBrAQAuAAQKf0IAAhsACQnkISYEAFcDABsACQnkISYEAFcDAAEuAAUUCQkZABYAmBoA.Reds:BAAALgAECgEJAQAAAA==.Relax:BAABLgAECn8YAAIHAAYJOh5ZUQCRAQAHAAYJOh5ZUQCRAQAAAA==.',
Rh='Rhesand:BAABLgAECn8ZAAMJAAgJPAS8VgDXAAAJAAgJPAS8VgDXAAAKAAEJjwGoLQAEAAAAAA==.Rhëa:BAAALgAECgMJBAAAAA==.',
Ri='Riellus:BAAALgADCgkJFQAAAA==.Riiu:BAABLgAECn8cAAIkAAYJHR0wJwB9AQAkAAYJHR0wJwB9AQABLgAFFAMJCgACADMbAA==.Rindra:BAAALgAECgUJCAAAAA==.Rinkelle:BAAALgAECgYJBgAAAA==.Riven:BAABLgAECn8WAAQBAAYJjhzxngA9AQABAAYJDxrxngA9AQAfAAMJThMwDwBrAAAgAAEJkR9nCwBdAAAAAA==.Rixin:BAECLgAFFH8jAAMRAAkJRxxBEQBTAgARAAkJRxxBEQBTAgASAAEJAABhNQAAAAAuAAQKfzwAAhEACQk3JgYGAEkDABEACQk3JgYGAEkDAAAA.Rixryu:BAEALgADCgkJFgABLgAFFAkJIwARAEccAA==.',
Ro='Roaka:BAAALgADCggJCAAAAA==.Rokom:BAACLgAFFH8LAAINAAMJ1xh/NADfAAANAAMJ1xh/NADfAAAuAAQKfyYAAg0ACQkkIG8TALICAA0ACQkkIG8TALICAAAA.Rollster:BAAALgAECgQJBAAAAA==.Rotandroll:BAAALgADCgYJBgABLgAECgEJAQAMAAAAAA==.',
Ru='Runed:BAAALgAECgEJAwAAAA==.Ruwey:BAAALgAECgEJAQAAAA==.',
Ry='Ryuk:BAAALgAECgYJEQAAAA==.',
['Rè']='Rèzurrect:BAAALgAECgUJDgABLgAECgcJFwABAHwaAA==.',
Sa='Saaratharaxx:BAAALgAECgUJDAAAAA==.Sackhunter:BAABLgAECn8aAAIHAAcJEg6ViwAJAQAHAAcJEg6ViwAJAQAAAA==.Saero:BAABLgAECn8UAAIaAAcJbBmUKgC7AQAaAAcJbBmUKgC7AQAAAA==.Sake:BAAALgAECgUJBQABLgAFFAUJGgAkAHEUAA==.Salla:BAAALgAECgUJBQAAAA==.Saluuknir:BAACLgAFFH8FAAIJAAIJ7QcLVwBwAAAJAAIJ7QcLVwBwAAAuAAQKfzEAAwkACQmBD/smAKoBAAkACQlBD/smAKoBAAoABgloB4ojAAwBAAAA.Saoko:BAAALgADCgEJAQAAAA==.Saphh:BAABLgAECn8jAAQSAAgJah2gBACcAQARAAcJbBvMZgDBAQASAAYJgRygBACcAQAQAAUJ/xnlEwA/AQABLgAFFAcJHgAQAGoXAA==.Satrath:BAABLgAFFH8FAAIBAAIJdgkSqgCAAAABAAIJdgkSqgCAAAABLgAFFAYJCAAjAD4iAA==.',
Se='Sedalin:BAAALgAECgEJAQAAAA==.Seekae:BAAALgAECgEJAQAAAA==.Sepidasprite:BAAALgADCgEJAQAAAA==.Setoplek:BAAALgAECgEJAQAAAA==.',
Sh='Shaddoot:BAAALgAFFAIJBAAAAA==.Shadowangel:BAAALgAFFAEJAQAAAA==.Shadowbladez:BAAALgAECgEJAQAAAA==.Shadowxd:BAABLgAFFH8LAAMeAAMJFxBaRgCcAAAeAAMJFxBaRgCcAAAIAAEJGwgAAAAAAAAAAA==.Sharky:BAAALgAFFAIJAwABLgAFFAkJEAAWANQSAA==.Shaulana:BAAALgADCgYJBgAAAA==.Sheepforfree:BAAALgAECgIJAgAAAA==.Shenwu:BAAALgAFFAIJAwAAAA==.Shin:BAAALgADCgEJAQAAAA==.Shinishamy:BAAALgADCgEJAQAAAA==.Shirokuma:BAABLgAFFH8hAAIIAAgJhCFaAwDxAQAIAAgJhCFaAwDxAQAAAA==.Shorty:BAAALgADCgYJEAAAAA==.Shwizzle:BAAALgADCgEJAQAAAA==.',
Si='Siera:BAAALgAECgQJBQABLgAECggJDQAMAAAAAA==.Sigrun:BAAALgADCgIJAgAAAA==.Sipz:BAAALgAECgIJAgABLgAECgYJBgAMAAAAAA==.',
Sk='Skinbone:BAAALgADCgQJBAAAAA==.Skyrius:BAABLgAFFH8GAAIRAAIJ2wk7+AB1AAARAAIJ2wk7+AB1AAAAAA==.',
Sl='Slaty:BAAALgAECgIJAgAAAA==.Slingshotz:BAABLgAECn8ZAAIiAAkJ4RmrBgCWAgAiAAkJ4RmrBgCWAgAAAA==.Slootbag:BAAALgAECgkJDwAAAA==.',
Sm='Smolchili:BAAALgADCgkJCQAAAA==.',
Sn='Snax:BAAALgAECgIJAgAAAA==.Sneakylev:BAACLgAFFH8JAAIjAAQJtxB6DwAVAQAjAAQJtxB6DwAVAQAuAAQKfxkAAiMACAlxG9YTAAUCACMACAlxG9YTAAUCAAEuAAUUCQkZABYAmBoA.Sneux:BAAALgADCgcJDQAAAA==.Snuuze:BAACLgAFFH8PAAICAAMJJiEzTgASAQACAAMJJiEzTgASAQAuAAQKfyoAAgIACAkWI3AlAJECAAIACAkWI3AlAJECAAEuAAUUBgkLAA4AgRYA.Snuuzi:BAAALgAFFAEJAQABLgAFFAYJCwAOAIEWAA==.',
So='Soberloki:BAAALgAECgIJAgAAAA==.Sola:BAAALgAECgEJAQAAAA==.Solari:BAABLgAECn8cAAMHAAkJjRrtJQA2AgAHAAkJ1BftJQA2AgAOAAcJlhUVHwDGAQAAAA==.Sole:BAAALgAECgMJAwAAAA==.Solix:BAAALgAECgEJAQAAAA==.Solpra:BAAALgAECgEJAQAAAA==.Solune:BAAALgAECgIJAwAAAA==.Solvi:BAAALgAECgYJDgAAAA==.Sophispapa:BAABLgAECn9CAAICAAcJ5SChPAASAgACAAcJ5SChPAASAgAAAA==.Souprage:BAABLgAECn8UAAINAAgJvhApMwB+AQANAAgJvhApMwB+AQAAAA==.',
Sp='Spellmaden:BAAALgADCgMJBgABLgAFFAQJCAAmAH0WAA==.Spywar:BAAALgAECgYJCAABLgAECggJHwAVACkXAA==.',
St='Starlighter:BAABLgAECn8qAAMZAAkJiAvhKwB2AQAZAAkJiAvhKwB2AQAdAAYJGQXVSwC0AAABLgAFFAIJAgAMAAAAAA==.Starsomave:BAAALgAFFAIJAgAAAA==.Steen:BAAALgAECgQJBwAAAA==.Stinkylev:BAACLgAFFH8KAAIQAAUJTA2CCQAEAQAQAAUJTA2CCQAEAQAuAAQKfyUAAhAACQloH8sAAO8CABAACQloH8sAAO8CAAEuAAUUCQkZABYAmBoA.Strentor:BAAALgAECgQJBQAAAA==.',
Su='Sunshinë:BAAALgAECgEJAgAAAA==.Supressor:BAAALgADCgQJCAABLgAECgIJAgAMAAAAAA==.',
Sy='Sylvester:BAAALgADCgIJAgAAAA==.',
['Sé']='Sérolis:BAAALgADCgEJAQAAAA==.',
Ta='Taehausx:BAACLgAFFH9sAAIFAAkJ9yYDAACmAwAFAAkJ9yYDAACmAwAuAAQKfzIAAwUACQkOJh8GACUDAAUACQkOJh8GACUDACQAAgk5HjZdAKIAAAAA.Tarmo:BAAALgADCgYJFgAAAA==.',
Te='Telesto:BAAALgAECgIJAgABLgAFFAgJIQACAEMeAA==.Templeton:BAAALgADCgMJAwAAAA==.Tenath:BAABLgAECn8bAAIOAAcJsRK5KAA3AQAOAAcJsRK5KAA3AQAAAA==.',
Th='Thaleon:BAAALgAECgcJDgAAAA==.Tharella:BAAALgAECgYJCwAAAA==.Tharion:BAAALgAFFAIJAgAAAA==.Thauriel:BAAALgAECgYJCAAAAA==.Thrumple:BAAALgADCgYJCgAAAA==.',
Ti='Tipz:BAAALgAECgIJAwABLgAECgYJBgAMAAAAAA==.Titania:BAABLgAECn8eAAIaAAkJTAa9QAB1AQAaAAkJTAa9QAB1AQAAAA==.',
Tr='Trollztoll:BAAALgAECgIJAgAAAA==.',
Tu='Tuulk:BAAALgADCgIJAgAAAA==.',
Ty='Typical:BAAALgADCgcJCwAAAA==.',
Ug='Uggoorc:BAACLgAFFH8SAAIPAAUJIwvGTQAQAQAPAAUJIwvGTQAQAQAuAAQKfywAAg8ACQlSHjIIAAgCAA8ACQlSHjIIAAgCAAAA.Uggotroll:BAAALgAECgUJCwABLgAFFAUJEgAPACMLAA==.Ugrin:BAAALgAECgEJAQAAAA==.',
Un='Unholylord:BAAALgAECggJDAABLgAFFAkJIgAZALgfAA==.',
Ur='Ursok:BAAALgAECgYJDQABLgAECgYJFwAFAIoWAA==.',
Ut='Uthok:BAAALgADCgcJBwAAAA==.',
Va='Vacalocà:BAABLgAECn8UAAIXAAgJUQ1iGQBEAQAXAAgJUQ1iGQBEAQAAAA==.Valerian:BAAALgAECggJDgAAAA==.Validori:BAAALgADCgEJAQAAAA==.Van:BAABLgAECn8aAAMLAAkJAghMDgAfAQALAAkJAghMDgAfAQAcAAEJjgMLFwAVAAAAAA==.Vaultkey:BAAALgADCgIJAwAAAA==.',
Ve='Vegesha:BAAALgAECgEJAgAAAA==.Veinke:BAABLgAECn8VAAIGAAkJ+w5gCwClAQAGAAkJ+w5gCwClAQAAAA==.Vengefullev:BAABLgAECn8WAAIGAAYJ2xOGAwAnAQAGAAYJ2xOGAwAnAQABLgAFFAkJGQAWAJgaAA==.Venin:BAAALgAECgYJCwAAAA==.Vessarind:BAAALgADCgEJAgAAAA==.',
Vi='Vic:BAAALgADCgYJBgAAAA==.Vitora:BAAALgAECgYJEQAAAA==.',
Vo='Voidkurn:BAAALgADCgYJCQAAAA==.Von:BAAALgADCgIJAgAAAA==.',
Vy='Vyse:BAAALgADCgYJBgAAAA==.',
Wa='Waally:BAAALgAECgcJEwAAAA==.Wahgwan:BAAALgAECgMJAwAAAA==.Waleran:BAAALgADCgIJAgAAAA==.Warrdaddy:BAAALgAECgYJEgABLgADCgcJBwAMAAAAAA==.Warriorbp:BAAALgADCgkJFwAAAA==.Wattz:BAAALgAECgYJBgAAAA==.',
We='Weebsora:BAACLgAFFH8HAAIHAAYJKxAaHAA0AQAHAAYJKxAaHAA0AQAuAAQKfxkAAgcACQndHr4EAO0BAAcACQndHr4EAO0BAAAA.Weeple:BAAALgADCgkJCQAAAA==.',
Wo='Worldtree:BAABLgAECn8WAAIUAAYJnw+MZQArAQAUAAYJnw+MZQArAQAAAA==.',
Wy='Wynne:BAAALgAECggJCwAAAA==.',
Xa='Xaelthira:BAAALgAECgYJCgAAAA==.Xaphån:BAAALgAECgYJCAAAAA==.',
Xe='Xerath:BAAALgADCgYJCAAAAA==.',
Xi='Xips:BAAALgADCgMJAwABLgAECgYJBgAMAAAAAA==.',
Xo='Xoru:BAAALgADCgYJBgAAAA==.Xoruk:BAAALgADCgQJBAABLgAFFAIJAgAMAAAAAA==.Xorun:BAAALgAECgEJAQABLgAFFAIJAgAMAAAAAA==.',
Xz='Xzarrion:BAAALgAECgEJAQAAAA==.',
Ya='Yadhi:BAABLgAECn8XAAQFAAYJihbpMgA1AQAFAAUJihbpMgA1AQAWAAYJoBCgUAAsAQAkAAUJ3AdDaACFAAAAAA==.',
Ye='Yetkin:BAAALgAECgYJDQAAAA==.',
Yi='Yifftron:BAAALgAECgYJBgAAAA==.Yimomo:BAABLgAECn8cAAMdAAkJhRUbLgCMAQAdAAkJhRUbLgCMAQAZAAcJtwcMTgDYAAAAAA==.',
Yo='Yoshira:BAAALgAECgMJAwABLgAECggJDQAMAAAAAA==.',
Yv='Yveltal:BAAALgAECggJCQAAAA==.',
Yz='Yzra:BAAALgAECgQJBgAAAA==.',
Za='Zahndrekh:BAAALgADCgUJBQAAAA==.Zalconn:BAACLgAFFH8cAAMjAAUJVyY4DgCwAQAjAAUJVyY4DgCwAQAmAAIJDRdxDACZAAAuAAQKfysAAyMACQkcJjoDAGwDACMACQnZJToDAGwDACYAAQneJoEbAHEAAAAA.Zarrona:BAACLgAFFH8IAAImAAQJfRakAgATAQAmAAQJfRakAgATAQAuAAQKfyYAAyYACAkRHxkFAB4CACYABwm2HRkFAB4CACMABwmRGlEfAJsBAAAA.Zayah:BAABLgAECn8aAAIVAAgJLxaMKQCkAQAVAAgJLxaMKQCkAQAAAA==.',
Zi='Zinmaris:BAAALgAFFAIJAgAAAA==.Zivanka:BAAALgAECgcJEAAAAA==.',
Zn='Znasty:BAABLgAECn8tAAIjAAkJBSSoAgAuAwAjAAkJBSSoAgAuAwAAAA==.',
Zo='Zombaman:BAAALgADCgMJAwAAAA==.',
Zu='Zuber:BAAALgAECgEJBQABLgAECgYJFwAHAE4WAA==.Zuong:BAAALgADCgQJBAAAAA==.',
Zy='Zyrap:BAAALgAECgMJAwAAAA==.',
['År']='Årtimus:BAAALgADCgYJBgAAAA==.',
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
