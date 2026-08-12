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

local lookup = {'Mage-Frost','Paladin-Retribution','Paladin-Protection','Warrior-Arms','Monk-Brewmaster','DemonHunter-Vengeance','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Unknown-Unknown','Warrior-Fury','DemonHunter-Havoc','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Affliction','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Monk-Mistweaver','Druid-Feral','Druid-Balance','Priest-Shadow','Paladin-Holy','Priest-Discipline','Warlock-Destruction','Priest-Holy','Druid-Restoration','Mage-Fire','Druid-Guardian','Mage-Arcane','Hunter-Marksmanship','Hunter-Survival','Rogue-Subtlety','Monk-Windwalker','Evoker-Preservation','Rogue-Outlaw','Shaman-Enhancement',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=46,date='2026-08-11',data={Ab='Abeblinkin:BAABLgAECn9NAAIBAAkJkSJlAwDNAgABAAkJkSJlAwDNAgAAAA==.',
Ac='Accursed:BAAALgAECgEJAQAAAA==.',
Ad='Adcrusty:BAAALgAECgEJAQAAAA==.',
Ae='Aegrias:BAABLgAECn8hAAICAAkJEx48JwCJAgACAAkJEx48JwCJAgAAAA==.Aeledron:BAAALgADCgQJBQAAAA==.Aerodria:BAABLgAECn9yAAMCAAkJqhjVCgC8AQACAAkJCxjVCgC8AQADAAUJ0xTYBQAvAQAAAA==.',
Ag='Agwang:BAAALgAECgEJAQAAAA==.',
Aj='Ajm:BAABLgAFFH8LAAIEAAQJmxT6GQAWAQAEAAQJmxT6GQAWAQAAAA==.',
Ak='Akarii:BAAALgAECgYJEAABLgAECgYJFwAFAIoWAA==.Akeno:BAACLgAFFH8HAAMGAAYJ1Q1bBQC1AAAGAAMJaBNbBQC1AAAHAAQJMQj+MwCmAAAuAAQKfxUAAgYACAlAI1kBABgDAAYACAlAI1kBABgDAAAA.Akiaura:BAAALgAECgYJEgAAAA==.Akime:BAAALgAECgYJDwAAAA==.Akudama:BAABLgAECn8tAAMIAAkJnxprEABkAgAIAAkJnxprEABkAgAJAAIJqQkFNwBfAAABLgAFFAkJMAAKALQXAA==.',
Al='Alarm:BAAALgADCgEJAQABLgADCgcJCwALAAAAAA==.Albince:BAAALgADCgIJAgAAAA==.Aldanil:BAAALgAECggJEAAAAA==.Aligh:BAAALgAECgEJAQAAAA==.Alisae:BAAALgADCgMJAwAAAA==.Alma:BAAALgAECgUJBQAAAA==.Alye:BAAALgAECgcJEAAAAA==.',
Am='Amellis:BAAALgAECgUJCQAAAA==.',
An='Ananac:BAAALgADCgEJAQAAAA==.Andreasham:BAAALgADCgEJAQAAAA==.Annisseda:BAACLgAFFH8mAAMMAAgJ/B4+BgDaAQAMAAgJ/B4+BgDaAQAEAAQJHxlXDgDiAAAuAAQKfysAAwwACQmLJP0HAN8CAAwACQmLJP0HAN8CAAQAAQl9ITFkAFkAAAAA.',
Ar='Aradril:BAAALgADCgcJCwAAAA==.Arrhythmia:BAAALgAECgkJJQABLgAFFAkJKgALAAAAAQ==.',
As='Ashrak:BAAALgAECgQJBAAAAA==.Ashér:BAAALgAECgEJAQAAAA==.Astaulis:BAAALgADCgUJCAAAAA==.',
Ax='Axelle:BAAALgAECgkJEAAAAA==.',
Az='Azzy:BAACLgAFFH8wAAIMAAkJ1R2UAgBsAgAMAAkJ1R2UAgBsAgAuAAQKfz4AAgwACQnlJXgCAJMDAAwACQnlJXgCAJMDAAAA.',
Ba='Babyboomie:BAAALgAECgUJBwAAAA==.Bagagwa:BAAALgADCgcJCAAAAA==.Bal:BAABLgAECn8kAAQNAAgJVhXKHQDRAQANAAgJ8xLKHQDRAQAHAAYJWQ/EkwD5AAAGAAIJBiFQKQBeAAAAAA==.Balam:BAAALgADCgEJAQAAAA==.Balana:BAAALgAECgUJCAAAAA==.Bambudda:BAAALgAFFAIJAgAAAA==.Bananski:BAABLgAECn8VAAMDAAYJUQ2vJADjAAADAAUJIA+vJADjAAACAAYJXwa49QDEAAAAAA==.Bandu:BAAALgADCgEJAgAAAA==.Barkeep:BAABLgAECn8aAAIOAAkJaw+WOADMAQAOAAkJaw+WOADMAQAAAA==.Bassoon:BAAALgAECgMJAwABLgAFFAIJBQAFAE4RAA==.',
Be='Beast:BAACLgAFFH8rAAQPAAgJ5h1EBADBAQAPAAYJwB5EBADBAQAQAAYJJh2MKgC+AQARAAEJAADvUQAAAAAuAAQKfygAAxAACAloI5AYAOgCABAACAloI5AYAOgCAA8AAgkxJYUHANwAAAAA.Beeflocks:BAABLgAECn8jAAISAAkJMhxABwD/AQASAAkJMhxABwD/AQAAAA==.Beefpile:BAAALgADCgUJBQAAAA==.Bekarn:BAABLgAECn8YAAMTAAcJeAofUwA5AQATAAcJeAofUwA5AQAUAAMJ7AhzegBaAAAAAA==.Benafflock:BAAALgAECgMJAwAAAA==.Bennafflock:BAAALgAECgUJCwAAAA==.Bergz:BAAALgAECgMJAgAAAA==.',
Bh='Bhp:BAAALgADCgMJAwABLgAECgMJAwALAAAAAA==.',
Bi='Bigbleu:BAAALgAECgUJCQABLgAECggJJwAVAHkdAA==.Bigdh:BAAALgAECgYJDgAAAA==.Bigdraco:BAAALgADCgQJBAAAAA==.Biggums:BAAALgADCgMJAwAAAA==.Biglev:BAAALgADCgMJAwABLgAFFAkJGQAWAJgaAA==.Bigpapapump:BAAALgAECgEJAQAAAA==.Bigxthaplug:BAAALgAECgYJCQAAAA==.Bilboswagins:BAABLgAECn8UAAIMAAcJyxwLIwA9AgAMAAcJyxwLIwA9AgAAAA==.Billski:BAAALgAECgcJCQAAAA==.Billyspike:BAABLgAECn8YAAMXAAYJ0RrjDQDVAQAXAAYJ0RrjDQDVAQAYAAEJkhKtigA2AAABLgAECgkJFAAZAEYdAA==.Billyspiked:BAAALgAECgIJAgABLgAECgkJFAAZAEYdAA==.Billyspikedh:BAAALgADCgMJAwABLgAECgkJFAAZAEYdAA==.Billyspikeev:BAAALgADCgYJBgABLgAECgkJFAAZAEYdAA==.Billyspikepd:BAABLgAECn8UAAMCAAkJBxTFTgDbAQACAAkJBxTFTgDbAQAaAAEJ7wILlgAqAAABLgAECgkJFAAZAEYdAA==.Billyspikepr:BAABLgAECn8UAAMZAAkJRh3VAwDmAQAZAAkJRh3VAwDmAQAbAAEJZRg+UQBHAAAAAA==.Billyspikerg:BAAALgADCgIJAgABLgAECgkJFAAZAEYdAA==.',
Bl='Blammo:BAAALgADCgcJCQAAAA==.Blobcat:BAABLgAECn8fAAIYAAcJsx8QBQCqAQAYAAcJsx8QBQCqAQAAAA==.Blobknight:BAAALgAECgIJAgAAAA==.Blobpally:BAACLgAFFH8NAAICAAQJ0RT9TgAQAQACAAQJ0RT9TgAQAQAuAAQKfyAAAgIABwm7IW0dALoCAAIABwm7IW0dALoCAAAA.Bloodhase:BAACLgAFFH8IAAIQAAQJLBg4OQDyAAAQAAQJLBg4OQDyAAAuAAQKfxgAAhAABwkbEW2XADoBABAABwkbEW2XADoBAAAA.Bloodprince:BAAALgAECgMJAwAAAA==.Bloodreign:BAAALgAECgQJBQABLgAECgYJFwAFAIoWAA==.Bluecantsee:BAAALgAECgEJAQAAAA==.Bluecard:BAACLgAFFH8lAAIKAAgJ8BrMCgAWAgAKAAgJ8BrMCgAWAgAuAAQKfywABAoACQl+IcYPAM4CAAoACQl+IcYPAM4CABwAAwnVGMg5AM0AABIAAQkXIY0nAFMAAAAA.',
Bo='Bokunh:BAAALgAECgYJEgAAAA==.Bookofmoon:BAAALgAECgUJBQAAAA==.Boomywhoomy:BAAALgAECgIJBQAAAA==.Bootstrap:BAAALgAECgkJCQAAAA==.Booya:BAAALgAECgEJAQAAAA==.Bothenheim:BAACLgAFFH8hAAMCAAgJQx5sEwDQAQACAAgJQx5sEwDQAQADAAMJQQxSEwBfAAAuAAQKfyYAAgIACQmAIgYVAMQCAAIACQmAIgYVAMQCAAAA.Bowdaddy:BAAALgADCgcJBwAAAA==.Boxtribution:BAAALgAECgMJBQAAAA==.Boxxman:BAAALgAECgcJAQAAAA==.',
Br='Breakdown:BAAALgAECgIJAgAAAA==.Brewsimmons:BAABLgAFFH8iAAIWAAkJHxprAgD+AgAWAAkJHxprAgD+AgAAAA==.Brüisér:BAACLgAFFH8FAAIDAAIJxwbJFABUAAADAAIJxwbJFABUAAAuAAQKfyUAAgMACQluD5IYAFgBAAMACQluD5IYAFgBAAAA.',
Bu='Buber:BAABLgAECn8XAAIHAAYJThbIfgAiAQAHAAYJThbIfgAiAQAAAA==.Bublz:BAAALgAECgcJBwAAAA==.Bumpinuglies:BAAALgAECgEJAQAAAA==.',
Ca='Callamdrake:BAAALgAECgEJAQAAAA==.Callamsvoid:BAAALgAECgMJCAAAAA==.Camazotz:BAAALgAECgUJBwAAAA==.Capie:BAAALgAECgkJEAAAAA==.Carathea:BAABLgAECn8iAAIdAAgJMSCCDACLAgAdAAgJMSCCDACLAgAAAA==.Cardstock:BAAALgAECggJCAABLgAFFAkJKgALAAAAAQ==.Carrotbear:BAAALgADCgQJBAAAAA==.Carveina:BAAALgADCgEJAQAAAA==.Cassiopeià:BAAALgAECgMJAwAAAA==.Caylen:BAACLgAFFH8hAAIeAAgJPxzwBABIAgAeAAgJPxzwBABIAgAuAAQKfyAAAh4ACAm3HkIRAK0CAB4ACAm3HkIRAK0CAAAA.Cayth:BAACLgAFFH8aAAMKAAUJ0CDCOABnAQAKAAUJux3COABnAQASAAEJJR+qGABcAAAuAAQKfzAABAoACQn7IakFAGIDAAoACQn7IakFAGIDABwAAgkLAx9VAG8AABIAAQnKHNQOAFYAAAAA.',
Ce='Cemie:BAAALgADCgcJBwAAAA==.Centralia:BAAALgADCgYJBwAAAA==.Centri:BAACLgAFFH86AAMBAAkJ9SBMAgAjAwABAAkJ9SBMAgAjAwAfAAMJvhdGBACRAAAuAAQKfyQAAgEACQlGJRYaAA8DAAEACQlGJRYaAA8DAAAA.Cerestus:BAAALgADCgMJAwAAAA==.',
Ch='Chadbear:BAABLgAECn8VAAMgAAgJRBU8GQCFAQAgAAgJRBU8GQCFAQAXAAMJwQm6NAAwAAAAAA==.Chadtones:BAAALgAECgYJCgAAAA==.Chimueloh:BAAALgADCgQJBAAAAA==.Chiron:BAAALgADCgIJAgAAAA==.Chowa:BAAALgAFFAMJAwAAAA==.Chrleone:BAAALgAECgIJAwAAAA==.Chu:BAAALgAECgEJAQAAAA==.',
Cl='Cladiuss:BAAALgADCgIJAgAAAA==.Cleverlev:BAABLgAECn8gAAIhAAYJBiC0AQCZAQAhAAYJBiC0AQCZAQABLgAFFAkJGQAWAJgaAA==.',
Co='Colapse:BAAALgAECgEJAQAAAA==.Colivism:BAABLgAECn8kAAIBAAgJpRaleQDeAQABAAgJpRaleQDeAQAAAA==.Colívis:BAAALgAECgQJBQAAAA==.Commodorecdx:BAAALgADCgcJBwAAAA==.Cotali:BAAALgADCgUJBQABLgAECggJIgAdADEgAA==.',
Cr='Crackfiend:BAAALgADCgUJBwAAAA==.Crispi:BAAALgADCgYJBAAAAA==.Cruellev:BAABLgAECn8XAAISAAUJ1RO1BQD4AAASAAUJ1RO1BQD4AAABLgAFFAkJGQAWAJgaAA==.Crymbrulay:BAAALgAECgYJCAAAAA==.',
Cu='Cuurtis:BAAALgADCgEJAQAAAA==.',
Cz='Czernobog:BAAALgAECgMJAwAAAA==.',
Da='Daedrenda:BAAALgAECgMJBAAAAA==.Daeland:BAABLgAECn8yAAIMAAkJ0hDjJQDJAQAMAAkJ0hDjJQDJAQAAAA==.Dakky:BAAALgAFFAUJAQAAAA==.Dandakian:BAAALgAECgEJAgAAAA==.',
De='Deadwrs:BAAALgAECgEJAQAAAA==.Deathbruiser:BAAALgAECgQJBAAAAA==.Deathsgrace:BAAALgAECgkJCQAAAA==.Deathtank:BAAALgAFFAIJBAAAAA==.Deathtolife:BAAALgAECgQJCAAAAA==.Decima:BAABLgAECn8pAAIYAAkJ4A2HCwAEAQAYAAkJ4A2HCwAEAQAAAA==.Degrance:BAAALgAECgUJBQAAAA==.Demeter:BAACLgAFFH8fAAQOAAcJ8Bh0MQBMAQAOAAUJfCF0MQBMAQAiAAIJ2gWBIwCSAAAjAAEJ/iMgFQBiAAAuAAQKfyIABA4ACQlYIuASAKACAA4ACAk6HuASAKACACIABglxILUoAOQBACMAAQkoIM9TAF8AAAAA.Demonpunter:BAAALgAFFAIJBAABLgAFFAgJKAAKAGYgAA==.Dewussi:BAACLgAFFH8TAAICAAQJnAnpWwD4AAACAAQJnAnpWwD4AAAuAAQKfyQAAwMABwniHYENAO8BAAMABwk4GYENAO8BAAIABwlnG29pAJwBAAAA.',
Di='Diablita:BAAALgAECgEJAQAAAA==.Dicethrower:BAAALgAECgQJBwAAAA==.Dinkltn:BAAALgAECgUJCgAAAA==.Dinoscarr:BAAALgAECgYJDwAAAA==.Dixiinormis:BAAALgAECgkJEgABLgAECgkJTQABAJEiAA==.',
Dj='Djholy:BAAALgAECgcJDwABLgAECgcJEAALAAAAAA==.',
Do='Dotmaxxing:BAAALgAFFAEJAgAAAA==.Dotsndash:BAAALgAECgkJCgAAAA==.',
Dp='Dpsshaman:BAABLgAECn8cAAIUAAkJ6x6fCgC1AgAUAAkJ6x6fCgC1AgAAAA==.',
Dr='Drarmaku:BAAALgAECgIJAgAAAA==.Dreadingfate:BAAALgAECgkJEAAAAA==.Drscholar:BAAALgAECgIJAwAAAA==.Druidpwnz:BAAALgADCgMJAwAAAA==.',
Du='Duber:BAAALgAECgUJBgABLgAECgYJFwAHAE4WAA==.Dungorogue:BAABLgAECn8wAAIkAAgJcRAJHgClAQAkAAgJcRAJHgClAQAAAA==.Dustln:BAAALgAECgEJAQAAAA==.',
Dy='Dyonne:BAAALgADCgEJAgAAAA==.',
['Dé']='Déwéy:BAAALgAECgIJAgABLgAFFAQJEwACAJwJAA==.',
Ea='Eargox:BAAALgAECgUJBQAAAA==.',
El='Elbone:BAAALgADCgUJBQAAAA==.Elidia:BAAALgADCgcJBwAAAA==.Elinia:BAABLgAECn8zAAMdAAkJqxGpIwClAQAdAAgJqRKpIwClAQAZAAkJgQbSNwA2AQAAAA==.Elivoker:BAAALgAECgYJAwAAAA==.Elmdor:BAAALgAECgcJDQAAAA==.Elyndra:BAAALgAFFAEJAQAAAA==.',
En='Eniacoc:BAAALgAECgkJCQAAAA==.Enlag:BAAALgAECgMJAwAAAA==.',
Et='Etriganna:BAAALgAECgEJAQAAAA==.',
Ev='Evilwitch:BAAALgADCgEJAQAAAA==.Evistiah:BAAALgAECgEJAQAAAA==.',
Ex='Excentric:BAACLgAFFH8HAAICAAUJaSGEDwCJAQACAAUJaSGEDwCJAQAuAAQKfxkAAgIACAl0Hpc9AA4CAAIACAl0Hpc9AA4CAAEuAAUUCQk6AAEA9SAA.Excerpt:BAAALgAECgMJAwABLgAFFAkJOgABAPUgAA==.Exortus:BAAALgAFFAMJAwABLgAFFAgJIQACAEMeAA==.',
Fa='Falloutman:BAAALgAECgEJAQAAAA==.Farther:BAABLgAECn8YAAIOAAcJaR8iBwAkAgAOAAcJaR8iBwAkAgABLgAECgcJEQALAAAAAA==.Farëeya:BAAALgADCgcJDAAAAA==.Fayne:BAAALgAECgUJCQAAAA==.',
Fe='Fellirane:BAAALgADCgUJBQAAAA==.Fernsama:BAAALgAECgYJCAABLgAECgYJCgALAAAAAA==.',
Fi='Fishton:BAAALgADCgUJCwAAAA==.',
Fl='Flauros:BAABLgAECn8XAAIHAAcJ4Q3khgASAQAHAAcJ4Q3khgASAQAAAA==.',
Fo='Fonk:BAACLgAFFH8IAAIcAAQJqAwGBQDvAAAcAAQJqAwGBQDvAAAuAAQKfxUAAxwABwkGIJABAPMBABwABgkFIpABAPMBABIABAlICl0JAJoAAAAA.',
Fr='Fraternite:BAAALgAECgkJDgAAAA==.Froackeh:BAAALgAECggJBwAAAA==.Froackie:BAAALgAECgYJEAABLgAECggJBwALAAAAAA==.Fruto:BAACLgAFFH8FAAIFAAIJThGdRQCKAAAFAAIJThGdRQCKAAAuAAQKfzEAAgUACQnLF/ETABACAAUACQnLF/ETABACAAAA.',
Fu='Furricane:BAAALgAECgEJAQAAAA==.',
Ga='Gabriellad:BAAALgAFFAIJBAAAAA==.Garzislao:BAAALgAECggJEAAAAA==.',
Gh='Ghostfox:BAAALgAECgMJAwAAAA==.',
Gi='Giterdonee:BAACLgAFFH8cAAIMAAgJKxb2CADPAQAMAAgJKxb2CADPAQAuAAQKfyEAAgwACQn9IKEEAF8DAAwACQn9IKEEAF8DAAAA.',
Gl='Gleymoulleon:BAAALgAECgQJBwAAAA==.',
Go='Goblinbeans:BAACLgAFFH8LAAITAAUJlQiPBQBzAQATAAUJlQiPBQBzAQAuAAQKfxcAAhMACAlLFqckAAMCABMACAlLFqckAAMCAAEuAAUUCQkiABYAHxoA.Goku:BAAALgAECgQJBAAAAA==.Gotchoo:BAAALgAFFAEJAgABLgAFFAMJAwALAAAAAA==.Gothmommy:BAABLgAECn8UAAIbAAkJJxnqAQCjAgAbAAkJJxnqAQCjAgAAAA==.',
Gr='Greenbeans:BAAALgAECgUJCQABLgAFFAkJIgAWAB8aAA==.Grence:BAAALgAECgUJDAABLgAECgcJEwALAAAAAA==.Grimreaper:BAABLgAECn8lAAMTAAcJNw3OXABGAQATAAcJNw3OXABGAQAUAAQJPwLJewBVAAAAAA==.Griphöök:BAAALgAECgEJAgAAAA==.Groldin:BAAALgAECgQJBgAAAA==.Groshkar:BAAALgADCgcJCwAAAA==.Grumble:BAAALgAFFAEJAQAAAA==.',
['Gõ']='Gõtchoo:BAAALgAFFAMJAwAAAA==.',
Ha='Hairball:BAABLgAECn8iAAIjAAkJkRQTEwAOAgAjAAkJkRQTEwAOAgAAAA==.Hallona:BAAALgADCgMJAwAAAA==.Hammerthumb:BAAALgAECgUJDAABLgAFFAIJBgAXAPkHAA==.Hanniy:BAAALgAECgIJAQABLgAECgIJAgALAAAAAA==.Happydavis:BAAALgADCgUJBQAAAA==.Hardstyle:BAAALgAECgEJAQAAAA==.',
Ho='Hotdoggin:BAAALgADCgYJDAAAAA==.Hotpocket:BAAALgAECgIJAgAAAA==.',
Hy='Hyara:BAABLgAECn8rAAIOAAkJghziDwC8AgAOAAkJghziDwC8AgAAAA==.',
['Hì']='Hìm:BAAALgAECgMJBAAAAA==.',
['Hù']='Hùñtarð:BAAALgAECgMJAwAAAA==.',
Ib='Ibefarmin:BAAALgAECgEJAQAAAA==.',
Ic='Icecreammen:BAAALgADCgQJBAAAAA==.Iceshadow:BAACLgAFFH8NAAIWAAQJ/RR1JACjAAAWAAQJ/RR1JACjAAAuAAQKfxYAAxYABwnjHq0VAG0CABYABwnjHq0VAG0CACUAAgkrAqLDAA8AAAAA.Icobal:BAAALgADCgYJCAAAAA==.',
Il='Illisa:BAAALgADCgMJAwAAAA==.',
In='Inubis:BAAALgAECgIJAgAAAA==.',
Ir='Irongallo:BAAALgADCgEJAQAAAA==.',
Ix='Ixtlipactzin:BAAALgAECgIJAgAAAA==.',
Ja='Jabdis:BAAALgADCgEJAQAAAA==.Jabzulsor:BAAALgAECgEJAQAAAA==.Jacopo:BAABLgAECn8XAAIQAAgJtw43hABbAQAQAAgJtw43hABbAQAAAA==.',
Je='Jeffster:BAAALgAFFAIJBAAAAA==.',
Jo='Jocko:BAAALgAECgMJAwAAAA==.Jordi:BAABLgAECn89AAIOAAkJ2B51GQCNAgAOAAkJ2B51GQCNAgAAAA==.',
Ju='Justinfox:BAAALgADCgEJAQAAAA==.Jutti:BAAALgAECgQJDAAAAA==.',
Ka='Kaellen:BAAALgADCgUJBQAAAA==.Kahnman:BAAALgADCgUJBQAAAA==.Kaka:BAAALgAECgcJEwAAAA==.Kalet:BAAALgAECgMJAwAAAA==.Kandinsky:BAAALgADCgIJAgAAAA==.Kanree:BAACLgAFFH8xAAMWAAkJ2gjKHQCCAQAWAAkJ2gjKHQCCAQAlAAEJ5gYIRgA0AAAuAAQKfz4AAxYACQkiG0oLAJwCABYACQkiG0oLAJwCACUAAQknB7KpACgAAAAA.Kartiri:BAACLgAFFH8iAAMmAAgJEBh8DQDHAQAmAAYJ0Bd8DQDHAQAIAAgJPhWyCwCkAQAuAAQKfy8ABCYACQmRHVoGAN4CACYACQmRHVoGAN4CAAgABQnWFm80AGEBAAkABQkPGM0lAPUAAAAA.Katigirl:BAAALgAECgQJCQAAAA==.Kawhi:BAAALgAFFAEJAQAAAA==.',
Ke='Kea:BAACLgAFFH8jAAMbAAYJViBACwC2AQAbAAUJ5iNACwC2AQAdAAMJrBahFAB4AAAuAAQKfzwAAxsACQkNJr0AAOEDABsACQkNJr0AAOEDAB0AAwlTI2A1AC4BAAAA.Keedoril:BAAALgADCgUJCgAAAA==.Keratos:BAAALgAECgYJCQAAAA==.',
Kh='Khaalid:BAAALgAECgYJCgABLgAECgYJFwAFAIoWAA==.Khran:BAAALgADCgIJAgAAAA==.',
Ki='Kickingfluff:BAAALgADCgIJAgAAAA==.Kimjoonsang:BAAALgAECgEJAQABLgAECgEJAQALAAAAAA==.Kincane:BAAALgADCgMJAwAAAA==.Kipz:BAAALgAECgYJBgAAAA==.Kittyboy:BAAALgADCgUJBQAAAA==.',
Ko='Kookykrook:BAABLgAFFH8IAAIIAAQJrQ8yNADyAAAIAAQJrQ8yNADyAAAAAA==.Korxin:BAACLgAFFH8gAAIOAAgJuRSKEQDXAQAOAAgJuRSKEQDXAQAuAAQKfysAAg4ACQkpI+oEAD8DAA4ACQkpI+oEAD8DAAAA.Kozmikfrost:BAAALgADCgEJAQAAAA==.',
Kr='Kreizikat:BAACLgAFFH8PAAIeAAUJDxPFIQBKAQAeAAUJDxPFIQBKAQAuAAQKfzIAAh4ACAnJITQOAMgCAB4ACAnJITQOAMgCAAEuAAUUBgkJABYAjxIA.Krinn:BAAALgAECgYJCQAAAA==.Krios:BAAALgADCgQJBAAAAA==.',
Ku='Kurnhaspios:BAAALgADCgQJBwAAAA==.Kurquaan:BAABLgAECn8aAAMgAAkJgxMJGACRAQAgAAkJgxMJGACRAQAYAAQJEwyWVgDKAAAAAA==.',
La='Lanstan:BAAALgAECgQJBAAAAA==.Lanstyn:BAAALgAECgQJBAABLgAECgYJFwAFAIoWAA==.',
Le='Leanfiend:BAAALgAECgUJBQAAAA==.Leilar:BAAALgAECgIJAwAAAA==.Leron:BAAALgAECgYJCAAAAA==.Levitticus:BAACLgAFFH8GAAIaAAMJ2R1+IwAEAQAaAAMJ2R1+IwAEAQAuAAQKfzkAAhoACQlCH0sGACgDABoACQlCH0sGACgDAAEuAAUUCQkZABYAmBoA.',
Li='Liale:BAAALgAFFAEJAQAAAA==.Lideyn:BAAALgAECgIJAgAAAA==.Lidrel:BAAALgAECgYJBgAAAA==.Lightbreath:BAAALgAECgEJAQAAAA==.Lightfury:BAAALgAECgYJCgAAAA==.Limone:BAAALgAECgEJAQAAAA==.',
Lo='Loinari:BAABLgAECn8mAAIYAAcJbAyiDgDSAAAYAAcJbAyiDgDSAAAAAA==.Lokano:BAAALgAECgUJBwAAAA==.',
Lu='Luaru:BAAALgAECgEJAQAAAA==.Ludmylha:BAAALgAFFAEJAQAAAA==.Luisda:BAAALgAECgIJAgAAAA==.Lulak:BAAALgAECgQJCQAAAA==.Lull:BAABLgAECn8tAAMcAAkJ6A5ICwCMAQAcAAkJ6A5ICwCMAQAKAAEJ4QLaYwEdAAAAAA==.Lushil:BAAALgAFFAMJAwAAAA==.Luthin:BAAALgADCgUJBgAAAA==.',
Ly='Lyadre:BAAALgAECgIJAgAAAA==.Lynai:BAAALgADCgIJAgAAAA==.Lyndis:BAAALgAECgQJBAAAAA==.',
Ma='Madness:BAAALgAECgMJAwAAAA==.Magejaf:BAAALgADCgcJDQABLgAECggJIAASALIYAA==.Magidragon:BAABLgAECn8eAAIBAAkJcA/kDQCFAQABAAkJcA/kDQCFAQAAAA==.Mandrah:BAAALgADCgQJBQAAAA==.Maybell:BAAALgAECgQJCgAAAA==.',
Md='Mdavis:BAAALgAECgcJBwAAAA==.',
Me='Melt:BAACLgAFFH8wAAMKAAkJtBeQFwAEAgAKAAgJmReQFwAEAgAcAAEJchgiHABbAAAuAAQKfz4AAwoACQl+I/8JAAEDAAoACQl+I/8JAAEDABwABAmoEncsAAwBAAAA.Mepha:BAABLgAFFH8LAAIQAAUJIAyjMwAFAQAQAAUJIAyjMwAFAQAAAA==.Metons:BAAALgAECggJDQAAAA==.Metroboofin:BAAALgAECgMJAQAAAA==.',
Mi='Midei:BAAALgADCgkJFgAAAA==.Midriffluvr:BAAALgAECgQJBwAAAA==.Mikasa:BAAALgADCgEJAQAAAA==.Mike:BAAALgAFFAEJAQABLgAECgcJEQALAAAAAA==.Mimosa:BAAALgADCgYJCgABLgAECgYJCgALAAAAAA==.Mirna:BAAALgAECgMJBgAAAA==.Misfitdh:BAAALgAECgEJAQAAAA==.Misfitdk:BAAALgAECgEJBAAAAA==.Misfitdots:BAAALgAECgEJAQAAAA==.Misfitmagi:BAAALgAECgEJBAAAAA==.Misfitmonk:BAAALgAECgEJAgAAAA==.Misfitmorph:BAAALgAECgEJAQAAAA==.Misfitorc:BAAALgAECgEJAQAAAA==.Misfittotem:BAAALgAECgEJAwAAAA==.Misfitx:BAAALgAECgEJAgAAAA==.Missfire:BAAALgAECgkJCQAAAA==.Missðirect:BAAALgAECgEJAQABLgAFFAIJAwALAAAAAA==.Mistfox:BAAALgAECggJEgAAAA==.',
Mo='Mobiouse:BAAALgADCgYJBgAAAA==.Mollieann:BAAALgAECgQJBgAAAA==.Mommon:BAAALgAECgYJCAAAAA==.Moonraisin:BAAALgAECgMJBQAAAA==.Morrighan:BAAALgADCgQJBQAAAA==.',
Mu='Mukdron:BAAALgADCgIJAgAAAA==.',
['Mâ']='Mâlus:BAAALgAECgYJEwAAAA==.',
['Mä']='Märs:BAAALgAECgMJBQAAAA==.',
Na='Nadra:BAAALgAFFAIJAgAAAA==.Naminé:BAAALgAECgEJAQABLgAFFAQJCAAnAH0WAA==.Nattyrav:BAACLgAFFH8XAAIoAAUJ/BzYAwBJAQAoAAUJ/BzYAwBJAQAuAAQKfygAAygACQkbH8ADAO4CACgACQlnHsADAO4CABQABgnHG/03AFgBAAAA.Nawari:BAAALgAECgIJAwAAAA==.',
Ne='Nemonk:BAACLgAFFH8OAAIlAAMJpx1MCwDxAAAlAAMJpx1MCwDxAAAuAAQKf1oAAyUACQkeH0AGAOgCACUACQkeH0AGAOgCABYAAQlQA1bWABwAAAAA.Nerfling:BAAALgADCgYJBgAAAA==.Neryssa:BAACLgAFFH8cAAQKAAkJ8BjODgBFAgAKAAkJORjODgBFAgAcAAEJYRVKHgBXAAASAAEJpRwyHABVAAAuAAQKfzoAAwoACQnYJOkIAAwDAAoACAlvJOkIAAwDABwABAkpJPUYAIMBAAAA.Nezarec:BAAALgADCgIJAgAAAA==.',
Ni='Nickjamez:BAAALgADCgYJBgAAAA==.Nimh:BAAALgADCgUJCgAAAA==.Nipz:BAAALgAECgEJAQABLgAECgYJBgALAAAAAA==.',
No='Nocter:BAABLgAECn8hAAQKAAkJPx1nNwAuAgAKAAcJ9RxnNwAuAgASAAUJUiCTCwCBAQAcAAMJ9g0APgC8AAAAAA==.Noqtir:BAAALgAECgUJCgAAAA==.Not:BAAALgADCgcJAgAAAA==.Noyoo:BAAALgADCgEJAQAAAA==.',
Nu='Nunca:BAAALgAECgEJAQAAAA==.',
Ny='Nymura:BAABLgAECn8kAAICAAgJQgrTpwArAQACAAgJQgrTpwArAQAAAA==.',
['Nä']='Näesthra:BAABLgAECn8kAAIdAAgJdBhpHADjAQAdAAgJdBhpHADjAQAAAA==.',
Oa='Oakhugger:BAACLgAFFH8GAAIXAAIJ+QfhDABiAAAXAAIJ+QfhDABiAAAuAAQKfyQAAxcACQlYEN0PALkBABcACQlYEN0PALkBABgAAQkAAE2xAAAAAAAA.',
Ob='Obelisk:BAAALgADCgYJBgAAAA==.Obelix:BAAALgAECgEJAQAAAA==.',
Ok='Okarun:BAABLgAECn8jAAIHAAcJTB5nQQDuAQAHAAcJTB5nQQDuAQABLgAFFAQJCAAnAH0WAA==.',
Ol='Oldeone:BAAALgAECgMJBAAAAA==.Olillivia:BAAALgADCgIJAQAAAA==.Olyvivia:BAABLgAFFH8GAAIPAAIJuwJ3FwBgAAAPAAIJuwJ3FwBgAAAAAA==.',
Om='Omgega:BAABLgAECn9EAAICAAgJWhuTNwAjAgACAAgJWhuTNwAjAgAAAA==.',
On='Onichan:BAAALgAECgYJCQABLgAFFAkJJwAUAOcdAA==.Onimeek:BAABLgAECn9eAAMNAAkJHSBqBwC7AgANAAkJHSBqBwC7AgAHAAIJPAleDgE7AAAAAA==.',
Or='Oragar:BAAALgAECgQJBAAAAA==.Oryn:BAAALgAFFAEJAwABLgAFFAIJBgABACcVAA==.Oryx:BAAALgAECgEJBAAAAA==.',
Pa='Pallywahwah:BAAALgAFFAEJAQAAAA==.Palpitations:BAAALgAECgcJEAAAAA==.Paper:BAAALgAFFAkJKgAAAQ==.Paudetunia:BAAALgADCgIJAgAAAA==.Pazrael:BAAALgADCgEJAQAAAA==.',
Pe='Peacefullev:BAACLgAFFH8ZAAMWAAkJmBpdCwBRAgAWAAkJmBpdCwBRAgAlAAEJKQuFRAA2AAAuAAQKfyoAAxYACQlsI64OALUCABYACQlsI64OALUCACUABwnDFY4mAIEBAAAA.Peiko:BAAALgADCgIJAgAAAA==.Pelagius:BAAALgADCgYJBwAAAA==.Penance:BAAALgAECgEJAQAAAA==.Pestilence:BAAALgAECggJDQAAAA==.Pewpewpew:BAAALgAECgYJCgAAAA==.',
Ph='Phantomthief:BAAALgAECggJAwAAAA==.Phyllus:BAAALgAFFAIJAwAAAA==.',
Pi='Pictureplane:BAAALgADCgEJAQAAAA==.Pipe:BAAALgAFFAEJAQAAAA==.Pipeleto:BAACLgAFFH8VAAIMAAQJWhhWDgAzAQAMAAQJWhhWDgAzAQAuAAQKfx0AAgwACQmJGPUeAPcBAAwACQmJGPUeAPcBAAAA.',
Po='Poochimus:BAABLgAECn8hAAIoAAkJsROxCgAOAgAoAAkJsROxCgAOAgAAAA==.Pookong:BAAALgAECgUJCQAAAA==.Poonslayerxx:BAAALgADCgMJAwAAAA==.',
Pr='Previdius:BAAALgAECggJEQAAAA==.Priestpwnz:BAAALgAECgYJDwAAAA==.Protomán:BAABLgAECn8bAAIKAAkJHxYqCACRAQAKAAkJHxYqCACRAQAAAA==.Proximity:BAAALgADCgQJBQABLgADCgcJCwALAAAAAA==.',
Ps='Psychmike:BAAALgAECgEJAQAAAA==.',
Pw='Pwrbttm:BAAALgAECgEJAQABLgAFFAUJEgAOACMLAA==.',
['Pé']='Pépega:BAAALgAECgIJAgAAAA==.',
Ra='Rafferno:BAAALgAECgEJAgAAAA==.',
Re='Redeemedlev:BAACLgAFFH8kAAIbAAYJrRQ9DgBrAQAbAAYJrRQ9DgBrAQAuAAQKf0IAAhsACQnkISYEAFcDABsACQnkISYEAFcDAAEuAAUUCQkZABYAmBoA.Reds:BAAALgAECgEJAQAAAA==.Relax:BAABLgAECn8YAAIHAAYJOh5ZUQCRAQAHAAYJOh5ZUQCRAQAAAA==.',
Rh='Rhesand:BAABLgAECn8ZAAMIAAgJPAS8VgDXAAAIAAgJPAS8VgDXAAAJAAEJjwGoLQAEAAAAAA==.Rhëa:BAAALgAECgMJBAAAAA==.',
Ri='Riellus:BAAALgADCgkJFQAAAA==.Riiu:BAABLgAECn8cAAIlAAYJHR0wJwB9AQAlAAYJHR0wJwB9AQABLgAFFAMJCgACADMbAA==.Rindra:BAAALgAECgUJCAAAAA==.Rinkelle:BAAALgAECgYJBgAAAA==.Riven:BAABLgAECn8WAAQBAAYJjhzxngA9AQABAAYJDxrxngA9AQAfAAMJThMwDwBrAAAhAAEJkR9OCwBdAAAAAA==.Rixin:BAECLgAFFH8jAAMQAAkJRxxBEQBTAgAQAAkJRxxBEQBTAgARAAEJAABFNQAAAAAuAAQKfzwAAhAACQk3JgYGAEkDABAACQk3JgYGAEkDAAAA.Rixryu:BAEALgADCgkJFgABLgAFFAkJIwAQAEccAA==.',
Ro='Roaka:BAAALgADCggJCAAAAA==.Rokom:BAACLgAFFH8LAAIMAAMJ1xh/NADfAAAMAAMJ1xh/NADfAAAuAAQKfyYAAgwACQkkIG8TALICAAwACQkkIG8TALICAAAA.Rollster:BAAALgAECgQJBAAAAA==.Rotandroll:BAAALgADCgYJBgABLgAECgEJAQALAAAAAA==.',
Ru='Runed:BAAALgAECgEJAwAAAA==.Ruwey:BAAALgAECgEJAQAAAA==.',
Ry='Ryuk:BAAALgAECgYJEQAAAA==.',
['Rè']='Rèzurrect:BAAALgAECgUJDgABLgAFFAEJAQALAAAAAA==.',
Sa='Saaratharaxx:BAAALgAECgUJDAAAAA==.Sackhunter:BAABLgAECn8aAAIHAAcJEg6ViwAJAQAHAAcJEg6ViwAJAQAAAA==.Saero:BAABLgAECn8UAAIaAAcJbBmUKgC7AQAaAAcJbBmUKgC7AQAAAA==.Sake:BAAALgAECgUJBQABLgAFFAUJGgAlAHEUAA==.Salla:BAAALgAECgUJBQAAAA==.Saluuknir:BAACLgAFFH8FAAIIAAIJ7QcLVwBwAAAIAAIJ7QcLVwBwAAAuAAQKfzEAAwgACQmBD/smAKoBAAgACQlBD/smAKoBAAkABgloB4ojAAwBAAAA.Saoko:BAAALgADCgEJAQAAAA==.Saphh:BAABLgAECn8jAAQRAAgJah2XBACcAQAQAAcJbBvMZgDBAQARAAYJgRyXBACcAQAPAAUJ/xnlEwA/AQABLgAFFAcJHgAPAGoXAA==.Satrath:BAABLgAFFH8FAAIBAAIJdgkSqgCAAAABAAIJdgkSqgCAAAABLgAFFAYJCAAkAD4iAA==.',
Se='Sedalin:BAAALgAECgEJAQAAAA==.Seekae:BAAALgAECgEJAQAAAA==.Sepidasprite:BAAALgADCgEJAQAAAA==.Setoplek:BAAALgAECgEJAQAAAA==.',
Sh='Shaddoot:BAAALgAFFAIJBAAAAA==.Shadowangel:BAAALgAFFAEJAQAAAA==.Shadowbladez:BAAALgAECgEJAQAAAA==.Shadowxd:BAABLgAFFH8LAAMeAAMJFxBaRgCcAAAeAAMJFxBaRgCcAAAgAAEJGwgAAAAAAAAAAA==.Sharky:BAAALgAFFAIJAwABLgAFFAkJMgAhAMUdAA==.Shaulana:BAAALgADCgYJBgAAAA==.Sheepforfree:BAAALgAECgIJAgAAAA==.Shenwu:BAAALgAFFAIJAwAAAA==.Shin:BAAALgADCgEJAQAAAA==.Shinishamy:BAAALgADCgEJAQAAAA==.Shirokuma:BAABLgAFFH8hAAIgAAgJhCFaAwDxAQAgAAgJhCFaAwDxAQABLgAFFAYJBwAGANUNAA==.Shorty:BAAALgADCgYJEAAAAA==.Shwizzle:BAAALgADCgEJAQAAAA==.',
Si='Siera:BAAALgAECgQJBQABLgAECggJDQALAAAAAA==.Sigrun:BAAALgADCgIJAgAAAA==.Sipz:BAAALgAECgIJAgABLgAECgYJBgALAAAAAA==.',
Sk='Skinbone:BAAALgADCgQJBAAAAA==.Skyrius:BAABLgAFFH8GAAIQAAIJ2wk7+AB1AAAQAAIJ2wk7+AB1AAAAAA==.',
Sl='Slaty:BAAALgAECgIJAgAAAA==.Slingshotz:BAABLgAECn8ZAAIjAAkJ4RmrBgCWAgAjAAkJ4RmrBgCWAgAAAA==.Slootbag:BAAALgAECgkJDwAAAA==.',
Sm='Smolchili:BAAALgADCgkJCQAAAA==.',
Sn='Snax:BAAALgAECgIJAgAAAA==.Sneakylev:BAACLgAFFH8JAAIkAAQJtxB6DwAVAQAkAAQJtxB6DwAVAQAuAAQKfxkAAiQACAlxG9YTAAUCACQACAlxG9YTAAUCAAEuAAUUCQkZABYAmBoA.Sneux:BAAALgADCgcJDQAAAA==.Snuuze:BAACLgAFFH8PAAICAAMJJiEzTgASAQACAAMJJiEzTgASAQAuAAQKfyoAAgIACAkWI3AlAJECAAIACAkWI3AlAJECAAEuAAUUBgkLAA0AgRYA.Snuuzi:BAAALgAFFAEJAQABLgAFFAYJCwANAIEWAA==.',
So='Soberloki:BAAALgAECgIJAgAAAA==.Sola:BAAALgAECgEJAQAAAA==.Solari:BAABLgAECn8cAAMHAAkJjRrtJQA2AgAHAAkJ1BftJQA2AgANAAcJlhUVHwDGAQAAAA==.Sole:BAAALgAECgMJAwAAAA==.Solix:BAAALgAECgEJAQAAAA==.Solpra:BAAALgAECgEJAQAAAA==.Solune:BAAALgAECgIJAwAAAA==.Solvi:BAAALgAECgYJDgAAAA==.Sophispapa:BAABLgAECn9CAAICAAcJ5SChPAASAgACAAcJ5SChPAASAgAAAA==.Souprage:BAABLgAECn8UAAIMAAgJvhApMwB+AQAMAAgJvhApMwB+AQAAAA==.',
Sp='Spellmaden:BAAALgADCgMJBgABLgAFFAQJCAAnAH0WAA==.Spywar:BAAALgAECgYJCAABLgAECggJHwAUACkXAA==.',
St='Starlighter:BAABLgAECn8qAAMZAAkJiAvhKwB2AQAZAAkJiAvhKwB2AQAdAAYJGQXVSwC0AAABLgAFFAIJAgALAAAAAA==.Starsomave:BAAALgAFFAIJAgAAAA==.Steen:BAAALgAECgQJBwAAAA==.Stinkylev:BAACLgAFFH8KAAIPAAUJTA1/CQAEAQAPAAUJTA1/CQAEAQAuAAQKfyUAAg8ACQloH8gAAPACAA8ACQloH8gAAPACAAEuAAUUCQkZABYAmBoA.Strentor:BAAALgAECgQJBQAAAA==.',
Su='Sunshinë:BAAALgAECgEJAgAAAA==.Supressor:BAAALgADCgQJCAABLgAECgIJAgALAAAAAA==.',
Sy='Sylvester:BAAALgADCgIJAgAAAA==.',
['Sé']='Sérolis:BAAALgADCgEJAQAAAA==.',
Ta='Taehausx:BAACLgAFFH9sAAIFAAkJ9yYDAACmAwAFAAkJ9yYDAACmAwAuAAQKfzIAAwUACQkOJh8GACUDAAUACQkOJh8GACUDACUAAgk5HjZdAKIAAAAA.Tarmo:BAAALgADCgYJFgAAAA==.',
Te='Telesto:BAAALgAECgIJAgABLgAFFAgJIQACAEMeAA==.Templeton:BAAALgADCgMJAwAAAA==.Tenath:BAABLgAECn8bAAINAAcJsRK5KAA3AQANAAcJsRK5KAA3AQAAAA==.',
Th='Thaleon:BAAALgAECgcJDgAAAA==.Tharella:BAAALgAECgYJCwAAAA==.Tharion:BAAALgAFFAIJAgAAAA==.Thauriel:BAAALgAECgYJCAAAAA==.Thrumple:BAAALgADCgYJCgAAAA==.',
Ti='Tipz:BAAALgAECgIJAwABLgAECgYJBgALAAAAAA==.Titania:BAABLgAECn8eAAIaAAkJTAa9QAB1AQAaAAkJTAa9QAB1AQAAAA==.',
Tr='Trollztoll:BAAALgAECgIJAgAAAA==.',
Tu='Tuulk:BAAALgADCgIJAgAAAA==.',
Ty='Typical:BAAALgADCgcJCwAAAA==.',
Ug='Uggoorc:BAACLgAFFH8SAAIOAAUJIwvGTQAQAQAOAAUJIwvGTQAQAQAuAAQKfywAAg4ACQlSHiIIAAgCAA4ACQlSHiIIAAgCAAAA.Uggotroll:BAAALgAECgUJCwABLgAFFAUJEgAOACMLAA==.Ugrin:BAAALgAECgEJAQAAAA==.',
Un='Unholylord:BAAALgAECggJDAABLgAFFAkJIgAZALgfAA==.',
Ur='Ursok:BAAALgAECgYJDQABLgAECgYJFwAFAIoWAA==.',
Ut='Uthok:BAAALgADCgcJBwAAAA==.',
Va='Vacalocà:BAABLgAECn8UAAIXAAgJUQ1iGQBEAQAXAAgJUQ1iGQBEAQAAAA==.Valerian:BAAALgAECggJDgAAAA==.Validori:BAAALgADCgEJAQAAAA==.Van:BAABLgAECn8aAAMKAAkJAgg7DgAfAQAKAAkJAgg7DgAfAQAcAAEJjgPmFgAVAAAAAA==.Vaultkey:BAAALgADCgIJAwAAAA==.',
Ve='Vegesha:BAAALgAECgEJAgAAAA==.Veinke:BAABLgAECn8VAAIGAAkJ+w5gCwClAQAGAAkJ+w5gCwClAQAAAA==.Vengefullev:BAABLgAECn8WAAIGAAYJ2xOFAwAnAQAGAAYJ2xOFAwAnAQABLgAFFAkJGQAWAJgaAA==.Venin:BAAALgAECgYJCwAAAA==.Vessarind:BAAALgADCgEJAgAAAA==.',
Vi='Vic:BAAALgADCgYJBgAAAA==.Vitora:BAAALgAECgYJEQAAAA==.',
Vo='Voidkurn:BAAALgADCgYJCQAAAA==.Von:BAAALgADCgIJAgAAAA==.',
Vy='Vyse:BAAALgADCgYJBgAAAA==.',
Wa='Waally:BAAALgAECgcJEwAAAA==.Wahgwan:BAAALgAECgMJAwAAAA==.Waleran:BAAALgADCgIJAgAAAA==.Warrdaddy:BAAALgAECgYJEgABLgADCgcJBwALAAAAAA==.Warriorbp:BAAALgADCgkJFwAAAA==.Wattz:BAAALgAECgYJBgAAAA==.',
We='Weebsora:BAACLgAFFH8HAAIHAAYJKxAVHAA0AQAHAAYJKxAVHAA0AQAuAAQKfxkAAgcACQndHrYEAO0BAAcACQndHrYEAO0BAAAA.Weeple:BAAALgADCgkJCQAAAA==.',
Wo='Worldtree:BAABLgAECn8WAAITAAYJnw+MZQArAQATAAYJnw+MZQArAQAAAA==.',
Wy='Wynne:BAAALgAECggJCwAAAA==.',
Xa='Xaelthira:BAAALgAECgYJCgAAAA==.Xaphån:BAAALgAECgYJCAAAAA==.',
Xe='Xerath:BAAALgADCgYJCAAAAA==.',
Xi='Xips:BAAALgADCgMJAwABLgAECgYJBgALAAAAAA==.',
Xo='Xoru:BAAALgADCgYJBgAAAA==.Xoruk:BAAALgADCgQJBAABLgAFFAIJAgALAAAAAA==.Xorun:BAAALgAECgEJAQABLgAFFAIJAgALAAAAAA==.',
Xz='Xzarrion:BAAALgAECgEJAQAAAA==.',
Ya='Yadhi:BAABLgAECn8XAAQFAAYJihbpMgA1AQAFAAUJihbpMgA1AQAWAAYJoBCgUAAsAQAlAAUJ3AdDaACFAAAAAA==.',
Ye='Yetkin:BAAALgAECgYJDQAAAA==.',
Yi='Yifftron:BAAALgAECgYJBgABLgAECggJHgAOAAogAA==.Yimomo:BAABLgAECn8cAAMdAAkJhRUbLgCMAQAdAAkJhRUbLgCMAQAZAAcJtwcMTgDYAAAAAA==.',
Yo='Yoshira:BAAALgAECgMJAwABLgAECggJDQALAAAAAA==.',
Yv='Yveltal:BAAALgAECggJCQAAAA==.',
Yz='Yzra:BAAALgAECgQJBgAAAA==.',
Za='Zahndrekh:BAAALgADCgUJBQAAAA==.Zalconn:BAACLgAFFH8cAAMkAAUJVyY4DgCwAQAkAAUJVyY4DgCwAQAnAAIJDRdxDACZAAAuAAQKfysAAyQACQkcJjoDAGwDACQACQnZJToDAGwDACcAAQneJoEbAHEAAAAA.Zarrona:BAACLgAFFH8IAAInAAQJfRalAgAVAQAnAAQJfRalAgAVAQAuAAQKfyYAAycACAkRHxkFAB4CACcABwm2HRkFAB4CACQABwmRGlEfAJsBAAAA.Zayah:BAABLgAECn8aAAIUAAgJLxaMKQCkAQAUAAgJLxaMKQCkAQAAAA==.',
Zi='Zinmaris:BAAALgAFFAIJAgAAAA==.Zivanka:BAAALgAECgcJEAAAAA==.',
Zn='Znasty:BAABLgAECn8tAAIkAAkJBSSoAgAuAwAkAAkJBSSoAgAuAwAAAA==.',
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
