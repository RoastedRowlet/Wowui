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

local lookup = {'Priest-Shadow','Unknown-Unknown','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Protection','Paladin-Retribution','Warrior-Arms','Warrior-Protection','Monk-Mistweaver','DemonHunter-Havoc','Priest-Holy','Mage-Arcane','Druid-Guardian','Warrior-Fury','Hunter-BeastMastery','Paladin-Holy','DeathKnight-Blood','Shaman-Elemental','Druid-Restoration','Druid-Feral','Monk-Windwalker','Mage-Frost','Druid-Balance','Monk-Brewmaster','Rogue-Assassination','Rogue-Subtlety','Warlock-Destruction','Warlock-Demonology','Priest-Discipline','DemonHunter-Vengeance','Shaman-Restoration','Warlock-Affliction','Shaman-Enhancement','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Mage-Fire','DemonHunter-Devourer','Hunter-Marksmanship',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abaca:BAAANQAECgIIAgAAAA==.Abacatte:BAAANQAECgUICQAAAA==.',
Ad='Adelaide:BAAANQADCgUIBwABNQAFFAcIFwABABESAA==.',
Ae='Aelthor:BAAANQAECgEIAQAAAA==.',
Al='Alanie:BAAANQAECgEIAQABNQAECgYIDgACAAAAAA==.Aleriastorm:BAAANQABCgIIAgAAAA==.Alessaxd:BAABNQAECn8YAAMDAAkKPA6iQwC1AQADAAkKPA6iQwC1AQAEAAMKRwwLQwCtAAAAAA==.Alfajhor:BAABNQAECn89AAMFAAoKaSOPAgCjAwAFAAoKaSOPAgCjAwAGAAEKAAA2cgEAAAAAAA==.Alfajhòr:BAAANQAECgEIBQAAAA==.Alfajhõr:BAAANQAECgYIDgAAAA==.Alkaid:BAABNQAECn8sAAMHAAkK8hjgOwDhAQAHAAgK1RjgOwDhAQAIAAgK+gsTIwAxAQAAAA==.Alladryel:BAAANQADCgYIBgAAAA==.Allandriel:BAAANQAECgIIAgABNQAECgYIEwACAAAAAA==.Alleriane:BAABNQAECn8lAAIJAAoKghqDDwCIAgAJAAoKghqDDwCIAgAAAA==.Allone:BAABNQAECn8xAAIKAAoKFguERQCaAQAKAAoKFguERQCaAQAAAA==.Allunt:BAAANQAECgYICwAAAA==.Almin:BAAANQAECgIIBwAAAA==.Alruna:BAAANQAECgIIAgAAAA==.',
Am='Ametnys:BAAANQAECgUIEAAAAA==.Amonhar:BAAANQAECgQIBQABNQAECgkJJAALAAIYAA==.',
An='Anakata:BAAANQAECgYIDgAAAA==.Andaliz:BAABNQAECn8yAAIGAAkKByR9BwC+AwAGAAkKByR9BwC+AwAAAA==.Andaril:BAAANQAECgQIBgAAAA==.Antonel:BAAANQABCgYIBgAAAA==.Antonellaes:BAAANQAECgEIAwABNQAECgYIGAADAEYFAA==.',
Ap='Aprocom:BAAANQAECgUIBgAAAA==.',
Ar='Arcanör:BAABNQAECn8bAAIMAAgKsg0D9QChAQAMAAgKsg0D9QChAQAAAA==.Arctorius:BAABNQAECn8UAAMGAAcKaQxe0AB7AQAGAAcKaQxe0AB7AQAFAAEKAADzdgAmAAAAAA==.Arkanidas:BAAANQAECgEIAQAAAA==.Aronys:BAAANQAECgYIEAAAAA==.Arquitetö:BAAANQADCgIIAgAAAA==.Arthashand:BAAANQADCgEIAQAAAA==.Artronis:BAABNQAECn8tAAINAAoK+hL6EwAkAgANAAoK+hL6EwAkAgAAAA==.Arukäi:BAABNQAECn8hAAMHAAgKxwr0qwCvAQAHAAgKxwr0qwCvAQAOAAMKgQdWKQBlAAAAAA==.Arägørn:BAAANQAECgUIDgAAAA==.',
As='Assintomatic:BAAANQAECgEIAQABNQAECggIEAACAAAAAA==.',
At='Atriuz:BAAANQAECgQIDAAAAA==.Ats:BAAANQAECgEIAQAAAA==.',
Ay='Ayrthwill:BAAANQAECgEIBAAAAA==.',
Az='Azerotiano:BAAANQAECgQIDgAAAA==.',
['Aÿ']='Aÿ:BAAANQAECgEIAQAAAA==.',
Ba='Badhealer:BAAANQAECgcICQAAAA==.Baldraccus:BAAANQADCgcIBwAAAA==.Balk:BAABNQAECn82AAIPAAoKhSBZIAAWAwAPAAoKhSBZIAAWAwAAAA==.Bambur:BAAANQAECgEIAQAAAA==.Barauna:BAAANQAECgEIAQAAAA==.Barbabruto:BAABNQAECn8lAAMIAAoKfhpECwCIAgAIAAoKShlECwCIAgAOAAIKRxw+FQCgAAAAAA==.Barbacancer:BAAANQAECgQIBQAAAA==.Barbalock:BAAANQADCggICAAAAA==.Barbaogro:BAAANQAECgEIAQAAAA==.Barbasanta:BAAANQAECgQIBgABNQAECgoKJQAIAH4aAA==.Batgirl:BAAANQAECggIEQAAAA==.',
Be='Belthorsin:BAAANQADCgYIBgAAAA==.Belthorvil:BAAANQADCgEIAQAAAA==.',
Bi='Bigbag:BAAANQADCgQIBQAAAA==.Biønic:BAAANQAECgUIEQAAAA==.',
Bl='Blackheartz:BAAANQAECgEIAQAAAA==.Blackmoonx:BAABNQAECn8VAAIDAAkK2BjLKgBFAgADAAkK2BjLKgBFAgABNQAECggIFwAHAGIiAA==.Blackninja:BAAANQAECgEIAQAAAA==.Blu:BAEANQAECgEIAQABNQAECgcIFQAQALgMAA==.',
Bo='Box:BAAANQADCgMIAwAAAA==.',
Br='Brahman:BAAANQAECgEIAQAAAA==.Bratloko:BAAANQADCgMIAwAAAA==.Bright:BAAANQADCgYIBgAAAA==.Brimathor:BAAANQAECgIIAQAAAA==.Bruex:BAAANQAECgEIAgAAAA==.Bruker:BAAANQADCgIIAgAAAA==.Brutalhoof:BAAANQAECgEIAgAAAA==.',
Bu='Buzzumaaky:BAABNQAECn8VAAIMAAcKPhdYuAATAgAMAAcKPhdYuAATAgAAAA==.',
By='Bynhu:BAAANQADCggICAAAAA==.',
['Bá']='Bávor:BAAANQADCgEIAQAAAA==.',
['Bí']='Bílly:BAAANQAECgEIAQAAAA==.',
Ca='Callstorm:BAAANQAECgEIAwAAAA==.Calteryeker:BAAANQAECgQIEAAAAA==.Capitu:BAAANQADCggIEwABNQAECgkJJAARAL8aAA==.Capyvara:BAAANQABCgYIBwAAAA==.Caralh:BAACNQAFFH8FAAIRAAQKfg9MJABsAAARAAQKfg9MJABsAAA1AAQKfy0AAhEACQq+IKsRAB8DABEACQq+IKsRAB8DAAAA.Caroll:BAAANQADCgMIAwAAAA==.Caçaorda:BAAANQAECgMJBAAAAA==.',
Ce='Cecilith:BAACNQAFFH8LAAISAAMKFQlvDQDHAAASAAMKFQlvDQDHAAA1AAQKfzsAAhIACgrjICQWAEQDABIACgrjICQWAEQDAAAA.Cernûnnos:BAABNQAECn8UAAMTAAUK3RfjOQBPAQATAAUK3RfjOQBPAQAUAAEKAABETQAdAAAAAA==.',
Ch='Champdude:BAABNQAECn82AAMVAAkKzR4wDQAdAgAVAAkKzR4wDQAdAgAJAAIKKQ55JgBuAAAAAA==.Chopquatro:BAAANQADCggICAAAAA==.Chrnnos:BAAANQAECgYICQABNQAECgkJIQAOAPUdAA==.',
Co='Corineus:BAAANQADCgYIDQAAAA==.Cowzeroth:BAABNQAECn8tAAISAAgKDR+zPgB7AgASAAgKDR+zPgB7AgABNQAECgoKNgAPAIUgAA==.',
Cr='Crassustitan:BAAANQAECggICQAAAA==.Cristcalad:BAABNQAECn8eAAMIAAYKTxZLIgA4AQAIAAYKTxZLIgA4AQAHAAYKqAxG5gAaAQAAAA==.',
Cu='Cutia:BAAANQAECgEIAQAAAA==.',
Da='Daemi:BAAANQAECggIEAAAAA==.Dakael:BAAANQAECgEIAQABNQAECgkJNwAUANocAA==.Dalaty:BAAANQAECgUIDwAAAA==.Daresh:BAAANQADCgEIAQAAAA==.Dariok:BAABNQAECn8eAAIHAAcKjAQYqQC6AAAHAAcKjAQYqQC6AAAAAA==.Darkove:BAABNQAECn8qAAIWAAoKHRAsDQDgAQAWAAoKHRAsDQDgAQAAAA==.Darrow:BAABNQAECn8uAAIDAAoKVRXlIQC9AQADAAoKVRXlIQC9AQAAAA==.Daryan:BAAANQAECgcIEAAAAA==.Day:BAAANQAECgQIBgAAAA==.',
De='Deathinhu:BAABNQAECn85AAIMAAoKKB9JIgBvAgAMAAoKKB9JIgBvAgAAAA==.Demoriana:BAABNQAECn8YAAMDAAYKRgU1fQCzAAADAAYKNAQ1fQCzAAARAAQKbwS3bABaAAAAAA==.Dethroned:BAAANQAECgQIDQAAAA==.',
Di='Diefs:BAAANQAECgEIAQABNQAECgkJJAALAAIYAA==.Digaoxdrx:BAAANQADCgQIBAAAAA==.Dimeros:BAABNQAECn86AAIXAAoKdwpqIACDAQAXAAoKdwpqIACDAQAAAA==.Divano:BAABNQAECn84AAIBAAoKyB7BBgCpAgABAAoKyB7BBgCpAgAAAA==.',
Dk='Dkats:BAAANQAECgEIAQAAAA==.Dkhalifa:BAAANQADCgYIBgAAAA==.',
Do='Dogowner:BAAANQAECgYIBgAAAA==.Donora:BAAANQAECgQIBAAAAA==.Dorfillaw:BAAANQAECgUICgAAAA==.Dorvana:BAAANQADCgMJAwABNQAECgkJMgAGAAckAA==.',
Dr='Dracthyrius:BAAANQAECgEIAQAAAA==.Draenthar:BAAANQADCgQIBQAAAA==.Dragonstyle:BAAANQAECgcIDQAAAA==.Dragony:BAAANQAECgEIAQAAAA==.Dreez:BAAANQAECgYICAAAAA==.Drexus:BAAANQADCgMIAwAAAA==.Drigolas:BAAANQADCgYICAAAAA==.Druidblack:BAAANQADCgUIBQAAAA==.',
Eh='Ehomi:BAAANQADCgIIAgAAAA==.',
Ei='Eirin:BAABNQAECn8aAAIYAAUKlRM/HQAUAQAYAAUKlRM/HQAUAQAAAA==.',
El='Eldris:BAAANQADCgEIAQAAAA==.Elidibus:BAAANQADCgQIBAAAAA==.Elistraee:BAAANQADCgEIAQAAAA==.Ellvarg:BAAANQAECgEIAQAAAA==.Eltaelei:BAAANQAECgEIAQAAAA==.Eluuria:BAABNQAECn8bAAIGAAoKMw06iQA+AQAGAAoKMw06iQA+AQAAAA==.',
En='Enkrenco:BAAANQADCgQIBAAAAA==.Ennafaryn:BAAANQABCgQIBgAAAA==.Ensabanú:BAAANQADCgQIBAAAAA==.',
Er='Erilaethaen:BAAANQAECgIIAgAAAA==.Erlek:BAAANQADCggIFQAAAA==.Ernest:BAABNQAECn81AAITAAkKjiESBwDuAgATAAkKjiESBwDuAgAAAA==.Erulan:BAAANQADCgQIBwAAAA==.',
Es='Estgan:BAAANQADCgMIAwAAAA==.',
Et='Ether:BAABNQAECn8ZAAIRAAkKrRJRTQDAAQARAAkKrRJRTQDAAQAAAA==.Etubrutus:BAAANQAECgEIAQAAAA==.',
Ev='Evangelouco:BAAANQADCgQIBAAAAA==.Evilbarba:BAACNQAFFH8FAAIGAAUK/guKFAASAQAGAAUK/guKFAASAQA1AAQKfyYAAgYACQoJGll4ADwCAAYACQoJGll4ADwCAAAA.',
Ex='Exodes:BAAANQADCgMIAwAAAA==.Exort:BAAANQAECgUICwAAAA==.Exothus:BAAANQAECgQJCQAAAA==.',
Fa='Faldark:BAAANQADCgUIBQAAAA==.Fandrall:BAAANQAECgEIAQAAAA==.Faranir:BAAANQADCggIEAAAAA==.Faris:BAABNQAECn8tAAMZAAoKOBMxOAD2AQAZAAcKhhcxOAD2AQAaAAkKKg48RgBGAQABNQAECgoKNgAPAIUgAA==.Faver:BAAANQADCgMIAwAAAA==.Fayla:BAAANQAECgEIAwAAAA==.Faölin:BAABNQAECn8qAAIaAAkKCxeEEQBpAgAaAAkKCxeEEQBpAgAAAA==.',
Fe='Ferael:BAABNQAECn87AAMGAAoKgR+dFADWAgAGAAoKgR+dFADWAgAFAAQKPQkPUACmAAAAAA==.Ferrus:BAAANQAECgQIBAAAAA==.',
Fi='Filik:BAAANQAECgEIAQAAAA==.',
Fj='Fjord:BAAANQAECgIIAgAAAA==.',
Fl='Flavors:BAABNQAECn8oAAQHAAoKqh7vKgAQAwAHAAoKqh7vKgAQAwAOAAEKChuRHQBRAAAIAAEKCxhmLABGAAAAAA==.Florbela:BAABNQAECn8fAAITAAgKygvAMwB8AQATAAgKygvAMwB8AQAAAA==.Flupy:BAAANQAECgEIAQAAAA==.',
Fo='Fogue:BAAANQADCgMIAwAAAA==.',
Fr='Fredericc:BAAANQAECgcIDgAAAA==.Freecs:BAAANQAECgcIEwABNQAECgoKFAAMAFwQAA==.Freyá:BAABNQAECn8wAAMFAAoKChxlEACXAgAFAAoKChxlEACXAgAGAAcK2hAp3ABjAQAAAA==.Frostburn:BAAANQAECggIEAAAAA==.Froststriker:BAAANQAECgIIAgAAAA==.',
Fu='Fulvo:BAAANQADCgQIBQAAAA==.',
Ga='Gadodamorena:BAAANQAECgEIAQAAAA==.Galfur:BAABNQAECn8cAAIXAAUKOQeAfwDQAAAXAAUKOQeAfwDQAAAAAA==.Galhuda:BAAANQAECgQIBwAAAA==.Galica:BAAANQAECgEIAQAAAA==.Gandwelf:BAAANQADCggICAAAAA==.',
Ge='Geisty:BAAANQAECgEIAQABNQAECgIIBQACAAAAAA==.',
Gl='Glutotwo:BAAANQAECgEIAgAAAA==.',
Go='Goldchain:BAAANQAECgYICwAAAA==.Govers:BAAANQAECgEIAQABNQAECgcICQACAAAAAA==.',
Gr='Grommar:BAAANQADCgUIBQABNQAECgQIEAACAAAAAA==.Grumax:BAABNQAECn8YAAIGAAcKkAvs1wBsAQAGAAcKkAvs1wBsAQAAAA==.',
Gu='Gudeath:BAABNQAECn8vAAIHAAkKnxWJiAAHAgAHAAkKnxWJiAAHAgAAAA==.Guerrerinhow:BAAANQAECgIIAwABNQAECgoKJwAXAOQNAA==.Guitianki:BAAANQADCggIEgAAAA==.Gulek:BAAANQAECgYIBAAAAA==.Gussg:BAABNQAECn8jAAMbAAgKTBYVBABsAQAbAAcKTBYVBABsAQAcAAUKugjo4QAFAQAAAA==.',
['Gà']='Gàladriel:BAAANQAECgYIEQAAAA==.',
['Gö']='Göhan:BAABNQAECn8UAAINAAgKgg/QGABHAQANAAgKgg/QGABHAQAAAA==.',
['Gø']='Gøvers:BAAANQAECgcICQAAAA==.',
['Gü']='Güttz:BAABNQAECn8gAAIKAAgK5RCCOwDaAQAKAAgK5RCCOwDaAQAAAA==.',
Ha='Hagires:BAAANQAECgYIBwAAAA==.Hanaluna:BAAANQADCggICAAAAA==.Harchus:BAAANQAECgEIAQAAAA==.Hargarthul:BAAANQAECgEIAQAAAA==.Hazell:BAAANQAECgEIAQAAAA==.',
He='Heaveth:BAAANQADCgYIAgABNQAECgoKQAASAGocAA==.Hellspont:BAABNQAECn8gAAQUAAgKKiIaDABnAgAUAAcKPSIaDABnAgATAAUKChlrHgBtAQANAAIKzxv/RgCVAAAAAA==.Hendrikison:BAAANQAECgIIBAAAAA==.',
Ho='Horagalles:BAAANQAECgEIAQAAAA==.Hotmojo:BAACNQAFFH8LAAIMAAQK6haWGwDTAAAMAAQK6haWGwDTAAA1AAQKf0UAAgwACgpcIeAVALMCAAwACgpcIeAVALMCAAAA.',
Hu='Hunfox:BAABNQAECn9GAAIPAAoKRCPACQCPAwAPAAoKRCPACQCPAwAAAA==.Hunterhearst:BAAANQADCgYIBwAAAA==.Huor:BAAANQAECgQIBAAAAA==.',
Hy='Hylana:BAAANQADCggICAAAAA==.',
['Hö']='Hölycrüsh:BAACNQAFFH8FAAIGAAMKgRuLFwDtAAAGAAMKgRuLFwDtAAA1AAQKfzwAAgYACgpXI10mAGoCAAYACgpXI10mAGoCAAAA.',
Ih='Ihntwuaed:BAAANQADCgQIBwAAAA==.',
Ik='Ikoo:BAABNQAECn8XAAIdAAkKHRcJAgAyAgAdAAkKHRcJAgAyAgAAAA==.',
Il='Illaril:BAACNQAFFH8YAAIeAAUKDQ1tAgAZAQAeAAUKDQ1tAgAZAQA1AAQKfzUAAh4ACgrLHBcDAGwCAB4ACgrLHBcDAGwCAAAA.',
In='Interestelar:BAAANQADCgYIBgAAAA==.Invisiblelol:BAAANQAECgUIDAAAAA==.',
Ir='Irmãodouther:BAAANQAECgUJBQAAAA==.Irridan:BAAANQADCggICQAAAA==.',
Is='Isenhearth:BAAANQABCgUIBQAAAA==.Ishtarie:BAABNQAECn8dAAIfAAgKYx8MLwClAgAfAAgKYx8MLwClAgAAAA==.',
It='Itokeszdan:BAAANQAECgEIAQAAAA==.',
Iv='Ivina:BAABNQAECn9BAAMcAAoKqh1tEQCdAgAcAAoKqh1tEQCdAgAgAAEKjwasMwAsAAAAAA==.',
Iz='Izaar:BAAANQAECgEIAQAAAA==.',
Ja='Jangeoffry:BAAANQAECgEIAQAAAA==.Jayser:BAAANQAECgEIBQAAAA==.',
Jh='Jhonatinha:BAAANQAECgUICAAAAA==.',
Jk='Jks:BAAANQAECgcIBwAAAA==.',
Ju='Jullianxd:BAAANQAECgUIDQAAAA==.Junjih:BAAANQAECgUIBQABNQAECgkJFgAcAOcQAA==.',
Ka='Kaallew:BAAANQAECggIEAAAAA==.Kaallmonge:BAAANQAECgEIAQAAAA==.Kaelonidas:BAAANQAECgQIDgAAAA==.Kaelyaa:BAAANQADCgUIBQAAAA==.Kainer:BAAANQADCgYICQAAAA==.Kalazshar:BAABNQAECn8fAAINAAkKowqRKQBKAQANAAkKowqRKQBKAQAAAA==.Kalduran:BAAANQADCggIPQAAAA==.Kalelzinho:BAAANQADCgYICgAAAA==.Kaluss:BAABNQAECn8kAAMMAAgKVglB6QC3AQAMAAgK1whB6QC3AQAWAAEKbwsmLgAvAAAAAA==.Kanduz:BAAANQAECgUICQAAAA==.Kantaa:BAAANQAECgIICAAAAA==.Karlariel:BAAANQAECgUIBQABNQAECgYIEwACAAAAAA==.Karmabb:BAAANQAECgUIDAAAAA==.Kauss:BAAANQAECgIJAgAAAA==.Kavartu:BAABNQAECn8yAAMSAAoK7xgvJwDLAQASAAoK7xgvJwDLAQAfAAEK5QD23gARAAAAAA==.Kayli:BAAANQAECgEIBAAAAA==.Kaysa:BAAANQAECgEIAQAAAA==.',
Ke='Keillor:BAABNQAECn8nAAMfAAYK5hLPTgBbAQAfAAYK5hLPTgBbAQASAAUKQwvxwAAQAQAAAA==.Keldorian:BAAANQAECgIIAgAAAA==.Kenzou:BAABNQAECn8hAAIYAAcKyB0WBwCMAQAYAAcKyB0WBwCMAQAAAA==.Keytymari:BAAANQAECgUICwAAAA==.',
Kh='Khaliq:BAABNQAECn8kAAIKAAkKyBQRIACVAQAKAAkKyBQRIACVAQAAAA==.Khallani:BAAANQADCgIIAgABNQAECgIIBQACAAAAAA==.',
Ki='Kieran:BAAANQADCgYIBgAAAA==.Kimashi:BAAANQAECgIIAwAAAA==.Kissme:BAABNQAECn8qAAMTAAoKPxB3MwB/AQATAAkKeQ93MwB/AQAXAAYK5AlaYwBBAQAAAA==.Kitamor:BAABNQAECn81AAMXAAoKZQfPJABeAQAXAAoKaAbPJABeAQANAAQKcwnvSwB5AAAAAA==.',
Kl='Kletian:BAAANQAECgEIAQABNQAECgoKNgAPAIUgAA==.',
Ko='Koriakin:BAAANQAECgYIBwAAAA==.Korogth:BAAANQAECgYIDQAAAA==.Kosmo:BAABNQAECn8gAAIgAAcKihVuCQDsAQAgAAcKihVuCQDsAQAAAA==.',
Kr='Krisyum:BAAANQAECgEIAQAAAA==.Krosmu:BAAANQADCgcIBgAAAA==.Kräsus:BAAANQADCgQIBAABNQAECggIJgAYANMgAA==.',
Ku='Kurado:BAAANQAECgIIAwAAAA==.',
Ky='Kyrysa:BAAANQAECgEIAwAAAA==.Kyrïn:BAAANQADCgUIBQABNQAFFAYIDwAZAMkWAA==.',
Kz='Kzinn:BAAANQAECgEIAQAAAA==.',
['Kæ']='Kæs:BAAANQADCgUIBQAAAA==.',
['Kö']='Körn:BAAANQAECgQIBwABNQAECgoKJwAfAEQTAA==.',
La='Ladyrichter:BAAANQAECgEIAgAAAA==.Laetus:BAABNQAECn8hAAIMAAoK/RkJTgDlAgAMAAoK/RkJTgDlAgAAAA==.Lagerthaloth:BAAANQADCgUIBAAAAA==.Laiander:BAABNQAECn8bAAIXAAgKXg2lLQAiAQAXAAgKXg2lLQAiAQAAAA==.Laiany:BAABNQAECn80AAILAAkKaR9MHgD4AgALAAkKaR9MHgD4AgAAAA==.Lainarning:BAAANQAECgEIAgAAAA==.Lani:BAAANQAECgIIBAAAAA==.Laolong:BAAANQADCgYIBgAAAA==.',
Le='Leeloo:BAAANQAECgEIAQAAAA==.Leeoncamillo:BAAANQADCgYIBgABNQAECgYIGAADAEYFAA==.Leetohro:BAABNQAECn8UAAIRAAcK4AP4kwC4AAARAAcK4AP4kwC4AAAAAA==.Leodoros:BAABNQAECn8jAAIMAAcKAAuVKgFFAQAMAAcKAAuVKgFFAQAAAA==.Leric:BAAANQAECgMIBAAAAA==.Lewellin:BAAANQADCgcICgAAAA==.Leyviosa:BAAANQAECgEIAgAAAA==.',
Lh='Lhwei:BAAANQAECgcICAABNQAECgoKRgAJAP4lAA==.',
Li='Lichkíng:BAABNQAECn8WAAMDAAYKxAjdbwDfAAADAAYKxAjdbwDfAAAEAAIK2gRT0wBHAAAAAA==.Lifeisalie:BAAANQAECgQIBAAAAA==.Lighty:BAAANQADCgQICAAAAA==.Lihr:BAAANQADCggIEAAAAA==.Lijiang:BAABNQAECn8mAAIYAAgK0yBUBgDpAgAYAAgK0yBUBgDpAgAAAA==.Lilianpotter:BAAANQADCgYIBgAAAA==.Lilibel:BAAANQAECgEIBgAAAA==.Lillit:BAAANQAECgUIEQAAAA==.Lindaah:BAAANQAECgEIAgAAAA==.Lindapriesty:BAAANQADCgIIAgAAAA==.Lislfox:BAABNQAECn8kAAINAAkKOhynEABWAgANAAkKOhynEABWAgAAAA==.',
Ll='Lledritch:BAAANQAECgEIAQAAAA==.',
Lm='Lmmds:BAAANQADCgcIEwAAAA==.',
Lo='Lockdown:BAABNQAECn89AAIcAAoKZBQkKgAJAgAcAAoKZBQkKgAJAgAAAA==.Loukou:BAAANQAECgEIBAAAAA==.',
Lu='Luacs:BAABNQAECn8nAAQfAAoKRBPHZwDVAQAfAAgKMRPHZwDVAQAhAAgK2Rh6DQC6AQASAAIKfgk3DwFtAAAAAA==.Luccoa:BAAANQAECgcIEQABNQAECggIJgAYANMgAA==.Lucileia:BAAANQAECgEIAQAAAA==.Lucyfary:BAAANQADCgcICAAAAA==.Luhhrogue:BAAANQAECgMIBAAAAA==.Lunirah:BAAANQADCgYICAAAAA==.Luxwind:BAAANQAECgEIAgAAAA==.',
Ly='Lylka:BAABNQAECn81AAMQAAkKQSVdFwCJAgAQAAcKxyRdFwCJAgAFAAkK2yETBwBwAgAAAA==.',
['Lé']='Léofar:BAABNQAECn8dAAIFAAgKcAP4PgAAAQAFAAgKcAP4PgAAAQAAAA==.',
['Lü']='Lücyfer:BAAANQAECgMIBgAAAA==.',
['Lÿ']='Lÿcanthrøpe:BAAANQAECgEIAQAAAA==.',
Ma='Maanu:BAAANQADCgUIBQABNQAECgEIAgACAAAAAA==.Maeghann:BAAANQADCgQIAwAAAA==.Magostosaa:BAAANQAECgEIBAAAAA==.Makani:BAAANQAECgEIAwAAAA==.Malewolyyc:BAABNQAECn8xAAMLAAoKfR+nHQD6AgALAAoKfR+nHQD6AgABAAQK2w2pTwDTAAAAAA==.Massafera:BAABNQAECn8kAAIGAAgK2BG9nADpAQAGAAgK2BG9nADpAQAAAA==.Mathfacbruxo:BAAANQADCgYJBgABNQAECggIIQAPAH8gAA==.Mathfacii:BAABNQAECn8hAAIPAAgKfyDlLgDgAgAPAAgKfyDlLgDgAgAAAA==.Mayanyy:BAAANQAECgEIAQAAAA==.',
Mc='Mcq:BAAANQAECgEIBAAAAA==.',
Md='Mdrdark:BAABNQAECn8tAAIEAAoKLBu5EAAVAgAEAAoKLBu5EAAVAgAAAA==.',
Me='Medz:BAABNQAECn8kAAIMAAgKzBgoWACkAQAMAAgKzBgoWACkAQAAAA==.Meetjack:BAAANQAECgEIAwAAAA==.Meinstein:BAAANQAECgEIBQAAAA==.Meizu:BAAANQAECgQJDgAAAA==.Mellkor:BAABNQAECn8pAAIKAAcKWhojMgAZAgAKAAcKWhojMgAZAgAAAA==.Meneláu:BAAANQADCggICAAAAA==.Metamorful:BAAANQAECggIEQAAAA==.',
Mi='Mihsi:BAAANQAECgQIBAAAAA==.Milim:BAABNQAECn8eAAQiAAoKwAtLDQAGAQAiAAkKUQxLDQAGAQAjAAQKZwZBFgDNAAAkAAIKZwLMUQApAAAAAA==.Minilock:BAAANQAECgQIBgAAAA==.Mistogunn:BAAANQADCggICAAAAA==.Mitchell:BAAANQAECgEIAgABNQAECgEIAwACAAAAAA==.',
Ml='Mls:BAAANQADCgYICwAAAA==.',
Mm='Mmarcão:BAAANQAECgQIBwAAAA==.',
Mo='Modes:BAABNQAECn8kAAIRAAkKvxqDJwCDAgARAAkKvxqDJwCDAgAAAA==.Moffir:BAAANQADCgYIBgAAAA==.Mogrus:BAAANQAECgEIAQAAAA==.Mohanninha:BAAANQAECgUIBQAAAA==.Mohotok:BAABNQAECn8tAAIGAAkKFgqueQBeAQAGAAkKFgqueQBeAQAAAA==.Monshiro:BAAANQAECgEIAQABNQAECgoKFAAMAFwQAA==.Morkath:BAAANQADCggICAAAAA==.Mortank:BAAANQAECgEIAQABNQAECgcIDgACAAAAAA==.Mortixxia:BAABNQAECn8hAAMbAAYKUx26DgAPAgAbAAYKUx26DgAPAgAcAAIKDQ5B5gA6AAAAAA==.',
Mu='Murano:BAABNQAECn8nAAIOAAkK1xaRCABbAgAOAAkK1xaRCABbAgAAAA==.',
['Má']='Máia:BAAANQAECgcIEQAAAA==.',
['Mä']='Mändosz:BAABNQAECn8gAAIDAAgKHRkVKABXAgADAAgKHRkVKABXAgAAAA==.',
['Mé']='Ménace:BAAANQAECgIIBAABNQAECggIEAACAAAAAA==.',
['Mÿ']='Mÿstyna:BAAANQAECgEIAQAAAA==.',
Na='Nagts:BAAANQADCggICgAAAA==.Nalathiel:BAAANQAECgYICAAAAA==.Narancia:BAABNQAECn8UAAIMAAoKXBA2OAASAgAMAAoKXBA2OAASAgAAAA==.Narrih:BAAANQAECgIIBQAAAA==.Nazawill:BAAANQADCgQIBAAAAA==.Nazdru:BAAANQAECgEIAQABNQAECgkJNwAUANocAA==.Nazzh:BAAANQAECggIDAABNQAFFAUICAAHAN8XAA==.',
Ne='Nefas:BAAANQAECgcIDgAAAA==.Nepthunus:BAABNQAECn8sAAIlAAkKQxiwAQCDAgAlAAkKQxiwAQCDAgAAAA==.',
Ni='Niiz:BAAANQAECggICAAAAA==.Ninde:BAAANQADCggIDgAAAA==.',
No='Notforall:BAAANQADCgIIAgAAAA==.',
['Nï']='Nïix:BAAANQADCgYIBgAAAA==.',
['Nö']='Nöirr:BAAANQAECgEIAgAAAA==.',
Od='Odestruidor:BAAANQAECgUIDAAAAA==.',
Oi='Oioimiguel:BAAANQAECgEIAQAAAA==.',
Ol='Oluss:BAABNQAECn8iAAMQAAoKhBETWgALAgAQAAoKhBETWgALAgAGAAEKtwddqQEyAAABNQAECgoKRgAPAEQjAA==.',
On='Onys:BAAANQADCgIIAgAAAA==.',
Oo='Oob:BAAANQAECgcIDAAAAA==.',
Op='Opus:BAABNQAECn8bAAMQAAgKcBJwZADrAQAQAAgKcBJwZADrAQAFAAUKSAWRTQCyAAAAAA==.Opusbergen:BAAANQADCgQIBAAAAA==.',
Or='Origon:BAAANQADCggICwAAAA==.Orillan:BAABNQAECn8uAAIKAAkKCxRsJABxAQAKAAkKCxRsJABxAQAAAA==.Ornsteinsnow:BAAANQAECgEIAQAAAA==.Orsonn:BAABNQAECn8YAAIQAAcKXg4FogBAAQAQAAcKXg4FogBAAQAAAA==.Orucão:BAAANQABCgEIAQAAAA==.Oruism:BAAANQAECgYIBQAAAA==.Orukam:BAABNQAECn8YAAMTAAkKlQy7NAB1AQATAAkKlQy7NAB1AQAXAAIKMgjaoABcAAAAAA==.Orukanorum:BAAANQAECgEIAQAAAA==.Orukrente:BAAANQAECgEIAQAAAA==.Orulord:BAAANQABCgIIAwAAAA==.Orurage:BAAANQABCgYIBAAAAA==.',
Pa='Palaha:BAAANQAECgYICgABNQAECgoKRgAPAEQjAA==.Palatina:BAABNQAECn8gAAIGAAkKyx00OQDsAgAGAAkKyx00OQDsAgABNQAECgkJMgAGAAckAA==.Pandalokodj:BAAANQAECgEIAQAAAA==.Pangedrey:BAABNQAECn8zAAMVAAoKJxl3DAArAgAVAAoKJxl3DAArAgAJAAEKRxWHSgA9AAAAAA==.Parcival:BAAANQAECgEIAQAAAA==.Parký:BAAANQAECggIEQAAAA==.Paullk:BAAANQAECgEIBwAAAA==.',
Pe='Penseur:BAAANQABCgYJBgAAAA==.Peruchi:BAAANQADCgIIAgAAAA==.Perísdra:BAAANQAECgEIAQABNQAECgQIEAACAAAAAA==.',
Pg='Pgms:BAAANQADCggIEgAAAA==.',
Pi='Picu:BAAANQADCgUICQAAAA==.Pitombinha:BAABNQAECn8hAAMOAAkK9R2pCgAdAgAOAAcK0h2pCgAdAgAHAAQKZRmmnQDQAAAAAA==.Pixiks:BAAANQABCgYIBwAAAA==.',
Pp='Ppandora:BAAANQADCgUICgAAAA==.',
Pr='Predadore:BAAANQADCgUIBQAAAA==.',
Pu='Pussytrix:BAAANQAECgcIBwAAAA==.',
Py='Pyrix:BAAANQADCgIIAgAAAA==.',
['Pä']='Pändero:BAAANQAECgEIAQAAAA==.',
['Pî']='Pîo:BAACNQAFFH8FAAIMAAQKRww4LAAtAQAMAAQKRww4LAAtAQA1AAQKfzgAAgwACgrBIQ0sADcDAAwACgrBIQ0sADcDAAAA.',
Qu='Quirow:BAABNQAECn8uAAISAAkKiQ5tOwBnAQASAAkKiQ5tOwBnAQAAAA==.',
Ra='Radiação:BAAANQAECgMIAwAAAA==.Radunz:BAABNQAECn83AAMUAAkK2hzcBQAhAgAUAAkK2hzcBQAhAgATAAMKlhURTgDTAAAAAA==.Ragnaros:BAAANQAECgQIBQAAAA==.Ragnarssön:BAAANQAECgQIBwAAAA==.Ragnarøk:BAAANQABCggICgAAAA==.Raio:BAABNQAECn85AAIMAAoKUhxcKwBFAgAMAAoKUhxcKwBFAgAAAA==.Ramorey:BAAANQAECgQICQAAAA==.Ramsez:BAAANQAECgEIAQAAAA==.Ranruulfnarm:BAAANQAECgEIAQAAAA==.Rargsa:BAAANQAECgUIEQAAAA==.Rargul:BAAANQAECgIIAwAAAA==.Rariel:BAABNQAECn8ZAAIKAAoKyxH+JwBYAQAKAAoKyxH+JwBYAQAAAA==.Raymain:BAABNQAECn8lAAQJAAkKUBrFGQDjAQAJAAgKFBnFGQDjAQAVAAkKLBdyKQDSAQAYAAEKUgN1IAAiAAAAAA==.Raíka:BAAANQADCggIDQAAAA==.',
Re='Rebimboca:BAAANQAECgEIBAAAAA==.Redoon:BAAANQAECgIIAgAAAA==.Rendoras:BAAANQAECgEIAQAAAA==.Rezadeiro:BAAANQAECgEIAQAAAA==.',
Rh='Rhaumarhu:BAAANQADCgYIDAAAAA==.',
Ro='Rockit:BAAANQADCgMICAAAAA==.Rodbree:BAABNQAECn8rAAMQAAoKLiFrDQBeAwAQAAoKLiFrDQBeAwAGAAIKAADEbwFuAAAAAA==.Roguinhu:BAAANQAECgcIEAAAAA==.Roseangel:BAAANQABCgEIAQAAAA==.',
Ru='Rubian:BAAANQADCgYIDAAAAA==.Rudan:BAAANQAECgEIAgAAAA==.Rurumo:BAAANQAECgEIAgAAAA==.Rustovick:BAAANQAECgUIDAAAAA==.',
['Rä']='Rämzä:BAAANQAECgEIAQABNQAECggIFAANAIIPAA==.',
['Rå']='Råy:BAABNQAECn8rAAMEAAoKLBwtJwCfAgAEAAoKLBwtJwCfAgADAAEKkg48qwA3AAAAAA==.',
Sa='Saalla:BAAANQAECgEIAgABNQAECgkJNwAUANocAA==.Saffír:BAABNQAECn8mAAIGAAkKThNijgAIAgAGAAkKThNijgAIAgAAAA==.Sahkev:BAAANQAECgIIAwAAAA==.Samalandraa:BAABNQAECn8YAAMSAAgK/g17TwAfAQASAAcKWg97TwAfAQAhAAIK1AX3IwBxAAAAAA==.Sanateia:BAAANQAECgEIAgAAAA==.Saniest:BAABNQAECn8fAAMBAAoKeh3EEwDJAgABAAkKQB3EEwDJAgALAAUKEh7PjQC3AAAAAA==.Sapekinhä:BAABNQAECn8aAAIKAAkKVhWgLgAxAgAKAAkKVhWgLgAxAgAAAA==.Satanvitória:BAAANQAECgYIEQAAAA==.Saturio:BAAANQAECgEIAQAAAA==.',
Se='Segavaxx:BAAANQABCgQIBAAAAA==.Seilaa:BAAANQAECgIIBQAAAA==.Selorixie:BAAANQAECgYIEgABNQAECgYIIQAbAFMdAA==.Sereiaa:BAAANQAECgYIEQAAAA==.',
Sh='Shamate:BAAANQAECgUIAwAAAA==.Shanoa:BAAANQAECgQIBQAAAA==.Sharae:BAAANQADCggIDQAAAA==.Shedo:BAABNQAECn8YAAMHAAkKohkEeQAsAgAHAAgKohkEeQAsAgAOAAIKUhqzJwBvAAAAAA==.Shonja:BAAANQAECgMIAwAAAA==.Shula:BAAANQADCgYIBgAAAA==.',
Si='Sialeeds:BAAANQAECgEIAgAAAA==.Siclop:BAAANQAECgIIAgAAAA==.Simplicity:BAABNQAECn8aAAMLAAgKwBdCZADzAQALAAgKwBdCZADzAQABAAMKbxJoVwCtAAAAAA==.Sinton:BAAANQABCgIIAgAAAA==.',
Sk='Skadrian:BAAANQAECgQIBAAAAA==.Skadryan:BAAANQAECgQICwAAAA==.Skalnark:BAAANQAECgUIEgAAAA==.Skinme:BAAANQAECgEIAQAAAA==.Skysoul:BAAANQAECgEJAwAAAA==.',
Sl='Sleeppanda:BAAANQAECgEIAgABNQAECgoKSwAYADYbAA==.',
So='Sofiela:BAAANQAECgIIAgAAAA==.Soijiro:BAAANQADCgIIAgAAAA==.Soju:BAAANQADCgIIAgAAAA==.Sol:BAAANQADCgQIBAAAAA==.Sombrea:BAAANQAECgEIAgAAAA==.',
Sp='Spectrø:BAAANQADCgcIFAAAAA==.',
Ss='Sstrange:BAAANQADCggICQAAAA==.',
St='Starkz:BAAANQADCgUIBQAAAA==.Stëlla:BAABNQAECn8tAAIfAAoKtxrrGQByAgAfAAoKtxrrGQByAgAAAA==.',
Su='Suckmyhammer:BAAANQAECgcIDgAAAA==.Sungjinwoo:BAAANQAECgYIEgAAAA==.Sunnara:BAABNQAECn8hAAImAAoKIBzxFQC0AgAmAAoKIBzxFQC0AgAAAA==.',
Sy='Syuon:BAABNQAECn9GAAIJAAoK/iVIAAA9BAAJAAoK/iVIAAA9BAAAAA==.',
Sz='Szaa:BAAANQADCgQIBwAAAA==.',
Ta='Taelin:BAAANQAECgEIAQAAAA==.Talandar:BAABNQAECn9DAAIXAAoKoRgeEQA3AgAXAAoKoRgeEQA3AgAAAA==.Tankoso:BAAANQADCgcIBgABNQADCggICQACAAAAAA==.Tankudo:BAABNQAECn8rAAMEAAkK8Ba3GQCpAQAEAAkK8Ba3GQCpAQARAAIK4xdZdQBIAAAAAA==.Tapuloka:BAAANQAECgEIAQAAAA==.',
Te='Tennebra:BAAANQADCggICQAAAA==.',
Th='Thabitah:BAABNQAECn83AAIBAAkKwhOzEADCAQABAAkKwhOzEADCAQAAAA==.Thanathus:BAAANQAECgIICAAAAA==.Thaumiel:BAAANQADCgEIAQAAAA==.Thedragon:BAABNQAECn8xAAMPAAoKYR5/EQDDAgAPAAoKYR5/EQDDAgAnAAEKAQspTAA5AAAAAA==.Thorkel:BAAANQAECgIIAwAAAA==.Thotamon:BAAANQAECgIIAgAAAA==.Thýah:BAAANQAECgUIBwAAAA==.',
Ti='Tidim:BAAANQADCgcIDQAAAA==.Tiih:BAAANQABCgUIBwAAAA==.',
To='Tonypaludo:BAAANQAECgEIAwAAAA==.',
Tr='Trueperceval:BAAANQAECgEIAQAAAA==.',
Ts='Tsukii:BAAANQAECgEIAQAAAA==.',
Tu='Tushui:BAAANQAECgEIAQAAAA==.',
Us='Usfull:BAABNQAECn8kAAMLAAkKAhhuWwAPAgALAAkKAhhuWwAPAgABAAIKsQOhagBYAAAAAA==.',
Va='Vaatu:BAAANQADCgMIBAAAAA==.Vaeltor:BAAANQAECggIBAAAAA==.Valegás:BAAANQAECgEIAQAAAA==.Vallkÿria:BAAANQAECgcICwAAAA==.Varrex:BAAANQAECgEIAQAAAA==.Vaëllen:BAABNQAECn8iAAMNAAgKpQhKJgDbAAANAAgKpQhKJgDbAAAXAAEKAAC7wAAhAAAAAA==.',
Ve='Vehuguito:BAAANQAECgEIAQABNQAECgkJFQAQAH4TAA==.Vehuiáh:BAABNQAECn8VAAIQAAkKfhMyaQDcAQAQAAkKfhMyaQDcAQAAAA==.Velen:BAABNQAECn81AAMEAAoKexv2EAASAgAEAAoKexv2EAASAgADAAEKswh9iwAzAAAAAA==.Verno:BAAANQAECgIIAgAAAA==.Verzuk:BAAANQAECgUIDQAAAA==.',
Vi='Vintejulgar:BAAANQAECgEIAgAAAA==.Vintekilo:BAABNQAECn8dAAIGAAoKKgyunADpAQAGAAoKKgyunADpAQAAAA==.Vinteservir:BAAANQAECgEIAQAAAA==.',
Vo='Voiddh:BAACNQAFFH8FAAImAAUKrgU9BwC7AAAmAAUKrgU9BwC7AAA1AAQKfyYAAiYACgrxEzElAB0CACYACgrxEzElAB0CAAAA.Vortiaz:BAAANQAECgEIAwABNQAECggIDQACAAAAAA==.',
Vr='Vrenshrrgn:BAAANQAECgEIAwAAAA==.',
Vy='Vygh:BAABNQAECn81AAMcAAoK1B0lIgD7AgAcAAoK1B0lIgD7AgAbAAEKuAs4eQA0AAAAAA==.Vyndrill:BAABNQAECn8mAAIaAAkKuBT4HQDjAQAaAAkKuBT4HQDjAQAAAA==.',
['Vø']='Vølkan:BAAANQAECgEIBAAAAA==.',
Wa='Walkers:BAABNQAECn8qAAIPAAoKpxNyQQDeAQAPAAoKpxNyQQDeAQAAAA==.Warlaka:BAAANQADCgYICwAAAA==.',
We='Weevil:BAAANQADCgYICgAAAA==.',
Wo='Worgenbelfin:BAAANQADCggIDQAAAA==.',
Wy='Wyrel:BAAANQAECgEIAQAAAA==.',
Xa='Xalmoria:BAAANQAECgYIDAAAAA==.',
Xe='Xendor:BAAANQAECgEIAQAAAA==.',
Xu='Xurumeloun:BAAANQAECgEIAQAAAA==.',
Ya='Yamii:BAAANQAECgQIBgAAAA==.Yasmini:BAAANQABCgEIAQAAAA==.',
Yi='Yingsu:BAABNQAECn8ZAAMVAAoKohiCGACDAgAVAAoKPxiCGACDAgAYAAYK6RAHHAAmAQAAAA==.Yippwarr:BAAANQADCgMIBAAAAA==.',
Yu='Yunná:BAAANQAECgEIAQAAAA==.',
Yv='Yvin:BAAANQAECgIIBQAAAA==.',
Za='Zakir:BAAANQAECgQICQAAAA==.Zaolron:BAAANQADCgIIAQAAAA==.',
Ze='Zeddshm:BAAANQAECgEJAQABNQAECgoKLwAHAKgVAA==.Zeeno:BAAANQAECgEIAwAAAA==.',
Zh='Zhynah:BAAANQADCgUIBQAAAA==.',
Zi='Zibrautar:BAAANQADCgIIAgAAAA==.Ziracruz:BAAANQAECgQICAAAAA==.',
Zu='Zulyn:BAAANQADCgcIFwAAAA==.Zupen:BAAANQAECgEIAgAAAA==.',
['Àr']='Àrdath:BAAANQADCggIDgAAAA==.Àrthemís:BAAANQADCgEIAQAAAA==.',
['Ár']='Áraujo:BAAANQADCgEJAQABNQADCgUIBQACAAAAAA==.Árÿä:BAABNQAECn81AAIPAAkKfhBxRwDIAQAPAAkKfhBxRwDIAQAAAA==.',
['Áy']='Áy:BAAANQADCgIIAgAAAA==.',
['Är']='Äraxy:BAAANQAECgEIAQAAAA==.',
['Èv']='Èver:BAAANQADCgIIAgAAAA==.',
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
