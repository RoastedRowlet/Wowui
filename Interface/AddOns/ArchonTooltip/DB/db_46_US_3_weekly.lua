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

local lookup = {'Mage-Frost','Paladin-Retribution','Paladin-Protection','Warrior-Arms','DemonHunter-Vengeance','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Unknown-Unknown','Monk-Brewmaster','Warrior-Fury','DemonHunter-Havoc','Hunter-BeastMastery','Warlock-Affliction','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Monk-Mistweaver','Druid-Feral','Druid-Balance','Priest-Shadow','Paladin-Holy','Priest-Discipline','DeathKnight-Unholy','Warlock-Destruction','Priest-Holy','Druid-Restoration','Mage-Fire','Druid-Guardian','Mage-Arcane','Hunter-Marksmanship','Hunter-Survival','Rogue-Subtlety','Monk-Windwalker','Evoker-Preservation','Rogue-Outlaw','Shaman-Enhancement','DeathKnight-Frost','DeathKnight-Blood',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=46,date='2026-08-04',data={Ab='Abeblinkin:BAABLgAECn9NAAIBAAkJkSIqAwDSAgABAAkJkSIqAwDSAgAAAA==.',
Ac='Accursed:BAAALgAECgEJAQAAAA==.',
Ad='Adcrusty:BAAALgAECgEJAQAAAA==.',
Ae='Aegrias:BAABLgAECn8hAAICAAkJEx48JwCJAgACAAkJEx48JwCJAgAAAA==.Aeledron:BAAALgADCgQJBQAAAA==.Aerodria:BAABLgAECn9yAAMCAAkJqhgWCgC8AQACAAkJCxgWCgC8AQADAAUJ0xR1BQAwAQAAAA==.',
Ag='Agwang:BAAALgAECgEJAQAAAA==.',
Aj='Ajm:BAABLgAFFH8LAAIEAAQJmxT6GQAWAQAEAAQJmxT6GQAWAQAAAA==.',
Ak='Akarii:BAAALgAECgYJEAAAAA==.Akeno:BAACLgAFFH8HAAMFAAYJ1Q0zBQC2AAAFAAMJaBMzBQC2AAAGAAQJMQi4MwCmAAAuAAQKfxUAAgUACAlAI1kBABgDAAUACAlAI1kBABgDAAAA.Akiaura:BAAALgAECgYJEgAAAA==.Akime:BAAALgAECgYJDwAAAA==.Akudama:BAABLgAECn8tAAMHAAkJnxprEABkAgAHAAkJnxprEABkAgAIAAIJqQkFNwBfAAABLgAFFAkJLwAJALQXAA==.',
Al='Alarm:BAAALgADCgEJAQABLgADCgcJCwAKAAAAAA==.Albince:BAAALgADCgIJAgAAAA==.Aldanil:BAAALgAECggJEAAAAA==.Aligh:BAAALgAECgEJAQAAAA==.Alisae:BAAALgADCgMJAwAAAA==.Alma:BAAALgAECgUJBQAAAA==.Alye:BAAALgAECgcJEAAAAA==.',
Am='Amellis:BAAALgAECgUJCQAAAA==.',
An='Ananac:BAAALgADCgEJAQAAAA==.Andreasham:BAAALgADCgEJAQAAAA==.Andrius:BAAALgAECgQJBQABLgAECgYJFwALAIoWAA==.Annisseda:BAACLgAFFH8mAAMMAAgJ/B7PBQDcAQAMAAgJ/B7PBQDcAQAEAAQJHxmFDQDjAAAuAAQKfysAAwwACQmLJP0HAN8CAAwACQmLJP0HAN8CAAQAAQl9ITFkAFkAAAAA.',
Ar='Aradril:BAAALgADCgcJCwAAAA==.Arktos:BAAALgAECgYJDQABLgAECgYJFwALAIoWAA==.Arrhythmia:BAAALgAECgkJJQABLgAFFAkJKQAKAAAAAQ==.',
As='Ashrak:BAAALgAECgQJBAAAAA==.Ashér:BAAALgAECgEJAQAAAA==.Astaulis:BAAALgADCgUJCAAAAA==.',
Ax='Axelle:BAAALgAECggJDwAAAA==.',
Az='Azzy:BAACLgAFFH8vAAIMAAkJgRuUAgBsAgAMAAkJgRuUAgBsAgAuAAQKfz4AAgwACQnlJXgCAJMDAAwACQnlJXgCAJMDAAAA.',
Ba='Babyboomie:BAAALgAECgUJBwAAAA==.Bagagwa:BAAALgADCgcJCAAAAA==.Bal:BAABLgAECn8kAAQNAAgJVhXKHQDRAQANAAgJ8xLKHQDRAQAGAAYJWQ/EkwD5AAAFAAIJBiFQKQBeAAAAAA==.Balam:BAAALgADCgEJAQAAAA==.Balana:BAAALgAECgUJCAAAAA==.Bambudda:BAAALgAFFAIJAgAAAA==.Bananski:BAABLgAECn8VAAMDAAYJUQ2vJADjAAADAAUJIA+vJADjAAACAAYJXwa49QDEAAAAAA==.Bandu:BAAALgADCgEJAgAAAA==.Barkeep:BAABLgAECn8aAAIOAAkJaw+WOADMAQAOAAkJaw+WOADMAQAAAA==.Bassoon:BAAALgAECgMJAwABLgAFFAIJBQALAE4RAA==.Bayeux:BAAALgAECgEJAQABLgAECgYJFwALAIoWAA==.',
Be='Beeflocks:BAABLgAECn8jAAIPAAkJMhxABwD/AQAPAAkJMhxABwD/AQAAAA==.Beefpile:BAAALgADCgUJBQAAAA==.Bekarn:BAABLgAECn8YAAMQAAcJeAofUwA5AQAQAAcJeAofUwA5AQARAAMJ7AhzegBaAAAAAA==.Benafflock:BAAALgAECgMJAwAAAA==.Bennafflock:BAAALgAECgUJCwAAAA==.Bergz:BAAALgAECgMJAgAAAA==.',
Bh='Bhp:BAAALgADCgMJAwABLgAECgMJAwAKAAAAAA==.',
Bi='Bigbleu:BAAALgAECgUJCQABLgAECggJJwASAHkdAA==.Bigdh:BAAALgAECgYJDgAAAA==.Bigdraco:BAAALgADCgQJBAAAAA==.Biggums:BAAALgADCgMJAwAAAA==.Biglev:BAAALgADCgMJAwABLgAFFAkJFwATAJkaAA==.Bigpapapump:BAAALgAECgEJAQAAAA==.Bigxthaplug:BAAALgAECgYJCQAAAA==.Bilboswagins:BAABLgAECn8UAAIMAAcJyxwLIwA9AgAMAAcJyxwLIwA9AgAAAA==.Billski:BAAALgAECgcJCQAAAA==.Billyspike:BAABLgAECn8YAAMUAAYJ0RrjDQDVAQAUAAYJ0RrjDQDVAQAVAAEJkhKtigA2AAABLgAECgkJFAAWAEYdAA==.Billyspiked:BAAALgAECgIJAgABLgAECgkJFAAWAEYdAA==.Billyspikedh:BAAALgADCgMJAwABLgAECgkJFAAWAEYdAA==.Billyspikeev:BAAALgADCgYJBgABLgAECgkJFAAWAEYdAA==.Billyspikepd:BAABLgAECn8UAAMCAAkJBxTFTgDbAQACAAkJBxTFTgDbAQAXAAEJ7wILlgAqAAABLgAECgkJFAAWAEYdAA==.Billyspikepr:BAABLgAECn8UAAMWAAkJRh13AwDrAQAWAAkJRh13AwDrAQAYAAEJZRg+UQBHAAAAAA==.Billyspikerg:BAAALgADCgIJAgABLgAECgkJFAAWAEYdAA==.',
Bl='Blammo:BAAALgADCgcJCQAAAA==.Blobcat:BAABLgAECn8cAAIVAAcJSx/xBACiAQAVAAcJSx/xBACiAQAAAA==.Blobknight:BAAALgADCgEJAQAAAA==.Blobpally:BAACLgAFFH8NAAICAAQJ0RT9TgAQAQACAAQJ0RT9TgAQAQAuAAQKfyAAAgIABwm7IW0dALoCAAIABwm7IW0dALoCAAAA.Bloodhase:BAACLgAFFH8IAAIZAAQJLBj7NgD3AAAZAAQJLBj7NgD3AAAuAAQKfxgAAhkABwkbEW2XADoBABkABwkbEW2XADoBAAAA.Bloodprince:BAAALgAECgMJAwAAAA==.Bluecantsee:BAAALgAECgEJAQAAAA==.Bluecard:BAACLgAFFH8lAAIJAAgJ8BofCgAeAgAJAAgJ8BofCgAeAgAuAAQKfywABAkACQl+IcYPAM4CAAkACQl+IcYPAM4CABoAAwnVGMg5AM0AAA8AAQkXIY0nAFMAAAAA.',
Bo='Bokunh:BAAALgAECgYJEgAAAA==.Bookofmoon:BAAALgAECgUJBQAAAA==.Boomywhoomy:BAAALgAECgIJBQAAAA==.Bootstrap:BAAALgAECgkJCQAAAA==.Bothenheim:BAACLgAFFH8hAAMCAAgJQx5sEwDQAQACAAgJQx5sEwDQAQADAAMJQQxSEwBfAAAuAAQKfyYAAgIACQmAIgYVAMQCAAIACQmAIgYVAMQCAAAA.Bowdaddy:BAAALgADCgcJBwAAAA==.Boxtribution:BAAALgAECgMJBQAAAA==.Boxxman:BAAALgAECgcJAQAAAA==.',
Br='Breakdown:BAAALgAECgIJAgAAAA==.Brewsimmons:BAABLgAFFH8iAAITAAkJHxokAgAEAwATAAkJHxokAgAEAwAAAA==.Brüisér:BAACLgAFFH8FAAIDAAIJxwbJFABUAAADAAIJxwbJFABUAAAuAAQKfyUAAgMACQluD5IYAFgBAAMACQluD5IYAFgBAAAA.',
Bu='Buber:BAABLgAECn8XAAIGAAYJThbIfgAiAQAGAAYJThbIfgAiAQAAAA==.Bublz:BAAALgAECgcJBwAAAA==.Bumpinuglies:BAAALgAECgEJAQAAAA==.',
Ca='Callamdrake:BAAALgAECgEJAQAAAA==.Callamsvoid:BAAALgAECgMJCAAAAA==.Camazotz:BAAALgAECgUJBwAAAA==.Capie:BAAALgAECgkJEAAAAA==.Carathea:BAABLgAECn8iAAIbAAgJMSCCDACLAgAbAAgJMSCCDACLAgAAAA==.Cardstock:BAAALgAECggJCAABLgAFFAkJKQAKAAAAAQ==.Carrotbear:BAAALgADCgQJBAAAAA==.Carveina:BAAALgADCgEJAQAAAA==.Cassiopeià:BAAALgAECgMJAwAAAA==.Caylen:BAACLgAFFH8hAAIcAAgJPxyWBABRAgAcAAgJPxyWBABRAgAuAAQKfyAAAhwACAm3HkIRAK0CABwACAm3HkIRAK0CAAAA.Cayth:BAACLgAFFH8aAAMJAAUJ0CDCOABnAQAJAAUJux3COABnAQAPAAEJJR+qGABcAAAuAAQKfysAAwkACQnMIakFAGIDAAkACQnMIakFAGIDABoAAgkLAx9VAG8AAAAA.',
Ce='Cemie:BAAALgADCgcJBwAAAA==.Centralia:BAAALgADCgYJBwAAAA==.Centri:BAACLgAFFH82AAMBAAkJDB7VAgAKAwABAAkJDB7VAgAKAwAdAAMJvhcOBACRAAAuAAQKfyQAAgEACQlGJRYaAA8DAAEACQlGJRYaAA8DAAAA.Cerestus:BAAALgADCgMJAwAAAA==.',
Ch='Chadbear:BAABLgAECn8VAAMeAAgJRBU8GQCFAQAeAAgJRBU8GQCFAQAUAAMJwQm6NAAwAAAAAA==.Chadtones:BAAALgAECgYJCgAAAA==.Chimueloh:BAAALgADCgQJBAAAAA==.Chiron:BAAALgADCgIJAgAAAA==.Chowa:BAAALgAFFAMJAwAAAA==.Chrleone:BAAALgAECgIJAwAAAA==.Chu:BAAALgAECgEJAQAAAA==.',
Cl='Cleverlev:BAABLgAECn8gAAIfAAYJBiBxAQCYAQAfAAYJBiBxAQCYAQABLgAFFAkJFwATAJkaAA==.',
Co='Colapse:BAAALgAECgEJAQAAAA==.Colivism:BAABLgAECn8kAAIBAAgJpRaleQDeAQABAAgJpRaleQDeAQAAAA==.Colívis:BAAALgAECgQJBQAAAA==.Commodorecdx:BAAALgADCgcJBwAAAA==.Cotali:BAAALgADCgUJBQABLgAECggJIgAbADEgAA==.',
Cr='Crackfiend:BAAALgADCgUJBwAAAA==.Crispi:BAAALgADCgYJBAAAAA==.Cruellev:BAABLgAECn8XAAIPAAUJ1RNLBQD5AAAPAAUJ1RNLBQD5AAABLgAFFAkJFwATAJkaAA==.Crymbrulay:BAAALgAECgYJCAAAAA==.',
Cu='Cuurtis:BAAALgADCgEJAQAAAA==.',
Cz='Czernobog:BAAALgAECgMJAwAAAA==.',
Da='Daedrenda:BAAALgAECgMJBAAAAA==.Daeland:BAABLgAECn8yAAIMAAkJ0hDjJQDJAQAMAAkJ0hDjJQDJAQAAAA==.Dakky:BAAALgAFFAQJAQAAAA==.Dandakian:BAAALgAECgEJAgAAAA==.',
De='Deathbruiser:BAAALgAECgQJBAAAAA==.Deathsgrace:BAAALgAECgkJCQAAAA==.Deathtank:BAAALgAFFAIJBAAAAA==.Deathtolife:BAAALgAECgQJCAAAAA==.Decima:BAABLgAECn8pAAIVAAkJ4A1XCgALAQAVAAkJ4A1XCgALAQAAAA==.Degrance:BAAALgAECgUJBQAAAA==.Demeter:BAACLgAFFH8fAAQOAAcJ8Bh0MQBMAQAOAAUJfCF0MQBMAQAgAAIJ2gWBIwCSAAAhAAEJ/iONFABjAAAuAAQKfyIABA4ACQlYIuASAKACAA4ACAk6HuASAKACACAABglxILUoAOQBACEAAQkoIM9TAF8AAAAA.Demonpunter:BAAALgAFFAIJBAABLgAFFAgJJwAJAGYgAA==.Dewussi:BAACLgAFFH8TAAICAAQJnAnpWwD4AAACAAQJnAnpWwD4AAAuAAQKfyQAAwMABwniHYENAO8BAAMABwk4GYENAO8BAAIABwlnG29pAJwBAAAA.',
Di='Diablita:BAAALgAECgEJAQAAAA==.Dicethrower:BAAALgAECgQJBwAAAA==.Dinkltn:BAAALgAECgUJCgAAAA==.Dinoscarr:BAAALgAECgYJDwAAAA==.Dixiinormis:BAAALgAECgkJEgABLgAECgkJTQABAJEiAA==.',
Dj='Djholy:BAAALgAECgcJDwABLgAECgcJEAAKAAAAAA==.',
Do='Dotmaxxing:BAAALgAFFAEJAgAAAA==.Dotsndash:BAAALgAECgkJCgAAAA==.',
Dp='Dpsshaman:BAABLgAECn8cAAIRAAkJ6x6fCgC1AgARAAkJ6x6fCgC1AgAAAA==.',
Dr='Drarmaku:BAAALgAECgIJAgAAAA==.Dreadingfate:BAAALgAECgkJEAAAAA==.Drscholar:BAAALgAECgIJAwAAAA==.Druidpwnz:BAAALgADCgMJAwAAAA==.',
Du='Duber:BAAALgAECgUJBgAAAA==.Dungorogue:BAABLgAECn8wAAIiAAgJcRAJHgClAQAiAAgJcRAJHgClAQAAAA==.Dustln:BAAALgAECgEJAQAAAA==.',
Dy='Dyonne:BAAALgADCgEJAgAAAA==.',
['Dé']='Déwéy:BAAALgAECgIJAgABLgAFFAQJEwACAJwJAA==.',
El='Elbone:BAAALgADCgUJBQAAAA==.Elidia:BAAALgADCgcJBwAAAA==.Elinia:BAABLgAECn8zAAMbAAkJqxGpIwClAQAbAAgJqRKpIwClAQAWAAkJgQbSNwA2AQAAAA==.Elivoker:BAAALgAECgYJAwAAAA==.Elmdor:BAAALgAECgcJDQAAAA==.Elyndra:BAAALgAFFAEJAQAAAA==.',
En='Eniacoc:BAAALgAECgkJCQAAAA==.Enlag:BAAALgAECgMJAwAAAA==.',
Et='Etriganna:BAAALgAECgEJAQAAAA==.',
Ev='Evilwitch:BAAALgADCgEJAQAAAA==.Evistiah:BAAALgAECgEJAQAAAA==.',
Ex='Excentric:BAABLgAECn8ZAAICAAgJdB6XPQAOAgACAAgJdB6XPQAOAgABLgAFFAkJNgABAAweAA==.Excerpt:BAAALgAECgMJAwABLgAFFAkJNgABAAweAA==.Exortus:BAAALgAFFAMJAwABLgAFFAgJIQACAEMeAA==.',
Fa='Falloutman:BAAALgAECgEJAQAAAA==.Farther:BAABLgAECn8YAAIOAAcJaR+PBgAlAgAOAAcJaR+PBgAlAgABLgAECgcJEQAKAAAAAA==.Farëeya:BAAALgADCgcJDAAAAA==.Fayne:BAAALgAECgUJCQAAAA==.',
Fe='Fellirane:BAAALgADCgUJBQAAAA==.Fernsama:BAAALgAECgYJCAABLgAECgYJCgAKAAAAAA==.',
Fi='Fishton:BAAALgADCgUJCwAAAA==.',
Fl='Flauros:BAABLgAECn8XAAIGAAcJ4Q3khgASAQAGAAcJ4Q3khgASAQAAAA==.',
Fo='Fonk:BAACLgAFFH8IAAIaAAQJqAygBADzAAAaAAQJqAygBADzAAAuAAQKfxUAAxoABwkGIGIBAPQBABoABgkFImIBAPQBAA8ABAlICrwIAJsAAAAA.',
Fr='Fraternite:BAAALgAECgkJDgAAAA==.Froackeh:BAAALgAECggJBwAAAA==.Froackie:BAAALgAECgYJEAABLgAECggJBwAKAAAAAA==.Fruto:BAACLgAFFH8FAAILAAIJThGdRQCKAAALAAIJThGdRQCKAAAuAAQKfzEAAgsACQnLF/ETABACAAsACQnLF/ETABACAAAA.',
Fu='Furricane:BAAALgAECgEJAQAAAA==.',
Ga='Gabriellad:BAAALgAFFAIJBAAAAA==.Garzislao:BAAALgAECggJEAAAAA==.',
Gh='Ghostfox:BAAALgAECgMJAwAAAA==.',
Gi='Giterdonee:BAACLgAFFH8cAAIMAAgJKxb2CADPAQAMAAgJKxb2CADPAQAuAAQKfyEAAgwACQn9IKEEAF8DAAwACQn9IKEEAF8DAAAA.',
Gl='Gleymoulleon:BAAALgAECgQJBwAAAA==.',
Go='Goblinbeans:BAACLgAFFH8LAAIQAAUJlQiPBQBzAQAQAAUJlQiPBQBzAQAuAAQKfxcAAhAACAlLFqckAAMCABAACAlLFqckAAMCAAEuAAUUCQkiABMAHxoA.Goku:BAAALgAECgQJBAAAAA==.Gotchoo:BAAALgAFFAEJAgABLgAFFAMJAwAKAAAAAA==.Gothmommy:BAAALgAECgkJCwAAAA==.',
Gr='Greenbeans:BAAALgAECgUJCQABLgAFFAkJIgATAB8aAA==.Grence:BAAALgAECgUJDAABLgAECgcJEwAKAAAAAA==.Grimreaper:BAABLgAECn8lAAMQAAcJNw3OXABGAQAQAAcJNw3OXABGAQARAAQJPwLJewBVAAAAAA==.Griphöök:BAAALgAECgEJAgAAAA==.Groldin:BAAALgAECgQJBgAAAA==.Groshkar:BAAALgADCgcJCwAAAA==.Grumble:BAAALgAFFAEJAQAAAA==.',
['Gõ']='Gõtchoo:BAAALgAFFAMJAwAAAA==.',
Ha='Hairball:BAABLgAECn8iAAIhAAkJkRQTEwAOAgAhAAkJkRQTEwAOAgAAAA==.Hallona:BAAALgADCgMJAwAAAA==.Hammerthumb:BAAALgAECgUJDAABLgAFFAIJBgAUAPkHAA==.Hanniy:BAAALgAECgIJAQABLgAECgIJAgAKAAAAAA==.Happydavis:BAAALgADCgUJBQAAAA==.Hardstyle:BAAALgAECgEJAQAAAA==.',
Ho='Hotdoggin:BAAALgADCgYJDAAAAA==.Hotpocket:BAAALgAECgIJAgAAAA==.',
Hy='Hyara:BAABLgAECn8rAAIOAAkJghziDwC8AgAOAAkJghziDwC8AgAAAA==.',
['Hì']='Hìm:BAAALgAECgMJBAAAAA==.',
['Hù']='Hùñtarð:BAAALgADCgkJJQAAAA==.',
Ib='Ibefarmin:BAAALgAECgEJAQAAAA==.',
Ic='Icecreammen:BAAALgADCgQJBAAAAA==.Iceshadow:BAACLgAFFH8NAAITAAQJ/RQoJACkAAATAAQJ/RQoJACkAAAuAAQKfxYAAxMABwnjHq0VAG0CABMABwnjHq0VAG0CACMAAgkrAqLDAA8AAAAA.Icobal:BAAALgADCgYJCAAAAA==.',
Il='Illisa:BAAALgADCgMJAwAAAA==.',
In='Inubis:BAAALgAECgIJAgAAAA==.',
Ir='Irongallo:BAAALgADCgEJAQAAAA==.',
Ix='Ixtlipactzin:BAAALgAECgIJAgAAAA==.',
Ja='Jabdis:BAAALgADCgEJAQAAAA==.Jabzulsor:BAAALgAECgEJAQAAAA==.Jacopo:BAABLgAECn8XAAIZAAgJtw43hABbAQAZAAgJtw43hABbAQAAAA==.',
Je='Jeffster:BAAALgAFFAIJBAAAAA==.',
Jo='Jocko:BAAALgAECgMJAwAAAA==.Jordi:BAABLgAECn89AAIOAAkJ2B51GQCNAgAOAAkJ2B51GQCNAgAAAA==.',
Ju='Justinfox:BAAALgADCgEJAQAAAA==.Jutti:BAAALgAECgQJDAAAAA==.',
Ka='Kaellen:BAAALgADCgUJBQAAAA==.Kahnman:BAAALgADCgUJBQAAAA==.Kaka:BAAALgAECgcJEwAAAA==.Kalet:BAAALgAECgMJAwAAAA==.Kandinsky:BAAALgADCgIJAgAAAA==.Kanree:BAACLgAFFH8wAAMTAAgJrgnKHQCCAQATAAgJrgnKHQCCAQAjAAEJ5gYIRgA0AAAuAAQKfz4AAxMACQkiG0oLAJwCABMACQkiG0oLAJwCACMAAQknB7KpACgAAAAA.Kartiri:BAACLgAFFH8iAAMkAAgJEBh8DQDHAQAkAAYJ0Bd8DQDHAQAHAAgJPhU1CwClAQAuAAQKfy8ABCQACQmRHVoGAN4CACQACQmRHVoGAN4CAAcABQnWFm80AGEBAAgABQkPGM0lAPUAAAAA.Katigirl:BAAALgAECgQJCQAAAA==.Kawhi:BAAALgAFFAEJAQAAAA==.',
Ke='Kea:BAACLgAFFH8jAAMYAAYJViDBCgC5AQAYAAUJ5iPBCgC5AQAbAAMJrBYsFAB5AAAuAAQKfzwAAxgACQkNJr0AAOEDABgACQkNJr0AAOEDABsAAwlTI2A1AC4BAAAA.Keedoril:BAAALgADCgUJCgAAAA==.Keratos:BAAALgAECgYJCQAAAA==.',
Kh='Khaalid:BAAALgAECgYJCgABLgAECgYJFwALAIoWAA==.Khran:BAAALgADCgIJAgAAAA==.',
Ki='Kickingfluff:BAAALgADCgIJAgAAAA==.Kimjoonsang:BAAALgAECgEJAQABLgAECgEJAQAKAAAAAA==.Kipz:BAAALgAECgYJBgAAAA==.Kittyboy:BAAALgADCgUJBQAAAA==.',
Ko='Kookykrook:BAABLgAFFH8IAAIHAAQJrQ8yNADyAAAHAAQJrQ8yNADyAAAAAA==.Korxin:BAACLgAFFH8gAAIOAAgJuRSKEQDXAQAOAAgJuRSKEQDXAQAuAAQKfysAAg4ACQkpI+oEAD8DAA4ACQkpI+oEAD8DAAAA.Kozmikfrost:BAAALgADCgEJAQAAAA==.',
Kr='Kreizikat:BAACLgAFFH8PAAIcAAUJDxPFIQBKAQAcAAUJDxPFIQBKAQAuAAQKfzIAAhwACAnJITQOAMgCABwACAnJITQOAMgCAAEuAAUUBgkJABMAjxIA.Krinn:BAAALgAECgYJCQAAAA==.Krios:BAAALgADCgQJBAAAAA==.',
Ku='Kurnhaspios:BAAALgADCgQJBwAAAA==.Kurquaan:BAABLgAECn8aAAMeAAkJgxMJGACRAQAeAAkJgxMJGACRAQAVAAQJEwyWVgDKAAAAAA==.',
La='Lanstan:BAAALgAECgQJBAAAAA==.',
Le='Leilar:BAAALgAECgIJAwAAAA==.Leron:BAAALgAECgYJCAAAAA==.Levitticus:BAACLgAFFH8GAAIXAAMJ2R1+IwAEAQAXAAMJ2R1+IwAEAQAuAAQKfzkAAhcACQlCH0sGACgDABcACQlCH0sGACgDAAEuAAUUCQkXABMAmRoA.',
Li='Liale:BAAALgAFFAEJAQAAAA==.Lideyn:BAAALgAECgIJAgAAAA==.Lidrel:BAAALgAECgYJBgAAAA==.Lightbreath:BAAALgAECgEJAQAAAA==.Lightfury:BAAALgAECgYJCgAAAA==.Limone:BAAALgAECgEJAQAAAA==.',
Lo='Loinari:BAABLgAECn8mAAIVAAcJbAxjDQDVAAAVAAcJbAxjDQDVAAAAAA==.Lokano:BAAALgAECgUJBwAAAA==.',
Lu='Luaru:BAAALgAECgEJAQAAAA==.Ludmylha:BAAALgAFFAEJAQAAAA==.Luisda:BAAALgAECgEJAQAAAA==.Lulak:BAAALgAECgQJCQAAAA==.Lull:BAABLgAECn8tAAMaAAkJ6A5ICwCMAQAaAAkJ6A5ICwCMAQAJAAEJ4QLaYwEdAAAAAA==.Lushil:BAAALgAFFAMJAwAAAA==.Luthin:BAAALgADCgUJBgAAAA==.',
Ly='Lyadre:BAAALgAECgIJAgAAAA==.Lynai:BAAALgADCgIJAgAAAA==.Lyndis:BAAALgAECgQJBAAAAA==.',
Ma='Madness:BAAALgAECgMJAwAAAA==.Magejaf:BAAALgADCgcJDQABLgAECggJIAAPALIYAA==.Magidragon:BAABLgAECn8eAAIBAAkJcA/vDACIAQABAAkJcA/vDACIAQAAAA==.Mandrah:BAAALgADCgQJBQAAAA==.Maybell:BAAALgAECgQJCgAAAA==.',
Md='Mdavis:BAAALgAECgcJBwAAAA==.',
Me='Melt:BAACLgAFFH8vAAMJAAkJtBeQFwAEAgAJAAgJmReQFwAEAgAaAAEJchgiHABbAAAuAAQKfz4AAwkACQl+I/8JAAEDAAkACQl+I/8JAAEDABoABAmoEncsAAwBAAAA.Mepha:BAABLgAFFH8KAAIZAAQJYwwXTwC5AAAZAAQJYwwXTwC5AAAAAA==.Metons:BAAALgAECggJDQAAAA==.Metroboofin:BAAALgAECgMJAQAAAA==.',
Mi='Midei:BAAALgADCgkJFgAAAA==.Midriffluvr:BAAALgAECgQJBwAAAA==.Mikasa:BAAALgADCgEJAQAAAA==.Mike:BAAALgAFFAEJAQABLgAECgcJEQAKAAAAAA==.Mimosa:BAAALgADCgYJCgABLgAECgYJCgAKAAAAAA==.Mirna:BAAALgAECgMJBgAAAA==.Misfitdh:BAAALgAECgEJAQAAAA==.Misfitdk:BAAALgAECgEJBAAAAA==.Misfitdots:BAAALgAECgEJAQAAAA==.Misfitmagi:BAAALgAECgEJBAAAAA==.Misfitmonk:BAAALgAECgEJAgAAAA==.Misfitmorph:BAAALgAECgEJAQAAAA==.Misfitorc:BAAALgAECgEJAQAAAA==.Misfittotem:BAAALgAECgEJAwAAAA==.Misfitx:BAAALgAECgEJAQAAAA==.Missfire:BAAALgAECgkJCQAAAA==.Missðirect:BAAALgAECgEJAQABLgAFFAIJAwAKAAAAAA==.Mistfox:BAAALgAECggJEgAAAA==.',
Mo='Mobiouse:BAAALgADCgYJBgAAAA==.Mollieann:BAAALgAECgQJBgAAAA==.Mommon:BAAALgAECgYJCAAAAA==.Moonraisin:BAAALgAECgMJBQAAAA==.Morrighan:BAAALgADCgQJBQAAAA==.',
Mu='Mukdron:BAAALgADCgIJAgAAAA==.',
['Mâ']='Mâlus:BAAALgAECgYJEwAAAA==.',
['Mä']='Märs:BAAALgAECgMJAwAAAA==.',
Na='Nadra:BAAALgAFFAIJAgAAAA==.Naminé:BAAALgAECgEJAQABLgAFFAQJCAAlAH0WAA==.Nattyrav:BAACLgAFFH8XAAImAAUJ/ByaAwBLAQAmAAUJ/ByaAwBLAQAuAAQKfygAAyYACQkbH8ADAO4CACYACQlnHsADAO4CABEABgnHG/03AFgBAAAA.Nawari:BAAALgAECgIJAwAAAA==.',
Ne='Nemonk:BAACLgAFFH8OAAIjAAMJpx21CgDyAAAjAAMJpx21CgDyAAAuAAQKf1oAAyMACQkeH0AGAOgCACMACQkeH0AGAOgCABMAAQlQA1bWABwAAAAA.Neryssa:BAACLgAFFH8cAAQJAAkJ8BjODgBFAgAJAAkJORjODgBFAgAaAAEJYRVKHgBXAAAPAAEJpRwyHABVAAAuAAQKfzoAAwkACQnYJOkIAAwDAAkACAlvJOkIAAwDABoABAkpJPUYAIMBAAAA.',
Ni='Nickjamez:BAAALgADCgYJBgAAAA==.Nimh:BAAALgADCgUJCgAAAA==.Nipz:BAAALgAECgEJAQABLgAECgYJBgAKAAAAAA==.',
No='Nocter:BAABLgAECn8hAAQJAAkJPx1nNwAuAgAJAAcJ9RxnNwAuAgAPAAUJUiCTCwCBAQAaAAMJ9g0APgC8AAAAAA==.Noqtir:BAAALgAECgUJCgAAAA==.Not:BAAALgADCgcJAgAAAA==.Noyoo:BAAALgADCgEJAQAAAA==.',
Nu='Nunca:BAAALgAECgEJAQAAAA==.',
Ny='Nymura:BAABLgAECn8kAAICAAgJQgrTpwArAQACAAgJQgrTpwArAQAAAA==.',
['Nä']='Näesthra:BAABLgAECn8kAAIbAAgJdBhpHADjAQAbAAgJdBhpHADjAQAAAA==.',
Oa='Oakhugger:BAACLgAFFH8GAAIUAAIJ+QebDABiAAAUAAIJ+QebDABiAAAuAAQKfyQAAxQACQlYEN0PALkBABQACQlYEN0PALkBABUAAQkAAE2xAAAAAAAA.',
Ob='Obelisk:BAAALgADCgYJBgAAAA==.Obelix:BAAALgAECgEJAQAAAA==.',
Ok='Okarun:BAABLgAECn8jAAIGAAcJTB5nQQDuAQAGAAcJTB5nQQDuAQABLgAFFAQJCAAlAH0WAA==.',
Ol='Oldeone:BAAALgAECgMJBAAAAA==.Olillivia:BAAALgADCgIJAQAAAA==.Olyvivia:BAABLgAFFH8GAAInAAIJuwKcFgBhAAAnAAIJuwKcFgBhAAAAAA==.',
Om='Omgega:BAABLgAECn9EAAICAAgJWhuTNwAjAgACAAgJWhuTNwAjAgAAAA==.',
On='Onichan:BAAALgAECgYJCQABLgAFFAkJJQARAGwcAA==.Onimeek:BAABLgAECn9eAAMNAAkJHSBqBwC7AgANAAkJHSBqBwC7AgAGAAIJPAleDgE7AAAAAA==.',
Or='Oragar:BAAALgAECgQJBAAAAA==.Oryn:BAAALgAFFAEJAwABLgAFFAIJBgABACcVAA==.Oryx:BAAALgAECgEJAwAAAA==.',
Pa='Pallywahwah:BAAALgAFFAEJAQAAAA==.Palpitations:BAAALgAECgcJEAAAAA==.Paper:BAAALgAFFAkJKQAAAQ==.Paudetunia:BAAALgADCgIJAgAAAA==.',
Pe='Peacefullev:BAACLgAFFH8XAAMTAAkJmRpdCwBRAgATAAkJmRpdCwBRAgAjAAEJKQuFRAA2AAAuAAQKfycAAxMACAnmIK4OALUCABMACAnmIK4OALUCACMABwnDFY4mAIEBAAAA.Peiko:BAAALgADCgIJAgAAAA==.Pelagius:BAAALgADCgYJBwAAAA==.Penance:BAAALgAECgEJAQAAAA==.Pestilence:BAAALgAECggJDQAAAA==.Pewpewpew:BAAALgAECgYJCgAAAA==.',
Ph='Phantomthief:BAAALgAECggJAwAAAA==.Phyllus:BAAALgAFFAIJAwAAAA==.',
Pi='Pictureplane:BAAALgADCgEJAQAAAA==.Pipe:BAAALgAFFAEJAQAAAA==.Pipeleto:BAACLgAFFH8VAAIMAAQJWhjSDQA1AQAMAAQJWhjSDQA1AQAuAAQKfx0AAgwACQmJGPUeAPcBAAwACQmJGPUeAPcBAAAA.',
Po='Poochimus:BAABLgAECn8hAAImAAkJsROxCgAOAgAmAAkJsROxCgAOAgAAAA==.Pookong:BAAALgAECgUJCQAAAA==.Poonslayerxx:BAAALgADCgMJAwAAAA==.',
Pr='Previdius:BAAALgAECggJEQAAAA==.Priestpwnz:BAAALgAECgYJDwAAAA==.Protomán:BAABLgAECn8ZAAIJAAkJGRawBwCUAQAJAAkJGRawBwCUAQAAAA==.Proximity:BAAALgADCgQJBQABLgADCgcJCwAKAAAAAA==.',
Ps='Psychmike:BAAALgAECgEJAQAAAA==.',
Pw='Pwrbttm:BAAALgAECgEJAQABLgAFFAUJEgAOACMLAA==.',
['Pé']='Pépega:BAAALgAECgIJAgAAAA==.',
Ra='Rafferno:BAAALgAECgEJAgAAAA==.',
Re='Redeemedlev:BAACLgAFFH8kAAIYAAYJrRSjDQBvAQAYAAYJrRSjDQBvAQAuAAQKf0IAAhgACQnkISYEAFcDABgACQnkISYEAFcDAAEuAAUUCQkXABMAmRoA.Reds:BAAALgAECgEJAQAAAA==.Relax:BAABLgAECn8YAAIGAAYJOh5ZUQCRAQAGAAYJOh5ZUQCRAQAAAA==.',
Rh='Rhesand:BAABLgAECn8ZAAMHAAgJPAS8VgDXAAAHAAgJPAS8VgDXAAAIAAEJjwGoLQAEAAAAAA==.Rhëa:BAAALgAECgMJBAAAAA==.',
Ri='Riellus:BAAALgADCgkJFQAAAA==.Riiu:BAABLgAECn8cAAIjAAYJHR0wJwB9AQAjAAYJHR0wJwB9AQABLgAFFAMJCgACADMbAA==.Rindra:BAAALgAECgUJCAAAAA==.Rinkelle:BAAALgAECgYJBgAAAA==.Riven:BAABLgAECn8VAAQBAAYJjhzxngA9AQABAAYJDxrxngA9AQAdAAMJThMwDwBrAAAfAAEJkR+jCQBdAAAAAA==.Rixin:BAECLgAFFH8iAAMZAAkJRxxBEQBTAgAZAAkJRxxBEQBTAgAoAAEJAABxMwAAAAAuAAQKfzwAAhkACQk3JgYGAEkDABkACQk3JgYGAEkDAAAA.Rixryu:BAEALgADCgkJFgABLgAFFAkJIgAZAEccAA==.',
Ro='Roaka:BAAALgADCggJCAAAAA==.Rokom:BAACLgAFFH8LAAIMAAMJ1xh/NADfAAAMAAMJ1xh/NADfAAAuAAQKfyYAAgwACQkkIG8TALICAAwACQkkIG8TALICAAAA.Rollster:BAAALgAECgQJBAAAAA==.Rotandroll:BAAALgADCgYJBgABLgAECgEJAQAKAAAAAA==.',
Ru='Runed:BAAALgAECgEJAgAAAA==.Ruwey:BAAALgAECgEJAQAAAA==.',
Ry='Ryuk:BAAALgAECgYJEQAAAA==.',
['Rè']='Rèzurrect:BAAALgAECgUJDgABLgAFFAEJAQAKAAAAAA==.',
Sa='Saaratharaxx:BAAALgAECgUJDAAAAA==.Sackhunter:BAABLgAECn8aAAIGAAcJEg6ViwAJAQAGAAcJEg6ViwAJAQAAAA==.Saero:BAABLgAECn8UAAIXAAcJbBmUKgC7AQAXAAcJbBmUKgC7AQAAAA==.Sake:BAAALgAECgUJBQABLgAFFAUJGgAjAHEUAA==.Salla:BAAALgAECgUJBQAAAA==.Saluuknir:BAACLgAFFH8FAAIHAAIJ7QcLVwBwAAAHAAIJ7QcLVwBwAAAuAAQKfzEAAwcACQmBD/smAKoBAAcACQlBD/smAKoBAAgABgloB4ojAAwBAAAA.Saoko:BAAALgADCgEJAQAAAA==.Saphh:BAABLgAECn8hAAQoAAgJFxwvBgAzAQAZAAcJbBvMZgDBAQAnAAUJ/xnlEwA/AQAoAAUJkhovBgAzAQABLgAFFAcJHgAnAGoXAA==.Satrath:BAABLgAFFH8FAAIBAAIJdgkSqgCAAAABAAIJdgkSqgCAAAABLgAFFAYJCAAiAD4iAA==.',
Se='Sedalin:BAAALgAECgEJAQAAAA==.Seekae:BAAALgAECgEJAQAAAA==.Sepidasprite:BAAALgADCgEJAQAAAA==.Setoplek:BAAALgAECgEJAQAAAA==.',
Sh='Shaddoot:BAAALgAFFAIJBAAAAA==.Shadowangel:BAAALgAFFAEJAQAAAA==.Shadowbladez:BAAALgAECgEJAQAAAA==.Shadowxd:BAABLgAFFH8LAAMcAAMJFxBaRgCcAAAcAAMJFxBaRgCcAAAeAAEJGwgAAAAAAAAAAA==.Sharky:BAAALgAFFAIJAwABLgAFFAkJMgAfAMUdAA==.Shaulana:BAAALgADCgYJBgAAAA==.Sheepforfree:BAAALgAECgIJAgAAAA==.Shenwu:BAAALgAFFAIJAwAAAA==.Shin:BAAALgADCgEJAQAAAA==.Shinishamy:BAAALgADCgEJAQAAAA==.Shirokuma:BAABLgAFFH8hAAIeAAgJhCFaAwDxAQAeAAgJhCFaAwDxAQABLgAFFAYJBwAFANUNAA==.Shorty:BAAALgADCgYJEAAAAA==.',
Si='Siera:BAAALgAECgQJBQABLgAECggJDQAKAAAAAA==.Sigrun:BAAALgADCgIJAgAAAA==.Sipz:BAAALgAECgIJAgABLgAECgYJBgAKAAAAAA==.',
Sk='Skinbone:BAAALgADCgQJBAAAAA==.Skyrius:BAABLgAFFH8GAAIZAAIJ2wk7+AB1AAAZAAIJ2wk7+AB1AAAAAA==.',
Sl='Slaty:BAAALgAECgIJAgAAAA==.Slingshotz:BAABLgAECn8ZAAIhAAkJ4RmrBgCWAgAhAAkJ4RmrBgCWAgAAAA==.Slootbag:BAAALgAECgkJDwAAAA==.',
Sm='Smolchili:BAAALgADCgkJCQAAAA==.',
Sn='Snax:BAAALgAECgIJAgAAAA==.Sneakylev:BAACLgAFFH8JAAIiAAQJtxDFDgAcAQAiAAQJtxDFDgAcAQAuAAQKfxkAAiIACAlxG9YTAAUCACIACAlxG9YTAAUCAAEuAAUUCQkXABMAmRoA.Sneux:BAAALgADCgcJDQAAAA==.Snuuze:BAACLgAFFH8PAAICAAMJJiEzTgASAQACAAMJJiEzTgASAQAuAAQKfyoAAgIACAkWI3AlAJECAAIACAkWI3AlAJECAAEuAAUUBgkLAA0AgRYA.Snuuzi:BAAALgAFFAEJAQABLgAFFAYJCwANAIEWAA==.',
So='Soberloki:BAAALgAECgIJAgAAAA==.Sola:BAAALgAECgEJAQAAAA==.Solari:BAABLgAECn8cAAMGAAkJjRrtJQA2AgAGAAkJ1BftJQA2AgANAAcJlhUVHwDGAQAAAA==.Sole:BAAALgAECgMJAwAAAA==.Solix:BAAALgAECgEJAQAAAA==.Solpra:BAAALgAECgEJAQAAAA==.Solune:BAAALgAECgIJAwAAAA==.Solvi:BAAALgAECgYJDgAAAA==.Sophispapa:BAABLgAECn9CAAICAAcJ5SChPAASAgACAAcJ5SChPAASAgAAAA==.Souprage:BAABLgAECn8UAAIMAAgJvhApMwB+AQAMAAgJvhApMwB+AQAAAA==.',
Sp='Spellmaden:BAAALgADCgMJBgABLgAFFAQJCAAlAH0WAA==.Spywar:BAAALgAECgYJCAABLgAECggJHwARACkXAA==.',
St='Starlighter:BAABLgAECn8qAAMWAAkJiAvhKwB2AQAWAAkJiAvhKwB2AQAbAAYJGQXVSwC0AAABLgAFFAIJAgAKAAAAAA==.Starsomave:BAAALgAFFAIJAgAAAA==.Steen:BAAALgAECgQJBwAAAA==.Stinkylev:BAACLgAFFH8KAAInAAUJTA0hCQAHAQAnAAUJTA0hCQAHAQAuAAQKfyUAAicACQloH7oAAPACACcACQloH7oAAPACAAEuAAUUCQkXABMAmRoA.Strentor:BAAALgAECgQJBQAAAA==.',
Su='Sunshinë:BAAALgAECgEJAgAAAA==.Supressor:BAAALgADCgQJCAABLgAECgIJAgAKAAAAAA==.',
Sy='Sylvester:BAAALgADCgIJAgAAAA==.',
['Sé']='Sérolis:BAAALgADCgEJAQAAAA==.',
Ta='Taehausx:BAACLgAFFH9sAAILAAkJ9yYCAACmAwALAAkJ9yYCAACmAwAuAAQKfzAAAwsACQlSJB8GACUDAAsACQlSJB8GACUDACMAAgk5HjZdAKIAAAAA.Tarmo:BAAALgADCgYJFgAAAA==.',
Te='Telesto:BAAALgAECgIJAgABLgAFFAgJIQACAEMeAA==.Templeton:BAAALgADCgMJAwAAAA==.Tenath:BAABLgAECn8bAAINAAcJsRK5KAA3AQANAAcJsRK5KAA3AQAAAA==.',
Th='Thaleon:BAAALgAECgcJDgAAAA==.Tharella:BAAALgAECgYJCwAAAA==.Tharion:BAAALgAFFAIJAgAAAA==.Thauriel:BAAALgAECgYJCAAAAA==.Thrumple:BAAALgADCgYJCgAAAA==.',
Ti='Tipz:BAAALgAECgIJAwABLgAECgYJBgAKAAAAAA==.Titania:BAABLgAECn8eAAIXAAkJTAa9QAB1AQAXAAkJTAa9QAB1AQAAAA==.',
To='Toe:BAAALgAFFAgJKwAAAQ==.',
Tr='Trollztoll:BAAALgAECgIJAgAAAA==.',
Tu='Tuulk:BAAALgADCgIJAgAAAA==.',
Ty='Typical:BAAALgADCgcJCwAAAA==.',
Ug='Uggoorc:BAACLgAFFH8SAAIOAAUJIwvGTQAQAQAOAAUJIwvGTQAQAQAuAAQKfywAAg4ACQlSHocHAAkCAA4ACQlSHocHAAkCAAAA.Uggotroll:BAAALgAECgUJCwABLgAFFAUJEgAOACMLAA==.Ugrin:BAAALgAECgEJAQAAAA==.',
Un='Unholylord:BAAALgAECggJDAABLgAFFAgJIQAWAGkgAA==.',
Ut='Uthok:BAAALgADCgcJBwAAAA==.',
Va='Vacalocà:BAABLgAECn8UAAIUAAgJUQ1iGQBEAQAUAAgJUQ1iGQBEAQAAAA==.Valerian:BAAALgAECggJDgAAAA==.Validori:BAAALgADCgEJAQAAAA==.Van:BAABLgAECn8aAAMJAAkJAgg2DQAjAQAJAAkJAgg2DQAjAQAaAAEJjgNGFQAVAAAAAA==.Vaultkey:BAAALgADCgIJAwAAAA==.',
Ve='Vegesha:BAAALgAECgEJAgAAAA==.Veinke:BAABLgAECn8VAAIFAAkJ+w5gCwClAQAFAAkJ+w5gCwClAQAAAA==.Vengefullev:BAABLgAECn8UAAIFAAYJ2xNGAwAoAQAFAAYJ2xNGAwAoAQABLgAFFAkJFwATAJkaAA==.Venin:BAAALgAECgYJCwAAAA==.Vessarind:BAAALgADCgEJAgAAAA==.',
Vi='Vitora:BAAALgAECgYJEQAAAA==.',
Vo='Voidkurn:BAAALgADCgYJCQAAAA==.Von:BAAALgADCgIJAgAAAA==.',
Vy='Vyse:BAAALgADCgYJBgAAAA==.',
Wa='Waally:BAAALgAECgcJEwAAAA==.Wahgwan:BAAALgAECgMJAwAAAA==.Waleran:BAAALgADCgIJAgAAAA==.Warrdaddy:BAAALgAECgYJEgABLgADCgcJBwAKAAAAAA==.Warriorbp:BAAALgADCgkJFwAAAA==.Wattz:BAAALgAECgYJBgAAAA==.',
We='Weebsora:BAACLgAFFH8HAAIGAAYJKxDuGgA7AQAGAAYJKxDuGgA7AQAuAAQKfxkAAgYACQndHmgEAPABAAYACQndHmgEAPABAAAA.Weeple:BAAALgADCgkJCQAAAA==.',
Wo='Worldtree:BAABLgAECn8WAAIQAAYJnw+MZQArAQAQAAYJnw+MZQArAQAAAA==.',
Wy='Wynne:BAAALgAECggJCwAAAA==.',
Xa='Xaelthira:BAAALgAECgYJCgAAAA==.Xaphån:BAAALgAECgYJCAAAAA==.',
Xe='Xerath:BAAALgADCgYJCAAAAA==.',
Xi='Xips:BAAALgADCgMJAwABLgAECgYJBgAKAAAAAA==.',
Xo='Xoru:BAAALgADCgYJBgAAAA==.Xoruk:BAAALgADCgQJBAABLgAFFAIJAgAKAAAAAA==.Xorun:BAAALgAECgEJAQABLgAFFAIJAgAKAAAAAA==.',
Xz='Xzarrion:BAAALgAECgEJAQAAAA==.',
Ya='Yadhi:BAABLgAECn8XAAQLAAYJihbpMgA1AQALAAUJihbpMgA1AQATAAYJoBCgUAAsAQAjAAUJ3AdDaACFAAAAAA==.',
Ye='Yetkin:BAAALgAECgYJDQAAAA==.',
Yi='Yifftron:BAAALgAECgYJBgABLgAECggJHgAOAAogAA==.Yimomo:BAABLgAECn8cAAMbAAkJhRUbLgCMAQAbAAkJhRUbLgCMAQAWAAcJtwcMTgDYAAAAAA==.',
Yo='Yoshira:BAAALgAECgMJAwABLgAECggJDQAKAAAAAA==.',
Yv='Yveltal:BAAALgAECggJCQAAAA==.',
Yz='Yzra:BAAALgAECgQJBgAAAA==.',
Za='Zahndrekh:BAAALgADCgUJBQAAAA==.Zalconn:BAACLgAFFH8cAAMiAAUJVyY4DgCwAQAiAAUJVyY4DgCwAQAlAAIJDRdxDACZAAAuAAQKfysAAyIACQkcJjoDAGwDACIACQnZJToDAGwDACUAAQneJoEbAHEAAAAA.Zarrona:BAACLgAFFH8IAAIlAAQJfRaKAgAVAQAlAAQJfRaKAgAVAQAuAAQKfyYAAyUACAkRHxkFAB4CACUABwm2HRkFAB4CACIABwmRGlEfAJsBAAAA.Zayah:BAABLgAECn8aAAIRAAgJLxaMKQCkAQARAAgJLxaMKQCkAQAAAA==.',
Zi='Zinmaris:BAAALgAFFAIJAgAAAA==.Zivanka:BAAALgAECgcJEAAAAA==.',
Zn='Znasty:BAABLgAECn8tAAIiAAkJBSSoAgAuAwAiAAkJBSSoAgAuAwAAAA==.',
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
