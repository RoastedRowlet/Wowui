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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Mage-Frost','Hunter-BeastMastery','Shaman-Enhancement','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Evoker-Devastation','Paladin-Retribution','Paladin-Holy','Monk-Brewmaster','Hunter-Survival','Rogue-Assassination','Warrior-Fury','Warlock-Affliction','Monk-Mistweaver','Mage-Fire','Paladin-Protection','DeathKnight-Frost','Evoker-Augmentation','Rogue-Outlaw','Rogue-Subtlety','DemonHunter-Vengeance','Warrior-Protection','Warrior-Arms','Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Windwalker','Evoker-Preservation','DemonHunter-Havoc','Druid-Feral','Druid-Guardian','Hunter-Marksmanship','Druid-Balance','Mage-Arcane',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aannte:BAACLgAFFH8ZAAMBAAgJyhgABgDAAQABAAYJCRcABgDAAQACAAQJ8hejCAD9AAAuAAQKfyIAAwEACQlVIowmAHgCAAEACQlGIowmAHgCAAIABAnwHvcdAGABAAAA.Aardbark:BAAALgADCgEJAQAAAA==.',
Ab='Abúsedyoû:BAAALgADCgQJBgAAAA==.',
Ac='Achtland:BAAALgAECgUJBgABLgAFFAEJAQADAAAAAA==.',
Ad='Adekai:BAAALgAECgYJEAAAAA==.Adv:BAAALgAECgEJAQAAAA==.',
Ae='Aerestrix:BAAALgAECgYJBwAAAA==.',
Ai='Airvis:BAABLgAECn8wAAIEAAgJzAyDegB9AQAEAAgJzAyDegB9AQAAAA==.',
Al='Alacia:BAAALgAECgkJEAABLgAFFAMJCQAFAFIaAA==.Alatarr:BAAALgAECgcJEQAAAA==.Albinomonk:BAAALgADCgcJBwAAAA==.',
An='Anankei:BAAALgAECgUJCgAAAA==.Annastrophic:BAAALgADCgMJAwAAAA==.Anrí:BAAALgAECgEJAQAAAA==.Antaria:BAAALgADCgcJFgAAAA==.Ante:BAAALgADCgUJAQAAAA==.Antiform:BAAALgAECgMJBwAAAA==.Antpony:BAAALgAECgIJAgABLgAECgYJCgADAAAAAA==.',
Aq='Aqulara:BAAALgAECgEJAQAAAA==.',
Ar='Arcish:BAAALgAECgEJAgAAAA==.Arjun:BAABLgAECn8YAAIGAAgJQRKJEACcAQAGAAgJQRKJEACcAQAAAA==.Arkirla:BAAALgAECgEJAgAAAA==.Arkiyra:BAAALgAECggJDgAAAA==.Arklira:BAAALgAECgEJAQAAAA==.Arkosh:BAAALgAECgEJAgAAAA==.Arkyra:BAAALgAECgUJBwAAAA==.Arovix:BAABLgAECn8ZAAIHAAgJVBpGKgD6AQAHAAgJVBpGKgD6AQAAAA==.',
As='Ashwey:BAAALgADCgkJCAAAAA==.',
At='Atom:BAABLgAECn8fAAIFAAkJgxWbLAAfAgAFAAkJgxWbLAAfAgAAAA==.',
Au='Aubreey:BAAALgADCgcJCQAAAA==.Aureille:BAAALgAECgYJCgAAAA==.',
Aw='Awoozehl:BAACLgAFFH8fAAMIAAcJLiD2IQDCAQAIAAYJLiD2IQDCAQAJAAEJAABiRQAAAAAuAAQKfz0AAggACQnWJhQCAHsDAAgACQnWJhQCAHsDAAAA.',
Az='Azanoth:BAAALgAECgYJCQABLgAFFAMJBwAJAKAQAA==.Azgrodon:BAABLgAECn82AAMKAAkJrBemGwBiAgAKAAkJrBemGwBiAgALAAMJjww+bACSAAAAAA==.Azor:BAABLgAECn8YAAIMAAgJch08HQCiAgAMAAgJch08HQCiAgAAAA==.',
Ba='Baja:BAAALgAECgQJBAAAAA==.Baldomar:BAAALgADCgUJCAAAAA==.Banatok:BAAALgAECgEJAQAAAA==.Bangmonk:BAAALgAFFAQJBAABLgAFFAgJIAANACAgAA==.Bangungot:BAAALgADCgMJAwABLgAFFAgJIAANACAgAA==.Barristan:BAAALgAECgUJDQAAAA==.Barzalie:BAAALgAECgYJDAABLgAFFAMJAwADAAAAAA==.Bathrezz:BAABLgAECn8gAAMOAAkJoxf7SgDbAQAOAAkJoxf7SgDbAQAPAAMJWA9zZQCSAAAAAA==.',
Be='Bearyonce:BAAALgAFFAIJAwAAAA==.Beerbelly:BAAALgAFFAMJAwAAAA==.Beleaves:BAACLgAFFH8gAAIQAAgJYQeQBgBqAQAQAAgJYQeQBgBqAQAuAAQKf0EAAhAACQlbHf8JAIsCABAACQlbHf8JAIsCAAAA.Beorl:BAAALgADCgYJCAAAAA==.',
Bh='Bhackshots:BAABLgAECn8XAAIRAAUJjSFkKwBDAQARAAUJjSFkKwBDAQABLgAECgkJNQASAPkjAA==.',
Bi='Bifurious:BAABLgAECn8jAAITAAkJvx3wDQCKAgATAAkJvx3wDQCKAgAAAA==.Bigrob:BAAALgAECgEJBQAAAA==.',
Bl='Blowmybubble:BAAALgAECgEJAQABLgAECgkJIAAFAKchAA==.Bluereindeer:BAABLgAECn8VAAIIAAkJAgstYQCeAQAIAAkJAgstYQCeAQAAAA==.',
Bo='Bobsstones:BAACLgAFFH8dAAQBAAgJlB7QAwDkAQABAAcJWB3QAwDkAQACAAQJ6x0sBgANAQAUAAIJPSNyCgDBAAAuAAQKfykABAIACQlCJT0GAGwCAAEABwmkJP4bAK0CAAIABgmDJD0GAGwCABQAAwm6JOgVANUAAAAA.Bonekitty:BAAALgAECgYJBgAAAA==.Bonkulo:BAACLgAFFH8HAAIJAAMJoBAOJgCuAAAJAAMJoBAOJgCuAAAuAAQKfygAAwkACQmjFaYSANkBAAkACAmEF6YSANkBAAgAAQl6CLdcATUAAAAA.Boofassist:BAABLgAECn8dAAIPAAkJ7CKABAAmAwAPAAkJ7CKABAAmAwABLgAFFAcJGQAVANgZAA==.Boogey:BAABLgAECn8fAAMEAAgJfQ2CegB9AQAEAAgJfQ2CegB9AQAWAAEJpQiNEAAyAAAAAA==.Boompowwow:BAABLgAECn8VAAILAAYJIxnmNACDAQALAAYJIxnmNACDAQAAAA==.Boomsonic:BAAALgADCgUJBQABLgAECgkJIwATAL8dAA==.Bophadeez:BAABLgAECn8qAAQPAAgJeB4bHwAgAgAPAAcJGSEbHwAgAgAXAAgJ/xjLDADsAQAOAAYJvQ/MjABhAQAAAA==.',
Br='Broccoliz:BAECLgAFFH8oAAIHAAgJKBWyBgB5AgAHAAgJKBWyBgB5AgAuAAQKf0IAAgcACQkUH9MYAHECAAcACQkUH9MYAHECAAAA.Brokan:BAAALgAFFAIJAgAAAA==.Brokgar:BAAALgAECggJEAAAAA==.Brotu:BAAALgADCgIJAQAAAA==.Bruceleroy:BAAALgADCgEJAQAAAA==.Brutalsmasch:BAAALgADCgUJBQAAAA==.',
Bu='Bubu:BAAALgAECgEJAQAAAA==.Bulis:BAAALgAECgMJAwAAAA==.Bullblaster:BAAALgAECgMJBQAAAA==.',
Bw='Bwonshamdi:BAAALgAECgcJBwABLgAECgcJBwADAAAAAA==.',
['Bõ']='Bõb:BAAALgAECgQJCgAAAA==.',
Ca='Caden:BAAALgAECgQJBAABLgAFFAMJCQAFAFIaAA==.Cafca:BAABLgAECn86AAICAAkJgBi4AwBHAgACAAkJgBi4AwBHAgAAAA==.Cahma:BAAALgADCgYJEAAAAA==.Caitlin:BAAALgAECgEJAQABLgAFFAQJCgAFAFYZAA==.Callyour:BAAALgADCgIJAgAAAA==.Cask:BAAALgADCgYJAQAAAA==.',
Ch='Chaesol:BAAALgAFFAEJAQAAAA==.Chainsawloli:BAAALgADCgUJBQAAAA==.Changying:BAAALgAECggJDQAAAA==.Cheekung:BAAALgAECgcJEgAAAA==.Cheeseburgr:BAAALgADCgEJAQAAAA==.Choedankal:BAAALgADCgcJBwAAAA==.Chophouse:BAAALgAECgkJBgAAAA==.Chungusdelux:BAAALgAECgMJAwAAAA==.',
Cl='Clearlyumad:BAACLgAFFH8TAAQIAAYJ6RCkVQA5AQAIAAYJDw+kVQA5AQAYAAQJywVAEADyAAAJAAEJAAApWAAAAAAuAAQKfxsAAggACAmPHlE8AEYCAAgACAmPHlE8AEYCAAAA.Clèrick:BAABLgAECn87AAMPAAkJ8SNiAwBjAwAPAAkJ8SNiAwBjAwAOAAEJfwlbbgE7AAAAAA==.',
Co='Coldcrow:BAAALgAECgEJAQAAAA==.Combination:BAACLgAFFH8PAAIVAAQJAR9UHABhAQAVAAQJAR9UHABhAQAuAAQKfxQAAhUACAn7IVoIAAcDABUACAn7IVoIAAcDAAAA.Confessor:BAAALgAECgEJAQAAAA==.Corruptions:BAAALgADCgEJAQAAAA==.',
Cr='Cromuk:BAAALgAECgEJAQAAAA==.Crux:BAAALgADCgQJBAAAAA==.',
Cy='Cyfrin:BAAALgADCgEJAQAAAA==.Cyânide:BAAALgADCgYJDQAAAA==.',
['Cõ']='Cõurage:BAAALgAECgYJCAAAAA==.',
Da='Dabbhammer:BAAALgAFFAEJAQAAAA==.Dabbyforms:BAAALgAECgIJAgABLgAFFAEJAQADAAAAAA==.Dabbzyvoker:BAABLgAECn8gAAMZAAgJgQwnNwBGAQAZAAgJQwwnNwBGAQANAAYJowZ/IgAWAQABLgAFFAEJAQADAAAAAA==.Dallzbeep:BAAALgAECgkJCQABLgAFFAQJFAAVAH8gAA==.Danathoor:BAAALgADCggJCAAAAA==.Danathor:BAAALgADCgcJBwAAAA==.Dangbro:BAAALgAECgYJEQAAAA==.Dankspank:BAAALgAECgQJCAAAAA==.Danteus:BAAALgADCgMJAwABLgAECgUJDwADAAAAAA==.Darkrigh:BAAALgADCggJDgAAAA==.Darkwave:BAABLgAECn81AAIBAAkJfRjXIABaAgABAAkJfRjXIABaAgAAAA==.Darthdiddyus:BAACLgAFFH8rAAMaAAgJehytAAAmAgAaAAcJKx6tAAAmAgAbAAQJHhSnDQAQAQAuAAQKfzIABBoACQmeJJ0AAC4DABoACQmaJJ0AAC4DABsABwlRITwUAHICABIABAnJId0KAIIBAAAA.Datdruidguy:BAAALgADCgUJBQABLgAECgYJBgADAAAAAA==.Datlock:BAAALgADCgEJAQABLgAECgYJBgADAAAAAA==.Datshammy:BAAALgAECgYJBgAAAA==.Daviculas:BAAALgADCggJDgAAAA==.Dawghawg:BAAALgAECgQJBAAAAA==.Dawnnie:BAACLgAFFH8PAAIXAAQJuA+5CADcAAAXAAQJuA+5CADcAAAuAAQKfzsAAhcACQlOGqUIAD4CABcACQlOGqUIAD4CAAAA.Dawnte:BAABLgAECn8dAAIOAAcJHBzIWwCwAQAOAAcJHBzIWwCwAQABLgAECgUJDwADAAAAAA==.Dawsonrogers:BAACLgAFFH8FAAITAAMJfgVSOQCrAAATAAMJfgVSOQCrAAAuAAQKfxsAAhMACAlwEdoqAKMBABMACAlwEdoqAKMBAAAA.Dayvastate:BAABLgAECn83AAMIAAkJqhs8IwBxAgAIAAkJqhs8IwBxAgAYAAEJDxIkNQA0AAAAAA==.Dazshir:BAAALgADCgMJAwAAAA==.',
De='Deathbanana:BAABLgAFFH8ZAAIIAAUJayJkMACKAQAIAAUJayJkMACKAQABLgAFFAgJGQAEAAYaAA==.Deaththreat:BAAALgAECgQJBAABLgAECggJHAAOAPoZAA==.Delema:BAACLgAFFH8RAAIOAAUJph8xCwBTAQAOAAUJph8xCwBTAQAuAAQKfyAAAg4ACAlaIUQiAKACAA4ACAlaIUQiAKACAAAA.Democrit:BAAALgAECgYJDgAAAA==.Demonjuice:BAAALgAECgcJDAAAAA==.Derpyblinker:BAABLgAECn8VAAIEAAYJQRDu0wBHAQAEAAYJQRDu0wBHAQAAAA==.Destructer:BAABLgAECn8pAAICAAgJNhJTCgCQAQACAAgJNhJTCgCQAQAAAA==.Dethstar:BAAALgAECgQJAwABLgAECgkJNQABAH0YAA==.Devoured:BAAALgADCgMJAwAAAA==.',
Di='Dinger:BAAALgAECgEJAQAAAA==.Dirtydinker:BAAALgAECgYJDQAAAA==.Disconneted:BAAALgADCgYJBgAAAA==.Dishwasher:BAAALgADCgIJAgAAAA==.Dixsard:BAABLgAECn81AAMSAAkJ+SMXAQAMAwASAAkJxyMXAQAMAwAbAAcJTx1tIwDeAQAAAA==.',
Do='Dobrova:BAAALgAECgEJAQAAAA==.Doezenn:BAAALgADCgUJBQAAAA==.Dogofwar:BAAALgAECgEJAQAAAA==.Dottprepared:BAACLgAFFH8cAAIcAAYJeRGyAABRAQAcAAYJeRGyAABRAQAuAAQKf0EAAhwACQmaIpcBAAcDABwACQmaIpcBAAcDAAAA.Dottyfu:BAABLgAFFH8FAAIQAAMJKwmaOwCrAAAQAAMJKwmaOwCrAAAAAA==.Doubted:BAAALgAECgQJBAAAAA==.',
Dr='Dracoiconic:BAAALgAECgEJAgAAAA==.Dragonboffa:BAAALgAECgcJAQAAAA==.Draul:BAAALgAECgEJAQABLgAECgkJNgAKAKwXAA==.Drexl:BAACLgAFFH8PAAIdAAUJghG6BQARAQAdAAUJghG6BQARAQAuAAQKfzgABB4ACQkjHrMGAIYCAB4ACQnlHbMGAIYCABMABwkSBtplABwBAB0AAgmHDHo7AHAAAAAA.Dril:BAABLgAECn8dAAMMAAgJMxmCNADoAQAMAAgJHxmCNADoAQAcAAIJAhZvIACBAAAAAA==.Drognin:BAAALgADCgEJAQAAAA==.Drunkfu:BAAALgADCgQJBAAAAA==.',
Du='Dubstep:BAAALgAECgkJAgAAAA==.Dudette:BAAALgAECgcJDAAAAA==.Dunlop:BAABLgAECn8fAAMfAAkJqBgdDQCGAgAfAAkJqBgdDQCGAgAgAAIJ9wTHcgBMAAAAAA==.',
Dv='Dvmcquéén:BAABLgAECn8WAAMCAAcJ5xkzCwANAgACAAcJ5xkzCwANAgABAAIJBwRHBwFOAAAAAA==.',
Dw='Dweams:BAACLgAFFH8cAAIgAAcJTxk9AQAnAgAgAAcJTxk9AQAnAgAuAAQKfzwAAyAACQmLJugAAHoDACAACQmLJugAAHoDACEABAmrDNE5ANgAAAAA.Dweamu:BAAALgAECgUJCQAAAA==.',
['Dâ']='Dântæ:BAAALgAECgUJDwAAAA==.',
['Då']='Dåmon:BAAALgAECgEJBAAAAA==.',
['Dö']='Döts:BAAALgADCgMJAgAAAA==.',
['Dø']='Døctøred:BAAALgAECgYJEwAAAA==.',
Ec='Ectonight:BAAALgAECgUJDAAAAA==.',
Ed='Edgybob:BAAALgAECgMJAwAAAA==.',
Eg='Eggfooyung:BAACLgAFFH8ZAAIVAAcJ2BmzDQADAgAVAAcJ2BmzDQADAgAuAAQKfzIAAxUACQmPIRcEAC8DABUACQmPIRcEAC8DACIABwlPCCk7ADABAAAA.Egwene:BAAALgAECgYJBwAAAA==.',
El='Eldar:BAAALgAECgUJBQAAAA==.Elfchick:BAAALgADCgEJAQAAAA==.Elhonna:BAABLgAFFH8FAAIFAAQJEwJYYgDGAAAFAAQJEwJYYgDGAAAAAA==.Elsâ:BAAALgAECgQJCAAAAA==.',
Em='Emwen:BAAALgADCgMJAwAAAA==.',
En='Endcredits:BAABLgAECn8gAAIJAAkJPw9wHABrAQAJAAkJPw9wHABrAQAAAA==.',
Et='Ether:BAABLgAECn8eAAILAAgJzhPUKADNAQALAAgJzhPUKADNAQAAAA==.Ettie:BAAALgAECgMJBQABLgAECgQJBgADAAAAAA==.',
Ev='Evieroot:BAAALgADCgMJAwAAAA==.Evoulker:BAACLgAFFH8gAAIjAAgJDBvyAABWAgAjAAgJDBvyAABWAgAuAAQKf0EAAiMACQkSH6YFAO4CACMACQkSH6YFAO4CAAAA.',
Ex='Exodyce:BAAALgAECgQJBAAAAA==.',
Ey='Eyecantsee:BAAALgADCgIJAgABLgAECgIJAgADAAAAAA==.',
Fa='Faene:BAAALgAECgQJCgABLgAECgUJBQADAAAAAA==.Faire:BAAALgADCgUJBQABLgAFFAQJCgAFAFYZAA==.Fairytale:BAACLgAFFH8dAAMhAAcJhxFLAwDPAQAhAAcJhxFLAwDPAQAfAAEJMwjHEwBGAAAuAAQKf0EAAyEACQlmIAAHANUCACEACQlmHQAHANUCAB8ABwn5HkcSAE4CAAAA.Faitza:BAAALgAECgYJCgAAAA==.Fantastico:BAAALgAECgUJDQAAAA==.',
Fe='Felheim:BAACLgAFFH8PAAIMAAUJPwrwOQApAQAMAAUJPwrwOQApAQAuAAQKfyQAAgwACQlrHAMcAGICAAwACQlrHAMcAGICAAAA.Fellitha:BAABLgAECn8UAAIJAAgJKwLGOgCcAAAJAAgJKwLGOgCcAAAAAA==.Fellithà:BAAALgAECgYJDAAAAA==.Felrend:BAAALgADCgMJAgAAAA==.Fentertained:BAAALgADCgcJCAAAAA==.',
Fi='Fiercevalkyr:BAAALgAECgkJBgAAAA==.Firsttower:BAAALgADCgIJAgAAAA==.Fists:BAACLgAFFH8UAAIVAAQJfyCpGwBnAQAVAAQJfyCpGwBnAQAuAAQKfzUABBUACQlMHV8MAMQCABUACQlMHV8MAMQCABAABAlOFrRdAMwAACIAAwlrFMhQALcAAAAA.Fizle:BAABLgAECn8ZAAIjAAgJWAq1GABAAQAjAAgJWAq1GABAAQAAAA==.',
Fl='Flink:BAAALgAECgYJEwAAAA==.',
Fr='Friend:BAAALgAECgYJEAAAAA==.Frostmoan:BAAALgAFFAEJAQAAAA==.Frostyninja:BAABLgAECn8jAAIFAAgJlgarjQAWAQAFAAgJlgarjQAWAQAAAA==.',
Ga='Gabryal:BAABLgAECn8nAAIgAAkJSyDvBgDcAgAgAAkJSyDvBgDcAgAAAA==.Galthur:BAAALgAECgUJCQAAAA==.Ganbatte:BAAALgAECgYJBgAAAA==.Garchomp:BAAALgAECgUJEwAAAA==.',
Ge='Gellina:BAAALgAECgUJBgAAAA==.Georg:BAACLgAFFH8bAAIOAAYJuRwPAwDIAQAOAAYJuRwPAwDIAQAuAAQKfzIAAg4ACQm7JjADAKMDAA4ACQm7JjADAKMDAAAA.Gerbankis:BAAALgAECgMJAwAAAA==.',
Gh='Ghoul:BAACLgAFFH8GAAIIAAIJICVanwDJAAAIAAIJICVanwDJAAAuAAQKfxoAAggACAmSI+gZAOECAAgACAmSI+gZAOECAAAA.Ghouligan:BAAALgAECgQJBAAAAA==.',
Gi='Giga:BAAALgADCgcJCwAAAA==.',
Gl='Glaiver:BAABLgAECn8eAAIkAAkJbQ5hHACJAQAkAAkJbQ5hHACJAQAAAA==.Glassjaw:BAAALgADCgUJBQAAAA==.',
Go='Goewin:BAAALgAFFAEJAQAAAA==.Gojo:BAAALgADCgYJDwAAAA==.Gorgrom:BAAALgADCgIJAgAAAA==.',
Gr='Gradiant:BAAALgAECgEJAgABLgAECgkJNgAKAKwXAA==.Greg:BAAALgAECgIJAgAAAA==.Gregorz:BAAALgAECgEJAQAAAA==.',
Gu='Gulgodeth:BAAALgAECgQJBQAAAA==.Gulgrimmar:BAACLgAFFH8dAAMLAAgJFyAKBQBYAgALAAcJ7CAKBQBYAgAKAAEJPQxKIABRAAAuAAQKfzcAAgsACQnnJqwAANkDAAsACQnnJqwAANkDAAAA.Guwudanielle:BAAALgAFFAIJAgABLgAFFAQJCgAFAFYZAA==.',
Ha='Hailsstorm:BAAALgADCgcJEgAAAA==.Hardfeelings:BAABLgAECn8cAAIOAAgJ+hk3PwD+AQAOAAgJ+hk3PwD+AQAAAA==.Harkness:BAAALgAECgYJDwAAAA==.Hassif:BAAALgAECgEJAQAAAA==.',
He='Heimerdoodle:BAAALgAECggJEwAAAA==.Hemlawk:BAAALgAECgEJAQAAAA==.Hemus:BAAALgAECgMJAwAAAA==.Hexed:BAABLgAECn8sAAIQAAkJcA48HgCrAQAQAAkJcA48HgCrAQAAAA==.',
Ho='Hochipo:BAAALgAECgEJAQAAAA==.',
Hu='Hughue:BAAALgADCgUJBQAAAA==.Hugs:BAAALgAECgYJCgAAAA==.Hurjek:BAAALgAFFAEJAQABLgAFFAQJDwAVAAEfAA==.',
Hy='Hyuna:BAAALgAECgEJAQABLgAECgcJDgADAAAAAA==.',
Ia='Iaso:BAABLgAECn8eAAIfAAkJURLIGwDaAQAfAAkJURLIGwDaAQAAAA==.',
Ic='Iconstar:BAAALgADCgMJAwAAAA==.',
Ig='Igneel:BAAALgADCgQJAQAAAA==.',
Ij='Ijustankedu:BAAALgAECgMJAwAAAA==.',
Ik='Ikiea:BAAALgAECgcJCAAAAA==.',
Il='Ilgrim:BAABLgAECn8YAAMPAAgJWxnPKAC8AQAPAAgJWxnPKAC8AQAOAAQJ+AO2LAFIAAABLgAFFAUJDgAbACkPAA==.Ilravenll:BAACLgAFFH8OAAIbAAUJKQ/OHAAoAQAbAAUJKQ/OHAAoAQAuAAQKfyEAAhsACQmQGOgKAGoCABsACQmQGOgKAGoCAAAA.Ilyana:BAACLgAFFH8bAAIEAAcJzRk3GQAMAgAEAAcJzRk3GQAMAgAuAAQKf0EAAgQACQk2JrkDAGkDAAQACQk2JrkDAGkDAAAA.',
Im='Impavido:BAAALgAECgYJBgAAAA==.',
In='Inholy:BAABLgAECn8UAAIkAAYJohfOIQBXAQAkAAYJohfOIQBXAQAAAA==.Insights:BAAALgADCgMJAwAAAA==.',
Ir='Ironwithin:BAAALgAECgQJBAAAAA==.',
Is='Isabella:BAAALgAECgEJAQABLgAFFAQJCgAFAFYZAA==.',
It='Ithopel:BAABLgAECn8mAAIHAAYJASF6KAASAgAHAAYJASF6KAASAgAAAA==.',
Ja='Jalista:BAAALgADCgMJAwAAAA==.Jayc:BAACLgAFFH8bAAIEAAUJCSDtRQBPAQAEAAUJCSDtRQBPAQAuAAQKfx0AAgQACAlgHid0AOoBAAQACAlgHid0AOoBAAAA.',
Je='Jereico:BAACLgAFFH8hAAIZAAgJmCLrAACQAgAZAAgJmCLrAACQAgAuAAQKfzsAAhkACQnmJlgAAJMDABkACQnmJlgAAJMDAAAA.Jeryhn:BAACLgAFFH8dAAIPAAgJnhJEAgDZAQAPAAgJnhJEAgDZAQAuAAQKf0EAAg8ACQk8GhYTAHoCAA8ACQk8GhYTAHoCAAAA.',
Jo='Joeburrow:BAAALgAECgQJBAAAAA==.Joeynodz:BAAALgADCgYJEgAAAA==.Jortshorts:BAABLgAECn8vAAIlAAkJ+AmNGAA5AQAlAAkJ+AmNGAA5AQAAAA==.',
Jr='Jray:BAABLgAECn8VAAIOAAYJGRnOZAC3AQAOAAYJGRnOZAC3AQAAAA==.',
Ju='Juggalo:BAACLgAFFH8OAAMNAAQJmSFlAQCLAQANAAQJmSFlAQCLAQAZAAEJkQauYQA3AAAuAAQKfysAAw0ACQllIncBANsCAA0ACQllIncBANsCABkAAgmJEv+BAEkAAAAA.June:BAACLgAFFH8eAAIVAAcJmhmxAQAaAgAVAAcJmhmxAQAaAgAuAAQKfz8AAxUACQlsIbMEAB0DABUACQlsIbMEAB0DACIACQkGH9wIAK0CAAAA.Juuju:BAAALgAECgYJDwAAAA==.',
Ka='Kaldriss:BAAALgAECgEJAgAAAA==.Kalen:BAAALgADCgEJAgAAAA==.Katashimus:BAAALgAECgYJDAAAAA==.Kawasuoo:BAABLgAECn8fAAMHAAgJMR14IQAzAgAHAAcJzhx4IQAzAgAmAAYJAAwtOwClAAAAAA==.Kaze:BAAALgAECgcJEQAAAA==.',
Kh='Khaotichic:BAABLgAECn8eAAIFAAYJCA48jQAXAQAFAAYJCA48jQAXAQAAAA==.Khrenak:BAAALgAECgUJCwAAAA==.',
Ki='Kickpunch:BAAALgAECgYJDgAAAA==.Kirah:BAACLgAFFH8HAAIZAAIJmByXRQCkAAAZAAIJmByXRQCkAAAuAAQKfyAAAhkACQmwIWoEAEoDABkACQmwIWoEAEoDAAEuAAUUBAkKAAUAVhkA.',
Kl='Kläus:BAAALgAECgEJAQAAAA==.',
Ko='Koddin:BAABLgAECn8zAAIOAAkJ6h6KJABpAgAOAAkJ6h6KJABpAgAAAA==.Korenchkin:BAAALgAECgEJAgAAAA==.Koreth:BAACLgAFFH8fAAMbAAYJLCH9CgC9AQAbAAUJLCH9CgC9AQASAAEJAACyBwA5AAAuAAQKf0cAAxsACQmAJpEBAFEDABsACQmAJpEBAFEDABIACAmWGg8EAHcCAAAA.Kornholyo:BAAALgAECgEJAQAAAA==.',
Kr='Kragoth:BAAALgADCgIJAgAAAA==.',
Ku='Kutuzov:BAABLgAECn8eAAIKAAUJRBasWwA6AQAKAAUJRBasWwA6AQAAAA==.',
Kw='Kwaiza:BAAALgAECgYJDwAAAA==.',
['Ká']='Káel:BAAALgAECgMJAwAAAA==.',
La='Lailaysia:BAABLgAECn8XAAIfAAkJFR98BgABAwAfAAkJFR98BgABAwAAAA==.Lamemoosaur:BAAALgADCgIJAgABLgAECgYJCgADAAAAAA==.Laríca:BAACLgAFFH8ZAAIPAAUJ7CUCCAAgAgAPAAUJ7CUCCAAgAgAuAAQKfzEAAg8ACQmDJYMCAFIDAA8ACQmDJYMCAFIDAAAA.Laustin:BAABLgAECn8kAAQRAAkJXhuxCQB/AgARAAkJVhuxCQB/AgAnAAYJEhAGGgDTAAAFAAIJbwVo+QBUAAAAAA==.Laustinjung:BAAALgADCgIJAQAAAA==.Laydout:BAAALgAECggJEgABLgAECgkJIAAFAG8iAA==.Laydoutyota:BAABLgAECn8gAAIFAAkJbyKVDwDLAgAFAAkJbyKVDwDLAgAAAA==.',
Le='Leag:BAABLgAECn8YAAMTAAcJFw+MQACiAQATAAcJFw+MQACiAQAeAAEJJAmvPwA5AAAAAA==.Lemonruss:BAAALgADCgQJBAAAAA==.',
Li='Liaria:BAAALgAECgEJAQAAAA==.Lilea:BAACLgAFFH8JAAIFAAMJUhqhUQDvAAAFAAMJUhqhUQDvAAAuAAQKfzUAAwUACQnFH6kTAKoCAAUACQnFH6kTAKoCACcABwnrEfc0AJYBAAAA.Lionsmane:BAAALgAECgcJCwABLgAECgkJHwAfAKgYAA==.Lithium:BAAALgADCgUJBQAAAA==.Littledeb:BAAALgAFFAEJAQAAAA==.',
Lo='Lockdots:BAAALgADCgIJAgAAAA==.Lolchaosbolt:BAAALgADCgYJBgAAAA==.Lortherian:BAABLgAECn8VAAMdAAgJ9h8WCQBaAgAdAAgJ9h8WCQBaAgATAAEJugyxnAAyAAAAAA==.Lowbo:BAAALgADCgUJBQAAAA==.Lowelfesteem:BAAALgADCgUJBQAAAA==.',
Lu='Lucey:BAAALgAECgEJAgAAAA==.Lucille:BAABLgAECn8aAAIEAAYJ3gdh1gDiAAAEAAYJ3gdh1gDiAAAAAA==.',
Ly='Lyndira:BAAALgAECgUJBQAAAA==.',
['Lä']='Läwlbringer:BAAALgAECggJDQAAAA==.',
['Lî']='Lîghtt:BAAALgADCgQJBAAAAA==.',
Ma='Mabritos:BAAALgAECgQJBQABLgAFFAYJGgAnAJ8eAA==.Maccabee:BAAALgAECgEJAQAAAA==.Malison:BAAALgAECgIJAgAAAA==.Mania:BAAALgADCgYJBgABLgAECgkJIwATAL8dAA==.Mathath:BAACLgAFFH8NAAIIAAQJ5QvVcAASAQAIAAQJ5QvVcAASAQAuAAQKfxwAAwgACAn4FxBTAMMBAAgACAnIFxBTAMMBAAkABAlUFacoAPkAAAAA.Mathmath:BAAALgAECgUJCgABLgAFFAEJAQADAAAAAA==.Mathoras:BAABLgAECn8aAAIBAAkJKBa8MwAFAgABAAkJKBa8MwAFAgAAAA==.Mazraq:BAAALgAECgEJAgABLgAECgkJNgAKAKwXAA==.',
Me='Meandean:BAAALgAECgIJBgAAAA==.Meatier:BAAALgAECgcJCQABLgAECgkJIwATAL8dAA==.Meatless:BAAALgADCgcJDQAAAA==.',
Mi='Micmac:BAAALgAECgQJCQAAAA==.Milo:BAAALgAECgQJBgAAAA==.Miltonroe:BAABLgAECn8iAAIGAAgJ6Q6jFABhAQAGAAgJ6Q6jFABhAQAAAA==.Mirithul:BAAALgADCgYJBwAAAA==.Mischiëf:BAAALgAECgcJEgAAAA==.Mitsuri:BAABLgAECn8iAAIEAAgJoQrekgCtAQAEAAgJoQrekgCtAQAAAA==.',
Mo='Modr:BAAALgAECgkJEgAAAA==.Moiraine:BAAALgAECgEJAQAAAA==.Monkynate:BAAALgAECgYJCgAAAA==.Monsterskill:BAABLgAECn8jAAQUAAgJgBseEAAsAQAUAAYJtxoeEAAsAQABAAUJdBmlkwAQAQACAAUJhxNULQAIAQAAAA==.Moonerva:BAABLgAECn8gAAIoAAkJEA2LJwCFAQAoAAkJEA2LJwCFAQAAAA==.Morpheos:BAAALgADCgQJBAAAAA==.Mortgage:BAAALgADCgUJBQAAAA==.',
Mu='Mutsu:BAAALgADCgcJBwAAAA==.',
Mv='Mvqchx:BAAALgAECgUJCQAAAA==.',
['Mì']='Mìssy:BAAALgAECgEJAQAAAA==.',
Na='Naturelass:BAAALgADCgUJBQAAAA==.Nausicaa:BAAALgAECgEJAQAAAA==.Nawwll:BAAALgADCgMJAwAAAA==.',
Ne='Neotama:BAAALgAECggJEgAAAA==.Nethis:BAABLgAECn8nAAIgAAgJmRx/FQAYAgAgAAgJmRx/FQAYAgAAAA==.',
Ni='Niatpacgrom:BAACLgAFFH8MAAIGAAQJmw7kCAAgAQAGAAQJmw7kCAAgAQAuAAQKfyIAAgYACQlsGTcHAE8CAAYACQlsGTcHAE8CAAAA.Nivla:BAAALgADCgMJAwAAAA==.',
No='Nobacon:BAAALgAECgYJDAAAAA==.Nokix:BAAALgADCgkJDgAAAA==.Nonorcman:BAAALgAECgIJAgAAAA==.Norah:BAAALgAECgEJAQAAAA==.Norvis:BAAALgAECgQJBQAAAA==.Notdragon:BAABLgAECn8VAAIEAAQJrQpC7QDAAAAEAAQJrQpC7QDAAAAAAA==.',
Nu='Nukeddukem:BAAALgAECgYJEgAAAA==.',
Nv='Nv:BAAALgAECggJEwAAAA==.',
Ny='Nymrod:BAABLgAECn8sAAMBAAkJSBR5NwD2AQABAAkJSBR5NwD2AQACAAIJpgduZQBEAAAAAA==.',
['Ní']='Nír:BAAALgAECgQJBAAAAA==.',
Ob='Oben:BAAALgAECggJAQAAAA==.',
Oj='Ojou:BAAALgADCgMJAwABLgAFFAMJAwADAAAAAA==.',
Om='Omizzig:BAAALgAECgcJDQAAAA==.',
On='Onepunch:BAAALgAECgQJCAAAAA==.',
Or='Orcman:BAAALgADCgIJAgABLgAECgIJAgADAAAAAA==.Orloran:BAAALgADCgIJAgAAAA==.',
Ot='Otterknight:BAAALgADCgkJCQABLgAECggJHwAHADEdAA==.',
Pa='Palthur:BAAALgAECgYJDQAAAA==.Parria:BAABLgAECn8UAAIBAAcJ8REecQBTAQABAAcJ8REecQBTAQABLgAECgkJFwAfABUfAA==.Pasqualino:BAAALgAECgYJCgAAAA==.Passionate:BAACLgAFFH8MAAIjAAQJwAxqGgDaAAAjAAQJwAxqGgDaAAAuAAQKfyYAAiMACAmfFFYVAPUBACMACAmfFFYVAPUBAAAA.',
Pe='Peepis:BAAALgADCgEJAQABLgAECgkJIwATAL8dAA==.Pennance:BAABLgAECn8iAAIPAAkJ/RuZDgCiAgAPAAkJ/RuZDgCiAgAAAA==.',
Ph='Phatmidas:BAABLgAECn81AAIOAAkJyBklMwApAgAOAAkJyBklMwApAgAAAA==.Philth:BAAALgAECgUJBgAAAA==.',
Pi='Pistfist:BAAALgAECgcJAQAAAA==.',
Pl='Plagueground:BAACLgAFFH8YAAIIAAYJYCCoDABSAgAIAAYJYCCoDABSAgAuAAQKf0QAAggACQnhJgUCAHwDAAgACQnhJgUCAHwDAAAA.Plutonyus:BAAALgAECgEJAQAAAA==.',
Po='Poc:BAABLgAECn8ZAAIEAAYJPB3wdADoAQAEAAYJPB3wdADoAQAAAA==.Pockets:BAAALgAECgMJBwAAAA==.Potatopotato:BAACLgAFFH8OAAIbAAQJAxMHGABEAQAbAAQJAxMHGABEAQAuAAQKfyIAAhsACQk0FSUcAB4CABsACQk0FSUcAB4CAAAA.Pounces:BAAALgAECgYJEgABLgAECgcJGAAZAKgXAA==.Powerfistin:BAAALgADCgcJBwAAAA==.',
Pr='Prosecutor:BAAALgAECgUJDAAAAA==.Prozak:BAAALgAECgUJCQABLgAFFAMJCwAQANoFAA==.Prynts:BAABLgAECn8VAAIOAAcJZh3sRAAVAgAOAAcJZh3sRAAVAgAAAA==.Prøzak:BAACLgAFFH8LAAIQAAMJ2gUyPACoAAAQAAMJ2gUyPACoAAAuAAQKfxUAAhAACAl5C3gyAC8BABAACAl5C3gyAC8BAAAA.',
Ps='Psychomidget:BAAALgAECgYJCgAAAA==.',
Pu='Puetrid:BAAALgADCgYJBgABLgAECgQJBAADAAAAAA==.',
Ra='Raanky:BAAALgAECgEJAQAAAA==.Radiantlight:BAACLgAFFH8FAAIhAAIJjANgPQBsAAAhAAIJjANgPQBsAAAuAAQKfxYAAiEACAm8ELEcANoBACEACAm8ELEcANoBAAAA.Randomly:BAAALgAECgQJBAAAAA==.Raspberries:BAAALgAECgcJBwAAAA==.Rautha:BAAALgAECgkJEgAAAA==.Rayl:BAABLgAECn8cAAMIAAcJvBrNRwDjAQAIAAcJvBrNRwDjAQAJAAEJ5QFNYQAcAAAAAA==.Razsputin:BAAALgAECgMJBwAAAA==.',
Re='Rekless:BAAALgADCgUJBQAAAA==.Rethgar:BAAALgAECgUJEgAAAA==.',
Rh='Rhaegosa:BAABLgAECn8zAAQZAAkJDxk5JgClAQAZAAcJ0xk5JgClAQAjAAQJjBasGgAmAQANAAQJrg2rFgCfAAAAAA==.Rhavik:BAAALgAECgQJBgAAAA==.Rhekt:BAAALgAECgIJBQAAAA==.Rhok:BAAALgAECgEJAQAAAA==.Rhokladar:BAAALgAECgUJCwAAAA==.',
Ri='Rickylafleur:BAAALgAECgEJAQAAAA==.Ridcully:BAABLgAECn8bAAIHAAgJlxc4OACsAQAHAAgJlxc4OACsAQAAAA==.Rimath:BAAALgAECgcJBAAAAA==.Rinswind:BAAALgADCgMJAwAAAA==.',
Ro='Robopacman:BAACLgAFFH8WAAQYAAUJECGLCABJAQAIAAQJvyBASABRAQAYAAQJdRiLCABJAQAJAAEJAADpQQAAAAAuAAQKfzoABAgACQkEJRgPACMDAAgACQnyJBgPACMDAAkACAlDItsGAKgCABgAAgnhGLYkAJUAAAAA.Rodstewart:BAACLgAFFH8ZAAMFAAgJShiAEQCwAQAFAAUJSxyAEQCwAQAnAAUJUgzvFAD2AAAuAAQKfycAAwUACQmwJE0WAIYCAAUACAmPJE0WAIYCACcABwnbHxomAPgBAAAA.Roofeo:BAABLgAECn8hAAQCAAgJJBXeDQBRAQACAAYJmBbeDQBRAQAUAAQJIhXDFgD9AAABAAQJcgzMvwDGAAABLgAFFAMJBwAJAKAQAA==.Rotdaddy:BAABLgAECn8oAAIIAAkJFQWOjwA+AQAIAAkJFQWOjwA+AQAAAA==.',
Ry='Ryoshin:BAAALgADCgEJAQABLgAECgYJDQADAAAAAA==.Ryzel:BAAALgADCgUJBQAAAA==.',
['Rï']='Rïn:BAAALgADCgEJAQAAAA==.',
Sa='Sabatikus:BAAALgAECgIJAgAAAA==.Salas:BAABLgAECn8UAAIBAAcJzgzJiwAeAQABAAcJzgzJiwAeAQAAAA==.Salino:BAABLgAECn8UAAMlAAcJ3Bi6DgC4AQAlAAcJ3Bi6DgC4AQAHAAUJbQYniwCWAAAAAA==.Salinoster:BAAALgAECgEJAgAAAA==.Salordell:BAAALgADCgIJAwAAAA==.Sam:BAAALgADCgEJAQAAAA==.Sanque:BAAALgAECgMJAwAAAA==.Sarate:BAABLgAECn8rAAIgAAgJ3A7NKwBvAQAgAAgJ3A7NKwBvAQAAAA==.Savannah:BAABLgAFFH8KAAIFAAQJVhl0NAA5AQAFAAQJVhl0NAA5AQAAAA==.Savvtwo:BAAALgADCgcJBwABLgAFFAgJHQAMAPEiAQ==.',
Sc='Scathach:BAABLgAECn8gAAMMAAcJ4x5VOgDSAQAMAAcJ4x5VOgDSAQAkAAQJURguRADmAAABLgAFFAEJAQADAAAAAA==.Scoop:BAAALgADCgYJBgAAAA==.Scorandom:BAAALgAECgEJAQAAAA==.',
Se='Seetani:BAAALgADCgUJBgABLgAECgQJBgADAAAAAA==.Semko:BAAALgAECgEJAgAAAA==.Seven:BAAALgAECgcJCgAAAA==.Sezra:BAAALgADCgkJAQAAAA==.',
Sh='Shamalam:BAAALgADCgEJAQAAAA==.Shei:BAAALgAECgIJAgAAAA==.Sheidon:BAAALgAECgQJBAAAAA==.Shinanigans:BAAALgAECgYJDwAAAA==.Shruikan:BAAALgADCggJDAAAAA==.',
Si='Silverslam:BAAALgAECgEJAQABLgAECggJGAAGAEESAA==.Sinatra:BAAALgAECgIJBAABLgAECgcJEQADAAAAAA==.Siqodel:BAAALgADCgYJCAAAAA==.',
Sk='Skurge:BAABLgAECn8UAAMYAAgJagroFAAlAQAYAAgJagroFAAlAQAIAAMJgQN2JAFqAAAAAA==.',
Sl='Slamb:BAAALgAECgYJBwAAAA==.Slimetongue:BAAALgADCgMJAwAAAA==.',
Sm='Smaaug:BAAALgAFFAMJBAAAAA==.',
Sn='Snuggle:BAAALgAECgEJAQAAAA==.',
So='Solstis:BAAALgAECggJDgAAAA==.Sookie:BAAALgADCgIJAgAAAA==.Sorzsnipe:BAAALgADCgQJBAAAAA==.',
Sp='Spellchücker:BAAALgAECgcJDQAAAA==.Spfzero:BAAALgAECgIJAgAAAA==.',
St='Staggered:BAACLgAFFH8PAAIQAAQJoh56GQBHAQAQAAQJoh56GQBHAQAuAAQKfyUAAxAACAkOIusLAM8CABAACAkOIusLAM8CACIAAQk1A9WMABwAAAAA.Stiffbutt:BAAALgAECgEJAQAAAA==.Stonebeard:BAAALgAECgIJAgAAAA==.Stoneojinray:BAAALgADCgEJAQAAAA==.Stoneorcman:BAAALgADCgcJBwABLgAECgIJAgADAAAAAA==.Stormriderr:BAAALgAECgYJCQAAAA==.',
Su='Subdofu:BAAALgADCgQJBAABLgAECgcJFwAbAN0cAA==.Subtox:BAABLgAECn8XAAMbAAcJ3RxNIQDvAQAbAAcJ3RxNIQDvAQASAAEJkgu5HwA0AAAAAA==.',
Sw='Sweetcool:BAAALgAECgUJCQABLgAECggJLgAFAP4jAA==.Sweetzeke:BAAALgAECgEJAQAAAA==.',
Sy='Syphilistjt:BAABLgAECn8WAAIhAAgJ0xLIFwDgAQAhAAgJ0xLIFwDgAQAAAA==.Syphillis:BAAALgAECgYJCgAAAA==.',
['Sá']='Sálud:BAACLgAFFH8MAAIoAAUJix9MFwBIAQAoAAUJix9MFwBIAQAuAAQKfywAAygACAmnI5IHANICACgACAmnI5IHANICACYABwmhGTcUAKMBAAAA.',
['Sê']='Sêp:BAAALgAECggJDgAAAA==.',
Ta='Takoda:BAAALgAECgEJAgAAAA==.Talivath:BAAALgAECgUJCQAAAA==.Tanissaria:BAAALgADCgIJAgAAAA==.Taranith:BAAALgAECgUJBQABLgAECggJGQAEAPoTAA==.Tarhealeon:BAABLgAECn9wAAMOAAkJ+xVMOAAWAgAOAAkJ+xVMOAAWAgAPAAkJyRuWIQARAgAAAA==.Tarmander:BAAALgAECgYJDgAAAA==.Taylörshift:BAAALgAECgQJBwAAAA==.',
Te='Telahnicus:BAAALgAECgEJAQAAAA==.Terranox:BAAALgADCgMJAwAAAA==.Testostauren:BAAALgAECgQJCAAAAA==.',
Th='Thabigone:BAAALgAECgYJDAAAAA==.Thalnaria:BAAALgAECgYJCwAAAA==.Threebuttons:BAAALgAECgUJDgABLgAFFAQJEwAjANENAA==.Thunderkis:BAABLgAECn8XAAMFAAYJHAeuowDrAAARAAYJMQaNNwD0AAAFAAYJHAeuowDrAAAAAA==.',
Ti='Tiewaz:BAAALgAECgYJBgABLgAECggJHwAEAFoPAA==.Tiewiz:BAABLgAECn8fAAMEAAgJWg/5hgBjAQAEAAgJEQz5hgBjAQApAAUJlw2TDACgAAAAAA==.Titanarum:BAAALgAECgQJBAAAAA==.',
To='Tointjoker:BAAALgAECgUJBgAAAA==.Tolun:BAABLgAECn8/AAIEAAkJqhx9HQClAgAEAAkJqhx9HQClAgAAAA==.Tosan:BAAALgADCggJDgAAAA==.',
Tr='Treeplague:BAABLgAECn9EAAMgAAkJBxM6GAD+AQAgAAkJBxM6GAD+AQAhAAcJ8RUkHADfAQAAAA==.Trypleg:BAAALgAECgMJAwAAAA==.',
Tu='Tungie:BAABLgAECn8bAAIIAAgJ0iCjPgAAAgAIAAgJ0iCjPgAAAgAAAA==.Turn:BAACLgAFFH8kAAQBAAgJoxVyCAChAQABAAYJnhpyCAChAQACAAUJwg2+AwBcAQAUAAIJmSCdGABXAAAuAAQKf0gABAEACQlRJr8UANkCAAEACAliJb8UANkCABQAAwlJJtYaANYAAAIAAwmxJBoZANAAAAAA.Turtleduck:BAABLgAECn8fAAINAAgJ/BivBQD0AQANAAgJ/BivBQD0AQAAAA==.Tuskbreaker:BAAALgAECgIJAgAAAA==.',
Tw='Twittytister:BAAALgADCgQJBAAAAA==.Twostrokes:BAAALgAECgEJAQAAAA==.',
Ty='Tyrese:BAAALgADCggJEAAAAA==.',
Uf='Uffin:BAAALgAECgQJBQAAAA==.',
Um='Umbryx:BAAALgAECgYJDQAAAA==.',
Un='Unagi:BAABLgAECn8bAAIGAAkJTxMeCQAgAgAGAAkJTxMeCQAgAgAAAA==.Unholy:BAAALgADCgIJAgAAAA==.',
Va='Valdi:BAABLgAECn8ZAAIOAAcJkww4tgAKAQAOAAcJkww4tgAKAQAAAA==.',
Ve='Velthera:BAABLgAECn8XAAIjAAgJCyJEBAAQAwAjAAgJCyJEBAAQAwABLgAFFAQJDwAVAAEfAA==.Venomlight:BAAALgADCgIJAgAAAA==.Venomstrikes:BAAALgAECgcJEwAAAA==.Venratzi:BAAALgAECgQJBAAAAA==.Vespertina:BAAALgAECgIJAgAAAA==.',
Vi='Viscerion:BAAALgAECgUJBQAAAA==.',
Vo='Voridor:BAAALgADCgEJAQAAAA==.Voulk:BAAALgAFFAMJAwABLgAFFAgJIAAjAAwbAA==.',
Vy='Vyllan:BAABLgAECn8bAAQUAAgJAQYCEwD8AAABAAgJmgWxkgASAQAUAAYJKwQCEwD8AAACAAMJmgEpPwApAAAAAA==.',
Wa='Waldgeist:BAAALgAECgUJBQABLgAECgkJIwATAL8dAA==.Walthur:BAAALgADCgkJDQAAAA==.Waobby:BAAALgADCgIJAgAAAA==.Warrpigg:BAAALgAECgEJAQAAAA==.Waterdrinker:BAAALgAECgQJBgAAAA==.Wavybone:BAAALgAECgEJAgAAAA==.',
Wh='Whickedthur:BAAALgAECgYJBgAAAA==.Whiisper:BAAALgADCgMJAwAAAA==.Whoarlock:BAAALgADCgUJCAAAAA==.',
Wi='Wimp:BAAALgAECgEJAQAAAA==.',
Wo='Wo:BAAALgAFFAEJAQAAAA==.',
Wu='Wutangstyle:BAAALgAECgIJAgABLgAECgkJIwATAL8dAA==.',
Wy='Wyatta:BAAALgADCgIJAgAAAA==.',
Xe='Xelinia:BAACLgAFFH8RAAIgAAUJoxKuCgAJAQAgAAUJoxKuCgAJAQAuAAQKfyEAAiAACQk5H20MALwCACAACQk5H20MALwCAAAA.Xen:BAABLgAFFH8JAAIlAAQJ8hs/BABoAQAlAAQJ8hs/BABoAQAAAA==.',
Xf='Xfortune:BAAALgADCgcJCQAAAA==.',
Xh='Xholycritz:BAAALgAECgMJBAAAAA==.Xhöly:BAAALgAECgEJAQAAAA==.',
Xu='Xuefeng:BAACLgAFFH8YAAIiAAUJ0x66CgBmAQAiAAUJ0x66CgBmAQAuAAQKfzcAAiIACQl7IBYHANACACIACQl7IBYHANACAAAA.',
Ya='Yahwae:BAAALgADCgUJBQABLgAECgkJNQABAH0YAA==.',
Ye='Yenchmeister:BAACLgAFFH8cAAMTAAcJkxxEAwDDAQATAAUJuRxEAwDDAQAeAAYJ3RoAAgBiAQAuAAQKfygAAxMACQkgJdcJABEDABMACQkgJdcJABEDAB4AAgl3ICEoAK4AAAAA.',
Yo='Youngbusta:BAABLgAECn8zAAIEAAkJ9iKGEwDfAgAEAAkJ9iKGEwDfAgAAAA==.',
Yu='Yuta:BAAALgAECgYJDQAAAA==.',
Za='Zad:BAAALgADCgIJAgAAAA==.',
Ze='Zenrac:BAAALgADCgUJBQAAAA==.Zeromus:BAAALgAECgIJAgAAAA==.',
Zi='Zilvanic:BAACLgAFFH8OAAIXAAQJxwhVCwCzAAAXAAQJxwhVCwCzAAAuAAQKfyQABBcACAlgErUVAGsBABcACAn0EbUVAGsBAA4ABQlZEPPnAMcAAA8AAwl8AQiDAGwAAAAA.Zilvanion:BAABLgAFFH8FAAIUAAMJ0QPACgC8AAAUAAMJ0QPACgC8AAAAAA==.',
Zo='Zourknight:BAAALgAECgYJBgAAAA==.Zourlight:BAAALgAECgQJBQAAAA==.Zourlock:BAABLgAECn8XAAQBAAYJdRCvkwAQAQABAAYJAQ+vkwAQAQAUAAIJJhKNJQB8AAACAAEJAAAlbwA3AAAAAA==.Zourpatch:BAAALgADCgMJAwAAAA==.',
Zu='Zulvaz:BAAALgAECgIJAwAAAA==.Zurey:BAABLgAECn88AAIMAAkJVg1yVwB1AQAMAAkJVg1yVwB1AQAAAA==.',
Zy='Zynjamin:BAACLgAFFH8gAAMNAAgJ0iE9AAADAgAZAAcJFCG6BwBdAgANAAYJ6yM9AAADAgAuAAQKfy4AAg0ACQkLJC8AANsDAA0ACQkLJC8AANsDAAAA.',
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
