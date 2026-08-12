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

local lookup = {'Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Mage-Frost','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Havoc','Monk-Mistweaver','Warlock-Demonology','DeathKnight-Unholy','Warrior-Protection','DemonHunter-Devourer','Paladin-Holy','Shaman-Restoration','Hunter-Marksmanship','Shaman-Elemental','Warrior-Fury','Hunter-BeastMastery','Druid-Feral','Paladin-Retribution','Priest-Discipline','Priest-Shadow','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','Priest-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','Druid-Guardian','Rogue-Assassination','Hunter-Survival','Paladin-Protection','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=46,date='2026-08-11',data={Ab='Abones:BAABLgAFFH8OAAIBAAMJ+yA6EAAMAQABAAMJ+yA6EAAMAQAAAA==.Absolon:BAAALgAECgQJBAAAAA==.Absólon:BAAALgADCgcJBwAAAA==.',
Ae='Aendia:BAAALgADCgMJBAAAAA==.Aeolos:BAAALgAECgUJBgAAAA==.',
Af='Affae:BAABLgAFFH8KAAMCAAMJFBNsMgB6AAADAAIJ6RZNRwCBAAACAAIJPg5sMgB6AAAAAA==.',
Ag='Agilitiess:BAAALgAECgEJAgABLgAECgEJBQAEAAAAAA==.Agrios:BAAALgAECgYJCgAAAA==.',
Ak='Ak:BAABLgAECn8qAAIFAAkJRSKSFgDSAgAFAAkJRSKSFgDSAgAAAA==.',
Al='Alanas:BAAALgADCgEJAQAAAA==.Alchemie:BAAALgAECgEJAQAAAA==.Alcohlol:BAAALgADCgEJAQAAAA==.Alexandra:BAAALgAECgEJAQABLgAFFAEJAgAEAAAAAA==.Allendril:BAAALgADCgIJAgABLgAECgkJKwAGAFMZAA==.Alliekill:BAAALgAECgQJBAABLgAECggJFwAHAC8RAA==.Allister:BAAALgAECgYJBgABLgAECgkJHgAIAEsfAA==.Altahari:BAAALgAFFAIJAgABLgAFFAYJGgAJAOYcAA==.Alynnei:BAAALgAECgMJAwABLgAFFAEJAgAEAAAAAA==.',
Am='Amare:BAAALgAECggJCwAAAA==.',
An='Ancalagon:BAAALgAECgQJCQAAAA==.Andros:BAABLgAECn8cAAIKAAgJQRv9LwAYAgAKAAgJQRv9LwAYAgAAAA==.Anekaatwo:BAAALgADCgEJAQAAAA==.Angryangel:BAAALgAECgEJAQAAAA==.Antigone:BAAALgAECgYJCwAAAA==.',
Ar='Arabelli:BAAALgADCgYJBgAAAA==.Arasun:BAAALgADCgIJAgAAAA==.Araxe:BAABLgAECn8mAAMLAAcJthtiWwC1AQALAAcJlhpiWwC1AQAGAAQJoxY/KwD/AAAAAA==.Ariv:BAAALgAECgEJBQAAAA==.Arroyo:BAACLgAFFH8GAAILAAMJ1A4TowDRAAALAAMJ1A4TowDRAAAuAAQKfy4AAwsACQk3IT8TANUCAAsACQk3IT8TANUCAAYABAnJG58eAFIBAAAA.Artax:BAAALgADCgYJDAAAAA==.',
As='Asalohir:BAAALgAECgUJBQAAAA==.Ashryn:BAAALgAECgEJAgABLgAECgEJBQAEAAAAAA==.Ashvyn:BAAALgAECgEJAgABLgAECgEJBQAEAAAAAA==.Askadar:BAACLgAFFH8fAAIMAAYJfyYOBAAxAgAMAAYJfyYOBAAxAgAuAAQKfy8AAgwACQlyJhUBAFwDAAwACQlyJhUBAFwDAAAA.',
At='Athridran:BAAALgAECgQJBgAAAA==.Atinyhorse:BAABLgAECn8ZAAINAAcJ3AuSjQAFAQANAAcJ3AuSjQAFAQAAAA==.Atrax:BAACLgAFFH8LAAIOAAMJLgwkHgBnAAAOAAMJLgwkHgBnAAAuAAQKfxsAAg4ABwl0DxY5AGgBAA4ABwl0DxY5AGgBAAAA.Atrex:BAAALgAFFAEJAwAAAA==.Atrexx:BAABLgAFFH8PAAIPAAMJehkgHgDgAAAPAAMJehkgHgDgAAAAAA==.Atryx:BAABLgAFFH8SAAIQAAMJ7hi5GgDbAAAQAAMJ7hi5GgDbAAAAAA==.',
Au='Auronralius:BAAALgADCgIJAgAAAA==.',
Ax='Ax:BAAALgADCgcJCgABLgAECgYJDwAEAAAAAA==.Axmodel:BAAALgADCgIJAgABLgADCgQJBAAEAAAAAA==.',
Az='Azazél:BAAALgAECgIJAwAAAA==.Azuleja:BAAALgADCgEJAQAAAA==.Azzura:BAAALgADCgYJBwAAAA==.',
Ba='Baheem:BAABLgAECn82AAIFAAcJFwyNGwD/AAAFAAcJFwyNGwD/AAAAAA==.Bams:BAABLgAECn8fAAMRAAkJYh3wHgDrAQARAAcJ4h7wHgDrAQAPAAgJzAtQUwBnAQAAAA==.Bamsx:BAAALgAECgcJBwAAAA==.Baneofdemons:BAAALgADCgEJAQAAAA==.Barrillon:BAAALgADCgEJAQAAAA==.Bastile:BAAALgAECgYJDwAAAA==.Bauer:BAAALgAECgQJBAAAAA==.',
Be='Benel:BAAALgAECggJEgAAAA==.',
Bi='Bifrons:BAAALgAECgEJAQAAAA==.Bigblkengery:BAAALgADCgcJCAAAAA==.Bigdill:BAAALgAECgEJAQAAAA==.Biggrippa:BAABLgAECn8lAAISAAkJcCBJGwByAgASAAkJcCBJGwByAgAAAA==.Bighoofprint:BAAALgAECgkJAQAAAA==.Bigtotempole:BAABLgAECn8aAAIRAAkJLAkZSQAQAQARAAkJLAkZSQAQAQAAAA==.',
Bj='Bjornar:BAAALgADCgEJAQAAAA==.',
Bl='Blahwithpets:BAABLgAECn8sAAITAAkJtxaNMAAaAgATAAkJtxaNMAAaAgAAAA==.Blappin:BAAALgAECgEJAQAAAA==.Bloodmyst:BAAALgAECgcJEQABLgAECgkJKAAUAHcgAA==.Bloodplague:BAAALgAECgIJAgAAAA==.Bloodymaw:BAAALgAECgQJBAAAAA==.Bloomer:BAAALgADCgEJAQAAAA==.Blooshield:BAAALgAECgUJCQAAAA==.Bluemchen:BAAALgADCgMJAwAAAA==.Blurt:BAAALgAECgEJAQAAAA==.',
Bo='Bobble:BAABLgAECn8iAAIOAAkJHxskGwArAgAOAAkJHxskGwArAgAAAA==.Bohelranus:BAAALgADCgkJFwAAAA==.Boneman:BAAALgAECgUJBgAAAA==.Bookwyrm:BAAALgADCgkJHQAAAA==.Boolicious:BAAALgAECgQJBQABLgAECgkJMgAVAIYRAA==.Boolil:BAAALgAECgQJCgABLgAECgkJMgAVAIYRAA==.Boolove:BAAALgAECgMJBAABLgAECgkJMgAVAIYRAA==.Booqt:BAAALgAECggJCQABLgAECgkJMgAVAIYRAA==.Booshorty:BAAALgAECgYJEQABLgAECgkJMgAVAIYRAA==.Boriel:BAAALgAECgYJBwAAAA==.Boö:BAAALgAECgcJDQABLgAECgkJMgAVAIYRAA==.',
Br='Breake:BAACLgAFFH8SAAIWAAMJiBT9IgB/AAAWAAMJiBT9IgB/AAAuAAQKfyMAAxYACAmlF8QXABcCABYACAmlF8QXABcCABcAAwl0D1xsAG4AAAAA.',
Bu='Bubblebreath:BAAALgAECgEJAQAAAA==.',
By='Byssrak:BAABLgAECn8dAAMYAAgJ+hEYMAB3AQAYAAgJ0BEYMAB3AQAZAAQJ0w7AEwDPAAAAAA==.',
Ca='Caladiir:BAAALgAECgUJBQABLgAECgkJHwADAEshAA==.Cattiebuzz:BAAALgAECgIJAwABLgAECgkJOwATAKceAA==.',
Ce='Cerealmilk:BAABLgAECn8ZAAIaAAgJ+BmYCQBNAgAaAAgJ+BmYCQBNAgABLgAFFAIJAgAEAAAAAA==.',
Ch='Chadd:BAAALgADCgYJBgABLgAECgQJBgAEAAAAAA==.Cheesefel:BAAALgADCgEJAQAAAA==.Childishbro:BAAALgAECgEJAQAAAA==.Chilla:BAAALgAECgMJAwAAAA==.Chitung:BAAALgADCgQJBAABLgAECgQJBAAEAAAAAA==.Chopshop:BAAALgAECgEJAQAAAA==.Christopher:BAACLgAFFH8SAAIFAAUJAB9RSgBNAQAFAAUJAB9RSgBNAQAuAAQKfxsAAgUACQn2IJwtALsCAAUACQn2IJwtALsCAAAA.',
Ci='Cialismaxing:BAAALgAECggJDQABLgAECggJGQACAMwNAA==.Cindragos:BAAALgAECgQJBQABLgAFFAEJAQAEAAAAAA==.',
Co='Cocofluff:BAACLgAFFH8uAAIMAAgJ/CQLAQDUAgAMAAgJ/CQLAQDUAgAuAAQKfyUAAgwACAkAIiEEAAoDAAwACAkAIiEEAAoDAAAA.Consolata:BAAALgAECgEJAQAAAA==.Cowculus:BAAALgAECgIJAgABLgAECggJDAAEAAAAAA==.',
Cr='Creed:BAAALgAECgEJAQAAAA==.Creepychaos:BAAALgADCgkJKwABLgAECgkJSAALAD0IAA==.Creepydemise:BAABLgAECn9IAAILAAkJPQgScQCCAQALAAkJPQgScQCCAQAAAA==.Creepydrunk:BAAALgAECgIJAgABLgAECgkJSAALAD0IAA==.Creepyfoxxy:BAAALgADCgkJGwAAAA==.Croixsmash:BAABLgAECn8gAAISAAkJZB5GIgBDAgASAAkJZB5GIgBDAgAAAA==.Croixtemplar:BAAALgAECgYJDAAAAA==.',
Cu='Cuculain:BAAALgAECgEJBAAAAA==.Custodian:BAAALgAECgQJBAAAAA==.Cuttinglass:BAAALgADCgcJBwAAAA==.',
Cy='Cyleese:BAAALgAECgEJAQAAAA==.Cytherea:BAAALgADCgcJDAAAAA==.',
Da='Daedra:BAAALgAECgQJBgAAAA==.Dagdelythy:BAAALgAECgUJBwABLgAECgcJIwATAFQNAA==.Danoa:BAAALgAECgQJCgAAAA==.Daraellea:BAAALgAECgUJBQAAAA==.Darkcross:BAAALgADCgUJCAAAAA==.Darthorak:BAABLgAECn8lAAQKAAgJmQh2gAA4AQAKAAgJHQh2gAA4AQAbAAUJ9QbqIQCzAAAcAAYJtAUQIwCYAAAAAA==.Darthzai:BAAALgAECgMJBgAAAA==.Davennial:BAABLgAECn88AAIVAAkJ5BFGVwDFAQAVAAkJ5BFGVwDFAQAAAA==.Dawnn:BAABLgAECn8bAAIGAAkJ/wm2IgA9AQAGAAkJ/wm2IgA9AQAAAA==.Dayman:BAAALgAFFAEJAgAAAA==.',
De='Deanwnchestr:BAABLgAECn8pAAIFAAgJ8AlqkQBVAQAFAAgJ8AlqkQBVAQAAAA==.Deathmamba:BAAALgADCgMJAwAAAA==.Deatnshadow:BAABLgAFFH8FAAIGAAMJbBiNJQDFAAAGAAMJbBiNJQDFAAAAAA==.Deletus:BAAALgADCgkJCQAAAA==.Demise:BAAALgAECgQJCAAAAA==.Demonberry:BAAALgADCgEJAgAAAA==.Demonnutcase:BAAALgADCgYJEAAAAA==.Derogatory:BAAALgADCgYJDQABLgAFFAkJIwAdACEaAA==.Desylla:BAAALgAECgQJBAAAAA==.Devildograh:BAAALgAECgQJBwAAAA==.',
Di='Diah:BAAALgAECgQJBwAAAA==.Dibinator:BAAALgADCgEJAQAAAA==.Dio:BAAALgADCgYJDQAAAA==.Diodata:BAAALgAECgEJAgABLgAECggJHQACAKohAA==.Diophantus:BAAALgAECgIJBQABLgAECggJHQACAKohAA==.Divinity:BAAALgAECgEJAQAAAA==.',
Dm='Dmncgdss:BAAALgAECggJEgAAAA==.',
Do='Dogeatdog:BAAALgADCgkJFwAAAA==.Dohaeriz:BAAALgAECgEJBAAAAA==.Doregoran:BAABLgAECn8pAAIcAAgJhBPRCgCVAQAcAAgJhBPRCgCVAQAAAA==.Dovairous:BAABLgAECn8eAAIeAAgJWAswWAAwAQAeAAgJWAswWAAwAQAAAA==.',
Dr='Draakell:BAAALgAECgQJBAAAAA==.Dracopeet:BAABLgAECn8aAAQYAAcJvwQ5cACLAAAYAAUJEgU5cACLAAAaAAQJGwPUNQBOAAAZAAMJwQLDKQAnAAAAAA==.Dragonator:BAAALgAECgYJDQAAAA==.Drausella:BAAALgAECgEJAQAAAA==.Dreala:BAAALgAECgkJEwAAAA==.Dreamsicle:BAAALgAECgMJAwAAAA==.Dregomalfoy:BAAALgAECgQJBAAAAA==.Drexor:BAAALgAECgQJEQAAAA==.Drhealgôod:BAAALgAECgYJDAABLgAECgkJMQAaAKgWAA==.',
Du='Dudè:BAAALgAECgQJBgAAAA==.',
Dv='Dvlzadvocate:BAAALgAECgYJEgAAAA==.',
['Dâ']='Dâggèr:BAAALgAFFAEJAQAAAA==.',
['Dí']='Dímoní:BAAALgAECgIJAgAAAA==.',
['Dü']='Dürin:BAAALgAECgEJAgAAAA==.',
Ec='Echidna:BAABLgAECn8fAAIKAAgJCQoBngACAQAKAAgJCQoBngACAQAAAA==.',
Ed='Edgeovo:BAAALgAECgEJAQABLgAECgEJBQAEAAAAAA==.Edict:BAAALgAECgEJAQAAAA==.',
El='Elawen:BAAALgAECgYJDQAAAA==.Elder:BAAALgAECgEJAgAAAA==.Eleblah:BAAALgADCgcJBwAAAA==.Elfkinn:BAACLgAFFH8pAAMfAAYJRxy+DQDBAQAfAAYJRxy+DQDBAQAeAAIJ+gAvawBEAAAuAAQKfyUAAx8ACQmmHqUQAFkCAB8ACQmmHqUQAFkCAB4ABAlrBY+sAG0AAAAA.Elgund:BAAALgADCgQJBAAAAA==.Elivaniel:BAAALgAECgcJEAAAAA==.',
En='Enlargdcrit:BAAALgAECgMJAwAAAA==.',
Eq='Equinox:BAAALgADCgQJBAAAAA==.',
Er='Ericcdraven:BAABLgAECn8iAAISAAgJgQ5zNwBpAQASAAgJgQ5zNwBpAQAAAA==.Erodoria:BAABLgAECn8eAAMIAAkJSx/dCQCLAgAIAAgJBSLdCQCLAgAgAAUJ/hAFFQAFAQAAAA==.',
Et='Eternalfire:BAAALgADCgcJDgABLgAECgkJIwAfABgaAA==.',
Ev='Eve:BAAALgAECgEJAQAAAA==.Eveliong:BAAALgADCgEJAQAAAA==.Evilobama:BAAALgAECgUJBgAAAA==.Evoke:BAAALgAFFAEJAQABLgAFFAcJMAAPAFIaAA==.',
Ex='Exzanthia:BAAALgAECgUJBwAAAA==.',
Ey='Eyln:BAACLgAFFH8LAAIQAAQJMwqHCgDfAAAQAAQJMwqHCgDfAAAuAAQKfzUAAhAACQnOHRwDAKgCABAACQnOHRwDAKgCAAAA.',
Fa='Facielshot:BAAALgAECgYJDQABLgAECgkJMQAaAKgWAA==.Falkor:BAABLgAECn8xAAMaAAkJqBYADAAXAgAaAAkJqBYADAAXAgAZAAEJ6QI/LAAaAAAAAA==.Fanaa:BAAALgAECgEJAQAAAA==.Fanir:BAAALgAECgcJBwAAAA==.Fatino:BAAALgAECgUJBQAAAA==.Fatkid:BAABLgAECn8VAAINAAcJng95eAAwAQANAAcJng95eAAwAQAAAA==.Fayway:BAABLgAECn9VAAIeAAkJVSKPBgBPAwAeAAkJVSKPBgBPAwAAAA==.',
Fe='Ferral:BAABLgAECn8oAAIUAAkJdyD7BACoAgAUAAkJdyD7BACoAgAAAA==.Festukar:BAAALgAECgUJBwAAAA==.',
Fi='Figgy:BAAALgAECgUJCAAAAA==.Filthypirate:BAABLgAECn8UAAIVAAgJARFprgAhAQAVAAgJARFprgAhAQAAAA==.Firepower:BAABLgAECn8jAAIFAAkJxheBOwAsAgAFAAkJxheBOwAsAgABLgAECggJIAAUAJcTAA==.Fistatoosh:BAABLgAECn8iAAIDAAgJUCSYBgDQAgADAAgJUCSYBgDQAgAAAA==.',
Fl='Florane:BAAALgAECgUJDAAAAA==.Flyingbotato:BAAALgADCgkJFQABLgAECggJIAAUAJcTAA==.',
Fo='Forevershy:BAAALgADCgkJEgAAAA==.',
Fr='Fries:BAECLgAFFH8MAAIhAAYJ2R/BBAB6AQAhAAYJ2R/BBAB6AQAuAAQKfxwAAyEACQkBIpYCAO8CACEACQkBIpYCAO8CAA8ABQkGDISDANgAAAAA.Fruits:BAAALgAECgYJBwAAAA==.',
Ga='Galdavin:BAABLgAECn8XAAIVAAgJnBqgKQB+AgAVAAgJnBqgKQB+AgAAAA==.Galenhaihi:BAAALgADCgUJBQAAAA==.Galexstrasza:BAAALgADCgYJBgABLgAECgUJDgAEAAAAAA==.Gallandia:BAAALgADCgEJAQABLgAECgUJDgAEAAAAAA==.Gallielynne:BAAALgAECgUJDgAAAA==.Ganduin:BAAALgAECgMJAwAAAA==.Gankdd:BAABLgAECn8UAAMSAAcJLhuUPgBLAQASAAcJxhmUPgBLAQAiAAMJnRvCHgD4AAAAAA==.Garnnt:BAAALgADCgkJEQAAAA==.Gartas:BAAALgAECgIJAgAAAA==.',
Gh='Ghoulfriend:BAAALgAECgEJAQAAAA==.',
Gi='Giggles:BAABLgAECn8uAAIRAAkJiBn4AwD7AQARAAkJiBn4AwD7AQAAAA==.Gigglez:BAAALgADCggJCAAAAA==.Gimmothyjr:BAAALgAECgUJBgAAAA==.',
Gl='Glennspyder:BAAALgAECgQJDQABLgAECgcJIwATAFQNAA==.',
Go='Gonzo:BAAALgAFFAEJAQABLgAFFAcJMAAPAFIaAA==.Goysoldier:BAAALgAFFAMJBAAAAA==.',
Gr='Greenbean:BAABLgAFFH8pAAINAAUJhBtZIAASAQANAAUJhBtZIAASAQABLgAFFAYJKQAfAEccAA==.Grelleth:BAAALgAFFAQJBAAAAA==.Groddz:BAABLgAECn8WAAINAAkJvgbyhQAUAQANAAkJvgbyhQAUAQAAAA==.Groto:BAAALgAECgYJCgAAAA==.Grrum:BAABLgAECn8gAAQWAAcJXgvaNwAzAQAWAAcJkQnaNwAzAQAXAAQJaQhAWwCpAAAdAAIJQwlEfgA0AAAAAA==.Grèy:BAAALgAECgcJCAAAAA==.',
Gu='Gurînkaida:BAAALgAECgQJBAAAAA==.',
Ha='Haell:BAAALgAECgYJCgAAAA==.Hanjo:BAABLgAECn8wAAIMAAkJzyHdBADQAgAMAAkJzyHdBADQAgAAAA==.Hanoa:BAAALgAECgYJCgAAAA==.Harakiri:BAABLgAECn8UAAIPAAcJixUvNgCqAQAPAAcJixUvNgCqAQAAAA==.Hardare:BAABLgAECn8ZAAICAAgJzA31JACvAQACAAgJzA31JACvAQAAAA==.Harpune:BAAALgADCgIJAgAAAA==.Hatookorr:BAAALgAECgUJBQABLgAECggJIAAUAJcTAA==.Hayali:BAABLgAECn8iAAINAAgJXRYTPQDTAQANAAgJXRYTPQDTAQAAAA==.',
He='Helledrians:BAAALgAECgQJBgAAAA==.',
Hi='Hiawatha:BAAALgADCgcJAwAAAA==.',
Hm='Hmccrnglbery:BAAALgAECgMJBAABLgAECggJGQACAMwNAA==.',
Ho='Hottogo:BAAALgADCgcJBwAAAA==.',
Hw='Hwei:BAAALgADCgEJAQAAAA==.',
Hy='Hydé:BAABLgAECn8VAAMjAAgJxBvCCgA4AgAjAAgJxBvCCgA4AgAUAAEJOhwTRABTAAABLgAECgkJHgAgAFggAA==.Hypatia:BAABLgAECn8dAAICAAgJqiGqDQBrAgACAAgJqiGqDQBrAgAAAA==.',
['Hä']='Häxan:BAAALgAECgQJBAAAAA==.',
Ia='Iame:BAAALgADCgMJAwAAAA==.Iapetus:BAAALgADCgIJAgAAAA==.',
Ic='Icedchi:BAEBLgAECn8iAAIDAAkJ3x/SEQApAgADAAkJ3x/SEQApAgAAAA==.',
In='Incite:BAABLgAECn8gAAMkAAkJaA9lCgCRAQAkAAkJZQ9lCgCRAQABAAUJ+g2QQQAUAQAAAA==.',
Is='Ishvala:BAAALgADCgMJAwAAAA==.',
Iz='Izcarius:BAAALgADCgIJAgAAAA==.',
Ja='Jackpad:BAAALgAECgEJAgAAAA==.Jademist:BAAALgAECgYJDAABLgAECgkJMQAaAKgWAA==.Jaland:BAAALgADCgMJAwAAAA==.Jarrel:BAAALgAECgIJBAAAAA==.',
Je='Jellybreak:BAACLgAFFH8JAAIfAAQJMg7PEwDsAAAfAAQJMg7PEwDsAAAuAAQKfz0AAx8ACQmGFkAYAAsCAB8ACQmGFkAYAAsCACMABwmpCOY+AKsAAAAA.',
Jo='Joeewee:BAAALgAECgYJBgAAAA==.Jonjud:BAAALgAECgYJDAAAAA==.',
Js='Jskimonkpo:BAAALgADCgUJCQAAAA==.',
Ju='Jubilee:BAAALgAECgkJCQAAAA==.Julius:BAAALgAFFAEJAQAAAA==.',
Jy='Jyrian:BAAALgADCgMJAwAAAA==.',
Ka='Kaanâ:BAABLgAECn8zAAIdAAkJWhxkCQDSAgAdAAkJWhxkCQDSAgAAAA==.Kaelei:BAAALgADCgkJKwAAAA==.Kagamire:BAAALgADCgYJBQAAAA==.Kamine:BAAALgAECgUJEAAAAA==.Kanyeeast:BAAALgAECgYJCgAAAA==.Karnen:BAAALgAECgMJAwAAAA==.Kateblue:BAABLgAECn8vAAIfAAkJhRoGEABhAgAfAAkJhRoGEABhAgAAAA==.',
Ke='Kelcier:BAAALgADCgYJBgAAAA==.Kelser:BAABLgAECn8ZAAMbAAgJTx7FBAApAgAbAAgJTx7FBAApAgAKAAMJoBXuxgDLAAAAAA==.Kensington:BAABLgAECn8hAAIkAAgJdggnDgBDAQAkAAgJdggnDgBDAQAAAA==.Kethry:BAAALgAECgIJAwAAAA==.',
Ki='Kiku:BAABLgAECn8lAAIYAAkJjyPsBQD+AgAYAAkJjyPsBQD+AgAAAA==.Kikyou:BAAALgAECgYJCgABLgAECgkJJQAYAI8jAA==.Kim:BAABLgAECn8fAAIlAAkJRhBnFgDuAQAlAAkJRhBnFgDuAQAAAA==.Kinrah:BAAALgADCgMJAwABLgAECgEJAQAEAAAAAA==.Kirandra:BAAALgADCgMJAwAAAA==.Kirëë:BAAALgAECggJCAAAAA==.Kissofdeáth:BAAALgAECgIJAwAAAA==.',
Ko='Korlock:BAABLgAECn8mAAQKAAkJAB4vNAA8AgAKAAgJGR0vNAA8AgAcAAEJAACvbAA7AAAbAAEJPRc4PQA4AAAAAA==.',
Kr='Kreepywife:BAABLgAECn8jAAIXAAgJsRlfAwAAAgAXAAgJsRlfAwAAAgAAAA==.Krelbelorll:BAAALgAECgEJAQAAAA==.Krowley:BAABLgAECn8nAAIPAAkJPxB4MADzAQAPAAkJPxB4MADzAQAAAA==.',
Ku='Kurast:BAAALgAECgMJAwABLgAECgkJMQAaAKgWAA==.Kuzan:BAACLgAFFH8TAAIFAAUJEB9rTABHAQAFAAUJEB9rTABHAQAuAAQKfx8AAgUABwl3IfQ2AJgCAAUABwl3IfQ2AJgCAAAA.',
Kw='Kwaichangcai:BAAALgADCgYJCgABLgAECgcJIwATAFQNAA==.',
Kx='Kxwono:BAAALgAECgcJBwAAAA==.',
Ky='Kyoyama:BAAALgAECgMJBwABLgAFFAQJEwAbACUdAA==.',
La='Lacious:BAAALgADCgEJAQABLgAECgkJOwATAKceAA==.Ladýshinobu:BAABLgAECn8nAAIOAAgJQBBIKQDDAQAOAAgJQBBIKQDDAQAAAA==.Lananar:BAAALgADCgUJBQAAAA==.Layssaenna:BAAALgAECgYJCAAAAA==.',
Le='Leahu:BAABLgAECn88AAImAAkJBhiuCgAfAgAmAAkJBhiuCgAfAgAAAA==.Lediaa:BAAALgAECgMJBAAAAA==.',
Li='Lifekiller:BAAALgAECgYJDwAAAA==.Lightark:BAAALgAECgEJAgAAAA==.Linekingz:BAAALgADCgEJAQAAAA==.Linetheshamy:BAAALgADCgkJDQAAAA==.Lineurathrot:BAAALgADCgYJCAAAAA==.Lisavia:BAAALgADCgUJBgAAAA==.Littlespyone:BAABLgAECn8jAAITAAYJVA0DIADkAAATAAYJVA0DIADkAAAAAA==.Lizardman:BAAALgAFFAEJAQAAAA==.',
Lo='Locholovis:BAABLgAECn8wAAIcAAkJOhR5BwDcAQAcAAkJOhR5BwDcAQAAAA==.Locklicous:BAABLgAECn8WAAMKAAkJ2xepPQDlAQAKAAkJ2BOpPQDlAQAbAAYJWxV2EgBBAQAAAA==.Longhorse:BAACLgAFFH8iAAIGAAcJ5h+lEgBiAQAGAAcJ5h+lEgBiAQAuAAQKfzYAAwYACQn4JMgFAOACAAYACQmqIsgFAOACAAsABgnhJfpfAKkBAAAA.Longknight:BAAALgAECgEJAQAAAA==.Longr:BAAALgAECgYJCwAAAA==.Lorna:BAABLgAECn8XAAINAAgJJhJcVgCEAQANAAgJJhJcVgCEAQAAAA==.Lorthimar:BAAALgAECgUJCgABLgAECgkJJgAKAAAeAA==.',
Lu='Lumi:BAABLgAECn8WAAIFAAkJchhwUQDoAQAFAAkJchhwUQDoAQAAAA==.Luminarae:BAAALgADCgEJAQAAAA==.Luminouss:BAABLgAFFH8QAAIPAAcJuBKEFQC5AQAPAAcJuBKEFQC5AQABLgAFFAMJBgAWAOcUAA==.Lumpia:BAABLgAFFH8IAAINAAUJGBmzQgAfAQANAAUJGBmzQgAfAQAAAA==.',
Ly='Lylo:BAAALgADCgEJAQAAAA==.Lyrinir:BAABLgAECn8dAAMMAAkJ/hkjEQD2AQAMAAkJ/hkjEQD2AQAiAAEJigTaigAbAAAAAA==.Lyrium:BAABLgAECn8ZAAMgAAgJtRm8CgC4AQAgAAUJDR+8CgC4AQAIAAcJ+RA9KgAtAQABLgAECgkJHQAMAP4ZAA==.',
Ma='Madar:BAABLgAECn8oAAIKAAgJMQcomQALAQAKAAgJMQcomQALAQAAAA==.Maggus:BAAALgADCgQJBAAAAA==.Magicgal:BAAALgAECggJDQAAAA==.Maiden:BAAALgAECgUJBQAAAA==.Maiklytzwhet:BAAALgAECgUJBQAAAA==.Mairon:BAAALgAECgMJBgAAAA==.Malvorak:BAABLgAECn88AAIGAAkJzBLSBQBdAQAGAAkJzBLSBQBdAQAAAA==.Mande:BAAALgADCgQJBAAAAA==.Mantis:BAAALgAECgkJEQABLgAECgkJMQAaAKgWAA==.Marrock:BAAALgAECgYJEQAAAA==.Marzipain:BAAALgAECgEJAQAAAA==.Mavarasie:BAAALgAECgUJDgAAAA==.Mavaressy:BAAALgAECgMJAwAAAA==.Mavaria:BAAALgAECgYJDAAAAA==.',
Mc='Mcmuffin:BAABLgAECn8YAAIWAAgJugbXEADMAAAWAAgJugbXEADMAAAAAA==.',
Me='Mechacattie:BAABLgAECn87AAITAAkJpx4iFACxAgATAAkJpx4iFACxAgAAAA==.Mediator:BAAALgAECgEJAQAAAA==.Meekerz:BAAALgAECgIJAgAAAA==.Mega:BAAALgAFFAIJAwAAAA==.Melganis:BAAALgADCgMJBAAAAA==.Melissandra:BAABLgAECn8qAAMXAAgJ0gxoNgA9AQAXAAgJ0gxoNgA9AQAdAAIJiAb1dABVAAAAAA==.Mercas:BAAALgAECgcJDwABLgAECgkJJgAjAKMaAA==.Metacallae:BAAALgADCgcJAQAAAA==.Metra:BAAALgADCgEJAQAAAA==.Mezi:BAACLgAFFH8MAAIdAAQJZB6wBwBLAQAdAAQJZB6wBwBLAQAuAAQKf0UAAh0ACQnlIWgHAPgCAB0ACQnlIWgHAPgCAAAA.Mezmera:BAAALgADCgUJBgABLgAECgIJAwAEAAAAAA==.',
Mh='Mhonster:BAAALgAECgYJCgABLgAFFAEJAgAEAAAAAA==.',
Mi='Mildchaos:BAAALgAFFAEJAQAAAA==.Missed:BAAALgAECgQJBQAAAA==.Mittens:BAACLgAFFH8GAAIWAAMJ5xRcMADRAAAWAAMJ5xRcMADRAAAuAAQKfxkAAx0ACQlbGXQoAK0BAB0ABgn7GXQoAK0BABYABwlvE8ohAIUBAAAA.',
Mo='Mofro:BAAALgADCgQJBAABLgAECgQJBAAEAAAAAA==.Mokgunal:BAAALgADCgQJBAAAAA==.Money:BAAALgADCgIJAgABLgAECggJIwAVABghAA==.Moneyshotinc:BAAALgAECgkJCgABLgAECggJIwAVABghAA==.Moraine:BAAALgAECgQJBAAAAA==.Moreki:BAAALgAECgMJAwAAAA==.Morro:BAABLgAECn8wAAIRAAkJVw8sKwCaAQARAAkJVw8sKwCaAQAAAA==.',
Ms='Msvelvet:BAAALgAECgYJCQABLgAECgYJGwAPAO0VAA==.',
Mu='Mugiwara:BAACLgAFFH8LAAICAAQJbCQnDABkAQACAAQJbCQnDABkAQAuAAQKfxYAAgIABwntJAkKANcCAAIABwntJAkKANcCAAAA.Mulron:BAABLgAECn8kAAImAAkJmhE0EgCjAQAmAAkJmhE0EgCjAQAAAA==.',
My='Myrica:BAAALgAECggJDwAAAA==.Mysweetheals:BAAALgADCgcJBwAAAA==.',
['Må']='Mådcõw:BAAALgAECgUJBgAAAA==.',
['Mö']='Mööve:BAAALgAECgMJAwAAAA==.',
Na='Nallos:BAAALgADCgEJAQAAAA==.Natajapar:BAAALgAECgEJAQABLgAECgcJCQAEAAAAAA==.',
Ne='Nefesh:BAABLgAFFH8ZAAMNAAUJlBFzVADxAAANAAUJnwpzVADxAAAgAAEJaCSjCABjAAAAAA==.Neff:BAAALgADCgMJAwAAAA==.Nemeesis:BAAALgAECgMJBAAAAA==.',
Ni='Nightingales:BAAALgAECgMJAwAAAA==.',
Ny='Nyomie:BAAALgADCgEJAgAAAA==.Nyyx:BAAALgAECgQJBAABLgAECgYJCgAEAAAAAA==.',
Oa='Oakenshíeld:BAACLgAFFH8XAAIfAAcJ0w/kGQBKAQAfAAcJ0w/kGQBKAQAuAAQKfzsAAh8ACQlCF9AUAGsCAB8ACQlCF9AUAGsCAAAA.',
Ob='Obama:BAAALgADCgQJBAAAAA==.',
Og='Oggy:BAABLgAECn8bAAIOAAkJlAcKDADwAAAOAAkJlAcKDADwAAABLgAECgkJMQAaAKgWAA==.',
Ol='Olkwon:BAAALgAFFAIJAwAAAA==.',
On='Onlyfeigns:BAAALgAECgMJAwAAAA==.',
Oo='Oozwoz:BAAALgAECgcJDwAAAA==.',
Or='Orileluu:BAAALgAECgEJAQAAAA==.',
Ou='Outfoxed:BAABLgAFFH8FAAIPAAMJrhLoJQC1AAAPAAMJrhLoJQC1AAABLgAFFAkJIwAdACEaAA==.',
Ox='Oxwon:BAAALgAECgYJCwAAAA==.Oxythymia:BAAALgAECgEJAQABLgAECggJLQAdAKwdAA==.',
Pa='Paisho:BAAALgAECgQJBQAAAA==.Palliera:BAAALgAECgQJBgAAAA==.Pallirot:BAAALgAECggJCAAAAA==.Pallynomial:BAAALgADCgcJCgAAAA==.Papapapaya:BAAALgAECgYJBwAAAA==.Pawmuck:BAABLgAECn8tAAIVAAgJ9Rk+PAATAgAVAAgJ9Rk+PAATAgAAAA==.',
Pe='Peer:BAAALgAECgEJAgAAAA==.Peetufo:BAAALgAECgEJAQAAAA==.Pewpewtazarz:BAAALgAECgUJCQAAAA==.',
Ph='Phancy:BAAALgADCggJDgAAAA==.Phrizzle:BAAALgADCgMJAwAAAA==.',
Pl='Plaguebeard:BAABLgAECn8XAAMLAAcJBx9/PABFAgALAAcJBx9/PABFAgAGAAUJCRiiJwABAQAAAA==.Plagueblade:BAABLgAECn8rAAMGAAkJUxmWEgDlAQAGAAkJOhiWEgDlAQALAAEJ3RqCVAFNAAAAAA==.',
Po='Podtinder:BAAALgAECgcJDAABLgAECgkJMQAaAKgWAA==.Poof:BAAALgAFFAIJAgAAAA==.Poseidon:BAAALgAECgIJAgAAAA==.',
Pr='Prescription:BAABLgAECn8ZAAMJAAkJewsMYQD1AAAJAAgJjAsMYQD1AAACAAcJvQisRQDpAAAAAA==.Progression:BAAALgAECgEJBwAAAA==.',
Pu='Punish:BAAALgAECgEJAQAAAA==.',
Py='Pyrolord:BAAALgADCgYJCAAAAA==.',
Ra='Ragingrain:BAABLgAECn8jAAImAAgJVxmyDAD6AQAmAAgJVxmyDAD6AQAAAA==.Rainsshammy:BAAALgAECgQJCAAAAA==.Rainthefire:BAABLgAECn8/AAITAAkJZRqRLAArAgATAAkJZRqRLAArAgAAAA==.Ralthor:BAAALgADCgMJAwAAAA==.Ramalama:BAAALgAECgEJAgAAAA==.Rassarudk:BAAALgAECgYJCwAAAA==.Ravinfire:BAAALgAECgQJBwAAAA==.Rawktuah:BAAALgAECgMJAwAAAA==.',
Re='Realhelz:BAAALgAECgQJBQAAAA==.Redcross:BAABLgAECn8cAAMOAAkJrg94BADOAQAOAAkJrg94BADOAQAVAAQJTAzzPABpAAAAAA==.Redoxx:BAAALgAECgYJDQAAAA==.Redsamilf:BAAALgAECgUJBwAAAA==.Rekka:BAAALgADCgMJAwAAAA==.Restofarian:BAACLgAFFH8wAAIPAAcJUhoNCQDDAQAPAAcJUhoNCQDDAQAuAAQKfyMAAg8ACQmJG0UXAFsCAA8ACQmJG0UXAFsCAAAA.',
Rh='Rhagnor:BAAALgAECgkJDAAAAA==.',
Ri='Rianon:BAAALgADCgkJEgABLgAECgkJNQANANccAA==.Rift:BAAALgAECgEJAwAAAA==.Righteous:BAABLgAECn8zAAIdAAkJFh7oAQCNAgAdAAkJFh7oAQCNAgAAAA==.Rizzy:BAABLgAECn8iAAMGAAkJQxenDwARAgAGAAkJQxenDwARAgALAAkJ7gjubQCJAQAAAA==.',
Ro='Rollinsinc:BAAALgAECgkJAwAAAA==.Roshin:BAAALgAECgEJAgAAAA==.Rotinlock:BAAALgADCgYJDAAAAA==.Rotinshot:BAACLgAFFH8VAAMTAAYJjhLbIQB9AQATAAYJjhLbIQB9AQAlAAIJbgMhLQB6AAAuAAQKfygAAxMACQlsIWUWAIUCABMACAmTImUWAIUCACUACAl0GuEQALYBAAAA.',
Ru='Ruin:BAAALgAECgMJBAAAAA==.Rutikee:BAABLgAECn9OAAIeAAkJeRQXBgCWAQAeAAkJeRQXBgCWAQAAAA==.',
Ry='Rykko:BAAALgAECgEJAQAAAA==.Ryomensukuna:BAAALgAFFAIJAQAAAA==.',
Sa='Sacerdos:BAABLgAECn8VAAIdAAgJlBW8FgAmAgAdAAgJlBW8FgAmAgABLgAECgkJOgAKAAEbAA==.Saeris:BAAALgADCggJCAABLgAECggJEAAEAAAAAA==.Sagordez:BAACLgAFFH8HAAMJAAMJxg9dLAB4AAAJAAMJxg9dLAB4AAACAAEJ0ArWRAA2AAAuAAQKfygABAkACAm0Hi0ZAE8CAAkABwmVHi0ZAE8CAAMABwlxFXsmAHsBAAIAAQnhD7ejAC0AAAEuAAQKCQkeACAAWCAA.Salima:BAAALgADCgMJAwAAAA==.Saltybrew:BAAALgADCgMJAwAAAA==.Sandrill:BAAALgAECgYJCgABLgAECggJIAAUAJcTAA==.Sarr:BAAALgAECgMJAwAAAA==.Satorugojo:BAAALgAECgUJBgABLgAFFAIJAQAEAAAAAA==.Savior:BAABLgAECn8yAAIVAAkJNBbpBwADAgAVAAkJNBbpBwADAgAAAA==.Sazed:BAAALgAECggJDgAAAA==.',
Sc='Scrom:BAAALgAECgIJBAAAAA==.',
Se='Seabush:BAAALgAECgIJAwAAAA==.Seastorm:BAAALgAECgkJCQAAAA==.Seeker:BAAALgAECgEJAQAAAA==.Seizon:BAABLgAECn8uAAMlAAkJBBpiAQBaAgAlAAkJBBpiAQBaAgAQAAIJmQf2MwBMAAAAAA==.Sekkusu:BAAALgAECgQJBAAAAA==.Semila:BAAALgAECgcJCQAAAA==.Sendor:BAAALgAECgYJBgAAAA==.Senseicanz:BAAALgAECgQJBgAAAA==.Sepulchure:BAAALgADCgMJAwAAAA==.Serina:BAAALgAECgQJBwABLgAECgkJKwAGAFMZAA==.Serom:BAABLgAECn8hAAIeAAgJdRlhHwBLAgAeAAgJdRlhHwBLAgAAAA==.Sesshomaaru:BAAALgADCggJEQAAAA==.',
Sh='Shaazrah:BAABLgAECn8fAAIDAAkJSyGVCgCKAgADAAkJSyGVCgCKAgAAAA==.Shadowoak:BAAALgAECgIJAgAAAA==.Shadows:BAAALgADCgcJBwAAAA==.Shamkazaam:BAAALgAECgkJEwAAAA==.Shammyhagär:BAAALgADCgMJAwABLgAECgQJBAAEAAAAAA==.Sharalvia:BAAALgADCgUJCAAAAA==.Sharkn:BAAALgAECgEJAQAAAA==.Sharkyo:BAAALgADCgIJAgAAAA==.Sharpshôôter:BAAALgAFFAMJAwAAAA==.Sherunn:BAABLgAECn8jAAIfAAcJpQ0dOgAqAQAfAAcJpQ0dOgAqAQAAAA==.Shifty:BAAALgAECgEJAgAAAA==.Shiftydon:BAABLgAECn8eAAQUAAkJ0RA0EAC0AQAUAAkJ0RA0EAC0AQAeAAIJ+Q2CqwBeAAAjAAEJMguSgAAhAAAAAA==.Shimakaze:BAACLgAFFH8IAAITAAIJPwZyUgB3AAATAAIJPwZyUgB3AAAuAAQKfz8AAhMACQn3DrtFANABABMACQn3DrtFANABAAAA.Shirvana:BAAALgAECgQJBwABLgAECgcJCQAEAAAAAA==.Shooters:BAABLgAECn8YAAIlAAkJOx26DQDuAQAlAAkJOx26DQDuAQAAAA==.Shortbow:BAAALgADCgQJBgABLgAECgEJAgAEAAAAAA==.Shyminx:BAAALgAECgEJAQAAAA==.Shymistress:BAACLgAFFH8JAAITAAQJBxHnKgD4AAATAAQJBxHnKgD4AAAuAAQKfz0AAhMACQkTIr8MAO0CABMACQkTIr8MAO0CAAAA.Shåmmy:BAABLgAECn9GAAIPAAkJRxdgBQAhAgAPAAkJRxdgBQAhAgAAAA==.',
Si='Simonezer:BAAALgAECgkJAwAAAA==.Sindralea:BAAALgAECgQJBQABLgAECgkJJwAfAFUfAA==.Sins:BAABLgAECn8nAAIfAAkJVR9YCQC+AgAfAAkJVR9YCQC+AgAAAA==.Sionell:BAAALgADCgQJBAAAAA==.',
Sj='Sjöfn:BAAALgAECgEJAQAAAA==.',
Sk='Skiá:BAACLgAFFH8GAAIUAAMJtBIDDwDPAAAUAAMJtBIDDwDPAAAuAAQKf1QAAhQACQm7IewBABYDABQACQm7IewBABYDAAAA.Skodoosh:BAAALgAECgYJEAAAAA==.Skrinkles:BAAALgAECgYJDgAAAA==.Skyrocket:BAAALgAECgIJAwAAAA==.',
Sl='Slashpoison:BAAALgADCgcJDgAAAA==.Slicedbread:BAACLgAFFH8UAAIOAAYJ/BzeBwBUAQAOAAYJ/BzeBwBUAQAuAAQKfycAAw4ACQk7IOwOAJ4CAA4ACQk7IOwOAJ4CABUABwkKG6BBACACAAAA.Slorth:BAACLgAFFH8GAAILAAMJNBYkoADUAAALAAMJNBYkoADUAAAuAAQKfyIAAgsACAkYGn5KABMCAAsACAkYGn5KABMCAAAA.',
Sm='Smallfrye:BAAALgAECgIJAgAAAA==.',
Sn='Snizzlaki:BAABLgAECn9TAAMDAAkJeQ/CIAChAQADAAkJQg/CIAChAQACAAcJxggqDAC+AAAAAA==.',
So='Sofa:BAAALgADCgkJDAAAAA==.Solaene:BAAALgAFFAEJAgAAAA==.Soundsmystic:BAAALgADCgUJBQAAAA==.',
Sp='Spareparts:BAAALgAECgMJAwABLgAECgYJGwAPAO0VAA==.Sparkilies:BAAALgADCgYJBgAAAA==.Sparkleglory:BAAALgAECgMJAwAAAA==.Spicybreath:BAAALgAECgQJBAABLgAECgcJEQAEAAAAAA==.Spicydemon:BAAALgAECgcJEQAAAA==.Spicydrood:BAAALgAECgEJAQAAAA==.Spicytotems:BAAALgAECgEJAQAAAA==.Splaash:BAAALgAECgMJAwAAAA==.Splàsh:BAABLgAECn8bAAQPAAkJ3x8aBgAQAwAPAAkJ3x8aBgAQAwARAAUJpRWMZQC1AAAhAAIJRg3XMgBlAAAAAA==.',
St='Starwolfy:BAAALgAECgUJBQAAAA==.Steakman:BAAALgADCgIJAgAAAA==.Stoneboot:BAAALgAECggJEwAAAA==.Stryk:BAAALgAFFAEJAQAAAA==.Sts:BAAALgAECgIJAgAAAA==.',
Su='Sumaria:BAABLgAECn8oAAIXAAkJQgJlZgCDAAAXAAkJQgJlZgCDAAAAAA==.Superman:BAAALgAECggJCwAAAA==.',
Sw='Sweatycrits:BAAALgAECggJDQAAAA==.Sweetvixen:BAABLgAECn8bAAMPAAYJ7RXNDABlAQAPAAYJ7RXNDABlAQARAAEJ7wDpxgAMAAAAAA==.',
Sy='Sylvanasthot:BAAALgAECgQJBAAAAA==.Symora:BAAALgAECgUJBQAAAA==.',
['Sä']='Sävägeäf:BAAALgADCgcJBwAAAA==.',
Ta='Taana:BAAALgAECgUJCgAAAA==.Takbez:BAABLgAECn8gAAIUAAgJlxOSCwAGAgAUAAgJlxOSCwAGAgAAAA==.Tandria:BAAALgAECgYJDwAAAA==.Tarot:BAAALgADCgEJAQAAAA==.Taterhops:BAAALgAECgEJAQABLgAECgkJKAAFAD8gAA==.Tattered:BAAALgADCgEJAQAAAA==.Tauru:BAABLgAECn8jAAMeAAgJzhmxIQA6AgAeAAgJzhmxIQA6AgAfAAMJ7RLkEgCjAAAAAA==.Tazale:BAAALgAECggJDAABLgAECgkJDwAEAAAAAA==.',
Te='Teakaachu:BAABLgAECn8aAAIJAAkJbRTQKQDdAQAJAAkJbRTQKQDdAQAAAA==.Terdanator:BAABLgAECn8gAAMhAAgJ0Bc+DQDdAQAhAAgJ0Bc+DQDdAQARAAEJLQZ1uQAjAAAAAA==.Tetranis:BAAALgADCgQJBgAAAA==.',
Th='Thanathot:BAAALgADCgMJAwAAAA==.Thanatus:BAABLgAECn86AAQKAAkJARsvIQBeAgAKAAkJARsvIQBeAgAbAAQJyRCtIAC8AAAcAAEJzgf2eAAqAAAAAA==.Themia:BAAALgADCgMJAwAAAA==.Thetino:BAAALgAECgIJAgAAAA==.Throwinhands:BAAALgAECgEJAQAAAA==.',
Ti='Tiari:BAABLgAECn8yAAMOAAkJCRzZDADCAgAOAAkJCRzZDADCAgAVAAYJ0APlFAGgAAAAAA==.Tidepod:BAAALgAECgcJDQAAAA==.Timesink:BAAALgAECgQJBQAAAA==.Tisane:BAAALgAECgMJAwAAAA==.',
Tn='Tntclepriest:BAAALgAECgcJDgABLgAECgYJFAAbAGkVAA==.',
Tr='Tralline:BAAALgADCgMJAgAAAA==.Tranzig:BAAALgADCgUJBQAAAA==.Tridius:BAABLgAECn8dAAQXAAgJ3hgMCABQAQAXAAgJ3hgMCABQAQAWAAYJSBq9OAAvAQAdAAMJnRyfTQCsAAAAAA==.Trollins:BAAALgAECgIJAgAAAA==.Truda:BAAALgAECgcJBwAAAA==.Trumped:BAAALgADCgUJBwAAAA==.',
Tu='Turdanator:BAABLgAECn9NAAMXAAkJDhlSEwA3AgAXAAkJDhlSEwA3AgAdAAcJ/gtsQQAzAQAAAA==.',
Tw='Twittle:BAAALgAECgEJAQAAAA==.Twizzlers:BAAALgAECgQJBAAAAA==.',
Up='Upgraydd:BAAALgAECgIJBAABLgAECgcJEQAEAAAAAA==.',
Ur='Uraenus:BAAALgAECgcJEwAAAA==.Urahrotar:BAAALgADCgUJBgAAAA==.Uriah:BAABLgAECn81AAITAAkJ4Rj5CwCxAQATAAkJ4Rj5CwCxAQAAAA==.Ursúla:BAABLgAFFH8MAAIKAAUJNwoZYAAHAQAKAAUJNwoZYAAHAQABLgAFFAYJKQAfAEccAA==.Uryu:BAAALgAECgQJBAAAAA==.Urïah:BAAALgAECgYJDAABLgAECgkJNQATAOEYAA==.',
Ut='Utherr:BAABLgAFFH8FAAIVAAMJ6BrEaADdAAAVAAMJ6BrEaADdAAAAAA==.',
Va='Valaravaus:BAAALgAECgUJBwAAAA==.Valionandros:BAAALgAECgYJCAAAAA==.Vanaril:BAAALgAECgMJAwAAAA==.Vashirr:BAAALgAECgMJAwAAAA==.',
Ve='Vecks:BAAALgAECgQJBAAAAA==.Veldonir:BAAALgAECgEJAQAAAA==.Vergus:BAAALgAECgQJBAAAAA==.',
Vi='Violin:BAEALgAECgIJAwABLgAECggJDAAEAAAAAA==.Violinmax:BAEALgAECgYJDQABLgAECggJDAAEAAAAAA==.Viral:BAAALgAFFAEJAQAAAA==.',
Vo='Voidnova:BAAALgAECgEJAQAAAA==.Vonnie:BAAALgAECggJDgAAAA==.',
Vy='Vynlerinis:BAABLgAECn8eAAIgAAkJWCAJAwC5AgAgAAkJWCAJAwC5AgAAAA==.',
['Vé']='Végeta:BAAALgAECgIJBAABLgAECgkJMQAaAKgWAA==.',
Wa='Wardestroyer:BAAALgAECggJEQAAAA==.Wardwhelp:BAABLgAECn8oAAIMAAkJURxXAgAEAgAMAAkJURxXAgAEAgABLgAFFAIJAgAEAAAAAA==.',
We='Wetfinger:BAAALgAECgEJAQAAAA==.',
Wi='Wifehaver:BAABLgAECn8oAAIDAAkJuR8kFAANAgADAAkJuR8kFAANAgAAAA==.Wildmist:BAAALgAECgMJAwAAAA==.Winniedapoo:BAABLgAECn80AAIKAAgJ2BudNgD/AQAKAAgJ2BudNgD/AQAAAA==.Winterpaw:BAAALgAECgEJAQABLgAECgkJKwAGAFMZAA==.',
Wo='Wooloo:BAACLgAFFH8vAAQKAAkJcyKuCQB2AgAKAAgJ+CKuCQB2AgAcAAQJvxsfAwBvAQAbAAEJAADKBABZAAAuAAQKfygAAwoACQmzJfwPAM0CAAoACQmzJfwPAM0CABwABAlPHXogAE8BAAAA.',
Wu='Wurm:BAAALgAECgIJAgAAAA==.',
Wy='Wynona:BAAALgAECgcJCAAAAA==.',
Xa='Xanagore:BAABLgAECn8sAAMSAAkJVyJGBwDqAgASAAkJ6SFGBwDqAgAMAAEJ0RbRUgAzAAAAAA==.Xanllan:BAAALgAECgQJBgAAAA==.Xanthecat:BAAALgAECgQJBAAAAA==.Xanzul:BAABLgAECn8eAAIQAAcJpxPnDgBvAQAQAAcJpxPnDgBvAQABLgAECgkJLAASAFciAA==.',
Xe='Xenojiiva:BAAALgAECgEJAQABLgAFFAEJAgAEAAAAAA==.',
Xk='Xkwon:BAAALgAFFAEJAQAAAA==.Xkwøn:BAACLgAFFH8ZAAInAAYJtxjHBABKAQAnAAYJtxjHBABKAQAuAAQKfzwAAicACQkwIdsCAIUCACcACQkwIdsCAIUCAAAA.',
Xu='Xunie:BAABLgAECn8pAAILAAkJHBV2NAAtAgALAAkJHBV2NAAtAgAAAA==.',
Xx='Xximage:BAABLgAECn8dAAMoAAkJ1CRfAQDIAgAoAAkJ1CRfAQDIAgAFAAEJAACeWgFLAAAAAA==.',
Yu='Yulìe:BAAALgADCgcJBwAAAA==.',
Za='Zaibloom:BAAALgADCggJFgAAAA==.Zana:BAABLgAECn8aAAINAAgJPRLBdgAzAQANAAgJPRLBdgAzAQAAAA==.Zaretan:BAAALgAECgYJCQAAAA==.',
Zb='Zbrute:BAABLgAECn8pAAITAAkJXxz7FwCXAgATAAkJXxz7FwCXAgAAAA==.',
Ze='Zeffen:BAAALgAECgIJBAABLgAECggJKAAKADEHAA==.Zefphenn:BAAALgAECgQJBgABLgAECggJKAAKADEHAA==.Zenny:BAAALgADCggJEwAAAA==.',
Zi='Zildroghar:BAAALgADCgcJCAAAAA==.Zivz:BAAALgADCgUJBQAAAA==.',
Zo='Zokohjin:BAACLgAFFH8FAAILAAIJdxY0lgBDAAALAAIJdxY0lgBDAAAuAAQKfyUAAwsACQlYHJ4uAEUCAAsACQlYHJ4uAEUCAAYAAgn7F41BAIkAAAAA.',
Zu='Zulgar:BAAALgAFFAIJAgABLgAFFAkJJwAFADoaAA==.Zulpher:BAAALgADCgYJFwAAAA==.',
['Ðo']='Ðondon:BAAALgADCgQJBQAAAA==.Ðoppelgänger:BAAALgAECgEJCAAAAA==.',
['Øk']='Økwøn:BAACLgAFFH8PAAIFAAMJGBWOOQC3AAAFAAMJGBWOOQC3AAAuAAQKfzsAAwUACAkRHyJKAFkCAAUACAn4HiJKAFkCACgABAnvIdIHACoBAAAA.',
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
