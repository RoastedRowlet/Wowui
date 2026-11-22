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

local lookup = {'Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Protection','Paladin-Retribution','Paladin-Holy','Warrior-Arms','Warrior-Protection','Unknown-Unknown','Monk-Mistweaver','DemonHunter-Havoc','Priest-Holy','Mage-Arcane','Druid-Guardian','Warrior-Fury','Hunter-BeastMastery','Shaman-Elemental','Shaman-Restoration','DemonHunter-Vengeance','DeathKnight-Blood','Druid-Restoration','Druid-Feral','Monk-Windwalker','Mage-Frost','Druid-Balance','Monk-Brewmaster','Rogue-Assassination','Rogue-Subtlety','Warlock-Destruction','Warlock-Demonology','Priest-Discipline','Warlock-Affliction','Shaman-Enhancement','Hunter-Marksmanship','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Mage-Fire','Rogue-Outlaw','DemonHunter-Devourer',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abaca:BAAANQAECgIIAgAAAA==.Abacatte:BAAANQAECgQICAAAAA==.',
Ad='Adelaide:BAAANQADCgUIBwABNQAFFAkJGwABANMPAA==.',
Ae='Aelthor:BAAANQAECgQIBQAAAA==.',
Al='Alanie:BAAANQAECggICwAAAA==.Aleriastorm:BAAANQABCgIIAgAAAA==.Alessaxd:BAABNQAECn8eAAMCAAoKfg6iQwC1AQACAAoKpQ2iQwC1AQADAAUKUA3YPQAbAQAAAA==.Alfajhor:BAABNQAECn9PAAQEAAoKOyWPAgCjAwAEAAoKOyWPAgCjAwAFAAUKmRTB7AAJAQAGAAEKhAnm+QAxAAAAAA==.Alfajhòr:BAAANQAECgEIAQAAAA==.Alfajhõr:BAAANQAECgYICgAAAA==.Alkaid:BAABNQAECn9AAAMHAAoKVhjeRgAsAgAHAAkKPRjeRgAsAgAIAAgK+gsTIwAxAQAAAA==.Alladryel:BAAANQADCgYIBgAAAA==.Allandriel:BAAANQAECgEIAQABNQAECgYIEAAJAAAAAA==.Alleriane:BAABNQAECn8qAAIKAAoK2huDDwCIAgAKAAoK2huDDwCIAgAAAA==.Allone:BAABNQAECn9JAAILAAoKMw8YLwCdAQALAAoKMw8YLwCdAQAAAA==.Allunt:BAAANQAECgcICgAAAA==.Almin:BAAANQAECgIIBQAAAA==.Alruna:BAAANQAECgUICQAAAA==.',
Am='Ametnys:BAAANQAECgUICgAAAA==.Amonhar:BAAANQAECgUIBAABNQAECgoKKAAMAK4XAA==.',
An='Anakata:BAAANQAECgcIDQAAAA==.Andaliz:BAABNQAECn8yAAIFAAkKByR9BwC+AwAFAAkKByR9BwC+AwAAAA==.Andaril:BAAANQAECgUIDAAAAA==.Antonel:BAAANQABCgYIBgAAAA==.Antonellaes:BAAANQAECgEIAQABNQAECgcIGQACAPgEAA==.',
Ap='Aprocom:BAAANQAECgUIDgAAAA==.',
Ar='Arcanör:BAABNQAECn8bAAINAAgKsg0D9QChAQANAAgKsg0D9QChAQAAAA==.Arctorius:BAABNQAECn8XAAMFAAcKaQxe0AB7AQAFAAcKaQxe0AB7AQAEAAEKAADzdgAmAAAAAA==.Aronys:BAAANQAECgYIEAAAAA==.Arquitetö:BAAANQADCgIIAgAAAA==.Arthashand:BAAANQADCgEIAQAAAA==.Artronis:BAABNQAECn81AAIOAAoKaRP6EwAkAgAOAAoKaRP6EwAkAgAAAA==.Arukäi:BAABNQAECn8hAAMHAAgKxwr0qwCvAQAHAAgKxwr0qwCvAQAPAAMKgQdWKQBlAAAAAA==.Arägørn:BAABNQAECn8aAAIFAAcKpAYmCAHdAAAFAAcKpAYmCAHdAAAAAA==.',
As='Assintomatic:BAAANQABCgYICQABNQAECggIDgAJAAAAAA==.',
At='Atriuz:BAAANQAECgQIDAAAAA==.Ats:BAAANQADCggIEQAAAA==.',
Au='Aurín:BAAANQADCgQIBAAAAA==.',
Az='Azarado:BAAANQAECggIBgAAAA==.Azerotiano:BAABNQAECn8fAAIQAAkKlApZiQClAQAQAAkKlApZiQClAQAAAA==.',
['Aÿ']='Aÿ:BAAANQAECgEIAQAAAA==.',
Ba='Badhealer:BAABNQAECn8ZAAMRAAkKYxFSSQCwAQARAAgKYhJSSQCwAQASAAQKOQTPyACHAAAAAA==.Baldraccus:BAAANQADCgcIBwAAAA==.Balk:BAABNQAECn88AAIQAAoKvyBZIAAWAwAQAAoKvyBZIAAWAwAAAA==.Bambur:BAAANQADCggICgAAAA==.Barauna:BAAANQABCgIIAgAAAA==.Barbabruto:BAABNQAECn8lAAMIAAoKfhpECwCIAgAIAAoKShlECwCIAgAPAAIKRxy9IgCVAAAAAA==.Barbacancer:BAAANQAECgcICAAAAA==.Barbalock:BAAANQAECgIIAgAAAA==.Barbasanta:BAAANQAECgQICAABNQAECgoKJQAIAH4aAA==.Batgirl:BAABNQAECn8ZAAMTAAoKaw3HEQAtAQATAAgKIgzHEQAtAQALAAcKpQ1RSQAHAQAAAA==.',
Be='Belthorsin:BAAANQADCgYIBgAAAA==.Belthorvil:BAAANQADCgEIAQAAAA==.',
Bi='Bigbag:BAAANQADCgQIBQAAAA==.Biønic:BAAANQAECgUIEQAAAA==.',
Bl='Blackheartz:BAAANQAECgMIAwAAAA==.Blackmoonx:BAABNQAECn8YAAICAAkKjx3LKgBFAgACAAkKjx3LKgBFAgABNQAECggIFwAHAGIiAA==.Blackninja:BAAANQABCggIGwAAAA==.Blu:BAEANQAECgEIAQABNQAECgYIEQAJAAAAAA==.',
Bo='Box:BAAANQADCgMIAwAAAA==.',
Br='Brahman:BAAANQAECgEIAQAAAA==.Bratloko:BAAANQADCgMIAwAAAA==.Bright:BAAANQADCgYIBgAAAA==.Brinston:BAAANQADCgUICgABNQAFFAYICAAMAEgNAA==.Bruex:BAAANQADCgIIAgAAAA==.Bruker:BAAANQADCgIIAwAAAA==.Brutalhoof:BAAANQAECgEIAwAAAA==.',
Bu='Buzzumaaky:BAABNQAECn8VAAINAAcKPhdYuAATAgANAAcKPhdYuAATAgAAAA==.',
By='Bynhu:BAAANQADCggICAAAAA==.',
['Bá']='Bávor:BAAANQADCgEIAQAAAA==.',
['Bí']='Bílly:BAAANQAECgEIAQAAAA==.',
['Bü']='Büdweiser:BAAANQAECgEIAQAAAA==.',
Ca='Calteryeker:BAAANQAECgMICwAAAA==.Capitu:BAAANQADCggIEwABNQAECgkJJwAUAPYbAA==.Capyvara:BAAANQABCgYIBwAAAA==.Caraldk:BAACNQAFFH8FAAIUAAQKfg9MJABsAAAUAAQKfg9MJABsAAA1AAQKfzAAAxQACgrEHasRAB8DABQACQq+IKsRAB8DAAMAAQrxCCyJADUAAAAA.Caroll:BAAANQADCgMIAwAAAA==.Caçaorda:BAAANQAECgMJBAAAAA==.',
Ce='Ceciliah:BAACNQAFFH8QAAIRAAQKUBB5EgDaAAARAAQKUBB5EgDaAAA1AAQKf0cAAhEACgqMIj8SANkCABEACgqMIj8SANkCAAAA.Cernûnnos:BAABNQAECn8bAAMVAAcKURgOLQCHAQAVAAcKURgOLQCHAQAWAAEKAABETQAdAAAAAA==.',
Ch='Champdude:BAABNQAECn9RAAMXAAoK2x2wFwCNAgAXAAkKzR6wFwCNAgAKAAkK0BT7DgAsAgAAAA==.Chifrelda:BAAANQAECgIIAgAAAA==.Chopquatro:BAAANQADCggICAAAAA==.Chopum:BAAANQAECggICAAAAA==.Chrnnos:BAAANQAECgcICwABNQAECgkJKQAPAPweAA==.',
Co='Coffeebean:BAAANQAECgQIBAAAAA==.Corineus:BAAANQADCgYIDgAAAA==.Cowzeroth:BAABNQAECn84AAIRAAoKbSBmFgC3AgARAAoKbSBmFgC3AgABNQAECgoKPAAQAL8gAA==.',
Cr='Crassustitan:BAAANQAECggICQAAAA==.Criativa:BAAANQAECgIIAgAAAA==.Cristcalad:BAABNQAECn8nAAMHAAkKlBKbdgChAQAHAAkKBQ6bdgChAQAIAAYKTxZLIgA4AQAAAA==.',
Cu='Cutia:BAAANQAECgEIAQAAAA==.',
Da='Daemi:BAAANQAECggIEAAAAA==.Dakael:BAAANQABCgYIDgABNQAECgoKUgAWAGwgAA==.Dalaty:BAABNQAECn8VAAIFAAUKPAetIwG1AAAFAAUKPAetIwG1AAAAAA==.Daresh:BAAANQADCgEIAQAAAA==.Dariok:BAABNQAECn8kAAIHAAgKDQXqxgDmAAAHAAgKDQXqxgDmAAAAAA==.Darkove:BAABNQAECn8qAAIYAAoKHRAsDQDgAQAYAAoKHRAsDQDgAQAAAA==.Darrow:BAABNQAECn82AAICAAoKVRVsNAALAgACAAoKVRVsNAALAgAAAA==.Daryan:BAAANQAECgcIDwAAAA==.Day:BAAANQAECgQIBQAAAA==.',
De='Deathinhu:BAABNQAECn9MAAINAAoKjiCuJwCgAgANAAoKjiCuJwCgAgAAAA==.Demoriana:BAABNQAECn8ZAAMCAAcK+AQ1fQCzAAACAAcKHQQ1fQCzAAAUAAQKbwSDjABTAAAAAA==.Dethroned:BAAANQAECgUICgAAAA==.',
Di='Digaolock:BAAANQAECgEIAQAAAA==.Digaoxdrx:BAAANQADCgQIBAAAAA==.Dimeros:BAABNQAECn9LAAIZAAoK2guILgCRAQAZAAoK2guILgCRAQAAAA==.Divano:BAABNQAECn9EAAIBAAoKACBeCQDLAgABAAoKACBeCQDLAgAAAA==.',
Dk='Dkats:BAAANQADCggIDAAAAA==.Dkhalifa:BAAANQADCgYIBgAAAA==.',
Do='Dogowner:BAAANQAECgcIBwAAAA==.Donora:BAAANQAECgQIBAAAAA==.Dorfillaw:BAAANQAECgUICQAAAA==.Dorvana:BAAANQADCgMJAwABNQAECgkJMgAFAAckAA==.',
Dr='Dracthyrius:BAAANQAECgEIAQAAAA==.Draenthar:BAAANQAECgEIAQAAAA==.Dragonstyle:BAAANQAECgcICwAAAA==.Dragony:BAAANQADCgQIBAAAAA==.Dreez:BAAANQAECgUICAAAAA==.Drexus:BAAANQADCgMIAwAAAA==.Drigolas:BAAANQADCgYICAAAAA==.Druidblack:BAAANQADCgUIBQAAAA==.',
Eh='Ehomi:BAAANQADCgIIAgAAAA==.',
Ei='Eirin:BAABNQAECn8eAAIaAAUK1xU/HQAUAQAaAAUK1xU/HQAUAQAAAA==.',
El='Eldris:BAAANQADCgEIAQAAAA==.Elidibus:BAAANQADCgQIBAAAAA==.Elistraee:BAAANQADCgEIAQAAAA==.Ellvarg:BAAANQADCgYIDAAAAA==.Eluuria:BAABNQAECn8gAAIFAAoKGBAQrAB3AQAFAAoKGBAQrAB3AQAAAA==.',
En='Enkrenco:BAAANQADCgQIBAAAAA==.Ennafaryn:BAAANQABCgQIBgAAAA==.Ensabanú:BAAANQADCgQIBAAAAA==.',
Er='Erilaethaen:BAAANQAECgIIAgAAAA==.Erlek:BAAANQADCggIFwAAAA==.Ernest:BAABNQAECn9PAAIVAAoKaSB2CwAVAwAVAAoKaSB2CwAVAwAAAA==.Erulan:BAAANQADCgQIBwAAAA==.',
Es='Estgan:BAAANQADCgMIAwAAAA==.',
Et='Ether:BAABNQAECn8ZAAIUAAkKrRJRTQDAAQAUAAkKrRJRTQDAAQAAAA==.',
Ev='Evangelouco:BAAANQADCgQIBAAAAA==.Evilbarba:BAACNQAFFH8GAAIFAAYK0gyKFAASAQAFAAYK0gyKFAASAQA1AAQKfzgAAgUACQptIBwrALUCAAUACQptIBwrALUCAAAA.',
Ex='Exodes:BAAANQAECgMIBAAAAA==.Exort:BAAANQAECgUICwAAAA==.Exothus:BAAANQAECgQJBwAAAA==.',
Fa='Faaver:BAAANQADCgMIAwAAAA==.Faldark:BAAANQADCgUIBQAAAA==.Faranir:BAAANQAECgMIAwAAAA==.Faris:BAABNQAECn84AAMbAAoK+RQxOAD2AQAbAAgKlBYxOAD2AQAcAAkKqBFWTQDMAQABNQAECgoKPAAQAL8gAA==.Faversani:BAABNQAECn8sAAQHAAoKYiLvKgAQAwAHAAoKYiLvKgAQAwAPAAEKChsGLwBLAAAIAAEKCxhoQAA/AAAAAA==.Fayla:BAAANQADCgMIAwAAAA==.Faölin:BAABNQAECn83AAIcAAoKNxqEEQBpAgAcAAoKNxqEEQBpAgAAAA==.',
Fe='Ferael:BAABNQAECn9OAAMFAAoKFiHgHgDlAgAFAAoKFiHgHgDlAgAEAAQKPQkPUACmAAAAAA==.Ferrus:BAAANQAECgQIAwAAAA==.Fewlin:BAAANQAECgMIAwAAAA==.',
Fj='Fjord:BAAANQAECgIIAgAAAA==.',
Fl='Florbela:BAABNQAECn8fAAIVAAgKygvAMwB8AQAVAAgKygvAMwB8AQAAAA==.',
Fo='Fogue:BAAANQADCgMIAwAAAA==.',
Fr='Fredericc:BAABNQAECn8XAAIRAAgKjgqligD3AAARAAgKjgqligD3AAAAAA==.Freecs:BAABNQAECn8dAAMZAAgK7RyDGQBAAgAZAAgK7RyDGQBAAgAWAAIKtRo7MACSAAAAAA==.Freyá:BAABNQAECn89AAMEAAoKCh5lEACXAgAEAAoKOB1lEACXAgAFAAoKrxPp0QA0AQAAAA==.Frostburn:BAAANQAECggIEAAAAA==.Froststriker:BAAANQAECgEIAQAAAA==.',
Fu='Fulvo:BAAANQADCgQIBQAAAA==.',
Ga='Gadodamorena:BAAANQAECgEIAQAAAA==.Galfur:BAABNQAECn8cAAIZAAUKOQeAfwDQAAAZAAUKOQeAfwDQAAAAAA==.Galhuda:BAABNQAECn8fAAIVAAkKxgihMwBUAQAVAAkKxgihMwBUAQAAAA==.Galica:BAAANQADCgIIAgAAAA==.Gallatheya:BAAANQAECgYIAQAAAA==.Gandwelf:BAAANQADCggICAAAAA==.',
Ge='Geisty:BAAANQAECgEIAQABNQAECgIIBAAJAAAAAA==.Gemius:BAAANQADCgMIAwAAAA==.',
Gl='Glutotwo:BAAANQADCgYIEgAAAA==.',
Go='Goldchain:BAAANQAECgYICAAAAA==.Govers:BAAANQAECgEIAQABNQAECggICgAJAAAAAA==.',
Gr='Grommar:BAAANQADCgUIBQABNQAECgMICwAJAAAAAA==.Grumax:BAABNQAECn8YAAIFAAcKkAvs1wBsAQAFAAcKkAvs1wBsAQAAAA==.',
Gu='Gudeath:BAABNQAECn8vAAIHAAkKnxWJiAAHAgAHAAkKnxWJiAAHAgAAAA==.Guerrerinhow:BAABNQAECn8aAAMHAAkKrAYTvQD9AAAHAAkK9wUTvQD9AAAIAAEKXwcAAAAAAAABNQAECgoKPQAZAKERAA==.Guitianki:BAAANQADCggIEgAAAA==.Gulek:BAAANQAECgYIBAAAAA==.Gussg:BAABNQAECn8oAAMdAAkKUxRVBwBeAQAdAAcKTBZVBwBeAQAeAAYKqwjo4QAFAQAAAA==.',
['Gà']='Gàladriel:BAABNQAECn8eAAIVAAcKrhfGIQDqAQAVAAcKrhfGIQDqAQAAAA==.',
['Gö']='Göhan:BAABNQAECn8aAAIOAAgKjBHmIgBrAQAOAAgKjBHmIgBrAQAAAA==.',
['Gø']='Gøvers:BAAANQAECggICgAAAA==.',
['Gü']='Güttz:BAABNQAECn8lAAILAAgKSRGCOwDaAQALAAgKSRGCOwDaAQAAAA==.',
Ha='Hagires:BAAANQAECgYIBwAAAA==.Hanaluna:BAAANQADCggICAAAAA==.Harchus:BAAANQAECgEIAQAAAA==.Hargarthul:BAAANQADCgMIBAAAAA==.Hazell:BAAANQADCggIDQAAAA==.',
He='Heaveth:BAAANQADCgYIAgABNQAECgoKVwARALYeAA==.Hellspont:BAABNQAECn81AAQWAAoKPiGfBwB7AgAWAAkKKyGfBwB7AgAVAAgKFRX1HwD9AQAOAAMKMRv/RgCVAAAAAA==.Helwin:BAAANQADCgEIAQAAAA==.Hendrikison:BAAANQAECgQIBgAAAA==.',
Ho='Horagalles:BAAANQADCgIIAgAAAA==.Hotmojo:BAACNQAFFH8SAAINAAUKdRkXJADoAAANAAUKdRkXJADoAAA1AAQKf1QAAg0ACgqQIosTAP0CAA0ACgqQIosTAP0CAAAA.',
Hu='Hunfox:BAABNQAECn9gAAIQAAoKZSTACQCPAwAQAAoKZSTACQCPAwAAAA==.Hunterhearst:BAAANQADCgYIBwAAAA==.Huor:BAAANQAECgQIBAAAAA==.',
Hy='Hylana:BAAANQADCggICAAAAA==.',
['Hö']='Hölycrüsh:BAACNQAFFH8JAAIFAAMK3yKLFwDtAAAFAAMK3yKLFwDtAAA1AAQKf04AAgUACgoFJSkJAFMDAAUACgoFJSkJAFMDAAAA.',
Ih='Ihntwuaed:BAAANQADCgQIBwAAAA==.',
Ik='Ikoo:BAABNQAECn8yAAIfAAoKDxsjAgDEAgAfAAoKDxsjAgDEAgAAAA==.',
Il='Illaril:BAACNQAFFH8aAAITAAYKdAttAgAZAQATAAYKdAttAgAZAQA1AAQKfzcAAhMACgrPHOcFAFQCABMACgrPHOcFAFQCAAAA.',
Im='Imcomparavel:BAAANQADCgQIBAAAAA==.',
In='Indarion:BAAANQAECgMIAwAAAA==.Interestelar:BAAANQADCgYIBgAAAA==.Invisiblelol:BAAANQAECgUICgAAAA==.',
Ir='Irmãodouther:BAAANQAECggIDgAAAA==.Irridan:BAAANQADCggICQAAAA==.',
Is='Isenhearth:BAAANQABCgUIBQAAAA==.Ishtarie:BAABNQAECn8gAAISAAoKbR0MLwClAgASAAoKbR0MLwClAgAAAA==.',
Iv='Ivina:BAABNQAECn9KAAMeAAoK+h3tIwCCAgAeAAoK+h3tIwCCAgAgAAEKjwasMwAsAAAAAA==.',
Iz='Izaar:BAAANQADCggIGQAAAA==.',
Ja='Jangeoffry:BAAANQABCgMIAwAAAA==.Jayser:BAAANQADCgYIBgAAAA==.',
Jh='Jhonatinha:BAAANQAECgUIBwAAAA==.',
Jk='Jks:BAAANQAECgcICAAAAA==.',
Ju='Jullianxd:BAAANQAECgYIDQAAAA==.Junjih:BAAANQAECgUIBQABNQAECgkJIQAeAKgWAA==.',
Ka='Kaallew:BAAANQAECggIDgAAAA==.Kaallmonge:BAAANQABCgcIBwAAAA==.Kaelonidas:BAAANQAECgQIDAAAAA==.Kaelyaa:BAAANQADCgUIBQAAAA==.Kainer:BAAANQADCgYICQAAAA==.Kalazshar:BAABNQAECn8nAAIOAAoKcguRKQBKAQAOAAoKcguRKQBKAQAAAA==.Kalduran:BAAANQADCggIPQAAAA==.Kalelzinho:BAAANQADCgYICgAAAA==.Kaluss:BAABNQAECn8mAAMNAAoKrghB6QC3AQANAAoKTwhB6QC3AQAYAAEKbwtzQgAtAAAAAA==.Kanduz:BAAANQAECgUICAAAAA==.Karlariel:BAAANQAECgUIBQABNQAECgYIEAAJAAAAAA==.Karmabb:BAAANQAECgUICgAAAA==.Kauss:BAAANQAECgIIAgAAAA==.Kavartu:BAACNQAFFH8FAAMRAAIKeAqyHwCDAAARAAIKeAqyHwCDAAAhAAEKXhB4CABMAAA1AAQKfzkABBEACgqSGYRFAGACABEACgqSGYRFAGACACEAAgpmC+MuAHkAABIAAQrlAPIVAQ0AAAAA.Kayli:BAAANQADCgcIDgAAAA==.',
Ke='Keillor:BAABNQAECn8tAAMSAAcKXRFWagB1AQASAAcKXRFWagB1AQARAAUKQwvxwAAQAQAAAA==.Keldorian:BAAANQAECgUIBwAAAA==.Kenzou:BAABNQAECn8iAAIaAAgKkRzoCADDAQAaAAgKkRzoCADDAQAAAA==.Keytymari:BAAANQAECgcIDQAAAA==.',
Kh='Khaliq:BAABNQAECn8lAAILAAkKzRRKMQAfAgALAAkKzRRKMQAfAgAAAA==.Khallani:BAAANQADCgIIAgABNQAECgIIBAAJAAAAAA==.',
Ki='Kieran:BAAANQADCgYIBgAAAA==.Kimashi:BAAANQAECgIIBAAAAA==.Kissme:BAABNQAECn8uAAMVAAoK8RB3MwB/AQAVAAkKPhB3MwB/AQAZAAYK5AlaYwBBAQAAAA==.Kitamor:BAABNQAECn9IAAMZAAoKLwlkMwBxAQAZAAoKJwlkMwBxAQAOAAQKcwnvSwB5AAAAAA==.',
Kl='Kletian:BAAANQAECgYIBgABNQAECgoKPAAQAL8gAA==.',
Ko='Koriakin:BAABNQAECn8cAAMQAAoKkx4yHgDIAgAQAAoKkx4yHgDIAgAiAAEK5gawZgAzAAAAAA==.Korogth:BAAANQAECgYICAAAAA==.Kosmo:BAABNQAECn8xAAIgAAoKYBZTBgANAgAgAAoKYBZTBgANAgAAAA==.',
Kr='Krisyum:BAAANQAECgQIBgAAAA==.Krosmu:BAAANQADCgcIBgAAAA==.Kräsus:BAAANQADCgQIBAABNQAECgoKLAAUAFkhAA==.',
Ku='Kurado:BAAANQAECgIIBAAAAA==.',
Ky='Kyrïn:BAAANQAECgEIAQABNQAFFAYIDwAbAMkWAA==.',
Kz='Kzinn:BAAANQAECgEIAQAAAA==.',
['Kæ']='Kæs:BAAANQADCgUIBQAAAA==.',
['Kö']='Körn:BAAANQAECgQIBwABNQAECgoKKAASAEQTAA==.',
La='Ladyrichter:BAAANQADCggICAAAAA==.Laetus:BAABNQAECn8hAAINAAoK/RkJTgDlAgANAAoK/RkJTgDlAgAAAA==.Lagerthaloth:BAAANQADCgUIBAAAAA==.Laiander:BAABNQAECn8uAAIZAAoKVQ7pKgCpAQAZAAoKVQ7pKgCpAQAAAA==.Laiany:BAABNQAECn84AAIMAAoKex9MHgD4AgAMAAoKex9MHgD4AgAAAA==.Lainarning:BAAANQAECgEIAQAAAA==.Lani:BAAANQAECgIIAQAAAA==.Laolong:BAAANQAECgEIAQAAAA==.',
Le='Leeloo:BAAANQABCgQICAAAAA==.Leeoncamillo:BAAANQADCgYIBgABNQAECgcIGQACAPgEAA==.Leetohro:BAABNQAECn8XAAIUAAcKKAT4kwC4AAAUAAcKKAT4kwC4AAAAAA==.Leodoros:BAABNQAECn8jAAINAAcKAAuVKgFFAQANAAcKAAuVKgFFAQAAAA==.Leric:BAAANQAECgMIBgAAAA==.Lewellin:BAAANQADCgcIEQAAAA==.',
Lh='Lhwei:BAAANQAECgcICAABNQAECgoKTQAKAB0mAA==.',
Li='Lichkíng:BAABNQAECn8WAAMCAAYKxAjdbwDfAAACAAYKxAjdbwDfAAADAAIK2gRT0wBHAAAAAA==.Lifeisalie:BAAANQAECgQIBAAAAA==.Lighty:BAAANQADCggIDQAAAA==.Lihr:BAAANQADCggIEAAAAA==.Lijiang:BAABNQAECn8mAAIaAAgK0yBUBgDpAgAaAAgK0yBUBgDpAgABNQAECgoKLAAUAFkhAA==.Lilianpotter:BAAANQADCgYIBgAAAA==.Lilibel:BAAANQAECgMIAwAAAA==.Lillit:BAABNQAECn8aAAMgAAkKdgdZFwDKAAAgAAYKXwdZFwDKAAAeAAcKEgWX1ACoAAAAAA==.Lindaah:BAAANQADCggINAAAAA==.Lindapriesty:BAAANQADCgIIAgAAAA==.Lirak:BAAANQAECgIIAgAAAA==.Lislfox:BAABNQAECn8oAAIOAAoKCxynEABWAgAOAAoKCxynEABWAgAAAA==.',
Ll='Lledritch:BAAANQADCgUIBQAAAA==.',
Lm='Lmmds:BAAANQADCgcIEwAAAA==.',
Lo='Lockdown:BAABNQAECn8+AAIeAAoKqRTLTwDlAQAeAAoKqRTLTwDlAQAAAA==.Lortheron:BAAANQAECgMIAwAAAA==.',
Lu='Luacs:BAABNQAECn8oAAQSAAoKRBPHZwDVAQASAAgKMRPHZwDVAQAhAAgKWhkkFwCiAQARAAIKfgk3DwFtAAAAAA==.Luccoa:BAABNQAECn8sAAIUAAoKWSHMBwAMAwAUAAoKWSHMBwAMAwAAAA==.Lucyfary:BAAANQADCgcICAAAAA==.Luhhrogue:BAAANQAECgMIAwAAAA==.Lunirah:BAAANQADCgYICAAAAA==.',
Ly='Lylka:BAABNQAECn9QAAMEAAoKoCGwBwDQAgAEAAoKoCGwBwDQAgAGAAcKxyTyKwB2AgAAAA==.',
['Lé']='Léofar:BAABNQAECn8eAAIEAAkK7gP4PgAAAQAEAAkK7gP4PgAAAQAAAA==.',
['Lü']='Lücyfer:BAABNQAECn8YAAIeAAkKFwkmbACUAQAeAAkKFwkmbACUAQAAAA==.',
Ma='Maanu:BAAANQADCgUIBQABNQADCggINAAJAAAAAA==.Maeghann:BAAANQADCgQIAwAAAA==.Magashuave:BAAANQADCgcIBwAAAA==.Magostosaa:BAAANQABCgIIAgAAAA==.Magraver:BAAANQAECgUIBAAAAA==.Makani:BAAANQAECgEIAgAAAA==.Maldock:BAAANQADCgYIBQAAAA==.Malewolyyc:BAABNQAECn8xAAMMAAoKfR+nHQD6AgAMAAoKfR+nHQD6AgABAAQK2w2pTwDTAAAAAA==.Massafera:BAABNQAECn8pAAIFAAkKVxK9nADpAQAFAAkKVxK9nADpAQAAAA==.Mathfacbruxo:BAAANQADCgYJBgABNQAECgoKKgAQAMMcAA==.Mathfacii:BAABNQAECn8qAAIQAAoKwxzlLgDgAgAQAAoKwxzlLgDgAgAAAA==.Mayanyy:BAAANQAECgEIAQAAAA==.',
Mc='Mcq:BAAANQAECgEIAQAAAA==.',
Md='Mdrdark:BAABNQAECn8tAAIDAAoKLBs/LQB+AgADAAoKLBs/LQB+AgAAAA==.',
Me='Medheya:BAAANQADCgIIBAAAAA==.Medz:BAABNQAECn8lAAINAAkKwxcJcQDPAQANAAkKwxcJcQDPAQAAAA==.Meetjack:BAAANQAECgEIAQAAAA==.Meiyin:BAAANQADCggICAAAAA==.Meizu:BAAANQAECgQIDAAAAA==.Mellkor:BAABNQAECn9BAAILAAoKjhzlEQCaAgALAAoKjhzlEQCaAgAAAA==.Meneláu:BAAANQADCggICAAAAA==.Metamorful:BAAANQAECggIDgAAAA==.',
Mi='Mihsi:BAAANQAECgQIBAAAAA==.Milim:BAABNQAECn8uAAQjAAoKUQ0NEwAGAQAjAAkK7wwNEwAGAQAkAAkKFQk2EADdAAAlAAIKZwLMUQApAAAAAA==.Minilock:BAAANQAECgQIBQAAAA==.Mistogunn:BAAANQADCggICAAAAA==.',
Ml='Mls:BAAANQADCgYICwAAAA==.',
Mm='Mmarcão:BAAANQAECgUIBQAAAA==.',
Mo='Modes:BAABNQAECn8nAAIUAAkK9huDJwCDAgAUAAkK9huDJwCDAgAAAA==.Moffir:BAAANQADCgYIBgAAAA==.Mogrus:BAAANQADCgUIAgAAAA==.Mohanninha:BAAANQAECgUIBgAAAA==.Mohotok:BAABNQAECn9IAAIFAAoKZg4+gADMAQAFAAoKZg4+gADMAQAAAA==.Morhome:BAAANQADCgUIBgAAAA==.Morkath:BAAANQADCggICAAAAA==.Mortank:BAAANQAECgEIAQABNQAECgcIDgAJAAAAAA==.Mortixxia:BAABNQAECn8hAAMdAAYKUx26DgAPAgAdAAYKUx26DgAPAgAeAAIKDQ7nFQE4AAAAAA==.',
Mu='Murano:BAABNQAECn8nAAIPAAkK1xaRCABbAgAPAAkK1xaRCABbAgAAAA==.',
['Má']='Máia:BAABNQAECn8UAAIdAAcK/wnOGACaAAAdAAcK/wnOGACaAAAAAA==.',
['Mä']='Mändosz:BAABNQAECn8hAAICAAkKYRgVKABXAgACAAkKYRgVKABXAgAAAA==.',
['Mé']='Ménace:BAAANQAECgIIAgABNQAECggIEAAJAAAAAA==.',
['Mÿ']='Mÿstyna:BAAANQADCgUJCQAAAA==.',
Na='Nagts:BAAANQADCggICgAAAA==.Nalathiel:BAAANQAECggIEwAAAA==.Narancia:BAABNQAECn8gAAINAAoKLBXGSgAuAgANAAoKLBXGSgAuAgABNQAECggIHQAZAO0cAA==.Narrih:BAAANQAECgIIBAAAAA==.Nazawill:BAAANQADCgQIBAAAAA==.Nazdru:BAAANQABCgcICQABNQAECgoKUgAWAGwgAA==.Nazzh:BAAANQAECggIDAABNQAFFAYICQAHADAbAA==.',
Ne='Nefas:BAAANQAECgcICwAAAA==.Nepthunus:BAABNQAECn9HAAImAAoKaR7mAADEAgAmAAoKaR7mAADEAgAAAA==.',
Ni='Niiz:BAAANQAECggICAAAAA==.Nimloth:BAAANQAECggIDwABNQAECggIJAAOAN0IAA==.Ninde:BAAANQADCggIDgAAAA==.',
No='Notforall:BAAANQADCgIIAgAAAA==.',
['Nï']='Nïix:BAAANQADCgYIBgAAAA==.',
['Nö']='Nöirr:BAAANQABCgUIBAAAAA==.',
Od='Odestruidor:BAAANQAECgYICgAAAA==.',
Ol='Oluss:BAABNQAECn8kAAMGAAoKuRETWgALAgAGAAoKuRETWgALAgAFAAEKtwddqQEyAAABNQAECgoKYAAQAGUkAA==.',
On='Onys:BAAANQADCgIIAgAAAA==.',
Oo='Oob:BAAANQAECgcICwAAAA==.',
Op='Opus:BAABNQAECn8bAAMGAAgKcBJwZADrAQAGAAgKcBJwZADrAQAEAAUKSAWRTQCyAAAAAA==.Opusbergen:BAAANQADCgQIBAAAAA==.',
Or='Origon:BAAANQADCggICwAAAA==.Orillan:BAABNQAECn8yAAILAAkKuhTjOgDeAQALAAkKuhTjOgDeAQAAAA==.Ornsteinsnow:BAAANQAECggIDAAAAA==.Orsonn:BAABNQAECn8aAAIGAAgKdQ0FogBAAQAGAAgKdQ0FogBAAQAAAA==.Orucão:BAAANQABCgEIAQAAAA==.Oruism:BAAANQAECgYIBAAAAA==.Orukalango:BAAANQABCgIIAgAAAA==.Orukam:BAABNQAECn8eAAMVAAoKsgy7NAB1AQAVAAoKsgy7NAB1AQAZAAIKMgjaoABcAAAAAA==.Orukanorum:BAAANQADCgcIAwAAAA==.Orukrente:BAAANQABCgIIAgAAAA==.Orulord:BAAANQABCgIIAwAAAA==.Orurage:BAAANQABCgYIBAAAAA==.',
Pa='Painkyller:BAAANQADCggICgAAAA==.Palaha:BAAANQAECgcICwABNQAECgoKYAAQAGUkAA==.Palatina:BAABNQAECn8gAAIFAAkKyx00OQDsAgAFAAkKyx00OQDsAgABNQAECgkJMgAFAAckAA==.Pandalokodj:BAAANQAECgEIAQAAAA==.Pangedrey:BAABNQAECn9GAAMXAAoKFhrNEQBDAgAXAAoKFhrNEQBDAgAKAAMKMw1TMwBtAAAAAA==.Parcival:BAAANQAECgQICgAAAA==.Parký:BAABNQAECn8cAAMSAAkK0h+eFQAKAwASAAkK0h+eFQAKAwARAAEKAACRRQErAAAAAA==.Paullk:BAAANQADCgIIAgAAAA==.',
Pe='Penseur:BAAANQABCgYIBgAAAA==.Peruchi:BAAANQADCgIIAgAAAA==.Perísdra:BAAANQADCgcIDQABNQAECgMICwAJAAAAAA==.',
Pg='Pgms:BAAANQADCggIEgAAAA==.',
Pi='Picu:BAAANQADCgUICQAAAA==.Pistoriane:BAAANQADCggICAABNQAECgoKKgAKANobAA==.Pitombinha:BAABNQAECn8pAAMPAAkK/B6PCgDsAQAPAAgKEByPCgDsAQAHAAQKZRm52ADCAAAAAA==.Pixiks:BAAANQABCgYIBwAAAA==.',
Pp='Ppandora:BAAANQADCggIEgAAAA==.',
Pr='Predadore:BAAANQADCgUIBQAAAA==.',
Py='Pyrix:BAAANQADCgIIAgAAAA==.',
['Pä']='Pändero:BAAANQABCgMIAwAAAA==.',
['Pî']='Pîo:BAACNQAFFH8FAAINAAQKRww4LAAtAQANAAQKRww4LAAtAQA1AAQKf0EAAg0ACgpXIg0sADcDAA0ACgpXIg0sADcDAAAA.',
Qu='Quirow:BAABNQAECn8wAAIRAAoKRw7kUQCSAQARAAoKRw7kUQCSAQAAAA==.',
Ra='Radiação:BAAANQAECgMIAwAAAA==.Radunz:BAABNQAECn9SAAMWAAoKbCBCBADrAgAWAAoKbCBCBADrAgAVAAMKlhURTgDTAAAAAA==.Ragnaros:BAAANQAECgQIBQAAAA==.Ragnarssön:BAAANQAECgYIBwAAAA==.Ragnarøk:BAAANQABCggICgAAAA==.Raio:BAABNQAECn9HAAINAAoKzR4fSwDrAgANAAoKzR4fSwDrAgAAAA==.Ramorey:BAAANQAECgYIDQAAAA==.Ranruulfnarm:BAAANQABCgQICAAAAA==.Rargsa:BAABNQAECn8WAAICAAUKgQNmgQCnAAACAAUKgQNmgQCnAAAAAA==.Rargul:BAAANQAECgQIAwAAAA==.Rariel:BAABNQAECn8lAAILAAoKQxOKPQDNAQALAAoKQxOKPQDNAQAAAA==.Raymain:BAABNQAECn8mAAQKAAkKUBrFGQDjAQAKAAgKFBnFGQDjAQAXAAkKLBdyKQDSAQAaAAEKUgOwKwAhAAAAAA==.Raíka:BAAANQADCggIDQAAAA==.',
Re='Rebimboca:BAAANQAECgEIAQAAAA==.Redoon:BAAANQAECgIIAQAAAA==.Rendoras:BAAANQAECgEIAQAAAA==.Rezadeiro:BAAANQADCgUICQAAAA==.',
Rh='Rhaumarhu:BAAANQADCgcIEgAAAA==.',
Ro='Rockit:BAAANQADCgMICAAAAA==.Rodbree:BAABNQAECn89AAMGAAoKICVDCgB+AwAGAAoKICVDCgB+AwAFAAIKAADEbwFuAAAAAA==.Roguinhu:BAABNQAECn8UAAMbAAcKOgoMJwD8AAAbAAcKOgoMJwD8AAAnAAQK5wTiFwBnAAAAAA==.Roseangel:BAAANQABCgEIAQAAAA==.',
Ru='Rubian:BAAANQADCgYIDAAAAA==.Rudan:BAAANQAECgEIAQAAAA==.Rurumo:BAAANQAECgEIAQAAAA==.Rustovick:BAABNQAECn8cAAIDAAYKIQwXSQDiAAADAAYKIQwXSQDiAAAAAA==.',
['Rä']='Rämzä:BAAANQAECgEIAQABNQAECggIGgAOAIwRAA==.',
['Rå']='Råy:BAABNQAECn8rAAMDAAoKLBwtJwCfAgADAAoKLBwtJwCfAgACAAEKkg48qwA3AAAAAA==.',
Sa='Saalla:BAAANQABCgYIDwABNQAECgoKUgAWAGwgAA==.Saffír:BAABNQAECn83AAIFAAoKMBbFYQAPAgAFAAoKMBbFYQAPAgAAAA==.Sahkev:BAAANQAECgUICAAAAA==.Samalandraa:BAABNQAECn8pAAMRAAkK1hUwMQATAgARAAkKFhMwMQATAgAhAAUKUA98HQBGAQAAAA==.Sanateia:BAAANQAECgQIBgAAAA==.Saniest:BAABNQAECn8rAAMBAAoKxx7EEwDJAgABAAkKvR7EEwDJAgAMAAcKZSFqOwBNAgAAAA==.Sapekinhä:BAABNQAECn8aAAILAAkKVhWgLgAxAgALAAkKVhWgLgAxAgAAAA==.Satanvitória:BAAANQAECgYIEAAAAA==.',
Sc='Scrøøge:BAAANQAECggIEgAAAA==.',
Se='Segavaxx:BAAANQABCgQIBAAAAA==.Selorixie:BAAANQAECgYIDAABNQAECgYIIQAdAFMdAA==.Sereiaa:BAABNQAECn8fAAIQAAoKuwr2jgCYAQAQAAoKuwr2jgCYAQAAAA==.',
Sh='Shadowmore:BAABNQAECn8VAAIgAAkK+gr6CgCYAQAgAAkK+gr6CgCYAQABNQAECgoKQQALAI4cAA==.Shamate:BAAANQAECgUIAgAAAA==.Shanoa:BAAANQAECgQICAAAAA==.Sharae:BAAANQADCggIDQAAAA==.Shaÿane:BAAANQAECgUIBQAAAA==.Shedo:BAABNQAECn8YAAMHAAkKohkEeQAsAgAHAAgKohkEeQAsAgAPAAIKUhqzJwBvAAAAAA==.Shonja:BAAANQAECgUICwAAAA==.Shula:BAAANQADCgYIBgAAAA==.',
Si='Sialeeds:BAAANQADCgMIAwAAAA==.Siclop:BAAANQAECgIIAgAAAA==.Simplicity:BAABNQAECn8aAAMMAAgKwBdCZADzAQAMAAgKwBdCZADzAQABAAMKbxJoVwCtAAAAAA==.Sinton:BAAANQABCgIIAgAAAA==.',
Sk='Skadrian:BAAANQAECgQIBAAAAA==.Skadryan:BAAANQAECgUIDgAAAA==.Skalnark:BAABNQAECn8qAAIeAAoKOA3FXAC+AQAeAAoKOA3FXAC+AQAAAA==.Skinme:BAAANQAECgEIAQAAAA==.Skysoul:BAAANQAECgEJAgAAAA==.',
Sl='Sleeppanda:BAAANQAECgEIAgABNQAECgoKNwAEAJgkAA==.',
So='Sofiela:BAAANQAECgIIAgAAAA==.Soijiro:BAAANQADCgIIAgAAAA==.Soju:BAAANQADCgIIAgAAAA==.Sol:BAAANQADCgQIBAAAAA==.Sombrea:BAAANQADCgcIEQAAAA==.',
Sp='Spectrø:BAAANQADCgcIFAAAAA==.',
Ss='Sstrange:BAAANQAECgEIAQABNQAECgUIBQAJAAAAAA==.',
St='Starkz:BAAANQADCgUIBQAAAA==.Stormswill:BAAANQAECgEIAQAAAA==.Stëlla:BAABNQAECn89AAISAAoKmBx+KACIAgASAAoKmBx+KACIAgAAAA==.',
Su='Suckmyhammer:BAAANQAECgcIDgAAAA==.Sungjinwoo:BAAANQAECgYIEAAAAA==.Sunnara:BAABNQAECn8rAAIoAAoKXhzxFQC0AgAoAAoKXhzxFQC0AgAAAA==.',
Sy='Syuon:BAABNQAECn9NAAIKAAoKHSaqAADcAwAKAAoKHSaqAADcAwAAAA==.',
Sz='Szaa:BAAANQADCgUICAAAAA==.',
Ta='Talandar:BAABNQAECn9YAAIZAAoKphm6FwBTAgAZAAoKphm6FwBTAgAAAA==.Tallgh:BAAANQAECgUIBQAAAA==.Tankoso:BAAANQAECgQIBgABNQAECgUIBQAJAAAAAA==.Tankudo:BAABNQAECn81AAMDAAkKQBpMHwDnAQADAAkKQBpMHwDnAQAUAAIK4xdOlgBCAAAAAA==.Tataloka:BAAANQAECgMIAQAAAA==.',
Te='Tennebra:BAAANQADCggICQAAAA==.',
Th='Thabitah:BAABNQAECn9SAAIBAAoKJBUvEwAqAgABAAoKJBUvEwAqAgAAAA==.Thanathus:BAAANQAECgIIAQAAAA==.Thaumiel:BAAANQADCgEIAQAAAA==.Thedragon:BAABNQAECn9GAAMQAAoKdiKtFAD3AgAQAAoKdiKtFAD3AgAiAAEKfxOZWwBEAAAAAA==.Thorkel:BAAANQAECgIIAgAAAA==.Thotamon:BAAANQAECgUIDAAAAA==.Thýah:BAAANQAECgYICAAAAA==.',
Ti='Tidim:BAAANQADCgcIEAAAAA==.Tiih:BAAANQABCgUIBwAAAA==.',
To='Tonypaludo:BAAANQAECgEIAQAAAA==.',
Tr='Trueperceval:BAAANQABCgQIBgAAAA==.',
Tu='Tushui:BAAANQADCgMIAwAAAA==.',
Ur='Uriuri:BAAANQABCggIEgABNQAECgoKUgAWAGwgAA==.',
Us='Usfull:BAABNQAECn8oAAMMAAoKrhduWwAPAgAMAAoKrhduWwAPAgABAAIKsQOhagBYAAAAAA==.',
Va='Vaatu:BAAANQADCgMIBAAAAA==.Vaeltor:BAAANQAECggIBQAAAA==.Valegás:BAAANQAECgcICgAAAA==.Vallentyne:BAAANQAECgUIBAAAAA==.Vallkÿria:BAAANQAECgcIDAAAAA==.Varrex:BAAANQAECgEIAQAAAA==.Vaëllen:BAABNQAECn8kAAMOAAgK3QihOwDTAAAOAAgK3QihOwDTAAAZAAEKAAC7wAAhAAAAAA==.',
Ve='Vehuiáh:BAABNQAECn8bAAIGAAkK8xPjVQC+AQAGAAkK8xPjVQC+AQAAAA==.Vehuzito:BAAANQAECgUIBQABNQAECgkJGwAGAPMTAA==.Velen:BAABNQAECn9hAAMDAAoKeCNuAwBJAwADAAoKeCNuAwBJAwACAAEKswg8tgAzAAAAAA==.Verno:BAAANQAECgIIAgAAAA==.Verzuk:BAAANQAECggIDQAAAA==.',
Vi='Vintejulgar:BAAANQABCggICQAAAA==.Vintekilo:BAABNQAECn8hAAIFAAoKVA2unADpAQAFAAoKVA2unADpAQAAAA==.Vinteservir:BAAANQABCgQIBAAAAA==.',
Vo='Voiddh:BAACNQAFFH8JAAIoAAUK+AwqCQDPAAAoAAUK+AwqCQDPAAA1AAQKfz0AAigACgpoFuwUABkCACgACgpoFuwUABkCAAAA.',
Vr='Vrenshrrgn:BAAANQAECgEIAgAAAA==.',
Vy='Vygh:BAABNQAECn9GAAMeAAoKsR8lIgD7AgAeAAoKsR8lIgD7AgAdAAEKuAs4eQA0AAAAAA==.Vyndrill:BAABNQAECn8qAAIcAAkKyBT4HQDjAQAcAAkKyBT4HQDjAQAAAA==.',
Wa='Walkers:BAABNQAECn8vAAIQAAoK1xOXVQBxAgAQAAoK1xOXVQBxAgAAAA==.Warlaka:BAAANQADCgYICwAAAA==.',
We='Weevil:BAAANQADCgYICgAAAA==.Wezen:BAAANQADCgMIAwAAAA==.',
Wo='Worgenbelfin:BAAANQADCggIDQAAAA==.',
Wy='Wyrel:BAAANQADCgQICAAAAA==.',
Xa='Xalmoria:BAAANQAECgcICgAAAA==.',
Xu='Xurumeloun:BAAANQADCgYIBgAAAA==.',
Ya='Yamii:BAAANQAECgQIBgAAAA==.Yasmini:BAAANQABCgEIAQAAAA==.',
Ye='Yenom:BAAANQADCgIIAgAAAA==.',
Yi='Yingsu:BAABNQAECn8cAAMXAAoKFR2CGACDAgAXAAoKshyCGACDAgAaAAYK6RAHHAAmAQAAAA==.Yippwarr:BAAANQADCgMIBAAAAA==.',
Yu='Yunná:BAAANQADCgYICgAAAA==.',
Yv='Yvin:BAAANQAECgIIAgAAAA==.',
Za='Zakir:BAAANQAECgUICQAAAA==.Zaolron:BAAANQADCgIIAQAAAA==.Zawarudo:BAAANQADCggICAAAAA==.',
Ze='Zeddshm:BAAANQAECgEIAQABNQAECgoKOQAHABYXAA==.',
Zh='Zhynah:BAAANQADCgUIBQAAAA==.',
Zi='Zibrautar:BAAANQADCgIIAgAAAA==.Ziracruz:BAAANQAECgQICAAAAA==.',
Zu='Zulyn:BAAANQADCgcIFwAAAA==.',
['Àr']='Àrdath:BAAANQAECgQIBQAAAA==.Àrthemís:BAAANQADCgEIAQAAAA==.',
['Ár']='Áraujo:BAAANQADCgEJAQABNQADCgUIBQAJAAAAAA==.Árÿä:BAABNQAECn9QAAIQAAoKDRGXYAAGAgAQAAoKDRGXYAAGAgAAAA==.',
['Áy']='Áy:BAAANQAECgEIAQAAAA==.',
['Är']='Äraxy:BAAANQAECgEIAQAAAA==.',
['Èn']='Ènoia:BAAANQAECgQIBAAAAA==.',
['Èv']='Èver:BAAANQADCgIIAgAAAA==.',
['Ðh']='Ðh:BAAANQAECgQIAgAAAA==.',
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
