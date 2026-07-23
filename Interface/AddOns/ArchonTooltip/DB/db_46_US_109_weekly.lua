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

local lookup = {'Priest-Shadow','Druid-Restoration','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Unholy','Warrior-Arms','DeathKnight-Frost','DeathKnight-Blood','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Druid-Guardian','Druid-Balance','Evoker-Augmentation','Unknown-Unknown','Warrior-Fury','DemonHunter-Devourer','Paladin-Holy','Mage-Frost','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Monk-Brewmaster','Priest-Discipline','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Mage-Fire','Hunter-Survival','Shaman-Enhancement','Rogue-Outlaw','Rogue-Assassination','Mage-Arcane','Evoker-Devastation','Evoker-Preservation',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abelao:BAAALgAECgcJEwAAAA==.',
Ad='Adelaide:BAAALgAECgIJAgABLgAFFAkJLQABAD8ZAA==.Adoramuss:BAAALgAECgYJCwAAAA==.Adrianoj:BAAALgAECgEJAQABLgAFFAIJBQACAD0RAA==.',
Ae='Aeklug:BAAALgAECgIJAgAAAA==.Aelon:BAAALgADCgcJDAAAAA==.Aelthor:BAABLgAECn8WAAIDAAQJ3BEeBgDIAAADAAQJ3BEeBgDIAAAAAA==.Aemeath:BAABLgAECn8XAAMEAAkJiyHXAQD8AgAEAAkJiyHXAQD8AgAFAAIJnhgCSgCOAAAAAA==.Aenthür:BAAALgAECgEJAQAAAA==.',
Ah='Ahammes:BAAALgAECgQJBAABLgAECgcJHwAGAIAJAA==.Ahmus:BAAALgAECgUJDAAAAA==.Ahrallu:BAAALgADCgEJAgAAAA==.',
Ai='Aioliavictus:BAAALgAECgEJAQAAAA==.',
Ak='Akaynu:BAAALgAECgEJAQAAAA==.',
Al='Alanie:BAAALgAECgUJDQABLgAFFAIJBgAHAOkPAA==.Aldranir:BAAALgADCgEJAQAAAA==.Alessaxd:BAACLgAFFH8KAAIGAAIJlBARWwCSAAAGAAIJlBARWwCSAAAuAAQKfy8ABAYACQmiFbk6ABUCAAYACQmhFbk6ABUCAAgABwmcEnwTAEMBAAkAAglLBvcWABwAAAAA.Alexa:BAAALgAECgQJBAAAAA==.Alfajhor:BAABLgAECn86AAMKAAgJFx+6EAC5AQAKAAYJoyK6EAC5AQALAAgJZx0KYgCsAQAAAA==.Alfajhòr:BAAALgAECgIJAgAAAA==.Alfajhôr:BAAALgAECgUJBwAAAA==.Alkarin:BAAALgAECgEJAwAAAA==.Allandriel:BAAALgAECgQJBAAAAA==.Alldarion:BAAALgAECgMJCQAAAA==.Allendra:BAAALgADCgcJCQAAAA==.Alleriane:BAACLgAFFH8GAAIMAAIJOherSACDAAAMAAIJOherSACDAAAuAAQKfz8AAwwACQlEH7UIABADAAwACQlEH7UIABADAA0AAQmnApGNABgAAAAA.Allerios:BAAALgAECgUJCQAAAA==.Allone:BAACLgAFFH8HAAIFAAMJCQcOEACcAAAFAAMJCQcOEACcAAAuAAQKfyQAAgUACAlJEqUpADABAAUACAlJEqUpADABAAAA.Allyhra:BAAALgADCgQJBAAAAA==.Allëria:BAAALgADCgMJAwAAAA==.Alruna:BAAALgAECgEJAQAAAA==.',
Am='Ametnys:BAAALgAECgQJDwAAAA==.Amonhar:BAAALgAECgQJBQABLgAECgkJOwAOAB4SAA==.Amyn:BAAALgADCgYJBwAAAA==.',
An='Anakata:BAABLgAECn8cAAQPAAYJ3RVhLAD+AAAPAAYJ3RVhLAD+AAACAAIJ+wW80QAzAAAQAAEJww8qjgAyAAAAAA==.Anakinini:BAACLgAFFH8FAAIRAAIJFgHzYwBDAAARAAIJFgHzYwBDAAAuAAQKfyIAAhEACAlsCTVEABkBABEACAlsCTVEABkBAAEuAAQKBgkMABIAAAAA.Analia:BAABLgAECn8lAAQCAAgJFR5/HgBLAgACAAcJVR1/HgBLAgAPAAgJnQgHOADGAAAQAAUJxhs8DgCYAAABLgAFFAIJBgAHAOkPAA==.Andaliz:BAACLgAFFH8SAAILAAMJwSbAMABQAQALAAMJwSbAMABQAQAuAAQKfzYAAgsACQkLJjIDAGcDAAsACQkLJjIDAGcDAAEuAAUUBQkGAAsAWhcA.Andorith:BAAALgAECgEJAgAAAA==.Anelie:BAAALgAECgQJDQABLgAFFAIJBgAHAOkPAA==.Annhe:BAAALgAECgEJAQAAAA==.Ansalon:BAAALgADCgYJBwAAAA==.Anthorus:BAAALgAECgUJBgAAAA==.Antonellaes:BAAALgAECgUJCgABLgAECgcJDgASAAAAAA==.',
Ao='Aoiisuu:BAAALgADCgYJCAAAAA==.',
Ap='Apodrecido:BAAALgAECgYJBgAAAA==.Apoxus:BAAALgADCgIJAgAAAA==.',
Ar='Arajakata:BAAALgAECgEJBgAAAA==.Arctorius:BAABLgAECn8WAAILAAcJbQ8IpwAtAQALAAcJbQ8IpwAtAQAAAA==.Arethiel:BAAALgADCgYJBgAAAA==.Arlandriah:BAAALgADCgYJCQABLgAECgYJGAALABAYAA==.Artronis:BAACLgAFFH8JAAIPAAQJCwthHACuAAAPAAQJCwthHACuAAAuAAQKfycAAw8ACQluFxwVAKwBAA8ACAlPFhwVAKwBAAMAAgnFGQQMAF0AAAAA.Artånis:BAAALgAECgcJDAAAAA==.Arukäi:BAABLgAECn8UAAITAAkJ8A9IBACcAQATAAkJ8A9IBACcAQAAAA==.Aruthuro:BAAALgAECgYJEgAAAA==.',
As='Ashbörn:BAAALgAECgQJCAAAAA==.Astel:BAABLgAECn8mAAIUAAkJUxbvAwDbAQAUAAkJUxbvAwDbAQAAAA==.',
At='Atriuz:BAABLgAECn8bAAIVAAYJahouLwDGAQAVAAYJahouLwDGAQAAAA==.Ats:BAAALgAECgMJBQAAAA==.',
Ay='Aykho:BAABLgAECn8nAAIWAAgJRRY7aACsAQAWAAgJRRY7aACsAQAAAA==.',
Az='Azurion:BAAALgAECgYJCgAAAA==.',
['Aÿ']='Aÿ:BAAALgAECgMJBAAAAA==.',
Ba='Baguh:BAAALgADCggJCAAAAA==.Bagunça:BAAALgADCgYJBgAAAA==.Bakuugou:BAAALgAECgMJCgAAAA==.Balk:BAAALgAECgQJBAAAAA==.Balthar:BAAALgAFFAIJAgAAAA==.Bambur:BAAALgADCgMJAwAAAA==.Barbabruto:BAABLgAECn8+AAIXAAkJZx5uBwCMAgAXAAkJZx5uBwCMAgAAAA==.Basilisco:BAAALgAECgEJAQAAAA==.',
Be='Belleg:BAAALgAECgEJAgAAAA==.Beronhuz:BAAALgAECgMJAwAAAA==.',
Bf='Bf:BAAALgAECgEJBAAAAA==.',
Bi='Biafalcão:BAAALgAECgEJAQAAAA==.Bijanca:BAAALgAECgYJBgAAAA==.Birthdäy:BAAALgADCgEJAQAAAA==.Bisponegro:BAAALgAECgQJCwABLgABCgcJFQASAAAAAA==.Biønic:BAAALgAECgMJCQAAAA==.',
Bl='Blackline:BAACLgAFFH8HAAIGAAMJrwvzRADGAAAGAAMJrwvzRADGAAAuAAQKfyIAAgYACAlWE25hAKYBAAYACAlWE25hAKYBAAAA.Blueish:BAAALgAECgUJBQABLgAECggJGgACAOsTAA==.',
Bo='Boipretim:BAAALgAECgYJDwAAAA==.Bontorius:BAAALgADCgEJAgAAAA==.Bordello:BAAALgADCgUJBQAAAA==.',
Br='Bradio:BAAALgADCggJCAAAAA==.Brahman:BAAALgAECgEJBAAAAA==.Bratloko:BAAALgAECgUJBQAAAA==.Braverne:BAAALgAECgEJAQAAAA==.Bromos:BAAALgAECgQJCAAAAA==.Brutalhoof:BAAALgAECgQJBAAAAA==.Brönsted:BAAALgADCgMJAwAAAA==.',
Bu='Bubbalo:BAAALgADCgUJBQAAAA==.Bullsman:BAAALgADCgQJBAAAAA==.Buzzumaaky:BAABLgAECn8YAAIWAAgJTxepiQC/AQAWAAgJTxepiQC/AQAAAA==.',
By='Byakura:BAAALgADCggJCwAAAA==.',
['Bü']='Büdweiser:BAAALgAECgcJEQAAAA==.',
Ca='Cabernet:BAAALgAECgUJBwAAAA==.Cabeçaquente:BAAALgAECgcJCQAAAA==.Cabinking:BAAALgAECgIJAgAAAA==.Calanthe:BAAALgADCgkJCQAAAA==.Calhistra:BAABLgAECn8nAAMYAAgJQxmBTAC1AQAYAAgJQxmBTAC1AQAZAAIJRQokVQBvAAAAAA==.Callstorm:BAAALgADCgcJBwAAAA==.Calteryeker:BAABLgAECn8bAAILAAgJLRw1BgD2AQALAAgJLRw1BgD2AQAAAA==.Camillas:BAAALgAECggJDwAAAA==.Caosenvy:BAAALgAECgEJAQAAAA==.Caralh:BAAALgAECgEJAgAAAA==.Caroll:BAAALgAECgIJAgAAAA==.Castaldi:BAAALgAECgEJAgABLgAECgcJCwASAAAAAA==.Cathe:BAABLgAECn8aAAIaAAYJ6R0/YQCEAQAaAAYJ6R0/YQCEAQAAAA==.Caçaorda:BAAALgAECgMJBAAAAA==.',
Ce='Cecilith:BAAALgAECggJDQAAAA==.Cernunos:BAAALgADCgEJAQAAAA==.Cernûnnos:BAACLgAFFH8FAAICAAIJPRGMUwB3AAACAAIJPRGMUwB3AAAuAAQKfxUAAgIABglOD5RdAB4BAAIABglOD5RdAB4BAAAA.',
Ch='Champdude:BAABLgAECn9RAAQNAAkJqiPjAwAfAwANAAkJqiPjAwAfAwAbAAgJJxuBEQAtAgAMAAMJjR4VWwAIAQAAAA==.Changeman:BAAALgAECgEJAQAAAA==.Chankowkwai:BAAALgAECgYJCQAAAA==.Chanë:BAAALgADCgIJAwAAAA==.Chaosangel:BAAALgAECgUJCgABLgAFFAMJCgAQAMgHAA==.Chewi:BAAALgAECgQJBwAAAA==.Chrnnos:BAAALgAECgYJBgAAAA==.',
Ci='Citra:BAAALgAECgMJBwAAAA==.',
Co='Coconolose:BAAALgAECgIJBgAAAA==.Cod:BAAALgAECgIJAwAAAA==.Codecks:BAAALgADCgYJBgAAAA==.Coldbringer:BAAALgAECgEJAQAAAA==.Coldhearths:BAAALgAECgUJBgAAAA==.Cortegelido:BAAALgADCgIJAgAAAA==.Couro:BAAALgAECggJCwAAAA==.Cowçadora:BAAALgAECgMJAwAAAA==.',
Cr='Criminøsa:BAAALgAECgcJCQAAAA==.Cristcalad:BAABLgAECn9LAAMHAAkJERu6CQBRAgAHAAkJ/Bm6CQBRAgAXAAcJyBZ7AgCnAQAAAA==.Cryomanta:BAAALgAECgUJBQAAAA==.',
Cu='Cunhaovirado:BAABLgAECn8YAAILAAcJagPfPgBQAAALAAcJagPfPgBQAAABLgAFFAYJEQANAOEXAA==.Cunhazinha:BAAALgAECgQJBAAAAA==.Cupyncha:BAAALgADCgcJBwAAAA==.Cutia:BAAALgADCgEJAQAAAA==.Cutiesissy:BAAALgAECgQJCAABLgAECgcJGgALAEoQAA==.',
['Cø']='Cøøkye:BAAALgAECgQJBQAAAA==.',
Da='Daellus:BAAALgADCgUJBQAAAA==.Daemi:BAAALgAECgIJBAAAAA==.Daibodan:BAAALgAECgEJBAAAAA==.Dalaty:BAAALgAECgUJBQAAAA==.Daniilos:BAAALgAFFAEJAQAAAA==.Daresh:BAAALgADCgIJAgAAAA==.Darklara:BAABLgAECn8lAAIEAAkJBRkQCQDeAQAEAAkJBRkQCQDeAQAAAA==.Darkove:BAABLgAECn8vAAIWAAkJjBIrVADgAQAWAAkJjBIrVADgAQAAAA==.Darrow:BAACLgAFFH8SAAMGAAQJUh0iSgBeAQAGAAQJ+BsiSgBeAQAIAAMJdxyfEQAGAQAuAAQKfy8AAwYACQnPJP0PAOwCAAYACQn0I/0PAOwCAAgACAn8IloDALMCAAAA.Dartibeccoso:BAAALgADCgcJBwAAAA==.Daviberger:BAAALgAECgMJAwAAAA==.',
De='Deany:BAAALgAECgEJAgAAAA==.Deathinhu:BAABLgAECn9gAAIWAAkJaSGdAgDMAgAWAAkJaSGdAgDMAgAAAA==.Deathnacht:BAAALgAECgQJCQAAAA==.Delset:BAAALgADCgIJAgAAAA==.Demiun:BAAALgADCgUJBQAAAA==.Demojoca:BAAALgAECgIJAgABLgAECgcJDgASAAAAAA==.Dentepodre:BAAALgADCgEJAQAAAA==.Dervus:BAAALgADCgcJBwAAAA==.Dethroned:BAAALgAECgUJDAAAAA==.Devrath:BAAALgAECgEJAQAAAA==.Devyogi:BAAALgADCgcJCAAAAA==.',
Di='Diefs:BAAALgAECgEJAQAAAA==.Dimeros:BAABLgAECn9KAAIQAAkJTRbSAgDhAQAQAAkJTRbSAgDhAQAAAA==.Dito:BAAALgADCgEJAQAAAA==.Divano:BAACLgAFFH8SAAIBAAMJ8hu4DAABAQABAAMJ8hu4DAABAQAuAAQKfzEAAwEACQlGH2cNAH4CAAEACQlGH2cNAH4CABwAAwkCCXJgAHwAAAAA.',
Dk='Dkats:BAAALgAECgEJAgAAAA==.',
Dn='Dng:BAAALgAECgcJCAAAAA==.',
Do='Dogowner:BAAALgAECgkJEgAAAA==.Dogs:BAABLgAFFH8IAAILAAIJmxo0OACjAAALAAIJmxo0OACjAAAAAA==.Donora:BAABLgAECn8sAAQLAAkJFRNpUwDPAQALAAkJFRNpUwDPAQAVAAEJfwN0kgAsAAAKAAEJKAYUXQAVAAAAAA==.',
Dr='Drackmontana:BAABLgAECn8lAAMTAAgJaA4gNgDQAQATAAgJEg4gNgDQAQAXAAIJEhVBPQBjAAAAAA==.Drafael:BAAALgADCggJDgABLgAECgkJXQADAFoiAA==.Dragonfoox:BAAALgAECgIJAgAAAA==.Dragoniron:BAAALgADCgEJAQAAAA==.Dragony:BAAALgAECgEJBAAAAA==.Dragunass:BAABLgAECn9GAAMTAAkJQR9BAwDSAQATAAkJXR5BAwDSAQAXAAgJdBm2EgDAAQAAAA==.Dragøndeath:BAAALgADCgEJAgAAAA==.Drakars:BAAALgADCgUJBAAAAA==.Dranarus:BAAALgADCgQJBAAAAA==.Drexus:BAAALgAECgQJBAAAAA==.Druidblack:BAAALgAECgIJAwAAAA==.Drunkler:BAAALgAECgYJBwAAAA==.Dryter:BAABLgAECn8VAAINAAcJEA9QKwCEAQANAAcJEA9QKwCEAQAAAA==.Drákon:BAAALgAECgEJAQAAAA==.',
Du='Dubhe:BAABLgAECn8dAAMVAAkJERQLAgApAgAVAAkJERQLAgApAgALAAQJbBSiwAAHAQAAAA==.',
Dy='Dysttopia:BAAALgADCgcJCAAAAA==.',
El='Eldryrin:BAAALgAECgEJAQAAAA==.Elendile:BAAALgAECgEJAQAAAA==.Elinius:BAABLgAECn8vAAMQAAkJzSDQCADGAgAQAAkJzSDQCADGAgACAAIJUwyU2QArAAAAAA==.Elistraee:BAAALgAECgEJAQAAAA==.Ellandria:BAAALgAECgMJAwAAAA==.Ellonara:BAAALgAECgEJAQAAAA==.Ellvarg:BAAALgADCgQJBAAAAA==.Eloren:BAAALgAECgYJCwABLgAECggJIAAVAPERAA==.Eluuria:BAAALgAFFAEJAQAAAA==.Elyzia:BAAALgAECgEJAQAAAA==.',
En='Endorena:BAAALgADCgEJAQAAAA==.Ensabanú:BAAALgAECgEJAgAAAA==.',
Ep='Ephesus:BAAALgADCgIJAgAAAA==.',
Er='Erikssen:BAAALgADCgYJBgAAAA==.Ernest:BAABLgAECn9VAAICAAkJVh+SCAAvAwACAAkJVh+SCAAvAwAAAA==.Erynneus:BAAALgADCgMJAwAAAA==.',
Es='Estagiario:BAAALgAECgQJBgABLgAFFAIJBQAFAMMYAA==.Estgan:BAAALgADCgYJBgAAAA==.',
Eu='Eusouobatman:BAAALgADCgIJAgAAAA==.',
Ev='Evetts:BAAALgADCgEJAQAAAA==.Evilbarba:BAABLgAFFH8FAAILAAIJNBCkjwCTAAALAAIJNBCkjwCTAAAAAA==.',
Ex='Exort:BAABLgAECn8gAAIWAAYJlBVjmwBDAQAWAAYJlBVjmwBDAQAAAA==.Exothus:BAAALgAECgEJAgAAAA==.Expressão:BAAALgADCgYJCwAAAA==.Exødus:BAAALgAECgEJAQAAAA==.',
Fa='Faeldar:BAACLgAFFH8XAAIcAAQJvxBlEgDsAAAcAAQJvxBlEgDsAAAuAAQKf1sAAhwACQmAH68AAE0DABwACQmAH68AAE0DAAAA.Fafabr:BAAALgAECgEJAQAAAA==.Faldark:BAAALgAECgYJDgAAAA==.Fandrall:BAAALgAECgUJCAAAAA==.Faris:BAABLgAFFH8KAAIdAAMJzw5+HQB3AAAdAAMJzw5+HQB3AAAAAA==.Farmfarm:BAAALgADCgEJAQAAAA==.Faver:BAAALgAECgQJBQAAAA==.Faölin:BAABLgAECn8sAAIdAAcJxR0hBABQAQAdAAcJxR0hBABQAQAAAA==.',
Fe='Feenigan:BAAALgAECgEJAQABLgAECgQJBAASAAAAAA==.Feeniä:BAAALgAECgQJBAAAAA==.Ferael:BAABLgAECn9BAAMLAAkJZCLPDwDoAgALAAkJZCLPDwDoAgAVAAgJ2RpdAQB9AgAAAA==.',
Fi='Fil:BAAALgAECgEJAQAAAA==.Firstomega:BAAALgADCgMJAwAAAA==.',
Fl='Flavors:BAACLgAFFH8GAAITAAMJzyTlIAAvAQATAAMJzyTlIAAvAQAuAAQKfyMAAxMACQndI+UHAOECABMACQndI+UHAOECAAcABAkhHgIUAGYBAAAA.Florbela:BAAALgAECgUJCQAAAA==.Flämbë:BAAALgADCgEJAQAAAA==.',
Fo='Foemablack:BAAALgAECgQJBAAAAA==.Fogue:BAAALgAECgkJEgAAAA==.Foxthamy:BAABLgAECn8mAAIMAAcJaxLKPAB8AQAMAAcJaxLKPAB8AQAAAA==.',
Fr='Frachlitzz:BAACLgAFFH8JAAIWAAMJWA+1hQDNAAAWAAMJWA+1hQDNAAAuAAQKfz0AAhYACQkhFn86AC8CABYACQkhFn86AC8CAAAA.Fradem:BAAALgAECgcJDQAAAA==.Freccianera:BAAALgADCgEJAQAAAA==.Fredericc:BAABLgAECn8cAAMeAAkJlw/2RwCOAQAeAAgJYA72RwCOAQAfAAcJ2gVYWQDfAAAAAA==.Fredinho:BAAALgAECgEJAQAAAA==.Freecs:BAAALgAECgYJBwABLgAECgcJCwASAAAAAA==.Freyá:BAABLgAECn8jAAILAAkJcCGHFADHAgALAAkJcCGHFADHAgAAAA==.Frostgore:BAAALgAECgEJAQAAAA==.Froststriker:BAAALgAECgEJAQAAAA==.Frozenn:BAAALgAECgUJBAABLgAECggJQQANAIYcAA==.Frs:BAAALgAECgEJAgAAAA==.',
Ga='Galfur:BAAALgAECgEJAQAAAA==.Galhuda:BAABLgAECn8WAAICAAYJ4Q9rBwAnAQACAAYJ4Q9rBwAnAQAAAA==.Galyan:BAAALgADCgEJAQAAAA==.Gandalpha:BAAALgAECgUJBwAAAA==.Gandwelf:BAAALgADCgkJCQAAAA==.Gazieri:BAABLgAECn8gAAMVAAgJ8RFkRQBiAQAVAAgJ8RFkRQBiAQALAAQJCw/z2gDWAAAAAA==.',
Ge='Geeklimim:BAAALgAECgEJAQAAAA==.Geisty:BAAALgAECgMJAwABLgAECgcJHwAGAIAJAA==.',
Gh='Ghalladriel:BAAALgADCgEJAwAAAA==.Ghruka:BAAALgAECgQJBAAAAA==.',
Gi='Giafar:BAAALgAECgEJAQABLgAECgYJDAASAAAAAA==.Ginea:BAAALgAECgEJAQAAAA==.',
Gl='Gluke:BAAALgAECgMJAwAAAA==.Glutotwo:BAAALgADCgQJBgAAAA==.',
Gn='Gnomari:BAABLgAECn8kAAIYAAgJJQL35ACTAAAYAAgJJQL35ACTAAAAAA==.',
Go='Goratrix:BAAALgAECgUJBQABLgAECgcJHwAGAIAJAA==.Gordanado:BAAALgAECgEJAgAAAA==.Gordruida:BAAALgAECgEJAQAAAA==.Govers:BAAALgADCgMJAwABLgAECgMJBAASAAAAAA==.',
Gr='Grandecoisa:BAAALgAECgEJAQAAAA==.Greyfin:BAAALgAECgEJBAAAAA==.Greyvor:BAAALgADCgEJAQAAAA==.Grimch:BAAALgAECgEJAQAAAA==.Grommar:BAAALgAECgEJAQABLgAECggJGwALAC0cAA==.Grumax:BAABLgAECn8UAAILAAgJyQ/FdACRAQALAAgJyQ/FdACRAQAAAA==.Grymysa:BAAALgAECgIJAgAAAA==.Grössa:BAABLgAECn8YAAMVAAcJIwiGWwAOAQAVAAcJIwiGWwAOAQALAAMJCQRdhgE5AAABLgAECgkJFwAYAJ8IAA==.',
Gu='Gugsã:BAAALgAECgEJAgAAAA==.Guitianki:BAAALgAECgEJAQAAAA==.Gulek:BAAALgAECgQJBAAAAA==.Gussg:BAABLgAECn8XAAQYAAkJnwgmZwBvAQAYAAkJnwgmZwBvAQAgAAEJzwgcQwArAAAZAAIJGQTpRgAeAAAAAA==.Gustavonz:BAAALgADCgcJBwAAAA==.',
['Gö']='Göhan:BAAALgADCgUJBQABLgAECgYJEwASAAAAAA==.',
['Gø']='Gøvers:BAAALgAECgMJBAAAAA==.',
Ha='Hakuouki:BAAALgAECgMJAwAAAA==.Hammurabi:BAAALgADCgEJAQAAAA==.Handyman:BAAALgADCgYJCgAAAA==.Hantom:BAAALgADCgYJBgABLgAFFAYJEQANAOEXAA==.Harchus:BAAALgADCgEJAQAAAA==.Hazell:BAAALgADCgYJBgAAAA==.',
He='Heaveth:BAAALgAECgMJAwABLgAFFAMJCwAfAP4cAA==.Hefestion:BAAALgAFFAMJBAAAAA==.Hellspont:BAAALgAECgkJDgAAAA==.Helsingdarck:BAAALgADCgIJAgAAAA==.Hendrikison:BAAALgAECgcJCgAAAA==.',
Hi='Hildegyth:BAABLgAECn8fAAMNAAgJWBE1MQBhAQANAAcJWRE1MQBhAQAMAAUJZxG8WwAGAQAAAA==.',
Hj='Hjalmar:BAAALgADCgcJCQAAAA==.',
Ho='Hodtiva:BAABLgAECn8xAAMBAAgJ+BPeLQBqAQABAAgJ+BPeLQBqAQAOAAYJRA9nEABmAAAAAA==.Homerz:BAAALgADCgEJAQAAAA==.Horagalles:BAAALgAECgEJAQAAAA==.Hotmojo:BAABLgAECn8eAAIWAAgJOw+5eQCFAQAWAAgJOw+5eQCFAQABLgAFFAcJFgAfABsYAA==.',
Hu='Hunfox:BAACLgAFFH8XAAIaAAQJUhhpCwAHAQAaAAQJUhhpCwAHAQAuAAQKf0QAAhoACQmuI78JAAoDABoACQmuI78JAAoDAAAA.Hunterzika:BAAALgAECgEJAQAAAA==.Huor:BAAALgAECgIJAgAAAA==.',
['Hä']='Härkness:BAAALgAECgYJCAAAAA==.',
['Hø']='Høolligans:BAAALgAECgEJAQAAAA==.',
['Hü']='Hüskar:BAABLgAECn8fAAMTAAkJ/AuTMQCGAQATAAkJuQuTMQCGAQAHAAEJCg8JfAAtAAAAAA==.',
Ic='Icechips:BAAALgADCgUJBQAAAA==.Ichigoz:BAABLgAECn8iAAIWAAkJBQqscgCUAQAWAAkJBQqscgCUAQAAAA==.',
Ih='Ihntwuaed:BAAALgADCgYJCwAAAA==.',
Ik='Ikoo:BAABLgAECn9WAAIcAAkJkSAGAQDwAgAcAAkJkSAGAQDwAgAAAA==.',
Il='Illaril:BAACLgAFFH8mAAIEAAYJIx2xAQC3AQAEAAYJIx2xAQC3AQAuAAQKf2UAAgQACQmMIWQCANcCAAQACQmMIWQCANcCAAAA.',
In='Indarion:BAAALgADCgYJEQAAAA==.Ingratt:BAAALgAECgEJAgAAAA==.Invisiblelol:BAAALgAECgIJAgAAAA==.',
Ir='Irmãodouther:BAAALgAFFAIJAwAAAA==.Irontoko:BAAALgAECgYJBgAAAA==.',
Is='Isebby:BAAALgADCgMJAwAAAA==.Ishtarie:BAAALgAECgQJBQABLgAECgkJHgACAJkXAA==.',
It='Itzzdan:BAAALgADCgMJAwAAAA==.',
Iv='Ivina:BAACLgAFFH8LAAIYAAQJnwtpIgD5AAAYAAQJnwtpIgD5AAAuAAQKfxcAAxgACQniFtgPANgAABgACAniFtgPANgAACAAAgmpF7gcAI0AAAAA.',
Iz='Izaar:BAAALgAECgQJEwAAAA==.',
Ja='Jacsonnaik:BAAALgAECgQJBQAAAA==.Jadelina:BAAALgAECgEJAQAAAA==.Janaìna:BAAALgAECgMJAwAAAA==.Jangeoffry:BAAALgADCgEJAQAAAA==.Jaymee:BAAALgAECgEJBAAAAA==.',
Je='Jetset:BAAALgAECgMJAwABLgAECgkJFgAUAOwPAA==.',
Jh='Jhonatinha:BAABLgAECn8VAAMLAAcJBxkN3gDgAAALAAYJaxkN3gDgAAAVAAQJng69dgCfAAAAAA==.',
Ji='Jigsaww:BAAALgAECgQJCQAAAA==.',
Jk='Jks:BAAALgAECgYJEAAAAA==.',
Jo='Joaquim:BAAALgAECgIJAgAAAA==.Jogaveiopl:BAAALgADCgIJAgAAAA==.Johnlobo:BAAALgAECgEJAQAAAA==.Joventino:BAAALgADCgQJBQAAAA==.',
Ju='Jucah:BAABLgAECn8ZAAIfAAkJZAt6OwBIAQAfAAkJZAt6OwBIAQAAAA==.Julabolseiro:BAABLgAECn8ZAAMOAAgJgBC3CQDcAAAOAAgJgBC3CQDcAAABAAIJBgJAiQAwAAAAAA==.Julinhas:BAAALgAECgEJAQAAAA==.Jullianxd:BAAALgAECgMJAwABLgAECgkJFgAUAOwPAA==.Juzefa:BAAALgAECgcJBAAAAA==.',
Ka='Kaallew:BAABLgAECn8ZAAIKAAkJuRccGABdAQAKAAkJuRccGABdAQAAAA==.Kaelonidas:BAAALgAECgEJAQAAAA==.Kaezar:BAAALgADCgEJAQAAAA==.Kainer:BAAALgAECgQJBwAAAA==.Kalazshar:BAABLgAECn8mAAIPAAkJbBI0FgCiAQAPAAkJbBI0FgCiAQAAAA==.Kalduran:BAAALgADCgEJAQAAAA==.Kalelzinho:BAAALgAECgEJAQAAAA==.Kaluss:BAABLgAECn8XAAIWAAgJvAbCIwCgAAAWAAgJvAbCIwCgAAAAAA==.Kanalet:BAAALgAECgYJCAAAAA==.Kandára:BAAALgADCgYJBgAAAA==.Kantaa:BAAALgAECgQJDQAAAA==.Kanturu:BAAALgAECgQJBAAAAA==.Kanzaki:BAAALgADCgcJBwABLgAECgkJUQANAKojAA==.Karonn:BAABLgAECn8UAAILAAYJ/A3mlABTAQALAAYJ/A3mlABTAQAAAA==.Kavartu:BAAALgAFFAEJAQAAAA==.Kaymon:BAAALgAECgEJAQAAAA==.',
Ke='Keillor:BAABLgAECn8pAAMeAAgJGRaYRQCXAQAeAAcJWRSYRQCXAQAfAAYJXRqCLwCCAQAAAA==.Kelantir:BAAALgAECgYJCQABLgAECgkJDAASAAAAAA==.Keldorian:BAAALgADCgcJEAAAAA==.Kelishe:BAAALgAECgUJBQAAAA==.Kelliar:BAAALgAECgIJAQAAAA==.Kelorn:BAAALgADCgYJBgABLgAECggJGAAeAPARAA==.Kelysa:BAAALgADCgkJDgABLgAECggJQgAXACYdAA==.Kenzou:BAABLgAECn8ZAAMbAAgJvhlDMQA9AQAbAAYJCR1DMQA9AQANAAcJSQ/0OAAeAQAAAA==.',
Kh='Khadi:BAAALgAECgcJCwAAAA==.Khaeltaz:BAAALgAECgMJAwAAAA==.Khalandra:BAABLgAECn8eAAITAAkJaBtyKwAIAgATAAkJaBtyKwAIAgAAAA==.Khalel:BAAALgADCgEJAgAAAA==.Khaliq:BAABLgAECn8eAAMFAAkJVxV5FADtAQAFAAkJVxV5FADtAQAUAAQJLApxrwCtAAAAAA==.Khallani:BAABLgAECn8fAAIGAAcJgAlLlQBWAQAGAAcJgAlLlQBWAQAAAA==.Khamul:BAAALgAECgQJBgAAAA==.Khaos:BAAALgAECggJEwAAAA==.Khisto:BAABLgAECn80AAMWAAkJnRsqOQA0AgAWAAkJnRsqOQA0AgAhAAcJ3Rf5BACSAQAAAA==.Khroriggs:BAAALgAECgYJDQABLgAECgcJBwASAAAAAA==.Khrøna:BAAALgADCgIJAgABLgAECgcJBwASAAAAAA==.',
Ki='Kieran:BAAALgAECgUJCwAAAA==.Killerbiie:BAAALgADCgIJAgAAAA==.Killerdown:BAAALgADCgIJAgAAAA==.Kimashi:BAAALgAECgUJBQAAAA==.Kindie:BAAALgADCgcJCwABLgAECggJFAAUABEIAA==.Kisam:BAAALgAFFAEJAQAAAA==.Kissme:BAACLgAFFH8FAAMQAAMJ2AkNQgBuAAAQAAIJdwgNQgBuAAAPAAEJmwxTQgAmAAAuAAQKfx4AAxAACQmYEE0tAG8BABAACAneEU0tAG8BAA8ABAmICAhHAI0AAAAA.Kitamor:BAABLgAECn9aAAIQAAkJsRMQAwDPAQAQAAkJsRMQAwDPAQAAAA==.Kiya:BAAALgADCgcJHgAAAA==.',
Kl='Klorokina:BAAALgAECgYJBgAAAA==.',
Ko='Kooraqt:BAAALgAECgQJBAAAAA==.Koriakin:BAABLgAECn8vAAMaAAkJIR3QEADKAgAaAAkJIR3QEADKAgAiAAcJBxigGQDSAQAAAA==.Kosmo:BAAALgAECgcJCQAAAA==.Kotalkhan:BAAALgADCgkJEQAAAA==.',
Kr='Krosmu:BAAALgADCgcJBwAAAA==.Krov:BAAALgAECgEJAQAAAA==.Kryon:BAAALgAECgYJDgAAAA==.Kryzthor:BAAALgAECgYJCAAAAA==.Kräsus:BAABLgAECn9DAAIXAAkJAibtAABiAwAXAAkJAibtAABiAwAAAA==.Krønna:BAAALgAECgQJBAABLgAECgYJKQAjAEsIAA==.',
Ku='Kul:BAAALgAECgUJBgAAAA==.Kuthila:BAAALgADCgIJAgAAAA==.',
Ky='Kyzaru:BAAALgAECgIJAgAAAA==.',
['Kÿ']='Kÿdou:BAAALgAECgcJDgAAAA==.',
La='Ladrion:BAABLgAECn9WAAQkAAkJtR+HAQDfAgAkAAkJvB6HAQDfAgAdAAkJAxmFFABuAgAlAAkJ9RflBAA6AgAAAA==.Laetus:BAABLgAECn8ZAAImAAcJqxdpCAAXAQAmAAcJqxdpCAAXAQAAAA==.Lagosta:BAAALgAECgMJBgAAAA==.Laiany:BAABLgAECn9MAAIOAAkJJSISBABFAwAOAAkJJSISBABFAwAAAA==.Lani:BAAALgAECgEJAQAAAA==.',
Le='Legacia:BAAALgADCgYJBgAAAA==.Lekrom:BAAALgADCgYJBgAAAA==.Leodoros:BAAALgAECgYJDQAAAA==.Lequinhö:BAAALgAECgIJAgAAAA==.Leric:BAAALgADCgcJCgAAAA==.Lethmar:BAABLgAECn8eAAIYAAcJMxerXQCGAQAYAAcJMxerXQCGAQAAAA==.Levanah:BAABLgAFFH8IAAIaAAYJFAIrWwDuAAAaAAYJFAIrWwDuAAAAAA==.Leyana:BAAALgAECgUJBwAAAA==.',
Lh='Lhwei:BAAALgAECggJCwABLgAFFAQJEgAMANkbAA==.',
Li='Liandra:BAAALgAECgEJAQAAAA==.Licaon:BAAALgADCgYJDgAAAA==.Lichkiller:BAAALgAECgUJBQAAAA==.Lichkíng:BAAALgAECgYJBgAAAA==.Lightbreaker:BAABLgAECn8jAAILAAkJZAipiQBdAQALAAkJZAipiQBdAQAAAA==.Lihr:BAAALgADCgYJCQAAAA==.Lilianpotter:BAAALgAECgEJAQAAAA==.Lilithrix:BAAALgADCgIJAgAAAA==.Lillit:BAABLgAECn9LAAQgAAkJWhEkDgB6AQAYAAkJ7A8JUwCjAQAgAAgJJg4kDgB6AQAZAAIJvwYwPQA3AAAAAA==.Lindaah:BAABLgAECn9BAAMNAAgJhhzrAQD6AQANAAgJhhzrAQD6AQAMAAYJBwwCGACmAAAAAA==.Lindademon:BAAALgAECgUJDwAAAA==.Lindahealer:BAAALgAECgUJCgABLgAECgUJDwASAAAAAA==.Lislfox:BAABLgAECn9AAAIPAAkJbBrPCABfAgAPAAkJbBrPCABfAgAAAA==.Lithlad:BAAALgADCgIJAgAAAA==.',
Lk='Lkinho:BAAALgAECgMJBAAAAA==.',
Lm='Lmmds:BAAALgAECgUJCwAAAA==.',
Lo='Lockynha:BAAALgADCgEJAQAAAA==.Lonän:BAAALgAECgQJBAAAAA==.Loohynir:BAABLgAFFH8FAAICAAIJFQlzXABiAAACAAIJFQlzXABiAAAAAA==.Lotusbird:BAAALgADCgcJBwAAAA==.',
Lu='Lucario:BAAALgAECgEJAwAAAA==.Luccoa:BAAALgAECgkJEwABLgAECgkJQwAXAAImAA==.Luccyah:BAAALgADCgkJDwAAAA==.Lucifïr:BAAALgAECgEJAQAAAA==.Lucileia:BAAALgAECgQJBQAAAA==.Lukazgplay:BAAALgADCgIJAgAAAA==.Lutsul:BAAALgAECgEJAQAAAA==.',
Ly='Lylka:BAABLgAECn9HAAMKAAkJ0SWoAABlAwAKAAkJ0SWoAABlAwAVAAMJIiM5RAAwAQAAAA==.Lyrrena:BAAALgAECgMJBwAAAA==.',
Ma='Maanu:BAAALgAECgcJDwABLgAECggJQQANAIYcAA==.Maclaw:BAAALgADCgEJAQAAAA==.Macumbadora:BAAALgAECgQJCgAAAA==.Madfulock:BAABLgAECn8UAAIYAAcJiBh4XwCBAQAYAAcJiBh4XwCBAQAAAA==.Maeghann:BAAALgADCgMJAwAAAA==.Magalândia:BAAALgAECgIJAgAAAA==.Magraver:BAAALgAECgQJAwAAAA==.Mais:BAAALgAECgEJAQAAAA==.Makani:BAAALgAFFAEJAQAAAA==.Malewolyyc:BAACLgAFFH8IAAMOAAIJyR6KJACYAAAOAAIJyR6KJACYAAABAAEJZgfsPQA9AAAuAAQKfysAAw4ACQmZIXYMAJ8CAA4ACAk/I3YMAJ8CAAEABglGEYk6ACkBAAAA.Malhun:BAAALgADCgUJDgAAAA==.Malphan:BAAALgAECgcJBwAAAA==.Malyguz:BAACLgAFFH8UAAIWAAQJ1BKpXQAkAQAWAAQJ1BKpXQAkAQAuAAQKfxsAAhYABwldG+BgABkCABYABwldG+BgABkCAAAA.Malévolaa:BAAALgAECgYJBwAAAA==.Manipullador:BAAALgAECgIJAgAAAA==.Mapussauro:BAAALgAECgcJEQAAAA==.Maradi:BAAALgADCgIJAgAAAA==.Mariob:BAABLgAFFH8GAAIJAAIJEAWhOwBIAAAJAAIJEAWhOwBIAAAAAA==.Marjøly:BAAALgAECgEJAQAAAA==.Markson:BAAALgADCgEJAQAAAA==.Massafera:BAABLgAECn8fAAILAAkJMxP4WgC8AQALAAkJMxP4WgC8AQAAAA==.Mather:BAAALgAECgEJAQAAAA==.Mathfacbruxo:BAABLgAECn9NAAIYAAkJFhzVGQCJAgAYAAkJFhzVGQCJAgAAAA==.Mauritiuz:BAAALgAFFAEJAQAAAA==.Mayanyy:BAAALgAECgEJAQAAAA==.',
Mc='Mcq:BAAALgAECgEJAQAAAA==.',
Md='Mdrdark:BAACLgAFFH8OAAIGAAYJ2BOMaAAoAQAGAAYJ2BOMaAAoAQAuAAQKfy0AAwYACQmiGRkxADoCAAYACQmiGRkxADoCAAkAAwm/FVhIAGwAAAAA.',
Me='Medz:BAABLgAECn8jAAIWAAkJlRqKMQBTAgAWAAkJlRqKMQBTAgAAAA==.Meedea:BAAALgADCgUJBgAAAA==.Meetjack:BAAALgAECgEJAgAAAA==.Megalyan:BAAALgAECgEJAQAAAA==.Meiyin:BAAALgAECgcJEAAAAA==.Melania:BAAALgAECgEJAwAAAA==.Melissandra:BAAALgAFFAIJAwAAAA==.Mellkor:BAABLgAECn8qAAIFAAkJQhv+DABWAgAFAAkJQhv+DABWAgAAAA==.Melytah:BAAALgAECgEJAgAAAA==.Melzynhaa:BAAALgAECgEJBAABLgAECggJQQANAIYcAA==.Meraxxes:BAAALgADCgcJDAAAAA==.Merellien:BAAALgADCggJDgAAAA==.Mestreioda:BAAALgAECgQJBAAAAA==.Metamorful:BAABLgAECn8ZAAICAAkJBxL/SQB7AQACAAkJBxL/SQB7AQAAAA==.',
Mh='Mhorgann:BAAALgAECgUJBgAAAA==.',
Mi='Mijonakombi:BAABLgAECn8WAAILAAkJ/hpnLwBDAgALAAkJ/hpnLwBDAgAAAA==.Mikveh:BAAALgAECgYJCgAAAA==.Milim:BAABLgAECn9BAAQRAAkJ8hMlHgDmAQARAAkJ2RIlHgDmAQAnAAgJRQ2GDwATAQAoAAEJyQXsDAAeAAAAAA==.Milliidan:BAAALgADCgUJBQAAAA==.Mindrathys:BAAALgAECgEJAgAAAA==.Mithrius:BAABLgAECn8kAAILAAgJxxHvcACMAQALAAgJxxHvcACMAQAAAA==.',
Ml='Mls:BAAALgAECgUJBgAAAA==.',
Mo='Mogrus:BAAALgAECgQJBAAAAA==.Mohanna:BAAALgAECgkJEAAAAA==.Mohanninha:BAAALgAECgYJCwAAAA==.Mohotok:BAABLgAECn9VAAILAAkJSBncJwBkAgALAAkJSBncJwBkAgAAAA==.Moonøvesso:BAAALgAECgIJBQAAAA==.Moopp:BAAALgADCgcJCAAAAA==.Mortixxia:BAABLgAECn8oAAIZAAgJnx0kBABCAgAZAAgJnx0kBABCAgAAAA==.',
Mu='Muata:BAAALgAECgYJDwAAAA==.Muf:BAAALgAECgYJBgAAAA==.Mupar:BAAALgADCgIJAgAAAA==.Murano:BAABLgAECn8yAAMTAAkJxR75DQCQAgATAAkJxR75DQCQAgAHAAMJywp/VQCBAAAAAA==.Muzzo:BAAALgADCgYJCwABLgAECgcJEgASAAAAAA==.',
My='Myrmïdom:BAAALgAECgIJAgAAAA==.Myzoreh:BAAALgAECggJDAAAAA==.',
['Má']='Mágico:BAAALgAECgEJAwAAAA==.Máia:BAABLgAECn8UAAIZAAgJiAxrEQAvAQAZAAgJiAxrEQAvAQAAAA==.',
['Mä']='Mändosz:BAABLgAECn8ZAAMGAAkJMRKYbgCIAQAGAAgJahKYbgCIAQAIAAMJCRB0JACsAAAAAA==.',
['Mé']='Ménace:BAACLgAFFH8FAAIYAAMJPhfybQDmAAAYAAMJPhfybQDmAAAuAAQKfxUAAxgACQnmHfZaALcBABgACAnmHfZaALcBABkAAwlcDvJGAJoAAAAA.',
['Mÿ']='Mÿstyna:BAAALgAECgEJAQAAAA==.',
Na='Naallia:BAAALgAECgEJAwAAAA==.Nalathiel:BAABLgAECn8XAAIOAAgJsw3vMwA2AQAOAAgJsw3vMwA2AQAAAA==.Narancia:BAAALgAECgYJDQABLgAECgcJCwASAAAAAA==.Naryth:BAAALgAECgYJCAAAAA==.Nassur:BAAALgADCgEJAQAAAA==.Nattaliaa:BAAALgAECgEJAQAAAA==.Nazawill:BAAALgAECgQJBQAAAA==.Nazdru:BAAALgADCgMJAwABLgAECgkJXQADAFoiAA==.Nazzh:BAAALgAECgEJAQABLgAECgUJFAAUAKQdAA==.',
Ne='Necronx:BAAALgAECgEJAQAAAA==.Necronxd:BAAALgADCgEJAgAAAA==.Nefas:BAABLgAECn8jAAIZAAkJYxPnBwDSAQAZAAkJYxPnBwDSAQAAAA==.Nefazo:BAAALgAECgcJCgAAAA==.Nefilo:BAAALgADCgYJEAAAAA==.Nepthunus:BAABLgAECn9JAAIhAAkJuyGEAAAXAwAhAAkJuyGEAAAXAwAAAA==.Nermand:BAAALgAECgEJAQAAAA==.Neshula:BAAALgADCgMJAwAAAA==.Neuvosor:BAAALgAECgEJAQAAAA==.',
Ni='Nibelunga:BAAALgADCgYJBgAAAA==.Nijor:BAAALgADCgYJBgAAAA==.Nilsonssbnu:BAAALgAECgEJAQAAAA==.',
No='Nobelnaga:BAAALgAECgMJAwAAAA==.Noovaatoo:BAABLgAFFH8FAAIGAAMJaQN5WACYAAAGAAMJaQN5WACYAAAAAA==.Noria:BAAALgAECgEJAQAAAA==.Novatoo:BAAALgAFFAEJAQAAAA==.',
Ny='Nymira:BAAALgADCgIJAgABLgAFFAIJCgAGAJQQAA==.Nyobb:BAAALgADCgkJDAAAAA==.Nyxra:BAAALgADCgcJEAAAAA==.',
['Në']='Nëcros:BAABLgAECn8VAAMGAAcJzRwkBwCxAQAGAAcJzRwkBwCxAQAJAAUJ6A1hDgBeAAAAAA==.',
['Nö']='Nöirr:BAAALgAECgUJBwAAAA==.',
Oc='Ocelotte:BAAALgADCgEJAQAAAA==.',
Od='Odin:BAAALgAECgEJAQAAAA==.Odynsabio:BAAALgAECgEJAQAAAA==.',
Of='Ofanzitsu:BAAALgADCgQJBAAAAA==.',
Oi='Oioimiguel:BAAALgAECgUJBQAAAA==.',
Ol='Olhua:BAAALgAECgMJCQAAAA==.Oljedvlad:BAAALgADCgIJAgAAAA==.Oluss:BAAALgADCgUJBQABLgAFFAgJFwAaAFIYAA==.',
Om='Omnath:BAAALgADCgYJBgAAAA==.',
Or='Orillan:BAABLgAECn9YAAMFAAkJIBtlCwBwAgAFAAkJIBtlCwBwAgAUAAEJhAcY5gAsAAAAAA==.Ornsteinsnow:BAABLgAECn8ZAAIVAAkJvhSJHAAfAgAVAAkJvhSJHAAfAgAAAA==.Orob:BAABLgAECn8WAAICAAYJhQm+eQDKAAACAAYJhQm+eQDKAAAAAA==.Ororah:BAAALgAECgYJEAAAAA==.Orsonn:BAAALgAECgYJDAAAAA==.Orukam:BAABLgAECn8ZAAMCAAkJMBYvRACAAQACAAgJ7BQvRACAAQAQAAMJTgjAaAB9AAAAAA==.',
Os='Oszwald:BAAALgADCgEJAQAAAA==.',
['Oú']='Oúkürä:BAAALgAECgYJCgAAAA==.',
Pa='Paachamama:BAAALgADCgMJAwAAAA==.Padawani:BAAALgAECgMJAwAAAA==.Padgodeira:BAAALgAECgQJBAAAAA==.Padrealpha:BAAALgADCgcJCgAAAA==.Padrekelmøn:BAAALgAECgQJBAAAAA==.Palaha:BAAALgADCgEJAQABLgAFFAgJFwAaAFIYAA==.Palantír:BAAALgAECgEJAQAAAA==.Palatina:BAABLgAFFH8GAAILAAUJWhenQgAmAQALAAUJWhenQgAmAQAAAA==.Palazzy:BAAALgAECgEJAgAAAA==.Pandong:BAAALgAECggJEAAAAA==.Panena:BAAALgAECgIJAwAAAA==.Pangedrey:BAABLgAECn9UAAMNAAkJOCBjCADBAgANAAkJOCBjCADBAgAbAAcJJQRzTQDJAAAAAA==.Paracepatrol:BAAALgAECgQJAwAAAA==.Parcival:BAACLgAFFH8LAAIaAAMJoBokVwD4AAAaAAMJoBokVwD4AAAuAAQKfzsAAhoACQm8I1cBACADABoACQm8I1cBACADAAAA.Parký:BAAALgAECggJCQAAAA==.Pattalógika:BAAALgAECgEJAQAAAA==.Paullk:BAABLgAECn8gAAIQAAYJchQQPQAcAQAQAAYJchQQPQAcAQAAAA==.',
Pe='Pedrinho:BAAALgADCgYJBgABLgAFFAYJFwAUAD4eAA==.Penseur:BAAALgAECggJDgAAAA==.Penéllope:BAAALgAECgQJBwAAAA==.Persëphone:BAABLgAECn8VAAMOAAcJsRTjPQD6AAAOAAUJyRDjPQD6AAABAAYJCBKDXAClAAAAAA==.Peruchi:BAAALgAFFAIJAgAAAA==.',
Pg='Pgms:BAAALgAECgUJBQAAAA==.',
Ph='Phacozitos:BAAALgAECgEJAgAAAA==.Phaxe:BAAALgADCgIJAgAAAA==.Phoenicx:BAAALgADCgMJBgAAAA==.Phøënïx:BAAALgAECgcJDAAAAA==.',
Pi='Pipelinebr:BAAALgAECgUJBQAAAA==.Pitombinha:BAAALgAECgEJBAAAAA==.',
Pl='Plumalume:BAAALgADCgYJBgAAAA==.',
Po='Powalker:BAAALgAECgEJAgAAAA==.Powertell:BAAALgAECgYJCQABLgAECgkJHQANAMoSAA==.',
Pp='Pp:BAABLgAFFH8TAAQcAAUJngmTIgA7AQAcAAUJngmTIgA7AQABAAIJ4wYXMwB4AAAOAAEJ6wCPPQAlAAABLgAFFAgJJgARACcXAA==.',
Pr='Prometeus:BAAALgAECgYJDwAAAA==.Pryon:BAAALgAECgUJCwAAAA==.',
Pt='Ptollomeu:BAAALgAECgMJBQABLgAECgMJCQASAAAAAA==.',
['Pä']='Pändero:BAABLgAECn8WAAIMAAYJ8yIIGgBHAgAMAAYJ8yIIGgBHAgAAAA==.Pänqueca:BAAALgAECgEJAgAAAA==.',
['Pé']='Pénacova:BAAALgADCgEJAQAAAA==.',
['Pî']='Pîo:BAACLgAFFH8IAAIWAAMJVxE6gADWAAAWAAMJVxE6gADWAAAuAAQKfxcAAxYACAltGVZiALoBABYACAl5GFZiALoBACYABAnTGPAKACwBAAAA.',
Qu='Quejerok:BAAALgAECgYJEwAAAA==.',
Ra='Radiação:BAAALgAECgUJBgAAAA==.Radunz:BAABLgAECn9dAAIDAAkJWiL6AQAUAwADAAkJWiL6AQAUAwAAAA==.Ragnaros:BAABLgAFFH8FAAIVAAIJAxAxOwB4AAAVAAIJAxAxOwB4AAAAAA==.Ragnarssön:BAAALgAFFAEJAQAAAA==.Raineko:BAAALgADCgYJBgAAAA==.Raio:BAACLgAFFH8FAAIWAAIJlxNbogCKAAAWAAIJlxNbogCKAAAuAAQKfy8AAhYACQkEIfIdAKkCABYACQkEIfIdAKkCAAAA.Ralfwur:BAAALgAECgQJBwAAAA==.Ramsez:BAAALgAECgEJAQAAAA==.Rargsa:BAABLgAECn8iAAIIAAgJwwvCBQDOAAAIAAgJwwvCBQDOAAAAAA==.Rariel:BAAALgADCgIJAgAAAA==.Rasmon:BAABLgAECn8uAAIYAAkJRxTAQwDQAQAYAAkJRxTAQwDQAQAAAA==.Ravendreth:BAAALgADCgEJAQAAAA==.Raykarla:BAAALgAECgIJAwAAAA==.Raymain:BAACLgAFFH8GAAMNAAMJzh1PGwDxAAANAAMJzh1PGwDxAAAMAAEJkw6vZgAuAAAuAAQKfyQAAwwACQkSFqw9AHkBAAwACAmaFKw9AHkBAA0ABwkXFrc4AB8BAAAA.Raíka:BAAALgAECgYJEAAAAA==.',
Re='Reddnose:BAAALgAECgUJCQAAAA==.Reineke:BAAALgADCgEJAgAAAA==.Reinhold:BAABLgAECn8cAAMLAAcJ6RTBewB3AQALAAcJ6RTBewB3AQAVAAUJ2Qj8WwDGAAAAAA==.',
Rh='Rhuryk:BAAALgADCggJCAAAAA==.',
Ri='Ricktdai:BAAALgAECgEJAQAAAA==.Riesze:BAACLgAFFH8KAAIaAAMJoRGZXwDlAAAaAAMJoRGZXwDlAAAuAAQKfycAAhoACQl9GWshAGACABoACQl9GWshAGACAAAA.',
Ro='Roguinhu:BAAALgAFFAEJAQAAAA==.Ropaoo:BAABLgAECn8XAAIZAAYJEhbMDwBDAQAZAAYJEhbMDwBDAQAAAA==.',
Ru='Rua:BAAALgAECgQJBAAAAA==.Rurumo:BAAALgAECgcJBwAAAA==.Rusga:BAAALgADCggJCgAAAA==.Rustovick:BAAALgAECgMJBwAAAA==.',
Ry='Rytheas:BAAALgAECgQJBgAAAA==.',
['Rä']='Rämzä:BAAALgAECgYJEwAAAA==.',
['Rå']='Råy:BAAALgAECgQJCQAAAA==.',
['Rí']='Rízadinha:BAAALgAECgQJBAAAAA==.',
Sa='Saargeras:BAAALgADCgMJAwAAAA==.Saffír:BAABLgAECn8pAAILAAkJTRhBNgAoAgALAAkJTRhBNgAoAgAAAA==.Saiden:BAAALgADCgQJBAAAAA==.Saintkaue:BAAALgADCgUJCAAAAA==.Sairoz:BAAALgAECgEJBAAAAA==.Samalandraa:BAAALgADCgEJAQAAAA==.Sanahh:BAAALgAECgYJEwAAAA==.Sanateia:BAAALgADCgYJCwAAAA==.Santamadre:BAAALgADCgEJAQAAAA==.Sapekinhä:BAACLgAFFH8FAAIFAAIJwxj3IQCLAAAFAAIJwxj3IQCLAAAuAAQKfywABAUACQlJI70EAPoCAAUACQlJI70EAPoCAAQAAglSGOwjAH8AABQAAglFCR/5AFQAAAAA.Satanvitória:BAABLgAECn8uAAMHAAgJ7B5tDAAgAgATAAcJYRo0JgAoAgAHAAgJbh5tDAAgAgAAAA==.Sauroth:BAAALgADCgUJCQAAAA==.',
Sc='Scheiren:BAAALgAECgQJBgAAAA==.Scéal:BAAALgAECgMJAwAAAA==.',
Se='Senegos:BAAALgADCgcJBwAAAA==.Sereiaa:BAABLgAECn8rAAIaAAkJ9g0WZQB6AQAaAAkJ9g0WZQB6AQAAAA==.Sesiom:BAAALgAECgcJBgAAAA==.',
Sh='Shalltearr:BAAALgADCgEJAQAAAA==.Shamana:BAAALgAECgEJAQAAAA==.Shamate:BAAALgAFFAEJAQAAAA==.Shanoa:BAAALgAECgMJAwAAAA==.Sharae:BAAALgAECgQJCAAAAA==.Shariany:BAAALgADCgEJAQAAAA==.Sharpersong:BAAALgADCgcJBgAAAA==.Shedo:BAABLgAECn8VAAMHAAgJAxovFwCiAQAHAAcJuBkvFwCiAQATAAYJWg+VYgAoAQAAAA==.Sheevane:BAABLgAECn8eAAICAAkJmResJAAnAgACAAkJmResJAAnAgAAAA==.Shinzo:BAAALgADCgEJAQAAAA==.Shonja:BAAALgADCgcJDgAAAA==.Shula:BAAALgADCgcJDQAAAA==.Shumuk:BAAALgAECgEJAQAAAA==.Shytarra:BAAALgAECgUJBQABLgAECggJQQANAIYcAA==.Shÿnara:BAAALgAECgkJDwAAAA==.',
Si='Siclop:BAAALgADCgYJBgAAAA==.Silgris:BAAALgAECgEJAQABLgAECggJIAAVAPERAA==.Silmeria:BAABLgAECn8dAAIeAAkJdAZUXwA+AQAeAAkJdAZUXwA+AQAAAA==.Silverchain:BAAALgADCgcJCgAAAA==.Simplicity:BAAALgADCgIJAgAAAA==.Sinton:BAAALgAECgQJCAAAAA==.',
Sk='Skadryan:BAAALgAECgIJAgAAAA==.Skeletowman:BAAALgADCgUJBQAAAA==.Skineh:BAAALgAECgQJBwAAAA==.Skinme:BAABLgAECn8UAAIMAAYJKwQhjACDAAAMAAYJKwQhjACDAAAAAA==.',
Sm='Smylf:BAAALgAECgkJEAAAAA==.',
Sn='Snakedown:BAAALgAECgEJAgAAAA==.',
So='Sombrea:BAABLgAECn8VAAILAAcJyQfx8ADJAAALAAcJyQfx8ADJAAAAAA==.',
Sp='Spectrø:BAAALgAECgYJBgAAAA==.',
Sr='Srheal:BAAALgAECgQJBAAAAA==.Srsapo:BAAALgAECgMJBgAAAA==.',
Ss='Ssamara:BAAALgAECgYJBgAAAA==.',
St='Stampede:BAAALgADCgMJAwAAAA==.Starian:BAABLgAECn8gAAMCAAcJKRwtJQAjAgACAAcJKRwtJQAjAgAQAAEJywwTfwAzAAAAAA==.Starkz:BAAALgAECgEJAwAAAA==.Straider:BAAALgAECgEJAQAAAA==.Stëlla:BAABLgAECn8vAAIeAAgJ3RS6LwD2AQAeAAgJ3RS6LwD2AQAAAA==.',
Su='Suckmyhammer:BAABLgAECn8VAAIjAAcJdwuqBgDEAAAjAAcJdwuqBgDEAAAAAA==.Sunnara:BAACLgAFFH8XAAIUAAYJPh67EwBmAQAUAAYJPh67EwBmAQAuAAQKfyIAAhQACQnwITwKAPgCABQACQnwITwKAPgCAAAA.Superkx:BAAALgAECgQJBQAAAA==.Suzanomu:BAAALgADCgYJCwAAAA==.',
Sy='Sylran:BAAALgADCgQJBgAAAA==.Synk:BAAALgADCgQJBAAAAA==.Syofra:BAAALgAECgQJBQAAAA==.Syrelys:BAAALgADCgYJBgAAAA==.Syuon:BAACLgAFFH8SAAIMAAQJ2RvTFQALAQAMAAQJ2RvTFQALAQAuAAQKfzQAAwwACQkiIQYGAEYDAAwACQkiIQYGAEYDAA0AAgmQBqSKAEcAAAAA.',
['Së']='Sëkhmet:BAAALgAECgYJCwAAAA==.',
['Sï']='Sïmbä:BAABLgAECn8bAAMGAAkJjQ4DdQB6AQAGAAkJjQ4DdQB6AQAIAAEJkAShGQAoAAABLgAFFAEJAQASAAAAAA==.',
['Só']='Sósummono:BAAALgADCgYJBwAAAA==.',
['Sÿ']='Sÿkies:BAAALgADCgEJAQAAAA==.',
Ta='Talandar:BAABLgAECn8/AAIQAAkJshxhAQCJAgAQAAkJshxhAQCJAgAAAA==.Tankudo:BAABLgAECn8dAAIGAAgJKhOmhQBYAQAGAAgJKhOmhQBYAQAAAA==.Tannia:BAAALgADCgIJAgAAAA==.Tanthallas:BAAALgAECgEJAQAAAA==.Tavindapedra:BAAALgAECgYJCwAAAA==.',
Tc='Tchurusbango:BAAALgAECgEJAQAAAA==.Tchutchuco:BAAALgAECgIJAwAAAA==.',
Te='Tekzero:BAAALgAECgEJCAAAAA==.Tempestus:BAAALgADCgYJBgAAAA==.Tennebra:BAAALgAECgEJAQAAAA==.Teobaldo:BAAALgADCgYJCgAAAA==.Terron:BAABLgAECn8yAAMeAAkJEBYjIgBCAgAeAAkJEBYjIgBCAgAfAAIJnRc6dQCMAAAAAA==.',
Th='Thabitah:BAABLgAECn9XAAIBAAkJNyAhAQCtAgABAAkJNyAhAQCtAgAAAA==.Thaliath:BAAALgADCgQJBAAAAA==.Thallariel:BAAALgAECgQJBwAAAA==.Theteo:BAABLgAECn8ZAAILAAkJZQumggBqAQALAAkJZQumggBqAQAAAA==.Thiberios:BAAALgAECgUJDAAAAA==.Thirros:BAAALgADCgUJBQAAAA==.Thorres:BAAALgAECgMJBwAAAA==.Thotamon:BAAALgAECgQJCAAAAA==.Throin:BAAALgAECgMJAwAAAA==.Thràain:BAAALgAECgcJDgAAAA==.Thuki:BAAALgAECgEJAQAAAA==.Thunderblade:BAAALgAECgYJDgAAAA==.Thuska:BAAALgADCgYJBgAAAA==.Théus:BAAALgAECgMJAwABLgAFFAMJBQAYAD4XAA==.',
Ti='Tidim:BAAALgAECgEJAQAAAA==.Tiramisu:BAAALgAECgcJCwAAAA==.',
To='Torâo:BAABLgAECn8XAAIIAAcJ6ghxBgC7AAAIAAcJ6ghxBgC7AAAAAA==.Toucinho:BAAALgAECgYJDgAAAA==.',
Tr='Traydd:BAABLgAECn8iAAIDAAgJlBWoDgDKAQADAAgJlBWoDgDKAQAAAA==.Tredmor:BAAALgAECgEJAQAAAA==.Trollando:BAAALgAECgUJCAAAAA==.Trutona:BAAALgAECgEJAQAAAA==.',
Tu='Tuga:BAAALgADCgMJAwAAAA==.Turokk:BAABLgAECn8pAAIaAAgJfxTKEAA5AQAaAAgJfxTKEAA5AQAAAA==.',
Tw='Twilight:BAAALgADCgYJDQAAAA==.Twylluch:BAAALgADCgQJBgABLgAECgkJKAAVAOsXAA==.',
['Të']='Tëmys:BAAALgADCgEJAQAAAA==.',
Ul='Ulhim:BAAALgADCgcJEwAAAA==.',
Ur='Uriuri:BAAALgADCgYJBgABLgAECgkJXQADAFoiAA==.',
Us='Usfull:BAABLgAECn87AAMOAAkJHhJ0JQCZAQAOAAgJYhN0JQCZAQABAAgJFg0fLwBjAQAAAA==.',
Va='Vacavelha:BAAALgAECgEJAQAAAA==.Vahtorn:BAAALgAECgMJBgAAAA==.Valaerys:BAAALgAECgUJCgAAAA==.Valaniri:BAAALgADCgEJAQAAAA==.Vallkÿria:BAAALgAECgYJBwAAAA==.Vanheelsen:BAAALgAFFAIJBAAAAA==.Vanyathariel:BAAALgAECgEJAgAAAA==.Vareena:BAAALgADCggJCAABLgAECgkJQwAXAAImAA==.Vashiel:BAAALgADCgIJAgAAAA==.',
Ve='Vehuiáh:BAABLgAECn8eAAMVAAgJMB0ZHQAbAgAVAAgJMB0ZHQAbAgALAAEJRQQFwgEjAAAAAA==.Velen:BAABLgAECn8iAAIGAAkJHxX1BQDdAQAGAAkJHxX1BQDdAQAAAA==.Vellkor:BAAALgADCgYJBgAAAA==.Vellon:BAAALgADCgEJAQAAAA==.Venrique:BAAALgAECgQJBAABLgAECgYJEgASAAAAAA==.Venusa:BAAALgAECgYJBgAAAA==.Verno:BAAALgADCgcJCwAAAA==.Verzuk:BAABLgAECn8eAAIGAAgJPQqWjABMAQAGAAgJPQqWjABMAQAAAA==.',
Vi='Vidnands:BAAALgAECgEJAQAAAA==.Viinyy:BAAALgAECgMJAwAAAA==.Vilthor:BAAALgAECgUJBQAAAA==.Vintekilo:BAABLgAECn8YAAILAAkJzRaiYgC9AQALAAkJzRaiYgC9AQAAAA==.',
Vo='Voiddh:BAAALgAECgcJDAAAAA==.Vokeshar:BAAALgADCgUJBQAAAA==.Voltadupla:BAAALgAECgQJBQAAAA==.Voop:BAAALgADCgYJFAAAAA==.',
Vr='Vrenshrrgn:BAAALgAECgUJBAAAAA==.',
Vu='Vulcânico:BAAALgADCgUJCQAAAA==.',
Vy='Vygh:BAACLgAFFH8JAAIYAAMJmBXHdQDWAAAYAAMJmBXHdQDWAAAuAAQKfy4AAxgACQm5IVYOANoCABgACQm5IVYOANoCABkAAQkjDzpwADYAAAAA.Vyndrill:BAAALgAECgYJDgAAAA==.',
['Vä']='Välion:BAAALgADCgIJAgAAAA==.',
Wa='Wacom:BAAALgADCgUJBQAAAA==.Walkers:BAAALgAECgkJDgAAAA==.Warlaka:BAAALgAECgUJDAAAAA==.Warpiel:BAAALgADCgcJDAABLgAECgkJHgAcAC0OAA==.Wartigeer:BAAALgAECgEJAQAAAA==.Watchtower:BAAALgAECgQJBAAAAA==.',
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
Yi='Yingsu:BAABLgAECn8ZAAIbAAkJeCLRDgBNAgAbAAkJeCLRDgBNAgAAAA==.',
Yo='Yoshihime:BAAALgAECgIJAgABLgAECgkJHgACAJkXAA==.',
Yv='Yvin:BAAALgAECgMJBAAAAA==.',
Za='Zallmo:BAACLgAFFH8JAAITAAMJ4AlPIgCKAAATAAMJ4AlPIgCKAAAuAAQKfyMAAhMACAl/FaMkANABABMACAl/FaMkANABAAAA.Zaolron:BAAALgADCgYJBgAAAA==.Zarath:BAAALgAECgUJBgAAAA==.Zawarudo:BAAALgAECgYJCgAAAA==.',
Ze='Zedd:BAAALgAFFAIJAgAAAA==.Zenorclord:BAAALgADCgQJBgAAAA==.Zeytona:BAABLgAECn8jAAIbAAkJjAuLJgB6AQAbAAkJjAuLJgB6AQAAAA==.',
Zi='Ziracruz:BAAALgAECgQJCwAAAA==.',
Zu='Zulyn:BAAALgAECgIJAgAAAA==.',
['Zí']='Zíngara:BAAALgAECgEJAQAAAA==.',
['Ár']='Árÿä:BAABLgAECn9VAAIaAAkJURVkMQAWAgAaAAkJURVkMQAWAgAAAA==.',
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
