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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Elemental','Shaman-Restoration','Priest-Holy','Rogue-Subtlety','Druid-Balance','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Assassination','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Warrior-Fury','Hunter-Survival','Mage-Frost','Monk-Brewmaster','Priest-Shadow','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','Warlock-Affliction','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Druid-Feral','Paladin-Holy','Priest-Discipline','Druid-Restoration','Paladin-Protection','Mage-Arcane','Shaman-Enhancement','DemonHunter-Vengeance','Warrior-Protection','Rogue-Outlaw','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abandonhope:BAAALgAECgMJAwABLgAECgkJEwABAAAAAA==.',
Ac='Accuser:BAAALgADCgEJAQAAAA==.Acky:BAAALgADCgUJBQAAAA==.',
Ad='Adwen:BAABLgAECn8iAAICAAgJYRlDYwCqAQACAAgJYRlDYwCqAQAAAA==.',
Ae='Aenimal:BAAALgAECgYJEAAAAA==.Aer:BAAALgADCgkJCQAAAA==.Aeronemon:BAAALgAECgEJAgAAAA==.',
Ai='Airill:BAAALgADCgQJBQAAAA==.',
Ak='Akforty:BAABLgAECn8fAAMDAAkJIiHNCgDvAgADAAkJIiHNCgDvAgAEAAIJoBV7eABfAAAAAA==.Akittymeow:BAABLgAECn8bAAMFAAkJuw/WRgAYAQAFAAgJKQ/WRgAYAQAGAAMJiwWWqQB2AAAAAA==.',
Al='Aldredevon:BAAALgAECgEJAQAAAA==.Aleshock:BAAALgAECgkJEQAAAA==.Alidar:BAAALgAECgcJEwAAAA==.Alphaboner:BAAALgADCgYJBwAAAA==.Altairis:BAAALgAECgEJAgAAAA==.Altartoy:BAABLgAECn8hAAIHAAgJ6Qq5NwAeAQAHAAgJ6Qq5NwAeAQAAAA==.Althunter:BAACLgAFFH8NAAIEAAQJUiF0EQBNAQAEAAQJUiF0EQBNAQAuAAQKfxsAAgQACAneIcwGACICAAQACAneIcwGACICAAAA.',
Am='Amanita:BAAALgAECgQJBAABLgAECgkJEQABAAAAAA==.Amelina:BAAALgAECgYJDgAAAA==.Amerit:BAAALgAECgEJAQAAAA==.Amorir:BAACLgAFFH8PAAICAAQJSwPwaADdAAACAAQJSwPwaADdAAAuAAQKf1IAAgIACQnsEthWAMYBAAIACQnsEthWAMYBAAAA.Amorit:BAAALgAFFAIJAgAAAA==.Amorydalias:BAAALgAECgUJBgAAAA==.Amozon:BAAALgADCgEJAQAAAA==.',
An='Anamortem:BAAALgAECgMJAwABLgAECgkJIQAIAAcZAA==.Anastala:BAABLgAECn8rAAIJAAkJ5RXuGQD8AQAJAAkJ5RXuGQD8AQAAAA==.Andeddo:BAABLgAECn8WAAMKAAkJehUhXwCrAQAKAAYJURYhXwCrAQALAAYJWhFSKgAFAQAAAA==.Angchu:BAAALgADCgQJBAAAAA==.Angelmàker:BAAALgAECgMJBAABLgADCgcJEwABAAAAAA==.Angelmäker:BAAALgAECgYJCgABLgADCgcJEwABAAAAAA==.Annesta:BAABLgAECn8hAAMIAAkJBxnGGADUAQAIAAkJ0hjGGADUAQAMAAEJ9xazJQA9AAAAAA==.',
Ap='Apostus:BAAALgADCgcJDgAAAA==.Apothica:BAAALgAECgUJBgAAAA==.',
Aq='Aquafox:BAABLgAECn8uAAMGAAkJlR6oCgAMAwAGAAkJlR6oCgAMAwAFAAQJERUjTgD9AAAAAA==.',
Ar='Archontas:BAABLgAECn8kAAIJAAgJkSHrCgClAgAJAAgJkSHrCgClAgAAAA==.Ariodh:BAABLgAECn87AAMNAAkJLSaAAgBgAwANAAkJLSaAAgBgAwAOAAUJpB9eJACaAQAAAA==.Ariodr:BAAALgAFFAEJAQAAAA==.Arkaline:BAAALgAECgIJAgABLgAECgUJBQABAAAAAA==.Artuarry:BAACLgAFFH8hAAIPAAcJPBE+NQBzAQAPAAcJPBE+NQBzAQAuAAQKfyYAAg8ACQlGH2MfAGgCAA8ACQlGH2MfAGgCAAAA.Aryndus:BAABLgAECn8lAAICAAkJcx7dHACYAgACAAkJcx7dHACYAgAAAA==.',
At='Athenà:BAAALgAECgUJBQAAAA==.',
Av='Avocado:BAABLgAECn8jAAMDAAkJnCU1DgDgAgADAAkJHiM1DgDgAgAEAAcJVCKaCwCuAQAAAA==.',
Ax='Axelaw:BAAALgADCgQJBAAAAA==.',
Ay='Ayrz:BAAALgAECgIJAgAAAA==.',
Az='Azaria:BAAALgADCgIJAgAAAA==.',
Ba='Baddjujumon:BAABLgAECn8XAAMFAAgJ0gR8WADaAAAFAAgJ0gR8WADaAAAGAAEJoAEf9AAdAAAAAA==.Baileyhowl:BAAALgAECgEJBQAAAA==.Bammie:BAAALgADCgYJCgAAAA==.Bananuth:BAAALgAECgIJAwABLgAFFAcJIAAKANMbAA==.Banthr:BAABLgAECn8XAAIQAAkJNw4sLgCYAQAQAAkJNw4sLgCYAQAAAA==.Barkert:BAAALgADCgQJAwAAAA==.Baroke:BAAALgAECgMJBwABLgAECggJIQAHAOkKAA==.Barokoshama:BAAALgAECgcJEQAAAA==.Basaltytaco:BAAALgADCgEJAQAAAA==.Battleworm:BAAALgADCgkJEwABLgAFFAMJAwABAAAAAA==.',
Bb='Bbalrd:BAACLgAFFH8JAAIKAAMJ0xtzDgCeAAAKAAMJ0xtzDgCeAAAuAAQKfxcAAgoACQmiF3hOANcBAAoACQmiF3hOANcBAAAA.',
Be='Bearglie:BAAALgAECggJDgAAAA==.Beepers:BAAALgAECgYJBgAAAA==.Beezelpup:BAAALgAECgYJCAABLgAECgkJFwAQADcOAA==.',
Bi='Bigcow:BAAALgAECgUJCQAAAA==.',
Bl='Blackolives:BAAALgAECgkJEAAAAA==.Bladesp:BAAALgAECgYJDQABLgAECgkJGQANAAkSAA==.Blondefu:BAAALgAECgUJCwAAAA==.Bloodybonne:BAAALgADCgcJBwAAAA==.Bloodyell:BAAALgAECgYJBgAAAA==.Bloore:BAAALgAECgMJAwABLgAECgkJLAAEAG0iAA==.Bluejuly:BAAALgAECgUJBQAAAA==.Blutø:BAAALgAFFAIJAgAAAA==.',
Bo='Boflex:BAAALgADCgQJBgAAAA==.Bomboclat:BAAALgAECgUJCwAAAA==.Bonesknows:BAAALgADCgEJAQAAAA==.Boofy:BAAALgAECgMJAwABLgAECgkJFgAPANwWAA==.Borhoag:BAAALgADCgEJAQABLgAECggJDgABAAAAAA==.Bowwie:BAACLgAFFH8SAAMRAAQJKBS0FgAbAQARAAQJDxC0FgAbAQADAAMJZRBlbwDCAAAuAAQKfzUABAMACQnZHy0GACsDAAMACQkTHi0GACsDABEACQkXGkAJAIoCAAQAAQkVAxWTACcAAAAA.',
Br='Britney:BAAALgADCgkJCQAAAA==.Bronzé:BAACLgAFFH8HAAISAAMJwhkCbwAEAQASAAMJwhkCbwAEAQAuAAQKfzIAAhIABwkyI+gzAEkCABIABwkyI+gzAEkCAAAA.Brotherfrey:BAAALgAECggJEQAAAA==.Bruish:BAABLgAFFH8MAAITAAQJtwzFDQAWAQATAAQJtwzFDQAWAQAAAA==.Bruty:BAAALgAECgEJAQAAAA==.',
Bu='Bubbadoo:BAABLgAECn8lAAIJAAkJzQ9YIwCvAQAJAAkJzQ9YIwCvAQAAAA==.Buddy:BAABLgAECn8ZAAIUAAYJoRI3OgAqAQAUAAYJoRI3OgAqAQABLgAECggJJwALAHMhAA==.Bulan:BAABLgAECn9KAAIVAAkJuCW7AgCcAwAVAAkJuCW7AgCcAwAAAA==.',
Bw='Bweninger:BAAALgAECgEJAQAAAA==.',
['Bô']='Bôôsted:BAABLgAECn8iAAIFAAkJ8BT3AQDcAAAFAAkJ8BT3AQDcAAABLgAFFAEJAQABAAAAAA==.',
Ca='Caistan:BAAALgADCgYJCAAAAA==.Calyopi:BAAALgAFFAIJAgAAAA==.Candypants:BAABLgAECn8jAAQVAAkJxRa7GwA6AgAVAAkJxRa7GwA6AgATAAcJ9A6TPAAJAQAWAAMJ2At6aQCBAAAAAA==.Caoth:BAAALgAECgYJEwAAAA==.Cappilon:BAABLgAECn8eAAISAAkJ7SFZFwDNAgASAAkJ7SFZFwDNAgAAAA==.Carcus:BAABLgAECn8nAAIPAAkJKB+aEADIAgAPAAkJKB+aEADIAgAAAA==.Carmila:BAAALgADCgEJAQAAAA==.Cayleedah:BAABLgAECn8vAAIEAAkJ5wwNEgA6AQAEAAkJ5wwNEgA6AQAAAA==.Cayssaris:BAABLgAECn8WAAIXAAgJbBlsDwDwAQAXAAgJbBlsDwDwAQAAAA==.',
Cc='Cc:BAABLgAECn8WAAQYAAYJPBPsDgBCAQAYAAUJ9BPsDgBCAQAZAAYJKwstIwA+AQAPAAQJzhP5tQDtAAAAAA==.',
Ce='Ceeti:BAABLgAECn84AAMaAAkJICGOCADOAgAaAAkJICGOCADOAgAbAAIJeAYcQABpAAAAAA==.Celandrelia:BAAALgAECgUJBQABLgAECggJLAAcAEQXAA==.',
Ch='Chaewon:BAAALgAFFAEJAQABLgAFFAQJEQAHADMkAA==.Channeria:BAAALgAECgEJAQAAAA==.Chaoticoreo:BAABLgAECn8xAAMOAAkJOh7rCQCLAgAOAAkJOh7rCQCLAgANAAQJ4w9rrQCzAAAAAA==.Chappedlips:BAAALgAECgkJBwAAAA==.Chareyne:BAABLgAECn8ZAAIHAAgJ5RFyJgC5AQAHAAgJ5RFyJgC5AQAAAA==.Cheetor:BAAALgAECgMJAwABLgAFFAQJEgARACoWAA==.Cheezytaco:BAAALgAECgYJDgABLgAECgkJJAACACMdAA==.Chidge:BAAALgADCggJCwAAAA==.Chikila:BAABLgAECn8jAAMZAAgJBhlsBwDeAQAZAAgJBhlsBwDeAQAPAAMJeAyQ4wCVAAAAAA==.Chilliflakez:BAABLgAECn8XAAIVAAcJ1Q7fSABJAQAVAAcJ1Q7fSABJAQAAAA==.Chro:BAAALgAECgcJBwABLgAECgkJOQAFAHofAA==.',
Ci='Cindezar:BAAALgADCgMJAwAAAA==.',
Cl='Clementyn:BAABLgAECn8WAAICAAcJOBB5zgD1AAACAAcJOBB5zgD1AAAAAA==.Cleyi:BAABLgAECn8qAAIHAAkJMw3AKgByAQAHAAkJMw3AKgByAQAAAA==.',
Co='Coldpasta:BAAALgAECgYJDgABLgAFFAIJBAABAAAAAA==.Colonoscopy:BAAALgAECgMJBAAAAA==.Coreyy:BAAALgADCgUJBwAAAA==.Corva:BAACLgAFFH8YAAIPAAUJKxKpVwAYAQAPAAUJKxKpVwAYAQAuAAQKfyoAAg8ACQnpFbBDANABAA8ACQnpFbBDANABAAAA.Cosairi:BAAALgAECgYJEwAAAA==.Cougztroll:BAABLgAECn83AAMXAAkJlRUMEwDCAQAXAAkJlRUMEwDCAQAdAAYJ/gstKADNAAAAAA==.',
Cr='Crazaki:BAAALgADCgEJAQAAAA==.Crosseye:BAAALgADCgMJBwAAAA==.Crossie:BAAALgADCgEJAQAAAA==.',
Ct='Ctd:BAAALgADCgkJGwABLgAECgkJOAAaACAhAA==.',
Cu='Curfluffin:BAAALgADCgEJAQAAAA==.Cuttercupx:BAAALgAECgQJBQABLgAECgkJEwABAAAAAA==.',
Da='Dahn:BAAALgAECgIJAgAAAA==.Dakadin:BAABLgAECn8mAAMeAAkJ+yPNEgB7AgAeAAkJ+yPNEgB7AgACAAQJ7hec3gDgAAAAAA==.Daranne:BAACLgAFFH8fAAICAAUJaxblQwAjAQACAAUJaxblQwAjAQAuAAQKfysAAgIACQn5Gxc/ACkCAAIACQn5Gxc/ACkCAAAA.Darkenedstar:BAAALgAECgYJDQABLgAECgYJEAABAAAAAA==.Darksoulstwo:BAAALgADCgMJAwAAAA==.Dasbeans:BAABLgAECn8cAAMaAAkJNAmwRwAMAQAaAAgJPQqwRwAMAQAcAAIJkgHvRgARAAAAAA==.Dashy:BAABLgAECn8WAAMHAAgJ8R8XFAA2AgAHAAgJVBoXFAA2AgAfAAYJ4B6vFgAiAgAAAA==.Datran:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.',
De='Deaduglie:BAABLgAECn84AAMPAAkJbBYtNwD8AQAPAAkJbBYtNwD8AQAZAAEJMQjvcQA0AAAAAA==.Delamyr:BAAALgADCggJCAAAAA==.Deliandora:BAAALgAECgQJCAAAAA==.Delusional:BAAALgAECgcJDwAAAA==.Delynique:BAAALgADCgEJAQABLgAECgkJLAAEAG0iAA==.Demonx:BAAALgAECgEJAQAAAA==.Denaric:BAABLgAECn8hAAMgAAgJ+xiTKgABAgAgAAcJkBmTKgABAgAJAAcJJA7KOwAiAQAAAA==.Dergen:BAAALgAECgkJCwABLgAECgkJEwABAAAAAA==.Destroyevsky:BAABLgAECn8gAAIQAAYJSwI2gQBzAAAQAAYJSwI2gQBzAAAAAA==.Detonate:BAABLgAECn8aAAISAAYJbhyVfwB4AQASAAYJbhyVfwB4AQAAAA==.',
Dh='Dhpoo:BAAALgADCgUJBAAAAA==.Dhvecx:BAAALgAECgUJBgABLgAECgYJDQABAAAAAA==.',
Di='Dilbo:BAAALgAFFAIJAgABLgAFFAcJIQAJACYZAA==.Diomed:BAAALgAECgEJAQAAAA==.Diqoff:BAAALgAECgIJAgAAAA==.Diqon:BAABLgAECn84AAMKAAkJDRtrNAAtAgAKAAkJDRtrNAAtAgALAAcJtxSOIwA3AQAAAA==.Disturbedtwo:BAAALgAECgYJCgAAAA==.',
Do='Dolphinz:BAACLgAFFH8XAAICAAUJ4BkYMABSAQACAAUJ4BkYMABSAQAuAAQKfzIAAwIACQn+IbYQAOECAAIACQn+IbYQAOECACEAAgnpCiI8AE4AAAAA.Doryadni:BAAALgADCgcJBgAAAA==.',
Dr='Draci:BAAALgAECgcJDQABLgAECgkJUQAQAJQeAA==.Dragondaddy:BAAALgAECgkJEAAAAA==.Dragonpede:BAACLgAFFH8JAAIaAAUJRRlCGQCcAQAaAAUJRRlCGQCcAQAuAAQKfzkAAhoACQkWIPcJALkCABoACQkWIPcJALkCAAAA.Dragonwarior:BAABLgAECn8fAAIQAAkJ6hv+LACeAQAQAAkJ6hv+LACeAQAAAA==.Drakindees:BAAALgAECgUJBQABLgAECgcJJAASAPYhAA==.Drakkyn:BAABLgAECn8hAAIQAAgJ2BkUHQAFAgAQAAgJ2BkUHQAFAgAAAA==.Drakonus:BAAALgAECgUJCQAAAA==.Dread:BAAALgADCgQJBAAAAA==.Drosuu:BAAALgAECgEJAQAAAA==.Druish:BAACLgAFFH8lAAIXAAcJyCDBAgARAgAXAAcJyCDBAgARAgAuAAQKfywAAxcACQk0JqMAAG0DABcACQk0JqMAAG0DAB0AAgkOD5ksAGEAAAAA.Drykkr:BAABLgAECn8mAAITAAkJnBYiGQDdAQATAAkJnBYiGQDdAQAAAA==.',
Du='Dullahan:BAAALgAECgUJBgAAAA==.Dunstie:BAAALgADCgEJAQABLgAECgcJGwALACoeAA==.Durrik:BAAALgADCgcJBwAAAA==.Duuhh:BAAALgAECgEJAQAAAA==.',
['Dà']='Dàsh:BAAALgAECgYJBgABLgAECggJFgAHAPEfAA==.',
Ea='Eatrocks:BAAALgADCggJCAAAAA==.',
Ed='Edorn:BAAALgAECgUJBQAAAA==.',
Ef='Efn:BAAALgAECgYJEwAAAA==.',
El='Elcrys:BAABLgAECn8aAAIgAAcJ3BaiNgC+AQAgAAcJ3BaiNgC+AQAAAA==.Elentiya:BAAALgAECgkJDQAAAA==.Eleòs:BAAALgADCgYJBgAAAA==.Elion:BAAALgAECgEJAQAAAA==.Ellyra:BAABLgAFFH8HAAIDAAMJiwVObwDDAAADAAMJiwVObwDDAAAAAA==.Elpollo:BAABLgAECn8kAAMSAAcJ9iGUQgBwAgASAAcJ9iGUQgBwAgAiAAEJshe1HAA6AAAAAA==.Elsinn:BAAALgADCggJEAAAAA==.Elvar:BAAALgAECgYJEgAAAA==.',
Em='Emmdwemm:BAAALgAECgQJCgAAAA==.',
En='Enoki:BAAALgAECgQJBAAAAA==.',
Ep='Ephelia:BAACLgAFFH8eAAIGAAUJfSa2CQAuAgAGAAUJfSa2CQAuAgAuAAQKfxkAAwYACQlfGooiAA8CAAYACQlfGooiAA8CAAUAAQmMA/eUACAAAAAA.Epitome:BAABLgAECn8pAAISAAkJsRatPgAhAgASAAkJsRatPgAhAgAAAA==.',
Er='Erid:BAAALgAECgcJEQAAAA==.',
Et='Etude:BAAALgADCgEJAQAAAA==.',
Ev='Evelyndel:BAAALgAECgYJBwAAAA==.Evergrey:BAABLgAECn8ZAAIUAAcJsAz9OgAmAQAUAAcJsAz9OgAmAQAAAA==.Evermoons:BAABLgAECn8jAAIgAAkJVxl0FgCUAgAgAAkJVxl0FgCUAgAAAA==.Evodaka:BAAALgAECgIJAwABLgAECgkJJgAeAPsjAA==.',
Fa='Falaria:BAAALgAECgQJBAAAAA==.Falasdaer:BAABLgAECn8lAAMNAAkJvSKNFQCXAgANAAgJQCKNFQCXAgAOAAQJAiLqHgCDAQAAAA==.Fallansting:BAABLgAECn8WAAINAAcJ0hoJOwDbAQANAAcJ0hoJOwDbAQAAAA==.Falstaff:BAABLgAECn8fAAITAAkJxhWmFgD1AQATAAkJxhWmFgD1AQAAAA==.Fartshooter:BAAALgAECgYJEQAAAA==.Fatterblunt:BAACLgAFFH8hAAIJAAcJJhneEQCTAQAJAAcJJhneEQCTAQAuAAQKfywAAgkACQkyIXoAAOUBAAkACQkyIXoAAOUBAAAA.',
Fe='Fedner:BAABLgAECn8XAAIGAAcJSQ+UWQBRAQAGAAcJSQ+UWQBRAQAAAA==.Feldar:BAABLgAECn84AAICAAkJyiHSDwDnAgACAAkJyiHSDwDnAgAAAA==.Fend:BAAALgADCgQJBAAAAA==.Feronite:BAAALgAECgYJCgABLgAFFAQJEgARACgUAA==.Feyredarling:BAAALgAECgMJAwAAAA==.',
Fi='Fists:BAACLgAFFH8MAAITAAQJgBxfIgAiAQATAAQJgBxfIgAiAQAuAAQKfyoAAxMABgmEI44WAFQCABMABgmEI44WAFQCABYABAk3EqtUAL4AAAAA.Fistweaver:BAAALgAECgIJAgAAAA==.Fizzbeard:BAAALgADCgcJCgAAAA==.Fizzical:BAAALgADCgkJFwAAAA==.Fizzleclaw:BAABLgAECn8iAAMXAAgJFR5OCQBWAgAXAAgJFR5OCQBWAgAJAAQJDRFoRwDuAAAAAA==.Fizzleded:BAAALgAECgQJBQABLgAECggJIgAXABUeAA==.Fizzleflare:BAAALgADCgkJCQAAAA==.',
Fl='Flightrisk:BAAALgAECgQJBgABLgAECgkJEwABAAAAAA==.Florisa:BAABLgAECn8jAAICAAgJ5RyvQwD7AQACAAgJ5RyvQwD7AQAAAA==.',
Fo='Fool:BAAALgAFFAEJAQABLgAFFAMJAwABAAAAAA==.Fordi:BAABLgAECn85AAMFAAkJeh/mCgCyAgAFAAkJcR/mCgCyAgAjAAQJpRbpAgBWAAAAAA==.Forendor:BAAALgAECgMJBwAAAA==.Fourdy:BAABLgAECn8yAAIGAAcJkRlFQACsAQAGAAcJkRlFQACsAQAAAA==.',
Fr='Fragdoll:BAAALgAECgQJCgAAAA==.Freakinlarry:BAAALgADCgEJAQAAAA==.Freakinoak:BAACLgAFFH8GAAIgAAMJ5AisBgBgAAAgAAMJ5AisBgBgAAAuAAQKfy4AAiAACQmjFPEjACwCACAACQmjFPEjACwCAAAA.Fredboat:BAAALgAECgEJAgABLgAFFAIJCgAKAL0mAA==.Free:BAABLgAECn8ZAAMNAAkJCRJTQwC+AQANAAgJCRJTQwC+AQAkAAUJ9Ap3IACAAAAAAA==.Frenn:BAAALgAECgUJCAAAAA==.Froost:BAACLgAFFH8YAAMKAAUJmBdACADzAAAKAAQJmBdACADzAAALAAEJAABAVQAAAAAuAAQKfxgAAgoACQlfHvRMAAwCAAoACQlfHvRMAAwCAAAA.',
Fu='Funkflex:BAAALgAECgEJAQABLgAECgkJGQANAAkSAA==.Furvert:BAAALgAECgkJEwAAAA==.Fushi:BAAALgAECgEJAQAAAA==.',
Ga='Gandis:BAAALgAECgkJEgAAAA==.Gapper:BAACLgAFFH8SAAIRAAQJKhYYEgA3AQARAAQJKhYYEgA3AQAuAAQKf1QAAxEACQmNJUQBAFcDABEACQmNJUQBAFcDAAQAAgldGaoBAFUAAAAA.Gargodath:BAAALgAECgUJDAAAAA==.',
Gi='Gielinor:BAAALgADCgIJAgAAAA==.Gimbó:BAAALgADCgQJBgAAAA==.',
Gl='Glamour:BAAALgADCgEJAgAAAA==.Glestaar:BAACLgAFFH8HAAIDAAMJrwwrZgDZAAADAAMJrwwrZgDZAAAuAAQKfykAAwMACAmfHGswABoCAAMACAmfHGswABoCAAQAAglFC4V8AFIAAAAA.Glitterpants:BAAALgAECgMJBAAAAA==.Glyr:BAAALgAECgYJCgAAAA==.',
Go='Goingrouge:BAAALgAECgYJCgAAAA==.Goldabelle:BAAALgAECgYJCgAAAA==.Goonkin:BAAALgAECgUJBQABLgAFFAQJEgARACoWAA==.Gorlami:BAABLgAFFH8GAAICAAMJZA5JgwCuAAACAAMJZA5JgwCuAAAAAA==.Gothelf:BAAALgAFFAIJBAAAAA==.Gothri:BAAALgAECgcJCQABLgAECgcJFQAaAJAVAA==.Gothstraza:BAABLgAECn8VAAIaAAcJkBUVOgBEAQAaAAcJkBUVOgBEAQAAAA==.Gottemgood:BAAALgADCgUJBQAAAA==.',
Gr='Grimli:BAABLgAECn8jAAIGAAkJwQ8IRQCaAQAGAAkJwQ8IRQCaAQAAAA==.Growth:BAABLgAECn8ZAAMUAAkJNAm2LwBgAQAUAAkJNAm2LwBgAQAfAAYJohBnOQArAQAAAA==.',
Gu='Gurthcaptian:BAAALgAECgQJBAAAAA==.',
Gy='Gyatso:BAAALgADCgMJAwAAAA==.',
['Gá']='Gárròsh:BAAALgAECgYJBgAAAA==.',
['Gô']='Gôôse:BAAALgAECgYJBgAAAA==.',
Ha='Haerin:BAAALgAECgIJAgABLgAFFAQJEQAHADMkAA==.Happykilmøre:BAAALgAECgQJBAABLgAECgkJEgABAAAAAA==.Harnel:BAABLgAECn80AAICAAkJSgQD2gDmAAACAAkJSgQD2gDmAAAAAA==.Haseo:BAAALgAECgkJDAAAAA==.Hattorihanzo:BAAALgAECggJDwAAAA==.',
He='Healeymonstr:BAAALgADCgIJAgAAAA==.Healmart:BAABLgAECn8YAAIfAAgJegZGOQAsAQAfAAgJegZGOQAsAQAAAA==.Heartëater:BAAALgADCgYJBgAAAA==.Hellinyoface:BAAALgADCgUJBQAAAA==.Heymage:BAAALgADCgkJCQAAAA==.',
Hi='Himothyy:BAAALgAECgQJBAAAAA==.',
Ho='Holypeetch:BAAALgADCgYJBgAAAA==.Hoofpics:BAAALgAECgQJBAAAAA==.Hordedefect:BAAALgAECgEJAQABLgAECgkJEwABAAAAAA==.Hoyer:BAAALgAECgkJEwAAAA==.',
Hu='Hulkhogan:BAAALgAECggJDgAAAA==.Humbledrink:BAAALgAECgQJBQAAAA==.',
Im='Impact:BAAALgADCgcJCgAAAA==.',
In='Inflícted:BAACLgAFFH8UAAIfAAUJ7wu4IQBCAQAfAAUJ7wu4IQBCAQAuAAQKfxUAAh8ACQlFEUwZAAcCAB8ACQlFEUwZAAcCAAAA.Innoscent:BAAALgAECgYJBgAAAA==.Inzo:BAAALgAFFAEJAgAAAA==.',
Io='Iove:BAABLgAECn8aAAIVAAkJZBVZIQASAgAVAAkJZBVZIQASAgAAAA==.',
Ja='Jahsahm:BAAALgAECgcJEQAAAA==.Jajung:BAAALgADCgMJAwAAAA==.Jakub:BAABLgAECn8hAAILAAkJqRezDgAgAgALAAkJqRezDgAgAgABLgAFFAQJEgARACgUAA==.Jakuren:BAAALgADCgYJBgAAAA==.Jamjam:BAAALgAECgUJBQAAAA==.',
Je='Jesit:BAABLgAECn8aAAIbAAYJ8hXgFAB9AQAbAAYJ8hXgFAB9AQAAAA==.',
Jh='Jhonn:BAAALgAECgEJAQABLgAECgkJRgAlAL8iAA==.',
Ji='Jingles:BAAALgADCgYJBgAAAA==.',
Jj='Jjada:BAACLgAFFH8JAAMNAAQJvw28UQD4AAANAAQJvw28UQD4AAAkAAEJdBXnEQA9AAAuAAQKfx0AAw0ACQnFIQgQAMICAA0ACQl0IAgQAMICACQABgmeIYAFAE0CAAAA.',
Jo='Johnwolf:BAABLgAECn8WAAICAAgJ8wIB9wDCAAACAAgJ8wIB9wDCAAAAAA==.',
Jy='Jyade:BAABLgAECn8/AAMMAAkJdBGsBwDcAQAMAAkJdBGsBwDcAQAmAAUJnwifCAD6AAAAAA==.Jynoria:BAAALgADCgcJDAAAAA==.',
Ka='Kainlok:BAAALgADCgIJAgAAAA==.Kaiserice:BAAALgAECgcJEAAAAA==.Kaliel:BAAALgAECgUJBQAAAA==.Kamarra:BAABLgAECn8fAAIaAAcJmgf7VADdAAAaAAcJmgf7VADdAAAAAA==.Kamencider:BAABLgAECn8dAAISAAcJ8RAvmABIAQASAAcJ8RAvmABIAQAAAA==.Kamidala:BAAALgAECgIJAgAAAA==.Kankles:BAACLgAFFH8FAAIJAAQJ3x48HAA5AQAJAAQJ3x48HAA5AQAuAAQKfyoAAgkACAnuIkELAJ8CAAkACAnuIkELAJ8CAAAA.Karhualaston:BAAALgAECgEJAQAAAA==.Karva:BAAALgAECgIJAwAAAA==.Katabetta:BAAALgADCgMJAwAAAA==.Kayati:BAAALgAECgYJCgABLgAFFAcJGAAPABsMAA==.',
Ke='Kellmagnison:BAAALgAECgIJAgABLgAECgkJNgACADoIAA==.Kentukee:BAAALgAECgIJBAABLgAECgkJKQARALoSAA==.Kernelpanic:BAACLgAFFH8gAAMKAAcJ0xv6KADGAQAKAAcJ0xv6KADGAQAnAAEJ/gXcKwA6AAAuAAQKfysAAgoACQkCIl4gAIcCAAoACQkCIl4gAIcCAAAA.Kessho:BAAALgAECgYJDwABLgAFFAQJEgARACgUAA==.Kevynn:BAAALgADCgMJAgAAAA==.Keyoshi:BAAALgAECgYJBgAAAA==.',
Ki='Kickrocks:BAAALgAECgEJAQAAAA==.Kilerforlife:BAAALgAECgYJCwAAAA==.Kilowog:BAAALgADCgUJCAAAAA==.Kilpally:BAAALgAECgYJBwAAAA==.Kintra:BAAALgADCgIJAgAAAA==.Kirin:BAAALgAECgEJAQAAAA==.Kirkle:BAABLgAECn9VAAIZAAkJnx9PAQDfAgAZAAkJnx9PAQDfAgAAAA==.Kithara:BAAALgAECgEJAwAAAA==.',
Ko='Kovie:BAAALgADCggJCAAAAA==.Kovy:BAABLgAECn8VAAMLAAkJ8RZ6FADJAQALAAkJ8RZ6FADJAQAKAAEJCQQKJQEvAAAAAA==.Kovya:BAAALgADCgYJBwAAAA==.',
Kr='Krelel:BAAALgADCgIJAgAAAA==.Krukar:BAAALgADCgYJDAAAAA==.',
Ku='Kubo:BAAALgAECgYJBwABLgAFFAQJEgARACgUAA==.',
Ky='Kydroga:BAAALgAECgYJEAAAAA==.Kynaria:BAAALgAECgIJAgAAAA==.Kynsia:BAAALgADCgQJBgAAAA==.',
La='Lamörak:BAABLgAECn81AAICAAkJZiJWDgDzAgACAAkJZiJWDgDzAgAAAA==.Landrick:BAABLgAECn9AAAMKAAkJVR3cIQCAAgAKAAkJVR3cIQCAAgALAAEJ6BcCBABHAAAAAA==.Lastotem:BAAALgADCgEJAQAAAA==.Lastshot:BAABLgAECn8XAAIDAAgJxhNTQQDeAQADAAgJxhNTQQDeAQAAAA==.Latest:BAAALgADCgQJBAAAAA==.Lavaevoker:BAAALgADCgcJBwABLgAECggJKAATAO8LAA==.Lavanor:BAAALgADCgIJAgAAAA==.Lavasaurus:BAABLgAECn8iAAQbAAgJkho5EwCVAQAbAAYJUxo5EwCVAQAaAAgJSA+YMAB1AQAcAAEJDRNtJAA6AAAAAA==.',
Le='Leafstorm:BAAALgAECgYJDwAAAA==.Lehala:BAAALgADCgQJBAAAAA==.Lektar:BAAALgAECgUJBQABLgAECgYJEwABAAAAAA==.Leloosh:BAAALgADCgkJDAABLgAFFAIJBAABAAAAAA==.Lemon:BAABLgAECn8sAAIZAAkJBRTlBgDuAQAZAAkJBRTlBgDuAQAAAA==.Leokenoso:BAABLgAECn8kAAIkAAkJEhN8CgC7AQAkAAkJEhN8CgC7AQAAAA==.Lesclaypool:BAAALgAECgcJCgAAAA==.Lessalia:BAAALgAECgEJAQAAAA==.Lewd:BAAALgAECgUJCgAAAA==.Lexor:BAAALgADCgQJBAAAAA==.',
Li='Lifebloomz:BAABLgAECn82AAIgAAkJDw63OgCpAQAgAAkJDw63OgCpAQAAAA==.Lifesabeach:BAAALgAECgMJAwAAAA==.Lilfluffcc:BAAALgAECgQJBAAAAA==.Lissana:BAAALgADCgUJBQAAAA==.',
Lo='Lockward:BAAALgAECgUJBwAAAA==.Loidvoid:BAAALgAECgYJCAAAAA==.Lorblor:BAABLgAECn8qAAIkAAkJCCBlAgDaAgAkAAkJCCBlAgDaAgAAAA==.Lorerun:BAAALgADCgUJCAAAAA==.Lowang:BAABLgAECn8dAAITAAkJnROtJwB0AQATAAkJnROtJwB0AQAAAA==.Lowmein:BAABLgAECn8UAAIGAAgJMR4lKgDlAQAGAAgJMR4lKgDlAQAAAA==.',
Lu='Lucÿfer:BAAALgAFFAIJAwAAAA==.Lumie:BAAALgAECgYJEQAAAA==.Luminisx:BAAALgADCgMJAwAAAA==.Lunafox:BAABLgAECn8oAAIGAAgJOh4IFgCaAgAGAAgJOh4IFgCaAgAAAA==.Lunamae:BAABLgAECn8pAAIiAAkJiRlsAwDtAQAiAAkJiRlsAwDtAQAAAA==.Lupacho:BAAALgAFFAIJAwAAAA==.Luvvyyaa:BAABLgAECn9hAAMfAAkJsCFOAABjAgAHAAkJ+h2xCADAAgAfAAkJeB9OAABjAgAAAA==.Luvyya:BAAALgAECgYJEAABLgAECgkJYQAfALAhAA==.Luvyyaa:BAAALgAECgQJBQABLgAECgkJYQAfALAhAA==.',
Ly='Lyrinaku:BAABLgAECn8UAAIHAAcJWRVQNgBkAQAHAAcJWRVQNgBkAQAAAA==.Lythomancer:BAABLgAECn8kAAIZAAkJzg5aEAA8AQAZAAkJzg5aEAA8AQAAAA==.',
Ma='Maddeena:BAABLgAECn8lAAIGAAgJ/wdLZQArAQAGAAgJ/wdLZQArAQAAAA==.Maddy:BAABLgAECn8iAAMWAAkJWBopFQAQAgAWAAgJYh0pFQAQAgATAAkJexBOGgDTAQAAAA==.Maelyssa:BAAALgADCgMJAwAAAA==.Magicmangge:BAAALgADCgYJBgABLgAFFAEJAQABAAAAAA==.Makeitclap:BAAALgAECgMJBAABLgAECgcJHQASAPEQAA==.Malidian:BAABLgAECn8dAAINAAkJdw9GVgCEAQANAAkJdw9GVgCEAQAAAA==.Matchadaddy:BAAALgAECgEJAwAAAA==.Maxohlx:BAACLgAFFH8YAAIPAAcJGwz+KgCaAQAPAAcJGwz+KgCaAQAuAAQKf0cAAg8ACQlnIdUIAA4DAA8ACQlnIdUIAA4DAAAA.',
Mc='Mcmercie:BAAALgAECgkJCgAAAA==.',
Me='Mechacooter:BAAALgAFFAMJAwAAAA==.Meeko:BAAALgADCgUJBQABLgAFFAgJIgAbAAQhAA==.Megahertz:BAAALgADCgEJAQAAAA==.Megg:BAAALgADCggJEQAAAA==.Meilia:BAAALgADCgUJBwAAAA==.Mekagatha:BAAALgADCgkJEgAAAA==.Mekari:BAABLgAECn8wAAIRAAkJxR0fCgB9AgARAAkJxR0fCgB9AgAAAA==.Melchiorr:BAACLgAFFH8NAAIYAAQJ2BlaAwBiAQAYAAQJ2BlaAwBiAQAuAAQKfykAAhgACQkRHEQFADgCABgACQkRHEQFADgCAAAA.Melignant:BAAALgADCgEJAQAAAA==.Melosia:BAAALgADCgQJBwAAAA==.Melynne:BAABLgAECn9HAAMGAAkJ4BV/IgBAAgAGAAkJ4BV/IgBAAgAFAAIJeATEgQBBAAAAAA==.Memmel:BAAALgADCgMJAwAAAA==.Meredeath:BAABLgAECn8UAAIJAAgJKg1zRQD2AAAJAAgJKg1zRQD2AAAAAA==.',
Mi='Micro:BAAALgAECgkJEwAAAA==.Microkeg:BAAALgAECgcJBAAAAA==.Microslash:BAAALgADCgMJAwABLgAECgkJEwABAAAAAA==.Minji:BAAALgAFFAEJAQABLgAFFAQJEQAHADMkAA==.Minsoo:BAACLgAFFH8MAAIVAAQJTBgxKgAfAQAVAAQJTBgxKgAfAQAuAAQKfxwAAhUACQkFHkgNAMcCABUACQkFHkgNAMcCAAAA.Mistblade:BAAALgAECgQJCwABLgAECgkJGQANAAkSAA==.Miststriker:BAAALgAECgUJCQAAAA==.Mistytaco:BAAALgAECgEJAQAAAA==.',
Ml='Mlrglett:BAABLgAECn9FAAMXAAkJqSJmAwDwAgAXAAkJqSJmAwDwAgAJAAEJihMfhgAqAAAAAA==.Mlrglo:BAAALgADCgcJCQAAAA==.',
Mm='Mmooney:BAAALgADCgIJAgABLgAECgkJFwAQADcOAA==.',
Mo='Moisturizeme:BAAALgAECgUJBQAAAA==.Mojomaker:BAABLgAECn8VAAIGAAYJAhLzXQBDAQAGAAYJAhLzXQBDAQAAAA==.Moojitsu:BAAALgADCgMJAwAAAA==.Mormegil:BAABLgAECn8nAAMLAAgJcyHNCACHAgALAAgJcyHNCACHAgAnAAEJeA3QOwAvAAAAAA==.Moshimoshi:BAACLgAFFH8XAAMGAAYJ6xFLHACKAQAGAAYJ6xFLHACKAQAFAAIJWAkySQBrAAAuAAQKfx4AAwUACQl4HGcbADcCAAUACAlHHGcbADcCAAYACAlHCXRRAD8BAAAA.Motosake:BAAALgAECgQJBQAAAA==.',
Mu='Muffinlord:BAAALgAECgYJEQAAAA==.Munkeebutt:BAABLgAECn8gAAQRAAkJMQmJHgCoAQARAAkJDQmJHgCoAQAEAAcJYAcoUwD/AAADAAEJsQst1QAwAAAAAA==.Munkeefase:BAAALgADCgEJAQAAAA==.',
My='Myronis:BAAALgADCgIJAgAAAA==.Mythaera:BAAALgADCgYJBwAAAA==.',
Na='Naberius:BAABLgAECn8ZAAMaAAgJ6RP3LwB4AQAaAAgJ6RP3LwB4AQAbAAEJJgsrPgArAAABLgAECggJIQAgAPsYAA==.Naillil:BAAALgAECgEJAQAAAA==.Namiiswan:BAAALgADCgMJBQAAAA==.Nasmine:BAAALgADCgEJAQAAAA==.Natsuki:BAAALgADCgUJBwAAAA==.',
Ne='Nefarius:BAAALgAFFAEJAQAAAA==.Neflite:BAABLgAECn8eAAIZAAcJvwfbGwDGAAAZAAcJvwfbGwDGAAAAAA==.Nelfie:BAAALgAECgEJAQAAAA==.Nessará:BAABLgAECn8WAAIHAAYJQCHvFQAjAgAHAAYJQCHvFQAjAgAAAA==.',
Ni='Nineõseven:BAABLgAECn8YAAIUAAcJixN9IADVAQAUAAcJixN9IADVAQABLgAECgEJAQABAAAAAA==.Ninjapro:BAAALgAECgkJAgAAAA==.Nixia:BAAALgAECgQJBQAAAA==.',
No='Nodiddy:BAAALgAECgQJDAABLgAECgcJJAASAPYhAA==.Nowari:BAAALgAECgQJBAABLgAECgkJKgAHADMNAA==.',
Nu='Nuraga:BAABLgAECn8hAAMlAAgJlyHXBwCpAgAlAAcJCSTXBwCpAgAQAAEJ7hK1lwBDAAAAAA==.',
Ob='Obeeone:BAAALgAECgEJAgAAAA==.Obviate:BAAALgAECgEJAQAAAA==.',
On='Onasta:BAABLgAECn8hAAIKAAkJkx+KOAAdAgAKAAkJkx+KOAAdAgAAAA==.Onelastkiss:BAAALgAECgEJAQAAAA==.',
Oo='Oogway:BAAALgADCgUJBQAAAA==.',
Op='Oprahheals:BAABLgAECn8cAAICAAkJFB6fGACvAgACAAkJFB6fGACvAgAAAA==.',
Or='Oreoagane:BAAALgAECgYJBwAAAA==.Oreobeer:BAAALgAECgEJAQAAAA==.Oreomonster:BAAALgAECgcJEQAAAA==.Orquesta:BAAALgAECgQJCwAAAA==.',
Pa='Paccer:BAAALgAECgEJAQAAAA==.Pacerx:BAAALgAECgIJAgAAAA==.Pandaemonia:BAACLgAFFH8cAAIkAAUJpg/qBwDYAAAkAAUJpg/qBwDYAAAuAAQKfyQAAiQACQncDaMWAPIAACQACQncDaMWAPIAAAAA.Pandakyle:BAABLgAECn8XAAIVAAYJ5xdCSgBDAQAVAAYJ5xdCSgBDAQAAAA==.Pandexander:BAAALgADCgMJAwAAAA==.Panterå:BAAALgAECgEJAgAAAA==.Parts:BAABLgAECn8iAAISAAgJtiGIIQDtAgASAAgJtiGIIQDtAgABLgAFFAYJGQAnAMAYAA==.Patchmen:BAAALgAECgQJBAAAAA==.Pattilicious:BAABLgAECn8kAAICAAkJZwt6egB5AQACAAkJZwt6egB5AQAAAA==.',
Pe='Pepsizero:BAAALgAECgUJCwAAAA==.',
Ph='Phlesh:BAAALgAECgEJAgAAAA==.Phlvrabies:BAAALgADCgMJBQAAAA==.Phonedin:BAABLgAECn8jAAMcAAkJERmdBgCIAgAcAAkJERmdBgCIAgAaAAMJBhchSQCyAAAAAA==.Phoënix:BAACLgAFFH8YAAMGAAYJzxVcGQCcAQAGAAYJzxVcGQCcAQAFAAIJwQOcUABUAAAuAAQKfywAAwYACQmWHdMSALYCAAYACQmWHdMSALYCAAUABAnmGL1lALQAAAAA.',
Pi='Pieglaive:BAABLgAECn8jAAMOAAkJzSGyCAChAgAOAAkJzSGyCAChAgANAAIJuhZpwwB2AAAAAA==.Pierres:BAAALgAECgkJEgAAAA==.Piondelth:BAAALgAECgcJEQAAAA==.',
Pl='Plantman:BAAALgAECgYJDgAAAA==.',
Po='Pointyboner:BAAALgADCgYJCAAAAA==.Poofort:BAAALgAECgYJDwAAAA==.Pooner:BAAALgADCgMJAwAAAA==.Porkins:BAAALgAECgMJAwAAAA==.Postoak:BAAALgAECgUJCgAAAA==.Powerochrist:BAABLgAECn8xAAIeAAkJ+BlmEACVAgAeAAkJ+BlmEACVAgAAAA==.',
Pr='Priscila:BAAALgADCgYJBgAAAA==.Proxzy:BAABLgAECn8ZAAIFAAgJ/yD2DACWAgAFAAgJ/yD2DACWAgAAAA==.',
Pu='Pubessalad:BAABLgAECn8xAAICAAYJHB0KZQClAQACAAYJHB0KZQClAQAAAA==.Puddin:BAAALgADCgQJBwAAAA==.Puffytaco:BAAALgAECgYJCwABLgAECgkJJAACACMdAA==.',
Py='Pyrug:BAAALgAECgUJCAABLgAECgkJOAAPAGwWAA==.',
Qu='Qualek:BAABLgAECn8XAAIlAAkJMRJfEAADAgAlAAkJMRJfEAADAgAAAA==.Quilue:BAABLgAECn8hAAISAAkJ0xOTQgAUAgASAAkJ0xOTQgAUAgAAAA==.',
Ra='Rannmagnison:BAABLgAECn82AAICAAkJOgjYigBbAQACAAkJOgjYigBbAQAAAA==.Raquoon:BAABLgAECn8ZAAIlAAgJLQ9BHwA5AQAlAAgJLQ9BHwA5AQAAAA==.Rasonia:BAAALgAECgYJBgABLgAFFAQJDAAfAOERAA==.Ratfu:BAAALgADCgcJDQAAAA==.Raumulus:BAAALgAECgkJCwAAAA==.Razjin:BAABLgAECn8aAAMGAAkJeiPsCQDaAgAGAAkJeiPsCQDaAgAFAAEJ/wqvsgAnAAAAAA==.',
Re='Reapér:BAAALgAECgkJBQAAAA==.Reckjames:BAAALgAECgEJAQAAAA==.Rene:BAAALgADCgYJBgAAAA==.Reze:BAACLgAFFH8UAAIWAAQJayCVDABeAQAWAAQJayCVDABeAQAuAAQKfxYAAhYACAlYHqcRADYCABYACAlYHqcRADYCAAEuAAUUCQlMAA4A2CUA.',
Rh='Rhaeynera:BAABLgAECn8uAAIcAAkJJAbzDwALAQAcAAkJJAbzDwALAQAAAA==.Rhyel:BAAALgADCgIJAgAAAA==.Rhyno:BAAALgADCgkJGwABLgAECgkJNwAPAEIgAA==.Rhysedwyn:BAAALgADCgkJEgABLgAECgEJAQABAAAAAA==.',
Ri='Riezen:BAABLgAECn8WAAIKAAkJ9hGGAwDsAAAKAAkJ9hGGAwDsAAAAAA==.Ringol:BAAALgAECgQJCgABLgAECgYJDgABAAAAAA==.Rinorik:BAABLgAECn83AAMPAAkJQiDZEQC9AgAPAAkJQiDZEQC9AgAZAAYJCRn2FACjAQAAAA==.Rizzdor:BAAALgADCgcJCAABLgAECgkJEgABAAAAAA==.',
Ro='Rockbiter:BAAALgAECgEJAgAAAA==.Rockhhard:BAABLgAECn8eAAIGAAkJxx5dHwBUAgAGAAkJxx5dHwBUAgAAAA==.Roeken:BAABLgAECn86AAIQAAkJKRXWIADqAQAQAAkJKRXWIADqAQAAAA==.Rollingman:BAABLgAECn8XAAIVAAgJZxYsJQD6AQAVAAgJZxYsJQD6AQAAAA==.Roummi:BAAALgAECgEJAQAAAA==.',
Ru='Rudybear:BAAALgAECgEJAQABLgAFFAEJAgABAAAAAA==.Rudyrots:BAAALgAECgEJAQABLgAFFAEJAgABAAAAAA==.Rudyshoots:BAAALgAFFAEJAgAAAA==.Rum:BAAALgAECgMJAwAAAA==.',
Ry='Rybear:BAAALgADCgkJCwAAAA==.Rygaard:BAABLgAECn84AAIlAAkJHyIjBQDJAgAlAAkJHyIjBQDJAgAAAA==.Rystic:BAAALgADCgkJGQAAAA==.Ryutiz:BAABLgAECn8sAAIEAAkJbSLuAQDqAgAEAAkJbSLuAQDqAgAAAA==.Ryward:BAAALgADCgcJBwAAAA==.Ryyuk:BAAALgAECgMJBAABLgAECgkJGQANAAkSAA==.',
Sa='Sacridas:BAAALgAECgEJAQABLgAECgkJLAAEAG0iAA==.Sako:BAAALgADCgUJCgAAAA==.Salandar:BAAALgAECgIJAgABLgAECgkJNgACADoIAA==.Samsó:BAABLgAECn8ZAAMCAAkJrBjEaQCrAQACAAkJrBjEaQCrAQAeAAQJ3BQNagDSAAAAAA==.Sapharina:BAACLgAFFH8MAAIfAAQJ4RH3JgASAQAfAAQJ4RH3JgASAQAuAAQKfzMAAh8ACQmWF+4QAGQCAB8ACQmWF+4QAGQCAAAA.Sassgrip:BAAALgADCgEJAQABLgAECgcJDQABAAAAAA==.Sassier:BAAALgAECgcJDQAAAA==.Sathenaz:BAAALgADCgcJCQAAAA==.',
Sc='Scarcy:BAACLgAFFH8aAAIIAAcJoBYzCwDnAQAIAAcJoBYzCwDnAQAuAAQKfzMAAwgACQliGrAQAJ0CAAgACQliGrAQAJ0CACYAAwmXCHkeAFoAAAAA.',
Se='Seacotton:BAABLgAECn8fAAMoAAkJvxuaBwB9AgAoAAkJFRuaBwB9AgAQAAcJoBVaQACjAQAAAA==.Searfang:BAACLgAFFH8UAAIFAAUJVBZtIgARAQAFAAUJVBZtIgARAQAuAAQKfzgAAwUACQmEIYgHAOQCAAUACQmEIYgHAOQCAAYAAQljE8DTADYAAAAA.Seariel:BAAALgAECgUJBwAAAA==.Seatea:BAAALgADCgkJCQABLgAECgkJOAAaACAhAA==.Selestra:BAAALgAFFAIJAgAAAA==.Selinise:BAAALgAECgUJBQAAAA==.Sematic:BAAALgAFFAEJAQABLgAFFAYJFQASABkcAA==.Senpai:BAAALgAECgQJBAAAAA==.Seraphymm:BAAALgADCgEJAQAAAA==.',
Sh='Shadowjacker:BAACLgAFFH8TAAINAAUJ9BuBPAA0AQANAAUJ9BuBPAA0AQAuAAQKfzgAAg0ACQkmIYIHAFEDAA0ACQkmIYIHAFEDAAAA.Shadowmidget:BAABLgAECn8WAAIPAAkJ3BahVwDBAQAPAAkJ3BahVwDBAQAAAA==.Shadrielis:BAABLgAECn9EAAMfAAkJvR+ICQDZAgAfAAkJvR+ICQDZAgAHAAIJVQ3VbgBsAAAAAA==.Shanlao:BAAALgAFFAIJAgABLgAFFAcJIQAPADwRAA==.Shirkka:BAAALgADCgMJBAAAAA==.Shurihito:BAABLgAECn8lAAICAAkJiR5NIgB9AgACAAkJiR5NIgB9AgAAAA==.',
Si='Sieron:BAABLgAECn8UAAIKAAYJ/RxdkgBBAQAKAAYJ/RxdkgBBAQAAAA==.Silaslunark:BAAALgAECgkJCwAAAA==.Sinkrow:BAAALgAECgYJBgAAAA==.Sixpack:BAABLgAECn8dAAIgAAkJjA70PACfAQAgAAkJjA70PACfAQAAAA==.',
Sk='Skarigar:BAAALgAECgEJAwAAAA==.Skeeterson:BAAALgADCgUJCAAAAA==.Skurplock:BAAALgADCgEJAQAAAA==.Skytec:BAAALgADCgMJAwAAAA==.Skëëts:BAABLgAECn8cAAQfAAgJSBBBKQCJAQAfAAgJJBBBKQCJAQAUAAEJuwThkwAnAAAHAAEJ5gaudAAlAAAAAA==.Skùrvypete:BAAALgAFFAEJAQAAAA==.',
Sl='Slampoof:BAAALgAECgQJDQAAAA==.Slamslayer:BAAALgAECgEJAQAAAA==.Sleez:BAAALgAECgYJDAAAAA==.Sloodraga:BAAALgADCgYJBgAAAA==.',
Sm='Smallgregory:BAAALgAECgYJDAAAAA==.',
Sn='Sneakdead:BAAALgAECgcJCgAAAA==.Sneakerzz:BAAALgADCgQJBAAAAA==.Sneakfury:BAAALgAECgYJCgABLgAECgcJCgABAAAAAA==.Sneeler:BAAALgAECgEJAQAAAA==.Snowscayia:BAACLgAFFH8MAAQgAAYJARjbLAACAQAgAAQJwBDbLAACAQAJAAUJSQh4KwDfAAAdAAIJIQqcGABuAAAuAAQKfy4ABAkACQkbGDMnAMUBAAkACAk2GjMnAMUBACAABwleGD87ALgBAB0AAQlhCfJQADcAAAAA.',
So='Solanar:BAABLgAECn8+AAMeAAkJgSMKEQCNAgAeAAgJsiMKEQCNAgACAAcJESHEMQA5AgAAAA==.Solesin:BAAALgAFFAEJAQABLgAFFAUJEwAbADIXAA==.Solm:BAAALgADCgkJJAAAAA==.Solmina:BAABLgAECn83AAISAAkJIh7iHwCfAgASAAkJIh7iHwCfAgAAAA==.Somniatis:BAAALgAECgEJAQAAAA==.Soobin:BAAALgAECgkJCQAAAA==.Soulciopath:BAAALgAECgUJCAAAAA==.Souljin:BAAALgADCgMJAwAAAA==.',
Sp='Spartan:BAAALgAECgQJBAAAAA==.Spicypants:BAAALgADCgMJAwAAAA==.Spicytaco:BAAALgAECgUJCgABLgAECgkJJAACACMdAA==.Spookuleli:BAAALgADCggJCwAAAA==.Sprinklewiz:BAAALgADCgMJAwAAAA==.',
Sq='Squadie:BAABLgAECn87AAIDAAkJOQv2aQBuAQADAAkJOQv2aQBuAQAAAA==.Squanchs:BAACLgAFFH8XAAIGAAYJ5xn5FAC+AQAGAAYJ5xn5FAC+AQAuAAQKfx4AAwYACQlkHygMAL8CAAYACQlkHygMAL8CAAUAAQkGAPTHAAEAAAEuAAQKBwkcACAAkxsA.Squanchy:BAABLgAECn8cAAIgAAcJkxtxPACyAQAgAAcJkxtxPACyAQAAAA==.Squisquee:BAAALgADCgcJBwAAAA==.',
Sr='Srbojangles:BAAALgAECgcJCAABLgAECgcJJAASAPYhAA==.Srry:BAABLgAECn8VAAIQAAcJsBrUKQATAgAQAAcJsBrUKQATAgAAAA==.',
St='Stinkvile:BAAALgAECgEJAQAAAA==.Stonebraid:BAAALgADCgEJAQAAAA==.Sturdy:BAAALgADCgEJAQAAAA==.',
Su='Suiféng:BAAALgAFFAIJAwAAAA==.Sukuna:BAAALgAECgYJCAAAAA==.Sundance:BAAALgAECgkJEQAAAA==.Surmise:BAACLgAFFH8VAAMSAAYJGRwlFAB6AQASAAYJkxslFAB6AQAiAAEJBSMCBQBhAAAuAAQKfzMAAxIACQkBJa0FAFYDABIACQkBJa0FAFYDACIABAlVIBkJAAQBAAAA.Sust:BAABLgAFFH8HAAINAAQJOReJPgAtAQANAAQJOReJPgAtAQABLgAFFAYJFQASABkcAA==.Sustenance:BAAALgAFFAIJBAABLgAFFAYJFQASABkcAA==.',
Sw='Swayzeetrain:BAACLgAFFH8eAAMeAAUJfybgCAAwAgAeAAUJfybgCAAwAgACAAEJpAxQMABUAAAuAAQKfxsAAwIACQkCHCxmALQBAAIABwkgGixmALQBAB4ACAn1IOA2AKABAAAA.',
Sy='Sydris:BAAALgAECgkJBQAAAA==.Syrrel:BAAALgADCgQJBAAAAA==.',
['Sü']='Süß:BAAALgAFFAIJAgABLgAFFAQJCQANAL8NAA==.',
Ta='Tabius:BAABLgAECn8mAAMdAAkJXR7+CQAiAgAdAAkJXR7+CQAiAgAJAAMJyw4XYwCOAAAAAA==.Talkingtaco:BAABLgAECn8kAAICAAkJIx0sHwCMAgACAAkJIx0sHwCMAgAAAA==.Taln:BAAALgAECgEJAwABLgAECggJJwALAHMhAA==.Talìa:BAAALgADCgIJAgABLgAECgEJAQABAAAAAA==.Tareul:BAAALgADCgIJAgAAAA==.Tarn:BAAALgAECgkJEgAAAA==.',
Te='Temok:BAABLgAECn8kAAICAAgJTRDodACEAQACAAgJTRDodACEAQAAAA==.',
Th='Thiccbush:BAAALgAECgEJAQAAAA==.Thirielnet:BAAALgAECggJDwAAAA==.This:BAAALgAECgEJAQAAAA==.Thorisdead:BAAALgAECgMJBQABLgAECggJKAATAO8LAA==.Thorkell:BAAALgADCgUJBQAAAA==.Thosen:BAAALgAECgYJEgAAAA==.',
Ti='Tinkaballah:BAAALgAECgcJDgAAAA==.Tipy:BAAALgADCgUJBQAAAA==.',
To='Tore:BAACLgAFFH8XAAIDAAYJIxr3MQBLAQADAAYJIxr3MQBLAQAuAAQKfzMAAgMACQmUIqcJAPwCAAMACQmUIqcJAPwCAAAA.Totemangge:BAAALgAFFAEJAQAAAA==.Totesmagoat:BAAALgADCgYJBgAAAA==.',
Tr='Trifectas:BAAALgADCgcJGQAAAA==.Trinadel:BAACLgAFFH8WAAIJAAYJVRG4FgBlAQAJAAYJVRG4FgBlAQAuAAQKfx0AAgkACAmnHS8PAK0CAAkACAmnHS8PAK0CAAAA.Träitors:BAAALgADCgcJEwAAAA==.Tråitors:BAABLgAECn87AAMPAAYJ7yJ7OQD0AQAPAAYJ7yJ7OQD0AQAZAAEJAAA0ZQBFAAABLgADCgcJEwABAAAAAA==.',
Ts='Tsarevich:BAABLgAECn8ZAAIiAAgJ7wl7BwA1AQAiAAgJ7wl7BwA1AQAAAA==.Tshera:BAAALgAECgEJAQABLgAECgkJNgACADoIAA==.',
Tu='Tugtheshaman:BAABLgAECn8dAAIGAAgJoxgmGgBGAgAGAAgJoxgmGgBGAgAAAA==.Tunechii:BAAALgAECgMJBAABLgAECgkJGQANAAkSAA==.',
Tw='Twileaf:BAABLgAECn82AAIgAAkJRAlsYQARAQAgAAkJRAlsYQARAQAAAA==.Twoinchisbig:BAABLgAECn9OAAIlAAkJLRs6CgBPAgAlAAkJLRs6CgBPAgAAAA==.',
Ty='Typhoidmary:BAABLgAECn8XAAMPAAgJhAmIggBVAQAPAAcJhAmIggBVAQAZAAEJAAAOdgAuAAABLgAFFAMJAwABAAAAAA==.',
['Té']='Térror:BAAALgAECgcJDwAAAA==.',
Ug='Ugtales:BAAALgAECgEJAQAAAA==.',
Un='Unbenched:BAAALgADCgQJBQABLgAECgkJOQAFAHofAA==.Uncool:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Unholyz:BAAALgAECgUJCAAAAA==.Unstable:BAAALgAECgEJAQAAAA==.',
Ur='Ursoc:BAABLgAECn84AAMJAAkJ9hLKHgDRAQAJAAkJ9hLKHgDRAQAgAAYJRxHVWQAqAQAAAA==.Urteg:BAAALgADCgkJFAAAAA==.',
Ut='Uthmansur:BAAALgAECgEJAgAAAA==.',
Uu='Uub:BAAALgAECgIJAgAAAA==.',
Va='Vairekor:BAAALgAECgYJCgABLgAFFAcJIQAPADwRAA==.Valdria:BAAALgADCgUJBQAAAA==.Vanillaçake:BAAALgAFFAEJAQAAAA==.Vanishja:BAAALgAECgYJDwAAAA==.Varkbyte:BAABLgAECn8XAAIHAAcJbBPdJACdAQAHAAcJbBPdJACdAQAAAA==.Varrik:BAACLgAFFH8aAAMQAAUJWCF6EwBuAQAQAAUJWCF6EwBuAQAoAAMJ7hhjKADLAAAuAAQKfykAAxAACQkeI4oJABUDABAACQkeI4oJABUDACgABgmcG00fAGMBAAAA.',
Ve='Vec:BAAALgAECgYJDQAAAA==.Velamor:BAABLgAECn8YAAQkAAYJzgtNHQCxAAAkAAYJ5gpNHQCxAAAOAAMJygk5VQCTAAANAAMJagrn2QCCAAAAAA==.Velaria:BAAALgADCgcJBwAAAA==.',
Vi='Violynt:BAAALgADCgEJAQAAAA==.',
Vo='Volieu:BAABLgAECn8jAAIiAAkJPRSCAwDnAQAiAAkJPRSCAwDnAQAAAA==.Volklin:BAABLgAECn8iAAMGAAgJqQkLYAA8AQAGAAgJqQkLYAA8AQAFAAYJIgnzXgDHAAAAAA==.Voyageurs:BAABLgAECn8cAAIdAAkJpBwuBgCHAgAdAAkJpBwuBgCHAgAAAA==.',
Vy='Vyrka:BAAALgAECgMJDQAAAA==.',
Wa='Wallstreet:BAAALgAECgUJBQAAAA==.Warroute:BAAALgAECgUJBQABLgAFFAQJCQANAL8NAA==.Waterdweller:BAAALgAECgEJBAAAAA==.',
We='Wegl:BAABLgAECn8WAAISAAUJhRdtwgAGAQASAAUJhRdtwgAGAQAAAA==.Werebear:BAAALgADCgMJAwABLgAECgQJBQABAAAAAA==.Werewithal:BAAALgAECgUJCQABLgAECgkJKQARALoSAA==.Wesleypipes:BAAALgAECgEJAQAAAA==.Wetfloorsign:BAAALgAECgYJEQAAAA==.',
Wh='Wholeymilk:BAAALgAECgQJCAAAAA==.',
Wi='Wiindsslashh:BAAALgAECgYJBwAAAA==.Wilbur:BAAALgADCgQJBQAAAA==.Windslash:BAAALgAECgIJAgAAAA==.Wish:BAAALgAECgYJCQAAAA==.',
Wo='Wonderx:BAAALgADCgIJAgAAAA==.Wonyoung:BAACLgAFFH8RAAIHAAQJMyRsDACDAQAHAAQJMyRsDACDAQAuAAQKfzIAAgcACQnzI9kBAFgDAAcACQnzI9kBAFgDAAAA.',
Wr='Wraithwok:BAAALgAECgUJBgAAAA==.',
Wu='Wuthrad:BAAALgAECgEJAQAAAA==.',
['Wü']='Würzig:BAABLgAFFH8HAAMKAAUJDAmngQAEAQAKAAUJDAmngQAEAQALAAIJ4AO5OABSAAABLgAFFAQJCQANAL8NAA==.',
Xa='Xala:BAABLgAECn8VAAMLAAkJbw0eIgBCAQALAAkJ+QweIgBCAQAnAAIJ+AduMABcAAAAAA==.Xalah:BAAALgAECggJEgAAAA==.Xalaz:BAACLgAFFH8WAAMPAAYJZQ4APABcAQAPAAYJZQ4APABcAQAZAAEJVwJgGgBGAAAuAAQKfx0AAw8ACQlXHHQ2ADICAA8ACAlXHHQ2ADICABkAAgkLFGNSAHcAAAAA.Xanaris:BAAALgADCgEJAQABLgAFFAIJCgAKAL0mAA==.Xandumbra:BAAALgADCgEJAQAAAA==.Xarosea:BAACLgAFFH8MAAICAAQJPxMfUQANAQACAAQJPxMfUQANAQAuAAQKfyoAAgIABwk6JPYYANMCAAIABwk6JPYYANMCAAAA.',
Xe='Xelienn:BAAALgAECgQJBwAAAA==.Xelojr:BAAALgADCgkJHAAAAA==.',
Xh='Xhael:BAAALgADCgEJAQAAAA==.',
Xi='Xia:BAABLgAECn9CAAIHAAkJqRkzFQA0AgAHAAkJqRkzFQA0AgAAAA==.Xilstorm:BAAALgAECgcJBwAAAA==.',
Xo='Xoilkick:BAABLgAECn8VAAIWAAgJqBY4AQDyAAAWAAgJqBY4AQDyAAAAAA==.Xoilwings:BAAALgAECgIJAgAAAA==.Xooiill:BAAALgAECggJEQAAAA==.',
Xp='Xpacer:BAAALgAECgcJEwAAAA==.',
['Xê']='Xêna:BAAALgAECgUJDQAAAA==.',
Ye='Yekira:BAAALgADCgEJAgAAAA==.Yellowsnøw:BAACLgAFFH8JAAISAAMJRAcxkQC1AAASAAMJRAcxkQC1AAAuAAQKfzwAAhIACQnwF9osAGYCABIACQnwF9osAGYCAAAA.',
Yu='Yumeshade:BAAALgAECgYJCwAAAA==.',
Za='Zaila:BAAALgAECgUJBQAAAA==.Zal:BAAALgAECgYJBgABLgAFFAcJEAAlANwWAA==.Zamari:BAAALgAECggJEQAAAA==.Zanazer:BAAALgAECgcJBgABLgAECgkJPgAeAIEjAA==.Zanzabar:BAABLgAECn8WAAIdAAkJegvGEACgAQAdAAkJegvGEACgAQAAAA==.Zathmage:BAAALgADCgMJAwAAAA==.Zaxin:BAABLgAECn8XAAMHAAkJDQ4QJwCNAQAHAAkJDQ4QJwCNAQAUAAUJiAQeSwCtAAAAAA==.',
Ze='Zelfie:BAAALgADCgUJBQAAAA==.Zellda:BAAALgAECgYJCQAAAA==.Zerodarkness:BAAALgADCgkJCQAAAA==.Zeros:BAABLgAECn8XAAISAAkJeBgcPAApAgASAAkJeBgcPAApAgAAAA==.',
Zi='Ziperz:BAAALgAECggJCAAAAA==.',
Zo='Zoerina:BAAALgAECgcJDwAAAA==.Zoobilong:BAABLgAECn8VAAICAAUJoRIfuwAQAQACAAUJoRIfuwAQAQAAAA==.',
Zx='Zxak:BAABLgAECn85AAIOAAkJaSb1BAD1AgAOAAkJaSb1BAD1AgAAAA==.',
Zy='Zyahk:BAAALgADCgQJBQAAAA==.Zynn:BAAALgAECgEJAgAAAA==.',
['Zë']='Zën:BAAALgAECgEJAQABLgAFFAUJFAAfAO8LAA==.',
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
