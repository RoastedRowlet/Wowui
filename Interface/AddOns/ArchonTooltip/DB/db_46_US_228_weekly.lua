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

local lookup = {'Hunter-Survival','DeathKnight-Unholy','Warlock-Affliction','Unknown-Unknown','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Druid-Balance','Warrior-Protection','Mage-Frost','Warrior-Fury','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','Priest-Holy','Warlock-Destruction','Rogue-Subtlety','Evoker-Devastation','Priest-Shadow','Priest-Discipline','Warlock-Demonology','Paladin-Retribution','Druid-Restoration','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Paladin-Holy','DemonHunter-Vengeance','Evoker-Augmentation','Monk-Windwalker',}
local provider = {region='US',realm='Uldaman',name='US',type='weekly',zone=46,date='2026-05-17',data={Ad='Ademar:BAABLgAECn8lAAIBAAYJkRjXHQB0AQABAAYJkRjXHQB0AQABLgAECgcJFwACAGASAA==.',
Ae='Aenora:BAAALgAECgMJAwAAAA==.',
Ag='Aggrothief:BAAALgAECgQJBAAAAA==.Agrius:BAAALgAECgYJDAAAAA==.',
Ai='Ainokeas:BAAALgAECgIJAgAAAA==.',
Ak='Akurumira:BAAALgADCgQJBgAAAA==.',
Al='Alexändros:BAAALgADCgUJCAAAAA==.Alkie:BAAALgAECgMJBgAAAA==.Allectra:BAAALgAECgQJCwAAAA==.Allupinya:BAAALgAECgUJBQAAAA==.',
Am='Amnon:BAABLgAECn8nAAIDAAgJGx/uAwATAgADAAgJGx/uAwATAgAAAA==.',
Ar='Arelliea:BAAALgADCgEJAQABLgAFFAEJAQAEAAAAAA==.',
As='Asaelis:BAAALgAECgYJDQAAAA==.Astauren:BAAALgADCgMJBAAAAA==.Astralflame:BAAALgADCgIJAgAAAA==.',
Au='Augwaddles:BAAALgAECgUJBwABLgAECggJGQAFAAMgAA==.',
Av='Avataraang:BAAALgADCgEJAQAAAA==.Avramora:BAAALgAECgUJDAABLgAFFAEJAQAEAAAAAA==.',
Ax='Axila:BAAALgAECgIJAwAAAA==.',
Az='Azdaja:BAABLgAECn8lAAMGAAkJFg75GQCjAQAGAAkJFg75GQCjAQAHAAEJ7QD8dwAPAAAAAA==.Azgardia:BAAALgAECgYJCAAAAA==.Azryiel:BAAALgAECgUJBQABLgAECgkJJQAGABYOAA==.Azulå:BAAALgAECgcJDgAAAA==.',
Ba='Bach:BAABLgAFFH8NAAIIAAMJNCIdFAAsAQAIAAMJNCIdFAAsAQAAAA==.Balloffur:BAABLgAECn8cAAIJAAkJIA6DEgCAAQAJAAkJIA6DEgCAAQAAAA==.Bamboostixx:BAABLgAECn8dAAIKAAgJlgydbABrAQAKAAgJlgydbABrAQAAAA==.',
Be='Bellgirls:BAAALgAECgMJAwAAAA==.Belnetukent:BAAALgADCgEJAQAAAA==.Berastu:BAABLgAECn8hAAILAAkJohSgGgDXAQALAAkJohSgGgDXAQAAAA==.Berastú:BAAALgAECgYJCwAAAA==.',
Bl='Blackbear:BAAALgAECgMJAwABLgADCgEJAQAEAAAAAA==.Bloodlusst:BAAALgAECgEJAQAAAA==.Bloodraina:BAAALgADCgYJBgAAAA==.',
Bo='Bonechill:BAAALgADCgYJDAAAAA==.Boogyboo:BAAALgADCgEJAQAAAA==.Booz:BAABLgAECn8eAAIMAAYJYxnrUgBLAQAMAAYJYxnrUgBLAQAAAA==.Bors:BAABLgAECn8fAAMNAAkJQxmiCQD8AgANAAkJQxmiCQD8AgAOAAUJARHRUgABAQAAAA==.',
Bu='Bubbleõseven:BAAALgADCggJDwAAAA==.Bunnystalker:BAAALgADCgYJBwAAAA==.',
Ca='Callee:BAABLgAECn8hAAINAAgJAA1+VQBZAQANAAgJAA1+VQBZAQAAAA==.Calyse:BAABLgAECn8dAAIPAAcJISGhBwAXAgAPAAcJISGhBwAXAgAAAA==.Casblind:BAACLgAFFH8bAAIMAAYJrhzaDADFAQAMAAYJrhzaDADFAQAuAAQKfx8AAgwACQkZIHsQAPoCAAwACQkZIHsQAPoCAAAA.Casima:BAAALgAECgYJEQAAAA==.',
Ch='Chandani:BAAALgAECgYJCAAAAA==.Chesterblat:BAAALgADCgIJAgAAAA==.Cheydinhal:BAABLgAECn8tAAIQAAgJWRKKGADJAQAQAAgJWRKKGADJAQAAAA==.Chicknwaffle:BAAALgAECgQJCgAAAA==.Chocó:BAAALgADCgEJAQAAAA==.Chumlee:BAABLgAECn8nAAIGAAcJ1hm8GACvAQAGAAcJ1hm8GACvAQAAAA==.',
Ci='Ciri:BAAALgAECgEJAQAAAA==.',
Co='Colleague:BAAALgAECgEJAQAAAA==.Cornmoon:BAAALgADCgQJAgAAAA==.',
Cr='Crank:BAAALgAFFAMJAwABLgAFFAgJIAARAAgiAA==.',
Da='Dalanorea:BAAALgAECgYJBgAAAA==.Dandorn:BAAALgADCgIJAgAAAA==.Darksushi:BAAALgAECgYJDgAAAA==.Daylate:BAAALgADCgUJBQAAAA==.',
Dh='Dhabyss:BAAALgADCggJCAABLgAECggJJQASAGYhAA==.',
Di='Diménsional:BAABLgAECn8dAAIGAAgJow8dIwBeAQAGAAgJow8dIwBeAQAAAA==.Dinbek:BAAALgAECgcJCgAAAA==.Dindino:BAAALgADCgkJCQAAAA==.Dindroc:BAAALgADCgcJDgAAAA==.Dingread:BAAALgAECgYJBgAAAA==.',
Dr='Dragin:BAABLgAECn8gAAITAAgJvQdtCwAmAQATAAgJvQdtCwAmAQAAAA==.Dreyla:BAAALgADCgQJCAAAAA==.Drunkmcmonk:BAAALgADCgMJBgAAAA==.',
Du='Duronimo:BAAALgAECgQJBAAAAA==.Dusksurge:BAAALgADCgIJAgAAAA==.',
['Dÿ']='Dÿmmensional:BAAALgAECgIJAwAAAA==.',
Ec='Eclipze:BAACLgAFFH8PAAMUAAQJGwm4EwAXAQAUAAQJGwm4EwAXAQAVAAIJgAJGMwBCAAAuAAQKfyMABBQACQmqGFkPACACABQACQmqGFkPACACABUAAQkoB9hbACsAABAAAQnmARyKACIAAAAA.Eclipzee:BAAALgADCgMJAwABLgAFFAQJDwAUABsJAA==.Eclipzé:BAABLgAECn8ZAAMDAAgJqRlFDwALAQAWAAYJMhHFeAAaAQADAAUJqRhFDwALAQABLgAFFAQJDwAUABsJAA==.',
Ei='Eifel:BAAALgAECgcJEgABLgAECgkJGwAXABceAA==.',
El='Elessardan:BAABLgAECn8pAAMYAAkJVx4tBwAWAwAYAAkJVx4tBwAWAwAIAAIJXhGyawBxAAAAAA==.Elothien:BAAALgAECgEJAQAAAA==.Elvaca:BAAALgAECgUJBQAAAA==.',
En='Endilli:BAAALgAECgUJDQAAAA==.',
Eq='Equinoxis:BAEALgAECgYJBgABLgAFFAYJHgAUAO0YAA==.',
Et='Eternal:BAAALgAFFAMJBAAAAA==.',
Ev='Evaki:BAAALgADCgEJAgAAAA==.',
Ez='Ezekiel:BAAALgAECgEJAQAAAA==.',
Fa='Faein:BAAALgADCgIJAgAAAA==.Fallynangel:BAABLgAECn8tAAISAAcJyhe/GQB+AQASAAcJyhe/GQB+AQAAAA==.',
Fe='Fearlock:BAAALgADCgUJCAAAAA==.Felrafram:BAAALgADCgQJAwAAAA==.Fenyx:BAABLgAECn8xAAIGAAkJvA/fFwC2AQAGAAkJvA/fFwC2AQABLgAFFAMJCQAJAJcZAA==.',
Fi='Filho:BAABLgAECn8cAAMNAAcJVhI1WgBMAQANAAcJVhI1WgBMAQAOAAIJqALDgABEAAAAAA==.',
Fr='Friedtips:BAAALgADCgQJBgABLgAFFAIJBgAZABQeAA==.Frostwaffle:BAAALgADCgYJBgABLgAECgQJCgAEAAAAAA==.Frumpy:BAAALgAECgEJAQABLgAECgcJCgAEAAAAAA==.',
Ga='Gabe:BAAALgAECgUJBgAAAA==.Galvek:BAACLgAFFH8OAAQBAAQJahdHCQBXAQABAAQJahdHCQBXAQANAAIJawtoVQCRAAAOAAEJnwNuLABBAAAuAAQKfycABAEACQm7HR8KAEwCAAEACAmUHh8KAEwCAA0ABgkIHbFBAKkBAA4ABgmhEGM9AGgBAAAA.Garjzlaa:BAAALgAECgYJBwAAAA==.Garugamesh:BAAALgADCgcJCQAAAA==.Gas:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.',
Gi='Gigglebytes:BAAALgAECgIJAQAAAA==.',
Gn='Gnowen:BAAALgADCgkJCQABLgAECgQJCAAEAAAAAA==.',
Go='Gojira:BAAALgADCgIJAgAAAA==.',
Gr='Greyswandir:BAAALgAECgQJDQAAAA==.Gryssli:BAAALgADCgIJAgAAAA==.',
Gw='Gwarr:BAAALgAECgYJCgAAAA==.',
Ha='Harandufu:BAAALgAECgEJAQAAAA==.Harvie:BAAALgADCgYJBgABLgAECgQJDQAEAAAAAA==.Hatani:BAAALgAECgEJAQABLgAECgYJDAAEAAAAAA==.Haylee:BAAALgADCgkJEwAAAA==.',
He='Hemofluffin:BAAALgAECgIJAgABLgAFFAQJDgACAKEVAA==.',
Hu='Husky:BAAALgAECggJEgAAAA==.',
Ic='Icyfurball:BAAALgAECgIJAgABLgAECgYJEQAEAAAAAA==.',
Ik='Ikillyounows:BAAALgAECgQJBAAAAA==.',
Il='Ilovesanta:BAAALgAECgYJCwAAAA==.',
In='Indigobleue:BAABLgAECn8qAAQQAAcJZR/BEgAIAgAQAAcJZR/BEgAIAgAVAAUJQBjiJgBKAQAUAAEJIAhqaAAwAAAAAA==.Infidel:BAAALgAECgIJAwABLgADCgEJAQAEAAAAAA==.',
Ja='Japplen:BAAALgAECgQJCAAAAA==.',
Je='Jeffery:BAAALgADCgMJAwAAAA==.Jeraziah:BAAALgADCgYJBwAAAA==.',
Ji='Jinkalou:BAAALgAECgQJBAABLgAECggJGgAFAEQWAA==.Jinn:BAAALgADCgUJBQAAAA==.Jiñ:BAAALgAECgQJCAAAAA==.',
Jo='Jorenson:BAABLgAECn8pAAICAAgJYxKzWwB8AQACAAgJYxKzWwB8AQAAAA==.',
Ka='Kaether:BAABLgAECn8VAAMQAAYJOQmHNAD2AAAQAAYJOQmHNAD2AAAUAAIJmADkaQAkAAAAAA==.Kalzdemar:BAABLgAECn8XAAMCAAcJYBJIawBVAQACAAcJVRBIawBVAQAaAAQJtRh3DwCmAAAAAA==.Kasitus:BAABLgAECn8eAAICAAgJIyTtGQBzAgACAAgJIyTtGQBzAgAAAA==.',
Ke='Keldanor:BAAALgAECgEJAQAAAA==.',
Kh='Khei:BAAALgADCgIJAgAAAA==.',
Ki='Kilometraje:BAABLgAECn8YAAMbAAgJOxJOFACEAQAbAAgJJxFOFACEAQACAAYJTwwC3QCIAAAAAA==.Kira:BAAALgAECgIJAgAAAA==.Kissey:BAAALgAECgQJBQAAAA==.Kivi:BAAALgADCgEJAQAAAA==.',
Ko='Korneliuz:BAABLgAECn8UAAMFAAYJdxzsMQCeAQAFAAYJdxzsMQCeAQAcAAEJvwxSjwAoAAABLgAFFAIJBQALAIYfAA==.',
Kr='Kraink:BAAALgADCgEJAQAAAA==.Krayvin:BAAALgADCgIJAgAAAA==.',
Ku='Kungmoofu:BAAALgADCgIJAgABLgAECgcJCgAEAAAAAA==.',
Ky='Kyrak:BAAALgAECgYJDQAAAA==.',
La='Labiamajorah:BAAALgADCgIJAgAAAA==.Ladiebee:BAAALgADCggJCAAAAA==.Lainey:BAABLgAECn83AAINAAkJmh2MCwC8AgANAAkJmh2MCwC8AgAAAA==.Landocamando:BAABLgAECn8ZAAILAAYJGxjLLwBPAQALAAYJGxjLLwBPAQAAAA==.Larrusbain:BAABLgAECn8WAAIdAAYJBhdhKgB7AQAdAAYJBhdhKgB7AQAAAA==.',
Le='Leafin:BAAALgADCgUJCQABLgAECgcJLQASAMoXAA==.Lerya:BAABLgAECn8hAAITAAkJ7BIaBgC0AQATAAkJ7BIaBgC0AQAAAA==.Levictus:BAAALgAECgEJAQAAAA==.Lexnn:BAABLgAECn8nAAIMAAgJwxICQQCGAQAMAAgJwxICQQCGAQAAAA==.Lexonidas:BAAALgADCgEJAgAAAA==.',
Li='Liantelva:BAAALgAECgcJEQAAAA==.Lifepriest:BAAALgADCggJDAAAAA==.Ligetnoone:BAAALgAECgYJEQAAAA==.Lighte:BAABLgAECn8xAAIKAAkJCRtYIQBjAgAKAAkJCRtYIQBjAgAAAA==.Lilyith:BAAALgAECgIJBQAAAA==.Lips:BAAALgAECgMJAwAAAA==.',
Lo='Logicx:BAABLgAECn8mAAIIAAcJSxTUIgBlAQAIAAcJSxTUIgBlAQAAAA==.Lorvoldenord:BAAALgADCgIJAgAAAA==.',
Lu='Lunarìa:BAAALgADCggJCwAAAA==.',
['Lê']='Lêssa:BAAALgAECgQJBQAAAA==.',
Ma='Magici:BAABLgAECn8hAAIKAAcJ/A+9fwBDAQAKAAcJ/A+9fwBDAQAAAA==.Magnyesis:BAAALgADCgEJAQAAAA==.Mahavailo:BAAALgAECgUJBQAAAA==.Malina:BAAALgAECgEJAQAAAA==.Manimal:BAAALgAECgEJAwAAAA==.Mavren:BAAALgAECgQJCgAAAA==.',
Me='Mefisto:BAAALgAECgQJBQABLgAECgQJCAAEAAAAAA==.Mellesaun:BAABLgAECn8eAAQeAAcJiAmmEQDqAAAeAAcJYAmmEQDqAAAMAAYJIwaOlgCrAAAZAAQJkgVqWwBzAAAAAA==.Merie:BAAALgADCgYJBwAAAA==.Mewtwo:BAABLgAFFH8IAAIWAAMJCQu0VwDTAAAWAAMJCQu0VwDTAAABLgAFFAcJFgAfABwXAA==.',
Mi='Miikeey:BAAALgADCgIJAgAAAA==.Mirei:BAAALgADCggJCQAAAA==.Mithrios:BAAALgADCgcJDAAAAA==.',
Mo='Moonsaw:BAABLgAECn8XAAIgAAYJXyV9DwAQAgAgAAYJXyV9DwAQAgAAAA==.Mordella:BAAALgADCgIJAwAAAA==.Moriartus:BAAALgADCgEJAQAAAA==.Mosthated:BAAALgADCgIJAgAAAA==.',
My='Myrling:BAABLgAECn8aAAMYAAYJ3gkpXwDgAAAYAAYJ3gkpXwDgAAAIAAEJSwKUfQAcAAAAAA==.Mythrial:BAAALgAECgYJCgAAAA==.',
Ne='Nenni:BAAALgADCgYJBgAAAA==.Neph:BAAALgADCgkJCQAAAA==.Newt:BAABLgAECn8pAAQMAAkJ9RhiHwAeAgAMAAgJoxZiHwAeAgAZAAcJlRakIAC4AQAeAAEJrwIIKwAiAAAAAA==.',
Ni='Nimbus:BAACLgAFFH8UAAIKAAQJlBscJQByAQAKAAQJlBscJQByAQAuAAQKfxsAAgoACQl+IGINAOICAAoACQl+IGINAOICAAEuAAUUCAkWAB8ATBYA.Nishikki:BAECLgAFFH8eAAIUAAYJ7RgZBQC3AQAUAAYJ7RgZBQC3AQAuAAQKfzwAAhQACQmYI6ABAEcDABQACQmYI6ABAEcDAAAA.',
No='Nocanno:BAAALgADCgYJBgAAAA==.',
Ny='Nydie:BAABLgAECn8zAAIXAAkJBxqHJAA1AgAXAAkJBxqHJAA1AgAAAA==.Nymuellyn:BAABLgAECn8lAAISAAgJZiH1CQBBAgASAAgJZiH1CQBBAgAAAA==.',
Nz='Nzonah:BAAALgADCgEJAQAAAA==.',
Pa='Palmanance:BAAALgAECgkJCgAAAA==.',
Pe='Penumbral:BAAALgAECgYJDwAAAA==.',
Ph='Phalst:BAAALgAECgEJAgAAAA==.Phibalan:BAAALgAECgEJAQAAAA==.',
Pi='Pixel:BAAALgAECgIJAwAAAA==.Pixil:BAAALgADCgEJAQAAAA==.Pixishot:BAABLgAECn8WAAINAAYJPAxLcAAXAQANAAYJPAxLcAAXAQAAAA==.',
Pr='Pradigy:BAABLgAECn8YAAICAAYJxQ+ikAALAQACAAYJxQ+ikAALAQAAAA==.',
Pu='Pubba:BAAALgAECgcJCgAAAA==.Pubbazug:BAAALgAECgUJCwABLgAECgcJCgAEAAAAAA==.Pubismaximus:BAAALgAECgEJAQABLgAECgcJCgAEAAAAAA==.',
Pw='Pwincess:BAAALgAECgQJBAAAAA==.',
Ra='Raelyndria:BAABLgAECn8VAAMUAAgJSBZHGwCkAQAUAAgJSBZHGwCkAQAVAAUJdhkjKABVAQAAAA==.Raengurth:BAAALgAECgUJBQAAAA==.Raenraug:BAAALgADCgMJAwAAAA==.Rakkali:BAAALgAFFAEJAQAAAA==.Rancavus:BAAALgADCgMJAwAAAA==.Rastakehn:BAAALgADCgYJBgAAAA==.Ratraxx:BAAALgADCgYJBgABLgAECggJGgAFAEQWAA==.Razaller:BAABLgAECn8UAAMfAAkJiA6CKgBrAQAfAAkJiA6CKgBrAQATAAEJFgE+RgAbAAAAAA==.',
Rc='Rctraxx:BAAALgAECgYJBwABLgAECggJGgAFAEQWAA==.',
Re='Redrogue:BAABLgAECn8mAAIRAAcJzQoVEAD9AAARAAcJzQoVEAD9AAAAAA==.Revela:BAAALgADCgcJDQAAAA==.',
Ri='Riftan:BAACLgAFFH8OAAICAAQJoRXrPABCAQACAAQJoRXrPABCAQAuAAQKfzIAAgIACAnWIfIaANwCAAIACAnWIfIaANwCAAAA.Rightousnes:BAAALgADCgcJCQAAAA==.Riviee:BAAALgAECgUJEQAAAA==.',
Ro='Rogun:BAABLgAECn8WAAIOAAcJrQt6EQAEAQAOAAcJrQt6EQAEAQAAAA==.Roredge:BAAALgAECgEJAQABLgAECggJGgAFAEQWAA==.Rosealie:BAAALgADCgMJAwAAAA==.',
Ry='Rycbar:BAAALgADCgkJCQAAAA==.Rynthanuu:BAAALgADCgEJAQAAAA==.',
Sa='Sarann:BAAALgAECgMJAwAAAA==.Satele:BAAALgAECgQJBwAAAA==.',
Sc='Scarypoppins:BAABLgAECn8fAAIbAAgJDiGiBgB6AgAbAAgJDiGiBgB6AgAAAA==.',
Se='Seloki:BAAALgADCgQJBAAAAA==.Senia:BAAALgAECgcJCQAAAA==.Seniortank:BAAALgADCgEJAQAAAA==.Serracha:BAAALgAECgYJDAABLgAECgkJJQAGABYOAA==.Seònaid:BAAALgAFFAIJBAAAAA==.',
Sh='Shadowkaizen:BAAALgADCgEJAQAAAA==.Shambullance:BAAALgADCgUJBQABLgAECgYJDQAEAAAAAA==.Shammywaddle:BAABLgAECn8ZAAMFAAgJAyDzIQATAgAFAAYJ4CHzIQATAgAcAAgJnRDLJQBzAQAAAA==.Shamtraxx:BAABLgAECn8aAAMFAAgJRBb5LwDIAQAFAAcJPBb5LwDIAQAcAAcJTw1zRgAvAQAAAA==.Sheraania:BAAALgADCgcJCAAAAA==.',
Si='Sinistress:BAAALgADCgcJCwAAAA==.',
Sk='Skorpius:BAAALgAECgQJDQAAAA==.Skumi:BAAALgAECgUJCwAAAA==.',
Sl='Slaytanic:BAABLgAECn8mAAIXAAcJGhzKQgDBAQAXAAcJGhzKQgDBAQAAAA==.Slymick:BAAALgAECggJEgAAAA==.',
So='Solora:BAABLgAECn8mAAIcAAcJZgZVRQDUAAAcAAcJZgZVRQDUAAAAAA==.Soluna:BAABLgAECn8nAAIXAAgJMBaBRwC0AQAXAAgJMBaBRwC0AQAAAA==.',
St='Stiflerd:BAAALgADCgEJAQAAAA==.Strawry:BAAALgAECgQJBgAAAA==.Stuffedbear:BAABLgAECn8UAAIIAAYJBQU3SACiAAAIAAYJBQU3SACiAAAAAA==.',
Su='Subiegrl:BAAALgAECgQJBAAAAA==.Sunjiwung:BAAALgAECgMJAwAAAA==.Supadin:BAAALgAECgEJAQAAAA==.',
Sw='Swll:BAAALgAECgYJDQAAAA==.',
Sy='Sylanann:BAAALgADCgMJAwAAAA==.Syrüs:BAACLgAFFH8GAAIZAAIJFB7FEAC3AAAZAAIJFB7FEAC3AAAuAAQKfyIAAhkACAmkHwITAD8CABkACAmkHwITAD8CAAAA.',
['Sã']='Sãrik:BAAALgAECgQJCAAAAA==.',
['Sí']='Sílver:BAABLgAECn8kAAIcAAgJphAyKgBXAQAcAAgJphAyKgBXAQAAAA==.',
Ta='Taebeck:BAAALgADCgQJBAAAAA==.Tasty:BAAALgADCgYJBgABLgAFFAQJDQAFACEYAA==.',
Th='Thalyra:BAAALgADCgYJBgAAAA==.Thirstrap:BAABLgAECn8eAAIZAAgJ6wy+GgBOAQAZAAgJ6wy+GgBOAQAAAA==.Thorge:BAABLgAECn8WAAIBAAYJMBZ8IQBTAQABAAYJMBZ8IQBTAQAAAA==.Thyrus:BAAALgADCgQJBAAAAA==.',
Ti='Tips:BAAALgADCgQJBAAAAA==.',
To='Tokesmasmoke:BAAALgAECgMJAwAAAA==.Toragos:BAAALgADCgQJBAAAAA==.',
Tr='Träshley:BAAALgAECgYJEwAAAA==.',
Uk='Uknak:BAAALgAECgQJBwAAAA==.',
Ul='Ulanui:BAAALgADCgMJAwAAAA==.',
Ur='Urma:BAAALgAECgQJBQAAAA==.',
Va='Vaediirn:BAAALgADCgQJBAAAAA==.Vallcore:BAAALgADCgUJBgAAAA==.',
Ve='Vennt:BAABLgAECn8aAAIOAAgJJRFoJwDuAQAOAAgJJRFoJwDuAQAAAA==.Ventt:BAACLgAFFH8YAAIcAAYJFhHeCwBtAQAcAAYJFhHeCwBtAQAuAAQKfzEAAhwACQkkI7MDAAIDABwACQkkI7MDAAIDAAAA.',
Vo='Volstaag:BAAALgAECgEJBAAAAA==.Voluus:BAABLgAECn8VAAIcAAcJrAzENgAUAQAcAAcJrAzENgAUAQAAAA==.',
Vr='Vrorag:BAAALgAECgcJEwAAAA==.',
Wa='Walfar:BAAALgAECgQJCAAAAA==.Walterlight:BAAALgADCgcJCwAAAA==.Warbuckss:BAAALgAECgQJDQABLgAECgYJGAACAMUPAA==.Wayme:BAABLgAECn8UAAIRAAUJnw7BFgC8AAARAAUJnw7BFgC8AAAAAA==.',
We='Wendorf:BAAALgADCgkJCQAAAA==.',
Wh='Whispyr:BAAALgADCgcJCAAAAA==.Whiteclaw:BAAALgAECgMJAwAAAA==.',
Wo='Wooster:BAAALgAECgEJAQAAAA==.',
Xa='Xahle:BAABLgAECn8bAAICAAgJ4BGhXwByAQACAAgJ4BGhXwByAQAAAA==.Xanado:BAAALgADCgEJAQAAAA==.',
Xs='Xsanguinate:BAAALgAECgQJBAAAAA==.',
Ya='Yarikh:BAAALgADCgEJAQAAAA==.',
Za='Zadkiel:BAAALgAECgQJBgAAAA==.',
Ze='Zeparu:BAABLgAECn8XAAICAAgJYxKaTACkAQACAAgJYxKaTACkAQAAAA==.Zero:BAAALgAECgUJBwABLgAECgkJHwAHAEkWAA==.',
Zi='Zitillidan:BAAALgAECgcJBwABLgAECgcJFwACAGASAA==.',
Zo='Zogz:BAAALgAECgYJEwAAAA==.',
['Âi']='Âid:BAAALgADCgkJCQAAAA==.',
['Ëi']='Ëifel:BAABLgAECn8bAAIXAAkJFx4ZIQCmAgAXAAkJFx4ZIQCmAgAAAA==.',
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
