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
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abandonhope:BAAALgAECgMJAwABLgAECgkJDwABAAAAAA==.',
Ac='Accuser:BAAALgADCgEJAQAAAA==.Acky:BAAALgADCgUJBQAAAA==.',
Ad='Adwen:BAABLgAECn8XAAICAAYJ+xlyiABEAQACAAYJ+xlyiABEAQAAAA==.',
Ae='Aenimal:BAAALgAECgYJEAAAAA==.Aer:BAAALgADCgkJCQAAAA==.Aeronemon:BAAALgAECgEJAgAAAA==.',
Ai='Airill:BAAALgADCgQJBQAAAA==.',
Ak='Akforty:BAABLgAECn8fAAMDAAkJIiHNCgDvAgADAAkJIiHNCgDvAgAEAAIJoBV7eABfAAAAAA==.Akittymeow:BAABLgAECn8bAAMFAAkJuw/cPgAcAQAFAAgJKQ/cPgAcAQAGAAMJiwWEmAB2AAAAAA==.',
Al='Aldredevon:BAAALgAECgEJAQAAAA==.Aleshock:BAAALgAECgkJEQAAAA==.Alidar:BAAALgAECgcJEwAAAA==.Alphaboner:BAAALgADCgYJBwAAAA==.Altairis:BAAALgAECgEJAgAAAA==.Altartoy:BAABLgAECn8hAAIHAAgJ6QqfMQAtAQAHAAgJ6QqfMQAtAQAAAA==.Althunter:BAACLgAFFH8NAAIEAAQJUiHKCwBwAQAEAAQJUiHKCwBwAQAuAAQKfxsAAgQACAneIcwFACwCAAQACAneIcwFACwCAAAA.',
Am='Amanita:BAAALgAECgQJBAABLgAECggJEAABAAAAAA==.Amelina:BAAALgAECgYJDgAAAA==.Amerit:BAAALgAECgEJAQAAAA==.Amorir:BAACLgAFFH8KAAICAAQJSwMkUwDmAAACAAQJSwMkUwDmAAAuAAQKf0cAAgIACQnsEs1PAMABAAIACQnsEs1PAMABAAAA.Amorit:BAAALgAECgYJDgAAAA==.Amorydalias:BAAALgAECgUJBgAAAA==.Amozon:BAAALgADCgEJAQAAAA==.',
An='Anamortem:BAAALgAECgMJAwABLgAECgkJIQAIAAcZAA==.Anastala:BAABLgAECn8rAAIJAAkJ5RVHFgAGAgAJAAkJ5RVHFgAGAgAAAA==.Andeddo:BAAALgAECgkJCQAAAA==.Angchu:BAAALgADCgQJBAAAAA==.Angelmàker:BAAALgAECgMJBAABLgADCgcJEwABAAAAAA==.Angelmäker:BAAALgAECgQJBQABLgADCgcJEwABAAAAAA==.Annesta:BAABLgAECn8hAAMIAAkJBxlsFQDcAQAIAAkJ0hhsFQDcAQAKAAEJ9xYeIgA9AAAAAA==.',
Ap='Apostus:BAAALgADCgcJDgAAAA==.Apothica:BAAALgAECgUJBgAAAA==.',
Aq='Aquafox:BAABLgAECn8eAAMGAAgJWCBuDQDUAgAGAAgJWCBuDQDUAgAFAAMJYxDZZgCTAAAAAA==.',
Ar='Archontas:BAABLgAECn8kAAIJAAgJkSF3CQCoAgAJAAgJkSF3CQCoAgAAAA==.Ariodh:BAABLgAECn86AAMLAAkJLSbmAQBhAwALAAkJLSbmAQBhAwAMAAUJpB9eJACaAQAAAA==.Arkaline:BAAALgAECgEJAQAAAA==.Artuarry:BAACLgAFFH8gAAINAAYJvRIOJQCCAQANAAYJvRIOJQCCAQAuAAQKfyYAAg0ACQlGHyobAHMCAA0ACQlGHyobAHMCAAAA.Aryndus:BAABLgAECn8lAAICAAkJcx6QFwCfAgACAAkJcx6QFwCfAgAAAA==.',
At='Athenà:BAAALgAECgUJBQAAAA==.',
Av='Avocado:BAABLgAECn8jAAMDAAkJnCW1CgDtAgADAAkJHiO1CgDtAgAEAAcJVCI2CgC0AQAAAA==.',
Ax='Axelaw:BAAALgADCgQJBAAAAA==.',
Ay='Ayrz:BAAALgAECgIJAgAAAA==.',
Az='Azaria:BAAALgADCgIJAgAAAA==.',
Ba='Baddjujumon:BAABLgAECn8XAAMFAAgJ0gQITgDhAAAFAAgJ0gQITgDhAAAGAAEJoAHj2AAdAAAAAA==.Baileyhowl:BAAALgAECgEJBQAAAA==.Bammie:BAAALgADCgYJCgAAAA==.Bananuth:BAAALgAECgIJAwABLgAFFAYJHwAOAJ4eAA==.Banthr:BAABLgAECn8UAAIPAAkJDw5yKQCeAQAPAAkJDw5yKQCeAQAAAA==.Barkert:BAAALgADCgEJAQAAAA==.Baroke:BAAALgAECgMJBwABLgAECggJIQAHAOkKAA==.Barokoshama:BAAALgAECgcJEQAAAA==.Basaltytaco:BAAALgADCgEJAQAAAA==.Battleworm:BAAALgADCgkJEwABLgAFFAMJAwABAAAAAA==.',
Bb='Bbalrd:BAABLgAECn8XAAIOAAkJohdCRADiAQAOAAkJohdCRADiAQAAAA==.',
Be='Bearglie:BAAALgAECggJDgAAAA==.Beepers:BAAALgAECgYJBgAAAA==.Beezelpup:BAAALgAECgYJCAAAAA==.',
Bi='Bigcow:BAAALgAECgUJCQAAAA==.',
Bl='Blackolives:BAAALgAECgcJDAAAAA==.Bladesp:BAAALgAECgYJBwABLgAECgkJGQALAAkSAA==.Blondefu:BAAALgAECgUJCwAAAA==.Bloodybonne:BAAALgADCgcJBwAAAA==.Bloodyell:BAAALgAECgEJAQAAAA==.Bloore:BAAALgAECgMJAwABLgAECgkJLAAEAG0iAA==.Bluejuly:BAAALgAECgUJBQAAAA==.Blutø:BAAALgAECgYJDAAAAA==.',
Bo='Boflex:BAAALgADCgQJBgAAAA==.Bomboclat:BAAALgAECgUJCwAAAA==.Bonesknows:BAAALgADCgEJAQAAAA==.Boofy:BAAALgAECgMJAwABLgAECgkJFgANANwWAA==.Borhoag:BAAALgADCgEJAQABLgAECggJCwABAAAAAA==.Bowwie:BAACLgAFFH8PAAMQAAQJEBKpFAAYAQAQAAQJDwupFAAYAQADAAMJZRCVVwDKAAAuAAQKfysABAMACQmNHy0GACsDAAMACQkTHi0GACsDABAACAkPGMYUAPIBAAQAAQkVAxWTACcAAAAA.',
Br='Britney:BAAALgADCgkJCQAAAA==.Bronzé:BAABLgAECn8wAAIRAAcJfyFLNQArAgARAAcJfyFLNQArAgAAAA==.Brotherfrey:BAAALgAECgYJCgAAAA==.Bruish:BAABLgAFFH8MAAISAAQJtwzFDQAWAQASAAQJtwzFDQAWAQAAAA==.',
Bu='Bubbadoo:BAABLgAECn8jAAIJAAgJhhBWJwB6AQAJAAgJhhBWJwB6AQAAAA==.Buddy:BAABLgAECn8ZAAITAAYJoRLKMwAoAQATAAYJoRLKMwAoAQABLgAECggJJgAUAHMhAA==.Bulan:BAABLgAECn8+AAIVAAkJhSRiAgCUAwAVAAkJhSRiAgCUAwAAAA==.',
Bw='Bweninger:BAAALgAECgEJAQAAAA==.',
['Bô']='Bôôsted:BAABLgAECn8dAAIFAAkJ0hTfIAAIAgAFAAkJ0hTfIAAIAgAAAA==.',
Ca='Caistan:BAAALgADCgYJCAAAAA==.Calyopi:BAAALgAFFAIJAgAAAA==.Candypants:BAABLgAECn8iAAQVAAkJuxUwGgAgAgAVAAkJuxUwGgAgAgASAAcJ9A7FNwANAQAWAAMJ2AvZXQCFAAAAAA==.Caoth:BAAALgAECgYJEwAAAA==.Cappilon:BAABLgAECn8XAAIRAAgJiyHpLABPAgARAAgJiyHpLABPAgAAAA==.Carcus:BAAALgAECggJDQAAAA==.Cayleedah:BAABLgAECn8mAAIEAAgJxQdQEwASAQAEAAgJxQdQEwASAQAAAA==.Cayssaris:BAAALgAECgYJEwAAAA==.',
Cc='Cc:BAABLgAECn8WAAQXAAYJPBPsDgBCAQAXAAUJ9BPsDgBCAQAYAAYJKwstIwA+AQANAAQJzhP5tQDtAAAAAA==.',
Ce='Ceeti:BAABLgAECn84AAMZAAkJICGEBwDJAgAZAAkJICGEBwDJAgAaAAIJeAYcQABpAAAAAA==.Celandrelia:BAAALgAECgUJBQABLgAECggJLAAbAEQXAA==.',
Ch='Chaewon:BAAALgAECgYJCgABLgAFFAQJEQAHADMkAA==.Channeria:BAAALgAECgEJAQAAAA==.Chaoticoreo:BAABLgAECn8xAAMMAAkJOh4KCACTAgAMAAkJOh4KCACTAgALAAQJ4w9rrQCzAAAAAA==.Chappedlips:BAAALgAECgkJBwAAAA==.Chareyne:BAABLgAECn8ZAAIHAAgJ5RFyJgC5AQAHAAgJ5RFyJgC5AQAAAA==.Cheetor:BAAALgAECgMJAwABLgAFFAQJCgAQANQUAA==.Cheezytaco:BAAALgAECgYJDgABLgAECgkJIwACANccAA==.Chidge:BAAALgADCggJCwAAAA==.Chikila:BAABLgAECn8jAAMYAAgJBhkrBgDlAQAYAAgJBhkrBgDlAQANAAMJeAwF0gCfAAAAAA==.Chilliflakez:BAABLgAECn8VAAIVAAYJNQ0QTgD+AAAVAAYJNQ0QTgD+AAAAAA==.Chro:BAAALgAECgcJBwABLgAECgkJMQAFANIeAA==.',
Ci='Cindezar:BAAALgADCgMJAwAAAA==.',
Cl='Clementyn:BAABLgAECn8WAAICAAcJOBCwugDyAAACAAcJOBCwugDyAAAAAA==.Cleyi:BAABLgAECn8pAAIHAAgJxQ1QLABRAQAHAAgJxQ1QLABRAQAAAA==.',
Co='Coldpasta:BAAALgAECgYJDgABLgAFFAIJBAABAAAAAA==.Colonoscopy:BAAALgAECgMJBAAAAA==.Coreyy:BAAALgADCgUJBwAAAA==.Corva:BAACLgAFFH8TAAINAAQJKxIdRwAmAQANAAQJKxIdRwAmAQAuAAQKfyoAAg0ACQnpFS87AOEBAA0ACQnpFS87AOEBAAAA.Cosairi:BAAALgAECgYJEwAAAA==.Cougztroll:BAABLgAECn83AAMcAAkJlRXIDwDJAQAcAAkJlRXIDwDJAQAdAAYJ/gvHIQDTAAAAAA==.',
Cr='Crazaki:BAAALgADCgEJAQAAAA==.Crosseye:BAAALgADCgEJAQAAAA==.',
Ct='Ctd:BAAALgADCgkJCQABLgAECgkJOAAZACAhAA==.',
Cu='Curfluffin:BAAALgADCgEJAQAAAA==.Cuttercupx:BAAALgAECgIJAgABLgAECgkJDwABAAAAAA==.',
Da='Dahn:BAAALgAECgIJAgAAAA==.Dakadin:BAABLgAECn8mAAMeAAkJ+yN9EAB/AgAeAAkJ+yN9EAB/AgACAAQJ7hcAxgDiAAAAAA==.Daranne:BAACLgAFFH8SAAICAAQJgxRFMwAtAQACAAQJgxRFMwAtAQAuAAQKfykAAgIACQnwGhc/ACkCAAIACQnwGhc/ACkCAAAA.Darkenedstar:BAAALgAECgYJCgABLgAECgYJEAABAAAAAA==.Darksoulstwo:BAAALgADCgMJAwAAAA==.Dasbeans:BAABLgAECn8XAAMZAAkJOghDRgDuAAAZAAgJIAlDRgDuAAAbAAIJkgHvRgARAAAAAA==.Dashy:BAABLgAECn8WAAMHAAgJ8R8xEQBCAgAHAAgJVBoxEQBCAgAfAAYJ4B69EwAiAgAAAA==.Datran:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.',
De='Deaduglie:BAABLgAECn84AAMNAAkJbBYRMAAMAgANAAkJbBYRMAAMAgAYAAEJMQjvcQA0AAAAAA==.Deliandora:BAAALgAECgQJCAAAAA==.Delusional:BAAALgAECgcJDwAAAA==.Delynique:BAAALgADCgEJAQABLgAECgkJLAAEAG0iAA==.Demonx:BAAALgAECgEJAQAAAA==.Denaric:BAABLgAECn8WAAMgAAYJdxpAMgDCAQAgAAYJdxpAMgDCAQAJAAUJ6QgQWQCSAAABLgAECgcJEAABAAAAAA==.Dergen:BAAALgAECgIJAgABLgAECgkJDwABAAAAAA==.Destroyevsky:BAABLgAECn8gAAIPAAYJSwJZdAB2AAAPAAYJSwJZdAB2AAAAAA==.Detonate:BAABLgAECn8ZAAIRAAYJbhz1cgB5AQARAAYJbhz1cgB5AQAAAA==.',
Dh='Dhvecx:BAAALgAECgUJBgABLgAECgYJDQABAAAAAA==.',
Di='Dilbo:BAAALgAFFAIJAgABLgAFFAYJIAAJAPAaAA==.Diomed:BAAALgAECgEJAQAAAA==.Diqoff:BAAALgADCgkJCQAAAA==.Diqon:BAABLgAECn84AAMOAAkJDRsELgA0AgAOAAkJDRsELgA0AgAUAAcJtxSQHwA+AQAAAA==.Disturbedtwo:BAAALgAECgYJCgAAAA==.',
Do='Dolphinz:BAACLgAFFH8TAAICAAQJ4RWKKwA/AQACAAQJ4RWKKwA/AQAuAAQKfy8AAwIACAmqIU8YANcCAAIACAmqIU8YANcCACEAAgnpCiI8AE4AAAAA.Doryadni:BAAALgADCgcJBgAAAA==.',
Dr='Dragonpede:BAABLgAECn85AAIZAAkJFiDYCACzAgAZAAkJFiDYCACzAgAAAA==.Dragonwarior:BAABLgAECn8fAAIPAAkJ6huaJwCpAQAPAAkJ6huaJwCpAQAAAA==.Drakindees:BAAALgAECgUJBQABLgAECgcJJAARAPYhAA==.Drakkyn:BAABLgAECn8aAAIPAAYJTR06KwCUAQAPAAYJTR06KwCUAQAAAA==.Drakonus:BAAALgAECgUJCQAAAA==.Dread:BAAALgADCgQJBAAAAA==.Drosuu:BAAALgAECgEJAQAAAA==.Druish:BAACLgAFFH8kAAIcAAYJ4SSCAQAhAgAcAAYJ4SSCAQAhAgAuAAQKfywAAxwACQk0JnYAAHIDABwACQk0JnYAAHIDAB0AAgkOD5ksAGEAAAAA.Drykkr:BAABLgAECn8mAAISAAkJnBYRFwDfAQASAAkJnBYRFwDfAQAAAA==.',
Du='Dullahan:BAAALgAECgUJBgAAAA==.Dunstie:BAAALgADCgEJAQABLgAECgYJGQAUAGkfAA==.Durrik:BAAALgADCgcJBwAAAA==.',
['Dà']='Dàsh:BAAALgAECgYJBgABLgAECggJFgAHAPEfAA==.',
Ea='Eatrocks:BAAALgADCggJCAAAAA==.',
Ed='Edorn:BAAALgAECgUJBQAAAA==.',
Ef='Efn:BAAALgAECgYJEwAAAA==.',
El='Elcrys:BAABLgAECn8aAAIgAAcJ3BYcMwC+AQAgAAcJ3BYcMwC+AQAAAA==.Elentiya:BAAALgAECgQJBAAAAA==.Elion:BAAALgAECgEJAQAAAA==.Ellyra:BAAALgAFFAIJAgAAAA==.Elpollo:BAABLgAECn8kAAMRAAcJ9iGUQgBwAgARAAcJ9iGUQgBwAgAiAAEJshe1HAA6AAAAAA==.Elsinn:BAAALgADCgUJBgAAAA==.Elvar:BAAALgAECgQJEAAAAA==.',
Em='Emmdwemm:BAAALgAECgQJCAAAAA==.',
En='Enoki:BAAALgAECgQJBAAAAA==.',
Ep='Ephelia:BAACLgAFFH8RAAIGAAQJ+SKyFQCIAQAGAAQJ+SKyFQCIAQAuAAQKfxkAAwYACQlfGooiAA8CAAYACQlfGooiAA8CAAUAAQmMA/eUACAAAAAA.Epitome:BAABLgAECn8mAAIRAAkJeBZ1OAAgAgARAAkJeBZ1OAAgAgAAAA==.',
Er='Erid:BAAALgAECgcJEQAAAA==.',
Et='Etude:BAAALgADCgEJAQAAAA==.',
Ev='Evelyndel:BAAALgAECgYJBwAAAA==.Evergrey:BAABLgAECn8ZAAITAAcJsAx5NQAeAQATAAcJsAx5NQAeAQAAAA==.Evermoons:BAABLgAECn8jAAIgAAkJVxkQFACXAgAgAAkJVxkQFACXAgAAAA==.Evodaka:BAAALgAECgIJAwAAAA==.',
Fa='Falaria:BAAALgAECgQJBAAAAA==.Falasdaer:BAABLgAECn8dAAILAAgJLyIdEwCWAgALAAgJLyIdEwCWAgAAAA==.Fallansting:BAAALgAECgkJEgAAAA==.Falstaff:BAABLgAECn8fAAISAAkJxhWcFAD4AQASAAkJxhWcFAD4AQAAAA==.Fartshooter:BAAALgAECgYJEQAAAA==.Fatterblunt:BAACLgAFFH8gAAIJAAYJ8BrvCgCoAQAJAAYJ8BrvCgCoAQAuAAQKfyYAAgkACQk3ILYNAMACAAkACQk3ILYNAMACAAAA.',
Fe='Fedner:BAABLgAECn8XAAIGAAcJSQ8cUABTAQAGAAcJSQ8cUABTAQAAAA==.Feldar:BAABLgAECn8yAAICAAkJyiBaDwDVAgACAAkJyiBaDwDVAgAAAA==.Fend:BAAALgADCgQJBAAAAA==.Feronite:BAAALgAECgUJBQABLgAFFAQJDwAQABASAA==.Feyredarling:BAAALgAECgMJAwAAAA==.',
Fi='Fists:BAACLgAFFH8MAAISAAQJgBzKGwAtAQASAAQJgBzKGwAtAQAuAAQKfyoAAxIABgmEI44WAFQCABIABgmEI44WAFQCABYABAk3EqtUAL4AAAAA.Fizzbeard:BAAALgADCgcJCgAAAA==.Fizzical:BAAALgADCgkJDwAAAA==.Fizzleclaw:BAABLgAECn8XAAMcAAYJDxyVFACOAQAcAAYJDxyVFACOAQAJAAIJkw2sZwBiAAAAAA==.Fizzleded:BAAALgAECgQJBQABLgAECgYJFwAcAA8cAA==.Fizzleflare:BAAALgADCgkJCQAAAA==.',
Fl='Flightrisk:BAAALgAECgQJBgABLgAECgkJDwABAAAAAA==.Florisa:BAABLgAECn8jAAICAAgJ5RxxOgABAgACAAgJ5RxxOgABAgAAAA==.',
Fo='Fool:BAAALgAECgUJBQABLgAFFAMJAwABAAAAAA==.Fordi:BAABLgAECn8xAAMFAAkJ0h49CgCmAgAFAAkJ0h49CgCmAgAjAAMJ9RS+LgBRAAAAAA==.Forendor:BAAALgAECgIJAwAAAA==.Fourdy:BAABLgAECn8wAAIGAAcJCRk1OQCvAQAGAAcJCRk1OQCvAQAAAA==.',
Fr='Fragdoll:BAAALgAECgQJCgAAAA==.Freakinlarry:BAAALgADCgEJAQAAAA==.Freakinoak:BAABLgAECn8lAAIgAAkJthGfKQD0AQAgAAkJthGfKQD0AQAAAA==.Free:BAABLgAECn8ZAAMLAAkJCRL4OwDAAQALAAgJCRL4OwDAAQAkAAUJ9Ap3IACAAAAAAA==.Frenn:BAAALgAECgIJAgAAAA==.Froost:BAACLgAFFH8LAAIOAAQJJheeVQAsAQAOAAQJJheeVQAsAQAuAAQKfxgAAg4ACQlfHvRMAAwCAA4ACQlfHvRMAAwCAAAA.',
Fu='Funkflex:BAAALgAECgEJAQABLgAECgkJGQALAAkSAA==.Furvert:BAAALgAECgkJDwAAAA==.Fushi:BAAALgAECgEJAQAAAA==.',
Ga='Gandis:BAAALgAECgkJEgAAAA==.Gapper:BAACLgAFFH8KAAIQAAQJ1BRbDwBBAQAQAAQJ1BRbDwBBAQAuAAQKf0wAAhAACQmLJdEAAGIDABAACQmLJdEAAGIDAAAA.Gargodath:BAAALgAECgMJAwAAAA==.',
Gi='Gielinor:BAAALgADCgIJAgAAAA==.Gimbó:BAAALgADCgQJBgAAAA==.',
Gl='Glamour:BAAALgADCgEJAgAAAA==.Glestaar:BAABLgAECn8pAAMDAAgJnxzmKAAkAgADAAgJnxzmKAAkAgAEAAIJRQuFfABSAAAAAA==.Glyr:BAAALgAECgYJCgAAAA==.',
Go='Goingrouge:BAAALgAECgYJCgAAAA==.Goldabelle:BAAALgAECgYJCgAAAA==.Goonkin:BAAALgAECgUJBQABLgAFFAQJCgAQANQUAA==.Gorlami:BAABLgAFFH8GAAICAAMJZA4EaQC1AAACAAMJZA4EaQC1AAAAAA==.Gothelf:BAAALgAFFAIJBAAAAA==.Gothri:BAAALgAECgcJCQABLgAECgcJFQAZAJAVAA==.Gothstraza:BAABLgAECn8VAAIZAAcJkBXrMwBBAQAZAAcJkBXrMwBBAQAAAA==.Gottemgood:BAAALgADCgUJBQAAAA==.',
Gr='Grimli:BAABLgAECn8fAAIGAAkJsQ79PwCRAQAGAAkJsQ79PwCRAQAAAA==.Growth:BAABLgAECn8ZAAMTAAkJNAmZKgBeAQATAAkJNAmZKgBeAQAfAAYJohA7MQAyAQAAAA==.',
Gu='Gurthcaptian:BAAALgAECgQJBAAAAA==.',
Gy='Gyatso:BAAALgADCgMJAwAAAA==.',
['Gá']='Gárròsh:BAAALgAECgYJBgAAAA==.',
Ha='Haerin:BAAALgAECgIJAgABLgAFFAQJEQAHADMkAA==.Happykilmøre:BAAALgAECgQJBAABLgAECgkJEgABAAAAAA==.Harnel:BAABLgAECn8rAAICAAgJXwNc3wDAAAACAAgJXwNc3wDAAAAAAA==.Haseo:BAAALgAECggJCwAAAA==.Hattorihanzo:BAAALgAECgYJDAAAAA==.',
He='Healeymonstr:BAAALgADCgIJAgAAAA==.Healmart:BAABLgAECn8VAAIfAAYJZAdLQADeAAAfAAYJZAdLQADeAAAAAA==.Heartëater:BAAALgADCgYJBgAAAA==.Hellinyoface:BAAALgADCgUJBQAAAA==.Heymage:BAAALgADCgkJCQAAAA==.',
Hi='Himothyy:BAAALgAECgQJBAAAAA==.',
Ho='Holypeetch:BAAALgADCgYJBgAAAA==.Hoofpics:BAAALgAECgQJBAAAAA==.Hordedefect:BAAALgAECgEJAQABLgAECgkJDwABAAAAAA==.Hoyer:BAAALgAECgkJEwAAAA==.',
Hu='Hulkhogan:BAAALgAECgcJBwAAAA==.Humbledrink:BAAALgAECgQJBQAAAA==.',
Im='Impact:BAAALgADCgcJCgAAAA==.',
In='Inflícted:BAABLgAFFH8IAAIfAAQJRQVRJQDuAAAfAAQJRQVRJQDuAAAAAA==.Innoscent:BAAALgAECgYJBgAAAA==.Inzo:BAAALgAFFAEJAgAAAA==.',
Io='Iove:BAABLgAECn8aAAIVAAkJZBV8HAAOAgAVAAkJZBV8HAAOAgAAAA==.',
Ja='Jahsahm:BAAALgAECgcJEQAAAA==.Jajung:BAAALgADCgMJAwAAAA==.Jakub:BAABLgAECn8hAAIUAAkJqRdBDAAuAgAUAAkJqRdBDAAuAgABLgAFFAQJDwAQABASAA==.Jakuren:BAAALgADCgYJBgAAAA==.Jamjam:BAAALgADCgYJCQAAAA==.',
Je='Jesit:BAABLgAECn8aAAIaAAYJ8hWpEwB8AQAaAAYJ8hWpEwB8AQAAAA==.',
Jh='Jhonn:BAAALgAECgEJAQABLgAECgkJRgAlAL8iAA==.',
Ji='Jingles:BAAALgADCgYJBgAAAA==.',
Jj='Jjada:BAACLgAFFH8HAAMLAAQJtQvfRgD5AAALAAQJIQrfRgD5AAAkAAEJdBUmDgA/AAAuAAQKfxsAAwsACAk1I8gWAHoCAAsACAm0IcgWAHoCACQABgmeIYAFAE0CAAAA.',
Jo='Johnwolf:BAABLgAECn8UAAICAAYJ3gLhBgGOAAACAAYJ3gLhBgGOAAAAAA==.',
Jy='Jyade:BAABLgAECn8yAAMKAAkJhQ46BwDVAQAKAAkJhQ46BwDVAQAmAAUJnwifCAD6AAAAAA==.Jynoria:BAAALgADCgcJDAAAAA==.',
Ka='Kainlok:BAAALgADCgIJAgAAAA==.Kaiserice:BAAALgAECgcJEAAAAA==.Kamarra:BAABLgAECn8dAAIZAAcJOwe6TgDNAAAZAAcJOwe6TgDNAAAAAA==.Kamencider:BAABLgAECn8dAAIRAAcJ8RCyiwBFAQARAAcJ8RCyiwBFAQAAAA==.Kamidala:BAAALgAECgIJAgAAAA==.Kankles:BAACLgAFFH8FAAIJAAQJ3x6WFABJAQAJAAQJ3x6WFABJAQAuAAQKfyoAAgkACAnuIr4JAKMCAAkACAnuIr4JAKMCAAAA.Karva:BAAALgAECgIJAwAAAA==.Katabetta:BAAALgADCgMJAwAAAA==.',
Ke='Kellmagnison:BAAALgAECgIJAgABLgAECggJLQACAP8GAA==.Kentukee:BAAALgADCggJCwABLgAECgkJJwAQAC0SAA==.Kernelpanic:BAACLgAFFH8fAAMOAAYJnh7CFwDZAQAOAAYJnh7CFwDZAQAnAAEJ/gXbIAA7AAAuAAQKfycAAg4ACQkCItgnAE8CAA4ACQkCItgnAE8CAAAA.Kessho:BAAALgAECgYJDwABLgAFFAQJDwAQABASAA==.Kevynn:BAAALgADCgMJAgAAAA==.Keyoshi:BAAALgAECgYJBgAAAA==.',
Ki='Kickrocks:BAAALgAECgEJAQAAAA==.Kilerforlife:BAAALgAECgYJCwAAAA==.Kilowog:BAAALgADCgUJCAAAAA==.Kilpally:BAAALgAECgYJBwAAAA==.Kintra:BAAALgADCgIJAgAAAA==.Kirin:BAAALgADCgEJAQAAAA==.Kirkle:BAABLgAECn86AAIYAAkJCx32AQCbAgAYAAkJCx32AQCbAgAAAA==.Kithara:BAAALgAECgEJAwAAAA==.',
Ko='Kovie:BAAALgADCggJCAAAAA==.Kovy:BAABLgAECn8VAAMUAAkJ8RZ6FADJAQAUAAkJ8RZ6FADJAQAOAAEJCQQKJQEvAAAAAA==.Kovya:BAAALgADCgYJBwAAAA==.',
Kr='Krelel:BAAALgADCgIJAgAAAA==.Krukar:BAAALgADCgYJDAAAAA==.',
Ku='Kubo:BAAALgAECgYJBgABLgAFFAQJDwAQABASAA==.',
Ky='Kydroga:BAAALgAECgYJEAAAAA==.Kynaria:BAAALgAECgEJAQAAAA==.Kynsia:BAAALgADCgQJBgAAAA==.',
La='Lamörak:BAABLgAECn8yAAICAAkJsSHQCgD8AgACAAkJsSHQCgD8AgAAAA==.Landrick:BAABLgAECn80AAIOAAkJcxo9KABNAgAOAAkJcxo9KABNAgAAAA==.Lastotem:BAAALgADCgEJAQAAAA==.Lastshot:BAAALgAECggJEAAAAA==.Latest:BAAALgADCgQJBAAAAA==.Lavaevoker:BAAALgADCgcJBwABLgAECggJIwASAJwHAA==.Lavanor:BAAALgADCgIJAgAAAA==.Lavasaurus:BAABLgAECn8iAAQaAAgJkhrtEQCXAQAaAAYJUxrtEQCXAQAZAAgJSA8HKwB3AQAbAAEJDRMkIQA7AAAAAA==.',
Le='Leafstorm:BAAALgAECgYJDwAAAA==.Lehala:BAAALgADCgQJBAAAAA==.Lektar:BAAALgAECgUJBQABLgAECgYJEwABAAAAAA==.Leloosh:BAAALgADCgkJDAABLgAFFAIJBAABAAAAAA==.Lemon:BAABLgAECn8iAAIYAAgJbgqoEQASAQAYAAgJbgqoEQASAQAAAA==.Leokenoso:BAABLgAECn8hAAIkAAkJCxIBCQDGAQAkAAkJCxIBCQDGAQAAAA==.Lesclaypool:BAAALgAECgcJCQAAAA==.Lessalia:BAAALgAECgEJAQAAAA==.Lewd:BAAALgAECgQJBgAAAA==.Lexen:BAAALgADCgEJAQAAAA==.Lexor:BAAALgADCgQJBAAAAA==.',
Li='Lifebloomz:BAABLgAECn8uAAIgAAkJpwyBPACPAQAgAAkJpwyBPACPAQAAAA==.Lifesabeach:BAAALgAECgMJAwAAAA==.Lilfluffcc:BAAALgAECgQJBAAAAA==.Lissana:BAAALgADCgUJBQAAAA==.',
Lo='Lockward:BAAALgAECgIJAwAAAA==.Loidvoid:BAAALgADCgkJEQAAAA==.Lorblor:BAABLgAECn8iAAIkAAkJbB6hAgC5AgAkAAkJbB6hAgC5AgAAAA==.Lorerun:BAAALgADCgUJCAAAAA==.Lowang:BAABLgAECn8dAAISAAkJnRO8JAB0AQASAAkJnRO8JAB0AQAAAA==.Lowmein:BAABLgAECn8UAAIGAAgJMR4lKgDlAQAGAAgJMR4lKgDlAQAAAA==.',
Lu='Lucÿfer:BAAALgAFFAIJAwAAAA==.Lumie:BAAALgAECgYJEQAAAA==.Luminisx:BAAALgADCgMJAwAAAA==.Lunafox:BAABLgAECn8kAAIGAAgJOh7VEgCdAgAGAAgJOh7VEgCdAgAAAA==.Lunamae:BAABLgAECn8mAAIiAAgJZxcdAwDsAQAiAAgJZxcdAwDsAQAAAA==.Lupacho:BAAALgAFFAIJAgAAAA==.Luvvyyaa:BAABLgAECn9IAAMHAAkJwiCxCADAAgAHAAkJ+h2xCADAAgAfAAkJpRfFDQBzAgAAAA==.Luvyya:BAAALgAECgYJEAABLgAECgkJSAAHAMIgAA==.Luvyyaa:BAAALgAECgQJBQABLgAECgkJSAAHAMIgAA==.',
Ly='Lyrinaku:BAABLgAECn8UAAIHAAcJWRVQNgBkAQAHAAcJWRVQNgBkAQAAAA==.Lythomancer:BAABLgAECn8fAAIYAAgJiQ/bDgA3AQAYAAgJiQ/bDgA3AQAAAA==.',
Ma='Maddeena:BAABLgAECn8bAAIGAAYJnQfYdADdAAAGAAYJnQfYdADdAAAAAA==.Maddy:BAABLgAECn8iAAMWAAkJWBqHEgAXAgAWAAgJYh2HEgAXAgASAAkJexAfGADVAQAAAA==.Maelyssa:BAAALgADCgMJAwAAAA==.Magicmangge:BAAALgADCgYJBgABLgAFFAEJAQABAAAAAA==.Makeitclap:BAAALgAECgMJBAABLgAECgcJHQARAPEQAA==.Malidian:BAABLgAECn8dAAILAAkJdw9oTQCGAQALAAkJdw9oTQCGAQAAAA==.Matchadaddy:BAAALgAECgEJAwAAAA==.Maxohlx:BAACLgAFFH8UAAINAAYJ7A2yLABoAQANAAYJ7A2yLABoAQAuAAQKfzgAAg0ACQnHHGoOAMwCAA0ACQnHHGoOAMwCAAAA.',
Mc='Mcmercie:BAAALgAECgkJCgAAAA==.',
Me='Mechacooter:BAAALgAFFAMJAwAAAA==.Meeko:BAAALgADCgUJBQABLgAFFAgJGwAaAPggAA==.Megahertz:BAAALgADCgEJAQAAAA==.Megg:BAAALgADCggJEQAAAA==.Meilia:BAAALgADCgUJBwAAAA==.Mekari:BAABLgAECn8wAAIQAAkJxR2JCACJAgAQAAkJxR2JCACJAgAAAA==.Melchiorr:BAABLgAECn8mAAIXAAgJ3RyDBgDyAQAXAAgJ3RyDBgDyAQAAAA==.Melignant:BAAALgADCgEJAQAAAA==.Melosia:BAAALgADCgQJBwAAAA==.Melynne:BAABLgAECn9FAAMGAAkJBxUKIQAvAgAGAAkJBxUKIQAvAgAFAAIJeATEgQBBAAAAAA==.Memmel:BAAALgADCgMJAwAAAA==.Meredeath:BAABLgAECn8UAAIJAAgJKg3aPgD3AAAJAAgJKg3aPgD3AAAAAA==.',
Mi='Micro:BAAALgAECgkJEwAAAA==.Microkeg:BAAALgAECgcJBAAAAA==.Microslash:BAAALgADCgMJAwABLgAECgkJEwABAAAAAA==.Minsoo:BAABLgAECn8bAAIVAAgJex4PEQB4AgAVAAgJex4PEQB4AgAAAA==.Mistblade:BAAALgAECgQJCwABLgAECgkJGQALAAkSAA==.Miststriker:BAAALgAECgUJCQAAAA==.Mistytaco:BAAALgAECgEJAQAAAA==.',
Ml='Mlrglett:BAABLgAECn86AAMcAAgJACIcBQChAgAcAAgJACIcBQChAgAJAAEJihMfhgAqAAAAAA==.Mlrglo:BAAALgADCgcJCQAAAA==.',
Mo='Moisturizeme:BAAALgAECgUJBQAAAA==.Mojomaker:BAABLgAECn8VAAIGAAYJAhJyVABEAQAGAAYJAhJyVABEAQAAAA==.Moojitsu:BAAALgADCgMJAwAAAA==.Mormegil:BAABLgAECn8mAAIUAAgJcyFnBwCRAgAUAAgJcyFnBwCRAgAAAA==.Moshimoshi:BAACLgAFFH8VAAMGAAUJEBPfHQBTAQAGAAUJEBPfHQBTAQAFAAEJIQO3TQAzAAAuAAQKfxwAAwUACAmXG2cbADcCAAUABwkQHWcbADcCAAYABwkUCnRRAD8BAAAA.Motosake:BAAALgAECgQJBQAAAA==.',
Mu='Muffinlord:BAAALgAECgYJEQAAAA==.Munkeebutt:BAABLgAECn8gAAQQAAkJMQkzGwC1AQAQAAkJDQkzGwC1AQAEAAcJYAcoUwD/AAADAAEJsQst1QAwAAAAAA==.Munkeefase:BAAALgADCgEJAQAAAA==.',
My='Myronis:BAAALgADCgEJAQAAAA==.',
Na='Naberius:BAAALgAECgcJEAAAAA==.Naillil:BAAALgAECgEJAQAAAA==.Namiiswan:BAAALgADCgMJBQAAAA==.Nasmine:BAAALgADCgEJAQAAAA==.Natsuki:BAAALgADCgUJBwAAAA==.',
Ne='Nefarius:BAAALgAECggJDQABLgAECgkJFAANAKcYAA==.Neflite:BAABLgAECn8eAAIYAAcJvwcGGADOAAAYAAcJvwcGGADOAAAAAA==.Nelfie:BAAALgAECgEJAQAAAA==.Nessará:BAABLgAECn8VAAIHAAYJQCELEwAsAgAHAAYJQCELEwAsAgAAAA==.',
Ni='Nineõseven:BAABLgAECn8YAAITAAcJixN9IADVAQATAAcJixN9IADVAQABLgAECgEJAQABAAAAAA==.Ninjapro:BAAALgAECgEJAQAAAA==.Nixia:BAAALgAECgQJBAAAAA==.',
No='Nodiddy:BAAALgAECgQJBQABLgAECgcJJAARAPYhAA==.',
Nu='Nuraga:BAABLgAECn8hAAMlAAgJlyHXBwCpAgAlAAcJCSTXBwCpAgAPAAEJ7hKmhwBEAAAAAA==.',
Ob='Obeeone:BAAALgAECgEJAgAAAA==.',
On='Onasta:BAABLgAECn8hAAIOAAkJkx8qMgAiAgAOAAkJkx8qMgAiAgAAAA==.Onelastkiss:BAAALgAECgEJAQAAAA==.',
Op='Oprahheals:BAABLgAECn8cAAICAAkJFB4LFAC2AgACAAkJFB4LFAC2AgAAAA==.',
Or='Oreoagane:BAAALgADCgQJBAAAAA==.Oreobeer:BAAALgAECgEJAQAAAA==.Oreomonster:BAAALgAECgcJEQAAAA==.Orquesta:BAAALgAECgQJCQAAAA==.',
Pa='Paccer:BAAALgAECgEJAQAAAA==.Pacerx:BAAALgAECgIJAgAAAA==.Pandaemonia:BAACLgAFFH8SAAIkAAQJNA1UBgDUAAAkAAQJNA1UBgDUAAAuAAQKfyQAAiQACQncDXETAP0AACQACQncDXETAP0AAAAA.Pandakyle:BAABLgAECn8XAAIVAAYJ5xdsPgBBAQAVAAYJ5xdsPgBBAQAAAA==.Pandexander:BAAALgADCgMJAwAAAA==.Panterå:BAAALgAECgEJAQAAAA==.Parts:BAABLgAECn8iAAIRAAgJtiGIIQDtAgARAAgJtiGIIQDtAgABLgAFFAUJFwAnALgdAA==.Patchmen:BAAALgAECgQJBAAAAA==.Pattilicious:BAABLgAECn8kAAICAAkJZwtVbgB3AQACAAkJZwtVbgB3AQAAAA==.',
Pe='Pepsizero:BAAALgAECgUJCwAAAA==.',
Ph='Phlesh:BAAALgAECgEJAgAAAA==.Phlvrabies:BAAALgADCgMJBQAAAA==.Phonedin:BAABLgAECn8jAAMbAAkJERmdBgCIAgAbAAkJERmdBgCIAgAZAAMJBhchSQCyAAAAAA==.Phoënix:BAACLgAFFH8TAAMGAAUJGxaNGwBhAQAGAAUJGxaNGwBhAQAFAAEJGga4SgA5AAAuAAQKfyMAAwYACQmWHeIPALoCAAYACQmWHeIPALoCAAUAAwnmGHhaALkAAAAA.',
Pi='Pieglaive:BAABLgAECn8jAAMMAAkJzSHSBgCtAgAMAAkJzSHSBgCtAgALAAIJuhZpwwB2AAAAAA==.Pierres:BAAALgAECggJCQAAAA==.Piondelth:BAAALgAECgcJEQAAAA==.',
Pl='Plantman:BAAALgAECgYJDgAAAA==.',
Po='Pointyboner:BAAALgADCgQJBAAAAA==.Poofort:BAAALgAECgYJCQAAAA==.Pooner:BAAALgADCgMJAwAAAA==.Porkins:BAAALgAECgMJAwAAAA==.Postoak:BAAALgAECgUJCgAAAA==.Powerochrist:BAABLgAECn8xAAIeAAkJ+BlLDgCaAgAeAAkJ+BlLDgCaAgAAAA==.',
Pr='Priscila:BAAALgADCgYJBgAAAA==.Proxzy:BAABLgAECn8ZAAIFAAgJ/yDgCgCeAgAFAAgJ/yDgCgCeAgAAAA==.',
Pu='Pubessalad:BAABLgAECn8iAAICAAYJDRSjogAYAQACAAYJDRSjogAYAQAAAA==.Puddin:BAAALgADCgQJBwAAAA==.Puffytaco:BAAALgAECgYJCwABLgAECgkJIwACANccAA==.',
Qu='Qualek:BAABLgAECn8XAAIlAAkJMRJfEAADAgAlAAkJMRJfEAADAgAAAA==.Quilue:BAABLgAECn8dAAIRAAkJMw7nWgC1AQARAAkJMw7nWgC1AQAAAA==.',
Ra='Rannmagnison:BAABLgAECn8tAAICAAgJ/wZ9pgASAQACAAgJ/wZ9pgASAQAAAA==.Raquoon:BAABLgAECn8WAAIlAAYJ1w6SKADWAAAlAAYJ1w6SKADWAAAAAA==.Rasonia:BAAALgAECgYJBgABLgAFFAMJBgAfACYLAA==.Ratfu:BAAALgADCgcJDQAAAA==.Raumulus:BAAALgAECgEJAQAAAA==.Razjin:BAABLgAECn8aAAMGAAkJeiPsCQDaAgAGAAkJeiPsCQDaAgAFAAEJ/wrDngAnAAAAAA==.',
Re='Reapér:BAAALgAECgkJBQAAAA==.Rene:BAAALgADCgYJBgAAAA==.Reze:BAACLgAFFH8UAAIWAAQJayD8CABuAQAWAAQJayD8CABuAQAuAAQKfxYAAhYACAlYHlIPAD0CABYACAlYHlIPAD0CAAEuAAUUCQk0AAwAfx8A.',
Rh='Rhaeynera:BAABLgAECn8lAAIbAAcJ5AXLEADqAAAbAAcJ5AXLEADqAAAAAA==.Rhyel:BAAALgADCgIJAgAAAA==.Rhyno:BAAALgADCgkJEgABLgAECgkJNwANAEIgAA==.Rhysedwyn:BAAALgADCgkJEgABLgAECgEJAQABAAAAAA==.',
Ri='Riezen:BAAALgAECggJEgAAAA==.Ringol:BAAALgAECgQJCgABLgAECgYJDgABAAAAAA==.Rinorik:BAABLgAECn83AAMNAAkJQiD5DgDHAgANAAkJQiD5DgDHAgAYAAYJCRn2FACjAQAAAA==.Rizzdor:BAAALgADCgcJCAABLgAECgkJEgABAAAAAA==.',
Ro='Rockbiter:BAAALgAECgEJAgAAAA==.Rockhhard:BAABLgAECn8eAAIGAAkJxx44GwBXAgAGAAkJxx44GwBXAgAAAA==.Roeken:BAABLgAECn86AAIPAAkJKRVEHAD4AQAPAAkJKRVEHAD4AQAAAA==.Rollingman:BAAALgAECgYJEgAAAA==.Roummi:BAAALgAECgEJAQAAAA==.',
Ru='Rudyrots:BAAALgAECgEJAQABLgAFFAEJAgABAAAAAA==.Rudyshoots:BAAALgAFFAEJAgAAAA==.Rum:BAAALgAECgMJAwAAAA==.',
Ry='Rybear:BAAALgADCgkJCQAAAA==.Rygaard:BAABLgAECn84AAIlAAkJHyLsAwDcAgAlAAkJHyLsAwDcAgAAAA==.Rystic:BAAALgADCgkJCQAAAA==.Ryutiz:BAABLgAECn8sAAIEAAkJbSKCAQD3AgAEAAkJbSKCAQD3AgAAAA==.Ryward:BAAALgADCgcJBwAAAA==.Ryyuk:BAAALgAECgMJBAABLgAECgkJGQALAAkSAA==.',
Sa='Sacridas:BAAALgAECgEJAQABLgAECgkJLAAEAG0iAA==.Sako:BAAALgADCgUJCgAAAA==.Samsó:BAABLgAECn8XAAMCAAkJmBenfQBYAQACAAkJmBenfQBYAQAeAAQJ3BQNagDSAAAAAA==.Sapharina:BAACLgAFFH8GAAIfAAMJJgsDKQDLAAAfAAMJJgsDKQDLAAAuAAQKfzMAAh8ACQmWF3EOAGkCAB8ACQmWF3EOAGkCAAAA.Sassgrip:BAAALgADCgEJAQABLgAECgYJDAABAAAAAA==.Sassier:BAAALgAECgYJDAAAAA==.Sathenaz:BAAALgADCgcJCQAAAA==.',
Sc='Scarcy:BAACLgAFFH8RAAIIAAUJKRmGCwCYAQAIAAUJKRmGCwCYAQAuAAQKfzMAAwgACQliGrAQAJ0CAAgACQliGrAQAJ0CACYAAwmXCLIaAFsAAAAA.',
Se='Seacotton:BAABLgAECn8aAAMoAAkJlhulBgB9AgAoAAkJ7BqlBgB9AgAPAAcJoBVaQACjAQAAAA==.Searfang:BAACLgAFFH8UAAIFAAUJVBZTGgAhAQAFAAUJVBZTGgAhAQAuAAQKfzMAAwUACQlpIHoLAJYCAAUACQlpIHoLAJYCAAYAAQljE/S8ADYAAAAA.Seariel:BAAALgAECgUJBgAAAA==.Seatea:BAAALgADCgkJCQABLgAECgkJOAAZACAhAA==.Selestra:BAAALgAFFAIJAgAAAA==.Selinise:BAAALgAECgUJBQAAAA==.Sematic:BAAALgAFFAEJAQABLgAFFAYJFAARAJMbAA==.Senpai:BAAALgAECgQJBAAAAA==.Seraphymm:BAAALgADCgEJAQAAAA==.',
Sh='Shadowjacker:BAACLgAFFH8RAAILAAUJ+xrRMQA1AQALAAUJ+xrRMQA1AQAuAAQKfzgAAgsACQkmIYIHAFEDAAsACQkmIYIHAFEDAAAA.Shadowmidget:BAABLgAECn8WAAINAAkJ3BahVwDBAQANAAkJ3BahVwDBAQAAAA==.Shadrielis:BAABLgAECn84AAMfAAkJHhtfCgCtAgAfAAkJHhtfCgCtAgAHAAIJVQ3VbgBsAAAAAA==.Shanlao:BAAALgAFFAIJAgABLgAFFAYJIAANAL0SAA==.Shirkka:BAAALgADCgMJBAAAAA==.Shurihito:BAABLgAECn8lAAICAAkJiR4xHACEAgACAAkJiR4xHACEAgAAAA==.',
Si='Sieron:BAABLgAECn8UAAIOAAYJ/RyPhQBDAQAOAAYJ/RyPhQBDAQAAAA==.Silaslunark:BAAALgAECgkJCwAAAA==.Sinkrow:BAAALgAECgYJBgAAAA==.Sixpack:BAABLgAECn8aAAIgAAkJbQ7IOAChAQAgAAkJbQ7IOAChAQAAAA==.',
Sk='Skarigar:BAAALgAECgEJAwAAAA==.Skeeterson:BAAALgADCgUJCAAAAA==.Skiððles:BAAALgAECgYJBgABLgAECgkJHQAFANIUAA==.Skytec:BAAALgADCgMJAwAAAA==.Skëëts:BAABLgAECn8cAAQfAAgJSBBiIwCQAQAfAAgJJBBiIwCQAQATAAEJuwTtgQAnAAAHAAEJ5gbMbAAnAAAAAA==.Skùrvypete:BAAALgAECgEJAQABLgAECgkJHQAFANIUAA==.',
Sl='Slampoof:BAAALgAECgQJCgAAAA==.Slamslayer:BAAALgAECgEJAQAAAA==.Sleez:BAAALgAECgYJDAAAAA==.Sloodraga:BAAALgADCgYJBgAAAA==.',
Sm='Smallgregory:BAAALgAECgYJDAAAAA==.',
Sn='Sneakdead:BAAALgAECgcJCgAAAA==.Sneakerzz:BAAALgADCgQJBAAAAA==.Sneakfury:BAAALgAECgYJCgABLgAECgcJCgABAAAAAA==.Sneeler:BAAALgAECgEJAQAAAA==.Snowscayia:BAACLgAFFH8LAAQgAAYJARgVJAAgAQAgAAQJwBAVJAAgAQAJAAQJSQjZIwDjAAAdAAIJIQohEgB3AAAuAAQKfyoABAkACQkbGDMnAMUBAAkACAk2GjMnAMUBACAABwn1FD87ALgBAB0AAQlhCflCADcAAAAA.',
So='Solanar:BAABLgAECn88AAMeAAkJZiG5DgCUAgAeAAgJsiO5DgCUAgACAAcJESG0KgA+AgAAAA==.Solesin:BAAALgAFFAEJAQABLgAFFAUJEwAaADIXAA==.Solm:BAAALgADCgkJEgAAAA==.Solmina:BAABLgAECn83AAIRAAkJIh4pGwCiAgARAAkJIh4pGwCiAgAAAA==.Somniatis:BAAALgAECgEJAQAAAA==.Soulciopath:BAAALgAECgUJCAAAAA==.Souljin:BAAALgADCgMJAwAAAA==.',
Sp='Spicypants:BAAALgADCgMJAwAAAA==.Spicytaco:BAAALgAECgUJCgABLgAECgkJIwACANccAA==.Spookuleli:BAAALgADCggJCwAAAA==.Sprinklewiz:BAAALgADCgMJAwAAAA==.',
Sq='Squadie:BAABLgAECn8zAAIDAAgJiQvQXAB2AQADAAgJiQvQXAB2AQAAAA==.Squanchs:BAACLgAFFH8TAAIGAAUJnRp9FgCCAQAGAAUJnRp9FgCCAQAuAAQKfx4AAwYACQlkHygMAL8CAAYACQlkHygMAL8CAAUAAQkGANSvAAEAAAEuAAQKBwkcACAAkxsA.Squanchy:BAABLgAECn8cAAIgAAcJkxtxPACyAQAgAAcJkxtxPACyAQAAAA==.Squisquee:BAAALgADCgcJBwAAAA==.',
Sr='Srbojangles:BAAALgAECgcJCAABLgAECgcJJAARAPYhAA==.Srry:BAABLgAECn8VAAIPAAcJsBrUKQATAgAPAAcJsBrUKQATAgAAAA==.',
St='Stinkvile:BAAALgAECgEJAQAAAA==.Stonebraid:BAAALgADCgEJAQAAAA==.Sturdy:BAAALgADCgEJAQAAAA==.',
Su='Suiféng:BAAALgAECgIJAgAAAA==.Sukuna:BAAALgAECgYJCAAAAA==.Sundance:BAAALgAECggJEAAAAA==.Surmise:BAACLgAFFH8UAAIRAAYJkxsHJQCmAQARAAYJkxsHJQCmAQAuAAQKfzIAAxEACQkBJTkEAFcDABEACQkBJTkEAFcDACIABAlVIPQHAAgBAAAA.Sust:BAAALgAFFAEJAwABLgAFFAYJFAARAJMbAA==.Sustenance:BAAALgAFFAIJAgABLgAFFAYJFAARAJMbAA==.',
Sw='Swayzeetrain:BAACLgAFFH8RAAMeAAQJoCNWEACZAQAeAAQJoCNWEACZAQACAAEJpAxQMABUAAAuAAQKfxsAAwIACQkCHCxmALQBAAIABwkgGixmALQBAB4ACAn1IOA2AKABAAAA.',
['Sü']='Süß:BAAALgAFFAIJAgABLgAFFAQJBwALALULAA==.',
Ta='Tabius:BAABLgAECn8mAAMdAAkJXR6KCAAkAgAdAAkJXR6KCAAkAgAJAAMJyw6vWQCPAAAAAA==.Talkingtaco:BAABLgAECn8jAAICAAkJ1xwuHgB6AgACAAkJ1xwuHgB6AgAAAA==.Taln:BAAALgAECgEJAgABLgAECggJJgAUAHMhAA==.Talìa:BAAALgADCgIJAgABLgAECgEJAQABAAAAAA==.Tareul:BAAALgADCgIJAgAAAA==.Tarn:BAAALgAECgkJEgAAAA==.',
Te='Temok:BAABLgAECn8aAAICAAYJQgz7vwDrAAACAAYJQgz7vwDrAAAAAA==.',
Th='Thiccbush:BAAALgAECgEJAQAAAA==.Thirielnet:BAAALgAECgUJBwAAAA==.This:BAAALgAECgEJAQAAAA==.Thorisdead:BAAALgAECgEJAQABLgAECggJIwASAJwHAA==.Thorkell:BAAALgADCgUJBQAAAA==.Thosen:BAAALgAECgUJBQAAAA==.',
Ti='Tinkaballah:BAAALgAECgcJDgAAAA==.Tipy:BAAALgADCgUJBQAAAA==.',
To='Tore:BAACLgAFFH8VAAIDAAUJSBpIJwBJAQADAAUJSBpIJwBJAQAuAAQKfzMAAgMACQmUIqcJAPwCAAMACQmUIqcJAPwCAAAA.Totemangge:BAAALgAFFAEJAQAAAA==.',
Tr='Trifectas:BAAALgADCgcJFwAAAA==.Trinadel:BAACLgAFFH8OAAIJAAUJcBF/HQAIAQAJAAUJcBF/HQAIAQAuAAQKfx0AAgkACAmnHS8PAK0CAAkACAmnHS8PAK0CAAAA.Träitors:BAAALgADCgcJEwAAAA==.Tråitors:BAABLgAECn82AAMNAAYJciKmNwDuAQANAAYJciKmNwDuAQAYAAEJAAA0ZQBFAAABLgADCgcJEwABAAAAAA==.',
Ts='Tsarevich:BAABLgAECn8WAAIiAAYJhAhdCQDbAAAiAAYJhAhdCQDbAAAAAA==.',
Tu='Tugtheshaman:BAABLgAECn8dAAIGAAgJoxgmGgBGAgAGAAgJoxgmGgBGAgAAAA==.',
Tw='Twileaf:BAABLgAECn8tAAIgAAgJkAbKZQDxAAAgAAgJkAbKZQDxAAAAAA==.Twoinchisbig:BAABLgAECn9OAAIlAAkJLRtUCABhAgAlAAkJLRtUCABhAgAAAA==.',
Ty='Typhoidmary:BAABLgAECn8XAAMNAAgJhAmIggBVAQANAAcJhAmIggBVAQAYAAEJAAAOdgAuAAABLgAFFAMJAwABAAAAAA==.',
['Té']='Térror:BAAALgAECgcJDwAAAA==.',
Un='Unbenched:BAAALgADCgQJBQABLgAECgkJMQAFANIeAA==.Uncool:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Unholyz:BAAALgAECgUJCAAAAA==.',
Ur='Ursoc:BAABLgAECn84AAMJAAkJ9hLIGgDbAQAJAAkJ9hLIGgDbAQAgAAYJRxEhVQApAQAAAA==.Urteg:BAAALgADCgkJFAAAAA==.',
Uu='Uub:BAAALgAECgIJAgAAAA==.',
Va='Vairekor:BAAALgADCggJDgABLgAFFAYJIAANAL0SAA==.Valdria:BAAALgADCgUJBQAAAA==.Vanillaçake:BAAALgAECgYJCAAAAA==.Vanishja:BAAALgAECgYJDwAAAA==.Varkbyte:BAABLgAECn8WAAIHAAYJHBb9JACGAQAHAAYJHBb9JACGAQAAAA==.Varrik:BAACLgAFFH8SAAMPAAUJfCAHEQBeAQAPAAUJfCAHEQBeAQAoAAMJ7hgyHgDSAAAuAAQKfyYAAw8ACAnjIooJABUDAA8ACAnjIooJABUDACgABgmcG8YbAGQBAAAA.',
Ve='Vec:BAAALgAECgYJDQAAAA==.Velamor:BAABLgAECn8YAAQkAAYJzgvZGQCzAAAkAAYJ5grZGQCzAAAMAAMJygk5VQCTAAALAAMJagr8yAB3AAAAAA==.Velaria:BAAALgADCgcJBwAAAA==.',
Vi='Violynt:BAAALgADCgEJAQAAAA==.',
Vo='Volieu:BAABLgAECn8hAAIiAAkJpxPzAgD2AQAiAAkJpxPzAgD2AQAAAA==.Volklin:BAABLgAECn8gAAMGAAgJywjZVQA/AQAGAAgJywjZVQA/AQAFAAYJIgktVADNAAAAAA==.Voyageurs:BAABLgAECn8bAAIdAAgJlhzeBwA0AgAdAAgJlhzeBwA0AgAAAA==.',
Vy='Vyrka:BAAALgAECgMJDQAAAA==.',
Wa='Wallstreet:BAAALgAECgUJBQAAAA==.Waterdweller:BAAALgAECgEJAwAAAA==.',
We='Wegl:BAAALgAECgUJEwAAAA==.Werebear:BAAALgADCgMJAwABLgAECgQJBQABAAAAAA==.Werewithal:BAAALgADCgYJCwABLgAECgkJJwAQAC0SAA==.Wesleypipes:BAAALgAECgEJAQAAAA==.Wetfloorsign:BAAALgAECgYJEQAAAA==.',
Wh='Wholeymilk:BAAALgADCgYJCgAAAA==.',
Wi='Wiindsslashh:BAAALgAECgYJBwAAAA==.Wilbur:BAAALgADCgQJBQAAAA==.Windslash:BAAALgAECgIJAgAAAA==.',
Wo='Wonderx:BAAALgADCgIJAgAAAA==.Wonyoung:BAACLgAFFH8RAAIHAAQJMySjCACTAQAHAAQJMySjCACTAQAuAAQKfzIAAgcACQnzI9kBAFgDAAcACQnzI9kBAFgDAAAA.',
Wr='Wraithwok:BAAALgAECgUJBQAAAA==.',
Wu='Wuthrad:BAAALgADCgQJBAAAAA==.',
Xa='Xala:BAABLgAECn8UAAMUAAkJbw1YIwAdAQAUAAgJUA5YIwAdAQAnAAIJ+AdeJgBkAAAAAA==.Xalah:BAAALgAECgcJCgAAAA==.Xalaz:BAACLgAFFH8VAAMNAAUJKRGNSQAhAQANAAUJKRGNSQAhAQAYAAEJVwJgGgBGAAAuAAQKfx0AAw0ACQlXHHQ2ADICAA0ACAlXHHQ2ADICABgAAgkLFGNSAHcAAAAA.Xanaris:BAAALgADCgEJAQABLgAFFAIJCgAOAL0mAA==.Xandumbra:BAAALgADCgEJAQAAAA==.Xarosea:BAACLgAFFH8MAAICAAQJPxN+PQAZAQACAAQJPxN+PQAZAQAuAAQKfyoAAgIABwk6JPYYANMCAAIABwk6JPYYANMCAAAA.',
Xe='Xelojr:BAAALgADCgkJHAAAAA==.',
Xh='Xhael:BAAALgADCgEJAQAAAA==.',
Xi='Xia:BAABLgAECn9CAAIHAAkJqRkzFQA0AgAHAAkJqRkzFQA0AgAAAA==.',
Xo='Xoilkick:BAAALgAECgYJEAAAAA==.Xoilwings:BAAALgAECgIJAgAAAA==.Xooiill:BAAALgAECggJEQAAAA==.',
Xp='Xpacer:BAAALgAECgcJEwAAAA==.',
['Xê']='Xêna:BAAALgAECgQJBgAAAA==.',
Ye='Yekira:BAAALgADCgEJAgAAAA==.Yellowsnøw:BAACLgAFFH8FAAIRAAMJaQT/fgC9AAARAAMJaQT/fgC9AAAuAAQKfzMAAhEACQngFQc2ACgCABEACQngFQc2ACgCAAAA.',
Yu='Yumeshade:BAAALgAECgYJCgAAAA==.',
Za='Zaila:BAAALgAECgUJBQAAAA==.Zal:BAAALgAECgYJBgABLgAFFAUJCQAlAJsTAA==.Zamari:BAAALgAECgcJDgAAAA==.Zanzabar:BAABLgAECn8WAAIdAAkJegvGEACgAQAdAAkJegvGEACgAQAAAA==.Zathmage:BAAALgADCgMJAwAAAA==.Zaxin:BAABLgAECn8WAAMHAAgJSA72KABqAQAHAAgJSA72KABqAQATAAUJiAQeSwCtAAAAAA==.',
Ze='Zelfie:BAAALgADCgUJBQAAAA==.Zellda:BAAALgAECgYJCQAAAA==.Zerodarkness:BAAALgADCgkJCQAAAA==.Zeros:BAABLgAECn8WAAIRAAgJAxn3TADdAQARAAgJAxn3TADdAQAAAA==.',
Zi='Ziperz:BAAALgAECggJCAAAAA==.',
Zo='Zoerina:BAAALgAECgcJDwAAAA==.Zoobilong:BAAALgAECgUJEgAAAA==.',
Zx='Zxak:BAABLgAECn80AAIMAAgJjiYLBAD3AgAMAAgJjiYLBAD3AgAAAA==.',
Zy='Zyahk:BAAALgADCgQJBQAAAA==.Zynn:BAAALgAECgEJAgAAAA==.',
['Zë']='Zën:BAAALgAECgEJAQABLgAFFAQJCAAfAEUFAA==.',
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
