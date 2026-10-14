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

local lookup = {'Priest-Shadow','Paladin-Protection','Warrior-Protection','Warrior-Arms','Monk-Mistweaver','DemonHunter-Havoc','Priest-Holy','Paladin-Retribution','Unknown-Unknown','Mage-Arcane','Druid-Guardian','Warrior-Fury','Hunter-BeastMastery','DeathKnight-Blood','Shaman-Elemental','Monk-Windwalker','Rogue-Assassination','Mage-Frost','DeathKnight-Frost','Druid-Balance','Druid-Restoration','Rogue-Subtlety','Warlock-Destruction','Warlock-Demonology','Druid-Feral','DemonHunter-Vengeance','Shaman-Restoration','Warlock-Affliction','Monk-Brewmaster','Shaman-Enhancement','Paladin-Holy','DeathKnight-Unholy','Mage-Fire','DemonHunter-Devourer',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abaca:BAAANQAECgIIAgAAAA==.Abacatte:BAAANQAECgQICAAAAA==.',
Ad='Adelaide:BAAANQADCgUIBwABNQAFFAcIFwABABESAA==.',
Ae='Aelthor:BAAANQADCggIRQAAAA==.',
Ai='Aioliavictus:BAAANQADCgUIBQAAAA==.',
Al='Aleriastorm:BAAANQABCgIIAgAAAA==.Alessaxd:BAAANQAECgcIDAAAAA==.Alfajhor:BAABNQAECn8oAAICAAkKcCOOAgCjAwACAAkKcCOOAgCjAwAAAA==.Alfajhòr:BAAANQAECgEIAQAAAA==.Alfajhõr:BAAANQAECgYICgAAAA==.Alkaid:BAABNQAECn8cAAMDAAgKGROQIgAxAQAEAAcK+BKxpQC6AQADAAYK6w6QIgAxAQAAAA==.Alladryel:BAAANQADCgYIBgAAAA==.Alleriane:BAABNQAECn8eAAIFAAkKVhpMDwCHAgAFAAkKVhpMDwCHAgAAAA==.Allone:BAABNQAECn8iAAIGAAkKygmsRACaAQAGAAkKygmsRACaAQAAAA==.Allunt:BAAANQAECgUIBQAAAA==.Almin:BAAANQAECgIIBQAAAA==.',
Am='Ametnys:BAAANQAECgUICgAAAA==.Amonhar:BAAANQAECgQIBAABNQAECgcIIAAHAIEaAA==.',
An='Anakata:BAAANQAECgQIBgAAAA==.Andaliz:BAABNQAECn8yAAIIAAkKByRcBwC/AwAIAAkKByRcBwC/AwAAAA==.Andaril:BAAANQADCgcIBwAAAA==.Antonel:BAAANQABCgYIBgAAAA==.Antonellaes:BAAANQADCgcIDAABNQAECgQICwAJAAAAAA==.',
Ap='Aprocom:BAAANQADCgQIBAAAAA==.',
Ar='Arcanör:BAABNQAECn8XAAIKAAcKDw3D8gCiAQAKAAcKDw3D8gCiAQAAAA==.Arctorius:BAAANQAECgYIEQAAAA==.Aronys:BAAANQAECgYICgAAAA==.Arquitetö:BAAANQADCgIIAgAAAA==.Arthashand:BAAANQADCgEIAQAAAA==.Artronis:BAABNQAECn8iAAILAAkKLxOgEwAjAgALAAkKLxOgEwAjAgAAAA==.Arukäi:BAABNQAECn8hAAMEAAgKxwr+qQCvAQAEAAgKxwr+qQCvAQAMAAMKgQfHKABlAAAAAA==.Arägørn:BAAANQAECgMIBQAAAA==.',
As='Assintomatic:BAAANQABCgYICQABNQAECggIDQAJAAAAAA==.',
At='Atriuz:BAAANQAECgQIDAAAAA==.Ats:BAAANQADCggICwAAAA==.',
Az='Azerotiano:BAAANQAECgQIBgAAAA==.',
['Aÿ']='Aÿ:BAAANQAECgEIAQAAAA==.',
Ba='Baldraccus:BAAANQADCgcIBwAAAA==.Balk:BAABNQAECn8pAAINAAkKbB6/HwAXAwANAAkKbB6/HwAXAwAAAA==.Bambur:BAAANQADCggICgAAAA==.Barauna:BAAANQABCgIIAgAAAA==.Barbabruto:BAABNQAECn8gAAIDAAkKERgiCwCIAgADAAkKERgiCwCIAgAAAA==.Barbacancer:BAAANQAECgQIBAAAAA==.Barbasanta:BAAANQAECgMIAgABNQAECgkJIAADABEYAA==.Batgirl:BAAANQAECgQIBAAAAA==.',
Be='Belthorsin:BAAANQADCgYIBgAAAA==.Belthorvil:BAAANQADCgEIAQAAAA==.',
Bi='Bigbag:BAAANQADCgQIBQAAAA==.Biønic:BAAANQAECgUICQAAAA==.',
Bl='Blackmoonx:BAAANQAECgcIEgAAAA==.Blackninja:BAAANQABCggIGwAAAA==.Blu:BAEANQAECgEIAQABNQAECgYIEQAJAAAAAA==.',
Bo='Box:BAAANQADCgMIAwAAAA==.',
Br='Brahman:BAAANQAECgEIAQAAAA==.Bright:BAAANQADCgYIBgAAAA==.Bruex:BAAANQADCgIIAgAAAA==.Bruker:BAAANQADCgIIAgAAAA==.',
Bu='Buzzumaaky:BAAANQAECgYIEgAAAA==.',
['Bá']='Bávor:BAAANQADCgEIAQAAAA==.',
['Bí']='Bílly:BAAANQAECgEIAQAAAA==.',
Ca='Calteryeker:BAAANQAECgMICAAAAA==.Capitu:BAAANQADCggICwABNQAECggIGgAOAKcbAA==.Capyvara:BAAANQABCgYIBwAAAA==.Caralh:BAABNQAECn8nAAIOAAkKviBhEQAgAwAOAAkKviBhEQAgAwAAAA==.Caroll:BAAANQADCgMIAwAAAA==.Caçaorda:BAAANQAECgMJBAAAAA==.',
Ce='Cecilith:BAACNQAFFH8FAAIPAAIKCgoLJgCRAAAPAAIKCgoLJgCRAAA1AAQKfyoAAg8ACQrPIM0VAEQDAA8ACQrPIM0VAEQDAAAA.Cernûnnos:BAAANQAECgQIDQAAAA==.',
Ch='Champdude:BAABNQAECn8lAAMQAAgK/h5PFwCNAgAQAAcKaSFPFwCNAgAFAAEKuwzzSgA1AAAAAA==.Chopquatro:BAAANQADCggICAAAAA==.Chrnnos:BAAANQAECgUIBwAAAA==.',
Co='Corineus:BAAANQADCgYICQAAAA==.Cowzeroth:BAABNQAECn8gAAIPAAcKXyDRPQB7AgAPAAcKXyDRPQB7AgABNQAECggIHgARAPEQAA==.',
Cr='Crassustitan:BAAANQAECgcIEgAAAA==.Cristcalad:BAAANQAECgUIDwAAAA==.',
Da='Daemi:BAAANQAECggIDgAAAA==.Dalaty:BAAANQAECgUICgAAAA==.Daresh:BAAANQADCgEJAQAAAA==.Dariok:BAAANQAECgYIEwAAAA==.Darkove:BAABNQAECn8mAAISAAgKFxMCDQDgAQASAAgKFxMCDQDgAQAAAA==.Darrow:BAABNQAECn8jAAITAAkK1w5pMwALAgATAAkK1w5pMwALAgAAAA==.Daryan:BAAANQAECgcIDwAAAA==.Day:BAAANQAECgQIBAAAAA==.',
De='Deathinhu:BAABNQAECn8sAAIKAAgKnyBOTADpAgAKAAgKnyBOTADpAgAAAA==.Demoriana:BAAANQAECgQICwAAAA==.Dethroned:BAAANQAECgQICgAAAA==.',
Di='Dimeros:BAABNQAECn8oAAIUAAgKzAoXTwCfAQAUAAgKzAoXTwCfAQAAAA==.Divano:BAABNQAECn8pAAIBAAkK8x2PCwArAwABAAkK8x2PCwArAwAAAA==.',
Dk='Dkats:BAAANQADCgQIBAAAAA==.Dkhalifa:BAAANQADCgYIBgAAAA==.',
Do='Dogowner:BAAANQAECgYIBgAAAA==.Donora:BAAANQAECgQIBAAAAA==.Dorfillaw:BAAANQAECgUICQAAAA==.Dorvana:BAAANQADCgMJAwABNQAECgkJMgAIAAckAA==.',
Dr='Dracthyrius:BAAANQAECgEIAQAAAA==.Draenthar:BAAANQADCgQIBQAAAA==.Dragonstyle:BAAANQAECgcICwAAAA==.Dragony:BAAANQADCgQIBAAAAA==.Dreez:BAAANQAECgQIBgAAAA==.Drexus:BAAANQADCgMIAwAAAA==.Drigolas:BAAANQADCgYIBgAAAA==.Druidblack:BAAANQADCgUIBQAAAA==.',
Eh='Ehomi:BAAANQADCgIIAgAAAA==.',
Ei='Eirin:BAAANQAECgQIEQAAAA==.',
El='Eldris:BAAANQADCgEIAQAAAA==.Elidibus:BAAANQADCgQIBAAAAA==.Ellvarg:BAAANQADCgYIDAAAAA==.Eluuria:BAAANQAECggIDQAAAA==.',
En='Enkrenco:BAAANQADCgQIBAAAAA==.Ennafaryn:BAAANQABCgQIBAAAAA==.Ensabanú:BAAANQADCgQIBAAAAA==.',
Er='Erilaethaen:BAAANQAECgIIAgAAAA==.Erlek:BAAANQADCgUICwAAAA==.Ernest:BAABNQAECn8lAAIVAAgK/R5AEQDGAgAVAAgK/R5AEQDGAgAAAA==.Erulan:BAAANQADCgQIBwAAAA==.',
Es='Estgan:BAAANQADCgMIAwAAAA==.',
Et='Ether:BAABNQAECn8YAAIOAAgKvBG2TADAAQAOAAgKvBG2TADAAQAAAA==.Etubrutus:BAAANQADCgUIBAAAAA==.',
Ev='Evangelouco:BAAANQADCgQIBAAAAA==.Evilbarba:BAABNQAECn8dAAIIAAgKWhmddgA7AgAIAAgKWhmddgA7AgAAAA==.',
Ex='Exort:BAAANQAECgQICAAAAA==.Exothus:BAAANQAECgQJBwAAAA==.',
Fa='Faldark:BAAANQADCgUIBQAAAA==.Fandrall:BAAANQADCggIFAAAAA==.Faranir:BAAANQADCggIEAAAAA==.Faris:BAABNQAECn8eAAMRAAgK8RDiOwDcAQARAAcKOBLiOwDcAQAWAAcKygxrJQCYAQAAAA==.Faver:BAAANQADCgMIAwAAAA==.Faölin:BAABNQAECn8fAAIWAAgKnxZTEQBpAgAWAAgKnxZTEQBpAgAAAA==.',
Fe='Ferael:BAABNQAECn8sAAMIAAkKKBvZNwDtAgAIAAkKKBvZNwDtAgACAAQKPQkKTwCmAAAAAA==.Ferrus:BAAANQAECgQIAwAAAA==.',
Fj='Fjord:BAAANQAECgIIAgAAAA==.',
Fl='Flavors:BAABNQAECn8hAAIEAAgKDiIHKgARAwAEAAgKDiIHKgARAwAAAA==.Florbela:BAABNQAECn8WAAIVAAgKkAs4MwB8AQAVAAgKkAs4MwB8AQAAAA==.',
Fr='Fredericc:BAAANQAECgUIBQAAAA==.Freecs:BAAANQAECgUIBQAAAA==.Freyá:BAABNQAECn8kAAMCAAkK+RsvEACYAgACAAgKHR0vEACYAgAIAAYK2hDh2ABjAQAAAA==.Frostburn:BAAANQAECggIDwAAAA==.Froststriker:BAAANQAECgEIAQAAAA==.',
Fu='Fulvo:BAAANQADCgQIBQAAAA==.',
Ga='Gadodamorena:BAAANQAECgEIAQAAAA==.Galfur:BAABNQAECn8bAAIUAAUKOQc6fgDQAAAUAAUKOQc6fgDQAAAAAA==.Galhuda:BAAANQAECgMIAwAAAA==.Galica:BAAANQADCgIIAgAAAA==.Gandwelf:BAAANQADCggICAAAAA==.',
Ge='Geisty:BAAANQAECgEIAQABNQAECgIIBAAJAAAAAA==.',
Gl='Glutotwo:BAAANQADCgYIEgAAAA==.',
Go='Goldchain:BAAANQAECgMIBgAAAA==.Govers:BAAANQAECgEIAQABNQAECgcIDwAJAAAAAA==.',
Gr='Grommar:BAAANQADCgUIBQABNQAECgMICAAJAAAAAA==.Grumax:BAABNQAECn8YAAIIAAcKkAuU1ABsAQAIAAcKkAuU1ABsAQAAAA==.',
Gu='Gudeath:BAABNQAECn8pAAIEAAgKDBfjhgAHAgAEAAgKDBfjhgAHAgAAAA==.Guerrerinhow:BAAANQADCggIHgABNQAECgcIHAAUAB0RAA==.Guitianki:BAAANQADCgYIBgAAAA==.Gulek:BAAANQAECgYICQAAAA==.Gussg:BAABNQAECn8aAAMXAAgKABTFGAClAQAXAAcKABTFGAClAQAYAAUKugg73wAFAQAAAA==.',
['Gà']='Gàladriel:BAAANQAECgUIBwAAAA==.',
['Gö']='Göhan:BAAANQAECgIIAwAAAA==.',
['Gø']='Gøvers:BAAANQAECgcIDwAAAA==.',
['Gü']='Güttz:BAABNQAECn8gAAIGAAgK5RDHOgDaAQAGAAgK5RDHOgDaAQAAAA==.',
Ha='Hagires:BAAANQAECgYIBwAAAA==.Hanaluna:BAAANQADCggICAAAAA==.Harchus:BAAANQADCgYIEgAAAA==.Hargarthul:BAAANQADCgMIBAAAAA==.Hazell:BAAANQADCggIDQAAAA==.',
He='Hellspont:BAABNQAECn8UAAMZAAcKIyHuCwBoAgAZAAYKTCLuCwBoAgALAAIKzxuXRQCVAAAAAA==.Hendrikison:BAAANQAECgIIAgAAAA==.',
Ho='Horagalles:BAAANQADCgIIAgAAAA==.Hotmojo:BAACNQAFFH8GAAIKAAIKaxYyQgCkAAAKAAIKaxYyQgCkAAA1AAQKfzcAAgoACQrxIWsvAC4DAAoACQrxIWsvAC4DAAAA.',
Hu='Hunfox:BAABNQAECn80AAINAAkKziKSCQCQAwANAAkKziKSCQCQAwAAAA==.Hunterhearst:BAAANQADCgYIBwAAAA==.Huor:BAAANQADCggICAAAAA==.',
Hy='Hylana:BAAANQADCgEIAQAAAA==.',
['Hö']='Hölycrüsh:BAABNQAECn8tAAIIAAgKVyFqQADRAgAIAAgKVyFqQADRAgAAAA==.',
Ik='Ikoo:BAAANQAECgYJDAAAAA==.',
Il='Illaril:BAACNQAFFH8TAAIaAAUKDQ1dAgAZAQAaAAUKDQ1dAgAZAQA1AAQKfyoAAhoACQq1GR4JAFkCABoACQq1GR4JAFkCAAAA.',
In='Interestelar:BAAANQADCgYIBgAAAA==.Invisiblelol:BAAANQAECgUICgAAAA==.',
Ir='Irmãodouther:BAAANQAECgUJBQAAAA==.Irridan:BAAANQADCgQIBQAAAA==.',
Is='Isenhearth:BAAANQABCgUIBQAAAA==.Ishtarie:BAABNQAECn8ZAAIbAAgKax5wLgCmAgAbAAgKax5wLgCmAgAAAA==.',
It='Itokeszdan:BAAANQADCgYIBAAAAA==.',
Iv='Ivina:BAABNQAECn8yAAMYAAkK/xrTRwB4AgAYAAkK/xrTRwB4AgAcAAEKjwY3MwAsAAAAAA==.',
Iz='Izaar:BAAANQADCggIFwAAAA==.',
Ja='Jangeoffry:BAAANQABCgMIAwAAAA==.',
Jh='Jhonatinha:BAAANQAECgUIBwAAAA==.',
Ju='Jullianxd:BAAANQAECgQIBwAAAA==.Junjih:BAAANQAECgUIBQABNQAECgcIEgAJAAAAAA==.',
Ka='Kaallew:BAAANQAECggIDQAAAA==.Kaallmonge:BAAANQABCgcIBwAAAA==.Kaelonidas:BAAANQAECgQIDAAAAA==.Kaelyaa:BAAANQADCgUIBQAAAA==.Kainer:BAAANQADCgYICQAAAA==.Kalazshar:BAABNQAECn8dAAILAAgKqQrgKABKAQALAAgKqQrgKABKAQAAAA==.Kalduran:BAAANQADCggIPQAAAA==.Kalelzinho:BAAANQADCgYIBAAAAA==.Kaluss:BAABNQAECn8cAAIKAAgK1wj/5gC4AQAKAAgK1wj/5gC4AQAAAA==.Kanduz:BAAANQAECgEIAgAAAA==.Kantaa:BAAANQADCggIKwAAAA==.Karmabb:BAAANQAECgUICgAAAA==.Kauss:BAAANQAECgIJAgAAAA==.Kavartu:BAABNQAECn8kAAIPAAkKZReFRABgAgAPAAkKZReFRABgAgAAAA==.Kayli:BAAANQADCgcIDgAAAA==.Kaysa:BAAANQADCggIDQAAAA==.',
Ke='Keillor:BAABNQAECn8hAAMbAAYKOQoTrQASAQAbAAYKOQoTrQASAQAPAAUKQwt3vgARAQAAAA==.Keldorian:BAAANQADCgQIBAAAAA==.Kenzou:BAABNQAECn8VAAIdAAYKwB41DgAQAgAdAAYKwB41DgAQAgAAAA==.Keytymari:BAAANQAECgUICgAAAA==.',
Kh='Khaliq:BAABNQAECn8aAAIGAAgKzhShMAAfAgAGAAgKzhShMAAfAgAAAA==.Khallani:BAAANQADCgIIAgABNQAECgIIBAAJAAAAAA==.',
Ki='Kieran:BAAANQADCgYIBgAAAA==.Kimashi:BAAANQAECgEIAgAAAA==.Kissme:BAABNQAECn8kAAMVAAgKZxD6MgB+AQAVAAcKbg/6MgB+AQAUAAYK5AltYgBAAQAAAA==.Kitamor:BAABNQAECn8qAAMUAAgKnAZnYwA8AQAUAAgKsQRnYwA8AQALAAMKLAtISgB5AAAAAA==.',
Kl='Kletian:BAAANQADCggICAAAAA==.',
Ko='Koriakin:BAAANQADCggIGQAAAA==.Korogth:BAAANQAECgUIBgAAAA==.Kosmo:BAABNQAECn8aAAIcAAcKihVdCQDsAQAcAAcKihVdCQDsAQAAAA==.',
Kr='Krisyum:BAAANQAECgEIAQAAAA==.Krosmu:BAAANQABCgMIAwAAAA==.Kräsus:BAAANQADCgQIBAABNQAECggIJgAdANMgAA==.',
Ku='Kurado:BAAANQAECgIIAgAAAA==.',
Ky='Kyrïn:BAAANQADCgUIBQABNQAFFAUICgARAAUaAA==.',
Kz='Kzinn:BAAANQAECgEIAQAAAA==.',
['Kö']='Körn:BAAANQAECgQIBwABNQAECggIGgAbADETAA==.',
La='Ladyrichter:BAAANQABCgcIDQAAAA==.Laetus:BAABNQAECn8ZAAIKAAkKiRvbTADoAgAKAAkKiRvbTADoAgAAAA==.Lagerthaloth:BAAANQADCgUIBAAAAA==.Laiander:BAAANQAECgUIDwAAAA==.Laiany:BAABNQAECn8pAAIHAAgK2yG1HQD4AgAHAAgK2yG1HQD4AgAAAA==.Lainarning:BAAANQAECgEIAQAAAA==.Lani:BAAANQAECgIIAQAAAA==.Laolong:BAAANQADCgYIBgAAAA==.',
Le='Leeoncamillo:BAAANQADCgUIBQABNQAECgQICwAJAAAAAA==.Leetohro:BAAANQAECgUIDgAAAA==.Leodoros:BAABNQAECn8hAAIKAAYKOAwPKAFFAQAKAAYKOAwPKAFFAQAAAA==.',
Li='Lichkíng:BAAANQAECgQICQAAAA==.Lighty:BAAANQADCgQICAAAAA==.Lijiang:BAABNQAECn8mAAIdAAgK0yBDBgDpAgAdAAgK0yBDBgDpAgAAAA==.Lilianpotter:BAAANQADCgYIBgAAAA==.Lilibel:BAAANQAECgEIAwAAAA==.Lillit:BAAANQAECgQIBAAAAA==.Lindaah:BAAANQADCggINAAAAA==.Lindapriesty:BAAANQADCgIIAgAAAA==.Lislfox:BAABNQAECn8gAAILAAcK8B1TEABWAgALAAcK8B1TEABWAgAAAA==.',
Ll='Lledritch:BAAANQADCgUIBQAAAA==.',
Lm='Lmmds:BAAANQADCgcIDQAAAA==.',
Lo='Lockdown:BAABNQAECn8tAAIYAAgKXxLNdQD8AQAYAAgKXxLNdQD8AQAAAA==.Loukou:BAAANQADCggIHQAAAA==.',
Lu='Luacs:BAABNQAECn8aAAQbAAgKMROUZgDVAQAbAAgKMROUZgDVAQAeAAUK8BwNGwCvAQAPAAIKfgmXCwFtAAAAAA==.Luccoa:BAAANQADCgMIAwABNQAECggIJgAdANMgAA==.Lucileia:BAAANQADCgcIBwAAAA==.Lucyfary:BAAANQADCgcICAAAAA==.Luhhrogue:BAAANQAECgMIAwAAAA==.Lunirah:BAAANQADCgYICAAAAA==.',
Ly='Lylka:BAABNQAECn8lAAMCAAgKRyBqDwCkAgACAAgKRyBqDwCkAgAfAAUKISTyVwAOAgAAAA==.',
['Lé']='Léofar:BAAANQAECgcIEgAAAA==.',
['Lü']='Lücyfer:BAAANQAECgMIAwAAAA==.',
Ma='Maanu:BAAANQADCgUIBQABNQADCggINAAJAAAAAA==.Maeghann:BAAANQADCgQIAwAAAA==.Magostosaa:BAAANQABCgIIAgAAAA==.Makani:BAAANQAECgEIAgAAAA==.Malewolyyc:BAABNQAECn8pAAMHAAkKAR0bHQD7AgAHAAkKAR0bHQD7AgABAAQK2w3BTgDTAAAAAA==.Massafera:BAABNQAECn8bAAIIAAgKnBFbmgDpAQAIAAgKnBFbmgDpAQAAAA==.Mathfacbruxo:BAAANQADCgYJBgABNQAECggIIQANAH8gAA==.Mathfacii:BAABNQAECn8hAAINAAgKfyD+LQDhAgANAAgKfyD+LQDhAgAAAA==.Mayanyy:BAAANQAECgEIAQAAAA==.',
Mc='Mcq:BAAANQAECgEIAQAAAA==.',
Md='Mdrdark:BAABNQAECn8jAAIgAAkKuRzaLAB+AgAgAAkKuRzaLAB+AgAAAA==.',
Me='Medz:BAABNQAECn8bAAIKAAgKvBfplABWAgAKAAgKvBfplABWAgAAAA==.Meetjack:BAAANQAECgEIAQAAAA==.Meizu:BAAANQAECgQJDAAAAA==.Mellkor:BAABNQAECn8dAAIGAAcKjRlrMQAZAgAGAAcKjRlrMQAZAgAAAA==.Meneláu:BAAANQADCggICAAAAA==.Metamorful:BAAANQAECggIDgAAAA==.',
Mi='Mihsi:BAAANQADCgEIAQAAAA==.Milim:BAAANQAECgcIEgAAAA==.Minilock:BAAANQAECgQIBQAAAA==.Mistogunn:BAAANQADCggICAAAAA==.Mitchell:BAAANQABCgUIBgAAAA==.',
Ml='Mls:BAAANQADCgYICwAAAA==.',
Mm='Mmarcão:BAAANQAECgQIBAAAAA==.',
Mo='Modes:BAABNQAECn8aAAIOAAgKpxsCJwCEAgAOAAgKpxsCJwCEAgAAAA==.Moffir:BAAANQADCgYIBgAAAA==.Mogrus:BAAANQADCgUIAgAAAA==.Mohanninha:BAAANQAECgQIBAAAAA==.Mohotok:BAABNQAECn8dAAIIAAgKdwlZxQCLAQAIAAgKdwlZxQCLAQAAAA==.Monshiro:BAAANQAECgEIAQABNQAECgUIBQAJAAAAAA==.Morkath:BAAANQADCggICAAAAA==.Mortixxia:BAABNQAECn8bAAIXAAYKUx2eDgAPAgAXAAYKUx2eDgAPAgAAAA==.',
Mu='Murano:BAABNQAECn8nAAIMAAkK1xZ/CABaAgAMAAkK1xZ/CABaAgAAAA==.',
['Má']='Máia:BAAANQAECgQIBwAAAA==.',
['Mä']='Mändosz:BAABNQAECn8YAAITAAgKHRlBJwBYAgATAAgKHRlBJwBYAgAAAA==.',
['Mé']='Ménace:BAAANQAECgMIAgABNQAECggIDwAJAAAAAA==.',
['Mÿ']='Mÿstyna:BAAANQADCgUJCQAAAA==.',
Na='Nagts:BAAANQADCggICgAAAA==.Nalathiel:BAAANQAECgUIBQAAAA==.Narancia:BAAANQAECgQIBwABNQAECgUIBQAJAAAAAA==.Narrih:BAAANQAECgIIBAAAAA==.Nazawill:BAAANQADCgQIBAAAAA==.Nazzh:BAAANQAECggIDAAAAA==.',
Ne='Nefas:BAAANQAECgcICwAAAA==.Nepthunus:BAABNQAECn8dAAIhAAgKhRipAQCDAgAhAAgKhRipAQCDAgAAAA==.',
Ni='Ninde:BAAANQADCggICAAAAA==.',
No='Notforall:BAAANQADCgIIAgAAAA==.',
['Nï']='Nïix:BAAANQADCgYIBgAAAA==.',
['Nö']='Nöirr:BAAANQABCgUIBAAAAA==.',
Od='Odestruidor:BAAANQAECgUICAAAAA==.',
Oi='Oioimiguel:BAAANQADCgcIBwAAAA==.',
Ol='Oluss:BAABNQAECn8eAAMfAAkK4w5BWQALAgAfAAkK4w5BWQALAgAIAAEKtwcgowEyAAABNQAECgkJNAANAM4iAA==.',
On='Onys:BAAANQADCgIIAgAAAA==.',
Oo='Oob:BAAANQAECgQIBAAAAA==.',
Op='Opus:BAABNQAECn8aAAMfAAgKcBKBYwDrAQAfAAgKcBKBYwDrAQACAAUKSAWsTACyAAAAAA==.Opusbergen:BAAANQADCgQIBAAAAA==.',
Or='Origon:BAAANQADCggICwAAAA==.Orillan:BAABNQAECn8gAAIGAAcKsxQmOgDeAQAGAAcKsxQmOgDeAQAAAA==.Ornsteinsnow:BAAANQADCgUIBQAAAA==.Orsonn:BAAANQAECgUIDAAAAA==.Orucão:BAAANQABCgEIAQAAAA==.Oruism:BAAANQABCgQIBAAAAA==.Orukam:BAAANQAECgcIEQAAAA==.Orukanorum:BAAANQADCgcIAwAAAA==.Orukrente:BAAANQABCgIIAgAAAA==.Orulord:BAAANQABCgIIAwAAAA==.Orurage:BAAANQABCgYIBAAAAA==.',
Pa='Palaha:BAAANQAECgQIBAABNQAECgkJNAANAM4iAA==.Palatina:BAABNQAECn8fAAIIAAgK5x5hOADsAgAIAAgK5x5hOADsAgABNQAECgkJMgAIAAckAA==.Pandalokodj:BAAANQAECgEIAQAAAA==.Pangedrey:BAABNQAECn8mAAMQAAgKbhnKHABOAgAQAAgKbhnKHABOAgAFAAEKRxWBSQA9AAAAAA==.Parký:BAAANQAECgcIEgAAAA==.Paullk:BAAANQADCgIIAgAAAA==.',
Pe='Penseur:BAAANQABCgYJBgAAAA==.Peruchi:BAAANQADCgIIAgAAAA==.Perísdra:BAAANQADCgcIDQABNQAECgMICAAJAAAAAA==.',
Pg='Pgms:BAAANQADCggIDQAAAA==.',
Pi='Picu:BAAANQADCgUICQAAAA==.Pitombinha:BAABNQAECn8ZAAMMAAgKgRqOCgAdAgAMAAYKSB2OCgAdAgAEAAQK+xMT8AD6AAAAAA==.Pixiks:BAAANQABCgYIBwAAAA==.',
Pp='Ppandora:BAAANQADCgUICgAAAA==.',
Pr='Predadore:BAAANQADCgUIBQAAAA==.',
Py='Pyrix:BAAANQADCgIIAgAAAA==.',
['Pä']='Pändero:BAAANQABCgMIAwAAAA==.',
['Pî']='Pîo:BAABNQAECn8sAAIKAAkKDyFNKwA5AwAKAAkKDyFNKwA5AwAAAA==.',
Qu='Quirow:BAABNQAECn8iAAIPAAgKuQ/eawDYAQAPAAgKuQ/eawDYAQAAAA==.',
Ra='Radiação:BAAANQAECgMIAwAAAA==.Radunz:BAABNQAECn8nAAMZAAgKTR0CCQC5AgAZAAgKTR0CCQC5AgAVAAMKlhUyTQDTAAAAAA==.Ragnaros:BAAANQAECgQIBQAAAA==.Ragnarssön:BAAANQADCgEIAQAAAA==.Ragnarøk:BAAANQABCggICAAAAA==.Raio:BAABNQAECn8pAAIKAAkKAhtSSQDvAgAKAAkKAhtSSQDvAgAAAA==.Ramorey:BAAANQAECgIIAgAAAA==.Ramsez:BAAANQABCgQIBAAAAA==.Ranruulfnarm:BAAANQABCgQICAAAAA==.Rargsa:BAAANQAECgQICQAAAA==.Rargul:BAAANQAECgIIAgAAAA==.Rariel:BAAANQAECgYIDgAAAA==.Raymain:BAABNQAECn8eAAMFAAgKAxlzGQDkAQAFAAcKaRdzGQDkAQAQAAcKHxgDKQDSAQAAAA==.Raíka:BAAANQADCggIDQAAAA==.',
Re='Rebimboca:BAAANQAECgEIAQAAAA==.Redoon:BAAANQADCgQIBQAAAA==.Rendoras:BAAANQAECgEIAQAAAA==.Rezadeiro:BAAANQADCgUIBAAAAA==.',
Rh='Rhaumarhu:BAAANQADCgYIDAAAAA==.',
Ro='Rockit:BAAANQADCgMICAAAAA==.Rodbree:BAABNQAECn8kAAMfAAkK8B8oDQBfAwAfAAkK8B8oDQBfAwAIAAIKAABeagFuAAAAAA==.Roguinhu:BAAANQAECgIIBgAAAA==.',
Ru='Rubian:BAAANQADCgYIDAAAAA==.Rudan:BAAANQAECgEIAQAAAA==.Rurumo:BAAANQAECgEJAQAAAA==.Rustovick:BAAANQAECgEIAQAAAA==.',
['Rä']='Rämzä:BAAANQADCggICgABNQAECgIIAwAJAAAAAA==.',
['Rå']='Råy:BAABNQAECn8mAAMgAAkKTx3SJgCeAgAgAAkKTx3SJgCeAgATAAEKkg7NpwA3AAAAAA==.',
Sa='Saffír:BAABNQAECn8aAAIIAAgKBBMRjAAJAgAIAAgKBBMRjAAJAgAAAA==.Samalandraa:BAAANQAECgUICAAAAA==.Sanateia:BAAANQAECgEIAgAAAA==.Saniest:BAABNQAECn8bAAMBAAgKph9/EwDJAgABAAgKph9/EwDJAgAHAAMK3xzgvADdAAAAAA==.Sapekinhä:BAABNQAECn8VAAIGAAgKZRf7LQAxAgAGAAgKZRf7LQAxAgAAAA==.Satanvitória:BAAANQAECgYIEAAAAA==.',
Se='Segavaxx:BAAANQABCgQIBAAAAA==.Seilaa:BAAANQABCgIIAgAAAA==.Selorixie:BAAANQAECgMIBQABNQAECgYIGwAXAFMdAA==.Sereiaa:BAAANQAECgUIDAAAAA==.',
Sh='Shamate:BAAANQADCgQJBAAAAA==.Shanoa:BAAANQAECgQIBQAAAA==.Sharae:BAAANQADCggIDQAAAA==.Shedo:BAABNQAECn8XAAMEAAgK6hondwAtAgAEAAcK6hondwAtAgAMAAIKUhouJwBvAAAAAA==.Shonja:BAAANQADCgYICQAAAA==.',
Si='Sialeeds:BAAANQADCgMIAwAAAA==.Siclop:BAAANQAECgIIAgAAAA==.Simplicity:BAABNQAECn8YAAMHAAcKCBrpYgD0AQAHAAcKCBrpYgD0AQABAAMKbxJnVgCtAAAAAA==.Sinton:BAAANQABCgIIAgAAAA==.',
Sk='Skadrian:BAAANQADCgQIBgAAAA==.Skadryan:BAAANQAECgQIBAAAAA==.Skalnark:BAAANQAECgUIBQAAAA==.Skinme:BAAANQAECgEIAQAAAA==.Skysoul:BAAANQAECgEJAgAAAA==.',
Sl='Sleeppanda:BAAANQAECgEIAgABNQAECgkJPQAdAM8cAA==.',
So='Sofiela:BAAANQAECgIIAgAAAA==.Soijiro:BAAANQADCgIIAgAAAA==.Soju:BAAANQADCgIIAgAAAA==.Sol:BAAANQADCgQIBAAAAA==.Sombrea:BAAANQADCgYICwAAAA==.',
Sp='Spectrø:BAAANQADCgcIFAAAAA==.',
Ss='Sstrange:BAAANQADCgcICAAAAA==.',
St='Starkz:BAAANQADCgUIBQAAAA==.Stëlla:BAABNQAECn8dAAIbAAcK9hguYgDkAQAbAAcK9hguYgDkAQAAAA==.',
Su='Suckmyhammer:BAAANQAECgYICQAAAA==.Sungjinwoo:BAAANQAECgYIEAAAAA==.Sunnara:BAABNQAECn8bAAIiAAkKoBu7FQCzAgAiAAkKoBu7FQCzAgAAAA==.',
Sy='Syuon:BAABNQAECn8wAAIFAAkKniWkAADcAwAFAAkKniWkAADcAwAAAA==.',
Sz='Szaa:BAAANQADCgEIAQAAAA==.',
Ta='Talandar:BAABNQAECn8vAAIUAAkKERaZJwCVAgAUAAkKERaZJwCVAgAAAA==.Tankudo:BAABNQAECn8dAAIgAAgKVReHPQAnAgAgAAgKVReHPQAnAgAAAA==.',
Te='Tennebra:BAAANQADCggICQAAAA==.',
Th='Thabitah:BAABNQAECn8oAAIBAAgKZBPzJAAFAgABAAgKZBPzJAAFAgAAAA==.Thanathus:BAAANQADCggIMQAAAA==.Thaumiel:BAAANQADCgEIAQAAAA==.Thedragon:BAABNQAECn8WAAINAAgKGxwFOwC3AgANAAgKGxwFOwC3AgAAAA==.Thorkel:BAAANQADCgcICgAAAA==.Thotamon:BAAANQADCgYICgAAAA==.Thýah:BAAANQADCggICAAAAA==.',
Ti='Tidim:BAAANQADCgYIBgAAAA==.Tiih:BAAANQABCgUIBQAAAA==.',
To='Tonypaludo:BAAANQAECgEIAQAAAA==.',
Tr='Trueperceval:BAAANQABCgQIBgAAAA==.',
Tu='Tushui:BAAANQADCgMIAwAAAA==.',
Us='Usfull:BAABNQAECn8gAAMHAAcKgRohWgAPAgAHAAcKgRohWgAPAgABAAIKsQNcaQBYAAAAAA==.',
Va='Vaatu:BAAANQADCgMIBAAAAA==.Vallkÿria:BAAANQAECgQIBAAAAA==.Varrex:BAAANQADCgEIAQAAAA==.Vaëllen:BAABNQAECn8ZAAMLAAcKvQdsMQANAQALAAcKvQdsMQANAQAUAAEKAACJvgAhAAAAAA==.',
Ve='Vehuguito:BAAANQADCgUIBQAAAA==.Vehuiáh:BAAANQAECgcIEQAAAA==.Velen:BAABNQAECn8lAAIgAAgK7R3eKACTAgAgAAgK7R3eKACTAgAAAA==.Verno:BAAANQAECgIIAgAAAA==.Verzuk:BAAANQAECgQIBgAAAA==.',
Vi='Vintejulgar:BAAANQABCggICQAAAA==.Vintekilo:BAABNQAECn8aAAIIAAkKgww5mgDpAQAIAAkKgww5mgDpAQAAAA==.Vinteservir:BAAANQABCgQIBAAAAA==.',
Vo='Voiddh:BAABNQAECn8cAAIiAAkKSxHVJAAdAgAiAAkKSxHVJAAdAgAAAA==.',
Vr='Vrenshrrgn:BAAANQAECgEIAgAAAA==.',
Vy='Vygh:BAABNQAECn8nAAMYAAkK2RtKIQD8AgAYAAkK2RtKIQD8AgAXAAEKuAuYeAA0AAAAAA==.Vyndrill:BAABNQAECn8cAAIWAAcKihSaHQDjAQAWAAcKihSaHQDjAQAAAA==.',
Wa='Walkers:BAABNQAECn8cAAINAAkKphGgWQBkAgANAAkKphGgWQBkAgAAAA==.Warlaka:BAAANQADCgYICwAAAA==.',
We='Weevil:BAAANQADCgYICgAAAA==.',
Wo='Worgenbelfin:BAAANQADCgYIBgAAAA==.',
Wy='Wyrel:BAAANQABCgYICQAAAA==.',
Xa='Xalmoria:BAAANQAECgYICQAAAA==.',
Xu='Xurumeloun:BAAANQADCgYIBgAAAA==.',
Ya='Yamii:BAAANQAECgQIBgAAAA==.Yasmini:BAAANQABCgEIAQAAAA==.',
Yi='Yingsu:BAAANQAECggIEgAAAA==.Yippwarr:BAAANQADCgMIBAAAAA==.',
Yu='Yunná:BAAANQADCgQICAAAAA==.',
Yv='Yvin:BAAANQAECgIIAgAAAA==.',
Za='Zakir:BAAANQAECgEIBAAAAA==.Zaolron:BAAANQADCgIIAQAAAA==.',
Ze='Zeddshm:BAAANQAECgEJAQABNQAECgkJKwAEAIIXAA==.Zeeno:BAAANQADCggICwAAAA==.',
Zh='Zhynah:BAAANQADCgUIBQAAAA==.',
Zi='Ziracruz:BAAANQAECgQICAAAAA==.',
Zu='Zulyn:BAAANQADCgcIFwAAAA==.',
['Àr']='Àrdath:BAAANQADCggIDgAAAA==.Àrthemís:BAAANQADCgEIAQAAAA==.',
['Ár']='Áraujo:BAAANQADCgEJAQABNQADCgUIBQAJAAAAAA==.Árÿä:BAABNQAECn8lAAINAAgK3hH1dAAjAgANAAgK3hH1dAAjAgAAAA==.',
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
