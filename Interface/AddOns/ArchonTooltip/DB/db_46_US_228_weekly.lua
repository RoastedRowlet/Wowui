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

local lookup = {'Hunter-Survival','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Affliction','Unknown-Unknown','Priest-Holy','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Warrior-Protection','Mage-Frost','Warrior-Fury','DemonHunter-Devourer','Paladin-Protection','Warlock-Destruction','Rogue-Subtlety','Evoker-Devastation','Priest-Shadow','Priest-Discipline','Warlock-Demonology','Paladin-Retribution','Druid-Restoration','Shaman-Elemental','DemonHunter-Havoc','DeathKnight-Frost','Paladin-Holy','Evoker-Augmentation','Druid-Guardian','DemonHunter-Vengeance','Monk-Windwalker',}
local provider = {region='US',realm='Uldaman',name='US',type='weekly',zone=46,date='2026-06-07',data={Ad='Ademar:BAABLgAECn8nAAIBAAcJ3hV6HwCdAQABAAcJ3hV6HwCdAQABLgAECggJGQACAGkSAA==.',
Ae='Aenora:BAAALgAECgMJAwAAAA==.',
Ag='Aggrothief:BAAALgAECgUJBgAAAA==.Agrius:BAAALgAECgYJDAAAAA==.',
Ai='Ainokeas:BAAALgAECgIJAgAAAA==.',
Ak='Akurumira:BAAALgAECgEJAQAAAA==.',
Al='Alexändros:BAAALgADCgUJCAAAAA==.Alkie:BAAALgAECgUJCAAAAA==.Allectra:BAAALgAECgYJDwAAAA==.Allupinya:BAAALgAECgUJBwABLgAECgkJIwADAN4gAA==.',
Am='Amnon:BAABLgAECn89AAIEAAkJQSAhAgCzAgAEAAkJQSAhAgCzAgAAAA==.',
Ar='Arelliea:BAAALgADCgEJAQABLgAFFAEJAQAFAAAAAA==.Arlessa:BAAALgAECgQJBAABLgAECgkJOgAGAC8hAA==.',
As='Asaelis:BAAALgAECgYJDQAAAA==.Astauren:BAAALgADCgMJBAAAAA==.Astralflame:BAAALgADCgYJCAAAAA==.',
Au='Augwaddles:BAAALgAECgUJBwABLgAECggJGQAHAAMgAA==.Aurius:BAAALgAECgUJCgABLgAFFAIJCAAIAA8PAA==.',
Av='Avataraang:BAAALgADCgEJAQAAAA==.Avramora:BAAALgAECgUJDAABLgAFFAEJAQAFAAAAAA==.',
Ax='Axila:BAAALgAECgIJAwAAAA==.',
Az='Azdaja:BAACLgAFFH8IAAIIAAIJDw/DQgCHAAAIAAIJDw/DQgCHAAAuAAQKfysAAwgACQn0DuIfAKABAAgACQn0DuIfAKABAAkAAQntAPx3AA8AAAAA.Azgardia:BAAALgAECgYJCAAAAA==.Azryiel:BAAALgAECgcJEAABLgAFFAIJCAAIAA8PAA==.Azulå:BAACLgAFFH8HAAIKAAQJVgkiRAAVAQAKAAQJVgkiRAAVAQAuAAQKfyEAAwoACQnoE5ksACECAAoACQnoE5ksACECAAsAAQmuA7JCAB0AAAAA.',
Ba='Bach:BAABLgAFFH8XAAIMAAUJNyOmEACGAQAMAAUJNyOmEACGAQAAAA==.Balloffur:BAABLgAECn8cAAINAAkJIA5/GQBkAQANAAkJIA5/GQBkAQAAAA==.Bamboostixx:BAABLgAECn8qAAIOAAkJnhGuSAD7AQAOAAkJnhGuSAD7AQAAAA==.',
Be='Bellgirls:BAAALgAECgMJAwAAAA==.Belnetukent:BAAALgADCgEJAQAAAA==.Berastu:BAACLgAFFH8HAAIPAAMJ1giGNgDDAAAPAAMJ1giGNgDDAAAuAAQKfyEAAg8ACQmjFFEkAM0BAA8ACQmjFFEkAM0BAAAA.Berastú:BAAALgAECgYJDQAAAA==.',
Bl='Blackbear:BAAALgAECgMJAwABLgADCgEJAQAFAAAAAA==.Bleufromage:BAAALgADCggJCwAAAA==.Bloodlusst:BAAALgAECgMJBAAAAA==.Bloodraina:BAAALgADCgYJBgAAAA==.',
Bm='Bmm:BAAALgAECgEJAQAAAA==.',
Bo='Bonechill:BAAALgADCgYJDAAAAA==.Boogyboo:BAAALgADCgEJAQAAAA==.Booz:BAABLgAECn8vAAIQAAgJnxs9KgAWAgAQAAgJnxs9KgAWAgAAAA==.Bors:BAABLgAECn8fAAMKAAkJQxmiCQD8AgAKAAkJQxmiCQD8AgALAAUJARHRUgABAQAAAA==.Botch:BAAALgAECgYJBgAAAA==.Bowdacious:BAAALgAECgEJAwABLgAECgkJIwADAN4gAA==.',
Bu='Bubbleõseven:BAAALgADCggJDwAAAA==.Bugabooed:BAAALgADCgkJEAAAAA==.Bunnystalker:BAAALgADCgYJBwAAAA==.',
Ca='Callee:BAABLgAECn8qAAIKAAgJXg2lYAB7AQAKAAgJXg2lYAB7AQAAAA==.Calyse:BAABLgAECn8dAAIRAAcJISFBCwAIAgARAAcJISFBCwAIAgAAAA==.Casblind:BAACLgAFFH8jAAIQAAgJQRpbCwBGAgAQAAgJQRpbCwBGAgAuAAQKfyAAAhAACQk6IHsQAPoCABAACQk6IHsQAPoCAAAA.Casima:BAABLgAECn8bAAIKAAkJVRB8NQD9AQAKAAkJVRB8NQD9AQAAAA==.',
Ch='Chandani:BAAALgAECgYJCAAAAA==.Chesterblat:BAAALgADCgIJAgAAAA==.Cheydinhal:BAABLgAECn9DAAIGAAgJMBaHGAD8AQAGAAgJMBaHGAD8AQAAAA==.Cheydinhil:BAAALgADCgYJCwAAAA==.Chicknwaffle:BAAALgAECgQJCgAAAA==.Chocó:BAAALgADCgEJAQAAAA==.Chumlee:BAABLgAECn8sAAIIAAgJQRliFwDmAQAIAAgJQRliFwDmAQAAAA==.Chunks:BAAALgAECgIJAgAAAA==.',
Ci='Ciri:BAAALgAECgEJAQAAAA==.',
Co='Colleague:BAAALgAECgYJEQAAAA==.Cornmoon:BAAALgADCgUJAwAAAA==.',
Cr='Crank:BAAALgAFFAMJAwABLgAFFAgJIAASAAkiAA==.Crewgy:BAAALgADCgEJAQAAAA==.',
Da='Dalanorea:BAAALgAECgYJBgAAAA==.Dandorn:BAAALgADCgIJAgAAAA==.Darkocean:BAAALgADCgEJAQAAAA==.Darksushi:BAAALgAECgYJEAAAAA==.Daylate:BAAALgADCgUJBQAAAA==.',
Dh='Dhabyss:BAAALgADCggJCAABLgAECgkJNgATAD0kAA==.',
Di='Diménsional:BAABLgAECn8fAAIIAAgJLhCqKgBaAQAIAAgJLhCqKgBaAQAAAA==.Dinbek:BAAALgAECgcJEgAAAA==.Dindino:BAAALgADCgkJEAAAAA==.Dindroc:BAAALgAECgQJBAAAAA==.Dingread:BAAALgAECgYJBgAAAA==.',
Dr='Dragin:BAABLgAECn8pAAIUAAgJqAiLDQAqAQAUAAgJqAiLDQAqAQAAAA==.Dreyla:BAAALgADCgQJCAAAAA==.Drunkmcmonk:BAAALgADCgMJBgAAAA==.',
Du='Duronimo:BAAALgAECgUJBgAAAA==.Dusksurge:BAAALgADCgIJAgAAAA==.',
['Dÿ']='Dÿmmensional:BAAALgAFFAIJAgAAAA==.',
Ec='Eclipze:BAACLgAFFH8TAAMVAAQJ4QunGwAAAQAVAAQJ4QunGwAAAQAWAAIJgAKDRQA9AAAuAAQKfyMABBUACQmqGNIWAAsCABUACQmqGNIWAAsCABYAAQkoB9hbACsAAAYAAQnmARyKACIAAAAA.Eclipzee:BAAALgADCgMJAwABLgAFFAQJEwAVAOELAA==.Eclipzé:BAABLgAECn8cAAMEAAkJNxnxEABEAQAEAAYJPBjxEABEAQAXAAYJMhE6lAAPAQABLgAFFAQJEwAVAOELAA==.',
Ei='Eifel:BAAALgAECgcJEgABLgAECgkJGwAYABceAA==.',
El='Elessardan:BAABLgAECn8tAAMZAAkJmh4ECQAiAwAZAAkJmh4ECQAiAwAMAAIJXhGyawBxAAAAAA==.Ellynara:BAAALgAECgQJBAABLgAECgkJJgABAFEYAA==.Elothien:BAAALgAECgEJAwABLgAECgkJLQAZAJoeAA==.Elvaca:BAAALgAECgUJBQAAAA==.',
En='Endilli:BAABLgAECn8WAAIaAAYJCgXLZwChAAAaAAYJCgXLZwChAAAAAA==.',
Eq='Equinoxis:BAEALgAECgYJCwABLgAFFAgJJQAVAKQZAA==.',
Et='Eternal:BAABLgAFFH8GAAIYAAQJXg0zSwAKAQAYAAQJXg0zSwAKAQAAAA==.',
Ev='Evaki:BAAALgADCgEJAgAAAA==.',
Ez='Ezekiel:BAAALgAECgEJAQAAAA==.',
Fa='Faein:BAAALgADCgIJAgAAAA==.Fallynangel:BAABLgAECn9EAAITAAgJJxd2GQDBAQATAAgJJxd2GQDBAQAAAA==.',
Fe='Fealeen:BAAALgAECgEJAQAAAA==.Fearlock:BAAALgADCgUJCAAAAA==.Felrafram:BAAALgADCgQJAwAAAA==.Fenyx:BAABLgAECn9MAAIIAAkJbRb5EAAqAgAIAAkJbRb5EAAqAgABLgAFFAQJEwANAL8YAA==.',
Fi='Fightnyte:BAAALgAECgUJBQABLgAECgkJKwAXAFUaAQ==.Filho:BAABLgAECn8dAAMKAAcJ6BKzdwBFAQAKAAcJ6BKzdwBFAQALAAIJqALDgABEAAAAAA==.',
Fo='Foth:BAAALgAECgEJAQAAAA==.',
Fr='Friedtips:BAAALgADCgQJBgABLgAFFAQJDwAbALoYAA==.Frostwaffle:BAAALgADCgYJBgABLgAECgQJCgAFAAAAAA==.Frumpy:BAAALgAECgEJAQABLgAECgcJDwAFAAAAAA==.',
Ga='Gabe:BAAALgAECgUJDAAAAA==.Galvek:BAACLgAFFH8RAAQBAAUJaheWEQAvAQABAAUJaheWEQAvAQAKAAIJawvAfwCEAAALAAEJnwNuLABBAAAuAAQKfycABAEACQm+HYgPADMCAAEACAmUHogPADMCAAoABgkOHbFBAKkBAAsABgmhEGM9AGgBAAAA.Garjzlaa:BAAALgAECgYJBwAAAA==.Garugamesh:BAAALgADCgcJDgAAAA==.Gas:BAAALgAECgEJAQABLgAFFAMJAwAFAAAAAA==.',
Gi='Gigglebytes:BAAALgAECgIJAQAAAA==.',
Gn='Gnowen:BAAALgADCgkJEgABLgAECgYJFwARACkaAA==.',
Go='Gojira:BAAALgADCgIJAgAAAA==.',
Gr='Greyswandir:BAABLgAECn8fAAIKAAcJhg4McABWAQAKAAcJhg4McABWAQAAAA==.Gryssli:BAAALgADCgIJAgAAAA==.',
Gu='Gulatz:BAAALgAECgMJAwAAAA==.',
Gw='Gwarr:BAAALgAECgYJDAAAAA==.',
Ha='Harandufu:BAAALgAECgQJBQAAAA==.Hardwön:BAAALgAECgMJAwAAAA==.Harvie:BAAALgADCgYJDAABLgAECgcJHwAKAIYOAA==.Hatani:BAAALgAECgEJAQABLgAECgYJDAAFAAAAAA==.Haylee:BAAALgADCgkJEwAAAA==.',
He='Healingfoxy:BAAALgAECgQJCAAAAA==.Hemofluffin:BAAALgAECgIJAgABLgAFFAUJEwACACAXAA==.',
Hu='Husky:BAAALgAECggJEgAAAA==.',
Ic='Icyfurball:BAAALgAECgIJAgABLgAECggJGgANAJgmAA==.',
Ik='Ikillyounows:BAAALgAECgQJBAAAAA==.',
Il='Ilovesanta:BAAALgAECgYJDQAAAA==.',
In='Indigobleue:BAABLgAECn9BAAQWAAgJ5B07FQAmAgAGAAgJ5B1QFAAqAgAWAAcJcxs7FQAmAgAVAAIJ6QsUagBlAAAAAA==.Infidel:BAAALgAECgUJCAABLgADCgEJAQAFAAAAAA==.',
Ja='Jalincia:BAAALgAECgUJCAAAAA==.Japplen:BAAALgAECgQJCAAAAA==.',
Je='Jeffery:BAAALgADCgUJDAAAAA==.Jeraziah:BAAALgADCgYJDQAAAA==.',
Ji='Jinkalou:BAAALgAECgQJBAABLgAECggJGgAHAEQWAA==.Jinn:BAAALgADCgUJBQAAAA==.Jinsun:BAAALgAECgUJCAAAAA==.Jiñ:BAAALgAECgQJCAAAAA==.',
Jo='Jorenson:BAABLgAECn8sAAICAAkJ1BFxUgDGAQACAAkJ1BFxUgDGAQAAAA==.',
Ju='Justbeatit:BAAALgADCgQJBAAAAA==.',
Ka='Kaether:BAABLgAECn8aAAMGAAkJsgdTMABBAQAGAAkJsgdTMABBAQAVAAIJmADkaQAkAAAAAA==.Kahlesia:BAAALgADCgkJCQAAAA==.Kalzdemar:BAABLgAECn8ZAAMCAAcJaRKqhwBNAQACAAcJVRCqhwBNAQAcAAQJxxiPIwChAAAAAA==.Kasitus:BAABLgAECn8eAAICAAgJJSTcJgBgAgACAAgJJSTcJgBgAgAAAA==.',
Ke='Keldanor:BAAALgAECgEJAQAAAA==.',
Kh='Khei:BAAALgADCgIJAgAAAA==.',
Ki='Kickthebaby:BAAALgADCgYJBgAAAA==.Kilometraje:BAABLgAECn8YAAMDAAgJOxIjHABuAQADAAgJJxEjHABuAQACAAYJTwxYEwGFAAAAAA==.Kira:BAAALgAECgIJAgABLgAFFAMJAwAFAAAAAA==.Kissey:BAAALgAECgYJCwAAAA==.Kivi:BAAALgADCgEJAQAAAA==.',
Ko='Korneliuz:BAACLgAFFH8GAAIHAAIJRhjUWACLAAAHAAIJRhjUWACLAAAuAAQKfxkAAwcABgl3HABCAJkBAAcABgl3HABCAJkBABoABAmWF5ZXANAAAAAA.',
Kr='Kraink:BAAALgADCgEJAQAAAA==.Krayvin:BAAALgADCgIJAgAAAA==.Kringlë:BAAALgAECgYJBgAAAA==.',
Ku='Kungmoofu:BAAALgADCgIJAgABLgAECgcJDwAFAAAAAA==.',
Ky='Kylan:BAAALgAECgEJAQAAAA==.Kyrak:BAAALgAECgYJDwAAAA==.',
La='Labiamajorah:BAAALgADCgIJAgAAAA==.Ladiebee:BAAALgADCggJCAAAAA==.Lainey:BAACLgAFFH8JAAIKAAMJPh1tTgD3AAAKAAMJPh1tTgD3AAAuAAQKfz0AAgoACQlQIHkPAMwCAAoACQlQIHkPAMwCAAAA.Landocamando:BAABLgAECn8qAAIPAAcJxht0IADnAQAPAAcJxht0IADnAQAAAA==.Larrusbain:BAABLgAECn8nAAIdAAcJGxhBIgDpAQAdAAcJGxhBIgDpAQAAAA==.',
Le='Leafin:BAAALgADCgUJCQABLgAECggJRAATACcXAA==.Lerya:BAACLgAFFH8HAAMeAAMJIQTCSACZAAAeAAMJIQTCSACZAAAUAAEJWwM6DwA5AAAuAAQKfyEAAhQACQnsEt8IAJYBABQACQnsEt8IAJYBAAAA.Levictus:BAAALgAECgEJAQAAAA==.Lexnn:BAABLgAECn84AAIQAAkJLBNTNwDeAQAQAAkJLBNTNwDeAQAAAA==.Lexonidas:BAAALgADCgEJAgAAAA==.',
Li='Liantelva:BAAALgAECgcJEQAAAA==.Lifepriest:BAAALgAECgEJAQAAAA==.Ligetnoone:BAABLgAECn8aAAINAAgJmCY2AwD/AgANAAgJmCY2AwD/AgAAAA==.Lighte:BAABLgAECn8yAAIOAAkJLhwcLABjAgAOAAkJLhwcLABjAgAAAA==.Lilyith:BAAALgAECgYJDAAAAA==.Lips:BAAALgAECgMJAwAAAA==.',
Lo='Logicx:BAABLgAECn82AAMMAAgJsRmcFwAGAgAMAAgJsRmcFwAGAgAfAAEJqQRjgAARAAAAAA==.Lorka:BAAALgAECgIJAgAAAA==.Lorvoldenord:BAAALgADCgIJAgAAAA==.',
Lu='Lunarìa:BAAALgADCggJCwAAAA==.',
['Lê']='Lêssa:BAAALgAECgQJBQAAAA==.',
Ma='Magici:BAABLgAECn82AAIOAAgJUhAgcQCSAQAOAAgJUhAgcQCSAQAAAA==.Magnyesis:BAAALgADCgEJAQAAAA==.Mahavailo:BAAALgAECgUJBQAAAA==.Malina:BAAALgAECgEJAQAAAA==.Manimal:BAAALgAECgcJDAAAAA==.Marraud:BAAALgAECgcJBwAAAA==.Mavren:BAAALgAECgUJDAAAAA==.',
Me='Mefisto:BAAALgAECgQJBwABLgAECgYJFwARACkaAA==.Megadruid:BAAALgAECgIJAwAAAA==.Mellesaun:BAABLgAECn8uAAQgAAkJsQpEDwBMAQAgAAkJsQpEDwBMAQAQAAYJIwZ2uACrAAAbAAQJkgVqWwBzAAAAAA==.Meloncholy:BAAALgADCgkJCQAAAA==.Merie:BAAALgADCgYJBwAAAA==.Mewtwo:BAABLgAFFH8QAAIXAAUJVBkDQAA+AQAXAAUJVBkDQAA+AQABLgAFFAgJFwAeAGAUAA==.',
Mi='Miikeey:BAAALgADCgIJAgAAAA==.Mirei:BAAALgADCggJCQAAAA==.Mithrios:BAAALgAECgUJBQABLgAECgkJCAAFAAAAAA==.',
Mo='Moonsaw:BAACLgAFFH8KAAIhAAQJkR+mCQB1AQAhAAQJkR+mCQB1AQAuAAQKfycAAiEACAmLJN4FAOkCACEACAmLJN4FAOkCAAAA.Mordella:BAAALgADCgIJAwAAAA==.Moriartus:BAAALgADCgEJAQAAAA==.Mosthated:BAAALgADCgIJAgAAAA==.',
Mu='Muffin:BAEALgADCgYJBgABLgAECgYJGQAXAOYgAA==.',
My='Myrling:BAABLgAECn8gAAMZAAgJTgh+XgASAQAZAAgJTgh+XgASAQAMAAEJSwJcnQAcAAAAAA==.Mythrial:BAAALgAECgYJCgAAAA==.',
Ne='Nenni:BAAALgADCgYJBgAAAA==.Neph:BAAALgADCgkJCQAAAA==.Newt:BAACLgAFFH8JAAIQAAMJSwxhYQC8AAAQAAMJSwxhYQC8AAAuAAQKfykABBAACQn2GEspABsCABAACAmkFkspABsCABsABwmVFqQgALgBACAAAQmvAvs3AB8AAAAA.',
Ni='Nimbus:BAACLgAFFH8dAAIOAAUJqB7JOgBzAQAOAAUJqB7JOgBzAQAuAAQKfy0AAg4ACQnMJC0FAFkDAA4ACQnMJC0FAFkDAAEuAAUUCAkiAB4A8hsA.Ninkasi:BAAALgAECgYJBgAAAA==.Nishikki:BAECLgAFFH8lAAIVAAgJpBn/AgBXAgAVAAgJpBn/AgBXAgAuAAQKfzwAAhUACQmYI9ACADgDABUACQmYI9ACADgDAAAA.',
No='Nocanno:BAAALgADCgYJBgAAAA==.Nonbearnary:BAAALgAECgUJBQAAAA==.',
Ny='Nydie:BAABLgAECn87AAIYAAkJNBtAJwBcAgAYAAkJNBtAJwBcAgAAAA==.Nymuellyn:BAABLgAECn82AAITAAkJPSTnAQBCAwATAAkJPSTnAQBCAwAAAA==.',
Nz='Nzonah:BAAALgADCgEJAQAAAA==.',
Ot='Ottokurai:BAAALgAECgQJBAAAAA==.',
Pa='Palmanance:BAAALgAECgkJCgAAAA==.Pariahus:BAAALgAECgQJBAABLgAECgkJGwAYABceAA==.',
Pe='Penumbral:BAAALgAECgYJDwAAAA==.',
Ph='Phalst:BAAALgAECgEJAgAAAA==.Phibalan:BAAALgAECgMJBAAAAA==.',
Pi='Pixel:BAAALgAECgIJAwAAAA==.Pixie:BAAALgAECgUJCQAAAA==.Pixil:BAAALgADCgEJAQAAAA==.Pixishot:BAABLgAECn8aAAIKAAcJ9Qw0gQAxAQAKAAcJ9Qw0gQAxAQAAAA==.',
Pr='Pradigy:BAABLgAECn8dAAMCAAYJehW8uAAAAQACAAYJxQ+8uAAAAQADAAMJbhf0MADRAAAAAA==.Prestolight:BAAALgAECgEJAQABLgAECgkJIwADAN4gAA==.Proofing:BAAALgAECgQJBAAAAA==.',
Pu='Pubba:BAAALgAECgcJDwAAAA==.Pubbazug:BAAALgAECgUJCwABLgAECgcJDwAFAAAAAA==.Pubismaximus:BAAALgAECgEJAQABLgAECgcJDwAFAAAAAA==.',
Pw='Pwincess:BAABLgAECn8eAAMcAAkJrQmYDwBuAQAcAAkJrQmYDwBuAQACAAkJcQTnkAA9AQAAAA==.',
Ra='Raelyndria:BAABLgAECn8ZAAMVAAkJuRjaIQCxAQAVAAgJvBfaIQCxAQAWAAYJ0BojKABVAQAAAA==.Raengurth:BAAALgAECgYJBwAAAA==.Raenraug:BAAALgADCgMJAwAAAA==.Raidiance:BAAALgADCgYJBgAAAA==.Rakkali:BAAALgAFFAEJAQAAAA==.Rancavus:BAAALgADCgMJAwAAAA==.Rastakehn:BAAALgADCgYJBgAAAA==.Ratraxx:BAAALgADCgYJBgABLgAECggJGgAHAEQWAA==.Razaller:BAABLgAECn8UAAMeAAkJiQ6CKgBrAQAeAAkJiQ6CKgBrAQAUAAEJFgE+RgAbAAAAAA==.',
Rc='Rctraxx:BAAALgAECgYJBwABLgAECggJGgAHAEQWAA==.',
Re='Realpro:BAAALgAECgQJBAAAAA==.Redrogue:BAABLgAECn89AAISAAgJxwxrEAAwAQASAAgJxwxrEAAwAQAAAA==.Revela:BAAALgADCgcJDQAAAA==.',
Ri='Riftan:BAACLgAFFH8TAAICAAUJIBedYAAsAQACAAUJIBedYAAsAQAuAAQKfzIAAgIACAncIfIaANwCAAIACAncIfIaANwCAAAA.Rightousnes:BAAALgADCgcJCQAAAA==.Riviee:BAABLgAECn8dAAIPAAcJkQcDTgAIAQAPAAcJkQcDTgAIAQAAAA==.',
Ro='Rogun:BAABLgAECn8xAAILAAgJ8RCQDQB5AQALAAgJ8RCQDQB5AQAAAA==.Roredge:BAAALgAECgEJAQABLgAECggJGgAHAEQWAA==.Rosealie:BAAALgADCgMJAwAAAA==.',
Ry='Rycbar:BAAALgADCgkJCQAAAA==.Rynthanuu:BAAALgADCgEJAQAAAA==.',
Sa='Sarann:BAAALgAECgQJCgAAAA==.Sassbringer:BAAALgAECgQJBQAAAA==.Satele:BAAALgAECgYJDQAAAA==.Sauce:BAAALgADCgMJAwAAAA==.',
Sc='Scarypoppins:BAABLgAECn8jAAIDAAkJ3iD8BQC+AgADAAkJ3iD8BQC+AgAAAA==.',
Se='Seloki:BAAALgADCgQJBAAAAA==.Senia:BAAALgAECggJDwAAAA==.Seniortank:BAAALgADCgEJAQAAAA==.Serracha:BAAALgAECgYJDAABLgAFFAIJCAAIAA8PAA==.Serraz:BAAALgAECgMJBgABLgAFFAIJCAAIAA8PAA==.Serrbear:BAAALgAECgcJCAAAAA==.Seònaid:BAAALgAFFAIJBAAAAA==.',
Sh='Shadowkaizen:BAAALgADCgEJAQAAAA==.Shambullance:BAAALgAFFAEJAgABLgAECgYJDQAFAAAAAA==.Shammywaddle:BAABLgAECn8ZAAMHAAgJAyDzIQATAgAHAAYJ4CHzIQATAgAaAAgJnRDDMQBqAQAAAA==.Shamtraxx:BAABLgAECn8aAAMHAAgJRBb5LwDIAQAHAAcJPBb5LwDIAQAaAAcJTw1zRgAvAQAAAA==.Sheraania:BAAALgADCgcJCAAAAA==.',
Si='Sinistress:BAAALgADCgcJCwAAAA==.',
Sk='Skorpius:BAABLgAECn8dAAIXAAcJmwfIpQDxAAAXAAcJmwfIpQDxAAAAAA==.Skumi:BAAALgAECgUJCwAAAA==.',
Sl='Slaytanic:BAABLgAECn89AAIYAAgJQh4RKQBUAgAYAAgJQh4RKQBUAgAAAA==.Slymick:BAABLgAECn8WAAITAAkJYQSOLwAWAQATAAkJYQSOLwAWAQAAAA==.',
Sn='Snoka:BAAALgAECgcJCQAAAA==.',
So='Solora:BAABLgAECn89AAIaAAgJFQjFRwAGAQAaAAgJFQjFRwAGAQAAAA==.Soluna:BAABLgAECn87AAIYAAkJ8xXwPQADAgAYAAkJ8xXwPQADAgAAAA==.',
Sp='Sparrowrain:BAAALgAECgUJBQAAAA==.',
St='Stiflerd:BAAALgADCgEJAQAAAA==.Strawry:BAAALgAECgQJCAAAAA==.Stuffedbear:BAABLgAECn8UAAIMAAYJBQW/WgCcAAAMAAYJBQW/WgCcAAAAAA==.',
Su='Subiegrl:BAAALgAECgQJBAAAAA==.Sunjiwung:BAAALgAECgMJAwAAAA==.Supadin:BAAALgAECgIJAgAAAA==.Supernano:BAAALgAECgUJBQAAAA==.',
Sw='Swll:BAAALgAECgYJDQAAAA==.',
Sy='Sylanann:BAAALgADCgMJAwAAAA==.Syrüs:BAACLgAFFH8PAAIbAAQJuhgmDAA2AQAbAAQJuhgmDAA2AQAuAAQKfyYAAhsACAmpIK4KAHACABsACAmpIK4KAHACAAAA.',
['Sã']='Sãrik:BAAALgAECgYJEAAAAA==.',
['Sí']='Sílver:BAABLgAECn8kAAIaAAgJphCoOABHAQAaAAgJphCoOABHAQAAAA==.',
Ta='Taebeck:BAAALgADCgQJBAAAAA==.Tasty:BAAALgADCgYJBgABLgAFFAQJFgAHAOMbAA==.',
Te='Telamon:BAAALgADCgcJCAAAAA==.Teokojin:BAAALgAECgMJAwAAAA==.',
Th='Thalyra:BAABLgAFFH8GAAIQAAMJCBboUgDmAAAQAAMJCBboUgDmAAAAAA==.Thirstrap:BAABLgAECn8kAAIbAAgJ5Q74IQBYAQAbAAgJ5Q74IQBYAQAAAA==.Thorge:BAABLgAECn8mAAIBAAkJURh1CgB0AgABAAkJURh1CgB0AgAAAA==.Thyrus:BAAALgADCgQJBAAAAA==.',
Ti='Tips:BAAALgADCgQJBAAAAA==.',
To='Tokesmasmoke:BAAALgAECgMJAwAAAA==.Toragos:BAAALgADCgQJBAAAAA==.',
Tr='Träshley:BAAALgAECgYJEwAAAA==.',
Uk='Uknak:BAAALgAECgQJBwAAAA==.',
Ul='Ulanui:BAAALgADCgMJAwAAAA==.',
Un='Unrêstrained:BAAALgADCgQJBAAAAA==.',
Ur='Urma:BAAALgAECgQJBQAAAA==.',
Va='Vaediirn:BAAALgADCgQJBAAAAA==.Vallcore:BAAALgADCgUJBgAAAA==.',
Ve='Vennt:BAABLgAECn8hAAMKAAgJYRdQTwCqAQALAAgJLRFoJwDuAQAKAAYJyR1QTwCqAQABLgAFFAcJHgAaADgTAA==.Ventt:BAACLgAFFH8eAAIaAAcJOBM6DQC1AQAaAAcJOBM6DQC1AQAuAAQKfzEAAhoACQkjIwsGAPMCABoACQkjIwsGAPMCAAAA.',
Vo='Volstaag:BAAALgAECgEJBgAAAA==.Voluus:BAABLgAECn8VAAIaAAcJqwyJRwAHAQAaAAcJqwyJRwAHAQAAAA==.',
Vr='Vrorag:BAAALgAECgcJEwAAAA==.',
Wa='Walfar:BAABLgAECn8XAAIRAAYJKRr5FQBpAQARAAYJKRr5FQBpAQAAAA==.Wallbanger:BAAALgAFFAMJAwAAAA==.Walterlight:BAAALgADCgcJCwAAAA==.Warbuckss:BAAALgAECgQJEQABLgAECgYJHQACAHoVAA==.Warbucksthe:BAAALgAECgEJAgABLgAECgYJHQACAHoVAA==.Warbud:BAAALgADCgQJBwAAAA==.Wayme:BAABLgAECn8fAAISAAcJqw/aEAApAQASAAcJqw/aEAApAQAAAA==.',
We='Wendorf:BAAALgADCgkJDgAAAA==.',
Wh='Whispyr:BAAALgADCgcJCAAAAA==.Whiteclaw:BAAALgAECgMJAwAAAA==.',
Wo='Wooster:BAAALgAECgIJAwAAAA==.',
Xa='Xaeru:BAAALgAECgEJAgAAAA==.Xahle:BAABLgAECn8cAAICAAkJpBJvSgDdAQACAAkJpBJvSgDdAQAAAA==.Xanado:BAAALgADCgEJAQAAAA==.',
Xs='Xsanguinate:BAAALgAECgQJBAAAAA==.',
Ya='Yarikh:BAAALgAECgEJAQAAAA==.',
Za='Zadkiel:BAAALgAFFAEJAQAAAA==.',
Ze='Zeparu:BAABLgAECn8pAAMCAAkJVx2KFADGAgACAAkJVx2KFADGAgAcAAEJcxJnNAA5AAAAAA==.Zero:BAAALgAECgUJBwABLgAECgkJHwAJAEkWAA==.',
Zi='Zitillidan:BAAALgAECgcJDQABLgAECggJGQACAGkSAA==.',
Zo='Zogz:BAAALgAECgYJEwAAAA==.',
['Âi']='Âid:BAAALgADCgkJCQAAAA==.',
['Ëi']='Ëifel:BAABLgAECn8bAAIYAAkJFx4ZIQCmAgAYAAkJFx4ZIQCmAgAAAA==.',
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
