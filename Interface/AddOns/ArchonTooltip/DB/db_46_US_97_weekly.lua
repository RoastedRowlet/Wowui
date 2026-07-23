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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Elemental','Shaman-Restoration','Priest-Holy','Rogue-Subtlety','Druid-Balance','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Assassination','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Warrior-Fury','Hunter-Survival','Monk-Brewmaster','Mage-Frost','Priest-Shadow','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','Warlock-Affliction','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Druid-Feral','Paladin-Holy','Priest-Discipline','Druid-Restoration','Paladin-Protection','Mage-Arcane','Shaman-Enhancement','DemonHunter-Vengeance','Warrior-Protection','Rogue-Outlaw','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abandonhope:BAAALgAECgMJAwABLgAECgkJEwABAAAAAA==.',
Ac='Accuser:BAAALgADCgEJAQAAAA==.Acky:BAAALgADCgUJBQAAAA==.Acrasia:BAAALgAECgUJBQAAAA==.',
Ad='Adwen:BAABLgAECn8kAAICAAkJZxpCYwCqAQACAAkJZxpCYwCqAQAAAA==.',
Ae='Aenimal:BAAALgAECgYJEAAAAA==.Aer:BAAALgADCgkJCQAAAA==.Aeronemon:BAAALgAECgEJAgAAAA==.',
Ag='Agamemmnon:BAAALgAECgEJAQAAAA==.',
Ah='Ahavati:BAAALgADCgMJAwAAAA==.',
Ai='Airill:BAAALgADCgQJBQAAAA==.',
Ak='Akforty:BAABLgAECn8fAAMDAAkJIiHNCgDvAgADAAkJIiHNCgDvAgAEAAIJoBV7eABfAAAAAA==.Akittymeow:BAABLgAECn8bAAMFAAkJuw/YRgAYAQAFAAgJKQ/YRgAYAQAGAAMJiwWcqQB2AAAAAA==.',
Al='Alconaus:BAAALgAECgEJAQAAAA==.Aldredevon:BAAALgAECgEJAQAAAA==.Aleshock:BAAALgAECgkJEQAAAA==.Alidar:BAAALgAECgcJEwAAAA==.Alphaboner:BAAALgADCgYJBwAAAA==.Altairis:BAAALgAECgEJAgAAAA==.Altartoy:BAABLgAECn8hAAIHAAgJ6Qq+NwAeAQAHAAgJ6Qq+NwAeAQAAAA==.Althunter:BAACLgAFFH8NAAIEAAQJUiFjEQBOAQAEAAQJUiFjEQBOAQAuAAQKfxsAAgQACAneIcwGACICAAQACAneIcwGACICAAAA.',
Am='Amanita:BAAALgAECgQJBAABLgAECgkJEQABAAAAAA==.Amelina:BAAALgAECgYJDgAAAA==.Amerit:BAAALgAECgEJAQAAAA==.Amorage:BAAALgAECgMJAwAAAA==.Amorir:BAACLgAFFH8RAAICAAQJlQPmaADdAAACAAQJlQPmaADdAAAuAAQKf1sAAgIACQnwFZcNAFMBAAIACQnwFZcNAFMBAAAA.Amorit:BAABLgAECn8WAAIDAAcJYRDrdQBUAQADAAcJYRDrdQBUAQAAAA==.Amorydalias:BAAALgAECgUJBgAAAA==.Amozon:BAAALgADCgEJAQAAAA==.',
An='Anamortem:BAAALgAECgMJAwABLgAECgkJIQAIAAcZAA==.Anastala:BAABLgAECn8rAAIJAAkJ5RXwGQD8AQAJAAkJ5RXwGQD8AQAAAA==.Andeddo:BAACLgAFFH8KAAIKAAQJsAv0LgAHAQAKAAQJsAv0LgAHAQAuAAQKfxcAAwoACQkxFiNfAKsBAAoABglFFyNfAKsBAAsABglaEVYqAAUBAAAA.Angchu:BAAALgADCgQJBAAAAA==.Angelmàker:BAAALgAECgMJBAABLgADCgcJEwABAAAAAA==.Angelmäker:BAAALgAECgYJCwABLgADCgcJEwABAAAAAA==.Annesta:BAABLgAECn8hAAMIAAkJBxnHGADUAQAIAAkJ0hjHGADUAQAMAAEJ9xa0JQA9AAAAAA==.Anriq:BAAALgAECggJCAAAAA==.',
Ap='Apostus:BAAALgADCgcJDgAAAA==.Apothica:BAAALgAECgUJBgAAAA==.',
Aq='Aquafox:BAABLgAECn89AAMGAAkJMx+mCgAMAwAGAAkJMx+mCgAMAwAFAAYJBhw3BgBMAQAAAA==.',
Ar='Archnemesis:BAAALgAECgQJBAAAAA==.Archontas:BAABLgAECn8kAAIJAAgJkSHrCgClAgAJAAgJkSHrCgClAgAAAA==.Ariodh:BAABLgAECn87AAMNAAkJLSaAAgBgAwANAAkJLSaAAgBgAwAOAAUJpB9eJACaAQAAAA==.Ariodr:BAAALgAFFAEJAgAAAA==.Arkaline:BAAALgAFFAEJAQAAAA==.Artuarry:BAACLgAFFH8lAAIPAAcJCRIZNQBzAQAPAAcJCRIZNQBzAQAuAAQKfyYAAg8ACQlGH2MfAGgCAA8ACQlGH2MfAGgCAAAA.Aryndus:BAABLgAECn8lAAICAAkJcx7eHACYAgACAAkJcx7eHACYAgAAAA==.',
At='Athenà:BAAALgAECgUJBQAAAA==.',
Av='Avocado:BAABLgAECn8jAAMDAAkJnCUzDgDgAgADAAkJHiMzDgDgAgAEAAcJVCKaCwCuAQAAAA==.',
Ax='Axelaw:BAAALgADCgQJBAAAAA==.',
Ay='Ayrz:BAAALgAECgIJAgAAAA==.',
Az='Azaria:BAAALgADCgIJAgAAAA==.',
Ba='Baddjujumon:BAABLgAECn8XAAMFAAgJ0gSAWADaAAAFAAgJ0gSAWADaAAAGAAEJoAEf9AAdAAAAAA==.Baileyhowl:BAAALgAECgEJBQAAAA==.Bammie:BAAALgADCgYJCgAAAA==.Bananus:BAAALgAECgIJAwAAAA==.Banthr:BAABLgAECn8XAAIQAAkJNw4tLgCYAQAQAAkJNw4tLgCYAQAAAA==.Barkert:BAAALgADCgYJBAAAAA==.Baroke:BAAALgAECgMJBwABLgAECggJIQAHAOkKAA==.Barokoshama:BAAALgAECgcJEQAAAA==.Basaltytaco:BAAALgADCgEJAQAAAA==.Battleworm:BAAALgADCgkJEwABLgAFFAMJAwABAAAAAA==.',
Bb='Bbalrd:BAACLgAFFH8JAAIKAAMJ0xtYggADAQAKAAMJ0xtYggADAQAuAAQKfxcAAgoACQmiF3xOANcBAAoACQmiF3xOANcBAAAA.',
Be='Bearglie:BAAALgAECggJDgAAAA==.Beepers:BAAALgAECgYJBgAAAA==.Beezelpup:BAAALgAECgYJCQABLgAECgkJFwAQADcOAA==.Belaris:BAAALgAECgQJCQABLgAFFAgJGwAPAOkLAA==.',
Bi='Bigcow:BAAALgAECgUJCQAAAA==.',
Bl='Blackolives:BAAALgAECgkJEQAAAA==.Bladesp:BAAALgAECgYJDQABLgAECgkJGQANAAkSAA==.Blads:BAAALgAECgEJAgAAAA==.Blondefu:BAAALgAECgUJCwAAAA==.Bloodybonne:BAAALgAECgEJAQAAAA==.Bloodyell:BAAALgAECgYJBgAAAA==.Bloore:BAAALgAECgMJAwABLgAECgkJLAAEAG0iAA==.Bluejuly:BAAALgAECgUJBQAAAA==.Blutø:BAAALgAFFAIJAgAAAA==.',
Bo='Boflex:BAAALgADCgQJBgAAAA==.Bomboclat:BAAALgAECgUJCwAAAA==.Bonesknows:BAAALgADCgEJAQAAAA==.Boofy:BAAALgAECgMJAwABLgAECgkJFgAPANwWAA==.Borhoag:BAAALgADCgEJAQABLgAECggJDwABAAAAAA==.Bowwie:BAACLgAFFH8TAAMRAAUJshGzFgAbAQARAAUJaw6zFgAbAQADAAMJZRBibwDCAAAuAAQKfz4ABAMACQnZHy0GACsDAAMACQkTHi0GACsDABEACQkZGkYBADMCAAQAAQkVAxWTACcAAAAA.',
Br='Britney:BAAALgADCgkJCQAAAA==.Brotherfrey:BAAALgAECggJEQAAAA==.Bruish:BAABLgAFFH8MAAISAAQJtwzFDQAWAQASAAQJtwzFDQAWAQAAAA==.Bruty:BAAALgAECgEJAgAAAA==.Brònze:BAACLgAFFH8IAAITAAMJwhnnbgAEAQATAAMJwhnnbgAEAQAuAAQKfzIAAhMABwkyI+UzAEkCABMABwkyI+UzAEkCAAAA.',
Bu='Bubbadoo:BAABLgAECn8lAAIJAAkJzQ9fIwCvAQAJAAkJzQ9fIwCvAQAAAA==.Buddy:BAABLgAECn8ZAAIUAAYJoRI7OgAqAQAUAAYJoRI7OgAqAQABLgAECgkJKgALAL8iAA==.Bulan:BAABLgAECn9NAAIVAAkJryW6AgCcAwAVAAkJryW6AgCcAwAAAA==.',
Bw='Bweninger:BAAALgAECgEJAQAAAA==.',
['Bô']='Bôôsted:BAABLgAECn8iAAIFAAkJ8BTfIAAIAgAFAAkJ8BTfIAAIAgABLgAFFAEJAQABAAAAAA==.',
Ca='Caistan:BAAALgADCgYJCAAAAA==.Calyopi:BAAALgAFFAIJAgAAAA==.Candypants:BAABLgAECn8jAAQVAAkJxRa6GwA6AgAVAAkJxRa6GwA6AgASAAcJ9A6VPAAJAQAWAAMJ2At3aQCBAAAAAA==.Caoth:BAAALgAECgYJEwAAAA==.Cappilon:BAABLgAECn8fAAITAAkJCiJWFwDNAgATAAkJCiJWFwDNAgAAAA==.Carcus:BAABLgAECn82AAIPAAkJkiC8AQC+AgAPAAkJkiC8AQC+AgAAAA==.Carmila:BAAALgADCgEJAQAAAA==.Cayleedah:BAABLgAECn8wAAIEAAkJ5wwNEgA6AQAEAAkJ5wwNEgA6AQAAAA==.Cayssaris:BAABLgAECn8ZAAIXAAkJNBlrDwDwAQAXAAkJNBlrDwDwAQAAAA==.',
Cc='Cc:BAABLgAECn8WAAQYAAYJPBPsDgBCAQAYAAUJ9BPsDgBCAQAZAAYJKwstIwA+AQAPAAQJzhP5tQDtAAAAAA==.',
Ce='Ceeti:BAABLgAECn85AAMaAAkJICGNCADOAgAaAAkJICGNCADOAgAbAAIJeAYcQABpAAAAAA==.Celandrelia:BAAALgAECgUJBQABLgAECggJLAAcAEQXAA==.',
Ch='Chaewon:BAAALgAFFAEJAQABLgAFFAQJEQAHADMkAA==.Channeria:BAAALgAECgEJAQAAAA==.Chaoticoreo:BAABLgAECn80AAMOAAkJYB7qCQCLAgAOAAkJYB7qCQCLAgANAAQJ4w9rrQCzAAAAAA==.Chappedlips:BAAALgAECgkJBwAAAA==.Chareyne:BAABLgAECn8ZAAIHAAgJ5RFyJgC5AQAHAAgJ5RFyJgC5AQAAAA==.Cheetor:BAAALgAECgMJAwABLgAFFAQJFwARACoWAA==.Cheezytaco:BAAALgAECgYJDgABLgAECgkJJAACACMdAA==.Chidge:BAAALgADCggJCwAAAA==.Chihirosan:BAAALgAECgEJAQABLgAFFAQJFwAGAJwSAA==.Chikila:BAABLgAECn8jAAMZAAgJBhlsBwDeAQAZAAgJBhlsBwDeAQAPAAMJeAyQ4wCVAAAAAA==.Chikilia:BAAALgADCgYJBgAAAA==.Chilliflakez:BAABLgAECn8aAAMVAAkJ4A/fSABJAQAVAAgJ5Q7fSABJAQAWAAEJmwpZGwAxAAAAAA==.Chips:BAAALgAECgQJBAAAAA==.Chro:BAAALgAECgcJBwABLgAECgkJOQAFAIAfAA==.',
Ci='Cindezar:BAAALgADCgMJAwAAAA==.',
Cl='Clementyn:BAABLgAECn8WAAICAAcJOBB8zgD1AAACAAcJOBB8zgD1AAAAAA==.Cleyi:BAACLgAFFH8FAAIHAAIJFBV1EwBuAAAHAAIJFBV1EwBuAAAuAAQKfy4AAgcACQnqEtMFAFMBAAcACQnqEtMFAFMBAAAA.',
Co='Coldpasta:BAAALgAECgYJDgABLgAFFAIJBAABAAAAAA==.Coreyy:BAAALgADCgUJBwAAAA==.Corva:BAACLgAFFH8YAAIPAAUJKxKTVwAYAQAPAAUJKxKTVwAYAQAuAAQKfyoAAg8ACQnpFbJDANABAA8ACQnpFbJDANABAAAA.Cosairi:BAAALgAFFAEJAwAAAA==.Cougztroll:BAABLgAECn83AAMXAAkJlRUMEwDCAQAXAAkJlRUMEwDCAQAdAAYJ/gsuKADNAAAAAA==.',
Cr='Crazaki:BAAALgADCgEJAQAAAA==.Cront:BAAALgADCgEJAQABLgAECgkJNgAPAJIgAA==.Crosseye:BAAALgADCgYJCgAAAA==.Crossie:BAAALgADCgEJAQAAAA==.',
Ct='Ctd:BAAALgAECgEJAwABLgAECgkJOQAaACAhAA==.',
Cu='Curfluffin:BAAALgADCgEJAQAAAA==.Cuttercupx:BAAALgAECgQJBQABLgAECgkJEwABAAAAAA==.',
Da='Dahn:BAAALgAECgIJAgAAAA==.Dakadin:BAABLgAECn8mAAMeAAkJ+yPKEgB7AgAeAAkJ+yPKEgB7AgACAAQJ7hef3gDgAAAAAA==.Daranne:BAACLgAFFH8nAAICAAYJ0RPZQwAjAQACAAYJ0RPZQwAjAQAuAAQKfywAAgIACQlzHBc/ACkCAAIACQlzHBc/ACkCAAAA.Darkenedstar:BAAALgAECgYJDQABLgAECgYJEAABAAAAAA==.Darksoulstwo:BAAALgADCgMJAwAAAA==.Dasbeans:BAABLgAECn8cAAMaAAkJNAmyRwAMAQAaAAgJPQqyRwAMAQAcAAIJkgHvRgARAAAAAA==.Dashy:BAABLgAECn8YAAMHAAgJ8R8YFAA2AgAHAAgJVBoYFAA2AgAfAAYJ4B6xFgAiAgAAAA==.Datran:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.',
De='Deaduglie:BAABLgAECn84AAMPAAkJbBYvNwD8AQAPAAkJbBYvNwD8AQAZAAEJMQjvcQA0AAAAAA==.Deamor:BAAALgADCggJCAAAAA==.Deezz:BAAALgAECgUJCAAAAA==.Delamyr:BAAALgADCggJCAAAAA==.Deliandora:BAAALgAECgQJCAAAAA==.Delusional:BAAALgAECgcJDwAAAA==.Delynique:BAAALgADCgEJAQABLgAECgkJLAAEAG0iAA==.Demonknightz:BAAALgAECgMJAwAAAA==.Demonx:BAAALgAECgEJAQAAAA==.Denaric:BAABLgAECn8hAAMgAAgJ+xiQKgABAgAgAAcJkBmQKgABAgAJAAcJJA7OOwAiAQABLgAECgkJHAAaAKkSAA==.Denjie:BAAALgADCgMJAwAAAA==.Dergen:BAAALgAECgkJCwABLgAECgkJEwABAAAAAA==.Destroyevsky:BAABLgAECn8hAAIQAAcJsgI3gQBzAAAQAAcJsgI3gQBzAAAAAA==.Detonate:BAABLgAECn8aAAITAAYJbhyTfwB4AQATAAYJbhyTfwB4AQAAAA==.',
Dh='Dhpoo:BAAALgADCgUJBAAAAA==.Dhvecx:BAAALgAECgUJBgABLgAECgYJDQABAAAAAA==.',
Di='Dilbo:BAAALgAFFAIJAgABLgAFFAcJJAAJAJkaAA==.Diomed:BAAALgAECgEJAQAAAA==.Diqoff:BAAALgAECgIJBAAAAA==.Diqon:BAABLgAECn84AAMKAAkJDRtsNAAtAgAKAAkJDRtsNAAtAgALAAcJtxSPIwA3AQAAAA==.Disturbedtwo:BAAALgAECgYJCgAAAA==.',
Do='Dolphinz:BAACLgAFFH8gAAICAAgJqxdECADTAQACAAgJqxdECADTAQAuAAQKfzIAAwIACQn+IbcQAOECAAIACQn+IbcQAOECACEAAgnpCiI8AE4AAAAA.Doryadni:BAAALgADCgcJBgAAAA==.',
Dr='Draci:BAAALgAECgcJDQABLgAECgkJWAAQAPkeAA==.Dragondaddy:BAABLgAECn8XAAMaAAkJahRSAwB7AQAaAAcJgBRSAwB7AQAcAAkJlwxZDgAmAQAAAA==.Dragonpede:BAACLgAFFH8KAAIaAAUJRRk7GQCcAQAaAAUJRRk7GQCcAQAuAAQKfzkAAhoACQkWIPcJALkCABoACQkWIPcJALkCAAAA.Dragonwarior:BAABLgAECn8fAAIQAAkJ6hv+LACeAQAQAAkJ6hv+LACeAQAAAA==.Drakindees:BAAALgAECgUJBQABLgAECgcJJAATAPYhAA==.Drakkyn:BAABLgAECn8lAAIQAAkJpBoVHQAFAgAQAAkJpBoVHQAFAgAAAA==.Drakonus:BAAALgAECgUJCQAAAA==.Dread:BAAALgADCgQJBAAAAA==.Drosuu:BAAALgAECgEJAQAAAA==.Druish:BAACLgAFFH8lAAIXAAcJrSDBAgARAgAXAAcJrSDBAgARAgAuAAQKfywAAxcACQk0JqMAAG0DABcACQk0JqMAAG0DAB0AAgkOD5ksAGEAAAAA.Drykkr:BAABLgAECn8mAAISAAkJnBYiGQDdAQASAAkJnBYiGQDdAQAAAA==.',
Dt='Dtaylsh:BAAALgAECgEJAQAAAA==.',
Du='Dullahan:BAAALgAECgUJBgAAAA==.Dunstie:BAAALgADCgEJAQABLgAECgcJGwALACoeAA==.Durrik:BAAALgADCgcJBwAAAA==.Duuhh:BAAALgAECgMJBQAAAA==.',
['Dà']='Dàsh:BAAALgAECgYJBgABLgAECggJGAAHAPEfAA==.',
['Dä']='Däshy:BAAALgAECgEJAQABLgAECggJGAAHAPEfAA==.',
Ea='Eatrocks:BAAALgADCggJCAAAAA==.',
Ed='Edorn:BAAALgAECgUJBQAAAA==.',
Ef='Efn:BAAALgAECgYJEwAAAA==.',
El='Elcrys:BAABLgAECn8bAAIgAAcJ5higNgC+AQAgAAcJ5higNgC+AQAAAA==.Elentiya:BAAALgAECgkJDQAAAA==.Eleòs:BAAALgADCgYJBgAAAA==.Elion:BAAALgAECgEJAQAAAA==.Ellyra:BAABLgAFFH8IAAIDAAMJiwVLbwDDAAADAAMJiwVLbwDDAAAAAA==.Elpollo:BAABLgAECn8kAAMTAAcJ9iGUQgBwAgATAAcJ9iGUQgBwAgAiAAEJshe1HAA6AAAAAA==.Elsinn:BAAALgAECgIJAgAAAA==.Elvar:BAABLgAECn8XAAITAAYJlAb2LwBjAAATAAYJlAb2LwBjAAAAAA==.',
Em='Emmdwemm:BAAALgAECgQJCgAAAA==.',
En='Enetash:BAAALgAECgIJAgAAAA==.Enoki:BAAALgAECgQJBAAAAA==.',
Ep='Ephelia:BAACLgAFFH8mAAIGAAYJgSQwBQD8AQAGAAYJgSQwBQD8AQAuAAQKfxkAAwYACQlfGooiAA8CAAYACQlfGooiAA8CAAUAAQmMA/eUACAAAAAA.Epitome:BAABLgAECn8pAAITAAkJsRarPgAhAgATAAkJsRarPgAhAgAAAA==.',
Er='Erid:BAAALgAECgcJEQAAAA==.',
Et='Etude:BAAALgADCgEJAQAAAA==.',
Ev='Evelyndel:BAAALgAECgYJBwAAAA==.Evergrey:BAABLgAECn8ZAAIUAAcJsAwBOwAmAQAUAAcJsAwBOwAmAQAAAA==.Evermoons:BAABLgAECn8jAAIgAAkJVxl0FgCUAgAgAAkJVxl0FgCUAgAAAA==.Evodaka:BAAALgAECgIJAwABLgAECgkJJgAeAPsjAA==.',
Fa='Falaria:BAAALgAECgQJBAAAAA==.Falasdaer:BAABLgAECn8lAAMNAAkJvSKLFQCXAgANAAgJQCKLFQCXAgAOAAQJAiLqHgCDAQAAAA==.Fallansting:BAABLgAECn8WAAINAAcJ0hoNOwDbAQANAAcJ0hoNOwDbAQAAAA==.Falstaff:BAABLgAECn8fAAISAAkJxhWpFgD1AQASAAkJxhWpFgD1AQAAAA==.Fartshooter:BAAALgAECgYJEQAAAA==.Fatterblunt:BAACLgAFFH8kAAIJAAcJmRrREQCTAQAJAAcJmRrREQCTAQAuAAQKfy4AAgkACQlNI3EBAIECAAkACQlNI3EBAIECAAAA.',
Fe='Fedner:BAABLgAECn8XAAIGAAcJSQ+YWQBRAQAGAAcJSQ+YWQBRAQAAAA==.Feldar:BAABLgAECn84AAICAAkJyiHUDwDnAgACAAkJyiHUDwDnAgAAAA==.Fend:BAAALgADCgQJBAAAAA==.Feronite:BAAALgAECgYJCgABLgAFFAUJEwARALIRAA==.Feyredarling:BAAALgAECgMJAwAAAA==.',
Fi='Fistingg:BAAALgADCgMJAwAAAA==.Fists:BAACLgAFFH8MAAISAAQJgBxXIgAiAQASAAQJgBxXIgAiAQAuAAQKfyoAAxIABgmEI44WAFQCABIABgmEI44WAFQCABYABAk3EqtUAL4AAAAA.Fistweaver:BAAALgAECgIJAgAAAA==.Fizzbeard:BAAALgADCgcJCgAAAA==.Fizzical:BAAALgADCgkJFwAAAA==.Fizzleclaw:BAABLgAECn8tAAMXAAkJsR8fAQB0AgAXAAkJsR8fAQB0AgAJAAQJDRFtRwDuAAAAAA==.Fizzleded:BAAALgAECgQJBQABLgAECgkJLQAXALEfAA==.Fizzleflare:BAAALgADCgkJCQAAAA==.',
Fl='Flightrisk:BAAALgAECgQJBgABLgAECgkJEwABAAAAAA==.Flirbert:BAAALgADCgYJBwAAAA==.Florisa:BAABLgAECn8jAAICAAgJ5RyuQwD7AQACAAgJ5RyuQwD7AQAAAA==.',
Fo='Fool:BAAALgAFFAEJAQABLgAFFAMJAwABAAAAAA==.Fordi:BAABLgAECn85AAMFAAkJgB/oCgCyAgAFAAkJcR/oCgCyAgAjAAQJsRYMDgBTAAAAAA==.Forendor:BAAALgAECgMJBwAAAA==.Fourdy:BAABLgAECn8yAAIGAAcJkRlJQACsAQAGAAcJkRlJQACsAQAAAA==.',
Fr='Fragdoll:BAAALgAECgQJCgAAAA==.Freakinlarry:BAAALgADCgEJAQAAAA==.Freakinoak:BAACLgAFFH8IAAIgAAMJ5AjjHAB6AAAgAAMJ5AjjHAB6AAAuAAQKfy4AAiAACQmjFPAjACwCACAACQmjFPAjACwCAAAA.Freakintim:BAAALgAECgYJBgAAAA==.Fredboat:BAAALgAECgEJAgABLgAFFAIJCgAKAL0mAA==.Free:BAABLgAECn8ZAAMNAAkJCRJVQwC+AQANAAgJCRJVQwC+AQAkAAUJ9Ap3IACAAAAAAA==.Frenn:BAAALgAECgUJCQAAAA==.Froost:BAACLgAFFH8dAAMKAAYJ6BSFJAA0AQAKAAUJ6BSFJAA0AQALAAEJAAA+VQAAAAAuAAQKfxgAAgoACQlfHvRMAAwCAAoACQlfHvRMAAwCAAAA.',
Fu='Funkflex:BAAALgAECgEJAQABLgAECgkJGQANAAkSAA==.Furvert:BAAALgAECgkJEwAAAA==.Fushi:BAAALgAECgEJAQAAAA==.',
Ga='Gandis:BAAALgAECgkJEgAAAA==.Gapper:BAACLgAFFH8XAAIRAAQJKhYYEgA3AQARAAQJKhYYEgA3AQAuAAQKf1gAAxEACQmNJUQBAFcDABEACQmNJUQBAFcDAAQABAmnH4ICABcBAAAA.Gargodath:BAAALgAFFAMJAwAAAA==.',
Gi='Gielinor:BAAALgADCgIJAgAAAA==.',
Gl='Glamour:BAAALgADCgEJAgAAAA==.Glestaar:BAACLgAFFH8HAAIDAAMJrwwsZgDZAAADAAMJrwwsZgDZAAAuAAQKfykAAwMACAmfHGkwABoCAAMACAmfHGkwABoCAAQAAglFC4V8AFIAAAAA.Glitterpants:BAAALgAECgMJBAAAAA==.Glyr:BAAALgAECgYJCgAAAA==.',
Go='Goingrouge:BAAALgAECgYJCgAAAA==.Goldabelle:BAAALgAECgYJCgAAAA==.Goonkin:BAAALgAFFAIJAgABLgAFFAQJFwARACoWAA==.Gorlami:BAABLgAFFH8GAAICAAMJZA5AgwCuAAACAAMJZA5AgwCuAAAAAA==.Gothelf:BAAALgAFFAIJBAAAAA==.Gothri:BAAALgAECgcJDQABLgAECgcJFQAaAJAVAA==.Gothstraza:BAABLgAECn8VAAIaAAcJkBUXOgBEAQAaAAcJkBUXOgBEAQAAAA==.Gottemgood:BAAALgADCgUJBQAAAA==.',
Gr='Grimli:BAABLgAECn8jAAIGAAkJwQ8NRQCaAQAGAAkJwQ8NRQCaAQAAAA==.Grimmz:BAAALgADCgcJCwAAAA==.Growth:BAABLgAECn8ZAAMUAAkJNAm6LwBgAQAUAAkJNAm6LwBgAQAfAAYJohBmOQArAQAAAA==.',
Gu='Gurthcaptian:BAAALgAECgQJBAAAAA==.',
Gy='Gyatso:BAAALgADCgMJAwAAAA==.',
['Gá']='Gárròsh:BAAALgAECgYJBgAAAA==.',
['Gô']='Gôôse:BAAALgAFFAEJAQAAAA==.',
Ha='Haerin:BAAALgAECgIJAgABLgAFFAQJEQAHADMkAA==.Happykilmøre:BAAALgAECgQJBAABLgAECgkJEgABAAAAAA==.Harnel:BAABLgAECn83AAICAAkJBQVMLQBxAAACAAkJBQVMLQBxAAAAAA==.Haseo:BAAALgAECgkJDQAAAA==.Hashira:BAAALgADCggJDQAAAA==.Hattorihanzo:BAAALgAECggJDwAAAA==.',
He='Healeymonstr:BAAALgADCgIJAgAAAA==.Healmart:BAABLgAECn8ZAAIfAAkJcwZFOQAsAQAfAAkJcwZFOQAsAQAAAA==.Heartëater:BAAALgADCgYJBgAAAA==.Hellinyoface:BAAALgADCgUJBQAAAA==.Heymage:BAAALgADCgkJCQAAAA==.',
Hi='Himothyy:BAAALgAECgQJBAAAAA==.',
Ho='Holypeetch:BAAALgADCgYJBgAAAA==.Hoofpics:BAAALgAECgQJBAAAAA==.Hordedefect:BAAALgAECgEJAQABLgAECgkJEwABAAAAAA==.Hoyer:BAAALgAECgkJEwAAAA==.',
Hu='Hulkhogan:BAAALgAECggJDgAAAA==.Humbledrink:BAAALgAECggJDQAAAA==.',
Im='Impact:BAAALgADCgcJCgAAAA==.',
In='Inflícted:BAACLgAFFH8WAAIfAAYJ9QpBEgDuAAAfAAYJ9QpBEgDuAAAuAAQKfxgAAh8ACQmkEk4ZAAcCAB8ACQmkEk4ZAAcCAAAA.Innoscent:BAAALgAECgYJBgAAAA==.Inzo:BAAALgAFFAEJAgAAAA==.',
Io='Iove:BAABLgAECn8aAAIVAAkJZBVYIQASAgAVAAkJZBVYIQASAgAAAA==.',
Ja='Jago:BAAALgADCggJDgAAAA==.Jahsahm:BAAALgAECgcJEQAAAA==.Jajung:BAAALgADCgMJAwAAAA==.Jakub:BAABLgAECn8oAAILAAkJkRizDgAgAgALAAkJkRizDgAgAgABLgAFFAUJEwARALIRAA==.Jakuren:BAAALgADCgYJBgAAAA==.Jamjam:BAAALgAECgUJBQAAAA==.',
Je='Jesit:BAABLgAECn8aAAIbAAYJ8hXgFAB9AQAbAAYJ8hXgFAB9AQAAAA==.',
Jh='Jhonn:BAAALgAECgEJAQABLgAECgkJRgAlAL8iAA==.',
Ji='Jingles:BAAALgADCgYJBgAAAA==.',
Jj='Jjada:BAACLgAFFH8JAAMNAAQJvw2wUQD4AAANAAQJvw2wUQD4AAAkAAEJdBXoEQA9AAAuAAQKfx0AAw0ACQnFIQgQAMICAA0ACQl0IAgQAMICACQABgmeIYAFAE0CAAAA.',
Jo='Johnwolf:BAABLgAECn8ZAAICAAkJ0gMG9wDCAAACAAkJ0gMG9wDCAAAAAA==.',
Jy='Jyade:BAABLgAECn9EAAMMAAkJtBS+AADeAQAMAAkJtBS+AADeAQAmAAUJnwifCAD6AAAAAA==.Jynoria:BAAALgADCgcJDAAAAA==.',
Ka='Kainlok:BAAALgADCgIJAgAAAA==.Kaiserice:BAAALgAECgcJEAAAAA==.Kaliel:BAAALgAECgYJEwAAAA==.Kamarra:BAABLgAECn8iAAMaAAcJ4Qj7VADdAAAaAAcJmgf7VADdAAAcAAIJVAkEBgBMAAAAAA==.Kamencider:BAABLgAECn8dAAITAAcJ8RAymABIAQATAAcJ8RAymABIAQAAAA==.Kamidala:BAAALgAECgIJAgAAAA==.Kanata:BAAALgAECgEJAQAAAA==.Kankles:BAACLgAFFH8FAAIJAAQJ3x40HAA5AQAJAAQJ3x40HAA5AQAuAAQKfyoAAgkACAnuIkELAJ8CAAkACAnuIkELAJ8CAAAA.Karbonn:BAAALgAECgkJAQAAAA==.Karhualaston:BAAALgAECgEJAQAAAA==.Karva:BAAALgAECgIJAwAAAA==.Katabetta:BAAALgADCgMJAwAAAA==.Kayati:BAABLgAECn8YAAIGAAkJiRg6AgCXAgAGAAkJiRg6AgCXAgABLgAFFAgJGwAPAOkLAA==.',
Ke='Kellmagnison:BAAALgAECgIJAgABLgAECgkJOAACANUIAA==.Kentukee:BAAALgAECgQJBgABLgAECgkJKQARALoSAA==.Kernelpanic:BAACLgAFFH8kAAMKAAcJExznKADGAQAKAAcJExznKADGAQAnAAEJ/gXaKwA6AAAuAAQKfysAAgoACQkCIlwgAIcCAAoACQkCIlwgAIcCAAAA.Kessho:BAAALgAECgYJDwABLgAFFAUJEwARALIRAA==.Kevynn:BAAALgADCgMJAgAAAA==.Keyoshi:BAAALgAECgYJBgAAAA==.',
Ki='Kickrocks:BAAALgAECgEJAQAAAA==.Kilerforlife:BAAALgAECgYJCwAAAA==.Kilgarnish:BAAALgAECgEJAgAAAA==.Kilowog:BAAALgADCgUJCAAAAA==.Kilpally:BAAALgAECgYJBwAAAA==.Kintra:BAAALgADCgIJAgAAAA==.Kirin:BAAALgAECgEJAQAAAA==.Kirkle:BAABLgAECn9wAAIZAAkJ2iEqAAAAAwAZAAkJ2iEqAAAAAwAAAA==.Kithara:BAAALgAECgEJAwAAAA==.',
Ko='Kovie:BAAALgADCggJCAAAAA==.Kovy:BAABLgAECn8VAAMLAAkJ8RZ6FADJAQALAAkJ8RZ6FADJAQAKAAEJCQQKJQEvAAAAAA==.Kovya:BAAALgADCgYJBwAAAA==.',
Kr='Krelel:BAAALgADCgIJAgAAAA==.Kriaast:BAAALgAECgMJAwAAAA==.Krukar:BAAALgADCgYJDAAAAA==.',
Ku='Kubo:BAAALgAECgYJBwABLgAFFAUJEwARALIRAA==.',
Ky='Kydroga:BAAALgAECgYJEQAAAA==.Kynaria:BAABLgAECn8XAAIDAAcJXxdPCQCtAQADAAcJXxdPCQCtAQAAAA==.Kynsia:BAAALgADCgQJBgAAAA==.',
La='Lamörak:BAABLgAECn81AAICAAkJZiJYDgDzAgACAAkJZiJYDgDzAgAAAA==.Landrick:BAABLgAECn9AAAMKAAkJVh3bIQCAAgAKAAkJVh3bIQCAAgALAAEJyhfaEQBCAAAAAA==.Lastotem:BAAALgADCgEJAQAAAA==.Lastshot:BAABLgAECn8XAAIDAAgJxhNQQQDeAQADAAgJxhNQQQDeAQAAAA==.Latest:BAAALgADCgQJBAAAAA==.Lavaevoker:BAAALgADCgcJBwABLgAECggJKAASAO8LAA==.Lavanor:BAAALgADCgIJAgAAAA==.Lavasaurus:BAABLgAECn8iAAQbAAgJkho7EwCVAQAbAAYJUxo7EwCVAQAaAAgJSA+aMAB1AQAcAAEJDRNtJAA6AAAAAA==.',
Le='Leafstorm:BAAALgAECgYJDwAAAA==.Lehala:BAAALgADCgQJBAAAAA==.Lektar:BAAALgAECgUJBQABLgAECgYJEwABAAAAAA==.Leloosh:BAAALgADCgkJDAABLgAFFAIJBAABAAAAAA==.Lemon:BAABLgAECn80AAIZAAkJURXlBgDuAQAZAAkJURXlBgDuAQAAAA==.Leokenoso:BAABLgAECn8mAAIkAAkJ8hR8CgC7AQAkAAkJ8hR8CgC7AQAAAA==.Lesclaypool:BAAALgAECgcJCgAAAA==.Lessalia:BAAALgAECgEJAQAAAA==.Lewd:BAAALgAECgUJCgAAAA==.Lexor:BAAALgADCgQJBAAAAA==.',
Li='Lifebloomz:BAABLgAECn82AAIgAAkJDw60OgCpAQAgAAkJDw60OgCpAQAAAA==.Lifesabeach:BAAALgAECgMJAwAAAA==.Lilfluffcc:BAAALgAECgQJBAAAAA==.Lissana:BAAALgADCgUJBQAAAA==.',
Lo='Lockward:BAAALgAECgUJBwAAAA==.Loidvoid:BAAALgAECgYJDQAAAA==.Lorblor:BAABLgAECn8yAAQkAAkJSyFlAgDaAgAkAAkJCCBlAgDaAgAOAAcJMxoSAgAkAgANAAEJAAB4PAAAAAAAAA==.Lorerun:BAAALgADCgUJCAAAAA==.Lowang:BAABLgAECn8dAAISAAkJnROvJwB0AQASAAkJnROvJwB0AQAAAA==.Lowmein:BAABLgAECn8UAAIGAAgJMR4lKgDlAQAGAAgJMR4lKgDlAQAAAA==.',
Lu='Lucidlux:BAAALgAECgEJAgAAAA==.Lucÿfer:BAAALgAFFAIJAwAAAA==.Lumie:BAAALgAECgYJEQAAAA==.Luminisx:BAAALgADCgMJAwAAAA==.Lunafox:BAABLgAECn8oAAIGAAgJOh4KFgCaAgAGAAgJOh4KFgCaAgAAAA==.Lunamae:BAABLgAECn8pAAIiAAkJJBlsAwDtAQAiAAkJJBlsAwDtAQAAAA==.Lupacho:BAAALgAFFAIJAwAAAA==.Luvvyaa:BAAALgAECgcJBwABLgAECgkJagAfAEAiAA==.Luvvyyaa:BAABLgAECn9qAAMfAAkJQCKgAABdAwAfAAkJCCGgAABdAwAHAAkJ+h2xCADAAgAAAA==.Luvyya:BAAALgAECgYJEAABLgAECgkJagAfAEAiAA==.Luvyyaa:BAAALgAECgQJBQABLgAECgkJagAfAEAiAA==.',
Ly='Lyllianne:BAAALgADCgIJAgAAAA==.Lyrinaku:BAABLgAECn8UAAIHAAcJWRVQNgBkAQAHAAcJWRVQNgBkAQAAAA==.Lythomancer:BAABLgAECn8lAAIZAAkJyA5aEAA8AQAZAAkJyA5aEAA8AQAAAA==.',
Ma='Maddeena:BAABLgAECn8yAAMGAAkJIQ36CABxAQAGAAkJIQ36CABxAQAFAAEJBRCFIgAuAAAAAA==.Maddy:BAABLgAECn8iAAMWAAkJWBopFQAQAgAWAAgJYh0pFQAQAgASAAkJexBPGgDTAQAAAA==.Maelyssa:BAAALgADCgMJAwAAAA==.Magicmangge:BAAALgADCgYJBgABLgAFFAEJAQABAAAAAA==.Makeitclap:BAAALgAECgMJBAABLgAECgcJHQATAPEQAA==.Malidian:BAABLgAECn8dAAINAAkJdw9DVgCEAQANAAkJdw9DVgCEAQAAAA==.Matchadaddy:BAAALgAECgEJAwAAAA==.Maxohlx:BAACLgAFFH8bAAIPAAgJ6QvXKgCaAQAPAAgJ6QvXKgCaAQAuAAQKf1AAAg8ACQnRItUIAA4DAA8ACQnRItUIAA4DAAAA.',
Mc='Mcmercie:BAAALgAECgkJCgAAAA==.',
Me='Mechacooter:BAAALgAFFAMJAwAAAA==.Meeko:BAAALgADCgUJBQABLgAFFAkJMgAbAPsiAA==.Megahertz:BAAALgADCgEJAQAAAA==.Megg:BAAALgADCggJEQAAAA==.Meilia:BAAALgADCgUJBwAAAA==.Mekagatha:BAAALgADCgkJEgAAAA==.Mekari:BAABLgAECn80AAIRAAkJex4gCgB9AgARAAkJex4gCgB9AgAAAA==.Mekhail:BAAALgADCggJCAAAAA==.Melchiorr:BAACLgAFFH8WAAIYAAUJxhpaAwBiAQAYAAUJxhpaAwBiAQAuAAQKfyoAAhgACQksHkQFADgCABgACQksHkQFADgCAAAA.Melignant:BAAALgADCgEJAQAAAA==.Melosia:BAAALgADCgQJBwAAAA==.Melynne:BAABLgAECn9HAAMGAAkJ4BWAIgBAAgAGAAkJ4BWAIgBAAgAFAAIJeATEgQBBAAAAAA==.Memmel:BAAALgADCgMJAwAAAA==.Meredeath:BAABLgAECn8UAAIJAAgJKg14RQD2AAAJAAgJKg14RQD2AAAAAA==.',
Mi='Micro:BAAALgAECgkJEwAAAA==.Microkeg:BAAALgAECgcJBAAAAA==.Microslash:BAAALgADCgMJAwABLgAECgkJEwABAAAAAA==.Minji:BAAALgAFFAEJAQABLgAFFAQJEQAHADMkAA==.Minsoo:BAACLgAFFH8QAAIVAAUJuxpvEwAsAQAVAAUJuxpvEwAsAQAuAAQKfx0AAhUACQkOHkUNAMcCABUACQkOHkUNAMcCAAAA.Mistblade:BAAALgAECgQJDQABLgAECgkJGQANAAkSAA==.Miststriker:BAAALgAECgUJCQAAAA==.Mistytaco:BAAALgAECgEJAQAAAA==.',
Ml='Mlrglett:BAABLgAECn9FAAMXAAkJrSJmAwDwAgAXAAkJrSJmAwDwAgAJAAEJihMfhgAqAAAAAA==.Mlrglo:BAAALgADCgcJCQAAAA==.',
Mm='Mmooney:BAAALgADCgIJAgABLgAECgkJFwAQADcOAA==.',
Mo='Moisturizeme:BAAALgAECgUJBQAAAA==.Mojomaker:BAABLgAECn8VAAIGAAYJAhL4XQBDAQAGAAYJAhL4XQBDAQAAAA==.Moojitsu:BAAALgADCgMJAwAAAA==.Mormegil:BAABLgAECn8qAAMLAAkJvyLKCACHAgALAAkJKCHKCACHAgAnAAMJMhTzBwCZAAAAAA==.Moshimoshi:BAACLgAFFH8YAAMGAAcJDBA4HACKAQAGAAcJDBA4HACKAQAFAAIJWAkwSQBrAAAuAAQKfx4AAwUACQlsHGcbADcCAAUACAlHHGcbADcCAAYACAlGCXRRAD8BAAAA.Motosake:BAAALgAECgQJBQAAAA==.',
Mu='Muffinlord:BAAALgAECgYJEQAAAA==.Munkeebutt:BAABLgAECn8gAAQRAAkJMQmJHgCoAQARAAkJDQmJHgCoAQAEAAcJYAcoUwD/AAADAAEJsQst1QAwAAAAAA==.Munkeefase:BAAALgADCgEJAQAAAA==.',
My='Myronis:BAAALgADCgIJAgAAAA==.Mythaera:BAAALgADCgYJBwAAAA==.',
Na='Naberius:BAABLgAECn8cAAMaAAkJqRL4LwB4AQAaAAkJqRL4LwB4AQAbAAIJ7gcqPgArAAAAAA==.Naillil:BAAALgAECgEJAQAAAA==.Namiiswan:BAAALgADCgMJBQAAAA==.Nasmine:BAAALgADCgEJAQAAAA==.Natsuki:BAAALgADCgUJBwAAAA==.',
Ne='Nefarius:BAAALgAFFAEJAQAAAA==.Neflite:BAABLgAECn8eAAIZAAcJvwfdGwDGAAAZAAcJvwfdGwDGAAAAAA==.Nelfie:BAAALgAECgEJAQAAAA==.Nessará:BAABLgAECn8WAAIHAAYJQCHvFQAjAgAHAAYJQCHvFQAjAgAAAA==.',
Ni='Nineõseven:BAABLgAECn8YAAIUAAcJixN9IADVAQAUAAcJixN9IADVAQABLgAECgEJAQABAAAAAA==.Ninjapro:BAAALgAECgkJAgAAAA==.Nixia:BAAALgAECgQJBQAAAA==.',
No='Nodiddy:BAAALgAECgQJDAABLgAECgcJJAATAPYhAA==.Nowari:BAAALgAECgQJBAABLgAFFAIJBQAHABQVAA==.',
Nu='Nuraga:BAABLgAECn8hAAMlAAgJlyHXBwCpAgAlAAcJCSTXBwCpAgAQAAEJ7hK6lwBDAAAAAA==.',
Ob='Obeeone:BAAALgAECgEJAgAAAA==.Obviate:BAAALgAECgEJAgAAAA==.',
On='Onasta:BAABLgAECn8hAAIKAAkJkx+MOAAdAgAKAAkJkx+MOAAdAgAAAA==.Onelastkiss:BAAALgAECgEJAQAAAA==.',
Oo='Oogway:BAAALgAECgcJBwAAAA==.',
Op='Oprahheals:BAABLgAECn8cAAICAAkJFB6fGACvAgACAAkJFB6fGACvAgAAAA==.',
Or='Oreoagane:BAAALgAFFAEJAQAAAA==.Oreobeer:BAAALgAECgEJAQAAAA==.Oreomonster:BAAALgAECgcJEQAAAA==.Orquesta:BAAALgAECgQJCwAAAA==.',
Pa='Paccer:BAAALgAECgEJAQAAAA==.Pacerx:BAAALgAECgIJAgAAAA==.Pandaemonia:BAACLgAFFH8kAAIkAAYJdBEdAwDzAAAkAAYJdBEdAwDzAAAuAAQKfyQAAiQACQncDaMWAPIAACQACQncDaMWAPIAAAAA.Pandaemonium:BAAALgAECgEJAQABLgAECgYJEAABAAAAAA==.Pandakyle:BAABLgAECn8XAAIVAAYJ5xc/SgBDAQAVAAYJ5xc/SgBDAQAAAA==.Pandexander:BAAALgADCgMJAwAAAA==.Panterå:BAAALgAECgEJAgABLgADCgcJEwABAAAAAA==.Parts:BAABLgAECn8iAAITAAgJtiGIIQDtAgATAAgJtiGIIQDtAgABLgAFFAYJGQAnAJoYAA==.Patchmen:BAAALgAECgQJBAAAAA==.Pattilicious:BAABLgAECn8kAAICAAkJZwt3egB5AQACAAkJZwt3egB5AQAAAA==.',
Pe='Pease:BAAALgAECgEJAQAAAA==.Pepsizero:BAAALgAECgUJCwAAAA==.',
Ph='Phlesh:BAAALgAECgEJAgAAAA==.Phlvrabies:BAAALgADCgMJBQAAAA==.Phonedin:BAABLgAECn8jAAMcAAkJERmdBgCIAgAcAAkJERmdBgCIAgAaAAMJBhchSQCyAAAAAA==.Phoënix:BAACLgAFFH8YAAMGAAYJzxVJGQCdAQAGAAYJzxVJGQCdAQAFAAIJwQOcUABUAAAuAAQKfywAAwYACQmWHdMSALYCAAYACQmWHdMSALYCAAUABAnmGL5lALQAAAAA.',
Pi='Pieglaive:BAABLgAECn8jAAMOAAkJzSGyCAChAgAOAAkJzSGyCAChAgANAAIJuhZpwwB2AAAAAA==.Pierres:BAAALgAECgkJEgAAAA==.Piondelth:BAAALgAECgcJEQAAAA==.',
Pl='Plantman:BAAALgAECgYJDgAAAA==.Plumberman:BAAALgAECgYJCwAAAA==.',
Po='Pointyboner:BAAALgADCgYJCAAAAA==.Poofort:BAAALgAECgYJDwAAAA==.Pooner:BAAALgADCgMJAwAAAA==.Porkins:BAAALgAECgMJAwAAAA==.Postoak:BAAALgAECgUJCgAAAA==.Powerochrist:BAABLgAECn8xAAIeAAkJ+BllEACVAgAeAAkJ+BllEACVAgAAAA==.',
Pr='Priscila:BAAALgADCgYJBgAAAA==.Proctologie:BAAALgAECgMJBAAAAA==.Proxzy:BAABLgAECn8ZAAIFAAgJ/yD2DACWAgAFAAgJ/yD2DACWAgAAAA==.',
Pu='Pubessalad:BAABLgAECn8xAAICAAYJHB0GZQClAQACAAYJHB0GZQClAQAAAA==.Puddin:BAAALgADCgQJBwAAAA==.Puffytaco:BAAALgAECgYJCwABLgAECgkJJAACACMdAA==.',
Py='Pyrug:BAAALgAECgUJCAABLgAECgkJOAAPAGwWAA==.',
Qu='Qualek:BAABLgAECn8XAAIlAAkJMRJfEAADAgAlAAkJMRJfEAADAgAAAA==.Quilue:BAABLgAECn8kAAITAAkJoBWPQgAUAgATAAkJoBWPQgAUAgAAAA==.',
Ra='Rankak:BAAALgAFFAIJAgAAAA==.Rannmagnison:BAABLgAECn84AAICAAkJ1QjXigBbAQACAAkJ1QjXigBbAQAAAA==.Raquoon:BAABLgAECn8cAAIlAAkJuw5BHwA5AQAlAAkJuw5BHwA5AQAAAA==.Rasonia:BAAALgAFFAEJAQABLgAFFAQJDwAfAOERAA==.Ratfu:BAAALgADCgcJDQAAAA==.Raumulus:BAAALgAFFAEJAQAAAA==.Razjin:BAABLgAECn8aAAMGAAkJeiPsCQDaAgAGAAkJeiPsCQDaAgAFAAEJ/wqzsgAnAAAAAA==.',
Re='Reapér:BAAALgAECgkJBQAAAA==.Reckjames:BAAALgAECgEJAQAAAA==.Rene:BAAALgADCgYJBgAAAA==.Reze:BAACLgAFFH8YAAIWAAQJVCGWDABeAQAWAAQJVCGWDABeAQAuAAQKfxYAAhYACAlYHqcRADYCABYACAlYHqcRADYCAAEuAAUUCQleAA4AlCYA.',
Rh='Rhaeynera:BAABLgAECn8vAAIcAAkJ1QbzDwALAQAcAAkJ1QbzDwALAQAAAA==.Rhyel:BAAALgADCgIJAgAAAA==.Rhyno:BAAALgADCgkJGwABLgAECgkJOwAPAO0gAA==.Rhysedwyn:BAAALgADCgkJEgABLgAECgEJAQABAAAAAA==.',
Ri='Riezen:BAABLgAECn8XAAIKAAkJpBL+EwDqAAAKAAkJpBL+EwDqAAAAAA==.Ringol:BAAALgAECgQJCgABLgAECgYJDgABAAAAAA==.Rinorik:BAABLgAECn87AAQPAAkJ7SDZEQC9AgAPAAkJQiDZEQC9AgAZAAYJPhz2FACjAQAYAAEJTCPhCQBmAAAAAA==.Rizzdor:BAAALgADCgcJCAABLgAECgkJEgABAAAAAA==.',
Ro='Roam:BAAALgAECgEJAQAAAA==.Rockbiter:BAAALgAECgEJAgAAAA==.Rockhhard:BAABLgAECn8eAAIGAAkJxx5eHwBUAgAGAAkJxx5eHwBUAgAAAA==.Roeken:BAABLgAECn86AAIQAAkJKRXYIADqAQAQAAkJKRXYIADqAQAAAA==.Rollingman:BAABLgAECn8ZAAIVAAkJlRYtJQD6AQAVAAkJlRYtJQD6AQAAAA==.Roummi:BAAALgAECgEJAQAAAA==.',
Ru='Rudybear:BAAALgAECgEJAQABLgAFFAEJAgABAAAAAA==.Rudyrots:BAAALgAECgEJAQABLgAFFAEJAgABAAAAAA==.Rudyshoots:BAAALgAFFAEJAgAAAA==.Rui:BAAALgAECgMJAwAAAA==.Rum:BAAALgAECgMJAwAAAA==.',
Ry='Rybear:BAAALgAECgEJBAAAAA==.Rygaard:BAABLgAECn84AAIlAAkJHyIgBQDJAgAlAAkJHyIgBQDJAgAAAA==.Rystic:BAAALgADCgkJGQAAAA==.Ryutiz:BAABLgAECn8sAAIEAAkJbSLuAQDqAgAEAAkJbSLuAQDqAgAAAA==.Ryward:BAAALgADCgcJBwAAAA==.Ryyuk:BAAALgAECgMJBAABLgAECgkJGQANAAkSAA==.',
Sa='Sacridas:BAAALgAECgEJAQABLgAECgkJLAAEAG0iAA==.Sako:BAAALgADCgUJCgAAAA==.Salandar:BAAALgAECgIJAgABLgAECgkJOAACANUIAA==.Samsó:BAABLgAECn8aAAQCAAkJqxjEaQCrAQACAAkJqxjEaQCrAQAeAAQJ3BQNagDSAAAhAAEJVwnxEwAqAAAAAA==.Sapharina:BAACLgAFFH8PAAIfAAQJ4RHzJgASAQAfAAQJ4RHzJgASAQAuAAQKfzMAAh8ACQmWF+4QAGQCAB8ACQmWF+4QAGQCAAAA.Sassgrip:BAAALgADCgEJAQABLgAECgcJEAABAAAAAA==.Sassier:BAAALgAECgcJEAAAAA==.Sathenaz:BAAALgADCgcJCQAAAA==.',
Sc='Scarcy:BAACLgAFFH8bAAIIAAgJFhQqCwDnAQAIAAgJFhQqCwDnAQAuAAQKfzMAAwgACQliGrAQAJ0CAAgACQliGrAQAJ0CACYAAwmXCHgeAFoAAAAA.Schreckstoff:BAAALgADCgYJBgABLgAECgkJKQARALoSAA==.',
Se='Seacotton:BAABLgAECn8fAAMoAAkJvxuaBwB9AgAoAAkJFRuaBwB9AgAQAAcJoBVaQACjAQAAAA==.Searfang:BAACLgAFFH8eAAIFAAYJBxT/CwBOAQAFAAYJBxT/CwBOAQAuAAQKfzgAAwUACQmEIYgHAOQCAAUACQmEIYgHAOQCAAYAAQljE8HTADYAAAAA.Seariel:BAAALgAECgUJBwABLgAFFAYJHgAFAAcUAA==.Seatea:BAAALgADCgkJCQABLgAECgkJOQAaACAhAA==.Selestra:BAAALgAFFAIJAgAAAA==.Selinise:BAAALgAECgUJBQAAAA==.Sematic:BAAALgAFFAEJAQABLgAFFAYJFQATABkcAA==.Senpai:BAAALgAECgQJBAAAAA==.Seraphymm:BAAALgADCgEJAQAAAA==.',
Sh='Shadowjacker:BAACLgAFFH8UAAINAAYJAhh1PAA0AQANAAYJAhh1PAA0AQAuAAQKfzgAAg0ACQkmIYIHAFEDAA0ACQkmIYIHAFEDAAAA.Shadowmidget:BAABLgAECn8WAAIPAAkJ3BahVwDBAQAPAAkJ3BahVwDBAQAAAA==.Shadowsburns:BAAALgADCgEJAQAAAA==.Shadrielis:BAABLgAECn9EAAMfAAkJvR+HCQDZAgAfAAkJvR+HCQDZAgAHAAIJVQ3VbgBsAAAAAA==.Shallanra:BAAALgAECgQJBQABLgAECgcJGwAgAOYYAA==.Shanlao:BAAALgAFFAIJAgABLgAFFAcJJQAPAAkSAA==.Sharael:BAAALgAFFAEJAgAAAA==.Shiftytank:BAAALgADCgEJAQAAAA==.Shirkka:BAAALgADCgMJBAAAAA==.Shurihito:BAABLgAECn8lAAICAAkJiR5OIgB9AgACAAkJiR5OIgB9AgAAAA==.',
Si='Sieron:BAABLgAECn8UAAIKAAYJ/RxekgBBAQAKAAYJ/RxekgBBAQAAAA==.Silaslunark:BAAALgAECgkJCwAAAA==.Sinkrow:BAAALgAECgYJBgAAAA==.Sixpack:BAABLgAECn8dAAIgAAkJjA7xPACfAQAgAAkJjA7xPACfAQAAAA==.',
Sk='Skarigar:BAAALgAECgEJAwAAAA==.Skeeter:BAAALgAECgkJEAABLgAFFAQJFwARACoWAA==.Skeeterson:BAAALgADCgUJCAAAAA==.Skurplock:BAAALgADCgEJAQAAAA==.Skytec:BAAALgADCgMJAwAAAA==.Skëëts:BAABLgAECn8cAAQfAAgJSBBDKQCJAQAfAAgJJBBDKQCJAQAUAAEJuwTokwAnAAAHAAEJ5gaydAAlAAAAAA==.Skùrvypete:BAAALgAFFAEJAQAAAA==.',
Sl='Slampoof:BAAALgAECgQJDwAAAA==.Slamslayer:BAAALgAECgEJAQAAAA==.Sleez:BAAALgAECgYJDAAAAA==.Sloodraga:BAAALgADCgYJBgAAAA==.',
Sm='Smallgregory:BAAALgAECgYJDAAAAA==.',
Sn='Sneakdead:BAAALgAECgcJCgAAAA==.Sneakerzz:BAAALgADCgQJBAAAAA==.Sneakfury:BAAALgAECgYJCgABLgAECgcJCgABAAAAAA==.Sneeler:BAAALgAECgEJAQAAAA==.Snowscayia:BAACLgAFFH8NAAQgAAcJUhXTLAACAQAgAAUJcQ7TLAACAQAJAAUJSQh1KwDfAAAdAAIJIQqeGABuAAAuAAQKfy4ABAkACQkbGDMnAMUBAAkACAk2GjMnAMUBACAABwleGD87ALgBAB0AAQlhCfNQADcAAAAA.',
So='Solanar:BAABLgAECn9AAAMeAAkJgSMJEQCNAgAeAAgJsiMJEQCNAgACAAcJESHBMQA5AgAAAA==.Solesin:BAAALgAFFAEJAQABLgAFFAUJEwAbADIXAA==.Solm:BAAALgAECgEJAwAAAA==.Solmina:BAABLgAECn83AAITAAkJIh7hHwCfAgATAAkJIh7hHwCfAgAAAA==.Somniatis:BAAALgAECgEJAQAAAA==.Soobin:BAAALgAECgkJCgAAAA==.Soulciopath:BAAALgAECgUJCAAAAA==.Souljin:BAAALgADCgMJAwAAAA==.Soybeans:BAAALgAECgcJBwAAAA==.',
Sp='Spartan:BAAALgAECgQJBAAAAA==.Spicypants:BAAALgADCgMJAwAAAA==.Spicytaco:BAAALgAECgUJCgABLgAECgkJJAACACMdAA==.Spookuleli:BAAALgADCggJCwAAAA==.Sprinklewiz:BAAALgADCgMJAwAAAA==.',
Sq='Squadie:BAABLgAECn8+AAIDAAkJpgvyaQBuAQADAAkJpgvyaQBuAQAAAA==.Squanchs:BAACLgAFFH8YAAIGAAcJChrvFAC+AQAGAAcJChrvFAC+AQAuAAQKfx4AAwYACQlkHygMAL8CAAYACQlkHygMAL8CAAUAAQkGAPbHAAEAAAEuAAQKBwkcACAAkxsA.Squanchy:BAABLgAECn8cAAIgAAcJkxtxPACyAQAgAAcJkxtxPACyAQAAAA==.Squisquee:BAAALgADCgcJBwAAAA==.',
Sr='Srbojangles:BAAALgAECgcJCAABLgAECgcJJAATAPYhAA==.Srry:BAABLgAECn8VAAIQAAcJsBrUKQATAgAQAAcJsBrUKQATAgAAAA==.',
St='Stinkvile:BAAALgAECgEJAQAAAA==.Stonebraid:BAAALgADCgEJAQAAAA==.Sturdy:BAAALgADCgEJAQAAAA==.Stôrmfang:BAAALgAECgUJBQAAAA==.',
Su='Suga:BAAALgAECgkJCwAAAA==.Suiféng:BAACLgAFFH8GAAIIAAMJ+giYFADIAAAIAAMJ+giYFADIAAAuAAQKfxQAAggACQmcEa0WAOgBAAgACQmcEa0WAOgBAAAA.Sukuna:BAAALgAECgYJCAAAAA==.Sundance:BAAALgAECgkJEQAAAA==.Sundown:BAAALgADCgEJAQAAAA==.Surmise:BAACLgAFFH8VAAMTAAYJGRwlFAB6AQATAAYJkxslFAB6AQAiAAEJBSMABQBhAAAuAAQKfzMAAxMACQkBJa0FAFYDABMACQkBJa0FAFYDACIABAlVIBkJAAQBAAAA.Sust:BAABLgAFFH8MAAINAAYJGBupEACJAQANAAYJGBupEACJAQABLgAFFAYJFQATABkcAA==.Sustenance:BAABLgAFFH8GAAMnAAIJiRLkEQB7AAAKAAIJiRKA1QCLAAAnAAIJtwzkEQB7AAABLgAFFAYJFQATABkcAA==.',
Sw='Swayzeetrain:BAACLgAFFH8mAAMeAAYJXiVDBAAKAgAeAAYJXiVDBAAKAgACAAEJpAxQMABUAAAuAAQKfxsAAwIACQkCHCxmALQBAAIABwkgGixmALQBAB4ACAn1IOA2AKABAAAA.',
Sy='Sydris:BAAALgAECgkJBQAAAA==.Sylvanic:BAAALgAECgQJBQAAAA==.Syrina:BAAALgADCgEJAQAAAA==.Syrrel:BAAALgADCgYJBgAAAA==.',
['Sü']='Süß:BAAALgAFFAIJAgABLgAFFAQJCQANAL8NAA==.',
Ta='Tabius:BAABLgAECn8mAAMdAAkJXR7/CQAiAgAdAAkJXR7/CQAiAgAJAAMJyw4cYwCOAAAAAA==.Talkingtaco:BAABLgAECn8kAAICAAkJIx0vHwCMAgACAAkJIx0vHwCMAgAAAA==.Taln:BAAALgAECgEJAwABLgAECgkJKgALAL8iAA==.Talìa:BAAALgADCgIJAgABLgAECgEJAQABAAAAAA==.Tareul:BAAALgADCgIJAgAAAA==.Tarn:BAAALgAECgkJEgAAAA==.',
Te='Temok:BAABLgAECn8pAAICAAkJOhHldACEAQACAAkJOhHldACEAQAAAA==.',
Th='Thiccbush:BAAALgAECgEJAQAAAA==.Thiccdiq:BAAALgAECgEJAgAAAA==.Thirielnet:BAAALgAECggJDwAAAA==.This:BAAALgAECgEJAQAAAA==.Thorisdead:BAAALgAECgMJBQABLgAECggJKAASAO8LAA==.Thorkell:BAAALgADCgUJBQAAAA==.Thosen:BAAALgAECgYJEwAAAA==.',
Ti='Tinkaballah:BAAALgAECgcJDgAAAA==.Tipy:BAAALgADCgUJBQAAAA==.',
To='Tore:BAACLgAFFH8ZAAIDAAcJlxr0MQBLAQADAAcJlxr0MQBLAQAuAAQKfzUAAgMACQnsIqcJAPwCAAMACQnsIqcJAPwCAAAA.Totemangge:BAAALgAFFAEJAQAAAA==.Totesmagoat:BAAALgADCgYJBgAAAA==.',
Tr='Trifectas:BAAALgADCgcJGQAAAA==.Trinadel:BAACLgAFFH8WAAIJAAYJVRGuFgBlAQAJAAYJVRGuFgBlAQAuAAQKfycAAgkACQnGId4AAPoCAAkACQnGId4AAPoCAAAA.Träitors:BAAALgADCgcJEwAAAA==.Tråitors:BAABLgAECn8+AAMPAAgJQh99OQD0AQAPAAgJQh99OQD0AQAZAAEJAAA0ZQBFAAABLgADCgcJEwABAAAAAA==.',
Ts='Tsarevich:BAABLgAECn8cAAIiAAkJQgt7BwA1AQAiAAkJQgt7BwA1AQAAAA==.Tshera:BAAALgAECgEJAgABLgAECgkJOAACANUIAA==.',
Tu='Tugtheshaman:BAABLgAECn8dAAIGAAgJoxgmGgBGAgAGAAgJoxgmGgBGAgAAAA==.Tunechii:BAAALgAECgMJBQABLgAECgkJGQANAAkSAA==.',
Tw='Twileaf:BAABLgAECn83AAIgAAkJQQlpYQARAQAgAAkJQQlpYQARAQAAAA==.Twoinchisbig:BAABLgAECn9OAAIlAAkJLRs5CgBPAgAlAAkJLRs5CgBPAgAAAA==.',
Ty='Typhoidmary:BAABLgAECn8XAAMPAAgJhAmIggBVAQAPAAcJhAmIggBVAQAZAAEJAAAOdgAuAAABLgAFFAMJAwABAAAAAA==.',
['Té']='Térror:BAAALgAECgcJDwAAAA==.',
Ug='Ugtales:BAAALgAECgEJAQAAAA==.',
Un='Unbenched:BAAALgADCgQJBQABLgAECgkJOQAFAIAfAA==.Uncool:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Unholyz:BAAALgAECgUJCAAAAA==.Universe:BAAALgAECgEJAQAAAA==.Unstable:BAAALgAECgEJAQAAAA==.',
Ur='Ursoc:BAABLgAECn84AAMJAAkJ9hLNHgDRAQAJAAkJ9hLNHgDRAQAgAAYJRxHRWQAqAQAAAA==.Urteg:BAAALgADCgkJFAAAAA==.',
Ut='Uthmansur:BAAALgAECgEJAgAAAA==.',
Uu='Uub:BAAALgAECgIJAgAAAA==.',
Va='Vairekor:BAAALgAECggJDAABLgAFFAcJJQAPAAkSAA==.Valdria:BAAALgADCgUJBQAAAA==.Vanillaçake:BAAALgAFFAEJAgAAAA==.Vanishja:BAAALgAECgYJDwAAAA==.Varkbyte:BAABLgAECn8XAAIHAAcJbBPiJACdAQAHAAcJbBPiJACdAQAAAA==.Varrik:BAACLgAFFH8fAAMQAAUJVyI9CQBgAQAQAAUJVyI9CQBgAQAoAAMJ7hhbKADLAAAuAAQKfykAAxAACQkeI4oJABUDABAACQkeI4oJABUDACgABgmcG00fAGMBAAAA.',
Ve='Vec:BAAALgAECgYJDQAAAA==.Velamor:BAABLgAECn8YAAQkAAYJzgtQHQCxAAAkAAYJ5gpQHQCxAAAOAAMJygk5VQCTAAANAAMJagrp2QCCAAAAAA==.Velaria:BAAALgADCgcJBwAAAA==.',
Vi='Violynt:BAAALgADCgEJAQAAAA==.',
Vo='Volieu:BAABLgAECn8jAAIiAAkJPRSCAwDnAQAiAAkJPRSCAwDnAQAAAA==.Volklin:BAABLgAECn89AAMGAAkJ6hL5BADyAQAGAAkJ6hL5BADyAQAFAAcJSAtUCgDoAAAAAA==.Voyageurs:BAACLgAFFH8GAAIdAAQJ3xkaDQDmAAAdAAQJ3xkaDQDmAAAuAAQKfx0AAh0ACQmLHS8GAIcCAB0ACQmLHS8GAIcCAAAA.',
Vy='Vyrka:BAAALgAECgMJDQAAAA==.',
Wa='Wallstreet:BAAALgAECgUJBQAAAA==.Warroute:BAAALgAECgUJBQABLgAFFAQJCQANAL8NAA==.Waterdweller:BAAALgAECgEJBAAAAA==.',
We='Wegl:BAABLgAECn8ZAAITAAUJ7xnFHADIAAATAAUJ7xnFHADIAAAAAA==.Werebear:BAAALgADCgMJAwABLgAECggJDQABAAAAAA==.Werewithal:BAAALgAECgYJDgABLgAECgkJKQARALoSAA==.Wesleypipes:BAAALgAECgEJAQAAAA==.Wetfloorsign:BAAALgAECgYJEQAAAA==.',
Wh='Wholeymilk:BAAALgAECgQJCgAAAA==.',
Wi='Wiindsslashh:BAAALgAECgYJBwAAAA==.Wilbur:BAAALgADCgQJBQAAAA==.Windslash:BAAALgAECgIJAgAAAA==.Wish:BAAALgAECgYJCQAAAA==.',
Wo='Wonderx:BAAALgADCgIJAgAAAA==.Wonyoung:BAACLgAFFH8RAAIHAAQJMyRsDACEAQAHAAQJMyRsDACEAQAuAAQKfzIAAgcACQnzI9kBAFgDAAcACQnzI9kBAFgDAAAA.',
Wr='Wraithwok:BAAALgAECgUJBgAAAA==.',
Wu='Wuthrad:BAAALgAECgEJAQAAAA==.',
['Wü']='Würzig:BAABLgAFFH8HAAMKAAUJDAmfgQAEAQAKAAUJDAmfgQAEAQALAAIJ4AO3OABSAAABLgAFFAQJCQANAL8NAA==.',
Xa='Xala:BAABLgAECn8VAAMLAAkJbw0fIgBCAQALAAkJ+QwfIgBCAQAnAAIJ+AdtMABcAAAAAA==.Xalah:BAAALgAECggJEgAAAA==.Xalaz:BAACLgAFFH8XAAMPAAcJTg/lOwBcAQAPAAcJTg/lOwBcAQAZAAEJVwJgGgBGAAAuAAQKfx0AAw8ACQlXHHQ2ADICAA8ACAlXHHQ2ADICABkAAgkLFGNSAHcAAAAA.Xanaris:BAAALgADCgEJAQABLgAFFAIJCgAKAL0mAA==.Xandumbra:BAAALgADCgEJAQAAAA==.Xarosea:BAACLgAFFH8MAAICAAQJPxMQUQANAQACAAQJPxMQUQANAQAuAAQKfyoAAgIABwk6JPYYANMCAAIABwk6JPYYANMCAAAA.',
Xe='Xelienn:BAAALgAECgYJDAAAAA==.Xelojr:BAAALgADCgkJHAAAAA==.',
Xh='Xhael:BAAALgADCgEJAQAAAA==.',
Xi='Xia:BAABLgAECn9CAAIHAAkJqRkzFQA0AgAHAAkJqRkzFQA0AgAAAA==.Xildivh:BAAALgAECgEJAQAAAA==.Xilstorm:BAAALgAECgcJBwAAAA==.',
Xo='Xoilbiis:BAAALgAECgYJBwAAAA==.Xoilcast:BAAALgAECgIJAgAAAA==.Xoilkick:BAABLgAECn8bAAIWAAkJ9BotAQB4AgAWAAkJ9BotAQB4AgAAAA==.Xoilpal:BAAALgAECgQJBAAAAA==.Xoilwings:BAAALgAECgMJBAAAAA==.Xooiill:BAAALgAECggJEQAAAA==.',
Xp='Xpacer:BAAALgAECgcJEwAAAA==.',
['Xê']='Xêna:BAAALgAECgUJDgAAAA==.',
Ye='Yekira:BAAALgADCgEJAgAAAA==.Yellowsnøw:BAACLgAFFH8JAAITAAMJRAcZkQC1AAATAAMJRAcZkQC1AAAuAAQKfz4AAhMACQlNGNcsAGYCABMACQlNGNcsAGYCAAAA.',
Yu='Yumeshade:BAAALgAECgYJCwAAAA==.',
Za='Zaila:BAAALgAECgUJBQAAAA==.Zal:BAEALgAECgYJBgABLgAFFAgJEQAlAMcVAA==.Zamari:BAAALgAECggJEQAAAA==.Zanazer:BAAALgAECgcJBgABLgAECgkJQAAeAIEjAA==.Zanzabar:BAABLgAECn8bAAIdAAkJOxFbBAAJAQAdAAkJOxFbBAAJAQAAAA==.Zathmage:BAAALgADCgMJAwAAAA==.Zaxin:BAABLgAECn8XAAMHAAkJDQ4UJwCNAQAHAAkJDQ4UJwCNAQAUAAUJiAQeSwCtAAAAAA==.',
Ze='Zelfie:BAAALgADCgUJBQAAAA==.Zellda:BAAALgAECgYJCQAAAA==.Zerodarkness:BAAALgADCgkJCQAAAA==.Zeros:BAABLgAECn8XAAITAAkJeBgZPAApAgATAAkJeBgZPAApAgAAAA==.',
Zi='Ziperz:BAAALgAECggJCAAAAA==.',
Zo='Zoerina:BAAALgAECgcJDwAAAA==.Zoobilong:BAABLgAECn8XAAICAAcJKRAfuwAQAQACAAcJKRAfuwAQAQAAAA==.',
Zx='Zxak:BAABLgAECn9AAAIOAAkJaSagAABHAwAOAAkJaSagAABHAwAAAA==.',
Zy='Zyahk:BAAALgADCgQJBQAAAA==.Zynn:BAAALgAECgEJAgAAAA==.',
['Zë']='Zën:BAAALgAECgcJDAABLgAFFAYJFgAfAPUKAA==.',
['Ða']='Ðashÿ:BAAALgAECgMJAwABLgAECggJGAAHAPEfAA==.',
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
