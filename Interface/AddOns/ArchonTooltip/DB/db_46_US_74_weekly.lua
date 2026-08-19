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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Druid-Balance','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','Evoker-Augmentation','Priest-Holy','Monk-Mistweaver','Priest-Discipline','Warlock-Demonology','Rogue-Subtlety','Hunter-BeastMastery','DemonHunter-Devourer','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Rogue-Assassination','Evoker-Preservation','Shaman-Enhancement','Shaman-Elemental','DeathKnight-Blood','Hunter-Marksmanship','Hunter-Survival','Warrior-Fury','Warrior-Protection','Shaman-Restoration','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','Mage-Fire','Paladin-Protection','Druid-Guardian','Mage-Frost','Druid-Feral','DemonHunter-Vengeance','Rogue-Outlaw','Warrior-Arms','Mage-Arcane',}
local provider = {region='US',realm="Drak'Tharon",name='US',type='weekly',zone=46,date='2026-08-18',data={Aa='Aaronguy:BAAALgAFFAEJAQAAAA==.',
Ad='Adorah:BAABLgAECn8gAAIBAAkJBBSQSADsAQABAAkJBBSQSADsAQAAAA==.',
Ak='Akazamello:BAAALgAECgEJAQAAAA==.',
Al='Aldafir:BAAALgAECgEJBAAAAA==.Allyia:BAAALgADCgEJAgABLgAECgYJBgACAAAAAA==.Alucarde:BAABLgAECn8cAAIDAAkJAgyvNwA2AQADAAkJAgyvNwA2AQAAAA==.',
An='Angrboda:BAAALgADCgYJBwAAAA==.',
Ar='Arator:BAAALgADCgYJBQAAAA==.Artelios:BAAALgADCgMJAwAAAA==.Arvad:BAAALgADCgUJBQABLgAFFAMJCwAEAH0gAA==.',
As='Ashknight:BAABLgAECn8WAAIFAAgJTAaS1ADiAAAFAAgJTAaS1ADiAAAAAA==.',
Au='Auroralights:BAAALgAECgQJBAAAAA==.',
Ax='Axél:BAAALgAECgEJAQAAAA==.',
Az='Azarathia:BAAALgAECgQJBAAAAA==.Azriel:BAAALgAECgEJAQABLgAFFAgJLAAGAAMgAA==.',
Ba='Babyjeebus:BAAALgAECgYJCgAAAA==.Bagged:BAAALgAECgcJEgAAAA==.Balzak:BAAALgADCgMJAwAAAA==.Barbaria:BAAALgAECgUJBQAAAA==.Bastas:BAABLgAECn8iAAIHAAkJKRgoJwAaAgAHAAkJKRgoJwAaAgAAAA==.',
Be='Beartreecat:BAAALgAECgEJAgAAAA==.Beastley:BAAALgADCgcJBwAAAA==.Beekro:BAACLgAFFH8pAAIIAAgJfSDPCQDUAQAIAAgJfSDPCQDUAQAuAAQKfzEAAggACQlYI8cHANoCAAgACQlYI8cHANoCAAAA.Beladentata:BAAALgADCgYJBgABLgAFFAgJHwAJAAcSAA==.Belaen:BAACLgAFFH8KAAIEAAQJkRiZDQApAQAEAAQJkRiZDQApAQAuAAQKfywAAgQACQkpHvQLAM4CAAQACQkpHvQLAM4CAAAA.Belarina:BAABLgAFFH8MAAIKAAYJHAqrJgA5AQAKAAYJHAqrJgA5AQABLgAFFAgJHwAJAAcSAA==.Belatink:BAACLgAFFH8fAAMJAAgJBxINBwBcAQAJAAgJBxINBwBcAQALAAMJTAGQRQBkAAAuAAQKfywAAwkACQmYHUgJALcCAAkACQmYHUgJALcCAAsABwnxClkyAA4BAAAA.',
Bi='Biggschottz:BAAALgADCgYJBgAAAA==.Bilando:BAAALgAECgYJDwAAAA==.',
Bl='Bloodveil:BAAALgAFFAEJAQABLgAFFAMJBgAMACwgAA==.Blueberry:BAAALgAECgEJAQAAAA==.Blàckbeard:BAABLgAECn8mAAINAAgJzxZjHwCbAQANAAgJzxZjHwCbAQAAAA==.',
Bo='Borden:BAAALgAECgkJEQAAAA==.',
Br='Brutalize:BAAALgAECgcJCgAAAA==.',
Bu='Bustyvoidelf:BAAALgAECgQJBAAAAA==.Buttercup:BAACLgAFFH8mAAIHAAcJpx/yCwA0AgAHAAcJpx/yCwA0AgAuAAQKfy0AAgcACQl2IVgIADIDAAcACQl2IVgIADIDAAAA.',
Ca='Carbohydrate:BAAALgAECgEJAQAAAA==.Carbos:BAAALgAECgEJAQAAAA==.',
Ch='Chainer:BAABLgAECn88AAIOAAkJXRqIBgA3AgAOAAkJXRqIBgA3AgAAAA==.Chirios:BAAALgAECgYJDgAAAA==.',
Ck='Ckdeath:BAABLgAECn8XAAIFAAgJJRlTaACWAQAFAAgJJRlTaACWAQAAAA==.Ckwarlock:BAAALgAECgIJAgAAAA==.',
Cl='Clam:BAAALgAECgEJAQABLgAECgkJFAAMAEEeAA==.Clubsandwich:BAAALgAECgMJBgAAAA==.',
Cr='Crash:BAAALgAECgEJAgABLgAFFAgJFAAPAFAXAA==.Crunchies:BAABLgAFFH8FAAIKAAUJqA0gGgD5AAAKAAUJqA0gGgD5AAAAAA==.',
Cu='Cursén:BAABLgAECn8yAAQMAAkJbRh2OwDtAQAMAAkJbRh2OwDtAQAQAAIJXQ+tIABvAAARAAEJigcpdwAtAAAAAA==.',
Da='Dacker:BAAALgADCgUJBQAAAA==.Daelen:BAAALgAECgEJBAABLgAFFAUJCQACAAAAAQ==.Daiquiri:BAABLgAFFH8FAAIIAAMJtBTlKQB7AAAIAAMJtBTlKQB7AAABLgAFFAkJIgASACsbAA==.Darlocke:BAABLgAECn8pAAITAAgJyRQwCADLAQATAAgJyRQwCADLAQAAAA==.Darthvolo:BAAALgADCgEJAQABLgAECgUJEAACAAAAAA==.Darwin:BAAALgADCgIJAgAAAA==.Daysforsand:BAAALgAECgEJAQAAAA==.Dayshinkan:BAAALgAECgEJBAAAAA==.',
De='Deathmurk:BAACLgAFFH8KAAIFAAMJUxb2jADwAAAFAAMJUxb2jADwAAAuAAQKfzYAAgUACQnSHFQrAFMCAAUACQnSHFQrAFMCAAAA.Deathstyck:BAAALgADCgcJBwABLgADCgcJBwACAAAAAA==.',
Di='Diasoul:BAAALgAECgkJCAAAAA==.Dimblederf:BAAALgADCgMJAwAAAA==.Divinesteez:BAAALgAECgQJBgABLgAFFAQJBAACAAAAAA==.',
Do='Dolt:BAAALgAECgEJAQABLgAECgUJBgACAAAAAA==.Doomentia:BAABLgAECn8ZAAMUAAgJQwz3JQBHAQAUAAgJQwz3JQBHAQAIAAYJuwoyXwC9AAAAAA==.',
Dr='Dragith:BAAALgAECgMJAwABLgAFFAgJGgAOAG4QAA==.Drezzarnbez:BAAALgAECgcJEAAAAA==.Drimdor:BAAALgAECgIJAgAAAA==.Druìdfluid:BAAALgAECgUJBgAAAA==.',
Du='Dungakrung:BAAALgADCgMJAwAAAA==.Durgrim:BAACLgAFFH8fAAIVAAgJmh0cBAA/AQAVAAgJmh0cBAA/AQAuAAQKfycAAhUACQmpIuQDAOoCABUACQmpIuQDAOoCAAAA.',
Dw='Dwuiduwu:BAAALgADCgMJAwAAAA==.',
Ed='Edine:BAAALgAECgMJBgAAAA==.',
Ee='Eeèva:BAACLgAFFH8KAAIOAAIJkgtQTQCKAAAOAAIJkgtQTQCKAAAuAAQKfyAAAg4ACQmUFMFLAL4BAA4ACQmUFMFLAL4BAAAA.',
Ef='Efah:BAAALgAECgUJCAAAAA==.',
El='Elementriix:BAAALgADCgEJAQAAAA==.Elgordo:BAAALgAECgYJBgAAAA==.',
Ep='Epoxxy:BAAALgAECgEJAgAAAA==.',
Es='Espresso:BAACLgAFFH8iAAISAAkJKxtLAgCRAgASAAkJKxtLAgCRAgAuAAQKfy8AAhIACQnYJGkDACoDABIACQnYJGkDACoDAAAA.',
Ex='Exvo:BAAALgAECgUJCgAAAA==.',
['Eè']='Eèêva:BAAALgADCgcJBwAAAA==.',
Fa='Fallenseraph:BAAALgADCgUJBQAAAA==.',
Fe='Fellbent:BAAALgAECgIJAgABLgAFFAQJBAACAAAAAA==.Fenric:BAAALgAECgEJAwAAAA==.',
Fh='Fhtagnglui:BAAALgAECgYJBwABLgAFFAUJCQACAAAAAQ==.',
Fr='Freddiemerc:BAAALgADCgcJDAAAAA==.Frogspawn:BAAALgADCgEJAQAAAA==.',
Fu='Furrywar:BAAALgAECgEJAQABLgAFFAkJFQAWABAhAA==.',
Ga='Gaartak:BAACLgAFFH8sAAQGAAgJAyCTBwB0AQAGAAQJHSCTBwB0AQAXAAUJcRIqDwAAAQAFAAUJHSGZNgD7AAAuAAQKfzYABBcACQkeJToBANUCAAUACAmwIyYPACMDABcACQm1HzoBANUCAAYABwmTIO0JAOQBAAAA.',
Ge='Geg:BAAALgAECgIJAgABLgAECgUJBgACAAAAAA==.Gengar:BAAALgAECggJEgAAAA==.Geto:BAAALgADCgYJBwAAAA==.',
Gi='Gimble:BAAALgAECgMJAgAAAA==.Girlypop:BAAALgADCgQJBAAAAA==.Gith:BAABLgAFFH8aAAIOAAgJbhBZDgDLAQAOAAgJbhBZDgDLAQAAAA==.Githlock:BAABLgAECn8YAAQQAAgJIhKqBwDXAQAQAAcJ7ROqBwDXAQARAAUJJwdoNwDYAAAMAAIJUQiSTAEuAAABLgAFFAgJGgAOAG4QAA==.Githon:BAAALgAECggJEwABLgAFFAgJGgAOAG4QAA==.Githpriest:BAAALgADCgcJBwABLgAFFAgJGgAOAG4QAA==.',
Gl='Gluegun:BAACLgAFFH8iAAQYAAYJXBbbCAAJAQAZAAQJFhEtCAAXAQAYAAYJxhHbCAAJAQAOAAIJcBpMfACfAAAuAAQKfxsABBgACQm5HHkeADMCABgACAn6G3keADMCABkAAwnzEDEJAKcAAA4AAgn0IW0KAVMAAAAA.',
Go='Gondo:BAAALgAECgUJBQABLgAFFAMJCAAOAKUXAA==.Goodberry:BAAALgADCgYJBgAAAA==.',
Gr='Griselbrand:BAAALgAECgUJBwAAAA==.Grogrin:BAACLgAFFH8mAAMaAAgJGhVzEAAdAQAbAAYJYReAEQAfAQAaAAUJ9hBzEAAdAQAuAAQKf0EAAxoACQn8Io0BAMACABoACQmEIo0BAMACABsABAkQGm04AJQAAAAA.',
Gu='Gunnlaugr:BAAALgADCgYJBgAAAA==.',
Ha='Haleb:BAAALgADCgYJBgAAAA==.Haribooty:BAAALgAECgUJBQABLgAFFAgJKwAcAJsUAA==.Harlíequinn:BAABLgAECn8sAAIcAAkJXgO0gwDXAAAcAAkJXgO0gwDXAAAAAA==.Harmacist:BAABLgAECn8ZAAISAAcJ9A5POAA0AQASAAcJ9A5POAA0AQAAAA==.',
He='Hekate:BAAALgAECgEJAQAAAA==.Hex:BAABLgAFFH8KAAIcAAUJXw75FgAVAQAcAAUJXw75FgAVAQABLgAFFAUJHAAJAHIhAA==.',
Hi='Hitmonlee:BAABLgAFFH8NAAQdAAcJiRjBAwCkAQAdAAYJ2hrBAwCkAQAeAAIJIArMIQA9AAAKAAEJ0gLnTgAUAAABLgAFFAkJVwAIACQhAA==.',
Ho='Hobstwo:BAAALgAECgEJAQAAAA==.Hoofhearted:BAAALgAECgIJAgAAAA==.Hoofstompa:BAAALgADCgMJAwAAAA==.Houtoku:BAAALgAFFAUJCQAAAQ==.Hozi:BAACLgAFFH8QAAMFAAMJkh5dRwDMAAAFAAMJkh5dRwDMAAAXAAMJewtdHwBnAAAuAAQKf0EABAUACQnsIr0QAOcCAAUACQnsIr0QAOcCABcAAwkhGQI9AF8AAAYAAQkfBzEZACoAAAAA.Hozina:BAAALgAECgcJBwABLgAFFAMJEAAFAJIeAA==.Hozjor:BAAALgAECgYJDwABLgAFFAMJEAAFAJIeAA==.',
Hp='Hpnosis:BAABLgAECn8XAAIBAAgJng8sfQCAAQABAAgJng8sfQCAAQAAAA==.',
Hu='Hukdonfonex:BAAALgAECgcJDAAAAA==.Hunterin:BAABLgAECn8ZAAMOAAgJ1CSGDADcAgAOAAcJxiSGDADcAgAYAAMJryL2SgAmAQABLgAFFAkJFQAWABAhAA==.Huntington:BAAALgAECgYJCAABLgAECgkJMgAMAG0YAA==.',
Il='Illidanmello:BAACLgAFFH8kAAIPAAcJyh+gHwC6AQAPAAcJyh+gHwC6AQAuAAQKfysAAw8ACQkuIPIlADYCAA8ACQkuIPIlADYCAB8AAwnqDwFTAJ0AAAAA.',
Im='Imtrying:BAACLgAFFH8rAAIcAAgJmxSDCQC7AQAcAAgJmxSDCQC7AQAuAAQKfywAAhwACQknFAorAOEBABwACQknFAorAOEBAAAA.',
Is='Isolet:BAAALgAECgYJBgAAAA==.',
Ja='Jayaegis:BAAALgADCgUJBgAAAA==.Jayaesir:BAABLgAFFH8JAAIBAAMJXR/OHwANAQABAAMJXR/OHwANAQAAAA==.Jayal:BAACLgAFFH8XAAIBAAUJBBUaJAD6AAABAAUJBBUaJAD6AAAuAAQKfysAAgEACQncE0tuAJEBAAEACQncE0tuAJEBAAAA.',
Je='Jerdek:BAAALgAECgEJAQAAAA==.Jessïe:BAAALgAECgUJCAAAAA==.Jester:BAAALgAECggJDAAAAA==.',
Jo='Johndurgrim:BAAALgAFFAQJBAABLgAFFAgJHwAVAJodAA==.Joja:BAACLgAFFH8gAAIKAAUJnBMrJQBEAQAKAAUJnBMrJQBEAQAuAAQKfyQAAwoACQlrGDcaAEYCAAoACQlrGDcaAEYCAB4AAgnFFZ4SAD0AAAAA.Jooja:BAABLgAECn8tAAMTAAkJLRVLCADJAQATAAcJVBhLCADJAQANAAQJBA95NgD6AAABLgAFFAUJIAAKAJwTAA==.',
Ju='Juliana:BAAALgADCgEJAQAAAA==.Julow:BAAALgAECgEJAwAAAA==.',
['Jö']='Jökér:BAAALgADCgEJAQAAAA==.',
Ka='Kaizen:BAAALgAECgUJBQAAAA==.Katbelle:BAACLgAFFH8qAAIgAAgJUguLAQBNAQAgAAgJUguLAQBNAQAuAAQKfy4AAiAACQmBGPgCAAsCACAACQmBGPgCAAsCAAAA.',
Ke='Keyi:BAAALgADCgcJDgABLgADCgcJBwACAAAAAA==.Keynallan:BAAALgAECgQJBAAAAA==.',
Kh='Khalur:BAAALgAECgQJBQABLgAFFAUJCQACAAAAAQ==.',
Ki='Kinkykelly:BAACLgAFFH8UAAIPAAgJMRNTCgCIAQAPAAgJMRNTCgCIAQAuAAQKfyIAAg8ACAmHIdklAG8CAA8ACAmHIdklAG8CAAAA.',
Kl='Kloo:BAAALgAECgEJAQAAAA==.',
Kr='Krixxus:BAAALgAECgEJAgAAAA==.Kruger:BAAALgAECgYJBgAAAA==.Krugidan:BAABLgAECn8UAAIfAAgJeiBADABiAgAfAAgJeiBADABiAgAAAA==.',
Ku='Kuroishi:BAAALgAECgEJAQAAAA==.',
['Kú']='Kúsh:BAAALgAECgQJBwAAAA==.',
['Kü']='Küsh:BAAALgAECggJEwAAAA==.',
La='Lahar:BAAALgAFFAEJAgABLgAFFAUJHAAJAHIhAA==.Lala:BAAALgAECgUJAgAAAA==.',
Le='Leof:BAAALgAECgEJAQABLgAFFAgJHwAVAJodAA==.Leshwi:BAAALgAECgYJDAABLgAECgYJEAACAAAAAA==.',
Li='Liltimmyp:BAAALgADCgEJAQAAAA==.Littlelam:BAACLgAFFH8VAAMFAAUJfSHjSABhAQAFAAQJfSHjSABhAQAXAAEJAAC8awAAAAAuAAQKfy0AAgUACAlUI7cTAAUDAAUACAlUI7cTAAUDAAAA.',
Lo='Locknar:BAAALgADCgYJBgABLgAECgUJCAACAAAAAA==.Lockybowboa:BAAALgAECgMJAwAAAA==.Locrock:BAAALgAECgEJAQAAAA==.Loken:BAAALgAECgkJDgABLgAFFAYJAQACAAAAAA==.Longneck:BAAALgADCgIJAwABLgAFFAUJIAAKAJwTAA==.Lorkhan:BAABLgAECn8VAAIhAAkJ2xW4FQB1AQAhAAkJ2xW4FQB1AQAAAA==.Lotti:BAAALgAECgUJBgAAAA==.Loxsmith:BAAALgAECgYJBgABLgAFFAQJBAACAAAAAA==.',
Lt='Ltcclover:BAAALgAECgQJCQAAAA==.',
Lu='Lugren:BAAALgADCgYJBgAAAA==.',
Ma='Maledict:BAABLgAECn8WAAIPAAcJlwYggwAiAQAPAAcJlwYggwAiAQAAAA==.Malgan:BAAALgAECgcJCQABLgAFFAUJCQACAAAAAQ==.Manhattan:BAAALgAECgcJDwABLgAFFAkJIgASACsbAA==.Martini:BAAALgAECgQJCgABLgAFFAkJIgASACsbAA==.',
Mc='Mccavity:BAABLgAECn8VAAIQAAYJNxnhAgB0AQAQAAYJNxnhAgB0AQABLgAECgkJNQAiALcHAA==.',
Me='Meko:BAAALgAECgUJBwAAAA==.Merikaya:BAAALgAECggJCwAAAA==.Meèko:BAAALgAFFAEJAQAAAA==.Meéko:BAAALgADCgQJBAAAAA==.',
Mi='Miau:BAAALgAECgYJBgAAAA==.Mistafridge:BAAALgAFFAQJBAAAAA==.',
Mo='Mollie:BAAALgAECgIJAwABLgAFFAQJEAAeAIUjAA==.Monkedor:BAAALgADCgIJAgAAAA==.Moocelee:BAAALgAECgQJCAAAAA==.',
Mu='Murk:BAAALgADCgkJDQABLgAFFAMJCgAFAFMWAA==.Murloc:BAAALgADCgEJAQAAAA==.',
Na='Nah:BAAALgADCgcJBwAAAA==.Nahshadah:BAAALgADCggJCAAAAA==.Nano:BAAALgAECgMJAwABLgAFFAQJBAACAAAAAA==.Nanome:BAABLgAECn8VAAIjAAYJghX4pgAwAQAjAAYJghX4pgAwAQABLgAFFAQJBAACAAAAAA==.Nazure:BAAALgAECgEJAQAAAA==.',
Ne='Nedra:BAAALgADCgEJAQABLgAECgYJBgACAAAAAA==.Nesral:BAABLgAECn8ZAAIOAAgJrhTDJwAaAgAOAAgJrhTDJwAaAgAAAA==.Nevoir:BAAALgAECggJCQAAAA==.',
Nh='Nhasir:BAACLgAFFH8fAAIXAAgJ+BFJDwD+AAAXAAgJ+BFJDwD+AAAuAAQKfyIAAhcACQmHISQHAL4CABcACQmHISQHAL4CAAAA.Nhasraxion:BAABLgAFFH8FAAIhAAMJARG9CQB/AAAhAAMJARG9CQB/AAABLgAFFAgJHwAXAPgRAA==.Nhastea:BAACLgAFFH8HAAIeAAIJHB7OPwCnAAAeAAIJHB7OPwCnAAAuAAQKfxcAAh4ABwmDGqggAKIBAB4ABwmDGqggAKIBAAEuAAUUCAkfABcA+BEA.',
Ni='Niceneasy:BAAALgAECgMJAwAAAA==.Niematotamto:BAAALgADCgEJAQAAAA==.',
No='Normal:BAAALgAECgMJAwAAAA==.Nowaifu:BAAALgAECgYJEQAAAA==.',
Od='Odrade:BAAALgADCgIJAgABLgADCgIJAgACAAAAAA==.',
Ow='Owlbread:BAABLgAECn8VAAIkAAkJ6wnQFwBCAQAkAAkJ6wnQFwBCAQAAAA==.',
Oz='Ozwin:BAABLgAECn8ZAAMKAAYJuRyTDgA8AQAKAAQJuRyTDgA8AQAeAAYJYRbMMwAwAQABLgAFFAgJLAAGAAMgAA==.',
Pa='Palarin:BAAALgAFFAEJAQABLgAFFAkJFQAWABAhAA==.',
Pe='Peccator:BAACLgAFFH8cAAIJAAUJciFcCwCWAQAJAAUJciFcCwCWAQAuAAQKfykAAgkACQmRIhgEAEUDAAkACQmRIhgEAEUDAAAA.Pein:BAAALgADCgIJAgAAAA==.Percdirty:BAAALgADCgUJCAAAAA==.Persess:BAAALgAECgQJBQAAAA==.',
Ph='Phatality:BAAALgAECgMJCQABLgAECgQJBQACAAAAAA==.',
Pi='Pillowpants:BAAALgAECgcJEAAAAA==.',
Pl='Plat:BAAALgAECgQJCgAAAA==.Platsearthen:BAABLgAECn8cAAIBAAgJqAMj/AC8AAABAAgJqAMj/AC8AAAAAA==.Platspriest:BAAALgADCgMJAwAAAA==.Ploo:BAAALgADCgcJAQAAAA==.',
Pn='Pneumma:BAAALgAECgcJDgABLgAFFAYJAQACAAAAAA==.',
Po='Poodrinker:BAAALgAECgEJAQABLgAECgcJEAACAAAAAA==.Potassium:BAAALgAECgcJCwAAAA==.',
Pr='Priya:BAAALgAECgYJEAAAAA==.Protect:BAAALgAECgMJBAABLgAFFAMJCAAOAKUXAA==.Pròm:BAAALgAECgIJAQAAAA==.',
Pu='Punkinhed:BAAALgADCgEJAQAAAA==.',
Ra='Ramordis:BAAALgADCgEJAQAAAA==.Ravia:BAABLgAECn8XAAIlAAcJDhyhBwALAgAlAAcJDhyhBwALAgAAAA==.',
Re='Rebyen:BAAALgADCgYJBQAAAA==.Refr:BAACLgAFFH8FAAMcAAUJkwRwNgBwAAAcAAQJsQFwNgBwAAAWAAEJ0gqnMgBIAAAuAAQKfxUAAhYACQldGBUDADYCABYACQldGBUDADYCAAAA.Regularhorns:BAABLgAECn8XAAIPAAgJSg6/fAAmAQAPAAgJSg6/fAAmAQAAAA==.Rendhoof:BAAALgAECgIJBQAAAA==.Renzo:BAAALgAECgQJAwABLgAFFAgJLAAGAAMgAA==.Reptarr:BAAALgAECgUJBQABLgAFFAQJBAACAAAAAA==.Restodruid:BAAALgAECgQJBAAAAA==.Rev:BAAALgADCgQJCAAAAA==.',
Ri='Richter:BAAALgADCgkJCQAAAA==.Rins:BAACLgAFFH8VAAIWAAkJECF8BwBBAgAWAAkJECF8BwBBAgAuAAQKfxcABBYABwm3I/EaAAkCABYABwlFI/EaAAkCABUABAnZHUwfAP8AABwAAQlTHj29AFQAAAAA.Rinslet:BAACLgAFFH8GAAMSAAIJ7x3LKgCpAAASAAIJ7x3LKgCpAAALAAEJEiFpKQBaAAAuAAQKfxUAAxIACQl0G/cRAEUCABIACAnIHPcRAEUCAAsAAwlBFUtSALgAAAEuAAUUCQkVABYAECEA.Riskante:BAACLgAFFH8TAAIBAAUJMBSwRgAeAQABAAUJMBSwRgAeAQAuAAQKfzUAAwEACQm7HW4fAIsCAAEACQm7HW4fAIsCAAQABQlmEfJbAA0BAAAA.',
Ro='Roonrana:BAAALgAECgMJBQAAAA==.Rosemari:BAAALgAECgQJCQABLgAFFAgJIgAmAAAaAA==.Rosey:BAACLgAFFH8iAAMmAAgJABpSAQCVAQAmAAcJmRlSAQCVAQANAAIJUhemHACcAAAuAAQKfz4AAyYACQn3JOACAIQCACYACQn3JOACAIQCAA0AAQkIEHkWAEQAAAAA.Rouge:BAAALgAECgEJAQABLgAFFAMJBgAMACwgAA==.',
Ru='Rubýrose:BAAALgAECggJCAAAAA==.Rulutieh:BAAALgAECgMJBgAAAA==.Runebraker:BAAALgAECgYJCwAAAA==.',
Sa='Sandfordays:BAAALgAECgMJBgAAAA==.Sardor:BAAALgAECgQJCAABLgAFFAgJLAAGAAMgAA==.',
Sc='Scorn:BAAALgAECgkJEQAAAA==.Scottyno:BAACLgAFFH8ZAAIBAAYJHhntFQBJAQABAAYJHhntFQBJAQAuAAQKfyYAAgEACQmrHpgbAJ4CAAEACQmrHpgbAJ4CAAAA.',
Se='Sempast:BAACLgAFFH8GAAIMAAMJLCA7ZgD5AAAMAAMJLCA7ZgD5AAAuAAQKfy0AAwwACQmuIq4KAPoCAAwACAmLIq4KAPoCABEABAngImcZAIABAAAA.Senarria:BAAALgAECgEJAQAAAA==.',
Sh='Shadyfear:BAAALgAECgEJAQAAAA==.Shaldin:BAABLgAECn8UAAIcAAcJBCDiKgAPAgAcAAcJBCDiKgAPAgAAAA==.Shaluesta:BAAALgAECgMJBAAAAA==.Shaluestaa:BAAALgAECgcJBwAAAA==.Shanithell:BAAALgADCgIJAgAAAA==.Shanksz:BAAALgAECgIJAwAAAA==.Shellyd:BAABLgAECn8mAAIaAAkJKRWHGgAZAgAaAAkJKRWHGgAZAgAAAA==.Shiryû:BAAALgADCgEJAQAAAA==.',
Si='Siennaa:BAAALgAECgIJAgAAAA==.Sinfulsmite:BAAALgADCgQJAQABLgAECgQJCgACAAAAAA==.Sins:BAACLgAFFH8NAAQFAAUJjhYiFgBLAQAFAAQJMxUiFgBLAQAGAAMJ5BDlGADEAAAXAAEJAABAaQAAAAAuAAQKfxYAAgUACAmFHxApAJYCAAUACAmFHxApAJYCAAAA.',
Sl='Sleifer:BAAALgAFFAIJAgAAAA==.Slide:BAAALgAECgYJBgAAAA==.',
Sn='Sneakyhand:BAACLgAFFH8rAAMaAAgJSyLuAwAyAgAaAAgJSSLuAwAyAgAnAAUJLCFmCgCiAQAuAAQKfzAABBoACQlTJRYEAGoDABoACAkUJhYEAGoDACcABAlNI1obAIABABsAAgl5IBUzALAAAAAA.',
So='Soupson:BAAALgADCgIJAgABLgAECgYJEAACAAAAAA==.',
St='Starind:BAAALgAECgEJAQAAAA==.Steelt:BAAALgAECgYJCwABLgAFFAgJGgAOAG4QAA==.Steris:BAAALgAECgYJEAAAAA==.Stinkindwarf:BAAALgAECgQJBAAAAA==.Stizzy:BAAALgAECgMJBQAAAA==.',
Su='Sunadora:BAAALgAECgEJBAAAAA==.',
Sw='Swagula:BAABLgAECn8ZAAIhAAgJjiMVBQCqAgAhAAgJjiMVBQCqAgAAAA==.',
Sy='Sylvain:BAAALgAECgEJAQABLgAECgkJKAAWAJIdAA==.Sylvi:BAABLgAECn8XAAMiAAkJQhnqDAC5AQAiAAkJQhnqDAC5AQAkAAIJFRILOgBwAAAAAA==.Syrup:BAAALgADCgkJCQAAAA==.Syurni:BAAALgADCgEJAgABLgAECgYJBgACAAAAAA==.',
Ta='Takitsu:BAACLgAFFH8oAAIiAAgJ3giMDgC3AAAiAAgJ3giMDgC3AAAuAAQKfy8AAiIACAnoFu4SAMQBACIACAnoFu4SAMQBAAAA.',
Te='Terror:BAAALgAECgkJEwAAAA==.',
Th='Tharion:BAAALgAECgEJAQAAAA==.Thedoctor:BAAALgAFFAYJAQAAAA==.',
Ti='Tinyfist:BAAALgADCgYJBgAAAA==.Tired:BAAALgADCgEJAgAAAA==.',
To='Tombz:BAACLgAFFH8UAAMFAAYJZxY5OACMAQAFAAYJZxY5OACMAQAXAAEJAABjYQAAAAAuAAQKfz4AAwUACQn0IA4kAHUCAAUACQn0IA4kAHUCABcAAgk1Ag5GADAAAAAA.Towa:BAAALgAFFAQJBAAAAA==.',
Tr='Trater:BAEBLgAECn8sAAIMAAYJhRR2HgCIAAAMAAYJhRR2HgCIAAAAAA==.Trilira:BAAALgADCgUJBwAAAA==.',
Tu='Turf:BAAALgADCgMJAgAAAA==.',
Ul='Ulangi:BAAALgAECgEJAQAAAA==.',
Un='Unbelavable:BAAALgAECgYJBwAAAA==.',
Ur='Uranis:BAAALgADCgEJAgAAAA==.Ursa:BAAALgAECgYJCgAAAA==.',
Va='Vaskie:BAABLgAFFH8IAAIaAAMJOxgwFgDsAAAaAAMJOxgwFgDsAAAAAA==.',
Ve='Veil:BAAALgAFFAIJBAABLgAFFAMJBgAMACwgAA==.',
Vl='Vlorax:BAAALgADCgMJBgAAAA==.',
Vo='Volodinson:BAAALgAECgUJEAAAAA==.Voodootactic:BAAALgAFFAEJAQAAAA==.',
Vy='Vynesh:BAAALgADCgEJAwAAAA==.Vyra:BAAALgAECgkJDQAAAA==.',
Wa='Wallê:BAACLgAFFH8KAAIcAAIJwhRFNQB0AAAcAAIJwhRFNQB0AAAuAAQKfxsAAxwACQmPGCUfAFYCABwACQmPGCUfAFYCABYABgmFB3ZkALgAAAAA.Wallë:BAAALgAECgQJBAAAAA==.Wandwanker:BAABLgAECn8aAAIoAAkJ7h24AQB0AgAoAAkJ7h24AQB0AgAAAA==.Warsawz:BAAALgAECgUJCQAAAA==.Warstephano:BAAALgAFFAIJAgAAAA==.',
We='Wetasscat:BAABLgAECn8UAAIMAAkJQR5MOQAmAgAMAAkJQR5MOQAmAgAAAA==.Weyae:BAAALgAECgQJDAAAAA==.',
Wh='Whorg:BAACLgAFFH8IAAIOAAMJpRd/aQDSAAAOAAMJpRd/aQDSAAAuAAQKfysAAw4ACAlkHyBGAM8BAA4ACAneHCBGAM8BABkABglHHPISAJQBAAAA.',
Wi='Willyboi:BAABLgAECn8uAAMjAAkJCxUKPQAmAgAjAAkJCxUKPQAmAgAoAAQJNwp9DwDKAAAAAA==.Wisemanorc:BAAALgAECgMJBQAAAA==.',
Xa='Xavierr:BAABLgAECn8aAAIKAAkJlxIJJwDvAQAKAAkJlxIJJwDvAQAAAA==.',
Ya='Yarkaz:BAAALgAECgQJCwAAAA==.',
Yi='Yinli:BAAALgAECgEJAQAAAA==.',
Yu='Yucky:BAAALgAECgEJAQABLgAECggJEwACAAAAAA==.Yuuyu:BAAALgAECgYJBgAAAA==.',
Za='Zaai:BAAALgADCgcJCgAAAA==.Zargus:BAABLgAECn8oAAIWAAkJkh0mJADFAQAWAAkJkh0mJADFAQAAAA==.Zarlunce:BAABLgAECn8iAAIaAAkJVRv/HgD3AQAaAAkJVRv/HgD3AQAAAA==.',
Ze='Zetsuon:BAACLgAFFH8HAAIHAAMJJhMXPgC3AAAHAAMJJhMXPgC3AAAuAAQKfzcAAgcACQnqH4oKABQDAAcACQnqH4oKABQDAAAA.',
Zu='Zuk:BAAALgAECgcJDQAAAA==.',
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
