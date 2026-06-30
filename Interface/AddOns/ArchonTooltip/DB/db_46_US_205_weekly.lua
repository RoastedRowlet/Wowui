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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Mage-Frost','Hunter-BeastMastery','Shaman-Enhancement','Druid-Restoration','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Evoker-Devastation','Paladin-Retribution','Paladin-Holy','Druid-Guardian','DemonHunter-Vengeance','Monk-Brewmaster','Hunter-Survival','Rogue-Assassination','Warrior-Fury','Warlock-Affliction','DeathKnight-Frost','Monk-Mistweaver','Mage-Fire','Paladin-Protection','Rogue-Subtlety','Evoker-Augmentation','Rogue-Outlaw','Warrior-Protection','Warrior-Arms','Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Windwalker','Evoker-Preservation','DemonHunter-Havoc','Druid-Feral','Hunter-Marksmanship','Druid-Balance','Mage-Arcane',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aannte:BAACLgAFFH8iAAMBAAgJyhgABgDAAQABAAYJCRcABgDAAQACAAQJ8hetBQAXAQAuAAQKfyQAAwEACQlVIowmAHgCAAEACQlGIowmAHgCAAIABAnwHvcdAGABAAAA.Aardbark:BAAALgADCgEJAQAAAA==.',
Ab='Abúsedyoû:BAAALgADCgQJBgAAAA==.',
Ac='Achtland:BAAALgAECgUJBgABLgAFFAEJAQADAAAAAA==.',
Ad='Adius:BAAALgAECgEJAQAAAA==.Adv:BAAALgAECgEJAQAAAA==.',
Ae='Aerestrix:BAAALgAECgYJBwAAAA==.',
Ai='Airvis:BAABLgAECn8yAAIEAAkJGgyIZgCwAQAEAAkJGgyIZgCwAQAAAA==.',
Al='Alacia:BAAALgAECgkJEAABLgAFFAMJCQAFAFIaAA==.Alatarr:BAAALgAECgcJEQAAAA==.Albinomonk:BAAALgADCgcJBwAAAA==.Alilea:BAAALgADCgYJBgABLgAFFAMJCQAFAFIaAA==.',
Am='Amaira:BAAALgADCgEJAQAAAA==.',
An='Anankei:BAAALgAECgUJCgAAAA==.Annastrophic:BAAALgADCgMJAwAAAA==.Anrí:BAAALgAECgEJAQAAAA==.Antaria:BAAALgADCgcJFgAAAA==.Ante:BAAALgADCgUJAQAAAA==.Antiform:BAAALgAECgMJBwAAAA==.Antpony:BAAALgAECgIJAgABLgAECgYJCgADAAAAAA==.',
Aq='Aqulara:BAAALgAECgEJAQAAAA==.',
Ar='Arcish:BAAALgAECgEJAgAAAA==.Arjun:BAABLgAECn8aAAIGAAkJAhI3DQDdAQAGAAkJAhI3DQDdAQAAAA==.Arkirla:BAAALgAECgEJAgAAAA==.Arkiyra:BAAALgAECggJDgAAAA==.Arklira:BAAALgAECgEJAQAAAA==.Arkosh:BAAALgAECgEJAgAAAA==.Arkyra:BAAALgAECgUJBwAAAA==.Aro:BAAALgAECgEJAQAAAA==.Arovix:BAABLgAECn8ZAAIHAAgJVBrvKwD6AQAHAAgJVBrvKwD6AQAAAA==.Arturogh:BAAALgAFFAIJBAABLgAFFAMJCwAIAFkUAA==.',
As='Ashwey:BAAALgADCgkJCAAAAA==.',
At='Atom:BAABLgAECn8lAAIFAAkJ2xiHHwBqAgAFAAkJ2xiHHwBqAgAAAA==.',
Au='Aubreey:BAAALgADCgcJCQAAAA==.Aureille:BAAALgAECgYJCgAAAA==.',
Aw='Awoozehl:BAACLgAFFH8qAAMJAAkJeyBLAwBdAgAJAAgJeyBLAwBdAgAIAAEJAABhTQAAAAAuAAQKfz0AAgkACQnWJpMCAHYDAAkACQnWJpMCAHYDAAAA.',
Az='Azanoth:BAAALgAECgYJCQABLgAFFAMJCwAIAFkUAA==.Azgrodon:BAABLgAECn82AAMKAAkJrBeTHQBgAgAKAAkJrBeTHQBgAgALAAMJjww+bACSAAAAAA==.Azor:BAABLgAECn8YAAIMAAgJch08HQCiAgAMAAgJch08HQCiAgAAAA==.',
Ba='Badatgame:BAAALgADCgUJBQABLgAECgIJAgADAAAAAA==.Baja:BAAALgAECgQJBAAAAA==.Baldomar:BAAALgADCgUJCAAAAA==.Banatok:BAAALgAECgEJAQAAAA==.Bangmonk:BAAALgAFFAQJBAABLgAFFAkJNAANAMciAA==.Bangungot:BAAALgADCgMJAwABLgAFFAkJNAANAMciAA==.Barristan:BAAALgAECgYJEwAAAA==.Barzalie:BAAALgAECgYJDAABLgAFFAMJAwADAAAAAA==.Bathrezz:BAABLgAECn8gAAMOAAkJoxewUADWAQAOAAkJoxewUADWAQAPAAMJWA/FaQCPAAAAAA==.',
Be='Bearlyawake:BAAALgAECgYJDAAAAA==.Bearyonce:BAABLgAFFH8GAAIQAAIJARbYJQCDAAAQAAIJARbYJQCDAAABLgAFFAcJIwARAEkRAA==.Beerbelly:BAAALgAFFAMJAwAAAA==.Beleaves:BAACLgAFFH8qAAISAAkJ/QkNDwCwAQASAAkJ/QkNDwCwAQAuAAQKf0EAAhIACQlbHbwKAIgCABIACQlbHbwKAIgCAAAA.Beorl:BAAALgADCgYJCAAAAA==.',
Bh='Bhackshots:BAABLgAECn8ZAAITAAUJjSGMLQA5AQATAAUJjSGMLQA5AQABLgAECgkJNwAUAPkjAA==.',
Bi='Bifurious:BAABLgAECn8jAAIVAAkJvx0XDwCDAgAVAAkJvx0XDwCDAgAAAA==.Bigrob:BAAALgAECgEJBQAAAA==.',
Bl='Blackprism:BAAALgAECgYJDgAAAA==.Blowmybubble:BAAALgAECgEJAQABLgAECgkJIAAFAKchAA==.Bluereindeer:BAABLgAECn8VAAIJAAkJAgvpaACUAQAJAAkJAgvpaACUAQAAAA==.',
Bo='Bobsstones:BAACLgAFFH8nAAQBAAkJvh/QAwDkAQABAAgJUhvQAwDkAQAWAAQJliXhAAA5AQACAAUJ0B4sBgANAQAuAAQKfykABAIACQlCJT0GAGwCAAEABwmkJP4bAK0CAAIABgmDJD0GAGwCABYAAwm6JOgVANUAAAAA.Bonekitty:BAAALgAECgYJBgAAAA==.Bonkulo:BAACLgAFFH8LAAIIAAMJWRQ0KAC0AAAIAAMJWRQ0KAC0AAAuAAQKfy4ABAgACQmjFT0UANABAAgACAmEFz0UANABABcAAwkACb8EAGcAAAkAAQl6CLFzATMAAAAA.Boofassist:BAABLgAECn8dAAIPAAkJ7CKABAAmAwAPAAkJ7CKABAAmAwABLgAFFAgJIgAYAJ0iAA==.Boogey:BAABLgAECn8fAAMEAAgJfQ3NggByAQAEAAgJfQ3NggByAQAZAAEJpQiNEAAyAAAAAA==.Boompowwow:BAABLgAECn8VAAILAAYJIxnmNACDAQALAAYJIxnmNACDAQAAAA==.Boomsonic:BAAALgADCgUJBQABLgAECgkJIwAVAL8dAA==.Bophadeez:BAABLgAECn8qAAQPAAgJeB4bHwAgAgAPAAcJGSEbHwAgAgAaAAgJ/ximDQDrAQAOAAYJvQ/MjABhAQABLgAFFAUJFwAYALIbAA==.',
Br='Briogan:BAABLgAFFH8GAAMJAAMJygPCLgCnAAAJAAMJygPCLgCnAAAIAAIJ7wCOPwAzAAAAAA==.Broccoliz:BAECLgAFFH85AAIHAAkJIhk5AQCdAgAHAAkJIhk5AQCdAgAuAAQKf0IAAgcACQkUH9MYAHECAAcACQkUH9MYAHECAAAA.Brokan:BAABLgAFFH8LAAIbAAMJ2AkaCwDeAAAbAAMJ2AkaCwDeAAAAAA==.Brokgar:BAAALgAECggJEAAAAA==.Brotu:BAAALgADCgIJAQAAAA==.Bruceleroy:BAAALgADCgEJAQAAAA==.Brutalsmasch:BAAALgADCgUJBQAAAA==.',
Bu='Bubu:BAAALgAECgEJAQAAAA==.Bulis:BAAALgAECgMJAwAAAA==.Bullblaster:BAAALgAECgMJBQAAAA==.',
Bw='Bwonshamdi:BAAALgAECgcJBwABLgAECgcJBwADAAAAAA==.',
['Bõ']='Bõb:BAAALgAECgYJEAAAAA==.',
Ca='Caden:BAAALgAECgQJBAABLgAFFAMJCQAFAFIaAA==.Cafca:BAABLgAECn86AAICAAkJgBgnBABCAgACAAkJgBgnBABCAgAAAA==.Cahma:BAAALgADCgYJEwAAAA==.Caitlin:BAAALgAECgEJAQABLgAFFAQJCgAFAFYZAA==.Callyour:BAAALgADCgIJAgAAAA==.Cask:BAAALgADCgYJAQAAAA==.',
Ch='Chaesol:BAAALgAFFAEJAQAAAA==.Chainsawloli:BAAALgADCgUJBQAAAA==.Changying:BAAALgAECggJDQAAAA==.Cheekung:BAAALgAECgcJEgAAAA==.Cheeseburgr:BAAALgADCgEJAQAAAA==.Choedankal:BAAALgADCgcJBwAAAA==.Chophouse:BAAALgAECgkJBgAAAA==.Chungusdelux:BAAALgAECgMJAwAAAA==.',
Cl='Clearlyumad:BAACLgAFFH8ZAAQJAAcJZRNIJQDXAQAJAAcJ+RJIJQDXAQAXAAQJywWiEwDxAAAIAAEJAADZYQAAAAAuAAQKfxsAAgkACAmPHlE8AEYCAAkACAmPHlE8AEYCAAAA.Clèrick:BAABLgAECn9BAAMPAAkJnSTcAwBfAwAPAAkJnSTcAwBfAwAOAAEJfwnFggE7AAAAAA==.',
Co='Coldcrow:BAAALgAECgEJAQAAAA==.Combination:BAACLgAFFH8YAAIYAAUJNR33BQCsAQAYAAUJNR33BQCsAQAuAAQKfxQAAhgACAn7ISgJAAgDABgACAn7ISgJAAgDAAAA.Confessor:BAAALgAECgEJAQAAAA==.Corruptions:BAAALgADCgEJAQAAAA==.',
Cr='Cromuk:BAAALgAECgEJAgAAAA==.Crustytowel:BAAALgAECgEJAQAAAA==.Crux:BAAALgADCgQJBAAAAA==.',
Cu='Cursedsofa:BAAALgAECgEJAQAAAA==.',
Cy='Cyfrin:BAAALgADCgEJAQAAAA==.Cyânide:BAAALgADCgYJDQAAAA==.',
['Cõ']='Cõurage:BAAALgAECgYJCAAAAA==.',
Da='Dabbhammer:BAAALgAFFAEJAQAAAA==.Dabbyforms:BAAALgAECgIJBAABLgAFFAEJAQADAAAAAA==.Dabbzyvoker:BAABLgAECn8gAAMcAAgJgQxZOgBCAQAcAAgJQwxZOgBCAQANAAYJowZ/IgAWAQABLgAFFAEJAQADAAAAAA==.Dallzbeep:BAAALgAECgkJCQABLgAFFAUJFwAYALIbAA==.Danathoor:BAAALgADCggJCAAAAA==.Danathor:BAAALgADCgcJBwAAAA==.Dangbro:BAAALgAECgYJEQAAAA==.Dankspank:BAAALgAECgQJCAABLgAECgYJEgADAAAAAA==.Danteus:BAAALgADCgMJAwABLgAECgUJDwADAAAAAA==.Darkrigh:BAAALgADCggJDgAAAA==.Darkwave:BAABLgAECn89AAIBAAkJMRnHIgBWAgABAAkJMRnHIgBWAgAAAA==.Darthdiddyus:BAACLgAFFH8zAAMdAAgJehzsAAAfAgAdAAcJKx7sAAAfAgAbAAQJqRWnDQAQAQAuAAQKfzIABB0ACQmeJLYAAC4DAB0ACQmaJLYAAC4DABsABwlRITwUAHICABQABAnJId0KAIIBAAAA.Datdruidguy:BAAALgADCgUJBQABLgAECgYJBgADAAAAAA==.Datlock:BAAALgADCgEJAQABLgAECgYJBgADAAAAAA==.Datshammy:BAAALgAECgYJBgAAAA==.Daviculas:BAAALgADCggJDgAAAA==.Dawghawg:BAAALgAECgQJBAAAAA==.Dawnnie:BAACLgAFFH8bAAIaAAQJwxICAgDWAAAaAAQJwxICAgDWAAAuAAQKf0IAAhoACQm+HM0GAHUCABoACQm+HM0GAHUCAAAA.Dawnte:BAABLgAECn8dAAIOAAcJHBzdYQCtAQAOAAcJHBzdYQCtAQABLgAECgUJDwADAAAAAA==.Dawsonrogers:BAACLgAFFH8JAAIVAAMJkwbiDwCsAAAVAAMJkwbiDwCsAAAuAAQKfx0AAhUACAm3ElEuAJcBABUACAm3ElEuAJcBAAAA.Dayvastate:BAABLgAECn83AAMJAAkJqhtGJgBqAgAJAAkJqhtGJgBqAgAXAAEJDxJtOwAwAAAAAA==.Dazshir:BAAALgADCgMJAwAAAA==.',
De='Deathbanana:BAABLgAFFH8cAAIJAAUJayIwPQB+AQAJAAUJayIwPQB+AQABLgAFFAkJIgAEADAfAA==.Deaththreat:BAAALgAECgQJBAABLgAECgkJJgAOALEcAA==.Deepwater:BAAALgAECgUJBQAAAA==.Delema:BAACLgAFFH8XAAIOAAYJ6xtsIQCBAQAOAAYJ6xtsIQCBAQAuAAQKfyAAAg4ACAlaIUQiAKACAA4ACAlaIUQiAKACAAAA.Democrit:BAAALgAECgYJDwAAAA==.Demonjuice:BAAALgAECgcJDAAAAA==.Derpyblinker:BAABLgAECn8VAAIEAAYJQRDu0wBHAQAEAAYJQRDu0wBHAQAAAA==.Destructer:BAABLgAECn8qAAICAAkJXxJdCADIAQACAAkJXxJdCADIAQAAAA==.Dethstar:BAAALgAECgUJCAABLgAECgkJPQABADEZAA==.Devoured:BAAALgADCgMJAwAAAA==.',
Di='Dinger:BAAALgAECgEJAQAAAA==.Dirtydinker:BAAALgAECgYJDQAAAA==.Disconneted:BAAALgADCgYJBgAAAA==.Dishwasher:BAAALgADCgIJAgAAAA==.Dixsard:BAABLgAECn83AAMUAAkJ+SM6AQAKAwAUAAkJxyM6AQAKAwAbAAcJOx9tIwDeAQAAAA==.',
Do='Dobrova:BAAALgAECgEJAQAAAA==.Doezenn:BAAALgADCgUJBQAAAA==.Dogofwar:BAAALgAECgEJAQAAAA==.Dottprepared:BAACLgAFFH8jAAIRAAcJSRGyAABRAQARAAcJSRGyAABRAQAuAAQKf0EAAhEACQmaIpcBAAcDABEACQmaIpcBAAcDAAAA.Dottyfu:BAABLgAFFH8FAAISAAMJKwl/PwCoAAASAAMJKwl/PwCoAAAAAA==.Doubted:BAAALgAECgQJBAAAAA==.',
Dr='Dracoiconic:BAAALgAECgEJAgAAAA==.Dragonboffa:BAAALgAECgcJAQAAAA==.Draul:BAAALgAECgEJAQABLgAECgkJNgAKAKwXAA==.Drexl:BAACLgAFFH8XAAMeAAcJ6hiiAgCXAQAeAAYJ6hiiAgCXAQAfAAEJAABiFgAAAAAuAAQKfzkABB8ACQlxH18HAIICAB8ACQnlHV8HAIICABUABwkSBtplABwBAB4AAgm+EVsHAE4AAAAA.Dril:BAABLgAECn8dAAMMAAgJMxlLNwDpAQAMAAgJHxlLNwDpAQARAAIJAhZvIACBAAAAAA==.Drognin:BAAALgADCgEJAQAAAA==.Drunera:BAAALgADCgQJAgAAAA==.Drunkfu:BAAALgADCgQJBAAAAA==.',
Du='Dubstep:BAAALgAECgkJAgAAAA==.Dudette:BAAALgAECgcJDAAAAA==.Dunlop:BAABLgAECn8fAAMgAAkJqBg1DgCEAgAgAAkJqBg1DgCEAgAhAAIJ9wSleQBMAAABLgAFFAMJBQAKAFEVAA==.',
Dv='Dvmcquéén:BAABLgAECn8WAAMCAAcJ5xkzCwANAgACAAcJ5xkzCwANAgABAAIJBwRHBwFOAAAAAA==.',
Dw='Dweams:BAACLgAFFH8jAAIhAAgJNRw9AQAnAgAhAAgJNRw9AQAnAgAuAAQKfzwAAyEACQmLJhIBAHIDACEACQmLJhIBAHIDACIABAmrDNE5ANgAAAAA.Dweamu:BAAALgAECgUJCQAAAA==.',
['Dâ']='Dântæ:BAAALgAECgUJDwAAAA==.',
['Då']='Dåmon:BAAALgAECgEJBAAAAA==.',
['Dö']='Döts:BAAALgADCgMJAgAAAA==.',
['Dø']='Døctøred:BAAALgAECgYJEwAAAA==.',
Ea='Easycheeze:BAAALgAECgEJAQAAAA==.',
Ec='Ectonight:BAAALgAECgUJDAAAAA==.',
Ed='Edgybob:BAAALgAECgMJAwAAAA==.',
Eg='Eggfooyung:BAACLgAFFH8iAAIYAAgJnSKdAgAXAwAYAAgJnSKdAgAXAwAuAAQKfzIAAxgACQmPIRcEAC8DABgACQmPIRcEAC8DACMABwlPCCk7ADABAAAA.Egwene:BAAALgAECgYJBwAAAA==.',
El='Eldar:BAAALgAECgUJBQAAAA==.Elfchick:BAAALgADCgEJAQAAAA==.Elhonna:BAABLgAFFH8GAAIFAAQJFQJfcAC/AAAFAAQJFQJfcAC/AAAAAA==.Elsâ:BAAALgAECgQJCAAAAA==.',
Em='Emwen:BAAALgADCgMJAwAAAA==.',
En='Endcredits:BAABLgAECn8iAAIIAAkJwg+wHAB0AQAIAAkJwg+wHAB0AQAAAA==.',
Et='Ether:BAABLgAECn8eAAILAAgJzhPUKADNAQALAAgJzhPUKADNAQAAAA==.Ettie:BAAALgAECgMJBgABLgAECgQJBgADAAAAAA==.',
Ev='Evieroot:BAAALgADCgMJAwAAAA==.Evoulker:BAACLgAFFH8rAAIkAAkJdRryAABWAgAkAAkJdRryAABWAgAuAAQKf0EAAiQACQkSH6YFAO4CACQACQkSH6YFAO4CAAAA.',
Ex='Exodyce:BAAALgAECgQJBAAAAA==.',
Ey='Eyecantsee:BAAALgADCgIJAgABLgAECgIJAgADAAAAAA==.',
Fa='Faene:BAAALgAECgUJCwABLgAECgUJBQADAAAAAA==.Faire:BAAALgADCgUJBQABLgAFFAQJCgAFAFYZAA==.Fairytale:BAACLgAFFH8oAAMiAAkJeQ9LAwDPAQAiAAkJeQ9LAwDPAQAgAAEJMwjHEwBGAAAuAAQKf0EAAyIACQlmIAAHANUCACIACQlmHQAHANUCACAABwn5HkcSAE4CAAAA.Faitza:BAAALgAECgYJCgAAAA==.Fantastico:BAAALgAECgUJDQAAAA==.',
Fe='Felheim:BAACLgAFFH8TAAIMAAYJTwnPMgBaAQAMAAYJTwnPMgBaAQAuAAQKfyoAAgwACQlbHuIBAM0BAAwACQlbHuIBAM0BAAAA.Fellitha:BAABLgAECn8UAAIIAAgJKwKiPgCVAAAIAAgJKwKiPgCVAAAAAA==.Fellithà:BAAALgAECgcJDgAAAA==.Felrend:BAAALgADCgMJAgAAAA==.Fentertained:BAAALgADCgcJCAAAAA==.',
Fi='Fiercevalkyr:BAAALgAECgkJBgAAAA==.Firsttower:BAAALgADCgIJAgAAAA==.Fists:BAACLgAFFH8XAAIYAAUJshu5GgCfAQAYAAUJshu5GgCfAQAuAAQKfzYABBgACQkXHqELAN4CABgACQkXHqELAN4CABIABAlOFrRdAMwAACMAAwlrFFRVALcAAAAA.Fizle:BAABLgAECn8bAAIkAAkJHAquFgBkAQAkAAkJHAquFgBkAQAAAA==.',
Fl='Flink:BAAALgAECgYJEwAAAA==.',
Fo='Formosa:BAAALgADCgEJAQAAAA==.Fourchainz:BAABLgAFFH8FAAIHAAMJMyRNBwAjAQAHAAMJMyRNBwAjAQABLgAFFAcJDAAkANMPAA==.',
Fr='Friend:BAAALgAECgYJEAAAAA==.Frostmoan:BAAALgAFFAEJAQAAAA==.Frostyninja:BAABLgAECn8jAAIFAAgJlgZTlwARAQAFAAgJlgZTlwARAQAAAA==.',
['Fä']='Fäye:BAAALgAECgEJAQAAAA==.',
Ga='Gabryal:BAABLgAECn8nAAIhAAkJSyCeBwDWAgAhAAkJSyCeBwDWAgAAAA==.Galthur:BAAALgAECgUJCQAAAA==.Ganbatte:BAAALgAECgYJBgAAAA==.Garchomp:BAAALgAECgUJEwAAAA==.Gargameel:BAAALgAECgMJAwAAAA==.',
Ge='Gellina:BAAALgAECgUJBgAAAA==.Georg:BAACLgAFFH8jAAIOAAcJLRzAAwDQAQAOAAcJLRzAAwDQAQAuAAQKfzIAAg4ACQm7JjADAKMDAA4ACQm7JjADAKMDAAAA.Gerbankis:BAAALgAECgMJAwAAAA==.',
Gh='Ghoul:BAACLgAFFH8HAAIJAAIJICWYPgBtAAAJAAIJICWYPgBtAAAuAAQKfxoAAgkACAmSI+gZAOECAAkACAmSI+gZAOECAAAA.Ghouligan:BAAALgAECgQJBAAAAA==.',
Gi='Giga:BAAALgADCgcJEAAAAA==.',
Gl='Glaiver:BAABLgAECn8hAAIlAAkJ5xB/GgCsAQAlAAkJ5xB/GgCsAQAAAA==.Glassjaw:BAAALgADCgUJBQAAAA==.',
Go='Goewin:BAAALgAFFAEJAQAAAA==.Gojo:BAAALgADCgYJDwAAAA==.Gorgrom:BAAALgADCgIJAgAAAA==.',
Gr='Gradiant:BAAALgAECgEJAgABLgAECgkJNgAKAKwXAA==.Greg:BAAALgAECgIJAgAAAA==.Gregorz:BAAALgAECgEJAQAAAA==.',
Gu='Gulgodeth:BAAALgAECgQJBQAAAA==.Gulgrimmar:BAACLgAFFH8pAAMLAAkJMCI2AQCSAgALAAkJMCI2AQCSAgAKAAIJWRZTcABdAAAuAAQKfzcAAgsACQnnJqwAANkDAAsACQnnJqwAANkDAAAA.Guwudanielle:BAAALgAFFAIJAgABLgAFFAQJCgAFAFYZAA==.',
['Gì']='Gìzzìmo:BAAALgAECggJEAAAAA==.',
Ha='Hailsstorm:BAAALgADCgcJEgAAAA==.Hardfeelings:BAABLgAECn8mAAIOAAkJsRzcIACEAgAOAAkJsRzcIACEAgAAAA==.Harkness:BAAALgAECgYJDwAAAA==.Hassif:BAAALgAECgEJAQAAAA==.',
He='Heimerdoodle:BAAALgAECggJEwAAAA==.Hemlawk:BAAALgAECgEJAQAAAA==.Hemus:BAAALgAECgMJAwAAAA==.Hexappeal:BAAALgAECgIJAgAAAA==.Hexed:BAABLgAECn8wAAISAAkJZw+KHwCqAQASAAkJZw+KHwCqAQAAAA==.',
Ho='Hochipo:BAAALgAECgEJAQAAAA==.',
Hu='Hughue:BAAALgADCgUJBQAAAA==.Hugs:BAAALgAECgYJCgAAAA==.Hurjek:BAAALgAFFAEJAQABLgAFFAUJGAAYADUdAA==.',
Hy='Hyuna:BAAALgAECgEJAQABLgAECgcJDgADAAAAAA==.',
Ia='Iaso:BAABLgAECn8lAAIgAAkJCBQQGgD6AQAgAAkJCBQQGgD6AQAAAA==.',
Ic='Icehide:BAAALgAECgQJBAAAAA==.Iconstar:BAAALgADCgUJBAAAAA==.',
Ig='Igneel:BAAALgADCgQJAQAAAA==.Ignored:BAABLgAFFH8KAAIPAAUJOhDKBABRAQAPAAUJOhDKBABRAQAAAA==.',
Ij='Ijustankedu:BAAALgAECgMJAwAAAA==.',
Ik='Ikiea:BAAALgAECgcJCAAAAA==.',
Il='Ilgrim:BAABLgAECn8YAAMPAAgJWxnFKgC5AQAPAAgJWxnFKgC5AQAOAAQJ+AO2LAFIAAABLgAFFAUJDgAbACkPAA==.Ilravenll:BAACLgAFFH8OAAIbAAUJKQ9PIAAiAQAbAAUJKQ9PIAAiAQAuAAQKfyEAAhsACQmQGPMLAGUCABsACQmQGPMLAGUCAAAA.Ilweaver:BAAALgAFFAEJAQABLgAFFAUJDgAbACkPAA==.Ilyana:BAACLgAFFH8lAAIEAAkJKxZJBgABAgAEAAkJKxZJBgABAgAuAAQKf0EAAgQACQk2Jm0EAGMDAAQACQk2Jm0EAGMDAAAA.',
Im='Impavido:BAAALgAECgYJBgAAAA==.',
In='Inholy:BAABLgAECn8UAAIlAAYJohdhJABVAQAlAAYJohdhJABVAQAAAA==.Insights:BAAALgADCgMJAwAAAA==.',
Is='Isabella:BAAALgAECgEJAQABLgAFFAQJCgAFAFYZAA==.',
It='Ithopel:BAABLgAECn8mAAIHAAYJASF6KAASAgAHAAYJASF6KAASAgAAAA==.',
Ja='Jalista:BAAALgADCgMJAwAAAA==.Jayc:BAACLgAFFH8fAAIEAAYJyx3mMwCZAQAEAAYJyx3mMwCZAQAuAAQKfx0AAgQACAlgHid0AOoBAAQACAlgHid0AOoBAAAA.',
Je='Jereico:BAACLgAFFH8tAAIcAAkJaCPrAACQAgAcAAkJaCPrAACQAgAuAAQKfzsAAhwACQnmJnIAAI8DABwACQnmJnIAAI8DAAAA.Jeryhn:BAACLgAFFH8mAAIPAAkJbRdmAQA1AgAPAAkJbRdmAQA1AgAuAAQKf0EAAg8ACQk8GhYTAHoCAA8ACQk8GhYTAHoCAAAA.',
Jo='Joeburrow:BAAALgAECgQJBAAAAA==.Joeynodz:BAAALgADCgYJEgAAAA==.Jortshorts:BAABLgAECn8vAAImAAkJ+AnYGgA2AQAmAAkJ+AnYGgA2AQAAAA==.',
Jr='Jray:BAABLgAECn8VAAIOAAYJGRnOZAC3AQAOAAYJGRnOZAC3AQAAAA==.',
Ju='Juggalo:BAACLgAFFH8OAAMNAAQJmSHfAQB+AQANAAQJmSHfAQB+AQAcAAEJkQY4ZwA3AAAuAAQKfysAAw0ACQllIp4BANcCAA0ACQllIp4BANcCABwAAgmJEp2JAEkAAAAA.June:BAACLgAFFH8kAAIYAAgJgBuxAQAaAgAYAAgJgBuxAQAaAgAuAAQKfz8AAxgACQlsIbMEAB0DABgACQlsIbMEAB0DACMACQkGH7MJAKoCAAAA.Juuju:BAAALgAECgYJEwAAAA==.',
Ka='Kaereth:BAAALgAFFAIJAwABLgAFFAgJKAAbAIkeAQ==.Kaldriss:BAAALgAECgEJAgAAAA==.Kalen:BAAALgADCgEJAgAAAA==.Katashimus:BAABLgAECn8YAAIEAAgJWAxpDwDFAAAEAAgJWAxpDwDFAAAAAA==.Kawasuoo:BAABLgAECn8gAAMHAAgJMR3HIgAzAgAHAAcJzhzHIgAzAgAQAAYJAAxoQAClAAAAAA==.Kaze:BAAALgAECgcJEQAAAA==.',
Ke='Kethram:BAAALgAECgYJDAAAAA==.',
Kh='Khaotichic:BAABLgAECn8lAAIFAAcJGA50kQAcAQAFAAcJGA50kQAcAQAAAA==.Khrenak:BAAALgAECgUJCwAAAA==.',
Ki='Kickpunch:BAAALgAECgYJDgAAAA==.Kirah:BAACLgAFFH8HAAIcAAIJxRzUTACbAAAcAAIJxRzUTACbAAAuAAQKfyAAAhwACQmwIWoEAEoDABwACQmwIWoEAEoDAAEuAAUUBAkKAAUAVhkA.',
Kl='Klrum:BAAALgAECgYJBQAAAA==.Kläus:BAAALgAECgEJAQAAAA==.',
Ko='Koddin:BAABLgAECn8zAAIOAAkJ6h7AJwBkAgAOAAkJ6h7AJwBkAgAAAA==.Korenchkin:BAAALgAECgEJAgAAAA==.Koreth:BAACLgAFFH8oAAMbAAgJiR5eCQALAgAbAAYJ7CBeCQALAgAUAAIJNRDKAgBcAAAuAAQKf0gAAxsACQmAJtYBAE0DABsACQmAJtYBAE0DABQACAmWGg8EAHcCAAAA.Kornholyo:BAAALgAECgEJAQAAAA==.',
Kr='Kragoth:BAAALgADCgIJAgAAAA==.',
Ku='Kutuzov:BAABLgAECn8mAAIKAAgJrhPLQACqAQAKAAgJrhPLQACqAQAAAA==.',
Kw='Kwaiza:BAAALgAECgYJDwAAAA==.',
['Ká']='Káel:BAAALgAECgMJAwAAAA==.',
La='Lailaysia:BAABLgAECn8cAAIgAAkJDyIlAwBiAwAgAAkJDyIlAwBiAwAAAA==.Lamemoosaur:BAAALgADCgIJAgABLgAECgYJCgADAAAAAA==.Laríca:BAACLgAFFH8fAAIPAAUJ7CUoCgAWAgAPAAUJ7CUoCgAWAgAuAAQKfzMAAg8ACQmDJYMCAFIDAA8ACQmDJYMCAFIDAAAA.Laustin:BAABLgAECn8kAAQTAAkJXhvBCgByAgATAAkJVhvBCgByAgAnAAYJEhCUGwDRAAAFAAIJbwWdCwFSAAAAAA==.Laustinjung:BAAALgADCgIJAQAAAA==.Laydout:BAAALgAECggJEgABLgAECgkJIAAFAG8iAA==.Laydoutyota:BAABLgAECn8gAAIFAAkJbyLmEQDCAgAFAAkJbyLmEQDCAgAAAA==.',
Le='Leag:BAABLgAECn8YAAMVAAcJFw+MQACiAQAVAAcJFw+MQACiAQAfAAEJJAmvPwA5AAAAAA==.Lemonruss:BAAALgADCgQJBAAAAA==.',
Li='Liaria:BAAALgAECgEJAQAAAA==.Lilea:BAACLgAFFH8JAAIFAAMJUhpuXQDqAAAFAAMJUhpuXQDqAAAuAAQKfzkAAwUACQnFH/kVAKQCAAUACQnFH/kVAKQCACcABwkQF2QBAPkAAAAA.Lionsmane:BAACLgAFFH8FAAIKAAMJURXLEQC/AAAKAAMJURXLEQC/AAAuAAQKfxoAAwoACQnDF9wDAH0BAAoACQnDF9wDAH0BAAYAAQkqBUVEACgAAAAA.Lithium:BAAALgADCgUJBQAAAA==.Littledeb:BAAALgAFFAEJAQAAAA==.',
Lo='Lockdots:BAAALgADCggJCwAAAA==.Lolchaosbolt:BAAALgADCgYJBgAAAA==.Lortherian:BAABLgAECn8bAAMeAAkJzSDnCABpAgAeAAkJzSDnCABpAgAVAAEJ/hb1lgBEAAAAAA==.Lowbo:BAAALgADCgUJBQAAAA==.Lowelfesteem:BAAALgADCgUJBQAAAA==.',
Lu='Lucey:BAAALgAECgEJAwAAAA==.Lucille:BAABLgAECn8aAAIEAAYJ3gfJ3wDbAAAEAAYJ3gfJ3wDbAAAAAA==.',
Ly='Lyndira:BAAALgAECgUJBQAAAA==.Lyraan:BAAALgAECgcJBwAAAA==.',
['Lä']='Läwlbringer:BAAALgAECggJDQAAAA==.',
['Lî']='Lîghtt:BAAALgADCgQJBAAAAA==.',
Ma='Mabritos:BAAALgAECgQJBQABLgAFFAYJGgAnAJ8eAA==.Maccabee:BAAALgAECgEJAQAAAA==.Malison:BAAALgAECgIJAgAAAA==.Mania:BAAALgADCgYJBgABLgAECgkJIwAVAL8dAA==.Mareth:BAAALgAECgUJBQAAAA==.Mathath:BAACLgAFFH8NAAIJAAQJ5QvCfgAJAQAJAAQJ5QvCfgAJAQAuAAQKfxwAAwkACAn4F+xXAL4BAAkACAnIF+xXAL4BAAgABAlUFacoAPkAAAAA.Mathmath:BAAALgAECgUJCgABLgAFFAEJAQADAAAAAA==.Mathoras:BAACLgAFFH8HAAIBAAMJCwvafgDHAAABAAMJCwvafgDHAAAuAAQKfxoAAgEACQkoFgA3AP0BAAEACQkoFgA3AP0BAAAA.Mazraq:BAAALgAECgEJAgABLgAECgkJNgAKAKwXAA==.',
Me='Meandean:BAAALgAECgIJBgAAAA==.Meatier:BAAALgAECgcJDwABLgAECgkJIwAVAL8dAA==.Meatless:BAAALgADCgcJDQAAAA==.Melliya:BAABLgAFFH8GAAIiAAMJeAKqOwCPAAAiAAMJeAKqOwCPAAAAAA==.Merp:BAAALgAECgMJBAAAAA==.',
Mi='Micmac:BAAALgAECgQJCQAAAA==.Milktankk:BAAALgAECgUJCAAAAA==.Milo:BAAALgAECggJDwAAAA==.Miltonroe:BAACLgAFFH8JAAIGAAMJxAYBEQC4AAAGAAMJxAYBEQC4AAAuAAQKfyoAAgYACAm/FAIPAMABAAYACAm/FAIPAMABAAAA.Mirithul:BAAALgADCgYJBwAAAA==.Mischiëf:BAABLgAECn8VAAIOAAcJvgTJ7QDNAAAOAAcJvgTJ7QDNAAAAAA==.Mitsuri:BAABLgAECn8iAAIEAAgJoQrekgCtAQAEAAgJoQrekgCtAQAAAA==.',
Mo='Modr:BAAALgAECgkJEgAAAA==.Moiraine:BAAALgAECgEJAQAAAA==.Monkynate:BAAALgAECgYJCgAAAA==.Monsterskill:BAABLgAECn8jAAQWAAgJgBseEAAsAQAWAAYJtxoeEAAsAQACAAUJhxNULQAIAQABAAUJdBknmwAHAQAAAA==.Moonerva:BAABLgAECn8iAAIoAAkJ9g4oJQCiAQAoAAkJ9g4oJQCiAQAAAA==.Morpheos:BAAALgADCgQJBAAAAA==.Mortgage:BAAALgADCgUJBQAAAA==.',
Mu='Mutsu:BAAALgADCgcJBwAAAA==.',
Mv='Mvqchx:BAAALgAECgUJCQAAAA==.',
['Mì']='Mìssy:BAABLgAECn8VAAIYAAYJiAvGCgC+AAAYAAYJiAvGCgC+AAAAAA==.',
Na='Nadrine:BAAALgAECgEJAQAAAA==.Naturelass:BAAALgADCgUJBQAAAA==.Nausicaa:BAAALgAECgEJAQAAAA==.Nawwll:BAAALgADCgMJAwAAAA==.',
Ne='Neotama:BAAALgAECggJEgAAAA==.Nethis:BAABLgAECn8nAAIhAAgJmRyjFgAVAgAhAAgJmRyjFgAVAgAAAA==.',
Ni='Niatpacgrom:BAACLgAFFH8PAAIGAAYJ4w5hCgAYAQAGAAYJ4w5hCgAYAQAuAAQKfyIAAgYACQlsGdkHAEwCAAYACQlsGdkHAEwCAAAA.Nightwang:BAAALgAECgUJBwAAAA==.Ninja:BAAALgAECgIJAgAAAA==.Nivla:BAAALgADCgMJAwAAAA==.',
No='Nobacon:BAAALgAECgYJDgAAAA==.Nokix:BAAALgADCgkJFgAAAA==.Nonorcman:BAAALgAECgIJAgAAAA==.Norah:BAAALgAECgEJAQAAAA==.Norvis:BAAALgAECgQJBQAAAA==.Notdragon:BAABLgAECn8WAAIEAAQJrQpd+AC4AAAEAAQJrQpd+AC4AAAAAA==.',
Nu='Nukeddukem:BAAALgAECgYJEgAAAA==.Numenax:BAAALgAECgEJAgAAAA==.',
Nv='Nv:BAAALgAECggJEwAAAA==.',
Ny='Nymrod:BAABLgAECn8sAAMBAAkJSBTROwDrAQABAAkJSBTROwDrAQACAAIJpgduZQBEAAAAAA==.',
['Ní']='Nír:BAAALgAECgQJBAAAAA==.',
Ob='Oben:BAAALgAECggJAQAAAA==.',
Oj='Ojou:BAAALgADCgMJAwABLgAFFAMJAwADAAAAAA==.',
On='Onepunch:BAAALgAECgQJCAAAAA==.',
Or='Orcman:BAAALgADCgIJAgABLgAECgIJAgADAAAAAA==.Orloran:BAAALgADCgIJAgAAAA==.',
Ot='Otterknight:BAAALgAECgUJBQABLgAECggJIAAHADEdAA==.',
Pa='Paladeem:BAAALgADCgEJAQAAAA==.Palthur:BAAALgAECgYJDQAAAA==.Parria:BAABLgAECn8UAAIBAAcJ8RGwdgBMAQABAAcJ8RGwdgBMAQABLgAECgkJHAAgAA8iAA==.Pasqualino:BAAALgAECgYJCgAAAA==.Passionate:BAACLgAFFH8MAAIkAAQJwAyIHADSAAAkAAQJwAyIHADSAAAuAAQKfyYAAiQACAmfFFYVAPUBACQACAmfFFYVAPUBAAAA.',
Pe='Peepis:BAAALgAECgUJBQABLgAECgkJIwAVAL8dAA==.Pennance:BAABLgAECn8iAAIPAAkJ/RuZDgCiAgAPAAkJ/RuZDgCiAgAAAA==.',
Ph='Phatmidas:BAABLgAECn87AAIOAAkJ0xnNNgAmAgAOAAkJ0xnNNgAmAgAAAA==.Philth:BAAALgAECgUJBwAAAA==.',
Pi='Pistfist:BAAALgAECgcJAQAAAA==.',
Pl='Plaguebanger:BAAALgADCgQJBAAAAA==.Plagueground:BAACLgAFFH8qAAIJAAkJBiAoAgCcAgAJAAkJBiAoAgCcAgAuAAQKf0YAAgkACQntJmgCAHgDAAkACQntJmgCAHgDAAAA.Plutonyus:BAAALgAECgEJAQAAAA==.',
Po='Poc:BAABLgAECn8ZAAIEAAYJPB3wdADoAQAEAAYJPB3wdADoAQAAAA==.Pockets:BAAALgAECgMJBwAAAA==.Poolstick:BAAALgAECgYJCAAAAA==.Potatopotato:BAACLgAFFH8UAAIbAAQJChT5GgBAAQAbAAQJChT5GgBAAQAuAAQKfyUAAhsACQnAGNIOAD4CABsACQnAGNIOAD4CAAAA.Pounces:BAABLgAECn8XAAImAAYJ/yNlEgCVAQAmAAYJ/yNlEgCVAQABLgAECgcJIAAcALUZAA==.Powerfistin:BAAALgADCgcJBwAAAA==.',
Pr='Prosecutor:BAAALgAECgUJDAAAAA==.Prozak:BAAALgAFFAIJAgABLgAFFAMJDgASAC4GAA==.Prynts:BAABLgAECn8VAAIOAAcJZh3sRAAVAgAOAAcJZh3sRAAVAgAAAA==.Prøzak:BAACLgAFFH8OAAISAAMJLgavPwCoAAASAAMJLgavPwCoAAAuAAQKfxUAAhIACAl5C5o0ACwBABIACAl5C5o0ACwBAAAA.',
Ps='Psychomidget:BAABLgAECn8dAAIiAAYJ8g5TAwA+AQAiAAYJ8g5TAwA+AQAAAA==.',
Pu='Puetrid:BAAALgADCgYJBgABLgAECgQJBAADAAAAAA==.Pulsar:BAAALgAECgQJBAAAAA==.',
Ra='Raanky:BAAALgAECgEJAQAAAA==.Radiantlight:BAACLgAFFH8GAAIiAAMJGgNHOgCaAAAiAAMJGgNHOgCaAAAuAAQKfxYAAiIACAm8EPEeANYBACIACAm8EPEeANYBAAAA.Randomly:BAAALgAECgQJCAAAAA==.Raspberries:BAAALgAECgcJBwAAAA==.Rautha:BAAALgAECgkJEgAAAA==.Rayl:BAABLgAECn8dAAMJAAcJvBpnSwDgAQAJAAcJvBpnSwDgAQAIAAEJ5QEuZwAbAAAAAA==.Razsputin:BAAALgAECgMJBwAAAA==.',
Re='Rekless:BAAALgADCgUJBQAAAA==.Rethgar:BAAALgAECgUJEgAAAA==.',
Rh='Rhaegosa:BAABLgAECn8zAAQcAAkJDxnNJwClAQAcAAcJ0xnNJwClAQAkAAQJjBZ+GwAlAQANAAQJrg0TGACaAAAAAA==.Rhavik:BAAALgAECgQJBgAAAA==.Rhekt:BAAALgAECgIJBQAAAA==.Rhok:BAAALgAECgEJAQAAAA==.Rhokladar:BAAALgAECgUJCwAAAA==.',
Ri='Rickylafleur:BAAALgAECgEJAQAAAA==.Ridcully:BAABLgAECn8bAAIHAAgJlxdoOgCrAQAHAAgJlxdoOgCrAQAAAA==.Rimath:BAAALgAECgcJBAAAAA==.Rinswind:BAAALgADCgMJAwAAAA==.',
Ro='Robopacman:BAACLgAFFH8aAAQXAAUJECHNCgBIAQAXAAQJGBnNCgBIAQAJAAQJvyAkVgBGAQAIAAEJAABhSQAAAAAuAAQKfzoABAkACQkEJRgPACMDAAkACQnyJBgPACMDAAgACAlDIo8HAKECABcAAgnhGEsoAJEAAAAA.Rodstewart:BAACLgAFFH8jAAMFAAkJiRevDQD7AQAFAAcJjRivDQD7AQAnAAUJUgzvFAD2AAAuAAQKfycAAwUACQmwJE0WAIYCAAUACAmPJE0WAIYCACcABwnbHxomAPgBAAAA.Roofeo:BAABLgAECn8hAAQCAAgJJBUVDwBNAQACAAYJmBYVDwBNAQAWAAQJIhXbGAD8AAABAAQJcgzuxQDDAAABLgAFFAMJCwAIAFkUAA==.Rosentwig:BAAALgADCgEJAQAAAA==.Rotdaddy:BAABLgAECn8uAAIJAAkJEAbfmQA2AQAJAAkJEAbfmQA2AQAAAA==.',
Ry='Ryoshin:BAAALgADCgEJAQABLgAECgYJDQADAAAAAA==.Ryzel:BAAALgADCgUJBQAAAA==.',
['Rï']='Rïn:BAAALgADCgEJAQAAAA==.',
Sa='Sabatikus:BAAALgAECgIJAgAAAA==.Salas:BAABLgAECn8UAAIBAAcJzgz6kQAXAQABAAcJzgz6kQAXAQAAAA==.Salino:BAABLgAECn8UAAMmAAcJ3BjODwC5AQAmAAcJ3BjODwC5AQAHAAUJbQZRjwCWAAAAAA==.Salinoster:BAAALgAECgEJBAABLgAECgcJFAAmANwYAA==.Salordell:BAAALgADCgIJAwAAAA==.Sam:BAAALgADCgEJAQAAAA==.Sanque:BAAALgAECgMJAwAAAA==.Sarate:BAABLgAECn8tAAIhAAgJJBFdLwBiAQAhAAgJJBFdLwBiAQAAAA==.Savannah:BAABLgAFFH8KAAIFAAQJVhkRPwAvAQAFAAQJVhkRPwAvAQAAAA==.Savvtwo:BAAALgADCgcJBwABLgAFFAkJHwAMAMgfAQ==.',
Sc='Scathach:BAABLgAECn8gAAMMAAcJ4x6mPQDRAQAMAAcJ4x6mPQDRAQAlAAQJURguRADmAAABLgAFFAEJAQADAAAAAA==.Scoop:BAAALgADCgYJBgAAAA==.Scorandom:BAAALgAECgEJAQAAAA==.',
Se='Seetani:BAAALgADCgUJBgABLgAECgQJBgADAAAAAA==.Semko:BAAALgAECgEJBAAAAA==.Seven:BAAALgAECgcJCgAAAA==.Sezra:BAAALgADCgkJAQAAAA==.',
Sh='Shamalam:BAAALgADCgEJAQAAAA==.Sharpchedda:BAABLgAECn8UAAMmAAYJKw82KADNAAAmAAYJoAk2KADNAAAQAAIJ0BOdTAB5AAAAAA==.Shei:BAAALgAECgIJAgAAAA==.Sheidon:BAAALgAECgQJBAAAAA==.Shinanigans:BAAALgAECgYJDwAAAA==.Shruikan:BAAALgADCggJDAAAAA==.',
Si='Silverbäck:BAAALgAECgYJBQABLgAECgkJGgAGAAISAA==.Silverslam:BAAALgAECgEJAQABLgAECgkJGgAGAAISAA==.Sinatra:BAAALgAECgIJBAABLgAECgcJEQADAAAAAA==.Siqodel:BAAALgADCgYJCAAAAA==.',
Sk='Skurge:BAABLgAECn8ZAAMXAAkJGwqEFwAaAQAXAAgJagqEFwAaAQAJAAQJXgdkEgCPAAAAAA==.',
Sl='Slamb:BAAALgAECgYJBwAAAA==.Slimetongue:BAAALgADCgMJAwAAAA==.Slynsoft:BAAALgAECgEJAQAAAA==.',
Sm='Smaaug:BAAALgAFFAMJBAAAAA==.',
Sn='Snuggle:BAAALgAECgEJAQAAAA==.',
So='Solstis:BAAALgAECggJDgAAAA==.Sookie:BAAALgADCgIJAgAAAA==.Sorzsnipe:BAAALgADCgQJBAAAAA==.',
Sp='Spellchücker:BAAALgAECgcJDQAAAA==.Spfzero:BAAALgAECgIJAgAAAA==.',
St='Staggered:BAACLgAFFH8PAAISAAQJoh7zHABBAQASAAQJoh7zHABBAQAuAAQKfyUAAxIACAkOIusLAM8CABIACAkOIusLAM8CACMAAQk1A9WMABwAAAAA.Starzburstz:BAAALgADCgEJAQAAAA==.Stiffbutt:BAAALgAECgMJBAAAAA==.Stonebeard:BAAALgAECggJEgAAAA==.Stoneojinray:BAAALgADCgEJAQAAAA==.Stoneorcman:BAAALgADCgcJBwABLgAECgIJAgADAAAAAA==.Stregobor:BAAALgAECgkJCQAAAA==.',
Su='Subdofu:BAAALgADCgQJBAABLgAECgcJFwAbAN0cAA==.Subtox:BAABLgAECn8XAAMbAAcJ3RxNIQDvAQAbAAcJ3RxNIQDvAQAUAAEJkgu5HwA0AAAAAA==.',
Sw='Sweetcool:BAAALgAECgUJCQABLgAECggJMAAFAP4jAA==.Sweetzeke:BAAALgAECgEJAQAAAA==.',
Sy='Syphilistjt:BAABLgAECn8WAAIiAAgJ0xLIFwDgAQAiAAgJ0xLIFwDgAQAAAA==.Syphillis:BAAALgAECgYJCgAAAA==.',
['Sá']='Sálud:BAACLgAFFH8MAAIoAAUJix8fGwBAAQAoAAUJix8fGwBAAQAuAAQKfywAAygACAmnIzgIANACACgACAmnIzgIANACABAABwmhGRgWAKMBAAAA.',
['Sê']='Sêp:BAAALgAECggJDgAAAA==.',
Ta='Takoda:BAAALgAECgEJAgAAAA==.Talivath:BAAALgAECgUJCgAAAA==.Tanissaria:BAAALgADCgIJAgAAAA==.Taranith:BAAALgAECgUJBQABLgAECggJGQAEAPoTAA==.Tarhealeon:BAABLgAECn9+AAQOAAkJ8RhYPAATAgAOAAkJIRdYPAATAgAPAAkJyRuWIQARAgAaAAcJ2xX4AQAxAQAAAA==.Tarmander:BAAALgAECgYJDgAAAA==.Taylörshift:BAAALgAECgQJBwAAAA==.',
Te='Telahnicus:BAAALgAECgEJAQAAAA==.Terranox:BAAALgADCgMJAwAAAA==.Testostauren:BAAALgAECgQJCAAAAA==.',
Th='Thabigone:BAAALgAECgYJDAAAAA==.Thalen:BAAALgAECgEJAQAAAA==.Thalnaria:BAAALgAECgYJCwAAAA==.Thetraveler:BAAALgAECgEJAQAAAA==.Threebuttons:BAAALgAECgUJDgABLgAFFAUJGQAkAHQLAA==.Thunderkis:BAABLgAECn8XAAMFAAYJHAfgrgDmAAATAAYJMQYZOgDsAAAFAAYJHAfgrgDmAAAAAA==.',
Ti='Tiewaz:BAAALgAECgYJBwABLgAECggJHwAEAFoPAA==.Tiewiz:BAABLgAECn8fAAMEAAgJWg/jjgBaAQAEAAgJEQzjjgBaAQApAAUJlw3SDQCfAAAAAA==.Titanarum:BAAALgAECgQJBAAAAA==.',
To='Toebonk:BAAALgAECgUJBQAAAA==.Tointjoker:BAAALgAECgUJBgAAAA==.Tolun:BAABLgAECn9AAAIEAAkJqhwgIACeAgAEAAkJqhwgIACeAgAAAA==.Tosan:BAAALgADCggJDgAAAA==.',
Tr='Treeplague:BAABLgAECn9EAAMhAAkJBxMsGgD0AQAhAAkJBxMsGgD0AQAiAAcJ8RVpHgDbAQAAAA==.Trypleg:BAAALgAECgMJAwAAAA==.',
Tu='Tungie:BAABLgAECn8bAAIJAAgJ0iA4QwD5AQAJAAgJ0iA4QwD5AQAAAA==.Turn:BAACLgAFFH8xAAQBAAkJBxdyCAChAQABAAgJzBhyCAChAQACAAUJwg2+AwBcAQAWAAIJmSCBFwBgAAAuAAQKf0gABAEACQlRJr8UANkCAAEACAliJb8UANkCABYAAwlJJlAdANQAAAIAAwmxJK4aAM4AAAAA.Turtleduck:BAABLgAECn8kAAINAAgJnBufBAApAgANAAgJnBufBAApAgAAAA==.Tuskbreaker:BAAALgAECgIJAgAAAA==.',
Tw='Twittytister:BAAALgADCgQJBAAAAA==.Twostrokes:BAAALgAECgEJAQAAAA==.',
Ty='Tyrese:BAAALgADCggJEAAAAA==.',
Uf='Uffin:BAAALgAECgQJBQAAAA==.',
Um='Umbryx:BAAALgAECgYJDgAAAA==.',
Un='Unagi:BAABLgAECn8cAAIGAAkJrBNgCQAnAgAGAAkJrBNgCQAnAgAAAA==.Unholy:BAAALgADCgIJAgAAAA==.Untouched:BAAALgAECgYJBwAAAA==.',
Va='Valdi:BAABLgAECn8ZAAIOAAcJkwxvwQAGAQAOAAcJkwxvwQAGAQAAAA==.',
Ve='Velthera:BAABLgAECn8XAAIkAAgJCyJEBAAQAwAkAAgJCyJEBAAQAwABLgAFFAUJGAAYADUdAA==.Venomlight:BAAALgADCgIJAgAAAA==.Venomstrikes:BAAALgAECgcJEwAAAA==.Venratzi:BAAALgAECgQJBAAAAA==.Vespertina:BAAALgAECgIJAgAAAA==.',
Vi='Viscerion:BAAALgAECgUJBgAAAA==.',
Vo='Voridor:BAAALgADCgEJAQAAAA==.Voulk:BAAALgAFFAMJAwABLgAFFAkJKwAkAHUaAA==.',
Vy='Vyllan:BAABLgAECn8bAAQWAAgJAQYCEwD8AAABAAgJmgXamQAJAQAWAAYJKwQCEwD8AAACAAMJmgESQwAoAAAAAA==.',
Wa='Waldgeist:BAAALgAECgUJBQABLgAECgkJIwAVAL8dAA==.Walthur:BAAALgADCgkJDQAAAA==.Waobby:BAAALgADCgIJAgAAAA==.Warrpigg:BAAALgAECgEJAQAAAA==.Waterdrinker:BAAALgAECgQJBgAAAA==.Wavybone:BAAALgAECgEJAgAAAA==.',
Wh='Whickedthur:BAAALgAECgYJBgAAAA==.Whiisper:BAAALgADCgMJAwAAAA==.Whoarlock:BAAALgADCgUJCAAAAA==.',
Wi='Wimp:BAAALgAFFAEJAQAAAA==.',
Wo='Wo:BAAALgAFFAIJAwAAAA==.',
Wu='Wutangstyle:BAAALgAECgIJAgABLgAECgkJIwAVAL8dAA==.',
Wy='Wyatta:BAAALgADCgIJAgAAAA==.',
Xe='Xelinia:BAACLgAFFH8XAAIhAAYJhRN7EQBdAQAhAAYJhRN7EQBdAQAuAAQKfyEAAiEACQk5H20MALwCACEACQk5H20MALwCAAAA.Xen:BAABLgAFFH8LAAImAAQJ8hswBQBhAQAmAAQJ8hswBQBhAQAAAA==.',
Xf='Xfortune:BAAALgADCgcJCQAAAA==.',
Xh='Xholycritz:BAAALgAECgMJBAAAAA==.Xhöly:BAAALgAECgEJAQAAAA==.',
Xu='Xuefeng:BAACLgAFFH8hAAIjAAUJ5x+fAgA4AQAjAAUJ5x+fAgA4AQAuAAQKfzcAAiMACQl7IL0HAMwCACMACQl7IL0HAMwCAAAA.',
Ya='Yahwae:BAAALgADCgUJBQABLgAECgkJPQABADEZAA==.',
Ye='Yenchmeister:BAACLgAFFH8jAAMVAAgJQBxEAwDDAQAVAAUJuRxEAwDDAQAfAAgJeRoiAgCaAQAuAAQKfygAAxUACQkgJdcJABEDABUACQkgJdcJABEDAB8AAgl3ICEoAK4AAAAA.',
Yo='Youngbusta:BAABLgAECn8zAAIEAAkJ9iJ5FQDYAgAEAAkJ9iJ5FQDYAgAAAA==.',
Yu='Yuta:BAAALgAECgYJDQAAAA==.',
Za='Zad:BAAALgADCgIJAgAAAA==.',
Ze='Zenrac:BAAALgADCgUJBQAAAA==.Zeromus:BAAALgAECgIJAgAAAA==.',
Zi='Zilvanic:BAACLgAFFH8OAAIaAAQJxwgaDQCoAAAaAAQJxwgaDQCoAAAuAAQKfyQABBoACAlgEgUXAGkBABoACAn0EQUXAGkBAA4ABQlZEKf1AMQAAA8AAwl8AQiDAGwAAAAA.Zilvanion:BAABLgAFFH8KAAIWAAUJ/QgNAQAqAQAWAAUJ/QgNAQAqAQAAAA==.',
Zo='Zourknight:BAAALgAECgcJEQAAAA==.Zourlight:BAAALgAECgQJBQAAAA==.Zourlock:BAABLgAECn8XAAQBAAYJdRC5mAALAQABAAYJAQ+5mAALAQAWAAIJJhK5KAB8AAACAAEJAAAlbwA3AAAAAA==.Zourpatch:BAAALgADCgQJCgAAAA==.',
Zu='Zulvaz:BAAALgAECgIJAwAAAA==.Zurey:BAABLgAECn88AAIMAAkJVg27WwB1AQAMAAkJVg27WwB1AQAAAA==.',
Zy='Zynjamin:BAACLgAFFH8kAAMNAAgJ0iE9AAADAgAcAAcJFCG9CgBNAgANAAYJ6yM9AAADAgAuAAQKfzIAAw0ACQkLJC8AANsDAA0ACQkLJC8AANsDABwAAgnTI00IAGoAAAAA.',
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
