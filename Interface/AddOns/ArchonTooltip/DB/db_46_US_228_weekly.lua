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

local lookup = {'Hunter-Survival','DeathKnight-Blood','Warlock-Affliction','Unknown-Unknown','Priest-Holy','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Warrior-Protection','Mage-Frost','Warrior-Fury','DemonHunter-Devourer','Paladin-Protection','Warlock-Destruction','Rogue-Subtlety','Evoker-Devastation','Priest-Shadow','Priest-Discipline','Warlock-Demonology','Paladin-Retribution','Druid-Restoration','DemonHunter-Havoc','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Elemental','Paladin-Holy','Evoker-Augmentation','Druid-Guardian','DemonHunter-Vengeance','Monk-Windwalker',}
local provider = {region='US',realm='Uldaman',name='US',type='weekly',zone=46,date='2026-05-31',data={Ad='Ademar:BAABLgAECn8nAAIBAAcJ3hX0HQCfAQABAAcJ3hX0HQCfAQAAAA==.',
Ae='Aenora:BAAALgAECgMJAwAAAA==.',
Ag='Aggrothief:BAAALgAECgUJBQAAAA==.Agrius:BAAALgAECgYJDAAAAA==.',
Ai='Ainokeas:BAAALgAECgIJAgAAAA==.',
Ak='Akurumira:BAAALgADCgkJCwAAAA==.',
Al='Alexändros:BAAALgADCgUJCAAAAA==.Alkie:BAAALgAECgQJBwAAAA==.Allectra:BAAALgAECgYJDwAAAA==.Allupinya:BAAALgAECgUJBwABLgAECgkJIwACAN4gAA==.',
Am='Amnon:BAABLgAECn84AAIDAAkJQSAsAgCgAgADAAkJQSAsAgCgAgAAAA==.',
Ar='Arelliea:BAAALgADCgEJAQABLgAFFAEJAQAEAAAAAA==.Arlessa:BAAALgAECgQJBAABLgAECgkJNQAFAC8hAA==.',
As='Asaelis:BAAALgAECgYJDQAAAA==.Astauren:BAAALgADCgMJBAAAAA==.Astralflame:BAAALgADCgYJCAAAAA==.',
Au='Augwaddles:BAAALgAECgUJBwABLgAECggJGQAGAAMgAA==.',
Av='Avataraang:BAAALgADCgEJAQAAAA==.Avramora:BAAALgAECgUJDAABLgAFFAEJAQAEAAAAAA==.',
Ax='Axila:BAAALgAECgIJAwAAAA==.',
Az='Azdaja:BAACLgAFFH8IAAIHAAIJDw9JPwCHAAAHAAIJDw9JPwCHAAAuAAQKfykAAwcACQl0DhgfAJ0BAAcACQl0DhgfAJ0BAAgAAQntAPx3AA8AAAAA.Azgardia:BAAALgAECgYJCAAAAA==.Azryiel:BAAALgAECgcJEAABLgAFFAIJCAAHAA8PAA==.Azulå:BAABLgAECn8hAAMJAAkJ6BPDKAAnAgAJAAkJ6BPDKAAnAgAKAAEJrgO6PwAeAAAAAA==.',
Ba='Bach:BAABLgAFFH8XAAILAAUJNyNsDQCOAQALAAUJNyNsDQCOAQAAAA==.Balloffur:BAABLgAECn8cAAIMAAkJIA6jFwBuAQAMAAkJIA6jFwBuAQAAAA==.Bamboostixx:BAABLgAECn8pAAINAAkJnhHnRAD3AQANAAkJnhHnRAD3AQAAAA==.',
Be='Bellgirls:BAAALgAECgMJAwAAAA==.Belnetukent:BAAALgADCgEJAQAAAA==.Berastu:BAACLgAFFH8FAAIOAAIJMQhEPgCDAAAOAAIJMQhEPgCDAAAuAAQKfyEAAg4ACQmjFHgiAM0BAA4ACQmjFHgiAM0BAAAA.Berastú:BAAALgAECgYJDQAAAA==.',
Bl='Blackbear:BAAALgAECgMJAwABLgADCgEJAQAEAAAAAA==.Bleufromage:BAAALgADCggJCwAAAA==.Bloodlusst:BAAALgAECgMJBAAAAA==.Bloodraina:BAAALgADCgYJBgAAAA==.',
Bo='Bonechill:BAAALgADCgYJDAAAAA==.Boogyboo:BAAALgADCgEJAQAAAA==.Booz:BAABLgAECn8sAAIPAAgJnxtQKAAWAgAPAAgJnxtQKAAWAgAAAA==.Bors:BAABLgAECn8fAAMJAAkJQxmiCQD8AgAJAAkJQxmiCQD8AgAKAAUJARHRUgABAQAAAA==.Botch:BAAALgAECgYJBgAAAA==.Bowdacious:BAAALgAECgEJAwABLgAECgkJIwACAN4gAA==.',
Bu='Bubbleõseven:BAAALgADCggJDwAAAA==.Bugabooed:BAAALgADCgkJEAAAAA==.Bunnystalker:BAAALgADCgYJBwAAAA==.',
Ca='Callee:BAABLgAECn8qAAIJAAgJXg1hWgB/AQAJAAgJXg1hWgB/AQAAAA==.Calyse:BAABLgAECn8dAAIQAAcJISF8CgALAgAQAAcJISF8CgALAgAAAA==.Casblind:BAACLgAFFH8jAAIPAAgJQRr9BwBOAgAPAAgJQRr9BwBOAgAuAAQKfx8AAg8ACQkZIHsQAPoCAA8ACQkZIHsQAPoCAAAA.Casima:BAAALgAECggJEwAAAA==.',
Ch='Chandani:BAAALgAECgYJCAAAAA==.Chesterblat:BAAALgADCgIJAgAAAA==.Cheydinhal:BAABLgAECn8+AAIFAAgJzBVFFwACAgAFAAgJzBVFFwACAgAAAA==.Cheydinhil:BAAALgADCgYJBgAAAA==.Chicknwaffle:BAAALgAECgQJCgAAAA==.Chocó:BAAALgADCgEJAQAAAA==.Chumlee:BAABLgAECn8sAAIHAAgJQRlaFgDoAQAHAAgJQRlaFgDoAQAAAA==.Chunks:BAAALgAECgIJAgAAAA==.',
Ci='Ciri:BAAALgAECgEJAQAAAA==.',
Co='Colleague:BAAALgAECgYJCwAAAA==.Cornmoon:BAAALgADCgUJAwAAAA==.',
Cr='Crank:BAAALgAFFAMJAwABLgAFFAgJIAARAAkiAA==.',
Da='Dalanorea:BAAALgAECgYJBgAAAA==.Dandorn:BAAALgADCgIJAgAAAA==.Darksushi:BAAALgAECgYJEAAAAA==.Daylate:BAAALgADCgUJBQAAAA==.',
Dh='Dhabyss:BAAALgADCggJCAABLgAECgkJNgASAD0kAA==.',
Di='Diménsional:BAABLgAECn8dAAIHAAgJpQ/pKQBVAQAHAAgJpQ/pKQBVAQAAAA==.Dinbek:BAAALgAECgcJEAAAAA==.Dindino:BAAALgADCgkJEAAAAA==.Dindroc:BAAALgAECgQJBAAAAA==.Dingread:BAAALgAECgYJBgAAAA==.',
Dr='Dragin:BAABLgAECn8pAAITAAgJqAjNDAAxAQATAAgJqAjNDAAxAQAAAA==.Dreyla:BAAALgADCgQJCAAAAA==.Drunkmcmonk:BAAALgADCgMJBgAAAA==.',
Du='Duronimo:BAAALgAECgUJBgAAAA==.Dusksurge:BAAALgADCgIJAgAAAA==.',
['Dÿ']='Dÿmmensional:BAAALgAFFAEJAQAAAA==.',
Ec='Eclipze:BAACLgAFFH8TAAMUAAQJ4QsFGQAIAQAUAAQJ4QsFGQAIAQAVAAIJgAIfPwBBAAAuAAQKfyMABBQACQmqGIMVAAUCABQACQmqGIMVAAUCABUAAQkoB9hbACsAAAUAAQnmARyKACIAAAAA.Eclipzee:BAAALgADCgMJAwABLgAFFAQJEwAUAOELAA==.Eclipzé:BAABLgAECn8cAAMDAAkJNxmHDwBHAQADAAYJPBiHDwBHAQAWAAYJMhGajgAVAQABLgAFFAQJEwAUAOELAA==.',
Ei='Eifel:BAAALgAECgcJEgABLgAECgkJGwAXABceAA==.',
El='Elessardan:BAABLgAECn8tAAMYAAkJmh5kCAAkAwAYAAkJmh5kCAAkAwALAAIJXhGyawBxAAAAAA==.Elothien:BAAALgAECgEJAwABLgAECgkJLQAYAJoeAA==.Elvaca:BAAALgAECgUJBQAAAA==.',
En='Endilli:BAAALgAECgYJEwAAAA==.',
Eq='Equinoxis:BAEALgAECgYJCwABLgAFFAcJJAAUACscAA==.',
Et='Eternal:BAABLgAFFH8GAAIXAAQJXg30QQATAQAXAAQJXg30QQATAQAAAA==.',
Ev='Evaki:BAAALgADCgEJAgAAAA==.',
Ez='Ezekiel:BAAALgAECgEJAQAAAA==.',
Fa='Faein:BAAALgADCgIJAgAAAA==.Fallynangel:BAABLgAECn89AAISAAgJJxeiGAC9AQASAAgJJxeiGAC9AQAAAA==.',
Fe='Fealeen:BAAALgAECgEJAQAAAA==.Fearlock:BAAALgADCgUJCAAAAA==.Felrafram:BAAALgADCgQJAwAAAA==.Fenyx:BAABLgAECn9DAAIHAAkJdRX5EQAWAgAHAAkJdRX5EQAWAgAAAA==.',
Fi='Fightnyte:BAAALgAECgUJBQABLgAECgkJIgAWALcXAQ==.Filho:BAABLgAECn8dAAMJAAcJ6BKOcABKAQAJAAcJ6BKOcABKAQAKAAIJqALDgABEAAAAAA==.',
Fr='Friedtips:BAAALgADCgQJBgABLgAFFAQJCwAZAL4VAA==.Frostwaffle:BAAALgADCgYJBgABLgAECgQJCgAEAAAAAA==.Frumpy:BAAALgAECgEJAQABLgAECgcJDwAEAAAAAA==.',
Ga='Gabe:BAAALgAECgUJCwAAAA==.Galvek:BAACLgAFFH8QAAQBAAUJahdKDwBDAQABAAUJahdKDwBDAQAJAAIJawtjcwCIAAAKAAEJnwNuLABBAAAuAAQKfycABAEACQm+HW4OADYCAAEACAmUHm4OADYCAAkABgkOHbFBAKkBAAoABgmhEGM9AGgBAAAA.Garjzlaa:BAAALgAECgYJBwAAAA==.Garugamesh:BAAALgADCgcJDgAAAA==.Gas:BAAALgAECgEJAQABLgAFFAMJAwAEAAAAAA==.',
Gi='Gigglebytes:BAAALgAECgIJAQAAAA==.',
Gn='Gnowen:BAAALgADCgkJEgABLgAECgYJEQAEAAAAAA==.',
Go='Gojira:BAAALgADCgIJAgAAAA==.',
Gr='Greyswandir:BAABLgAECn8ZAAIJAAYJDxBZfQAuAQAJAAYJDxBZfQAuAQAAAA==.Gryssli:BAAALgADCgIJAgAAAA==.',
Gu='Gulatz:BAAALgADCgcJCAAAAA==.',
Gw='Gwarr:BAAALgAECgYJDAAAAA==.',
Ha='Harandufu:BAAALgAECgQJBQAAAA==.Hardwön:BAAALgAECgMJAwAAAA==.Harvie:BAAALgADCgYJBgABLgAECgYJGQAJAA8QAA==.Hatani:BAAALgAECgEJAQABLgAECgYJDAAEAAAAAA==.Haylee:BAAALgADCgkJEwAAAA==.',
He='Healingfoxy:BAAALgAECgQJBAAAAA==.Hemofluffin:BAAALgAECgIJAgABLgAFFAUJEwAaACAXAA==.',
Hu='Husky:BAAALgAECggJEgAAAA==.',
Ic='Icyfurball:BAAALgAECgIJAgABLgAECggJGgAMAJgmAA==.',
Ik='Ikillyounows:BAAALgAECgQJBAAAAA==.',
Il='Ilovesanta:BAAALgAECgYJDQAAAA==.',
In='Indigobleue:BAABLgAECn86AAQFAAgJ5B3zEgAxAgAFAAgJ5B3zEgAxAgAVAAcJ6hhsGADwAQAUAAEJIAipigAVAAAAAA==.Infidel:BAAALgAECgUJCAABLgADCgEJAQAEAAAAAA==.',
Ja='Jalincia:BAAALgAECgUJCAAAAA==.Japplen:BAAALgAECgQJCAAAAA==.',
Je='Jeffery:BAAALgADCgQJBwAAAA==.Jeraziah:BAAALgADCgYJDQAAAA==.',
Ji='Jinkalou:BAAALgAECgQJBAABLgAECggJGgAGAEQWAA==.Jinn:BAAALgADCgUJBQAAAA==.Jinsun:BAAALgAECgUJCAAAAA==.Jiñ:BAAALgAECgQJCAAAAA==.',
Jo='Jorenson:BAABLgAECn8sAAIaAAkJ1BF5TgDGAQAaAAkJ1BF5TgDGAQAAAA==.',
Ju='Justbeatit:BAAALgADCgQJBAAAAA==.',
Ka='Kaether:BAABLgAECn8ZAAMFAAgJYAeQNAAdAQAFAAgJYAeQNAAdAQAUAAIJmADkaQAkAAAAAA==.Kalzdemar:BAABLgAECn8ZAAMaAAcJaRJCgQBOAQAaAAcJVRBCgQBOAQAbAAQJxxhdHwCiAAABLgAECgcJJwABAN4VAA==.Kasitus:BAABLgAECn8eAAIaAAgJJSTtIwBjAgAaAAgJJSTtIwBjAgAAAA==.',
Ke='Keldanor:BAAALgAECgEJAQAAAA==.',
Kh='Khei:BAAALgADCgIJAgAAAA==.',
Ki='Kickthebaby:BAAALgADCgYJBgAAAA==.Kilometraje:BAABLgAECn8YAAMCAAgJOxI6GgBzAQACAAgJJxE6GgBzAQAaAAYJTwyFBgGFAAAAAA==.Kira:BAAALgAECgIJAgABLgAFFAMJAwAEAAAAAA==.Kissey:BAAALgAECgYJCQAAAA==.Kivi:BAAALgADCgEJAQAAAA==.',
Ko='Korneliuz:BAACLgAFFH8FAAIGAAIJRhgAUQCVAAAGAAIJRhgAUQCVAAAuAAQKfxkAAwYABgl3HIs+AJoBAAYABgl3HIs+AJoBABwABAmWF95TANAAAAAA.',
Kr='Kraink:BAAALgADCgEJAQAAAA==.Krayvin:BAAALgADCgIJAgAAAA==.Kringlë:BAAALgAECgYJBgAAAA==.',
Ku='Kungmoofu:BAAALgADCgIJAgABLgAECgcJDwAEAAAAAA==.',
Ky='Kyrak:BAAALgAECgYJDwAAAA==.',
La='Labiamajorah:BAAALgADCgIJAgAAAA==.Ladiebee:BAAALgADCggJCAAAAA==.Lainey:BAACLgAFFH8HAAIJAAMJvhzARAD+AAAJAAMJvhzARAD+AAAuAAQKfz0AAgkACQlQIJENANMCAAkACQlQIJENANMCAAAA.Landocamando:BAABLgAECn8lAAIOAAcJvBqVIQDTAQAOAAcJvBqVIQDTAQAAAA==.Larrusbain:BAABLgAECn8iAAIdAAcJURZhJgDCAQAdAAcJURZhJgDCAQAAAA==.',
Le='Leafin:BAAALgADCgUJCQABLgAECggJPQASACcXAA==.Lerya:BAACLgAFFH8GAAMeAAMJIQR+QgCdAAAeAAMJIQR+QgCdAAATAAEJVwMNDgA/AAAuAAQKfyEAAhMACQnsEmAIAJoBABMACQnsEmAIAJoBAAAA.Levictus:BAAALgAECgEJAQAAAA==.Lexnn:BAABLgAECn84AAIPAAkJLBM5MwDkAQAPAAkJLBM5MwDkAQAAAA==.Lexonidas:BAAALgADCgEJAgAAAA==.',
Li='Liantelva:BAAALgAECgcJEQAAAA==.Lifepriest:BAAALgAECgEJAQAAAA==.Ligetnoone:BAABLgAECn8aAAIMAAgJmCbiAgADAwAMAAgJmCbiAgADAwAAAA==.Lighte:BAABLgAECn8yAAINAAkJLhxrKQBfAgANAAkJLhxrKQBfAgAAAA==.Lilyith:BAAALgAECgYJDAAAAA==.Lips:BAAALgAECgMJAwAAAA==.',
Lo='Logicx:BAABLgAECn81AAMLAAgJORkyFwD+AQALAAgJORkyFwD+AQAfAAEJqQT7dAAUAAAAAA==.Lorka:BAAALgAECgIJAgAAAA==.Lorvoldenord:BAAALgADCgIJAgAAAA==.',
Lu='Lunarìa:BAAALgADCggJCwAAAA==.',
['Lê']='Lêssa:BAAALgAECgQJBQAAAA==.',
Ma='Magici:BAABLgAECn8vAAINAAgJyg/BcACAAQANAAgJyg/BcACAAQAAAA==.Magnyesis:BAAALgADCgEJAQAAAA==.Mahavailo:BAAALgAECgUJBQAAAA==.Malina:BAAALgAECgEJAQAAAA==.Manimal:BAAALgAECgcJCwAAAA==.Marraud:BAAALgAECgcJBwAAAA==.Mavren:BAAALgAECgUJDAAAAA==.',
Me='Mefisto:BAAALgAECgQJBgABLgAECgYJEQAEAAAAAA==.Megadruid:BAAALgAECgEJAQAAAA==.Mellesaun:BAABLgAECn8mAAQgAAgJwwjDEgAJAQAgAAgJoQjDEgAJAQAPAAYJIwY7sQClAAAZAAQJkgVqWwBzAAAAAA==.Merie:BAAALgADCgYJBwAAAA==.Mewtwo:BAABLgAFFH8PAAIWAAQJVBn1NwBDAQAWAAQJVBn1NwBDAQABLgAFFAgJFwAeAGAUAA==.',
Mi='Miikeey:BAAALgADCgIJAgAAAA==.Mirei:BAAALgADCggJCQAAAA==.Mithrios:BAAALgAECgUJBQABLgAECgkJCAAEAAAAAA==.',
Mo='Moonsaw:BAACLgAFFH8GAAIhAAQJ6R7mCABxAQAhAAQJ6R7mCABxAQAuAAQKfyQAAiEACAlJIbAHALsCACEACAlJIbAHALsCAAAA.Mordella:BAAALgADCgIJAwAAAA==.Moriartus:BAAALgADCgEJAQAAAA==.Mosthated:BAAALgADCgIJAgAAAA==.',
Mu='Muffin:BAEALgADCgYJBgABLgAECgYJEwAWAE8gAA==.',
My='Myrling:BAABLgAECn8gAAMYAAgJTgi/WgAXAQAYAAgJTgi/WgAXAQALAAEJSwK3lQAcAAAAAA==.Mythrial:BAAALgAECgYJCgAAAA==.',
Ne='Nenni:BAAALgADCgYJBgAAAA==.Neph:BAAALgADCgkJCQAAAA==.Newt:BAACLgAFFH8HAAIPAAMJSwxqWQDEAAAPAAMJSwxqWQDEAAAuAAQKfykABA8ACQn2GJUmAB4CAA8ACAmkFpUmAB4CABkABwmVFqQgALgBACAAAQmvAiA1AB8AAAAA.',
Ni='Nimbus:BAACLgAFFH8YAAINAAUJRx5lNgBpAQANAAUJRx5lNgBpAQAuAAQKfy0AAg0ACQnMJHQEAFUDAA0ACQnMJHQEAFUDAAEuAAUUCAkeAB4A8hsA.Ninkasi:BAAALgAECgYJBgAAAA==.Nishikki:BAECLgAFFH8kAAIUAAcJKxwVBAATAgAUAAcJKxwVBAATAgAuAAQKfzwAAhQACQmYI4MCADADABQACQmYI4MCADADAAAA.',
No='Nocanno:BAAALgADCgYJBgAAAA==.Nonbearnary:BAAALgAECgUJBQAAAA==.',
Ny='Nydie:BAABLgAECn87AAIXAAkJNBsoJABdAgAXAAkJNBsoJABdAgAAAA==.Nymuellyn:BAABLgAECn82AAISAAkJPSSrAQBHAwASAAkJPSSrAQBHAwAAAA==.',
Nz='Nzonah:BAAALgADCgEJAQAAAA==.',
Ot='Ottokurai:BAAALgAECgQJBAAAAA==.',
Pa='Palmanance:BAAALgAECgkJCgAAAA==.Pariahus:BAAALgAECgQJBAABLgAECgkJGwAXABceAA==.',
Pe='Penumbral:BAAALgAECgYJDwAAAA==.',
Ph='Phalst:BAAALgAECgEJAgAAAA==.Phibalan:BAAALgAECgMJBAAAAA==.',
Pi='Pixel:BAAALgAECgIJAwAAAA==.Pixie:BAAALgAECgQJCAAAAA==.Pixil:BAAALgADCgEJAQAAAA==.Pixishot:BAABLgAECn8XAAIJAAYJcgxLcAAXAQAJAAYJcgxLcAAXAQAAAA==.',
Pr='Pradigy:BAABLgAECn8dAAMaAAYJehVVsAAAAQAaAAYJxQ9VsAAAAQACAAMJbhduLgDTAAAAAA==.Prestolight:BAAALgAECgEJAQABLgAECgkJIwACAN4gAA==.Proofing:BAAALgAECgQJBAAAAA==.',
Pu='Pubba:BAAALgAECgcJDwAAAA==.Pubbazug:BAAALgAECgUJCwABLgAECgcJDwAEAAAAAA==.Pubismaximus:BAAALgAECgEJAQABLgAECgcJDwAEAAAAAA==.',
Pw='Pwincess:BAABLgAECn8cAAMbAAkJqgnTDgBaAQAbAAkJqgnTDgBaAQAaAAkJcQRGigA9AQAAAA==.',
Ra='Raelyndria:BAABLgAECn8ZAAMUAAkJuRi7HwCsAQAUAAgJvBe7HwCsAQAVAAYJ0BojKABVAQAAAA==.Raengurth:BAAALgAECgYJBwAAAA==.Raenraug:BAAALgADCgMJAwAAAA==.Raidiance:BAAALgADCgYJBgAAAA==.Rakkali:BAAALgAFFAEJAQAAAA==.Rancavus:BAAALgADCgMJAwAAAA==.Rastakehn:BAAALgADCgYJBgAAAA==.Ratraxx:BAAALgADCgYJBgABLgAECggJGgAGAEQWAA==.Razaller:BAABLgAECn8UAAMeAAkJiQ6CKgBrAQAeAAkJiQ6CKgBrAQATAAEJFgE+RgAbAAAAAA==.',
Rc='Rctraxx:BAAALgAECgYJBwABLgAECggJGgAGAEQWAA==.',
Re='Realpro:BAAALgAECgQJBAAAAA==.Redrogue:BAABLgAECn82AAIRAAgJ9QvlDwArAQARAAgJ9QvlDwArAQAAAA==.Revela:BAAALgADCgcJDQAAAA==.',
Ri='Riftan:BAACLgAFFH8TAAIaAAUJIBe2VQAtAQAaAAUJIBe2VQAtAQAuAAQKfzIAAhoACAncIfIaANwCABoACAncIfIaANwCAAAA.Rightousnes:BAAALgADCgcJCQAAAA==.Riviee:BAABLgAECn8ZAAIOAAYJlAYHYAC9AAAOAAYJlAYHYAC9AAAAAA==.',
Ro='Rogun:BAABLgAECn8lAAIKAAgJhA0CDwBTAQAKAAgJhA0CDwBTAQAAAA==.Roredge:BAAALgAECgEJAQABLgAECggJGgAGAEQWAA==.Rosealie:BAAALgADCgMJAwAAAA==.',
Ry='Rycbar:BAAALgADCgkJCQAAAA==.Rynthanuu:BAAALgADCgEJAQAAAA==.',
Sa='Sarann:BAAALgAECgQJCgAAAA==.Sassbringer:BAAALgAECgQJBAAAAA==.Satele:BAAALgAECgYJCwAAAA==.',
Sc='Scarypoppins:BAABLgAECn8jAAICAAkJ3iBaBQDEAgACAAkJ3iBaBQDEAgAAAA==.',
Se='Seloki:BAAALgADCgQJBAAAAA==.Senia:BAAALgAECggJDwAAAA==.Seniortank:BAAALgADCgEJAQAAAA==.Serracha:BAAALgAECgYJDAABLgAFFAIJCAAHAA8PAA==.Serraz:BAAALgAECgMJBgABLgAFFAIJCAAHAA8PAA==.Seònaid:BAAALgAFFAIJBAAAAA==.',
Sh='Shadowkaizen:BAAALgADCgEJAQAAAA==.Shambullance:BAAALgAFFAEJAgABLgAECgYJDQAEAAAAAA==.Shammywaddle:BAABLgAECn8ZAAMGAAgJAyDzIQATAgAGAAYJ4CHzIQATAgAcAAgJnRA2LwBtAQAAAA==.Shamtraxx:BAABLgAECn8aAAMGAAgJRBb5LwDIAQAGAAcJPBb5LwDIAQAcAAcJTw1zRgAvAQAAAA==.Sheraania:BAAALgADCgcJCAAAAA==.',
Si='Sinistress:BAAALgADCgcJCwAAAA==.',
Sk='Skorpius:BAABLgAECn8XAAIWAAcJ0wbtogDxAAAWAAcJ0wbtogDxAAAAAA==.Skumi:BAAALgAECgUJCwAAAA==.',
Sl='Slaytanic:BAABLgAECn82AAIXAAgJSR0YKgBCAgAXAAgJSR0YKgBCAgAAAA==.Slymick:BAABLgAECn8UAAISAAgJOAM5OADTAAASAAgJOAM5OADTAAAAAA==.',
Sn='Snoka:BAAALgAECgcJCQAAAA==.',
So='Solora:BAABLgAECn82AAIcAAgJsgf6QwAKAQAcAAgJsgf6QwAKAQAAAA==.Soluna:BAABLgAECn84AAIXAAkJjBVpOgACAgAXAAkJjBVpOgACAgAAAA==.',
Sp='Sparrowrain:BAAALgAECgMJAwAAAA==.',
St='Stiflerd:BAAALgADCgEJAQAAAA==.Strawry:BAAALgAECgQJCAAAAA==.Stuffedbear:BAABLgAECn8UAAILAAYJBQWnVgCcAAALAAYJBQWnVgCcAAAAAA==.',
Su='Subiegrl:BAAALgAECgQJBAAAAA==.Sunjiwung:BAAALgAECgMJAwAAAA==.Supadin:BAAALgAECgIJAgAAAA==.Supernano:BAAALgAECgUJBQAAAA==.',
Sw='Swll:BAAALgAECgYJDQAAAA==.',
Sy='Sylanann:BAAALgADCgMJAwAAAA==.Syrüs:BAACLgAFFH8LAAIZAAQJvhUnCwAwAQAZAAQJvhUnCwAwAQAuAAQKfyYAAhkACAmpIKwJAHUCABkACAmpIKwJAHUCAAAA.',
['Sã']='Sãrik:BAAALgAECgYJEAAAAA==.',
['Sí']='Sílver:BAABLgAECn8kAAIcAAgJphDFNABPAQAcAAgJphDFNABPAQAAAA==.',
Ta='Taebeck:BAAALgADCgQJBAAAAA==.Tasty:BAAALgADCgYJBgABLgAFFAQJEgAGAP0YAA==.',
Te='Telamon:BAAALgADCgIJAgAAAA==.Teokojin:BAAALgAECgMJAwAAAA==.',
Th='Thalyra:BAABLgAFFH8GAAIPAAMJCBZdSwDtAAAPAAMJCBZdSwDtAAAAAA==.Thirstrap:BAABLgAECn8kAAIZAAgJ5Q64HwBaAQAZAAgJ5Q64HwBaAQAAAA==.Thorge:BAABLgAECn8iAAIBAAkJehXVDQA+AgABAAkJehXVDQA+AgAAAA==.Thyrus:BAAALgADCgQJBAAAAA==.',
Ti='Tips:BAAALgADCgQJBAAAAA==.',
To='Tokesmasmoke:BAAALgAECgMJAwAAAA==.Toragos:BAAALgADCgQJBAAAAA==.',
Tr='Träshley:BAAALgAECgYJEwAAAA==.',
Uk='Uknak:BAAALgAECgQJBwAAAA==.',
Ul='Ulanui:BAAALgADCgMJAwAAAA==.',
Ur='Urma:BAAALgAECgQJBQAAAA==.',
Va='Vaediirn:BAAALgADCgQJBAAAAA==.Vallcore:BAAALgADCgUJBgAAAA==.',
Ve='Vennt:BAABLgAECn8hAAMJAAgJYReoSQCvAQAKAAgJLRFoJwDuAQAJAAYJyR2oSQCvAQAAAA==.Ventt:BAACLgAFFH8dAAIcAAcJOBNvCgDCAQAcAAcJOBNvCgDCAQAuAAQKfzEAAhwACQkjI3oFAPcCABwACQkjI3oFAPcCAAAA.',
Vo='Volstaag:BAAALgAECgEJBgAAAA==.Voluus:BAABLgAECn8VAAIcAAcJqwzZQgAOAQAcAAcJqwzZQgAOAQAAAA==.',
Vr='Vrorag:BAAALgAECgcJEwAAAA==.',
Wa='Walfar:BAAALgAECgYJEQAAAA==.Wallbanger:BAAALgAFFAMJAwAAAA==.Walterlight:BAAALgADCgcJCwAAAA==.Warbuckss:BAAALgAECgQJEQABLgAECgYJHQAaAHoVAA==.Warbucksthe:BAAALgAECgEJAgABLgAECgYJHQAaAHoVAA==.Warbud:BAAALgADCgEJAQAAAA==.Wayme:BAABLgAECn8bAAIRAAYJuA96FADwAAARAAYJuA96FADwAAAAAA==.',
We='Wendorf:BAAALgADCgkJDgAAAA==.',
Wh='Whispyr:BAAALgADCgcJCAAAAA==.Whiteclaw:BAAALgAECgMJAwAAAA==.',
Wo='Wooster:BAAALgAECgIJAwAAAA==.',
Xa='Xaeru:BAAALgAECgEJAgAAAA==.Xahle:BAABLgAECn8cAAIaAAkJpBKnRgDdAQAaAAkJpBKnRgDdAQAAAA==.Xanado:BAAALgADCgEJAQAAAA==.',
Xs='Xsanguinate:BAAALgAECgQJBAAAAA==.',
Ya='Yarikh:BAAALgAECgEJAQAAAA==.',
Za='Zadkiel:BAAALgAFFAEJAQAAAA==.',
Ze='Zeparu:BAABLgAECn8pAAMaAAkJVx2+EgDIAgAaAAkJVx2+EgDIAgAbAAEJcxJALwA6AAAAAA==.Zero:BAAALgAECgUJBwABLgAECgkJHwAIAEkWAA==.',
Zi='Zitillidan:BAAALgAECgcJDQABLgAECgcJJwABAN4VAA==.',
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
