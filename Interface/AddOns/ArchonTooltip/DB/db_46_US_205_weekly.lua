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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Mage-Frost','Hunter-BeastMastery','Shaman-Enhancement','Druid-Restoration','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Evoker-Devastation','Paladin-Retribution','Paladin-Holy','DemonHunter-Vengeance','Monk-Brewmaster','Hunter-Survival','Rogue-Assassination','Warrior-Fury','Warlock-Affliction','DeathKnight-Frost','Monk-Mistweaver','Mage-Fire','Paladin-Protection','Rogue-Subtlety','Evoker-Augmentation','Rogue-Outlaw','Warrior-Protection','Warrior-Arms','Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Windwalker','Evoker-Preservation','DemonHunter-Havoc','Druid-Feral','Hunter-Marksmanship','Druid-Balance','Mage-Arcane',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=46,date='2026-08-04',data={Aa='Aannte:BAACLgAFFH8sAAMBAAkJfhcABgDAAQABAAcJmBUABgDAAQACAAQJ8hetBQAXAQAuAAQKfyQAAwEACQlVIowmAHgCAAEACQlGIowmAHgCAAIABAnwHvcdAGABAAAA.Aardbark:BAAALgADCgEJAQAAAA==.',
Ab='Abúsedyoû:BAAALgADCgQJBgAAAA==.',
Ac='Achtland:BAAALgAECgUJBgABLgAFFAEJAQADAAAAAA==.',
Ad='Adius:BAAALgAECgEJAQAAAA==.Adv:BAAALgAECgEJAQAAAA==.',
Ae='Aerestrix:BAAALgAECgYJBwAAAA==.',
Ai='Airvis:BAABLgAECn8yAAIEAAkJGgyIZgCwAQAEAAkJGgyIZgCwAQAAAA==.',
Ak='Akirika:BAAALgAECgkJAgAAAA==.',
Al='Alacia:BAAALgAECgkJEAABLgAFFAMJCgAFAFIaAA==.Alatarr:BAAALgAECgcJEQAAAA==.Albinomonk:BAAALgADCgcJBwAAAA==.Alilea:BAAALgADCgYJBgABLgAFFAMJCgAFAFIaAA==.Alundre:BAAALgAECgEJAQAAAA==.',
Am='Amaira:BAAALgADCgEJAQAAAA==.',
An='Anankei:BAAALgAECgUJCgAAAA==.Annastrophic:BAAALgADCgMJAwAAAA==.Anrí:BAAALgAECgEJAQAAAA==.Antaria:BAAALgADCgcJFgAAAA==.Ante:BAAALgADCgUJAQAAAA==.Antpony:BAAALgAECgIJAgABLgAECgYJCgADAAAAAA==.',
Aq='Aqulara:BAAALgAECgEJAQAAAA==.',
Ar='Arcish:BAAALgAECgEJAgAAAA==.Arjun:BAABLgAECn8aAAIGAAkJAhI3DQDdAQAGAAkJAhI3DQDdAQAAAA==.Arkirla:BAAALgAECgEJAgAAAA==.Arkiyra:BAAALgAECggJDgAAAA==.Arklira:BAAALgAECgEJAQAAAA==.Arkosh:BAAALgAECgEJAgAAAA==.Arkyra:BAAALgAECgUJBwAAAA==.Aro:BAAALgAECgEJAQAAAA==.Arovix:BAABLgAECn8ZAAIHAAgJVBrvKwD6AQAHAAgJVBrvKwD6AQAAAA==.Arturogh:BAABLgAFFH8MAAIIAAQJ+AwADwCvAAAIAAQJ+AwADwCvAAAAAA==.',
As='Ashwey:BAAALgADCgkJCAAAAA==.Aspira:BAAALgAECgUJBQAAAA==.Astin:BAAALgADCgYJCAAAAA==.',
At='Atom:BAABLgAECn8nAAIFAAkJFBmHHwBqAgAFAAkJFBmHHwBqAgAAAA==.',
Au='Aubreey:BAAALgADCgcJCQAAAA==.Aureille:BAAALgAECgYJCgAAAA==.',
Aw='Awoozehl:BAACLgAFFH83AAMJAAkJ/iEKCwA+AgAJAAgJ/iEKCwA+AgAKAAEJAABhTQAAAAAuAAQKfz0AAgkACQnWJpMCAHYDAAkACQnWJpMCAHYDAAAA.',
Az='Azanoth:BAAALgAECgYJCQABLgAFFAQJDAAIAPgMAA==.Azgrodon:BAABLgAECn82AAMLAAkJrBeTHQBgAgALAAkJrBeTHQBgAgAMAAMJjww+bACSAAAAAA==.Azor:BAABLgAECn8YAAINAAgJch08HQCiAgANAAgJch08HQCiAgAAAA==.',
Ba='Badatgame:BAAALgAECgQJBAAAAA==.Baja:BAAALgAECgQJBAAAAA==.Baldomar:BAAALgADCgUJCAAAAA==.Banatok:BAAALgAECgEJAQAAAA==.Bangmonk:BAAALgAFFAQJBAABLgAFFAkJSgAOAD8jAA==.Bangungot:BAAALgADCgMJAwABLgAFFAkJSgAOAD8jAA==.Barristan:BAAALgAECgYJEwAAAA==.Bartholomule:BAAALgAECgEJAQAAAA==.Barzalie:BAAALgAECgYJDAABLgAFFAMJAwADAAAAAA==.Bathrezz:BAABLgAECn8gAAMPAAkJoxewUADWAQAPAAkJoxewUADWAQAQAAMJWA/FaQCPAAAAAA==.',
Be='Bearlyawake:BAAALgAECgYJDAAAAA==.Bearyonce:BAABLgAFFH8HAAIIAAMJARbYJQCDAAAIAAMJARbYJQCDAAABLgAFFAkJLQARADIRAA==.Beerbelly:BAAALgAFFAMJAwAAAA==.Beleaves:BAACLgAFFH81AAISAAkJkwoNDwCwAQASAAkJkwoNDwCwAQAuAAQKf0EAAhIACQlbHbwKAIgCABIACQlbHbwKAIgCAAAA.Beorl:BAAALgADCgYJCAAAAA==.',
Bh='Bhackshots:BAABLgAECn8ZAAITAAUJjSGMLQA5AQATAAUJjSGMLQA5AQABLgAFFAIJBQAUAIAiAA==.',
Bi='Bifurious:BAABLgAECn8jAAIVAAkJvx0XDwCDAgAVAAkJvx0XDwCDAgAAAA==.Bigrob:BAAALgAECgEJBQAAAA==.',
Bl='Blackprism:BAAALgAECgYJEwAAAA==.Blowmybubble:BAAALgAECgEJAQABLgAECgkJIAAFAKchAA==.Bluereindeer:BAABLgAECn8VAAIJAAkJAgvpaACUAQAJAAkJAgvpaACUAQAAAA==.',
Bo='Bobsstones:BAACLgAFFH8xAAQBAAkJ3yHQAwDkAQABAAgJwh3QAwDkAQAWAAUJzyCpAQB/AQACAAUJ0B4sBgANAQAuAAQKfykABAIACQlCJT0GAGwCAAEABwmkJP4bAK0CAAIABgmDJD0GAGwCABYAAwm6JOgVANUAAAAA.Bonekitty:BAAALgAECgYJBgAAAA==.Bonkulo:BAACLgAFFH8LAAIKAAMJWRQ0KAC0AAAKAAMJWRQ0KAC0AAAuAAQKfy4ABAoACQmjFT0UANABAAoACAmEFz0UANABABcAAwkACYQOAF8AAAkAAQl6CLFzATMAAAEuAAUUBAkMAAgA+AwA.Boofassist:BAABLgAECn8dAAIQAAkJ7CKABAAmAwAQAAkJ7CKABAAmAwABLgAFFAgJIgAYAJ0iAA==.Boogey:BAABLgAECn8fAAMEAAgJfQ3NggByAQAEAAgJfQ3NggByAQAZAAEJpQiNEAAyAAAAAA==.Boompowwow:BAABLgAECn8VAAIMAAYJIxnmNACDAQAMAAYJIxnmNACDAQAAAA==.Boomsonic:BAAALgADCgUJBQABLgAECgkJIwAVAL8dAA==.Bophadeez:BAABLgAECn8qAAQQAAgJeB4bHwAgAgAQAAcJGSEbHwAgAgAaAAgJ/ximDQDrAQAPAAYJvQ/MjABhAQABLgAFFAUJFwAYALIbAA==.',
Br='Brienyx:BAAALgAECgMJBwAAAA==.Briogan:BAABLgAFFH8GAAMJAAMJygMlYQCTAAAJAAMJygMlYQCTAAAKAAIJ7wCOPwAzAAAAAA==.Broccoliz:BAECLgAFFH9HAAIHAAkJpxqlBQC1AgAHAAkJpxqlBQC1AgAuAAQKf0IAAgcACQkUH9MYAHECAAcACQkUH9MYAHECAAAA.Brokan:BAABLgAFFH8LAAIbAAMJ2AnGFwC/AAAbAAMJ2AnGFwC/AAAAAA==.Brokgar:BAAALgAECggJEAAAAA==.Brokgian:BAABLgAFFH8JAAILAAMJrgzEKgCcAAALAAMJrgzEKgCcAAAAAA==.Brotu:BAAALgADCgIJAQAAAA==.Bruceleroy:BAAALgADCgEJAQAAAA==.Brutalsmasch:BAAALgADCgUJBQAAAA==.',
Bu='Bubu:BAAALgAECgEJAQAAAA==.Bukhaki:BAAALgAFFAEJAQABLgAFFAIJBQAUAIAiAA==.Bulis:BAAALgAECgMJAwAAAA==.Bullblaster:BAAALgAECgMJBQAAAA==.',
Bw='Bwonshamdi:BAAALgAECgcJBwABLgAECgcJBwADAAAAAA==.',
['Bõ']='Bõb:BAAALgAFFAMJAwAAAA==.',
Ca='Caden:BAAALgAECgQJBAABLgAFFAMJCgAFAFIaAA==.Cafca:BAABLgAECn9AAAICAAkJvRsnBABCAgACAAkJvRsnBABCAgAAAA==.Cahma:BAAALgAECgUJBgAAAA==.Caitlin:BAAALgAECgEJAQABLgAFFAQJCgAFAFYZAA==.Callyour:BAAALgADCgIJAgAAAA==.Cankel:BAAALgAECgEJAQAAAA==.Cask:BAAALgADCgYJAQAAAA==.',
Ch='Chaesol:BAAALgAFFAEJAQAAAA==.Chainsawloli:BAAALgADCgUJBQAAAA==.Changying:BAAALgAECggJDQAAAA==.Cheekung:BAAALgAECgcJEgAAAA==.Cheeseburgr:BAAALgADCgEJAQAAAA==.Chewedup:BAAALgAECgcJBAABLgAECgkJIwAVAL8dAA==.Choedankal:BAAALgADCgcJBwAAAA==.Chophouse:BAAALgAECgkJBgAAAA==.Chungusdelux:BAAALgAECgMJAwAAAA==.',
Cl='Clearlyumad:BAACLgAFFH8ZAAQJAAcJZRNIJQDXAQAJAAcJ+RJIJQDXAQAXAAQJywWiEwDxAAAKAAEJAADZYQAAAAAuAAQKfxsAAgkACAmPHlE8AEYCAAkACAmPHlE8AEYCAAAA.Clèrick:BAABLgAECn9CAAMQAAkJnSTcAwBfAwAQAAkJnSTcAwBfAwAPAAEJfwnFggE7AAAAAA==.',
Co='Coldcrow:BAAALgAECgEJAQAAAA==.Combination:BAACLgAFFH8aAAIYAAYJ5hxSCwDZAQAYAAYJ5hxSCwDZAQAuAAQKfxYAAhgACAkNJCgJAAgDABgACAkNJCgJAAgDAAAA.Confessor:BAAALgAECgEJAQAAAA==.Corruptions:BAAALgADCgEJAQAAAA==.Cowen:BAAALgAECgMJBQAAAA==.',
Cr='Cromuk:BAAALgAECgEJAgAAAA==.Crustytowel:BAAALgAECgEJAQAAAA==.Crux:BAAALgADCgQJBAAAAA==.',
Cu='Cursedsofa:BAAALgAECgEJAQAAAA==.',
Cy='Cyfrin:BAAALgADCgEJAQAAAA==.Cyânide:BAAALgADCgYJDQAAAA==.',
['Cõ']='Cõurage:BAAALgAECgYJCAAAAA==.',
Da='Dabbhammer:BAAALgAFFAEJAwAAAA==.Dabbyforms:BAAALgAECgIJBAABLgAFFAEJAwADAAAAAA==.Dabbyshatner:BAAALgAECgEJAgABLgAFFAEJAwADAAAAAA==.Dabbzyvoker:BAABLgAECn8gAAMcAAgJgQxZOgBCAQAcAAgJQwxZOgBCAQAOAAYJowZ/IgAWAQABLgAFFAEJAwADAAAAAA==.Dallzbeep:BAAALgAECgkJCQABLgAFFAUJFwAYALIbAA==.Danathoor:BAAALgADCggJCAAAAA==.Danathor:BAAALgADCgcJBwAAAA==.Dangbro:BAAALgAECgYJEQAAAA==.Dankspank:BAAALgAECgQJCAABLgAECgcJFwAbAAwRAA==.Danteus:BAAALgADCgMJAwABLgAECgUJDwADAAAAAA==.Darkrigh:BAAALgADCggJDgAAAA==.Darkwave:BAACLgAFFH8IAAIBAAMJXQt5NQC4AAABAAMJXQt5NQC4AAAuAAQKfz4AAgEACQkxGcciAFYCAAEACQkxGcciAFYCAAAA.Darthdiddyus:BAACLgAFFH81AAMdAAkJ8xvsAAAfAgAdAAcJKx7sAAAfAgAbAAUJExenDQAQAQAuAAQKfzYABB0ACQl7JbYAAC4DAB0ACQl3JbYAAC4DABsABwlRITwUAHICABQABAnJId0KAIIBAAAA.Datdruidguy:BAAALgADCgUJBQABLgAECgYJBgADAAAAAA==.Datlock:BAAALgADCgEJAQABLgAECgYJBgADAAAAAA==.Datshammy:BAAALgAECgYJBgAAAA==.Daviculas:BAAALgADCggJDgAAAA==.Dawghawg:BAAALgAECgQJBAAAAA==.Dawnnie:BAACLgAFFH8eAAIaAAYJtRC5BADuAAAaAAYJtRC5BADuAAAuAAQKf0IAAhoACQm+HM0GAHUCABoACQm+HM0GAHUCAAAA.Dawnte:BAABLgAECn8dAAIPAAcJHBzdYQCtAQAPAAcJHBzdYQCtAQABLgAECgUJDwADAAAAAA==.Dawsonrogers:BAACLgAFFH8QAAIVAAYJPAiQDgAtAQAVAAYJPAiQDgAtAQAuAAQKfx4AAhUACQlXE1EuAJcBABUACQlXE1EuAJcBAAAA.Dayvastate:BAABLgAECn83AAMJAAkJqhtGJgBqAgAJAAkJqhtGJgBqAgAXAAEJDxJtOwAwAAAAAA==.Dazshir:BAAALgAECgUJBAAAAA==.',
De='Deathbanana:BAABLgAFFH8dAAIJAAUJDyQwPQB+AQAJAAUJDyQwPQB+AQABLgAFFAkJLAAEAEwhAA==.Deaththreat:BAABLgAECn8XAAIVAAcJhBrZAgAlAgAVAAcJhBrZAgAlAgABLgAECgkJKgAPALEcAA==.Deepwater:BAAALgAECgUJBQAAAA==.Delema:BAACLgAFFH8YAAIPAAYJ6xtsIQCBAQAPAAYJ6xtsIQCBAQAuAAQKfyAAAg8ACAlaIUQiAKACAA8ACAlaIUQiAKACAAAA.Democrit:BAAALgAECgYJDwAAAA==.Demonjuice:BAAALgAECgcJDAAAAA==.Derpyblinker:BAABLgAECn8VAAIEAAYJQRDu0wBHAQAEAAYJQRDu0wBHAQAAAA==.Destructer:BAABLgAECn8qAAICAAkJXxJdCADIAQACAAkJXxJdCADIAQAAAA==.Dethstar:BAAALgAECgUJCAABLgAFFAMJCAABAF0LAA==.Devoured:BAAALgADCgMJAwAAAA==.',
Di='Dinger:BAAALgAECgEJAQAAAA==.Dirtydinker:BAAALgAECgYJDQAAAA==.Disconneted:BAAALgADCgYJBgAAAA==.Dishwasher:BAAALgADCgIJAgAAAA==.Dixsard:BAACLgAFFH8FAAMUAAIJgCJJAwC+AAAUAAIJgCJJAwC+AAAbAAEJQxRGKABHAAAuAAQKfzcAAxQACQn5IzoBAAoDABQACQnHIzoBAAoDABsABwk7H20jAN4BAAAA.',
Do='Dobrova:BAAALgAECgEJAQAAAA==.Doezenn:BAAALgADCgUJBQAAAA==.Dogofwar:BAAALgAECgEJAQAAAA==.Dottprepared:BAACLgAFFH8tAAIRAAkJMhGDAQCcAQARAAkJMhGDAQCcAQAuAAQKf0EAAhEACQmaIpcBAAcDABEACQmaIpcBAAcDAAAA.Dottyfu:BAABLgAFFH8FAAISAAMJKwl/PwCoAAASAAMJKwl/PwCoAAAAAA==.Doubted:BAAALgAECgQJBAAAAA==.',
Dr='Dracoiconic:BAAALgAECgEJAgAAAA==.Dragonboffa:BAAALgAECgcJAQAAAA==.Draul:BAAALgAECgEJAQABLgAECgkJNgALAKwXAA==.Drexl:BAACLgAFFH8gAAMeAAkJyRSQBgCHAQAeAAYJPxqQBgCHAQAfAAMJaARlIwA+AAAuAAQKfzoABB8ACQlxH18HAIICAB8ACQnlHV8HAIICABUABwkSBtplABwBAB4AAgm+Ef8QAEoAAAAA.Dril:BAABLgAECn8dAAMNAAgJMxlLNwDpAQANAAgJHxlLNwDpAQARAAIJAhZvIACBAAAAAA==.Drognin:BAAALgAECgMJBAAAAA==.Drunera:BAAALgADCgQJAgAAAA==.Drunkfu:BAAALgADCgQJBAAAAA==.',
Du='Dubstep:BAAALgAECgkJAgAAAA==.Dudette:BAAALgAECgcJDAAAAA==.Dunlop:BAABLgAECn8fAAMgAAkJqBg1DgCEAgAgAAkJqBg1DgCEAgAhAAIJ9wSleQBMAAABLgAFFAMJBwALAB4ZAA==.',
Dv='Dvmcquéén:BAABLgAECn8WAAMCAAcJ5xkzCwANAgACAAcJ5xkzCwANAgABAAIJBwRHBwFOAAAAAA==.',
Dw='Dweams:BAACLgAFFH8nAAIhAAkJQRo9AQAnAgAhAAkJQRo9AQAnAgAuAAQKfzwAAyEACQmLJhIBAHIDACEACQmLJhIBAHIDACIABAmrDNE5ANgAAAAA.Dweamu:BAAALgAECgUJCQABLgAFFAkJJwAhAEEaAA==.',
['Dâ']='Dântæ:BAAALgAECgUJDwAAAA==.',
['Då']='Dåmon:BAAALgAECgEJBAAAAA==.',
['Dö']='Döts:BAAALgADCgMJAgAAAA==.',
['Dø']='Døctøred:BAAALgAECgYJEwAAAA==.',
Ea='Easycheeze:BAAALgAECgEJAgAAAA==.',
Ec='Ectonight:BAAALgAECgUJDAAAAA==.',
Ed='Edgybob:BAAALgAECgMJAwAAAA==.',
Eg='Eggfooyung:BAACLgAFFH8iAAIYAAgJnSKdAgAXAwAYAAgJnSKdAgAXAwAuAAQKfzIAAxgACQmPIRcEAC8DABgACQmPIRcEAC8DACMABwlPCCk7ADABAAAA.Egwene:BAAALgAECgYJBwAAAA==.',
El='Eldar:BAAALgAECgUJBQAAAA==.Elfchick:BAAALgADCgEJAQAAAA==.Elhonna:BAABLgAFFH8PAAIFAAYJTAkMGQBPAQAFAAYJTAkMGQBPAQAAAA==.Elsâ:BAAALgAECgQJCAAAAA==.',
Em='Emwen:BAAALgADCgMJAwAAAA==.',
En='Endcredits:BAABLgAECn8iAAIKAAkJwg+wHAB0AQAKAAkJwg+wHAB0AQAAAA==.',
Et='Ether:BAABLgAECn8eAAIMAAgJzhPUKADNAQAMAAgJzhPUKADNAQAAAA==.Ettie:BAAALgAECgMJBwABLgAECgQJBgADAAAAAA==.',
Ev='Evieroot:BAAALgADCgMJAwAAAA==.Evoulker:BAACLgAFFH84AAIkAAkJwBryAABWAgAkAAkJwBryAABWAgAuAAQKf0EAAiQACQkSH6YFAO4CACQACQkSH6YFAO4CAAAA.',
Ex='Exodyce:BAAALgAECgQJBAAAAA==.',
Ey='Eyecantsee:BAAALgADCgIJAgABLgAECgQJBAADAAAAAA==.',
Fa='Faene:BAAALgAECgUJCwABLgAECgUJBQADAAAAAA==.Faire:BAAALgADCgUJBQABLgAFFAQJCgAFAFYZAA==.Fairytale:BAACLgAFFH81AAMiAAkJvBBLAwDPAQAiAAkJvBBLAwDPAQAgAAEJMwjHEwBGAAAuAAQKf0EAAyIACQlmIAAHANUCACIACQlmHQAHANUCACAABwn5HkcSAE4CAAAA.Faitza:BAAALgAECgYJCgAAAA==.Fantastico:BAAALgAECgUJDQAAAA==.Fauxpaws:BAAALgAECgYJBgAAAA==.',
Fe='Felheim:BAACLgAFFH8TAAINAAYJTwnPMgBaAQANAAYJTwnPMgBaAQAuAAQKfyoAAg0ACQlbHp8FALwBAA0ACQlbHp8FALwBAAAA.Fellitha:BAABLgAECn8UAAIKAAgJKwKiPgCVAAAKAAgJKwKiPgCVAAAAAA==.Fellithà:BAAALgAECgcJDgAAAA==.Felrend:BAAALgADCgMJAgAAAA==.Fentertained:BAAALgADCgcJCAAAAA==.',
Fi='Fiercevalkyr:BAAALgAECgkJBgAAAA==.Firsttower:BAAALgADCgIJAgAAAA==.Fists:BAACLgAFFH8XAAIYAAUJshu5GgCfAQAYAAUJshu5GgCfAQAuAAQKfzgABBgACQkpH6ELAN4CABgACQkpH6ELAN4CABIABAlOFrRdAMwAACMAAwlrFFRVALcAAAAA.Fizle:BAABLgAECn8bAAIkAAkJHAquFgBkAQAkAAkJHAquFgBkAQAAAA==.',
Fl='Flink:BAABLgAECn8cAAMJAAgJEgaZIAC0AAAJAAcJjwWZIAC0AAAXAAYJTQP7EQBxAAAAAA==.',
Fo='Formosa:BAAALgADCgEJAQAAAA==.Fourchainz:BAABLgAFFH8LAAIHAAUJ1x2OCADGAQAHAAUJ1x2OCADGAQABLgAFFAcJDQAkANMPAA==.Foxygal:BAAALgAECgQJBAAAAA==.',
Fr='Friend:BAAALgAECgYJEAAAAA==.Frostmoan:BAAALgAFFAEJAQAAAA==.Frostyninja:BAABLgAECn8jAAIFAAgJlgZTlwARAQAFAAgJlgZTlwARAQAAAA==.',
['Fä']='Fäye:BAAALgAECgEJAQAAAA==.',
Ga='Gabryal:BAABLgAECn8nAAIhAAkJSyCeBwDWAgAhAAkJSyCeBwDWAgAAAA==.Galthur:BAAALgAECgUJCQAAAA==.Ganbatte:BAAALgAECgYJBgAAAA==.Garchomp:BAAALgAECgUJEwAAAA==.Gargameel:BAAALgAECgMJAwAAAA==.',
Ge='Gellina:BAAALgAECgUJBgAAAA==.Georg:BAACLgAFFH8uAAIPAAkJ+BcPAwDIAQAPAAkJ+BcPAwDIAQAuAAQKfzIAAg8ACQm7JjADAKMDAA8ACQm7JjADAKMDAAAA.Gerbankis:BAAALgAECgMJAwAAAA==.',
Gh='Ghoul:BAACLgAFFH8HAAIJAAIJICU1sADDAAAJAAIJICU1sADDAAAuAAQKfxoAAgkACAmSI+gZAOECAAkACAmSI+gZAOECAAAA.Ghouligan:BAAALgAECgQJBAAAAA==.',
Gi='Giga:BAAALgAECgMJAwAAAA==.',
Gl='Glaiver:BAABLgAECn8hAAIlAAkJ5xB/GgCsAQAlAAkJ5xB/GgCsAQAAAA==.Glassjaw:BAAALgADCgUJBQAAAA==.Glimer:BAAALgADCgIJAgAAAA==.',
Go='Goewin:BAAALgAFFAEJAQAAAA==.Gojo:BAAALgADCgYJDwAAAA==.Gorgrom:BAAALgADCgIJAgAAAA==.',
Gr='Gradiant:BAAALgAECgEJAgABLgAECgkJNgALAKwXAA==.Grantoro:BAABLgAFFH8FAAIIAAMJSQifFgBzAAAIAAMJSQifFgBzAAAAAA==.Greg:BAAALgAECgIJAgAAAA==.Gregorz:BAAALgAECgEJAQAAAA==.Grippies:BAAALgAECgkJCQAAAA==.',
Gu='Gulgodeth:BAAALgAECgQJBQAAAA==.Gulgrimmar:BAACLgAFFH83AAMMAAkJ7yPYAwCiAgAMAAkJ7yPYAwCiAgALAAIJWRZTcABdAAAuAAQKfzcAAgwACQnnJqwAANkDAAwACQnnJqwAANkDAAAA.Guwudanielle:BAAALgAFFAIJAgABLgAFFAQJCgAFAFYZAA==.',
['Gì']='Gìzzìmo:BAABLgAECn8XAAMRAAgJSB5KCADwAQARAAgJSB5KCADwAQANAAQJYhOlGgCtAAAAAA==.',
Ha='Hailsstorm:BAAALgADCgcJEgAAAA==.Hanora:BAAALgAECgEJAQABLgAFFAQJDAAIAPgMAA==.Hardfeelings:BAABLgAECn8qAAIPAAkJsRzcIACEAgAPAAkJsRzcIACEAgAAAA==.Harkness:BAAALgAECgYJDwAAAA==.Hassif:BAAALgAECgEJAQAAAA==.',
He='Heimerdoodle:BAAALgAECggJEwAAAA==.Hemlawk:BAAALgAECgEJAQAAAA==.Hemus:BAAALgAECgMJAwAAAA==.Hexappeal:BAAALgAECgIJAgAAAA==.Hexed:BAABLgAECn81AAISAAkJMRGKHwCqAQASAAkJMRGKHwCqAQAAAA==.',
Ho='Hochipo:BAAALgAECgEJAQAAAA==.',
Hu='Hughue:BAAALgAECgYJBgAAAA==.Hugs:BAAALgAECgYJCgAAAA==.Hurjek:BAAALgAFFAEJAQABLgAFFAYJGgAYAOYcAA==.',
Hy='Hyuna:BAAALgAECgEJAQABLgAECgcJDgADAAAAAA==.',
Ia='Iaso:BAABLgAECn8lAAIgAAkJCBQQGgD6AQAgAAkJCBQQGgD6AQAAAA==.',
Ic='Icehide:BAAALgAECgQJCQAAAA==.Iconstar:BAAALgADCggJEQAAAA==.',
Ig='Igneel:BAAALgADCgQJAQAAAA==.Ignored:BAABLgAFFH8MAAIQAAYJLhNdCACTAQAQAAYJLhNdCACTAQAAAA==.',
Ij='Ijustankedu:BAAALgAECgMJAwAAAA==.',
Ik='Ikiea:BAAALgAECgcJCAAAAA==.',
Il='Ilgrim:BAABLgAECn8YAAMQAAgJWxnFKgC5AQAQAAgJWxnFKgC5AQAPAAQJ+AO2LAFIAAABLgAFFAUJDgAbACkPAA==.Ilravenll:BAACLgAFFH8OAAIbAAUJKQ9PIAAiAQAbAAUJKQ9PIAAiAQAuAAQKfyEAAhsACQmQGPMLAGUCABsACQmQGPMLAGUCAAAA.Ilweaver:BAAALgAFFAEJAQABLgAFFAUJDgAbACkPAA==.Ilyana:BAACLgAFFH8yAAIEAAkJyBvzEwBQAgAEAAkJyBvzEwBQAgAuAAQKf0EAAgQACQk2Jm0EAGMDAAQACQk2Jm0EAGMDAAAA.',
Im='Impavido:BAAALgAECgYJBgAAAA==.',
In='Inholy:BAABLgAECn8UAAIlAAYJohdhJABVAQAlAAYJohdhJABVAQAAAA==.Insights:BAAALgADCgMJAwAAAA==.',
Is='Isabella:BAAALgAECgEJAQABLgAFFAQJCgAFAFYZAA==.',
It='Ithopel:BAABLgAECn8mAAIHAAYJASF6KAASAgAHAAYJASF6KAASAgAAAA==.',
Ja='Jalista:BAAALgADCgMJAwAAAA==.Jayc:BAACLgAFFH8hAAIEAAgJlRzmMwCZAQAEAAgJlRzmMwCZAQAuAAQKfyAAAgQACQkUIid0AOoBAAQACQkUIid0AOoBAAAA.',
Je='Jereico:BAACLgAFFH87AAIcAAkJ5SPrAACQAgAcAAkJ5SPrAACQAgAuAAQKfzsAAhwACQnmJnIAAI8DABwACQnmJnIAAI8DAAAA.Jeryhn:BAACLgAFFH8yAAIQAAkJOxlEAgDZAQAQAAkJOxlEAgDZAQAuAAQKf0EAAhAACQk8GhYTAHoCABAACQk8GhYTAHoCAAAA.Jezaridan:BAAALgADCgYJBgAAAA==.',
Jo='Joeburrow:BAAALgAECgQJBAAAAA==.Joeynodz:BAAALgADCgYJEgAAAA==.Jortshorts:BAABLgAECn8vAAImAAkJ+AnYGgA2AQAmAAkJ+AnYGgA2AQAAAA==.',
Jr='Jray:BAABLgAECn8VAAIPAAYJGRnOZAC3AQAPAAYJGRnOZAC3AQAAAA==.',
Ju='Juggalo:BAACLgAFFH8QAAMOAAUJXSDfAQB+AQAOAAUJXSDfAQB+AQAcAAEJkQY4ZwA3AAAuAAQKfysAAw4ACQllIp4BANcCAA4ACQllIp4BANcCABwAAgmJEp2JAEkAAAAA.June:BAACLgAFFH8pAAIYAAkJmBqxAQAaAgAYAAkJmBqxAQAaAgAuAAQKfz8AAxgACQlsIbMEAB0DABgACQlsIbMEAB0DACMACQkGH7MJAKoCAAAA.Juuju:BAAALgAECgYJEwAAAA==.',
Ka='Kaereth:BAAALgAFFAIJAwABLgAFFAkJNAAbAIIbAQ==.Kaldriss:BAAALgAECgEJAgAAAA==.Kalen:BAAALgADCgEJAgAAAA==.Kallidos:BAAALgAECgEJAQAAAA==.Katashimus:BAABLgAECn8hAAIEAAkJsxXyBgASAgAEAAkJsxXyBgASAgAAAA==.Kawasuoo:BAABLgAECn8gAAMHAAgJMR3HIgAzAgAHAAcJzhzHIgAzAgAIAAYJAAxoQAClAAAAAA==.Kaze:BAAALgAECgcJEQAAAA==.',
Ke='Kefka:BAAALgAECgYJCAABLgAFFAQJDAAIAPgMAA==.Kethram:BAAALgAECgYJDAAAAA==.',
Kh='Khaotichic:BAABLgAECn8oAAIFAAkJ6w5FIADWAAAFAAkJ6w5FIADWAAAAAA==.Khraboom:BAAALgAECgQJBQABLgAECgUJCwADAAAAAA==.Khrenak:BAAALgAECgUJCwAAAA==.',
Ki='Kickpunch:BAAALgAECgYJDgAAAA==.Kirah:BAACLgAFFH8HAAIcAAIJxRzUTACbAAAcAAIJxRzUTACbAAAuAAQKfyAAAhwACQmwIWoEAEoDABwACQmwIWoEAEoDAAEuAAUUBAkKAAUAVhkA.',
Kl='Klrum:BAAALgAECggJDwAAAA==.Kläus:BAAALgAECgEJAQAAAA==.',
Ko='Koddin:BAABLgAECn8zAAIPAAkJ6h7AJwBkAgAPAAkJ6h7AJwBkAgAAAA==.Korenchkin:BAAALgAECgEJAgAAAA==.Koreth:BAACLgAFFH80AAMbAAkJghteCQALAgAbAAcJHx1eCQALAgAUAAIJNRAPBgBTAAAuAAQKf0gAAxsACQmAJtYBAE0DABsACQmAJtYBAE0DABQACAmWGg8EAHcCAAAA.Kornholyo:BAAALgAECgEJAQAAAA==.',
Kr='Kragoth:BAAALgADCgIJAgAAAA==.',
Ku='Kutuzov:BAABLgAECn8oAAILAAkJchPLQACqAQALAAkJchPLQACqAQAAAA==.',
Kw='Kwaiza:BAAALgAECgYJDwAAAA==.',
['Ká']='Káel:BAAALgAECgMJAwAAAA==.',
La='Lailaysia:BAABLgAECn8cAAIgAAkJDyIlAwBiAwAgAAkJDyIlAwBiAwAAAA==.Lamemoosaur:BAAALgADCgIJAgABLgAECgYJCgADAAAAAA==.Laríca:BAACLgAFFH8rAAIQAAUJ7CUoCgAWAgAQAAUJ7CUoCgAWAgAuAAQKfzMAAhAACQmDJYMCAFIDABAACQmDJYMCAFIDAAAA.Laustin:BAABLgAECn8kAAQTAAkJXhvBCgByAgATAAkJVhvBCgByAgAnAAYJEhCUGwDRAAAFAAIJbwWdCwFSAAAAAA==.Laustinjung:BAAALgADCgIJAQAAAA==.Laydout:BAAALgAECggJEgABLgAECgkJIAAFAG8iAA==.Laydoutyota:BAABLgAECn8gAAIFAAkJbyLmEQDCAgAFAAkJbyLmEQDCAgAAAA==.',
Le='Leag:BAABLgAECn8YAAMVAAcJFw+MQACiAQAVAAcJFw+MQACiAQAfAAEJJAmvPwA5AAAAAA==.Leethaxor:BAAALgAECgEJAQAAAA==.Lemonruss:BAAALgADCgQJBAAAAA==.',
Li='Liaria:BAAALgAECgEJAQAAAA==.Lightyoassup:BAAALgADCgMJAwABLgAECgQJBAADAAAAAA==.Lilea:BAACLgAFFH8KAAIFAAMJUhpuXQDqAAAFAAMJUhpuXQDqAAAuAAQKfzoAAwUACQnFH/kVAKQCAAUACQnFH/kVAKQCACcABwkQF9sDAPYAAAAA.Lionsmane:BAACLgAFFH8HAAILAAMJHhnoIADMAAALAAMJHhnoIADMAAAuAAQKfyEAAwsACQm0HUcEAEICAAsACQm0HUcEAEICAAYAAQkqBUVEACgAAAAA.Lithium:BAAALgADCgUJBQAAAA==.Littledeb:BAAALgAFFAEJAQAAAA==.',
Lo='Lockdots:BAAALgADCggJCwAAAA==.Lolchaosbolt:BAAALgADCgYJBgAAAA==.Lortherian:BAABLgAECn8cAAMeAAkJySDnCABpAgAeAAkJySDnCABpAgAVAAEJ/hb1lgBEAAAAAA==.Lowbo:BAAALgADCgUJBQAAAA==.Lowelfesteem:BAAALgADCgUJBQAAAA==.',
Lu='Lucey:BAAALgAECgEJAwAAAA==.Lucille:BAABLgAECn8aAAIEAAYJ3gfJ3wDbAAAEAAYJ3gfJ3wDbAAAAAA==.Lunäh:BAAALgAECgEJAQAAAA==.',
Ly='Lyndira:BAAALgAECgUJBQAAAA==.Lyraan:BAACLgAFFH8GAAIQAAQJ4wwBEgDTAAAQAAQJ4wwBEgDTAAAuAAQKfxcAAw8ACQm6DbAOAHABAA8ACQm6DbAOAHABABAABwldCRkJABwBAAAA.',
['Lä']='Läwlbringer:BAAALgAECggJDQAAAA==.',
['Lî']='Lîghtt:BAAALgADCgQJBAAAAA==.',
Ma='Mabritos:BAAALgAECgQJBQABLgAFFAkJFQANAAcSAA==.Maccabee:BAAALgAECgEJAQAAAA==.Malison:BAAALgAECgIJAgAAAA==.Mania:BAAALgADCgYJBgABLgAECgkJIwAVAL8dAA==.Mareth:BAAALgAECgUJBQAAAA==.Mathath:BAACLgAFFH8QAAIJAAQJLBCSRgDMAAAJAAQJLBCSRgDMAAAuAAQKfxwAAwkACAn4F+xXAL4BAAkACAnIF+xXAL4BAAoABAlUFacoAPkAAAAA.Mathmath:BAAALgAECgUJCgABLgAFFAEJAQADAAAAAA==.Mathoras:BAACLgAFFH8HAAIBAAMJCwvafgDHAAABAAMJCwvafgDHAAAuAAQKfx8AAgEACQlZGAA3AP0BAAEACQlZGAA3AP0BAAAA.Maxboom:BAAALgAECgIJAgAAAA==.Mayleen:BAAALgAECgEJAQAAAA==.Mazraq:BAAALgAECgEJAgABLgAECgkJNgALAKwXAA==.',
Me='Meandean:BAAALgAECgIJBgAAAA==.Meatier:BAAALgAECgcJEAABLgAECgkJIwAVAL8dAA==.Meatless:BAAALgADCgcJDQAAAA==.Melliya:BAABLgAFFH8GAAIiAAMJeAKqOwCPAAAiAAMJeAKqOwCPAAAAAA==.Merp:BAAALgAECgMJBAAAAA==.',
Mi='Micmac:BAAALgAECgQJCQAAAA==.Milktankk:BAAALgAECgUJCAAAAA==.Milo:BAABLgAECn8WAAIYAAgJiga0FwDJAAAYAAgJiga0FwDJAAAAAA==.Miltonroe:BAACLgAFFH8PAAIGAAQJhwvvBgDwAAAGAAQJhwvvBgDwAAAuAAQKfywAAgYACQltFAIPAMABAAYACQltFAIPAMABAAAA.Mirithul:BAAALgADCgYJBwAAAA==.Mischiëf:BAABLgAECn8VAAIPAAcJvgTJ7QDNAAAPAAcJvgTJ7QDNAAAAAA==.Mitsuri:BAABLgAECn8iAAIEAAgJoQrekgCtAQAEAAgJoQrekgCtAQAAAA==.',
Mo='Modr:BAAALgAECgkJEgAAAA==.Moiraine:BAAALgAECgEJAQAAAA==.Monkynate:BAAALgAECgYJCgAAAA==.Monnz:BAAALgAECgkJCQAAAA==.Monsterskill:BAACLgAFFH8GAAMWAAMJyxitDgBbAAAWAAIJCx2tDgBbAAABAAEJShD4wgBGAAAuAAQKfyMABBYACAmAGx4QACwBABYABgm3Gh4QACwBAAIABQmHE1QtAAgBAAEABQl0GSebAAcBAAAA.Moonerva:BAABLgAECn8iAAIoAAkJ9g4oJQCiAQAoAAkJ9g4oJQCiAQAAAA==.Morpheos:BAAALgADCgQJBAAAAA==.Mortgage:BAAALgADCgUJBQAAAA==.',
Mu='Mutsu:BAAALgADCgcJBwAAAA==.',
Mv='Mvqchx:BAAALgAECgUJCQAAAA==.',
['Mì']='Mìssy:BAABLgAECn8hAAIYAAcJXhCkDQBCAQAYAAcJXhCkDQBCAQAAAA==.',
Na='Nadrine:BAAALgAECgEJAQAAAA==.Naturelass:BAAALgADCgUJBQAAAA==.Naughtye:BAAALgADCgMJAwAAAA==.Nausicaa:BAAALgAECgEJAQAAAA==.Nawwll:BAAALgADCgMJAwAAAA==.',
Ne='Neotama:BAAALgAECggJEgAAAA==.Nethis:BAABLgAECn8nAAIhAAgJmRyjFgAVAgAhAAgJmRyjFgAVAgAAAA==.',
Ni='Niatpacgrom:BAACLgAFFH8TAAIGAAYJCREsBgABAQAGAAYJCREsBgABAQAuAAQKfyIAAgYACQlsGdkHAEwCAAYACQlsGdkHAEwCAAAA.Nightwang:BAAALgAECgUJBwAAAA==.Ninja:BAAALgAECgIJAgAAAA==.Nivla:BAAALgADCgMJAwAAAA==.',
No='Nobacon:BAAALgAECgYJDgAAAA==.Nokix:BAAALgADCgkJFgAAAA==.Nonorcman:BAAALgAECgIJAgABLgAECgQJBAADAAAAAA==.Norah:BAAALgAECgEJAQAAAA==.Norvis:BAAALgAECgQJBQAAAA==.Notdragon:BAABLgAECn8WAAIEAAQJrQpd+AC4AAAEAAQJrQpd+AC4AAAAAA==.Novachrono:BAAALgAFFAEJAQAAAA==.',
Nu='Nukeddukem:BAAALgAECgYJEgAAAA==.Numenax:BAAALgAECgEJAwAAAA==.',
Nv='Nv:BAAALgAECggJEwAAAA==.',
Ny='Nymrod:BAABLgAECn8sAAMBAAkJSBTROwDrAQABAAkJSBTROwDrAQACAAIJpgduZQBEAAAAAA==.',
['Ní']='Nír:BAAALgAECgQJBAAAAA==.',
Ob='Oben:BAAALgAECggJAQAAAA==.',
Oj='Ojou:BAAALgADCgMJAwABLgAFFAMJAwADAAAAAA==.',
Ol='Oldspice:BAAALgAECgIJAwABLgAFFAMJCAABAF0LAA==.',
On='Onepunch:BAAALgAECgQJCAAAAA==.',
Or='Orcman:BAAALgAECgMJAwABLgAECgQJBAADAAAAAA==.Orloran:BAAALgADCgIJAgAAAA==.',
Ot='Otterknight:BAAALgAECgUJBQABLgAECggJIAAHADEdAA==.',
Pa='Paladeem:BAAALgADCgEJAQAAAA==.Palthur:BAAALgAECgYJDQAAAA==.Parria:BAABLgAECn8UAAIBAAcJ8RGwdgBMAQABAAcJ8RGwdgBMAQABLgAECgkJHAAgAA8iAA==.Pasqualino:BAAALgAECgYJCgAAAA==.Passionate:BAACLgAFFH8MAAIkAAQJwAyIHADSAAAkAAQJwAyIHADSAAAuAAQKfyYAAiQACAmfFFYVAPUBACQACAmfFFYVAPUBAAAA.',
Pe='Pennance:BAABLgAECn8iAAIQAAkJ/RuZDgCiAgAQAAkJ/RuZDgCiAgAAAA==.',
Ph='Phatmidas:BAABLgAECn9AAAIPAAkJMBrNNgAmAgAPAAkJMBrNNgAmAgAAAA==.Philth:BAAALgAECgUJBwAAAA==.',
Pi='Pistfist:BAAALgAECgcJAQAAAA==.',
Pl='Plaguebanger:BAAALgADCgQJBAAAAA==.Plagueground:BAACLgAFFH84AAIJAAkJeCNiCACqAgAJAAkJeCNiCACqAgAuAAQKf0YAAgkACQntJmgCAHgDAAkACQntJmgCAHgDAAAA.Plutonyus:BAAALgAECgEJAQAAAA==.',
Po='Poc:BAABLgAECn8ZAAIEAAYJPB3wdADoAQAEAAYJPB3wdADoAQAAAA==.Pockets:BAAALgAECgMJBwAAAA==.Poolstick:BAAALgAECgYJCAAAAA==.Potatopotato:BAACLgAFFH8UAAIbAAQJChT5GgBAAQAbAAQJChT5GgBAAQAuAAQKfyUAAhsACQnAGNIOAD4CABsACQnAGNIOAD4CAAAA.Pounces:BAACLgAFFH8FAAImAAEJtySEDABjAAAmAAEJtySEDABjAAAuAAQKfxcAAiYABgn/I2USAJUBACYABgn/I2USAJUBAAEuAAUUAwkIABwAKBgA.Powerfistin:BAAALgADCgcJBwAAAA==.',
Pr='Prosecutor:BAAALgAECgUJDAAAAA==.Prozak:BAABLgAFFH8IAAIIAAQJJQoiEgCVAAAIAAQJJQoiEgCVAAAAAA==.Prynts:BAABLgAECn8VAAIPAAcJZh3sRAAVAgAPAAcJZh3sRAAVAgAAAA==.Prôzak:BAAALgAFFAIJAgAAAA==.Prøzak:BAACLgAFFH8OAAISAAMJLgavPwCoAAASAAMJLgavPwCoAAAuAAQKfxYAAhIACAmoDJo0ACwBABIACAmoDJo0ACwBAAEuAAUUBAkIAAgAJQoA.',
Ps='Psychomidget:BAABLgAECn8iAAIiAAYJTBLlBwBjAQAiAAYJTBLlBwBjAQAAAA==.',
Pu='Puetrid:BAAALgADCgYJBgABLgAECgkJCQADAAAAAA==.Pulsar:BAAALgAFFAIJAgAAAA==.Purrari:BAAALgAECgMJBwAAAA==.',
Ra='Raanky:BAAALgAECgEJAQAAAA==.Radiantlight:BAACLgAFFH8HAAIiAAMJngNHOgCaAAAiAAMJngNHOgCaAAAuAAQKfxYAAiIACAm8EPEeANYBACIACAm8EPEeANYBAAAA.Randomly:BAAALgAECgQJCAAAAA==.Raspberries:BAAALgAECgcJBwAAAA==.Rautha:BAAALgAECgkJEgAAAA==.Rayl:BAABLgAECn8dAAMJAAcJvBpnSwDgAQAJAAcJvBpnSwDgAQAKAAEJ5QEuZwAbAAAAAA==.Razsputin:BAAALgAECgMJBwAAAA==.',
Re='Refined:BAAALgAFFAIJAwABLgAFFAYJGgAYAOYcAA==.Rekless:BAAALgADCgUJBQAAAA==.Rethgar:BAAALgAECgUJEgAAAA==.',
Rh='Rhaegosa:BAABLgAECn8zAAQcAAkJDxnNJwClAQAcAAcJ0xnNJwClAQAkAAQJjBZ+GwAlAQAOAAQJrg0TGACaAAAAAA==.Rhavik:BAAALgAECgQJBgAAAA==.Rhekt:BAAALgAECgIJBQAAAA==.Rhok:BAAALgAECgEJAQAAAA==.Rhokl:BAAALgAECgEJAQAAAA==.Rhokladar:BAAALgAECgUJCwAAAA==.',
Ri='Rickylafleur:BAAALgAECgEJAgAAAA==.Ridcully:BAABLgAECn8bAAIHAAgJlxdoOgCrAQAHAAgJlxdoOgCrAQAAAA==.Rimath:BAAALgAECgcJBAAAAA==.Rinswind:BAAALgADCgMJAwAAAA==.',
Rn='Rng:BAAALgAECgQJBAABLgAFFAEJAQADAAAAAA==.',
Ro='Robopacman:BAACLgAFFH8aAAQXAAUJECHNCgBIAQAXAAQJGBnNCgBIAQAJAAQJvyAkVgBGAQAKAAEJAABhSQAAAAAuAAQKfzoABAkACQkEJRgPACMDAAkACQnyJBgPACMDAAoACAlDIo8HAKECABcAAgnhGEsoAJEAAAAA.Rodstewart:BAACLgAFFH8vAAMFAAkJwx6vDQD7AQAFAAcJ0CCvDQD7AQAnAAUJUgzvFAD2AAAuAAQKfycAAwUACQmwJE0WAIYCAAUACAmPJE0WAIYCACcABwnbHxomAPgBAAAA.Roofeo:BAABLgAECn8mAAQCAAgJ5BUVDwBNAQACAAcJMhYVDwBNAQAWAAQJQxXbGAD8AAABAAQJcgzuxQDDAAABLgAFFAQJDAAIAPgMAA==.Rosentwig:BAAALgADCgEJAQAAAA==.Rotdaddy:BAABLgAECn8vAAIJAAkJugbfmQA2AQAJAAkJugbfmQA2AQAAAA==.',
Ry='Ryoshin:BAAALgADCgEJAQABLgAECgYJDQADAAAAAA==.Ryzel:BAAALgADCgUJBQAAAA==.',
['Rï']='Rïn:BAAALgADCgEJAQAAAA==.',
Sa='Sabatikus:BAAALgAECgIJAgAAAA==.Salas:BAABLgAECn8UAAIBAAcJzgz6kQAXAQABAAcJzgz6kQAXAQAAAA==.Salino:BAACLgAFFH8FAAImAAIJ1Q5DCgB7AAAmAAIJ1Q5DCgB7AAAuAAQKfxQAAyYABwncGM4PALkBACYABwncGM4PALkBAAcABQltBlGPAJYAAAAA.Salinoster:BAAALgAECgEJBAABLgAFFAIJBQAmANUOAA==.Salordell:BAAALgADCgIJAwAAAA==.Sam:BAAALgADCgEJAQAAAA==.Sanque:BAAALgAECgMJAwAAAA==.Sarate:BAABLgAECn80AAIhAAkJvhNZCAA9AQAhAAkJvhNZCAA9AQAAAA==.Savannah:BAABLgAFFH8KAAIFAAQJVhkRPwAvAQAFAAQJVhkRPwAvAQAAAA==.Savarra:BAAALgAECgEJAwAAAA==.Savvtwo:BAAALgADCgcJBwABLgAFFAkJKAANAPkhAQ==.',
Sc='Scathach:BAABLgAECn8gAAMNAAcJ4x6mPQDRAQANAAcJ4x6mPQDRAQAlAAQJURguRADmAAABLgAFFAEJAQADAAAAAA==.Scoop:BAAALgADCgYJBgAAAA==.Scorandom:BAAALgAECgEJAQAAAA==.',
Se='Seetani:BAAALgADCgUJBgABLgAECgQJBgADAAAAAA==.Semko:BAAALgAECgEJBQAAAA==.Seven:BAAALgAECgcJCgAAAA==.Sezra:BAAALgADCgkJAQAAAA==.',
Sh='Shadowfang:BAAALgAECgEJBQAAAA==.Shaetahn:BAAALgADCgEJAQAAAA==.Shamalam:BAAALgADCgEJAQAAAA==.Sharpchedda:BAABLgAECn8UAAMmAAYJKw82KADNAAAmAAYJoAk2KADNAAAIAAIJ0BOdTAB5AAAAAA==.Shei:BAAALgAECgIJAgAAAA==.Sheidon:BAAALgAECgQJBAAAAA==.Shikai:BAAALgAECgEJAgAAAA==.Shinanigans:BAAALgAECgYJDwAAAA==.Shruikan:BAAALgADCggJDAAAAA==.',
Si='Silverbäck:BAAALgAECgYJBwABLgAECgkJGgAGAAISAA==.Silverslam:BAAALgAECgEJAQABLgAECgkJGgAGAAISAA==.Sinatra:BAAALgAECgIJBAABLgAECgcJEQADAAAAAA==.Siqodel:BAAALgAECgEJAQAAAA==.',
Sk='Skurge:BAABLgAECn8aAAMXAAkJGwqEFwAaAQAXAAgJagqEFwAaAQAJAAQJ5AfjJgCXAAAAAA==.',
Sl='Slamb:BAAALgAECgYJBwAAAA==.Slimetongue:BAAALgADCgMJAwAAAA==.Slynsoft:BAAALgAECgEJAQAAAA==.',
Sm='Smaaug:BAAALgAFFAMJBAAAAA==.',
Sn='Snuggle:BAAALgAECgEJAQAAAA==.',
So='Solstis:BAAALgAECggJDgAAAA==.Sookie:BAAALgADCgIJAgAAAA==.Soranwena:BAABLgAECn8VAAIIAAkJ9RVUAgD7AQAIAAkJ9RVUAgD7AQAAAA==.Sorzsnipe:BAAALgADCgQJBAAAAA==.',
Sp='Spellchücker:BAAALgAECgcJDQAAAA==.Spfzero:BAAALgAECgIJAgAAAA==.Springblosum:BAAALgADCgEJAQAAAA==.',
St='Staggered:BAACLgAFFH8PAAISAAQJoh7zHABBAQASAAQJoh7zHABBAQAuAAQKfyUAAxIACAkOIusLAM8CABIACAkOIusLAM8CACMAAQk1A9WMABwAAAAA.Starzburstz:BAAALgADCgEJAQAAAA==.Stiffbutt:BAAALgAECgMJBAAAAA==.Stonebeard:BAABLgAECn8bAAMPAAgJUwoWGwD2AAAPAAgJUwoWGwD2AAAaAAEJ6gEYHQASAAAAAA==.Stoneojinray:BAAALgADCgEJAQAAAA==.Stoneorcman:BAAALgADCgcJBwABLgAECgQJBAADAAAAAA==.Stregobor:BAAALgAECgkJCQAAAA==.',
Su='Subdofu:BAAALgADCgQJBAABLgAECgcJFwAbAN0cAA==.Subtox:BAABLgAECn8XAAMbAAcJ3RxNIQDvAQAbAAcJ3RxNIQDvAQAUAAEJkgu5HwA0AAAAAA==.Suddenbert:BAAALgAECgYJBgAAAA==.Sut:BAAALgAECgIJAgAAAA==.',
Sw='Sweetcool:BAAALgAECgUJCQABLgAECgkJPgAFAA8jAA==.Sweetncuddly:BAAALgAECgMJAwAAAA==.Sweetzeke:BAAALgAECgEJAQAAAA==.',
Sy='Syphilistjt:BAABLgAECn8WAAIiAAgJ0xLIFwDgAQAiAAgJ0xLIFwDgAQAAAA==.Syphillis:BAAALgAECgYJCgAAAA==.',
['Sá']='Sálud:BAACLgAFFH8MAAIoAAUJix8fGwBAAQAoAAUJix8fGwBAAQAuAAQKfywAAygACAmnIzgIANACACgACAmnIzgIANACAAgABwmhGRgWAKMBAAAA.',
['Sê']='Sêp:BAAALgAECggJDgAAAA==.',
Ta='Takoda:BAAALgAECgEJAgAAAA==.Talivath:BAAALgAECgUJCgAAAA==.Taranith:BAAALgAECgUJBQABLgAECggJGQAEAPoTAA==.Tardron:BAAALgADCgEJAQAAAA==.Tarhealeon:BAABLgAECn+GAAQaAAkJ8BiKAwCMAQAPAAkJIRdYPAATAgAQAAkJyRuWIQARAgAaAAcJUxeKAwCMAQAAAA==.Tarmander:BAAALgAECgYJDgAAAA==.Taylörshift:BAAALgAECgQJBwAAAA==.',
Te='Telahnicus:BAAALgAECgEJAQAAAA==.Terranox:BAAALgADCgMJAwAAAA==.Testostauren:BAAALgAECgQJCQAAAA==.',
Th='Thabigone:BAAALgAECgYJDAAAAA==.Thalen:BAAALgAECgEJBAAAAA==.Thalnaria:BAAALgAECgYJCwAAAA==.Thatlock:BAAALgAECgUJCAAAAA==.Thetraveler:BAAALgAECgEJAQAAAA==.Thoped:BAAALgAECgIJAgAAAA==.Threebuttons:BAAALgAECgUJDgABLgAFFAUJGQAkAHQLAA==.Thunderkis:BAABLgAECn8aAAMFAAgJfwfgrgDmAAAFAAYJHAfgrgDmAAATAAgJ1wbLCwBrAAAAAA==.',
Ti='Tiewaz:BAAALgAECgYJBwABLgAECggJHwAEAFoPAA==.Tiewiz:BAABLgAECn8fAAMEAAgJWg/jjgBaAQAEAAgJEQzjjgBaAQApAAUJlw3SDQCfAAAAAA==.Titanarum:BAAALgAECgQJBAAAAA==.',
To='Toebonk:BAAALgAECgUJBQAAAA==.Tointjoker:BAAALgAECgUJBgAAAA==.Tolun:BAABLgAECn9AAAIEAAkJqhwgIACeAgAEAAkJqhwgIACeAgAAAA==.Tosan:BAAALgADCggJDgAAAA==.',
Tr='Treeplague:BAABLgAECn9EAAMhAAkJBxMsGgD0AQAhAAkJBxMsGgD0AQAiAAcJ8RVpHgDbAQAAAA==.Trypleg:BAAALgAECgMJAwAAAA==.',
Tu='Tungie:BAABLgAECn8bAAIJAAgJ0iA4QwD5AQAJAAgJ0iA4QwD5AQAAAA==.Turn:BAACLgAFFH8/AAQBAAkJ1xpyCAChAQABAAgJ+RxyCAChAQACAAUJwg2+AwBcAQAWAAMJBSGBFwBgAAAuAAQKf0gABAEACQlRJr8UANkCAAEACAliJb8UANkCABYAAwlJJlAdANQAAAIAAwmxJK4aAM4AAAAA.Turtleduck:BAABLgAECn8kAAIOAAgJnBufBAApAgAOAAgJnBufBAApAgAAAA==.Tuskbreaker:BAAALgAECgIJAgAAAA==.',
Tw='Twittytister:BAAALgADCgQJBAAAAA==.Twostrokes:BAAALgAECgEJAQAAAA==.',
Ty='Tyrese:BAAALgADCggJEAAAAA==.',
Uf='Uffin:BAAALgAECgQJBQAAAA==.',
Um='Umbryx:BAAALgAECgYJDgAAAA==.',
Un='Unagi:BAACLgAFFH8GAAIGAAIJ8RTPCwCZAAAGAAIJ8RTPCwCZAAAuAAQKfxwAAgYACQmsE2AJACcCAAYACQmsE2AJACcCAAAA.Unholy:BAAALgADCgIJAgAAAA==.Untouched:BAAALgAFFAIJBAAAAA==.',
Va='Vakama:BAAALgADCgUJBQAAAA==.Valdi:BAABLgAECn8ZAAIPAAcJkwxvwQAGAQAPAAcJkwxvwQAGAQAAAA==.',
Ve='Velthera:BAABLgAECn8XAAIkAAgJCyJEBAAQAwAkAAgJCyJEBAAQAwABLgAFFAYJGgAYAOYcAA==.Venomlight:BAAALgADCgIJAgAAAA==.Venomstrikes:BAAALgAECgcJEwAAAA==.Venratzi:BAAALgAECgUJCwABLgAECgkJCQADAAAAAA==.Vespertina:BAAALgAECgIJAgAAAA==.',
Vi='Viscerion:BAAALgAECgUJBgAAAA==.',
Vo='Voridor:BAAALgADCgEJAQAAAA==.Voulk:BAAALgAFFAMJAwABLgAFFAkJOAAkAMAaAA==.',
Vy='Vyllan:BAABLgAECn8bAAQWAAgJAQYCEwD8AAABAAgJmgXamQAJAQAWAAYJKwQCEwD8AAACAAMJmgESQwAoAAAAAA==.',
['Ví']='Víktor:BAAALgAECgkJAQAAAA==.',
Wa='Waldgeist:BAAALgAECgUJBQABLgAECgkJIwAVAL8dAA==.Walthur:BAAALgADCgkJDQAAAA==.Waobby:BAAALgADCgIJAgAAAA==.Warrpigg:BAAALgAECgEJAQAAAA==.Waterdrinker:BAAALgAECgQJBgAAAA==.Wavybone:BAAALgAECgEJAgAAAA==.',
Wh='Whickedthur:BAAALgAECgYJBgAAAA==.Whiisper:BAAALgADCgMJAwAAAA==.Whoarlock:BAAALgADCgUJCAAAAA==.',
Wi='Wimp:BAAALgAFFAEJAQAAAA==.',
Wo='Wo:BAAALgAFFAIJAwAAAA==.',
Wu='Wutangstyle:BAAALgAECgIJAgABLgAECgkJIwAVAL8dAA==.',
Wy='Wyatta:BAAALgADCgIJAgAAAA==.',
Xe='Xelinia:BAACLgAFFH8YAAIhAAYJhRN7EQBdAQAhAAYJhRN7EQBdAQAuAAQKfyEAAiEACQk5H20MALwCACEACQk5H20MALwCAAAA.Xen:BAABLgAFFH8MAAImAAQJ8hswBQBhAQAmAAQJ8hswBQBhAQAAAA==.',
Xf='Xfortune:BAAALgADCgcJCQAAAA==.',
Xh='Xholycritz:BAAALgAECgMJBAAAAA==.Xhöly:BAAALgAECgEJAQAAAA==.',
Xu='Xuefeng:BAACLgAFFH8hAAIjAAUJ5x9HDABiAQAjAAUJ5x9HDABiAQAuAAQKfzcAAiMACQl7IL0HAMwCACMACQl7IL0HAMwCAAAA.',
Ya='Yahwae:BAAALgAECgYJCwABLgAFFAMJCAABAF0LAA==.',
Ye='Yenchmeister:BAACLgAFFH8rAAMVAAkJDBpEAwDDAQAfAAkJfRjPAwDlAQAVAAUJuRxEAwDDAQAuAAQKfygAAxUACQkgJdcJABEDABUACQkgJdcJABEDAB8AAgl3ICEoAK4AAAAA.',
Yo='Youngbusta:BAABLgAECn8zAAIEAAkJ9iJ5FQDYAgAEAAkJ9iJ5FQDYAgAAAA==.',
Yu='Yuta:BAAALgAECgYJDQAAAA==.',
Za='Zad:BAAALgADCgIJAgAAAA==.Zanin:BAAALgAECgEJAgABLgAFFAIJBQAmANUOAA==.',
Zd='Zdervish:BAAALgAECgEJAQAAAA==.',
Ze='Zenrac:BAAALgADCgUJBQAAAA==.Zeromus:BAAALgAECgIJAgAAAA==.',
Zi='Zilvanic:BAACLgAFFH8OAAIaAAQJxwgaDQCoAAAaAAQJxwgaDQCoAAAuAAQKfyQABBoACAlgEgUXAGkBABoACAn0EQUXAGkBAA8ABQlZEKf1AMQAABAAAwl8AQiDAGwAAAAA.Zilvanion:BAABLgAFFH8OAAIWAAUJ5w0GAgBYAQAWAAUJ5w0GAgBYAQAAAA==.Zingzadang:BAAALgAFFAEJAQAAAA==.',
Zo='Zourknight:BAAALgAECgcJEgAAAA==.Zourlight:BAAALgAECgQJBQAAAA==.Zourlock:BAABLgAECn8XAAQBAAYJdRC5mAALAQABAAYJAQ+5mAALAQAWAAIJJhK5KAB8AAACAAEJAAAlbwA3AAAAAA==.Zourpatch:BAAALgADCgQJCgAAAA==.',
Zu='Zulvaz:BAAALgAECgIJAwAAAA==.Zurey:BAACLgAFFH8FAAINAAQJqwKAOgCJAAANAAQJqwKAOgCJAAAuAAQKfzwAAg0ACQlWDbtbAHUBAA0ACQlWDbtbAHUBAAAA.',
Zy='Zynjamin:BAACLgAFFH81AAMOAAkJCCQ9AAADAgAcAAkJISNXAgDgAgAOAAYJ6yM9AAADAgAuAAQKfzYAAw4ACQkLJC8AANsDAA4ACQkLJC8AANsDABwAAgmrJoQQAHIAAAAA.',
['Éc']='Écho:BAAALgAECgEJAgAAAA==.',
['Ðr']='Ðrèamless:BAAALgAECgcJDgAAAA==.',
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
