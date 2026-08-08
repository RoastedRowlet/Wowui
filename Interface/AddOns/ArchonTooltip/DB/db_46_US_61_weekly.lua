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

local lookup = {'DeathKnight-Frost','Unknown-Unknown','Hunter-BeastMastery','Hunter-Survival','Warrior-Fury','Warrior-Arms','Warlock-Demonology','Warlock-Affliction','Druid-Balance','Shaman-Elemental','Hunter-Marksmanship','Shaman-Restoration','Warrior-Protection','Warlock-Destruction','Priest-Discipline','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Blood','Paladin-Retribution','Monk-Windwalker','Priest-Holy','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','DemonHunter-Havoc','Rogue-Subtlety','Priest-Shadow','Druid-Feral','Monk-Mistweaver','Monk-Brewmaster','Paladin-Holy','Druid-Restoration','Druid-Guardian','DemonHunter-Devourer','Rogue-Assassination','Paladin-Protection',}
local provider = {region='US',realm='Darrowmere',name='US',type='weekly',zone=46,date='2026-08-04',data={Ab='Abaddonmoon:BAABLgAECn86AAIBAAkJ1g9BAwBsAQABAAkJ1g9BAwBsAQAAAA==.Absentia:BAAALgAECgEJAQABLgAECgEJAgACAAAAAA==.',
Ad='Adassa:BAAALgAECgkJCQAAAA==.Addvar:BAAALgADCgEJAQAAAA==.Adelost:BAAALgAECgQJBQAAAA==.',
Ae='Aelîn:BAAALgAFFAEJAQAAAA==.',
Ah='Ahalina:BAAALgAECgYJCAAAAA==.Ahnari:BAACLgAFFH8FAAIDAAMJdgJ5DwDMAAADAAMJdgJ5DwDMAAAuAAQKfxUAAwMACAlAEVg9ALkBAAMACAlAEVg9ALkBAAQABAm8AoQmAIsAAAAA.Ahnjo:BAAALgAECgMJAwAAAA==.',
Ai='Ailinaa:BAACLgAFFH8uAAMFAAkJTxoiBQD1AQAFAAkJFBgiBQD1AQAGAAYJvhx7CQC0AQAuAAQKfyAAAwUACQkkH8kVAJ8CAAUACAkpH8kVAJ8CAAYABAnjF1YvAAwBAAAA.',
Ak='Akalifato:BAACLgAFFH8KAAMHAAMJyx43YwABAQAHAAMJyx43YwABAQAIAAEJBBKJIQBPAAAuAAQKfxgAAgcABwkBG389AOYBAAcABwkBG389AOYBAAEuAAUUCQkjAAkATR4A.Akroma:BAAALgAECgIJBQAAAA==.',
Al='Alariya:BAAALgAECgUJBQAAAA==.Alerat:BAAALgAECgQJBQABLgAECgkJSgAKALAYAA==.Alistin:BAABLgAECn8dAAMEAAkJHBaHFAAAAgAEAAkJnxKHFAAAAgADAAIJUiGSJAC/AAAAAA==.Alistín:BAAALgAECgEJAQAAAA==.Alistïn:BAAALgAECgEJAwAAAA==.Alone:BAAALgADCgQJAwAAAA==.Alstir:BAAALgAECgEJAQAAAA==.',
Am='Amaryllis:BAAALgAECgEJAQAAAA==.Ambivalent:BAAALgAECgQJBgAAAA==.',
Ar='Aradin:BAAALgAECgMJBAAAAA==.Archanfel:BAACLgAFFH8NAAIEAAMJDAphDQDEAAAEAAMJDAphDQDEAAAuAAQKf0UAAwQACQnfE98YANkBAAQACQn0Et8YANkBAAsAAwlyEToiAJ8AAAAA.Archwimonde:BAAALgADCgMJAwAAAA==.Argasha:BAAALgADCgUJBQAAAA==.',
As='Asriel:BAAALgAECgcJDQAAAA==.',
At='Atraxa:BAAALgAECgYJDQAAAA==.',
Aw='Awsomweorc:BAAALgADCgEJAQAAAA==.',
Ax='Axies:BAAALgAECgEJAQABLgAECgQJBwACAAAAAA==.',
Ay='Ayurvedas:BAAALgAECgIJAgAAAA==.',
Az='Azar:BAAALgADCgUJBQABLgAECgEJAQACAAAAAA==.',
Ba='Bandie:BAABLgAECn8aAAMMAAgJkxxcBQARAgAMAAcJNh1cBQARAgAKAAEJcQkAAAAAAAAAAA==.Barksalot:BAAALgAECgcJBwAAAA==.Barrakum:BAAALgAECgUJDgAAAA==.Bastet:BAAALgADCgUJBQAAAA==.Bayn:BAAALgAECgEJAgAAAA==.',
Be='Beartho:BAAALgAECggJCQABLgAFFAMJDQANAM0mAA==.Beeftruck:BAACLgAFFH8QAAMGAAMJih32DQDeAAAGAAMJlBb2DQDeAAAFAAMJAxT0NgDXAAAuAAQKfzIAAwYACQlBIZAFALACAAYACQlzH5AFALACAAUABwn7HlUvAJIBAAAA.Belletrixx:BAABLgAECn8UAAMHAAYJOAx/xwDAAAAHAAYJggt/xwDAAAAOAAMJhQW9PAA5AAAAAA==.Bellonä:BAAALgAECgEJAQAAAA==.Berried:BAACLgAFFH8SAAIPAAMJ4B2LEwD6AAAPAAMJ4B2LEwD6AAAuAAQKf3UAAg8ACQlFJGQAALgDAA8ACQlFJGQAALgDAAAA.',
Bi='Bigred:BAAALgAECgMJAwAAAA==.Biigmâc:BAABLgAECn8WAAIKAAcJ6QUdSwAbAQAKAAcJ6QUdSwAbAQAAAA==.Biminem:BAABLgAECn8dAAIQAAgJbxXKDwC1AQAQAAgJbxXKDwC1AQAAAA==.Bitomax:BAAALgAECgUJBQAAAA==.',
Bl='Black:BAAALgAECgYJDAAAAA==.Blackwidow:BAAALgAECgMJAwAAAA==.Bloodshöt:BAABLgAECn8fAAMRAAgJdhu7OQAZAgARAAgJdhu7OQAZAgASAAEJXgcEagAVAAABLgAECgkJJwAFAIUYAA==.Bloôdymary:BAAALgAECgcJDAAAAA==.Bluntforce:BAAALgADCgkJCQAAAA==.',
Bo='Bodak:BAABLgAECn8bAAIMAAYJ5hnRNwCjAQAMAAYJ5hnRNwCjAQAAAA==.Boricua:BAAALgAECgEJAgAAAA==.',
Br='Brakun:BAAALgAECgQJBwAAAA==.Briline:BAAALgAECgEJAQAAAA==.Brolly:BAAALgAECgkJAgAAAA==.Bronwyn:BAAALgAFFAEJAQAAAA==.Broris:BAAALgAECgMJAwABLgAECgYJDAACAAAAAA==.Brucewii:BAAALgAECgUJBQAAAA==.Brunn:BAAALgAECgYJDAAAAA==.',
Ca='Calamari:BAAALgAECgMJBAAAAA==.Calistarius:BAACLgAFFH8NAAINAAUJ/xW+FAD7AAANAAUJ/xW+FAD7AAAuAAQKfx0AAg0ACQkCFO8SAL0BAA0ACQkCFO8SAL0BAAAA.Caliste:BAAALgADCgIJAgABLgAFFAUJEwAQAOkeAA==.Calityy:BAAALgADCgYJBgABLgAFFAkJHQAEAPwgAA==.Camine:BAABLgAECn81AAIRAAkJ/BzaLABMAgARAAkJ/BzaLABMAgAAAA==.Candrabeckya:BAAALgADCgUJBQAAAA==.Carise:BAAALgAECgQJBAAAAA==.Castalasaras:BAABLgAECn8lAAIRAAcJygfcGwDNAAARAAcJygfcGwDNAAAAAA==.Castorsilver:BAAALgAECgEJAQAAAA==.Caylin:BAAALgADCgcJBwABLgAECgUJCgACAAAAAA==.',
Ce='Certified:BAAALgAFFAMJAwAAAA==.',
Ch='Charkoal:BAAALgAECgUJBQAAAA==.Cheyane:BAABLgAECn8cAAITAAYJ7QZL8ADKAAATAAYJ7QZL8ADKAAAAAA==.Chickeny:BAAALgADCgEJAQAAAA==.Choppstik:BAABLgAECn8VAAIUAAYJpQW5XACjAAAUAAYJpQW5XACjAAAAAA==.Chåos:BAAALgAECgMJBQAAAA==.',
Co='Cocstrong:BAAALgADCggJDAAAAA==.Coldslayerck:BAAALgAECgcJDAAAAA==.Coldswiftck:BAAALgADCgkJCQAAAA==.Constäntine:BAABLgAECn8hAAIVAAkJBhgjEwBCAgAVAAkJBhgjEwBCAgAAAA==.Cordélia:BAAALgAECgQJBAABLgAECgkJJAADAGoUAA==.Coriolis:BAACLgAFFH8OAAIWAAMJ9RN9HQC6AAAWAAMJ9RN9HQC6AAAuAAQKf1AAAxYACQn4GrEBADACABYACQn4GrEBADACABcAAwmCCvEwAI8AAAAA.',
Cr='Cravedog:BAAALgAECgYJDAAAAA==.Crittycrat:BAAALgAECgUJBQAAAA==.Crowléy:BAAALgAECgYJEgAAAA==.',
Cu='Cuddlyowl:BAABLgAECn8XAAIYAAcJwQ4DqwCFAQAYAAcJwQ4DqwCFAQAAAA==.',
Da='Dagnamagus:BAAALgAECgkJDgAAAA==.Daire:BAAALgADCgYJBgAAAA==.Daliann:BAAALgAECgYJDQAAAA==.Damion:BAAALgAECgUJCgAAAA==.Damnation:BAAALgAECgYJCwAAAA==.Dangerduck:BAABLgAECn8fAAMXAAcJlRUwCgB+AQAXAAcJoBQwCgB+AQAWAAYJgg/+UADrAAAAAA==.Darktruth:BAAALgADCgMJAwAAAA==.Darkwingdûck:BAAALgAECgYJBgABLgAECgkJHQAQAPgZAA==.Dartes:BAABLgAECn8WAAIDAAgJaxGqXQCNAQADAAgJaxGqXQCNAQAAAA==.Dashe:BAAALgAECgcJAQAAAA==.',
De='Deathadder:BAAALgAECgIJAgAAAA==.Deathcokie:BAAALgAECgYJDgAAAA==.Deatho:BAACLgAFFH8NAAINAAMJzSYNCABUAQANAAMJzSYNCABUAQAuAAQKf0YAAw0ACQmZJjMCACkDAA0ACQmZJjMCACkDAAUAAQkJI3OdAEoAAAAA.Deathstoned:BAAALgADCgQJBQAAAA==.Deimos:BAAALgAECgEJAgAAAA==.Deratra:BAAALgADCgUJBQAAAA==.Destrocake:BAAALgAECgEJAwABLgAFFAQJCwATAA8YAA==.',
Di='Diamondshard:BAAALgAECgQJCwAAAA==.Discofreezer:BAAALgAECgEJAQAAAA==.',
Dl='Dlgadoflpjck:BAAALgAECgQJBAAAAA==.',
Dr='Draegov:BAAALgADCgYJBgAAAA==.Draeth:BAAALgADCgcJDQAAAA==.Drash:BAAALgAECgYJCwAAAA==.Dreadful:BAAALgAECgYJDgAAAA==.Dreylan:BAAALgADCgcJBwAAAA==.Dreyra:BAAALgAFFAMJBAABLgAFFAQJDAAEAKcNAA==.Droodtrass:BAAALgAFFAMJBAAAAA==.Drosof:BAAALgAECgEJAQAAAA==.Drow:BAAALgAECgEJAQAAAA==.',
Du='Dukalioth:BAABLgAECn8iAAIZAAcJ0BDdKAA2AQAZAAcJ0BDdKAA2AQAAAA==.Duris:BAAALgAECgEJAwAAAA==.Duskheart:BAAALgADCgUJBQAAAA==.',
['Dê']='Dêcay:BAACLgAFFH8aAAQBAAcJexwDBQCqAQABAAUJyhkDBQCqAQARAAYJgR0gNACZAQASAAEJAACHUwAAAAAuAAQKfz0AAxEACQmOIhMYAOsCABEACAk4IhMYAOsCAAEABwnHIQMGAEwCAAAA.',
['Dö']='Döctorfate:BAACLgAFFH8MAAIaAAMJuQr/FgDGAAAaAAMJuQr/FgDGAAAuAAQKfzEAAhoACQk2DmYDAJ4BABoACQk2DmYDAJ4BAAAA.',
Ed='Ediela:BAAALgAECgQJBAAAAA==.',
Ef='Effinsoldier:BAABLgAECn8yAAITAAkJQhojBgAtAgATAAkJQhojBgAtAgAAAA==.',
Eg='Egfuyun:BAAALgAECgQJBwAAAA==.',
Ek='Ekko:BAAALgAECgIJAgAAAA==.',
El='Ellyy:BAAALgAFFAEJAQAAAA==.Elvira:BAAALgAECgcJDQAAAA==.',
En='Endlessagony:BAACLgAFFH8HAAIRAAMJsxAQowDRAAARAAMJsxAQowDRAAAuAAQKfycAAhEACQmoHjAgAMECABEACQmoHjAgAMECAAAA.Endlessice:BAAALgAECgYJCgAAAA==.Ennyo:BAAALgAECgcJCgAAAA==.Enyo:BAACLgAFFH8HAAIHAAIJxxYplgCWAAAHAAIJxxYplgCWAAAuAAQKfzQABAcACQmnHzYZAI0CAAcACQmnHzYZAI0CAAgAAQkAADUnAFUAAA4AAgl4Bn1eAFMAAAAA.',
Er='Erastothenes:BAAALgAECgEJAQABLgAECgkJEgACAAAAAA==.Erathas:BAABLgAECn8ZAAITAAkJsRHBYQC/AQATAAkJsRHBYQC/AQAAAA==.Ermagerd:BAAALgAECgkJCQAAAA==.',
Fa='Faelissel:BAAALgADCgUJBQABLgAECgUJCgACAAAAAA==.Falandril:BAABLgAECn8PAAIbAAgJZhJJHgDTAQAbAAgJZhJJHgDTAQAAAA==.Fasriel:BAAALgAECgUJBgAAAA==.',
Fe='Feata:BAAALgAECgEJAQABLgAECgYJDAACAAAAAA==.Felston:BAAALgADCgUJBQAAAA==.',
Fi='Figment:BAAALgAECgYJCwAAAA==.Fineapple:BAAALgAECgkJBwAAAA==.Fiyero:BAABLgAECn8uAAMFAAkJ8A5aLACiAQAFAAkJ8A5aLACiAQAGAAcJwgQqJQDEAAAAAA==.',
Fl='Flagcrazed:BAAALgADCgUJBQAAAA==.Fleabath:BAABLgAECn8hAAIcAAYJZhSjBAAnAQAcAAYJZhSjBAAnAQABLgAECgkJJAADACUNAA==.Fluffypyro:BAAALgADCgYJBgAAAA==.',
Fo='Forëplây:BAAALgAECgYJCgAAAA==.Foughum:BAAALgADCgUJBQABLgAECgYJDAACAAAAAA==.',
Fr='Friedcheekin:BAAALgADCgUJBQAAAA==.',
Fu='Fury:BAAALgADCgEJAQAAAA==.',
Ga='Galdames:BAAALgAECgEJAQAAAA==.',
Ge='Gedien:BAAALgAECgkJEQAAAA==.Gerftrazkal:BAAALgAECgUJBQAAAA==.',
Gi='Gilforty:BAABLgAECn8bAAIOAAcJ/RdFDAB7AQAOAAcJ/RdFDAB7AQAAAA==.',
Gl='Glep:BAAALgAECgIJAgABLgAFFAMJBAACAAAAAA==.Gloomkin:BAAALgAECgEJAQAAAA==.Gloriosa:BAABLgAECn9JAAIdAAkJlRDULQDGAQAdAAkJlRDULQDGAQAAAA==.',
Go='Gonk:BAAALgAECgMJBAABLgAECgUJBwACAAAAAA==.Gorando:BAAALgADCgIJAgAAAA==.Gorl:BAAALgAECgEJAQAAAA==.Goél:BAAALgAECgQJBAAAAA==.',
Gr='Griddy:BAAALgAECgEJAQAAAA==.Grootforce:BAAALgADCgMJAwAAAA==.',
Gu='Gulithark:BAAALgAECgIJAgABLgAECgUJCgACAAAAAA==.Gump:BAAALgAECgQJCwABLgAFFAMJEAAGAIodAA==.',
Gv='Gvendalyn:BAACLgAFFH8XAAIDAAQJnh9gFwBeAQADAAQJnh9gFwBeAQAuAAQKf2AAAgMACQm0JqAAAJcDAAMACQm0JqAAAJcDAAAA.',
Gw='Gweyn:BAAALgADCgUJCAAAAA==.',
Gy='Gyatsò:BAABLgAECn8jAAIUAAkJAxihEwAfAgAUAAkJAxihEwAfAgAAAA==.',
['Gø']='Gød:BAAALgADCgUJBQAAAA==.',
Ha='Hakeem:BAAALgAFFAIJBAABLgAFFAUJGAAPAGwVAA==.Harshdh:BAAALgAECgYJBgABLgAFFAMJBwARAFMJAA==.Harshdk:BAACLgAFFH8HAAIRAAMJUwkbsgDAAAARAAMJUwkbsgDAAAAuAAQKfy4AAxEACQnVHC0XALsCABEACQnVHC0XALsCABIABAmgAblSAEwAAAAA.Harshpawz:BAAALgAECgUJBQABLgAFFAMJBwARAFMJAA==.',
He='Helel:BAACLgAFFH8XAAIRAAMJ3x4KMQAMAQARAAMJ3x4KMQAMAQAuAAQKf1AAAxEACQntIkgJACYDABEACQntIkgJACYDABIACAk6FnAbAIEBAAAA.',
Ho='Holyhotcakes:BAAALgAECgEJAQAAAA==.Hops:BAAALgAECgIJBgAAAA==.',
Il='Illibanger:BAAALgAECgkJDwABLgAFFAMJEAAGAIodAA==.Illidon:BAAALgADCgYJBgAAAA==.Illifiend:BAAALgAECgYJCQABLgAECgkJLgAFAPAOAA==.',
Im='Impetuous:BAAALgADCgYJDwABLgAECgkJJAADACUNAA==.',
Ip='Ipokeu:BAAALgAECgEJAQAAAA==.',
Ja='Jabmoney:BAABLgAECn8WAAMUAAkJCCM/DQBxAgAUAAkJCCM/DQBxAgAeAAEJRia0bQBpAAABLgAFFAIJAgACAAAAAA==.Jabohabo:BAAALgAECgQJBgABLgAFFAIJAgACAAAAAA==.Jaffy:BAABLgAECn8cAAIFAAgJHhGGBgB4AQAFAAgJHhGGBgB4AQAAAA==.Jamninja:BAACLgAFFH8GAAIYAAIJByAeTwCUAAAYAAIJByAeTwCUAAAuAAQKfykAAhgACQmzG14tAGQCABgACQmzG14tAGQCAAAA.Jamxd:BAAALgAECgcJCAABLgAFFAIJBgAYAAcgAA==.Jardalanin:BAAALgADCgEJAQAAAA==.Jaroshe:BAAALgADCgUJBQAAAA==.Jaxxson:BAAALgADCgUJBgAAAA==.',
Je='Jellyfish:BAACLgAFFH8LAAIPAAUJbAocIwA2AQAPAAUJbAocIwA2AQAuAAQKfx4AAw8ACQmrElQeANsBAA8ACQlhDlQeANsBABUACAlGDDAvAFUBAAAA.Jessamyn:BAABLgAECn8eAAIfAAkJZhLTAgAcAgAfAAkJZhLTAgAcAgAAAA==.',
Jh='Jhoira:BAAALgAECgYJDwAAAA==.',
Ji='Jimmy:BAAALgAECgEJAQAAAA==.Jingu:BAAALgAECgEJAQAAAA==.',
Jo='Jokko:BAAALgADCgEJAgAAAA==.Jordyy:BAABLgAECn8oAAQIAAkJTiLyBwDtAQAHAAgJfSCeIQCQAgAIAAYJpiTyBwDtAQAOAAIJERNKVABxAAAAAA==.',
Ka='Kaifren:BAACLgAFFH8OAAIYAAQJKhItYQAfAQAYAAQJKhItYQAfAQAuAAQKfx0AAhgACQmvFKFSAOQBABgACQmvFKFSAOQBAAAA.Kalifa:BAACLgAFFH8jAAMJAAgJTR7RAwCIAgAJAAgJTR7RAwCIAgAgAAEJdgH5fQAkAAAuAAQKfzcABAkACAn1I7cIAAoDAAkACAn1I7cIAAoDACAAAQnuGBa9AEkAACEAAgmIFaFuADsAAAAA.Kalinethe:BAAALgAECgEJAgAAAA==.Karatay:BAAALgADCgQJBQAAAA==.Karrod:BAABLgAECn8UAAMSAAgJmwpMOACzAAASAAYJywtMOACzAAARAAMJYgcqGgGLAAAAAA==.Katyce:BAAALgADCgcJDQAAAA==.',
Ke='Keilani:BAAALgAECgQJBQAAAA==.',
Kh='Khrysus:BAAALgAECgUJBQAAAA==.',
Ki='Kikorala:BAAALgAECgIJAgAAAA==.Killeerrkap:BAAALgAECgQJBgAAAA==.Killrmiller:BAAALgADCgMJAwAAAA==.Kirajdh:BAABLgAECn8mAAIiAAkJRR3GGACAAgAiAAkJRR3GGACAAgABLgAFFAMJBAACAAAAAA==.Kittenmitten:BAAALgADCgQJBAAAAA==.Kiv:BAAALgAFFAQJBAABLgAFFAYJJgAgACscAA==.Kiwaj:BAAALgAECgUJBQABLgAFFAMJBAACAAAAAA==.',
Kn='Knoa:BAAALgAECgkJDAAAAA==.',
Ko='Komayetu:BAAALgAECgUJCgAAAA==.',
Kr='Kraas:BAAALgAECgEJAgAAAA==.Krateis:BAABLgAECn8pAAIjAAcJ+QSYFADgAAAjAAcJ+QSYFADgAAAAAA==.Kraéthlas:BAAALgADCgYJCgAAAA==.',
Kv='Kvit:BAAALgAECgEJAQAAAA==.',
Kw='Kwonhee:BAAALgADCgMJAwAAAA==.',
La='Lanadelrey:BAAALgAECggJAQAAAA==.Laurenth:BAAALgADCgkJFQAAAA==.Lazyace:BAAALgAECgYJCQAAAA==.',
Le='Lebenspender:BAACLgAFFH8KAAIMAAMJnxvQJAC4AAAMAAMJnxvQJAC4AAAuAAQKfzoAAwwACAnvIpgKAA0DAAwACAnvIpgKAA0DAAoACAnoDhU4AFgBAAAA.Lextalonis:BAAALgAECgYJCAABLgAECggJEAACAAAAAA==.',
Li='Linkstery:BAABLgAECn83AAMHAAkJbhy+IQBbAgAHAAkJJBy+IQBbAgAOAAMJfRWwNADkAAAAAA==.Lisabolin:BAAALgADCgEJAgAAAA==.',
Lo='Losvanknight:BAABLgAECn8jAAILAAgJJBEqDQCPAQALAAgJJBEqDQCPAQAAAA==.',
Lt='Lt:BAAALgADCgEJAQAAAA==.',
Lu='Lunalii:BAACLgAFFH8HAAIBAAMJSR5tCAAVAQABAAMJSR5tCAAVAQAuAAQKfxUAAwEACAlWIogEAIACAAEACAlWIogEAIACABEAAQmOFLZmAT0AAAEuAAUUAwkIAAUAjiUA.',
Ly='Lyathon:BAAALgADCgMJAwAAAA==.',
['Lï']='Lïllïë:BAAALgADCgUJBQABLgAECggJGgAMAJMcAA==.',
Ma='Macdaddy:BAAALgAFFAEJAQAAAA==.Macfluffy:BAABLgAECn8VAAIeAAgJOwrnMwAwAQAeAAgJOwrnMwAwAQAAAA==.Macpendragon:BAAALgAECgUJBQAAAA==.Mactacolover:BAAALgAECgQJBAAAAA==.Madbomber:BAAALgAFFAEJBAAAAA==.Maeze:BAABLgAECn8kAAIDAAkJJQ3qWgCUAQADAAkJJQ3qWgCUAQAAAA==.Maezer:BAAALgAECgYJBgABLgAECgkJJAADACUNAA==.Magepawk:BAAALgAECgMJAwAAAA==.Magew:BAAALgADCgQJBAAAAA==.Malandru:BAACLgAFFH8TAAMfAAkJ4xHfDAAqAQAfAAgJNRDfDAAqAQATAAIJvxsPhACsAAAuAAQKfy0AAxMACQnlIgIXALkCABMACAn0JAIXALkCAB8ACQlUDGQ6AJABAAAA.Mawwow:BAABLgAFFH8HAAITAAMJVR7dHwANAQATAAMJVR7dHwANAQABLgAFFAMJCAAiAMgPAA==.Mawwowow:BAACLgAFFH8IAAIiAAMJyA9haQC5AAAiAAMJyA9haQC5AAAuAAQKfzwAAiIACQlGG+kmADACACIACQlGG+kmADACAAAA.Maximillius:BAAALgAECgYJBwABLgAECggJJgARAFEdAA==.Mayjoraid:BAAALgAECgEJAgAAAA==.',
Me='Meekah:BAACLgAFFH8YAAIPAAUJbBUBHQB0AQAPAAUJbBUBHQB0AQAuAAQKf1AAAg8ACQmxIDwEAFQDAA8ACQmxIDwEAFQDAAAA.Melbrosha:BAAALgAECgUJDAAAAA==.Melodine:BAAALgADCgEJAQAAAA==.Meriks:BAAALgAECgQJDAABLgAECgUJDQACAAAAAA==.Metaliorch:BAABLgAECn8VAAIKAAcJiwLlFwBzAAAKAAcJiwLlFwBzAAAAAA==.',
Mi='Mickmonkey:BAAALgAFFAMJAwABLgAECgMJAwACAAAAAA==.Mickspooky:BAACLgAFFH8XAAMRAAUJlhVXcwAaAQARAAQJlhVXcwAaAQASAAEJAAABVwAAAAAuAAQKfzEAAxEACAmXIEopAJUCABEACAmXIEopAJUCABIAAwm4GAo0AMoAAAEuAAQKAwkDAAIAAAAA.Mickstormy:BAAALgAECgMJAwAAAA==.Mierin:BAAALgAECgQJBwAAAA==.Milfy:BAAALgADCgQJBAABLgAECgEJAQACAAAAAA==.Mintie:BAABLgAECn84AAIhAAkJWRdHDQANAgAhAAkJWRdHDQANAgAAAA==.Miste:BAAALgAECgEJBAAAAA==.',
Mo='Moozylla:BAAALgAFFAEJAwAAAA==.Morbitaldo:BAAALgADCgEJAQAAAA==.Morrïgan:BAABLgAECn8YAAIRAAgJtRdDCAC9AQARAAgJtRdDCAC9AQAAAA==.Mossiah:BAAALgAECgEJAQAAAA==.',
My='Mylarna:BAABLgAECn9KAAIKAAkJsBi8AgA5AgAKAAkJsBi8AgA5AgAAAA==.Mynx:BAABLgAECn8hAAILAAgJLiPLAgC5AgALAAgJLiPLAgC5AgAAAA==.',
['Må']='Mårsh:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîstweaver:BAAALgAECgYJDAAAAA==.',
Na='Nadira:BAAALgAECgEJAQABLgAECgkJNQASAKwVAA==.Nahkti:BAAALgADCgcJBwAAAA==.Nazarick:BAAALgAECgYJCAABLgAFFAIJAgACAAAAAA==.',
Ne='Neona:BAAALgAECgQJBQAAAA==.Neriv:BAABLgAECn8XAAIOAAgJhw4kEAA/AQAOAAgJhw4kEAA/AQAAAA==.Nexaladin:BAAALgAECgEJAwAAAA==.Nexiroth:BAAALgAECgEJAQAAAA==.',
Ni='Nicor:BAAALgADCgQJBAAAAA==.Nightowls:BAAALgAECgEJAQAAAA==.Nimbus:BAAALgAECgMJBAABLgAFFAkJQgAWAEEdAA==.Nixii:BAACLgAFFH8LAAIJAAMJQxEiFwDAAAAJAAMJQxEiFwDAAAAuAAQKf0kAAgkACQnyGwkDABQCAAkACQnyGwkDABQCAAAA.',
No='Nocticula:BAABLgAECn86AAIVAAkJXAkjLwBVAQAVAAkJXAkjLwBVAQAAAA==.Noriinau:BAAALgADCgIJAgAAAA==.',
Ny='Nyet:BAACLgAFFH8iAAMFAAkJXBGTBQDjAQAFAAkJXBGTBQDjAQAGAAEJYgaPRAA9AAAuAAQKfxwAAgUACQm/G1wcAGoCAAUACQm/G1wcAGoCAAAA.Nythraxia:BAAALgAECgMJAwAAAA==.Nyxiria:BAAALgADCgcJGgAAAA==.',
['Nò']='Nòir:BAAALgAECgcJCAAAAA==.',
['Nø']='Nø:BAAALgADCgMJAwAAAA==.',
Oh='Ohnarr:BAAALgAECgMJBAAAAA==.',
Ok='Oktoberfist:BAAALgAECgcJBwABLgAFFAEJAQACAAAAAA==.Oku:BAAALgAECgQJBAAAAA==.',
Or='Orine:BAABLgAECn8eAAIRAAkJgAwWfgBnAQARAAkJgAwWfgBnAQAAAA==.Orion:BAAALgAFFAIJBAAAAA==.Orioz:BAACLgAFFH8TAAIQAAUJ6R6zCAAuAQAQAAUJ6R6zCAAuAQAuAAQKfyQAAhAACAk0IvEDAOgCABAACAk0IvEDAOgCAAAA.',
Os='Oshara:BAAALgAECgMJAwAAAA==.Osiras:BAAALgAECggJEAAAAA==.',
Ot='Othela:BAAALgADCgEJAQAAAA==.',
Ow='Owun:BAAALgADCgEJAQAAAA==.',
Oz='Oz:BAAALgADCgkJCgAAAA==.',
Pa='Pandapal:BAAALgAECgEJAgAAAA==.Papermoon:BAAALgAECgMJAwAAAA==.Pathbrin:BAAALgADCgEJAQAAAA==.Pauliee:BAAALgAECggJEAAAAA==.Pawkah:BAAALgAECgEJAgAAAA==.Paytowintaxi:BAAALgADCgEJAQAAAA==.',
Pe='Peyton:BAAALgADCggJEQAAAA==.',
Ph='Phoenixmage:BAAALgAECgUJBQAAAA==.',
Pr='Protection:BAAALgADCgUJBgAAAA==.',
Ps='Psychoman:BAAALgADCgMJAwABLgAFFAgJIgAJADMhAA==.Psychomurda:BAABLgAECn8dAAMTAAYJpAvj2ADnAAATAAYJpAvj2ADnAAAkAAMJ/gdPPgBkAAABLgAFFAUJGAAPAGwVAA==.',
Pu='Puthealshere:BAAALgAFFAEJAQAAAA==.',
['Pü']='Pü:BAAALgAECgEJAQABLgAECgkJNQASAKwVAA==.',
Ra='Radio:BAAALgAECgEJAgAAAA==.Raign:BAAALgAECgEJAgAAAA==.Randomfelfox:BAAALgAECgYJDQAAAA==.Ratpack:BAAALgAFFAEJAQAAAA==.',
Re='Renfri:BAABLgAECn8cAAIYAAgJ2QwsEgBCAQAYAAgJ2QwsEgBCAQAAAA==.',
Ro='Robel:BAAALgAECgUJCQAAAA==.Roflburger:BAABLgAECn8dAAIQAAkJ+BkQAQBYAgAQAAkJ+BkQAQBYAgAAAA==.Ronaldbruce:BAAALgAECgQJBQAAAA==.Roupert:BAAALgAECgEJBAAAAA==.Rovox:BAAALgAFFAMJBAAAAA==.',
Ru='Runebane:BAAALgADCgMJAwAAAA==.Rustpaw:BAAALgAECgYJBgAAAA==.',
Sa='Sadness:BAAALgAFFAEJAQAAAA==.Sao:BAAALgAECgIJAgAAAA==.Sardrian:BAABLgAECn8jAAIDAAcJQAnBkQAcAQADAAcJQAnBkQAcAQAAAA==.',
Sc='Scurgedeath:BAAALgAECgEJAQABLgAECgkJHwAaAOoSAA==.',
Se='Seimie:BAABLgAECn9YAAIOAAkJFxPMAQDDAQAOAAkJFxPMAQDDAQAAAA==.Selithvia:BAABLgAECn8YAAIbAAgJWxHaKACJAQAbAAgJWxHaKACJAQAAAA==.Senethotsare:BAAALgAECgkJEgAAAA==.Sethen:BAAALgAECgEJAQAAAA==.',
Sh='Shaboudi:BAAALgAECgUJBwAAAA==.Shamalicious:BAAALgADCgEJAQAAAA==.Shammwow:BAAALgAECgMJBwAAAA==.Shaofikx:BAABLgAECn80AAIeAAkJng1oJACJAQAeAAkJng1oJACJAQAAAA==.Shenknarok:BAABLgAECn8vAAIcAAYJnR4NEAC2AQAcAAYJnR4NEAC2AQAAAA==.Sherryl:BAACLgAFFH8LAAIgAAMJXwcGIABzAAAgAAMJXwcGIABzAAAuAAQKf0wAAiAACQkKFUIFAKwBACAACQkKFUIFAKwBAAAA.Shmooples:BAAALgAECgEJAQAAAA==.Shunei:BAAALgADCgQJBAAAAA==.',
Si='Siema:BAAALgAECgMJAwAAAA==.Sigurd:BAAALgADCggJBwAAAA==.',
Sk='Skdk:BAAALgADCgEJAQAAAA==.Skdragon:BAAALgADCgMJAQAAAA==.Skyari:BAACLgAFFH8IAAIFAAMJjiWiGQBMAQAFAAMJjiWiGQBMAQAuAAQKfysAAwUACQnjItkIANQCAAUACQngItkIANQCAAYAAQm+IilfAGQAAAAA.Skyarii:BAAALgAFFAEJAgABLgAFFAMJCAAFAI4lAA==.Skylaar:BAAALgAECgMJAwAAAA==.',
So='Songweaver:BAAALgAECgEJAgAAAA==.Soulminion:BAABLgAECn8fAAMRAAYJ6wI5FAGTAAARAAYJuAI5FAGTAAASAAEJ5gKVagAVAAAAAA==.',
Sp='Spiritshard:BAAALgAECgQJBgAAAA==.Splashmountn:BAEALgAECgYJEAAAAA==.Spriggens:BAAALgAFFAEJAgABLgAFFAQJFwADAJ4fAA==.',
St='Sthane:BAAALgADCgEJAQAAAA==.Sthise:BAAALgAECgMJAwAAAA==.Sturer:BAAALgADCgEJAQAAAA==.',
Su='Subtlety:BAABLgAECn8aAAIaAAkJ+yLsBADpAgAaAAkJ+yLsBADpAgAAAA==.Sulfurya:BAABLgAECn8VAAIZAAkJgRmPAwDWAQAZAAkJgRmPAwDWAQAAAA==.',
Sy='Sykodrag:BAAALgAFFAMJBAABLgAFFAgJIgAJADMhAA==.Sykoman:BAACLgAFFH8iAAMJAAgJMyF/BAAnAgAJAAgJMyF/BAAnAgAgAAEJ5QA7fQAmAAAuAAQKfygAAgkACAlwI30LAN8CAAkACAlwI30LAN8CAAAA.',
['Sì']='Sìleñtclãw:BAAALgAECgcJDgAAAA==.',
Ta='Talarina:BAAALgADCgYJBgAAAA==.Taylen:BAAALgADCgcJBwAAAA==.',
Te='Terumi:BAABLgAECn8tAAIDAAcJ8AldHwDcAAADAAcJ8AldHwDcAAAAAA==.Teverion:BAAALgADCgcJCwAAAA==.',
Th='Thesios:BAAALgAECgMJAwAAAA==.Thickthighs:BAAALgAECgEJAQAAAA==.Thiizz:BAAALgAFFAIJAgAAAA==.Thizz:BAABLgAECn8fAAIFAAYJPiD/KQASAgAFAAYJPiD/KQASAgABLgAFFAIJAgACAAAAAA==.Thracious:BAAALgAECgEJAQAAAA==.',
Ti='Tic:BAABLgAFFH8JAAIHAAMJnQY9SgBzAAAHAAMJnQY9SgBzAAAAAA==.Tinksy:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.Tionder:BAAALgAECgYJEQAAAA==.',
To='Toeto:BAAALgADCgYJBgAAAA==.Toetoeto:BAAALgAECgMJAwAAAA==.Toetoetoete:BAAALgADCgYJBgAAAA==.Tooe:BAAALgAECgMJAwAAAA==.Torquei:BAABLgAECn8UAAIDAAYJawt3KwCbAAADAAYJawt3KwCbAAAAAA==.Toxious:BAAALgAECgQJBAAAAA==.',
Tp='Tpaman:BAAALgAECgYJBgAAAA==.Tpdruid:BAAALgAECgMJAwAAAA==.',
Ts='Tsjuda:BAAALgADCgEJAQAAAA==.Tsjudii:BAAALgADCgYJBgAAAA==.Tsjudilla:BAAALgADCgEJAQAAAA==.',
Tu='Tujefe:BAAALgAECgcJCwAAAA==.',
Ty='Tyllibust:BAAALgAECgEJAQAAAA==.Tylorialin:BAAALgAECgUJBQABLgAFFAMJEAAGAIodAA==.',
Ug='Ugzlug:BAAALgADCgEJAQAAAA==.',
Un='Unholydk:BAABLgAFFH8HAAMTAAMJ5hExawDZAAATAAMJ5hExawDZAAAfAAIJngAARwBEAAABLgAFFAcJEQAgAI4WAA==.',
Va='Vacuus:BAABLgAECn8rAAIIAAkJWgrRDACPAQAIAAkJWgrRDACPAQAAAA==.Vahldire:BAABLgAECn85AAIYAAkJPw5XDACRAQAYAAkJPw5XDACRAQAAAA==.Valeri:BAAALgADCggJCwAAAA==.Valor:BAABLgAECn8UAAIkAAgJhhNwAwCTAQAkAAgJhhNwAwCTAQAAAA==.Varkon:BAAALgAECgYJBgAAAA==.Varn:BAAALgADCggJCAAAAA==.Varthion:BAAALgAECgYJBgAAAA==.',
Ve='Vegetas:BAAALgAECgYJBwAAAA==.Velastrasza:BAAALgADCgcJBwAAAA==.Velkethria:BAAALgAECgYJEwAAAA==.Velnythra:BAAALgAECgQJBQAAAA==.Velovañ:BAAALgADCgEJAQAAAA==.Velthyria:BAAALgADCgkJCQAAAA==.Vestara:BAAALgAECggJCAAAAA==.Veylara:BAABLgAECn8oAAIHAAcJ7gbYpAD3AAAHAAcJ7gbYpAD3AAAAAA==.',
Vi='Viryda:BAAALgAECgQJBAABLgAECggJMQAhAFEKAA==.',
Wa='Waeder:BAAALgADCgkJDAAAAA==.Wartimebeast:BAAALgAECgUJEAAAAA==.',
We='Welp:BAAALgAECgEJBQAAAA==.',
Wh='Wherebear:BAAALgAECgIJAgAAAA==.',
Wi='Windwalker:BAAALgAECgcJCAAAAA==.Wisteria:BAABLgAECn9FAAMOAAkJmx/1BQAHAgAOAAkJmx/1BQAHAgAIAAEJwwEzOAAaAAABLgAECgEJAgACAAAAAA==.',
Wo='Wompalot:BAAALgAECgYJCQAAAA==.Womplock:BAAALgAECgQJCQAAAA==.Wooly:BAAALgAECgMJAwAAAA==.',
Wr='Wrâth:BAACLgAFFH8MAAIYAAQJJgeVcQD9AAAYAAQJJgeVcQD9AAAuAAQKfzcAAhgACQnEFsxFAAoCABgACQnEFsxFAAoCAAAA.',
Wy='Wydwen:BAAALgAECgEJAQAAAA==.',
Xa='Xael:BAAALgAECgIJAgAAAA==.',
Xe='Xenro:BAAALgADCgcJBgAAAA==.',
Xi='Xirus:BAAALgADCgQJAQAAAA==.',
Xu='Xulfred:BAAALgADCgIJAgAAAA==.',
Ya='Yavana:BAAALgADCgEJAQAAAA==.',
Yo='Yoshiscookie:BAAALgADCgMJAwAAAA==.',
Zi='Zigzogg:BAAALgADCgEJAQAAAA==.Zilida:BAAALgADCgEJAQAAAA==.Ziwee:BAABLgAECn8aAAIeAAgJvBqBFQBeAgAeAAgJvBqBFQBeAgABLgAECggJGgAeALwaAA==.',
Zo='Zolvyr:BAAALgADCgMJAwAAAA==.Zorana:BAAALgADCgYJBgAAAA==.',
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
