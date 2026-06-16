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

local lookup = {'DeathKnight-Frost','Unknown-Unknown','Hunter-BeastMastery','Hunter-Survival','Warrior-Arms','Warrior-Fury','Warlock-Demonology','Warlock-Affliction','Druid-Balance','Shaman-Elemental','Hunter-Marksmanship','Paladin-Retribution','Warlock-Destruction','Priest-Discipline','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Restoration','Warrior-Protection','Monk-Windwalker','Priest-Holy','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','DemonHunter-Havoc','Rogue-Subtlety','Priest-Shadow','Druid-Feral','Monk-Mistweaver','Monk-Brewmaster','Druid-Restoration','Druid-Guardian','DemonHunter-Devourer','Rogue-Assassination','Paladin-Holy','Paladin-Protection',}
local provider = {region='US',realm='Darrowmere',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abaddonmoon:BAABLgAECn8vAAIBAAgJJQvnEwA7AQABAAgJJQvnEwA7AQAAAA==.Absentia:BAAALgAECgEJAQABLgAECgEJAgACAAAAAA==.',
Ad='Addvar:BAAALgADCgEJAQAAAA==.Adelost:BAAALgAECgQJBQAAAA==.',
Ah='Ahalina:BAAALgAECgYJCAAAAA==.Ahnari:BAACLgAFFH8FAAIDAAMJdgJ5DwDMAAADAAMJdgJ5DwDMAAAuAAQKfxUAAwMACAlAEVg9ALkBAAMACAlAEVg9ALkBAAQABAm8AoQmAIsAAAAA.',
Ai='Ailinaa:BAACLgAFFH8iAAMFAAYJmh27CAC3AQAFAAYJvhy7CAC3AQAGAAUJBRx6BQCbAQAuAAQKfyAAAwYACQkkH8kVAJ8CAAYACAkpH8kVAJ8CAAUABAnjF10uAAwBAAAA.',
Ak='Akalifato:BAACLgAFFH8KAAMHAAMJyx4QYAACAQAHAAMJyx4QYAACAQAIAAEJBBJ3IABPAAAuAAQKfxgAAgcABwkBG7g8AOgBAAcABwkBG7g8AOgBAAEuAAUUCAkjAAkATR4A.Akroma:BAAALgAECgIJBQAAAA==.',
Al='Alariya:BAAALgAECgUJBQAAAA==.Alerat:BAAALgAECgQJBAABLgAECgkJLwAKAPkRAA==.Alistin:BAABLgAECn8aAAMEAAkJ1RMTFAAFAgAEAAkJnxITFAAFAgADAAEJUSEX+ABiAAAAAA==.Alistïn:BAAALgAECgEJAwAAAA==.Alone:BAAALgADCgQJAwAAAA==.Alstir:BAAALgAECgEJAQAAAA==.',
Am='Amaryllis:BAAALgAECgEJAQAAAA==.Ambivalent:BAAALgAECgQJBgAAAA==.',
Ar='Aradin:BAAALgAECgMJBAAAAA==.Archanfel:BAACLgAFFH8FAAIEAAMJ1QHwKACNAAAEAAMJ1QHwKACNAAAuAAQKfz4AAwQACAmPFV8YAN4BAAQACAmDFF8YAN4BAAsAAwkKD6YhAKAAAAAA.Argasha:BAAALgADCgUJBQAAAA==.',
As='Asriel:BAAALgAECgcJDQAAAA==.',
At='Atraxa:BAAALgAECgYJDQAAAA==.',
Aw='Awsomweorc:BAAALgADCgEJAQAAAA==.',
Ax='Axies:BAAALgAECgEJAQABLgAECgQJBwACAAAAAA==.',
Ay='Ayonna:BAABLgAECn8cAAIMAAYJ7Qb16gDNAAAMAAYJ7Qb16gDNAAAAAA==.',
Az='Azar:BAAALgADCgUJBQABLgAECgEJAQACAAAAAA==.',
Ba='Bandie:BAAALgAECgYJEQAAAA==.Barksalot:BAAALgAECgcJBwAAAA==.Barrakum:BAAALgAECgUJDgAAAA==.Bastet:BAAALgADCgUJBQAAAA==.Bayn:BAAALgADCgQJCQAAAA==.',
Be='Beeftruck:BAACLgAFFH8MAAMGAAMJ8hRDNQDXAAAGAAMJAxRDNQDXAAAFAAMJpgjvLACqAAAuAAQKfzIAAwUACQlBIXEFALECAAUACQlzH3EFALECAAYABwn7Hu8uAJMBAAAA.Belletrixx:BAABLgAECn8UAAMHAAYJOAy3xADEAAAHAAYJggu3xADEAAANAAMJhQVOOwA5AAAAAA==.Bellonä:BAAALgAECgEJAQAAAA==.Berried:BAACLgAFFH8LAAIOAAMJdxJoMADHAAAOAAMJdxJoMADHAAAuAAQKf1IAAg4ACQkhIYYEAEgDAA4ACQkhIYYEAEgDAAAA.',
Bi='Biigmâc:BAABLgAECn8WAAIKAAcJ6QUdSwAbAQAKAAcJ6QUdSwAbAQAAAA==.Biminem:BAABLgAECn8dAAIPAAgJbxV2DwC1AQAPAAgJbxV2DwC1AQAAAA==.',
Bl='Black:BAAALgAECgYJDAAAAA==.Blackwidow:BAAALgAECgMJAwAAAA==.Bloodshöt:BAABLgAECn8fAAMQAAgJdhvlOAAZAgAQAAgJdhvlOAAZAgARAAEJXgf8ZwAXAAABLgAECgkJJwAGAIUYAA==.',
Bo='Bodak:BAABLgAECn8bAAISAAYJ5hnRNwCjAQASAAYJ5hnRNwCjAQAAAA==.Boricua:BAAALgAECgEJAgAAAA==.',
Br='Brakun:BAAALgADCgIJAgAAAA==.Brolly:BAAALgAECgkJAgAAAA==.Broris:BAAALgAECgMJAwABLgAECgYJDAACAAAAAA==.Brucewii:BAAALgAECgUJBQAAAA==.Brunn:BAAALgAECgYJDAAAAA==.',
Ca='Calamari:BAAALgAECgMJAwAAAA==.Calistarius:BAACLgAFFH8NAAITAAUJ/xXnEwD9AAATAAUJ/xXnEwD9AAAuAAQKfx0AAhMACQkCFJ8SAL4BABMACQkCFJ8SAL4BAAAA.Caliste:BAAALgADCgIJAgABLgAFFAUJEwAPAOkeAA==.Calityy:BAAALgADCgYJBgABLgAFFAgJHAAEAFohAA==.Camine:BAABLgAECn81AAIQAAkJ/BwwLABNAgAQAAkJ/BwwLABNAgAAAA==.Candrabeckya:BAAALgADCgUJBQAAAA==.Carise:BAAALgAECgQJBAAAAA==.Castalasaras:BAAALgAECgYJDwAAAA==.Castorsilver:BAAALgAECgEJAQAAAA==.',
Ce='Certified:BAAALgAFFAMJAwAAAA==.',
Ch='Charkoal:BAAALgAECgUJBQAAAA==.Chickeny:BAAALgADCgEJAQAAAA==.Choppstik:BAABLgAECn8VAAIUAAYJpQXEWgClAAAUAAYJpQXEWgClAAAAAA==.',
Co='Cocstrong:BAAALgADCgYJBQAAAA==.Coldslayerck:BAAALgAECgUJBQAAAA==.Constäntine:BAABLgAECn8eAAIVAAkJlBbLEgBDAgAVAAkJlBbLEgBDAgAAAA==.Coriolis:BAACLgAFFH8GAAIWAAMJFAmuSACkAAAWAAMJFAmuSACkAAAuAAQKf0IAAxYACAkNHEITAEMCABYACAkNHEITAEMCABcAAwmCCvEwAI8AAAAA.',
Cr='Cravedog:BAAALgAECgQJBAAAAA==.Crittycrat:BAAALgAECgUJBQAAAA==.Crowléy:BAAALgAECgYJEQAAAA==.',
Cu='Cuddlyowl:BAABLgAECn8XAAIYAAcJwQ4DqwCFAQAYAAcJwQ4DqwCFAQAAAA==.',
Da='Dagnamagus:BAAALgAECgcJDAAAAA==.Daire:BAAALgADCgYJBgAAAA==.Daliann:BAAALgAECgYJDAAAAA==.Damnation:BAAALgAECgYJCwAAAA==.Dangerduck:BAABLgAECn8fAAMXAAcJlRUPCgB+AQAXAAcJoBQPCgB+AQAWAAYJgg/VTwDqAAAAAA==.Darktruth:BAAALgADCgMJAwAAAA==.Dartes:BAABLgAECn8WAAIDAAgJaxHGWwCNAQADAAgJaxHGWwCNAQAAAA==.Dashe:BAAALgAECgcJAQAAAA==.',
De='Deathcokie:BAAALgAECgYJDgAAAA==.Deatho:BAACLgAFFH8GAAITAAMJzSbKDABXAQATAAMJzSbKDABXAQAuAAQKf0IAAxMACAn6JiUCACkDABMACAn6JiUCACkDAAYAAQkJI3OdAEoAAAAA.Deathstoned:BAAALgADCgQJBQAAAA==.Deimos:BAAALgAECgEJAgAAAA==.Deratra:BAAALgADCgUJBQAAAA==.',
Di='Diamondshard:BAAALgAECgQJCwAAAA==.Discofreezer:BAAALgAECgEJAQAAAA==.',
Dr='Draegov:BAAALgADCgYJBgAAAA==.Draeth:BAAALgADCgcJDQAAAA==.Dreadful:BAAALgAECgYJDgAAAA==.Dreylan:BAAALgADCgcJBwAAAA==.Dreyra:BAAALgADCgcJBwABLgAFFAMJCQAEANsXAA==.Drosof:BAAALgADCgYJFQAAAA==.Drow:BAAALgAECgEJAQAAAA==.',
Du='Dukalioth:BAABLgAECn8iAAIZAAcJ0BDRJwA4AQAZAAcJ0BDRJwA4AQAAAA==.Duskheart:BAAALgADCgUJBQAAAA==.',
['Dê']='Dêcay:BAACLgAFFH8aAAQBAAcJexxTBACuAQABAAUJyhlTBACuAQAQAAYJgR3DMACbAQARAAEJAACbUAAAAAAuAAQKfz0AAxAACQmOIhMYAOsCABAACAk4IhMYAOsCAAEABwnHIdoFAE4CAAAA.',
['Dö']='Döctorfate:BAABLgAECn8jAAIaAAgJ5Q3QIACLAQAaAAgJ5Q3QIACLAQAAAA==.',
Ed='Ediela:BAAALgAECgQJBAAAAA==.',
Ef='Effinsoldier:BAABLgAECn8gAAIMAAcJ3BRyeAB7AQAMAAcJ3BRyeAB7AQAAAA==.',
Eg='Egfuyun:BAAALgAECgQJBwAAAA==.',
Ek='Ekko:BAAALgADCgIJAgAAAA==.',
El='Ellyy:BAAALgAFFAEJAQAAAA==.Elvira:BAAALgAECgUJCAAAAA==.',
En='Endlessagony:BAACLgAFFH8FAAIQAAMJsxDvnQDVAAAQAAMJsxDvnQDVAAAuAAQKfycAAhAACQmoHjAgAMECABAACQmoHjAgAMECAAAA.Endlessice:BAAALgAECgYJCgAAAA==.Ennyo:BAAALgAECgcJCgAAAA==.Enyo:BAABLgAECn8xAAQHAAgJsiCkGACPAgAHAAgJsiCkGACPAgAIAAEJAAA1JwBVAAANAAIJeAZ9XgBTAAAAAA==.',
Er='Erastothenes:BAAALgAECgEJAQABLgAECgcJDAACAAAAAA==.Erathas:BAABLgAECn8ZAAIMAAkJsRHBYQC/AQAMAAkJsRHBYQC/AQAAAA==.',
Fa='Falandril:BAABLgAECn8PAAIbAAgJZhJ6HQDYAQAbAAgJZhJ6HQDYAQAAAA==.Fasriel:BAAALgAECgIJAgAAAA==.',
Fe='Feata:BAAALgAECgEJAQABLgAECgYJDAACAAAAAA==.Felston:BAAALgADCgUJBQAAAA==.',
Fi='Figment:BAAALgAECgQJBAAAAA==.Fiyero:BAABLgAECn8uAAMGAAkJ8A74KgCpAQAGAAkJ8A74KgCpAQAFAAcJwgQqJQDEAAAAAA==.',
Fl='Flagcrazed:BAAALgADCgUJBQAAAA==.Fleabath:BAABLgAECn8UAAIcAAYJ6AgWKgC8AAAcAAYJ6AgWKgC8AAABLgAECggJIAADAKUKAA==.Fluffypyro:BAAALgADCgYJBgAAAA==.',
Fo='Forëplây:BAAALgAECgYJCgAAAA==.Foughum:BAAALgADCgUJBQABLgAECgYJDAACAAAAAA==.',
Fr='Friedcheekin:BAAALgADCgUJBQAAAA==.',
Fu='Fury:BAAALgADCgEJAQAAAA==.',
Ga='Galdames:BAAALgADCgQJBAAAAA==.',
Ge='Gedien:BAAALgAECgkJEQAAAA==.Gerftrazkal:BAAALgAECgUJBQAAAA==.',
Gi='Gilforty:BAABLgAECn8YAAINAAcJ0RbzCwB8AQANAAcJ0RbzCwB8AQAAAA==.',
Gl='Glep:BAAALgAECgIJAgABLgAFFAMJBAACAAAAAA==.Gloriosa:BAABLgAECn9JAAIdAAkJlRDkLADEAQAdAAkJlRDkLADEAQAAAA==.',
Go='Gorl:BAAALgAECgEJAQAAAA==.',
Gr='Griddy:BAAALgAECgEJAQAAAA==.Grootforce:BAAALgADCgMJAwAAAA==.',
Gv='Gvendalyn:BAACLgAFFH8GAAIDAAMJDh8XRAAfAQADAAMJDh8XRAAfAQAuAAQKf0AAAgMACQmfJpoAAJcDAAMACQmfJpoAAJcDAAAA.',
Gw='Gweyn:BAAALgADCgUJCAAAAA==.',
Gy='Gyatsò:BAABLgAECn8jAAIUAAkJAxhZEwAfAgAUAAkJAxhZEwAfAgAAAA==.',
['Gø']='Gød:BAAALgADCgUJBQAAAA==.',
Ha='Hakeem:BAAALgAFFAIJBAABLgAFFAUJFQAOAPkUAA==.Harshdh:BAAALgAECgYJBgABLgAFFAMJBgAQAFMJAA==.Harshdk:BAACLgAFFH8GAAIQAAMJUwmCrADEAAAQAAMJUwmCrADEAAAuAAQKfy4AAxAACQnVHK8WALwCABAACQnVHK8WALwCABEABAmgAXJRAE0AAAAA.Harshpawz:BAAALgAECgUJBQABLgAFFAMJBgAQAFMJAA==.',
He='Helel:BAACLgAFFH8OAAIQAAMJqRnfjgDpAAAQAAMJqRnfjgDpAAAuAAQKf0gAAxAACQntIvAIACcDABAACQntIvAIACcDABEACAk+FP4aAIMBAAAA.',
Ho='Hops:BAAALgAECgIJBQAAAA==.',
Il='Illibanger:BAAALgAECgcJDAABLgAFFAMJDAAGAPIUAA==.Illifiend:BAAALgAECgYJCQABLgAECgkJLgAGAPAOAA==.',
Im='Impetuous:BAAALgADCgYJDwABLgAECggJIAADAKUKAA==.',
Ip='Ipokeu:BAAALgAECgEJAQAAAA==.',
Ja='Jabmoney:BAABLgAECn8UAAMUAAcJLiT/DAByAgAUAAcJLiT/DAByAgAeAAEJRiaSbABpAAABLgAECgcJFAAUAC4kAA==.Jaffy:BAAALgAECgYJCAAAAA==.Jamninja:BAABLgAECn8pAAIYAAkJsxu9LABkAgAYAAkJsxu9LABkAgAAAA==.Jamxd:BAAALgAECgcJBwABLgAECgkJKQAYALMbAA==.Jardalanin:BAAALgADCgEJAQAAAA==.Jaroshe:BAAALgADCgUJBQAAAA==.',
Je='Jellyfish:BAACLgAFFH8LAAIOAAUJbArfIQA3AQAOAAUJbArfIQA3AQAuAAQKfx4AAw4ACQmrEqwdAN4BAA4ACQlhDqwdAN4BABUACAlGDGQuAFUBAAAA.Jessamyn:BAAALgAECgYJCwAAAA==.',
Jh='Jhoira:BAAALgAECgYJDwAAAA==.',
Jo='Jokko:BAAALgADCgEJAgAAAA==.Jordyy:BAABLgAECn8oAAQIAAkJTiK5BwDuAQAHAAgJfSCeIQCQAgAIAAYJpiS5BwDuAQANAAIJERNKVABxAAAAAA==.',
Ka='Kaifren:BAACLgAFFH8OAAIYAAQJKhJQXgAuAQAYAAQJKhJQXgAuAQAuAAQKfx0AAhgACQmvFD1RAOUBABgACQmvFD1RAOUBAAAA.Kalifa:BAACLgAFFH8jAAMJAAgJTR5AAwCNAgAJAAgJTR5AAwCNAgAfAAEJdgE8ewAkAAAuAAQKfzcABAkACAn1I7cIAAoDAAkACAn1I7cIAAoDAB8AAQnuGEi7AEkAACAAAgmIFR5rADsAAAAA.Kalinethe:BAAALgAECgEJAgAAAA==.Karatay:BAAALgADCgQJBQAAAA==.Karrod:BAAALgAECggJEwAAAA==.Katyce:BAAALgADCgcJDQAAAA==.',
Ke='Keilani:BAAALgAECgQJBQAAAA==.',
Ki='Kikorala:BAAALgAECgIJAgAAAA==.Killeerrkap:BAAALgAECgQJBgAAAA==.Killrmiller:BAAALgADCgMJAwAAAA==.Kirajdh:BAABLgAECn8mAAIhAAkJRR1jGACAAgAhAAkJRR1jGACAAgABLgAFFAMJBAACAAAAAA==.Kittenmitten:BAAALgADCgQJBAAAAA==.Kiwaj:BAAALgAECgUJBQABLgAFFAMJBAACAAAAAA==.',
Ko='Komayetu:BAAALgAECgQJCQAAAA==.',
Kr='Kraas:BAAALgAECgEJAQAAAA==.Krateis:BAABLgAECn8pAAIiAAcJ+QRYFADgAAAiAAcJ+QRYFADgAAAAAA==.Kraéthlas:BAAALgADCgYJCgAAAA==.',
Kw='Kwonhee:BAAALgADCgMJAwAAAA==.',
La='Lanadelrey:BAAALgAECgYJAQAAAA==.Laurenth:BAAALgADCgkJFQAAAA==.Lazyace:BAAALgAECgYJCQAAAA==.',
Le='Lebenspender:BAACLgAFFH8FAAISAAMJTxS0TQC2AAASAAMJTxS0TQC2AAAuAAQKfzAAAxIACAnqIj0KAA0DABIACAnqIj0KAA0DAAoACAnoDhQ3AFgBAAAA.Lextalonis:BAAALgAECgYJCAABLgAECggJEAACAAAAAA==.',
Li='Linkstery:BAABLgAECn83AAMHAAkJbhwmIQBdAgAHAAkJJBwmIQBdAgANAAMJfRWwNADkAAAAAA==.',
Lo='Losvanknight:BAABLgAECn8jAAILAAgJJBHwDACPAQALAAgJJBHwDACPAQAAAA==.',
Lt='Lt:BAAALgADCgEJAQAAAA==.',
Lu='Lunalii:BAAALgAFFAIJAgABLgAFFAMJCAAGAI4lAA==.',
Ly='Lyathon:BAAALgADCgMJAwAAAA==.',
Ma='Macdaddy:BAAALgAECgIJAwAAAA==.Macfluffy:BAABLgAECn8VAAIeAAgJOwpZMwAwAQAeAAgJOwpZMwAwAQAAAA==.Mactacolover:BAAALgAECgQJBAAAAA==.Madbomber:BAAALgAECgcJEAAAAA==.Maeze:BAABLgAECn8gAAIDAAgJpQrFbwBcAQADAAgJpQrFbwBcAQAAAA==.Magepawk:BAAALgAECgMJAwAAAA==.Magew:BAAALgADCgQJBAAAAA==.Malandru:BAACLgAFFH8OAAMjAAYJzBTdGgBCAQAjAAUJsRLdGgBCAQAMAAIJvxvzfwCsAAAuAAQKfysAAwwACQnlImEWALsCAAwACAn0JGEWALsCACMACQlUDGQ6AJABAAAA.Mawwowow:BAACLgAFFH8GAAIhAAMJ5wucZgC5AAAhAAMJ5wucZgC5AAAuAAQKfzkAAiEACAmoG00mADACACEACAmoG00mADACAAAA.Maximillius:BAAALgAECgYJBwABLgAECggJJQAQAHgbAA==.Mayjoraid:BAAALgAECgEJAgAAAA==.',
Me='Meekah:BAACLgAFFH8VAAIOAAUJ+RT/GwB1AQAOAAUJ+RT/GwB1AQAuAAQKf1AAAg4ACQmxIBsEAFcDAA4ACQmxIBsEAFcDAAAA.Melbrosha:BAAALgAECgUJDAAAAA==.Melodine:BAAALgADCgEJAQAAAA==.Melyndia:BAAALgAECgUJBQABLgAECggJIQAfAP4fAA==.Meriks:BAAALgAECgQJDAABLgAECgUJDQACAAAAAA==.Metaliorch:BAAALgAECgQJBQAAAA==.',
Mi='Mickmonkey:BAAALgAFFAIJAgABLgAECgMJAwACAAAAAA==.Mickspooky:BAACLgAFFH8XAAMQAAUJlhVebwAdAQAQAAQJlhVebwAdAQARAAEJAAD0UwAAAAAuAAQKfzEAAxAACAmXIEopAJUCABAACAmXIEopAJUCABEAAwm4GEkzAMsAAAEuAAQKAwkDAAIAAAAA.Mickstormy:BAAALgAECgMJAwAAAA==.Mierin:BAAALgAECgQJBwAAAA==.Milfy:BAAALgADCgQJBAABLgAECgEJAQACAAAAAA==.Mintie:BAABLgAECn84AAIgAAkJWRcEDQAMAgAgAAkJWRcEDQAMAgAAAA==.',
Mo='Moozylla:BAAALgAECggJCgAAAA==.Morrïgan:BAAALgAFFAEJAwAAAA==.Mossiah:BAAALgAECgEJAQAAAA==.',
Mu='Muriggy:BAAALgADCgIJAgAAAA==.',
My='Mylarna:BAABLgAECn8vAAIKAAkJ+REtIgDQAQAKAAkJ+REtIgDQAQAAAA==.Mynx:BAABLgAECn8cAAILAAgJhSEEAwCqAgALAAgJhSEEAwCqAgAAAA==.',
['Må']='Mårsh:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîstweaver:BAAALgAECgYJCgAAAA==.',
Na='Nadira:BAAALgADCgcJDQABLgADCgkJEAACAAAAAA==.Nahkti:BAAALgADCgcJBwAAAA==.Nazarick:BAAALgAECgYJCAAAAA==.',
Ne='Neona:BAAALgAECgQJBQAAAA==.Neriv:BAABLgAECn8XAAINAAgJhw7HDwBAAQANAAgJhw7HDwBAAQAAAA==.Nexaladin:BAAALgAECgEJAgAAAA==.',
Ni='Nicor:BAAALgADCgQJBAAAAA==.Nimbus:BAAALgAECgMJBAABLgAFFAgJKAAWAPIbAA==.Nixii:BAABLgAECn87AAIJAAgJTBvzEwAxAgAJAAgJTBvzEwAxAgAAAA==.',
No='Nocticula:BAABLgAECn86AAIVAAkJXAleLgBWAQAVAAkJXAleLgBWAQAAAA==.Noriinau:BAAALgADCgIJAgAAAA==.',
Ny='Nyet:BAACLgAFFH8aAAMGAAYJbhEJEwBsAQAGAAYJbhEJEwBsAQAFAAEJYgY8QgA+AAAuAAQKfxwAAgYACQm/G1wcAGoCAAYACQm/G1wcAGoCAAAA.Nythraxia:BAAALgAECgMJAwAAAA==.Nyxiria:BAAALgADCgcJGgAAAA==.',
['Nò']='Nòir:BAAALgAECgcJCAAAAA==.',
['Nø']='Nø:BAAALgADCgMJAwAAAA==.',
Oh='Ohnarr:BAAALgAECgMJAwAAAA==.',
Ok='Oktoberfist:BAAALgAECgcJBwABLgAECggJAwACAAAAAA==.',
Or='Orine:BAABLgAECn8eAAIQAAkJgAwGfABpAQAQAAkJgAwGfABpAQAAAA==.Orion:BAAALgAFFAIJAwAAAA==.Orioz:BAACLgAFFH8TAAIPAAUJ6R5WCAAxAQAPAAUJ6R5WCAAxAQAuAAQKfyQAAg8ACAk0IvEDAOgCAA8ACAk0IvEDAOgCAAAA.',
Os='Osiras:BAAALgAECggJEAAAAA==.',
Ot='Othela:BAAALgADCgEJAQAAAA==.',
Ow='Owun:BAAALgADCgEJAQAAAA==.',
Oz='Oz:BAAALgADCgkJCgAAAA==.',
Pa='Pandapal:BAAALgAECgEJAgAAAA==.Pathbrin:BAAALgADCgEJAQAAAA==.Pauliee:BAAALgAECgcJDQAAAA==.Pawkah:BAAALgAECgEJAgAAAA==.Paytowintaxi:BAAALgADCgEJAQAAAA==.',
Pe='Peyton:BAAALgADCggJEQAAAA==.',
Ph='Phoenixmage:BAAALgAECgUJBQAAAA==.',
Pr='Protection:BAAALgADCgUJBgAAAA==.',
Ps='Psychoman:BAAALgADCgMJAwABLgAFFAUJEwAJAMAfAA==.Psychomurda:BAABLgAECn8dAAMMAAYJpAuG1ADqAAAMAAYJpAuG1ADqAAAkAAMJ/gd6PQBkAAABLgAFFAUJFQAOAPkUAA==.',
Pu='Puthealshere:BAAALgAFFAEJAQAAAA==.',
['Pü']='Pü:BAAALgADCgkJEAAAAA==.',
Ra='Raign:BAAALgAECgEJAgAAAA==.Randomfelfox:BAAALgAECgYJCAAAAA==.Ratpack:BAAALgAECggJAwAAAA==.',
Re='Renfri:BAAALgAECgYJCAAAAA==.',
Ro='Robel:BAAALgAECgUJBgAAAA==.Roflburger:BAAALgAECgcJBwAAAA==.Ronaldbruce:BAAALgAECgQJBQAAAA==.Roupert:BAAALgAECgEJBAAAAA==.Rovox:BAAALgAFFAMJBAAAAA==.',
Ru='Rustpaw:BAAALgAECgYJBgAAAA==.',
Sa='Sadness:BAAALgAFFAEJAQAAAA==.Sao:BAAALgAECgIJAgAAAA==.Sardrian:BAABLgAECn8dAAIDAAcJMAj/jgAcAQADAAcJMAj/jgAcAQAAAA==.',
Se='Seimie:BAABLgAECn8yAAINAAkJuAzsDABsAQANAAkJuAzsDABsAQAAAA==.Selithvia:BAABLgAECn8YAAIbAAgJWxFWKACLAQAbAAgJWxFWKACLAQAAAA==.Senethotsare:BAAALgAECgcJDAAAAA==.Sethen:BAAALgADCgEJAQAAAA==.',
Sh='Shaboudi:BAAALgAECgUJBwAAAA==.Shamalicious:BAAALgADCgEJAQAAAA==.Shammwow:BAAALgAECgMJBwAAAA==.Shaofikx:BAABLgAECn80AAIeAAkJng0OJACJAQAeAAkJng0OJACJAQAAAA==.Shenknarok:BAABLgAECn8vAAIcAAYJnR6mDwC2AQAcAAYJnR6mDwC2AQAAAA==.Sherryl:BAACLgAFFH8GAAIfAAMJ6wJ3VwBnAAAfAAMJ6wJ3VwBnAAAuAAQKfz8AAh8ACAmBFtYnAA8CAB8ACAmBFtYnAA8CAAAA.Shmooples:BAAALgAECgEJAQAAAA==.Shunei:BAAALgADCgQJBAAAAA==.',
Si='Siema:BAAALgAECgMJAwAAAA==.Sigurd:BAAALgADCggJBwAAAA==.',
Sk='Skdragon:BAAALgADCgMJAQAAAA==.Skyari:BAACLgAFFH8IAAIGAAMJjiVjGABNAQAGAAMJjiVjGABNAQAuAAQKfycAAwYACAmEJJsIANYCAAYACAmAJJsIANYCAAUAAQm+ItVcAGUAAAAA.Skyarii:BAAALgAECgcJDwABLgAFFAMJCAAGAI4lAA==.',
So='Songweaver:BAAALgAECgEJAgAAAA==.Soulminion:BAABLgAECn8fAAMQAAYJ6wI0DwGUAAAQAAYJuAI0DwGUAAARAAEJ5gLraQAVAAAAAA==.',
Sp='Spiritshard:BAAALgAECgQJBQAAAA==.Splashmountn:BAEALgAECgYJEAAAAA==.',
St='Sthane:BAAALgADCgEJAQAAAA==.Sthise:BAAALgAECgMJAwAAAA==.',
Su='Subtlety:BAABLgAECn8aAAIaAAkJ+yLGBADrAgAaAAkJ+yLGBADrAgAAAA==.Sulfurya:BAAALgAECgcJDwAAAA==.',
Sy='Sykodrag:BAAALgAFFAIJAgABLgAFFAUJEwAJAMAfAA==.Sykoman:BAACLgAFFH8TAAMJAAUJwB8qFwBaAQAJAAUJwB8qFwBaAQAfAAEJ5QB/egAmAAAuAAQKfygAAgkACAlwI30LAN8CAAkACAlwI30LAN8CAAAA.',
['Sì']='Sìleñtclãw:BAAALgAECgcJDgAAAA==.',
Ta='Talarina:BAAALgADCgYJBgAAAA==.Taylen:BAAALgADCgcJBwAAAA==.',
Te='Terumi:BAABLgAECn8XAAIDAAcJRQb5lQAPAQADAAcJRQb5lQAPAQAAAA==.Teverion:BAAALgADCgcJCwAAAA==.',
Th='Thesios:BAAALgAECgMJAwAAAA==.Thickthighs:BAAALgAECgEJAQAAAA==.Thiizz:BAAALgAECgYJCwAAAA==.Thizz:BAABLgAECn8fAAIGAAYJPiD/KQASAgAGAAYJPiD/KQASAgABLgAECgcJFAAUAC4kAA==.',
Ti='Tic:BAABLgAFFH8GAAIHAAMJuQMZiwCpAAAHAAMJuQMZiwCpAAAAAA==.Tinksy:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.Tionder:BAAALgAECgYJEQAAAA==.',
To='Toeto:BAAALgADCgYJBgAAAA==.Toetoeto:BAAALgAECgMJAwAAAA==.Toetoetoete:BAAALgADCgYJBgAAAA==.Tooe:BAAALgAECgMJAwAAAA==.Torquei:BAAALgAECgYJDQAAAA==.Toxious:BAAALgAECgQJBAAAAA==.',
Tp='Tpaman:BAAALgAECgYJBgAAAA==.Tpdruid:BAAALgAECgMJAwAAAA==.',
Ts='Tsjuda:BAAALgADCgEJAQAAAA==.Tsjudii:BAAALgADCgYJBgAAAA==.Tsjudilla:BAAALgADCgEJAQAAAA==.',
Tu='Tujefe:BAAALgAECgcJCwAAAA==.',
Ty='Tyllibust:BAAALgAECgEJAQAAAA==.',
Ug='Ugzlug:BAAALgADCgEJAQAAAA==.',
Un='Unholydk:BAABLgAFFH8HAAMMAAMJ5hE7ZwDZAAAMAAMJ5hE7ZwDZAAAjAAIJngBzRQBEAAABLgAFFAUJDgAfACEPAA==.',
Va='Vacuus:BAABLgAECn8mAAIIAAkJSwprDACRAQAIAAkJSwprDACRAQAAAA==.Vahldire:BAABLgAECn8VAAIYAAYJ6wnIzADzAAAYAAYJ6wnIzADzAAAAAA==.Valeri:BAAALgADCggJCwAAAA==.Varkon:BAAALgAECgYJBgAAAA==.Varn:BAAALgADCggJCAAAAA==.Varthion:BAAALgAECgYJBgAAAA==.',
Ve='Vegetas:BAAALgAECgYJBgAAAA==.Velastrasza:BAAALgADCgcJBwAAAA==.Velkethria:BAAALgAECgYJEwAAAA==.Velnyxia:BAAALgAECgQJBQAAAA==.Velovañ:BAAALgADCgEJAQAAAA==.Velthyria:BAAALgADCgkJCQAAAA==.Vestara:BAAALgAECggJCAAAAA==.Veylara:BAABLgAECn8oAAIHAAcJ7gbCogD6AAAHAAcJ7gbCogD6AAAAAA==.',
Vi='Viryda:BAAALgAECgQJBAABLgAECggJMQAgAFEKAA==.',
Wa='Waeder:BAAALgADCgkJDAAAAA==.Wartimebeast:BAAALgAECgUJEAAAAA==.',
We='Welp:BAAALgAECgEJBQAAAA==.',
Wh='Wherebear:BAAALgAECgIJAgAAAA==.',
Wi='Windwalker:BAAALgAECgcJCAAAAA==.Wisteria:BAABLgAECn9AAAMNAAgJJBvABQAJAgANAAgJJBvABQAJAgAIAAEJwwEzOAAaAAABLgAECgEJAgACAAAAAA==.',
Wo='Wompalot:BAAALgADCgQJBAAAAA==.Womplock:BAAALgAECgQJCQAAAA==.Wooly:BAAALgADCgIJAgAAAA==.',
Wr='Wrâth:BAACLgAFFH8MAAIYAAQJJgewbgALAQAYAAQJJgewbgALAQAuAAQKfzQAAhgACQlwFKFEAAoCABgACQlwFKFEAAoCAAAA.',
Wy='Wydwen:BAAALgAECgEJAQAAAA==.',
Xa='Xael:BAAALgAECgIJAgAAAA==.',
Xe='Xenro:BAAALgADCgcJBgAAAA==.',
Xi='Xirus:BAAALgADCgQJAQAAAA==.',
Xu='Xulfred:BAAALgADCgIJAgAAAA==.',
Ya='Yavana:BAAALgADCgEJAQAAAA==.',
Yo='Yoshiscookie:BAAALgADCgMJAwAAAA==.',
Zi='Zigzogg:BAAALgADCgEJAQAAAA==.Zilida:BAAALgADCgEJAQAAAA==.Ziwee:BAABLgAECn8aAAIeAAgJvBqBFQBeAgAeAAgJvBqBFQBeAgABLgAECggJGgAeALwaAA==.',
Zo='Zolvyr:BAAALgADCgMJAwAAAA==.Zorana:BAAALgADCgEJAQAAAA==.',
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
