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

local lookup = {'Paladin-Retribution','Monk-Brewmaster','Druid-Restoration','Druid-Feral','DemonHunter-Devourer','Warlock-Demonology','Warlock-Affliction','Priest-Holy','Warlock-Destruction','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Druid-Guardian','Rogue-Assassination','Priest-Shadow','Priest-Discipline','Paladin-Protection','Unknown-Unknown','Paladin-Holy','Hunter-BeastMastery','Shaman-Enhancement','Mage-Frost','Hunter-Marksmanship','Monk-Mistweaver','Hunter-Survival','Monk-Windwalker','Druid-Balance','Mage-Arcane','DemonHunter-Vengeance','Shaman-Restoration','DeathKnight-Blood','DemonHunter-Havoc','Shaman-Elemental','DeathKnight-Frost','Warrior-Arms','Warrior-Fury','Warrior-Protection','Rogue-Subtlety','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm='Blackhand',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abadacalama:BAABLgAECn8VAAIBAAcJERXObQBzAQABAAcJERXObQBzAQAAAA==.Abanddon:BAAALgAECgQJBAABLgAECggJIAACAFgSAA==.',
Ad='Adera:BAAALgADCgEJAQAAAA==.',
Ae='Aellee:BAAALgAECgQJCQAAAA==.Aeninas:BAABLgAECn8eAAICAAgJqhcOGADIAQACAAgJqhcOGADIAQAAAA==.Aeris:BAAALgADCgEJAQAAAA==.Aerynn:BAAALgADCgIJAgAAAA==.Aethwyn:BAAALgAECgcJDAAAAA==.',
Af='Afflictions:BAAALgADCgUJBQAAAA==.',
Ag='Agandaur:BAAALgAECgMJAwAAAA==.',
Ah='Ahnkala:BAAALgAECgUJCwAAAA==.Ahzi:BAABLgAECn8uAAMDAAkJrB0UFwBsAgADAAgJ0hwUFwBsAgAEAAUJkhfwEAByAQAAAA==.Ahzii:BAAALgADCgYJBwAAAA==.',
Ai='Aigirlfriend:BAABLgAECn8pAAIFAAkJPgq1UgBrAQAFAAkJPgq1UgBrAQAAAA==.Ains:BAABLgAECn8cAAMGAAkJiwcUXwBtAQAGAAkJQQcUXwBtAQAHAAMJXwa3HQCOAAAAAA==.Airsia:BAAALgADCggJDAAAAA==.',
Ak='Akro:BAAALgAECgEJAwABLgAECgcJGgABAJkkAA==.',
Al='Alarrah:BAAALgAECgQJBAAAAA==.Allupcreepy:BAABLgAECn8dAAIIAAgJ8CF3CAC/AgAIAAgJ8CF3CAC/AgAAAA==.Alphaandy:BAAALgAECgMJAwAAAA==.Alphaboy:BAAALgADCgcJBwAAAA==.Alphaxdruid:BAAALgAECgMJAwAAAA==.Alphaxsham:BAAALgAECgEJAQAAAA==.Alysara:BAAALgAECgMJAwAAAA==.',
Am='Ambewlance:BAABLgAECn8YAAMGAAgJSg9KXgBvAQAGAAgJKg9KXgBvAQAJAAMJRA51QQCvAAAAAA==.Ambrosious:BAAALgAECgEJAQAAAA==.Amethystra:BAABLgAECn8pAAMKAAkJfA2xJQCQAQAKAAkJfA2xJQCQAQALAAMJwwaXMgCBAAAAAA==.Amâlynd:BAABLgAECn8hAAIDAAkJdAjCSQBFAQADAAkJdAjCSQBFAQAAAA==.',
An='Anastasiaro:BAAALgADCgEJAQAAAA==.Anien:BAAALgADCgcJCAAAAA==.Annimosity:BAAALgAECgIJAwAAAA==.Ansem:BAAALgADCgUJBgAAAA==.Anthesis:BAACLgAFFH8MAAIDAAQJhxJZJwD/AAADAAQJhxJZJwD/AAAuAAQKfyMAAgMACAkQGsAaAEwCAAMACAkQGsAaAEwCAAAA.Anthonor:BAAALgAECgYJCAAAAA==.Anubrian:BAABLgAECn8fAAIMAAgJqgb1ggA4AQAMAAgJqgb1ggA4AQAAAA==.Anúbis:BAAALgAECgUJCgAAAA==.',
Ap='Apawllo:BAABLgAECn8vAAINAAkJMBRHEQCbAQANAAkJMBRHEQCbAQAAAA==.Apep:BAABLgAECn8aAAIOAAYJFiI2BgDnAQAOAAYJFiI2BgDnAQAAAA==.Apostle:BAACLgAFFH8hAAIIAAcJSxwuAgAkAgAIAAcJSxwuAgAkAgAuAAQKfzUAAwgACQm5I9kCAFIDAAgACQm5I9kCAFIDAA8AAgn7EdhUAIYAAAAA.',
Ar='Aramìs:BAAALgADCgYJBgAAAA==.Arlida:BAAALgADCgYJBgABLgAECgkJLgADAAIRAA==.Aryto:BAABLgAECn8uAAMPAAgJnCD4EAArAgAPAAgJnCD4EAArAgAQAAEJIBiTWwBHAAAAAA==.',
As='Ashlar:BAAALgADCgYJDAAAAA==.Asketill:BAACLgAFFH8JAAIBAAQJRAnfPAAPAQABAAQJRAnfPAAPAQAuAAQKfyYAAgEACAl/FXpMAMMBAAEACAl/FXpMAMMBAAAA.Astora:BAAALgADCggJCgABLgAECggJIAACAFkeAA==.',
Au='Auluras:BAAALgADCgUJBQAAAA==.Auren:BAAALgADCgMJBAAAAA==.',
Av='Avitus:BAAALgADCgIJBAAAAA==.',
Ay='Aylari:BAABLgAECn8vAAMBAAkJoSS7BgAiAwABAAkJjyS7BgAiAwARAAYJ+ReaEgCgAQAAAA==.',
Az='Azkadellia:BAAALgAECgMJAwAAAA==.Azonya:BAAALgADCgEJAgAAAA==.Azuth:BAAALgADCgMJAwAAAA==.',
Ba='Baaloo:BAAALgAECgEJAQABLgAECgUJDwASAAAAAA==.Bachren:BAAALgAECgYJCgAAAA==.Badil:BAAALgADCgIJAgAAAA==.Baitken:BAABLgAECn8cAAITAAgJvh0VEQBpAgATAAgJvh0VEQBpAgABLgAECggJHgACAKoXAA==.Batharel:BAABLgAECn8mAAIUAAgJARc5NwDWAQAUAAgJARc5NwDWAQAAAA==.',
Bd='Bdrone:BAAALgADCgYJCAAAAA==.',
Be='Bearen:BAABLgAECn8lAAIVAAgJQQq9EQBaAQAVAAgJQQq9EQBaAQAAAA==.Beckett:BAAALgAECggJCAABLgAECggJKwATACAgAA==.Bedazzle:BAAALgADCgcJBwABLgAFFAcJIQAIAEscAQ==.Beefo:BAAALgADCgUJBAAAAA==.Beemz:BAAALgAECgcJEwAAAA==.Beertrain:BAABLgAECn8tAAIMAAkJAhfoJgBEAgAMAAkJAhfoJgBEAgAAAA==.Beesechurger:BAABLgAECn8kAAIWAAkJoh3zIQB6AgAWAAkJoh3zIQB6AgAAAA==.Bekindrewind:BAABLgAECn8YAAIKAAgJwRaGIAC8AQAKAAgJwRaGIAC8AQAAAA==.Belladonia:BAAALgADCgcJBwABLgAECgkJNgADALIWAA==.Belladue:BAAALgADCgcJDgAAAA==.Bellezza:BAABLgAECn82AAIDAAkJshYyHQA4AgADAAkJshYyHQA4AgAAAA==.Bex:BAAALgADCgEJAQAAAA==.',
Bh='Bheef:BAAALgADCgMJAwAAAA==.',
Bi='Bigdisc:BAAALgADCgIJAgABLgAECgMJAwASAAAAAA==.Bigdumbcatqt:BAABLgAECn8pAAIRAAkJ6CYlAACDAwARAAkJ6CYlAACDAwAAAA==.Bignjuicy:BAAALgAECgcJDAAAAA==.',
Bl='Blarpsniff:BAAALgADCgUJBgAAAA==.Blinkk:BAAALgADCgEJAgABLgADCgMJAwASAAAAAA==.Bloodeagle:BAAALgADCgcJBwAAAA==.Bloodshhot:BAABLgAECn8zAAMUAAkJfBUGLwD3AQAUAAgJFRgGLwD3AQAXAAEJVANzjgAsAAAAAA==.Bloodthorne:BAAALgADCgUJCQAAAA==.Bloomtoob:BAAALgAECgMJAwABLgAFFAIJBQAFAMwdAA==.Bludgen:BAAALgAECgMJBAABLgAECggJIAAQANEeAA==.Blueragebar:BAAALgADCgkJCQAAAA==.',
Bo='Bobitt:BAABLgAECn8WAAIJAAYJLBrNCgBnAQAJAAYJLBrNCgBnAQAAAA==.Boddyknocker:BAABLgAECn8gAAIJAAkJlhNoBQDqAQAJAAkJlhNoBQDqAQAAAA==.Boinkusan:BAABLgAECn8rAAIYAAkJYSJ0BgANAwAYAAkJYSJ0BgANAwAAAA==.Bolthar:BAABLgAECn8WAAIBAAgJxQ4zlAAqAQABAAgJxQ4zlAAqAQAAAA==.Bonkler:BAABLgAECn8qAAMJAAkJbRlSEgC5AQAGAAkJXRb6LAANAgAJAAcJvxtSEgC5AQAAAA==.Boombox:BAAALgAECgYJDQAAAA==.Boomwand:BAAALgAECgUJCwABLgAECggJKwATACAgAA==.Boonerichard:BAABLgAECn8WAAIBAAYJfAKS+wCPAAABAAYJfAKS+wCPAAAAAA==.Bootysweatz:BAAALgADCgcJCQAAAA==.Bouchewager:BAAALgADCgcJDgAAAA==.Bowata:BAAALgAECgMJAwAAAA==.',
Br='Braina:BAAALgAECggJEQAAAA==.Branwin:BAAALgADCgcJCAAAAA==.Braver:BAACLgAFFH8VAAMZAAcJmREeBACeAQAZAAYJwxQeBACeAQAXAAUJtwmXEQAgAQAuAAQKfzIAAxcACQnmHyIJAA8DABcACQnKHyIJAA8DABkACAmLE1ITAPIBAAAA.Braverwar:BAAALgAECgYJDAABLgAFFAcJFQAZAJkRAA==.Brayedine:BAABLgAECn8WAAIWAAgJhwWlmgApAQAWAAgJhwWlmgApAQAAAA==.Break:BAACLgAFFH8eAAIBAAgJKCVeAAABAwABAAgJKCVeAAABAwAuAAQKfyQAAgEACQlTJjUBAH8DAAEACQlTJjUBAH8DAAEuAAUUCAkeAAEAKCUA.Breekachu:BAAALgADCgYJBgAAAA==.Breo:BAAALgADCgcJBwAAAA==.Brodin:BAAALgAECgEJAQAAAA==.Brohymn:BAAALgADCgEJAQAAAA==.Bromac:BAAALgAECgEJAQAAAA==.Bromaldehyde:BAAALgADCgIJAgAAAA==.Brooké:BAAALgADCgEJAQAAAA==.Broreen:BAAALgAECgEJAgAAAA==.Bruj:BAAALgAECgQJBAAAAA==.',
Bu='Bubblebutt:BAAALgADCgEJAQAAAA==.Bubbledis:BAAALgAECgQJDAABLgAECgcJFgAaAJwPAA==.Bubblekush:BAAALgADCgcJBwAAAA==.Bullfury:BAAALgADCgEJAQAAAA==.',
['Bù']='Bùbbles:BAAALgAECgYJEwAAAA==.',
Ca='Cadelsaya:BAABLgAECn81AAMTAAkJOhM6IQDUAQATAAkJOhM6IQDUAQABAAIJHAIgKwFLAAAAAA==.Caletha:BAABLgAECn8WAAMIAAYJSRsZKQCpAQAIAAYJ5RgZKQCpAQAQAAUJRBemIgB/AQAAAA==.Calimaria:BAAALgAECgEJAgAAAA==.Calixte:BAAALgAECgYJCgAAAA==.Cammandzar:BAAALgAECgcJDAABLgAECgUJBQASAAAAAA==.Canman:BAAALgAECgQJDQAAAA==.Cardeller:BAAALgADCgUJCAAAAA==.Cassei:BAACLgAFFH8PAAITAAUJsxBREgBlAQATAAUJsxBREgBlAQAuAAQKf1AAAxMACAkCIxwNALACABMACAkCIxwNALACAAEABgk0EYGxAPsAAAAA.',
Ce='Celenia:BAABLgAECn8YAAIPAAYJwwxvOQAFAQAPAAYJwwxvOQAFAQAAAA==.Celorious:BAABLgAECn8VAAIUAAcJExitOwDGAQAUAAcJExitOwDGAQAAAA==.',
Ch='Chainari:BAAALgAECgYJDwAAAA==.Chassis:BAAALgAECgQJBAABLgAECggJIAACAFgSAA==.Chawìzawd:BAAALgADCgYJBgAAAA==.Chee:BAAALgAECgEJAgAAAA==.Cheechychong:BAAALgAECgEJAQAAAA==.Cheeksdakota:BAAALgADCgYJBgAAAA==.Cheetopaly:BAABLgAECn8XAAMTAAgJ2xuOSwBKAQATAAYJWRqOSwBKAQABAAcJFAoAzgDRAAAAAA==.Cherrycrush:BAAALgAECgMJAwAAAA==.Chopsuey:BAAALgAECgEJBAAAAA==.Chuga:BAAALgAFFAEJAQAAAA==.Chummy:BAACLgAFFH8HAAIbAAMJrwr6JgDDAAAbAAMJrwr6JgDDAAAuAAQKfx4AAhsACQkjEqMWAO8BABsACQkjEqMWAO8BAAAA.Chìgusa:BAABLgAECn8sAAMIAAkJ1BXFHgDpAQAIAAkJ1BXFHgDpAQAQAAEJmAEdcAAWAAAAAA==.',
Ci='Cigarette:BAABLgAECn8fAAMDAAgJ2w64VwARAQADAAYJkw64VwARAQAbAAQJ6gyFRQDEAAAAAA==.Cilenzer:BAAALgAECgQJBgABLgAECgYJHgAbAGASAA==.Cinadra:BAAALgAECgQJBAAAAA==.Circa:BAAALgADCgUJBwAAAA==.',
Cl='Clumonk:BAABLgAECn8iAAIaAAkJfB1ACQCMAgAaAAkJfB1ACQCMAgAAAA==.',
Co='Convoke:BAACLgAFFH8HAAIDAAIJrBTKQACNAAADAAIJrBTKQACNAAAuAAQKfxQAAgMABwm+JLQMANcCAAMABwm+JLQMANcCAAEuAAUUBwkhAAgASxwA.Coosar:BAAALgAECgYJCAAAAA==.Coose:BAAALgAECgYJBwABLgAFFAEJAQASAAAAAA==.Coosedaplug:BAAALgADCgEJAQABLgAFFAEJAQASAAAAAA==.Coosey:BAAALgAECgcJCgABLgAFFAEJAQASAAAAAA==.Cooseyloosey:BAAALgAECgYJBwABLgAFFAEJAQASAAAAAA==.Coosicle:BAAALgAECgIJAgABLgAFFAEJAQASAAAAAA==.Coredron:BAAALgAECgMJBAAAAA==.Corellon:BAABLgAECn8wAAIBAAkJPBIERADbAQABAAkJPBIERADbAQAAAA==.Corinth:BAABLgAECn8qAAIcAAkJ3BslAgCGAgAcAAkJ3BslAgCGAgAAAA==.',
Cr='Cratoz:BAAALgAECgkJEAAAAA==.Craylic:BAAALgADCgkJDgAAAA==.Creepi:BAABLgAECn8YAAIdAAUJPBQeFADjAAAdAAUJPBQeFADjAAAAAA==.Criah:BAAALgADCggJCQAAAA==.Crixhs:BAAALgADCgUJCgAAAA==.Crossgideon:BAABLgAECn8rAAMdAAkJMhLPCQCdAQAdAAgJhhPPCQCdAQAFAAkJXwprUwBpAQAAAA==.Crosstero:BAAALgADCgYJBgAAAA==.Crossword:BAAALgADCgcJBwAAAA==.Croswind:BAAALgADCgcJDAABLgAECgkJKwAdADISAA==.',
Cu='Curandero:BAAALgADCggJFQABLgAECgQJDQASAAAAAA==.Currah:BAAALgAECgMJBAAAAA==.',
Cy='Cyndrine:BAACLgAFFH8HAAIFAAMJdwJLWwCgAAAFAAMJdwJLWwCgAAAuAAQKfzkAAh0ACQm9JVQAAFwDAB0ACQm9JVQAAFwDAAAA.Cynex:BAAALgAECgcJCQAAAA==.Cyrani:BAAALgADCgcJBwAAAA==.Cyrcyn:BAAALgAECgkJCQAAAA==.',
Da='Dadipps:BAABLgAECn8kAAIeAAgJFiMICQD6AgAeAAgJFiMICQD6AgAAAA==.Daggumit:BAAALgADCgYJDAAAAA==.Dagnei:BAAALgAECgQJBQAAAA==.Daltina:BAAALgAECgYJDAAAAA==.Dannyboone:BAAALgAECggJCgAAAA==.Darg:BAABLgAECn8rAAMfAAgJ9x4wDAAbAgAfAAgJ9x4wDAAbAgAMAAMJORUg5gC0AAAAAA==.Daurgoth:BAAALgADCgEJAQABLgADCgcJBwASAAAAAA==.',
Dd='Ddream:BAAALgADCgMJAwAAAA==.',
De='Deathpuma:BAABLgAECn8ZAAIfAAgJZhllEwCrAQAfAAgJZhllEwCrAQAAAA==.Deathrick:BAAALgAECgEJAQAAAA==.Deathrowe:BAABLgAECn84AAIMAAgJ8yHeFwCWAgAMAAgJ8yHeFwCWAgAAAA==.Deelyte:BAAALgAECgYJDgAAAA==.Deezenuts:BAAALgAECgEJAQAAAA==.Delorayne:BAAALgADCggJFwAAAA==.Demonic:BAAALgAECgEJAQAAAA==.Demonponii:BAAALgAECgkJEwAAAA==.Demonvann:BAAALgADCgkJJQAAAA==.Denouncer:BAABLgAECn8rAAMTAAgJICDkEgBVAgATAAcJHiDkEgBVAgABAAYJkRKFtQD0AAAAAA==.Deralth:BAAALgAECgMJAwAAAA==.Derca:BAABLgAECn8dAAMgAAUJCxcVKAD/AAAgAAUJCxcVKAD/AAAFAAEJ6wMs8AAiAAAAAA==.Dercadin:BAAALgAECgMJAwAAAA==.Dethman:BAAALgAECgQJBwAAAA==.Devoider:BAAALgAECgIJAgAAAA==.',
Di='Diddyknight:BAACLgAFFH8JAAIfAAQJchKTFgD1AAAfAAQJchKTFgD1AAAuAAQKfyUAAx8ACAmQEZIWAKwBAB8ACAmQEZIWAKwBAAwAAwmABp4QAVoAAAAA.Diddyrox:BAAALgADCgkJCAABLgAECggJHAAfADkdAA==.Dienne:BAEALgAECggJEgABLgAECgkJMgAYAGYZAA==.Dietunicorn:BAAALgAECgUJBQABLgAFFAIJBQAIAGcGAA==.Diminish:BAAALgAECgQJCAABLgAFFAEJAQASAAAAAA==.Diminutive:BAAALgADCgcJCAAAAA==.Dinarra:BAAALgAECgUJBQAAAA==.Diosdelaluna:BAAALgAECgEJAgAAAA==.Dipity:BAAALgADCgYJBgAAAA==.Discobirb:BAABLgAECn8sAAMGAAkJuhlHMwDzAQAGAAgJyxdHMwDzAQAJAAMJGh22HACgAAAAAA==.',
Do='Docdrood:BAAALgAECgEJAgAAAA==.Doctotems:BAAALgAECgQJBAAAAA==.Dohdag:BAAALgADCgEJAQAAAA==.Dokkyun:BAAALgADCgEJBAAAAA==.Donlazul:BAABLgAECn8dAAMeAAkJ4BkhHwAlAgAeAAkJ4BkhHwAlAgAhAAUJBg4HVQC2AAAAAA==.Dorff:BAABLgAECn83AAMJAAgJWhQPFQCiAQAGAAgJfBPoRQCyAQAJAAYJjBUPFQCiAQAAAA==.Dotlotto:BAABLgAECn8mAAIJAAgJrxnUBAD+AQAJAAgJrxnUBAD+AQAAAA==.',
Dr='Draconoth:BAABLgAECn8lAAIMAAgJrBFMVwCbAQAMAAgJrBFMVwCbAQAAAA==.Dragonare:BAAALgAECgYJBgABLgAECggJHAAfADkdAA==.Dragonir:BAAALgAECgQJDAABLgAECgkJKwABAGEdAA==.Dranddrand:BAABLgAECn8XAAICAAkJ5Bp4EwB1AgACAAkJ5Bp4EwB1AgAAAA==.Drandsdemise:BAAALgAECgcJBwAAAA==.Dreadborn:BAAALgADCgYJCAAAAA==.Dreadform:BAAALgAECgQJBQAAAA==.Drizit:BAAALgAECgQJBQAAAA==.Drunkardd:BAAALgADCgYJBgAAAA==.',
Du='Dumbbear:BAAALgADCgcJCgAAAA==.Dungard:BAAALgADCgcJBwABLgAECgkJNQATADoTAA==.Dunstird:BAABLgAFFH8KAAMMAAQJZRmsWAAdAQAMAAMJZx6sWAAdAQAiAAIJjg5rEgCRAAAAAA==.Durzi:BAAALgAECgUJBQABLgAFFAIJBQATALoiAA==.',
Dy='Dyami:BAAALgAECgYJBQAAAA==.',
['Dè']='Dèadèyè:BAAALgADCgEJAQAAAA==.',
Ea='Earthkorra:BAAALgADCgEJAQAAAA==.Eatmorechkn:BAABLgAECn8oAAIBAAkJvRW2MAAcAgABAAkJvRW2MAAcAgAAAA==.',
Ed='Edgerunners:BAAALgAECgcJCgAAAA==.Edgli:BAAALgAECgQJBAAAAA==.Edlania:BAAALgAECgEJAQAAAA==.',
Ee='Eellonwy:BAAALgAECgMJBwAAAA==.Eemerald:BAABLgAECn8WAAIDAAYJ6Qd5cQDAAAADAAYJ6Qd5cQDAAAAAAA==.',
Eg='Egna:BAABLgAECn8vAAIhAAkJmxHwIwCbAQAhAAkJmxHwIwCbAQAAAA==.',
El='Eldiablo:BAABLgAECn87AAIMAAkJpyFXFACtAgAMAAkJpyFXFACtAgAAAA==.Elfshots:BAAALgADCgQJBAABLgAECgcJFgAaAJwPAA==.Elizaa:BAABLgAECn8tAAMhAAkJsQhiMgBFAQAhAAkJsQhiMgBFAQAeAAcJdAdpXwAOAQAAAA==.Ellemeno:BAAALgAECgUJBQAAAA==.Eloria:BAAALgADCgIJAgAAAA==.',
Em='Emmadar:BAAALgADCgkJGwABLgAECgkJOwAGALsZAA==.',
En='Enhai:BAAALgADCgMJAwAAAA==.Ennoa:BAAALgAECgUJBAAAAA==.',
Er='Eric:BAAALgAECgYJCQAAAA==.Erinn:BAAALgADCggJDQAAAA==.Erioch:BAAALgAECgEJAQAAAA==.',
Et='Etoya:BAAALgAECgMJAwAAAA==.',
Ex='Execute:BAAALgADCgYJBwAAAA==.',
Ey='Eyllian:BAAALgADCgcJBwABLgAECgkJPQAMABohAA==.',
Ez='Ezykeil:BAAALgADCgYJBgAAAA==.',
Fe='Feelinbetter:BAAALgAECgIJBwAAAA==.Felicía:BAAALgAECgMJAwAAAA==.Fenrigaar:BAABLgAECn8iAAIbAAkJXBW1EwANAgAbAAkJXBW1EwANAgAAAA==.',
Fi='Fillin:BAAALgAECgQJCgAAAA==.Filô:BAACLgAFFH8SAAIPAAYJNQ4qCwBzAQAPAAYJNQ4qCwBzAQAuAAQKfykAAg8ACQmYIi4DAB0DAA8ACQmYIi4DAB0DAAAA.',
Fj='Fjörd:BAAALgAECgEJBQAAAA==.',
Fl='Flanker:BAAALgAECgcJDAABLgAECgkJJAAWAKIdAA==.Flashbang:BAAALgAECgcJCAABLgAECgkJMgAgADYVAA==.Flasherdemon:BAAALgAECgYJBgAAAA==.Flashoblight:BAAALgADCgYJDAABLgADCgkJDgASAAAAAA==.',
Fo='Forsakenly:BAABLgAECn8xAAIUAAkJdRZfJQAhAgAUAAkJdRZfJQAhAgAAAA==.',
Fr='Frasti:BAAALgAECgQJDQAAAA==.Freshstart:BAAALgAECgYJCQAAAA==.Frostmage:BAABLgAECn9BAAIWAAkJqR3XGACqAgAWAAkJqR3XGACqAgAAAA==.Frstbite:BAAALgAECgQJAgAAAA==.',
Fu='Fuegoblazeit:BAAALgAECgIJBAAAAA==.Fuhsrodah:BAAALgADCgEJAgAAAA==.Fulgure:BAABLgAECn8qAAIhAAkJ7RrpEgArAgAhAAkJ7RrpEgArAgAAAA==.Furbucket:BAABLgAECn8eAAMbAAkJEwlYNQAQAQAbAAgJ6wdYNQAQAQADAAUJqgnmkQCsAAAAAA==.Furfauxsake:BAAALgADCgkJCQAAAA==.Futon:BAAALgAECgQJBAAAAA==.Futonhunts:BAABLgAECn8yAAMUAAkJ2SAICQADAwAUAAkJ2SAICQADAwAZAAUJHA/RLgAMAQAAAA==.',
Fy='Fylerw:BAAALgAECggJEQAAAA==.',
['Få']='Fåe:BAAALgAECgMJBQAAAA==.',
Ga='Gagoogamesh:BAABLgAECn8oAAQMAAkJ3RFvSQDDAQAMAAkJZRBvSQDDAQAiAAkJ7AtgBwCJAQAfAAcJXAULNACaAAAAAA==.Gailyn:BAAALgAECgQJBAAAAA==.Galaxyshot:BAAALgADCgcJDAAAAA==.Garhiakitten:BAAALgADCgkJCQAAAA==.',
Ge='Gendershift:BAAALgADCgQJBAAAAA==.Getpsalm:BAAALgAECgkJBwAAAA==.',
Gh='Ghimpy:BAAALgAECgQJCgAAAA==.Ghostrideher:BAABLgAECn8pAAIUAAkJ0SEWEACoAgAUAAkJ0SEWEACoAgAAAA==.',
Gi='Gigadad:BAAALgAECgcJDAAAAA==.Gigafather:BAAALgAECggJDQAAAA==.',
Gl='Glaiverglaiv:BAAALgAECgEJAQAAAA==.Glurpglurp:BAAALgADCgEJAQAAAA==.',
Go='Goochkiss:BAAALgAECgMJAwAAAA==.Goyahokasinj:BAAALgADCgcJBwAAAA==.',
Gr='Griannee:BAABLgAECn8sAAIgAAkJgxtaCAB8AgAgAAkJgxtaCAB8AgAAAA==.Grimborn:BAAALgAECgIJAgAAAA==.Gripmedaddy:BAAALgADCgEJAQABLgAECgkJOQAYAGsbAA==.Grisdrips:BAAALgAECgQJBQAAAA==.Grislix:BAABLgAECn9DAAMGAAkJMxl4HQBaAgAGAAkJMxl4HQBaAgAJAAEJjgWJOwAfAAABLgAECgQJBQASAAAAAA==.Grismistea:BAAALgAECgcJCAABLgAECgQJBQASAAAAAA==.Gryffin:BAABLgAECn80AAIWAAkJPg+sUwDEAQAWAAkJPg+sUwDEAQAAAA==.',
Gu='Gurrth:BAAALgADCgMJAwAAAA==.',
['Gâ']='Gânk:BAABLgAECn8rAAMjAAkJmQtIGABuAQAjAAkJmQtIGABuAQAkAAIJmQJWnQBKAAAAAA==.',
['Gå']='Gåladriel:BAAALgAECgEJAQAAAA==.',
Ha='Hael:BAAALgAECgEJAQAAAA==.Halar:BAABLgAECn8VAAIDAAgJJg9lWQAKAQADAAgJJg9lWQAKAQAAAA==.Hammaford:BAAALgADCgMJAwAAAA==.Happiness:BAAALgAECgcJEgAAAA==.Hardknockers:BAABLgAECn8VAAIkAAYJEwsSSwDwAAAkAAYJEwsSSwDwAAAAAA==.Hargyll:BAAALgAECgcJDwAAAA==.',
He='Heavensbliss:BAAALgAECgMJAwABLgAECgkJQQAWAKkdAA==.Heavychevy:BAABLgAECn8fAAMkAAkJsBkZDwBhAgAkAAkJsBkZDwBhAgAjAAIJnRFxSABtAAAAAA==.Hellbentx:BAAALgAECgcJBwAAAA==.Heriel:BAAALgAECgQJBAABLgAECgkJKwABAGEdAA==.',
Hi='Hildoehealz:BAAALgAECgUJBQAAAA==.Hippyhunter:BAAALgAECgIJAwAAAA==.Hiroki:BAAALgADCgkJCQAAAA==.',
Ho='Hokes:BAACLgAFFH8FAAIWAAIJ8A3sgwCaAAAWAAIJ8A3sgwCaAAAuAAQKfxQAAhYABwnKHGNjABICABYABwnKHGNjABICAAEuAAUUAwkIAAMAYQ8A.Hole:BAAALgADCgMJAwAAAA==.Homgar:BAAALgADCgYJBwAAAA==.Hoori:BAABLgAFFH8TAAIlAAkJ4yMjAAAhAwAlAAkJ4yMjAAAhAwAAAA==.Hotsjkpurge:BAAALgAECgQJBAABLgAECgkJIgAaACwTAA==.',
Hu='Hughhoofner:BAAALgAECgUJBgAAAA==.Humphrees:BAABLgAECn87AAMmAAkJdxWsEAACAgAmAAkJdxWsEAACAgAOAAEJFwaYIQAqAAAAAA==.Huraji:BAAALgAFFAIJAgABLgAFFAUJEwAQAIEYAA==.',
Hy='Hydroheals:BAAALgAECgEJAgAAAA==.',
['Hà']='Hàtos:BAACLgAFFH8HAAIWAAIJEwlTjQCLAAAWAAIJEwlTjQCLAAAuAAQKfzgAAhYACQnHGZcnAGACABYACQnHGZcnAGACAAAA.Hàtoz:BAAALgAECgcJCQAAAA==.',
Ia='Ianisa:BAAALgAECgEJAQAAAA==.',
Id='Idot:BAAALgADCgUJBQABLgAECggJIwAgAFcNAA==.',
Ii='Iironrod:BAAALgADCgcJDgAAAA==.',
Il='Illran:BAAALgAECgIJAgAAAA==.',
Im='Imjustagirl:BAAALgADCgEJAQAAAA==.Impawsum:BAAALgADCgUJBwAAAA==.',
In='Invissibill:BAABLgAECn8rAAInAAgJcgk+CwA5AQAnAAgJcgk+CwA5AQAAAA==.',
Ir='Ironbark:BAAALgADCggJGAAAAA==.',
Iv='Ivanã:BAABLgAECn8pAAIdAAkJSRgdBQA3AgAdAAkJSRgdBQA3AgAAAA==.',
Iz='Izax:BAABLgAECn8wAAIGAAgJrRAiTQCcAQAGAAgJrRAiTQCcAQAAAA==.',
Ja='Jaakru:BAAALgADCgEJAQAAAA==.Jamestown:BAAALgADCgcJBwAAAA==.Janebquick:BAAALgAECgUJBgAAAA==.',
Je='Jelkal:BAAALgAECgkJEgAAAA==.Jemstone:BAAALgADCgYJBgAAAA==.',
Jj='Jjl:BAABLgAFFH8OAAIMAAYJviVZCAAsAgAMAAYJviVZCAAsAgAAAA==.',
Jo='Johnnylingo:BAAALgAECgEJAQAAAA==.Johnwarcratf:BAAALgAECgYJDAAAAA==.Jorim:BAAALgADCgUJBQAAAA==.',
Ju='Jupitus:BAABLgAECn8qAAIBAAkJJxpTHgByAgABAAkJJxpTHgByAgAAAA==.Juícewrld:BAAALgAECgQJBgAAAA==.',
['Jå']='Jåhkøtå:BAAALgAECgEJAQAAAA==.',
Ka='Kaboomkablow:BAAALgAECgQJBAABLgAECgcJFgAaAJwPAA==.Kaerou:BAAALgADCgkJEQAAAA==.Kaiborg:BAAALgADCgYJBgAAAA==.Kandranna:BAAALgADCgMJAwAAAA==.Kaosz:BAAALgADCgYJBgAAAA==.Karma:BAABLgAECn8iAAIaAAgJhCLxBwClAgAaAAgJhCLxBwClAgAAAA==.Katalania:BAAALgAECgYJBwAAAA==.Katalanii:BAABLgAECn8ZAAIDAAcJvgmFawDRAAADAAcJvgmFawDRAAAAAA==.Kathtaer:BAAALgADCggJDQAAAA==.Katinda:BAAALgADCgYJBgAAAA==.Katja:BAABLgAECn8YAAIGAAgJbRmlKQBqAgAGAAgJbRmlKQBqAgAAAA==.',
Ke='Kegna:BAAALgADCgkJEgAAAA==.Keiwhenua:BAABLgAECn8pAAMDAAkJURB+LgDIAQADAAkJURB+LgDIAQAbAAUJaAq0TQClAAAAAA==.Keled:BAABLgAECn8UAAMXAAYJKwTRIQB7AAAZAAYJIQPHOQC/AAAXAAQJ8APRIQB7AAAAAA==.Kelinn:BAAALgAECgQJCwAAAA==.Kelle:BAAALgAECggJDgAAAA==.Kelzier:BAAALgAECgUJCAABLgAECgkJKwABAGEdAA==.Kenthel:BAABLgAECn8XAAMmAAYJTBivIgBRAQAmAAUJdRmvIgBRAQAOAAEJfhIFIAA+AAAAAA==.Kenthels:BAABLgAECn8aAAMQAAYJghPeKwBIAQAQAAYJghPeKwBIAQAPAAEJYA/WbgA0AAABLgAECgYJFwAmAEwYAA==.Kezt:BAAALgADCgEJAQAAAA==.',
Kh='Khaleesi:BAAALgAECgkJCAAAAA==.Khalena:BAAALgADCgUJBwAAAA==.',
Ki='Kiiya:BAAALgAECgIJAgAAAA==.Kik:BAAALgAECgEJAQAAAA==.Killerchop:BAABLgAECn8gAAMcAAkJ8RjhBADvAQAcAAcJ8BjhBADvAQAWAAgJZBTXXwCkAQAAAA==.Kiplander:BAABLgAECn8eAAIbAAYJYBLnNQANAQAbAAYJYBLnNQANAQAAAA==.Kithforge:BAAALgADCgEJAQAAAA==.Kittytree:BAAALgADCgQJBAAAAA==.',
Ko='Kohii:BAAALgAECgIJAgAAAA==.Komosky:BAAALgAECgkJEgABLgAFFAcJHQAMAG4VAA==.Kongy:BAAALgADCgIJAgAAAA==.Korry:BAABLgAECn8UAAIVAAYJhg/BFwAGAQAVAAYJhg/BFwAGAQAAAA==.Kortanis:BAAALgAECgQJBAAAAA==.Korzaz:BAABLgAECn8fAAILAAcJ3w13CwA+AQALAAcJ3w13CwA+AQAAAA==.Kosiicek:BAAALgAECgEJAQAAAA==.Kotala:BAAALgAECgQJBAAAAA==.',
Kr='Krakìn:BAABLgAECn8ZAAIkAAYJiBBuPwAfAQAkAAYJiBBuPwAfAQAAAA==.Krelanllan:BAAALgADCgkJEAAAAA==.Krilliz:BAABLgAECn8aAAIgAAcJahP0HQBOAQAgAAcJahP0HQBOAQAAAA==.Krocodile:BAAALgAECgQJDAAAAA==.',
Ku='Kushage:BAAALgADCggJEAAAAA==.',
Ky='Kyndarra:BAAALgAECgIJAgABLgAECgkJLgADAAIRAA==.Kynlea:BAAALgADCgMJAwAAAA==.Kyumii:BAAALgADCgcJBwAAAA==.',
['Kà']='Kàstielle:BAAALgAECgcJDAAAAA==.',
['Kì']='Kìla:BAAALgAECgEJAQABLgAECgkJLwABAKEkAA==.',
La='Landissa:BAABLgAECn84AAImAAkJuxz9CAByAgAmAAkJuxz9CAByAgAAAA==.Lanigosa:BAAALgADCggJBwAAAA==.Lanno:BAAALgADCgUJBgAAAA==.Laquandrae:BAABLgAECn8eAAIBAAYJYyAGSgDJAQABAAYJYyAGSgDJAQAAAA==.Larryholmes:BAABLgAECn8WAAIaAAcJnA/3LQB0AQAaAAcJnA/3LQB0AQAAAA==.Lasting:BAAALgADCgYJCAAAAA==.Lathmaria:BAAALgADCgEJAQAAAA==.Lazydruid:BAAALgAECgMJBQAAAA==.',
Le='Leche:BAAALgAECgUJCQAAAA==.Leenaa:BAABLgAECn8uAAIDAAkJAhH8KgDdAQADAAkJAhH8KgDdAQAAAA==.Leesi:BAAALgAECgQJBAAAAA==.Lerash:BAAALgADCgIJAgAAAA==.',
Li='Liankaima:BAAALgADCgUJBQAAAA==.Lightninfury:BAAALgAECgUJBwAAAA==.Lihan:BAABLgAECn8YAAIkAAgJoBL3KwB+AQAkAAgJoBL3KwB+AQAAAA==.Lilieth:BAAALgAECgcJCQAAAA==.Lily:BAABLgAECn8vAAIMAAkJQho/IQBgAgAMAAkJQho/IQBgAgAAAA==.Lioele:BAEALgADCgEJAQABLgAECgkJMgAYAGYZAA==.Lite:BAAALgAECgUJBQAAAA==.Livelyfist:BAABLgAECn8pAAMYAAgJ/xy8DwByAgAYAAgJ/xy8DwByAgAaAAEJCA9MfgA0AAAAAA==.Livelywilds:BAAALgADCgYJBgAAAA==.Livvmore:BAAALgADCgEJAQAAAA==.',
Lo='Lockedtoit:BAAALgAECgQJBAAAAA==.Locki:BAAALgADCgcJBwAAAA==.Loosenut:BAAALgAECgEJAQAAAA==.Lortelle:BAAALgAECgQJBAABLgAECggJHAAfADkdAA==.Losic:BAAALgADCgcJCwAAAA==.Lotzofblood:BAABLgAECn8UAAIkAAgJIgoINQBPAQAkAAgJIgoINQBPAQAAAA==.Loverocket:BAABLgAECn8wAAIRAAkJjx8cAwDCAgARAAkJjx8cAwDCAgAAAA==.',
Lu='Lugosi:BAAALgADCgcJDQABLgAECgkJNQAFAL0aAA==.Lullers:BAAALgAECgMJBgAAAA==.Luna:BAAALgAECgYJCwABLgAFFAIJAgASAAAAAA==.Lunastorm:BAAALgADCggJFAAAAA==.Luroe:BAAALgADCgkJCQAAAA==.',
Ly='Lyralina:BAEALgADCgQJBAABLgAECgkJMgAYAGYZAA==.Lysergicon:BAAALgADCgEJAQAAAA==.Lyshia:BAABLgAECn8oAAIWAAkJqiGwGACrAgAWAAkJqiGwGACrAgAAAA==.Lyshion:BAAALgADCgYJBgAAAA==.',
['Lì']='Lìch:BAAALgADCgIJAgAAAA==.',
['Lí']='Líghthand:BAACLgAFFH8MAAIRAAQJ/iG7AQCJAQARAAQJ/iG7AQCJAQAuAAQKfyYAAxEACQk6IagBADYDABEACQk6IagBADYDAAEAAQm/DihYATUAAAAA.',
['Lý']='Lýght:BAAALgADCggJDAAAAA==.',
Ma='Magdaanii:BAAALgAECgYJCgAAAA==.Magedown:BAABLgAECn8jAAIWAAkJZhTOQQD7AQAWAAkJZhTOQQD7AQAAAA==.Magician:BAAALgAECgQJBwABLgAECgcJFgAaAJwPAA==.Magicmallet:BAABLgAECn8mAAITAAkJ7yWjAAC/AwATAAkJ7yWjAAC/AwAAAA==.Manwell:BAAALgAECgMJAwAAAA==.Martinell:BAAALgADCgYJDAAAAA==.Matap:BAAALgADCgkJGwAAAA==.Mataw:BAABLgAECn8lAAMkAAgJCx7PFgAUAgAkAAgJCx7PFgAUAgAjAAYJ3BCyFgBHAQAAAA==.Mattdemon:BAABLgAECn81AAIFAAkJvRrzHwA3AgAFAAkJvRrzHwA3AgAAAA==.Maulotov:BAAALgAECgYJBgAAAA==.',
Me='Mehruna:BAAALgADCgEJAgAAAA==.Meliany:BAAALgADCgYJCQAAAA==.Meliowar:BAAALgADCgQJBAAAAA==.Melkdudd:BAAALgAECgcJBwAAAA==.Mephmonster:BAAALgADCgEJAQAAAA==.Merrciless:BAAALgAECgYJCAAAAA==.Meríin:BAAALgADCggJDgAAAA==.Meteori:BAAALgADCgEJAQAAAA==.Metroboomkin:BAAALgAECgIJAgAAAA==.',
Mi='Miksi:BAAALgADCgcJFgABLgAECgUJDwASAAAAAA==.Miradele:BAABLgAECn8WAAMDAAgJEgaOXgD6AAADAAgJEgaOXgD6AAAbAAMJhQoUWAB/AAAAAA==.Miraxx:BAAALgAECgQJCQAAAA==.Misscleö:BAABLgAECn8uAAIBAAkJYxQUPgDtAQABAAkJYxQUPgDtAQAAAA==.Mistybrew:BAAALgADCgMJAwAAAA==.Miyoshi:BAABLgAECn8eAAImAAgJIggFJABGAQAmAAgJIggFJABGAQAAAA==.Mizrhi:BAAALgAECgMJBAAAAA==.',
Mo='Monthy:BAAALgADCgUJCAAAAA==.Moonkey:BAAALgAECgIJAgAAAA==.Moosakka:BAABLgAECn8xAAMYAAkJ5xdeEQBgAgAYAAkJ5xdeEQBgAgAaAAgJEROGIwBrAQAAAA==.Moosedluffy:BAAALgAECgcJEgAAAA==.Moosesiah:BAAALgAECgcJEQAAAA==.Moovinthru:BAAALgAECgUJCwAAAA==.Moraxes:BAABLgAECn8sAAMlAAkJox2hBgB+AgAlAAkJox2hBgB+AgAjAAUJORVxLADpAAAAAA==.Mordenkainen:BAABLgAECn8VAAMJAAYJSAfGJABoAAAGAAYJ7AZgqgDWAAAJAAQJNAbGJABoAAAAAA==.Morenor:BAABLgAECn8VAAIPAAYJXAaFPQAIAQAPAAYJXAaFPQAIAQAAAA==.Morphidmage:BAABLgAECn86AAIWAAkJlBGaRADyAQAWAAkJlBGaRADyAQAAAA==.Mortetdabo:BAAALgAECgYJBwAAAA==.Motoko:BAAALgAECgMJCQAAAA==.Motolei:BAAALgADCggJDgABLgAECgkJKwAdADISAA==.',
Mu='Muaadib:BAAALgAECgUJBQABLgAECgkJKwAdADISAA==.',
My='Mydin:BAABLgAECn8hAAIBAAkJFBcrSgDJAQABAAkJFBcrSgDJAQAAAA==.Myordarsh:BAABLgAECn8sAAQMAAkJ9xZ0LQAmAgAMAAkJ9xZ0LQAmAgAfAAYJxwlGLwC1AAAiAAIJBwgSJABWAAAAAA==.Myssaphra:BAAALgAFFAMJAwABLgAFFAQJDAADAIcSAA==.',
['Mì']='Mìsawa:BAAALgAECgYJEgAAAA==.',
Na='Nael:BAAALgAECgQJBAAAAA==.Naeleen:BAAALgADCgQJBwAAAA==.Nakai:BAAALgADCgkJGwAAAA==.Nasmage:BAAALgADCgkJCgAAAA==.Nastijiggle:BAAALgAECgYJBgABLgAECgkJIgAhAIgdAA==.',
Ne='Necromann:BAAALgADCgcJBwAAAA==.Nelfgonewild:BAAALgAECgIJBAAAAA==.Nexs:BAAALgAECgcJBwAAAA==.Nexxa:BAABLgAECn8tAAIUAAkJTBbgJgAZAgAUAAkJTBbgJgAZAgAAAA==.Neyrina:BAAALgADCgUJCAAAAA==.',
Ni='Nickk:BAAALgAECgkJAQAAAA==.Nightshadow:BAAALgAECgcJEwAAAA==.Niqkle:BAABLgAECn8uAAMhAAkJhBW0GgDgAQAhAAkJhBW0GgDgAQAeAAgJYAiBWwATAQAAAA==.Nirat:BAAALgADCgEJAQAAAA==.Nishandriel:BAAALgADCgkJDwAAAA==.Nivia:BAABLgAECn8YAAIWAAcJMh6EQQD8AQAWAAcJMh6EQQD8AQABLgAFFAcJIQAIAEscAA==.',
No='Nohurtscooby:BAAALgAECgQJCQAAAA==.Normond:BAAALgADCgUJDAAAAA==.Nosiaria:BAAALgAECgEJAQAAAA==.Notadh:BAABLgAECn8bAAIFAAgJ7A9eVABmAQAFAAgJ7A9eVABmAQAAAA==.Notmeanzy:BAABLgAECn84AAMPAAkJ1yG4BADzAgAPAAkJ1yG4BADzAgAQAAMJQhZkOwDOAAAAAA==.',
Ns='Nstagatr:BAAALgADCgEJAQAAAA==.',
Nu='Numeroun:BAAALgAECgQJCQAAAA==.Nunbora:BAAALgAECgEJAQAAAA==.',
['Né']='Nécrömancer:BAAALgADCgIJAgAAAA==.',
['Nï']='Nïghtknïght:BAAALgAECgMJAwAAAA==.',
Oc='Occidius:BAAALgAECgYJEAAAAA==.',
Ol='Oldoriel:BAAALgADCgIJAgAAAA==.Oleanna:BAABLgAECn8fAAIaAAcJgg7uMAAZAQAaAAcJgg7uMAAZAQABLgAECgkJPgABAPwZAA==.Olehanna:BAABLgAECn8+AAIBAAkJ/BlaLAAtAgABAAkJ/BlaLAAtAgAAAA==.Olendra:BAAALgAECgcJBwABLgAECgkJPgABAPwZAA==.',
On='Onyxcaduceus:BAAALgADCgQJBAABLgAECgkJMAAhAEETAA==.Onyxtear:BAAALgAECgUJBQABLgAECgkJMAAhAEETAA==.Onyxvolt:BAAALgADCgcJBwABLgAECgkJMAAhAEETAA==.',
Op='Opioid:BAABLgAECn8hAAIUAAgJBxmsNQDcAQAUAAgJBxmsNQDcAQAAAA==.Opsec:BAAALgAECgEJAgABLgAECgkJMgAgADYVAA==.Opsèc:BAABLgAECn8yAAMgAAkJNhUDEADyAQAgAAkJzBMDEADyAQAFAAkJGBG+QAClAQAAAA==.',
Or='Orsa:BAABLgAECn8VAAIhAAcJcxQkMACfAQAhAAcJcxQkMACfAQAAAA==.',
Ot='Othon:BAAALgADCgEJAQAAAA==.',
Ou='Oubus:BAAALgAECgkJCAAAAA==.Out:BAAALgAECgEJAQAAAA==.',
Pa='Palinurus:BAAALgADCgIJAgAAAA==.Pallywalnuts:BAAALgAECgEJAQAAAA==.Parleey:BAACLgAFFH8WAAIGAAcJZA8lFQCsAQAGAAcJZA8lFQCsAQAuAAQKfyoABAYACAmzHBQfAJ0CAAYACAmzHBQfAJ0CAAkABAnvCls1AOEAAAcAAQnBIB4oAFEAAAAA.',
Pe='Pebbles:BAAALgAECgIJAgABLgAECgYJEwASAAAAAA==.Pedren:BAABLgAECn8aAAIeAAcJRA9SQwBuAQAeAAcJRA9SQwBuAQAAAA==.Perfectpal:BAABLgAECn8iAAMTAAkJnhWrKQCaAQATAAkJnhWrKQCaAQABAAEJ3gfkagEuAAAAAA==.Peri:BAAALgADCgUJBQAAAA==.',
Ph='Phaeseus:BAAALgAECggJCgAAAA==.Phexaryl:BAAALgAECgUJBgAAAA==.',
Pl='Planette:BAABLgAECn8bAAIeAAkJFxTxHQAwAgAeAAkJFxTxHQAwAgAAAA==.',
Po='Poinda:BAAALgADCgIJAgAAAA==.Poisionivy:BAAALgADCgEJAQAAAA==.Pooskbuddy:BAAALgADCgkJCQAAAA==.Popcorners:BAABLgAECn81AAMQAAkJSB5pCAC4AgAQAAkJSB5pCAC4AgAPAAQJWxEjTACvAAAAAA==.Popopanda:BAAALgAECgUJDwAAAA==.Poppnlok:BAAALgADCgEJAQAAAA==.Pordgio:BAABLgAECn8iAAImAAkJDhHSEQD1AQAmAAkJDhHSEQD1AQAAAA==.Pozzi:BAAALgAECgUJCgAAAA==.',
Pr='Praypal:BAAALgAECgUJCQAAAA==.Problematiç:BAAALgADCgEJAQAAAA==.Proxxy:BAAALgADCgMJAwAAAA==.',
Ps='Psuedolus:BAABLgAECn8dAAIMAAgJdiLPLwAcAgAMAAgJdiLPLwAcAgAAAA==.Psålm:BAABLgAECn8dAAIPAAkJMBIeGADiAQAPAAkJMBIeGADiAQAAAA==.',
Pu='Pulshadow:BAACLgAFFH8bAAIPAAYJjRyUBQDMAQAPAAYJjRyUBQDMAQAuAAQKfyIAAg8ACQk3JDMFAD0DAA8ACQk3JDMFAD0DAAAA.Pumah:BAAALgAECgQJDQAAAA==.Pumpmedaddy:BAAALgADCgYJBgABLgAECgkJOQAYAGsbAA==.Purified:BAAALgAECgIJAgABLgAFFAgJIwACAHYSAA==.',
Pw='Pweenqween:BAAALgADCgEJAQAAAA==.',
Py='Pyreska:BAAALgAECgkJDAAAAA==.Pyroklasm:BAABLgAECn8bAAIWAAcJtByGUwA9AgAWAAcJtByGUwA9AgAAAA==.',
Qt='Qthunter:BAAALgADCgkJCQABLgAECgkJIgAaACwTAA==.Qtlocks:BAAALgADCgkJCQABLgAECgkJIgAaACwTAA==.Qtmonk:BAABLgAECn8iAAIaAAkJLBOzFgDXAQAaAAkJLBOzFgDXAQAAAA==.',
Qu='Quartzecoatl:BAAALgADCgMJAwAAAA==.Quela:BAAALgAECgMJBgAAAA==.Quintcaster:BAAALgAECgQJBgAAAA==.Quirt:BAAALgAFFAMJBAAAAA==.',
Ra='Raamen:BAAALgAECgUJDwAAAA==.Rabiéz:BAAALgAECgQJCAAAAA==.Radioface:BAAALgAECgIJAwAAAA==.Raellia:BAABLgAECn87AAQGAAkJuxnIPADPAQAGAAcJHxjIPADPAQAJAAMJuRgHIACGAAAHAAIJFxuZHgCFAAAAAA==.Raimmey:BAAALgAECgMJBQAAAA==.Rajann:BAAALgADCgMJAwAAAA==.Rajia:BAABLgAECn8aAAIJAAcJ2wyeEAANAQAJAAcJ2wyeEAANAQABLgAECggJLgAJAKoQAA==.Rakaw:BAAALgADCgMJAwAAAA==.Ralune:BAABLgAECn8uAAIbAAgJ7w8NJQB0AQAbAAgJ7w8NJQB0AQAAAA==.Randomdhunte:BAAALgADCgkJEgAAAA==.Randomone:BAABLgAECn8aAAITAAkJ5whHLwB2AQATAAkJ5whHLwB2AQAAAA==.Ranes:BAABLgAECn87AAQmAAkJ6yE+BgCpAgAmAAkJ6yE+BgCpAgAOAAQJuA/IEgDWAAAnAAEJQwfSHgApAAAAAA==.Rathmore:BAAALgAECgQJBQAAAA==.Raylavoidles:BAAALgADCgcJDgAAAA==.Rayllee:BAAALgAECgcJEAAAAA==.',
Re='Redi:BAAALgADCgYJBgAAAA==.Redxelementz:BAABLgAECn8nAAIeAAkJZCMSBwAZAwAeAAkJZCMSBwAZAwAAAA==.Relyana:BAAALgADCgEJAQAAAA==.Remena:BAABLgAECn8WAAIaAAcJERzmFwAlAgAaAAcJERzmFwAlAgAAAA==.Renasen:BAABLgAECn8dAAMjAAkJ2iJgBACtAgAjAAgJriNgBACtAgAkAAcJpxaJNQBMAQAAAA==.Rendiwyn:BAAALgADCgcJBwAAAA==.Reno:BAABLgAECn8tAAMTAAkJ+B5zBgAFAwATAAkJ+B5zBgAFAwABAAEJjBLuTwE3AAAAAA==.René:BAAALgADCgUJBwAAAA==.Resimetha:BAAALgADCgcJCAAAAA==.Resiretha:BAABLgAECn8gAAMGAAkJogQBewAuAQAGAAkJogQBewAuAQAJAAEJBQUhegAoAAAAAA==.Revelynn:BAABLgAECn8wAAMFAAkJJR4MGABpAgAFAAkJJR4MGABpAgAdAAEJcx37IwBTAAAAAA==.',
Rh='Rhemedi:BAAALgAECgYJDAAAAA==.Rhico:BAAALgADCgEJAQAAAA==.Rhyin:BAAALgADCgYJBgAAAA==.',
Ri='Riolu:BAAALgAECgQJBgAAAA==.',
Rn='Rngesus:BAAALgAECgEJAQABLgAECgkJPQAMABohAA==.',
Ro='Robotmonk:BAAALgAECgcJCwABLgAFFAQJDAARAP4hAA==.Rook:BAAALgAECgEJAQAAAA==.Rooxxy:BAAALgAECgcJEwAAAA==.Rotawna:BAABLgAECn8WAAIhAAYJkAVlVgCxAAAhAAYJkAVlVgCxAAAAAA==.Roxxye:BAAALgADCgEJAQABLgAECgcJEwASAAAAAA==.',
Ru='Rumikang:BAAALgADCgkJCQABLgAECgkJOwAGALsZAA==.Rumms:BAAALgAECgcJCwAAAA==.Rustybottom:BAAALgADCgEJAQAAAA==.Ruumis:BAAALgAECgQJBAAAAA==.',
Ry='Rydric:BAABLgAECn8WAAIWAAgJFyPIEwAxAwAWAAgJFyPIEwAxAwAAAA==.Ryezn:BAAALgAECgEJAQAAAA==.Rygrim:BAAALgAECgUJBQAAAA==.Ryxhal:BAAALgADCgYJBgAAAA==.Ryzur:BAAALgAECggJCQAAAA==.',
['Rï']='Rïnzlër:BAAALgAECgcJEwAAAA==.',
Sa='Saela:BAAALgAECgYJBgAAAA==.Sarac:BAABLgAECn8hAAIlAAgJuAJOKADIAAAlAAgJuAJOKADIAAAAAA==.Saratosh:BAAALgADCgEJAQAAAA==.Savira:BAAALgAECgYJDQAAAA==.',
Sc='Scaleorva:BAABLgAECn8lAAMLAAgJzA8ECgBeAQALAAcJVhEECgBeAQAKAAMJQQkKXgCRAAAAAA==.',
Se='Sealmedaddy:BAAALgADCgEJAQABLgAECgkJOQAYAGsbAA==.Selfaware:BAAALgAECgYJBwABLgAECggJIAACAFkeAA==.Seraphìm:BAABLgAECn8eAAIBAAkJJAfFeQBaAQABAAkJJAfFeQBaAQAAAA==.',
Sh='Shadefu:BAAALgADCgYJBgABLgAECggJKwAcAIAOAA==.Shadowjacker:BAAALgAECgEJAQAAAA==.Shadyballs:BAABLgAECn8rAAQcAAgJgA6CBQBSAQAWAAgJ5wvadQBwAQAcAAcJsw+CBQBSAQAoAAYJUgpBBwDwAAAAAA==.Shakypete:BAAALgAECgYJDgABLgAECgYJHgAbAGASAA==.Shalaena:BAAALgAECgMJAwAAAA==.Shamagorn:BAAALgADCgcJBwAAAA==.Shamysosa:BAABLgAECn8oAAMhAAcJWBymHgDAAQAhAAcJWBymHgDAAQAeAAUJ7hGdXQAMAQAAAA==.Shanebentea:BAABLgAECn8yAAIkAAkJThYwFAArAgAkAAkJThYwFAArAgAAAA==.Shaozan:BAAALgADCgcJBwAAAA==.Sharpy:BAAALgAECgcJDQABLgAECggJMgAWAIseAA==.Sharpyboi:BAAALgADCgMJAwABLgAECggJMgAWAIseAA==.Sharpyy:BAAALgADCgYJBgABLgAECggJMgAWAIseAA==.Shinjí:BAACLgAFFH8TAAIMAAQJMyErKgB0AQAMAAQJMyErKgB0AQAuAAQKfzAAAwwACAmSIkUaAIcCAAwACAmSIkUaAIcCAB8AAQkIAEtRAAEAAAEuAAUUBgkbAAwAFR4A.Shiven:BAAALgAECgYJEQAAAA==.Shmob:BAABLgAECn8VAAIhAAYJ4g3SPAARAQAhAAYJ4g3SPAARAQAAAA==.Shnappz:BAABLgAECn8qAAMGAAgJnwx6aABVAQAGAAcJmAl6aABVAQAJAAQJ+hHDHACfAAAAAA==.Shockittome:BAAALgADCgUJBQAAAA==.Shroomee:BAABLgAFFH8SAAQDAAkJgQvzDADPAQADAAcJZArzDADPAQAbAAQJkBokHAAUAQANAAIJkBRYFgCKAAAAAA==.Shwillacus:BAAALgADCgkJEgAAAA==.Shwillarou:BAABLgAECn86AAIMAAkJbA+7SQDCAQAMAAkJbA+7SQDCAQAAAA==.Shwillmoon:BAAALgADCgkJEgAAAA==.Shärpy:BAABLgAECn8yAAIWAAgJix6iJQBpAgAWAAgJix6iJQBpAgAAAA==.',
Si='Silverstring:BAAALgAECgYJEgAAAA==.Simmi:BAAALgAECgIJAgAAAA==.Sinergee:BAABLgAECn8vAAIUAAkJURQzJwAYAgAUAAkJURQzJwAYAgAAAA==.Sinfulgold:BAAALgADCgQJBAAAAA==.Sinfulkitten:BAAALgADCggJFwAAAA==.Sinnj:BAABLgAECn8bAAIWAAcJUAcItwD6AAAWAAcJUAcItwD6AAAAAA==.Sithlörd:BAAALgAECgcJCQAAAA==.',
Sk='Skinney:BAAALgAECgIJAwAAAA==.Skinsey:BAAALgAECgMJAwAAAA==.Skycrush:BAAALgAECgQJBwAAAA==.',
Sl='Slanie:BAABLgAECn8pAAIIAAgJnxD9IACYAQAIAAgJnxD9IACYAQAAAA==.Slayne:BAAALgADCgEJAgAAAA==.Slingerz:BAABLgAECn82AAIlAAkJpBavDgDUAQAlAAkJpBavDgDUAQAAAA==.Slowmeaux:BAAALgADCgYJCgAAAA==.',
Sm='Smoky:BAABLgAECn8bAAQGAAkJZSBFOwAfAgAGAAcJMyBFOwAfAgAJAAMJPB+9LAALAQAHAAEJAACVIgBnAAAAAA==.',
Sn='Snacky:BAAALgADCgIJAgAAAA==.Sneakpastya:BAABLgAECn8qAAImAAkJrAbqHACEAQAmAAkJrAbqHACEAQAAAA==.Sneakyg:BAAALgAECgEJAQABLgAECgkJKwABAGEdAA==.Snooksdk:BAAALgADCgEJAQAAAA==.',
So='Solkar:BAABLgAECn8eAAIRAAgJRxT0EACIAQARAAgJRxT0EACIAQAAAA==.Sollis:BAABLgAECn8WAAIWAAUJUAVi5gCsAAAWAAUJUAVi5gCsAAAAAA==.Sonastii:BAABLgAECn8iAAIhAAkJiB2mDAB3AgAhAAkJiB2mDAB3AgAAAA==.Soulbztrd:BAABLgAECn8gAAMJAAkJABdsGgB5AQAJAAUJIRpsGgB5AQAGAAcJDxTreQAwAQAAAA==.Soulmoss:BAAALgAECgYJBgABLgAECgYJBgASAAAAAA==.Soulpepper:BAAALgAECgQJBAAAAA==.Soulreaper:BAAALgAECgYJBgABLgAECgYJBgASAAAAAA==.Soulsnatcher:BAAALgAECgYJBgAAAA==.',
Sp='Spazzchel:BAAALgAECgQJCwAAAA==.Spinmedaddy:BAAALgAECgQJBAABLgAECgkJOQAYAGsbAA==.Spruce:BAAALgADCgkJJAAAAA==.',
St='Stahlman:BAABLgAECn87AAIeAAkJdxzNFQBvAgAeAAkJdxzNFQBvAgAAAA==.Stalpho:BAABLgAECn8qAAIkAAkJzRWfFQAeAgAkAAkJzRWfFQAeAgAAAA==.Starflare:BAAALgAECgUJCQABLgAECgkJMAAeAOoRAA==.Starkind:BAABLgAECn8wAAIeAAkJ6hF/KADuAQAeAAkJ6hF/KADuAQAAAA==.Stefussy:BAAALgADCgIJAgAAAA==.Stetson:BAAALgAECgIJAgAAAA==.Stonefist:BAABLgAECn8WAAIaAAYJ2A4dOAD1AAAaAAYJ2A4dOAD1AAABLgAECgcJKAAhAFgcAA==.Stoutmist:BAAALgAECgEJAQAAAA==.Sturr:BAAALgAECgEJAQAAAA==.Styrke:BAAALgAECgIJAgAAAA==.',
Su='Subza:BAAALgADCgMJAwAAAA==.Sundalo:BAAALgAECgUJCAAAAA==.Supergood:BAAALgAECgYJBgAAAA==.Superjoyful:BAAALgADCgEJAQAAAA==.Supersweet:BAAALgADCgYJEQAAAA==.Sutterkain:BAAALgAECgMJBAAAAA==.',
Sw='Swagadin:BAABLgAECn8pAAIBAAkJ1yRWBwBdAwABAAkJ1yRWBwBdAwAAAA==.Swaquinius:BAAALgAECgUJBgAAAA==.',
Sy='Syine:BAAALgADCgUJBQAAAA==.Sylee:BAABLgAFFH8KAAIYAAQJTRp9GgAkAQAYAAQJTRp9GgAkAQAAAA==.',
Ta='Tabitia:BAABLgAECn8qAAMUAAkJEROKNQDdAQAUAAkJxxGKNQDdAQAZAAYJnhL+FAB4AQAAAA==.Tahra:BAAALgADCgcJDQAAAA==.Taladari:BAAALgADCgEJAQAAAA==.Taliss:BAABLgAECn8hAAIIAAgJvR7BCgCUAgAIAAgJvR7BCgCUAgAAAA==.Talonpepper:BAAALgADCgMJAwAAAA==.Tankmedaddy:BAABLgAECn85AAMYAAkJaxt7CwCvAgAYAAkJaxt7CwCvAgAaAAEJawMEiAAoAAAAAA==.Tankopotamus:BAAALgADCgEJAQAAAA==.Tapenga:BAAALgAECgQJBAAAAA==.Tappuccino:BAAALgAECgUJCwAAAA==.Taras:BAACLgAFFH8PAAIkAAMJIyQqEQD+AAAkAAMJIyQqEQD+AAAuAAQKfxwAAiQACQkGIPEHACoDACQACQkGIPEHACoDAAAA.Taraxist:BAABLgAECn80AAIJAAkJhBslAgCAAgAJAAkJhBslAgCAAgAAAA==.Tarcanisdk:BAABLgAECn8oAAIMAAkJSRs1IwBWAgAMAAkJSRs1IwBWAgAAAA==.Tasuma:BAAALgAECgYJDAAAAA==.Tautology:BAABLgAECn8fAAIPAAgJVxgkHwClAQAPAAgJVxgkHwClAQAAAA==.Tazdingo:BAAALgADCgEJAQAAAA==.',
Tc='Tchala:BAABLgAECn8rAAIBAAkJYR0DHAB/AgABAAkJYR0DHAB/AgAAAA==.Tchallah:BAAALgADCgYJBgABLgAECgYJFwANABoTAA==.Tchaumb:BAAALgAFFAEJAQAAAA==.',
Te='Tedeschi:BAAALgAECgEJAgAAAA==.Teks:BAABLgAECn80AAITAAkJyR+hBAAuAwATAAkJyR+hBAAuAwAAAA==.Teksakah:BAAALgADCggJCAABLgAECgkJNAATAMkfAA==.Teksara:BAAALgADCgcJBwABLgAECgkJNAATAMkfAA==.Teksbane:BAAALgADCgcJBwABLgAECgkJNAATAMkfAA==.Tekszen:BAAALgAECgEJAQABLgAECgkJNAATAMkfAA==.Tencup:BAABLgAECn8gAAICAAgJWR4pCwBkAgACAAgJWR4pCwBkAgAAAA==.Tengoa:BAAALgAECgEJAQAAAA==.Teth:BAABLgAECn8tAAMJAAgJixk6BAAUAgAJAAgJixk6BAAUAgAGAAEJuQFENgEfAAAAAA==.Tetsuyo:BAAALgAECgYJDwAAAA==.Tevildo:BAAALgAECgEJAwAAAA==.',
Th='Thaine:BAABLgAECn82AAIBAAkJtyRJCQAFAwABAAkJtyRJCQAFAwAAAA==.Theelvira:BAAALgADCgYJBgAAAA==.Theoalthor:BAAALgAECgMJAwAAAA==.Theresis:BAAALgAECgMJBAAAAA==.Therkadin:BAAALgAECgYJEAAAAA==.Theundeadone:BAAALgAECgYJCAAAAA==.Thndrwzrd:BAABLgAECn8ZAAIUAAYJjAfmjgDvAAAUAAYJjAfmjgDvAAAAAA==.Throw:BAAALgAECgMJAwABLgAECgUJBQASAAAAAA==.Thrust:BAAALgADCgIJAgAAAA==.',
Ti='Ticho:BAABLgAECn8kAAIMAAkJLgYfeABNAQAMAAkJLgYfeABNAQAAAA==.Tidel:BAAALgAECgYJCQAAAA==.Tindmina:BAABLgAECn8bAAITAAcJvBkXMgC3AQATAAcJvBkXMgC3AQAAAA==.Tinglekin:BAAALgAECgIJAwAAAA==.',
Tl='Tlo:BAAALgAECgcJDgAAAA==.Tlol:BAAALgAECgUJBwABLgAECgcJDgASAAAAAA==.',
To='Toenails:BAAALgADCgYJBgAAAA==.Topflight:BAAALgAECgEJAQABLgAECgQJBAASAAAAAA==.Torkkit:BAAALgAECgEJAwABLgAECgYJDQASAAAAAA==.Torodisilis:BAAALgAECgIJAgABLgAECgkJKwABAGEdAA==.Torqit:BAAALgAECgMJBQABLgAECgYJDQASAAAAAA==.Totemdude:BAAALgADCgEJAQAAAA==.Totemzrus:BAAALgAECgcJEgAAAA==.',
Tr='Trath:BAAALgADCgcJCwAAAA==.Trent:BAAALgADCgQJCAAAAA==.Treygec:BAAALgADCgkJCQAAAA==.Trickette:BAAALgAECgkJCQAAAA==.Trickeye:BAAALgADCgIJAgAAAA==.Trina:BAAALgADCgkJCQAAAA==.Trollmorty:BAAALgAECgEJAQAAAA==.',
Tw='Twicks:BAABLgAFFH8PAAQaAAUJlBPpAgB8AQAaAAUJ5RHpAgB8AQAYAAQJNgJ8JQDIAAACAAEJfRhHSQBHAAABLgAFFAcJBwAPAPEhAA==.',
Tz='Tzaim:BAAALgADCgkJCQAAAA==.Tzuri:BAAALgAECgIJBAAAAA==.',
Ud='Udderlyquiff:BAAALgAECgIJAgAAAA==.Udderlyslow:BAABLgAECn8eAAIeAAcJByGcGwA7AgAeAAcJByGcGwA7AgAAAA==.',
Ug='Uglyloser:BAAALgAECgIJAwAAAA==.',
Un='Undeez:BAAALgAECgMJAwAAAA==.Unluckyfrien:BAAALgAECgIJAgAAAA==.',
Va='Vaeshta:BAABLgAECn8gAAIVAAgJAAQZGQD2AAAVAAgJAAQZGQD2AAAAAA==.Vaku:BAAALgAECgEJAQAAAA==.Valhallarama:BAABLgAECn8ZAAIeAAgJxwppUwAwAQAeAAgJxwppUwAwAQAAAA==.Vampy:BAABLgAECn8YAAIXAAcJKxOwDQBbAQAXAAcJKxOwDQBbAQAAAA==.Vannida:BAAALgAECgUJBQAAAA==.Vanìlla:BAAALgADCgEJAQAAAA==.Varya:BAABLgAECn8VAAIkAAgJVQewPAAqAQAkAAgJVQewPAAqAQAAAA==.Vasuvious:BAABLgAECn8iAAICAAcJDR2ZHgANAgACAAcJDR2ZHgANAgAAAA==.',
Ve='Vesstara:BAAALgADCgcJEQABLgAECgQJCQASAAAAAA==.Vet:BAAALgAECgkJAQAAAA==.',
Vi='Vinago:BAAALgAECgMJAwAAAA==.',
Vo='Voidabyss:BAAALgADCgUJBQAAAA==.Voidixx:BAAALgADCggJEwAAAA==.Voodoo:BAAALgAECgYJCgAAAA==.',
Vy='Vyleta:BAAALgADCgYJBgAAAA==.Vyllian:BAABLgAECn89AAMMAAkJGiFfEwC0AgAMAAkJHCBfEwC0AgAfAAgJ+Q6GHQA6AQAAAA==.Vyri:BAAALgAECgEJAQAAAA==.',
['Vá']='Váz:BAAALgADCgYJBgABLgAFFAMJCAADAGEPAA==.',
Wa='Wangwang:BAAALgAECgUJCwAAAA==.Warlakaflaka:BAAALgAECgUJEwABLgAECggJKwAcAIAOAA==.',
We='Welikeweed:BAAALgAECgYJDAABLgAFFAMJCQAeAKMYAA==.',
Wh='Whale:BAABLgAECn8mAAIlAAkJqBwdBwBxAgAlAAkJqBwdBwBxAgAAAA==.Whine:BAAALgAECgQJBwAAAA==.',
Wi='Wibbers:BAAALgAECgEJAwAAAA==.Wicked:BAABLgAECn8XAAIBAAUJliAPigA7AQABAAUJliAPigA7AQABLgAFFAEJAQASAAAAAA==.Willôw:BAAALgADCgkJEQABLgAECgkJGwAIALEfAA==.Windwalker:BAABLgAECn8aAAIaAAkJ/BAgGwCrAQAaAAkJ/BAgGwCrAQAAAA==.Winkey:BAAALgADCgYJBgAAAA==.Winston:BAAALgADCgcJCwAAAA==.',
Wo='Wolfsong:BAAALgADCgMJBAABLgAECgQJBgASAAAAAA==.Woosaah:BAAALgAECgcJBwAAAA==.',
Wr='Wreckyou:BAABLgAECn8WAAQJAAYJXA8uMgDwAAAGAAYJ/wcNqwADAQAJAAYJxgYuMgDwAAAHAAUJmw71FgDRAAAAAA==.',
Wt='Wtfimkorgak:BAABLgAECn8yAAIIAAgJxyBnEQBXAgAIAAgJxyBnEQBXAgAAAA==.',
Wy='Wy:BAAALgADCgYJBgAAAA==.Wylestrean:BAABLgAECn80AAMZAAkJ/xp+DwAcAgAZAAgJsxp+DwAcAgAUAAMJWBgcwQB/AAAAAA==.',
Xa='Xandoriel:BAAALgADCgQJBAAAAA==.',
Xi='Xiaomao:BAEBLgAECn8yAAQYAAgJZhnQIADQAQAYAAgJZhnQIADQAQAaAAMJwwc7WgB5AAACAAEJcgCImAAXAAAAAA==.',
Xy='Xyrathul:BAAALgAECgEJAgAAAA==.',
Ya='Yaric:BAAALgAECgMJBQAAAA==.',
Ye='Yeahigotmilk:BAAALgADCgUJBQAAAA==.Yeinn:BAAALgAFFAIJAwAAAA==.Yellowgoblin:BAAALgAECgIJAgAAAA==.',
Yo='Yopali:BAAALgAECgIJAwAAAA==.',
Yu='Yugiohrox:BAABLgAECn8cAAIfAAgJOR2DCwBbAgAfAAgJOR2DCwBbAgAAAA==.Yujology:BAABLgAECn8pAAIdAAkJIAmTDABgAQAdAAkJIAmTDABgAQAAAA==.',
Za='Zandalarthas:BAAALgAECgIJAgABLgAECggJHgACAKoXAA==.Zaolandoorss:BAAALgAECgEJAQAAAA==.',
Ze='Zel:BAABLgAECn8ZAAIJAAYJNgnAFwDEAAAJAAYJNgnAFwDEAAAAAA==.Zentradei:BAAALgAECgUJCwAAAA==.Zephariel:BAAALgADCgcJBwAAAA==.Zephirothh:BAAALgAECgUJBAAAAA==.',
Zi='Zieganfuss:BAABLgAECn8dAAIWAAgJYB0AVQA5AgAWAAgJYB0AVQA5AgAAAA==.Zilly:BAAALgAECgEJAQAAAA==.Zimmy:BAAALgADCggJDgAAAA==.',
Zo='Zoho:BAABLgAECn8gAAICAAgJWBIoJQBlAQACAAgJWBIoJQBlAQAAAA==.Zoomies:BAAALgADCgMJAwAAAA==.',
Zu='Zulkai:BAABLgAECn8tAAIDAAkJfhkMEQCoAgADAAkJfhkMEQCoAgAAAA==.',
Zy='Zynvar:BAAALgADCgYJBgAAAA==.',
['Zá']='Záv:BAACLgAFFH8IAAIDAAMJYQ8WMgDIAAADAAMJYQ8WMgDIAAAuAAQKfxgAAwMACAl2FzInABkCAAMACAl2FzInABkCAAQAAglKCowvAGEAAAAA.',
['Zä']='Zäne:BAABLgAECn8ZAAIWAAYJIBpCjQC4AQAWAAYJIBpCjQC4AQAAAA==.',
['Çl']='Çlù:BAAALgAECgYJBwAAAA==.',
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
