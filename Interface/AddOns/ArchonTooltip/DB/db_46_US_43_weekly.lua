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

local lookup = {'Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Mage-Frost','DeathKnight-Blood','DemonHunter-Havoc','Monk-Mistweaver','Warlock-Demonology','DeathKnight-Unholy','Warrior-Protection','DemonHunter-Devourer','Paladin-Holy','Hunter-Marksmanship','Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','Hunter-BeastMastery','Druid-Feral','Priest-Discipline','Priest-Shadow','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','Priest-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','Hunter-Survival','Paladin-Protection','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abones:BAAALgAECggJDgAAAA==.Absolon:BAAALgAECgQJBAAAAA==.Absólon:BAAALgADCgcJBwAAAA==.',
Ae='Aendia:BAAALgADCgIJAwAAAA==.Aeolos:BAAALgAECgUJBQAAAA==.',
Af='Affae:BAABLgAFFH8KAAMBAAMJFBNsMgB6AAACAAIJ6RZaRwCBAAABAAIJPg5sMgB6AAAAAA==.',
Ag='Agilitiess:BAAALgAECgEJAQABLgAECgEJAgADAAAAAA==.Agrios:BAAALgAECgYJCgAAAA==.',
Ak='Ak:BAABLgAECn8qAAIEAAkJRSKVFgDSAgAEAAkJRSKVFgDSAgAAAA==.',
Al='Alanas:BAAALgADCgEJAQAAAA==.Alcohlol:BAAALgADCgEJAQAAAA==.Allendril:BAAALgADCgIJAgABLgAECgkJKwAFAFMZAA==.Allister:BAAALgAECgYJBgABLgAECgkJHgAGAEsfAA==.Altahari:BAAALgAFFAEJAQABLgAFFAUJFAAHAKccAA==.',
Am='Amare:BAAALgAECgcJCgAAAA==.',
An='Ancalagon:BAAALgAECgQJCQAAAA==.Andros:BAABLgAECn8VAAIIAAgJshn9LwAYAgAIAAgJshn9LwAYAgAAAA==.Anekaatwo:BAAALgADCgEJAQAAAA==.Antigone:BAAALgAECgYJCwAAAA==.',
Ar='Araxe:BAABLgAECn8mAAMJAAcJthtfWwC1AQAJAAcJlhpfWwC1AQAFAAQJoxY7KwD/AAAAAA==.Arroyo:BAACLgAFFH8GAAIJAAMJ1A4XowDRAAAJAAMJ1A4XowDRAAAuAAQKfy4AAwkACQk3ITwTANUCAAkACQk3ITwTANUCAAUABAnJG58eAFIBAAAA.Artax:BAAALgADCgYJDAAAAA==.',
As='Asalohir:BAAALgAECgUJBQAAAA==.Ashryn:BAAALgAECgEJAgAAAA==.Askadar:BAACLgAFFH8ZAAIKAAYJfyYQBAAxAgAKAAYJfyYQBAAxAgAuAAQKfy8AAgoACQlyJhUBAFwDAAoACQlyJhUBAFwDAAAA.',
At='Athridran:BAAALgAECgEJAQAAAA==.Atinyhorse:BAABLgAECn8ZAAILAAcJ3AuRjQAFAQALAAcJ3AuRjQAFAQAAAA==.Atrax:BAACLgAFFH8FAAIMAAIJrwThQgBZAAAMAAIJrwThQgBZAAAuAAQKfxoAAgwABwl0DxU5AGgBAAwABwl0DxU5AGgBAAAA.Atrexx:BAAALgAFFAIJBAAAAA==.Atryx:BAABLgAFFH8NAAINAAMJNBjNGgDbAAANAAMJNBjNGgDbAAAAAA==.',
Au='Auronralius:BAAALgADCgIJAgAAAA==.',
Ax='Ax:BAAALgADCgcJCgABLgAECgYJDgADAAAAAA==.',
Az='Azazél:BAAALgAECgIJAgAAAA==.Azuleja:BAAALgADCgEJAQAAAA==.Azzura:BAAALgADCgYJBwAAAA==.',
Ba='Babyboo:BAAALgAECgYJBgABLgAECgkJMAAOAIYRAA==.Baheem:BAABLgAECn8ZAAIEAAYJVwNuAwGnAAAEAAYJVwNuAwGnAAAAAA==.Bams:BAABLgAECn8fAAMPAAkJYh3xHgDrAQAPAAcJ4h7xHgDrAQAQAAgJzAtLUwBnAQAAAA==.Bamsx:BAAALgAECgcJBwAAAA==.Baneofdemons:BAAALgADCgEJAQAAAA==.Barrillon:BAAALgADCgEJAQAAAA==.Bastile:BAAALgAECgYJDwAAAA==.Bauer:BAAALgAECgQJBAAAAA==.',
Be='Benel:BAAALgAECggJEgAAAA==.',
Bi='Bifrons:BAAALgADCgMJAwAAAA==.Bigblkengery:BAAALgADCgcJCAAAAA==.Bigdill:BAAALgAECgEJAQAAAA==.Biggrippa:BAABLgAECn8lAAIRAAkJcCBJGwByAgARAAkJcCBJGwByAgAAAA==.Bighoofprint:BAAALgAECgkJAQAAAA==.Bigtotempole:BAABLgAECn8YAAIPAAgJZwkXSQAQAQAPAAgJZwkXSQAQAQAAAA==.',
Bj='Bjornar:BAAALgADCgEJAQAAAA==.',
Bl='Blahwithpets:BAABLgAECn8sAAISAAkJtxaOMAAaAgASAAkJtxaOMAAaAgAAAA==.Blappin:BAAALgADCgcJFAAAAA==.Bloodmyst:BAAALgAECgcJEQABLgAECgkJIQATAFMdAA==.Bloodymaw:BAAALgAECgQJBAAAAA==.Bloomer:BAAALgADCgEJAQAAAA==.Blooshield:BAAALgAECgUJBQAAAA==.Bluemchen:BAAALgADCgMJAwAAAA==.Blurt:BAAALgAECgEJAQAAAA==.',
Bo='Bobble:BAABLgAECn8eAAIMAAkJxBgnGwArAgAMAAkJxBgnGwArAgAAAA==.Bohelranus:BAAALgADCgkJFwAAAA==.Boneman:BAAALgAECgUJBQAAAA==.Bookwyrm:BAAALgADCgkJDQAAAA==.Boolil:BAAALgAECgQJCQABLgAECgkJMAAOAIYRAA==.Boolove:BAAALgAECgMJAwABLgAECgkJMAAOAIYRAA==.Booqt:BAAALgAECggJCQABLgAECgkJMAAOAIYRAA==.Boriel:BAAALgAECgYJBgAAAA==.',
Br='Breake:BAACLgAFFH8MAAIUAAMJnwtgNQC2AAAUAAMJnwtgNQC2AAAuAAQKfyIAAxQACAmlF8MXABcCABQACAmlF8MXABcCABUAAwl0D09sAG4AAAAA.',
Bu='Bubblebreath:BAAALgAECgEJAQAAAA==.',
By='Byssrak:BAABLgAECn8dAAMWAAgJ+hEWMAB3AQAWAAgJ0BEWMAB3AQAXAAQJ0w7BEwDPAAAAAA==.',
Ca='Caladiir:BAAALgAECgUJBQABLgAECgkJHwACAEshAA==.Cattiebuzz:BAAALgAECgIJAwABLgAECgkJOwASAKceAA==.',
Ce='Cerealmilk:BAABLgAECn8XAAIYAAgJkBmYCQBNAgAYAAgJkBmYCQBNAgABLgAECgkJHgAKAJIaAA==.',
Ch='Chadd:BAAALgADCgYJBgABLgAECgQJBgADAAAAAA==.Childishbro:BAAALgAECgEJAQAAAA==.Chilla:BAAALgAECgMJAwAAAA==.Chitung:BAAALgADCgQJBAABLgAECgQJBAADAAAAAA==.Chopshop:BAAALgAECgEJAQAAAA==.Christopher:BAACLgAFFH8SAAIEAAUJAB9sSgBNAQAEAAUJAB9sSgBNAQAuAAQKfxsAAgQACQn2IJwtALsCAAQACQn2IJwtALsCAAAA.',
Ci='Cialismaxing:BAAALgAECggJDQABLgAECggJGQABAMwNAA==.Cindragos:BAAALgAECgQJBQABLgAFFAEJAQADAAAAAA==.',
Co='Cocofluff:BAACLgAFFH8pAAIKAAgJ/CQLAQDUAgAKAAgJ/CQLAQDUAgAuAAQKfyUAAgoACAkAIiEEAAoDAAoACAkAIiEEAAoDAAAA.',
Cr='Creed:BAAALgAECgEJAQAAAA==.Creepychaos:BAAALgADCgkJKwABLgAECgkJSAAJAD0IAA==.Creepydemise:BAABLgAECn9IAAIJAAkJPQgScQCCAQAJAAkJPQgScQCCAQAAAA==.Creepydrunk:BAAALgAECgIJAgABLgAECgkJSAAJAD0IAA==.Creepyfoxxy:BAAALgADCgkJGwAAAA==.Croixsmash:BAABLgAECn8gAAIRAAkJZB5GIgBDAgARAAkJZB5GIgBDAgAAAA==.Croixtemplar:BAAALgAECgYJCwAAAA==.',
Cu='Cuculain:BAAALgAECgEJBAAAAA==.Custodian:BAAALgAECgQJBAAAAA==.Cuttinglass:BAAALgADCgcJBwAAAA==.',
Cy='Cytherea:BAAALgADCgcJDAAAAA==.',
Da='Daedra:BAAALgAECgQJBgAAAA==.Dagdelythy:BAAALgAECgUJBQABLgAECgUJFwASAHMLAA==.Danoa:BAAALgAECgQJCgAAAA==.Daraellea:BAAALgAECgUJBQAAAA==.Darkcross:BAAALgADCgUJCAAAAA==.Darthorak:BAABLgAECn8lAAQIAAgJmQhygAA4AQAIAAgJHQhygAA4AQAZAAUJ9QbsIQCzAAAaAAYJtAUOIwCYAAAAAA==.Darthzai:BAAALgAECgMJAwAAAA==.Davennial:BAABLgAECn88AAIOAAkJ5BFHVwDFAQAOAAkJ5BFHVwDFAQAAAA==.Dawnn:BAABLgAECn8bAAIFAAkJ/wm0IgA9AQAFAAkJ/wm0IgA9AQAAAA==.Dayman:BAAALgAFFAEJAgAAAA==.',
De='Deanwnchestr:BAABLgAECn8oAAIEAAgJ8AlnkQBVAQAEAAgJ8AlnkQBVAQAAAA==.Deathmamba:BAAALgADCgMJAwAAAA==.Deatnshadow:BAABLgAFFH8FAAIFAAMJbBiUJQDEAAAFAAMJbBiUJQDEAAAAAA==.Demise:BAAALgAECgQJCAAAAA==.Demonberry:BAAALgADCgEJAgAAAA==.Demonnutcase:BAAALgADCgYJEAAAAA==.Derogatory:BAAALgADCgYJDQABLgAFFAgJIAAbADIbAA==.Desylla:BAAALgADCgQJBAAAAA==.Devildograh:BAAALgAECgQJBwAAAA==.',
Di='Diah:BAAALgAECgQJBwAAAA==.Dibinator:BAAALgADCgEJAQAAAA==.Dio:BAAALgADCgYJDQAAAA==.Diodata:BAAALgAECgEJAgABLgAECggJHQABAKohAA==.Diophantus:BAAALgAECgIJBQABLgAECggJHQABAKohAA==.Divinity:BAAALgAECgEJAQAAAA==.',
Dm='Dmncgdss:BAAALgAECggJDwAAAA==.',
Do='Dogeatdog:BAAALgADCgkJFAAAAA==.Dohaeriz:BAAALgAECgEJAwAAAA==.Doregoran:BAABLgAECn8pAAIaAAgJhBPRCgCVAQAaAAgJhBPRCgCVAQAAAA==.Dovairous:BAABLgAECn8eAAIcAAgJWAs0WAAwAQAcAAgJWAs0WAAwAQAAAA==.',
Dr='Draakell:BAAALgAECgQJBAAAAA==.Dracopeet:BAABLgAECn8aAAQWAAcJvwQ3cACLAAAWAAUJEgU3cACLAAAYAAQJGwPVNQBOAAAXAAMJwQLDKQAnAAAAAA==.Dragonator:BAAALgAECgMJAwAAAA==.Drausella:BAAALgAECgEJAQAAAA==.Dregomalfoy:BAAALgAECgQJBAAAAA==.Drexor:BAAALgAECgQJCwAAAA==.',
Du='Dudè:BAAALgAECgQJAwAAAA==.',
Dv='Dvlzadvocate:BAAALgAECgYJEgAAAA==.',
['Dâ']='Dâggèr:BAAALgAFFAEJAQAAAA==.',
['Dü']='Dürin:BAAALgAECgEJAgAAAA==.',
Ec='Echidna:BAABLgAECn8dAAIIAAcJKAr/nQACAQAIAAcJKAr/nQACAQAAAA==.',
Ed='Edgeovo:BAAALgAECgEJAQABLgAECgEJAgADAAAAAA==.Edict:BAAALgAECgEJAQAAAA==.',
El='Elawen:BAAALgAECgYJDQAAAA==.Elder:BAAALgAECgEJAgAAAA==.Eleblah:BAAALgADCgcJBwAAAA==.Elfkinn:BAACLgAFFH8lAAMdAAYJFxzLDQDBAQAdAAYJFxzLDQDBAQAcAAIJ+gAwawBEAAAuAAQKfyUAAx0ACQmmHqQQAFkCAB0ACQmmHqQQAFkCABwABAlrBY+sAG0AAAAA.Elgund:BAAALgADCgQJBAAAAA==.Elivaniel:BAAALgAECgcJEAAAAA==.',
En='Enlargdcrit:BAAALgAECgMJAwAAAA==.',
Eq='Equinox:BAAALgADCgQJBAAAAA==.',
Er='Ericcdraven:BAABLgAECn8iAAIRAAgJgQ5zNwBpAQARAAgJgQ5zNwBpAQAAAA==.Erodoria:BAABLgAECn8eAAMGAAkJSx/eCQCLAgAGAAgJBSLeCQCLAgAeAAUJ/hAFFQAFAQAAAA==.',
Et='Eternalfire:BAAALgADCgcJDgABLgAECgkJHQAdANwXAA==.',
Ev='Eve:BAAALgAECgEJAQAAAA==.Eveliong:BAAALgADCgEJAQAAAA==.Evilobama:BAAALgAECgUJBgAAAA==.Evoke:BAAALgAFFAEJAQABLgAFFAUJHwAQAFcZAA==.',
Ex='Exzanthia:BAAALgAECgEJAwAAAA==.',
Ey='Eyln:BAABLgAECn8yAAINAAkJpx0cAwCoAgANAAkJpx0cAwCoAgAAAA==.',
Fa='Falkor:BAABLgAECn8tAAMYAAkJqBYADAAXAgAYAAkJqBYADAAXAgAXAAEJ6QI/LAAaAAAAAA==.Fanir:BAAALgAECgcJBwAAAA==.Fatino:BAAALgAECgUJBQAAAA==.Fatkid:BAABLgAECn8VAAILAAcJng95eAAwAQALAAcJng95eAAwAQAAAA==.Fayway:BAABLgAECn9DAAIcAAkJviGPBgBPAwAcAAkJviGPBgBPAwAAAA==.',
Fe='Ferral:BAABLgAECn8hAAITAAkJUx37BACoAgATAAkJUx37BACoAgAAAA==.Festukar:BAAALgAECgUJBwAAAA==.',
Fi='Figgy:BAAALgAECgQJBAAAAA==.Filthypirate:BAABLgAECn8UAAIOAAgJARFqrgAhAQAOAAgJARFqrgAhAQAAAA==.Firepower:BAABLgAECn8hAAIEAAkJxheEOwAsAgAEAAkJxheEOwAsAgABLgAECggJIAATAJcTAA==.Fistatoosh:BAABLgAECn8iAAICAAgJUCSYBgDQAgACAAgJUCSYBgDQAgAAAA==.',
Fl='Florane:BAAALgAECgUJDAAAAA==.Flyingbotato:BAAALgADCgkJFQABLgAECggJIAATAJcTAA==.',
Fo='Forevershy:BAAALgADCgkJEgAAAA==.',
Fr='Fries:BAECLgAFFH8KAAIfAAUJ/x7DBAB6AQAfAAUJ/x7DBAB6AQAuAAQKfxwAAx8ACQkBIpcCAO8CAB8ACQkBIpcCAO8CABAABQkGDH6DANgAAAAA.Fruits:BAAALgAECgYJBwAAAA==.',
Ga='Galdavin:BAABLgAECn8XAAIOAAgJnBqgKQB+AgAOAAgJnBqgKQB+AgAAAA==.Galenhaihi:BAAALgADCgUJBQAAAA==.Galexstrasza:BAAALgADCgYJBgABLgAECgUJDgADAAAAAA==.Gallandia:BAAALgADCgEJAQABLgAECgUJDgADAAAAAA==.Gallielynne:BAAALgAECgUJDgAAAA==.Gankdd:BAABLgAECn8UAAMRAAcJLhuTPgBLAQARAAcJxhmTPgBLAQAgAAMJnRvCHgD4AAAAAA==.Garnnt:BAAALgADCgkJEQAAAA==.',
Gi='Giggles:BAABLgAECn8oAAIPAAkJghQnLQCPAQAPAAkJghQnLQCPAQAAAA==.Gigglez:BAAALgADCggJCAAAAA==.Gimmothyjr:BAAALgAECgUJBgAAAA==.',
Gl='Glennspyder:BAAALgAECgQJDQABLgAECgUJFwASAHMLAA==.',
Go='Gonzo:BAAALgAFFAEJAQABLgAFFAUJHwAQAFcZAA==.Goysoldier:BAAALgAFFAMJBAAAAA==.',
Gr='Greenbean:BAABLgAFFH8dAAILAAUJkhizOQA+AQALAAUJkhizOQA+AQABLgAFFAYJJQAdABccAA==.Grelleth:BAAALgAECgQJBQAAAA==.Groddz:BAABLgAECn8WAAILAAkJvgbyhQAUAQALAAkJvgbyhQAUAQAAAA==.Groto:BAAALgAECgYJBgAAAA==.Grrum:BAABLgAECn8fAAQUAAcJXgvbNwAzAQAUAAcJkQnbNwAzAQAVAAQJaQg2WwCpAAAbAAEJQBFEfgA0AAAAAA==.',
Gu='Gurînkaida:BAAALgAECgQJBAAAAA==.',
Ha='Haell:BAAALgAECgYJCgAAAA==.Hanjo:BAABLgAECn8vAAIKAAkJzyHgBADQAgAKAAkJzyHgBADQAgAAAA==.Hanoa:BAAALgAECgYJCgAAAA==.Harakiri:BAABLgAECn8UAAIQAAcJixUvNgCqAQAQAAcJixUvNgCqAQAAAA==.Hardare:BAABLgAECn8ZAAIBAAgJzA31JACvAQABAAgJzA31JACvAQAAAA==.Harpune:BAAALgADCgIJAgAAAA==.Hatookorr:BAAALgAECgUJBQABLgAECggJIAATAJcTAA==.Hayali:BAABLgAECn8iAAILAAgJXRYRPQDTAQALAAgJXRYRPQDTAQAAAA==.',
He='Helledrians:BAAALgAECgQJBgAAAA==.',
Hi='Hiawatha:BAAALgADCgcJAwAAAA==.',
Hm='Hmccrnglbery:BAAALgAECgMJBAABLgAECggJGQABAMwNAA==.',
Ho='Hottogo:BAAALgADCgcJBwAAAA==.',
Hw='Hwei:BAAALgADCgEJAQAAAA==.',
Hy='Hydé:BAAALgAECggJEAABLgAECgkJHgAeAFggAA==.Hypatia:BAABLgAECn8dAAIBAAgJqiGqDQBrAgABAAgJqiGqDQBrAgAAAA==.',
['Hä']='Häxan:BAAALgAECgQJBAAAAA==.',
Ia='Iame:BAAALgADCgMJAwAAAA==.Iapetus:BAAALgADCgIJAgAAAA==.',
Ic='Icedchi:BAEBLgAECn8iAAICAAkJ3x/SEQApAgACAAkJ3x/SEQApAgAAAA==.',
In='Incite:BAABLgAECn8gAAMhAAkJaA9lCgCRAQAhAAkJZQ9lCgCRAQAiAAUJ+g2QQQAUAQAAAA==.',
Is='Ishvala:BAAALgADCgMJAwAAAA==.',
Ja='Jackpad:BAAALgAECgEJAgAAAA==.Jademist:BAAALgAECgYJCgABLgAECgkJLQAYAKgWAA==.Jaland:BAAALgADCgMJAwAAAA==.Jarrel:BAAALgAECgIJBAAAAA==.',
Je='Jellybreak:BAABLgAECn88AAMdAAkJhBY+GAALAgAdAAkJhBY+GAALAgAjAAcJqQjkPgCrAAAAAA==.',
Jo='Joeewee:BAAALgAECgYJBgAAAA==.Jonjud:BAAALgAECgYJDAAAAA==.',
Js='Jskimonkpo:BAAALgADCgUJCQAAAA==.',
Ju='Julius:BAAALgAFFAEJAQAAAA==.',
Jy='Jyrian:BAAALgADCgMJAwAAAA==.',
Ka='Kaanâ:BAABLgAECn8yAAIbAAkJWhxkCQDSAgAbAAkJWhxkCQDSAgAAAA==.Kaelei:BAAALgADCgkJKwAAAA==.Kagamire:BAAALgADCgYJBQAAAA==.Kamine:BAAALgAECgUJEAAAAA==.Kanyeeast:BAAALgAECgYJCgAAAA==.Karnen:BAAALgAECgMJAwAAAA==.Kateblue:BAABLgAECn8uAAIdAAkJhRoEEABhAgAdAAkJhRoEEABhAgAAAA==.',
Ke='Kelcier:BAAALgADCgYJBgAAAA==.Kelser:BAABLgAECn8VAAMZAAcJ2B7FBAApAgAZAAcJ2B7FBAApAgAIAAMJoBXuxgDLAAAAAA==.Kensington:BAABLgAECn8hAAIhAAgJdggpDgBDAQAhAAgJdggpDgBDAQAAAA==.Kethry:BAAALgADCgcJBwAAAA==.',
Ki='Kiku:BAABLgAECn8iAAIWAAkJYiPtBQD+AgAWAAkJYiPtBQD+AgAAAA==.Kikyou:BAAALgAECgYJBgABLgAECgkJIgAWAGIjAA==.Kim:BAABLgAECn8fAAIkAAkJRhBqFgDuAQAkAAkJRhBqFgDuAQAAAA==.Kinrah:BAAALgADCgMJAwAAAA==.Kirandra:BAAALgADCgMJAwAAAA==.Kirëë:BAAALgAECggJCAAAAA==.Kissofdeáth:BAAALgAECgIJAwAAAA==.',
Ko='Korlock:BAABLgAECn8mAAQIAAkJAB4vNAA8AgAIAAgJGR0vNAA8AgAaAAEJAACvbAA7AAAZAAEJPRc5PQA4AAAAAA==.',
Kr='Kreepywife:BAABLgAECn8ZAAIVAAcJ7BcRAQBBAQAVAAcJ7BcRAQBBAQAAAA==.Krelbelorll:BAAALgAECgEJAQAAAA==.Krowley:BAABLgAECn8nAAIQAAkJPxB0MADzAQAQAAkJPxB0MADzAQAAAA==.',
Ku='Kurast:BAAALgAECgMJAwABLgAECgkJLQAYAKgWAA==.Kuzan:BAACLgAFFH8TAAIEAAUJEB+HTABHAQAEAAUJEB+HTABHAQAuAAQKfx8AAgQABwl3IfQ2AJgCAAQABwl3IfQ2AJgCAAAA.',
Kx='Kxwono:BAAALgAECgcJBwAAAA==.',
Ky='Kyoyama:BAAALgAECgMJBwABLgAFFAMJDQAZAAEhAA==.',
La='Lacious:BAAALgADCgEJAQABLgAECgkJOwASAKceAA==.Ladýshinobu:BAABLgAECn8nAAIMAAgJQBBFKQDDAQAMAAgJQBBFKQDDAQAAAA==.Lananar:BAAALgADCgUJBQAAAA==.Layssaenna:BAAALgAECgYJCAAAAA==.',
Le='Leahu:BAABLgAECn88AAIlAAkJBhiuCgAfAgAlAAkJBhiuCgAfAgAAAA==.Lediaa:BAAALgAECgMJBAAAAA==.',
Li='Lifekiller:BAAALgAECgYJDwAAAA==.Lightark:BAAALgAECgEJAgAAAA==.Linekingz:BAAALgADCgEJAQAAAA==.Linetheshamy:BAAALgADCgkJDQAAAA==.Lineurathrot:BAAALgADCgYJCAAAAA==.Lisavia:BAAALgADCgUJBgAAAA==.Littlespyone:BAABLgAECn8XAAISAAUJcwvczgCsAAASAAUJcwvczgCsAAAAAA==.Lizardman:BAAALgAFFAEJAQAAAA==.',
Lo='Locholovis:BAABLgAECn8wAAIaAAkJOhR5BwDcAQAaAAkJOhR5BwDcAQAAAA==.Locklicous:BAABLgAECn8WAAMIAAkJ2xemPQDlAQAIAAkJ2BOmPQDlAQAZAAYJWxV4EgBBAQAAAA==.Longhorse:BAACLgAFFH8fAAIFAAUJZCKrEgBiAQAFAAUJZCKrEgBiAQAuAAQKfzEAAwUACQn4JMgFAOACAAUACQmpIsgFAOACAAkABgnhJfhfAKkBAAAA.Longknight:BAAALgAECgEJAQAAAA==.Longr:BAAALgAECgYJCwAAAA==.Lorna:BAABLgAECn8XAAILAAgJJhJdVgCEAQALAAgJJhJdVgCEAQAAAA==.Lorthimar:BAAALgAECgUJCgABLgAECgkJJgAIAAAeAA==.',
Lu='Lumi:BAABLgAECn8WAAIEAAkJchhyUQDoAQAEAAkJchhyUQDoAQAAAA==.Luminarae:BAAALgADCgEJAQAAAA==.Luminouss:BAABLgAFFH8OAAIQAAcJuBKSFQC5AQAQAAcJuBKSFQC5AQABLgAFFAMJBgAUAOcUAA==.Lumpia:BAABLgAFFH8IAAILAAUJGBnCQgAfAQALAAUJGBnCQgAfAQAAAA==.',
Ly='Lylo:BAAALgADCgEJAQAAAA==.Lyrinir:BAABLgAECn8dAAMKAAkJ/hkjEQD2AQAKAAkJ/hkjEQD2AQAgAAEJigTcigAbAAAAAA==.Lyrium:BAABLgAECn8ZAAMeAAgJtRm8CgC4AQAeAAUJDR+8CgC4AQAGAAcJ+RA4KgAtAQABLgAECgkJHQAKAP4ZAA==.',
Ma='Madar:BAABLgAECn8gAAIIAAgJpgYkmQALAQAIAAgJpgYkmQALAQAAAA==.Maggus:BAAALgADCgQJBAAAAA==.Magicgal:BAAALgAECggJDQAAAA==.Maiden:BAAALgAECgUJBQAAAA==.Maiklytzwhet:BAAALgAECgUJBQAAAA==.Mairon:BAAALgAECgMJBgAAAA==.Malvorak:BAABLgAECn8yAAIFAAgJcREbHwBcAQAFAAgJcREbHwBcAQAAAA==.Mande:BAAALgADCgQJBAAAAA==.Mantis:BAAALgAECgkJDAABLgAECgkJLQAYAKgWAA==.Marrock:BAAALgAECgYJEQAAAA==.Marzipain:BAAALgAECgEJAQAAAA==.Mavarasie:BAAALgAECgUJDgAAAA==.Mavaressy:BAAALgAECgMJAwAAAA==.Mavaria:BAAALgAECgUJCQAAAA==.',
Mc='Mcmuffin:BAAALgAECgYJEAAAAA==.',
Me='Mechacattie:BAABLgAECn87AAISAAkJpx4kFACxAgASAAkJpx4kFACxAgAAAA==.Mediator:BAAALgAECgEJAQAAAA==.Meekerz:BAAALgAECgIJAgAAAA==.Mega:BAAALgAFFAIJAwAAAA==.Melganis:BAAALgADCgMJBAAAAA==.Melissandra:BAABLgAECn8pAAMVAAgJ0gxjNgA9AQAVAAgJ0gxjNgA9AQAbAAIJiAb1dABVAAAAAA==.Mercas:BAAALgAECgcJDwABLgAECgkJJgAjAKMaAA==.Metacallae:BAAALgADCgcJAQAAAA==.Mezi:BAABLgAECn9CAAIbAAkJ4SFoBwD4AgAbAAkJ4SFoBwD4AgAAAA==.Mezmera:BAAALgADCgUJBgABLgAECgIJAwADAAAAAA==.',
Mh='Mhonster:BAAALgAECgYJBgABLgAECgcJCQADAAAAAA==.',
Mi='Missed:BAAALgAECgQJBQAAAA==.Mittens:BAACLgAFFH8GAAIUAAMJ5xRiMADRAAAUAAMJ5xRiMADRAAAuAAQKfxkAAxsACQlbGXQoAK0BABsABgn7GXQoAK0BABQABwlvE8ohAIUBAAAA.',
Mo='Mofro:BAAALgADCgQJBAABLgAECgQJBAADAAAAAA==.Mokgunal:BAAALgADCgQJBAAAAA==.Money:BAAALgADCgIJAgABLgAECggJIwAOABghAA==.Moneyshotinc:BAAALgAECgkJCgABLgAECggJIwAOABghAA==.Moraine:BAAALgAECgQJBAAAAA==.Moreki:BAAALgAECgMJAwAAAA==.Morro:BAABLgAECn8wAAIPAAkJVw8qKwCaAQAPAAkJVw8qKwCaAQAAAA==.',
Ms='Msvelvet:BAAALgADCgkJHgABLgAECgQJDQADAAAAAA==.',
Mu='Mugiwara:BAACLgAFFH8LAAIBAAQJbCQoDABkAQABAAQJbCQoDABkAQAuAAQKfxYAAgEABwntJAkKANcCAAEABwntJAkKANcCAAAA.Mulron:BAABLgAECn8kAAIlAAkJmhE0EgCjAQAlAAkJmhE0EgCjAQAAAA==.',
My='Myrica:BAAALgAECggJDQAAAA==.',
['Må']='Mådcõw:BAAALgAECgUJBgAAAA==.',
['Mö']='Mööve:BAAALgAECgMJAwAAAA==.',
Na='Nallos:BAAALgADCgEJAQAAAA==.Natajapar:BAAALgAECgEJAQABLgAECgcJCQADAAAAAA==.',
Ne='Nefesh:BAABLgAFFH8WAAILAAUJnwp9VADxAAALAAUJnwp9VADxAAAAAA==.Neff:BAAALgADCgMJAwAAAA==.',
Ni='Nightingales:BAAALgAECgMJAwAAAA==.',
Ny='Nyomie:BAAALgADCgEJAgAAAA==.Nyyx:BAAALgAECgQJBAABLgAECgYJCgADAAAAAA==.',
Oa='Oakenshíeld:BAACLgAFFH8VAAIdAAYJ4BHuGQBKAQAdAAYJ4BHuGQBKAQAuAAQKfzsAAh0ACQlCF9AUAGsCAB0ACQlCF9AUAGsCAAAA.',
Ob='Obama:BAAALgADCgQJBAAAAA==.',
Og='Oggy:BAAALgAECgkJDAABLgAECgkJLQAYAKgWAA==.',
Ol='Olkwon:BAAALgAFFAIJAwAAAA==.',
On='Onlyfeigns:BAAALgAECgIJAgAAAA==.',
Oo='Oozwoz:BAAALgAECgcJDgAAAA==.',
Or='Orileluu:BAAALgAECgEJAQAAAA==.',
Ox='Oxwon:BAAALgAECgYJCwAAAA==.',
Pa='Paisho:BAAALgAECgQJBQAAAA==.Palliera:BAAALgAECgQJBAAAAA==.Pallirot:BAAALgAECggJCAAAAA==.Pallynomial:BAAALgADCgcJCgAAAA==.Pawmuck:BAABLgAECn8tAAIOAAgJ9RlBPAATAgAOAAgJ9RlBPAATAgAAAA==.',
Pe='Peer:BAAALgAECgEJAgAAAA==.Pewpewtazarz:BAAALgAECgUJCQAAAA==.',
Ph='Phancy:BAAALgADCggJDgAAAA==.Phrizzle:BAAALgADCgMJAwAAAA==.',
Pl='Plaguebeard:BAABLgAECn8XAAMJAAcJBx9/PABFAgAJAAcJBx9/PABFAgAFAAUJCRiiJwABAQAAAA==.Plagueblade:BAABLgAECn8rAAMFAAkJUxmVEgDlAQAFAAkJOhiVEgDlAQAJAAEJ3Rp4VAFNAAAAAA==.',
Po='Podtinder:BAAALgAECgcJDAABLgAECgkJLQAYAKgWAA==.Poof:BAAALgAECgYJCgABLgAECgkJHgAKAJIaAA==.Poseidon:BAAALgAECgIJAgAAAA==.',
Pr='Prescription:BAABLgAECn8XAAMHAAgJ+AkIYQD1AAAHAAcJ1AkIYQD1AAABAAcJvQirRQDpAAAAAA==.Progression:BAAALgAECgEJBgAAAA==.',
Pu='Punish:BAAALgAECgEJAQAAAA==.',
Py='Pyrolord:BAAALgADCgYJCAAAAA==.',
Ra='Ragingrain:BAABLgAECn8jAAIlAAgJVxmxDAD6AQAlAAgJVxmxDAD6AQAAAA==.Rainsshammy:BAAALgAECgQJCAAAAA==.Rainthefire:BAABLgAECn8/AAISAAkJZRqSLAArAgASAAkJZRqSLAArAgAAAA==.Ralthor:BAAALgADCgMJAwAAAA==.Ramalama:BAAALgAECgEJAgAAAA==.Rassarudk:BAAALgAECgYJCwAAAA==.Ravinfire:BAAALgAECgQJBwAAAA==.Rawktuah:BAAALgAECgMJAwAAAA==.',
Re='Realhelz:BAAALgAECgQJBQAAAA==.Redcross:BAAALgAECgYJDgAAAA==.Redoxx:BAAALgAECgYJDQAAAA==.Restofarian:BAACLgAFFH8fAAIQAAUJVxlLAwAMAQAQAAUJVxlLAwAMAQAuAAQKfyMAAhAACQmJG0UXAFsCABAACQmJG0UXAFsCAAAA.',
Rh='Rhagnor:BAAALgAECgQJBAAAAA==.',
Ri='Rianon:BAAALgADCgkJEgABLgAECgkJLAALABobAA==.Rift:BAAALgAECgEJAwAAAA==.Righteous:BAABLgAECn8sAAIbAAkJPRwdAQBOAQAbAAkJPRwdAQBOAQAAAA==.Rizzy:BAABLgAECn8iAAMFAAkJSBeoDwARAgAFAAkJSBeoDwARAgAJAAkJ7gjvbQCJAQAAAA==.',
Ro='Rollinsinc:BAAALgAECgkJAwAAAA==.Roshin:BAAALgAECgEJAgAAAA==.Rotinlock:BAAALgADCgYJDAAAAA==.Rotinshot:BAACLgAFFH8TAAMSAAYJuxHeIQB9AQASAAYJuxHeIQB9AQAkAAIJbgMfLQB6AAAuAAQKfygAAxIACQlsIWUWAIUCABIACAmTImUWAIUCACQACAl0GuEQALYBAAAA.',
Ru='Ruin:BAAALgAECgMJBAAAAA==.Rutikee:BAABLgAECn9GAAIcAAgJAxaYLgDrAQAcAAgJAxaYLgDrAQAAAA==.',
Sa='Sacerdos:BAABLgAECn8VAAIbAAgJlBW8FgAmAgAbAAgJlBW8FgAmAgABLgAECgkJOgAIAAEbAA==.Saeris:BAAALgADCggJCAABLgAECgcJDgADAAAAAA==.Sagordez:BAACLgAFFH8FAAMHAAEJSBXFYAA/AAAHAAEJSBXFYAA/AAABAAEJ0ArYRAA2AAAuAAQKfygABAcACAm0HjAZAE4CAAcABwmVHjAZAE4CAAIABwlxFXgmAHsBAAEAAQnhD7SjAC0AAAEuAAQKCQkeAB4AWCAA.Salima:BAAALgADCgMJAwAAAA==.Saltybrew:BAAALgADCgMJAwAAAA==.Sandrill:BAAALgAECgYJCgABLgAECggJIAATAJcTAA==.Satorugojo:BAAALgAECgUJBgAAAA==.Savior:BAAALgAECgUJDwAAAA==.Sazed:BAAALgAECggJDgAAAA==.',
Sc='Scrom:BAAALgAECgIJBAAAAA==.',
Se='Seabush:BAAALgAECgIJAwAAAA==.Seastorm:BAAALgAECgkJCAAAAA==.Seeker:BAAALgAECgEJAQAAAA==.Seizon:BAABLgAECn8hAAMkAAgJzBSnAABjAQAkAAgJzBSnAABjAQANAAIJmQf4MwBMAAAAAA==.Semila:BAAALgAECgcJCQAAAA==.Sendor:BAAALgAECgYJBgAAAA==.Senseicanz:BAAALgAECgQJBAAAAA==.Sepulchure:BAAALgADCgMJAwAAAA==.Serina:BAAALgAECgQJBgABLgAECgkJKwAFAFMZAA==.Serom:BAABLgAECn8hAAIcAAgJdRlhHwBLAgAcAAgJdRlhHwBLAgAAAA==.Sesshomaaru:BAAALgADCggJEQAAAA==.',
Sh='Shaazrah:BAABLgAECn8fAAICAAkJSyGVCgCKAgACAAkJSyGVCgCKAgAAAA==.Shadowoak:BAAALgAECgIJAgAAAA==.Shadows:BAAALgADCgcJBwAAAA==.Shamkazaam:BAAALgAECggJCwAAAA==.Shammyhagär:BAAALgADCgMJAwABLgAECgQJBAADAAAAAA==.Sharalvia:BAAALgADCgUJCAAAAA==.Sharkn:BAAALgAECgEJAQAAAA==.Sharkyo:BAAALgADCgIJAgAAAA==.Sharpshôôter:BAAALgAECgEJAQAAAA==.Sherunn:BAABLgAECn8iAAIdAAcJpQ0ZOgAqAQAdAAcJpQ0ZOgAqAQAAAA==.Shifty:BAAALgAECgEJAgAAAA==.Shiftydon:BAABLgAECn8eAAQTAAkJ0RAyEAC0AQATAAkJ0RAyEAC0AQAcAAIJ+Q2CqwBeAAAjAAEJMguOgAAhAAAAAA==.Shimakaze:BAABLgAECn88AAISAAkJoA66RQDQAQASAAkJoA66RQDQAQAAAA==.Shirvana:BAAALgAECgQJBwABLgAECgcJCQADAAAAAA==.Shooters:BAABLgAECn8YAAIkAAkJOx26DQDuAQAkAAkJOx26DQDuAQAAAA==.Shortbow:BAAALgADCgQJBgABLgAECgEJAgADAAAAAA==.Shyminx:BAAALgADCgkJEgAAAA==.Shymistress:BAACLgAFFH8FAAISAAEJxBjnEQBWAAASAAEJxBjnEQBWAAAuAAQKfzkAAhIACQkTIsIMAO0CABIACQkTIsIMAO0CAAAA.Shåmmy:BAABLgAECn8/AAIQAAkJ7hPrKAAaAgAQAAkJ7hPrKAAaAgAAAA==.',
Si='Simonezer:BAAALgAECgkJAwAAAA==.Sins:BAABLgAECn8nAAIdAAkJVR9YCQC+AgAdAAkJVR9YCQC+AgAAAA==.Sionell:BAAALgADCgQJBAAAAA==.',
Sk='Skiá:BAACLgAFFH8GAAITAAMJtBIBDwDPAAATAAMJtBIBDwDPAAAuAAQKf1QAAhMACQm7IewBABYDABMACQm7IewBABYDAAAA.Skodoosh:BAAALgAECgYJDwAAAA==.Skrinkles:BAAALgAECgYJDgAAAA==.Skyrocket:BAAALgAECgIJAwAAAA==.',
Sl='Slashpoison:BAAALgADCgcJDgAAAA==.Slicedbread:BAACLgAFFH8UAAIMAAYJ/BzeBwBUAQAMAAYJ/BzeBwBUAQAuAAQKfycAAwwACQk7IOwOAJ4CAAwACQk7IOwOAJ4CAA4ABwkKG6BBACACAAAA.Slorth:BAACLgAFFH8GAAIJAAMJNBYpoADUAAAJAAMJNBYpoADUAAAuAAQKfyIAAgkACAkYGn5KABMCAAkACAkYGn5KABMCAAAA.',
Sm='Smallfrye:BAAALgAECgEJAQAAAA==.',
Sn='Snizzlaki:BAABLgAECn8+AAICAAkJQg+/IAChAQACAAkJQg+/IAChAQAAAA==.',
So='Sofa:BAAALgADCgkJDAAAAA==.Solaene:BAAALgAECgcJCQAAAA==.Soundsmystic:BAAALgADCgUJBQAAAA==.',
Sp='Sparkilies:BAAALgADCgYJBgAAAA==.Sparkleglory:BAAALgAECgMJAwAAAA==.Spicybreath:BAAALgAECgQJBAABLgAECgcJEQADAAAAAA==.Spicydemon:BAAALgAECgcJEQAAAA==.Spicydrood:BAAALgAECgEJAQAAAA==.Spicytotems:BAAALgAECgEJAQAAAA==.Splaash:BAAALgAECgMJAwAAAA==.Splàsh:BAABLgAECn8bAAQQAAkJ3x8aBgAQAwAQAAkJ3x8aBgAQAwAPAAUJpRWKZQC1AAAfAAIJRg3XMgBlAAAAAA==.',
St='Starwolfy:BAAALgAECgUJBQAAAA==.Steakman:BAAALgADCgIJAgAAAA==.Stoneboot:BAAALgAECggJEwAAAA==.',
Su='Sumaria:BAABLgAECn8mAAIVAAgJkgFZZgCDAAAVAAgJkgFZZgCDAAAAAA==.',
Sw='Sweatycrits:BAAALgAECggJDQAAAA==.Sweetvixen:BAAALgAECgQJDQAAAA==.',
Sy='Sylvanasthot:BAAALgADCgYJDAAAAA==.',
['Sä']='Sävägeäf:BAAALgADCgcJBwAAAA==.',
Ta='Taana:BAAALgAECgUJCgAAAA==.Takbez:BAABLgAECn8gAAITAAgJlxOSCwAGAgATAAgJlxOSCwAGAgAAAA==.Tandria:BAAALgAECgYJCwAAAA==.Tarot:BAAALgADCgEJAQAAAA==.Taterhops:BAAALgAECgEJAQABLgAECgkJKAAEAD4gAA==.Tattered:BAAALgADCgEJAQAAAA==.Tauru:BAABLgAECn8fAAMcAAgJRRmzIQA6AgAcAAgJRRmzIQA6AgAdAAEJphGCiwA1AAAAAA==.Tazale:BAAALgAECggJCgABLgAECgYJBgADAAAAAA==.',
Te='Teakaachu:BAABLgAECn8YAAIHAAgJKBTPKQDdAQAHAAgJKBTPKQDdAQAAAA==.Terdanator:BAABLgAECn8fAAMfAAgJFhY/DQDdAQAfAAgJFhY/DQDdAQAPAAEJLQZxuQAjAAAAAA==.Tetranis:BAAALgADCgQJBgAAAA==.',
Th='Thanathot:BAAALgADCgMJAwAAAA==.Thanatus:BAABLgAECn86AAQIAAkJARsuIQBeAgAIAAkJARsuIQBeAgAZAAQJyRCuIAC8AAAaAAEJzgf2eAAqAAAAAA==.Themia:BAAALgADCgMJAwAAAA==.',
Ti='Tiari:BAABLgAECn8rAAMMAAkJ8xvZDADCAgAMAAkJ8xvZDADCAgAOAAYJ0APeFAGgAAAAAA==.Tidepod:BAAALgADCgIJAgAAAA==.Timesink:BAAALgAECgQJBQAAAA==.Tisane:BAAALgAECgMJAwAAAA==.',
Tn='Tntclepriest:BAAALgAECgcJDQABLgAECgYJFAAZAGkVAA==.',
Tr='Tralline:BAAALgADCgMJAgAAAA==.Tranzig:BAAALgADCgUJBQAAAA==.Tridius:BAABLgAECn8XAAQVAAgJkxZjGwDqAQAVAAgJkxZjGwDqAQAUAAYJpBi+OAAvAQAbAAIJfB6ZTQCsAAAAAA==.Trollins:BAAALgAECgIJAgAAAA==.Truda:BAAALgAECgIJAgAAAA==.',
Tu='Turdanator:BAABLgAECn9NAAMVAAkJDhlTEwA3AgAVAAkJDhlTEwA3AgAbAAcJ/gtsQQAzAQAAAA==.',
Tw='Twizzlers:BAAALgAECgQJBAAAAA==.',
Up='Upgraydd:BAAALgAECgIJBAABLgAECgcJEQADAAAAAA==.',
Ur='Uraenus:BAAALgAECgcJEwAAAA==.Urahrotar:BAAALgADCgUJBgAAAA==.Uriah:BAABLgAECn8qAAISAAkJxRauMgASAgASAAkJxRauMgASAgAAAA==.Ursúla:BAABLgAFFH8KAAIIAAQJ6govYAAHAQAIAAQJ6govYAAHAQABLgAFFAYJJQAdABccAA==.Uryu:BAAALgAECgQJBAAAAA==.Urïah:BAAALgAECgYJDAABLgAECgkJKgASAMUWAA==.',
Ut='Utherr:BAABLgAFFH8FAAIOAAMJ6BrMaADdAAAOAAMJ6BrMaADdAAAAAA==.',
Va='Valaravaus:BAAALgAECgEJAwAAAA==.Valionandros:BAAALgAECgYJBwAAAA==.Vanaril:BAAALgAECgMJAwAAAA==.Vashirr:BAAALgAECgMJAwAAAA==.',
Ve='Veldonir:BAAALgAECgEJAQAAAA==.Vergus:BAAALgAECgQJBAAAAA==.',
Vi='Violin:BAEALgAECgIJAwABLgAECggJDAADAAAAAA==.Violinmax:BAEALgAECgYJDQABLgAECggJDAADAAAAAA==.Viral:BAAALgAFFAEJAQAAAA==.',
Vo='Voidnova:BAAALgAECgEJAQAAAA==.Vonnie:BAAALgAECgUJBQAAAA==.',
Vy='Vynlerinis:BAABLgAECn8eAAIeAAkJWCAJAwC5AgAeAAkJWCAJAwC5AgAAAA==.',
['Vé']='Végeta:BAAALgAECgIJAgABLgAECgkJLQAYAKgWAA==.',
Wa='Wardestroyer:BAAALgAECggJEQAAAA==.Wardwhelp:BAABLgAECn8eAAIKAAkJkhoRDwD4AQAKAAkJkhoRDwD4AQAAAA==.',
Wi='Wifehaver:BAABLgAECn8oAAICAAkJuR8jFAANAgACAAkJuR8jFAANAgAAAA==.Wildmist:BAAALgAECgMJAwAAAA==.Winniedapoo:BAABLgAECn80AAIIAAgJ2BubNgD/AQAIAAgJ2BubNgD/AQAAAA==.Winterpaw:BAAALgAECgEJAQABLgAECgkJKwAFAFMZAA==.',
Wo='Wooloo:BAACLgAFFH8gAAQIAAkJHiC8CQB2AgAIAAgJ4yG8CQB2AgAaAAQJ+xgfAwBvAQAZAAEJAADKBABZAAAuAAQKfygAAwgACQmzJfwPAM0CAAgACQmzJfwPAM0CABoABAlPHXogAE8BAAAA.',
Wu='Wurm:BAAALgAECgIJAgAAAA==.',
Wy='Wynona:BAAALgAECgUJBQAAAA==.',
Xa='Xanagore:BAABLgAECn8oAAMRAAkJVyJGBwDqAgARAAkJ6SFGBwDqAgAKAAEJ0RbNUgAzAAAAAA==.Xanllan:BAAALgAECgQJBgAAAA==.Xanthecat:BAAALgAECgQJBAAAAA==.Xanzul:BAABLgAECn8ZAAINAAcJOxPmDgBvAQANAAcJOxPmDgBvAQABLgAECgkJKAARAFciAA==.',
Xe='Xenojiiva:BAAALgADCgIJAgABLgAECgcJCQADAAAAAA==.',
Xk='Xkwon:BAAALgAFFAEJAQAAAA==.Xkwøn:BAACLgAFFH8XAAImAAQJ3hrHBABKAQAmAAQJ3hrHBABKAQAuAAQKfzwAAiYACQkwIdsCAIUCACYACQkwIdsCAIUCAAAA.',
Xu='Xunie:BAABLgAECn8oAAIJAAkJHBV2NAAtAgAJAAkJHBV2NAAtAgAAAA==.',
Xx='Xximage:BAABLgAECn8dAAMnAAkJ1CRfAQDIAgAnAAkJ1CRfAQDIAgAEAAEJAACeWgFLAAAAAA==.',
Yu='Yulìe:BAAALgADCgcJBwAAAA==.',
Za='Zaibloom:BAAALgADCggJFgAAAA==.Zana:BAABLgAECn8ZAAILAAgJPRLEdgAzAQALAAgJPRLEdgAzAQAAAA==.Zaretan:BAAALgADCgkJFgAAAA==.',
Zb='Zbrute:BAABLgAECn8pAAISAAkJXxz9FwCXAgASAAkJXxz9FwCXAgAAAA==.',
Ze='Zeffen:BAAALgAECgIJBAABLgAECggJIAAIAKYGAA==.Zefphenn:BAAALgAECgQJBgABLgAECggJIAAIAKYGAA==.Zenny:BAAALgADCggJEwAAAA==.',
Zi='Zildroghar:BAAALgADCgcJCAAAAA==.Zivz:BAAALgADCgUJBQAAAA==.',
Zo='Zokohjin:BAABLgAECn8lAAMJAAkJWBydLgBFAgAJAAkJWBydLgBFAgAFAAIJ+xeLQQCJAAAAAA==.',
Zu='Zulgar:BAAALgAFFAIJAgABLgAFFAgJFgAEAFgZAA==.Zulpher:BAAALgADCgYJEwAAAA==.',
['Ðo']='Ðondon:BAAALgADCgQJBQAAAA==.Ðoppelgänger:BAAALgAECgEJBQAAAA==.',
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
