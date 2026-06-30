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

local lookup = {'Monk-Windwalker','Monk-Brewmaster','Mage-Frost','DeathKnight-Blood','DemonHunter-Havoc','Monk-Mistweaver','Warlock-Demonology','DeathKnight-Unholy','Unknown-Unknown','Warrior-Protection','DemonHunter-Devourer','Paladin-Holy','Shaman-Restoration','Hunter-Marksmanship','Shaman-Elemental','Warrior-Fury','Hunter-BeastMastery','Druid-Feral','Priest-Discipline','Priest-Shadow','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Priest-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','Druid-Guardian','Rogue-Assassination','Rogue-Subtlety','Hunter-Survival','Paladin-Protection','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abones:BAAALgAFFAIJAwAAAA==.Absolon:BAAALgAECgQJBAAAAA==.Absólon:BAAALgADCgcJBwAAAA==.',
Ae='Aendia:BAAALgADCgIJAwAAAA==.Aeolos:BAAALgAECgUJBQAAAA==.',
Af='Affae:BAABLgAFFH8KAAMBAAMJFBNsMgB6AAACAAIJ6RZNRwCBAAABAAIJPg5sMgB6AAAAAA==.',
Ag='Agilitiess:BAAALgAECgEJAgAAAA==.Agrios:BAAALgAECgYJCgAAAA==.',
Ak='Ak:BAABLgAECn8qAAIDAAkJRSKSFgDSAgADAAkJRSKSFgDSAgAAAA==.',
Al='Alanas:BAAALgADCgEJAQAAAA==.Alchemie:BAAALgAECgEJAQAAAA==.Alcohlol:BAAALgADCgEJAQAAAA==.Allendril:BAAALgADCgIJAgABLgAECgkJKwAEAFMZAA==.Allister:BAAALgAECgYJBgABLgAECgkJHgAFAEsfAA==.Altahari:BAAALgAFFAEJAQABLgAFFAUJGAAGADUdAA==.',
Am='Amare:BAAALgAECgcJCgAAAA==.',
An='Ancalagon:BAAALgAECgQJCQAAAA==.Andros:BAABLgAECn8WAAIHAAgJshn9LwAYAgAHAAgJshn9LwAYAgAAAA==.Anekaatwo:BAAALgADCgEJAQAAAA==.Antigone:BAAALgAECgYJCwAAAA==.',
Ar='Araxe:BAABLgAECn8mAAMIAAcJthtiWwC1AQAIAAcJlhpiWwC1AQAEAAQJoxY/KwD/AAAAAA==.Arroyo:BAACLgAFFH8GAAIIAAMJ1A4TowDRAAAIAAMJ1A4TowDRAAAuAAQKfy4AAwgACQk3IT8TANUCAAgACQk3IT8TANUCAAQABAnJG58eAFIBAAAA.Artax:BAAALgADCgYJDAAAAA==.',
As='Asalohir:BAAALgAECgUJBQAAAA==.Ashryn:BAAALgAECgEJAgABLgAECgEJAgAJAAAAAA==.Askadar:BAACLgAFFH8ZAAIKAAYJfyYOBAAxAgAKAAYJfyYOBAAxAgAuAAQKfy8AAgoACQlyJhUBAFwDAAoACQlyJhUBAFwDAAAA.',
At='Athridran:BAAALgAECgQJBQAAAA==.Atinyhorse:BAABLgAECn8ZAAILAAcJ3AuSjQAFAQALAAcJ3AuSjQAFAQAAAA==.Atrax:BAACLgAFFH8GAAIMAAIJbQndQgBZAAAMAAIJbQndQgBZAAAuAAQKfxsAAgwABwl0DxY5AGgBAAwABwl0DxY5AGgBAAAA.Atrexx:BAABLgAFFH8GAAINAAMJ8hFOFACqAAANAAMJ8hFOFACqAAAAAA==.Atryx:BAABLgAFFH8NAAIOAAMJNBi5GgDbAAAOAAMJNBi5GgDbAAAAAA==.',
Au='Auronralius:BAAALgADCgIJAgAAAA==.',
Ax='Ax:BAAALgADCgcJCgABLgAECgYJDgAJAAAAAA==.Axmodel:BAAALgADCgIJAgABLgADCgQJBAAJAAAAAA==.',
Az='Azazél:BAAALgAECgIJAgAAAA==.Azuleja:BAAALgADCgEJAQAAAA==.Azzura:BAAALgADCgYJBwAAAA==.',
Ba='Babyboo:BAAALgAECgYJBgABLgAECggJCQAJAAAAAA==.Baheem:BAABLgAECn8cAAIDAAYJ7gN1AwGnAAADAAYJ7gN1AwGnAAAAAA==.Bams:BAABLgAECn8fAAMPAAkJYh3wHgDrAQAPAAcJ4h7wHgDrAQANAAgJzAtQUwBnAQAAAA==.Bamsx:BAAALgAECgcJBwAAAA==.Baneofdemons:BAAALgADCgEJAQAAAA==.Barrillon:BAAALgADCgEJAQAAAA==.Bastile:BAAALgAECgYJDwAAAA==.Bauer:BAAALgAECgQJBAAAAA==.',
Be='Benel:BAAALgAECggJEgAAAA==.',
Bi='Bifrons:BAAALgADCgMJAwAAAA==.Bigblkengery:BAAALgADCgcJCAAAAA==.Bigdill:BAAALgAECgEJAQAAAA==.Biggrippa:BAABLgAECn8lAAIQAAkJcCBJGwByAgAQAAkJcCBJGwByAgAAAA==.Bighoofprint:BAAALgAECgkJAQAAAA==.Bigtotempole:BAABLgAECn8YAAIPAAgJZwkZSQAQAQAPAAgJZwkZSQAQAQAAAA==.',
Bj='Bjornar:BAAALgADCgEJAQAAAA==.',
Bl='Blahwithpets:BAABLgAECn8sAAIRAAkJtxaNMAAaAgARAAkJtxaNMAAaAgAAAA==.Blappin:BAAALgADCgcJFAAAAA==.Bloodmyst:BAAALgAECgcJEQABLgAECgkJKAASAHcgAA==.Bloodymaw:BAAALgAECgQJBAAAAA==.Bloomer:BAAALgADCgEJAQAAAA==.Blooshield:BAAALgAECgUJBQAAAA==.Bluemchen:BAAALgADCgMJAwAAAA==.Blurt:BAAALgAECgEJAQAAAA==.',
Bo='Bobble:BAABLgAECn8eAAIMAAkJxBgkGwArAgAMAAkJxBgkGwArAgAAAA==.Bohelranus:BAAALgADCgkJFwAAAA==.Boneman:BAAALgAECgUJBQAAAA==.Bookwyrm:BAAALgADCgkJEQAAAA==.Boolil:BAAALgAECgQJCgABLgAECggJCQAJAAAAAA==.Boolove:BAAALgAECgMJAwABLgAECggJCQAJAAAAAA==.Booqt:BAAALgAECggJCQAAAA==.Boriel:BAAALgAECgYJBwAAAA==.',
Br='Breake:BAACLgAFFH8NAAITAAMJDgxZNQC2AAATAAMJDgxZNQC2AAAuAAQKfyMAAxMACAmlF8QXABcCABMACAmlF8QXABcCABQAAwl0D1xsAG4AAAAA.',
Bu='Bubblebreath:BAAALgAECgEJAQAAAA==.',
By='Byssrak:BAABLgAECn8dAAMVAAgJ+hEYMAB3AQAVAAgJ0BEYMAB3AQAWAAQJ0w7AEwDPAAAAAA==.',
Ca='Caladiir:BAAALgAECgUJBQABLgAECgkJHwACAEshAA==.Cattiebuzz:BAAALgAECgIJAwABLgAECgkJOwARAKceAA==.',
Ce='Cerealmilk:BAABLgAECn8ZAAIXAAgJ+BmYCQBNAgAXAAgJ+BmYCQBNAgABLgAECgkJJAAKAPUaAA==.',
Ch='Chadd:BAAALgADCgYJBgABLgAECgQJBgAJAAAAAA==.Childishbro:BAAALgAECgEJAQAAAA==.Chilla:BAAALgAECgMJAwAAAA==.Chitung:BAAALgADCgQJBAABLgAECgQJBAAJAAAAAA==.Chopshop:BAAALgAECgEJAQAAAA==.Christopher:BAACLgAFFH8SAAIDAAUJAB9RSgBNAQADAAUJAB9RSgBNAQAuAAQKfxsAAgMACQn2IJwtALsCAAMACQn2IJwtALsCAAAA.',
Ci='Cialismaxing:BAAALgAECggJDQABLgAECggJGQABAMwNAA==.Cindragos:BAAALgAECgQJBQABLgAFFAEJAQAJAAAAAA==.',
Co='Cocofluff:BAACLgAFFH8pAAIKAAgJ/CQLAQDUAgAKAAgJ/CQLAQDUAgAuAAQKfyUAAgoACAkAIiEEAAoDAAoACAkAIiEEAAoDAAAA.',
Cr='Creed:BAAALgAECgEJAQAAAA==.Creepychaos:BAAALgADCgkJKwABLgAECgkJSAAIAD0IAA==.Creepydemise:BAABLgAECn9IAAIIAAkJPQgScQCCAQAIAAkJPQgScQCCAQAAAA==.Creepydrunk:BAAALgAECgIJAgABLgAECgkJSAAIAD0IAA==.Creepyfoxxy:BAAALgADCgkJGwAAAA==.Croixsmash:BAABLgAECn8gAAIQAAkJZB5GIgBDAgAQAAkJZB5GIgBDAgAAAA==.Croixtemplar:BAAALgAECgYJCwAAAA==.',
Cu='Cuculain:BAAALgAECgEJBAAAAA==.Custodian:BAAALgAECgQJBAAAAA==.Cuttinglass:BAAALgADCgcJBwAAAA==.',
Cy='Cytherea:BAAALgADCgcJDAAAAA==.',
Da='Daedra:BAAALgAECgQJBgAAAA==.Dagdelythy:BAAALgAECgUJBwABLgAECgUJFwARAHMLAA==.Danoa:BAAALgAECgQJCgAAAA==.Daraellea:BAAALgAECgUJBQAAAA==.Darkcross:BAAALgADCgUJCAAAAA==.Darthorak:BAABLgAECn8lAAQHAAgJmQh2gAA4AQAHAAgJHQh2gAA4AQAYAAUJ9QbqIQCzAAAZAAYJtAUQIwCYAAAAAA==.Darthzai:BAAALgAECgMJAwAAAA==.Davennial:BAABLgAECn88AAIaAAkJ5BFGVwDFAQAaAAkJ5BFGVwDFAQAAAA==.Dawnn:BAABLgAECn8bAAIEAAkJ/wm2IgA9AQAEAAkJ/wm2IgA9AQAAAA==.Dayman:BAAALgAFFAEJAgAAAA==.',
De='Deanwnchestr:BAABLgAECn8pAAIDAAgJ8AlqkQBVAQADAAgJ8AlqkQBVAQAAAA==.Deathmamba:BAAALgADCgMJAwAAAA==.Deatnshadow:BAABLgAFFH8FAAIEAAMJbBiNJQDFAAAEAAMJbBiNJQDFAAAAAA==.Demise:BAAALgAECgQJCAAAAA==.Demonberry:BAAALgADCgEJAgAAAA==.Demonnutcase:BAAALgADCgYJEAAAAA==.Derogatory:BAAALgADCgYJDQABLgAFFAgJIgAbAEMbAA==.Desylla:BAAALgAECgQJBAAAAA==.Devildograh:BAAALgAECgQJBwAAAA==.',
Di='Diah:BAAALgAECgQJBwAAAA==.Dibinator:BAAALgADCgEJAQAAAA==.Dio:BAAALgADCgYJDQAAAA==.Diodata:BAAALgAECgEJAgABLgAECggJHQABAKohAA==.Diophantus:BAAALgAECgIJBQABLgAECggJHQABAKohAA==.Divinity:BAAALgAECgEJAQAAAA==.',
Dm='Dmncgdss:BAAALgAECggJDwAAAA==.',
Do='Dogeatdog:BAAALgADCgkJFwAAAA==.Dohaeriz:BAAALgAECgEJAwAAAA==.Doregoran:BAABLgAECn8pAAIZAAgJhBPRCgCVAQAZAAgJhBPRCgCVAQAAAA==.Dovairous:BAABLgAECn8eAAIcAAgJWAswWAAwAQAcAAgJWAswWAAwAQAAAA==.',
Dr='Draakell:BAAALgAECgQJBAAAAA==.Dracopeet:BAABLgAECn8aAAQVAAcJvwQ5cACLAAAVAAUJEgU5cACLAAAXAAQJGwPUNQBOAAAWAAMJwQLDKQAnAAAAAA==.Dragonator:BAAALgAECgMJAwAAAA==.Drausella:BAAALgAECgEJAQAAAA==.Dregomalfoy:BAAALgAECgQJBAAAAA==.Drexor:BAAALgAECgQJCwAAAA==.Drhealgôod:BAAALgAECgQJBQABLgAECgkJMQAXAKgWAA==.',
Du='Dudè:BAAALgAECgQJBAAAAA==.',
Dv='Dvlzadvocate:BAAALgAECgYJEgAAAA==.',
['Dâ']='Dâggèr:BAAALgAFFAEJAQAAAA==.',
['Dü']='Dürin:BAAALgAECgEJAgAAAA==.',
Ec='Echidna:BAABLgAECn8dAAIHAAcJKAoBngACAQAHAAcJKAoBngACAQAAAA==.',
Ed='Edgeovo:BAAALgAECgEJAQABLgAECgEJAgAJAAAAAA==.Edict:BAAALgAECgEJAQAAAA==.',
El='Elawen:BAAALgAECgYJDQAAAA==.Elder:BAAALgAECgEJAgAAAA==.Eleblah:BAAALgADCgcJBwAAAA==.Elfkinn:BAACLgAFFH8mAAMdAAYJFxy+DQDBAQAdAAYJFxy+DQDBAQAcAAIJ+gAvawBEAAAuAAQKfyUAAx0ACQmmHqUQAFkCAB0ACQmmHqUQAFkCABwABAlrBY+sAG0AAAAA.Elgund:BAAALgADCgQJBAAAAA==.Elivaniel:BAAALgAECgcJEAAAAA==.',
En='Enlargdcrit:BAAALgAECgMJAwAAAA==.',
Eq='Equinox:BAAALgADCgQJBAAAAA==.',
Er='Ericcdraven:BAABLgAECn8iAAIQAAgJgQ5zNwBpAQAQAAgJgQ5zNwBpAQAAAA==.Erodoria:BAABLgAECn8eAAMFAAkJSx/dCQCLAgAFAAgJBSLdCQCLAgAeAAUJ/hAFFQAFAQAAAA==.',
Et='Eternalfire:BAAALgADCgcJDgABLgAECgkJIwAdABgaAA==.',
Ev='Eve:BAAALgAECgEJAQAAAA==.Eveliong:BAAALgADCgEJAQAAAA==.Evilobama:BAAALgAECgUJBgAAAA==.Evoke:BAAALgAFFAEJAQABLgAFFAUJIAANAFcZAA==.',
Ex='Exzanthia:BAAALgAECgEJAwAAAA==.',
Ey='Eyln:BAACLgAFFH8FAAIOAAIJtw2hJACJAAAOAAIJtw2hJACJAAAuAAQKfzQAAg4ACQnUHRwDAKgCAA4ACQnUHRwDAKgCAAAA.',
Fa='Falkor:BAABLgAECn8xAAMXAAkJqBYADAAXAgAXAAkJqBYADAAXAgAWAAEJ6QI/LAAaAAAAAA==.Fanir:BAAALgAECgcJBwAAAA==.Fatino:BAAALgAECgUJBQAAAA==.Fatkid:BAABLgAECn8VAAILAAcJng95eAAwAQALAAcJng95eAAwAQAAAA==.Fayway:BAABLgAECn9DAAIcAAkJviGPBgBPAwAcAAkJviGPBgBPAwAAAA==.',
Fe='Ferral:BAABLgAECn8oAAISAAkJdyBhAABAAgASAAkJdyBhAABAAgAAAA==.Festukar:BAAALgAECgUJBwAAAA==.',
Fi='Figgy:BAAALgAECgUJCAAAAA==.Filthypirate:BAABLgAECn8UAAIaAAgJARFprgAhAQAaAAgJARFprgAhAQAAAA==.Firepower:BAABLgAECn8hAAIDAAkJxheBOwAsAgADAAkJxheBOwAsAgABLgAECggJIAASAJcTAA==.Fistatoosh:BAABLgAECn8iAAICAAgJUCSYBgDQAgACAAgJUCSYBgDQAgAAAA==.',
Fl='Florane:BAAALgAECgUJDAAAAA==.Flyingbotato:BAAALgADCgkJFQABLgAECggJIAASAJcTAA==.',
Fo='Forevershy:BAAALgADCgkJEgAAAA==.',
Fr='Fries:BAECLgAFFH8LAAIfAAUJTR/BBAB6AQAfAAUJTR/BBAB6AQAuAAQKfxwAAx8ACQkBIpYCAO8CAB8ACQkBIpYCAO8CAA0ABQkGDISDANgAAAAA.Fruits:BAAALgAECgYJBwAAAA==.',
Ga='Galdavin:BAABLgAECn8XAAIaAAgJnBqgKQB+AgAaAAgJnBqgKQB+AgAAAA==.Galenhaihi:BAAALgADCgUJBQAAAA==.Galexstrasza:BAAALgADCgYJBgABLgAECgUJDgAJAAAAAA==.Gallandia:BAAALgADCgEJAQABLgAECgUJDgAJAAAAAA==.Gallielynne:BAAALgAECgUJDgAAAA==.Gankdd:BAABLgAECn8UAAMQAAcJLhuUPgBLAQAQAAcJxhmUPgBLAQAgAAMJnRvCHgD4AAAAAA==.Garnnt:BAAALgADCgkJEQAAAA==.',
Gh='Ghoulfriend:BAAALgAECgEJAQAAAA==.',
Gi='Giggles:BAABLgAECn8uAAIPAAkJhRknAQATAgAPAAkJhRknAQATAgAAAA==.Gigglez:BAAALgADCggJCAAAAA==.Gimmothyjr:BAAALgAECgUJBgAAAA==.',
Gl='Glennspyder:BAAALgAECgQJDQABLgAECgUJFwARAHMLAA==.',
Go='Gonzo:BAAALgAFFAEJAQABLgAFFAUJIAANAFcZAA==.Goysoldier:BAAALgAFFAMJBAAAAA==.',
Gr='Greenbean:BAABLgAFFH8lAAILAAUJuBl7EAAXAQALAAUJuBl7EAAXAQABLgAFFAYJJgAdABccAA==.Grelleth:BAAALgAECgQJBQAAAA==.Groddz:BAABLgAECn8WAAILAAkJvgbyhQAUAQALAAkJvgbyhQAUAQAAAA==.Groto:BAAALgAECgYJBgAAAA==.Grrum:BAABLgAECn8gAAQTAAcJXgvaNwAzAQATAAcJkQnaNwAzAQAUAAQJaQhAWwCpAAAbAAIJQglEfgA0AAAAAA==.',
Gu='Gurînkaida:BAAALgAECgQJBAAAAA==.',
Ha='Haell:BAAALgAECgYJCgAAAA==.Hanjo:BAABLgAECn8wAAIKAAkJzyHdBADQAgAKAAkJzyHdBADQAgAAAA==.Hanoa:BAAALgAECgYJCgAAAA==.Harakiri:BAABLgAECn8UAAINAAcJixUvNgCqAQANAAcJixUvNgCqAQAAAA==.Hardare:BAABLgAECn8ZAAIBAAgJzA31JACvAQABAAgJzA31JACvAQAAAA==.Harpune:BAAALgADCgIJAgAAAA==.Hatookorr:BAAALgAECgUJBQABLgAECggJIAASAJcTAA==.Hayali:BAABLgAECn8iAAILAAgJXRYTPQDTAQALAAgJXRYTPQDTAQAAAA==.',
He='Helledrians:BAAALgAECgQJBgAAAA==.',
Hi='Hiawatha:BAAALgADCgcJAwAAAA==.',
Hm='Hmccrnglbery:BAAALgAECgMJBAABLgAECggJGQABAMwNAA==.',
Ho='Hottogo:BAAALgADCgcJBwAAAA==.',
Hw='Hwei:BAAALgADCgEJAQAAAA==.',
Hy='Hydé:BAABLgAECn8UAAMhAAgJXhvCCgA4AgAhAAgJXhvCCgA4AgASAAEJOhwTRABTAAABLgAECgkJHgAeAFggAA==.Hypatia:BAABLgAECn8dAAIBAAgJqiGqDQBrAgABAAgJqiGqDQBrAgAAAA==.',
['Hä']='Häxan:BAAALgAECgQJBAAAAA==.',
Ia='Iame:BAAALgADCgMJAwAAAA==.Iapetus:BAAALgADCgIJAgAAAA==.',
Ic='Icedchi:BAEBLgAECn8iAAICAAkJ3x/SEQApAgACAAkJ3x/SEQApAgAAAA==.',
In='Incite:BAABLgAECn8gAAMiAAkJaA9lCgCRAQAiAAkJZQ9lCgCRAQAjAAUJ+g2QQQAUAQAAAA==.',
Is='Ishvala:BAAALgADCgMJAwAAAA==.',
Iz='Izcarius:BAAALgADCgIJAgAAAA==.',
Ja='Jackpad:BAAALgAECgEJAgAAAA==.Jademist:BAAALgAECgYJCwABLgAECgkJMQAXAKgWAA==.Jaland:BAAALgADCgMJAwAAAA==.Jarrel:BAAALgAECgIJBAAAAA==.',
Je='Jellybreak:BAACLgAFFH8FAAIdAAIJ2AjhDwB3AAAdAAIJ2AjhDwB3AAAuAAQKfz0AAx0ACQmEFkAYAAsCAB0ACQmEFkAYAAsCACEABwmpCOY+AKsAAAAA.',
Jo='Joeewee:BAAALgAECgYJBgAAAA==.Jonjud:BAAALgAECgYJDAAAAA==.',
Js='Jskimonkpo:BAAALgADCgUJCQAAAA==.',
Ju='Julius:BAAALgAFFAEJAQAAAA==.',
Jy='Jyrian:BAAALgADCgMJAwAAAA==.',
Ka='Kaanâ:BAABLgAECn8zAAIbAAkJWhxkCQDSAgAbAAkJWhxkCQDSAgAAAA==.Kaelei:BAAALgADCgkJKwAAAA==.Kagamire:BAAALgADCgYJBQAAAA==.Kamine:BAAALgAECgUJEAAAAA==.Kanyeeast:BAAALgAECgYJCgAAAA==.Karnen:BAAALgAECgMJAwAAAA==.Kateblue:BAABLgAECn8vAAIdAAkJhRoGEABhAgAdAAkJhRoGEABhAgAAAA==.',
Ke='Kelcier:BAAALgADCgYJBgAAAA==.Kelser:BAABLgAECn8ZAAMYAAgJUR7FBAApAgAYAAgJUR7FBAApAgAHAAMJoBXuxgDLAAAAAA==.Kensington:BAABLgAECn8hAAIiAAgJdggnDgBDAQAiAAgJdggnDgBDAQAAAA==.Kethry:BAAALgAECgEJAQAAAA==.',
Ki='Kiku:BAABLgAECn8iAAIVAAkJYiPsBQD+AgAVAAkJYiPsBQD+AgAAAA==.Kikyou:BAAALgAECgYJCQABLgAECgkJIgAVAGIjAA==.Kim:BAABLgAECn8fAAIkAAkJRhBnFgDuAQAkAAkJRhBnFgDuAQAAAA==.Kinrah:BAAALgADCgMJAwAAAA==.Kirandra:BAAALgADCgMJAwAAAA==.Kirëë:BAAALgAECggJCAAAAA==.Kissofdeáth:BAAALgAECgIJAwAAAA==.',
Ko='Korlock:BAABLgAECn8mAAQHAAkJAB4vNAA8AgAHAAgJGR0vNAA8AgAZAAEJAACvbAA7AAAYAAEJPRc4PQA4AAAAAA==.',
Kr='Kreepywife:BAABLgAECn8gAAIUAAcJjxllAQDFAQAUAAcJjxllAQDFAQAAAA==.Krelbelorll:BAAALgAECgEJAQAAAA==.Krowley:BAABLgAECn8nAAINAAkJPxB4MADzAQANAAkJPxB4MADzAQAAAA==.',
Ku='Kurast:BAAALgAECgMJAwABLgAECgkJMQAXAKgWAA==.Kuzan:BAACLgAFFH8TAAIDAAUJEB9rTABHAQADAAUJEB9rTABHAQAuAAQKfx8AAgMABwl3IfQ2AJgCAAMABwl3IfQ2AJgCAAAA.',
Kx='Kxwono:BAAALgAECgcJBwAAAA==.',
Ky='Kyoyama:BAAALgAECgMJBwABLgAFFAMJDQAYAAEhAA==.',
La='Lacious:BAAALgADCgEJAQABLgAECgkJOwARAKceAA==.Ladýshinobu:BAABLgAECn8nAAIMAAgJQBBIKQDDAQAMAAgJQBBIKQDDAQAAAA==.Lananar:BAAALgADCgUJBQAAAA==.Layssaenna:BAAALgAECgYJCAAAAA==.',
Le='Leahu:BAABLgAECn88AAIlAAkJBhiuCgAfAgAlAAkJBhiuCgAfAgAAAA==.Lediaa:BAAALgAECgMJBAAAAA==.',
Li='Lifekiller:BAAALgAECgYJDwAAAA==.Lightark:BAAALgAECgEJAgAAAA==.Linekingz:BAAALgADCgEJAQAAAA==.Linetheshamy:BAAALgADCgkJDQAAAA==.Lineurathrot:BAAALgADCgYJCAAAAA==.Lisavia:BAAALgADCgUJBgAAAA==.Littlespyone:BAABLgAECn8XAAIRAAUJcwvhzgCsAAARAAUJcwvhzgCsAAAAAA==.Lizardman:BAAALgAFFAEJAQAAAA==.',
Lo='Locholovis:BAABLgAECn8wAAIZAAkJOhR5BwDcAQAZAAkJOhR5BwDcAQAAAA==.Locklicous:BAABLgAECn8WAAMHAAkJ2xepPQDlAQAHAAkJ2BOpPQDlAQAYAAYJWxV2EgBBAQAAAA==.Longhorse:BAACLgAFFH8gAAIEAAYJBiGlEgBiAQAEAAYJBiGlEgBiAQAuAAQKfzEAAwQACQn4JMgFAOACAAQACQmpIsgFAOACAAgABgnhJfpfAKkBAAAA.Longknight:BAAALgAECgEJAQAAAA==.Longr:BAAALgAECgYJCwAAAA==.Lorna:BAABLgAECn8XAAILAAgJJhJcVgCEAQALAAgJJhJcVgCEAQAAAA==.Lorthimar:BAAALgAECgUJCgABLgAECgkJJgAHAAAeAA==.',
Lu='Lumi:BAABLgAECn8WAAIDAAkJchhwUQDoAQADAAkJchhwUQDoAQAAAA==.Luminarae:BAAALgADCgEJAQAAAA==.Luminouss:BAABLgAFFH8QAAINAAcJuBKEFQC5AQANAAcJuBKEFQC5AQABLgAFFAMJBgATAOcUAA==.Lumpia:BAABLgAFFH8IAAILAAUJGBmzQgAfAQALAAUJGBmzQgAfAQAAAA==.',
Ly='Lylo:BAAALgADCgEJAQAAAA==.Lyrinir:BAABLgAECn8dAAMKAAkJ/hkjEQD2AQAKAAkJ/hkjEQD2AQAgAAEJigTaigAbAAAAAA==.Lyrium:BAABLgAECn8ZAAMeAAgJtRm8CgC4AQAeAAUJDR+8CgC4AQAFAAcJ+RA9KgAtAQABLgAECgkJHQAKAP4ZAA==.',
Ma='Madar:BAABLgAECn8gAAIHAAgJpgYomQALAQAHAAgJpgYomQALAQAAAA==.Maggus:BAAALgADCgQJBAAAAA==.Magicgal:BAAALgAECggJDQAAAA==.Maiden:BAAALgAECgUJBQAAAA==.Maiklytzwhet:BAAALgAECgUJBQAAAA==.Mairon:BAAALgAECgMJBgAAAA==.Malvorak:BAABLgAECn8zAAIEAAgJcREcHwBcAQAEAAgJcREcHwBcAQAAAA==.Mande:BAAALgADCgQJBAAAAA==.Mantis:BAAALgAECgkJDAABLgAECgkJMQAXAKgWAA==.Marrock:BAAALgAECgYJEQAAAA==.Marzipain:BAAALgAECgEJAQAAAA==.Mavarasie:BAAALgAECgUJDgAAAA==.Mavaressy:BAAALgAECgMJAwAAAA==.Mavaria:BAAALgAECgUJCwAAAA==.',
Mc='Mcmuffin:BAAALgAECgcJEgAAAA==.',
Me='Mechacattie:BAABLgAECn87AAIRAAkJpx4iFACxAgARAAkJpx4iFACxAgAAAA==.Mediator:BAAALgAECgEJAQAAAA==.Meekerz:BAAALgAECgIJAgAAAA==.Mega:BAAALgAFFAIJAwAAAA==.Melganis:BAAALgADCgMJBAAAAA==.Melissandra:BAABLgAECn8qAAMUAAgJ0gxoNgA9AQAUAAgJ0gxoNgA9AQAbAAIJiAb1dABVAAAAAA==.Mercas:BAAALgAECgcJDwABLgAECgkJJgAhAKMaAA==.Metacallae:BAAALgADCgcJAQAAAA==.Mezi:BAACLgAFFH8GAAIbAAIJLyQ8BgDQAAAbAAIJLyQ8BgDQAAAuAAQKf0QAAhsACQnhIWgHAPgCABsACQnhIWgHAPgCAAAA.Mezmera:BAAALgADCgUJBgABLgAECgIJAwAJAAAAAA==.',
Mh='Mhonster:BAAALgAECgYJBgABLgAFFAEJAQAJAAAAAA==.',
Mi='Missed:BAAALgAECgQJBQAAAA==.Mittens:BAACLgAFFH8GAAITAAMJ5xRcMADRAAATAAMJ5xRcMADRAAAuAAQKfxkAAxsACQlbGXQoAK0BABsABgn7GXQoAK0BABMABwlvE8ohAIUBAAAA.',
Mo='Mofro:BAAALgADCgQJBAABLgAECgQJBAAJAAAAAA==.Mokgunal:BAAALgADCgQJBAAAAA==.Money:BAAALgADCgIJAgABLgAECggJIwAaABghAA==.Moneyshotinc:BAAALgAECgkJCgABLgAECggJIwAaABghAA==.Moraine:BAAALgAECgQJBAAAAA==.Moreki:BAAALgAECgMJAwAAAA==.Morro:BAABLgAECn8wAAIPAAkJVw8sKwCaAQAPAAkJVw8sKwCaAQAAAA==.',
Ms='Msvelvet:BAAALgADCgkJHgABLgAECgQJDQAJAAAAAA==.',
Mu='Mugiwara:BAACLgAFFH8LAAIBAAQJbCQnDABkAQABAAQJbCQnDABkAQAuAAQKfxYAAgEABwntJAkKANcCAAEABwntJAkKANcCAAAA.Mulron:BAABLgAECn8kAAIlAAkJmhE0EgCjAQAlAAkJmhE0EgCjAQAAAA==.',
My='Myrica:BAAALgAECggJDwAAAA==.',
['Må']='Mådcõw:BAAALgAECgUJBgAAAA==.',
['Mö']='Mööve:BAAALgAECgMJAwAAAA==.',
Na='Nallos:BAAALgADCgEJAQAAAA==.Natajapar:BAAALgAECgEJAQABLgAECgcJCQAJAAAAAA==.',
Ne='Nefesh:BAABLgAFFH8XAAMLAAUJnwpzVADxAAALAAUJnwpzVADxAAAeAAEJ7AefBgAnAAAAAA==.Neff:BAAALgADCgMJAwAAAA==.',
Ni='Nightingales:BAAALgAECgMJAwAAAA==.',
Ny='Nyomie:BAAALgADCgEJAgAAAA==.Nyyx:BAAALgAECgQJBAABLgAECgYJCgAJAAAAAA==.',
Oa='Oakenshíeld:BAACLgAFFH8VAAIdAAYJ4BHkGQBKAQAdAAYJ4BHkGQBKAQAuAAQKfzsAAh0ACQlCF9AUAGsCAB0ACQlCF9AUAGsCAAAA.',
Ob='Obama:BAAALgADCgQJBAAAAA==.',
Og='Oggy:BAAALgAECgkJDAABLgAECgkJMQAXAKgWAA==.',
Ol='Olkwon:BAAALgAFFAIJAwAAAA==.',
On='Onlyfeigns:BAAALgAECgMJAwAAAA==.',
Oo='Oozwoz:BAAALgAECgcJDgAAAA==.',
Or='Orileluu:BAAALgAECgEJAQAAAA==.',
Ox='Oxwon:BAAALgAECgYJCwAAAA==.',
Pa='Paisho:BAAALgAECgQJBQAAAA==.Palliera:BAAALgAECgQJBgAAAA==.Pallirot:BAAALgAECggJCAAAAA==.Pallynomial:BAAALgADCgcJCgAAAA==.Pawmuck:BAABLgAECn8tAAIaAAgJ9Rk+PAATAgAaAAgJ9Rk+PAATAgAAAA==.',
Pe='Peer:BAAALgAECgEJAgAAAA==.Pewpewtazarz:BAAALgAECgUJCQAAAA==.',
Ph='Phancy:BAAALgADCggJDgAAAA==.Phrizzle:BAAALgADCgMJAwAAAA==.',
Pl='Plaguebeard:BAABLgAECn8XAAMIAAcJBx9/PABFAgAIAAcJBx9/PABFAgAEAAUJCRiiJwABAQAAAA==.Plagueblade:BAABLgAECn8rAAMEAAkJUxmWEgDlAQAEAAkJOhiWEgDlAQAIAAEJ3RqCVAFNAAAAAA==.',
Po='Podtinder:BAAALgAECgcJDAABLgAECgkJMQAXAKgWAA==.Poof:BAAALgAECgcJEAABLgAECgkJJAAKAPUaAA==.Poseidon:BAAALgAECgIJAgAAAA==.',
Pr='Prescription:BAABLgAECn8YAAMGAAgJ+AkMYQD1AAAGAAcJ1AkMYQD1AAABAAcJvQisRQDpAAAAAA==.Progression:BAAALgAECgEJBwAAAA==.',
Pu='Punish:BAAALgAECgEJAQAAAA==.',
Py='Pyrolord:BAAALgADCgYJCAAAAA==.',
Ra='Ragingrain:BAABLgAECn8jAAIlAAgJVxmyDAD6AQAlAAgJVxmyDAD6AQAAAA==.Rainsshammy:BAAALgAECgQJCAAAAA==.Rainthefire:BAABLgAECn8/AAIRAAkJZRqRLAArAgARAAkJZRqRLAArAgAAAA==.Ralthor:BAAALgADCgMJAwAAAA==.Ramalama:BAAALgAECgEJAgAAAA==.Rassarudk:BAAALgAECgYJCwAAAA==.Ravinfire:BAAALgAECgQJBwAAAA==.Rawktuah:BAAALgAECgMJAwAAAA==.',
Re='Realhelz:BAAALgAECgQJBQAAAA==.Redcross:BAAALgAECgYJDgAAAA==.Redoxx:BAAALgAECgYJDQAAAA==.Restofarian:BAACLgAFFH8gAAINAAUJVxmjCQAhAQANAAUJVxmjCQAhAQAuAAQKfyMAAg0ACQmJG0UXAFsCAA0ACQmJG0UXAFsCAAAA.',
Rh='Rhagnor:BAAALgAECgQJBAAAAA==.',
Ri='Rianon:BAAALgADCgkJEgABLgAECgkJNAALANccAA==.Rift:BAAALgAECgEJAwAAAA==.Righteous:BAABLgAECn8tAAIbAAkJ7RwfAgCNAQAbAAkJ7RwfAgCNAQAAAA==.Rizzy:BAABLgAECn8iAAMEAAkJSBenDwARAgAEAAkJSBenDwARAgAIAAkJ7gjubQCJAQAAAA==.',
Ro='Rollinsinc:BAAALgAECgkJAwAAAA==.Roshin:BAAALgAECgEJAgAAAA==.Rotinlock:BAAALgADCgYJDAAAAA==.Rotinshot:BAACLgAFFH8UAAMRAAYJjhLbIQB9AQARAAYJjhLbIQB9AQAkAAIJbgMhLQB6AAAuAAQKfygAAxEACQlsIWUWAIUCABEACAmTImUWAIUCACQACAl0GuEQALYBAAAA.',
Ru='Ruin:BAAALgAECgMJBAAAAA==.Rutikee:BAABLgAECn9OAAIcAAkJeBQ6AgCWAQAcAAkJeBQ6AgCWAQAAAA==.',
Sa='Sacerdos:BAABLgAECn8VAAIbAAgJlBW8FgAmAgAbAAgJlBW8FgAmAgABLgAECgkJOgAHAAEbAA==.Saeris:BAAALgADCggJCAABLgAECgcJDgAJAAAAAA==.Sagordez:BAACLgAFFH8FAAMGAAEJSBXCYAA/AAAGAAEJSBXCYAA/AAABAAEJ0ArWRAA2AAAuAAQKfygABAYACAm0Hi0ZAE8CAAYABwmVHi0ZAE8CAAIABwlxFXsmAHsBAAEAAQnhD7ejAC0AAAEuAAQKCQkeAB4AWCAA.Salima:BAAALgADCgMJAwAAAA==.Saltybrew:BAAALgADCgMJAwAAAA==.Sandrill:BAAALgAECgYJCgABLgAECggJIAASAJcTAA==.Satorugojo:BAAALgAECgUJBgAAAA==.Savior:BAAALgAECgUJEwAAAA==.Sazed:BAAALgAECggJDgAAAA==.',
Sc='Scrom:BAAALgAECgIJBAAAAA==.',
Se='Seabush:BAAALgAECgIJAwAAAA==.Seastorm:BAAALgAECgkJCQAAAA==.Seeker:BAAALgAECgEJAQAAAA==.Seizon:BAABLgAECn8pAAMkAAkJ9BeEAABrAgAkAAkJ9BeEAABrAgAOAAIJmQf2MwBMAAAAAA==.Semila:BAAALgAECgcJCQAAAA==.Sendor:BAAALgAECgYJBgAAAA==.Senseicanz:BAAALgAECgQJBAAAAA==.Sepulchure:BAAALgADCgMJAwAAAA==.Serina:BAAALgAECgQJBwABLgAECgkJKwAEAFMZAA==.Serom:BAABLgAECn8hAAIcAAgJdRlhHwBLAgAcAAgJdRlhHwBLAgAAAA==.Sesshomaaru:BAAALgADCggJEQAAAA==.',
Sh='Shaazrah:BAABLgAECn8fAAICAAkJSyGVCgCKAgACAAkJSyGVCgCKAgAAAA==.Shadowoak:BAAALgAECgIJAgAAAA==.Shadows:BAAALgADCgcJBwAAAA==.Shamkazaam:BAAALgAECggJDgAAAA==.Shammyhagär:BAAALgADCgMJAwABLgAECgQJBAAJAAAAAA==.Sharalvia:BAAALgADCgUJCAAAAA==.Sharkn:BAAALgAECgEJAQAAAA==.Sharkyo:BAAALgADCgIJAgAAAA==.Sharpshôôter:BAAALgAECgYJBgAAAA==.Sherunn:BAABLgAECn8jAAIdAAcJpQ0dOgAqAQAdAAcJpQ0dOgAqAQAAAA==.Shifty:BAAALgAECgEJAgAAAA==.Shiftydon:BAABLgAECn8eAAQSAAkJ0RA0EAC0AQASAAkJ0RA0EAC0AQAcAAIJ+Q2CqwBeAAAhAAEJMguSgAAhAAAAAA==.Shimakaze:BAACLgAFFH8GAAIRAAIJPwazJwCCAAARAAIJPwazJwCCAAAuAAQKfz4AAhEACQn2DrtFANABABEACQn2DrtFANABAAAA.Shirvana:BAAALgAECgQJBwABLgAECgcJCQAJAAAAAA==.Shooters:BAABLgAECn8YAAIkAAkJOx26DQDuAQAkAAkJOx26DQDuAQAAAA==.Shortbow:BAAALgADCgQJBgABLgAECgEJAgAJAAAAAA==.Shyminx:BAAALgADCgkJEgAAAA==.Shymistress:BAACLgAFFH8FAAIRAAEJxBgOOABTAAARAAEJxBgOOABTAAAuAAQKfzoAAhEACQkTIr8MAO0CABEACQkTIr8MAO0CAAAA.Shåmmy:BAABLgAECn9GAAINAAkJRxeWAQA3AgANAAkJRxeWAQA3AgAAAA==.',
Si='Simonezer:BAAALgAECgkJAwAAAA==.Sins:BAABLgAECn8nAAIdAAkJVR9YCQC+AgAdAAkJVR9YCQC+AgAAAA==.Sionell:BAAALgADCgQJBAAAAA==.',
Sk='Skiá:BAACLgAFFH8GAAISAAMJtBIDDwDPAAASAAMJtBIDDwDPAAAuAAQKf1QAAhIACQm7IewBABYDABIACQm7IewBABYDAAAA.Skodoosh:BAAALgAECgYJDwAAAA==.Skrinkles:BAAALgAECgYJDgAAAA==.Skyrocket:BAAALgAECgIJAwAAAA==.',
Sl='Slashpoison:BAAALgADCgcJDgAAAA==.Slicedbread:BAACLgAFFH8UAAIMAAYJ/BzeBwBUAQAMAAYJ/BzeBwBUAQAuAAQKfycAAwwACQk7IOwOAJ4CAAwACQk7IOwOAJ4CABoABwkKG6BBACACAAAA.Slorth:BAACLgAFFH8GAAIIAAMJNBYkoADUAAAIAAMJNBYkoADUAAAuAAQKfyIAAggACAkYGn5KABMCAAgACAkYGn5KABMCAAAA.',
Sm='Smallfrye:BAAALgAECgEJAQAAAA==.',
Sn='Snizzlaki:BAABLgAECn8+AAICAAkJQg/CIAChAQACAAkJQg/CIAChAQAAAA==.',
So='Sofa:BAAALgADCgkJDAAAAA==.Solaene:BAAALgAFFAEJAQAAAA==.Soundsmystic:BAAALgADCgUJBQAAAA==.',
Sp='Sparkilies:BAAALgADCgYJBgAAAA==.Sparkleglory:BAAALgAECgMJAwAAAA==.Spicybreath:BAAALgAECgQJBAABLgAECgcJEQAJAAAAAA==.Spicydemon:BAAALgAECgcJEQAAAA==.Spicydrood:BAAALgAECgEJAQAAAA==.Spicytotems:BAAALgAECgEJAQAAAA==.Splaash:BAAALgAECgMJAwAAAA==.Splàsh:BAABLgAECn8bAAQNAAkJ3x8aBgAQAwANAAkJ3x8aBgAQAwAPAAUJpRWMZQC1AAAfAAIJRg3XMgBlAAAAAA==.',
St='Starwolfy:BAAALgAECgUJBQAAAA==.Steakman:BAAALgADCgIJAgAAAA==.Stoneboot:BAAALgAECggJEwAAAA==.',
Su='Sumaria:BAABLgAECn8mAAIUAAgJkgFlZgCDAAAUAAgJkgFlZgCDAAAAAA==.',
Sw='Sweatycrits:BAAALgAECggJDQAAAA==.Sweetvixen:BAAALgAECgQJDQAAAA==.',
Sy='Sylvanasthot:BAAALgAECgQJBAAAAA==.',
['Sä']='Sävägeäf:BAAALgADCgcJBwAAAA==.',
Ta='Taana:BAAALgAECgUJCgAAAA==.Takbez:BAABLgAECn8gAAISAAgJlxOSCwAGAgASAAgJlxOSCwAGAgAAAA==.Tandria:BAAALgAECgYJCwAAAA==.Tarot:BAAALgADCgEJAQAAAA==.Taterhops:BAAALgAECgEJAQABLgAECgkJKAADAD4gAA==.Tattered:BAAALgADCgEJAQAAAA==.Tauru:BAABLgAECn8fAAMcAAgJRRmxIQA6AgAcAAgJRRmxIQA6AgAdAAEJphGHiwA1AAAAAA==.Tazale:BAAALgAECggJDAABLgAECgYJBgAJAAAAAA==.',
Te='Teakaachu:BAABLgAECn8YAAIGAAgJKBTQKQDdAQAGAAgJKBTQKQDdAQAAAA==.Terdanator:BAABLgAECn8fAAMfAAgJFhY+DQDdAQAfAAgJFhY+DQDdAQAPAAEJLQZ1uQAjAAAAAA==.Tetranis:BAAALgADCgQJBgAAAA==.',
Th='Thanathot:BAAALgADCgMJAwAAAA==.Thanatus:BAABLgAECn86AAQHAAkJARsvIQBeAgAHAAkJARsvIQBeAgAYAAQJyRCtIAC8AAAZAAEJzgf2eAAqAAAAAA==.Themia:BAAALgADCgMJAwAAAA==.Thetino:BAAALgAECgEJAQAAAA==.',
Ti='Tiari:BAABLgAECn8rAAMMAAkJ8xvZDADCAgAMAAkJ8xvZDADCAgAaAAYJ0APlFAGgAAAAAA==.Tidepod:BAAALgADCgIJAgAAAA==.Timesink:BAAALgAECgQJBQAAAA==.Tisane:BAAALgAECgMJAwAAAA==.',
Tn='Tntclepriest:BAAALgAECgcJDQABLgAECgYJFAAYAGkVAA==.',
Tr='Tralline:BAAALgADCgMJAgAAAA==.Tranzig:BAAALgADCgUJBQAAAA==.Tridius:BAABLgAECn8dAAQUAAgJ3hhiAgBhAQAUAAgJ3hhiAgBhAQATAAYJSBq9OAAvAQAbAAMJnRyfTQCsAAAAAA==.Trollins:BAAALgAECgIJAgAAAA==.Truda:BAAALgAECgIJAgAAAA==.Trumped:BAAALgADCgUJBwAAAA==.',
Tu='Turdanator:BAABLgAECn9NAAMUAAkJDhlSEwA3AgAUAAkJDhlSEwA3AgAbAAcJ/gtsQQAzAQAAAA==.',
Tw='Twizzlers:BAAALgAECgQJBAAAAA==.',
Up='Upgraydd:BAAALgAECgIJBAABLgAECgcJEQAJAAAAAA==.',
Ur='Uraenus:BAAALgAECgcJEwAAAA==.Urahrotar:BAAALgADCgUJBgAAAA==.Uriah:BAABLgAECn8vAAIRAAkJ7xd/BACmAQARAAkJ7xd/BACmAQAAAA==.Ursúla:BAABLgAFFH8KAAIHAAQJ6goZYAAHAQAHAAQJ6goZYAAHAQABLgAFFAYJJgAdABccAA==.Uryu:BAAALgAECgQJBAAAAA==.Urïah:BAAALgAECgYJDAABLgAECgkJLwARAO8XAA==.',
Ut='Utherr:BAABLgAFFH8FAAIaAAMJ6BrEaADdAAAaAAMJ6BrEaADdAAAAAA==.',
Va='Valaravaus:BAAALgAECgEJAwAAAA==.Valionandros:BAAALgAECgYJCAAAAA==.Vanaril:BAAALgAECgMJAwAAAA==.Vashirr:BAAALgAECgMJAwAAAA==.',
Ve='Veldonir:BAAALgAECgEJAQAAAA==.Vergus:BAAALgAECgQJBAAAAA==.',
Vi='Violin:BAEALgAECgIJAwABLgAECggJDAAJAAAAAA==.Violinmax:BAEALgAECgYJDQABLgAECggJDAAJAAAAAA==.Viral:BAAALgAFFAEJAQAAAA==.',
Vo='Voidnova:BAAALgAECgEJAQAAAA==.Vonnie:BAAALgAECgUJBQAAAA==.',
Vy='Vynlerinis:BAABLgAECn8eAAIeAAkJWCAJAwC5AgAeAAkJWCAJAwC5AgAAAA==.',
['Vé']='Végeta:BAAALgAECgIJAgABLgAECgkJMQAXAKgWAA==.',
Wa='Wardestroyer:BAAALgAECggJEQAAAA==.Wardwhelp:BAABLgAECn8kAAIKAAkJ9RrQAAABAgAKAAkJ9RrQAAABAgAAAA==.',
Wi='Wifehaver:BAABLgAECn8oAAICAAkJuR8kFAANAgACAAkJuR8kFAANAgAAAA==.Wildmist:BAAALgAECgMJAwAAAA==.Winniedapoo:BAABLgAECn80AAIHAAgJ2BudNgD/AQAHAAgJ2BudNgD/AQAAAA==.Winterpaw:BAAALgAECgEJAQABLgAECgkJKwAEAFMZAA==.',
Wo='Wooloo:BAACLgAFFH8kAAQHAAkJhiCuCQB2AgAHAAgJWiKuCQB2AgAZAAQJ+xgfAwBvAQAYAAEJAADKBABZAAAuAAQKfygAAwcACQmzJfwPAM0CAAcACQmzJfwPAM0CABkABAlPHXogAE8BAAAA.',
Wu='Wurm:BAAALgAECgIJAgAAAA==.',
Wy='Wynona:BAAALgAECgYJBgAAAA==.',
Xa='Xanagore:BAABLgAECn8sAAMQAAkJVyJGBwDqAgAQAAkJ6SFGBwDqAgAKAAEJ0RbRUgAzAAAAAA==.Xanllan:BAAALgAECgQJBgAAAA==.Xanthecat:BAAALgAECgQJBAAAAA==.Xanzul:BAABLgAECn8ZAAIOAAcJOxPnDgBvAQAOAAcJOxPnDgBvAQABLgAECgkJLAAQAFciAA==.',
Xe='Xenojiiva:BAAALgADCgIJAgABLgAFFAEJAQAJAAAAAA==.',
Xk='Xkwon:BAAALgAFFAEJAQAAAA==.Xkwøn:BAACLgAFFH8XAAImAAQJ3hrHBABKAQAmAAQJ3hrHBABKAQAuAAQKfzwAAiYACQkwIdsCAIUCACYACQkwIdsCAIUCAAAA.',
Xu='Xunie:BAABLgAECn8pAAIIAAkJHBV2NAAtAgAIAAkJHBV2NAAtAgAAAA==.',
Xx='Xximage:BAABLgAECn8dAAMnAAkJ1CRfAQDIAgAnAAkJ1CRfAQDIAgADAAEJAACeWgFLAAAAAA==.',
Yu='Yulìe:BAAALgADCgcJBwAAAA==.',
Za='Zaibloom:BAAALgADCggJFgAAAA==.Zana:BAABLgAECn8ZAAILAAgJPRLBdgAzAQALAAgJPRLBdgAzAQAAAA==.Zaretan:BAAALgADCgkJFgAAAA==.',
Zb='Zbrute:BAABLgAECn8pAAIRAAkJXxz7FwCXAgARAAkJXxz7FwCXAgAAAA==.',
Ze='Zeffen:BAAALgAECgIJBAABLgAECggJIAAHAKYGAA==.Zefphenn:BAAALgAECgQJBgABLgAECggJIAAHAKYGAA==.Zenny:BAAALgADCggJEwAAAA==.',
Zi='Zildroghar:BAAALgADCgcJCAAAAA==.Zivz:BAAALgADCgUJBQAAAA==.',
Zo='Zokohjin:BAABLgAECn8lAAMIAAkJWByeLgBFAgAIAAkJWByeLgBFAgAEAAIJ+xeNQQCJAAAAAA==.',
Zu='Zulgar:BAAALgAFFAIJAgABLgAFFAgJFwADAFgZAA==.Zulpher:BAAALgADCgYJEwAAAA==.',
['Ðo']='Ðondon:BAAALgADCgQJBQAAAA==.Ðoppelgänger:BAAALgAECgEJBgAAAA==.',
['Øk']='Økwøn:BAACLgAFFH8PAAIDAAMJGBWOOQC3AAADAAMJGBWOOQC3AAAuAAQKfzsAAwMACAkRHyJKAFkCAAMACAn4HiJKAFkCACcABAnvIdIHACoBAAAA.',
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
