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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Mage-Frost','Hunter-BeastMastery','Shaman-Enhancement','Druid-Restoration','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Evoker-Devastation','Paladin-Retribution','Paladin-Holy','Druid-Guardian','DemonHunter-Vengeance','Monk-Brewmaster','Hunter-Survival','Rogue-Assassination','Warrior-Fury','Warlock-Affliction','Monk-Mistweaver','Mage-Fire','Paladin-Protection','Rogue-Subtlety','DeathKnight-Frost','Evoker-Augmentation','Rogue-Outlaw','Warrior-Protection','Warrior-Arms','Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Windwalker','Evoker-Preservation','DemonHunter-Havoc','Druid-Feral','Hunter-Marksmanship','Druid-Balance','Mage-Arcane',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aannte:BAACLgAFFH8cAAMBAAgJyhgABgDAAQABAAYJCRcABgDAAQACAAQJ8hetBQAXAQAuAAQKfyQAAwEACQlVIowmAHgCAAEACQlGIowmAHgCAAIABAnwHvcdAGABAAAA.Aardbark:BAAALgADCgEJAQAAAA==.',
Ab='Abúsedyoû:BAAALgADCgQJBgAAAA==.',
Ac='Achtland:BAAALgAECgUJBgABLgAFFAEJAQADAAAAAA==.',
Ad='Adv:BAAALgAECgEJAQAAAA==.',
Ae='Aerestrix:BAAALgAECgYJBwAAAA==.',
Ai='Airvis:BAABLgAECn8yAAIEAAkJGgyHZgCwAQAEAAkJGgyHZgCwAQAAAA==.',
Al='Alacia:BAAALgAECgkJEAABLgAFFAMJCQAFAFIaAA==.Alatarr:BAAALgAECgcJEQAAAA==.Albinomonk:BAAALgADCgcJBwAAAA==.',
An='Anankei:BAAALgAECgUJCgAAAA==.Annastrophic:BAAALgADCgMJAwAAAA==.Anrí:BAAALgAECgEJAQAAAA==.Antaria:BAAALgADCgcJFgAAAA==.Ante:BAAALgADCgUJAQAAAA==.Antiform:BAAALgAECgMJBwAAAA==.Antpony:BAAALgAECgIJAgABLgAECgYJCgADAAAAAA==.',
Aq='Aqulara:BAAALgAECgEJAQAAAA==.',
Ar='Arcish:BAAALgAECgEJAgAAAA==.Arjun:BAABLgAECn8aAAIGAAkJAhI3DQDdAQAGAAkJAhI3DQDdAQAAAA==.Arkirla:BAAALgAECgEJAgAAAA==.Arkiyra:BAAALgAECggJDgAAAA==.Arklira:BAAALgAECgEJAQAAAA==.Arkosh:BAAALgAECgEJAgAAAA==.Arkyra:BAAALgAECgUJBwAAAA==.Arovix:BAABLgAECn8ZAAIHAAgJVBrzKwD6AQAHAAgJVBrzKwD6AQAAAA==.Arturogh:BAAALgAFFAIJAgABLgAFFAMJCQAIAFkUAA==.',
As='Ashwey:BAAALgADCgkJCAAAAA==.',
At='Atom:BAABLgAECn8lAAIFAAkJ2xiJHwBqAgAFAAkJ2xiJHwBqAgAAAA==.',
Au='Aubreey:BAAALgADCgcJCQAAAA==.Aureille:BAAALgAECgYJCgAAAA==.',
Aw='Awoozehl:BAACLgAFFH8lAAMJAAkJnR+5AQD1AQAJAAgJnR+5AQD1AQAIAAEJAABkTQAAAAAuAAQKfz0AAgkACQnWJpMCAHYDAAkACQnWJpMCAHYDAAAA.',
Az='Azanoth:BAAALgAECgYJCQABLgAFFAMJCQAIAFkUAA==.Azgrodon:BAABLgAECn82AAMKAAkJrBeQHQBhAgAKAAkJrBeQHQBhAgALAAMJjww+bACSAAAAAA==.Azor:BAABLgAECn8YAAIMAAgJch08HQCiAgAMAAgJch08HQCiAgAAAA==.',
Ba='Baja:BAAALgAECgQJBAAAAA==.Baldomar:BAAALgADCgUJCAAAAA==.Banatok:BAAALgAECgEJAQAAAA==.Bangmonk:BAAALgAFFAQJBAABLgAFFAkJLgANAGwgAA==.Bangungot:BAAALgADCgMJAwABLgAFFAkJLgANAGwgAA==.Barristan:BAAALgAECgYJEwAAAA==.Barzalie:BAAALgAECgYJDAABLgAFFAMJAwADAAAAAA==.Bathrezz:BAABLgAECn8gAAMOAAkJoxezUADWAQAOAAkJoxezUADWAQAPAAMJWA/HaQCPAAAAAA==.',
Be='Bearlyawake:BAAALgAECgYJBwAAAA==.Bearyonce:BAABLgAFFH8GAAIQAAIJARbWJQCDAAAQAAIJARbWJQCDAAABLgAFFAcJHwARALwPAA==.Beerbelly:BAAALgAFFAMJAwAAAA==.Beleaves:BAACLgAFFH8lAAISAAkJWwkcDwCwAQASAAkJWwkcDwCwAQAuAAQKf0EAAhIACQlbHbwKAIgCABIACQlbHbwKAIgCAAAA.Beorl:BAAALgADCgYJCAAAAA==.',
Bh='Bhackshots:BAABLgAECn8XAAITAAUJjSGJLQA5AQATAAUJjSGJLQA5AQABLgAECgkJNwAUAPkjAA==.',
Bi='Bifurious:BAABLgAECn8jAAIVAAkJvx0XDwCDAgAVAAkJvx0XDwCDAgAAAA==.Bigrob:BAAALgAECgEJBQAAAA==.',
Bl='Blackprism:BAAALgAECgUJCAAAAA==.Blowmybubble:BAAALgAECgEJAQABLgAECgkJIAAFAKchAA==.Bluereindeer:BAABLgAECn8VAAIJAAkJAgvoaACUAQAJAAkJAgvoaACUAQAAAA==.',
Bo='Bobsstones:BAACLgAFFH8fAAQBAAkJZRzQAwDkAQABAAgJBhvQAwDkAQACAAQJ6x0sBgANAQAWAAIJPSN1DAC5AAAuAAQKfykABAIACQlCJT0GAGwCAAEABwmkJP4bAK0CAAIABgmDJD0GAGwCABYAAwm6JOgVANUAAAAA.Bonekitty:BAAALgAECgYJBgAAAA==.Bonkulo:BAACLgAFFH8JAAIIAAMJWRQ6KAC0AAAIAAMJWRQ6KAC0AAAuAAQKfygAAwgACQmjFTwUANABAAgACAmEFzwUANABAAkAAQl6CK1zATMAAAAA.Boofassist:BAABLgAECn8dAAIPAAkJ7CKABAAmAwAPAAkJ7CKABAAmAwABLgAFFAgJIAAXAJ0iAA==.Boogey:BAABLgAECn8fAAMEAAgJfQ3LggByAQAEAAgJfQ3LggByAQAYAAEJpQiNEAAyAAAAAA==.Boompowwow:BAABLgAECn8VAAILAAYJIxnmNACDAQALAAYJIxnmNACDAQAAAA==.Boomsonic:BAAALgADCgUJBQABLgAECgkJIwAVAL8dAA==.Bophadeez:BAABLgAECn8qAAQPAAgJeB4bHwAgAgAPAAcJGSEbHwAgAgAZAAgJ/ximDQDrAQAOAAYJvQ/MjABhAQABLgAFFAUJFwAXALIbAA==.',
Br='Briogan:BAAALgAFFAIJAwAAAA==.Broccoliz:BAECLgAFFH8yAAIHAAkJ6RanBQC1AgAHAAkJ6RanBQC1AgAuAAQKf0IAAgcACQkUH9MYAHECAAcACQkUH9MYAHECAAAA.Brokan:BAABLgAFFH8IAAIaAAMJpAiEAwDfAAAaAAMJpAiEAwDfAAAAAA==.Brokgar:BAAALgAECggJEAAAAA==.Brotu:BAAALgADCgIJAQAAAA==.Bruceleroy:BAAALgADCgEJAQAAAA==.Brutalsmasch:BAAALgADCgUJBQAAAA==.',
Bu='Bubu:BAAALgAECgEJAQAAAA==.Bulis:BAAALgAECgMJAwAAAA==.Bullblaster:BAAALgAECgMJBQAAAA==.',
Bw='Bwonshamdi:BAAALgAECgcJBwABLgAECgcJBwADAAAAAA==.',
['Bõ']='Bõb:BAAALgAECgYJEAAAAA==.',
Ca='Caden:BAAALgAECgQJBAABLgAFFAMJCQAFAFIaAA==.Cafca:BAABLgAECn86AAICAAkJgBgnBABCAgACAAkJgBgnBABCAgAAAA==.Cahma:BAAALgADCgYJEwAAAA==.Caitlin:BAAALgAECgEJAQABLgAFFAQJCgAFAFYZAA==.Callyour:BAAALgADCgIJAgAAAA==.Cask:BAAALgADCgYJAQAAAA==.',
Ch='Chaesol:BAAALgAFFAEJAQAAAA==.Chainsawloli:BAAALgADCgUJBQAAAA==.Changying:BAAALgAECggJDQAAAA==.Cheekung:BAAALgAECgcJEgAAAA==.Cheeseburgr:BAAALgADCgEJAQAAAA==.Choedankal:BAAALgADCgcJBwAAAA==.Chophouse:BAAALgAECgkJBgAAAA==.Chungusdelux:BAAALgAECgMJAwAAAA==.',
Cl='Clearlyumad:BAACLgAFFH8YAAQJAAcJZRNcJQDXAQAJAAcJ+RJcJQDXAQAbAAQJywWiEwDxAAAIAAEJAADbYQAAAAAuAAQKfxsAAgkACAmPHlE8AEYCAAkACAmPHlE8AEYCAAAA.Clèrick:BAABLgAECn8+AAMPAAkJnSTdAwBfAwAPAAkJnSTdAwBfAwAOAAEJfwnCggE7AAAAAA==.',
Co='Coldcrow:BAAALgAECgEJAQAAAA==.Combination:BAACLgAFFH8UAAIXAAUJpxylAgBlAQAXAAUJpxylAgBlAQAuAAQKfxQAAhcACAn7ISsJAAgDABcACAn7ISsJAAgDAAAA.Confessor:BAAALgAECgEJAQAAAA==.Corruptions:BAAALgADCgEJAQAAAA==.',
Cr='Cromuk:BAAALgAECgEJAgAAAA==.Crustytowel:BAAALgAECgEJAQAAAA==.Crux:BAAALgADCgQJBAAAAA==.',
Cu='Cursedsofa:BAAALgAECgEJAQAAAA==.',
Cy='Cyfrin:BAAALgADCgEJAQAAAA==.Cyânide:BAAALgADCgYJDQAAAA==.',
['Cõ']='Cõurage:BAAALgAECgYJCAAAAA==.',
Da='Dabbhammer:BAAALgAFFAEJAQAAAA==.Dabbyforms:BAAALgAECgIJBAABLgAFFAEJAQADAAAAAA==.Dabbzyvoker:BAABLgAECn8gAAMcAAgJgQxXOgBCAQAcAAgJQwxXOgBCAQANAAYJowZ/IgAWAQABLgAFFAEJAQADAAAAAA==.Dallzbeep:BAAALgAECgkJCQABLgAFFAUJFwAXALIbAA==.Danathoor:BAAALgADCggJCAAAAA==.Danathor:BAAALgADCgcJBwAAAA==.Dangbro:BAAALgAECgYJEQAAAA==.Dankspank:BAAALgAECgQJCAABLgAECgYJEQADAAAAAA==.Danteus:BAAALgADCgMJAwABLgAECgUJDwADAAAAAA==.Darkrigh:BAAALgADCggJDgAAAA==.Darkwave:BAABLgAECn89AAIBAAkJMRnEIgBWAgABAAkJMRnEIgBWAgAAAA==.Darthdiddyus:BAACLgAFFH8xAAMdAAgJehzsAAAfAgAdAAcJKx7sAAAfAgAaAAQJHhSnDQAQAQAuAAQKfzIABB0ACQmeJLYAAC4DAB0ACQmaJLYAAC4DABoABwlRITwUAHICABQABAnJId0KAIIBAAAA.Datdruidguy:BAAALgADCgUJBQABLgAECgYJBgADAAAAAA==.Datlock:BAAALgADCgEJAQABLgAECgYJBgADAAAAAA==.Datshammy:BAAALgAECgYJBgAAAA==.Daviculas:BAAALgADCggJDgAAAA==.Dawghawg:BAAALgAECgQJBAAAAA==.Dawnnie:BAACLgAFFH8XAAIZAAQJixLyCADnAAAZAAQJixLyCADnAAAuAAQKf0IAAhkACQm+HM0GAHUCABkACQm+HM0GAHUCAAAA.Dawnte:BAABLgAECn8dAAIOAAcJHBzeYQCtAQAOAAcJHBzeYQCtAQABLgAECgUJDwADAAAAAA==.Dawsonrogers:BAACLgAFFH8HAAIVAAMJFQYfPwCrAAAVAAMJFQYfPwCrAAAuAAQKfxwAAhUACAlwEVAuAJcBABUACAlwEVAuAJcBAAAA.Dayvastate:BAABLgAECn83AAMJAAkJqhtGJgBqAgAJAAkJqhtGJgBqAgAbAAEJDxJuOwAwAAAAAA==.Dazshir:BAAALgADCgMJAwAAAA==.',
De='Deathbanana:BAABLgAFFH8cAAIJAAUJayI7PQB+AQAJAAUJayI7PQB+AQABLgAFFAkJGwAEAJQaAA==.Deaththreat:BAAALgAECgQJBAABLgAECgkJIgAOAIobAA==.Deepwater:BAAALgAECgUJBQAAAA==.Delema:BAACLgAFFH8WAAIOAAYJ6xuDIQCBAQAOAAYJ6xuDIQCBAQAuAAQKfyAAAg4ACAlaIUQiAKACAA4ACAlaIUQiAKACAAAA.Democrit:BAAALgAECgYJDwAAAA==.Demonjuice:BAAALgAECgcJDAAAAA==.Derpyblinker:BAABLgAECn8VAAIEAAYJQRDu0wBHAQAEAAYJQRDu0wBHAQAAAA==.Destructer:BAABLgAECn8qAAICAAkJXxJdCADIAQACAAkJXxJdCADIAQAAAA==.Dethstar:BAAALgAECgUJCAABLgAECgkJPQABADEZAA==.Devoured:BAAALgADCgMJAwAAAA==.',
Di='Dinger:BAAALgAECgEJAQAAAA==.Dirtydinker:BAAALgAECgYJDQAAAA==.Disconneted:BAAALgADCgYJBgAAAA==.Dishwasher:BAAALgADCgIJAgAAAA==.Dixsard:BAABLgAECn83AAMUAAkJ+SM6AQAKAwAUAAkJxyM6AQAKAwAaAAcJOx9tIwDeAQAAAA==.',
Do='Dobrova:BAAALgAECgEJAQAAAA==.Doezenn:BAAALgADCgUJBQAAAA==.Dogofwar:BAAALgAECgEJAQAAAA==.Dottprepared:BAACLgAFFH8fAAIRAAcJvA+yAABRAQARAAcJvA+yAABRAQAuAAQKf0EAAhEACQmaIpcBAAcDABEACQmaIpcBAAcDAAAA.Dottyfu:BAABLgAFFH8FAAISAAMJKwmNPwCoAAASAAMJKwmNPwCoAAAAAA==.Doubted:BAAALgAECgQJBAAAAA==.',
Dr='Dracoiconic:BAAALgAECgEJAgAAAA==.Dragonboffa:BAAALgAECgcJAQAAAA==.Draul:BAAALgAECgEJAQABLgAECgkJNgAKAKwXAA==.Drexl:BAACLgAFFH8RAAIeAAUJERS6BQARAQAeAAUJERS6BQARAQAuAAQKfzgABB8ACQkjHl8HAIICAB8ACQnlHV8HAIICABUABwkSBtplABwBAB4AAgmHDHo7AHAAAAAA.Dril:BAABLgAECn8dAAMMAAgJMxlKNwDpAQAMAAgJHxlKNwDpAQARAAIJAhZvIACBAAAAAA==.Drognin:BAAALgADCgEJAQAAAA==.Drunkfu:BAAALgADCgQJBAAAAA==.',
Du='Dubstep:BAAALgAECgkJAgAAAA==.Dudette:BAAALgAECgcJDAAAAA==.Dunlop:BAABLgAECn8fAAMgAAkJqBg1DgCEAgAgAAkJqBg1DgCEAgAhAAIJ9wSceQBMAAABLgAECggJFAAKANQWAA==.',
Dv='Dvmcquéén:BAABLgAECn8WAAMCAAcJ5xkzCwANAgACAAcJ5xkzCwANAgABAAIJBwRHBwFOAAAAAA==.',
Dw='Dweams:BAACLgAFFH8fAAIhAAgJjxs9AQAnAgAhAAgJjxs9AQAnAgAuAAQKfzwAAyEACQmLJhMBAHIDACEACQmLJhMBAHIDACIABAmrDNE5ANgAAAAA.Dweamu:BAAALgAECgUJCQAAAA==.',
['Dâ']='Dântæ:BAAALgAECgUJDwAAAA==.',
['Då']='Dåmon:BAAALgAECgEJBAAAAA==.',
['Dö']='Döts:BAAALgADCgMJAgAAAA==.',
['Dø']='Døctøred:BAAALgAECgYJEwAAAA==.',
Ec='Ectonight:BAAALgAECgUJDAAAAA==.',
Ed='Edgybob:BAAALgAECgMJAwAAAA==.',
Eg='Eggfooyung:BAACLgAFFH8gAAIXAAgJnSKeAgAXAwAXAAgJnSKeAgAXAwAuAAQKfzIAAxcACQmPIRcEAC8DABcACQmPIRcEAC8DACMABwlPCCk7ADABAAAA.Egwene:BAAALgAECgYJBwAAAA==.',
El='Eldar:BAAALgAECgUJBQAAAA==.Elfchick:BAAALgADCgEJAQAAAA==.Elhonna:BAABLgAFFH8GAAIFAAQJFQJicAC/AAAFAAQJFQJicAC/AAAAAA==.Elsâ:BAAALgAECgQJCAAAAA==.',
Em='Emwen:BAAALgADCgMJAwAAAA==.',
En='Endcredits:BAABLgAECn8iAAIIAAkJwg+uHAB0AQAIAAkJwg+uHAB0AQAAAA==.',
Et='Ether:BAABLgAECn8eAAILAAgJzhPUKADNAQALAAgJzhPUKADNAQAAAA==.Ettie:BAAALgAECgMJBgABLgAECgQJBgADAAAAAA==.',
Ev='Evieroot:BAAALgADCgMJAwAAAA==.Evoulker:BAACLgAFFH8lAAIkAAkJbRryAABWAgAkAAkJbRryAABWAgAuAAQKf0EAAiQACQkSH6YFAO4CACQACQkSH6YFAO4CAAAA.',
Ex='Exodyce:BAAALgAECgQJBAAAAA==.',
Ey='Eyecantsee:BAAALgADCgIJAgABLgAECgIJAgADAAAAAA==.',
Fa='Faene:BAAALgAECgQJCgABLgAECgUJBQADAAAAAA==.Faire:BAAALgADCgUJBQABLgAFFAQJCgAFAFYZAA==.Fairytale:BAACLgAFFH8iAAMiAAkJ0g5LAwDPAQAiAAkJ0g5LAwDPAQAgAAEJMwjHEwBGAAAuAAQKf0EAAyIACQlmIAAHANUCACIACQlmHQAHANUCACAABwn5HkcSAE4CAAAA.Faitza:BAAALgAECgYJCgAAAA==.Fantastico:BAAALgAECgUJDQAAAA==.',
Fe='Felheim:BAACLgAFFH8SAAIMAAYJTwnWMgBaAQAMAAYJTwnWMgBaAQAuAAQKfyQAAgwACQlrHJgdAGMCAAwACQlrHJgdAGMCAAAA.Fellitha:BAABLgAECn8UAAIIAAgJKwKfPgCVAAAIAAgJKwKfPgCVAAAAAA==.Fellithà:BAAALgAECgcJDgAAAA==.Felrend:BAAALgADCgMJAgAAAA==.Fentertained:BAAALgADCgcJCAAAAA==.',
Fi='Fiercevalkyr:BAAALgAECgkJBgAAAA==.Firsttower:BAAALgADCgIJAgAAAA==.Fists:BAACLgAFFH8XAAIXAAUJshu5GgCfAQAXAAUJshu5GgCfAQAuAAQKfzYABBcACQkXHqMLAN4CABcACQkXHqMLAN4CABIABAlOFrRdAMwAACMAAwlrFFJVALcAAAAA.Fizle:BAABLgAECn8bAAIkAAkJHAquFgBkAQAkAAkJHAquFgBkAQAAAA==.',
Fl='Flink:BAAALgAECgYJEwAAAA==.',
Fo='Fourchainz:BAABLgAFFH8FAAIHAAMJMyQ7AgAkAQAHAAMJMyQ7AgAkAQABLgAFFAcJDAAkANMPAA==.',
Fr='Friend:BAAALgAECgYJEAAAAA==.Frostmoan:BAAALgAFFAEJAQAAAA==.Frostyninja:BAABLgAECn8jAAIFAAgJlgZUlwARAQAFAAgJlgZUlwARAQAAAA==.',
Ga='Gabryal:BAABLgAECn8nAAIhAAkJSyCeBwDWAgAhAAkJSyCeBwDWAgAAAA==.Galthur:BAAALgAECgUJCQAAAA==.Ganbatte:BAAALgAECgYJBgAAAA==.Garchomp:BAAALgAECgUJEwAAAA==.Gargameel:BAAALgAECgMJAwAAAA==.',
Ge='Gellina:BAAALgAECgUJBgAAAA==.Georg:BAACLgAFFH8eAAIOAAcJAhsPAwDIAQAOAAcJAhsPAwDIAQAuAAQKfzIAAg4ACQm7JjADAKMDAA4ACQm7JjADAKMDAAAA.Gerbankis:BAAALgAECgMJAwAAAA==.',
Gh='Ghoul:BAACLgAFFH8GAAIJAAIJICU/sADCAAAJAAIJICU/sADCAAAuAAQKfxoAAgkACAmSI+gZAOECAAkACAmSI+gZAOECAAAA.Ghouligan:BAAALgAECgQJBAAAAA==.',
Gi='Giga:BAAALgADCgcJEAAAAA==.',
Gl='Glaiver:BAABLgAECn8hAAIlAAkJ5xCAGgCsAQAlAAkJ5xCAGgCsAQAAAA==.Glassjaw:BAAALgADCgUJBQAAAA==.',
Go='Goewin:BAAALgAFFAEJAQAAAA==.Gojo:BAAALgADCgYJDwAAAA==.Gorgrom:BAAALgADCgIJAgAAAA==.',
Gr='Gradiant:BAAALgAECgEJAgABLgAECgkJNgAKAKwXAA==.Greg:BAAALgAECgIJAgAAAA==.Gregorz:BAAALgAECgEJAQAAAA==.',
Gu='Gulgodeth:BAAALgAECgQJBQAAAA==.Gulgrimmar:BAACLgAFFH8kAAMLAAkJnh7aAwCiAgALAAkJnh7aAwCiAgAKAAIJWRZScABdAAAuAAQKfzcAAgsACQnnJqwAANkDAAsACQnnJqwAANkDAAAA.Guwudanielle:BAAALgAFFAIJAgABLgAFFAQJCgAFAFYZAA==.',
['Gì']='Gìzzìmo:BAAALgAECggJDwAAAA==.',
Ha='Hailsstorm:BAAALgADCgcJEgAAAA==.Hardfeelings:BAABLgAECn8iAAIOAAkJihvaIACEAgAOAAkJihvaIACEAgAAAA==.Harkness:BAAALgAECgYJDwAAAA==.Hassif:BAAALgAECgEJAQAAAA==.',
He='Heimerdoodle:BAAALgAECggJEwAAAA==.Hemlawk:BAAALgAECgEJAQAAAA==.Hemus:BAAALgAECgMJAwAAAA==.Hexed:BAABLgAECn8vAAISAAkJZw+IHwCqAQASAAkJZw+IHwCqAQAAAA==.',
Ho='Hochipo:BAAALgAECgEJAQAAAA==.',
Hu='Hughue:BAAALgADCgUJBQAAAA==.Hugs:BAAALgAECgYJCgAAAA==.Hurjek:BAAALgAFFAEJAQABLgAFFAUJFAAXAKccAA==.',
Hy='Hyuna:BAAALgAECgEJAQABLgAECgcJDgADAAAAAA==.',
Ia='Iaso:BAABLgAECn8lAAIgAAkJCBQNGgD6AQAgAAkJCBQNGgD6AQAAAA==.',
Ic='Iconstar:BAAALgADCgUJBAAAAA==.',
Ig='Igneel:BAAALgADCgQJAQAAAA==.Ignored:BAABLgAFFH8GAAIPAAUJwgxEAgD5AAAPAAUJwgxEAgD5AAAAAA==.',
Ij='Ijustankedu:BAAALgAECgMJAwAAAA==.',
Ik='Ikiea:BAAALgAECgcJCAAAAA==.',
Il='Ilgrim:BAABLgAECn8YAAMPAAgJWxnDKgC5AQAPAAgJWxnDKgC5AQAOAAQJ+AO2LAFIAAABLgAFFAUJDgAaACkPAA==.Ilravenll:BAACLgAFFH8OAAIaAAUJKQ9WIAAiAQAaAAUJKQ9WIAAiAQAuAAQKfyEAAhoACQmQGPELAGUCABoACQmQGPELAGUCAAAA.Ilweaver:BAAALgAFFAEJAQABLgAFFAUJDgAaACkPAA==.Ilyana:BAACLgAFFH8gAAIEAAkJoRUAFABQAgAEAAkJoRUAFABQAgAuAAQKf0EAAgQACQk2Jm0EAGMDAAQACQk2Jm0EAGMDAAAA.',
Im='Impavido:BAAALgAECgYJBgAAAA==.',
In='Inholy:BAABLgAECn8UAAIlAAYJohddJABVAQAlAAYJohddJABVAQAAAA==.Insights:BAAALgADCgMJAwAAAA==.',
Is='Isabella:BAAALgAECgEJAQABLgAFFAQJCgAFAFYZAA==.',
It='Ithopel:BAABLgAECn8mAAIHAAYJASF6KAASAgAHAAYJASF6KAASAgAAAA==.',
Ja='Jalista:BAAALgADCgMJAwAAAA==.Jayc:BAACLgAFFH8fAAIEAAYJyx0HNACZAQAEAAYJyx0HNACZAQAuAAQKfx0AAgQACAlgHid0AOoBAAQACAlgHid0AOoBAAAA.',
Je='Jereico:BAACLgAFFH8nAAIcAAkJQiLrAACQAgAcAAkJQiLrAACQAgAuAAQKfzsAAhwACQnmJnIAAI8DABwACQnmJnIAAI8DAAAA.Jeryhn:BAACLgAFFH8hAAIPAAkJbRdEAgDZAQAPAAkJbRdEAgDZAQAuAAQKf0EAAg8ACQk8GhYTAHoCAA8ACQk8GhYTAHoCAAAA.',
Jo='Joeburrow:BAAALgAECgQJBAAAAA==.Joeynodz:BAAALgADCgYJEgAAAA==.Jortshorts:BAABLgAECn8vAAImAAkJ+AnYGgA2AQAmAAkJ+AnYGgA2AQAAAA==.',
Jr='Jray:BAABLgAECn8VAAIOAAYJGRnOZAC3AQAOAAYJGRnOZAC3AQAAAA==.',
Ju='Juggalo:BAACLgAFFH8OAAMNAAQJmSHgAQB+AQANAAQJmSHgAQB+AQAcAAEJkQY6ZwA3AAAuAAQKfysAAw0ACQllIp4BANcCAA0ACQllIp4BANcCABwAAgmJEpqJAEkAAAAA.June:BAACLgAFFH8fAAIXAAgJxRmxAQAaAgAXAAgJxRmxAQAaAgAuAAQKfz8AAxcACQlsIbMEAB0DABcACQlsIbMEAB0DACMACQkGH7IJAKoCAAAA.Juuju:BAAALgAECgYJEwAAAA==.',
Ka='Kaldriss:BAAALgAECgEJAgAAAA==.Kalen:BAAALgADCgEJAgAAAA==.Katashimus:BAAALgAECggJEgAAAA==.Kawasuoo:BAABLgAECn8gAAMHAAgJMR3IIgAzAgAHAAcJzhzIIgAzAgAQAAYJAAxmQAClAAAAAA==.Kaze:BAAALgAECgcJEQAAAA==.',
Ke='Kethram:BAAALgAECgMJBAAAAA==.',
Kh='Khaotichic:BAABLgAECn8jAAIFAAYJFA92kQAcAQAFAAYJFA92kQAcAQAAAA==.Khrenak:BAAALgAECgUJCwAAAA==.',
Ki='Kickpunch:BAAALgAECgYJDgAAAA==.Kirah:BAACLgAFFH8HAAIcAAIJmBzeTACaAAAcAAIJmBzeTACaAAAuAAQKfyAAAhwACQmwIWoEAEoDABwACQmwIWoEAEoDAAEuAAUUBAkKAAUAVhkA.',
Kl='Klrum:BAAALgAECgYJBQAAAA==.Kläus:BAAALgAECgEJAQAAAA==.',
Ko='Koddin:BAABLgAECn8zAAIOAAkJ6h7BJwBkAgAOAAkJ6h7BJwBkAgAAAA==.Korenchkin:BAAALgAECgEJAgAAAA==.Koreth:BAACLgAFFH8kAAMaAAgJLRtrCQALAgAaAAYJAB1rCQALAgAUAAIJNRD1AABgAAAuAAQKf0cAAxoACQmAJtYBAE0DABoACQmAJtYBAE0DABQACAmWGg8EAHcCAAAA.Kornholyo:BAAALgAECgEJAQAAAA==.',
Kr='Kragoth:BAAALgADCgIJAgAAAA==.',
Ku='Kutuzov:BAABLgAECn8lAAIKAAcJPBXFQACqAQAKAAcJPBXFQACqAQAAAA==.',
Kw='Kwaiza:BAAALgAECgYJDwAAAA==.',
['Ká']='Káel:BAAALgAECgMJAwAAAA==.',
La='Lailaysia:BAABLgAECn8cAAIgAAkJDyImAwBiAwAgAAkJDyImAwBiAwAAAA==.Lamemoosaur:BAAALgADCgIJAgABLgAECgYJCgADAAAAAA==.Laríca:BAACLgAFFH8cAAIPAAUJ7CUqCgAWAgAPAAUJ7CUqCgAWAgAuAAQKfzEAAg8ACQmDJYMCAFIDAA8ACQmDJYMCAFIDAAAA.Laustin:BAABLgAECn8kAAQTAAkJXhvDCgByAgATAAkJVhvDCgByAgAnAAYJEhCUGwDRAAAFAAIJbwWZCwFSAAAAAA==.Laustinjung:BAAALgADCgIJAQAAAA==.Laydout:BAAALgAECggJEgABLgAECgkJIAAFAG8iAA==.Laydoutyota:BAABLgAECn8gAAIFAAkJbyLpEQDCAgAFAAkJbyLpEQDCAgAAAA==.',
Le='Leag:BAABLgAECn8YAAMVAAcJFw+MQACiAQAVAAcJFw+MQACiAQAfAAEJJAmvPwA5AAAAAA==.Lemonruss:BAAALgADCgQJBAAAAA==.',
Li='Liaria:BAAALgAECgEJAQAAAA==.Lilea:BAACLgAFFH8JAAIFAAMJUhpvXQDqAAAFAAMJUhpvXQDqAAAuAAQKfzUAAwUACQnFH/kVAKQCAAUACQnFH/kVAKQCACcABwnrEfc0AJYBAAAA.Lionsmane:BAABLgAECn8UAAMKAAgJ1BZOJQAvAgAKAAgJ1BZOJQAvAgAGAAEJKgVERAAoAAAAAA==.Lithium:BAAALgADCgUJBQAAAA==.Littledeb:BAAALgAFFAEJAQAAAA==.',
Lo='Lockdots:BAAALgADCgcJCQAAAA==.Lolchaosbolt:BAAALgADCgYJBgAAAA==.Lortherian:BAABLgAECn8YAAMeAAgJyiDoCABpAgAeAAgJyiDoCABpAgAVAAEJ/hbvlgBEAAAAAA==.Lowbo:BAAALgADCgUJBQAAAA==.Lowelfesteem:BAAALgADCgUJBQAAAA==.',
Lu='Lucey:BAAALgAECgEJAwAAAA==.Lucille:BAABLgAECn8aAAIEAAYJ3gfE3wDbAAAEAAYJ3gfE3wDbAAAAAA==.',
Ly='Lyndira:BAAALgAECgUJBQAAAA==.',
['Lä']='Läwlbringer:BAAALgAECggJDQAAAA==.',
['Lî']='Lîghtt:BAAALgADCgQJBAAAAA==.',
Ma='Mabritos:BAAALgAECgQJBQABLgAFFAYJGgAnAJ8eAA==.Maccabee:BAAALgAECgEJAQAAAA==.Malison:BAAALgAECgIJAgAAAA==.Mania:BAAALgADCgYJBgABLgAECgkJIwAVAL8dAA==.Mathath:BAACLgAFFH8NAAIJAAQJ5QvJfgAJAQAJAAQJ5QvJfgAJAQAuAAQKfxwAAwkACAn4F+hXAL4BAAkACAnIF+hXAL4BAAgABAlUFacoAPkAAAAA.Mathmath:BAAALgAECgUJCgABLgAFFAEJAQADAAAAAA==.Mathoras:BAACLgAFFH8HAAIBAAMJCwvwfgDHAAABAAMJCwvwfgDHAAAuAAQKfxoAAgEACQkoFv42AP0BAAEACQkoFv42AP0BAAAA.Mazraq:BAAALgAECgEJAgABLgAECgkJNgAKAKwXAA==.',
Me='Meandean:BAAALgAECgIJBgAAAA==.Meatier:BAAALgAECgcJDwABLgAECgkJIwAVAL8dAA==.Meatless:BAAALgADCgcJDQAAAA==.Melliya:BAABLgAFFH8GAAIiAAMJeAKuOwCPAAAiAAMJeAKuOwCPAAAAAA==.Merp:BAAALgAECgMJBAAAAA==.',
Mi='Micmac:BAAALgAECgQJCQAAAA==.Milktankk:BAAALgAECgUJCAAAAA==.Milo:BAAALgAECgcJDQAAAA==.Miltonroe:BAACLgAFFH8JAAIGAAMJxAYDEQC4AAAGAAMJxAYDEQC4AAAuAAQKfyoAAgYACAm/FAMPAMABAAYACAm/FAMPAMABAAAA.Mirithul:BAAALgADCgYJBwAAAA==.Mischiëf:BAABLgAECn8VAAIOAAcJvgTF7QDNAAAOAAcJvgTF7QDNAAAAAA==.Mitsuri:BAABLgAECn8iAAIEAAgJoQrekgCtAQAEAAgJoQrekgCtAQAAAA==.',
Mo='Modr:BAAALgAECgkJEgAAAA==.Moiraine:BAAALgAECgEJAQAAAA==.Monkynate:BAAALgAECgYJCgAAAA==.Monsterskill:BAABLgAECn8jAAQWAAgJgBseEAAsAQAWAAYJtxoeEAAsAQACAAUJhxNULQAIAQABAAUJdBkjmwAHAQAAAA==.Moonerva:BAABLgAECn8iAAIoAAkJ9g4kJQCiAQAoAAkJ9g4kJQCiAQAAAA==.Morpheos:BAAALgADCgQJBAAAAA==.Mortgage:BAAALgADCgUJBQAAAA==.',
Mu='Mutsu:BAAALgADCgcJBwAAAA==.',
Mv='Mvqchx:BAAALgAECgUJCQAAAA==.',
['Mì']='Mìssy:BAAALgAECgYJDwAAAA==.',
Na='Naturelass:BAAALgADCgUJBQAAAA==.Nausicaa:BAAALgAECgEJAQAAAA==.Nawwll:BAAALgADCgMJAwAAAA==.',
Ne='Neotama:BAAALgAECggJEgAAAA==.Nethis:BAABLgAECn8nAAIhAAgJmRyjFgAVAgAhAAgJmRyjFgAVAgAAAA==.',
Ni='Niatpacgrom:BAACLgAFFH8OAAIGAAUJVBBkCgAYAQAGAAUJVBBkCgAYAQAuAAQKfyIAAgYACQlsGdgHAEwCAAYACQlsGdgHAEwCAAAA.Nivla:BAAALgADCgMJAwAAAA==.',
No='Nobacon:BAAALgAECgYJDQAAAA==.Nokix:BAAALgADCgkJDgAAAA==.Nonorcman:BAAALgAECgIJAgAAAA==.Norah:BAAALgAECgEJAQAAAA==.Norvis:BAAALgAECgQJBQAAAA==.Notdragon:BAABLgAECn8WAAIEAAQJrQpY+AC4AAAEAAQJrQpY+AC4AAAAAA==.',
Nu='Nukeddukem:BAAALgAECgYJEgAAAA==.Numenax:BAAALgAECgEJAgAAAA==.',
Nv='Nv:BAAALgAECggJEwAAAA==.',
Ny='Nymrod:BAABLgAECn8sAAMBAAkJSBTPOwDrAQABAAkJSBTPOwDrAQACAAIJpgduZQBEAAAAAA==.',
['Ní']='Nír:BAAALgAECgQJBAAAAA==.',
Ob='Oben:BAAALgAECggJAQAAAA==.',
Oj='Ojou:BAAALgADCgMJAwABLgAFFAMJAwADAAAAAA==.',
On='Onepunch:BAAALgAECgQJCAAAAA==.',
Or='Orcman:BAAALgADCgIJAgABLgAECgIJAgADAAAAAA==.Orloran:BAAALgADCgIJAgAAAA==.',
Ot='Otterknight:BAAALgAECgUJBQABLgAECggJIAAHADEdAA==.',
Pa='Palthur:BAAALgAECgYJDQAAAA==.Parria:BAABLgAECn8UAAIBAAcJ8RGtdgBMAQABAAcJ8RGtdgBMAQABLgAECgkJHAAgAA8iAA==.Pasqualino:BAAALgAECgYJCgAAAA==.Passionate:BAACLgAFFH8MAAIkAAQJwAyLHADSAAAkAAQJwAyLHADSAAAuAAQKfyYAAiQACAmfFFYVAPUBACQACAmfFFYVAPUBAAAA.',
Pe='Peepis:BAAALgAECgUJBQABLgAECgkJIwAVAL8dAA==.Pennance:BAABLgAECn8iAAIPAAkJ/RuZDgCiAgAPAAkJ/RuZDgCiAgAAAA==.',
Ph='Phatmidas:BAABLgAECn84AAIOAAkJyBnRNgAmAgAOAAkJyBnRNgAmAgAAAA==.Philth:BAAALgAECgUJBwAAAA==.',
Pi='Pistfist:BAAALgAECgcJAQAAAA==.',
Pl='Plaguebanger:BAAALgADCgQJBAAAAA==.Plagueground:BAACLgAFFH8lAAIJAAgJBiBpCACqAgAJAAgJBiBpCACqAgAuAAQKf0UAAgkACQnhJmgCAHgDAAkACQnhJmgCAHgDAAAA.Plutonyus:BAAALgAECgEJAQAAAA==.',
Po='Poc:BAABLgAECn8ZAAIEAAYJPB3wdADoAQAEAAYJPB3wdADoAQAAAA==.Pockets:BAAALgAECgMJBwAAAA==.Poolstick:BAAALgAECgYJCAAAAA==.Potatopotato:BAACLgAFFH8SAAIaAAQJmhP+GgBAAQAaAAQJmhP+GgBAAQAuAAQKfyUAAhoACQnAGM8OAD4CABoACQnAGM8OAD4CAAAA.Pounces:BAABLgAECn8WAAImAAYJhiBjEgCVAQAmAAYJhiBjEgCVAQAAAA==.Powerfistin:BAAALgADCgcJBwAAAA==.',
Pr='Prosecutor:BAAALgAECgUJDAAAAA==.Prozak:BAAALgAECgUJEQABLgAFFAMJDQASAC4GAA==.Prynts:BAABLgAECn8VAAIOAAcJZh3sRAAVAgAOAAcJZh3sRAAVAgAAAA==.Prøzak:BAACLgAFFH8NAAISAAMJLga8PwCoAAASAAMJLga8PwCoAAAuAAQKfxUAAhIACAl5C5c0ACwBABIACAl5C5c0ACwBAAAA.',
Ps='Psychomidget:BAAALgAECgYJEgAAAA==.',
Pu='Puetrid:BAAALgADCgYJBgABLgAECgQJBAADAAAAAA==.',
Ra='Raanky:BAAALgAECgEJAQAAAA==.Radiantlight:BAACLgAFFH8GAAIiAAMJGgNMOgCaAAAiAAMJGgNMOgCaAAAuAAQKfxYAAiIACAm8EO4eANYBACIACAm8EO4eANYBAAAA.Randomly:BAAALgAECgQJCAAAAA==.Raspberries:BAAALgAECgcJBwAAAA==.Rautha:BAAALgAECgkJEgAAAA==.Rayl:BAABLgAECn8dAAMJAAcJvBpiSwDgAQAJAAcJvBpiSwDgAQAIAAEJ5QEuZwAbAAAAAA==.Razsputin:BAAALgAECgMJBwAAAA==.',
Re='Rekless:BAAALgADCgUJBQAAAA==.Rethgar:BAAALgAECgUJEgAAAA==.',
Rh='Rhaegosa:BAABLgAECn8zAAQcAAkJDxnMJwClAQAcAAcJ0xnMJwClAQAkAAQJjBZ9GwAlAQANAAQJrg0TGACaAAAAAA==.Rhavik:BAAALgAECgQJBgAAAA==.Rhekt:BAAALgAECgIJBQAAAA==.Rhok:BAAALgAECgEJAQAAAA==.Rhokladar:BAAALgAECgUJCwAAAA==.',
Ri='Rickylafleur:BAAALgAECgEJAQAAAA==.Ridcully:BAABLgAECn8bAAIHAAgJlxdrOgCrAQAHAAgJlxdrOgCrAQAAAA==.Rimath:BAAALgAECgcJBAAAAA==.Rinswind:BAAALgADCgMJAwAAAA==.',
Ro='Robopacman:BAACLgAFFH8aAAQbAAUJECHPCgBIAQAbAAQJGBnPCgBIAQAJAAQJvyAqVgBGAQAIAAEJAABkSQAAAAAuAAQKfzoABAkACQkEJRgPACMDAAkACQnyJBgPACMDAAgACAlDIpIHAKECABsAAgnhGE0oAJEAAAAA.Rodstewart:BAACLgAFFH8dAAMFAAkJCBezDQD7AQAFAAcJ+hezDQD7AQAnAAUJUgzvFAD2AAAuAAQKfycAAwUACQmwJE0WAIYCAAUACAmPJE0WAIYCACcABwnbHxomAPgBAAAA.Roofeo:BAABLgAECn8hAAQCAAgJJBUVDwBNAQACAAYJmBYVDwBNAQAWAAQJIhXcGAD8AAABAAQJcgzwxQDDAAABLgAFFAMJCQAIAFkUAA==.Rosentwig:BAAALgADCgEJAQAAAA==.Rotdaddy:BAABLgAECn8rAAIJAAkJCgaIBgCTAAAJAAkJCgaIBgCTAAAAAA==.',
Ry='Ryoshin:BAAALgADCgEJAQABLgAECgYJDQADAAAAAA==.Ryzel:BAAALgADCgUJBQAAAA==.',
['Rï']='Rïn:BAAALgADCgEJAQAAAA==.',
Sa='Sabatikus:BAAALgAECgIJAgAAAA==.Salas:BAABLgAECn8UAAIBAAcJzgz2kQAXAQABAAcJzgz2kQAXAQAAAA==.Salino:BAABLgAECn8UAAMmAAcJ3BjMDwC5AQAmAAcJ3BjMDwC5AQAHAAUJbQZTjwCWAAAAAA==.Salinoster:BAAALgAECgEJBAABLgAECgcJFAAmANwYAA==.Salordell:BAAALgADCgIJAwAAAA==.Sam:BAAALgADCgEJAQAAAA==.Sanque:BAAALgAECgMJAwAAAA==.Sarate:BAABLgAECn8rAAIhAAgJ3A5aLwBiAQAhAAgJ3A5aLwBiAQAAAA==.Savannah:BAABLgAFFH8KAAIFAAQJVhkVPwAvAQAFAAQJVhkVPwAvAQAAAA==.Savvtwo:BAAALgADCgcJBwABLgAFFAgJHQAMAPEiAQ==.',
Sc='Scathach:BAABLgAECn8gAAMMAAcJ4x6jPQDRAQAMAAcJ4x6jPQDRAQAlAAQJURguRADmAAABLgAFFAEJAQADAAAAAA==.Scoop:BAAALgADCgYJBgAAAA==.Scorandom:BAAALgAECgEJAQAAAA==.',
Se='Seetani:BAAALgADCgUJBgABLgAECgQJBgADAAAAAA==.Semko:BAAALgAECgEJBAAAAA==.Seven:BAAALgAECgcJCgAAAA==.Sezra:BAAALgADCgkJAQAAAA==.',
Sh='Shamalam:BAAALgADCgEJAQAAAA==.Sharpchedda:BAABLgAECn8UAAMmAAYJKw81KADNAAAmAAYJoAk1KADNAAAQAAIJ0BOyBABTAAAAAA==.Shei:BAAALgAECgIJAgAAAA==.Sheidon:BAAALgAECgQJBAAAAA==.Shinanigans:BAAALgAECgYJDwAAAA==.Shruikan:BAAALgADCggJDAAAAA==.',
Si='Silverslam:BAAALgAECgEJAQABLgAECgkJGgAGAAISAA==.Sinatra:BAAALgAECgIJBAABLgAECgcJEQADAAAAAA==.Siqodel:BAAALgADCgYJCAAAAA==.',
Sk='Skurge:BAABLgAECn8WAAMbAAgJagqEFwAaAQAbAAgJagqEFwAaAQAJAAMJ+wRDLQFyAAAAAA==.',
Sl='Slamb:BAAALgAECgYJBwAAAA==.Slimetongue:BAAALgADCgMJAwAAAA==.Slynsoft:BAAALgAECgEJAQAAAA==.',
Sm='Smaaug:BAAALgAFFAMJBAAAAA==.',
Sn='Snuggle:BAAALgAECgEJAQAAAA==.',
So='Solstis:BAAALgAECggJDgAAAA==.Sookie:BAAALgADCgIJAgAAAA==.Sorzsnipe:BAAALgADCgQJBAAAAA==.',
Sp='Spellchücker:BAAALgAECgcJDQAAAA==.Spfzero:BAAALgAECgIJAgAAAA==.',
St='Staggered:BAACLgAFFH8PAAISAAQJoh77HABBAQASAAQJoh77HABBAQAuAAQKfyUAAxIACAkOIusLAM8CABIACAkOIusLAM8CACMAAQk1A9WMABwAAAAA.Stiffbutt:BAAALgAECgIJAgAAAA==.Stonebeard:BAAALgAECgQJBwAAAA==.Stoneojinray:BAAALgADCgEJAQAAAA==.Stoneorcman:BAAALgADCgcJBwABLgAECgIJAgADAAAAAA==.',
Su='Subdofu:BAAALgADCgQJBAABLgAECgcJFwAaAN0cAA==.Subtox:BAABLgAECn8XAAMaAAcJ3RxNIQDvAQAaAAcJ3RxNIQDvAQAUAAEJkgu5HwA0AAAAAA==.',
Sw='Sweetcool:BAAALgAECgUJCQABLgAECggJLgAFAP4jAA==.Sweetzeke:BAAALgAECgEJAQAAAA==.',
Sy='Syphilistjt:BAABLgAECn8WAAIiAAgJ0xLIFwDgAQAiAAgJ0xLIFwDgAQAAAA==.Syphillis:BAAALgAECgYJCgAAAA==.',
['Sá']='Sálud:BAACLgAFFH8MAAIoAAUJix8oGwBAAQAoAAUJix8oGwBAAQAuAAQKfywAAygACAmnIzgIANACACgACAmnIzgIANACABAABwmhGRgWAKMBAAAA.',
['Sê']='Sêp:BAAALgAECggJDgAAAA==.',
Ta='Takoda:BAAALgAECgEJAgAAAA==.Talivath:BAAALgAECgUJCgAAAA==.Tanissaria:BAAALgADCgIJAgAAAA==.Taranith:BAAALgAECgUJBQABLgAECggJGQAEAPoTAA==.Tarhealeon:BAABLgAECn98AAQOAAkJwhdbPAATAgAOAAkJ+xVbPAATAgAPAAkJyRuWIQARAgAZAAYJAhgTAQD3AAAAAA==.Tarmander:BAAALgAECgYJDgAAAA==.Taylörshift:BAAALgAECgQJBwAAAA==.',
Te='Telahnicus:BAAALgAECgEJAQAAAA==.Terranox:BAAALgADCgMJAwAAAA==.Testostauren:BAAALgAECgQJCAAAAA==.',
Th='Thabigone:BAAALgAECgYJDAAAAA==.Thalen:BAAALgAECgEJAQAAAA==.Thalnaria:BAAALgAECgYJCwAAAA==.Thetraveler:BAAALgAECgEJAQAAAA==.Threebuttons:BAAALgAECgUJDgABLgAFFAUJGAAkAHQLAA==.Thunderkis:BAABLgAECn8XAAMFAAYJHAfargDmAAATAAYJMQYWOgDsAAAFAAYJHAfargDmAAAAAA==.',
Ti='Tiewaz:BAAALgAECgYJBwABLgAECggJHwAEAFoPAA==.Tiewiz:BAABLgAECn8fAAMEAAgJWg/gjgBaAQAEAAgJEQzgjgBaAQApAAUJlw3SDQCfAAAAAA==.Titanarum:BAAALgAECgQJBAAAAA==.',
To='Tointjoker:BAAALgAECgUJBgAAAA==.Tolun:BAABLgAECn8/AAIEAAkJqhwhIACeAgAEAAkJqhwhIACeAgAAAA==.Tosan:BAAALgADCggJDgAAAA==.',
Tr='Treeplague:BAABLgAECn9EAAMhAAkJBxMrGgD0AQAhAAkJBxMrGgD0AQAiAAcJ8RVnHgDbAQAAAA==.Trypleg:BAAALgAECgMJAwAAAA==.',
Tu='Tungie:BAABLgAECn8bAAIJAAgJ0iA1QwD5AQAJAAgJ0iA1QwD5AQAAAA==.Turn:BAACLgAFFH8sAAQBAAkJchRyCAChAQABAAgJ2RVyCAChAQACAAUJwg2+AwBcAQAWAAIJmSCAFwBgAAAuAAQKf0gABAEACQlRJr8UANkCAAEACAliJb8UANkCABYAAwlJJlEdANQAAAIAAwmxJK0aAM4AAAAA.Turtleduck:BAABLgAECn8kAAINAAgJnBufBAApAgANAAgJnBufBAApAgAAAA==.Tuskbreaker:BAAALgAECgIJAgAAAA==.',
Tw='Twittytister:BAAALgADCgQJBAAAAA==.Twostrokes:BAAALgAECgEJAQAAAA==.',
Ty='Tyrese:BAAALgADCggJEAAAAA==.',
Uf='Uffin:BAAALgAECgQJBQAAAA==.',
Um='Umbryx:BAAALgAECgYJDgAAAA==.',
Un='Unagi:BAABLgAECn8cAAIGAAkJrBNgCQAnAgAGAAkJrBNgCQAnAgAAAA==.Unholy:BAAALgADCgIJAgAAAA==.Untouched:BAAALgAECgUJBgAAAA==.',
Va='Valdi:BAABLgAECn8ZAAIOAAcJkwxuwQAGAQAOAAcJkwxuwQAGAQAAAA==.',
Ve='Velthera:BAABLgAECn8XAAIkAAgJCyJEBAAQAwAkAAgJCyJEBAAQAwABLgAFFAUJFAAXAKccAA==.Venomlight:BAAALgADCgIJAgAAAA==.Venomstrikes:BAAALgAECgcJEwAAAA==.Venratzi:BAAALgAECgQJBAAAAA==.Vespertina:BAAALgAECgIJAgAAAA==.',
Vi='Viscerion:BAAALgAECgUJBgAAAA==.',
Vo='Voridor:BAAALgADCgEJAQAAAA==.Voulk:BAAALgAFFAMJAwABLgAFFAkJJQAkAG0aAA==.',
Vy='Vyllan:BAABLgAECn8bAAQWAAgJAQYCEwD8AAABAAgJmgXWmQAJAQAWAAYJKwQCEwD8AAACAAMJmgERQwAoAAAAAA==.',
Wa='Waldgeist:BAAALgAECgUJBQABLgAECgkJIwAVAL8dAA==.Walthur:BAAALgADCgkJDQAAAA==.Waobby:BAAALgADCgIJAgAAAA==.Warrpigg:BAAALgAECgEJAQAAAA==.Waterdrinker:BAAALgAECgQJBgAAAA==.Wavybone:BAAALgAECgEJAgAAAA==.',
Wh='Whickedthur:BAAALgAECgYJBgAAAA==.Whiisper:BAAALgADCgMJAwAAAA==.Whoarlock:BAAALgADCgUJCAAAAA==.',
Wi='Wimp:BAAALgAFFAEJAQAAAA==.',
Wo='Wo:BAAALgAFFAIJAwAAAA==.',
Wu='Wutangstyle:BAAALgAECgIJAgABLgAECgkJIwAVAL8dAA==.',
Wy='Wyatta:BAAALgADCgIJAgAAAA==.',
Xe='Xelinia:BAACLgAFFH8WAAIhAAYJhRN6EQBdAQAhAAYJhRN6EQBdAQAuAAQKfyEAAiEACQk5H20MALwCACEACQk5H20MALwCAAAA.Xen:BAABLgAFFH8LAAImAAQJ8hsvBQBhAQAmAAQJ8hsvBQBhAQAAAA==.',
Xf='Xfortune:BAAALgADCgcJCQAAAA==.',
Xh='Xholycritz:BAAALgAECgMJBAAAAA==.Xhöly:BAAALgAECgEJAQAAAA==.',
Xu='Xuefeng:BAACLgAFFH8gAAIjAAUJ5x9HDABiAQAjAAUJ5x9HDABiAQAuAAQKfzcAAiMACQl7IL0HAMwCACMACQl7IL0HAMwCAAAA.',
Ya='Yahwae:BAAALgADCgUJBQABLgAECgkJPQABADEZAA==.',
Ye='Yenchmeister:BAACLgAFFH8fAAMVAAgJZRtEAwDDAQAVAAUJuRxEAwDDAQAfAAcJxRkAAgBiAQAuAAQKfygAAxUACQkgJdcJABEDABUACQkgJdcJABEDAB8AAgl3ICEoAK4AAAAA.',
Yo='Youngbusta:BAABLgAECn8zAAIEAAkJ9iJ9FQDYAgAEAAkJ9iJ9FQDYAgAAAA==.',
Yu='Yuta:BAAALgAECgYJDQAAAA==.',
Za='Zad:BAAALgADCgIJAgAAAA==.',
Ze='Zenrac:BAAALgADCgUJBQAAAA==.Zeromus:BAAALgAECgIJAgAAAA==.',
Zi='Zilvanic:BAACLgAFFH8OAAIZAAQJxwgaDQCoAAAZAAQJxwgaDQCoAAAuAAQKfyQABBkACAlgEgUXAGkBABkACAn0EQUXAGkBAA4ABQlZEKL1AMQAAA8AAwl8AQiDAGwAAAAA.Zilvanion:BAABLgAFFH8GAAIWAAMJoQS8DAC0AAAWAAMJoQS8DAC0AAAAAA==.',
Zo='Zourknight:BAAALgAECgcJEAAAAA==.Zourlight:BAAALgAECgQJBQAAAA==.Zourlock:BAABLgAECn8XAAQBAAYJdRC2mAALAQABAAYJAQ+2mAALAQAWAAIJJhK5KAB8AAACAAEJAAAlbwA3AAAAAA==.Zourpatch:BAAALgADCgQJCgAAAA==.',
Zu='Zulvaz:BAAALgAECgIJAwAAAA==.Zurey:BAABLgAECn88AAIMAAkJVg28WwB1AQAMAAkJVg28WwB1AQAAAA==.',
Zy='Zynjamin:BAACLgAFFH8hAAMNAAgJ0iE9AAADAgAcAAcJFCHRCgBLAgANAAYJ6yM9AAADAgAuAAQKfzAAAw0ACQkLJC8AANsDAA0ACQkLJC8AANsDABwAAQlLIy0DAGkAAAAA.',
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
