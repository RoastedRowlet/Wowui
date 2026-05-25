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

local lookup = {'Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Shaman-Enhancement','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','Evoker-Devastation','Paladin-Retribution','Paladin-Holy','Monk-Brewmaster','Hunter-Survival','Rogue-Assassination','Warrior-Fury','Warlock-Affliction','Monk-Mistweaver','Mage-Fire','Paladin-Protection','DeathKnight-Frost','Evoker-Augmentation','Rogue-Outlaw','Rogue-Subtlety','DemonHunter-Vengeance','Warrior-Protection','Warrior-Arms','Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Windwalker','Evoker-Preservation','DemonHunter-Havoc','Druid-Feral','Druid-Guardian','Hunter-Marksmanship','Druid-Balance','Mage-Arcane',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aannte:BAACLgAFFH8ZAAMBAAgJyhgABgDAAQABAAYJCRcABgDAAQACAAQJ8he6BQALAQAuAAQKfyIAAwEACQlVIowmAHgCAAEACQlGIowmAHgCAAIABAnwHvcdAGABAAAA.Aardbark:BAAALgADCgEJAQAAAA==.',
Ab='Abúsedyoû:BAAALgADCgMJAwAAAA==.',
Ac='Achtland:BAAALgAECgUJBgABLgAECgcJIAADAOMeAA==.',
Ad='Adekai:BAAALgAECgYJDgAAAA==.Adv:BAAALgAECgEJAQAAAA==.',
Ae='Aerestrix:BAAALgAECgYJBwAAAA==.',
Ai='Airvis:BAABLgAECn8jAAIEAAYJKwrjtwD5AAAEAAYJKwrjtwD5AAAAAA==.',
Al='Alacia:BAAALgAECggJDQABLgAFFAMJCQAFAFIaAA==.Alatarr:BAAALgAECgcJEQAAAA==.Albinomonk:BAAALgADCgcJBwAAAA==.',
An='Anankei:BAAALgAECgMJAwAAAA==.Annastrophic:BAAALgADCgMJAwAAAA==.Anrí:BAAALgAECgEJAQAAAA==.Antaria:BAAALgADCgcJFgAAAA==.Ante:BAAALgADCgUJAQAAAA==.Antiform:BAAALgAECgIJBgAAAA==.Antpony:BAAALgAECgIJAgABLgAECgYJCgAGAAAAAA==.',
Ar='Arcish:BAAALgAECgEJAgAAAA==.Arjun:BAABLgAECn8YAAIHAAgJQRKaDQCfAQAHAAgJQRKaDQCfAQAAAA==.Arkirla:BAAALgAECgEJAgAAAA==.Arkiyra:BAAALgAECggJDQAAAA==.Arklira:BAAALgAECgEJAQAAAA==.Arkosh:BAAALgAECgEJAgAAAA==.Arkyra:BAAALgAECgUJBwAAAA==.Arovix:BAABLgAECn8ZAAIIAAgJVBo4JgD7AQAIAAgJVBo4JgD7AQAAAA==.',
As='Ashwey:BAAALgADCgkJCAAAAA==.',
At='Atom:BAABLgAECn8VAAIFAAgJBRQzPQDAAQAFAAgJBRQzPQDAAQAAAA==.',
Au='Aubreey:BAAALgADCgcJCQAAAA==.Aureille:BAAALgAECgYJCgAAAA==.',
Aw='Awoozehl:BAACLgAFFH8fAAMJAAcJLiBrEQDbAQAJAAYJLiBrEQDbAQAKAAEJAAB/NwAAAAAuAAQKfz0AAgkACQnWJi4BAIIDAAkACQnWJi4BAIIDAAAA.',
Az='Azanoth:BAAALgAECgYJCAABLgAECggJHQACAKkUAA==.Azgrodon:BAABLgAECn8vAAMLAAkJJxecGABYAgALAAkJJxecGABYAgAMAAMJjww+bACSAAAAAA==.Azor:BAABLgAECn8YAAIDAAgJch08HQCiAgADAAgJch08HQCiAgAAAA==.',
Ba='Baja:BAAALgAECgQJBAAAAA==.Baldomar:BAAALgADCgUJCAAAAA==.Bangmonk:BAAALgAFFAQJBAABLgAFFAgJIAANACAgAA==.Bangungot:BAAALgADCgMJAwABLgAFFAgJIAANACAgAA==.Barristan:BAAALgAECgUJBQAAAA==.Barzalie:BAAALgAECgYJDAABLgAFFAMJAwAGAAAAAA==.Bathrezz:BAABLgAECn8gAAMOAAkJoxcKPQDwAQAOAAkJoxcKPQDwAQAPAAMJWA9gXACTAAAAAA==.',
Be='Beerbelly:BAAALgAFFAMJAwAAAA==.Beleaves:BAACLgAFFH8gAAIQAAgJYQeQBgBqAQAQAAgJYQeQBgBqAQAuAAQKf0EAAhAACQlbHTYIAJMCABAACQlbHTYIAJMCAAAA.Beorl:BAAALgADCgYJCAAAAA==.',
Bh='Bhackshots:BAABLgAECn8XAAIRAAUJjSF+JgBIAQARAAUJjSF+JgBIAQABLgAECggJNAASAGQkAA==.',
Bi='Bifurious:BAABLgAECn8jAAITAAkJvx3BCgCXAgATAAkJvx3BCgCXAgAAAA==.Bigrob:BAAALgAECgEJBAAAAA==.',
Bl='Blowmybubble:BAAALgAECgEJAQABLgAECgkJIAAFAKchAA==.Bluereindeer:BAABLgAECn8VAAIJAAkJAgs5VQChAQAJAAkJAgs5VQChAQAAAA==.',
Bo='Bobsstones:BAACLgAFFH8WAAQBAAgJiR7QAwDkAQABAAcJNB3QAwDkAQACAAQJ6x0sBgANAQAUAAEJoCVkEABYAAAuAAQKfykABAIACQlCJT0GAGwCAAEABwmkJP4bAK0CAAIABgmDJD0GAGwCABQAAwm6JOgVANUAAAAA.Bonekitty:BAAALgAECgYJBgAAAA==.Bonkulo:BAABLgAECn8XAAMKAAgJqxLvGQBeAQAKAAcJLRXvGQBeAQAJAAEJoQP+TQEmAAABLgAECggJHQACAKkUAA==.Boofassist:BAABLgAECn8dAAIPAAkJ7CKABAAmAwAPAAkJ7CKABAAmAwABLgAFFAYJFwAVAAMZAA==.Boogey:BAABLgAECn8fAAMEAAgJfQ35awCGAQAEAAgJfQ35awCGAQAWAAEJpQiNEAAyAAAAAA==.Boompowwow:BAABLgAECn8VAAIMAAYJIxnmNACDAQAMAAYJIxnmNACDAQAAAA==.Boomsonic:BAAALgADCgUJBQABLgAECgkJIwATAL8dAA==.Bophadeez:BAABLgAECn8lAAQPAAgJeB4bHwAgAgAPAAcJGSEbHwAgAgAXAAgJhBZDDgCxAQAOAAYJvQ/MjABhAQAAAA==.',
Br='Broccoliz:BAECLgAFFH8gAAIIAAgJlQ/0AgC9AQAIAAgJlQ/0AgC9AQAuAAQKf0IAAggACQkUH9MYAHECAAgACQkUH9MYAHECAAAA.Brokan:BAAALgAECgcJBwAAAA==.Brokgar:BAAALgAECggJEAAAAA==.Brotu:BAAALgADCgIJAQAAAA==.Bruceleroy:BAAALgADCgEJAQAAAA==.Brutalsmasch:BAAALgADCgUJBQAAAA==.',
Bu='Bubu:BAAALgAECgEJAQAAAA==.Bulis:BAAALgAECgEJAQAAAA==.Bullblaster:BAAALgAECgMJBQAAAA==.',
Bw='Bwonshamdi:BAAALgAECgcJBwABLgAECgcJBwAGAAAAAA==.',
['Bõ']='Bõb:BAAALgAECgQJCQAAAA==.',
Ca='Cafca:BAABLgAECn83AAICAAkJRBgNAwBIAgACAAkJRBgNAwBIAgAAAA==.Cahma:BAAALgADCgYJEAAAAA==.Caitlin:BAAALgAECgEJAQABLgAFFAQJCgAFAFYZAA==.Callyour:BAAALgADCgIJAgAAAA==.Cask:BAAALgADCgYJAQAAAA==.',
Ch='Chainsawloli:BAAALgADCgUJBQAAAA==.Changying:BAAALgAECggJCwAAAA==.Cheekung:BAAALgAECgcJEgAAAA==.Choedankal:BAAALgADCgcJBwAAAA==.Chophouse:BAAALgAECgkJBgAAAA==.',
Cl='Clearlyumad:BAACLgAFFH8NAAQJAAUJhxBvbADxAAAJAAQJhxBvbADxAAAYAAEJkAObGgA+AAAKAAEJAACuRgAAAAAuAAQKfxsAAgkACAmPHlE8AEYCAAkACAmPHlE8AEYCAAAA.Clèrick:BAABLgAECn8wAAIPAAgJzSPBBwDrAgAPAAgJzSPBBwDrAgAAAA==.',
Co='Coldcrow:BAAALgAECgEJAQAAAA==.Combination:BAABLgAFFH8LAAIVAAQJhx4CFABqAQAVAAQJhx4CFABqAQAAAA==.Confessor:BAAALgAECgEJAQAAAA==.Corruptions:BAAALgADCgEJAQAAAA==.',
Cr='Crux:BAAALgADCgQJBAAAAA==.',
Cy='Cyfrin:BAAALgADCgEJAQAAAA==.Cyânide:BAAALgADCgYJDQAAAA==.',
['Cõ']='Cõurage:BAAALgAECgYJCAAAAA==.',
Da='Dabbhammer:BAAALgAFFAEJAQAAAA==.Dabbzyvoker:BAABLgAECn8gAAMZAAgJgQyYLwBSAQAZAAgJQwyYLwBSAQANAAYJowZ/IgAWAQABLgAFFAEJAQAGAAAAAA==.Dallzbeep:BAAALgAECgkJCQABLgAFFAQJDAAVAH8gAA==.Danathoor:BAAALgADCggJCAAAAA==.Danathor:BAAALgADCgcJBwAAAA==.Dangbro:BAAALgAECgYJDQAAAA==.Dankspank:BAAALgAECgQJCAAAAA==.Danteus:BAAALgADCgMJAwABLgAECgUJDwAGAAAAAA==.Darkrigh:BAAALgADCggJDgAAAA==.Darkwave:BAABLgAECn8rAAIBAAgJqBeNNgDmAQABAAgJqBeNNgDmAQAAAA==.Darthdiddyus:BAACLgAFFH8lAAMaAAcJKx5RAAA7AgAaAAcJKx5RAAA7AgAbAAMJtxSnDQAQAQAuAAQKfzIABBoACQmeJHAAADUDABoACQmaJHAAADUDABsABwlRITwUAHICABIABAnJId0KAIIBAAAA.Datdruidguy:BAAALgADCgUJBQABLgAECgYJBgAGAAAAAA==.Datlock:BAAALgADCgEJAQABLgAECgYJBgAGAAAAAA==.Datshammy:BAAALgAECgYJBgAAAA==.Daviculas:BAAALgADCggJDgAAAA==.Dawghawg:BAAALgAECgQJBAAAAA==.Dawnnie:BAACLgAFFH8IAAIXAAMJBA+YCQCrAAAXAAMJBA+YCQCrAAAuAAQKfzYAAhcACAneGCMMANYBABcACAneGCMMANYBAAAA.Dawnte:BAABLgAECn8dAAIOAAcJHBxVTQDBAQAOAAcJHBxVTQDBAQABLgAECgUJDwAGAAAAAA==.Dawsonrogers:BAAALgAFFAIJAgAAAA==.Dayvastate:BAABLgAECn80AAMJAAkJqhs8HAB7AgAJAAkJqhs8HAB7AgAYAAEJDxJnKQA3AAAAAA==.Dazshir:BAAALgADCgMJAwAAAA==.',
De='Deathbanana:BAABLgAFFH8JAAIJAAMJHR/6aAD4AAAJAAMJHR/6aAD4AAABLgAFFAgJGAAEAAYaAA==.Deaththreat:BAAALgAECgQJBAABLgAECggJHAAOAPoZAA==.Delema:BAACLgAFFH8RAAIOAAUJph8xCwBTAQAOAAUJph8xCwBTAQAuAAQKfyAAAg4ACAlaIUQiAKACAA4ACAlaIUQiAKACAAAA.Democrit:BAAALgAECgUJBwAAAA==.Demonjuice:BAAALgAECgUJCAAAAA==.Derpyblinker:BAABLgAECn8VAAIEAAYJQRDu0wBHAQAEAAYJQRDu0wBHAQAAAA==.Destructer:BAABLgAECn8gAAICAAgJjBCUCgBrAQACAAgJjBCUCgBrAQAAAA==.Dethstar:BAAALgADCgUJBQABLgAECggJKwABAKgXAA==.Devoured:BAAALgADCgMJAwAAAA==.',
Di='Dinger:BAAALgAECgEJAQAAAA==.Dirtydinker:BAAALgAECgYJDQAAAA==.Disconneted:BAAALgADCgYJBgAAAA==.Dishwasher:BAAALgADCgIJAgAAAA==.Dixsard:BAABLgAECn80AAMSAAgJZCTYAQC1AgASAAgJLCTYAQC1AgAbAAcJTx1tIwDeAQAAAA==.',
Do='Dobrova:BAAALgAECgEJAQAAAA==.Doezenn:BAAALgADCgUJBQAAAA==.Dogofwar:BAAALgAECgEJAQAAAA==.Dottprepared:BAACLgAFFH8cAAIcAAYJeRGyAABRAQAcAAYJeRGyAABRAQAuAAQKf0EAAhwACQmaIpcBAAcDABwACQmaIpcBAAcDAAAA.Dottyfu:BAABLgAFFH8FAAIQAAMJKwlHMwC4AAAQAAMJKwlHMwC4AAAAAA==.Doubted:BAAALgAECgQJBAAAAA==.',
Dr='Dracoiconic:BAAALgAECgEJAgAAAA==.Dragonboffa:BAAALgAECgcJAQAAAA==.Draul:BAAALgAECgEJAQABLgAECgkJLwALACcXAA==.Drexl:BAACLgAFFH8PAAIdAAUJghG6BQARAQAdAAUJghG6BQARAQAuAAQKfzgABB4ACQkjHi4FAJYCAB4ACQnlHS4FAJYCABMABwkSBtplABwBAB0AAgmHDHo7AHAAAAAA.Dril:BAABLgAECn8cAAMDAAgJnhgPMQDiAQADAAgJihgPMQDiAQAcAAIJAhZvIACBAAAAAA==.Drognin:BAAALgADCgEJAQAAAA==.Drunkfu:BAAALgADCgQJBAAAAA==.',
Du='Dubstep:BAAALgAECgkJAgAAAA==.Dudette:BAAALgAECgcJDAAAAA==.Dunlop:BAABLgAECn8dAAMfAAkJqBisCgCVAgAfAAkJqBisCgCVAgAgAAEJsQItfAAhAAAAAA==.',
Dv='Dvmcquéén:BAABLgAECn8WAAMCAAcJ5xkzCwANAgACAAcJ5xkzCwANAgABAAIJBwRHBwFOAAAAAA==.',
Dw='Dweams:BAACLgAFFH8cAAIgAAcJTxk9AQAnAgAgAAcJTxk9AQAnAgAuAAQKfzsAAyAACQmLJpEAAIEDACAACQmLJpEAAIEDACEABAmrDNE5ANgAAAAA.Dweamu:BAAALgAECgQJBgAAAA==.',
['Dâ']='Dântæ:BAAALgAECgUJDwAAAA==.',
['Då']='Dåmon:BAAALgAECgEJAgAAAA==.',
['Dö']='Döts:BAAALgADCgMJAgAAAA==.',
['Dø']='Døctøred:BAAALgAECgYJEwAAAA==.',
Ec='Ectonight:BAAALgAECgQJBwAAAA==.',
Ed='Edgybob:BAAALgAECgMJAwAAAA==.',
Eg='Eggfooyung:BAACLgAFFH8XAAIVAAYJAxndDADDAQAVAAYJAxndDADDAQAuAAQKfzIAAxUACQmPIRcEAC8DABUACQmPIRcEAC8DACIABwlPCCk7ADABAAAA.Egwene:BAAALgAECgYJBwAAAA==.',
El='Eldar:BAAALgAECgUJBQAAAA==.Elfchick:BAAALgADCgEJAQAAAA==.Elhonna:BAAALgAECgQJBAAAAA==.Elsâ:BAAALgAECgQJCAAAAA==.',
Em='Emwen:BAAALgADCgMJAwAAAA==.',
En='Endcredits:BAABLgAECn8fAAIKAAgJqg6rHgAvAQAKAAgJqg6rHgAvAQAAAA==.',
Et='Ether:BAABLgAECn8eAAIMAAgJzhPUKADNAQAMAAgJzhPUKADNAQAAAA==.Ettie:BAAALgADCgEJAQABLgAECgQJBQAGAAAAAA==.',
Ev='Evieroot:BAAALgADCgMJAwAAAA==.Evoulker:BAACLgAFFH8gAAIjAAgJDBvyAABWAgAjAAgJDBvyAABWAgAuAAQKf0EAAiMACQkSH6YFAO4CACMACQkSH6YFAO4CAAAA.',
Ex='Exodyce:BAAALgAECgQJBAAAAA==.',
Ey='Eyecantsee:BAAALgADCgIJAgABLgADCgcJBwAGAAAAAA==.',
Fa='Faene:BAAALgAECgQJCgABLgAECgUJBQAGAAAAAA==.Faire:BAAALgADCgUJBQABLgAFFAQJCgAFAFYZAA==.Fairytale:BAACLgAFFH8dAAMhAAcJhxFLAwDPAQAhAAcJhxFLAwDPAQAfAAEJMwjHEwBGAAAuAAQKf0EAAyEACQlmIAAHANUCACEACQlmHQAHANUCAB8ABwn5HkcSAE4CAAAA.Faitza:BAAALgAECgYJCgAAAA==.Fantastico:BAAALgAECgUJDQAAAA==.',
Fe='Felheim:BAACLgAFFH8NAAIDAAQJkAt7QAD8AAADAAQJkAt7QAD8AAAuAAQKfyAAAgMACQlrHOsXAGoCAAMACQlrHOsXAGoCAAAA.Fellitha:BAABLgAECn8UAAIKAAgJKwKTMwCdAAAKAAgJKwKTMwCdAAAAAA==.Fellithà:BAAALgAECgUJCwAAAA==.Felrend:BAAALgADCgMJAgAAAA==.Fentertained:BAAALgADCgcJCAAAAA==.',
Fi='Fiercevalkyr:BAAALgAECgkJBgAAAA==.Firsttower:BAAALgADCgIJAgAAAA==.Fists:BAACLgAFFH8MAAIVAAQJfyAbEwB1AQAVAAQJfyAbEwB1AQAuAAQKfzUABBUACQlMHSUKAMMCABUACQlMHSUKAMMCABAABAlOFrRdAMwAACIAAwlrFKZGALoAAAAA.Fizle:BAABLgAECn8YAAIjAAcJnwsJGAAsAQAjAAcJnwsJGAAsAQAAAA==.',
Fl='Flink:BAAALgAECgYJEwAAAA==.',
Fr='Friend:BAAALgAECgYJEAAAAA==.Frostmoan:BAAALgAFFAEJAQAAAA==.Frostyninja:BAABLgAECn8jAAIFAAgJlgYNewAaAQAFAAgJlgYNewAaAQAAAA==.',
Ga='Gabryal:BAABLgAECn8eAAIgAAgJDx4MEAA2AgAgAAgJDx4MEAA2AgAAAA==.Galthur:BAAALgAECgUJBgAAAA==.Garchomp:BAAALgAECgUJEwAAAA==.',
Ge='Gellina:BAAALgAECgUJBgAAAA==.Georg:BAACLgAFFH8bAAIOAAYJuRwPAwDIAQAOAAYJuRwPAwDIAQAuAAQKfzIAAg4ACQm7JjADAKMDAA4ACQm7JjADAKMDAAAA.Gerbankis:BAAALgAECgMJAwAAAA==.',
Gh='Ghoul:BAACLgAFFH8GAAIJAAIJICXogADSAAAJAAIJICXogADSAAAuAAQKfxoAAgkACAmSI+gZAOECAAkACAmSI+gZAOECAAAA.Ghouligan:BAAALgAECgQJBAAAAA==.',
Gi='Giga:BAAALgADCgYJBgAAAA==.',
Gl='Glaiver:BAABLgAECn8dAAIkAAgJhg6nHABaAQAkAAgJhg6nHABaAQAAAA==.Glassjaw:BAAALgADCgUJBQAAAA==.',
Go='Goewin:BAAALgAECgUJBgABLgAECgcJIAADAOMeAA==.Gojo:BAAALgADCgYJDwAAAA==.Goodbye:BAAALgADCgUJBQAAAA==.Gorgrom:BAAALgADCgIJAgAAAA==.',
Gr='Gradiant:BAAALgAECgEJAgABLgAECgkJLwALACcXAA==.Greg:BAAALgAECgIJAgAAAA==.Gregorz:BAAALgAECgEJAQAAAA==.',
Gu='Gulgodeth:BAAALgAECgQJBAAAAA==.Gulgrimmar:BAACLgAFFH8cAAMMAAgJFyA+AgB3AgAMAAcJ7CA+AgB3AgALAAEJPQxKIABRAAAuAAQKfzcAAgwACQnnJqwAANkDAAwACQnnJqwAANkDAAAA.Guwudanielle:BAAALgAECgcJEQABLgAFFAQJCgAFAFYZAA==.',
Ha='Hailsstorm:BAAALgADCgcJEgAAAA==.Hardfeelings:BAABLgAECn8cAAIOAAgJ+hnWMwAQAgAOAAgJ+hnWMwAQAgAAAA==.Harkness:BAAALgAECgYJDQAAAA==.Hassif:BAAALgAECgEJAQAAAA==.',
He='Heimerdoodle:BAAALgAECggJEwAAAA==.Hemlawk:BAAALgAECgEJAQAAAA==.Hemus:BAAALgAECgMJAwAAAA==.Hexed:BAABLgAECn8kAAIQAAgJ8gpTLAA5AQAQAAgJ8gpTLAA5AQAAAA==.',
Hu='Hughue:BAAALgADCgUJBQAAAA==.Hugs:BAAALgAECgYJCgAAAA==.Hurjek:BAAALgADCgEJAQABLgAFFAQJCwAVAIceAA==.',
Hy='Hyuna:BAAALgAECgEJAQABLgAECgcJDgAGAAAAAA==.',
Ia='Iaso:BAAALgAECgYJEQAAAA==.',
Ic='Iconstar:BAAALgADCgMJAwAAAA==.',
Ig='Igneel:BAAALgADCgQJAQAAAA==.',
Ij='Ijustankedu:BAAALgAECgMJAwAAAA==.',
Ik='Ikiea:BAAALgAECgcJCAAAAA==.',
Il='Ilgrim:BAABLgAECn8XAAMPAAgJWxkGJAC/AQAPAAgJWxkGJAC/AQAOAAMJEAO2LAFIAAABLgAFFAUJCgAbANgNAA==.Ilravenll:BAACLgAFFH8KAAIbAAUJ2A3fFwApAQAbAAUJ2A3fFwApAQAuAAQKfxgAAhsABgn6HOAbAI4BABsABgn6HOAbAI4BAAAA.Ilyana:BAACLgAFFH8ZAAIEAAcJnhnKDAAiAgAEAAcJnhnKDAAiAgAuAAQKf0EAAgQACQk2JncCAHMDAAQACQk2JncCAHMDAAAA.',
Im='Impavido:BAAALgAECgYJBgAAAA==.',
In='Inholy:BAAALgAECgYJEAAAAA==.Insights:BAAALgADCgMJAwAAAA==.',
Is='Isabella:BAAALgAECgEJAQABLgAFFAQJCgAFAFYZAA==.',
It='Ithopel:BAABLgAECn8jAAIIAAYJASF6KAASAgAIAAYJASF6KAASAgAAAA==.',
Ja='Jalista:BAAALgADCgMJAwAAAA==.Jayc:BAACLgAFFH8WAAIEAAUJKSB9NgBWAQAEAAUJKSB9NgBWAQAuAAQKfx0AAgQACAlgHid0AOoBAAQACAlgHid0AOoBAAAA.',
Je='Jereico:BAACLgAFFH8hAAIZAAgJmCLrAACQAgAZAAgJmCLrAACQAgAuAAQKfzsAAhkACQnmJjMAAJkDABkACQnmJjMAAJkDAAAA.Jeryhn:BAACLgAFFH8dAAIPAAgJnhJEAgDZAQAPAAgJnhJEAgDZAQAuAAQKf0EAAg8ACQk8GhYTAHoCAA8ACQk8GhYTAHoCAAAA.',
Jo='Joeburrow:BAAALgAECgQJBAAAAA==.Joeynodz:BAAALgADCgYJEgAAAA==.Jortshorts:BAABLgAECn8vAAIlAAkJ+AnWEwBIAQAlAAkJ+AnWEwBIAQAAAA==.',
Jr='Jray:BAABLgAECn8VAAIOAAYJGRnOZAC3AQAOAAYJGRnOZAC3AQAAAA==.',
Ju='Juggalo:BAACLgAFFH8HAAMNAAMJpxxDBAAWAQANAAMJpxxDBAAWAQAZAAEJkQa+UgA6AAAuAAQKfysAAw0ACQllIigBAOUCAA0ACQllIigBAOUCABkAAgmJEqpzAEkAAAAA.June:BAACLgAFFH8eAAIVAAcJmhmxAQAaAgAVAAcJmhmxAQAaAgAuAAQKfz8AAxUACQlsIbMEAB0DABUACQlsIbMEAB0DACIACQkGH/4GALkCAAAA.Juuju:BAAALgAECgYJDgAAAA==.',
Ka='Kaldriss:BAAALgAECgEJAgAAAA==.Kalen:BAAALgADCgEJAgAAAA==.Katashimus:BAAALgAECgYJCwAAAA==.Kawasuoo:BAABLgAECn8fAAMIAAgJMR3BHQA0AgAIAAcJzhzBHQA0AgAmAAYJAAzwLgCpAAAAAA==.Kaze:BAAALgAECgcJEQAAAA==.',
Kh='Khaotichic:BAABLgAECn8VAAIFAAYJ3wsBgwAIAQAFAAYJ3wsBgwAIAQAAAA==.Khrenak:BAAALgAECgQJCgAAAA==.',
Ki='Kickpunch:BAAALgAECgYJDgAAAA==.Kirah:BAACLgAFFH8HAAIZAAIJmBwMOQCtAAAZAAIJmBwMOQCtAAAuAAQKfyAAAhkACQmwIWoEAEoDABkACQmwIWoEAEoDAAEuAAUUBAkKAAUAVhkA.',
Kl='Kläus:BAAALgAECgEJAQAAAA==.',
Ko='Koddin:BAABLgAECn8zAAIOAAkJ6h70HAB6AgAOAAkJ6h70HAB6AgAAAA==.Korenchkin:BAAALgAECgEJAgAAAA==.Koreth:BAACLgAFFH8aAAMbAAYJLCE3BgDNAQAbAAUJLCE3BgDNAQASAAEJAACyBwA5AAAuAAQKf0cAAxsACQmAJhIBAF0DABsACQmAJhIBAF0DABIACAmWGg8EAHcCAAAA.Kornholyo:BAAALgAECgEJAQAAAA==.',
Kr='Kragoth:BAAALgADCgIJAgAAAA==.',
Ku='Kutuzov:BAABLgAECn8VAAILAAUJABb/UAA4AQALAAUJABb/UAA4AQAAAA==.',
Kw='Kwaiza:BAAALgAECgYJDwAAAA==.',
['Ká']='Káel:BAAALgAECgMJAwAAAA==.',
La='Lailaysia:BAAALgAECggJEgAAAA==.Lamemoosaur:BAAALgADCgIJAgABLgAECgYJCgAGAAAAAA==.Laríca:BAACLgAFFH8QAAIPAAQJmSYRCwC+AQAPAAQJmSYRCwC+AQAuAAQKfy0AAg8ACQlNJYMCAFIDAA8ACQlNJYMCAFIDAAAA.Laustin:BAABLgAECn8iAAQRAAgJhBxKDQA2AgARAAgJexxKDQA2AgAnAAYJEhC6FgDcAAAFAAIJbwUX2QBXAAAAAA==.Laustinjung:BAAALgADCgIJAQAAAA==.Laydout:BAAALgAECggJDQABLgAECgkJGQAFALYhAA==.Laydoutyota:BAABLgAECn8ZAAIFAAkJtiEZGQByAgAFAAkJtiEZGQByAgAAAA==.',
Le='Leag:BAABLgAECn8YAAMTAAcJFw+MQACiAQATAAcJFw+MQACiAQAeAAEJJAmvPwA5AAAAAA==.Lemonruss:BAAALgADCgQJBAAAAA==.',
Li='Liaria:BAAALgAECgEJAQAAAA==.Lilea:BAACLgAFFH8JAAIFAAMJUhqfPAD2AAAFAAMJUhqfPAD2AAAuAAQKfzUAAwUACQnFH0IOALkCAAUACQnFH0IOALkCACcABwnrEfc0AJYBAAAA.Lithium:BAAALgADCgUJBQAAAA==.Littledeb:BAAALgAFFAEJAQAAAA==.',
Lo='Lockdots:BAAALgADCgEJAQAAAA==.Lolchaosbolt:BAAALgADCgYJBgAAAA==.Lortherian:BAAALgAECgYJDwAAAA==.Lowbo:BAAALgADCgUJBQAAAA==.Lowelfesteem:BAAALgADCgUJBQAAAA==.',
Lu='Lucey:BAAALgAECgEJAQAAAA==.Lucille:BAABLgAECn8ZAAIEAAYJ3geCwQDqAAAEAAYJ3geCwQDqAAAAAA==.',
Ly='Lyndira:BAAALgAECgUJBQAAAA==.',
['Lä']='Läwlbringer:BAAALgAECggJDQAAAA==.',
['Lî']='Lîghtt:BAAALgADCgQJBAAAAA==.',
Ma='Mabritos:BAAALgAECgQJBQABLgAFFAYJGgAnAJ8eAA==.Maccabee:BAAALgAECgEJAQAAAA==.Mania:BAAALgADCgYJBgABLgAECgkJIwATAL8dAA==.Mathath:BAACLgAFFH8NAAIJAAQJ5QuDVwAfAQAJAAQJ5QuDVwAfAQAuAAQKfxwAAwkACAn4F7RHAMgBAAkACAnIF7RHAMgBAAoABAlUFacoAPkAAAAA.Mathmath:BAAALgAECgUJCgABLgAECgcJIAADAOMeAA==.Mathoras:BAABLgAECn8ZAAIBAAkJKBZAKwAUAgABAAkJKBZAKwAUAgAAAA==.Mazraq:BAAALgAECgEJAQABLgAECgkJLwALACcXAA==.',
Me='Meandean:BAAALgAECgIJBgAAAA==.Meatier:BAAALgAECgEJAQABLgAECgkJIwATAL8dAA==.Meatless:BAAALgADCgcJDQAAAA==.',
Mi='Micmac:BAAALgAECgQJCQAAAA==.Milo:BAAALgAECgIJAgAAAA==.Miltonroe:BAABLgAECn8iAAIHAAgJ6Q48EQBhAQAHAAgJ6Q48EQBhAQAAAA==.Mirithul:BAAALgADCgYJBwAAAA==.Mischiëf:BAAALgAECgYJDQAAAA==.Mitsuri:BAABLgAECn8iAAIEAAgJoQrekgCtAQAEAAgJoQrekgCtAQAAAA==.',
Mo='Modr:BAAALgAECgkJEgAAAA==.Moiraine:BAAALgAECgEJAQAAAA==.Monkynate:BAAALgAECgYJCgAAAA==.Monsterskill:BAABLgAECn8iAAQUAAgJzhgeEAAsAQAUAAYJuRYeEAAsAQABAAUJdBnlhQAZAQACAAUJhxNULQAIAQAAAA==.Moonerva:BAABLgAECn8fAAIoAAgJgAxKLABEAQAoAAgJgAxKLABEAQAAAA==.Morpheos:BAAALgADCgQJBAAAAA==.Mortgage:BAAALgADCgUJBQAAAA==.',
Mu='Mutsu:BAAALgADCgcJBwAAAA==.',
Mv='Mvqchx:BAAALgAECgUJCQAAAA==.',
Na='Naturelass:BAAALgADCgUJBQAAAA==.Nausicaa:BAAALgAECgEJAQAAAA==.Nawwll:BAAALgADCgMJAwAAAA==.',
Ne='Neotama:BAAALgAECggJEgAAAA==.Nethis:BAABLgAECn8nAAIgAAgJmRwHEgAfAgAgAAgJmRwHEgAfAgAAAA==.',
Ni='Niatpacgrom:BAABLgAECn8iAAIHAAkJbBmbBQBbAgAHAAkJbBmbBQBbAgAAAA==.Nivla:BAAALgADCgMJAwAAAA==.',
No='Nobacon:BAAALgAECgMJBwAAAA==.Nokix:BAAALgADCgkJDgAAAA==.Norah:BAAALgAECgEJAQAAAA==.Norvis:BAAALgAECgQJBQAAAA==.Notdragon:BAAALgAECgQJEQAAAA==.',
Nu='Nukeddukem:BAAALgAECgYJEgAAAA==.',
Nv='Nv:BAAALgAECggJEwAAAA==.',
Ny='Nymrod:BAABLgAECn8sAAMBAAkJSBQpLwAEAgABAAkJSBQpLwAEAgACAAIJpgduZQBEAAAAAA==.',
['Ní']='Nír:BAAALgAECgQJBAAAAA==.',
Ob='Oben:BAAALgAECggJAQAAAA==.',
Oj='Ojou:BAAALgADCgMJAwABLgAFFAMJAwAGAAAAAA==.',
Om='Omizzig:BAAALgAECgUJCwAAAA==.',
On='Onepunch:BAAALgAECgQJBgAAAA==.',
Or='Orcman:BAAALgADCgIJAgABLgADCgcJBwAGAAAAAA==.Orloran:BAAALgADCgIJAgAAAA==.',
Pa='Palthur:BAAALgAECgUJDAAAAA==.Parria:BAAALgAECgYJEgABLgAECggJEgAGAAAAAA==.Pasqualino:BAAALgAECgYJCgAAAA==.Passionate:BAACLgAFFH8MAAIjAAQJwAy5FQADAQAjAAQJwAy5FQADAQAuAAQKfyYAAiMACAmfFFYVAPUBACMACAmfFFYVAPUBAAAA.',
Pe='Peepis:BAAALgADCgEJAQABLgAECgkJIwATAL8dAA==.Pennance:BAABLgAECn8iAAIPAAkJ/RuZDgCiAgAPAAkJ/RuZDgCiAgAAAA==.',
Ph='Phatmidas:BAABLgAECn8sAAIOAAgJhxmVTADCAQAOAAgJhxmVTADCAQAAAA==.Philth:BAAALgAECgUJBQAAAA==.',
Pi='Pistfist:BAAALgAECgcJAQAAAA==.',
Pl='Plagueground:BAACLgAFFH8TAAIJAAYJYCA7BQBgAgAJAAYJYCA7BQBgAgAuAAQKf0QAAgkACQnhJkEBAIEDAAkACQnhJkEBAIEDAAAA.Plutonyus:BAAALgAECgEJAQAAAA==.',
Po='Poc:BAABLgAECn8ZAAIEAAYJPB3wdADoAQAEAAYJPB3wdADoAQAAAA==.Pockets:BAAALgAECgMJBwAAAA==.Potatopotato:BAACLgAFFH8IAAIbAAIJYhUHJgCeAAAbAAIJYhUHJgCeAAAuAAQKfyIAAhsACQk0FSUcAB4CABsACQk0FSUcAB4CAAAA.Pounces:BAAALgAECgYJEgABLgAECgcJGAAZAKgXAA==.Powerfistin:BAAALgADCgcJBwAAAA==.',
Pr='Prosecutor:BAAALgAECgUJDAAAAA==.Prynts:BAABLgAECn8VAAIOAAcJZh3sRAAVAgAOAAcJZh3sRAAVAgAAAA==.Prøzak:BAABLgAECn8VAAIQAAgJeQuJLQAyAQAQAAgJeQuJLQAyAQAAAA==.',
Pu='Puetrid:BAAALgADCgYJBgABLgAECgQJBAAGAAAAAA==.',
Ra='Raanky:BAAALgAECgEJAQAAAA==.Radiantlight:BAAALgAECgMJBAAAAA==.Randomly:BAAALgAECgQJBAAAAA==.Raspberries:BAAALgAECgcJBwAAAA==.Rautha:BAAALgAECgkJEgAAAA==.Rayl:BAAALgAECgYJEwAAAA==.Razsputin:BAAALgAECgMJBwAAAA==.',
Re='Rekless:BAAALgADCgUJBQAAAA==.Rethgar:BAAALgAECgUJEgAAAA==.',
Rh='Rhaegosa:BAABLgAECn8zAAQZAAkJDxmtIQCpAQAZAAcJ0xmtIQCpAQAjAAQJjBYKGAAsAQANAAQJrg1LFACkAAAAAA==.Rhavik:BAAALgAECgQJBQAAAA==.Rhekt:BAAALgAECgIJBQAAAA==.Rhokladar:BAAALgAECgQJCgAAAA==.',
Ri='Ridcully:BAABLgAECn8bAAIIAAgJlxdoMwCsAQAIAAgJlxdoMwCsAQAAAA==.Rimath:BAAALgAECgcJBAAAAA==.Rinswind:BAAALgADCgMJAwAAAA==.',
Ro='Robopacman:BAACLgAFFH8QAAQJAAUJvyCzMABjAQAJAAQJvyCzMABjAQAYAAEJUR3yFQBWAAAKAAEJAADxNAAAAAAuAAQKfy8AAgkACQnyJBgPACMDAAkACQnyJBgPACMDAAAA.Rodstewart:BAACLgAFFH8ZAAMFAAgJShhcBwDCAQAFAAUJSxxcBwDCAQAnAAUJUgzvFAD2AAAuAAQKfycAAwUACQmwJE0WAIYCAAUACAmPJE0WAIYCACcABwnbHxomAPgBAAAA.Roofeo:BAABLgAECn8dAAQCAAgJqRSxCwBXAQACAAYJmBaxCwBXAQAUAAQJgBBjFgDXAAABAAQJcgytrwDMAAAAAA==.Rotdaddy:BAABLgAECn8lAAIJAAgJ7gQzkwAaAQAJAAgJ7gQzkwAaAQAAAA==.',
Ry='Ryoshin:BAAALgADCgEJAQABLgAECgYJDQAGAAAAAA==.Ryzel:BAAALgADCgUJBQAAAA==.',
['Rï']='Rïn:BAAALgADCgEJAQAAAA==.',
Sa='Salas:BAABLgAECn8UAAIBAAcJzgxnfgAnAQABAAcJzgxnfgAnAQAAAA==.Salino:BAAALgAECgUJBQAAAA==.Salinoster:BAAALgADCgEJAQAAAA==.Salordell:BAAALgADCgIJAwAAAA==.Sam:BAAALgADCgEJAQAAAA==.Sanque:BAAALgADCgQJAwAAAA==.Sarate:BAABLgAECn8rAAIgAAgJ3A5+JQB2AQAgAAgJ3A5+JQB2AQAAAA==.Savannah:BAABLgAFFH8KAAIFAAQJVhlVHwBJAQAFAAQJVhlVHwBJAQAAAA==.Savvtwo:BAAALgADCgcJBwABLgAFFAgJHQADAPEiAQ==.',
Sc='Scathach:BAABLgAECn8gAAMDAAcJ4x6cMgDbAQADAAcJ4x6cMgDbAQAkAAQJURguRADmAAAAAA==.Scoop:BAAALgADCgYJBgAAAA==.Scorandom:BAAALgAECgEJAQAAAA==.',
Se='Seven:BAAALgAECgIJBAAAAA==.Sezra:BAAALgADCgkJAQAAAA==.',
Sh='Shamalam:BAAALgADCgEJAQAAAA==.Shei:BAAALgAECgIJAgAAAA==.Sheidon:BAAALgAECgQJBAAAAA==.Shinanigans:BAAALgAECgYJDwAAAA==.Shruikan:BAAALgADCggJDAAAAA==.',
Si='Silverslam:BAAALgAECgEJAQABLgAECggJGAAHAEESAA==.Sinatra:BAAALgAECgIJBAABLgAECgcJEQAGAAAAAA==.Siqodel:BAAALgADCgYJCAAAAA==.',
Sk='Skurge:BAAALgAECgYJDwAAAA==.',
Sl='Slamb:BAAALgAECgYJBwAAAA==.Slimetongue:BAAALgADCgMJAwAAAA==.',
Sm='Smaaug:BAAALgAFFAMJAwAAAA==.',
Sn='Snuggle:BAAALgAECgEJAQAAAA==.',
So='Solstis:BAAALgAECggJDgAAAA==.Sorzsnipe:BAAALgADCgQJBAAAAA==.',
Sp='Spellchücker:BAAALgAECgcJDQAAAA==.Spfzero:BAAALgAECgEJAQAAAA==.',
St='Staggered:BAACLgAFFH8PAAIQAAQJoh7kEgBTAQAQAAQJoh7kEgBTAQAuAAQKfyUAAxAACAkOIusLAM8CABAACAkOIusLAM8CACIAAQk1A9WMABwAAAAA.Stoneojinray:BAAALgADCgEJAQAAAA==.Stoneorcman:BAAALgADCgcJBwAAAA==.Stormriderr:BAAALgAECgYJCQAAAA==.',
Su='Subdofu:BAAALgADCgQJBAABLgAECgcJFwAbAN0cAA==.Subtox:BAABLgAECn8XAAMbAAcJ3RxNIQDvAQAbAAcJ3RxNIQDvAQASAAEJkgu5HwA0AAAAAA==.',
Sw='Sweetcool:BAAALgAECgUJCQABLgAECggJLQAFAN4hAA==.Sweetzeke:BAAALgAECgEJAQAAAA==.',
Sy='Syphilistjt:BAABLgAECn8WAAIhAAgJ0xLIFwDgAQAhAAgJ0xLIFwDgAQAAAA==.Syphillis:BAAALgAECgYJCgAAAA==.',
['Sá']='Sálud:BAACLgAFFH8MAAIoAAUJix+UDwBlAQAoAAUJix+UDwBlAQAuAAQKfyIAAygACAmSH4APAKkCACgABwlcIYAPAKkCACYABwmhGTEQAKgBAAAA.',
['Sê']='Sêp:BAAALgAECggJDAAAAA==.',
Ta='Takoda:BAAALgAECgEJAQAAAA==.Talivath:BAAALgADCgEJAQAAAA==.Tanissaria:BAAALgADCgIJAgAAAA==.Taranith:BAAALgAECgUJBQABLgAECggJGQAEAPoTAA==.Tarhealeon:BAABLgAECn9cAAMPAAkJyRuWIQARAgAPAAkJyRuWIQARAgAOAAkJnBSCOAAAAgAAAA==.Tarmander:BAAALgAECgYJDgAAAA==.Taylörshift:BAAALgAECgQJBwAAAA==.',
Te='Telahnicus:BAAALgAECgEJAQAAAA==.Terranox:BAAALgADCgMJAwAAAA==.Testostauren:BAAALgAECgMJBgAAAA==.',
Th='Thabigone:BAAALgAECgYJDAAAAA==.Thalnaria:BAAALgAECgYJCwAAAA==.Threebuttons:BAAALgAECgUJDgABLgAFFAQJDwAjADULAA==.Thunderkis:BAAALgAECgYJEwAAAA==.',
Ti='Tiewaz:BAAALgAECgYJBgABLgAECggJHwAEAFoPAA==.Tiewiz:BAABLgAECn8fAAMEAAgJWg/cdwBsAQAEAAgJEQzcdwBsAQApAAUJlw2VCgCpAAAAAA==.',
To='Tointjoker:BAAALgAECgMJBAAAAA==.Tolun:BAABLgAECn8/AAIEAAkJqhwnGACuAgAEAAkJqhwnGACuAgAAAA==.Tosan:BAAALgADCggJDgAAAA==.',
Tr='Treeplague:BAABLgAECn86AAMgAAkJcxDuGQDRAQAgAAkJcxDuGQDRAQAhAAYJnxRsIwCDAQAAAA==.Trypleg:BAAALgAECgMJAwAAAA==.',
Tu='Tumadre:BAAALgAECgEJAQAAAA==.Tungie:BAABLgAECn8bAAIJAAgJ0iAeNQAHAgAJAAgJ0iAeNQAHAgAAAA==.Turn:BAACLgAFFH8kAAQBAAgJoxVyCAChAQABAAYJnhpyCAChAQACAAUJwg2+AwBcAQAUAAIJmSCKDwBaAAAuAAQKf0QABAEACQn9Jb8UANkCAAEACAklJb8UANkCABQAAwlJJjsWANkAAAIAAwlXJJEWAM0AAAAA.Turtleduck:BAABLgAECn8fAAINAAgJ/BjgBAD7AQANAAgJ/BjgBAD7AQAAAA==.Tuskbreaker:BAAALgAECgIJAgAAAA==.',
Tw='Twittytister:BAAALgADCgQJBAAAAA==.Twostrokes:BAAALgAECgEJAQAAAA==.',
Ty='Tyrese:BAAALgADCggJEAAAAA==.',
Uf='Uffin:BAAALgAECgQJBQAAAA==.',
Um='Umbryx:BAAALgAECgYJDQAAAA==.',
Un='Unagi:BAABLgAECn8VAAIHAAgJrQ0LEAB2AQAHAAgJrQ0LEAB2AQAAAA==.Unholy:BAAALgADCgIJAgAAAA==.',
Va='Valdi:BAABLgAECn8ZAAIOAAcJkwwPnAAcAQAOAAcJkwwPnAAcAQAAAA==.',
Ve='Velthera:BAABLgAECn8XAAIjAAgJCyJEBAAQAwAjAAgJCyJEBAAQAwABLgAFFAQJCwAVAIceAA==.Venomlight:BAAALgADCgIJAgAAAA==.Venomstrikes:BAAALgAECgcJEQAAAA==.Venratzi:BAAALgAECgQJBAAAAA==.Vespertina:BAAALgADCgYJBgAAAA==.',
Vo='Voridor:BAAALgADCgEJAQAAAA==.Voulk:BAAALgAFFAMJAwABLgAFFAgJIAAjAAwbAA==.',
Vy='Vyllan:BAABLgAECn8bAAQUAAgJAQYCEwD8AAABAAgJmgV9hAAcAQAUAAYJKwQCEwD8AAACAAMJmgEDOAArAAAAAA==.',
Wa='Waldgeist:BAAALgAECgUJBQABLgAECgkJIwATAL8dAA==.Walthur:BAAALgADCgkJDQAAAA==.Waobby:BAAALgADCgIJAgAAAA==.Warrpigg:BAAALgAECgEJAQAAAA==.Waterdrinker:BAAALgAECgQJBgAAAA==.Wavybone:BAAALgAECgEJAgAAAA==.',
Wh='Whiisper:BAAALgADCgMJAwAAAA==.Whoarlock:BAAALgADCgUJCAAAAA==.',
Wo='Wo:BAAALgADCgMJAwAAAA==.',
Wu='Wutangstyle:BAAALgAECgIJAgABLgAECgkJIwATAL8dAA==.',
Wy='Wyatta:BAAALgADCgIJAgAAAA==.',
Xe='Xelinia:BAACLgAFFH8QAAIgAAUJoxJXFQAgAQAgAAUJoxJXFQAgAQAuAAQKfyEAAiAACQk5H20MALwCACAACQk5H20MALwCAAAA.Xen:BAABLgAFFH8FAAIlAAQJxQ/ZBQAvAQAlAAQJxQ/ZBQAvAQAAAA==.',
Xf='Xfortune:BAAALgADCgcJCQAAAA==.',
Xh='Xholycritz:BAAALgAECgMJBAAAAA==.',
Xu='Xuefeng:BAACLgAFFH8QAAIiAAQJjhbADAA0AQAiAAQJjhbADAA0AQAuAAQKfzcAAiIACQl7IFQFANwCACIACQl7IFQFANwCAAAA.',
Ye='Yenchmeister:BAACLgAFFH8cAAMTAAcJkxxEAwDDAQATAAUJuRxEAwDDAQAeAAYJ3RoAAgBiAQAuAAQKfygAAxMACQkgJdcJABEDABMACQkgJdcJABEDAB4AAgl3ICEoAK4AAAAA.',
Yo='Youngbusta:BAABLgAECn8zAAIEAAkJ9iIwDwDqAgAEAAkJ9iIwDwDqAgAAAA==.',
Yu='Yuta:BAAALgAECgYJDQAAAA==.',
Za='Zad:BAAALgADCgIJAgAAAA==.',
Ze='Zenrac:BAAALgADCgUJBQAAAA==.Zeromus:BAAALgAECgIJAgAAAA==.',
Zi='Zilvanic:BAACLgAFFH8KAAIXAAMJdwtsCgCdAAAXAAMJdwtsCgCdAAAuAAQKfyQABBcACAlgEm8SAHMBABcACAn0EW8SAHMBAA4ABQlZECbNANIAAA8AAwl8AQiDAGwAAAAA.Zilvanion:BAAALgAECgYJCgAAAA==.',
Zo='Zourknight:BAAALgADCgcJEAAAAA==.Zourlight:BAAALgADCgUJBgAAAA==.Zourlock:BAABLgAECn8WAAQBAAYJdRCdhgAXAQABAAYJAQ+dhgAXAQAUAAIJJhIKHwCAAAACAAEJAAAlbwA3AAAAAA==.Zourpatch:BAAALgADCgMJAwAAAA==.',
Zu='Zulvaz:BAAALgAECgIJAwAAAA==.Zurey:BAABLgAECn88AAIDAAkJVg2RSgCEAQADAAkJVg2RSgCEAQAAAA==.',
Zy='Zynjamin:BAACLgAFFH8cAAMNAAcJCiE9AAADAgANAAYJ6yM9AAADAgAZAAYJOB9hCQD4AQAuAAQKfy4AAg0ACQkLJC8AANsDAA0ACQkLJC8AANsDAAAA.',
['Ðr']='Ðrèamless:BAAALgAECgUJBwAAAA==.',
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
