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

local lookup = {'Mage-Frost','Paladin-Retribution','Paladin-Protection','Warrior-Arms','DemonHunter-Vengeance','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Unknown-Unknown','Warrior-Fury','DemonHunter-Havoc','Hunter-BeastMastery','Monk-Brewmaster','Warlock-Affliction','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Monk-Mistweaver','Druid-Feral','Druid-Balance','Priest-Shadow','Paladin-Holy','Priest-Discipline','DeathKnight-Unholy','Warlock-Destruction','Priest-Holy','Druid-Restoration','Mage-Fire','Druid-Guardian','Mage-Arcane','Hunter-Marksmanship','Hunter-Survival','Rogue-Subtlety','Monk-Windwalker','Evoker-Preservation','Rogue-Outlaw','Shaman-Enhancement','DeathKnight-Frost','DeathKnight-Blood',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abeblinkin:BAABLgAECn9NAAIBAAkJkSJ1AgDbAgABAAkJkSJ1AgDbAgAAAA==.',
Ac='Accursed:BAAALgAECgEJAQAAAA==.',
Ad='Adcrusty:BAAALgAECgEJAQAAAA==.',
Ae='Aegrias:BAABLgAECn8hAAICAAkJEx48JwCJAgACAAkJEx48JwCJAgAAAA==.Aeledron:BAAALgADCgQJBQAAAA==.Aerodria:BAABLgAECn9uAAMCAAkJCxi/BwDBAQACAAkJCxi/BwDBAQADAAUJcxEeBQAOAQAAAA==.',
Aj='Ajm:BAABLgAFFH8LAAIEAAQJmxT6GQAWAQAEAAQJmxT6GQAWAQAAAA==.',
Ak='Akarii:BAAALgAECgYJEAAAAA==.Akeno:BAACLgAFFH8GAAMFAAYJ1Q1aBAC8AAAFAAMJaBNaBAC8AAAGAAMJeAVUOgBuAAAuAAQKfxUAAgUACAlAI1kBABgDAAUACAlAI1kBABgDAAAA.Akiaura:BAAALgAECgYJEgAAAA==.Akime:BAAALgAECgYJDwAAAA==.Akudama:BAABLgAECn8tAAMHAAkJnxprEABkAgAHAAkJnxprEABkAgAIAAIJqQkFNwBfAAABLgAFFAgJLgAJACQZAA==.',
Al='Alarm:BAAALgADCgEJAQABLgADCgcJCwAKAAAAAA==.Albince:BAAALgADCgIJAgAAAA==.Aldanil:BAAALgAECggJEAAAAA==.Aligh:BAAALgAECgEJAQAAAA==.Alisae:BAAALgADCgMJAwAAAA==.Alma:BAAALgAECgUJBQAAAA==.Alye:BAAALgAECgcJEAAAAA==.',
Am='Amellis:BAAALgAECgUJCQAAAA==.',
An='Ananac:BAAALgADCgEJAQAAAA==.Andreasham:BAAALgADCgEJAQAAAA==.Andrius:BAAALgAECgQJBQAAAA==.Annisseda:BAACLgAFFH8lAAMLAAgJ4x5ECQDKAQALAAcJHyFECQDKAQAEAAQJHxkjCwDoAAAuAAQKfysAAwsACQmLJP0HAN8CAAsACQmLJP0HAN8CAAQAAQl9ITFkAFkAAAAA.',
Ar='Aradril:BAAALgADCgcJCwAAAA==.Arktos:BAAALgAECgYJDQAAAA==.Arrhythmia:BAAALgAECgkJJQABLgAFFAgJKAAKAAAAAQ==.',
As='Ashrak:BAAALgAECgQJBAAAAA==.Ashér:BAAALgAECgEJAQAAAA==.Astaulis:BAAALgADCgUJCAAAAA==.',
Ax='Axelle:BAAALgAECggJDwAAAA==.',
Az='Azzy:BAACLgAFFH8uAAILAAgJ2hqUAgBsAgALAAgJ2hqUAgBsAgAuAAQKfz4AAgsACQnlJXgCAJMDAAsACQnlJXgCAJMDAAAA.',
Ba='Babyboomie:BAAALgAECgUJBwAAAA==.Bagagwa:BAAALgADCgcJCAAAAA==.Bal:BAABLgAECn8kAAQMAAgJVhXKHQDRAQAMAAgJ8xLKHQDRAQAGAAYJWQ/EkwD5AAAFAAIJBiFQKQBeAAAAAA==.Balam:BAAALgADCgEJAQAAAA==.Balana:BAAALgAECgUJCAAAAA==.Bambudda:BAAALgAFFAIJAgAAAA==.Bananski:BAABLgAECn8VAAMDAAYJUQ2vJADjAAADAAUJIA+vJADjAAACAAYJXwa49QDEAAAAAA==.Bandu:BAAALgADCgEJAgAAAA==.Barkeep:BAABLgAECn8aAAINAAkJaw+WOADMAQANAAkJaw+WOADMAQAAAA==.Bassoon:BAAALgAECgMJAwABLgAFFAIJBQAOAE4RAA==.',
Be='Beeflocks:BAABLgAECn8jAAIPAAkJMhxABwD/AQAPAAkJMhxABwD/AQAAAA==.Beefpile:BAAALgADCgUJBQAAAA==.Bekarn:BAABLgAECn8YAAMQAAcJeAofUwA5AQAQAAcJeAofUwA5AQARAAMJ7AhzegBaAAAAAA==.Benafflock:BAAALgAECgMJAwAAAA==.Bennafflock:BAAALgAECgUJCwAAAA==.Bergz:BAAALgAECgMJAgAAAA==.',
Bh='Bhp:BAAALgADCgMJAwABLgAECgMJAwAKAAAAAA==.',
Bi='Bigbleu:BAAALgAECgUJCQABLgAECggJJwASAHkdAA==.Bigdh:BAAALgAECgYJDgAAAA==.Bigdraco:BAAALgADCgQJBAAAAA==.Biglev:BAAALgADCgMJAwABLgAFFAgJFgATAPgaAA==.Bigpapapump:BAAALgAECgEJAQAAAA==.Bigxthaplug:BAAALgAECgYJCQAAAA==.Bilboswagins:BAABLgAECn8UAAILAAcJyxwLIwA9AgALAAcJyxwLIwA9AgAAAA==.Billski:BAAALgAECgcJCQAAAA==.Billyspike:BAABLgAECn8YAAMUAAYJ0RrjDQDVAQAUAAYJ0RrjDQDVAQAVAAEJkhKtigA2AAABLgAECgkJFAAWAEYdAA==.Billyspiked:BAAALgAECgIJAgABLgAECgkJFAAWAEYdAA==.Billyspikedh:BAAALgADCgMJAwABLgAECgkJFAAWAEYdAA==.Billyspikeev:BAAALgADCgYJBgABLgAECgkJFAAWAEYdAA==.Billyspikepd:BAABLgAECn8UAAMCAAkJBxTFTgDbAQACAAkJBxTFTgDbAQAXAAEJ7wILlgAqAAABLgAECgkJFAAWAEYdAA==.Billyspikepr:BAABLgAECn8UAAMWAAkJRh2dAgD1AQAWAAkJRh2dAgD1AQAYAAEJZRg+UQBHAAAAAA==.Billyspikerg:BAAALgADCgIJAgABLgAECgkJFAAWAEYdAA==.',
Bl='Blammo:BAAALgADCgcJCQAAAA==.Blobcat:BAABLgAECn8cAAIVAAcJSx+sAwCpAQAVAAcJSx+sAwCpAQAAAA==.Blobknight:BAAALgADCgEJAQAAAA==.Blobpally:BAACLgAFFH8NAAICAAQJ0RT9TgAQAQACAAQJ0RT9TgAQAQAuAAQKfyAAAgIABwm7IW0dALoCAAIABwm7IW0dALoCAAAA.Bloodhase:BAACLgAFFH8IAAIZAAQJLBgJMAADAQAZAAQJLBgJMAADAQAuAAQKfxgAAhkABwkbEW2XADoBABkABwkbEW2XADoBAAAA.Bloodprince:BAAALgAECgMJAwAAAA==.Bluecantsee:BAAALgAECgEJAQAAAA==.Bluecard:BAACLgAFFH8kAAIJAAgJEBk8CAAhAgAJAAgJEBk8CAAhAgAuAAQKfywABAkACQl+IcYPAM4CAAkACQl+IcYPAM4CABoAAwnVGMg5AM0AAA8AAQkXIY0nAFMAAAAA.',
Bo='Bokunh:BAAALgAECgYJEgAAAA==.Bookofmoon:BAAALgAECgUJBQAAAA==.Boomywhoomy:BAAALgAECgIJBQAAAA==.Bootstrap:BAAALgAECgkJCQAAAA==.Bothenheim:BAACLgAFFH8gAAMCAAgJkR1sEwDQAQACAAgJkR1sEwDQAQADAAMJQQxSEwBfAAAuAAQKfyYAAgIACQmAIgYVAMQCAAIACQmAIgYVAMQCAAAA.Bowdaddy:BAAALgADCgcJBwAAAA==.Boxtribution:BAAALgAECgMJBQAAAA==.Boxxman:BAAALgAECgcJAQAAAA==.',
Br='Breakdown:BAAALgAECgIJAgAAAA==.Brewsimmons:BAABLgAFFH8YAAITAAkJDBSLBgAmAgATAAkJDBSLBgAmAgAAAA==.Brüisér:BAACLgAFFH8FAAIDAAIJxwbJFABUAAADAAIJxwbJFABUAAAuAAQKfyUAAgMACQluD5IYAFgBAAMACQluD5IYAFgBAAAA.',
Bu='Bublz:BAAALgAECgcJBwAAAA==.Bumpinuglies:BAAALgAECgEJAQAAAA==.',
Ca='Callamdrake:BAAALgAECgEJAQAAAA==.Callamsvoid:BAAALgAECgMJCAAAAA==.Camazotz:BAAALgAECgUJBwAAAA==.Capie:BAAALgAECgkJEAAAAA==.Carathea:BAABLgAECn8iAAIbAAgJMSCCDACLAgAbAAgJMSCCDACLAgAAAA==.Cardstock:BAAALgAECggJCAABLgAFFAgJKAAKAAAAAQ==.Carrotbear:BAAALgADCgQJBAAAAA==.Cassiopeià:BAAALgAECgMJAwAAAA==.Caylen:BAACLgAFFH8gAAIcAAgJPxuJAwBzAgAcAAgJPxuJAwBzAgAuAAQKfyAAAhwACAm3HkIRAK0CABwACAm3HkIRAK0CAAAA.Cayth:BAACLgAFFH8aAAMJAAUJ0CDCOABnAQAJAAUJux3COABnAQAPAAEJJR+qGABcAAAuAAQKfysAAwkACQnMIakFAGIDAAkACQnMIakFAGIDABoAAgkLAx9VAG8AAAAA.',
Ce='Cemie:BAAALgADCgcJBwAAAA==.Centralia:BAAALgADCgYJBwAAAA==.Centri:BAACLgAFFH8sAAMBAAkJIRumAwDcAgABAAkJIRumAwDcAgAdAAMJvhc9AwCpAAAuAAQKfyQAAgEACQlGJRYaAA8DAAEACQlGJRYaAA8DAAAA.Cerestus:BAAALgADCgMJAwAAAA==.',
Ch='Chadbear:BAABLgAECn8VAAMeAAgJRBU8GQCFAQAeAAgJRBU8GQCFAQAUAAMJwQm6NAAwAAAAAA==.Chadtones:BAAALgAECgYJCgAAAA==.Chimueloh:BAAALgADCgQJBAAAAA==.Chiron:BAAALgADCgIJAgAAAA==.Chowa:BAAALgAFFAMJAwAAAA==.Chrleone:BAAALgAECgIJAwAAAA==.Chu:BAAALgAECgEJAQAAAA==.',
Cl='Cleverlev:BAABLgAECn8cAAIfAAYJthkQBwBDAQAfAAYJthkQBwBDAQABLgAFFAgJFgATAPgaAA==.',
Co='Colapse:BAAALgAECgEJAQAAAA==.Colivism:BAABLgAECn8kAAIBAAgJpRaleQDeAQABAAgJpRaleQDeAQAAAA==.Colívis:BAAALgAECgQJBQAAAA==.Commodorecdx:BAAALgADCgcJBwAAAA==.Cotali:BAAALgADCgUJBQABLgAECggJIgAbADEgAA==.',
Cr='Crackfiend:BAAALgADCgUJBwAAAA==.Crispi:BAAALgADCgYJBAAAAA==.Cruellev:BAABLgAECn8XAAIPAAUJ1RMwBAD8AAAPAAUJ1RMwBAD8AAABLgAFFAgJFgATAPgaAA==.Crymbrulay:BAAALgAECgYJCAAAAA==.',
Cu='Cuurtis:BAAALgADCgEJAQAAAA==.',
Cz='Czernobog:BAAALgAECgMJAwAAAA==.',
Da='Daedrenda:BAAALgAECgMJBAAAAA==.Daeland:BAABLgAECn8yAAILAAkJ0hDjJQDJAQALAAkJ0hDjJQDJAQAAAA==.Dakky:BAAALgAFFAQJAQAAAA==.Dandakian:BAAALgAECgEJAgAAAA==.',
De='Deadwrs:BAAALgADCgIJAgAAAA==.Deathbruiser:BAAALgAECgQJBAAAAA==.Deathsgrace:BAAALgAECgkJCQAAAA==.Deathtank:BAAALgAFFAIJBAAAAA==.Deathtolife:BAAALgAECgQJCAAAAA==.Decima:BAABLgAECn8pAAIVAAkJ4A2wBwARAQAVAAkJ4A2wBwARAQAAAA==.Degrance:BAAALgAECgUJBQAAAA==.Demeter:BAACLgAFFH8fAAQNAAcJ8Bh0MQBMAQANAAUJfCF0MQBMAQAgAAIJ2gWBIwCSAAAhAAEJ/iM4EgBnAAAuAAQKfyIABA0ACQlYIuASAKACAA0ACAk6HuASAKACACAABglxILUoAOQBACEAAQkoIM9TAF8AAAAA.Demonpunter:BAAALgAFFAIJBAABLgAFFAgJHQAJAMYfAA==.Dewussi:BAACLgAFFH8TAAICAAQJnAnpWwD4AAACAAQJnAnpWwD4AAAuAAQKfyQAAwMABwniHYENAO8BAAMABwk4GYENAO8BAAIABwlnG29pAJwBAAAA.',
Di='Diablita:BAAALgAECgEJAQAAAA==.Dicethrower:BAAALgAECgQJBwAAAA==.Dinkltn:BAAALgAECgUJCgAAAA==.Dinoscarr:BAAALgAECgYJDwAAAA==.Dixiinormis:BAAALgAECgkJDgABLgAECgkJTQABAJEiAA==.',
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
Ex='Excentric:BAABLgAECn8ZAAICAAgJdB6XPQAOAgACAAgJdB6XPQAOAgABLgAFFAkJLAABACEbAA==.Excerpt:BAAALgAECgMJAwABLgAFFAkJLAABACEbAA==.Exortus:BAAALgAFFAMJAwABLgAFFAgJIAACAJEdAA==.',
Fa='Falloutman:BAAALgAECgEJAQAAAA==.Farther:BAABLgAECn8YAAINAAcJbB8PBQAvAgANAAcJbB8PBQAvAgAAAA==.Farëeya:BAAALgADCgcJDAAAAA==.Fayne:BAAALgAECgUJCQAAAA==.',
Fe='Fellirane:BAAALgADCgUJBQAAAA==.Fernsama:BAAALgAECgYJCAAAAA==.',
Fi='Fishton:BAAALgADCgUJCwAAAA==.',
Fl='Flauros:BAABLgAECn8XAAIGAAcJ4Q3khgASAQAGAAcJ4Q3khgASAQAAAA==.',
Fr='Fraternite:BAAALgAECgkJDgAAAA==.Froackeh:BAAALgAECggJBwAAAA==.Froackie:BAAALgAECgYJEAABLgAECggJBwAKAAAAAA==.Fruto:BAACLgAFFH8FAAIOAAIJThGdRQCKAAAOAAIJThGdRQCKAAAuAAQKfzEAAg4ACQnLF/ETABACAA4ACQnLF/ETABACAAAA.',
Fu='Furricane:BAAALgAECgEJAQAAAA==.',
Ga='Gabriellad:BAAALgAFFAIJBAAAAA==.Garzislao:BAAALgAECggJEAAAAA==.',
Gh='Ghostfox:BAAALgAECgMJAwAAAA==.',
Gi='Giterdonee:BAACLgAFFH8cAAILAAgJKxb2CADPAQALAAgJKxb2CADPAQAuAAQKfyEAAgsACQn9IKEEAF8DAAsACQn9IKEEAF8DAAAA.',
Gl='Gleymoulleon:BAAALgAECgQJBwAAAA==.',
Go='Goblinbeans:BAACLgAFFH8LAAIQAAUJlQiPBQBzAQAQAAUJlQiPBQBzAQAuAAQKfxcAAhAACAlLFqckAAMCABAACAlLFqckAAMCAAEuAAUUCQkYABMADBQA.Goku:BAAALgAECgQJBAAAAA==.Gotchoo:BAAALgAFFAEJAgABLgAFFAMJAwAKAAAAAA==.Gothmommy:BAAALgAECgIJAgAAAA==.',
Gr='Greenbeans:BAAALgAECgUJCQABLgAFFAkJGAATAAwUAA==.Grence:BAAALgAECgUJDAABLgAECgcJEwAKAAAAAA==.Grimreaper:BAABLgAECn8lAAMQAAcJNw3OXABGAQAQAAcJNw3OXABGAQARAAQJPwLJewBVAAAAAA==.Griphöök:BAAALgAECgEJAgAAAA==.Groldin:BAAALgAECgQJBgAAAA==.Groshkar:BAAALgADCgcJCwAAAA==.Grumble:BAAALgAFFAEJAQAAAA==.',
['Gõ']='Gõtchoo:BAAALgAFFAMJAwAAAA==.',
Ha='Hairball:BAABLgAECn8iAAIhAAkJkRQTEwAOAgAhAAkJkRQTEwAOAgAAAA==.Hallona:BAAALgADCgMJAwAAAA==.Hammerthumb:BAAALgAECgUJDAABLgAFFAIJBgAUAPkHAA==.Hanniy:BAAALgAECgIJAQABLgAECgIJAgAKAAAAAA==.Happydavis:BAAALgADCgUJBQAAAA==.',
Ho='Hotdoggin:BAAALgADCgYJDAAAAA==.Hotpocket:BAAALgAECgIJAgAAAA==.',
Hy='Hyara:BAABLgAECn8rAAINAAkJghziDwC8AgANAAkJghziDwC8AgAAAA==.',
['Hì']='Hìm:BAAALgAECgMJBAAAAA==.',
['Hù']='Hùñtarð:BAAALgADCggJFwAAAA==.',
Ib='Ibefarmin:BAAALgAECgEJAQAAAA==.',
Ic='Icecreammen:BAAALgADCgQJBAAAAA==.Iceshadow:BAACLgAFFH8NAAITAAQJ/RRYIACnAAATAAQJ/RRYIACnAAAuAAQKfxYAAxMABwnjHq0VAG0CABMABwnjHq0VAG0CACMAAgkrAqLDAA8AAAAA.Icobal:BAAALgADCgYJCAAAAA==.',
Il='Illisa:BAAALgADCgMJAwAAAA==.',
In='Inubis:BAAALgAECgIJAgAAAA==.',
Ir='Irongallo:BAAALgADCgEJAQAAAA==.',
Ix='Ixtlipactzin:BAAALgAECgIJAgAAAA==.',
Ja='Jabdis:BAAALgADCgEJAQAAAA==.Jabzulsor:BAAALgAECgEJAQAAAA==.Jacopo:BAABLgAECn8XAAIZAAgJtw43hABbAQAZAAgJtw43hABbAQAAAA==.',
Je='Jeffster:BAAALgAFFAIJBAAAAA==.',
Jo='Jocko:BAAALgAECgMJAwAAAA==.Jordi:BAABLgAECn89AAINAAkJ2B51GQCNAgANAAkJ2B51GQCNAgAAAA==.',
Ju='Jutti:BAAALgAECgQJDAAAAA==.',
Ka='Kaellen:BAAALgADCgUJBQAAAA==.Kahnman:BAAALgADCgUJBQAAAA==.Kaka:BAAALgAECgcJEwAAAA==.Kalet:BAAALgAECgMJAwAAAA==.Kaluaruun:BAAALgAECgEJAQAAAA==.Kandinsky:BAAALgADCgIJAgAAAA==.Kanree:BAACLgAFFH8vAAMTAAcJrQrKHQCCAQATAAcJrQrKHQCCAQAjAAEJ5gYIRgA0AAAuAAQKfz4AAxMACQkiG0oLAJwCABMACQkiG0oLAJwCACMAAQknB7KpACgAAAAA.Kartiri:BAACLgAFFH8hAAMkAAgJEBh8DQDHAQAkAAYJ0Bd8DQDHAQAHAAgJPhWuCADHAQAuAAQKfy8ABCQACQmRHVoGAN4CACQACQmRHVoGAN4CAAcABQnWFm80AGEBAAgABQkPGM0lAPUAAAAA.Katigirl:BAAALgAECgQJBAAAAA==.Kawhi:BAAALgAFFAEJAQAAAA==.',
Ke='Kea:BAACLgAFFH8jAAMYAAYJViAgCQDFAQAYAAUJ5iMgCQDFAQAbAAMJrBYdEgCAAAAuAAQKfzwAAxgACQkNJr0AAOEDABgACQkNJr0AAOEDABsAAwlTI2A1AC4BAAAA.Keedoril:BAAALgADCgUJCgAAAA==.Keicelinis:BAABLgAECn8WAAIGAAYJ9xLIfgAiAQAGAAYJ9xLIfgAiAQAAAA==.Keratos:BAAALgAECgYJCQAAAA==.',
Kh='Khaalid:BAAALgAECgYJCgAAAA==.Khran:BAAALgADCgIJAgAAAA==.',
Ki='Kickingfluff:BAAALgADCgIJAgAAAA==.Kimjoonsang:BAAALgAECgEJAQABLgAECgEJAQAKAAAAAA==.Kipz:BAAALgAECgUJBQAAAA==.Kittyboy:BAAALgADCgUJBQAAAA==.',
Ko='Kookykrook:BAABLgAFFH8IAAIHAAQJrQ8yNADyAAAHAAQJrQ8yNADyAAAAAA==.Korxin:BAACLgAFFH8gAAINAAgJuRSKEQDXAQANAAgJuRSKEQDXAQAuAAQKfysAAg0ACQkpI+oEAD8DAA0ACQkpI+oEAD8DAAAA.Kozmikfrost:BAAALgADCgEJAQAAAA==.',
Kr='Kreizikat:BAACLgAFFH8PAAIcAAUJDxPFIQBKAQAcAAUJDxPFIQBKAQAuAAQKfzIAAhwACAnJITQOAMgCABwACAnJITQOAMgCAAEuAAUUBgkJABMAjxIA.Krinn:BAAALgAECgYJCQAAAA==.Krios:BAAALgADCgQJBAAAAA==.',
Ku='Kurquaan:BAABLgAECn8aAAMeAAkJgxMJGACRAQAeAAkJgxMJGACRAQAVAAQJEwyWVgDKAAAAAA==.',
La='Lanstan:BAAALgAECgQJBAAAAA==.',
Le='Leilar:BAAALgAECgIJAwAAAA==.Leron:BAAALgAECgYJCAAAAA==.Levitticus:BAACLgAFFH8GAAIXAAMJ2R1+IwAEAQAXAAMJ2R1+IwAEAQAuAAQKfzkAAhcACQlCH0sGACgDABcACQlCH0sGACgDAAEuAAUUCAkWABMA+BoA.',
Li='Liale:BAAALgAFFAEJAQAAAA==.Lideyn:BAAALgAECgIJAgAAAA==.Lidrel:BAAALgAECgYJBgAAAA==.Lightbreath:BAAALgAECgEJAQAAAA==.Lightfury:BAAALgAECgQJBwABLgAECgYJCAAKAAAAAA==.Limone:BAAALgADCgUJBQAAAA==.',
Lo='Loinari:BAABLgAECn8hAAIVAAcJHAoQDAC4AAAVAAcJHAoQDAC4AAAAAA==.Lokano:BAAALgAECgUJBwAAAA==.',
Lu='Luaru:BAAALgAECgEJAQAAAA==.Ludmylha:BAAALgAFFAEJAQAAAA==.Luisda:BAAALgADCgUJBQAAAA==.Lulak:BAAALgAECgQJCQAAAA==.Lull:BAABLgAECn8tAAMaAAkJ6A5ICwCMAQAaAAkJ6A5ICwCMAQAJAAEJ4QLaYwEdAAAAAA==.Lushil:BAAALgAFFAMJAwAAAA==.Luthin:BAAALgADCgUJBgAAAA==.',
Ly='Lyadre:BAAALgAECgIJAgAAAA==.Lynai:BAAALgADCgIJAgAAAA==.Lyndis:BAAALgAECgQJBAAAAA==.',
Ma='Madness:BAAALgAECgMJAwAAAA==.Magejaf:BAAALgADCgcJDQABLgAECggJIAAPALIYAA==.Magidragon:BAABLgAECn8eAAIBAAkJcA9SCgCLAQABAAkJcA9SCgCLAQAAAA==.Mandrah:BAAALgADCgQJBQAAAA==.Maybell:BAAALgAECgQJCgAAAA==.',
Md='Mdavis:BAAALgAECgcJBwAAAA==.',
Me='Melt:BAACLgAFFH8uAAMJAAgJJBmQFwAEAgAJAAcJQhmQFwAEAgAaAAEJchgiHABbAAAuAAQKfz4AAwkACQl+I/8JAAEDAAkACQl+I/8JAAEDABoABAmoEncsAAwBAAAA.Mepha:BAABLgAFFH8KAAIZAAQJYwxbRADIAAAZAAQJYwxbRADIAAAAAA==.Metons:BAAALgAECggJDQAAAA==.Metroboofin:BAAALgAECgMJAQAAAA==.',
Mi='Midei:BAAALgADCgkJFgAAAA==.Midriffluvr:BAAALgAECgQJBwAAAA==.Mikasa:BAAALgADCgEJAQAAAA==.Mike:BAACLgAFFH8GAAIaAAQJ0grEAwDxAAAaAAQJ0grEAwDxAAAuAAQKfxUAAxoABwkGIAgBAPYBABoABgkFIggBAPYBAA8ABAlICgAHAKQAAAEuAAQKBwkYAA0AbB8A.Mimosa:BAAALgADCgYJCgABLgAECgYJCAAKAAAAAA==.Mirna:BAAALgAECgMJBgAAAA==.Misfitdh:BAAALgAECgEJAQAAAA==.Misfitdk:BAAALgAECgEJBAAAAA==.Misfitdots:BAAALgAECgEJAQAAAA==.Misfitmagi:BAAALgAECgEJBAAAAA==.Misfitmonk:BAAALgAECgEJAgAAAA==.Misfittotem:BAAALgAECgEJAwAAAA==.Misfitx:BAAALgAECgEJAQAAAA==.Missfire:BAAALgAECgkJCQAAAA==.Missðirect:BAAALgAECgEJAQABLgAFFAIJAwAKAAAAAA==.Mistfox:BAAALgAECggJEgAAAA==.',
Mo='Mobiouse:BAAALgADCgYJBgAAAA==.Mollieann:BAAALgAECgQJBgAAAA==.Mommon:BAAALgAECgYJCAAAAA==.Moonraisin:BAAALgAECgMJBQAAAA==.Morrighan:BAAALgADCgQJBQAAAA==.',
Mu='Mukdron:BAAALgADCgIJAgAAAA==.',
['Mâ']='Mâlus:BAAALgAECgYJEwAAAA==.',
Na='Nadra:BAAALgAFFAIJAgAAAA==.Naminé:BAAALgADCgMJAwABLgAFFAQJCAAlAH0WAA==.Nattyrav:BAACLgAFFH8XAAImAAUJ/ByHAgBeAQAmAAUJ/ByHAgBeAQAuAAQKfygAAyYACQkbH8ADAO4CACYACQlnHsADAO4CABEABgnHG/03AFgBAAAA.Nawari:BAAALgAECgIJAwAAAA==.',
Ne='Nemonk:BAACLgAFFH8OAAIjAAMJpx29CAD7AAAjAAMJpx29CAD7AAAuAAQKf1oAAyMACQkeH0AGAOgCACMACQkeH0AGAOgCABMAAQlQA1bWABwAAAAA.Neryssa:BAACLgAFFH8bAAQJAAgJhhvODgBFAgAJAAgJtRrODgBFAgAaAAEJYRVKHgBXAAAPAAEJpRwyHABVAAAuAAQKfzoAAwkACQnYJOkIAAwDAAkACAlvJOkIAAwDABoABAkpJPUYAIMBAAAA.',
Ni='Nickjamez:BAAALgADCgYJBgAAAA==.Nimh:BAAALgADCgUJCgAAAA==.Nipz:BAAALgAECgEJAQABLgAECgUJBQAKAAAAAA==.',
No='Nocter:BAABLgAECn8hAAQJAAkJPx1nNwAuAgAJAAcJ9RxnNwAuAgAPAAUJUiCTCwCBAQAaAAMJ9g0APgC8AAAAAA==.Noqtir:BAAALgAECgUJCgAAAA==.Not:BAAALgADCgcJAgAAAA==.Noyoo:BAAALgADCgEJAQAAAA==.',
Nu='Nunca:BAAALgAECgEJAQAAAA==.',
Ny='Nymura:BAABLgAECn8kAAICAAgJQgrTpwArAQACAAgJQgrTpwArAQAAAA==.',
['Nä']='Näesthra:BAABLgAECn8kAAIbAAgJdBhpHADjAQAbAAgJdBhpHADjAQAAAA==.',
Oa='Oakhugger:BAACLgAFFH8GAAIUAAIJ+QeaCgBpAAAUAAIJ+QeaCgBpAAAuAAQKfyQAAxQACQlYEN0PALkBABQACQlYEN0PALkBABUAAQkAAE2xAAAAAAAA.',
Ob='Obelisk:BAAALgADCgYJBgAAAA==.Obelix:BAAALgAECgEJAQAAAA==.',
Ok='Okarun:BAABLgAECn8jAAIGAAcJTB5nQQDuAQAGAAcJTB5nQQDuAQABLgAFFAQJCAAlAH0WAA==.',
Ol='Oldeone:BAAALgAECgMJBAAAAA==.Olillivia:BAAALgADCgIJAQAAAA==.Olyvivia:BAABLgAFFH8GAAInAAIJuwJ6EwBlAAAnAAIJuwJ6EwBlAAAAAA==.',
Om='Omgega:BAABLgAECn9EAAICAAgJWhuTNwAjAgACAAgJWhuTNwAjAgAAAA==.',
On='Onichan:BAAALgAECgYJCQABLgAFFAkJHwARAKEZAA==.Onimeek:BAABLgAECn9aAAMMAAkJEyBqBwC7AgAMAAkJEyBqBwC7AgAGAAIJPAleDgE7AAAAAA==.',
Or='Oragar:BAAALgAECgQJBAAAAA==.Oryn:BAAALgAFFAEJAwABLgAFFAIJBgABACcVAA==.Oryx:BAAALgAECgEJAwAAAA==.',
Pa='Pallywahwah:BAAALgAFFAEJAQAAAA==.Palpitations:BAAALgAECgcJEAAAAA==.Paper:BAAALgAFFAgJKAAAAQ==.Paudetunia:BAAALgADCgIJAgAAAA==.',
Pe='Peacefullev:BAACLgAFFH8WAAMTAAgJ+BpdCwBRAgATAAgJ+BpdCwBRAgAjAAEJKQuFRAA2AAAuAAQKfyYAAxMACAn8Hq4OALUCABMACAn8Hq4OALUCACMABwnDFY4mAIEBAAAA.Peiko:BAAALgADCgIJAgAAAA==.Pelagius:BAAALgADCgYJBwAAAA==.Penance:BAAALgAECgEJAQAAAA==.Pestilence:BAAALgAECggJDQAAAA==.Pewpewpew:BAAALgAECgYJBgAAAA==.',
Ph='Phantomthief:BAAALgAECggJAwAAAA==.Phyllus:BAAALgAFFAIJAwAAAA==.',
Pi='Pictureplane:BAAALgADCgEJAQAAAA==.Pipeleto:BAACLgAFFH8RAAILAAMJZhkBEwDtAAALAAMJZhkBEwDtAAAuAAQKfx0AAgsACQmJGPUeAPcBAAsACQmJGPUeAPcBAAAA.',
Po='Poochimus:BAABLgAECn8hAAImAAkJsROxCgAOAgAmAAkJsROxCgAOAgAAAA==.Pookong:BAAALgAECgUJCQAAAA==.Poonslayerxx:BAAALgADCgMJAwAAAA==.',
Pr='Previdius:BAAALgAECggJEQAAAA==.Priestpwnz:BAAALgAECgYJDwAAAA==.Protomán:BAABLgAECn8YAAIJAAkJGRYyBwB0AQAJAAkJGRYyBwB0AQAAAA==.Proximity:BAAALgADCgQJBQABLgADCgcJCwAKAAAAAA==.',
Ps='Psychmike:BAAALgAECgEJAQAAAA==.',
Pw='Pwrbttm:BAAALgAECgEJAQABLgAFFAUJEgANACMLAA==.',
['Pé']='Pépega:BAAALgAECgIJAgAAAA==.',
Ra='Rafferno:BAAALgAECgEJAgAAAA==.',
Re='Redeemedlev:BAACLgAFFH8kAAIYAAYJrRRhCwCEAQAYAAYJrRRhCwCEAQAuAAQKf0IAAhgACQnkISYEAFcDABgACQnkISYEAFcDAAEuAAUUCAkWABMA+BoA.Reds:BAAALgAECgEJAQAAAA==.Relax:BAABLgAECn8YAAIGAAYJOh5ZUQCRAQAGAAYJOh5ZUQCRAQAAAA==.',
Rh='Rhesand:BAABLgAECn8ZAAMHAAgJPAS8VgDXAAAHAAgJPAS8VgDXAAAIAAEJjwGoLQAEAAAAAA==.Rhëa:BAAALgAECgMJBAAAAA==.',
Ri='Riellus:BAAALgADCgkJFQAAAA==.Riiu:BAABLgAECn8cAAIjAAYJHR0wJwB9AQAjAAYJHR0wJwB9AQABLgAFFAMJCgACADMbAA==.Rindra:BAAALgAECgUJCAAAAA==.Rinkelle:BAAALgAECgYJBgAAAA==.Riven:BAABLgAECn8UAAQBAAYJjhzxngA9AQABAAYJDxrxngA9AQAdAAMJXxMwDwBrAAAfAAEJlB8yBgBcAAAAAA==.Rixin:BAECLgAFFH8hAAMZAAgJhBxBEQBTAgAZAAgJhBxBEQBTAgAoAAEJAAC9LQAAAAAuAAQKfzwAAhkACQk3JgYGAEkDABkACQk3JgYGAEkDAAAA.Rixryu:BAEALgADCgkJFgABLgAFFAgJIQAZAIQcAA==.',
Ro='Roaka:BAAALgADCggJCAAAAA==.Rokom:BAACLgAFFH8LAAILAAMJ1xh/NADfAAALAAMJ1xh/NADfAAAuAAQKfyQAAgsACAneH28TALICAAsACAneH28TALICAAAA.Rollster:BAAALgAECgQJBAAAAA==.Rotandroll:BAAALgADCgYJBgABLgAECgEJAQAKAAAAAA==.',
Ru='Runed:BAAALgAECgEJAgAAAA==.Ruwey:BAAALgAECgEJAQAAAA==.',
Ry='Ryuk:BAAALgAECgYJEQAAAA==.',
['Rè']='Rèzurrect:BAAALgAECgUJDgAAAA==.',
Sa='Saaratharaxx:BAAALgAECgUJDAAAAA==.Sackhunter:BAABLgAECn8aAAIGAAcJEg6ViwAJAQAGAAcJEg6ViwAJAQAAAA==.Saero:BAABLgAECn8UAAIXAAcJbBmUKgC7AQAXAAcJbBmUKgC7AQAAAA==.Sake:BAAALgAECgUJBQABLgAFFAUJGgAjAHEUAA==.Salla:BAAALgAECgUJBQAAAA==.Saluuknir:BAACLgAFFH8FAAIHAAIJ7QcLVwBwAAAHAAIJ7QcLVwBwAAAuAAQKfzEAAwcACQmBD/smAKoBAAcACQlBD/smAKoBAAgABgloB4ojAAwBAAAA.Saphh:BAABLgAECn8gAAQoAAcJkBzYBgDrAAAZAAcJbBvMZgDBAQAnAAUJ/xnlEwA/AQAoAAQJAxvYBgDrAAABLgAFFAcJHgAnAGoXAA==.Satrath:BAABLgAFFH8FAAIBAAIJdgkSqgCAAAABAAIJdgkSqgCAAAABLgAFFAUJCAAiAD4iAA==.',
Se='Sedalin:BAAALgAECgEJAQAAAA==.Seekae:BAAALgAECgEJAQAAAA==.Sepidasprite:BAAALgADCgEJAQAAAA==.Setoplek:BAAALgAECgEJAQAAAA==.',
Sh='Shaddoot:BAAALgAFFAIJBAAAAA==.Shadowangel:BAAALgAFFAEJAQAAAA==.Shadowbladez:BAAALgAECgEJAQAAAA==.Shadowxd:BAABLgAFFH8LAAMcAAMJFxBaRgCcAAAcAAMJFxBaRgCcAAAeAAEJGwgAAAAAAAAAAA==.Sharky:BAAALgAFFAIJAwABLgAFFAkJLgAfACUdAA==.Shaulana:BAAALgADCgYJBgAAAA==.Sheepforfree:BAAALgAECgIJAgAAAA==.Shenwu:BAAALgAFFAIJAwAAAA==.Shinishamy:BAAALgADCgEJAQAAAA==.Shirokuma:BAABLgAFFH8gAAIeAAgJ/h5aAwDxAQAeAAgJ/h5aAwDxAQABLgAFFAYJBgAFANUNAA==.Shorty:BAAALgADCgYJEAAAAA==.',
Si='Siera:BAAALgAECgQJBQABLgAECggJDQAKAAAAAA==.Sigrun:BAAALgADCgIJAgAAAA==.Sipz:BAAALgAECgIJAgABLgAECgUJBQAKAAAAAA==.',
Sk='Skinbone:BAAALgADCgQJBAAAAA==.Skyrius:BAABLgAFFH8GAAIZAAIJ2wk7+AB1AAAZAAIJ2wk7+AB1AAAAAA==.',
Sl='Slaty:BAAALgAECgIJAgAAAA==.Slingshotz:BAABLgAECn8ZAAIhAAkJ4RmrBgCWAgAhAAkJ4RmrBgCWAgAAAA==.Slootbag:BAAALgAECgkJDwAAAA==.',
Sn='Snax:BAAALgAECgIJAgAAAA==.Sneakylev:BAACLgAFFH8JAAIiAAQJtxBtDAAnAQAiAAQJtxBtDAAnAQAuAAQKfxkAAiIACAlxG9YTAAUCACIACAlxG9YTAAUCAAEuAAUUCAkWABMA+BoA.Sneux:BAAALgADCgcJDQAAAA==.Snuuze:BAACLgAFFH8PAAICAAMJJiEzTgASAQACAAMJJiEzTgASAQAuAAQKfyoAAgIACAkWI3AlAJECAAIACAkWI3AlAJECAAEuAAUUBgkLAAwAgRYA.Snuuzi:BAAALgAFFAEJAQABLgAFFAYJCwAMAIEWAA==.',
So='Soberloki:BAAALgAECgIJAgAAAA==.Sola:BAAALgAECgEJAQAAAA==.Solari:BAABLgAECn8cAAMGAAkJjRrtJQA2AgAGAAkJ1BftJQA2AgAMAAcJlhUVHwDGAQAAAA==.Sole:BAAALgAECgMJAwAAAA==.Solix:BAAALgAECgEJAQAAAA==.Solpra:BAAALgAECgEJAQAAAA==.Solune:BAAALgAECgIJAwAAAA==.Solvi:BAAALgAECgYJDgAAAA==.Sophispapa:BAABLgAECn9CAAICAAcJ5SChPAASAgACAAcJ5SChPAASAgAAAA==.Souprage:BAABLgAECn8UAAILAAgJvhApMwB+AQALAAgJvhApMwB+AQAAAA==.',
Sp='Spellmaden:BAAALgADCgMJBgABLgAFFAQJCAAlAH0WAA==.Spywar:BAAALgAECgYJCAABLgAECggJHwARACkXAA==.',
St='Starlighter:BAABLgAECn8qAAMWAAkJiAvhKwB2AQAWAAkJiAvhKwB2AQAbAAYJGQXVSwC0AAABLgAFFAIJAgAKAAAAAA==.Starsomave:BAAALgAFFAIJAgAAAA==.Steen:BAAALgAECgQJBwAAAA==.Stinkylev:BAACLgAFFH8KAAInAAUJTA2rBwALAQAnAAUJTA2rBwALAQAuAAQKfxwAAicACQkcH50AAO0CACcACQkcH50AAO0CAAEuAAUUCAkWABMA+BoA.Strentor:BAAALgAECgQJBQAAAA==.',
Su='Sunshinë:BAAALgAECgEJAgAAAA==.Supressor:BAAALgADCgQJCAABLgAECgIJAgAKAAAAAA==.',
Sy='Sylvester:BAAALgADCgIJAgAAAA==.',
['Sé']='Sérolis:BAAALgADCgEJAQAAAA==.',
Ta='Taehausx:BAACLgAFFH9bAAIOAAkJ9yYBAACrAwAOAAkJ9yYBAACrAwAuAAQKfzAAAw4ACQlSJB8GACUDAA4ACQlSJB8GACUDACMAAgk5HjZdAKIAAAAA.Tarmo:BAAALgADCgYJFgAAAA==.',
Te='Telesto:BAAALgAECgIJAgABLgAFFAgJIAACAJEdAA==.Templeton:BAAALgADCgMJAwAAAA==.Tenath:BAABLgAECn8bAAIMAAcJsRK5KAA3AQAMAAcJsRK5KAA3AQAAAA==.',
Th='Thaleon:BAAALgAECgcJDgAAAA==.Tharella:BAAALgAECgYJCwAAAA==.Tharion:BAAALgAFFAIJAgAAAA==.Thauriel:BAAALgAECgYJCAAAAA==.Thrumple:BAAALgADCgYJCgAAAA==.',
Ti='Tipz:BAAALgAECgIJAwABLgAECgUJBQAKAAAAAA==.Titania:BAABLgAECn8eAAIXAAkJTAa9QAB1AQAXAAkJTAa9QAB1AQAAAA==.',
Tr='Trollztoll:BAAALgAECgIJAgAAAA==.',
Tu='Tuulk:BAAALgADCgIJAgAAAA==.',
Ty='Typical:BAAALgADCgcJCwAAAA==.',
Ug='Uggoorc:BAACLgAFFH8SAAINAAUJIwvGTQAQAQANAAUJIwvGTQAQAQAuAAQKfywAAg0ACQlSHroFABYCAA0ACQlSHroFABYCAAAA.Uggotroll:BAAALgAECgUJCwABLgAFFAUJEgANACMLAA==.Ugrin:BAAALgAECgEJAQAAAA==.',
Un='Unholylord:BAAALgAECggJDAABLgAFFAgJIQAWAGkgAA==.',
Ut='Uthok:BAAALgADCgcJBwAAAA==.',
Va='Vacalocà:BAABLgAECn8UAAIUAAgJUQ1iGQBEAQAUAAgJUQ1iGQBEAQAAAA==.Valerian:BAAALgAECggJDgAAAA==.Validori:BAAALgADCgEJAQAAAA==.Van:BAABLgAECn8aAAMJAAkJAgi4CgApAQAJAAkJAgi4CgApAQAaAAEJjgNVEQAVAAAAAA==.Vaultkey:BAAALgADCgIJAwAAAA==.',
Ve='Vegesha:BAAALgAECgEJAgAAAA==.Veinke:BAABLgAECn8VAAIFAAkJ+w5gCwClAQAFAAkJ+w5gCwClAQAAAA==.Vengefullev:BAAALgAECgQJDAABLgAFFAgJFgATAPgaAA==.Venin:BAAALgAECgYJCwAAAA==.Vessarind:BAAALgADCgEJAgAAAA==.',
Vi='Vitora:BAAALgAECgYJEQAAAA==.',
Vo='Voidkurn:BAAALgADCgYJCQAAAA==.Von:BAAALgADCgIJAgAAAA==.',
Vy='Vyse:BAAALgADCgYJBgAAAA==.',
Wa='Waally:BAAALgAECgcJEgAAAA==.Wahgwan:BAAALgAECgMJAwAAAA==.Waleran:BAAALgADCgIJAgAAAA==.Warrdaddy:BAAALgAECgYJEgABLgADCgcJBwAKAAAAAA==.Warriorbp:BAAALgADCgkJFwAAAA==.Wattz:BAAALgAECgYJBgAAAA==.',
We='Weebsora:BAACLgAFFH8GAAIGAAUJwg/EIAD3AAAGAAUJwg/EIAD3AAAuAAQKfxQAAgYACAntHAwNAAgBAAYACAntHAwNAAgBAAAA.Weeple:BAAALgADCgkJCQAAAA==.',
Wo='Worldtree:BAABLgAECn8XAAIQAAcJHRCMZQArAQAQAAcJHRCMZQArAQAAAA==.',
Wy='Wynne:BAAALgAECggJCwAAAA==.',
Xa='Xaelthira:BAAALgAECgYJCgAAAA==.',
Xe='Xerath:BAAALgADCgYJCAAAAA==.',
Xi='Xips:BAAALgADCgMJAwABLgAECgUJBQAKAAAAAA==.',
Xo='Xoru:BAAALgADCgYJBgAAAA==.Xoruk:BAAALgADCgQJBAABLgAFFAIJAgAKAAAAAA==.Xorun:BAAALgAECgEJAQABLgAFFAIJAgAKAAAAAA==.',
Xz='Xzarrion:BAAALgAECgEJAQAAAA==.',
Ya='Yadhi:BAABLgAECn8XAAQOAAYJihbpMgA1AQAOAAUJihbpMgA1AQATAAYJoBCgUAAsAQAjAAUJ3AdDaACFAAAAAA==.',
Ye='Yetkin:BAAALgAECgYJDQAAAA==.',
Yi='Yifftron:BAAALgAECgYJBgABLgAECggJGwANAAogAA==.Yimomo:BAABLgAECn8cAAMbAAkJhRUbLgCMAQAbAAkJhRUbLgCMAQAWAAcJtwcMTgDYAAAAAA==.',
Yo='Yoshira:BAAALgAECgMJAwABLgAECggJDQAKAAAAAA==.',
Yv='Yveltal:BAAALgAECggJCQAAAA==.',
Yz='Yzra:BAAALgAECgQJBgAAAA==.',
Za='Zahndrekh:BAAALgADCgUJBQAAAA==.Zalconn:BAACLgAFFH8cAAMiAAUJVyY4DgCwAQAiAAUJVyY4DgCwAQAlAAIJDRdxDACZAAAuAAQKfysAAyIACQkcJjoDAGwDACIACQnZJToDAGwDACUAAQneJoEbAHEAAAAA.Zarrona:BAACLgAFFH8IAAIlAAQJfRYtAgAaAQAlAAQJfRYtAgAaAQAuAAQKfyYAAyUACAkRHxkFAB4CACUABwm2HRkFAB4CACIABwmRGlEfAJsBAAAA.Zayah:BAABLgAECn8aAAIRAAgJLxaMKQCkAQARAAgJLxaMKQCkAQAAAA==.',
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
