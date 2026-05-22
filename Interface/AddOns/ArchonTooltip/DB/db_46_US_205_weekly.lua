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

local lookup = {'Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Shaman-Enhancement','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','Evoker-Devastation','Paladin-Retribution','Monk-Brewmaster','Hunter-Survival','Rogue-Assassination','Warrior-Fury','Warlock-Affliction','Paladin-Holy','Monk-Mistweaver','Mage-Fire','Paladin-Protection','Evoker-Augmentation','Rogue-Outlaw','Rogue-Subtlety','DeathKnight-Frost','DemonHunter-Vengeance','Warrior-Protection','Warrior-Arms','Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Windwalker','Evoker-Preservation','DemonHunter-Havoc','Druid-Feral','Druid-Guardian','Hunter-Marksmanship','Druid-Balance','Mage-Arcane',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aannte:BAACLgAFFH8ZAAMBAAgJxBgABgDAAQABAAYJCRcABgDAAQACAAQJ6BdlBAAYAQAuAAQKfyIAAwEACQlKIowmAHgCAAEACQk6IowmAHgCAAIABAnwHvcdAGABAAAA.Aardbark:BAAALgADCgEJAQAAAA==.',
Ac='Achtland:BAAALgAECgUJBgABLgAECgcJIAADAM8eAA==.',
Ad='Adekai:BAAALgAECgYJDgAAAA==.Adv:BAAALgAECgEJAQAAAA==.',
Ae='Aerestrix:BAAALgAECgYJBwAAAA==.',
Ai='Airvis:BAABLgAECn8dAAIEAAYJVwf5rgDpAAAEAAYJVwf5rgDpAAAAAA==.',
Al='Alacia:BAAALgAECggJDAABLgAFFAMJBgAFAIoWAA==.Alatarr:BAAALgAECgcJEQAAAA==.Albinomonk:BAAALgADCgcJBwAAAA==.',
An='Anankei:BAAALgAECgMJAwAAAA==.Annastrophic:BAAALgADCgMJAwAAAA==.Anrí:BAAALgAECgEJAQAAAA==.Antaria:BAAALgADCgcJFgAAAA==.Ante:BAAALgADCgUJAQAAAA==.Antiform:BAAALgAECgIJBgAAAA==.Antpony:BAAALgAECgIJAgABLgAECgYJCgAGAAAAAA==.',
Ar='Arcish:BAAALgAECgEJAgAAAA==.Arjun:BAABLgAECn8XAAIHAAgJFREwDACHAQAHAAgJFREwDACHAQAAAA==.Arkirla:BAAALgAECgEJAgAAAA==.Arkiyra:BAAALgAECggJDQAAAA==.Arkosh:BAAALgAECgEJAQAAAA==.Arkyra:BAAALgAECgUJBwAAAA==.Arovix:BAABLgAECn8VAAIIAAgJmxnHJQDbAQAIAAgJmxnHJQDbAQAAAA==.',
As='Ashwey:BAAALgADCgkJCAAAAA==.',
At='Atom:BAAALgAECgcJDQAAAA==.',
Au='Aubreey:BAAALgADCgcJCQAAAA==.Aureille:BAAALgAECgYJCgAAAA==.',
Aw='Awoozehl:BAACLgAFFH8fAAMJAAcJKyBiCQCaAQAJAAYJKyBiCQCaAQAKAAEJAAB/LgAAAAAuAAQKfz0AAgkACQnWJrcAAIgDAAkACQnWJrcAAIgDAAAA.',
Az='Azanoth:BAAALgAECgIJAgAAAA==.Azgrodon:BAABLgAECn8vAAMLAAkJJxdREwBfAgALAAkJJxdREwBfAgAMAAMJjww+bACSAAAAAA==.Azor:BAABLgAECn8YAAIDAAgJch08HQCiAgADAAgJch08HQCiAgAAAA==.',
Ba='Baja:BAAALgAECgQJBAAAAA==.Baldomar:BAAALgADCgUJCAAAAA==.Bangmonk:BAAALgAFFAQJBAABLgAFFAgJHQANACAgAA==.Bangungot:BAAALgADCgMJAwABLgAFFAgJHQANACAgAA==.Barzalie:BAAALgAECgYJDAABLgAFFAMJAwAGAAAAAA==.Bathrezz:BAABLgAECn8YAAIOAAgJTxgYRgCtAQAOAAgJTxgYRgCtAQAAAA==.',
Be='Beerbelly:BAAALgAFFAMJAwAAAA==.Beleaves:BAACLgAFFH8gAAIPAAgJYQftCQCEAQAPAAgJYQftCQCEAQAuAAQKfz8AAg8ACQmyG40HAIkCAA8ACQmyG40HAIkCAAAA.Beorl:BAAALgADCgYJCAAAAA==.',
Bh='Bhackshots:BAABLgAECn8XAAIQAAUJjSEtIABNAQAQAAUJjSEtIABNAQABLgAECggJMAARAO8jAA==.',
Bi='Bifurious:BAABLgAECn8eAAISAAkJox1kCACaAgASAAkJox1kCACaAgAAAA==.Bigrob:BAAALgAECgEJAwAAAA==.',
Bl='Blowmybubble:BAAALgADCgMJAwABLgAECgkJIAAFAKchAA==.Bluereindeer:BAABLgAECn8VAAIJAAkJAgsDSQCiAQAJAAkJAgsDSQCiAQAAAA==.',
Bo='Bobsstones:BAACLgAFFH8VAAQBAAgJHR7QAwDkAQABAAcJthzQAwDkAQACAAQJ6x0sBgANAQATAAEJoCUwCgBfAAAuAAQKfyUABAIACQlCJT0GAGwCAAEABwkmI/4bAK0CAAIABgmDJD0GAGwCABMAAglDJOgVANUAAAAA.Bonekitty:BAAALgAECgYJBgAAAA==.Bonkulo:BAABLgAECn8UAAMKAAcJUhJPGQAlAQAKAAYJQhVPGQAlAQAJAAEJoANpMAEgAAAAAA==.Boofassist:BAABLgAECn8dAAIUAAkJ7CKABAAmAwAUAAkJ7CKABAAmAwABLgAFFAYJFgAVAAMZAA==.Boogey:BAABLgAECn8UAAMEAAYJzQwNlwASAQAEAAYJzQwNlwASAQAWAAEJpQiNEAAyAAAAAA==.Boompowwow:BAABLgAECn8VAAIMAAYJIxnmNACDAQAMAAYJIxnmNACDAQAAAA==.Boomsonic:BAAALgADCgUJBQABLgAECgkJHgASAKMdAA==.Bophadeez:BAABLgAECn8lAAQUAAgJeB4bHwAgAgAUAAcJGiEbHwAgAgAXAAgJgha4CwC1AQAOAAYJvQ/MjABhAQAAAA==.',
Br='Broccoliz:BAECLgAFFH8gAAIIAAgJkA/0AgC9AQAIAAgJkA/0AgC9AQAuAAQKf0AAAggACQkUH9MYAHECAAgACQkUH9MYAHECAAAA.Brokgar:BAAALgAECggJEAAAAA==.Brotu:BAAALgADCgIJAQAAAA==.Bruceleroy:BAAALgADCgEJAQAAAA==.Brutalsmasch:BAAALgADCgUJBQAAAA==.',
Bu='Bubu:BAAALgAECgEJAQAAAA==.Bulis:BAAALgAECgEJAQAAAA==.Bullblaster:BAAALgAECgMJBQAAAA==.',
Bw='Bwonshamdi:BAAALgAECgcJBwABLgAECgcJBwAGAAAAAA==.',
['Bõ']='Bõb:BAAALgAECgMJBQAAAA==.',
Ca='Cafca:BAABLgAECn8uAAICAAkJQxi+AgA3AgACAAkJQxi+AgA3AgAAAA==.Caitlin:BAAALgAECgEJAQABLgAFFAQJBwAFALcRAA==.Callyour:BAAALgADCgIJAgAAAA==.Cask:BAAALgADCgYJAQAAAA==.',
Ch='Chainsawloli:BAAALgADCgUJBQAAAA==.Changying:BAAALgAECgcJCQAAAA==.Cheekung:BAAALgAECgcJEgAAAA==.Choedankal:BAAALgADCgcJBwAAAA==.Chophouse:BAAALgAECgkJBgAAAA==.',
Cl='Clearlyumad:BAACLgAFFH8MAAMJAAUJhxAmWACvAAAJAAQJhxAmWACvAAAKAAEJAAAtOwAAAAAuAAQKfxsAAgkACAmNHlE8AEYCAAkACAmNHlE8AEYCAAAA.Clèrick:BAABLgAECn8pAAIUAAgJxCMxCwCTAgAUAAgJxCMxCwCTAgAAAA==.',
Co='Coldcrow:BAAALgAECgEJAQAAAA==.Combination:BAABLgAFFH8HAAIVAAQJoxMmFgAZAQAVAAQJoxMmFgAZAQAAAA==.Confessor:BAAALgADCgEJAQAAAA==.Corruptions:BAAALgADCgEJAQAAAA==.',
Cr='Crux:BAAALgADCgQJBAAAAA==.',
Cy='Cyfrin:BAAALgADCgEJAQAAAA==.Cyânide:BAAALgADCgYJDQAAAA==.',
['Cõ']='Cõurage:BAAALgAECgYJCAAAAA==.',
Da='Dabbhammer:BAAALgAECgIJBAABLgAECggJGgANABMGAA==.Dabbzyvoker:BAABLgAECn8aAAMNAAgJEwZ/IgAWAQANAAYJowZ/IgAWAQAYAAgJVQVvPwDZAAAAAA==.Dallzbeep:BAAALgAECgkJCQABLgAFFAMJCQAVAFYiAA==.Danathoor:BAAALgADCggJCAAAAA==.Danathor:BAAALgADCgcJBwAAAA==.Dangbro:BAAALgAECgUJBwAAAA==.Dankspank:BAAALgAECgQJBQAAAA==.Danteus:BAAALgADCgMJAwABLgAECgUJDwAGAAAAAA==.Darkrigh:BAAALgADCggJDgAAAA==.Darkwave:BAABLgAECn8mAAIBAAgJnRZDMgDSAQABAAgJnRZDMgDSAQAAAA==.Darthdiddyus:BAACLgAFFH8eAAMZAAYJVCBnAQCFAQAZAAYJrh9nAQCFAQAaAAMJtxSnDQAQAQAuAAQKfzIABBkACQmeJEQAAEEDABkACQmaJEQAAEEDABoABwlRITwUAHICABEABAnJId0KAIIBAAAA.Datdruidguy:BAAALgADCgUJBQABLgAECgYJBgAGAAAAAA==.Datlock:BAAALgADCgEJAQABLgAECgYJBgAGAAAAAA==.Datshammy:BAAALgAECgYJBgAAAA==.Daviculas:BAAALgADCggJDgAAAA==.Dawghawg:BAAALgAECgQJBAAAAA==.Dawnnie:BAACLgAFFH8FAAIXAAIJTgmOCwBoAAAXAAIJTgmOCwBoAAAuAAQKfy4AAhcACAnKF8wMAPsBABcACAnKF8wMAPsBAAAA.Dawnte:BAABLgAECn8dAAIOAAcJHByuOwDOAQAOAAcJHByuOwDOAQABLgAECgUJDwAGAAAAAA==.Dawsonrogers:BAAALgAECgYJCgAAAA==.Dayvastate:BAABLgAECn8uAAMJAAkJtRkbIQBAAgAJAAkJNRkbIQBAAgAbAAEJDxK7IAA6AAAAAA==.Dazshir:BAAALgADCgMJAwAAAA==.',
De='Deathbanana:BAABLgAFFH8JAAIJAAMJHR/EVQC0AAAJAAMJHR/EVQC0AAABLgAFFAgJFwAEAAgaAA==.Deaththreat:BAAALgAECgQJBAABLgAECggJGAAOAMAYAA==.Delema:BAACLgAFFH8RAAIOAAUJph9EEwBwAQAOAAUJph9EEwBwAQAuAAQKfyAAAg4ACAlaIUQiAKACAA4ACAlaIUQiAKACAAAA.Democrit:BAAALgAECgIJAgAAAA==.Demonjuice:BAAALgAECgUJCAAAAA==.Derpyblinker:BAABLgAECn8VAAIEAAYJQRDu0wBHAQAEAAYJQRDu0wBHAQAAAA==.Destructer:BAABLgAECn8YAAICAAcJ8w7ODQAWAQACAAcJ8w7ODQAWAQAAAA==.Dethstar:BAAALgADCgUJBQABLgAECggJJgABAJ0WAA==.Devoured:BAAALgADCgMJAwAAAA==.',
Di='Dinger:BAAALgAECgEJAQAAAA==.Dirtydinker:BAAALgAECgYJDQAAAA==.Disconneted:BAAALgADCgYJBgAAAA==.Dishwasher:BAAALgADCgIJAgAAAA==.Dixsard:BAABLgAECn8wAAMRAAgJ7yOhAQCtAgARAAgJtiOhAQCtAgAaAAcJTB1tIwDeAQAAAA==.',
Do='Doezenn:BAAALgADCgUJBQAAAA==.Dottprepared:BAACLgAFFH8cAAIcAAYJeRGyAABRAQAcAAYJeRGyAABRAQAuAAQKfz8AAhwACQmMIpcBAAcDABwACQmMIpcBAAcDAAAA.Dottyfu:BAABLgAFFH8FAAIPAAMJKwkZLQC7AAAPAAMJKwkZLQC7AAAAAA==.Doubted:BAAALgAECgQJBAAAAA==.',
Dr='Dracoiconic:BAAALgAECgEJAgAAAA==.Dragonboffa:BAAALgAECgcJAQAAAA==.Draul:BAAALgAECgEJAQABLgAECgkJLwALACcXAA==.Drexl:BAACLgAFFH8PAAIdAAUJghG6BQARAQAdAAUJghG6BQARAQAuAAQKfzYABB4ACQkjHqADAKICAB4ACQnmHaADAKICABIABwkSBtplABwBAB0AAgmHDHo7AHAAAAAA.Dril:BAABLgAECn8aAAMDAAYJChnMSgBYAQADAAYJ7hjMSgBYAQAcAAIJAhZvIACBAAAAAA==.Drognin:BAAALgADCgEJAQAAAA==.Drunkfu:BAAALgADCgQJBAAAAA==.',
Du='Dubstep:BAAALgAECgkJAgAAAA==.Dudette:BAAALgAECgcJCwAAAA==.Dunlop:BAABLgAECn8VAAMfAAgJ5xCWFwDJAQAfAAgJ5xCWFwDJAQAgAAEJsQKnbQAhAAAAAA==.',
Dv='Dvmcquéén:BAABLgAECn8WAAMCAAcJ5xkzCwANAgACAAcJ5xkzCwANAgABAAIJBwRHBwFOAAAAAA==.',
Dw='Dweams:BAACLgAFFH8cAAIgAAcJSxk9AQAnAgAgAAcJSxk9AQAnAgAuAAQKfzoAAyAACQmKJmYAAIIDACAACQmKJmYAAIIDACEABAmrDNE5ANgAAAAA.',
['Dâ']='Dântæ:BAAALgAECgUJDwAAAA==.',
['Då']='Dåmon:BAAALgAECgEJAQAAAA==.',
['Dö']='Döts:BAAALgADCgMJAgAAAA==.',
['Dø']='Døctøred:BAAALgAECgYJEwAAAA==.',
Ec='Ectonight:BAAALgAECgQJBwAAAA==.',
Ed='Edgybob:BAAALgAECgMJAwAAAA==.',
Eg='Eggfooyung:BAACLgAFFH8WAAIVAAYJAxnICADUAQAVAAYJAxnICADUAQAuAAQKfzIAAxUACQmPIRcEAC8DABUACQmPIRcEAC8DACIABwlPCCk7ADABAAAA.Egwene:BAAALgAECgYJBwAAAA==.',
El='Eldar:BAAALgAECgUJBQAAAA==.Elfchick:BAAALgADCgEJAQAAAA==.Elhonna:BAAALgAECgQJBAAAAA==.Elsâ:BAAALgAECgQJCAAAAA==.',
Em='Emwen:BAAALgADCgMJAwAAAA==.',
En='Endcredits:BAABLgAECn8fAAIKAAgJqQ5gGwATAQAKAAgJqQ5gGwATAQAAAA==.',
Et='Ether:BAABLgAECn8eAAIMAAgJzhPUKADNAQAMAAgJzhPUKADNAQAAAA==.',
Ev='Evieroot:BAAALgADCgMJAwAAAA==.Evoulker:BAACLgAFFH8gAAIjAAgJEhvyAABWAgAjAAgJEhvyAABWAgAuAAQKfz8AAiMACQkTH6YFAO4CACMACQkTH6YFAO4CAAAA.',
Ex='Exodyce:BAAALgAECgQJBAAAAA==.',
Ey='Eyecantsee:BAAALgADCgIJAgABLgADCgcJBwAGAAAAAA==.',
Fa='Faene:BAAALgAECgQJCgABLgAECgUJBQAGAAAAAA==.Faire:BAAALgADCgUJBQABLgAFFAQJBwAFALcRAA==.Fairytale:BAACLgAFFH8dAAMhAAcJhxFLAwDPAQAhAAcJhxFLAwDPAQAfAAEJMwjHEwBGAAAuAAQKfz8AAyEACQlSIAAHANUCACEACQlTHQAHANUCAB8ABwn5HkcSAE4CAAAA.Faitza:BAAALgAECgYJCgAAAA==.Fantastico:BAAALgAECgUJDAAAAA==.',
Fe='Felheim:BAACLgAFFH8MAAIDAAQJkAvfNQADAQADAAQJkAvfNQADAQAuAAQKfxwAAgMACAkAG3IiAAMCAAMACAkAG3IiAAMCAAAA.Fellitha:BAABLgAECn8UAAIKAAgJKgLcLQCRAAAKAAgJKgLcLQCRAAAAAA==.Fellithà:BAAALgAECgUJCwAAAA==.Felrend:BAAALgADCgMJAgAAAA==.Fentertained:BAAALgADCgcJCAAAAA==.',
Fi='Fiercevalkyr:BAAALgAECgkJBgAAAA==.Firsttower:BAAALgADCgEJAQAAAA==.Fists:BAACLgAFFH8JAAIVAAMJViKuFAApAQAVAAMJViKuFAApAQAuAAQKfywAAxUACAnBHq0KAI0CABUACAnBHq0KAI0CAA8ABAlOFrRdAMwAAAAA.Fizle:BAABLgAECn8YAAIjAAcJngsXFQAvAQAjAAcJngsXFQAvAQAAAA==.',
Fl='Flink:BAAALgAECgYJEwAAAA==.',
Fr='Friend:BAAALgAECgYJEAAAAA==.Frostmoan:BAAALgAFFAEJAQAAAA==.Frostyninja:BAABLgAECn8jAAIFAAgJlgaJZgAcAQAFAAgJlgaJZgAcAQAAAA==.',
Ga='Gabryal:BAABLgAECn8eAAIgAAgJDh5LDABDAgAgAAgJDh5LDABDAgAAAA==.Galthur:BAAALgAECgQJBAAAAA==.Garchomp:BAAALgAECgUJEgAAAA==.',
Ge='Gellina:BAAALgAECgUJBgAAAA==.Georg:BAACLgAFFH8bAAIOAAYJuRwPAwDIAQAOAAYJuRwPAwDIAQAuAAQKfzAAAg4ACQmBJjADAKMDAA4ACQmBJjADAKMDAAAA.Gerbankis:BAAALgAECgMJAwAAAA==.',
Gh='Ghoul:BAABLgAECn8aAAIJAAgJkiPoGQDhAgAJAAgJkiPoGQDhAgAAAA==.Ghouligan:BAAALgAECgQJBAAAAA==.',
Gl='Glaiver:BAABLgAECn8dAAIkAAgJhQ6oFwBgAQAkAAgJhQ6oFwBgAQAAAA==.Glassjaw:BAAALgADCgUJBQAAAA==.',
Go='Goewin:BAAALgAECgUJBgABLgAECgcJIAADAM8eAA==.Gojo:BAAALgADCgYJDwAAAA==.Goodbye:BAAALgADCgUJBQAAAA==.Gorgrom:BAAALgADCgIJAgAAAA==.',
Gr='Gradiant:BAAALgAECgEJAgABLgAECgkJLwALACcXAA==.Greg:BAAALgAECgIJAgAAAA==.Gregorz:BAAALgAECgEJAQAAAA==.',
Gu='Gulgodeth:BAAALgAECgQJBAAAAA==.Gulgrimmar:BAACLgAFFH8cAAMMAAgJGiAlAQCCAgAMAAcJ8CAlAQCCAgALAAEJPQxKIABRAAAuAAQKfzUAAgwACQnfJqwAANkDAAwACQnfJqwAANkDAAAA.Guwudanielle:BAAALgAECgcJDwABLgAFFAQJBwAFALcRAA==.',
Ha='Hailsstorm:BAAALgADCgcJEgAAAA==.Hardfeelings:BAABLgAECn8YAAIOAAgJwBiAMAD4AQAOAAgJwBiAMAD4AQAAAA==.Harkness:BAAALgAECgYJDQAAAA==.Hassif:BAAALgAECgEJAQAAAA==.',
He='Heimerdoodle:BAAALgAECgcJEQAAAA==.Hemlawk:BAAALgAECgEJAQAAAA==.Hemus:BAAALgAECgMJAwAAAA==.Hexed:BAABLgAECn8dAAIPAAgJOAk3KgAoAQAPAAgJOAk3KgAoAQAAAA==.',
Hu='Hughue:BAAALgADCgUJBQAAAA==.Hugs:BAAALgAECgYJCgAAAA==.',
Hy='Hyuna:BAAALgAECgEJAQABLgAECgcJDgAGAAAAAA==.',
Ia='Iaso:BAAALgAECgYJEQAAAA==.',
Ic='Iconstar:BAAALgADCgMJAwAAAA==.',
Ig='Igneel:BAAALgADCgQJAQAAAA==.',
Ij='Ijustankedu:BAAALgAECgMJAwAAAA==.',
Ik='Ikiea:BAAALgAECgcJCAAAAA==.',
Il='Ilgrim:BAAALgAFFAIJAgABLgAFFAQJCAAaAD4NAA==.Ilravenll:BAABLgAFFH8IAAIaAAQJPg33EwApAQAaAAQJPg33EwApAQAAAA==.Ilyana:BAACLgAFFH8ZAAIEAAcJnxkcBwAxAgAEAAcJnxkcBwAxAgAuAAQKfz8AAgQACQk2JqIBAHkDAAQACQk2JqIBAHkDAAAA.',
Im='Impavido:BAAALgAECgYJBgAAAA==.',
In='Inholy:BAAALgAECgYJDQAAAA==.Insights:BAAALgADCgMJAwAAAA==.',
Is='Isabella:BAAALgAECgEJAQABLgAFFAQJBwAFALcRAA==.',
It='Ithopel:BAABLgAECn8jAAIIAAYJASF6KAASAgAIAAYJASF6KAASAgAAAA==.',
Ja='Jalista:BAAALgADCgMJAwAAAA==.Jayc:BAACLgAFFH8NAAIEAAQJ5B3nJwBmAQAEAAQJ5B3nJwBmAQAuAAQKfx0AAgQACAlgHid0AOoBAAQACAlgHid0AOoBAAAA.',
Je='Jereico:BAACLgAFFH8hAAIYAAgJlSLrAACQAgAYAAgJlSLrAACQAgAuAAQKfzkAAhgACQnlJiUAAJUDABgACQnlJiUAAJUDAAAA.Jeryhn:BAACLgAFFH8dAAIUAAgJlBJEAgDZAQAUAAgJlBJEAgDZAQAuAAQKfz8AAhQACQk8GhYTAHoCABQACQk8GhYTAHoCAAAA.',
Jo='Joeburrow:BAAALgAECgIJAgAAAA==.Joeynodz:BAAALgADCgYJEgAAAA==.Jortshorts:BAABLgAECn8kAAIlAAgJTwj7EwAbAQAlAAgJTwj7EwAbAQAAAA==.',
Jr='Jray:BAABLgAECn8VAAIOAAYJGRnOZAC3AQAOAAYJGRnOZAC3AQAAAA==.',
Ju='Juggalo:BAABLgAECn8pAAMNAAkJQiAHAQDZAgANAAkJCSAHAQDZAgAYAAIJiRIbZgBJAAAAAA==.June:BAACLgAFFH8eAAIVAAcJmxmxAQAaAgAVAAcJmxmxAQAaAgAuAAQKfz8AAxUACQlsIbMEAB0DABUACQlsIbMEAB0DACIACQkGHygFAMUCAAAA.Juuju:BAAALgAECgUJCQAAAA==.',
Ka='Kaldriss:BAAALgAECgEJAQAAAA==.Kalen:BAAALgADCgEJAgAAAA==.Katashimus:BAAALgAECgYJCwAAAA==.Kawasuoo:BAABLgAECn8bAAMIAAYJVR9vHgAMAgAIAAYJVR9vHgAMAgAmAAUJEw1lKACSAAAAAA==.Kaze:BAAALgAECgYJCgAAAA==.',
Kh='Khaotichic:BAAALgAECgUJEAAAAA==.Khrenak:BAAALgAECgQJCgAAAA==.',
Ki='Kickpunch:BAAALgAECgYJCQAAAA==.Kirah:BAACLgAFFH8HAAIYAAIJmByAMAC1AAAYAAIJmByAMAC1AAAuAAQKfyAAAhgACQmwIWoEAEoDABgACQmwIWoEAEoDAAEuAAUUBAkHAAUAtxEA.',
Ko='Koddin:BAABLgAECn8zAAIOAAkJ6h7LFACKAgAOAAkJ6h7LFACKAgAAAA==.Korenchkin:BAAALgAECgEJAgAAAA==.Koreth:BAACLgAFFH8aAAMaAAYJLCEMAwDrAQAaAAUJLCEMAwDrAQARAAEJAACyBwA5AAAuAAQKf0UAAxoACQkmJuwAAFMDABoACQkmJuwAAFMDABEACAmWGg8EAHcCAAAA.Kornholyo:BAAALgAECgEJAQAAAA==.',
Kr='Kragoth:BAAALgADCgIJAgAAAA==.',
Ku='Kutuzov:BAAALgAECgUJEQAAAA==.',
Kw='Kwaiza:BAAALgAECgYJDwAAAA==.',
['Ká']='Káel:BAAALgAECgMJAwAAAA==.',
La='Lailaysia:BAAALgAECgcJDQAAAA==.Lamemoosaur:BAAALgADCgIJAgABLgAECgYJCgAGAAAAAA==.Laríca:BAACLgAFFH8MAAIUAAQJmSagCADFAQAUAAQJmSagCADFAQAuAAQKfysAAhQACQmYJPkBAGcDABQACQmYJPkBAGcDAAAA.Laustin:BAABLgAECn8gAAQQAAgJpBrbDAAXAgAQAAgJfBrbDAAXAgAnAAYJEhBSFQCwAAAFAAIJbwXSvQBYAAAAAA==.Laydout:BAAALgAECgcJBQABLgAECgkJGQAFALYhAA==.Laydoutyota:BAABLgAECn8ZAAIFAAkJtiEZGQByAgAFAAkJtiEZGQByAgAAAA==.',
Le='Leag:BAABLgAECn8YAAMSAAcJFw+MQACiAQASAAcJFw+MQACiAQAeAAEJJAmvPwA5AAAAAA==.Lemonruss:BAAALgADCgQJBAAAAA==.',
Li='Liaria:BAAALgAECgEJAQAAAA==.Lilea:BAACLgAFFH8GAAIFAAMJiha9MgD2AAAFAAMJiha9MgD2AAAuAAQKfzUAAwUACQnFH14JAM4CAAUACQnFH14JAM4CACcABwnhEfc0AJYBAAAA.Lithium:BAAALgADCgUJBQAAAA==.Littledeb:BAAALgAFFAEJAQAAAA==.',
Lo='Lockdots:BAAALgADCgEJAQAAAA==.Lolchaosbolt:BAAALgADCgYJBgAAAA==.Lortherian:BAAALgAECgYJDwAAAA==.Lowbo:BAAALgADCgUJBQAAAA==.Lowelfesteem:BAAALgADCgUJBQAAAA==.',
Lu='Lucille:BAABLgAECn8ZAAIEAAYJ3geQqgDwAAAEAAYJ3geQqgDwAAAAAA==.',
Ly='Lyndira:BAAALgAECgUJBQAAAA==.',
['Lä']='Läwlbringer:BAAALgAECggJDQAAAA==.',
['Lî']='Lîghtt:BAAALgADCgQJBAAAAA==.',
Ma='Mabritos:BAAALgAECgQJBQABLgAFFAYJGgAnAJ8eAA==.Maccabee:BAAALgAECgEJAQAAAA==.Mania:BAAALgADCgYJBgABLgAECgkJHgASAKMdAA==.Mathath:BAACLgAFFH8GAAIJAAMJTww4cQCTAAAJAAMJTww4cQCTAAAuAAQKfxwAAwkACAn3F3Y6ANIBAAkACAnGF3Y6ANIBAAoABAlUFacoAPkAAAAA.Mathmath:BAAALgAECgUJCQABLgAECgcJIAADAM8eAA==.Mathoras:BAABLgAECn8WAAIBAAcJaRWYUgBnAQABAAcJaRWYUgBnAQAAAA==.',
Me='Meandean:BAAALgAECgIJBgAAAA==.Meatier:BAAALgAECgEJAQABLgAECgkJHgASAKMdAA==.Meatless:BAAALgADCgcJDQAAAA==.',
Mi='Micmac:BAAALgAECgQJCQAAAA==.Miltonroe:BAABLgAECn8gAAIHAAgJfg4mDgBfAQAHAAgJfg4mDgBfAQAAAA==.Mirithul:BAAALgADCgYJBwAAAA==.Mischiëf:BAAALgAECgYJCwAAAA==.Mitsuri:BAABLgAECn8iAAIEAAgJoQrekgCtAQAEAAgJoQrekgCtAQAAAA==.',
Mo='Modr:BAAALgAECgkJEAAAAA==.Monkynate:BAAALgAECgYJCgAAAA==.Monsterskill:BAABLgAECn8hAAQTAAgJzhgeEAAsAQATAAYJxBYeEAAsAQABAAUJdBkdcQAeAQACAAUJhhNULQAIAQAAAA==.Moonerva:BAABLgAECn8fAAIoAAgJgAxHJgBBAQAoAAgJgAxHJgBBAQAAAA==.Morpheos:BAAALgADCgQJBAAAAA==.Mortgage:BAAALgADCgUJBQAAAA==.',
Mu='Mutsu:BAAALgADCgcJBwAAAA==.',
Mv='Mvqchx:BAAALgAECgMJBQAAAA==.',
Na='Naturelass:BAAALgADCgUJBQAAAA==.Nausicaa:BAAALgADCgYJCQAAAA==.Nawwll:BAAALgADCgMJAwAAAA==.',
Ne='Neotama:BAAALgAECggJEgAAAA==.Nethis:BAABLgAECn8jAAIgAAYJ9BySHQCEAQAgAAYJ9BySHQCEAQAAAA==.',
Ni='Niatpacgrom:BAABLgAECn8fAAIHAAkJfBjPBABQAgAHAAkJfBjPBABQAgAAAA==.Nivla:BAAALgADCgMJAwAAAA==.',
No='Nobacon:BAAALgAECgMJBQAAAA==.Norah:BAAALgAECgEJAQAAAA==.Norvis:BAAALgAECgQJBQAAAA==.Notdragon:BAAALgAECgQJEQAAAA==.',
Nu='Nukeddukem:BAAALgAECgYJEgAAAA==.',
Nv='Nv:BAAALgAECggJEwAAAA==.',
Ny='Nymrod:BAABLgAECn8sAAMBAAkJRhSVJgAHAgABAAkJRhSVJgAHAgACAAIJpgduZQBEAAAAAA==.',
['Ní']='Nír:BAAALgAECgQJBAAAAA==.',
Oj='Ojou:BAAALgADCgMJAwABLgAFFAMJAwAGAAAAAA==.',
Om='Omizzig:BAAALgAECgUJCwAAAA==.',
On='Onepunch:BAAALgAECgQJBgAAAA==.',
Or='Orcman:BAAALgADCgIJAgABLgADCgcJBwAGAAAAAA==.Orloran:BAAALgADCgIJAgAAAA==.',
Pa='Palthur:BAAALgAECgUJCAAAAA==.Parria:BAAALgAECgYJEAABLgAECgcJDQAGAAAAAA==.Pasqualino:BAAALgAECgYJCgAAAA==.Passionate:BAACLgAFFH8JAAIjAAMJZQ2mFwC5AAAjAAMJZQ2mFwC5AAAuAAQKfyYAAiMACAmfFFYVAPUBACMACAmfFFYVAPUBAAAA.',
Pe='Peepis:BAAALgADCgEJAQABLgAECgkJHgASAKMdAA==.Pennance:BAABLgAECn8iAAIUAAkJ/huZDgCiAgAUAAkJ/huZDgCiAgAAAA==.',
Ph='Phatmidas:BAABLgAECn8lAAIOAAgJtBeyUACPAQAOAAgJtBeyUACPAQAAAA==.',
Pl='Plagueground:BAACLgAFFH8PAAIJAAYJtx7BAwDqAQAJAAYJtx7BAwDqAQAuAAQKf0IAAgkACQnfJt4AAIIDAAkACQnfJt4AAIIDAAAA.Plutonyus:BAAALgAECgEJAQAAAA==.',
Po='Poc:BAABLgAECn8YAAIEAAYJPB3wdADoAQAEAAYJPB3wdADoAQAAAA==.Pockets:BAAALgAECgMJBwAAAA==.Potatopotato:BAACLgAFFH8GAAIaAAIJYhW8IACgAAAaAAIJYhW8IACgAAAuAAQKfyIAAhoACQknFSUcAB4CABoACQknFSUcAB4CAAAA.Pounces:BAAALgAECgYJEgABLgAECgcJGAAYAKgXAA==.Powerfistin:BAAALgADCgcJBwAAAA==.',
Pr='Prosecutor:BAAALgAECgUJDAAAAA==.Prynts:BAABLgAECn8VAAIOAAcJZh3sRAAVAgAOAAcJZh3sRAAVAgAAAA==.Prøzak:BAAALgAFFAIJAgAAAA==.',
Pu='Puetrid:BAAALgADCgYJBgABLgAECgQJBAAGAAAAAA==.',
Ra='Raanky:BAAALgAECgEJAQAAAA==.Radiantlight:BAAALgAECgEJAQAAAA==.Randomly:BAAALgADCgkJJQAAAA==.Raspberries:BAAALgAECgcJBwAAAA==.Rautha:BAAALgAECgkJEgAAAA==.Rayl:BAAALgAECgYJDwAAAA==.Razsputin:BAAALgAECgMJBwAAAA==.',
Re='Rekless:BAAALgADCgUJBQAAAA==.Rethgar:BAAALgAECgUJEgAAAA==.',
Rh='Rhaegosa:BAABLgAECn8tAAQYAAkJ7xcWHgDUAQAYAAcJVBgWHgDUAQANAAQJrg16EQCsAAAjAAIJfhEqIwCKAAAAAA==.Rhavik:BAAALgADCgQJBAAAAA==.Rhekt:BAAALgAECgIJBQAAAA==.Rhokladar:BAAALgAECgQJCQAAAA==.',
Ri='Ridcully:BAABLgAECn8bAAIIAAgJmBdPLQCrAQAIAAgJmBdPLQCrAQAAAA==.Rimath:BAAALgAECgcJBAAAAA==.Rinswind:BAAALgADCgMJAwAAAA==.',
Ro='Robopacman:BAACLgAFFH8OAAIJAAQJvyBUHgAgAQAJAAQJvyBUHgAgAQAuAAQKfy8AAgkACQnyJBgPACMDAAkACQnyJBgPACMDAAAA.Rodstewart:BAACLgAFFH8ZAAMFAAgJWBgHAwDlAQAFAAUJXRwHAwDlAQAnAAUJUgzvFAD2AAAuAAQKfyUAAwUACQmUJE0WAIYCAAUACAluJE0WAIYCACcABwnNHxomAPgBAAAA.Roofeo:BAABLgAECn8VAAQCAAcJFhRZFgC6AAATAAQJgBCEEQDYAAABAAQJUwstnQDFAAACAAQJzxVZFgC6AAAAAA==.Rotdaddy:BAABLgAECn8XAAIJAAgJKgPclgDxAAAJAAgJKgPclgDxAAAAAA==.',
Ry='Ryoshin:BAAALgADCgEJAQABLgAECgYJDQAGAAAAAA==.Ryzze:BAAALgADCgYJCQAAAA==.',
['Rï']='Rïn:BAAALgADCgEJAQAAAA==.',
Sa='Salas:BAABLgAECn8UAAIBAAcJzgyFawAqAQABAAcJzgyFawAqAQAAAA==.Salino:BAAALgAECgUJBQAAAA==.Salinoster:BAAALgADCgEJAQAAAA==.Salordell:BAAALgADCgIJAwAAAA==.Sam:BAAALgADCgEJAQAAAA==.Sarate:BAABLgAECn8kAAIgAAgJiQ5QIQBoAQAgAAgJiQ5QIQBoAQAAAA==.Savannah:BAABLgAFFH8HAAIFAAQJtxG5IAA3AQAFAAQJtxG5IAA3AQAAAA==.Savvtwo:BAAALgADCgcJBwABLgAFFAcJHAADACUkAQ==.',
Sc='Scathach:BAABLgAECn8gAAMDAAcJzx61LADNAQADAAcJzx61LADNAQAkAAQJURguRADmAAAAAA==.Scorandom:BAAALgAECgEJAQAAAA==.',
Se='Seven:BAAALgAECgIJAgAAAA==.Sezra:BAAALgADCgkJAQAAAA==.',
Sh='Shamalam:BAAALgADCgEJAQAAAA==.Shei:BAAALgAECgIJAgAAAA==.Sheidon:BAAALgAECgQJBAAAAA==.Shinanigans:BAAALgAECgYJDgAAAA==.Shruikan:BAAALgADCggJDAAAAA==.',
Si='Silverslam:BAAALgAECgEJAQABLgAECggJFwAHABURAA==.Sinatra:BAAALgAECgIJBAABLgAECgYJCgAGAAAAAA==.Siqodel:BAAALgADCgYJCAAAAA==.',
Sk='Skurge:BAAALgAECgYJDwAAAA==.',
Sl='Slamb:BAAALgAECgYJBwAAAA==.Slimetongue:BAAALgADCgMJAwAAAA==.',
Sm='Smaaug:BAAALgAECgEJAQAAAA==.',
Sn='Snuggle:BAAALgAECgEJAQAAAA==.',
So='Solstis:BAAALgAECggJDgAAAA==.Sorzsnipe:BAAALgADCgQJBAAAAA==.',
Sp='Spellchücker:BAAALgAECgcJDQAAAA==.Spfzero:BAAALgAECgEJAQAAAA==.',
St='Staggered:BAACLgAFFH8PAAIPAAQJoh56DgBZAQAPAAQJoh56DgBZAQAuAAQKfyUAAw8ACAkOIusLAM8CAA8ACAkOIusLAM8CACIAAQk1A9WMABwAAAAA.Stoneojinray:BAAALgADCgEJAQAAAA==.Stoneorcman:BAAALgADCgcJBwAAAA==.Stormriderr:BAAALgAECgYJCQAAAA==.',
Su='Subdofu:BAAALgADCgQJBAABLgAECgcJFwAaAN0cAA==.Subtox:BAABLgAECn8XAAMaAAcJ3RxNIQDvAQAaAAcJ3RxNIQDvAQARAAEJkgu5HwA0AAAAAA==.',
Sw='Sweetcool:BAAALgAECgUJCQABLgAECggJLQAFAN4hAA==.',
Sy='Syphilistjt:BAABLgAECn8WAAIhAAgJ0xLIFwDgAQAhAAgJ0xLIFwDgAQAAAA==.Syphillis:BAAALgAECgYJCgAAAA==.',
['Sá']='Sálud:BAACLgAFFH8KAAIoAAQJmhmzGwDxAAAoAAQJmhmzGwDxAAAuAAQKfyIAAygACAmSH4APAKkCACgABwlcIYAPAKkCACYABwmhGfsMAKkBAAAA.',
['Sê']='Sêp:BAAALgAECgcJCgAAAA==.',
Ta='Tanissaria:BAAALgADCgEJAQAAAA==.Taranith:BAAALgAECgUJBQABLgAECggJFgAEAPYTAA==.Tarhealeon:BAABLgAECn9DAAMUAAkJqxqWIQARAgAUAAkJqxqWIQARAgAOAAgJ1xAeSgChAQAAAA==.Tarmander:BAAALgAECgYJDgAAAA==.Taylörshift:BAAALgAECgQJBwAAAA==.',
Te='Telahnicus:BAAALgADCgEJAQAAAA==.Terranox:BAAALgADCgMJAwAAAA==.Testostauren:BAAALgAECgMJBgAAAA==.',
Th='Thabigone:BAAALgAECgYJDAAAAA==.Thalnaria:BAAALgAECgYJCwAAAA==.Threebuttons:BAAALgAECgUJDgABLgAFFAMJCwAjAFwHAA==.Thunderkis:BAAALgAECgYJEAAAAA==.',
Ti='Tiewaz:BAAALgAECgYJBgABLgAECggJHgAEAFoPAA==.Tiewiz:BAABLgAECn8eAAMEAAgJWg8QagBqAQAEAAgJEQwQagBqAQApAAUJlw16CQCvAAAAAA==.',
To='Tointjoker:BAAALgAECgMJBAAAAA==.Tolun:BAABLgAECn89AAIEAAkJtxt6FQCiAgAEAAkJtxt6FQCiAgAAAA==.Tosan:BAAALgADCggJDgAAAA==.',
Tr='Treeplague:BAABLgAECn8xAAMgAAkJ/gz8GgCbAQAgAAkJ/gz8GgCbAQAhAAYJnxSdHQCHAQAAAA==.Trypleg:BAAALgAECgMJAwAAAA==.',
Tu='Tungie:BAABLgAECn8bAAIJAAgJ0iDCKwALAgAJAAgJ0iDCKwALAgAAAA==.Turn:BAACLgAFFH8gAAQBAAgJoBXICgDHAQABAAYJnhrICgDHAQACAAUJvg2+AwBcAQATAAIJmSCqCQBjAAAuAAQKfzoABAEACQn2JL8UANkCAAEACAkbJL8UANkCABMAAwlJJkoRANsAAAIAAwlXJC0UAMoAAAAA.Turtleduck:BAABLgAECn8ZAAINAAYJ9RoyBwCIAQANAAYJ9RoyBwCIAQAAAA==.Tuskbreaker:BAAALgAECgIJAgAAAA==.',
Tw='Twittytister:BAAALgADCgQJBAAAAA==.Twostrokes:BAAALgAECgEJAQAAAA==.',
Ty='Tyrese:BAAALgADCggJEAAAAA==.',
Uf='Uffin:BAAALgAECgQJBQAAAA==.',
Um='Umbryx:BAAALgAECgYJCQAAAA==.',
Un='Unagi:BAAALgAECggJEQAAAA==.Unholy:BAAALgADCgIJAgAAAA==.',
Va='Valdi:BAABLgAECn8WAAIOAAcJkwxJgQAjAQAOAAcJkwxJgQAjAQAAAA==.',
Ve='Velthera:BAABLgAECn8XAAIjAAgJCyJEBAAQAwAjAAgJCyJEBAAQAwABLgAFFAQJBwAVAKMTAA==.Venomlight:BAAALgADCgIJAgAAAA==.Venomstrikes:BAAALgAECgYJEAAAAA==.Venratzi:BAAALgAECgQJBAAAAA==.Vespertina:BAAALgADCgYJBgAAAA==.',
Vo='Voridor:BAAALgADCgEJAQAAAA==.Voulk:BAAALgAFFAMJAwABLgAFFAgJIAAjABIbAA==.',
Vy='Vyllan:BAABLgAECn8UAAQTAAgJ8AQCEwD8AAATAAYJKwQCEwD8AAABAAgJGgRUgwD3AAACAAMJmgEhMgArAAAAAA==.',
Wa='Waldgeist:BAAALgAECgUJBQABLgAECgkJHgASAKMdAA==.Walthur:BAAALgADCgkJDQAAAA==.Waobby:BAAALgADCgIJAgAAAA==.Warrpigg:BAAALgAECgEJAQAAAA==.Waterdrinker:BAAALgAECgIJAgAAAA==.Wavybone:BAAALgAECgEJAgAAAA==.',
Wh='Whiisper:BAAALgADCgMJAwAAAA==.Whoarlock:BAAALgADCgUJCAAAAA==.',
Wo='Wo:BAAALgADCgMJAwAAAA==.',
Wu='Wutangstyle:BAAALgAECgIJAgABLgAECgkJHgASAKMdAA==.',
Wy='Wyatta:BAAALgADCgIJAgAAAA==.',
Xe='Xelinia:BAACLgAFFH8QAAIgAAUJoxJJEQArAQAgAAUJoxJJEQArAQAuAAQKfyEAAiAACQk1H20MALwCACAACQk1H20MALwCAAAA.Xen:BAAALgAFFAQJBAAAAA==.',
Xf='Xfortune:BAAALgADCgcJCQAAAA==.',
Xh='Xholycritz:BAAALgAECgMJAwAAAA==.',
Xu='Xuefeng:BAACLgAFFH8QAAIiAAQJjhYmCQBBAQAiAAQJjhYmCQBBAQAuAAQKfzcAAiIACQl7IN4DAOgCACIACQl7IN4DAOgCAAAA.',
Ye='Yenchmeister:BAACLgAFFH8cAAMSAAcJkxxEAwDDAQASAAUJuRxEAwDDAQAeAAYJ3RoAAgBiAQAuAAQKfygAAxIACQkgJdcJABEDABIACQkgJdcJABEDAB4AAgl3ICEoAK4AAAAA.',
Yo='Youngbusta:BAABLgAECn8uAAIEAAkJ0iIfEADHAgAEAAkJ0iIfEADHAgAAAA==.',
Yu='Yuta:BAAALgAECgYJDQAAAA==.',
Za='Zad:BAAALgADCgIJAgAAAA==.',
Ze='Zenrac:BAAALgADCgUJBQAAAA==.Zeromus:BAAALgAECgIJAgAAAA==.',
Zi='Zilvanic:BAACLgAFFH8HAAIXAAMJYwdcCQCNAAAXAAMJYwdcCQCNAAAuAAQKfyQABBcACAlgEoIPAHUBABcACAn0EYIPAHUBAA4ABQlZEJKsANgAABQAAwl8AQiDAGwAAAAA.Zilvanion:BAAALgAECgYJCQAAAA==.',
Zo='Zourknight:BAAALgADCgcJEAAAAA==.Zourlight:BAAALgADCgUJBgAAAA==.Zourlock:BAAALgAECgYJEwAAAA==.Zourpatch:BAAALgADCgMJAwAAAA==.',
Zu='Zulvaz:BAAALgAECgIJAwAAAA==.Zurey:BAABLgAECn88AAIDAAkJVQ0UQgB2AQADAAkJVQ0UQgB2AQAAAA==.',
Zy='Zynjamin:BAACLgAFFH8XAAMNAAcJ4iA9AAADAgANAAYJ6yM9AAADAgAYAAEJtBGFPwBdAAAuAAQKfy4AAg0ACQkLJC8AANsDAA0ACQkLJC8AANsDAAAA.',
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
