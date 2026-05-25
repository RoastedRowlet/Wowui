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

local lookup = {'Monk-Windwalker','Monk-Brewmaster','Mage-Frost','DeathKnight-Blood','DeathKnight-Unholy','Warrior-Protection','DemonHunter-Devourer','Hunter-Marksmanship','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','Hunter-BeastMastery','Druid-Feral','Paladin-Holy','Paladin-Retribution','Priest-Discipline','Evoker-Augmentation','Evoker-Devastation','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Restoration','Evoker-Preservation','Druid-Balance','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','Priest-Shadow','Priest-Holy','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','Hunter-Survival','Paladin-Protection','Monk-Mistweaver','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Absolon:BAAALgAECgQJBAAAAA==.Absólon:BAAALgADCgcJBwAAAA==.',
Ae='Aendia:BAAALgADCgIJAwAAAA==.Aeolos:BAAALgAECgUJBQAAAA==.',
Af='Affae:BAABLgAFFH8KAAMBAAMJFBOtJACIAAACAAIJ6RYiOgCPAAABAAIJPg6tJACIAAAAAA==.',
Ag='Agrios:BAAALgAECgUJBgAAAA==.',
Ak='Ak:BAABLgAECn8oAAIDAAgJZSApKgBVAgADAAgJZSApKgBVAgAAAA==.',
Al='Alanas:BAAALgADCgEJAQAAAA==.Alcohlol:BAAALgADCgEJAQAAAA==.Allendril:BAAALgADCgIJAgABLgAECggJJQAEAPcYAA==.',
Am='Amare:BAAALgAECgcJCgAAAA==.',
An='Ancalagon:BAAALgAECgQJCQAAAA==.Andros:BAAALgAECgYJCwAAAA==.Anekaatwo:BAAALgADCgEJAQAAAA==.Antigone:BAAALgAECgYJCwAAAA==.',
Ar='Araxe:BAABLgAECn8iAAMFAAYJdhsmYwB+AQAFAAYJTRomYwB+AQAEAAQJoxZkIwAJAQAAAA==.Arroyo:BAABLgAECn8oAAMFAAkJ2x+sEwCyAgAFAAkJwx+sEwCyAgAEAAQJyRufHgBSAQAAAA==.Artax:BAAALgADCgYJDAAAAA==.',
As='Asalohir:BAAALgAECgEJAQAAAA==.Askadar:BAACLgAFFH8MAAIGAAQJlCa5BAC5AQAGAAQJlCa5BAC5AQAuAAQKfy8AAgYACQlyJncAAHEDAAYACQlyJncAAHEDAAAA.',
At='Atinyhorse:BAABLgAECn8ZAAIHAAcJ3AuwdwALAQAHAAcJ3AuwdwALAQAAAA==.Atrax:BAAALgAECgcJEQAAAA==.Atryx:BAABLgAFFH8GAAIIAAMJohQvEwDrAAAIAAMJohQvEwDrAAAAAA==.',
Ax='Ax:BAAALgADCgcJCgABLgAECgYJDQAJAAAAAA==.',
Az='Azazél:BAAALgAECgIJAgAAAA==.Azuleja:BAAALgADCgEJAQAAAA==.Azzura:BAAALgADCgMJAwAAAA==.',
Ba='Baheem:BAAALgAECgMJCwAAAA==.Bams:BAABLgAECn8cAAMKAAgJZBxGKAB/AQAKAAYJzB1GKAB/AQALAAgJzAvyQwBrAQAAAA==.Baneofdemons:BAAALgADCgEJAQAAAA==.Barrillon:BAAALgADCgEJAQAAAA==.Bastile:BAAALgAECgYJDwAAAA==.Bauer:BAAALgAECgQJBAAAAA==.',
Be='Benel:BAAALgAECggJEgAAAA==.',
Bi='Bifrons:BAAALgADCgMJAwAAAA==.Bigblkengery:BAAALgADCgcJCAAAAA==.Bigdill:BAAALgAECgEJAQAAAA==.Biggrippa:BAABLgAECn8lAAIMAAkJcCDyFgATAgAMAAkJcCDyFgATAgAAAA==.Bighoofprint:BAAALgADCgQJAwAAAA==.Bigtotempole:BAAALgAECggJEgAAAA==.',
Bj='Bjornar:BAAALgADCgEJAQAAAA==.',
Bl='Blahwithpets:BAABLgAECn8lAAINAAgJZxe1OADQAQANAAgJZxe1OADQAQAAAA==.Blappin:BAAALgADCgYJDgAAAA==.Bloodmyst:BAAALgAECgMJBwABLgAECgkJIAAOAEQcAA==.Bloodymaw:BAAALgAECgQJBAAAAA==.Bloomer:BAAALgADCgEJAQAAAA==.Blooshield:BAAALgAECgUJBQAAAA==.Bluemchen:BAAALgADCgMJAwAAAA==.Blurt:BAAALgAECgEJAQAAAA==.',
Bo='Bobble:BAABLgAECn8cAAIPAAgJ1BgdHgDqAQAPAAgJ1BgdHgDqAQAAAA==.Bohelranus:BAAALgADCgkJFwAAAA==.Boneman:BAAALgADCgQJBAAAAA==.Bookwyrm:BAAALgADCgUJBAAAAA==.Boolil:BAAALgAECgQJCQABLgAECgkJLgAQAIYRAA==.Booqt:BAAALgAECggJCAABLgAECgkJLgAQAIYRAA==.',
Br='Breake:BAACLgAFFH8FAAIRAAMJBArJJQDRAAARAAMJBArJJQDRAAAuAAQKfxsAAhEACAmlF5gSACICABEACAmlF5gSACICAAAA.',
Bu='Bubblebreath:BAAALgAECgEJAQAAAA==.',
By='Byssrak:BAABLgAECn8YAAMSAAcJ9hHjMABKAQASAAcJxRHjMABKAQATAAQJkw05FAClAAAAAA==.',
Ca='Caladiir:BAAALgAECgUJBQABLgAECgkJHwACAEshAA==.Cattiebuzz:BAAALgAECgIJAwABLgAECgkJLgANAMUdAA==.',
Ce='Cerealmilk:BAAALgAECgYJDQAAAA==.',
Ch='Chadd:BAAALgADCgYJBgABLgAECgQJBgAJAAAAAA==.Childishbro:BAAALgAECgEJAQAAAA==.Chilla:BAAALgAECgMJAwAAAA==.Chitung:BAAALgADCgQJBAABLgAECgQJBAAJAAAAAA==.Christopher:BAACLgAFFH8RAAIDAAUJAB8FMQBjAQADAAUJAB8FMQBjAQAuAAQKfxsAAgMACQn2IJwtALsCAAMACQn2IJwtALsCAAAA.',
Ci='Cialismaxing:BAAALgAECggJDQABLgAECggJGQABAMwNAA==.Cindragos:BAAALgAECgQJBQABLgAECgUJDQAJAAAAAA==.',
Co='Cocofluff:BAACLgAFFH8gAAIGAAcJNiQiAQBoAgAGAAcJNiQiAQBoAgAuAAQKfyUAAgYACAkAIiEEAAoDAAYACAkAIiEEAAoDAAAA.',
Cr='Creed:BAAALgAECgEJAQAAAA==.Creepychaos:BAAALgADCgkJKwABLgAECggJOAAFAJMHAA==.Creepydemise:BAABLgAECn84AAIFAAgJkwfmewBFAQAFAAgJkwfmewBFAQAAAA==.Creepydrunk:BAAALgADCgEJAQABLgAECggJOAAFAJMHAA==.Creepyfoxxy:BAAALgADCgkJCQAAAA==.Croixsmash:BAABLgAECn8eAAIMAAgJzRhGIgBDAgAMAAgJzRhGIgBDAgAAAA==.Croixtemplar:BAAALgAECgUJBQAAAA==.',
Cu='Cuculain:BAAALgAECgEJAgAAAA==.Custodian:BAAALgAECgQJBAAAAA==.Cuttinglass:BAAALgADCgcJBwAAAA==.',
Cy='Cytherea:BAAALgADCgcJDAAAAA==.',
Da='Daedra:BAAALgAECgQJBgAAAA==.Danoa:BAAALgAECgQJCgAAAA==.Daraellea:BAAALgAECgUJBQAAAA==.Darkcross:BAAALgADCgUJCAAAAA==.Darthorak:BAABLgAECn8cAAQUAAcJ1QZrHQCaAAAVAAYJ9QaGpwDbAAAUAAYJ+QRrHQCaAAAWAAMJDwZMJQBdAAAAAA==.Davennial:BAABLgAECn8yAAIQAAgJ1BL5WQCgAQAQAAgJ1BL5WQCgAQAAAA==.Dawnn:BAAALgAECgYJEgAAAA==.Dayman:BAAALgAFFAEJAgAAAA==.',
De='Deanwnchestr:BAABLgAECn8dAAIDAAcJQQi3oAAgAQADAAcJQQi3oAAgAQAAAA==.Deathmamba:BAAALgADCgMJAwAAAA==.Deatnshadow:BAAALgAFFAMJAwAAAA==.Demise:BAAALgAECgQJCAAAAA==.Demonberry:BAAALgADCgEJAgAAAA==.Demonnutcase:BAAALgADCgYJEAAAAA==.Derogatory:BAAALgADCgYJDQAAAA==.Desylla:BAAALgADCgQJBAAAAA==.Devildograh:BAAALgAECgQJBwAAAA==.',
Di='Diah:BAAALgAECgQJBwAAAA==.Dibinator:BAAALgADCgEJAQAAAA==.Dio:BAAALgADCgYJDQAAAA==.Diodata:BAAALgAECgEJAQABLgAECggJHQABAKohAA==.Diophantus:BAAALgAECgIJBQABLgAECggJHQABAKohAA==.Divinity:BAAALgAECgEJAQAAAA==.',
Dm='Dmncgdss:BAAALgAECgYJDQAAAA==.',
Do='Dogeatdog:BAAALgADCgIJAwAAAA==.Doregoran:BAABLgAECn8bAAIUAAgJGhCsCwBXAQAUAAgJGhCsCwBXAQAAAA==.Dovairous:BAABLgAECn8bAAIXAAgJHwrQTgAwAQAXAAgJHwrQTgAwAQAAAA==.',
Dr='Draakell:BAAALgAECgQJAwAAAA==.Dracopeet:BAABLgAECn8ZAAQSAAcJvwTwXgCOAAASAAUJ4wTwXgCOAAAYAAQJGwO6LgBQAAATAAMJwQLFIgAsAAAAAA==.Drausella:BAAALgADCgUJCAAAAA==.Dregomalfoy:BAAALgAECgQJBAAAAA==.Drexor:BAAALgAECgMJAwAAAA==.',
Du='Dudè:BAAALgADCgkJCQAAAA==.',
Dv='Dvlzadvocate:BAAALgAECgYJEgAAAA==.',
['Dâ']='Dâggèr:BAAALgAECgUJDQAAAA==.',
['Dü']='Dürin:BAAALgAECgEJAgAAAA==.',
Ec='Echidna:BAABLgAECn8cAAIVAAYJXgpQoADnAAAVAAYJXgpQoADnAAAAAA==.',
Ed='Edict:BAAALgAECgEJAQAAAA==.',
El='Elawen:BAAALgAECgYJBgAAAA==.Elder:BAAALgAECgEJAgAAAA==.Eleblah:BAAALgADCgcJBwAAAA==.Elfkinn:BAACLgAFFH8PAAMZAAQJZBIyGQAkAQAZAAQJZBIyGQAkAQAXAAEJTgCGZQAjAAAuAAQKfyUAAxkACQmmHogMAGgCABkACQmmHogMAGgCABcABAlrBY+sAG0AAAAA.Elgund:BAAALgADCgQJBAAAAA==.Elivaniel:BAAALgAECgcJDwAAAA==.',
En='Enlargdcrit:BAAALgAECgMJAwAAAA==.',
Eq='Equinox:BAAALgADCgQJBAAAAA==.',
Er='Ericcdraven:BAABLgAECn8cAAIMAAgJAA70LQBzAQAMAAgJAA70LQBzAQAAAA==.Erodoria:BAABLgAECn8bAAMaAAgJCR4WDQAeAgAaAAcJAiEWDQAeAgAbAAUJ/hA6EQAMAQAAAA==.',
Et='Eternalfire:BAAALgADCgcJDgABLgAECggJHAAZAG0XAA==.',
Ev='Eve:BAAALgAECgEJAQAAAA==.Eveliong:BAAALgADCgEJAQAAAA==.Evilobama:BAAALgAECgUJBgAAAA==.Evoke:BAAALgAFFAEJAQABLgAFFAQJDQALAEQSAA==.',
Ex='Exzanthia:BAAALgAECgEJAwAAAA==.',
Ey='Eyln:BAABLgAECn8mAAIIAAkJChbpBQAWAgAIAAkJChbpBQAWAgAAAA==.',
Fa='Falkor:BAABLgAECn8pAAIYAAkJqBb0CQAgAgAYAAkJqBb0CQAgAgAAAA==.Fanir:BAAALgAECgcJBwAAAA==.Fatkid:BAAALgAECgcJCQAAAA==.Fayway:BAABLgAECn87AAIXAAkJviH4BABSAwAXAAkJviH4BABSAwAAAA==.',
Fe='Ferral:BAABLgAECn8gAAIOAAkJRByxAwCtAgAOAAkJRByxAwCtAgAAAA==.Festukar:BAAALgAECgUJBwAAAA==.',
Fi='Filthypirate:BAABLgAECn8UAAIQAAgJARHdiwA4AQAQAAgJARHdiwA4AQAAAA==.Firepower:BAABLgAECn8fAAIDAAgJ5RdPRgDtAQADAAgJ5RdPRgDtAQABLgAECggJIAAOAJcTAA==.Fistatoosh:BAABLgAECn8iAAICAAgJUCT8BADYAgACAAgJUCT8BADYAgAAAA==.',
Fl='Florane:BAAALgAECgUJDAAAAA==.Flyingbotato:BAAALgADCgkJFQABLgAECggJIAAOAJcTAA==.',
Fr='Fries:BAECLgAFFH8FAAIcAAIJByP4DQBmAAAcAAIJByP4DQBmAAAuAAQKfxwAAxwACQkBIqsBAP4CABwACQkBIqsBAP4CAAsABQkGDB9tANoAAAEuAAUUBAkHABUApg8A.Fruits:BAAALgAECgYJBwAAAA==.',
Ga='Galdavin:BAABLgAECn8XAAIQAAgJnBqgKQB+AgAQAAgJnBqgKQB+AgAAAA==.Galenhaihi:BAAALgADCgUJBQAAAA==.Galexstrasza:BAAALgADCgYJBgABLgAECgUJDgAJAAAAAA==.Gallandia:BAAALgADCgEJAQABLgAECgUJDgAJAAAAAA==.Gallielynne:BAAALgAECgUJDgAAAA==.Gankdd:BAABLgAECn8UAAMMAAcJLhsbMwBYAQAMAAcJxhkbMwBYAQAdAAMJnRvCHgD4AAAAAA==.Garnnt:BAAALgADCgkJEQAAAA==.',
Gi='Giggles:BAABLgAECn8bAAIKAAgJwg6JMQBJAQAKAAgJwg6JMQBJAQAAAA==.Gigglez:BAAALgADCggJCAAAAA==.Gimmothyjr:BAAALgAECgUJBgAAAA==.',
Gl='Glennspyder:BAAALgAECgMJCQABLgAECgQJEgAJAAAAAA==.',
Gr='Greenbean:BAABLgAFFH8JAAIHAAQJBwaHRADtAAAHAAQJBwaHRADtAAABLgAFFAQJDwAZAGQSAA==.Groddz:BAABLgAECn8VAAIHAAgJsgbLgAD2AAAHAAgJsgbLgAD2AAAAAA==.Grrum:BAABLgAECn8dAAQRAAcJXguCKwBLAQARAAcJkQmCKwBLAQAeAAQJDwc0TACvAAAfAAEJQBFEfgA0AAAAAA==.',
Ha='Hanjo:BAABLgAECn8mAAIGAAgJASI1BgCIAgAGAAgJASI1BgCIAgAAAA==.Hanoa:BAAALgAECgYJCgAAAA==.Harakiri:BAABLgAECn8UAAILAAcJixUvNgCqAQALAAcJixUvNgCqAQAAAA==.Hardare:BAABLgAECn8ZAAIBAAgJzA31JACvAQABAAgJzA31JACvAQAAAA==.Hatookorr:BAAALgAECgQJBAABLgAECggJIAAOAJcTAA==.Hayali:BAABLgAECn8iAAIHAAgJXRanMgDbAQAHAAgJXRanMgDbAQAAAA==.',
He='Helledrians:BAAALgAECgQJBgAAAA==.',
Hi='Hiawatha:BAAALgADCgcJAwAAAA==.',
Hm='Hmccrnglbery:BAAALgAECgMJBAABLgAECggJGQABAMwNAA==.',
Ho='Hottogo:BAAALgADCgcJBwAAAA==.',
Hw='Hwei:BAAALgADCgEJAQAAAA==.',
Hy='Hypatia:BAABLgAECn8dAAIBAAgJqiFbCgB4AgABAAgJqiFbCgB4AgAAAA==.',
['Hä']='Häxan:BAAALgAECgQJBAAAAA==.',
Ia='Iame:BAAALgADCgMJAwAAAA==.Iapetus:BAAALgADCgIJAgAAAA==.',
Ic='Icedchi:BAEBLgAECn8dAAICAAkJ3x9kFgBWAgACAAkJ3x9kFgBWAgAAAA==.',
In='Incite:BAABLgAECn8gAAMgAAkJaA9vCACgAQAgAAkJZQ9vCACgAQAhAAUJ+g2QQQAUAQAAAA==.',
Is='Ishvala:BAAALgADCgMJAwAAAA==.',
Ja='Jaland:BAAALgADCgMJAwAAAA==.Jarrel:BAAALgAECgIJBAAAAA==.',
Je='Jellybreak:BAABLgAECn8yAAMZAAkJKBTjFgDtAQAZAAkJKBTjFgDtAQAiAAcJqQigLQCwAAAAAA==.',
Jo='Joeewee:BAAALgAECgYJBgAAAA==.Jonjud:BAAALgAECgYJDAAAAA==.',
Js='Jskimonkpo:BAAALgADCgUJCQAAAA==.',
Ju='Julius:BAAALgAFFAEJAQAAAA==.',
Jy='Jyrian:BAAALgADCgMJAwAAAA==.',
Ka='Kaanâ:BAABLgAECn8mAAIfAAgJ8B7PCAC5AgAfAAgJ8B7PCAC5AgAAAA==.Kaelei:BAAALgADCgkJKwAAAA==.Kamine:BAAALgAECgUJDQAAAA==.Kanyeeast:BAAALgAECgYJCgAAAA==.Kateblue:BAABLgAECn8kAAIZAAgJQBgLGADgAQAZAAgJQBgLGADgAQAAAA==.',
Ke='Kelcier:BAAALgADCgYJBgAAAA==.Kelser:BAABLgAECn8VAAMWAAcJ2B7FBAApAgAWAAcJ2B7FBAApAgAVAAMJoBXuxgDLAAAAAA==.Kensington:BAABLgAECn8hAAIgAAgJdgjMCwBPAQAgAAgJdgjMCwBPAQAAAA==.',
Ki='Kiku:BAABLgAECn8iAAISAAkJYiOnBAAFAwASAAkJYiOnBAAFAwAAAA==.Kikyou:BAAALgAECgYJBgABLgAECgkJIgASAGIjAA==.Kim:BAABLgAECn8cAAIjAAgJdg0JHACeAQAjAAgJdg0JHACeAQAAAA==.Kinrah:BAAALgADCgMJAwAAAA==.Kirandra:BAAALgADCgMJAwAAAA==.Kissofdeáth:BAAALgAECgEJAQAAAA==.',
Ko='Korlock:BAABLgAECn8mAAQVAAkJAB4vNAA8AgAVAAgJGR0vNAA8AgAWAAEJPRcWLQA/AAAUAAEJAACvbAA7AAAAAA==.',
Kr='Kreepywife:BAAALgAECgYJBwAAAA==.Krelbelorll:BAAALgAECgEJAQAAAA==.Krowley:BAABLgAECn8eAAILAAgJ2Qr/TABHAQALAAgJ2Qr/TABHAQAAAA==.',
Ku='Kuzan:BAACLgAFFH8RAAIDAAUJWB7qOgBNAQADAAUJWB7qOgBNAQAuAAQKfx8AAgMABwl3IfQ2AJgCAAMABwl3IfQ2AJgCAAAA.',
Kx='Kxwono:BAAALgAECgcJBwAAAA==.',
Ky='Kyoyama:BAAALgAECgMJBQABLgAECggJHAAVAB4gAA==.',
La='Lacious:BAAALgADCgEJAQABLgAECgkJLgANAMUdAA==.Ladýshinobu:BAABLgAECn8gAAIPAAcJfQwDPQAqAQAPAAcJfQwDPQAqAQAAAA==.Lananar:BAAALgADCgUJBQAAAA==.Layssaenna:BAAALgAECgYJCAAAAA==.',
Le='Leahu:BAABLgAECn8yAAIkAAgJEhhYDQDAAQAkAAgJEhhYDQDAAQAAAA==.Lediaa:BAAALgADCgcJBwAAAA==.',
Li='Lightark:BAAALgAECgEJAgAAAA==.Linekingz:BAAALgADCgEJAQAAAA==.Linetheshamy:BAAALgADCgYJBwAAAA==.Lineurathrot:BAAALgADCgYJCAAAAA==.Littlespyone:BAAALgAECgQJEgAAAA==.',
Lo='Locholovis:BAABLgAECn8qAAIUAAgJXRIeCQCJAQAUAAgJXRIeCQCJAQAAAA==.Locklicous:BAABLgAECn8VAAMWAAgJoBZsDQBOAQAVAAgJChJaTgCZAQAWAAYJWxVsDQBOAQAAAA==.Longhorse:BAACLgAFFH8eAAIEAAUJRyFICwBsAQAEAAUJRyFICwBsAQAuAAQKfzEAAwQACQn4JMgFAOACAAQACQmpIsgFAOACAAUABgnhJRVQAK8BAAAA.Longknight:BAAALgAECgEJAQAAAA==.Longr:BAAALgAECgYJCwAAAA==.Lorna:BAABLgAECn8VAAIHAAcJYxG8XQBLAQAHAAcJYxG8XQBLAQAAAA==.Lorthimar:BAAALgAECgUJCgABLgAECgkJJgAVAAAeAA==.',
Lu='Lumi:BAAALgAECggJEgAAAA==.Luminarae:BAAALgADCgEJAQAAAA==.Luminouss:BAABLgAFFH8LAAILAAUJThf+EQCLAQALAAUJThf+EQCLAQABLgAFFAMJBgARAOcUAA==.Lumpia:BAABLgAFFH8IAAIHAAUJGBlRKgA+AQAHAAUJGBlRKgA+AQAAAA==.',
Ly='Lyrinir:BAABLgAECn8dAAMGAAkJ/hmnEQCmAQAGAAkJ/hmnEQCmAQAdAAEJigRNbAAdAAAAAA==.Lyrium:BAABLgAECn8ZAAMbAAgJtRm8CgC4AQAbAAUJDR+8CgC4AQAaAAcJ+RDcIAA2AQABLgAECgkJHQAGAP4ZAA==.',
Ma='Madar:BAABLgAECn8UAAIVAAYJJQaRsADKAAAVAAYJJQaRsADKAAAAAA==.Maggus:BAAALgADCgQJBAAAAA==.Magicgal:BAAALgAECgUJCAAAAA==.Maiden:BAAALgAECgUJBQAAAA==.Maiklytzwhet:BAAALgAECgUJBQAAAA==.Mairon:BAAALgAECgMJBgAAAA==.Malvorak:BAABLgAECn8gAAIEAAcJRRJvHgAxAQAEAAcJRRJvHgAxAQAAAA==.Mande:BAAALgADCgQJBAAAAA==.Mantis:BAAALgAECgkJCgABLgAECgkJKQAYAKgWAA==.Marrock:BAAALgAECgQJBQAAAA==.Marzipain:BAAALgAECgEJAQAAAA==.Mavarasie:BAAALgAECgUJDQAAAA==.',
Mc='Mcmuffin:BAAALgAECgUJDAAAAA==.',
Me='Mechacattie:BAABLgAECn8uAAINAAkJxR0lEACoAgANAAkJxR0lEACoAgAAAA==.Mediator:BAAALgAECgEJAQAAAA==.Meekerz:BAAALgAECgIJAgAAAA==.Mega:BAAALgAFFAIJAwAAAA==.Melganis:BAAALgADCgMJBAAAAA==.Melissandra:BAABLgAECn8kAAMeAAgJOQxzKwBQAQAeAAgJOQxzKwBQAQAfAAIJiAb1dABVAAAAAA==.Mercas:BAAALgAECgcJDwABLgAECgkJJgAiAKMaAA==.Mezi:BAABLgAECn8zAAIfAAkJkyAUBQAOAwAfAAkJkyAUBQAOAwAAAA==.Mezmera:BAAALgADCgUJBgABLgAECgEJAQAJAAAAAA==.',
Mh='Mhonster:BAAALgAECgYJBgAAAA==.',
Mi='Missed:BAAALgAECgQJBQAAAA==.Mittens:BAACLgAFFH8GAAIRAAMJ5xTpIQDvAAARAAMJ5xTpIQDvAAAuAAQKfxkAAx8ACQlbGXQoAK0BAB8ABgn7GXQoAK0BABEABwlvE8ohAIUBAAAA.',
Mo='Mofro:BAAALgADCgQJBAABLgAECgQJBAAJAAAAAA==.Mokgunal:BAAALgADCgQJBAAAAA==.Money:BAAALgADCgIJAgABLgAECggJIwAQABghAA==.Moneyshotinc:BAAALgAECgkJCgABLgAECggJIwAQABghAA==.Moraine:BAAALgAECgQJBAAAAA==.Moreki:BAAALgAECgMJAwAAAA==.Morro:BAABLgAECn8dAAIKAAgJHg4YMwBBAQAKAAgJHg4YMwBBAQAAAA==.',
Ms='Msvelvet:BAAALgADCgkJGgABLgAECgMJBgAJAAAAAA==.',
Mu='Mugiwara:BAACLgAFFH8LAAIBAAQJbCSEBgB8AQABAAQJbCSEBgB8AQAuAAQKfxYAAgEABwntJAkKANcCAAEABwntJAkKANcCAAAA.Mulron:BAABLgAECn8gAAIkAAgJjBCqEwBjAQAkAAgJjBCqEwBjAQAAAA==.',
My='Myrica:BAAALgAECgQJBwAAAA==.',
['Mö']='Mööve:BAAALgAECgMJAwAAAA==.',
Na='Nallos:BAAALgADCgEJAQAAAA==.Natajapar:BAAALgAECgEJAQABLgAECgcJCQAJAAAAAA==.',
Ne='Nefesh:BAABLgAFFH8IAAIHAAQJQQWCRADtAAAHAAQJQQWCRADtAAAAAA==.Neff:BAAALgADCgMJAwAAAA==.',
Ni='Nightingales:BAAALgAECgMJAwAAAA==.',
Ny='Nyomie:BAAALgADCgEJAgAAAA==.Nyyx:BAAALgAECgQJBAAAAA==.',
Oa='Oakenshíeld:BAACLgAFFH8TAAIZAAUJ2RTgGAAlAQAZAAUJ2RTgGAAlAQAuAAQKfzsAAhkACQlCF9AUAGsCABkACQlCF9AUAGsCAAAA.',
Ob='Obama:BAAALgADCgQJBAAAAA==.',
Og='Oggy:BAAALgAECgkJCgABLgAECgkJKQAYAKgWAA==.',
Ol='Olkwon:BAAALgAECgYJDAAAAA==.',
On='Onlyfeigns:BAAALgAECgIJAgAAAA==.',
Oo='Oozwoz:BAAALgAECgUJCQAAAA==.',
Or='Orileluu:BAAALgADCgYJFQAAAA==.',
Ox='Oxwon:BAAALgAECgYJCwAAAA==.',
Pa='Paisho:BAAALgAECgQJBQAAAA==.Palliera:BAAALgAECgQJBAAAAA==.Pallirot:BAAALgAECggJCAAAAA==.Pallynomial:BAAALgADCgcJCgAAAA==.Pawmuck:BAABLgAECn8dAAIQAAcJexh3TgC+AQAQAAcJexh3TgC+AQAAAA==.',
Pe='Peer:BAAALgAECgEJAgAAAA==.Pewpewtazarz:BAAALgAECgQJBQAAAA==.',
Ph='Phancy:BAAALgADCggJDgAAAA==.Phrizzle:BAAALgADCgIJAgAAAA==.',
Pl='Plaguebeard:BAABLgAECn8XAAMFAAcJBx9/PABFAgAFAAcJBx9/PABFAgAEAAUJCRiiJwABAQAAAA==.Plagueblade:BAABLgAECn8lAAMEAAgJ9xj1FACYAQAEAAgJthf1FACYAQAFAAEJ3RrWGQFPAAAAAA==.',
Po='Podtinder:BAAALgAECgcJBwABLgAECgkJKQAYAKgWAA==.Poof:BAAALgAECgYJCgABLgAECgYJDQAJAAAAAA==.Poseidon:BAAALgAECgIJAgAAAA==.',
Pr='Prescription:BAAALgAECgcJCgAAAA==.Progression:BAAALgAECgEJBQAAAA==.',
Pu='Punish:BAAALgAECgEJAQAAAA==.',
Py='Pyrolord:BAAALgADCgYJCAAAAA==.',
Ra='Ragingrain:BAABLgAECn8YAAIkAAcJ3BfmEQB7AQAkAAcJ3BfmEQB7AQAAAA==.Rainthefire:BAABLgAECn8/AAINAAkJZRrmIAA5AgANAAkJZRrmIAA5AgAAAA==.Ralthor:BAAALgADCgMJAwAAAA==.Rassarudk:BAAALgAECgYJCwAAAA==.Ravinfire:BAAALgAECgQJBwAAAA==.Rawktuah:BAAALgAECgMJAwAAAA==.',
Re='Realhelz:BAAALgAECgQJBQAAAA==.Redcross:BAAALgAECgUJCAAAAA==.Redoxx:BAAALgAECgYJDQAAAA==.Restofarian:BAACLgAFFH8NAAILAAQJRBJnLAD5AAALAAQJRBJnLAD5AAAuAAQKfxcAAgsACQkOG0UXAFsCAAsACQkOG0UXAFsCAAAA.',
Ri='Rianon:BAAALgADCgkJEgABLgAECggJJgAHAHkZAA==.Rift:BAAALgAECgEJAwAAAA==.Righteous:BAABLgAECn8hAAIfAAYJKh7uFwDnAQAfAAYJKh7uFwDnAQAAAA==.Rizzy:BAAALgAECggJDgAAAA==.',
Ro='Rollinsinc:BAAALgAECgkJAwAAAA==.Roshin:BAAALgAECgEJAgAAAA==.Rotinlock:BAAALgADCgYJDAAAAA==.Rotinshot:BAACLgAFFH8LAAMNAAQJtw+IMQAcAQANAAQJtw+IMQAcAQAjAAIJbgM4IwCAAAAuAAQKfygAAw0ACQlsIWUWAIUCAA0ACAmTImUWAIUCACMACAl0GuEQALYBAAAA.',
Ru='Ruin:BAAALgAECgMJBAAAAA==.Rutikee:BAABLgAECn84AAIXAAgJCBSvLADTAQAXAAgJCBSvLADTAQAAAA==.',
Sa='Sacerdos:BAABLgAECn8VAAIfAAgJlBW8FgAmAgAfAAgJlBW8FgAmAgABLgAECgkJMwAVANUaAA==.Saeris:BAAALgADCggJCAABLgAECgYJDQAJAAAAAA==.Sagordez:BAABLgAECn8UAAQlAAgJQho1GwD+AQAlAAcJrBo1GwD+AQACAAYJdhKsMwATAQABAAEJ4Q8YhAAvAAABLgAECgkJHgAbAFggAA==.Salima:BAAALgADCgMJAwAAAA==.Saltybrew:BAAALgADCgMJAwAAAA==.Sandrill:BAAALgAECgYJBgABLgAECggJIAAOAJcTAA==.Satorugojo:BAAALgAECgUJBgAAAA==.Savior:BAAALgADCgkJPwAAAA==.Sazed:BAAALgAECgcJBwAAAA==.',
Sc='Scrom:BAAALgAECgEJAQAAAA==.',
Se='Seabush:BAAALgAECgEJAQAAAA==.Seastorm:BAAALgAECgEJAgAAAA==.Seeker:BAAALgAECgEJAQAAAA==.Seizon:BAAALgAECgQJBAAAAA==.Semila:BAAALgAECgcJCQAAAA==.Sepulchure:BAAALgADCgMJAwAAAA==.Serina:BAAALgADCgIJAgABLgAECggJJQAEAPcYAA==.Serom:BAABLgAECn8XAAIXAAcJbBlHJAAGAgAXAAcJbBlHJAAGAgAAAA==.Sesshomaaru:BAAALgADCggJEQAAAA==.',
Sh='Shaazrah:BAABLgAECn8fAAICAAkJSyEaCACVAgACAAkJSyEaCACVAgAAAA==.Shadows:BAAALgADCgcJBwAAAA==.Shammyhagär:BAAALgADCgMJAwABLgAECgQJBAAJAAAAAA==.Sharalvia:BAAALgADCgUJCAAAAA==.Sharkn:BAAALgADCgcJDAAAAA==.Sherunn:BAABLgAECn8gAAIZAAcJWgsvNQARAQAZAAcJWgsvNQARAQAAAA==.Shifty:BAAALgAECgEJAgAAAA==.Shiftydon:BAABLgAECn8XAAMOAAgJzRC+DwCEAQAOAAgJzRC+DwCEAQAXAAIJ+Q2omgBeAAAAAA==.Shimakaze:BAABLgAECn8tAAINAAkJKwtXQAC2AQANAAkJKwtXQAC2AQAAAA==.Shirvana:BAAALgAECgQJBgABLgAECgcJCQAJAAAAAA==.Shooters:BAABLgAECn8YAAIjAAkJOx2/GAC7AQAjAAkJOx2/GAC7AQAAAA==.Shortbow:BAAALgADCgQJBgABLgAECgEJAgAJAAAAAA==.Shyminx:BAAALgADCgkJEgAAAA==.Shymistress:BAABLgAECn8zAAINAAgJlCGpEwCLAgANAAgJlCGpEwCLAgAAAA==.Shåmmy:BAABLgAECn8vAAILAAkJwA2tOgCSAQALAAkJwA2tOgCSAQAAAA==.',
Si='Simonezer:BAAALgAECgkJAwAAAA==.Sins:BAABLgAECn8fAAIZAAgJeB8sDgBQAgAZAAgJeB8sDgBQAgAAAA==.Sionell:BAAALgADCgQJBAAAAA==.',
Sk='Skiá:BAABLgAECn86AAIOAAkJix7HAgDSAgAOAAkJix7HAgDSAgAAAA==.Skodoosh:BAAALgAECgEJAwAAAA==.Skrinkles:BAAALgAECgYJDQAAAA==.Skyrocket:BAAALgAECgIJAwAAAA==.',
Sl='Slashpoison:BAAALgADCgcJDgAAAA==.Slicedbread:BAACLgAFFH8UAAIPAAYJ/BxvCwC5AQAPAAYJ/BxvCwC5AQAuAAQKfycAAw8ACQk7IOwOAJ4CAA8ACQk7IOwOAJ4CABAABwkKG6BBACACAAAA.Slorth:BAACLgAFFH8GAAIFAAMJNBYJcgDoAAAFAAMJNBYJcgDoAAAuAAQKfyIAAgUACAkYGn5KABMCAAUACAkYGn5KABMCAAAA.',
Sm='Smallfrye:BAAALgADCgMJAwAAAA==.',
Sn='Snizzlaki:BAABLgAECn83AAICAAkJKg/vGwCnAQACAAkJKg/vGwCnAQAAAA==.',
So='Sofa:BAAALgADCgkJDAAAAA==.Soundsmystic:BAAALgADCgUJBQAAAA==.',
Sp='Sparkilies:BAAALgADCgYJBgAAAA==.Spicybreath:BAAALgAECgQJBAABLgAECgcJEQAJAAAAAA==.Spicydemon:BAAALgAECgcJEQAAAA==.Spicydrood:BAAALgAECgEJAQAAAA==.Spicytotems:BAAALgAECgEJAQAAAA==.Splaash:BAAALgAECgMJAwAAAA==.Splàsh:BAABLgAECn8aAAQLAAkJ3x8aBgAQAwALAAkJ3x8aBgAQAwAKAAUJrROKXQCbAAAcAAIJRg1EJgBnAAAAAA==.',
St='Starwolfy:BAAALgADCgQJBAAAAA==.Steakman:BAAALgADCgIJAgAAAA==.Stoneboot:BAAALgAECggJEwAAAA==.',
Su='Sumaria:BAABLgAECn8gAAIeAAcJhwE/VwB6AAAeAAcJhwE/VwB6AAAAAA==.',
Sw='Sweatycrits:BAAALgAECggJDQAAAA==.Sweetvixen:BAAALgAECgMJBgAAAA==.',
Sy='Sylvanasthot:BAAALgADCgYJDAAAAA==.',
Ta='Takbez:BAABLgAECn8gAAIOAAgJlxOSCwAGAgAOAAgJlxOSCwAGAgAAAA==.Tandria:BAAALgAECgUJBQAAAA==.Tarot:BAAALgADCgEJAQAAAA==.Taterhops:BAAALgADCgIJAgABLgAECgkJJQADAFQfAA==.Tattered:BAAALgADCgEJAQAAAA==.Tauru:BAABLgAECn8ZAAIXAAgJWBdMJAAGAgAXAAgJWBdMJAAGAgAAAA==.',
Te='Teakaachu:BAAALgAECggJEgAAAA==.Terdanator:BAABLgAECn8YAAMcAAcJpxWTDwB+AQAcAAcJpxWTDwB+AQAKAAEJLQZQlgAkAAAAAA==.Tetranis:BAAALgADCgQJBgAAAA==.',
Th='Thanathot:BAAALgADCgMJAwAAAA==.Thanatus:BAABLgAECn8zAAQVAAkJ1RqiHABfAgAVAAkJ1RqiHABfAgAWAAMJpglAIgBqAAAUAAEJzgf2eAAqAAAAAA==.Themia:BAAALgADCgMJAwAAAA==.',
Ti='Tiari:BAABLgAECn8iAAIPAAkJCRvHCgC8AgAPAAkJCRvHCgC8AgAAAA==.Timesink:BAAALgAECgQJBQAAAA==.Tisane:BAAALgAECgMJAwAAAA==.',
Tn='Tntclepriest:BAAALgAECgcJDQABLgAECgYJFAAWAGkVAA==.',
Tr='Tralline:BAAALgADCgMJAgAAAA==.Tranzig:BAAALgADCgUJBQAAAA==.Tridius:BAAALgAECgYJDQAAAA==.Trollins:BAAALgAECgIJAgAAAA==.',
Tu='Turdanator:BAABLgAECn9HAAMeAAkJDhngDgBFAgAeAAkJDhngDgBFAgAfAAcJ/gtsQQAzAQAAAA==.',
Tw='Twizzlers:BAAALgADCgEJAQAAAA==.',
Up='Upgraydd:BAAALgAECgIJBAABLgAECgcJEQAJAAAAAA==.',
Ur='Uraenus:BAAALgAECgcJEwAAAA==.Urahrotar:BAAALgADCgUJBgAAAA==.Uriah:BAABLgAECn8cAAINAAgJpxIIQgCwAQANAAgJpxIIQgCwAQAAAA==.Ursúla:BAABLgAFFH8HAAIVAAMJ6QzRZADOAAAVAAMJ6QzRZADOAAABLgAFFAQJDwAZAGQSAA==.Uryu:BAAALgAECgQJBAAAAA==.Urïah:BAAALgADCgkJGgABLgAECggJHAANAKcSAA==.',
Ut='Utherr:BAAALgAFFAMJAwAAAA==.',
Va='Valaravaus:BAAALgAECgEJAwAAAA==.Valionandros:BAAALgAECgYJBwAAAA==.Vanaril:BAAALgAECgMJAwAAAA==.Vashirr:BAAALgAECgMJAwAAAA==.',
Ve='Vergus:BAAALgAECgQJBAAAAA==.',
Vi='Violin:BAAALgAECgIJAwABLgAECgYJDQAJAAAAAA==.Violinmax:BAAALgAECgYJDQAAAA==.Viral:BAAALgAFFAEJAQAAAA==.',
Vo='Voidnova:BAAALgAECgEJAQAAAA==.Vonnie:BAAALgAECgUJBQAAAA==.',
Vy='Vynlerinis:BAABLgAECn8eAAIbAAkJWCDzAQDRAgAbAAkJWCDzAQDRAgAAAA==.',
Wa='Wardestroyer:BAAALgAECggJEQAAAA==.Wardwhelp:BAAALgAECgQJEgABLgAECgYJDQAJAAAAAA==.',
Wi='Wifehaver:BAABLgAECn8oAAICAAkJuR+oEAAWAgACAAkJuR+oEAAWAgAAAA==.Winniedapoo:BAABLgAECn80AAIVAAgJ2BvFLAAOAgAVAAgJ2BvFLAAOAgAAAA==.Winterpaw:BAAALgAECgEJAQABLgAECggJJQAEAPcYAA==.',
Wo='Wooloo:BAACLgAFFH8YAAQUAAcJChwfAwBvAQAVAAYJsx0cDQBzAQAUAAQJ+xgfAwBvAQAWAAEJAADKBABZAAAuAAQKfygAAxUACQmzJfUKAOICABUACQmzJfUKAOICABQABAlPHXogAE8BAAAA.',
Wu='Wurm:BAAALgAECgIJAgAAAA==.',
Xa='Xanagore:BAABLgAECn8mAAMMAAgJfSLuCgCVAgAMAAgJACLuCgCVAgAGAAEJ0RYQRQA4AAAAAA==.Xanthecat:BAAALgAECgQJBAAAAA==.Xanzul:BAAALgAECgMJAwABLgAECggJJgAMAH0iAA==.',
Xk='Xkwon:BAAALgAFFAEJAQAAAA==.Xkwøn:BAACLgAFFH8TAAImAAQJdhrUAgBcAQAmAAQJdhrUAgBcAQAuAAQKfzsAAiYACAkbIikCAIoCACYACAkbIikCAIoCAAAA.',
Xu='Xunie:BAABLgAECn8VAAIFAAgJcRAaWACZAQAFAAgJcRAaWACZAQAAAA==.',
Xx='Xximage:BAABLgAECn8dAAMnAAkJ1CRfAQDIAgAnAAkJ1CRfAQDIAgADAAEJAACeWgFLAAAAAA==.',
Yu='Yulìe:BAAALgADCgcJBwAAAA==.',
Za='Zaibloom:BAAALgADCggJFgAAAA==.Zana:BAABLgAECn8XAAIHAAcJ/BFCaQBnAQAHAAcJ/BFCaQBnAQAAAA==.Zaretan:BAAALgADCgcJDQAAAA==.',
Zb='Zbrute:BAABLgAECn8gAAINAAgJ6RYaOwDIAQANAAgJ6RYaOwDIAQAAAA==.',
Ze='Zeffen:BAAALgAECgIJBAABLgAECgYJFAAVACUGAA==.Zefphenn:BAAALgAECgQJBgABLgAECgYJFAAVACUGAA==.Zenny:BAAALgADCggJEwAAAA==.',
Zi='Zivz:BAAALgADCgUJBQAAAA==.',
Zo='Zokohjin:BAABLgAECn8fAAMFAAkJexuKMQAVAgAFAAkJexuKMQAVAgAEAAEJqRzWRABNAAAAAA==.',
Zu='Zulpher:BAAALgADCgQJBAAAAA==.',
['Ðo']='Ðondon:BAAALgADCgQJBQAAAA==.Ðoppelgänger:BAAALgAECgEJBAAAAA==.',
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
