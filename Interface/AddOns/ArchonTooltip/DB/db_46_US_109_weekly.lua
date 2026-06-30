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

local lookup = {'Priest-Shadow','Druid-Restoration','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Unholy','Unknown-Unknown','DeathKnight-Frost','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Druid-Guardian','Druid-Balance','Evoker-Augmentation','DemonHunter-Devourer','Paladin-Holy','Mage-Frost','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Monk-Brewmaster','Warrior-Arms','Priest-Discipline','Warrior-Fury','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Mage-Fire','Hunter-Survival','Shaman-Enhancement','Rogue-Outlaw','Rogue-Assassination','Mage-Arcane','DeathKnight-Blood','Evoker-Devastation','Evoker-Preservation',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abelao:BAAALgAECgcJEwAAAA==.',
Ad='Adelaide:BAAALgAECgIJAgABLgAFFAgJIQABAGQaAA==.Adoramuss:BAAALgAECgYJCwAAAA==.Adrianoj:BAAALgAECgEJAQABLgAFFAIJBQACAD0RAA==.',
Ae='Aeklug:BAAALgADCgcJCAAAAA==.Aelon:BAAALgADCgcJDAAAAA==.Aelthor:BAABLgAECn8WAAIDAAQJ3BGvAgDaAAADAAQJ3BGvAgDaAAAAAA==.Aemeath:BAABLgAECn8XAAMEAAkJiyHXAQD8AgAEAAkJiyHXAQD8AgAFAAIJnhgCSgCOAAAAAA==.Aenthür:BAAALgAECgEJAQAAAA==.',
Ah='Ahammes:BAAALgAECgQJBAABLgAECgcJHwAGAIAJAA==.Ahmus:BAAALgAECgUJDAAAAA==.Ahrallu:BAAALgADCgEJAgAAAA==.',
Ai='Aioliavictus:BAAALgADCgIJAgAAAA==.',
Ak='Akaynu:BAAALgAECgEJAQAAAA==.',
Al='Alanie:BAAALgAECgUJDQABLgAFFAIJAgAHAAAAAA==.Aldranir:BAAALgADCgEJAQAAAA==.Alessaxd:BAACLgAFFH8KAAIGAAIJlBCAMgCYAAAGAAIJlBCAMgCYAAAuAAQKfyoAAwYACQmhFbk6ABUCAAYACQmhFbk6ABUCAAgABwnKD3wTAEMBAAAA.Alexa:BAAALgAECgQJBAAAAA==.Alfajhor:BAABLgAECn86AAMJAAgJFx+6EAC5AQAJAAYJoyK6EAC5AQAKAAgJZx0KYgCsAQAAAA==.Alfajhòr:BAAALgAECgIJAgAAAA==.Alfajhôr:BAAALgAECgUJBwAAAA==.Alkarin:BAAALgAECgEJAwAAAA==.Allandriel:BAAALgAECgQJBAAAAA==.Alldarion:BAAALgAECgMJCQAAAA==.Allendra:BAAALgADCgcJCQAAAA==.Alleriane:BAACLgAFFH8GAAILAAIJOherSACDAAALAAIJOherSACDAAAuAAQKfz0AAwsACQlEH7UIABADAAsACQlEH7UIABADAAwAAQmnApGNABgAAAAA.Allerios:BAAALgAECgUJCQAAAA==.Allone:BAACLgAFFH8GAAIFAAMJtwMMCQCRAAAFAAMJtwMMCQCRAAAuAAQKfyQAAgUACAk8EqUpADABAAUACAk8EqUpADABAAAA.Allyhra:BAAALgADCgQJBAAAAA==.Allëria:BAAALgADCgMJAwAAAA==.Alruna:BAAALgAECgEJAQAAAA==.',
Am='Ametnys:BAAALgAECgQJDAAAAA==.Amonhar:BAAALgAECgQJBQABLgAECgkJOwANAB4SAA==.Amyn:BAAALgADCgYJBwAAAA==.',
An='Anakata:BAABLgAECn8cAAQOAAYJ3RVhLAD+AAAOAAYJ3RVhLAD+AAACAAIJ+wW80QAzAAAPAAEJww8qjgAyAAAAAA==.Anakinini:BAABLgAECn8iAAIQAAgJbAk1RAAZAQAQAAgJbAk1RAAZAQABLgAECgYJDAAHAAAAAA==.Analia:BAABLgAECn8lAAQCAAgJFR5/HgBLAgACAAcJVR1/HgBLAgAOAAgJnQgHOADGAAAPAAUJxhsNBwCfAAABLgAFFAIJAgAHAAAAAA==.Andaliz:BAACLgAFFH8SAAIKAAMJwSbAMABQAQAKAAMJwSbAMABQAQAuAAQKfzYAAgoACQkLJjIDAGcDAAoACQkLJjIDAGcDAAEuAAUUBQkGAAoAWhcA.Andorith:BAAALgAECgEJAgAAAA==.Anelie:BAAALgAECgQJDQABLgAFFAIJAgAHAAAAAA==.Annhe:BAAALgAECgEJAQAAAA==.Ansalon:BAAALgADCgYJBwAAAA==.Anthorus:BAAALgAECgUJBgAAAA==.Antonellaes:BAAALgAECgUJCgABLgAECgcJDgAHAAAAAA==.',
Ao='Aoiisuu:BAAALgADCgYJCAAAAA==.',
Ap='Apodrecido:BAAALgAECgYJBgAAAA==.Apoxus:BAAALgADCgIJAgAAAA==.',
Ar='Arajakata:BAAALgAECgEJAwAAAA==.Arctorius:BAABLgAECn8VAAIKAAcJaw0IpwAtAQAKAAcJaw0IpwAtAQAAAA==.Arethiel:BAAALgADCgYJBgAAAA==.Arlandriah:BAAALgADCgYJCQABLgAECgYJGAAKABAYAA==.Artronis:BAACLgAFFH8JAAIOAAQJCwthHACuAAAOAAQJCwthHACuAAAuAAQKfyYAAw4ACAlPFhwVAKwBAA4ACAlPFhwVAKwBAAMAAQk9FDJOADwAAAAA.Artånis:BAAALgAECgcJDAAAAA==.Arukäi:BAAALgAECgQJBAAAAA==.Aruthuro:BAAALgAECgYJDwAAAA==.',
As='Ashbörn:BAAALgAECgQJBwAAAA==.Astel:BAABLgAECn8mAAIRAAkJNxazAQDpAQARAAkJNxazAQDpAQAAAA==.',
At='Atriuz:BAABLgAECn8bAAISAAYJahouLwDGAQASAAYJahouLwDGAQAAAA==.Ats:BAAALgAECgMJBQAAAA==.',
Ay='Aykho:BAABLgAECn8nAAITAAgJRRY7aACsAQATAAgJRRY7aACsAQAAAA==.',
Az='Azurion:BAAALgAECgYJCgAAAA==.',
['Aÿ']='Aÿ:BAAALgAECgMJBAAAAA==.',
Ba='Baguh:BAAALgADCggJCAAAAA==.Bagunça:BAAALgADCgYJBgAAAA==.Bakuugou:BAAALgAECgMJCgAAAA==.Balk:BAAALgAECgQJBAAAAA==.Balthar:BAAALgAECgIJAgAAAA==.Bambur:BAAALgADCgMJAwAAAA==.Barbabruto:BAABLgAECn8+AAIUAAkJZx5uBwCMAgAUAAkJZx5uBwCMAgAAAA==.Basilisco:BAAALgAECgEJAQAAAA==.',
Be='Belleg:BAAALgAECgEJAgAAAA==.Beronhuz:BAAALgAECgMJAwAAAA==.',
Bf='Bf:BAAALgAECgEJBAAAAA==.',
Bi='Biafalcão:BAAALgAECgEJAQAAAA==.Bijanca:BAAALgAECgYJBgAAAA==.Birthdäy:BAAALgADCgEJAQAAAA==.Bisponegro:BAAALgAECgQJCwABLgABCgcJFQAHAAAAAA==.Biønic:BAAALgAECgMJCQAAAA==.',
Bl='Blackline:BAACLgAFFH8FAAIGAAMJVwh5KQC/AAAGAAMJVwh5KQC/AAAuAAQKfyIAAgYACAlWE25hAKYBAAYACAlWE25hAKYBAAAA.',
Bo='Boipretim:BAAALgAECgYJDwAAAA==.Bontorius:BAAALgADCgEJAgAAAA==.Bordello:BAAALgADCgUJBQAAAA==.',
Br='Bradio:BAAALgADCggJCAAAAA==.Brahman:BAAALgAECgEJBAAAAA==.Bratloko:BAAALgAECgUJBQAAAA==.Braverne:BAAALgAECgEJAQAAAA==.Bromos:BAAALgAECgQJCAAAAA==.Brutalhoof:BAAALgAECgQJBAAAAA==.Brönsted:BAAALgADCgMJAwAAAA==.',
Bu='Bubbalo:BAAALgADCgUJBQAAAA==.Bullsman:BAAALgADCgQJBAAAAA==.Buzzumaaky:BAABLgAECn8YAAITAAgJTxepiQC/AQATAAgJTxepiQC/AQAAAA==.',
By='Byakura:BAAALgADCggJCwAAAA==.',
['Bü']='Büdweiser:BAAALgAECgcJEQAAAA==.',
Ca='Cabernet:BAAALgAECgUJBwAAAA==.Cabeçaquente:BAAALgAECgcJCQAAAA==.Cabinking:BAAALgAECgIJAgAAAA==.Calanthe:BAAALgADCgkJCQAAAA==.Calhistra:BAABLgAECn8nAAMVAAgJQxmBTAC1AQAVAAgJQxmBTAC1AQAWAAIJRQokVQBvAAAAAA==.Callstorm:BAAALgADCgcJBwAAAA==.Calteryeker:BAABLgAECn8aAAIKAAcJYhzRAwCyAQAKAAcJYhzRAwCyAQAAAA==.Camillas:BAAALgAECggJDwAAAA==.Caosenvy:BAAALgAECgEJAQAAAA==.Caralh:BAAALgAECgEJAgAAAA==.Caroll:BAAALgAECgIJAgAAAA==.Castaldi:BAAALgAECgEJAgABLgAECgcJCwAHAAAAAA==.Cathe:BAABLgAECn8aAAIXAAYJ6R0/YQCEAQAXAAYJ6R0/YQCEAQAAAA==.Caçaorda:BAAALgAECgIJAgAAAA==.',
Ce='Cecilith:BAAALgAECggJDQAAAA==.Cernunos:BAAALgADCgEJAQAAAA==.Cernûnnos:BAACLgAFFH8FAAICAAIJPRGMUwB3AAACAAIJPRGMUwB3AAAuAAQKfxUAAgIABglOD5RdAB4BAAIABglOD5RdAB4BAAAA.',
Ch='Champdude:BAABLgAECn9RAAQMAAkJqiPjAwAfAwAMAAkJqiPjAwAfAwAYAAgJJxuBEQAtAgALAAMJjR4VWwAIAQAAAA==.Changeman:BAAALgAECgEJAQAAAA==.Chankowkwai:BAAALgAECgYJCQAAAA==.Chanë:BAAALgADCgIJAwAAAA==.Chaosangel:BAAALgAECgUJCgABLgAFFAMJCgAPAMgHAA==.Chewi:BAAALgAECgQJBwAAAA==.Chrnnos:BAAALgAECgYJBgAAAA==.',
Ci='Citra:BAAALgAECgMJBwAAAA==.',
Co='Coconolose:BAAALgAECgIJBgAAAA==.Cod:BAAALgAECgIJAwAAAA==.Codecks:BAAALgADCgYJBgAAAA==.Coldbringer:BAAALgAECgEJAQAAAA==.Coldhearths:BAAALgAECgUJBgAAAA==.Couro:BAAALgAECgcJCgAAAA==.Cowçadora:BAAALgAECgMJAwAAAA==.',
Cr='Criminøsa:BAAALgAECgcJCQAAAA==.Cristcalad:BAABLgAECn9HAAMZAAkJkxm6CQBRAgAZAAkJfxi6CQBRAgAUAAcJEhcRAQC0AQAAAA==.Cryomanta:BAAALgAECgUJBQAAAA==.',
Cu='Cunhaovirado:BAAALgAECgcJEwABLgAFFAYJEQAMAOEXAA==.Cunhazinha:BAAALgAECgQJBAAAAA==.Cupyncha:BAAALgADCgcJBwAAAA==.Cutia:BAAALgADCgEJAQAAAA==.Cutiesissy:BAAALgAECgQJCAABLgAECgcJGgAKAEoQAA==.',
['Cø']='Cøøkye:BAAALgAECgQJBQAAAA==.',
Da='Daellus:BAAALgADCgUJBQAAAA==.Daemi:BAAALgAECgIJBAAAAA==.Daibodan:BAAALgAECgEJBAAAAA==.Dalaty:BAAALgAECgUJBQAAAA==.Daniilos:BAAALgAFFAEJAQAAAA==.Daresh:BAAALgADCgIJAgAAAA==.Darklara:BAABLgAECn8lAAIEAAkJBRkQCQDeAQAEAAkJBRkQCQDeAQAAAA==.Darkove:BAABLgAECn8vAAITAAkJjBIrVADgAQATAAkJjBIrVADgAQAAAA==.Darrow:BAACLgAFFH8SAAMGAAQJUh0iSgBeAQAGAAQJ+BsiSgBeAQAIAAMJdxyfEQAGAQAuAAQKfy8AAwYACQnPJP0PAOwCAAYACQn0I/0PAOwCAAgACAn8IloDALMCAAAA.Dartibeccoso:BAAALgADCgcJBwAAAA==.Daviberger:BAAALgAECgMJAwAAAA==.',
De='Deany:BAAALgAECgEJAgAAAA==.Deathinhu:BAABLgAECn9gAAITAAkJayFcAQDSAgATAAkJayFcAQDSAgAAAA==.Deathnacht:BAAALgAECgQJBwAAAA==.Delset:BAAALgADCgIJAgAAAA==.Demiun:BAAALgADCgUJBQAAAA==.Demojoca:BAAALgAECgIJAgABLgAECgcJDgAHAAAAAA==.Dentepodre:BAAALgADCgEJAQAAAA==.Dervus:BAAALgADCgcJBwAAAA==.Dethroned:BAAALgAECgUJDAAAAA==.Devrath:BAAALgAECgEJAQAAAA==.Devyogi:BAAALgADCgcJCAAAAA==.',
Di='Diefs:BAAALgAECgEJAQAAAA==.Dimeros:BAABLgAECn9CAAIPAAkJARNRAgBrAQAPAAkJARNRAgBrAQAAAA==.Dito:BAAALgADCgEJAQAAAA==.Divano:BAACLgAFFH8SAAIBAAMJ8hsGBgARAQABAAMJ8hsGBgARAQAuAAQKfzAAAwEACAnJH2cNAH4CAAEACAnJH2cNAH4CABoAAwkCCXJgAHwAAAAA.',
Dk='Dkats:BAAALgAECgEJAgAAAA==.',
Dn='Dng:BAAALgAECgcJCAAAAA==.',
Do='Dogowner:BAAALgAECgkJEgAAAA==.Dogs:BAAALgAFFAEJAwAAAA==.Donora:BAABLgAECn8sAAQKAAkJFRNpUwDPAQAKAAkJFRNpUwDPAQASAAEJfwN0kgAsAAAJAAEJKAYUXQAVAAAAAA==.',
Dr='Drackmontana:BAABLgAECn8lAAMbAAgJaA4gNgDQAQAbAAgJEg4gNgDQAQAUAAIJEhVBPQBjAAAAAA==.Drafael:BAAALgADCggJDgABLgAECgkJXQADAFoiAA==.Dragonfoox:BAAALgAECgIJAgAAAA==.Dragoniron:BAAALgADCgEJAQAAAA==.Dragony:BAAALgAECgEJBAAAAA==.Dragunass:BAABLgAECn9CAAMbAAkJXR4QEAB5AgAbAAkJXR4QEAB5AgAUAAcJkhq2EgDAAQAAAA==.Dragøndeath:BAAALgADCgEJAgAAAA==.Drakars:BAAALgADCgUJBAAAAA==.Dranarus:BAAALgADCgQJBAAAAA==.Drexus:BAAALgAECgQJBAAAAA==.Druidblack:BAAALgAECgIJAwAAAA==.Drunkler:BAAALgAECgYJBgAAAA==.Dryter:BAABLgAECn8VAAIMAAcJEA9QKwCEAQAMAAcJEA9QKwCEAQAAAA==.Drákon:BAAALgAECgEJAQAAAA==.',
Du='Dubhe:BAAALgAECgUJEQAAAA==.',
Dy='Dysttopia:BAAALgADCgcJCAAAAA==.',
El='Eldryrin:BAAALgAECgEJAQAAAA==.Elendile:BAAALgAECgEJAQAAAA==.Elinius:BAABLgAECn8vAAMPAAkJzSDQCADGAgAPAAkJzSDQCADGAgACAAIJUwyU2QArAAAAAA==.Elistraee:BAAALgAECgEJAQAAAA==.Ellandria:BAAALgAECgMJAwAAAA==.Ellonara:BAAALgAECgEJAQAAAA==.Ellvarg:BAAALgADCgQJBAAAAA==.Eloren:BAAALgAECgYJCwABLgAECggJIAASAPERAA==.Eluuria:BAAALgAFFAEJAQAAAA==.Elyzia:BAAALgAECgEJAQAAAA==.',
En='Endorena:BAAALgADCgEJAQAAAA==.Ensabanú:BAAALgAECgEJAQAAAA==.',
Ep='Ephesus:BAAALgADCgIJAgAAAA==.',
Er='Erikssen:BAAALgADCgYJBgAAAA==.Ernest:BAABLgAECn9VAAICAAkJVh+bAAC2AgACAAkJVh+bAAC2AgAAAA==.Erynneus:BAAALgADCgMJAwAAAA==.',
Es='Estagiario:BAAALgAECgQJBgABLgAFFAIJBQAFAMMYAA==.Estgan:BAAALgADCgYJBgAAAA==.',
Eu='Eusouobatman:BAAALgADCgIJAgAAAA==.',
Ev='Evetts:BAAALgADCgEJAQAAAA==.Evilbarba:BAABLgAFFH8FAAIKAAIJNBCkjwCTAAAKAAIJNBCkjwCTAAAAAA==.',
Ex='Exort:BAABLgAECn8gAAITAAYJlBUFEgCqAAATAAYJlBUFEgCqAAAAAA==.Exothus:BAAALgAECgEJAgAAAA==.Expressão:BAAALgADCgYJCwAAAA==.Exødus:BAAALgAECgEJAQAAAA==.',
Fa='Faeldar:BAACLgAFFH8PAAIaAAMJcQ8BEACoAAAaAAMJcQ8BEACoAAAuAAQKf0cAAhoACQk6F3UCAHkBABoACQk6F3UCAHkBAAAA.Faldark:BAAALgAECgYJDgAAAA==.Fandrall:BAAALgAECgUJCAAAAA==.Faris:BAABLgAFFH8KAAIcAAMJzw4VEQCGAAAcAAMJzw4VEQCGAAAAAA==.Farmfarm:BAAALgADCgEJAQAAAA==.Faver:BAAALgAECgQJBQAAAA==.Faölin:BAABLgAECn8nAAIcAAcJ1hyEGQDNAQAcAAcJ1hyEGQDNAQAAAA==.',
Fe='Feenigan:BAAALgAECgEJAQABLgAECgQJBAAHAAAAAA==.Feeniä:BAAALgAECgQJBAAAAA==.Ferael:BAABLgAECn9BAAMKAAkJZCLPDwDoAgAKAAkJZCLPDwDoAgASAAgJ2RqPAACNAgAAAA==.',
Fi='Fil:BAAALgAECgEJAQAAAA==.Firstomega:BAAALgADCgMJAwAAAA==.',
Fl='Flavors:BAACLgAFFH8GAAIbAAMJzyTlIAAvAQAbAAMJzyTlIAAvAQAuAAQKfyMAAxsACQndI+UHAOECABsACQndI+UHAOECABkABAkhHgIUAGYBAAAA.Florbela:BAAALgAECgUJCQAAAA==.Flämbë:BAAALgADCgEJAQAAAA==.',
Fo='Foemablack:BAAALgAECgQJBAAAAA==.Fogue:BAAALgAECgkJEgAAAA==.Foxthamy:BAABLgAECn8mAAILAAcJaxLKPAB8AQALAAcJaxLKPAB8AQAAAA==.',
Fr='Frachlitzz:BAACLgAFFH8IAAITAAMJ9Q21hQDNAAATAAMJ9Q21hQDNAAAuAAQKfz0AAhMACQkhFn86AC8CABMACQkhFn86AC8CAAAA.Fradem:BAAALgAECgcJDQAAAA==.Freccianera:BAAALgADCgEJAQAAAA==.Fredericc:BAABLgAECn8cAAMdAAkJlw/2RwCOAQAdAAgJYA72RwCOAQAeAAcJ2gVYWQDfAAAAAA==.Fredinho:BAAALgAECgEJAQAAAA==.Freecs:BAAALgAECgYJBwABLgAECgcJCwAHAAAAAA==.Freyá:BAABLgAECn8jAAIKAAkJcCGHFADHAgAKAAkJcCGHFADHAgAAAA==.Frostgore:BAAALgAECgEJAQAAAA==.Froststriker:BAAALgAECgEJAQAAAA==.Frozenn:BAAALgAECgUJBAABLgAECggJOAAMAMgZAA==.Frs:BAAALgAECgEJAgAAAA==.',
Ga='Galfur:BAAALgAECgEJAQAAAA==.Galhuda:BAAALgAECgUJCQAAAA==.Galyan:BAAALgADCgEJAQAAAA==.Gandalpha:BAAALgAECgUJBwAAAA==.Gandwelf:BAAALgADCgkJCQAAAA==.Gazieri:BAABLgAECn8gAAMSAAgJ8RFkRQBiAQASAAgJ8RFkRQBiAQAKAAQJCw/z2gDWAAAAAA==.',
Ge='Geisty:BAAALgAECgMJAwABLgAECgcJHwAGAIAJAA==.',
Gh='Ghalladriel:BAAALgADCgEJAwAAAA==.Ghruka:BAAALgAECgQJBAAAAA==.',
Gi='Giafar:BAAALgAECgEJAQABLgAECgYJDAAHAAAAAA==.Ginea:BAAALgAECgEJAQAAAA==.',
Gl='Gluke:BAAALgAECgMJAwAAAA==.Glutotwo:BAAALgADCgQJBgAAAA==.',
Gn='Gnomari:BAABLgAECn8kAAIVAAgJJQL35ACTAAAVAAgJJQL35ACTAAAAAA==.',
Go='Goratrix:BAAALgAECgUJBQABLgAECgcJHwAGAIAJAA==.Gordanado:BAAALgAECgEJAgAAAA==.Gordruida:BAAALgAECgEJAQAAAA==.Govers:BAAALgADCgMJAwABLgAECgMJBAAHAAAAAA==.',
Gr='Grandecoisa:BAAALgAECgEJAQAAAA==.Greyfin:BAAALgAECgEJAwAAAA==.Greyvor:BAAALgADCgEJAQAAAA==.Grimch:BAAALgAECgEJAQAAAA==.Grumax:BAABLgAECn8UAAIKAAgJyQ/FdACRAQAKAAgJyQ/FdACRAQAAAA==.Grymysa:BAAALgAECgIJAgAAAA==.Grössa:BAABLgAECn8YAAMSAAcJIwiGWwAOAQASAAcJIwiGWwAOAQAKAAMJCQRdhgE5AAABLgAECgkJFwAVAJ8IAA==.',
Gu='Gugsã:BAAALgAECgEJAgAAAA==.Guitianki:BAAALgAECgEJAQAAAA==.Gulek:BAAALgAECgQJBAAAAA==.Gussg:BAABLgAECn8XAAQVAAkJnwgmZwBvAQAVAAkJnwgmZwBvAQAfAAEJzwgcQwArAAAWAAIJGQTpRgAeAAAAAA==.Gustavonz:BAAALgADCgcJBwAAAA==.',
['Gö']='Göhan:BAAALgADCgUJBQABLgAECgYJEwAHAAAAAA==.',
['Gø']='Gøvers:BAAALgAECgMJBAAAAA==.',
Ha='Hakuouki:BAAALgAECgMJAwAAAA==.Handyman:BAAALgADCgYJCgAAAA==.Hantom:BAAALgADCgYJBgABLgAFFAYJEQAMAOEXAA==.Hazell:BAAALgADCgYJBgAAAA==.',
He='Heaveth:BAAALgAECgMJAwABLgAFFAMJCwAeAP4cAA==.Hefestion:BAAALgAFFAIJAwAAAA==.Hellspont:BAAALgAECgMJAwAAAA==.Helsingdarck:BAAALgADCgIJAgAAAA==.Hendrikison:BAAALgAECgcJCgAAAA==.',
Hi='Hildegyth:BAABLgAECn8fAAMMAAgJWBE1MQBhAQAMAAcJWRE1MQBhAQALAAUJZxG8WwAGAQAAAA==.',
Hj='Hjalmar:BAAALgADCgcJCQAAAA==.',
Ho='Hodtiva:BAABLgAECn8tAAMBAAgJdBDeLQBqAQABAAgJdBDeLQBqAQANAAUJDA5QTgCpAAAAAA==.Homerz:BAAALgADCgEJAQAAAA==.Horagalles:BAAALgAECgEJAQAAAA==.Hotmojo:BAABLgAECn8eAAITAAgJOw+5eQCFAQATAAgJOw+5eQCFAQABLgAFFAUJDwAeAE0cAA==.',
Hu='Hunfox:BAACLgAFFH8VAAIXAAMJUR9pCwAHAQAXAAMJUR9pCwAHAQAuAAQKf0QAAhcACQmuI78JAAoDABcACQmuI78JAAoDAAAA.',
['Hä']='Härkness:BAAALgAECgYJCAAAAA==.',
['Hø']='Høolligans:BAAALgAECgEJAQAAAA==.',
['Hü']='Hüskar:BAABLgAECn8fAAMbAAkJ/AuTMQCGAQAbAAkJuQuTMQCGAQAZAAEJCg8JfAAtAAAAAA==.',
Ic='Icechips:BAAALgADCgUJBQAAAA==.Ichigoz:BAABLgAECn8iAAITAAkJBQqscgCUAQATAAkJBQqscgCUAQAAAA==.',
Ih='Ihntwuaed:BAAALgADCgYJCQAAAA==.',
Ik='Ikoo:BAABLgAECn9WAAIaAAkJkSB0AADnAgAaAAkJkSB0AADnAgAAAA==.',
Il='Illaril:BAACLgAFFH8mAAIEAAYJIx2xAQC3AQAEAAYJIx2xAQC3AQAuAAQKf2UAAgQACQmMIWQCANcCAAQACQmMIWQCANcCAAAA.',
In='Indarion:BAAALgADCgYJEQAAAA==.Ingratt:BAAALgAECgEJAgAAAA==.Invisiblelol:BAAALgAECgIJAgAAAA==.',
Ir='Irmãodouther:BAAALgAFFAIJAwAAAA==.Irontoko:BAAALgAECgYJBgAAAA==.',
Is='Isebby:BAAALgADCgMJAwAAAA==.Ishtarie:BAAALgAECgQJBQABLgAECgkJHgACAJkXAA==.',
It='Itzzdan:BAAALgADCgMJAwAAAA==.',
Iv='Ivina:BAACLgAFFH8GAAIVAAMJNw0zGADNAAAVAAMJNw0zGADNAAAuAAQKfxQAAxUACAlOFvCRADUBABUABwlOFvCRADUBAB8AAgmpF7gcAI0AAAAA.',
Iz='Izaar:BAAALgAECgQJDwAAAA==.',
Ja='Jacsonnaik:BAAALgAECgQJBQAAAA==.Jadelina:BAAALgAECgEJAQAAAA==.Janaìna:BAAALgAECgMJAwAAAA==.Jangeoffry:BAAALgADCgEJAQAAAA==.Jaymee:BAAALgAECgEJAQAAAA==.',
Jh='Jhonatinha:BAABLgAECn8VAAMKAAcJBxkN3gDgAAAKAAYJaxkN3gDgAAASAAQJng69dgCfAAAAAA==.',
Ji='Jigsaww:BAAALgAECgQJCQAAAA==.',
Jk='Jks:BAAALgAECgUJCgAAAA==.',
Jo='Joaquim:BAAALgAECgIJAgAAAA==.Jogaveiopl:BAAALgADCgIJAgAAAA==.Johnlobo:BAAALgAECgEJAQAAAA==.Joventino:BAAALgADCgQJBQAAAA==.',
Ju='Jucah:BAABLgAECn8ZAAIeAAkJZAt6OwBIAQAeAAkJZAt6OwBIAQAAAA==.Julabolseiro:BAABLgAECn8WAAMNAAgJ+wyPLQBgAQANAAgJ+wyPLQBgAQABAAIJBgJAiQAwAAAAAA==.Julinhas:BAAALgAECgEJAQAAAA==.Jullianxd:BAAALgAECgMJAwABLgAECgkJFgARAOwPAA==.',
Ka='Kaallew:BAABLgAECn8ZAAIJAAkJuRccGABdAQAJAAkJuRccGABdAQAAAA==.Kaezar:BAAALgADCgEJAQAAAA==.Kainer:BAAALgAECgQJBgAAAA==.Kalazshar:BAABLgAECn8mAAIOAAkJbBI0FgCiAQAOAAkJbBI0FgCiAQAAAA==.Kalelzinho:BAAALgADCgYJCAAAAA==.Kaluss:BAABLgAECn8XAAITAAgJyQbzEQCrAAATAAgJyQbzEQCrAAAAAA==.Kanalet:BAAALgAECgYJCAAAAA==.Kandára:BAAALgADCgYJBgAAAA==.Kantaa:BAAALgAECgQJDAAAAA==.Kanturu:BAAALgAECgQJBAAAAA==.Kanzaki:BAAALgADCgcJBwABLgAECgkJUQAMAKojAA==.Karonn:BAABLgAECn8UAAIKAAYJ/A3mlABTAQAKAAYJ/A3mlABTAQAAAA==.Kavartu:BAAALgAECgYJDAAAAA==.Kaymon:BAAALgAECgEJAQAAAA==.',
Ke='Keillor:BAABLgAECn8pAAMdAAgJGRaYRQCXAQAdAAcJWRSYRQCXAQAeAAYJXRqCLwCCAQAAAA==.Kelantir:BAAALgAECgYJCQABLgAECgkJDAAHAAAAAA==.Keldorian:BAAALgADCgcJEAAAAA==.Kelishe:BAAALgAECgUJBQAAAA==.Kelliar:BAAALgAECgIJAQAAAA==.Kelorn:BAAALgADCgYJBgABLgAECggJFwAdAMIQAA==.Kelysa:BAAALgADCgkJDgABLgAECggJQgAUACYdAA==.Kenzou:BAABLgAECn8YAAMYAAcJ0hhDMQA9AQAYAAUJexxDMQA9AQAMAAcJSQ/0OAAeAQAAAA==.',
Kh='Khadi:BAAALgAECgcJCwAAAA==.Khaeltaz:BAAALgAECgMJAwAAAA==.Khalandra:BAABLgAECn8eAAIbAAkJaBtyKwAIAgAbAAkJaBtyKwAIAgAAAA==.Khalel:BAAALgADCgEJAgAAAA==.Khaliq:BAABLgAECn8eAAMFAAkJVxV5FADtAQAFAAkJVxV5FADtAQARAAQJLApxrwCtAAAAAA==.Khallani:BAABLgAECn8fAAIGAAcJgAlLlQBWAQAGAAcJgAlLlQBWAQAAAA==.Khamul:BAAALgAECgQJBgAAAA==.Khaos:BAAALgAECggJEwAAAA==.Khisto:BAABLgAECn80AAMTAAkJnRsqOQA0AgATAAkJnRsqOQA0AgAgAAcJ3Rf5BACSAQAAAA==.Khroriggs:BAAALgAECgYJDQABLgAECgcJBwAHAAAAAA==.Khrøna:BAAALgADCgIJAgABLgAECgcJBwAHAAAAAA==.',
Ki='Kieran:BAAALgAECgMJAwAAAA==.Killerbiie:BAAALgADCgIJAgAAAA==.Killerdown:BAAALgADCgIJAgAAAA==.Kimashi:BAAALgAECgUJBQAAAA==.Kindie:BAAALgADCgcJCwABLgAECggJFAARABEIAA==.Kisam:BAAALgAECgYJBwAAAA==.Kissme:BAACLgAFFH8FAAMPAAMJ2AkNQgBuAAAPAAIJdwgNQgBuAAAOAAEJmwxTQgAmAAAuAAQKfx4AAw8ACQmYEE0tAG8BAA8ACAneEU0tAG8BAA4ABAmICAhHAI0AAAAA.Kitamor:BAABLgAECn9ZAAIPAAkJeRObAQCxAQAPAAkJeRObAQCxAQAAAA==.Kiya:BAAALgADCgcJHgAAAA==.',
Kl='Klorokina:BAAALgAECgYJBgAAAA==.',
Ko='Kooraqt:BAAALgAECgQJBAAAAA==.Koriakin:BAABLgAECn8vAAMXAAkJIR3QEADKAgAXAAkJIR3QEADKAgAhAAcJBxigGQDSAQAAAA==.Kosmo:BAAALgAECgcJCQAAAA==.Kotalkhan:BAAALgADCgkJEQAAAA==.',
Kr='Krosmu:BAAALgADCgcJBwAAAA==.Krov:BAAALgAECgEJAQAAAA==.Kryon:BAAALgAECgYJDgAAAA==.Kryzthor:BAAALgAECgYJCAAAAA==.Kräsus:BAABLgAECn9DAAIUAAkJAibtAABiAwAUAAkJAibtAABiAwAAAA==.Krønna:BAAALgAECgQJBAABLgAECgYJKQAiAEsIAA==.',
Ku='Kul:BAAALgAECgUJBgAAAA==.Kuthila:BAAALgADCgIJAgAAAA==.',
Ky='Kyzaru:BAAALgAECgIJAgAAAA==.',
['Kÿ']='Kÿdou:BAAALgAECgcJDgAAAA==.',
La='Ladrion:BAABLgAECn9WAAQjAAkJtR+HAQDfAgAjAAkJvB6HAQDfAgAcAAkJAxmFFABuAgAkAAkJ9RflBAA6AgAAAA==.Laetus:BAABLgAECn8ZAAIlAAcJqxdpCAAXAQAlAAcJqxdpCAAXAQAAAA==.Lagosta:BAAALgAECgMJBgAAAA==.Laiany:BAABLgAECn9MAAINAAkJJSISBABFAwANAAkJJSISBABFAwAAAA==.Lani:BAAALgAECgEJAQAAAA==.',
Le='Legacia:BAAALgADCgYJBgAAAA==.Lekrom:BAAALgADCgYJBgAAAA==.Leodoros:BAAALgAECgQJBAAAAA==.Lequinhö:BAAALgAECgIJAgAAAA==.Leric:BAAALgADCgcJCgAAAA==.Lethmar:BAABLgAECn8eAAIVAAcJMxerXQCGAQAVAAcJMxerXQCGAQAAAA==.Levanah:BAABLgAFFH8IAAIXAAYJFAIrWwDuAAAXAAYJFAIrWwDuAAAAAA==.Leyana:BAAALgAECgUJBwAAAA==.',
Lh='Lhwei:BAAALgAECgIJAgABLgAFFAQJEAALAMMYAA==.',
Li='Liandra:BAAALgAECgEJAQAAAA==.Licaon:BAAALgADCgYJDgAAAA==.Lichkiller:BAAALgAECgUJBQAAAA==.Lichkíng:BAAALgAECgYJBgAAAA==.Lightbreaker:BAABLgAECn8jAAIKAAkJZAipiQBdAQAKAAkJZAipiQBdAQAAAA==.Lihr:BAAALgADCgYJCQAAAA==.Lilianpotter:BAAALgAECgEJAQAAAA==.Lilithrix:BAAALgADCgIJAgAAAA==.Lillit:BAABLgAECn9HAAQfAAkJahEkDgB6AQAVAAkJ/A8JUwCjAQAfAAgJ9w0kDgB6AQAWAAIJvwYwPQA3AAAAAA==.Lindaah:BAABLgAECn84AAMMAAgJyBkqFgAGAgAMAAgJyBkqFgAGAgALAAYJBwzTDgCCAAAAAA==.Lindademon:BAAALgAECgUJDwAAAA==.Lindahealer:BAAALgAECgUJCgABLgAECgUJDwAHAAAAAA==.Lislfox:BAABLgAECn9AAAIOAAkJbBrPCABfAgAOAAkJbBrPCABfAgAAAA==.Lithlad:BAAALgADCgIJAgAAAA==.',
Lk='Lkinho:BAAALgAECgMJBAAAAA==.',
Lm='Lmmds:BAAALgAECgUJCwAAAA==.',
Lo='Lockynha:BAAALgADCgEJAQAAAA==.Lonän:BAAALgAECgQJBAAAAA==.Loohynir:BAABLgAFFH8FAAICAAIJFQlzXABiAAACAAIJFQlzXABiAAAAAA==.Lotusbird:BAAALgADCgcJBwAAAA==.',
Lu='Lucario:BAAALgAECgEJAgAAAA==.Luccoa:BAAALgAECgkJEwABLgAECgkJQwAUAAImAA==.Luccyah:BAAALgADCgkJDgAAAA==.Lucifïr:BAAALgAECgEJAQAAAA==.Lucileia:BAAALgAECgQJBQAAAA==.Lukazgplay:BAAALgADCgIJAgAAAA==.Lutsul:BAAALgAECgEJAQAAAA==.',
Ly='Lylka:BAABLgAECn9HAAMJAAkJ0SWoAABlAwAJAAkJ0SWoAABlAwASAAMJIiM5RAAwAQAAAA==.Lyrrena:BAAALgAECgMJBwAAAA==.',
Ma='Maanu:BAAALgAECgcJDwABLgAECggJOAAMAMgZAA==.Maclaw:BAAALgADCgEJAQAAAA==.Macumbadora:BAAALgAECgQJCgAAAA==.Madfulock:BAABLgAECn8UAAIVAAcJiBh4XwCBAQAVAAcJiBh4XwCBAQAAAA==.Maeghann:BAAALgADCgMJAwAAAA==.Magalândia:BAAALgAECgIJAgAAAA==.Magraver:BAAALgAECgMJAwAAAA==.Mais:BAAALgAECgEJAQAAAA==.Makani:BAAALgAECgUJBgAAAA==.Malewolyyc:BAACLgAFFH8IAAMNAAIJyR6KJACYAAANAAIJyR6KJACYAAABAAEJZgfsPQA9AAAuAAQKfysAAw0ACQmZIXYMAJ8CAA0ACAk/I3YMAJ8CAAEABglGEYk6ACkBAAEuAAUUAwkDAAcAAAAA.Malhun:BAAALgADCgUJDgAAAA==.Malphan:BAAALgAECgcJBwAAAA==.Malyguz:BAACLgAFFH8UAAITAAQJ1BKpXQAkAQATAAQJ1BKpXQAkAQAuAAQKfxsAAhMABwldG+BgABkCABMABwldG+BgABkCAAAA.Malévolaa:BAAALgAECgYJBwAAAA==.Manipullador:BAAALgAECgIJAgAAAA==.Mapussauro:BAAALgAECgcJEQAAAA==.Maradi:BAAALgADCgIJAgAAAA==.Mariob:BAABLgAFFH8GAAImAAIJEAWhOwBIAAAmAAIJEAWhOwBIAAAAAA==.Marjøly:BAAALgAECgEJAQAAAA==.Markson:BAAALgADCgEJAQAAAA==.Massafera:BAABLgAECn8fAAIKAAkJMxP4WgC8AQAKAAkJMxP4WgC8AQAAAA==.Mather:BAAALgAECgEJAQAAAA==.Mathfacbruxo:BAABLgAECn9NAAIVAAkJFhzVGQCJAgAVAAkJFhzVGQCJAgAAAA==.Mauritiuz:BAAALgAFFAEJAQAAAA==.Mayanyy:BAAALgAECgEJAQAAAA==.',
Mc='Mcq:BAAALgAECgEJAQAAAA==.',
Md='Mdrdark:BAACLgAFFH8NAAIGAAUJlxSMaAAoAQAGAAUJlxSMaAAoAQAuAAQKfy0AAwYACQmiGRkxADoCAAYACQmiGRkxADoCACYAAwm/FVhIAGwAAAAA.',
Me='Medz:BAABLgAECn8jAAITAAkJlRqKMQBTAgATAAkJlRqKMQBTAgAAAA==.Meedea:BAAALgADCgUJBgAAAA==.Meetjack:BAAALgAECgEJAgAAAA==.Meiyin:BAAALgAECgcJEAAAAA==.Melania:BAAALgAECgEJAgAAAA==.Melissandra:BAAALgAFFAIJAwAAAA==.Mellkor:BAABLgAECn8qAAIFAAkJQhv+DABWAgAFAAkJQhv+DABWAgAAAA==.Melytah:BAAALgAECgEJAgAAAA==.Melzynhaa:BAAALgAECgEJAwABLgAECggJOAAMAMgZAA==.Meraxxes:BAAALgADCgcJDAAAAA==.Merellien:BAAALgADCggJDgAAAA==.Mestreioda:BAAALgAECgQJBAAAAA==.Metamorful:BAABLgAECn8ZAAICAAkJBxL/SQB7AQACAAkJBxL/SQB7AQAAAA==.',
Mh='Mhorgann:BAAALgAECgUJBgAAAA==.',
Mi='Mijonakombi:BAABLgAECn8WAAIKAAkJ/hpnLwBDAgAKAAkJ/hpnLwBDAgAAAA==.Mikveh:BAAALgAECgYJCgAAAA==.Milim:BAABLgAECn9BAAQQAAkJ8hMlHgDmAQAQAAkJ2RIlHgDmAQAnAAgJRQ2GDwATAQAoAAEJyQUYBgAjAAAAAA==.Milliidan:BAAALgADCgUJBQAAAA==.Mindrathys:BAAALgAECgEJAQAAAA==.Mithrius:BAABLgAECn8kAAIKAAgJxxHvcACMAQAKAAgJxxHvcACMAQAAAA==.',
Ml='Mls:BAAALgAECgUJBgAAAA==.',
Mo='Mogrus:BAAALgAECgQJBAAAAA==.Mohanna:BAAALgAECgkJEAAAAA==.Mohanninha:BAAALgAECgYJCwAAAA==.Mohotok:BAABLgAECn9VAAIKAAkJSBncJwBkAgAKAAkJSBncJwBkAgAAAA==.Moonøvesso:BAAALgAECgIJBQAAAA==.Moopp:BAAALgADCgcJCAAAAA==.Mortixxia:BAABLgAECn8oAAIWAAgJnx0kBABCAgAWAAgJnx0kBABCAgAAAA==.',
Mu='Muata:BAAALgAECgYJDwAAAA==.Muf:BAAALgAECgYJBgAAAA==.Mupar:BAAALgADCgIJAgAAAA==.Murano:BAABLgAECn8yAAMbAAkJxR75DQCQAgAbAAkJxR75DQCQAgAZAAMJywp/VQCBAAAAAA==.Muzzo:BAAALgADCgYJCwABLgAECgcJEgAHAAAAAA==.',
My='Myrmïdom:BAAALgAECgIJAgAAAA==.Myzoreh:BAAALgAECggJDAAAAA==.',
['Má']='Mágico:BAAALgAECgEJAwAAAA==.Máia:BAABLgAECn8UAAIWAAgJiAxrEQAvAQAWAAgJiAxrEQAvAQAAAA==.',
['Mä']='Mändosz:BAABLgAECn8ZAAMGAAkJMRKYbgCIAQAGAAgJahKYbgCIAQAIAAMJCRB0JACsAAAAAA==.',
['Mé']='Ménace:BAACLgAFFH8FAAIVAAMJPhfybQDmAAAVAAMJPhfybQDmAAAuAAQKfxUAAxUACQnmHfZaALcBABUACAnmHfZaALcBABYAAwlcDvJGAJoAAAAA.',
['Mÿ']='Mÿstyna:BAAALgAECgEJAQAAAA==.',
Na='Nalathiel:BAABLgAECn8UAAINAAgJ+gzvMwA2AQANAAgJ+gzvMwA2AQAAAA==.Narancia:BAAALgAECgYJDQABLgAECgcJCwAHAAAAAA==.Naryth:BAAALgAECgYJCAAAAA==.Nassur:BAAALgADCgEJAQAAAA==.Nattaliaa:BAAALgAECgEJAQAAAA==.Nazawill:BAAALgAECgQJBAAAAA==.Nazdru:BAAALgADCgMJAwABLgAECgkJXQADAFoiAA==.Nazzh:BAAALgAECgEJAQABLgAECgQJBQAHAAAAAA==.',
Ne='Necronx:BAAALgAECgEJAQAAAA==.Necronxd:BAAALgADCgEJAgAAAA==.Nefas:BAABLgAECn8jAAIWAAkJYxPnBwDSAQAWAAkJYxPnBwDSAQAAAA==.Nefazo:BAAALgAECgcJCgAAAA==.Nefilo:BAAALgADCgYJEAAAAA==.Nepthunus:BAABLgAECn9JAAIgAAkJuyGEAAAXAwAgAAkJuyGEAAAXAwAAAA==.Nermand:BAAALgAECgEJAQAAAA==.Neshula:BAAALgADCgMJAwAAAA==.Neuvosor:BAAALgAECgEJAQAAAA==.',
Ni='Nibelunga:BAAALgADCgYJBgAAAA==.Nijor:BAAALgADCgYJBgAAAA==.Nilsonssbnu:BAAALgAECgEJAQAAAA==.',
No='Nobelnaga:BAAALgAECgMJAwAAAA==.Noovaatoo:BAAALgAFFAEJAQAAAA==.Noria:BAAALgAECgEJAQAAAA==.Novatoo:BAAALgAFFAEJAQAAAA==.',
Ny='Nyobb:BAAALgADCgMJAwAAAA==.Nyxra:BAAALgADCgcJEAAAAA==.',
['Në']='Nëcros:BAAALgAECgcJCwAAAA==.',
['Nö']='Nöirr:BAAALgAECgUJBwAAAA==.',
Oc='Ocelotte:BAAALgADCgEJAQAAAA==.',
Od='Odin:BAAALgAECgEJAQAAAA==.Odynsabio:BAAALgAECgEJAQAAAA==.',
Of='Ofanzitsu:BAAALgADCgQJBAAAAA==.',
Oi='Oioimiguel:BAAALgAECgUJBQAAAA==.',
Ol='Olhua:BAAALgAECgMJCAAAAA==.Oljedvlad:BAAALgADCgEJAQAAAA==.Oluss:BAAALgADCgUJBQABLgAFFAMJFQAXAFEfAA==.',
Om='Omnath:BAAALgADCgYJBgAAAA==.',
Or='Orillan:BAABLgAECn9OAAMFAAkJIBtlCwBwAgAFAAkJIBtlCwBwAgARAAEJhAcY5gAsAAAAAA==.Ornsteinsnow:BAABLgAECn8ZAAISAAkJvhSJHAAfAgASAAkJvhSJHAAfAgAAAA==.Orob:BAABLgAECn8WAAICAAYJhQm+eQDKAAACAAYJhQm+eQDKAAAAAA==.Ororah:BAAALgAECgYJEAAAAA==.Orsonn:BAAALgAECgYJDAAAAA==.Orukam:BAABLgAECn8ZAAMCAAkJMBYvRACAAQACAAgJ7BQvRACAAQAPAAMJTgjAaAB9AAAAAA==.',
Os='Oszwald:BAAALgADCgEJAQAAAA==.',
['Oú']='Oúkürä:BAAALgAECgYJCgAAAA==.',
Pa='Padawani:BAAALgAECgMJAwAAAA==.Padgodeira:BAAALgAECgQJBAAAAA==.Padrealpha:BAAALgADCgcJCgAAAA==.Padrekelmøn:BAAALgAECgQJBAAAAA==.Palaha:BAAALgADCgEJAQABLgAFFAMJFQAXAFEfAA==.Palantír:BAAALgAECgEJAQAAAA==.Palatina:BAABLgAFFH8GAAIKAAUJWhenQgAmAQAKAAUJWhenQgAmAQAAAA==.Palazzy:BAAALgAECgEJAgAAAA==.Pandong:BAAALgAECggJEAAAAA==.Panena:BAAALgAECgIJAwAAAA==.Pangedrey:BAABLgAECn9UAAMMAAkJOCBjCADBAgAMAAkJOCBjCADBAgAYAAcJJQRzTQDJAAAAAA==.Paracepatrol:BAAALgAECgQJAwAAAA==.Parcival:BAACLgAFFH8LAAIXAAMJoBokVwD4AAAXAAMJoBokVwD4AAAuAAQKfzsAAhcACQm8I44AACYDABcACQm8I44AACYDAAAA.Parký:BAAALgAECgcJCAAAAA==.Pattalógika:BAAALgAECgEJAQAAAA==.Paullk:BAABLgAECn8gAAIPAAYJchQQPQAcAQAPAAYJchQQPQAcAQAAAA==.',
Pe='Pedrinho:BAAALgADCgYJBgABLgAFFAUJEwARACIgAA==.Penseur:BAAALgAECggJDgAAAA==.Penéllope:BAAALgAECgQJBwAAAA==.Persëphone:BAABLgAECn8VAAMNAAcJsRTjPQD6AAANAAUJyRDjPQD6AAABAAYJCBKDXAClAAAAAA==.Peruchi:BAAALgAECgQJBAAAAA==.',
Pg='Pgms:BAAALgAECgUJBQAAAA==.',
Ph='Phacozitos:BAAALgAECgEJAgAAAA==.Phaxe:BAAALgADCgIJAgAAAA==.Phoenicx:BAAALgADCgMJBgAAAA==.Phøënïx:BAAALgAECgcJDAAAAA==.',
Pi='Pipelinebr:BAAALgAECgUJBQAAAA==.Pitombinha:BAAALgAECgEJBAAAAA==.',
Pl='Plumalume:BAAALgADCgYJBgAAAA==.',
Po='Powalker:BAAALgAECgEJAgAAAA==.Powertell:BAAALgAECgMJAwABLgAECgkJHQAMAMoSAA==.',
Pp='Pp:BAABLgAFFH8TAAQaAAUJngmTIgA7AQAaAAUJngmTIgA7AQABAAIJ4wYXMwB4AAANAAEJ6wCPPQAlAAABLgAFFAYJIwAaAPYXAA==.',
Pr='Prometeus:BAAALgAECgYJDwAAAA==.Pryon:BAAALgAECgUJCwAAAA==.',
Pt='Ptollomeu:BAAALgAECgMJBQABLgAECgMJCQAHAAAAAA==.',
['Pä']='Pändero:BAABLgAECn8WAAILAAYJ8yIIGgBHAgALAAYJ8yIIGgBHAgAAAA==.Pänqueca:BAAALgAECgEJAgAAAA==.',
['Pé']='Pénacova:BAAALgADCgEJAQAAAA==.',
['Pî']='Pîo:BAACLgAFFH8IAAITAAMJVxE6gADWAAATAAMJVxE6gADWAAAuAAQKfxcAAxMACAltGVZiALoBABMACAl5GFZiALoBACUABAnTGPAKACwBAAAA.',
Qu='Quejerok:BAAALgAECgYJEwAAAA==.',
Ra='Radiação:BAAALgAECgUJBQAAAA==.Radunz:BAABLgAECn9dAAIDAAkJWiIrAADuAgADAAkJWiIrAADuAgAAAA==.Ragnaros:BAABLgAFFH8FAAISAAIJAxAxOwB4AAASAAIJAxAxOwB4AAAAAA==.Ragnarssön:BAAALgAFFAEJAQAAAA==.Raineko:BAAALgADCgYJBgAAAA==.Raio:BAACLgAFFH8FAAITAAIJlxNbogCKAAATAAIJlxNbogCKAAAuAAQKfy8AAhMACQkEIfIdAKkCABMACQkEIfIdAKkCAAAA.Ralfwur:BAAALgAECgQJBwAAAA==.Ramsez:BAAALgAECgEJAQAAAA==.Rargsa:BAABLgAECn8dAAIIAAgJfAaNGQAHAQAIAAgJfAaNGQAHAQAAAA==.Rariel:BAAALgADCgIJAgAAAA==.Rasmon:BAABLgAECn8uAAIVAAkJRxTAQwDQAQAVAAkJRxTAQwDQAQAAAA==.Ravendreth:BAAALgADCgEJAQAAAA==.Raykarla:BAAALgAECgIJAwAAAA==.Raymain:BAACLgAFFH8GAAMMAAMJzh1PGwDxAAAMAAMJzh1PGwDxAAALAAEJkw6vZgAuAAAuAAQKfyQAAwsACQkSFqw9AHkBAAsACAmaFKw9AHkBAAwABwkXFrc4AB8BAAAA.Raíka:BAAALgAECgYJEAAAAA==.',
Re='Reddnose:BAAALgAECgUJCQAAAA==.Reinhold:BAABLgAECn8bAAMKAAcJYRTBewB3AQAKAAcJYRTBewB3AQASAAUJ2Qj8WwDGAAAAAA==.',
Rh='Rhuryk:BAAALgADCggJCAAAAA==.',
Ri='Ricktdai:BAAALgAECgEJAQAAAA==.Riesze:BAACLgAFFH8KAAIXAAMJoRGZXwDlAAAXAAMJoRGZXwDlAAAuAAQKfycAAhcACQl9GWshAGACABcACQl9GWshAGACAAAA.',
Ro='Roguinhu:BAAALgAFFAEJAQAAAA==.Ropaoo:BAABLgAECn8XAAIWAAYJEhbMDwBDAQAWAAYJEhbMDwBDAQAAAA==.',
Ru='Rua:BAAALgAECgQJBAAAAA==.Rurumo:BAAALgAECgcJBwAAAA==.Rusga:BAAALgADCggJCgAAAA==.Rustovick:BAAALgAECgMJBgAAAA==.',
Ry='Rytheas:BAAALgAECgQJBgAAAA==.',
['Rä']='Rämzä:BAAALgAECgYJEwAAAA==.',
['Rå']='Råy:BAAALgAECgQJCQAAAA==.',
['Rí']='Rízadinha:BAAALgAECgQJBAAAAA==.',
Sa='Saargeras:BAAALgADCgMJAwAAAA==.Saffír:BAABLgAECn8pAAIKAAkJTRhBNgAoAgAKAAkJTRhBNgAoAgAAAA==.Saiden:BAAALgADCgQJBAAAAA==.Saintkaue:BAAALgADCgUJCAAAAA==.Sairoz:BAAALgAECgEJAQAAAA==.Samalandraa:BAAALgADCgEJAQAAAA==.Sanahh:BAAALgAECgYJCAAAAA==.Sanateia:BAAALgADCgYJCwAAAA==.Santamadre:BAAALgADCgEJAQAAAA==.Sapekinhä:BAACLgAFFH8FAAIFAAIJwxj3IQCLAAAFAAIJwxj3IQCLAAAuAAQKfywABAUACQlJI70EAPoCAAUACQlJI70EAPoCAAQAAglSGOwjAH8AABEAAglFCR/5AFQAAAAA.Satanvitória:BAABLgAECn8uAAMZAAgJ7B5tDAAgAgAbAAcJYRo0JgAoAgAZAAgJbh5tDAAgAgAAAA==.Sauroth:BAAALgADCgUJCQAAAA==.',
Sc='Scheiren:BAAALgAECgQJBgAAAA==.',
Se='Senegos:BAAALgADCgcJBwAAAA==.Sereiaa:BAABLgAECn8qAAIXAAgJCA8WZQB6AQAXAAgJCA8WZQB6AQAAAA==.Sesiom:BAAALgAECgcJBgAAAA==.',
Sh='Shalltearr:BAAALgADCgEJAQAAAA==.Shamana:BAAALgAECgEJAQAAAA==.Shamate:BAAALgAFFAEJAQAAAA==.Shanoa:BAAALgAECgMJAwAAAA==.Sharae:BAAALgADCgMJBAAAAA==.Shariany:BAAALgADCgEJAQAAAA==.Sharpersong:BAAALgADCgcJBgAAAA==.Shedo:BAABLgAECn8VAAMZAAgJAxovFwCiAQAZAAcJuBkvFwCiAQAbAAYJWg+VYgAoAQAAAA==.Sheevane:BAABLgAECn8eAAICAAkJmResJAAnAgACAAkJmResJAAnAgAAAA==.Shinzo:BAAALgADCgEJAQAAAA==.Shonja:BAAALgADCgcJDgAAAA==.Shula:BAAALgADCgcJDQAAAA==.Shumuk:BAAALgAECgEJAQAAAA==.Shÿnara:BAAALgAECgkJDwAAAA==.',
Si='Siclop:BAAALgADCgYJBgAAAA==.Silgris:BAAALgAECgEJAQABLgAECggJIAASAPERAA==.Silmeria:BAABLgAECn8dAAIdAAkJdAZUXwA+AQAdAAkJdAZUXwA+AQAAAA==.Silverchain:BAAALgADCgcJCgAAAA==.Sinton:BAAALgAECgQJCAAAAA==.',
Sk='Skadryan:BAAALgAECgEJAQAAAA==.Skeletowman:BAAALgADCgUJBQAAAA==.Skineh:BAAALgAECgQJBwAAAA==.Skinme:BAABLgAECn8UAAILAAYJKwQhjACDAAALAAYJKwQhjACDAAAAAA==.',
Sm='Smylf:BAAALgAECgkJEAAAAA==.',
Sn='Snakedown:BAAALgAECgEJAgAAAA==.',
So='Sombrea:BAAALgAECgYJEgAAAA==.',
Sp='Spectrø:BAAALgAECgYJBgAAAA==.',
Sr='Srheal:BAAALgAECgQJBAAAAA==.Srsapo:BAAALgAECgMJBgAAAA==.',
Ss='Ssamara:BAAALgAECgYJBgAAAA==.',
St='Stampede:BAAALgADCgMJAwAAAA==.Starian:BAABLgAECn8gAAMCAAcJKRwtJQAjAgACAAcJKRwtJQAjAgAPAAEJywwTfwAzAAAAAA==.Straider:BAAALgAECgEJAQAAAA==.Stëlla:BAABLgAECn8vAAIdAAgJ3RS6LwD2AQAdAAgJ3RS6LwD2AQAAAA==.',
Su='Suckmyhammer:BAAALgAECgYJDQAAAA==.Sunnara:BAACLgAFFH8TAAIRAAUJIiB+MwBXAQARAAUJIiB+MwBXAQAuAAQKfyIAAhEACQnwITwKAPgCABEACQnwITwKAPgCAAAA.Superkx:BAAALgAECgQJBQAAAA==.Suzanomu:BAAALgADCgYJCwAAAA==.',
Sy='Sylran:BAAALgADCgQJBgAAAA==.Synk:BAAALgADCgQJBAAAAA==.Syofra:BAAALgAECgQJBQAAAA==.Syrelys:BAAALgADCgYJBgAAAA==.Syuon:BAACLgAFFH8QAAILAAQJwxh/KwAVAQALAAQJwxh/KwAVAQAuAAQKfzMAAwsACQkiIQYGAEYDAAsACQkiIQYGAEYDAAwAAgmQBqSKAEcAAAAA.',
['Së']='Sëkhmet:BAAALgAECgYJCwAAAA==.',
['Sï']='Sïmbä:BAABLgAECn8bAAMGAAkJjQ4DdQB6AQAGAAkJjQ4DdQB6AQAIAAEJkAShGQAoAAABLgAFFAEJAQAHAAAAAA==.',
['Só']='Sósummono:BAAALgADCgYJBwAAAA==.',
['Sÿ']='Sÿkies:BAAALgADCgEJAQAAAA==.',
Ta='Talandar:BAABLgAECn8/AAIPAAkJSxyVAAChAgAPAAkJSxyVAAChAgAAAA==.Tankudo:BAABLgAECn8dAAIGAAgJJxOmhQBYAQAGAAgJJxOmhQBYAQAAAA==.Tannia:BAAALgADCgIJAgAAAA==.Tanthallas:BAAALgAECgEJAQAAAA==.Tavindapedra:BAAALgAECgYJCwAAAA==.',
Tc='Tchutchuco:BAAALgAECgIJAwAAAA==.',
Te='Tekzero:BAAALgAECgEJCAAAAA==.Tempestus:BAAALgADCgYJBgAAAA==.Tennebra:BAAALgAECgEJAQAAAA==.Teobaldo:BAAALgADCgYJCgAAAA==.Terron:BAABLgAECn8yAAMdAAkJEBYjIgBCAgAdAAkJEBYjIgBCAgAeAAIJnRc6dQCMAAAAAA==.',
Th='Thabitah:BAABLgAECn9XAAIBAAkJNiBwAAC8AgABAAkJNiBwAAC8AgAAAA==.Thaliath:BAAALgADCgQJBAAAAA==.Thallariel:BAAALgAECgQJBwAAAA==.Theteo:BAABLgAECn8ZAAIKAAkJZQumggBqAQAKAAkJZQumggBqAQAAAA==.Thiberios:BAAALgAECgUJDAAAAA==.Thirros:BAAALgADCgUJBQAAAA==.Thorres:BAAALgAECgMJBwAAAA==.Thotamon:BAAALgAECgQJCAAAAA==.Throin:BAAALgAECgMJAwAAAA==.Thràain:BAAALgAECgcJDgAAAA==.Thuki:BAAALgAECgEJAQAAAA==.Thunderblade:BAAALgAECgYJDgAAAA==.Thuska:BAAALgADCgYJBgAAAA==.Théus:BAAALgAECgMJAwABLgAFFAMJBQAVAD4XAA==.',
Ti='Tiramisu:BAAALgAECgcJCwAAAA==.',
To='Torâo:BAABLgAECn8XAAIIAAcJ6gh/AgDOAAAIAAcJ6gh/AgDOAAAAAA==.Toucinho:BAAALgAECgYJDgAAAA==.',
Tr='Traydd:BAABLgAECn8iAAIDAAgJlBWoDgDKAQADAAgJlBWoDgDKAQAAAA==.Trollando:BAAALgAECgUJCAAAAA==.',
Tu='Tuga:BAAALgADCgMJAwAAAA==.Turokk:BAABLgAECn8oAAIXAAgJmhNuDADxAAAXAAgJmhNuDADxAAAAAA==.',
Tw='Twilight:BAAALgADCgYJDQAAAA==.Twylluch:BAAALgADCgQJBgABLgAECgkJKAASAOsXAA==.',
['Të']='Tëmys:BAAALgADCgEJAQAAAA==.',
Ul='Ulhim:BAAALgADCgcJEwAAAA==.',
Ur='Uriuri:BAAALgADCgYJBgABLgAECgkJXQADAFoiAA==.',
Us='Usfull:BAABLgAECn87AAMNAAkJHhJ0JQCZAQANAAgJYhN0JQCZAQABAAgJFg0fLwBjAQAAAA==.',
Va='Vacavelha:BAAALgAECgEJAQAAAA==.Vahtorn:BAAALgAECgMJBgAAAA==.Valaerys:BAAALgAECgUJCgAAAA==.Valaniri:BAAALgADCgEJAQAAAA==.Vallkÿria:BAAALgAECgYJBwAAAA==.Vanheelsen:BAAALgAFFAIJAgAAAA==.Vanyathariel:BAAALgAECgEJAQAAAA==.Vareena:BAAALgADCggJCAABLgAECgkJQwAUAAImAA==.Vashiel:BAAALgADCgIJAgAAAA==.',
Ve='Vehuiáh:BAABLgAECn8eAAMSAAgJMB0ZHQAbAgASAAgJMB0ZHQAbAgAKAAEJRQQFwgEjAAAAAA==.Velen:BAABLgAECn8bAAIGAAgJnBEnkwBAAQAGAAgJnBEnkwBAAQAAAA==.Vellkor:BAAALgADCgYJBgAAAA==.Vellon:BAAALgADCgEJAQAAAA==.Venrique:BAAALgAECgQJBAABLgAECgYJEQAHAAAAAA==.Venusa:BAAALgADCgMJBAAAAA==.Verno:BAAALgADCgcJCwAAAA==.Verzuk:BAABLgAECn8dAAIGAAgJPQqWjABMAQAGAAgJPQqWjABMAQAAAA==.',
Vi='Vidnands:BAAALgAECgEJAQAAAA==.Viinyy:BAAALgAECgMJAwAAAA==.Vilthor:BAAALgAECgUJBQAAAA==.Vintekilo:BAABLgAECn8YAAIKAAkJzRaiYgC9AQAKAAkJzRaiYgC9AQAAAA==.',
Vo='Voiddh:BAAALgAECgcJDAAAAA==.Vokeshar:BAAALgADCgUJBQAAAA==.Voltadupla:BAAALgAECgQJBQAAAA==.Voop:BAAALgADCgYJFAAAAA==.',
Vr='Vrenshrrgn:BAAALgADCgYJCQAAAA==.',
Vu='Vulcânico:BAAALgADCgUJCQAAAA==.',
Vy='Vygh:BAACLgAFFH8JAAIVAAMJmBXHdQDWAAAVAAMJmBXHdQDWAAAuAAQKfy0AAxUACQm5IVYOANoCABUACQm5IVYOANoCABYAAQkjDzpwADYAAAAA.Vyndrill:BAAALgAECgYJDgAAAA==.',
['Vä']='Välion:BAAALgADCgIJAgAAAA==.',
Wa='Wacom:BAAALgADCgUJBQAAAA==.Walkers:BAAALgAECgkJDgAAAA==.Warlaka:BAAALgAECgUJCwAAAA==.Warpiel:BAAALgADCgcJDAABLgAECgkJHgAaAC0OAA==.Wartigeer:BAAALgAECgEJAQAAAA==.Watchtower:BAAALgAECgQJBAAAAA==.',
We='Wenus:BAAALgAECgIJAgAAAA==.',
Wh='Wheez:BAAALgAECgQJBAABLgAECgkJNAATAJ0bAA==.',
Wi='Williem:BAAALgADCgYJEwAAAA==.',
Wo='Worthy:BAAALgADCgQJBAAAAA==.',
['Wä']='Wätanabe:BAAALgAECgQJBAAAAA==.',
Xa='Xafado:BAAALgAECgEJAQAAAA==.Xamalandrö:BAAALgAECgQJCwAAAA==.',
Xe='Xeal:BAAALgADCgEJAQAAAA==.Xehagus:BAAALgADCgcJCgAAAA==.',
Xi='Xiblaublum:BAAALgADCgMJAwAAAA==.Xinhagoo:BAAALgAECgMJAwAAAA==.Xiquimiro:BAAALgADCgQJBAAAAA==.',
Xx='Xximperadorx:BAAALgADCgIJAgAAAA==.',
Ya='Yasuoh:BAAALgAECgQJCAAAAA==.',
Ye='Yewner:BAAALgADCgYJBQAAAA==.',
Yi='Yingsu:BAABLgAECn8ZAAIYAAkJeCLRDgBNAgAYAAkJeCLRDgBNAgAAAA==.',
Yo='Yoshihime:BAAALgAECgIJAgABLgAECgkJHgACAJkXAA==.',
Yv='Yvin:BAAALgAECgMJBAAAAA==.',
Za='Zallmo:BAACLgAFFH8FAAIbAAMJTQVDPQC4AAAbAAMJTQVDPQC4AAAuAAQKfyMAAhsACAl/FaMkANABABsACAl/FaMkANABAAAA.Zarath:BAAALgAECgUJBgAAAA==.Zawarudo:BAAALgAECgYJCgAAAA==.',
Ze='Zedd:BAAALgAFFAIJAgAAAA==.Zenorclord:BAAALgADCgQJBgAAAA==.Zeytona:BAABLgAECn8jAAIYAAkJjAuLJgB6AQAYAAkJjAuLJgB6AQAAAA==.',
Zi='Ziracruz:BAAALgAECgQJCwAAAA==.',
['Zí']='Zíngara:BAAALgAECgEJAQAAAA==.',
['Ár']='Árÿä:BAABLgAECn9VAAIXAAkJURVkMQAWAgAXAAkJURVkMQAWAgAAAA==.',
['Är']='Äraxy:BAAALgAECgMJBgAAAA==.',
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
