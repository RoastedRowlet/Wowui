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

local lookup = {'Unknown-Unknown','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Havoc','Priest-Holy','Evoker-Augmentation','Druid-Guardian','Druid-Balance','Druid-Feral','Paladin-Holy','Mage-Frost','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Warrior-Arms','DemonHunter-Vengeance','Priest-Shadow','Warrior-Fury','Priest-Discipline','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','DemonHunter-Devourer','Mage-Fire','Rogue-Assassination','DeathKnight-Blood','Evoker-Devastation','Mage-Arcane','Monk-Brewmaster',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abelao:BAAALgAECgcJEwAAAA==.',
Ad='Adelaide:BAAALgAECgIJAgABLgAECggJDQABAAAAAA==.Adoramuss:BAAALgAECgYJCwAAAA==.Adrianoj:BAAALgAECgEJAQAAAA==.',
Ae='Aelon:BAAALgADCgEJAQAAAA==.Aelthor:BAAALgAECgQJCwAAAA==.',
Ah='Ahmus:BAAALgAECgUJDAAAAA==.Ahrallu:BAAALgADCgEJAgAAAA==.',
Ai='Aioliavictus:BAAALgADCgIJAgAAAA==.',
Al='Alanie:BAAALgAECgUJCQABLgAECggJIwACABUeAA==.Aldranir:BAAALgADCgEJAQAAAA==.Alessaxd:BAABLgAECn8ZAAMDAAkJBhBIQgC1AQADAAkJYg9IQgC1AQAEAAIJtRDUGAB6AAAAAA==.Alexa:BAAALgAECgQJBAAAAA==.Alfajhor:BAABLgAECn8zAAMFAAgJXR1vCwC4AQAFAAYJ9yFvCwC4AQAGAAgJHBzNVQB/AQAAAA==.Alfajhòr:BAAALgAECgEJAQAAAA==.Alfajhôr:BAAALgAECgUJBwAAAA==.Alkarin:BAAALgAECgEJAwAAAA==.Allandriel:BAAALgAECgQJBAAAAA==.Alldarion:BAAALgAECgMJCQAAAA==.Allendra:BAAALgADCgcJCQAAAA==.Alleriane:BAABLgAECn8wAAMHAAgJvh4RCQCqAgAHAAgJvh4RCQCqAgAIAAEJpwKRjQAYAAAAAA==.Allerios:BAAALgAECgUJCQAAAA==.Allone:BAABLgAECn8ZAAIJAAcJZwyHLQBfAQAJAAcJZwyHLQBfAQAAAA==.Allyhra:BAAALgADCgQJBAAAAA==.Allëria:BAAALgADCgMJAwAAAA==.',
Am='Ametnys:BAAALgAECgEJAwAAAA==.Amonhar:BAAALgADCgIJAgABLgAECgkJMAAKAOAQAA==.Amyn:BAAALgADCgYJBwAAAA==.',
An='Anakata:BAAALgAECgUJEwAAAA==.Anakinini:BAABLgAECn8bAAILAAgJhAhKMQAYAQALAAgJhAhKMQAYAQABLgAECgYJBgABAAAAAA==.Analia:BAABLgAECn8jAAQCAAgJFR5/HgBLAgACAAcJVR1/HgBLAgAMAAgJnQjtHgDSAAANAAMJPxw0RgCdAAAAAA==.Andaliz:BAACLgAFFH8JAAIGAAMJ8iF8KAAwAQAGAAMJ8iF8KAAwAQAuAAQKfyoAAgYACQmiJRsCAF0DAAYACQmiJRsCAF0DAAAA.Andorith:BAAALgAECgEJAQAAAA==.Anelie:BAAALgAECgQJDQABLgAECggJIwACABUeAA==.Ansalon:BAAALgADCgYJBwAAAA==.Antonellaes:BAAALgAECgMJAwABLgAECgcJDQABAAAAAA==.',
Ao='Aoiisuu:BAAALgADCgYJCAAAAA==.',
Ap='Apodrecido:BAAALgAECgYJBgAAAA==.',
Ar='Arajakata:BAAALgAECgEJAgAAAA==.Arctorius:BAAALgAECgYJDAAAAA==.Arethiel:BAAALgADCgYJBgAAAA==.Arlandriah:BAAALgADCgYJCQABLgAECgYJGAAGABAYAA==.Artronis:BAABLgAECn8jAAMMAAgJYxUwDQCjAQAMAAgJYxUwDQCjAQAOAAEJPRQSLwA/AAAAAA==.Artånis:BAAALgAECgcJCwAAAA==.Aruthuro:BAAALgAECgYJDwAAAA==.',
As='Ashbörn:BAAALgADCgcJDgAAAA==.',
At='Atriuz:BAABLgAECn8bAAIPAAYJahouLwDGAQAPAAYJahouLwDGAQAAAA==.Ats:BAAALgADCgYJCgAAAA==.',
Ay='Aykho:BAABLgAECn8nAAIQAAgJRBbnSAC9AQAQAAgJRBbnSAC9AQAAAA==.',
Az='Azurion:BAAALgAECgQJBAAAAA==.',
['Aÿ']='Aÿ:BAAALgADCgYJBgAAAA==.',
Ba='Baguh:BAAALgADCggJCAAAAA==.Bagunça:BAAALgADCgYJBgAAAA==.Bakuugou:BAAALgAECgMJBgAAAA==.Bambur:BAAALgADCgMJAwAAAA==.Barbabruto:BAABLgAECn8jAAIRAAgJ6RuvCQAPAgARAAgJ6RuvCQAPAgAAAA==.Basilisco:BAAALgAECgEJAQAAAA==.',
Be='Belleg:BAAALgAECgEJAQAAAA==.',
Bf='Bf:BAAALgADCgEJAQAAAA==.',
Bi='Biafalcão:BAAALgAECgEJAQAAAA==.Bijanca:BAAALgAECgYJBgAAAA==.Birthdäy:BAAALgADCgEJAQAAAA==.Bisponegro:BAAALgAECgQJBwABLgABCgcJFQABAAAAAA==.Biønic:BAAALgAECgMJCQAAAA==.',
Bl='Blackline:BAABLgAECn8YAAIDAAgJHBBDXABqAQADAAgJHBBDXABqAQAAAA==.',
Bo='Boipretim:BAAALgAECgUJDQAAAA==.Bontorius:BAAALgADCgEJAgAAAA==.Bordello:BAAALgADCgUJBQAAAA==.',
Br='Bradio:BAAALgADCggJCAAAAA==.Bratloko:BAAALgAECgUJBQAAAA==.Bromos:BAAALgAECgQJCAAAAA==.Brönsted:BAAALgADCgMJAwAAAA==.',
Bu='Bubbalo:BAAALgADCgUJBQAAAA==.Bullsman:BAAALgADCgQJBAAAAA==.Buzzumaaky:BAABLgAECn8YAAIQAAgJSxepiQC/AQAQAAgJSxepiQC/AQAAAA==.',
By='Byakura:BAAALgADCggJCwAAAA==.',
['Bü']='Büdweiser:BAAALgAECgIJAgAAAA==.',
Ca='Cabernet:BAAALgAECgUJBwAAAA==.Cabeçaquente:BAAALgAECgcJCQAAAA==.Calhistra:BAABLgAECn8nAAMSAAgJQhnmNADFAQASAAgJQhnmNADFAQATAAIJRQokVQBvAAAAAA==.Calteryeker:BAAALgAECgQJBgAAAA==.Camillas:BAAALgAECgcJCgAAAA==.Caosenvy:BAAALgAECgEJAQAAAA==.Caralh:BAAALgAECgEJAgAAAA==.Caroll:BAAALgAECgIJAgAAAA==.Castaldi:BAAALgAECgEJAQABLgAECgYJBwABAAAAAA==.Cathe:BAABLgAECn8VAAIUAAYJIRzySABtAQAUAAYJIRzySABtAQAAAA==.',
Ce='Cernûnnos:BAAALgAFFAIJAgAAAA==.',
Ch='Champdude:BAABLgAECn8vAAIIAAkJwCJ6AgAZAwAIAAkJwCJ6AgAZAwAAAA==.Chankowkwai:BAAALgAECgYJCQAAAA==.Chanë:BAAALgADCgIJAwAAAA==.',
Ci='Citra:BAAALgAECgMJBwAAAA==.',
Co='Coconolose:BAAALgAECgIJBgAAAA==.Cod:BAAALgAECgIJAwAAAA==.Codecks:BAAALgADCgYJBgAAAA==.Coldbringer:BAAALgAECgEJAQAAAA==.Coldhearths:BAAALgAECgUJBgAAAA==.Couro:BAAALgAECgYJCAAAAA==.Cowçadora:BAAALgADCgIJAQAAAA==.',
Cr='Criminøsa:BAAALgAECgEJAQAAAA==.Cristcalad:BAABLgAECn8pAAMVAAgJoRM3EACVAQAVAAgJoRM3EACVAQARAAEJYQULTwAfAAAAAA==.Cryomanta:BAAALgAECgUJBQAAAA==.',
Cu='Cunhaovirado:BAAALgAECgQJBQABLgAFFAQJDQAIANUZAA==.Cunhazinha:BAAALgAECgQJBAAAAA==.Cutia:BAAALgADCgEJAQAAAA==.Cutiesissy:BAAALgAECgQJCAABLgAECgcJGgAGAEoQAA==.',
['Cø']='Cøøkye:BAAALgAECgQJBQAAAA==.',
Da='Daellus:BAAALgADCgUJBQAAAA==.Daemi:BAAALgAECgIJBAAAAA==.Daibodan:BAAALgAECgEJBAAAAA==.Dalaty:BAAALgAECgUJBQAAAA==.Daniilos:BAAALgAECgUJCAAAAA==.Darklara:BAABLgAECn8jAAIWAAgJahntBwCkAQAWAAgJahntBwCkAQAAAA==.Darkove:BAABLgAECn8uAAIQAAkJjBJCOAD2AQAQAAkJjBJCOAD2AQAAAA==.Darrow:BAACLgAFFH8FAAMEAAMJ/xiWBwD4AAAEAAMJrxeWBwD4AAADAAIJhQx6nQCNAAAuAAQKfy0AAwQACQmkI1gBANQCAAMACQnJIrYKAOECAAQACAn7IlgBANQCAAAA.Dartibeccoso:BAAALgADCgcJBwAAAA==.',
De='Deany:BAAALgAECgEJAQAAAA==.Deathinhu:BAABLgAECn81AAIQAAkJVB5KEwCvAgAQAAkJVB5KEwCvAgAAAA==.Deathnacht:BAAALgAECgQJBwAAAA==.Delset:BAAALgADCgIJAgAAAA==.Demojoca:BAAALgADCgkJEAABLgAECgcJDQABAAAAAA==.Dentepodre:BAAALgADCgEJAQAAAA==.Dervus:BAAALgADCgcJBwAAAA==.Devrath:BAAALgAECgEJAQAAAA==.Devyogi:BAAALgADCgcJCAAAAA==.',
Di='Dimeros:BAABLgAECn8bAAINAAgJuQlmKQAqAQANAAgJuQlmKQAqAQAAAA==.Dito:BAAALgADCgEJAQAAAA==.Divano:BAABLgAECn8eAAIXAAgJTRs1DgAkAgAXAAgJTRs1DgAkAgAAAA==.',
Dk='Dkats:BAAALgAECgEJAgAAAA==.',
Dn='Dng:BAAALgAECgcJCAAAAA==.',
Do='Dogowner:BAAALgAECggJEQAAAA==.Donora:BAABLgAECn8jAAMGAAkJkhK8NgDeAQAGAAkJkhK8NgDeAQAFAAEJKAbDQwAVAAAAAA==.',
Dr='Drackmontana:BAABLgAECn8lAAMYAAgJZw4gNgDQAQAYAAgJEQ4gNgDQAQARAAIJEhVBPQBjAAAAAA==.Drafael:BAAALgADCggJDgABLgAECgkJMQAOANsgAA==.Dragoniron:BAAALgADCgEJAQAAAA==.Dragony:BAAALgAECgEJBAAAAA==.Dragunass:BAABLgAECn8iAAMYAAgJxhseEgAZAgAYAAgJOhseEgAZAgARAAYJghX/GAAkAQAAAA==.Dragøndeath:BAAALgADCgEJAgAAAA==.Drakars:BAAALgADCgUJBAAAAA==.Dranarus:BAAALgADCgQJBAAAAA==.Druidblack:BAAALgAECgIJAgAAAA==.Drunkler:BAAALgAECgYJBgAAAA==.Dryter:BAABLgAECn8VAAIIAAcJEA9QKwCEAQAIAAcJEA9QKwCEAQAAAA==.Drákon:BAAALgADCgIJAgAAAA==.',
Du='Dubhe:BAAALgAECgUJDAAAAA==.',
Dy='Dysttopia:BAAALgADCgcJCAAAAA==.',
El='Eldryrin:BAAALgAECgEJAQAAAA==.Elendile:BAAALgAECgEJAQAAAA==.Elinius:BAABLgAECn8qAAMNAAkJgCA2BQDLAgANAAkJgCA2BQDLAgACAAIJUwz9rQAuAAAAAA==.Elistraee:BAAALgADCgcJEAAAAA==.Ellandria:BAAALgAECgMJAwAAAA==.Eloren:BAAALgAECgYJCwABLgAECggJIAAPAPIRAA==.Eluuria:BAAALgAECgkJDQAAAA==.Elyzia:BAAALgAECgEJAQAAAA==.',
En='Endorena:BAAALgADCgEJAQAAAA==.',
Ep='Ephesus:BAAALgADCgIJAgAAAA==.',
Er='Erikssen:BAAALgADCgYJBgAAAA==.Ernest:BAABLgAECn8oAAICAAkJVxb9GQAtAgACAAkJVxb9GQAtAgAAAA==.Erynneus:BAAALgADCgMJAwAAAA==.',
Es='Estagiario:BAAALgAECgIJAQABLgAECgkJIwAJAL0gAA==.',
Ev='Evetts:BAAALgADCgEJAQAAAA==.Evilbarba:BAAALgAECgIJAgAAAA==.',
Ex='Exort:BAAALgAECgYJDwAAAA==.Expressão:BAAALgADCgUJBQAAAA==.',
Fa='Faeldar:BAABLgAECn80AAIZAAkJnxLVDgApAgAZAAkJnxLVDgApAgAAAA==.Faldark:BAAALgADCgkJEQAAAA==.Fandrall:BAAALgAECgUJCAAAAA==.Faris:BAAALgAFFAIJBAAAAA==.Faver:BAAALgADCgcJCAAAAA==.Faölin:BAABLgAECn8ZAAIaAAcJdBi6FgCQAQAaAAcJdBi6FgCQAQAAAA==.',
Fe='Feenigan:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.Feeniä:BAAALgAECgQJBAAAAA==.Ferael:BAABLgAECn8rAAIGAAkJjx9nEACpAgAGAAkJjx9nEACpAgAAAA==.',
Fi='Fil:BAAALgAECgEJAQAAAA==.Firstomega:BAAALgADCgMJAwAAAA==.',
Fl='Flavors:BAABLgAECn8jAAMYAAkJ3SPnAgAPAwAYAAkJ3SPnAgAPAwAVAAQJIR4CFABmAQAAAA==.Florbela:BAAALgAECgUJCAAAAA==.',
Fo='Fogue:BAAALgADCgEJAQAAAA==.Foxthamy:BAABLgAECn8fAAIHAAcJDxIQKABdAQAHAAcJDxIQKABdAQAAAA==.',
Fr='Frachlitzz:BAABLgAECn8wAAIQAAkJChO8NgD8AQAQAAkJChO8NgD8AQAAAA==.Fradem:BAAALgAECgIJAgAAAA==.Freccianera:BAAALgADCgEJAQAAAA==.Fredericc:BAABLgAECn8XAAMbAAgJAg/YOgBiAQAbAAcJiQ3YOgBiAQAcAAcJ2gVYWQDfAAAAAA==.Fredinho:BAAALgADCgEJAQAAAA==.Freyá:BAABLgAECn8bAAIGAAkJ+x8lDQDFAgAGAAkJ+x8lDQDFAgAAAA==.Frs:BAAALgAECgEJAgAAAA==.',
Ga='Galhuda:BAAALgADCgYJBgAAAA==.Galyan:BAAALgADCgEJAQAAAA==.Gandwelf:BAAALgADCgkJCQAAAA==.Gazieri:BAABLgAECn8gAAMPAAgJ8hFkRQBiAQAPAAgJ8hFkRQBiAQAGAAQJCw/z2gDWAAAAAA==.',
Gh='Ghalladriel:BAAALgADCgEJAwAAAA==.Ghruka:BAAALgAECgQJBAAAAA==.',
Gi='Giafar:BAAALgAECgEJAQABLgAECgYJBgABAAAAAA==.',
Gn='Gnomari:BAAALgAECgcJEwAAAA==.',
Go='Gordanado:BAAALgAECgEJAgAAAA==.Gordruida:BAAALgAECgEJAQAAAA==.Govers:BAAALgADCgMJAwABLgAECgMJBAABAAAAAA==.',
Gr='Greyvor:BAAALgADCgEJAQAAAA==.Grumax:BAABLgAECn8UAAIGAAgJyQ/FdACRAQAGAAgJyQ/FdACRAQAAAA==.Grössa:BAABLgAECn8YAAMPAAcJIwgPRwDLAAAPAAcJIwgPRwDLAAAGAAMJCQSXHAE+AAABLgAECgkJEQABAAAAAA==.',
Gu='Guitianki:BAAALgAECgEJAQAAAA==.Gulek:BAAALgAECgMJAwAAAA==.Gussg:BAAALgAECgkJEQAAAA==.Gustavonz:BAAALgADCgcJBwAAAA==.',
['Gö']='Göhan:BAAALgADCgUJBQABLgAECgYJEwABAAAAAA==.',
['Gø']='Gøvers:BAAALgAECgMJBAAAAA==.',
Ha='Handyman:BAAALgADCgYJBgAAAA==.',
Hi='Hildegyth:BAABLgAECn8fAAMIAAgJVxE1MQBhAQAIAAcJWRE1MQBhAQAHAAUJZxEbNwD+AAAAAA==.',
Hj='Hjalmar:BAAALgADCgcJCQAAAA==.',
Ho='Hodtiva:BAABLgAECn8sAAMXAAgJ/g9fIABuAQAXAAgJ/g9fIABuAQAKAAUJDA40OwC8AAAAAA==.Homerz:BAAALgADCgEJAQAAAA==.Hotmojo:BAAALgAECgYJBwAAAA==.',
Hu='Hunfox:BAACLgAFFH8NAAIUAAMJahtpCwAHAQAUAAMJahtpCwAHAQAuAAQKfzgAAhQACQmuIxQEAB4DABQACQmuIxQEAB4DAAAA.',
['Hä']='Härkness:BAAALgAECgEJAQAAAA==.',
['Hü']='Hüskar:BAABLgAECn8ZAAMYAAgJrAvYLQBKAQAYAAgJYAvYLQBKAQAVAAEJCg87UAAwAAAAAA==.',
Ic='Icechips:BAAALgADCgUJBQAAAA==.Ichigoz:BAAALgAECggJEQAAAA==.',
Ih='Ihntwuaed:BAAALgADCgYJCQAAAA==.',
Ik='Ikoo:BAABLgAECn8vAAIZAAkJ1RsyBgDWAgAZAAkJ1RsyBgDWAgAAAA==.',
Il='Illaril:BAACLgAFFH8SAAIWAAQJBBWmAgAbAQAWAAQJBBWmAgAbAQAuAAQKf1gAAhYACQnnH2QCANcCABYACQnnH2QCANcCAAAA.',
In='Indarion:BAAALgADCgYJEQAAAA==.Ingratt:BAAALgAECgEJAQAAAA==.Invisiblelol:BAAALgAECgIJAgAAAA==.',
Ir='Irmãodouther:BAAALgAECgUJBQAAAA==.',
Is='Isebby:BAAALgADCgMJAwAAAA==.',
It='Itzzdan:BAAALgADCgMJAwAAAA==.',
Iv='Ivina:BAABLgAECn8UAAMSAAgJTBbwkQA1AQASAAcJTBbwkQA1AQAdAAIJqRe4HACNAAAAAA==.',
Iz='Izaar:BAAALgAECgQJDAAAAA==.',
Ja='Janaìna:BAAALgAECgMJAwAAAA==.Jangeoffry:BAAALgADCgEJAQAAAA==.',
Jh='Jhonatinha:BAABLgAECn8VAAMGAAcJBxn+nADwAAAGAAYJaxn+nADwAAAPAAQJng69dgCfAAAAAA==.',
Ji='Jigsaww:BAAALgAECgEJAwAAAA==.',
Jo='Joaquim:BAAALgAECgIJAgAAAA==.Jogaveiopl:BAAALgADCgIJAgAAAA==.Joventino:BAAALgADCgQJBQAAAA==.',
Ju='Jucah:BAABLgAECn8ZAAIcAAkJZAsPKABWAQAcAAkJZAsPKABWAQAAAA==.Jullianxd:BAAALgADCgIJAgABLgAECggJFAAeAPsQAA==.',
Ka='Kaallew:BAABLgAECn8XAAIFAAgJ7RgUFgBwAQAFAAgJ7RgUFgBwAQAAAA==.Kaezar:BAAALgADCgEJAQAAAA==.Kainer:BAAALgAECgQJBQAAAA==.Kalazshar:BAAALgAECggJEQAAAA==.Kalelzinho:BAAALgADCgYJBgAAAA==.Kaluss:BAAALgAECgYJBwAAAA==.Kanalet:BAAALgAECgYJCAAAAA==.Kantaa:BAAALgAECgQJCgAAAA==.Kanturu:BAAALgAECgQJBAAAAA==.Karonn:BAABLgAECn8UAAIGAAYJ/A3mlABTAQAGAAYJ/A3mlABTAQAAAA==.Kavartu:BAAALgADCgUJCAAAAA==.',
Ke='Keillor:BAABLgAECn8XAAIbAAYJgBM8PwBPAQAbAAYJgBM8PwBPAQAAAA==.Kelantir:BAAALgAECgYJCQABLgAECgcJCgABAAAAAA==.Keldorian:BAAALgADCgcJEAAAAA==.Kelliar:BAAALgAECgIJAQAAAA==.Kelorn:BAAALgADCgYJBgAAAA==.Kelysa:BAAALgADCgUJBQABLgAECgcJKwARAL4cAA==.Kenzou:BAAALgAECgYJEAAAAA==.',
Kh='Khadi:BAAALgAECgYJCAAAAA==.Khaeltaz:BAAALgAECgMJAwAAAA==.Khalandra:BAABLgAECn8aAAIYAAgJzRtyKwAIAgAYAAgJzRtyKwAIAgAAAA==.Khalel:BAAALgADCgEJAgAAAA==.Khaliq:BAABLgAECn8eAAMJAAkJVhX9CwAFAgAJAAkJVhX9CwAFAgAeAAQJLApxrwCtAAAAAA==.Khallani:BAABLgAECn8aAAIDAAcJ4ghLlQBWAQADAAcJ4ghLlQBWAQAAAA==.Khamul:BAAALgAECgIJAgAAAA==.Khaos:BAAALgAECggJEwAAAA==.Khisto:BAABLgAECn8sAAMQAAgJxxpsOwDqAQAQAAgJxxpsOwDqAQAfAAUJsxdABABVAQAAAA==.Khroriggs:BAAALgAECgYJDQABLgAECgcJBwABAAAAAA==.',
Ki='Killerbiie:BAAALgADCgIJAgAAAA==.Killerdown:BAAALgADCgIJAgAAAA==.Kimashi:BAAALgAECgUJBQAAAA==.Kindie:BAAALgADCgcJCwABLgAECggJFAAeABAIAA==.Kissme:BAABLgAECn8YAAMNAAkJlA+1IABnAQANAAgJ9hC1IABnAQAMAAEJ4wVzQwAqAAAAAA==.Kitamor:BAABLgAECn8sAAINAAkJXAZiLQASAQANAAkJXAZiLQASAQAAAA==.Kiya:BAAALgADCgcJHgAAAA==.',
Ko='Koriakin:BAAALgAECgcJEgAAAA==.Kosmo:BAAALgAECgQJBAAAAA==.Kotalkhan:BAAALgADCgkJEQAAAA==.',
Kr='Krov:BAAALgAECgEJAQAAAA==.Kryon:BAAALgAECgYJDgAAAA==.Kryzthor:BAAALgAECgYJCAAAAA==.Kräsus:BAABLgAECn8xAAIRAAkJfyWwAABXAwARAAkJfyWwAABXAwAAAA==.',
Ku='Kul:BAAALgAECgMJAwAAAA==.Kuroelf:BAAALgAECgMJAwAAAA==.Kuthila:BAAALgADCgIJAgAAAA==.',
Ky='Kyzaru:BAAALgAECgEJAQAAAA==.',
['Kÿ']='Kÿdou:BAAALgAECgcJDgAAAA==.',
La='Ladrion:BAABLgAECn80AAMgAAkJYxvhAgBTAgAgAAkJ9hfhAgBTAgAaAAkJAxkzDwDpAQAAAA==.Laetus:BAAALgAECgUJEQAAAA==.Lagosta:BAAALgAECgMJBgAAAA==.Laiany:BAABLgAECn8zAAIKAAkJSiF7AgBGAwAKAAkJSiF7AgBGAwAAAA==.Lani:BAAALgAECgEJAQAAAA==.',
Le='Legacia:BAAALgADCgYJBgAAAA==.Lekrom:BAAALgADCgYJBgAAAA==.Lequinhö:BAAALgAECgIJAgAAAA==.Leric:BAAALgADCgcJCgAAAA==.Lethmar:BAABLgAECn8aAAISAAcJMhdqQQCZAQASAAcJMhdqQQCZAQAAAA==.Leyana:BAAALgAECgUJBQAAAA==.',
Lh='Lhwei:BAAALgAECgIJAgABLgAECgkJJAAHAD8fAA==.',
Li='Liandra:BAAALgAECgEJAQAAAA==.Licaon:BAAALgADCgYJCwAAAA==.Lichkiller:BAAALgAECgIJAgAAAA==.Lightbreaker:BAABLgAECn8jAAIGAAkJZAg/WQB2AQAGAAkJZAg/WQB2AQAAAA==.Lihr:BAAALgADCgYJCQAAAA==.Lilianpotter:BAAALgAECgEJAQAAAA==.Lilithrix:BAAALgADCgIJAgAAAA==.Lillit:BAABLgAECn8pAAQdAAgJdA0NCgBRAQASAAgJ+wvIUgBlAQAdAAgJ1goNCgBRAQATAAIJvwYZLAA+AAAAAA==.Lindaah:BAABLgAECn8gAAMIAAgJVRVNGQCWAQAIAAgJVRVNGQCWAQAHAAYJtgOtTACaAAAAAA==.Lindademon:BAAALgAECgQJBQAAAA==.Lindahealer:BAAALgAECgEJAgABLgAECgQJBQABAAAAAA==.Lislfox:BAABLgAECn8xAAIMAAkJ4hbKBwAQAgAMAAkJ4hbKBwAQAgAAAA==.Lithlad:BAAALgADCgIJAgAAAA==.',
Lk='Lkinho:BAAALgAECgMJBAAAAA==.',
Lm='Lmmds:BAAALgADCgYJDwAAAA==.',
Lo='Lockynha:BAAALgADCgEJAQAAAA==.Loohynir:BAAALgAFFAIJAgAAAA==.Lotusbird:BAAALgADCgcJBwAAAA==.',
Lu='Luccyah:BAAALgADCgkJCQAAAA==.Lucileia:BAAALgADCgEJAQAAAA==.Lukazgplay:BAAALgADCgIJAgAAAA==.Lutsul:BAAALgAECgEJAQAAAA==.',
Ly='Lylka:BAABLgAECn8xAAIFAAkJlSSJAABIAwAFAAkJlSSJAABIAwAAAA==.Lyrrena:BAAALgAECgMJAwAAAA==.',
Ma='Macumbadora:BAAALgAECgQJCQAAAA==.Madfulock:BAAALgAECgYJDQAAAA==.Maeghann:BAAALgADCgMJAwAAAA==.Magraver:BAAALgADCgUJCAAAAA==.Mais:BAAALgADCgMJBQAAAA==.Malewolyyc:BAACLgAFFH8GAAIKAAIJyR5RFwCxAAAKAAIJyR5RFwCxAAAuAAQKfyYAAwoACAk/I9gGAMICAAoACAk/I9gGAMICABcAAwmJEJ5BALAAAAAA.Malhun:BAAALgADCgUJDgAAAA==.Malphan:BAAALgAECgcJBwAAAA==.Malyguz:BAACLgAFFH8QAAIQAAQJBhC+QAA5AQAQAAQJBhC+QAA5AQAuAAQKfxkAAhAABwldG+BgABkCABAABwldG+BgABkCAAAA.Malévolatity:BAAALgADCgEJAQAAAA==.Manipullador:BAAALgAECgIJAgAAAA==.Mapussauro:BAAALgAECgcJEQAAAA==.Maradi:BAAALgADCgIJAgAAAA==.Mariob:BAAALgAECgQJCAAAAA==.Marjøly:BAAALgAECgEJAQAAAA==.Markson:BAAALgADCgEJAQAAAA==.Massafera:BAABLgAECn8fAAIGAAkJMhOWOADXAQAGAAkJMhOWOADXAQAAAA==.Mathfacbruxo:BAABLgAECn8wAAISAAkJGRr1FgBhAgASAAkJGRr1FgBhAgAAAA==.Mauritiuz:BAAALgAECgYJDQAAAA==.Mayanyy:BAAALgADCgYJBgAAAA==.',
Mc='Mcq:BAAALgADCgUJBQAAAA==.',
Md='Mdrdark:BAACLgAFFH8HAAIDAAMJbBRWXAD4AAADAAMJbBRWXAD4AAAuAAQKfy0AAwMACQmiGfgdAFACAAMACQmiGfgdAFACACEAAwm/FeMzAHcAAAAA.',
Me='Medz:BAABLgAECn8jAAIQAAkJlRoBHgBtAgAQAAkJlRoBHgBtAgAAAA==.Meedea:BAAALgADCgUJBgAAAA==.Meetjack:BAAALgADCgIJAgAAAA==.Melania:BAAALgAECgEJAgAAAA==.Melissandra:BAAALgAFFAEJAQAAAA==.Mellkor:BAABLgAECn8jAAIJAAgJxhvfCgAZAgAJAAgJxhvfCgAZAgAAAA==.Melytah:BAAALgAECgEJAgAAAA==.Melzynhaa:BAAALgAECgEJAQABLgAECggJIAAIAFUVAA==.Meraxxes:BAAALgADCgYJBgAAAA==.Merellien:BAAALgADCggJDgAAAA==.Metamorful:BAABLgAECn8UAAICAAgJVhP/SQB7AQACAAgJVhP/SQB7AQAAAA==.',
Mh='Mhorgann:BAAALgAECgUJBgAAAA==.',
Mi='Mijonakombi:BAABLgAECn8WAAIGAAkJ/hp2GQBrAgAGAAkJ/hp2GQBrAgAAAA==.Mikveh:BAAALgAECgQJBAAAAA==.Milim:BAABLgAECn8mAAMLAAkJqxLeGADAAQALAAkJvxHeGADAAQAiAAgJMAuDHgA6AQAAAA==.Milliidan:BAAALgADCgUJBQAAAA==.Mindrathys:BAAALgAECgEJAQAAAA==.Mithrius:BAABLgAECn8UAAIGAAgJawsDhAAcAQAGAAgJawsDhAAcAQAAAA==.',
Ml='Mls:BAAALgADCgYJCwAAAA==.',
Mo='Mogrus:BAAALgADCgMJAwAAAA==.Mohanna:BAAALgAECgcJDAAAAA==.Mohanninha:BAAALgAECgYJCwAAAA==.Mohotok:BAABLgAECn8vAAIGAAkJRBi6IQA6AgAGAAkJRBi6IQA6AgAAAA==.Moonøvesso:BAAALgAECgEJAgAAAA==.Moopp:BAAALgADCgIJAgAAAA==.Mortixxia:BAABLgAECn8ZAAITAAYJzxnhCABrAQATAAYJzxnhCABrAQAAAA==.',
Mu='Muata:BAAALgAECgYJDwAAAA==.Mupar:BAAALgADCgIJAgAAAA==.Murano:BAABLgAECn8qAAMYAAgJfRywEgAUAgAYAAgJfRywEgAUAgAVAAMJywo7NQCMAAAAAA==.Muzzo:BAAALgADCgYJCwABLgAECgUJCgABAAAAAA==.',
My='Myrmïdom:BAAALgAECgIJAgAAAA==.Myzoreh:BAAALgADCgEJAQAAAA==.',
['Má']='Mágico:BAAALgAECgEJAwAAAA==.Máia:BAAALgAFFAEJAQAAAA==.',
['Mä']='Mändosz:BAABLgAECn8ZAAMDAAkJMRIeSgCcAQADAAgJahIeSgCcAQAEAAMJCRDKEwC8AAAAAA==.',
['Mé']='Ménace:BAAALgAFFAIJAgAAAA==.',
Na='Nalathiel:BAAALgAECgYJDAAAAA==.Narancia:BAAALgAECgYJBwAAAA==.Nassur:BAAALgADCgEJAQAAAA==.Nattaliaa:BAAALgAECgEJAQAAAA==.Nazdru:BAAALgADCgMJAwABLgAECgkJMQAOANsgAA==.Nazzh:BAAALgAECgEJAQAAAA==.',
Ne='Necronx:BAAALgAECgEJAQAAAA==.Necronxd:BAAALgADCgEJAgAAAA==.Nefas:BAABLgAECn8dAAITAAkJKxExBgCsAQATAAkJKxExBgCsAQAAAA==.Nefazo:BAAALgAECgcJCgAAAA==.Nefilo:BAAALgADCgYJEAAAAA==.Nepthunus:BAABLgAECn8tAAIfAAkJGxhFAQBLAgAfAAkJGxhFAQBLAgAAAA==.Nermand:BAAALgAECgEJAQAAAA==.Neshula:BAAALgADCgMJAwAAAA==.Neuvosor:BAAALgAECgEJAQAAAA==.',
Ni='Nibelunga:BAAALgADCgYJBgAAAA==.Nijor:BAAALgADCgYJBgAAAA==.',
No='Nobelnaga:BAAALgAECgMJAwAAAA==.',
Ny='Nyxra:BAAALgADCgcJEAAAAA==.',
['Nö']='Nöirr:BAAALgADCgUJBQAAAA==.',
Oc='Ocelotte:BAAALgADCgEJAQAAAA==.',
Oi='Oioimiguel:BAAALgADCgUJBQAAAA==.',
Ol='Olhua:BAAALgAECgIJAgAAAA==.Oljedvlad:BAAALgADCgEJAQAAAA==.Oluss:BAAALgADCgUJBQABLgAFFAMJDQAUAGobAA==.',
Om='Omnath:BAAALgADCgYJBgAAAA==.',
Or='Orillan:BAABLgAECn8yAAMJAAgJdBj3DQDhAQAJAAgJdBj3DQDhAQAeAAEJhAcY5gAsAAAAAA==.Ornsteinsnow:BAABLgAECn8ZAAIPAAkJvhTOEQA6AgAPAAkJvhTOEQA6AgAAAA==.Orob:BAAALgAECgEJAQAAAA==.Ororah:BAAALgAECgUJCQAAAA==.Orukam:BAABLgAECn8XAAMCAAgJ7BRKNACCAQACAAgJ7BRKNACCAQANAAIJ5ginWgBSAAAAAA==.',
Os='Oszwald:BAAALgADCgEJAQAAAA==.',
['Oú']='Oúkürä:BAAALgAECgYJCgAAAA==.',
Pa='Padawani:BAAALgAECgIJAgAAAA==.Padgodeira:BAAALgAECgQJBAAAAA==.Padrealpha:BAAALgADCgcJCgAAAA==.Padrekelmøn:BAAALgAECgQJBAAAAA==.Palaha:BAAALgADCgEJAQABLgAFFAMJDQAUAGobAA==.Palatina:BAAALgADCgIJAgAAAA==.Palazzy:BAAALgAECgEJAQAAAA==.Panena:BAAALgAECgIJAwAAAA==.Pangedrey:BAABLgAECn80AAIIAAkJNx6tBwCIAgAIAAkJNx6tBwCIAgAAAA==.Paracepatrol:BAAALgAECgQJAwAAAA==.Parcival:BAACLgAFFH8FAAIUAAMJUA5OOADkAAAUAAMJUA5OOADkAAAuAAQKfxcAAhQACQl1G8ASAKECABQACQl1G8ASAKECAAAA.Parký:BAAALgAECgYJBgAAAA==.Pattalógika:BAAALgAECgEJAQAAAA==.Paullk:BAABLgAECn8gAAINAAYJchSlKgAjAQANAAYJchSlKgAjAQAAAA==.',
Pe='Pedrinho:BAAALgADCgYJBgABLgAFFAQJCQAeAJMfAA==.Penéllope:BAAALgAECgEJAQAAAA==.Persëphone:BAABLgAECn8VAAMKAAcJsBQuLwAMAQAKAAUJxxAuLwAMAQAXAAYJCBLMQAC0AAAAAA==.Peruchi:BAAALgAECgQJBAAAAA==.',
Pg='Pgms:BAAALgADCgYJCgAAAA==.',
Ph='Phaxe:BAAALgADCgIJAgAAAA==.Phoenicx:BAAALgADCgMJBgAAAA==.',
Pi='Pipelinebr:BAAALgAECgUJBQAAAA==.',
Pp='Pp:BAABLgAFFH8FAAQKAAMJ+wUkKQAuAAAKAAEJ6wAkKQAuAAAXAAEJZACcKgAsAAAZAAEJSQByNAAgAAAAAA==.',
Pr='Prometeus:BAAALgAECgUJCgAAAA==.Pryon:BAAALgAECgUJCwAAAA==.',
['Pä']='Pändero:BAAALgAFFAEJAQAAAA==.Pänqueca:BAAALgAECgEJAgAAAA==.',
['Pé']='Pénacova:BAAALgADCgEJAQAAAA==.',
['Pî']='Pîo:BAABLgAECn8XAAMQAAgJbRnkQwDOAQAQAAgJeRjkQwDOAQAjAAQJ0xjwCgAsAQAAAA==.',
Qu='Quejerok:BAAALgAECgYJDQAAAA==.',
Ra='Radunz:BAABLgAECn8xAAIOAAkJ2yCTAQDxAgAOAAkJ2yCTAQDxAgAAAA==.Raineko:BAAALgADCgYJBgAAAA==.Raio:BAACLgAFFH8FAAIQAAIJlRPEcAClAAAQAAIJlRPEcAClAAAuAAQKfycAAhAACQm+Hu4UAKUCABAACQm+Hu4UAKUCAAAA.Ralfwur:BAAALgAECgQJBwAAAA==.Rargsa:BAAALgAECgcJDgAAAA==.Rariel:BAAALgADCgMJAgAAAA==.Rasmon:BAABLgAECn8sAAISAAgJ1RRQQACdAQASAAgJ1RRQQACdAQAAAA==.Ravendreth:BAAALgADCgEJAQAAAA==.Raykarla:BAAALgAECgIJAwAAAA==.Raymain:BAABLgAECn8iAAMHAAkJzxVBJQBxAQAHAAgJTxRBJQBxAQAIAAcJFxadJwAnAQAAAA==.Raíka:BAAALgAECgUJBQAAAA==.',
Re='Reddnose:BAAALgAECgUJCQAAAA==.Reinhold:BAAALgAECgUJBwAAAA==.',
Ri='Ricktdai:BAAALgAECgEJAQAAAA==.Riesze:BAABLgAECn8dAAIUAAkJ7xV8HQAnAgAUAAkJ7xV8HQAnAgAAAA==.',
Ro='Roguinhu:BAAALgAECgEJAQAAAA==.Ropaoo:BAAALgAECgMJCQAAAA==.',
Ru='Rua:BAAALgAECgQJBAAAAA==.Rusga:BAAALgADCgEJAQAAAA==.Rustovick:BAAALgAECgMJBQAAAA==.',
Ry='Rytheas:BAAALgAECgQJBAAAAA==.',
['Rä']='Rämzä:BAAALgAECgYJEwAAAA==.',
['Rå']='Råy:BAAALgAECgQJBgAAAA==.',
Sa='Saargeras:BAAALgADCgMJAwAAAA==.Saffír:BAABLgAECn8eAAIGAAgJ1hZRNgDfAQAGAAgJ1hZRNgDfAQAAAA==.Saiden:BAAALgADCgQJBAAAAA==.Saintkaue:BAAALgADCgIJAgAAAA==.Samalandraa:BAAALgADCgEJAQAAAA==.Sanahh:BAAALgAECgYJCAAAAA==.Sanateia:BAAALgADCgYJCwAAAA==.Santamadre:BAAALgADCgEJAQAAAA==.Sapekinhä:BAABLgAECn8jAAMJAAkJvSB+BQCcAgAJAAgJNCJ+BQCcAgAWAAIJUhhAGQCGAAAAAA==.Saphirah:BAAALgADCgEJAQAAAA==.Satanvitória:BAABLgAECn8uAAMVAAgJ7B4BBwA5AgAVAAgJbh4BBwA5AgAYAAcJYRo0JgAoAgAAAA==.',
Sc='Scheiren:BAAALgAECgMJAwAAAA==.',
Se='Senegos:BAAALgADCgcJBwAAAA==.Sereiaa:BAABLgAECn8bAAIUAAYJAg6paQATAQAUAAYJAg6paQATAQAAAA==.Sesiom:BAAALgAECgcJBgAAAA==.',
Sh='Shalltearr:BAAALgADCgEJAQAAAA==.Shamate:BAAALgAECgMJBAAAAA==.Shanoa:BAAALgAECgMJAwAAAA==.Sharpersong:BAAALgADCgcJBgAAAA==.Shedo:BAABLgAECn8VAAMVAAgJAxoUDgCxAQAVAAcJtxkUDgCxAQAYAAYJWg+VYgAoAQAAAA==.Sheevane:BAABLgAECn8eAAICAAkJmRebGgAoAgACAAkJmRebGgAoAgAAAA==.Shinzo:BAAALgADCgEJAQAAAA==.Shonja:BAAALgADCgcJDgAAAA==.Shula:BAAALgADCgcJDQAAAA==.Shÿnara:BAAALgAECgkJDwAAAA==.',
Si='Siclop:BAAALgADCgYJBgAAAA==.Silgris:BAAALgAECgEJAQABLgAECggJIAAPAPIRAA==.Silmeria:BAAALgAECgcJDgAAAA==.Silverchain:BAAALgADCgcJCgAAAA==.Sinton:BAAALgAECgMJBAAAAA==.',
Sk='Skeletowman:BAAALgADCgEJAQAAAA==.Skineh:BAAALgAECgMJAwAAAA==.Skinme:BAABLgAECn8UAAIHAAYJKwSZUACKAAAHAAYJKwSZUACKAAAAAA==.',
Sm='Smylf:BAAALgAECggJDwAAAA==.',
So='Sombrea:BAAALgAECgQJCAAAAA==.',
Sp='Spectrø:BAAALgAECgYJBgAAAA==.',
Sr='Srheal:BAAALgAECgQJBAAAAA==.Srsapo:BAAALgAECgMJBgAAAA==.',
St='Stampede:BAAALgADCgMJAwAAAA==.Starian:BAABLgAECn8gAAMCAAcJKRzKGgAnAgACAAcJKRzKGgAnAgANAAEJywwTfwAzAAAAAA==.Stëlla:BAABLgAECn8iAAIbAAcJahIZNwB0AQAbAAcJahIZNwB0AQAAAA==.',
Su='Sunnara:BAACLgAFFH8JAAIeAAQJkx/gFgB1AQAeAAQJkx/gFgB1AQAuAAQKfyIAAh4ACQnwIV0FAAYDAB4ACQnwIV0FAAYDAAAA.Superkx:BAAALgAECgQJBQAAAA==.Suzanomu:BAAALgADCgYJCwAAAA==.',
Sy='Sylran:BAAALgADCgQJBgAAAA==.Synk:BAAALgADCgQJBAAAAA==.Syofra:BAAALgAECgQJBQAAAA==.Syrelys:BAAALgADCgYJBgAAAA==.Syuon:BAABLgAECn8kAAIHAAkJPx+hBAASAwAHAAkJPx+hBAASAwAAAA==.',
['Së']='Sëkhmet:BAAALgAECgYJCwAAAA==.',
['Sï']='Sïmbä:BAABLgAECn8VAAMDAAgJcw95ngBEAQADAAgJcw95ngBEAQAEAAEJkAShGQAoAAAAAA==.',
['Sÿ']='Sÿkies:BAAALgADCgEJAQAAAA==.',
Ta='Talandar:BAABLgAECn8tAAINAAkJMBfwDwAQAgANAAkJMBfwDwAQAgAAAA==.Tankudo:BAABLgAECn8WAAIDAAYJVhQVjQABAQADAAYJVhQVjQABAQAAAA==.Tanthallas:BAAALgAECgEJAQAAAA==.Tavindapedra:BAAALgAECgYJCwAAAA==.',
Tc='Tchutchuco:BAAALgAECgIJAwAAAA==.',
Te='Tekzero:BAAALgAECgEJBwAAAA==.Tempestus:BAAALgADCgYJBgAAAA==.Tennebra:BAAALgADCgYJCAAAAA==.Teobaldo:BAAALgADCgYJCgAAAA==.Terron:BAABLgAECn8mAAIbAAcJiRemJwDIAQAbAAcJiRemJwDIAQAAAA==.',
Th='Thabitah:BAABLgAECn8uAAIXAAkJ/xrGCAB8AgAXAAkJ/xrGCAB8AgAAAA==.Thaliath:BAAALgADCgQJBAAAAA==.Thallariel:BAAALgAECgEJAQAAAA==.Theteo:BAABLgAECn8ZAAIGAAkJZQtHVQCAAQAGAAkJZQtHVQCAAQAAAA==.Thiberios:BAAALgAECgUJDAAAAA==.Thirros:BAAALgADCgUJBQAAAA==.Thorres:BAAALgAECgIJAgAAAA==.Thotamon:BAAALgAECgQJCAAAAA==.Thràain:BAAALgAECgcJDQAAAA==.Thuki:BAAALgADCgYJDAAAAA==.Thunderblade:BAAALgAECgYJDgAAAA==.Théus:BAAALgAECgMJAwABLgAFFAIJAgABAAAAAA==.',
Ti='Tiramisu:BAAALgAECgEJAgABLgAECgYJBwABAAAAAA==.',
To='Toucinho:BAAALgAECgYJDgAAAA==.',
Tr='Traydd:BAABLgAECn8UAAIOAAcJ2gi5FQAEAQAOAAcJ2gi5FQAEAQAAAA==.Trollando:BAAALgAECgUJCAAAAA==.',
Tu='Tuga:BAAALgADCgMJAwAAAA==.Turokk:BAABLgAECn8bAAIUAAgJTA8yQACLAQAUAAgJTA8yQACLAQAAAA==.',
Tw='Twilight:BAAALgADCgYJDQAAAA==.Twylluch:BAAALgADCgQJBgABLgAECgkJJQAPAOsXAA==.',
Ul='Ulhim:BAAALgADCgcJEwAAAA==.',
Ur='Uriuri:BAAALgADCgYJBgABLgAECgkJMQAOANsgAA==.',
Us='Usfull:BAABLgAECn8wAAMKAAkJ4BDwHACVAQAKAAgJ/RHwHACVAQAXAAgJ8gq+IgBbAQAAAA==.',
Va='Vacavelha:BAAALgAECgEJAQAAAA==.Vahtorn:BAAALgAECgMJBgAAAA==.Valaerys:BAAALgAECgQJBQAAAA==.Valaniri:BAAALgADCgEJAQAAAA==.Vanyathariel:BAAALgADCgYJAwAAAA==.Vareena:BAAALgADCggJCAABLgAECgkJMQARAH8lAA==.Vashiel:BAAALgADCgIJAgAAAA==.',
Ve='Vehuiáh:BAABLgAECn8ZAAMPAAgJMB2BEwApAgAPAAgJMB2BEwApAgAGAAEJRQRoSwEpAAAAAA==.Velen:BAABLgAECn8aAAIDAAcJshCcZABUAQADAAcJshCcZABUAQAAAA==.Vellkor:BAAALgADCgYJBgAAAA==.Vellon:BAAALgADCgEJAQAAAA==.Venusa:BAAALgADCgMJBAAAAA==.Verno:BAAALgADCgcJCwAAAA==.Verzuk:BAAALgAECgYJEgAAAA==.',
Vi='Vidnands:BAAALgAECgEJAQAAAA==.Viinyy:BAAALgAECgIJAgAAAA==.Vilthor:BAAALgAECgUJBQAAAA==.Vintekilo:BAABLgAECn8WAAIGAAgJ9xeiYgC9AQAGAAgJ9xeiYgC9AQAAAA==.',
Vo='Voiddh:BAAALgAECgcJDAAAAA==.Vokeshar:BAAALgADCgUJBQAAAA==.Voltadupla:BAAALgAECgQJBQAAAA==.Voop:BAAALgADCgYJFAAAAA==.',
Vr='Vrenshrrgn:BAAALgADCgYJBgAAAA==.',
Vy='Vygh:BAACLgAFFH8JAAISAAMJmBVtSgDqAAASAAMJmBVtSgDqAAAuAAQKfyUAAxIACQnoHvYNAKoCABIACQnoHvYNAKoCABMAAQkjDzpwADYAAAAA.Vyndrill:BAAALgAECgYJDQAAAA==.',
['Vä']='Välion:BAAALgADCgIJAgAAAA==.',
Wa='Wacom:BAAALgADCgUJBQAAAA==.Walkers:BAAALgAECgUJBAAAAA==.Warlaka:BAAALgADCgYJBgAAAA==.Warpiel:BAAALgADCgcJDAABLgAECgkJHgAZAC0OAA==.Watchtower:BAAALgADCgYJDgAAAA==.',
Wh='Wheez:BAAALgAECgQJBAABLgAECggJLAAQAMcaAA==.',
Wi='Williem:BAAALgADCgYJEwAAAA==.',
Wo='Worthy:BAAALgADCgQJBAAAAA==.',
Xa='Xafado:BAAALgAECgEJAQAAAA==.Xamalandrö:BAAALgAECgQJCwAAAA==.',
Xe='Xehagus:BAAALgADCgcJCgAAAA==.',
Xi='Xiblaublum:BAAALgADCgMJAwAAAA==.Xiquimiro:BAAALgADCgQJBAAAAA==.',
Xx='Xximperadorx:BAAALgADCgIJAgAAAA==.',
Ya='Yasuoh:BAAALgAECgQJCAAAAA==.',
Ye='Yewner:BAAALgADCgYJBQAAAA==.',
Yi='Yingsu:BAABLgAECn8XAAIkAAgJ0SDEEwBzAgAkAAgJ0SDEEwBzAgAAAA==.',
Yo='Yoshihime:BAAALgAECgIJAgABLgAECgkJHgACAJkXAA==.',
Yv='Yvin:BAAALgAECgMJAwAAAA==.',
Za='Zallmo:BAAALgAFFAEJAQAAAA==.Zarath:BAAALgAECgUJBgAAAA==.Zawarudo:BAAALgAECgQJCAAAAA==.',
Ze='Zedd:BAAALgAFFAIJAgAAAA==.Zenorclord:BAAALgADCgQJBgAAAA==.Zeytona:BAABLgAECn8jAAIkAAkJjAtdHACFAQAkAAkJjAtdHACFAQAAAA==.',
Zi='Ziracruz:BAAALgAECgQJCwAAAA==.',
['Zí']='Zíngara:BAAALgAECgEJAQAAAA==.',
['Ár']='Árÿä:BAABLgAECn8xAAIUAAkJIhIvKQDpAQAUAAkJIhIvKQDpAQAAAA==.',
['Är']='Äraxy:BAAALgAECgMJBgAAAA==.',
['Äy']='Äy:BAAALgADCgYJCwAAAA==.',
['Ém']='Émtocremoso:BAAALgADCgMJAwAAAA==.',
['Ðh']='Ðh:BAAALgADCgkJEQAAAA==.',
['Øv']='Øvesso:BAAALgAECggJEQAAAA==.',
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
