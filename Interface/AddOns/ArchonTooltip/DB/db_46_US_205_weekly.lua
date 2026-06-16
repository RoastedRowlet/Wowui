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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Mage-Frost','Hunter-BeastMastery','Shaman-Enhancement','Druid-Restoration','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Evoker-Devastation','Paladin-Retribution','Paladin-Holy','Monk-Brewmaster','Hunter-Survival','Rogue-Assassination','Warrior-Fury','Warlock-Affliction','Monk-Mistweaver','Mage-Fire','Paladin-Protection','Rogue-Subtlety','DeathKnight-Frost','Evoker-Augmentation','Rogue-Outlaw','DemonHunter-Vengeance','Warrior-Protection','Warrior-Arms','Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Windwalker','Evoker-Preservation','DemonHunter-Havoc','Druid-Feral','Druid-Guardian','Hunter-Marksmanship','Druid-Balance','Mage-Arcane',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aannte:BAACLgAFFH8ZAAMBAAgJyhgABgDAAQABAAYJCRcABgDAAQACAAQJ8hetBQAXAQAuAAQKfyIAAwEACQlVIowmAHgCAAEACQlGIowmAHgCAAIABAnwHvcdAGABAAAA.Aardbark:BAAALgADCgEJAQAAAA==.',
Ab='Abúsedyoû:BAAALgADCgQJBgAAAA==.',
Ac='Achtland:BAAALgAECgUJBgABLgAFFAEJAQADAAAAAA==.',
Ad='Adekai:BAAALgAECgYJEQAAAA==.Adv:BAAALgAECgEJAQAAAA==.',
Ae='Aerestrix:BAAALgAECgYJBwAAAA==.',
Ai='Airvis:BAABLgAECn8yAAIEAAkJGgzoZACxAQAEAAkJGgzoZACxAQAAAA==.',
Al='Alacia:BAAALgAECgkJEAABLgAFFAMJCQAFAFIaAA==.Alatarr:BAAALgAECgcJEQAAAA==.Albinomonk:BAAALgADCgcJBwAAAA==.',
An='Anankei:BAAALgAECgUJCgAAAA==.Annastrophic:BAAALgADCgMJAwAAAA==.Anrí:BAAALgAECgEJAQAAAA==.Antaria:BAAALgADCgcJFgAAAA==.Ante:BAAALgADCgUJAQAAAA==.Antiform:BAAALgAECgMJBwAAAA==.Antpony:BAAALgAECgIJAgABLgAECgYJCgADAAAAAA==.',
Aq='Aqulara:BAAALgAECgEJAQAAAA==.',
Ar='Arcish:BAAALgAECgEJAgAAAA==.Arjun:BAABLgAECn8aAAIGAAkJAhLnDADfAQAGAAkJAhLnDADfAQAAAA==.Arkirla:BAAALgAECgEJAgAAAA==.Arkiyra:BAAALgAECggJDgAAAA==.Arklira:BAAALgAECgEJAQAAAA==.Arkosh:BAAALgAECgEJAgAAAA==.Arkyra:BAAALgAECgUJBwAAAA==.Arovix:BAABLgAECn8ZAAIHAAgJVBp+KwD6AQAHAAgJVBp+KwD6AQAAAA==.Arturogh:BAAALgAECgUJBQABLgAFFAMJCQAIAFkUAA==.',
As='Ashwey:BAAALgADCgkJCAAAAA==.',
At='Atom:BAABLgAECn8fAAIFAAkJgxXALwAZAgAFAAkJgxXALwAZAgAAAA==.',
Au='Aubreey:BAAALgADCgcJCQAAAA==.Aureille:BAAALgAECgYJCgAAAA==.',
Aw='Awoozehl:BAACLgAFFH8gAAMJAAgJeR98FwAUAgAJAAcJeR98FwAUAgAIAAEJAACmSgAAAAAuAAQKfz0AAgkACQnWJmMCAHgDAAkACQnWJmMCAHgDAAAA.',
Az='Azanoth:BAAALgAECgYJCQABLgAFFAMJCQAIAFkUAA==.Azgrodon:BAABLgAECn82AAMKAAkJrBcCHQBhAgAKAAkJrBcCHQBhAgALAAMJjww+bACSAAAAAA==.Azor:BAABLgAECn8YAAIMAAgJch08HQCiAgAMAAgJch08HQCiAgAAAA==.',
Ba='Baja:BAAALgAECgQJBAAAAA==.Baldomar:BAAALgADCgUJCAAAAA==.Banatok:BAAALgAECgEJAQAAAA==.Bangmonk:BAAALgAFFAQJBAABLgAFFAkJIQANAMgfAA==.Bangungot:BAAALgADCgMJAwABLgAFFAkJIQANAMgfAA==.Barristan:BAAALgAECgUJEQAAAA==.Barzalie:BAAALgAECgYJDAABLgAFFAMJAwADAAAAAA==.Bathrezz:BAABLgAECn8gAAMOAAkJoxeXTgDaAQAOAAkJoxeXTgDaAQAPAAMJWA9JaACRAAAAAA==.',
Be='Bearyonce:BAAALgAFFAIJAwAAAA==.Beerbelly:BAAALgAFFAMJAwAAAA==.Beleaves:BAACLgAFFH8hAAIQAAkJvgYrDgCwAQAQAAkJvgYrDgCwAQAuAAQKf0EAAhAACQlbHY0KAIkCABAACQlbHY0KAIkCAAAA.Beorl:BAAALgADCgYJCAAAAA==.',
Bh='Bhackshots:BAABLgAECn8XAAIRAAUJjSEDLQA9AQARAAUJjSEDLQA9AQABLgAECgkJNQASAPkjAA==.',
Bi='Bifurious:BAABLgAECn8jAAITAAkJvx3JDgCFAgATAAkJvx3JDgCFAgAAAA==.Bigrob:BAAALgAECgEJBQAAAA==.',
Bl='Blackprism:BAAALgAECgUJBQAAAA==.Blowmybubble:BAAALgAECgEJAQABLgAECgkJIAAFAKchAA==.Bluereindeer:BAABLgAECn8VAAIJAAkJAguOZgCXAQAJAAkJAguOZgCXAQAAAA==.',
Bo='Bobsstones:BAACLgAFFH8dAAQBAAgJlB7QAwDkAQABAAcJWB3QAwDkAQACAAQJ6x0sBgANAQAUAAIJPSPUCwC6AAAuAAQKfykABAIACQlCJT0GAGwCAAEABwmkJP4bAK0CAAIABgmDJD0GAGwCABQAAwm6JOgVANUAAAAA.Bonekitty:BAAALgAECgYJBgAAAA==.Bonkulo:BAACLgAFFH8JAAIIAAMJWRT+JgC4AAAIAAMJWRT+JgC4AAAuAAQKfygAAwgACQmjFd8TANIBAAgACAmEF98TANIBAAkAAQl6CJxrATQAAAAA.Boofassist:BAABLgAECn8dAAIPAAkJ7CKABAAmAwAPAAkJ7CKABAAmAwABLgAFFAgJHwAVAJ0iAA==.Boogey:BAABLgAECn8fAAMEAAgJfQ3QgAByAQAEAAgJfQ3QgAByAQAWAAEJpQiNEAAyAAAAAA==.Boompowwow:BAABLgAECn8VAAILAAYJIxnmNACDAQALAAYJIxnmNACDAQAAAA==.Boomsonic:BAAALgADCgUJBQABLgAECgkJIwATAL8dAA==.Bophadeez:BAABLgAECn8qAAQPAAgJeB4bHwAgAgAPAAcJGSEbHwAgAgAXAAgJ/xhiDQDrAQAOAAYJvQ/MjABhAQAAAA==.',
Br='Broccoliz:BAECLgAFFH8tAAIHAAkJFxQuBQC2AgAHAAkJFxQuBQC2AgAuAAQKf0IAAgcACQkUH9MYAHECAAcACQkUH9MYAHECAAAA.Brokan:BAABLgAFFH8FAAIYAAMJHgfbKgDPAAAYAAMJHgfbKgDPAAAAAA==.Brokgar:BAAALgAECggJEAAAAA==.Brotu:BAAALgADCgIJAQAAAA==.Bruceleroy:BAAALgADCgEJAQAAAA==.Brutalsmasch:BAAALgADCgUJBQAAAA==.',
Bu='Bubu:BAAALgAECgEJAQAAAA==.Bulis:BAAALgAECgMJAwAAAA==.Bullblaster:BAAALgAECgMJBQAAAA==.',
Bw='Bwonshamdi:BAAALgAECgcJBwABLgAECgcJBwADAAAAAA==.',
['Bõ']='Bõb:BAAALgAECgQJDgAAAA==.',
Ca='Caden:BAAALgAECgQJBAABLgAFFAMJCQAFAFIaAA==.Cafca:BAABLgAECn86AAICAAkJgBgCBABDAgACAAkJgBgCBABDAgAAAA==.Cahma:BAAALgADCgYJEAAAAA==.Caitlin:BAAALgAECgEJAQABLgAFFAQJCgAFAFYZAA==.Callyour:BAAALgADCgIJAgAAAA==.Cask:BAAALgADCgYJAQAAAA==.',
Ch='Chaesol:BAAALgAFFAEJAQAAAA==.Chainsawloli:BAAALgADCgUJBQAAAA==.Changying:BAAALgAECggJDQAAAA==.Cheekung:BAAALgAECgcJEgAAAA==.Cheeseburgr:BAAALgADCgEJAQAAAA==.Choedankal:BAAALgADCgcJBwAAAA==.Chophouse:BAAALgAECgkJBgAAAA==.Chungusdelux:BAAALgAECgMJAwAAAA==.',
Cl='Clearlyumad:BAACLgAFFH8XAAQJAAcJOhNFIgDZAQAJAAcJzhJFIgDZAQAZAAQJywWbEgDxAAAIAAEJAAClXgAAAAAuAAQKfxsAAgkACAmPHlE8AEYCAAkACAmPHlE8AEYCAAAA.Clèrick:BAABLgAECn87AAMPAAkJ8SO5AwBgAwAPAAkJ8SO5AwBgAwAOAAEJfwkVfAE7AAAAAA==.',
Co='Coldcrow:BAAALgAECgEJAQAAAA==.Combination:BAACLgAFFH8QAAIVAAUJqBv7GACgAQAVAAUJqBv7GACgAQAuAAQKfxQAAhUACAn7IfEIAAgDABUACAn7IfEIAAgDAAAA.Confessor:BAAALgAECgEJAQAAAA==.Corruptions:BAAALgADCgEJAQAAAA==.',
Cr='Cromuk:BAAALgAECgEJAgAAAA==.Crux:BAAALgADCgQJBAAAAA==.',
Cu='Cursedsofa:BAAALgAECgEJAQAAAA==.',
Cy='Cyfrin:BAAALgADCgEJAQAAAA==.Cyânide:BAAALgADCgYJDQAAAA==.',
['Cõ']='Cõurage:BAAALgAECgYJCAAAAA==.',
Da='Dabbhammer:BAAALgAFFAEJAQAAAA==.Dabbyforms:BAAALgAECgIJAwABLgAFFAEJAQADAAAAAA==.Dabbzyvoker:BAABLgAECn8gAAMaAAgJgQwbOQBFAQAaAAgJQwwbOQBFAQANAAYJowZ/IgAWAQABLgAFFAEJAQADAAAAAA==.Dallzbeep:BAAALgAECgkJCQABLgAFFAUJFgAVALIbAA==.Danathoor:BAAALgADCggJCAAAAA==.Danathor:BAAALgADCgcJBwAAAA==.Dangbro:BAAALgAECgYJEQAAAA==.Dankspank:BAAALgAECgQJCAABLgAECgYJDAADAAAAAA==.Danteus:BAAALgADCgMJAwABLgAECgUJDwADAAAAAA==.Darkrigh:BAAALgADCggJDgAAAA==.Darkwave:BAABLgAECn88AAIBAAkJfRgnIgBXAgABAAkJfRgnIgBXAgAAAA==.Darthdiddyus:BAACLgAFFH8vAAMbAAgJehzLAAAhAgAbAAcJKx7LAAAhAgAYAAQJHhSnDQAQAQAuAAQKfzIABBsACQmeJLAAAC8DABsACQmaJLAAAC8DABgABwlRITwUAHICABIABAnJId0KAIIBAAAA.Datdruidguy:BAAALgADCgUJBQABLgAECgYJBgADAAAAAA==.Datlock:BAAALgADCgEJAQABLgAECgYJBgADAAAAAA==.Datshammy:BAAALgAECgYJBgAAAA==.Daviculas:BAAALgADCggJDgAAAA==.Dawghawg:BAAALgAECgQJBAAAAA==.Dawnnie:BAACLgAFFH8TAAIXAAQJthAyCQDeAAAXAAQJthAyCQDeAAAuAAQKf0AAAhcACQlWHAkHAG0CABcACQlWHAkHAG0CAAAA.Dawnte:BAABLgAECn8dAAIOAAcJHBxYYACuAQAOAAcJHBxYYACuAQABLgAECgUJDwADAAAAAA==.Dawsonrogers:BAACLgAFFH8FAAITAAMJfgVAPQCrAAATAAMJfgVAPQCrAAAuAAQKfxwAAhMACAlwEQEtAJ0BABMACAlwEQEtAJ0BAAAA.Dayvastate:BAABLgAECn83AAMJAAkJqhuzJQBrAgAJAAkJqhuzJQBrAgAZAAEJDxLwOAA0AAAAAA==.Dazshir:BAAALgADCgMJAwAAAA==.',
De='Deathbanana:BAABLgAFFH8cAAIJAAUJayJ/OQCBAQAJAAUJayJ/OQCBAQABLgAFFAgJGQAEAAYaAA==.Deaththreat:BAAALgAECgQJBAABLgAECgkJHgAOADUaAA==.Deepwater:BAAALgAECgUJBQAAAA==.Delema:BAACLgAFFH8VAAIOAAYJ6xtNHwCCAQAOAAYJ6xtNHwCCAQAuAAQKfyAAAg4ACAlaIUQiAKACAA4ACAlaIUQiAKACAAAA.Democrit:BAAALgAECgYJDwAAAA==.Demonjuice:BAAALgAECgcJDAAAAA==.Derpyblinker:BAABLgAECn8VAAIEAAYJQRDu0wBHAQAEAAYJQRDu0wBHAQAAAA==.Destructer:BAABLgAECn8qAAICAAkJXxITCADJAQACAAkJXxITCADJAQAAAA==.Dethstar:BAAALgAECgUJBgABLgAECgkJPAABAH0YAA==.Devoured:BAAALgADCgMJAwAAAA==.',
Di='Dinger:BAAALgAECgEJAQAAAA==.Dirtydinker:BAAALgAECgYJDQAAAA==.Disconneted:BAAALgADCgYJBgAAAA==.Dishwasher:BAAALgADCgIJAgAAAA==.Dixsard:BAABLgAECn81AAMSAAkJ+SM0AQAJAwASAAkJxyM0AQAJAwAYAAcJTx1tIwDeAQAAAA==.',
Do='Dobrova:BAAALgAECgEJAQAAAA==.Doezenn:BAAALgADCgUJBQAAAA==.Dogofwar:BAAALgAECgEJAQAAAA==.Dottprepared:BAACLgAFFH8dAAIcAAcJvA+yAABRAQAcAAcJvA+yAABRAQAuAAQKf0EAAhwACQmaIpcBAAcDABwACQmaIpcBAAcDAAAA.Dottyfu:BAABLgAFFH8FAAIQAAMJKwlNPgCoAAAQAAMJKwlNPgCoAAAAAA==.Doubted:BAAALgAECgQJBAAAAA==.',
Dr='Dracoiconic:BAAALgAECgEJAgAAAA==.Dragonboffa:BAAALgAECgcJAQAAAA==.Draul:BAAALgAECgEJAQABLgAECgkJNgAKAKwXAA==.Drexl:BAACLgAFFH8PAAIdAAUJghG6BQARAQAdAAUJghG6BQARAQAuAAQKfzgABB4ACQkjHicHAIQCAB4ACQnlHScHAIQCABMABwkSBtplABwBAB0AAgmHDHo7AHAAAAAA.Dril:BAABLgAECn8dAAMMAAgJMxmcNgDoAQAMAAgJHxmcNgDoAQAcAAIJAhZvIACBAAAAAA==.Drognin:BAAALgADCgEJAQAAAA==.Drunkfu:BAAALgADCgQJBAAAAA==.',
Du='Dubstep:BAAALgAECgkJAgAAAA==.Dudette:BAAALgAECgcJDAAAAA==.Dunlop:BAABLgAECn8fAAMfAAkJqBjzDQCEAgAfAAkJqBjzDQCEAgAgAAIJ9wR7dwBMAAABLgAFFAIJAgADAAAAAA==.',
Dv='Dvmcquéén:BAABLgAECn8WAAMCAAcJ5xkzCwANAgACAAcJ5xkzCwANAgABAAIJBwRHBwFOAAAAAA==.',
Dw='Dweams:BAACLgAFFH8dAAIgAAgJARk9AQAnAgAgAAgJARk9AQAnAgAuAAQKfzwAAyAACQmLJv8AAHUDACAACQmLJv8AAHUDACEABAmrDNE5ANgAAAAA.Dweamu:BAAALgAECgUJCQAAAA==.',
['Dâ']='Dântæ:BAAALgAECgUJDwAAAA==.',
['Då']='Dåmon:BAAALgAECgEJBAAAAA==.',
['Dö']='Döts:BAAALgADCgMJAgAAAA==.',
['Dø']='Døctøred:BAAALgAECgYJEwAAAA==.',
Ec='Ectonight:BAAALgAECgUJDAAAAA==.',
Ed='Edgybob:BAAALgAECgMJAwAAAA==.',
Eg='Eggfooyung:BAACLgAFFH8fAAIVAAgJnSJHAgAZAwAVAAgJnSJHAgAZAwAuAAQKfzIAAxUACQmPIRcEAC8DABUACQmPIRcEAC8DACIABwlPCCk7ADABAAAA.Egwene:BAAALgAECgYJBwAAAA==.',
El='Eldar:BAAALgAECgUJBQAAAA==.Elfchick:BAAALgADCgEJAQAAAA==.Elhonna:BAABLgAFFH8GAAIFAAQJFQLDawC/AAAFAAQJFQLDawC/AAAAAA==.Elsâ:BAAALgAECgQJCAAAAA==.',
Em='Emwen:BAAALgADCgMJAwAAAA==.',
En='Endcredits:BAABLgAECn8iAAIIAAkJwg8gHAB3AQAIAAkJwg8gHAB3AQAAAA==.',
Et='Ether:BAABLgAECn8eAAILAAgJzhPUKADNAQALAAgJzhPUKADNAQAAAA==.Ettie:BAAALgAECgMJBQABLgAECgQJBgADAAAAAA==.',
Ev='Evieroot:BAAALgADCgMJAwAAAA==.Evoulker:BAACLgAFFH8hAAIjAAkJfhnyAABWAgAjAAkJfhnyAABWAgAuAAQKf0EAAiMACQkSH6YFAO4CACMACQkSH6YFAO4CAAAA.',
Ex='Exodyce:BAAALgAECgQJBAAAAA==.',
Ey='Eyecantsee:BAAALgADCgIJAgABLgAECgIJAgADAAAAAA==.',
Fa='Faene:BAAALgAECgQJCgABLgAECgUJBQADAAAAAA==.Faire:BAAALgADCgUJBQABLgAFFAQJCgAFAFYZAA==.Fairytale:BAACLgAFFH8eAAMhAAgJjg9LAwDPAQAhAAgJjg9LAwDPAQAfAAEJMwjHEwBGAAAuAAQKf0EAAyEACQlmIAAHANUCACEACQlmHQAHANUCAB8ABwn5HkcSAE4CAAAA.Faitza:BAAALgAECgYJCgAAAA==.Fantastico:BAAALgAECgUJDQAAAA==.',
Fe='Felheim:BAACLgAFFH8RAAIMAAYJTwlOMABcAQAMAAYJTwlOMABcAQAuAAQKfyQAAgwACQlrHCEdAGICAAwACQlrHCEdAGICAAAA.Fellitha:BAABLgAECn8UAAIIAAgJKwJPPQCYAAAIAAgJKwJPPQCYAAAAAA==.Fellithà:BAAALgAECgcJDgAAAA==.Felrend:BAAALgADCgMJAgAAAA==.Fentertained:BAAALgADCgcJCAAAAA==.',
Fi='Fiercevalkyr:BAAALgAECgkJBgAAAA==.Firsttower:BAAALgADCgIJAgAAAA==.Fists:BAACLgAFFH8WAAIVAAUJshsHGQCgAQAVAAUJshsHGQCgAQAuAAQKfzUABBUACQlMHSENAMUCABUACQlMHSENAMUCABAABAlOFrRdAMwAACIAAwlrFANUALcAAAAA.Fizle:BAABLgAECn8bAAIjAAkJHApqFgBkAQAjAAkJHApqFgBkAQAAAA==.',
Fl='Flink:BAAALgAECgYJEwAAAA==.',
Fo='Fourchainz:BAAALgAFFAIJAgABLgAFFAYJEAAVANQTAA==.',
Fr='Friend:BAAALgAECgYJEAAAAA==.Frostmoan:BAAALgAFFAEJAQAAAA==.Frostyninja:BAABLgAECn8jAAIFAAgJlgaElAARAQAFAAgJlgaElAARAQAAAA==.',
Ga='Gabryal:BAABLgAECn8nAAIgAAkJSyB6BwDYAgAgAAkJSyB6BwDYAgAAAA==.Galthur:BAAALgAECgUJCQAAAA==.Ganbatte:BAAALgAECgYJBgAAAA==.Garchomp:BAAALgAECgUJEwAAAA==.Gargameel:BAAALgAECgMJAwAAAA==.',
Ge='Gellina:BAAALgAECgUJBgAAAA==.Georg:BAACLgAFFH8cAAIOAAcJOxkPAwDIAQAOAAcJOxkPAwDIAQAuAAQKfzIAAg4ACQm7JjADAKMDAA4ACQm7JjADAKMDAAAA.Gerbankis:BAAALgAECgMJAwAAAA==.',
Gh='Ghoul:BAACLgAFFH8GAAIJAAIJICXlqwDEAAAJAAIJICXlqwDEAAAuAAQKfxoAAgkACAmSI+gZAOECAAkACAmSI+gZAOECAAAA.Ghouligan:BAAALgAECgQJBAAAAA==.',
Gi='Giga:BAAALgADCgcJCwAAAA==.',
Gl='Glaiver:BAABLgAECn8hAAIkAAkJ5xCgGQCvAQAkAAkJ5xCgGQCvAQAAAA==.Glassjaw:BAAALgADCgUJBQAAAA==.',
Go='Goewin:BAAALgAFFAEJAQAAAA==.Gojo:BAAALgADCgYJDwAAAA==.Gorgrom:BAAALgADCgIJAgAAAA==.',
Gr='Gradiant:BAAALgAECgEJAgABLgAECgkJNgAKAKwXAA==.Greg:BAAALgAECgIJAgAAAA==.Gregorz:BAAALgAECgEJAQAAAA==.',
Gu='Gulgodeth:BAAALgAECgQJBQAAAA==.Gulgrimmar:BAACLgAFFH8fAAMLAAkJgB9mAwCmAgALAAgJISBmAwCmAgAKAAIJWRbSbABdAAAuAAQKfzcAAgsACQnnJqwAANkDAAsACQnnJqwAANkDAAAA.Guwudanielle:BAAALgAFFAIJAgABLgAFFAQJCgAFAFYZAA==.',
['Gì']='Gìzzìmo:BAAALgAECggJDwAAAA==.',
Ha='Hailsstorm:BAAALgADCgcJEgAAAA==.Hardfeelings:BAABLgAECn8eAAIOAAkJNRokKgBXAgAOAAkJNRokKgBXAgAAAA==.Harkness:BAAALgAECgYJDwAAAA==.Hassif:BAAALgAECgEJAQAAAA==.',
He='Heimerdoodle:BAAALgAECggJEwAAAA==.Hemlawk:BAAALgAECgEJAQAAAA==.Hemus:BAAALgAECgMJAwAAAA==.Hexed:BAABLgAECn8sAAIQAAkJcA4yHwCqAQAQAAkJcA4yHwCqAQAAAA==.',
Ho='Hochipo:BAAALgAECgEJAQAAAA==.',
Hu='Hughue:BAAALgADCgUJBQAAAA==.Hugs:BAAALgAECgYJCgAAAA==.Hurjek:BAAALgAFFAEJAQABLgAFFAUJEAAVAKgbAA==.',
Hy='Hyuna:BAAALgAECgEJAQABLgAECgcJDgADAAAAAA==.',
Ia='Iaso:BAABLgAECn8lAAIfAAkJCBScGQD6AQAfAAkJCBScGQD6AQAAAA==.',
Ic='Iconstar:BAAALgADCgMJAwAAAA==.',
Ig='Igneel:BAAALgADCgQJAQAAAA==.Ignored:BAAALgAFFAIJAgAAAA==.',
Ij='Ijustankedu:BAAALgAECgMJAwAAAA==.',
Ik='Ikiea:BAAALgAECgcJCAAAAA==.',
Il='Ilgrim:BAABLgAECn8YAAMPAAgJWxkzKgC6AQAPAAgJWxkzKgC6AQAOAAQJ+AO2LAFIAAABLgAFFAUJDgAYACkPAA==.Ilravenll:BAACLgAFFH8OAAIYAAUJKQ9IHwAiAQAYAAUJKQ9IHwAiAQAuAAQKfyEAAhgACQmQGJsLAGcCABgACQmQGJsLAGcCAAAA.Ilweaver:BAAALgAFFAEJAQABLgAFFAUJDgAYACkPAA==.Ilyana:BAACLgAFFH8cAAIEAAgJGBg1EgBYAgAEAAgJGBg1EgBYAgAuAAQKf0EAAgQACQk2JiUEAGUDAAQACQk2JiUEAGUDAAAA.',
Im='Impavido:BAAALgAECgYJBgAAAA==.',
In='Inholy:BAABLgAECn8UAAIkAAYJohenIwBWAQAkAAYJohenIwBWAQAAAA==.Insights:BAAALgADCgMJAwAAAA==.',
Is='Isabella:BAAALgAECgEJAQABLgAFFAQJCgAFAFYZAA==.',
It='Ithopel:BAABLgAECn8mAAIHAAYJASF6KAASAgAHAAYJASF6KAASAgAAAA==.',
Ja='Jalista:BAAALgADCgMJAwAAAA==.Jayc:BAACLgAFFH8eAAIEAAUJCSApTABOAQAEAAUJCSApTABOAQAuAAQKfx0AAgQACAlgHid0AOoBAAQACAlgHid0AOoBAAAA.',
Je='Jereico:BAACLgAFFH8iAAIaAAkJQiLrAACQAgAaAAkJQiLrAACQAgAuAAQKfzsAAhoACQnmJmoAAJEDABoACQnmJmoAAJEDAAAA.Jeryhn:BAACLgAFFH8dAAIPAAgJnhJEAgDZAQAPAAgJnhJEAgDZAQAuAAQKf0EAAg8ACQk8GhYTAHoCAA8ACQk8GhYTAHoCAAAA.',
Jo='Joeburrow:BAAALgAECgQJBAAAAA==.Joeynodz:BAAALgADCgYJEgAAAA==.Jortshorts:BAABLgAECn8vAAIlAAkJ+AleGgA1AQAlAAkJ+AleGgA1AQAAAA==.',
Jr='Jray:BAABLgAECn8VAAIOAAYJGRnOZAC3AQAOAAYJGRnOZAC3AQAAAA==.',
Ju='Juggalo:BAACLgAFFH8OAAMNAAQJmSHAAQCBAQANAAQJmSHAAQCBAQAaAAEJkQYUZQA3AAAuAAQKfysAAw0ACQllIpMBANcCAA0ACQllIpMBANcCABoAAgmJEiiHAEkAAAAA.June:BAACLgAFFH8fAAIVAAgJxRmxAQAaAgAVAAgJxRmxAQAaAgAuAAQKfz8AAxUACQlsIbMEAB0DABUACQlsIbMEAB0DACIACQkGH3kJAKoCAAAA.Juuju:BAAALgAECgYJEwAAAA==.',
Ka='Kaldriss:BAAALgAECgEJAgAAAA==.Kalen:BAAALgADCgEJAgAAAA==.Katashimus:BAAALgAECggJEgAAAA==.Kawasuoo:BAABLgAECn8gAAMHAAgJMR1pIgAzAgAHAAcJzhxpIgAzAgAmAAYJAAy4PgClAAAAAA==.Kaze:BAAALgAECgcJEQAAAA==.',
Kh='Khaotichic:BAABLgAECn8iAAIFAAYJFA/AjgAcAQAFAAYJFA/AjgAcAQAAAA==.Khrenak:BAAALgAECgUJCwAAAA==.',
Ki='Kickpunch:BAAALgAECgYJDgAAAA==.Kirah:BAACLgAFFH8HAAIaAAIJmBwbSgCfAAAaAAIJmBwbSgCfAAAuAAQKfyAAAhoACQmwIWoEAEoDABoACQmwIWoEAEoDAAEuAAUUBAkKAAUAVhkA.',
Kl='Klrum:BAAALgAECgQJAgAAAA==.Kläus:BAAALgAECgEJAQAAAA==.',
Ko='Koddin:BAABLgAECn8zAAIOAAkJ6h4KJwBlAgAOAAkJ6h4KJwBlAgAAAA==.Korenchkin:BAAALgAECgEJAgAAAA==.Koreth:BAACLgAFFH8hAAMYAAcJGBymCAAMAgAYAAYJGBymCAAMAgASAAEJAACyBwA5AAAuAAQKf0cAAxgACQmAJsYBAE4DABgACQmAJsYBAE4DABIACAmWGg8EAHcCAAAA.Kornholyo:BAAALgAECgEJAQAAAA==.',
Kr='Kragoth:BAAALgADCgIJAgAAAA==.',
Ku='Kutuzov:BAABLgAECn8kAAIKAAcJbBTJPwCqAQAKAAcJbBTJPwCqAQAAAA==.',
Kw='Kwaiza:BAAALgAECgYJDwAAAA==.',
['Ká']='Káel:BAAALgAECgMJAwAAAA==.',
La='Lailaysia:BAABLgAECn8cAAIfAAkJDyIUAwBjAwAfAAkJDyIUAwBjAwAAAA==.Lamemoosaur:BAAALgADCgIJAgABLgAECgYJCgADAAAAAA==.Laríca:BAACLgAFFH8ZAAIPAAUJ7CVSCQAYAgAPAAUJ7CVSCQAYAgAuAAQKfzEAAg8ACQmDJYMCAFIDAA8ACQmDJYMCAFIDAAAA.Laustin:BAABLgAECn8kAAQRAAkJXhtPCgB5AgARAAkJVhtPCgB5AgAnAAYJEhAuGwDRAAAFAAIJbwUNBgFSAAAAAA==.Laustinjung:BAAALgADCgIJAQAAAA==.Laydout:BAAALgAECggJEgABLgAECgkJIAAFAG8iAA==.Laydoutyota:BAABLgAECn8gAAIFAAkJbyI3EQDEAgAFAAkJbyI3EQDEAgAAAA==.',
Le='Leag:BAABLgAECn8YAAMTAAcJFw+MQACiAQATAAcJFw+MQACiAQAeAAEJJAmvPwA5AAAAAA==.Lemonruss:BAAALgADCgQJBAAAAA==.',
Li='Liaria:BAAALgAECgEJAQAAAA==.Lilea:BAACLgAFFH8JAAIFAAMJUhqMWQDqAAAFAAMJUhqMWQDqAAAuAAQKfzUAAwUACQnFHzgVAKUCAAUACQnFHzgVAKUCACcABwnrEfc0AJYBAAAA.Lionsmane:BAAALgAFFAIJAgAAAA==.Lithium:BAAALgADCgUJBQAAAA==.Littledeb:BAAALgAFFAEJAQAAAA==.',
Lo='Lockdots:BAAALgADCgcJCQAAAA==.Lolchaosbolt:BAAALgADCgYJBgAAAA==.Lortherian:BAABLgAECn8VAAMdAAgJ9h+xCQBVAgAdAAgJ9h+xCQBVAgATAAEJugzwogAyAAAAAA==.Lowbo:BAAALgADCgUJBQAAAA==.Lowelfesteem:BAAALgADCgUJBQAAAA==.',
Lu='Lucey:BAAALgAECgEJAgAAAA==.Lucille:BAABLgAECn8aAAIEAAYJ3gcJ3QDbAAAEAAYJ3gcJ3QDbAAAAAA==.',
Ly='Lyndira:BAAALgAECgUJBQAAAA==.',
['Lä']='Läwlbringer:BAAALgAECggJDQAAAA==.',
['Lî']='Lîghtt:BAAALgADCgQJBAAAAA==.',
Ma='Mabritos:BAAALgAECgQJBQABLgAFFAYJGgAnAJ8eAA==.Maccabee:BAAALgAECgEJAQAAAA==.Malison:BAAALgAECgIJAgAAAA==.Mania:BAAALgADCgYJBgABLgAECgkJIwATAL8dAA==.Mathath:BAACLgAFFH8NAAIJAAQJ5QuiegANAQAJAAQJ5QuiegANAQAuAAQKfxwAAwkACAn4F7JWAL4BAAkACAnIF7JWAL4BAAgABAlUFacoAPkAAAAA.Mathmath:BAAALgAECgUJCgABLgAFFAEJAQADAAAAAA==.Mathoras:BAABLgAECn8aAAIBAAkJKBanNQABAgABAAkJKBanNQABAgAAAA==.Mazraq:BAAALgAECgEJAgABLgAECgkJNgAKAKwXAA==.',
Me='Meandean:BAAALgAECgIJBgAAAA==.Meatier:BAAALgAECgcJDwABLgAECgkJIwATAL8dAA==.Meatless:BAAALgADCgcJDQAAAA==.Melliya:BAABLgAFFH8FAAIhAAMJeALBOQCRAAAhAAMJeALBOQCRAAAAAA==.Merp:BAAALgAECgEJAgAAAA==.',
Mi='Micmac:BAAALgAECgQJCQAAAA==.Milktankk:BAAALgAECgMJAwAAAA==.Milo:BAAALgAECgcJDAAAAA==.Miltonroe:BAACLgAFFH8GAAIGAAMJbQQTEQCuAAAGAAMJbQQTEQCuAAAuAAQKfyoAAgYACAm/FLoOAMEBAAYACAm/FLoOAMEBAAAA.Mirithul:BAAALgADCgYJBwAAAA==.Mischiëf:BAABLgAECn8VAAIOAAcJvgR56QDPAAAOAAcJvgR56QDPAAAAAA==.Mitsuri:BAABLgAECn8iAAIEAAgJoQrekgCtAQAEAAgJoQrekgCtAQAAAA==.',
Mo='Modr:BAAALgAECgkJEgAAAA==.Moiraine:BAAALgAECgEJAQAAAA==.Monkynate:BAAALgAECgYJCgAAAA==.Monsterskill:BAABLgAECn8jAAQUAAgJgBseEAAsAQAUAAYJtxoeEAAsAQABAAUJdBmMmAALAQACAAUJhxNULQAIAQAAAA==.Moonerva:BAABLgAECn8iAAIoAAkJ9g4sJACmAQAoAAkJ9g4sJACmAQAAAA==.Morpheos:BAAALgADCgQJBAAAAA==.Mortgage:BAAALgADCgUJBQAAAA==.',
Mu='Mutsu:BAAALgADCgcJBwAAAA==.',
Mv='Mvqchx:BAAALgAECgUJCQAAAA==.',
['Mì']='Mìssy:BAAALgAECgYJDAAAAA==.',
Na='Naturelass:BAAALgADCgUJBQAAAA==.Nausicaa:BAAALgAECgEJAQAAAA==.Nawwll:BAAALgADCgMJAwAAAA==.',
Ne='Neotama:BAAALgAECggJEgAAAA==.Nethis:BAABLgAECn8nAAIgAAgJmRxsFgAWAgAgAAgJmRxsFgAWAgAAAA==.',
Ni='Niatpacgrom:BAACLgAFFH8OAAIGAAUJVBDOCQAeAQAGAAUJVBDOCQAeAQAuAAQKfyIAAgYACQlsGaUHAEwCAAYACQlsGaUHAEwCAAAA.Nivla:BAAALgADCgMJAwAAAA==.',
No='Nobacon:BAAALgAECgYJDAAAAA==.Nokix:BAAALgADCgkJDgAAAA==.Nonorcman:BAAALgAECgIJAgAAAA==.Norah:BAAALgAECgEJAQAAAA==.Norvis:BAAALgAECgQJBQAAAA==.Notdragon:BAABLgAECn8WAAIEAAQJrQpF9QC4AAAEAAQJrQpF9QC4AAAAAA==.',
Nu='Nukeddukem:BAAALgAECgYJEgAAAA==.',
Nv='Nv:BAAALgAECggJEwAAAA==.',
Ny='Nymrod:BAABLgAECn8sAAMBAAkJSBRSOgDwAQABAAkJSBRSOgDwAQACAAIJpgduZQBEAAAAAA==.',
['Ní']='Nír:BAAALgAECgQJBAAAAA==.',
Ob='Oben:BAAALgAECggJAQAAAA==.',
Oj='Ojou:BAAALgADCgMJAwABLgAFFAMJAwADAAAAAA==.',
On='Onepunch:BAAALgAECgQJCAAAAA==.',
Or='Orcman:BAAALgADCgIJAgABLgAECgIJAgADAAAAAA==.Orloran:BAAALgADCgIJAgAAAA==.',
Ot='Otterknight:BAAALgAECgUJBQABLgAECggJIAAHADEdAA==.',
Pa='Palthur:BAAALgAECgYJDQAAAA==.Parria:BAABLgAECn8UAAIBAAcJ8RFcdABQAQABAAcJ8RFcdABQAQABLgAECgkJHAAfAA8iAA==.Pasqualino:BAAALgAECgYJCgAAAA==.Passionate:BAACLgAFFH8MAAIjAAQJwAztGwDSAAAjAAQJwAztGwDSAAAuAAQKfyYAAiMACAmfFFYVAPUBACMACAmfFFYVAPUBAAAA.',
Pe='Peepis:BAAALgADCgEJAQABLgAECgkJIwATAL8dAA==.Pennance:BAABLgAECn8iAAIPAAkJ/RuZDgCiAgAPAAkJ/RuZDgCiAgAAAA==.',
Ph='Phatmidas:BAABLgAECn81AAIOAAkJyBnqNQAnAgAOAAkJyBnqNQAnAgAAAA==.Philth:BAAALgAECgUJBwAAAA==.',
Pi='Pistfist:BAAALgAECgcJAQAAAA==.',
Pl='Plagueground:BAACLgAFFH8gAAIJAAcJTyD+BgCsAgAJAAcJTyD+BgCsAgAuAAQKf0UAAgkACQnhJkMCAHkDAAkACQnhJkMCAHkDAAAA.Plutonyus:BAAALgAECgEJAQAAAA==.',
Po='Poc:BAABLgAECn8ZAAIEAAYJPB3wdADoAQAEAAYJPB3wdADoAQAAAA==.Pockets:BAAALgAECgMJBwAAAA==.Poolstick:BAAALgAECgYJCAAAAA==.Potatopotato:BAACLgAFFH8SAAIYAAQJmhP+GQBBAQAYAAQJmhP+GQBBAQAuAAQKfyUAAhgACQnAGG4OAEACABgACQnAGG4OAEACAAAA.Pounces:BAABLgAECn8VAAIlAAYJNCDsEQCVAQAlAAYJNCDsEQCVAQAAAA==.Powerfistin:BAAALgADCgcJBwAAAA==.',
Pr='Prosecutor:BAAALgAECgUJDAAAAA==.Prozak:BAAALgAECgUJDgABLgAFFAMJDQAQAC4GAA==.Prynts:BAABLgAECn8VAAIOAAcJZh3sRAAVAgAOAAcJZh3sRAAVAgAAAA==.Prøzak:BAACLgAFFH8NAAIQAAMJLgaEPgCoAAAQAAMJLgaEPgCoAAAuAAQKfxUAAhAACAl5CxA0ACwBABAACAl5CxA0ACwBAAAA.',
Ps='Psychomidget:BAAALgAECgYJEQAAAA==.',
Pu='Puetrid:BAAALgADCgYJBgABLgAECgQJBAADAAAAAA==.',
Ra='Raanky:BAAALgAECgEJAQAAAA==.Radiantlight:BAACLgAFFH8GAAIhAAMJGgNdOACbAAAhAAMJGgNdOACbAAAuAAQKfxYAAiEACAm8EDgeANkBACEACAm8EDgeANkBAAAA.Randomly:BAAALgAECgQJCAAAAA==.Raspberries:BAAALgAECgcJBwAAAA==.Rautha:BAAALgAECgkJEgAAAA==.Rayl:BAABLgAECn8dAAMJAAcJvBpySgDgAQAJAAcJvBpySgDgAQAIAAEJ5QGsZQAcAAAAAA==.Razsputin:BAAALgAECgMJBwAAAA==.',
Re='Rekless:BAAALgADCgUJBQAAAA==.Rethgar:BAAALgAECgUJEgAAAA==.',
Rh='Rhaegosa:BAABLgAECn8zAAQaAAkJDxlcJwClAQAaAAcJ0xlcJwClAQAjAAQJjBY2GwAlAQANAAQJrg2uFwCaAAAAAA==.Rhavik:BAAALgAECgQJBgAAAA==.Rhekt:BAAALgAECgIJBQAAAA==.Rhok:BAAALgAECgEJAQAAAA==.Rhokladar:BAAALgAECgUJCwAAAA==.',
Ri='Rickylafleur:BAAALgAECgEJAQAAAA==.Ridcully:BAABLgAECn8bAAIHAAgJlxfPOQCsAQAHAAgJlxfPOQCsAQAAAA==.Rimath:BAAALgAECgcJBAAAAA==.Rinswind:BAAALgADCgMJAwAAAA==.',
Ro='Robopacman:BAACLgAFFH8XAAQZAAUJECH7CQBKAQAJAAQJvyBAUQBLAQAZAAQJdRj7CQBKAQAIAAEJAADaRgAAAAAuAAQKfzoABAkACQkEJRgPACMDAAkACQnyJBgPACMDAAgACAlDIlsHAKMCABkAAgnhGFAnAJIAAAAA.Rodstewart:BAACLgAFFH8aAAMFAAkJKBYADAD8AQAFAAYJyBgADAD8AQAnAAUJUgzvFAD2AAAuAAQKfycAAwUACQmwJE0WAIYCAAUACAmPJE0WAIYCACcABwnbHxomAPgBAAAA.Roofeo:BAABLgAECn8hAAQCAAgJJBW5DgBOAQACAAYJmBa5DgBOAQAUAAQJIhVMGAD8AAABAAQJcgyKwwDGAAABLgAFFAMJCQAIAFkUAA==.Rotdaddy:BAABLgAECn8oAAIJAAkJFQXAlgA4AQAJAAkJFQXAlgA4AQAAAA==.',
Ry='Ryoshin:BAAALgADCgEJAQABLgAECgYJDQADAAAAAA==.Ryzel:BAAALgADCgUJBQAAAA==.',
['Rï']='Rïn:BAAALgADCgEJAQAAAA==.',
Sa='Sabatikus:BAAALgAECgIJAgAAAA==.Salas:BAABLgAECn8UAAIBAAcJzgyEjwAbAQABAAcJzgyEjwAbAQAAAA==.Salino:BAABLgAECn8UAAMlAAcJ3Bh5DwC4AQAlAAcJ3Bh5DwC4AQAHAAUJbQYljgCWAAAAAA==.Salinoster:BAAALgAECgEJAwAAAA==.Salordell:BAAALgADCgIJAwAAAA==.Sam:BAAALgADCgEJAQAAAA==.Sanque:BAAALgAECgMJAwAAAA==.Sarate:BAABLgAECn8rAAIgAAgJ3A55LgBlAQAgAAgJ3A55LgBlAQAAAA==.Savannah:BAABLgAFFH8KAAIFAAQJVhn1OwAvAQAFAAQJVhn1OwAvAQAAAA==.Savvtwo:BAAALgADCgcJBwABLgAFFAgJHQAMAPEiAQ==.',
Sc='Scathach:BAABLgAECn8gAAMMAAcJ4x69PADRAQAMAAcJ4x69PADRAQAkAAQJURguRADmAAABLgAFFAEJAQADAAAAAA==.Scoop:BAAALgADCgYJBgAAAA==.Scorandom:BAAALgAECgEJAQAAAA==.',
Se='Seetani:BAAALgADCgUJBgABLgAECgQJBgADAAAAAA==.Semko:BAAALgAECgEJAwAAAA==.Seven:BAAALgAECgcJCgAAAA==.Sezra:BAAALgADCgkJAQAAAA==.',
Sh='Shamalam:BAAALgADCgEJAQAAAA==.Shei:BAAALgAECgIJAgAAAA==.Sheidon:BAAALgAECgQJBAAAAA==.Shinanigans:BAAALgAECgYJDwAAAA==.Shruikan:BAAALgADCggJDAAAAA==.',
Si='Silverbäck:BAAALgADCgUJBQABLgAECgkJGgAGAAISAA==.Silverslam:BAAALgAECgEJAQABLgAECgkJGgAGAAISAA==.Sinatra:BAAALgAECgIJBAABLgAECgcJEQADAAAAAA==.Siqodel:BAAALgADCgYJCAAAAA==.',
Sk='Skurge:BAABLgAECn8UAAMZAAgJagppFgAiAQAZAAgJagppFgAiAQAJAAMJgQPjMAFoAAAAAA==.',
Sl='Slamb:BAAALgAECgYJBwAAAA==.Slimetongue:BAAALgADCgMJAwAAAA==.',
Sm='Smaaug:BAAALgAFFAMJBAAAAA==.',
Sn='Snuggle:BAAALgAECgEJAQAAAA==.',
So='Solstis:BAAALgAECggJDgAAAA==.Sookie:BAAALgADCgIJAgAAAA==.Sorzsnipe:BAAALgADCgQJBAAAAA==.',
Sp='Spellchücker:BAAALgAECgcJDQAAAA==.Spfzero:BAAALgAECgIJAgAAAA==.',
St='Staggered:BAACLgAFFH8PAAIQAAQJoh7yGwBCAQAQAAQJoh7yGwBCAQAuAAQKfyUAAxAACAkOIusLAM8CABAACAkOIusLAM8CACIAAQk1A9WMABwAAAAA.Stiffbutt:BAAALgAECgEJAQAAAA==.Stonebeard:BAAALgAECgIJAwAAAA==.Stoneojinray:BAAALgADCgEJAQAAAA==.Stoneorcman:BAAALgADCgcJBwABLgAECgIJAgADAAAAAA==.',
Su='Subdofu:BAAALgADCgQJBAABLgAECgcJFwAYAN0cAA==.Subtox:BAABLgAECn8XAAMYAAcJ3RxNIQDvAQAYAAcJ3RxNIQDvAQASAAEJkgu5HwA0AAAAAA==.',
Sw='Sweetcool:BAAALgAECgUJCQABLgAECggJLgAFAP4jAA==.Sweetzeke:BAAALgAECgEJAQAAAA==.',
Sy='Syphilistjt:BAABLgAECn8WAAIhAAgJ0xLIFwDgAQAhAAgJ0xLIFwDgAQAAAA==.Syphillis:BAAALgAECgYJCgAAAA==.',
['Sá']='Sálud:BAACLgAFFH8MAAIoAAUJix/+GQBCAQAoAAUJix/+GQBCAQAuAAQKfywAAygACAmnIxMIANACACgACAmnIxMIANACACYABwmhGYYVAKMBAAAA.',
['Sê']='Sêp:BAAALgAECggJDgAAAA==.',
Ta='Takoda:BAAALgAECgEJAgAAAA==.Talivath:BAAALgAECgUJCgAAAA==.Tanissaria:BAAALgADCgIJAgAAAA==.Taranith:BAAALgAECgUJBQABLgAECggJGQAEAPoTAA==.Tarhealeon:BAABLgAECn91AAQOAAkJEBd0OwATAgAOAAkJ+xV0OwATAgAPAAkJyRuWIQARAgAXAAUJERgqHwAXAQAAAA==.Tarmander:BAAALgAECgYJDgAAAA==.Taylörshift:BAAALgAECgQJBwAAAA==.',
Te='Telahnicus:BAAALgAECgEJAQAAAA==.Terranox:BAAALgADCgMJAwAAAA==.Testostauren:BAAALgAECgQJCAAAAA==.',
Th='Thabigone:BAAALgAECgYJDAAAAA==.Thalnaria:BAAALgAECgYJCwAAAA==.Threebuttons:BAAALgAECgUJDgABLgAFFAUJFwAjAHQLAA==.Thunderkis:BAABLgAECn8XAAMFAAYJHAeMqwDmAAARAAYJMQZTOQDvAAAFAAYJHAeMqwDmAAAAAA==.',
Ti='Tiewaz:BAAALgAECgYJBwABLgAECggJHwAEAFoPAA==.Tiewiz:BAABLgAECn8fAAMEAAgJWg+zjABbAQAEAAgJEQyzjABbAQApAAUJlw1lDQCfAAAAAA==.Titanarum:BAAALgAECgQJBAAAAA==.',
To='Tointjoker:BAAALgAECgUJBgAAAA==.Tolun:BAABLgAECn8/AAIEAAkJqhxMHwCfAgAEAAkJqhxMHwCfAgAAAA==.Tosan:BAAALgADCggJDgAAAA==.',
Tr='Treeplague:BAABLgAECn9EAAMgAAkJBxNEGQD7AQAgAAkJBxNEGQD7AQAhAAcJ8RWuHQDeAQAAAA==.Trypleg:BAAALgAECgMJAwAAAA==.',
Tu='Tungie:BAABLgAECn8bAAIJAAgJ0iARQgD6AQAJAAgJ0iARQgD6AQAAAA==.Turn:BAACLgAFFH8oAAQBAAkJ4RNyCAChAQABAAcJchdyCAChAQACAAUJwg2+AwBcAQAUAAIJmSCLFgBhAAAuAAQKf0gABAEACQlRJr8UANkCAAEACAliJb8UANkCABQAAwlJJpccANUAAAIAAwmxJCgaAM8AAAAA.Turtleduck:BAABLgAECn8kAAINAAgJnBuHBAApAgANAAgJnBuHBAApAgAAAA==.Tuskbreaker:BAAALgAECgIJAgAAAA==.',
Tw='Twittytister:BAAALgADCgQJBAAAAA==.Twostrokes:BAAALgAECgEJAQAAAA==.',
Ty='Tyrese:BAAALgADCggJEAAAAA==.',
Uf='Uffin:BAAALgAECgQJBQAAAA==.',
Um='Umbryx:BAAALgAECgYJDQAAAA==.',
Un='Unagi:BAABLgAECn8cAAIGAAkJrBMeCQAoAgAGAAkJrBMeCQAoAgAAAA==.Unholy:BAAALgADCgIJAgAAAA==.',
Va='Valdi:BAABLgAECn8ZAAIOAAcJkwx8vQAJAQAOAAcJkwx8vQAJAQAAAA==.',
Ve='Velthera:BAABLgAECn8XAAIjAAgJCyJEBAAQAwAjAAgJCyJEBAAQAwABLgAFFAUJEAAVAKgbAA==.Venomlight:BAAALgADCgIJAgAAAA==.Venomstrikes:BAAALgAECgcJEwAAAA==.Venratzi:BAAALgAECgQJBAAAAA==.Vespertina:BAAALgAECgIJAgAAAA==.',
Vi='Viscerion:BAAALgAECgUJBgAAAA==.',
Vo='Voridor:BAAALgADCgEJAQAAAA==.Voulk:BAAALgAFFAMJAwABLgAFFAkJIQAjAH4ZAA==.',
Vy='Vyllan:BAABLgAECn8bAAQUAAgJAQYCEwD8AAABAAgJmgXWlwANAQAUAAYJKwQCEwD8AAACAAMJmgGdQQAoAAAAAA==.',
Wa='Waldgeist:BAAALgAECgUJBQABLgAECgkJIwATAL8dAA==.Walthur:BAAALgADCgkJDQAAAA==.Waobby:BAAALgADCgIJAgAAAA==.Warrpigg:BAAALgAECgEJAQAAAA==.Waterdrinker:BAAALgAECgQJBgAAAA==.Wavybone:BAAALgAECgEJAgAAAA==.',
Wh='Whickedthur:BAAALgAECgYJBgAAAA==.Whiisper:BAAALgADCgMJAwAAAA==.Whoarlock:BAAALgADCgUJCAAAAA==.',
Wi='Wimp:BAAALgAECgIJBAAAAA==.',
Wo='Wo:BAAALgAFFAIJAwAAAA==.',
Wu='Wutangstyle:BAAALgAECgIJAgABLgAECgkJIwATAL8dAA==.',
Wy='Wyatta:BAAALgADCgIJAgAAAA==.',
Xe='Xelinia:BAACLgAFFH8VAAIgAAYJhRPYEABdAQAgAAYJhRPYEABdAQAuAAQKfyEAAiAACQk5H20MALwCACAACQk5H20MALwCAAAA.Xen:BAABLgAFFH8KAAIlAAQJ8hvnBABiAQAlAAQJ8hvnBABiAQAAAA==.',
Xf='Xfortune:BAAALgADCgcJCQAAAA==.',
Xh='Xholycritz:BAAALgAECgMJBAAAAA==.Xhöly:BAAALgAECgEJAQAAAA==.',
Xu='Xuefeng:BAACLgAFFH8dAAIiAAUJOx+lCwBjAQAiAAUJOx+lCwBjAQAuAAQKfzcAAiIACQl7IJcHAM0CACIACQl7IJcHAM0CAAAA.',
Ya='Yahwae:BAAALgADCgUJBQABLgAECgkJPAABAH0YAA==.',
Ye='Yenchmeister:BAACLgAFFH8dAAMTAAgJYRpEAwDDAQATAAUJuRxEAwDDAQAeAAcJlhgAAgBiAQAuAAQKfygAAxMACQkgJdcJABEDABMACQkgJdcJABEDAB4AAgl3ICEoAK4AAAAA.',
Yo='Youngbusta:BAABLgAECn8zAAIEAAkJ9iLsFADZAgAEAAkJ9iLsFADZAgAAAA==.',
Yu='Yuta:BAAALgAECgYJDQAAAA==.',
Za='Zad:BAAALgADCgIJAgAAAA==.',
Ze='Zenrac:BAAALgADCgUJBQAAAA==.Zeromus:BAAALgAECgIJAgAAAA==.',
Zi='Zilvanic:BAACLgAFFH8OAAIXAAQJxwitDACqAAAXAAQJxwitDACqAAAuAAQKfyQABBcACAlgErwWAGkBABcACAn0EbwWAGkBAA4ABQlZEC/wAMcAAA8AAwl8AQiDAGwAAAAA.Zilvanion:BAABLgAFFH8GAAIUAAMJoQQdDAC2AAAUAAMJoQQdDAC2AAAAAA==.',
Zo='Zourknight:BAAALgAECgYJCQAAAA==.Zourlight:BAAALgAECgQJBQAAAA==.Zourlock:BAABLgAECn8XAAQBAAYJdRD/lwAMAQABAAYJAQ//lwAMAQAUAAIJJhK3JwB8AAACAAEJAAAlbwA3AAAAAA==.Zourpatch:BAAALgADCgQJCgAAAA==.',
Zu='Zulvaz:BAAALgAECgIJAwAAAA==.Zurey:BAABLgAECn88AAIMAAkJVg1vWgB1AQAMAAkJVg1vWgB1AQAAAA==.',
Zy='Zynjamin:BAACLgAFFH8gAAMNAAgJ0iE9AAADAgAaAAcJFCHnCQBQAgANAAYJ6yM9AAADAgAuAAQKfy4AAg0ACQkLJC8AANsDAA0ACQkLJC8AANsDAAAA.',
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
