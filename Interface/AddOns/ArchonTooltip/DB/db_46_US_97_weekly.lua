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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Elemental','Shaman-Restoration','Priest-Holy','Rogue-Subtlety','Druid-Balance','Rogue-Assassination','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','DeathKnight-Unholy','Warrior-Fury','Hunter-Survival','Mage-Frost','Monk-Brewmaster','Priest-Shadow','DeathKnight-Blood','Monk-Mistweaver','Monk-Windwalker','Warlock-Affliction','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Druid-Guardian','Druid-Feral','Paladin-Holy','Priest-Discipline','Druid-Restoration','Paladin-Protection','Mage-Arcane','Shaman-Enhancement','DemonHunter-Vengeance','Warrior-Protection','Rogue-Outlaw','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abandonhope:BAAALgAECgMJAwABLgAECgkJDwABAAAAAA==.',
Ac='Accuser:BAAALgADCgEJAQAAAA==.Acky:BAAALgADCgUJBQAAAA==.',
Ad='Adwen:BAABLgAECn8bAAICAAYJPRqxgABiAQACAAYJPRqxgABiAQAAAA==.',
Ae='Aenimal:BAAALgAECgYJEAAAAA==.Aer:BAAALgADCgkJCQAAAA==.Aeronemon:BAAALgAECgEJAgAAAA==.',
Ai='Airill:BAAALgADCgQJBQAAAA==.',
Ak='Akforty:BAABLgAECn8fAAMDAAkJIiHNCgDvAgADAAkJIiHNCgDvAgAEAAIJoBV7eABfAAAAAA==.Akittymeow:BAABLgAECn8bAAMFAAkJuw+lQgAZAQAFAAgJKQ+lQgAZAQAGAAMJiwVhoAB2AAAAAA==.',
Al='Aldredevon:BAAALgAECgEJAQAAAA==.Aleshock:BAAALgAECgkJEQAAAA==.Alidar:BAAALgAECgcJEwAAAA==.Alphaboner:BAAALgADCgYJBwAAAA==.Altairis:BAAALgAECgEJAgAAAA==.Altartoy:BAABLgAECn8hAAIHAAgJ6QoZNQAgAQAHAAgJ6QoZNQAgAQAAAA==.Althunter:BAACLgAFFH8NAAIEAAQJUiGlDgBhAQAEAAQJUiGlDgBhAQAuAAQKfxsAAgQACAneIUwGACUCAAQACAneIUwGACUCAAAA.',
Am='Amanita:BAAALgAECgQJBAABLgAECggJEAABAAAAAA==.Amelina:BAAALgAECgYJDgAAAA==.Amerit:BAAALgAECgEJAQAAAA==.Amorir:BAACLgAFFH8MAAICAAQJSwM5XQDfAAACAAQJSwM5XQDfAAAuAAQKf0cAAgIACQnsEiZUAMMBAAIACQnsEiZUAMMBAAAA.Amorit:BAAALgAFFAIJAgAAAA==.Amorydalias:BAAALgAECgUJBgAAAA==.Amozon:BAAALgADCgEJAQAAAA==.',
An='Anamortem:BAAALgAECgMJAwABLgAECgkJIQAIAAcZAA==.Anastala:BAABLgAECn8rAAIJAAkJ5RUhGAAAAgAJAAkJ5RUhGAAAAgAAAA==.Andeddo:BAAALgAFFAEJAQAAAA==.Angchu:BAAALgADCgQJBAAAAA==.Angelmàker:BAAALgAECgMJBAABLgADCgcJEwABAAAAAA==.Angelmäker:BAAALgAECgQJBgABLgADCgcJEwABAAAAAA==.Annesta:BAABLgAECn8hAAMIAAkJBxkJFwDWAQAIAAkJ0hgJFwDWAQAKAAEJ9xbBIwA9AAAAAA==.',
Ap='Apostus:BAAALgADCgcJDgAAAA==.Apothica:BAAALgAECgUJBgAAAA==.',
Aq='Aquafox:BAABLgAECn8jAAMGAAgJWCDnDgDRAgAGAAgJWCDnDgDRAgAFAAMJ+xP+XwC0AAAAAA==.',
Ar='Archontas:BAABLgAECn8kAAIJAAgJkSFBCgCnAgAJAAgJkSFBCgCnAgAAAA==.Ariodh:BAABLgAECn87AAMLAAkJLSYoAgBhAwALAAkJLSYoAgBhAwAMAAUJpB9eJACaAQAAAA==.Arkaline:BAAALgAECgEJAQAAAA==.Artuarry:BAACLgAFFH8gAAINAAYJvRL6LAB3AQANAAYJvRL6LAB3AQAuAAQKfyYAAg0ACQlGH4EdAG0CAA0ACQlGH4EdAG0CAAAA.Aryndus:BAABLgAECn8lAAICAAkJcx4oGgCdAgACAAkJcx4oGgCdAgAAAA==.',
At='Athenà:BAAALgAECgUJBQAAAA==.',
Av='Avocado:BAABLgAECn8jAAMDAAkJnCVUDADnAgADAAkJHiNUDADnAgAEAAcJVCLkCgCwAQAAAA==.',
Ax='Axelaw:BAAALgADCgQJBAAAAA==.',
Ay='Ayrz:BAAALgAECgIJAgAAAA==.',
Az='Azaria:BAAALgADCgIJAgAAAA==.',
Ba='Baddjujumon:BAABLgAECn8XAAMFAAgJ0gQEUwDbAAAFAAgJ0gQEUwDbAAAGAAEJoAEg5QAdAAAAAA==.Baileyhowl:BAAALgAECgEJBQAAAA==.Bammie:BAAALgADCgYJCgAAAA==.Bananuth:BAAALgAECgIJAwABLgAFFAYJHwAOAJ4eAA==.Banthr:BAABLgAECn8VAAIPAAkJMw6oKgCkAQAPAAkJMw6oKgCkAQAAAA==.Barkert:BAAALgADCgQJAwAAAA==.Baroke:BAAALgAECgMJBwABLgAECggJIQAHAOkKAA==.Barokoshama:BAAALgAECgcJEQAAAA==.Basaltytaco:BAAALgADCgEJAQAAAA==.Battleworm:BAAALgADCgkJEwABLgAFFAMJAwABAAAAAA==.',
Bb='Bbalrd:BAACLgAFFH8FAAIOAAIJbRwBqgC1AAAOAAIJbRwBqgC1AAAuAAQKfxcAAg4ACQmiFydIAOIBAA4ACQmiFydIAOIBAAAA.',
Be='Bearglie:BAAALgAECggJDgAAAA==.Beepers:BAAALgAECgYJBgAAAA==.Beezelpup:BAAALgAECgYJCAAAAA==.',
Bi='Bigcow:BAAALgAECgUJCQAAAA==.',
Bl='Blackolives:BAAALgAECggJDQAAAA==.Bladesp:BAAALgAECgYJCgABLgAECgkJGQALAAkSAA==.Blondefu:BAAALgAECgUJCwAAAA==.Bloodybonne:BAAALgADCgcJBwAAAA==.Bloodyell:BAAALgAECgEJAQAAAA==.Bloore:BAAALgAECgMJAwABLgAECgkJLAAEAG0iAA==.Bluejuly:BAAALgAECgUJBQAAAA==.Blutø:BAAALgAECgYJDAAAAA==.',
Bo='Boflex:BAAALgADCgQJBgAAAA==.Bomboclat:BAAALgAECgUJCwAAAA==.Bonesknows:BAAALgADCgEJAQAAAA==.Boofy:BAAALgAECgMJAwABLgAECgkJFgANANwWAA==.Borhoag:BAAALgADCgEJAQABLgAECggJCwABAAAAAA==.Bowwie:BAACLgAFFH8QAAMQAAQJEBLOFgAJAQAQAAQJDwvOFgAJAQADAAMJZRANYgDHAAAuAAQKfysABAMACQmNHy0GACsDAAMACQkTHi0GACsDABAACAkPGA8WAO8BAAQAAQkVAxWTACcAAAAA.',
Br='Britney:BAAALgADCgkJCQAAAA==.Bronzé:BAABLgAECn8yAAIRAAcJMiMRMQBOAgARAAcJMiMRMQBOAgAAAA==.Brotherfrey:BAAALgAECggJEQAAAA==.Bruish:BAABLgAFFH8MAAISAAQJtwzFDQAWAQASAAQJtwzFDQAWAQAAAA==.',
Bu='Bubbadoo:BAABLgAECn8jAAIJAAgJhhCeKQB4AQAJAAgJhhCeKQB4AQAAAA==.Buddy:BAABLgAECn8ZAAITAAYJoRKzNwAtAQATAAYJoRKzNwAtAQABLgAECggJJwAUAHMhAA==.Bulan:BAABLgAECn9DAAIVAAkJsyRrAgCdAwAVAAkJsyRrAgCdAwAAAA==.',
Bw='Bweninger:BAAALgAECgEJAQAAAA==.',
['Bô']='Bôôsted:BAABLgAECn8dAAIFAAkJ0hTfIAAIAgAFAAkJ0hTfIAAIAgABLgAFFAEJAQABAAAAAA==.',
Ca='Caistan:BAAALgADCgYJCAAAAA==.Calyopi:BAAALgAFFAIJAgAAAA==.Candypants:BAABLgAECn8iAAQVAAkJuxVkHAAhAgAVAAkJuxVkHAAhAgASAAcJ9A4COgAMAQAWAAMJ2AvtYgCDAAAAAA==.Caoth:BAAALgAECgYJEwAAAA==.Cappilon:BAABLgAECn8XAAIRAAgJiyEZMABSAgARAAgJiyEZMABSAgAAAA==.Carcus:BAAALgAECggJDgAAAA==.Carmila:BAAALgADCgEJAQAAAA==.Cayleedah:BAABLgAECn8qAAIEAAgJfQqxEQA0AQAEAAgJfQqxEQA0AQAAAA==.Cayssaris:BAAALgAECgYJEwAAAA==.',
Cc='Cc:BAABLgAECn8WAAQXAAYJPBPsDgBCAQAXAAUJ9BPsDgBCAQAYAAYJKwstIwA+AQANAAQJzhP5tQDtAAAAAA==.',
Ce='Ceeti:BAABLgAECn84AAMZAAkJICEeCADQAgAZAAkJICEeCADQAgAaAAIJeAYcQABpAAAAAA==.Celandrelia:BAAALgAECgUJBQABLgAECggJLAAbAEQXAA==.',
Ch='Chaewon:BAAALgAECgYJCgABLgAFFAQJEQAHADMkAA==.Channeria:BAAALgAECgEJAQAAAA==.Chaoticoreo:BAABLgAECn8xAAMMAAkJOh79CACOAgAMAAkJOh79CACOAgALAAQJ4w9rrQCzAAAAAA==.Chappedlips:BAAALgAECgkJBwAAAA==.Chareyne:BAABLgAECn8ZAAIHAAgJ5RFyJgC5AQAHAAgJ5RFyJgC5AQAAAA==.Cheetor:BAAALgAECgMJAwABLgAFFAQJDQAQANQUAA==.Cheezytaco:BAAALgAECgYJDgABLgAECgkJJAACACMdAA==.Chidge:BAAALgADCggJCwAAAA==.Chikila:BAABLgAECn8jAAMYAAgJBhm2BgDjAQAYAAgJBhm2BgDjAQANAAMJeAwo2gCbAAAAAA==.Chilliflakez:BAABLgAECn8VAAIVAAYJNQ0CVQD/AAAVAAYJNQ0CVQD/AAAAAA==.Chro:BAAALgAECgcJBwABLgAECgkJNgAFAGEfAA==.',
Ci='Cindezar:BAAALgADCgMJAwAAAA==.',
Cl='Clementyn:BAABLgAECn8WAAICAAcJOBD0wgD4AAACAAcJOBD0wgD4AAAAAA==.Cleyi:BAABLgAECn8pAAIHAAgJxQ05LwBGAQAHAAgJxQ05LwBGAQAAAA==.',
Co='Coldpasta:BAAALgAECgYJDgABLgAFFAIJBAABAAAAAA==.Colonoscopy:BAAALgAECgMJBAAAAA==.Coreyy:BAAALgADCgUJBwAAAA==.Corva:BAACLgAFFH8UAAINAAQJKxKbTwAaAQANAAQJKxKbTwAaAQAuAAQKfyoAAg0ACQnpFSM/ANoBAA0ACQnpFSM/ANoBAAAA.Cosairi:BAAALgAECgYJEwAAAA==.Cougztroll:BAABLgAECn83AAMcAAkJlRV4EQDCAQAcAAkJlRV4EQDCAQAdAAYJ/gusJADRAAAAAA==.',
Cr='Crazaki:BAAALgADCgEJAQAAAA==.Crosseye:BAAALgADCgMJAwAAAA==.Crossie:BAAALgADCgEJAQAAAA==.',
Ct='Ctd:BAAALgADCgkJEgABLgAECgkJOAAZACAhAA==.',
Cu='Curfluffin:BAAALgADCgEJAQAAAA==.Cuttercupx:BAAALgAECgIJAgABLgAECgkJDwABAAAAAA==.',
Da='Dahn:BAAALgAECgIJAgAAAA==.Dakadin:BAABLgAECn8mAAMeAAkJ+yOyEQB8AgAeAAkJ+yOyEQB8AgACAAQJ7hc61ADgAAAAAA==.Daranne:BAACLgAFFH8XAAICAAUJaxZhOgAnAQACAAUJaxZhOgAnAQAuAAQKfykAAgIACQnwGhc/ACkCAAIACQnwGhc/ACkCAAAA.Darkenedstar:BAAALgAECgYJDQABLgAECgYJEAABAAAAAA==.Darksoulstwo:BAAALgADCgMJAwAAAA==.Dasbeans:BAABLgAECn8cAAMZAAkJNAm2QwAPAQAZAAgJPQq2QwAPAQAbAAIJkgHvRgARAAAAAA==.Dashy:BAABLgAECn8WAAMHAAgJ8R+jEgA6AgAHAAgJVBqjEgA6AgAfAAYJ4B4qFQAlAgAAAA==.Datran:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.',
De='Deaduglie:BAABLgAECn84AAMNAAkJbBb5MgAHAgANAAkJbBb5MgAHAgAYAAEJMQjvcQA0AAAAAA==.Deliandora:BAAALgAECgQJCAAAAA==.Delusional:BAAALgAECgcJDwAAAA==.Delynique:BAAALgADCgEJAQABLgAECgkJLAAEAG0iAA==.Demonx:BAAALgAECgEJAQAAAA==.Denaric:BAABLgAECn8WAAMgAAYJdxoeNADCAQAgAAYJdxoeNADCAQAJAAUJ6QhhXQCRAAABLgAECgcJEgABAAAAAA==.Dergen:BAAALgAECgkJCwABLgAECgkJDwABAAAAAA==.Destroyevsky:BAABLgAECn8gAAIPAAYJSwJsegB2AAAPAAYJSwJsegB2AAAAAA==.Detonate:BAABLgAECn8ZAAIRAAYJbhzreQB+AQARAAYJbhzreQB+AQAAAA==.',
Dh='Dhpoo:BAAALgADCgUJBAAAAA==.Dhvecx:BAAALgAECgUJBgABLgAECgYJDQABAAAAAA==.',
Di='Dilbo:BAAALgAFFAIJAgABLgAFFAYJIAAJAPAaAA==.Diomed:BAAALgAECgEJAQAAAA==.Diqoff:BAAALgADCgkJEgAAAA==.Diqon:BAABLgAECn84AAMOAAkJDRtDMQAyAgAOAAkJDRtDMQAyAgAUAAcJtxSxIQA7AQAAAA==.Disturbedtwo:BAAALgAECgYJCgAAAA==.',
Do='Dolphinz:BAACLgAFFH8UAAICAAUJ4RVQNAA0AQACAAUJ4RVQNAA0AQAuAAQKfzEAAwIACAnBIoQcAI8CAAIACAnBIoQcAI8CACEAAgnpCiI8AE4AAAAA.Doryadni:BAAALgADCgcJBgAAAA==.',
Dr='Draci:BAAALgAECgYJBgAAAA==.Dragonpede:BAACLgAFFH8JAAIZAAUJRRn5EwCsAQAZAAUJRRn5EwCsAQAuAAQKfzkAAhkACQkWIIIJALoCABkACQkWIIIJALoCAAAA.Dragonwarior:BAABLgAECn8fAAIPAAkJ6hv9KQCoAQAPAAkJ6hv9KQCoAQAAAA==.Drakindees:BAAALgAECgUJBQABLgAECgcJJAARAPYhAA==.Drakkyn:BAABLgAECn8aAAIPAAYJTR38LQCRAQAPAAYJTR38LQCRAQAAAA==.Drakonus:BAAALgAECgUJCQAAAA==.Dread:BAAALgADCgQJBAAAAA==.Drosuu:BAAALgAECgEJAQAAAA==.Druish:BAACLgAFFH8kAAIcAAYJ4SQHAgAZAgAcAAYJ4SQHAgAZAgAuAAQKfywAAxwACQk0JoUAAG4DABwACQk0JoUAAG4DAB0AAgkOD5ksAGEAAAAA.Drykkr:BAABLgAECn8mAAISAAkJnBYZGADfAQASAAkJnBYZGADfAQAAAA==.',
Du='Dullahan:BAAALgAECgUJBgAAAA==.Dunstie:BAAALgADCgEJAQABLgAECgcJGwAUACoeAA==.Durrik:BAAALgADCgcJBwAAAA==.',
['Dà']='Dàsh:BAAALgAECgYJBgABLgAECggJFgAHAPEfAA==.',
Ea='Eatrocks:BAAALgADCggJCAAAAA==.',
Ed='Edorn:BAAALgAECgUJBQAAAA==.',
Ef='Efn:BAAALgAECgYJEwAAAA==.',
El='Elcrys:BAABLgAECn8aAAIgAAcJ3Bb2NAC+AQAgAAcJ3Bb2NAC+AQAAAA==.Elentiya:BAAALgAECgQJBAAAAA==.Eleòs:BAAALgADCgYJBgAAAA==.Elion:BAAALgAECgEJAQAAAA==.Ellyra:BAABLgAFFH8FAAIDAAMJEAWkYgDFAAADAAMJEAWkYgDFAAAAAA==.Elpollo:BAABLgAECn8kAAMRAAcJ9iGUQgBwAgARAAcJ9iGUQgBwAgAiAAEJshe1HAA6AAAAAA==.Elsinn:BAAALgADCggJCgAAAA==.Elvar:BAAALgAECgYJEgAAAA==.',
Em='Emmdwemm:BAAALgAECgQJCgAAAA==.',
En='Enoki:BAAALgAECgQJBAAAAA==.',
Ep='Ephelia:BAACLgAFFH8WAAIGAAUJfiVJCAAfAgAGAAUJfiVJCAAfAgAuAAQKfxkAAwYACQlfGooiAA8CAAYACQlfGooiAA8CAAUAAQmMA/eUACAAAAAA.Epitome:BAABLgAECn8nAAIRAAkJeBY3PAAjAgARAAkJeBY3PAAjAgAAAA==.',
Er='Erid:BAAALgAECgcJEQAAAA==.',
Et='Etude:BAAALgADCgEJAQAAAA==.',
Ev='Evelyndel:BAAALgAECgYJBwAAAA==.Evergrey:BAABLgAECn8ZAAITAAcJsAzJNgAyAQATAAcJsAzJNgAyAQAAAA==.Evermoons:BAABLgAECn8jAAIgAAkJVxkuFQCWAgAgAAkJVxkuFQCWAgAAAA==.Evodaka:BAAALgAECgIJAwAAAA==.',
Fa='Falaria:BAAALgAECgQJBAAAAA==.Falasdaer:BAABLgAECn8iAAMLAAkJsiIPFACYAgALAAgJQCIPFACYAgAMAAQJViGtHACFAQAAAA==.Fallansting:BAAALgAECgkJEgAAAA==.Falstaff:BAABLgAECn8fAAISAAkJxhWlFQD2AQASAAkJxhWlFQD2AQAAAA==.Fartshooter:BAAALgAECgYJEQAAAA==.Fatterblunt:BAACLgAFFH8gAAIJAAYJ8BoRDgCeAQAJAAYJ8BoRDgCeAQAuAAQKfyYAAgkACQk3ILYNAMACAAkACQk3ILYNAMACAAAA.',
Fe='Fedner:BAABLgAECn8XAAIGAAcJSQ/oVABRAQAGAAcJSQ/oVABRAQAAAA==.Feldar:BAABLgAECn83AAICAAkJyiHkDQDtAgACAAkJyiHkDQDtAgAAAA==.Fend:BAAALgADCgQJBAAAAA==.Feronite:BAAALgAECgUJBQABLgAFFAQJEAAQABASAA==.Feyredarling:BAAALgAECgMJAwAAAA==.',
Fi='Fists:BAACLgAFFH8MAAISAAQJgBy0HgAoAQASAAQJgBy0HgAoAQAuAAQKfyoAAxIABgmEI44WAFQCABIABgmEI44WAFQCABYABAk3EqtUAL4AAAAA.Fizzbeard:BAAALgADCgcJCgAAAA==.Fizzical:BAAALgADCgkJDwAAAA==.Fizzleclaw:BAABLgAECn8bAAMcAAgJZBmEFgCLAQAcAAYJDxyEFgCLAQAJAAQJDRHBQwDvAAAAAA==.Fizzleded:BAAALgAECgQJBQABLgAECggJGwAcAGQZAA==.Fizzleflare:BAAALgADCgkJCQAAAA==.',
Fl='Flightrisk:BAAALgAECgQJBgABLgAECgkJDwABAAAAAA==.Florisa:BAABLgAECn8jAAICAAgJ5RzkPgD/AQACAAgJ5RzkPgD/AQAAAA==.',
Fo='Fool:BAAALgAECgUJBQABLgAFFAMJAwABAAAAAA==.Fordi:BAABLgAECn82AAMFAAkJYR/5CQC1AgAFAAkJYR/5CQC1AgAjAAMJ9RQPMwBQAAAAAA==.Forendor:BAAALgAECgMJBgAAAA==.Fourdy:BAABLgAECn8wAAIGAAcJCRm9PACtAQAGAAcJCRm9PACtAQAAAA==.',
Fr='Fragdoll:BAAALgAECgQJCgAAAA==.Freakinlarry:BAAALgADCgEJAQAAAA==.Freakinoak:BAABLgAECn8sAAIgAAkJoxSTIgArAgAgAAkJoxSTIgArAgAAAA==.Fredboat:BAAALgAECgEJAgABLgAFFAIJCgAOAL0mAA==.Free:BAABLgAECn8ZAAMLAAkJCRL1PwC9AQALAAgJCRL1PwC9AQAkAAUJ9Ap3IACAAAAAAA==.Frenn:BAAALgAECgUJBwAAAA==.Froost:BAACLgAFFH8QAAMOAAUJJhe+XgAsAQAOAAQJJhe+XgAsAQAUAAEJAAB3TAAAAAAuAAQKfxgAAg4ACQlfHvRMAAwCAA4ACQlfHvRMAAwCAAAA.',
Fu='Funkflex:BAAALgAECgEJAQABLgAECgkJGQALAAkSAA==.Furvert:BAAALgAECgkJDwAAAA==.Fushi:BAAALgAECgEJAQAAAA==.',
Ga='Gandis:BAAALgAECgkJEgAAAA==.Gapper:BAACLgAFFH8NAAIQAAQJ1BTMHADbAAAQAAQJ1BTMHADbAAAuAAQKf1EAAxAACQmLJQkBAF4DABAACQmLJQkBAF4DAAQAAQmXFsczAEQAAAAA.Gargodath:BAAALgAECgQJBQAAAA==.',
Gi='Gielinor:BAAALgADCgIJAgAAAA==.Gimbó:BAAALgADCgQJBgAAAA==.',
Gl='Glamour:BAAALgADCgEJAgAAAA==.Glestaar:BAABLgAECn8pAAMDAAgJnxyRLAAfAgADAAgJnxyRLAAfAgAEAAIJRQuFfABSAAAAAA==.Glitterpants:BAAALgAECgIJAgAAAA==.Glyr:BAAALgAECgYJCgAAAA==.',
Go='Goingrouge:BAAALgAECgYJCgAAAA==.Goldabelle:BAAALgAECgYJCgAAAA==.Goonkin:BAAALgAECgUJBQABLgAFFAQJDQAQANQUAA==.Gorlami:BAABLgAFFH8GAAICAAMJZA6odQCvAAACAAMJZA6odQCvAAAAAA==.Gothelf:BAAALgAFFAIJBAAAAA==.Gothri:BAAALgAECgcJCQABLgAECgcJFQAZAJAVAA==.Gothstraza:BAABLgAECn8VAAIZAAcJkBXzNgBHAQAZAAcJkBXzNgBHAQAAAA==.Gottemgood:BAAALgADCgUJBQAAAA==.',
Gr='Grimli:BAABLgAECn8hAAIGAAkJTw+5QgCVAQAGAAkJTw+5QgCVAQAAAA==.Growth:BAABLgAECn8ZAAMTAAkJNAlxKwBxAQATAAkJNAlxKwBxAQAfAAYJohA7NQAzAQAAAA==.',
Gu='Gurthcaptian:BAAALgAECgQJBAAAAA==.',
Gy='Gyatso:BAAALgADCgMJAwAAAA==.',
['Gá']='Gárròsh:BAAALgAECgYJBgAAAA==.',
Ha='Haerin:BAAALgAECgIJAgABLgAFFAQJEQAHADMkAA==.Happykilmøre:BAAALgAECgQJBAABLgAECgkJEgABAAAAAA==.Harnel:BAABLgAECn8vAAICAAgJ0ANH1ADgAAACAAgJ0ANH1ADgAAAAAA==.Haseo:BAAALgAECggJCwAAAA==.Hattorihanzo:BAAALgAECgYJDAAAAA==.',
He='Healeymonstr:BAAALgADCgIJAgAAAA==.Healmart:BAABLgAECn8YAAIfAAgJegbrNAA1AQAfAAgJegbrNAA1AQAAAA==.Heartëater:BAAALgADCgYJBgAAAA==.Hellinyoface:BAAALgADCgUJBQAAAA==.Heymage:BAAALgADCgkJCQAAAA==.',
Hi='Himothyy:BAAALgAECgQJBAAAAA==.',
Ho='Holypeetch:BAAALgADCgYJBgAAAA==.Hoofpics:BAAALgAECgQJBAAAAA==.Hordedefect:BAAALgAECgEJAQABLgAECgkJDwABAAAAAA==.Hoyer:BAAALgAECgkJEwAAAA==.',
Hu='Hulkhogan:BAAALgAECggJCQAAAA==.Humbledrink:BAAALgAECgQJBQAAAA==.',
Im='Impact:BAAALgADCgcJCgAAAA==.',
In='Inflícted:BAACLgAFFH8NAAIfAAUJ7wt4HQBIAQAfAAUJ7wt4HQBIAQAuAAQKfxUAAh8ACQlFESsXAA8CAB8ACQlFESsXAA8CAAAA.Innoscent:BAAALgAECgYJBgAAAA==.Inzo:BAAALgAFFAEJAgAAAA==.',
Io='Iove:BAABLgAECn8aAAIVAAkJZBX4HgAOAgAVAAkJZBX4HgAOAgAAAA==.',
Ja='Jahsahm:BAAALgAECgcJEQAAAA==.Jajung:BAAALgADCgMJAwAAAA==.Jakub:BAABLgAECn8hAAIUAAkJqRdbDQApAgAUAAkJqRdbDQApAgABLgAFFAQJEAAQABASAA==.Jakuren:BAAALgADCgYJBgAAAA==.Jamjam:BAAALgADCgYJCQAAAA==.',
Je='Jesit:BAABLgAECn8aAAIaAAYJ8hVhFAB8AQAaAAYJ8hVhFAB8AQAAAA==.',
Jh='Jhonn:BAAALgAECgEJAQABLgAECgkJRgAlAL8iAA==.',
Ji='Jingles:BAAALgADCgYJBgAAAA==.',
Jj='Jjada:BAACLgAFFH8HAAMLAAQJtQucTgDxAAALAAQJIQqcTgDxAAAkAAEJdBXIDwA9AAAuAAQKfx0AAwsACQnFIfAOAMICAAsACQl0IPAOAMICACQABgmeIYAFAE0CAAAA.',
Jo='Johnwolf:BAABLgAECn8UAAICAAYJ3gKVEgGTAAACAAYJ3gKVEgGTAAAAAA==.',
Jy='Jyade:BAABLgAECn8zAAMKAAkJMQ+dBwDUAQAKAAkJMQ+dBwDUAQAmAAUJnwifCAD6AAAAAA==.Jynoria:BAAALgADCgcJDAAAAA==.',
Ka='Kainlok:BAAALgADCgIJAgAAAA==.Kaiserice:BAAALgAECgcJEAAAAA==.Kaliel:BAAALgADCgEJAQAAAA==.Kamarra:BAABLgAECn8dAAIZAAcJOwcAUADiAAAZAAcJOwcAUADiAAAAAA==.Kamencider:BAABLgAECn8dAAIRAAcJ8RCbjwBTAQARAAcJ8RCbjwBTAQAAAA==.Kamidala:BAAALgAECgIJAgAAAA==.Kankles:BAACLgAFFH8FAAIJAAQJ3x45GABAAQAJAAQJ3x45GABAAQAuAAQKfyoAAgkACAnuIpEKAKECAAkACAnuIpEKAKECAAAA.Karva:BAAALgAECgIJAwAAAA==.Katabetta:BAAALgADCgMJAwAAAA==.',
Ke='Kellmagnison:BAAALgAECgIJAgABLgAECgkJMAACADMIAA==.Kentukee:BAAALgAECgIJAgABLgAECgkJJwAQAC0SAA==.Kernelpanic:BAACLgAFFH8fAAMOAAYJnh6pHwDOAQAOAAYJnh6pHwDOAQAnAAEJ/gVcJQA6AAAuAAQKfycAAg4ACQkCIggrAEwCAA4ACQkCIggrAEwCAAAA.Kessho:BAAALgAECgYJDwABLgAFFAQJEAAQABASAA==.Kevynn:BAAALgADCgMJAgAAAA==.Keyoshi:BAAALgAECgYJBgAAAA==.',
Ki='Kickrocks:BAAALgAECgEJAQAAAA==.Kilerforlife:BAAALgAECgYJCwAAAA==.Kilowog:BAAALgADCgUJCAAAAA==.Kilpally:BAAALgAECgYJBwAAAA==.Kintra:BAAALgADCgIJAgAAAA==.Kirin:BAAALgAECgEJAQAAAA==.Kirkle:BAABLgAECn9DAAIYAAkJaR0FAgCjAgAYAAkJaR0FAgCjAgAAAA==.Kithara:BAAALgAECgEJAwAAAA==.',
Ko='Kovie:BAAALgADCggJCAAAAA==.Kovy:BAABLgAECn8VAAMUAAkJ8RZ6FADJAQAUAAkJ8RZ6FADJAQAOAAEJCQQKJQEvAAAAAA==.Kovya:BAAALgADCgYJBwAAAA==.',
Kr='Krelel:BAAALgADCgIJAgAAAA==.Krukar:BAAALgADCgYJDAAAAA==.',
Ku='Kubo:BAAALgAECgYJBgABLgAFFAQJEAAQABASAA==.',
Ky='Kydroga:BAAALgAECgYJEAAAAA==.Kynaria:BAAALgAECgEJAQAAAA==.Kynsia:BAAALgADCgQJBgAAAA==.',
La='Lamörak:BAABLgAECn8yAAICAAkJsSGQDAD5AgACAAkJsSGQDAD5AgAAAA==.Landrick:BAABLgAECn85AAIOAAkJlRtkIwBwAgAOAAkJlRtkIwBwAgAAAA==.Lastotem:BAAALgADCgEJAQAAAA==.Lastshot:BAAALgAECggJEQAAAA==.Latest:BAAALgADCgQJBAAAAA==.Lavaevoker:BAAALgADCgcJBwABLgAECggJJwASAO8LAA==.Lavanor:BAAALgADCgIJAgAAAA==.Lavasaurus:BAABLgAECn8iAAQaAAgJkhqaEgCXAQAaAAYJUxqaEgCXAQAZAAgJSA+VLQB7AQAbAAEJDRNgIgA6AAAAAA==.',
Le='Leafstorm:BAAALgAECgYJDwAAAA==.Lehala:BAAALgADCgQJBAAAAA==.Lektar:BAAALgAECgUJBQABLgAECgYJEwABAAAAAA==.Leloosh:BAAALgADCgkJDAABLgAFFAIJBAABAAAAAA==.Lemon:BAABLgAECn8iAAIYAAgJbgrbEgAQAQAYAAgJbgrbEgAQAQAAAA==.Leokenoso:BAABLgAECn8hAAIkAAkJCxLKCQC7AQAkAAkJCxLKCQC7AQAAAA==.Lesclaypool:BAAALgAECgcJCQAAAA==.Lessalia:BAAALgAECgEJAQAAAA==.Lewd:BAAALgAECgQJBgAAAA==.Lexor:BAAALgADCgQJBAAAAA==.',
Li='Lifebloomz:BAABLgAECn8uAAIgAAkJpwyBPgCPAQAgAAkJpwyBPgCPAQAAAA==.Lifesabeach:BAAALgAECgMJAwAAAA==.Lilfluffcc:BAAALgAECgQJBAAAAA==.Lissana:BAAALgADCgUJBQAAAA==.',
Lo='Lockward:BAAALgAECgUJBwAAAA==.Loidvoid:BAAALgAECgEJAQAAAA==.Lorblor:BAABLgAECn8kAAIkAAkJ7h86AgDYAgAkAAkJ7h86AgDYAgAAAA==.Lorerun:BAAALgADCgUJCAAAAA==.Lowang:BAABLgAECn8dAAISAAkJnRNFJgB0AQASAAkJnRNFJgB0AQAAAA==.Lowmein:BAABLgAECn8UAAIGAAgJMR4lKgDlAQAGAAgJMR4lKgDlAQAAAA==.',
Lu='Lucÿfer:BAAALgAFFAIJAwAAAA==.Lumie:BAAALgAECgYJEQAAAA==.Luminisx:BAAALgADCgMJAwAAAA==.Lunafox:BAABLgAECn8lAAIGAAgJOh5wFACbAgAGAAgJOh5wFACbAgAAAA==.Lunamae:BAABLgAECn8nAAIiAAgJMBgtAwDvAQAiAAgJMBgtAwDvAQAAAA==.Lupacho:BAAALgAFFAIJAwAAAA==.Luvvyyaa:BAABLgAECn9RAAMHAAkJwiCxCADAAgAHAAkJ+h2xCADAAgAfAAkJShisDQCHAgAAAA==.Luvyya:BAAALgAECgYJEAABLgAECgkJUQAHAMIgAA==.Luvyyaa:BAAALgAECgQJBQABLgAECgkJUQAHAMIgAA==.',
Ly='Lyrinaku:BAABLgAECn8UAAIHAAcJWRVQNgBkAQAHAAcJWRVQNgBkAQAAAA==.Lythomancer:BAABLgAECn8fAAIYAAgJiQ/vDwA1AQAYAAgJiQ/vDwA1AQAAAA==.',
Ma='Maddeena:BAABLgAECn8eAAIGAAgJkgZxZAAeAQAGAAgJkgZxZAAeAQAAAA==.Maddy:BAABLgAECn8iAAMWAAkJWBriEwASAgAWAAgJYh3iEwASAgASAAkJexA7GQDUAQAAAA==.Maelyssa:BAAALgADCgMJAwAAAA==.Magicmangge:BAAALgADCgYJBgABLgAFFAEJAQABAAAAAA==.Makeitclap:BAAALgAECgMJBAABLgAECgcJHQARAPEQAA==.Malidian:BAABLgAECn8dAAILAAkJdw8/UgCDAQALAAkJdw8/UgCDAQAAAA==.Matchadaddy:BAAALgAECgEJAwAAAA==.Maxohlx:BAACLgAFFH8VAAINAAYJ7A0bNABfAQANAAYJ7A0bNABfAQAuAAQKf0EAAg0ACQkoIWgIAA0DAA0ACQkoIWgIAA0DAAAA.',
Mc='Mcmercie:BAAALgAECgkJCgAAAA==.',
Me='Mechacooter:BAAALgAFFAMJAwAAAA==.Meeko:BAAALgADCgUJBQABLgAFFAgJGwAaAPggAA==.Megahertz:BAAALgADCgEJAQAAAA==.Megg:BAAALgADCggJEQAAAA==.Meilia:BAAALgADCgUJBwAAAA==.Mekagatha:BAAALgADCgkJCQAAAA==.Mekari:BAABLgAECn8wAAIQAAkJxR1QCQCFAgAQAAkJxR1QCQCFAgAAAA==.Melchiorr:BAACLgAFFH8FAAIXAAMJqxU/BwD7AAAXAAMJqxU/BwD7AAAuAAQKfykAAhcACQkRHKMEAD4CABcACQkRHKMEAD4CAAAA.Melignant:BAAALgADCgEJAQAAAA==.Melosia:BAAALgADCgQJBwAAAA==.Melynne:BAABLgAECn9FAAMGAAkJBxVNIwAtAgAGAAkJBxVNIwAtAgAFAAIJeATEgQBBAAAAAA==.Memmel:BAAALgADCgMJAwAAAA==.Meredeath:BAABLgAECn8UAAIJAAgJKg0rQgD2AAAJAAgJKg0rQgD2AAAAAA==.',
Mi='Micro:BAAALgAECgkJEwAAAA==.Microkeg:BAAALgAECgcJBAAAAA==.Microslash:BAAALgADCgMJAwABLgAECgkJEwABAAAAAA==.Minsoo:BAACLgAFFH8FAAIVAAMJiRUxMQDHAAAVAAMJiRUxMQDHAAAuAAQKfxwAAhUACQkFHkYMAMUCABUACQkFHkYMAMUCAAAA.Mistblade:BAAALgAECgQJCwABLgAECgkJGQALAAkSAA==.Miststriker:BAAALgAECgUJCQAAAA==.Mistytaco:BAAALgAECgEJAQAAAA==.',
Ml='Mlrglett:BAABLgAECn8/AAMcAAkJCyEMAwDxAgAcAAkJCyEMAwDxAgAJAAEJihMfhgAqAAAAAA==.Mlrglo:BAAALgADCgcJCQAAAA==.',
Mo='Moisturizeme:BAAALgAECgUJBQAAAA==.Mojomaker:BAABLgAECn8VAAIGAAYJAhL9WABDAQAGAAYJAhL9WABDAQAAAA==.Moojitsu:BAAALgADCgMJAwAAAA==.Mormegil:BAABLgAECn8nAAMUAAgJcyEcCACNAgAUAAgJcyEcCACNAgAnAAEJeA29NQAzAAAAAA==.Moshimoshi:BAACLgAFFH8VAAMGAAUJEBPsIwBBAQAGAAUJEBPsIwBBAQAFAAEJIQOzVAAzAAAuAAQKfx0AAwUACAlHHGcbADcCAAUACAlHHGcbADcCAAYABwkUCnRRAD8BAAAA.Motosake:BAAALgAECgQJBQAAAA==.',
Mu='Muffinlord:BAAALgAECgYJEQAAAA==.Munkeebutt:BAABLgAECn8gAAQQAAkJMQmzHACyAQAQAAkJDQmzHACyAQAEAAcJYAcoUwD/AAADAAEJsQst1QAwAAAAAA==.Munkeefase:BAAALgADCgEJAQAAAA==.',
My='Myronis:BAAALgADCgIJAgAAAA==.Mythaera:BAAALgADCgYJBgAAAA==.',
Na='Naberius:BAAALgAECgcJEgAAAA==.Naillil:BAAALgAECgEJAQAAAA==.Namiiswan:BAAALgADCgMJBQAAAA==.Nasmine:BAAALgADCgEJAQAAAA==.Natsuki:BAAALgADCgUJBwAAAA==.',
Ne='Nefarius:BAAALgAFFAEJAQAAAA==.Neflite:BAABLgAECn8eAAIYAAcJvweqGQDMAAAYAAcJvweqGQDMAAAAAA==.Nelfie:BAAALgAECgEJAQAAAA==.Nessará:BAABLgAECn8WAAIHAAYJQCF1FAAmAgAHAAYJQCF1FAAmAgAAAA==.',
Ni='Nineõseven:BAABLgAECn8YAAITAAcJixN9IADVAQATAAcJixN9IADVAQABLgAECgEJAQABAAAAAA==.Ninjapro:BAAALgAECgkJAgAAAA==.Nixia:BAAALgAECgQJBAAAAA==.',
No='Nodiddy:BAAALgAECgQJBQABLgAECgcJJAARAPYhAA==.',
Nu='Nuraga:BAABLgAECn8hAAMlAAgJlyHXBwCpAgAlAAcJCSTXBwCpAgAPAAEJ7hLLjgBEAAAAAA==.',
Ob='Obeeone:BAAALgAECgEJAgAAAA==.',
On='Onasta:BAABLgAECn8hAAIOAAkJkx+uNQAgAgAOAAkJkx+uNQAgAgAAAA==.Onelastkiss:BAAALgAECgEJAQAAAA==.',
Op='Oprahheals:BAABLgAECn8cAAICAAkJFB46FgC0AgACAAkJFB46FgC0AgAAAA==.',
Or='Oreoagane:BAAALgAECgYJBwAAAA==.Oreobeer:BAAALgAECgEJAQAAAA==.Oreomonster:BAAALgAECgcJEQAAAA==.Orquesta:BAAALgAECgQJCgAAAA==.',
Pa='Paccer:BAAALgAECgEJAQAAAA==.Pacerx:BAAALgAECgIJAgAAAA==.Pandaemonia:BAACLgAFFH8XAAIkAAUJpg/kBgDYAAAkAAUJpg/kBgDYAAAuAAQKfyQAAiQACQncDTwVAPMAACQACQncDTwVAPMAAAAA.Pandakyle:BAABLgAECn8XAAIVAAYJ5xcgRABBAQAVAAYJ5xcgRABBAQAAAA==.Pandexander:BAAALgADCgMJAwAAAA==.Panterå:BAAALgAECgEJAQAAAA==.Parts:BAABLgAECn8iAAIRAAgJtiGIIQDtAgARAAgJtiGIIQDtAgABLgAFFAUJGAAnALgdAA==.Patchmen:BAAALgAECgQJBAAAAA==.Pattilicious:BAABLgAECn8kAAICAAkJZwtlcgB+AQACAAkJZwtlcgB+AQAAAA==.',
Pe='Pepsizero:BAAALgAECgUJCwAAAA==.',
Ph='Phlesh:BAAALgAECgEJAgAAAA==.Phlvrabies:BAAALgADCgMJBQAAAA==.Phonedin:BAABLgAECn8jAAMbAAkJERmdBgCIAgAbAAkJERmdBgCIAgAZAAMJBhchSQCyAAAAAA==.Phoënix:BAACLgAFFH8XAAMGAAUJDhf3IABRAQAGAAUJDhf3IABRAQAFAAIJwQNlRwBdAAAuAAQKfyMAAwYACQmWHWQRALgCAAYACQmWHWQRALgCAAUAAwnmGHZfALYAAAAA.',
Pi='Pieglaive:BAABLgAECn8jAAMMAAkJzSHJBwCmAgAMAAkJzSHJBwCmAgALAAIJuhZpwwB2AAAAAA==.Pierres:BAAALgAECgkJEgAAAA==.Piondelth:BAAALgAECgcJEQAAAA==.',
Pl='Plantman:BAAALgAECgYJDgAAAA==.',
Po='Pointyboner:BAAALgADCgYJCAAAAA==.Poofort:BAAALgAECgYJDwAAAA==.Pooner:BAAALgADCgMJAwAAAA==.Porkins:BAAALgAECgMJAwAAAA==.Postoak:BAAALgAECgUJCgAAAA==.Powerochrist:BAABLgAECn8xAAIeAAkJ+BlbDwCXAgAeAAkJ+BlbDwCXAgAAAA==.',
Pr='Priscila:BAAALgADCgYJBgAAAA==.Proxzy:BAABLgAECn8ZAAIFAAgJ/yDjCwCZAgAFAAgJ/yDjCwCZAgAAAA==.',
Pu='Pubessalad:BAABLgAECn8oAAICAAYJCRuZbACKAQACAAYJCRuZbACKAQAAAA==.Puddin:BAAALgADCgQJBwAAAA==.Puffytaco:BAAALgAECgYJCwABLgAECgkJJAACACMdAA==.',
Py='Pyrug:BAAALgAECgUJBwABLgAECgkJOAANAGwWAA==.',
Qu='Qualek:BAABLgAECn8XAAIlAAkJMRJfEAADAgAlAAkJMRJfEAADAgAAAA==.Quilue:BAABLgAECn8hAAIRAAkJ0xP6PAAgAgARAAkJ0xP6PAAgAgAAAA==.',
Ra='Rannmagnison:BAABLgAECn8wAAICAAkJMwg5ggBfAQACAAkJMwg5ggBfAQAAAA==.Raquoon:BAABLgAECn8WAAIlAAYJ1w4QKwDSAAAlAAYJ1w4QKwDSAAAAAA==.Rasonia:BAAALgAECgYJBgABLgAFFAQJCQAfAMoLAA==.Ratfu:BAAALgADCgcJDQAAAA==.Raumulus:BAAALgAECgEJAQAAAA==.Razjin:BAABLgAECn8aAAMGAAkJeiPsCQDaAgAGAAkJeiPsCQDaAgAFAAEJ/woIpwAnAAAAAA==.',
Re='Reapér:BAAALgAECgkJBQAAAA==.Rene:BAAALgADCgYJBgAAAA==.Reze:BAACLgAFFH8UAAIWAAQJayCYCgBnAQAWAAQJayCYCgBnAQAuAAQKfxYAAhYACAlYHnoQADkCABYACAlYHnoQADkCAAEuAAUUCQk8AAwAySIA.',
Rh='Rhaeynera:BAABLgAECn8pAAIbAAgJEgYpDwAMAQAbAAgJEgYpDwAMAQAAAA==.Rhyel:BAAALgADCgIJAgAAAA==.Rhyno:BAAALgADCgkJEgABLgAECgkJNwANAEIgAA==.Rhysedwyn:BAAALgADCgkJEgABLgAECgEJAQABAAAAAA==.',
Ri='Riezen:BAAALgAECggJEwAAAA==.Ringol:BAAALgAECgQJCgABLgAECgYJDgABAAAAAA==.Rinorik:BAABLgAECn83AAMNAAkJQiBlEADDAgANAAkJQiBlEADDAgAYAAYJCRn2FACjAQAAAA==.Rizzdor:BAAALgADCgcJCAABLgAECgkJEgABAAAAAA==.',
Ro='Rockbiter:BAAALgAECgEJAgAAAA==.Rockhhard:BAABLgAECn8eAAIGAAkJxx5nHQBVAgAGAAkJxx5nHQBVAgAAAA==.Roeken:BAABLgAECn86AAIPAAkJKRUOHgD3AQAPAAkJKRUOHgD3AQAAAA==.Rollingman:BAABLgAECn8VAAIVAAgJYhUpJQDkAQAVAAgJYhUpJQDkAQAAAA==.Roummi:BAAALgAECgEJAQAAAA==.',
Ru='Rudybear:BAAALgAECgEJAQABLgAFFAEJAgABAAAAAA==.Rudyrots:BAAALgAECgEJAQABLgAFFAEJAgABAAAAAA==.Rudyshoots:BAAALgAFFAEJAgAAAA==.Rum:BAAALgAECgMJAwAAAA==.',
Ry='Rybear:BAAALgADCgkJCQAAAA==.Rygaard:BAABLgAECn84AAIlAAkJHyKHBADRAgAlAAkJHyKHBADRAgAAAA==.Rystic:BAAALgADCgkJEgAAAA==.Ryutiz:BAABLgAECn8sAAIEAAkJbSKsAQDwAgAEAAkJbSKsAQDwAgAAAA==.Ryward:BAAALgADCgcJBwAAAA==.Ryyuk:BAAALgAECgMJBAABLgAECgkJGQALAAkSAA==.',
Sa='Sacridas:BAAALgAECgEJAQABLgAECgkJLAAEAG0iAA==.Sako:BAAALgADCgUJCgAAAA==.Salandar:BAAALgAECgIJAgABLgAECgkJMAACADMIAA==.Samsó:BAABLgAECn8XAAMCAAkJmBfEaQCrAQACAAkJmBfEaQCrAQAeAAQJ3BQNagDSAAAAAA==.Sapharina:BAACLgAFFH8JAAIfAAQJygvnJQD/AAAfAAQJygvnJQD/AAAuAAQKfzMAAh8ACQmWF70PAGgCAB8ACQmWF70PAGgCAAAA.Sassgrip:BAAALgADCgEJAQABLgAECgYJDAABAAAAAA==.Sassier:BAAALgAECgYJDAAAAA==.Sathenaz:BAAALgADCgcJCQAAAA==.',
Sc='Scarcy:BAACLgAFFH8VAAIIAAYJKRkADQCgAQAIAAYJKRkADQCgAQAuAAQKfzMAAwgACQliGrAQAJ0CAAgACQliGrAQAJ0CACYAAwmXCGocAFsAAAAA.',
Se='Seacotton:BAABLgAECn8fAAMoAAkJvxsGBwB/AgAoAAkJFRsGBwB/AgAPAAcJoBVaQACjAQAAAA==.Searfang:BAACLgAFFH8UAAIFAAUJVBYNHgAcAQAFAAUJVBYNHgAcAQAuAAQKfzgAAwUACQmEIasGAOcCAAUACQmEIasGAOcCAAYAAQljE0nHADYAAAAA.Seariel:BAAALgAECgUJBwAAAA==.Seatea:BAAALgADCgkJCQABLgAECgkJOAAZACAhAA==.Selestra:BAAALgAFFAIJAgAAAA==.Selinise:BAAALgAECgUJBQAAAA==.Sematic:BAAALgAFFAEJAQABLgAFFAYJFQARABkcAA==.Senpai:BAAALgAECgQJBAAAAA==.Seraphymm:BAAALgADCgEJAQAAAA==.',
Sh='Shadowjacker:BAACLgAFFH8SAAILAAUJ9BsONAA9AQALAAUJ9BsONAA9AQAuAAQKfzgAAgsACQkmIYIHAFEDAAsACQkmIYIHAFEDAAAA.Shadowmidget:BAABLgAECn8WAAINAAkJ3BahVwDBAQANAAkJ3BahVwDBAQAAAA==.Shadrielis:BAABLgAECn89AAMfAAkJaB7gCADcAgAfAAkJaB7gCADcAgAHAAIJVQ3VbgBsAAAAAA==.Shanlao:BAAALgAFFAIJAgABLgAFFAYJIAANAL0SAA==.Shirkka:BAAALgADCgMJBAAAAA==.Shurihito:BAABLgAECn8lAAICAAkJiR5QHwCBAgACAAkJiR5QHwCBAgAAAA==.',
Si='Sieron:BAABLgAECn8UAAIOAAYJ/RzAjABDAQAOAAYJ/RzAjABDAQAAAA==.Silaslunark:BAAALgAECgkJCwAAAA==.Sinkrow:BAAALgAECgYJBgAAAA==.Sixpack:BAABLgAECn8aAAIgAAkJbQ5rOwCdAQAgAAkJbQ5rOwCdAQAAAA==.',
Sk='Skarigar:BAAALgAECgEJAwAAAA==.Skeeterson:BAAALgADCgUJCAAAAA==.Skiððles:BAAALgAECgYJBgABLgAFFAEJAQABAAAAAA==.Skurplock:BAAALgADCgEJAQAAAA==.Skytec:BAAALgADCgMJAwAAAA==.Skëëts:BAABLgAECn8cAAQfAAgJSBBvJgCQAQAfAAgJJBBvJgCQAQATAAEJuwTzigAnAAAHAAEJ5gZ+bgAnAAAAAA==.Skùrvypete:BAAALgAFFAEJAQAAAA==.',
Sl='Slampoof:BAAALgAECgQJDQAAAA==.Slamslayer:BAAALgAECgEJAQAAAA==.Sleez:BAAALgAECgYJDAAAAA==.Sloodraga:BAAALgADCgYJBgAAAA==.',
Sm='Smallgregory:BAAALgAECgYJDAAAAA==.',
Sn='Sneakdead:BAAALgAECgcJCgAAAA==.Sneakerzz:BAAALgADCgQJBAAAAA==.Sneakfury:BAAALgAECgYJCgABLgAECgcJCgABAAAAAA==.Sneeler:BAAALgAECgEJAQAAAA==.Snowscayia:BAACLgAFFH8LAAQgAAYJARhZKAATAQAgAAQJwBBZKAATAQAJAAQJSQhwJwDhAAAdAAIJIQr3FAB0AAAuAAQKfy4ABAkACQkbGDMnAMUBAAkACAk2GjMnAMUBACAABwleGD87ALgBAB0AAQlhCUVJADcAAAAA.',
So='Solanar:BAABLgAECn88AAMeAAkJZiHjDwCQAgAeAAgJsiPjDwCQAgACAAcJESFJLgA9AgAAAA==.Solesin:BAAALgAFFAEJAQABLgAFFAUJEwAaADIXAA==.Solm:BAAALgADCgkJGwAAAA==.Solmina:BAABLgAECn83AAIRAAkJIh5jHQClAgARAAkJIh5jHQClAgAAAA==.Somniatis:BAAALgAECgEJAQAAAA==.Soulciopath:BAAALgAECgUJCAAAAA==.Souljin:BAAALgADCgMJAwAAAA==.',
Sp='Spartan:BAAALgAECgQJBAAAAA==.Spicypants:BAAALgADCgMJAwAAAA==.Spicytaco:BAAALgAECgUJCgABLgAECgkJJAACACMdAA==.Spookuleli:BAAALgADCggJCwAAAA==.Sprinklewiz:BAAALgADCgMJAwAAAA==.',
Sq='Squadie:BAABLgAECn83AAIDAAgJzgsBYgB1AQADAAgJzgsBYgB1AQAAAA==.Squanchs:BAACLgAFFH8VAAIGAAYJ5xlvEADDAQAGAAYJ5xlvEADDAQAuAAQKfx4AAwYACQlkHygMAL8CAAYACQlkHygMAL8CAAUAAQkGAKe6AAEAAAEuAAQKBwkcACAAkxsA.Squanchy:BAABLgAECn8cAAIgAAcJkxtxPACyAQAgAAcJkxtxPACyAQAAAA==.Squisquee:BAAALgADCgcJBwAAAA==.',
Sr='Srbojangles:BAAALgAECgcJCAABLgAECgcJJAARAPYhAA==.Srry:BAABLgAECn8VAAIPAAcJsBrUKQATAgAPAAcJsBrUKQATAgAAAA==.',
St='Stinkvile:BAAALgAECgEJAQAAAA==.Stonebraid:BAAALgADCgEJAQAAAA==.Sturdy:BAAALgADCgEJAQAAAA==.',
Su='Suiféng:BAAALgAFFAEJAQAAAA==.Sukuna:BAAALgAECgYJCAAAAA==.Sundance:BAAALgAECggJEAAAAA==.Surmise:BAACLgAFFH8VAAMRAAYJGRwlFAB6AQARAAYJkxslFAB6AQAiAAEJBSMVBABlAAAuAAQKfzIAAxEACQkBJc8EAF0DABEACQkBJc8EAF0DACIABAlVIHkIAAUBAAAA.Sust:BAAALgAFFAIJBAABLgAFFAYJFQARABkcAA==.Sustenance:BAAALgAFFAIJAwABLgAFFAYJFQARABkcAA==.',
Sw='Swayzeetrain:BAACLgAFFH8WAAMeAAUJzCRZCAAaAgAeAAUJzCRZCAAaAgACAAEJpAxQMABUAAAuAAQKfxsAAwIACQkCHCxmALQBAAIABwkgGixmALQBAB4ACAn1IOA2AKABAAAA.',
Sy='Sydris:BAAALgAECgkJBQAAAA==.Syrrel:BAAALgADCgQJBAAAAA==.',
['Sü']='Süß:BAAALgAFFAIJAgABLgAFFAQJBwALALULAA==.',
Ta='Tabius:BAABLgAECn8mAAMdAAkJXR5LCQAiAgAdAAkJXR5LCQAiAgAJAAMJyw7iXQCPAAAAAA==.Talkingtaco:BAABLgAECn8kAAICAAkJIx14HACQAgACAAkJIx14HACQAgAAAA==.Taln:BAAALgAECgEJAgABLgAECggJJwAUAHMhAA==.Talìa:BAAALgADCgIJAgABLgAECgEJAQABAAAAAA==.Tareul:BAAALgADCgIJAgAAAA==.Tarn:BAAALgAECgkJEgAAAA==.',
Te='Temok:BAABLgAECn8dAAICAAgJuwoGlAA/AQACAAgJuwoGlAA/AQAAAA==.',
Th='Thiccbush:BAAALgAECgEJAQAAAA==.Thirielnet:BAAALgAECggJDwAAAA==.This:BAAALgAECgEJAQAAAA==.Thorisdead:BAAALgAECgEJAQABLgAECggJJwASAO8LAA==.Thorkell:BAAALgADCgUJBQAAAA==.Thosen:BAAALgAECgYJCgAAAA==.',
Ti='Tinkaballah:BAAALgAECgcJDgAAAA==.Tipy:BAAALgADCgUJBQAAAA==.',
To='Tore:BAACLgAFFH8VAAIDAAUJSBpFLwBEAQADAAUJSBpFLwBEAQAuAAQKfzMAAgMACQmUIqcJAPwCAAMACQmUIqcJAPwCAAAA.Totemangge:BAAALgAFFAEJAQAAAA==.Totesmagoat:BAAALgADCgYJBgAAAA==.',
Tr='Trifectas:BAAALgADCgcJGQAAAA==.Trinadel:BAACLgAFFH8SAAIJAAUJBhKLHwAOAQAJAAUJBhKLHwAOAQAuAAQKfx0AAgkACAmnHS8PAK0CAAkACAmnHS8PAK0CAAAA.Träitors:BAAALgADCgcJEwAAAA==.Tråitors:BAABLgAECn82AAMNAAYJciKOOgDrAQANAAYJciKOOgDrAQAYAAEJAAA0ZQBFAAABLgADCgcJEwABAAAAAA==.',
Ts='Tsarevich:BAABLgAECn8WAAIiAAYJhAgcCgDVAAAiAAYJhAgcCgDVAAAAAA==.',
Tu='Tugtheshaman:BAABLgAECn8dAAIGAAgJoxgmGgBGAgAGAAgJoxgmGgBGAgAAAA==.Tunechii:BAAALgAECgMJBAABLgAECgkJGQALAAkSAA==.',
Tw='Twileaf:BAABLgAECn8xAAIgAAgJDAlVXQAVAQAgAAgJDAlVXQAVAQAAAA==.Twoinchisbig:BAABLgAECn9OAAIlAAkJLRtfCQBVAgAlAAkJLRtfCQBVAgAAAA==.',
Ty='Typhoidmary:BAABLgAECn8XAAMNAAgJhAmIggBVAQANAAcJhAmIggBVAQAYAAEJAAAOdgAuAAABLgAFFAMJAwABAAAAAA==.',
['Té']='Térror:BAAALgAECgcJDwAAAA==.',
Un='Unbenched:BAAALgADCgQJBQABLgAECgkJNgAFAGEfAA==.Uncool:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Unholyz:BAAALgAECgUJCAAAAA==.',
Ur='Ursoc:BAABLgAECn84AAMJAAkJ9hLCHADVAQAJAAkJ9hLCHADVAQAgAAYJRxF1VwApAQAAAA==.Urteg:BAAALgADCgkJFAAAAA==.',
Ut='Uthmansur:BAAALgAECgEJAgAAAA==.',
Uu='Uub:BAAALgAECgIJAgAAAA==.',
Va='Vairekor:BAAALgADCggJDgABLgAFFAYJIAANAL0SAA==.Valdria:BAAALgADCgUJBQAAAA==.Vanillaçake:BAAALgAFFAEJAQAAAA==.Vanishja:BAAALgAECgYJDwAAAA==.Varkbyte:BAABLgAECn8WAAIHAAYJHBZiJwB9AQAHAAYJHBZiJwB9AQAAAA==.Varrik:BAACLgAFFH8SAAMPAAUJfCAoFQBSAQAPAAUJfCAoFQBSAQAoAAMJ7hjmIgDOAAAuAAQKfycAAw8ACQnYIYoJABUDAA8ACQnYIYoJABUDACgABgmcG8cdAGMBAAAA.',
Ve='Vec:BAAALgAECgYJDQAAAA==.Velamor:BAABLgAECn8YAAQkAAYJzguMGwCxAAAkAAYJ5gqMGwCxAAAMAAMJygk5VQCTAAALAAMJagrkzgCCAAAAAA==.Velaria:BAAALgADCgcJBwAAAA==.',
Vi='Violynt:BAAALgADCgEJAQAAAA==.',
Vo='Volieu:BAABLgAECn8hAAIiAAkJpxNDAwDqAQAiAAkJpxNDAwDqAQAAAA==.Volklin:BAABLgAECn8gAAMGAAgJywiWWgA+AQAGAAgJywiWWgA+AQAFAAYJIglMWQDIAAAAAA==.Voyageurs:BAABLgAECn8cAAIdAAkJpBybBQCJAgAdAAkJpBybBQCJAgAAAA==.',
Vy='Vyrka:BAAALgAECgMJDQAAAA==.',
Wa='Wallstreet:BAAALgAECgUJBQAAAA==.Waterdweller:BAAALgAECgEJBAAAAA==.',
We='Wegl:BAAALgAECgUJEwAAAA==.Werebear:BAAALgADCgMJAwABLgAECgQJBQABAAAAAA==.Werewithal:BAAALgADCgYJCwABLgAECgkJJwAQAC0SAA==.Wesleypipes:BAAALgAECgEJAQAAAA==.Wetfloorsign:BAAALgAECgYJEQAAAA==.',
Wh='Wholeymilk:BAAALgAECgQJAwAAAA==.',
Wi='Wiindsslashh:BAAALgAECgYJBwAAAA==.Wilbur:BAAALgADCgQJBQAAAA==.Windslash:BAAALgAECgIJAgAAAA==.Wish:BAAALgAECgUJBQAAAA==.',
Wo='Wonderx:BAAALgADCgIJAgAAAA==.Wonyoung:BAACLgAFFH8RAAIHAAQJMyRjCgCKAQAHAAQJMyRjCgCKAQAuAAQKfzIAAgcACQnzI9kBAFgDAAcACQnzI9kBAFgDAAAA.',
Wr='Wraithwok:BAAALgAECgUJBQAAAA==.',
Wu='Wuthrad:BAAALgAECgEJAQAAAA==.',
['Wü']='Würzig:BAABLgAFFH8HAAMOAAUJDAlecwANAQAOAAUJDAlecwANAQAUAAIJ4AMKMgBcAAABLgAFFAQJBwALALULAA==.',
Xa='Xala:BAABLgAECn8VAAMUAAkJbw3GHwBKAQAUAAkJ+QzGHwBKAQAnAAIJ+AeFKwBhAAAAAA==.Xalah:BAAALgAECggJEgAAAA==.Xalaz:BAACLgAFFH8WAAMNAAYJZQ7oMwBgAQANAAYJZQ7oMwBgAQAYAAEJVwJgGgBGAAAuAAQKfx0AAw0ACQlXHHQ2ADICAA0ACAlXHHQ2ADICABgAAgkLFGNSAHcAAAAA.Xanaris:BAAALgADCgEJAQABLgAFFAIJCgAOAL0mAA==.Xandumbra:BAAALgADCgEJAQAAAA==.Xarosea:BAACLgAFFH8MAAICAAQJPxP1RgARAQACAAQJPxP1RgARAQAuAAQKfyoAAgIABwk6JPYYANMCAAIABwk6JPYYANMCAAAA.',
Xe='Xelojr:BAAALgADCgkJHAAAAA==.',
Xh='Xhael:BAAALgADCgEJAQAAAA==.',
Xi='Xia:BAABLgAECn9CAAIHAAkJqRkzFQA0AgAHAAkJqRkzFQA0AgAAAA==.',
Xo='Xoilkick:BAAALgAECgYJEAAAAA==.Xoilwings:BAAALgAECgIJAgAAAA==.Xooiill:BAAALgAECggJEQAAAA==.',
Xp='Xpacer:BAAALgAECgcJEwAAAA==.',
['Xê']='Xêna:BAAALgAECgQJCgAAAA==.',
Ye='Yekira:BAAALgADCgEJAgAAAA==.Yellowsnøw:BAACLgAFFH8GAAIRAAMJaQQLiAC7AAARAAMJaQQLiAC7AAAuAAQKfzwAAhEACQnwFykqAGsCABEACQnwFykqAGsCAAAA.',
Yu='Yumeshade:BAAALgAECgYJCgAAAA==.',
Za='Zaila:BAAALgAECgUJBQAAAA==.Zal:BAAALgAECgYJBgABLgAFFAUJCQAlAJsTAA==.Zamari:BAAALgAECggJEQAAAA==.Zanzabar:BAABLgAECn8WAAIdAAkJegvGEACgAQAdAAkJegvGEACgAQAAAA==.Zathmage:BAAALgADCgMJAwAAAA==.Zaxin:BAABLgAECn8XAAMHAAkJDQ4EJQCOAQAHAAkJDQ4EJQCOAQATAAUJiAQeSwCtAAAAAA==.',
Ze='Zelfie:BAAALgADCgUJBQAAAA==.Zellda:BAAALgAECgYJCQAAAA==.Zerodarkness:BAAALgADCgkJCQAAAA==.Zeros:BAABLgAECn8XAAIRAAkJeBhiOAAwAgARAAkJeBhiOAAwAgAAAA==.',
Zi='Ziperz:BAAALgAECggJCAAAAA==.',
Zo='Zoerina:BAAALgAECgcJDwAAAA==.Zoobilong:BAABLgAECn8VAAICAAUJoRIfuwAQAQACAAUJoRIfuwAQAQAAAA==.',
Zx='Zxak:BAABLgAECn80AAIMAAgJjia0BADxAgAMAAgJjia0BADxAgAAAA==.',
Zy='Zyahk:BAAALgADCgQJBQAAAA==.Zynn:BAAALgAECgEJAgAAAA==.',
['Zë']='Zën:BAAALgAECgEJAQABLgAFFAUJDQAfAO8LAA==.',
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
