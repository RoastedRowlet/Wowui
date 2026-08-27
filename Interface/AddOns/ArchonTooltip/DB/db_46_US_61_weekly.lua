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

local lookup = {'DeathKnight-Frost','Hunter-BeastMastery','Hunter-Survival','Warrior-Fury','Warrior-Arms','Warlock-Demonology','Warlock-Affliction','Druid-Balance','Shaman-Elemental','Hunter-Marksmanship','Unknown-Unknown','Shaman-Restoration','Warrior-Protection','Warlock-Destruction','Priest-Discipline','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Blood','Paladin-Retribution','Monk-Windwalker','Priest-Holy','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','Druid-Restoration','DemonHunter-Havoc','Rogue-Subtlety','Priest-Shadow','Druid-Feral','Monk-Mistweaver','Monk-Brewmaster','Paladin-Holy','Druid-Guardian','DemonHunter-Devourer','Rogue-Assassination','Paladin-Protection',}
local provider = {region='US',realm='Darrowmere',name='US',type='weekly',zone=46,date='2026-08-25',data={Ab='Abaddonmoon:BAACLgAFFH8GAAIBAAMJvAvDDgC7AAABAAMJvAvDDgC7AAAuAAQKfz4AAgEACQm9E2ACAMQBAAEACQm9E2ACAMQBAAAA.',
Ad='Adassa:BAAALgAECgkJCQAAAA==.Addvar:BAAALgADCgEJAQAAAA==.Adelost:BAAALgAECgQJBQAAAA==.',
Ae='Aelîn:BAAALgAFFAEJAQAAAA==.',
Ah='Ahalina:BAAALgAECgYJCAAAAA==.Ahnari:BAACLgAFFH8FAAICAAMJdgJ5DwDMAAACAAMJdgJ5DwDMAAAuAAQKfxUAAwIACAlAEVg9ALkBAAIACAlAEVg9ALkBAAMABAm8AoQmAIsAAAAA.Ahnjo:BAAALgAECgMJAwAAAA==.',
Ai='Ailinaa:BAACLgAFFH8uAAMEAAkJTxp8BQD0AQAEAAkJFBh8BQD0AQAFAAYJvhx7CQC0AQAuAAQKfyAAAwQACQkkH8kVAJ8CAAQACAkpH8kVAJ8CAAUABAnjF1YvAAwBAAAA.',
Ak='Akalifato:BAACLgAFFH8KAAMGAAMJyx43YwABAQAGAAMJyx43YwABAQAHAAEJBBKJIQBPAAAuAAQKfxgAAgYABwkBG389AOYBAAYABwkBG389AOYBAAEuAAUUCQkjAAgATR4A.Akroma:BAAALgAECgIJBQAAAA==.',
Al='Alariya:BAAALgAECgUJBQAAAA==.Alerat:BAAALgAECgQJBQABLgAECgkJSgAJALAYAA==.Alistin:BAABLgAECn8dAAMDAAkJHBaHFAAAAgADAAkJnxKHFAAAAgACAAIJUiESJwC+AAAAAA==.Alistìn:BAAALgAECgEJAQAAAA==.Alistín:BAAALgAECgEJAQAAAA==.Alistïn:BAAALgAECgEJAwAAAA==.Alone:BAAALgADCgQJAwAAAA==.Alstir:BAAALgAECgEJAQAAAA==.',
Am='Amaryllis:BAAALgAECgEJAQAAAA==.Ambivalent:BAAALgAECgQJBgAAAA==.',
Ar='Aradin:BAAALgAECgMJBAAAAA==.Archanfel:BAACLgAFFH8PAAIDAAMJKgq5DQDCAAADAAMJKgq5DQDCAAAuAAQKf0kAAwMACQnfE1oEAEYBAAMACQn0EloEAEYBAAoAAwlyEToiAJ8AAAAA.Archwimonde:BAAALgADCgMJAwAAAA==.Argasha:BAAALgADCgUJBQAAAA==.',
As='Asriel:BAAALgAECgcJDQAAAA==.',
At='Atraxa:BAAALgAECgYJDQAAAA==.',
Aw='Awsomweorc:BAAALgADCgEJAQAAAA==.',
Ax='Axies:BAAALgAECgEJAQABLgAECgQJBwALAAAAAA==.',
Ay='Ayurvedas:BAAALgAECgIJAgAAAA==.',
Az='Azar:BAAALgADCgUJBQABLgAECgEJAQALAAAAAA==.',
Ba='Bandie:BAABLgAECn8bAAMMAAgJkxzcBQAPAgAMAAcJNh3cBQAPAgAJAAEJHRANLQAwAAAAAA==.Barksalot:BAAALgAECgcJBwAAAA==.Barrakum:BAAALgAECgUJDgAAAA==.Bastet:BAAALgADCgUJBQAAAA==.Bayn:BAAALgAECgQJBwAAAA==.',
Be='Beartho:BAAALgAECggJCQABLgAFFAMJDQANAM0mAA==.Beeftruck:BAACLgAFFH8QAAMFAAMJih3fDgDdAAAFAAMJlBbfDgDdAAAEAAMJAxT0NgDXAAAuAAQKfzIAAwUACQlBIZAFALACAAUACQlzH5AFALACAAQABwn7HlUvAJIBAAAA.Belletrixx:BAABLgAECn8UAAMGAAYJOAx/xwDAAAAGAAYJggt/xwDAAAAOAAMJhQW9PAA5AAAAAA==.Bellonä:BAAALgAECgEJAQAAAA==.Berried:BAACLgAFFH8SAAIPAAMJ4B0sFAD4AAAPAAMJ4B0sFAD4AAAuAAQKf34AAg8ACQlFJHEAALYDAA8ACQlFJHEAALYDAAAA.',
Bi='Bigred:BAAALgAECgMJBAAAAA==.Biigmâc:BAABLgAECn8WAAIJAAcJ6QUdSwAbAQAJAAcJ6QUdSwAbAQAAAA==.Biminem:BAABLgAECn8dAAIQAAgJbxXKDwC1AQAQAAgJbxXKDwC1AQAAAA==.Bitomax:BAAALgAECgUJBQAAAA==.',
Bl='Black:BAAALgAECgYJDAAAAA==.Blackwidow:BAAALgAECgMJAwAAAA==.Bloodshöt:BAABLgAECn8fAAMRAAgJdhu7OQAZAgARAAgJdhu7OQAZAgASAAEJXgcEagAVAAABLgAECgkJJwAEAIUYAA==.Bloôdymary:BAAALgAECgcJDAAAAA==.Bluntforce:BAAALgADCgkJCQAAAA==.',
Bo='Bodak:BAABLgAECn8bAAIMAAYJ5hnRNwCjAQAMAAYJ5hnRNwCjAQAAAA==.Boricua:BAAALgAECgEJAgAAAA==.',
Br='Brakun:BAAALgAECgQJBwAAAA==.Briline:BAAALgAECgEJAQAAAA==.Brolly:BAAALgAECgkJAgAAAA==.Bronwyn:BAAALgAFFAEJAQAAAA==.Broris:BAAALgAECgMJAwABLgAECgYJDAALAAAAAA==.Brucewii:BAAALgAECgUJBQAAAA==.Brunn:BAAALgAECgYJDAAAAA==.',
Ca='Calamari:BAAALgAECgMJBAAAAA==.Calistarius:BAACLgAFFH8NAAINAAUJ/xW+FAD7AAANAAUJ/xW+FAD7AAAuAAQKfx0AAg0ACQkCFO8SAL0BAA0ACQkCFO8SAL0BAAAA.Caliste:BAAALgADCgIJAgABLgAFFAUJEwAQAOkeAA==.Calityy:BAAALgADCgYJBgABLgAFFAkJHQADAPwgAA==.Camine:BAABLgAECn81AAIRAAkJ/BzaLABMAgARAAkJ/BzaLABMAgAAAA==.Candrabeckya:BAAALgADCgUJBQAAAA==.Capmurica:BAAALgAECgIJAgAAAA==.Carise:BAAALgAECgQJBAAAAA==.Castalasaras:BAABLgAECn8lAAIRAAcJygebHQDNAAARAAcJygebHQDNAAAAAA==.Castorsilver:BAAALgAECgEJAQAAAA==.Caylin:BAAALgADCgcJBwABLgAECgUJCgALAAAAAA==.',
Ce='Certified:BAAALgAFFAMJAwAAAA==.',
Ch='Charkoal:BAAALgAECgUJBQAAAA==.Cheyane:BAABLgAECn8cAAITAAYJ7QZL8ADKAAATAAYJ7QZL8ADKAAAAAA==.Chickeny:BAAALgADCgEJAQAAAA==.Choppstik:BAABLgAECn8VAAIUAAYJpQW5XACjAAAUAAYJpQW5XACjAAAAAA==.Chåos:BAAALgAECgMJBQAAAA==.',
Co='Cocstrong:BAAALgADCggJDAAAAA==.Coldslayerck:BAAALgAECgcJDAAAAA==.Coldswiftck:BAAALgADCgkJCQAAAA==.Constäntine:BAABLgAECn8hAAIVAAkJBhgjEwBCAgAVAAkJBhgjEwBCAgAAAA==.Cordélia:BAAALgAECgQJBAABLgAECgkJJQACAGoUAA==.Coriolis:BAACLgAFFH8QAAIWAAMJ9RNUHgC7AAAWAAMJ9RNUHgC7AAAuAAQKf1QAAxYACQmPG28BAGoCABYACQmPG28BAGoCABcAAwmCCvEwAI8AAAAA.',
Cr='Cravedog:BAAALgAECgYJDAAAAA==.Crittycrat:BAAALgAECgUJBQAAAA==.Crowléy:BAAALgAECgYJEgAAAA==.',
Cu='Cuddlyowl:BAABLgAECn8XAAIYAAcJwQ4DqwCFAQAYAAcJwQ4DqwCFAQAAAA==.',
Da='Dagnamagus:BAAALgAECgkJDgAAAA==.Daire:BAAALgADCgYJBgAAAA==.Daliann:BAAALgAECgYJDQAAAA==.Damion:BAAALgAECgUJCgAAAA==.Damnation:BAAALgAECgYJCwAAAA==.Dangerduck:BAABLgAECn8fAAMXAAcJlRUwCgB+AQAXAAcJoBQwCgB+AQAWAAYJgg/+UADrAAAAAA==.Darktruth:BAAALgADCgMJAwAAAA==.Darkwingdûck:BAAALgAECgYJBgABLgAECgkJHQAQAPgZAA==.Dartes:BAABLgAECn8WAAICAAgJaxGqXQCNAQACAAgJaxGqXQCNAQAAAA==.Dashe:BAAALgAECgcJAQAAAA==.',
De='Deathadder:BAAALgAECgIJAgAAAA==.Deathcokie:BAAALgAECgYJDgAAAA==.Deatho:BAACLgAFFH8NAAINAAMJzSZDCABPAQANAAMJzSZDCABPAQAuAAQKf0oAAw0ACQmZJjMCACkDAA0ACQmZJjMCACkDAAQAAQkJI3OdAEoAAAAA.Deathstoned:BAAALgADCgQJBQAAAA==.Deimos:BAAALgAECgEJAgAAAA==.Deratra:BAAALgADCgUJBQAAAA==.Destrocake:BAAALgAECgEJAwABLgAFFAQJCwATAA8YAA==.',
Di='Diamondshard:BAAALgAECgQJCwAAAA==.Discofreezer:BAAALgAECgEJAQAAAA==.',
Dl='Dlgadoflpjck:BAAALgAECgQJBAAAAA==.',
Dr='Draegov:BAAALgADCgYJBgAAAA==.Draeth:BAAALgADCgcJDQAAAA==.Drash:BAAALgAECgYJCwAAAA==.Dreadful:BAAALgAECgcJEAAAAA==.Dreylan:BAAALgADCgcJBwAAAA==.Dreyra:BAAALgAFFAMJBAABLgAFFAQJDAADAKcNAA==.Droodtrass:BAABLgAFFH8FAAIZAAQJkAlMGACxAAAZAAQJkAlMGACxAAAAAA==.Drosof:BAAALgAECgEJAQAAAA==.Drow:BAAALgAECgEJAQAAAA==.',
Du='Dukalioth:BAABLgAECn8iAAIaAAcJ0BDdKAA2AQAaAAcJ0BDdKAA2AQAAAA==.Duris:BAAALgAECgEJAwAAAA==.Duskheart:BAAALgADCgUJBQAAAA==.',
['Dê']='Dêcay:BAACLgAFFH8aAAQBAAcJexwDBQCqAQABAAUJyhkDBQCqAQARAAYJgR0gNACZAQASAAEJAACHUwAAAAAuAAQKfz0AAxEACQmOIhMYAOsCABEACAk4IhMYAOsCAAEABwnHIQMGAEwCAAAA.',
['Dö']='Döctorfate:BAACLgAFFH8OAAIbAAMJuQodGAC/AAAbAAMJuQodGAC/AAAuAAQKfzUAAhsACQl4D3MDAKsBABsACQl4D3MDAKsBAAAA.',
Ed='Ediela:BAAALgAECgQJBAAAAA==.',
Ef='Effinsoldier:BAABLgAECn83AAITAAkJ+xsIBQByAgATAAkJ+xsIBQByAgAAAA==.',
Eg='Egfuyun:BAAALgAECgQJBwAAAA==.',
Ek='Ekko:BAAALgAECgIJAgAAAA==.',
El='Ellyy:BAAALgAFFAEJAQAAAA==.Elvira:BAAALgAECggJDwAAAA==.',
En='Endlessagony:BAACLgAFFH8HAAIRAAMJsxAQowDRAAARAAMJsxAQowDRAAAuAAQKfycAAhEACQmoHjAgAMECABEACQmoHjAgAMECAAAA.Endlessice:BAAALgAECgYJCgAAAA==.Ennyo:BAAALgAECgcJCgAAAA==.Enyo:BAACLgAFFH8HAAIGAAIJxxYplgCWAAAGAAIJxxYplgCWAAAuAAQKfzQABAYACQmnHzYZAI0CAAYACQmnHzYZAI0CAAcAAQkAADUnAFUAAA4AAgl4Bn1eAFMAAAAA.',
Er='Erastothenes:BAAALgAECgEJAQABLgAECgkJEgALAAAAAA==.Erathas:BAABLgAECn8ZAAITAAkJsRHBYQC/AQATAAkJsRHBYQC/AQAAAA==.Ermagerd:BAAALgAECgkJCQAAAA==.',
Fa='Faelissel:BAAALgADCgUJBQABLgAECgUJCgALAAAAAA==.Falandril:BAABLgAECn8PAAIcAAgJZhJJHgDTAQAcAAgJZhJJHgDTAQAAAA==.Fasriel:BAAALgAECgUJBgAAAA==.',
Fe='Feata:BAAALgAECgEJAQABLgAECgYJDAALAAAAAA==.Felston:BAAALgADCgUJBQAAAA==.',
Fi='Figment:BAAALgAECgYJCwAAAA==.Fineapple:BAAALgAECgkJBwAAAA==.Fiyero:BAABLgAECn8uAAMEAAkJ8A5aLACiAQAEAAkJ8A5aLACiAQAFAAcJwgQqJQDEAAAAAA==.',
Fl='Flagcrazed:BAAALgADCgUJBQAAAA==.Fleabath:BAABLgAECn8hAAIdAAYJZhTyBAAmAQAdAAYJZhTyBAAmAQABLgAECgkJJAACACUNAA==.Fluffypyro:BAAALgADCgYJBgAAAA==.',
Fo='Forëplây:BAAALgAECgYJCgAAAA==.Foughum:BAAALgADCgUJBQABLgAECgYJDAALAAAAAA==.',
Fr='Friedcheekin:BAAALgADCgUJBQAAAA==.',
Fu='Fury:BAAALgADCgEJAQAAAA==.',
Ga='Galdames:BAAALgAECgEJAQAAAA==.',
Ge='Gedien:BAAALgAECgkJEQAAAA==.Gerftrazkal:BAAALgAECgUJBQAAAA==.',
Gi='Gilforty:BAABLgAECn8bAAIOAAcJ/RdFDAB7AQAOAAcJ/RdFDAB7AQAAAA==.',
Gl='Glep:BAAALgAECgIJAgABLgAFFAMJBAALAAAAAA==.Gloomkin:BAAALgAECgEJAQAAAA==.Gloriosa:BAABLgAECn9JAAIeAAkJlRDULQDGAQAeAAkJlRDULQDGAQAAAA==.',
Go='Gonk:BAAALgAECgUJBgABLgAECgUJBwALAAAAAA==.Gorando:BAAALgADCgIJAgAAAA==.Gorl:BAAALgAECgEJAQAAAA==.Goél:BAAALgAECgQJBAAAAA==.',
Gr='Griddy:BAAALgAECgEJAQAAAA==.Grootforce:BAAALgADCgMJAwAAAA==.',
Gu='Gulithark:BAAALgAECgIJAgABLgAECgUJCgALAAAAAA==.Gump:BAAALgAECgQJCwABLgAFFAMJEAAFAIodAA==.',
Gv='Gvendalyn:BAACLgAFFH8XAAICAAQJnh+DGABbAQACAAQJnh+DGABbAQAuAAQKf2AAAgIACQm0JqAAAJcDAAIACQm0JqAAAJcDAAAA.',
Gw='Gweyn:BAAALgADCgUJCAAAAA==.',
Gy='Gyatsò:BAABLgAECn8jAAIUAAkJAxihEwAfAgAUAAkJAxihEwAfAgAAAA==.',
['Gø']='Gød:BAAALgADCgUJBQAAAA==.',
Ha='Hakeem:BAAALgAFFAIJBAABLgAFFAUJGAAPAGwVAA==.Harshdh:BAAALgAECgYJBgABLgAFFAMJBwARAFMJAA==.Harshdk:BAACLgAFFH8HAAIRAAMJUwkbsgDAAAARAAMJUwkbsgDAAAAuAAQKfy4AAxEACQnVHC0XALsCABEACQnVHC0XALsCABIABAmgAblSAEwAAAAA.Harshpawz:BAAALgAECgUJBQABLgAFFAMJBwARAFMJAA==.',
He='Helel:BAACLgAFFH8ZAAMRAAMJ3x47MgALAQARAAMJ3x47MgALAQASAAIJiw9tHQBzAAAuAAQKf1QAAxEACQntIkgJACYDABEACQntIkgJACYDABIACAlxHJYEAJ4BAAAA.',
Ho='Hops:BAAALgAECgIJBgAAAA==.',
Il='Illibanger:BAAALgAECgkJDwABLgAFFAMJEAAFAIodAA==.Illidon:BAAALgADCgYJBgAAAA==.Illifiend:BAAALgAECgYJCQABLgAECgkJLgAEAPAOAA==.',
Im='Impetuous:BAAALgADCgYJDwABLgAECgkJJAACACUNAA==.',
Ip='Ipokeu:BAAALgAECgEJAQAAAA==.',
Ja='Jabmoney:BAABLgAECn8WAAMUAAkJCCM/DQBxAgAUAAkJCCM/DQBxAgAfAAEJRia0bQBpAAABLgAFFAIJAgALAAAAAA==.Jabohabo:BAAALgAECgQJBgABLgAFFAIJAgALAAAAAA==.Jaffy:BAABLgAECn8cAAIEAAgJHhHzBgB4AQAEAAgJHhHzBgB4AQAAAA==.Jamninja:BAACLgAFFH8GAAIYAAIJByA2UACUAAAYAAIJByA2UACUAAAuAAQKfykAAhgACQmzG14tAGQCABgACQmzG14tAGQCAAAA.Jamxd:BAAALgAECgcJCAABLgAFFAIJBgAYAAcgAA==.Jardalanin:BAAALgADCgEJAQAAAA==.Jaroshe:BAAALgADCgUJBQAAAA==.Jaxxson:BAAALgADCgYJCgAAAA==.',
Je='Jellyfish:BAACLgAFFH8LAAIPAAUJbAocIwA2AQAPAAUJbAocIwA2AQAuAAQKfx4AAw8ACQmrElQeANsBAA8ACQlhDlQeANsBABUACAlGDDAvAFUBAAAA.Jessamyn:BAABLgAECn8eAAIgAAkJZhIuAwAdAgAgAAkJZhIuAwAdAgAAAA==.',
Jh='Jhoira:BAAALgAECgYJDwAAAA==.',
Ji='Jimmy:BAAALgAECgEJAQAAAA==.Jingu:BAAALgAECgEJAQAAAA==.',
Jo='Jokko:BAAALgADCgEJAgAAAA==.Jordyy:BAABLgAECn8oAAQHAAkJTiLyBwDtAQAGAAgJfSCeIQCQAgAHAAYJpiTyBwDtAQAOAAIJERNKVABxAAAAAA==.',
Ka='Kaifren:BAACLgAFFH8OAAIYAAQJKhItYQAfAQAYAAQJKhItYQAfAQAuAAQKfx0AAhgACQmvFKFSAOQBABgACQmvFKFSAOQBAAAA.Kalifa:BAACLgAFFH8jAAMIAAgJTR7RAwCIAgAIAAgJTR7RAwCIAgAZAAEJdgH5fQAkAAAuAAQKfzcABAgACAn1I7cIAAoDAAgACAn1I7cIAAoDABkAAQnuGBa9AEkAACEAAgmIFaFuADsAAAAA.Kalinethe:BAAALgAECgEJAgAAAA==.Karatay:BAAALgADCgQJBQAAAA==.Karrod:BAABLgAECn8UAAMSAAgJmwpMOACzAAASAAYJywtMOACzAAARAAMJYgcqGgGLAAAAAA==.Katyce:BAAALgADCgcJDQAAAA==.Kayohs:BAAALgADCgEJAQAAAA==.',
Ke='Keilani:BAAALgAECgQJBQAAAA==.',
Kh='Khrysus:BAAALgAECgUJBQAAAA==.',
Ki='Kikorala:BAAALgAECgIJAgAAAA==.Killeerrkap:BAAALgAECgQJBgAAAA==.Killrmiller:BAAALgADCgMJAwAAAA==.Kirajdh:BAABLgAECn8mAAIiAAkJRR3GGACAAgAiAAkJRR3GGACAAgABLgAFFAMJBAALAAAAAA==.Kittenmitten:BAAALgADCgQJBAAAAA==.Kiv:BAAALgAFFAQJBAABLgAFFAYJJgAZACscAA==.Kiwaj:BAAALgAECgUJBQABLgAFFAMJBAALAAAAAA==.',
Kn='Knoa:BAAALgAECgkJDAAAAA==.',
Ko='Komayetu:BAAALgAECgUJCgAAAA==.',
Kr='Kraas:BAAALgAECgEJAgAAAA==.Krateis:BAABLgAECn8pAAIjAAcJ+QSYFADgAAAjAAcJ+QSYFADgAAAAAA==.Kraéthlas:BAAALgADCgYJCgAAAA==.',
Kv='Kvit:BAAALgAECgEJAQAAAA==.Kvothê:BAAALgAECgEJAQAAAA==.',
Kw='Kwonhee:BAAALgADCgMJAwAAAA==.',
La='Lanadelrey:BAAALgAECggJAQAAAA==.Laurenth:BAAALgADCgkJFQAAAA==.Lazyace:BAAALgAFFAEJAQAAAA==.',
Le='Lebenspender:BAACLgAFFH8KAAIMAAMJnxvHJQC2AAAMAAMJnxvHJQC2AAAuAAQKfzoAAwwACAnvIpgKAA0DAAwACAnvIpgKAA0DAAkACAnoDhU4AFgBAAAA.Lextalonis:BAAALgAECgYJCAABLgAECggJEAALAAAAAA==.',
Li='Linkstery:BAABLgAECn83AAMGAAkJbhy+IQBbAgAGAAkJJBy+IQBbAgAOAAMJfRWwNADkAAAAAA==.Lisabolin:BAAALgADCgEJAgAAAA==.',
Lo='Losvanknight:BAABLgAECn8jAAIKAAgJJBEqDQCPAQAKAAgJJBEqDQCPAQAAAA==.',
Lt='Lt:BAAALgADCgEJAQAAAA==.',
Lu='Lunalii:BAACLgAFFH8HAAIBAAMJSR7MCAASAQABAAMJSR7MCAASAQAuAAQKfxUAAwEACAlWIogEAIACAAEACAlWIogEAIACABEAAQmOFLZmAT0AAAEuAAUUAwkIAAQAjiUA.',
Ly='Lyathon:BAAALgADCgMJAwAAAA==.',
['Lï']='Lïllïë:BAAALgADCgUJBQABLgAECggJGwAMAJMcAA==.',
Ma='Macdaddy:BAAALgAFFAEJAQAAAA==.Macfluffy:BAABLgAECn8VAAIfAAgJOwrnMwAwAQAfAAgJOwrnMwAwAQAAAA==.Macpendragon:BAAALgAECgkJCQAAAA==.Mactacolover:BAAALgAECgQJBAAAAA==.Madbomber:BAAALgAFFAEJBAAAAA==.Maeze:BAABLgAECn8kAAICAAkJJQ3qWgCUAQACAAkJJQ3qWgCUAQAAAA==.Maezer:BAAALgAECgYJBgABLgAECgkJJAACACUNAA==.Magepawk:BAAALgAECgMJAwAAAA==.Magew:BAAALgADCgQJBAAAAA==.Malandru:BAACLgAFFH8VAAMgAAkJBRKMDQAqAQAgAAgJXBCMDQAqAQATAAIJvxsPhACsAAAuAAQKfy0AAxMACQnlIgIXALkCABMACAn0JAIXALkCACAACQlUDGQ6AJABAAAA.Mawwow:BAABLgAFFH8JAAITAAMJhCHuGgAmAQATAAMJhCHuGgAmAQAAAA==.Mawwowow:BAACLgAFFH8IAAIiAAMJyA9haQC5AAAiAAMJyA9haQC5AAAuAAQKfzwAAiIACQlGG+kmADACACIACQlGG+kmADACAAEuAAUUAwkJABMAhCEA.Maximillius:BAAALgAECgYJBwABLgAECggJJgARAFEdAA==.Mayjoraid:BAAALgAECgEJAgAAAA==.',
Me='Meekah:BAACLgAFFH8YAAIPAAUJbBUBHQB0AQAPAAUJbBUBHQB0AQAuAAQKf1AAAg8ACQmxIDwEAFQDAA8ACQmxIDwEAFQDAAAA.Melbrosha:BAAALgAECgUJDAAAAA==.Melodine:BAAALgADCgEJAQAAAA==.Meriks:BAAALgAECgQJDAABLgAECgUJDQALAAAAAA==.Metaliorch:BAABLgAECn8VAAIJAAcJiwIkGgBvAAAJAAcJiwIkGgBvAAAAAA==.',
Mi='Micksippy:BAAALgAFFAMJAwAAAA==.Mickspooky:BAACLgAFFH8XAAMRAAUJlhVXcwAaAQARAAQJlhVXcwAaAQASAAEJAAABVwAAAAAuAAQKfzEAAxEACAmXIEopAJUCABEACAmXIEopAJUCABIAAwm4GAo0AMoAAAEuAAQKAwkDAAsAAAAA.Mickstormy:BAAALgAECgMJAwAAAA==.Mierin:BAAALgAECgQJBwAAAA==.Milfy:BAAALgADCgQJBAABLgAECgEJAQALAAAAAA==.Mintie:BAABLgAECn84AAIhAAkJWRdHDQANAgAhAAkJWRdHDQANAgAAAA==.Miste:BAAALgAECgEJBAAAAA==.',
Mo='Moozylla:BAAALgAFFAEJAwAAAA==.Morbitaldo:BAAALgADCgEJAQAAAA==.Morrïgan:BAABLgAECn8YAAIRAAgJtRffCAC8AQARAAgJtRffCAC8AQAAAA==.Mossiah:BAAALgAECgEJAQAAAA==.',
My='Mylarna:BAABLgAECn9KAAIJAAkJsBgPAwA1AgAJAAkJsBgPAwA1AgAAAA==.Mynthia:BAAALgADCgUJBQAAAA==.Mynx:BAABLgAECn8hAAIKAAgJLiPLAgC5AgAKAAgJLiPLAgC5AgAAAA==.',
['Må']='Mårsh:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîstweaver:BAAALgAECgYJDAAAAA==.',
Na='Nadira:BAAALgAECgEJAQABLgAECgkJNQASAKwVAA==.Nahkti:BAAALgADCgcJBwAAAA==.Nazarick:BAAALgAECgYJCAABLgAFFAIJAgALAAAAAA==.',
Ne='Neona:BAAALgAECgQJBQAAAA==.Neriv:BAABLgAECn8XAAIOAAgJhw4kEAA/AQAOAAgJhw4kEAA/AQAAAA==.Nexaladin:BAAALgAECgEJAwAAAA==.Nexiroth:BAAALgAECgEJAQAAAA==.',
Ni='Nicor:BAAALgADCgQJBAAAAA==.Nightowls:BAAALgAECgIJAgAAAA==.Nimbus:BAAALgAECgMJBAABLgAFFAkJQgAWAEEdAA==.Nixii:BAACLgAFFH8NAAIIAAMJQxFGGAC/AAAIAAMJQxFGGAC/AAAuAAQKf00AAggACQlpHE8CAFkCAAgACQlpHE8CAFkCAAAA.',
No='Nocticula:BAABLgAECn86AAIVAAkJXAkjLwBVAQAVAAkJXAkjLwBVAQAAAA==.Noriinau:BAAALgADCgIJAgAAAA==.',
Ny='Nyet:BAACLgAFFH8iAAMEAAkJXBH+BQDiAQAEAAkJXBH+BQDiAQAFAAEJYgaPRAA9AAAuAAQKfxwAAgQACQm/G1wcAGoCAAQACQm/G1wcAGoCAAAA.Nythraxia:BAAALgAECgMJAwAAAA==.Nyxiria:BAAALgADCgcJGgAAAA==.',
['Nò']='Nòir:BAAALgAECgcJCAAAAA==.',
['Nø']='Nø:BAAALgADCgMJAwAAAA==.',
Oh='Ohnarr:BAAALgAECgMJBAAAAA==.',
Ok='Oktoberfist:BAAALgAECgcJBwABLgAFFAIJAgALAAAAAA==.Oku:BAAALgAECgQJBAAAAA==.',
Or='Orgullo:BAAALgAECgMJAwAAAA==.Orine:BAABLgAECn8eAAIRAAkJgAwWfgBnAQARAAkJgAwWfgBnAQAAAA==.Orion:BAAALgAFFAIJBAAAAA==.Orioz:BAACLgAFFH8TAAIQAAUJ6R6zCAAuAQAQAAUJ6R6zCAAuAQAuAAQKfyQAAhAACAk0IvEDAOgCABAACAk0IvEDAOgCAAAA.',
Os='Oshara:BAAALgAECgMJAwAAAA==.Osiras:BAAALgAECggJEAAAAA==.',
Ot='Othela:BAAALgADCgEJAQAAAA==.',
Ow='Owun:BAAALgADCgEJAQAAAA==.',
Oz='Oz:BAAALgADCgkJCgAAAA==.',
Pa='Pandapal:BAAALgAECgEJAgAAAA==.Papermoon:BAAALgAECgMJAwAAAA==.Pathbrin:BAAALgADCgEJAQAAAA==.Pauliee:BAAALgAECggJEAAAAA==.Pawkah:BAAALgAECgEJAgAAAA==.Paytowintaxi:BAAALgADCgEJAQAAAA==.',
Pe='Peyton:BAAALgADCggJEQAAAA==.',
Ph='Phoenixmage:BAAALgAECgUJBQAAAA==.',
Pr='Protection:BAAALgADCgUJBgAAAA==.',
Ps='Psychoman:BAAALgADCgMJAwABLgAFFAgJJAAIAAgiAA==.Psychomurda:BAABLgAECn8dAAMTAAYJpAvj2ADnAAATAAYJpAvj2ADnAAAkAAMJ/gdPPgBkAAABLgAFFAUJGAAPAGwVAA==.',
Pu='Puthealshere:BAAALgAFFAEJAQAAAA==.',
Py='Pytheas:BAAALgAECgQJBAABLgAECgEJAgALAAAAAA==.',
['Pü']='Pü:BAAALgAECgEJAQABLgAECgkJNQASAKwVAA==.',
Ra='Radio:BAAALgAECgEJAgAAAA==.Raign:BAAALgAECgEJAgAAAA==.Randomfelfox:BAAALgAECgYJDQAAAA==.Ratpack:BAAALgAFFAEJAQABLgAFFAIJAgALAAAAAA==.',
Re='Renfri:BAABLgAECn8cAAIYAAgJ2QxtFAA4AQAYAAgJ2QxtFAA4AQAAAA==.',
Ro='Robel:BAAALgAECgcJDwAAAA==.Roflburger:BAABLgAECn8dAAIQAAkJ+BkwAQBTAgAQAAkJ+BkwAQBTAgAAAA==.Ronaldbruce:BAAALgAECgQJBQAAAA==.Roupert:BAAALgAECgEJBAAAAA==.Rovox:BAAALgAFFAMJBAAAAA==.',
Ru='Runebane:BAAALgADCgMJAwAAAA==.Rustpaw:BAAALgAECgYJBgAAAA==.',
Sa='Sadness:BAAALgAFFAEJAQAAAA==.Sao:BAAALgAECgIJAgAAAA==.Sardrian:BAABLgAECn8kAAICAAcJKgoOKAC5AAACAAcJKgoOKAC5AAAAAA==.',
Sc='Scurgedeath:BAAALgAECgEJAQABLgAECgkJHwAbAOoSAA==.',
Se='Seimie:BAABLgAECn9dAAIOAAkJtRPgAQDQAQAOAAkJtRPgAQDQAQAAAA==.Selithvia:BAABLgAECn8YAAIcAAgJWxHaKACJAQAcAAgJWxHaKACJAQAAAA==.Senethotsare:BAAALgAECgkJEgAAAA==.Sethen:BAAALgAECgEJAQAAAA==.',
Sh='Shaboudi:BAAALgAECgUJBwAAAA==.Shamalicious:BAAALgADCgEJAQAAAA==.Shammwow:BAAALgAECgMJBwAAAA==.Shaofikx:BAABLgAECn80AAIfAAkJng1oJACJAQAfAAkJng1oJACJAQAAAA==.Shenknarok:BAABLgAECn8vAAIdAAYJnR4NEAC2AQAdAAYJnR4NEAC2AQAAAA==.Sherryl:BAACLgAFFH8NAAIZAAMJXwegIABzAAAZAAMJXwegIABzAAAuAAQKf1AAAhkACQkLFRsFAMYBABkACQkLFRsFAMYBAAAA.Shmooples:BAAALgAECgEJAQAAAA==.Shunei:BAAALgADCgQJBAAAAA==.',
Si='Siema:BAAALgAECgMJAwAAAA==.Sigurd:BAAALgADCggJBwAAAA==.',
Sk='Skdk:BAAALgADCgEJAQAAAA==.Skdragon:BAAALgADCgMJAQAAAA==.Skyarii:BAAALgAFFAEJAgABLgAFFAMJCAAEAI4lAA==.Skylaar:BAAALgAECgMJAwAAAA==.',
So='Songweaver:BAAALgAECgEJAgAAAA==.Soulminion:BAABLgAECn8fAAMRAAYJ6wI5FAGTAAARAAYJuAI5FAGTAAASAAEJ5gKVagAVAAAAAA==.',
Sp='Spiritshard:BAAALgAECgQJBgAAAA==.Splashmountn:BAEALgAECgYJEAAAAA==.Spriggens:BAAALgAFFAEJAgABLgAFFAQJFwACAJ4fAA==.',
St='Sthane:BAAALgADCgEJAQAAAA==.Sthise:BAAALgAECgMJAwAAAA==.Sturer:BAAALgADCgEJAQAAAA==.',
Su='Subtlety:BAABLgAECn8aAAIbAAkJ+yLsBADpAgAbAAkJ+yLsBADpAgAAAA==.Sulfurya:BAABLgAECn8VAAIaAAkJgRnpAwDVAQAaAAkJgRnpAwDVAQAAAA==.',
Sy='Sykodrag:BAAALgAFFAMJBAABLgAFFAgJJAAIAAgiAA==.Sykoman:BAACLgAFFH8kAAMIAAgJCCL+AwBJAgAIAAgJCCL+AwBJAgAZAAEJ5QA7fQAmAAAuAAQKfygAAggACAlwI30LAN8CAAgACAlwI30LAN8CAAAA.',
['Sì']='Sìleñtclãw:BAAALgAECgcJDgAAAA==.',
Ta='Talarina:BAAALgADCgYJBgAAAA==.Taylen:BAAALgADCgcJBwAAAA==.',
Te='Terumi:BAABLgAECn8zAAICAAcJoQpFIADjAAACAAcJoQpFIADjAAAAAA==.Teverion:BAAALgADCgcJCwAAAA==.',
Th='Thesios:BAAALgAECgMJAwAAAA==.Thickthighs:BAAALgAECgEJAQAAAA==.Thiizz:BAAALgAFFAIJAgAAAA==.Thizz:BAABLgAECn8fAAIEAAYJPiD/KQASAgAEAAYJPiD/KQASAgABLgAFFAIJAgALAAAAAA==.Thracious:BAAALgAECgEJAQAAAA==.Thïzz:BAAALgAECgIJAgABLgAFFAIJAgALAAAAAA==.',
Ti='Tic:BAABLgAFFH8JAAIGAAMJnQbujQCpAAAGAAMJnQbujQCpAAAAAA==.Tinksy:BAAALgADCgEJAQABLgAECgEJAQALAAAAAA==.Tionder:BAAALgAECgYJEQAAAA==.',
To='Toeto:BAAALgADCgYJBgAAAA==.Toetoeto:BAAALgAECgMJAwAAAA==.Toetoetoete:BAAALgADCgYJBgAAAA==.Tooe:BAAALgAECgMJAwAAAA==.Torquei:BAABLgAECn8UAAICAAYJawsVLgCbAAACAAYJawsVLgCbAAAAAA==.Toxious:BAAALgAECgQJBAAAAA==.',
Tp='Tpaman:BAAALgAECgYJBgAAAA==.Tpdruid:BAAALgAECgMJAwAAAA==.',
Ts='Tsjuda:BAAALgADCgEJAQAAAA==.Tsjudii:BAAALgADCgYJBgAAAA==.Tsjudilla:BAAALgADCgEJAQAAAA==.',
Tu='Tujefe:BAAALgAECgcJCwAAAA==.',
Ty='Tyllibust:BAAALgAECgEJAQAAAA==.Tylorialin:BAAALgAECgUJBQABLgAFFAMJEAAFAIodAA==.',
Ug='Ugzlug:BAAALgADCgEJAQAAAA==.',
Un='Unholydk:BAABLgAFFH8HAAMTAAMJ5hExawDZAAATAAMJ5hExawDZAAAgAAIJngAARwBEAAABLgAFFAgJEwAZAHIVAA==.',
Va='Vacuus:BAABLgAECn8rAAIHAAkJWgrRDACPAQAHAAkJWgrRDACPAQAAAA==.Vahldire:BAABLgAECn85AAIYAAkJPw5CDQCOAQAYAAkJPw5CDQCOAQAAAA==.Valeri:BAAALgADCggJCwAAAA==.Valor:BAABLgAECn8UAAIkAAgJhhO4AwCSAQAkAAgJhhO4AwCSAQAAAA==.Varkon:BAAALgAECgYJBgAAAA==.Varn:BAAALgADCggJCAAAAA==.Varthion:BAAALgAECgYJBgAAAA==.',
Ve='Vegetas:BAAALgAECgYJBwAAAA==.Velastrasza:BAAALgADCgcJBwAAAA==.Velkethria:BAAALgAECgYJEwAAAA==.Velnythra:BAAALgAECgQJBQAAAA==.Velovañ:BAAALgADCgEJAQAAAA==.Velthyria:BAAALgADCgkJCQAAAA==.Vestara:BAAALgAECggJCAAAAA==.Veylara:BAABLgAECn8oAAIGAAcJ7gbYpAD3AAAGAAcJ7gbYpAD3AAAAAA==.',
Vi='Viryda:BAAALgAECgQJBAABLgAECggJMQAhAFEKAA==.',
Wa='Waeder:BAAALgADCgkJDAAAAA==.Wartimebeast:BAAALgAECgUJEAAAAA==.',
We='Welp:BAAALgAECgEJBQAAAA==.',
Wh='Wherebear:BAAALgAECgIJAgAAAA==.',
Wi='Windwalker:BAAALgAECgcJCAAAAA==.Wisteria:BAABLgAECn9FAAMOAAkJmx/1BQAHAgAOAAkJmx/1BQAHAgAHAAEJwwEzOAAaAAABLgAECgEJAgALAAAAAA==.',
Wo='Wompalot:BAAALgAECgYJCQAAAA==.Womplock:BAAALgAECgQJCQAAAA==.Wompnhood:BAAALgAECgEJAQABLgAECgYJCQALAAAAAA==.Wooly:BAAALgAECgMJAwAAAA==.',
Wr='Wrâth:BAACLgAFFH8MAAIYAAQJJgeVcQD9AAAYAAQJJgeVcQD9AAAuAAQKfzcAAhgACQnEFsxFAAoCABgACQnEFsxFAAoCAAAA.',
Wy='Wydwen:BAAALgAECgEJAQAAAA==.',
Xa='Xael:BAAALgAECgIJAgAAAA==.',
Xe='Xenro:BAAALgADCgcJBgAAAA==.',
Xi='Xirus:BAAALgADCgQJAQAAAA==.',
Xu='Xulfred:BAAALgADCgIJAgAAAA==.',
Ya='Yavana:BAAALgADCgEJAQAAAA==.',
Yo='Yoshiscookie:BAAALgADCgMJAwAAAA==.',
Za='Zalus:BAAALgAECgQJBAAAAA==.',
Ze='Zenatria:BAAALgADCgEJAQAAAA==.',
Zi='Zigzogg:BAAALgADCgEJAQAAAA==.Zilida:BAAALgADCgEJAQAAAA==.Ziwee:BAABLgAECn8aAAIfAAgJvBqBFQBeAgAfAAgJvBqBFQBeAgABLgAECggJGgAfALwaAA==.',
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
