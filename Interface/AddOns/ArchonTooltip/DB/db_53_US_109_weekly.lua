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

local lookup = {'Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Protection','Paladin-Retribution','Warrior-Arms','Warrior-Protection','Unknown-Unknown','Monk-Mistweaver','DemonHunter-Havoc','Priest-Holy','Mage-Arcane','Druid-Guardian','Warrior-Fury','Hunter-BeastMastery','DemonHunter-Vengeance','DeathKnight-Blood','Shaman-Elemental','Druid-Restoration','Druid-Feral','Monk-Windwalker','Mage-Frost','Druid-Balance','Monk-Brewmaster','Rogue-Subtlety','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','Priest-Discipline','Shaman-Restoration','Warlock-Affliction','Shaman-Enhancement','Paladin-Holy','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Mage-Fire','DemonHunter-Devourer','Hunter-Marksmanship',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abaca:BAAANQAECgIIAgAAAA==.Abacatte:BAAANQAECgQICAAAAA==.',
Ad='Adelaide:BAAANQADCgUIBwABNQAFFAgIGQABALoQAA==.',
Ae='Aelthor:BAAANQAECgEIAQAAAA==.',
Al='Alanie:BAAANQAECgYIBwAAAA==.Aleriastorm:BAAANQABCgIIAgAAAA==.Alessaxd:BAABNQAECn8cAAMCAAoKfg6iQwC1AQACAAoKpQ2iQwC1AQADAAUKUA3hNAAgAQAAAA==.Alfajhor:BAABNQAECn9DAAMEAAoKHCWPAgCjAwAEAAoKHCWPAgCjAwAFAAEKAADeoQEAAAAAAA==.Alfajhòr:BAAANQAECgEIAQAAAA==.Alfajhõr:BAAANQAECgYICwAAAA==.Alkaid:BAABNQAECn8uAAMGAAoKphfBQQAPAgAGAAkKjRfBQQAPAgAHAAgK+gsTIwAxAQAAAA==.Alladryel:BAAANQADCgYIBgAAAA==.Allandriel:BAAANQAECgIIAgABNQAECgYIEgAIAAAAAA==.Alleriane:BAABNQAECn8pAAIJAAoK2huDDwCIAgAJAAoK2huDDwCIAgAAAA==.Allone:BAABNQAECn86AAIKAAoKTA7UJwCQAQAKAAoKTA7UJwCQAQAAAA==.Allunt:BAAANQAECgcICgAAAA==.Almin:BAAANQAECgIIBgAAAA==.Alruna:BAAANQAECgIIAgAAAA==.',
Am='Ametnys:BAAANQAECgUICgAAAA==.Amonhar:BAAANQAECgUIBQABNQAECgkJJgALADcYAA==.',
An='Anakata:BAAANQAECgcIDQAAAA==.Andaliz:BAABNQAECn8yAAIFAAkKByR9BwC+AwAFAAkKByR9BwC+AwAAAA==.Andaril:BAAANQAECgUICQAAAA==.Antonel:BAAANQABCgYIBgAAAA==.Antonellaes:BAAANQAECgEIAQABNQAECgcIGQACAPgEAA==.',
Ap='Aprocom:BAAANQAECgUICAAAAA==.',
Ar='Arcanör:BAABNQAECn8bAAIMAAgKsg0D9QChAQAMAAgKsg0D9QChAQAAAA==.Arctorius:BAABNQAECn8XAAMFAAcKaQxe0AB7AQAFAAcKaQxe0AB7AQAEAAEKAADzdgAmAAAAAA==.Aronys:BAAANQAECgYIEAAAAA==.Arquitetö:BAAANQADCgIIAgAAAA==.Arthashand:BAAANQADCgEIAQAAAA==.Artronis:BAABNQAECn8xAAINAAoKHhP6EwAkAgANAAoKHhP6EwAkAgAAAA==.Arukäi:BAABNQAECn8hAAMGAAgKxwr0qwCvAQAGAAgKxwr0qwCvAQAOAAMKgQdWKQBlAAAAAA==.Arägørn:BAAANQAECgUIEQAAAA==.',
As='Assintomatic:BAAANQABCgYICQABNQAECggIEQAIAAAAAA==.',
At='Atriuz:BAAANQAECgQIDAAAAA==.Ats:BAAANQADCggIEQAAAA==.',
Au='Aurín:BAAANQADCgQIBAAAAA==.',
Ay='Ayrthwill:BAAANQAECgEIAgAAAA==.',
Az='Azarado:BAAANQAECggIBwAAAA==.Azerotiano:BAAANQAECgQIDwAAAA==.',
['Aÿ']='Aÿ:BAAANQAECgEIAQAAAA==.',
Ba='Badhealer:BAAANQAECgYIDwAAAA==.Baldraccus:BAAANQADCgcIBwAAAA==.Balk:BAABNQAECn88AAIPAAoKvyBZIAAWAwAPAAoKvyBZIAAWAwAAAA==.Bambur:BAAANQADCggICgAAAA==.Barauna:BAAANQABCgIIAgAAAA==.Barbabruto:BAABNQAECn8lAAMHAAoKfhpECwCIAgAHAAoKShlECwCIAgAOAAIKRxxDGwCaAAAAAA==.Barbacancer:BAAANQAECgUIBgAAAA==.Barbalock:BAAANQADCggICAAAAA==.Barbaogro:BAAANQAECgEIAgAAAA==.Barbasanta:BAAANQAECgQICAABNQAECgoKJQAHAH4aAA==.Batgirl:BAABNQAECn8YAAMQAAoKaw0/DgAuAQAQAAgKIgw/DgAuAQAKAAcKpQ0hPgAEAQAAAA==.',
Be='Belthorsin:BAAANQADCgYIBgAAAA==.Belthorvil:BAAANQADCgEIAQAAAA==.',
Bi='Bigbag:BAAANQADCgQIBQAAAA==.Biønic:BAAANQAECgUIEQAAAA==.',
Bl='Blackmoonx:BAABNQAECn8VAAICAAkK2BjLKgBFAgACAAkK2BjLKgBFAgABNQAECggIFwAGAGIiAA==.Blackninja:BAAANQABCggIGwAAAA==.Blu:BAEANQAECgEIAQABNQAECgYIEQAIAAAAAA==.',
Bo='Box:BAAANQADCgMIAwAAAA==.',
Br='Brahman:BAAANQAECgEIAQAAAA==.Bratloko:BAAANQADCgMIAwAAAA==.Bright:BAAANQADCgYIBgAAAA==.Brinston:BAAANQADCgQIBAABNQAFFAUIBwALALcNAA==.Bruex:BAAANQADCgIIAgAAAA==.Bruker:BAAANQADCgIIAwAAAA==.Brutalhoof:BAAANQAECgEIBQAAAA==.',
Bu='Buzzumaaky:BAABNQAECn8VAAIMAAcKPhdYuAATAgAMAAcKPhdYuAATAgAAAA==.',
By='Bynhu:BAAANQADCggICAAAAA==.',
['Bá']='Bávor:BAAANQADCgEIAQAAAA==.',
['Bí']='Bílly:BAAANQAECgEIAQAAAA==.',
Ca='Calteryeker:BAAANQAECgMIDAAAAA==.Capitu:BAAANQADCggIEwABNQAECgkJJgARAL8aAA==.Capyvara:BAAANQABCgYIBwAAAA==.Caralh:BAACNQAFFH8FAAIRAAQKfg9MJABsAAARAAQKfg9MJABsAAA1AAQKfy8AAxEACgrEHasRAB8DABEACQq+IKsRAB8DAAMAAQrxCFx7ADUAAAAA.Caroll:BAAANQADCgMIAwAAAA==.Caçaorda:BAAANQAECgMJBAAAAA==.',
Ce='Ceciliah:BAACNQAFFH8OAAISAAQKxwlTEADOAAASAAQKxwlTEADOAAA1AAQKf0QAAhIACgqMIr8PANMCABIACgqMIr8PANMCAAAA.Cernûnnos:BAABNQAECn8YAAMTAAYK3RfpMAAjAQATAAYK3RfpMAAjAQAUAAEKAABETQAdAAAAAA==.',
Ch='Champdude:BAABNQAECn8/AAMVAAoK6hsKEgANAgAVAAkKzR4KEgANAgAJAAkK+w+vDwDYAQAAAA==.Chopquatro:BAAANQADCggICAAAAA==.Chopum:BAAANQAECggICAAAAA==.Chrnnos:BAAANQAECgYICQABNQAECgkJIgAOAPweAA==.',
Co='Corineus:BAAANQADCgYIDQAAAA==.Cowzeroth:BAABNQAECn84AAISAAoKbSAlEQDFAgASAAoKbSAlEQDFAgABNQAECgoKPAAPAL8gAA==.',
Cr='Crassustitan:BAAANQAECggICQAAAA==.Cristcalad:BAABNQAECn8kAAMHAAcKqxNLIgA4AQAHAAYKTxZLIgA4AQAGAAcKSQ2NkAAqAQAAAA==.',
Cu='Cutia:BAAANQAECgEIAQAAAA==.',
Da='Daemi:BAAANQAECggIEAAAAA==.Dakael:BAAANQAECgEIAQABNQAECgoKQAAUAEYdAA==.Dalaty:BAAANQAECgUIEgAAAA==.Daresh:BAAANQADCgEIAQAAAA==.Dariok:BAABNQAECn8hAAIGAAgK4QTksQDfAAAGAAgK4QTksQDfAAAAAA==.Darkove:BAABNQAECn8qAAIWAAoKHRAsDQDgAQAWAAoKHRAsDQDgAQAAAA==.Darrow:BAABNQAECn8yAAICAAoKVRVsNAALAgACAAoKVRVsNAALAgAAAA==.Daryan:BAAANQAECgcIDwAAAA==.Day:BAAANQAECgQIBQAAAA==.',
De='Deathinhu:BAABNQAECn9BAAIMAAoKKB+BKgB3AgAMAAoKKB+BKgB3AgAAAA==.Demoriana:BAABNQAECn8ZAAMCAAcK+AQ1fQCzAAACAAcKHQQ1fQCzAAARAAQKbwR2fQBWAAAAAA==.Dethroned:BAAANQAECgQICgAAAA==.',
Di='Diefs:BAAANQAECgEIAQABNQAECgkJJgALADcYAA==.Digaolock:BAAANQAECgEIAQAAAA==.Digaoxdrx:BAAANQADCgQIBAAAAA==.Dimeros:BAABNQAECn9DAAIXAAoK2gvgJgCOAQAXAAoK2gvgJgCOAQAAAA==.Divano:BAABNQAECn9AAAIBAAoK9x6/CwAqAwABAAoK9x6/CwAqAwAAAA==.',
Dk='Dkats:BAAANQADCggIDAAAAA==.Dkhalifa:BAAANQADCgYIBgAAAA==.',
Do='Dogowner:BAAANQAECgcIBwAAAA==.Donora:BAAANQAECgQIBAAAAA==.Dorfillaw:BAAANQAECgUICQAAAA==.Dorvana:BAAANQADCgMJAwABNQAECgkJMgAFAAckAA==.',
Dr='Dracthyrius:BAAANQAECgEIAQAAAA==.Draenthar:BAAANQAECgEIAQAAAA==.Dragonstyle:BAAANQAECgcICwAAAA==.Dragony:BAAANQADCgQIBAAAAA==.Dreez:BAAANQAECgYICAAAAA==.Drexus:BAAANQADCgMIAwAAAA==.Drigolas:BAAANQADCgYICAAAAA==.Druidblack:BAAANQADCgUIBQAAAA==.',
Eh='Ehomi:BAAANQADCgIIAgAAAA==.',
Ei='Eirin:BAABNQAECn8eAAIYAAUK1xU/HQAUAQAYAAUK1xU/HQAUAQAAAA==.',
El='Eldris:BAAANQADCgEIAQAAAA==.Elidibus:BAAANQADCgQIBAAAAA==.Elistraee:BAAANQADCgEIAQAAAA==.Ellvarg:BAAANQADCgYIDAAAAA==.Eluuria:BAABNQAECn8fAAIFAAoKAhCQhwB9AQAFAAoKAhCQhwB9AQAAAA==.',
En='Enkrenco:BAAANQADCgQIBAAAAA==.Ennafaryn:BAAANQABCgQIBgAAAA==.Ensabanú:BAAANQADCgQIBAAAAA==.',
Er='Erilaethaen:BAAANQAECgIIAgAAAA==.Erlek:BAAANQADCggIFwAAAA==.Ernest:BAABNQAECn89AAITAAoKaSA+CAAcAwATAAoKaSA+CAAcAwAAAA==.Erulan:BAAANQADCgQIBwAAAA==.',
Es='Estgan:BAAANQADCgMIAwAAAA==.',
Et='Ether:BAABNQAECn8ZAAIRAAkKrRJRTQDAAQARAAkKrRJRTQDAAQAAAA==.',
Ev='Evangelouco:BAAANQADCgQIBAAAAA==.Evilbarba:BAACNQAFFH8FAAIFAAUK/guKFAASAQAFAAUK/guKFAASAQA1AAQKfzQAAgUACQo9Hf0vAHcCAAUACQo9Hf0vAHcCAAAA.',
Ex='Exodes:BAAANQAECgEIAgAAAA==.Exort:BAAANQAECgUICwAAAA==.Exothus:BAAANQAECgQJBwAAAA==.',
Fa='Faaver:BAAANQADCgMIAwAAAA==.Faldark:BAAANQADCgUIBQAAAA==.Fandrall:BAAANQADCggIFAAAAA==.Faranir:BAAANQADCggIEAAAAA==.Faris:BAABNQAECn81AAMZAAoK+RQJPgDAAQAaAAgKlBYxOAD2AQAZAAkKhREJPgDAAQABNQAECgoKPAAPAL8gAA==.Faversani:BAABNQAECn8qAAQGAAoKYiLvKgAQAwAGAAoKYiLvKgAQAwAOAAEKChtpJQBOAAAHAAEKCxj+NQBCAAAAAA==.Fayla:BAAANQADCgMIAwAAAA==.Faölin:BAABNQAECn8sAAIZAAoKCxeEEQBpAgAZAAoKCxeEEQBpAgAAAA==.',
Fe='Ferael:BAABNQAECn9DAAMFAAoKuB+SHwDDAgAFAAoKuB+SHwDDAgAEAAQKPQkPUACmAAAAAA==.Ferrus:BAAANQAECgQIAwAAAA==.',
Fj='Fjord:BAAANQAECgIIAgAAAA==.',
Fl='Florbela:BAABNQAECn8fAAITAAgKygvAMwB8AQATAAgKygvAMwB8AQAAAA==.',
Fo='Fogue:BAAANQADCgMIAwAAAA==.',
Fr='Fredericc:BAABNQAECn8WAAISAAgKjgrFcgD4AAASAAgKjgrFcgD4AAAAAA==.Freecs:BAABNQAECn8YAAMXAAgKrxvVFwAfAgAXAAgKrxvVFwAfAgAUAAIKtRrpJACYAAAAAA==.Freyá:BAABNQAECn80AAMEAAoKYxxlEACXAgAEAAoKYxxlEACXAgAFAAgKJREp3ABjAQAAAA==.Frostburn:BAAANQAECggIEQAAAA==.Froststriker:BAAANQAECgIIAgAAAA==.',
Fu='Fulvo:BAAANQADCgQIBQAAAA==.',
Ga='Gadodamorena:BAAANQAECgEIAQAAAA==.Galfur:BAABNQAECn8cAAIXAAUKOQeAfwDQAAAXAAUKOQeAfwDQAAAAAA==.Galhuda:BAAANQAECgYIEgAAAA==.Galica:BAAANQAECgEIAQAAAA==.Gallatheya:BAAANQAECgUIAQAAAA==.Gandwelf:BAAANQADCggICAAAAA==.',
Ge='Geisty:BAAANQAECgEIAQABNQAECgIIBAAIAAAAAA==.Gemius:BAAANQADCgMIAwAAAA==.',
Gl='Glutotwo:BAAANQADCgYIEgAAAA==.',
Go='Goldchain:BAAANQAECgcICgAAAA==.Govers:BAAANQAECgEIAQABNQAECggICwAIAAAAAA==.',
Gr='Grommar:BAAANQADCgUIBQABNQAECgMIDAAIAAAAAA==.Grumax:BAABNQAECn8YAAIFAAcKkAvs1wBsAQAFAAcKkAvs1wBsAQAAAA==.',
Gu='Gudeath:BAABNQAECn8vAAIGAAkKnxWJiAAHAgAGAAkKnxWJiAAHAgAAAA==.Guerrerinhow:BAAANQAECgcIDgABNQAECgoKLQAXAMsOAA==.Guitianki:BAAANQADCggIEgAAAA==.Gulek:BAAANQAECgYIBAAAAA==.Gussg:BAABNQAECn8nAAMbAAgKTBZcBQBqAQAbAAcKTBZcBQBqAQAcAAUKugjo4QAFAQAAAA==.',
['Gà']='Gàladriel:BAABNQAECn8VAAITAAYKQhV7JwBoAQATAAYKQhV7JwBoAQAAAA==.',
['Gö']='Göhan:BAABNQAECn8aAAINAAgKjBGsGgB2AQANAAgKjBGsGgB2AQAAAA==.',
['Gø']='Gøvers:BAAANQAECggICwAAAA==.',
['Gü']='Güttz:BAABNQAECn8gAAIKAAgK5RCCOwDaAQAKAAgK5RCCOwDaAQAAAA==.',
Ha='Hagires:BAAANQAECgYIBwAAAA==.Hanaluna:BAAANQADCggICAAAAA==.Harchus:BAAANQAECgEIAQAAAA==.Hargarthul:BAAANQADCgMIBAAAAA==.',
He='Heaveth:BAAANQADCgYIAgABNQAECgoKSgASAIwcAA==.Hellspont:BAABNQAECn8mAAQUAAkKnCEaDABnAgAUAAgKlSEaDABnAgATAAYK/xblIgCRAQANAAIKzxv/RgCVAAAAAA==.Hendrikison:BAAANQAECgMIAgAAAA==.',
Ho='Horagalles:BAAANQADCgIIAgAAAA==.Hotmojo:BAACNQAFFH8OAAIMAAUK6hb5IgDNAAAMAAUK6hb5IgDNAAA1AAQKf0cAAgwACgoUIqUhAJ4CAAwACgoUIqUhAJ4CAAAA.',
Hu='Hunfox:BAABNQAECn9VAAIPAAoKXyQTBwBBAwAPAAoKXyQTBwBBAwAAAA==.Hunterhearst:BAAANQADCgYIBwAAAA==.Huor:BAAANQAECgQIBAAAAA==.',
Hy='Hylana:BAAANQADCggICAAAAA==.',
['Hö']='Hölycrüsh:BAACNQAFFH8FAAIFAAMKgRuLFwDtAAAFAAMKgRuLFwDtAAA1AAQKf0UAAgUACgqJJOoMACkDAAUACgqJJOoMACkDAAAA.',
Ih='Ihntwuaed:BAAANQADCgQIBwAAAA==.',
Ik='Ikoo:BAABNQAECn8gAAIdAAoKuRj+AQCUAgAdAAoKuRj+AQCUAgAAAA==.',
Il='Illaril:BAACNQAFFH8aAAIQAAYKdAttAgAZAQAQAAYKdAttAgAZAQA1AAQKfzcAAhAACgrPHJEEAF0CABAACgrPHJEEAF0CAAAA.',
In='Indarion:BAAANQADCgQIBQAAAA==.Interestelar:BAAANQADCgYIBgAAAA==.Invisiblelol:BAAANQAECgUICgAAAA==.',
Ir='Irmãodouther:BAAANQAECgcIDQAAAA==.Irridan:BAAANQADCggICQAAAA==.',
Is='Isenhearth:BAAANQABCgUIBQAAAA==.Ishtarie:BAABNQAECn8fAAIeAAoKbR0MLwClAgAeAAoKbR0MLwClAgAAAA==.',
Iv='Ivina:BAABNQAECn9JAAMcAAoK+h0gGwCJAgAcAAoK+h0gGwCJAgAfAAEKjwasMwAsAAAAAA==.',
Iz='Izaar:BAAANQAECgEIAQAAAA==.',
Ja='Jangeoffry:BAAANQABCgMIAwAAAA==.Jayser:BAAANQAECgEIAwAAAA==.',
Jh='Jhonatinha:BAAANQAECgUIBwAAAA==.',
Jk='Jks:BAAANQAECgcICAAAAA==.',
Ju='Jullianxd:BAAANQAECgUIDAAAAA==.Junjih:BAAANQAECgUIBQABNQAECgkJFgAcAOcQAA==.',
Ka='Kaallew:BAAANQAECggIEQAAAA==.Kaallmonge:BAAANQABCgcIBwAAAA==.Kaelonidas:BAAANQAECgQIDAAAAA==.Kaelyaa:BAAANQADCgUIBQAAAA==.Kainer:BAAANQADCgYICQAAAA==.Kalazshar:BAABNQAECn8jAAINAAoKEAuRKQBKAQANAAoKEAuRKQBKAQAAAA==.Kalduran:BAAANQADCggIPQAAAA==.Kalelzinho:BAAANQADCgYICgAAAA==.Kaluss:BAABNQAECn8lAAMMAAkK9whB6QC3AQAMAAkKiwhB6QC3AQAWAAEKbwuPOAAtAAAAAA==.Kanduz:BAAANQAECgUICAAAAA==.Kantaa:BAAANQAECgIIBQAAAA==.Karlariel:BAAANQAECgUIBQABNQAECgYIEgAIAAAAAA==.Karmabb:BAAANQAECgUICgAAAA==.Kauss:BAAANQAECgIJAgAAAA==.Kavartu:BAABNQAECn82AAMSAAoKkhkTMwDSAQASAAoKkhkTMwDSAQAeAAEK5QAd/AAQAAAAAA==.Kayli:BAAANQADCgcIDgAAAA==.',
Ke='Keillor:BAABNQAECn8rAAMeAAYKThPDYgBcAQAeAAYKThPDYgBcAQASAAUKQwvxwAAQAQAAAA==.Keldorian:BAAANQAECgMIBAAAAA==.Kenzou:BAABNQAECn8iAAIYAAgKkRwnBwDFAQAYAAgKkRwnBwDFAQAAAA==.Keytymari:BAAANQAECgcIEAAAAA==.',
Kh='Khaliq:BAABNQAECn8kAAIKAAkKyBRKMQAfAgAKAAkKyBRKMQAfAgAAAA==.Khallani:BAAANQADCgIIAgABNQAECgIIBAAIAAAAAA==.',
Ki='Kieran:BAAANQADCgYIBgAAAA==.Kimashi:BAAANQAECgIIBAAAAA==.Kissme:BAABNQAECn8uAAMTAAoK8RB3MwB/AQATAAkKPhB3MwB/AQAXAAYK5AlaYwBBAQAAAA==.Kitamor:BAABNQAECn89AAMXAAoKxgd+LgBXAQAXAAoKKAd+LgBXAQANAAQKcwnvSwB5AAAAAA==.',
Kl='Kletian:BAAANQAECgYIBwABNQAECgoKPAAPAL8gAA==.',
Ko='Koriakin:BAAANQAECggIEAAAAA==.Korogth:BAAANQAECgYICgAAAA==.Kosmo:BAABNQAECn8qAAIfAAoKIBW0BAAKAgAfAAoKIBW0BAAKAgAAAA==.',
Kr='Krisyum:BAAANQAECgEIAQAAAA==.Krosmu:BAAANQADCgcIBgAAAA==.Kräsus:BAAANQADCgQIBAABNQAECgoKGgARADUcAA==.',
Ku='Kurado:BAAANQAECgIIBAAAAA==.',
Ky='Kyrysa:BAAANQAECgEIAgAAAA==.Kyrïn:BAAANQAECgEIAQABNQAFFAYIDwAaAMkWAA==.',
Kz='Kzinn:BAAANQAECgEIAQAAAA==.',
['Kæ']='Kæs:BAAANQADCgUIBQAAAA==.',
['Kö']='Körn:BAAANQAECgQIBwABNQAECgoKKAAeAEQTAA==.',
La='Ladyrichter:BAAANQAECgEIAQAAAA==.Laetus:BAABNQAECn8hAAIMAAoK/RkJTgDlAgAMAAoK/RkJTgDlAgAAAA==.Lagerthaloth:BAAANQADCgUIBAAAAA==.Laiander:BAABNQAECn8kAAIXAAkKng6TKQB6AQAXAAkKng6TKQB6AQAAAA==.Laiany:BAABNQAECn80AAILAAkKaR9MHgD4AgALAAkKaR9MHgD4AgAAAA==.Lainarning:BAAANQAECgEIAQAAAA==.Lani:BAAANQAECgIIAQAAAA==.Laolong:BAAANQADCgYIBgAAAA==.',
Le='Leeloo:BAAANQAECgEIAQAAAA==.Leeoncamillo:BAAANQADCgYIBgABNQAECgcIGQACAPgEAA==.Leetohro:BAABNQAECn8XAAIRAAcKKAT4kwC4AAARAAcKKAT4kwC4AAAAAA==.Leodoros:BAABNQAECn8jAAIMAAcKAAuVKgFFAQAMAAcKAAuVKgFFAQAAAA==.Leric:BAAANQAECgMIBAAAAA==.Lewellin:BAAANQADCgcIDQAAAA==.Leyviosa:BAAANQAECgEIAQAAAA==.',
Lh='Lhwei:BAAANQAECgcICAABNQAECgoKTAAJAB0mAA==.',
Li='Lichkíng:BAABNQAECn8WAAMCAAYKxAjdbwDfAAACAAYKxAjdbwDfAAADAAIK2gRT0wBHAAAAAA==.Lifeisalie:BAAANQAECgQIBAAAAA==.Lighty:BAAANQADCgQICAAAAA==.Lihr:BAAANQADCggIEAAAAA==.Lijiang:BAABNQAECn8mAAIYAAgK0yBUBgDpAgAYAAgK0yBUBgDpAgABNQAECgoKGgARADUcAA==.Lilianpotter:BAAANQADCgYIBgAAAA==.Lilibel:BAAANQAECgEIBgAAAA==.Lillit:BAABNQAECn8XAAMfAAcKIgd5GgBtAAAcAAcKEgXMuQCsAAAfAAQKwwZ5GgBtAAAAAA==.Lindaah:BAAANQADCggINAAAAA==.Lindapriesty:BAAANQADCgIIAgAAAA==.Lislfox:BAABNQAECn8mAAINAAkKOhynEABWAgANAAkKOhynEABWAgAAAA==.',
Ll='Lledritch:BAAANQADCgUIBQAAAA==.',
Lm='Lmmds:BAAANQADCgcIEwAAAA==.',
Lo='Lockdown:BAABNQAECn8+AAIcAAoKqRRMPADwAQAcAAoKqRRMPADwAQAAAA==.Loukou:BAAANQAECgEIAQAAAA==.',
Lu='Luacs:BAABNQAECn8oAAQeAAoKRBPHZwDVAQAeAAgKMRPHZwDVAQAgAAgKWhmoEgCoAQASAAIKfgk3DwFtAAAAAA==.Luccoa:BAABNQAECn8aAAIRAAoKNRy8EAB2AgARAAoKNRy8EAB2AgAAAA==.Lucileia:BAAANQAECgEIAQAAAA==.Lucyfary:BAAANQADCgcICAAAAA==.Luhhrogue:BAAANQAECgMIAwAAAA==.Lunirah:BAAANQADCgYICAAAAA==.',
Ly='Lylka:BAABNQAECn8+AAMEAAoKISEgBwC4AgAEAAoKISEgBwC4AgAhAAcKxyQaIgCBAgAAAA==.',
['Lé']='Léofar:BAABNQAECn8dAAIEAAgKcAP4PgAAAQAEAAgKcAP4PgAAAQAAAA==.',
['Lü']='Lücyfer:BAAANQAECgMIBgAAAA==.',
Ma='Maanu:BAAANQADCgUIBQABNQADCggINAAIAAAAAA==.Maeghann:BAAANQADCgQIAwAAAA==.Magostosaa:BAAANQABCgIIAgAAAA==.Makani:BAAANQAECgEIAgAAAA==.Maldock:BAAANQADCgYIBQAAAA==.Malewolyyc:BAABNQAECn8xAAMLAAoKfR+nHQD6AgALAAoKfR+nHQD6AgABAAQK2w2pTwDTAAAAAA==.Massafera:BAABNQAECn8mAAIFAAgKHBK9nADpAQAFAAgKHBK9nADpAQAAAA==.Mathfacbruxo:BAAANQADCgYJBgABNQAECggIIQAPAH8gAA==.Mathfacii:BAABNQAECn8hAAIPAAgKfyDlLgDgAgAPAAgKfyDlLgDgAgAAAA==.Mayanyy:BAAANQAECgEIAQAAAA==.',
Mc='Mcq:BAAANQAECgIIAgAAAA==.',
Md='Mdrdark:BAABNQAECn8tAAIDAAoKLBuKFwABAgADAAoKLBuKFwABAgAAAA==.',
Me='Medz:BAABNQAECn8kAAIMAAgKzBhJlgBTAgAMAAgKzBhJlgBTAgAAAA==.Meetjack:BAAANQAECgEIAQAAAA==.Meinstein:BAAANQAECgEIAgAAAA==.Meiyin:BAAANQADCggICAAAAA==.Meizu:BAAANQAECgQJDAAAAA==.Mellkor:BAABNQAECn8vAAIKAAgKqBkuKQCGAQAKAAgKqBkuKQCGAQAAAA==.Meneláu:BAAANQADCggICAAAAA==.Metamorful:BAAANQAECggIDwAAAA==.',
Mi='Mihsi:BAAANQAECgQIBAAAAA==.Milim:BAABNQAECn8lAAQiAAoKxwyPEAD/AAAiAAkKUQyPEAD/AAAjAAkKFQl8DQDfAAAkAAIKZwLMUQApAAAAAA==.Minilock:BAAANQAECgQIBQAAAA==.Mistogunn:BAAANQADCggICAAAAA==.Mitchell:BAAANQAECgEIAQAAAA==.',
Ml='Mls:BAAANQADCgYICwAAAA==.',
Mm='Mmarcão:BAAANQAECgUIBgAAAA==.',
Mo='Modes:BAABNQAECn8mAAIRAAkKvxqDJwCDAgARAAkKvxqDJwCDAgAAAA==.Moffir:BAAANQADCgYIBgAAAA==.Mogrus:BAAANQADCgUIAgAAAA==.Mohanninha:BAAANQAECgQIBgAAAA==.Mohotok:BAABNQAECn82AAIFAAoKZgpPhQCBAQAFAAoKZgpPhQCBAQAAAA==.Monshiro:BAAANQAECgEIAQABNQAECggIGAAXAK8bAA==.Morhome:BAAANQADCgEIAQAAAA==.Morkath:BAAANQADCggICAAAAA==.Mortank:BAAANQAECgEIAQABNQAECgcIDgAIAAAAAA==.Mortixxia:BAABNQAECn8hAAMbAAYKUx26DgAPAgAbAAYKUx26DgAPAgAcAAIKDQ6u/QA6AAAAAA==.',
Mu='Murano:BAABNQAECn8nAAIOAAkK1xaRCABbAgAOAAkK1xaRCABbAgAAAA==.',
['Má']='Máia:BAABNQAECn8UAAIbAAcK/wk5FACeAAAbAAcK/wk5FACeAAAAAA==.',
['Mä']='Mändosz:BAABNQAECn8gAAICAAgKHRkVKABXAgACAAgKHRkVKABXAgAAAA==.',
['Mé']='Ménace:BAAANQAECgIIBAABNQAECggIEQAIAAAAAA==.',
['Mÿ']='Mÿstyna:BAAANQADCgUJCQAAAA==.',
Na='Nagts:BAAANQADCggICgAAAA==.Nalathiel:BAAANQAECgYICgAAAA==.Narancia:BAABNQAECn8cAAIMAAoKLBXuOQA9AgAMAAoKLBXuOQA9AgABNQAECggIGAAXAK8bAA==.Narrih:BAAANQAECgIIBAAAAA==.Nazawill:BAAANQADCgQIBAAAAA==.Nazdru:BAAANQAECgEIAQABNQAECgoKQAAUAEYdAA==.Nazzh:BAAANQAECggIDAABNQAFFAYICQAGADAbAA==.',
Ne='Nefas:BAAANQAECgcICwAAAA==.Nepthunus:BAABNQAECn81AAIlAAoKvhr6AAB0AgAlAAoKvhr6AAB0AgAAAA==.',
Ni='Niiz:BAAANQAECggICAAAAA==.Nimloth:BAAANQAECggIDQABNQAECggIJAANAN0IAA==.Ninde:BAAANQADCggIDgAAAA==.',
No='Notforall:BAAANQADCgIIAgAAAA==.',
['Nï']='Nïix:BAAANQADCgYIBgAAAA==.',
['Nö']='Nöirr:BAAANQABCgUIBAAAAA==.',
Od='Odestruidor:BAAANQAECgUICwAAAA==.',
Ol='Oluss:BAABNQAECn8kAAMhAAoKuRETWgALAgAhAAoKuRETWgALAgAFAAEKtwddqQEyAAABNQAECgoKVQAPAF8kAA==.',
On='Onys:BAAANQADCgIIAgAAAA==.',
Oo='Oob:BAAANQAECgcICwAAAA==.',
Op='Opus:BAABNQAECn8bAAMhAAgKcBJwZADrAQAhAAgKcBJwZADrAQAEAAUKSAWRTQCyAAAAAA==.Opusbergen:BAAANQADCgQIBAAAAA==.',
Or='Origon:BAAANQADCggICwAAAA==.Orillan:BAABNQAECn8yAAIKAAkKuhQsLwBdAQAKAAkKuhQsLwBdAQAAAA==.Ornsteinsnow:BAAANQAECgUIBgAAAA==.Orsonn:BAABNQAECn8aAAIhAAgKdQ01eQAYAQAhAAgKdQ01eQAYAQAAAA==.Orucão:BAAANQABCgEIAQAAAA==.Oruism:BAAANQAECgYIBAAAAA==.Orukalango:BAAANQAECgEIAQAAAA==.Orukam:BAABNQAECn8cAAMTAAoKdgy7NAB1AQATAAoKdgy7NAB1AQAXAAIKMgjaoABcAAAAAA==.Orukanorum:BAAANQADCgcIAwAAAA==.Orukrente:BAAANQABCgIIAgAAAA==.Orulord:BAAANQABCgIIAwAAAA==.Orurage:BAAANQABCgYIBAAAAA==.',
Pa='Painkyller:BAAANQAECgEIAQAAAA==.Palaha:BAAANQAECgcIDAABNQAECgoKVQAPAF8kAA==.Palatina:BAABNQAECn8gAAIFAAkKyx00OQDsAgAFAAkKyx00OQDsAgABNQAECgkJMgAFAAckAA==.Pandalokodj:BAAANQAECgEIAQAAAA==.Pangedrey:BAABNQAECn87AAMVAAoKJxnIEAAgAgAVAAoKJxnIEAAgAgAJAAEKRxWHSgA9AAAAAA==.Parcival:BAAANQAECgQIBQAAAA==.Parký:BAABNQAECn8YAAMeAAcKniLyHgCWAgAeAAcKniLyHgCWAgASAAEKAACRRQErAAAAAA==.Paullk:BAAANQAECgEIAgAAAA==.',
Pe='Penseur:BAAANQABCgYIBgAAAA==.Peruchi:BAAANQAECgEIAQAAAA==.Perísdra:BAAANQADCgcIDQABNQAECgMIDAAIAAAAAA==.',
Pg='Pgms:BAAANQADCggIEgAAAA==.',
Pi='Picu:BAAANQADCgUICQAAAA==.Pistoriane:BAAANQADCggICAABNQAECgoKKQAJANobAA==.Pitombinha:BAABNQAECn8iAAMOAAkK/B7DCADTAQAOAAcKMB/DCADTAQAGAAQKZRmVvADIAAAAAA==.Pixiks:BAAANQABCgYIBwAAAA==.',
Pp='Ppandora:BAAANQADCggIEgAAAA==.',
Pr='Predadore:BAAANQADCgUIBQAAAA==.',
Py='Pyrix:BAAANQADCgIIAgAAAA==.',
['Pä']='Pändero:BAAANQABCgMIAwAAAA==.',
['Pî']='Pîo:BAACNQAFFH8FAAIMAAQKRww4LAAtAQAMAAQKRww4LAAtAQA1AAQKfzoAAgwACgrBIQ0sADcDAAwACgrBIQ0sADcDAAAA.',
Qu='Quirow:BAABNQAECn8uAAISAAkKiQ5GTwBhAQASAAkKiQ5GTwBhAQAAAA==.',
Ra='Radiação:BAAANQAECgMIAwAAAA==.Radunz:BAABNQAECn9AAAMUAAoKRh2IBQCGAgAUAAoKRh2IBQCGAgATAAMKlhURTgDTAAAAAA==.Ragnaros:BAAANQAECgQIBQAAAA==.Ragnarssön:BAAANQAECgQIBQAAAA==.Ragnarøk:BAAANQABCggICgAAAA==.Raio:BAABNQAECn8/AAIMAAoKzR4lLQBtAgAMAAoKzR4lLQBtAgAAAA==.Ramorey:BAAANQAECgQICQAAAA==.Ranruulfnarm:BAAANQABCgQICAAAAA==.Rargsa:BAAANQAECgQIDwAAAA==.Rargul:BAAANQAECgQIAwAAAA==.Rariel:BAABNQAECn8dAAIKAAoKAxKKPQDNAQAKAAoKAxKKPQDNAQAAAA==.Raymain:BAABNQAECn8mAAQJAAkKUBrFGQDjAQAJAAgKFBnFGQDjAQAVAAkKLBdyKQDSAQAYAAEKUgMHJgAiAAAAAA==.Raíka:BAAANQADCggIDQAAAA==.',
Re='Rebimboca:BAAANQAECgEIAQAAAA==.Redoon:BAAANQAECgIIAQAAAA==.Rendoras:BAAANQAECgEIAQAAAA==.',
Rh='Rhaumarhu:BAAANQADCgcIEgAAAA==.',
Ro='Rockit:BAAANQADCgMICAAAAA==.Rodbree:BAABNQAECn81AAMhAAoKICVnBwCJAwAhAAoKICVnBwCJAwAFAAIKAADEbwFuAAAAAA==.Roguinhu:BAAANQAECgYIEgAAAA==.Roseangel:BAAANQABCgEIAQAAAA==.',
Ru='Rubian:BAAANQADCgYIDAAAAA==.Rudan:BAAANQAECgEIAQAAAA==.Rurumo:BAAANQAECgEIAQAAAA==.Rustovick:BAAANQAECgUIEwAAAA==.',
['Rä']='Rämzä:BAAANQAECgEIAQABNQAECggIGgANAIwRAA==.',
['Rå']='Råy:BAABNQAECn8rAAMDAAoKLBwtJwCfAgADAAoKLBwtJwCfAgACAAEKkg48qwA3AAAAAA==.',
Sa='Saalla:BAAANQAECgEIAwABNQAECgoKQAAUAEYdAA==.Saffír:BAABNQAECn8xAAIFAAoK7hQIXgDeAQAFAAoK7hQIXgDeAQAAAA==.Sahkev:BAAANQAECgYIBwAAAA==.Samalandraa:BAABNQAECn8cAAMSAAgKGhA9QQCUAQASAAgKGhA9QQCUAQAgAAIK1AUVKgBrAAAAAA==.Sanateia:BAAANQAECgEIAgAAAA==.Saniest:BAABNQAECn8hAAMBAAoKeh3EEwDJAgABAAkKQB3EEwDJAgALAAUKEh5apwC2AAAAAA==.Sapekinhä:BAABNQAECn8aAAIKAAkKVhWgLgAxAgAKAAkKVhWgLgAxAgAAAA==.Satanvitória:BAAANQAECgYIEAAAAA==.',
Se='Segavaxx:BAAANQABCgQIBAAAAA==.Seilaa:BAAANQAECgIIAgAAAA==.Selorixie:BAAANQAECgYIDwABNQAECgYIIQAbAFMdAA==.Sereiaa:BAABNQAECn8XAAIPAAgKKQiksAAMAQAPAAgKKQiksAAMAQAAAA==.',
Sh='Shadowmore:BAAANQAECgQIBAABNQAECggILwAKAKgZAA==.Shamate:BAAANQAECgUIAgAAAA==.Shanoa:BAAANQAECgUIBwAAAA==.Sharae:BAAANQADCggIDQAAAA==.Shaÿane:BAAANQAECgUIBgAAAA==.Shedo:BAABNQAECn8YAAMGAAkKohkEeQAsAgAGAAgKohkEeQAsAgAOAAIKUhqzJwBvAAAAAA==.Shonja:BAAANQAECgMICAAAAA==.Shula:BAAANQADCgYIBgAAAA==.',
Si='Sialeeds:BAAANQADCgMIAwAAAA==.Siclop:BAAANQAECgIIAgAAAA==.Simplicity:BAABNQAECn8aAAMLAAgKwBdCZADzAQALAAgKwBdCZADzAQABAAMKbxJoVwCtAAAAAA==.Sinton:BAAANQABCgIIAgAAAA==.',
Sk='Skadrian:BAAANQAECgQIBAAAAA==.Skadryan:BAAANQAECgUIDwAAAA==.Skalnark:BAABNQAECn8aAAIcAAkKRgsPZABvAQAcAAkKRgsPZABvAQAAAA==.Skinme:BAAANQAECgEIAQAAAA==.Skysoul:BAAANQAECgEJAgAAAA==.',
Sl='Sleeppanda:BAAANQAECgEIAgABNQAECgoKLwAEABQkAA==.',
So='Sofiela:BAAANQAECgIIAgAAAA==.Soijiro:BAAANQADCgIIAgAAAA==.Soju:BAAANQADCgIIAgAAAA==.Sol:BAAANQADCgQIBAAAAA==.',
Sp='Spectrø:BAAANQADCgcIFAAAAA==.',
Ss='Sstrange:BAAANQADCggICQABNQAECgQIBAAIAAAAAA==.',
St='Starkz:BAAANQADCgUIBQAAAA==.Stormswill:BAAANQAECgEIAQAAAA==.Stëlla:BAABNQAECn81AAIeAAoKtxpXJQBqAgAeAAoKtxpXJQBqAgAAAA==.',
Su='Suckmyhammer:BAAANQAECgcIDgAAAA==.Sungjinwoo:BAAANQAECgYIEAAAAA==.Sunnara:BAABNQAECn8oAAImAAoKXhzxFQC0AgAmAAoKXhzxFQC0AgAAAA==.',
Sy='Syuon:BAABNQAECn9MAAIJAAoKHSaqAADcAwAJAAoKHSaqAADcAwAAAA==.',
Sz='Szaa:BAAANQADCgUICAAAAA==.',
Ta='Taelin:BAAANQAECgEIAQAAAA==.Talandar:BAABNQAECn9OAAIXAAoKlhnPEwBTAgAXAAoKlhnPEwBTAgAAAA==.Tankoso:BAAANQAECgQIBAAAAA==.Tankudo:BAABNQAECn8xAAMDAAkKvhlqGgDjAQADAAkKvhlqGgDjAQARAAIK4xeBhgBFAAAAAA==.Tapuloka:BAAANQAECgEIAQAAAA==.Tataloka:BAAANQAECgMIAQAAAA==.',
Te='Tennebra:BAAANQADCggICQAAAA==.',
Th='Thabitah:BAABNQAECn9AAAIBAAoKJxMBEgADAgABAAoKJxMBEgADAgAAAA==.Thanathus:BAAANQAECgIIAgAAAA==.Thangu:BAAANQAECggIAQAAAA==.Thaumiel:BAAANQADCgEIAQAAAA==.Thedragon:BAABNQAECn89AAMPAAoKCiGpEADzAgAPAAoKCiGpEADzAgAnAAEKAQuoVgA5AAAAAA==.Thorkel:BAAANQAECgIIAgAAAA==.Thotamon:BAAANQAECgQICQAAAA==.Thýah:BAAANQAECgUIBwAAAA==.',
Ti='Tidim:BAAANQADCgcIEAAAAA==.Tiih:BAAANQABCgUIBwAAAA==.',
To='Tonypaludo:BAAANQAECgEIAQAAAA==.',
Tr='Trueperceval:BAAANQABCgQIBgAAAA==.',
Ts='Tsukii:BAAANQAECgEIAQAAAA==.',
Tu='Tushui:BAAANQADCgMIAwAAAA==.',
Ur='Uriuri:BAAANQAECgEIAQABNQAECgoKQAAUAEYdAA==.',
Us='Usfull:BAABNQAECn8mAAMLAAkKNxhuWwAPAgALAAkKNxhuWwAPAgABAAIKsQOhagBYAAAAAA==.',
Va='Vaatu:BAAANQADCgMIBAAAAA==.Vaeltor:BAAANQAECggIBAAAAA==.Valegás:BAAANQAECgQIBgAAAA==.Vallentyne:BAAANQAECgUIBQAAAA==.Vallkÿria:BAAANQAECgcIDAAAAA==.Varrex:BAAANQAECgEIAQAAAA==.Vaëllen:BAABNQAECn8kAAMNAAgK3QiUMADXAAANAAgK3QiUMADXAAAXAAEKAAC7wAAhAAAAAA==.',
Ve='Vehuiáh:BAABNQAECn8bAAIhAAkK8xOGQADfAQAhAAkK8xOGQADfAQAAAA==.Velen:BAABNQAECn9BAAMDAAoKhB/GCADMAgADAAoKhB/GCADMAgACAAEKswjAnwAzAAAAAA==.Verno:BAAANQAECgIIAgAAAA==.Verzuk:BAAANQAECgYIDgAAAA==.',
Vi='Vintejulgar:BAAANQABCggICQAAAA==.Vintekilo:BAABNQAECn8hAAIFAAoKVA2unADpAQAFAAoKVA2unADpAQAAAA==.Vinteservir:BAAANQABCgQIBAAAAA==.',
Vo='Voiddh:BAACNQAFFH8FAAImAAUKrgXsCAC1AAAmAAUKrgXsCAC1AAA1AAQKfy4AAiYACgqFFTElAB0CACYACgqFFTElAB0CAAAA.Vortiaz:BAAANQAECgEIAwABNQAECggICgAIAAAAAA==.',
Vr='Vrenshrrgn:BAAANQAECgEIAgAAAA==.',
Vy='Vygh:BAABNQAECn88AAMcAAoKGh8lIgD7AgAcAAoKGh8lIgD7AgAbAAEKuAs4eQA0AAAAAA==.Vyndrill:BAABNQAECn8qAAIZAAkKyBT4HQDjAQAZAAkKyBT4HQDjAQAAAA==.',
['Vø']='Vølkan:BAAANQAECgEIAwAAAA==.',
Wa='Walkers:BAABNQAECn8sAAIPAAoKpxOXVQBxAgAPAAoKpxOXVQBxAgAAAA==.Warlaka:BAAANQADCgYICwAAAA==.',
We='Weevil:BAAANQADCgYICgAAAA==.',
Wo='Worgenbelfin:BAAANQADCggIDQAAAA==.',
Wy='Wyrel:BAAANQADCgQIBgAAAA==.',
Xa='Xalmoria:BAAANQAECgcICgAAAA==.',
Xu='Xurumeloun:BAAANQADCgYIBgAAAA==.',
Ya='Yamii:BAAANQAECgQIBgAAAA==.Yasmini:BAAANQABCgEIAQAAAA==.',
Yi='Yingsu:BAABNQAECn8cAAMVAAoKFR2CGACDAgAVAAoKshyCGACDAgAYAAYK6RAHHAAmAQAAAA==.Yippwarr:BAAANQADCgMIBAAAAA==.',
Yu='Yunná:BAAANQADCgYICgAAAA==.',
Yv='Yvin:BAAANQAECgIIAgAAAA==.',
Za='Zakir:BAAANQAECgQICAAAAA==.Zaolron:BAAANQADCgIIAQAAAA==.Zawarudo:BAAANQADCggICAAAAA==.',
Ze='Zeddshm:BAAANQAECgEJAQABNQAECgoKLwAGAKgVAA==.',
Zh='Zhynah:BAAANQADCgUIBQAAAA==.',
Zi='Zibrautar:BAAANQADCgIIAgAAAA==.Ziracruz:BAAANQAECgQICAAAAA==.',
Zu='Zulyn:BAAANQADCgcIFwAAAA==.Zupen:BAAANQAECgEIAgAAAA==.',
['Àr']='Àrdath:BAAANQAECgQIBAAAAA==.Àrthemís:BAAANQADCgEIAQAAAA==.',
['Ár']='Áraujo:BAAANQADCgEJAQABNQADCgUIBQAIAAAAAA==.Árÿä:BAABNQAECn8+AAIPAAoKeRChTAD4AQAPAAoKeRChTAD4AQAAAA==.',
['Áy']='Áy:BAAANQADCgIIAgAAAA==.',
['Är']='Äraxy:BAAANQAECgEIAQAAAA==.',
['Èv']='Èver:BAAANQADCgIIAgAAAA==.',
['Ðh']='Ðh:BAAANQAECgEIAQAAAA==.',
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
