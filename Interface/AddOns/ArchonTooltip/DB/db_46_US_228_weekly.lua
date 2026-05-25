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

local lookup = {'Hunter-Survival','DeathKnight-Unholy','Warlock-Affliction','Unknown-Unknown','Priest-Holy','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Druid-Balance','Warrior-Protection','Mage-Frost','Warrior-Fury','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','Warlock-Destruction','Rogue-Subtlety','Evoker-Devastation','Priest-Shadow','Priest-Discipline','Warlock-Demonology','Paladin-Retribution','Druid-Restoration','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Paladin-Holy','Evoker-Augmentation','DemonHunter-Vengeance','Monk-Windwalker',}
local provider = {region='US',realm='Uldaman',name='US',type='weekly',zone=46,date='2026-05-24',data={Ad='Ademar:BAABLgAECn8lAAIBAAYJkRikIgBqAQABAAYJkRikIgBqAQABLgAECgcJGQACAGkSAA==.',
Ae='Aenora:BAAALgAECgMJAwAAAA==.',
Ag='Aggrothief:BAAALgAECgQJBAAAAA==.Agrius:BAAALgAECgYJDAAAAA==.',
Ai='Ainokeas:BAAALgAECgIJAgAAAA==.',
Ak='Akurumira:BAAALgADCgQJBgAAAA==.',
Al='Alexändros:BAAALgADCgUJCAAAAA==.Alkie:BAAALgAECgMJBgAAAA==.Allectra:BAAALgAECgYJDwAAAA==.Allupinya:BAAALgAECgUJBgAAAA==.',
Am='Amnon:BAABLgAECn8wAAIDAAkJyB89AgCRAgADAAkJyB89AgCRAgAAAA==.',
Ar='Arelliea:BAAALgADCgEJAQABLgAFFAEJAQAEAAAAAA==.Arlessa:BAAALgAECgMJAwABLgAECgkJLgAFAMQeAA==.',
As='Asaelis:BAAALgAECgYJDQAAAA==.Astauren:BAAALgADCgMJBAAAAA==.Astralflame:BAAALgADCgYJCAAAAA==.',
Au='Augwaddles:BAAALgAECgUJBwABLgAECggJGQAGAAMgAA==.',
Av='Avataraang:BAAALgADCgEJAQAAAA==.Avramora:BAAALgAECgUJDAABLgAFFAEJAQAEAAAAAA==.',
Ax='Axila:BAAALgAECgIJAwAAAA==.',
Az='Azdaja:BAABLgAECn8lAAMHAAkJFg4GHQCgAQAHAAkJFg4GHQCgAQAIAAEJ7QD8dwAPAAAAAA==.Azgardia:BAAALgAECgYJCAAAAA==.Azryiel:BAAALgAECgcJEAABLgAECgkJJQAHABYOAA==.Azulå:BAAALgAFFAEJAQAAAA==.',
Ba='Bach:BAABLgAFFH8SAAIJAAUJexrWEgBNAQAJAAUJexrWEgBNAQAAAA==.Balloffur:BAABLgAECn8cAAIKAAkJIA5TFQB6AQAKAAkJIA5TFQB6AQAAAA==.Bamboostixx:BAABLgAECn8mAAILAAkJKRCyQwD3AQALAAkJKRCyQwD3AQAAAA==.',
Be='Bellgirls:BAAALgAECgMJAwAAAA==.Belnetukent:BAAALgADCgEJAQAAAA==.Berastu:BAABLgAECn8hAAIMAAkJoxSCHwDSAQAMAAkJoxSCHwDSAQAAAA==.Berastú:BAAALgAECgYJCwAAAA==.',
Bl='Blackbear:BAAALgAECgMJAwABLgADCgEJAQAEAAAAAA==.Bleufromage:BAAALgADCgIJAgAAAA==.Bloodlusst:BAAALgAECgEJAQAAAA==.Bloodraina:BAAALgADCgYJBgAAAA==.',
Bo='Bonechill:BAAALgADCgYJDAAAAA==.Boogyboo:BAAALgADCgEJAQAAAA==.Booz:BAABLgAECn8lAAINAAgJyhguLQD2AQANAAgJyhguLQD2AQAAAA==.Bors:BAABLgAECn8fAAMOAAkJQxmiCQD8AgAOAAkJQxmiCQD8AgAPAAUJARHRUgABAQAAAA==.Bowdacious:BAAALgAECgEJAgAAAA==.',
Bu='Bubbleõseven:BAAALgADCggJDwAAAA==.Bunnystalker:BAAALgADCgYJBwAAAA==.',
Ca='Callee:BAABLgAECn8mAAIOAAgJXg0aUwB9AQAOAAgJXg0aUwB9AQAAAA==.Calyse:BAABLgAECn8dAAIQAAcJISFgCQAPAgAQAAcJISFgCQAPAgAAAA==.Casblind:BAACLgAFFH8dAAINAAcJeBpgCgALAgANAAcJeBpgCgALAgAuAAQKfx8AAg0ACQkZIHsQAPoCAA0ACQkZIHsQAPoCAAAA.Casima:BAAALgAECgcJEgAAAA==.',
Ch='Chandani:BAAALgAECgYJCAAAAA==.Chesterblat:BAAALgADCgIJAgAAAA==.Cheydinhal:BAABLgAECn83AAIFAAgJShRsGADkAQAFAAgJShRsGADkAQAAAA==.Chicknwaffle:BAAALgAECgQJCgAAAA==.Chocó:BAAALgADCgEJAQAAAA==.Chumlee:BAABLgAECn8qAAIHAAgJ4BifFQDhAQAHAAgJ4BifFQDhAQAAAA==.',
Ci='Ciri:BAAALgAECgEJAQAAAA==.',
Co='Colleague:BAAALgAECgUJBgAAAA==.Cornmoon:BAAALgADCgQJAgAAAA==.',
Cr='Crank:BAAALgAFFAMJAwABLgAFFAgJIAARAAkiAA==.',
Da='Dalanorea:BAAALgAECgYJBgAAAA==.Dandorn:BAAALgADCgIJAgAAAA==.Darksushi:BAAALgAECgYJEAAAAA==.Daylate:BAAALgADCgUJBQAAAA==.',
Dh='Dhabyss:BAAALgADCggJCAABLgAECggJLQASAL8jAA==.',
Di='Diménsional:BAABLgAECn8dAAIHAAgJpQ99JwBYAQAHAAgJpQ99JwBYAQAAAA==.Dinbek:BAAALgAECgcJDwAAAA==.Dindino:BAAALgADCgkJEAAAAA==.Dindroc:BAAALgAECgQJBAAAAA==.Dingread:BAAALgAECgYJBgAAAA==.',
Dr='Dragin:BAABLgAECn8lAAITAAgJqAjkCwA3AQATAAgJqAjkCwA3AQAAAA==.Dreyla:BAAALgADCgQJCAAAAA==.Drunkmcmonk:BAAALgADCgMJBgAAAA==.',
Du='Duronimo:BAAALgAECgUJBgAAAA==.Dusksurge:BAAALgADCgIJAgAAAA==.',
['Dÿ']='Dÿmmensional:BAAALgAECgQJBwAAAA==.',
Ec='Eclipze:BAACLgAFFH8TAAMUAAQJ4Qt6FQAiAQAUAAQJ4Qt6FQAiAQAVAAIJgAJdOwBCAAAuAAQKfyMABBQACQmqGHQTABICABQACQmqGHQTABICABUAAQkoB9hbACsAAAUAAQnmARyKACIAAAAA.Eclipzee:BAAALgADCgMJAwABLgAFFAQJEwAUAOELAA==.Eclipzé:BAABLgAECn8aAAMDAAgJqBkkEwABAQAWAAYJMhGshgAaAQADAAUJpxgkEwABAQABLgAFFAQJEwAUAOELAA==.',
Ei='Eifel:BAAALgAECgcJEgABLgAECgkJGwAXABceAA==.',
El='Elessardan:BAABLgAECn8tAAMYAAkJmh6HBwAlAwAYAAkJmh6HBwAlAwAJAAIJXhGyawBxAAAAAA==.Elothien:BAAALgAECgEJAgAAAA==.Elvaca:BAAALgAECgUJBQAAAA==.',
En='Endilli:BAAALgAECgUJDQAAAA==.',
Eq='Equinoxis:BAEALgAECgYJCwABLgAFFAYJIwAUAPocAA==.',
Et='Eternal:BAABLgAFFH8GAAIXAAQJXg2HNwAgAQAXAAQJXg2HNwAgAQAAAA==.',
Ev='Evaki:BAAALgADCgEJAgAAAA==.',
Ez='Ezekiel:BAAALgAECgEJAQAAAA==.',
Fa='Faein:BAAALgADCgIJAgAAAA==.Fallynangel:BAABLgAECn81AAISAAgJkhafFgDCAQASAAgJkhafFgDCAQAAAA==.',
Fe='Fearlock:BAAALgADCgUJCAAAAA==.Felrafram:BAAALgADCgQJAwAAAA==.Fenyx:BAABLgAECn86AAIHAAkJHhRUEgAFAgAHAAkJHhRUEgAFAgABLgAFFAMJDAAKAJcZAA==.',
Fi='Fightnyte:BAAALgAECgUJBQABLgAECgkJIgAWALcXAQ==.Filho:BAABLgAECn8cAAMOAAcJVhL4aABFAQAOAAcJVhL4aABFAQAPAAIJqALDgABEAAAAAA==.',
Fr='Friedtips:BAAALgADCgQJBgABLgAFFAMJBwAZAMUUAA==.Frostwaffle:BAAALgADCgYJBgABLgAECgQJCgAEAAAAAA==.Frumpy:BAAALgAECgEJAQABLgAECgcJEAAEAAAAAA==.',
Ga='Gabe:BAAALgAECgUJCwAAAA==.Galvek:BAACLgAFFH8PAAQBAAUJahfUDABIAQABAAUJahfUDABIAQAOAAIJaws1ZQCMAAAPAAEJnwNuLABBAAAuAAQKfycABAEACQm+HfQMAD0CAAEACAmUHvQMAD0CAA4ABgkOHbFBAKkBAA8ABgmhEGM9AGgBAAAA.Garjzlaa:BAAALgAECgYJBwAAAA==.Garugamesh:BAAALgADCgcJCQAAAA==.Gas:BAAALgAECgEJAQABLgAECgQJBAAEAAAAAA==.',
Gi='Gigglebytes:BAAALgAECgIJAQAAAA==.',
Gn='Gnowen:BAAALgADCgkJCQABLgAECgUJDAAEAAAAAA==.',
Go='Gojira:BAAALgADCgIJAgAAAA==.',
Gr='Greyswandir:BAAALgAECgYJEwAAAA==.Gryssli:BAAALgADCgIJAgAAAA==.',
Gw='Gwarr:BAAALgAECgYJDAAAAA==.',
Ha='Harandufu:BAAALgAECgQJBQAAAA==.Hardwön:BAAALgAECgMJAwAAAA==.Harvie:BAAALgADCgYJBgABLgAECgYJEwAEAAAAAA==.Hatani:BAAALgAECgEJAQAAAA==.Haylee:BAAALgADCgkJEwAAAA==.',
He='Hemofluffin:BAAALgAECgIJAgABLgAFFAQJDgACAKEVAA==.',
Hu='Husky:BAAALgAECggJEgAAAA==.',
Ic='Icyfurball:BAAALgAECgIJAgABLgAECgcJGAAKAKImAA==.',
Ik='Ikillyounows:BAAALgAECgQJBAAAAA==.',
Il='Ilovesanta:BAAALgAECgYJDQAAAA==.',
In='Indigobleue:BAABLgAECn8yAAQFAAgJeh1oEQA0AgAFAAgJeh1oEQA0AgAVAAcJHBiQGADkAQAUAAEJIAirdAAvAAAAAA==.Infidel:BAAALgAECgQJBwABLgADCgEJAQAEAAAAAA==.',
Ja='Jalincia:BAAALgAECgUJBQAAAA==.Japplen:BAAALgAECgQJCAAAAA==.',
Je='Jeffery:BAAALgADCgMJAwAAAA==.Jeraziah:BAAALgADCgYJBwAAAA==.',
Ji='Jinkalou:BAAALgAECgQJBAABLgAECggJGgAGAEQWAA==.Jinn:BAAALgADCgUJBQAAAA==.Jinsun:BAAALgAECgUJBQAAAA==.Jiñ:BAAALgAECgQJCAAAAA==.',
Jo='Jorenson:BAABLgAECn8qAAICAAgJaBK2ZAB9AQACAAgJaBK2ZAB9AQAAAA==.',
Ka='Kaether:BAABLgAECn8XAAMFAAcJMwgPNAASAQAFAAcJMwgPNAASAQAUAAIJmADkaQAkAAAAAA==.Kalzdemar:BAABLgAECn8ZAAMCAAcJaRJTeQBOAQACAAcJVRBTeQBOAQAaAAQJxxhzHACjAAAAAA==.Kasitus:BAABLgAECn8eAAICAAgJJSRNIABoAgACAAgJJSRNIABoAgAAAA==.',
Ke='Keldanor:BAAALgAECgEJAQAAAA==.',
Kh='Khei:BAAALgADCgIJAgAAAA==.',
Ki='Kilometraje:BAABLgAECn8YAAMbAAgJOxIMGAB3AQAbAAgJJxEMGAB3AQACAAYJTwwl9QCGAAAAAA==.Kira:BAAALgAECgIJAgABLgAECgQJBAAEAAAAAA==.Kissey:BAAALgAECgQJBwAAAA==.Kivi:BAAALgADCgEJAQAAAA==.',
Ko='Korneliuz:BAACLgAFFH8FAAIGAAIJRhi0RwCZAAAGAAIJRhi0RwCZAAAuAAQKfxUAAwYABgl3HJM5AJsBAAYABgl3HJM5AJsBABwAAQm/DFKPACgAAAAA.',
Kr='Kraink:BAAALgADCgEJAQAAAA==.Krayvin:BAAALgADCgIJAgAAAA==.',
Ku='Kungmoofu:BAAALgADCgIJAgABLgAECgcJEAAEAAAAAA==.',
Ky='Kyrak:BAAALgAECgYJDwAAAA==.',
La='Labiamajorah:BAAALgADCgIJAgAAAA==.Ladiebee:BAAALgADCggJCAAAAA==.Lainey:BAACLgAFFH8FAAIOAAMJehl4OwD/AAAOAAMJehl4OwD/AAAuAAQKfz0AAg4ACQlQIPYKANsCAA4ACQlQIPYKANsCAAAA.Landocamando:BAABLgAECn8eAAIMAAYJeRtaKgCLAQAMAAYJeRtaKgCLAQAAAA==.Larrusbain:BAABLgAECn8bAAIdAAYJWxgDLACOAQAdAAYJWxgDLACOAQAAAA==.',
Le='Leafin:BAAALgADCgUJCQABLgAECggJNQASAJIWAA==.Lerya:BAACLgAFFH8FAAMeAAMJIQQOOwCnAAAeAAMJIQQOOwCnAAATAAEJVwPHDAA/AAAuAAQKfyEAAhMACQnsEnEHAKcBABMACQnsEnEHAKcBAAAA.Levictus:BAAALgAECgEJAQAAAA==.Lexnn:BAABLgAECn8vAAINAAgJPhODRQCXAQANAAgJPhODRQCXAQAAAA==.Lexonidas:BAAALgADCgEJAgAAAA==.',
Li='Liantelva:BAAALgAECgcJEQAAAA==.Lifepriest:BAAALgAECgEJAQAAAA==.Ligetnoone:BAABLgAECn8YAAIKAAcJoibTBQCVAgAKAAcJoibTBQCVAgAAAA==.Lighte:BAABLgAECn8yAAILAAkJLhzCJABvAgALAAkJLhzCJABvAgAAAA==.Lilyith:BAAALgAECgYJCwAAAA==.Lips:BAAALgAECgMJAwAAAA==.',
Lo='Logicx:BAABLgAECn8tAAIJAAgJEhiyFgDxAQAJAAgJEhiyFgDxAQAAAA==.Lorka:BAAALgADCgYJBgAAAA==.Lorvoldenord:BAAALgADCgIJAgAAAA==.',
Lu='Lunarìa:BAAALgADCggJCwAAAA==.',
['Lê']='Lêssa:BAAALgAECgQJBQAAAA==.',
Ma='Magici:BAABLgAECn8pAAILAAgJyg+SZgCWAQALAAgJyg+SZgCWAQAAAA==.Magnyesis:BAAALgADCgEJAQAAAA==.Mahavailo:BAAALgAECgUJBQAAAA==.Malina:BAAALgAECgEJAQAAAA==.Manimal:BAAALgAECgEJBAAAAA==.Marraud:BAAALgADCgYJBAAAAA==.Mavren:BAAALgAECgUJDAAAAA==.',
Me='Mefisto:BAAALgAECgQJBQABLgAECgUJDAAEAAAAAA==.Megadruid:BAAALgADCgEJAQAAAA==.Mellesaun:BAABLgAECn8mAAQfAAgJxQg8EQAPAQAfAAgJowg8EQAPAQANAAYJIwY8pwCrAAAZAAQJkgVqWwBzAAAAAA==.Merie:BAAALgADCgYJBwAAAA==.Mewtwo:BAABLgAFFH8KAAIWAAMJLBMGXADjAAAWAAMJLBMGXADjAAABLgAFFAcJFgAeABwXAA==.',
Mi='Miikeey:BAAALgADCgIJAgAAAA==.Mirei:BAAALgADCggJCQAAAA==.Mithrios:BAAALgAECgUJBQABLgAECgkJCAAEAAAAAA==.',
Mo='Moonsaw:BAABLgAECn8cAAIgAAcJkCTJCgBzAgAgAAcJkCTJCgBzAgAAAA==.Mordella:BAAALgADCgIJAwAAAA==.Moriartus:BAAALgADCgEJAQAAAA==.Mosthated:BAAALgADCgIJAgAAAA==.',
Mu='Muffin:BAEALgADCgYJBgABLgAECgUJDgAEAAAAAA==.',
My='Myrling:BAABLgAECn8dAAMYAAgJTAjNVgAWAQAYAAgJTAjNVgAWAQAJAAEJSwI+iwAcAAAAAA==.Mythrial:BAAALgAECgYJCgAAAA==.',
Ne='Nenni:BAAALgADCgYJBgAAAA==.Neph:BAAALgADCgkJCQAAAA==.Newt:BAACLgAFFH8FAAINAAMJSwz0TwDMAAANAAMJSwz0TwDMAAAuAAQKfykABA0ACQn2GBkjACgCAA0ACAmkFhkjACgCABkABwmVFqQgALgBAB8AAQmvAowwACEAAAAA.',
Ni='Nimbus:BAACLgAFFH8YAAILAAUJRx65KgB8AQALAAUJRx65KgB8AQAuAAQKfyQAAgsACQlpImcKABMDAAsACQlpImcKABMDAAEuAAUUCAkWAB4ATBYA.Ninkasi:BAAALgAECgYJBgAAAA==.Nishikki:BAECLgAFFH8jAAIUAAYJ+hxYBQDWAQAUAAYJ+hxYBQDWAQAuAAQKfzwAAhQACQmYIyICAD8DABQACQmYIyICAD8DAAAA.',
No='Nocanno:BAAALgADCgYJBgAAAA==.',
Ny='Nydie:BAABLgAECn87AAIXAAkJNBsgIABqAgAXAAkJNBsgIABqAgAAAA==.Nymuellyn:BAABLgAECn8tAAISAAgJvyP2BgCaAgASAAgJvyP2BgCaAgAAAA==.',
Nz='Nzonah:BAAALgADCgEJAQAAAA==.',
Ot='Ottokurai:BAAALgAECgQJBAAAAA==.',
Pa='Palmanance:BAAALgAECgkJCgAAAA==.Pariahus:BAAALgAECgQJBAABLgAECgkJGwAXABceAA==.',
Pe='Penumbral:BAAALgAECgYJDwAAAA==.',
Ph='Phalst:BAAALgAECgEJAgAAAA==.Phibalan:BAAALgAECgEJAQAAAA==.',
Pi='Pixel:BAAALgAECgIJAwAAAA==.Pixil:BAAALgADCgEJAQAAAA==.Pixishot:BAABLgAECn8WAAIOAAYJPAxLcAAXAQAOAAYJPAxLcAAXAQAAAA==.',
Pr='Pradigy:BAABLgAECn8ZAAICAAYJxQ8KpQAAAQACAAYJxQ8KpQAAAQAAAA==.',
Pu='Pubba:BAAALgAECgcJEAAAAA==.Pubbazug:BAAALgAECgUJCwABLgAECgcJEAAEAAAAAA==.Pubismaximus:BAAALgAECgEJAQABLgAECgcJEAAEAAAAAA==.',
Pw='Pwincess:BAAALgAECgkJDQAAAA==.',
Ra='Raelyndria:BAABLgAECn8XAAMUAAgJvBc9HQC3AQAUAAgJvBc9HQC3AQAVAAUJ8BsjKABVAQAAAA==.Raengurth:BAAALgAECgYJBwAAAA==.Raenraug:BAAALgADCgMJAwAAAA==.Rakkali:BAAALgAFFAEJAQAAAA==.Rancavus:BAAALgADCgMJAwAAAA==.Rastakehn:BAAALgADCgYJBgAAAA==.Ratraxx:BAAALgADCgYJBgABLgAECggJGgAGAEQWAA==.Razaller:BAABLgAECn8UAAMeAAkJiQ6CKgBrAQAeAAkJiQ6CKgBrAQATAAEJFgE+RgAbAAAAAA==.',
Rc='Rctraxx:BAAALgAECgYJBwABLgAECggJGgAGAEQWAA==.',
Re='Redrogue:BAABLgAECn8uAAIRAAgJIwoBEAAYAQARAAgJIwoBEAAYAQAAAA==.Revela:BAAALgADCgcJDQAAAA==.',
Ri='Riftan:BAACLgAFFH8OAAICAAQJoRXxTQAxAQACAAQJoRXxTQAxAQAuAAQKfzIAAgIACAncIfIaANwCAAIACAncIfIaANwCAAAA.Rightousnes:BAAALgADCgcJCQAAAA==.Riviee:BAABLgAECn8UAAIMAAUJvgeDXAC3AAAMAAUJvgeDXAC3AAAAAA==.',
Ro='Rogun:BAABLgAECn8eAAIPAAcJyA3KEQAaAQAPAAcJyA3KEQAaAQAAAA==.Roredge:BAAALgAECgEJAQABLgAECggJGgAGAEQWAA==.Rosealie:BAAALgADCgMJAwAAAA==.',
Ry='Rycbar:BAAALgADCgkJCQAAAA==.Rynthanuu:BAAALgADCgEJAQAAAA==.',
Sa='Sarann:BAAALgAECgMJBQAAAA==.Satele:BAAALgAECgQJCQAAAA==.',
Sc='Scarypoppins:BAABLgAECn8hAAIbAAgJiCHTBwB4AgAbAAgJiCHTBwB4AgAAAA==.',
Se='Seloki:BAAALgADCgQJBAAAAA==.Senia:BAAALgAECgcJCQAAAA==.Seniortank:BAAALgADCgEJAQAAAA==.Serracha:BAAALgAECgYJDAABLgAECgkJJQAHABYOAA==.Seònaid:BAAALgAFFAIJBAAAAA==.',
Sh='Shadowkaizen:BAAALgADCgEJAQAAAA==.Shambullance:BAAALgAFFAEJAQABLgAECgYJDQAEAAAAAA==.Shammywaddle:BAABLgAECn8ZAAMGAAgJAyDzIQATAgAGAAYJ4CHzIQATAgAcAAgJnRCpKwBuAQAAAA==.Shamtraxx:BAABLgAECn8aAAMGAAgJRBb5LwDIAQAGAAcJPBb5LwDIAQAcAAcJTw1zRgAvAQAAAA==.Sheraania:BAAALgADCgcJCAAAAA==.',
Si='Sinistress:BAAALgADCgcJCwAAAA==.',
Sk='Skorpius:BAAALgAECgYJEwAAAA==.Skumi:BAAALgAECgUJCwAAAA==.',
Sl='Slaytanic:BAABLgAECn8uAAIXAAgJhRwGLgAoAgAXAAgJhRwGLgAoAgAAAA==.Slymick:BAAALgAECggJEwAAAA==.',
Sn='Snoka:BAAALgAECgYJBgAAAA==.',
So='Solora:BAABLgAECn8uAAIcAAgJHgc5QQACAQAcAAgJHgc5QQACAQAAAA==.Soluna:BAABLgAECn8wAAIXAAkJ1RSaOQD+AQAXAAkJ1RSaOQD+AQAAAA==.',
Sp='Sparrowrain:BAAALgAECgMJAwAAAA==.',
St='Stiflerd:BAAALgADCgEJAQAAAA==.Strawry:BAAALgAECgQJCAAAAA==.Stuffedbear:BAABLgAECn8UAAIJAAYJBQUrUQCcAAAJAAYJBQUrUQCcAAAAAA==.',
Su='Subiegrl:BAAALgAECgQJBAAAAA==.Sunjiwung:BAAALgAECgMJAwAAAA==.Supadin:BAAALgAECgIJAgAAAA==.Supernano:BAAALgAECgUJBQAAAA==.',
Sw='Swll:BAAALgAECgYJDQAAAA==.',
Sy='Sylanann:BAAALgADCgMJAwAAAA==.Syrüs:BAACLgAFFH8HAAIZAAMJxRQBEQDlAAAZAAMJxRQBEQDlAAAuAAQKfyYAAhkACAmpIG4IAHwCABkACAmpIG4IAHwCAAAA.',
['Sã']='Sãrik:BAAALgAECgYJDQAAAA==.',
['Sí']='Sílver:BAABLgAECn8kAAIcAAgJphDhMABRAQAcAAgJphDhMABRAQAAAA==.',
Ta='Taebeck:BAAALgADCgQJBAAAAA==.Tasty:BAAALgADCgYJBgABLgAFFAQJDgAGACEYAA==.',
Th='Thalyra:BAAALgAFFAMJBAAAAA==.Thirstrap:BAABLgAECn8iAAIZAAgJPg53HQBWAQAZAAgJPg53HQBWAQAAAA==.Thorge:BAABLgAECn8dAAIBAAgJaxWqFQDbAQABAAgJaxWqFQDbAQAAAA==.Thyrus:BAAALgADCgQJBAAAAA==.',
Ti='Tips:BAAALgADCgQJBAAAAA==.',
To='Tokesmasmoke:BAAALgAECgMJAwAAAA==.Toragos:BAAALgADCgQJBAAAAA==.',
Tr='Träshley:BAAALgAECgYJEwAAAA==.',
Uk='Uknak:BAAALgAECgQJBwAAAA==.',
Ul='Ulanui:BAAALgADCgMJAwAAAA==.',
Ur='Urma:BAAALgAECgQJBQAAAA==.',
Va='Vaediirn:BAAALgADCgQJBAAAAA==.Vallcore:BAAALgADCgUJBgAAAA==.',
Ve='Vennt:BAABLgAECn8hAAMOAAgJYRe1QAC2AQAPAAgJLRFoJwDuAQAOAAYJyR21QAC2AQAAAA==.Ventt:BAACLgAFFH8cAAIcAAYJyROPDACGAQAcAAYJyROPDACGAQAuAAQKfzEAAhwACQkjI9YEAPoCABwACQkjI9YEAPoCAAAA.',
Vo='Volstaag:BAAALgAECgEJBAAAAA==.Voluus:BAABLgAECn8VAAIcAAcJqwzcPQAQAQAcAAcJqwzcPQAQAQAAAA==.',
Vr='Vrorag:BAAALgAECgcJEwAAAA==.',
Wa='Walfar:BAAALgAECgUJDAAAAA==.Wallbanger:BAAALgAECgQJBAAAAA==.Walterlight:BAAALgADCgcJCwAAAA==.Warbuckss:BAAALgAECgQJDgABLgAECgYJGQACAMUPAA==.Warbucksthe:BAAALgADCgYJBgABLgAECgYJGQACAMUPAA==.Warbud:BAAALgADCgEJAQAAAA==.Wayme:BAABLgAECn8XAAIRAAUJnw5DGQC6AAARAAUJnw5DGQC6AAAAAA==.',
We='Wendorf:BAAALgADCgkJDgAAAA==.',
Wh='Whispyr:BAAALgADCgcJCAAAAA==.Whiteclaw:BAAALgAECgMJAwAAAA==.',
Wo='Wooster:BAAALgAECgEJAgAAAA==.',
Xa='Xahle:BAABLgAECn8cAAICAAkJpBLOQADhAQACAAkJpBLOQADhAQAAAA==.Xanado:BAAALgADCgEJAQAAAA==.',
Xs='Xsanguinate:BAAALgAECgQJBAAAAA==.',
Ya='Yarikh:BAAALgADCgEJAQAAAA==.',
Za='Zadkiel:BAAALgAECgQJBgAAAA==.',
Ze='Zeparu:BAABLgAECn8gAAICAAkJqhy6EQDDAgACAAkJqhy6EQDDAgAAAA==.Zero:BAAALgAECgUJBwABLgAECgkJHwAIAEkWAA==.',
Zi='Zitillidan:BAAALgAECgcJBwABLgAECgcJGQACAGkSAA==.',
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
