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

local lookup = {'Priest-Shadow','DeathKnight-Unholy','Druid-Restoration','DeathKnight-Frost','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Havoc','Priest-Holy','Druid-Guardian','Evoker-Augmentation','Unknown-Unknown','Druid-Balance','Druid-Feral','Paladin-Holy','Mage-Frost','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Warrior-Arms','DemonHunter-Vengeance','Warrior-Fury','Priest-Discipline','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','DemonHunter-Devourer','Monk-Brewmaster','Mage-Fire','Hunter-Survival','Shaman-Enhancement','Rogue-Outlaw','Rogue-Assassination','Mage-Arcane','DeathKnight-Blood','Evoker-Devastation',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abelao:BAAALgAECgcJEwAAAA==.',
Ad='Adelaide:BAAALgAECgIJAgABLgAFFAcJGgABALAaAA==.Adoramuss:BAAALgAECgYJCwAAAA==.Adrianoj:BAAALgAECgEJAQAAAA==.',
Ae='Aelon:BAAALgADCgUJBQAAAA==.Aelthor:BAAALgAECgQJCwAAAA==.Aemeath:BAAALgAECgkJCQAAAA==.',
Ah='Ahammes:BAAALgAECgQJBAABLgAECgcJHwACAIAJAA==.Ahmus:BAAALgAECgUJDAAAAA==.Ahrallu:BAAALgADCgEJAgAAAA==.',
Ai='Aioliavictus:BAAALgADCgIJAgAAAA==.',
Al='Alanie:BAAALgAECgUJCQABLgAECggJIwADABUeAA==.Aldranir:BAAALgADCgEJAQAAAA==.Alessaxd:BAABLgAECn8dAAMCAAkJ5hD+TAC4AQACAAkJQxD+TAC4AQAEAAMJRA+8HACaAAAAAA==.Alexa:BAAALgAECgQJBAAAAA==.Alfajhor:BAABLgAECn86AAMFAAgJFx9jDQDAAQAFAAYJoyJjDQDAAQAGAAgJZx38TgC8AQAAAA==.Alfajhòr:BAAALgAECgIJAgAAAA==.Alfajhôr:BAAALgAECgUJBwAAAA==.Alkarin:BAAALgAECgEJAwAAAA==.Allandriel:BAAALgAECgQJBAAAAA==.Alldarion:BAAALgAECgMJCQAAAA==.Allendra:BAAALgADCgcJCQAAAA==.Alleriane:BAABLgAECn85AAMHAAkJrh4BBwABAwAHAAkJrh4BBwABAwAIAAEJpwKRjQAYAAAAAA==.Allerios:BAAALgAECgUJCQAAAA==.Allone:BAABLgAECn8aAAIJAAcJZwyHLQBfAQAJAAcJZwyHLQBfAQAAAA==.Allyhra:BAAALgADCgQJBAAAAA==.Allëria:BAAALgADCgMJAwAAAA==.',
Am='Ametnys:BAAALgAECgQJCAAAAA==.Amonhar:BAAALgAECgEJAQABLgAECgkJMwAKAN8QAA==.Amyn:BAAALgADCgYJBwAAAA==.',
An='Anakata:BAABLgAECn8UAAMLAAYJ2BUiJADrAAALAAYJ2BUiJADrAAADAAIJ+wV4uwAzAAAAAA==.Anakinini:BAABLgAECn8bAAIMAAgJhAjaOAAiAQAMAAgJhAjaOAAiAQABLgAECgYJBgANAAAAAA==.Analia:BAABLgAECn8jAAQDAAgJFR5/HgBLAgADAAcJVR1/HgBLAgALAAgJnQjAKADMAAAOAAMJQByTTwCeAAAAAA==.Andaliz:BAACLgAFFH8MAAIGAAMJkiXIIwBKAQAGAAMJkiXIIwBKAQAuAAQKfzMAAgYACQkLJpABAHcDAAYACQkLJpABAHcDAAAA.Andorith:BAAALgAECgEJAQAAAA==.Anelie:BAAALgAECgQJDQABLgAECggJIwADABUeAA==.Ansalon:BAAALgADCgYJBwAAAA==.Antonellaes:BAAALgAECgMJAwABLgAECgcJDgANAAAAAA==.Anturio:BAAALgAECgQJBwAAAA==.',
Ao='Aoiisuu:BAAALgADCgYJCAAAAA==.',
Ap='Apodrecido:BAAALgAECgYJBgAAAA==.',
Ar='Arajakata:BAAALgAECgEJAgAAAA==.Arctorius:BAAALgAECgYJEQAAAA==.Arethiel:BAAALgADCgYJBgAAAA==.Arlandriah:BAAALgADCgYJCQABLgAECgYJGAAGABAYAA==.Artronis:BAABLgAECn8kAAMLAAgJYhUFEQCeAQALAAgJYhUFEQCeAQAPAAEJPRQjOQA/AAAAAA==.Artånis:BAAALgAECgcJDAAAAA==.Aruthuro:BAAALgAECgYJDwAAAA==.',
As='Ashbörn:BAAALgADCgcJDgAAAA==.Astel:BAAALgAECgcJBwAAAA==.',
At='Atriuz:BAABLgAECn8bAAIQAAYJahouLwDGAQAQAAYJahouLwDGAQAAAA==.Ats:BAAALgAECgIJAgAAAA==.',
Ay='Aykho:BAABLgAECn8nAAIRAAgJRRaSVQC/AQARAAgJRRaSVQC/AQAAAA==.',
Az='Azurion:BAAALgAECgYJCgAAAA==.',
['Aÿ']='Aÿ:BAAALgAECgMJAwAAAA==.',
Ba='Baguh:BAAALgADCggJCAAAAA==.Bagunça:BAAALgADCgYJBgAAAA==.Bakuugou:BAAALgAECgMJCAAAAA==.Bambur:BAAALgADCgMJAwAAAA==.Barbabruto:BAABLgAECn8jAAISAAgJ6hvtCwAHAgASAAgJ6hvtCwAHAgAAAA==.Basilisco:BAAALgAECgEJAQAAAA==.',
Be='Belleg:BAAALgAECgEJAgAAAA==.',
Bf='Bf:BAAALgADCgEJAQAAAA==.',
Bi='Biafalcão:BAAALgAECgEJAQAAAA==.Bijanca:BAAALgAECgYJBgAAAA==.Birthdäy:BAAALgADCgEJAQAAAA==.Bisponegro:BAAALgAECgQJBwABLgABCgcJFQANAAAAAA==.Biønic:BAAALgAECgMJCQAAAA==.',
Bl='Blackline:BAABLgAECn8fAAICAAgJPRKWXACOAQACAAgJPRKWXACOAQAAAA==.',
Bo='Boipretim:BAAALgAECgUJDQAAAA==.Bontorius:BAAALgADCgEJAgAAAA==.Bordello:BAAALgADCgUJBQAAAA==.',
Br='Bradio:BAAALgADCggJCAAAAA==.Brahman:BAAALgAECgEJAQAAAA==.Bratloko:BAAALgAECgUJBQAAAA==.Bromos:BAAALgAECgQJCAAAAA==.Brutalhoof:BAAALgAECgQJBAAAAA==.Brönsted:BAAALgADCgMJAwAAAA==.',
Bu='Bubbalo:BAAALgADCgUJBQAAAA==.Bullsman:BAAALgADCgQJBAAAAA==.Buzzumaaky:BAABLgAECn8YAAIRAAgJTxepiQC/AQARAAgJTxepiQC/AQAAAA==.',
By='Byakura:BAAALgADCggJCwAAAA==.',
['Bü']='Büdweiser:BAAALgAECgMJBQAAAA==.',
Ca='Cabernet:BAAALgAECgUJBwAAAA==.Cabeçaquente:BAAALgAECgcJCQAAAA==.Calhistra:BAABLgAECn8nAAMTAAgJQxnfPwDFAQATAAgJQxnfPwDFAQAUAAIJRQokVQBvAAAAAA==.Calteryeker:BAAALgAECgYJDQAAAA==.Camillas:BAAALgAECggJDwAAAA==.Caosenvy:BAAALgAECgEJAQAAAA==.Caralh:BAAALgAECgEJAgAAAA==.Caroll:BAAALgAECgIJAgAAAA==.Castaldi:BAAALgAECgEJAQABLgAECgcJCAANAAAAAA==.Cathe:BAABLgAECn8VAAIVAAYJIRznXgBcAQAVAAYJIRznXgBcAQAAAA==.',
Ce='Cernûnnos:BAAALgAFFAIJBAAAAA==.',
Ch='Champdude:BAABLgAECn82AAIIAAkJZiP8AgAdAwAIAAkJZiP8AgAdAwAAAA==.Chankowkwai:BAAALgAECgYJCQAAAA==.Chanë:BAAALgADCgIJAwAAAA==.Chewi:BAAALgAECgEJAgAAAA==.',
Ci='Citra:BAAALgAECgMJBwAAAA==.',
Co='Coconolose:BAAALgAECgIJBgAAAA==.Cod:BAAALgAECgIJAwAAAA==.Codecks:BAAALgADCgYJBgAAAA==.Coldbringer:BAAALgAECgEJAQAAAA==.Coldhearths:BAAALgAECgUJBgAAAA==.Couro:BAAALgAECgYJCAAAAA==.Cowçadora:BAAALgADCgIJAQAAAA==.',
Cr='Criminøsa:BAAALgAECgcJCAAAAA==.Cristcalad:BAABLgAECn8wAAMWAAgJ2BaWDgDWAQAWAAgJ2BaWDgDWAQASAAEJYQULTwAfAAAAAA==.Cryomanta:BAAALgAECgUJBQAAAA==.',
Cu='Cunhaovirado:BAAALgAECgQJBwABLgAFFAUJDgAIANUZAA==.Cunhazinha:BAAALgAECgQJBAAAAA==.Cupyncha:BAAALgADCgUJBQAAAA==.Cutia:BAAALgADCgEJAQAAAA==.Cutiesissy:BAAALgAECgQJCAABLgAECgcJGgAGAEoQAA==.',
['Cø']='Cøøkye:BAAALgAECgQJBQAAAA==.',
Da='Daellus:BAAALgADCgUJBQAAAA==.Daemi:BAAALgAECgIJBAAAAA==.Daibodan:BAAALgAECgEJBAAAAA==.Dalaty:BAAALgAECgUJBQAAAA==.Daniilos:BAAALgAFFAEJAQAAAA==.Darklara:BAABLgAECn8lAAIXAAkJBRnpBgDxAQAXAAkJBRnpBgDxAQAAAA==.Darkove:BAABLgAECn8uAAIRAAkJjBK8QwD0AQARAAkJjBK8QwD0AQAAAA==.Darrow:BAACLgAFFH8JAAMCAAQJRRi3OgBOAQACAAQJ5BW3OgBOAQAEAAMJrxcmDADrAAAuAAQKfy4AAwIACQm0I8ANAN8CAAIACQnZIsANAN8CAAQACAn8Ig0CAMECAAAA.Dartibeccoso:BAAALgADCgcJBwAAAA==.',
De='Deany:BAAALgAECgEJAQAAAA==.Deathinhu:BAABLgAECn9HAAIRAAkJDB8aEQDbAgARAAkJDB8aEQDbAgAAAA==.Deathnacht:BAAALgAECgQJBwAAAA==.Delset:BAAALgADCgIJAgAAAA==.Demojoca:BAAALgAECgEJAQABLgAECgcJDgANAAAAAA==.Dentepodre:BAAALgADCgEJAQAAAA==.Dervus:BAAALgADCgcJBwAAAA==.Dethroned:BAAALgAECgUJCAAAAA==.Devrath:BAAALgAECgEJAQAAAA==.Devyogi:BAAALgADCgcJCAAAAA==.',
Di='Diefs:BAAALgAECgEJAQAAAA==.Dimeros:BAABLgAECn8jAAIOAAkJ/wmkJQBwAQAOAAkJ/wmkJQBwAQAAAA==.Dito:BAAALgADCgEJAQAAAA==.Divano:BAACLgAFFH8FAAIBAAIJGRUtIQCqAAABAAIJGRUtIQCqAAAuAAQKfyMAAgEACAm6H9QKAIECAAEACAm6H9QKAIECAAAA.',
Dk='Dkats:BAAALgAECgEJAgAAAA==.',
Dn='Dng:BAAALgAECgcJCAAAAA==.',
Do='Dogowner:BAAALgAECggJEQAAAA==.Donora:BAABLgAECn8pAAQGAAkJFRM1QADnAQAGAAkJFRM1QADnAQAQAAEJfwOogAAsAAAFAAEJKAZQTQAVAAAAAA==.',
Dr='Drackmontana:BAABLgAECn8lAAMYAAgJaA4gNgDQAQAYAAgJEg4gNgDQAQASAAIJEhVBPQBjAAAAAA==.Drafael:BAAALgADCggJDgABLgAECgkJOgAPANwgAA==.Dragoniron:BAAALgADCgEJAQAAAA==.Dragony:BAAALgAECgEJBAAAAA==.Dragunass:BAABLgAECn8sAAMYAAgJoxyAFwAOAgAYAAgJFxyAFwAOAgASAAcJaBeeFQB0AQAAAA==.Dragøndeath:BAAALgADCgEJAgAAAA==.Drakars:BAAALgADCgUJBAAAAA==.Dranarus:BAAALgADCgQJBAAAAA==.Druidblack:BAAALgAECgIJAgAAAA==.Drunkler:BAAALgAECgYJBgAAAA==.Dryter:BAABLgAECn8VAAIIAAcJEA9QKwCEAQAIAAcJEA9QKwCEAQAAAA==.Drákon:BAAALgADCgUJBgAAAA==.',
Du='Dubhe:BAAALgAECgUJDAAAAA==.',
Dy='Dysttopia:BAAALgADCgcJCAAAAA==.',
El='Eldryrin:BAAALgAECgEJAQAAAA==.Elendile:BAAALgAECgEJAQAAAA==.Elinius:BAABLgAECn8sAAMOAAkJzSCCBgDPAgAOAAkJzSCCBgDPAgADAAIJUwyCvwAuAAAAAA==.Elistraee:BAAALgAECgEJAQAAAA==.Ellandria:BAAALgAECgMJAwAAAA==.Ellonara:BAAALgAECgEJAQAAAA==.Eloren:BAAALgAECgYJCwABLgAECggJIAAQAPERAA==.Eluuria:BAAALgAFFAEJAQAAAA==.Elyzia:BAAALgAECgEJAQAAAA==.',
En='Endorena:BAAALgADCgEJAQAAAA==.',
Ep='Ephesus:BAAALgADCgIJAgAAAA==.',
Er='Erikssen:BAAALgADCgYJBgAAAA==.Ernest:BAABLgAECn8xAAIDAAkJLxrXEACqAgADAAkJLxrXEACqAgAAAA==.Erynneus:BAAALgADCgMJAwAAAA==.',
Es='Estagiario:BAAALgAECgMJBAABLgAECgkJKgAJAP4hAA==.',
Ev='Evetts:BAAALgADCgEJAQAAAA==.Evilbarba:BAAALgAECgIJAgAAAA==.',
Ex='Exort:BAAALgAECgYJDwAAAA==.Expressão:BAAALgADCgYJCwAAAA==.',
Fa='Faeldar:BAABLgAECn83AAIZAAkJ2xL6EQApAgAZAAkJ2xL6EQApAgAAAA==.Faldark:BAAALgAECgIJAgAAAA==.Fandrall:BAAALgAECgUJCAAAAA==.Faris:BAABLgAFFH8FAAIaAAIJ2wtVJwCYAAAaAAIJ2wtVJwCYAAAAAA==.Faver:BAAALgAECgQJBQAAAA==.Faölin:BAABLgAECn8ZAAIaAAcJdBj8HQB7AQAaAAcJdBj8HQB7AQAAAA==.',
Fe='Feenigan:BAAALgAECgEJAQABLgAECgQJBAANAAAAAA==.Feeniä:BAAALgAECgQJBAAAAA==.Ferael:BAABLgAECn8yAAIGAAkJPiJBCwDxAgAGAAkJPiJBCwDxAgAAAA==.',
Fi='Fil:BAAALgAECgEJAQAAAA==.Firstomega:BAAALgADCgMJAwAAAA==.',
Fl='Flavors:BAABLgAECn8jAAMYAAkJ3SMFBQD3AgAYAAkJ3SMFBQD3AgAWAAQJIR4CFABmAQAAAA==.Florbela:BAAALgAECgUJCAAAAA==.Flämbë:BAAALgADCgEJAQAAAA==.',
Fo='Fogue:BAAALgAECgUJAwAAAA==.Foxthamy:BAABLgAECn8jAAIHAAcJKRLFLwBrAQAHAAcJKRLFLwBrAQAAAA==.',
Fr='Frachlitzz:BAABLgAECn85AAIRAAkJchR2NgAiAgARAAkJchR2NgAiAgAAAA==.Fradem:BAAALgAECgYJCAAAAA==.Freccianera:BAAALgADCgEJAQAAAA==.Fredericc:BAABLgAECn8aAAMbAAkJCg+iOgCSAQAbAAgJwQ2iOgCSAQAcAAcJ2gVYWQDfAAAAAA==.Fredinho:BAAALgAECgEJAQAAAA==.Freecs:BAAALgAECgEJAQABLgAECgcJCAANAAAAAA==.Freyá:BAABLgAECn8hAAIGAAkJcCGDDQDfAgAGAAkJcCGDDQDfAgAAAA==.Frs:BAAALgAECgEJAgAAAA==.',
Ga='Galhuda:BAAALgADCgYJBgAAAA==.Galyan:BAAALgADCgEJAQAAAA==.Gandwelf:BAAALgADCgkJCQAAAA==.Gazieri:BAABLgAECn8gAAMQAAgJ8RFkRQBiAQAQAAgJ8RFkRQBiAQAGAAQJCw/z2gDWAAAAAA==.',
Ge='Geisty:BAAALgAECgMJAwABLgAECgcJHwACAIAJAA==.',
Gh='Ghalladriel:BAAALgADCgEJAwAAAA==.Ghruka:BAAALgAECgQJBAAAAA==.',
Gi='Giafar:BAAALgAECgEJAQABLgAECgYJBgANAAAAAA==.',
Gn='Gnomari:BAABLgAECn8UAAITAAgJJAFJ8QBYAAATAAgJJAFJ8QBYAAAAAA==.',
Go='Goratrix:BAAALgAECgUJBQABLgAECgcJHwACAIAJAA==.Gordanado:BAAALgAECgEJAgAAAA==.Gordruida:BAAALgAECgEJAQAAAA==.Govers:BAAALgADCgMJAwABLgAECgMJBAANAAAAAA==.',
Gr='Grandecoisa:BAAALgAECgEJAQAAAA==.Greyvor:BAAALgADCgEJAQAAAA==.Grumax:BAABLgAECn8UAAIGAAgJyQ/FdACRAQAGAAgJyQ/FdACRAQAAAA==.Grössa:BAABLgAECn8YAAMQAAcJIwiGWwAOAQAQAAcJIwiGWwAOAQAGAAMJCQS8RQE8AAABLgAECgkJFwATAJ8IAA==.',
Gu='Guitianki:BAAALgAECgEJAQAAAA==.Gulek:BAAALgAECgMJAwAAAA==.Gussg:BAABLgAECn8XAAQTAAkJnwgzVQCGAQATAAkJnwgzVQCGAQAdAAEJzwhoMwArAAAUAAIJGQROOwAgAAAAAA==.Gustavonz:BAAALgADCgcJBwAAAA==.',
['Gö']='Göhan:BAAALgADCgUJBQABLgAECgYJEwANAAAAAA==.',
['Gø']='Gøvers:BAAALgAECgMJBAAAAA==.',
Ha='Handyman:BAAALgADCgYJBgAAAA==.',
He='Hefestion:BAAALgAECgEJAgAAAA==.Helsingdarck:BAAALgADCgIJAgAAAA==.',
Hi='Hildegyth:BAABLgAECn8fAAMIAAgJWBE1MQBhAQAIAAcJWRE1MQBhAQAHAAUJZxEXRAACAQAAAA==.',
Hj='Hjalmar:BAAALgADCgcJCQAAAA==.',
Ho='Hodtiva:BAABLgAECn8tAAMBAAgJdBCFJAB9AQABAAgJdBCFJAB9AQAKAAUJDA7GQgC4AAAAAA==.Homerz:BAAALgADCgEJAQAAAA==.Hotmojo:BAAALgAECgcJDgABLgAFFAQJCgAcADMcAA==.',
Hu='Hunfox:BAACLgAFFH8PAAIVAAMJahtpCwAHAQAVAAMJahtpCwAHAQAuAAQKf0EAAhUACQmuI04FAB8DABUACQmuI04FAB8DAAAA.',
['Hä']='Härkness:BAAALgAECgEJAgAAAA==.',
['Hü']='Hüskar:BAABLgAECn8fAAMYAAkJ/AttJwCaAQAYAAkJuQttJwCaAQAWAAEJCg+hYAAwAAAAAA==.',
Ic='Icechips:BAAALgADCgUJBQAAAA==.Ichigoz:BAABLgAECn8aAAIRAAkJdwYvdAB0AQARAAkJdwYvdAB0AQAAAA==.',
Ih='Ihntwuaed:BAAALgADCgYJCQAAAA==.',
Ik='Ikoo:BAABLgAECn83AAIZAAkJ/RuaBwDYAgAZAAkJ/RuaBwDYAgAAAA==.',
Il='Illaril:BAACLgAFFH8WAAIXAAQJHhihAgA0AQAXAAQJHhihAgA0AQAuAAQKf18AAhcACQlFIWQCANcCABcACQlFIWQCANcCAAAA.',
In='Indarion:BAAALgADCgYJEQAAAA==.Ingratt:BAAALgAECgEJAgAAAA==.Invisiblelol:BAAALgAECgIJAgAAAA==.',
Ir='Irmãodouther:BAAALgAECgcJBwAAAA==.',
Is='Isebby:BAAALgADCgMJAwAAAA==.Ishtarie:BAAALgAECgQJBQABLgAECgkJHgADAJkXAA==.',
It='Itzzdan:BAAALgADCgMJAwAAAA==.',
Iv='Ivina:BAABLgAECn8UAAMTAAgJThbwkQA1AQATAAcJThbwkQA1AQAdAAIJqRe4HACNAAAAAA==.',
Iz='Izaar:BAAALgAECgQJDgAAAA==.',
Ja='Janaìna:BAAALgAECgMJAwAAAA==.Jangeoffry:BAAALgADCgEJAQAAAA==.',
Jh='Jhonatinha:BAABLgAECn8VAAMGAAcJBxm1ugDtAAAGAAYJaxm1ugDtAAAQAAQJng69dgCfAAAAAA==.',
Ji='Jigsaww:BAAALgAECgMJBQAAAA==.',
Jo='Joaquim:BAAALgAECgIJAgAAAA==.Jogaveiopl:BAAALgADCgIJAgAAAA==.Johnlobo:BAAALgAECgEJAQAAAA==.Joventino:BAAALgADCgQJBQAAAA==.',
Ju='Jucah:BAABLgAECn8ZAAIcAAkJZAvzLwBSAQAcAAkJZAvzLwBSAQAAAA==.Julabolseiro:BAAALgADCgkJCQAAAA==.Jullianxd:BAAALgADCgIJAgABLgAECgkJFgAeAOwPAA==.',
Ka='Kaallew:BAABLgAECn8ZAAIFAAkJuRecEwBkAQAFAAkJuRecEwBkAQAAAA==.Kaezar:BAAALgADCgEJAQAAAA==.Kainer:BAAALgAECgQJBQAAAA==.Kalazshar:BAABLgAECn8ZAAILAAgJTBJoGABNAQALAAgJTBJoGABNAQAAAA==.Kalelzinho:BAAALgADCgYJBgAAAA==.Kaluss:BAAALgAECgYJCwAAAA==.Kanalet:BAAALgAECgYJCAAAAA==.Kantaa:BAAALgAECgQJCgAAAA==.Kanturu:BAAALgAECgQJBAAAAA==.Karonn:BAABLgAECn8UAAIGAAYJ/A3mlABTAQAGAAYJ/A3mlABTAQAAAA==.Kavartu:BAAALgAECgYJBgAAAA==.Kaymon:BAAALgAECgEJAQAAAA==.',
Ke='Keillor:BAABLgAECn8bAAIbAAYJKxR5RwBdAQAbAAYJKxR5RwBdAQAAAA==.Kelantir:BAAALgAECgYJCQABLgAECgkJDAANAAAAAA==.Keldorian:BAAALgADCgcJEAAAAA==.Kelishe:BAAALgAECgUJBQAAAA==.Kelliar:BAAALgAECgIJAQAAAA==.Kelorn:BAAALgADCgYJBgAAAA==.Kelysa:BAAALgADCgkJDgABLgAECggJPAASACYdAA==.Kenzou:BAABLgAECn8XAAMfAAcJ0hj5KgBBAQAfAAUJexz5KgBBAQAIAAcJSQ9WLQAsAQAAAA==.',
Kh='Khadi:BAAALgAECgcJCQAAAA==.Khaeltaz:BAAALgAECgMJAwAAAA==.Khalandra:BAABLgAECn8eAAIYAAkJaBtyKwAIAgAYAAkJaBtyKwAIAgAAAA==.Khalel:BAAALgADCgEJAgAAAA==.Khaliq:BAABLgAECn8eAAMJAAkJVxVODwD8AQAJAAkJVxVODwD8AQAeAAQJLApxrwCtAAAAAA==.Khallani:BAABLgAECn8fAAICAAcJgAlLlQBWAQACAAcJgAlLlQBWAQAAAA==.Khamul:BAAALgAECgQJBgAAAA==.Khaos:BAAALgAECggJEwAAAA==.Khisto:BAABLgAECn80AAMRAAkJnRu2LQBEAgARAAkJnRu2LQBEAgAgAAcJ3ReJAwCsAQAAAA==.Khroriggs:BAAALgAECgYJDQABLgAECgcJBwANAAAAAA==.',
Ki='Killerbiie:BAAALgADCgIJAgAAAA==.Killerdown:BAAALgADCgIJAgAAAA==.Kimashi:BAAALgAECgUJBQAAAA==.Kindie:BAAALgADCgcJCwABLgAECggJFAAeABEIAA==.Kissme:BAABLgAECn8cAAMOAAkJmBBRJQByAQAOAAgJ3hFRJQByAQALAAIJAgczRgBPAAAAAA==.Kitamor:BAABLgAECn81AAIOAAkJLwpCKQBXAQAOAAkJLwpCKQBXAQAAAA==.Kiya:BAAALgADCgcJHgAAAA==.',
Kl='Klorokina:BAAALgAECgYJBgAAAA==.',
Ko='Koriakin:BAABLgAECn8ZAAMVAAgJHhiWJgAbAgAVAAgJHhiWJgAbAgAhAAUJohHXMAD+AAAAAA==.Kosmo:BAAALgAECgQJBAAAAA==.Kotalkhan:BAAALgADCgkJEQAAAA==.',
Kr='Krov:BAAALgAECgEJAQAAAA==.Kryon:BAAALgAECgYJDgAAAA==.Kryzthor:BAAALgAECgYJCAAAAA==.Kräsus:BAABLgAECn8xAAISAAkJgSUQAQBNAwASAAkJgSUQAQBNAwAAAA==.Krønna:BAAALgAECgQJBAABLgAECgYJKQAiAEsIAA==.',
Ku='Kul:BAAALgAECgUJBgAAAA==.Kuroelf:BAAALgAECgMJAwAAAA==.Kuthila:BAAALgADCgIJAgAAAA==.',
Ky='Kyzaru:BAAALgAECgEJAQAAAA==.',
['Kÿ']='Kÿdou:BAAALgAECgcJDgAAAA==.',
La='Ladrion:BAABLgAECn9GAAQjAAkJXx4RAgCOAgAjAAkJeRoRAgCOAgAaAAkJAxmFFABuAgAkAAkJ9Re5AwBIAgAAAA==.Laetus:BAABLgAECn8YAAIlAAUJ9xiWCgAzAQAlAAUJ9xiWCgAzAQAAAA==.Lagosta:BAAALgAECgMJBgAAAA==.Laiany:BAABLgAECn88AAIKAAkJ5yH/AgBMAwAKAAkJ5yH/AgBMAwAAAA==.Lani:BAAALgAECgEJAQAAAA==.',
Le='Legacia:BAAALgADCgYJBgAAAA==.Lekrom:BAAALgADCgYJBgAAAA==.Lequinhö:BAAALgAECgIJAgAAAA==.Leric:BAAALgADCgcJCgAAAA==.Lethmar:BAABLgAECn8aAAITAAcJMxduTwCWAQATAAcJMxduTwCWAQAAAA==.Leyana:BAAALgAECgUJBgAAAA==.',
Lh='Lhwei:BAAALgAECgIJAgABLgAECgkJJQAHAD8fAA==.',
Li='Liandra:BAAALgAECgEJAQAAAA==.Licaon:BAAALgADCgYJCwAAAA==.Lichkiller:BAAALgAECgUJBQAAAA==.Lightbreaker:BAABLgAECn8jAAIGAAkJZAgHawB5AQAGAAkJZAgHawB5AQAAAA==.Lihr:BAAALgADCgYJCQAAAA==.Lilianpotter:BAAALgAECgEJAQAAAA==.Lilithrix:BAAALgADCgIJAgAAAA==.Lillit:BAABLgAECn8wAAQdAAgJlg3BCwBpAQAdAAgJfQvBCwBpAQATAAgJ+wupYABpAQAUAAIJvwZ5MgA7AAAAAA==.Lindaah:BAABLgAECn8nAAMIAAgJqxf2FwDKAQAIAAgJqxf2FwDKAQAHAAYJvQT8XQCfAAAAAA==.Lindademon:BAAALgAECgUJCAAAAA==.Lindahealer:BAAALgAECgEJAgABLgAECgUJCAANAAAAAA==.Lislfox:BAABLgAECn80AAILAAkJCRixCAAoAgALAAkJCRixCAAoAgAAAA==.Lithlad:BAAALgADCgIJAgAAAA==.',
Lk='Lkinho:BAAALgAECgMJBAAAAA==.',
Lm='Lmmds:BAAALgADCgYJFQAAAA==.',
Lo='Lockynha:BAAALgADCgEJAQAAAA==.Loohynir:BAAALgAFFAIJAgAAAA==.Lotusbird:BAAALgADCgcJBwAAAA==.',
Lu='Luccoa:BAAALgAECgkJCQABLgAECgkJMQASAIElAA==.Luccyah:BAAALgADCgkJDAAAAA==.Lucifïr:BAAALgAECgEJAQAAAA==.Lucileia:BAAALgAECgEJAgAAAA==.Lukazgplay:BAAALgADCgIJAgAAAA==.Lutsul:BAAALgAECgEJAQAAAA==.',
Ly='Lylka:BAABLgAECn8xAAIFAAkJliTSAABEAwAFAAkJliTSAABEAwAAAA==.Lyrrena:BAAALgAECgMJAwAAAA==.',
Ma='Maanu:BAAALgADCgMJAwABLgAECggJJwAIAKsXAA==.Macumbadora:BAAALgAECgQJCgAAAA==.Madfulock:BAAALgAECgcJEgAAAA==.Maeghann:BAAALgADCgMJAwAAAA==.Magalândia:BAAALgADCgEJAQAAAA==.Magraver:BAAALgAECgMJAwAAAA==.Mais:BAAALgADCgMJBQAAAA==.Malewolyyc:BAACLgAFFH8GAAIKAAIJyR4FHACrAAAKAAIJyR4FHACrAAAuAAQKfygAAwoACAk/Ix0JALQCAAoACAk/Ix0JALQCAAEABQnWEp07APsAAAEuAAUUAwkDAA0AAAAA.Malhun:BAAALgADCgUJDgAAAA==.Malphan:BAAALgAECgcJBwAAAA==.Malyguz:BAACLgAFFH8QAAIRAAQJBhB3TwAqAQARAAQJBhB3TwAqAQAuAAQKfxsAAhEABwldG+BgABkCABEABwldG+BgABkCAAAA.Malévolatity:BAAALgAECgUJCQAAAA==.Manipullador:BAAALgAECgIJAgAAAA==.Mapussauro:BAAALgAECgcJEQAAAA==.Maradi:BAAALgADCgIJAgAAAA==.Mariob:BAAALgAFFAEJAQAAAA==.Marjøly:BAAALgAECgEJAQAAAA==.Markson:BAAALgADCgEJAQAAAA==.Massafera:BAABLgAECn8fAAIGAAkJMxN8QwDdAQAGAAkJMxN8QwDdAQAAAA==.Mather:BAAALgAECgEJAQAAAA==.Mathfacbruxo:BAABLgAECn84AAITAAkJThpuGgBrAgATAAkJThpuGgBrAgAAAA==.Mauritiuz:BAAALgAFFAEJAQAAAA==.Mayanyy:BAAALgAECgEJAQAAAA==.',
Mc='Mcq:BAAALgADCgYJCwAAAA==.',
Md='Mdrdark:BAACLgAFFH8LAAICAAQJfxPMTAAxAQACAAQJfxPMTAAxAQAuAAQKfy0AAwIACQmiGTwmAEcCAAIACQmiGTwmAEcCACYAAwm/FQk8AHAAAAAA.',
Me='Medz:BAABLgAECn8jAAIRAAkJlRoqJgBnAgARAAkJlRoqJgBnAgAAAA==.Meedea:BAAALgADCgUJBgAAAA==.Meetjack:BAAALgADCgIJAgAAAA==.Meiyin:BAAALgAECgEJAQAAAA==.Melania:BAAALgAECgEJAgAAAA==.Melissandra:BAAALgAFFAEJAQAAAA==.Mellkor:BAABLgAECn8nAAIJAAgJxhswDgANAgAJAAgJxhswDgANAgAAAA==.Melytah:BAAALgAECgEJAgAAAA==.Melzynhaa:BAAALgAECgEJAQABLgAECggJJwAIAKsXAA==.Meraxxes:BAAALgADCgcJDAAAAA==.Merellien:BAAALgADCggJDgAAAA==.Metamorful:BAABLgAECn8ZAAIDAAkJBxL/SQB7AQADAAkJBxL/SQB7AQAAAA==.',
Mh='Mhorgann:BAAALgAECgUJBgAAAA==.',
Mi='Mijonakombi:BAABLgAECn8WAAIGAAkJ/hoEIwBZAgAGAAkJ/hoEIwBZAgAAAA==.Mikveh:BAAALgAECgUJBgAAAA==.Milim:BAABLgAECn83AAMMAAkJ8hNkGQDrAQAMAAkJ2RJkGQDrAQAnAAgJRQ1fDgAGAQAAAA==.Milliidan:BAAALgADCgUJBQAAAA==.Mindrathys:BAAALgAECgEJAQAAAA==.Mithrius:BAABLgAECn8iAAIGAAgJxxHVVwClAQAGAAgJxxHVVwClAQAAAA==.',
Ml='Mls:BAAALgADCgYJCwAAAA==.',
Mo='Mogrus:BAAALgADCgMJAwAAAA==.Mohanna:BAAALgAECggJDgAAAA==.Mohanninha:BAAALgAECgYJCwAAAA==.Mohotok:BAABLgAECn84AAIGAAkJThgyKwAyAgAGAAkJThgyKwAyAgAAAA==.Moonøvesso:BAAALgAECgEJAgAAAA==.Moopp:BAAALgADCgIJAgAAAA==.Mortixxia:BAABLgAECn8gAAIUAAcJuRv0BQDXAQAUAAcJuRv0BQDXAQAAAA==.',
Mu='Muata:BAAALgAECgYJDwAAAA==.Muf:BAAALgAECgYJBgAAAA==.Mupar:BAAALgADCgIJAgAAAA==.Murano:BAABLgAECn8yAAMYAAkJxR6PCQCpAgAYAAkJxR6PCQCpAgAWAAMJywqyQQCKAAAAAA==.Muzzo:BAAALgADCgYJCwABLgAECgYJDgANAAAAAA==.',
My='Myrmïdom:BAAALgAECgIJAgAAAA==.Myzoreh:BAAALgAECgcJCAAAAA==.',
['Má']='Mágico:BAAALgAECgEJAwAAAA==.Máia:BAABLgAECn8UAAIUAAgJiAwrDQA+AQAUAAgJiAwrDQA+AQAAAA==.',
['Mä']='Mändosz:BAABLgAECn8ZAAMCAAkJMRJDWQCXAQACAAgJahJDWQCXAQAEAAMJCRDMGQC3AAAAAA==.',
['Mé']='Ménace:BAABLgAECn8VAAMTAAkJ5h32WgC3AQATAAgJ5h32WgC3AQAUAAMJXA7yRgCaAAAAAA==.',
Na='Nalathiel:BAAALgAECgcJEAAAAA==.Narancia:BAAALgAECgYJCAABLgAECgcJCAANAAAAAA==.Naryth:BAAALgAECgYJCAAAAA==.Nassur:BAAALgADCgEJAQAAAA==.Nattaliaa:BAAALgAECgEJAQAAAA==.Nazawill:BAAALgADCgEJAQAAAA==.Nazdru:BAAALgADCgMJAwABLgAECgkJOgAPANwgAA==.Nazzh:BAAALgAECgEJAQAAAA==.',
Ne='Necronx:BAAALgAECgEJAQAAAA==.Necronxd:BAAALgADCgEJAgAAAA==.Nefas:BAABLgAECn8jAAIUAAkJYxOaBQDkAQAUAAkJYxOaBQDkAQAAAA==.Nefazo:BAAALgAECgcJCgAAAA==.Nefilo:BAAALgADCgYJEAAAAA==.Nepthunus:BAABLgAECn8vAAIgAAkJRRqHAQBYAgAgAAkJRRqHAQBYAgAAAA==.Nermand:BAAALgAECgEJAQAAAA==.Neshula:BAAALgADCgMJAwAAAA==.Neuvosor:BAAALgAECgEJAQAAAA==.',
Ni='Nibelunga:BAAALgADCgYJBgAAAA==.Nijor:BAAALgADCgYJBgAAAA==.',
No='Nobelnaga:BAAALgAECgMJAwAAAA==.',
Ny='Nyxra:BAAALgADCgcJEAAAAA==.',
['Nö']='Nöirr:BAAALgADCgcJCwAAAA==.',
Oc='Ocelotte:BAAALgADCgEJAQAAAA==.',
Od='Odynsabio:BAAALgAECgEJAQAAAA==.',
Oi='Oioimiguel:BAAALgADCgUJBQAAAA==.',
Ol='Olhua:BAAALgAECgIJAwAAAA==.Oljedvlad:BAAALgADCgEJAQAAAA==.Oluss:BAAALgADCgUJBQABLgAFFAMJDwAVAGobAA==.',
Om='Omnath:BAAALgADCgYJBgAAAA==.',
Or='Orillan:BAABLgAECn85AAMJAAkJ+BjbCwAyAgAJAAkJ+BjbCwAyAgAeAAEJhAcY5gAsAAAAAA==.Ornsteinsnow:BAABLgAECn8ZAAIQAAkJvhQVFwApAgAQAAkJvhQVFwApAgAAAA==.Orob:BAAALgAECgEJAQAAAA==.Ororah:BAAALgAECgYJCwAAAA==.Orukam:BAABLgAECn8ZAAMDAAkJMBbROwCCAQADAAgJ7BTROwCCAQAOAAMJTgjnVgCDAAAAAA==.',
Os='Oszwald:BAAALgADCgEJAQAAAA==.',
['Oú']='Oúkürä:BAAALgAECgYJCgAAAA==.',
Pa='Padawani:BAAALgAECgIJAgAAAA==.Padgodeira:BAAALgAECgQJBAAAAA==.Padrealpha:BAAALgADCgcJCgAAAA==.Padrekelmøn:BAAALgAECgQJBAAAAA==.Palaha:BAAALgADCgEJAQABLgAFFAMJDwAVAGobAA==.Palatina:BAAALgAFFAQJBAAAAA==.Palazzy:BAAALgAECgEJAgAAAA==.Pandong:BAAALgAECgMJAwAAAA==.Panena:BAAALgAECgIJAwAAAA==.Pangedrey:BAABLgAECn9GAAIIAAkJZR8bBwC3AgAIAAkJZR8bBwC3AgAAAA==.Paracepatrol:BAAALgAECgQJAwAAAA==.Parcival:BAACLgAFFH8IAAIVAAMJkBkLRwDaAAAVAAMJkBkLRwDaAAAuAAQKfykAAhUACQl+IisFACEDABUACQl+IisFACEDAAAA.Parký:BAAALgAECgYJBgAAAA==.Pattalógika:BAAALgAECgEJAQAAAA==.Paullk:BAABLgAECn8gAAIOAAYJchQfMwAcAQAOAAYJchQfMwAcAQAAAA==.',
Pe='Pedrinho:BAAALgADCgYJBgABLgAFFAQJDQAeAJMfAA==.Penéllope:BAAALgAECgQJBQAAAA==.Persëphone:BAABLgAECn8VAAMKAAcJsRSzNQAFAQAKAAUJyRCzNQAFAQABAAYJCBKYSwCyAAAAAA==.Peruchi:BAAALgAECgQJBAAAAA==.',
Pg='Pgms:BAAALgADCgYJCgAAAA==.',
Ph='Phaxe:BAAALgADCgIJAgAAAA==.Phoenicx:BAAALgADCgMJBgAAAA==.Phøënïx:BAAALgAECgQJBQAAAA==.',
Pi='Pipelinebr:BAAALgAECgUJBQAAAA==.Pitombinha:BAAALgAECgEJAQAAAA==.',
Pp='Pp:BAABLgAFFH8JAAQBAAMJggx9MQA0AAABAAEJPAF9MQA0AAAKAAEJ6wBNLwAsAAAZAAEJ7grwPQAmAAAAAA==.',
Pr='Prometeus:BAAALgAECgYJDwAAAA==.Pryon:BAAALgAECgUJCwAAAA==.',
['Pä']='Pändero:BAAALgAFFAEJAQAAAA==.Pänqueca:BAAALgAECgEJAgAAAA==.',
['Pé']='Pénacova:BAAALgADCgEJAQAAAA==.',
['Pî']='Pîo:BAACLgAFFH8FAAIRAAMJAg9maADlAAARAAMJAg9maADlAAAuAAQKfxcAAxEACAltGUBRAMsBABEACAl5GEBRAMsBACUABAnTGPAKACwBAAAA.',
Qu='Quejerok:BAAALgAECgYJEwAAAA==.',
Ra='Radunz:BAABLgAECn86AAIPAAkJ3CA0AgDsAgAPAAkJ3CA0AgDsAgAAAA==.Raineko:BAAALgADCgYJBgAAAA==.Raio:BAACLgAFFH8FAAIRAAIJlxN9gACfAAARAAIJlxN9gACfAAAuAAQKfy8AAhEACQkEISIWALkCABEACQkEISIWALkCAAAA.Ralfwur:BAAALgAECgQJBwAAAA==.Rargsa:BAABLgAECn8UAAIEAAgJQwVYFADzAAAEAAgJQwVYFADzAAAAAA==.Rariel:BAAALgADCgMJAgAAAA==.Rasmon:BAABLgAECn8uAAITAAkJRxRZNgDnAQATAAkJRxRZNgDnAQAAAA==.Ravendreth:BAAALgADCgEJAQAAAA==.Raykarla:BAAALgAECgIJAwAAAA==.Raymain:BAACLgAFFH8GAAMIAAMJzh3OEgAFAQAIAAMJzh3OEgAFAQAHAAEJkw5zPwA+AAAuAAQKfyQAAwcACQkSFsotAHYBAAcACAmaFMotAHYBAAgABwkXFnYuACYBAAAA.Raíka:BAAALgAECgUJBQAAAA==.',
Re='Reddnose:BAAALgAECgUJCQAAAA==.Reinhold:BAAALgAECgUJCwAAAA==.',
Rh='Rhuryk:BAAALgADCggJCAAAAA==.',
Ri='Ricktdai:BAAALgAECgEJAQAAAA==.Riesze:BAABLgAECn8mAAIVAAkJfRm0FgB2AgAVAAkJfRm0FgB2AgAAAA==.',
Ro='Roguinhu:BAAALgAECgEJAQAAAA==.Ropaoo:BAAALgAECgMJCQAAAA==.',
Ru='Rua:BAAALgAECgQJBAAAAA==.Rusga:BAAALgADCggJCAAAAA==.Rustovick:BAAALgAECgMJBQAAAA==.',
Ry='Rytheas:BAAALgAECgQJBgAAAA==.',
['Rä']='Rämzä:BAAALgAECgYJEwAAAA==.',
['Rå']='Råy:BAAALgAECgQJBwAAAA==.',
['Rí']='Rízadinha:BAAALgAECgQJBAAAAA==.',
Sa='Saargeras:BAAALgADCgMJAwAAAA==.Saffír:BAABLgAECn8kAAIGAAgJThg4PwDqAQAGAAgJThg4PwDqAQAAAA==.Saiden:BAAALgADCgQJBAAAAA==.Saintkaue:BAAALgADCgUJBQAAAA==.Samalandraa:BAAALgADCgEJAQAAAA==.Sanahh:BAAALgAECgYJCAAAAA==.Sanateia:BAAALgADCgYJCwAAAA==.Santamadre:BAAALgADCgEJAQAAAA==.Sapekinhä:BAABLgAECn8qAAQJAAkJ/iGnAwDwAgAJAAkJ/iGnAwDwAgAXAAIJUhiNHQCCAAAeAAIJRQnN0wBVAAAAAA==.Saphirah:BAAALgAECgEJAQAAAA==.Satanvitória:BAABLgAECn8uAAMWAAgJ7B5UCQAwAgAWAAgJbh5UCQAwAgAYAAcJYRo0JgAoAgAAAA==.',
Sc='Scheiren:BAAALgAECgMJAwAAAA==.',
Se='Senegos:BAAALgADCgcJBwAAAA==.Sereiaa:BAABLgAECn8eAAIVAAYJAg5MfwARAQAVAAYJAg5MfwARAQAAAA==.Sesiom:BAAALgAECgcJBgAAAA==.',
Sh='Shalltearr:BAAALgADCgEJAQAAAA==.Shamate:BAAALgAECgMJBAAAAA==.Shanoa:BAAALgAECgMJAwAAAA==.Sharpersong:BAAALgADCgcJBgAAAA==.Shedo:BAABLgAECn8VAAMWAAgJAxokEgCsAQAWAAcJuBkkEgCsAQAYAAYJWg+VYgAoAQAAAA==.Sheevane:BAABLgAECn8eAAIDAAkJmRdMHwAoAgADAAkJmRdMHwAoAgAAAA==.Shinzo:BAAALgADCgEJAQAAAA==.Shonja:BAAALgADCgcJDgAAAA==.Shula:BAAALgADCgcJDQAAAA==.Shÿnara:BAAALgAECgkJDwAAAA==.',
Si='Siclop:BAAALgADCgYJBgAAAA==.Silgris:BAAALgAECgEJAQABLgAECggJIAAQAPERAA==.Silmeria:BAABLgAECn8UAAIbAAgJAgVTYQAAAQAbAAgJAgVTYQAAAQAAAA==.Silverchain:BAAALgADCgcJCgAAAA==.Sinton:BAAALgAECgQJCAAAAA==.',
Sk='Skadryan:BAAALgAECgEJAQAAAA==.Skeletowman:BAAALgADCgEJAQAAAA==.Skineh:BAAALgAECgMJAwAAAA==.Skinme:BAABLgAECn8UAAIHAAYJKwRqZACIAAAHAAYJKwRqZACIAAAAAA==.',
Sm='Smylf:BAAALgAECgkJEAAAAA==.',
Sn='Snakedown:BAAALgAECgEJAgAAAA==.',
So='Sombrea:BAAALgAECgUJCgAAAA==.',
Sp='Spectrø:BAAALgAECgYJBgAAAA==.',
Sr='Srheal:BAAALgAECgQJBAAAAA==.Srsapo:BAAALgAECgMJBgAAAA==.',
St='Stampede:BAAALgADCgMJAwAAAA==.Starian:BAABLgAECn8gAAMDAAcJKRymHwAmAgADAAcJKRymHwAmAgAOAAEJywwTfwAzAAAAAA==.Stëlla:BAABLgAECn8qAAIbAAgJfBOoKwDcAQAbAAgJfBOoKwDcAQAAAA==.',
Su='Suckmyhammer:BAAALgADCgUJCAAAAA==.Sunnara:BAACLgAFFH8NAAIeAAQJkx+DHwBrAQAeAAQJkx+DHwBrAQAuAAQKfyIAAh4ACQnwIVQHAAMDAB4ACQnwIVQHAAMDAAAA.Superkx:BAAALgAECgQJBQAAAA==.Suzanomu:BAAALgADCgYJCwAAAA==.',
Sy='Sylran:BAAALgADCgQJBgAAAA==.Synk:BAAALgADCgQJBAAAAA==.Syofra:BAAALgAECgQJBQAAAA==.Syrelys:BAAALgADCgYJBgAAAA==.Syuon:BAABLgAECn8lAAIHAAkJPx9vBgAOAwAHAAkJPx9vBgAOAwAAAA==.',
['Së']='Sëkhmet:BAAALgAECgYJCwAAAA==.',
['Sï']='Sïmbä:BAABLgAECn8bAAMCAAkJjQ5KXwCHAQACAAkJjQ5KXwCHAQAEAAEJkAShGQAoAAAAAA==.',
['Sÿ']='Sÿkies:BAAALgADCgEJAQAAAA==.',
Ta='Talandar:BAABLgAECn82AAIOAAkJERkdDQBgAgAOAAkJERkdDQBgAgAAAA==.Tankudo:BAABLgAECn8ZAAICAAYJBhaFiQAsAQACAAYJBhaFiQAsAQAAAA==.Tanthallas:BAAALgAECgEJAQAAAA==.Tavindapedra:BAAALgAECgYJCwAAAA==.',
Tc='Tchutchuco:BAAALgAECgIJAwAAAA==.',
Te='Tekzero:BAAALgAECgEJBwAAAA==.Tempestus:BAAALgADCgYJBgAAAA==.Tennebra:BAAALgADCgYJCAAAAA==.Teobaldo:BAAALgADCgYJCgAAAA==.Terron:BAABLgAECn8rAAIbAAgJhRVfJQD/AQAbAAgJhRVfJQD/AQAAAA==.',
Th='Thabitah:BAABLgAECn83AAIBAAkJYB2OCAClAgABAAkJYB2OCAClAgAAAA==.Thaliath:BAAALgADCgQJBAAAAA==.Thallariel:BAAALgAECgQJBgAAAA==.Theteo:BAABLgAECn8ZAAIGAAkJZQvDZACGAQAGAAkJZQvDZACGAQAAAA==.Thiberios:BAAALgAECgUJDAAAAA==.Thirros:BAAALgADCgUJBQAAAA==.Thorres:BAAALgAECgIJAgAAAA==.Thotamon:BAAALgAECgQJCAAAAA==.Throin:BAAALgAECgMJAwAAAA==.Thràain:BAAALgAECgcJDgAAAA==.Thuki:BAAALgADCgYJDAAAAA==.Thunderblade:BAAALgAECgYJDgAAAA==.Théus:BAAALgAECgMJAwABLgAECgkJFQATAOYdAA==.',
Ti='Tiramisu:BAAALgAECgcJCAAAAA==.',
To='Torâo:BAAALgAECgMJAwAAAA==.Toucinho:BAAALgAECgYJDgAAAA==.',
Tr='Traydd:BAABLgAECn8ZAAIPAAcJBg3LFgAmAQAPAAcJBg3LFgAmAQAAAA==.Trollando:BAAALgAECgUJCAAAAA==.',
Tu='Tuga:BAAALgADCgMJAwAAAA==.Turokk:BAABLgAECn8bAAIVAAgJTA/MTgCIAQAVAAgJTA/MTgCIAQAAAA==.',
Tw='Twilight:BAAALgADCgYJDQAAAA==.Twylluch:BAAALgADCgQJBgABLgAECgkJKAAQAOsXAA==.',
Ul='Ulhim:BAAALgADCgcJEwAAAA==.',
Ur='Uriuri:BAAALgADCgYJBgABLgAECgkJOgAPANwgAA==.',
Us='Usfull:BAABLgAECn8zAAMKAAkJ3xB6IgCMAQAKAAgJ/BF6IgCMAQABAAgJawvwJwBmAQAAAA==.',
Va='Vacavelha:BAAALgAECgEJAQAAAA==.Vahtorn:BAAALgAECgMJBgAAAA==.Valaerys:BAAALgAECgUJCgAAAA==.Valaniri:BAAALgADCgEJAQAAAA==.Vanyathariel:BAAALgADCgYJAwAAAA==.Vareena:BAAALgADCggJCAABLgAECgkJMQASAIElAA==.Vashiel:BAAALgADCgIJAgAAAA==.',
Ve='Vehuiáh:BAABLgAECn8eAAMQAAgJMB3wFwAhAgAQAAgJMB3wFwAhAgAGAAEJRQRNeAEoAAAAAA==.Velen:BAABLgAECn8aAAICAAcJshCSegBIAQACAAcJshCSegBIAQAAAA==.Vellkor:BAAALgADCgYJBgAAAA==.Vellon:BAAALgADCgEJAQAAAA==.Venrique:BAAALgAECgMJAwABLgAECgYJDAANAAAAAA==.Venusa:BAAALgADCgMJBAAAAA==.Verno:BAAALgADCgcJCwAAAA==.Verzuk:BAABLgAECn8aAAICAAgJoQizeQBKAQACAAgJoQizeQBKAQAAAA==.',
Vi='Vidnands:BAAALgAECgEJAQAAAA==.Viinyy:BAAALgAECgMJAwAAAA==.Vilthor:BAAALgAECgUJBQAAAA==.Vintekilo:BAABLgAECn8YAAIGAAkJzRaiYgC9AQAGAAkJzRaiYgC9AQAAAA==.',
Vo='Voiddh:BAAALgAECgcJDAAAAA==.Vokeshar:BAAALgADCgUJBQAAAA==.Voltadupla:BAAALgAECgQJBQAAAA==.Voop:BAAALgADCgYJFAAAAA==.',
Vr='Vrenshrrgn:BAAALgADCgYJBgAAAA==.',
Vy='Vygh:BAACLgAFFH8JAAITAAMJmBVhWQDlAAATAAMJmBVhWQDlAAAuAAQKfysAAxMACQm5ID8MANcCABMACQm5ID8MANcCABQAAQkjDzpwADYAAAAA.Vyndrill:BAAALgAECgYJDgAAAA==.',
['Vä']='Välion:BAAALgADCgIJAgAAAA==.',
Wa='Wacom:BAAALgADCgUJBQAAAA==.Walkers:BAAALgAECgUJBQAAAA==.Warlaka:BAAALgAECgIJAgAAAA==.Warpiel:BAAALgADCgcJDAABLgAECgkJHgAZAC0OAA==.Watchtower:BAAALgAECgQJBAAAAA==.',
Wh='Wheez:BAAALgAECgQJBAABLgAECgkJNAARAJ0bAA==.',
Wi='Williem:BAAALgADCgYJEwAAAA==.',
Wo='Worthy:BAAALgADCgQJBAAAAA==.',
Xa='Xafado:BAAALgAECgEJAQAAAA==.Xamalandrö:BAAALgAECgQJCwAAAA==.',
Xe='Xeal:BAAALgADCgEJAQAAAA==.Xehagus:BAAALgADCgcJCgAAAA==.',
Xi='Xiblaublum:BAAALgADCgMJAwAAAA==.Xinhagoo:BAAALgAECgMJAwAAAA==.Xiquimiro:BAAALgADCgQJBAAAAA==.',
Xx='Xximperadorx:BAAALgADCgIJAgAAAA==.',
Ya='Yasuoh:BAAALgAECgQJCAAAAA==.',
Ye='Yewner:BAAALgADCgYJBQAAAA==.',
Yi='Yingsu:BAABLgAECn8ZAAIfAAkJeCLwCwBXAgAfAAkJeCLwCwBXAgAAAA==.',
Yo='Yoshihime:BAAALgAECgIJAgABLgAECgkJHgADAJkXAA==.',
Yv='Yvin:BAAALgAECgMJBAAAAA==.',
Za='Zallmo:BAAALgAFFAEJAQAAAA==.Zarath:BAAALgAECgUJBgAAAA==.Zawarudo:BAAALgAECgQJCAAAAA==.',
Ze='Zedd:BAAALgAFFAIJAgAAAA==.Zenorclord:BAAALgADCgQJBgAAAA==.Zeytona:BAABLgAECn8jAAIfAAkJjAvVIACCAQAfAAkJjAvVIACCAQAAAA==.',
Zi='Ziracruz:BAAALgAECgQJCwAAAA==.',
['Zí']='Zíngara:BAAALgAECgEJAQAAAA==.',
['Ár']='Árÿä:BAABLgAECn86AAIVAAkJoBMILgD7AQAVAAkJoBMILgD7AQAAAA==.',
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
