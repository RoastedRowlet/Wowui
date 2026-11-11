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

local lookup = {'Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Protection','Paladin-Retribution','Warrior-Arms','Warrior-Protection','Unknown-Unknown','Monk-Mistweaver','DemonHunter-Havoc','Priest-Holy','Mage-Arcane','Druid-Guardian','Warrior-Fury','Hunter-BeastMastery','DemonHunter-Vengeance','DeathKnight-Blood','Shaman-Elemental','Druid-Restoration','Druid-Feral','Monk-Windwalker','Mage-Frost','Druid-Balance','Monk-Brewmaster','Rogue-Subtlety','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','Priest-Discipline','Shaman-Restoration','Warlock-Affliction','Shaman-Enhancement','Hunter-Marksmanship','Paladin-Holy','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Mage-Fire','Rogue-Outlaw','DemonHunter-Devourer',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abaca:BAAANQAECgIIAgAAAA==.Abacatte:BAAANQAECgQICAAAAA==.',
Ad='Adelaide:BAAANQADCgUIBwABNQAFFAgIGQABALoQAA==.',
Ae='Aelthor:BAAANQAECgQIBQAAAA==.',
Al='Alanie:BAAANQAECgcICwAAAA==.Aleriastorm:BAAANQABCgIIAgAAAA==.Alessaxd:BAABNQAECn8eAAMCAAoKfg6iQwC1AQACAAoKpQ2iQwC1AQADAAUKUA11OgAcAQAAAA==.Alfajhor:BAABNQAECn9JAAMEAAoKOyWPAgCjAwAEAAoKOyWPAgCjAwAFAAEKAACqvQEAAAAAAA==.Alfajhòr:BAAANQAECgEIAQAAAA==.Alfajhõr:BAAANQAECgYICgAAAA==.Alkaid:BAABNQAECn83AAMGAAoKVhhmRAAkAgAGAAkKPRhmRAAkAgAHAAgK+gsTIwAxAQAAAA==.Alladryel:BAAANQADCgYIBgAAAA==.Allandriel:BAAANQAECgEIAQABNQAECgYIEAAIAAAAAA==.Alleriane:BAABNQAECn8qAAIJAAoK2huDDwCIAgAJAAoK2huDDwCIAgAAAA==.Allone:BAABNQAECn8/AAIKAAoKMw9HKwCfAQAKAAoKMw9HKwCfAQAAAA==.Allunt:BAAANQAECgcICgAAAA==.Almin:BAAANQAECgIIBQAAAA==.Alruna:BAAANQAECgIIAgAAAA==.',
Am='Ametnys:BAAANQAECgUICgAAAA==.Amonhar:BAAANQAECgUIBAABNQAECgoKKAALAK4XAA==.',
An='Anakata:BAAANQAECgcIDQAAAA==.Andaliz:BAABNQAECn8yAAIFAAkKByR9BwC+AwAFAAkKByR9BwC+AwAAAA==.Andaril:BAAANQAECgUIDAAAAA==.Antonel:BAAANQABCgYIBgAAAA==.Antonellaes:BAAANQAECgEIAQABNQAECgcIGQACAPgEAA==.',
Ap='Aprocom:BAAANQAECgUICwAAAA==.',
Ar='Arcanör:BAABNQAECn8bAAIMAAgKsg0D9QChAQAMAAgKsg0D9QChAQAAAA==.Arctorius:BAABNQAECn8XAAMFAAcKaQxe0AB7AQAFAAcKaQxe0AB7AQAEAAEKAADzdgAmAAAAAA==.Aronys:BAAANQAECgYIEAAAAA==.Arquitetö:BAAANQADCgIIAgAAAA==.Arthashand:BAAANQADCgEIAQAAAA==.Artronis:BAABNQAECn81AAINAAoKaRP6EwAkAgANAAoKaRP6EwAkAgAAAA==.Arukäi:BAABNQAECn8hAAMGAAgKxwr0qwCvAQAGAAgKxwr0qwCvAQAOAAMKgQdWKQBlAAAAAA==.Arägørn:BAABNQAECn8UAAIFAAUKPwczHQGpAAAFAAUKPwczHQGpAAAAAA==.',
As='Assintomatic:BAAANQABCgYICQABNQAECggIDgAIAAAAAA==.',
At='Atriuz:BAAANQAECgQIDAAAAA==.Ats:BAAANQADCggIEQAAAA==.',
Au='Aurín:BAAANQADCgQIBAAAAA==.',
Az='Azarado:BAAANQAECggIBgAAAA==.Azerotiano:BAABNQAECn8XAAIPAAgKHgcQqwBBAQAPAAgKHgcQqwBBAQAAAA==.',
['Aÿ']='Aÿ:BAAANQAECgEIAQAAAA==.',
Ba='Badhealer:BAAANQAECgYIEAAAAA==.Baldraccus:BAAANQADCgcIBwAAAA==.Balk:BAABNQAECn88AAIPAAoKvyBZIAAWAwAPAAoKvyBZIAAWAwAAAA==.Bambur:BAAANQADCggICgAAAA==.Barauna:BAAANQABCgIIAgAAAA==.Barbabruto:BAABNQAECn8lAAMHAAoKfhpECwCIAgAHAAoKShlECwCIAgAOAAIKRxyPHwCXAAAAAA==.Barbacancer:BAAANQAECgcICAAAAA==.Barbalock:BAAANQAECgIIAgAAAA==.Barbasanta:BAAANQAECgQICAABNQAECgoKJQAHAH4aAA==.Batgirl:BAABNQAECn8ZAAMQAAoKaw1SEAAsAQAQAAgKIgxSEAAsAQAKAAcKpQ0uRAAJAQAAAA==.',
Be='Belthorsin:BAAANQADCgYIBgAAAA==.Belthorvil:BAAANQADCgEIAQAAAA==.',
Bi='Bigbag:BAAANQADCgQIBQAAAA==.Biønic:BAAANQAECgUIEQAAAA==.',
Bl='Blackmoonx:BAABNQAECn8YAAICAAkKjx3LKgBFAgACAAkKjx3LKgBFAgABNQAECggIFwAGAGIiAA==.Blackninja:BAAANQABCggIGwAAAA==.Blu:BAEANQAECgEIAQABNQAECgYIEQAIAAAAAA==.',
Bo='Box:BAAANQADCgMIAwAAAA==.',
Br='Brahman:BAAANQAECgEIAQAAAA==.Bratloko:BAAANQADCgMIAwAAAA==.Bright:BAAANQADCgYIBgAAAA==.Brinston:BAAANQADCgUICgABNQAFFAYICAALAEgNAA==.Bruex:BAAANQADCgIIAgAAAA==.Bruker:BAAANQADCgIIAwAAAA==.Brutalhoof:BAAANQAECgEIAgAAAA==.',
Bu='Buzzumaaky:BAABNQAECn8VAAIMAAcKPhdYuAATAgAMAAcKPhdYuAATAgAAAA==.',
By='Bynhu:BAAANQADCggICAAAAA==.',
['Bá']='Bávor:BAAANQADCgEIAQAAAA==.',
['Bí']='Bílly:BAAANQAECgEIAQAAAA==.',
['Bü']='Büdweiser:BAAANQAECgEIAQAAAA==.',
Ca='Calteryeker:BAAANQAECgMICwAAAA==.Capitu:BAAANQADCggIEwABNQAECgkJJwARAPYbAA==.Capyvara:BAAANQABCgYIBwAAAA==.Caralh:BAACNQAFFH8FAAIRAAQKfg9MJABsAAARAAQKfg9MJABsAAA1AAQKfzAAAxEACgrEHasRAB8DABEACQq+IKsRAB8DAAMAAQrxCJWDADUAAAAA.Caroll:BAAANQADCgMIAwAAAA==.Caçaorda:BAAANQAECgMJBAAAAA==.',
Ce='Ceciliah:BAACNQAFFH8QAAISAAQKUBBBEADcAAASAAQKUBBBEADcAAA1AAQKf0cAAhIACgqMIosQAN4CABIACgqMIosQAN4CAAAA.Cernûnnos:BAABNQAECn8bAAMTAAcKURhPKQCIAQATAAcKURhPKQCIAQAUAAEKAABETQAdAAAAAA==.',
Ch='Champdude:BAABNQAECn9IAAMVAAoK0x2wFwCNAgAVAAkKzR6wFwCNAgAJAAkK8hGNEADuAQAAAA==.Chifrelda:BAAANQADCgUIBQAAAA==.Chopquatro:BAAANQADCggICAAAAA==.Chopum:BAAANQAECggICAAAAA==.Chrnnos:BAAANQAECgcICwABNQAECgkJKAAOAPweAA==.',
Co='Coffeebean:BAAANQAECgMIBAAAAA==.Corineus:BAAANQADCgYIDQAAAA==.Cowzeroth:BAABNQAECn84AAISAAoKbSBFFAC9AgASAAoKbSBFFAC9AgABNQAECgoKPAAPAL8gAA==.',
Cr='Crassustitan:BAAANQAECggICQAAAA==.Cristcalad:BAABNQAECn8kAAMHAAcKqxNLIgA4AQAHAAYKTxZLIgA4AQAGAAcKSQ1RoAAoAQAAAA==.',
Cu='Cutia:BAAANQAECgEIAQAAAA==.',
Da='Daemi:BAAANQAECggIEAAAAA==.Dakael:BAAANQABCgYIDgABNQAECgoKSQAUAM8fAA==.Dalaty:BAAANQAECgUIEgAAAA==.Daresh:BAAANQADCgEIAQAAAA==.Dariok:BAABNQAECn8kAAIGAAgKDQW2vADoAAAGAAgKDQW2vADoAAAAAA==.Darkove:BAABNQAECn8qAAIWAAoKHRAsDQDgAQAWAAoKHRAsDQDgAQAAAA==.Darrow:BAABNQAECn82AAICAAoKVRVsNAALAgACAAoKVRVsNAALAgAAAA==.Daryan:BAAANQAECgcIDwAAAA==.Day:BAAANQAECgQIBQAAAA==.',
De='Deathinhu:BAABNQAECn9IAAIMAAoK0x/3JACgAgAMAAoK0x/3JACgAgAAAA==.Demoriana:BAABNQAECn8ZAAMCAAcK+AQ1fQCzAAACAAcKHQQ1fQCzAAARAAQKbwTThQBWAAAAAA==.Dethroned:BAAANQAECgQICgAAAA==.',
Di='Digaolock:BAAANQAECgEIAQAAAA==.Digaoxdrx:BAAANQADCgQIBAAAAA==.Dimeros:BAABNQAECn9LAAIXAAoK2gsWKwCRAQAXAAoK2gsWKwCRAQAAAA==.Divano:BAABNQAECn9EAAIBAAoKACCvCADMAgABAAoKACCvCADMAgAAAA==.',
Dk='Dkats:BAAANQADCggIDAAAAA==.Dkhalifa:BAAANQADCgYIBgAAAA==.',
Do='Dogowner:BAAANQAECgcIBwAAAA==.Donora:BAAANQAECgQIBAAAAA==.Dorfillaw:BAAANQAECgUICQAAAA==.Dorvana:BAAANQADCgMJAwABNQAECgkJMgAFAAckAA==.',
Dr='Dracthyrius:BAAANQAECgEIAQAAAA==.Draenthar:BAAANQAECgEIAQAAAA==.Dragonstyle:BAAANQAECgcICwAAAA==.Dragony:BAAANQADCgQIBAAAAA==.Dreez:BAAANQAECgUICAAAAA==.Drexus:BAAANQADCgMIAwAAAA==.Drigolas:BAAANQADCgYICAAAAA==.Druidblack:BAAANQADCgUIBQAAAA==.',
Eh='Ehomi:BAAANQADCgIIAgAAAA==.',
Ei='Eirin:BAABNQAECn8eAAIYAAUK1xU/HQAUAQAYAAUK1xU/HQAUAQAAAA==.',
El='Eldris:BAAANQADCgEIAQAAAA==.Elidibus:BAAANQADCgQIBAAAAA==.Elistraee:BAAANQADCgEIAQAAAA==.Ellvarg:BAAANQADCgYIDAAAAA==.Eluuria:BAABNQAECn8gAAIFAAoKGBBTngB7AQAFAAoKGBBTngB7AQAAAA==.',
En='Enkrenco:BAAANQADCgQIBAAAAA==.Ennafaryn:BAAANQABCgQIBgAAAA==.Ensabanú:BAAANQADCgQIBAAAAA==.',
Er='Erilaethaen:BAAANQAECgIIAgAAAA==.Erlek:BAAANQADCggIFwAAAA==.Ernest:BAABNQAECn9GAAITAAoKaSAeCgAYAwATAAoKaSAeCgAYAwAAAA==.Erulan:BAAANQADCgQIBwAAAA==.',
Es='Estgan:BAAANQADCgMIAwAAAA==.',
Et='Ether:BAABNQAECn8ZAAIRAAkKrRJRTQDAAQARAAkKrRJRTQDAAQAAAA==.',
Ev='Evangelouco:BAAANQADCgQIBAAAAA==.Evilbarba:BAACNQAFFH8GAAIFAAYK0gyKFAASAQAFAAYK0gyKFAASAQA1AAQKfzYAAgUACQqtHzksAKQCAAUACQqtHzksAKQCAAAA.',
Ex='Exodes:BAAANQAECgMIBAAAAA==.Exort:BAAANQAECgUICwAAAA==.Exothus:BAAANQAECgQJBwAAAA==.',
Fa='Faaver:BAAANQADCgMIAwAAAA==.Faldark:BAAANQADCgUIBQAAAA==.Faranir:BAAANQAECgMIAwAAAA==.Faris:BAABNQAECn84AAMZAAoK+RQQRgDNAQAaAAgKlBYxOAD2AQAZAAkKqBEQRgDNAQABNQAECgoKPAAPAL8gAA==.Faversani:BAABNQAECn8sAAQGAAoKYiLvKgAQAwAGAAoKYiLvKgAQAwAOAAEKChvcKgBMAAAHAAEKCxgkPABAAAAAAA==.Fayla:BAAANQADCgMIAwAAAA==.Faölin:BAABNQAECn8wAAIZAAoKCxeEEQBpAgAZAAoKCxeEEQBpAgAAAA==.',
Fe='Ferael:BAABNQAECn9KAAMFAAoKFiEvGwDtAgAFAAoKFiEvGwDtAgAEAAQKPQkPUACmAAAAAA==.Ferrus:BAAANQAECgQIAwAAAA==.',
Fj='Fjord:BAAANQAECgIIAgAAAA==.',
Fl='Florbela:BAABNQAECn8fAAITAAgKygvAMwB8AQATAAgKygvAMwB8AQAAAA==.',
Fo='Fogue:BAAANQADCgMIAwAAAA==.',
Fr='Fredericc:BAABNQAECn8XAAISAAgKjgoHgQD4AAASAAgKjgoHgQD4AAAAAA==.Freecs:BAABNQAECn8cAAMXAAgKuxwkGQAwAgAXAAgKuxwkGQAwAgAUAAIKtRqMKwCUAAAAAA==.Freyá:BAABNQAECn88AAMEAAoKCh5lEACXAgAEAAoKOB1lEACXAgAFAAkKmRQp3ABjAQAAAA==.Frostburn:BAAANQAECggIEAAAAA==.Froststriker:BAAANQAECgEIAQAAAA==.',
Fu='Fulvo:BAAANQADCgQIBQAAAA==.',
Ga='Gadodamorena:BAAANQAECgEIAQAAAA==.Galfur:BAABNQAECn8cAAIXAAUKOQeAfwDQAAAXAAUKOQeAfwDQAAAAAA==.Galhuda:BAAANQAECggIEwAAAA==.Galica:BAAANQADCgIIAgAAAA==.Gallatheya:BAAANQAECgYIAQAAAA==.Gandwelf:BAAANQADCggICAAAAA==.',
Ge='Geisty:BAAANQAECgEIAQABNQAECgIIBAAIAAAAAA==.Gemius:BAAANQADCgMIAwAAAA==.',
Gl='Glutotwo:BAAANQADCgYIEgAAAA==.',
Go='Goldchain:BAAANQAECgYICAAAAA==.Govers:BAAANQAECgEIAQABNQAECggICgAIAAAAAA==.',
Gr='Grommar:BAAANQADCgUIBQABNQAECgMICwAIAAAAAA==.Grumax:BAABNQAECn8YAAIFAAcKkAvs1wBsAQAFAAcKkAvs1wBsAQAAAA==.',
Gu='Gudeath:BAABNQAECn8vAAIGAAkKnxWJiAAHAgAGAAkKnxWJiAAHAgAAAA==.Guerrerinhow:BAABNQAECn8UAAIGAAkK7AMIuwDsAAAGAAkK7AMIuwDsAAABNQAECgoKNAAXAAIPAA==.Guitianki:BAAANQADCggIEgAAAA==.Gulek:BAAANQAECgYIBAAAAA==.Gussg:BAABNQAECn8oAAMbAAkKUxRrBgBjAQAbAAcKTBZrBgBjAQAcAAYKqwjo4QAFAQAAAA==.',
['Gà']='Gàladriel:BAABNQAECn8YAAITAAYKQhWwLQBlAQATAAYKQhWwLQBlAQAAAA==.',
['Gö']='Göhan:BAABNQAECn8aAAINAAgKjBFwHwBwAQANAAgKjBFwHwBwAQAAAA==.',
['Gø']='Gøvers:BAAANQAECggICgAAAA==.',
['Gü']='Güttz:BAABNQAECn8jAAIKAAgKSRGCOwDaAQAKAAgKSRGCOwDaAQAAAA==.',
Ha='Hagires:BAAANQAECgYIBwAAAA==.Hanaluna:BAAANQADCggICAAAAA==.Harchus:BAAANQAECgEIAQAAAA==.Hargarthul:BAAANQADCgMIBAAAAA==.Hazell:BAAANQADCggIDQAAAA==.',
He='Heaveth:BAAANQADCgYIAgABNQAECgoKUwASAGoeAA==.Hellspont:BAABNQAECn8tAAQUAAoKiCCpBwBlAgAUAAkKWyCpBwBlAgATAAcKLBUmIwC/AQANAAIKzxv/RgCVAAAAAA==.Hendrikison:BAAANQAECgIIAwAAAA==.',
Ho='Horagalles:BAAANQADCgIIAgAAAA==.Hotmojo:BAACNQAFFH8SAAIMAAUKdRkdHwDyAAAMAAUKdRkdHwDyAAA1AAQKf0wAAgwACgpUIlcgALUCAAwACgpUIlcgALUCAAAA.',
Hu='Hunfox:BAABNQAECn9cAAIPAAoKXyTACQCPAwAPAAoKXyTACQCPAwAAAA==.Hunterhearst:BAAANQADCgYIBwAAAA==.Huor:BAAANQAECgQIBAAAAA==.',
Hy='Hylana:BAAANQADCggICAAAAA==.',
['Hö']='Hölycrüsh:BAACNQAFFH8HAAIFAAMK3yKyFQDOAAAFAAMK3yKyFQDOAAA1AAQKf0gAAgUACgoEJbMNADMDAAUACgoEJbMNADMDAAAA.',
Ih='Ihntwuaed:BAAANQADCgQIBwAAAA==.',
Ik='Ikoo:BAABNQAECn8pAAIdAAoKWRlJAgCiAgAdAAoKWRlJAgCiAgAAAA==.',
Il='Illaril:BAACNQAFFH8aAAIQAAYKdAttAgAZAQAQAAYKdAttAgAZAQA1AAQKfzcAAhAACgrPHGQFAFYCABAACgrPHGQFAFYCAAAA.',
In='Indarion:BAAANQAECgMIAwAAAA==.Interestelar:BAAANQADCgYIBgAAAA==.Invisiblelol:BAAANQAECgUICgAAAA==.',
Ir='Irmãodouther:BAAANQAECggIDgAAAA==.Irridan:BAAANQADCggICQAAAA==.',
Is='Isenhearth:BAAANQABCgUIBQAAAA==.Ishtarie:BAABNQAECn8gAAIeAAoKbR0MLwClAgAeAAoKbR0MLwClAgAAAA==.',
Iv='Ivina:BAABNQAECn9KAAMcAAoK+h1VHwCKAgAcAAoK+h1VHwCKAgAfAAEKjwasMwAsAAAAAA==.',
Iz='Izaar:BAAANQADCggIGQAAAA==.',
Ja='Jangeoffry:BAAANQABCgMIAwAAAA==.',
Jh='Jhonatinha:BAAANQAECgUIBwAAAA==.',
Jk='Jks:BAAANQAECgYICAAAAA==.',
Ju='Jullianxd:BAAANQAECgYIDQAAAA==.Junjih:BAAANQAECgUIBQABNQAECgkJHAAcAHAVAA==.',
Ka='Kaallew:BAAANQAECggIDgAAAA==.Kaallmonge:BAAANQABCgcIBwAAAA==.Kaelonidas:BAAANQAECgQIDAAAAA==.Kaelyaa:BAAANQADCgUIBQAAAA==.Kainer:BAAANQADCgYICQAAAA==.Kalazshar:BAABNQAECn8nAAINAAoKcguRKQBKAQANAAoKcguRKQBKAQAAAA==.Kalduran:BAAANQADCggIPQAAAA==.Kalelzinho:BAAANQADCgYICgAAAA==.Kaluss:BAABNQAECn8mAAMMAAoKrghB6QC3AQAMAAoKTwhB6QC3AQAWAAEKbwsxPgAtAAAAAA==.Kanduz:BAAANQAECgUICAAAAA==.Karlariel:BAAANQAECgUIBQABNQAECgYIEAAIAAAAAA==.Karmabb:BAAANQAECgUICgAAAA==.Kauss:BAAANQAECgIJAgAAAA==.Kavartu:BAACNQAFFH8FAAMSAAIKeAr2HACDAAASAAIKeAr2HACDAAAgAAEKXhDlBwBNAAA1AAQKfzkABBIACgqSGYRFAGACABIACgqSGYRFAGACACAAAgpmCyosAHkAAB4AAQrlAO4LAQ8AAAAA.Kayli:BAAANQADCgcIDgAAAA==.',
Ke='Keillor:BAABNQAECn8tAAMeAAcKXREQYgB6AQAeAAcKXREQYgB6AQASAAUKQwvxwAAQAQAAAA==.Keldorian:BAAANQAECgUIBwAAAA==.Kenzou:BAABNQAECn8iAAIYAAgKkRwvCADDAQAYAAgKkRwvCADDAQAAAA==.Keytymari:BAAANQAECgcIDQAAAA==.',
Kh='Khaliq:BAABNQAECn8lAAIKAAkKzRRKMQAfAgAKAAkKzRRKMQAfAgAAAA==.Khallani:BAAANQADCgIIAgABNQAECgIIBAAIAAAAAA==.',
Ki='Kieran:BAAANQADCgYIBgAAAA==.Kimashi:BAAANQAECgIIBAAAAA==.Kissme:BAABNQAECn8uAAMTAAoK8RB3MwB/AQATAAkKPhB3MwB/AQAXAAYK5AlaYwBBAQAAAA==.Kitamor:BAABNQAECn9EAAMXAAoKYgj/MABpAQAXAAoKWgj/MABpAQANAAQKcwnvSwB5AAAAAA==.',
Kl='Kletian:BAAANQAECgYIBgABNQAECgoKPAAPAL8gAA==.',
Ko='Koriakin:BAABNQAECn8bAAMPAAoKkx54GQDSAgAPAAoKkx54GQDSAgAhAAEK5gYOYgAzAAAAAA==.Korogth:BAAANQAECgYICAAAAA==.Kosmo:BAABNQAECn8uAAIfAAoKRRafBQARAgAfAAoKRRafBQARAgAAAA==.',
Kr='Krisyum:BAAANQAECgQIBQAAAA==.Krosmu:BAAANQADCgcIBgAAAA==.Kräsus:BAAANQADCgQIBAABNQAECgoKIwARAAEhAA==.',
Ku='Kurado:BAAANQAECgIIBAAAAA==.',
Ky='Kyrïn:BAAANQAECgEIAQABNQAFFAYIDwAaAMkWAA==.',
Kz='Kzinn:BAAANQAECgEIAQAAAA==.',
['Kæ']='Kæs:BAAANQADCgUIBQAAAA==.',
['Kö']='Körn:BAAANQAECgQIBwABNQAECgoKKAAeAEQTAA==.',
La='Laetus:BAABNQAECn8hAAIMAAoK/RkJTgDlAgAMAAoK/RkJTgDlAgAAAA==.Lagerthaloth:BAAANQADCgUIBAAAAA==.Laiander:BAABNQAECn8qAAIXAAoKKQ4XKACoAQAXAAoKKQ4XKACoAQAAAA==.Laiany:BAABNQAECn84AAILAAoKex9MHgD4AgALAAoKex9MHgD4AgAAAA==.Lainarning:BAAANQAECgEIAQAAAA==.Lani:BAAANQAECgIIAQAAAA==.Laolong:BAAANQAECgEIAQAAAA==.',
Le='Leeloo:BAAANQABCgQICAAAAA==.Leeoncamillo:BAAANQADCgYIBgABNQAECgcIGQACAPgEAA==.Leetohro:BAABNQAECn8XAAIRAAcKKAT4kwC4AAARAAcKKAT4kwC4AAAAAA==.Leodoros:BAABNQAECn8jAAIMAAcKAAuVKgFFAQAMAAcKAAuVKgFFAQAAAA==.Leric:BAAANQAECgMIBgAAAA==.Lewellin:BAAANQADCggIDgAAAA==.',
Lh='Lhwei:BAAANQAECgcICAABNQAECgoKTAAJAB0mAA==.',
Li='Lichkíng:BAABNQAECn8WAAMCAAYKxAjdbwDfAAACAAYKxAjdbwDfAAADAAIK2gRT0wBHAAAAAA==.Lifeisalie:BAAANQAECgQIBAAAAA==.Lighty:BAAANQADCggIDQAAAA==.Lihr:BAAANQADCggIEAAAAA==.Lijiang:BAABNQAECn8mAAIYAAgK0yBUBgDpAgAYAAgK0yBUBgDpAgABNQAECgoKIwARAAEhAA==.Lilianpotter:BAAANQADCgYIBgAAAA==.Lilibel:BAAANQAECgMIAwAAAA==.Lillit:BAABNQAECn8XAAMfAAcKIgcjHwBqAAAcAAcKEgVWywCoAAAfAAQKwwYjHwBqAAAAAA==.Lindaah:BAAANQADCggINAAAAA==.Lindapriesty:BAAANQADCgIIAgAAAA==.Lirak:BAAANQAECgIIAgAAAA==.Lislfox:BAABNQAECn8oAAINAAoKCxynEABWAgANAAoKCxynEABWAgAAAA==.',
Ll='Lledritch:BAAANQADCgUIBQAAAA==.',
Lm='Lmmds:BAAANQADCgcIEwAAAA==.',
Lo='Lockdown:BAABNQAECn8+AAIcAAoKqRTPRwDrAQAcAAoKqRTPRwDrAQAAAA==.Lortheron:BAAANQAECgIIAgAAAA==.',
Lu='Luacs:BAABNQAECn8oAAQeAAoKRBPHZwDVAQAeAAgKMRPHZwDVAQAgAAgKWhleFQCkAQASAAIKfgk3DwFtAAAAAA==.Luccoa:BAABNQAECn8jAAIRAAoKASHBCAD4AgARAAoKASHBCAD4AgAAAA==.Lucyfary:BAAANQADCgcICAAAAA==.Luhhrogue:BAAANQAECgMIAwAAAA==.Lunirah:BAAANQADCgYICAAAAA==.',
Ly='Lylka:BAABNQAECn9HAAMEAAoKYiH1BwC6AgAEAAoKYiH1BwC6AgAiAAcKxyRYKAB5AgAAAA==.',
['Lé']='Léofar:BAABNQAECn8eAAIEAAkK7gP/NwC9AAAEAAkK7gP/NwC9AAAAAA==.',
['Lü']='Lücyfer:BAAANQAECgcIEQAAAA==.',
Ma='Maanu:BAAANQADCgUIBQABNQADCggINAAIAAAAAA==.Maeghann:BAAANQADCgQIAwAAAA==.Magashuave:BAAANQADCgcIBwAAAA==.Magostosaa:BAAANQABCgIIAgAAAA==.Magraver:BAAANQAECgUIBAAAAA==.Makani:BAAANQAECgEIAgAAAA==.Maldock:BAAANQADCgYIBQAAAA==.Malewolyyc:BAABNQAECn8xAAMLAAoKfR+nHQD6AgALAAoKfR+nHQD6AgABAAQK2w2pTwDTAAAAAA==.Massafera:BAABNQAECn8pAAIFAAkKVxK9nADpAQAFAAkKVxK9nADpAQAAAA==.Mathfacbruxo:BAAANQADCgYJBgABNQAECggIIQAPAH8gAA==.Mathfacii:BAABNQAECn8hAAIPAAgKfyDlLgDgAgAPAAgKfyDlLgDgAgAAAA==.Mayanyy:BAAANQAECgEIAQAAAA==.',
Mc='Mcq:BAAANQAECgIIAQAAAA==.',
Md='Mdrdark:BAABNQAECn8tAAIDAAoKLBv7GgD7AQADAAoKLBv7GgD7AQAAAA==.',
Me='Medheya:BAAANQADCgIIAgAAAA==.Medz:BAABNQAECn8lAAIMAAkKwxenaQDPAQAMAAkKwxenaQDPAQAAAA==.Meetjack:BAAANQAECgEIAQAAAA==.Meiyin:BAAANQADCggICAAAAA==.Meizu:BAAANQAECgQJDAAAAA==.Mellkor:BAABNQAECn81AAIKAAkKABvjHAASAgAKAAkKABvjHAASAgAAAA==.Meneláu:BAAANQADCggICAAAAA==.Metamorful:BAAANQAECggIDgAAAA==.',
Mi='Mihsi:BAAANQAECgQIBAAAAA==.Milim:BAABNQAECn8sAAQjAAoKBg0EEgADAQAjAAkKmQwEEgADAQAkAAkKFQklDwDeAAAlAAIKZwLMUQApAAAAAA==.Minilock:BAAANQAECgQIBQAAAA==.Mistogunn:BAAANQADCggICAAAAA==.',
Ml='Mls:BAAANQADCgYICwAAAA==.',
Mm='Mmarcão:BAAANQAECgUIBQAAAA==.',
Mo='Modes:BAABNQAECn8nAAIRAAkK9huDJwCDAgARAAkK9huDJwCDAgAAAA==.Moffir:BAAANQADCgYIBgAAAA==.Mogrus:BAAANQADCgUIAgAAAA==.Mohanninha:BAAANQAECgUIBgAAAA==.Mohotok:BAABNQAECn8/AAIFAAoK+g3LdgDNAQAFAAoK+g3LdgDNAQAAAA==.Monshiro:BAAANQAECgEIAQABNQAECggIHAAXALscAA==.Morhome:BAAANQADCgUIBgAAAA==.Morkath:BAAANQADCggICAAAAA==.Mortank:BAAANQAECgEIAQABNQAECgcIDgAIAAAAAA==.Mortixxia:BAABNQAECn8hAAMbAAYKUx26DgAPAgAbAAYKUx26DgAPAgAcAAIKDQ43DQE4AAAAAA==.',
Mu='Murano:BAABNQAECn8nAAIOAAkK1xaRCABbAgAOAAkK1xaRCABbAgAAAA==.',
['Má']='Máia:BAABNQAECn8UAAIbAAcK/wkOFwCbAAAbAAcK/wkOFwCbAAAAAA==.',
['Mä']='Mändosz:BAABNQAECn8hAAICAAkKYRgVKABXAgACAAkKYRgVKABXAgAAAA==.',
['Mé']='Ménace:BAAANQAECgIIAgABNQAECggIEAAIAAAAAA==.',
['Mÿ']='Mÿstyna:BAAANQADCgUJCQAAAA==.',
Na='Nagts:BAAANQADCggICgAAAA==.Nalathiel:BAAANQAECggIEgAAAA==.Narancia:BAABNQAECn8fAAIMAAoKLBWpRAAxAgAMAAoKLBWpRAAxAgABNQAECggIHAAXALscAA==.Narrih:BAAANQAECgIIBAAAAA==.Nazawill:BAAANQADCgQIBAAAAA==.Nazdru:BAAANQABCgcICQABNQAECgoKSQAUAM8fAA==.Nazzh:BAAANQAECggIDAABNQAFFAYICQAGADAbAA==.',
Ne='Nefas:BAAANQAECgcICwAAAA==.Nepthunus:BAABNQAECn8+AAImAAoKpx3qAACuAgAmAAoKpx3qAACuAgAAAA==.',
Ni='Niiz:BAAANQAECggICAAAAA==.Nimloth:BAAANQAECggIDwABNQAECggIJAANAN0IAA==.Ninde:BAAANQADCggIDgAAAA==.',
No='Notforall:BAAANQADCgIIAgAAAA==.',
['Nï']='Nïix:BAAANQADCgYIBgAAAA==.',
['Nö']='Nöirr:BAAANQABCgUIBAAAAA==.',
Od='Odestruidor:BAAANQAECgUICgAAAA==.',
Ol='Oluss:BAABNQAECn8kAAMiAAoKuRETWgALAgAiAAoKuRETWgALAgAFAAEKtwddqQEyAAABNQAECgoKXAAPAF8kAA==.',
On='Onys:BAAANQADCgIIAgAAAA==.',
Oo='Oob:BAAANQAECgcICwAAAA==.',
Op='Opus:BAABNQAECn8bAAMiAAgKcBJwZADrAQAiAAgKcBJwZADrAQAEAAUKSAWRTQCyAAAAAA==.Opusbergen:BAAANQADCgQIBAAAAA==.',
Or='Origon:BAAANQADCggICwAAAA==.Orillan:BAABNQAECn8yAAIKAAkKuhTjOgDeAQAKAAkKuhTjOgDeAQAAAA==.Ornsteinsnow:BAAANQAECgMIBAAAAA==.Orsonn:BAABNQAECn8aAAIiAAgKdQ0FogBAAQAiAAgKdQ0FogBAAQAAAA==.Orucão:BAAANQABCgEIAQAAAA==.Oruism:BAAANQAECgYIBAAAAA==.Orukalango:BAAANQABCgIIAgAAAA==.Orukam:BAABNQAECn8eAAMTAAoKsgy7NAB1AQATAAoKsgy7NAB1AQAXAAIKMgjaoABcAAAAAA==.Orukanorum:BAAANQADCgcIAwAAAA==.Orukrente:BAAANQABCgIIAgAAAA==.Orulord:BAAANQABCgIIAwAAAA==.Orurage:BAAANQABCgYIBAAAAA==.',
Pa='Painkyller:BAAANQADCggICgAAAA==.Palaha:BAAANQAECgcICwABNQAECgoKXAAPAF8kAA==.Palatina:BAABNQAECn8gAAIFAAkKyx00OQDsAgAFAAkKyx00OQDsAgABNQAECgkJMgAFAAckAA==.Pandalokodj:BAAANQAECgEIAQAAAA==.Pangedrey:BAABNQAECn9CAAMVAAoK8xn5EAA7AgAVAAoK8xn5EAA7AgAJAAMKMw1EMABwAAAAAA==.Parcival:BAAANQAECgMIBgAAAA==.Parký:BAABNQAECn8cAAMeAAkK0h/5EgAOAwAeAAkK0h/5EgAOAwASAAEKAACRRQErAAAAAA==.Paullk:BAAANQADCgIIAgAAAA==.',
Pe='Penseur:BAAANQABCgYIBgAAAA==.Peruchi:BAAANQADCgIIAgAAAA==.Perísdra:BAAANQADCgcIDQABNQAECgMICwAIAAAAAA==.',
Pg='Pgms:BAAANQADCggIEgAAAA==.',
Pi='Picu:BAAANQADCgUICQAAAA==.Pistoriane:BAAANQADCggICAABNQAECgoKKgAJANobAA==.Pitombinha:BAABNQAECn8oAAMOAAkK/B5QCQDxAQAOAAgKEBxQCQDxAQAGAAQKZRmWzQDEAAAAAA==.Pixiks:BAAANQABCgYIBwAAAA==.',
Pp='Ppandora:BAAANQADCggIEgAAAA==.',
Pr='Predadore:BAAANQADCgUIBQAAAA==.',
Py='Pyrix:BAAANQADCgIIAgAAAA==.',
['Pä']='Pändero:BAAANQABCgMIAwAAAA==.',
['Pî']='Pîo:BAACNQAFFH8FAAIMAAQKRww4LAAtAQAMAAQKRww4LAAtAQA1AAQKfz8AAgwACgpXIg0sADcDAAwACgpXIg0sADcDAAAA.',
Qu='Quirow:BAABNQAECn8wAAISAAoKRw7oSgCTAQASAAoKRw7oSgCTAQAAAA==.',
Ra='Radiação:BAAANQAECgMIAwAAAA==.Radunz:BAABNQAECn9JAAMUAAoKzx+VBADNAgAUAAoKzx+VBADNAgATAAMKlhURTgDTAAAAAA==.Ragnaros:BAAANQAECgQIBQAAAA==.Ragnarssön:BAAANQAECgYIBwAAAA==.Ragnarøk:BAAANQABCggICgAAAA==.Raio:BAABNQAECn9GAAIMAAoKzR5WNQBjAgAMAAoKzR5WNQBjAgAAAA==.Ramorey:BAAANQAECgYIDQAAAA==.Ranruulfnarm:BAAANQABCgQICAAAAA==.Rargsa:BAABNQAECn8UAAICAAUKgQNmgQCnAAACAAUKgQNmgQCnAAAAAA==.Rargul:BAAANQAECgQIAwAAAA==.Rariel:BAABNQAECn8hAAIKAAoKphKKPQDNAQAKAAoKphKKPQDNAQAAAA==.Raymain:BAABNQAECn8mAAQJAAkKUBrFGQDjAQAJAAgKFBnFGQDjAQAVAAkKLBdyKQDSAQAYAAEKUgN/KQAhAAAAAA==.Raíka:BAAANQADCggIDQAAAA==.',
Re='Rebimboca:BAAANQAECgEIAQAAAA==.Redoon:BAAANQAECgIIAQAAAA==.Rendoras:BAAANQAECgEIAQAAAA==.',
Rh='Rhaumarhu:BAAANQADCgcIEgAAAA==.',
Ro='Rockit:BAAANQADCgMICAAAAA==.Rodbree:BAABNQAECn89AAMiAAoKICXvCACEAwAiAAoKICXvCACEAwAFAAIKAADEbwFuAAAAAA==.Roguinhu:BAABNQAECn8UAAMaAAcKOgpcJQAAAQAaAAcKOgpcJQAAAQAnAAQK5wTiFwBnAAAAAA==.Roseangel:BAAANQABCgEIAQAAAA==.',
Ru='Rubian:BAAANQADCgYIDAAAAA==.Rudan:BAAANQAECgEIAQAAAA==.Rurumo:BAAANQAECgEIAQAAAA==.Rustovick:BAABNQAECn8YAAIDAAYKIQwPRgDgAAADAAYKIQwPRgDgAAAAAA==.',
['Rä']='Rämzä:BAAANQAECgEIAQABNQAECggIGgANAIwRAA==.',
['Rå']='Råy:BAABNQAECn8rAAMDAAoKLBwtJwCfAgADAAoKLBwtJwCfAgACAAEKkg48qwA3AAAAAA==.',
Sa='Saalla:BAAANQABCgYIDwABNQAECgoKSQAUAM8fAA==.Saffír:BAABNQAECn81AAIFAAoKIhXBYwD5AQAFAAoKIhXBYwD5AQAAAA==.Sahkev:BAAANQAECgUICAAAAA==.Samalandraa:BAABNQAECn8iAAMSAAkK0hP8NwDfAQASAAkKGRH8NwDfAQAgAAQKMg9vIAAIAQAAAA==.Sanateia:BAAANQAECgQIBgAAAA==.Saniest:BAABNQAECn8nAAMBAAoKxx7EEwDJAgABAAkKvR7EEwDJAgALAAcKZSFfNQBUAgAAAA==.Sapekinhä:BAABNQAECn8aAAIKAAkKVhWgLgAxAgAKAAkKVhWgLgAxAgAAAA==.Satanvitória:BAAANQAECgYIEAAAAA==.',
Se='Segavaxx:BAAANQABCgQIBAAAAA==.Selorixie:BAAANQAECgYIDAABNQAECgYIIQAbAFMdAA==.Sereiaa:BAABNQAECn8bAAIPAAkK7wnGngBaAQAPAAkK7wnGngBaAQAAAA==.',
Sh='Shadowmore:BAAANQAECgcICwABNQAECgkJNQAKAAAbAA==.Shamate:BAAANQAECgUIAgAAAA==.Shanoa:BAAANQAECgQICAAAAA==.Sharae:BAAANQADCggIDQAAAA==.Shaÿane:BAAANQAECgUIBQAAAA==.Shedo:BAABNQAECn8YAAMGAAkKohkEeQAsAgAGAAgKohkEeQAsAgAOAAIKUhqzJwBvAAAAAA==.Shonja:BAAANQAECgUICwAAAA==.Shula:BAAANQADCgYIBgAAAA==.',
Si='Sialeeds:BAAANQADCgMIAwAAAA==.Siclop:BAAANQAECgIIAgAAAA==.Simplicity:BAABNQAECn8aAAMLAAgKwBdCZADzAQALAAgKwBdCZADzAQABAAMKbxJoVwCtAAAAAA==.Sinton:BAAANQABCgIIAgAAAA==.',
Sk='Skadrian:BAAANQAECgQIBAAAAA==.Skadryan:BAAANQAECgUIDgAAAA==.Skalnark:BAABNQAECn8iAAIcAAoKCAydWgCxAQAcAAoKCAydWgCxAQAAAA==.Skinme:BAAANQAECgEIAQAAAA==.Skysoul:BAAANQAECgEJAgAAAA==.',
Sl='Sleeppanda:BAAANQAECgEIAgABNQAECgoKNQAEAJgkAA==.',
So='Sofiela:BAAANQAECgIIAgAAAA==.Soijiro:BAAANQADCgIIAgAAAA==.Soju:BAAANQADCgIIAgAAAA==.Sol:BAAANQADCgQIBAAAAA==.Sombrea:BAAANQADCgcIEQAAAA==.',
Sp='Spectrø:BAAANQADCgcIFAAAAA==.',
Ss='Sstrange:BAAANQADCggICQABNQAECgQIBgAIAAAAAA==.',
St='Starkz:BAAANQADCgUIBQAAAA==.Stormswill:BAAANQAECgEIAQAAAA==.Stëlla:BAABNQAECn89AAIeAAoKmBwQJACNAgAeAAoKmBwQJACNAgAAAA==.',
Su='Suckmyhammer:BAAANQAECgcIDgAAAA==.Sungjinwoo:BAAANQAECgYIEAAAAA==.Sunnara:BAABNQAECn8rAAIoAAoKXhzxFQC0AgAoAAoKXhzxFQC0AgAAAA==.',
Sy='Syuon:BAABNQAECn9MAAIJAAoKHSaqAADcAwAJAAoKHSaqAADcAwAAAA==.',
Sz='Szaa:BAAANQADCgUICAAAAA==.',
Ta='Talandar:BAABNQAECn9YAAIXAAoKphkAFgBUAgAXAAoKphkAFgBUAgAAAA==.Tankoso:BAAANQAECgQIBgAAAA==.Tankudo:BAABNQAECn81AAMDAAkKQBq/HADrAQADAAkKQBq/HADrAQARAAIK4xcqkABDAAAAAA==.Tataloka:BAAANQAECgMIAQAAAA==.',
Te='Tennebra:BAAANQADCggICQAAAA==.',
Th='Thabitah:BAABNQAECn9JAAIBAAoKERT3EgAVAgABAAoKERT3EgAVAgAAAA==.Thanathus:BAAANQAECgIIAQAAAA==.Thaumiel:BAAANQADCgEIAQAAAA==.Thedragon:BAABNQAECn9BAAMPAAoKdiI7EQACAwAPAAoKdiI7EQACAwAhAAEKAQvKXQA5AAAAAA==.Thorkel:BAAANQAECgIIAgAAAA==.Thotamon:BAAANQAECgUIDAAAAA==.Thýah:BAAANQAECgYICAAAAA==.',
Ti='Tidim:BAAANQADCgcIEAAAAA==.Tiih:BAAANQABCgUIBwAAAA==.',
To='Tonypaludo:BAAANQAECgEIAQAAAA==.',
Tr='Trueperceval:BAAANQABCgQIBgAAAA==.',
Tu='Tushui:BAAANQADCgMIAwAAAA==.',
Ur='Uriuri:BAAANQABCggIEgABNQAECgoKSQAUAM8fAA==.',
Us='Usfull:BAABNQAECn8oAAMLAAoKrhduWwAPAgALAAoKrhduWwAPAgABAAIKsQOhagBYAAAAAA==.',
Va='Vaatu:BAAANQADCgMIBAAAAA==.Vaeltor:BAAANQAECggIBQAAAA==.Valegás:BAAANQAECgYICgAAAA==.Vallentyne:BAAANQAECgUIBAAAAA==.Vallkÿria:BAAANQAECgcIDAAAAA==.Varrex:BAAANQAECgEIAQAAAA==.Vaëllen:BAABNQAECn8kAAMNAAgK3QghNwDVAAANAAgK3QghNwDVAAAXAAEKAAC7wAAhAAAAAA==.',
Ve='Vehuiáh:BAABNQAECn8bAAIiAAkK8xMHTQDMAQAiAAkK8xMHTQDMAQAAAA==.Vehuzito:BAAANQAECgUIBQABNQAECgkJGwAiAPMTAA==.Velen:BAABNQAECn9PAAMDAAoKCiGxBQAUAwADAAoKCiGxBQAUAwACAAEKswhXrQAzAAAAAA==.Verno:BAAANQAECgIIAgAAAA==.Verzuk:BAAANQAECgYIDAAAAA==.',
Vi='Vintejulgar:BAAANQABCggICQAAAA==.Vintekilo:BAABNQAECn8hAAIFAAoKVA2unADpAQAFAAoKVA2unADpAQAAAA==.Vinteservir:BAAANQABCgQIBAAAAA==.',
Vo='Voiddh:BAACNQAFFH8FAAIoAAUKrgUECgCyAAAoAAUKrgUECgCyAAA1AAQKfzYAAigACgpbFoUYAN0BACgACgpbFoUYAN0BAAAA.',
Vr='Vrenshrrgn:BAAANQAECgEIAgAAAA==.',
Vy='Vygh:BAABNQAECn9EAAMcAAoKsR8lIgD7AgAcAAoKsR8lIgD7AgAbAAEKuAs4eQA0AAAAAA==.Vyndrill:BAABNQAECn8qAAIZAAkKyBT4HQDjAQAZAAkKyBT4HQDjAQAAAA==.',
Wa='Walkers:BAABNQAECn8tAAIPAAoKrBOXVQBxAgAPAAoKrBOXVQBxAgAAAA==.Warlaka:BAAANQADCgYICwAAAA==.',
We='Weevil:BAAANQADCgYICgAAAA==.',
Wo='Worgenbelfin:BAAANQADCggIDQAAAA==.',
Wy='Wyrel:BAAANQADCgQIBgAAAA==.',
Xa='Xalmoria:BAAANQAECgcICgAAAA==.',
Xu='Xurumeloun:BAAANQADCgYIBgAAAA==.',
Ya='Yamii:BAAANQAECgQIBgAAAA==.Yasmini:BAAANQABCgEIAQAAAA==.',
Ye='Yenom:BAAANQADCgIIAgAAAA==.',
Yi='Yingsu:BAABNQAECn8cAAMVAAoKFR2CGACDAgAVAAoKshyCGACDAgAYAAYK6RAHHAAmAQAAAA==.Yippwarr:BAAANQADCgMIBAAAAA==.',
Yu='Yunná:BAAANQADCgYICgAAAA==.',
Yv='Yvin:BAAANQAECgIIAgAAAA==.',
Za='Zakir:BAAANQAECgUICQAAAA==.Zaolron:BAAANQADCgIIAQAAAA==.Zawarudo:BAAANQADCggICAAAAA==.',
Ze='Zeddshm:BAAANQAECgEIAQABNQAECgoKOAAGAAoXAA==.',
Zh='Zhynah:BAAANQADCgUIBQAAAA==.',
Zi='Zibrautar:BAAANQADCgIIAgAAAA==.Ziracruz:BAAANQAECgQICAAAAA==.',
Zu='Zulyn:BAAANQADCgcIFwAAAA==.',
['Àr']='Àrdath:BAAANQAECgQIBQAAAA==.Àrthemís:BAAANQADCgEIAQAAAA==.',
['Ár']='Áraujo:BAAANQADCgEJAQABNQADCgUIBQAIAAAAAA==.Árÿä:BAABNQAECn9HAAIPAAoKDREGVgAIAgAPAAoKDREGVgAIAgAAAA==.',
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
