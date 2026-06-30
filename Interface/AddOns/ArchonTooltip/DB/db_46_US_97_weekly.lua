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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Elemental','Shaman-Restoration','Priest-Holy','Rogue-Subtlety','Druid-Balance','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Assassination','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Warrior-Fury','Hunter-Survival','Monk-Brewmaster','Priest-Shadow','Monk-Mistweaver','Monk-Windwalker','Mage-Frost','Druid-Guardian','Warlock-Affliction','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Druid-Feral','Paladin-Holy','Priest-Discipline','Druid-Restoration','Paladin-Protection','Mage-Arcane','Shaman-Enhancement','DemonHunter-Vengeance','Warrior-Protection','Rogue-Outlaw','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abandonhope:BAAALgAECgMJAwABLgAECgkJEwABAAAAAA==.',
Ac='Accuser:BAAALgADCgEJAQAAAA==.Acky:BAAALgADCgUJBQAAAA==.',
Ad='Adwen:BAABLgAECn8iAAICAAgJYRlCYwCqAQACAAgJYRlCYwCqAQAAAA==.',
Ae='Aenimal:BAAALgAECgYJEAAAAA==.Aer:BAAALgADCgkJCQAAAA==.Aeronemon:BAAALgAECgEJAgAAAA==.',
Ag='Agamemmnon:BAAALgAECgEJAQAAAA==.',
Ai='Airill:BAAALgADCgQJBQAAAA==.',
Ak='Akforty:BAABLgAECn8fAAMDAAkJIiHNCgDvAgADAAkJIiHNCgDvAgAEAAIJoBV7eABfAAAAAA==.Akittymeow:BAABLgAECn8bAAMFAAkJuw/YRgAYAQAFAAgJKQ/YRgAYAQAGAAMJiwWcqQB2AAAAAA==.',
Al='Aldredevon:BAAALgAECgEJAQAAAA==.Aleshock:BAAALgAECgkJEQAAAA==.Alidar:BAAALgAECgcJEwAAAA==.Alphaboner:BAAALgADCgYJBwAAAA==.Altairis:BAAALgAECgEJAgAAAA==.Altartoy:BAABLgAECn8hAAIHAAgJ6Qq+NwAeAQAHAAgJ6Qq+NwAeAQAAAA==.Althunter:BAACLgAFFH8NAAIEAAQJUiFjEQBOAQAEAAQJUiFjEQBOAQAuAAQKfxsAAgQACAneIcwGACICAAQACAneIcwGACICAAAA.',
Am='Amanita:BAAALgAECgQJBAABLgAECgkJEQABAAAAAA==.Amelina:BAAALgAECgYJDgAAAA==.Amerit:BAAALgAECgEJAQAAAA==.Amorir:BAACLgAFFH8RAAICAAQJlQPmaADdAAACAAQJlQPmaADdAAAuAAQKf1oAAgIACQnwFakHADUBAAIACQnwFakHADUBAAAA.Amorit:BAABLgAECn8WAAIDAAcJYRDrdQBUAQADAAcJYRDrdQBUAQAAAA==.Amorydalias:BAAALgAECgUJBgAAAA==.Amozon:BAAALgADCgEJAQAAAA==.',
An='Anamortem:BAAALgAECgMJAwABLgAECgkJIQAIAAcZAA==.Anastala:BAABLgAECn8rAAIJAAkJ5RXwGQD8AQAJAAkJ5RXwGQD8AQAAAA==.Andeddo:BAACLgAFFH8HAAIKAAMJRAwZJgDLAAAKAAMJRAwZJgDLAAAuAAQKfxcAAwoACQkxFiNfAKsBAAoABglFFyNfAKsBAAsABglaEVYqAAUBAAAA.Angchu:BAAALgADCgQJBAAAAA==.Angelmàker:BAAALgAECgMJBAABLgADCgcJEwABAAAAAA==.Angelmäker:BAAALgAECgYJCwABLgADCgcJEwABAAAAAA==.Annesta:BAABLgAECn8hAAMIAAkJBxnHGADUAQAIAAkJ0hjHGADUAQAMAAEJ9xa0JQA9AAAAAA==.',
Ap='Apostus:BAAALgADCgcJDgAAAA==.Apothica:BAAALgAECgUJBgAAAA==.',
Aq='Aquafox:BAABLgAECn8yAAMGAAkJMx+mCgAMAwAGAAkJMx+mCgAMAwAFAAQJERUmTgD9AAAAAA==.',
Ar='Archnemesis:BAAALgAECgQJBAAAAA==.Archontas:BAABLgAECn8kAAIJAAgJkSHrCgClAgAJAAgJkSHrCgClAgAAAA==.Ariodh:BAABLgAECn87AAMNAAkJLSaAAgBgAwANAAkJLSaAAgBgAwAOAAUJpB9eJACaAQAAAA==.Ariodr:BAAALgAFFAEJAgAAAA==.Arkaline:BAAALgAECgQJBAABLgAECgUJBQABAAAAAA==.Artuarry:BAACLgAFFH8kAAIPAAcJFBKUDQArAQAPAAcJFBKUDQArAQAuAAQKfyYAAg8ACQlGH2MfAGgCAA8ACQlGH2MfAGgCAAAA.Aryndus:BAABLgAECn8lAAICAAkJcx7eHACYAgACAAkJcx7eHACYAgAAAA==.',
At='Athenà:BAAALgAECgUJBQAAAA==.',
Av='Avocado:BAABLgAECn8jAAMDAAkJnCUzDgDgAgADAAkJHiMzDgDgAgAEAAcJVCKaCwCuAQAAAA==.',
Ax='Axelaw:BAAALgADCgQJBAAAAA==.',
Ay='Ayrz:BAAALgAECgIJAgAAAA==.',
Az='Azaria:BAAALgADCgIJAgAAAA==.',
Ba='Baddjujumon:BAABLgAECn8XAAMFAAgJ0gSAWADaAAAFAAgJ0gSAWADaAAAGAAEJoAEf9AAdAAAAAA==.Baileyhowl:BAAALgAECgEJBQAAAA==.Bammie:BAAALgADCgYJCgAAAA==.Bananuth:BAAALgAECgIJAwABLgAFFAcJIwAKAFocAA==.Banthr:BAABLgAECn8XAAIQAAkJNw4tLgCYAQAQAAkJNw4tLgCYAQAAAA==.Barkert:BAAALgADCgQJAwAAAA==.Baroke:BAAALgAECgMJBwABLgAECggJIQAHAOkKAA==.Barokoshama:BAAALgAECgcJEQAAAA==.Basaltytaco:BAAALgADCgEJAQAAAA==.Battleworm:BAAALgADCgkJEwABLgAFFAMJAwABAAAAAA==.',
Bb='Bbalrd:BAACLgAFFH8JAAIKAAMJ0xtYggADAQAKAAMJ0xtYggADAQAuAAQKfxcAAgoACQmiF3xOANcBAAoACQmiF3xOANcBAAAA.',
Be='Bearglie:BAAALgAECggJDgAAAA==.Beepers:BAAALgAECgYJBgAAAA==.Beezelpup:BAAALgAECgYJCQABLgAECgkJFwAQADcOAA==.',
Bi='Bigcow:BAAALgAECgUJCQAAAA==.',
Bl='Blackolives:BAAALgAECgkJEAAAAA==.Bladesp:BAAALgAECgYJDQABLgAECgkJGQANAAkSAA==.Blads:BAAALgAECgEJAgAAAA==.Blondefu:BAAALgAECgUJCwAAAA==.Bloodybonne:BAAALgADCgcJBwAAAA==.Bloodyell:BAAALgAECgYJBgAAAA==.Bloore:BAAALgAECgMJAwABLgAECgkJLAAEAG0iAA==.Bluejuly:BAAALgAECgUJBQAAAA==.Blutø:BAAALgAFFAIJAgAAAA==.',
Bo='Boflex:BAAALgADCgQJBgAAAA==.Bomboclat:BAAALgAECgUJCwAAAA==.Bonesknows:BAAALgADCgEJAQAAAA==.Boofy:BAAALgAECgMJAwABLgAECgkJFgAPANwWAA==.Borhoag:BAAALgADCgEJAQABLgAECggJDwABAAAAAA==.Bowwie:BAACLgAFFH8SAAMRAAQJKBSzFgAbAQARAAQJDxCzFgAbAQADAAMJZRBibwDCAAAuAAQKfz4ABAMACQnZHy0GACsDAAMACQkTHi0GACsDABEACQkZGpQAAE4CAAQAAQkVAxWTACcAAAAA.',
Br='Britney:BAAALgADCgkJCQAAAA==.Brotherfrey:BAAALgAECggJEQAAAA==.Bruish:BAABLgAFFH8MAAISAAQJtwzFDQAWAQASAAQJtwzFDQAWAQAAAA==.Bruty:BAAALgAECgEJAgAAAA==.',
Bu='Bubbadoo:BAABLgAECn8lAAIJAAkJzQ9fIwCvAQAJAAkJzQ9fIwCvAQAAAA==.Buddy:BAABLgAECn8ZAAITAAYJoRI7OgAqAQATAAYJoRI7OgAqAQABLgAECgkJKAALACghAA==.Bulan:BAABLgAECn9KAAIUAAkJuCW6AgCcAwAUAAkJuCW6AgCcAwAAAA==.',
Bw='Bweninger:BAAALgAECgEJAQAAAA==.',
['Bô']='Bôôsted:BAABLgAECn8iAAIFAAkJ8BTfIAAIAgAFAAkJ8BTfIAAIAgABLgAFFAEJAQABAAAAAA==.',
Ca='Caistan:BAAALgADCgYJCAAAAA==.Calyopi:BAAALgAFFAIJAgAAAA==.Candypants:BAABLgAECn8jAAQUAAkJxRa6GwA6AgAUAAkJxRa6GwA6AgASAAcJ9A6VPAAJAQAVAAMJ2At3aQCBAAAAAA==.Caoth:BAAALgAECgYJEwAAAA==.Cappilon:BAABLgAECn8fAAIWAAkJCiJWFwDNAgAWAAkJCiJWFwDNAgAAAA==.Carcus:BAABLgAECn8vAAIPAAkJiR8AAQCNAgAPAAkJiR8AAQCNAgAAAA==.Carmila:BAAALgADCgEJAQAAAA==.Cayleedah:BAABLgAECn8vAAIEAAkJ5wwNEgA6AQAEAAkJ5wwNEgA6AQAAAA==.Cayssaris:BAABLgAECn8WAAIXAAgJbBlrDwDwAQAXAAgJbBlrDwDwAQAAAA==.',
Cc='Cc:BAABLgAECn8WAAQYAAYJPBPsDgBCAQAYAAUJ9BPsDgBCAQAZAAYJKwstIwA+AQAPAAQJzhP5tQDtAAAAAA==.',
Ce='Ceeti:BAABLgAECn84AAMaAAkJICGNCADOAgAaAAkJICGNCADOAgAbAAIJeAYcQABpAAAAAA==.Celandrelia:BAAALgAECgUJBQABLgAECggJLAAcAEQXAA==.',
Ch='Chaewon:BAAALgAFFAEJAQABLgAFFAQJEQAHADMkAA==.Channeria:BAAALgAECgEJAQAAAA==.Chaoticoreo:BAABLgAECn80AAMOAAkJYB7qCQCLAgAOAAkJYB7qCQCLAgANAAQJ4w9rrQCzAAAAAA==.Chappedlips:BAAALgAECgkJBwAAAA==.Chareyne:BAABLgAECn8ZAAIHAAgJ5RFyJgC5AQAHAAgJ5RFyJgC5AQAAAA==.Cheetor:BAAALgAECgMJAwABLgAFFAQJEwARACoWAA==.Cheezytaco:BAAALgAECgYJDgABLgAECgkJJAACACMdAA==.Chidge:BAAALgADCggJCwAAAA==.Chikila:BAABLgAECn8jAAMZAAgJBhlsBwDeAQAZAAgJBhlsBwDeAQAPAAMJeAyQ4wCVAAAAAA==.Chilliflakez:BAABLgAECn8XAAIUAAcJ1Q7fSABJAQAUAAcJ1Q7fSABJAQAAAA==.Chro:BAAALgAECgcJBwABLgAECgkJOQAFAHofAA==.',
Ci='Cindezar:BAAALgADCgMJAwAAAA==.',
Cl='Clementyn:BAABLgAECn8WAAICAAcJOBB8zgD1AAACAAcJOBB8zgD1AAAAAA==.Cleyi:BAABLgAECn8qAAIHAAkJMw3GKgByAQAHAAkJMw3GKgByAQAAAA==.',
Co='Coldpasta:BAAALgAECgYJDgABLgAFFAIJBAABAAAAAA==.Colonoscopy:BAAALgAECgMJBAAAAA==.Coreyy:BAAALgADCgUJBwAAAA==.Corva:BAACLgAFFH8YAAIPAAUJKxKTVwAYAQAPAAUJKxKTVwAYAQAuAAQKfyoAAg8ACQnpFbJDANABAA8ACQnpFbJDANABAAAA.Cosairi:BAAALgAFFAEJAQAAAA==.Cougztroll:BAABLgAECn83AAMXAAkJlRUMEwDCAQAXAAkJlRUMEwDCAQAdAAYJ/gsuKADNAAAAAA==.',
Cr='Crazaki:BAAALgADCgEJAQAAAA==.Crosseye:BAAALgADCgMJBwAAAA==.Crossie:BAAALgADCgEJAQAAAA==.',
Ct='Ctd:BAAALgAECgEJAQABLgAECgkJOAAaACAhAA==.',
Cu='Curfluffin:BAAALgADCgEJAQAAAA==.Cuttercupx:BAAALgAECgQJBQABLgAECgkJEwABAAAAAA==.',
Da='Dahn:BAAALgAECgIJAgAAAA==.Dakadin:BAABLgAECn8mAAMeAAkJ+yPKEgB7AgAeAAkJ+yPKEgB7AgACAAQJ7hef3gDgAAAAAA==.Daranne:BAACLgAFFH8jAAICAAUJaxbZQwAjAQACAAUJaxbZQwAjAQAuAAQKfysAAgIACQn5Gxc/ACkCAAIACQn5Gxc/ACkCAAAA.Darkenedstar:BAAALgAECgYJDQABLgAECgYJEAABAAAAAA==.Darksoulstwo:BAAALgADCgMJAwAAAA==.Dasbeans:BAABLgAECn8cAAMaAAkJNAmyRwAMAQAaAAgJPQqyRwAMAQAcAAIJkgHvRgARAAAAAA==.Dashy:BAABLgAECn8WAAMHAAgJ8R8YFAA2AgAHAAgJVBoYFAA2AgAfAAYJ4B6xFgAiAgAAAA==.Datran:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.',
De='Deaduglie:BAABLgAECn84AAMPAAkJbBYvNwD8AQAPAAkJbBYvNwD8AQAZAAEJMQjvcQA0AAAAAA==.Delamyr:BAAALgADCggJCAAAAA==.Deliandora:BAAALgAECgQJCAAAAA==.Delusional:BAAALgAECgcJDwAAAA==.Delynique:BAAALgADCgEJAQABLgAECgkJLAAEAG0iAA==.Demonx:BAAALgAECgEJAQAAAA==.Denaric:BAABLgAECn8hAAMgAAgJ+xiQKgABAgAgAAcJkBmQKgABAgAJAAcJJA7OOwAiAQAAAA==.Dergen:BAAALgAECgkJCwABLgAECgkJEwABAAAAAA==.Destroyevsky:BAABLgAECn8gAAIQAAYJSwI3gQBzAAAQAAYJSwI3gQBzAAAAAA==.Detonate:BAABLgAECn8aAAIWAAYJbhyTfwB4AQAWAAYJbhyTfwB4AQAAAA==.',
Dh='Dhpoo:BAAALgADCgUJBAAAAA==.Dhvecx:BAAALgAECgUJBgABLgAECgYJDQABAAAAAA==.',
Di='Dilbo:BAAALgAFFAIJAgABLgAFFAcJJAAJAAgbAA==.Diomed:BAAALgAECgEJAQAAAA==.Diqoff:BAAALgAECgIJAwAAAA==.Diqon:BAABLgAECn84AAMKAAkJDRtsNAAtAgAKAAkJDRtsNAAtAgALAAcJtxSPIwA3AQAAAA==.Disturbedtwo:BAAALgAECgYJCgAAAA==.',
Do='Dolphinz:BAACLgAFFH8XAAICAAUJ4BkJMABSAQACAAUJ4BkJMABSAQAuAAQKfzIAAwIACQn+IbcQAOECAAIACQn+IbcQAOECACEAAgnpCiI8AE4AAAAA.Doryadni:BAAALgADCgcJBgAAAA==.',
Dr='Draci:BAAALgAECgcJDQABLgAECgkJUQAQAJQeAA==.Dragondaddy:BAAALgAECgkJEAAAAA==.Dragonpede:BAACLgAFFH8KAAIaAAUJRRk7GQCcAQAaAAUJRRk7GQCcAQAuAAQKfzkAAhoACQkWIPcJALkCABoACQkWIPcJALkCAAAA.Dragonwarior:BAABLgAECn8fAAIQAAkJ6hv+LACeAQAQAAkJ6hv+LACeAQAAAA==.Drakindees:BAAALgAECgUJBQABLgAECgcJJAAWAPYhAA==.Drakkyn:BAABLgAECn8iAAIQAAkJ8BgVHQAFAgAQAAkJ8BgVHQAFAgAAAA==.Drakonus:BAAALgAECgUJCQAAAA==.Dread:BAAALgADCgQJBAAAAA==.Drosuu:BAAALgAECgEJAQAAAA==.Druish:BAACLgAFFH8lAAIXAAcJyCDBAgARAgAXAAcJyCDBAgARAgAuAAQKfywAAxcACQk0JqMAAG0DABcACQk0JqMAAG0DAB0AAgkOD5ksAGEAAAAA.Drykkr:BAABLgAECn8mAAISAAkJnBYiGQDdAQASAAkJnBYiGQDdAQAAAA==.',
Du='Dullahan:BAAALgAECgUJBgAAAA==.Dunstie:BAAALgADCgEJAQABLgAECgcJGwALACoeAA==.Durrik:BAAALgADCgcJBwAAAA==.Duuhh:BAAALgAECgEJAQAAAA==.',
['Dà']='Dàsh:BAAALgAECgYJBgABLgAECggJFgAHAPEfAA==.',
['Dä']='Däshy:BAAALgAECgEJAQABLgAECggJFgAHAPEfAA==.',
Ea='Eatrocks:BAAALgADCggJCAAAAA==.',
Ed='Edorn:BAAALgAECgUJBQAAAA==.',
Ef='Efn:BAAALgAECgYJEwAAAA==.',
El='Elcrys:BAABLgAECn8bAAIgAAcJ5higNgC+AQAgAAcJ5higNgC+AQAAAA==.Elentiya:BAAALgAECgkJDQAAAA==.Eleòs:BAAALgADCgYJBgAAAA==.Elion:BAAALgAECgEJAQAAAA==.Ellyra:BAABLgAFFH8IAAIDAAMJiwVLbwDDAAADAAMJiwVLbwDDAAAAAA==.Elpollo:BAABLgAECn8kAAMWAAcJ9iGUQgBwAgAWAAcJ9iGUQgBwAgAiAAEJshe1HAA6AAAAAA==.Elsinn:BAAALgAECgIJAgAAAA==.Elvar:BAABLgAECn8XAAIWAAYJlAZdGABtAAAWAAYJlAZdGABtAAAAAA==.',
Em='Emmdwemm:BAAALgAECgQJCgAAAA==.',
En='Enetash:BAAALgAECgIJAgAAAA==.Enoki:BAAALgAECgQJBAAAAA==.',
Ep='Ephelia:BAACLgAFFH8iAAIGAAUJfSaEAwC5AQAGAAUJfSaEAwC5AQAuAAQKfxkAAwYACQlfGooiAA8CAAYACQlfGooiAA8CAAUAAQmMA/eUACAAAAAA.Epitome:BAABLgAECn8pAAIWAAkJsRarPgAhAgAWAAkJsRarPgAhAgAAAA==.',
Er='Erid:BAAALgAECgcJEQAAAA==.',
Et='Etude:BAAALgADCgEJAQAAAA==.',
Ev='Evelyndel:BAAALgAECgYJBwAAAA==.Evergrey:BAABLgAECn8ZAAITAAcJsAwBOwAmAQATAAcJsAwBOwAmAQAAAA==.Evermoons:BAABLgAECn8jAAIgAAkJVxl0FgCUAgAgAAkJVxl0FgCUAgAAAA==.Evodaka:BAAALgAECgIJAwABLgAECgkJJgAeAPsjAA==.',
Fa='Falaria:BAAALgAECgQJBAAAAA==.Falasdaer:BAABLgAECn8lAAMNAAkJvSKLFQCXAgANAAgJQCKLFQCXAgAOAAQJAiLqHgCDAQAAAA==.Fallansting:BAABLgAECn8WAAINAAcJ0hoNOwDbAQANAAcJ0hoNOwDbAQAAAA==.Falstaff:BAABLgAECn8fAAISAAkJxhWpFgD1AQASAAkJxhWpFgD1AQAAAA==.Fartshooter:BAAALgAECgYJEQAAAA==.Fatterblunt:BAACLgAFFH8kAAIJAAcJCBvREQCTAQAJAAcJCBvREQCTAQAuAAQKfy4AAgkACQk8I5QAAKECAAkACQk8I5QAAKECAAAA.',
Fe='Fedner:BAABLgAECn8XAAIGAAcJSQ+YWQBRAQAGAAcJSQ+YWQBRAQAAAA==.Feldar:BAABLgAECn84AAICAAkJyiHUDwDnAgACAAkJyiHUDwDnAgAAAA==.Fend:BAAALgADCgQJBAAAAA==.Feronite:BAAALgAECgYJCgABLgAFFAQJEgARACgUAA==.Feyredarling:BAAALgAECgMJAwAAAA==.',
Fi='Fists:BAACLgAFFH8MAAISAAQJgBxXIgAiAQASAAQJgBxXIgAiAQAuAAQKfyoAAxIABgmEI44WAFQCABIABgmEI44WAFQCABUABAk3EqtUAL4AAAAA.Fistweaver:BAAALgAECgIJAgAAAA==.Fizzbeard:BAAALgADCgcJCgAAAA==.Fizzical:BAAALgADCgkJFwAAAA==.Fizzleclaw:BAABLgAECn8jAAMXAAkJMR5OCQBWAgAXAAkJMR5OCQBWAgAJAAQJDRFtRwDuAAAAAA==.Fizzleded:BAAALgAECgQJBQABLgAECgkJIwAXADEeAA==.Fizzleflare:BAAALgADCgkJCQAAAA==.',
Fl='Flightrisk:BAAALgAECgQJBgABLgAECgkJEwABAAAAAA==.Flirbert:BAAALgADCgYJBgAAAA==.Florisa:BAABLgAECn8jAAICAAgJ5RyuQwD7AQACAAgJ5RyuQwD7AQAAAA==.',
Fo='Fool:BAAALgAFFAEJAQABLgAFFAMJAwABAAAAAA==.Fordi:BAABLgAECn85AAMFAAkJeh/oCgCyAgAFAAkJcR/oCgCyAgAjAAQJpRY4BwBTAAAAAA==.Forendor:BAAALgAECgMJBwAAAA==.Fourdy:BAABLgAECn8yAAIGAAcJkRlJQACsAQAGAAcJkRlJQACsAQAAAA==.',
Fr='Fragdoll:BAAALgAECgQJCgAAAA==.Freakinlarry:BAAALgADCgEJAQAAAA==.Freakinoak:BAACLgAFFH8IAAIgAAMJ5AhfEACCAAAgAAMJ5AhfEACCAAAuAAQKfy4AAiAACQmjFPAjACwCACAACQmjFPAjACwCAAAA.Fredboat:BAAALgAECgEJAgABLgAFFAIJCgAKAL0mAA==.Free:BAABLgAECn8ZAAMNAAkJCRJVQwC+AQANAAgJCRJVQwC+AQAkAAUJ9Ap3IACAAAAAAA==.Frenn:BAAALgAECgUJCAAAAA==.Froost:BAACLgAFFH8cAAMKAAUJmBctHgDuAAAKAAQJmBctHgDuAAALAAEJAAA+VQAAAAAuAAQKfxgAAgoACQlfHvRMAAwCAAoACQlfHvRMAAwCAAAA.',
Fu='Funkflex:BAAALgAECgEJAQABLgAECgkJGQANAAkSAA==.Furvert:BAAALgAECgkJEwAAAA==.Fushi:BAAALgAECgEJAQAAAA==.',
Ga='Gandis:BAAALgAECgkJEgAAAA==.Gapper:BAACLgAFFH8TAAIRAAQJKhYYEgA3AQARAAQJKhYYEgA3AQAuAAQKf1QAAxEACQmNJUQBAFcDABEACQmNJUQBAFcDAAQAAgldGTwEAFMAAAAA.Gargodath:BAAALgAFFAIJAgAAAA==.',
Gi='Gielinor:BAAALgADCgIJAgAAAA==.Gimbó:BAAALgADCgQJBgAAAA==.',
Gl='Glamour:BAAALgADCgEJAgAAAA==.Glestaar:BAACLgAFFH8HAAIDAAMJrwwsZgDZAAADAAMJrwwsZgDZAAAuAAQKfykAAwMACAmfHGkwABoCAAMACAmfHGkwABoCAAQAAglFC4V8AFIAAAAA.Glitterpants:BAAALgAECgMJBAAAAA==.Glyr:BAAALgAECgYJCgAAAA==.',
Go='Goingrouge:BAAALgAECgYJCgAAAA==.Goldabelle:BAAALgAECgYJCgAAAA==.Goonkin:BAAALgAFFAIJAgABLgAFFAQJEwARACoWAA==.Gorlami:BAABLgAFFH8GAAICAAMJZA5AgwCuAAACAAMJZA5AgwCuAAAAAA==.Gothelf:BAAALgAFFAIJBAAAAA==.Gothri:BAAALgAECgcJCQABLgAECgcJFQAaAJAVAA==.Gothstraza:BAABLgAECn8VAAIaAAcJkBUXOgBEAQAaAAcJkBUXOgBEAQAAAA==.Gottemgood:BAAALgADCgUJBQAAAA==.',
Gr='Grayé:BAACLgAFFH8IAAIWAAMJwhnnbgAEAQAWAAMJwhnnbgAEAQAuAAQKfzIAAhYABwkyI+UzAEkCABYABwkyI+UzAEkCAAAA.Grimli:BAABLgAECn8jAAIGAAkJwQ8NRQCaAQAGAAkJwQ8NRQCaAQAAAA==.Growth:BAABLgAECn8ZAAMTAAkJNAm6LwBgAQATAAkJNAm6LwBgAQAfAAYJohBmOQArAQAAAA==.',
Gu='Gurthcaptian:BAAALgAECgQJBAAAAA==.',
Gy='Gyatso:BAAALgADCgMJAwAAAA==.',
['Gá']='Gárròsh:BAAALgAECgYJBgAAAA==.',
['Gô']='Gôôse:BAAALgAECgYJBgAAAA==.',
Ha='Haerin:BAAALgAECgIJAgABLgAFFAQJEQAHADMkAA==.Happykilmøre:BAAALgAECgQJBAABLgAECgkJEgABAAAAAA==.Harnel:BAABLgAECn80AAICAAkJSgQD2gDmAAACAAkJSgQD2gDmAAAAAA==.Haseo:BAAALgAECgkJDQAAAA==.Hashira:BAAALgADCggJCAAAAA==.Hattorihanzo:BAAALgAECggJDwAAAA==.',
He='Healeymonstr:BAAALgADCgIJAgAAAA==.Healmart:BAABLgAECn8ZAAIfAAkJdAZFOQAsAQAfAAkJdAZFOQAsAQAAAA==.Heartëater:BAAALgADCgYJBgAAAA==.Hellinyoface:BAAALgADCgUJBQAAAA==.Heymage:BAAALgADCgkJCQAAAA==.',
Hi='Himothyy:BAAALgAECgQJBAAAAA==.',
Ho='Holypeetch:BAAALgADCgYJBgAAAA==.Hoofpics:BAAALgAECgQJBAAAAA==.Hordedefect:BAAALgAECgEJAQABLgAECgkJEwABAAAAAA==.Hoyer:BAAALgAECgkJEwAAAA==.',
Hu='Hulkhogan:BAAALgAECggJDgAAAA==.Humbledrink:BAAALgAECgUJBgAAAA==.',
Im='Impact:BAAALgADCgcJCgAAAA==.',
In='Inflícted:BAACLgAFFH8VAAIfAAUJ7wusIQBCAQAfAAUJ7wusIQBCAQAuAAQKfxYAAh8ACQlFEU4ZAAcCAB8ACQlFEU4ZAAcCAAAA.Innoscent:BAAALgAECgYJBgAAAA==.Inzo:BAAALgAFFAEJAgAAAA==.',
Io='Iove:BAABLgAECn8aAAIUAAkJZBVYIQASAgAUAAkJZBVYIQASAgAAAA==.',
Ja='Jago:BAAALgADCggJCgAAAA==.Jahsahm:BAAALgAECgcJEQAAAA==.Jajung:BAAALgADCgMJAwAAAA==.Jakub:BAABLgAECn8hAAILAAkJqRezDgAgAgALAAkJqRezDgAgAgABLgAFFAQJEgARACgUAA==.Jakuren:BAAALgADCgYJBgAAAA==.Jamjam:BAAALgAECgUJBQAAAA==.',
Je='Jesit:BAABLgAECn8aAAIbAAYJ8hXgFAB9AQAbAAYJ8hXgFAB9AQAAAA==.',
Jh='Jhonn:BAAALgAECgEJAQABLgAECgkJRgAlAL8iAA==.',
Ji='Jingles:BAAALgADCgYJBgAAAA==.',
Jj='Jjada:BAACLgAFFH8JAAMNAAQJvw2wUQD4AAANAAQJvw2wUQD4AAAkAAEJdBXoEQA9AAAuAAQKfx0AAw0ACQnFIQgQAMICAA0ACQl0IAgQAMICACQABgmeIYAFAE0CAAAA.',
Jo='Johnwolf:BAABLgAECn8WAAICAAgJ8wIG9wDCAAACAAgJ8wIG9wDCAAAAAA==.',
Jy='Jyade:BAABLgAECn9BAAMMAAkJlRRnAACmAQAMAAkJlRRnAACmAQAmAAUJnwifCAD6AAAAAA==.Jynoria:BAAALgADCgcJDAAAAA==.',
Ka='Kainlok:BAAALgADCgIJAgAAAA==.Kaiserice:BAAALgAECgcJEAAAAA==.Kaliel:BAAALgAECgYJDgAAAA==.Kamarra:BAABLgAECn8fAAIaAAcJmgf7VADdAAAaAAcJmgf7VADdAAAAAA==.Kamencider:BAABLgAECn8dAAIWAAcJ8RAymABIAQAWAAcJ8RAymABIAQAAAA==.Kamidala:BAAALgAECgIJAgAAAA==.Kankles:BAACLgAFFH8FAAIJAAQJ3x40HAA5AQAJAAQJ3x40HAA5AQAuAAQKfyoAAgkACAnuIkELAJ8CAAkACAnuIkELAJ8CAAAA.Karbonn:BAAALgAECgkJAQAAAA==.Karhualaston:BAAALgAECgEJAQAAAA==.Karva:BAAALgAECgIJAwAAAA==.Katabetta:BAAALgADCgMJAwAAAA==.Kayati:BAABLgAECn8VAAIGAAkJBxL2AQAMAgAGAAkJBxL2AQAMAgABLgAFFAgJGwAPAOkLAA==.',
Ke='Kellmagnison:BAAALgAECgIJAgABLgAECgkJNgACADoIAA==.Kentukee:BAAALgAECgIJBAABLgAECgkJKQARALoSAA==.Kernelpanic:BAACLgAFFH8jAAMKAAcJWhynDgBfAQAKAAcJWhynDgBfAQAnAAEJ/gXaKwA6AAAuAAQKfysAAgoACQkCIlwgAIcCAAoACQkCIlwgAIcCAAAA.Kessho:BAAALgAECgYJDwABLgAFFAQJEgARACgUAA==.Kevynn:BAAALgADCgMJAgAAAA==.Keyoshi:BAAALgAECgYJBgAAAA==.',
Ki='Kickrocks:BAAALgAECgEJAQAAAA==.Kilerforlife:BAAALgAECgYJCwAAAA==.Kilgarnish:BAAALgADCgkJCQAAAA==.Kilowog:BAAALgADCgUJCAAAAA==.Kilpally:BAAALgAECgYJBwAAAA==.Kintra:BAAALgADCgIJAgAAAA==.Kirin:BAAALgAECgEJAQAAAA==.Kirkle:BAABLgAECn9eAAIZAAkJnx9PAQDfAgAZAAkJnx9PAQDfAgAAAA==.Kithara:BAAALgAECgEJAwAAAA==.',
Ko='Kovie:BAAALgADCggJCAAAAA==.Kovy:BAABLgAECn8VAAMLAAkJ8RZ6FADJAQALAAkJ8RZ6FADJAQAKAAEJCQQKJQEvAAAAAA==.Kovya:BAAALgADCgYJBwAAAA==.',
Kr='Krelel:BAAALgADCgIJAgAAAA==.Krukar:BAAALgADCgYJDAAAAA==.',
Ku='Kubo:BAAALgAECgYJBwABLgAFFAQJEgARACgUAA==.',
Ky='Kydroga:BAAALgAECgYJEAAAAA==.Kynaria:BAAALgAECgIJAgAAAA==.Kynsia:BAAALgADCgQJBgAAAA==.',
La='Lamörak:BAABLgAECn81AAICAAkJZiJYDgDzAgACAAkJZiJYDgDzAgAAAA==.Landrick:BAABLgAECn9AAAMKAAkJVR3bIQCAAgAKAAkJVR3bIQCAAgALAAEJ6BdUCQBCAAAAAA==.Lastotem:BAAALgADCgEJAQAAAA==.Lastshot:BAABLgAECn8XAAIDAAgJxhNQQQDeAQADAAgJxhNQQQDeAQAAAA==.Latest:BAAALgADCgQJBAAAAA==.Lavaevoker:BAAALgADCgcJBwABLgAECggJKAASAO8LAA==.Lavanor:BAAALgADCgIJAgAAAA==.Lavasaurus:BAABLgAECn8iAAQbAAgJkho7EwCVAQAbAAYJUxo7EwCVAQAaAAgJSA+aMAB1AQAcAAEJDRNtJAA6AAAAAA==.',
Le='Leafstorm:BAAALgAECgYJDwAAAA==.Lehala:BAAALgADCgQJBAAAAA==.Lektar:BAAALgAECgUJBQABLgAECgYJEwABAAAAAA==.Leloosh:BAAALgADCgkJDAABLgAFFAIJBAABAAAAAA==.Lemon:BAABLgAECn8sAAIZAAkJBRTlBgDuAQAZAAkJBRTlBgDuAQAAAA==.Leokenoso:BAABLgAECn8kAAIkAAkJEhN8CgC7AQAkAAkJEhN8CgC7AQAAAA==.Lesclaypool:BAAALgAECgcJCgAAAA==.Lessalia:BAAALgAECgEJAQAAAA==.Lewd:BAAALgAECgUJCgAAAA==.Lexor:BAAALgADCgQJBAAAAA==.',
Li='Lifebloomz:BAABLgAECn82AAIgAAkJDw60OgCpAQAgAAkJDw60OgCpAQAAAA==.Lifesabeach:BAAALgAECgMJAwAAAA==.Lilfluffcc:BAAALgAECgQJBAAAAA==.Lissana:BAAALgADCgUJBQAAAA==.',
Lo='Lockward:BAAALgAECgUJBwAAAA==.Loidvoid:BAAALgAECgYJCAAAAA==.Lorblor:BAABLgAECn8yAAQkAAkJSiFlAgDaAgAkAAkJCCBlAgDaAgAOAAcJMRr5AAAhAgANAAEJAACPJAAAAAAAAA==.Lorerun:BAAALgADCgUJCAAAAA==.Lowang:BAABLgAECn8dAAISAAkJnROvJwB0AQASAAkJnROvJwB0AQAAAA==.Lowmein:BAABLgAECn8UAAIGAAgJMR4lKgDlAQAGAAgJMR4lKgDlAQAAAA==.',
Lu='Lucÿfer:BAAALgAFFAIJAwAAAA==.Lumie:BAAALgAECgYJEQAAAA==.Luminisx:BAAALgADCgMJAwAAAA==.Lunafox:BAABLgAECn8oAAIGAAgJOh4KFgCaAgAGAAgJOh4KFgCaAgAAAA==.Lunamae:BAABLgAECn8pAAIiAAkJiRlsAwDtAQAiAAkJiRlsAwDtAQAAAA==.Lupacho:BAAALgAFFAIJAwAAAA==.Luvvyaa:BAAALgAECgcJBwABLgAECgkJYwAfALAhAA==.Luvvyyaa:BAABLgAECn9jAAMfAAkJsCFgAAALAwAfAAkJeB9gAAALAwAHAAkJ+h2xCADAAgAAAA==.Luvyya:BAAALgAECgYJEAABLgAECgkJYwAfALAhAA==.Luvyyaa:BAAALgAECgQJBQABLgAECgkJYwAfALAhAA==.',
Ly='Lyrinaku:BAABLgAECn8UAAIHAAcJWRVQNgBkAQAHAAcJWRVQNgBkAQAAAA==.Lythomancer:BAABLgAECn8kAAIZAAkJzg5aEAA8AQAZAAkJzg5aEAA8AQAAAA==.',
Ma='Maddeena:BAABLgAECn8nAAIGAAkJbAhRZQArAQAGAAkJbAhRZQArAQAAAA==.Maddy:BAABLgAECn8iAAMVAAkJWBopFQAQAgAVAAgJYh0pFQAQAgASAAkJexBPGgDTAQAAAA==.Maelyssa:BAAALgADCgMJAwAAAA==.Magicmangge:BAAALgADCgYJBgABLgAFFAEJAQABAAAAAA==.Makeitclap:BAAALgAECgMJBAABLgAECgcJHQAWAPEQAA==.Malidian:BAABLgAECn8dAAINAAkJdw9DVgCEAQANAAkJdw9DVgCEAQAAAA==.Matchadaddy:BAAALgAECgEJAwAAAA==.Maxohlx:BAACLgAFFH8bAAIPAAgJ6QvXKgCaAQAPAAgJ6QvXKgCaAQAuAAQKf0cAAg8ACQlnIdUIAA4DAA8ACQlnIdUIAA4DAAAA.',
Mc='Mcmercie:BAAALgAECgkJCgAAAA==.',
Me='Mechacooter:BAAALgAFFAMJAwAAAA==.Meeko:BAAALgADCgUJBQABLgAFFAgJJAAbAAQhAA==.Megahertz:BAAALgADCgEJAQAAAA==.Megg:BAAALgADCggJEQAAAA==.Meilia:BAAALgADCgUJBwAAAA==.Mekagatha:BAAALgADCgkJEgAAAA==.Mekari:BAABLgAECn8xAAIRAAkJxR0gCgB9AgARAAkJxR0gCgB9AgAAAA==.Melchiorr:BAACLgAFFH8RAAIYAAQJ2BlaAwBiAQAYAAQJ2BlaAwBiAQAuAAQKfykAAhgACQkRHEQFADgCABgACQkRHEQFADgCAAAA.Melignant:BAAALgADCgEJAQAAAA==.Melosia:BAAALgADCgQJBwAAAA==.Melynne:BAABLgAECn9HAAMGAAkJ4BWAIgBAAgAGAAkJ4BWAIgBAAgAFAAIJeATEgQBBAAAAAA==.Memmel:BAAALgADCgMJAwAAAA==.Meredeath:BAABLgAECn8UAAIJAAgJKg14RQD2AAAJAAgJKg14RQD2AAAAAA==.',
Mi='Micro:BAAALgAECgkJEwAAAA==.Microkeg:BAAALgAECgcJBAAAAA==.Microslash:BAAALgADCgMJAwABLgAECgkJEwABAAAAAA==.Minji:BAAALgAFFAEJAQABLgAFFAQJEQAHADMkAA==.Minsoo:BAACLgAFFH8OAAIUAAQJgRo2KgAfAQAUAAQJgRo2KgAfAQAuAAQKfxwAAhQACQkFHkUNAMcCABQACQkFHkUNAMcCAAAA.Mistblade:BAAALgAECgQJDAABLgAECgkJGQANAAkSAA==.Miststriker:BAAALgAECgUJCQAAAA==.Mistytaco:BAAALgAECgEJAQAAAA==.',
Ml='Mlrglett:BAABLgAECn9FAAMXAAkJqSJmAwDwAgAXAAkJqSJmAwDwAgAJAAEJihMfhgAqAAAAAA==.Mlrglo:BAAALgADCgcJCQAAAA==.',
Mm='Mmooney:BAAALgADCgIJAgABLgAECgkJFwAQADcOAA==.',
Mo='Moisturizeme:BAAALgAECgUJBQAAAA==.Mojomaker:BAABLgAECn8VAAIGAAYJAhL4XQBDAQAGAAYJAhL4XQBDAQAAAA==.Moojitsu:BAAALgADCgMJAwAAAA==.Mormegil:BAABLgAECn8oAAMLAAkJKCHKCACHAgALAAkJKCHKCACHAgAnAAEJeA3QOwAvAAAAAA==.Moshimoshi:BAACLgAFFH8XAAMGAAYJ6xE4HACKAQAGAAYJ6xE4HACKAQAFAAIJWAkwSQBrAAAuAAQKfx4AAwUACQl4HGcbADcCAAUACAlHHGcbADcCAAYACAlHCXRRAD8BAAAA.Motosake:BAAALgAECgQJBQAAAA==.',
Mu='Muffinlord:BAAALgAECgYJEQAAAA==.Munkeebutt:BAABLgAECn8gAAQRAAkJMQmJHgCoAQARAAkJDQmJHgCoAQAEAAcJYAcoUwD/AAADAAEJsQst1QAwAAAAAA==.Munkeefase:BAAALgADCgEJAQAAAA==.',
My='Myronis:BAAALgADCgIJAgAAAA==.Mythaera:BAAALgADCgYJBwAAAA==.',
Na='Naberius:BAABLgAECn8ZAAMaAAgJ6RP4LwB4AQAaAAgJ6RP4LwB4AQAbAAEJJgsqPgArAAABLgAECggJIQAgAPsYAA==.Naillil:BAAALgAECgEJAQAAAA==.Namiiswan:BAAALgADCgMJBQAAAA==.Nasmine:BAAALgADCgEJAQAAAA==.Natsuki:BAAALgADCgUJBwAAAA==.',
Ne='Nefarius:BAAALgAFFAEJAQAAAA==.Neflite:BAABLgAECn8eAAIZAAcJvwfdGwDGAAAZAAcJvwfdGwDGAAAAAA==.Nelfie:BAAALgAECgEJAQAAAA==.Nessará:BAABLgAECn8WAAIHAAYJQCHvFQAjAgAHAAYJQCHvFQAjAgAAAA==.',
Ni='Nineõseven:BAABLgAECn8YAAITAAcJixN9IADVAQATAAcJixN9IADVAQABLgAECgEJAQABAAAAAA==.Ninjapro:BAAALgAECgkJAgAAAA==.Nixia:BAAALgAECgQJBQAAAA==.',
No='Nodiddy:BAAALgAECgQJDAABLgAECgcJJAAWAPYhAA==.Nowari:BAAALgAECgQJBAABLgAECgkJKgAHADMNAA==.',
Nu='Nuraga:BAABLgAECn8hAAMlAAgJlyHXBwCpAgAlAAcJCSTXBwCpAgAQAAEJ7hK6lwBDAAAAAA==.',
Ob='Obeeone:BAAALgAECgEJAgAAAA==.Obviate:BAAALgAECgEJAQAAAA==.',
On='Onasta:BAABLgAECn8hAAIKAAkJkx+MOAAdAgAKAAkJkx+MOAAdAgAAAA==.Onelastkiss:BAAALgAECgEJAQAAAA==.',
Oo='Oogway:BAAALgAECgcJBwAAAA==.',
Op='Oprahheals:BAABLgAECn8cAAICAAkJFB6fGACvAgACAAkJFB6fGACvAgAAAA==.',
Or='Oreoagane:BAAALgAFFAEJAQAAAA==.Oreobeer:BAAALgAECgEJAQAAAA==.Oreomonster:BAAALgAECgcJEQAAAA==.Orquesta:BAAALgAECgQJCwAAAA==.',
Pa='Paccer:BAAALgAECgEJAQAAAA==.Pacerx:BAAALgAECgIJAgAAAA==.Pandaemonia:BAACLgAFFH8gAAIkAAUJpg/sBwDYAAAkAAUJpg/sBwDYAAAuAAQKfyQAAiQACQncDaMWAPIAACQACQncDaMWAPIAAAAA.Pandakyle:BAABLgAECn8XAAIUAAYJ5xc/SgBDAQAUAAYJ5xc/SgBDAQAAAA==.Pandexander:BAAALgADCgMJAwAAAA==.Panterå:BAAALgAECgEJAgAAAA==.Parts:BAABLgAECn8iAAIWAAgJtiGIIQDtAgAWAAgJtiGIIQDtAgABLgAFFAYJGQAnAMAYAA==.Patchmen:BAAALgAECgQJBAAAAA==.Pattilicious:BAABLgAECn8kAAICAAkJZwt3egB5AQACAAkJZwt3egB5AQAAAA==.',
Pe='Pepsizero:BAAALgAECgUJCwAAAA==.',
Ph='Phlesh:BAAALgAECgEJAgAAAA==.Phlvrabies:BAAALgADCgMJBQAAAA==.Phonedin:BAABLgAECn8jAAMcAAkJERmdBgCIAgAcAAkJERmdBgCIAgAaAAMJBhchSQCyAAAAAA==.Phoënix:BAACLgAFFH8YAAMGAAYJzxVJGQCdAQAGAAYJzxVJGQCdAQAFAAIJwQOcUABUAAAuAAQKfywAAwYACQmWHdMSALYCAAYACQmWHdMSALYCAAUABAnmGL5lALQAAAAA.',
Pi='Pieglaive:BAABLgAECn8jAAMOAAkJzSGyCAChAgAOAAkJzSGyCAChAgANAAIJuhZpwwB2AAAAAA==.Pierres:BAAALgAECgkJEgAAAA==.Piondelth:BAAALgAECgcJEQAAAA==.',
Pl='Plantman:BAAALgAECgYJDgAAAA==.',
Po='Pointyboner:BAAALgADCgYJCAAAAA==.Poofort:BAAALgAECgYJDwAAAA==.Pooner:BAAALgADCgMJAwAAAA==.Porkins:BAAALgAECgMJAwAAAA==.Postoak:BAAALgAECgUJCgAAAA==.Powerochrist:BAABLgAECn8xAAIeAAkJ+BllEACVAgAeAAkJ+BllEACVAgAAAA==.',
Pr='Priscila:BAAALgADCgYJBgAAAA==.Proxzy:BAABLgAECn8ZAAIFAAgJ/yD2DACWAgAFAAgJ/yD2DACWAgAAAA==.',
Pu='Pubessalad:BAABLgAECn8xAAICAAYJHB0GZQClAQACAAYJHB0GZQClAQAAAA==.Puddin:BAAALgADCgQJBwAAAA==.Puffytaco:BAAALgAECgYJCwABLgAECgkJJAACACMdAA==.',
Py='Pyrug:BAAALgAECgUJCAABLgAECgkJOAAPAGwWAA==.',
Qu='Qualek:BAABLgAECn8XAAIlAAkJMRJfEAADAgAlAAkJMRJfEAADAgAAAA==.Quilue:BAABLgAECn8hAAIWAAkJ0xOPQgAUAgAWAAkJ0xOPQgAUAgAAAA==.',
Ra='Rankak:BAAALgAFFAIJAgAAAA==.Rannmagnison:BAABLgAECn82AAICAAkJOgjXigBbAQACAAkJOgjXigBbAQAAAA==.Raquoon:BAABLgAECn8ZAAIlAAgJLQ9BHwA5AQAlAAgJLQ9BHwA5AQAAAA==.Rasonia:BAAALgAFFAEJAQABLgAFFAQJDwAfAOERAA==.Ratfu:BAAALgADCgcJDQAAAA==.Raumulus:BAAALgAECgkJEgAAAA==.Razjin:BAABLgAECn8aAAMGAAkJeiPsCQDaAgAGAAkJeiPsCQDaAgAFAAEJ/wqzsgAnAAAAAA==.',
Re='Reapér:BAAALgAECgkJBQAAAA==.Reckjames:BAAALgAECgEJAQAAAA==.Rene:BAAALgADCgYJBgAAAA==.Reze:BAACLgAFFH8XAAIVAAQJ5iCWDABeAQAVAAQJ5iCWDABeAQAuAAQKfxYAAhUACAlYHqcRADYCABUACAlYHqcRADYCAAEuAAUUCQlTAA4AQiYA.',
Rh='Rhaeynera:BAABLgAECn8uAAIcAAkJJAbzDwALAQAcAAkJJAbzDwALAQAAAA==.Rhyel:BAAALgADCgIJAgAAAA==.Rhyno:BAAALgADCgkJGwABLgAECgkJOAAPAOkgAA==.Rhysedwyn:BAAALgADCgkJEgABLgAECgEJAQABAAAAAA==.',
Ri='Riezen:BAABLgAECn8WAAIKAAkJ9hFXCgDoAAAKAAkJ9hFXCgDoAAAAAA==.Ringol:BAAALgAECgQJCgABLgAECgYJDgABAAAAAA==.Rinorik:BAABLgAECn84AAMPAAkJ6SDZEQC9AgAPAAkJQiDZEQC9AgAZAAYJNxz2FACjAQAAAA==.Rizzdor:BAAALgADCgcJCAABLgAECgkJEgABAAAAAA==.',
Ro='Roam:BAAALgAECgEJAQAAAA==.Rockbiter:BAAALgAECgEJAgAAAA==.Rockhhard:BAABLgAECn8eAAIGAAkJxx5eHwBUAgAGAAkJxx5eHwBUAgAAAA==.Roeken:BAABLgAECn86AAIQAAkJKRXYIADqAQAQAAkJKRXYIADqAQAAAA==.Rollingman:BAABLgAECn8XAAIUAAgJZxYtJQD6AQAUAAgJZxYtJQD6AQAAAA==.Roummi:BAAALgAECgEJAQAAAA==.',
Ru='Rudybear:BAAALgAECgEJAQABLgAFFAEJAgABAAAAAA==.Rudyrots:BAAALgAECgEJAQABLgAFFAEJAgABAAAAAA==.Rudyshoots:BAAALgAFFAEJAgAAAA==.Rui:BAAALgAECgMJAwAAAA==.Rum:BAAALgAECgMJAwAAAA==.',
Ry='Rybear:BAAALgAECgEJAQAAAA==.Rygaard:BAABLgAECn84AAIlAAkJHyIgBQDJAgAlAAkJHyIgBQDJAgAAAA==.Rystic:BAAALgADCgkJGQAAAA==.Ryutiz:BAABLgAECn8sAAIEAAkJbSLuAQDqAgAEAAkJbSLuAQDqAgAAAA==.Ryward:BAAALgADCgcJBwAAAA==.Ryyuk:BAAALgAECgMJBAABLgAECgkJGQANAAkSAA==.',
Sa='Sacridas:BAAALgAECgEJAQABLgAECgkJLAAEAG0iAA==.Sako:BAAALgADCgUJCgAAAA==.Salandar:BAAALgAECgIJAgABLgAECgkJNgACADoIAA==.Samsó:BAABLgAECn8ZAAMCAAkJrBjEaQCrAQACAAkJrBjEaQCrAQAeAAQJ3BQNagDSAAAAAA==.Sapharina:BAACLgAFFH8PAAIfAAQJ4RHzJgASAQAfAAQJ4RHzJgASAQAuAAQKfzMAAh8ACQmWF+4QAGQCAB8ACQmWF+4QAGQCAAAA.Sassgrip:BAAALgADCgEJAQABLgAECgcJEAABAAAAAA==.Sassier:BAAALgAECgcJEAAAAA==.Sathenaz:BAAALgADCgcJCQAAAA==.',
Sc='Scarcy:BAACLgAFFH8bAAIIAAgJFhQqCwDnAQAIAAgJFhQqCwDnAQAuAAQKfzMAAwgACQliGrAQAJ0CAAgACQliGrAQAJ0CACYAAwmXCHgeAFoAAAAA.',
Se='Seacotton:BAABLgAECn8fAAMoAAkJvxuaBwB9AgAoAAkJFRuaBwB9AgAQAAcJoBVaQACjAQAAAA==.Searfang:BAACLgAFFH8VAAIFAAUJVBZsIgARAQAFAAUJVBZsIgARAQAuAAQKfzgAAwUACQmEIYgHAOQCAAUACQmEIYgHAOQCAAYAAQljE8HTADYAAAAA.Seariel:BAAALgAECgUJBwAAAA==.Seatea:BAAALgADCgkJCQABLgAECgkJOAAaACAhAA==.Selestra:BAAALgAFFAIJAgAAAA==.Selinise:BAAALgAECgUJBQAAAA==.Sematic:BAAALgAFFAEJAQABLgAFFAYJFQAWABkcAA==.Senpai:BAAALgAECgQJBAAAAA==.Seraphymm:BAAALgADCgEJAQAAAA==.',
Sh='Shadowjacker:BAACLgAFFH8TAAINAAUJ9Bt1PAA0AQANAAUJ9Bt1PAA0AQAuAAQKfzgAAg0ACQkmIYIHAFEDAA0ACQkmIYIHAFEDAAAA.Shadowmidget:BAABLgAECn8WAAIPAAkJ3BahVwDBAQAPAAkJ3BahVwDBAQAAAA==.Shadowsburns:BAAALgADCgEJAQAAAA==.Shadrielis:BAABLgAECn9EAAMfAAkJvR+HCQDZAgAfAAkJvR+HCQDZAgAHAAIJVQ3VbgBsAAAAAA==.Shallanra:BAAALgAECgIJAgABLgAECgcJGwAgAOYYAA==.Shanlao:BAAALgAFFAIJAgABLgAFFAcJJAAPABQSAA==.Sharael:BAAALgAECgUJBQAAAA==.Shirkka:BAAALgADCgMJBAAAAA==.Shurihito:BAABLgAECn8lAAICAAkJiR5OIgB9AgACAAkJiR5OIgB9AgAAAA==.',
Si='Sieron:BAABLgAECn8UAAIKAAYJ/RxekgBBAQAKAAYJ/RxekgBBAQAAAA==.Silaslunark:BAAALgAECgkJCwAAAA==.Sinkrow:BAAALgAECgYJBgAAAA==.Sixpack:BAABLgAECn8dAAIgAAkJjA7xPACfAQAgAAkJjA7xPACfAQAAAA==.',
Sk='Skarigar:BAAALgAECgEJAwAAAA==.Skeeter:BAAALgAECgkJCQABLgAFFAQJEwARACoWAA==.Skeeterson:BAAALgADCgUJCAAAAA==.Skurplock:BAAALgADCgEJAQAAAA==.Skytec:BAAALgADCgMJAwAAAA==.Skëëts:BAABLgAECn8cAAQfAAgJSBBDKQCJAQAfAAgJJBBDKQCJAQATAAEJuwTokwAnAAAHAAEJ5gaydAAlAAAAAA==.Skùrvypete:BAAALgAFFAEJAQAAAA==.',
Sl='Slampoof:BAAALgAECgQJDwAAAA==.Slamslayer:BAAALgAECgEJAQAAAA==.Sleez:BAAALgAECgYJDAAAAA==.Sloodraga:BAAALgADCgYJBgAAAA==.',
Sm='Smallgregory:BAAALgAECgYJDAAAAA==.',
Sn='Sneakdead:BAAALgAECgcJCgAAAA==.Sneakerzz:BAAALgADCgQJBAAAAA==.Sneakfury:BAAALgAECgYJCgABLgAECgcJCgABAAAAAA==.Sneeler:BAAALgAECgEJAQAAAA==.Snowscayia:BAACLgAFFH8NAAQgAAcJUhXTLAACAQAgAAUJcQ7TLAACAQAJAAUJSQh1KwDfAAAdAAIJIQqeGABuAAAuAAQKfy4ABAkACQkbGDMnAMUBAAkACAk2GjMnAMUBACAABwleGD87ALgBAB0AAQlhCfNQADcAAAAA.',
So='Solanar:BAABLgAECn8+AAMeAAkJgSMJEQCNAgAeAAgJsiMJEQCNAgACAAcJESHBMQA5AgAAAA==.Solesin:BAAALgAFFAEJAQABLgAFFAUJEwAbADIXAA==.Solm:BAAALgAECgEJAQAAAA==.Solmina:BAABLgAECn83AAIWAAkJIh7hHwCfAgAWAAkJIh7hHwCfAgAAAA==.Somniatis:BAAALgAECgEJAQAAAA==.Soobin:BAAALgAECgkJCQAAAA==.Soulciopath:BAAALgAECgUJCAAAAA==.Souljin:BAAALgADCgMJAwAAAA==.',
Sp='Spartan:BAAALgAECgQJBAAAAA==.Spicypants:BAAALgADCgMJAwAAAA==.Spicytaco:BAAALgAECgUJCgABLgAECgkJJAACACMdAA==.Spookuleli:BAAALgADCggJCwAAAA==.Sprinklewiz:BAAALgADCgMJAwAAAA==.',
Sq='Squadie:BAABLgAECn87AAIDAAkJOQvyaQBuAQADAAkJOQvyaQBuAQAAAA==.Squanchs:BAACLgAFFH8XAAIGAAYJ5xnvFAC+AQAGAAYJ5xnvFAC+AQAuAAQKfx4AAwYACQlkHygMAL8CAAYACQlkHygMAL8CAAUAAQkGAPbHAAEAAAEuAAQKBwkcACAAkxsA.Squanchy:BAABLgAECn8cAAIgAAcJkxtxPACyAQAgAAcJkxtxPACyAQAAAA==.Squisquee:BAAALgADCgcJBwAAAA==.',
Sr='Srbojangles:BAAALgAECgcJCAABLgAECgcJJAAWAPYhAA==.Srry:BAABLgAECn8VAAIQAAcJsBrUKQATAgAQAAcJsBrUKQATAgAAAA==.',
St='Stinkvile:BAAALgAECgEJAQAAAA==.Stonebraid:BAAALgADCgEJAQAAAA==.Sturdy:BAAALgADCgEJAQAAAA==.',
Su='Suiféng:BAAALgAFFAIJAwAAAA==.Sukuna:BAAALgAECgYJCAAAAA==.Sundance:BAAALgAECgkJEQAAAA==.Surmise:BAACLgAFFH8VAAMWAAYJGRwlFAB6AQAWAAYJkxslFAB6AQAiAAEJBSMABQBhAAAuAAQKfzMAAxYACQkBJa0FAFYDABYACQkBJa0FAFYDACIABAlVIBkJAAQBAAAA.Sust:BAABLgAFFH8LAAINAAUJrBv0CgBgAQANAAUJrBv0CgBgAQABLgAFFAYJFQAWABkcAA==.Sustenance:BAABLgAFFH8GAAMnAAIJiRLZCACIAAAKAAIJiRKA1QCLAAAnAAIJtwzZCACIAAABLgAFFAYJFQAWABkcAA==.',
Sw='Swayzeetrain:BAACLgAFFH8iAAMeAAUJfybcCAAwAgAeAAUJfybcCAAwAgACAAEJpAxQMABUAAAuAAQKfxsAAwIACQkCHCxmALQBAAIABwkgGixmALQBAB4ACAn1IOA2AKABAAAA.',
Sy='Sydris:BAAALgAECgkJBQAAAA==.Sylvanic:BAAALgAECgEJAQAAAA==.Syrrel:BAAALgADCgYJBgAAAA==.',
['Sü']='Süß:BAAALgAFFAIJAgABLgAFFAQJCQANAL8NAA==.',
Ta='Tabius:BAABLgAECn8mAAMdAAkJXR7/CQAiAgAdAAkJXR7/CQAiAgAJAAMJyw4cYwCOAAAAAA==.Talkingtaco:BAABLgAECn8kAAICAAkJIx0vHwCMAgACAAkJIx0vHwCMAgAAAA==.Taln:BAAALgAECgEJAwABLgAECgkJKAALACghAA==.Talìa:BAAALgADCgIJAgABLgAECgEJAQABAAAAAA==.Tareul:BAAALgADCgIJAgAAAA==.Tarn:BAAALgAECgkJEgAAAA==.',
Te='Temok:BAABLgAECn8lAAICAAkJLhDldACEAQACAAkJLhDldACEAQAAAA==.',
Th='Thiccbush:BAAALgAECgEJAQAAAA==.Thirielnet:BAAALgAECggJDwAAAA==.This:BAAALgAECgEJAQAAAA==.Thorisdead:BAAALgAECgMJBQABLgAECggJKAASAO8LAA==.Thorkell:BAAALgADCgUJBQAAAA==.Thosen:BAAALgAECgYJEgAAAA==.',
Ti='Tinkaballah:BAAALgAECgcJDgAAAA==.Tipy:BAAALgADCgUJBQAAAA==.',
To='Tore:BAACLgAFFH8YAAIDAAYJIxr0MQBLAQADAAYJIxr0MQBLAQAuAAQKfzMAAgMACQmUIqcJAPwCAAMACQmUIqcJAPwCAAAA.Totemangge:BAAALgAFFAEJAQAAAA==.Totesmagoat:BAAALgADCgYJBgAAAA==.',
Tr='Trifectas:BAAALgADCgcJGQAAAA==.Trinadel:BAACLgAFFH8WAAIJAAYJVRGuFgBlAQAJAAYJVRGuFgBlAQAuAAQKfyUAAgkACAmsIYoAALMCAAkACAmsIYoAALMCAAAA.Träitors:BAAALgADCgcJEwAAAA==.Tråitors:BAABLgAECn88AAMPAAcJnyF9OQD0AQAPAAcJnyF9OQD0AQAZAAEJAAA0ZQBFAAABLgADCgcJEwABAAAAAA==.',
Ts='Tsarevich:BAABLgAECn8ZAAIiAAgJ7wl7BwA1AQAiAAgJ7wl7BwA1AQAAAA==.Tshera:BAAALgAECgEJAQABLgAECgkJNgACADoIAA==.',
Tu='Tugtheshaman:BAABLgAECn8dAAIGAAgJoxgmGgBGAgAGAAgJoxgmGgBGAgAAAA==.Tunechii:BAAALgAECgMJBQABLgAECgkJGQANAAkSAA==.',
Tw='Twileaf:BAABLgAECn82AAIgAAkJRAlpYQARAQAgAAkJRAlpYQARAQAAAA==.Twoinchisbig:BAABLgAECn9OAAIlAAkJLRs5CgBPAgAlAAkJLRs5CgBPAgAAAA==.',
Ty='Typhoidmary:BAABLgAECn8XAAMPAAgJhAmIggBVAQAPAAcJhAmIggBVAQAZAAEJAAAOdgAuAAABLgAFFAMJAwABAAAAAA==.',
['Té']='Térror:BAAALgAECgcJDwAAAA==.',
Ug='Ugtales:BAAALgAECgEJAQAAAA==.',
Un='Unbenched:BAAALgADCgQJBQABLgAECgkJOQAFAHofAA==.Uncool:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Unholyz:BAAALgAECgUJCAAAAA==.Unstable:BAAALgAECgEJAQAAAA==.',
Ur='Ursoc:BAABLgAECn84AAMJAAkJ9hLNHgDRAQAJAAkJ9hLNHgDRAQAgAAYJRxHRWQAqAQAAAA==.Urteg:BAAALgADCgkJFAAAAA==.',
Ut='Uthmansur:BAAALgAECgEJAgAAAA==.',
Uu='Uub:BAAALgAECgIJAgAAAA==.',
Va='Vairekor:BAAALgAECggJDAABLgAFFAcJJAAPABQSAA==.Valdria:BAAALgADCgUJBQAAAA==.Vanillaçake:BAAALgAFFAEJAQAAAA==.Vanishja:BAAALgAECgYJDwAAAA==.Varkbyte:BAABLgAECn8XAAIHAAcJbBPiJACdAQAHAAcJbBPiJACdAQAAAA==.Varrik:BAACLgAFFH8eAAMQAAUJVyKaBgAqAQAQAAUJVyKaBgAqAQAoAAMJ7hhbKADLAAAuAAQKfykAAxAACQkeI4oJABUDABAACQkeI4oJABUDACgABgmcG00fAGMBAAAA.',
Ve='Vec:BAAALgAECgYJDQAAAA==.Velamor:BAABLgAECn8YAAQkAAYJzgtQHQCxAAAkAAYJ5gpQHQCxAAAOAAMJygk5VQCTAAANAAMJagrp2QCCAAAAAA==.Velaria:BAAALgADCgcJBwAAAA==.',
Vi='Violynt:BAAALgADCgEJAQAAAA==.',
Vo='Volieu:BAABLgAECn8jAAIiAAkJPRSCAwDnAQAiAAkJPRSCAwDnAQAAAA==.Volklin:BAABLgAECn8rAAMFAAkJ9BFVBAACAQAFAAcJZAtVBAACAQAGAAkJHwllCwCjAAAAAA==.Voyageurs:BAABLgAECn8cAAIdAAkJpBwvBgCHAgAdAAkJpBwvBgCHAgAAAA==.',
Vy='Vyrka:BAAALgAECgMJDQAAAA==.',
Wa='Wallstreet:BAAALgAECgUJBQAAAA==.Warroute:BAAALgAECgUJBQABLgAFFAQJCQANAL8NAA==.Waterdweller:BAAALgAECgEJBAAAAA==.',
We='Wegl:BAABLgAECn8ZAAIWAAUJ7xmeDgDOAAAWAAUJ7xmeDgDOAAAAAA==.Werebear:BAAALgADCgMJAwABLgAECgUJBgABAAAAAA==.Werewithal:BAAALgAECgUJCQABLgAECgkJKQARALoSAA==.Wesleypipes:BAAALgAECgEJAQAAAA==.Wetfloorsign:BAAALgAECgYJEQAAAA==.',
Wh='Wholeymilk:BAAALgAECgQJCQAAAA==.',
Wi='Wiindsslashh:BAAALgAECgYJBwAAAA==.Wilbur:BAAALgADCgQJBQAAAA==.Windslash:BAAALgAECgIJAgAAAA==.Wish:BAAALgAECgYJCQAAAA==.',
Wo='Wonderx:BAAALgADCgIJAgAAAA==.Wonyoung:BAACLgAFFH8RAAIHAAQJMyRsDACEAQAHAAQJMyRsDACEAQAuAAQKfzIAAgcACQnzI9kBAFgDAAcACQnzI9kBAFgDAAAA.',
Wr='Wraithwok:BAAALgAECgUJBgAAAA==.',
Wu='Wuthrad:BAAALgAECgEJAQAAAA==.',
['Wü']='Würzig:BAABLgAFFH8HAAMKAAUJDAmfgQAEAQAKAAUJDAmfgQAEAQALAAIJ4AO3OABSAAABLgAFFAQJCQANAL8NAA==.',
Xa='Xala:BAABLgAECn8VAAMLAAkJbw0fIgBCAQALAAkJ+QwfIgBCAQAnAAIJ+AdtMABcAAAAAA==.Xalah:BAAALgAECggJEgAAAA==.Xalaz:BAACLgAFFH8WAAMPAAYJZQ7lOwBcAQAPAAYJZQ7lOwBcAQAZAAEJVwJgGgBGAAAuAAQKfx0AAw8ACQlXHHQ2ADICAA8ACAlXHHQ2ADICABkAAgkLFGNSAHcAAAAA.Xanaris:BAAALgADCgEJAQABLgAFFAIJCgAKAL0mAA==.Xandumbra:BAAALgADCgEJAQAAAA==.Xarosea:BAACLgAFFH8MAAICAAQJPxMQUQANAQACAAQJPxMQUQANAQAuAAQKfyoAAgIABwk6JPYYANMCAAIABwk6JPYYANMCAAAA.',
Xe='Xelienn:BAAALgAECgQJBwAAAA==.Xelojr:BAAALgADCgkJHAAAAA==.',
Xh='Xhael:BAAALgADCgEJAQAAAA==.',
Xi='Xia:BAABLgAECn9CAAIHAAkJqRkzFQA0AgAHAAkJqRkzFQA0AgAAAA==.Xilstorm:BAAALgAECgcJBwAAAA==.',
Xo='Xoilkick:BAABLgAECn8WAAIVAAgJDBhKAgAwAQAVAAgJDBhKAgAwAQAAAA==.Xoilpal:BAAALgAECgQJBAAAAA==.Xoilwings:BAAALgAECgMJBAAAAA==.Xooiill:BAAALgAECggJEQAAAA==.',
Xp='Xpacer:BAAALgAECgcJEwAAAA==.',
['Xê']='Xêna:BAAALgAECgUJDQAAAA==.',
Ye='Yekira:BAAALgADCgEJAgAAAA==.Yellowsnøw:BAACLgAFFH8JAAIWAAMJRAcZkQC1AAAWAAMJRAcZkQC1AAAuAAQKfzwAAhYACQnwF9csAGYCABYACQnwF9csAGYCAAAA.',
Yu='Yumeshade:BAAALgAECgYJCwAAAA==.',
Za='Zaila:BAAALgAECgUJBQAAAA==.Zal:BAAALgAECgYJBgABLgAFFAgJEQAlAMcVAA==.Zamari:BAAALgAECggJEQAAAA==.Zanazer:BAAALgAECgcJBgABLgAECgkJPgAeAIEjAA==.Zanzabar:BAABLgAECn8WAAIdAAkJegvGEACgAQAdAAkJegvGEACgAQAAAA==.Zathmage:BAAALgADCgMJAwAAAA==.Zaxin:BAABLgAECn8XAAMHAAkJDQ4UJwCNAQAHAAkJDQ4UJwCNAQATAAUJiAQeSwCtAAAAAA==.',
Ze='Zelfie:BAAALgADCgUJBQAAAA==.Zellda:BAAALgAECgYJCQAAAA==.Zerodarkness:BAAALgADCgkJCQAAAA==.Zeros:BAABLgAECn8XAAIWAAkJeBgZPAApAgAWAAkJeBgZPAApAgAAAA==.',
Zi='Ziperz:BAAALgAECggJCAAAAA==.',
Zo='Zoerina:BAAALgAECgcJDwAAAA==.Zoobilong:BAABLgAECn8XAAICAAcJHRAfuwAQAQACAAcJHRAfuwAQAQAAAA==.',
Zx='Zxak:BAABLgAECn85AAIOAAkJaSb0BAD1AgAOAAkJaSb0BAD1AgAAAA==.',
Zy='Zyahk:BAAALgADCgQJBQAAAA==.Zynn:BAAALgAECgEJAgAAAA==.',
['Zë']='Zën:BAAALgAECgEJAQABLgAFFAUJFQAfAO8LAA==.',
['Ða']='Ðashÿ:BAAALgAECgMJAwABLgAECggJFgAHAPEfAA==.',
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
