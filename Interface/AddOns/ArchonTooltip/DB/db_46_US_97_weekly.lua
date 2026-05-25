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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Elemental','Shaman-Restoration','Priest-Holy','Paladin-Retribution','Rogue-Subtlety','Druid-Balance','Rogue-Assassination','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','DeathKnight-Unholy','Warrior-Fury','Hunter-Survival','Mage-Frost','Monk-Brewmaster','Priest-Shadow','DeathKnight-Blood','Monk-Mistweaver','Monk-Windwalker','Warlock-Affliction','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Druid-Guardian','Paladin-Holy','Priest-Discipline','Paladin-Protection','Druid-Feral','Druid-Restoration','Mage-Arcane','Shaman-Enhancement','DemonHunter-Vengeance','Warrior-Protection','Rogue-Outlaw','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abandonhope:BAAALgAECgMJAwABLgAECgkJDQABAAAAAA==.',
Ac='Accuser:BAAALgADCgEJAQAAAA==.Acky:BAAALgADCgUJBQAAAA==.',
Ad='Adwen:BAAALgAECgUJEwAAAA==.',
Ae='Aenimal:BAAALgAECgYJDQAAAA==.Aer:BAAALgADCgkJCQAAAA==.Aeronemon:BAAALgAECgEJAgAAAA==.',
Ai='Airill:BAAALgADCgQJBQAAAA==.',
Ak='Akforty:BAABLgAECn8fAAMCAAkJIiHNCgDvAgACAAkJIiHNCgDvAgADAAIJoBV7eABfAAAAAA==.Akittymeow:BAABLgAECn8bAAMEAAkJuw8/OgAdAQAEAAgJKQ8/OgAdAQAFAAMJiwU6jQB2AAAAAA==.',
Al='Aldredevon:BAAALgAECgEJAQAAAA==.Aleshock:BAAALgAECggJDwAAAA==.Alidar:BAAALgAECgcJEwAAAA==.Alphaboner:BAAALgADCgYJBwAAAA==.Altairis:BAAALgAECgEJAgAAAA==.Altartoy:BAABLgAECn8hAAIGAAgJ6QrwLQA4AQAGAAgJ6QrwLQA4AQAAAA==.Althunter:BAACLgAFFH8NAAIDAAQJUiFOCQCGAQADAAQJUiFOCQCGAQAuAAQKfxsAAgMACAneITUFADECAAMACAneITUFADECAAAA.',
Am='Amelina:BAAALgAECgUJCQAAAA==.Amerit:BAAALgADCgUJBQAAAA==.Amorir:BAABLgAECn89AAIHAAkJ+RHzSgDHAQAHAAkJ+RHzSgDHAQAAAA==.Amorit:BAAALgAECgYJCQAAAA==.Amorydalias:BAAALgAECgUJBgAAAA==.Amozon:BAAALgADCgEJAQAAAA==.',
An='Anamortem:BAAALgAECgMJAwABLgAECgkJIQAIAAcZAA==.Anastala:BAABLgAECn8qAAIJAAgJ8BXUGwC8AQAJAAgJ8BXUGwC8AQAAAA==.Angchu:BAAALgADCgQJBAAAAA==.Angelmàker:BAAALgAECgMJBAABLgADCgcJEwABAAAAAA==.Annesta:BAABLgAECn8hAAMIAAkJBxnuEgDoAQAIAAkJ0hjuEgDoAQAKAAEJ9xanHwBAAAAAAA==.',
Ap='Apostus:BAAALgADCgcJDgAAAA==.Apothica:BAAALgAECgUJBgAAAA==.',
Aq='Aquafox:BAABLgAECn8XAAMFAAYJJiL7HQAwAgAFAAYJJiL7HQAwAgAEAAMJYxCSXwCUAAAAAA==.',
Ar='Archontas:BAABLgAECn8jAAIJAAgJfyGHCACpAgAJAAgJfyGHCACpAgAAAA==.Ariodh:BAABLgAECn81AAMLAAkJLSa1AQBnAwALAAkJLSa1AQBnAwAMAAUJpB9eJACaAQAAAA==.Arkaline:BAAALgAECgEJAQAAAA==.Artuarry:BAACLgAFFH8aAAINAAUJ7xCkQAAjAQANAAUJ7xCkQAAjAQAuAAQKfyYAAg0ACQlGH3UYAHgCAA0ACQlGH3UYAHgCAAAA.Aryndus:BAABLgAECn8cAAIHAAkJRR22GQCLAgAHAAkJRR22GQCLAgAAAA==.',
At='Athenà:BAAALgAECgQJBAAAAA==.',
Av='Avocado:BAABLgAECn8jAAMCAAkJnCV3CAD1AgACAAkJHiN3CAD1AgADAAcJVCJlCQC4AQAAAA==.',
Ax='Axelaw:BAAALgADCgQJBAAAAA==.',
Ay='Ayrz:BAAALgAECgIJAgAAAA==.',
Az='Azaria:BAAALgADCgIJAgAAAA==.',
Ba='Baddjujumon:BAAALgAECggJDwAAAA==.Baileyhowl:BAAALgAECgEJBQAAAA==.Bammie:BAAALgADCgYJCgAAAA==.Bananuth:BAAALgAECgIJAwABLgAFFAUJGQAOAM8cAA==.Banthr:BAABLgAECn8UAAIPAAkJDw6NJQCmAQAPAAkJDw6NJQCmAQAAAA==.Barkert:BAAALgADCgEJAQAAAA==.Baroke:BAAALgAECgMJBwABLgAECggJIQAGAOkKAA==.Barokoshama:BAAALgAECgcJEQAAAA==.Basaltytaco:BAAALgADCgEJAQAAAA==.Battleworm:BAAALgADCgkJEwABLgAFFAMJAwABAAAAAA==.',
Bb='Bbalrd:BAABLgAECn8XAAIOAAkJohdvPgDmAQAOAAkJohdvPgDmAQAAAA==.',
Be='Bearglie:BAAALgAECgYJBgAAAA==.Beepers:BAAALgAECgYJBgAAAA==.Beezelpup:BAAALgADCgUJBQAAAA==.',
Bi='Bigcow:BAAALgAECgUJCQAAAA==.',
Bl='Blackolives:BAAALgAECgcJDAAAAA==.Bladesp:BAAALgAECgYJBwABLgAECggJFwALAJcRAA==.Blondefu:BAAALgAECgUJCwAAAA==.Bloodybonne:BAAALgADCgcJBwAAAA==.Bloodyell:BAAALgAECgEJAQAAAA==.Bloore:BAAALgAECgMJAwABLgAECgkJLAADAG0iAA==.Bluejuly:BAAALgAECgQJBAAAAA==.Blutø:BAAALgAECgYJDAAAAA==.',
Bo='Boflex:BAAALgADCgQJBgAAAA==.Bomboclat:BAAALgAECgUJCwAAAA==.Bonesknows:BAAALgADCgEJAQAAAA==.Boofy:BAAALgAECgMJAwABLgAECgkJFgANANwWAA==.Borhoag:BAAALgADCgEJAQABLgAECgcJCAABAAAAAA==.Bowwie:BAACLgAFFH8PAAMQAAQJEBL3EQAeAQAQAAQJDwv3EQAeAQACAAMJZRCkSwDLAAAuAAQKfysABAIACQmNHy0GACsDAAIACQkTHi0GACsDABAACAkPGKQSAPkBAAMAAQkVAxWTACcAAAAA.',
Br='Britney:BAAALgADCgkJCQAAAA==.Bronzé:BAABLgAECn8uAAIRAAcJfyHCMAA3AgARAAcJfyHCMAA3AgAAAA==.Brotherfrey:BAAALgAECgYJCgAAAA==.Bruish:BAABLgAFFH8MAAISAAQJtwzFDQAWAQASAAQJtwzFDQAWAQAAAA==.',
Bu='Bubbadoo:BAABLgAECn8gAAIJAAgJbQ+nJgBpAQAJAAgJbQ+nJgBpAQAAAA==.Buddy:BAABLgAECn8ZAAITAAYJoRLhLwA2AQATAAYJoRLhLwA2AQABLgAECggJJgAUAHMhAA==.Bulan:BAABLgAECn86AAIVAAkJhSQEAgCYAwAVAAkJhSQEAgCYAwAAAA==.',
Bw='Bweninger:BAAALgAECgEJAQAAAA==.',
['Bô']='Bôôsted:BAABLgAECn8dAAIEAAkJ0hTfIAAIAgAEAAkJ0hTfIAAIAgAAAA==.',
Ca='Caistan:BAAALgADCgYJCAAAAA==.Candypants:BAABLgAECn8hAAQVAAgJgBaeHQDqAQAVAAgJgBaeHQDqAQASAAcJ9A6zNAAOAQAWAAMJ2AuBVgCFAAAAAA==.Caoth:BAAALgAECgYJEwAAAA==.Cappilon:BAAALgAECggJEQAAAA==.Carcus:BAAALgAECgcJBwAAAA==.Cayleedah:BAABLgAECn8mAAIDAAgJxQcPEgAUAQADAAgJxQcPEgAUAQAAAA==.Cayssaris:BAAALgAECgUJEQAAAA==.',
Cc='Cc:BAABLgAECn8WAAQXAAYJPBPsDgBCAQAXAAUJ9BPsDgBCAQAYAAYJKwstIwA+AQANAAQJzhP5tQDtAAAAAA==.',
Ce='Ceeti:BAABLgAECn84AAMZAAkJICHyBgDUAgAZAAkJICHyBgDUAgAaAAIJeAYcQABpAAAAAA==.Celandrelia:BAAALgAECgUJBQABLgAECggJLAAbAEQXAA==.',
Ch='Chaewon:BAAALgAECgYJCgABLgAFFAQJEQAGADMkAA==.Channeria:BAAALgAECgEJAQAAAA==.Chaoticoreo:BAABLgAECn8xAAMMAAkJOh70BgCaAgAMAAkJOh70BgCaAgALAAQJ4w9rrQCzAAAAAA==.Chappedlips:BAAALgAECgkJBgAAAA==.Chareyne:BAABLgAECn8ZAAIGAAgJ5RFyJgC5AQAGAAgJ5RFyJgC5AQAAAA==.Cheetor:BAAALgAECgMJAwABLgAFFAMJBgAQAEMYAA==.Cheezytaco:BAAALgAECgYJDgABLgAECgkJIwAHANccAA==.Chidge:BAAALgADCggJCwAAAA==.Chikila:BAABLgAECn8jAAMYAAgJBhljBQDrAQAYAAgJBhljBQDrAQANAAMJeAw2xgCjAAAAAA==.Chilliflakez:BAAALgAECgUJEwAAAA==.Chro:BAAALgAECgcJBwABLgAECgkJLQAEAP0dAA==.',
Ci='Cindezar:BAAALgADCgMJAwAAAA==.',
Cl='Clementyn:BAABLgAECn8WAAIHAAcJOBCGpwAKAQAHAAcJOBCGpwAKAQAAAA==.Cleyi:BAABLgAECn8pAAIGAAgJxQ0CKQBaAQAGAAgJxQ0CKQBaAQAAAA==.',
Co='Coldpasta:BAAALgAECgYJDgABLgAFFAIJBAABAAAAAA==.Colonoscopy:BAAALgAECgMJBAAAAA==.Coreyy:BAAALgADCgUJBwAAAA==.Corva:BAACLgAFFH8PAAINAAQJqQ6YUwD0AAANAAQJqQ6YUwD0AAAuAAQKfyoAAg0ACQnpFQI2AOgBAA0ACQnpFQI2AOgBAAAA.Cosairi:BAAALgAECgYJEgAAAA==.Cougztroll:BAABLgAECn8wAAIcAAkJlRW1DQDMAQAcAAkJlRW1DQDMAQAAAA==.',
Cr='Crazaki:BAAALgADCgEJAQAAAA==.',
Cu='Curfluffin:BAAALgADCgEJAQAAAA==.Cuttercupx:BAAALgAECgEJAQABLgAECgkJDQABAAAAAA==.',
Da='Dahn:BAAALgAECgIJAgAAAA==.Dakadin:BAABLgAECn8mAAMdAAkJ+yPJDgCDAgAdAAkJ+yPJDgCDAgAHAAQJ7hczuQDvAAAAAA==.Daranne:BAACLgAFFH8OAAIHAAQJqROtLQA0AQAHAAQJqROtLQA0AQAuAAQKfycAAgcACQnHGhc/ACkCAAcACQnHGhc/ACkCAAAA.Darkenedstar:BAAALgAECgYJCgABLgAECgYJDQABAAAAAA==.Darksoulstwo:BAAALgADCgMJAwAAAA==.Dasbeans:BAABLgAECn8XAAMZAAkJOgj/PQALAQAZAAgJIAn/PQALAQAbAAIJkgHvRgARAAAAAA==.Dashy:BAABLgAECn8WAAMGAAgJ8R9gDwBLAgAGAAgJVBpgDwBLAgAeAAYJ4B7NEQAsAgAAAA==.Datran:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.',
De='Deaduglie:BAABLgAECn84AAMNAAkJbBY2KwAUAgANAAkJbBY2KwAUAgAYAAEJMQjvcQA0AAAAAA==.Deliandora:BAAALgAECgQJBwAAAA==.Delusional:BAAALgAECgcJDQAAAA==.Delynique:BAAALgADCgEJAQABLgAECgkJLAADAG0iAA==.Demonx:BAAALgAECgEJAQAAAA==.Denaric:BAAALgAECgYJEAAAAA==.Destroyevsky:BAABLgAECn8aAAIPAAUJ3QGUeABTAAAPAAUJ3QGUeABTAAAAAA==.Detonate:BAABLgAECn8YAAIRAAYJbhyCbQCDAQARAAYJbhyCbQCDAQAAAA==.',
Dh='Dhvecx:BAAALgAECgUJBgABLgAECgYJDQABAAAAAA==.',
Di='Dilbo:BAAALgAECgIJBAABLgAFFAUJGgAJABkVAA==.Diomed:BAAALgAECgEJAQAAAA==.Diqon:BAABLgAECn84AAMOAAkJDRusKQA3AgAOAAkJDRusKQA3AgAUAAcJtxSgHABDAQAAAA==.Disturbedtwo:BAAALgAECgYJCgAAAA==.',
Do='Dolphinz:BAACLgAFFH8PAAIHAAQJ0RTiJABHAQAHAAQJ0RTiJABHAQAuAAQKfy8AAwcACAmqIU8YANcCAAcACAmqIU8YANcCAB8AAgnpCiI8AE4AAAAA.Doryadni:BAAALgADCgcJBgAAAA==.',
Dr='Dragonpede:BAABLgAECn85AAIZAAkJFiAnCAC9AgAZAAkJFiAnCAC9AgAAAA==.Dragonwarior:BAABLgAECn8fAAIPAAkJ6humIwCyAQAPAAkJ6humIwCyAQAAAA==.Drakindees:BAAALgAECgQJBAABLgAECgcJJAARAPYhAA==.Drakkyn:BAABLgAECn8aAAIPAAYJTR2TJwCZAQAPAAYJTR2TJwCZAQAAAA==.Drakonus:BAAALgAECgUJCQAAAA==.Dread:BAAALgADCgQJBAAAAA==.Drosuu:BAAALgAECgEJAQAAAA==.Druish:BAACLgAFFH8eAAIcAAUJZCMrAwChAQAcAAUJZCMrAwChAQAuAAQKfywAAxwACQk0JlwAAHMDABwACQk0JlwAAHMDACAAAgkOD5ksAGEAAAAA.Drykkr:BAABLgAECn8mAAISAAkJnBYeFQDlAQASAAkJnBYeFQDlAQAAAA==.',
Du='Dullahan:BAAALgAECgUJBgAAAA==.Dunstie:BAAALgADCgEJAQABLgAECgUJFwAUADEeAA==.Durrik:BAAALgADCgcJBwAAAA==.',
['Dà']='Dàsh:BAAALgAECgYJBgABLgAECggJFgAGAPEfAA==.',
Ea='Eatrocks:BAAALgADCggJCAAAAA==.',
Ed='Edorn:BAAALgAECgUJBQAAAA==.',
Ef='Efn:BAAALgAECgYJEwAAAA==.',
El='Elcrys:BAABLgAECn8aAAIhAAcJ3BZTMAC9AQAhAAcJ3BZTMAC9AQAAAA==.Elion:BAAALgAECgEJAQAAAA==.Ellyra:BAAALgAECgYJCwAAAA==.Elpollo:BAABLgAECn8kAAMRAAcJ9iGUQgBwAgARAAcJ9iGUQgBwAgAiAAEJshe1HAA6AAAAAA==.Elvar:BAAALgAECgQJDwAAAA==.',
Em='Emmdwemm:BAAALgAECgQJCAAAAA==.',
En='Enoki:BAAALgAECgQJBAAAAA==.',
Ep='Ephelia:BAACLgAFFH8NAAIFAAQJHR7NFwBhAQAFAAQJHR7NFwBhAQAuAAQKfxcAAwUACAkjG4oiAA8CAAUACAkjG4oiAA8CAAQAAQmMA/eUACAAAAAA.Epitome:BAABLgAECn8gAAIRAAgJBhfkUQDKAQARAAgJBhfkUQDKAQAAAA==.',
Er='Erid:BAAALgAECgcJEQAAAA==.',
Et='Etude:BAAALgADCgEJAQAAAA==.',
Ev='Evelyndel:BAAALgAECgYJBwAAAA==.Evergrey:BAABLgAECn8ZAAITAAcJsAxALwA5AQATAAcJsAxALwA5AQAAAA==.Evermoons:BAABLgAECn8jAAIhAAkJVxmkEgCWAgAhAAkJVxmkEgCWAgAAAA==.Evodaka:BAAALgAECgIJAwAAAA==.',
Fa='Falaria:BAAALgAECgQJBAAAAA==.Falasdaer:BAABLgAECn8ZAAILAAgJ6CHIEgCPAgALAAgJ6CHIEgCPAgAAAA==.Fallansting:BAAALgAECgkJCwAAAA==.Falstaff:BAABLgAECn8fAAISAAkJxhXzEgD9AQASAAkJxhXzEgD9AQAAAA==.Fartshooter:BAAALgAECgYJEQAAAA==.Fatterblunt:BAACLgAFFH8aAAIJAAUJGRXwFgAvAQAJAAUJGRXwFgAvAQAuAAQKfyYAAgkACQk3ILYNAMACAAkACQk3ILYNAMACAAAA.',
Fe='Fedner:BAABLgAECn8XAAIFAAcJSQ+bSQBUAQAFAAcJSQ+bSQBUAQAAAA==.Feldar:BAABLgAECn8uAAIHAAkJ7B+pEQDAAgAHAAkJ7B+pEQDAAgAAAA==.Fend:BAAALgADCgQJBAAAAA==.Feyredarling:BAAALgAECgMJAwAAAA==.',
Fi='Fists:BAACLgAFFH8MAAISAAQJgBzXFwA1AQASAAQJgBzXFwA1AQAuAAQKfyoAAxIABgmEI44WAFQCABIABgmEI44WAFQCABYABAk3EqtUAL4AAAAA.Fizzbeard:BAAALgADCgcJCgAAAA==.Fizzical:BAAALgADCgkJDwAAAA==.Fizzleclaw:BAABLgAECn8WAAMcAAYJDxwFEgCRAQAcAAYJDxwFEgCRAQAJAAIJkw2aYABiAAAAAA==.Fizzleded:BAAALgAECgQJBQABLgAECgYJFgAcAA8cAA==.Fizzleflare:BAAALgADCgkJCQAAAA==.',
Fl='Flightrisk:BAAALgAECgQJBgABLgAECgkJDQABAAAAAA==.Florisa:BAABLgAECn8jAAIHAAgJ5RzFMwAQAgAHAAgJ5RzFMwAQAgAAAA==.',
Fo='Fool:BAAALgAECgUJBQABLgAFFAMJAwABAAAAAA==.Fordi:BAABLgAECn8tAAMEAAkJ/R3ACgCRAgAEAAkJ/R3ACgCRAgAjAAMJ9RQcKQBSAAAAAA==.Forendor:BAAALgAECgIJAwAAAA==.Fourdy:BAABLgAECn8wAAIFAAcJCRkxNACxAQAFAAcJCRkxNACxAQAAAA==.',
Fr='Fragdoll:BAAALgAECgQJCgAAAA==.Freakinlarry:BAAALgADCgEJAQAAAA==.Freakinoak:BAABLgAECn8jAAIhAAgJKBI5MQC4AQAhAAgJKBI5MQC4AQAAAA==.Free:BAABLgAECn8XAAMLAAgJlxH/TgB2AQALAAcJlxH/TgB2AQAkAAUJ9Ap3IACAAAAAAA==.Froost:BAACLgAFFH8LAAIOAAQJJhe/RwA4AQAOAAQJJhe/RwA4AQAuAAQKfxgAAg4ACQlfHvRMAAwCAA4ACQlfHvRMAAwCAAAA.',
Fu='Funkflex:BAAALgAECgEJAQABLgAECggJFwALAJcRAA==.Furvert:BAAALgAECgkJDQAAAA==.Fushi:BAAALgAECgEJAQAAAA==.',
Ga='Gandis:BAAALgAECgkJEgAAAA==.Gapper:BAACLgAFFH8GAAIQAAMJQxjnFQD3AAAQAAMJQxjnFQD3AAAuAAQKf0QAAhAACQnYJB0BAEkDABAACQnYJB0BAEkDAAAA.Gargodath:BAAALgAECgMJAwAAAA==.',
Gi='Gimbó:BAAALgADCgQJBgAAAA==.',
Gl='Glamour:BAAALgADCgEJAgAAAA==.Glestaar:BAABLgAECn8pAAMCAAgJnxwJIwAtAgACAAgJnxwJIwAtAgADAAIJRQuFfABSAAAAAA==.Glyr:BAAALgAECgYJCgAAAA==.',
Go='Goingrouge:BAAALgAECgYJCgAAAA==.Goldabelle:BAAALgAECgYJCgAAAA==.Goonkin:BAAALgAECgUJBQABLgAFFAMJBgAQAEMYAA==.Gorlami:BAABLgAFFH8GAAIHAAMJZA6kWgDBAAAHAAMJZA6kWgDBAAAAAA==.Gothelf:BAAALgAFFAIJBAAAAA==.Gothri:BAAALgAECgcJCQABLgAECgcJFQAZAJAVAA==.Gothstraza:BAABLgAECn8VAAIZAAcJkBW6MABLAQAZAAcJkBW6MABLAQAAAA==.Gottemgood:BAAALgADCgUJBQAAAA==.',
Gr='Grimli:BAABLgAECn8fAAIFAAkJsQ7POgCRAQAFAAkJsQ7POgCRAQAAAA==.Growth:BAABLgAECn8ZAAMTAAkJNAn6JAB6AQATAAkJNAn6JAB6AQAeAAYJohDvLABBAQAAAA==.',
Gu='Gurthcaptian:BAAALgAECgQJBAAAAA==.',
Gy='Gyatso:BAAALgADCgMJAwAAAA==.',
['Gá']='Gárròsh:BAAALgAECgYJBgAAAA==.',
Ha='Haerin:BAAALgAECgIJAgABLgAFFAQJEQAGADMkAA==.Happykilmøre:BAAALgAECgQJBAABLgAECgkJEgABAAAAAA==.Harnel:BAABLgAECn8nAAIHAAcJWQMH2wC+AAAHAAcJWQMH2wC+AAAAAA==.Haseo:BAAALgAECgQJBQAAAA==.Hattorihanzo:BAAALgAECgUJCwAAAA==.',
He='Healeymonstr:BAAALgADCgIJAgAAAA==.Healmart:BAABLgAECn8VAAIeAAYJZAduOQD4AAAeAAYJZAduOQD4AAAAAA==.Heartëater:BAAALgADCgYJBgAAAA==.Hellinyoface:BAAALgADCgUJBQAAAA==.Heymage:BAAALgADCgkJCQAAAA==.',
Hi='Himothyy:BAAALgAECgQJBAAAAA==.',
Ho='Holypeetch:BAAALgADCgYJBgAAAA==.Hoofpics:BAAALgADCggJEAAAAA==.Hordedefect:BAAALgAECgEJAQABLgAECgkJDQABAAAAAA==.Hoyer:BAAALgAECgkJEwAAAA==.',
Hu='Humbledrink:BAAALgAECgEJAQAAAA==.',
Im='Impact:BAAALgADCgcJCgAAAA==.',
In='Inflícted:BAAALgAFFAIJBAAAAA==.Innoscent:BAAALgAECgYJBgAAAA==.Inzo:BAAALgAFFAEJAQAAAA==.',
Io='Iove:BAABLgAECn8aAAIVAAkJZBV5GQANAgAVAAkJZBV5GQANAgAAAA==.',
Ja='Jahsahm:BAAALgAECgcJEQAAAA==.Jajung:BAAALgADCgMJAwAAAA==.Jakub:BAABLgAECn8cAAIUAAkJFhTlDwDcAQAUAAkJFhTlDwDcAQABLgAFFAQJDwAQABASAA==.Jakuren:BAAALgADCgYJBgAAAA==.Jamjam:BAAALgADCgYJCQAAAA==.',
Je='Jesit:BAABLgAECn8WAAIaAAYJpRMoFQBUAQAaAAYJpRMoFQBUAQAAAA==.',
Jh='Jhonn:BAAALgADCgkJCQABLgAECgkJOwAlAAMfAA==.',
Ji='Jingles:BAAALgADCgYJBgAAAA==.',
Jj='Jjada:BAACLgAFFH8FAAMLAAQJtQv7QAD6AAALAAQJ9Qf7QAD6AAAkAAEJdBU5DABAAAAuAAQKfxsAAwsACAk1I6oUAIECAAsACAm0IaoUAIECACQABgmeIYAFAE0CAAAA.',
Jo='Johnwolf:BAAALgAECgUJEgAAAA==.',
Jy='Jyade:BAABLgAECn8pAAMKAAgJZg0sCQCMAQAKAAgJWA0sCQCMAQAmAAUJnwifCAD6AAAAAA==.Jynoria:BAAALgADCgcJDAAAAA==.',
Ka='Kainlok:BAAALgADCgIJAgAAAA==.Kaiserice:BAAALgAECgcJEAAAAA==.Kamarra:BAABLgAECn8dAAIZAAcJOwfjRADuAAAZAAcJOwfjRADuAAAAAA==.Kamencider:BAABLgAECn8dAAIRAAcJ8RBAgABaAQARAAcJ8RBAgABaAQAAAA==.Kamidala:BAAALgAECgIJAgAAAA==.Kankles:BAACLgAFFH8FAAIJAAQJ3x4eEQBXAQAJAAQJ3x4eEQBXAQAuAAQKfyoAAgkACAnuIq4IAKUCAAkACAnuIq4IAKUCAAAA.Karva:BAAALgAECgIJAgAAAA==.Katabetta:BAAALgADCgMJAwAAAA==.',
Ke='Kentukee:BAAALgADCgcJCgABLgAECggJJgAQADASAA==.Kernelpanic:BAACLgAFFH8ZAAMOAAUJzxy1LwBlAQAOAAUJzxy1LwBlAQAnAAEJ/gULGwA7AAAuAAQKfycAAg4ACQkCIrsjAFQCAA4ACQkCIrsjAFQCAAAA.Kessho:BAAALgAECgYJDwABLgAFFAQJDwAQABASAA==.Kevynn:BAAALgADCgMJAgAAAA==.Keyoshi:BAAALgAECgYJBgAAAA==.',
Ki='Kickrocks:BAAALgADCgUJBwAAAA==.Kilerforlife:BAAALgAECgYJCwAAAA==.Kilowog:BAAALgADCgUJCAAAAA==.Kilpally:BAAALgAECgYJBwAAAA==.Kintra:BAAALgADCgIJAgAAAA==.Kirin:BAAALgADCgEJAQAAAA==.Kirkle:BAABLgAECn8xAAIYAAkJrBzsAQCOAgAYAAkJrBzsAQCOAgAAAA==.Kithara:BAAALgAECgEJAwAAAA==.',
Ko='Kovie:BAAALgADCggJCAAAAA==.Kovy:BAAALgAFFAIJAgAAAA==.Kovya:BAAALgADCgYJBwAAAA==.',
Kr='Krelel:BAAALgADCgIJAgAAAA==.Krukar:BAAALgADCgYJDAAAAA==.',
Ku='Kubo:BAAALgAECgYJBgABLgAFFAQJDwAQABASAA==.',
Ky='Kydroga:BAAALgAECgYJEAAAAA==.Kynaria:BAAALgADCgMJAwAAAA==.Kynsia:BAAALgADCgQJBgAAAA==.',
La='Lamörak:BAABLgAECn8pAAIHAAkJuB4DEwC1AgAHAAkJuB4DEwC1AgAAAA==.Landrick:BAABLgAECn8wAAIOAAkJCRncKgAyAgAOAAkJCRncKgAyAgAAAA==.Lastotem:BAAALgADCgEJAQAAAA==.Lastshot:BAAALgAECggJEAAAAA==.Latest:BAAALgADCgQJBAAAAA==.Lavaevoker:BAAALgADCgcJBwABLgAECggJHAASAAgGAA==.Lavasaurus:BAABLgAECn8hAAMaAAgJkhrsEACWAQAaAAYJUxrsEACWAQAZAAgJSA9CKACAAQAAAA==.',
Le='Leafstorm:BAAALgAECgYJDwAAAA==.Lehala:BAAALgADCgQJBAAAAA==.Lektar:BAAALgAECgUJBQABLgAECgYJEwABAAAAAA==.Leloosh:BAAALgADCgkJDAABLgAFFAIJBAABAAAAAA==.Lemon:BAABLgAECn8gAAIYAAcJ3gomEwDsAAAYAAcJ3gomEwDsAAAAAA==.Leokenoso:BAABLgAECn8hAAIkAAkJCxItCADLAQAkAAkJCxItCADLAQAAAA==.Lesclaypool:BAAALgAECgcJBwAAAA==.Lessalia:BAAALgAECgEJAQAAAA==.Lewd:BAAALgAECgQJBgAAAA==.Lexen:BAAALgADCgEJAQAAAA==.',
Li='Lifebloomz:BAABLgAECn8lAAIhAAkJaAsNPQB9AQAhAAkJaAsNPQB9AQAAAA==.Lifesabeach:BAAALgAECgMJAwAAAA==.Lilfluffcc:BAAALgAECgQJBAAAAA==.Lissana:BAAALgADCgUJBQAAAA==.',
Lo='Lockward:BAAALgAECgIJAQAAAA==.Loidvoid:BAAALgADCgkJDQAAAA==.Lorblor:BAABLgAECn8hAAIkAAgJYx+DAwB5AgAkAAgJYx+DAwB5AgAAAA==.Lorerun:BAAALgADCgUJCAAAAA==.Lowang:BAABLgAECn8dAAISAAkJnRM4IgB5AQASAAkJnRM4IgB5AQAAAA==.Lowmein:BAAALgAECggJEwAAAA==.',
Lu='Lucÿfer:BAAALgAFFAIJAwAAAA==.Lumie:BAAALgAECgYJDAAAAA==.Luminisx:BAAALgADCgMJAwAAAA==.Lunafox:BAABLgAECn8kAAIFAAgJOh60EACgAgAFAAgJOh60EACgAgAAAA==.Lunamae:BAABLgAECn8fAAIiAAgJTRR5AwDBAQAiAAgJTRR5AwDBAQAAAA==.Lupacho:BAAALgAECgcJDgAAAA==.Luvvyyaa:BAABLgAECn8/AAMGAAkJ+h2xCADAAgAGAAkJ+h2xCADAAgAeAAgJrRNeFgD2AQAAAA==.Luvyya:BAAALgAECgYJEAABLgAECgkJPwAGAPodAA==.Luvyyaa:BAAALgAECgQJBQABLgAECgkJPwAGAPodAA==.',
Ly='Lyrinaku:BAABLgAECn8UAAIGAAcJWRVQNgBkAQAGAAcJWRVQNgBkAQAAAA==.Lythomancer:BAABLgAECn8fAAIYAAgJiQ82DQA+AQAYAAgJiQ82DQA+AQAAAA==.',
Ma='Maddeena:BAABLgAECn8aAAIFAAYJHAclbQDaAAAFAAYJHAclbQDaAAAAAA==.Maddy:BAABLgAECn8aAAMWAAkJWBrsEAAaAgAWAAgJYh3sEAAaAgASAAIJ0QYlagBXAAAAAA==.Maelyssa:BAAALgADCgMJAwAAAA==.Magicmangge:BAAALgADCgYJBgABLgAFFAEJAQABAAAAAA==.Makeitclap:BAAALgAECgMJBAABLgAECgcJHQARAPEQAA==.Malidian:BAABLgAECn8dAAILAAkJdw/NRQCTAQALAAkJdw/NRQCTAQAAAA==.Matchadaddy:BAAALgAECgEJAwAAAA==.Maxohlx:BAACLgAFFH8TAAINAAYJuQuvJgBmAQANAAYJuQuvJgBmAQAuAAQKfysAAg0ACQn2G0IXAIACAA0ACQn2G0IXAIACAAAA.',
Mc='Mcmercie:BAAALgAECgkJCgAAAA==.',
Me='Mechacooter:BAAALgAFFAMJAwAAAA==.Meeko:BAAALgADCgUJBQABLgAFFAcJFQAaAC0fAA==.Megahertz:BAAALgADCgEJAQAAAA==.Megg:BAAALgADCggJEQAAAA==.Meilia:BAAALgADCgUJBwAAAA==.Mekari:BAABLgAECn8wAAIQAAkJxR1hBwCQAgAQAAkJxR1hBwCQAgAAAA==.Melchiorr:BAABLgAECn8kAAIXAAgJKxjGBgDsAQAXAAgJKxjGBgDsAQAAAA==.Melignant:BAAALgADCgEJAQAAAA==.Melosia:BAAALgADCgQJBwAAAA==.Melynne:BAABLgAECn89AAMFAAkJIxQwIAAhAgAFAAkJIxQwIAAhAgAEAAIJeATEgQBBAAAAAA==.Memmel:BAAALgADCgMJAwAAAA==.Meredeath:BAABLgAECn8UAAIJAAgJKg0uOgD3AAAJAAgJKg0uOgD3AAAAAA==.',
Mi='Micro:BAAALgAECgkJEwAAAA==.Microkeg:BAAALgAECgcJBAAAAA==.Microslash:BAAALgADCgMJAwABLgAECgkJEwABAAAAAA==.Minsoo:BAABLgAECn8ZAAIVAAgJIx1bEQBgAgAVAAgJIx1bEQBgAgAAAA==.Mistblade:BAAALgAECgQJCgABLgAECggJFwALAJcRAA==.Miststriker:BAAALgAECgUJCQAAAA==.',
Ml='Mlrglett:BAABLgAECn82AAMcAAgJACJmBACkAgAcAAgJACJmBACkAgAJAAEJihMfhgAqAAAAAA==.Mlrglo:BAAALgADCgcJCQAAAA==.',
Mo='Moisturizeme:BAAALgAECgQJBgAAAA==.Mojomaker:BAABLgAECn8UAAIFAAUJuRP6WQAZAQAFAAUJuRP6WQAZAQAAAA==.Moojitsu:BAAALgADCgMJAwAAAA==.Mormegil:BAABLgAECn8mAAIUAAgJcyF3BgCWAgAUAAgJcyF3BgCWAgAAAA==.Moshimoshi:BAACLgAFFH8RAAMFAAUJahLQGQBSAQAFAAUJahLQGQBSAQAEAAEJIQN+RQA1AAAuAAQKfxwAAwQACAmXG2cbADcCAAQABwkQHWcbADcCAAUABwkUCnRRAD8BAAAA.Motosake:BAAALgAECgQJBQAAAA==.',
Mu='Muffinlord:BAAALgAECgYJEQAAAA==.Munkeebutt:BAABLgAECn8gAAQQAAkJMQn3GAC5AQAQAAkJDQn3GAC5AQADAAcJYAcoUwD/AAACAAEJsQst1QAwAAAAAA==.Munkeefase:BAAALgADCgEJAQAAAA==.',
Na='Naberius:BAAALgAECgcJCgAAAA==.Naillil:BAAALgAECgEJAQAAAA==.Namiiswan:BAAALgADCgMJBQAAAA==.Natsuki:BAAALgADCgUJBwAAAA==.',
Ne='Nefarius:BAAALgAECgcJCwABLgAECgkJFAANAKcYAA==.Neflite:BAABLgAECn8eAAIYAAcJvwe5FQDUAAAYAAcJvwe5FQDUAAAAAA==.Nelfie:BAAALgAECgEJAQAAAA==.Nessará:BAAALgAECgYJEAAAAA==.',
Ni='Nineõseven:BAABLgAECn8YAAITAAcJixN9IADVAQATAAcJixN9IADVAQABLgAECgEJAQABAAAAAA==.Ninjapro:BAAALgAECgEJAQAAAA==.Nixia:BAAALgAECgQJBAAAAA==.',
No='Nodiddy:BAAALgAECgQJBQABLgAECgcJJAARAPYhAA==.',
Nu='Nuraga:BAABLgAECn8hAAMlAAgJlyHXBwCpAgAlAAcJCSTXBwCpAgAPAAEJ7hJCfABJAAAAAA==.',
Ob='Obeeone:BAAALgAECgEJAgAAAA==.',
On='Onasta:BAABLgAECn8hAAIOAAkJkx9yLQAmAgAOAAkJkx9yLQAmAgAAAA==.Onelastkiss:BAAALgAECgEJAQAAAA==.',
Op='Oprahheals:BAABLgAECn8cAAIHAAkJFB7zEADGAgAHAAkJFB7zEADGAgAAAA==.',
Or='Oreobeer:BAAALgAECgEJAQAAAA==.Oreomonster:BAAALgAECgcJEQAAAA==.Orquesta:BAAALgAECgQJCQAAAA==.',
Pa='Paccer:BAAALgAECgEJAQAAAA==.Pacerx:BAAALgAECgIJAgAAAA==.Pandaemonia:BAACLgAFFH8OAAIkAAQJsgxCBQDVAAAkAAQJsgxCBQDVAAAuAAQKfyIAAiQACQncDfURAAEBACQACQncDfURAAEBAAAA.Pandakyle:BAABLgAECn8XAAIVAAYJ5xcYNwBBAQAVAAYJ5xcYNwBBAQAAAA==.Pandexander:BAAALgADCgMJAwAAAA==.Panterå:BAAALgAECgEJAQAAAA==.Parts:BAABLgAECn8iAAIRAAgJtiGIIQDtAgARAAgJtiGIIQDtAgABLgAFFAUJFQAnALgdAA==.Patchmen:BAAALgAECgQJBAAAAA==.Pattilicious:BAABLgAECn8kAAIHAAkJZwuJXQCXAQAHAAkJZwuJXQCXAQAAAA==.',
Pe='Pepsizero:BAAALgAECgUJCwAAAA==.',
Ph='Phlesh:BAAALgAECgEJAgAAAA==.Phlvrabies:BAAALgADCgMJBQAAAA==.Phonedin:BAABLgAECn8jAAMbAAkJERmdBgCIAgAbAAkJERmdBgCIAgAZAAMJBhchSQCyAAAAAA==.Phoënix:BAACLgAFFH8PAAIFAAQJFBe/JAAYAQAFAAQJFBe/JAAYAQAuAAQKfyIAAwUACQmWHd8NAL4CAAUACQmWHd8NAL4CAAQAAwlkFKdfAJMAAAAA.',
Pi='Pieglaive:BAABLgAECn8jAAMMAAkJzSG/BQC3AgAMAAkJzSG/BQC3AgALAAIJuhZpwwB2AAAAAA==.Pierres:BAAALgAECggJCQAAAA==.Piondelth:BAAALgAECgcJEQAAAA==.',
Pl='Plantman:BAAALgAECgUJCQAAAA==.',
Po='Pointyboner:BAAALgADCgQJBAAAAA==.Poofort:BAAALgAECgYJCQAAAA==.Pooner:BAAALgADCgMJAwAAAA==.Porkins:BAAALgAECgMJAwAAAA==.Postoak:BAAALgAECgUJCgAAAA==.Powerochrist:BAABLgAECn8pAAIdAAkJ8BMxHQDzAQAdAAkJ8BMxHQDzAQAAAA==.',
Pr='Proxzy:BAAALgAECggJEgAAAA==.',
Pu='Pubessalad:BAABLgAECn8cAAIHAAYJyRMamQAiAQAHAAYJyRMamQAiAQAAAA==.Puddin:BAAALgADCgQJBgAAAA==.Puffytaco:BAAALgAECgYJCwABLgAECgkJIwAHANccAA==.',
Qu='Qualek:BAABLgAECn8XAAIlAAkJMRJfEAADAgAlAAkJMRJfEAADAgAAAA==.Quilue:BAABLgAECn8dAAIRAAkJMw5YUQDLAQARAAkJMw5YUQDLAQAAAA==.',
Ra='Rannmagnison:BAABLgAECn8rAAIHAAgJuwbmlAApAQAHAAgJuwbmlAApAQAAAA==.Raquoon:BAABLgAECn8UAAIlAAUJuQ/HKwCzAAAlAAUJuQ/HKwCzAAAAAA==.Rasonia:BAAALgAECgYJBgABLgAECgkJMgAeAJYXAA==.Ratfu:BAAALgADCgcJDQAAAA==.Raumulus:BAAALgAECgEJAQAAAA==.Razjin:BAABLgAECn8aAAMFAAkJeiPsCQDaAgAFAAkJeiPsCQDaAgAEAAEJ/wpdkgAnAAAAAA==.',
Re='Reapér:BAAALgAECgkJBQAAAA==.Reze:BAACLgAFFH8TAAIWAAQJdx/TBwBqAQAWAAQJdx/TBwBqAQAuAAQKfxYAAhYACAlYHt0NAEECABYACAlYHt0NAEECAAEuAAUUCQkqAAwAfx8A.',
Rh='Rhaeynera:BAABLgAECn8lAAIbAAcJ5AWlDwDtAAAbAAcJ5AWlDwDtAAAAAA==.Rhyel:BAAALgADCgIJAgAAAA==.Rhyno:BAAALgADCgkJCQAAAA==.Rhysedwyn:BAAALgADCgkJCQABLgAECgEJAQABAAAAAA==.',
Ri='Riezen:BAAALgAECgEJAwAAAA==.Ringol:BAAALgAECgQJCgABLgAECgYJDgABAAAAAA==.Rinorik:BAABLgAECn83AAMNAAkJQiAaDQDOAgANAAkJQiAaDQDOAgAYAAYJCRn2FACjAQAAAA==.Rizzdor:BAAALgADCgcJCAABLgAECgkJEgABAAAAAA==.',
Ro='Rockbiter:BAAALgAECgEJAgAAAA==.Rockhhard:BAABLgAECn8eAAIFAAkJxx5TGABbAgAFAAkJxx5TGABbAgAAAA==.Roeken:BAABLgAECn8xAAIPAAkJdRSAGwDtAQAPAAkJdRSAGwDtAQAAAA==.Rollingman:BAAALgAECgYJEgAAAA==.',
Ru='Rudyrots:BAAALgAECgEJAQABLgAFFAEJAgABAAAAAA==.Rudyshoots:BAAALgAFFAEJAgAAAA==.Rum:BAAALgAECgMJAwAAAA==.',
Ry='Rygaard:BAABLgAECn84AAIlAAkJHyI3AwDoAgAlAAkJHyI3AwDoAgAAAA==.Rystic:BAAALgADCgkJCQAAAA==.Ryutiz:BAABLgAECn8sAAIDAAkJbSJNAQD+AgADAAkJbSJNAQD+AgAAAA==.Ryward:BAAALgADCgcJBwAAAA==.Ryyuk:BAAALgAECgMJBAABLgAECggJFwALAJcRAA==.',
Sa='Sacridas:BAAALgAECgEJAQABLgAECgkJLAADAG0iAA==.Sako:BAAALgADCgUJCgAAAA==.Samsó:BAABLgAECn8WAAMHAAkJqxbEaQCrAQAHAAkJqxbEaQCrAQAdAAQJ3BQNagDSAAAAAA==.Sapharina:BAABLgAECn8yAAIeAAkJlhe6DAB3AgAeAAkJlhe6DAB3AgAAAA==.Sassgrip:BAAALgADCgEJAQABLgAECgYJDAABAAAAAA==.Sassier:BAAALgAECgYJDAAAAA==.Sathenaz:BAAALgADCgcJCQAAAA==.',
Sc='Scarcy:BAACLgAFFH8RAAIIAAUJKRmLCACjAQAIAAUJKRmLCACjAQAuAAQKfzMAAwgACQliGl0NACwCAAgACQliGl0NACwCACYAAwmXCHUYAFsAAAAA.',
Se='Seacotton:BAABLgAECn8aAAMoAAkJlhu/BQCIAgAoAAkJ7Bq/BQCIAgAPAAcJoBVaQACjAQAAAA==.Searfang:BAACLgAFFH8SAAIEAAQJVBb9FQAwAQAEAAQJVBb9FQAwAQAuAAQKfzMAAwQACQlpIA0KAJoCAAQACQlpIA0KAJoCAAUAAQljE0euADYAAAAA.Seariel:BAAALgAECgUJBgAAAA==.Seatea:BAAALgADCgkJCQABLgAECgkJOAAZACAhAA==.Selestra:BAAALgAFFAIJAgAAAA==.Selinise:BAAALgAECgUJBQAAAA==.Sematic:BAAALgAFFAEJAQABLgAFFAYJFAARAJMbAA==.Senpai:BAAALgAECgQJBAAAAA==.Seraphymm:BAAALgADCgEJAQAAAA==.',
Sh='Shadowjacker:BAACLgAFFH8RAAILAAUJ+xqLKgA9AQALAAUJ+xqLKgA9AQAuAAQKfzgAAgsACQkmIYIHAFEDAAsACQkmIYIHAFEDAAAA.Shadowmidget:BAABLgAECn8WAAINAAkJ3BahVwDBAQANAAkJ3BahVwDBAQAAAA==.Shadrielis:BAABLgAECn80AAMeAAkJHRswCQC4AgAeAAkJHRswCQC4AgAGAAIJVQ3VbgBsAAAAAA==.Shanlao:BAAALgAECgIJAgABLgAFFAUJGgANAO8QAA==.Shirkka:BAAALgADCgMJBAAAAA==.Shurihito:BAABLgAECn8lAAIHAAkJiR5fGACTAgAHAAkJiR5fGACTAgAAAA==.',
Si='Sieron:BAABLgAECn8UAAIOAAYJ/RwLfABFAQAOAAYJ/RwLfABFAQAAAA==.Silaslunark:BAAALgAECggJCgAAAA==.Sinkrow:BAAALgAECgYJBgAAAA==.Sixpack:BAABLgAECn8aAAIhAAkJbQ6QNQChAQAhAAkJbQ6QNQChAQAAAA==.',
Sk='Skarigar:BAAALgAECgEJAwAAAA==.Skeeterson:BAAALgADCgUJBwAAAA==.Skiððles:BAAALgAECgYJBgABLgAECgkJHQAEANIUAA==.Skytec:BAAALgADCgMJAwAAAA==.Skëëts:BAABLgAECn8cAAQeAAgJSBBYIACcAQAeAAgJJBBYIACcAQATAAEJuwQ0eAAoAAAGAAEJ5gb+ZQAoAAAAAA==.Skùrvypete:BAAALgADCgEJAQABLgAECgkJHQAEANIUAA==.',
Sl='Slampoof:BAAALgAECgQJCQAAAA==.Slamslayer:BAAALgAECgEJAQAAAA==.Sleez:BAAALgAECgYJDAAAAA==.Sloodraga:BAAALgADCgYJBgAAAA==.',
Sm='Smallgregory:BAAALgAECgYJDAAAAA==.',
Sn='Sneakdead:BAAALgAECgcJCgAAAA==.Sneakerzz:BAAALgADCgQJBAAAAA==.Sneakfury:BAAALgAECgYJCgABLgAECgcJCgABAAAAAA==.Sneeler:BAAALgAECgEJAQAAAA==.Snowscayia:BAACLgAFFH8KAAQJAAUJ4AlkHwD8AAAJAAQJSQhkHwD8AAAhAAMJOROWLgDXAAAgAAIJIQpiDwB6AAAuAAQKfyoABAkACQkbGDMnAMUBAAkACAk2GjMnAMUBACEABwn1FD87ALgBACAAAQlhCcs6ADoAAAAA.',
So='Solanar:BAABLgAECn85AAMdAAgJsiMcDQCaAgAdAAgJsiMcDQCaAgAHAAUJlSGZYwCJAQAAAA==.Solesin:BAAALgAFFAEJAQABLgAFFAUJEwAaADIXAA==.Solm:BAAALgADCgkJCQAAAA==.Solmina:BAABLgAECn83AAIRAAkJIh4QGACvAgARAAkJIh4QGACvAgAAAA==.Somniatis:BAAALgAECgEJAQAAAA==.Soulciopath:BAAALgAECgUJCAAAAA==.Souljin:BAAALgADCgMJAwAAAA==.',
Sp='Spicypants:BAAALgADCgMJAwAAAA==.Spicytaco:BAAALgAECgUJCgABLgAECgkJIwAHANccAA==.Spookuleli:BAAALgADCggJCwAAAA==.Sprinklewiz:BAAALgADCgMJAwAAAA==.',
Sq='Squadie:BAABLgAECn8vAAICAAgJ+gqnVgByAQACAAgJ+gqnVgByAQAAAA==.Squanchs:BAACLgAFFH8TAAIFAAUJnRqtEACXAQAFAAUJnRqtEACXAQAuAAQKfx4AAwUACQlkHygMAL8CAAUACQlkHygMAL8CAAQAAQkGAK6hAAEAAAEuAAQKBwkcACEAkxsA.Squanchy:BAABLgAECn8cAAIhAAcJkxtxPACyAQAhAAcJkxtxPACyAQAAAA==.Squisquee:BAAALgADCgcJBwAAAA==.',
Sr='Srbojangles:BAAALgAECgYJBgABLgAECgcJJAARAPYhAA==.Srry:BAABLgAECn8VAAIPAAcJsBrUKQATAgAPAAcJsBrUKQATAgAAAA==.',
St='Stinkvile:BAAALgAECgEJAQAAAA==.Stonebraid:BAAALgADCgEJAQAAAA==.Sturdy:BAAALgADCgEJAQAAAA==.',
Su='Sukuna:BAAALgAECgYJCAAAAA==.Sundance:BAAALgAECggJEAAAAA==.Surmise:BAACLgAFFH8UAAIRAAYJkxvNGgC7AQARAAYJkxvNGgC7AQAuAAQKfzIAAxEACQkBJW4DAGQDABEACQkBJW4DAGQDACIABAlVIDYHAA4BAAAA.Sust:BAAALgAFFAEJAQABLgAFFAYJFAARAJMbAA==.',
Sw='Swayzeetrain:BAACLgAFFH8NAAMdAAQJ+iLwDQCYAQAdAAQJ+iLwDQCYAQAHAAEJpAxQMABUAAAuAAQKfxkAAwcACQkCHCxmALQBAAcABwkgGixmALQBAB0ACAlQH+A2AKABAAAA.',
['Sü']='Süß:BAAALgAFFAIJAgABLgAFFAQJBQALALULAA==.',
Ta='Tabius:BAABLgAECn8mAAMgAAkJXR6WBwAsAgAgAAkJXR6WBwAsAgAJAAMJyw6WUwCPAAAAAA==.Talkingtaco:BAABLgAECn8jAAIHAAkJ1xwKGgCJAgAHAAkJ1xwKGgCJAgAAAA==.Taln:BAAALgAECgEJAQABLgAECggJJgAUAHMhAA==.Talìa:BAAALgADCgIJAgABLgAECgEJAQABAAAAAA==.Tareul:BAAALgADCgIJAgAAAA==.Tarn:BAAALgAECgkJEgAAAA==.',
Te='Temok:BAABLgAECn8aAAIHAAYJQgyCrAACAQAHAAYJQgyCrAACAQAAAA==.',
Th='Thiccbush:BAAALgAECgEJAQAAAA==.Thirielnet:BAAALgAECgUJBwAAAA==.This:BAAALgAECgEJAQAAAA==.Thorisdead:BAAALgAECgEJAQABLgAECggJHAASAAgGAA==.Thorkell:BAAALgADCgUJBQAAAA==.Thosen:BAAALgAECgQJBAAAAA==.',
Ti='Tinkaballah:BAAALgAECgcJDgAAAA==.Tipy:BAAALgADCgUJBQAAAA==.',
To='Tore:BAACLgAFFH8OAAICAAMJdhwwFQCwAAACAAMJdhwwFQCwAAAuAAQKfzEAAgIACQn5IacJAPwCAAIACQn5IacJAPwCAAAA.Totemangge:BAAALgAFFAEJAQAAAA==.',
Tr='Trifectas:BAAALgADCgcJFwAAAA==.Trinadel:BAACLgAFFH8KAAIJAAQJMg2AHAARAQAJAAQJMg2AHAARAQAuAAQKfx0AAgkACAmnHS8PAK0CAAkACAmnHS8PAK0CAAAA.Träitors:BAAALgADCgcJEwAAAA==.Tråitors:BAABLgAECn82AAMNAAYJciK1MwDyAQANAAYJciK1MwDyAQAYAAEJAAA0ZQBFAAABLgADCgcJEwABAAAAAA==.',
Ts='Tsarevich:BAABLgAECn8UAAIiAAUJAQkTCgC2AAAiAAUJAQkTCgC2AAAAAA==.',
Tu='Tugtheshaman:BAABLgAECn8dAAIFAAgJoxgmGgBGAgAFAAgJoxgmGgBGAgAAAA==.',
Tw='Twileaf:BAABLgAECn8pAAIhAAcJFgfKaQDWAAAhAAcJFgfKaQDWAAAAAA==.Twoinchisbig:BAABLgAECn9LAAIlAAgJPR3YCQAxAgAlAAgJPR3YCQAxAgAAAA==.',
Ty='Typhoidmary:BAABLgAECn8XAAMNAAgJhAmIggBVAQANAAcJhAmIggBVAQAYAAEJAAAOdgAuAAABLgAFFAMJAwABAAAAAA==.',
['Té']='Térror:BAAALgAECgcJDwAAAA==.',
Un='Uncool:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Unholyz:BAAALgAECgUJCAAAAA==.',
Ur='Ursoc:BAABLgAECn82AAMJAAgJVRRUHwCfAQAJAAgJVRRUHwCfAQAhAAYJRxFPUQAnAQAAAA==.Urteg:BAAALgADCgkJFAAAAA==.',
Uu='Uub:BAAALgAECgIJAgAAAA==.',
Va='Vairekor:BAAALgADCggJDgABLgAFFAUJGgANAO8QAA==.Valdria:BAAALgADCgUJBQAAAA==.Vanillaçake:BAAALgAECgYJBwAAAA==.Vanishja:BAAALgAECgYJDwAAAA==.Varkbyte:BAABLgAECn8UAAIGAAUJfBXKKwBHAQAGAAUJfBXKKwBHAQAAAA==.Varrik:BAACLgAFFH8PAAMPAAUJfCCnDQBjAQAPAAUJfCCnDQBjAQAoAAMJ7hi5GADUAAAuAAQKfyYAAw8ACAnjIooJABUDAA8ACAnjIooJABUDACgABgmcG+0YAGkBAAAA.',
Ve='Vec:BAAALgAECgYJDQAAAA==.Velamor:BAABLgAECn8YAAQkAAYJzgueFwC6AAAkAAYJ5gqeFwC6AAAMAAMJygk5VQCTAAALAAMJagpFugCDAAAAAA==.Velaria:BAAALgADCgcJBwAAAA==.',
Vi='Violynt:BAAALgADCgEJAQAAAA==.',
Vo='Volieu:BAABLgAECn8gAAIiAAgJSBSpAwC4AQAiAAgJSBSpAwC4AQAAAA==.Volklin:BAABLgAECn8gAAMFAAgJywgiTwA/AQAFAAgJywgiTwA/AQAEAAYJIgkLTgDNAAAAAA==.Voyageurs:BAABLgAECn8XAAIgAAgJZBVyDQCqAQAgAAgJZBVyDQCqAQAAAA==.',
Vy='Vyrka:BAAALgAECgMJDQAAAA==.',
Wa='Wallstreet:BAAALgAECgUJBQAAAA==.Waterdweller:BAAALgAECgEJAwAAAA==.',
We='Wegl:BAAALgAECgUJDgAAAA==.Werebear:BAAALgADCgMJAwABLgAECgEJAQABAAAAAA==.Werewithal:BAAALgADCgYJCwABLgAECggJJgAQADASAA==.Wesleypipes:BAAALgAECgEJAQAAAA==.Wetfloorsign:BAAALgAECgYJEQAAAA==.',
Wh='Wholeymilk:BAAALgADCgMJAwAAAA==.',
Wi='Wiindsslashh:BAAALgAECgYJBwAAAA==.Wilbur:BAAALgADCgQJBQAAAA==.Windslash:BAAALgAECgIJAgAAAA==.',
Wo='Wonderx:BAAALgADCgIJAgAAAA==.Wonyoung:BAACLgAFFH8RAAIGAAQJMyQ5BwCdAQAGAAQJMyQ5BwCdAQAuAAQKfzIAAgYACQnzI9kBAFgDAAYACQnzI9kBAFgDAAAA.',
Wr='Wraithwok:BAAALgAECgUJBQAAAA==.',
Wu='Wuthrad:BAAALgADCgQJBAAAAA==.',
Xa='Xala:BAABLgAECn8UAAMUAAkJbw2OIAAfAQAUAAgJUA6OIAAfAQAnAAIJ+AceIgBlAAAAAA==.Xalah:BAAALgAECgcJCgAAAA==.Xalaz:BAACLgAFFH8UAAMNAAUJHxEgQgAgAQANAAUJHxEgQgAgAQAYAAEJVwJgGgBGAAAuAAQKfx0AAw0ACQlXHHQ2ADICAA0ACAlXHHQ2ADICABgAAgkLFGNSAHcAAAAA.Xanaris:BAAALgADCgEJAQABLgAFFAIJCgAOAL0mAA==.Xandumbra:BAAALgADCgEJAQAAAA==.Xarosea:BAACLgAFFH8MAAIHAAQJPxPbMgApAQAHAAQJPxPbMgApAQAuAAQKfyoAAgcABwk6JPYYANMCAAcABwk6JPYYANMCAAAA.',
Xe='Xelojr:BAAALgADCgkJHAAAAA==.',
Xh='Xhael:BAAALgADCgEJAQAAAA==.',
Xi='Xia:BAABLgAECn86AAIGAAkJqRkzFQA0AgAGAAkJqRkzFQA0AgAAAA==.',
Xo='Xoilkick:BAAALgAECgYJEAAAAA==.Xoilwings:BAAALgAECgEJAQAAAA==.Xooiill:BAAALgAECgcJEAAAAA==.',
Xp='Xpacer:BAAALgAECgcJEwAAAA==.',
['Xê']='Xêna:BAAALgAECgIJAgAAAA==.',
Ye='Yekira:BAAALgADCgEJAgAAAA==.Yellowsnøw:BAABLgAECn8rAAIRAAgJLxYkTQDXAQARAAgJLxYkTQDXAQAAAA==.',
Yu='Yumeshade:BAAALgAECgYJCgAAAA==.',
Za='Zaila:BAAALgAECgUJBQAAAA==.Zal:BAAALgAECgYJBgABLgAFFAUJFAAfAKAWAA==.Zamari:BAAALgAECgYJDAAAAA==.Zanzabar:BAABLgAECn8VAAIgAAkJwgrGEACgAQAgAAkJwgrGEACgAQAAAA==.Zathmage:BAAALgADCgMJAwAAAA==.Zaxin:BAABLgAECn8WAAMGAAgJSA4TJgBxAQAGAAgJSA4TJgBxAQATAAUJiAQeSwCtAAAAAA==.',
Ze='Zelfie:BAAALgADCgUJBQAAAA==.Zellda:BAAALgAECgUJCAAAAA==.Zeros:BAABLgAECn8WAAIRAAgJAxl9RwDpAQARAAgJAxl9RwDpAQAAAA==.',
Zo='Zoerina:BAAALgAECgcJDwAAAA==.Zoobilong:BAAALgAECgUJEgAAAA==.',
Zx='Zxak:BAABLgAECn8zAAIMAAgJUyatAwDwAgAMAAgJUyatAwDwAgAAAA==.',
Zy='Zyahk:BAAALgADCgQJBQAAAA==.Zynn:BAAALgAECgEJAgAAAA==.',
['Zë']='Zën:BAAALgAECgEJAQABLgAFFAIJBAABAAAAAA==.',
['Ða']='Ðashÿ:BAAALgAECgMJAwABLgAECggJFgAGAPEfAA==.',
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
