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

local lookup = {'Hunter-Survival','DeathKnight-Blood','Warlock-Affliction','Unknown-Unknown','Priest-Holy','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Warrior-Protection','Mage-Frost','Warrior-Fury','DemonHunter-Devourer','Paladin-Protection','Warlock-Destruction','Rogue-Subtlety','Evoker-Devastation','Priest-Shadow','Priest-Discipline','Warlock-Demonology','Paladin-Retribution','Druid-Restoration','Shaman-Elemental','DemonHunter-Havoc','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Holy','Evoker-Augmentation','Druid-Guardian','DemonHunter-Vengeance','Monk-Windwalker','Rogue-Outlaw',}
local provider = {region='US',realm='Uldaman',name='US',type='weekly',zone=46,date='2026-06-14',data={Ad='Ademar:BAABLgAECn8nAAIBAAcJ3hW6IACXAQABAAcJ3hW6IACXAQAAAA==.',
Ae='Aenora:BAAALgAECgMJAwAAAA==.',
Ag='Aggrothief:BAAALgAECgUJCQAAAA==.Agrius:BAAALgAECgYJDAAAAA==.',
Ai='Ainokeas:BAAALgAECgIJAgAAAA==.',
Ak='Akurumira:BAAALgAECgEJAQAAAA==.',
Al='Alexändros:BAAALgADCgUJCAAAAA==.Alkie:BAAALgAECgUJCAAAAA==.Allectra:BAAALgAECgYJDwAAAA==.Allupinya:BAAALgAECgUJBwABLgAECgkJIwACAN4gAA==.',
Am='Amnon:BAABLgAECn89AAIDAAkJQSBaAgCvAgADAAkJQSBaAgCvAgAAAA==.',
Ar='Arelliea:BAAALgADCgEJAQABLgAFFAEJAQAEAAAAAA==.Arlessa:BAAALgAECgQJBAABLgAECgkJQQAFAC8hAA==.',
As='Asaelis:BAAALgAECgYJDQAAAA==.Astauren:BAAALgADCgMJBAAAAA==.Astralflame:BAAALgADCgYJCAAAAA==.',
Au='Augwaddles:BAAALgAECgUJBwABLgAECggJGQAGAAMgAA==.Aurius:BAAALgAECgUJCgABLgAFFAIJCAAHAA8PAA==.',
Av='Avataraang:BAAALgADCgEJAQAAAA==.Avramora:BAAALgAECgUJDAABLgAFFAEJAQAEAAAAAA==.',
Ax='Axila:BAAALgAECgIJAwAAAA==.',
Az='Azdaja:BAACLgAFFH8IAAIHAAIJDw+vRQCFAAAHAAIJDw+vRQCFAAAuAAQKfy0AAwcACQm5D2IeALEBAAcACQm5D2IeALEBAAgAAQntAPx3AA8AAAAA.Azgardia:BAAALgAECgYJCAAAAA==.Azryiel:BAAALgAECgcJEAABLgAFFAIJCAAHAA8PAA==.Azulå:BAACLgAFFH8IAAIJAAUJVgk7SwAQAQAJAAUJVgk7SwAQAQAuAAQKfyEAAwkACQnoE8UvABoCAAkACQnoE8UvABoCAAoAAQmuA0xFAB0AAAAA.',
Ba='Bach:BAABLgAFFH8XAAILAAUJNyMcEwB/AQALAAUJNyMcEwB/AQAAAA==.Balloffur:BAABLgAECn8cAAIMAAkJIA6OGgBiAQAMAAkJIA6OGgBiAQAAAA==.Bamboostixx:BAABLgAECn8qAAINAAkJnhFOTQDxAQANAAkJnhFOTQDxAQAAAA==.',
Be='Bellachai:BAAALgAECgEJAQAAAA==.Bellgirls:BAAALgAECgMJAwAAAA==.Belnetukent:BAAALgADCgEJAQAAAA==.Berastu:BAACLgAFFH8HAAIOAAMJ1ghSOgDDAAAOAAMJ1ghSOgDDAAAuAAQKfyEAAg4ACQmjFEImAMYBAA4ACQmjFEImAMYBAAAA.Berastú:BAAALgAECgYJEQAAAA==.',
Bl='Blackbear:BAAALgAECgMJAwABLgADCgEJAQAEAAAAAA==.Bleufromage:BAAALgADCggJCwAAAA==.Bloodlusst:BAAALgAECgMJBAAAAA==.Bloodraina:BAAALgADCgYJBgAAAA==.',
Bm='Bmm:BAAALgAFFAEJAQAAAA==.',
Bo='Bonechill:BAAALgADCgYJDAAAAA==.Boogyboo:BAAALgADCgEJAQAAAA==.Booz:BAABLgAECn8wAAIPAAkJyRuGGwBtAgAPAAkJyRuGGwBtAgAAAA==.Bors:BAABLgAECn8fAAMJAAkJQxmiCQD8AgAJAAkJQxmiCQD8AgAKAAUJARHRUgABAQAAAA==.Botch:BAAALgAECgYJBgAAAA==.Bowdacious:BAAALgAECgEJAwABLgAECgkJIwACAN4gAA==.',
Bu='Bubbleõseven:BAAALgADCggJDwAAAA==.Bugabooed:BAAALgADCgkJGgAAAA==.Bunnystalker:BAAALgADCgYJBwAAAA==.',
Ca='Callee:BAABLgAECn8rAAIJAAgJXg3YZQB1AQAJAAgJXg3YZQB1AQAAAA==.Calyse:BAABLgAECn8dAAIQAAcJISHICwAGAgAQAAcJISHICwAGAgAAAA==.Casblind:BAACLgAFFH8jAAIPAAgJQRrHDgA2AgAPAAgJQRrHDgA2AgAuAAQKfyAAAg8ACQk6IHsQAPoCAA8ACQk6IHsQAPoCAAAA.Casima:BAABLgAECn8bAAIJAAkJVRBKOQD2AQAJAAkJVRBKOQD2AQAAAA==.',
Ch='Chandani:BAAALgAECgcJCgAAAA==.Chesterblat:BAAALgADCgIJAgAAAA==.Cheydinhal:BAABLgAECn9MAAIFAAgJTRq1EQBQAgAFAAgJTRq1EQBQAgAAAA==.Cheydinhil:BAAALgADCgcJDAAAAA==.Chicknwaffle:BAAALgAECgQJCwAAAA==.Chocó:BAAALgADCgEJAQAAAA==.Chumlee:BAABLgAECn8sAAIHAAgJQRk1GADkAQAHAAgJQRk1GADkAQAAAA==.Chunks:BAAALgAECgIJAgAAAA==.',
Ci='Ciri:BAAALgAECgEJAQAAAA==.',
Co='Colleague:BAAALgAECgYJEQAAAA==.Cornmoon:BAAALgADCgcJCQAAAA==.',
Cr='Crank:BAAALgAFFAMJAwABLgAFFAkJIQARAK8gAA==.Crewgy:BAAALgADCgEJAQAAAA==.',
Da='Dalanorea:BAAALgAECgYJBgAAAA==.Dandorn:BAAALgADCgIJAgAAAA==.Darkocean:BAAALgADCgEJAQAAAA==.Darksushi:BAAALgAECgYJEAAAAA==.Daylate:BAAALgADCgUJBQAAAA==.',
De='Deadlyhealer:BAAALgAECgYJCwAAAA==.',
Dh='Dhabyss:BAAALgADCggJCAABLgAECgkJNgASAD0kAA==.',
Di='Diménsional:BAABLgAECn8fAAIHAAgJLhC6KwBZAQAHAAgJLhC6KwBZAQAAAA==.Dinbek:BAAALgAECgcJEwAAAA==.Dindino:BAAALgAECgEJAQAAAA==.Dindroc:BAAALgAECgYJCAAAAA==.Dingread:BAAALgAECgYJBgAAAA==.',
Dr='Dragin:BAABLgAECn8qAAITAAgJvAgoDgAmAQATAAgJvAgoDgAmAQAAAA==.Dreyla:BAAALgADCgQJCAAAAA==.Drunkmcmonk:BAAALgADCgMJBgAAAA==.',
Du='Duronimo:BAAALgAECgUJBgAAAA==.Dusksurge:BAAALgADCgIJAgAAAA==.',
['Dÿ']='Dÿmmensional:BAAALgAFFAIJAgAAAA==.',
Ec='Eclipze:BAACLgAFFH8VAAMUAAUJ4QvCHQD/AAAUAAUJ4QvCHQD/AAAVAAIJgAIJSwA8AAAuAAQKfyMABBQACQmqGOcXAAgCABQACQmqGOcXAAgCABUAAQkoB9hbACsAAAUAAQnmARyKACIAAAAA.Eclipzee:BAAALgADCgMJAwABLgAFFAUJFQAUAOELAA==.Eclipzé:BAABLgAECn8cAAMDAAkJNxkfEgBCAQADAAYJPBgfEgBCAQAWAAYJMhFblwAPAQABLgAFFAUJFQAUAOELAA==.Eclípze:BAAALgAECgIJAgABLgAFFAUJFQAUAOELAA==.',
Ei='Eifel:BAAALgAECgcJEgABLgAECgkJGwAXABceAA==.',
El='Elessardan:BAACLgAFFH8GAAIYAAMJzxJ1PAC6AAAYAAMJzxJ1PAC6AAAuAAQKfy0AAxgACQmaHpIJAB8DABgACQmaHpIJAB8DAAsAAgleEbJrAHEAAAAA.Ellynara:BAAALgAECgQJBAABLgAECgkJJgABAFEYAA==.Elothien:BAAALgAECgEJAwABLgAFFAMJBgAYAM8SAA==.Elvaca:BAAALgAECgUJBQAAAA==.',
En='Endilli:BAABLgAECn8cAAIZAAYJLAdbYwC4AAAZAAYJLAdbYwC4AAAAAA==.',
Eq='Equinoxis:BAEALgAECgYJCwABLgAFFAgJJQAUAKQZAA==.',
Et='Eternal:BAABLgAFFH8GAAIXAAQJXg33UQAHAQAXAAQJXg33UQAHAQAAAA==.',
Ev='Evaki:BAAALgADCgEJAgAAAA==.',
Ez='Ezekiel:BAAALgAECgEJAQAAAA==.',
Fa='Faein:BAAALgADCgIJAgAAAA==.Fallynangel:BAACLgAFFH8GAAISAAQJIxH8GgA9AQASAAQJIxH8GgA9AQAuAAQKf0YAAhIACQmbFrsSAA0CABIACQmbFrsSAA0CAAAA.',
Fe='Fealeen:BAAALgAECgEJAQAAAA==.Fearlock:BAAALgADCgUJCAAAAA==.Felrafram:BAAALgADCgQJAwAAAA==.Fenyx:BAACLgAFFH8IAAIHAAMJlQqROwC1AAAHAAMJlQqROwC1AAAuAAQKf1AAAgcACQmAF/UQADECAAcACQmAF/UQADECAAEuAAUUBAkXAAwAvxgA.',
Fi='Fightnyte:BAAALgAECgUJBQABLgAECgkJKwAWAFUaAQ==.Filho:BAABLgAECn8eAAMJAAgJZxEwYgB+AQAJAAgJZxEwYgB+AQAKAAIJqALDgABEAAAAAA==.',
Fo='Foth:BAAALgAECgQJBQAAAA==.',
Fr='Friedtips:BAAALgADCgQJBgABLgAFFAQJEwAaABEZAA==.Frostwaffle:BAAALgADCgYJBgABLgAECgQJCwAEAAAAAA==.Frumpy:BAAALgAECgEJAQABLgAECgcJEAAEAAAAAA==.',
Ga='Gabe:BAAALgAECgYJDQAAAA==.Galvek:BAACLgAFFH8SAAQBAAYJeRWCCACGAQABAAYJeRWCCACGAQAJAAIJawsxigCDAAAKAAEJnwNuLABBAAAuAAQKfycABAEACQm+HRUQADACAAEACAmUHhUQADACAAkABgkOHbFBAKkBAAoABgmhEGM9AGgBAAAA.Garjzlaa:BAAALgAECgYJBwAAAA==.Garugamesh:BAAALgADCgcJDgAAAA==.Gas:BAAALgAECgEJAQABLgAFFAMJAwAEAAAAAA==.',
Gi='Gigglebytes:BAAALgAECgIJAQAAAA==.',
Gn='Gnowen:BAAALgADCgkJEgABLgAECgYJHQAQACkaAA==.',
Go='Gojira:BAAALgADCgIJAgAAAA==.',
Gr='Greyswandir:BAABLgAECn8hAAIJAAcJDA+WcgBXAQAJAAcJDA+WcgBXAQAAAA==.Gryssli:BAAALgADCgIJAgAAAA==.',
Gu='Gulatz:BAAALgAECgcJCgAAAA==.',
Gw='Gwarr:BAAALgAECgYJDAAAAA==.',
Ha='Harandufu:BAAALgAECgQJBQAAAA==.Hardwön:BAAALgAECgMJAwAAAA==.Harvie:BAAALgADCgYJDAABLgAECgcJIQAJAAwPAA==.Hatani:BAAALgAECgEJAQABLgAECgYJDAAEAAAAAA==.Haylee:BAAALgADCgkJEwAAAA==.',
He='Healingfoxy:BAAALgAECgcJDgAAAA==.Hemofluffin:BAAALgAECgIJAgABLgAFFAUJFwAbACAXAA==.',
Hu='Husky:BAAALgAECggJEgAAAA==.',
Ic='Icyfurball:BAAALgAECgIJAgABLgAECgkJHwAMAK0mAA==.',
Ik='Ikillyounows:BAAALgAECgQJBAAAAA==.',
Il='Ilovesanta:BAAALgAECgYJDQAAAA==.',
In='Indigobleue:BAABLgAECn9DAAQVAAkJHh6NDgCFAgAVAAgJAhyNDgCFAgAFAAgJ5B1pFQAnAgAUAAIJ6QtvcABfAAAAAA==.Infidel:BAAALgAECgUJCAABLgADCgEJAQAEAAAAAA==.',
Ja='Jalincia:BAAALgAECgUJCAAAAA==.Japplen:BAAALgAECgYJDQAAAA==.',
Je='Jeffery:BAAALgADCgUJDAAAAA==.Jemera:BAAALgADCgUJBQAAAA==.Jeraziah:BAAALgADCgYJDQAAAA==.',
Ji='Jinkalou:BAAALgAECgQJBAABLgAECggJGgAGAEQWAA==.Jinn:BAAALgADCgUJBQAAAA==.Jinsun:BAAALgAECgUJDQAAAA==.Jiñ:BAAALgAECgQJCAAAAA==.',
Jo='Jorenson:BAABLgAECn8sAAIbAAkJ1BFmVwC9AQAbAAkJ1BFmVwC9AQAAAA==.',
Ju='Justbeatit:BAAALgADCgQJBAAAAA==.',
['Jï']='Jïñ:BAAALgADCgUJBQAAAA==.',
Ka='Kaether:BAABLgAECn8aAAMFAAkJsgcFMgA/AQAFAAkJsgcFMgA/AQAUAAIJmADkaQAkAAAAAA==.Kahlesia:BAAALgADCgkJCQAAAA==.Kalzdemar:BAABLgAECn8ZAAMbAAcJaRJtjQBIAQAbAAcJVRBtjQBIAQAcAAQJxxiOJQChAAABLgAECgcJJwABAN4VAA==.Kasitus:BAABLgAECn8eAAIbAAgJJSTGKABdAgAbAAgJJSTGKABdAgAAAA==.',
Ke='Keldanor:BAAALgAECgEJAQAAAA==.',
Kh='Khei:BAAALgADCgIJAgAAAA==.',
Ki='Kickthebaby:BAAALgADCgcJEQAAAA==.Kilometraje:BAABLgAECn8YAAMCAAgJOxKLHQBqAQACAAgJJxGLHQBqAQAbAAYJTwx2HAGFAAAAAA==.Kira:BAAALgAECgIJAgABLgAFFAMJAwAEAAAAAA==.Kissey:BAAALgAECgYJDAAAAA==.Kivi:BAAALgADCgEJAQAAAA==.',
Ko='Korlat:BAAALgADCgcJBwAAAA==.Korneliuz:BAACLgAFFH8GAAIGAAIJRhjXXgCIAAAGAAIJRhjXXgCIAAAuAAQKfxkAAwYABgl3HPJEAJcBAAYABgl3HPJEAJcBABkABAmWF2RbAM8AAAAA.',
Kr='Kraink:BAAALgADCgEJAQAAAA==.Krayvin:BAAALgADCgIJAgAAAA==.Kringlë:BAAALgAECgYJBgAAAA==.',
Ku='Kungmoofu:BAAALgAECgMJAwABLgAECgcJEAAEAAAAAA==.',
Ky='Kylan:BAAALgAECgEJAQAAAA==.Kyrak:BAAALgAECgYJDwAAAA==.',
La='Labiamajorah:BAAALgADCgIJAgAAAA==.Ladiebee:BAAALgAECgEJAQAAAA==.Lainey:BAACLgAFFH8MAAIJAAQJvBnNMwBBAQAJAAQJvBnNMwBBAQAuAAQKfz0AAgkACQlQIAsRAMYCAAkACQlQIAsRAMYCAAAA.Landocamando:BAABLgAECn8rAAIOAAgJRxl3GQAhAgAOAAgJRxl3GQAhAgAAAA==.Larrusbain:BAABLgAECn8nAAIdAAcJGxh4IwDoAQAdAAcJGxh4IwDoAQAAAA==.',
Le='Leafin:BAAALgADCgUJCQABLgAFFAQJBgASACMRAA==.Lerya:BAACLgAFFH8HAAMeAAMJIQTjTQCQAAAeAAMJIQTjTQCQAAATAAEJWwMtEAA4AAAuAAQKfyEAAhMACQnsEkoJAJQBABMACQnsEkoJAJQBAAAA.Levictus:BAAALgAECgEJAQAAAA==.Lexnn:BAABLgAECn84AAIPAAkJLBM8OQDfAQAPAAkJLBM8OQDfAQAAAA==.Lexonidas:BAAALgADCgEJAgAAAA==.',
Li='Liantelva:BAAALgAECgcJEQAAAA==.Lifepriest:BAAALgAECgEJAQAAAA==.Ligetnoone:BAABLgAECn8fAAIMAAkJrSZmAAB+AwAMAAkJrSZmAAB+AwAAAA==.Lighte:BAABLgAECn86AAINAAkJ0x24HACtAgANAAkJ0x24HACtAgAAAA==.Lilyith:BAAALgAECgYJDAAAAA==.Lips:BAAALgAECgMJAwAAAA==.',
Lo='Logicx:BAABLgAECn82AAMLAAgJsRmEGAAGAgALAAgJsRmEGAAGAgAfAAEJqQShiQARAAAAAA==.Lorka:BAAALgAECgIJAgAAAA==.Lorvoldenord:BAAALgADCgIJAgAAAA==.',
Lu='Lunarìa:BAAALgADCggJCwAAAA==.',
['Lê']='Lêssa:BAAALgAECgQJBQAAAA==.',
Ma='Magici:BAABLgAECn84AAINAAkJiw+WWgDLAQANAAkJiw+WWgDLAQAAAA==.Magnyesis:BAAALgADCgEJAQAAAA==.Mahavailo:BAAALgAECgUJBQAAAA==.Malina:BAAALgAECgEJAQAAAA==.Manimal:BAAALgAECgcJDAAAAA==.Marraud:BAAALgAECgcJEQAAAA==.Mavren:BAAALgAECgUJDAAAAA==.',
Me='Mefisto:BAAALgAECgQJBwABLgAECgYJHQAQACkaAA==.Megadruid:BAAALgAECgIJAwAAAA==.Mellesaun:BAABLgAECn82AAQgAAkJKw0EDgBuAQAgAAkJKw0EDgBuAQAPAAYJIwayvgCrAAAaAAQJkgVqWwBzAAAAAA==.Meloncholy:BAAALgADCgkJCQAAAA==.Merie:BAAALgADCgYJBwAAAA==.Mewtwo:BAABLgAFFH8RAAIWAAUJVBl9RgA4AQAWAAUJVBl9RgA4AQABLgAFFAgJFwAeAGAUAA==.',
Mi='Miikeey:BAAALgADCgIJAgAAAA==.Mirei:BAAALgADCggJCQAAAA==.Mithrios:BAAALgAECgUJBQABLgAECgkJCAAEAAAAAA==.',
Mo='Moonsaw:BAACLgAFFH8KAAIhAAQJkR8JCwBtAQAhAAQJkR8JCwBtAQAuAAQKfykAAiEACAlXJYEFAPcCACEACAlXJYEFAPcCAAAA.Mordella:BAAALgADCgIJAwAAAA==.Moriartus:BAAALgADCgEJAQAAAA==.Mosthated:BAAALgADCgIJAgAAAA==.',
Mu='Muffin:BAEALgADCgYJBgABLgAECgYJHwAWAGwiAA==.',
My='Myrling:BAACLgAFFH8GAAIYAAMJlgW6UgB0AAAYAAMJlgW6UgB0AAAuAAQKfyAAAxgACAlOCBxhABABABgACAlOCBxhABABAAsAAQlLAiqjABwAAAAA.Mythrial:BAAALgAECgYJCgAAAA==.',
Ne='Nenni:BAAALgADCgYJBgAAAA==.Neph:BAAALgADCgkJCQAAAA==.Newt:BAACLgAFFH8MAAIPAAQJnwvBUQD0AAAPAAQJnwvBUQD0AAAuAAQKfykABA8ACQn2GPYqABsCAA8ACAmkFvYqABsCABoABwmVFqQgALgBACAAAQmvAn86AB8AAAAA.',
Ni='Nimbus:BAACLgAFFH8dAAINAAUJqB6oQABuAQANAAUJqB6oQABuAQAuAAQKfy0AAg0ACQnMJKwFAFQDAA0ACQnMJKwFAFQDAAEuAAUUCAkoAB4A8hsA.Ninkasi:BAAALgAECgYJBwAAAA==.Nishikki:BAECLgAFFH8lAAIUAAgJpBnrAwBMAgAUAAgJpBnrAwBMAgAuAAQKfzwAAhQACQmYIxADADQDABQACQmYIxADADQDAAAA.',
No='Nocanno:BAAALgADCgYJBgAAAA==.Nonbearnary:BAAALgAECgcJDAAAAA==.',
Ny='Nydie:BAABLgAECn87AAIXAAkJNBuVKQBaAgAXAAkJNBuVKQBaAgAAAA==.Nymuellyn:BAABLgAECn82AAISAAkJPSQdAgA+AwASAAkJPSQdAgA+AwAAAA==.',
Nz='Nzonah:BAAALgADCgEJAQAAAA==.',
Ot='Ottokurai:BAAALgAECgQJBAAAAA==.',
Pa='Palmanance:BAAALgAECgkJCgAAAA==.Pariahus:BAAALgAECgQJBAABLgAECgkJGwAXABceAA==.',
Pe='Penumbral:BAAALgAECgYJDwAAAA==.',
Ph='Phalst:BAAALgAECgEJAgAAAA==.Phibalan:BAAALgAECgMJBAAAAA==.',
Pi='Pixel:BAAALgAECgIJAwAAAA==.Pixie:BAAALgAECgUJCQAAAA==.Pixil:BAAALgADCgEJAQAAAA==.Pixishot:BAABLgAECn8cAAIJAAgJ2QsGcwBWAQAJAAgJ2QsGcwBWAQAAAA==.',
Pr='Pradigy:BAABLgAECn8dAAMbAAYJehUGwAD8AAAbAAYJxQ8GwAD8AAACAAMJbhe3MgDPAAAAAA==.Prestolight:BAAALgAECgEJAQABLgAECgkJIwACAN4gAA==.Proofing:BAAALgAECgQJBAAAAA==.',
Pu='Pubba:BAAALgAECgcJEAAAAA==.Pubbamoo:BAAALgAECgUJCwAAAA==.Pubismaximus:BAAALgAECgIJAgABLgAECgcJEAAEAAAAAA==.',
Pw='Pwincess:BAABLgAECn8nAAMcAAkJvw3vDAClAQAcAAkJvw3vDAClAQAbAAkJcQTwlwA3AQAAAA==.',
Ra='Raelyndria:BAABLgAECn8ZAAMUAAkJuRgmIwCvAQAUAAgJvBcmIwCvAQAVAAYJ0BojKABVAQAAAA==.Raengurth:BAAALgAECgYJBwAAAA==.Raenraug:BAAALgADCgMJAwAAAA==.Raidiance:BAAALgADCgYJBgAAAA==.Rakkali:BAAALgAFFAEJAQAAAA==.Rancavus:BAAALgADCgMJAwAAAA==.Rastakehn:BAAALgADCgYJBgAAAA==.Ratraxx:BAAALgADCgYJBgABLgAECggJGgAGAEQWAA==.Razaller:BAABLgAECn8UAAMeAAkJiQ6CKgBrAQAeAAkJiQ6CKgBrAQATAAEJFgE+RgAbAAAAAA==.',
Rc='Rctraxx:BAAALgAECgYJBwABLgAECggJGgAGAEQWAA==.',
Re='Realpro:BAAALgAECgQJBAAAAA==.Redrogue:BAABLgAECn8/AAIRAAkJuw3hDABuAQARAAkJuw3hDABuAQAAAA==.Revela:BAAALgADCgcJDQAAAA==.',
Ri='Riftan:BAACLgAFFH8XAAMbAAUJIBcxagAjAQAbAAUJIBcxagAjAQAcAAEJuQMAKgA7AAAuAAQKfzQAAhsACQmXHvIaANwCABsACQmXHvIaANwCAAAA.Rightousnes:BAAALgADCgcJCQAAAA==.Riviee:BAABLgAECn8fAAIOAAgJZAc7RQAxAQAOAAgJZAc7RQAxAQAAAA==.',
Ro='Rogun:BAABLgAECn83AAIKAAgJTxGADQCGAQAKAAgJTxGADQCGAQAAAA==.Roredge:BAAALgAECgEJAQABLgAECggJGgAGAEQWAA==.Rosealie:BAAALgADCgMJAwAAAA==.',
Ry='Rycbar:BAAALgADCgkJCQAAAA==.Rynthanuu:BAAALgADCgEJAQAAAA==.',
Sa='Sarann:BAAALgAECgQJCgAAAA==.Sassbringer:BAAALgAECgUJCgAAAA==.Satele:BAAALgAECgYJDgAAAA==.Sauce:BAAALgADCgMJAwAAAA==.',
Sc='Scarypoppins:BAABLgAECn8jAAICAAkJ3iB3BgC4AgACAAkJ3iB3BgC4AgAAAA==.',
Se='Seloki:BAAALgADCgQJBAAAAA==.Senia:BAAALgAECggJDwAAAA==.Seniortank:BAAALgADCgEJAQAAAA==.Serracha:BAAALgAECgYJDAABLgAFFAIJCAAHAA8PAA==.Serraz:BAAALgAECgMJBgABLgAFFAIJCAAHAA8PAA==.Serrbear:BAAALgAECgcJCAAAAA==.Seònaid:BAAALgAFFAIJBAAAAA==.',
Sh='Shadowkaizen:BAAALgADCgEJAQAAAA==.Shambullance:BAAALgAFFAEJAgABLgAECgYJDQAEAAAAAA==.Shammywaddle:BAABLgAECn8ZAAMGAAgJAyDzIQATAgAGAAYJ4CHzIQATAgAZAAgJnRDuMwBpAQAAAA==.Shamtraxx:BAABLgAECn8aAAMGAAgJRBb5LwDIAQAGAAcJPBb5LwDIAQAZAAcJTw1zRgAvAQAAAA==.Sheraania:BAAALgADCgcJCAAAAA==.',
Si='Sinistress:BAAALgADCgcJCwAAAA==.',
Sk='Skorpius:BAABLgAECn8fAAIWAAcJmwe6qQDwAAAWAAcJmwe6qQDwAAAAAA==.Skumi:BAAALgAECgUJCwAAAA==.',
Sl='Slaytanic:BAABLgAECn8+AAIXAAgJQh6nKwBRAgAXAAgJQh6nKwBRAgAAAA==.Slymick:BAABLgAECn8WAAISAAkJYQRKMQAWAQASAAkJYQRKMQAWAQAAAA==.',
Sn='Snoka:BAAALgAECgcJCQAAAA==.',
So='Solora:BAABLgAECn8/AAIZAAkJ/AcCQAAxAQAZAAkJ/AcCQAAxAQAAAA==.Soluna:BAABLgAECn87AAIXAAkJ8xU0QQABAgAXAAkJ8xU0QQABAgAAAA==.',
Sp='Sparrowrain:BAAALgAECgUJBQAAAA==.',
St='Stiflerd:BAAALgADCgEJAQAAAA==.Strawry:BAAALgAECgQJCAAAAA==.Stuffedbear:BAABLgAECn8UAAILAAYJBQUbXgCbAAALAAYJBQUbXgCbAAAAAA==.',
Su='Subiegrl:BAAALgAECgQJBAAAAA==.Sunjiwung:BAAALgAECgMJAwAAAA==.Supadin:BAAALgAECgIJAgAAAA==.Supernano:BAAALgAECgUJBQAAAA==.',
Sv='Svyra:BAAALgADCgEJAQAAAA==.',
Sw='Swll:BAAALgAECgYJDQAAAA==.',
Sy='Sylanann:BAAALgADCgMJAwAAAA==.Syrüs:BAACLgAFFH8TAAIaAAQJERmKDQA4AQAaAAQJERmKDQA4AQAuAAQKfygAAhoACQmMIS4FAO4CABoACQmMIS4FAO4CAAAA.',
['Sã']='Sãrik:BAABLgAECn8VAAIXAAYJvxM3owAxAQAXAAYJvxM3owAxAQAAAA==.',
['Sí']='Sílver:BAABLgAECn8kAAIZAAgJphAKOwBHAQAZAAgJphAKOwBHAQAAAA==.',
Ta='Taebeck:BAAALgADCgQJBAAAAA==.Tasty:BAAALgADCgYJBgABLgAFFAQJGQAGAOsbAA==.',
Te='Telamon:BAAALgADCgcJDAAAAA==.Teokojin:BAAALgAECgMJAwAAAA==.',
Th='Thalyra:BAABLgAFFH8HAAIPAAMJCBZNWADiAAAPAAMJCBZNWADiAAAAAA==.Thirstrap:BAABLgAECn8kAAIaAAgJ5Q4QJABUAQAaAAgJ5Q4QJABUAQAAAA==.Thorge:BAABLgAECn8mAAIBAAkJURgQCwBvAgABAAkJURgQCwBvAgAAAA==.Thyrus:BAAALgADCgQJBAAAAA==.',
Ti='Tips:BAAALgADCgQJBAAAAA==.',
To='Tokesmasmoke:BAAALgAECgMJAwAAAA==.Toragos:BAAALgADCgQJBAAAAA==.',
Tr='Träshley:BAAALgAECgYJEwAAAA==.',
Uk='Uknak:BAAALgAECgQJBwAAAA==.',
Ul='Ulanui:BAAALgADCgMJAwAAAA==.',
Un='Unrêstrained:BAAALgADCgQJBAAAAA==.',
Ur='Urma:BAAALgAECgQJBQAAAA==.',
Va='Vaediirn:BAAALgADCgQJBAAAAA==.Vallcore:BAAALgADCgUJBgAAAA==.',
Ve='Vennt:BAACLgAFFH8FAAIJAAUJVw9LQAAoAQAJAAUJVw9LQAAoAQAuAAQKfyEAAwkACAlhF7BTAKUBAAoACAktEWgnAO4BAAkABgnJHbBTAKUBAAEuAAUUBwkeABkAOBMA.Ventt:BAACLgAFFH8eAAIZAAcJOBPHDwClAQAZAAcJOBPHDwClAQAuAAQKfzEAAhkACQkjI4wGAPECABkACQkjI4wGAPECAAAA.Veredelyse:BAAALgAECgYJBgABLgAECggJGgAiANQQAA==.',
Vo='Volstaag:BAAALgAECgEJBwAAAA==.Voluus:BAABLgAECn8VAAIZAAcJqwyjSgAHAQAZAAcJqwyjSgAHAQAAAA==.',
Vr='Vrorag:BAAALgAECgcJEwAAAA==.',
Wa='Walfar:BAABLgAECn8dAAIQAAYJKRriFgBoAQAQAAYJKRriFgBoAQAAAA==.Wallbanger:BAAALgAFFAMJAwAAAA==.Walterlight:BAAALgADCgcJCwAAAA==.Warbuckss:BAAALgAECgQJEQABLgAECgYJHQAbAHoVAA==.Warbucksthe:BAAALgAECgEJAgABLgAECgYJHQAbAHoVAA==.Warbud:BAAALgADCgUJCwAAAA==.Wayme:BAABLgAECn8hAAIRAAgJhw5rDwBGAQARAAgJhw5rDwBGAQAAAA==.',
We='Wendorf:BAAALgADCgkJDgAAAA==.',
Wh='Whispyr:BAAALgADCgcJCAAAAA==.Whiteclaw:BAAALgAECgMJAwAAAA==.',
Wo='Wooster:BAAALgAECgIJAwAAAA==.',
Xa='Xaeru:BAAALgAECgEJAgAAAA==.Xahle:BAABLgAECn8cAAIbAAkJpBKUTgDVAQAbAAkJpBKUTgDVAQAAAA==.Xanado:BAAALgADCgEJAQAAAA==.',
Xs='Xsanguinate:BAAALgAECgQJBAAAAA==.',
Ya='Yarikh:BAAALgAECgEJAQAAAA==.',
Za='Zadkiel:BAAALgAFFAEJAQAAAA==.',
Ze='Zendayah:BAAALgADCgMJAwAAAA==.Zeparu:BAABLgAECn8vAAMbAAkJzB0EFADOAgAbAAkJzB0EFADOAgAcAAEJcxLkNwA5AAAAAA==.Zero:BAAALgAECgUJBwABLgAECgkJHwAIAEkWAA==.',
Zi='Zinkgirl:BAAALgADCgIJAgAAAA==.Zitillidan:BAAALgAECggJEwABLgAECgcJJwABAN4VAA==.',
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
