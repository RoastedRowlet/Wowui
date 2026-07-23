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

local lookup = {'Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Mage-Frost','DeathKnight-Blood','DemonHunter-Havoc','Monk-Mistweaver','Warlock-Demonology','DeathKnight-Unholy','Warrior-Protection','DemonHunter-Devourer','Paladin-Holy','Shaman-Restoration','Hunter-Marksmanship','Shaman-Elemental','Warrior-Fury','Hunter-BeastMastery','Druid-Feral','Paladin-Retribution','Priest-Discipline','Priest-Shadow','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','Priest-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','Druid-Guardian','Rogue-Assassination','Hunter-Survival','Paladin-Protection','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abones:BAABLgAFFH8NAAIBAAMJ+yCpDQAVAQABAAMJ+yCpDQAVAQAAAA==.Absolon:BAAALgAECgQJBAAAAA==.Absólon:BAAALgADCgcJBwAAAA==.',
Ae='Aendia:BAAALgADCgIJAwAAAA==.Aeolos:BAAALgAECgUJBgAAAA==.',
Af='Affae:BAABLgAFFH8KAAMCAAMJFBNsMgB6AAADAAIJ6RZNRwCBAAACAAIJPg5sMgB6AAAAAA==.',
Ag='Agilitiess:BAAALgAECgEJAgABLgAECgEJBQAEAAAAAA==.Agrios:BAAALgAECgYJCgAAAA==.',
Ak='Ak:BAABLgAECn8qAAIFAAkJRSKSFgDSAgAFAAkJRSKSFgDSAgAAAA==.',
Al='Alanas:BAAALgADCgEJAQAAAA==.Alchemie:BAAALgAECgEJAQAAAA==.Alcohlol:BAAALgADCgEJAQAAAA==.Allendril:BAAALgADCgIJAgABLgAECgkJKwAGAFMZAA==.Alliekill:BAAALgAECgQJBAABLgAECgUJCQAEAAAAAA==.Allister:BAAALgAECgYJBgABLgAECgkJHgAHAEsfAA==.Altahari:BAAALgAFFAIJAgABLgAFFAYJGgAIAOYcAA==.Alynnei:BAAALgAECgMJAwABLgAFFAEJAgAEAAAAAA==.',
Am='Amare:BAAALgAECggJCwAAAA==.',
An='Ancalagon:BAAALgAECgQJCQAAAA==.Andros:BAABLgAECn8cAAIJAAgJQRudBwBnAQAJAAgJQRudBwBnAQAAAA==.Anekaatwo:BAAALgADCgEJAQAAAA==.Antigone:BAAALgAECgYJCwAAAA==.',
Ar='Arasun:BAAALgADCgIJAgAAAA==.Araxe:BAABLgAECn8mAAMKAAcJthtiWwC1AQAKAAcJlhpiWwC1AQAGAAQJoxY/KwD/AAAAAA==.Ariv:BAAALgAECgEJBQAAAA==.Arroyo:BAACLgAFFH8GAAIKAAMJ1A4TowDRAAAKAAMJ1A4TowDRAAAuAAQKfy4AAwoACQk3IT8TANUCAAoACQk3IT8TANUCAAYABAnJG58eAFIBAAAA.Artax:BAAALgADCgYJDAAAAA==.',
As='Asalohir:BAAALgAECgUJBQAAAA==.Ashryn:BAAALgAECgEJAgABLgAECgEJBQAEAAAAAA==.Ashvyn:BAAALgAECgEJAgABLgAECgEJBQAEAAAAAA==.Askadar:BAACLgAFFH8fAAILAAYJfyYOBAAxAgALAAYJfyYOBAAxAgAuAAQKfy8AAgsACQlyJhUBAFwDAAsACQlyJhUBAFwDAAAA.',
At='Athridran:BAAALgAECgQJBgAAAA==.Atinyhorse:BAABLgAECn8ZAAIMAAcJ3AuSjQAFAQAMAAcJ3AuSjQAFAQAAAA==.Atrax:BAACLgAFFH8LAAINAAMJLgynGQBuAAANAAMJLgynGQBuAAAuAAQKfxsAAg0ABwl0DxY5AGgBAA0ABwl0DxY5AGgBAAAA.Atrexx:BAABLgAFFH8MAAIOAAMJGRhKHADWAAAOAAMJGRhKHADWAAAAAA==.Atryx:BAABLgAFFH8SAAIPAAMJ7hi5GgDbAAAPAAMJ7hi5GgDbAAAAAA==.',
Au='Auronralius:BAAALgADCgIJAgAAAA==.',
Ax='Ax:BAAALgADCgcJCgABLgAECgYJDwAEAAAAAA==.Axmodel:BAAALgADCgIJAgABLgADCgQJBAAEAAAAAA==.',
Az='Azazél:BAAALgAECgIJAgAAAA==.Azuleja:BAAALgADCgEJAQAAAA==.Azzura:BAAALgADCgYJBwAAAA==.',
Ba='Baheem:BAABLgAECn8kAAIFAAcJ0AXbHADIAAAFAAcJ0AXbHADIAAAAAA==.Bams:BAABLgAECn8fAAMQAAkJYh3wHgDrAQAQAAcJ4h7wHgDrAQAOAAgJzAtQUwBnAQAAAA==.Bamsx:BAAALgAECgcJBwAAAA==.Baneofdemons:BAAALgADCgEJAQAAAA==.Barrillon:BAAALgADCgEJAQAAAA==.Bastile:BAAALgAECgYJDwAAAA==.Bauer:BAAALgAECgQJBAAAAA==.',
Be='Benel:BAAALgAECggJEgAAAA==.',
Bi='Bifrons:BAAALgADCgMJAwAAAA==.Bigblkengery:BAAALgADCgcJCAAAAA==.Bigdill:BAAALgAECgEJAQAAAA==.Biggrippa:BAABLgAECn8lAAIRAAkJcCBJGwByAgARAAkJcCBJGwByAgAAAA==.Bighoofprint:BAAALgAECgkJAQAAAA==.Bigtotempole:BAABLgAECn8aAAIQAAkJLAkZSQAQAQAQAAkJLAkZSQAQAQAAAA==.',
Bj='Bjornar:BAAALgADCgEJAQAAAA==.',
Bl='Blahwithpets:BAABLgAECn8sAAISAAkJtxaNMAAaAgASAAkJtxaNMAAaAgAAAA==.Blappin:BAAALgAECgEJAQAAAA==.Bloodmyst:BAAALgAECgcJEQABLgAECgkJKAATAHcgAA==.Bloodymaw:BAAALgAECgQJBAAAAA==.Bloomer:BAAALgADCgEJAQAAAA==.Blooshield:BAAALgAECgUJCQAAAA==.Bluemchen:BAAALgADCgMJAwAAAA==.Blurt:BAAALgAECgEJAQAAAA==.',
Bo='Bobble:BAABLgAECn8hAAINAAkJfBokGwArAgANAAkJfBokGwArAgAAAA==.Bohelranus:BAAALgADCgkJFwAAAA==.Boneman:BAAALgAECgUJBgAAAA==.Bookwyrm:BAAALgADCgkJFAAAAA==.Boolil:BAAALgAECgQJCgABLgAECgkJMgAUAIYRAA==.Boolove:BAAALgAECgMJBAABLgAECgkJMgAUAIYRAA==.Booqt:BAAALgAECggJCQABLgAECgkJMgAUAIYRAA==.Booshorty:BAAALgAECgYJEQABLgAECgkJMgAUAIYRAA==.Boriel:BAAALgAECgYJBwAAAA==.Boö:BAAALgAECgYJDAAAAA==.',
Br='Breake:BAACLgAFFH8SAAIVAAMJiBTIHgCCAAAVAAMJiBTIHgCCAAAuAAQKfyMAAxUACAmlF8QXABcCABUACAmlF8QXABcCABYAAwl0D1xsAG4AAAAA.',
Bu='Bubblebreath:BAAALgAECgEJAQAAAA==.',
By='Byssrak:BAABLgAECn8dAAMXAAgJ+hEYMAB3AQAXAAgJ0BEYMAB3AQAYAAQJ0w7AEwDPAAAAAA==.',
Ca='Caladiir:BAAALgAECgUJBQABLgAECgkJHwADAEshAA==.Cattiebuzz:BAAALgAECgIJAwABLgAECgkJOwASAKceAA==.',
Ce='Cerealmilk:BAABLgAECn8ZAAIZAAgJ+BmYCQBNAgAZAAgJ+BmYCQBNAgABLgAFFAIJAgAEAAAAAA==.',
Ch='Chadd:BAAALgADCgYJBgABLgAECgQJBgAEAAAAAA==.Cheesefel:BAAALgADCgEJAQAAAA==.Childishbro:BAAALgAECgEJAQAAAA==.Chilla:BAAALgAECgMJAwAAAA==.Chitung:BAAALgADCgQJBAABLgAECgQJBAAEAAAAAA==.Chopshop:BAAALgAECgEJAQAAAA==.Christopher:BAACLgAFFH8SAAIFAAUJAB9RSgBNAQAFAAUJAB9RSgBNAQAuAAQKfxsAAgUACQn2IJwtALsCAAUACQn2IJwtALsCAAAA.',
Ci='Cialismaxing:BAAALgAECggJDQABLgAECggJGQACAMwNAA==.Cindragos:BAAALgAECgQJBQABLgAFFAEJAQAEAAAAAA==.',
Co='Cocofluff:BAACLgAFFH8uAAILAAgJ/CQLAQDUAgALAAgJ/CQLAQDUAgAuAAQKfyUAAgsACAkAIiEEAAoDAAsACAkAIiEEAAoDAAAA.Consolata:BAAALgAECgEJAQAAAA==.Cowculus:BAAALgAECgIJAgABLgAECggJDAAEAAAAAA==.',
Cr='Creed:BAAALgAECgEJAQAAAA==.Creepychaos:BAAALgADCgkJKwABLgAECgkJSAAKAD0IAA==.Creepydemise:BAABLgAECn9IAAIKAAkJPQgScQCCAQAKAAkJPQgScQCCAQAAAA==.Creepydrunk:BAAALgAECgIJAgABLgAECgkJSAAKAD0IAA==.Creepyfoxxy:BAAALgADCgkJGwAAAA==.Croixsmash:BAABLgAECn8gAAIRAAkJZB5GIgBDAgARAAkJZB5GIgBDAgAAAA==.Croixtemplar:BAAALgAECgYJDAAAAA==.',
Cu='Cuculain:BAAALgAECgEJBAAAAA==.Custodian:BAAALgAECgQJBAAAAA==.Cuttinglass:BAAALgADCgcJBwAAAA==.',
Cy='Cyleese:BAAALgAECgEJAQAAAA==.Cytherea:BAAALgADCgcJDAAAAA==.',
Da='Daedra:BAAALgAECgQJBgAAAA==.Dagdelythy:BAAALgAECgUJBwABLgAECgYJIwASAFQNAA==.Danoa:BAAALgAECgQJCgAAAA==.Daraellea:BAAALgAECgUJBQAAAA==.Darkcross:BAAALgADCgUJCAAAAA==.Darthorak:BAABLgAECn8lAAQJAAgJmQh2gAA4AQAJAAgJHQh2gAA4AQAaAAUJ9QbqIQCzAAAbAAYJtAUQIwCYAAAAAA==.Darthzai:BAAALgAECgMJAwAAAA==.Davennial:BAABLgAECn88AAIUAAkJ5BFGVwDFAQAUAAkJ5BFGVwDFAQAAAA==.Dawnn:BAABLgAECn8bAAIGAAkJ/wm2IgA9AQAGAAkJ/wm2IgA9AQAAAA==.Dayman:BAAALgAFFAEJAgAAAA==.',
De='Deanwnchestr:BAABLgAECn8pAAIFAAgJ8AlqkQBVAQAFAAgJ8AlqkQBVAQAAAA==.Deathmamba:BAAALgADCgMJAwAAAA==.Deatnshadow:BAABLgAFFH8FAAIGAAMJbBiNJQDFAAAGAAMJbBiNJQDFAAAAAA==.Deletus:BAAALgADCgkJCQAAAA==.Demise:BAAALgAECgQJCAAAAA==.Demonberry:BAAALgADCgEJAgAAAA==.Demonnutcase:BAAALgADCgYJEAAAAA==.Derogatory:BAAALgADCgYJDQABLgAFFAgJIgAcAEMbAA==.Desylla:BAAALgAECgQJBAAAAA==.Devildograh:BAAALgAECgQJBwAAAA==.',
Di='Diah:BAAALgAECgQJBwAAAA==.Dibinator:BAAALgADCgEJAQAAAA==.Dio:BAAALgADCgYJDQAAAA==.Diodata:BAAALgAECgEJAgABLgAECggJHQACAKohAA==.Diophantus:BAAALgAECgIJBQABLgAECggJHQACAKohAA==.Divinity:BAAALgAECgEJAQAAAA==.',
Dm='Dmncgdss:BAAALgAECggJEgAAAA==.',
Do='Dogeatdog:BAAALgADCgkJFwAAAA==.Dohaeriz:BAAALgAECgEJBAAAAA==.Doregoran:BAABLgAECn8pAAIbAAgJhBPRCgCVAQAbAAgJhBPRCgCVAQAAAA==.Dovairous:BAABLgAECn8eAAIdAAgJWAswWAAwAQAdAAgJWAswWAAwAQAAAA==.',
Dr='Draakell:BAAALgAECgQJBAAAAA==.Dracopeet:BAABLgAECn8aAAQXAAcJvwQ5cACLAAAXAAUJEgU5cACLAAAZAAQJGwPUNQBOAAAYAAMJwQLDKQAnAAAAAA==.Dragonator:BAAALgAECgUJCAAAAA==.Drausella:BAAALgAECgEJAQAAAA==.Dreamsicle:BAAALgAECgMJAwAAAA==.Dregomalfoy:BAAALgAECgQJBAAAAA==.Drexor:BAAALgAECgQJCwAAAA==.Drhealgôod:BAAALgAECgYJDAABLgAECgkJMQAZAKgWAA==.',
Du='Dudè:BAAALgAECgQJBgAAAA==.',
Dv='Dvlzadvocate:BAAALgAECgYJEgAAAA==.',
['Dâ']='Dâggèr:BAAALgAFFAEJAQAAAA==.',
['Dü']='Dürin:BAAALgAECgEJAgAAAA==.',
Ec='Echidna:BAABLgAECn8fAAIJAAgJCQoBngACAQAJAAgJCQoBngACAQAAAA==.',
Ed='Edgeovo:BAAALgAECgEJAQABLgAECgEJBQAEAAAAAA==.Edict:BAAALgAECgEJAQAAAA==.',
El='Elawen:BAAALgAECgYJDQAAAA==.Elder:BAAALgAECgEJAgAAAA==.Eleblah:BAAALgADCgcJBwAAAA==.Elfkinn:BAACLgAFFH8pAAMeAAYJRxy+DQDBAQAeAAYJRxy+DQDBAQAdAAIJ+gAvawBEAAAuAAQKfyUAAx4ACQmmHqUQAFkCAB4ACQmmHqUQAFkCAB0ABAlrBY+sAG0AAAAA.Elgund:BAAALgADCgQJBAAAAA==.Elivaniel:BAAALgAECgcJEAAAAA==.',
En='Enlargdcrit:BAAALgAECgMJAwAAAA==.',
Eq='Equinox:BAAALgADCgQJBAAAAA==.',
Er='Ericcdraven:BAABLgAECn8iAAIRAAgJgQ5zNwBpAQARAAgJgQ5zNwBpAQAAAA==.Erodoria:BAABLgAECn8eAAMHAAkJSx/dCQCLAgAHAAgJBSLdCQCLAgAfAAUJ/hAFFQAFAQAAAA==.',
Et='Eternalfire:BAAALgADCgcJDgABLgAECgkJIwAeABgaAA==.',
Ev='Eve:BAAALgAECgEJAQAAAA==.Eveliong:BAAALgADCgEJAQAAAA==.Evilobama:BAAALgAECgUJBgAAAA==.Evoke:BAAALgAFFAEJAQABLgAFFAYJKgAOAPcZAA==.',
Ex='Exzanthia:BAAALgAECgEJAwAAAA==.',
Ey='Eyln:BAACLgAFFH8LAAIPAAQJMwroCADmAAAPAAQJMwroCADmAAAuAAQKfzUAAg8ACQnOHRwDAKgCAA8ACQnOHRwDAKgCAAAA.',
Fa='Facielshot:BAAALgAECgYJCwABLgAECgkJMQAZAKgWAA==.Falkor:BAABLgAECn8xAAMZAAkJqBYADAAXAgAZAAkJqBYADAAXAgAYAAEJ6QI/LAAaAAAAAA==.Fanaa:BAAALgAECgEJAQAAAA==.Fanir:BAAALgAECgcJBwAAAA==.Fatino:BAAALgAECgUJBQAAAA==.Fatkid:BAABLgAECn8VAAIMAAcJng95eAAwAQAMAAcJng95eAAwAQAAAA==.Fayway:BAABLgAECn9MAAIdAAkJxiGPBgBPAwAdAAkJxiGPBgBPAwAAAA==.',
Fe='Ferral:BAABLgAECn8oAAITAAkJdyD7BACoAgATAAkJdyD7BACoAgAAAA==.Festukar:BAAALgAECgUJBwAAAA==.',
Fi='Figgy:BAAALgAECgUJCAAAAA==.Filthypirate:BAABLgAECn8UAAIUAAgJARFprgAhAQAUAAgJARFprgAhAQAAAA==.Firepower:BAABLgAECn8hAAIFAAkJxheBOwAsAgAFAAkJxheBOwAsAgABLgAECggJIAATAJcTAA==.Fistatoosh:BAABLgAECn8iAAIDAAgJUCSYBgDQAgADAAgJUCSYBgDQAgAAAA==.',
Fl='Florane:BAAALgAECgUJDAAAAA==.Flyingbotato:BAAALgADCgkJFQABLgAECggJIAATAJcTAA==.',
Fo='Forevershy:BAAALgADCgkJEgAAAA==.',
Fr='Fries:BAECLgAFFH8LAAIgAAUJTR/BBAB6AQAgAAUJTR/BBAB6AQAuAAQKfxwAAyAACQkBIpYCAO8CACAACQkBIpYCAO8CAA4ABQkGDISDANgAAAAA.Fruits:BAAALgAECgYJBwAAAA==.',
Ga='Galdavin:BAABLgAECn8XAAIUAAgJnBqgKQB+AgAUAAgJnBqgKQB+AgAAAA==.Galenhaihi:BAAALgADCgUJBQAAAA==.Galexstrasza:BAAALgADCgYJBgABLgAECgUJDgAEAAAAAA==.Gallandia:BAAALgADCgEJAQABLgAECgUJDgAEAAAAAA==.Gallielynne:BAAALgAECgUJDgAAAA==.Ganduin:BAAALgAECgMJAwAAAA==.Gankdd:BAABLgAECn8UAAMRAAcJLhuUPgBLAQARAAcJxhmUPgBLAQAhAAMJnRvCHgD4AAAAAA==.Garnnt:BAAALgADCgkJEQAAAA==.',
Gh='Ghoulfriend:BAAALgAECgEJAQAAAA==.',
Gi='Giggles:BAABLgAECn8uAAIQAAkJiBm1AgAAAgAQAAkJiBm1AgAAAgAAAA==.Gigglez:BAAALgADCggJCAAAAA==.Gimmothyjr:BAAALgAECgUJBgAAAA==.',
Gl='Glennspyder:BAAALgAECgQJDQABLgAECgYJIwASAFQNAA==.',
Go='Gonzo:BAAALgAFFAEJAQABLgAFFAYJKgAOAPcZAA==.Goysoldier:BAAALgAFFAMJBAAAAA==.',
Gr='Greenbean:BAABLgAFFH8pAAIMAAUJhBsoGwAfAQAMAAUJhBsoGwAfAQABLgAFFAYJKQAeAEccAA==.Grelleth:BAAALgAFFAQJBAAAAA==.Groddz:BAABLgAECn8WAAIMAAkJvgbyhQAUAQAMAAkJvgbyhQAUAQAAAA==.Groto:BAAALgAECgYJCgAAAA==.Grrum:BAABLgAECn8gAAQVAAcJXgvaNwAzAQAVAAcJkQnaNwAzAQAWAAQJaQhAWwCpAAAcAAIJQwlEfgA0AAAAAA==.Grèy:BAAALgAECgcJBwAAAA==.',
Gu='Gurînkaida:BAAALgAECgQJBAAAAA==.',
Ha='Haell:BAAALgAECgYJCgAAAA==.Hanjo:BAABLgAECn8wAAILAAkJzyHdBADQAgALAAkJzyHdBADQAgAAAA==.Hanoa:BAAALgAECgYJCgAAAA==.Harakiri:BAABLgAECn8UAAIOAAcJixUvNgCqAQAOAAcJixUvNgCqAQAAAA==.Hardare:BAABLgAECn8ZAAICAAgJzA31JACvAQACAAgJzA31JACvAQAAAA==.Harpune:BAAALgADCgIJAgAAAA==.Hatookorr:BAAALgAECgUJBQABLgAECggJIAATAJcTAA==.Hayali:BAABLgAECn8iAAIMAAgJXRYTPQDTAQAMAAgJXRYTPQDTAQAAAA==.',
He='Helledrians:BAAALgAECgQJBgAAAA==.',
Hi='Hiawatha:BAAALgADCgcJAwAAAA==.',
Hm='Hmccrnglbery:BAAALgAECgMJBAABLgAECggJGQACAMwNAA==.',
Ho='Hottogo:BAAALgADCgcJBwAAAA==.',
Hw='Hwei:BAAALgADCgEJAQAAAA==.',
Hy='Hydé:BAABLgAECn8VAAMiAAgJxBvCCgA4AgAiAAgJxBvCCgA4AgATAAEJOhwTRABTAAABLgAECgkJHgAfAFggAA==.Hypatia:BAABLgAECn8dAAICAAgJqiGqDQBrAgACAAgJqiGqDQBrAgAAAA==.',
['Hä']='Häxan:BAAALgAECgQJBAAAAA==.',
Ia='Iame:BAAALgADCgMJAwAAAA==.Iapetus:BAAALgADCgIJAgAAAA==.',
Ic='Icedchi:BAEBLgAECn8iAAIDAAkJ3x/SEQApAgADAAkJ3x/SEQApAgAAAA==.',
In='Incite:BAABLgAECn8gAAMjAAkJaA9lCgCRAQAjAAkJZQ9lCgCRAQABAAUJ+g2QQQAUAQAAAA==.',
Is='Ishvala:BAAALgADCgMJAwAAAA==.',
Iz='Izcarius:BAAALgADCgIJAgAAAA==.',
Ja='Jackpad:BAAALgAECgEJAgAAAA==.Jademist:BAAALgAECgYJDAABLgAECgkJMQAZAKgWAA==.Jaland:BAAALgADCgMJAwAAAA==.Jarrel:BAAALgAECgIJBAAAAA==.',
Je='Jellybreak:BAACLgAFFH8JAAIeAAQJMg5gDwD8AAAeAAQJMg5gDwD8AAAuAAQKfz0AAx4ACQmGFkAYAAsCAB4ACQmGFkAYAAsCACIABwmpCOY+AKsAAAAA.',
Jo='Joeewee:BAAALgAECgYJBgAAAA==.Jonjud:BAAALgAECgYJDAAAAA==.',
Js='Jskimonkpo:BAAALgADCgUJCQAAAA==.',
Ju='Jubilee:BAAALgAECgkJCQAAAA==.Julius:BAAALgAFFAEJAQAAAA==.',
Jy='Jyrian:BAAALgADCgMJAwAAAA==.',
Ka='Kaanâ:BAABLgAECn8zAAIcAAkJWhxkCQDSAgAcAAkJWhxkCQDSAgAAAA==.Kaelei:BAAALgADCgkJKwAAAA==.Kagamire:BAAALgADCgYJBQAAAA==.Kamine:BAAALgAECgUJEAAAAA==.Kanyeeast:BAAALgAECgYJCgAAAA==.Karnen:BAAALgAECgMJAwAAAA==.Kateblue:BAABLgAECn8vAAIeAAkJhRoGEABhAgAeAAkJhRoGEABhAgAAAA==.',
Ke='Kelcier:BAAALgADCgYJBgAAAA==.Kelser:BAABLgAECn8ZAAMaAAgJTx7FBAApAgAaAAgJTx7FBAApAgAJAAMJoBXuxgDLAAAAAA==.Kensington:BAABLgAECn8hAAIjAAgJdggnDgBDAQAjAAgJdggnDgBDAQAAAA==.Kethry:BAAALgAECgIJAwAAAA==.',
Ki='Kiku:BAABLgAECn8jAAIXAAkJYiPsBQD+AgAXAAkJYiPsBQD+AgAAAA==.Kikyou:BAAALgAECgYJCgABLgAECgkJIwAXAGIjAA==.Kim:BAABLgAECn8fAAIkAAkJRhBnFgDuAQAkAAkJRhBnFgDuAQAAAA==.Kinrah:BAAALgADCgMJAwABLgAECgEJAQAEAAAAAA==.Kirandra:BAAALgADCgMJAwAAAA==.Kirëë:BAAALgAECggJCAAAAA==.Kissofdeáth:BAAALgAECgIJAwAAAA==.',
Ko='Korlock:BAABLgAECn8mAAQJAAkJAB4vNAA8AgAJAAgJGR0vNAA8AgAbAAEJAACvbAA7AAAaAAEJPRc4PQA4AAAAAA==.',
Kr='Kreepywife:BAABLgAECn8jAAIWAAgJsRlOAgANAgAWAAgJsRlOAgANAgAAAA==.Krelbelorll:BAAALgAECgEJAQAAAA==.Krowley:BAABLgAECn8nAAIOAAkJPxB4MADzAQAOAAkJPxB4MADzAQAAAA==.',
Ku='Kurast:BAAALgAECgMJAwABLgAECgkJMQAZAKgWAA==.Kuzan:BAACLgAFFH8TAAIFAAUJEB9rTABHAQAFAAUJEB9rTABHAQAuAAQKfx8AAgUABwl3IfQ2AJgCAAUABwl3IfQ2AJgCAAAA.',
Kx='Kxwono:BAAALgAECgcJBwAAAA==.',
Ky='Kyoyama:BAAALgAECgMJBwABLgAFFAQJEwAaACUdAA==.',
La='Lacious:BAAALgADCgEJAQABLgAECgkJOwASAKceAA==.Ladýshinobu:BAABLgAECn8nAAINAAgJQBBIKQDDAQANAAgJQBBIKQDDAQAAAA==.Lananar:BAAALgADCgUJBQAAAA==.Layssaenna:BAAALgAECgYJCAAAAA==.',
Le='Leahu:BAABLgAECn88AAIlAAkJBhiuCgAfAgAlAAkJBhiuCgAfAgAAAA==.Lediaa:BAAALgAECgMJBAAAAA==.',
Li='Lifekiller:BAAALgAECgYJDwAAAA==.Lightark:BAAALgAECgEJAgAAAA==.Linekingz:BAAALgADCgEJAQAAAA==.Linetheshamy:BAAALgADCgkJDQAAAA==.Lineurathrot:BAAALgADCgYJCAAAAA==.Lisavia:BAAALgADCgUJBgAAAA==.Littlespyone:BAABLgAECn8jAAISAAYJVA0GGAD0AAASAAYJVA0GGAD0AAAAAA==.Lizardman:BAAALgAFFAEJAQAAAA==.',
Lo='Locholovis:BAABLgAECn8wAAIbAAkJOhR5BwDcAQAbAAkJOhR5BwDcAQAAAA==.Locklicous:BAABLgAECn8WAAMJAAkJ2xepPQDlAQAJAAkJ2BOpPQDlAQAaAAYJWxV2EgBBAQAAAA==.Longhorse:BAACLgAFFH8hAAIGAAcJ5h+lEgBiAQAGAAcJ5h+lEgBiAQAuAAQKfzEAAwYACQn4JMgFAOACAAYACQmpIsgFAOACAAoABgnhJfpfAKkBAAAA.Longknight:BAAALgAECgEJAQAAAA==.Longr:BAAALgAECgYJCwAAAA==.Lorna:BAABLgAECn8XAAIMAAgJJhJcVgCEAQAMAAgJJhJcVgCEAQAAAA==.Lorthimar:BAAALgAECgUJCgABLgAECgkJJgAJAAAeAA==.',
Lu='Lumi:BAABLgAECn8WAAIFAAkJchhwUQDoAQAFAAkJchhwUQDoAQAAAA==.Luminarae:BAAALgADCgEJAQAAAA==.Luminouss:BAABLgAFFH8QAAIOAAcJuBKEFQC5AQAOAAcJuBKEFQC5AQABLgAFFAMJBgAVAOcUAA==.Lumpia:BAABLgAFFH8IAAIMAAUJGBmzQgAfAQAMAAUJGBmzQgAfAQAAAA==.',
Ly='Lylo:BAAALgADCgEJAQAAAA==.Lyrinir:BAABLgAECn8dAAMLAAkJ/hkjEQD2AQALAAkJ/hkjEQD2AQAhAAEJigTaigAbAAAAAA==.Lyrium:BAABLgAECn8ZAAMfAAgJtRm8CgC4AQAfAAUJDR+8CgC4AQAHAAcJ+RA9KgAtAQABLgAECgkJHQALAP4ZAA==.',
Ma='Madar:BAABLgAECn8gAAIJAAgJpgYomQALAQAJAAgJpgYomQALAQAAAA==.Maggus:BAAALgADCgQJBAAAAA==.Magicgal:BAAALgAECggJDQAAAA==.Maiden:BAAALgAECgUJBQAAAA==.Maiklytzwhet:BAAALgAECgUJBQAAAA==.Mairon:BAAALgAECgMJBgAAAA==.Malvorak:BAABLgAECn88AAIGAAkJzBIXBABkAQAGAAkJzBIXBABkAQAAAA==.Mande:BAAALgADCgQJBAAAAA==.Mantis:BAAALgAECgkJDAABLgAECgkJMQAZAKgWAA==.Marrock:BAAALgAECgYJEQAAAA==.Marzipain:BAAALgAECgEJAQAAAA==.Mavarasie:BAAALgAECgUJDgAAAA==.Mavaressy:BAAALgAECgMJAwAAAA==.Mavaria:BAAALgAECgYJDAAAAA==.',
Mc='Mcmuffin:BAABLgAECn8YAAIVAAgJuga5DADPAAAVAAgJuga5DADPAAAAAA==.',
Me='Mechacattie:BAABLgAECn87AAISAAkJpx4iFACxAgASAAkJpx4iFACxAgAAAA==.Mediator:BAAALgAECgEJAQAAAA==.Meekerz:BAAALgAECgIJAgAAAA==.Mega:BAAALgAFFAIJAwAAAA==.Melganis:BAAALgADCgMJBAAAAA==.Melissandra:BAABLgAECn8qAAMWAAgJ0gxoNgA9AQAWAAgJ0gxoNgA9AQAcAAIJiAb1dABVAAAAAA==.Mercas:BAAALgAECgcJDwABLgAECgkJJgAiAKMaAA==.Metacallae:BAAALgADCgcJAQAAAA==.Mezi:BAACLgAFFH8MAAIcAAQJZB4uBgBYAQAcAAQJZB4uBgBYAQAuAAQKf0UAAhwACQnlIWgHAPgCABwACQnlIWgHAPgCAAAA.Mezmera:BAAALgADCgUJBgABLgAECgIJAwAEAAAAAA==.',
Mh='Mhonster:BAAALgAECgYJCgABLgAFFAEJAgAEAAAAAA==.',
Mi='Mildchaos:BAAALgAECgUJBQAAAA==.Missed:BAAALgAECgQJBQAAAA==.Mittens:BAACLgAFFH8GAAIVAAMJ5xRcMADRAAAVAAMJ5xRcMADRAAAuAAQKfxkAAxwACQlbGXQoAK0BABwABgn7GXQoAK0BABUABwlvE8ohAIUBAAAA.',
Mo='Mofro:BAAALgADCgQJBAABLgAECgQJBAAEAAAAAA==.Mokgunal:BAAALgADCgQJBAAAAA==.Money:BAAALgADCgIJAgABLgAECggJIwAUABghAA==.Moneyshotinc:BAAALgAECgkJCgABLgAECggJIwAUABghAA==.Moraine:BAAALgAECgQJBAAAAA==.Moreki:BAAALgAECgMJAwAAAA==.Morro:BAABLgAECn8wAAIQAAkJVw8sKwCaAQAQAAkJVw8sKwCaAQAAAA==.',
Ms='Msvelvet:BAAALgAECgYJCQABLgAECgYJFwAOAKwTAA==.',
Mu='Mugiwara:BAACLgAFFH8LAAICAAQJbCQnDABkAQACAAQJbCQnDABkAQAuAAQKfxYAAgIABwntJAkKANcCAAIABwntJAkKANcCAAAA.Mulron:BAABLgAECn8kAAIlAAkJmhE0EgCjAQAlAAkJmhE0EgCjAQAAAA==.',
My='Myrica:BAAALgAECggJDwAAAA==.',
['Må']='Mådcõw:BAAALgAECgUJBgAAAA==.',
['Mö']='Mööve:BAAALgAECgMJAwAAAA==.',
Na='Nallos:BAAALgADCgEJAQAAAA==.Natajapar:BAAALgAECgEJAQABLgAECgcJCQAEAAAAAA==.',
Ne='Nefesh:BAABLgAFFH8ZAAMMAAUJlBFzVADxAAAMAAUJnwpzVADxAAAfAAEJaCQ7BwBlAAAAAA==.Neff:BAAALgADCgMJAwAAAA==.',
Ni='Nightingales:BAAALgAECgMJAwAAAA==.',
Ny='Nyomie:BAAALgADCgEJAgAAAA==.Nyyx:BAAALgAECgQJBAABLgAECgYJCgAEAAAAAA==.',
Oa='Oakenshíeld:BAACLgAFFH8XAAIeAAcJ0w/kGQBKAQAeAAcJ0w/kGQBKAQAuAAQKfzsAAh4ACQlCF9AUAGsCAB4ACQlCF9AUAGsCAAAA.',
Ob='Obama:BAAALgADCgQJBAAAAA==.',
Og='Oggy:BAABLgAECn8XAAINAAkJqwXOCgC8AAANAAkJqwXOCgC8AAABLgAECgkJMQAZAKgWAA==.',
Ol='Olkwon:BAAALgAFFAIJAwAAAA==.',
On='Onlyfeigns:BAAALgAECgMJAwAAAA==.',
Oo='Oozwoz:BAAALgAECgcJDgAAAA==.',
Or='Oradreladin:BAAALgAECggJCgAAAA==.Orileluu:BAAALgAECgEJAQAAAA==.',
Ou='Outfoxed:BAABLgAFFH8FAAIOAAMJrhJfIAC/AAAOAAMJrhJfIAC/AAABLgAFFAgJIgAcAEMbAA==.',
Ox='Oxwon:BAAALgAECgYJCwAAAA==.',
Pa='Paisho:BAAALgAECgQJBQAAAA==.Palliera:BAAALgAECgQJBgAAAA==.Pallirot:BAAALgAECggJCAAAAA==.Pallynomial:BAAALgADCgcJCgAAAA==.Papapapaya:BAAALgAECgYJBwAAAA==.Pawmuck:BAABLgAECn8tAAIUAAgJ9Rk+PAATAgAUAAgJ9Rk+PAATAgAAAA==.',
Pe='Peer:BAAALgAECgEJAgAAAA==.Pewpewtazarz:BAAALgAECgUJCQAAAA==.',
Ph='Phancy:BAAALgADCggJDgAAAA==.Phrizzle:BAAALgADCgMJAwAAAA==.',
Pl='Plaguebeard:BAABLgAECn8XAAMKAAcJBx9/PABFAgAKAAcJBx9/PABFAgAGAAUJCRiiJwABAQAAAA==.Plagueblade:BAABLgAECn8rAAMGAAkJUxmWEgDlAQAGAAkJOhiWEgDlAQAKAAEJ3RqCVAFNAAAAAA==.',
Po='Podtinder:BAAALgAECgcJDAABLgAECgkJMQAZAKgWAA==.Poof:BAAALgAFFAIJAgAAAA==.Poseidon:BAAALgAECgIJAgAAAA==.',
Pr='Prescription:BAABLgAECn8YAAMIAAgJ+AkMYQD1AAAIAAcJ1AkMYQD1AAACAAcJvQisRQDpAAAAAA==.Progression:BAAALgAECgEJBwAAAA==.',
Pu='Punish:BAAALgAECgEJAQAAAA==.',
Py='Pyrolord:BAAALgADCgYJCAAAAA==.',
Ra='Ragingrain:BAABLgAECn8jAAIlAAgJVxmyDAD6AQAlAAgJVxmyDAD6AQAAAA==.Rainsshammy:BAAALgAECgQJCAAAAA==.Rainthefire:BAABLgAECn8/AAISAAkJZRqRLAArAgASAAkJZRqRLAArAgAAAA==.Ralthor:BAAALgADCgMJAwAAAA==.Ramalama:BAAALgAECgEJAgAAAA==.Rassarudk:BAAALgAECgYJCwAAAA==.Ravinfire:BAAALgAECgQJBwAAAA==.Rawktuah:BAAALgAECgMJAwAAAA==.',
Re='Realhelz:BAAALgAECgQJBQAAAA==.Redcross:BAABLgAECn8cAAMNAAkJrg82AwDMAQANAAkJrg82AwDMAQAUAAQJTAwjMQBoAAAAAA==.Redoxx:BAAALgAECgYJDQAAAA==.Restofarian:BAACLgAFFH8qAAIOAAYJ9xmSCgCMAQAOAAYJ9xmSCgCMAQAuAAQKfyMAAg4ACQmJG0UXAFsCAA4ACQmJG0UXAFsCAAAA.',
Rh='Rhagnor:BAAALgAECgkJDAAAAA==.',
Ri='Rianon:BAAALgADCgkJEgABLgAECgkJNAAMANccAA==.Rift:BAAALgAECgEJAwAAAA==.Righteous:BAABLgAECn8zAAIcAAkJFh5dAQCVAgAcAAkJFh5dAQCVAgAAAA==.Rizzy:BAABLgAECn8iAAMGAAkJQxenDwARAgAGAAkJQxenDwARAgAKAAkJ7gjubQCJAQAAAA==.',
Ro='Rollinsinc:BAAALgAECgkJAwAAAA==.Roshin:BAAALgAECgEJAgAAAA==.Rotinlock:BAAALgADCgYJDAAAAA==.Rotinshot:BAACLgAFFH8VAAMSAAYJjhLbIQB9AQASAAYJjhLbIQB9AQAkAAIJbgMhLQB6AAAuAAQKfygAAxIACQlsIWUWAIUCABIACAmTImUWAIUCACQACAl0GuEQALYBAAAA.',
Ru='Ruin:BAAALgAECgMJBAAAAA==.Rutikee:BAABLgAECn9OAAIdAAkJeRSzBACVAQAdAAkJeRSzBACVAQAAAA==.',
Sa='Sacerdos:BAABLgAECn8VAAIcAAgJlBW8FgAmAgAcAAgJlBW8FgAmAgABLgAECgkJOgAJAAEbAA==.Saeris:BAAALgADCggJCAABLgAECgcJDgAEAAAAAA==.Sagordez:BAACLgAFFH8HAAMIAAMJxg+hJgCCAAAIAAMJxg+hJgCCAAACAAEJ0ArWRAA2AAAuAAQKfygABAgACAm0Hi0ZAE8CAAgABwmVHi0ZAE8CAAMABwlxFXsmAHsBAAIAAQnhD7ejAC0AAAEuAAQKCQkeAB8AWCAA.Salima:BAAALgADCgMJAwAAAA==.Saltybrew:BAAALgADCgMJAwAAAA==.Sandrill:BAAALgAECgYJCgABLgAECggJIAATAJcTAA==.Sarr:BAAALgAECgMJAwAAAA==.Satorugojo:BAAALgAECgUJBgAAAA==.Savior:BAABLgAECn8pAAIUAAkJVhVVBgDxAQAUAAkJVhVVBgDxAQAAAA==.Sazed:BAAALgAECggJDgAAAA==.',
Sc='Scrom:BAAALgAECgIJBAAAAA==.',
Se='Seabush:BAAALgAECgIJAwAAAA==.Seastorm:BAAALgAECgkJCQAAAA==.Seeker:BAAALgAECgEJAQAAAA==.Seizon:BAABLgAECn8sAAMkAAkJFBgXAQBaAgAkAAkJFBgXAQBaAgAPAAIJmQf2MwBMAAAAAA==.Sekkusu:BAAALgAECgQJBAAAAA==.Semila:BAAALgAECgcJCQAAAA==.Sendor:BAAALgAECgYJBgAAAA==.Senseicanz:BAAALgAECgQJBQAAAA==.Sepulchure:BAAALgADCgMJAwAAAA==.Serina:BAAALgAECgQJBwABLgAECgkJKwAGAFMZAA==.Serom:BAABLgAECn8hAAIdAAgJdRlhHwBLAgAdAAgJdRlhHwBLAgAAAA==.Sesshomaaru:BAAALgADCggJEQAAAA==.',
Sh='Shaazrah:BAABLgAECn8fAAIDAAkJSyGVCgCKAgADAAkJSyGVCgCKAgAAAA==.Shadowoak:BAAALgAECgIJAgAAAA==.Shadows:BAAALgADCgcJBwAAAA==.Shamkazaam:BAAALgAECgkJEwAAAA==.Shammyhagär:BAAALgADCgMJAwABLgAECgQJBAAEAAAAAA==.Sharalvia:BAAALgADCgUJCAAAAA==.Sharkn:BAAALgAECgEJAQAAAA==.Sharkyo:BAAALgADCgIJAgAAAA==.Sharpshôôter:BAAALgAFFAMJAwAAAA==.Sherunn:BAABLgAECn8jAAIeAAcJpQ0dOgAqAQAeAAcJpQ0dOgAqAQAAAA==.Shifty:BAAALgAECgEJAgAAAA==.Shiftydon:BAABLgAECn8eAAQTAAkJ0RA0EAC0AQATAAkJ0RA0EAC0AQAdAAIJ+Q2CqwBeAAAiAAEJMguSgAAhAAAAAA==.Shimakaze:BAACLgAFFH8IAAISAAIJPwZlSAB5AAASAAIJPwZlSAB5AAAuAAQKfz8AAhIACQn3DrtFANABABIACQn3DrtFANABAAAA.Shirvana:BAAALgAECgQJBwABLgAECgcJCQAEAAAAAA==.Shooters:BAABLgAECn8YAAIkAAkJOx26DQDuAQAkAAkJOx26DQDuAQAAAA==.Shortbow:BAAALgADCgQJBgABLgAECgEJAgAEAAAAAA==.Shyminx:BAAALgAECgEJAQAAAA==.Shymistress:BAACLgAFFH8JAAISAAQJBxHNIwABAQASAAQJBxHNIwABAQAuAAQKfz0AAhIACQkTIr8MAO0CABIACQkTIr8MAO0CAAAA.Shåmmy:BAABLgAECn9GAAIOAAkJRxffAwAmAgAOAAkJRxffAwAmAgAAAA==.',
Si='Simonezer:BAAALgAECgkJAwAAAA==.Sins:BAABLgAECn8nAAIeAAkJVR9YCQC+AgAeAAkJVR9YCQC+AgAAAA==.Sionell:BAAALgADCgQJBAAAAA==.',
Sk='Skiá:BAACLgAFFH8GAAITAAMJtBIDDwDPAAATAAMJtBIDDwDPAAAuAAQKf1QAAhMACQm7IewBABYDABMACQm7IewBABYDAAAA.Skodoosh:BAAALgAECgYJEAAAAA==.Skrinkles:BAAALgAECgYJDgAAAA==.Skyrocket:BAAALgAECgIJAwAAAA==.',
Sl='Slashpoison:BAAALgADCgcJDgAAAA==.Slicedbread:BAACLgAFFH8UAAINAAYJ/BzeBwBUAQANAAYJ/BzeBwBUAQAuAAQKfycAAw0ACQk7IOwOAJ4CAA0ACQk7IOwOAJ4CABQABwkKG6BBACACAAAA.Slorth:BAACLgAFFH8GAAIKAAMJNBYkoADUAAAKAAMJNBYkoADUAAAuAAQKfyIAAgoACAkYGn5KABMCAAoACAkYGn5KABMCAAAA.',
Sm='Smallfrye:BAAALgAECgEJAQAAAA==.',
Sn='Snizzlaki:BAABLgAECn9MAAMDAAkJeQ/CIAChAQADAAkJQg/CIAChAQACAAcJxgiyCADNAAAAAA==.',
So='Sofa:BAAALgADCgkJDAAAAA==.Solaene:BAAALgAFFAEJAgAAAA==.Soundsmystic:BAAALgADCgUJBQAAAA==.',
Sp='Spareparts:BAAALgAECgMJAwABLgAECgYJFwAOAKwTAA==.Sparkilies:BAAALgADCgYJBgAAAA==.Sparkleglory:BAAALgAECgMJAwAAAA==.Spicybreath:BAAALgAECgQJBAABLgAECgcJEQAEAAAAAA==.Spicydemon:BAAALgAECgcJEQAAAA==.Spicydrood:BAAALgAECgEJAQAAAA==.Spicytotems:BAAALgAECgEJAQAAAA==.Splaash:BAAALgAECgMJAwAAAA==.Splàsh:BAABLgAECn8bAAQOAAkJ3x8aBgAQAwAOAAkJ3x8aBgAQAwAQAAUJpRWMZQC1AAAgAAIJRg3XMgBlAAAAAA==.',
St='Starwolfy:BAAALgAECgUJBQAAAA==.Steakman:BAAALgADCgIJAgAAAA==.Stoneboot:BAAALgAECggJEwAAAA==.Stryk:BAAALgAFFAEJAQAAAA==.Sts:BAAALgAECgIJAgAAAA==.',
Su='Sumaria:BAABLgAECn8oAAIWAAkJPwJlZgCDAAAWAAkJPwJlZgCDAAAAAA==.',
Sw='Sweatycrits:BAAALgAECggJDQAAAA==.Sweetvixen:BAABLgAECn8XAAMOAAYJrBPGCwA1AQAOAAYJrBPGCwA1AQAQAAEJ7wDpxgAMAAAAAA==.',
Sy='Sylvanasthot:BAAALgAECgQJBAAAAA==.Symora:BAAALgAECgUJBQAAAA==.',
['Sä']='Sävägeäf:BAAALgADCgcJBwAAAA==.',
Ta='Taana:BAAALgAECgUJCgAAAA==.Takbez:BAABLgAECn8gAAITAAgJlxOSCwAGAgATAAgJlxOSCwAGAgAAAA==.Tandria:BAAALgAECgYJDwAAAA==.Tarot:BAAALgADCgEJAQAAAA==.Taterhops:BAAALgAECgEJAQABLgAECgkJKAAFAD8gAA==.Tattered:BAAALgADCgEJAQAAAA==.Tauru:BAABLgAECn8jAAMdAAgJzhmxIQA6AgAdAAgJzhmxIQA6AgAeAAMJ7RJGDQCnAAAAAA==.Tazale:BAAALgAECggJDAABLgAECgYJBgAEAAAAAA==.',
Te='Teakaachu:BAABLgAECn8aAAIIAAkJbRTQKQDdAQAIAAkJbRTQKQDdAQAAAA==.Terdanator:BAABLgAECn8gAAMgAAgJ0Bc+DQDdAQAgAAgJ0Bc+DQDdAQAQAAEJLQZ1uQAjAAAAAA==.Tetranis:BAAALgADCgQJBgAAAA==.',
Th='Thanathot:BAAALgADCgMJAwAAAA==.Thanatus:BAABLgAECn86AAQJAAkJARsvIQBeAgAJAAkJARsvIQBeAgAaAAQJyRCtIAC8AAAbAAEJzgf2eAAqAAAAAA==.Themia:BAAALgADCgMJAwAAAA==.Thetino:BAAALgAECgIJAgAAAA==.Throwinhands:BAAALgAECgEJAQAAAA==.',
Ti='Tiari:BAABLgAECn8yAAMNAAkJCRzZDADCAgANAAkJCRzZDADCAgAUAAYJ0APlFAGgAAAAAA==.Tidepod:BAAALgAECgcJDQAAAA==.Timesink:BAAALgAECgQJBQAAAA==.Tisane:BAAALgAECgMJAwAAAA==.',
Tn='Tntclepriest:BAAALgAECgcJDQABLgAECgYJFAAaAGkVAA==.',
Tr='Tralline:BAAALgADCgMJAgAAAA==.Tranzig:BAAALgADCgUJBQAAAA==.Tridius:BAABLgAECn8dAAQWAAgJ3hi2BQBaAQAWAAgJ3hi2BQBaAQAVAAYJSBq9OAAvAQAcAAMJnRyfTQCsAAAAAA==.Trollins:BAAALgAECgIJAgAAAA==.Truda:BAAALgAECgcJBwAAAA==.Trumped:BAAALgADCgUJBwAAAA==.',
Tu='Turdanator:BAABLgAECn9NAAMWAAkJDhlSEwA3AgAWAAkJDhlSEwA3AgAcAAcJ/gtsQQAzAQAAAA==.',
Tw='Twittle:BAAALgAECgEJAQAAAA==.Twizzlers:BAAALgAECgQJBAAAAA==.',
Up='Upgraydd:BAAALgAECgIJBAABLgAECgcJEQAEAAAAAA==.',
Ur='Uraenus:BAAALgAECgcJEwAAAA==.Urahrotar:BAAALgADCgUJBgAAAA==.Uriah:BAABLgAECn81AAISAAkJ4RisCAC8AQASAAkJ4RisCAC8AQAAAA==.Ursúla:BAABLgAFFH8LAAIJAAQJVwwZYAAHAQAJAAQJVwwZYAAHAQABLgAFFAYJKQAeAEccAA==.Uryu:BAAALgAECgQJBAAAAA==.Urïah:BAAALgAECgYJDAABLgAECgkJNQASAOEYAA==.',
Ut='Utherr:BAABLgAFFH8FAAIUAAMJ6BrEaADdAAAUAAMJ6BrEaADdAAAAAA==.',
Va='Valaravaus:BAAALgAECgEJAwAAAA==.Valionandros:BAAALgAECgYJCAAAAA==.Vanaril:BAAALgAECgMJAwAAAA==.Vashirr:BAAALgAECgMJAwAAAA==.',
Ve='Vecks:BAAALgAECgQJBAAAAA==.Veldonir:BAAALgAECgEJAQAAAA==.Vergus:BAAALgAECgQJBAAAAA==.',
Vi='Violin:BAEALgAECgIJAwABLgAECggJDAAEAAAAAA==.Violinmax:BAEALgAECgYJDQABLgAECggJDAAEAAAAAA==.Viral:BAAALgAFFAEJAQAAAA==.',
Vo='Voidnova:BAAALgAECgEJAQAAAA==.Vonnie:BAAALgAECggJDgAAAA==.',
Vy='Vynlerinis:BAABLgAECn8eAAIfAAkJWCAJAwC5AgAfAAkJWCAJAwC5AgAAAA==.',
['Vé']='Végeta:BAAALgAECgIJBAABLgAECgkJMQAZAKgWAA==.',
Wa='Wardestroyer:BAAALgAECggJEQAAAA==.Wardwhelp:BAABLgAECn8oAAILAAkJURynAQAMAgALAAkJURynAQAMAgABLgAFFAIJAgAEAAAAAA==.',
We='Wetfinger:BAAALgAECgEJAQAAAA==.',
Wi='Wifehaver:BAABLgAECn8oAAIDAAkJuR8kFAANAgADAAkJuR8kFAANAgAAAA==.Wildmist:BAAALgAECgMJAwAAAA==.Winniedapoo:BAABLgAECn80AAIJAAgJ2BudNgD/AQAJAAgJ2BudNgD/AQAAAA==.Winterpaw:BAAALgAECgEJAQABLgAECgkJKwAGAFMZAA==.',
Wo='Wooloo:BAACLgAFFH8rAAQJAAkJcyKuCQB2AgAJAAgJ+CKuCQB2AgAbAAQJvxsfAwBvAQAaAAEJAADKBABZAAAuAAQKfygAAwkACQmzJfwPAM0CAAkACQmzJfwPAM0CABsABAlPHXogAE8BAAAA.',
Wu='Wurm:BAAALgAECgIJAgAAAA==.',
Wy='Wynona:BAAALgAECgcJCAAAAA==.',
Xa='Xanagore:BAABLgAECn8sAAMRAAkJVyJGBwDqAgARAAkJ6SFGBwDqAgALAAEJ0RbRUgAzAAAAAA==.Xanllan:BAAALgAECgQJBgAAAA==.Xanthecat:BAAALgAECgQJBAAAAA==.Xanzul:BAABLgAECn8eAAIPAAcJpxPnDgBvAQAPAAcJpxPnDgBvAQABLgAECgkJLAARAFciAA==.',
Xe='Xenojiiva:BAAALgAECgEJAQABLgAFFAEJAgAEAAAAAA==.',
Xk='Xkwon:BAAALgAFFAEJAQAAAA==.Xkwøn:BAACLgAFFH8YAAImAAUJ2BjHBABKAQAmAAUJ2BjHBABKAQAuAAQKfzwAAiYACQkwIdsCAIUCACYACQkwIdsCAIUCAAAA.',
Xu='Xunie:BAABLgAECn8pAAIKAAkJHBV2NAAtAgAKAAkJHBV2NAAtAgAAAA==.',
Xx='Xximage:BAABLgAECn8dAAMnAAkJ1CRfAQDIAgAnAAkJ1CRfAQDIAgAFAAEJAACeWgFLAAAAAA==.',
Yu='Yulìe:BAAALgADCgcJBwAAAA==.',
Za='Zaibloom:BAAALgADCggJFgAAAA==.Zana:BAABLgAECn8ZAAIMAAgJPRLBdgAzAQAMAAgJPRLBdgAzAQAAAA==.Zaretan:BAAALgAECgIJAgAAAA==.',
Zb='Zbrute:BAABLgAECn8pAAISAAkJXxz7FwCXAgASAAkJXxz7FwCXAgAAAA==.',
Ze='Zeffen:BAAALgAECgIJBAABLgAECggJIAAJAKYGAA==.Zefphenn:BAAALgAECgQJBgABLgAECggJIAAJAKYGAA==.Zenny:BAAALgADCggJEwAAAA==.',
Zi='Zildroghar:BAAALgADCgcJCAAAAA==.Zivz:BAAALgADCgUJBQAAAA==.',
Zo='Zokohjin:BAACLgAFFH8FAAIKAAIJdxZ7hgBHAAAKAAIJdxZ7hgBHAAAuAAQKfyUAAwoACQlYHJ4uAEUCAAoACQlYHJ4uAEUCAAYAAgn7F41BAIkAAAAA.',
Zu='Zulgar:BAAALgAFFAIJAgABLgAFFAkJHgAFABcaAA==.Zulpher:BAAALgADCgYJFwAAAA==.',
['Ðo']='Ðondon:BAAALgADCgQJBQAAAA==.Ðoppelgänger:BAAALgAECgEJCAAAAA==.',
['Øk']='Økwøn:BAACLgAFFH8PAAIFAAMJGBWOOQC3AAAFAAMJGBWOOQC3AAAuAAQKfzsAAwUACAkRHyJKAFkCAAUACAn4HiJKAFkCACcABAnvIdIHACoBAAAA.',
['ße']='ßeorn:BAAALgAECgUJBQAAAA==.',
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
