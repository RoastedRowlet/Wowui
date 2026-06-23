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

local lookup = {'Hunter-Survival','DeathKnight-Blood','Warlock-Affliction','Unknown-Unknown','Priest-Holy','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Warrior-Protection','Mage-Frost','Warrior-Fury','DemonHunter-Devourer','Paladin-Protection','Priest-Shadow','Warlock-Destruction','Rogue-Subtlety','Evoker-Devastation','Priest-Discipline','Warlock-Demonology','Paladin-Retribution','Druid-Restoration','Shaman-Elemental','DemonHunter-Havoc','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Holy','Evoker-Augmentation','Druid-Guardian','DemonHunter-Vengeance','Monk-Windwalker',}
local provider = {region='US',realm='Uldaman',name='US',type='weekly',zone=46,date='2026-06-21',data={Ad='Ademar:BAACLgAFFH8HAAIBAAQJUgtcAgDrAAABAAQJUgtcAgDrAAAuAAQKfycAAgEABwneFTwhAJIBAAEABwneFTwhAJIBAAAA.',
Ae='Aenora:BAAALgAECgMJAwAAAA==.',
Ag='Aggrothief:BAAALgAECgUJCQAAAA==.Agrius:BAAALgAECgYJDAAAAA==.',
Ai='Ainokeas:BAAALgAECgIJAgAAAA==.',
Ak='Akurumira:BAAALgAECgEJAQAAAA==.',
Al='Alexändros:BAAALgADCgUJCAAAAA==.Alkie:BAAALgAECgUJCAAAAA==.Allectra:BAAALgAECgcJEAAAAA==.Allupinya:BAAALgAECgUJBwABLgAECgkJIwACAN4gAA==.',
Am='Amnon:BAABLgAECn9AAAIDAAkJRyBjAgCvAgADAAkJRyBjAgCvAgAAAA==.',
Ar='Arelliea:BAAALgADCgEJAQABLgAFFAEJAQAEAAAAAA==.Arlessa:BAAALgAECgQJBAABLgAECgkJSgAFAGwiAA==.',
As='Asaelis:BAAALgAECgYJDQAAAA==.Astauren:BAAALgADCgMJBAAAAA==.Astralflame:BAAALgADCgYJCAAAAA==.',
Au='Augwaddles:BAAALgAECgUJBwABLgAECggJGQAGAAMgAA==.Aurius:BAAALgAECgUJCgABLgAFFAIJCAAHAA8PAA==.',
Av='Avataraang:BAAALgADCgEJAQAAAA==.Avramora:BAAALgAECgUJDAABLgAFFAEJAQAEAAAAAA==.',
Ax='Axila:BAAALgAECgIJAwAAAA==.',
Az='Azdaja:BAACLgAFFH8IAAIHAAIJDw+VRgCFAAAHAAIJDw+VRgCFAAAuAAQKfy0AAwcACQm5D54eALEBAAcACQm5D54eALEBAAgAAQntAPx3AA8AAAAA.Azgardia:BAAALgAECgYJCAAAAA==.Azryiel:BAAALgAECgcJEAABLgAFFAIJCAAHAA8PAA==.Azulå:BAACLgAFFH8JAAIJAAUJKQunTQAQAQAJAAUJKQunTQAQAQAuAAQKfyEAAwkACQnoE4swABoCAAkACQnoE4swABoCAAoAAQmuAwhGAB0AAAAA.',
Ba='Bach:BAABLgAFFH8XAAILAAUJNyMcFAB8AQALAAUJNyMcFAB8AQAAAA==.Balloffur:BAABLgAECn8cAAIMAAkJIA7QGgBiAQAMAAkJIA7QGgBiAQAAAA==.Bamboostixx:BAABLgAECn8xAAINAAkJbBLAAgBsAQANAAkJbBLAAgBsAQAAAA==.',
Be='Bellachai:BAAALgAECgEJAQAAAA==.Bellgirls:BAAALgAECgMJAwAAAA==.Belnetukent:BAAALgADCgEJAQAAAA==.Berastu:BAACLgAFFH8JAAIOAAMJ/goRBwCeAAAOAAMJ/goRBwCeAAAuAAQKfyEAAg4ACQmjFE8nAL8BAA4ACQmjFE8nAL8BAAAA.Berastú:BAAALgAECgYJEQAAAA==.Bergodon:BAAALgADCgEJAQAAAA==.',
Bl='Blackbear:BAAALgAECgMJAwABLgADCgEJAQAEAAAAAA==.Bleufromage:BAAALgADCggJCwAAAA==.Bloodlusst:BAAALgAECgMJBAAAAA==.Bloodraina:BAAALgADCgYJBgAAAA==.',
Bm='Bmm:BAAALgAFFAEJAgAAAA==.',
Bo='Bonechill:BAAALgADCgYJDAAAAA==.Boogyboo:BAAALgADCgEJAQAAAA==.Booz:BAABLgAECn8xAAIPAAkJyRvSGwBtAgAPAAkJyRvSGwBtAgAAAA==.Bors:BAABLgAECn8fAAMJAAkJQxmiCQD8AgAJAAkJQxmiCQD8AgAKAAUJARHRUgABAQAAAA==.Botch:BAAALgAECgYJBgAAAA==.Bowdacious:BAAALgAECgEJAwABLgAECgkJIwACAN4gAA==.',
Br='Breek:BAAALgADCgEJAQAAAA==.',
Bu='Bubbleõseven:BAAALgADCggJDwAAAA==.Bugabooed:BAAALgADCgkJGgAAAA==.Bunnystalker:BAAALgADCgYJBwAAAA==.',
Ca='Callee:BAABLgAECn8rAAIJAAgJXg0nZwB1AQAJAAgJXg0nZwB1AQAAAA==.Calyse:BAABLgAECn8dAAIQAAcJISH2CwAGAgAQAAcJISH2CwAGAgAAAA==.Casblind:BAACLgAFFH8jAAIPAAgJQRo8EAAyAgAPAAgJQRo8EAAyAgAuAAQKfyAAAg8ACQk6IHsQAPoCAA8ACQk6IHsQAPoCAAAA.Casima:BAABLgAECn8bAAIJAAkJVRAeOgD2AQAJAAkJVRAeOgD2AQAAAA==.Castos:BAAALgAECgEJAQAAAA==.',
Ch='Chandani:BAAALgAECgcJCgAAAA==.Chesterblat:BAAALgADCgIJAgAAAA==.Cheydinhal:BAABLgAECn9SAAMFAAgJTRrqEQBQAgAFAAgJTRrqEQBQAgARAAEJcwMtmAAhAAAAAA==.Cheydinhil:BAAALgADCgcJDAAAAA==.Chicknwaffle:BAAALgAECgQJCwAAAA==.Chocó:BAAALgADCgEJAQAAAA==.Chumlee:BAABLgAECn8sAAIHAAgJQRllGADkAQAHAAgJQRllGADkAQAAAA==.Chunks:BAAALgAECgMJAwAAAA==.',
Ci='Ciri:BAAALgAECgEJAQAAAA==.',
Co='Colleague:BAABLgAECn8WAAIBAAYJ0wpeAQD1AAABAAYJ0wpeAQD1AAAAAA==.Cornmoon:BAAALgADCgcJCQAAAA==.',
Cr='Crank:BAABLgAFFH8OAAINAAYJPxk1BAC0AQANAAYJPxk1BAC0AQABLgAFFAkJIwASAK8gAA==.Crewgy:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.',
Da='Dalanorea:BAAALgAECgYJBgAAAA==.Dandorn:BAAALgADCgIJAgAAAA==.Darkocean:BAAALgADCgEJAQAAAA==.Darksushi:BAAALgAECgcJEgAAAA==.Daylate:BAAALgADCgUJBQAAAA==.',
De='Deadlyhealer:BAABLgAECn8UAAIRAAYJIwSEAwCiAAARAAYJIwSEAwCiAAAAAA==.Deathbear:BAAALgADCgIJAgABLgAECggJOAACAJgYAA==.',
Dh='Dhabyss:BAAALgADCggJCAABLgAECgkJNgATAD0kAA==.',
Di='Diménsional:BAABLgAECn8fAAIHAAgJLhAPLABZAQAHAAgJLhAPLABZAQAAAA==.Dinbek:BAABLgAECn8UAAMJAAcJAhGfcQBdAQAJAAcJAhGfcQBdAQABAAEJFgSMagAoAAAAAA==.Dindino:BAAALgAECgEJAQAAAA==.Dindroc:BAAALgAECgYJCAAAAA==.Dingread:BAAALgAECgYJBgAAAA==.',
Dr='Dragin:BAABLgAECn8qAAIUAAgJvAhTDgAmAQAUAAgJvAhTDgAmAQAAAA==.Dreyla:BAAALgADCgQJCAAAAA==.Drunkmcmonk:BAAALgADCgMJBgAAAA==.',
Du='Duronimo:BAAALgAECgYJBwAAAA==.Dusksurge:BAAALgADCgIJAgAAAA==.',
['Dÿ']='Dÿmmensional:BAAALgAFFAIJAgAAAA==.',
Ec='Eclipze:BAACLgAFFH8XAAMRAAUJJA1tHgD+AAARAAUJJA1tHgD+AAAVAAIJgALfTAA8AAAuAAQKfyMABBEACQmqGGIYAAQCABEACQmqGGIYAAQCABUAAQkoB9hbACsAAAUAAQnmARyKACIAAAAA.Eclipzee:BAAALgADCgMJAwABLgAFFAUJFwARACQNAA==.Eclipzé:BAACLgAFFH8FAAMDAAQJJguvDwCWAAADAAMJ5wyvDwCWAAAWAAEJ4wU/HQBDAAAuAAQKfxwAAwMACQk3GXISAEEBAAMABgk8GHISAEEBABYABgkyEWWZAAoBAAEuAAUUBQkXABEAJA0A.Eclípze:BAAALgAECgIJAgABLgAFFAUJFwARACQNAA==.',
Ei='Eifel:BAAALgAECgcJEgABLgAECgkJGwAXABceAA==.',
El='Elessardan:BAACLgAFFH8GAAIYAAMJzxJ1PQC6AAAYAAMJzxJ1PQC6AAAuAAQKfy0AAxgACQmaHrgJAB8DABgACQmaHrgJAB8DAAsAAgleEbJrAHEAAAAA.Ellynara:BAAALgAECgQJBAABLgAECgkJJwABAFEYAA==.Elothien:BAAALgAECgEJAwABLgAFFAMJBgAYAM8SAA==.Elvaca:BAAALgAECgUJBQAAAA==.',
En='Endilli:BAABLgAECn8eAAIZAAYJLAf1dQCLAAAZAAYJLAf1dQCLAAAAAA==.',
Eq='Equinoxis:BAEALgAECgYJCwABLgAFFAgJKQARANcaAA==.',
Et='Eternal:BAABLgAFFH8GAAIXAAQJXg0ZVAAHAQAXAAQJXg0ZVAAHAQAAAA==.',
Ev='Evaki:BAAALgAECgEJAQAAAA==.',
Ez='Ezekiel:BAAALgAECgEJAQAAAA==.',
Fa='Faein:BAAALgADCgIJAgAAAA==.Fallynangel:BAACLgAFFH8KAAITAAQJIxEuAwAaAQATAAQJIxEuAwAaAQAuAAQKf0gAAhMACQmbFhsTAAwCABMACQmbFhsTAAwCAAAA.',
Fe='Fealeen:BAAALgAECgEJAQAAAA==.Fearlock:BAAALgADCgUJCAAAAA==.Felrafram:BAAALgADCgQJAwAAAA==.Fenyx:BAACLgAFFH8KAAIHAAMJlQqYBgBwAAAHAAMJlQqYBgBwAAAuAAQKf1AAAgcACQmAFyIRADECAAcACQmAFyIRADECAAEuAAUUBAkaAAwAvxgA.',
Fi='Fightnyte:BAAALgAECgUJBQABLgAECgkJNAAWABUcAQ==.Filho:BAABLgAECn8eAAMJAAgJZxFvYwB+AQAJAAgJZxFvYwB+AQAKAAIJqALDgABEAAAAAA==.',
Fo='Foth:BAAALgAECgQJBQAAAA==.',
Fr='Friedtips:BAAALgADCgQJBgABLgAFFAUJFAAaABEZAA==.Frostwaffle:BAAALgADCgYJBgABLgAECgQJCwAEAAAAAA==.Frumpy:BAAALgAECgEJAQABLgAECgcJEAAEAAAAAA==.',
Ga='Gabe:BAAALgAECgYJEwAAAA==.Galvek:BAACLgAFFH8SAAQBAAYJeRXLCACGAQABAAYJeRXLCACGAQAJAAIJawsYjgCDAAAKAAEJnwNuLABBAAAuAAQKfycABAEACQm+HSkQAC4CAAEACAmUHikQAC4CAAkABgkOHbFBAKkBAAoABgmhEGM9AGgBAAAA.Garjzlaa:BAAALgAECgYJBwAAAA==.Garugamesh:BAAALgADCgcJDgAAAA==.Gas:BAAALgAECgEJAQABLgAFFAMJAwAEAAAAAA==.',
Gi='Gigglebytes:BAAALgAECgIJAQAAAA==.',
Gn='Gnowen:BAAALgADCgkJEgABLgAECgYJHgAQACkaAA==.',
Go='Gojira:BAAALgADCgIJAgAAAA==.',
Gr='Greyswandir:BAABLgAECn8iAAIJAAgJ5Q+qWQCXAQAJAAgJ5Q+qWQCXAQAAAA==.Gryssli:BAAALgADCgIJAgAAAA==.',
Gu='Gulatz:BAAALgAECgcJCgAAAA==.',
Gw='Gwarr:BAAALgAECgcJDQAAAA==.',
Ha='Harandufu:BAAALgAECgQJBQAAAA==.Hardwön:BAAALgAECgMJAwAAAA==.Harvie:BAAALgADCgYJEgABLgAECggJIgAJAOUPAA==.Hatani:BAAALgAECgEJAQABLgAECgYJDAAEAAAAAA==.Haylee:BAAALgADCgkJEwAAAA==.',
He='Healingfoxy:BAAALgAECgcJDwAAAA==.Hemofluffin:BAAALgAECgIJAgABLgAFFAUJGwAbACAXAA==.',
Hu='Hungreborn:BAAALgADCgMJAwAAAA==.Husky:BAAALgAECggJEgAAAA==.',
Ic='Icyfurball:BAAALgAECgIJAgABLgAECgkJIAAMAK0mAA==.',
Ik='Ikillyounows:BAAALgAECgQJBAAAAA==.',
Il='Ilovesanta:BAAALgAECgcJDgAAAA==.',
In='Indigobleue:BAABLgAECn9FAAQVAAkJHh7GDgCDAgAVAAgJAhzGDgCDAgAFAAgJ5B2gFQAnAgARAAIJ6QvGcgBcAAAAAA==.Infidel:BAAALgAECgYJDAABLgADCgEJAQAEAAAAAA==.',
Ja='Jalincia:BAAALgAECgUJCAAAAA==.Japplen:BAAALgAECgYJDQAAAA==.',
Je='Jeffery:BAAALgAECgMJAwAAAA==.Jemera:BAAALgAECgMJAwAAAA==.Jeraziah:BAAALgADCgYJDQAAAA==.',
Ji='Jinkalou:BAAALgAECgQJBAABLgAECggJGgAGAEQWAA==.Jinn:BAAALgADCgUJBQAAAA==.Jinsun:BAAALgAECgUJDQAAAA==.Jiñ:BAAALgAECgQJCAAAAA==.',
Jo='Jorenson:BAABLgAECn8sAAIbAAkJ1BHkWAC7AQAbAAkJ1BHkWAC7AQAAAA==.',
Ju='Justbeatit:BAAALgADCgQJBAAAAA==.',
['Jï']='Jïñ:BAAALgAECgMJAwAAAA==.',
Ka='Kaether:BAABLgAECn8aAAMFAAkJsgePMgA/AQAFAAkJsgePMgA/AQARAAIJmADkaQAkAAAAAA==.Kahlesia:BAAALgADCgkJCQAAAA==.Kalzdemar:BAACLgAFFH8GAAIcAAMJjQ/VAwCKAAAcAAMJjQ/VAwCKAAAuAAQKfxkAAxsABwlpEoGPAEcBABsABwlVEIGPAEcBABwABAnHGA0mAKEAAAEuAAUUBAkHAAEAUgsA.Kasitus:BAABLgAECn8gAAIbAAkJIyI5KQBcAgAbAAkJIyI5KQBcAgAAAA==.Kaï:BAAALgADCgIJAgAAAA==.',
Ke='Keldanor:BAAALgAECgEJAQAAAA==.',
Kh='Khei:BAAALgADCgIJAgAAAA==.',
Ki='Kickthebaby:BAAALgADCgcJEQAAAA==.Kilometraje:BAABLgAECn8YAAMCAAgJOxL1HQBoAQACAAgJJxH1HQBoAQAbAAYJTww/HwGFAAAAAA==.Kira:BAAALgAECgIJAgABLgAFFAMJAwAEAAAAAA==.Kissey:BAAALgAECgYJDwAAAA==.Kivi:BAAALgADCgEJAQAAAA==.',
Ko='Korlat:BAAALgADCgcJBwAAAA==.Korneliuz:BAACLgAFFH8GAAIGAAIJRhgJYQCIAAAGAAIJRhgJYQCIAAAuAAQKfxkAAwYABgl3HL5FAJcBAAYABgl3HL5FAJcBABkABAmWF1FcAM8AAAEuAAUUAwkDAAQAAAAA.',
Kr='Kraink:BAAALgADCgEJAQAAAA==.Krayvin:BAAALgADCgIJAgAAAA==.Kringlë:BAAALgAECgYJBgAAAA==.',
Ku='Kundraa:BAAALgADCgIJAgAAAA==.Kungmoofu:BAAALgAECgMJAwABLgAECgcJEAAEAAAAAA==.',
Ky='Kylan:BAAALgAECgEJAQAAAA==.Kyrak:BAAALgAECgcJEAAAAA==.',
La='Labiamajorah:BAAALgADCgIJAgAAAA==.Ladiebee:BAAALgAECgEJAgAAAA==.Lainey:BAACLgAFFH8NAAIJAAQJvBl8NgBAAQAJAAQJvBl8NgBAAQAuAAQKfz0AAgkACQlQIIURAMUCAAkACQlQIIURAMUCAAAA.Landocamando:BAABLgAECn8sAAIOAAgJvBm9GQAgAgAOAAgJvBm9GQAgAgAAAA==.Larrusbain:BAABLgAECn8nAAIdAAcJGxjGIwDnAQAdAAcJGxjGIwDnAQAAAA==.',
Le='Leafin:BAAALgADCgUJCQABLgAFFAQJCgATACMRAA==.Lemonpdcake:BAAALgADCgEJAQAAAA==.Lerya:BAACLgAFFH8HAAMeAAMJIQSOTwCQAAAeAAMJIQSOTwCQAAAUAAEJWwOCEAA4AAAuAAQKfyEAAhQACQnsEmMJAJQBABQACQnsEmMJAJQBAAAA.Levictus:BAAALgAECgEJAQAAAA==.Lexnn:BAABLgAECn84AAIPAAkJLBO6OQDgAQAPAAkJLBO6OQDgAQAAAA==.Lexonidas:BAAALgADCgEJAgAAAA==.',
Li='Liantelva:BAAALgAECgcJEQAAAA==.Lifepriest:BAAALgAECgEJAQAAAA==.Lifeweaver:BAAALgAECgcJBwAAAA==.Ligetnoone:BAABLgAECn8gAAIMAAkJrSZsAAB+AwAMAAkJrSZsAAB+AwAAAA==.Lighte:BAABLgAECn86AAINAAkJ0x0+HQCtAgANAAkJ0x0+HQCtAgAAAA==.Lilyith:BAAALgAECgYJDAAAAA==.Lips:BAAALgAECgMJAwAAAA==.',
Lo='Logicx:BAABLgAECn82AAMLAAgJsRnHGAAGAgALAAgJsRnHGAAGAgAfAAEJqQS6jAARAAAAAA==.Lorinne:BAAALgADCgQJBAAAAA==.Lorka:BAAALgAECgIJAgAAAA==.Lorvoldenord:BAAALgADCgIJAgAAAA==.',
Lu='Lunarìa:BAAALgADCggJCwAAAA==.',
['Lê']='Lêssa:BAAALgAECgYJCAAAAA==.',
Ma='Magici:BAABLgAECn85AAINAAkJEhFzWwDLAQANAAkJEhFzWwDLAQAAAA==.Magnyesis:BAAALgADCgEJAQAAAA==.Mahavailo:BAAALgAECgUJBQAAAA==.Malina:BAAALgAECgEJAQAAAA==.Manimal:BAAALgAECgcJDAAAAA==.Marraud:BAABLgAECn8UAAITAAcJ6QN+AwBvAAATAAcJ6QN+AwBvAAAAAA==.Mavren:BAAALgAECgUJDAAAAA==.',
Me='Mefisto:BAAALgAECgQJBwABLgAECgYJHgAQACkaAA==.Megadruid:BAAALgAECgIJAwAAAA==.Mellesaun:BAABLgAECn88AAQgAAkJ8RCjAAAmAQAgAAkJ8RCjAAAmAQAPAAYJIwbIwACrAAAaAAQJkgVqWwBzAAAAAA==.Meloncholy:BAAALgADCgkJCQAAAA==.Merie:BAAALgADCgYJBwAAAA==.Mewtwo:BAABLgAFFH8RAAIWAAUJVBkmSAA3AQAWAAUJVBkmSAA3AQABLgAFFAgJGwAeAOEVAA==.',
Mi='Miikeey:BAAALgADCgIJAgAAAA==.Mirei:BAAALgADCggJCQAAAA==.Mithrios:BAAALgAECgUJBQABLgAECgkJCAAEAAAAAA==.',
Mo='Moonsaw:BAACLgAFFH8NAAIhAAQJ9B+tCgB1AQAhAAQJ9B+tCgB1AQAuAAQKfysAAiEACAlXJaIFAPYCACEACAlXJaIFAPYCAAAA.Mordella:BAAALgADCgIJAwAAAA==.Moriartus:BAAALgAECgEJAQAAAA==.Mosthated:BAAALgADCgIJAgAAAA==.',
Mu='Muffin:BAEALgADCgYJBgABLgAECgYJIQAWAGwiAA==.',
My='Myrling:BAACLgAFFH8GAAIYAAMJlgUhVAB0AAAYAAMJlgUhVAB0AAAuAAQKfyEAAxgACQkuCK9hABABABgACQkuCK9hABABAAsAAQlLAjClABwAAAAA.Mythrial:BAAALgAECgYJCgAAAA==.',
['Mï']='Mïck:BAAALgAECgEJAQABLgAECgkJGAATAKgEAA==.',
Ne='Nenni:BAAALgADCgYJBgAAAA==.Neph:BAAALgADCgkJCQAAAA==.Newt:BAACLgAFFH8MAAIPAAQJnwtzUwD0AAAPAAQJnwtzUwD0AAAuAAQKfykABA8ACQn2GHArABsCAA8ACAmkFnArABsCABoABwmVFqQgALgBACAAAQmvAmA7AB8AAAAA.',
Ni='Nimbus:BAACLgAFFH8dAAINAAUJqB6xQQBpAQANAAUJqB6xQQBpAQAuAAQKfy0AAg0ACQnMJOkFAFMDAA0ACQnMJOkFAFMDAAEuAAUUCQkvAB4AUxoA.Ninkasi:BAAALgAECgYJCAAAAA==.Nishikki:BAECLgAFFH8pAAIRAAgJ1xotAwBvAgARAAgJ1xotAwBvAgAuAAQKfzwAAhEACQmYIysDADEDABEACQmYIysDADEDAAAA.',
No='Nocanno:BAAALgADCgYJBgAAAA==.Nonbearnary:BAAALgAECgcJDAAAAA==.',
Ny='Nydie:BAABLgAECn87AAIXAAkJNBuQKgBXAgAXAAkJNBuQKgBXAgAAAA==.Nymuellyn:BAABLgAECn82AAITAAkJPSQvAgA9AwATAAkJPSQvAgA9AwAAAA==.',
Nz='Nzonah:BAAALgADCgEJAQAAAA==.',
Ot='Ottokurai:BAAALgAECgQJBAAAAA==.',
Pa='Palmanance:BAAALgAECgkJCgAAAA==.Pariahus:BAAALgAECgQJBAABLgAECgkJGwAXABceAA==.',
Pe='Pente:BAAALgADCgEJAQAAAA==.Penumbral:BAAALgAECgYJDwAAAA==.',
Ph='Phalst:BAAALgAECgEJAgAAAA==.Phibalan:BAAALgAECgMJBAAAAA==.',
Pi='Pixel:BAAALgAECgIJAwAAAA==.Pixie:BAAALgAECgUJCQAAAA==.Pixil:BAAALgADCgEJAQAAAA==.Pixishot:BAABLgAECn8cAAIJAAgJ2QtzdABWAQAJAAgJ2QtzdABWAQAAAA==.',
Pr='Pradigy:BAABLgAECn8dAAMCAAYJehUfMwDPAAAbAAYJxQ/awgD6AAACAAMJbhcfMwDPAAAAAA==.Prestolight:BAAALgAECgEJAQABLgAECgkJIwACAN4gAA==.Proofing:BAAALgAECgQJBAAAAA==.',
Pu='Pubba:BAAALgAECgcJEAAAAA==.Pubbamoo:BAAALgAECgUJCwAAAA==.Pubismaximus:BAAALgAECgIJAgABLgAECgcJEAAEAAAAAA==.',
Pw='Pwincess:BAABLgAECn8nAAMcAAkJvw13DQCfAQAcAAkJvw13DQCfAQAbAAkJcQT7mQA1AQAAAA==.',
Ra='Raelyndria:BAABLgAECn8aAAMRAAkJuRiOIwCsAQARAAgJvBeOIwCsAQAVAAYJ0BojKABVAQAAAA==.Raengurth:BAAALgAECgYJBwAAAA==.Raenraug:BAAALgADCgMJAwAAAA==.Raidiance:BAAALgADCgYJBgAAAA==.Rakkali:BAAALgAFFAEJAQAAAA==.Rancavus:BAAALgADCgMJAwAAAA==.Rastakehn:BAAALgADCgYJBgAAAA==.Ratraxx:BAAALgADCgYJBgABLgAECggJGgAGAEQWAA==.Razaller:BAABLgAECn8UAAMeAAkJiQ6CKgBrAQAeAAkJiQ6CKgBrAQAUAAEJFgE+RgAbAAAAAA==.',
Rc='Rctraxx:BAAALgAECgYJBwABLgAECggJGgAGAEQWAA==.',
Re='Realpro:BAAALgAECgQJBAAAAA==.Redrogue:BAABLgAECn9BAAISAAkJuw0MDQBuAQASAAkJuw0MDQBuAQAAAA==.Revela:BAAALgADCgcJDQAAAA==.',
Ri='Riftan:BAACLgAFFH8bAAMbAAUJIBf4CwDwAAAbAAUJIBf4CwDwAAAcAAEJuQOEKwA7AAAuAAQKfzQAAhsACQmXHvIaANwCABsACQmXHvIaANwCAAAA.Rightousnes:BAAALgADCgcJCQAAAA==.Riviee:BAABLgAECn8hAAIOAAgJwAdzRgAsAQAOAAgJwAdzRgAsAQAAAA==.',
Ro='Rogun:BAABLgAECn8+AAIKAAgJ6xGPAAAlAQAKAAgJ6xGPAAAlAQAAAA==.Roredge:BAAALgAECgEJAQABLgAECggJGgAGAEQWAA==.Rosealie:BAAALgADCgMJAwAAAA==.',
Ry='Rycbar:BAAALgADCgkJCQAAAA==.Rynthanuu:BAAALgADCgEJAQAAAA==.',
Sa='Sarann:BAAALgAECgQJCgAAAA==.Sassbringer:BAAALgAECgUJCgAAAA==.Satele:BAAALgAECgYJEQAAAA==.Sauce:BAAALgADCgMJAwAAAA==.',
Sc='Scarypoppins:BAABLgAECn8jAAICAAkJ3iCYBgC3AgACAAkJ3iCYBgC3AgAAAA==.',
Se='Seloki:BAAALgADCgQJBAAAAA==.Senia:BAABLgAECn8UAAMWAAgJQwiMBADBAAAWAAYJ6wmMBADBAAADAAcJ8ALXHACLAAAAAA==.Seniortank:BAAALgADCgEJAQAAAA==.Serracha:BAAALgAECgYJDAABLgAFFAIJCAAHAA8PAA==.Serraz:BAAALgAECgMJBgABLgAFFAIJCAAHAA8PAA==.Serrbear:BAAALgAECgcJCAAAAA==.Seònaid:BAAALgAFFAIJBAABLgAFFAMJBAAEAAAAAA==.',
Sh='Shadowkaizen:BAAALgADCgEJAQAAAA==.Shambullance:BAAALgAFFAEJAgABLgAECgYJDQAEAAAAAA==.Shammywaddle:BAABLgAECn8ZAAMGAAgJAyDzIQATAgAGAAYJ4CHzIQATAgAZAAgJnRBvNABpAQAAAA==.Shamtraxx:BAABLgAECn8aAAMGAAgJRBb5LwDIAQAGAAcJPBb5LwDIAQAZAAcJTw1zRgAvAQAAAA==.Sheraania:BAAALgADCgcJCAAAAA==.',
Si='Sinistress:BAAALgADCgcJCwAAAA==.',
Sk='Skorpius:BAABLgAECn8gAAIWAAgJPAfrlQAQAQAWAAgJPAfrlQAQAQAAAA==.Skumi:BAAALgAECgUJCwAAAA==.',
Sl='Slaytanic:BAABLgAECn9AAAIXAAkJjBwuLABQAgAXAAkJjBwuLABQAgAAAA==.Slymick:BAABLgAECn8YAAITAAkJqATwMQAUAQATAAkJqATwMQAUAQAAAA==.',
Sn='Snoka:BAAALgAECgcJCQAAAA==.',
So='Solora:BAABLgAECn9BAAIZAAkJ/Af9QAAwAQAZAAkJ/Af9QAAwAQAAAA==.Soluna:BAABLgAECn9EAAIXAAkJ4BdHAQD7AQAXAAkJ4BdHAQD7AQAAAA==.',
Sp='Sparrowrain:BAAALgAECgUJBQAAAA==.',
St='Stiflerd:BAAALgADCgEJAQAAAA==.Strawry:BAAALgAECgQJCgAAAA==.Stuffedbear:BAABLgAECn8UAAILAAYJBQUyXwCbAAALAAYJBQUyXwCbAAAAAA==.',
Su='Subiegrl:BAAALgAECgQJBAAAAA==.Sunjiwung:BAAALgAECgQJBAAAAA==.Supadin:BAAALgAECgIJAgAAAA==.Supernano:BAAALgAECgUJBQAAAA==.',
Sv='Svyra:BAAALgADCgEJAQAAAA==.',
Sw='Swll:BAAALgAECgYJDQAAAA==.',
Sy='Sylanann:BAAALgADCgMJAwAAAA==.Syrüs:BAACLgAFFH8UAAIaAAUJERlXDgAzAQAaAAUJERlXDgAzAQAuAAQKfygAAhoACQmMIU8FAO0CABoACQmMIU8FAO0CAAAA.',
['Sã']='Sãrik:BAABLgAECn8YAAIXAAYJ+BSqBQDpAAAXAAYJ+BSqBQDpAAAAAA==.',
['Sí']='Sílver:BAABLgAECn8kAAIZAAgJphAPPABFAQAZAAgJphAPPABFAQAAAA==.',
Ta='Taebeck:BAAALgADCgQJBAAAAA==.Tasty:BAAALgADCgYJBgABLgAFFAQJGQAGAOsbAA==.',
Te='Telamon:BAAALgADCgkJEAAAAA==.Teokojin:BAAALgAECgMJAwAAAA==.Tethyssra:BAAALgAECgMJAwAAAA==.',
Th='Thalyra:BAABLgAFFH8HAAIPAAMJCBZiWgDhAAAPAAMJCBZiWgDhAAAAAA==.Thirstrap:BAABLgAECn8kAAIaAAgJ5Q6yJABTAQAaAAgJ5Q6yJABTAQAAAA==.Thorge:BAABLgAECn8nAAIBAAkJURh0CwBpAgABAAkJURh0CwBpAgAAAA==.Thyrus:BAAALgADCgQJBAAAAA==.Thíngtwo:BAAALgAECgQJBgAAAA==.',
Ti='Tips:BAAALgADCgQJBAAAAA==.',
To='Tokesmasmoke:BAAALgAECgMJAwAAAA==.Toragos:BAAALgADCgQJBAAAAA==.',
Tr='Träshley:BAAALgAECgYJEwAAAA==.',
Uk='Uknak:BAAALgAECgQJBwAAAA==.',
Ul='Ulanui:BAAALgADCgMJAwAAAA==.',
Un='Unrêstrained:BAAALgADCgQJBAAAAA==.',
Ur='Urma:BAAALgAECgQJBQAAAA==.',
Va='Vaediirn:BAAALgADCgQJBAAAAA==.Vallcore:BAAALgADCgUJBgAAAA==.',
Ve='Vennt:BAACLgAFFH8FAAIJAAUJVw/HQgAoAQAJAAUJVw/HQgAoAQAuAAQKfyEAAwkACAlhFwZVAKUBAAoACAktEWgnAO4BAAkABgnJHQZVAKUBAAEuAAUUBwkeABkAOBMA.Ventt:BAACLgAFFH8eAAIZAAcJOBPEEACjAQAZAAcJOBPEEACjAQAuAAQKfzEAAhkACQkjI7kGAPACABkACQkjI7kGAPACAAAA.Veredelyse:BAAALgAECgYJCAAAAA==.',
Vo='Volstaag:BAAALgAECgEJBwAAAA==.Voluus:BAABLgAECn8VAAIZAAcJqwzYSwAFAQAZAAcJqwzYSwAFAQAAAA==.',
Vr='Vrorag:BAAALgAECgcJEwAAAA==.',
Wa='Walfar:BAABLgAECn8eAAIQAAYJKRoaFwBoAQAQAAYJKRoaFwBoAQAAAA==.Wallbanger:BAAALgAFFAMJAwAAAA==.Walterlight:BAAALgADCgcJCwAAAA==.Warbuckss:BAAALgAECgQJEQABLgAECgYJHQACAHoVAA==.Warbucksthe:BAAALgAECgEJAgABLgAECgYJHQACAHoVAA==.Warbud:BAAALgADCgUJCwAAAA==.Wayme:BAABLgAECn8jAAISAAgJHBCgDwBGAQASAAgJHBCgDwBGAQAAAA==.',
We='Wendorf:BAAALgADCgkJDgAAAA==.',
Wh='Whispyr:BAAALgADCgcJCAAAAA==.Whiteclaw:BAAALgAECgMJAwAAAA==.',
Wo='Wooster:BAAALgAECgIJAwAAAA==.',
Xa='Xaeru:BAAALgAECgEJAgAAAA==.Xahle:BAABLgAECn8cAAIbAAkJpBLkTwDTAQAbAAkJpBLkTwDTAQAAAA==.Xanado:BAAALgADCgEJAQAAAA==.',
Xe='Xenophilius:BAAALgADCgIJAgAAAA==.',
Xs='Xsanguinate:BAAALgAECgQJBAAAAA==.',
Ya='Yarikh:BAAALgAECgEJAQAAAA==.',
Za='Zadkiel:BAAALgAFFAEJAQAAAA==.',
Ze='Zendayah:BAAALgADCgMJAwAAAA==.Zeparu:BAACLgAFFH8HAAIbAAMJgg5CEwCoAAAbAAMJgg5CEwCoAAAuAAQKfy8AAxsACQnMHVEUAM4CABsACQnMHVEUAM4CABwAAQlzEiY5ADgAAAAA.Zero:BAAALgAECgUJBwABLgAECgkJHwAIAEkWAA==.',
Zi='Zinkgirl:BAAALgADCgUJBQAAAA==.Zitillidan:BAAALgAECggJEwABLgAFFAQJBwABAFILAA==.',
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
