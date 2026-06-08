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

local lookup = {'Priest-Shadow','DeathKnight-Unholy','Druid-Restoration','DeathKnight-Frost','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Havoc','Priest-Holy','Druid-Guardian','Druid-Balance','Evoker-Augmentation','Unknown-Unknown','Druid-Feral','DemonHunter-Devourer','Paladin-Holy','Mage-Frost','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Monk-Brewmaster','Warrior-Arms','DemonHunter-Vengeance','Priest-Discipline','Warrior-Fury','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Mage-Fire','Hunter-Survival','Shaman-Enhancement','Rogue-Outlaw','Rogue-Assassination','Mage-Arcane','DeathKnight-Blood','Evoker-Devastation',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abelao:BAAALgAECgcJEwAAAA==.',
Ad='Adelaide:BAAALgAECgIJAgABLgAFFAcJGgABALAaAA==.Adoramuss:BAAALgAECgYJCwAAAA==.Adrianoj:BAAALgAECgEJAQAAAA==.',
Ae='Aeklug:BAAALgADCgcJCAAAAA==.Aelon:BAAALgADCgUJBQAAAA==.Aelthor:BAAALgAECgQJDAAAAA==.Aemeath:BAAALgAECgkJEQAAAA==.',
Ah='Ahammes:BAAALgAECgQJBAABLgAECgcJHwACAIAJAA==.Ahmus:BAAALgAECgUJDAAAAA==.Ahrallu:BAAALgADCgEJAgAAAA==.',
Ai='Aioliavictus:BAAALgADCgIJAgAAAA==.',
Al='Alanie:BAAALgAECgUJDQABLgAECggJIwADABUeAA==.Aldranir:BAAALgADCgEJAQAAAA==.Alessaxd:BAACLgAFFH8HAAICAAIJ/Q3NvACVAAACAAIJ/Q3NvACVAAAuAAQKfykAAwIACQmhFfA2ABsCAAIACQmhFfA2ABsCAAQABwnKD5sRAEoBAAAA.Alexa:BAAALgAECgQJBAAAAA==.Alfajhor:BAABLgAECn86AAMFAAgJFx/ADwC6AQAFAAYJoyLADwC6AQAGAAgJZx0jXACvAQAAAA==.Alfajhòr:BAAALgAECgIJAgAAAA==.Alfajhôr:BAAALgAECgUJBwAAAA==.Alkarin:BAAALgAECgEJAwAAAA==.Allandriel:BAAALgAECgUJBQAAAA==.Alldarion:BAAALgAECgMJCQAAAA==.Allendra:BAAALgADCgcJCQAAAA==.Alleriane:BAACLgAFFH8GAAIHAAIJOhdaPwCFAAAHAAIJOhdaPwCFAAAuAAQKfzwAAwcACQlEH+sHABADAAcACQlEH+sHABADAAgAAQmnApGNABgAAAAA.Allerios:BAAALgAECgUJCQAAAA==.Allone:BAABLgAECn8eAAIJAAcJ/BHALAAIAQAJAAcJ/BHALAAIAQAAAA==.Allyhra:BAAALgADCgQJBAAAAA==.Allëria:BAAALgADCgMJAwAAAA==.Alruna:BAAALgAECgEJAQAAAA==.',
Am='Ametnys:BAAALgAECgQJCAAAAA==.Amonhar:BAAALgAECgQJBQABLgAECgkJOwAKAB4SAA==.Amyn:BAAALgADCgYJBwAAAA==.',
An='Anakata:BAABLgAECn8bAAQLAAYJ3RXwKAD+AAALAAYJ3RXwKAD+AAADAAIJ+wW8ygAzAAAMAAEJww9+hgAyAAAAAA==.Anakinini:BAABLgAECn8bAAINAAgJhAgoQgAWAQANAAgJhAgoQgAWAQABLgAECgYJBgAOAAAAAA==.Analia:BAABLgAECn8jAAQDAAgJFR5/HgBLAgADAAcJVR1/HgBLAgALAAgJnQg5MwDIAAAMAAMJQByQWQCeAAAAAA==.Andaliz:BAACLgAFFH8SAAIGAAMJwSZiKABVAQAGAAMJwSZiKABVAQAuAAQKfzYAAgYACQkLJpQCAGsDAAYACQkLJpQCAGsDAAEuAAUUBQkGAAYAWhcA.Andorith:BAAALgAECgEJAgAAAA==.Anelie:BAAALgAECgQJDQABLgAECggJIwADABUeAA==.Annhe:BAAALgAECgEJAQAAAA==.Ansalon:BAAALgADCgYJBwAAAA==.Anthorus:BAAALgAECgIJAgAAAA==.Antonellaes:BAAALgAECgUJCgABLgAECgcJDgAOAAAAAA==.Anturio:BAAALgAECgQJBwAAAA==.',
Ao='Aoiisuu:BAAALgADCgYJCAAAAA==.',
Ap='Apodrecido:BAAALgAECgYJBgAAAA==.',
Ar='Arajakata:BAAALgAECgEJAgAAAA==.Arctorius:BAAALgAECgYJEwAAAA==.Arethiel:BAAALgADCgYJBgAAAA==.Arlandriah:BAAALgADCgYJCQABLgAECgYJGAAGABAYAA==.Artronis:BAACLgAFFH8HAAILAAQJCwvCFgC6AAALAAQJCwvCFgC6AAAuAAQKfyYAAwsACAlPFkoTAKwBAAsACAlPFkoTAKwBAA8AAQk9FM5GADwAAAAA.Artånis:BAAALgAECgcJDAAAAA==.Arukäi:BAAALgADCgYJBgAAAA==.Aruthuro:BAAALgAECgYJDwAAAA==.',
As='Ashbörn:BAAALgAECgQJBgAAAA==.Astel:BAABLgAECn8VAAIQAAkJVAncXwBeAQAQAAkJVAncXwBeAQAAAA==.',
At='Atriuz:BAABLgAECn8bAAIRAAYJahouLwDGAQARAAYJahouLwDGAQAAAA==.Ats:BAAALgAECgIJAgAAAA==.',
Ay='Aykho:BAABLgAECn8nAAISAAgJRRbLYQC1AQASAAgJRRbLYQC1AQAAAA==.',
Az='Azurion:BAAALgAECgYJCgAAAA==.',
['Aÿ']='Aÿ:BAAALgAECgMJAwAAAA==.',
Ba='Baguh:BAAALgADCggJCAAAAA==.Bagunça:BAAALgADCgYJBgAAAA==.Bakuugou:BAAALgAECgMJCgAAAA==.Bambur:BAAALgADCgMJAwAAAA==.Barbabruto:BAABLgAECn8sAAITAAgJLB6HDAAXAgATAAgJLB6HDAAXAgAAAA==.Basilisco:BAAALgAECgEJAQAAAA==.',
Be='Belleg:BAAALgAECgEJAgAAAA==.Beronhuz:BAAALgAECgMJAwAAAA==.',
Bf='Bf:BAAALgAECgEJAQAAAA==.',
Bi='Biafalcão:BAAALgAECgEJAQAAAA==.Bijanca:BAAALgAECgYJBgAAAA==.Birthdäy:BAAALgADCgEJAQAAAA==.Bisponegro:BAAALgAECgQJCwABLgABCgcJFQAOAAAAAA==.Biønic:BAAALgAECgMJCQAAAA==.',
Bl='Blackline:BAABLgAECn8fAAICAAgJPRJDaQCLAQACAAgJPRJDaQCLAQAAAA==.',
Bo='Boipretim:BAAALgAECgYJDwAAAA==.Bontorius:BAAALgADCgEJAgAAAA==.Bordello:BAAALgADCgUJBQAAAA==.',
Br='Bradio:BAAALgADCggJCAAAAA==.Brahman:BAAALgAECgEJAwAAAA==.Bratloko:BAAALgAECgUJBQAAAA==.Bromos:BAAALgAECgQJCAAAAA==.Brutalhoof:BAAALgAECgQJBAAAAA==.Brönsted:BAAALgADCgMJAwAAAA==.',
Bu='Bubbalo:BAAALgADCgUJBQAAAA==.Bullsman:BAAALgADCgQJBAAAAA==.Buzzumaaky:BAABLgAECn8YAAISAAgJTxepiQC/AQASAAgJTxepiQC/AQAAAA==.',
By='Byakura:BAAALgADCggJCwAAAA==.',
['Bü']='Büdweiser:BAAALgAECgcJEAAAAA==.',
Ca='Cabernet:BAAALgAECgUJBwAAAA==.Cabeçaquente:BAAALgAECgcJCQAAAA==.Calanthe:BAAALgADCgcJBwAAAA==.Calhistra:BAABLgAECn8nAAMUAAgJQxmySAC7AQAUAAgJQxmySAC7AQAVAAIJRQokVQBvAAAAAA==.Calteryeker:BAAALgAECgYJEAAAAA==.Camillas:BAAALgAECggJDwAAAA==.Caosenvy:BAAALgAECgEJAQAAAA==.Caralh:BAAALgAECgEJAgAAAA==.Caroll:BAAALgAECgIJAgAAAA==.Castaldi:BAAALgAECgEJAgABLgAECgcJCwAOAAAAAA==.Cathe:BAABLgAECn8VAAIWAAYJIRzJSwCGAQAWAAYJIRzJSwCGAQAAAA==.',
Ce='Cecilith:BAAALgAECgYJCAAAAA==.Cernûnnos:BAACLgAFFH8FAAIDAAIJPRHCTACAAAADAAIJPRHCTACAAAAuAAQKfxUAAgMABglOD5JaAB4BAAMABglOD5JaAB4BAAAA.',
Ch='Champdude:BAABLgAECn9GAAQIAAkJqiNlAwAjAwAIAAkJqiNlAwAjAwAHAAMJjR66UgAIAQAXAAUJLxbLOwAFAQAAAA==.Chankowkwai:BAAALgAECgYJCQAAAA==.Chanë:BAAALgADCgIJAwAAAA==.Chaosangel:BAAALgAECgUJBgABLgAFFAMJBgAMAEsGAA==.Chewi:BAAALgAECgQJBwAAAA==.Chrnnos:BAAALgAECgEJAQAAAA==.',
Ci='Citra:BAAALgAECgMJBwAAAA==.',
Co='Coconolose:BAAALgAECgIJBgAAAA==.Cod:BAAALgAECgIJAwAAAA==.Codecks:BAAALgADCgYJBgAAAA==.Coldbringer:BAAALgAECgEJAQAAAA==.Coldhearths:BAAALgAECgUJBgAAAA==.Couro:BAAALgAECgYJCAAAAA==.Cowçadora:BAAALgADCgIJAQAAAA==.',
Cr='Criminøsa:BAAALgAECgcJCQAAAA==.Cristcalad:BAABLgAECn84AAMYAAgJoBejEADdAQAYAAgJoBejEADdAQATAAEJYQULTwAfAAAAAA==.Cryomanta:BAAALgAECgUJBQAAAA==.',
Cu='Cunhaovirado:BAAALgAECgYJDAABLgAFFAUJDwAIANUZAA==.Cunhazinha:BAAALgAECgQJBAAAAA==.Cupyncha:BAAALgADCgcJBwAAAA==.Cutia:BAAALgADCgEJAQAAAA==.Cutiesissy:BAAALgAECgQJCAABLgAECgcJGgAGAEoQAA==.',
['Cø']='Cøøkye:BAAALgAECgQJBQAAAA==.',
Da='Daellus:BAAALgADCgUJBQAAAA==.Daemi:BAAALgAECgIJBAAAAA==.Daibodan:BAAALgAECgEJBAAAAA==.Dalaty:BAAALgAECgUJBQAAAA==.Daniilos:BAAALgAFFAEJAQAAAA==.Daresh:BAAALgADCgIJAgAAAA==.Darklara:BAABLgAECn8lAAIZAAkJBRl6CADeAQAZAAkJBRl6CADeAQAAAA==.Darkove:BAABLgAECn8uAAISAAkJjBKXTQDsAQASAAkJjBKXTQDsAQAAAA==.Darrow:BAACLgAFFH8QAAMCAAQJ+BvBPABqAQACAAQJ+BvBPABqAQAEAAMJhRikEQDhAAAuAAQKfy8AAwIACQnPJEEOAPICAAIACQn0I0EOAPICAAQACAn8IvACALoCAAAA.Dartibeccoso:BAAALgADCgcJBwAAAA==.Daviberger:BAAALgAECgMJAwAAAA==.',
De='Deany:BAAALgAECgEJAQAAAA==.Deathinhu:BAABLgAECn9XAAISAAkJox+BEQDsAgASAAkJox+BEQDsAgAAAA==.Deathnacht:BAAALgAECgQJBwAAAA==.Delset:BAAALgADCgIJAgAAAA==.Demojoca:BAAALgAECgEJAQABLgAECgcJDgAOAAAAAA==.Dentepodre:BAAALgADCgEJAQAAAA==.Dervus:BAAALgADCgcJBwAAAA==.Dethroned:BAAALgAECgUJDAAAAA==.Devrath:BAAALgAECgEJAQAAAA==.Devyogi:BAAALgADCgcJCAAAAA==.',
Di='Diefs:BAAALgAECgEJAQAAAA==.Dimeros:BAABLgAECn8vAAIMAAkJJg8vIgCqAQAMAAkJJg8vIgCqAQAAAA==.Dito:BAAALgADCgEJAQAAAA==.Divano:BAACLgAFFH8KAAIBAAMJNBAyIwDGAAABAAMJNBAyIwDGAAAuAAQKfywAAwEACAnJH/QMAH0CAAEACAnJH/QMAH0CABoAAwkCCQ1ZAIQAAAAA.',
Dk='Dkats:BAAALgAECgEJAgAAAA==.',
Dn='Dng:BAAALgAECgcJCAAAAA==.',
Do='Dogowner:BAAALgAECgkJEgAAAA==.Donora:BAABLgAECn8sAAQGAAkJFRPwTQDTAQAGAAkJFRPwTQDTAQARAAEJfwOjjAAsAAAFAAEJKAYaWAAVAAAAAA==.',
Dr='Drackmontana:BAABLgAECn8lAAMbAAgJaA4gNgDQAQAbAAgJEg4gNgDQAQATAAIJEhVBPQBjAAAAAA==.Drafael:BAAALgADCggJDgABLgAECgkJSwAPAIUhAA==.Dragoniron:BAAALgADCgEJAQAAAA==.Dragony:BAAALgAECgEJBAAAAA==.Dragunass:BAABLgAECn8xAAMbAAkJhBzFEgBWAgAbAAkJChzFEgBWAgATAAcJPBrsEgCyAQAAAA==.Dragøndeath:BAAALgADCgEJAgAAAA==.Drakars:BAAALgADCgUJBAAAAA==.Dranarus:BAAALgADCgQJBAAAAA==.Drexus:BAAALgAECgQJBAAAAA==.Druidblack:BAAALgAECgIJAgAAAA==.Drunkler:BAAALgAECgYJBgAAAA==.Dryter:BAABLgAECn8VAAIIAAcJEA9QKwCEAQAIAAcJEA9QKwCEAQAAAA==.Drákon:BAAALgADCgUJBgAAAA==.',
Du='Dubhe:BAAALgAECgUJEAAAAA==.',
Dy='Dysttopia:BAAALgADCgcJCAAAAA==.',
El='Eldryrin:BAAALgAECgEJAQAAAA==.Elendile:BAAALgAECgEJAQAAAA==.Elinius:BAABLgAECn8vAAMMAAkJzSAeCADIAgAMAAkJzSAeCADIAgADAAIJUwx5zwAuAAAAAA==.Elistraee:BAAALgAECgEJAQAAAA==.Ellandria:BAAALgAECgMJAwAAAA==.Ellonara:BAAALgAECgEJAQAAAA==.Eloren:BAAALgAECgYJCwABLgAECggJIAARAPERAA==.Eluuria:BAAALgAFFAEJAQAAAA==.Elyzia:BAAALgAECgEJAQAAAA==.',
En='Endorena:BAAALgADCgEJAQAAAA==.',
Ep='Ephesus:BAAALgADCgIJAgAAAA==.',
Er='Erikssen:BAAALgADCgYJBgAAAA==.Ernest:BAABLgAECn9DAAIDAAkJ0R4cCAAuAwADAAkJ0R4cCAAuAwAAAA==.Erynneus:BAAALgADCgMJAwAAAA==.',
Es='Estagiario:BAAALgAECgQJBgABLgAFFAIJBQAJAMMYAA==.',
Eu='Eusouobatman:BAAALgADCgIJAgAAAA==.',
Ev='Evetts:BAAALgADCgEJAQAAAA==.Evilbarba:BAAALgAFFAEJAQAAAA==.',
Ex='Exort:BAABLgAECn8ZAAISAAYJcBNanQA6AQASAAYJcBNanQA6AQAAAA==.Expressão:BAAALgADCgYJCwAAAA==.',
Fa='Faeldar:BAACLgAFFH8JAAIaAAMJlAxMLwC7AAAaAAMJlAxMLwC7AAAuAAQKfz8AAhoACQnbErQVAB8CABoACQnbErQVAB8CAAAA.Faldark:BAAALgAECgQJCAAAAA==.Fandrall:BAAALgAECgUJCAAAAA==.Faris:BAABLgAFFH8IAAIcAAIJ2xJrLACkAAAcAAIJ2xJrLACkAAAAAA==.Farmfarm:BAAALgADCgEJAQAAAA==.Faver:BAAALgAECgQJBQAAAA==.Faölin:BAABLgAECn8nAAIcAAcJ1hyvFwDRAQAcAAcJ1hyvFwDRAQAAAA==.',
Fe='Feenigan:BAAALgAECgEJAQABLgAECgQJBAAOAAAAAA==.Feeniä:BAAALgAECgQJBAAAAA==.Ferael:BAABLgAECn84AAIGAAkJTCLmDQDtAgAGAAkJTCLmDQDtAgAAAA==.',
Fi='Fil:BAAALgAECgEJAQAAAA==.Firstomega:BAAALgADCgMJAwAAAA==.',
Fl='Flavors:BAACLgAFFH8GAAIbAAMJzyQZGwA3AQAbAAMJzyQZGwA3AQAuAAQKfyMAAxsACQndI/AGAOgCABsACQndI/AGAOgCABgABAkhHgIUAGYBAAAA.Florbela:BAAALgAECgUJCAAAAA==.Flämbë:BAAALgADCgEJAQAAAA==.',
Fo='Fogue:BAAALgAECgkJEAAAAA==.Foxthamy:BAABLgAECn8mAAIHAAcJaxJKOAB5AQAHAAcJaxJKOAB5AQAAAA==.',
Fr='Frachlitzz:BAACLgAFFH8IAAISAAMJ9Q3zewDZAAASAAMJ9Q3zewDZAAAuAAQKfzsAAhIACQmBFQo9ACACABIACQmBFQo9ACACAAAA.Fradem:BAAALgAECgcJDAAAAA==.Freccianera:BAAALgADCgEJAQAAAA==.Fredericc:BAABLgAECn8aAAMdAAkJCg8RRACPAQAdAAgJwQ0RRACPAQAeAAcJ2gVYWQDfAAAAAA==.Fredinho:BAAALgAECgEJAQAAAA==.Freecs:BAAALgAECgYJBwABLgAECgcJCwAOAAAAAA==.Freyá:BAABLgAECn8jAAIGAAkJcCFuEgDMAgAGAAkJcCFuEgDMAgAAAA==.Frostgore:BAAALgAECgEJAQAAAA==.Froststriker:BAAALgAECgEJAQAAAA==.Frs:BAAALgAECgEJAgAAAA==.',
Ga='Galhuda:BAAALgADCgYJBgAAAA==.Galyan:BAAALgADCgEJAQAAAA==.Gandalpha:BAAALgAECgUJBQAAAA==.Gandwelf:BAAALgADCgkJCQAAAA==.Gazieri:BAABLgAECn8gAAMRAAgJ8RFkRQBiAQARAAgJ8RFkRQBiAQAGAAQJCw/z2gDWAAAAAA==.',
Ge='Geisty:BAAALgAECgMJAwABLgAECgcJHwACAIAJAA==.',
Gh='Ghalladriel:BAAALgADCgEJAwAAAA==.Ghruka:BAAALgAECgQJBAAAAA==.',
Gi='Giafar:BAAALgAECgEJAQABLgAECgYJBgAOAAAAAA==.',
Gl='Gluke:BAAALgAECgMJAwAAAA==.Glutotwo:BAAALgADCgEJAQAAAA==.',
Gn='Gnomari:BAABLgAECn8bAAIUAAgJfAEc8gBwAAAUAAgJfAEc8gBwAAAAAA==.',
Go='Goratrix:BAAALgAECgUJBQABLgAECgcJHwACAIAJAA==.Gordanado:BAAALgAECgEJAgAAAA==.Gordruida:BAAALgAECgEJAQAAAA==.Govers:BAAALgADCgMJAwABLgAECgMJBAAOAAAAAA==.',
Gr='Grandecoisa:BAAALgAECgEJAQAAAA==.Greyfin:BAAALgADCgEJAQAAAA==.Greyvor:BAAALgADCgEJAQAAAA==.Grimch:BAAALgAECgEJAQAAAA==.Grumax:BAABLgAECn8UAAIGAAgJyQ/FdACRAQAGAAgJyQ/FdACRAQAAAA==.Grymysa:BAAALgAECgIJAgAAAA==.Grössa:BAABLgAECn8YAAMRAAcJIwiGWwAOAQARAAcJIwiGWwAOAQAGAAMJCQRIcAE6AAABLgAECgkJFwAUAJ8IAA==.',
Gu='Guitianki:BAAALgAECgEJAQAAAA==.Gulek:BAAALgAECgMJAwAAAA==.Gussg:BAABLgAECn8XAAQUAAkJnwjlYAB6AQAUAAkJnwjlYAB6AQAfAAEJzwiyPQArAAAVAAIJGQQFQwAeAAAAAA==.Gustavonz:BAAALgADCgcJBwAAAA==.',
['Gö']='Göhan:BAAALgADCgUJBQABLgAECgYJEwAOAAAAAA==.',
['Gø']='Gøvers:BAAALgAECgMJBAAAAA==.',
Ha='Handyman:BAAALgADCgYJCgAAAA==.Hantom:BAAALgADCgYJBgABLgAFFAUJDwAIANUZAA==.',
He='Hefestion:BAAALgAECgQJBQAAAA==.Helsingdarck:BAAALgADCgIJAgAAAA==.Hendrikison:BAAALgAECgYJCAAAAA==.',
Hi='Hildegyth:BAABLgAECn8fAAMIAAgJWBE1MQBhAQAIAAcJWRE1MQBhAQAHAAUJZxHJUwAEAQAAAA==.',
Hj='Hjalmar:BAAALgADCgcJCQAAAA==.',
Ho='Hodtiva:BAABLgAECn8tAAMBAAgJdBCoKgB1AQABAAgJdBCoKgB1AQAKAAUJDA6BSgCrAAAAAA==.Homerz:BAAALgADCgEJAQAAAA==.Hotmojo:BAABLgAECn8XAAISAAcJ7wpeoAA2AQASAAcJ7wpeoAA2AQABLgAFFAUJDwAeAE0cAA==.',
Hr='Hrafnn:BAAALgADCgQJBAAAAA==.',
Hu='Hunfox:BAACLgAFFH8VAAIWAAMJUR9pCwAHAQAWAAMJUR9pCwAHAQAuAAQKf0QAAhYACQmuIyEIABIDABYACQmuIyEIABIDAAAA.',
['Hä']='Härkness:BAAALgAECgYJCAAAAA==.',
['Hø']='Høolligans:BAAALgAECgEJAQAAAA==.',
['Hü']='Hüskar:BAABLgAECn8fAAMbAAkJ/AvcLQCSAQAbAAkJuQvcLQCSAQAYAAEJCg+LcwAtAAAAAA==.',
Ic='Icechips:BAAALgADCgUJBQAAAA==.Ichigoz:BAABLgAECn8iAAISAAkJBQptawCeAQASAAkJBQptawCeAQAAAA==.',
Ih='Ihntwuaed:BAAALgADCgYJCQAAAA==.',
Ik='Ikoo:BAABLgAECn9EAAIaAAkJwR0TBwABAwAaAAkJwR0TBwABAwAAAA==.',
Il='Illaril:BAACLgAFFH8gAAIZAAUJpx+cAgBrAQAZAAUJpx+cAgBrAQAuAAQKf2MAAhkACQmMIWQCANcCABkACQmMIWQCANcCAAAA.',
In='Indarion:BAAALgADCgYJEQAAAA==.Ingratt:BAAALgAECgEJAgAAAA==.Invisiblelol:BAAALgAECgIJAgAAAA==.',
Ir='Irmãodouther:BAAALgAECggJCAAAAA==.',
Is='Isebby:BAAALgADCgMJAwAAAA==.Ishtarie:BAAALgAECgQJBQABLgAECgkJHgADAJkXAA==.',
It='Itzzdan:BAAALgADCgMJAwAAAA==.',
Iv='Ivina:BAABLgAECn8UAAMUAAgJThbwkQA1AQAUAAcJThbwkQA1AQAfAAIJqRe4HACNAAAAAA==.',
Iz='Izaar:BAAALgAECgQJDgAAAA==.',
Ja='Jacsonnaik:BAAALgAECgQJBQAAAA==.Jadelina:BAAALgAECgEJAQAAAA==.Janaìna:BAAALgAECgMJAwAAAA==.Jangeoffry:BAAALgADCgEJAQAAAA==.',
Jh='Jhonatinha:BAABLgAECn8VAAMGAAcJBxla0wDhAAAGAAYJaxla0wDhAAARAAQJng69dgCfAAAAAA==.',
Ji='Jigsaww:BAAALgAECgQJCAAAAA==.',
Jo='Joaquim:BAAALgAECgIJAgAAAA==.Jogaveiopl:BAAALgADCgIJAgAAAA==.Johnlobo:BAAALgAECgEJAQAAAA==.Joventino:BAAALgADCgQJBQAAAA==.',
Ju='Jucah:BAABLgAECn8ZAAIeAAkJZAvTNwBJAQAeAAkJZAvTNwBJAQAAAA==.Julabolseiro:BAAALgAFFAEJAQAAAA==.Jullianxd:BAAALgADCgYJCAABLgAECgkJFgAQAOwPAA==.',
Ka='Kaallew:BAABLgAECn8ZAAIFAAkJuRegFgBgAQAFAAkJuRegFgBgAQAAAA==.Kaezar:BAAALgADCgEJAQAAAA==.Kainer:BAAALgAECgQJBQAAAA==.Kalazshar:BAABLgAECn8mAAILAAkJbBJIFACiAQALAAkJbBJIFACiAQAAAA==.Kalelzinho:BAAALgADCgYJCAAAAA==.Kaluss:BAAALgAECgYJDwAAAA==.Kanalet:BAAALgAECgYJCAAAAA==.Kantaa:BAAALgAECgQJCgAAAA==.Kanturu:BAAALgAECgQJBAAAAA==.Kanzaki:BAAALgADCgcJBwABLgAECgkJRgAIAKojAA==.Karonn:BAABLgAECn8UAAIGAAYJ/A3mlABTAQAGAAYJ/A3mlABTAQAAAA==.Kavartu:BAAALgAECgYJBgAAAA==.Kaymon:BAAALgAECgEJAQAAAA==.',
Ke='Keillor:BAABLgAECn8pAAMdAAgJGRbvQQCYAQAdAAcJWRTvQQCYAQAeAAYJXRp9LACEAQAAAA==.Kelantir:BAAALgAECgYJCQABLgAECgkJDAAOAAAAAA==.Keldorian:BAAALgADCgcJEAAAAA==.Kelishe:BAAALgAECgUJBQAAAA==.Kelliar:BAAALgAECgIJAQAAAA==.Kelorn:BAAALgADCgYJBgABLgAECgcJCQAOAAAAAA==.Kelysa:BAAALgADCgkJDgABLgAECggJPQATACYdAA==.Kenzou:BAABLgAECn8YAAMXAAcJ0hhvLwA+AQAXAAUJexxvLwA+AQAIAAcJSQ81NQAiAQAAAA==.',
Kh='Khadi:BAAALgAECgcJCwAAAA==.Khaeltaz:BAAALgAECgMJAwAAAA==.Khalandra:BAABLgAECn8eAAIbAAkJaBtyKwAIAgAbAAkJaBtyKwAIAgAAAA==.Khalel:BAAALgADCgEJAgAAAA==.Khaliq:BAABLgAECn8eAAMJAAkJVxXoEgDxAQAJAAkJVxXoEgDxAQAQAAQJLApxrwCtAAAAAA==.Khallani:BAABLgAECn8fAAICAAcJgAlLlQBWAQACAAcJgAlLlQBWAQAAAA==.Khamul:BAAALgAECgQJBgAAAA==.Khaos:BAAALgAECggJEwAAAA==.Khisto:BAABLgAECn80AAMSAAkJnRtPNgA4AgASAAkJnRtPNgA4AgAgAAcJ3ReDBACVAQAAAA==.Khroriggs:BAAALgAECgYJDQABLgAECgcJBwAOAAAAAA==.',
Ki='Kieran:BAAALgAECgMJAwAAAA==.Killerbiie:BAAALgADCgIJAgAAAA==.Killerdown:BAAALgADCgIJAgAAAA==.Kimashi:BAAALgAECgUJBQAAAA==.Kindie:BAAALgADCgcJCwABLgAECggJFAAQABEIAA==.Kissme:BAACLgAFFH8FAAMMAAMJ2AlXPABuAAAMAAIJdwhXPABuAAALAAEJmwwGNwAtAAAuAAQKfx4AAwwACQmYEN0qAHABAAwACAneEd0qAHABAAsABAmICP9AAI0AAAAA.Kitamor:BAABLgAECn9LAAIMAAkJ2A2mJgCLAQAMAAkJ2A2mJgCLAQAAAA==.Kiya:BAAALgADCgcJHgAAAA==.',
Kl='Klorokina:BAAALgAECgYJBgAAAA==.',
Ko='Koriakin:BAABLgAECn8vAAMWAAkJIR23DgDRAgAWAAkJIR23DgDRAgAhAAcJBxifGADXAQAAAA==.Kosmo:BAAALgAECgQJBAAAAA==.Kotalkhan:BAAALgADCgkJEQAAAA==.',
Kr='Krov:BAAALgAECgEJAQAAAA==.Kryon:BAAALgAECgYJDgAAAA==.Kryzthor:BAAALgAECgYJCAAAAA==.Kräsus:BAABLgAECn9DAAITAAkJAia+AABmAwATAAkJAia+AABmAwAAAA==.Krønna:BAAALgAECgQJBAABLgAECgYJKQAiAEsIAA==.',
Ku='Kul:BAAALgAECgUJBgAAAA==.Kuthila:BAAALgADCgIJAgAAAA==.',
Ky='Kyzaru:BAAALgAECgEJAQAAAA==.',
['Kÿ']='Kÿdou:BAAALgAECgcJDgAAAA==.',
La='Ladrion:BAABLgAECn9WAAQjAAkJtx9lAQDfAgAjAAkJvh5lAQDfAgAcAAkJAxmFFABuAgAkAAkJ9ReXBAA9AgAAAA==.Laetus:BAABLgAECn8ZAAIlAAYJhBgIBgBcAQAlAAYJhBgIBgBcAQAAAA==.Lagosta:BAAALgAECgMJBgAAAA==.Laiany:BAABLgAECn9MAAIKAAkJJSKnAwBJAwAKAAkJJSKnAwBJAwAAAA==.Lani:BAAALgAECgEJAQAAAA==.',
Le='Legacia:BAAALgADCgYJBgAAAA==.Lekrom:BAAALgADCgYJBgAAAA==.Leodoros:BAAALgADCgEJAQAAAA==.Lequinhö:BAAALgAECgIJAgAAAA==.Leric:BAAALgADCgcJCgAAAA==.Lethmar:BAABLgAECn8aAAIUAAcJMxdSWgCKAQAUAAcJMxdSWgCKAQAAAA==.Levanah:BAAALgAFFAIJAgAAAA==.Leyana:BAAALgAECgUJBwAAAA==.',
Lh='Lhwei:BAAALgAECgIJAgABLgAFFAMJCQAHAP4WAA==.',
Li='Liandra:BAAALgAECgEJAQAAAA==.Licaon:BAAALgADCgYJDQAAAA==.Lichkiller:BAAALgAECgUJBQAAAA==.Lightbreaker:BAABLgAECn8jAAIGAAkJZAjFgABiAQAGAAkJZAjFgABiAQAAAA==.Lihr:BAAALgADCgYJCQAAAA==.Lilianpotter:BAAALgAECgEJAQAAAA==.Lilithrix:BAAALgADCgIJAgAAAA==.Lillit:BAABLgAECn84AAQfAAgJ7g2SDgBgAQAUAAgJQw3fZQBtAQAfAAgJfQuSDgBgAQAVAAIJvwalOQA4AAAAAA==.Lindaah:BAABLgAECn8rAAMIAAgJqxdUGwDIAQAIAAgJqxdUGwDIAQAHAAYJ3gSUdgCZAAAAAA==.Lindademon:BAAALgAECgUJDwAAAA==.Lindahealer:BAAALgAECgUJCgABLgAECgUJDwAOAAAAAA==.Lislfox:BAABLgAECn9AAAILAAkJbBoYCABgAgALAAkJbBoYCABgAgAAAA==.Lithlad:BAAALgADCgIJAgAAAA==.',
Lk='Lkinho:BAAALgAECgMJBAAAAA==.',
Lm='Lmmds:BAAALgADCgYJGwAAAA==.',
Lo='Lockynha:BAAALgADCgEJAQAAAA==.Loohynir:BAAALgAFFAIJAwAAAA==.Lotusbird:BAAALgADCgcJBwAAAA==.',
Lu='Lucario:BAAALgAECgEJAgAAAA==.Luccoa:BAAALgAECgkJCQABLgAECgkJQwATAAImAA==.Luccyah:BAAALgADCgkJDgAAAA==.Lucifïr:BAAALgAECgEJAQAAAA==.Lucileia:BAAALgAECgQJBQAAAA==.Lukazgplay:BAAALgADCgIJAgAAAA==.Lutsul:BAAALgAECgEJAQAAAA==.',
Ly='Lylka:BAABLgAECn87AAMFAAkJ0SWFAABoAwAFAAkJ0SWFAABoAwARAAMJIiN/QQAxAQAAAA==.Lyrrena:BAAALgAECgMJBAAAAA==.',
Ma='Maanu:BAAALgAECgcJDwABLgAECggJKwAIAKsXAA==.Macumbadora:BAAALgAECgQJCgAAAA==.Madfulock:BAAALgAECgcJEgAAAA==.Maeghann:BAAALgADCgMJAwAAAA==.Magalândia:BAAALgAECgIJAgAAAA==.Magraver:BAAALgAECgMJAwAAAA==.Mais:BAAALgADCgMJBQAAAA==.Malewolyyc:BAACLgAFFH8IAAMKAAIJyR4eIQCcAAAKAAIJyR4eIQCcAAABAAEJZgdhOAA9AAAuAAQKfysAAwoACQmZIXALAKMCAAoACAk/I3ALAKMCAAEABglGEQ42ADUBAAEuAAUUAwkDAA4AAAAA.Malhun:BAAALgADCgUJDgAAAA==.Malphan:BAAALgAECgcJBwAAAA==.Malyguz:BAACLgAFFH8UAAISAAQJ1BJlUgA3AQASAAQJ1BJlUgA3AQAuAAQKfxsAAhIABwldG+BgABkCABIABwldG+BgABkCAAAA.Malévolaa:BAAALgAECgYJBwAAAA==.Manipullador:BAAALgAECgIJAgAAAA==.Mapussauro:BAAALgAECgcJEQAAAA==.Maradi:BAAALgADCgIJAgAAAA==.Mariob:BAABLgAFFH8FAAImAAIJWgTzNABOAAAmAAIJWgTzNABOAAAAAA==.Marjøly:BAAALgAECgEJAQAAAA==.Markson:BAAALgADCgEJAQAAAA==.Massafera:BAABLgAECn8fAAIGAAkJMxNxVQDAAQAGAAkJMxNxVQDAAQAAAA==.Mather:BAAALgAECgEJAQAAAA==.Mathfacbruxo:BAABLgAECn9FAAIUAAkJIRugHAByAgAUAAkJIRugHAByAgAAAA==.Mauritiuz:BAAALgAFFAEJAQAAAA==.Mayanyy:BAAALgAECgEJAQAAAA==.',
Mc='Mcq:BAAALgAECgEJAQAAAA==.',
Md='Mdrdark:BAACLgAFFH8NAAICAAUJlxToWwAwAQACAAUJlxToWwAwAQAuAAQKfy0AAwIACQmiGZotAEACAAIACQmiGZotAEACACYAAwm/FZ5EAG8AAAAA.',
Me='Medz:BAABLgAECn8jAAISAAkJlRp7LQBdAgASAAkJlRp7LQBdAgAAAA==.Meedea:BAAALgADCgUJBgAAAA==.Meetjack:BAAALgADCgIJAgAAAA==.Meiyin:BAAALgAECgYJCgAAAA==.Melania:BAAALgAECgEJAgAAAA==.Melissandra:BAAALgAFFAIJAwAAAA==.Mellkor:BAABLgAECn8qAAIJAAkJQhvkCwBYAgAJAAkJQhvkCwBYAgAAAA==.Melytah:BAAALgAECgEJAgAAAA==.Melzynhaa:BAAALgAECgEJAgABLgAECggJKwAIAKsXAA==.Meraxxes:BAAALgADCgcJDAAAAA==.Merellien:BAAALgADCggJDgAAAA==.Metamorful:BAABLgAECn8ZAAIDAAkJBxL/SQB7AQADAAkJBxL/SQB7AQAAAA==.',
Mh='Mhorgann:BAAALgAECgUJBgAAAA==.',
Mi='Mijonakombi:BAABLgAECn8WAAIGAAkJ/hrzKwBHAgAGAAkJ/hrzKwBHAgAAAA==.Mikveh:BAAALgAECgYJCgAAAA==.Milim:BAABLgAECn8/AAMNAAkJ8hPhHADoAQANAAkJ2RLhHADoAQAnAAgJRQ2yDgAUAQAAAA==.Milliidan:BAAALgADCgUJBQAAAA==.Mindrathys:BAAALgAECgEJAQAAAA==.Mithrius:BAABLgAECn8kAAIGAAgJxxHOagCOAQAGAAgJxxHOagCOAQAAAA==.',
Ml='Mls:BAAALgADCgYJDgAAAA==.',
Mo='Mogrus:BAAALgADCgMJAwAAAA==.Mohanna:BAAALgAECggJDgAAAA==.Mohanninha:BAAALgAECgYJCwAAAA==.Mohotok:BAABLgAECn9JAAIGAAkJNhm4KABVAgAGAAkJNhm4KABVAgAAAA==.Moonøvesso:BAAALgAECgIJBAAAAA==.Moopp:BAAALgADCgcJCAAAAA==.Mortixxia:BAABLgAECn8oAAIVAAgJnx2xAwBIAgAVAAgJnx2xAwBIAgAAAA==.',
Mu='Muata:BAAALgAECgYJDwAAAA==.Muf:BAAALgAECgYJBgAAAA==.Mupar:BAAALgADCgIJAgAAAA==.Murano:BAABLgAECn8yAAMbAAkJxR6MDACaAgAbAAkJxR6MDACaAgAYAAMJywrUTgCGAAAAAA==.Muzzo:BAAALgADCgYJCwABLgAECgYJCwAOAAAAAA==.',
My='Myrmïdom:BAAALgAECgIJAgAAAA==.Myzoreh:BAAALgAECggJDAAAAA==.',
['Má']='Mágico:BAAALgAECgEJAwAAAA==.Máia:BAABLgAECn8UAAIVAAgJiAzkDwA1AQAVAAgJiAzkDwA1AQAAAA==.',
['Mä']='Mändosz:BAABLgAECn8ZAAMCAAkJMRIGZgCTAQACAAgJahIGZgCTAQAEAAMJCRAMIQCyAAAAAA==.',
['Mé']='Ménace:BAABLgAECn8VAAMUAAkJ5h32WgC3AQAUAAgJ5h32WgC3AQAVAAMJXA7yRgCaAAAAAA==.',
['Mÿ']='Mÿstyna:BAAALgAECgEJAQAAAA==.',
Na='Nalathiel:BAAALgAECgcJEwAAAA==.Narancia:BAAALgAECgYJDQABLgAECgcJCwAOAAAAAA==.Naryth:BAAALgAECgYJCAAAAA==.Nassur:BAAALgADCgEJAQAAAA==.Nattaliaa:BAAALgAECgEJAQAAAA==.Nazawill:BAAALgADCgEJAQAAAA==.Nazdru:BAAALgADCgMJAwABLgAECgkJSwAPAIUhAA==.Nazzh:BAAALgAECgEJAQABLgAECgQJBQAOAAAAAA==.',
Ne='Necronx:BAAALgAECgEJAQAAAA==.Necronxd:BAAALgADCgEJAgAAAA==.Nefas:BAABLgAECn8jAAIVAAkJYxMoBwDWAQAVAAkJYxMoBwDWAQAAAA==.Nefazo:BAAALgAECgcJCgAAAA==.Nefilo:BAAALgADCgYJEAAAAA==.Nepthunus:BAABLgAECn8/AAIgAAkJDyGPAAADAwAgAAkJDyGPAAADAwAAAA==.Nermand:BAAALgAECgEJAQAAAA==.Neshula:BAAALgADCgMJAwAAAA==.Neuvosor:BAAALgAECgEJAQAAAA==.',
Ni='Nibelunga:BAAALgADCgYJBgAAAA==.Nijor:BAAALgADCgYJBgAAAA==.Nilsonssbnu:BAAALgAECgEJAQAAAA==.',
No='Nobelnaga:BAAALgAECgMJAwAAAA==.Novatoo:BAAALgAECgUJDAAAAA==.',
Ny='Nyobb:BAAALgADCgMJAwAAAA==.Nyxra:BAAALgADCgcJEAAAAA==.',
['Nö']='Nöirr:BAAALgAECgEJAQAAAA==.',
Oc='Ocelotte:BAAALgADCgEJAQAAAA==.',
Od='Odin:BAAALgAECgEJAQAAAA==.Odynsabio:BAAALgAECgEJAQAAAA==.',
Of='Ofanzitsu:BAAALgADCgQJBAAAAA==.',
Oi='Oioimiguel:BAAALgADCgYJCwAAAA==.',
Ol='Olhua:BAAALgAECgIJBAAAAA==.Oljedvlad:BAAALgADCgEJAQAAAA==.Oluss:BAAALgADCgUJBQABLgAFFAMJFQAWAFEfAA==.',
Om='Omnath:BAAALgADCgYJBgAAAA==.',
Or='Orillan:BAABLgAECn9DAAMJAAkJDxvACgBsAgAJAAkJDxvACgBsAgAQAAEJhAcY5gAsAAAAAA==.Ornsteinsnow:BAABLgAECn8ZAAIRAAkJvhQIGwAhAgARAAkJvhQIGwAhAgAAAA==.Orob:BAAALgAECgYJDAAAAA==.Ororah:BAAALgAECgYJEAAAAA==.Orukam:BAABLgAECn8ZAAMDAAkJMBZ1QQCCAQADAAgJ7BR1QQCCAQAMAAMJTgiDYgCAAAAAAA==.',
Os='Oszwald:BAAALgADCgEJAQAAAA==.',
['Oú']='Oúkürä:BAAALgAECgYJCgAAAA==.',
Pa='Padawani:BAAALgAECgIJAgAAAA==.Padgodeira:BAAALgAECgQJBAAAAA==.Padrealpha:BAAALgADCgcJCgAAAA==.Padrekelmøn:BAAALgAECgQJBAAAAA==.Palaha:BAAALgADCgEJAQABLgAFFAMJFQAWAFEfAA==.Palatina:BAABLgAFFH8GAAIGAAUJWheROQApAQAGAAUJWheROQApAQAAAA==.Palazzy:BAAALgAECgEJAgAAAA==.Pandong:BAAALgAECggJDwAAAA==.Panena:BAAALgAECgIJAwAAAA==.Pangedrey:BAABLgAECn9TAAMIAAkJ5x+2BwDEAgAIAAkJ5x+2BwDEAgAXAAcJJQSoSgDLAAAAAA==.Paracepatrol:BAAALgAECgQJAwAAAA==.Parcival:BAACLgAFFH8LAAIWAAMJoBohTAD+AAAWAAMJoBohTAD+AAAuAAQKfzIAAhYACQmKI5cEAEADABYACQmKI5cEAEADAAAA.Parký:BAAALgAECgYJBgAAAA==.Pattalógika:BAAALgAECgEJAQAAAA==.Paullk:BAABLgAECn8gAAIMAAYJchQCOgAcAQAMAAYJchQCOgAcAQAAAA==.',
Pe='Pedrinho:BAAALgADCgYJBgABLgAFFAUJEQAQACIgAA==.Penseur:BAAALgAECgcJBwAAAA==.Penéllope:BAAALgAECgQJBwAAAA==.Persëphone:BAABLgAECn8VAAMKAAcJsRQVOwD7AAAKAAUJyRAVOwD7AAABAAYJCBJiVgCuAAAAAA==.Peruchi:BAAALgAECgQJBAAAAA==.',
Pg='Pgms:BAAALgADCgYJDwAAAA==.',
Ph='Phacozitos:BAAALgAECgEJAQAAAA==.Phaxe:BAAALgADCgIJAgAAAA==.Phoenicx:BAAALgADCgMJBgAAAA==.Phøënïx:BAAALgAECgcJDAAAAA==.',
Pi='Pipelinebr:BAAALgAECgUJBQAAAA==.Pitombinha:BAAALgAECgEJAwAAAA==.',
Pl='Plumalume:BAAALgADCgYJBgAAAA==.',
Po='Powalker:BAAALgAECgEJAQAAAA==.',
Pp='Pp:BAABLgAFFH8QAAQaAAUJjQm9JgD5AAAaAAUJjQm9JgD5AAABAAIJ4wY3LgB6AAAKAAEJ6wDUNwAoAAABLgAFFAcJGgANALgRAA==.',
Pr='Prometeus:BAAALgAECgYJDwAAAA==.Pryon:BAAALgAECgUJCwAAAA==.',
Pt='Ptollomeu:BAAALgAECgMJBQABLgAECgMJCQAOAAAAAA==.',
['Pä']='Pändero:BAABLgAECn8WAAIHAAYJ8yLEFwBIAgAHAAYJ8yLEFwBIAgAAAA==.Pänqueca:BAAALgAECgEJAgAAAA==.',
['Pé']='Pénacova:BAAALgADCgEJAQAAAA==.',
['Pî']='Pîo:BAACLgAFFH8HAAISAAMJVxEYdQDmAAASAAMJVxEYdQDmAAAuAAQKfxcAAxIACAltGRRcAMQBABIACAl5GBRcAMQBACUABAnTGPAKACwBAAAA.',
Qu='Quejerok:BAAALgAECgYJEwAAAA==.',
Ra='Radiação:BAAALgAECgIJAgAAAA==.Radunz:BAABLgAECn9LAAIPAAkJhSFeAgD6AgAPAAkJhSFeAgD6AgAAAA==.Ragnaros:BAAALgAFFAEJAQAAAA==.Ragnarssön:BAAALgAECgQJAwAAAA==.Raineko:BAAALgADCgYJBgAAAA==.Raio:BAACLgAFFH8FAAISAAIJlxPNlwCSAAASAAIJlxPNlwCSAAAuAAQKfy8AAhIACQkEIdQbAK0CABIACQkEIdQbAK0CAAAA.Ralfwur:BAAALgAECgQJBwAAAA==.Rargsa:BAABLgAECn8dAAIEAAgJfAbyFgARAQAEAAgJfAbyFgARAQAAAA==.Rariel:BAAALgADCgMJAgAAAA==.Rasmon:BAABLgAECn8uAAIUAAkJRxSCPwDZAQAUAAkJRxSCPwDZAQAAAA==.Ravendreth:BAAALgADCgEJAQAAAA==.Raykarla:BAAALgAECgIJAwAAAA==.Raymain:BAACLgAFFH8GAAMIAAMJzh0uGQD5AAAIAAMJzh0uGQD5AAAHAAEJkw5rWQAvAAAuAAQKfyQAAwcACQkSFvo4AHUBAAcACAmaFPo4AHUBAAgABwkXFoQ1ACEBAAAA.Raíka:BAAALgAECgYJCwAAAA==.',
Re='Reddnose:BAAALgAECgUJCQAAAA==.Reinhold:BAABLgAECn8aAAMGAAcJYRSNdAB6AQAGAAcJYRSNdAB6AQARAAUJ2QhZWADJAAAAAA==.',
Rh='Rhuryk:BAAALgADCggJCAAAAA==.',
Ri='Ricktdai:BAAALgAECgEJAQAAAA==.Riesze:BAACLgAFFH8GAAIWAAMJoRGHUwDrAAAWAAMJoRGHUwDrAAAuAAQKfycAAhYACQl9GRAeAGcCABYACQl9GRAeAGcCAAAA.',
Ro='Roguinhu:BAAALgAECgYJBQAAAA==.Ropaoo:BAABLgAECn8XAAIVAAYJEhaWDgBGAQAVAAYJEhaWDgBGAQAAAA==.',
Ru='Rua:BAAALgAECgQJBAAAAA==.Rurumo:BAAALgADCgQJBAAAAA==.Rusga:BAAALgADCggJCAAAAA==.Rustovick:BAAALgAECgMJBQAAAA==.',
Ry='Rytheas:BAAALgAECgQJBgAAAA==.',
['Rä']='Rämzä:BAAALgAECgYJEwAAAA==.',
['Rå']='Råy:BAAALgAECgQJCQAAAA==.',
['Rí']='Rízadinha:BAAALgAECgQJBAAAAA==.',
Sa='Saargeras:BAAALgADCgMJAwAAAA==.Saffír:BAABLgAECn8mAAIGAAkJTRisMgArAgAGAAkJTRisMgArAgAAAA==.Saiden:BAAALgADCgQJBAAAAA==.Saintkaue:BAAALgADCgUJCAAAAA==.Samalandraa:BAAALgADCgEJAQAAAA==.Sanahh:BAAALgAECgYJCAAAAA==.Sanateia:BAAALgADCgYJCwAAAA==.Santamadre:BAAALgADCgEJAQAAAA==.Sapekinhä:BAACLgAFFH8FAAIJAAIJwxh0HQCLAAAJAAIJwxh0HQCLAAAuAAQKfywABAkACQlJIxoEAAADAAkACQlJIxoEAAADABkAAglSGK8hAIAAABAAAglFCeLrAFQAAAAA.Satanvitória:BAABLgAECn8uAAMYAAgJ7B6gCwAiAgAbAAcJYRo0JgAoAgAYAAgJbh6gCwAiAgAAAA==.Sauroth:BAAALgADCgUJBQAAAA==.',
Sc='Scheiren:BAAALgAECgQJBgAAAA==.',
Se='Senegos:BAAALgADCgcJBwAAAA==.Sereiaa:BAABLgAECn8nAAIWAAcJTBG7YwBxAQAWAAcJTBG7YwBxAQAAAA==.Sesiom:BAAALgAECgcJBgAAAA==.',
Sh='Shalltearr:BAAALgADCgEJAQAAAA==.Shamate:BAAALgAFFAEJAQAAAA==.Shanoa:BAAALgAECgMJAwAAAA==.Shariany:BAAALgADCgEJAQAAAA==.Sharpersong:BAAALgADCgcJBgAAAA==.Shedo:BAABLgAECn8VAAMYAAgJAxoMFgCiAQAYAAcJuBkMFgCiAQAbAAYJWg+VYgAoAQAAAA==.Sheevane:BAABLgAECn8eAAIDAAkJmRcnIwAnAgADAAkJmRcnIwAnAgAAAA==.Shinzo:BAAALgADCgEJAQAAAA==.Shonja:BAAALgADCgcJDgAAAA==.Shula:BAAALgADCgcJDQAAAA==.Shumuk:BAAALgAECgEJAQAAAA==.Shÿnara:BAAALgAECgkJDwAAAA==.',
Si='Siclop:BAAALgADCgYJBgAAAA==.Silgris:BAAALgAECgEJAQABLgAECggJIAARAPERAA==.Silmeria:BAABLgAECn8WAAIdAAgJAgUbbwD+AAAdAAgJAgUbbwD+AAAAAA==.Silverchain:BAAALgADCgcJCgAAAA==.Sinton:BAAALgAECgQJCAAAAA==.',
Sk='Skadryan:BAAALgAECgEJAQAAAA==.Skeletowman:BAAALgADCgEJAQAAAA==.Skineh:BAAALgAECgQJBwAAAA==.Skinme:BAABLgAECn8UAAIHAAYJKwTTfgCDAAAHAAYJKwTTfgCDAAAAAA==.',
Sm='Smylf:BAAALgAECgkJEAAAAA==.',
Sn='Snakedown:BAAALgAECgEJAgAAAA==.',
So='Sombrea:BAAALgAECgYJDQAAAA==.',
Sp='Spectrø:BAAALgAECgYJBgAAAA==.',
Sr='Srheal:BAAALgAECgQJBAAAAA==.Srsapo:BAAALgAECgMJBgAAAA==.',
Ss='Ssamara:BAAALgAECgUJBQAAAA==.',
St='Stampede:BAAALgADCgMJAwAAAA==.Starian:BAABLgAECn8gAAMDAAcJKRyaIwAkAgADAAcJKRyaIwAkAgAMAAEJywwTfwAzAAAAAA==.Stëlla:BAABLgAECn8vAAIdAAgJ3RTyLAD3AQAdAAgJ3RTyLAD3AQAAAA==.',
Su='Suckmyhammer:BAAALgAECgEJAQAAAA==.Sunnara:BAACLgAFFH8RAAIQAAUJIiAaKwBiAQAQAAUJIiAaKwBiAQAuAAQKfyIAAhAACQnwIWQJAPkCABAACQnwIWQJAPkCAAAA.Supergx:BAAALgAECgEJAQAAAA==.Superkx:BAAALgAECgQJBQAAAA==.Suzanomu:BAAALgADCgYJCwAAAA==.',
Sy='Sylran:BAAALgADCgQJBgAAAA==.Synk:BAAALgADCgQJBAAAAA==.Syofra:BAAALgAECgQJBQAAAA==.Syrelys:BAAALgADCgYJBgAAAA==.Syuon:BAACLgAFFH8JAAIHAAMJ/hbQLQDaAAAHAAMJ/hbQLQDaAAAuAAQKfzIAAwcACQkiIWsFAEYDAAcACQkiIWsFAEYDAAgAAgmQBi6CAEcAAAAA.',
['Së']='Sëkhmet:BAAALgAECgYJCwAAAA==.',
['Sï']='Sïmbä:BAABLgAECn8bAAMCAAkJjQ5ObACEAQACAAkJjQ5ObACEAQAEAAEJkAShGQAoAAABLgAFFAEJAQAOAAAAAA==.',
['Sÿ']='Sÿkies:BAAALgADCgEJAQAAAA==.',
Ta='Talandar:BAABLgAECn82AAIMAAkJERnpDwBWAgAMAAkJERnpDwBWAgAAAA==.Tankudo:BAABLgAECn8ZAAICAAYJBhYymwAqAQACAAYJBhYymwAqAQAAAA==.Tannia:BAAALgADCgIJAgAAAA==.Tanthallas:BAAALgAECgEJAQAAAA==.Tavindapedra:BAAALgAECgYJCwAAAA==.',
Tc='Tchutchuco:BAAALgAECgIJAwAAAA==.',
Te='Tekzero:BAAALgAECgEJCAAAAA==.Tempestus:BAAALgADCgYJBgAAAA==.Tennebra:BAAALgADCgYJCAAAAA==.Teobaldo:BAAALgADCgYJCgAAAA==.Terron:BAABLgAECn8wAAMdAAkJEBYRIABCAgAdAAkJEBYRIABCAgAeAAEJFhn5jABJAAAAAA==.',
Th='Thabitah:BAABLgAECn9FAAIBAAkJzB7hBwDNAgABAAkJzB7hBwDNAgAAAA==.Thaliath:BAAALgADCgQJBAAAAA==.Thallariel:BAAALgAECgQJBgAAAA==.Theteo:BAABLgAECn8ZAAIGAAkJZQszegBuAQAGAAkJZQszegBuAQAAAA==.Thiberios:BAAALgAECgUJDAAAAA==.Thirros:BAAALgADCgUJBQAAAA==.Thorres:BAAALgAECgMJBwAAAA==.Thotamon:BAAALgAECgQJCAAAAA==.Throin:BAAALgAECgMJAwAAAA==.Thràain:BAAALgAECgcJDgAAAA==.Thuki:BAAALgADCgYJDQAAAA==.Thunderblade:BAAALgAECgYJDgAAAA==.Théus:BAAALgAECgMJAwABLgAECgkJFQAUAOYdAA==.',
Ti='Tiramisu:BAAALgAECgcJCwAAAA==.',
To='Torâo:BAAALgAECgYJCgAAAA==.Toucinho:BAAALgAECgYJDgAAAA==.',
Tr='Traydd:BAABLgAECn8iAAIPAAgJlBVzDQDOAQAPAAgJlBVzDQDOAQAAAA==.Trollando:BAAALgAECgUJCAAAAA==.',
Tu='Tuga:BAAALgADCgMJAwAAAA==.Turokk:BAABLgAECn8bAAIWAAgJTA/VXACDAQAWAAgJTA/VXACDAQAAAA==.',
Tw='Twilight:BAAALgADCgYJDQAAAA==.Twylluch:BAAALgADCgQJBgABLgAECgkJKAARAOsXAA==.',
Ul='Ulhim:BAAALgADCgcJEwAAAA==.',
Ur='Uriuri:BAAALgADCgYJBgABLgAECgkJSwAPAIUhAA==.',
Us='Usfull:BAABLgAECn87AAMKAAkJHhJkIwCaAQAKAAgJYhNkIwCaAQABAAgJFg1oKwBxAQAAAA==.',
Va='Vacavelha:BAAALgAECgEJAQAAAA==.Vahtorn:BAAALgAECgMJBgAAAA==.Valaerys:BAAALgAECgUJCgAAAA==.Valaniri:BAAALgADCgEJAQAAAA==.Vallkÿria:BAAALgAECgYJBQAAAA==.Vanheelsen:BAAALgAFFAEJAQAAAA==.Vanyathariel:BAAALgAECgEJAQAAAA==.Vareena:BAAALgADCggJCAABLgAECgkJQwATAAImAA==.Vashiel:BAAALgADCgIJAgAAAA==.',
Ve='Vehuiáh:BAABLgAECn8eAAMRAAgJMB2GGwAdAgARAAgJMB2GGwAdAgAGAAEJRQTpqgEjAAAAAA==.Velen:BAABLgAECn8aAAICAAcJshDviwBEAQACAAcJshDviwBEAQAAAA==.Vellkor:BAAALgADCgYJBgAAAA==.Vellon:BAAALgADCgEJAQAAAA==.Venrique:BAAALgAECgMJAwABLgAECgYJEQAOAAAAAA==.Venusa:BAAALgADCgMJBAAAAA==.Verno:BAAALgADCgcJCwAAAA==.Verzuk:BAABLgAECn8dAAICAAgJPQqwggBVAQACAAgJPQqwggBVAQAAAA==.',
Vi='Vidnands:BAAALgAECgEJAQAAAA==.Viinyy:BAAALgAECgMJAwAAAA==.Vilthor:BAAALgAECgUJBQAAAA==.Vintekilo:BAABLgAECn8YAAIGAAkJzRaiYgC9AQAGAAkJzRaiYgC9AQAAAA==.',
Vo='Voiddh:BAAALgAECgcJDAAAAA==.Vokeshar:BAAALgADCgUJBQAAAA==.Voltadupla:BAAALgAECgQJBQAAAA==.Voop:BAAALgADCgYJFAAAAA==.',
Vr='Vrenshrrgn:BAAALgADCgYJBgAAAA==.',
Vy='Vygh:BAACLgAFFH8JAAIUAAMJmBVFbADZAAAUAAMJmBVFbADZAAAuAAQKfy0AAxQACQm5IfwMAOACABQACQm5IfwMAOACABUAAQkjDzpwADYAAAAA.Vyndrill:BAAALgAECgYJDgAAAA==.',
['Vä']='Välion:BAAALgADCgIJAgAAAA==.',
Wa='Wacom:BAAALgADCgUJBQAAAA==.Walkers:BAAALgAECggJDQAAAA==.Warlaka:BAAALgAECgQJBgAAAA==.Warpiel:BAAALgADCgcJDAABLgAECgkJHgAaAC0OAA==.Watchtower:BAAALgAECgQJBAAAAA==.',
We='Wenus:BAAALgAECgIJAgAAAA==.',
Wh='Wheez:BAAALgAECgQJBAABLgAECgkJNAASAJ0bAA==.',
Wi='Williem:BAAALgADCgYJEwAAAA==.',
Wo='Worthy:BAAALgADCgQJBAAAAA==.',
['Wä']='Wätanabe:BAAALgAECgQJBAAAAA==.',
Xa='Xafado:BAAALgAECgEJAQAAAA==.Xamalandrö:BAAALgAECgQJCwAAAA==.',
Xe='Xeal:BAAALgADCgEJAQAAAA==.Xehagus:BAAALgADCgcJCgAAAA==.',
Xi='Xiblaublum:BAAALgADCgMJAwAAAA==.Xinhagoo:BAAALgAECgMJAwAAAA==.Xiquimiro:BAAALgADCgQJBAAAAA==.',
Xx='Xximperadorx:BAAALgADCgIJAgAAAA==.',
Ya='Yasuoh:BAAALgAECgQJCAAAAA==.',
Ye='Yewner:BAAALgADCgYJBQAAAA==.',
Yi='Yingsu:BAABLgAECn8ZAAIXAAkJeCLuDQBQAgAXAAkJeCLuDQBQAgAAAA==.',
Yo='Yoshihime:BAAALgAECgIJAgABLgAECgkJHgADAJkXAA==.',
Yv='Yvin:BAAALgAECgMJBAAAAA==.',
Za='Zallmo:BAABLgAECn8fAAIbAAgJbhVgIwDSAQAbAAgJbhVgIwDSAQAAAA==.Zarath:BAAALgAECgUJBgAAAA==.Zawarudo:BAAALgAECgQJCAAAAA==.',
Ze='Zedd:BAAALgAFFAIJAgAAAA==.Zenorclord:BAAALgADCgQJBgAAAA==.Zeytona:BAABLgAECn8jAAIXAAkJjAvOJAB9AQAXAAkJjAvOJAB9AQAAAA==.',
Zi='Ziracruz:BAAALgAECgQJCwAAAA==.',
['Zí']='Zíngara:BAAALgAECgEJAQAAAA==.',
['Ár']='Árÿä:BAABLgAECn9MAAIWAAkJURW6LQAaAgAWAAkJURW6LQAaAgAAAA==.',
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
