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
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aannte:BAACLgAFFH8ZAAMBAAgJyhgABgDAAQABAAYJCRcABgDAAQACAAQJ8hc+BwAFAQAuAAQKfyIAAwEACQlVIowmAHgCAAEACQlGIowmAHgCAAIABAnwHvcdAGABAAAA.Aardbark:BAAALgADCgEJAQAAAA==.',
Ab='Abúsedyoû:BAAALgADCgQJBgAAAA==.',
Ac='Achtland:BAAALgAECgUJBgABLgAFFAEJAQADAAAAAA==.',
Ad='Adekai:BAAALgAECgYJDwAAAA==.Adv:BAAALgAECgEJAQAAAA==.',
Ae='Aerestrix:BAAALgAECgYJBwAAAA==.',
Ai='Airvis:BAABLgAECn8pAAIEAAcJBgwLkQA7AQAEAAcJBgwLkQA7AQAAAA==.',
Al='Alacia:BAAALgAECgkJEAABLgAFFAMJCQAFAFIaAA==.Alatarr:BAAALgAECgcJEQAAAA==.Albinomonk:BAAALgADCgcJBwAAAA==.',
An='Anankei:BAAALgAECgQJBQAAAA==.Annastrophic:BAAALgADCgMJAwAAAA==.Anrí:BAAALgAECgEJAQAAAA==.Antaria:BAAALgADCgcJFgAAAA==.Ante:BAAALgADCgUJAQAAAA==.Antiform:BAAALgAECgMJBwAAAA==.Antpony:BAAALgAECgIJAgABLgAECgYJCgADAAAAAA==.',
Aq='Aqulara:BAAALgAECgEJAQAAAA==.',
Ar='Arcish:BAAALgAECgEJAgAAAA==.Arjun:BAABLgAECn8YAAIGAAgJQRJMDwCdAQAGAAgJQRJMDwCdAQAAAA==.Arkirla:BAAALgAECgEJAgAAAA==.Arkiyra:BAAALgAECggJDgAAAA==.Arklira:BAAALgAECgEJAQAAAA==.Arkosh:BAAALgAECgEJAgAAAA==.Arkyra:BAAALgAECgUJBwAAAA==.Arovix:BAABLgAECn8ZAAIHAAgJVBqKKAD7AQAHAAgJVBqKKAD7AQAAAA==.',
As='Ashwey:BAAALgADCgkJCAAAAA==.',
At='Atom:BAABLgAECn8cAAIFAAkJRRQlKwAaAgAFAAkJRRQlKwAaAgAAAA==.',
Au='Aubreey:BAAALgADCgcJCQAAAA==.Aureille:BAAALgAECgYJCgAAAA==.',
Aw='Awoozehl:BAACLgAFFH8fAAMIAAcJLiCuGQDMAQAIAAYJLiCuGQDMAQAJAAEJAAAFPwAAAAAuAAQKfz0AAggACQnWJqYBAH4DAAgACQnWJqYBAH4DAAAA.',
Az='Azanoth:BAAALgAECgYJCQABLgAECgkJIwAJAIEUAA==.Azgrodon:BAABLgAECn82AAMKAAkJrBeBGQBlAgAKAAkJrBeBGQBlAgALAAMJjww+bACSAAAAAA==.Azor:BAABLgAECn8YAAIMAAgJch08HQCiAgAMAAgJch08HQCiAgAAAA==.',
Ba='Baja:BAAALgAECgQJBAAAAA==.Baldomar:BAAALgADCgUJCAAAAA==.Bangmonk:BAAALgAFFAQJBAABLgAFFAgJIAANACAgAA==.Bangungot:BAAALgADCgMJAwABLgAFFAgJIAANACAgAA==.Barristan:BAAALgAECgUJCgAAAA==.Barzalie:BAAALgAECgYJDAABLgAFFAMJAwADAAAAAA==.Bathrezz:BAABLgAECn8gAAMOAAkJoxcOSQDTAQAOAAkJoxcOSQDTAQAPAAMJWA+aYQCSAAAAAA==.',
Be='Bearyonce:BAAALgAFFAEJAQAAAA==.Beerbelly:BAAALgAFFAMJAwAAAA==.Beleaves:BAACLgAFFH8gAAIQAAgJYQeQBgBqAQAQAAgJYQeQBgBqAQAuAAQKf0EAAhAACQlbHT8JAI4CABAACQlbHT8JAI4CAAAA.Beorl:BAAALgADCgYJCAAAAA==.',
Bh='Bhackshots:BAABLgAECn8XAAIRAAUJjSGkKQBDAQARAAUJjSGkKQBDAQABLgAECgkJNQASAPkjAA==.',
Bi='Bifurious:BAABLgAECn8jAAITAAkJvx2SDACOAgATAAkJvx2SDACOAgAAAA==.Bigrob:BAAALgAECgEJBQAAAA==.',
Bl='Blowmybubble:BAAALgAECgEJAQABLgAECgkJIAAFAKchAA==.Bluereindeer:BAABLgAECn8VAAIIAAkJAgt/XACeAQAIAAkJAgt/XACeAQAAAA==.',
Bo='Bobsstones:BAACLgAFFH8dAAQBAAgJlB7QAwDkAQABAAcJWB3QAwDkAQACAAQJ6x0sBgANAQAUAAIJPSOPCADHAAAuAAQKfykABAIACQlCJT0GAGwCAAEABwmkJP4bAK0CAAIABgmDJD0GAGwCABQAAwm6JOgVANUAAAAA.Bonekitty:BAAALgAECgYJBgAAAA==.Bonkulo:BAABLgAECn8jAAMJAAkJgRS4EgDIAQAJAAgJ6ha4EgDIAQAIAAEJoQPIZwEmAAAAAA==.Boofassist:BAABLgAECn8dAAIPAAkJ7CKABAAmAwAPAAkJ7CKABAAmAwABLgAFFAcJGQAVANgZAA==.Boogey:BAABLgAECn8fAAMEAAgJfQ1NeABtAQAEAAgJfQ1NeABtAQAWAAEJpQiNEAAyAAAAAA==.Boompowwow:BAABLgAECn8VAAILAAYJIxnmNACDAQALAAYJIxnmNACDAQAAAA==.Boomsonic:BAAALgADCgUJBQABLgAECgkJIwATAL8dAA==.Bophadeez:BAABLgAECn8qAAQPAAgJeB4bHwAgAgAPAAcJGSEbHwAgAgAXAAgJ/xi1CwDzAQAOAAYJvQ/MjABhAQAAAA==.',
Br='Broccoliz:BAECLgAFFH8hAAIHAAgJ0hH0AgC9AQAHAAgJ0hH0AgC9AQAuAAQKf0IAAgcACQkUH9MYAHECAAcACQkUH9MYAHECAAAA.Brokan:BAAALgAECgYJBgAAAA==.Brokgar:BAAALgAECggJEAAAAA==.Brotu:BAAALgADCgIJAQAAAA==.Bruceleroy:BAAALgADCgEJAQAAAA==.Brutalsmasch:BAAALgADCgUJBQAAAA==.',
Bu='Bubu:BAAALgAECgEJAQAAAA==.Bulis:BAAALgAECgEJAQAAAA==.Bullblaster:BAAALgAECgMJBQAAAA==.',
Bw='Bwonshamdi:BAAALgAECgcJBwABLgAECgcJBwADAAAAAA==.',
['Bõ']='Bõb:BAAALgAECgQJCgAAAA==.',
Ca='Caden:BAAALgAECgQJBAABLgAFFAMJCQAFAFIaAA==.Cafca:BAABLgAECn86AAICAAkJgBhUAwBLAgACAAkJgBhUAwBLAgAAAA==.Cahma:BAAALgADCgYJEAAAAA==.Caitlin:BAAALgAECgEJAQABLgAFFAQJCgAFAFYZAA==.Callyour:BAAALgADCgIJAgAAAA==.Cask:BAAALgADCgYJAQAAAA==.',
Ch='Chaesol:BAAALgAFFAEJAQAAAA==.Chainsawloli:BAAALgADCgUJBQAAAA==.Changying:BAAALgAECggJDQAAAA==.Cheekung:BAAALgAECgcJEgAAAA==.Cheeseburgr:BAAALgADCgEJAQAAAA==.Choedankal:BAAALgADCgcJBwAAAA==.Chophouse:BAAALgAECgkJBgAAAA==.Chungusdelux:BAAALgAECgMJAwAAAA==.',
Cl='Clearlyumad:BAACLgAFFH8NAAQIAAUJhxCQfADlAAAIAAQJhxCQfADlAAAYAAEJkANSIQA4AAAJAAEJAAAqUAAAAAAuAAQKfxsAAggACAmPHlE8AEYCAAgACAmPHlE8AEYCAAAA.Clèrick:BAABLgAECn81AAIPAAkJKyKCBQAnAwAPAAkJKyKCBQAnAwAAAA==.',
Co='Coldcrow:BAAALgAECgEJAQAAAA==.Combination:BAACLgAFFH8PAAIVAAQJAR/EFwBoAQAVAAQJAR/EFwBoAQAuAAQKfxQAAhUACAn7IZ8HAAcDABUACAn7IZ8HAAcDAAAA.Confessor:BAAALgAECgEJAQAAAA==.Corruptions:BAAALgADCgEJAQAAAA==.',
Cr='Crux:BAAALgADCgQJBAAAAA==.',
Cy='Cyfrin:BAAALgADCgEJAQAAAA==.Cyânide:BAAALgADCgYJDQAAAA==.',
['Cõ']='Cõurage:BAAALgAECgYJCAAAAA==.',
Da='Dabbhammer:BAAALgAFFAEJAQAAAA==.Dabbyforms:BAAALgAECgIJAgABLgAFFAEJAQADAAAAAA==.Dabbzyvoker:BAABLgAECn8gAAMZAAgJgQzMMwBCAQAZAAgJQwzMMwBCAQANAAYJowZ/IgAWAQABLgAFFAEJAQADAAAAAA==.Dallzbeep:BAAALgAECgkJCQABLgAFFAQJEAAVAH8gAA==.Danathoor:BAAALgADCggJCAAAAA==.Danathor:BAAALgADCgcJBwAAAA==.Dangbro:BAAALgAECgYJEQAAAA==.Dankspank:BAAALgAECgQJCAAAAA==.Danteus:BAAALgADCgMJAwABLgAECgUJDwADAAAAAA==.Darkrigh:BAAALgADCggJDgAAAA==.Darkwave:BAABLgAECn8uAAIBAAkJ/xXvKwAdAgABAAkJ/xXvKwAdAgAAAA==.Darthdiddyus:BAACLgAFFH8mAAMaAAgJehx1AAAuAgAaAAcJKx51AAAuAgAbAAQJHhSnDQAQAQAuAAQKfzIABBoACQmeJIgAADEDABoACQmaJIgAADEDABsABwlRITwUAHICABIABAnJId0KAIIBAAAA.Datdruidguy:BAAALgADCgUJBQABLgAECgYJBgADAAAAAA==.Datlock:BAAALgADCgEJAQABLgAECgYJBgADAAAAAA==.Datshammy:BAAALgAECgYJBgAAAA==.Daviculas:BAAALgADCggJDgAAAA==.Dawghawg:BAAALgAECgQJBAAAAA==.Dawnnie:BAACLgAFFH8LAAIXAAMJbw8fCwCrAAAXAAMJbw8fCwCrAAAuAAQKfzkAAhcACQlDGvQHAEICABcACQlDGvQHAEICAAAA.Dawnte:BAABLgAECn8dAAIOAAcJHByFVQCxAQAOAAcJHByFVQCxAQABLgAECgUJDwADAAAAAA==.Dawsonrogers:BAAALgAFFAIJAwAAAA==.Dayvastate:BAABLgAECn83AAMIAAkJqhuFIABzAgAIAAkJqhuFIABzAgAYAAEJDxJ+LwA2AAAAAA==.Dazshir:BAAALgADCgMJAwAAAA==.',
De='Deathbanana:BAABLgAFFH8ZAAIIAAUJayL7JgCRAQAIAAUJayL7JgCRAQABLgAFFAgJGQAEAAYaAA==.Deaththreat:BAAALgAECgQJBAABLgAECggJHAAOAPoZAA==.Delema:BAACLgAFFH8RAAIOAAUJph8xCwBTAQAOAAUJph8xCwBTAQAuAAQKfyAAAg4ACAlaIUQiAKACAA4ACAlaIUQiAKACAAAA.Democrit:BAAALgAECgUJCAAAAA==.Demonjuice:BAAALgAECgcJDAAAAA==.Derpyblinker:BAABLgAECn8VAAIEAAYJQRDu0wBHAQAEAAYJQRDu0wBHAQAAAA==.Destructer:BAABLgAECn8lAAICAAgJ0hAcCwBxAQACAAgJ0hAcCwBxAQAAAA==.Dethstar:BAAALgADCgUJBQABLgAECgkJLgABAP8VAA==.Devoured:BAAALgADCgMJAwAAAA==.',
Di='Dinger:BAAALgAECgEJAQAAAA==.Dirtydinker:BAAALgAECgYJDQAAAA==.Disconneted:BAAALgADCgYJBgAAAA==.Dishwasher:BAAALgADCgIJAgAAAA==.Dixsard:BAABLgAECn81AAMSAAkJ+SPwAAARAwASAAkJxyPwAAARAwAbAAcJTx1tIwDeAQAAAA==.',
Do='Dobrova:BAAALgAECgEJAQAAAA==.Doezenn:BAAALgADCgUJBQAAAA==.Dogofwar:BAAALgAECgEJAQAAAA==.Dottprepared:BAACLgAFFH8cAAIcAAYJeRGyAABRAQAcAAYJeRGyAABRAQAuAAQKf0EAAhwACQmaIpcBAAcDABwACQmaIpcBAAcDAAAA.Dottyfu:BAABLgAFFH8FAAIQAAMJKwkTOACwAAAQAAMJKwkTOACwAAAAAA==.Doubted:BAAALgAECgQJBAAAAA==.',
Dr='Dracoiconic:BAAALgAECgEJAgAAAA==.Dragonboffa:BAAALgAECgcJAQAAAA==.Draul:BAAALgAECgEJAQABLgAECgkJNgAKAKwXAA==.Drexl:BAACLgAFFH8PAAIdAAUJghG6BQARAQAdAAUJghG6BQARAQAuAAQKfzgABB4ACQkjHhYGAIsCAB4ACQnlHRYGAIsCABMABwkSBtplABwBAB0AAgmHDHo7AHAAAAAA.Dril:BAABLgAECn8dAAMMAAgJMxkuMgDnAQAMAAgJHxkuMgDnAQAcAAIJAhZvIACBAAAAAA==.Drognin:BAAALgADCgEJAQAAAA==.Drunkfu:BAAALgADCgQJBAAAAA==.',
Du='Dubstep:BAAALgAECgkJAgAAAA==.Dudette:BAAALgAECgcJDAAAAA==.Dunlop:BAABLgAECn8fAAMfAAkJqBghDACMAgAfAAkJqBghDACMAgAgAAIJ9wTNaQBNAAAAAA==.',
Dv='Dvmcquéén:BAABLgAECn8WAAMCAAcJ5xkzCwANAgACAAcJ5xkzCwANAgABAAIJBwRHBwFOAAAAAA==.',
Dw='Dweams:BAACLgAFFH8cAAIgAAcJTxk9AQAnAgAgAAcJTxk9AQAnAgAuAAQKfzwAAyAACQmLJrwAAHIDACAACQmLJrwAAHIDACEABAmrDNE5ANgAAAAA.Dweamu:BAAALgAECgUJCQAAAA==.',
['Dâ']='Dântæ:BAAALgAECgUJDwAAAA==.',
['Då']='Dåmon:BAAALgAECgEJBAAAAA==.',
['Dö']='Döts:BAAALgADCgMJAgAAAA==.',
['Dø']='Døctøred:BAAALgAECgYJEwAAAA==.',
Ec='Ectonight:BAAALgAECgQJBwAAAA==.',
Ed='Edgybob:BAAALgAECgMJAwAAAA==.',
Eg='Eggfooyung:BAACLgAFFH8ZAAIVAAcJ2BlfCgAQAgAVAAcJ2BlfCgAQAgAuAAQKfzIAAxUACQmPIRcEAC8DABUACQmPIRcEAC8DACIABwlPCCk7ADABAAAA.Egwene:BAAALgAECgYJBwAAAA==.',
El='Eldar:BAAALgAECgUJBQAAAA==.Elfchick:BAAALgADCgEJAQAAAA==.Elhonna:BAAALgAFFAQJBAAAAA==.Elsâ:BAAALgAECgQJCAAAAA==.',
Em='Emwen:BAAALgADCgMJAwAAAA==.',
En='Endcredits:BAABLgAECn8fAAIJAAgJqg6cIQAsAQAJAAgJqg6cIQAsAQAAAA==.',
Et='Ether:BAABLgAECn8eAAILAAgJzhPUKADNAQALAAgJzhPUKADNAQAAAA==.Ettie:BAAALgAECgMJBQABLgAECgQJBgADAAAAAA==.',
Ev='Evieroot:BAAALgADCgMJAwAAAA==.Evoulker:BAACLgAFFH8gAAIjAAgJDBvyAABWAgAjAAgJDBvyAABWAgAuAAQKf0EAAiMACQkSH6YFAO4CACMACQkSH6YFAO4CAAAA.',
Ex='Exodyce:BAAALgAECgQJBAAAAA==.',
Ey='Eyecantsee:BAAALgADCgIJAgABLgADCgcJBwADAAAAAA==.',
Fa='Faene:BAAALgAECgQJCgABLgAECgUJBQADAAAAAA==.Faire:BAAALgADCgUJBQABLgAFFAQJCgAFAFYZAA==.Fairytale:BAACLgAFFH8dAAMhAAcJhxFLAwDPAQAhAAcJhxFLAwDPAQAfAAEJMwjHEwBGAAAuAAQKf0EAAyEACQlmIAAHANUCACEACQlmHQAHANUCAB8ABwn5HkcSAE4CAAAA.Faitza:BAAALgAECgYJCgAAAA==.Fantastico:BAAALgAECgUJDQAAAA==.',
Fe='Felheim:BAACLgAFFH8PAAIMAAUJPwp8MgAyAQAMAAUJPwp8MgAyAQAuAAQKfyQAAgwACQlrHE4aAGICAAwACQlrHE4aAGICAAAA.Fellitha:BAABLgAECn8UAAIJAAgJKwLGNwCdAAAJAAgJKwLGNwCdAAAAAA==.Fellithà:BAAALgAECgUJCwAAAA==.Felrend:BAAALgADCgMJAgAAAA==.Fentertained:BAAALgADCgcJCAAAAA==.',
Fi='Fiercevalkyr:BAAALgAECgkJBgAAAA==.Firsttower:BAAALgADCgIJAgAAAA==.Fists:BAACLgAFFH8QAAIVAAQJfyBDFwBtAQAVAAQJfyBDFwBtAQAuAAQKfzUABBUACQlMHVkLAMQCABUACQlMHVkLAMQCABAABAlOFrRdAMwAACIAAwlrFNVMALkAAAAA.Fizle:BAABLgAECn8YAAIjAAcJnwtRGQAsAQAjAAcJnwtRGQAsAQAAAA==.',
Fl='Flink:BAAALgAECgYJEwAAAA==.',
Fr='Friend:BAAALgAECgYJEAAAAA==.Frostmoan:BAAALgAFFAEJAQAAAA==.Frostyninja:BAABLgAECn8jAAIFAAgJlgb5hQAZAQAFAAgJlgb5hQAZAQAAAA==.',
Ga='Gabryal:BAABLgAECn8nAAIgAAkJSyAoBgDYAgAgAAkJSyAoBgDYAgAAAA==.Galthur:BAAALgAECgUJBgAAAA==.Garchomp:BAAALgAECgUJEwAAAA==.',
Ge='Gellina:BAAALgAECgUJBgAAAA==.Georg:BAACLgAFFH8bAAIOAAYJuRwPAwDIAQAOAAYJuRwPAwDIAQAuAAQKfzIAAg4ACQm7JjADAKMDAA4ACQm7JjADAKMDAAAA.Gerbankis:BAAALgAECgMJAwAAAA==.',
Gh='Ghoul:BAACLgAFFH8GAAIIAAIJICVKjwDNAAAIAAIJICVKjwDNAAAuAAQKfxoAAggACAmSI+gZAOECAAgACAmSI+gZAOECAAAA.Ghouligan:BAAALgAECgQJBAAAAA==.',
Gi='Giga:BAAALgADCgcJCwAAAA==.',
Gl='Glaiver:BAABLgAECn8dAAIkAAgJhg4HIABTAQAkAAgJhg4HIABTAQAAAA==.Glassjaw:BAAALgADCgUJBQAAAA==.',
Go='Goewin:BAAALgAFFAEJAQAAAA==.Gojo:BAAALgADCgYJDwAAAA==.Gorgrom:BAAALgADCgIJAgAAAA==.',
Gr='Gradiant:BAAALgAECgEJAgABLgAECgkJNgAKAKwXAA==.Greg:BAAALgAECgIJAgAAAA==.Gregorz:BAAALgAECgEJAQAAAA==.',
Gu='Gulgodeth:BAAALgAECgQJBQAAAA==.Gulgrimmar:BAACLgAFFH8dAAMLAAgJFyBmAwBpAgALAAcJ7CBmAwBpAgAKAAEJPQxKIABRAAAuAAQKfzcAAgsACQnnJqwAANkDAAsACQnnJqwAANkDAAAA.Guwudanielle:BAAALgAFFAIJAgABLgAFFAQJCgAFAFYZAA==.',
Ha='Hailsstorm:BAAALgADCgcJEgAAAA==.Hardfeelings:BAABLgAECn8cAAIOAAgJ+hmvOgAAAgAOAAgJ+hmvOgAAAgAAAA==.Harkness:BAAALgAECgYJDgAAAA==.Hassif:BAAALgAECgEJAQAAAA==.',
He='Heimerdoodle:BAAALgAECggJEwAAAA==.Hemlawk:BAAALgAECgEJAQAAAA==.Hemus:BAAALgAECgMJAwAAAA==.Hexed:BAABLgAECn8mAAIQAAgJ+QpHLwA1AQAQAAgJ+QpHLwA1AQAAAA==.',
Ho='Hochipo:BAAALgAECgEJAQAAAA==.',
Hu='Hughue:BAAALgADCgUJBQAAAA==.Hugs:BAAALgAECgYJCgAAAA==.Hurjek:BAAALgAFFAEJAQABLgAFFAQJDwAVAAEfAA==.',
Hy='Hyuna:BAAALgAECgEJAQABLgAECgcJDgADAAAAAA==.',
Ia='Iaso:BAABLgAECn8VAAIfAAYJgharKgBdAQAfAAYJgharKgBdAQAAAA==.',
Ic='Iconstar:BAAALgADCgMJAwAAAA==.',
Ig='Igneel:BAAALgADCgQJAQAAAA==.',
Ij='Ijustankedu:BAAALgAECgMJAwAAAA==.',
Ik='Ikiea:BAAALgAECgcJCAAAAA==.',
Il='Ilgrim:BAABLgAECn8YAAMPAAgJWxnhJgC9AQAPAAgJWxnhJgC9AQAOAAQJ+AO2LAFIAAABLgAFFAUJDgAbACkPAA==.Ilravenll:BAACLgAFFH8OAAIbAAUJKQ/ZGQAsAQAbAAUJKQ/ZGQAsAQAuAAQKfyEAAhsACQmQGOwJAHACABsACQmQGOwJAHACAAAA.Ilyana:BAACLgAFFH8ZAAIEAAcJnhlZEwAQAgAEAAcJnhlZEwAQAgAuAAQKf0EAAgQACQk2JjoDAGQDAAQACQk2JjoDAGQDAAAA.',
Im='Impavido:BAAALgAECgYJBgAAAA==.',
In='Inholy:BAAALgAECgYJEAAAAA==.Insights:BAAALgADCgMJAwAAAA==.',
Is='Isabella:BAAALgAECgEJAQABLgAFFAQJCgAFAFYZAA==.',
It='Ithopel:BAABLgAECn8mAAIHAAYJASF6KAASAgAHAAYJASF6KAASAgAAAA==.',
Ja='Jalista:BAAALgADCgMJAwAAAA==.Jayc:BAACLgAFFH8XAAIEAAUJCSBmOwBYAQAEAAUJCSBmOwBYAQAuAAQKfx0AAgQACAlgHid0AOoBAAQACAlgHid0AOoBAAAA.',
Je='Jereico:BAACLgAFFH8hAAIZAAgJmCLrAACQAgAZAAgJmCLrAACQAgAuAAQKfzsAAhkACQnmJkMAAIkDABkACQnmJkMAAIkDAAAA.Jeryhn:BAACLgAFFH8dAAIPAAgJnhJEAgDZAQAPAAgJnhJEAgDZAQAuAAQKf0EAAg8ACQk8GhYTAHoCAA8ACQk8GhYTAHoCAAAA.',
Jo='Joeburrow:BAAALgAECgQJBAAAAA==.Joeynodz:BAAALgADCgYJEgAAAA==.Jortshorts:BAABLgAECn8vAAIlAAkJ+AmuFgA5AQAlAAkJ+AmuFgA5AQAAAA==.',
Jr='Jray:BAABLgAECn8VAAIOAAYJGRnOZAC3AQAOAAYJGRnOZAC3AQAAAA==.',
Ju='Juggalo:BAACLgAFFH8LAAMNAAQJJx9oAQCBAQANAAQJJx9oAQCBAQAZAAEJkQb5WwA3AAAuAAQKfysAAw0ACQllIlUBAN8CAA0ACQllIlUBAN8CABkAAgmJErB5AEkAAAAA.June:BAACLgAFFH8eAAIVAAcJmhmxAQAaAgAVAAcJmhmxAQAaAgAuAAQKfz8AAxUACQlsIbMEAB0DABUACQlsIbMEAB0DACIACQkGHx4IALICAAAA.Juuju:BAAALgAECgYJDwAAAA==.',
Ka='Kaldriss:BAAALgAECgEJAgAAAA==.Kalen:BAAALgADCgEJAgAAAA==.Katashimus:BAAALgAECgYJDAAAAA==.Kawasuoo:BAABLgAECn8fAAMHAAgJMR3sHwA0AgAHAAcJzhzsHwA0AgAmAAYJAAxJNgCmAAAAAA==.Kaze:BAAALgAECgcJEQAAAA==.',
Kh='Khaotichic:BAABLgAECn8aAAIFAAYJFQ3FiwAOAQAFAAYJFQ3FiwAOAQAAAA==.Khrenak:BAAALgAECgQJCgAAAA==.',
Ki='Kickpunch:BAAALgAECgYJDgAAAA==.Kirah:BAACLgAFFH8HAAIZAAIJmBy1PwCnAAAZAAIJmBy1PwCnAAAuAAQKfyAAAhkACQmwIWoEAEoDABkACQmwIWoEAEoDAAEuAAUUBAkKAAUAVhkA.',
Kl='Kläus:BAAALgAECgEJAQAAAA==.',
Ko='Koddin:BAABLgAECn8zAAIOAAkJ6h4nIQBrAgAOAAkJ6h4nIQBrAgAAAA==.Korenchkin:BAAALgAECgEJAgAAAA==.Koreth:BAACLgAFFH8bAAMbAAYJLCHUCADDAQAbAAUJLCHUCADDAQASAAEJAACyBwA5AAAuAAQKf0cAAxsACQmAJlYBAFYDABsACQmAJlYBAFYDABIACAmWGg8EAHcCAAAA.Kornholyo:BAAALgAECgEJAQAAAA==.',
Kr='Kragoth:BAAALgADCgIJAgAAAA==.',
Ku='Kutuzov:BAABLgAECn8aAAIKAAUJABYWWAA3AQAKAAUJABYWWAA3AQAAAA==.',
Kw='Kwaiza:BAAALgAECgYJDwAAAA==.',
['Ká']='Káel:BAAALgAECgMJAwAAAA==.',
La='Lailaysia:BAABLgAECn8XAAIfAAkJFR/SBQAJAwAfAAkJFR/SBQAJAwAAAA==.Lamemoosaur:BAAALgADCgIJAgABLgAECgYJCgADAAAAAA==.Laríca:BAACLgAFFH8VAAIPAAUJdSSDBwAWAgAPAAUJdSSDBwAWAgAuAAQKfy8AAg8ACQlNJYMCAFIDAA8ACQlNJYMCAFIDAAAA.Laustin:BAABLgAECn8kAAQRAAkJXhu7CACFAgARAAkJVhu7CACFAgAnAAYJEhBqGADZAAAFAAIJbwV56gBXAAAAAA==.Laustinjung:BAAALgADCgIJAQAAAA==.Laydout:BAAALgAECggJDQABLgAECgkJIAAFAG8iAA==.Laydoutyota:BAABLgAECn8gAAIFAAkJbyKMDQDSAgAFAAkJbyKMDQDSAgAAAA==.',
Le='Leag:BAABLgAECn8YAAMTAAcJFw+MQACiAQATAAcJFw+MQACiAQAeAAEJJAmvPwA5AAAAAA==.Lemonruss:BAAALgADCgQJBAAAAA==.',
Li='Liaria:BAAALgAECgEJAQAAAA==.Lilea:BAACLgAFFH8JAAIFAAMJUhrvRwDzAAAFAAMJUhrvRwDzAAAuAAQKfzUAAwUACQnFH50RAK8CAAUACQnFH50RAK8CACcABwnrEfc0AJYBAAAA.Lithium:BAAALgADCgUJBQAAAA==.Littledeb:BAAALgAFFAEJAQAAAA==.',
Lo='Lockdots:BAAALgADCgIJAgAAAA==.Lolchaosbolt:BAAALgADCgYJBgAAAA==.Lortherian:BAAALgAECggJEgAAAA==.Lowbo:BAAALgADCgUJBQAAAA==.Lowelfesteem:BAAALgADCgUJBQAAAA==.',
Lu='Lucey:BAAALgAECgEJAgAAAA==.Lucille:BAABLgAECn8aAAIEAAYJ3geD1ADLAAAEAAYJ3geD1ADLAAAAAA==.',
Ly='Lyndira:BAAALgAECgUJBQAAAA==.',
['Lä']='Läwlbringer:BAAALgAECggJDQAAAA==.',
['Lî']='Lîghtt:BAAALgADCgQJBAAAAA==.',
Ma='Mabritos:BAAALgAECgQJBQABLgAFFAYJGgAnAJ8eAA==.Maccabee:BAAALgAECgEJAQAAAA==.Malison:BAAALgAECgIJAgAAAA==.Mania:BAAALgADCgYJBgABLgAECgkJIwATAL8dAA==.Mathath:BAACLgAFFH8NAAIIAAQJ5QubZQAUAQAIAAQJ5QubZQAUAQAuAAQKfxwAAwgACAn4F4BOAMQBAAgACAnIF4BOAMQBAAkABAlUFacoAPkAAAAA.Mathmath:BAAALgAECgUJCgABLgAFFAEJAQADAAAAAA==.Mathoras:BAABLgAECn8aAAIBAAkJKBZTMAALAgABAAkJKBZTMAALAgAAAA==.Mazraq:BAAALgAECgEJAgABLgAECgkJNgAKAKwXAA==.',
Me='Meandean:BAAALgAECgIJBgAAAA==.Meatier:BAAALgAECgcJCAABLgAECgkJIwATAL8dAA==.Meatless:BAAALgADCgcJDQAAAA==.',
Mi='Micmac:BAAALgAECgQJCQAAAA==.Milo:BAAALgAECgQJBgAAAA==.Miltonroe:BAABLgAECn8iAAIGAAgJ6Q5LEwBhAQAGAAgJ6Q5LEwBhAQAAAA==.Mirithul:BAAALgADCgYJBwAAAA==.Mischiëf:BAAALgAECgcJEAAAAA==.Mitsuri:BAABLgAECn8iAAIEAAgJoQrekgCtAQAEAAgJoQrekgCtAQAAAA==.',
Mo='Modr:BAAALgAECgkJEgAAAA==.Moiraine:BAAALgAECgEJAQAAAA==.Money:BAAALgADCgUJBQAAAA==.Monkynate:BAAALgAECgYJCgAAAA==.Monsterskill:BAABLgAECn8iAAQUAAgJzhgeEAAsAQAUAAYJuRYeEAAsAQABAAUJdBkHjwATAQACAAUJhxNULQAIAQAAAA==.Moonerva:BAABLgAECn8fAAIoAAgJgAzyLwBDAQAoAAgJgAzyLwBDAQAAAA==.Morpheos:BAAALgADCgQJBAAAAA==.Mortgage:BAAALgADCgUJBQAAAA==.',
Mu='Mutsu:BAAALgADCgcJBwAAAA==.',
Mv='Mvqchx:BAAALgAECgUJCQAAAA==.',
['Mì']='Mìssy:BAAALgAECgEJAQAAAA==.',
Na='Naturelass:BAAALgADCgUJBQAAAA==.Nausicaa:BAAALgAECgEJAQAAAA==.Nawwll:BAAALgADCgMJAwAAAA==.',
Ne='Neotama:BAAALgAECggJEgAAAA==.Nethis:BAABLgAECn8nAAIgAAgJmRz4EwATAgAgAAgJmRz4EwATAgAAAA==.',
Ni='Niatpacgrom:BAACLgAFFH8IAAIGAAQJ0g2qBwAmAQAGAAQJ0g2qBwAmAQAuAAQKfyIAAgYACQlsGYcGAFUCAAYACQlsGYcGAFUCAAAA.Nivla:BAAALgADCgMJAwAAAA==.',
No='Nobacon:BAAALgAECgUJCgAAAA==.Nokix:BAAALgADCgkJDgAAAA==.Norah:BAAALgAECgEJAQAAAA==.Norvis:BAAALgAECgQJBQAAAA==.Notdragon:BAAALgAECgQJEgAAAA==.',
Nu='Nukeddukem:BAAALgAECgYJEgAAAA==.',
Nv='Nv:BAAALgAECggJEwAAAA==.',
Ny='Nymrod:BAABLgAECn8sAAMBAAkJSBQFNAD8AQABAAkJSBQFNAD8AQACAAIJpgduZQBEAAAAAA==.',
['Ní']='Nír:BAAALgAECgQJBAAAAA==.',
Ob='Oben:BAAALgAECggJAQAAAA==.',
Oj='Ojou:BAAALgADCgMJAwABLgAFFAMJAwADAAAAAA==.',
Om='Omizzig:BAAALgAECgUJCwAAAA==.',
On='Onepunch:BAAALgAECgQJBgAAAA==.',
Or='Orcman:BAAALgADCgIJAgABLgADCgcJBwADAAAAAA==.Orloran:BAAALgADCgIJAgAAAA==.',
Pa='Palthur:BAAALgAECgYJDQAAAA==.Parria:BAABLgAECn8UAAIBAAcJ8RG/awBZAQABAAcJ8RG/awBZAQABLgAECgkJFwAfABUfAA==.Pasqualino:BAAALgAECgYJCgAAAA==.Passionate:BAACLgAFFH8MAAIjAAQJwAzsFwD5AAAjAAQJwAzsFwD5AAAuAAQKfyYAAiMACAmfFFYVAPUBACMACAmfFFYVAPUBAAAA.',
Pe='Peepis:BAAALgADCgEJAQABLgAECgkJIwATAL8dAA==.Pennance:BAABLgAECn8iAAIPAAkJ/RuZDgCiAgAPAAkJ/RuZDgCiAgAAAA==.',
Ph='Phatmidas:BAABLgAECn8vAAIOAAkJyBmKMAAlAgAOAAkJyBmKMAAlAgAAAA==.Philth:BAAALgAECgUJBQAAAA==.',
Pi='Pistfist:BAAALgAECgcJAQAAAA==.',
Pl='Plagueground:BAACLgAFFH8XAAIIAAYJYCAiCABcAgAIAAYJYCAiCABcAgAuAAQKf0QAAggACQnhJqoBAH4DAAgACQnhJqoBAH4DAAAA.Plutonyus:BAAALgAECgEJAQAAAA==.',
Po='Poc:BAABLgAECn8ZAAIEAAYJPB3wdADoAQAEAAYJPB3wdADoAQAAAA==.Pockets:BAAALgAECgMJBwAAAA==.Potatopotato:BAACLgAFFH8LAAIbAAMJ2xLSIADyAAAbAAMJ2xLSIADyAAAuAAQKfyIAAhsACQk0FSUcAB4CABsACQk0FSUcAB4CAAAA.Pounces:BAAALgAECgYJEgABLgAECgcJGAAZAKgXAA==.Powerfistin:BAAALgADCgcJBwAAAA==.',
Pr='Prosecutor:BAAALgAECgUJDAAAAA==.Prynts:BAABLgAECn8VAAIOAAcJZh3sRAAVAgAOAAcJZh3sRAAVAgAAAA==.Prøzak:BAACLgAFFH8GAAIQAAMJxwPIOgCiAAAQAAMJxwPIOgCiAAAuAAQKfxUAAhAACAl5C2swAC8BABAACAl5C2swAC8BAAAA.',
Pu='Puetrid:BAAALgADCgYJBgABLgAECgQJBAADAAAAAA==.',
Ra='Raanky:BAAALgAECgEJAQAAAA==.Radiantlight:BAAALgAECggJEAAAAA==.Randomly:BAAALgAECgQJBAAAAA==.Raspberries:BAAALgAECgcJBwAAAA==.Rautha:BAAALgAECgkJEgAAAA==.Rayl:BAABLgAECn8UAAIIAAYJGBdnegBZAQAIAAYJGBdnegBZAQAAAA==.Razsputin:BAAALgAECgMJBwAAAA==.',
Re='Rekless:BAAALgADCgUJBQAAAA==.Rethgar:BAAALgAECgUJEgAAAA==.',
Rh='Rhaegosa:BAABLgAECn8zAAQZAAkJDxlTJACfAQAZAAcJ0xlTJACfAQAjAAQJjBbPGQAmAQANAAQJrg3JFQChAAAAAA==.Rhavik:BAAALgAECgQJBgAAAA==.Rhekt:BAAALgAECgIJBQAAAA==.Rhok:BAAALgAECgEJAQAAAA==.Rhokladar:BAAALgAECgUJCwAAAA==.',
Ri='Ridcully:BAABLgAECn8bAAIHAAgJlxc5NgCtAQAHAAgJlxc5NgCtAQAAAA==.Rimath:BAAALgAECgcJBAAAAA==.Rinswind:BAAALgADCgMJAwAAAA==.',
Ro='Robopacman:BAACLgAFFH8VAAQYAAUJECHZBgBSAQAYAAQJdRjZBgBSAQAIAAQJvyD3PwBRAQAJAAEJAADxOwAAAAAuAAQKfzoABAgACQkEJRgPACMDAAgACQnyJBgPACMDAAkACAlDIkIGAKwCABgAAgnhGPYfAJkAAAAA.Rodstewart:BAACLgAFFH8ZAAMFAAgJShgaDAC4AQAFAAUJSxwaDAC4AQAnAAUJUgzvFAD2AAAuAAQKfycAAwUACQmwJE0WAIYCAAUACAmPJE0WAIYCACcABwnbHxomAPgBAAAA.Roofeo:BAABLgAECn8gAAQCAAgJJBXoDABTAQACAAYJmBboDABTAQAUAAQJIhX9FAD+AAABAAQJcgzWuADKAAABLgAECgkJIwAJAIEUAA==.Rotdaddy:BAABLgAECn8nAAIIAAgJ7gQ/nwAYAQAIAAgJ7gQ/nwAYAQAAAA==.',
Ry='Ryoshin:BAAALgADCgEJAQABLgAECgYJDQADAAAAAA==.Ryzel:BAAALgADCgUJBQAAAA==.',
['Rï']='Rïn:BAAALgADCgEJAQAAAA==.',
Sa='Sabatikus:BAAALgAECgIJAgAAAA==.Salas:BAABLgAECn8UAAIBAAcJzgx0hgAiAQABAAcJzgx0hgAiAQAAAA==.Salino:BAAALgAECgYJCgAAAA==.Salinoster:BAAALgAECgEJAQAAAA==.Salordell:BAAALgADCgIJAwAAAA==.Sam:BAAALgADCgEJAQAAAA==.Sanque:BAAALgAECgMJAwAAAA==.Sarate:BAABLgAECn8rAAIgAAgJ3A52KQBlAQAgAAgJ3A52KQBlAQAAAA==.Savannah:BAABLgAFFH8KAAIFAAQJVhl2KwA/AQAFAAQJVhl2KwA/AQAAAA==.Savvtwo:BAAALgADCgcJBwABLgAFFAgJHQAMAPEiAQ==.',
Sc='Scathach:BAABLgAECn8gAAMMAAcJ4x4OOQDMAQAMAAcJ4x4OOQDMAQAkAAQJURguRADmAAABLgAFFAEJAQADAAAAAA==.Scoop:BAAALgADCgYJBgAAAA==.Scorandom:BAAALgAECgEJAQAAAA==.',
Se='Seetani:BAAALgADCgUJBgABLgAECgQJBgADAAAAAA==.Seven:BAAALgAECgcJCgAAAA==.Sezra:BAAALgADCgkJAQAAAA==.',
Sh='Shamalam:BAAALgADCgEJAQAAAA==.Shei:BAAALgAECgIJAgAAAA==.Sheidon:BAAALgAECgQJBAAAAA==.Shinanigans:BAAALgAECgYJDwAAAA==.Shruikan:BAAALgADCggJDAAAAA==.',
Si='Silverslam:BAAALgAECgEJAQABLgAECggJGAAGAEESAA==.Sinatra:BAAALgAECgIJBAABLgAECgcJEQADAAAAAA==.Siqodel:BAAALgADCgYJCAAAAA==.',
Sk='Skurge:BAAALgAECggJEgAAAA==.',
Sl='Slamb:BAAALgAECgYJBwAAAA==.Slimetongue:BAAALgADCgMJAwAAAA==.',
Sm='Smaaug:BAAALgAFFAMJAwAAAA==.',
Sn='Snuggle:BAAALgAECgEJAQAAAA==.',
So='Solstis:BAAALgAECggJDgAAAA==.Sorzsnipe:BAAALgADCgQJBAAAAA==.',
Sp='Spellchücker:BAAALgAECgcJDQAAAA==.Spfzero:BAAALgAECgEJAQAAAA==.',
St='Staggered:BAACLgAFFH8PAAIQAAQJoh6jFgBLAQAQAAQJoh6jFgBLAQAuAAQKfyUAAxAACAkOIusLAM8CABAACAkOIusLAM8CACIAAQk1A9WMABwAAAAA.Stiffbutt:BAAALgAECgEJAQAAAA==.Stonebeard:BAAALgADCgcJBwAAAA==.Stoneojinray:BAAALgADCgEJAQAAAA==.Stoneorcman:BAAALgADCgcJBwAAAA==.Stormriderr:BAAALgAECgYJCQAAAA==.',
Su='Subdofu:BAAALgADCgQJBAABLgAECgcJFwAbAN0cAA==.Subtox:BAABLgAECn8XAAMbAAcJ3RxNIQDvAQAbAAcJ3RxNIQDvAQASAAEJkgu5HwA0AAAAAA==.',
Sw='Sweetcool:BAAALgAECgUJCQABLgAECggJLgAFAP4jAA==.Sweetzeke:BAAALgAECgEJAQAAAA==.',
Sy='Syphilistjt:BAABLgAECn8WAAIhAAgJ0xLIFwDgAQAhAAgJ0xLIFwDgAQAAAA==.Syphillis:BAAALgAECgYJCgAAAA==.',
['Sá']='Sálud:BAACLgAFFH8MAAIoAAUJix+0EwBQAQAoAAUJix+0EwBQAQAuAAQKfyoAAygACAmXI9wHAMQCACgACAmXI9wHAMQCACYABwmhGXgSAKYBAAAA.',
['Sê']='Sêp:BAAALgAECggJDgAAAA==.',
Ta='Takoda:BAAALgAECgEJAQAAAA==.Talivath:BAAALgAECgMJBQAAAA==.Tanissaria:BAAALgADCgIJAgAAAA==.Taranith:BAAALgAECgUJBQABLgAECggJGQAEAPoTAA==.Tarhealeon:BAABLgAECn9uAAMOAAkJ+xXxMwAYAgAOAAkJ+xXxMwAYAgAPAAkJyRuWIQARAgAAAA==.Tarmander:BAAALgAECgYJDgAAAA==.Taylörshift:BAAALgAECgQJBwAAAA==.',
Te='Telahnicus:BAAALgAECgEJAQAAAA==.Terranox:BAAALgADCgMJAwAAAA==.Testostauren:BAAALgAECgQJCAAAAA==.',
Th='Thabigone:BAAALgAECgYJDAAAAA==.Thalnaria:BAAALgAECgYJCwAAAA==.Threebuttons:BAAALgAECgUJDgABLgAFFAQJEwAjANENAA==.Thunderkis:BAAALgAECgYJEwAAAA==.',
Ti='Tiewaz:BAAALgAECgYJBgABLgAECggJHwAEAFoPAA==.Tiewiz:BAABLgAECn8fAAMEAAgJWg+KhwBNAQAEAAgJEQyKhwBNAQApAAUJlw2vCwCjAAAAAA==.',
To='Tointjoker:BAAALgAECgUJBgAAAA==.Tolun:BAABLgAECn8/AAIEAAkJqhwSGwCiAgAEAAkJqhwSGwCiAgAAAA==.Tosan:BAAALgADCggJDgAAAA==.',
Tr='Treeplague:BAABLgAECn9DAAMgAAkJmxLeFwDtAQAgAAkJmxLeFwDtAQAhAAcJ8RUUGgDeAQAAAA==.Trypleg:BAAALgAECgMJAwAAAA==.',
Tu='Tungie:BAABLgAECn8bAAIIAAgJ0iDdOgABAgAIAAgJ0iDdOgABAgAAAA==.Turn:BAACLgAFFH8kAAQBAAgJoxVyCAChAQABAAYJnhpyCAChAQACAAUJwg2+AwBcAQAUAAIJmSCiFABZAAAuAAQKf0QABAEACQn9Jb8UANkCAAEACAklJb8UANkCABQAAwlJJswYANcAAAIAAwlXJGcYAMoAAAAA.Turtleduck:BAABLgAECn8fAAINAAgJ/BhVBQD5AQANAAgJ/BhVBQD5AQAAAA==.Tuskbreaker:BAAALgAECgIJAgAAAA==.',
Tw='Twittytister:BAAALgADCgQJBAAAAA==.Twostrokes:BAAALgAECgEJAQAAAA==.',
Ty='Tyrese:BAAALgADCggJEAAAAA==.',
Uf='Uffin:BAAALgAECgQJBQAAAA==.',
Um='Umbryx:BAAALgAECgYJDQAAAA==.',
Un='Unagi:BAABLgAECn8aAAIGAAgJPRR/CwDfAQAGAAgJPRR/CwDfAQAAAA==.Unholy:BAAALgADCgIJAgAAAA==.',
Va='Valdi:BAABLgAECn8ZAAIOAAcJkwwQrgAGAQAOAAcJkwwQrgAGAQAAAA==.',
Ve='Velthera:BAABLgAECn8XAAIjAAgJCyJEBAAQAwAjAAgJCyJEBAAQAwABLgAFFAQJDwAVAAEfAA==.Venomlight:BAAALgADCgIJAgAAAA==.Venomstrikes:BAAALgAECgcJEwAAAA==.Venratzi:BAAALgAECgQJBAAAAA==.Vespertina:BAAALgAECgIJAgAAAA==.',
Vi='Viscerion:BAAALgAECgUJBQAAAA==.',
Vo='Voridor:BAAALgADCgEJAQAAAA==.Voulk:BAAALgAFFAMJAwABLgAFFAgJIAAjAAwbAA==.',
Vy='Vyllan:BAABLgAECn8bAAQUAAgJAQYCEwD8AAABAAgJmgUPjQAWAQAUAAYJKwQCEwD8AAACAAMJmgHWOwAqAAAAAA==.',
Wa='Waldgeist:BAAALgAECgUJBQABLgAECgkJIwATAL8dAA==.Walthur:BAAALgADCgkJDQAAAA==.Waobby:BAAALgADCgIJAgAAAA==.Warrpigg:BAAALgAECgEJAQAAAA==.Waterdrinker:BAAALgAECgQJBgAAAA==.Wavybone:BAAALgAECgEJAgAAAA==.',
Wh='Whickedthur:BAAALgAECgYJBgAAAA==.Whiisper:BAAALgADCgMJAwAAAA==.Whoarlock:BAAALgADCgUJCAAAAA==.',
Wo='Wo:BAAALgAECgcJBwAAAA==.',
Wu='Wutangstyle:BAAALgAECgIJAgABLgAECgkJIwATAL8dAA==.',
Wy='Wyatta:BAAALgADCgIJAgAAAA==.',
Xe='Xelinia:BAACLgAFFH8QAAIgAAUJoxLDGAANAQAgAAUJoxLDGAANAQAuAAQKfyEAAiAACQk5H20MALwCACAACQk5H20MALwCAAAA.Xen:BAABLgAFFH8HAAIlAAQJhhaFBABQAQAlAAQJhhaFBABQAQAAAA==.',
Xf='Xfortune:BAAALgADCgcJCQAAAA==.',
Xh='Xholycritz:BAAALgAECgMJBAAAAA==.',
Xu='Xuefeng:BAACLgAFFH8VAAIiAAUJSBrKDABEAQAiAAUJSBrKDABEAQAuAAQKfzcAAiIACQl7IFYGANUCACIACQl7IFYGANUCAAAA.',
Ye='Yenchmeister:BAACLgAFFH8cAAMTAAcJkxxEAwDDAQATAAUJuRxEAwDDAQAeAAYJ3RoAAgBiAQAuAAQKfygAAxMACQkgJdcJABEDABMACQkgJdcJABEDAB4AAgl3ICEoAK4AAAAA.',
Yo='Youngbusta:BAABLgAECn8zAAIEAAkJ9iLKEQDcAgAEAAkJ9iLKEQDcAgAAAA==.',
Yu='Yuta:BAAALgAECgYJDQAAAA==.',
Za='Zad:BAAALgADCgIJAgAAAA==.',
Ze='Zenrac:BAAALgADCgUJBQAAAA==.Zeromus:BAAALgAECgIJAgAAAA==.',
Zi='Zilvanic:BAACLgAFFH8OAAIXAAQJxwgOCgC8AAAXAAQJxwgOCgC8AAAuAAQKfyQABBcACAlgEioUAHABABcACAn0ESoUAHABAA4ABQlZELfXAMoAAA8AAwl8AQiDAGwAAAAA.Zilvanion:BAAALgAFFAIJAgAAAA==.',
Zo='Zourknight:BAAALgADCgcJEAAAAA==.Zourlight:BAAALgAECgEJAQAAAA==.Zourlock:BAABLgAECn8XAAQBAAYJdRAVjgAVAQABAAYJAQ8VjgAVAQAUAAIJJhL8IgB8AAACAAEJAAAlbwA3AAAAAA==.Zourpatch:BAAALgADCgMJAwAAAA==.',
Zu='Zulvaz:BAAALgAECgIJAwAAAA==.Zurey:BAABLgAECn88AAIMAAkJVg2xUgB2AQAMAAkJVg2xUgB2AQAAAA==.',
Zy='Zynjamin:BAACLgAFFH8gAAMNAAgJ0iE9AAADAgAZAAcJFCHJBQBqAgANAAYJ6yM9AAADAgAuAAQKfy4AAg0ACQkLJC8AANsDAA0ACQkLJC8AANsDAAAA.',
['Éc']='Écho:BAAALgAECgEJAQAAAA==.',
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
