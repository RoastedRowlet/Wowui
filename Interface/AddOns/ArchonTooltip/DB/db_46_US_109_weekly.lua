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

local lookup = {'Priest-Shadow','Druid-Restoration','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Unholy','Warrior-Arms','DeathKnight-Frost','DeathKnight-Blood','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Druid-Guardian','Druid-Balance','Evoker-Augmentation','Unknown-Unknown','Warrior-Fury','DemonHunter-Devourer','Paladin-Holy','Mage-Frost','Warrior-Protection','Priest-Discipline','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Monk-Brewmaster','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Hunter-Survival','Hunter-Marksmanship','Mage-Fire','Shaman-Enhancement','Rogue-Outlaw','Rogue-Assassination','Mage-Arcane','Evoker-Devastation','Evoker-Preservation',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=46,date='2026-08-04',data={Ab='Abelao:BAAALgAECgcJEwAAAA==.',
Ad='Adelaide:BAAALgAECgIJAgABLgAFFAkJMAABAD8ZAA==.Adoramuss:BAAALgAECgYJCwAAAA==.Adrianoj:BAAALgAECgEJAQABLgAFFAIJBQACAD0RAA==.',
Ae='Aeklug:BAAALgAECgIJAgAAAA==.Aelon:BAAALgADCgcJDAAAAA==.Aelthor:BAABLgAECn8WAAIDAAQJ3BGbBwDFAAADAAQJ3BGbBwDFAAAAAA==.Aemeath:BAABLgAECn8XAAMEAAkJiyHXAQD8AgAEAAkJiyHXAQD8AgAFAAIJnhgCSgCOAAAAAA==.Aenthür:BAAALgAECgEJAQAAAA==.',
Ah='Ahammes:BAAALgAECgQJBAABLgAECgcJHwAGAIAJAA==.Ahmus:BAAALgAECgUJDAAAAA==.Ahrallu:BAAALgADCgEJAgAAAA==.',
Ai='Aioliavictus:BAAALgAECgEJAQAAAA==.',
Ak='Akaynu:BAAALgAECgEJAQAAAA==.',
Al='Alanie:BAAALgAECgUJDQABLgAFFAIJBgAHAOkPAA==.Aldranir:BAAALgADCgEJAQAAAA==.Alessaxd:BAACLgAFFH8NAAIGAAMJHA3GSwDAAAAGAAMJHA3GSwDAAAAuAAQKfzEABAYACQkuF7k6ABUCAAYACQmNFrk6ABUCAAgABwl+FHwTAEMBAAkAAglLBkAcABsAAAAA.Alexa:BAAALgAECgQJBAAAAA==.Alfajhor:BAABLgAECn86AAMKAAgJFx+6EAC5AQAKAAYJoyK6EAC5AQALAAgJZx0KYgCsAQAAAA==.Alfajhòr:BAAALgAECgIJAgAAAA==.Alfajhôr:BAAALgAECgUJBwAAAA==.Alkarin:BAAALgAECgEJAwAAAA==.Allandriel:BAAALgAECgQJBAAAAA==.Alldarion:BAAALgAECgMJCQAAAA==.Allendra:BAAALgADCgcJCQAAAA==.Alleriane:BAACLgAFFH8GAAIMAAIJOherSACDAAAMAAIJOherSACDAAAuAAQKfz8AAwwACQlEH7UIABADAAwACQlEH7UIABADAA0AAQmnApGNABgAAAAA.Allerios:BAAALgAECgUJCQAAAA==.Allone:BAACLgAFFH8HAAIFAAMJCQeMEgCYAAAFAAMJCQeMEgCYAAAuAAQKfyQAAgUACAlJEqUpADABAAUACAlJEqUpADABAAAA.Allyhra:BAAALgADCgQJBAAAAA==.Allëria:BAAALgADCgMJAwAAAA==.Alruna:BAAALgAECgEJAQAAAA==.',
Am='Ametnys:BAAALgAECgUJEAAAAA==.Amonhar:BAAALgAECgQJBQABLgAECgkJOwAOAB4SAA==.Amyn:BAAALgADCgYJBwAAAA==.',
An='Anakata:BAABLgAECn8cAAQPAAYJ3RVhLAD+AAAPAAYJ3RVhLAD+AAACAAIJ+wW80QAzAAAQAAEJww8qjgAyAAAAAA==.Anakinini:BAACLgAFFH8FAAIRAAIJFgHzYwBDAAARAAIJFgHzYwBDAAAuAAQKfyIAAhEACAlsCTVEABkBABEACAlsCTVEABkBAAEuAAQKBgkMABIAAAAA.Analia:BAABLgAECn8lAAQCAAgJFR5/HgBLAgACAAcJVR1/HgBLAgAPAAgJnQgHOADGAAAQAAUJxhuzEgCWAAABLgAFFAIJBgAHAOkPAA==.Andaliz:BAACLgAFFH8SAAILAAMJwSbAMABQAQALAAMJwSbAMABQAQAuAAQKfzcAAgsACQkLJjIDAGcDAAsACQkLJjIDAGcDAAEuAAUUBQkGAAsAWhcA.Andorith:BAAALgAECgEJAgAAAA==.Anelie:BAAALgAECgQJDQABLgAFFAIJBgAHAOkPAA==.Annhe:BAAALgAECgEJAQAAAA==.Ansalon:BAAALgADCgYJBwAAAA==.Anthorus:BAAALgAECgUJBgAAAA==.Antonellaes:BAAALgAECgUJCgABLgAECgcJDgASAAAAAA==.',
Ao='Aoiisuu:BAAALgADCgYJCAAAAA==.',
Ap='Apodrecido:BAAALgAECgYJBgAAAA==.Apoxus:BAAALgADCgIJAgAAAA==.',
Ar='Arajakata:BAAALgAECgEJBgAAAA==.Arctorius:BAABLgAECn8WAAILAAcJbQ8IpwAtAQALAAcJbQ8IpwAtAQAAAA==.Arethiel:BAAALgADCgYJBgAAAA==.Arlandriah:BAAALgADCgYJCQABLgAECgYJGAALABAYAA==.Aronys:BAAALgADCgcJBwAAAA==.Artronis:BAACLgAFFH8JAAIPAAQJCwthHACuAAAPAAQJCwthHACuAAAuAAQKfycAAw8ACQluFxwVAKwBAA8ACAlPFhwVAKwBAAMAAgnFGYUOAFoAAAAA.Artånis:BAAALgAECgcJDAAAAA==.Arukäi:BAABLgAECn8VAAITAAkJ8A90BQCbAQATAAkJ8A90BQCbAQAAAA==.Aruthuro:BAAALgAECgYJEgAAAA==.Arwenidril:BAAALgAECgEJAQAAAA==.',
As='Ashbörn:BAAALgAECgQJCAAAAA==.Astel:BAABLgAECn8mAAIUAAkJUxYXBQDTAQAUAAkJUxYXBQDTAQAAAA==.',
At='Atriuz:BAABLgAECn8bAAIVAAYJahouLwDGAQAVAAYJahouLwDGAQAAAA==.Ats:BAAALgAECgUJCgAAAA==.',
Ay='Aykho:BAABLgAECn8nAAIWAAgJRRY7aACsAQAWAAgJRRY7aACsAQAAAA==.',
Az='Azurion:BAAALgAECgYJCgAAAA==.',
['Aÿ']='Aÿ:BAAALgAECgMJBAAAAA==.',
Ba='Baguh:BAAALgADCggJCAAAAA==.Bagunça:BAAALgADCgYJBgAAAA==.Bakuugou:BAAALgAECgMJCgAAAA==.Balk:BAAALgAFFAIJAwAAAA==.Balthar:BAAALgAFFAIJAgAAAA==.Bambur:BAAALgADCgMJAwAAAA==.Barbabruto:BAABLgAECn8+AAIXAAkJZx5uBwCMAgAXAAkJZx5uBwCMAgAAAA==.Basilisco:BAAALgAECgEJAQAAAA==.',
Be='Belleg:BAAALgAECgEJAgAAAA==.Beronhuz:BAAALgAECgMJAwAAAA==.',
Bf='Bf:BAAALgAECgEJBAAAAA==.',
Bi='Biafalcão:BAAALgAECgEJAQAAAA==.Bijanca:BAAALgAECgYJBgAAAA==.Birthdäy:BAAALgADCgEJAQAAAA==.Bisponegro:BAAALgAECgQJCwABLgABCgcJFQASAAAAAA==.Biønic:BAAALgAECgMJCQAAAA==.',
Bl='Blackline:BAACLgAFFH8HAAIGAAMJrwulTwC4AAAGAAMJrwulTwC4AAAuAAQKfyIAAgYACAlWE25hAKYBAAYACAlWE25hAKYBAAAA.Blu:BAECLgAFFH8XAAIYAAQJvxBkFQDfAAAYAAQJvxBkFQDfAAAuAAQKf2wAAxgACQkqINEAAFMDABgACQkqINEAAFMDAAEAAwm3EkQRAK8AAAEuAAUUBAkXABgAvxAA.Blueish:BAAALgAECgUJBQABLgAECggJKQACAJ4aAA==.',
Bo='Boipretim:BAAALgAECgYJDwAAAA==.Bontorius:BAAALgADCgEJAgAAAA==.Bordello:BAAALgADCgUJBQAAAA==.',
Br='Bradio:BAAALgADCggJCAAAAA==.Brahman:BAAALgAECgEJBAAAAA==.Bratloko:BAAALgAECgUJBQAAAA==.Braverne:BAAALgAECgEJAQAAAA==.Bromos:BAAALgAECgQJCAAAAA==.Bruker:BAAALgAECgEJAQAAAA==.Brutalhoof:BAAALgAECgQJBAAAAA==.Brönsted:BAAALgADCgMJAwAAAA==.',
Bu='Bubbalo:BAAALgADCgUJBQAAAA==.Bullsman:BAAALgADCgQJBAAAAA==.Buzzumaaky:BAABLgAECn8YAAIWAAgJTxepiQC/AQAWAAgJTxepiQC/AQAAAA==.',
By='Byakura:BAAALgADCggJCwAAAA==.',
['Bü']='Büdweiser:BAAALgAECgcJEQAAAA==.',
Ca='Cabernet:BAAALgAECgUJBwAAAA==.Cabeçaquente:BAAALgAECgcJCQAAAA==.Cabinking:BAAALgAECgIJAgAAAA==.Calanthe:BAAALgADCgkJCQAAAA==.Calhistra:BAABLgAECn8nAAMZAAgJQxmBTAC1AQAZAAgJQxmBTAC1AQAaAAIJRQokVQBvAAAAAA==.Callstorm:BAAALgADCgcJBwAAAA==.Calteryeker:BAABLgAECn8cAAILAAgJTx2fBQBEAgALAAgJTx2fBQBEAgAAAA==.Camillas:BAAALgAECggJDwAAAA==.Caosenvy:BAAALgAECgEJAQAAAA==.Caralh:BAAALgAECgEJAgAAAA==.Caroll:BAAALgAECgIJAgAAAA==.Caryill:BAAALgAECgEJAQAAAA==.Castaldi:BAAALgAECgEJAgABLgAECgcJCwASAAAAAA==.Cathe:BAABLgAECn8aAAIbAAYJ6R0/YQCEAQAbAAYJ6R0/YQCEAQAAAA==.Caçaorda:BAAALgAECgMJBAAAAA==.',
Ce='Cecilith:BAAALgAECggJDQAAAA==.Cernunos:BAAALgADCgEJAQAAAA==.Cernûnnos:BAACLgAFFH8FAAICAAIJPRGMUwB3AAACAAIJPRGMUwB3AAAuAAQKfxUAAgIABglOD5RdAB4BAAIABglOD5RdAB4BAAAA.',
Ch='Champdude:BAABLgAECn9TAAQNAAkJqiPjAwAfAwANAAkJqiPjAwAfAwAcAAgJJxuBEQAtAgAMAAMJjR4VWwAIAQAAAA==.Changeman:BAAALgAECgEJAQAAAA==.Chankowkwai:BAAALgAECgYJCQAAAA==.Chanë:BAAALgADCgIJAwAAAA==.Chaosangel:BAAALgAECgUJCgABLgAFFAMJCgAQAMgHAA==.Chewi:BAAALgAECgQJBwAAAA==.Chrnnos:BAAALgAECgYJBgAAAA==.',
Ci='Citra:BAAALgAECgMJBwAAAA==.',
Co='Coconolose:BAAALgAECgIJBgAAAA==.Cod:BAAALgAECgIJAwAAAA==.Codecks:BAAALgADCgYJBgAAAA==.Coldbringer:BAAALgAECgEJAQAAAA==.Coldhearths:BAAALgAECgUJBgAAAA==.Cortegelido:BAAALgADCgIJAgAAAA==.Couro:BAAALgAECggJCwAAAA==.Cowzeroth:BAAALgAECgEJAgAAAA==.Cowçadora:BAAALgAECgMJBQAAAA==.',
Cr='Criminøsa:BAAALgAECgcJCQAAAA==.Cristcalad:BAABLgAECn9TAAMHAAkJKxyRAQAAAgAHAAkJ9hqRAQAAAgAXAAcJ9BYjAwClAQAAAA==.Cryomanta:BAAALgAECgUJBQAAAA==.',
Cu='Cunhaovirado:BAABLgAECn8YAAILAAcJagMfUABHAAALAAcJagMfUABHAAABLgAFFAYJEQANAOEXAA==.Cunhazinha:BAAALgAECgQJBAAAAA==.Cupyncha:BAAALgADCgcJBwAAAA==.Cutia:BAAALgADCgEJAQAAAA==.Cutiesissy:BAAALgAECgQJCAABLgAECgcJGgALAEoQAA==.',
['Cø']='Cøøkye:BAAALgAECgQJBQAAAA==.',
Da='Daellus:BAAALgAECgMJAwAAAA==.Daemi:BAAALgAECgIJBAAAAA==.Daibodan:BAAALgAECgEJBAAAAA==.Dalaty:BAAALgAECgUJBgAAAA==.Daniilos:BAAALgAFFAEJAQAAAA==.Daresh:BAAALgADCgIJAgAAAA==.Dariok:BAAALgAECgIJAgAAAA==.Darklara:BAABLgAECn8lAAIEAAkJBRkQCQDeAQAEAAkJBRkQCQDeAQAAAA==.Darkove:BAABLgAECn8vAAIWAAkJjBIrVADgAQAWAAkJjBIrVADgAQAAAA==.Darrow:BAACLgAFFH8SAAMGAAQJUh0iSgBeAQAGAAQJ+BsiSgBeAQAIAAMJdxyfEQAGAQAuAAQKfy8AAwYACQnPJP0PAOwCAAYACQn0I/0PAOwCAAgACAn8IloDALMCAAAA.Dartibeccoso:BAAALgADCgcJBwAAAA==.Daviberger:BAAALgAECgMJAwAAAA==.',
De='Deany:BAAALgAECgEJAgAAAA==.Deathinhu:BAABLgAECn9gAAIWAAkJaSFZAwDEAgAWAAkJaSFZAwDEAgAAAA==.Deathnacht:BAAALgAECgQJDQAAAA==.Delset:BAAALgADCgIJAgAAAA==.Demiun:BAAALgADCgUJBQAAAA==.Demojoca:BAAALgAECgIJAgABLgAECgcJDgASAAAAAA==.Dentepodre:BAAALgADCgEJAQAAAA==.Dervus:BAAALgADCgcJBwAAAA==.Dethroned:BAAALgAECgUJDAAAAA==.Devrath:BAAALgAECgEJAQAAAA==.Devyogi:BAAALgADCgcJCAAAAA==.',
Di='Diefs:BAAALgAECgEJAQAAAA==.Digaolock:BAAALgAECgEJAQAAAA==.Dimeros:BAABLgAECn9KAAIQAAkJTRbJAwDdAQAQAAkJTRbJAwDdAQAAAA==.Dito:BAAALgADCgEJAQAAAA==.Divano:BAACLgAFFH8SAAIBAAMJ8hvFDwDzAAABAAMJ8hvFDwDzAAAuAAQKfzEAAwEACQlGH2cNAH4CAAEACQlGH2cNAH4CABgAAwkCCXJgAHwAAAAA.',
Dk='Dkats:BAAALgAECgEJAgAAAA==.',
Dn='Dng:BAAALgAECgcJCAAAAA==.',
Do='Dogowner:BAAALgAECgkJEgAAAA==.Dogs:BAABLgAFFH8IAAILAAIJmxr0PwCgAAALAAIJmxr0PwCgAAAAAA==.Donora:BAABLgAECn8sAAQLAAkJFRNpUwDPAQALAAkJFRNpUwDPAQAVAAEJfwN0kgAsAAAKAAEJKAYUXQAVAAAAAA==.',
Dr='Drackmontana:BAABLgAECn8lAAMTAAgJaA4gNgDQAQATAAgJEg4gNgDQAQAXAAIJEhVBPQBjAAAAAA==.Drafael:BAAALgADCggJDgABLgAECgkJZgADAFEjAA==.Dragonfoox:BAAALgAECgIJAgAAAA==.Dragoniron:BAAALgADCgEJAQAAAA==.Dragony:BAAALgAECgEJBAAAAA==.Dragunass:BAABLgAECn9GAAMTAAkJQR8rBADPAQATAAkJXR4rBADPAQAXAAgJdBm2EgDAAQAAAA==.Dragøndeath:BAAALgADCgEJAgAAAA==.Drakars:BAAALgADCgUJBAAAAA==.Dranarus:BAAALgADCgQJBAAAAA==.Drexus:BAAALgAECgQJBAAAAA==.Druidblack:BAAALgAECgIJAwAAAA==.Drunkler:BAAALgAECgYJBwAAAA==.Dryter:BAABLgAECn8VAAINAAcJEA9QKwCEAQANAAcJEA9QKwCEAQAAAA==.Drákon:BAAALgAECgEJAQAAAA==.',
Du='Dubhe:BAABLgAECn8dAAMVAAkJERSkAgAqAgAVAAkJERSkAgAqAgALAAQJbBSiwAAHAQAAAA==.',
Dy='Dysttopia:BAAALgADCgcJCAAAAA==.',
El='Eldryrin:BAAALgAECgEJAQAAAA==.Elendile:BAAALgAECgEJAQAAAA==.Elidibus:BAAALgAECgEJAgAAAA==.Elinius:BAABLgAECn8vAAMQAAkJzSDQCADGAgAQAAkJzSDQCADGAgACAAIJUwyU2QArAAAAAA==.Elistraee:BAAALgAECgEJAQAAAA==.Ellandria:BAAALgAECgMJAwAAAA==.Ellonara:BAAALgAECgEJAQAAAA==.Ellvarg:BAAALgADCgQJBAAAAA==.Eloren:BAAALgAECgYJCwABLgAECggJIAAVAPERAA==.Eluuria:BAAALgAFFAEJAQAAAA==.Elyzia:BAAALgAECgEJAQAAAA==.',
En='Endorena:BAAALgADCgEJAQAAAA==.Ensabanú:BAAALgAECgEJAgAAAA==.',
Ep='Ephesus:BAAALgADCgIJAgAAAA==.',
Er='Erikssen:BAAALgADCgYJBgAAAA==.Ernest:BAABLgAECn9eAAICAAkJVh+SCAAvAwACAAkJVh+SCAAvAwAAAA==.Erynneus:BAAALgADCgMJAwAAAA==.',
Es='Estagiario:BAAALgAECgQJBgABLgAFFAIJBQAFAMMYAA==.Estgan:BAAALgADCgYJBgAAAA==.',
Et='Etubrutus:BAAALgAECgYJBwAAAA==.',
Eu='Eusouobatman:BAAALgADCgIJAgAAAA==.',
Ev='Evangelouco:BAAALgAECgQJBAAAAA==.Evetts:BAAALgADCgEJAQAAAA==.Evilbarba:BAABLgAFFH8FAAILAAIJNBCkjwCTAAALAAIJNBCkjwCTAAAAAA==.',
Ex='Exort:BAABLgAECn8jAAIWAAcJ+BjlEABQAQAWAAcJ+BjlEABQAQAAAA==.Exothus:BAAALgAECgEJAgAAAA==.Expressão:BAAALgADCgYJCwAAAA==.Exødus:BAAALgAECgEJAQAAAA==.',
Fa='Fafabr:BAAALgAECgEJAQAAAA==.Faldark:BAAALgAECgYJDgAAAA==.Fandrall:BAAALgAECgUJCAAAAA==.Faris:BAABLgAFFH8KAAIdAAMJzw7DIAB1AAAdAAMJzw7DIAB1AAAAAA==.Farmfarm:BAAALgADCgEJAQAAAA==.Faver:BAAALgAECgQJBQAAAA==.Faölin:BAABLgAECn8tAAIdAAcJxR0KBQBNAQAdAAcJxR0KBQBNAQAAAA==.',
Fe='Feenigan:BAAALgAECgEJAQABLgAECgQJBAASAAAAAA==.Feeniä:BAAALgAECgQJBAAAAA==.Ferael:BAABLgAECn9BAAMLAAkJZCLPDwDoAgALAAkJZCLPDwDoAgAVAAgJ2Rq5AQCBAgAAAA==.',
Fi='Fil:BAAALgAECgEJAQAAAA==.Firstomega:BAAALgADCgMJAwAAAA==.',
Fl='Flavors:BAACLgAFFH8GAAITAAMJzyTlIAAvAQATAAMJzyTlIAAvAQAuAAQKfyMAAxMACQndI+UHAOECABMACQndI+UHAOECAAcABAkhHgIUAGYBAAAA.Florbela:BAAALgAECgcJCwAAAA==.Flämbë:BAAALgADCgEJAQAAAA==.',
Fo='Foemablack:BAAALgAECgQJBAAAAA==.Fogue:BAAALgAECgkJEwAAAA==.Foxthamy:BAABLgAECn8mAAIMAAcJaxLKPAB8AQAMAAcJaxLKPAB8AQAAAA==.',
Fr='Frachlitzz:BAACLgAFFH8JAAIWAAMJWA+1hQDNAAAWAAMJWA+1hQDNAAAuAAQKfz0AAhYACQkhFn86AC8CABYACQkhFn86AC8CAAAA.Fradem:BAAALgAECgcJDQAAAA==.Freccianera:BAAALgADCgEJAQAAAA==.Fredericc:BAABLgAECn8cAAMeAAkJlw/2RwCOAQAeAAgJYA72RwCOAQAfAAcJ2gVYWQDfAAAAAA==.Fredinho:BAAALgAECgEJAQAAAA==.Freecs:BAAALgAECgYJBwABLgAECgcJCwASAAAAAA==.Freyá:BAABLgAECn8jAAILAAkJcCGHFADHAgALAAkJcCGHFADHAgAAAA==.Frostgore:BAAALgAECgEJAQAAAA==.Froststriker:BAAALgAECgEJAQAAAA==.Frozenn:BAAALgAECgUJBAABLgAECggJQgANAIYcAA==.Frs:BAAALgAECgEJAgAAAA==.',
Ga='Gafgarion:BAAALgAECgEJAQAAAA==.Galfur:BAAALgAECgEJAQAAAA==.Galhuda:BAABLgAECn8bAAICAAYJchKzBwBNAQACAAYJchKzBwBNAQAAAA==.Galyan:BAAALgADCgEJAQAAAA==.Gandalpha:BAAALgAECgUJBwAAAA==.Gandwelf:BAAALgADCgkJCQAAAA==.Gazieri:BAABLgAECn8gAAMVAAgJ8RFkRQBiAQAVAAgJ8RFkRQBiAQALAAQJCw/z2gDWAAAAAA==.',
Ge='Geeklimim:BAAALgAECgEJAQAAAA==.Geisty:BAAALgAECgMJAwABLgAECgcJHwAGAIAJAA==.Georgya:BAAALgAECgMJBAAAAA==.',
Gh='Ghalladriel:BAAALgADCgEJAwAAAA==.Ghruka:BAAALgAECgQJBAAAAA==.',
Gi='Giafar:BAAALgAECgEJAQABLgAECgYJDAASAAAAAA==.Ginea:BAAALgAECgEJAQAAAA==.',
Gl='Gluke:BAAALgAECgMJAwAAAA==.Glutotwo:BAAALgADCgQJBgAAAA==.',
Gn='Gnomari:BAABLgAECn8kAAIZAAgJJQL35ACTAAAZAAgJJQL35ACTAAAAAA==.',
Go='Goratrix:BAAALgAECgUJBQABLgAECgcJHwAGAIAJAA==.Gordanado:BAAALgAECgEJAgAAAA==.Gordruida:BAAALgAECgEJAQAAAA==.Govers:BAAALgADCgMJAwABLgAECgMJBAASAAAAAA==.',
Gr='Grandecoisa:BAAALgAECgEJAQAAAA==.Greyfin:BAAALgAECgEJBAAAAA==.Greyvor:BAAALgADCgEJAQAAAA==.Grimch:BAAALgAECgEJAQAAAA==.Grommar:BAAALgAECgEJAQABLgAECggJHAALAE8dAA==.Grumax:BAABLgAECn8UAAILAAgJyQ/FdACRAQALAAgJyQ/FdACRAQAAAA==.Grymysa:BAAALgAECgIJAgAAAA==.Grössa:BAABLgAECn8YAAMVAAcJIwiGWwAOAQAVAAcJIwiGWwAOAQALAAMJCQRdhgE5AAABLgAECgkJFwAZAJ8IAA==.',
Gu='Gudeath:BAAALgAECgcJCQAAAA==.Gugsã:BAAALgAECgEJAgAAAA==.Guitianki:BAAALgAECgEJAQAAAA==.Gulek:BAAALgAECgQJBAAAAA==.Gussg:BAABLgAECn8XAAQZAAkJnwgmZwBvAQAZAAkJnwgmZwBvAQAgAAEJzwgcQwArAAAaAAIJGQTpRgAeAAAAAA==.Gustavonz:BAAALgADCgcJBwAAAA==.',
['Gö']='Göhan:BAAALgADCgUJBQABLgAECgYJEwASAAAAAA==.',
['Gø']='Gøvers:BAAALgAECgMJBAAAAA==.',
Ha='Hakuouki:BAAALgAECgMJBgAAAA==.Hammurabi:BAAALgADCgEJAQAAAA==.Handyman:BAAALgADCgYJCgAAAA==.Hantom:BAAALgADCggJCQABLgAFFAYJEQANAOEXAA==.Harchus:BAAALgAECgEJAQAAAA==.Hazell:BAAALgAECgEJAQAAAA==.',
He='Heaveth:BAAALgAECgMJAwABLgAFFAMJCwAfAP4cAA==.Hefestion:BAAALgAFFAMJBAAAAA==.Hellspont:BAABLgAECn8WAAIPAAkJiCGsAAAAAwAPAAkJiCGsAAAAAwAAAA==.Helsingdarck:BAAALgADCgIJAgAAAA==.Hendrikison:BAAALgAECgcJCgAAAA==.',
Hi='Hildegyth:BAABLgAECn8fAAMNAAgJWBE1MQBhAQANAAcJWRE1MQBhAQAMAAUJZxG8WwAGAQAAAA==.',
Hj='Hjalmar:BAAALgADCgcJCQAAAA==.',
Ho='Hodtiva:BAABLgAECn8yAAMBAAgJwRTeLQBqAQABAAgJwRTeLQBqAQAOAAYJRA+pEwBlAAAAAA==.Homerz:BAAALgADCgEJAQAAAA==.Horagalles:BAAALgAECgEJAQAAAA==.Hotmojo:BAABLgAECn8qAAIWAAgJcRvUBgAWAgAWAAgJcRvUBgAWAgABLgAFFAgJFwAfALMZAA==.',
Hu='Hunfox:BAACLgAFFH8XAAIbAAQJUhhpCwAHAQAbAAQJUhhpCwAHAQAuAAQKf0QAAhsACQmuI78JAAoDABsACQmuI78JAAoDAAAA.Hunterzika:BAAALgAECgEJAQAAAA==.Huor:BAAALgAECgIJAgAAAA==.',
['Hä']='Härkness:BAAALgAECgYJCAAAAA==.',
['Hö']='Hölycrüsh:BAAALgAFFAEJAQAAAA==.',
['Hø']='Høolligans:BAAALgAECgEJAQAAAA==.',
['Hü']='Hüskar:BAABLgAECn8fAAMTAAkJ/AuTMQCGAQATAAkJuQuTMQCGAQAHAAEJCg8JfAAtAAAAAA==.',
Ic='Icechips:BAAALgADCgUJBQAAAA==.Ichigoz:BAABLgAECn8iAAIWAAkJBQqscgCUAQAWAAkJBQqscgCUAQAAAA==.',
Ih='Ihntwuaed:BAAALgADCgYJCwAAAA==.',
Ik='Ikoo:BAABLgAECn9iAAMYAAkJkSA0AQD6AgAYAAkJkSA0AQD6AgABAAEJvQ7bJwAtAAAAAA==.',
Il='Illaril:BAACLgAFFH8sAAIEAAYJRh2xAQC3AQAEAAYJRh2xAQC3AQAuAAQKf2YAAgQACQn3IWQCANcCAAQACQn3IWQCANcCAAAA.',
In='Indarion:BAAALgAECgEJAQAAAA==.Ingratt:BAAALgAECgEJAgAAAA==.Invisiblelol:BAAALgAECgIJAgAAAA==.',
Ir='Irakerr:BAABLgAECn8YAAILAAkJyAs0FwAVAQALAAkJyAs0FwAVAQAAAA==.Irmãodouther:BAAALgAFFAIJAwAAAA==.Irontoko:BAAALgAECggJDgAAAA==.',
Is='Isebby:BAAALgADCgMJAwAAAA==.Ishtarie:BAAALgAECgQJBQABLgAECgkJHgACAJkXAA==.',
It='Itzzdan:BAAALgADCgMJAwAAAA==.',
Iv='Ivina:BAACLgAFFH8LAAIZAAQJnwt/JwDzAAAZAAQJnwt/JwDzAAAuAAQKfxcAAxkACQniFhETANUAABkACAniFhETANUAACAAAgmpF7gcAI0AAAAA.',
Iz='Izaar:BAAALgAECgQJEwAAAA==.',
Ja='Jacsonnaik:BAAALgAECgQJBQAAAA==.Jadelina:BAAALgAECgEJAQAAAA==.Janaìna:BAAALgAECgMJAwAAAA==.Jangeoffry:BAAALgADCgEJAQAAAA==.Jaymee:BAAALgAECgEJBQAAAA==.',
Je='Jetset:BAAALgAECgMJAwABLgAECgkJFgAUAOwPAA==.',
Jh='Jhonatinha:BAABLgAECn8VAAMLAAcJBxkN3gDgAAALAAYJaxkN3gDgAAAVAAQJng69dgCfAAAAAA==.',
Ji='Jigsaww:BAAALgAECgQJCQAAAA==.',
Jk='Jks:BAAALgAECgYJEAAAAA==.',
Jo='Joaquim:BAAALgAECgIJAgAAAA==.Jogaveiopl:BAAALgADCgIJAgAAAA==.Johnlobo:BAAALgAECgEJAQAAAA==.Joventino:BAAALgADCgQJBQAAAA==.',
Ju='Jucah:BAABLgAECn8ZAAIfAAkJZAt6OwBIAQAfAAkJZAt6OwBIAQAAAA==.Julabolseiro:BAABLgAECn8ZAAMOAAgJgBCvCwDaAAAOAAgJgBCvCwDaAAABAAIJBgJAiQAwAAAAAA==.Julinhas:BAAALgAECgEJAQAAAA==.Jullianxd:BAAALgAECgMJAwABLgAECgkJFgAUAOwPAA==.Juzefa:BAAALgAECgcJBQAAAA==.',
Ka='Kaallew:BAABLgAECn8ZAAIKAAkJuRccGABdAQAKAAkJuRccGABdAQAAAA==.Kaelonidas:BAAALgAECgEJAQAAAA==.Kaezar:BAAALgADCgEJAQAAAA==.Kainer:BAAALgAECgQJBwAAAA==.Kakwzo:BAAALgAECgEJAQAAAA==.Kalazshar:BAABLgAECn8mAAIPAAkJbBI0FgCiAQAPAAkJbBI0FgCiAQAAAA==.Kalduran:BAABLgAECn8fAAMhAAgJQAYZBgDuAAAhAAgJqQUZBgDuAAAiAAEJxQeNDwAbAAAAAA==.Kalelzinho:BAAALgAECgEJAQAAAA==.Kaluss:BAABLgAECn8YAAIWAAgJqwfHKgChAAAWAAgJqwfHKgChAAAAAA==.Kanalet:BAAALgAECgYJCAAAAA==.Kandára:BAAALgADCgYJCAAAAA==.Kantaa:BAAALgAECgQJDwAAAA==.Kanturu:BAAALgAECgQJBAAAAA==.Kanzaki:BAAALgADCgcJBwABLgAECgkJUwANAKojAA==.Karonn:BAABLgAECn8UAAILAAYJ/A3mlABTAQALAAYJ/A3mlABTAQAAAA==.Kavartu:BAAALgAFFAEJAQAAAA==.Kaymon:BAAALgAECgEJAQAAAA==.',
Ke='Keillor:BAABLgAECn8pAAMeAAgJGRaYRQCXAQAeAAcJWRSYRQCXAQAfAAYJXRqCLwCCAQAAAA==.Kelantir:BAAALgAECgYJCQABLgAECgkJDAASAAAAAA==.Keldorian:BAAALgADCgcJEAAAAA==.Kelishe:BAAALgAECgUJBQAAAA==.Kelliar:BAAALgAECgIJAQAAAA==.Kelorn:BAAALgADCgYJBgABLgAECggJGAAeAPARAA==.Kelysa:BAAALgADCgkJDgABLgAECggJQgAXACYdAA==.Kenzou:BAABLgAECn8ZAAMcAAgJvhlDMQA9AQAcAAYJCR1DMQA9AQANAAcJSQ/0OAAeAQAAAA==.',
Kh='Khadi:BAAALgAECgcJCwAAAA==.Khaeltaz:BAAALgAECgMJAwAAAA==.Khalandra:BAABLgAECn8eAAITAAkJaBtyKwAIAgATAAkJaBtyKwAIAgAAAA==.Khalel:BAAALgADCgEJAgAAAA==.Khaliq:BAABLgAECn8eAAMFAAkJVxV5FADtAQAFAAkJVxV5FADtAQAUAAQJLApxrwCtAAAAAA==.Khallani:BAABLgAECn8fAAIGAAcJgAlLlQBWAQAGAAcJgAlLlQBWAQAAAA==.Khamul:BAAALgAECgQJBgAAAA==.Khaos:BAAALgAECggJEwAAAA==.Khisto:BAABLgAECn80AAMWAAkJnRsqOQA0AgAWAAkJnRsqOQA0AgAjAAcJ3Rf5BACSAQAAAA==.Khroriggs:BAAALgAECgYJDQABLgAECgcJBwASAAAAAA==.Khrøna:BAAALgADCgIJAgABLgAECgcJBwASAAAAAA==.',
Ki='Kieran:BAAALgAECgUJCwAAAA==.Killerbacon:BAAALgAECgEJAgAAAA==.Killerbiie:BAAALgADCgIJAgAAAA==.Killerdown:BAAALgADCgIJAgAAAA==.Killmastah:BAAALgAECgEJAQAAAA==.Kimashi:BAAALgAECgUJBQAAAA==.Kindie:BAAALgADCgcJCwABLgAECggJFAAUABEIAA==.Kisam:BAAALgAFFAIJAgAAAA==.Kissme:BAACLgAFFH8FAAMQAAMJ2AkNQgBuAAAQAAIJdwgNQgBuAAAPAAEJmwxTQgAmAAAuAAQKfx4AAxAACQmYEE0tAG8BABAACAneEU0tAG8BAA8ABAmICAhHAI0AAAAA.Kitamor:BAABLgAECn9hAAIQAAkJNxWAAwDzAQAQAAkJNxWAAwDzAQAAAA==.Kiya:BAAALgADCgcJHgAAAA==.',
Kl='Klorokina:BAAALgAECgYJBgAAAA==.',
Ko='Kooraqt:BAAALgAECgQJBAAAAA==.Koriakin:BAABLgAECn8vAAMbAAkJIR3QEADKAgAbAAkJIR3QEADKAgAhAAcJBxigGQDSAQAAAA==.Kosmo:BAAALgAECgcJCQAAAA==.Kotalkhan:BAAALgADCgkJEQAAAA==.',
Kr='Krosmu:BAAALgADCgcJBwAAAA==.Krov:BAAALgAECgEJAQAAAA==.Kryon:BAAALgAECgYJDgAAAA==.Kryzthor:BAAALgAECgYJCAAAAA==.Kräsus:BAABLgAECn9VAAIXAAkJAibtAABiAwAXAAkJAibtAABiAwAAAA==.Krønna:BAAALgAECgQJBAABLgAECgYJKQAkAEsIAA==.',
Ku='Kul:BAAALgAECgUJBgAAAA==.Kuthila:BAAALgADCgIJAgAAAA==.',
Ky='Kyzaru:BAAALgAECgIJAgAAAA==.',
['Kÿ']='Kÿdou:BAAALgAECgcJDgAAAA==.',
La='Ladrion:BAABLgAECn9WAAQlAAkJtR+HAQDfAgAlAAkJvB6HAQDfAgAdAAkJAxmFFABuAgAmAAkJ9RflBAA6AgAAAA==.Laetus:BAABLgAECn8ZAAInAAcJqxdpCAAXAQAnAAcJqxdpCAAXAQAAAA==.Lagosta:BAAALgAECgMJBgAAAA==.Laiany:BAABLgAECn9MAAIOAAkJJSISBABFAwAOAAkJJSISBABFAwAAAA==.Lani:BAAALgAECgEJAQAAAA==.',
Le='Leetohro:BAAALgAECgEJAQAAAA==.Legacia:BAAALgADCgYJBgAAAA==.Lekrom:BAAALgADCgYJBgAAAA==.Leodoros:BAAALgAECgYJDQAAAA==.Lequinhö:BAAALgAECgIJAgAAAA==.Leric:BAAALgADCgcJCgAAAA==.Lethmar:BAABLgAECn8eAAIZAAcJMxerXQCGAQAZAAcJMxerXQCGAQAAAA==.Levanah:BAABLgAFFH8IAAIbAAYJFAIrWwDuAAAbAAYJFAIrWwDuAAAAAA==.Leyana:BAAALgAECgUJBwAAAA==.',
Lh='Lhwei:BAAALgAECggJCwABLgAFFAQJEgAMANkbAA==.',
Li='Liandra:BAAALgAECgEJAQAAAA==.Licaon:BAAALgADCgYJDgAAAA==.Lichkiller:BAAALgAECgUJBQAAAA==.Lichkíng:BAAALgAECgYJBgAAAA==.Lightbreaker:BAABLgAECn8jAAILAAkJZAipiQBdAQALAAkJZAipiQBdAQAAAA==.Lihr:BAAALgADCgYJCQAAAA==.Lilianpotter:BAAALgAECgEJAQAAAA==.Lilithrix:BAAALgADCgIJAgAAAA==.Lillit:BAABLgAECn9TAAQgAAkJSxQ8AgCXAQAgAAgJUBM8AgCXAQAZAAkJ7A9eDwAEAQAaAAIJvwYwPQA3AAAAAA==.Lindaah:BAABLgAECn9CAAMNAAgJhhx7AgDzAQANAAgJhhx7AgDzAQAMAAcJTA3gFADkAAAAAA==.Lindademon:BAAALgAECgUJDwAAAA==.Lindahealer:BAAALgAECgUJCgABLgAECgUJDwASAAAAAA==.Lislfox:BAABLgAECn9AAAIPAAkJbBrPCABfAgAPAAkJbBrPCABfAgAAAA==.Lithlad:BAAALgADCgIJAgAAAA==.',
Lk='Lkinho:BAAALgAECgMJBAAAAA==.',
Lm='Lmmds:BAAALgAECgUJCwAAAA==.',
Lo='Lockynha:BAAALgADCgEJAQAAAA==.Lonän:BAAALgAECgQJBAAAAA==.Loohynir:BAABLgAFFH8FAAICAAIJFQlzXABiAAACAAIJFQlzXABiAAAAAA==.Lotusbird:BAAALgADCgcJBwAAAA==.',
Lu='Lucario:BAAALgAECgEJAwAAAA==.Luccoa:BAAALgAECgkJEwABLgAECgkJVQAXAAImAA==.Luccyah:BAAALgADCgkJDwAAAA==.Lucifïr:BAAALgAECgEJAQAAAA==.Lucileia:BAAALgAECgQJBQAAAA==.Lukazgplay:BAAALgADCgIJAgAAAA==.Lunirah:BAAALgAECgMJBAAAAA==.Lutsul:BAAALgAECgEJAQAAAA==.',
Ly='Lylka:BAABLgAECn9ZAAMKAAkJ0SWoAABlAwAKAAkJ0SWoAABlAwAVAAMJIiM5RAAwAQAAAA==.Lyrrena:BAAALgAECgMJBwAAAA==.',
Ma='Maanu:BAAALgAECgcJDwABLgAECggJQgANAIYcAA==.Maclaw:BAAALgADCgEJAQAAAA==.Macumbadora:BAAALgAECgQJCgAAAA==.Madfulock:BAABLgAECn8UAAIZAAcJiBh4XwCBAQAZAAcJiBh4XwCBAQAAAA==.Maeghann:BAAALgAECgQJBAAAAA==.Magalândia:BAAALgAECgIJAgAAAA==.Magashuave:BAAALgADCgEJAQAAAA==.Magraver:BAAALgAECgQJAwAAAA==.Mais:BAAALgAECgEJAQAAAA==.Makani:BAAALgAFFAEJAQAAAA==.Malewolyyc:BAACLgAFFH8IAAMOAAIJyR6KJACYAAAOAAIJyR6KJACYAAABAAEJZgfsPQA9AAAuAAQKfysAAw4ACQmZIXYMAJ8CAA4ACAk/I3YMAJ8CAAEABglGEYk6ACkBAAEuAAUUAwkDABIAAAAA.Malhun:BAAALgADCgUJDgAAAA==.Malphan:BAAALgAECgcJBwAAAA==.Malyguz:BAACLgAFFH8UAAIWAAQJ1BKpXQAkAQAWAAQJ1BKpXQAkAQAuAAQKfxsAAhYABwldG+BgABkCABYABwldG+BgABkCAAAA.Malévolaa:BAAALgAECgYJBwAAAA==.Manipullador:BAAALgAECgIJAgAAAA==.Mapussauro:BAAALgAECgcJEQAAAA==.Maradi:BAAALgADCgIJAgAAAA==.Mariob:BAABLgAFFH8GAAIJAAIJEAWhOwBIAAAJAAIJEAWhOwBIAAAAAA==.Marjøly:BAAALgAECgEJAQAAAA==.Markson:BAAALgADCgEJAQAAAA==.Massafera:BAABLgAECn8fAAILAAkJMxP4WgC8AQALAAkJMxP4WgC8AQAAAA==.Mather:BAAALgAECgEJAQAAAA==.Mathfacbruxo:BAABLgAECn9NAAIZAAkJFhzVGQCJAgAZAAkJFhzVGQCJAgAAAA==.Matui:BAAALgAECgEJAQAAAA==.Mauritiuz:BAAALgAFFAEJAQAAAA==.Mayanyy:BAAALgAECgEJAQAAAA==.',
Mc='Mcq:BAAALgAECgEJAQAAAA==.',
Md='Mdrdark:BAACLgAFFH8OAAIGAAYJ2BOMaAAoAQAGAAYJ2BOMaAAoAQAuAAQKfy0AAwYACQmiGRkxADoCAAYACQmiGRkxADoCAAkAAwm/FVhIAGwAAAAA.',
Me='Medz:BAABLgAECn8jAAIWAAkJlRqKMQBTAgAWAAkJlRqKMQBTAgAAAA==.Meedea:BAAALgADCgUJBgAAAA==.Meetjack:BAAALgAECgEJAgAAAA==.Megalyan:BAAALgAECgEJAQAAAA==.Meiyin:BAAALgAECgcJEAAAAA==.Melania:BAAALgAECgEJAwAAAA==.Melissandra:BAAALgAFFAIJAwAAAA==.Mellkor:BAABLgAECn8qAAIFAAkJQhv+DABWAgAFAAkJQhv+DABWAgAAAA==.Melytah:BAAALgAECgEJBAAAAA==.Melzynhaa:BAAALgAECgEJBAABLgAECggJQgANAIYcAA==.Meraxxes:BAAALgADCgcJDAAAAA==.Mercurios:BAAALgAECgYJBgAAAA==.Merellien:BAAALgADCggJDgAAAA==.Mestreioda:BAAALgAECgQJBAAAAA==.Metamorful:BAABLgAECn8ZAAICAAkJBxL/SQB7AQACAAkJBxL/SQB7AQAAAA==.',
Mh='Mhorgann:BAAALgAECgkJEQAAAA==.',
Mi='Mijonakombi:BAABLgAECn8WAAILAAkJ/hpnLwBDAgALAAkJ/hpnLwBDAgAAAA==.Mikveh:BAAALgAECgYJCgAAAA==.Milim:BAABLgAECn9BAAQRAAkJ8hMlHgDmAQARAAkJ2RIlHgDmAQAoAAgJRQ2GDwATAQApAAEJyQXiDwAeAAAAAA==.Milliidan:BAAALgADCgUJBQAAAA==.Mindrathys:BAAALgAECgEJAgAAAA==.Mithrius:BAABLgAECn8kAAILAAgJxxHvcACMAQALAAgJxxHvcACMAQAAAA==.',
Ml='Mls:BAAALgAECgUJBgAAAA==.',
Mo='Mogrus:BAAALgAECgUJBQAAAA==.Mohanna:BAAALgAECgkJEAAAAA==.Mohanninha:BAAALgAECgYJCwAAAA==.Mohotok:BAABLgAECn9fAAILAAkJ+hk0BgArAgALAAkJ+hk0BgArAgAAAA==.Momy:BAAALgAECgEJAQAAAA==.Moonøvesso:BAAALgAECgIJBQAAAA==.Moopp:BAAALgADCgcJCAAAAA==.Mortixxia:BAABLgAECn8oAAIaAAgJnx0kBABCAgAaAAgJnx0kBABCAgAAAA==.Moryhana:BAAALgADCgEJAQAAAA==.',
Mu='Muata:BAAALgAECgYJDwAAAA==.Muf:BAAALgAECgYJBgAAAA==.Mupar:BAAALgADCgIJAgAAAA==.Murano:BAABLgAECn8yAAMTAAkJxR75DQCQAgATAAkJxR75DQCQAgAHAAMJywp/VQCBAAAAAA==.Muzzo:BAAALgADCgYJCwABLgAECgcJEgASAAAAAA==.',
My='Mypower:BAAALgADCgkJCQAAAA==.Myrmïdom:BAAALgAECgIJAgAAAA==.Myzoreh:BAAALgAECggJDAAAAA==.',
['Má']='Mágico:BAAALgAECgEJAwAAAA==.Máia:BAABLgAECn8UAAIaAAgJiAxrEQAvAQAaAAgJiAxrEQAvAQAAAA==.',
['Mä']='Mändosz:BAABLgAECn8ZAAMGAAkJMRKYbgCIAQAGAAgJahKYbgCIAQAIAAMJCRB0JACsAAAAAA==.',
['Mé']='Ménace:BAACLgAFFH8FAAIZAAMJPhfybQDmAAAZAAMJPhfybQDmAAAuAAQKfxUAAxkACQnmHfZaALcBABkACAnmHfZaALcBABoAAwlcDvJGAJoAAAAA.',
['Mÿ']='Mÿstyna:BAAALgAECgEJAQAAAA==.',
Na='Naallia:BAAALgAECgEJAwAAAA==.Nalathiel:BAABLgAECn8YAAIOAAkJWQ7vMwA2AQAOAAkJWQ7vMwA2AQAAAA==.Narancia:BAAALgAECgYJDQABLgAECgcJCwASAAAAAA==.Naryth:BAAALgAECgYJCAAAAA==.Nassur:BAAALgADCgEJAQAAAA==.Nattaliaa:BAAALgAECgEJAQAAAA==.Nazawill:BAAALgAECgQJBQAAAA==.Nazdru:BAAALgADCgMJAwABLgAECgkJZgADAFEjAA==.Nazzh:BAAALgAECgEJAQABLgAFFAUJCQAUAMwUAA==.',
Ne='Necronx:BAAALgAECgEJAQAAAA==.Necronxd:BAAALgADCgEJAgAAAA==.Nefas:BAABLgAECn8jAAIaAAkJYxPnBwDSAQAaAAkJYxPnBwDSAQAAAA==.Nefazo:BAAALgAECgcJCgAAAA==.Nefilo:BAAALgADCgYJEAAAAA==.Nepthunus:BAABLgAECn9OAAIjAAkJuyGEAAAXAwAjAAkJuyGEAAAXAwAAAA==.Nermand:BAAALgAECgEJAQAAAA==.Neshula:BAAALgADCgMJAwAAAA==.Neuvosor:BAAALgAECgEJAQAAAA==.',
Ni='Nibelunga:BAAALgADCgYJBgAAAA==.Nijor:BAAALgADCgYJBgAAAA==.Nilsonssbnu:BAAALgAECgEJAQAAAA==.',
No='Nobelnaga:BAAALgAECgMJAwAAAA==.Noovaatoo:BAABLgAFFH8FAAIGAAMJaQMbZACNAAAGAAMJaQMbZACNAAAAAA==.Noria:BAAALgAECgIJAgAAAA==.Novatoo:BAAALgAFFAEJAQAAAA==.',
Ny='Nymira:BAAALgADCgIJAgABLgAFFAMJDQAGABwNAA==.Nyobb:BAAALgADCgkJDAAAAA==.Nyxra:BAAALgADCgcJEAAAAA==.',
['Në']='Nëcros:BAABLgAECn8WAAMGAAcJlR76BQAPAgAGAAcJlR76BQAPAgAJAAUJ6A3cEQBcAAAAAA==.',
['Nö']='Nöirr:BAAALgAECgUJBwAAAA==.',
Oc='Ocelotte:BAAALgADCgEJAQAAAA==.',
Od='Odin:BAAALgAECgEJAQAAAA==.Odynsabio:BAAALgAECgEJAQAAAA==.',
Of='Ofanzitsu:BAAALgADCgQJBAAAAA==.',
Oi='Oioimiguel:BAAALgAECgUJBQAAAA==.',
Ol='Olhua:BAAALgAECgMJCQAAAA==.Oljedvlad:BAAALgADCgIJAgAAAA==.Oluss:BAAALgADCgUJBQABLgAFFAgJFwAbAFIYAA==.',
Om='Omnath:BAAALgADCgYJBgAAAA==.',
On='Onixtrazzia:BAAALgAECgUJCAAAAA==.',
Or='Orillan:BAABLgAECn9YAAMFAAkJIBtlCwBwAgAFAAkJIBtlCwBwAgAUAAEJhAcY5gAsAAAAAA==.Ornsteinsnow:BAABLgAECn8ZAAIVAAkJvhSJHAAfAgAVAAkJvhSJHAAfAgAAAA==.Orob:BAABLgAECn8WAAICAAYJhQm+eQDKAAACAAYJhQm+eQDKAAAAAA==.Ororah:BAAALgAECgYJEAAAAA==.Orsonn:BAAALgAECgYJDAAAAA==.Orukam:BAABLgAECn8ZAAMCAAkJMBYvRACAAQACAAgJ7BQvRACAAQAQAAMJTgjAaAB9AAAAAA==.',
Os='Oszwald:BAAALgADCgEJAQAAAA==.',
['Oú']='Oúkürä:BAAALgAECgYJCgAAAA==.',
Pa='Paachamama:BAAALgADCgMJAwAAAA==.Padawani:BAAALgAECgMJAwAAAA==.Padgodeira:BAAALgAECgQJBAAAAA==.Padrealpha:BAAALgADCgcJCgAAAA==.Padrekelmøn:BAAALgAECgQJBAAAAA==.Palaha:BAAALgADCgEJAQABLgAFFAgJFwAbAFIYAA==.Palantír:BAAALgAECgEJAQAAAA==.Palatina:BAABLgAFFH8GAAILAAUJWhenQgAmAQALAAUJWhenQgAmAQAAAA==.Palazzy:BAAALgAECgEJAgAAAA==.Pandong:BAAALgAECggJEAAAAA==.Panena:BAAALgAECgIJAwAAAA==.Pangedrey:BAABLgAECn9UAAMNAAkJOCBjCADBAgANAAkJOCBjCADBAgAcAAcJJQRzTQDJAAAAAA==.Paracepatrol:BAAALgAECgQJAwAAAA==.Parcival:BAACLgAFFH8LAAIbAAMJoBokVwD4AAAbAAMJoBokVwD4AAAuAAQKfzsAAhsACQm8I4AFADoDABsACQm8I4AFADoDAAAA.Parký:BAAALgAECggJCQAAAA==.Pattalógika:BAAALgAECgEJAQAAAA==.Paullk:BAABLgAECn8gAAIQAAYJchQQPQAcAQAQAAYJchQQPQAcAQAAAA==.',
Pe='Pedrinho:BAAALgADCgYJBgABLgAFFAYJFwAUAD4eAA==.Penseur:BAAALgAECggJDgAAAA==.Penéllope:BAAALgAECgQJBwAAAA==.Persëphone:BAABLgAECn8VAAMOAAcJsRTjPQD6AAAOAAUJyRDjPQD6AAABAAYJCBKDXAClAAAAAA==.Peruchi:BAAALgAFFAIJAgAAAA==.',
Pg='Pgms:BAAALgAECgUJBQAAAA==.',
Ph='Phacozitos:BAAALgAECgEJAgAAAA==.Phaxe:BAAALgADCgIJAgAAAA==.Phoenicx:BAAALgADCgMJBgAAAA==.Phøënïx:BAAALgAECgcJDAAAAA==.',
Pi='Pipelinebr:BAAALgAECgUJBQAAAA==.Pitombinha:BAAALgAECgEJBAAAAA==.',
Pl='Plumalume:BAAALgADCgYJBgAAAA==.',
Po='Powalker:BAAALgAECgEJAgAAAA==.Powertell:BAAALgAECgYJCQABLgAECgkJHQANAMoSAA==.',
Pp='Pp:BAABLgAFFH8TAAQYAAUJngmTIgA7AQAYAAUJngmTIgA7AQABAAIJ4wYXMwB4AAAOAAEJ6wCPPQAlAAABLgAFFAgJLAARAAEaAA==.',
Pr='Prometeus:BAAALgAECgYJDwAAAA==.Pryom:BAAALgADCgEJAQAAAA==.Pryon:BAAALgAECgUJCwAAAA==.',
Pt='Ptollomeu:BAAALgAECgMJBQABLgAECgMJCQASAAAAAA==.',
['Pä']='Pändero:BAABLgAECn8WAAIMAAYJ8yIIGgBHAgAMAAYJ8yIIGgBHAgAAAA==.Pänqueca:BAAALgAECgEJAgAAAA==.',
['Pé']='Pénacova:BAAALgADCgEJAQAAAA==.',
['Pî']='Pîo:BAACLgAFFH8IAAIWAAMJVxE6gADWAAAWAAMJVxE6gADWAAAuAAQKfxcAAxYACAltGVZiALoBABYACAl5GFZiALoBACcABAnTGPAKACwBAAAA.',
Qu='Quejerok:BAAALgAECgYJEwAAAA==.',
Ra='Radiação:BAAALgAECgUJBgAAAA==.Radunz:BAABLgAECn9mAAIDAAkJUSN1AAD2AgADAAkJUSN1AAD2AgAAAA==.Ragnaros:BAABLgAFFH8FAAIVAAIJAxAxOwB4AAAVAAIJAxAxOwB4AAAAAA==.Ragnarssön:BAAALgAFFAEJAQAAAA==.Raineko:BAAALgADCgYJBgAAAA==.Raio:BAACLgAFFH8FAAIWAAIJlxNbogCKAAAWAAIJlxNbogCKAAAuAAQKfy8AAhYACQkEIfIdAKkCABYACQkEIfIdAKkCAAAA.Ralfwur:BAAALgAECgQJBwAAAA==.Ramsez:BAAALgAECgEJAQAAAA==.Rargsa:BAABLgAECn8lAAIIAAgJwwtFBwDTAAAIAAgJwwtFBwDTAAAAAA==.Rariel:BAAALgADCgIJAgAAAA==.Rasmon:BAABLgAECn8uAAIZAAkJRxTAQwDQAQAZAAkJRxTAQwDQAQAAAA==.Ravendreth:BAAALgADCgEJAQAAAA==.Raykarla:BAAALgAECgIJAwAAAA==.Raymain:BAACLgAFFH8GAAMNAAMJzh1PGwDxAAANAAMJzh1PGwDxAAAMAAEJkw6vZgAuAAAuAAQKfyQAAwwACQkSFqw9AHkBAAwACAmaFKw9AHkBAA0ABwkXFrc4AB8BAAAA.Raíka:BAAALgAECgYJEAAAAA==.',
Re='Reddnose:BAAALgAECgUJCQAAAA==.Reineke:BAAALgADCgEJAgAAAA==.Reinhold:BAABLgAECn8cAAMLAAcJ6RTBewB3AQALAAcJ6RTBewB3AQAVAAUJ2Qj8WwDGAAAAAA==.',
Rh='Rhuryk:BAAALgADCggJCAAAAA==.',
Ri='Ricktdai:BAAALgAECgEJAQAAAA==.Riesze:BAACLgAFFH8KAAIbAAMJoRGZXwDlAAAbAAMJoRGZXwDlAAAuAAQKfycAAhsACQl9GWshAGACABsACQl9GWshAGACAAAA.',
Ro='Roguinhu:BAAALgAFFAEJAQAAAA==.Ropaoo:BAABLgAECn8XAAIaAAYJEhbMDwBDAQAaAAYJEhbMDwBDAQAAAA==.',
Ru='Rua:BAAALgAECgQJBAAAAA==.Rurumo:BAABLgAECn8WAAIgAAgJDyF6AACqAgAgAAgJDyF6AACqAgAAAA==.Rusga:BAAALgADCggJCgAAAA==.Rustovick:BAAALgAECgMJBwAAAA==.',
Ry='Rytheas:BAAALgAECgQJBgAAAA==.',
['Rä']='Rämzä:BAAALgAECgYJEwAAAA==.',
['Rå']='Råy:BAAALgAECgQJCQAAAA==.',
['Rí']='Rízadinha:BAAALgAECgQJBAAAAA==.',
Sa='Saargeras:BAAALgADCgMJAwAAAA==.Saffír:BAABLgAECn8pAAILAAkJTRhBNgAoAgALAAkJTRhBNgAoAgAAAA==.Saiden:BAAALgAECgEJAQAAAA==.Saintkaue:BAAALgADCgUJCAAAAA==.Sairoz:BAAALgAECgEJBAAAAA==.Samalandraa:BAAALgADCgEJAQAAAA==.Sanahh:BAABLgAECn8YAAMLAAYJ1wquKQClAAALAAYJ1wquKQClAAAKAAUJTQP7EwBHAAAAAA==.Sanateia:BAAALgADCgYJCwAAAA==.Santamadre:BAAALgADCgEJAQAAAA==.Sapekinhä:BAACLgAFFH8FAAIFAAIJwxj3IQCLAAAFAAIJwxj3IQCLAAAuAAQKfywABAUACQlJI70EAPoCAAUACQlJI70EAPoCAAQAAglSGOwjAH8AABQAAglFCR/5AFQAAAAA.Satanvitória:BAABLgAECn8uAAMHAAgJ7B5tDAAgAgATAAcJYRo0JgAoAgAHAAgJbh5tDAAgAgAAAA==.Sauroth:BAAALgADCgUJCQAAAA==.',
Sc='Scheiren:BAAALgAECgQJBgAAAA==.Scéal:BAAALgAECgMJAwAAAA==.',
Se='Senegos:BAAALgADCgcJBwAAAA==.Sereiaa:BAABLgAECn8rAAIbAAkJ9g0WZQB6AQAbAAkJ9g0WZQB6AQAAAA==.Sesiom:BAAALgAECgcJBgAAAA==.',
Sh='Shalltearr:BAAALgADCgEJAQAAAA==.Shamana:BAAALgAECgEJAQAAAA==.Shamate:BAAALgAFFAEJAQAAAA==.Shanoa:BAAALgAECgMJAwAAAA==.Sharae:BAAALgAECgQJCAAAAA==.Shariany:BAAALgADCgEJAQAAAA==.Sharpersong:BAAALgADCgcJBgAAAA==.Shedo:BAABLgAECn8VAAMHAAgJAxovFwCiAQAHAAcJuBkvFwCiAQATAAYJWg+VYgAoAQAAAA==.Sheevane:BAABLgAECn8eAAICAAkJmResJAAnAgACAAkJmResJAAnAgAAAA==.Shinzo:BAAALgADCgEJAQAAAA==.Shonja:BAAALgADCgcJDgAAAA==.Shula:BAAALgADCgcJDQAAAA==.Shumuk:BAAALgAECgEJAQAAAA==.Shytarra:BAAALgAECgUJBQABLgAECggJQgANAIYcAA==.Shÿnara:BAAALgAECgkJDwAAAA==.',
Si='Siclop:BAAALgADCgYJBgAAAA==.Silgris:BAAALgAECgEJAQABLgAECggJIAAVAPERAA==.Silmeria:BAABLgAECn8dAAIeAAkJdAZUXwA+AQAeAAkJdAZUXwA+AQAAAA==.Silverchain:BAAALgADCgcJCgAAAA==.Simplicity:BAAALgAECgEJAQAAAA==.Sinton:BAAALgAECgQJCAAAAA==.',
Sk='Skadryan:BAAALgAECgIJAwAAAA==.Skalnark:BAAALgAECgQJCAAAAA==.Skeletowman:BAAALgADCgUJBQAAAA==.Skineh:BAAALgAECgQJBwAAAA==.Skinme:BAABLgAECn8UAAIMAAYJKwQhjACDAAAMAAYJKwQhjACDAAAAAA==.',
Sm='Smylf:BAAALgAECgkJEAAAAA==.',
Sn='Snakedown:BAAALgAECgEJAgAAAA==.',
So='Sombrea:BAABLgAECn8VAAILAAcJyQfx8ADJAAALAAcJyQfx8ADJAAAAAA==.',
Sp='Spectrø:BAAALgAECgYJBgAAAA==.',
Sr='Srheal:BAAALgAECgQJBAAAAA==.Srsapo:BAAALgAECgMJBgAAAA==.',
Ss='Ssamara:BAAALgAECgYJBgAAAA==.',
St='Stampede:BAAALgADCgMJAwAAAA==.Starian:BAABLgAECn8gAAMCAAcJKRwtJQAjAgACAAcJKRwtJQAjAgAQAAEJywwTfwAzAAAAAA==.Starkz:BAAALgAECgEJAwAAAA==.Straider:BAAALgAECgEJAQAAAA==.Stëlla:BAABLgAECn8vAAIeAAgJ3RS6LwD2AQAeAAgJ3RS6LwD2AQAAAA==.',
Su='Suckmyhammer:BAABLgAECn8VAAIkAAcJdwuECAC/AAAkAAcJdwuECAC/AAAAAA==.Sungjinwoo:BAAALgADCgMJAwAAAA==.Sunnara:BAACLgAFFH8XAAIUAAYJPh7nFwBYAQAUAAYJPh7nFwBYAQAuAAQKfyIAAhQACQnwITwKAPgCABQACQnwITwKAPgCAAAA.Superkx:BAAALgAECgQJBQAAAA==.Suzanomu:BAAALgADCgYJCwAAAA==.',
Sy='Sylran:BAAALgADCgQJBgAAAA==.Synk:BAAALgADCgQJBAAAAA==.Syofra:BAAALgAECgQJBQAAAA==.Syrelys:BAAALgADCgYJBgAAAA==.Syuon:BAACLgAFFH8SAAIMAAQJ2RvTGAAGAQAMAAQJ2RvTGAAGAQAuAAQKfzQAAwwACQkiIQYGAEYDAAwACQkiIQYGAEYDAA0AAgmQBqSKAEcAAAAA.',
['Së']='Sëkhmet:BAAALgAECgYJCwAAAA==.',
['Sï']='Sïmbä:BAABLgAECn8bAAMGAAkJjQ4DdQB6AQAGAAkJjQ4DdQB6AQAIAAEJkAShGQAoAAABLgAFFAEJAQASAAAAAA==.',
['Só']='Sósummono:BAAALgADCgYJBwAAAA==.',
['Sÿ']='Sÿkies:BAAALgADCgEJAQAAAA==.',
Ta='Talandar:BAABLgAECn8/AAIQAAkJshzRAQCAAgAQAAkJshzRAQCAAgAAAA==.Tankudo:BAABLgAECn8dAAIGAAgJKhOmhQBYAQAGAAgJKhOmhQBYAQAAAA==.Tannia:BAAALgAECgYJBgAAAA==.Tanthallas:BAAALgAECgEJAQAAAA==.Tavindapedra:BAAALgAECgYJCwAAAA==.',
Tc='Tchurusbango:BAAALgAECgEJAQAAAA==.Tchutchuco:BAAALgAECgIJAwAAAA==.',
Te='Tekzero:BAAALgAECgEJCAAAAA==.Tempestus:BAAALgADCgYJBgAAAA==.Tennebra:BAAALgAECgEJAQAAAA==.Teobaldo:BAAALgAECgEJAQAAAA==.Terron:BAABLgAECn8yAAMeAAkJEBYjIgBCAgAeAAkJEBYjIgBCAgAfAAIJnRc6dQCMAAAAAA==.',
Th='Thabitah:BAABLgAECn9mAAIBAAkJ1CA6AQDQAgABAAkJ1CA6AQDQAgAAAA==.Thagale:BAAALgAECgQJBAABLgAECgkJYQAQADcVAA==.Thaliath:BAAALgADCgQJBAAAAA==.Thallariel:BAAALgAECgQJBwAAAA==.Theteo:BAABLgAECn8ZAAILAAkJZQumggBqAQALAAkJZQumggBqAQAAAA==.Thiberios:BAAALgAECgUJDAAAAA==.Thirros:BAAALgADCgUJBQAAAA==.Thorres:BAAALgAECgMJBwAAAA==.Thotamon:BAAALgAECgQJCAAAAA==.Throin:BAAALgAECgMJAwAAAA==.Thràain:BAAALgAECgcJDgAAAA==.Thuki:BAAALgAECgEJAQAAAA==.Thunderblade:BAAALgAECgYJDgAAAA==.Thuska:BAAALgADCgYJBgAAAA==.Théus:BAAALgAECgMJAwABLgAFFAMJBQAZAD4XAA==.',
Ti='Tidim:BAAALgAECgEJAQAAAA==.Tiramisu:BAAALgAECgcJCwAAAA==.',
To='Torâo:BAABLgAECn8XAAIIAAcJ6ghMCAC8AAAIAAcJ6ghMCAC8AAAAAA==.Toucinho:BAAALgAECgYJDgAAAA==.',
Tr='Traydd:BAABLgAECn8iAAIDAAgJlBWoDgDKAQADAAgJlBWoDgDKAQAAAA==.Tredmor:BAAALgAECgEJAQAAAA==.Trollando:BAAALgAECgUJCAAAAA==.Trutona:BAAALgAECgEJAQAAAA==.',
Tu='Tuga:BAAALgADCgMJAwAAAA==.Turokk:BAABLgAECn8pAAIbAAgJfxRxFAA0AQAbAAgJfxRxFAA0AQAAAA==.',
Tw='Twilight:BAAALgADCgYJDQAAAA==.Twylluch:BAAALgADCgQJBgABLgAECgkJKAAVAOsXAA==.',
['Të']='Tëmys:BAAALgADCgEJAQAAAA==.',
Ul='Ulhim:BAAALgADCgcJEwAAAA==.',
Ur='Uriuri:BAAALgADCgYJBgABLgAECgkJZgADAFEjAA==.',
Us='Usfull:BAABLgAECn87AAMOAAkJHhJ0JQCZAQAOAAgJYhN0JQCZAQABAAgJFg0fLwBjAQAAAA==.',
Va='Vacavelha:BAAALgAECgEJAQAAAA==.Vahtorn:BAAALgAECgMJBgAAAA==.Valaerys:BAAALgAECgUJCgAAAA==.Valaniri:BAAALgADCgEJAQAAAA==.Vallkÿria:BAAALgAECgYJBwAAAA==.Vanheelsen:BAAALgAFFAIJBAAAAA==.Vanyathariel:BAAALgAECgEJAgAAAA==.Vareena:BAAALgADCggJCAABLgAECgkJVQAXAAImAA==.Vashiel:BAAALgADCgIJAgAAAA==.',
Ve='Vehuiáh:BAABLgAECn8eAAMVAAgJMB0ZHQAbAgAVAAgJMB0ZHQAbAgALAAEJRQQFwgEjAAAAAA==.Velen:BAABLgAECn8pAAIGAAkJPRlSBABnAgAGAAkJPRlSBABnAgAAAA==.Vellkor:BAAALgADCgYJBgAAAA==.Vellon:BAAALgADCgEJAQAAAA==.Venrique:BAAALgAECgQJBAABLgAECgYJEgASAAAAAA==.Venusa:BAAALgAECgYJBgAAAA==.Verno:BAAALgADCgcJCwAAAA==.Verzuk:BAABLgAECn8eAAIGAAgJPQqWjABMAQAGAAgJPQqWjABMAQAAAA==.',
Vi='Vidnands:BAAALgAECgEJAQAAAA==.Viinyy:BAAALgAECgMJAwAAAA==.Vilthor:BAAALgAECgUJBQAAAA==.Vintekilo:BAABLgAECn8YAAILAAkJzRaiYgC9AQALAAkJzRaiYgC9AQAAAA==.',
Vo='Vokeshar:BAAALgADCgUJBQAAAA==.Voltadupla:BAAALgAECgQJBQAAAA==.Voop:BAAALgADCgYJFAAAAA==.',
Vr='Vrenshrrgn:BAAALgAECgYJBgAAAA==.',
Vu='Vulcânico:BAAALgADCgUJCQAAAA==.',
Vy='Vygh:BAACLgAFFH8JAAIZAAMJmBXHdQDWAAAZAAMJmBXHdQDWAAAuAAQKfy4AAxkACQm5IVYOANoCABkACQm5IVYOANoCABoAAQkjDzpwADYAAAAA.Vyndrill:BAAALgAECgYJDgAAAA==.',
['Vä']='Välion:BAAALgADCgIJAgAAAA==.',
Wa='Wacom:BAAALgADCgUJBQAAAA==.Walkers:BAAALgAECgkJDgAAAA==.Warlaka:BAAALgAECgYJDgAAAA==.Warpiel:BAAALgADCgcJDAABLgAECgkJHgAYAC0OAA==.Wartigeer:BAAALgAECgEJAQAAAA==.Watchtower:BAAALgAECgQJBAAAAA==.',
We='Wenus:BAAALgAFFAEJAQAAAA==.',
Wh='Wheez:BAAALgAECgQJBAABLgAECgkJNAAWAJ0bAA==.',
Wi='Williem:BAAALgADCgYJFAAAAA==.',
Wo='Worthy:BAAALgADCgQJBAAAAA==.',
Wy='Wyrel:BAAALgAECgEJAgAAAA==.',
['Wä']='Wätanabe:BAAALgAECgQJBAAAAA==.',
Xa='Xafado:BAAALgAECgEJAQAAAA==.Xamalandrö:BAAALgAECgQJCwAAAA==.',
Xe='Xeal:BAAALgADCgEJAQAAAA==.Xehagus:BAAALgADCgcJCgAAAA==.',
Xi='Xiblaublum:BAAALgADCgMJAwAAAA==.Xinhagoo:BAAALgAECgMJAwAAAA==.Xiquimiro:BAAALgADCgQJBAAAAA==.',
Xx='Xximperadorx:BAAALgADCgIJAgAAAA==.',
Ya='Yasuoh:BAAALgAECgQJCAAAAA==.',
Ye='Yewner:BAAALgADCgYJBQAAAA==.',
Yi='Yingsu:BAABLgAECn8ZAAIcAAkJeCLRDgBNAgAcAAkJeCLRDgBNAgAAAA==.',
Yo='Yoshihime:BAAALgAECgIJAgABLgAECgkJHgACAJkXAA==.',
Yv='Yvin:BAAALgAECgMJBAAAAA==.',
Za='Zallmo:BAACLgAFFH8JAAITAAMJ4AmyJgCHAAATAAMJ4AmyJgCHAAAuAAQKfyMAAhMACAl/FaMkANABABMACAl/FaMkANABAAAA.Zaolron:BAAALgAECgEJAQAAAA==.Zarath:BAAALgAECgUJBgAAAA==.Zawarudo:BAAALgAECgYJCgAAAA==.',
Ze='Zedd:BAAALgAFFAIJAgAAAA==.Zenorclord:BAAALgADCgQJBgAAAA==.Zeratulw:BAAALgAECgEJAQAAAA==.Zeytona:BAABLgAECn8jAAIcAAkJjAuLJgB6AQAcAAkJjAuLJgB6AQAAAA==.',
Zi='Ziracruz:BAAALgAECgQJCwAAAA==.',
Zu='Zulyn:BAAALgAECgIJAgAAAA==.Zupen:BAAALgAECgMJAQAAAA==.',
['Zí']='Zíngara:BAAALgAECgEJAQAAAA==.',
['Ár']='Árÿä:BAABLgAECn9VAAIbAAkJURVkMQAWAgAbAAkJURVkMQAWAgAAAA==.',
['Ãy']='Ãy:BAAALgAECgEJAQAAAA==.',
['Är']='Äraxy:BAAALgAECgUJCwAAAA==.',
['Äy']='Äy:BAAALgAECgEJAQAAAA==.',
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
