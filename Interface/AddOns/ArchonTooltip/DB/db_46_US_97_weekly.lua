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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Elemental','Shaman-Restoration','Priest-Holy','Paladin-Retribution','Rogue-Subtlety','Druid-Balance','Rogue-Assassination','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','DeathKnight-Unholy','Warrior-Fury','Hunter-Survival','Mage-Frost','Monk-Brewmaster','Priest-Shadow','DeathKnight-Blood','Monk-Mistweaver','Monk-Windwalker','Warlock-Affliction','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Druid-Guardian','Paladin-Holy','Paladin-Protection','Druid-Feral','Druid-Restoration','Mage-Arcane','Shaman-Enhancement','DemonHunter-Vengeance','Priest-Discipline','Rogue-Outlaw','DeathKnight-Frost','Warrior-Protection','Warrior-Arms',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abandonhope:BAAALgAECgMJAwABLgAECgMJBAABAAAAAA==.',
Ac='Accuser:BAAALgADCgEJAQAAAA==.Acky:BAAALgADCgUJBQAAAA==.',
Ad='Adwen:BAAALgAECgUJEgAAAA==.',
Ae='Aenimal:BAAALgADCggJCAABLgADCgkJDgABAAAAAA==.Aer:BAAALgADCgkJCQAAAA==.Aeronemon:BAAALgAECgEJAgAAAA==.',
Ai='Airill:BAAALgADCgQJBQAAAA==.',
Ak='Akforty:BAABLgAECn8fAAMCAAkJIiHNCgDvAgACAAkJIiHNCgDvAgADAAIJoBV7eABfAAAAAA==.Akittymeow:BAABLgAECn8bAAMEAAkJuw9AMQAfAQAEAAgJKQ9AMQAfAQAFAAMJigVGeQB2AAAAAA==.',
Al='Aldredevon:BAAALgAECgEJAQAAAA==.Aleshock:BAAALgAECgcJDAAAAA==.Alidar:BAAALgAECgcJEwAAAA==.Alphaboner:BAAALgADCgYJBwAAAA==.Altairis:BAAALgAECgEJAgAAAA==.Altartoy:BAABLgAECn8dAAIGAAgJ6Aq3JwA/AQAGAAgJ6Aq3JwA/AQAAAA==.Althunter:BAACLgAFFH8JAAIDAAMJUhutDQAMAQADAAMJUhutDQAMAQAuAAQKfxsAAgMACAneIewDAEACAAMACAneIewDAEACAAAA.',
Am='Amelina:BAAALgAECgUJCQAAAA==.Amorir:BAABLgAECn83AAIHAAkJ+RGbPgDCAQAHAAkJ+RGbPgDCAQAAAA==.Amorit:BAAALgADCgkJCgAAAA==.Amorydalias:BAAALgAECgUJBgAAAA==.Amozon:BAAALgADCgEJAQAAAA==.',
An='Anamortem:BAAALgAECgMJAwABLgAECgkJIQAIAAcZAA==.Anastala:BAABLgAECn8mAAIJAAgJ8RX1FgC/AQAJAAgJ8RX1FgC/AQAAAA==.Angchu:BAAALgADCgQJBAAAAA==.Angelmàker:BAAALgAECgMJBAABLgADCgcJEwABAAAAAA==.Annesta:BAABLgAECn8hAAMIAAkJBxmyDgDvAQAIAAkJ0hiyDgDvAQAKAAEJ9xaFHABAAAAAAA==.',
Ap='Apostus:BAAALgADCgcJDgAAAA==.Apothica:BAAALgAECgUJBgAAAA==.',
Aq='Aquafox:BAABLgAECn8XAAMFAAYJJiLEFwA3AgAFAAYJJiLEFwA3AgAEAAMJYxA0UgCWAAAAAA==.',
Ar='Archontas:BAABLgAECn8bAAIJAAYJmyAQFwC9AQAJAAYJmyAQFwC9AQAAAA==.Ariodh:BAABLgAECn8uAAMLAAkJKiY0AQBmAwALAAkJKiY0AQBmAwAMAAUJpB9eJACaAQAAAA==.Arkaline:BAAALgAECgEJAQAAAA==.Artuarry:BAACLgAFFH8VAAINAAUJnw7DOAAdAQANAAUJnw7DOAAdAQAuAAQKfyYAAg0ACQlCH1oSAIICAA0ACQlCH1oSAIICAAAA.Aryndus:BAABLgAECn8VAAIHAAkJrxzuFwB0AgAHAAkJrxzuFwB0AgAAAA==.',
At='Athenà:BAAALgAECgQJBAAAAA==.',
Av='Avocado:BAABLgAECn8jAAMCAAkJnCUkBQAKAwACAAkJHSMkBQAKAwADAAcJQiJMBwDLAQAAAA==.',
Ax='Axelaw:BAAALgADCgQJBAAAAA==.',
Ay='Ayrz:BAAALgAECgIJAgAAAA==.',
Az='Azaria:BAAALgADCgIJAgAAAA==.',
Ba='Baddjujumon:BAAALgAECggJDwAAAA==.Baileyhowl:BAAALgAECgEJBAAAAA==.Bammie:BAAALgADCgYJCgAAAA==.Bananuth:BAAALgAECgIJAwABLgAFFAUJFAAOAEAcAA==.Banthr:BAABLgAECn8UAAIPAAkJDw4FHwCnAQAPAAkJDw4FHwCnAQAAAA==.Barkert:BAAALgADCgEJAQAAAA==.Baroke:BAAALgAECgMJBwABLgAECggJHQAGAOgKAA==.Barokoshama:BAAALgAECgcJEQAAAA==.Basaltytaco:BAAALgADCgEJAQAAAA==.Battleworm:BAAALgADCgkJEwABLgAFFAMJAwABAAAAAA==.',
Bb='Bbalrd:BAABLgAECn8XAAIOAAkJoRe0MwDpAQAOAAkJoRe0MwDpAQAAAA==.',
Be='Bearglie:BAAALgAECgYJBgAAAA==.Beepers:BAAALgAECgYJBgAAAA==.',
Bi='Bigcow:BAAALgAECgUJCQAAAA==.',
Bl='Blackolives:BAAALgAECgcJDAAAAA==.Blondefu:BAAALgAECgUJCwAAAA==.Bloodybonne:BAAALgADCgcJBwAAAA==.Bloodyell:BAAALgAECgEJAQAAAA==.Bloore:BAAALgAECgMJAwABLgAECggJIwADAO4hAA==.Bluejuly:BAAALgAECgQJBAAAAA==.Blutø:BAAALgAECgQJBgAAAA==.',
Bo='Boflex:BAAALgADCgQJBQAAAA==.Bomboclat:BAAALgAECgUJCwAAAA==.Bonesknows:BAAALgADCgEJAQAAAA==.Boofy:BAAALgAECgMJAwABLgAECgkJFgANANwWAA==.Bowwie:BAACLgAFFH8OAAMQAAQJEBKMFADtAAAQAAMJMw6MFADtAAACAAMJZRDOOwDXAAAuAAQKfysABAIACQmPHy0GACsDAAIACQkTHi0GACsDABAACAkQGMANAAkCAAMAAQkVAxWTACcAAAAA.',
Br='Britney:BAAALgADCgkJCQAAAA==.Bronzé:BAABLgAECn8tAAIRAAYJyCImOQDzAQARAAYJyCImOQDzAQAAAA==.Brotherfrey:BAAALgAECgYJCgAAAA==.Bruish:BAABLgAFFH8MAAISAAQJtwzFDQAWAQASAAQJtwzFDQAWAQAAAA==.',
Bu='Bubbadoo:BAABLgAECn8gAAIJAAgJbQ8+IQBiAQAJAAgJbQ8+IQBiAQAAAA==.Buddy:BAABLgAECn8UAAITAAYJXA00MAAJAQATAAYJXA00MAAJAQABLgAECgYJHgAUAOEiAA==.Bulan:BAABLgAECn81AAIVAAgJRiVTAwBBAwAVAAgJRiVTAwBBAwAAAA==.',
Bw='Bweninger:BAAALgADCgcJBwAAAA==.',
['Bô']='Bôôsted:BAABLgAECn8XAAIEAAkJ0BTfIAAIAgAEAAkJ0BTfIAAIAgAAAA==.',
Ca='Caistan:BAAALgADCgYJCAAAAA==.Candypants:BAABLgAECn8bAAQVAAgJgBa2FwDmAQAVAAgJgBa2FwDmAQAWAAMJ2AvrSACQAAASAAIJBg16dAAzAAAAAA==.Caoth:BAAALgAECgYJEwAAAA==.Cappilon:BAAALgAECggJEQAAAA==.Carcus:BAAALgAECgEJAQAAAA==.Cayleedah:BAABLgAECn8mAAIDAAgJwweeDwAYAQADAAgJwweeDwAYAQAAAA==.Cayssaris:BAAALgAECgUJEAAAAA==.',
Cc='Cc:BAABLgAECn8WAAQXAAYJPBPsDgBCAQAXAAUJ9BPsDgBCAQAYAAYJKwstIwA+AQANAAQJzhP5tQDtAAAAAA==.',
Ce='Ceeti:BAABLgAECn84AAMZAAkJHSFKBQDYAgAZAAkJHSFKBQDYAgAaAAIJeAYcQABpAAAAAA==.Celandrelia:BAAALgAECgUJBQABLgAECggJKwAbAF8WAA==.',
Ch='Chaewon:BAAALgAECgYJCgABLgAFFAQJEQAGADMkAA==.Channeria:BAAALgAECgEJAQAAAA==.Chaoticoreo:BAABLgAECn8xAAMMAAkJOh7qBACsAgAMAAkJOh7qBACsAgALAAQJ4w9rrQCzAAAAAA==.Chappedlips:BAAALgAECgkJBwAAAA==.Chareyne:BAABLgAECn8ZAAIGAAgJ5RFyJgC5AQAGAAgJ5RFyJgC5AQAAAA==.Cheetor:BAAALgAECgMJAwABLgAECgkJPAAQADIkAA==.Cheezytaco:BAAALgAECgYJDgABLgAECgkJIwAHANccAA==.Chidge:BAAALgADCggJCwAAAA==.Chikila:BAABLgAECn8bAAMYAAcJyxkDBgCxAQAYAAcJyxkDBgCxAQANAAEJdQZYCwEsAAAAAA==.Chilliflakez:BAAALgAECgUJEwAAAA==.Chro:BAAALgAECgcJBwABLgAECggJJgAEABYeAA==.',
Ci='Cindezar:BAAALgADCgMJAwAAAA==.',
Cl='Clementyn:BAABLgAECn8WAAIHAAcJOBBDiwAPAQAHAAcJOBBDiwAPAQAAAA==.Cleyi:BAABLgAECn8pAAIGAAgJxQ3hIgBjAQAGAAgJxQ3hIgBjAQAAAA==.',
Co='Coldpasta:BAAALgAECgYJDgABLgAFFAIJBAABAAAAAA==.Colonoscopy:BAAALgAECgEJAQAAAA==.Coreyy:BAAALgADCgUJBwAAAA==.Corva:BAACLgAFFH8LAAINAAMJ7w60UQDbAAANAAMJ7w60UQDbAAAuAAQKfyoAAg0ACQnpFaQsAOgBAA0ACQnpFaQsAOgBAAAA.Cosairi:BAAALgAECgQJBAAAAA==.Cougztroll:BAABLgAECn8pAAIcAAkJBBVRDACxAQAcAAkJBBVRDACxAQAAAA==.',
Cr='Crazaki:BAAALgADCgEJAQAAAA==.',
Cu='Curfluffin:BAAALgADCgEJAQAAAA==.Cuttercupx:BAAALgAECgEJAQABLgAECgMJBAABAAAAAA==.',
Da='Dahn:BAAALgAECgIJAgAAAA==.Dakadin:BAABLgAECn8mAAMdAAkJ+yNLCwCQAgAdAAkJ+yNLCwCQAgAHAAQJ7hebmgD0AAAAAA==.Daranne:BAACLgAFFH8KAAIHAAMJmxWTOAD9AAAHAAMJmxWTOAD9AAAuAAQKfyUAAgcACAkhHBc/ACkCAAcACAkhHBc/ACkCAAAA.Darkenedstar:BAAALgADCgkJDgAAAA==.Darksoulstwo:BAAALgADCgMJAwAAAA==.Dasbeans:BAAALgAFFAIJAwAAAA==.Dashy:BAAALgAECggJEQAAAA==.Datran:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.',
De='Deaduglie:BAABLgAECn8xAAMNAAkJchXwJwD+AQANAAkJchXwJwD+AQAYAAEJMQjvcQA0AAAAAA==.Deliandora:BAAALgAECgQJBwAAAA==.Delusional:BAAALgAECgcJDQAAAA==.Delynique:BAAALgADCgEJAQABLgAECggJIwADAO4hAA==.Demonx:BAAALgAECgEJAQAAAA==.Denaric:BAAALgAECgUJDgAAAA==.Destroyevsky:BAABLgAECn8VAAIPAAUJxgEMagBUAAAPAAUJxgEMagBUAAAAAA==.Detonate:BAABLgAECn8XAAIRAAYJbhxzWACSAQARAAYJbhxzWACSAQAAAA==.',
Dh='Dhvecx:BAAALgAECgUJBgABLgAECgYJDQABAAAAAA==.',
Di='Dilbo:BAAALgAECgEJAgAAAA==.Diomed:BAAALgAECgEJAQAAAA==.Diqon:BAABLgAECn84AAMOAAkJDRuuIABBAgAOAAkJDRuuIABBAgAUAAcJthQNFwBWAQAAAA==.Disturbedtwo:BAAALgAECgYJCgAAAA==.',
Do='Dolphinz:BAACLgAFFH8PAAIHAAQJ0RT7GQBXAQAHAAQJ0RT7GQBXAQAuAAQKfy4AAwcACAmoIVgVAIUCAAcACAmoIVgVAIUCAB4AAgnpCiI8AE4AAAAA.Doryadni:BAAALgADCgcJBgAAAA==.',
Dr='Dragonpede:BAABLgAECn85AAIZAAkJFSBMBgDAAgAZAAkJFSBMBgDAAgAAAA==.Dragonwarior:BAABLgAECn8fAAIPAAkJ6hvgHAC4AQAPAAkJ6hvgHAC4AQAAAA==.Drakindees:BAAALgAECgQJBAABLgAECgcJJAARAPUhAA==.Drakkyn:BAABLgAECn8UAAIPAAYJpxx5IgCQAQAPAAYJpxx5IgCQAQAAAA==.Drakonus:BAAALgAECgUJCQAAAA==.Dread:BAAALgADCgQJBAAAAA==.Drosuu:BAAALgAECgEJAQAAAA==.Druish:BAACLgAFFH8ZAAIcAAUJ3B++AgCEAQAcAAUJ3B++AgCEAQAuAAQKfywAAxwACQk0JkMAAHUDABwACQk0JkMAAHUDAB8AAgkOD5ksAGEAAAAA.Drykkr:BAABLgAECn8mAAISAAkJmhaFEQDtAQASAAkJmhaFEQDtAQAAAA==.',
Du='Dullahan:BAAALgAECgUJBgAAAA==.Durrik:BAAALgADCgcJBwAAAA==.',
['Dà']='Dàsh:BAAALgAECgYJBgABLgAECggJEQABAAAAAA==.',
Ea='Eatrocks:BAAALgADCggJCAAAAA==.',
Ed='Edorn:BAAALgADCgIJAgAAAA==.',
Ef='Efn:BAAALgAECgYJEwAAAA==.',
El='Elcrys:BAABLgAECn8aAAIgAAcJ3BYqKgC9AQAgAAcJ3BYqKgC9AQAAAA==.Elion:BAAALgAECgEJAQAAAA==.Ellyra:BAAALgAECgYJCQAAAA==.Elpollo:BAABLgAECn8kAAMRAAcJ9SGUQgBwAgARAAcJ9SGUQgBwAgAhAAEJshe1HAA6AAAAAA==.Elvar:BAAALgAECgQJCgAAAA==.',
Em='Emmdwemm:BAAALgAECgQJCAAAAA==.',
En='Enoki:BAAALgAECgQJBAAAAA==.',
Ep='Ephelia:BAACLgAFFH8KAAIFAAMJpR3iIAAIAQAFAAMJpR3iIAAIAQAuAAQKfxcAAwUACAkjG4oiAA8CAAUACAkjG4oiAA8CAAQAAQmMA/eUACAAAAAA.Epitome:BAABLgAECn8aAAIRAAgJyRWSSgC4AQARAAgJyRWSSgC4AQAAAA==.',
Er='Erid:BAAALgAECgcJEAAAAA==.',
Et='Etude:BAAALgADCgEJAQAAAA==.',
Ev='Evelyndel:BAAALgAECgIJAgAAAA==.Evergrey:BAAALgAECgcJEgAAAA==.Evermoons:BAABLgAECn8jAAIgAAkJVxlCDwCYAgAgAAkJVxlCDwCYAgAAAA==.Evodaka:BAAALgAECgIJAwAAAA==.',
Fa='Falaria:BAAALgAECgQJBAAAAA==.Falasdaer:BAABLgAECn8ZAAILAAgJ5yE0DgCUAgALAAgJ5yE0DgCUAgAAAA==.Fallansting:BAAALgAECgEJAQABLgAECggJGAARAAYVAA==.Falstaff:BAABLgAECn8fAAISAAkJxhUpDwALAgASAAkJxhUpDwALAgAAAA==.Fartshooter:BAAALgAECgYJEQAAAA==.Fatterblunt:BAACLgAFFH8VAAIJAAUJ1hK2EwAsAQAJAAUJ1hK2EwAsAQAuAAQKfyUAAgkACQmpH7YNAMACAAkACQmpH7YNAMACAAAA.',
Fe='Fedner:BAABLgAECn8XAAIFAAcJSQ8yPQBXAQAFAAcJSQ8yPQBXAQAAAA==.Feldar:BAABLgAECn8pAAIHAAgJ3h8dGgBmAgAHAAgJ3h8dGgBmAgAAAA==.Fend:BAAALgADCgQJBAAAAA==.Feyredarling:BAAALgAECgMJAwAAAA==.',
Fi='Fists:BAACLgAFFH8MAAISAAQJgBwtEgA+AQASAAQJgBwtEgA+AQAuAAQKfyoAAxIABgmEI44WAFQCABIABgmEI44WAFQCABYABAk3EqtUAL4AAAAA.Fizzbeard:BAAALgADCgcJCgAAAA==.Fizzical:BAAALgADCgYJBgAAAA==.Fizzleclaw:BAAALgAECgYJEAAAAA==.Fizzleded:BAAALgAECgQJBQABLgAECgYJEAABAAAAAA==.Fizzleflare:BAAALgADCgkJCQAAAA==.',
Fl='Flightrisk:BAAALgAECgQJBgABLgAECgMJBAABAAAAAA==.Florisa:BAABLgAECn8iAAIHAAgJPhwTMQD0AQAHAAgJPhwTMQD0AQAAAA==.',
Fo='Fordi:BAABLgAECn8mAAMEAAgJFh4zDgA7AgAEAAgJFh4zDgA7AgAiAAIJLRFHJgBzAAAAAA==.Forendor:BAAALgAECgIJAwAAAA==.Fourdy:BAABLgAECn8pAAIFAAcJCRm/MQCPAQAFAAcJCRm/MQCPAQAAAA==.',
Fr='Fragdoll:BAAALgAECgQJCgAAAA==.Freakinlarry:BAAALgADCgEJAQAAAA==.Freakinoak:BAABLgAECn8hAAIgAAgJlhHlKgC4AQAgAAgJlhHlKgC4AQAAAA==.Free:BAABLgAECn8XAAMLAAgJlhGoRABrAQALAAcJlhGoRABrAQAjAAUJ9Ap3IACAAAAAAA==.Froost:BAACLgAFFH8HAAIOAAMJqRdnXgD1AAAOAAMJqRdnXgD1AAAuAAQKfxYAAg4ACAnQHPRMAAwCAA4ACAnQHPRMAAwCAAAA.',
Fu='Funkflex:BAAALgAECgEJAQABLgAECggJFwALAJYRAA==.Furvert:BAAALgAECgMJBAAAAA==.Fushi:BAAALgAECgEJAQAAAA==.',
Ga='Gandis:BAAALgAECgkJEgAAAA==.Gapper:BAABLgAECn88AAIQAAkJMiQIAQA4AwAQAAkJMiQIAQA4AwAAAA==.Gargodath:BAAALgAECgMJAwAAAA==.',
Gi='Gimbó:BAAALgADCgQJBgAAAA==.',
Gl='Glamour:BAAALgADCgEJAgAAAA==.Glestaar:BAABLgAECn8jAAMCAAgJnBzzGgA2AgACAAgJnBzzGgA2AgADAAIJRQuFfABSAAAAAA==.Glyr:BAAALgAECgYJCgAAAA==.',
Go='Goingrouge:BAAALgAECgYJCgAAAA==.Goldabelle:BAAALgAECgYJCgAAAA==.Goonkin:BAAALgAECgMJAwABLgAECgkJPAAQADIkAA==.Gorlami:BAAALgAFFAMJBAAAAA==.Gothelf:BAAALgAFFAIJBAAAAA==.Gothri:BAAALgAECgYJCAABLgAECgcJFQAZAJAVAA==.Gothstraza:BAABLgAECn8VAAIZAAcJkBWnJwBPAQAZAAcJkBWnJwBPAQAAAA==.Gottemgood:BAAALgADCgUJBQAAAA==.',
Gr='Grimli:BAABLgAECn8fAAIFAAkJsQ4RMQCTAQAFAAkJsQ4RMQCTAQAAAA==.Growth:BAABLgAECn8ZAAMTAAkJNQmlHwBzAQATAAkJNQmlHwBzAQAkAAYJohDyJABIAQAAAA==.',
Gu='Gurthcaptian:BAAALgAECgQJBAAAAA==.',
Gy='Gyatso:BAAALgADCgMJAwAAAA==.',
['Gá']='Gárròsh:BAAALgAECgYJBgAAAA==.',
Ha='Haerin:BAAALgAECgIJAgABLgAFFAQJEQAGADMkAA==.Happykilmøre:BAAALgAECgQJBAABLgAECgkJEgABAAAAAA==.Harnel:BAABLgAECn8lAAIHAAcJWQMquQDCAAAHAAcJWQMquQDCAAAAAA==.Haseo:BAAALgAECgQJBQAAAA==.Hattorihanzo:BAAALgAECgQJCgAAAA==.',
He='Healeymonstr:BAAALgADCgIJAgAAAA==.Healmart:BAAALgAECgYJDwAAAA==.Heartëater:BAAALgADCgYJBgAAAA==.Hellinyoface:BAAALgADCgUJBQAAAA==.',
Hi='Himothyy:BAAALgAECgQJBAAAAA==.',
Ho='Holypeetch:BAAALgADCgYJBgAAAA==.Hoofpics:BAAALgADCggJEAAAAA==.Hordedefect:BAAALgAECgEJAQABLgAECgMJBAABAAAAAA==.Hoyer:BAAALgAECgkJEwAAAA==.',
Im='Impact:BAAALgADCgcJCgAAAA==.',
In='Inflícted:BAAALgAFFAIJBAAAAA==.Inzo:BAAALgAECgUJBQAAAA==.',
Io='Iove:BAABLgAECn8aAAIVAAkJZBUIFAAMAgAVAAkJZBUIFAAMAgAAAA==.',
Ja='Jahsahm:BAAALgAECgcJEQAAAA==.Jajung:BAAALgADCgMJAwAAAA==.Jakub:BAAALgAECggJEwABLgAFFAQJDgAQABASAA==.Jakuren:BAAALgADCgYJBgAAAA==.Jamjam:BAAALgADCgYJCQAAAA==.',
Je='Jesit:BAABLgAECn8WAAIaAAYJpRNhEgBYAQAaAAYJpRNhEgBYAQAAAA==.',
Ji='Jingles:BAAALgADCgYJBgAAAA==.',
Jj='Jjada:BAABLgAECn8XAAMLAAgJviK7EgBsAgALAAgJ3yC7EgBsAgAjAAYJniGABQBNAgAAAA==.',
Jo='Johnwolf:BAAALgAECgUJEQAAAA==.',
Jy='Jyade:BAABLgAECn8ZAAMKAAcJbwq4CwAwAQAKAAcJEAq4CwAwAQAlAAUJnwifCAD6AAAAAA==.Jynoria:BAAALgADCgcJDAAAAA==.',
Ka='Kainlok:BAAALgADCgIJAgAAAA==.Kaiserice:BAAALgAECgcJEAAAAA==.Kamarra:BAABLgAECn8bAAIZAAcJqQbEOwDmAAAZAAcJqQbEOwDmAAAAAA==.Kamencider:BAABLgAECn8dAAIRAAcJ8RCUcQBXAQARAAcJ8RCUcQBXAQAAAA==.Kamidala:BAAALgAECgIJAgAAAA==.Kankles:BAACLgAFFH8EAAIJAAQJ3x7fCwBkAQAJAAQJ3x7fCwBkAQAuAAQKfyoAAgkACAnqIm0GAK0CAAkACAnqIm0GAK0CAAAA.Katabetta:BAAALgADCgMJAwAAAA==.',
Ke='Kernelpanic:BAACLgAFFH8UAAMOAAUJQBwcMwBNAQAOAAUJQBwcMwBNAQAmAAEJ/gUJEwA7AAAuAAQKfycAAg4ACQkAIusaAGICAA4ACQkAIusaAGICAAAA.Kessho:BAAALgAECgYJDwABLgAFFAQJDgAQABASAA==.Kevynn:BAAALgADCgMJAgAAAA==.Keyoshi:BAAALgAECgYJBgAAAA==.',
Ki='Kickrocks:BAAALgADCgUJBwAAAA==.Kilerforlife:BAAALgAECgYJCwAAAA==.Kilowog:BAAALgADCgUJCAAAAA==.Kilpally:BAAALgAECgYJBwAAAA==.Kintra:BAAALgADCgIJAgAAAA==.Kirin:BAAALgADCgEJAQAAAA==.Kirkle:BAABLgAECn8oAAIYAAkJwRvxAQBuAgAYAAkJwRvxAQBuAgAAAA==.Kithara:BAAALgAECgEJAwAAAA==.',
Ko='Kovie:BAAALgADCggJCAAAAA==.Kovy:BAAALgAFFAIJAgAAAA==.Kovya:BAAALgADCgYJBwAAAA==.',
Kr='Krelel:BAAALgADCgIJAgAAAA==.Krukar:BAAALgADCgYJDAAAAA==.',
Ku='Kubo:BAAALgAECgYJBgABLgAFFAQJDgAQABASAA==.',
Ky='Kydroga:BAAALgAECgYJEAAAAA==.Kynaria:BAAALgADCgMJAwAAAA==.Kynsia:BAAALgADCgQJBQAAAA==.',
La='Lamörak:BAABLgAECn8nAAIHAAgJuR12HwBHAgAHAAgJuR12HwBHAgAAAA==.Landrick:BAABLgAECn8vAAIOAAgJkBoxMgDvAQAOAAgJkBoxMgDvAQAAAA==.Lastotem:BAAALgADCgEJAQAAAA==.Lastshot:BAAALgAECgYJCAAAAA==.Latest:BAAALgADCgQJBAAAAA==.Lavasaurus:BAABLgAECn8ZAAMaAAYJUxpkDgCbAQAaAAYJUxpkDgCbAQAZAAEJnA87bgAxAAAAAA==.',
Le='Leafstorm:BAAALgAECgYJDwAAAA==.Lehala:BAAALgADCgQJBAAAAA==.Lektar:BAAALgAECgUJBQABLgAECgYJEwABAAAAAA==.Leloosh:BAAALgADCgkJDAABLgAFFAIJBAABAAAAAA==.Lemon:BAABLgAECn8gAAIYAAcJ3goHEADzAAAYAAcJ3goHEADzAAAAAA==.Leokenoso:BAABLgAECn8cAAIjAAgJgRCHCQB9AQAjAAgJgRCHCQB9AQAAAA==.Lesclaypool:BAAALgADCgcJBwAAAA==.Lessalia:BAAALgADCgMJBgAAAA==.Lewd:BAAALgAECgQJBQAAAA==.',
Li='Lifebloomz:BAABLgAECn8jAAIgAAgJSwvcQABFAQAgAAgJSwvcQABFAQAAAA==.Lifesabeach:BAAALgAECgEJAQAAAA==.Lilfluffcc:BAAALgAECgQJBAAAAA==.Lissana:BAAALgADCgUJBQAAAA==.',
Lo='Lockward:BAAALgAECgIJAQAAAA==.Lorblor:BAABLgAECn8ZAAIjAAgJVBxLBQAAAgAjAAgJVBxLBQAAAgAAAA==.Lorerun:BAAALgADCgUJCAAAAA==.Lowang:BAABLgAECn8dAAISAAkJnRNsHQB9AQASAAkJnRNsHQB9AQAAAA==.Lowmein:BAAALgAECgYJDwAAAA==.',
Lu='Lucÿfer:BAAALgAECgIJAwAAAA==.Lumie:BAAALgAECgUJBgAAAA==.Luminisx:BAAALgADCgMJAwAAAA==.Lunafox:BAABLgAECn8gAAIFAAgJOh6oDACmAgAFAAgJOh6oDACmAgAAAA==.Lunamae:BAABLgAECn8YAAIhAAcJkRXFAwCWAQAhAAcJkRXFAwCWAQAAAA==.Lupacho:BAAALgAECgYJDAAAAA==.Luvvyyaa:BAABLgAECn83AAMGAAkJ+h2xCADAAgAGAAkJ+h2xCADAAgAkAAcJxA42HwB2AQAAAA==.Luvyya:BAAALgAECgUJDgABLgAECgkJNwAGAPodAA==.Luvyyaa:BAAALgAECgQJBQABLgAECgkJNwAGAPodAA==.',
Ly='Lyrinaku:BAABLgAECn8UAAIGAAcJWRVQNgBkAQAGAAcJWRVQNgBkAQAAAA==.Lythomancer:BAABLgAECn8fAAIYAAgJiA9PCwA7AQAYAAgJiA9PCwA7AQAAAA==.',
Ma='Maddeena:BAABLgAECn8UAAIFAAYJqwMmZwC4AAAFAAYJqwMmZwC4AAAAAA==.Maddy:BAABLgAECn8XAAIWAAcJ1R/vEADwAQAWAAcJ1R/vEADwAQAAAA==.Maelyssa:BAAALgADCgMJAwAAAA==.Magicmangge:BAAALgADCgYJBgABLgAFFAEJAQABAAAAAA==.Makeitclap:BAAALgAECgMJBAABLgAECgcJHQARAPEQAA==.Malidian:BAABLgAECn8dAAILAAkJdQ80PQCGAQALAAkJdQ80PQCGAQAAAA==.Matchadaddy:BAAALgAECgEJAwAAAA==.Maxohlx:BAACLgAFFH8RAAINAAUJ4AsjPAAUAQANAAUJ4AsjPAAUAQAuAAQKfygAAg0ACQk8G9oZALoCAA0ACQk8G9oZALoCAAAA.',
Mc='Mcmercie:BAAALgAECgMJAwAAAA==.',
Me='Mechacooter:BAAALgAFFAMJAwAAAA==.Meeko:BAAALgADCgUJBQABLgAFFAcJEAAaAO4aAA==.Megahertz:BAAALgADCgEJAQAAAA==.Megg:BAAALgADCgcJDAAAAA==.Meilia:BAAALgADCgUJBwAAAA==.Mekari:BAABLgAECn8wAAIQAAkJxR37BACkAgAQAAkJxR37BACkAgAAAA==.Melchiorr:BAABLgAECn8jAAIXAAcJWhjGBgDsAQAXAAcJWhjGBgDsAQAAAA==.Melignant:BAAALgADCgEJAQAAAA==.Melosia:BAAALgADCgQJBwAAAA==.Melynne:BAABLgAECn82AAMFAAkJIxSNGQAoAgAFAAkJIxSNGQAoAgAEAAIJeATEgQBBAAAAAA==.Memmel:BAAALgADCgMJAwAAAA==.Meredeath:BAABLgAECn8UAAIJAAgJKw22MgD1AAAJAAgJKw22MgD1AAAAAA==.',
Mi='Micro:BAAALgAECgkJEwAAAA==.Microkeg:BAAALgAECgcJBAAAAA==.Microslash:BAAALgADCgMJAwABLgAECgkJEwABAAAAAA==.Minsoo:BAABLgAECn8YAAIVAAcJXR3zFAACAgAVAAcJXR3zFAACAgAAAA==.Mistblade:BAAALgAECgQJCgABLgAECggJFwALAJYRAA==.Miststriker:BAAALgAECgUJCQAAAA==.',
Ml='Mlrglett:BAABLgAECn8yAAMcAAgJ3CF+AwCgAgAcAAgJ3CF+AwCgAgAJAAEJihMfhgAqAAAAAA==.Mlrglo:BAAALgADCgcJCQAAAA==.',
Mo='Moisturizeme:BAAALgAECgMJAwAAAA==.Mojomaker:BAAALgAECgUJEwAAAA==.Moojitsu:BAAALgADCgMJAwAAAA==.Mormegil:BAABLgAECn8eAAIUAAYJ4SJBDwAYAgAUAAYJ4SJBDwAYAgAAAA==.Moshimoshi:BAACLgAFFH8PAAMFAAQJqBDpIwD8AAAFAAQJqBDpIwD8AAAEAAEJIQOKOgA3AAAuAAQKfxwAAwQACAmXG2cbADcCAAQABwkQHWcbADcCAAUABwkUCnRRAD8BAAAA.',
Mu='Muffinlord:BAAALgAECgYJEQAAAA==.Munkeebutt:BAABLgAECn8gAAQQAAkJMQkHFAC9AQAQAAkJDQkHFAC9AQADAAcJTwcoUwD/AAACAAEJsQst1QAwAAAAAA==.Munkeefase:BAAALgADCgEJAQAAAA==.',
Na='Naberius:BAAALgAECgIJAgAAAA==.Naillil:BAAALgAECgEJAQAAAA==.Namiiswan:BAAALgADCgMJBQAAAA==.Natsuki:BAAALgADCgUJBwAAAA==.',
Ne='Nefarius:BAAALgAECgcJCwABLgAECggJEwABAAAAAA==.Neflite:BAABLgAECn8dAAIYAAcJXQcEEwDTAAAYAAcJXQcEEwDTAAAAAA==.Nelfie:BAAALgAECgEJAQAAAA==.Nessará:BAAALgAECgUJCgAAAA==.',
Ni='Nineõseven:BAABLgAECn8YAAITAAcJixN9IADVAQATAAcJixN9IADVAQABLgAECgEJAQABAAAAAA==.Ninjapro:BAAALgAECgEJAQAAAA==.Nixia:BAAALgAECgQJBAAAAA==.',
No='Nodiddy:BAAALgAECgQJBAABLgAECgcJJAARAPUhAA==.',
Nu='Nuraga:BAABLgAECn8hAAMnAAgJliHXBwCpAgAnAAcJByTXBwCpAgAPAAEJ7hKPbQBJAAAAAA==.',
Ob='Obeeone:BAAALgAECgEJAQAAAA==.',
On='Onasta:BAABLgAECn8hAAIOAAkJkh9rIgA3AgAOAAkJkh9rIgA3AgAAAA==.Onelastkiss:BAAALgAECgEJAQAAAA==.',
Op='Oprahheals:BAAALgAFFAEJAQAAAA==.',
Or='Oreobeer:BAAALgAECgEJAQAAAA==.Oreomonster:BAAALgAECgYJDQAAAA==.Orquesta:BAAALgAECgQJCAAAAA==.',
Pa='Paccer:BAAALgAECgEJAQAAAA==.Pacerx:BAAALgAECgIJAgAAAA==.Pandaemonia:BAACLgAFFH8KAAIjAAMJWw62BQCoAAAjAAMJWw62BQCoAAAuAAQKfyAAAiMACAnXDY0SACkBACMACAnXDY0SACkBAAAA.Pandakyle:BAABLgAECn8XAAIVAAYJ5xc0LABAAQAVAAYJ5xc0LABAAQAAAA==.Pandexander:BAAALgADCgMJAwAAAA==.Parts:BAABLgAECn8iAAIRAAgJtiGIIQDtAgARAAgJtiGIIQDtAgABLgAFFAUJEAAOALgdAA==.Patchmen:BAAALgAECgQJBAAAAA==.Pattilicious:BAABLgAECn8kAAIHAAkJZgtmTgCTAQAHAAkJZgtmTgCTAQAAAA==.',
Pe='Pepsizero:BAAALgAECgUJCwAAAA==.',
Ph='Phlesh:BAAALgAECgEJAgAAAA==.Phlvrabies:BAAALgADCgMJBQAAAA==.Phonedin:BAABLgAECn8jAAMbAAkJERmdBgCIAgAbAAkJERmdBgCIAgAZAAMJBhchSQCyAAAAAA==.Phoënix:BAACLgAFFH8LAAIFAAQJvBUUHAAgAQAFAAQJvBUUHAAgAQAuAAQKfx4AAwUACQmWHXQKAMQCAAUACQmWHXQKAMQCAAQAAgkhE3lnAFMAAAAA.',
Pi='Pieglaive:BAABLgAECn8jAAMMAAkJzCHsAwDJAgAMAAkJzCHsAwDJAgALAAIJuhZpwwB2AAAAAA==.Pierres:BAAALgAECgYJBwAAAA==.Piondelth:BAAALgAECgcJEQAAAA==.',
Pl='Plantman:BAAALgAECgUJCQAAAA==.',
Po='Poofort:BAAALgAECgMJAwAAAA==.Pooner:BAAALgADCgMJAwAAAA==.Porkins:BAAALgAECgMJAwAAAA==.Postoak:BAAALgAECgUJCgAAAA==.Powerochrist:BAABLgAECn8gAAIdAAkJjxEOGwDfAQAdAAkJjxEOGwDfAQAAAA==.',
Pr='Proxzy:BAAALgAECggJCwAAAA==.',
Pu='Pubessalad:BAABLgAECn8WAAIHAAYJyRNrfQAoAQAHAAYJyRNrfQAoAQAAAA==.Puddin:BAAALgADCgQJBgAAAA==.Puffytaco:BAAALgAECgQJBgABLgAECgkJIwAHANccAA==.',
Qu='Qualek:BAABLgAECn8XAAInAAkJMRJfEAADAgAnAAkJMRJfEAADAgAAAA==.Quilue:BAABLgAECn8ZAAIRAAgJhA6nXgCCAQARAAgJhA6nXgCCAQAAAA==.',
Ra='Rannmagnison:BAABLgAECn8pAAIHAAgJugZCgAAjAQAHAAgJugZCgAAjAQAAAA==.Raquoon:BAAALgAECgUJEwAAAA==.Ratfu:BAAALgADCgcJDQAAAA==.Razjin:BAABLgAECn8aAAMFAAkJeiPsCQDaAgAFAAkJeiPsCQDaAgAEAAEJ/wqefgApAAAAAA==.',
Re='Reapér:BAAALgAECgkJBQAAAA==.Reze:BAACLgAFFH8PAAIWAAQJdx9mBQB0AQAWAAQJdx9mBQB0AQAuAAQKfxYAAhYACAlYHu8KAEkCABYACAlYHu8KAEkCAAEuAAUUCAkmAAwA2R8A.',
Rh='Rhaeynera:BAABLgAECn8jAAIbAAcJtwVfDQDxAAAbAAcJtwVfDQDxAAAAAA==.',
Ri='Riezen:BAAALgAECgEJAgAAAA==.Ringol:BAAALgAECgQJCgAAAA==.Rinorik:BAABLgAECn83AAMNAAkJQSBeCQDaAgANAAkJQSBeCQDaAgAYAAYJCRn2FACjAQAAAA==.Rizzdor:BAAALgADCgcJCAABLgAECgkJEgABAAAAAA==.',
Ro='Rockbiter:BAAALgAECgEJAgAAAA==.Rockhhard:BAABLgAECn8cAAIFAAkJyB72EgBhAgAFAAkJyB72EgBhAgAAAA==.Roeken:BAABLgAECn8oAAIPAAkJ8BPnFwDiAQAPAAkJ8BPnFwDiAQAAAA==.Rollingman:BAAALgAECgYJEAAAAA==.',
Ru='Rudyrots:BAAALgAECgEJAQABLgAFFAEJAgABAAAAAA==.Rudyshoots:BAAALgAFFAEJAgAAAA==.',
Ry='Rygaard:BAABLgAECn84AAInAAkJHyI6AgD4AgAnAAkJHyI6AgD4AgAAAA==.Ryutiz:BAABLgAECn8jAAIDAAgJ7iHHEAC2AgADAAgJ7iHHEAC2AgAAAA==.Ryward:BAAALgADCgcJBwAAAA==.Ryyuk:BAAALgAECgMJBAABLgAECggJFwALAJYRAA==.',
Sa='Sacridas:BAAALgAECgEJAQABLgAECggJIwADAO4hAA==.Sako:BAAALgADCgUJCgAAAA==.Samsó:BAAALgAECggJEQAAAA==.Sapharina:BAABLgAECn8xAAIkAAkJfxdfCgB3AgAkAAkJfxdfCgB3AgAAAA==.Sassgrip:BAAALgADCgEJAQABLgAECgYJDAABAAAAAA==.Sassier:BAAALgAECgYJDAAAAA==.Sathenaz:BAAALgADCgcJCQAAAA==.',
Sc='Scarcy:BAACLgAFFH8RAAIIAAUJKRnmBACwAQAIAAUJKRnmBACwAQAuAAQKfy4AAwgACQliGrAQAJ0CAAgACQliGrAQAJ0CACUAAQkAABYdAAAAAAAA.',
Se='Seacotton:BAAALgAECgcJEQAAAA==.Searfang:BAACLgAFFH8OAAIEAAQJRBK6FAAkAQAEAAQJRBK6FAAkAQAuAAQKfy0AAwQACQlpHRoKAHYCAAQACQlpHRoKAHYCAAUAAQljE+WWADYAAAAA.Seariel:BAAALgAECgUJBgAAAA==.Selestra:BAAALgAFFAIJAgAAAA==.Selinise:BAAALgAECgUJBQAAAA==.Sematic:BAAALgAFFAEJAQABLgAFFAYJFAARAJMbAA==.Senpai:BAAALgAECgQJBAAAAA==.Seraphymm:BAAALgADCgEJAQAAAA==.',
Sh='Shadowjacker:BAACLgAFFH8PAAILAAQJ+xoKIABIAQALAAQJ+xoKIABIAQAuAAQKfzgAAgsACQkmIYIHAFEDAAsACQkmIYIHAFEDAAAA.Shadowmidget:BAABLgAECn8WAAINAAkJ3BahVwDBAQANAAkJ3BahVwDBAQAAAA==.Shadrielis:BAABLgAECn8vAAMkAAgJnx1oCQCJAgAkAAgJnx1oCQCJAgAGAAIJVQ3VbgBsAAAAAA==.Shanlao:BAAALgAECgIJAgABLgAFFAUJFQANAJ8OAA==.Shirkka:BAAALgADCgMJBAAAAA==.Shurihito:BAABLgAECn8hAAIHAAkJJB4bGABzAgAHAAkJJB4bGABzAgAAAA==.',
Si='Sieron:BAABLgAECn8UAAIOAAYJ/Ry/ZABUAQAOAAYJ/Ry/ZABUAQAAAA==.Silaslunark:BAAALgAECgcJCQAAAA==.Sixpack:BAABLgAECn8VAAIgAAkJWQyGaQAWAQAgAAkJWQyGaQAWAQAAAA==.',
Sk='Skarigar:BAAALgAECgEJAQAAAA==.Skeeterson:BAAALgADCgUJBwAAAA==.Skiððles:BAAALgAECgYJBgABLgAECgkJFwAEANAUAA==.Skytec:BAAALgADCgMJAwAAAA==.Skëëts:BAABLgAECn8bAAMkAAgJRxBpGgCjAQAkAAgJJBBpGgCjAQAGAAEJ5gZ/XAAoAAAAAA==.Skùrvypete:BAAALgADCgEJAQABLgAECgkJFwAEANAUAA==.',
Sl='Slampoof:BAAALgAECgEJAgAAAA==.Slamslayer:BAAALgAECgEJAQAAAA==.Sleez:BAAALgAECgYJDAAAAA==.Sloodraga:BAAALgADCgYJBgAAAA==.',
Sm='Smallgregory:BAAALgAECgYJDAAAAA==.',
Sn='Sneakdead:BAAALgAECgcJCgAAAA==.Sneakerzz:BAAALgADCgQJBAAAAA==.Sneakfury:BAAALgAECgYJCgABLgAECgcJCgABAAAAAA==.Sneeler:BAAALgAECgEJAQAAAA==.Snowscayia:BAACLgAFFH8GAAMJAAQJ2ggoIQDCAAAJAAMJiAgoIQDCAAAgAAIJAxBVOgCGAAAuAAQKfyoABAkACQkbGDMnAMUBAAkACAk1GjMnAMUBACAABwn1FD87ALgBAB8AAQlhCYowADoAAAAA.',
So='Solanar:BAABLgAECn8uAAMdAAgJsiO3CQCqAgAdAAgJsiO3CQCqAgAHAAEJAABqXQEAAAAAAA==.Solesin:BAAALgAFFAEJAQABLgAFFAQJEQAaAJwZAA==.Solmina:BAABLgAECn83AAIRAAkJIh5hEQC9AgARAAkJIh5hEQC9AgAAAA==.Somniatis:BAAALgAECgEJAQAAAA==.Soulciopath:BAAALgAECgUJCAAAAA==.',
Sp='Spicypants:BAAALgADCgMJAwAAAA==.Spicytaco:BAAALgAECgUJCgABLgAECgkJIwAHANccAA==.Spookuleli:BAAALgADCgQJBAAAAA==.Sprinklewiz:BAAALgADCgMJAwAAAA==.',
Sq='Squadie:BAABLgAECn8rAAICAAgJ7QdqUQBUAQACAAgJ7QdqUQBUAQAAAA==.Squanchs:BAACLgAFFH8RAAIFAAQJGh38FABLAQAFAAQJGh38FABLAQAuAAQKfx4AAwUACQllH8oLALICAAUACQllH8oLALICAAQAAQkGAO6MAAEAAAEuAAQKBwkcACAAkxsA.Squanchy:BAABLgAECn8cAAIgAAcJkxtxPACyAQAgAAcJkxtxPACyAQAAAA==.Squisquee:BAAALgADCgcJBwAAAA==.',
Sr='Srbojangles:BAAALgAECgYJBgABLgAECgcJJAARAPUhAA==.Srry:BAABLgAECn8VAAIPAAcJsBrUKQATAgAPAAcJsBrUKQATAgAAAA==.',
St='Stinkvile:BAAALgAECgEJAQAAAA==.Stonebraid:BAAALgADCgEJAQAAAA==.Sturdy:BAAALgADCgEJAQAAAA==.',
Su='Sukuna:BAAALgAECgYJCAAAAA==.Sundance:BAAALgAECggJDgAAAA==.Surmise:BAACLgAFFH8UAAIRAAYJkxv7EADNAQARAAYJkxv7EADNAQAuAAQKfycAAxEACQlPJDUNAN8CABEACQkDIzUNAN8CACEABAlVIGYGABUBAAAA.Sust:BAAALgAECgUJBQABLgAFFAYJFAARAJMbAA==.',
Sw='Swayzeetrain:BAACLgAFFH8JAAMdAAMJhhshHAD0AAAdAAMJhhshHAD0AAAHAAEJpAxQMABUAAAuAAQKfxcAAwcACAk6GyxmALQBAAcABwkgGixmALQBAB0ABwnJHeA2AKABAAAA.',
Ta='Tabius:BAABLgAECn8mAAMfAAkJWx7RBQA1AgAfAAkJWx7RBQA1AgAJAAMJyw45RwCYAAAAAA==.Talkingtaco:BAABLgAECn8jAAIHAAkJ1xxVEgCaAgAHAAkJ1xxVEgCaAgAAAA==.Taln:BAAALgADCgUJBQABLgAECgYJHgAUAOEiAA==.Talìa:BAAALgADCgIJAgABLgADCgQJBAABAAAAAA==.Tareul:BAAALgADCgIJAgAAAA==.Tarn:BAAALgAECgkJEgAAAA==.',
Te='Temok:BAABLgAECn8UAAIHAAYJ+grmlgD7AAAHAAYJ+grmlgD7AAAAAA==.',
Th='Theabyss:BAAALgAECgEJAQABLgADCgcJEwABAAAAAA==.Thiccbush:BAAALgAECgEJAQAAAA==.Thirielnet:BAAALgAECgUJBwAAAA==.This:BAAALgAECgEJAQAAAA==.Thorisdead:BAAALgADCgMJAwABLgAECgYJFQASALIHAA==.Thorkell:BAAALgADCgUJBQAAAA==.Thosen:BAAALgAECgQJBAAAAA==.',
Ti='Tinkaballah:BAAALgAECgcJDgAAAA==.Tipy:BAAALgADCgUJBQAAAA==.',
To='Tore:BAACLgAFFH8OAAICAAMJdhx9LwD+AAACAAMJdhx9LwD+AAAuAAQKfy8AAgIACAmPI6cJAPwCAAIACAmPI6cJAPwCAAAA.Totemangge:BAAALgAFFAEJAQAAAA==.',
Tr='Trifectas:BAAALgADCgcJEQAAAA==.Trinadel:BAACLgAFFH8KAAIJAAQJMg0iFwAYAQAJAAQJMg0iFwAYAQAuAAQKfx0AAgkACAmnHS8PAK0CAAkACAmnHS8PAK0CAAAA.Träitors:BAAALgADCgcJEwAAAA==.Tråitors:BAABLgAECn8wAAMNAAYJ/CHGNwAtAgANAAYJ/CHGNwAtAgAYAAEJAAA0ZQBFAAABLgADCgcJEwABAAAAAA==.',
Ts='Tsarevich:BAAALgAECgUJEwAAAA==.',
Tu='Tugtheshaman:BAABLgAECn8dAAIFAAgJoxgmGgBGAgAFAAgJoxgmGgBGAgAAAA==.',
Tw='Twileaf:BAABLgAECn8nAAIgAAcJFgdyXgDVAAAgAAcJFgdyXgDVAAAAAA==.Twoinchisbig:BAABLgAECn88AAInAAgJTBuxCwDkAQAnAAgJTBuxCwDkAQAAAA==.',
Ty='Typhoidmary:BAABLgAECn8XAAMNAAgJhAmIggBVAQANAAcJhAmIggBVAQAYAAEJAAAOdgAuAAABLgAFFAMJAwABAAAAAA==.',
['Té']='Térror:BAAALgAECgcJDwAAAA==.',
Un='Uncool:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Unholyz:BAAALgAECgQJBAAAAA==.',
Ur='Ursoc:BAABLgAECn8nAAMgAAgJEhVOSAAlAQAgAAYJRxFOSAAlAQAJAAcJlA7gNADpAAAAAA==.Urteg:BAAALgADCgYJCwAAAA==.',
Uu='Uub:BAAALgAECgIJAgAAAA==.',
Va='Vairekor:BAAALgADCggJDgABLgAFFAUJFQANAJ8OAA==.Valdria:BAAALgADCgUJBQAAAA==.Vanillaçake:BAAALgAECgEJAgAAAA==.Vanishja:BAAALgAECgYJDwAAAA==.Varkbyte:BAAALgAECgUJEwAAAA==.Varrik:BAACLgAFFH8MAAMPAAQJfCBYCAB1AQAPAAQJfCBYCAB1AQAoAAMJ7hh4EQDgAAAuAAQKfyYAAw8ACAnjIooJABUDAA8ACAnjIooJABUDACgABgmeG1UTAG8BAAAA.',
Ve='Vec:BAAALgAECgYJDQAAAA==.Velamor:BAABLgAECn8YAAQjAAYJzgsMFAC/AAAjAAYJ5goMFAC/AAAMAAMJygk5VQCTAAALAAMJagpXpACAAAAAAA==.Velaria:BAAALgADCgcJBwAAAA==.',
Vo='Volieu:BAABLgAECn8gAAIhAAgJRBT/AgDHAQAhAAgJRBT/AgDHAQAAAA==.Volklin:BAABLgAECn8ZAAMFAAgJ3gYhSQAmAQAFAAgJ3gYhSQAmAQAEAAYJSQdeRgDBAAAAAA==.Voyageurs:BAABLgAECn8VAAIfAAcJxRSpDgBoAQAfAAcJxRSpDgBoAQAAAA==.',
Vy='Vyrka:BAAALgAECgMJDQAAAA==.',
Wa='Wallstreet:BAAALgAECgUJBQAAAA==.Waterdweller:BAAALgAECgEJAgAAAA==.',
We='Wegl:BAAALgAECgUJDgAAAA==.Werewithal:BAAALgADCgUJBQABLgAECggJJgAQADASAA==.Wesleypipes:BAAALgAECgEJAQAAAA==.Wetfloorsign:BAAALgAECgYJEQAAAA==.',
Wh='Wholeymilk:BAAALgADCgMJAwAAAA==.',
Wi='Wiindsslashh:BAAALgAECgYJBwAAAA==.Wilbur:BAAALgADCgQJBQAAAA==.Windslash:BAAALgAECgIJAQAAAA==.',
Wo='Wonderx:BAAALgADCgIJAgAAAA==.Wonyoung:BAACLgAFFH8RAAIGAAQJMyQ1BQCiAQAGAAQJMyQ1BQCiAQAuAAQKfzIAAgYACQnzI9kBAFgDAAYACQnzI9kBAFgDAAAA.',
Wu='Wuthrad:BAAALgADCgQJBAAAAA==.',
Xa='Xala:BAABLgAECn8UAAMUAAkJbw0pGgA1AQAUAAgJUA4pGgA1AQAmAAIJ+AeHGgBnAAAAAA==.Xalah:BAAALgAECgYJBgAAAA==.Xalaz:BAACLgAFFH8SAAMNAAUJsBAINgAjAQANAAUJsBAINgAjAQAYAAEJVwJgGgBGAAAuAAQKfx0AAw0ACQlXHHQ2ADICAA0ACAlXHHQ2ADICABgAAgkLFGNSAHcAAAAA.Xanaris:BAAALgADCgEJAQABLgAFFAIJCQAOACImAA==.Xandumbra:BAAALgADCgEJAQAAAA==.Xarosea:BAACLgAFFH8MAAIHAAQJPxOaJQA4AQAHAAQJPxOaJQA4AQAuAAQKfyoAAgcABwk6JPYYANMCAAcABwk6JPYYANMCAAAA.',
Xe='Xelojr:BAAALgADCgkJHAAAAA==.',
Xh='Xhael:BAAALgADCgEJAQAAAA==.',
Xi='Xia:BAABLgAECn8zAAIGAAkJqRn7DQA9AgAGAAkJqRn7DQA9AgAAAA==.',
Xo='Xoilkick:BAAALgAECgUJCgAAAA==.Xoilwings:BAAALgAECgEJAQAAAA==.Xooiill:BAAALgAECgcJDQAAAA==.',
Xp='Xpacer:BAAALgAECgcJEwAAAA==.',
Ye='Yekira:BAAALgADCgEJAgAAAA==.Yellowsnøw:BAABLgAECn8pAAIRAAgJYBW3QgDRAQARAAgJYBW3QgDRAQAAAA==.',
Yu='Yumeshade:BAAALgAECgUJCQAAAA==.',
Za='Zal:BAAALgAECgYJBgABLgAFFAUJEwAeAKAWAA==.Zamari:BAAALgAECgYJCwAAAA==.Zanzabar:BAABLgAECn8VAAIfAAkJwgrGEACgAQAfAAkJwgrGEACgAQAAAA==.Zathmage:BAAALgADCgMJAwAAAA==.Zaxin:BAABLgAECn8VAAMGAAcJLA8VJABbAQAGAAcJLA8VJABbAQATAAUJiAQeSwCtAAAAAA==.',
Ze='Zelfie:BAAALgADCgUJBQAAAA==.Zellda:BAAALgAECgQJBwAAAA==.Zeros:BAABLgAECn8VAAIRAAcJ9xhEVACdAQARAAcJ9xhEVACdAQAAAA==.',
Zo='Zoerina:BAAALgAECgYJDQAAAA==.Zoobilong:BAAALgAECgUJDwAAAA==.',
Zx='Zxak:BAABLgAECn8rAAIMAAgJUybrAgDsAgAMAAgJUybrAgDsAgAAAA==.',
Zy='Zyahk:BAAALgADCgQJBQAAAA==.Zynn:BAAALgAECgEJAgAAAA==.',
['Zë']='Zën:BAAALgAECgEJAQABLgAFFAIJBAABAAAAAA==.',
['Ða']='Ðashÿ:BAAALgAECgMJAwABLgAECggJEQABAAAAAA==.',
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
