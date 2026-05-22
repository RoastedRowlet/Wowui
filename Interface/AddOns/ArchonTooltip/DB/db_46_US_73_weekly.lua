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

local lookup = {'Evoker-Augmentation','Evoker-Devastation','DemonHunter-Devourer','Unknown-Unknown','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Fury','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','DemonHunter-Vengeance','DemonHunter-Havoc','Priest-Holy','Mage-Frost','Paladin-Retribution','Rogue-Subtlety','Druid-Restoration','Druid-Balance','Evoker-Preservation','Druid-Guardian','Monk-Brewmaster','Warrior-Arms','Shaman-Enhancement','Monk-Windwalker','Shaman-Elemental','Warrior-Protection','DeathKnight-Frost','Monk-Mistweaver','Hunter-Survival','Priest-Shadow','Priest-Discipline','Paladin-Protection','Druid-Feral','Rogue-Outlaw','Paladin-Holy','Rogue-Assassination',}
local provider = {region='US',realm='Dragonmaw',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abbraxys:BAAALgADCgkJDgAAAA==.',
Ad='Adios:BAACLgAFFH8UAAIBAAcJrRkZBgAGAgABAAcJrRkZBgAGAgAuAAQKfxgAAwEACAkPJFcQAHMCAAEACAkPJFcQAHMCAAIABgnDDbUfADABAAAA.',
Ae='Ae:BAAALgAECgUJBwAAAA==.',
Af='Afflict:BAAALgADCgcJEwAAAA==.',
Ag='Agaar:BAABLgAECn8VAAIDAAYJ3wgRgADLAAADAAYJ3wgRgADLAAAAAA==.',
Ai='Aidasul:BAAALgAECgUJCgAAAA==.Aimer:BAAALgADCgQJBAABLgAECgYJDgAEAAAAAA==.Aireese:BAACLgAFFH8FAAMFAAIJVxb3HQB/AAAGAAIJTAkonQCNAAAFAAIJVxb3HQB/AAAuAAQKfzkAAgUACQllIfQCAOMCAAUACQllIfQCAOMCAAAA.',
Ak='Akaizhar:BAAALgADCgEJAQAAAA==.Akeera:BAAALgAECgQJBAAAAA==.',
Al='Alareth:BAAALgAECgYJCgAAAA==.Alarin:BAAALgADCgMJBQAAAA==.Alinity:BAAALgAECgUJBwAAAA==.Alnysh:BAAALgADCgUJCQAAAA==.Alvien:BAAALgAFFAMJAwAAAA==.',
Am='Amorilladron:BAABLgAECn8kAAIGAAkJ8QhWagBHAQAGAAkJ8QhWagBHAQAAAA==.',
An='Anakira:BAAALgADCggJEgAAAA==.Anséis:BAAALgAECgIJAQAAAA==.Anti:BAAALgAECgMJBAAAAA==.Antury:BAACLgAFFH8FAAIHAAMJJwxELwDGAAAHAAMJJwxELwDGAAAuAAQKfxUAAgcACQk4E840AIABAAcACQk4E840AIABAAAA.',
Aq='Aquamatty:BAAALgADCgEJAQAAAA==.',
Ar='Arcayne:BAAALgAECgMJAwAAAA==.Areeya:BAABLgAECn8iAAMIAAgJYBmGJwDxAQAIAAgJYBmGJwDxAQAJAAYJsxNISAAzAQAAAA==.Ariamis:BAAALgADCgYJBgAAAA==.Arkatt:BAABLgAECn81AAIGAAkJqhthHABZAgAGAAkJqhthHABZAgAAAA==.Arrowgance:BAAALgAECgUJCQABLgAFFAcJFAABAK0ZAA==.Artorious:BAAALgADCgUJBQAAAA==.Arulas:BAACLgAFFH8IAAIFAAMJAAmqGgCmAAAFAAMJAAmqGgCmAAAuAAQKfy4AAgUACQkGFIgNANsBAAUACQkGFIgNANsBAAAA.Arx:BAABLgAECn8XAAIKAAcJQCCaHQBhAgAKAAcJQCCaHQBhAgAAAA==.',
As='Ascrod:BAACLgAFFH8QAAQLAAUJ3xV3HgAKAQALAAUJCQ93HgAKAQAMAAIJwx7oCwBXAAANAAEJcQvEGgBGAAAuAAQKfxcABA0ABwlCGmQVAJ8BAA0ABgkAG2QVAJ8BAAsABQmgFTa0APAAAAwAAgkrGa0eAFUAAAEuAAMKBQkFAAQAAAAA.Ashami:BAAALgADCgEJAQABLgAECgcJFQAFAPkQAA==.Ashaxxi:BAAALgAECgMJAwABLgAFFAUJEAAOANQGAA==.Ashildr:BAACLgAFFH8QAAIOAAUJ1Aa3BADJAAAOAAUJ1Aa3BADJAAAuAAQKfyMABA4ACQnVEhMKAMcBAA4ACQnVEhMKAMcBAA8AAgm8A7RlAE0AAAMAAgkOBTbTAE0AAAAA.Asuwish:BAABLgAECn8tAAIQAAkJTxHzGAC6AQAQAAkJTxHzGAC6AQAAAA==.',
At='Atcjedi:BAAALgAECgcJEwAAAA==.Atmospherelo:BAAALgAECgYJBgABLgAFFAcJJgARADkkAA==.Atmospherew:BAABLgAFFH8KAAILAAIJHCWOVADVAAALAAIJHCWOVADVAAABLgAFFAcJJgARADkkAA==.Atmospherewr:BAAALgAFFAMJAwABLgAFFAcJJgARADkkAA==.Atmospherez:BAACLgAFFH8mAAIRAAcJOSQFAgCiAgARAAcJOSQFAgCiAgAuAAQKfykAAhEACQnZJkMAAAkEABEACQnZJkMAAAkEAAAA.',
Au='Audiamer:BAAALgAECgIJAgAAAA==.Auradawn:BAAALgADCgEJAQAAAA==.Auriøn:BAAALgAECgEJAQAAAA==.',
Ax='Axiom:BAAALgAECgEJAgAAAA==.',
Az='Azad:BAAALgADCgQJBAAAAA==.Azardel:BAAALgADCgQJBAAAAA==.Azmodan:BAAALgAECgMJAwAAAA==.',
['Añ']='Añdrew:BAAALgADCgIJAQAAAA==.',
Ba='Baalsdruid:BAAALgAECgcJDAAAAA==.Badgerdar:BAAALgAECggJDwAAAA==.Baep:BAACLgAFFH8MAAISAAQJZx2kDwCCAQASAAQJZx2kDwCCAQAuAAQKfxgAAhIACAl0JUUJAEcDABIACAl0JUUJAEcDAAAA.Baess:BAAALgAECgUJBQABLgAFFAQJCAATAK0YAA==.Bagels:BAABLgAECn8iAAMUAAgJKRt+EgB1AgAUAAgJKRt+EgB1AgAVAAIJRQoVWABYAAAAAA==.Baggins:BAAALgADCgMJAQAAAA==.Balance:BAABLgAECn9LAAQCAAgJwxkbBAD+AQACAAgJwxkbBAD+AQABAAYJ4xHWMwALAQAWAAMJwwTHPQB9AAAAAA==.Balooa:BAAALgAECgYJEQAAAA==.Bandrago:BAABLgAECn8VAAICAAYJSgSREQCpAAACAAYJSgSREQCpAAAAAA==.Banzan:BAAALgAECgQJBAAAAA==.Barktwain:BAABLgAECn8eAAIXAAgJqwzqGAAKAQAXAAgJqwzqGAAKAQABLgAECgUJDAAEAAAAAA==.Barracuda:BAAALgAECgQJBQAAAA==.Barrybrown:BAAALgAECgQJBwAAAA==.',
Bd='Bdikd:BAAALgADCgQJBwAAAA==.',
Be='Bearamedic:BAAALgAECgMJAwAAAA==.Beeaarr:BAABLgAECn8XAAISAAcJBBVTiABqAQASAAcJBBVTiABqAQAAAA==.Beercules:BAABLgAECn81AAIYAAkJ5hmdDQAgAgAYAAkJ5hmdDQAgAgAAAA==.Belagore:BAACLgAFFH8GAAMZAAMJzwX4FgCmAAAZAAMJWgT4FgCmAAAKAAEJawnUOABCAAAuAAQKfyUAAwoACQl2HUUYAIkCAAoACAlRHkUYAIkCABkAAwlUGvIiAO0AAAAA.Belegmor:BAAALgADCgMJBQAAAA==.Bellasnow:BAAALgAECgYJCAAAAA==.Benfrank:BAABLgAECn8oAAMXAAkJzhRzDwB9AQAVAAgJXxbjHwAAAgAXAAkJpA9zDwB9AQAAAA==.Benkkei:BAABLgAECn8wAAMKAAkJPSE8BQDTAgAKAAkJPSE8BQDTAgAZAAYJ4hXgEQCDAQAAAA==.Bethan:BAABLgAECn8cAAIRAAgJ/gQVkQAcAQARAAgJ/gQVkQAcAQAAAA==.',
Bf='Bfillz:BAABLgAECn8eAAIDAAgJhhfYOQCSAQADAAgJhhfYOQCSAQAAAA==.',
Bi='Bibi:BAAALgAECgYJDgAAAA==.Bigantall:BAAALgAECgQJBQAAAA==.Bigmedic:BAAALgAECgcJDwABLgAFFAUJDgAaAAQcAA==.Bigtea:BAAALgAECgQJCQAAAA==.Biishess:BAAALgAECgkJBAAAAA==.Bitta:BAAALgAECgcJCgAAAA==.',
Bl='Blaart:BAABLgAECn8XAAMLAAgJLxc+VgBbAQALAAYJABc+VgBbAQANAAMJpReJHACFAAAAAA==.Blacksheep:BAAALgAECgEJAgAAAA==.Blanka:BAACLgAFFH8OAAIaAAUJBBzEAgBeAQAaAAUJBBzEAgBeAQAuAAQKfyIAAxoACQmAHI4DAH4CABoACQmAHI4DAH4CAAcAAQmWASmqACMAAAAA.Blastphemous:BAAALgADCgYJBwAAAA==.Blax:BAAALgAECgcJBwAAAA==.Blindhugs:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.Bluexecute:BAAALgAECggJEwAAAA==.Blumez:BAAALgAECgcJDgAAAA==.Blùey:BAAALgADCgMJAwAAAA==.',
Bo='Bob:BAAALgADCgcJBwABLgAECgkJIQALALcbAA==.Bodytypebig:BAABLgAECn8xAAIXAAkJjR3IAwCSAgAXAAkJjR3IAwCSAgAAAA==.Boeuf:BAAALgAECgkJDwABLgAFFAMJAwAEAAAAAA==.Boicrystian:BAABLgAECn8UAAIVAAcJjwtTMAABAQAVAAcJjwtTMAABAQAAAA==.Bolillo:BAAALgAECgEJAQAAAA==.Bookitty:BAAALgAECgQJBQAAAA==.Bord:BAAALgADCgYJBgAAAA==.Bossed:BAAALgAFFAIJBAAAAA==.Bossladìe:BAAALgAECggJDQAAAA==.Boston:BAAALgAECgEJAgAAAA==.',
Br='Breezy:BAAALgAECgEJAQAAAA==.Brennly:BAAALgAECgYJBgAAAA==.Brewbies:BAAALgADCggJCgABLgAECgYJDgAEAAAAAA==.Brewness:BAAALgAECgcJEQABLgAECggJEwAEAAAAAA==.Brommix:BAAALgAECgUJCQAAAA==.Brown:BAABLgAECn8WAAIRAAcJ6xEojQAjAQARAAcJ6xEojQAjAQAAAA==.Broxy:BAAALgAECgEJAgAAAA==.',
Bu='Bucci:BAAALgADCgIJAwAAAA==.Buhbles:BAACLgAFFH8GAAIVAAYJcxcwBwCcAQAVAAYJcxcwBwCcAQAuAAQKfyEAAhUABwnZI2EUAG8CABUABwnZI2EUAG8CAAAA.Buhflobill:BAAALgADCgcJCgAAAA==.Bullshiitake:BAAALgAECgUJCgAAAA==.Burberry:BAAALgAECgEJAQAAAA==.',
Bw='Bwize:BAAALgAECgEJAQAAAA==.',
Ca='Cae:BAABLgAECn8WAAIDAAgJzBmkSgDKAQADAAgJzBmkSgDKAQAAAA==.Calaglin:BAACLgAFFH8HAAILAAMJ5g0PVADWAAALAAMJ5g0PVADWAAAuAAQKfyAAAwsACAmZH1sqAPIBAAsABwkQIVsqAPIBAA0AAgnLFo5LAIsAAAAA.Calastiria:BAAALgADCgcJDAAAAA==.Caleb:BAAALgADCgYJBgABLgAECgYJCAAEAAAAAA==.Calelorian:BAAALgADCgYJBgAAAA==.Camdragon:BAAALgADCgEJAQABLgAECgQJCAAEAAAAAA==.Cassylan:BAAALgADCgEJAQAAAA==.Catdancingif:BAABLgAFFH8HAAIbAAQJHRTACwAnAQAbAAQJHRTACwAnAQABLgAFFAYJDQAGANwhAA==.Catsack:BAAALgADCgcJBwAAAA==.Cavaloris:BAABLgAECn8UAAIcAAcJvwU4SwAbAQAcAAcJvwU4SwAbAQAAAA==.',
Ce='Cealena:BAAALgAECgQJBAAAAA==.Celesti:BAABLgAECn8gAAISAAcJWRlwUwCFAQASAAcJWRlwUwCFAQAAAA==.Cellia:BAABLgAECn8kAAISAAgJcx85GgBmAgASAAgJcx85GgBmAgAAAA==.Cevy:BAACLgAFFH8LAAIYAAQJhSLeCQCEAQAYAAQJhSLeCQCEAQAuAAQKfxcAAhgACQk+JCwFADYDABgACQk+JCwFADYDAAAA.',
Ch='Chekz:BAAALgADCgUJBQAAAA==.Chickenjoy:BAAALgADCgcJBwAAAA==.Chickensalad:BAAALgAECgIJAgABLgAECgYJCgAEAAAAAA==.Chiky:BAAALgAECgEJAQAAAA==.Chilæ:BAAALgAECgcJDAABLgAECgkJIAARADMVAA==.Chirhoxp:BAACLgAFFH8MAAIdAAMJsQUlFgCXAAAdAAMJsQUlFgCXAAAuAAQKfzgABB0ACQnaFeoMAM4BAB0ACQnWE+oMAM4BAAoAAwm5FuZnAFoAABkAAQmxDHFXACUAAAAA.Chocomousse:BAAALgADCgkJFAAAAA==.Chop:BAAALgAECgQJBAAAAA==.Christi:BAAALgAECgMJBAABLgAFFAQJBAAEAAAAAA==.Chubbstone:BAAALgADCgIJAgAAAA==.Chuckkyd:BAABLgAECn8rAAISAAgJ0h+QGgBkAgASAAgJ0h+QGgBkAgAAAA==.Chîll:BAAALgAECgcJBAAAAA==.',
Ci='Cileo:BAAALgADCgYJCQAAAA==.',
Cl='Clanka:BAAALgAECgQJBQAAAA==.Cleb:BAAALgAECgYJCAAAAA==.Clocker:BAABLgAECn8lAAIHAAgJOhu0GgAfAgAHAAgJOhu0GgAfAgAAAA==.Clumbsykoala:BAAALgAECgUJCAAAAA==.Clâyface:BAABLgAECn8eAAIVAAcJeQ0JMAADAQAVAAcJeQ0JMAADAQAAAA==.',
Co='Coasta:BAAALgAECgMJCAAAAA==.Coldlunch:BAAALgAECgIJBQAAAA==.Colton:BAABLgAFFH8FAAIWAAEJLgbYFgBKAAAWAAEJLgbYFgBKAAAAAA==.Combatcow:BAACLgAFFH8PAAIKAAQJPRs2DgBKAQAKAAQJPRs2DgBKAQAuAAQKfy0AAgoACQm1IDoLAAEDAAoACQm1IDoLAAEDAAAA.Cozmic:BAABLgAECn8zAAIRAAgJnyNJEQC+AgARAAgJnyNJEQC+AgAAAA==.',
Cq='Cq:BAAALgADCggJCAAAAA==.',
Cr='Crackseed:BAABLgAECn8WAAIUAAcJIh8/FwBFAgAUAAcJIh8/FwBFAgAAAA==.Craftymidget:BAABLgAECn8wAAIJAAkJZRCKBwDEAQAJAAkJZRCKBwDEAQAAAA==.Crit:BAAALgAECgYJEQABLgAFFAQJFAAGAEQhAA==.',
Ct='Ctn:BAAALgAECgMJBgAAAA==.',
Cu='Curandero:BAAALgAECgQJCwAAAA==.Curie:BAABLgAECn8gAAIRAAkJMxV3VwCVAQARAAkJMxV3VwCVAQAAAA==.',
Cy='Cyclohexyll:BAAALgAECgEJAgAAAA==.',
Da='Dalynar:BAAALgADCgEJAQAAAA==.Dameck:BAACLgAFFH8HAAIZAAMJPhZEEQDiAAAZAAMJPhZEEQDiAAAuAAQKfzkAAxkACQnCICQCAOYCABkACQnCICQCAOYCAAoABwnmF6BCAJoBAAAA.Dampo:BAAALgADCgYJDAAAAA==.Danakira:BAAALgADCgMJBgAAAA==.Dancemonkey:BAAALgAECgUJCQAAAA==.Daralock:BAABLgAECn8fAAMLAAgJVBs6TwDaAQALAAYJghs6TwDaAQANAAQJGRGIMwDpAAAAAA==.Darigaaz:BAAALgADCgYJBQAAAA==.Darkburley:BAAALgAECgUJBwAAAA==.Darkcastle:BAAALgADCgYJCwAAAA==.Darkholy:BAAALgAECgEJAQAAAA==.Darosh:BAAALgAECgcJCAABLgAECggJIgAeAG8aAA==.Das:BAABLgAECn8qAAIDAAkJLSEdCQDPAgADAAkJLSEdCQDPAgAAAA==.Dawnbringer:BAAALgADCgEJAQAAAA==.Dayxxday:BAAALgAECgQJBgAAAA==.Dazzeler:BAABLgAECn8iAAMeAAgJbxqvCACBAQAGAAcJiBgIUQCIAQAeAAcJexivCACBAQAAAA==.',
De='Deathdisiple:BAABLgAECn8VAAIGAAcJvQYFiQAIAQAGAAcJvQYFiQAIAQAAAA==.Deathlysue:BAAALgAECgIJAgAAAA==.Deathpetals:BAACLgAFFH8aAAIGAAcJ3CHdBAC0AQAGAAcJ3CHdBAC0AQAuAAQKfywAAgYACQkqJo4AAOoDAAYACQkqJo4AAOoDAAAA.Decepciona:BAABLgAECn8lAAQLAAcJMyIAHQA5AgALAAYJoSEAHQA5AgANAAMJaiAILAAPAQAMAAEJAAAkIwBlAAABLgAECgkJHQAfAHAdAA==.Deecaye:BAAALgAECgEJAQAAAA==.Deejaypaulyd:BAABLgAECn8hAAIgAAcJlhImHQBlAQAgAAcJlhImHQBlAQAAAA==.Delver:BAAALgADCgIJAgAAAA==.Demongirly:BAAALgADCgcJBwAAAA==.Derailed:BAAALgAECgUJBQAAAA==.Desp:BAAALgAECgMJAgABLgAFFAcJFwAhAMEVAA==.Despir:BAACLgAFFH8XAAMhAAcJwRWRBgCXAQAhAAYJVBSRBgCXAQAQAAMJUgnHBwDuAAAuAAQKfx0ABBAACAm9HawKAKICABAACAm9HawKAKICACEABglbJEUfAN4BACIAAgnVAhNQAE4AAAAA.Destantokill:BAAALgAECgMJAwAAAA==.Destro:BAAALgADCgUJBQAAAA==.Devilpoing:BAAALgAECgcJDQAAAA==.Devounor:BAAALgAECgYJCgAAAA==.',
Di='Ding:BAAALgADCgIJAgAAAA==.',
Do='Donnamatrix:BAAALgAECgIJAgAAAA==.Dorado:BAAALgADCgIJBAAAAA==.Doucheknight:BAAALgADCgMJBgAAAA==.',
Dr='Dracarizz:BAAALgADCgQJBAAAAA==.Draconius:BAAALgAECgEJAQAAAA==.Draenor:BAAALgADCgcJDQAAAA==.Dragnspittle:BAACLgAFFH8HAAMWAAMJlg5bFgDLAAAWAAMJlg5bFgDLAAABAAIJTBoOMgCkAAAuAAQKfy0ABBYACQm4Gq0DAMUCABYACQm4Gq0DAMUCAAEACQmhHOAJAHkCAAIAAwl0E+UQALQAAAAA.Dragonforce:BAABLgAECn8mAAICAAgJJxUxBQDKAQACAAgJJxUxBQDKAQAAAA==.Dragonskull:BAAALgAECgYJEAAAAA==.Dragonturd:BAABLgAECn8kAAISAAkJuRT2KgANAgASAAkJuRT2KgANAgAAAA==.Drazentar:BAABLgAECn8UAAIFAAYJnQTCMgCqAAAFAAYJnQTCMgCqAAAAAA==.Dreadnoughty:BAAALgADCgQJBAAAAA==.Dream:BAAALgADCgUJBQABLgAECgEJAQAEAAAAAA==.Dregore:BAABLgAECn8YAAIBAAcJGBIkKgA/AQABAAcJGBIkKgA/AQABLgAFFAMJBgAZAM8FAA==.Drethor:BAAALgADCgIJAgABLgAECggJJgAGAPAfAA==.Drevox:BAABLgAECn8mAAIGAAgJ8B/uKQCSAgAGAAgJ8B/uKQCSAgAAAA==.Druidheals:BAAALgAECgQJBwAAAA==.',
Du='Dulgar:BAACLgAFFH8FAAIHAAIJxRPKOgCUAAAHAAIJxRPKOgCUAAAuAAQKfzkAAgcACQmaHlMHAPICAAcACQmaHlMHAPICAAAA.Dummythick:BAAALgAECgEJAgAAAA==.Dummythicker:BAAALgADCgEJAQAAAA==.Dunsmuir:BAABLgAECn8vAAIIAAcJqx7OLQDUAQAIAAcJqx7OLQDUAQAAAA==.Dux:BAABLgAECn8OAAIDAAkJUx72QwDkAQADAAkJUx72QwDkAQAAAA==.',
['Dé']='Dévé:BAAALgADCgkJEAAAAA==.',
Ea='Eamonn:BAAALgADCgYJBgABLgAECgEJAwAEAAAAAA==.',
El='Elephant:BAAALgAECgEJAQAAAA==.Elhokar:BAAALgAECgcJDgAAAA==.Elisyum:BAAALgADCgQJBAAAAA==.Elleduff:BAABLgAECn8eAAIbAAgJkg7/IQBLAQAbAAgJkg7/IQBLAQAAAA==.Eloragon:BAAALgADCgcJDAAAAA==.Elspeth:BAAALgAECgUJCAAAAA==.Elviusel:BAAALgADCgMJAwAAAA==.Elydra:BAAALgAECgQJBQAAAA==.Elyssabeta:BAAALgAECgEJAgAAAA==.Elysstaa:BAABLgAECn8zAAMQAAkJgR8yAwAqAwAQAAkJgR8yAwAqAwAhAAQJzgtSSQC5AAAAAA==.',
En='Energizér:BAAALgAECgIJBQAAAA==.',
Eq='Equilibria:BAAALgAECgUJCwAAAA==.Equinox:BAAALgADCgIJAgAAAA==.',
Es='Esris:BAAALgAECggJKgAAAQ==.',
Et='Etík:BAAALgAECgQJBgAAAA==.',
Ev='Evomengol:BAAALgADCgUJBwABLgAFFAQJDgAVALsWAA==.',
Ex='Exaltso:BAAALgADCgkJCQAAAA==.Exorcist:BAAALgAECgEJAQAAAA==.',
Ey='Eyebright:BAAALgAECgMJAwAAAA==.Eyye:BAAALgADCgYJBgABLgAECgcJAQAEAAAAAA==.',
Fa='Falcyn:BAABLgAECn8zAAISAAgJSxGnWQB1AQASAAgJSxGnWQB1AQAAAA==.Faminex:BAACLgAFFH8YAAMcAAgJNyCwAACxAgAcAAgJNyCwAACxAgAaAAMJkh3TBwC/AAAuAAQKfx4AAxwACAkeIEIJAP4CABwACAkeIEIJAP4CABoABAmWHhEcAAoBAAAA.Famr:BAAALgADCgEJAQABLgAFFAgJGAAcADcgAA==.Farns:BAACLgAFFH8WAAIRAAcJyh6BBQAOAgARAAcJyh6BBQAOAgAuAAQKfxgAAhEACAnnJT0sAMICABEACAnnJT0sAMICAAAA.Fartmonster:BAAALgADCgEJAQAAAA==.',
Fe='Feiyue:BAABLgAECn8aAAMLAAgJyg81WAC/AQALAAgJyg81WAC/AQAMAAEJ6g0dMAA+AAAAAA==.Felinepriest:BAAALgAECgYJCQAAAA==.Felsdh:BAAALgAECgUJCgAAAA==.Felsoaked:BAAALgAECgQJCAAAAA==.Feltotes:BAAALgADCgcJDgAAAA==.Felucia:BAAALgAECgYJCgAAAA==.Fenryr:BAABLgAECn8aAAMJAAkJehwKBwDUAQAJAAgJphkKBwDUAQAIAAUJwh3jXAAzAQAAAA==.Feyvorian:BAAALgADCgMJAwAAAA==.',
Fi='Fingerbone:BAAALgADCgkJEgAAAA==.Firebäne:BAABLgAECn8dAAINAAkJhCAzAgBaAgANAAkJhCAzAgBaAgAAAA==.Firecreep:BAAALgAECgcJDAAAAA==.Fistweave:BAAALgAECgMJAwAAAA==.Fiññ:BAAALgAECgEJAQAAAA==.',
Fl='Flaminghawk:BAACLgAFFH8TAAIRAAYJrxUQIwB1AQARAAYJrxUQIwB1AQAuAAQKfy0AAhEACAmXIZEoANACABEACAmXIZEoANACAAAA.Flokkii:BAAALgAECgQJCAAAAA==.Floofie:BAAALgAECgEJAQAAAA==.Floofyfire:BAAALgAECgEJAQAAAA==.',
Fm='Fmnx:BAAALgADCgMJAwABLgAFFAgJGAAcADcgAA==.',
Fo='Foxmonk:BAAALgADCgYJBgAAAA==.Foxzxv:BAAALgAECgIJAgAAAA==.',
Fr='Frankazoid:BAABLgAECn8bAAIGAAkJ0RXcPgDBAQAGAAkJ0RXcPgDBAQAAAA==.Frankdatank:BAAALgADCgcJBwABLgAECgkJGwAGANEVAA==.Freightfrayn:BAACLgAFFH8IAAIHAAMJgQ+xMADBAAAHAAMJgQ+xMADBAAAuAAQKfywAAgcACQkwHPYGAAQDAAcACQkwHPYGAAQDAAAA.Freyin:BAABLgAECn8mAAIIAAkJ3xXZKADqAQAIAAkJ3xXZKADqAQAAAA==.Frolgar:BAAALgAECgIJAgAAAA==.Frostytotems:BAAALgADCgcJBgAAAA==.',
Fu='Fulldracarys:BAACLgAFFH8XAAIWAAYJWhxeAgD+AQAWAAYJWhxeAgD+AQAuAAQKfx8AAhYACAlyJZgCAEUDABYACAlyJZgCAEUDAAEuAAUUCAkZABQAdRkA.Fullgabagool:BAACLgAFFH8RAAIiAAUJTx5CCwDGAQAiAAUJTx5CCwDGAQAuAAQKfyUAAiIABwm5IhgHAL8CACIABwm5IhgHAL8CAAEuAAUUCAkZABQAdRkA.Fullmist:BAAALgAECgcJBgABLgAFFAgJGQAUAHUZAA==.Fulltranq:BAACLgAFFH8ZAAIUAAgJdRngAADpAgAUAAgJdRngAADpAgAuAAQKfx4AAhQABwnnIv0hADYCABQABwnnIv0hADYCAAAA.',
Fw='Fwaffy:BAABLgAFFH8FAAIGAAMJXQuCagDgAAAGAAMJXQuCagDgAAAAAA==.',
['Fë']='Fëanor:BAAALgAECgQJBAAAAA==.',
['Fø']='Føxz:BAABLgAECn8UAAIYAAgJHBwQFgBZAgAYAAgJHBwQFgBZAgAAAA==.Føxzxv:BAAALgAECggJDAAAAA==.',
Ga='Gamesucks:BAAALgAECgEJAgAAAA==.Ganster:BAAALgAECgEJAwAAAA==.Gaya:BAAALgADCgkJIAAAAA==.',
Ge='Gee:BAAALgADCgEJAgAAAA==.Geltheros:BAAALgADCggJCAAAAA==.Getzapped:BAAALgAECgQJBQAAAA==.',
Gf='Gfoo:BAACLgAFFH8MAAIbAAQJpxnjGgCeAAAbAAQJpxnjGgCeAAAuAAQKfxQAAhsABgnQGOsnAJoBABsABgnQGOsnAJoBAAAA.',
Gh='Ghidorah:BAAALgAECgMJBAAAAA==.',
Gi='Gigabloke:BAAALgADCgUJBQAAAA==.Gigastar:BAAALgAECgYJBgAAAA==.',
Gl='Glacia:BAAALgADCgUJBQAAAA==.Glaticus:BAAALgAECgEJAQAAAA==.Glimpse:BAAALgAECggJEQAAAA==.Glizzgobbler:BAAALgAECgQJBAAAAA==.',
Go='Gokêe:BAAALgAECgcJDgABLgAECgcJFQAFAE4cAA==.Golddigger:BAAALgAECgYJEwAAAA==.Golok:BAAALgAECgEJAwABLgAECgYJBgAEAAAAAA==.Goof:BAABLgAECn8YAAIGAAgJyxriKwAJAgAGAAgJyxriKwAJAgAAAA==.Goreshrieker:BAAALgAECgEJAQAAAA==.Gout:BAAALgAECgEJAQAAAA==.Goyuri:BAAALgAECggJDQAAAA==.',
Gr='Greenmonsta:BAAALgAECgcJDwAAAA==.Grimknight:BAAALgAECggJEwAAAA==.Groovi:BAAALgAECgIJAgAAAA==.Grubergeiger:BAAALgAECgUJCAABLgAFFAMJAwAEAAAAAA==.Gruunele:BAABLgAECn8jAAIaAAgJHR13BgARAgAaAAgJHR13BgARAgAAAA==.Grü:BAAALgADCgkJCQABLgAFFAMJAwAEAAAAAA==.',
Gu='Gutrigor:BAAALgAECgYJDQAAAA==.',
Gw='Gwår:BAAALgAECgYJCAAAAA==.',
['Gó']='Gókee:BAABLgAECn8VAAMFAAcJThx3EwCDAQAFAAcJThx3EwCDAQAGAAEJKgUAMQEnAAAAAA==.',
Ha='Habebe:BAAALgAFFAEJAQAAAA==.Hair:BAAALgADCgYJBgAAAA==.Hardknockz:BAAALgAECgYJCgABLgAECggJIAADAHQcAA==.Hashbrowns:BAACLgAFFH8HAAISAAMJJg96PgDwAAASAAMJJg96PgDwAAAuAAQKfygAAhIACQm9Id8KANwCABIACQm9Id8KANwCAAAA.Hav:BAEBLgAECn8vAAIRAAkJbiIlEwCwAgARAAkJbiIlEwCwAgAAAA==.Havaker:BAEALgAECgYJCgABLgAECgkJLwARAG4iAA==.Haxxorwyn:BAAALgAECgYJCQAAAA==.',
He='Healzyew:BAAALgADCggJCAAAAA==.Heartlust:BAACLgAFFH8GAAIRAAMJWwgeXwDkAAARAAMJWwgeXwDkAAAuAAQKfxgAAhEABwnRGC1yAO8BABEABwnRGC1yAO8BAAAA.Hefemusprime:BAAALgADCgkJEAAAAA==.Hellscolon:BAABLgAECn8hAAILAAkJmwptUwBjAQALAAkJmwptUwBjAQAAAA==.Hema:BAAALgAECgMJBAABLgAFFAMJBQAGAMwRAA==.Herakless:BAAALgAECggJEAAAAA==.',
Hi='Highrider:BAAALgADCggJDQAAAA==.Hillybaba:BAAALgADCgcJBwAAAA==.Hitagi:BAAALgAECgYJDQAAAA==.',
Ho='Hoa:BAAALgAECgQJBgAAAA==.Hobratickguy:BAAALgADCgUJBQAAAA==.Holi:BAAALgAECgEJAgAAAA==.Holicow:BAABLgAFFH8KAAISAAUJgxmMFgBjAQASAAUJgxmMFgBjAQAAAA==.Holii:BAAALgAECgEJAQAAAA==.Hollo:BAAALgAECgEJAQAAAA==.Holybagels:BAAALgAECgYJBgAAAA==.Holyblasts:BAAALgAECgYJEgAAAA==.Holyblowèr:BAABLgAECn8gAAISAAgJrSIbGgBmAgASAAgJrSIbGgBmAgAAAA==.Holydicsadin:BAAALgAECgQJBAAAAA==.Holydisciple:BAAALgADCgEJAQAAAA==.Holynikki:BAABLgAECn8aAAIjAAYJjwUUJwCMAAAjAAYJjwUUJwCMAAAAAA==.Holytalon:BAAALgADCgQJBQAAAA==.',
Hu='Hummingbird:BAABLgAECn8dAAIfAAkJcB2vCgCLAgAfAAkJcB2vCgCLAgAAAA==.Hungus:BAABLgAECn8dAAIPAAkJexkwCgAnAgAPAAkJexkwCgAnAgAAAA==.Huraacan:BAAALgAECgkJEQAAAA==.Hurtszick:BAAALgAECgEJAQAAAA==.',
Hy='Hybryddin:BAAALgADCgcJBwAAAA==.Hydrotiger:BAAALgAECgQJCQAAAA==.',
['Hà']='Hàra:BAAALgADCgcJCwAAAA==.',
Ia='Iamazombie:BAAALgADCgIJAgAAAA==.Iamholyman:BAAALgADCgYJBgAAAA==.',
Ig='Iggle:BAAALgADCgYJDAAAAA==.Igotchubruh:BAAALgAECgIJAgAAAA==.',
Ik='Ikitty:BAAALgAECgIJAgAAAA==.',
Il='Illiturtle:BAAALgAECgYJBgABLgAECgkJIgANAPcSAA==.Ilovemymommy:BAAALgAECggJEQAAAA==.',
Im='Imaru:BAAALgADCgYJBgAAAA==.Imnotthtgood:BAAALgAECgcJBwAAAA==.Impact:BAAALgAECgIJAgABLgAECggJSwACAMMZAA==.Implosion:BAABLgAECn8yAAILAAkJWxb6JAANAgALAAkJWxb6JAANAgAAAA==.',
In='Indigolemon:BAABLgAECn8aAAQXAAgJQRrdBQB2AgAXAAgJQRrdBQB2AgAkAAUJyBYmFgBXAQAVAAEJDhwwdQBOAAAAAA==.Inkconjurer:BAABLgAECn8eAAIRAAgJKh47OwDrAQARAAgJKh47OwDrAQAAAA==.Inkdrinker:BAAALgAECgEJAQABLgAECggJHgARACoeAA==.Inouskee:BAAALgADCgUJBQAAAA==.',
Io='Iowned:BAABLgAECn8gAAIjAAkJLBR7CgDMAQAjAAkJLBR7CgDMAQAAAA==.',
Ir='Irraelina:BAAALgADCgIJAgABLgAFFAUJDwAKAA0WAA==.',
Is='Ishundo:BAABLgAECn8fAAIbAAcJVhiMGACcAQAbAAcJVhiMGACcAQAAAA==.Isplash:BAAALgAECgEJAQAAAA==.',
Iv='Ivaellios:BAAALgADCgYJCQAAAA==.',
Iz='Izalithx:BAACLgAFFH8MAAMLAAYJFxzSAQAgAgALAAYJ6xrSAQAgAgANAAIJKhp2CwCvAAAuAAQKfxgAAwsACAkUIREqAGgCAAsABwkUIREqAGgCAA0AAwmHFoUvAP0AAAEuAAUUCAkYABwANyAA.',
Ja='Jakku:BAABLgAECn8WAAIRAAcJBgzAswB3AQARAAcJBgzAswB3AQAAAA==.Jamie:BAABLgAECn8ZAAMjAAgJBwyVHwALAQAjAAcJ/AqVHwALAQASAAIJjQ/b7gBtAAAAAA==.Jastiri:BAAALgADCgIJAgAAAA==.',
Je='Jelly:BAABLgAECn8UAAIRAAcJPh2nVgA1AgARAAcJPh2nVgA1AgAAAA==.Jezz:BAAALgADCgYJBgAAAA==.',
Ji='Jiinrop:BAEBLgAECn8WAAMNAAcJIxQbIABSAQALAAYJuRImbwCCAQANAAYJXxAbIABSAQAAAA==.Jinah:BAAALgADCgQJBAAAAA==.',
Jo='Johnassassin:BAAALgAECgYJCgABLgAECgkJOAAXADQcAA==.Jollyollie:BAAALgAECgYJCQAAAA==.Jonahkin:BAABLgAECn8YAAIVAAgJZBv8GwAiAgAVAAgJZBv8GwAiAgAAAA==.',
Ju='Judgewapner:BAAALgAECgEJAQAAAA==.Juicelord:BAAALgAECgMJBQAAAA==.Juiya:BAAALgADCgQJBAAAAA==.Juuice:BAAALgAECgEJAQAAAA==.',
Ka='Kaedes:BAACLgAFFH8OAAMVAAQJuxYLEgA1AQAVAAQJuxYLEgA1AQAkAAEJ6Q2DDQBVAAAuAAQKfzUABRUACAn0I20HAJkCABUACAlZI20HAJkCACQABgnfGe4SAIABABQAAgkoGY9zAJcAABcAAQkIFW8tAEEAAAAA.Kailyn:BAAALgAECgEJAgAAAA==.Kaiwai:BAAALgADCgYJBgAAAA==.Kaizoku:BAAALgADCgQJBAAAAA==.Kaladin:BAAALgAECgQJBQAAAA==.Kaldanarys:BAAALgAECgEJAQAAAA==.Kalenlock:BAAALgAECgYJCgAAAA==.Kaleo:BAAALgAECgIJAgABLgAECgcJEAAEAAAAAA==.Kaorii:BAAALgAECgEJAQAAAA==.Karsus:BAAALgAECgIJAgAAAA==.Katherrian:BAAALgADCgcJBwABLgAECgkJMwAIAG8fAA==.Kathorall:BAABLgAECn8sAAIIAAkJ1RQKIwAHAgAIAAkJ1RQKIwAHAgAAAA==.Kavawings:BAAALgAFFAEJAgAAAA==.Kawaiihealer:BAABLgAECn8tAAMQAAgJZB4fGgALAgAQAAgJZB4fGgALAgAhAAYJ8whiNQDsAAAAAA==.',
Ke='Keddy:BAAALgADCgMJCQAAAA==.Kemper:BAABLgAECn8iAAMgAAgJEBYoDwD3AQAgAAgJEBYoDwD3AQAIAAEJFxDa2AA5AAAAAA==.Keoua:BAAALgADCgIJAgAAAA==.Kerrs:BAAALgAECgEJAQAAAA==.Kerrz:BAAALgAECgEJAgAAAA==.',
Kh='Khaza:BAAALgADCgMJBgAAAA==.',
Ki='Kidil:BAAALgAECgIJAgAAAA==.Kidneypopper:BAABLgAECn8bAAITAAYJvB8AFACuAQATAAYJvB8AFACuAQABLgAECggJMwARAJ8jAA==.Kievit:BAABLgAECn8eAAIMAAkJ/wtZCAB4AQAMAAkJ/wtZCAB4AQAAAA==.Killá:BAAALgADCgMJAwAAAA==.Kir:BAABLgAECn8kAAMPAAYJRRyXJQCSAQAPAAUJyR2XJQCSAQADAAYJdBY8VAA4AQAAAA==.',
Kk='Kkonetica:BAAALgAECgMJAwABLgAECgkJJgAlANYXAA==.Kkrantuq:BAABLgAECn8mAAIlAAkJ1hfsAgA4AgAlAAkJ1hfsAgA4AgAAAA==.',
Kl='Klarityqt:BAAALgAECgQJBgAAAA==.Klarityx:BAABLgAECn8hAAIRAAkJ9hR1PQCCAgARAAkJ9hR1PQCCAgAAAA==.',
Ko='Kogadeath:BAAALgAECgEJAQAAAA==.Kogadraco:BAAALgAECggJEQAAAA==.Koma:BAAALgAECggJCAAAAA==.Komatos:BAACLgAFFH8PAAIcAAQJ1CQzBwCnAQAcAAQJ1CQzBwCnAQAuAAQKfzAAAhwACAnOJX0EAOkCABwACAnOJX0EAOkCAAAA.Korona:BAABLgAECn85AAIRAAkJ9hcGKgAwAgARAAkJ9hcGKgAwAgAAAA==.Korra:BAAALgADCgYJCgAAAA==.',
Kr='Kraptastic:BAAALgADCgEJAQAAAA==.',
Ky='Kylar:BAAALgAECgYJCwABLgAECgkJJgAlANYXAA==.',
['Kê']='Kênsêi:BAAALgAECgYJDAABLgAECgkJIQAcAC4SAA==.',
['Kô']='Kôan:BAAALgADCgkJEQAAAA==.',
La='Laserbeams:BAAALgAECgYJDgAAAA==.',
Le='Leafyjoe:BAAALgAECgcJCAAAAA==.Lechencaja:BAAALgAECgQJBgABLgAECggJGgAdAAwUAA==.Leehi:BAAALgAECgYJCQAAAA==.Legendarybob:BAAALgAECgMJAwAAAA==.Legomyeggö:BAABLgAECn8cAAIGAAcJsRsPVAD1AQAGAAcJsRsPVAD1AQAAAA==.',
Lh='Lhera:BAABLgAECn80AAQgAAkJPB6kBQCTAgAgAAkJ1R2kBQCTAgAIAAcJzRrXMwDgAQAJAAcJDRclDABTAQAAAA==.',
Li='Lilglittery:BAAALgADCgYJBgAAAA==.Lilnikki:BAAALgADCgcJDwAAAA==.Lilypotter:BAAALgAECgIJAwAAAA==.Lisp:BAAALgADCgYJBgAAAA==.Livathian:BAABLgAECn8dAAISAAgJWRR/TQCVAQASAAgJWRR/TQCVAQAAAA==.',
Ll='Lloromannic:BAAALgAECgQJBAAAAA==.',
Lo='Lockingdown:BAAALgADCgYJCAAAAA==.Longshotx:BAAALgADCgYJBgAAAA==.Lothuial:BAAALgADCgEJAgAAAA==.',
Lu='Lucellis:BAAALgAECgcJBwAAAA==.Lumira:BAABLgAECn8tAAIIAAkJJh1sFQBdAgAIAAkJJh1sFQBdAgAAAA==.Lunavel:BAAALgAECgQJBQAAAA==.Lunethi:BAAALgADCgYJCAAAAA==.Lurex:BAAALgADCgEJAgAAAA==.Luzwarlockok:BAAALgAECgcJCAAAAA==.',
Lz='Lzybys:BAAALgADCgYJBgAAAA==.',
Ma='Macrococ:BAAALgADCgQJAwAAAA==.Madris:BAABLgAECn8cAAMiAAcJphnTEwDoAQAiAAcJphnTEwDoAQAhAAcJQw2TKgAoAQAAAA==.Maelstroke:BAAALgADCgcJBwAAAA==.Magimagi:BAAALgAECgYJCQAAAA==.Magtharn:BAAALgAECgUJBwABLgAECggJDQAEAAAAAA==.Magusdark:BAAALgAECgYJCAAAAA==.Makkascholar:BAAALgAECgIJAgAAAA==.Makotoh:BAAALgADCgEJAQAAAA==.Malnorr:BAABLgAECn8dAAMLAAkJNBsjFAB1AgALAAkJNBsjFAB1AgANAAEJAACSaQA/AAAAAA==.Manbeerpig:BAAALgAFFAMJAwAAAA==.Mandykiinz:BAAALgAECgYJEgAAAA==.Mannimarco:BAAALgADCgEJAQAAAA==.Marcodison:BAAALgADCgcJCAAAAA==.Maryillo:BAACLgAFFH8nAAMXAAgJxxd2AABQAgAXAAgJqxZ2AABQAgAVAAUJVSHVBACeAQAuAAQKfykAAxcACAlAJJ8CAPwCABcACAkUIZ8CAPwCABUACAnFH6wNAMACAAAA.',
Mc='Mcflurry:BAAALgAECgQJBAAAAA==.',
Me='Medd:BAAALgAECgUJCQAAAA==.Mengol:BAAALgADCgMJAwABLgAFFAQJDgAVALsWAA==.Mennil:BAAALgAECgUJCgAAAA==.Meolater:BAABLgAECn8jAAIWAAgJZB/fAwC6AgAWAAgJZB/fAwC6AgAAAA==.Meowz:BAAALgADCgUJBQAAAA==.Mesmerise:BAABLgAECn8ZAAIFAAgJIyCiCQAoAgAFAAgJIyCiCQAoAgAAAA==.',
Mh='Mhyrora:BAAALgAECgEJAQAAAA==.',
Mi='Mick:BAAALgADCgcJBwAAAA==.Midorii:BAAALgADCggJCwAAAA==.Mikeygee:BAAALgAECgEJAQABLgAECggJDQAEAAAAAA==.Mio:BAAALgADCgcJBwAAAA==.Miraya:BAACLgAFFH8MAAILAAQJnQsOPwAMAQALAAQJnQsOPwAMAQAuAAQKfygAAwsACAm6GVMwAEsCAAsACAkJGVMwAEsCAA0ABAmtCZA6AMoAAAAA.Misbehaved:BAAALgADCgcJDAAAAA==.Mishrakthul:BAAALgAECgQJCAAAAA==.Missfear:BAAALgADCggJFwAAAA==.',
Mm='Mmrsdelaneys:BAAALgADCgEJAgAAAA==.',
Mo='Mokari:BAEBLgAECn84AAMgAAkJjiL7AQAEAwAgAAkJIyL7AQAEAwAIAAcJxhzrIgA0AgAAAA==.Mon:BAAALgADCgQJBwAAAA==.Moonfrost:BAABLgAECn8WAAIlAAkJBgzrBACtAQAlAAkJBgzrBACtAQAAAA==.Morbidchaos:BAACLgAFFH8UAAIDAAcJMx1lBAA4AgADAAcJMx1lBAA4AgAuAAQKfyIAAgMACQkbI8cFAGkDAAMACQkbI8cFAGkDAAAA.Morbius:BAAALgAECgcJEQAAAA==.Morglum:BAABLgAECn8pAAMLAAgJ8xvBOQAlAgALAAgJ8xvBOQAlAgANAAEJAAChbAA7AAAAAA==.Morlog:BAAALgAECgEJAQAAAA==.Mosnar:BAAALgADCgEJAQAAAA==.Movak:BAEALgADCgYJDAABLgAECgkJLwARAG4iAA==.',
Mu='Muddywalrus:BAAALgAECgIJCQAAAA==.Mukatsuku:BAAALgAECgcJDwAAAA==.Muscida:BAAALgADCgEJAQAAAA==.',
My='Mykg:BAAALgAECggJDQAAAA==.Myzas:BAAALgAECgYJBgAAAA==.',
['Mâ']='Mâyüri:BAABLgAECn8hAAMcAAkJLhKSIACJAQAcAAkJLhKSIACJAQAHAAMJtAZslABLAAAAAA==.',
Na='Naaldlooshii:BAAALgAECgEJAQABLgAECgIJAwAEAAAAAA==.Naeth:BAABLgAECn80AAISAAkJex5gEACpAgASAAkJex5gEACpAgAAAA==.Nalrot:BAAALgADCgYJCAABLgAECggJGQAFACMgAA==.Narcine:BAABLgAECn8zAAMIAAkJbx8WDQCkAgAIAAkJbx8WDQCkAgAgAAYJshvBEQCnAQAAAA==.Narina:BAAALgAECgkJDQAAAA==.Naví:BAAALgAECggJEwAAAA==.',
Ne='Necie:BAACLgAFFH8HAAIXAAMJ4gpRDQCfAAAXAAMJ4gpRDQCfAAAuAAQKfzkAAhcACQnjHLgDAJYCABcACQnjHLgDAJYCAAEuAAEKAQkBAAQAAAAA.Neckred:BAAALgADCgEJAQAAAA==.Nedri:BAABLgAECn8WAAMLAAgJWQ+tUQBoAQALAAgJnwytUQBoAQAMAAQJMgw6FwDEAAAAAA==.Nee:BAABLgAFFH8UAAIHAAYJ8xk+AwCmAQAHAAYJ8xk+AwCmAQAAAA==.Nelor:BAABLgAECn8XAAIDAAgJkxFqSABeAQADAAgJkxFqSABeAQAAAA==.Nerftitty:BAAALgAECgEJAQAAAA==.Nethya:BAAALgADCgMJAwAAAA==.',
Ni='Nibblet:BAAALgADCgEJAQAAAA==.Nightnight:BAAALgAECgYJCQAAAA==.Nikii:BAAALgADCgUJBQAAAA==.Nikkibear:BAAALgAECgMJBAAAAA==.Ninjason:BAAALgAECgEJAQAAAA==.Nio:BAAALgADCgUJBQAAAA==.Nissa:BAAALgAECgEJAQAAAA==.Nitashal:BAABLgAECn8xAAMWAAkJsSSEAACzAwAWAAkJsSSEAACzAwACAAEJwAYJQAAwAAAAAA==.',
No='Nobudagero:BAAALgAECgYJDgAAAA==.Nomag:BAAALgAECgcJAQAAAA==.Noremac:BAAALgADCgkJGgAAAA==.Norgalis:BAAALgADCgMJBQAAAA==.Nosman:BAAALgAECgMJAwAAAA==.',
Nr='Nrowtuo:BAAALgAECgYJDwAAAA==.',
Nu='Nummnomms:BAAALgAECgcJEQAAAA==.',
Ny='Ny:BAAALgADCgEJAwAAAA==.Nythariel:BAAALgADCgUJBQAAAA==.',
['Në']='Nëzükõ:BAAALgADCgkJFgABLgAECgkJIQAcAC4SAA==.',
Oa='Oathbreaker:BAAALgADCgcJBQAAAA==.',
Ol='Olivabiscuit:BAABLgAECn8VAAMGAAYJABWikgBbAQAGAAYJABWikgBbAQAFAAQJEg5UMQC2AAAAAA==.Oliviawildè:BAAALgAECgQJBgAAAA==.Olivya:BAAALgAECgQJBwAAAA==.',
On='Onepump:BAAALgADCgMJAwAAAA==.',
Oo='Oogiessxd:BAABLgAECn8WAAMiAAUJuRHUMgDoAAAiAAUJ2QzUMgDoAAAQAAIJtBNsbQBzAAAAAA==.Oops:BAAALgADCgQJBAAAAA==.',
Or='Ordel:BAAALgADCgMJAwAAAA==.Orwata:BAAALgADCgcJBwAAAA==.',
Ou='Ouskun:BAAALgADCgQJBgAAAA==.',
Ow='Owynn:BAAALgAECgMJAwAAAA==.',
Oz='Ozurot:BAABLgAECn8iAAIbAAgJFRCcHwBdAQAbAAgJFRCcHwBdAQAAAA==.',
Pa='Pakoh:BAACLgAFFH8FAAIUAAIJ7BfvGACaAAAUAAIJ7BfvGACaAAAuAAQKfykABBQACAnuI4gbAF8CABQABgkYJIgbAF8CABUACAlFIdERAPgBABcAAwmyIpwVAC0BAAAA.Palabok:BAABLgAECn8YAAISAAkJfhmxGgBjAgASAAkJfhmxGgBjAgAAAA==.Paladang:BAAALgAECgcJAQAAAA==.Paladont:BAAALgAECgMJBwAAAA==.Palmarez:BAAALgADCgYJBQAAAA==.Panchita:BAABLgAECn8bAAQiAAgJPxV+GgCiAQAiAAcJQxJ+GgCiAQAQAAUJNhgPTgAAAQAhAAIJFAWmVwBMAAAAAA==.Pandemoniúm:BAABLgAECn8aAAIbAAYJhhzAHAB3AQAbAAYJhhzAHAB3AQAAAA==.Panfriedrice:BAAALgAECgkJBgAAAA==.Pantyblossom:BAABLgAECn8aAAIQAAYJWxlzHACZAQAQAAYJWxlzHACZAQAAAA==.Pasdovqr:BAAALgAECgUJEAAAAA==.',
Pe='Peaches:BAABLgAECn8XAAMmAAgJYR62CQCqAgAmAAgJYR62CQCqAgAjAAEJ0ArDPAAqAAAAAA==.Peewees:BAAALgADCgcJBwAAAA==.Pegasus:BAABLgAECn8tAAINAAgJHRoKBACnAgANAAgJHRoKBACnAgAAAA==.Perlman:BAABLgAECn8UAAIDAAgJoBUmLQDKAQADAAgJoBUmLQDKAQAAAA==.Persivul:BAAALgAECgUJBgAAAA==.Pewpewz:BAAALgAECgYJDQABLgAECgkJOAAKABIUAA==.',
Ph='Phaeddrus:BAAALgAECgYJCwAAAA==.Phaedross:BAAALgAECgEJAQAAAA==.Pheret:BAAALgAFFAIJAwAAAA==.Phobos:BAABLgAECn84AAIBAAkJ+QcBJwBTAQABAAkJ+QcBJwBTAQAAAA==.Phogood:BAAALgAECgUJCwAAAA==.Phrix:BAAALgAECgQJBgABLgAFFAQJEQACAGcVAA==.',
Pi='Pineapple:BAAALgAECgUJCQABLgAECgcJEwAGAPEfAA==.Pineapplelol:BAABLgAECn8TAAMGAAcJ8R9WKQAUAgAGAAcJ8R9WKQAUAgAFAAIJdQ+zNwBjAAAAAA==.Pineapplë:BAABLgAECn8UAAMDAAgJEhmOLgBCAgADAAgJEhmOLgBCAgAPAAEJBR83awA7AAABLgAECgcJEwAGAPEfAA==.Pinecone:BAAALgADCgUJBQABLgAECgcJEwAGAPEfAA==.Pinëapple:BAAALgAECgYJCgABLgAECgcJEwAGAPEfAA==.Pissdanger:BAAALgAECgEJAQAAAA==.Piñeapple:BAAALgAECgYJDAABLgAECgcJEwAGAPEfAA==.',
Pl='Plot:BAAALgAECggJEgAAAA==.',
Po='Poekimaw:BAAALgAECgQJAwAAAA==.Polpo:BAACLgAFFH8XAAISAAUJkyT+CQCmAQASAAUJkyT+CQCmAQAuAAQKfxYAAhIACAkXJR0oAIQCABIACAkXJR0oAIQCAAAA.Poppinin:BAABLgAECn8jAAISAAgJaxcgPwDBAQASAAgJaxcgPwDBAQAAAA==.Powerwordhug:BAAALgAECgEJAQAAAA==.',
Pr='Prancer:BAAALgADCgMJAwAAAA==.Prevaleon:BAAALgADCgMJAwAAAA==.Procasual:BAABLgAECn8hAAIaAAgJPgh4EAAzAQAaAAgJPgh4EAAzAQAAAA==.',
Ps='Psychritic:BAABLgAECn8iAAIRAAgJFiLdGgB/AgARAAgJFiLdGgB/AgAAAA==.Psyence:BAAALgAECgQJCgABLgAECgkJIAAOANwUAA==.',
Pt='Pterodactyl:BAAALgAECgYJCgAAAA==.',
Pu='Purpletotem:BAAALgAECgQJBAAAAA==.Purrsnikitty:BAABLgAECn8gAAIIAAgJ0RU/NwCsAQAIAAgJ0RU/NwCsAQAAAA==.',
['Pà']='Pànzer:BAAALgAECgQJBAAAAA==.',
['Pî']='Pîneapple:BAAALgADCgcJCwABLgAECgcJEwAGAPEfAA==.',
['Pô']='Pô:BAAALgAECgQJBgABLgAECggJJAASAHMfAA==.',
Qq='Qqmoarnoob:BAAALgADCgYJBwAAAA==.',
Qu='Quillmane:BAAALgAECgYJEQABLgAFFAQJEQACAGcVAA==.Quiza:BAAALgADCgIJAgAAAA==.',
Ra='Raevyn:BAAALgAECgYJDgAAAA==.Ragebate:BAABLgAECn8gAAIDAAgJdBzbLwA8AgADAAgJdBzbLwA8AgAAAA==.Ragingbohner:BAAALgADCgcJBwAAAA==.Ragingdeath:BAAALgAECgQJBwAAAA==.Ragingson:BAAALgAECgQJBgAAAA==.Rainakamugi:BAABLgAECn8YAAMWAAkJfw5pDQCvAQAWAAkJfw5pDQCvAQABAAQJcgLlWgBpAAAAAA==.Rakko:BAAALgAECgMJAwAAAA==.Ralphanir:BAABLgAECn8kAAIHAAgJGRm7HQAHAgAHAAgJGRm7HQAHAgAAAA==.Rangi:BAAALgADCgcJCwAAAA==.Raskreia:BAAALgAECgQJCgAAAA==.Ravenclaw:BAAALgADCgEJAQAAAA==.Rawdogging:BAAALgADCgYJCgAAAA==.Rawrxd:BAAALgAECgYJEgAAAA==.Raygyu:BAAALgAECgQJBgABLgAECgkJKgAIAKcgAA==.Rayshoots:BAABLgAECn8qAAQIAAkJpyD3FwB5AgAIAAkJpyD3FwB5AgAgAAYJOhVaIABIAQAJAAEJhgAtnAAMAAAAAA==.Rayvoker:BAAALgADCgYJCgABLgAECgkJKgAIAKcgAA==.',
Re='Realkaleo:BAAALgAECgcJEAAAAA==.Rebekil:BAABLgAECn8WAAMVAAcJzQg9SAAMAQAVAAcJzQg9SAAMAQAUAAYJPQRUhQDMAAAAAA==.Rediline:BAAALgAECgUJCwAAAA==.Rekkfest:BAAALgADCgMJAwAAAA==.Remster:BAAALgADCgYJBgAAAA==.Rexari:BAAALgADCgkJFQAAAA==.Rezmae:BAAALgAECgQJBgAAAA==.Reznàp:BAAALgADCgUJBQAAAA==.',
Rh='Rhamah:BAAALgADCgEJAQAAAA==.Rheba:BAAALgADCgEJAQAAAA==.',
Ri='Rinrin:BAAALgADCgYJBgAAAA==.Riot:BAAALgAECgIJBAABLgAFFAQJFAAGAEQhAA==.Risotto:BAAALgADCgcJBwAAAA==.',
Ro='Rokømani:BAAALgADCgEJAQAAAA==.Roron:BAAALgAECgUJDAAAAA==.Rothgar:BAAALgADCgEJAQAAAA==.Roxy:BAAALgAECgUJBQAAAA==.',
Rr='Rrainmann:BAAALgADCgEJAQAAAA==.',
Ru='Rubmaps:BAAALgADCgUJBQAAAA==.',
Ry='Ryujin:BAAALgADCggJDwAAAA==.',
Sa='Sabi:BAAALgAECgYJEgAAAA==.Sadboy:BAAALgAECgYJEAAAAA==.Sadface:BAAALgAECgQJBAAAAA==.Safetyspork:BAAALgAECgEJBAABLgAECgcJAQAEAAAAAA==.Sagë:BAABLgAECn8XAAImAAYJCR8DGQDxAQAmAAYJCR8DGQDxAQAAAA==.Salamasina:BAAALgADCgIJAgAAAA==.Salsa:BAAALgAECgEJAQAAAA==.Samunzo:BAAALgADCgQJBQAAAA==.',
Sc='Schobe:BAAALgADCgEJAgABLgAECgIJAwAEAAAAAA==.Schönen:BAABLgAFFH8GAAIRAAMJrAKiZADMAAARAAMJrAKiZADMAAAAAA==.Scojo:BAAALgAECgEJAQAAAA==.Scârecrow:BAABLgAECn8TAAMDAAYJxBnxSQBZAQADAAYJxBnxSQBZAQAPAAEJzRHcawA6AAAAAA==.',
Se='Sehtherria:BAAALgAECgEJAgAAAA==.Seishouu:BAAALgADCgUJBQAAAA==.Sejien:BAABLgAECn8iAAMLAAYJwh+8NgC+AQALAAYJwh+8NgC+AQANAAEJAAAHdgAvAAAAAA==.Senjou:BAAALgAECgYJEQAAAA==.Sermet:BAAALgAECgIJAgABLgAECgkJIwADAJQeAA==.Serous:BAABLgAECn8jAAIKAAkJAx2JDgBDAgAKAAkJAx2JDgBDAgAAAA==.Serwellmet:BAAALgAECgYJBwABLgAECgkJIwADAJQeAA==.Setal:BAACLgAFFH8RAAMCAAQJZxU2AgBNAQACAAQJZxU2AgBNAQABAAIJwAbAHACLAAAuAAQKfzAAAwIACAndHa4DABICAAEACAnlGlkPAIECAAIACAnfHK4DABICAAAA.Sevrik:BAABLgAECn8lAAILAAgJBBypLgBSAgALAAgJBBypLgBSAgAAAA==.',
Sh='Shadowbruin:BAAALgAECgUJBgAAAA==.Shammoo:BAAALgAECgEJAQAAAA==.Shammycammy:BAAALgAECgQJCAAAAA==.Shaoling:BAAALgADCgEJAQAAAA==.Sharadra:BAAALgAECgYJDgAAAA==.Shecklethief:BAABLgAECn8eAAMiAAgJAQ0eGAC4AQAiAAgJAQ0eGAC4AQAQAAMJigJPTwBQAAAAAA==.Shimmyx:BAAALgADCgcJFgAAAA==.Shinizokonai:BAAALgAECgEJAQAAAA==.Shinydude:BAAALgAECgUJCwAAAA==.Shlendra:BAAALgAECgYJBgAAAA==.Shockwavee:BAAALgADCgQJBAABLgAECggJMwARAJ8jAA==.Shogunz:BAAALgAECgcJCgAAAA==.Shroudedmoon:BAACLgAFFH8OAAInAAUJYCEJAQCWAQAnAAUJYCEJAQCWAQAuAAQKfx0AAycACAlCJJ0BAAYDACcACAlCJJ0BAAYDACUABAlzGQcJAOkAAAEuAAUUBgkLABIA8R8A.Shàmshii:BAAALgADCgMJBQAAAA==.',
Si='Silk:BAABLgAECn8WAAMnAAcJDBMSCQBrAQAnAAcJDBMSCQBrAQATAAEJ+Qd2XwA3AAABLgAECggJFwAmAGEeAA==.Sinapaladin:BAABLgAECn8XAAMSAAYJxRkTWgB0AQASAAYJxRkTWgB0AQAjAAQJiAdHKgB2AAABLgAECgYJJAAPAEUcAA==.Sinavyr:BAAALgAECgMJAwAAAA==.',
Sk='Skarrtusk:BAAALgAECggJCAAAAA==.Skroh:BAAALgADCgEJAQAAAA==.Skwsham:BAABLgAECn8oAAIcAAkJKR14CQCBAgAcAAkJKR14CQCBAgAAAA==.',
Sl='Slabbcrakle:BAAALgADCgcJCgAAAA==.Slabbhammer:BAABLgAECn8mAAISAAgJGxmTMwDqAQASAAgJGxmTMwDqAQAAAA==.Slappers:BAAALgADCgIJAgAAAA==.Slaykanit:BAAALgAECgQJBQAAAA==.Slothzor:BAAALgAECgEJAQAAAA==.',
Sm='Smooshednewt:BAAALgAECgQJDwAAAA==.',
Sn='Sneakyknight:BAABLgAECn8XAAITAAgJ+gokHABZAQATAAgJ+gokHABZAQAAAA==.',
So='Sobaley:BAAALgADCgQJBAAAAA==.Soggysausage:BAAALgAECgYJBwAAAA==.Sohvar:BAAALgAECgYJCwAAAA==.Sophira:BAABLgAECn8sAAIVAAkJZRtECQB3AgAVAAkJZRtECQB3AgAAAA==.Sosneaky:BAAALgAECgQJBAAAAA==.',
Sp='Sparkels:BAAALgADCgYJBgAAAA==.Spectre:BAAALgAECgEJAQABLgAFFAQJFAAGAEQhAA==.Speknawz:BAACLgAFFH8IAAITAAQJrRgXDQBVAQATAAQJrRgXDQBVAQAuAAQKfyEAAhMACAlDHeoLABkCABMACAlDHeoLABkCAAAA.Spishak:BAAALgAECgYJBgAAAA==.Splatzill:BAAALgAECgcJEgAAAA==.Spoiledangel:BAABLgAECn8gAAIQAAgJ0hurEQAKAgAQAAgJ0hurEQAKAgAAAA==.Spookyhallow:BAABLgAECn8YAAIQAAgJ2wsJMgB4AQAQAAgJ2wsJMgB4AQAAAA==.Spoonhat:BAAALgAECgEJAQABLgAECgcJAQAEAAAAAA==.Springz:BAACLgAFFH8fAAIiAAcJ5B02AQBAAgAiAAcJ5B02AQBAAgAuAAQKfxgAAyIACAktIqYQABACACIABwmuIqYQABACACEAAQmsBVZkADAAAAAA.',
St='Starryniight:BAABLgAECn8uAAILAAgJfAj6ZQA0AQALAAgJfAj6ZQA0AQAAAA==.Stereodh:BAABLgAECn8rAAIDAAgJ4BizKADfAQADAAgJ4BizKADfAQAAAA==.',
Su='Suetang:BAAALgAECgQJBAAAAA==.Sullengard:BAAALgADCgkJCQAAAA==.Supanova:BAAALgAFFAEJAgAAAA==.Surwick:BAABLgAECn84AAIjAAkJNBJXCwC6AQAjAAkJNBJXCwC6AQAAAA==.Sussybaka:BAAALgADCgUJBQAAAA==.',
Sv='Svelus:BAACLgAFFH8LAAISAAYJ8R8XBQDqAQASAAYJ8R8XBQDqAQAuAAQKfxQAAhIABgk1I3g7ADYCABIABgk1I3g7ADYCAAAA.',
Sw='Swangin:BAAALgAECgEJAQAAAA==.Swingin:BAABLgAECn8kAAIjAAgJ+Qx0FQAkAQAjAAgJ+Qx0FQAkAQAAAA==.Swishers:BAAALgAECgUJBgAAAA==.',
Sy='Synapticvoid:BAABLgAECn8WAAIDAAgJMAaAdgDgAAADAAgJMAaAdgDgAAAAAA==.',
['Sï']='Sïxx:BAAALgADCgMJAwAAAA==.',
Ta='Tachealz:BAAALgAECgYJCAABLgAECgEJAQAEAAAAAA==.Talyynn:BAAALgAECgEJAQAAAA==.Tanurhide:BAAALgAECgQJBgAAAA==.Tapdat:BAACLgAFFH8KAAMLAAMJ6gu0WgDFAAALAAMJ6gu0WgDFAAANAAEJwg70FQBTAAAuAAQKfyQAAw0ACAlSHVkLAAsCAA0ABwl6GVkLAAsCAAsABwl3H9hIAPABAAAA.Tarram:BAAALgAECgYJCAAAAA==.Tartin:BAACLgAFFH8LAAIVAAUJ5gv7FwATAQAVAAUJ5gv7FwATAQAuAAQKfxsAAhUACAnTH1sOALgCABUACAnTH1sOALgCAAAA.Tasveira:BAAALgADCgUJBgAAAA==.Taurenmill:BAABLgAFFH8IAAIHAAMJOxYzKgDdAAAHAAMJOxYzKgDdAAAAAA==.',
Te='Teapsy:BAABLgAECn8aAAIbAAkJsCGtAgASAwAbAAkJsCGtAgASAwAAAA==.Techi:BAAALgAECgYJBgAAAA==.Tedward:BAAALgADCgQJBAAAAA==.Teener:BAAALgADCgQJBAAAAA==.Temres:BAABLgAECn8jAAQDAAkJlB7uCwCtAgADAAkJlB7uCwCtAgAOAAUJKxRaFQABAQAPAAMJXBlEJgDfAAAAAA==.Tendermulva:BAABLgAECn8hAAIMAAgJhgpXCADFAQAMAAgJhgpXCADFAQAAAA==.Tentoestwo:BAAALgAECgYJCgAAAA==.Tenzzo:BAAALgAECgUJBQAAAA==.Terekk:BAAALgADCgcJEwAAAA==.Terna:BAAALgADCgYJBwAAAA==.Tevashi:BAAALgAECgYJCwAAAA==.',
Th='Thannin:BAAALgAECgMJBgAAAA==.Tharekon:BAABLgAFFH8HAAMKAAMJehiKKQCeAAAKAAIJVxWKKQCeAAAZAAEJwB78HgBaAAAAAA==.Thedrink:BAAALgAECgUJBwAAAA==.Thermox:BAAALgAECgYJBwAAAA==.Thesauce:BAACLgAFFH8VAAIbAAYJRCEpAQD/AQAbAAYJRCEpAQD/AQAuAAQKfyMAAhsACQnBJF8CAHgDABsACQnBJF8CAHgDAAAA.Thesmallman:BAAALgADCgcJDgAAAA==.Thexcurse:BAAALgADCgcJBwAAAA==.Thimo:BAAALgAECgQJCQABLgAECgQJCgAEAAAAAA==.Thrikal:BAABLgAECn8wAAIPAAkJzRNQEQCvAQAPAAkJzRNQEQCvAQAAAA==.Throh:BAAALgADCgEJAQAAAA==.Thugd:BAAALgAECgYJEAAAAA==.',
Ti='Tiadalma:BAAALgAECgcJEgAAAA==.Tiek:BAABLgAECn80AAIKAAkJJhnxDQBKAgAKAAkJJhnxDQBKAgAAAA==.Tindissa:BAAALgAECgMJAwAAAA==.Tivis:BAABLgAECn8rAAINAAkJmQw3CQBjAQANAAkJmQw3CQBjAQAAAA==.',
To='Toastydemon:BAABLgAECn8nAAIDAAgJtBOBOQCUAQADAAgJtBOBOQCUAQAAAA==.Tokedope:BAAALgAECgUJCwAAAA==.Tomoe:BAAALgADCgkJCQAAAA==.Tomsmg:BAABLgAFFH8KAAIRAAQJqA3aQQA3AQARAAQJqA3aQQA3AQAAAA==.Tonen:BAABLgAECn8eAAIKAAcJ2RdWIwCKAQAKAAcJ2RdWIwCKAQAAAA==.Toofs:BAAALgAECgYJEAAAAA==.Torno:BAAALgAECgkJDgAAAA==.Totemtonya:BAAALgAECgEJAQAAAA==.Toxifay:BAAALgAECgYJCQAAAA==.Toywar:BAAALgADCgcJBgAAAA==.',
Tr='Traell:BAAALgAECgMJAwAAAA==.',
Ts='Tsilatra:BAAALgAECgQJBAAAAA==.',
Tu='Tufluk:BAABLgAECn8cAAIPAAkJJBXBEQCpAQAPAAkJJBXBEQCpAQAAAA==.Tuktirey:BAAALgAECgEJAQAAAA==.',
Tw='Twelevepeers:BAAALgAECgQJBAAAAA==.Twigs:BAAALgAECgkJCgAAAA==.',
['Tì']='Tìõ:BAABLgAECn8qAAIBAAgJdBTLGAAJAgABAAgJdBTLGAAJAgABLgAECgkJIQAcAC4SAA==.',
['Tô']='Tôms:BAAALgAECggJEwAAAA==.',
['Tö']='Töms:BAAALgADCgYJCAAAAA==.',
Ud='Udderlegend:BAAALgADCgcJEAAAAA==.',
Ug='Ughtismo:BAAALgAECgEJAQAAAA==.',
Ul='Ulrikan:BAAALgAECgEJAQAAAA==.Ultarok:BAAALgAECgkJEQAAAA==.',
Un='Undeadban:BAAALgAECgEJAQAAAA==.Unfiltered:BAAALgAECgQJDgAAAA==.Unwanted:BAAALgAECgYJEQAAAA==.',
Up='Upstream:BAAALgADCgYJCwAAAA==.',
Us='Usagiknight:BAAALgADCgEJAQAAAA==.Ushii:BAAALgAECgYJEAAAAA==.',
Va='Vaelindar:BAAALgADCgUJBgAAAA==.Vakarians:BAAALgAECgMJAwAAAA==.Vakkd:BAAALgADCgIJAgAAAA==.Valei:BAAALgAECgQJBAAAAA==.Valenai:BAAALgAECgEJAQAAAA==.Valor:BAACLgAFFH8UAAMGAAQJRCHxJwBjAQAGAAQJRCHxJwBjAQAeAAMJlBRNBwD/AAAuAAQKfyIAAwYACQl0H6YgAL8CAAYACAlIIqYgAL8CAB4ABgkoHHkGAL8BAAAA.Vampirevic:BAAALgAECgcJBwAAAA==.Vansanssra:BAAALgADCgEJAQAAAA==.Varcoh:BAABLgAECn8pAAMQAAkJuQ1THQCRAQAQAAkJuQ1THQCRAQAhAAIJUgQWWgBQAAAAAA==.',
Ve='Velixar:BAAALgAECgEJAQAAAA==.Veloxen:BAAALgAFFAEJAQAAAA==.Venthyr:BAAALgADCgIJAgABLgAFFAQJFAAGAEQhAA==.Verikost:BAAALgADCgEJAQAAAA==.',
Vi='Victanney:BAAALgAECgkJBwABLgAECgkJLwALABQfAA==.Vinda:BAACLgAFFH8IAAIhAAMJjQcGGQDXAAAhAAMJjQcGGQDXAAAuAAQKfzkAAiEACQkCGsEKAFkCACEACQkCGsEKAFkCAAAA.',
Vl='Vladious:BAABLgAECn8vAAQLAAkJFB9aDAC4AgALAAgJFB9aDAC4AgANAAIJvB1YSACWAAAMAAIJ+SAfHABjAAAAAA==.',
Vy='Vynd:BAAALgAECgYJEwAAAA==.Vynllandis:BAAALgADCgMJAwAAAA==.',
Wa='Walapon:BAAALgAECgQJAwAAAA==.Wallo:BAABLgAECn84AAIKAAkJEhSJFwDlAQAKAAkJEhSJFwDlAQAAAA==.Warglaivez:BAAALgAECgYJEgAAAA==.Washedbolt:BAAALgAFFAEJAQAAAA==.Washedpyro:BAAALgAECgcJCQAAAA==.Wata:BAAALgAECgMJAwAAAA==.Watchscotch:BAAALgADCgkJFQABLgAECggJIgAIAJgeAA==.Wayfairkid:BAAALgAECgYJCwAAAA==.',
We='Werken:BAAALgAECgYJCgAAAA==.',
Wh='Whyetee:BAACLgAFFH8FAAITAAIJQA9mIgCWAAATAAIJQA9mIgCWAAAuAAQKfy0AAxMACAlNI78LANoCABMACAkLIr8LANoCACcAAglKIm4UALYAAAAA.',
Wi='Willywonkas:BAAALgADCgkJGgAAAA==.Windowlicker:BAAALgADCgEJAQAAAA==.Wineo:BAABLgAECn8lAAIVAAkJwh6tDQDAAgAVAAkJwh6tDQDAAgAAAA==.Wizzwee:BAAALgAECgIJAgABLgAECgkJHgAPAIIcAA==.',
Wo='Woa:BAAALgAECgEJAQAAAA==.Wonder:BAAALgAECgIJAwAAAA==.Woofwoofwoof:BAABLgAECn8gAAIRAAkJLgyPUwCgAQARAAkJLgyPUwCgAQAAAA==.Worn:BAAALgADCgQJBAAAAA==.Worthlesshoe:BAAALgADCgIJBAABLgADCgUJBQAEAAAAAA==.',
Wr='Wraithwok:BAAALgADCgYJBgAAAA==.Wrld:BAAALgAECgYJCQAAAA==.',
['Wà']='Wàll:BAAALgADCgMJAwAAAA==.',
['Wå']='Wåffle:BAAALgADCgUJAwAAAA==.',
Xa='Xantodar:BAAALgAECgIJAgAAAA==.Xasther:BAABLgAECn8jAAISAAgJnCTGCwAwAwASAAgJnCTGCwAwAwAAAA==.Xav:BAAALgADCgkJDAAAAA==.',
Xe='Xenophilius:BAAALgAECgcJEAAAAA==.Xeruk:BAAALgAECgYJDAAAAA==.',
Ya='Yasha:BAAALgADCgEJAQABLgAECgUJCQAEAAAAAA==.',
Ye='Yearsfade:BAAALgADCgMJAwAAAA==.',
Yu='Yuka:BAAALgADCgUJBAAAAA==.Yulok:BAAALgAECgcJEAABLgAFFAgJGAAcADcgAA==.Yumí:BAABLgAECn8dAAMgAAgJ4RzZCQBCAgAgAAgJ4RzZCQBCAgAJAAEJywn4iQAxAAAAAA==.Yurgling:BAAALgAECgMJBAAAAA==.',
Za='Zaberra:BAAALgAECgEJAgABLgAECgkJLAAVAGUbAA==.Zanarkand:BAAALgAECggJEwAAAA==.Zarivara:BAAALgAECgEJAgAAAA==.',
Ze='Zepha:BAAALgADCgIJAQAAAA==.',
Zi='Zib:BAAALgAECgkJBgAAAA==.Zibrina:BAAALgADCgUJCAAAAA==.Zieg:BAAALgADCgIJAgABLgAFFAMJAwAEAAAAAA==.Zigzagz:BAAALgAECgYJCgAAAA==.Zina:BAAALgAECgEJAQAAAA==.Zitish:BAAALgADCgEJAQAAAA==.',
Zo='Zomby:BAAALgAECggJEAAAAA==.',
Zu='Zuko:BAAALgADCgEJAQAAAA==.',
['Ço']='Çookiemonstr:BAAALgADCgkJDwAAAA==.',
['Ëy']='Ëyë:BAAALgAFFAEJAQAAAA==.',
['Ñi']='Ñina:BAAALgAECgYJCgAAAA==.',
['ßu']='ßutterworth:BAAALgADCgEJAQAAAA==.',
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
