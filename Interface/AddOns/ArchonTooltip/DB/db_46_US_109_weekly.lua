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

local lookup = {'Priest-Shadow','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Unholy','Druid-Restoration','DeathKnight-Frost','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Druid-Guardian','Druid-Balance','Evoker-Augmentation','Unknown-Unknown','Druid-Feral','DemonHunter-Devourer','Paladin-Holy','Mage-Frost','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Monk-Brewmaster','Warrior-Arms','Priest-Discipline','Warrior-Fury','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Mage-Fire','Hunter-Survival','Shaman-Enhancement','Rogue-Outlaw','Rogue-Assassination','Mage-Arcane','DeathKnight-Blood','Evoker-Devastation',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abelao:BAAALgAECgcJEwAAAA==.',
Ad='Adelaide:BAAALgAECgIJAgABLgAFFAcJGgABALAaAA==.Adoramuss:BAAALgAECgYJCwAAAA==.Adrianoj:BAAALgAECgEJAQAAAA==.',
Ae='Aeklug:BAAALgADCgcJCAAAAA==.Aelon:BAAALgADCgcJDAAAAA==.Aelthor:BAAALgAECgQJEAAAAA==.Aemeath:BAABLgAECn8XAAMCAAkJiyHXAQD8AgACAAkJiyHXAQD8AgADAAIJnhgASgCOAAAAAA==.',
Ah='Ahammes:BAAALgAECgQJBAABLgAECgcJHwAEAIAJAA==.Ahmus:BAAALgAECgUJDAAAAA==.Ahrallu:BAAALgADCgEJAgAAAA==.',
Ai='Aioliavictus:BAAALgADCgIJAgAAAA==.',
Ak='Akaynu:BAAALgAECgEJAQAAAA==.',
Al='Alanie:BAAALgAECgUJDQABLgAECggJJQAFABUeAA==.Aldranir:BAAALgADCgEJAQAAAA==.Alessaxd:BAACLgAFFH8IAAIEAAIJlBCqGgBPAAAEAAIJlBCqGgBPAAAuAAQKfykAAwQACQmhFbQ6ABUCAAQACQmhFbQ6ABUCAAYABwnKD3wTAEMBAAAA.Alexa:BAAALgAECgQJBAAAAA==.Alfajhor:BAABLgAECn86AAMHAAgJFx+6EAC5AQAHAAYJoyK6EAC5AQAIAAgJZx0NYgCsAQAAAA==.Alfajhòr:BAAALgAECgIJAgAAAA==.Alfajhôr:BAAALgAECgUJBwAAAA==.Alkarin:BAAALgAECgEJAwAAAA==.Allandriel:BAAALgAECgUJBQAAAA==.Alldarion:BAAALgAECgMJCQAAAA==.Allendra:BAAALgADCgcJCQAAAA==.Alleriane:BAACLgAFFH8GAAIJAAIJOhelSACDAAAJAAIJOhelSACDAAAuAAQKfzwAAwkACQlEH7cIABADAAkACQlEH7cIABADAAoAAQmnApGNABgAAAAA.Allerios:BAAALgAECgUJCQAAAA==.Allone:BAABLgAECn8jAAIDAAcJ5xKfKQAwAQADAAcJ5xKfKQAwAQAAAA==.Allyhra:BAAALgADCgQJBAAAAA==.Allëria:BAAALgADCgMJAwAAAA==.Alruna:BAAALgAECgEJAQAAAA==.',
Am='Ametnys:BAAALgAECgQJDAAAAA==.Amonhar:BAAALgAECgQJBQABLgAECgkJOwALAB4SAA==.Amyn:BAAALgADCgYJBwAAAA==.',
An='Anakata:BAABLgAECn8cAAQMAAYJ3RViLAD+AAAMAAYJ3RViLAD+AAAFAAIJ+wW90QAzAAANAAEJww8njgAyAAAAAA==.Anakinini:BAABLgAECn8hAAIOAAgJbAkzRAAZAQAOAAgJbAkzRAAZAQABLgAECgYJDAAPAAAAAA==.Analia:BAABLgAECn8lAAQFAAgJFR5/HgBLAgAFAAcJVR1/HgBLAgAMAAgJnQgFOADGAAANAAUJxhunAgCfAAAAAA==.Andaliz:BAACLgAFFH8SAAIIAAMJwSbNMABQAQAIAAMJwSbNMABQAQAuAAQKfzYAAggACQkLJjEDAGcDAAgACQkLJjEDAGcDAAEuAAUUBQkGAAgAWhcA.Andorith:BAAALgAECgEJAgAAAA==.Anelie:BAAALgAECgQJDQABLgAECggJJQAFABUeAA==.Annhe:BAAALgAECgEJAQAAAA==.Ansalon:BAAALgADCgYJBwAAAA==.Anthorus:BAAALgAECgUJBgAAAA==.Antonellaes:BAAALgAECgUJCgABLgAECgcJDgAPAAAAAA==.',
Ao='Aoiisuu:BAAALgADCgYJCAAAAA==.',
Ap='Apodrecido:BAAALgAECgYJBgAAAA==.Apoxus:BAAALgADCgIJAgAAAA==.',
Ar='Arajakata:BAAALgAECgEJAwAAAA==.Arctorius:BAABLgAECn8UAAIIAAcJeQsJpwAtAQAIAAcJeQsJpwAtAQAAAA==.Arethiel:BAAALgADCgYJBgAAAA==.Arlandriah:BAAALgADCgYJCQABLgAECgYJGAAIABAYAA==.Artronis:BAACLgAFFH8JAAIMAAQJCwtfHACuAAAMAAQJCwtfHACuAAAuAAQKfyYAAwwACAlPFhwVAKwBAAwACAlPFhwVAKwBABAAAQk9FDNOADwAAAAA.Artånis:BAAALgAECgcJDAAAAA==.Arukäi:BAAALgADCgYJBgAAAA==.Aruthuro:BAAALgAECgYJDwAAAA==.',
As='Ashbörn:BAAALgAECgQJBwAAAA==.Astel:BAABLgAECn8dAAIRAAkJlBICNgDuAQARAAkJlBICNgDuAQAAAA==.',
At='Atriuz:BAABLgAECn8bAAISAAYJahouLwDGAQASAAYJahouLwDGAQAAAA==.Ats:BAAALgAECgMJBQAAAA==.',
Ay='Aykho:BAABLgAECn8nAAITAAgJRRY6aACsAQATAAgJRRY6aACsAQAAAA==.',
Az='Azurion:BAAALgAECgYJCgAAAA==.',
['Aÿ']='Aÿ:BAAALgAECgMJBAAAAA==.',
Ba='Baguh:BAAALgADCggJCAAAAA==.Bagunça:BAAALgADCgYJBgAAAA==.Bakuugou:BAAALgAECgMJCgAAAA==.Balk:BAAALgAECgQJBAAAAA==.Balthar:BAAALgAECgIJAgAAAA==.Bambur:BAAALgADCgMJAwAAAA==.Barbabruto:BAABLgAECn8+AAIUAAkJZx5xBwCMAgAUAAkJZx5xBwCMAgAAAA==.Basilisco:BAAALgAECgEJAQAAAA==.',
Be='Belleg:BAAALgAECgEJAgAAAA==.Beronhuz:BAAALgAECgMJAwAAAA==.',
Bf='Bf:BAAALgAECgEJAwAAAA==.',
Bi='Biafalcão:BAAALgAECgEJAQAAAA==.Bijanca:BAAALgAECgYJBgAAAA==.Birthdäy:BAAALgADCgEJAQAAAA==.Bisponegro:BAAALgAECgQJCwABLgABCgcJFQAPAAAAAA==.Biønic:BAAALgAECgMJCQAAAA==.',
Bl='Blackline:BAABLgAECn8iAAIEAAgJVhNsYQCmAQAEAAgJVhNsYQCmAQAAAA==.',
Bo='Boipretim:BAAALgAECgYJDwAAAA==.Bontorius:BAAALgADCgEJAgAAAA==.Bordello:BAAALgADCgUJBQAAAA==.',
Br='Bradio:BAAALgADCggJCAAAAA==.Brahman:BAAALgAECgEJBAAAAA==.Bratloko:BAAALgAECgUJBQAAAA==.Bromos:BAAALgAECgQJCAAAAA==.Brutalhoof:BAAALgAECgQJBAAAAA==.Brönsted:BAAALgADCgMJAwAAAA==.',
Bu='Bubbalo:BAAALgADCgUJBQAAAA==.Bullsman:BAAALgADCgQJBAAAAA==.Buzzumaaky:BAABLgAECn8YAAITAAgJTxepiQC/AQATAAgJTxepiQC/AQAAAA==.',
By='Byakura:BAAALgADCggJCwAAAA==.',
['Bü']='Büdweiser:BAAALgAECgcJEQAAAA==.',
Ca='Cabernet:BAAALgAECgUJBwAAAA==.Cabeçaquente:BAAALgAECgcJCQAAAA==.Cabinking:BAAALgAECgIJAgAAAA==.Calanthe:BAAALgADCgkJCQAAAA==.Calhistra:BAABLgAECn8nAAMVAAgJQxmBTAC1AQAVAAgJQxmBTAC1AQAWAAIJRQokVQBvAAAAAA==.Callstorm:BAAALgADCgcJBwAAAA==.Calteryeker:BAABLgAECn8UAAIIAAcJGRUNcwCIAQAIAAcJGRUNcwCIAQAAAA==.Camillas:BAAALgAECggJDwAAAA==.Caosenvy:BAAALgAECgEJAQAAAA==.Caralh:BAAALgAECgEJAgAAAA==.Caroll:BAAALgAECgIJAgAAAA==.Castaldi:BAAALgAECgEJAgABLgAECgcJCwAPAAAAAA==.Cathe:BAABLgAECn8aAAIXAAYJ6R1EYQCEAQAXAAYJ6R1EYQCEAQAAAA==.Caçaorda:BAAALgAECgIJAgAAAA==.',
Ce='Cecilith:BAAALgAECggJCwAAAA==.Cernûnnos:BAACLgAFFH8FAAIFAAIJPRGPUwB3AAAFAAIJPRGPUwB3AAAuAAQKfxUAAgUABglOD5hdAB4BAAUABglOD5hdAB4BAAAA.',
Ch='Champdude:BAABLgAECn9PAAQKAAkJqiPjAwAfAwAKAAkJqiPjAwAfAwAYAAgJJxuAEQAtAgAJAAMJjR4UWwAIAQAAAA==.Changeman:BAAALgAECgEJAQAAAA==.Chankowkwai:BAAALgAECgYJCQAAAA==.Chanë:BAAALgADCgIJAwAAAA==.Chaosangel:BAAALgAECgUJCgABLgAFFAMJCgANAMgHAA==.Chewi:BAAALgAECgQJBwAAAA==.Chrnnos:BAAALgAECgEJAQAAAA==.',
Ci='Citra:BAAALgAECgMJBwAAAA==.',
Co='Coconolose:BAAALgAECgIJBgAAAA==.Cod:BAAALgAECgIJAwAAAA==.Codecks:BAAALgADCgYJBgAAAA==.Coldbringer:BAAALgAECgEJAQAAAA==.Coldhearths:BAAALgAECgUJBgAAAA==.Couro:BAAALgAECgcJCgAAAA==.Cowçadora:BAAALgADCgIJAQAAAA==.',
Cr='Criminøsa:BAAALgAECgcJCQAAAA==.Cristcalad:BAABLgAECn9HAAMZAAkJkxm8CQBRAgAZAAkJfxi8CQBRAgAUAAcJEhdlAAC+AQAAAA==.Cryomanta:BAAALgAECgUJBQAAAA==.',
Cu='Cunhaovirado:BAAALgAECgYJDwABLgAFFAYJEQAKAOEXAA==.Cunhazinha:BAAALgAECgQJBAAAAA==.Cupyncha:BAAALgADCgcJBwAAAA==.Cutia:BAAALgADCgEJAQAAAA==.Cutiesissy:BAAALgAECgQJCAABLgAECgcJGgAIAEoQAA==.',
['Cø']='Cøøkye:BAAALgAECgQJBQAAAA==.',
Da='Daellus:BAAALgADCgUJBQAAAA==.Daemi:BAAALgAECgIJBAAAAA==.Daibodan:BAAALgAECgEJBAAAAA==.Dalaty:BAAALgAECgUJBQAAAA==.Daniilos:BAAALgAFFAEJAQAAAA==.Daresh:BAAALgADCgIJAgAAAA==.Darklara:BAABLgAECn8lAAICAAkJBRkQCQDeAQACAAkJBRkQCQDeAQAAAA==.Darkove:BAABLgAECn8uAAITAAkJjBIrVADgAQATAAkJjBIrVADgAQAAAA==.Darrow:BAACLgAFFH8SAAMEAAQJUh0rSgBeAQAEAAQJ+BsrSgBeAQAGAAMJdxyfEQAGAQAuAAQKfy8AAwQACQnPJPsPAOwCAAQACQn0I/sPAOwCAAYACAn8IloDALMCAAAA.Dartibeccoso:BAAALgADCgcJBwAAAA==.Daviberger:BAAALgAECgMJAwAAAA==.',
De='Deany:BAAALgAECgEJAgAAAA==.Deathinhu:BAABLgAECn9XAAITAAkJox9tEwDlAgATAAkJox9tEwDlAgAAAA==.Deathnacht:BAAALgAECgQJBwAAAA==.Delset:BAAALgADCgIJAgAAAA==.Demiun:BAAALgADCgUJBQAAAA==.Demojoca:BAAALgAECgIJAgABLgAECgcJDgAPAAAAAA==.Dentepodre:BAAALgADCgEJAQAAAA==.Dervus:BAAALgADCgcJBwAAAA==.Dethroned:BAAALgAECgUJDAAAAA==.Devrath:BAAALgAECgEJAQAAAA==.Devyogi:BAAALgADCgcJCAAAAA==.',
Di='Diefs:BAAALgAECgEJAQAAAA==.Dimeros:BAABLgAECn82AAINAAkJexCgIQC7AQANAAkJexCgIQC7AQAAAA==.Dito:BAAALgADCgEJAQAAAA==.Divano:BAACLgAFFH8OAAIBAAMJ1hUzBABwAAABAAMJ1hUzBABwAAAuAAQKfzAAAwEACAnJH2gNAH4CAAEACAnJH2gNAH4CABoAAwkCCXBgAHwAAAAA.',
Dk='Dkats:BAAALgAECgEJAgAAAA==.',
Dn='Dng:BAAALgAECgcJCAAAAA==.',
Do='Dogowner:BAAALgAECgkJEgAAAA==.Donora:BAABLgAECn8sAAQIAAkJFRNsUwDPAQAIAAkJFRNsUwDPAQASAAEJfwN3kgAsAAAHAAEJKAYUXQAVAAAAAA==.',
Dr='Drackmontana:BAABLgAECn8lAAMbAAgJaA4gNgDQAQAbAAgJEg4gNgDQAQAUAAIJEhVBPQBjAAAAAA==.Drafael:BAAALgADCggJDgABLgAECgkJVAAQAOQhAA==.Dragoniron:BAAALgADCgEJAQAAAA==.Dragony:BAAALgAECgEJBAAAAA==.Dragunass:BAABLgAECn8+AAMbAAkJjx0PEAB5AgAbAAkJjx0PEAB5AgAUAAcJkhq3EgDAAQAAAA==.Dragøndeath:BAAALgADCgEJAgAAAA==.Drakars:BAAALgADCgUJBAAAAA==.Dranarus:BAAALgADCgQJBAAAAA==.Drexus:BAAALgAECgQJBAAAAA==.Druidblack:BAAALgAECgIJAwAAAA==.Drunkler:BAAALgAECgYJBgAAAA==.Dryter:BAABLgAECn8VAAIKAAcJEA9QKwCEAQAKAAcJEA9QKwCEAQAAAA==.Drákon:BAAALgADCgUJBgAAAA==.',
Du='Dubhe:BAAALgAECgUJEAAAAA==.',
Dy='Dysttopia:BAAALgADCgcJCAAAAA==.',
El='Eldryrin:BAAALgAECgEJAQAAAA==.Elendile:BAAALgAECgEJAQAAAA==.Elinius:BAABLgAECn8vAAMNAAkJzSDQCADGAgANAAkJzSDQCADGAgAFAAIJUwyW2QArAAAAAA==.Elistraee:BAAALgAECgEJAQAAAA==.Ellandria:BAAALgAECgMJAwAAAA==.Ellonara:BAAALgAECgEJAQAAAA==.Ellvarg:BAAALgADCgQJBAAAAA==.Eloren:BAAALgAECgYJCwABLgAECggJIAASAPERAA==.Eluuria:BAAALgAFFAEJAQAAAA==.Elyzia:BAAALgAECgEJAQAAAA==.',
En='Endorena:BAAALgADCgEJAQAAAA==.',
Ep='Ephesus:BAAALgADCgIJAgAAAA==.',
Er='Erikssen:BAAALgADCgYJBgAAAA==.Ernest:BAABLgAECn9MAAIFAAkJOR+SCAAvAwAFAAkJOR+SCAAvAwAAAA==.Erynneus:BAAALgADCgMJAwAAAA==.',
Es='Estagiario:BAAALgAECgQJBgABLgAFFAIJBQADAMMYAA==.Estgan:BAAALgADCgYJBgAAAA==.',
Eu='Eusouobatman:BAAALgADCgIJAgAAAA==.',
Ev='Evetts:BAAALgADCgEJAQAAAA==.Evilbarba:BAABLgAFFH8FAAIIAAIJNBCkjwCTAAAIAAIJNBCkjwCTAAAAAA==.',
Ex='Exort:BAABLgAECn8cAAITAAYJFhVhmwBDAQATAAYJFhVhmwBDAQAAAA==.Exothus:BAAALgAECgEJAgAAAA==.Expressão:BAAALgADCgYJCwAAAA==.Exødus:BAAALgAECgEJAQAAAA==.',
Fa='Faeldar:BAACLgAFFH8LAAIaAAMJYQ2wNAC5AAAaAAMJYQ2wNAC5AAAuAAQKf0QAAhoACQkCFgIBAFUBABoACQkCFgIBAFUBAAAA.Faldark:BAAALgAECgYJDgAAAA==.Fandrall:BAAALgAECgUJCAAAAA==.Faris:BAABLgAFFH8IAAIcAAIJ2xLXMAChAAAcAAIJ2xLXMAChAAAAAA==.Farmfarm:BAAALgADCgEJAQAAAA==.Faver:BAAALgAECgQJBQAAAA==.Faölin:BAABLgAECn8nAAIcAAcJ1hyCGQDNAQAcAAcJ1hyCGQDNAQAAAA==.',
Fe='Feenigan:BAAALgAECgEJAQABLgAECgQJBAAPAAAAAA==.Feeniä:BAAALgAECgQJBAAAAA==.Ferael:BAABLgAECn84AAIIAAkJTCLNDwDoAgAIAAkJTCLNDwDoAgAAAA==.',
Fi='Fil:BAAALgAECgEJAQAAAA==.Firstomega:BAAALgADCgMJAwAAAA==.',
Fl='Flavors:BAACLgAFFH8GAAIbAAMJzyTsIAAvAQAbAAMJzyTsIAAvAQAuAAQKfyMAAxsACQndI+MHAOECABsACQndI+MHAOECABkABAkhHgIUAGYBAAAA.Florbela:BAAALgAECgUJCQAAAA==.Flämbë:BAAALgADCgEJAQAAAA==.',
Fo='Foemablack:BAAALgAECgQJBAAAAA==.Fogue:BAAALgAECgkJEgAAAA==.Foxthamy:BAABLgAECn8mAAIJAAcJaxLHPAB8AQAJAAcJaxLHPAB8AQAAAA==.',
Fr='Frachlitzz:BAACLgAFFH8IAAITAAMJ9Q3ShQDNAAATAAMJ9Q3ShQDNAAAuAAQKfz0AAhMACQkhFoI6AC8CABMACQkhFoI6AC8CAAAA.Fradem:BAAALgAECgcJDQAAAA==.Freccianera:BAAALgADCgEJAQAAAA==.Fredericc:BAABLgAECn8bAAMdAAkJCg/yRwCOAQAdAAgJwQ3yRwCOAQAeAAcJ2gVYWQDfAAAAAA==.Fredinho:BAAALgAECgEJAQAAAA==.Freecs:BAAALgAECgYJBwABLgAECgcJCwAPAAAAAA==.Freyá:BAABLgAECn8jAAIIAAkJcCGGFADHAgAIAAkJcCGGFADHAgAAAA==.Frostgore:BAAALgAECgEJAQAAAA==.Froststriker:BAAALgAECgEJAQAAAA==.Frs:BAAALgAECgEJAgAAAA==.',
Ga='Galhuda:BAAALgAECgUJBQAAAA==.Galyan:BAAALgADCgEJAQAAAA==.Gandalpha:BAAALgAECgUJBwAAAA==.Gandwelf:BAAALgADCgkJCQAAAA==.Gazieri:BAABLgAECn8gAAMSAAgJ8RFkRQBiAQASAAgJ8RFkRQBiAQAIAAQJCw/z2gDWAAAAAA==.',
Ge='Geisty:BAAALgAECgMJAwABLgAECgcJHwAEAIAJAA==.',
Gh='Ghalladriel:BAAALgADCgEJAwAAAA==.Ghruka:BAAALgAECgQJBAAAAA==.',
Gi='Giafar:BAAALgAECgEJAQABLgAECgYJDAAPAAAAAA==.Ginea:BAAALgAECgEJAQAAAA==.',
Gl='Gluke:BAAALgAECgMJAwAAAA==.Glutotwo:BAAALgADCgQJBgAAAA==.',
Gn='Gnomari:BAABLgAECn8jAAIVAAgJFwL25ACTAAAVAAgJFwL25ACTAAAAAA==.',
Go='Goratrix:BAAALgAECgUJBQABLgAECgcJHwAEAIAJAA==.Gordanado:BAAALgAECgEJAgAAAA==.Gordruida:BAAALgAECgEJAQAAAA==.Govers:BAAALgADCgMJAwABLgAECgMJBAAPAAAAAA==.',
Gr='Grandecoisa:BAAALgAECgEJAQAAAA==.Greyfin:BAAALgAECgEJAgAAAA==.Greyvor:BAAALgADCgEJAQAAAA==.Grimch:BAAALgAECgEJAQAAAA==.Grumax:BAABLgAECn8UAAIIAAgJyQ/FdACRAQAIAAgJyQ/FdACRAQAAAA==.Grymysa:BAAALgAECgIJAgAAAA==.Grössa:BAABLgAECn8YAAMSAAcJIwiGWwAOAQASAAcJIwiGWwAOAQAIAAMJCQRZhgE5AAABLgAECgkJFwAVAJ8IAA==.',
Gu='Gugsã:BAAALgAECgEJAgAAAA==.Guitianki:BAAALgAECgEJAQAAAA==.Gulek:BAAALgAECgQJBAAAAA==.Gussg:BAABLgAECn8XAAQVAAkJnwglZwBvAQAVAAkJnwglZwBvAQAfAAEJzwgeQwArAAAWAAIJGQTpRgAeAAAAAA==.Gustavonz:BAAALgADCgcJBwAAAA==.',
['Gö']='Göhan:BAAALgADCgUJBQABLgAECgYJEwAPAAAAAA==.',
['Gø']='Gøvers:BAAALgAECgMJBAAAAA==.',
Ha='Hakuouki:BAAALgAECgMJAwAAAA==.Handyman:BAAALgADCgYJCgAAAA==.Hantom:BAAALgADCgYJBgABLgAFFAYJEQAKAOEXAA==.Hazell:BAAALgADCgYJBgAAAA==.',
He='Heaveth:BAAALgAECgMJAwABLgAFFAMJCwAeAP4cAA==.Hefestion:BAAALgAFFAEJAQAAAA==.Hellspont:BAAALgAECgEJAQAAAA==.Helsingdarck:BAAALgADCgIJAgAAAA==.Hendrikison:BAAALgAECgcJCQAAAA==.',
Hi='Hildegyth:BAABLgAECn8fAAMKAAgJWBE1MQBhAQAKAAcJWRE1MQBhAQAJAAUJZxG8WwAGAQAAAA==.',
Hj='Hjalmar:BAAALgADCgcJCQAAAA==.',
Ho='Hodtiva:BAABLgAECn8tAAMBAAgJdBDcLQBqAQABAAgJdBDcLQBqAQALAAUJDA5JTgCpAAAAAA==.Homerz:BAAALgADCgEJAQAAAA==.Horagalles:BAAALgAECgEJAQAAAA==.Hotmojo:BAABLgAECn8eAAITAAgJOw+3eQCFAQATAAgJOw+3eQCFAQABLgAFFAUJDwAeAE0cAA==.',
Hu='Hunfox:BAACLgAFFH8VAAIXAAMJUR9pCwAHAQAXAAMJUR9pCwAHAQAuAAQKf0QAAhcACQmuI8IJAAoDABcACQmuI8IJAAoDAAAA.',
['Hä']='Härkness:BAAALgAECgYJCAAAAA==.',
['Hø']='Høolligans:BAAALgAECgEJAQAAAA==.',
['Hü']='Hüskar:BAABLgAECn8fAAMbAAkJ/AuRMQCGAQAbAAkJuQuRMQCGAQAZAAEJCg8NfAAtAAAAAA==.',
Ic='Icechips:BAAALgADCgUJBQAAAA==.Ichigoz:BAABLgAECn8iAAITAAkJBQqrcgCUAQATAAkJBQqrcgCUAQAAAA==.',
Ih='Ihntwuaed:BAAALgADCgYJCQAAAA==.',
Ik='Ikoo:BAABLgAECn9NAAIaAAkJLiD4BAA+AwAaAAkJLiD4BAA+AwAAAA==.',
Il='Illaril:BAACLgAFFH8mAAICAAYJIx2xAQC3AQACAAYJIx2xAQC3AQAuAAQKf2UAAgIACQmMIWQCANcCAAIACQmMIWQCANcCAAAA.',
In='Indarion:BAAALgADCgYJEQAAAA==.Ingratt:BAAALgAECgEJAgAAAA==.Invisiblelol:BAAALgAECgIJAgAAAA==.',
Ir='Irmãodouther:BAAALgAFFAIJAgAAAA==.',
Is='Isebby:BAAALgADCgMJAwAAAA==.Ishtarie:BAAALgAECgQJBQABLgAECgkJHgAFAJkXAA==.',
It='Itzzdan:BAAALgADCgMJAwAAAA==.',
Iv='Ivina:BAABLgAECn8UAAMVAAgJThbwkQA1AQAVAAcJThbwkQA1AQAfAAIJqRe4HACNAAAAAA==.',
Iz='Izaar:BAAALgAECgQJDgAAAA==.',
Ja='Jacsonnaik:BAAALgAECgQJBQAAAA==.Jadelina:BAAALgAECgEJAQAAAA==.Janaìna:BAAALgAECgMJAwAAAA==.Jangeoffry:BAAALgADCgEJAQAAAA==.Jaymee:BAAALgAECgEJAQAAAA==.',
Jh='Jhonatinha:BAABLgAECn8VAAMIAAcJBxkL3gDgAAAIAAYJaxkL3gDgAAASAAQJng69dgCfAAAAAA==.',
Ji='Jigsaww:BAAALgAECgQJCQAAAA==.',
Jk='Jks:BAAALgAECgUJCgAAAA==.',
Jo='Joaquim:BAAALgAECgIJAgAAAA==.Jogaveiopl:BAAALgADCgIJAgAAAA==.Johnlobo:BAAALgAECgEJAQAAAA==.Joventino:BAAALgADCgQJBQAAAA==.',
Ju='Jucah:BAABLgAECn8ZAAIeAAkJZAt3OwBIAQAeAAkJZAt3OwBIAQAAAA==.Julabolseiro:BAABLgAECn8VAAMLAAgJegyLLQBgAQALAAgJegyLLQBgAQABAAIJBgI4iQAwAAAAAA==.Julinhas:BAAALgADCgUJBQAAAA==.Jullianxd:BAAALgADCgYJCAABLgAECgkJFgARAOwPAA==.',
Ka='Kaallew:BAABLgAECn8ZAAIHAAkJuRccGABdAQAHAAkJuRccGABdAQAAAA==.Kaezar:BAAALgADCgEJAQAAAA==.Kainer:BAAALgAECgQJBQAAAA==.Kalazshar:BAABLgAECn8mAAIMAAkJbBIzFgCiAQAMAAkJbBIzFgCiAQAAAA==.Kalelzinho:BAAALgADCgYJCAAAAA==.Kaluss:BAABLgAECn8UAAITAAgJCgZOCwBdAAATAAgJCgZOCwBdAAAAAA==.Kanalet:BAAALgAECgYJCAAAAA==.Kandára:BAAALgADCgEJAQAAAA==.Kantaa:BAAALgAECgQJCwAAAA==.Kanturu:BAAALgAECgQJBAAAAA==.Kanzaki:BAAALgADCgcJBwABLgAECgkJTwAKAKojAA==.Karonn:BAABLgAECn8UAAIIAAYJ/A3mlABTAQAIAAYJ/A3mlABTAQAAAA==.Kavartu:BAAALgAECgYJDAAAAA==.Kaymon:BAAALgAECgEJAQAAAA==.',
Ke='Keillor:BAABLgAECn8pAAMdAAgJGRaTRQCXAQAdAAcJWRSTRQCXAQAeAAYJXRqBLwCCAQAAAA==.Kelantir:BAAALgAECgYJCQABLgAECgkJDAAPAAAAAA==.Keldorian:BAAALgADCgcJEAAAAA==.Kelishe:BAAALgAECgUJBQAAAA==.Kelliar:BAAALgAECgIJAQAAAA==.Kelorn:BAAALgADCgYJBgABLgAECggJEQAPAAAAAA==.Kelysa:BAAALgADCgkJDgABLgAECggJPQAUACYdAA==.Kenzou:BAABLgAECn8YAAMYAAcJ0hhBMQA9AQAYAAUJexxBMQA9AQAKAAcJSQ/1OAAeAQAAAA==.',
Kh='Khadi:BAAALgAECgcJCwAAAA==.Khaeltaz:BAAALgAECgMJAwAAAA==.Khalandra:BAABLgAECn8eAAIbAAkJaBtyKwAIAgAbAAkJaBtyKwAIAgAAAA==.Khalel:BAAALgADCgEJAgAAAA==.Khaliq:BAABLgAECn8eAAMDAAkJVxV6FADtAQADAAkJVxV6FADtAQARAAQJLApxrwCtAAAAAA==.Khallani:BAABLgAECn8fAAIEAAcJgAlLlQBWAQAEAAcJgAlLlQBWAQAAAA==.Khamul:BAAALgAECgQJBgAAAA==.Khaos:BAAALgAECggJEwAAAA==.Khisto:BAABLgAECn80AAMTAAkJnRstOQA0AgATAAkJnRstOQA0AgAgAAcJ3Rf5BACSAQAAAA==.Khroriggs:BAAALgAECgYJDQABLgAECgcJBwAPAAAAAA==.',
Ki='Kieran:BAAALgAECgMJAwAAAA==.Killerbiie:BAAALgADCgIJAgAAAA==.Killerdown:BAAALgADCgIJAgAAAA==.Kimashi:BAAALgAECgUJBQAAAA==.Kindie:BAAALgADCgcJCwABLgAECggJFAARABEIAA==.Kisam:BAAALgADCgEJAQAAAA==.Kissme:BAACLgAFFH8FAAMNAAMJ2AkPQgBuAAANAAIJdwgPQgBuAAAMAAEJmwxUQgAmAAAuAAQKfx4AAw0ACQmYEEstAG8BAA0ACAneEUstAG8BAAwABAmICAVHAI0AAAAA.Kitamor:BAABLgAECn9LAAINAAkJ2A1GKQCIAQANAAkJ2A1GKQCIAQAAAA==.Kiya:BAAALgADCgcJHgAAAA==.',
Kl='Klorokina:BAAALgAECgYJBgAAAA==.',
Ko='Kooraqt:BAAALgAECgQJBAAAAA==.Koriakin:BAABLgAECn8vAAMXAAkJIR3TEADKAgAXAAkJIR3TEADKAgAhAAcJBxikGQDSAQAAAA==.Kosmo:BAAALgAECgcJCQAAAA==.Kotalkhan:BAAALgADCgkJEQAAAA==.',
Kr='Krosmu:BAAALgADCgcJBwAAAA==.Krov:BAAALgAECgEJAQAAAA==.Kryon:BAAALgAECgYJDgAAAA==.Kryzthor:BAAALgAECgYJCAAAAA==.Kräsus:BAABLgAECn9DAAIUAAkJAibtAABiAwAUAAkJAibtAABiAwAAAA==.Krønna:BAAALgAECgQJBAABLgAECgYJKQAiAEsIAA==.',
Ku='Kul:BAAALgAECgUJBgAAAA==.Kuthila:BAAALgADCgIJAgAAAA==.',
Ky='Kyzaru:BAAALgAECgIJAgAAAA==.',
['Kÿ']='Kÿdou:BAAALgAECgcJDgAAAA==.',
La='Ladrion:BAABLgAECn9WAAQjAAkJtR+HAQDfAgAjAAkJvB6HAQDfAgAcAAkJAxmFFABuAgAkAAkJ9RflBAA6AgAAAA==.Laetus:BAABLgAECn8ZAAIlAAcJqxdpCAAXAQAlAAcJqxdpCAAXAQAAAA==.Lagosta:BAAALgAECgMJBgAAAA==.Laiany:BAABLgAECn9MAAILAAkJJSITBABFAwALAAkJJSITBABFAwAAAA==.Lani:BAAALgAECgEJAQAAAA==.',
Le='Legacia:BAAALgADCgYJBgAAAA==.Lekrom:BAAALgADCgYJBgAAAA==.Leodoros:BAAALgAECgQJBAAAAA==.Lequinhö:BAAALgAECgIJAgAAAA==.Leric:BAAALgADCgcJCgAAAA==.Lethmar:BAABLgAECn8eAAIVAAcJMxesXQCGAQAVAAcJMxesXQCGAQAAAA==.Levanah:BAABLgAFFH8IAAIXAAYJFAIsWwDuAAAXAAYJFAIsWwDuAAAAAA==.Leyana:BAAALgAECgUJBwAAAA==.',
Lh='Lhwei:BAAALgAECgIJAgABLgAFFAQJDAAJAHwWAA==.',
Li='Liandra:BAAALgAECgEJAQAAAA==.Licaon:BAAALgADCgYJDgAAAA==.Lichkiller:BAAALgAECgUJBQAAAA==.Lichkíng:BAAALgAECgIJAQAAAA==.Lightbreaker:BAABLgAECn8jAAIIAAkJZAipiQBdAQAIAAkJZAipiQBdAQAAAA==.Lihr:BAAALgADCgYJCQAAAA==.Lilianpotter:BAAALgAECgEJAQAAAA==.Lilithrix:BAAALgADCgIJAgAAAA==.Lillit:BAABLgAECn9HAAQfAAkJahEkDgB6AQAfAAgJ9w0kDgB6AQAVAAkJ/A+5AgDpAAAWAAIJvwYvPQA3AAAAAA==.Lindaah:BAABLgAECn8yAAMKAAgJyBkqFgAGAgAKAAgJyBkqFgAGAgAJAAYJJwljcADHAAAAAA==.Lindademon:BAAALgAECgUJDwAAAA==.Lindahealer:BAAALgAECgUJCgABLgAECgUJDwAPAAAAAA==.Lislfox:BAABLgAECn9AAAIMAAkJbBrPCABfAgAMAAkJbBrPCABfAgAAAA==.Lithlad:BAAALgADCgIJAgAAAA==.',
Lk='Lkinho:BAAALgAECgMJBAAAAA==.',
Lm='Lmmds:BAAALgAECgUJCwAAAA==.',
Lo='Lockynha:BAAALgADCgEJAQAAAA==.Loohynir:BAABLgAFFH8FAAIFAAIJFQl2XABiAAAFAAIJFQl2XABiAAAAAA==.Lotusbird:BAAALgADCgcJBwAAAA==.',
Lu='Lucario:BAAALgAECgEJAgAAAA==.Luccoa:BAAALgAECgkJCgABLgAECgkJQwAUAAImAA==.Luccyah:BAAALgADCgkJDgAAAA==.Lucifïr:BAAALgAECgEJAQAAAA==.Lucileia:BAAALgAECgQJBQAAAA==.Lukazgplay:BAAALgADCgIJAgAAAA==.Lutsul:BAAALgAECgEJAQAAAA==.',
Ly='Lylka:BAABLgAECn8+AAMHAAkJ0SWoAABlAwAHAAkJ0SWoAABlAwASAAMJIiM4RAAwAQAAAA==.Lyrrena:BAAALgAECgMJBwAAAA==.',
Ma='Maanu:BAAALgAECgcJDwABLgAECggJMgAKAMgZAA==.Macumbadora:BAAALgAECgQJCgAAAA==.Madfulock:BAABLgAECn8UAAIVAAcJiBi+AwC2AAAVAAcJiBi+AwC2AAAAAA==.Maeghann:BAAALgADCgMJAwAAAA==.Magalândia:BAAALgAECgIJAgAAAA==.Magraver:BAAALgAECgMJAwAAAA==.Mais:BAAALgAECgEJAQAAAA==.Makani:BAAALgAECgQJBAAAAA==.Malewolyyc:BAACLgAFFH8IAAMLAAIJyR6JJACYAAALAAIJyR6JJACYAAABAAEJZgfnPQA9AAAuAAQKfysAAwsACQmZIXYMAJ8CAAsACAk/I3YMAJ8CAAEABglGEYQ6ACkBAAEuAAUUAwkDAA8AAAAA.Malhun:BAAALgADCgUJDgAAAA==.Malphan:BAAALgAECgcJBwAAAA==.Malyguz:BAACLgAFFH8UAAITAAQJ1BLBXQAkAQATAAQJ1BLBXQAkAQAuAAQKfxsAAhMABwldG+BgABkCABMABwldG+BgABkCAAAA.Malévolaa:BAAALgAECgYJBwAAAA==.Manipullador:BAAALgAECgIJAgAAAA==.Mapussauro:BAAALgAECgcJEQAAAA==.Maradi:BAAALgADCgIJAgAAAA==.Mariob:BAABLgAFFH8GAAImAAIJEAWjOwBIAAAmAAIJEAWjOwBIAAAAAA==.Marjøly:BAAALgAECgEJAQAAAA==.Markson:BAAALgADCgEJAQAAAA==.Massafera:BAABLgAECn8fAAIIAAkJMxP5WgC8AQAIAAkJMxP5WgC8AQAAAA==.Mather:BAAALgAECgEJAQAAAA==.Mathfacbruxo:BAABLgAECn9NAAIVAAkJFhzUGQCJAgAVAAkJFhzUGQCJAgAAAA==.Mauritiuz:BAAALgAFFAEJAQAAAA==.Mayanyy:BAAALgAECgEJAQAAAA==.',
Mc='Mcq:BAAALgAECgEJAQAAAA==.',
Md='Mdrdark:BAACLgAFFH8NAAIEAAUJlxSSaAAoAQAEAAUJlxSSaAAoAQAuAAQKfy0AAwQACQmiGRkxADoCAAQACQmiGRkxADoCACYAAwm/FVZIAGwAAAAA.',
Me='Medz:BAABLgAECn8jAAITAAkJlRqMMQBTAgATAAkJlRqMMQBTAgAAAA==.Meedea:BAAALgADCgUJBgAAAA==.Meetjack:BAAALgAECgEJAgAAAA==.Meiyin:BAAALgAECgcJDQAAAA==.Melania:BAAALgAECgEJAgAAAA==.Melissandra:BAAALgAFFAIJAwAAAA==.Mellkor:BAABLgAECn8qAAIDAAkJQhv/DABWAgADAAkJQhv/DABWAgAAAA==.Melytah:BAAALgAECgEJAgAAAA==.Melzynhaa:BAAALgAECgEJAwABLgAECggJMgAKAMgZAA==.Meraxxes:BAAALgADCgcJDAAAAA==.Merellien:BAAALgADCggJDgAAAA==.Metamorful:BAABLgAECn8ZAAIFAAkJBxL/SQB7AQAFAAkJBxL/SQB7AQAAAA==.',
Mh='Mhorgann:BAAALgAECgUJBgAAAA==.',
Mi='Mijonakombi:BAABLgAECn8WAAIIAAkJ/hpoLwBDAgAIAAkJ/hpoLwBDAgAAAA==.Mikveh:BAAALgAECgYJCgAAAA==.Milim:BAABLgAECn8/AAMOAAkJ8hMmHgDmAQAOAAkJ2RImHgDmAQAnAAgJRQ2GDwATAQAAAA==.Milliidan:BAAALgADCgUJBQAAAA==.Mindrathys:BAAALgAECgEJAQAAAA==.Mithrius:BAABLgAECn8kAAIIAAgJxxHycACMAQAIAAgJxxHycACMAQAAAA==.',
Ml='Mls:BAAALgAECgUJBgAAAA==.',
Mo='Mogrus:BAAALgADCgMJAwAAAA==.Mohanna:BAAALgAECgkJDgAAAA==.Mohanninha:BAAALgAECgYJCwAAAA==.Mohotok:BAABLgAECn9SAAIIAAkJNhnbJwBkAgAIAAkJNhnbJwBkAgAAAA==.Moonøvesso:BAAALgAECgIJBQAAAA==.Moopp:BAAALgADCgcJCAAAAA==.Mortixxia:BAABLgAECn8oAAIWAAgJnx0kBABCAgAWAAgJnx0kBABCAgAAAA==.',
Mu='Muata:BAAALgAECgYJDwAAAA==.Muf:BAAALgAECgYJBgAAAA==.Mupar:BAAALgADCgIJAgAAAA==.Murano:BAABLgAECn8yAAMbAAkJxR73DQCQAgAbAAkJxR73DQCQAgAZAAMJywp8VQCBAAAAAA==.Muzzo:BAAALgADCgYJCwABLgAECgcJEgAPAAAAAA==.',
My='Myrmïdom:BAAALgAECgIJAgAAAA==.Myzoreh:BAAALgAECggJDAAAAA==.',
['Má']='Mágico:BAAALgAECgEJAwAAAA==.Máia:BAABLgAECn8UAAIWAAgJiAxqEQAvAQAWAAgJiAxqEQAvAQAAAA==.',
['Mä']='Mändosz:BAABLgAECn8ZAAMEAAkJMRKYbgCIAQAEAAgJahKYbgCIAQAGAAMJCRB1JACsAAAAAA==.',
['Mé']='Ménace:BAACLgAFFH8FAAIVAAMJPhcPbgDmAAAVAAMJPhcPbgDmAAAuAAQKfxUAAxUACQnmHfZaALcBABUACAnmHfZaALcBABYAAwlcDvJGAJoAAAAA.',
['Mÿ']='Mÿstyna:BAAALgAECgEJAQAAAA==.',
Na='Nalathiel:BAABLgAECn8UAAILAAgJ+gzrMwA2AQALAAgJ+gzrMwA2AQAAAA==.Narancia:BAAALgAECgYJDQABLgAECgcJCwAPAAAAAA==.Naryth:BAAALgAECgYJCAAAAA==.Nassur:BAAALgADCgEJAQAAAA==.Nattaliaa:BAAALgAECgEJAQAAAA==.Nazawill:BAAALgAECgEJAQAAAA==.Nazdru:BAAALgADCgMJAwABLgAECgkJVAAQAOQhAA==.Nazzh:BAAALgAECgEJAQABLgAECgUJBQAPAAAAAA==.',
Ne='Necronx:BAAALgAECgEJAQAAAA==.Necronxd:BAAALgADCgEJAgAAAA==.Nefas:BAABLgAECn8jAAIWAAkJYxPnBwDSAQAWAAkJYxPnBwDSAQAAAA==.Nefazo:BAAALgAECgcJCgAAAA==.Nefilo:BAAALgADCgYJEAAAAA==.Nepthunus:BAABLgAECn9IAAIgAAkJuyGEAAAXAwAgAAkJuyGEAAAXAwAAAA==.Nermand:BAAALgAECgEJAQAAAA==.Neshula:BAAALgADCgMJAwAAAA==.Neuvosor:BAAALgAECgEJAQAAAA==.',
Ni='Nibelunga:BAAALgADCgYJBgAAAA==.Nijor:BAAALgADCgYJBgAAAA==.Nilsonssbnu:BAAALgAECgEJAQAAAA==.',
No='Nobelnaga:BAAALgAECgMJAwAAAA==.Novatoo:BAAALgAFFAEJAQAAAA==.',
Ny='Nyobb:BAAALgADCgMJAwAAAA==.Nyxra:BAAALgADCgcJEAAAAA==.',
['Në']='Nëcros:BAAALgAECgQJBQAAAA==.',
['Nö']='Nöirr:BAAALgAECgQJBgAAAA==.',
Oc='Ocelotte:BAAALgADCgEJAQAAAA==.',
Od='Odin:BAAALgAECgEJAQAAAA==.Odynsabio:BAAALgAECgEJAQAAAA==.',
Of='Ofanzitsu:BAAALgADCgQJBAAAAA==.',
Oi='Oioimiguel:BAAALgAECgUJBQAAAA==.',
Ol='Olhua:BAAALgAECgMJCAAAAA==.Oljedvlad:BAAALgADCgEJAQAAAA==.Oluss:BAAALgADCgUJBQABLgAFFAMJFQAXAFEfAA==.',
Om='Omnath:BAAALgADCgYJBgAAAA==.',
Or='Orillan:BAABLgAECn9JAAMDAAkJIBtmCwBwAgADAAkJIBtmCwBwAgARAAEJhAcY5gAsAAAAAA==.Ornsteinsnow:BAABLgAECn8ZAAISAAkJvhSLHAAfAgASAAkJvhSLHAAfAgAAAA==.Orob:BAABLgAECn8WAAIFAAYJhQm9eQDKAAAFAAYJhQm9eQDKAAAAAA==.Ororah:BAAALgAECgYJEAAAAA==.Orsonn:BAAALgAECgYJDAAAAA==.Orukam:BAABLgAECn8ZAAMFAAkJMBYyRACAAQAFAAgJ7BQyRACAAQANAAMJTgi8aAB9AAAAAA==.',
Os='Oszwald:BAAALgADCgEJAQAAAA==.',
['Oú']='Oúkürä:BAAALgAECgYJCgAAAA==.',
Pa='Padawani:BAAALgAECgMJAwAAAA==.Padgodeira:BAAALgAECgQJBAAAAA==.Padrealpha:BAAALgADCgcJCgAAAA==.Padrekelmøn:BAAALgAECgQJBAAAAA==.Palaha:BAAALgADCgEJAQABLgAFFAMJFQAXAFEfAA==.Palantír:BAAALgADCgEJAQAAAA==.Palatina:BAABLgAFFH8GAAIIAAUJWhezQgAmAQAIAAUJWhezQgAmAQAAAA==.Palazzy:BAAALgAECgEJAgAAAA==.Pandong:BAAALgAECggJEAAAAA==.Panena:BAAALgAECgIJAwAAAA==.Pangedrey:BAABLgAECn9TAAMKAAkJ5x9jCADBAgAKAAkJ5x9jCADBAgAYAAcJJQRyTQDJAAAAAA==.Paracepatrol:BAAALgAECgQJAwAAAA==.Parcival:BAACLgAFFH8LAAIXAAMJoBohVwD4AAAXAAMJoBohVwD4AAAuAAQKfzIAAhcACQmKI4IFADoDABcACQmKI4IFADoDAAAA.Parký:BAAALgAECgcJCAAAAA==.Pattalógika:BAAALgAECgEJAQAAAA==.Paullk:BAABLgAECn8gAAINAAYJchQMPQAcAQANAAYJchQMPQAcAQAAAA==.',
Pe='Pedrinho:BAAALgADCgYJBgABLgAFFAUJEwARACIgAA==.Penseur:BAAALgAECgcJBwAAAA==.Penéllope:BAAALgAECgQJBwAAAA==.Persëphone:BAABLgAECn8VAAMLAAcJsRTcPQD6AAALAAUJyRDcPQD6AAABAAYJCBJ7XAClAAAAAA==.Peruchi:BAAALgAECgQJBAAAAA==.',
Pg='Pgms:BAAALgAECgUJBQAAAA==.',
Ph='Phacozitos:BAAALgAECgEJAgAAAA==.Phaxe:BAAALgADCgIJAgAAAA==.Phoenicx:BAAALgADCgMJBgAAAA==.Phøënïx:BAAALgAECgcJDAAAAA==.',
Pi='Pipelinebr:BAAALgAECgUJBQAAAA==.Pitombinha:BAAALgAECgEJBAAAAA==.',
Pl='Plumalume:BAAALgADCgYJBgAAAA==.',
Po='Powalker:BAAALgAECgEJAgAAAA==.',
Pp='Pp:BAABLgAFFH8TAAQaAAUJngmeIgA7AQAaAAUJngmeIgA7AQABAAIJ4wYVMwB4AAALAAEJ6wCOPQAlAAABLgAFFAcJGgAOALgRAA==.',
Pr='Prometeus:BAAALgAECgYJDwAAAA==.Pryon:BAAALgAECgUJCwAAAA==.',
Pt='Ptollomeu:BAAALgAECgMJBQABLgAECgMJCQAPAAAAAA==.',
['Pä']='Pändero:BAABLgAECn8WAAIJAAYJ8yIJGgBHAgAJAAYJ8yIJGgBHAgAAAA==.Pänqueca:BAAALgAECgEJAgAAAA==.',
['Pé']='Pénacova:BAAALgADCgEJAQAAAA==.',
['Pî']='Pîo:BAACLgAFFH8IAAITAAMJVxFZgADWAAATAAMJVxFZgADWAAAuAAQKfxcAAxMACAltGVRiALoBABMACAl5GFRiALoBACUABAnTGPAKACwBAAAA.',
Qu='Quejerok:BAAALgAECgYJEwAAAA==.',
Ra='Radiação:BAAALgAECgUJBQAAAA==.Radunz:BAABLgAECn9UAAIQAAkJ5CH6AQAUAwAQAAkJ5CH6AQAUAwAAAA==.Ragnaros:BAABLgAFFH8FAAISAAIJAxAzOwB4AAASAAIJAxAzOwB4AAAAAA==.Ragnarssön:BAAALgAFFAEJAQAAAA==.Raineko:BAAALgADCgYJBgAAAA==.Raio:BAACLgAFFH8FAAITAAIJlxNqogCKAAATAAIJlxNqogCKAAAuAAQKfy8AAhMACQkEIfIdAKkCABMACQkEIfIdAKkCAAAA.Ralfwur:BAAALgAECgQJBwAAAA==.Ramsez:BAAALgAECgEJAQAAAA==.Rargsa:BAABLgAECn8dAAIGAAgJfAaNGQAHAQAGAAgJfAaNGQAHAQAAAA==.Rariel:BAAALgADCgIJAgAAAA==.Rasmon:BAABLgAECn8uAAIVAAkJRxS+QwDQAQAVAAkJRxS+QwDQAQAAAA==.Ravendreth:BAAALgADCgEJAQAAAA==.Raykarla:BAAALgAECgIJAwAAAA==.Raymain:BAACLgAFFH8GAAMKAAMJzh1PGwDxAAAKAAMJzh1PGwDxAAAJAAEJkw61ZgAuAAAuAAQKfyQAAwkACQkSFqo9AHkBAAkACAmaFKo9AHkBAAoABwkXFrk4AB8BAAAA.Raíka:BAAALgAECgYJCwAAAA==.',
Re='Reddnose:BAAALgAECgUJCQAAAA==.Reinhold:BAABLgAECn8aAAMIAAcJYRTEewB3AQAIAAcJYRTEewB3AQASAAUJ2Qj8WwDGAAAAAA==.',
Rh='Rhuryk:BAAALgADCggJCAAAAA==.',
Ri='Ricktdai:BAAALgAECgEJAQAAAA==.Riesze:BAACLgAFFH8KAAIXAAMJoRGaXwDlAAAXAAMJoRGaXwDlAAAuAAQKfycAAhcACQl9GWshAGACABcACQl9GWshAGACAAAA.',
Ro='Roguinhu:BAAALgAFFAEJAQAAAA==.Ropaoo:BAABLgAECn8XAAIWAAYJEhbMDwBDAQAWAAYJEhbMDwBDAQAAAA==.',
Ru='Rua:BAAALgAECgQJBAAAAA==.Rurumo:BAAALgADCgQJBAAAAA==.Rusga:BAAALgADCggJCAAAAA==.Rustovick:BAAALgAECgMJBgAAAA==.',
Ry='Rytheas:BAAALgAECgQJBgAAAA==.',
['Rä']='Rämzä:BAAALgAECgYJEwAAAA==.',
['Rå']='Råy:BAAALgAECgQJCQAAAA==.',
['Rí']='Rízadinha:BAAALgAECgQJBAAAAA==.',
Sa='Saargeras:BAAALgADCgMJAwAAAA==.Saffír:BAABLgAECn8mAAIIAAkJTRhENgAoAgAIAAkJTRhENgAoAgAAAA==.Saiden:BAAALgADCgQJBAAAAA==.Saintkaue:BAAALgADCgUJCAAAAA==.Sairoz:BAAALgAECgEJAQAAAA==.Samalandraa:BAAALgADCgEJAQAAAA==.Sanahh:BAAALgAECgYJCAAAAA==.Sanateia:BAAALgADCgYJCwAAAA==.Santamadre:BAAALgADCgEJAQAAAA==.Sapekinhä:BAACLgAFFH8FAAIDAAIJwxjyIQCLAAADAAIJwxjyIQCLAAAuAAQKfywABAMACQlJI70EAPoCAAMACQlJI70EAPoCAAIAAglSGOsjAH8AABEAAglFCR75AFQAAAAA.Satanvitória:BAABLgAECn8uAAMZAAgJ7B5vDAAgAgAbAAcJYRo0JgAoAgAZAAgJbh5vDAAgAgAAAA==.Sauroth:BAAALgADCgUJCQAAAA==.',
Sc='Scheiren:BAAALgAECgQJBgAAAA==.',
Se='Senegos:BAAALgADCgcJBwAAAA==.Sereiaa:BAABLgAECn8qAAIXAAgJCA8aZQB6AQAXAAgJCA8aZQB6AQAAAA==.Sesiom:BAAALgAECgcJBgAAAA==.',
Sh='Shalltearr:BAAALgADCgEJAQAAAA==.Shamate:BAAALgAFFAEJAQAAAA==.Shanoa:BAAALgAECgMJAwAAAA==.Sharae:BAAALgADCgIJAQAAAA==.Shariany:BAAALgADCgEJAQAAAA==.Sharpersong:BAAALgADCgcJBgAAAA==.Shedo:BAABLgAECn8VAAMZAAgJAxouFwCiAQAZAAcJuBkuFwCiAQAbAAYJWg+VYgAoAQAAAA==.Sheevane:BAABLgAECn8eAAIFAAkJmReuJAAnAgAFAAkJmReuJAAnAgAAAA==.Shinzo:BAAALgADCgEJAQAAAA==.Shonja:BAAALgADCgcJDgAAAA==.Shula:BAAALgADCgcJDQAAAA==.Shumuk:BAAALgAECgEJAQAAAA==.Shÿnara:BAAALgAECgkJDwAAAA==.',
Si='Siclop:BAAALgADCgYJBgAAAA==.Silgris:BAAALgAECgEJAQABLgAECggJIAASAPERAA==.Silmeria:BAABLgAECn8WAAIdAAgJAgW1dQD8AAAdAAgJAgW1dQD8AAAAAA==.Silverchain:BAAALgADCgcJCgAAAA==.Sinton:BAAALgAECgQJCAAAAA==.',
Sk='Skadryan:BAAALgAECgEJAQAAAA==.Skeletowman:BAAALgADCgUJBQAAAA==.Skineh:BAAALgAECgQJBwAAAA==.Skinme:BAABLgAECn8UAAIJAAYJKwQdjACDAAAJAAYJKwQdjACDAAAAAA==.',
Sm='Smylf:BAAALgAECgkJEAAAAA==.',
Sn='Snakedown:BAAALgAECgEJAgAAAA==.',
So='Sombrea:BAAALgAECgYJEgAAAA==.',
Sp='Spectrø:BAAALgAECgYJBgAAAA==.',
Sr='Srheal:BAAALgAECgQJBAAAAA==.Srsapo:BAAALgAECgMJBgAAAA==.',
Ss='Ssamara:BAAALgAECgYJBgAAAA==.',
St='Stampede:BAAALgADCgMJAwAAAA==.Starian:BAABLgAECn8gAAMFAAcJKRwvJQAjAgAFAAcJKRwvJQAjAgANAAEJywwTfwAzAAAAAA==.Straider:BAAALgAECgEJAQAAAA==.Stëlla:BAABLgAECn8vAAIdAAgJ3RS5LwD2AQAdAAgJ3RS5LwD2AQAAAA==.',
Su='Suckmyhammer:BAAALgAECgYJBwAAAA==.Sunnara:BAACLgAFFH8TAAIRAAUJIiCKMwBXAQARAAUJIiCKMwBXAQAuAAQKfyIAAhEACQnwIT8KAPgCABEACQnwIT8KAPgCAAAA.Superkx:BAAALgAECgQJBQAAAA==.Suzanomu:BAAALgADCgYJCwAAAA==.',
Sy='Sylran:BAAALgADCgQJBgAAAA==.Synk:BAAALgADCgQJBAAAAA==.Syofra:BAAALgAECgQJBQAAAA==.Syrelys:BAAALgADCgYJBgAAAA==.Syuon:BAACLgAFFH8MAAIJAAQJfBZ6KwAVAQAJAAQJfBZ6KwAVAQAuAAQKfzMAAwkACQkiIQgGAEYDAAkACQkiIQgGAEYDAAoAAgmQBqaKAEcAAAAA.',
['Së']='Sëkhmet:BAAALgAECgYJCwAAAA==.',
['Sï']='Sïmbä:BAABLgAECn8bAAMEAAkJjQ4AdQB6AQAEAAkJjQ4AdQB6AQAGAAEJkAShGQAoAAABLgAFFAEJAQAPAAAAAA==.',
['Só']='Sósummono:BAAALgADCgIJAgAAAA==.',
['Sÿ']='Sÿkies:BAAALgADCgEJAQAAAA==.',
Ta='Talandar:BAABLgAECn82AAINAAkJERlGEQBRAgANAAkJERlGEQBRAgAAAA==.Tankudo:BAABLgAECn8cAAIEAAgJJxOjhQBYAQAEAAgJJxOjhQBYAQAAAA==.Tannia:BAAALgADCgIJAgAAAA==.Tanthallas:BAAALgAECgEJAQAAAA==.Tavindapedra:BAAALgAECgYJCwAAAA==.',
Tc='Tchutchuco:BAAALgAECgIJAwAAAA==.',
Te='Tekzero:BAAALgAECgEJCAAAAA==.Tempestus:BAAALgADCgYJBgAAAA==.Tennebra:BAAALgADCgYJCAAAAA==.Teobaldo:BAAALgADCgYJCgAAAA==.Terron:BAABLgAECn8yAAMdAAkJEBYiIgBCAgAdAAkJEBYiIgBCAgAeAAIJnRc0dQCMAAAAAA==.',
Th='Thabitah:BAABLgAECn9OAAIBAAkJ0R9nBgDrAgABAAkJ0R9nBgDrAgAAAA==.Thaliath:BAAALgADCgQJBAAAAA==.Thallariel:BAAALgAECgQJBwAAAA==.Theteo:BAABLgAECn8ZAAIIAAkJZQulggBqAQAIAAkJZQulggBqAQAAAA==.Thiberios:BAAALgAECgUJDAAAAA==.Thirros:BAAALgADCgUJBQAAAA==.Thorres:BAAALgAECgMJBwAAAA==.Thotamon:BAAALgAECgQJCAAAAA==.Throin:BAAALgAECgMJAwAAAA==.Thràain:BAAALgAECgcJDgAAAA==.Thuki:BAAALgAECgEJAQAAAA==.Thunderblade:BAAALgAECgYJDgAAAA==.Théus:BAAALgAECgMJAwABLgAFFAMJBQAVAD4XAA==.',
Ti='Tiramisu:BAAALgAECgcJCwAAAA==.',
To='Torâo:BAAALgAECgcJEgAAAA==.Toucinho:BAAALgAECgYJDgAAAA==.',
Tr='Traydd:BAABLgAECn8iAAIQAAgJlBWnDgDKAQAQAAgJlBWnDgDKAQAAAA==.Trollando:BAAALgAECgUJCAAAAA==.',
Tu='Tuga:BAAALgADCgMJAwAAAA==.Turokk:BAABLgAECn8dAAIXAAgJDRCGZAB8AQAXAAgJDRCGZAB8AQAAAA==.',
Tw='Twilight:BAAALgADCgYJDQAAAA==.Twylluch:BAAALgADCgQJBgABLgAECgkJKAASAOsXAA==.',
Ul='Ulhim:BAAALgADCgcJEwAAAA==.',
Ur='Uriuri:BAAALgADCgYJBgABLgAECgkJVAAQAOQhAA==.',
Us='Usfull:BAABLgAECn87AAMLAAkJHhJwJQCZAQALAAgJYhNwJQCZAQABAAgJFg0cLwBjAQAAAA==.',
Va='Vacavelha:BAAALgAECgEJAQAAAA==.Vahtorn:BAAALgAECgMJBgAAAA==.Valaerys:BAAALgAECgUJCgAAAA==.Valaniri:BAAALgADCgEJAQAAAA==.Vallkÿria:BAAALgAECgYJBgAAAA==.Vanheelsen:BAAALgAFFAIJAgAAAA==.Vanyathariel:BAAALgAECgEJAQAAAA==.Vareena:BAAALgADCggJCAABLgAECgkJQwAUAAImAA==.Vashiel:BAAALgADCgIJAgAAAA==.',
Ve='Vehuiáh:BAABLgAECn8eAAMSAAgJMB0aHQAbAgASAAgJMB0aHQAbAgAIAAEJRQQCwgEjAAAAAA==.Velen:BAABLgAECn8bAAIEAAgJnBEmkwBAAQAEAAgJnBEmkwBAAQAAAA==.Vellkor:BAAALgADCgYJBgAAAA==.Vellon:BAAALgADCgEJAQAAAA==.Venrique:BAAALgAECgQJBAABLgAECgYJEQAPAAAAAA==.Venusa:BAAALgADCgMJBAAAAA==.Verno:BAAALgADCgcJCwAAAA==.Verzuk:BAABLgAECn8dAAIEAAgJPQqXjABMAQAEAAgJPQqXjABMAQAAAA==.',
Vi='Vidnands:BAAALgAECgEJAQAAAA==.Viinyy:BAAALgAECgMJAwAAAA==.Vilthor:BAAALgAECgUJBQAAAA==.Vintekilo:BAABLgAECn8YAAIIAAkJzRaiYgC9AQAIAAkJzRaiYgC9AQAAAA==.',
Vo='Voiddh:BAAALgAECgcJDAAAAA==.Vokeshar:BAAALgADCgUJBQAAAA==.Voltadupla:BAAALgAECgQJBQAAAA==.Voop:BAAALgADCgYJFAAAAA==.',
Vr='Vrenshrrgn:BAAALgADCgYJBgAAAA==.',
Vy='Vygh:BAACLgAFFH8JAAIVAAMJmBXddQDWAAAVAAMJmBXddQDWAAAuAAQKfy0AAxUACQm5IVYOANoCABUACQm5IVYOANoCABYAAQkjDzpwADYAAAAA.Vyndrill:BAAALgAECgYJDgAAAA==.',
['Vä']='Välion:BAAALgADCgIJAgAAAA==.',
Wa='Wacom:BAAALgADCgUJBQAAAA==.Walkers:BAAALgAECgkJDgAAAA==.Warlaka:BAAALgAECgUJCwAAAA==.Warpiel:BAAALgADCgcJDAABLgAECgkJHgAaAC0OAA==.Watchtower:BAAALgAECgQJBAAAAA==.',
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
Yi='Yingsu:BAABLgAECn8ZAAIYAAkJeCLQDgBNAgAYAAkJeCLQDgBNAgAAAA==.',
Yo='Yoshihime:BAAALgAECgIJAgABLgAECgkJHgAFAJkXAA==.',
Yv='Yvin:BAAALgAECgMJBAAAAA==.',
Za='Zallmo:BAACLgAFFH8FAAIbAAMJTQVIPQC4AAAbAAMJTQVIPQC4AAAuAAQKfyMAAhsACAl/FaEkANABABsACAl/FaEkANABAAAA.Zarath:BAAALgAECgUJBgAAAA==.Zawarudo:BAAALgAECgYJCgAAAA==.',
Ze='Zedd:BAAALgAFFAIJAgAAAA==.Zenorclord:BAAALgADCgQJBgAAAA==.Zeytona:BAABLgAECn8jAAIYAAkJjAuIJgB6AQAYAAkJjAuIJgB6AQAAAA==.',
Zi='Ziracruz:BAAALgAECgQJCwAAAA==.',
['Zí']='Zíngara:BAAALgAECgEJAQAAAA==.',
['Ár']='Árÿä:BAABLgAECn9VAAIXAAkJURVmMQAWAgAXAAkJURVmMQAWAgAAAA==.',
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
