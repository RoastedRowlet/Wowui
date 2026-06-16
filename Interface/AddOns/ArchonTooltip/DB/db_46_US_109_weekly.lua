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
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abelao:BAAALgAECgcJEwAAAA==.',
Ad='Adelaide:BAAALgAECgIJAgABLgAFFAcJGgABALAaAA==.Adoramuss:BAAALgAECgYJCwAAAA==.Adrianoj:BAAALgAECgEJAQAAAA==.',
Ae='Aeklug:BAAALgADCgcJCAAAAA==.Aelon:BAAALgADCgUJBQAAAA==.Aelthor:BAAALgAECgQJEAAAAA==.Aemeath:BAABLgAECn8XAAMCAAkJiyHOAQD9AgACAAkJiyHOAQD9AgADAAIJnhioSACOAAAAAA==.',
Ah='Ahammes:BAAALgAECgQJBAABLgAECgcJHwAEAIAJAA==.Ahmus:BAAALgAECgUJDAAAAA==.Ahrallu:BAAALgADCgEJAgAAAA==.',
Ai='Aioliavictus:BAAALgADCgIJAgAAAA==.',
Al='Alanie:BAAALgAECgUJDQABLgAECggJIwAFABUeAA==.Aldranir:BAAALgADCgEJAQAAAA==.Alessaxd:BAACLgAFFH8HAAIEAAIJ/Q34yACVAAAEAAIJ/Q34yACVAAAuAAQKfykAAwQACQmhFbU5ABcCAAQACQmhFbU5ABcCAAYABwnKD+USAEcBAAAA.Alexa:BAAALgAECgQJBAAAAA==.Alfajhor:BAABLgAECn86AAMHAAgJFx9zEAC5AQAHAAYJoyJzEAC5AQAIAAgJZx3GYACtAQAAAA==.Alfajhòr:BAAALgAECgIJAgAAAA==.Alfajhôr:BAAALgAECgUJBwAAAA==.Alkarin:BAAALgAECgEJAwAAAA==.Allandriel:BAAALgAECgUJBQAAAA==.Alldarion:BAAALgAECgMJCQAAAA==.Allendra:BAAALgADCgcJCQAAAA==.Alleriane:BAACLgAFFH8GAAIJAAIJOhdxRQCDAAAJAAIJOhdxRQCDAAAuAAQKfzwAAwkACQlEH4cIABADAAkACQlEH4cIABADAAoAAQmnApGNABgAAAAA.Allerios:BAAALgAECgUJCQAAAA==.Allone:BAABLgAECn8fAAIDAAcJ/BHJLAAWAQADAAcJ/BHJLAAWAQAAAA==.Allyhra:BAAALgADCgQJBAAAAA==.Allëria:BAAALgADCgMJAwAAAA==.Alruna:BAAALgAECgEJAQAAAA==.',
Am='Ametnys:BAAALgAECgQJCAAAAA==.Amonhar:BAAALgAECgQJBQABLgAECgkJOwALAB4SAA==.Amyn:BAAALgADCgYJBwAAAA==.',
An='Anakata:BAABLgAECn8bAAQMAAYJ3RVqKwD9AAAMAAYJ3RVqKwD9AAAFAAIJ+wWPzwAzAAANAAEJww+YiwAyAAAAAA==.Anakinini:BAABLgAECn8cAAIOAAgJngjwRAATAQAOAAgJngjwRAATAQABLgAECgYJBwAPAAAAAA==.Analia:BAABLgAECn8jAAQFAAgJFR5/HgBLAgAFAAcJVR1/HgBLAgAMAAgJnQiZNgDHAAANAAMJQBzLXACeAAAAAA==.Andaliz:BAACLgAFFH8SAAIIAAMJwSYGLgBRAQAIAAMJwSYGLgBRAQAuAAQKfzYAAggACQkLJv0CAGgDAAgACQkLJv0CAGgDAAEuAAUUBQkGAAgAWhcA.Andorith:BAAALgAECgEJAgAAAA==.Anelie:BAAALgAECgQJDQABLgAECggJIwAFABUeAA==.Annhe:BAAALgAECgEJAQAAAA==.Ansalon:BAAALgADCgYJBwAAAA==.Anthorus:BAAALgAECgIJAgAAAA==.Antonellaes:BAAALgAECgUJCgABLgAECgcJDgAPAAAAAA==.Anturio:BAAALgAECgQJBwAAAA==.',
Ao='Aoiisuu:BAAALgADCgYJCAAAAA==.',
Ap='Apodrecido:BAAALgAECgYJBgAAAA==.',
Ar='Arajakata:BAAALgAECgEJAwAAAA==.Arctorius:BAABLgAECn8UAAIIAAcJeQsYpQAtAQAIAAcJeQsYpQAtAQAAAA==.Arethiel:BAAALgADCgYJBgAAAA==.Arlandriah:BAAALgADCgYJCQABLgAECgYJGAAIABAYAA==.Artronis:BAACLgAFFH8JAAIMAAQJCws6GgC1AAAMAAQJCws6GgC1AAAuAAQKfyYAAwwACAlPFpQUAKwBAAwACAlPFpQUAKwBABAAAQk9FOhLADwAAAAA.Artånis:BAAALgAECgcJDAAAAA==.Arukäi:BAAALgADCgYJBgAAAA==.Aruthuro:BAAALgAECgYJDwAAAA==.',
As='Ashbörn:BAAALgAECgQJBwAAAA==.Astel:BAABLgAECn8dAAIRAAkJlBJgNQDtAQARAAkJlBJgNQDtAQAAAA==.',
At='Atriuz:BAABLgAECn8bAAISAAYJahouLwDGAQASAAYJahouLwDGAQAAAA==.Ats:BAAALgAECgMJBQAAAA==.',
Ay='Aykho:BAABLgAECn8nAAITAAgJRRaVZgCsAQATAAgJRRaVZgCsAQAAAA==.',
Az='Azurion:BAAALgAECgYJCgAAAA==.',
['Aÿ']='Aÿ:BAAALgAECgMJBAAAAA==.',
Ba='Baguh:BAAALgADCggJCAAAAA==.Bagunça:BAAALgADCgYJBgAAAA==.Bakuugou:BAAALgAECgMJCgAAAA==.Balk:BAAALgAECgQJBAAAAA==.Balthar:BAAALgAECgEJAQAAAA==.Bambur:BAAALgADCgMJAwAAAA==.Barbabruto:BAABLgAECn8+AAIUAAkJZx5NBwCNAgAUAAkJZx5NBwCNAgAAAA==.Basilisco:BAAALgAECgEJAQAAAA==.',
Be='Belleg:BAAALgAECgEJAgAAAA==.Beronhuz:BAAALgAECgMJAwAAAA==.',
Bf='Bf:BAAALgAECgEJAgAAAA==.',
Bi='Biafalcão:BAAALgAECgEJAQAAAA==.Bijanca:BAAALgAECgYJBgAAAA==.Birthdäy:BAAALgADCgEJAQAAAA==.Bisponegro:BAAALgAECgQJCwABLgABCgcJFQAPAAAAAA==.Biønic:BAAALgAECgMJCQAAAA==.',
Bl='Blackline:BAABLgAECn8iAAIEAAgJVhPcXwCnAQAEAAgJVhPcXwCnAQAAAA==.',
Bo='Boipretim:BAAALgAECgYJDwAAAA==.Bontorius:BAAALgADCgEJAgAAAA==.Bordello:BAAALgADCgUJBQAAAA==.',
Br='Bradio:BAAALgADCggJCAAAAA==.Brahman:BAAALgAECgEJBAAAAA==.Bratloko:BAAALgAECgUJBQAAAA==.Bromos:BAAALgAECgQJCAAAAA==.Brutalhoof:BAAALgAECgQJBAAAAA==.Brönsted:BAAALgADCgMJAwAAAA==.',
Bu='Bubbalo:BAAALgADCgUJBQAAAA==.Bullsman:BAAALgADCgQJBAAAAA==.Buzzumaaky:BAABLgAECn8YAAITAAgJTxepiQC/AQATAAgJTxepiQC/AQAAAA==.',
By='Byakura:BAAALgADCggJCwAAAA==.',
['Bü']='Büdweiser:BAAALgAECgcJEAAAAA==.',
Ca='Cabernet:BAAALgAECgUJBwAAAA==.Cabeçaquente:BAAALgAECgcJCQAAAA==.Cabinking:BAAALgAECgIJAgAAAA==.Calanthe:BAAALgADCgkJCQAAAA==.Calhistra:BAABLgAECn8nAAMVAAgJQxntSwC2AQAVAAgJQxntSwC2AQAWAAIJRQokVQBvAAAAAA==.Calteryeker:BAAALgAECgYJEQAAAA==.Camillas:BAAALgAECggJDwAAAA==.Caosenvy:BAAALgAECgEJAQAAAA==.Caralh:BAAALgAECgEJAgAAAA==.Caroll:BAAALgAECgIJAgAAAA==.Castaldi:BAAALgAECgEJAgABLgAECgcJCwAPAAAAAA==.Cathe:BAABLgAECn8aAAIXAAYJ6R0JXwCFAQAXAAYJ6R0JXwCFAQAAAA==.',
Ce='Cecilith:BAAALgAECgYJCAAAAA==.Cernûnnos:BAACLgAFFH8FAAIFAAIJPRGjUQB3AAAFAAIJPRGjUQB3AAAuAAQKfxUAAgUABglOD9RcAB4BAAUABglOD9RcAB4BAAAA.',
Ch='Champdude:BAABLgAECn9PAAQKAAkJqiPBAwAgAwAKAAkJqiPBAwAgAwAYAAgJJxtAEQAuAgAJAAMJjR6BWAAHAQAAAA==.Chankowkwai:BAAALgAECgYJCQAAAA==.Chanë:BAAALgADCgIJAwAAAA==.Chaosangel:BAAALgAECgUJBwABLgAFFAMJCgANAMYHAA==.Chewi:BAAALgAECgQJBwAAAA==.Chrnnos:BAAALgAECgEJAQAAAA==.',
Ci='Citra:BAAALgAECgMJBwAAAA==.',
Co='Coconolose:BAAALgAECgIJBgAAAA==.Cod:BAAALgAECgIJAwAAAA==.Codecks:BAAALgADCgYJBgAAAA==.Coldbringer:BAAALgAECgEJAQAAAA==.Coldhearths:BAAALgAECgUJBgAAAA==.Couro:BAAALgAECgYJCQAAAA==.Cowçadora:BAAALgADCgIJAQAAAA==.',
Cr='Criminøsa:BAAALgAECgcJCQAAAA==.Cristcalad:BAABLgAECn9AAAMZAAkJfxiMCQBSAgAZAAkJfxiMCQBSAgAUAAEJYQULTwAfAAAAAA==.Cryomanta:BAAALgAECgUJBQAAAA==.',
Cu='Cunhaovirado:BAAALgAECgYJDAABLgAFFAYJEQAKAOEXAA==.Cunhazinha:BAAALgAECgQJBAAAAA==.Cupyncha:BAAALgADCgcJBwAAAA==.Cutia:BAAALgADCgEJAQAAAA==.Cutiesissy:BAAALgAECgQJCAABLgAECgcJGgAIAEoQAA==.',
['Cø']='Cøøkye:BAAALgAECgQJBQAAAA==.',
Da='Daellus:BAAALgADCgUJBQAAAA==.Daemi:BAAALgAECgIJBAAAAA==.Daibodan:BAAALgAECgEJBAAAAA==.Dalaty:BAAALgAECgUJBQAAAA==.Daniilos:BAAALgAFFAEJAQAAAA==.Daresh:BAAALgADCgIJAgAAAA==.Darklara:BAABLgAECn8lAAICAAkJBRnvCADeAQACAAkJBRnvCADeAQAAAA==.Darkove:BAABLgAECn8uAAITAAkJjBK9UgDhAQATAAkJjBK9UgDhAQAAAA==.Darrow:BAACLgAFFH8SAAMEAAQJUh0nRgBiAQAEAAQJ+BsnRgBiAQAGAAMJdxydEAAIAQAuAAQKfy8AAwQACQnPJJsPAO4CAAQACQn0I5sPAO4CAAYACAn8IkEDALYCAAAA.Dartibeccoso:BAAALgADCgcJBwAAAA==.Daviberger:BAAALgAECgMJAwAAAA==.',
De='Deany:BAAALgAECgEJAgAAAA==.Deathinhu:BAABLgAECn9XAAITAAkJox/iEgDmAgATAAkJox/iEgDmAgAAAA==.Deathnacht:BAAALgAECgQJBwAAAA==.Delset:BAAALgADCgIJAgAAAA==.Demojoca:BAAALgAECgIJAgABLgAECgcJDgAPAAAAAA==.Dentepodre:BAAALgADCgEJAQAAAA==.Dervus:BAAALgADCgcJBwAAAA==.Dethroned:BAAALgAECgUJDAAAAA==.Devrath:BAAALgAECgEJAQAAAA==.Devyogi:BAAALgADCgcJCAAAAA==.',
Di='Diefs:BAAALgAECgEJAQAAAA==.Dimeros:BAABLgAECn81AAINAAkJexDZIAC+AQANAAkJexDZIAC+AQAAAA==.Dito:BAAALgADCgEJAQAAAA==.Divano:BAACLgAFFH8MAAIBAAMJNBAEJgDDAAABAAMJNBAEJgDDAAAuAAQKfzAAAwEACAnJHzsNAH8CAAEACAnJHzsNAH8CABoAAwkCCaVdAIIAAAAA.',
Dk='Dkats:BAAALgAECgEJAgAAAA==.',
Dn='Dng:BAAALgAECgcJCAAAAA==.',
Do='Dogowner:BAAALgAECgkJEgAAAA==.Donora:BAABLgAECn8sAAQIAAkJFRM/UgDQAQAIAAkJFRM/UgDQAQASAAEJfwOikAAsAAAHAAEJKAaWWwAVAAAAAA==.',
Dr='Drackmontana:BAABLgAECn8lAAMbAAgJaA4gNgDQAQAbAAgJEg4gNgDQAQAUAAIJEhVBPQBjAAAAAA==.Drafael:BAAALgADCggJDgABLgAECgkJVAAQAOQhAA==.Dragoniron:BAAALgADCgEJAQAAAA==.Dragony:BAAALgAECgEJBAAAAA==.Dragunass:BAABLgAECn84AAMbAAkJjx2wDwB7AgAbAAkJjx2wDwB7AgAUAAcJPBrfEwCuAQAAAA==.Dragøndeath:BAAALgADCgEJAgAAAA==.Drakars:BAAALgADCgUJBAAAAA==.Dranarus:BAAALgADCgQJBAAAAA==.Drexus:BAAALgAECgQJBAAAAA==.Druidblack:BAAALgAECgIJAwAAAA==.Drunkler:BAAALgAECgYJBgAAAA==.Dryter:BAABLgAECn8VAAIKAAcJEA9QKwCEAQAKAAcJEA9QKwCEAQAAAA==.Drákon:BAAALgADCgUJBgAAAA==.',
Du='Dubhe:BAAALgAECgUJEAAAAA==.',
Dy='Dysttopia:BAAALgADCgcJCAAAAA==.',
El='Eldryrin:BAAALgAECgEJAQAAAA==.Elendile:BAAALgAECgEJAQAAAA==.Elinius:BAABLgAECn8vAAMNAAkJzSCkCADHAgANAAkJzSCkCADHAgAFAAIJUwz71QAtAAAAAA==.Elistraee:BAAALgAECgEJAQAAAA==.Ellandria:BAAALgAECgMJAwAAAA==.Ellonara:BAAALgAECgEJAQAAAA==.Eloren:BAAALgAECgYJCwABLgAECggJIAASAPERAA==.Eluuria:BAAALgAFFAEJAQAAAA==.Elyzia:BAAALgAECgEJAQAAAA==.',
En='Endorena:BAAALgADCgEJAQAAAA==.',
Ep='Ephesus:BAAALgADCgIJAgAAAA==.',
Er='Erikssen:BAAALgADCgYJBgAAAA==.Ernest:BAABLgAECn9MAAIFAAkJOR9lCAAwAwAFAAkJOR9lCAAwAwAAAA==.Erynneus:BAAALgADCgMJAwAAAA==.',
Es='Estagiario:BAAALgAECgQJBgABLgAFFAIJBQADAMMYAA==.',
Eu='Eusouobatman:BAAALgADCgIJAgAAAA==.',
Ev='Evetts:BAAALgADCgEJAQAAAA==.Evilbarba:BAABLgAFFH8FAAIIAAIJNBAYiwCTAAAIAAIJNBAYiwCTAAAAAA==.',
Ex='Exort:BAABLgAECn8cAAITAAYJFhV3mQBDAQATAAYJFhV3mQBDAQAAAA==.Exothus:BAAALgAECgEJAQAAAA==.Expressão:BAAALgADCgYJCwAAAA==.Exødus:BAAALgAECgEJAQAAAA==.',
Fa='Faeldar:BAACLgAFFH8JAAIaAAMJlAzsMgC6AAAaAAMJlAzsMgC6AAAuAAQKf0AAAhoACQnbEtUWAB0CABoACQnbEtUWAB0CAAAA.Faldark:BAAALgAECgYJDgAAAA==.Fandrall:BAAALgAECgUJCAAAAA==.Faris:BAABLgAFFH8IAAIcAAIJ2xJuLwChAAAcAAIJ2xJuLwChAAAAAA==.Farmfarm:BAAALgADCgEJAQAAAA==.Faver:BAAALgAECgQJBQAAAA==.Faölin:BAABLgAECn8nAAIcAAcJ1hwYGQDOAQAcAAcJ1hwYGQDOAQAAAA==.',
Fe='Feenigan:BAAALgAECgEJAQABLgAECgQJBAAPAAAAAA==.Feeniä:BAAALgAECgQJBAAAAA==.Ferael:BAABLgAECn84AAIIAAkJTCJBDwDpAgAIAAkJTCJBDwDpAgAAAA==.',
Fi='Fil:BAAALgAECgEJAQAAAA==.Firstomega:BAAALgADCgMJAwAAAA==.',
Fl='Flavors:BAACLgAFFH8GAAIbAAMJzyQfHwAxAQAbAAMJzyQfHwAxAQAuAAQKfyMAAxsACQndI60HAOMCABsACQndI60HAOMCABkABAkhHgIUAGYBAAAA.Florbela:BAAALgAECgUJCQAAAA==.Flämbë:BAAALgADCgEJAQAAAA==.',
Fo='Fogue:BAAALgAECgkJEgAAAA==.Foxthamy:BAABLgAECn8mAAIJAAcJaxJzOwB7AQAJAAcJaxJzOwB7AQAAAA==.',
Fr='Frachlitzz:BAACLgAFFH8IAAITAAMJ9Q30ggDZAAATAAMJ9Q30ggDZAAAuAAQKfzsAAhMACQmBFU4/ABwCABMACQmBFU4/ABwCAAAA.Fradem:BAAALgAECgcJDQAAAA==.Freccianera:BAAALgADCgEJAQAAAA==.Fredericc:BAABLgAECn8bAAMdAAkJCg/fRgCOAQAdAAgJwQ3fRgCOAQAeAAcJ2gVYWQDfAAAAAA==.Fredinho:BAAALgAECgEJAQAAAA==.Freecs:BAAALgAECgYJBwABLgAECgcJCwAPAAAAAA==.Freyá:BAABLgAECn8jAAIIAAkJcCHzEwDJAgAIAAkJcCHzEwDJAgAAAA==.Frostgore:BAAALgAECgEJAQAAAA==.Froststriker:BAAALgAECgEJAQAAAA==.Frs:BAAALgAECgEJAgAAAA==.',
Ga='Galhuda:BAAALgADCgYJCQAAAA==.Galyan:BAAALgADCgEJAQAAAA==.Gandalpha:BAAALgAECgUJBQAAAA==.Gandwelf:BAAALgADCgkJCQAAAA==.Gazieri:BAABLgAECn8gAAMSAAgJ8RFkRQBiAQASAAgJ8RFkRQBiAQAIAAQJCw/z2gDWAAAAAA==.',
Ge='Geisty:BAAALgAECgMJAwABLgAECgcJHwAEAIAJAA==.',
Gh='Ghalladriel:BAAALgADCgEJAwAAAA==.Ghruka:BAAALgAECgQJBAAAAA==.',
Gi='Giafar:BAAALgAECgEJAQABLgAECgYJBwAPAAAAAA==.',
Gl='Gluke:BAAALgAECgMJAwAAAA==.Glutotwo:BAAALgADCgQJBgAAAA==.',
Gn='Gnomari:BAABLgAECn8jAAIVAAgJFwJa4gCVAAAVAAgJFwJa4gCVAAAAAA==.',
Go='Goratrix:BAAALgAECgUJBQABLgAECgcJHwAEAIAJAA==.Gordanado:BAAALgAECgEJAgAAAA==.Gordruida:BAAALgAECgEJAQAAAA==.Govers:BAAALgADCgMJAwABLgAECgMJBAAPAAAAAA==.',
Gr='Grandecoisa:BAAALgAECgEJAQAAAA==.Greyfin:BAAALgAECgEJAgAAAA==.Greyvor:BAAALgADCgEJAQAAAA==.Grimch:BAAALgAECgEJAQAAAA==.Grumax:BAABLgAECn8UAAIIAAgJyQ/FdACRAQAIAAgJyQ/FdACRAQAAAA==.Grymysa:BAAALgAECgIJAgAAAA==.Grössa:BAABLgAECn8YAAMSAAcJIwiGWwAOAQASAAcJIwiGWwAOAQAIAAMJCQQUfgE6AAABLgAECgkJFwAVAJ8IAA==.',
Gu='Guitianki:BAAALgAECgEJAQAAAA==.Gulek:BAAALgAECgMJAwAAAA==.Gussg:BAABLgAECn8XAAQVAAkJnwgKZQBzAQAVAAkJnwgKZQBzAQAfAAEJzwhuQQArAAAWAAIJGQSURQAeAAAAAA==.Gustavonz:BAAALgADCgcJBwAAAA==.',
['Gö']='Göhan:BAAALgADCgUJBQABLgAECgYJEwAPAAAAAA==.',
['Gø']='Gøvers:BAAALgAECgMJBAAAAA==.',
Ha='Hakuouki:BAAALgAECgMJAwAAAA==.Handyman:BAAALgADCgYJCgAAAA==.Hantom:BAAALgADCgYJBgABLgAFFAYJEQAKAOEXAA==.',
He='Hefestion:BAAALgAFFAEJAQAAAA==.Helsingdarck:BAAALgADCgIJAgAAAA==.Hendrikison:BAAALgAECgYJCAAAAA==.',
Hi='Hildegyth:BAABLgAECn8fAAMKAAgJWBE1MQBhAQAKAAcJWRE1MQBhAQAJAAUJZxFdWQAFAQAAAA==.',
Hj='Hjalmar:BAAALgADCgcJCQAAAA==.',
Ho='Hodtiva:BAABLgAECn8tAAMBAAgJdBA+LQBtAQABAAgJdBA+LQBtAQALAAUJDA41TQCpAAAAAA==.Homerz:BAAALgADCgEJAQAAAA==.Horagalles:BAAALgAECgEJAQAAAA==.Hotmojo:BAABLgAECn8eAAITAAgJOw/idwCGAQATAAgJOw/idwCGAQABLgAFFAUJDwAeAE0cAA==.',
Hr='Hrafnn:BAAALgADCgQJBAAAAA==.',
Hu='Hunfox:BAACLgAFFH8VAAIXAAMJUR9pCwAHAQAXAAMJUR9pCwAHAQAuAAQKf0QAAhcACQmuI1MJAAsDABcACQmuI1MJAAsDAAAA.',
['Hä']='Härkness:BAAALgAECgYJCAAAAA==.',
['Hø']='Høolligans:BAAALgAECgEJAQAAAA==.',
['Hü']='Hüskar:BAABLgAECn8fAAMbAAkJ/AsaMACMAQAbAAkJuQsaMACMAQAZAAEJCg9FeQAtAAAAAA==.',
Ic='Icechips:BAAALgADCgUJBQAAAA==.Ichigoz:BAABLgAECn8iAAITAAkJBQrocACVAQATAAkJBQrocACVAQAAAA==.',
Ih='Ihntwuaed:BAAALgADCgYJCQAAAA==.',
Ik='Ikoo:BAABLgAECn9NAAIaAAkJLiDPBABBAwAaAAkJLiDPBABBAwAAAA==.',
Il='Illaril:BAACLgAFFH8lAAICAAYJ7xyCAQC4AQACAAYJ7xyCAQC4AQAuAAQKf2MAAgIACQmMIWQCANcCAAIACQmMIWQCANcCAAAA.',
In='Indarion:BAAALgADCgYJEQAAAA==.Ingratt:BAAALgAECgEJAgAAAA==.Invisiblelol:BAAALgAECgIJAgAAAA==.',
Ir='Irmãodouther:BAAALgAFFAIJAgAAAA==.',
Is='Isebby:BAAALgADCgMJAwAAAA==.Ishtarie:BAAALgAECgQJBQABLgAECgkJHgAFAJkXAA==.',
It='Itzzdan:BAAALgADCgMJAwAAAA==.',
Iv='Ivina:BAABLgAECn8UAAMVAAgJThbwkQA1AQAVAAcJThbwkQA1AQAfAAIJqRe4HACNAAAAAA==.',
Iz='Izaar:BAAALgAECgQJDgAAAA==.',
Ja='Jacsonnaik:BAAALgAECgQJBQAAAA==.Jadelina:BAAALgAECgEJAQAAAA==.Janaìna:BAAALgAECgMJAwAAAA==.Jangeoffry:BAAALgADCgEJAQAAAA==.',
Jh='Jhonatinha:BAABLgAECn8VAAMIAAcJBxkq2wDhAAAIAAYJaxkq2wDhAAASAAQJng69dgCfAAAAAA==.',
Ji='Jigsaww:BAAALgAECgQJCAAAAA==.',
Jk='Jks:BAAALgAECgEJAQAAAA==.',
Jo='Joaquim:BAAALgAECgIJAgAAAA==.Jogaveiopl:BAAALgADCgIJAgAAAA==.Johnlobo:BAAALgAECgEJAQAAAA==.Joventino:BAAALgADCgQJBQAAAA==.',
Ju='Jucah:BAABLgAECn8ZAAIeAAkJZAtGOgBJAQAeAAkJZAtGOgBJAQAAAA==.Julabolseiro:BAABLgAECn8VAAMLAAgJegzMLABgAQALAAgJegzMLABgAQABAAIJBgIVhgAxAAAAAA==.Julinhas:BAAALgADCgUJBQAAAA==.Jullianxd:BAAALgADCgYJCAABLgAECgkJFgARAOwPAA==.',
Ka='Kaallew:BAABLgAECn8ZAAIHAAkJuRfOFwBdAQAHAAkJuRfOFwBdAQAAAA==.Kaezar:BAAALgADCgEJAQAAAA==.Kainer:BAAALgAECgQJBQAAAA==.Kalazshar:BAABLgAECn8mAAIMAAkJbBKjFQCiAQAMAAkJbBKjFQCiAQAAAA==.Kalelzinho:BAAALgADCgYJCAAAAA==.Kaluss:BAAALgAECgcJEQAAAA==.Kanalet:BAAALgAECgYJCAAAAA==.Kantaa:BAAALgAECgQJCwAAAA==.Kanturu:BAAALgAECgQJBAAAAA==.Kanzaki:BAAALgADCgcJBwABLgAECgkJTwAKAKojAA==.Karonn:BAABLgAECn8UAAIIAAYJ/A3mlABTAQAIAAYJ/A3mlABTAQAAAA==.Kavartu:BAAALgAECgYJDAAAAA==.Kaymon:BAAALgAECgEJAQAAAA==.',
Ke='Keillor:BAABLgAECn8pAAMdAAgJGRaBRACXAQAdAAcJWRSBRACXAQAeAAYJXRqsLgCDAQAAAA==.Kelantir:BAAALgAECgYJCQABLgAECgkJDAAPAAAAAA==.Keldorian:BAAALgADCgcJEAAAAA==.Kelishe:BAAALgAECgUJBQAAAA==.Kelliar:BAAALgAECgIJAQAAAA==.Kelorn:BAAALgADCgYJBgABLgAECgcJCgAPAAAAAA==.Kelysa:BAAALgADCgkJDgABLgAECggJPQAUACYdAA==.Kenzou:BAABLgAECn8YAAMYAAcJ0hi0MAA9AQAYAAUJexy0MAA9AQAKAAcJSQ+xNwAgAQAAAA==.',
Kh='Khadi:BAAALgAECgcJCwAAAA==.Khaeltaz:BAAALgAECgMJAwAAAA==.Khalandra:BAABLgAECn8eAAIbAAkJaBtyKwAIAgAbAAkJaBtyKwAIAgAAAA==.Khalel:BAAALgADCgEJAgAAAA==.Khaliq:BAABLgAECn8eAAMDAAkJVxUMFADvAQADAAkJVxUMFADvAQARAAQJLApxrwCtAAAAAA==.Khallani:BAABLgAECn8fAAIEAAcJgAlLlQBWAQAEAAcJgAlLlQBWAQAAAA==.Khamul:BAAALgAECgQJBgAAAA==.Khaos:BAAALgAECggJEwAAAA==.Khisto:BAABLgAECn80AAMTAAkJnRsfOAA1AgATAAkJnRsfOAA1AgAgAAcJ3RfXBACSAQAAAA==.Khroriggs:BAAALgAECgYJDQABLgAECgcJBwAPAAAAAA==.',
Ki='Kieran:BAAALgAECgMJAwAAAA==.Killerbiie:BAAALgADCgIJAgAAAA==.Killerdown:BAAALgADCgIJAgAAAA==.Kimashi:BAAALgAECgUJBQAAAA==.Kindie:BAAALgADCgcJCwABLgAECggJFAARABEIAA==.Kissme:BAACLgAFFH8FAAMNAAMJ2Ak1QABuAAANAAIJdwg1QABuAAAMAAEJmww0PgAsAAAuAAQKfx4AAw0ACQmYEK8sAG4BAA0ACAneEa8sAG4BAAwABAmICCVFAI0AAAAA.Kitamor:BAABLgAECn9LAAINAAkJ2A1LKACLAQANAAkJ2A1LKACLAQAAAA==.Kiya:BAAALgADCgcJHgAAAA==.',
Kl='Klorokina:BAAALgAECgYJBgAAAA==.',
Ko='Kooraqt:BAAALgAECgQJBAAAAA==.Koriakin:BAABLgAECn8vAAMXAAkJIR01EADLAgAXAAkJIR01EADLAgAhAAcJBxh2GQDUAQAAAA==.Kosmo:BAAALgAECgcJCQAAAA==.Kotalkhan:BAAALgADCgkJEQAAAA==.',
Kr='Krosmu:BAAALgADCgcJBwAAAA==.Krov:BAAALgAECgEJAQAAAA==.Kryon:BAAALgAECgYJDgAAAA==.Kryzthor:BAAALgAECgYJCAAAAA==.Kräsus:BAABLgAECn9DAAIUAAkJAibgAABiAwAUAAkJAibgAABiAwAAAA==.Krønna:BAAALgAECgQJBAABLgAECgYJKQAiAEsIAA==.',
Ku='Kul:BAAALgAECgUJBgAAAA==.Kuthila:BAAALgADCgIJAgAAAA==.',
Ky='Kyzaru:BAAALgAECgIJAgAAAA==.',
['Kÿ']='Kÿdou:BAAALgAECgcJDgAAAA==.',
La='Ladrion:BAABLgAECn9WAAQjAAkJtR98AQDgAgAjAAkJvB58AQDgAgAcAAkJAxmFFABuAgAkAAkJ9RfYBAA6AgAAAA==.Laetus:BAABLgAECn8ZAAIlAAYJhBhWBgBbAQAlAAYJhBhWBgBbAQAAAA==.Lagosta:BAAALgAECgMJBgAAAA==.Laiany:BAABLgAECn9MAAILAAkJJSL5AwBGAwALAAkJJSL5AwBGAwAAAA==.Lani:BAAALgAECgEJAQAAAA==.',
Le='Legacia:BAAALgADCgYJBgAAAA==.Lekrom:BAAALgADCgYJBgAAAA==.Leodoros:BAAALgAECgQJBAAAAA==.Lequinhö:BAAALgAECgIJAgAAAA==.Leric:BAAALgADCgcJCgAAAA==.Lethmar:BAABLgAECn8eAAIVAAcJMxemWwCKAQAVAAcJMxemWwCKAQAAAA==.Levanah:BAAALgAFFAIJAgAAAA==.Leyana:BAAALgAECgUJBwAAAA==.',
Lh='Lhwei:BAAALgAECgIJAgABLgAFFAQJDAAJAHwWAA==.',
Li='Liandra:BAAALgAECgEJAQAAAA==.Licaon:BAAALgADCgYJDgAAAA==.Lichkiller:BAAALgAECgUJBQAAAA==.Lightbreaker:BAABLgAECn8jAAIIAAkJZAhohgBgAQAIAAkJZAhohgBgAQAAAA==.Lihr:BAAALgADCgYJCQAAAA==.Lilianpotter:BAAALgAECgEJAQAAAA==.Lilithrix:BAAALgADCgIJAgAAAA==.Lillit:BAABLgAECn9AAAQfAAkJ1A64DQB7AQAVAAkJmwwuUQCnAQAfAAgJ9w24DQB7AQAWAAIJvwYIPAA3AAAAAA==.Lindaah:BAABLgAECn8wAAMKAAgJHBl3FwD1AQAKAAgJHBl3FwD1AQAJAAYJJwlHbQDGAAAAAA==.Lindademon:BAAALgAECgUJDwAAAA==.Lindahealer:BAAALgAECgUJCgABLgAECgUJDwAPAAAAAA==.Lislfox:BAABLgAECn9AAAIMAAkJbBqhCABfAgAMAAkJbBqhCABfAgAAAA==.Lithlad:BAAALgADCgIJAgAAAA==.',
Lk='Lkinho:BAAALgAECgMJBAAAAA==.',
Lm='Lmmds:BAAALgAECgUJCwAAAA==.',
Lo='Lockynha:BAAALgADCgEJAQAAAA==.Loohynir:BAABLgAFFH8FAAIFAAIJFQmEWgBiAAAFAAIJFQmEWgBiAAAAAA==.Lotusbird:BAAALgADCgcJBwAAAA==.',
Lu='Lucario:BAAALgAECgEJAgAAAA==.Luccoa:BAAALgAECgkJCgABLgAECgkJQwAUAAImAA==.Luccyah:BAAALgADCgkJDgAAAA==.Lucifïr:BAAALgAECgEJAQAAAA==.Lucileia:BAAALgAECgQJBQAAAA==.Lukazgplay:BAAALgADCgIJAgAAAA==.Lutsul:BAAALgAECgEJAQAAAA==.',
Ly='Lylka:BAABLgAECn8+AAMHAAkJ0SWdAABmAwAHAAkJ0SWdAABmAwASAAMJIiNxQwAwAQAAAA==.Lyrrena:BAAALgAECgMJBwAAAA==.',
Ma='Maanu:BAAALgAECgcJDwABLgAECggJMAAKABwZAA==.Macumbadora:BAAALgAECgQJCgAAAA==.Madfulock:BAAALgAECgcJEgAAAA==.Maeghann:BAAALgADCgMJAwAAAA==.Magalândia:BAAALgAECgIJAgAAAA==.Magraver:BAAALgAECgMJAwAAAA==.Mais:BAAALgADCgMJBQAAAA==.Malewolyyc:BAACLgAFFH8IAAMLAAIJyR54IwCZAAALAAIJyR54IwCZAAABAAEJZgcbPAA9AAAuAAQKfysAAwsACQmZIT8MAJ8CAAsACAk/Iz8MAJ8CAAEABglGEcQ4AC4BAAEuAAUUAwkDAA8AAAAA.Malhun:BAAALgADCgUJDgAAAA==.Malphan:BAAALgAECgcJBwAAAA==.Malyguz:BAACLgAFFH8UAAITAAQJ1BKlWgA0AQATAAQJ1BKlWgA0AQAuAAQKfxsAAhMABwldG+BgABkCABMABwldG+BgABkCAAAA.Malévolaa:BAAALgAECgYJBwAAAA==.Manipullador:BAAALgAECgIJAgAAAA==.Mapussauro:BAAALgAECgcJEQAAAA==.Maradi:BAAALgADCgIJAgAAAA==.Mariob:BAABLgAFFH8FAAImAAIJWgQHOQBNAAAmAAIJWgQHOQBNAAAAAA==.Marjøly:BAAALgAECgEJAQAAAA==.Markson:BAAALgADCgEJAQAAAA==.Massafera:BAABLgAECn8fAAIIAAkJMxPIWQC9AQAIAAkJMxPIWQC9AQAAAA==.Mather:BAAALgAECgEJAQAAAA==.Mathfacbruxo:BAABLgAECn9NAAIVAAkJFhxTGQCKAgAVAAkJFhxTGQCKAgAAAA==.Mauritiuz:BAAALgAFFAEJAQAAAA==.Mayanyy:BAAALgAECgEJAQAAAA==.',
Mc='Mcq:BAAALgAECgEJAQAAAA==.',
Md='Mdrdark:BAACLgAFFH8NAAIEAAUJlxRKZAAsAQAEAAUJlxRKZAAsAQAuAAQKfy0AAwQACQmiGUkwADsCAAQACQmiGUkwADsCACYAAwm/FWZHAGwAAAAA.',
Me='Medz:BAABLgAECn8jAAITAAkJlRqpMABUAgATAAkJlRqpMABUAgAAAA==.Meedea:BAAALgADCgUJBgAAAA==.Meetjack:BAAALgAECgEJAQAAAA==.Meiyin:BAAALgAECgYJCwAAAA==.Melania:BAAALgAECgEJAgAAAA==.Melissandra:BAAALgAFFAIJAwAAAA==.Mellkor:BAABLgAECn8qAAIDAAkJQhu7DABXAgADAAkJQhu7DABXAgAAAA==.Melytah:BAAALgAECgEJAgAAAA==.Melzynhaa:BAAALgAECgEJAwABLgAECggJMAAKABwZAA==.Meraxxes:BAAALgADCgcJDAAAAA==.Merellien:BAAALgADCggJDgAAAA==.Metamorful:BAABLgAECn8ZAAIFAAkJBxL/SQB7AQAFAAkJBxL/SQB7AQAAAA==.',
Mh='Mhorgann:BAAALgAECgUJBgAAAA==.',
Mi='Mijonakombi:BAABLgAECn8WAAIIAAkJ/hqPLgBEAgAIAAkJ/hqPLgBEAgAAAA==.Mikveh:BAAALgAECgYJCgAAAA==.Milim:BAABLgAECn8/AAMOAAkJ8hPsHQDnAQAOAAkJ2RLsHQDnAQAnAAgJRQ1JDwASAQAAAA==.Milliidan:BAAALgADCgUJBQAAAA==.Mindrathys:BAAALgAECgEJAQAAAA==.Mithrius:BAABLgAECn8kAAIIAAgJxxFZbwCNAQAIAAgJxxFZbwCNAQAAAA==.',
Ml='Mls:BAAALgAECgUJBgAAAA==.',
Mo='Mogrus:BAAALgADCgMJAwAAAA==.Mohanna:BAAALgAECgkJDgAAAA==.Mohanninha:BAAALgAECgYJCwAAAA==.Mohotok:BAABLgAECn9SAAIIAAkJNhkaJwBlAgAIAAkJNhkaJwBlAgAAAA==.Moonøvesso:BAAALgAECgIJBQAAAA==.Moopp:BAAALgADCgcJCAAAAA==.Mortixxia:BAABLgAECn8oAAIWAAgJnx39AwBEAgAWAAgJnx39AwBEAgAAAA==.',
Mu='Muata:BAAALgAECgYJDwAAAA==.Muf:BAAALgAECgYJBgAAAA==.Mupar:BAAALgADCgIJAgAAAA==.Murano:BAABLgAECn8yAAMbAAkJxR6eDQCSAgAbAAkJxR6eDQCSAgAZAAMJywoWUwCCAAAAAA==.Muzzo:BAAALgADCgYJCwABLgAECgcJDwAPAAAAAA==.',
My='Myrmïdom:BAAALgAECgIJAgAAAA==.Myzoreh:BAAALgAECggJDAAAAA==.',
['Má']='Mágico:BAAALgAECgEJAwAAAA==.Máia:BAABLgAECn8UAAIWAAgJiAz+EAAwAQAWAAgJiAz+EAAwAQAAAA==.',
['Mä']='Mändosz:BAABLgAECn8ZAAMEAAkJMRISbACLAQAEAAgJahISbACLAQAGAAMJCRBhIwCvAAAAAA==.',
['Mé']='Ménace:BAACLgAFFH8FAAIVAAMJPhcyawDnAAAVAAMJPhcyawDnAAAuAAQKfxUAAxUACQnmHfZaALcBABUACAnmHfZaALcBABYAAwlcDvJGAJoAAAAA.',
['Mÿ']='Mÿstyna:BAAALgAECgEJAQAAAA==.',
Na='Nalathiel:BAAALgAECgcJEwAAAA==.Narancia:BAAALgAECgYJDQABLgAECgcJCwAPAAAAAA==.Naryth:BAAALgAECgYJCAAAAA==.Nassur:BAAALgADCgEJAQAAAA==.Nattaliaa:BAAALgAECgEJAQAAAA==.Nazawill:BAAALgAECgEJAQAAAA==.Nazdru:BAAALgADCgMJAwABLgAECgkJVAAQAOQhAA==.Nazzh:BAAALgAECgEJAQABLgAECgQJBQAPAAAAAA==.',
Ne='Necronx:BAAALgAECgEJAQAAAA==.Necronxd:BAAALgADCgEJAgAAAA==.Nefas:BAABLgAECn8jAAIWAAkJYxOwBwDSAQAWAAkJYxOwBwDSAQAAAA==.Nefazo:BAAALgAECgcJCgAAAA==.Nefilo:BAAALgADCgYJEAAAAA==.Nepthunus:BAABLgAECn9IAAIgAAkJuyF9AAAYAwAgAAkJuyF9AAAYAwAAAA==.Nermand:BAAALgAECgEJAQAAAA==.Neshula:BAAALgADCgMJAwAAAA==.Neuvosor:BAAALgAECgEJAQAAAA==.',
Ni='Nibelunga:BAAALgADCgYJBgAAAA==.Nijor:BAAALgADCgYJBgAAAA==.Nilsonssbnu:BAAALgAECgEJAQAAAA==.',
No='Nobelnaga:BAAALgAECgMJAwAAAA==.Novatoo:BAAALgAECgUJDAAAAA==.',
Ny='Nyobb:BAAALgADCgMJAwAAAA==.Nyxra:BAAALgADCgcJEAAAAA==.',
['Nö']='Nöirr:BAAALgAECgEJAgAAAA==.',
Oc='Ocelotte:BAAALgADCgEJAQAAAA==.',
Od='Odin:BAAALgAECgEJAQAAAA==.Odynsabio:BAAALgAECgEJAQAAAA==.',
Of='Ofanzitsu:BAAALgADCgQJBAAAAA==.',
Oi='Oioimiguel:BAAALgAECgUJBQAAAA==.',
Ol='Olhua:BAAALgAECgMJCAAAAA==.Oljedvlad:BAAALgADCgEJAQAAAA==.Oluss:BAAALgADCgUJBQABLgAFFAMJFQAXAFEfAA==.',
Om='Omnath:BAAALgADCgYJBgAAAA==.',
Or='Orillan:BAABLgAECn9EAAMDAAkJIBssCwBxAgADAAkJIBssCwBxAgARAAEJhAcY5gAsAAAAAA==.Ornsteinsnow:BAABLgAECn8ZAAISAAkJvhQmHAAgAgASAAkJvhQmHAAgAgAAAA==.Orob:BAAALgAECgYJEQAAAA==.Ororah:BAAALgAECgYJEAAAAA==.Orsonn:BAAALgAECgYJCAAAAA==.Orukam:BAABLgAECn8ZAAMFAAkJMBZMQwCBAQAFAAgJ7BRMQwCBAQANAAMJTggeZgB/AAAAAA==.',
Os='Oszwald:BAAALgADCgEJAQAAAA==.',
['Oú']='Oúkürä:BAAALgAECgYJCgAAAA==.',
Pa='Padawani:BAAALgAECgMJAwAAAA==.Padgodeira:BAAALgAECgQJBAAAAA==.Padrealpha:BAAALgADCgcJCgAAAA==.Padrekelmøn:BAAALgAECgQJBAAAAA==.Palaha:BAAALgADCgEJAQABLgAFFAMJFQAXAFEfAA==.Palatina:BAABLgAFFH8GAAIIAAUJWhe2PwAmAQAIAAUJWhe2PwAmAQAAAA==.Palazzy:BAAALgAECgEJAgAAAA==.Pandong:BAAALgAECggJDwAAAA==.Panena:BAAALgAECgIJAwAAAA==.Pangedrey:BAABLgAECn9TAAMKAAkJ5x88CADBAgAKAAkJ5x88CADBAgAYAAcJJQSuTADJAAAAAA==.Paracepatrol:BAAALgAECgQJAwAAAA==.Parcival:BAACLgAFFH8LAAIXAAMJoBorUwD5AAAXAAMJoBorUwD5AAAuAAQKfzIAAhcACQmKIz0FADsDABcACQmKIz0FADsDAAAA.Parký:BAAALgAECgYJBwAAAA==.Pattalógika:BAAALgAECgEJAQAAAA==.Paullk:BAABLgAECn8gAAINAAYJchRFPAAbAQANAAYJchRFPAAbAQAAAA==.',
Pe='Pedrinho:BAAALgADCgYJBgABLgAFFAUJEgARACIgAA==.Penseur:BAAALgAECgcJBwAAAA==.Penéllope:BAAALgAECgQJBwAAAA==.Persëphone:BAABLgAECn8VAAMLAAcJsRT8PAD6AAALAAUJyRD8PAD6AAABAAYJCBIWWwCmAAAAAA==.Peruchi:BAAALgAECgQJBAAAAA==.',
Pg='Pgms:BAAALgAECgUJBQAAAA==.',
Ph='Phacozitos:BAAALgAECgEJAQAAAA==.Phaxe:BAAALgADCgIJAgAAAA==.Phoenicx:BAAALgADCgMJBgAAAA==.Phøënïx:BAAALgAECgcJDAAAAA==.',
Pi='Pipelinebr:BAAALgAECgUJBQAAAA==.Pitombinha:BAAALgAECgEJBAAAAA==.',
Pl='Plumalume:BAAALgADCgYJBgAAAA==.',
Po='Powalker:BAAALgAECgEJAgAAAA==.',
Pp='Pp:BAABLgAFFH8QAAQaAAUJjQlEIQA9AQAaAAUJjQlEIQA9AQABAAIJ4waKMQB4AAALAAEJ6wAWPAAlAAABLgAFFAcJGgAOALgRAA==.',
Pr='Prometeus:BAAALgAECgYJDwAAAA==.Pryon:BAAALgAECgUJCwAAAA==.',
Pt='Ptollomeu:BAAALgAECgMJBQABLgAECgMJCQAPAAAAAA==.',
['Pä']='Pändero:BAABLgAECn8WAAIJAAYJ8yJUGQBIAgAJAAYJ8yJUGQBIAgAAAA==.Pänqueca:BAAALgAECgEJAgAAAA==.',
['Pé']='Pénacova:BAAALgADCgEJAQAAAA==.',
['Pî']='Pîo:BAACLgAFFH8IAAITAAMJVxFcfQDjAAATAAMJVxFcfQDjAAAuAAQKfxcAAxMACAltGbtgALsBABMACAl5GLtgALsBACUABAnTGPAKACwBAAAA.',
Qu='Quejerok:BAAALgAECgYJEwAAAA==.',
Ra='Radiação:BAAALgAECgUJBQAAAA==.Radunz:BAABLgAECn9UAAIQAAkJ5CHuAQATAwAQAAkJ5CHuAQATAwAAAA==.Ragnaros:BAABLgAFFH8FAAISAAIJAxDVOQB4AAASAAIJAxDVOQB4AAAAAA==.Ragnarssön:BAAALgAFFAEJAQAAAA==.Raineko:BAAALgADCgYJBgAAAA==.Raio:BAACLgAFFH8FAAITAAIJlxOInwCRAAATAAIJlxOInwCRAAAuAAQKfy8AAhMACQkEIVEdAKkCABMACQkEIVEdAKkCAAAA.Ralfwur:BAAALgAECgQJBwAAAA==.Rargsa:BAABLgAECn8dAAIGAAgJfAaCGAAOAQAGAAgJfAaCGAAOAQAAAA==.Rariel:BAAALgADCgMJAgAAAA==.Rasmon:BAABLgAECn8uAAIVAAkJRxQkQwDRAQAVAAkJRxQkQwDRAQAAAA==.Ravendreth:BAAALgADCgEJAQAAAA==.Raykarla:BAAALgAECgIJAwAAAA==.Raymain:BAACLgAFFH8GAAMKAAMJzh02GgDyAAAKAAMJzh02GgDyAAAJAAEJkw64YQAvAAAuAAQKfyQAAwkACQkSFjY8AHcBAAkACAmaFDY8AHcBAAoABwkXFuQ3AB8BAAAA.Raíka:BAAALgAECgYJCwAAAA==.',
Re='Reddnose:BAAALgAECgUJCQAAAA==.Reinhold:BAABLgAECn8aAAMIAAcJYRQFegB4AQAIAAcJYRQFegB4AQASAAUJ2QitWgDIAAAAAA==.',
Rh='Rhuryk:BAAALgADCggJCAAAAA==.',
Ri='Ricktdai:BAAALgAECgEJAQAAAA==.Riesze:BAACLgAFFH8JAAIXAAMJoRGdWwDlAAAXAAMJoRGdWwDlAAAuAAQKfycAAhcACQl9GXwgAGECABcACQl9GXwgAGECAAAA.',
Ro='Roguinhu:BAAALgAFFAEJAQAAAA==.Ropaoo:BAABLgAECn8XAAIWAAYJEhZ/DwBEAQAWAAYJEhZ/DwBEAQAAAA==.',
Ru='Rua:BAAALgAECgQJBAAAAA==.Rurumo:BAAALgADCgQJBAAAAA==.Rusga:BAAALgADCggJCAAAAA==.Rustovick:BAAALgAECgMJBQAAAA==.',
Ry='Rytheas:BAAALgAECgQJBgAAAA==.',
['Rä']='Rämzä:BAAALgAECgYJEwAAAA==.',
['Rå']='Råy:BAAALgAECgQJCQAAAA==.',
['Rí']='Rízadinha:BAAALgAECgQJBAAAAA==.',
Sa='Saargeras:BAAALgADCgMJAwAAAA==.Saffír:BAABLgAECn8mAAIIAAkJTRhVNQApAgAIAAkJTRhVNQApAgAAAA==.Saiden:BAAALgADCgQJBAAAAA==.Saintkaue:BAAALgADCgUJCAAAAA==.Sairoz:BAAALgAECgEJAQAAAA==.Samalandraa:BAAALgADCgEJAQAAAA==.Sanahh:BAAALgAECgYJCAAAAA==.Sanateia:BAAALgADCgYJCwAAAA==.Santamadre:BAAALgADCgEJAQAAAA==.Sapekinhä:BAACLgAFFH8FAAIDAAIJwxiTIACLAAADAAIJwxiTIACLAAAuAAQKfywABAMACQlJI4wEAP0CAAMACQlJI4wEAP0CAAIAAglSGEkjAH8AABEAAglFCfX0AFQAAAAA.Satanvitória:BAABLgAECn8uAAMZAAgJ7B4vDAAhAgAbAAcJYRo0JgAoAgAZAAgJbh4vDAAhAgAAAA==.Sauroth:BAAALgADCgUJCQAAAA==.',
Sc='Scheiren:BAAALgAECgQJBgAAAA==.',
Se='Senegos:BAAALgADCgcJBwAAAA==.Sereiaa:BAABLgAECn8pAAIXAAgJCA//YgB7AQAXAAgJCA//YgB7AQAAAA==.Sesiom:BAAALgAECgcJBgAAAA==.',
Sh='Shalltearr:BAAALgADCgEJAQAAAA==.Shamate:BAAALgAFFAEJAQAAAA==.Shanoa:BAAALgAECgMJAwAAAA==.Shariany:BAAALgADCgEJAQAAAA==.Sharpersong:BAAALgADCgcJBgAAAA==.Shedo:BAABLgAECn8VAAMZAAgJAxrEFgCiAQAZAAcJuBnEFgCiAQAbAAYJWg+VYgAoAQAAAA==.Sheevane:BAABLgAECn8eAAIFAAkJmRdUJAAmAgAFAAkJmRdUJAAmAgAAAA==.Shinzo:BAAALgADCgEJAQAAAA==.Shonja:BAAALgADCgcJDgAAAA==.Shula:BAAALgADCgcJDQAAAA==.Shumuk:BAAALgAECgEJAQAAAA==.Shÿnara:BAAALgAECgkJDwAAAA==.',
Si='Siclop:BAAALgADCgYJBgAAAA==.Silgris:BAAALgAECgEJAQABLgAECggJIAASAPERAA==.Silmeria:BAABLgAECn8WAAIdAAgJAgXccwD8AAAdAAgJAgXccwD8AAAAAA==.Silverchain:BAAALgADCgcJCgAAAA==.Sinton:BAAALgAECgQJCAAAAA==.',
Sk='Skadryan:BAAALgAECgEJAQAAAA==.Skeletowman:BAAALgADCgEJAQAAAA==.Skineh:BAAALgAECgQJBwAAAA==.Skinme:BAABLgAECn8UAAIJAAYJKwS/hwCDAAAJAAYJKwS/hwCDAAAAAA==.',
Sm='Smylf:BAAALgAECgkJEAAAAA==.',
Sn='Snakedown:BAAALgAECgEJAgAAAA==.',
So='Sombrea:BAAALgAECgYJEgAAAA==.',
Sp='Spectrø:BAAALgAECgYJBgAAAA==.',
Sr='Srheal:BAAALgAECgQJBAAAAA==.Srsapo:BAAALgAECgMJBgAAAA==.',
Ss='Ssamara:BAAALgAECgYJBQAAAA==.',
St='Stampede:BAAALgADCgMJAwAAAA==.Starian:BAABLgAECn8gAAMFAAcJKRy5JAAjAgAFAAcJKRy5JAAjAgANAAEJywwTfwAzAAAAAA==.Straider:BAAALgAECgEJAQAAAA==.Stëlla:BAABLgAECn8vAAIdAAgJ3RTlLgD2AQAdAAgJ3RTlLgD2AQAAAA==.',
Su='Suckmyhammer:BAAALgAECgEJAQAAAA==.Sunnara:BAACLgAFFH8SAAIRAAUJIiAAMQBZAQARAAUJIiAAMQBZAQAuAAQKfyIAAhEACQnwIQcKAPkCABEACQnwIQcKAPkCAAAA.Supergx:BAAALgAECgQJBAAAAA==.Superkx:BAAALgAECgQJBQAAAA==.Suzanomu:BAAALgADCgYJCwAAAA==.',
Sy='Sylran:BAAALgADCgQJBgAAAA==.Synk:BAAALgADCgQJBAAAAA==.Syofra:BAAALgAECgQJBQAAAA==.Syrelys:BAAALgADCgYJBgAAAA==.Syuon:BAACLgAFFH8MAAIJAAQJfBZNKQAWAQAJAAQJfBZNKQAWAQAuAAQKfzIAAwkACQkiIeQFAEYDAAkACQkiIeQFAEYDAAoAAgmQBiOIAEcAAAAA.',
['Së']='Sëkhmet:BAAALgAECgYJCwAAAA==.',
['Sï']='Sïmbä:BAABLgAECn8bAAMEAAkJjQ5UcgB9AQAEAAkJjQ5UcgB9AQAGAAEJkAShGQAoAAABLgAFFAEJAQAPAAAAAA==.',
['Sÿ']='Sÿkies:BAAALgADCgEJAQAAAA==.',
Ta='Talandar:BAABLgAECn82AAINAAkJERnAEABUAgANAAkJERnAEABUAgAAAA==.Tankudo:BAABLgAECn8aAAIEAAcJ6BO9ggBbAQAEAAcJ6BO9ggBbAQAAAA==.Tannia:BAAALgADCgIJAgAAAA==.Tanthallas:BAAALgAECgEJAQAAAA==.Tavindapedra:BAAALgAECgYJCwAAAA==.',
Tc='Tchutchuco:BAAALgAECgIJAwAAAA==.',
Te='Tekzero:BAAALgAECgEJCAAAAA==.Tempestus:BAAALgADCgYJBgAAAA==.Tennebra:BAAALgADCgYJCAAAAA==.Teobaldo:BAAALgADCgYJCgAAAA==.Terron:BAABLgAECn8xAAMdAAkJEBaCIQBCAgAdAAkJEBaCIQBCAgAeAAIJnRdfcwCMAAAAAA==.',
Th='Thabitah:BAABLgAECn9OAAIBAAkJ0R9FBgDuAgABAAkJ0R9FBgDuAgAAAA==.Thaliath:BAAALgADCgQJBAAAAA==.Thallariel:BAAALgAECgQJBgAAAA==.Theteo:BAABLgAECn8ZAAIIAAkJZQu8fwBsAQAIAAkJZQu8fwBsAQAAAA==.Thiberios:BAAALgAECgUJDAAAAA==.Thirros:BAAALgADCgUJBQAAAA==.Thorres:BAAALgAECgMJBwAAAA==.Thotamon:BAAALgAECgQJCAAAAA==.Throin:BAAALgAECgMJAwAAAA==.Thràain:BAAALgAECgcJDgAAAA==.Thuki:BAAALgAECgEJAQAAAA==.Thunderblade:BAAALgAECgYJDgAAAA==.Théus:BAAALgAECgMJAwABLgAFFAMJBQAVAD4XAA==.',
Ti='Tiramisu:BAAALgAECgcJCwAAAA==.',
To='Torâo:BAAALgAECgYJDgAAAA==.Toucinho:BAAALgAECgYJDgAAAA==.',
Tr='Traydd:BAABLgAECn8iAAIQAAgJlBVgDgDJAQAQAAgJlBVgDgDJAQAAAA==.Trollando:BAAALgAECgUJCAAAAA==.',
Tu='Tuga:BAAALgADCgMJAwAAAA==.Turokk:BAABLgAECn8bAAIXAAgJTA+YYgB8AQAXAAgJTA+YYgB8AQAAAA==.',
Tw='Twilight:BAAALgADCgYJDQAAAA==.Twylluch:BAAALgADCgQJBgABLgAECgkJKAASAOsXAA==.',
Ul='Ulhim:BAAALgADCgcJEwAAAA==.',
Ur='Uriuri:BAAALgADCgYJBgABLgAECgkJVAAQAOQhAA==.',
Us='Usfull:BAABLgAECn87AAMLAAkJHhLXJACZAQALAAgJYhPXJACZAQABAAgJFg2+LQBqAQAAAA==.',
Va='Vacavelha:BAAALgAECgEJAQAAAA==.Vahtorn:BAAALgAECgMJBgAAAA==.Valaerys:BAAALgAECgUJCgAAAA==.Valaniri:BAAALgADCgEJAQAAAA==.Vallkÿria:BAAALgAECgYJBgAAAA==.Vanheelsen:BAAALgAFFAIJAgAAAA==.Vanyathariel:BAAALgAECgEJAQAAAA==.Vareena:BAAALgADCggJCAABLgAECgkJQwAUAAImAA==.Vashiel:BAAALgADCgIJAgAAAA==.',
Ve='Vehuiáh:BAABLgAECn8eAAMSAAgJMB2xHAAcAgASAAgJMB2xHAAcAgAIAAEJRQSDugEjAAAAAA==.Velen:BAABLgAECn8aAAIEAAcJshCJkQBAAQAEAAcJshCJkQBAAQAAAA==.Vellkor:BAAALgADCgYJBgAAAA==.Vellon:BAAALgADCgEJAQAAAA==.Venrique:BAAALgAECgQJBAABLgAECgYJEQAPAAAAAA==.Venusa:BAAALgADCgMJBAAAAA==.Verno:BAAALgADCgcJCwAAAA==.Verzuk:BAABLgAECn8dAAIEAAgJPQqqiQBOAQAEAAgJPQqqiQBOAQAAAA==.',
Vi='Vidnands:BAAALgAECgEJAQAAAA==.Viinyy:BAAALgAECgMJAwAAAA==.Vilthor:BAAALgAECgUJBQAAAA==.Vintekilo:BAABLgAECn8YAAIIAAkJzRaiYgC9AQAIAAkJzRaiYgC9AQAAAA==.',
Vo='Voiddh:BAAALgAECgcJDAAAAA==.Vokeshar:BAAALgADCgUJBQAAAA==.Voltadupla:BAAALgAECgQJBQAAAA==.Voop:BAAALgADCgYJFAAAAA==.',
Vr='Vrenshrrgn:BAAALgADCgYJBgAAAA==.',
Vy='Vygh:BAACLgAFFH8JAAIVAAMJmBUvcwDWAAAVAAMJmBUvcwDWAAAuAAQKfy0AAxUACQm5IecNANwCABUACQm5IecNANwCABYAAQkjDzpwADYAAAAA.Vyndrill:BAAALgAECgYJDgAAAA==.',
['Vä']='Välion:BAAALgADCgIJAgAAAA==.',
Wa='Wacom:BAAALgADCgUJBQAAAA==.Walkers:BAAALgAECggJDQAAAA==.Warlaka:BAAALgAECgQJBwAAAA==.Warpiel:BAAALgADCgcJDAABLgAECgkJHgAaAC0OAA==.Watchtower:BAAALgAECgQJBAAAAA==.',
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
Yi='Yingsu:BAABLgAECn8ZAAIYAAkJeCKUDgBOAgAYAAkJeCKUDgBOAgAAAA==.',
Yo='Yoshihime:BAAALgAECgIJAgABLgAECgkJHgAFAJkXAA==.',
Yv='Yvin:BAAALgAECgMJBAAAAA==.',
Za='Zallmo:BAACLgAFFH8FAAIbAAMJTwWDOwC4AAAbAAMJTwWDOwC4AAAuAAQKfx8AAhsACAluFZYkAM8BABsACAluFZYkAM8BAAAA.Zarath:BAAALgAECgUJBgAAAA==.Zawarudo:BAAALgAECgYJCgAAAA==.',
Ze='Zedd:BAAALgAFFAIJAgAAAA==.Zenorclord:BAAALgADCgQJBgAAAA==.Zeytona:BAABLgAECn8jAAIYAAkJjAsnJgB6AQAYAAkJjAsnJgB6AQAAAA==.',
Zi='Ziracruz:BAAALgAECgQJCwAAAA==.',
['Zí']='Zíngara:BAAALgAECgEJAQAAAA==.',
['Ár']='Árÿä:BAABLgAECn9VAAIXAAkJURVBMAAXAgAXAAkJURVBMAAXAgAAAA==.',
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
