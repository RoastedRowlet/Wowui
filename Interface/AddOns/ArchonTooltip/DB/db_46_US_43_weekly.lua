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

local lookup = {'Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Mage-Frost','DeathKnight-Blood','DemonHunter-Havoc','Monk-Mistweaver','Warlock-Demonology','DeathKnight-Unholy','Unknown-Unknown','Warrior-Protection','DemonHunter-Devourer','Paladin-Holy','Shaman-Restoration','Hunter-Marksmanship','Shaman-Elemental','Warrior-Fury','Hunter-BeastMastery','Druid-Feral','Priest-Discipline','Priest-Shadow','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Priest-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','Druid-Guardian','Rogue-Assassination','Hunter-Survival','Paladin-Protection','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abones:BAABLgAFFH8GAAIBAAMJ3x+WCgAbAQABAAMJ3x+WCgAbAQAAAA==.Absolon:BAAALgAECgQJBAAAAA==.Absólon:BAAALgADCgcJBwAAAA==.',
Ae='Aendia:BAAALgADCgIJAwAAAA==.Aeolos:BAAALgAECgUJBQAAAA==.',
Af='Affae:BAABLgAFFH8KAAMCAAMJFBNsMgB6AAADAAIJ6RZNRwCBAAACAAIJPg5sMgB6AAAAAA==.',
Ag='Agilitiess:BAAALgAECgEJAgAAAA==.Agrios:BAAALgAECgYJCgAAAA==.',
Ak='Ak:BAABLgAECn8qAAIEAAkJRSKSFgDSAgAEAAkJRSKSFgDSAgAAAA==.',
Al='Alanas:BAAALgADCgEJAQAAAA==.Alchemie:BAAALgAECgEJAQAAAA==.Alcohlol:BAAALgADCgEJAQAAAA==.Allendril:BAAALgADCgIJAgABLgAECgkJKwAFAFMZAA==.Allister:BAAALgAECgYJBgABLgAECgkJHgAGAEsfAA==.Altahari:BAAALgAFFAEJAQABLgAFFAUJGAAHADUdAA==.',
Am='Amare:BAAALgAECgcJCgAAAA==.',
An='Ancalagon:BAAALgAECgQJCQAAAA==.Andros:BAABLgAECn8YAAIIAAgJaBr9LwAYAgAIAAgJaBr9LwAYAgAAAA==.Anekaatwo:BAAALgADCgEJAQAAAA==.Antigone:BAAALgAECgYJCwAAAA==.',
Ar='Araxe:BAABLgAECn8mAAMJAAcJthtiWwC1AQAJAAcJlhpiWwC1AQAFAAQJoxY/KwD/AAAAAA==.Arroyo:BAACLgAFFH8GAAIJAAMJ1A4TowDRAAAJAAMJ1A4TowDRAAAuAAQKfy4AAwkACQk3IT8TANUCAAkACQk3IT8TANUCAAUABAnJG58eAFIBAAAA.Artax:BAAALgADCgYJDAAAAA==.',
As='Asalohir:BAAALgAECgUJBQAAAA==.Ashryn:BAAALgAECgEJAgABLgAECgEJAgAKAAAAAA==.Askadar:BAACLgAFFH8ZAAILAAYJfyYOBAAxAgALAAYJfyYOBAAxAgAuAAQKfy8AAgsACQlyJhUBAFwDAAsACQlyJhUBAFwDAAAA.',
At='Athridran:BAAALgAECgQJBQAAAA==.Atinyhorse:BAABLgAECn8ZAAIMAAcJ3AuSjQAFAQAMAAcJ3AuSjQAFAQAAAA==.Atrax:BAACLgAFFH8HAAINAAMJ2wt8FABtAAANAAMJ2wt8FABtAAAuAAQKfxsAAg0ABwl0DxY5AGgBAA0ABwl0DxY5AGgBAAAA.Atrexx:BAABLgAFFH8GAAIOAAMJ8hG5HQCoAAAOAAMJ8hG5HQCoAAAAAA==.Atryx:BAABLgAFFH8OAAIPAAMJNBi5GgDbAAAPAAMJNBi5GgDbAAAAAA==.',
Au='Auronralius:BAAALgADCgIJAgAAAA==.',
Ax='Ax:BAAALgADCgcJCgABLgAECgYJDgAKAAAAAA==.Axmodel:BAAALgADCgIJAgABLgADCgQJBAAKAAAAAA==.',
Az='Azazél:BAAALgAECgIJAgAAAA==.Azuleja:BAAALgADCgEJAQAAAA==.Azzura:BAAALgADCgYJBwAAAA==.',
Ba='Babyboo:BAAALgAECgYJDAABLgAECggJCQAKAAAAAA==.Baheem:BAABLgAECn8eAAIEAAcJ2wQiJwBaAAAEAAcJ2wQiJwBaAAAAAA==.Bams:BAABLgAECn8fAAMQAAkJYh3wHgDrAQAQAAcJ4h7wHgDrAQAOAAgJzAtQUwBnAQAAAA==.Bamsx:BAAALgAECgcJBwAAAA==.Baneofdemons:BAAALgADCgEJAQAAAA==.Barrillon:BAAALgADCgEJAQAAAA==.Bastile:BAAALgAECgYJDwAAAA==.Bauer:BAAALgAECgQJBAAAAA==.',
Be='Benel:BAAALgAECggJEgAAAA==.',
Bi='Bifrons:BAAALgADCgMJAwAAAA==.Bigblkengery:BAAALgADCgcJCAAAAA==.Bigdill:BAAALgAECgEJAQAAAA==.Biggrippa:BAABLgAECn8lAAIRAAkJcCBJGwByAgARAAkJcCBJGwByAgAAAA==.Bighoofprint:BAAALgAECgkJAQAAAA==.Bigtotempole:BAABLgAECn8aAAIQAAkJLAkZSQAQAQAQAAkJLAkZSQAQAQAAAA==.',
Bj='Bjornar:BAAALgADCgEJAQAAAA==.',
Bl='Blahwithpets:BAABLgAECn8sAAISAAkJtxaNMAAaAgASAAkJtxaNMAAaAgAAAA==.Blappin:BAAALgAECgEJAQAAAA==.Bloodmyst:BAAALgAECgcJEQABLgAECgkJKAATAHcgAA==.Bloodymaw:BAAALgAECgQJBAAAAA==.Bloomer:BAAALgADCgEJAQAAAA==.Blooshield:BAAALgAECgUJCQAAAA==.Bluemchen:BAAALgADCgMJAwAAAA==.Blurt:BAAALgAECgEJAQAAAA==.',
Bo='Bobble:BAABLgAECn8eAAINAAkJxBgkGwArAgANAAkJxBgkGwArAgAAAA==.Bohelranus:BAAALgADCgkJFwAAAA==.Boneman:BAAALgAECgUJBgAAAA==.Bookwyrm:BAAALgADCgkJEQAAAA==.Boolil:BAAALgAECgQJCgABLgAECggJCQAKAAAAAA==.Boolove:BAAALgAECgMJBAABLgAECggJCQAKAAAAAA==.Booqt:BAAALgAECggJCQAAAA==.Boriel:BAAALgAECgYJBwAAAA==.',
Br='Breake:BAACLgAFFH8NAAIUAAMJDgxZNQC2AAAUAAMJDgxZNQC2AAAuAAQKfyMAAxQACAmlF8QXABcCABQACAmlF8QXABcCABUAAwl0D1xsAG4AAAAA.',
Bu='Bubblebreath:BAAALgAECgEJAQAAAA==.',
By='Byssrak:BAABLgAECn8dAAMWAAgJ+hEYMAB3AQAWAAgJ0BEYMAB3AQAXAAQJ0w7AEwDPAAAAAA==.',
Ca='Caladiir:BAAALgAECgUJBQABLgAECgkJHwADAEshAA==.Cattiebuzz:BAAALgAECgIJAwABLgAECgkJOwASAKceAA==.',
Ce='Cerealmilk:BAABLgAECn8ZAAIYAAgJ+BmYCQBNAgAYAAgJ+BmYCQBNAgABLgAFFAIJAgAKAAAAAA==.',
Ch='Chadd:BAAALgADCgYJBgABLgAECgQJBgAKAAAAAA==.Childishbro:BAAALgAECgEJAQAAAA==.Chilla:BAAALgAECgMJAwAAAA==.Chitung:BAAALgADCgQJBAABLgAECgQJBAAKAAAAAA==.Chopshop:BAAALgAECgEJAQAAAA==.Christopher:BAACLgAFFH8SAAIEAAUJAB9RSgBNAQAEAAUJAB9RSgBNAQAuAAQKfxsAAgQACQn2IJwtALsCAAQACQn2IJwtALsCAAAA.',
Ci='Cialismaxing:BAAALgAECggJDQABLgAECggJGQACAMwNAA==.Cindragos:BAAALgAECgQJBQABLgAFFAEJAQAKAAAAAA==.',
Co='Cocofluff:BAACLgAFFH8uAAILAAgJ/CQLAQDUAgALAAgJ/CQLAQDUAgAuAAQKfyUAAgsACAkAIiEEAAoDAAsACAkAIiEEAAoDAAAA.',
Cr='Creed:BAAALgAECgEJAQAAAA==.Creepychaos:BAAALgADCgkJKwABLgAECgkJSAAJAD0IAA==.Creepydemise:BAABLgAECn9IAAIJAAkJPQgScQCCAQAJAAkJPQgScQCCAQAAAA==.Creepydrunk:BAAALgAECgIJAgABLgAECgkJSAAJAD0IAA==.Creepyfoxxy:BAAALgADCgkJGwAAAA==.Croixsmash:BAABLgAECn8gAAIRAAkJZB5GIgBDAgARAAkJZB5GIgBDAgAAAA==.Croixtemplar:BAAALgAECgYJDAAAAA==.',
Cu='Cuculain:BAAALgAECgEJBAAAAA==.Custodian:BAAALgAECgQJBAAAAA==.Cuttinglass:BAAALgADCgcJBwAAAA==.',
Cy='Cytherea:BAAALgADCgcJDAAAAA==.',
Da='Daedra:BAAALgAECgQJBgAAAA==.Dagdelythy:BAAALgAECgUJBwABLgAECgUJGgASAHMLAA==.Danoa:BAAALgAECgQJCgAAAA==.Daraellea:BAAALgAECgUJBQAAAA==.Darkcross:BAAALgADCgUJCAAAAA==.Darthorak:BAABLgAECn8lAAQIAAgJmQh2gAA4AQAIAAgJHQh2gAA4AQAZAAUJ9QbqIQCzAAAaAAYJtAUQIwCYAAAAAA==.Darthzai:BAAALgAECgMJAwAAAA==.Davennial:BAABLgAECn88AAIbAAkJ5BFGVwDFAQAbAAkJ5BFGVwDFAQAAAA==.Dawnn:BAABLgAECn8bAAIFAAkJ/wm2IgA9AQAFAAkJ/wm2IgA9AQAAAA==.Dayman:BAAALgAFFAEJAgAAAA==.',
De='Deanwnchestr:BAABLgAECn8pAAIEAAgJ8AlqkQBVAQAEAAgJ8AlqkQBVAQAAAA==.Deathmamba:BAAALgADCgMJAwAAAA==.Deatnshadow:BAABLgAFFH8FAAIFAAMJbBiNJQDFAAAFAAMJbBiNJQDFAAAAAA==.Demise:BAAALgAECgQJCAAAAA==.Demonberry:BAAALgADCgEJAgAAAA==.Demonnutcase:BAAALgADCgYJEAAAAA==.Derogatory:BAAALgADCgYJDQABLgAFFAgJIgAcAEMbAA==.Desylla:BAAALgAECgQJBAAAAA==.Devildograh:BAAALgAECgQJBwAAAA==.',
Di='Diah:BAAALgAECgQJBwAAAA==.Dibinator:BAAALgADCgEJAQAAAA==.Dio:BAAALgADCgYJDQAAAA==.Diodata:BAAALgAECgEJAgABLgAECggJHQACAKohAA==.Diophantus:BAAALgAECgIJBQABLgAECggJHQACAKohAA==.Divinity:BAAALgAECgEJAQAAAA==.',
Dm='Dmncgdss:BAAALgAECggJDwAAAA==.',
Do='Dogeatdog:BAAALgADCgkJFwAAAA==.Dohaeriz:BAAALgAECgEJAwAAAA==.Doregoran:BAABLgAECn8pAAIaAAgJhBPRCgCVAQAaAAgJhBPRCgCVAQAAAA==.Dovairous:BAABLgAECn8eAAIdAAgJWAswWAAwAQAdAAgJWAswWAAwAQAAAA==.',
Dr='Draakell:BAAALgAECgQJBAAAAA==.Dracopeet:BAABLgAECn8aAAQWAAcJvwQ5cACLAAAWAAUJEgU5cACLAAAYAAQJGwPUNQBOAAAXAAMJwQLDKQAnAAAAAA==.Dragonator:BAAALgAECgMJAwAAAA==.Drausella:BAAALgAECgEJAQAAAA==.Dreamsicle:BAAALgAECgMJAwAAAA==.Dregomalfoy:BAAALgAECgQJBAAAAA==.Drexor:BAAALgAECgQJCwAAAA==.Drhealgôod:BAAALgAECgYJDAABLgAECgkJMQAYAKgWAA==.',
Du='Dudè:BAAALgAECgQJBQAAAA==.',
Dv='Dvlzadvocate:BAAALgAECgYJEgAAAA==.',
['Dâ']='Dâggèr:BAAALgAFFAEJAQAAAA==.',
['Dü']='Dürin:BAAALgAECgEJAgAAAA==.',
Ec='Echidna:BAABLgAECn8dAAIIAAcJKAoBngACAQAIAAcJKAoBngACAQAAAA==.',
Ed='Edgeovo:BAAALgAECgEJAQABLgAECgEJAgAKAAAAAA==.Edict:BAAALgAECgEJAQAAAA==.',
El='Elawen:BAAALgAECgYJDQAAAA==.Elder:BAAALgAECgEJAgAAAA==.Eleblah:BAAALgADCgcJBwAAAA==.Elfkinn:BAACLgAFFH8pAAMeAAYJRxy+DQDBAQAeAAYJRxy+DQDBAQAdAAIJ+gAvawBEAAAuAAQKfyUAAx4ACQmmHqUQAFkCAB4ACQmmHqUQAFkCAB0ABAlrBY+sAG0AAAAA.Elgund:BAAALgADCgQJBAAAAA==.Elivaniel:BAAALgAECgcJEAAAAA==.',
En='Enlargdcrit:BAAALgAECgMJAwAAAA==.',
Eq='Equinox:BAAALgADCgQJBAAAAA==.',
Er='Ericcdraven:BAABLgAECn8iAAIRAAgJgQ5zNwBpAQARAAgJgQ5zNwBpAQAAAA==.Erodoria:BAABLgAECn8eAAMGAAkJSx/dCQCLAgAGAAgJBSLdCQCLAgAfAAUJ/hAFFQAFAQAAAA==.',
Et='Eternalfire:BAAALgADCgcJDgABLgAECgkJIwAeABgaAA==.',
Ev='Eve:BAAALgAECgEJAQAAAA==.Eveliong:BAAALgADCgEJAQAAAA==.Evilobama:BAAALgAECgUJBgAAAA==.Evoke:BAAALgAFFAEJAQABLgAFFAUJIAAOAFcZAA==.',
Ex='Exzanthia:BAAALgAECgEJAwAAAA==.',
Ey='Eyln:BAACLgAFFH8FAAIPAAIJtw2hJACJAAAPAAIJtw2hJACJAAAuAAQKfzQAAg8ACQnOHRwDAKgCAA8ACQnOHRwDAKgCAAAA.',
Fa='Falkor:BAABLgAECn8xAAMYAAkJqBYADAAXAgAYAAkJqBYADAAXAgAXAAEJ6QI/LAAaAAAAAA==.Fanir:BAAALgAECgcJBwAAAA==.Fatino:BAAALgAECgUJBQAAAA==.Fatkid:BAABLgAECn8VAAIMAAcJng95eAAwAQAMAAcJng95eAAwAQAAAA==.Fayway:BAABLgAECn9DAAIdAAkJviGPBgBPAwAdAAkJviGPBgBPAwAAAA==.',
Fe='Ferral:BAABLgAECn8oAAITAAkJdyCpAAAzAgATAAkJdyCpAAAzAgAAAA==.Festukar:BAAALgAECgUJBwAAAA==.',
Fi='Figgy:BAAALgAECgUJCAAAAA==.Filthypirate:BAABLgAECn8UAAIbAAgJARFprgAhAQAbAAgJARFprgAhAQAAAA==.Firepower:BAABLgAECn8hAAIEAAkJxheBOwAsAgAEAAkJxheBOwAsAgAAAA==.Fistatoosh:BAABLgAECn8iAAIDAAgJUCSYBgDQAgADAAgJUCSYBgDQAgAAAA==.',
Fl='Florane:BAAALgAECgUJDAAAAA==.Flyingbotato:BAAALgADCgkJFQABLgAECgkJIQAEAMYXAA==.',
Fo='Forevershy:BAAALgADCgkJEgAAAA==.',
Fr='Fries:BAECLgAFFH8LAAIgAAUJTR/BBAB6AQAgAAUJTR/BBAB6AQAuAAQKfxwAAyAACQkBIpYCAO8CACAACQkBIpYCAO8CAA4ABQkGDISDANgAAAAA.Fruits:BAAALgAECgYJBwAAAA==.',
Ga='Galdavin:BAABLgAECn8XAAIbAAgJnBqgKQB+AgAbAAgJnBqgKQB+AgAAAA==.Galenhaihi:BAAALgADCgUJBQAAAA==.Galexstrasza:BAAALgADCgYJBgABLgAECgUJDgAKAAAAAA==.Gallandia:BAAALgADCgEJAQABLgAECgUJDgAKAAAAAA==.Gallielynne:BAAALgAECgUJDgAAAA==.Ganduin:BAAALgAECgMJAwAAAA==.Gankdd:BAABLgAECn8UAAMRAAcJLhuUPgBLAQARAAcJxhmUPgBLAQAhAAMJnRvCHgD4AAAAAA==.Garnnt:BAAALgADCgkJEQAAAA==.',
Gh='Ghoulfriend:BAAALgAECgEJAQAAAA==.',
Gi='Giggles:BAABLgAECn8uAAIQAAkJiBm+AQALAgAQAAkJiBm+AQALAgAAAA==.Gigglez:BAAALgADCggJCAAAAA==.Gimmothyjr:BAAALgAECgUJBgAAAA==.',
Gl='Glennspyder:BAAALgAECgQJDQABLgAECgUJGgASAHMLAA==.',
Go='Gonzo:BAAALgAFFAEJAQABLgAFFAUJIAAOAFcZAA==.Goysoldier:BAAALgAFFAMJBAAAAA==.',
Gr='Greenbean:BAABLgAFFH8oAAIMAAUJhBv5EwAwAQAMAAUJhBv5EwAwAQABLgAFFAYJKQAeAEccAA==.Grelleth:BAAALgAFFAQJBAAAAA==.Groddz:BAABLgAECn8WAAIMAAkJvgbyhQAUAQAMAAkJvgbyhQAUAQAAAA==.Groto:BAAALgAECgYJBgAAAA==.Grrum:BAABLgAECn8gAAQUAAcJXgvaNwAzAQAUAAcJkQnaNwAzAQAVAAQJaQhAWwCpAAAcAAIJQwlEfgA0AAAAAA==.',
Gu='Gurînkaida:BAAALgAECgQJBAAAAA==.',
Ha='Haell:BAAALgAECgYJCgAAAA==.Hanjo:BAABLgAECn8wAAILAAkJzyHdBADQAgALAAkJzyHdBADQAgAAAA==.Hanoa:BAAALgAECgYJCgAAAA==.Harakiri:BAABLgAECn8UAAIOAAcJixUvNgCqAQAOAAcJixUvNgCqAQAAAA==.Hardare:BAABLgAECn8ZAAICAAgJzA31JACvAQACAAgJzA31JACvAQAAAA==.Harpune:BAAALgADCgIJAgAAAA==.Hatookorr:BAAALgAECgUJBQABLgAECgkJIQAEAMYXAA==.Hayali:BAABLgAECn8iAAIMAAgJXRYTPQDTAQAMAAgJXRYTPQDTAQAAAA==.',
He='Helledrians:BAAALgAECgQJBgAAAA==.',
Hi='Hiawatha:BAAALgADCgcJAwAAAA==.',
Hm='Hmccrnglbery:BAAALgAECgMJBAABLgAECggJGQACAMwNAA==.',
Ho='Hottogo:BAAALgADCgcJBwAAAA==.',
Hw='Hwei:BAAALgADCgEJAQAAAA==.',
Hy='Hydé:BAABLgAECn8UAAMiAAgJXhvCCgA4AgAiAAgJXhvCCgA4AgATAAEJOhwTRABTAAABLgAECgkJHgAfAFggAA==.Hypatia:BAABLgAECn8dAAICAAgJqiGqDQBrAgACAAgJqiGqDQBrAgAAAA==.',
['Hä']='Häxan:BAAALgAECgQJBAAAAA==.',
Ia='Iame:BAAALgADCgMJAwAAAA==.Iapetus:BAAALgADCgIJAgAAAA==.',
Ic='Icedchi:BAEBLgAECn8iAAIDAAkJ3x/SEQApAgADAAkJ3x/SEQApAgAAAA==.',
In='Incite:BAABLgAECn8gAAMjAAkJaA9lCgCRAQAjAAkJZQ9lCgCRAQABAAUJ+g2QQQAUAQAAAA==.',
Is='Ishvala:BAAALgADCgMJAwAAAA==.',
Iz='Izcarius:BAAALgADCgIJAgAAAA==.',
Ja='Jackpad:BAAALgAECgEJAgAAAA==.Jademist:BAAALgAECgYJDAABLgAECgkJMQAYAKgWAA==.Jaland:BAAALgADCgMJAwAAAA==.Jarrel:BAAALgAECgIJBAAAAA==.',
Je='Jellybreak:BAACLgAFFH8FAAIeAAIJ2AghFgBwAAAeAAIJ2AghFgBwAAAuAAQKfz0AAx4ACQmGFkAYAAsCAB4ACQmGFkAYAAsCACIABwmpCOY+AKsAAAAA.',
Jo='Joeewee:BAAALgAECgYJBgAAAA==.Jonjud:BAAALgAECgYJDAAAAA==.',
Js='Jskimonkpo:BAAALgADCgUJCQAAAA==.',
Ju='Jubilee:BAAALgAECgkJCQAAAA==.Julius:BAAALgAFFAEJAQAAAA==.',
Jy='Jyrian:BAAALgADCgMJAwAAAA==.',
Ka='Kaanâ:BAABLgAECn8zAAIcAAkJWhxkCQDSAgAcAAkJWhxkCQDSAgAAAA==.Kaelei:BAAALgADCgkJKwAAAA==.Kagamire:BAAALgADCgYJBQAAAA==.Kamine:BAAALgAECgUJEAAAAA==.Kanyeeast:BAAALgAECgYJCgAAAA==.Karnen:BAAALgAECgMJAwAAAA==.Kateblue:BAABLgAECn8vAAIeAAkJhRoGEABhAgAeAAkJhRoGEABhAgAAAA==.',
Ke='Kelcier:BAAALgADCgYJBgAAAA==.Kelser:BAABLgAECn8ZAAMZAAgJTx7FBAApAgAZAAgJTx7FBAApAgAIAAMJoBXuxgDLAAAAAA==.Kensington:BAABLgAECn8hAAIjAAgJdggnDgBDAQAjAAgJdggnDgBDAQAAAA==.Kethry:BAAALgAECgIJAwAAAA==.',
Ki='Kiku:BAABLgAECn8iAAIWAAkJYiPsBQD+AgAWAAkJYiPsBQD+AgAAAA==.Kikyou:BAAALgAECgYJCgABLgAECgkJIgAWAGIjAA==.Kim:BAABLgAECn8fAAIkAAkJRhBnFgDuAQAkAAkJRhBnFgDuAQAAAA==.Kinrah:BAAALgADCgMJAwAAAA==.Kirandra:BAAALgADCgMJAwAAAA==.Kirëë:BAAALgAECggJCAAAAA==.Kissofdeáth:BAAALgAECgIJAwAAAA==.',
Ko='Korlock:BAABLgAECn8mAAQIAAkJAB4vNAA8AgAIAAgJGR0vNAA8AgAaAAEJAACvbAA7AAAZAAEJPRc4PQA4AAAAAA==.',
Kr='Kreepywife:BAABLgAECn8jAAIVAAgJsRmDAQAPAgAVAAgJsRmDAQAPAgAAAA==.Krelbelorll:BAAALgAECgEJAQAAAA==.Krowley:BAABLgAECn8nAAIOAAkJPxB4MADzAQAOAAkJPxB4MADzAQAAAA==.',
Ku='Kurast:BAAALgAECgMJAwABLgAECgkJMQAYAKgWAA==.Kuzan:BAACLgAFFH8TAAIEAAUJEB9rTABHAQAEAAUJEB9rTABHAQAuAAQKfx8AAgQABwl3IfQ2AJgCAAQABwl3IfQ2AJgCAAAA.',
Kx='Kxwono:BAAALgAECgcJBwAAAA==.',
Ky='Kyoyama:BAAALgAECgMJBwABLgAFFAMJDwAZAAEhAA==.',
La='Lacious:BAAALgADCgEJAQABLgAECgkJOwASAKceAA==.Ladýshinobu:BAABLgAECn8nAAINAAgJQBBIKQDDAQANAAgJQBBIKQDDAQAAAA==.Lananar:BAAALgADCgUJBQAAAA==.Layssaenna:BAAALgAECgYJCAAAAA==.',
Le='Leahu:BAABLgAECn88AAIlAAkJBhiuCgAfAgAlAAkJBhiuCgAfAgAAAA==.Lediaa:BAAALgAECgMJBAAAAA==.',
Li='Lifekiller:BAAALgAECgYJDwAAAA==.Lightark:BAAALgAECgEJAgAAAA==.Linekingz:BAAALgADCgEJAQAAAA==.Linetheshamy:BAAALgADCgkJDQAAAA==.Lineurathrot:BAAALgADCgYJCAAAAA==.Lisavia:BAAALgADCgUJBgAAAA==.Littlespyone:BAABLgAECn8aAAISAAUJcwsLFwC/AAASAAUJcwsLFwC/AAAAAA==.Lizardman:BAAALgAFFAEJAQAAAA==.',
Lo='Locholovis:BAABLgAECn8wAAIaAAkJOhR5BwDcAQAaAAkJOhR5BwDcAQAAAA==.Locklicous:BAABLgAECn8WAAMIAAkJ2xepPQDlAQAIAAkJ2BOpPQDlAQAZAAYJWxV2EgBBAQAAAA==.Longhorse:BAACLgAFFH8hAAIFAAcJ5h+lEgBiAQAFAAcJ5h+lEgBiAQAuAAQKfzEAAwUACQn4JMgFAOACAAUACQmpIsgFAOACAAkABgnhJfpfAKkBAAAA.Longknight:BAAALgAECgEJAQAAAA==.Longr:BAAALgAECgYJCwAAAA==.Lorna:BAABLgAECn8XAAIMAAgJJhJcVgCEAQAMAAgJJhJcVgCEAQAAAA==.Lorthimar:BAAALgAECgUJCgABLgAECgkJJgAIAAAeAA==.',
Lu='Lumi:BAABLgAECn8WAAIEAAkJchhwUQDoAQAEAAkJchhwUQDoAQAAAA==.Luminarae:BAAALgADCgEJAQAAAA==.Luminouss:BAABLgAFFH8QAAIOAAcJuBKEFQC5AQAOAAcJuBKEFQC5AQABLgAFFAMJBgAUAOcUAA==.Lumpia:BAABLgAFFH8IAAIMAAUJGBmzQgAfAQAMAAUJGBmzQgAfAQAAAA==.',
Ly='Lylo:BAAALgADCgEJAQAAAA==.Lyrinir:BAABLgAECn8dAAMLAAkJ/hkjEQD2AQALAAkJ/hkjEQD2AQAhAAEJigTaigAbAAAAAA==.Lyrium:BAABLgAECn8ZAAMfAAgJtRm8CgC4AQAfAAUJDR+8CgC4AQAGAAcJ+RA9KgAtAQABLgAECgkJHQALAP4ZAA==.',
Ma='Madar:BAABLgAECn8gAAIIAAgJpgYomQALAQAIAAgJpgYomQALAQAAAA==.Maggus:BAAALgADCgQJBAAAAA==.Magicgal:BAAALgAECggJDQAAAA==.Maiden:BAAALgAECgUJBQAAAA==.Maiklytzwhet:BAAALgAECgUJBQAAAA==.Mairon:BAAALgAECgMJBgAAAA==.Malvorak:BAABLgAECn83AAIFAAgJ2REcHwBcAQAFAAgJ2REcHwBcAQAAAA==.Mande:BAAALgADCgQJBAAAAA==.Mantis:BAAALgAECgkJDAABLgAECgkJMQAYAKgWAA==.Marrock:BAAALgAECgYJEQAAAA==.Marzipain:BAAALgAECgEJAQAAAA==.Mavarasie:BAAALgAECgUJDgAAAA==.Mavaressy:BAAALgAECgMJAwAAAA==.Mavaria:BAAALgAECgYJDAAAAA==.',
Mc='Mcmuffin:BAAALgAECgcJEwAAAA==.',
Me='Mechacattie:BAABLgAECn87AAISAAkJpx4iFACxAgASAAkJpx4iFACxAgAAAA==.Mediator:BAAALgAECgEJAQAAAA==.Meekerz:BAAALgAECgIJAgAAAA==.Mega:BAAALgAFFAIJAwAAAA==.Melganis:BAAALgADCgMJBAAAAA==.Melissandra:BAABLgAECn8qAAMVAAgJ0gxoNgA9AQAVAAgJ0gxoNgA9AQAcAAIJiAb1dABVAAAAAA==.Mercas:BAAALgAECgcJDwABLgAECgkJJgAiAKMaAA==.Metacallae:BAAALgADCgcJAQAAAA==.Mezi:BAACLgAFFH8GAAIcAAIJLyRVCQDPAAAcAAIJLyRVCQDPAAAuAAQKf0QAAhwACQnlIWgHAPgCABwACQnlIWgHAPgCAAAA.Mezmera:BAAALgADCgUJBgABLgAECgIJAwAKAAAAAA==.',
Mh='Mhonster:BAAALgAECgYJBgABLgAFFAEJAgAKAAAAAA==.',
Mi='Missed:BAAALgAECgQJBQAAAA==.Mittens:BAACLgAFFH8GAAIUAAMJ5xRcMADRAAAUAAMJ5xRcMADRAAAuAAQKfxkAAxwACQlbGXQoAK0BABwABgn7GXQoAK0BABQABwlvE8ohAIUBAAAA.',
Mo='Mofro:BAAALgADCgQJBAABLgAECgQJBAAKAAAAAA==.Mokgunal:BAAALgADCgQJBAAAAA==.Money:BAAALgADCgIJAgABLgAECggJIwAbABghAA==.Moneyshotinc:BAAALgAECgkJCgABLgAECggJIwAbABghAA==.Moraine:BAAALgAECgQJBAAAAA==.Moreki:BAAALgAECgMJAwAAAA==.Morro:BAABLgAECn8wAAIQAAkJVw8sKwCaAQAQAAkJVw8sKwCaAQAAAA==.',
Ms='Msvelvet:BAAALgAECgMJAwABLgAECgQJDgAKAAAAAA==.',
Mu='Mugiwara:BAACLgAFFH8LAAICAAQJbCQnDABkAQACAAQJbCQnDABkAQAuAAQKfxYAAgIABwntJAkKANcCAAIABwntJAkKANcCAAAA.Mulron:BAABLgAECn8kAAIlAAkJmhE0EgCjAQAlAAkJmhE0EgCjAQAAAA==.',
My='Myrica:BAAALgAECggJDwAAAA==.',
['Må']='Mådcõw:BAAALgAECgUJBgAAAA==.',
['Mö']='Mööve:BAAALgAECgMJAwAAAA==.',
Na='Nallos:BAAALgADCgEJAQAAAA==.Natajapar:BAAALgAECgEJAQABLgAECgcJCQAKAAAAAA==.',
Ne='Nefesh:BAABLgAFFH8YAAMMAAUJlBFzVADxAAAMAAUJnwpzVADxAAAfAAEJaCRVBQBoAAAAAA==.Neff:BAAALgADCgMJAwAAAA==.',
Ni='Nightingales:BAAALgAECgMJAwAAAA==.',
Ny='Nyomie:BAAALgADCgEJAgAAAA==.Nyyx:BAAALgAECgQJBAABLgAECgYJCgAKAAAAAA==.',
Oa='Oakenshíeld:BAACLgAFFH8WAAIeAAcJVw/kGQBKAQAeAAcJVw/kGQBKAQAuAAQKfzsAAh4ACQlCF9AUAGsCAB4ACQlCF9AUAGsCAAAA.',
Ob='Obama:BAAALgADCgQJBAAAAA==.',
Og='Oggy:BAAALgAECgkJDAABLgAECgkJMQAYAKgWAA==.',
Ol='Olkwon:BAAALgAFFAIJAwAAAA==.',
On='Onlyfeigns:BAAALgAECgMJAwAAAA==.',
Oo='Oozwoz:BAAALgAECgcJDgAAAA==.',
Or='Oradreladin:BAAALgAECgcJCAAAAA==.Orileluu:BAAALgAECgEJAQAAAA==.',
Ou='Outfoxed:BAAALgAECgMJAwABLgAFFAgJIgAcAEMbAA==.',
Ox='Oxwon:BAAALgAECgYJCwAAAA==.',
Pa='Paisho:BAAALgAECgQJBQAAAA==.Palliera:BAAALgAECgQJBgAAAA==.Pallirot:BAAALgAECggJCAAAAA==.Pallynomial:BAAALgADCgcJCgAAAA==.Pawmuck:BAABLgAECn8tAAIbAAgJ9Rk+PAATAgAbAAgJ9Rk+PAATAgAAAA==.',
Pe='Peer:BAAALgAECgEJAgAAAA==.Pewpewtazarz:BAAALgAECgUJCQAAAA==.',
Ph='Phancy:BAAALgADCggJDgAAAA==.Phrizzle:BAAALgADCgMJAwAAAA==.',
Pl='Plaguebeard:BAABLgAECn8XAAMJAAcJBx9/PABFAgAJAAcJBx9/PABFAgAFAAUJCRiiJwABAQAAAA==.Plagueblade:BAABLgAECn8rAAMFAAkJUxmWEgDlAQAFAAkJOhiWEgDlAQAJAAEJ3RqCVAFNAAAAAA==.',
Po='Podtinder:BAAALgAECgcJDAABLgAECgkJMQAYAKgWAA==.Poof:BAAALgAFFAIJAgAAAA==.Poseidon:BAAALgAECgIJAgAAAA==.',
Pr='Prescription:BAABLgAECn8YAAMHAAgJ+AkMYQD1AAAHAAcJ1AkMYQD1AAACAAcJvQisRQDpAAAAAA==.Progression:BAAALgAECgEJBwAAAA==.',
Pu='Punish:BAAALgAECgEJAQAAAA==.',
Py='Pyrolord:BAAALgADCgYJCAAAAA==.',
Ra='Ragingrain:BAABLgAECn8jAAIlAAgJVxmyDAD6AQAlAAgJVxmyDAD6AQAAAA==.Rainsshammy:BAAALgAECgQJCAAAAA==.Rainthefire:BAABLgAECn8/AAISAAkJZRqRLAArAgASAAkJZRqRLAArAgAAAA==.Ralthor:BAAALgADCgMJAwAAAA==.Ramalama:BAAALgAECgEJAgAAAA==.Rassarudk:BAAALgAECgYJCwAAAA==.Ravinfire:BAAALgAECgQJBwAAAA==.Rawktuah:BAAALgAECgMJAwAAAA==.',
Re='Realhelz:BAAALgAECgQJBQAAAA==.Redcross:BAAALgAECgYJEwAAAA==.Redoxx:BAAALgAECgYJDQAAAA==.Restofarian:BAACLgAFFH8gAAIOAAUJVxl/DgAfAQAOAAUJVxl/DgAfAQAuAAQKfyMAAg4ACQmJG0UXAFsCAA4ACQmJG0UXAFsCAAAA.',
Rh='Rhagnor:BAAALgAECgQJBAAAAA==.',
Ri='Rianon:BAAALgADCgkJEgABLgAECgkJNAAMANccAA==.Rift:BAAALgAECgEJAwAAAA==.Righteous:BAABLgAECn8uAAIcAAkJBiBZAgDNAQAcAAkJBiBZAgDNAQAAAA==.Rizzy:BAABLgAECn8iAAMFAAkJQxenDwARAgAFAAkJQxenDwARAgAJAAkJ7gjubQCJAQAAAA==.',
Ro='Rollinsinc:BAAALgAECgkJAwAAAA==.Roshin:BAAALgAECgEJAgAAAA==.Rotinlock:BAAALgADCgYJDAAAAA==.Rotinshot:BAACLgAFFH8UAAMSAAYJjhLbIQB9AQASAAYJjhLbIQB9AQAkAAIJbgMhLQB6AAAuAAQKfygAAxIACQlsIWUWAIUCABIACAmTImUWAIUCACQACAl0GuEQALYBAAAA.',
Ru='Ruin:BAAALgAECgMJBAAAAA==.Rutikee:BAABLgAECn9OAAIdAAkJeRRlAwCSAQAdAAkJeRRlAwCSAQAAAA==.',
Sa='Sacerdos:BAABLgAECn8VAAIcAAgJlBW8FgAmAgAcAAgJlBW8FgAmAgABLgAECgkJOgAIAAEbAA==.Saeris:BAAALgADCggJCAABLgAECgcJDgAKAAAAAA==.Sagordez:BAACLgAFFH8GAAMHAAIJVwzCYAA/AAAHAAIJVwzCYAA/AAACAAEJ0ArWRAA2AAAuAAQKfygABAcACAm0Hi0ZAE8CAAcABwmVHi0ZAE8CAAMABwlxFXsmAHsBAAIAAQnhD7ejAC0AAAEuAAQKCQkeAB8AWCAA.Salima:BAAALgADCgMJAwAAAA==.Saltybrew:BAAALgADCgMJAwAAAA==.Sandrill:BAAALgAECgYJCgABLgAECgkJIQAEAMYXAA==.Satorugojo:BAAALgAECgUJBgAAAA==.Savior:BAABLgAECn8ZAAIbAAYJuBZKDAAmAQAbAAYJuBZKDAAmAQAAAA==.Sazed:BAAALgAECggJDgAAAA==.',
Sc='Scrom:BAAALgAECgIJBAAAAA==.',
Se='Seabush:BAAALgAECgIJAwAAAA==.Seastorm:BAAALgAECgkJCQAAAA==.Seeker:BAAALgAECgEJAQAAAA==.Seizon:BAABLgAECn8rAAMkAAkJfRfMAABVAgAkAAkJfRfMAABVAgAPAAIJmQf2MwBMAAAAAA==.Sekkusu:BAAALgAECgQJBAAAAA==.Semila:BAAALgAECgcJCQAAAA==.Sendor:BAAALgAECgYJBgAAAA==.Senseicanz:BAAALgAECgQJBAAAAA==.Sepulchure:BAAALgADCgMJAwAAAA==.Serina:BAAALgAECgQJBwABLgAECgkJKwAFAFMZAA==.Serom:BAABLgAECn8hAAIdAAgJdRlhHwBLAgAdAAgJdRlhHwBLAgAAAA==.Sesshomaaru:BAAALgADCggJEQAAAA==.',
Sh='Shaazrah:BAABLgAECn8fAAIDAAkJSyGVCgCKAgADAAkJSyGVCgCKAgAAAA==.Shadowoak:BAAALgAECgIJAgAAAA==.Shadows:BAAALgADCgcJBwAAAA==.Shamkazaam:BAAALgAECggJDgAAAA==.Shammyhagär:BAAALgADCgMJAwABLgAECgQJBAAKAAAAAA==.Sharalvia:BAAALgADCgUJCAAAAA==.Sharkn:BAAALgAECgEJAQAAAA==.Sharkyo:BAAALgADCgIJAgAAAA==.Sharpshôôter:BAAALgAECgcJDAAAAA==.Sherunn:BAABLgAECn8jAAIeAAcJpQ0dOgAqAQAeAAcJpQ0dOgAqAQAAAA==.Shifty:BAAALgAECgEJAgAAAA==.Shiftydon:BAABLgAECn8eAAQTAAkJ0RA0EAC0AQATAAkJ0RA0EAC0AQAdAAIJ+Q2CqwBeAAAiAAEJMguSgAAhAAAAAA==.Shimakaze:BAACLgAFFH8GAAISAAIJPwb0OACAAAASAAIJPwb0OACAAAAuAAQKfz4AAhIACQn3DrtFANABABIACQn3DrtFANABAAAA.Shirvana:BAAALgAECgQJBwABLgAECgcJCQAKAAAAAA==.Shooters:BAABLgAECn8YAAIkAAkJOx26DQDuAQAkAAkJOx26DQDuAQAAAA==.Shortbow:BAAALgADCgQJBgABLgAECgEJAgAKAAAAAA==.Shyminx:BAAALgAECgEJAQAAAA==.Shymistress:BAACLgAFFH8FAAISAAEJxBi8SwBTAAASAAEJxBi8SwBTAAAuAAQKfzsAAhIACQkTIr8MAO0CABIACQkTIr8MAO0CAAAA.Shåmmy:BAABLgAECn9GAAIOAAkJRxdyAgAuAgAOAAkJRxdyAgAuAgAAAA==.',
Si='Simonezer:BAAALgAECgkJAwAAAA==.Sins:BAABLgAECn8nAAIeAAkJVR9YCQC+AgAeAAkJVR9YCQC+AgAAAA==.Sionell:BAAALgADCgQJBAAAAA==.',
Sk='Skiá:BAACLgAFFH8GAAITAAMJtBIDDwDPAAATAAMJtBIDDwDPAAAuAAQKf1QAAhMACQm7IewBABYDABMACQm7IewBABYDAAAA.Skodoosh:BAAALgAECgYJDwAAAA==.Skrinkles:BAAALgAECgYJDgAAAA==.Skyrocket:BAAALgAECgIJAwAAAA==.',
Sl='Slashpoison:BAAALgADCgcJDgAAAA==.Slicedbread:BAACLgAFFH8UAAINAAYJ/BzeBwBUAQANAAYJ/BzeBwBUAQAuAAQKfycAAw0ACQk7IOwOAJ4CAA0ACQk7IOwOAJ4CABsABwkKG6BBACACAAAA.Slorth:BAACLgAFFH8GAAIJAAMJNBYkoADUAAAJAAMJNBYkoADUAAAuAAQKfyIAAgkACAkYGn5KABMCAAkACAkYGn5KABMCAAAA.',
Sm='Smallfrye:BAAALgAECgEJAQAAAA==.',
Sn='Snizzlaki:BAABLgAECn8+AAIDAAkJQg/CIAChAQADAAkJQg/CIAChAQAAAA==.',
So='Sofa:BAAALgADCgkJDAAAAA==.Solaene:BAAALgAFFAEJAgAAAA==.Soundsmystic:BAAALgADCgUJBQAAAA==.',
Sp='Spareparts:BAAALgADCgUJCAABLgAECgQJDgAKAAAAAA==.Sparkilies:BAAALgADCgYJBgAAAA==.Sparkleglory:BAAALgAECgMJAwAAAA==.Spicybreath:BAAALgAECgQJBAABLgAECgcJEQAKAAAAAA==.Spicydemon:BAAALgAECgcJEQAAAA==.Spicydrood:BAAALgAECgEJAQAAAA==.Spicytotems:BAAALgAECgEJAQAAAA==.Splaash:BAAALgAECgMJAwAAAA==.Splàsh:BAABLgAECn8bAAQOAAkJ3x8aBgAQAwAOAAkJ3x8aBgAQAwAQAAUJpRWMZQC1AAAgAAIJRg3XMgBlAAAAAA==.',
St='Starwolfy:BAAALgAECgUJBQAAAA==.Steakman:BAAALgADCgIJAgAAAA==.Stoneboot:BAAALgAECggJEwAAAA==.Stryk:BAAALgAECgMJBAAAAA==.',
Su='Sumaria:BAABLgAECn8mAAIVAAgJkgFlZgCDAAAVAAgJkgFlZgCDAAAAAA==.',
Sw='Sweatycrits:BAAALgAECggJDQAAAA==.Sweetvixen:BAAALgAECgQJDgAAAA==.',
Sy='Sylvanasthot:BAAALgAECgQJBAAAAA==.Symora:BAAALgAECgQJBAAAAA==.',
['Sä']='Sävägeäf:BAAALgADCgcJBwAAAA==.',
Ta='Taana:BAAALgAECgUJCgAAAA==.Takbez:BAABLgAECn8gAAITAAgJlxOSCwAGAgATAAgJlxOSCwAGAgABLgAECgkJIQAEAMYXAA==.Tandria:BAAALgAECgYJDwAAAA==.Tarot:BAAALgADCgEJAQAAAA==.Taterhops:BAAALgAECgEJAQABLgAECgkJKAAEAD8gAA==.Tattered:BAAALgADCgEJAQAAAA==.Tauru:BAABLgAECn8jAAMdAAgJzhmxIQA6AgAdAAgJzhmxIQA6AgAeAAMJ7RICCQCxAAAAAA==.Tazale:BAAALgAECggJDAABLgAECgYJBgAKAAAAAA==.',
Te='Teakaachu:BAABLgAECn8aAAIHAAkJbRTQKQDdAQAHAAkJbRTQKQDdAQAAAA==.Terdanator:BAABLgAECn8gAAMgAAgJ0Bc+DQDdAQAgAAgJ0Bc+DQDdAQAQAAEJLQZ1uQAjAAAAAA==.Tetranis:BAAALgADCgQJBgAAAA==.',
Th='Thanathot:BAAALgADCgMJAwAAAA==.Thanatus:BAABLgAECn86AAQIAAkJARsvIQBeAgAIAAkJARsvIQBeAgAZAAQJyRCtIAC8AAAaAAEJzgf2eAAqAAAAAA==.Themia:BAAALgADCgMJAwAAAA==.Thetino:BAAALgAECgIJAgAAAA==.Throwinhands:BAAALgAECgEJAQAAAA==.',
Ti='Tiari:BAABLgAECn8yAAMNAAkJCRzZDADCAgANAAkJCRzZDADCAgAbAAYJ0APlFAGgAAAAAA==.Tidepod:BAAALgAECgYJBwAAAA==.Timesink:BAAALgAECgQJBQAAAA==.Tisane:BAAALgAECgMJAwAAAA==.',
Tn='Tntclepriest:BAAALgAECgcJDQABLgAECgYJFAAZAGkVAA==.',
Tr='Tralline:BAAALgADCgMJAgAAAA==.Tranzig:BAAALgADCgUJBQAAAA==.Tridius:BAABLgAECn8dAAQVAAgJ3hiwAwBgAQAVAAgJ3hiwAwBgAQAUAAYJSBq9OAAvAQAcAAMJnRyfTQCsAAAAAA==.Trollins:BAAALgAECgIJAgAAAA==.Truda:BAAALgAECgYJBgAAAA==.Trumped:BAAALgADCgUJBwAAAA==.',
Tu='Turdanator:BAABLgAECn9NAAMVAAkJDhlSEwA3AgAVAAkJDhlSEwA3AgAcAAcJ/gtsQQAzAQAAAA==.',
Tw='Twittle:BAAALgAECgEJAQAAAA==.Twizzlers:BAAALgAECgQJBAAAAA==.',
Up='Upgraydd:BAAALgAECgIJBAABLgAECgcJEQAKAAAAAA==.',
Ur='Uraenus:BAAALgAECgcJEwAAAA==.Urahrotar:BAAALgADCgUJBgAAAA==.Uriah:BAABLgAECn81AAISAAkJ4Rh+BQDGAQASAAkJ4Rh+BQDGAQAAAA==.Ursúla:BAABLgAFFH8KAAIIAAQJ6goZYAAHAQAIAAQJ6goZYAAHAQABLgAFFAYJKQAeAEccAA==.Uryu:BAAALgAECgQJBAAAAA==.Urïah:BAAALgAECgYJDAABLgAECgkJNQASAOEYAA==.',
Ut='Utherr:BAABLgAFFH8FAAIbAAMJ6BrEaADdAAAbAAMJ6BrEaADdAAAAAA==.',
Va='Valaravaus:BAAALgAECgEJAwAAAA==.Valionandros:BAAALgAECgYJCAAAAA==.Vanaril:BAAALgAECgMJAwAAAA==.Vashirr:BAAALgAECgMJAwAAAA==.',
Ve='Vecks:BAAALgAECgQJBAAAAA==.Veldonir:BAAALgAECgEJAQAAAA==.Vergus:BAAALgAECgQJBAAAAA==.',
Vi='Violin:BAEALgAECgIJAwABLgAECggJDAAKAAAAAA==.Violinmax:BAEALgAECgYJDQABLgAECggJDAAKAAAAAA==.Viral:BAAALgAFFAEJAQAAAA==.',
Vo='Voidnova:BAAALgAECgEJAQAAAA==.Vonnie:BAAALgAECgYJCQAAAA==.',
Vy='Vynlerinis:BAABLgAECn8eAAIfAAkJWCAJAwC5AgAfAAkJWCAJAwC5AgAAAA==.',
['Vé']='Végeta:BAAALgAECgIJAwABLgAECgkJMQAYAKgWAA==.',
Wa='Wardestroyer:BAAALgAECggJEQAAAA==.Wardwhelp:BAABLgAECn8oAAILAAkJURwIAQASAgALAAkJURwIAQASAgABLgAFFAIJAgAKAAAAAA==.',
Wi='Wifehaver:BAABLgAECn8oAAIDAAkJuR8kFAANAgADAAkJuR8kFAANAgAAAA==.Wildmist:BAAALgAECgMJAwAAAA==.Winniedapoo:BAABLgAECn80AAIIAAgJ2BudNgD/AQAIAAgJ2BudNgD/AQAAAA==.Winterpaw:BAAALgAECgEJAQABLgAECgkJKwAFAFMZAA==.',
Wo='Wooloo:BAACLgAFFH8lAAQIAAkJiCCuCQB2AgAIAAgJXCKuCQB2AgAaAAQJ+xgfAwBvAQAZAAEJAADKBABZAAAuAAQKfygAAwgACQmzJfwPAM0CAAgACQmzJfwPAM0CABoABAlPHXogAE8BAAAA.',
Wu='Wurm:BAAALgAECgIJAgAAAA==.',
Wy='Wynona:BAAALgAECgYJBgAAAA==.',
Xa='Xanagore:BAABLgAECn8sAAMRAAkJVyJGBwDqAgARAAkJ6SFGBwDqAgALAAEJ0RbRUgAzAAAAAA==.Xanllan:BAAALgAECgQJBgAAAA==.Xanthecat:BAAALgAECgQJBAAAAA==.Xanzul:BAABLgAECn8eAAIPAAcJpxPnDgBvAQAPAAcJpxPnDgBvAQABLgAECgkJLAARAFciAA==.',
Xe='Xenojiiva:BAAALgAECgEJAQABLgAFFAEJAgAKAAAAAA==.',
Xk='Xkwon:BAAALgAFFAEJAQAAAA==.Xkwøn:BAACLgAFFH8XAAImAAQJ3hrHBABKAQAmAAQJ3hrHBABKAQAuAAQKfzwAAiYACQkwIdsCAIUCACYACQkwIdsCAIUCAAAA.',
Xu='Xunie:BAABLgAECn8pAAIJAAkJHBV2NAAtAgAJAAkJHBV2NAAtAgAAAA==.',
Xx='Xximage:BAABLgAECn8dAAMnAAkJ1CRfAQDIAgAnAAkJ1CRfAQDIAgAEAAEJAACeWgFLAAAAAA==.',
Yu='Yulìe:BAAALgADCgcJBwAAAA==.',
Za='Zaibloom:BAAALgADCggJFgAAAA==.Zana:BAABLgAECn8ZAAIMAAgJPRLBdgAzAQAMAAgJPRLBdgAzAQAAAA==.Zaretan:BAAALgADCgkJFgAAAA==.',
Zb='Zbrute:BAABLgAECn8pAAISAAkJXxz7FwCXAgASAAkJXxz7FwCXAgAAAA==.',
Ze='Zeffen:BAAALgAECgIJBAABLgAECggJIAAIAKYGAA==.Zefphenn:BAAALgAECgQJBgABLgAECggJIAAIAKYGAA==.Zenny:BAAALgADCggJEwAAAA==.',
Zi='Zildroghar:BAAALgADCgcJCAAAAA==.Zivz:BAAALgADCgUJBQAAAA==.',
Zo='Zokohjin:BAABLgAECn8lAAMJAAkJWByeLgBFAgAJAAkJWByeLgBFAgAFAAIJ+xeNQQCJAAAAAA==.',
Zu='Zulgar:BAAALgAFFAIJAgABLgAFFAgJGgAEAFgZAA==.Zulpher:BAAALgADCgYJEwAAAA==.',
['Ðo']='Ðondon:BAAALgADCgQJBQAAAA==.Ðoppelgänger:BAAALgAECgEJCAAAAA==.',
['Øk']='Økwøn:BAACLgAFFH8PAAIEAAMJGBWOOQC3AAAEAAMJGBWOOQC3AAAuAAQKfzsAAwQACAkRHyJKAFkCAAQACAn4HiJKAFkCACcABAnvIdIHACoBAAAA.',
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
