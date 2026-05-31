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

local lookup = {'Monk-Windwalker','Monk-Brewmaster','Mage-Frost','DeathKnight-Blood','DeathKnight-Unholy','Warrior-Protection','DemonHunter-Devourer','Paladin-Holy','Hunter-Marksmanship','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','Hunter-BeastMastery','Druid-Feral','Paladin-Retribution','Priest-Discipline','Priest-Shadow','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Restoration','Druid-Balance','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','Priest-Holy','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','Hunter-Survival','Paladin-Protection','Monk-Mistweaver','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Absolon:BAAALgAECgQJBAAAAA==.Absólon:BAAALgADCgcJBwAAAA==.',
Ae='Aendia:BAAALgADCgIJAwAAAA==.Aeolos:BAAALgAECgUJBQAAAA==.',
Af='Affae:BAABLgAFFH8KAAMBAAMJFBOKKQCEAAACAAIJ6RZAPwCIAAABAAIJPg6KKQCEAAAAAA==.',
Ag='Agrios:BAAALgAECgYJCAAAAA==.',
Ak='Ak:BAABLgAECn8pAAIDAAkJ0SAcGACzAgADAAkJ0SAcGACzAgAAAA==.',
Al='Alanas:BAAALgADCgEJAQAAAA==.Alcohlol:BAAALgADCgEJAQAAAA==.Allendril:BAAALgADCgIJAgABLgAECgkJKQAEAFMZAA==.',
Am='Amare:BAAALgAECgcJCgAAAA==.',
An='Ancalagon:BAAALgAECgQJCQAAAA==.Andros:BAAALgAECgYJDAAAAA==.Anekaatwo:BAAALgADCgEJAQAAAA==.Antigone:BAAALgAECgYJCwAAAA==.',
Ar='Araxe:BAABLgAECn8iAAMFAAYJdhvFagB8AQAFAAYJTRrFagB8AQAEAAQJoxa8JgAFAQAAAA==.Arroyo:BAABLgAECn8oAAMFAAkJ2x9xFgCtAgAFAAkJwx9xFgCtAgAEAAQJyRufHgBSAQAAAA==.Artax:BAAALgADCgYJDAAAAA==.',
As='Asalohir:BAAALgAECgEJAQAAAA==.Askadar:BAACLgAFFH8PAAIGAAQJpSbTBQC6AQAGAAQJpSbTBQC6AQAuAAQKfy8AAgYACQlyJqQAAGgDAAYACQlyJqQAAGgDAAAA.',
At='Atinyhorse:BAABLgAECn8ZAAIHAAcJ3AsXgwD8AAAHAAcJ3AsXgwD8AAAAAA==.Atrax:BAABLgAECn8VAAIIAAcJ+A0sNwBaAQAIAAcJ+A0sNwBaAQAAAA==.Atryx:BAABLgAFFH8JAAIJAAMJBhUhFgDbAAAJAAMJBhUhFgDbAAAAAA==.',
Au='Auronralius:BAAALgADCgIJAgAAAA==.',
Ax='Ax:BAAALgADCgcJCgABLgAECgYJDQAKAAAAAA==.',
Az='Azazél:BAAALgAECgIJAgAAAA==.Azuleja:BAAALgADCgEJAQAAAA==.Azzura:BAAALgADCgYJBwAAAA==.',
Ba='Baheem:BAAALgAECgUJEAAAAA==.Bams:BAABLgAECn8cAAMLAAgJZBzqKwB9AQALAAYJzB3qKwB9AQAMAAgJzAvfSQBrAQAAAA==.Baneofdemons:BAAALgADCgEJAQAAAA==.Barrillon:BAAALgADCgEJAQAAAA==.Bastile:BAAALgAECgYJDwAAAA==.Bauer:BAAALgAECgQJBAAAAA==.',
Be='Benel:BAAALgAECggJEgAAAA==.',
Bi='Bifrons:BAAALgADCgMJAwAAAA==.Bigblkengery:BAAALgADCgcJCAAAAA==.Bigdill:BAAALgAECgEJAQAAAA==.Biggrippa:BAABLgAECn8lAAINAAkJcCBJGwByAgANAAkJcCBJGwByAgAAAA==.Bighoofprint:BAAALgAECgkJAQAAAA==.Bigtotempole:BAAALgAECggJEgAAAA==.',
Bj='Bjornar:BAAALgADCgEJAQAAAA==.',
Bl='Blahwithpets:BAABLgAECn8sAAIOAAkJtxbFKAAlAgAOAAkJtxbFKAAlAgAAAA==.Blappin:BAAALgADCgYJDgAAAA==.Bloodmyst:BAAALgAECgcJCwABLgAECgkJIAAPAEQcAA==.Bloodymaw:BAAALgAECgQJBAAAAA==.Bloomer:BAAALgADCgEJAQAAAA==.Blooshield:BAAALgAECgUJBQAAAA==.Bluemchen:BAAALgADCgMJAwAAAA==.Blurt:BAAALgAECgEJAQAAAA==.',
Bo='Bobble:BAABLgAECn8dAAIIAAgJYRmCHwDxAQAIAAgJYRmCHwDxAQAAAA==.Bohelranus:BAAALgADCgkJFwAAAA==.Boneman:BAAALgAECgUJBQAAAA==.Bookwyrm:BAAALgADCgcJCwAAAA==.Boolil:BAAALgAECgQJCQABLgAECgkJLgAQAIYRAA==.Boolove:BAAALgAECgIJAgAAAA==.Booqt:BAAALgAECggJCAABLgAECgkJLgAQAIYRAA==.',
Br='Breake:BAACLgAFFH8IAAIRAAMJUwpcKwC+AAARAAMJUwpcKwC+AAAuAAQKfx8AAxEACAmlF3EUABkCABEACAmlF3EUABkCABIAAgntBUVpAE8AAAAA.',
Bu='Bubblebreath:BAAALgAECgEJAQAAAA==.',
By='Byssrak:BAABLgAECn8ZAAMTAAcJ9hHeMwBCAQATAAcJxRHeMwBCAQAUAAQJ8g0REgDVAAAAAA==.',
Ca='Caladiir:BAAALgAECgUJBQABLgAECgkJHwACAEshAA==.Cattiebuzz:BAAALgAECgIJAwABLgAECgkJNAAOAGMeAA==.',
Ce='Cerealmilk:BAABLgAECn8VAAIVAAcJWxprCwARAgAVAAcJWxprCwARAgABLgAECggJHAAGAKEaAA==.',
Ch='Chadd:BAAALgADCgYJBgABLgAECgQJBgAKAAAAAA==.Childishbro:BAAALgAECgEJAQAAAA==.Chilla:BAAALgAECgMJAwAAAA==.Chitung:BAAALgADCgQJBAABLgAECgQJBAAKAAAAAA==.Chopshop:BAAALgAECgEJAQAAAA==.Christopher:BAACLgAFFH8SAAIDAAUJAB9dNwBkAQADAAUJAB9dNwBkAQAuAAQKfxsAAgMACQn2IJwtALsCAAMACQn2IJwtALsCAAAA.',
Ci='Cialismaxing:BAAALgAECggJDQABLgAECggJGQABAMwNAA==.Cindragos:BAAALgAECgQJBQABLgAECgUJDQAKAAAAAA==.',
Co='Cocofluff:BAACLgAFFH8mAAIGAAcJQCUPAQCSAgAGAAcJQCUPAQCSAgAuAAQKfyUAAgYACAkAIiEEAAoDAAYACAkAIiEEAAoDAAAA.',
Cr='Creed:BAAALgAECgEJAQAAAA==.Creepychaos:BAAALgADCgkJKwABLgAECggJOgAFAJMHAA==.Creepydemise:BAABLgAECn86AAIFAAgJkwf8hQBDAQAFAAgJkwf8hQBDAQAAAA==.Creepydrunk:BAAALgADCgEJAQABLgAECggJOgAFAJMHAA==.Creepyfoxxy:BAAALgADCgkJCQAAAA==.Croixsmash:BAABLgAECn8eAAINAAgJzRhGIgBDAgANAAgJzRhGIgBDAgAAAA==.Croixtemplar:BAAALgAECgUJBQAAAA==.',
Cu='Cuculain:BAAALgAECgEJAwAAAA==.Custodian:BAAALgAECgQJBAAAAA==.Cuttinglass:BAAALgADCgcJBwAAAA==.',
Cy='Cytherea:BAAALgADCgcJDAAAAA==.',
Da='Daedra:BAAALgAECgQJBgAAAA==.Danoa:BAAALgAECgQJCgAAAA==.Daraellea:BAAALgAECgUJBQAAAA==.Darkcross:BAAALgADCgUJCAAAAA==.Darthorak:BAABLgAECn8cAAQWAAcJ1QacHwCYAAAXAAYJ9Qb4sADXAAAWAAYJ+QScHwCYAAAYAAMJDwYfKgBcAAAAAA==.Darthzai:BAAALgAECgMJAwAAAA==.Davennial:BAABLgAECn85AAIQAAgJ1BIAZgCKAQAQAAgJ1BIAZgCKAQAAAA==.Dawnn:BAAALgAECgYJEgAAAA==.Dayman:BAAALgAFFAEJAgAAAA==.',
De='Deanwnchestr:BAABLgAECn8gAAIDAAgJcQhSkwA2AQADAAgJcQhSkwA2AQAAAA==.Deathmamba:BAAALgADCgMJAwAAAA==.Deatnshadow:BAABLgAFFH8FAAIEAAMJbBjqHADXAAAEAAMJbBjqHADXAAAAAA==.Demise:BAAALgAECgQJCAAAAA==.Demonberry:BAAALgADCgEJAgAAAA==.Demonnutcase:BAAALgADCgYJEAAAAA==.Derogatory:BAAALgADCgYJDQAAAA==.Desylla:BAAALgADCgQJBAAAAA==.Devildograh:BAAALgAECgQJBwAAAA==.',
Di='Diah:BAAALgAECgQJBwAAAA==.Dibinator:BAAALgADCgEJAQAAAA==.Dio:BAAALgADCgYJDQAAAA==.Diodata:BAAALgAECgEJAgABLgAECggJHQABAKohAA==.Diophantus:BAAALgAECgIJBQABLgAECggJHQABAKohAA==.Divinity:BAAALgAECgEJAQAAAA==.',
Dm='Dmncgdss:BAAALgAECgYJDQAAAA==.',
Do='Dogeatdog:BAAALgADCgcJCwAAAA==.Doregoran:BAABLgAECn8jAAIWAAgJgxL/CQCHAQAWAAgJgxL/CQCHAQAAAA==.Dovairous:BAABLgAECn8dAAIZAAgJrQrJUQA1AQAZAAgJrQrJUQA1AQAAAA==.',
Dr='Draakell:BAAALgAECgQJAwAAAA==.Dracopeet:BAABLgAECn8ZAAQTAAcJvwS4aAB1AAATAAUJ4wS4aAB1AAAVAAQJGwNEMQBQAAAUAAMJwQJcJQAsAAAAAA==.Drausella:BAAALgADCgUJCAAAAA==.Dregomalfoy:BAAALgAECgQJBAAAAA==.Drexor:BAAALgAECgMJAwAAAA==.',
Du='Dudè:BAAALgAECgMJAwAAAA==.',
Dv='Dvlzadvocate:BAAALgAECgYJEgAAAA==.',
['Dâ']='Dâggèr:BAAALgAECgUJDQAAAA==.',
['Dü']='Dürin:BAAALgAECgEJAgAAAA==.',
Ec='Echidna:BAABLgAECn8cAAIXAAYJXgpgqQDkAAAXAAYJXgpgqQDkAAAAAA==.',
Ed='Edict:BAAALgAECgEJAQAAAA==.',
El='Elawen:BAAALgAECgYJCAAAAA==.Elder:BAAALgAECgEJAgAAAA==.Eleblah:BAAALgADCgcJBwAAAA==.Elfkinn:BAACLgAFFH8aAAMaAAUJQx6ZEQBiAQAaAAUJQx6ZEQBiAQAZAAIJ+gAWXABMAAAuAAQKfyUAAxoACQmmHgsOAGQCABoACQmmHgsOAGQCABkABAlrBY+sAG0AAAAA.Elgund:BAAALgADCgQJBAAAAA==.Elivaniel:BAAALgAECgcJEAAAAA==.',
En='Enlargdcrit:BAAALgAECgMJAwAAAA==.',
Eq='Equinox:BAAALgADCgQJBAAAAA==.',
Er='Ericcdraven:BAABLgAECn8iAAINAAgJgQ6zMAB1AQANAAgJgQ6zMAB1AQAAAA==.Erodoria:BAABLgAECn8bAAMbAAgJCR7WDgAYAgAbAAcJAiHWDgAYAgAcAAUJ/hChEgAIAQAAAA==.',
Et='Eternalfire:BAAALgADCgcJDgABLgAECggJHAAaAG0XAA==.',
Ev='Eve:BAAALgAECgEJAQAAAA==.Eveliong:BAAALgADCgEJAQAAAA==.Evilobama:BAAALgAECgUJBgAAAA==.Evoke:BAAALgAFFAEJAQABLgAFFAQJEQAMAEEWAA==.',
Ex='Exzanthia:BAAALgAECgEJAwAAAA==.',
Ey='Eyln:BAABLgAECn8pAAIJAAkJMBirBQAxAgAJAAkJMBirBQAxAgAAAA==.',
Fa='Falkor:BAABLgAECn8pAAIVAAkJqBb2CgAbAgAVAAkJqBb2CgAbAgAAAA==.Fanir:BAAALgAECgcJBwAAAA==.Fatkid:BAAALgAECgcJCwAAAA==.Fayway:BAABLgAECn9DAAIZAAkJviGsBQBQAwAZAAkJviGsBQBQAwAAAA==.',
Fe='Ferral:BAABLgAECn8gAAIPAAkJRBxQBAChAgAPAAkJRBxQBAChAgAAAA==.Festukar:BAAALgAECgUJBwAAAA==.',
Fi='Filthypirate:BAABLgAECn8UAAIQAAgJARFSoAAbAQAQAAgJARFSoAAbAQAAAA==.Firepower:BAABLgAECn8fAAIDAAgJ5RehSwDhAQADAAgJ5RehSwDhAQABLgAECggJIAAPAJcTAA==.Fistatoosh:BAABLgAECn8iAAICAAgJUCSuBQDVAgACAAgJUCSuBQDVAgAAAA==.',
Fl='Florane:BAAALgAECgUJDAAAAA==.Flyingbotato:BAAALgADCgkJFQABLgAECggJIAAPAJcTAA==.',
Fr='Fries:BAECLgAFFH8FAAIdAAIJByNTEQBjAAAdAAIJByNTEQBjAAAuAAQKfxwAAx0ACQkBIvoBAPoCAB0ACQkBIvoBAPoCAAwABQkGDBh2ANoAAAEuAAUUBAkHABcApg8A.Fruits:BAAALgAECgYJBwAAAA==.',
Ga='Galdavin:BAABLgAECn8XAAIQAAgJnBqgKQB+AgAQAAgJnBqgKQB+AgAAAA==.Galenhaihi:BAAALgADCgUJBQAAAA==.Galexstrasza:BAAALgADCgYJBgABLgAECgUJDgAKAAAAAA==.Gallandia:BAAALgADCgEJAQABLgAECgUJDgAKAAAAAA==.Gallielynne:BAAALgAECgUJDgAAAA==.Gankdd:BAABLgAECn8UAAMNAAcJLhvkNwBSAQANAAcJxhnkNwBSAQAeAAMJnRvCHgD4AAAAAA==.Garnnt:BAAALgADCgkJEQAAAA==.',
Gi='Giggles:BAABLgAECn8jAAILAAgJ+hI3KACSAQALAAgJ+hI3KACSAQAAAA==.Gigglez:BAAALgADCggJCAAAAA==.Gimmothyjr:BAAALgAECgUJBgAAAA==.',
Gl='Glennspyder:BAAALgAECgQJCgABLgAECgQJEgAKAAAAAA==.',
Go='Gonzo:BAAALgAECgUJBQABLgAFFAQJEQAMAEEWAA==.',
Gr='Greenbean:BAABLgAFFH8QAAIHAAQJdg3qPwANAQAHAAQJdg3qPwANAQABLgAFFAUJGgAaAEMeAA==.Grelleth:BAAALgAECgIJAgAAAA==.Groddz:BAABLgAECn8VAAIHAAgJsgaCjQDmAAAHAAgJsgaCjQDmAAAAAA==.Grrum:BAABLgAECn8dAAQRAAcJXgtnMAA3AQARAAcJkQlnMAA3AQASAAQJDwfKVACUAAAfAAEJQBFEfgA0AAAAAA==.',
Ha='Haell:BAAALgAECgQJBAAAAA==.Hanjo:BAABLgAECn8tAAIGAAkJzyG0AwDjAgAGAAkJzyG0AwDjAgAAAA==.Hanoa:BAAALgAECgYJCgAAAA==.Harakiri:BAABLgAECn8UAAIMAAcJixUvNgCqAQAMAAcJixUvNgCqAQAAAA==.Hardare:BAABLgAECn8ZAAIBAAgJzA31JACvAQABAAgJzA31JACvAQAAAA==.Hatookorr:BAAALgAECgQJBAABLgAECggJIAAPAJcTAA==.Hayali:BAABLgAECn8iAAIHAAgJXRbQNgDUAQAHAAgJXRbQNgDUAQAAAA==.',
He='Helledrians:BAAALgAECgQJBgAAAA==.',
Hi='Hiawatha:BAAALgADCgcJAwAAAA==.',
Hm='Hmccrnglbery:BAAALgAECgMJBAABLgAECggJGQABAMwNAA==.',
Ho='Hottogo:BAAALgADCgcJBwAAAA==.',
Hw='Hwei:BAAALgADCgEJAQAAAA==.',
Hy='Hydé:BAAALgAECgEJAQABLgAECgkJHgAcAFggAA==.Hypatia:BAABLgAECn8dAAIBAAgJqiGzCwB0AgABAAgJqiGzCwB0AgAAAA==.',
['Hä']='Häxan:BAAALgAECgQJBAAAAA==.',
Ia='Iame:BAAALgADCgMJAwAAAA==.Iapetus:BAAALgADCgIJAgAAAA==.',
Ic='Icedchi:BAEBLgAECn8eAAICAAkJ3x9kFgBWAgACAAkJ3x9kFgBWAgAAAA==.',
In='Incite:BAABLgAECn8gAAMgAAkJaA8+CQCZAQAgAAkJZQ8+CQCZAQAhAAUJ+g2QQQAUAQAAAA==.',
Is='Ishvala:BAAALgADCgMJAwAAAA==.',
Ja='Jaland:BAAALgADCgMJAwAAAA==.Jarrel:BAAALgAECgIJBAAAAA==.',
Je='Jellybreak:BAABLgAECn81AAMaAAkJKRQyGQDqAQAaAAkJKRQyGQDqAQAiAAcJqQiWNACuAAAAAA==.',
Jo='Joeewee:BAAALgAECgYJBgAAAA==.Jonjud:BAAALgAECgYJDAAAAA==.',
Js='Jskimonkpo:BAAALgADCgUJCQAAAA==.',
Ju='Julius:BAAALgAFFAEJAQAAAA==.',
Jy='Jyrian:BAAALgADCgMJAwAAAA==.',
Ka='Kaanâ:BAABLgAECn8tAAIfAAkJWhzPBwDdAgAfAAkJWhzPBwDdAgAAAA==.Kaelei:BAAALgADCgkJKwAAAA==.Kamine:BAAALgAECgUJDwAAAA==.Kanyeeast:BAAALgAECgYJCgAAAA==.Kateblue:BAABLgAECn8rAAIaAAkJLRqiDgBcAgAaAAkJLRqiDgBcAgAAAA==.',
Ke='Kelcier:BAAALgADCgYJBgAAAA==.Kelser:BAABLgAECn8VAAMYAAcJ2B7FBAApAgAYAAcJ2B7FBAApAgAXAAMJoBXuxgDLAAAAAA==.Kensington:BAABLgAECn8hAAIgAAgJdgjXDABJAQAgAAgJdgjXDABJAQAAAA==.',
Ki='Kiku:BAABLgAECn8iAAITAAkJYiMYBQD6AgATAAkJYiMYBQD6AgAAAA==.Kikyou:BAAALgAECgYJBgABLgAECgkJIgATAGIjAA==.Kim:BAABLgAECn8cAAIjAAgJdg1BHgCbAQAjAAgJdg1BHgCbAQAAAA==.Kinrah:BAAALgADCgMJAwAAAA==.Kirandra:BAAALgADCgMJAwAAAA==.Kirëë:BAAALgAECggJCAAAAA==.Kissofdeáth:BAAALgAECgIJAwAAAA==.',
Ko='Korlock:BAABLgAECn8mAAQXAAkJAB4vNAA8AgAXAAgJGR0vNAA8AgAWAAEJAACvbAA7AAAYAAEJPRcpNQA4AAAAAA==.',
Kr='Kreepywife:BAAALgAECgYJCAAAAA==.Krelbelorll:BAAALgAECgEJAQAAAA==.Krowley:BAABLgAECn8eAAIMAAgJ2QpxUwBHAQAMAAgJ2QpxUwBHAQAAAA==.',
Ku='Kurast:BAAALgAECgIJAgABLgAECgkJKQAVAKgWAA==.Kuzan:BAACLgAFFH8RAAIDAAUJWB7aRQBBAQADAAUJWB7aRQBBAQAuAAQKfx8AAgMABwl3IfQ2AJgCAAMABwl3IfQ2AJgCAAAA.',
Kx='Kxwono:BAAALgAECgcJBwAAAA==.',
Ky='Kyoyama:BAAALgAECgMJBwABLgAECgkJHQAXAB4gAA==.',
La='Lacious:BAAALgADCgEJAQABLgAECgkJNAAOAGMeAA==.Ladýshinobu:BAABLgAECn8gAAIIAAcJfQy/QAApAQAIAAcJfQy/QAApAQAAAA==.Lananar:BAAALgADCgUJBQAAAA==.Layssaenna:BAAALgAECgYJCAAAAA==.',
Le='Leahu:BAABLgAECn82AAIkAAgJPBgnDgDHAQAkAAgJPBgnDgDHAQAAAA==.Lediaa:BAAALgAECgIJAgAAAA==.',
Li='Lifekiller:BAAALgAECgQJBgAAAA==.Lightark:BAAALgAECgEJAgAAAA==.Linekingz:BAAALgADCgEJAQAAAA==.Linetheshamy:BAAALgADCgYJBwAAAA==.Lineurathrot:BAAALgADCgYJCAAAAA==.Littlespyone:BAAALgAECgQJEgAAAA==.',
Lo='Locholovis:BAABLgAECn8tAAIWAAgJsBIGCgCHAQAWAAgJsBIGCgCHAQAAAA==.Locklicous:BAABLgAECn8VAAMYAAgJoBZjDwBGAQAXAAgJChJuVACTAQAYAAYJWxVjDwBGAQAAAA==.Longhorse:BAACLgAFFH8fAAIEAAUJZCKfDAByAQAEAAUJZCKfDAByAQAuAAQKfzEAAwQACQn4JMgFAOACAAQACQmpIsgFAOACAAUABgnhJc9WAK0BAAAA.Longknight:BAAALgAECgEJAQAAAA==.Longr:BAAALgAECgYJCwAAAA==.Lorna:BAABLgAECn8VAAIHAAcJYxGOZABEAQAHAAcJYxGOZABEAQAAAA==.Lorthimar:BAAALgAECgUJCgABLgAECgkJJgAXAAAeAA==.',
Lu='Lumi:BAAALgAECggJEwAAAA==.Luminarae:BAAALgADCgEJAQAAAA==.Luminouss:BAABLgAFFH8LAAIMAAUJThefFwB7AQAMAAUJThefFwB7AQABLgAFFAMJBgARAOcUAA==.Lumpia:BAABLgAFFH8IAAIHAAUJGBlnMgAzAQAHAAUJGBlnMgAzAQAAAA==.',
Ly='Lyrinir:BAABLgAECn8dAAMGAAkJ/hkjEQD2AQAGAAkJ/hkjEQD2AQAeAAEJigTadwAcAAAAAA==.Lyrium:BAABLgAECn8ZAAMcAAgJtRm8CgC4AQAcAAUJDR+8CgC4AQAbAAcJ+RBRJAAxAQABLgAECgkJHQAGAP4ZAA==.',
Ma='Madar:BAABLgAECn8UAAIXAAYJJQaDugDHAAAXAAYJJQaDugDHAAAAAA==.Maggus:BAAALgADCgQJBAAAAA==.Magicgal:BAAALgAECgUJCAAAAA==.Maiden:BAAALgAECgUJBQAAAA==.Maiklytzwhet:BAAALgAECgUJBQAAAA==.Mairon:BAAALgAECgMJBgAAAA==.Malvorak:BAABLgAECn8iAAIEAAgJHhAmHgBLAQAEAAgJHhAmHgBLAQAAAA==.Mande:BAAALgADCgQJBAAAAA==.Mantis:BAAALgAECgkJCgABLgAECgkJKQAVAKgWAA==.Marrock:BAAALgAECgYJDgAAAA==.Marzipain:BAAALgAECgEJAQAAAA==.Mavarasie:BAAALgAECgUJDgAAAA==.Mavaressy:BAAALgAECgMJAwAAAA==.',
Mc='Mcmuffin:BAAALgAECgUJDQAAAA==.',
Me='Mechacattie:BAABLgAECn80AAIOAAkJYx6pEAC3AgAOAAkJYx6pEAC3AgAAAA==.Mediator:BAAALgAECgEJAQAAAA==.Meekerz:BAAALgAECgIJAgAAAA==.Mega:BAAALgAFFAIJAwAAAA==.Melganis:BAAALgADCgMJBAAAAA==.Melissandra:BAABLgAECn8kAAMSAAgJOQwiMQA2AQASAAgJOQwiMQA2AQAfAAIJiAb1dABVAAAAAA==.Mercas:BAAALgAECgcJDwABLgAECgkJJgAiAKMaAA==.Mezi:BAABLgAECn82AAIfAAkJkyAGBgAFAwAfAAkJkyAGBgAFAwAAAA==.Mezmera:BAAALgADCgUJBgABLgAECgIJAwAKAAAAAA==.',
Mh='Mhonster:BAAALgAECgYJBgABLgAECgcJBwAKAAAAAA==.',
Mi='Missed:BAAALgAECgQJBQAAAA==.Mittens:BAACLgAFFH8GAAIRAAMJ5xTmJgDdAAARAAMJ5xTmJgDdAAAuAAQKfxkAAx8ACQlbGXQoAK0BAB8ABgn7GXQoAK0BABEABwlvE8ohAIUBAAAA.',
Mo='Mofro:BAAALgADCgQJBAABLgAECgQJBAAKAAAAAA==.Mokgunal:BAAALgADCgQJBAAAAA==.Money:BAAALgADCgIJAgABLgAECggJIwAQABghAA==.Moneyshotinc:BAAALgAECgkJCgABLgAECggJIwAQABghAA==.Moraine:BAAALgAECgQJBAAAAA==.Moreki:BAAALgAECgMJAwAAAA==.Morro:BAABLgAECn8qAAILAAgJcA5OMwBUAQALAAgJcA5OMwBUAQAAAA==.',
Ms='Msvelvet:BAAALgADCgkJGgABLgAECgMJBgAKAAAAAA==.',
Mu='Mugiwara:BAACLgAFFH8LAAIBAAQJbCSCCAB0AQABAAQJbCSCCAB0AQAuAAQKfxYAAgEABwntJAkKANcCAAEABwntJAkKANcCAAAA.Mulron:BAABLgAECn8gAAIkAAgJjBB+FQBgAQAkAAgJjBB+FQBgAQAAAA==.',
My='Myrica:BAAALgAECgQJBwAAAA==.',
['Mö']='Mööve:BAAALgAECgMJAwAAAA==.',
Na='Nallos:BAAALgADCgEJAQAAAA==.Natajapar:BAAALgAECgEJAQABLgAECgcJCQAKAAAAAA==.',
Ne='Nefesh:BAABLgAFFH8NAAIHAAUJCwjBSADzAAAHAAUJCwjBSADzAAAAAA==.Neff:BAAALgADCgMJAwAAAA==.',
Ni='Nightingales:BAAALgAECgMJAwAAAA==.',
Ny='Nyomie:BAAALgADCgEJAgAAAA==.Nyyx:BAAALgAECgQJBAAAAA==.',
Oa='Oakenshíeld:BAACLgAFFH8VAAIaAAYJ4BHtEwBOAQAaAAYJ4BHtEwBOAQAuAAQKfzsAAhoACQlCF9AUAGsCABoACQlCF9AUAGsCAAAA.',
Ob='Obama:BAAALgADCgQJBAAAAA==.',
Og='Oggy:BAAALgAECgkJCwABLgAECgkJKQAVAKgWAA==.',
Ol='Olkwon:BAAALgAECgYJDAAAAA==.',
On='Onlyfeigns:BAAALgAECgIJAgAAAA==.',
Oo='Oozwoz:BAAALgAECgUJCQAAAA==.',
Or='Orileluu:BAAALgADCgYJFQAAAA==.',
Ox='Oxwon:BAAALgAECgYJCwAAAA==.',
Pa='Paisho:BAAALgAECgQJBQAAAA==.Palliera:BAAALgAECgQJBAAAAA==.Pallirot:BAAALgAECggJCAAAAA==.Pallynomial:BAAALgADCgcJCgAAAA==.Pawmuck:BAABLgAECn8fAAIQAAgJhhdoQgDnAQAQAAgJhhdoQgDnAQAAAA==.',
Pe='Peer:BAAALgAECgEJAgAAAA==.Pewpewtazarz:BAAALgAECgQJBQAAAA==.',
Ph='Phancy:BAAALgADCggJDgAAAA==.Phrizzle:BAAALgADCgMJAwAAAA==.',
Pl='Plaguebeard:BAABLgAECn8XAAMFAAcJBx9/PABFAgAFAAcJBx9/PABFAgAEAAUJCRiiJwABAQAAAA==.Plagueblade:BAABLgAECn8pAAMEAAkJUxm9DwDzAQAEAAkJOhi9DwDzAQAFAAEJ3Rp8MQFNAAAAAA==.',
Po='Podtinder:BAAALgAECgcJBwABLgAECgkJKQAVAKgWAA==.Poof:BAAALgAECgYJCgABLgAECggJHAAGAKEaAA==.Poseidon:BAAALgAECgIJAgAAAA==.',
Pr='Prescription:BAAALgAECggJEQAAAA==.Progression:BAAALgAECgEJBQAAAA==.',
Pu='Punish:BAAALgAECgEJAQAAAA==.',
Py='Pyrolord:BAAALgADCgYJCAAAAA==.',
Ra='Ragingrain:BAABLgAECn8eAAIkAAcJExnBEACfAQAkAAcJExnBEACfAQAAAA==.Rainthefire:BAABLgAECn8/AAIOAAkJZRp8JQA1AgAOAAkJZRp8JQA1AgAAAA==.Ralthor:BAAALgADCgMJAwAAAA==.Rassarudk:BAAALgAECgYJCwAAAA==.Ravinfire:BAAALgAECgQJBwAAAA==.Rawktuah:BAAALgAECgMJAwAAAA==.',
Re='Realhelz:BAAALgAECgQJBQAAAA==.Redcross:BAAALgAECgUJCAAAAA==.Redoxx:BAAALgAECgYJDQAAAA==.Restofarian:BAACLgAFFH8RAAIMAAQJQRaKLAANAQAMAAQJQRaKLAANAQAuAAQKfx0AAgwACQlKG0UXAFsCAAwACQlKG0UXAFsCAAAA.',
Ri='Rianon:BAAALgADCgkJEgABLgAECggJJgAHAHkZAA==.Rift:BAAALgAECgEJAwAAAA==.Righteous:BAABLgAECn8iAAIfAAcJRRyHFQARAgAfAAcJRRyHFQARAgAAAA==.Rizzy:BAABLgAECn8XAAMFAAkJkQ6NYQCSAQAFAAkJ7giNYQCSAQAEAAYJ8BLjJAASAQAAAA==.',
Ro='Rollinsinc:BAAALgAECgkJAwAAAA==.Roshin:BAAALgAECgEJAgAAAA==.Rotinlock:BAAALgADCgYJDAAAAA==.Rotinshot:BAACLgAFFH8OAAMOAAQJwBJVMwAvAQAOAAQJwBJVMwAvAQAjAAIJbgNAJwB8AAAuAAQKfygAAw4ACQlsIWUWAIUCAA4ACAmTImUWAIUCACMACAl0GuEQALYBAAAA.',
Ru='Ruin:BAAALgAECgMJBAAAAA==.Rutikee:BAABLgAECn84AAIZAAgJCBRHLwDUAQAZAAgJCBRHLwDUAQAAAA==.',
Sa='Sacerdos:BAABLgAECn8VAAIfAAgJlBW8FgAmAgAfAAgJlBW8FgAmAgABLgAECgkJOgAXAAEbAA==.Saeris:BAAALgADCggJCAABLgAECgYJDQAKAAAAAA==.Sagordez:BAABLgAECn8gAAQlAAgJSBuVHgD9AQAlAAcJrBqVHgD9AQACAAcJOBUOJAB5AQABAAEJ4Q8OkAAvAAABLgAECgkJHgAcAFggAA==.Salima:BAAALgADCgMJAwAAAA==.Saltybrew:BAAALgADCgMJAwAAAA==.Sandrill:BAAALgAECgYJBgABLgAECggJIAAPAJcTAA==.Satorugojo:BAAALgAECgUJBgAAAA==.Savior:BAAALgAECgMJAwAAAA==.Sazed:BAAALgAECggJDgAAAA==.',
Sc='Scrom:BAAALgAECgIJAwAAAA==.',
Se='Seabush:BAAALgAECgEJAQAAAA==.Seastorm:BAAALgAECgEJAgAAAA==.Seeker:BAAALgAECgEJAQAAAA==.Seizon:BAAALgAECggJDAAAAA==.Semila:BAAALgAECgcJCQAAAA==.Sepulchure:BAAALgADCgMJAwAAAA==.Serina:BAAALgAECgMJAwABLgAECgkJKQAEAFMZAA==.Serom:BAABLgAECn8ZAAIZAAgJxhcMIQAsAgAZAAgJxhcMIQAsAgAAAA==.Sesshomaaru:BAAALgADCggJEQAAAA==.',
Sh='Shaazrah:BAABLgAECn8fAAICAAkJSyEaCQCQAgACAAkJSyEaCQCQAgAAAA==.Shadowoak:BAAALgAECgEJAQAAAA==.Shadows:BAAALgADCgcJBwAAAA==.Shammyhagär:BAAALgADCgMJAwABLgAECgQJBAAKAAAAAA==.Sharalvia:BAAALgADCgUJCAAAAA==.Sharkn:BAAALgADCgcJDAAAAA==.Sherunn:BAABLgAECn8gAAIaAAcJXAt3OQARAQAaAAcJXAt3OQARAQAAAA==.Shifty:BAAALgAECgEJAgAAAA==.Shiftydon:BAABLgAECn8eAAQPAAkJ0RCfDQC5AQAPAAkJ0RCfDQC5AQAZAAIJ+Q28oQBeAAAiAAEJMgsAagAhAAAAAA==.Shimakaze:BAABLgAECn8wAAIOAAkJQAveRQC4AQAOAAkJQAveRQC4AQAAAA==.Shirvana:BAAALgAECgQJBwABLgAECgcJCQAKAAAAAA==.Shooters:BAABLgAECn8YAAIjAAkJOx26DQDuAQAjAAkJOx26DQDuAQAAAA==.Shortbow:BAAALgADCgQJBgABLgAECgEJAgAKAAAAAA==.Shyminx:BAAALgADCgkJEgAAAA==.Shymistress:BAABLgAECn80AAIOAAgJlCGTFwCCAgAOAAgJlCGTFwCCAgAAAA==.Shåmmy:BAABLgAECn82AAIMAAkJ7hPwIwAdAgAMAAkJ7hPwIwAdAgAAAA==.',
Si='Simonezer:BAAALgAECgkJAwAAAA==.Sins:BAABLgAECn8mAAIaAAkJVR8ACADCAgAaAAkJVR8ACADCAgAAAA==.Sionell:BAAALgADCgQJBAAAAA==.',
Sk='Skiá:BAABLgAECn9DAAIPAAkJ4h4lAwDPAgAPAAkJ4h4lAwDPAgAAAA==.Skodoosh:BAAALgAECgEJAwAAAA==.Skrinkles:BAAALgAECgYJDQAAAA==.Skyrocket:BAAALgAECgIJAwAAAA==.',
Sl='Slashpoison:BAAALgADCgcJDgAAAA==.Slicedbread:BAACLgAFFH8UAAIIAAYJ/ByCDgCuAQAIAAYJ/ByCDgCuAQAuAAQKfycAAwgACQk7IOwOAJ4CAAgACQk7IOwOAJ4CABAABwkKG6BBACACAAAA.Slorth:BAACLgAFFH8GAAIFAAMJNBY4ggDdAAAFAAMJNBY4ggDdAAAuAAQKfyIAAgUACAkYGn5KABMCAAUACAkYGn5KABMCAAAA.',
Sm='Smallfrye:BAAALgADCgMJAwAAAA==.',
Sn='Snizzlaki:BAABLgAECn8+AAICAAkJQg8YHgCjAQACAAkJQg8YHgCjAQAAAA==.',
So='Sofa:BAAALgADCgkJDAAAAA==.Solaene:BAAALgAECgcJBwAAAA==.Soundsmystic:BAAALgADCgUJBQAAAA==.',
Sp='Sparkilies:BAAALgADCgYJBgAAAA==.Spicybreath:BAAALgAECgQJBAABLgAECgcJEQAKAAAAAA==.Spicydemon:BAAALgAECgcJEQAAAA==.Spicydrood:BAAALgAECgEJAQAAAA==.Spicytotems:BAAALgAECgEJAQAAAA==.Splaash:BAAALgAECgMJAwAAAA==.Splàsh:BAABLgAECn8aAAQMAAkJ3x8aBgAQAwAMAAkJ3x8aBgAQAwALAAUJrRPJZACaAAAdAAIJRg3zKgBnAAAAAA==.',
St='Starwolfy:BAAALgAECgUJBQAAAA==.Steakman:BAAALgADCgIJAgAAAA==.Stoneboot:BAAALgAECggJEwAAAA==.',
Su='Sumaria:BAABLgAECn8hAAISAAgJhwFgXQByAAASAAgJhwFgXQByAAAAAA==.',
Sw='Sweatycrits:BAAALgAECggJDQAAAA==.Sweetvixen:BAAALgAECgMJBgAAAA==.',
Sy='Sylvanasthot:BAAALgADCgYJDAAAAA==.',
Ta='Takbez:BAABLgAECn8gAAIPAAgJlxOSCwAGAgAPAAgJlxOSCwAGAgAAAA==.Tandria:BAAALgAECgUJBQAAAA==.Tarot:BAAALgADCgEJAQAAAA==.Taterhops:BAAALgADCgIJAgABLgAECgkJJQADAFQfAA==.Tattered:BAAALgADCgEJAQAAAA==.Tauru:BAABLgAECn8ZAAIZAAgJWBeRJgAHAgAZAAgJWBeRJgAHAgAAAA==.Tazale:BAAALgAECgYJBgABLgABCgMJBAAKAAAAAA==.',
Te='Teakaachu:BAAALgAECggJEgAAAA==.Terdanator:BAABLgAECn8dAAMdAAcJeBdLDwCdAQAdAAcJeBdLDwCdAQALAAEJLQZ2owAkAAAAAA==.Tetranis:BAAALgADCgQJBgAAAA==.',
Th='Thanathot:BAAALgADCgMJAwAAAA==.Thanatus:BAABLgAECn86AAQXAAkJARtTHQBmAgAXAAkJARtTHQBmAgAYAAQJyRARHAC8AAAWAAEJzgf2eAAqAAAAAA==.Themia:BAAALgADCgMJAwAAAA==.',
Ti='Tiari:BAABLgAECn8oAAMIAAkJCRscDAC4AgAIAAkJCRscDAC4AgAQAAYJ0AMX/QCbAAAAAA==.Timesink:BAAALgAECgQJBQAAAA==.Tisane:BAAALgAECgMJAwAAAA==.',
Tn='Tntclepriest:BAAALgAECgcJDQABLgAECgYJFAAYAGkVAA==.',
Tr='Tralline:BAAALgADCgMJAgAAAA==.Tranzig:BAAALgADCgUJBQAAAA==.Tridius:BAAALgAECggJEQAAAA==.Trollins:BAAALgAECgIJAgAAAA==.',
Tu='Turdanator:BAABLgAECn9IAAMSAAkJDhmaEAA4AgASAAkJDhmaEAA4AgAfAAcJ/gtsQQAzAQAAAA==.',
Tw='Twizzlers:BAAALgADCgEJAQAAAA==.',
Up='Upgraydd:BAAALgAECgIJBAABLgAECgcJEQAKAAAAAA==.',
Ur='Uraenus:BAAALgAECgcJEwAAAA==.Urahrotar:BAAALgADCgUJBgAAAA==.Uriah:BAABLgAECn8iAAIOAAgJphO1QgDCAQAOAAgJphO1QgDCAQAAAA==.Ursúla:BAABLgAFFH8HAAIXAAMJ6QxpbwDMAAAXAAMJ6QxpbwDMAAABLgAFFAUJGgAaAEMeAA==.Uryu:BAAALgAECgQJBAAAAA==.Urïah:BAAALgADCgkJIwABLgAECggJIgAOAKYTAA==.',
Ut='Utherr:BAABLgAFFH8FAAIQAAMJ6BrcTwDuAAAQAAMJ6BrcTwDuAAAAAA==.',
Va='Valaravaus:BAAALgAECgEJAwAAAA==.Valionandros:BAAALgAECgYJBwAAAA==.Vanaril:BAAALgAECgMJAwAAAA==.Vashirr:BAAALgAECgMJAwAAAA==.',
Ve='Veldonir:BAAALgAECgEJAQAAAA==.Vergus:BAAALgAECgQJBAAAAA==.',
Vi='Violin:BAAALgAECgIJAwABLgAECggJCQAKAAAAAA==.Violinmax:BAAALgAECgYJDQABLgAECggJCQAKAAAAAA==.Viral:BAAALgAFFAEJAQAAAA==.',
Vo='Voidnova:BAAALgAECgEJAQAAAA==.Vonnie:BAAALgAECgUJBQAAAA==.',
Vy='Vynlerinis:BAABLgAECn8eAAIcAAkJWCBYAgDIAgAcAAkJWCBYAgDIAgAAAA==.',
Wa='Wardestroyer:BAAALgAECggJEQAAAA==.Wardwhelp:BAABLgAECn8cAAIGAAgJoRrRDAAHAgAGAAgJoRrRDAAHAgAAAA==.',
Wi='Wifehaver:BAABLgAECn8oAAICAAkJuR8HEgATAgACAAkJuR8HEgATAgAAAA==.Winniedapoo:BAABLgAECn80AAIXAAgJ2BsFMQAIAgAXAAgJ2BsFMQAIAgAAAA==.Winterpaw:BAAALgAECgEJAQABLgAECgkJKQAEAFMZAA==.',
Wo='Wooloo:BAACLgAFFH8YAAQWAAcJChwfAwBvAQAXAAYJsx0cDQBzAQAWAAQJ+xgfAwBvAQAYAAEJAADKBABZAAAuAAQKfygAAxcACQmzJawMANsCABcACQmzJawMANsCABYABAlPHXogAE8BAAAA.',
Wu='Wurm:BAAALgAECgIJAgAAAA==.',
Xa='Xanagore:BAABLgAECn8mAAMNAAgJfSJxDACPAgANAAgJACJxDACPAgAGAAEJ0RZbSgA2AAAAAA==.Xanllan:BAAALgAECgQJBgAAAA==.Xanthecat:BAAALgAECgQJBAAAAA==.Xanzul:BAAALgAECgcJCgABLgAECggJJgANAH0iAA==.',
Xk='Xkwon:BAAALgAFFAEJAQAAAA==.Xkwøn:BAACLgAFFH8VAAImAAQJ3hpGAwBXAQAmAAQJ3hpGAwBXAQAuAAQKfzsAAiYACAkbImwCAIcCACYACAkbImwCAIcCAAAA.',
Xu='Xunie:BAABLgAECn8dAAIFAAgJmxFmXACeAQAFAAgJmxFmXACeAQAAAA==.',
Xx='Xximage:BAABLgAECn8dAAMnAAkJ1CRfAQDIAgAnAAkJ1CRfAQDIAgADAAEJAACeWgFLAAAAAA==.',
Yu='Yulìe:BAAALgADCgcJBwAAAA==.',
Za='Zaibloom:BAAALgADCggJFgAAAA==.Zana:BAABLgAECn8ZAAIHAAgJPRLBbAAvAQAHAAgJPRLBbAAvAQAAAA==.Zaretan:BAAALgADCgcJDgAAAA==.',
Zb='Zbrute:BAABLgAECn8gAAIOAAgJ6RZXQgDDAQAOAAgJ6RZXQgDDAQAAAA==.',
Ze='Zeffen:BAAALgAECgIJBAABLgAECgYJFAAXACUGAA==.Zefphenn:BAAALgAECgQJBgABLgAECgYJFAAXACUGAA==.Zenny:BAAALgADCggJEwAAAA==.',
Zi='Zivz:BAAALgADCgUJBQAAAA==.',
Zo='Zokohjin:BAABLgAECn8kAAMFAAkJWByIJwBQAgAFAAkJWByIJwBQAgAEAAEJqRzWSgBMAAAAAA==.',
Zu='Zulpher:BAAALgADCgQJBAAAAA==.',
['Ðo']='Ðondon:BAAALgADCgQJBQAAAA==.Ðoppelgänger:BAAALgAECgEJBQAAAA==.',
['Øk']='Økwøn:BAACLgAFFH8PAAIDAAMJGBWOOQC3AAADAAMJGBWOOQC3AAAuAAQKfzcAAgMACAn4HiJKAFkCAAMACAn4HiJKAFkCAAAA.',
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
