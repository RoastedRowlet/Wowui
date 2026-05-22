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

local lookup = {'Paladin-Retribution','Monk-Brewmaster','Druid-Restoration','DemonHunter-Devourer','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Druid-Guardian','Rogue-Assassination','Priest-Shadow','Priest-Discipline','Paladin-Protection','Unknown-Unknown','Paladin-Holy','Hunter-BeastMastery','Shaman-Enhancement','Mage-Frost','Hunter-Marksmanship','Monk-Mistweaver','Hunter-Survival','Monk-Windwalker','Druid-Balance','Mage-Arcane','DemonHunter-Vengeance','Shaman-Restoration','DeathKnight-Blood','Shaman-Elemental','DeathKnight-Frost','DemonHunter-Havoc','Warrior-Arms','Warrior-Fury','Warrior-Protection','Rogue-Subtlety','Rogue-Outlaw','Warlock-Affliction','Mage-Fire','Druid-Feral',}
local provider = {region='US',realm='Blackhand',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abadacalama:BAABLgAECn8VAAIBAAcJERXJWQB1AQABAAcJERXJWQB1AQAAAA==.',
Ad='Adera:BAAALgADCgEJAQAAAA==.',
Ae='Aellee:BAAALgAECgQJCAAAAA==.Aeninas:BAABLgAECn8bAAICAAYJ+Rh4IwBQAQACAAYJ+Rh4IwBQAQAAAA==.Aeris:BAAALgADCgEJAQAAAA==.Aerynn:BAAALgADCgIJAgAAAA==.Aethwyn:BAAALgAECgcJBwAAAA==.',
Af='Afflictions:BAAALgADCgUJBQAAAA==.',
Ag='Agandaur:BAAALgAECgEJAQAAAA==.',
Ah='Ahnkala:BAAALgAECgUJCwAAAA==.Ahzi:BAABLgAECn8lAAIDAAgJ0hxOEwBsAgADAAgJ0hxOEwBsAgAAAA==.Ahzii:BAAALgADCgYJBwAAAA==.',
Ai='Aigirlfriend:BAABLgAECn8oAAIEAAkJPQpLSQBbAQAEAAkJPQpLSQBbAQAAAA==.Ains:BAAALgAECgkJEwAAAA==.Airsia:BAAALgADCggJDAAAAA==.',
Ak='Akro:BAAALgAECgEJAgABLgAECgcJGQABAJkkAA==.',
Al='Alarrah:BAAALgAECgQJBAAAAA==.Allupcreepy:BAABLgAECn8cAAIFAAgJ3CGTBgDHAgAFAAgJ3CGTBgDHAgAAAA==.Alphaandy:BAAALgAECgMJAwAAAA==.Alphaboy:BAAALgADCgcJBwAAAA==.Alphaxdruid:BAAALgAECgMJAwAAAA==.Alphaxsham:BAAALgADCgIJAgAAAA==.Alysara:BAAALgAECgMJAwAAAA==.',
Am='Ambewlance:BAABLgAECn8YAAMGAAgJSQ+TUQBoAQAGAAgJKA+TUQBoAQAHAAMJRA51QQCvAAAAAA==.Ambrosious:BAAALgAECgEJAQAAAA==.Amethystra:BAABLgAECn8pAAMIAAkJew2CIACDAQAIAAkJew2CIACDAQAJAAMJwwaXMgCBAAAAAA==.Amâlynd:BAABLgAECn8gAAIDAAgJvAjeSwAXAQADAAgJvAjeSwAXAQAAAA==.',
An='Anastasiaro:BAAALgADCgEJAQAAAA==.Anien:BAAALgADCgEJAQAAAA==.Annimosity:BAAALgAECgIJAwAAAA==.Ansem:BAAALgADCgUJBgAAAA==.Anthesis:BAACLgAFFH8MAAIDAAQJhxJgIQAAAQADAAQJhxJgIQAAAQAuAAQKfyMAAgMACAkQGmgWAEwCAAMACAkQGmgWAEwCAAAA.Anthonor:BAAALgAECgYJCAAAAA==.Anubrian:BAABLgAECn8ZAAIKAAcJ/AVukAD7AAAKAAcJ/AVukAD7AAAAAA==.Anúbis:BAAALgAECgUJCgAAAA==.',
Ap='Apawllo:BAABLgAECn8vAAILAAkJLxRrDQCfAQALAAkJLxRrDQCfAQAAAA==.Apep:BAABLgAECn8UAAIMAAUJtB1fCwA3AQAMAAUJtB1fCwA3AQAAAA==.Apostle:BAACLgAFFH8fAAIFAAYJshxTAQC6AQAFAAYJshxTAQC6AQAuAAQKfzMAAgUACQm5I/UBAF4DAAUACQm5I/UBAF4DAAAA.',
Ar='Aramìs:BAAALgADCgYJBgAAAA==.Arlida:BAAALgADCgYJBgABLgAECgkJKwADAO0QAA==.Aryto:BAABLgAECn8lAAMNAAcJIiApDwAYAgANAAcJIiApDwAYAgAOAAEJOgXNWgAtAAAAAA==.',
As='Ashlar:BAAALgADCgYJDAAAAA==.Asketill:BAACLgAFFH8FAAIBAAIJOwITZgB9AAABAAIJOwITZgB9AAAuAAQKfx8AAgEACAlRFT9IAKQBAAEACAlRFT9IAKQBAAAA.Astora:BAAALgADCggJCgABLgAECggJGAACAMgaAA==.',
Au='Auluras:BAAALgADCgUJBQAAAA==.Auren:BAAALgADCgEJAQAAAA==.',
Av='Avitus:BAAALgADCgIJBAAAAA==.',
Ay='Aylari:BAABLgAECn8vAAMBAAkJoSRKBAAuAwABAAkJjyRKBAAuAwAPAAYJ+ReaEgCgAQAAAA==.',
Az='Azonya:BAAALgADCgEJAgAAAA==.Azuth:BAAALgADCgMJAwAAAA==.',
Ba='Baaloo:BAAALgAECgEJAQABLgAECgUJCwAQAAAAAA==.Bachren:BAAALgAECgYJCgAAAA==.Badil:BAAALgADCgIJAgAAAA==.Baitken:BAABLgAECn8ZAAIRAAcJmx21FQASAgARAAcJmx21FQASAgABLgAECgcJGwACAPkYAA==.Batharel:BAABLgAECn8lAAISAAcJsBlXNwCsAQASAAcJsBlXNwCsAQAAAA==.',
Bd='Bdrone:BAAALgADCgYJCAAAAA==.',
Be='Bearen:BAABLgAECn8lAAITAAgJQQpCDgBaAQATAAgJQQpCDgBaAQAAAA==.Beckett:BAAALgAECgUJBQABLgAECggJJQARAGAeAA==.Bedazzle:BAAALgADCgcJBwABLgAFFAYJHwAFALIcAQ==.Beefo:BAAALgADCgUJBAAAAA==.Beemz:BAAALgAECgcJEwAAAA==.Beertrain:BAABLgAECn8tAAIKAAkJABcfHwBKAgAKAAkJABcfHwBKAgAAAA==.Beesechurger:BAABLgAECn8iAAIUAAgJZBx7LQAhAgAUAAgJZBx7LQAhAgAAAA==.Bekindrewind:BAABLgAECn8YAAIIAAgJvBaGIAC8AQAIAAgJvBaGIAC8AQAAAA==.Belladonia:BAAALgADCgcJBwABLgAECgkJNgADALIWAA==.Belladue:BAAALgADCgMJBgAAAA==.Bellezza:BAABLgAECn82AAIDAAkJshadGAA5AgADAAkJshadGAA5AgAAAA==.Bex:BAAALgADCgEJAQAAAA==.',
Bh='Bheef:BAAALgADCgMJAwAAAA==.',
Bi='Bigdisc:BAAALgADCgIJAgABLgAECgMJAwAQAAAAAA==.Bigdumbcatqt:BAABLgAECn8pAAIPAAkJ6CYVAACEAwAPAAkJ6CYVAACEAwAAAA==.Bignjuicy:BAAALgAECgcJBwAAAA==.',
Bl='Blinkk:BAAALgADCgEJAgABLgADCgMJAwAQAAAAAA==.Bloodeagle:BAAALgADCgcJBwAAAA==.Bloodshhot:BAABLgAECn8zAAMSAAkJfRUMIgANAgASAAgJFRgMIgANAgAVAAEJVANzjgAsAAAAAA==.Bloodthorne:BAAALgADCgUJBQAAAA==.Bloomtoob:BAAALgAECgMJAwAAAA==.Bludgen:BAAALgAECgMJBAABLgAECggJIAAOANEeAA==.',
Bo='Bobitt:BAABLgAECn8WAAIHAAYJLBqnCABwAQAHAAYJLBqnCABwAQAAAA==.Boddyknocker:BAABLgAECn8WAAIHAAgJSAweDAAvAQAHAAgJSAweDAAvAQAAAA==.Boinkusan:BAABLgAECn8rAAIWAAkJYSKqBAARAwAWAAkJYSKqBAARAwAAAA==.Bolthar:BAABLgAECn8WAAIBAAgJxA57fwAkAQABAAgJxA57fwAkAQAAAA==.Bonkler:BAABLgAECn8hAAMHAAgJ4RpSEgC5AQAGAAgJtBb1NQDBAQAHAAYJyhlSEgC5AQAAAA==.Boombox:BAAALgAECgYJDQAAAA==.Boomwand:BAAALgAECgUJCwABLgAECggJJQARAGAeAA==.Boonerichard:BAAALgAECgUJEAAAAA==.Bootysweatz:BAAALgADCgcJCQAAAA==.Bouchewager:BAAALgADCgcJDgAAAA==.',
Br='Braina:BAAALgAECgcJDwAAAA==.Braver:BAACLgAFFH8RAAMXAAcJCA1RBACHAQAXAAYJbAxRBACHAQAVAAUJtgmXEQAgAQAuAAQKfzIAAxUACQnmHyIJAA8DABUACQnKHyIJAA8DABcACAmLE9gOAPsBAAAA.Braverwar:BAAALgAECgYJDAABLgAFFAcJEQAXAAgNAA==.Brayedine:BAABLgAECn8VAAIUAAgJgwUNigAoAQAUAAgJgwUNigAoAQAAAA==.Break:BAACLgAFFH8XAAIBAAgJlSBZAADfAgABAAgJlSBZAADfAgAuAAQKfyQAAgEACQlTJqoAAIMDAAEACQlTJqoAAIMDAAEuAAUUCAkXAAEAlSAA.Breekachu:BAAALgADCgYJBgAAAA==.Brodin:BAAALgAECgEJAQAAAA==.Brohymn:BAAALgADCgEJAQAAAA==.Bromaldehyde:BAAALgADCgIJAgAAAA==.Brooké:BAAALgADCgEJAQAAAA==.Bruj:BAAALgAECgQJBAAAAA==.',
Bu='Bubblebutt:BAAALgADCgEJAQAAAA==.Bubbledis:BAAALgAECgQJDAABLgAECgcJFgAYAJwPAA==.Bubblekush:BAAALgADCgcJBwAAAA==.Bullfury:BAAALgADCgEJAQAAAA==.',
['Bù']='Bùbbles:BAAALgAECgUJDAAAAA==.',
Ca='Cadelsaya:BAABLgAECn81AAMRAAkJOhPKGgDhAQARAAkJOhPKGgDhAQABAAIJHAIgKwFLAAAAAA==.Caletha:BAABLgAECn8WAAMFAAYJSRsZKQCpAQAFAAYJ5RgZKQCpAQAOAAUJRBemIgB/AQAAAA==.Calimaria:BAAALgAECgEJAQAAAA==.Calixte:BAAALgAECgYJCgAAAA==.Cammandzar:BAAALgAECgYJCQABLgAECgUJBQAQAAAAAA==.Canman:BAAALgAECgQJCgAAAA==.Cardeller:BAAALgADCgUJCAAAAA==.Cassei:BAACLgAFFH8KAAIRAAQJMxPLFQAoAQARAAQJMxPLFQAoAQAuAAQKf0oAAxEACAkCI6UIALwCABEACAkCI6UIALwCAAEABgnRDWGnAN4AAAAA.',
Ce='Celenia:BAAALgAECgUJEgAAAA==.Celorious:BAAALgAFFAIJAgAAAA==.',
Ch='Chainari:BAAALgAECgYJDwAAAA==.Chassis:BAAALgAECgQJBAABLgAECgYJFwACAKAVAA==.Chawìzawd:BAAALgADCgYJBgAAAA==.Chee:BAAALgAECgEJAgAAAA==.Cheechychong:BAAALgAECgEJAQAAAA==.Cheeksdakota:BAAALgADCgYJBgAAAA==.Cheetopaly:BAABLgAECn8XAAMRAAgJ2xuOSwBKAQARAAYJWRqOSwBKAQABAAcJFArhrADWAAAAAA==.Cherrycrush:BAAALgAECgMJAwAAAA==.Chopsuey:BAAALgADCgEJAQAAAA==.Chummy:BAACLgAFFH8HAAIZAAMJrwqCIADJAAAZAAMJrwqCIADJAAAuAAQKfx0AAhkACQnLEPAVAMoBABkACQnLEPAVAMoBAAAA.Chìgusa:BAABLgAECn8sAAMFAAkJ1BXFHgDpAQAFAAkJ1BXFHgDpAQAOAAEJmAF7YQAWAAAAAA==.',
Ci='Cigarette:BAABLgAECn8dAAMDAAYJkw62TQAQAQADAAYJkw62TQAQAQAZAAIJ8QuXVgBdAAAAAA==.Cilenzer:BAAALgAECgQJBgABLgAECgYJGwAZAK4QAA==.Cinadra:BAAALgAECgQJBAAAAA==.Circa:BAAALgADCgUJBwAAAA==.',
Cl='Clumonk:BAABLgAECn8cAAIYAAgJoxv1EADvAQAYAAgJoxv1EADvAQAAAA==.',
Co='Convoke:BAACLgAFFH8FAAIDAAIJrBQJOACOAAADAAIJrBQJOACOAAAuAAQKfxQAAgMABwm+JLQMANcCAAMABwm+JLQMANcCAAEuAAUUBgkfAAUAshwA.Coosar:BAAALgAECgYJCAAAAA==.Coose:BAAALgAECgYJBwABLgAECgcJCgAQAAAAAA==.Coosedaplug:BAAALgADCgEJAQABLgAECgcJCgAQAAAAAA==.Coosey:BAAALgAECgcJCgAAAA==.Cooseyloosey:BAAALgAECgYJBwABLgAECgcJCgAQAAAAAA==.Coosicle:BAAALgAECgIJAgABLgAECgcJCgAQAAAAAA==.Coredron:BAAALgAECgMJBAAAAA==.Corellon:BAABLgAECn8nAAIBAAgJ0g/yXgBpAQABAAgJ0g/yXgBpAQAAAA==.Corinth:BAABLgAECn8qAAIaAAkJ1hsYAQB9AgAaAAkJ1hsYAQB9AgAAAA==.',
Cr='Cratoz:BAAALgAECggJCwAAAA==.Craylic:BAAALgADCgkJDgAAAA==.Creepi:BAAALgAECgUJDgAAAA==.Criah:BAAALgADCggJCQAAAA==.Crixhs:BAAALgADCgUJBQAAAA==.Crossgideon:BAABLgAECn8iAAMbAAgJhhPmBwClAQAbAAgJhhPmBwClAQAEAAcJBAsEdQDkAAAAAA==.Crosstero:BAAALgADCgYJBgAAAA==.Crossword:BAAALgADCgcJBwAAAA==.Croswind:BAAALgADCgUJBQABLgAECggJIgAbAIYTAA==.',
Cu='Curandero:BAAALgADCggJFQABLgAECgQJCgAQAAAAAA==.Currah:BAAALgAECgEJAQAAAA==.',
Cy='Cyndrine:BAACLgAFFH8HAAIEAAMJdwI6TgCmAAAEAAMJdwI6TgCmAAAuAAQKfzAAAhsACQlxJUUAAFYDABsACQlxJUUAAFYDAAAA.Cynex:BAAALgAECgcJBwAAAA==.Cyrani:BAAALgADCgcJBwAAAA==.Cyrcyn:BAAALgAECgkJCQAAAA==.',
Da='Dadipps:BAABLgAECn8iAAIcAAgJ1SGiCADdAgAcAAgJ1SGiCADdAgAAAA==.Daggumit:BAAALgADCgYJDAAAAA==.Dagnei:BAAALgAECgQJBQAAAA==.Daltina:BAAALgAECgYJDAAAAA==.Dannyboone:BAAALgAECgIJAgAAAA==.Darg:BAABLgAECn8jAAMdAAcJxR6aCwD/AQAdAAcJxR6aCwD/AQAKAAMJORUg5gC0AAAAAA==.Daurgoth:BAAALgADCgEJAQABLgADCgcJBwAQAAAAAA==.',
Dd='Ddream:BAAALgADCgMJAwAAAA==.',
De='Deathpuma:BAABLgAECn8YAAIdAAgJZhkdDwDDAQAdAAgJZhkdDwDDAQAAAA==.Deathrowe:BAABLgAECn8wAAIKAAgJQyCXGgBkAgAKAAgJQyCXGgBkAgAAAA==.Deelyte:BAAALgAECgQJCAAAAA==.Deezenuts:BAAALgAECgEJAQAAAA==.Delorayne:BAAALgADCggJFwAAAA==.Demonic:BAAALgAECgEJAQAAAA==.Demonponii:BAAALgAECggJCwAAAA==.Demonvann:BAAALgADCgkJHAAAAA==.Denouncer:BAABLgAECn8lAAMRAAgJYB67FgAIAgARAAcJHh67FgAIAgABAAYJjxKeoADqAAAAAA==.Deralth:BAAALgAECgMJAwAAAA==.Derca:BAAALgAECgUJEwAAAA==.Dercadin:BAAALgADCggJFAAAAA==.Dethman:BAAALgAECgQJBwAAAA==.Devoider:BAAALgAECgIJAgAAAA==.',
Di='Diddyknight:BAACLgAFFH8JAAIdAAQJchKyEQD+AAAdAAQJchKyEQD+AAAuAAQKfyUAAx0ACAmQEZIWAKwBAB0ACAmQEZIWAKwBAAoAAwmABnHsAF4AAAAA.Diddyrox:BAAALgADCgkJCAABLgAECggJHAAdADkdAA==.Dienne:BAEALgAECggJEgABLgAECgkJKgAWANUYAA==.Dietunicorn:BAAALgAECgUJBQABLgAFFAIJBQAFAGcGAA==.Diminish:BAAALgAECgQJCAABLgAECgcJCgAQAAAAAA==.Diminutive:BAAALgADCgEJAQAAAA==.Dinarra:BAAALgAECgEJAQAAAA==.Diosdelaluna:BAAALgAECgEJAgAAAA==.Dipity:BAAALgADCgYJBgAAAA==.Discobirb:BAABLgAECn8sAAMGAAkJuRnTJwD/AQAGAAgJyxfTJwD/AQAHAAMJGB1gGQCgAAAAAA==.',
Do='Docdrood:BAAALgAECgEJAQAAAA==.Doctotems:BAAALgAECgQJAwAAAA==.Dohdag:BAAALgADCgEJAQAAAA==.Dokkyun:BAAALgADCgEJBAAAAA==.Donlazul:BAABLgAECn8dAAMcAAkJ4BkhHwAlAgAcAAkJ4BkhHwAlAgAeAAUJBg6BRwC9AAAAAA==.Dorff:BAABLgAECn8sAAMHAAgJLxQPFQCiAQAHAAYJjBUPFQCiAQAGAAgJTxPlPgCiAQAAAA==.Dotlotto:BAABLgAECn8hAAIHAAgJrxn6AwD8AQAHAAgJrxn6AwD8AQAAAA==.',
Dr='Draconoth:BAABLgAECn8gAAIKAAYJKBCzfwAaAQAKAAYJKBCzfwAaAQAAAA==.Dragonare:BAAALgAECgYJBgABLgAECggJHAAdADkdAA==.Dragonir:BAAALgAECgQJDAABLgAECggJIwABAJ8cAA==.Dranddrand:BAABLgAECn8XAAICAAkJ5Bp4EwB1AgACAAkJ5Bp4EwB1AgAAAA==.Drandsdemise:BAAALgAECgcJBwAAAA==.Dreadborn:BAAALgADCgYJCAAAAA==.Dreadform:BAAALgAECgEJAQAAAA==.Drizit:BAAALgAECgQJBQAAAA==.Drunkardd:BAAALgADCgYJBgAAAA==.',
Du='Dumbbear:BAAALgADCgcJCgAAAA==.Dungard:BAAALgADCgcJBwABLgAECgkJNQARADoTAA==.Dunstird:BAABLgAFFH8HAAMKAAQJlRewSAAmAQAKAAMJ/RuwSAAmAQAfAAEJXQriEQBEAAAAAA==.',
['Dè']='Dèadèyè:BAAALgADCgEJAQAAAA==.',
Ea='Earthkorra:BAAALgADCgEJAQAAAA==.Eatmorechkn:BAABLgAECn8oAAIBAAkJvRUYJgAjAgABAAkJvRUYJgAjAgAAAA==.',
Ed='Edgerunners:BAAALgAECgcJBwAAAA==.Edgli:BAAALgAECgQJBAAAAA==.Edlania:BAAALgAECgEJAQAAAA==.',
Ee='Eellonwy:BAAALgAECgMJBwAAAA==.Eemerald:BAAALgAECgUJEAAAAA==.',
Eg='Egna:BAABLgAECn8vAAIeAAkJmxF9HQCgAQAeAAkJmxF9HQCgAQAAAA==.',
El='Eldiablo:BAABLgAECn81AAIKAAkJpiFTDgC+AgAKAAkJpiFTDgC+AgAAAA==.Elfshots:BAAALgADCgQJBAABLgAECgcJFgAYAJwPAA==.Elizaa:BAABLgAECn8kAAMcAAgJbAlpXwAOAQAcAAcJcwdpXwAOAQAeAAcJ8gf8QADWAAAAAA==.Ellemeno:BAAALgAECgUJBQAAAA==.Eloria:BAAALgADCgIJAgAAAA==.',
Em='Emmadar:BAAALgADCgkJGwABLgAECgkJNQAGAL0YAA==.',
En='Enhai:BAAALgADCgMJAwAAAA==.Ennoa:BAAALgAECgUJBAAAAA==.',
Er='Eric:BAAALgAECgYJCQAAAA==.Erinn:BAAALgADCggJDQAAAA==.Erioch:BAAALgAECgEJAQAAAA==.',
Et='Etoya:BAAALgAECgMJAwAAAA==.',
Ex='Execute:BAAALgADCgYJBwAAAA==.',
Ez='Ezykeil:BAAALgADCgYJBgAAAA==.',
Fe='Feelinbetter:BAAALgAECgIJBwAAAA==.Felicía:BAAALgAECgMJAwAAAA==.Fenrigaar:BAABLgAECn8cAAIZAAcJlBZFIwBUAQAZAAcJlBZFIwBUAQAAAA==.',
Fi='Fillin:BAAALgAECgQJCgAAAA==.Filô:BAACLgAFFH8OAAINAAUJAA8TEAA4AQANAAUJAA8TEAA4AQAuAAQKfykAAg0ACQm4IhsHAJwCAA0ACQm4IhsHAJwCAAAA.',
Fj='Fjörd:BAAALgAECgEJBAAAAA==.',
Fl='Flanker:BAAALgAECgUJBQABLgAECggJIgAUAGQcAA==.Flashbang:BAAALgAECgcJCAABLgAECgkJKQAEAJcSAA==.Flasherdemon:BAAALgAECgYJBgAAAA==.Flashoblight:BAAALgADCgYJDAABLgADCgkJDgAQAAAAAA==.',
Fo='Forsakenly:BAABLgAECn8uAAISAAkJdRbIGgA3AgASAAkJdRbIGgA3AgAAAA==.',
Fr='Frasti:BAAALgAECgQJCgAAAA==.Freshstart:BAAALgAECgYJCQAAAA==.Frostmage:BAABLgAECn81AAIUAAkJch1GFwCVAgAUAAkJch1GFwCVAgAAAA==.Frstbite:BAAALgADCgYJBgAAAA==.',
Fu='Fuegoblazeit:BAAALgAECgIJBAAAAA==.Fuhsrodah:BAAALgADCgEJAgAAAA==.Fulgure:BAABLgAECn8qAAIeAAkJ7RpfDgA5AgAeAAkJ7RpfDgA5AgAAAA==.Furbucket:BAABLgAECn8eAAMZAAkJEwmNLAAXAQAZAAgJ6weNLAAXAQADAAUJqgnmkQCsAAAAAA==.Futon:BAAALgAECgQJBAAAAA==.Futonhunts:BAABLgAECn8yAAMSAAkJ2SAICQADAwASAAkJ2SAICQADAwAXAAUJHA/XJgATAQAAAA==.',
Fy='Fylerw:BAAALgAECggJEQAAAA==.',
['Få']='Fåe:BAAALgAECgMJBQAAAA==.',
Ga='Gagoogamesh:BAABLgAECn8oAAQKAAkJ3RHiPADIAQAKAAkJZRDiPADIAQAfAAkJ7AtgBwCJAQAdAAcJXAXvKwCmAAAAAA==.Gailyn:BAAALgAECgQJBAAAAA==.Galaxyshot:BAAALgADCgcJDAAAAA==.Garhiakitten:BAAALgADCgkJCQAAAA==.',
Ge='Gendershift:BAAALgADCgQJBAAAAA==.Getpsalm:BAAALgAECgkJBwAAAA==.',
Gh='Ghimpy:BAAALgAECgQJCgAAAA==.Ghostrideher:BAABLgAECn8lAAISAAkJMR4ZEgB4AgASAAkJMR4ZEgB4AgAAAA==.',
Gi='Gigadad:BAAALgAECgcJDAAAAA==.Gigafather:BAAALgAECggJDAAAAA==.',
Gl='Glurpglurp:BAAALgADCgEJAQAAAA==.',
Go='Goochkiss:BAAALgAECgMJAwAAAA==.Goyahokasinj:BAAALgADCgcJBwAAAA==.',
Gr='Griannee:BAABLgAECn8jAAIgAAgJ4BniDQDjAQAgAAgJ4BniDQDjAQAAAA==.Grimborn:BAAALgAECgIJAgAAAA==.Gripmedaddy:BAAALgADCgEJAQABLgAECgkJLAAWAPQYAA==.Grisdrips:BAAALgAECgQJBQAAAA==.Grislix:BAABLgAECn85AAMGAAkJeBeSHwApAgAGAAkJeBeSHwApAgAHAAEJjgX6NAAfAAABLgAECgQJBQAQAAAAAA==.Grismistea:BAAALgADCgkJCgABLgAECgQJBQAQAAAAAA==.Gryffin:BAABLgAECn8rAAIUAAkJPg8YSQC9AQAUAAkJPg8YSQC9AQAAAA==.',
Gu='Gurrth:BAAALgADCgMJAwAAAA==.',
['Gâ']='Gânk:BAABLgAECn8rAAMhAAkJmQsOFABnAQAhAAkJmQsOFABnAQAiAAIJmQJWnQBKAAAAAA==.',
['Gå']='Gåladriel:BAAALgAECgEJAQAAAA==.',
Ha='Hael:BAAALgAECgEJAQAAAA==.Halar:BAABLgAECn8VAAIDAAgJJg9rTwAKAQADAAgJJg9rTwAKAQAAAA==.Hammaford:BAAALgADCgMJAwAAAA==.Happiness:BAAALgAECgcJCgAAAA==.Hardknockers:BAABLgAECn8VAAIiAAYJEwtXPwD1AAAiAAYJEwtXPwD1AAAAAA==.Hargyll:BAAALgAECgcJDwAAAA==.',
He='Heavensbliss:BAAALgAECgMJAwABLgAECgkJNQAUAHIdAA==.Heavychevy:BAABLgAECn8XAAMiAAgJ6xMvKQBlAQAiAAcJSxQvKQBlAQAhAAEJqxFcTgAzAAAAAA==.Hellbentx:BAAALgAECgcJBwAAAA==.Heriel:BAAALgAECgQJBAABLgAECggJIwABAJ8cAA==.',
Hi='Hildoehealz:BAAALgAECgQJBAAAAA==.Hippyhunter:BAAALgAECgIJAwAAAA==.',
Ho='Hokes:BAACLgAFFH8FAAIUAAIJ8A1kdACgAAAUAAIJ8A1kdACgAAAuAAQKfxQAAhQABwnKHOBLALUBABQABwnKHOBLALUBAAEuAAUUAwkGAAMA4QsA.Hole:BAAALgADCgMJAwAAAA==.Homgar:BAAALgADCgYJBwAAAA==.Hoori:BAABLgAFFH8TAAIjAAkJ5CMPAAA6AwAjAAkJ5CMPAAA6AwAAAA==.',
Hu='Hughhoofner:BAAALgAECgUJBgAAAA==.Humphrees:BAABLgAECn81AAMkAAkJ2xOFDwDlAQAkAAkJ2xOFDwDlAQAMAAEJFwaYIQAqAAAAAA==.Huraji:BAAALgAFFAIJAgABLgAFFAUJEwAOAIEYAA==.',
Hy='Hydroheals:BAAALgAECgEJAQAAAA==.',
['Hà']='Hàtos:BAACLgAFFH8FAAIUAAIJVQiffwCNAAAUAAIJVQiffwCNAAAuAAQKfy4AAhQACQkYGegmAD4CABQACQkYGegmAD4CAAAA.Hàtoz:BAAALgAECgcJAwAAAA==.',
Ia='Ianisa:BAAALgAECgEJAQAAAA==.',
Id='Idot:BAAALgADCgUJBQABLgAECggJHwAgADMLAA==.',
Ii='Iironrod:BAAALgADCgcJDgAAAA==.',
Il='Illran:BAAALgAECgEJAQAAAA==.',
Im='Impawsum:BAAALgADCgUJBwAAAA==.',
In='Invissibill:BAABLgAECn8kAAIlAAgJngcGCgAnAQAlAAgJngcGCgAnAQAAAA==.',
Ir='Ironbark:BAAALgADCggJGAAAAA==.',
Iv='Ivanã:BAABLgAECn8gAAIbAAcJ4xu8BgDNAQAbAAcJ4xu8BgDNAQAAAA==.',
Iz='Izax:BAABLgAECn8mAAIGAAgJDQ7bTAB1AQAGAAgJDQ7bTAB1AQAAAA==.',
Ja='Jamestown:BAAALgADCgcJBwAAAA==.Janebquick:BAAALgAECgUJBgAAAA==.',
Je='Jelkal:BAAALgAECgkJEgAAAA==.Jemstone:BAAALgADCgYJBgAAAA==.',
Jj='Jjl:BAABLgAFFH8IAAIKAAYJVyXAowB+AAAKAAYJVyXAowB+AAAAAA==.',
Jo='Johnnylingo:BAAALgAECgEJAQAAAA==.Johnwarcratf:BAAALgAECgYJDAAAAA==.Jorim:BAAALgADCgUJBQAAAA==.',
Ju='Jupitus:BAABLgAECn8hAAIBAAgJfRaMOADYAQABAAgJfRaMOADYAQAAAA==.Juícewrld:BAAALgAECgQJBgAAAA==.',
['Jå']='Jåhkøtå:BAAALgAECgEJAQAAAA==.',
Ka='Kaboomkablow:BAAALgAECgQJBAABLgAECgcJFgAYAJwPAA==.Kaerou:BAAALgADCggJCAAAAA==.Kaosz:BAAALgADCgYJBgAAAA==.Karma:BAABLgAECn8dAAIYAAgJGyJ9BwCNAgAYAAgJGyJ9BwCNAgAAAA==.Katalania:BAAALgAECgYJBgAAAA==.Katalanii:BAABLgAECn8ZAAIDAAcJvAndXwDRAAADAAcJvAndXwDRAAAAAA==.Kathtaer:BAAALgADCggJDQAAAA==.Katja:BAABLgAECn8YAAIGAAgJbRmlKQBqAgAGAAgJbRmlKQBqAgAAAA==.',
Ke='Kegna:BAAALgADCgkJCQAAAA==.Keiwhenua:BAABLgAECn8gAAMDAAgJZw4KQQBEAQADAAgJZw4KQQBEAQAZAAUJaApQQgCsAAAAAA==.Keled:BAAALgAECgYJDgAAAA==.Kelinn:BAAALgAECgQJCwAAAA==.Kelle:BAAALgAECggJDgAAAA==.Kelzier:BAAALgAECgUJCAABLgAECggJIwABAJ8cAA==.Kenthel:BAABLgAECn8XAAMkAAYJTBgPHABaAQAkAAUJdRkPHABaAQAMAAEJfhLUHAA+AAAAAA==.Kenthels:BAABLgAECn8VAAMOAAYJuRGbKAAuAQAOAAYJuRGbKAAuAQANAAEJYA8GYQA0AAABLgAECgYJFwAkAEwYAA==.Kezt:BAAALgADCgEJAQAAAA==.',
Kh='Khaleesi:BAAALgAECgkJCAAAAA==.Khalena:BAAALgADCgUJBwAAAA==.',
Ki='Kiiya:BAAALgAECgIJAgAAAA==.Kik:BAAALgAECgEJAQAAAA==.Killerchop:BAABLgAECn8bAAMaAAgJChnhBADvAQAaAAcJ8BjhBADvAQAUAAcJKhMifADZAQAAAA==.Kiplander:BAABLgAECn8bAAIZAAYJrhCbMAAAAQAZAAYJrhCbMAAAAQAAAA==.Kithforge:BAAALgADCgEJAQAAAA==.Kittytree:BAAALgADCgQJBAAAAA==.',
Ko='Kohii:BAAALgAECgIJAgAAAA==.Kongy:BAAALgADCgIJAgAAAA==.Korry:BAAALgAECgUJDgAAAA==.Kortanis:BAAALgAECgQJBAAAAA==.Korzaz:BAABLgAECn8YAAIJAAcJpwxlCgAxAQAJAAcJpwxlCgAxAQAAAA==.Kosiicek:BAAALgAECgEJAQAAAA==.Kotala:BAAALgAECgQJBAAAAA==.',
Kr='Krakìn:BAAALgAECgUJEwAAAA==.Krelanllan:BAAALgADCgkJDQAAAA==.Krilliz:BAABLgAECn8UAAIgAAcJvQ9oKwBsAQAgAAcJvQ9oKwBsAQAAAA==.Krocodile:BAAALgAECgQJCQAAAA==.',
Ku='Kushage:BAAALgADCggJEAAAAA==.',
Ky='Kyndarra:BAAALgADCgcJBwABLgAECgkJKwADAO0QAA==.Kynlea:BAAALgADCgMJAwAAAA==.Kyumii:BAAALgADCgcJBwAAAA==.',
['Kì']='Kìla:BAAALgAECgEJAQABLgAECgkJLwABAKEkAA==.',
La='Landissa:BAABLgAECn8vAAIkAAkJ0RruCABLAgAkAAkJ0RruCABLAgAAAA==.Lanigosa:BAAALgADCggJBwAAAA==.Lanno:BAAALgADCgUJBgAAAA==.Laquandrae:BAABLgAECn8bAAIBAAYJGiBhQgC2AQABAAYJGiBhQgC2AQAAAA==.Larryholmes:BAABLgAECn8WAAIYAAcJnA/3LQB0AQAYAAcJnA/3LQB0AQAAAA==.Lasting:BAAALgADCgYJCAAAAA==.Lathmaria:BAAALgADCgEJAQAAAA==.',
Le='Leche:BAAALgAECgUJCQAAAA==.Leenaa:BAABLgAECn8rAAIDAAkJ7RBIJQDcAQADAAkJ7RBIJQDcAQAAAA==.Leesi:BAAALgADCgEJAQAAAA==.Lerash:BAAALgADCgIJAgAAAA==.',
Li='Liankaima:BAAALgADCgUJBQAAAA==.Lightninfury:BAAALgAECgUJBwAAAA==.Lihan:BAABLgAECn8XAAIiAAgJCxJVJQB9AQAiAAgJCxJVJQB9AQAAAA==.Lilieth:BAAALgADCgIJAgAAAA==.Lily:BAABLgAECn8vAAIKAAkJQRqXGQBpAgAKAAkJQRqXGQBpAgAAAA==.Livelyfist:BAABLgAECn8gAAIWAAcJFBzJFQD6AQAWAAcJFBzJFQD6AQAAAA==.Livelywilds:BAAALgADCgYJBgAAAA==.Livvmore:BAAALgADCgEJAQAAAA==.',
Lo='Locki:BAAALgADCgcJBwAAAA==.Loosenut:BAAALgAECgEJAQAAAA==.Lortelle:BAAALgAECgQJBAABLgAECggJHAAdADkdAA==.Losic:BAAALgADCgcJCwAAAA==.Lotzofblood:BAAALgAECgcJDQAAAA==.Loverocket:BAABLgAECn8qAAIPAAkJsx1AAwCZAgAPAAkJsx1AAwCZAgAAAA==.',
Lu='Lugosi:BAAALgADCgcJDQABLgAECgkJNQAEAL0aAA==.Lullers:BAAALgAECgMJBgAAAA==.Luna:BAAALgAECgYJCwABLgAFFAIJAgAQAAAAAA==.Lunastorm:BAAALgADCggJFAAAAA==.Luroe:BAAALgADCgkJCQAAAA==.',
Ly='Lyralina:BAEALgADCgQJBAABLgAECgkJKgAWANUYAA==.Lysergicon:BAAALgADCgEJAQAAAA==.Lyshia:BAABLgAECn8oAAIUAAkJqiF/EQC8AgAUAAkJqiF/EQC8AgAAAA==.Lyshion:BAAALgADCgYJBgAAAA==.',
['Lì']='Lìch:BAAALgADCgIJAgAAAA==.',
['Lí']='Líghthand:BAACLgAFFH8IAAIPAAMJbyPIAgA4AQAPAAMJbyPIAgA4AQAuAAQKfyUAAw8ACQk4IagBADYDAA8ACQk4IagBADYDAAEAAQm/DnssATcAAAAA.',
['Lý']='Lýght:BAAALgADCggJDAAAAA==.',
Ma='Magdaanii:BAAALgAECgUJCAAAAA==.Magedown:BAABLgAECn8jAAIUAAkJZhSWNAAEAgAUAAkJZhSWNAAEAgAAAA==.Magician:BAAALgAECgQJBwABLgAECgcJFgAYAJwPAA==.Magicmallet:BAABLgAECn8dAAIRAAkJwiOIAwA6AwARAAkJwiOIAwA6AwAAAA==.Manwell:BAAALgAECgMJAwAAAA==.Martinell:BAAALgADCgYJDAAAAA==.Matap:BAAALgADCgkJGwAAAA==.Mataw:BAABLgAECn8lAAMiAAgJCR6VEAAqAgAiAAgJCR6VEAAqAgAhAAYJ3BCyFgBHAQAAAA==.Mattdemon:BAABLgAECn81AAIEAAkJvRquGgAxAgAEAAkJvRquGgAxAgAAAA==.Maulotov:BAAALgAECgYJBgAAAA==.',
Me='Mehruna:BAAALgADCgEJAgAAAA==.Meliany:BAAALgADCgYJCQAAAA==.Meliowar:BAAALgADCgQJBAAAAA==.Melkdudd:BAAALgAECgcJBwAAAA==.Mephmonster:BAAALgADCgEJAQAAAA==.Merrciless:BAAALgAECgYJCAAAAA==.Meríin:BAAALgADCggJDgAAAA==.Meteori:BAAALgADCgEJAQAAAA==.Metroboomkin:BAAALgAECgIJAgAAAA==.',
Mi='Miksi:BAAALgADCgcJFgABLgAECgUJCwAQAAAAAA==.Miradele:BAAALgAECgcJEgAAAA==.Miraxx:BAAALgAECgQJCQAAAA==.Misscleö:BAABLgAECn8lAAIBAAkJ7hFaPQDGAQABAAkJ7hFaPQDGAQAAAA==.Mistybrew:BAAALgADCgMJAwAAAA==.Miyoshi:BAABLgAECn8dAAIkAAgJIghiHgBEAQAkAAgJIghiHgBEAQAAAA==.Mizrhi:BAAALgAECgMJBAAAAA==.',
Mo='Monthy:BAAALgADCgUJCAAAAA==.Moonkey:BAAALgAECgIJAgAAAA==.Moosakka:BAABLgAECn8rAAMWAAkJCxemDgBPAgAWAAkJCxemDgBPAgAYAAgJERM+HAB8AQAAAA==.Moosedluffy:BAAALgAECgYJDgAAAA==.Moosesiah:BAAALgAECgcJEQAAAA==.Moovinthru:BAAALgAECgUJCwAAAA==.Moraxes:BAABLgAECn8sAAMjAAkJoB24BACTAgAjAAkJoB24BACTAgAhAAUJORXPIgDuAAAAAA==.Mordenkainen:BAABLgAECn8VAAMHAAYJSAeiHwBrAAAGAAYJ7AZBkwDWAAAHAAQJNAaiHwBrAAAAAA==.Morenor:BAABLgAECn8VAAINAAYJXAaFPQAIAQANAAYJXAaFPQAIAQAAAA==.Morphidmage:BAABLgAECn80AAIUAAkJVw/sQQDUAQAUAAkJVw/sQQDUAQAAAA==.Mortetdabo:BAAALgAECgYJBwAAAA==.Motoko:BAAALgAECgMJAwAAAA==.Motolei:BAAALgADCggJDgABLgAECggJIgAbAIYTAA==.',
Mu='Muaadib:BAAALgADCgkJGgABLgAECggJIgAbAIYTAA==.',
My='Mydin:BAABLgAECn8hAAIBAAkJEhcOOwDOAQABAAkJEhcOOwDOAQAAAA==.Myordarsh:BAABLgAECn8mAAMKAAgJ2BfYOQDTAQAKAAgJ2BfYOQDTAQAdAAYJxwlxKAC8AAAAAA==.',
['Mì']='Mìsawa:BAAALgAECgUJEQAAAA==.',
Na='Nael:BAAALgAECgQJBAAAAA==.Naeleen:BAAALgADCgQJBwAAAA==.Nakai:BAAALgADCgkJGwAAAA==.Nasmage:BAAALgADCgkJCgAAAA==.',
Ne='Necromann:BAAALgADCgcJBwAAAA==.Nelfgonewild:BAAALgAECgIJAwAAAA==.Nexs:BAAALgAECgcJBwAAAA==.Nexxa:BAABLgAECn8kAAISAAgJqRbxMwC6AQASAAgJqRbxMwC6AQAAAA==.Neyrina:BAAALgADCgUJCAAAAA==.',
Ni='Nickk:BAAALgAECgkJAQAAAA==.Nightshadow:BAAALgAECgcJEwAAAA==.Niqkle:BAABLgAECn8uAAMeAAkJhBVRFQDqAQAeAAkJhBVRFQDqAQAcAAgJYAgQTQAWAQAAAA==.Nirat:BAAALgADCgEJAQAAAA==.Nishandriel:BAAALgADCgkJDwAAAA==.Nivia:BAAALgAECgYJEQABLgAFFAYJHwAFALIcAA==.',
No='Nohurtscooby:BAAALgAECgQJCQAAAA==.Normond:BAAALgADCgUJDAAAAA==.Nosiaria:BAAALgAECgEJAQAAAA==.Notadh:BAABLgAECn8TAAIEAAcJuhBYVQA1AQAEAAcJuhBYVQA1AQAAAA==.Notmeanzy:BAABLgAECn8yAAMNAAkJnCEdBADnAgANAAkJnCEdBADnAgAOAAMJQhZkOwDOAAAAAA==.',
Ns='Nstagatr:BAAALgADCgEJAQAAAA==.',
Nu='Numeroun:BAAALgAECgQJCQAAAA==.Nunbora:BAAALgAECgEJAQAAAA==.',
['Né']='Nécrömancer:BAAALgADCgIJAgAAAA==.',
['Nï']='Nïghtknïght:BAAALgAECgMJAwAAAA==.',
Oc='Occidius:BAAALgAECgUJCgAAAA==.',
Ol='Oldoriel:BAAALgADCgIJAgAAAA==.Oleanna:BAABLgAECn8fAAIYAAcJgg4MJwAqAQAYAAcJgg4MJwAqAQABLgAECgkJOAABAOcZAA==.Olehanna:BAABLgAECn84AAIBAAkJ5xk2IgA3AgABAAkJ5xk2IgA3AgAAAA==.Olendra:BAAALgAECgcJBwABLgAECgkJOAABAOcZAA==.Olestrid:BAAALgADCgkJEgABLgAECgkJOAABAOcZAA==.',
On='Onyxcaduceus:BAAALgADCgQJBAABLgADCgcJBwAQAAAAAA==.Onyxtear:BAAALgAECgQJBAAAAA==.Onyxvolt:BAAALgADCgcJBwAAAA==.',
Op='Opioid:BAABLgAECn8fAAISAAgJXBhWMADJAQASAAgJXBhWMADJAQAAAA==.Opsec:BAAALgAECgEJAgABLgAECgkJKQAEAJcSAA==.Opsèc:BAABLgAECn8pAAMEAAkJlxJCNgChAQAEAAkJFxFCNgChAQAgAAQJehUAAAAAAAAAAA==.',
Or='Orsa:BAABLgAECn8VAAIeAAcJcxQkMACfAQAeAAcJcxQkMACfAQAAAA==.',
Ot='Othon:BAAALgADCgEJAQAAAA==.',
Pe='Pebbles:BAAALgAECgIJAgABLgAECgUJDAAQAAAAAA==.Pedren:BAABLgAECn8UAAIcAAUJHhCUUgAAAQAcAAUJHhCUUgAAAQAAAA==.Perfectpal:BAABLgAECn8iAAMRAAkJnxUSIwChAQARAAkJnxUSIwChAQABAAEJ3gd/QgEuAAAAAA==.Peri:BAAALgADCgUJBQAAAA==.',
Ph='Phaeseus:BAAALgAECgUJBgAAAA==.Phexaryl:BAAALgAECgUJBgAAAA==.',
Pl='Planette:BAABLgAECn8bAAIcAAkJFxS6FwA3AgAcAAkJFxS6FwA3AgAAAA==.',
Po='Poinda:BAAALgADCgIJAgAAAA==.Poisionivy:BAAALgADCgEJAQAAAA==.Popcorners:BAABLgAECn81AAMOAAkJSB5YCACiAgAOAAkJSB5YCACiAgANAAQJWxELQQCzAAAAAA==.Popopanda:BAAALgAECgUJDwAAAA==.Poppnlok:BAAALgADCgEJAQAAAA==.Pordgio:BAABLgAECn8hAAIkAAgJ8RLPEgC6AQAkAAgJ8RLPEgC6AQAAAA==.Pozzi:BAAALgAECgQJCQAAAA==.',
Pr='Praypal:BAAALgAECgUJCQAAAA==.Problematiç:BAAALgADCgEJAQAAAA==.Proxxy:BAAALgADCgMJAwAAAA==.',
Ps='Psuedolus:BAABLgAECn8dAAIKAAgJdCLxIwAuAgAKAAgJdCLxIwAuAgAAAA==.Psålm:BAABLgAECn8ZAAINAAgJ5BBmHgB9AQANAAgJ5BBmHgB9AQAAAA==.',
Pu='Pulshadow:BAACLgAFFH8aAAINAAYJuxqoAwDXAQANAAYJuxqoAwDXAQAuAAQKfyAAAg0ACAkYJDMFAD0DAA0ACAkYJDMFAD0DAAAA.Pumah:BAAALgAECgQJCgAAAA==.Purified:BAAALgAECgIJAgABLgAFFAcJIAACAOEUAA==.',
Pw='Pweenqween:BAAALgADCgEJAQAAAA==.',
Py='Pyreska:BAAALgAECgkJDAAAAA==.Pyroklasm:BAABLgAECn8bAAIUAAcJtByGUwA9AgAUAAcJtByGUwA9AgAAAA==.',
Qt='Qthunter:BAAALgADCgkJCQABLgAECgkJHAAYAGwRAA==.Qtlocks:BAAALgADCgkJCQABLgAECgkJHAAYAGwRAA==.Qtmonk:BAABLgAECn8cAAIYAAkJbBGzFADCAQAYAAkJbBGzFADCAQAAAA==.',
Qu='Quartzecoatl:BAAALgADCgMJAwAAAA==.Quela:BAAALgAECgMJBgAAAA==.Quintcaster:BAAALgAECgQJBgAAAA==.Quirt:BAAALgAECgUJDgAAAA==.',
Ra='Raamen:BAAALgAECgUJCwAAAA==.Rabiéz:BAAALgAECgMJBAAAAA==.Radioface:BAAALgAECgEJAgAAAA==.Raellia:BAABLgAECn81AAQGAAkJvRgeNQDFAQAGAAcJ/hYeNQDFAQAmAAIJFxvNFwCGAAAHAAMJtxh9HACFAAAAAA==.Raimmey:BAAALgAECgMJBQAAAA==.Rajann:BAAALgADCgMJAwAAAA==.Rajia:BAAALgAECgYJEgABLgAECggJJwAHAP8OAA==.Rakaw:BAAALgADCgMJAwAAAA==.Ralune:BAABLgAECn8nAAIZAAgJHw9pIgBaAQAZAAgJHw9pIgBaAQAAAA==.Randomdhunte:BAAALgADCgkJDAAAAA==.Randomone:BAABLgAECn8UAAIRAAkJyQhhKAB7AQARAAkJyQhhKAB7AQAAAA==.Ranes:BAABLgAECn81AAQkAAkJgCH0BACmAgAkAAkJgCH0BACmAgAMAAQJuA/IEgDWAAAlAAEJQwfBGgApAAAAAA==.Rathmore:BAAALgAECgQJBQAAAA==.Raylavoidles:BAAALgADCgcJDgAAAA==.Rayllee:BAAALgAECgcJEAAAAA==.',
Re='Redi:BAAALgADCgYJBgAAAA==.Redxelementz:BAABLgAECn8nAAIcAAkJZCPIBAAiAwAcAAkJZCPIBAAiAwAAAA==.Relyana:BAAALgADCgEJAQAAAA==.Remena:BAABLgAECn8WAAIYAAcJERzmFwAlAgAYAAcJERzmFwAlAgAAAA==.Renasen:BAABLgAECn8XAAMhAAgJqyLrBgA7AgAhAAcJnSPrBgA7AgAiAAcJpRY5KwBZAQAAAA==.Rendiwyn:BAAALgADCgcJBwAAAA==.Reno:BAABLgAECn8iAAMRAAgJQxteEQBAAgARAAgJQxteEQBAAgABAAEJjBJlKQE4AAAAAA==.René:BAAALgADCgUJBwAAAA==.Resimetha:BAAALgADCgEJAQAAAA==.Resiretha:BAABLgAECn8XAAMGAAgJsQMBigDoAAAGAAgJsQMBigDoAAAHAAEJBQUhegAoAAAAAA==.Revelynn:BAABLgAECn8wAAMEAAkJJB6KEgBuAgAEAAkJJB6KEgBuAgAbAAEJcx3PHgBVAAAAAA==.',
Rh='Rhemedi:BAAALgAECgUJBQAAAA==.Rhico:BAAALgADCgEJAQAAAA==.Rhyin:BAAALgADCgYJBgAAAA==.',
Ri='Riolu:BAAALgAECgQJBgAAAA==.',
Rn='Rngesus:BAAALgAECgEJAQABLgAECggJNAAKACkhAA==.',
Ro='Robotmonk:BAAALgAECgcJCwABLgAFFAMJCAAPAG8jAA==.Rooxxy:BAAALgAECgcJEAAAAA==.Rotawna:BAAALgAECgYJDgAAAA==.Roxxye:BAAALgADCgEJAQABLgAECgcJEAAQAAAAAA==.',
Ru='Rumms:BAAALgAECgcJCwAAAA==.Rustybottom:BAAALgADCgEJAQAAAA==.Ruumis:BAAALgAECgQJBAAAAA==.',
Ry='Rydric:BAABLgAECn8WAAIUAAgJFyPIEwAxAwAUAAgJFyPIEwAxAwAAAA==.Ryezn:BAAALgAECgEJAQAAAA==.Ryxhal:BAAALgADCgYJBgAAAA==.Ryzur:BAAALgAECggJCAAAAA==.',
['Rï']='Rïnzlër:BAAALgAECgcJEwAAAA==.',
Sa='Saela:BAAALgAECgYJBgAAAA==.Sarac:BAABLgAECn8hAAIjAAgJuAJ3IwDKAAAjAAgJuAJ3IwDKAAAAAA==.Saratosh:BAAALgADCgEJAQAAAA==.Savira:BAAALgAECgYJDQAAAA==.',
Sc='Scaleorva:BAABLgAECn8gAAMJAAYJmQ+WCwAXAQAJAAYJmQ+WCwAXAQAIAAEJ+wgccQArAAAAAA==.',
Se='Sealmedaddy:BAAALgADCgEJAQABLgAECgkJLAAWAPQYAA==.Selfaware:BAAALgAECgYJBgABLgAECggJGAACAMgaAA==.Seraphìm:BAABLgAECn8dAAIBAAkJ3wZWawBMAQABAAkJ3wZWawBMAQAAAA==.',
Sh='Shadefu:BAAALgADCgYJBgABLgAECggJJAAaAHUOAA==.Shadyballs:BAABLgAECn8kAAQaAAgJdQ6iBABhAQAaAAcJsw+iBABhAQAUAAcJmwo1hwAuAQAnAAYJaAkuCQDDAAAAAA==.Shakypete:BAAALgAECgYJCwABLgAECgYJGwAZAK4QAA==.Shalaena:BAAALgAECgMJAwAAAA==.Shamagorn:BAAALgADCgcJBwAAAA==.Shamysosa:BAABLgAECn8gAAMeAAcJMRySGQDCAQAeAAcJMRySGQDCAQAcAAEJ6AOgpQAqAAAAAA==.Shanebentea:BAABLgAECn8pAAIiAAgJCBZSGgDMAQAiAAgJCBZSGgDMAQAAAA==.Sharpy:BAAALgAECgEJAQABLgAECggJKAAUAC8cAA==.Sharpyboi:BAAALgADCgMJAwABLgAECggJKAAUAC8cAA==.Sharpyy:BAAALgADCgYJBgABLgAECggJKAAUAC8cAA==.Shinjí:BAACLgAFFH8TAAIKAAQJMyEvGwCIAQAKAAQJMyEvGwCIAQAuAAQKfzAAAwoACAmPIsYTAJECAAoACAmPIsYTAJECAB0AAQkIAEtRAAEAAAEuAAUUBgkXAAoArR0A.Shiven:BAAALgAECgYJCQAAAA==.Shmob:BAABLgAECn8VAAIeAAYJ4Q1oMwAUAQAeAAYJ4Q1oMwAUAQAAAA==.Shnappz:BAABLgAECn8kAAMHAAYJqQ4qGQCiAAAGAAUJ5Ai6iQDoAAAHAAQJ+hEqGQCiAAAAAA==.Shockittome:BAAALgADCgUJBQAAAA==.Shroomee:BAABLgAFFH8SAAQDAAkJgwt5CQDTAQADAAcJZwp5CQDTAQAZAAQJkBoWFgAeAQALAAIJkBQrDwCKAAAAAA==.Shwillacus:BAAALgADCgkJCQAAAA==.Shwillarou:BAABLgAECn80AAIKAAkJqA5oQAC8AQAKAAkJqA5oQAC8AQAAAA==.Shwillmoon:BAAALgADCgkJEgAAAA==.Shärpy:BAABLgAECn8oAAIUAAgJLxxmLgAdAgAUAAgJLxxmLgAdAgAAAA==.',
Si='Silverstring:BAAALgAECgUJDAAAAA==.Simmi:BAAALgAECgIJAgAAAA==.Sinergee:BAABLgAECn8mAAISAAgJaBQZNAC6AQASAAgJaBQZNAC6AQAAAA==.Sinfulgold:BAAALgADCgQJBAAAAA==.Sinfulkitten:BAAALgADCggJFwAAAA==.Sinnj:BAABLgAECn8WAAIUAAcJ3gZEpAD5AAAUAAcJ3gZEpAD5AAAAAA==.Sithlörd:BAAALgAECgYJBgAAAA==.',
Sk='Skinney:BAAALgAECgIJAwAAAA==.Skinsey:BAAALgADCgcJBwAAAA==.Skycrush:BAAALgAECgQJBwAAAA==.',
Sl='Slanie:BAABLgAECn8mAAIFAAgJCxAoHQCTAQAFAAgJCxAoHQCTAQAAAA==.Slayne:BAAALgADCgEJAgAAAA==.Slingerz:BAABLgAECn82AAIjAAkJpBa+CwDjAQAjAAkJpBa+CwDjAQAAAA==.Slowmeaux:BAAALgADCgYJCgAAAA==.',
Sm='Smoky:BAABLgAECn8bAAQGAAkJZSBFOwAfAgAGAAcJMyBFOwAfAgAHAAMJPB+9LAALAQAmAAEJAACVIgBnAAAAAA==.',
Sn='Snacky:BAAALgADCgIJAgAAAA==.Sneakpastya:BAABLgAECn8hAAIkAAgJFAfVHgBAAQAkAAgJFAfVHgBAAQAAAA==.Sneakyg:BAAALgAECgEJAQABLgAECggJIwABAJ8cAA==.Snooksdk:BAAALgADCgEJAQABLgAFFAYJFwAUAAAbAA==.',
So='Solkar:BAABLgAECn8dAAIPAAgJoBIuDwB5AQAPAAgJoBIuDwB5AQAAAA==.Sollis:BAAALgAECgUJDQAAAA==.Sonastii:BAABLgAECn8fAAIeAAkJ5Bs3CwBmAgAeAAkJ5Bs3CwBmAgAAAA==.Soulbztrd:BAABLgAECn8gAAMHAAkJ/BZsGgB5AQAHAAUJIRpsGgB5AQAGAAcJCxTtaQArAQAAAA==.Soulmoss:BAAALgAECgYJBgABLgAECgYJBgAQAAAAAA==.Soulpepper:BAAALgAECgQJBAAAAA==.Soulreaper:BAAALgAECgYJBgABLgAECgYJBgAQAAAAAA==.Soulsnatcher:BAAALgAECgYJBgAAAA==.',
Sp='Spazzchel:BAAALgAECgQJCwAAAA==.Spinmedaddy:BAAALgADCgkJCgABLgAECgkJLAAWAPQYAA==.Spruce:BAAALgADCgkJGwAAAA==.',
St='Stahlman:BAABLgAECn81AAIcAAkJdhzbEAB3AgAcAAkJdhzbEAB3AgAAAA==.Stalpho:BAABLgAECn8qAAIiAAkJzRUrEAAuAgAiAAkJzRUrEAAuAgAAAA==.Starflare:BAAALgAECgQJBAABLgAECggJJwAcAB0PAA==.Starkind:BAABLgAECn8nAAIcAAgJHQ/QLwCZAQAcAAgJHQ/QLwCZAQAAAA==.Stefussy:BAAALgADCgIJAgAAAA==.Stonefist:BAABLgAECn8WAAIYAAYJ2A4JLgACAQAYAAYJ2A4JLgACAQABLgAECgcJIAAeADEcAA==.Stoutmist:BAAALgAECgEJAQAAAA==.Sturr:BAAALgAECgEJAQAAAA==.Styrke:BAAALgAECgIJAgAAAA==.',
Su='Subza:BAAALgADCgMJAwAAAA==.Sundalo:BAAALgAECgUJCAAAAA==.Supergood:BAAALgAECgYJBgAAAA==.Superjoyful:BAAALgADCgEJAQAAAA==.Supersweet:BAAALgADCgYJEQAAAA==.Sutterkain:BAAALgAECgMJBAAAAA==.',
Sw='Swagadin:BAABLgAECn8pAAIBAAkJ1yRWBwBdAwABAAkJ1yRWBwBdAwAAAA==.Swagika:BAAALgAECgUJBgABLgAECgkJKQABANckAA==.',
Sy='Syine:BAAALgADCgUJBQAAAA==.Sylee:BAABLgAFFH8KAAIWAAQJTRpBHQDOAAAWAAQJTRpBHQDOAAAAAA==.',
Ta='Tabitia:BAABLgAECn8qAAMSAAkJERM6KgDkAQASAAkJxxE6KgDkAQAXAAYJnhL+FAB4AQAAAA==.Tahra:BAAALgADCgYJBgAAAA==.Taladari:BAAALgADCgEJAQAAAA==.Taliss:BAABLgAECn8WAAIFAAcJSR84DwArAgAFAAcJSR84DwArAgAAAA==.Talonpepper:BAAALgADCgMJAwAAAA==.Tankmedaddy:BAABLgAECn8sAAMWAAkJ9BiHDABsAgAWAAkJ9BiHDABsAgAYAAEJawMEiAAoAAAAAA==.Tankopotamus:BAAALgADCgEJAQAAAA==.Tapenga:BAAALgAECgQJBAAAAA==.Tappuccino:BAAALgAECgQJCgAAAA==.Taras:BAACLgAFFH8NAAIiAAMJXyFFGgALAQAiAAMJXyFFGgALAQAuAAQKfxwAAiIACQkGIPEHACoDACIACQkGIPEHACoDAAAA.Taraxist:BAABLgAECn8rAAIHAAkJGhvzAQBtAgAHAAkJGhvzAQBtAgAAAA==.Tarcanisdk:BAABLgAECn8gAAIKAAgJqRjHOwDMAQAKAAgJqRjHOwDMAQAAAA==.Tasuma:BAAALgAECgYJDAAAAA==.Tautology:BAABLgAECn8fAAINAAgJVxhYGQCoAQANAAgJVxhYGQCoAQAAAA==.Tazdingo:BAAALgADCgEJAQAAAA==.',
Tc='Tchala:BAABLgAECn8jAAIBAAgJnxzzKQARAgABAAgJnxzzKQARAgAAAA==.Tchaumb:BAAALgAFFAEJAQAAAA==.',
Te='Tedeschi:BAAALgAECgEJAgAAAA==.Teks:BAABLgAECn8rAAIRAAkJyBwEBwDbAgARAAkJyBwEBwDbAgAAAA==.Teksakah:BAAALgADCggJCAABLgAECgkJKwARAMgcAA==.Teksara:BAAALgADCgcJBwABLgAECgkJKwARAMgcAA==.Teksbane:BAAALgADCgcJBwABLgAECgkJKwARAMgcAA==.Tekszen:BAAALgAECgEJAQABLgAECgkJKwARAMgcAA==.Tencup:BAABLgAECn8YAAICAAgJyBpvDwAIAgACAAgJyBpvDwAIAgAAAA==.Teth:BAABLgAECn8lAAMHAAgJ0RRPBgCqAQAHAAgJ0RRPBgCqAQAGAAEJuQF6FwEfAAAAAA==.Tetsuyo:BAAALgAECgUJCQAAAA==.Tevildo:BAAALgAECgEJAgAAAA==.',
Th='Thaine:BAABLgAECn82AAIBAAkJtyQpBgAQAwABAAkJtyQpBgAQAwAAAA==.Theelvira:BAAALgADCgYJBgAAAA==.Theoalthor:BAAALgAECgMJAwAAAA==.Theresis:BAAALgAECgMJBAAAAA==.Therkadin:BAAALgAECgYJDgAAAA==.Theundeadone:BAAALgAECgYJCAAAAA==.Thndrwzrd:BAAALgAECgUJEwAAAA==.Throw:BAAALgAECgMJAwAAAA==.Thrust:BAAALgADCgIJAgAAAA==.',
Ti='Ticho:BAABLgAECn8kAAIKAAkJLgahZgBPAQAKAAkJLgahZgBPAQAAAA==.Tidel:BAAALgAECgYJBwAAAA==.Tindmina:BAABLgAECn8bAAIRAAcJvBkXMgC3AQARAAcJvBkXMgC3AQAAAA==.Tinglekin:BAAALgAECgIJAwAAAA==.',
Tl='Tlo:BAAALgAECgcJDgAAAA==.Tlol:BAAALgAECgUJBwABLgAECgcJDgAQAAAAAA==.',
To='Toenails:BAAALgADCgYJBgAAAA==.Topflight:BAAALgAECgEJAQABLgAECgYJCAAQAAAAAA==.Torkkit:BAAALgAECgEJAwABLgAECgUJBgAQAAAAAA==.Torodisilis:BAAALgAECgIJAgABLgAECggJIwABAJ8cAA==.Torqit:BAAALgAECgMJBQABLgAECgUJBgAQAAAAAA==.Totemdude:BAAALgADCgEJAQAAAA==.Totemzrus:BAAALgAECgcJEgAAAA==.',
Tr='Trath:BAAALgADCgMJAwAAAA==.Trent:BAAALgADCgQJCAAAAA==.Trickette:BAAALgAECgkJCQAAAA==.Trickeye:BAAALgADCgIJAgAAAA==.',
Tw='Twicks:BAABLgAFFH8KAAQYAAUJpAzpAgB8AQAYAAUJkwjpAgB8AQAWAAQJNgKSHADWAAACAAEJfRgrQgBIAAAAAA==.',
Ud='Udderlyquiff:BAAALgAECgIJAgAAAA==.Udderlyslow:BAABLgAECn8eAAIcAAcJByGcGwA7AgAcAAcJByGcGwA7AgAAAA==.',
Ug='Uglyloser:BAAALgAECgIJAwAAAA==.',
Un='Undeez:BAAALgAECgMJAwAAAA==.Unluckyfrien:BAAALgAECgIJAgAAAA==.',
Va='Vaeshta:BAABLgAECn8gAAITAAgJ/wNPFAD5AAATAAgJ/wNPFAD5AAAAAA==.Vaku:BAAALgADCgkJDQAAAA==.Valhallarama:BAABLgAECn8YAAIcAAgJxQpSTAAZAQAcAAgJxQpSTAAZAQAAAA==.Vampy:BAABLgAECn8XAAIVAAcJuRKWDABMAQAVAAcJuRKWDABMAQAAAA==.Vannida:BAAALgAECgUJBQAAAA==.Vanìlla:BAAALgADCgEJAQAAAA==.Varya:BAAALgAECgcJDQAAAA==.Vasuvious:BAABLgAECn8iAAICAAcJDR2ZHgANAgACAAcJDR2ZHgANAgAAAA==.',
Ve='Vesstara:BAAALgADCgcJEQABLgAECgQJCQAQAAAAAA==.',
Vi='Vinago:BAAALgAECgMJAwAAAA==.',
Vo='Voidabyss:BAAALgADCgUJBQAAAA==.Voidixx:BAAALgADCggJEwAAAA==.Voodoo:BAAALgAECgYJCgAAAA==.',
Vy='Vyleta:BAAALgADCgYJBgAAAA==.Vyllian:BAABLgAECn80AAMKAAgJKSH8JgAfAgAKAAgJACD8JgAfAgAdAAgJ+A5CGABIAQAAAA==.Vyri:BAAALgAECgEJAQAAAA==.',
['Vá']='Váz:BAAALgADCgYJBgABLgAFFAMJBgADAOELAA==.',
Wa='Wangwang:BAAALgAECgUJCwAAAA==.Warlakaflaka:BAAALgAECgUJCQABLgAECggJJAAaAHUOAA==.Warlboro:BAACLgAFFH8UAAIGAAYJgA86IABbAQAGAAYJgA86IABbAQAuAAQKfyUABAYACAlwHBQfAJ0CAAYACAlwHBQfAJ0CAAcABAnvCls1AOEAACYAAQnBIB4oAFEAAAAA.',
We='Welikeweed:BAAALgAECgYJDAABLgAFFAMJBwAcAKMYAA==.',
Wh='Whale:BAABLgAECn8dAAIjAAkJ4RmEDQDCAQAjAAkJ4RmEDQDCAQAAAA==.Whine:BAAALgAECgQJBwAAAA==.',
Wi='Wibbers:BAAALgAECgEJAwAAAA==.Wicked:BAABLgAECn8XAAIBAAUJliCcbQBHAQABAAUJliCcbQBHAQABLgAECgcJCgAQAAAAAA==.Willôw:BAAALgADCgkJEQABLgAECgkJGwAFALEfAA==.Windwalker:BAABLgAECn8aAAIYAAkJ/BBMFQC7AQAYAAkJ/BBMFQC7AQAAAA==.Winkey:BAAALgADCgYJBgAAAA==.Winston:BAAALgADCgYJBwAAAA==.',
Wo='Wolfsong:BAAALgADCgMJBAABLgAECgQJBgAQAAAAAA==.Woosaah:BAAALgAECgcJBwAAAA==.',
Wr='Wreckyou:BAABLgAECn8WAAQHAAYJXA8uMgDwAAAGAAYJ/wcNqwADAQAHAAYJxgYuMgDwAAAmAAUJmw7NEQDSAAAAAA==.',
Wt='Wtfimkorgak:BAABLgAECn8qAAIFAAcJfCPICQCCAgAFAAcJfCPICQCCAgAAAA==.',
Wy='Wy:BAAALgADCgYJBgAAAA==.Wylestrean:BAABLgAECn8rAAMXAAkJ/xp1EgDQAQAXAAcJXhx1EgDQAQASAAMJWBhdpQCDAAAAAA==.',
Xa='Xandoriel:BAAALgADCgQJBAAAAA==.',
Xi='Xiaomao:BAABLgAECn8qAAQWAAcJ1RgfGADiAQAWAAcJ1RgfGADiAQAYAAMJwwdOTACDAAACAAEJcgBIiwAXAAAAAA==.',
Xy='Xyrathul:BAAALgAECgEJAgAAAA==.',
Ya='Yaric:BAAALgAECgMJBQAAAA==.',
Ye='Yeahigotmilk:BAAALgADCgUJBQAAAA==.Yeinn:BAAALgAFFAEJAQAAAA==.Yellowgoblin:BAAALgAECgIJAgAAAA==.',
Yo='Yopali:BAAALgAECgIJAwAAAA==.',
Yu='Yugiohrox:BAABLgAECn8cAAIdAAgJOR2DCwBbAgAdAAgJOR2DCwBbAgAAAA==.Yujology:BAABLgAECn8gAAIbAAgJDARhEQDiAAAbAAgJDARhEQDiAAAAAA==.',
Za='Zaolandoorss:BAAALgAECgEJAQAAAA==.',
Ze='Zel:BAAALgAECgUJEwAAAA==.Zentradei:BAAALgAECgUJCwAAAA==.Zephariel:BAAALgADCgcJBwAAAA==.Zephirothh:BAAALgAECgUJBAAAAA==.',
Zi='Zieganfuss:BAABLgAECn8dAAIUAAgJYB0AVQA5AgAUAAgJYB0AVQA5AgAAAA==.Zilly:BAAALgAECgEJAQAAAA==.Zimmy:BAAALgADCgYJBgAAAA==.',
Zo='Zoho:BAABLgAECn8XAAICAAYJoBUkLwANAQACAAYJoBUkLwANAQAAAA==.Zoomies:BAAALgADCgMJAwAAAA==.',
Zu='Zulkai:BAABLgAECn8qAAIDAAgJPhqqEwBpAgADAAgJPhqqEwBpAgAAAA==.',
Zy='Zynvar:BAAALgADCgYJBgAAAA==.',
['Zá']='Záv:BAACLgAFFH8GAAIDAAMJ4QuQLADEAAADAAMJ4QuQLADEAAAuAAQKfxgAAwMACAl2FzInABkCAAMACAl2FzInABkCACgAAglKCqsmAGcAAAAA.',
['Zä']='Zäne:BAABLgAECn8ZAAIUAAYJIBpCjQC4AQAUAAYJIBpCjQC4AQAAAA==.',
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
