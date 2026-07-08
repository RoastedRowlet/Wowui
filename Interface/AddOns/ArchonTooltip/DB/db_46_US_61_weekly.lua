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

local lookup = {'DeathKnight-Frost','Unknown-Unknown','Hunter-BeastMastery','Hunter-Survival','Warrior-Fury','Warrior-Arms','Warlock-Demonology','Warlock-Affliction','Druid-Balance','Shaman-Elemental','Hunter-Marksmanship','Shaman-Restoration','Warlock-Destruction','Priest-Discipline','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Paladin-Retribution','Monk-Windwalker','Priest-Holy','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','DemonHunter-Havoc','Rogue-Subtlety','Priest-Shadow','Druid-Feral','Monk-Mistweaver','Monk-Brewmaster','Druid-Restoration','Druid-Guardian','DemonHunter-Devourer','Rogue-Assassination','Paladin-Holy','Paladin-Protection',}
local provider = {region='US',realm='Darrowmere',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abaddonmoon:BAABLgAECn8yAAIBAAkJ6QvAFAA1AQABAAkJ6QvAFAA1AQAAAA==.Absentia:BAAALgAECgEJAQABLgAECgEJAgACAAAAAA==.',
Ad='Addvar:BAAALgADCgEJAQAAAA==.Adelost:BAAALgAECgQJBQAAAA==.',
Ah='Ahalina:BAAALgAECgYJCAAAAA==.Ahnari:BAACLgAFFH8FAAIDAAMJdgJ5DwDMAAADAAMJdgJ5DwDMAAAuAAQKfxUAAwMACAlAEVg9ALkBAAMACAlAEVg9ALkBAAQABAm8AoQmAIsAAAAA.Ahnjo:BAAALgADCgMJAwAAAA==.',
Ai='Ailinaa:BAACLgAFFH8rAAMFAAkJCxoZAgAdAgAFAAkJ0BcZAgAdAgAGAAYJvhx7CQC0AQAuAAQKfyAAAwUACQkkH8kVAJ8CAAUACAkpH8kVAJ8CAAYABAnjF1YvAAwBAAAA.',
Ak='Akalifato:BAACLgAFFH8KAAMHAAMJyx43YwABAQAHAAMJyx43YwABAQAIAAEJBBKJIQBPAAAuAAQKfxgAAgcABwkBG389AOYBAAcABwkBG389AOYBAAEuAAUUCAkjAAkATR4A.Akroma:BAAALgAECgIJBQAAAA==.',
Al='Alariya:BAAALgAECgUJBQAAAA==.Alerat:BAAALgAECgQJBAABLgAECgkJOgAKANYTAA==.Alistin:BAABLgAECn8bAAMEAAkJjRSHFAAAAgAEAAkJnxKHFAAAAgADAAEJECcGIQBxAAAAAA==.Alistïn:BAAALgAECgEJAwAAAA==.Alone:BAAALgADCgQJAwAAAA==.Alstir:BAAALgAECgEJAQAAAA==.',
Am='Amaryllis:BAAALgAECgEJAQAAAA==.Ambivalent:BAAALgAECgQJBgAAAA==.',
Ar='Aradin:BAAALgAECgMJBAAAAA==.Archanfel:BAACLgAFFH8IAAIEAAMJXgPYKQCNAAAEAAMJXgPYKQCNAAAuAAQKf0EAAwQACQlvE98YANkBAAQACQmEEt8YANkBAAsAAwkKDzoiAJ8AAAAA.Argasha:BAAALgADCgUJBQAAAA==.',
As='Asriel:BAAALgAECgcJDQAAAA==.',
At='Atraxa:BAAALgAECgYJDQAAAA==.',
Aw='Awsomweorc:BAAALgADCgEJAQAAAA==.',
Ax='Axies:BAAALgAECgEJAQABLgAECgQJBwACAAAAAA==.',
Az='Azar:BAAALgADCgUJBQABLgAECgEJAQACAAAAAA==.',
Ba='Bandie:BAABLgAECn8WAAIMAAYJLh+1BAClAQAMAAYJLh+1BAClAQAAAA==.Barksalot:BAAALgAECgcJBwAAAA==.Barrakum:BAAALgAECgUJDgAAAA==.Bastet:BAAALgADCgUJBQAAAA==.Bayn:BAAALgAECgEJAgAAAA==.',
Be='Beeftruck:BAACLgAFFH8PAAMGAAMJAhZGDAC6AAAFAAMJAxT0NgDXAAAGAAMJDA9GDAC6AAAuAAQKfzIAAwYACQlBIZAFALACAAYACQlzH5AFALACAAUABwn7HlUvAJIBAAAA.Belletrixx:BAABLgAECn8UAAMHAAYJOAx/xwDAAAAHAAYJggt/xwDAAAANAAMJhQW9PAA5AAAAAA==.Bellonä:BAAALgAECgEJAQAAAA==.Berried:BAACLgAFFH8PAAIOAAMJNhudEwC0AAAOAAMJNhudEwC0AAAuAAQKf2wAAg4ACQmaIz4AAKQDAA4ACQmaIz4AAKQDAAAA.',
Bi='Bigdaddydom:BAAALgAECgEJAQAAAA==.Biigmâc:BAABLgAECn8WAAIKAAcJ6QUdSwAbAQAKAAcJ6QUdSwAbAQAAAA==.Biminem:BAABLgAECn8dAAIPAAgJbxXKDwC1AQAPAAgJbxXKDwC1AQAAAA==.',
Bl='Black:BAAALgAECgYJDAAAAA==.Blackwidow:BAAALgAECgMJAwAAAA==.Bloodshöt:BAABLgAECn8fAAMQAAgJdhu7OQAZAgAQAAgJdhu7OQAZAgARAAEJXgcEagAVAAABLgAECgkJJwAFAIUYAA==.',
Bo='Bodak:BAABLgAECn8bAAIMAAYJ5hnRNwCjAQAMAAYJ5hnRNwCjAQAAAA==.Boricua:BAAALgAECgEJAgAAAA==.',
Br='Brakun:BAAALgADCgIJAgAAAA==.Briline:BAAALgAECgEJAQAAAA==.Brolly:BAAALgAECgkJAgAAAA==.Bronwyn:BAAALgAFFAEJAQAAAA==.Broris:BAAALgAECgMJAwABLgAECgYJDAACAAAAAA==.Brucewii:BAAALgAECgUJBQAAAA==.Brunn:BAAALgAECgYJDAAAAA==.',
Ca='Calamari:BAAALgAECgMJBAAAAA==.Calistarius:BAACLgAFFH8NAAISAAUJ/xW+FAD7AAASAAUJ/xW+FAD7AAAuAAQKfx0AAhIACQkCFO8SAL0BABIACQkCFO8SAL0BAAAA.Caliste:BAAALgADCgIJAgABLgAFFAUJEwAPAOkeAA==.Calityy:BAAALgADCgYJBgABLgAFFAgJHAAEAFohAA==.Camine:BAABLgAECn81AAIQAAkJ/BzaLABMAgAQAAkJ/BzaLABMAgAAAA==.Candrabeckya:BAAALgADCgUJBQAAAA==.Carise:BAAALgAECgQJBAAAAA==.Castalasaras:BAABLgAECn8iAAIQAAcJZQZjEQDQAAAQAAcJZQZjEQDQAAAAAA==.Castorsilver:BAAALgAECgEJAQAAAA==.',
Ce='Certified:BAAALgAFFAMJAwAAAA==.',
Ch='Charkoal:BAAALgAECgUJBQAAAA==.Cheyane:BAABLgAECn8cAAITAAYJ7QZL8ADKAAATAAYJ7QZL8ADKAAAAAA==.Chickeny:BAAALgADCgEJAQAAAA==.Choppstik:BAABLgAECn8VAAIUAAYJpQW5XACjAAAUAAYJpQW5XACjAAAAAA==.Chåos:BAAALgAECgEJAgAAAA==.',
Co='Cocstrong:BAAALgADCggJDAAAAA==.Coldslayerck:BAAALgAECgUJBQAAAA==.Coldswiftck:BAAALgADCgkJCQAAAA==.Constäntine:BAABLgAECn8hAAIVAAkJBhgjEwBCAgAVAAkJBhgjEwBCAgAAAA==.Coriolis:BAACLgAFFH8JAAIWAAMJfQn/SgChAAAWAAMJfQn/SgChAAAuAAQKf0UAAxYACQkqGpkTAEECABYACQkqGpkTAEECABcAAwmCCvEwAI8AAAAA.',
Cr='Cravedog:BAAALgAECgYJCwAAAA==.Crittycrat:BAAALgAECgUJBQAAAA==.Crowléy:BAAALgAECgYJEQAAAA==.',
Cu='Cuddlyowl:BAABLgAECn8XAAIYAAcJwQ4DqwCFAQAYAAcJwQ4DqwCFAQAAAA==.',
Da='Dagnamagus:BAAALgAECggJDQAAAA==.Daire:BAAALgADCgYJBgAAAA==.Daliann:BAAALgAECgYJDAAAAA==.Damnation:BAAALgAECgYJCwAAAA==.Dangerduck:BAABLgAECn8fAAMXAAcJlRUwCgB+AQAXAAcJoBQwCgB+AQAWAAYJgg/+UADrAAAAAA==.Darktruth:BAAALgADCgMJAwAAAA==.Dartes:BAABLgAECn8WAAIDAAgJaxGqXQCNAQADAAgJaxGqXQCNAQAAAA==.Dashe:BAAALgAECgcJAQAAAA==.',
De='Deathadder:BAAALgAECgIJAgAAAA==.Deathcokie:BAAALgAECgYJDgAAAA==.Deatho:BAACLgAFFH8IAAISAAMJzSZ2DQBWAQASAAMJzSZ2DQBWAQAuAAQKf0UAAxIACQmZJjMCACkDABIACQmZJjMCACkDAAUAAQkJI3OdAEoAAAAA.Deathstoned:BAAALgADCgQJBQAAAA==.Deimos:BAAALgAECgEJAgAAAA==.Deratra:BAAALgADCgUJBQAAAA==.Destrocake:BAAALgAECgEJAgABLgAFFAIJAgACAAAAAA==.',
Di='Diamondshard:BAAALgAECgQJCwAAAA==.Discofreezer:BAAALgAECgEJAQAAAA==.',
Dl='Dlgadoflpjck:BAAALgAECgQJBAAAAA==.',
Dr='Draegov:BAAALgADCgYJBgAAAA==.Draeth:BAAALgADCgcJDQAAAA==.Drash:BAAALgAECgIJAgAAAA==.Dreadful:BAAALgAECgYJDgAAAA==.Dreylan:BAAALgADCgcJBwAAAA==.Dreyra:BAAALgAFFAIJAgABLgAFFAQJDAAEAKcNAA==.Drosof:BAAALgAECgEJAQAAAA==.Drow:BAAALgAECgEJAQAAAA==.',
Du='Dukalioth:BAABLgAECn8iAAIZAAcJ0BDdKAA2AQAZAAcJ0BDdKAA2AQAAAA==.Duskheart:BAAALgADCgUJBQAAAA==.',
['Dê']='Dêcay:BAACLgAFFH8aAAQBAAcJexwDBQCqAQABAAUJyhkDBQCqAQAQAAYJgR0gNACZAQARAAEJAACHUwAAAAAuAAQKfz0AAxAACQmOIhMYAOsCABAACAk4IhMYAOsCAAEABwnHIQMGAEwCAAAA.',
['Dö']='Döctorfate:BAACLgAFFH8HAAIaAAMJJQI+LwCwAAAaAAMJJQI+LwCwAAAuAAQKfyYAAhoACQnJDFUhAIsBABoACQnJDFUhAIsBAAAA.',
Ed='Ediela:BAAALgAECgQJBAAAAA==.',
Ef='Effinsoldier:BAABLgAECn8sAAITAAgJBRmaBgCUAQATAAgJBRmaBgCUAQAAAA==.',
Eg='Egfuyun:BAAALgAECgQJBwAAAA==.',
Ek='Ekko:BAAALgAECgIJAgAAAA==.',
El='Ellyy:BAAALgAFFAEJAQAAAA==.Elvira:BAAALgAECgYJCgAAAA==.',
En='Endlessagony:BAACLgAFFH8HAAIQAAMJsxAQowDRAAAQAAMJsxAQowDRAAAuAAQKfycAAhAACQmoHjAgAMECABAACQmoHjAgAMECAAAA.Endlessice:BAAALgAECgYJCgAAAA==.Ennyo:BAAALgAECgcJCgAAAA==.Enyo:BAACLgAFFH8HAAIHAAIJxxYplgCWAAAHAAIJxxYplgCWAAAuAAQKfzQABAcACQmnHzYZAI0CAAcACQmnHzYZAI0CAAgAAQkAADUnAFUAAA0AAgl4Bn1eAFMAAAAA.',
Er='Erastothenes:BAAALgAECgEJAQABLgAECggJDQACAAAAAA==.Erathas:BAABLgAECn8ZAAITAAkJsRHBYQC/AQATAAkJsRHBYQC/AQAAAA==.',
Fa='Falandril:BAABLgAECn8PAAIbAAgJZhJJHgDTAQAbAAgJZhJJHgDTAQAAAA==.Fasriel:BAAALgAECgIJAgAAAA==.',
Fe='Feata:BAAALgAECgEJAQABLgAECgYJDAACAAAAAA==.Felston:BAAALgADCgUJBQAAAA==.',
Fi='Figment:BAAALgAECgYJCwAAAA==.Fineapple:BAAALgAECgkJBwAAAA==.Fiyero:BAABLgAECn8uAAMFAAkJ8A5aLACiAQAFAAkJ8A5aLACiAQAGAAcJwgQqJQDEAAAAAA==.',
Fl='Flagcrazed:BAAALgADCgUJBQAAAA==.Fleabath:BAABLgAECn8aAAIcAAYJvgrmBACyAAAcAAYJvgrmBACyAAABLgAECgkJJAADACUNAA==.Fluffypyro:BAAALgADCgYJBgAAAA==.',
Fo='Forëplây:BAAALgAECgYJCgAAAA==.Foughum:BAAALgADCgUJBQABLgAECgYJDAACAAAAAA==.',
Fr='Friedcheekin:BAAALgADCgUJBQAAAA==.',
Fu='Fury:BAAALgADCgEJAQAAAA==.',
Ga='Galdames:BAAALgAECgEJAQAAAA==.',
Ge='Gedien:BAAALgAECgkJEQAAAA==.Gerftrazkal:BAAALgAECgUJBQAAAA==.',
Gi='Gilforty:BAABLgAECn8YAAINAAcJ0RZFDAB7AQANAAcJ0RZFDAB7AQAAAA==.',
Gl='Glep:BAAALgAECgIJAgABLgAFFAMJBAACAAAAAA==.Gloriosa:BAABLgAECn9JAAIdAAkJlRDULQDGAQAdAAkJlRDULQDGAQAAAA==.',
Go='Gonk:BAAALgAECgEJAQABLgAECgUJBwACAAAAAA==.Gorl:BAAALgAECgEJAQAAAA==.',
Gr='Griddy:BAAALgAECgEJAQAAAA==.Grootforce:BAAALgADCgMJAwAAAA==.',
Gu='Gulithark:BAAALgADCgIJAgABLgAECgUJCgACAAAAAA==.Gump:BAAALgAECgQJCwABLgAFFAMJDwAGAAIWAA==.',
Gv='Gvendalyn:BAACLgAFFH8OAAIDAAQJnh95EABTAQADAAQJnh95EABTAQAuAAQKf04AAgMACQmfJqAAAJcDAAMACQmfJqAAAJcDAAAA.',
Gw='Gweyn:BAAALgADCgUJCAAAAA==.',
Gy='Gyatsò:BAABLgAECn8jAAIUAAkJAxihEwAfAgAUAAkJAxihEwAfAgAAAA==.',
['Gø']='Gød:BAAALgADCgUJBQAAAA==.',
Ha='Hakeem:BAAALgAFFAIJBAABLgAFFAUJFgAOAPkUAA==.Harshdh:BAAALgAECgYJBgABLgAFFAMJBgAQAFMJAA==.Harshdk:BAACLgAFFH8GAAIQAAMJUwkbsgDAAAAQAAMJUwkbsgDAAAAuAAQKfy4AAxAACQnVHC0XALsCABAACQnVHC0XALsCABEABAmgAblSAEwAAAAA.Harshpawz:BAAALgAECgUJBQABLgAFFAMJBgAQAFMJAA==.',
He='Helel:BAACLgAFFH8VAAIQAAMJzR6IMgDVAAAQAAMJzR6IMgDVAAAuAAQKf0wAAxAACQntIkgJACYDABAACQntIkgJACYDABEACAk+FHAbAIEBAAAA.',
Ho='Holyhotcakes:BAAALgAECgEJAQAAAA==.Hops:BAAALgAECgIJBgAAAA==.',
Il='Illibanger:BAAALgAECgcJDQABLgAFFAMJDwAGAAIWAA==.Illidon:BAAALgADCgYJBgAAAA==.Illifiend:BAAALgAECgYJCQABLgAECgkJLgAFAPAOAA==.',
Im='Impetuous:BAAALgADCgYJDwABLgAECgkJJAADACUNAA==.',
Ip='Ipokeu:BAAALgAECgEJAQAAAA==.',
Ja='Jabmoney:BAABLgAECn8VAAMUAAgJXCM/DQBxAgAUAAgJXCM/DQBxAgAeAAEJRia0bQBpAAABLgAFFAIJAgACAAAAAA==.Jaffy:BAAALgAECgYJEgAAAA==.Jamninja:BAACLgAFFH8GAAIYAAIJByDoOQCcAAAYAAIJByDoOQCcAAAuAAQKfykAAhgACQmzG14tAGQCABgACQmzG14tAGQCAAAA.Jamxd:BAAALgAECgcJCAABLgAFFAIJBgAYAAcgAA==.Jardalanin:BAAALgADCgEJAQAAAA==.Jaroshe:BAAALgADCgUJBQAAAA==.Jaxxson:BAAALgADCgUJBQAAAA==.',
Je='Jellyfish:BAACLgAFFH8LAAIOAAUJbAocIwA2AQAOAAUJbAocIwA2AQAuAAQKfx4AAw4ACQmrElQeANsBAA4ACQlhDlQeANsBABUACAlGDDAvAFUBAAAA.Jessamyn:BAAALgAECgYJEwAAAA==.',
Jh='Jhoira:BAAALgAECgYJDwAAAA==.',
Ji='Jimmy:BAAALgAECgEJAQAAAA==.Jingu:BAAALgAECgEJAQAAAA==.',
Jo='Jokko:BAAALgADCgEJAgAAAA==.Jordyy:BAABLgAECn8oAAQIAAkJTiLyBwDtAQAHAAgJfSCeIQCQAgAIAAYJpiTyBwDtAQANAAIJERNKVABxAAAAAA==.',
Ka='Kaifren:BAACLgAFFH8OAAIYAAQJKhItYQAfAQAYAAQJKhItYQAfAQAuAAQKfx0AAhgACQmvFKFSAOQBABgACQmvFKFSAOQBAAAA.Kalifa:BAACLgAFFH8jAAMJAAgJTR7RAwCIAgAJAAgJTR7RAwCIAgAfAAEJdgH5fQAkAAAuAAQKfzcABAkACAn1I7cIAAoDAAkACAn1I7cIAAoDAB8AAQnuGBa9AEkAACAAAgmIFaFuADsAAAAA.Kalinethe:BAAALgAECgEJAgAAAA==.Karatay:BAAALgADCgQJBQAAAA==.Karrod:BAABLgAECn8UAAMRAAgJmwpMOACzAAARAAYJywtMOACzAAAQAAMJYgcqGgGLAAAAAA==.Katyce:BAAALgADCgcJDQAAAA==.',
Ke='Keilani:BAAALgAECgQJBQAAAA==.',
Ki='Kikorala:BAAALgAECgIJAgAAAA==.Killeerrkap:BAAALgAECgQJBgAAAA==.Killrmiller:BAAALgADCgMJAwAAAA==.Kirajdh:BAABLgAECn8mAAIhAAkJRR3GGACAAgAhAAkJRR3GGACAAgABLgAFFAMJBAACAAAAAA==.Kittenmitten:BAAALgADCgQJBAAAAA==.Kiv:BAAALgAFFAEJAQABLgAFFAYJJAAfACscAA==.Kiwaj:BAAALgAECgUJBQABLgAFFAMJBAACAAAAAA==.',
Kn='Knoa:BAAALgAECgYJBwAAAA==.',
Ko='Komayetu:BAAALgAECgUJCgAAAA==.',
Kr='Kraas:BAAALgAECgEJAgAAAA==.Krateis:BAABLgAECn8pAAIiAAcJ+QSYFADgAAAiAAcJ+QSYFADgAAAAAA==.Kraéthlas:BAAALgADCgYJCgAAAA==.',
Kw='Kwonhee:BAAALgADCgMJAwAAAA==.',
La='Lanadelrey:BAAALgAECggJAQAAAA==.Laurenth:BAAALgADCgkJFQAAAA==.Lazyace:BAAALgAECgYJCQAAAA==.',
Le='Lebenspender:BAACLgAFFH8HAAIMAAMJ3xpURQDUAAAMAAMJ3xpURQDUAAAuAAQKfzAAAwwACAnqIpgKAA0DAAwACAnqIpgKAA0DAAoACAnoDhU4AFgBAAAA.Lextalonis:BAAALgAECgYJCAABLgAECggJEAACAAAAAA==.',
Li='Linkstery:BAABLgAECn83AAMHAAkJbhy+IQBbAgAHAAkJJBy+IQBbAgANAAMJfRWwNADkAAAAAA==.',
Lo='Losvanknight:BAABLgAECn8jAAILAAgJJBEqDQCPAQALAAgJJBEqDQCPAQAAAA==.',
Lt='Lt:BAAALgADCgEJAQAAAA==.',
Lu='Lunalii:BAAALgAFFAIJBAABLgAFFAMJCAAFAI4lAA==.',
Ly='Lyathon:BAAALgADCgMJAwAAAA==.',
['Lï']='Lïllïë:BAAALgADCgUJBQABLgAECgYJFgAMAC4fAA==.',
Ma='Macdaddy:BAAALgAECgYJCAAAAA==.Macfluffy:BAABLgAECn8VAAIeAAgJOwrnMwAwAQAeAAgJOwrnMwAwAQAAAA==.Mactacolover:BAAALgAECgQJBAAAAA==.Madbomber:BAAALgAECgcJEAAAAA==.Maeze:BAABLgAECn8kAAIDAAkJJQ3qWgCUAQADAAkJJQ3qWgCUAQAAAA==.Magepawk:BAAALgAECgMJAwAAAA==.Magew:BAAALgADCgQJBAAAAA==.Malandru:BAACLgAFFH8RAAMjAAcJkhSjGwBCAQAjAAYJyBKjGwBCAQATAAIJvxsPhACsAAAuAAQKfy0AAxMACQnlIgIXALkCABMACAn0JAIXALkCACMACQlUDGQ6AJABAAAA.Mawwow:BAAALgAFFAEJAQABLgAFFAMJCAAhAMgPAA==.Mawwowow:BAACLgAFFH8IAAIhAAMJyA9haQC5AAAhAAMJyA9haQC5AAAuAAQKfzwAAiEACQlGG+kmADACACEACQlGG+kmADACAAAA.Maximillius:BAAALgAECgYJBwABLgAECggJJgAQAFEdAA==.Mayjoraid:BAAALgAECgEJAgAAAA==.',
Me='Meekah:BAACLgAFFH8WAAIOAAUJ+RQBHQB0AQAOAAUJ+RQBHQB0AQAuAAQKf1AAAg4ACQmxIDwEAFQDAA4ACQmxIDwEAFQDAAAA.Melbrosha:BAAALgAECgUJDAAAAA==.Melodine:BAAALgADCgEJAQAAAA==.Meriks:BAAALgAECgQJDAABLgAECgUJDQACAAAAAA==.Metaliorch:BAAALgAECgYJEAAAAA==.',
Mi='Mickmonkey:BAAALgAFFAIJAgABLgAECgMJAwACAAAAAA==.Mickspooky:BAACLgAFFH8XAAMQAAUJlhVXcwAaAQAQAAQJlhVXcwAaAQARAAEJAAABVwAAAAAuAAQKfzEAAxAACAmXIEopAJUCABAACAmXIEopAJUCABEAAwm4GAo0AMoAAAEuAAQKAwkDAAIAAAAA.Mickstormy:BAAALgAECgMJAwAAAA==.Mierin:BAAALgAECgQJBwAAAA==.Milfy:BAAALgADCgQJBAABLgAECgEJAQACAAAAAA==.Mintie:BAABLgAECn84AAIgAAkJWRdHDQANAgAgAAkJWRdHDQANAgAAAA==.',
Mo='Moozylla:BAAALgAECggJCgAAAA==.Morrïgan:BAABLgAECn8TAAIQAAYJUBehCQAwAQAQAAYJUBehCQAwAQAAAA==.Mossiah:BAAALgAECgEJAQAAAA==.',
My='Mylarna:BAABLgAECn86AAIKAAkJ1hOcAgCrAQAKAAkJ1hOcAgCrAQAAAA==.Mynx:BAABLgAECn8hAAILAAgJLiPLAgC5AgALAAgJLiPLAgC5AgAAAA==.',
['Må']='Mårsh:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîstweaver:BAAALgAECgYJDAAAAA==.',
Na='Nadira:BAAALgAECgEJAQABLgAECgkJMQARAIwVAA==.Nahkti:BAAALgADCgcJBwAAAA==.Nazarick:BAAALgAECgYJCAAAAA==.',
Ne='Neona:BAAALgAECgQJBQAAAA==.Neriv:BAABLgAECn8XAAINAAgJhw4kEAA/AQANAAgJhw4kEAA/AQAAAA==.Nexaladin:BAAALgAECgEJAgAAAA==.',
Ni='Nicor:BAAALgADCgQJBAAAAA==.Nimbus:BAAALgAECgMJBAABLgAFFAkJNQAWALUbAA==.Nixii:BAACLgAFFH8GAAIJAAIJdQ6/QAByAAAJAAIJdQ6/QAByAAAuAAQKfz4AAgkACQm9GigUADICAAkACQm9GigUADICAAAA.',
No='Nocticula:BAABLgAECn86AAIVAAkJXAkjLwBVAQAVAAkJXAkjLwBVAQAAAA==.Noriinau:BAAALgADCgIJAgAAAA==.',
Ny='Nyet:BAACLgAFFH8aAAMFAAYJbhHOEwBsAQAFAAYJbhHOEwBsAQAGAAEJYgaPRAA9AAAuAAQKfxwAAgUACQm/G1wcAGoCAAUACQm/G1wcAGoCAAAA.Nythraxia:BAAALgAECgMJAwAAAA==.Nyxiria:BAAALgADCgcJGgAAAA==.',
['Nò']='Nòir:BAAALgAECgcJCAAAAA==.',
['Nø']='Nø:BAAALgADCgMJAwAAAA==.',
Oh='Ohnarr:BAAALgAECgMJBAAAAA==.',
Ok='Oktoberfist:BAAALgAECgcJBwABLgAFFAEJAQACAAAAAA==.',
Or='Orine:BAABLgAECn8eAAIQAAkJgAwWfgBnAQAQAAkJgAwWfgBnAQAAAA==.Orion:BAAALgAFFAIJBAAAAA==.Orioz:BAACLgAFFH8TAAIPAAUJ6R6zCAAuAQAPAAUJ6R6zCAAuAQAuAAQKfyQAAg8ACAk0IvEDAOgCAA8ACAk0IvEDAOgCAAAA.',
Os='Osiras:BAAALgAECggJEAAAAA==.',
Ot='Othela:BAAALgADCgEJAQAAAA==.',
Ow='Owun:BAAALgADCgEJAQAAAA==.',
Oz='Oz:BAAALgADCgkJCgAAAA==.',
Pa='Pandapal:BAAALgAECgEJAgAAAA==.Pathbrin:BAAALgADCgEJAQAAAA==.Pauliee:BAAALgAECggJEAAAAA==.Pawkah:BAAALgAECgEJAgAAAA==.Paytowintaxi:BAAALgADCgEJAQAAAA==.',
Pe='Peyton:BAAALgADCggJEQAAAA==.',
Ph='Phoenixmage:BAAALgAECgUJBQAAAA==.',
Pr='Protection:BAAALgADCgUJBgAAAA==.',
Ps='Psychoman:BAAALgADCgMJAwABLgAFFAcJFQAJAAIfAA==.Psychomurda:BAABLgAECn8dAAMTAAYJpAvj2ADnAAATAAYJpAvj2ADnAAAkAAMJ/gdPPgBkAAABLgAFFAUJFgAOAPkUAA==.',
Pu='Puthealshere:BAAALgAFFAEJAQAAAA==.',
['Pü']='Pü:BAAALgAECgEJAQABLgAECgkJMQARAIwVAA==.',
Ra='Radio:BAAALgAECgEJAgAAAA==.Raign:BAAALgAECgEJAgAAAA==.Randomfelfox:BAAALgAECgYJCwAAAA==.Ratpack:BAAALgAFFAEJAQAAAA==.',
Re='Renfri:BAAALgAECgYJEgAAAA==.',
Ro='Robel:BAAALgAECgUJBgAAAA==.Roflburger:BAABLgAECn8XAAIPAAgJSxqsAAAcAgAPAAgJSxqsAAAcAgAAAA==.Ronaldbruce:BAAALgAECgQJBQAAAA==.Roupert:BAAALgAECgEJBAAAAA==.Rovox:BAAALgAFFAMJBAAAAA==.',
Ru='Runebane:BAAALgADCgMJAwAAAA==.Rustpaw:BAAALgAECgYJBgAAAA==.',
Sa='Sadness:BAAALgAFFAEJAQAAAA==.Sao:BAAALgAECgIJAgAAAA==.Sardrian:BAABLgAECn8gAAIDAAcJJAnuGwCZAAADAAcJJAnuGwCZAAAAAA==.',
Sc='Scurgedeath:BAAALgAECgEJAQABLgAECgkJHwAaAOoSAA==.',
Se='Seimie:BAABLgAECn9AAAINAAkJLw/sAQBIAQANAAkJLw/sAQBIAQAAAA==.Selithvia:BAABLgAECn8YAAIbAAgJWxHaKACJAQAbAAgJWxHaKACJAQAAAA==.Senethotsare:BAAALgAECggJDQAAAA==.Sethen:BAAALgADCgEJAQAAAA==.',
Sh='Shaboudi:BAAALgAECgUJBwAAAA==.Shamalicious:BAAALgADCgEJAQAAAA==.Shammwow:BAAALgAECgMJBwAAAA==.Shaofikx:BAABLgAECn80AAIeAAkJng1oJACJAQAeAAkJng1oJACJAQAAAA==.Shenknarok:BAABLgAECn8vAAIcAAYJnR4NEAC2AQAcAAYJnR4NEAC2AQAAAA==.Sherryl:BAACLgAFFH8JAAIfAAMJ6wJdWQBnAAAfAAMJ6wJdWQBnAAAuAAQKf0IAAh8ACQnEFDAoABACAB8ACQnEFDAoABACAAAA.Shmooples:BAAALgAECgEJAQAAAA==.Shunei:BAAALgADCgQJBAAAAA==.',
Si='Siema:BAAALgAECgMJAwAAAA==.Sigurd:BAAALgADCggJBwAAAA==.',
Sk='Skdragon:BAAALgADCgMJAQAAAA==.Skyari:BAACLgAFFH8IAAIFAAMJjiWiGQBMAQAFAAMJjiWiGQBMAQAuAAQKfyoAAwUACQnjItkIANQCAAUACQngItkIANQCAAYAAQm+IilfAGQAAAAA.Skyarii:BAAALgAFFAEJAgABLgAFFAMJCAAFAI4lAA==.Skylaar:BAAALgAECgMJAwAAAA==.',
So='Songweaver:BAAALgAECgEJAgAAAA==.Soulminion:BAABLgAECn8fAAMQAAYJ6wI5FAGTAAAQAAYJuAI5FAGTAAARAAEJ5gKVagAVAAAAAA==.',
Sp='Spiritshard:BAAALgAECgQJBgAAAA==.Splashmountn:BAEALgAECgYJEAAAAA==.Spriggens:BAAALgAECgMJAgABLgAFFAQJDgADAJ4fAA==.',
St='Sthane:BAAALgADCgEJAQAAAA==.Sthise:BAAALgAECgMJAwAAAA==.',
Su='Subtlety:BAABLgAECn8aAAIaAAkJ+yLsBADpAgAaAAkJ+yLsBADpAgAAAA==.Sulfurya:BAAALgAECggJEwAAAA==.',
Sy='Sykodrag:BAAALgAFFAIJAgABLgAFFAcJFQAJAAIfAA==.Sykoman:BAACLgAFFH8VAAMJAAcJAh9rGABXAQAJAAcJAh9rGABXAQAfAAEJ5QA7fQAmAAAuAAQKfygAAgkACAlwI30LAN8CAAkACAlwI30LAN8CAAAA.',
['Sì']='Sìleñtclãw:BAAALgAECgcJDgAAAA==.',
Ta='Talarina:BAAALgADCgYJBgAAAA==.Taylen:BAAALgADCgcJBwAAAA==.',
Te='Terumi:BAABLgAECn8hAAIDAAcJowbvGQCnAAADAAcJowbvGQCnAAAAAA==.Teverion:BAAALgADCgcJCwAAAA==.',
Th='Thesios:BAAALgAECgMJAwAAAA==.Thickthighs:BAAALgAECgEJAQAAAA==.Thiizz:BAAALgAFFAIJAgAAAA==.Thizz:BAABLgAECn8fAAIFAAYJPiD/KQASAgAFAAYJPiD/KQASAgABLgAFFAIJAgACAAAAAA==.',
Ti='Tic:BAABLgAFFH8JAAIHAAMJnQbONQB8AAAHAAMJnQbONQB8AAAAAA==.Tinksy:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.Tionder:BAAALgAECgYJEQAAAA==.',
To='Toeto:BAAALgADCgYJBgAAAA==.Toetoeto:BAAALgAECgMJAwAAAA==.Toetoetoete:BAAALgADCgYJBgAAAA==.Tooe:BAAALgAECgMJAwAAAA==.Torquei:BAABLgAECn8UAAIDAAYJawu/GgCiAAADAAYJawu/GgCiAAAAAA==.Toxious:BAAALgAECgQJBAAAAA==.',
Tp='Tpaman:BAAALgAECgYJBgAAAA==.Tpdruid:BAAALgAECgMJAwAAAA==.',
Ts='Tsjuda:BAAALgADCgEJAQAAAA==.Tsjudii:BAAALgADCgYJBgAAAA==.Tsjudilla:BAAALgADCgEJAQAAAA==.',
Tu='Tujefe:BAAALgAECgcJCwAAAA==.',
Ty='Tyllibust:BAAALgAECgEJAQAAAA==.',
Ug='Ugzlug:BAAALgADCgEJAQAAAA==.',
Un='Unholydk:BAABLgAFFH8HAAMTAAMJ5hExawDZAAATAAMJ5hExawDZAAAjAAIJngAARwBEAAABLgAFFAUJDgAfACEPAA==.',
Va='Vacuus:BAABLgAECn8rAAIIAAkJWgrRDACPAQAIAAkJWgrRDACPAQAAAA==.Vahldire:BAABLgAECn8jAAIYAAcJfQviDgAKAQAYAAcJfQviDgAKAQAAAA==.Valeri:BAAALgADCggJCwAAAA==.Valor:BAAALgAECgcJDgAAAA==.Varkon:BAAALgAECgYJBgAAAA==.Varn:BAAALgADCggJCAAAAA==.Varthion:BAAALgAECgYJBgAAAA==.',
Ve='Vegetas:BAAALgAECgYJBgAAAA==.Velastrasza:BAAALgADCgcJBwAAAA==.Velkethria:BAAALgAECgYJEwAAAA==.Velnyxia:BAAALgAECgQJBQAAAA==.Velovañ:BAAALgADCgEJAQAAAA==.Velthyria:BAAALgADCgkJCQAAAA==.Vestara:BAAALgAECggJCAAAAA==.Veylara:BAABLgAECn8oAAIHAAcJ7gbYpAD3AAAHAAcJ7gbYpAD3AAAAAA==.',
Vi='Viryda:BAAALgAECgQJBAABLgAECggJMQAgAFEKAA==.',
Wa='Waeder:BAAALgADCgkJDAAAAA==.Wartimebeast:BAAALgAECgUJEAAAAA==.',
We='Welp:BAAALgAECgEJBQAAAA==.',
Wh='Wherebear:BAAALgAECgIJAgAAAA==.',
Wi='Windwalker:BAAALgAECgcJCAAAAA==.Wisteria:BAABLgAECn9DAAMNAAgJURz1BQAHAgANAAgJURz1BQAHAgAIAAEJwwEzOAAaAAABLgAECgEJAgACAAAAAA==.',
Wo='Wompalot:BAAALgAECgEJAQAAAA==.Womplock:BAAALgAECgQJCQAAAA==.Wooly:BAAALgAECgMJAwAAAA==.',
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
