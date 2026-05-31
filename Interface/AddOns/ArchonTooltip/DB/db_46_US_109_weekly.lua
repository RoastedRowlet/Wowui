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

local lookup = {'Priest-Shadow','DeathKnight-Unholy','Druid-Restoration','DeathKnight-Frost','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Havoc','Priest-Holy','Druid-Guardian','Evoker-Augmentation','Unknown-Unknown','Druid-Balance','Druid-Feral','Paladin-Holy','Mage-Frost','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Monk-Brewmaster','Warrior-Arms','DemonHunter-Vengeance','Priest-Discipline','Warrior-Fury','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','DemonHunter-Devourer','Mage-Fire','Hunter-Survival','Shaman-Enhancement','Rogue-Outlaw','Rogue-Assassination','Mage-Arcane','DeathKnight-Blood','Evoker-Devastation',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abelao:BAAALgAECgcJEwAAAA==.',
Ad='Adelaide:BAAALgAECgIJAgABLgAFFAcJGgABALAaAA==.Adoramuss:BAAALgAECgYJCwAAAA==.Adrianoj:BAAALgAECgEJAQAAAA==.',
Ae='Aelon:BAAALgADCgUJBQAAAA==.Aelthor:BAAALgAECgQJCwAAAA==.Aemeath:BAAALgAECgkJCwAAAA==.',
Ah='Ahammes:BAAALgAECgQJBAABLgAECgcJHwACAIAJAA==.Ahmus:BAAALgAECgUJDAAAAA==.Ahrallu:BAAALgADCgEJAgAAAA==.',
Ai='Aioliavictus:BAAALgADCgIJAgAAAA==.',
Al='Alanie:BAAALgAECgUJCQABLgAECggJIwADABUeAA==.Aldranir:BAAALgADCgEJAQAAAA==.Alessaxd:BAABLgAECn8kAAMCAAkJdBLNTwDBAQACAAkJaxDNTwDBAQAEAAcJyg8jEQAyAQAAAA==.Alexa:BAAALgAECgQJBAAAAA==.Alfajhor:BAABLgAECn86AAMFAAgJFx+1DgC9AQAFAAYJoyK1DgC9AQAGAAgJZx3fVQCwAQAAAA==.Alfajhòr:BAAALgAECgIJAgAAAA==.Alfajhôr:BAAALgAECgUJBwAAAA==.Alkarin:BAAALgAECgEJAwAAAA==.Allandriel:BAAALgAECgUJBQAAAA==.Alldarion:BAAALgAECgMJCQAAAA==.Allendra:BAAALgADCgcJCQAAAA==.Alleriane:BAACLgAFFH8GAAIHAAIJOhdPNwCIAAAHAAIJOhdPNwCIAAAuAAQKfzwAAwcACQlEHyoHABEDAAcACQlEHyoHABEDAAgAAQmnApGNABgAAAAA.Allerios:BAAALgAECgUJCQAAAA==.Allone:BAABLgAECn8aAAIJAAcJZwyHLQBfAQAJAAcJZwyHLQBfAQAAAA==.Allyhra:BAAALgADCgQJBAAAAA==.Allëria:BAAALgADCgMJAwAAAA==.',
Am='Ametnys:BAAALgAECgQJCAAAAA==.Amonhar:BAAALgAECgQJBQABLgAECgkJMwAKAN8QAA==.Amyn:BAAALgADCgYJBwAAAA==.',
An='Anakata:BAABLgAECn8ZAAMLAAYJ3RVgJQABAQALAAYJ3RVgJQABAQADAAIJ+wWFxAAzAAAAAA==.Anakinini:BAABLgAECn8bAAIMAAgJhAjHQAAFAQAMAAgJhAjHQAAFAQABLgAECgYJBgANAAAAAA==.Analia:BAABLgAECn8jAAQDAAgJFR5/HgBLAgADAAcJVR1/HgBLAgALAAgJnQjYLgDKAAAOAAMJQBx0VQCeAAAAAA==.Andaliz:BAACLgAFFH8PAAIGAAMJwCYbIwBYAQAGAAMJwCYbIwBYAQAuAAQKfzYAAgYACQkLJhMCAGwDAAYACQkLJhMCAGwDAAEuAAUUBQkGAAYAWhcA.Andorith:BAAALgAECgEJAQAAAA==.Anelie:BAAALgAECgQJDQABLgAECggJIwADABUeAA==.Annhe:BAAALgAECgEJAQAAAA==.Ansalon:BAAALgADCgYJBwAAAA==.Anthorus:BAAALgAECgIJAgAAAA==.Antonellaes:BAAALgAECgQJCQABLgAECgcJDgANAAAAAA==.Anturio:BAAALgAECgQJBwAAAA==.',
Ao='Aoiisuu:BAAALgADCgYJCAAAAA==.',
Ap='Apodrecido:BAAALgAECgYJBgAAAA==.',
Ar='Arajakata:BAAALgAECgEJAgAAAA==.Arctorius:BAAALgAECgYJEwAAAA==.Arethiel:BAAALgADCgYJBgAAAA==.Arlandriah:BAAALgADCgYJCQABLgAECgYJGAAGABAYAA==.Artronis:BAACLgAFFH8HAAILAAQJCwsgEwDDAAALAAQJCwsgEwDDAAAuAAQKfyYAAwsACAlPFqwRAK8BAAsACAlPFqwRAK8BAA8AAQk9FHpAAD0AAAAA.Artånis:BAAALgAECgcJDAAAAA==.Aruthuro:BAAALgAECgYJDwAAAA==.',
As='Ashbörn:BAAALgAECgQJBAAAAA==.Astel:BAAALgAECgcJDQAAAA==.',
At='Atriuz:BAABLgAECn8bAAIQAAYJahouLwDGAQAQAAYJahouLwDGAQAAAA==.Ats:BAAALgAECgIJAgAAAA==.',
Ay='Aykho:BAABLgAECn8nAAIRAAgJRRazXgCrAQARAAgJRRazXgCrAQAAAA==.',
Az='Azurion:BAAALgAECgYJCgAAAA==.',
['Aÿ']='Aÿ:BAAALgAECgMJAwAAAA==.',
Ba='Baguh:BAAALgADCggJCAAAAA==.Bagunça:BAAALgADCgYJBgAAAA==.Bakuugou:BAAALgAECgMJCgAAAA==.Bambur:BAAALgADCgMJAwAAAA==.Barbabruto:BAABLgAECn8sAAISAAgJLB6FCwAfAgASAAgJLB6FCwAfAgAAAA==.Basilisco:BAAALgAECgEJAQAAAA==.',
Be='Belleg:BAAALgAECgEJAgAAAA==.',
Bf='Bf:BAAALgADCgEJAQAAAA==.',
Bi='Biafalcão:BAAALgAECgEJAQAAAA==.Bijanca:BAAALgAECgYJBgAAAA==.Birthdäy:BAAALgADCgEJAQAAAA==.Bisponegro:BAAALgAECgQJCwABLgABCgcJFQANAAAAAA==.Biønic:BAAALgAECgMJCQAAAA==.',
Bl='Blackline:BAABLgAECn8fAAICAAgJPRI0ZACLAQACAAgJPRI0ZACLAQAAAA==.',
Bo='Boipretim:BAAALgAECgYJDwAAAA==.Bontorius:BAAALgADCgEJAgAAAA==.Bordello:BAAALgADCgUJBQAAAA==.',
Br='Bradio:BAAALgADCggJCAAAAA==.Brahman:BAAALgAECgEJAgAAAA==.Bratloko:BAAALgAECgUJBQAAAA==.Bromos:BAAALgAECgQJCAAAAA==.Brutalhoof:BAAALgAECgQJBAAAAA==.Brönsted:BAAALgADCgMJAwAAAA==.',
Bu='Bubbalo:BAAALgADCgUJBQAAAA==.Bullsman:BAAALgADCgQJBAAAAA==.Buzzumaaky:BAABLgAECn8YAAIRAAgJTxepiQC/AQARAAgJTxepiQC/AQAAAA==.',
By='Byakura:BAAALgADCggJCwAAAA==.',
['Bü']='Büdweiser:BAAALgAECgQJCgAAAA==.',
Ca='Cabernet:BAAALgAECgUJBwAAAA==.Cabeçaquente:BAAALgAECgcJCQAAAA==.Calhistra:BAABLgAECn8nAAMTAAgJQxkXRQDAAQATAAgJQxkXRQDAAQAUAAIJRQokVQBvAAAAAA==.Calteryeker:BAAALgAECgYJDwAAAA==.Camillas:BAAALgAECggJDwAAAA==.Caosenvy:BAAALgAECgEJAQAAAA==.Caralh:BAAALgAECgEJAgAAAA==.Castaldi:BAAALgAECgEJAgABLgAECgcJCwANAAAAAA==.Cathe:BAABLgAECn8VAAIVAAYJIRzJSwCGAQAVAAYJIRzJSwCGAQAAAA==.',
Ce='Cernûnnos:BAABLgAECn8UAAIDAAYJTg/KVwAfAQADAAYJTg/KVwAfAQAAAA==.',
Ch='Champdude:BAABLgAECn8/AAQIAAkJqiNRAwAfAwAIAAkJqiNRAwAfAwAWAAUJLxZXOQAGAQAHAAIJ5CJNXADKAAAAAA==.Chankowkwai:BAAALgAECgYJCQAAAA==.Chanë:BAAALgADCgIJAwAAAA==.Chewi:BAAALgAECgQJBgAAAA==.',
Ci='Citra:BAAALgAECgMJBwAAAA==.',
Co='Coconolose:BAAALgAECgIJBgAAAA==.Cod:BAAALgAECgIJAwAAAA==.Codecks:BAAALgADCgYJBgAAAA==.Coldbringer:BAAALgAECgEJAQAAAA==.Coldhearths:BAAALgAECgUJBgAAAA==.Couro:BAAALgAECgYJCAAAAA==.Cowçadora:BAAALgADCgIJAQAAAA==.',
Cr='Criminøsa:BAAALgAECgcJCQAAAA==.Cristcalad:BAABLgAECn83AAMXAAgJoBeCDwDeAQAXAAgJoBeCDwDeAQASAAEJYQULTwAfAAAAAA==.Cryomanta:BAAALgAECgUJBQAAAA==.',
Cu='Cunhaovirado:BAAALgAECgYJDAABLgAFFAUJDwAIANUZAA==.Cunhazinha:BAAALgAECgQJBAAAAA==.Cupyncha:BAAALgADCgUJBQAAAA==.Cutia:BAAALgADCgEJAQAAAA==.Cutiesissy:BAAALgAECgQJCAABLgAECgcJGgAGAEoQAA==.',
['Cø']='Cøøkye:BAAALgAECgQJBQAAAA==.',
Da='Daellus:BAAALgADCgUJBQAAAA==.Daemi:BAAALgAECgIJBAAAAA==.Daibodan:BAAALgAECgEJBAAAAA==.Dalaty:BAAALgAECgUJBQAAAA==.Daniilos:BAAALgAFFAEJAQAAAA==.Daresh:BAAALgADCgIJAgAAAA==.Darklara:BAABLgAECn8lAAIYAAkJBRm8BwDqAQAYAAkJBRm8BwDqAQAAAA==.Darkove:BAABLgAECn8uAAIRAAkJjBKlSgDkAQARAAkJjBKlSgDkAQAAAA==.Darrow:BAACLgAFFH8MAAMCAAQJRRh3RQBGAQACAAQJ5BV3RQBGAQAEAAMJhRi1DgDrAAAuAAQKfy4AAwIACQm0I+kPANsCAAIACQnZIukPANsCAAQACAn8IoECALYCAAAA.Dartibeccoso:BAAALgADCgcJBwAAAA==.',
De='Deany:BAAALgAECgEJAQAAAA==.Deathinhu:BAABLgAECn9QAAIRAAkJox/0EADiAgARAAkJox/0EADiAgAAAA==.Deathnacht:BAAALgAECgQJBwAAAA==.Delset:BAAALgADCgIJAgAAAA==.Demojoca:BAAALgAECgEJAQABLgAECgcJDgANAAAAAA==.Dentepodre:BAAALgADCgEJAQAAAA==.Dervus:BAAALgADCgcJBwAAAA==.Dethroned:BAAALgAECgUJDAAAAA==.Devrath:BAAALgAECgEJAQAAAA==.Devyogi:BAAALgADCgcJCAAAAA==.',
Di='Diefs:BAAALgAECgEJAQAAAA==.Dimeros:BAABLgAECn8uAAIOAAkJBQ/RHwCwAQAOAAkJBQ/RHwCwAQAAAA==.Dito:BAAALgADCgEJAQAAAA==.Divano:BAACLgAFFH8GAAIBAAIJ2xZ3JQCaAAABAAIJ2xZ3JQCaAAAuAAQKfycAAwEACAnJHw0MAHYCAAEACAnJHw0MAHYCABkAAwkCCZdVAHMAAAAA.',
Dk='Dkats:BAAALgAECgEJAgAAAA==.',
Dn='Dng:BAAALgAECgcJCAAAAA==.',
Do='Dogowner:BAAALgAECgkJEgAAAA==.Donora:BAABLgAECn8sAAQGAAkJFRPISADUAQAGAAkJFRPISADUAQAQAAEJfwOehwAsAAAFAAEJKAafUwAVAAAAAA==.',
Dr='Drackmontana:BAABLgAECn8lAAMaAAgJaA4gNgDQAQAaAAgJEg4gNgDQAQASAAIJEhVBPQBjAAAAAA==.Drafael:BAAALgADCggJDgABLgAECgkJQwAPAHEhAA==.Dragoniron:BAAALgADCgEJAQAAAA==.Dragony:BAAALgAECgEJBAAAAA==.Dragunass:BAABLgAECn8wAAMaAAgJoxxsGgAGAgAaAAgJFxxsGgAGAgASAAcJPBqgEQC5AQAAAA==.Dragøndeath:BAAALgADCgEJAgAAAA==.Drakars:BAAALgADCgUJBAAAAA==.Dranarus:BAAALgADCgQJBAAAAA==.Drexus:BAAALgAECgQJBAAAAA==.Druidblack:BAAALgAECgIJAgAAAA==.Drunkler:BAAALgAECgYJBgAAAA==.Dryter:BAABLgAECn8VAAIIAAcJEA9QKwCEAQAIAAcJEA9QKwCEAQAAAA==.Drákon:BAAALgADCgUJBgAAAA==.',
Du='Dubhe:BAAALgAECgUJDAAAAA==.',
Dy='Dysttopia:BAAALgADCgcJCAAAAA==.',
El='Eldryrin:BAAALgAECgEJAQAAAA==.Elendile:BAAALgAECgEJAQAAAA==.Elinius:BAABLgAECn8vAAMOAAkJzSB2BwDLAgAOAAkJzSB2BwDLAgADAAIJUwzIyAAuAAAAAA==.Elistraee:BAAALgAECgEJAQAAAA==.Ellandria:BAAALgAECgMJAwAAAA==.Ellonara:BAAALgAECgEJAQAAAA==.Eloren:BAAALgAECgYJCwABLgAECggJIAAQAPERAA==.Eluuria:BAAALgAFFAEJAQAAAA==.Elyzia:BAAALgAECgEJAQAAAA==.',
En='Endorena:BAAALgADCgEJAQAAAA==.',
Ep='Ephesus:BAAALgADCgIJAgAAAA==.',
Er='Erikssen:BAAALgADCgYJBgAAAA==.Ernest:BAABLgAECn86AAIDAAkJ0R6cBwAvAwADAAkJ0R6cBwAvAwAAAA==.Erynneus:BAAALgADCgMJAwAAAA==.',
Es='Estagiario:BAAALgAECgQJBgABLgAECgkJLAAJAEkjAA==.',
Ev='Evetts:BAAALgADCgEJAQAAAA==.Evilbarba:BAAALgAECgIJAgAAAA==.',
Ex='Exort:BAABLgAECn8ZAAIRAAYJcBNgkwA2AQARAAYJcBNgkwA2AQAAAA==.Expressão:BAAALgADCgYJCwAAAA==.',
Fa='Faeldar:BAACLgAFFH8HAAIZAAMJQgywKgDCAAAZAAMJQgywKgDCAAAuAAQKfzoAAhkACQnbEtgTACACABkACQnbEtgTACACAAAA.Faldark:BAAALgAECgQJBgAAAA==.Fandrall:BAAALgAECgUJCAAAAA==.Faris:BAABLgAFFH8HAAIbAAIJ6RCbKQCgAAAbAAIJ6RCbKQCgAAAAAA==.Faver:BAAALgAECgQJBQAAAA==.Faölin:BAABLgAECn8mAAIbAAcJvBpNGwCkAQAbAAcJvBpNGwCkAQAAAA==.',
Fe='Feenigan:BAAALgAECgEJAQABLgAECgQJBAANAAAAAA==.Feeniä:BAAALgAECgQJBAAAAA==.Ferael:BAABLgAECn84AAIGAAkJUSIcDADwAgAGAAkJUSIcDADwAgAAAA==.',
Fi='Fil:BAAALgAECgEJAQAAAA==.Firstomega:BAAALgADCgMJAwAAAA==.',
Fl='Flavors:BAACLgAFFH8FAAIaAAMJzyQ9FwA/AQAaAAMJzyQ9FwA/AQAuAAQKfyMAAxoACQndIxYGAO0CABoACQndIxYGAO0CABcABAkhHgIUAGYBAAAA.Florbela:BAAALgAECgUJCAAAAA==.Flämbë:BAAALgADCgEJAQAAAA==.',
Fo='Fogue:BAAALgAECgkJDgAAAA==.Foxthamy:BAABLgAECn8mAAIHAAcJaxKKMwB5AQAHAAcJaxKKMwB5AQAAAA==.',
Fr='Frachlitzz:BAACLgAFFH8FAAIRAAMJ9Q0BcwDcAAARAAMJ9Q0BcwDcAAAuAAQKfzsAAhEACQmBFSg5AB0CABEACQmBFSg5AB0CAAAA.Fradem:BAAALgAECgcJDAAAAA==.Freccianera:BAAALgADCgEJAQAAAA==.Fredericc:BAABLgAECn8aAAMcAAkJCg8gQACQAQAcAAgJwQ0gQACQAQAdAAcJ2gVYWQDfAAAAAA==.Fredinho:BAAALgAECgEJAQAAAA==.Freecs:BAAALgAECgYJBwABLgAECgcJCwANAAAAAA==.Freyá:BAABLgAECn8jAAIGAAkJcCFfEADPAgAGAAkJcCFfEADPAgAAAA==.Frostgore:BAAALgAECgEJAQAAAA==.Froststriker:BAAALgAECgEJAQAAAA==.Frs:BAAALgAECgEJAgAAAA==.',
Ga='Galhuda:BAAALgADCgYJBgAAAA==.Galyan:BAAALgADCgEJAQAAAA==.Gandwelf:BAAALgADCgkJCQAAAA==.Gazieri:BAABLgAECn8gAAMQAAgJ8RFkRQBiAQAQAAgJ8RFkRQBiAQAGAAQJCw/z2gDWAAAAAA==.',
Ge='Geisty:BAAALgAECgMJAwABLgAECgcJHwACAIAJAA==.',
Gh='Ghalladriel:BAAALgADCgEJAwAAAA==.Ghruka:BAAALgAECgQJBAAAAA==.',
Gi='Giafar:BAAALgAECgEJAQABLgAECgYJBgANAAAAAA==.',
Gl='Glutotwo:BAAALgADCgEJAQAAAA==.',
Gn='Gnomari:BAABLgAECn8WAAITAAgJKQFu/QBZAAATAAgJKQFu/QBZAAAAAA==.',
Go='Goratrix:BAAALgAECgUJBQABLgAECgcJHwACAIAJAA==.Gordanado:BAAALgAECgEJAgAAAA==.Gordruida:BAAALgAECgEJAQAAAA==.Govers:BAAALgADCgMJAwABLgAECgMJBAANAAAAAA==.',
Gr='Grandecoisa:BAAALgAECgEJAQAAAA==.Greyfin:BAAALgADCgEJAQAAAA==.Greyvor:BAAALgADCgEJAQAAAA==.Grimch:BAAALgAECgEJAQAAAA==.Grumax:BAABLgAECn8UAAIGAAgJyQ/FdACRAQAGAAgJyQ/FdACRAQAAAA==.Grössa:BAABLgAECn8YAAMQAAcJIwiGWwAOAQAQAAcJIwiGWwAOAQAGAAMJCQQXXwE6AAABLgAECgkJFwATAJ8IAA==.',
Gu='Guitianki:BAAALgAECgEJAQAAAA==.Gulek:BAAALgAECgMJAwAAAA==.Gussg:BAABLgAECn8XAAQTAAkJnwjoWwB/AQATAAkJnwjoWwB/AQAeAAEJzwiqOQArAAAUAAIJGQS3PwAeAAAAAA==.Gustavonz:BAAALgADCgcJBwAAAA==.',
['Gö']='Göhan:BAAALgADCgUJBQABLgAECgYJEwANAAAAAA==.',
['Gø']='Gøvers:BAAALgAECgMJBAAAAA==.',
Ha='Handyman:BAAALgADCgYJBgAAAA==.Hantom:BAAALgADCgMJAwABLgAFFAUJDwAIANUZAA==.',
He='Hefestion:BAAALgAECgQJBQAAAA==.Helsingdarck:BAAALgADCgIJAgAAAA==.Hendrikison:BAAALgAECgIJAgAAAA==.',
Hi='Hildegyth:BAABLgAECn8fAAMIAAgJWBE1MQBhAQAIAAcJWRE1MQBhAQAHAAUJZxHaTAADAQAAAA==.',
Hj='Hjalmar:BAAALgADCgcJCQAAAA==.',
Ho='Hodtiva:BAABLgAECn8tAAMBAAgJdBBHKABtAQABAAgJdBBHKABtAQAKAAUJDA57RwCwAAAAAA==.Homerz:BAAALgADCgEJAQAAAA==.Hotmojo:BAAALgAECgcJEQABLgAFFAUJDwAdAE0cAA==.',
Hr='Hrafnn:BAAALgADCgQJBAAAAA==.',
Hu='Hunfox:BAACLgAFFH8SAAIVAAMJIRxpCwAHAQAVAAMJIRxpCwAHAQAuAAQKf0QAAhUACQmuI8YGABgDABUACQmuI8YGABgDAAAA.',
['Hä']='Härkness:BAAALgAECgEJAgAAAA==.',
['Hü']='Hüskar:BAABLgAECn8fAAMaAAkJ/AuGKwCSAQAaAAkJuQuGKwCSAQAXAAEJCg+lagAwAAAAAA==.',
Ic='Icechips:BAAALgADCgUJBQAAAA==.Ichigoz:BAABLgAECn8fAAIRAAkJQAnVbQCGAQARAAkJQAnVbQCGAQAAAA==.',
Ih='Ihntwuaed:BAAALgADCgYJCQAAAA==.',
Ik='Ikoo:BAABLgAECn87AAIZAAkJKh1ZBwDqAgAZAAkJKh1ZBwDqAgAAAA==.',
Il='Illaril:BAACLgAFFH8cAAIYAAUJzh2FAgBbAQAYAAUJzh2FAgBbAQAuAAQKf2MAAhgACQmMIWQCANcCABgACQmMIWQCANcCAAAA.',
In='Indarion:BAAALgADCgYJEQAAAA==.Ingratt:BAAALgAECgEJAgAAAA==.Invisiblelol:BAAALgAECgIJAgAAAA==.',
Ir='Irmãodouther:BAAALgAECggJCAAAAA==.',
Is='Isebby:BAAALgADCgMJAwAAAA==.Ishtarie:BAAALgAECgQJBQABLgAECgkJHgADAJkXAA==.',
It='Itzzdan:BAAALgADCgMJAwAAAA==.',
Iv='Ivina:BAABLgAECn8UAAMTAAgJThbwkQA1AQATAAcJThbwkQA1AQAeAAIJqRe4HACNAAAAAA==.',
Iz='Izaar:BAAALgAECgQJDgAAAA==.',
Ja='Jacsonnaik:BAAALgAECgQJBQAAAA==.Janaìna:BAAALgAECgMJAwAAAA==.Jangeoffry:BAAALgADCgEJAQAAAA==.',
Jh='Jhonatinha:BAABLgAECn8VAAMGAAcJBxmpzQDXAAAGAAYJaxmpzQDXAAAQAAQJng69dgCfAAAAAA==.',
Ji='Jigsaww:BAAALgAECgQJCAAAAA==.',
Jo='Joaquim:BAAALgAECgIJAgAAAA==.Jogaveiopl:BAAALgADCgIJAgAAAA==.Johnlobo:BAAALgAECgEJAQAAAA==.Joventino:BAAALgADCgQJBQAAAA==.',
Ju='Jucah:BAABLgAECn8ZAAIdAAkJZAv1MwBQAQAdAAkJZAv1MwBQAQAAAA==.Julabolseiro:BAAALgAECgUJBQAAAA==.Jullianxd:BAAALgADCgIJAgABLgAECgkJFgAfAOwPAA==.',
Ka='Kaallew:BAABLgAECn8ZAAIFAAkJuRdRFQBiAQAFAAkJuRdRFQBiAQAAAA==.Kaezar:BAAALgADCgEJAQAAAA==.Kainer:BAAALgAECgQJBQAAAA==.Kalazshar:BAABLgAECn8iAAILAAkJcxDsFQCBAQALAAkJcxDsFQCBAQAAAA==.Kalelzinho:BAAALgADCgYJBgAAAA==.Kaluss:BAAALgAECgYJDAAAAA==.Kanalet:BAAALgAECgYJCAAAAA==.Kantaa:BAAALgAECgQJCgAAAA==.Kanturu:BAAALgAECgQJBAAAAA==.Kanzaki:BAAALgADCgcJBwABLgAECgkJPwAIAKojAA==.Karonn:BAABLgAECn8UAAIGAAYJ/A3mlABTAQAGAAYJ/A3mlABTAQAAAA==.Kavartu:BAAALgAECgYJBgAAAA==.Kaymon:BAAALgAECgEJAQAAAA==.',
Ke='Keillor:BAABLgAECn8dAAIcAAYJKxQKTgBbAQAcAAYJKxQKTgBbAQAAAA==.Kelantir:BAAALgAECgYJCQABLgAECgkJDAANAAAAAA==.Keldorian:BAAALgADCgcJEAAAAA==.Kelishe:BAAALgAECgUJBQAAAA==.Kelliar:BAAALgAECgIJAQAAAA==.Kelorn:BAAALgADCgYJBgAAAA==.Kelysa:BAAALgADCgkJDgABLgAECggJPQASACYdAA==.Kenzou:BAABLgAECn8XAAMWAAcJ0hirLQA+AQAWAAUJexyrLQA+AQAIAAcJSQ9RMQAqAQAAAA==.',
Kh='Khadi:BAAALgAECgcJCwAAAA==.Khaeltaz:BAAALgAECgMJAwAAAA==.Khalandra:BAABLgAECn8eAAIaAAkJaBtyKwAIAgAaAAkJaBtyKwAIAgAAAA==.Khalel:BAAALgADCgEJAgAAAA==.Khaliq:BAABLgAECn8eAAMJAAkJVxV6EQD0AQAJAAkJVxV6EQD0AQAfAAQJLApxrwCtAAAAAA==.Khallani:BAABLgAECn8fAAICAAcJgAlLlQBWAQACAAcJgAlLlQBWAQAAAA==.Khamul:BAAALgAECgQJBgAAAA==.Khaos:BAAALgAECggJEwAAAA==.Khisto:BAABLgAECn80AAMRAAkJnRvVMgA1AgARAAkJnRvVMgA1AgAgAAcJ3RcNBAChAQAAAA==.Khroriggs:BAAALgAECgYJDQABLgAECgcJBwANAAAAAA==.',
Ki='Killerbiie:BAAALgADCgIJAgAAAA==.Killerdown:BAAALgADCgIJAgAAAA==.Kimashi:BAAALgAECgUJBQAAAA==.Kindie:BAAALgADCgcJCwABLgAECggJFAAfABEIAA==.Kissme:BAABLgAECn8eAAMOAAkJmBCpKABxAQAOAAgJ3hGpKABxAQALAAQJiAjKOgCSAAAAAA==.Kitamor:BAABLgAECn9EAAIOAAkJ2A09JACPAQAOAAkJ2A09JACPAQAAAA==.Kiya:BAAALgADCgcJHgAAAA==.',
Kl='Klorokina:BAAALgAECgYJBgAAAA==.',
Ko='Koriakin:BAABLgAECn8fAAMVAAkJ5xnWFQCOAgAVAAkJ5xnWFQCOAgAhAAUJohF9NAD6AAAAAA==.Kosmo:BAAALgAECgQJBAAAAA==.Kotalkhan:BAAALgADCgkJEQAAAA==.',
Kr='Krov:BAAALgAECgEJAQAAAA==.Kryon:BAAALgAECgYJDgAAAA==.Kryzthor:BAAALgAECgYJCAAAAA==.Kräsus:BAABLgAECn86AAISAAkJ4yXMAABfAwASAAkJ4yXMAABfAwAAAA==.Krønna:BAAALgAECgQJBAABLgAECgYJKQAiAEsIAA==.',
Ku='Kul:BAAALgAECgUJBgAAAA==.Kuroelf:BAAALgAECgMJAwAAAA==.Kuthila:BAAALgADCgIJAgAAAA==.',
Ky='Kyzaru:BAAALgAECgEJAQAAAA==.',
['Kÿ']='Kÿdou:BAAALgAECgcJDgAAAA==.',
La='Ladrion:BAABLgAECn9PAAQjAAkJUh9xAQDQAgAjAAkJIR5xAQDQAgAbAAkJAxmFFABuAgAkAAkJ9RdPBAA/AgAAAA==.Laetus:BAABLgAECn8ZAAIlAAYJhBiZBQBhAQAlAAYJhBiZBQBhAQAAAA==.Lagosta:BAAALgAECgMJBgAAAA==.Laiany:BAABLgAECn9FAAIKAAkJJSI9AwBRAwAKAAkJJSI9AwBRAwAAAA==.Lani:BAAALgAECgEJAQAAAA==.',
Le='Legacia:BAAALgADCgYJBgAAAA==.Lekrom:BAAALgADCgYJBgAAAA==.Leodoros:BAAALgADCgEJAQAAAA==.Lequinhö:BAAALgAECgIJAgAAAA==.Leric:BAAALgADCgcJCgAAAA==.Lethmar:BAABLgAECn8aAAITAAcJMxdvVQCQAQATAAcJMxdvVQCQAQAAAA==.Levanah:BAAALgADCgYJBgAAAA==.Leyana:BAAALgAECgUJBgAAAA==.',
Lh='Lhwei:BAAALgAECgIJAgABLgAFFAIJBgAHAN4aAA==.',
Li='Liandra:BAAALgAECgEJAQAAAA==.Licaon:BAAALgADCgYJCwAAAA==.Lichkiller:BAAALgAECgUJBQAAAA==.Lightbreaker:BAABLgAECn8jAAIGAAkJZAjYfABaAQAGAAkJZAjYfABaAQAAAA==.Lihr:BAAALgADCgYJCQAAAA==.Lilianpotter:BAAALgAECgEJAQAAAA==.Lilithrix:BAAALgADCgIJAgAAAA==.Lillit:BAABLgAECn83AAQeAAgJ7g2WDQBeAQATAAgJQw2QYAB0AQAeAAgJfQuWDQBeAQAUAAIJvwaHNgA4AAAAAA==.Lindaah:BAABLgAECn8qAAMIAAgJqxdaGgDGAQAIAAgJqxdaGgDGAQAHAAYJ3gRBbACZAAAAAA==.Lindademon:BAAALgAECgUJDQAAAA==.Lindahealer:BAAALgAECgUJCAABLgAECgUJDQANAAAAAA==.Lislfox:BAABLgAECn84AAILAAkJQBjOCQAqAgALAAkJQBjOCQAqAgAAAA==.Lithlad:BAAALgADCgIJAgAAAA==.',
Lk='Lkinho:BAAALgAECgMJBAAAAA==.',
Lm='Lmmds:BAAALgADCgYJFQAAAA==.',
Lo='Lockynha:BAAALgADCgEJAQAAAA==.Loohynir:BAAALgAFFAIJAwAAAA==.Lotusbird:BAAALgADCgcJBwAAAA==.',
Lu='Lucario:BAAALgAECgEJAgAAAA==.Luccoa:BAAALgAECgkJCQABLgAECgkJOgASAOMlAA==.Luccyah:BAAALgADCgkJDAAAAA==.Lucifïr:BAAALgAECgEJAQAAAA==.Lucileia:BAAALgAECgQJBQAAAA==.Lukazgplay:BAAALgADCgIJAgAAAA==.Lutsul:BAAALgAECgEJAQAAAA==.',
Ly='Lylka:BAABLgAECn84AAMFAAkJkyWgAABdAwAFAAkJkyWgAABdAwAQAAMJIiPYPgAyAQAAAA==.Lyrrena:BAAALgAECgMJBAAAAA==.',
Ma='Maanu:BAAALgAECgQJBgABLgAECggJKgAIAKsXAA==.Macumbadora:BAAALgAECgQJCgAAAA==.Madfulock:BAAALgAECgcJEgAAAA==.Maeghann:BAAALgADCgMJAwAAAA==.Magalândia:BAAALgADCgEJAgAAAA==.Magraver:BAAALgAECgMJAwAAAA==.Mais:BAAALgADCgMJBQAAAA==.Malewolyyc:BAACLgAFFH8HAAMKAAIJyR5kHgCjAAAKAAIJyR5kHgCjAAABAAEJZgeeMgBCAAAuAAQKfysAAwoACQmZIW8KAKsCAAoACAk/I28KAKsCAAEABglGERQzACsBAAEuAAUUAwkDAA0AAAAA.Malhun:BAAALgADCgUJDgAAAA==.Malphan:BAAALgAECgcJBwAAAA==.Malyguz:BAACLgAFFH8UAAIRAAQJ1BI3SQA8AQARAAQJ1BI3SQA8AQAuAAQKfxsAAhEABwldG+BgABkCABEABwldG+BgABkCAAAA.Malévolatity:BAAALgAECgUJCgAAAA==.Manipullador:BAAALgAECgIJAgAAAA==.Mapussauro:BAAALgAECgcJEQAAAA==.Maradi:BAAALgADCgIJAgAAAA==.Mariob:BAAALgAFFAIJAwAAAA==.Marjøly:BAAALgAECgEJAQAAAA==.Markson:BAAALgADCgEJAQAAAA==.Massafera:BAABLgAECn8fAAIGAAkJMxPgTwDAAQAGAAkJMxPgTwDAAQAAAA==.Mather:BAAALgAECgEJAQAAAA==.Mathfacbruxo:BAABLgAECn9BAAITAAkJIRuwGgB3AgATAAkJIRuwGgB3AgAAAA==.Mauritiuz:BAAALgAFFAEJAQAAAA==.Mayanyy:BAAALgAECgEJAQAAAA==.',
Mc='Mcq:BAAALgAECgEJAQAAAA==.',
Md='Mdrdark:BAACLgAFFH8NAAICAAUJlxRoUAAzAQACAAUJlxRoUAAzAQAuAAQKfy0AAwIACQmiGaQqAEICAAIACQmiGaQqAEICACYAAwm/FQ9BAG8AAAAA.',
Me='Medz:BAABLgAECn8jAAIRAAkJlRqCKgBZAgARAAkJlRqCKgBZAgAAAA==.Meedea:BAAALgADCgUJBgAAAA==.Meetjack:BAAALgADCgIJAgAAAA==.Meiyin:BAAALgAECgMJBAAAAA==.Melania:BAAALgAECgEJAgAAAA==.Melissandra:BAAALgAFFAIJAwAAAA==.Mellkor:BAABLgAECn8pAAIJAAgJIhy8DgAZAgAJAAgJIhy8DgAZAgAAAA==.Melytah:BAAALgAECgEJAgAAAA==.Melzynhaa:BAAALgAECgEJAQABLgAECggJKgAIAKsXAA==.Meraxxes:BAAALgADCgcJDAAAAA==.Merellien:BAAALgADCggJDgAAAA==.Metamorful:BAABLgAECn8ZAAIDAAkJBxL/SQB7AQADAAkJBxL/SQB7AQAAAA==.',
Mh='Mhorgann:BAAALgAECgUJBgAAAA==.',
Mi='Mijonakombi:BAABLgAECn8WAAIGAAkJ/hpbKABJAgAGAAkJ/hpbKABJAgAAAA==.Mikveh:BAAALgAECgUJCQAAAA==.Milim:BAABLgAECn8/AAMMAAkJ8hNTGwDjAQAMAAkJ2RJTGwDjAQAnAAgJRQ0YDgAaAQAAAA==.Milliidan:BAAALgADCgUJBQAAAA==.Mindrathys:BAAALgAECgEJAQAAAA==.Mithrius:BAABLgAECn8kAAIGAAgJxxH1YwCOAQAGAAgJxxH1YwCOAQAAAA==.',
Ml='Mls:BAAALgADCgYJCwAAAA==.',
Mo='Mogrus:BAAALgADCgMJAwAAAA==.Mohanna:BAAALgAECggJDgAAAA==.Mohanninha:BAAALgAECgYJCwAAAA==.Mohotok:BAABLgAECn9AAAIGAAkJGRnyLAA0AgAGAAkJGRnyLAA0AgAAAA==.Moonøvesso:BAAALgAECgIJBAAAAA==.Moopp:BAAALgADCgcJCAAAAA==.Mortixxia:BAABLgAECn8nAAIUAAgJnx1RAwBLAgAUAAgJnx1RAwBLAgAAAA==.',
Mu='Muata:BAAALgAECgYJDwAAAA==.Muf:BAAALgAECgYJBgAAAA==.Mupar:BAAALgADCgIJAgAAAA==.Murano:BAABLgAECn8yAAMaAAkJxR44CwCfAgAaAAkJxR44CwCfAgAXAAMJywoASQCIAAAAAA==.Muzzo:BAAALgADCgYJCwABLgAECgYJDgANAAAAAA==.',
My='Myrmïdom:BAAALgAECgIJAgAAAA==.Myzoreh:BAAALgAECgcJCgAAAA==.',
['Má']='Mágico:BAAALgAECgEJAwAAAA==.Máia:BAABLgAECn8UAAIUAAgJiAzcDgA3AQAUAAgJiAzcDgA3AQAAAA==.',
['Mä']='Mändosz:BAABLgAECn8ZAAMCAAkJMRIOYQCTAQACAAgJahIOYQCTAQAEAAMJCRCeHAC2AAAAAA==.',
['Mé']='Ménace:BAABLgAECn8VAAMTAAkJ5h32WgC3AQATAAgJ5h32WgC3AQAUAAMJXA7yRgCaAAAAAA==.',
Na='Nalathiel:BAAALgAECgcJEQAAAA==.Narancia:BAAALgAECgYJDQABLgAECgcJCwANAAAAAA==.Naryth:BAAALgAECgYJCAAAAA==.Nassur:BAAALgADCgEJAQAAAA==.Nattaliaa:BAAALgAECgEJAQAAAA==.Nazawill:BAAALgADCgEJAQAAAA==.Nazdru:BAAALgADCgMJAwABLgAECgkJQwAPAHEhAA==.Nazzh:BAAALgAECgEJAQABLgAECgQJBQANAAAAAA==.',
Ne='Necronx:BAAALgAECgEJAQAAAA==.Necronxd:BAAALgADCgEJAgAAAA==.Nefas:BAABLgAECn8jAAIUAAkJYxOJBgDZAQAUAAkJYxOJBgDZAQAAAA==.Nefazo:BAAALgAECgcJCgAAAA==.Nefilo:BAAALgADCgYJEAAAAA==.Nepthunus:BAABLgAECn82AAIgAAkJ1x7ZAADKAgAgAAkJ1x7ZAADKAgAAAA==.Nermand:BAAALgAECgEJAQAAAA==.Neshula:BAAALgADCgMJAwAAAA==.Neuvosor:BAAALgAECgEJAQAAAA==.',
Ni='Nibelunga:BAAALgADCgYJBgAAAA==.Nijor:BAAALgADCgYJBgAAAA==.Nilsonssbnu:BAAALgAECgEJAQAAAA==.',
No='Nobelnaga:BAAALgAECgMJAwAAAA==.Novatoo:BAAALgAECgQJBwAAAA==.',
Ny='Nyobb:BAAALgADCgMJAwAAAA==.Nyxra:BAAALgADCgcJEAAAAA==.',
['Nö']='Nöirr:BAAALgADCgcJDgAAAA==.',
Oc='Ocelotte:BAAALgADCgEJAQAAAA==.',
Od='Odynsabio:BAAALgAECgEJAQAAAA==.',
Of='Ofanzitsu:BAAALgADCgQJBAAAAA==.',
Oi='Oioimiguel:BAAALgADCgYJCwAAAA==.',
Ol='Olhua:BAAALgAECgIJBAAAAA==.Oljedvlad:BAAALgADCgEJAQAAAA==.Oluss:BAAALgADCgUJBQABLgAFFAMJEgAVACEcAA==.',
Om='Omnath:BAAALgADCgYJBgAAAA==.',
Or='Orillan:BAABLgAECn9AAAMJAAkJnRp8CgBkAgAJAAkJnRp8CgBkAgAfAAEJhAcY5gAsAAAAAA==.Ornsteinsnow:BAABLgAECn8ZAAIQAAkJvhRiGQAkAgAQAAkJvhRiGQAkAgAAAA==.Orob:BAAALgAECgEJAgAAAA==.Ororah:BAAALgAECgYJDwAAAA==.Orukam:BAABLgAECn8ZAAMDAAkJMBY4PwCDAQADAAgJ7BQ4PwCDAQAOAAMJTghnXQCCAAAAAA==.',
Os='Oszwald:BAAALgADCgEJAQAAAA==.',
['Oú']='Oúkürä:BAAALgAECgYJCgAAAA==.',
Pa='Padawani:BAAALgAECgIJAgAAAA==.Padgodeira:BAAALgAECgQJBAAAAA==.Padrealpha:BAAALgADCgcJCgAAAA==.Padrekelmøn:BAAALgAECgQJBAAAAA==.Palaha:BAAALgADCgEJAQABLgAFFAMJEgAVACEcAA==.Palatina:BAABLgAFFH8GAAIGAAUJWhdJMAAzAQAGAAUJWhdJMAAzAQAAAA==.Palazzy:BAAALgAECgEJAgAAAA==.Pandong:BAAALgAECgQJBwAAAA==.Panena:BAAALgAECgIJAwAAAA==.Pangedrey:BAABLgAECn9MAAIIAAkJ5x8ABwDIAgAIAAkJ5x8ABwDIAgAAAA==.Paracepatrol:BAAALgAECgQJAwAAAA==.Parcival:BAACLgAFFH8JAAIVAAMJoBoGQwACAQAVAAMJoBoGQwACAQAuAAQKfzIAAhUACQmKI9kDAEUDABUACQmKI9kDAEUDAAAA.Parký:BAAALgAECgYJBgAAAA==.Pattalógika:BAAALgAECgEJAQAAAA==.Paullk:BAABLgAECn8gAAIOAAYJchRLNwAcAQAOAAYJchRLNwAcAQAAAA==.',
Pe='Pedrinho:BAAALgADCgYJBgABLgAFFAUJDgAfAJMfAA==.Penéllope:BAAALgAECgQJBwAAAA==.Persëphone:BAABLgAECn8VAAMKAAcJsRS9OAABAQAKAAUJyRC9OAABAQABAAYJCBLTUQCgAAAAAA==.Peruchi:BAAALgAECgQJBAAAAA==.',
Pg='Pgms:BAAALgADCgYJDwAAAA==.',
Ph='Phacozitos:BAAALgAECgEJAQAAAA==.Phaxe:BAAALgADCgIJAgAAAA==.Phoenicx:BAAALgADCgMJBgAAAA==.Phøënïx:BAAALgAECgcJDAAAAA==.',
Pi='Pipelinebr:BAAALgAECgUJBQAAAA==.Pitombinha:BAAALgAECgEJAgAAAA==.',
Pp='Pp:BAABLgAFFH8LAAQZAAMJewQeOABvAAAZAAIJRAYeOABvAAABAAEJPAGxNwArAAAKAAEJ6wApNAAoAAAAAA==.',
Pr='Prometeus:BAAALgAECgYJDwAAAA==.Pryon:BAAALgAECgUJCwAAAA==.',
Pt='Ptollomeu:BAAALgAECgMJBAABLgAECgMJCQANAAAAAA==.',
['Pä']='Pändero:BAAALgAFFAEJAQAAAA==.Pänqueca:BAAALgAECgEJAgAAAA==.',
['Pé']='Pénacova:BAAALgADCgEJAQAAAA==.',
['Pî']='Pîo:BAACLgAFFH8GAAIRAAMJVxHJawDqAAARAAMJVxHJawDqAAAuAAQKfxcAAxEACAltGcBWAMABABEACAl5GMBWAMABACUABAnTGPAKACwBAAAA.',
Qu='Quejerok:BAAALgAECgYJEwAAAA==.',
Ra='Radunz:BAABLgAECn9DAAIPAAkJcSE4AgD1AgAPAAkJcSE4AgD1AgAAAA==.Ragnaros:BAAALgAECgEJAQAAAA==.Raineko:BAAALgADCgYJBgAAAA==.Raio:BAACLgAFFH8FAAIRAAIJlxPJjQCVAAARAAIJlxPJjQCVAAAuAAQKfy8AAhEACQkEIWIZAKsCABEACQkEIWIZAKsCAAAA.Ralfwur:BAAALgAECgQJBwAAAA==.Rargsa:BAABLgAECn8XAAIEAAgJQQZkFgD1AAAEAAgJQQZkFgD1AAAAAA==.Rariel:BAAALgADCgMJAgAAAA==.Rasmon:BAABLgAECn8uAAITAAkJRxSWOwDfAQATAAkJRxSWOwDfAQAAAA==.Ravendreth:BAAALgADCgEJAQAAAA==.Raykarla:BAAALgAECgIJAwAAAA==.Raymain:BAACLgAFFH8GAAMIAAMJzh1wFgD9AAAIAAMJzh1wFgD9AAAHAAEJkw4vTgAyAAAuAAQKfyQAAwcACQkSFnA0AHQBAAcACAmaFHA0AHQBAAgABwkXFswyACMBAAAA.Raíka:BAAALgAECgYJCwAAAA==.',
Re='Reddnose:BAAALgAECgUJCQAAAA==.Reinhold:BAAALgAECgYJEwAAAA==.',
Rh='Rhuryk:BAAALgADCggJCAAAAA==.',
Ri='Ricktdai:BAAALgAECgEJAQAAAA==.Riesze:BAABLgAECn8nAAIVAAkJfRlSGwBsAgAVAAkJfRlSGwBsAgAAAA==.',
Ro='Roguinhu:BAAALgAECgEJAQAAAA==.Ropaoo:BAAALgAECgYJEwAAAA==.',
Ru='Rua:BAAALgAECgQJBAAAAA==.Rusga:BAAALgADCggJCAAAAA==.Rustovick:BAAALgAECgMJBQAAAA==.',
Ry='Rytheas:BAAALgAECgQJBgAAAA==.',
['Rä']='Rämzä:BAAALgAECgYJEwAAAA==.',
['Rå']='Råy:BAAALgAECgQJCAAAAA==.',
['Rí']='Rízadinha:BAAALgAECgQJBAAAAA==.',
Sa='Saargeras:BAAALgADCgMJAwAAAA==.Saffír:BAABLgAECn8mAAIGAAkJTRjXLgAsAgAGAAkJTRjXLgAsAgAAAA==.Saiden:BAAALgADCgQJBAAAAA==.Saintkaue:BAAALgADCgUJCAAAAA==.Samalandraa:BAAALgADCgEJAQAAAA==.Sanahh:BAAALgAECgYJCAAAAA==.Sanateia:BAAALgADCgYJCwAAAA==.Santamadre:BAAALgADCgEJAQAAAA==.Sapekinhä:BAABLgAECn8sAAQJAAkJSSNqAwAIAwAJAAkJSSNqAwAIAwAYAAIJUhjLHwCBAAAfAAIJRQnp5gBLAAAAAA==.Saphirah:BAAALgAECgQJBwAAAA==.Satanvitória:BAABLgAECn8uAAMXAAgJ7B6/CgAkAgAaAAcJYRo0JgAoAgAXAAgJbh6/CgAkAgAAAA==.',
Sc='Scheiren:BAAALgAECgQJBgAAAA==.',
Se='Senegos:BAAALgADCgcJBwAAAA==.Sereiaa:BAABLgAECn8lAAIVAAcJjQ7xawBSAQAVAAcJjQ7xawBSAQAAAA==.Sesiom:BAAALgAECgcJBgAAAA==.',
Sh='Shalltearr:BAAALgADCgEJAQAAAA==.Shamate:BAAALgAECgMJBQAAAA==.Shanoa:BAAALgAECgMJAwAAAA==.Shariany:BAAALgADCgEJAQAAAA==.Sharpersong:BAAALgADCgcJBgAAAA==.Shedo:BAABLgAECn8VAAMXAAgJAxpuFACjAQAXAAcJuBluFACjAQAaAAYJWg+VYgAoAQAAAA==.Sheevane:BAABLgAECn8eAAIDAAkJmReqIQAnAgADAAkJmReqIQAnAgAAAA==.Shinzo:BAAALgADCgEJAQAAAA==.Shonja:BAAALgADCgcJDgAAAA==.Shula:BAAALgADCgcJDQAAAA==.Shÿnara:BAAALgAECgkJDwAAAA==.',
Si='Siclop:BAAALgADCgYJBgAAAA==.Silgris:BAAALgAECgEJAQABLgAECggJIAAQAPERAA==.Silmeria:BAABLgAECn8WAAIcAAgJAgVfaQAAAQAcAAgJAgVfaQAAAQAAAA==.Silverchain:BAAALgADCgcJCgAAAA==.Sinton:BAAALgAECgQJCAAAAA==.',
Sk='Skadryan:BAAALgAECgEJAQAAAA==.Skeletowman:BAAALgADCgEJAQAAAA==.Skineh:BAAALgAECgQJBwAAAA==.Skinme:BAABLgAECn8UAAIHAAYJKwTScwCDAAAHAAYJKwTScwCDAAAAAA==.',
Sm='Smylf:BAAALgAECgkJEAAAAA==.',
Sn='Snakedown:BAAALgAECgEJAgAAAA==.',
So='Sombrea:BAAALgAECgYJDAAAAA==.',
Sp='Spectrø:BAAALgAECgYJBgAAAA==.',
Sr='Srheal:BAAALgAECgQJBAAAAA==.Srsapo:BAAALgAECgMJBgAAAA==.',
St='Stampede:BAAALgADCgMJAwAAAA==.Starian:BAABLgAECn8gAAMDAAcJKRztIQAlAgADAAcJKRztIQAlAgAOAAEJywwTfwAzAAAAAA==.Stëlla:BAABLgAECn8rAAIcAAgJfBMeMADZAQAcAAgJfBMeMADZAQAAAA==.',
Su='Suckmyhammer:BAAALgAECgEJAQAAAA==.Sunnara:BAACLgAFFH8OAAIfAAUJkx+yJgBhAQAfAAUJkx+yJgBhAQAuAAQKfyIAAh8ACQnwIYQIAPkCAB8ACQnwIYQIAPkCAAAA.Superkx:BAAALgAECgQJBQAAAA==.Suzanomu:BAAALgADCgYJCwAAAA==.',
Sy='Sylran:BAAALgADCgQJBgAAAA==.Synk:BAAALgADCgQJBAAAAA==.Syofra:BAAALgAECgQJBQAAAA==.Syrelys:BAAALgADCgYJBgAAAA==.Syuon:BAACLgAFFH8GAAIHAAIJ3hpxMgCeAAAHAAIJ3hpxMgCeAAAuAAQKfysAAgcACQkkINEFAC4DAAcACQkkINEFAC4DAAAA.',
['Së']='Sëkhmet:BAAALgAECgYJCwAAAA==.',
['Sï']='Sïmbä:BAABLgAECn8bAAMCAAkJjQ4gZwCEAQACAAkJjQ4gZwCEAQAEAAEJkAShGQAoAAABLgAECggJEgANAAAAAA==.',
['Sÿ']='Sÿkies:BAAALgADCgEJAQAAAA==.',
Ta='Talandar:BAABLgAECn82AAIOAAkJERmgDgBcAgAOAAkJERmgDgBcAgAAAA==.Tankudo:BAABLgAECn8ZAAICAAYJBhawkwArAQACAAYJBhawkwArAQAAAA==.Tannia:BAAALgADCgIJAgAAAA==.Tanthallas:BAAALgAECgEJAQAAAA==.Tavindapedra:BAAALgAECgYJCwAAAA==.',
Tc='Tchutchuco:BAAALgAECgIJAwAAAA==.',
Te='Tekzero:BAAALgAECgEJCAAAAA==.Tempestus:BAAALgADCgYJBgAAAA==.Tennebra:BAAALgADCgYJCAAAAA==.Teobaldo:BAAALgADCgYJCgAAAA==.Terron:BAABLgAECn8tAAMcAAgJBhaHKAABAgAcAAgJBhaHKAABAgAdAAEJFhlYhQBJAAAAAA==.',
Th='Thabitah:BAABLgAECn9AAAIBAAkJAR5vCACvAgABAAkJAR5vCACvAgAAAA==.Thaliath:BAAALgADCgQJBAAAAA==.Thallariel:BAAALgAECgQJBgAAAA==.Theteo:BAABLgAECn8ZAAIGAAkJZQuldQBoAQAGAAkJZQuldQBoAQAAAA==.Thiberios:BAAALgAECgUJDAAAAA==.Thirros:BAAALgADCgUJBQAAAA==.Thorres:BAAALgAECgMJBwAAAA==.Thotamon:BAAALgAECgQJCAAAAA==.Throin:BAAALgAECgMJAwAAAA==.Thràain:BAAALgAECgcJDgAAAA==.Thuki:BAAALgADCgYJDQAAAA==.Thunderblade:BAAALgAECgYJDgAAAA==.Théus:BAAALgAECgMJAwABLgAECgkJFQATAOYdAA==.',
Ti='Tiramisu:BAAALgAECgcJCwAAAA==.',
To='Torâo:BAAALgAECgMJAwAAAA==.Toucinho:BAAALgAECgYJDgAAAA==.',
Tr='Traydd:BAABLgAECn8fAAIPAAgJ7hNIDgCuAQAPAAgJ7hNIDgCuAQAAAA==.Trollando:BAAALgAECgUJCAAAAA==.',
Tu='Tuga:BAAALgADCgMJAwAAAA==.Turokk:BAABLgAECn8bAAIVAAgJTA+RVgCHAQAVAAgJTA+RVgCHAQAAAA==.',
Tw='Twilight:BAAALgADCgYJDQAAAA==.Twylluch:BAAALgADCgQJBgABLgAECgkJKAAQAOsXAA==.',
Ul='Ulhim:BAAALgADCgcJEwAAAA==.',
Ur='Uriuri:BAAALgADCgYJBgABLgAECgkJQwAPAHEhAA==.',
Us='Usfull:BAABLgAECn8zAAMKAAkJ3xA5JQCEAQAKAAgJ/BE5JQCEAQABAAgJawsiLQBOAQAAAA==.',
Va='Vacavelha:BAAALgAECgEJAQAAAA==.Vahtorn:BAAALgAECgMJBgAAAA==.Valaerys:BAAALgAECgUJCgAAAA==.Valaniri:BAAALgADCgEJAQAAAA==.Vallkÿria:BAAALgAECgEJAQAAAA==.Vanheelsen:BAAALgAECgIJAgAAAA==.Vanyathariel:BAAALgADCgYJAwAAAA==.Vareena:BAAALgADCggJCAABLgAECgkJOgASAOMlAA==.Vashiel:BAAALgADCgIJAgAAAA==.',
Ve='Vehuiáh:BAABLgAECn8eAAMQAAgJMB0NGgAeAgAQAAgJMB0NGgAeAgAGAAEJRQTykgElAAAAAA==.Velen:BAABLgAECn8aAAICAAcJshAJhQBEAQACAAcJshAJhQBEAQAAAA==.Vellkor:BAAALgADCgYJBgAAAA==.Vellon:BAAALgADCgEJAQAAAA==.Venrique:BAAALgAECgMJAwABLgAECgYJDAANAAAAAA==.Venusa:BAAALgADCgMJBAAAAA==.Verno:BAAALgADCgcJCwAAAA==.Verzuk:BAABLgAECn8cAAICAAgJPQpffABVAQACAAgJPQpffABVAQAAAA==.',
Vi='Vidnands:BAAALgAECgEJAQAAAA==.Viinyy:BAAALgAECgMJAwAAAA==.Vilthor:BAAALgAECgUJBQAAAA==.Vintekilo:BAABLgAECn8YAAIGAAkJzRaiYgC9AQAGAAkJzRaiYgC9AQAAAA==.',
Vo='Voiddh:BAAALgAECgcJDAAAAA==.Vokeshar:BAAALgADCgUJBQAAAA==.Voltadupla:BAAALgAECgQJBQAAAA==.Voop:BAAALgADCgYJFAAAAA==.',
Vr='Vrenshrrgn:BAAALgADCgYJBgAAAA==.',
Vy='Vygh:BAACLgAFFH8JAAITAAMJmBVLYwDjAAATAAMJmBVLYwDjAAAuAAQKfy0AAxMACQm5Ib0LAOQCABMACQm5Ib0LAOQCABQAAQkjDzpwADYAAAAA.Vyndrill:BAAALgAECgYJDgAAAA==.',
['Vä']='Välion:BAAALgADCgIJAgAAAA==.',
Wa='Wacom:BAAALgADCgUJBQAAAA==.Walkers:BAAALgAECgUJBQAAAA==.Warlaka:BAAALgAECgQJBgAAAA==.Warpiel:BAAALgADCgcJDAABLgAECgkJHgAZAC0OAA==.Watchtower:BAAALgAECgQJBAAAAA==.',
Wh='Wheez:BAAALgAECgQJBAABLgAECgkJNAARAJ0bAA==.',
Wi='Williem:BAAALgADCgYJEwAAAA==.',
Wo='Worthy:BAAALgADCgQJBAAAAA==.',
['Wä']='Wätanabe:BAAALgAECgQJBAAAAA==.',
Xa='Xafado:BAAALgAECgEJAQAAAA==.Xamalandrö:BAAALgAECgQJCwAAAA==.',
Xe='Xeal:BAAALgADCgEJAQAAAA==.Xehagus:BAAALgADCgcJCgAAAA==.',
Xi='Xiblaublum:BAAALgADCgMJAwAAAA==.Xinhagoo:BAAALgAECgMJAwAAAA==.Xiquimiro:BAAALgADCgQJBAAAAA==.',
Xx='Xximperadorx:BAAALgADCgIJAgAAAA==.',
Ya='Yasuoh:BAAALgAECgQJCAAAAA==.',
Ye='Yewner:BAAALgADCgYJBQAAAA==.',
Yi='Yingsu:BAABLgAECn8ZAAIWAAkJeCIHDQBTAgAWAAkJeCIHDQBTAgAAAA==.',
Yo='Yoshihime:BAAALgAECgIJAgABLgAECgkJHgADAJkXAA==.',
Yv='Yvin:BAAALgAECgMJBAAAAA==.',
Za='Zallmo:BAABLgAECn8aAAIaAAgJrhDnKQCbAQAaAAgJrhDnKQCbAQAAAA==.Zarath:BAAALgAECgUJBgAAAA==.Zawarudo:BAAALgAECgQJCAAAAA==.',
Ze='Zedd:BAAALgAFFAIJAgAAAA==.Zenorclord:BAAALgADCgQJBgAAAA==.Zeytona:BAABLgAECn8jAAIWAAkJjAtUIwB+AQAWAAkJjAtUIwB+AQAAAA==.',
Zi='Ziracruz:BAAALgAECgQJCwAAAA==.',
['Zí']='Zíngara:BAAALgAECgEJAQAAAA==.',
['Ár']='Árÿä:BAABLgAECn9DAAIVAAkJSxVSKgAeAgAVAAkJSxVSKgAeAgAAAA==.',
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
