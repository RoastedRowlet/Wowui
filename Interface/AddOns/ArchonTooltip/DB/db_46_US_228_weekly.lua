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

local lookup = {'Hunter-Survival','DeathKnight-Frost','DeathKnight-Blood','Warlock-Affliction','Unknown-Unknown','Priest-Holy','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Warrior-Protection','Mage-Frost','Warrior-Fury','DemonHunter-Devourer','Paladin-Protection','Priest-Shadow','Rogue-Subtlety','Evoker-Devastation','Priest-Discipline','Warlock-Demonology','Paladin-Retribution','Druid-Restoration','Druid-Guardian','Shaman-Elemental','DemonHunter-Havoc','DeathKnight-Unholy','Paladin-Holy','Evoker-Augmentation','Rogue-Outlaw','DemonHunter-Vengeance','Monk-Windwalker','Warlock-Destruction','Mage-Fire',}
local provider = {region='US',realm='Uldaman',name='US',type='weekly',zone=46,date='2026-08-25',data={Ad='Ademar:BAACLgAFFH8QAAIBAAQJWRBPCgDxAAABAAQJWRBPCgDxAAAuAAQKfygAAgEACAn6EzwhAJIBAAEACAn6EzwhAJIBAAEuAAUUAwkQAAIAHxcA.',
Ae='Aenora:BAAALgAECgMJAwAAAA==.',
Ag='Aggrothief:BAAALgAECgUJCQAAAA==.Agrius:BAAALgAECgYJDAAAAA==.',
Ai='Ainokeas:BAAALgAECgIJAgAAAA==.',
Ak='Akurumira:BAAALgAECgEJAQAAAA==.',
Al='Alexändros:BAAALgADCgUJCAAAAA==.Alkie:BAAALgAECgcJCgAAAA==.Allectra:BAAALgAECgkJEwAAAA==.Allupinya:BAAALgAECgUJCAABLgAECgkJIwADAN4gAA==.',
Am='Amnon:BAABLgAECn9DAAIEAAkJlyBjAgCvAgAEAAkJlyBjAgCvAgAAAA==.',
An='Anáthema:BAAALgADCgEJAQAAAA==.',
Ar='Arelliea:BAAALgADCgEJAQABLgAFFAEJAQAFAAAAAA==.Arlessa:BAAALgAECgQJBAABLgAECgkJVwAGAC4kAA==.',
As='Asaelis:BAAALgAECgYJDQAAAA==.Astauren:BAAALgADCgMJBAAAAA==.Astralflame:BAAALgADCgYJCAAAAA==.',
Au='Augwaddles:BAAALgAECgUJBwABLgAECggJGQAHAAMgAA==.Aurius:BAAALgAECgUJCgABLgAFFAMJCgAIAOMLAA==.',
Av='Avataraang:BAAALgADCgEJAQAAAA==.Avramora:BAAALgAECgUJDAABLgAFFAEJAQAFAAAAAA==.',
Ax='Axila:BAAALgAECgIJAwAAAA==.',
Az='Azdaja:BAACLgAFFH8KAAIIAAMJ4wuPRgCFAAAIAAMJ4wuPRgCFAAAuAAQKfy0AAwgACQm5D58eALEBAAgACQm5D58eALEBAAkAAQntAPx3AA8AAAAA.Azgardia:BAAALgAECgYJCAAAAA==.Azryiel:BAAALgAECgcJEAABLgAFFAMJCgAIAOMLAA==.Azulå:BAACLgAFFH8MAAIKAAYJzA+zHwAtAQAKAAYJzA+zHwAtAQAuAAQKfyEAAwoACQnoE4kwABoCAAoACQnoE4kwABoCAAsAAQmuAwlGAB0AAAAA.',
Ba='Bach:BAABLgAFFH8XAAIMAAUJNyMdFAB8AQAMAAUJNyMdFAB8AQAAAA==.Balloffur:BAACLgAFFH8HAAINAAMJsAXJFQB0AAANAAMJsAXJFQB0AAAuAAQKfyMAAg0ACQkKDwgGACABAA0ACQkKDwgGACABAAAA.Bamboostixx:BAABLgAECn8xAAIOAAkJbBIHEgBPAQAOAAkJbBIHEgBPAQAAAA==.',
Be='Beastlyheal:BAAALgAECgQJBAAAAA==.Bellachai:BAAALgAECgYJCAAAAA==.Bellgar:BAAALgAECgMJAwAAAA==.Bellgirls:BAAALgAECgMJAwAAAA==.Belnetukent:BAAALgADCgEJAQAAAA==.Berastu:BAACLgAFFH8OAAIPAAMJfxLGGQDUAAAPAAMJfxLGGQDUAAAuAAQKfyEAAg8ACQmjFFEnAL8BAA8ACQmjFFEnAL8BAAAA.Berastú:BAAALgAECgYJEQAAAA==.Bergalicious:BAAALgAECgkJCgAAAA==.Bergodon:BAAALgADCgEJAQAAAA==.',
Bl='Blackbear:BAAALgAECgMJAwABLgAECgEJAQAFAAAAAA==.Bleufromage:BAAALgADCggJCwAAAA==.Bloodlusst:BAAALgAECgMJBAAAAA==.Bloodraina:BAAALgADCgYJBgAAAA==.',
Bm='Bmm:BAAALgAFFAEJAwAAAA==.',
Bo='Bonechill:BAAALgADCgYJDAAAAA==.Boogyboo:BAAALgADCgEJAQAAAA==.Booz:BAABLgAECn8xAAIQAAkJyRvPGwBtAgAQAAkJyRvPGwBtAgAAAA==.Bors:BAABLgAECn8fAAMKAAkJQxmiCQD8AgAKAAkJQxmiCQD8AgALAAUJARHRUgABAQAAAA==.Botch:BAAALgAECgkJCgAAAA==.Bowdacious:BAAALgAECgEJBQABLgAECgkJIwADAN4gAA==.',
Br='Breek:BAAALgADCgEJAQAAAA==.',
Bu='Bubbleõseven:BAAALgADCggJDwAAAA==.Bugabooed:BAAALgADCgkJGwAAAA==.Bunnystalker:BAAALgADCgYJBwAAAA==.',
Ca='Callee:BAABLgAECn8rAAIKAAgJXg0lZwB1AQAKAAgJXg0lZwB1AQAAAA==.Calyse:BAABLgAECn8fAAIRAAgJISD2CwAGAgARAAgJISD2CwAGAgAAAA==.Casblind:BAACLgAFFH8lAAIQAAkJyRk5EAAyAgAQAAkJyRk5EAAyAgAuAAQKfyAAAhAACQk6IHsQAPoCABAACQk6IHsQAPoCAAAA.Casima:BAABLgAECn8eAAIKAAkJVRAcOgD2AQAKAAkJVRAcOgD2AQAAAA==.Castos:BAAALgAECgQJBAAAAA==.',
Ch='Chandani:BAAALgAECgcJCgAAAA==.Chesterblat:BAAALgADCgIJAgAAAA==.Cheydinhal:BAABLgAECn9YAAMGAAgJARzoEQBQAgAGAAgJARzoEQBQAgASAAEJcwMymAAhAAAAAA==.Cheydinhalas:BAAALgADCgYJBgAAAA==.Cheydinhil:BAAALgADCgcJEwAAAA==.Chichi:BAAALgAECgUJBwAAAA==.Chicknwaffle:BAAALgAECgQJDAAAAA==.Chocó:BAAALgADCgEJAQAAAA==.Chumlee:BAABLgAECn8sAAIIAAgJQRlmGADkAQAIAAgJQRlmGADkAQAAAA==.Chunks:BAABLgAECn8XAAIKAAkJaCCHAgDvAgAKAAkJaCCHAgDvAgAAAA==.',
Ci='Ciri:BAAALgAECgEJAQAAAA==.',
Co='Colleague:BAABLgAECn8iAAIBAAkJjBIRAgD4AQABAAkJjBIRAgD4AQAAAA==.Cornmoon:BAAALgADCgcJDQAAAA==.',
Cr='Crewgy:BAAALgADCgEJAQABLgAECgEJAQAFAAAAAA==.',
Da='Dalanorea:BAAALgAECgYJBgAAAA==.Dandorn:BAAALgADCgIJAgAAAA==.Darkocean:BAAALgADCgEJAQAAAA==.Darksushi:BAABLgAECn8aAAIBAAkJ5hJaAwCCAQABAAkJ5hJaAwCCAQAAAA==.Daylate:BAAALgADCgUJBQAAAA==.',
De='Deadlyhealer:BAABLgAECn8dAAISAAYJTgteEADDAAASAAYJTgteEADDAAAAAA==.Deathbear:BAAALgAECgcJCAABLgAECggJOAADAJgYAA==.Dedinhal:BAAALgADCgYJBwAAAA==.',
Dh='Dhabyss:BAAALgADCggJCAABLgAECgkJOgATAD0kAA==.',
Di='Diménsional:BAABLgAECn8fAAIIAAgJLhARLABZAQAIAAgJLhARLABZAQAAAA==.Dinbek:BAABLgAECn8YAAMKAAkJMRMpGwAIAQAKAAkJMRMpGwAIAQABAAEJFgSNagAoAAAAAA==.Dindino:BAAALgAECgEJAQAAAA==.Dindroc:BAAALgAECgYJDQAAAA==.Dingread:BAAALgAECgYJBgAAAA==.',
Dr='Dragin:BAABLgAECn8qAAIUAAgJvAhTDgAmAQAUAAgJvAhTDgAmAQAAAA==.Dreyla:BAAALgADCgQJCAAAAA==.Drunkmcmonk:BAAALgADCgMJBgAAAA==.Dránosh:BAAALgAECgEJAQAAAA==.',
Du='Duronimo:BAAALgAECgYJBwAAAA==.Dusksurge:BAAALgADCgIJAgAAAA==.',
['Dÿ']='Dÿmmensional:BAAALgAFFAIJAgAAAA==.',
Ec='Eclipze:BAACLgAFFH8dAAMSAAcJvAymEwDIAAASAAYJ1w2mEwDIAAAVAAMJ7wKkLgBBAAAuAAQKfyMABBIACQmqGGIYAAQCABIACQmqGGIYAAQCABUAAQkoB9hbACsAAAYAAQnmARyKACIAAAAA.Eclipzee:BAAALgADCgMJAwABLgAFFAcJHQASALwMAA==.Eclipzé:BAACLgAFFH8FAAMEAAQJJguvDwCWAAAEAAMJ5wyvDwCWAAAWAAEJ4wUZaQA4AAAuAAQKfxwAAwQACQk3GXASAEEBAAQABgk8GHASAEEBABYABgkyEWaZAAoBAAEuAAUUBwkdABIAvAwA.Eclípze:BAAALgAFFAEJAQABLgAFFAcJHQASALwMAA==.',
Ei='Eifel:BAAALgAECgcJEgABLgAECgkJGwAXABceAA==.Eifël:BAAALgAECgcJBwAAAA==.',
El='Elessardan:BAACLgAFFH8GAAIYAAMJzxJ1PQC6AAAYAAMJzxJ1PQC6AAAuAAQKfzcABBgACQkbILgJAB8DABgACQkbILgJAB8DABkAAwmJE4oNAKoAAAwAAgleEbJrAHEAAAAA.Ellynara:BAAALgAECgUJBQABLgAECgkJNgABAJAaAA==.Elothien:BAAALgAECgEJAwABLgAFFAMJBgAYAM8SAA==.Elvaca:BAAALgAECgUJBQAAAA==.Elvalin:BAAALgAECgEJAgABLgAECgkJIwADAN4gAA==.',
En='Endilli:BAABLgAECn8iAAIaAAcJhQdcHgBdAAAaAAcJhQdcHgBdAAABLgAFFAUJFgAXAN8hAA==.',
Eq='Equinoxis:BAEALgAECgYJCwABLgAFFAkJLAASAP4ZAA==.',
Et='Eternal:BAABLgAFFH8GAAIXAAQJXg0ZVAAHAQAXAAQJXg0ZVAAHAQAAAA==.',
Ev='Evaki:BAAALgAECgEJAgAAAA==.',
Ez='Ezekiel:BAAALgAECgEJAQAAAA==.',
Fa='Faein:BAAALgADCgIJAgAAAA==.Fallynangel:BAACLgAFFH8KAAITAAQJIxF9EwDmAAATAAQJIxF9EwDmAAAuAAQKf04AAhMACQmfGagDAKABABMACQmfGagDAKABAAAA.',
Fe='Fealeen:BAAALgAECgEJAQAAAA==.Fearlock:BAAALgADCgUJCAAAAA==.Fedas:BAAALgAFFAIJAgAAAA==.Felrafram:BAAALgADCgQJAwAAAA==.Fenyx:BAACLgAFFH8OAAIIAAMJlQpaPAC1AAAIAAMJlQpaPAC1AAAuAAQKf1IAAggACQmAFyMRADECAAgACQmAFyMRADECAAEuAAUUBQkqAA0AtRoA.',
Fi='Fightnyte:BAAALgAECgUJBQABLgAECgkJNgAWABUcAQ==.Filho:BAABLgAECn8eAAMKAAgJZxFqYwB+AQAKAAgJZxFqYwB+AQALAAIJqALDgABEAAAAAA==.Fizzletwist:BAAALgAECgEJAQAAAA==.',
Fo='Foth:BAAALgAECgQJBQAAAA==.',
Fr='Friedtips:BAAALgADCgQJBgABLgAFFAcJFwAbABYTAA==.Frierèn:BAAALgAECgkJEAAAAA==.Frisbee:BAAALgAECgYJBgABLgAECgkJEwAFAAAAAA==.Frostwaffle:BAAALgADCgYJBgABLgAECgQJDAAFAAAAAA==.Frumpy:BAAALgAECgEJAQABLgAECgYJEwAFAAAAAA==.',
Ga='Gabe:BAAALgAECgYJEwAAAA==.Galvek:BAACLgAFFH8SAAQBAAYJeRXMCACGAQABAAYJeRXMCACGAQAKAAIJawsZjgCDAAALAAEJnwNuLABBAAAuAAQKfycABAEACQm+HScQAC4CAAEACAmUHicQAC4CAAoABgkOHbFBAKkBAAsABgmhEGM9AGgBAAAA.Garjzlaa:BAAALgAECgYJBwAAAA==.Garugamesh:BAAALgADCgcJDgAAAA==.Gas:BAAALgAECgEJAQABLgAFFAMJAwAFAAAAAA==.',
Ge='Geewhiz:BAAALgADCgEJAQABLgAECgkJOAARACwOAA==.',
Gh='Ghanjamon:BAAALgADCgYJBgAAAA==.',
Gi='Gigglebytes:BAAALgAECgIJAQAAAA==.',
Gn='Gnowen:BAAALgADCgkJEgABLgAECgYJIwARACkaAA==.',
Go='Gojira:BAAALgADCgIJAgAAAA==.',
Gr='Greyswandir:BAABLgAECn83AAIKAAkJXBODDgCKAQAKAAkJXBODDgCKAQAAAA==.Gryssli:BAAALgADCgIJAgAAAA==.',
Gu='Gulatz:BAAALgAECgcJCgAAAA==.',
Gw='Gwarr:BAAALgAECgcJDQAAAA==.',
Ha='Hailyea:BAAALgAECgMJAwAAAA==.Harandufu:BAAALgAECgQJBQAAAA==.Hardwön:BAAALgAECgMJAwAAAA==.Harusi:BAAALgADCgEJAQAAAA==.Harvie:BAAALgADCgYJGAABLgAECgkJNwAKAFwTAA==.Hatani:BAAALgAECgEJAQABLgAECgYJDAAFAAAAAA==.Havøc:BAAALgAECgEJAQABLgAECgUJCQAFAAAAAA==.Haylee:BAAALgADCgkJEwAAAA==.',
He='Healingfoxy:BAABLgAECn8UAAMVAAkJJQjjPQAVAQAVAAkJJQjjPQAVAQASAAEJjw9bKQAwAAAAAA==.Hemofluffin:BAAALgAECgIJAgABLgAFFAUJIAAcAEEZAA==.',
Ho='Hossdresden:BAAALgADCgEJAQAAAA==.',
Hu='Hungreborn:BAAALgAECgIJAgAAAA==.Hunnee:BAAALgAECgIJAgAAAA==.Hunterkiil:BAAALgADCgEJAQAAAA==.Husky:BAAALgAECggJEgABLgAECgkJFwAKAGggAA==.',
Ic='Icyfurball:BAAALgAECgIJAgABLgAECgkJJQANAK0mAA==.',
Ik='Ikillyounows:BAAALgAECgQJBAAAAA==.',
Il='Illdinhal:BAAALgADCgIJAgAAAA==.Ilovesanta:BAAALgAECggJDwAAAA==.',
In='Indigobleue:BAACLgAFFH8GAAMGAAMJIBgjHQDPAAAGAAMJ+hcjHQDPAAAVAAEJEhRkLwA8AAAuAAQKf0YABBUACQkeHsUOAIMCABUACAkCHMUOAIMCAAYACAnkHaAVACcCABIAAgnpC8xyAFwAAAAA.Infidel:BAABLgAECn8VAAMXAAkJmAkPHQD3AAAXAAkJmAkPHQD3AAAdAAEJQwFpowAUAAABLgAECgEJAQAFAAAAAA==.',
Ja='Jalincia:BAAALgAECgUJCAAAAA==.Japplen:BAAALgAECgYJDQAAAA==.',
Je='Jeffery:BAAALgAECgMJBwAAAA==.Jemera:BAAALgAECgUJDgAAAA==.Jeraziah:BAAALgADCgYJDQAAAA==.',
Ji='Jinkalou:BAAALgAECgQJBAABLgAECggJGgAHAEQWAA==.Jinn:BAAALgADCgUJBQAAAA==.Jinsun:BAABLgAECn8WAAMCAAYJpxouAwCEAQACAAYJpxouAwCEAQAcAAUJ9giX8QC+AAAAAA==.Jiñ:BAAALgAECgQJCAAAAA==.',
Jo='Jorenson:BAABLgAECn8sAAIcAAkJ1BHlWAC7AQAcAAkJ1BHlWAC7AQAAAA==.',
Ju='Justbeatit:BAAALgADCgQJBAAAAA==.',
['Jï']='Jïñ:BAAALgAECgMJAwAAAA==.',
Ka='Kaether:BAABLgAECn8aAAMGAAkJsgeTMgA/AQAGAAkJsgeTMgA/AQASAAIJmADkaQAkAAAAAA==.Kahlesia:BAAALgADCgkJCQAAAA==.Kahuma:BAAALgAFFAIJAgAAAA==.Kalzdemar:BAACLgAFFH8QAAICAAMJHxeECwDiAAACAAMJHxeECwDiAAAuAAQKfxkAAxwABwlpEoWPAEYBABwABwlVEIWPAEYBAAIABAnHGA0mAKEAAAAA.Karanosliw:BAAALgADCgEJAQAAAA==.Kargg:BAAALgAECgcJDQAAAA==.Kasitus:BAABLgAECn8gAAIcAAkJICI6KQBcAgAcAAkJICI6KQBcAgAAAA==.Kaï:BAAALgADCgIJAgAAAA==.',
Ke='Keldanor:BAAALgAECgYJCwAAAA==.',
Kh='Kheann:BAAALgAECgIJAgAAAA==.Khei:BAAALgADCgIJAgAAAA==.',
Ki='Kickthebaby:BAAALgAECgMJAwAAAA==.Kilometraje:BAABLgAECn8YAAMDAAgJOxL2HQBoAQADAAgJJxH2HQBoAQAcAAYJTwxFHwGFAAAAAA==.Kira:BAAALgAECgIJAgABLgAFFAMJAwAFAAAAAA==.Kissey:BAAALgAECgcJEQAAAA==.Kivi:BAAALgADCgEJAQAAAA==.Kizsy:BAAALgAECgEJAQABLgAECgcJEQAFAAAAAA==.',
Ko='Konjar:BAAALgAECgIJAgAAAA==.Korlat:BAAALgAECgQJBAAAAA==.',
Kr='Kraink:BAAALgADCgEJAQAAAA==.Krayvin:BAAALgADCgIJAgAAAA==.Kringlë:BAAALgAECgYJBgAAAA==.',
Ku='Kundraa:BAAALgADCgIJAgAAAA==.Kungmoofu:BAAALgAECgMJAwABLgAECgYJEwAFAAAAAA==.',
Ky='Kylan:BAAALgAECgEJAQAAAA==.Kyrak:BAAALgAECggJEgAAAA==.',
La='Labiamajorah:BAAALgADCgIJAgAAAA==.Ladiebee:BAAALgAECgUJBgAAAA==.Lainey:BAACLgAFFH8WAAIKAAUJvBkHIQAmAQAKAAUJvBkHIQAmAQAuAAQKfz4AAgoACQlQIIIRAMUCAAoACQlQIIIRAMUCAAAA.Landocamando:BAABLgAECn8tAAIPAAgJvBm+GQAgAgAPAAgJvBm+GQAgAgAAAA==.Larrusbain:BAABLgAECn8nAAIdAAcJGxjHIwDnAQAdAAcJGxjHIwDnAQAAAA==.',
Le='Leafin:BAAALgADCgUJCQABLgAFFAQJCgATACMRAA==.Lehae:BAAALgAECgUJBQAAAA==.Lemonpdcake:BAAALgADCgEJAQAAAA==.Lerya:BAACLgAFFH8HAAMeAAMJIQSTTwCQAAAeAAMJIQSTTwCQAAAUAAEJWwOBEAA4AAAuAAQKfyEAAhQACQnsEmMJAJQBABQACQnsEmMJAJQBAAAA.Lessa:BAAALgAECgEJAQAAAA==.Lesslessa:BAAALgADCgcJBwAAAA==.Levictus:BAAALgAECgEJAQAAAA==.Lexnn:BAABLgAECn8/AAIQAAkJdhTtCgBOAQAQAAkJdhTtCgBOAQAAAA==.Lexonidas:BAAALgADCgEJAgAAAA==.',
Li='Liantelva:BAAALgAECgcJEQAAAA==.Lifepriest:BAAALgAECgMJBAAAAA==.Lifeweaver:BAAALgAECgcJBwAAAA==.Ligetnoone:BAABLgAECn8lAAINAAkJrSZsAAB+AwANAAkJrSZsAAB+AwAAAA==.Lighte:BAABLgAECn86AAIOAAkJ0x09HQCtAgAOAAkJ0x09HQCtAgAAAA==.Lilyith:BAAALgAECgYJDAAAAA==.Lips:BAAALgAECgMJAwAAAA==.',
Lo='Logicx:BAABLgAECn82AAMMAAgJsRnIGAAGAgAMAAgJsRnIGAAGAgAZAAEJqQS7jAARAAAAAA==.Lorin:BAAALgADCgIJAgAAAA==.Lorinne:BAAALgAECgUJBQAAAA==.Lorka:BAAALgAECgIJAgAAAA==.Lorvoldenord:BAAALgADCgIJAgAAAA==.',
Lu='Lumen:BAAALgADCgMJAwAAAA==.Lunarìa:BAAALgADCggJCwAAAA==.',
['Lê']='Lêssa:BAABLgAECn8XAAIKAAgJaw5TEQBkAQAKAAgJaw5TEQBkAQAAAA==.',
Ma='Magici:BAABLgAECn8/AAIOAAkJ/BMREwBEAQAOAAkJ/BMREwBEAQAAAA==.Magnyesis:BAAALgADCgEJAQAAAA==.Mahavailo:BAAALgAECgYJCgAAAA==.Malina:BAAALgAECgEJAQAAAA==.Manimal:BAAALgAECgcJDAAAAA==.Marraud:BAACLgAFFH8FAAMfAAIJmwKABwBHAAAfAAIJmwKABwBHAAATAAIJMgF+LQAzAAAuAAQKfxYAAhMACQm+BFoMAK0AABMACQm+BFoMAK0AAAAA.Mavren:BAAALgAECgcJDwAAAA==.',
Me='Mefisto:BAAALgAECgQJBwABLgAECgYJIwARACkaAA==.Megadruid:BAAALgAECgIJAwAAAA==.Mellesaun:BAABLgAECn9LAAQgAAkJxxb8AQCfAQAgAAkJYxX8AQCfAQAbAAYJfxSCCAApAQAQAAgJGgwOGwCzAAAAAA==.Meloncholy:BAAALgADCgkJGgAAAA==.Mephístø:BAACLgAFFH8GAAIHAAIJRhgKYQCIAAAHAAIJRhgKYQCIAAAuAAQKfxkAAwcABgl3HMJFAJcBAAcABgl3HMJFAJcBABoABAmWF1ZcAM8AAAEuAAUUAwkDAAUAAAAA.Merie:BAAALgADCgYJBwAAAA==.Mewtwo:BAABLgAFFH8SAAIWAAYJxhcpSAA3AQAWAAYJxhcpSAA3AQABLgAFFAkJJQAKAE4kAA==.',
Mi='Micali:BAAALgAECgUJBQAAAA==.Miikeey:BAAALgADCgIJAgAAAA==.Mirei:BAAALgADCggJCQAAAA==.Mithrios:BAAALgAECgYJCwABLgAECgkJDgAFAAAAAA==.',
Mo='Modulation:BAAALgAECgEJAQAAAA==.Moonpope:BAAALgAECgEJAQABLgAFFAUJGAAhACwgAA==.Moonsaw:BAACLgAFFH8YAAIhAAUJLCCtCgB1AQAhAAUJLCCtCgB1AQAuAAQKfy4AAiEACQk8JaIFAPYCACEACQk8JaIFAPYCAAAA.Mordella:BAAALgADCgIJAwAAAA==.Mordëkai:BAAALgAECgEJAgAAAA==.Moriartus:BAAALgAECgEJAQAAAA==.Mosthated:BAAALgADCgIJAgAAAA==.',
Mu='Muffin:BAEALgADCgYJBgABLgAECgkJJAAWAL4eAA==.',
My='Myrling:BAACLgAFFH8GAAIYAAMJlgUiVAB0AAAYAAMJlgUiVAB0AAAuAAQKfyEAAxgACQlBCK5hABABABgACQlBCK5hABABAAwAAQlLAjWlABwAAAAA.Mythrial:BAAALgAECgYJCgAAAA==.',
['Mï']='Mïck:BAAALgAECgEJAQABLgAECgkJGAATAKcEAA==.',
Ne='Nenni:BAAALgADCgYJBgAAAA==.Neph:BAAALgADCgkJCQAAAA==.Newt:BAACLgAFFH8TAAIQAAUJFhKFJgDpAAAQAAUJFhKFJgDpAAAuAAQKfykABBAACQn2GG0rABsCABAACAmkFm0rABsCABsABwmVFqQgALgBACAAAQmvAmI7AB8AAAAA.',
Ni='Nimbus:BAACLgAFFH8dAAIOAAUJqB6yQQBpAQAOAAUJqB6yQQBpAQAuAAQKfy0AAg4ACQnMJOkFAFMDAA4ACQnMJOkFAFMDAAEuAAUUCQlCAB4AQR0A.Ninkasi:BAAALgAECgYJCAABLgAFFAMJBwAcAIIOAA==.Nishikki:BAECLgAFFH8sAAISAAkJ/hktAwBvAgASAAkJ/hktAwBvAgAuAAQKfzwAAhIACQmYIyoDADEDABIACQmYIyoDADEDAAAA.',
No='Nocanno:BAAALgADCgYJBgAAAA==.Nonbearnary:BAAALgAECgcJEgAAAA==.',
Ny='Nydie:BAABLgAECn87AAIXAAkJNBuPKgBXAgAXAAkJNBuPKgBXAgAAAA==.Nymuellyn:BAABLgAECn86AAITAAkJPSQvAgA9AwATAAkJPSQvAgA9AwAAAA==.',
Nz='Nzonah:BAAALgADCgUJBQAAAA==.',
Ot='Ottokurai:BAAALgAECgQJBAAAAA==.',
Pa='Palmanance:BAAALgAECgkJCgAAAA==.Pariahus:BAAALgAECgQJBAABLgAECgkJGwAXABceAA==.',
Pe='Pente:BAAALgADCgEJAQAAAA==.Penumbral:BAAALgAECgYJDwAAAA==.Peterios:BAAALgAFFAIJAgABLgAFFAgJJwAHACIcAA==.',
Ph='Phalst:BAAALgAECgEJBAAAAA==.Phibalan:BAAALgAECgMJBAAAAA==.',
Pi='Pixel:BAAALgAECgIJAwAAAA==.Pixie:BAAALgAECgUJCQAAAA==.Pixil:BAAALgADCgEJAQAAAA==.Pixishot:BAABLgAECn8fAAIKAAkJewxwdABWAQAKAAkJewxwdABWAQAAAA==.',
Pr='Pradigy:BAACLgAFFH8GAAMDAAMJOwhLKAA4AAAcAAIJ7QGJCAFQAAADAAEJ2BRLKAA4AAAuAAQKfx0AAwMABgl6FSIzAM8AABwABgnFD+HCAPoAAAMAAwluFyIzAM8AAAAA.Prestolight:BAAALgAECgEJAgABLgAECgkJIwADAN4gAA==.Proofing:BAAALgAECgQJBAAAAA==.',
Pu='Pubba:BAAALgAECgYJEwAAAA==.Pubbamorn:BAAALgAECggJEwABLgAECgYJEwAFAAAAAA==.Pubismaximus:BAAALgAECgIJAgABLgAECgYJEwAFAAAAAA==.',
Pw='Pwincess:BAABLgAECn8yAAMCAAkJ7g8+BABMAQACAAkJ7g8+BABMAQAcAAkJcQT8mQA1AQAAAA==.',
Ra='Radiator:BAAALgAECgEJAQAAAA==.Raelyndria:BAABLgAECn8aAAMSAAkJuRiPIwCsAQASAAgJvBePIwCsAQAVAAYJ0BojKABVAQAAAA==.Raengurth:BAAALgAECgYJBwAAAA==.Raenraug:BAAALgADCgMJAwAAAA==.Raidiance:BAAALgADCgYJBgAAAA==.Rakkali:BAAALgAFFAEJAQAAAA==.Rancavus:BAAALgADCgMJAwAAAA==.Rastakehn:BAAALgADCgYJBgAAAA==.Ratraxx:BAAALgADCgYJBgABLgAECggJGgAHAEQWAA==.Razaller:BAABLgAECn8UAAMeAAkJiQ6CKgBrAQAeAAkJiQ6CKgBrAQAUAAEJFgE+RgAbAAAAAA==.',
Rc='Rctraxx:BAAALgAECgYJBwABLgAECggJGgAHAEQWAA==.',
Re='Realpro:BAAALgAECgQJBAAAAA==.Redrogue:BAABLgAECn9LAAIiAAkJGRAMDQBuAQAiAAkJGRAMDQBuAQAAAA==.Revela:BAAALgADCgcJDQAAAA==.',
Ri='Riftan:BAACLgAFFH8gAAMcAAUJQRmUMAARAQAcAAUJQRmUMAARAQACAAEJuQOCKwA7AAAuAAQKfzQAAhwACQmXHvIaANwCABwACQmXHvIaANwCAAAA.Rightousnes:BAAALgADCgcJCQAAAA==.Riviee:BAABLgAECn8iAAIPAAkJ+gd0RgAsAQAPAAkJ+gd0RgAsAQAAAA==.',
Ro='Rogun:BAABLgAECn9hAAILAAkJRxUXAQAYAgALAAkJRxUXAQAYAgAAAA==.Roredge:BAAALgAECgEJAQABLgAECggJGgAHAEQWAA==.Rosealie:BAAALgADCgMJAwAAAA==.',
Ry='Rycbar:BAAALgADCgkJCQAAAA==.Rynthanuu:BAAALgADCgEJAQAAAA==.',
Sa='Sarann:BAAALgAECgQJCgAAAA==.Sassbringer:BAAALgAECgUJCgAAAA==.Satele:BAAALgAECgcJEwAAAA==.Saty:BAABLgAFFH8tAAMOAAkJ2R/+AwDpAgAOAAkJ/B7+AwDpAgAjAAYJFxwaAQC1AQABLgAFFAkJKAAiAK8gAA==.Sauce:BAAALgADCgMJAwAAAA==.',
Sc='Scarypoppins:BAABLgAECn8jAAIDAAkJ3iCVBgC3AgADAAkJ3iCVBgC3AgAAAA==.',
Se='Seloki:BAAALgADCgQJBAAAAA==.Senia:BAABLgAECn8WAAMWAAkJIQjJEgDjAAAWAAgJcQjJEgDjAAAEAAcJ8ALXHACLAAAAAA==.Seniortank:BAAALgADCgEJAQAAAA==.Serracha:BAAALgAECgYJDAABLgAFFAMJCgAIAOMLAA==.Serraz:BAAALgAECgMJBgABLgAFFAMJCgAIAOMLAA==.Serrbear:BAAALgAECgcJCAAAAA==.Seònaid:BAAALgAFFAIJBAABLgAFFAMJBAAFAAAAAA==.',
Sh='Shadowkaizen:BAAALgADCgEJAQAAAA==.Shambullance:BAAALgAFFAEJAgABLgAECgYJDQAFAAAAAA==.Shammywaddle:BAABLgAECn8ZAAMHAAgJAyDzIQATAgAHAAYJ4CHzIQATAgAaAAgJnRBxNABpAQAAAA==.Shamtraxx:BAABLgAECn8aAAMHAAgJRBb5LwDIAQAHAAcJPBb5LwDIAQAaAAcJTw1zRgAvAQAAAA==.Sheraania:BAAALgADCgcJCAAAAA==.',
Si='Sinistress:BAAALgADCgcJCwAAAA==.',
Sk='Skorpius:BAABLgAECn8mAAIWAAkJDwraEAD7AAAWAAkJDwraEAD7AAAAAA==.Skumi:BAAALgAECgUJCwAAAA==.',
Sl='Slaytanic:BAABLgAECn9GAAIXAAkJxx0sLABQAgAXAAkJxx0sLABQAgAAAA==.Sleepyholow:BAAALgADCgEJAQAAAA==.Slymick:BAABLgAECn8YAAITAAkJpwTyMQAUAQATAAkJpwTyMQAUAQAAAA==.',
Sn='Snoka:BAAALgAECgkJEwAAAA==.',
So='Solora:BAABLgAECn9LAAIaAAkJ8AszDgDnAAAaAAkJ8AszDgDnAAAAAA==.Soluna:BAABLgAECn9EAAIXAAkJ2hdLCQDhAQAXAAkJ2hdLCQDhAQAAAA==.',
Sp='Sparrowrain:BAAALgAECgUJBQAAAA==.',
St='Stiflerd:BAAALgADCgEJAQAAAA==.Stinkie:BAAALgADCgkJCQAAAA==.Strawry:BAAALgAECgQJCwAAAA==.Stuffedbear:BAABLgAECn8UAAIMAAYJBQU2XwCbAAAMAAYJBQU2XwCbAAAAAA==.',
Su='Subiegrl:BAAALgAECgQJBAAAAA==.Sunjiwung:BAAALgAECgQJBAAAAA==.Supadin:BAAALgAECgIJAwAAAA==.Supawild:BAAALgADCgEJAQAAAA==.Supernano:BAAALgAECgUJBQAAAA==.',
Sv='Svyra:BAAALgADCgEJAQAAAA==.',
Sw='Swans:BAABLgAECn8UAAIGAAkJewhPCQAiAQAGAAkJewhPCQAiAQAAAA==.Swll:BAAALgAECgYJDQAAAA==.',
Sy='Sylanann:BAAALgADCgMJAwAAAA==.Syrüs:BAACLgAFFH8XAAIbAAcJFhNZDgAzAQAbAAcJFhNZDgAzAQAuAAQKfysAAhsACQlqIk4FAO0CABsACQlqIk4FAO0CAAAA.',
['Sã']='Sãrik:BAABLgAECn8eAAIXAAcJYhawEQBZAQAXAAcJYhawEQBZAQAAAA==.',
['Sí']='Sílver:BAABLgAECn8kAAIaAAgJphASPABFAQAaAAgJphASPABFAQAAAA==.',
Ta='Taebeck:BAAALgADCgQJBAAAAA==.Tasty:BAAALgADCgYJBgABLgAECgkJKAABAPoiAA==.',
Te='Telamon:BAAALgADCgkJEAAAAA==.Teokojin:BAAALgAECgMJAwAAAA==.Tethyssra:BAAALgAECgMJAwAAAA==.',
Th='Thalyra:BAABLgAFFH8HAAIQAAMJCBZhWgDhAAAQAAMJCBZhWgDhAAAAAA==.Thantinhal:BAAALgADCgQJBQAAAA==.Thestar:BAAALgADCgEJAQAAAA==.Thingthwee:BAAALgADCgMJAwAAAA==.Thirstrap:BAABLgAECn8zAAIbAAkJ/BblAgAgAgAbAAkJ/BblAgAgAgAAAA==.Thorge:BAABLgAECn82AAIBAAkJkBpaAQBcAgABAAkJkBpaAQBcAgAAAA==.Thyrus:BAAALgADCgQJBAAAAA==.Thíngtwo:BAAALgAECgQJDAAAAA==.',
Ti='Tiltawhirl:BAAALgAECgMJAwAAAA==.Tips:BAAALgADCgQJBAAAAA==.Tiscus:BAAALgADCggJCAAAAA==.',
To='Tokesmasmoke:BAAALgAECgMJAwAAAA==.Toragos:BAAALgADCgQJBAAAAA==.',
Tr='Träshley:BAAALgAECgYJEwAAAA==.',
Tu='Turtlestraza:BAAALgAECgEJAQAAAA==.',
Uk='Uknak:BAAALgAECgQJBwAAAA==.',
Ul='Ulanui:BAAALgADCgMJAwAAAA==.',
Un='Unnserra:BAAALgAECgUJBwABLgAFFAIJAgAFAAAAAA==.Unrêstrained:BAAALgADCgQJBAAAAA==.',
Ur='Urma:BAAALgAECgQJBQAAAA==.',
Va='Vaediirn:BAAALgADCgQJBAAAAA==.Vallcore:BAAALgADCgUJBgAAAA==.',
Ve='Vennt:BAACLgAFFH8FAAIKAAUJVw/GQgAoAQAKAAUJVw/GQgAoAQAuAAQKfyEAAwoACAlhFwZVAKUBAAsACAktEWgnAO4BAAoABgnJHQZVAKUBAAEuAAUUCAkgABoAQRMA.Ventt:BAACLgAFFH8gAAIaAAgJQRPGEACjAQAaAAgJQRPGEACjAQAuAAQKfzEAAhoACQkjI7oGAPACABoACQkjI7oGAPACAAAA.Veredelyse:BAAALgAECgYJCwABLgAFFAIJAgAFAAAAAA==.',
Vi='Vindicatez:BAAALgAECgIJAgAAAA==.',
Vo='Volstaag:BAAALgAECgEJBwAAAA==.Voluus:BAABLgAECn8WAAIaAAcJHA3aSwAFAQAaAAcJHA3aSwAFAQAAAA==.',
Vr='Vrorag:BAAALgAECgcJEwAAAA==.',
Wa='Walfar:BAABLgAECn8jAAIRAAYJKRoaFwBoAQARAAYJKRoaFwBoAQAAAA==.Wallbanger:BAAALgAFFAMJAwAAAA==.Walterlight:BAAALgADCgcJCwAAAA==.Warbuckss:BAAALgAFFAEJAgABLgAFFAMJBgADADsIAA==.Warbucksthe:BAAALgAECgEJAgABLgAFFAMJBgADADsIAA==.Warbud:BAAALgAECgEJAQAAAA==.Wayme:BAABLgAECn8kAAIiAAkJpBChDwBGAQAiAAkJpBChDwBGAQAAAA==.',
We='Wendorf:BAAALgADCgkJDgAAAA==.',
Wh='Whispyr:BAAALgADCgcJCAAAAA==.Whiteclaw:BAAALgAECgMJBgAAAA==.',
Wi='Wizzlord:BAAALgAECgYJCwAAAA==.',
Wo='Wooster:BAAALgAECgIJAwAAAA==.',
Wr='Writhshammy:BAAALgAECgQJCAAAAA==.',
Xa='Xaeru:BAAALgAECgEJAgAAAA==.Xahle:BAABLgAECn8cAAIcAAkJpBLoTwDTAQAcAAkJpBLoTwDTAQAAAA==.Xanado:BAAALgADCgEJAQAAAA==.',
Xe='Xenophilius:BAAALgADCgIJAgAAAA==.',
Xs='Xsanguinate:BAAALgAECgQJBAAAAA==.',
Ya='Yarikh:BAAALgAECgEJAQAAAA==.',
Za='Zadkiel:BAAALgAFFAEJAQAAAA==.',
Ze='Zekkhira:BAAALgAECgUJCAABLgAFFAQJCgATACMRAA==.Zendayah:BAAALgADCgMJAwAAAA==.Zeparu:BAACLgAFFH8HAAIcAAMJgg6QYgCUAAAcAAMJgg6QYgCUAAAuAAQKfy8AAxwACQnMHVMUAM4CABwACQnMHVMUAM4CAAIAAQlzEiY5ADgAAAAA.Zero:BAAALgAECgUJBwABLgAECgkJHwAJAEkWAA==.',
Zi='Zinkgirl:BAAALgADCgUJBQAAAA==.Zitillidan:BAAALgAFFAEJAQABLgAFFAMJEAACAB8XAA==.',
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
