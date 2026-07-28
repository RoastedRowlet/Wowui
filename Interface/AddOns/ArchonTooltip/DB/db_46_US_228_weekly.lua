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

local lookup = {'Hunter-Survival','DeathKnight-Blood','Warlock-Affliction','Unknown-Unknown','Priest-Holy','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Warrior-Protection','Mage-Frost','Warrior-Fury','DemonHunter-Devourer','Paladin-Protection','Priest-Shadow','Rogue-Subtlety','Evoker-Devastation','Priest-Discipline','Warlock-Demonology','Paladin-Retribution','Druid-Restoration','Druid-Guardian','Shaman-Elemental','DemonHunter-Havoc','DeathKnight-Unholy','Paladin-Holy','DeathKnight-Frost','Evoker-Augmentation','DemonHunter-Vengeance','Monk-Windwalker','Warlock-Destruction','Mage-Fire','Rogue-Outlaw',}
local provider = {region='US',realm='Uldaman',name='US',type='weekly',zone=46,date='2026-07-28',data={Ad='Ademar:BAACLgAFFH8QAAIBAAQJWRBUCQD2AAABAAQJWRBUCQD2AAAuAAQKfygAAgEACAn6EzwhAJIBAAEACAn6EzwhAJIBAAAA.',
Ae='Aenora:BAAALgAECgMJAwAAAA==.',
Ag='Aggrothief:BAAALgAECgUJCQAAAA==.Agrius:BAAALgAECgYJDAAAAA==.',
Ai='Ainokeas:BAAALgAECgIJAgAAAA==.',
Ak='Akurumira:BAAALgAECgEJAQAAAA==.',
Al='Alexändros:BAAALgADCgUJCAAAAA==.Alkie:BAAALgAECgcJCgAAAA==.Allectra:BAAALgAECgkJEwAAAA==.Allupinya:BAAALgAECgUJCAABLgAECgkJIwACAN4gAA==.',
Am='Amnon:BAABLgAECn9DAAIDAAkJlyBjAgCvAgADAAkJlyBjAgCvAgAAAA==.',
Ar='Arelliea:BAAALgADCgEJAQABLgAFFAEJAQAEAAAAAA==.Arlessa:BAAALgAECgQJBAABLgAECgkJVwAFAC4kAA==.',
As='Asaelis:BAAALgAECgYJDQAAAA==.Astauren:BAAALgADCgMJBAAAAA==.Astralflame:BAAALgADCgYJCAAAAA==.',
Au='Augwaddles:BAAALgAECgUJBwABLgAECggJGQAGAAMgAA==.Aurius:BAAALgAECgUJCgABLgAFFAMJCgAHAOMLAA==.',
Av='Avataraang:BAAALgADCgEJAQAAAA==.Avramora:BAAALgAECgUJDAABLgAFFAEJAQAEAAAAAA==.',
Ax='Axila:BAAALgAECgIJAwAAAA==.',
Az='Azdaja:BAACLgAFFH8KAAIHAAMJ4wuPRgCFAAAHAAMJ4wuPRgCFAAAuAAQKfy0AAwcACQm5D58eALEBAAcACQm5D58eALEBAAgAAQntAPx3AA8AAAAA.Azgardia:BAAALgAECgYJCAAAAA==.Azryiel:BAAALgAECgcJEAABLgAFFAMJCgAHAOMLAA==.Azulå:BAACLgAFFH8MAAIJAAYJzA/zHAAwAQAJAAYJzA/zHAAwAQAuAAQKfyEAAwkACQnoE4kwABoCAAkACQnoE4kwABoCAAoAAQmuAwlGAB0AAAAA.',
Ba='Bach:BAABLgAFFH8XAAILAAUJNyMdFAB8AQALAAUJNyMdFAB8AQAAAA==.Balloffur:BAACLgAFFH8HAAIMAAMJsAXJEwCAAAAMAAMJsAXJEwCAAAAuAAQKfxwAAgwACQkgDs8aAGIBAAwACQkgDs8aAGIBAAAA.Bamboostixx:BAABLgAECn8xAAINAAkJbBKFDwBRAQANAAkJbBKFDwBRAQAAAA==.',
Be='Beastlyheal:BAAALgAECgQJBAAAAA==.Bellachai:BAAALgAECgYJCAAAAA==.Bellgar:BAAALgAECgMJAwAAAA==.Bellgirls:BAAALgAECgMJAwAAAA==.Belnetukent:BAAALgADCgEJAQAAAA==.Berastu:BAACLgAFFH8OAAIOAAMJfxL3FwDWAAAOAAMJfxL3FwDWAAAuAAQKfyEAAg4ACQmjFFEnAL8BAA4ACQmjFFEnAL8BAAAA.Berastú:BAAALgAECgYJEQAAAA==.Bergalicious:BAAALgAECgkJCgAAAA==.Bergodon:BAAALgADCgEJAQAAAA==.',
Bl='Blackbear:BAAALgAECgMJAwABLgAECgEJAQAEAAAAAA==.Bleufromage:BAAALgADCggJCwAAAA==.Bloodlusst:BAAALgAECgMJBAAAAA==.Bloodraina:BAAALgADCgYJBgAAAA==.',
Bm='Bmm:BAAALgAFFAEJAwAAAA==.',
Bo='Bonechill:BAAALgADCgYJDAAAAA==.Boogyboo:BAAALgADCgEJAQAAAA==.Booz:BAABLgAECn8xAAIPAAkJyRvPGwBtAgAPAAkJyRvPGwBtAgAAAA==.Bors:BAABLgAECn8fAAMJAAkJQxmiCQD8AgAJAAkJQxmiCQD8AgAKAAUJARHRUgABAQAAAA==.Botch:BAAALgAECgkJCgAAAA==.Bowdacious:BAAALgAECgEJBQABLgAECgkJIwACAN4gAA==.',
Br='Breek:BAAALgADCgEJAQAAAA==.',
Bu='Bubbleõseven:BAAALgADCggJDwAAAA==.Bugabooed:BAAALgADCgkJGwAAAA==.Bunnystalker:BAAALgADCgYJBwAAAA==.',
Ca='Callee:BAABLgAECn8rAAIJAAgJXg0lZwB1AQAJAAgJXg0lZwB1AQAAAA==.Calyse:BAABLgAECn8fAAIQAAgJISD2CwAGAgAQAAgJISD2CwAGAgAAAA==.Casblind:BAACLgAFFH8kAAIPAAkJyRk5EAAyAgAPAAkJyRk5EAAyAgAuAAQKfyAAAg8ACQk6IHsQAPoCAA8ACQk6IHsQAPoCAAAA.Casima:BAABLgAECn8eAAIJAAkJVRAcOgD2AQAJAAkJVRAcOgD2AQAAAA==.Castos:BAAALgAECgQJBAAAAA==.',
Ch='Chandani:BAAALgAECgcJCgAAAA==.Chesterblat:BAAALgADCgIJAgAAAA==.Cheydinhal:BAABLgAECn9YAAMFAAgJARzoEQBQAgAFAAgJARzoEQBQAgARAAEJcwMymAAhAAAAAA==.Cheydinhalas:BAAALgADCgYJBgAAAA==.Cheydinhil:BAAALgADCgcJEwAAAA==.Chichi:BAAALgAECgUJBwAAAA==.Chicknwaffle:BAAALgAECgQJDAAAAA==.Chocó:BAAALgADCgEJAQAAAA==.Chumlee:BAABLgAECn8sAAIHAAgJQRlmGADkAQAHAAgJQRlmGADkAQAAAA==.Chunks:BAAALgAECgkJEQAAAA==.',
Ci='Ciri:BAAALgAECgEJAQAAAA==.',
Co='Colleague:BAABLgAECn8fAAIBAAkJWw4kAgDLAQABAAkJWw4kAgDLAQAAAA==.Cornmoon:BAAALgADCgcJDQAAAA==.',
Cr='Crewgy:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.',
Da='Dalanorea:BAAALgAECgYJBgAAAA==.Dandorn:BAAALgADCgIJAgAAAA==.Darkocean:BAAALgADCgEJAQAAAA==.Darksushi:BAABLgAECn8aAAIBAAkJ5hK9AgCLAQABAAkJ5hK9AgCLAQAAAA==.Daylate:BAAALgADCgUJBQAAAA==.',
De='Deadlyhealer:BAABLgAECn8dAAIRAAYJTguuDQDJAAARAAYJTguuDQDJAAAAAA==.Deathbear:BAAALgAECgcJCAABLgAECggJOAACAJgYAA==.Dedinhal:BAAALgADCgYJBwAAAA==.',
Dh='Dhabyss:BAAALgADCggJCAABLgAECgkJOgASAD0kAA==.',
Di='Diménsional:BAABLgAECn8fAAIHAAgJLhARLABZAQAHAAgJLhARLABZAQAAAA==.Dinbek:BAABLgAECn8YAAMJAAkJMRNcFwALAQAJAAkJMRNcFwALAQABAAEJFgSNagAoAAAAAA==.Dindino:BAAALgAECgEJAQAAAA==.Dindroc:BAAALgAECgYJDQAAAA==.Dingread:BAAALgAECgYJBgAAAA==.',
Dr='Dragin:BAABLgAECn8qAAITAAgJvAhTDgAmAQATAAgJvAhTDgAmAQAAAA==.Dreyla:BAAALgADCgQJCAAAAA==.Drunkmcmonk:BAAALgADCgMJBgAAAA==.Dránosh:BAAALgAECgEJAQAAAA==.',
Du='Duronimo:BAAALgAECgYJBwAAAA==.Dusksurge:BAAALgADCgIJAgAAAA==.',
['Dÿ']='Dÿmmensional:BAAALgAFFAIJAgAAAA==.',
Ec='Eclipze:BAACLgAFFH8cAAMRAAYJQQxwHgD+AAARAAUJgw1wHgD+AAAUAAMJ7wIJLABBAAAuAAQKfyMABBEACQmqGGIYAAQCABEACQmqGGIYAAQCABQAAQkoB9hbACsAAAUAAQnmARyKACIAAAAA.Eclipzee:BAAALgADCgMJAwABLgAFFAYJHAARAEEMAA==.Eclipzé:BAACLgAFFH8FAAMDAAQJJguvDwCWAAADAAMJ5wyvDwCWAAAVAAEJ4wUQaQA4AAAuAAQKfxwAAwMACQk3GXASAEEBAAMABgk8GHASAEEBABUABgkyEWaZAAoBAAEuAAUUBgkcABEAQQwA.Eclípze:BAAALgAECgIJAgABLgAFFAYJHAARAEEMAA==.',
Ei='Eifel:BAAALgAECgcJEgABLgAECgkJGwAWABceAA==.Eifël:BAAALgAECgcJBwAAAA==.',
El='Elessardan:BAACLgAFFH8GAAIXAAMJzxJ1PQC6AAAXAAMJzxJ1PQC6AAAuAAQKfzcABBcACQkbILgJAB8DABcACQkbILgJAB8DABgAAwmJE/8LAK0AAAsAAgleEbJrAHEAAAAA.Ellynara:BAAALgAECgUJBQABLgAECgkJNgABAJAaAA==.Elothien:BAAALgAECgEJAwABLgAFFAMJBgAXAM8SAA==.Elvaca:BAAALgAECgUJBQAAAA==.',
En='Endilli:BAABLgAECn8iAAIZAAcJhQe3GABjAAAZAAcJhQe3GABjAAABLgAFFAUJFgAWAN8hAA==.',
Eq='Equinoxis:BAEALgAECgYJCwABLgAFFAgJKQARANcaAA==.',
Et='Eternal:BAABLgAFFH8GAAIWAAQJXg0ZVAAHAQAWAAQJXg0ZVAAHAQAAAA==.',
Ev='Evaki:BAAALgAECgEJAgAAAA==.',
Ez='Ezekiel:BAAALgAECgEJAQAAAA==.',
Fa='Faein:BAAALgADCgIJAgAAAA==.Fallynangel:BAACLgAFFH8KAAISAAQJIxG1EQDtAAASAAQJIxG1EQDtAAAuAAQKf04AAhIACQmfGRYDAKIBABIACQmfGRYDAKIBAAAA.',
Fe='Fealeen:BAAALgAECgEJAQAAAA==.Fearlock:BAAALgADCgUJCAAAAA==.Fedas:BAAALgAFFAIJAgAAAA==.Felrafram:BAAALgADCgQJAwAAAA==.Fenyx:BAACLgAFFH8OAAIHAAMJlQpaPAC1AAAHAAMJlQpaPAC1AAAuAAQKf1IAAgcACQmAFyMRADECAAcACQmAFyMRADECAAEuAAUUBAkpAAwAtRoA.',
Fi='Fiaelyn:BAAALgAECgEJAQAAAA==.Fightnyte:BAAALgAECgUJBQABLgAECgkJNgAVABUcAQ==.Filho:BAABLgAECn8eAAMJAAgJZxFqYwB+AQAJAAgJZxFqYwB+AQAKAAIJqALDgABEAAAAAA==.Fizzletwist:BAAALgAECgEJAQAAAA==.',
Fo='Foth:BAAALgAECgQJBQAAAA==.',
Fr='Friedtips:BAAALgADCgQJBgABLgAFFAYJFgAaAAAVAA==.Frierèn:BAAALgAECgkJEAAAAA==.Frostwaffle:BAAALgADCgYJBgABLgAECgQJDAAEAAAAAA==.Frumpy:BAAALgAECgEJAQABLgAECgYJEwAEAAAAAA==.',
Ga='Gabe:BAAALgAECgYJEwAAAA==.Galvek:BAACLgAFFH8SAAQBAAYJeRXMCACGAQABAAYJeRXMCACGAQAJAAIJawsZjgCDAAAKAAEJnwNuLABBAAAuAAQKfycABAEACQm+HScQAC4CAAEACAmUHicQAC4CAAkABgkOHbFBAKkBAAoABgmhEGM9AGgBAAAA.Garjzlaa:BAAALgAECgYJBwAAAA==.Garugamesh:BAAALgADCgcJDgAAAA==.Gas:BAAALgAECgEJAQABLgAFFAMJAwAEAAAAAA==.',
Ge='Geewhiz:BAAALgADCgEJAQABLgAECgkJOAAQACwOAA==.',
Gh='Ghanjamon:BAAALgADCgYJBgAAAA==.',
Gi='Gigglebytes:BAAALgAECgIJAQAAAA==.',
Gn='Gnowen:BAAALgADCgkJEgABLgAECgYJIwAQACkaAA==.',
Go='Gojira:BAAALgADCgIJAgAAAA==.',
Gr='Greyswandir:BAABLgAECn83AAIJAAkJXBNGDACMAQAJAAkJXBNGDACMAQAAAA==.Gryssli:BAAALgADCgIJAgAAAA==.',
Gu='Gulatz:BAAALgAECgcJCgAAAA==.',
Gw='Gwarr:BAAALgAECgcJDQAAAA==.',
Ha='Hailyea:BAAALgAECgMJAwAAAA==.Harandufu:BAAALgAECgQJBQAAAA==.Hardwön:BAAALgAECgMJAwAAAA==.Harvie:BAAALgADCgYJGAABLgAECgkJNwAJAFwTAA==.Hatani:BAAALgAECgEJAQABLgAECgYJDAAEAAAAAA==.Havøc:BAAALgAECgEJAQABLgAECgUJCQAEAAAAAA==.Haylee:BAAALgADCgkJEwAAAA==.',
He='Healingfoxy:BAABLgAECn8UAAMUAAkJJQjjPQAVAQAUAAkJJQjjPQAVAQARAAEJjw+9IwAxAAAAAA==.Hemofluffin:BAAALgAECgIJAgABLgAFFAUJIAAbAEEZAA==.',
Hu='Hungreborn:BAAALgAECgIJAgAAAA==.Hunnee:BAAALgAECgIJAgAAAA==.Husky:BAAALgAECggJEgABLgAECgkJEQAEAAAAAA==.',
Ic='Icyfurball:BAAALgAECgIJAgABLgAECgkJJQAMAK0mAA==.',
Ik='Ikillyounows:BAAALgAECgQJBAAAAA==.',
Il='Illdinhal:BAAALgADCgIJAgAAAA==.Ilovesanta:BAAALgAECggJDwAAAA==.',
In='Indigobleue:BAABLgAECn9GAAQUAAkJHh7FDgCDAgAUAAgJAhzFDgCDAgAFAAgJ5B2gFQAnAgARAAIJ6QvMcgBcAAAAAA==.Infidel:BAABLgAECn8VAAMWAAkJmAk3GAD9AAAWAAkJmAk3GAD9AAAcAAEJQwFpowAUAAABLgAECgEJAQAEAAAAAA==.Inwë:BAAALgAECgkJCQAAAA==.',
Ja='Jalincia:BAAALgAECgUJCAAAAA==.Japplen:BAAALgAECgYJDQAAAA==.',
Je='Jeffery:BAAALgAECgMJBwAAAA==.Jemera:BAAALgAECgMJBAAAAA==.Jeraziah:BAAALgADCgYJDQAAAA==.',
Ji='Jinkalou:BAAALgAECgQJBAABLgAECggJGgAGAEQWAA==.Jinn:BAAALgADCgUJBQAAAA==.Jinsun:BAAALgAECgUJDgAAAA==.Jiñ:BAAALgAECgQJCAAAAA==.',
Jo='Jorenson:BAABLgAECn8sAAIbAAkJ1BHlWAC7AQAbAAkJ1BHlWAC7AQAAAA==.',
Ju='Justbeatit:BAAALgADCgQJBAAAAA==.',
['Jï']='Jïñ:BAAALgAECgMJAwAAAA==.',
Ka='Kaether:BAABLgAECn8aAAMFAAkJsgeTMgA/AQAFAAkJsgeTMgA/AQARAAIJmADkaQAkAAAAAA==.Kahlesia:BAAALgADCgkJCQAAAA==.Kahuma:BAAALgAFFAIJAgAAAA==.Kalzdemar:BAACLgAFFH8QAAIdAAMJHxeTCgDkAAAdAAMJHxeTCgDkAAAuAAQKfxkAAxsABwlpEoWPAEYBABsABwlVEIWPAEYBAB0ABAnHGA0mAKEAAAEuAAUUBAkQAAEAWRAA.Karanosliw:BAAALgADCgEJAQAAAA==.Kargg:BAAALgAECgcJDQAAAA==.Kasitus:BAABLgAECn8gAAIbAAkJICI6KQBcAgAbAAkJICI6KQBcAgAAAA==.Kaï:BAAALgADCgIJAgAAAA==.',
Ke='Keldanor:BAAALgAECgYJCwAAAA==.',
Kh='Kheann:BAAALgAECgIJAgAAAA==.Khei:BAAALgADCgIJAgAAAA==.',
Ki='Kickthebaby:BAAALgAECgMJAwAAAA==.Kilometraje:BAABLgAECn8YAAMCAAgJOxL2HQBoAQACAAgJJxH2HQBoAQAbAAYJTwxFHwGFAAAAAA==.Kira:BAAALgAECgIJAgABLgAFFAMJAwAEAAAAAA==.Kissey:BAAALgAECgYJEAAAAA==.Kivi:BAAALgADCgEJAQAAAA==.Kizsy:BAAALgAECgEJAQABLgAECgYJEAAEAAAAAA==.',
Ko='Konjar:BAAALgAECgIJAgAAAA==.Korlat:BAAALgAECgQJBAAAAA==.Korneliuz:BAACLgAFFH8GAAIGAAIJRhgKYQCIAAAGAAIJRhgKYQCIAAAuAAQKfxkAAwYABgl3HMJFAJcBAAYABgl3HMJFAJcBABkABAmWF1ZcAM8AAAEuAAUUAwkDAAQAAAAA.',
Kr='Kraink:BAAALgADCgEJAQAAAA==.Krayvin:BAAALgADCgIJAgAAAA==.Kringlë:BAAALgAECgYJBgAAAA==.',
Ku='Kundraa:BAAALgADCgIJAgAAAA==.Kungmoofu:BAAALgAECgMJAwABLgAECgYJEwAEAAAAAA==.',
Ky='Kylan:BAAALgAECgEJAQAAAA==.Kyrak:BAAALgAECggJEgAAAA==.',
La='Labiamajorah:BAAALgADCgIJAgAAAA==.Ladiebee:BAAALgAECgUJBgAAAA==.Lainey:BAACLgAFFH8WAAIJAAUJvBlYHgApAQAJAAUJvBlYHgApAQAuAAQKfz4AAgkACQlQIIIRAMUCAAkACQlQIIIRAMUCAAAA.Landocamando:BAABLgAECn8tAAIOAAgJvBm+GQAgAgAOAAgJvBm+GQAgAgAAAA==.Larrusbain:BAABLgAECn8nAAIcAAcJGxjHIwDnAQAcAAcJGxjHIwDnAQAAAA==.',
Le='Leafin:BAAALgADCgUJCQABLgAFFAQJCgASACMRAA==.Lehae:BAAALgAECgUJBQAAAA==.Lemonpdcake:BAAALgADCgEJAQAAAA==.Lerya:BAACLgAFFH8HAAMeAAMJIQSTTwCQAAAeAAMJIQSTTwCQAAATAAEJWwOBEAA4AAAuAAQKfyEAAhMACQnsEmMJAJQBABMACQnsEmMJAJQBAAAA.Lessa:BAAALgADCgIJAgAAAA==.Lesslessa:BAAALgADCgcJBwAAAA==.Levictus:BAAALgAECgEJAQAAAA==.Lexnn:BAABLgAECn8/AAIPAAkJdhSDCQBPAQAPAAkJdhSDCQBPAQAAAA==.Lexonidas:BAAALgADCgEJAgAAAA==.',
Li='Liantelva:BAAALgAECgcJEQAAAA==.Lifepriest:BAAALgAECgMJBAAAAA==.Lifeweaver:BAAALgAECgcJBwAAAA==.Ligetnoone:BAABLgAECn8lAAIMAAkJrSZsAAB+AwAMAAkJrSZsAAB+AwAAAA==.Lighte:BAABLgAECn86AAINAAkJ0x09HQCtAgANAAkJ0x09HQCtAgAAAA==.Lilyith:BAAALgAECgYJDAAAAA==.Lips:BAAALgAECgMJAwAAAA==.',
Lo='Logicx:BAABLgAECn82AAMLAAgJsRnIGAAGAgALAAgJsRnIGAAGAgAYAAEJqQS7jAARAAAAAA==.Lorin:BAAALgADCgIJAgAAAA==.Lorinne:BAAALgAECgUJBQAAAA==.Lorka:BAAALgAECgIJAgAAAA==.Lorvoldenord:BAAALgADCgIJAgAAAA==.',
Lu='Lunarìa:BAAALgADCggJCwAAAA==.',
['Lê']='Lêssa:BAABLgAECn8XAAIJAAgJaw7kDgBlAQAJAAgJaw7kDgBlAQAAAA==.',
Ma='Magici:BAABLgAECn8/AAINAAkJ/BOSEABFAQANAAkJ/BOSEABFAQAAAA==.Magnyesis:BAAALgADCgEJAQAAAA==.Mahavailo:BAAALgAECgYJBgAAAA==.Malina:BAAALgAECgEJAQAAAA==.Manimal:BAAALgAECgcJDAAAAA==.Marraud:BAABLgAECn8WAAISAAkJvgTFCgCtAAASAAkJvgTFCgCtAAAAAA==.Mavren:BAAALgAECgcJDwAAAA==.',
Me='Mefisto:BAAALgAECgQJBwABLgAECgYJIwAQACkaAA==.Megadruid:BAAALgAECgIJAwAAAA==.Mellesaun:BAABLgAECn9LAAQfAAkJxxauAQCjAQAfAAkJYxWuAQCjAQAaAAYJfxQyBwAoAQAPAAgJGgyjFwC3AAAAAA==.Meloncholy:BAAALgADCgkJGgAAAA==.Merie:BAAALgADCgYJBwAAAA==.Mewtwo:BAABLgAFFH8SAAIVAAYJxhcpSAA3AQAVAAYJxhcpSAA3AQABLgAFFAkJIwAJAE4kAA==.',
Mi='Micali:BAAALgAECgUJBQAAAA==.Miikeey:BAAALgADCgIJAgAAAA==.Mirei:BAAALgADCggJCQAAAA==.Mithrios:BAAALgAECgYJCwABLgAECgkJDgAEAAAAAA==.',
Mo='Modulation:BAAALgAECgEJAQAAAA==.Moonpope:BAAALgAECgEJAQABLgAFFAUJFQAgAPQfAA==.Moonsaw:BAACLgAFFH8VAAIgAAUJ9B+tCgB1AQAgAAUJ9B+tCgB1AQAuAAQKfy4AAiAACQk8JaIFAPYCACAACQk8JaIFAPYCAAAA.Mordella:BAAALgADCgIJAwAAAA==.Mordëkai:BAAALgAECgEJAgAAAA==.Moriartus:BAAALgAECgEJAQAAAA==.Mosthated:BAAALgADCgIJAgAAAA==.',
Mu='Muffin:BAEALgADCgYJBgABLgAECgkJJAAVAL4eAA==.',
My='Myrling:BAACLgAFFH8GAAIXAAMJlgUiVAB0AAAXAAMJlgUiVAB0AAAuAAQKfyEAAxcACQlBCK5hABABABcACQlBCK5hABABAAsAAQlLAjWlABwAAAAA.Mythrial:BAAALgAECgYJCgAAAA==.',
['Mï']='Mïck:BAAALgAECgEJAQABLgAECgkJGAASAKcEAA==.',
Ne='Nenni:BAAALgADCgYJBgAAAA==.Neph:BAAALgADCgkJCQAAAA==.Newt:BAACLgAFFH8TAAIPAAUJFhKJIwD1AAAPAAUJFhKJIwD1AAAuAAQKfykABA8ACQn2GG0rABsCAA8ACAmkFm0rABsCABoABwmVFqQgALgBAB8AAQmvAmI7AB8AAAAA.',
Ni='Nimbus:BAACLgAFFH8dAAINAAUJqB6yQQBpAQANAAUJqB6yQQBpAQAuAAQKfy0AAg0ACQnMJOkFAFMDAA0ACQnMJOkFAFMDAAEuAAUUCQlCAB4AQR0A.Ninkasi:BAAALgAECgYJCAABLgAFFAMJBwAbAIIOAA==.Nishikki:BAECLgAFFH8pAAIRAAgJ1xotAwBvAgARAAgJ1xotAwBvAgAuAAQKfzwAAhEACQmYIyoDADEDABEACQmYIyoDADEDAAAA.',
No='Nocanno:BAAALgADCgYJBgAAAA==.Nonbearnary:BAAALgAECgcJEgAAAA==.',
Ny='Nydie:BAABLgAECn87AAIWAAkJNBuPKgBXAgAWAAkJNBuPKgBXAgAAAA==.Nymuellyn:BAABLgAECn86AAISAAkJPSQvAgA9AwASAAkJPSQvAgA9AwAAAA==.',
Nz='Nzonah:BAAALgADCgUJBQAAAA==.',
Ot='Ottokurai:BAAALgAECgQJBAAAAA==.',
Pa='Palmanance:BAAALgAECgkJCgAAAA==.Pariahus:BAAALgAECgQJBAABLgAECgkJGwAWABceAA==.',
Pe='Pente:BAAALgADCgEJAQAAAA==.Penumbral:BAAALgAECgYJDwAAAA==.Peterios:BAAALgAFFAIJAgABLgAFFAgJJwAGACIcAA==.',
Ph='Phalst:BAAALgAECgEJAgAAAA==.Phibalan:BAAALgAECgMJBAAAAA==.',
Pi='Pixel:BAAALgAECgIJAwAAAA==.Pixie:BAAALgAECgUJCQAAAA==.Pixil:BAAALgADCgEJAQAAAA==.Pixishot:BAABLgAECn8fAAIJAAkJewxwdABWAQAJAAkJewxwdABWAQAAAA==.',
Pr='Pradigy:BAACLgAFFH8GAAMCAAMJOwj3JAA5AAAbAAIJ7QGJCAFQAAACAAEJ2BT3JAA5AAAuAAQKfx0AAwIABgl6FSIzAM8AABsABgnFD+HCAPoAAAIAAwluFyIzAM8AAAAA.Prestolight:BAAALgAECgEJAgABLgAECgkJIwACAN4gAA==.Proofing:BAAALgAECgQJBAAAAA==.',
Pu='Pubba:BAAALgAECgcJEQABLgAECgYJEwAEAAAAAA==.Pubbug:BAAALgAECgYJEwAAAA==.Pubismaximus:BAAALgAECgIJAgABLgAECgYJEwAEAAAAAA==.',
Pw='Pwincess:BAABLgAECn8yAAMdAAkJ7g+MAwBIAQAdAAkJ7g+MAwBIAQAbAAkJcQT8mQA1AQAAAA==.',
Ra='Raelyndria:BAABLgAECn8aAAMRAAkJuRiPIwCsAQARAAgJvBePIwCsAQAUAAYJ0BojKABVAQAAAA==.Raengurth:BAAALgAECgYJBwAAAA==.Raenraug:BAAALgADCgMJAwAAAA==.Raidiance:BAAALgADCgYJBgAAAA==.Rakkali:BAAALgAFFAEJAQAAAA==.Rancavus:BAAALgADCgMJAwAAAA==.Rastakehn:BAAALgADCgYJBgAAAA==.Ratraxx:BAAALgADCgYJBgABLgAECggJGgAGAEQWAA==.Razaller:BAABLgAECn8UAAMeAAkJiQ6CKgBrAQAeAAkJiQ6CKgBrAQATAAEJFgE+RgAbAAAAAA==.',
Rc='Rctraxx:BAAALgAECgYJBwABLgAECggJGgAGAEQWAA==.',
Re='Realpro:BAAALgAECgQJBAAAAA==.Redrogue:BAABLgAECn9LAAIhAAkJGRAMDQBuAQAhAAkJGRAMDQBuAQAAAA==.Revela:BAAALgADCgcJDQAAAA==.',
Ri='Riftan:BAACLgAFFH8gAAMbAAUJQRkbLAAZAQAbAAUJQRkbLAAZAQAdAAEJuQOCKwA7AAAuAAQKfzQAAhsACQmXHvIaANwCABsACQmXHvIaANwCAAAA.Rightousnes:BAAALgADCgcJCQAAAA==.Riviee:BAABLgAECn8iAAIOAAkJ+gd0RgAsAQAOAAkJ+gd0RgAsAQAAAA==.',
Ro='Rogun:BAABLgAECn9dAAIKAAkJRxXuAAAXAgAKAAkJRxXuAAAXAgAAAA==.Roredge:BAAALgAECgEJAQABLgAECggJGgAGAEQWAA==.Rosealie:BAAALgADCgMJAwAAAA==.',
Ry='Rycbar:BAAALgADCgkJCQAAAA==.Rynthanuu:BAAALgADCgEJAQAAAA==.',
Sa='Sarann:BAAALgAECgQJCgAAAA==.Sassbringer:BAAALgAECgUJCgAAAA==.Satele:BAAALgAECgYJEgAAAA==.Saty:BAABLgAFFH8mAAMNAAkJrB+9BADRAgANAAkJCB69BADRAgAiAAYJFxzuAADEAQABLgAFFAkJKAAhAK8gAA==.Sauce:BAAALgADCgMJAwAAAA==.',
Sc='Scarypoppins:BAABLgAECn8jAAICAAkJ3iCVBgC3AgACAAkJ3iCVBgC3AgAAAA==.',
Se='Seloki:BAAALgADCgQJBAAAAA==.Senia:BAABLgAECn8WAAMVAAkJIQhBEADoAAAVAAgJcQhBEADoAAADAAcJ8ALXHACLAAAAAA==.Seniortank:BAAALgADCgEJAQAAAA==.Serracha:BAAALgAECgYJDAABLgAFFAMJCgAHAOMLAA==.Serraz:BAAALgAECgMJBgABLgAFFAMJCgAHAOMLAA==.Serrbear:BAAALgAECgcJCAAAAA==.Seònaid:BAAALgAFFAIJBAABLgAFFAMJBAAEAAAAAA==.',
Sh='Shadowkaizen:BAAALgADCgEJAQAAAA==.Shambullance:BAAALgAFFAEJAgABLgAECgYJDQAEAAAAAA==.Shammywaddle:BAABLgAECn8ZAAMGAAgJAyDzIQATAgAGAAYJ4CHzIQATAgAZAAgJnRBxNABpAQAAAA==.Shamtraxx:BAABLgAECn8aAAMGAAgJRBb5LwDIAQAGAAcJPBb5LwDIAQAZAAcJTw1zRgAvAQAAAA==.Sheraania:BAAALgADCgcJCAAAAA==.',
Si='Sinistress:BAAALgADCgcJCwAAAA==.',
Sk='Skorpius:BAABLgAECn8mAAIVAAkJDwqrDgD/AAAVAAkJDwqrDgD/AAAAAA==.Skumi:BAAALgAECgUJCwAAAA==.',
Sl='Slaytanic:BAABLgAECn9GAAIWAAkJxx0sLABQAgAWAAkJxx0sLABQAgAAAA==.Sleepyholow:BAAALgADCgEJAQAAAA==.Slymick:BAABLgAECn8YAAISAAkJpwTyMQAUAQASAAkJpwTyMQAUAQAAAA==.',
Sn='Snoka:BAAALgAECgkJEQAAAA==.',
So='Solora:BAABLgAECn9LAAIZAAkJ8AufCwDuAAAZAAkJ8AufCwDuAAAAAA==.Soluna:BAABLgAECn9EAAIWAAkJ2hfGBwDjAQAWAAkJ2hfGBwDjAQAAAA==.',
Sp='Sparrowrain:BAAALgAECgUJBQAAAA==.',
St='Stiflerd:BAAALgADCgEJAQAAAA==.Stinkie:BAAALgADCgkJCQAAAA==.Strawry:BAAALgAECgQJCwAAAA==.Stuffedbear:BAABLgAECn8UAAILAAYJBQU2XwCbAAALAAYJBQU2XwCbAAAAAA==.',
Su='Subiegrl:BAAALgAECgQJBAAAAA==.Sunjiwung:BAAALgAECgQJBAAAAA==.Supadin:BAAALgAECgIJAwAAAA==.Supawild:BAAALgADCgEJAQAAAA==.Supernano:BAAALgAECgUJBQAAAA==.',
Sv='Svyra:BAAALgADCgEJAQAAAA==.',
Sw='Swans:BAABLgAECn8UAAIFAAkJewjqBwAqAQAFAAkJewjqBwAqAQAAAA==.Swll:BAAALgAECgYJDQAAAA==.',
Sy='Sylanann:BAAALgADCgMJAwAAAA==.Syrüs:BAACLgAFFH8WAAIaAAYJABVZDgAzAQAaAAYJABVZDgAzAQAuAAQKfysAAhoACQlqIk4FAO0CABoACQlqIk4FAO0CAAAA.',
['Sã']='Sãrik:BAABLgAECn8YAAIWAAYJ+BRsHADdAAAWAAYJ+BRsHADdAAAAAA==.',
['Sí']='Sílver:BAABLgAECn8kAAIZAAgJphASPABFAQAZAAgJphASPABFAQAAAA==.',
Ta='Taebeck:BAAALgADCgQJBAAAAA==.Tasty:BAAALgADCgYJBgABLgAECgkJKAABAPoiAA==.',
Te='Telamon:BAAALgADCgkJEAAAAA==.Teokojin:BAAALgAECgMJAwAAAA==.Tethyssra:BAAALgAECgMJAwAAAA==.',
Th='Thalyra:BAABLgAFFH8HAAIPAAMJCBZhWgDhAAAPAAMJCBZhWgDhAAAAAA==.Thestar:BAAALgADCgEJAQAAAA==.Thingthwee:BAAALgADCgMJAwAAAA==.Thirstrap:BAABLgAECn8zAAIaAAkJ/BZfAgAgAgAaAAkJ/BZfAgAgAgAAAA==.Thorge:BAABLgAECn82AAIBAAkJkBolAQBoAgABAAkJkBolAQBoAgAAAA==.Thyrus:BAAALgADCgQJBAAAAA==.Thíngtwo:BAAALgAECgQJCgAAAA==.',
Ti='Tiltawhirl:BAAALgAECgMJAwAAAA==.Tips:BAAALgADCgQJBAAAAA==.Tiscus:BAAALgADCggJCAAAAA==.',
To='Tokesmasmoke:BAAALgAECgMJAwAAAA==.Toragos:BAAALgADCgQJBAAAAA==.',
Tr='Träshley:BAAALgAECgYJEwAAAA==.',
Tu='Turtlestraza:BAAALgAECgEJAQAAAA==.',
Uk='Uknak:BAAALgAECgQJBwAAAA==.',
Ul='Ulanui:BAAALgADCgMJAwAAAA==.',
Un='Unnserra:BAAALgAECgUJBwABLgAECgkJIQAjAB0YAA==.Unrêstrained:BAAALgADCgQJBAAAAA==.',
Ur='Urma:BAAALgAECgQJBQAAAA==.',
Va='Vaediirn:BAAALgADCgQJBAAAAA==.Vallcore:BAAALgADCgUJBgAAAA==.',
Ve='Vennt:BAACLgAFFH8FAAIJAAUJVw/GQgAoAQAJAAUJVw/GQgAoAQAuAAQKfyEAAwkACAlhFwZVAKUBAAoACAktEWgnAO4BAAkABgnJHQZVAKUBAAEuAAUUBwkeABkAOBMA.Ventt:BAACLgAFFH8eAAIZAAcJOBPGEACjAQAZAAcJOBPGEACjAQAuAAQKfzEAAhkACQkjI7oGAPACABkACQkjI7oGAPACAAAA.Veredelyse:BAAALgAECgYJCwABLgAECgkJIQAjAB0YAA==.',
Vi='Vindicatez:BAAALgAECgIJAgAAAA==.',
Vo='Volstaag:BAAALgAECgEJBwAAAA==.Voluus:BAABLgAECn8WAAIZAAcJHA3aSwAFAQAZAAcJHA3aSwAFAQAAAA==.',
Vr='Vrorag:BAAALgAECgcJEwAAAA==.',
Wa='Walfar:BAABLgAECn8jAAIQAAYJKRoaFwBoAQAQAAYJKRoaFwBoAQAAAA==.Wallbanger:BAAALgAFFAMJAwAAAA==.Walterlight:BAAALgADCgcJCwAAAA==.Warbuckss:BAAALgAFFAEJAgABLgAFFAMJBgACADsIAA==.Warbucksthe:BAAALgAECgEJAgABLgAFFAMJBgACADsIAA==.Warbud:BAAALgADCgYJEQAAAA==.Wayme:BAABLgAECn8kAAIhAAkJpBChDwBGAQAhAAkJpBChDwBGAQAAAA==.',
We='Wendorf:BAAALgADCgkJDgAAAA==.',
Wh='Whispyr:BAAALgADCgcJCAAAAA==.Whiteclaw:BAAALgAECgMJBgAAAA==.',
Wi='Wizzlord:BAAALgAECgYJCwAAAA==.',
Wo='Wooster:BAAALgAECgIJAwAAAA==.',
Wr='Writhshammy:BAAALgAECgQJCAAAAA==.',
Xa='Xaeru:BAAALgAECgEJAgAAAA==.Xahle:BAABLgAECn8cAAIbAAkJpBLoTwDTAQAbAAkJpBLoTwDTAQAAAA==.Xanado:BAAALgADCgEJAQAAAA==.',
Xe='Xenophilius:BAAALgADCgIJAgAAAA==.',
Xs='Xsanguinate:BAAALgAECgQJBAAAAA==.',
Ya='Yarikh:BAAALgAECgEJAQAAAA==.',
Za='Zadkiel:BAAALgAFFAEJAQAAAA==.',
Ze='Zekkhira:BAAALgAECgUJCAABLgAFFAQJCgASACMRAA==.Zendayah:BAAALgADCgMJAwAAAA==.Zeparu:BAACLgAFFH8HAAIbAAMJgg63XACWAAAbAAMJgg63XACWAAAuAAQKfy8AAxsACQnMHVMUAM4CABsACQnMHVMUAM4CAB0AAQlzEiY5ADgAAAAA.Zero:BAAALgAECgUJBwABLgAECgkJHwAIAEkWAA==.',
Zi='Zinkgirl:BAAALgADCgUJBQAAAA==.Zitillidan:BAAALgAECggJEwABLgAFFAQJEAABAFkQAA==.',
Zo='Zogz:BAAALgAECgYJEwAAAA==.',
['Âi']='Âid:BAAALgADCgkJCQAAAA==.',
['Ëi']='Ëifel:BAABLgAECn8bAAIWAAkJFx4ZIQCmAgAWAAkJFx4ZIQCmAgAAAA==.',
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
