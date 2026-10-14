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

local lookup = {'Druid-Guardian','Druid-Balance','Paladin-Retribution','Mage-Frost','Warlock-Demonology','DemonHunter-Vengeance','DeathKnight-Unholy','Shaman-Restoration','Druid-Restoration','Shaman-Elemental','Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','Priest-Holy','Warrior-Arms','Warrior-Fury','Mage-Arcane','Paladin-Protection','DemonHunter-Devourer','Warrior-Protection','Shaman-Enhancement','DeathKnight-Frost','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Rogue-Outlaw','Paladin-Holy','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Priest-Discipline','Monk-Brewmaster','Evoker-Preservation','Monk-Windwalker','DemonHunter-Havoc',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aaril:BAAANQADCgUIFQAAAQ==.',
Ab='Abrams:BAABNQAECn8kAAMBAAgKJBAYHgCqAQABAAgKJBAYHgCqAQACAAgKAge2VwByAQAAAA==.Absínthè:BAAANQABCgQIBAAAAA==.',
Ag='Agnass:BAAANQADCgYIFAAAAA==.',
Ak='Akina:BAAANQAECgYIDAAAAA==.',
Al='Alcholic:BAAANQAECggIAQAAAA==.Aldea:BAAANQADCgYIBgAAAA==.Alialista:BAAANQAECgYIEQAAAA==.Alirrayia:BAAANQADCgMIAwAAAA==.Alirrayiia:BAABNQAECn8nAAIDAAgKfhCVnQDiAQADAAgKfhCVnQDiAQAAAA==.Allmight:BAAANQADCgMIAwAAAA==.Allystar:BAAANQADCgUICgAAAA==.Alvidor:BAABNQAECn8YAAIEAAYKjQo2GQArAQAEAAYKjQo2GQArAQAAAA==.',
Am='Amachine:BAAANQADCggIDgABNQAFFAYIGQAFAKMdAA==.Amethen:BAAANQAECgMIBgAAAA==.Amybabe:BAAANQAECgQICwAAAA==.',
An='Andydufresne:BAAANQAECgcICgABNQAECgkJJgAGAM8gAA==.Anestesiax:BAAANQAECgQIBAAAAA==.Anorivia:BAABNQAECn8eAAIHAAcKNQmtcwBFAQAHAAcKNQmtcwBFAQAAAA==.',
Ap='Apolloerosp:BAAANQAECgMIBQABNQAECggIGwAIAP0QAA==.Apollossham:BAABNQAECn8bAAIIAAgK/RAIcwCvAQAIAAgK/RAIcwCvAQAAAA==.',
Ar='Araluen:BAAANQABCgMIAwAAAA==.Arkagob:BAAANQADCgcIBwAAAA==.Arragora:BAAANQAECgQIBQAAAA==.Arrowdynamix:BAAANQAECgcIDwAAAA==.',
As='Ashyani:BAAANQADCgUIBQAAAA==.',
At='Atlan:BAAANQADCgUIBQABNQAECgcIHwAJAOshAA==.',
Au='Aurnhadon:BAAANQABCggIDAAAAA==.',
Ba='Babbayagga:BAABNQAECn8dAAIKAAgKIxPFUAAyAgAKAAgKIxPFUAAyAgAAAA==.Baji:BAABNQAECn8mAAMKAAkK0xb/WwALAgAKAAgK0xb/WwALAgAIAAgK+hZQXQD0AQAAAA==.Barefaall:BAACNQAFFH8KAAMLAAcKkwqeCwCRAQALAAUK1wqeCwCRAQAMAAMKLAquFQDdAAA1AAQKfzYAAwsACQoEJqceABsDAAsACApdJqceABsDAAwABgrXIEEkACgCAAAA.Barefalls:BAAANQAECgUICQABNQAFFAcICgALAJMKAA==.Baénoth:BAAANQABCgQIBgAAAA==.',
Be='Bealzebub:BAAANQAECgQIBAAAAA==.Bellucci:BAAANQADCgcICAABNQAECgUIEQANAAAAAA==.Berglock:BAAANQADCgcIBwABNQAECgUIBQANAAAAAA==.Bergonator:BAAANQAECgUIBQAAAA==.Bergue:BAAANQADCgQIBAABNQAECgUIBQANAAAAAA==.Berrodiah:BAAANQADCgcIDQABNQAECgUIEwANAAAAAA==.Bestlays:BAAANQADCgUIBQAAAA==.Bettiepage:BAAANQAECgQIBAAAAA==.',
Bh='Bheiroth:BAABNQAECn8iAAIOAAgKViSSFAAoAwAOAAgKViSSFAAoAwAAAA==.',
Bl='Blackchapell:BAAANQABCgYICQAAAA==.Blewmyload:BAAANQAECgUIBQAAAA==.Bluett:BAAANQADCgYIEQAAAA==.',
Bo='Bogertus:BAABNQAECn8lAAMPAAgKaSYfEgBzAwAPAAgKaSYfEgBzAwAQAAIKDiF7HgDJAAAAAA==.Boomertunes:BAAANQADCgQIBAAAAA==.Boxnasty:BAAANQADCgEIAQAAAA==.',
Br='Brein:BAABNQAECn8bAAIJAAYKQiMuGwBbAgAJAAYKQiMuGwBbAgAAAA==.',
Bu='Bucketeer:BAAANQAECgUICQAAAA==.Burzona:BAAANQABCgMIAwAAAA==.',
Ca='Cameltoetoe:BAAANQAECgEIAgAAAA==.Canaprey:BAAANQAECgcIEAAAAA==.Cathogin:BAAANQADCggIDgAAAA==.Catsdruid:BAAANQADCgcIBwAAAA==.Catshunter:BAAANQAECgEIAQAAAA==.',
Ce='Celaa:BAAANQADCgQIBAABNQAECgYIDAANAAAAAA==.Celebrían:BAAANQADCgUICAAAAA==.Celor:BAAANQABCgQIBgAAAA==.',
Ch='Chanka:BAAANQADCgcIEAAAAA==.Chantillary:BAAANQADCgYIFAAAAA==.Charise:BAAANQAECgUIDAAAAA==.Cheesy:BAAANQADCgYIDAAAAA==.Chopzullee:BAAANQAECgEIAQAAAA==.',
Ci='Cinnaz:BAAANQAECgUICwABNQAECgkJKwARANEVAA==.',
Cl='Clortho:BAAANQAECgQICAAAAA==.Clorthö:BAAANQADCgYICQAAAA==.',
Co='Colbiw:BAAANQABCgIIAgAAAA==.Colljack:BAACNQAFFH8aAAISAAYKZiC7AQA7AgASAAYKZiC7AQA7AgA1AAQKfykAAhIACQo4JIsEAG0DABIACQo4JIsEAG0DAAAA.Corvath:BAAANQAECgUIEQAAAA==.',
Cr='Cryptoe:BAABNQAECn83AAIRAAkKoBxsQAAEAwARAAkKoBxsQAAEAwAAAA==.',
Da='Daedamus:BAAANQADCgYIBgAAAA==.Daedelus:BAABNQAECn8cAAMTAAcKxhtrJQAXAgATAAcKxhtrJQAXAgAGAAIKew1IKABuAAAAAA==.Daglon:BAAANQAECgYIDAAAAA==.Daraedra:BAAANQADCgcIJQAAAA==.Dardolur:BAAANQADCgIIAgAAAA==.Darkbane:BAAANQADCggICAAAAA==.Darknìght:BAAANQAECgUIDgAAAA==.Darkraider:BAAANQAECgQICAAAAA==.Darkslayer:BAAANQADCgMIBQAAAA==.Darkthyr:BAAANQAECgQIBQAAAA==.',
De='Deeznutticus:BAACNQAFFH8MAAIPAAUKCBNYFQB5AQAPAAUKCBNYFQB5AQA1AAQKfyoAAg8ACQo5HxYeAD4DAA8ACQo5HxYeAD4DAAAA.Demonspud:BAAANQAECgYIEAAAAA==.Dersan:BAAANQADCgIIAgAAAA==.Destriant:BAABNQAECn8qAAISAAgKbSDqDQC6AgASAAgKbSDqDQC6AgAAAA==.Devourer:BAAANQABCgMIAwAAAA==.Dewburt:BAAANQAECgQIBQAAAA==.Deylia:BAAANQAECgEIAQABNQAFFAUICQAOAB0IAA==.',
Dh='Dhori:BAAANQADCgYIFAAAAA==.',
Di='Dillion:BAAANQAECgEIAQABNQAECgUIEQANAAAAAA==.Dionin:BAAANQADCgUICgAAAA==.Dirtybagrags:BAAANQADCggIGAAAAA==.Dirtychai:BAAANQAECgMIBAAAAA==.Disappear:BAAANQADCgYICgABNQAECgkJKwARANEVAA==.Dizzyhealz:BAAANQADCgMICQAAAA==.Dizzyhuntres:BAAANQADCgYIBwAAAA==.',
Do='Dooberto:BAABNQAECn8cAAMUAAgKFg8WGQCcAQAUAAgKFg8WGQCcAQAPAAMKywSaLgFwAAAAAA==.Dooburt:BAAANQAECgcIDQAAAA==.',
Dr='Dracaric:BAAANQADCgYIBgAAAA==.Draeca:BAAANQADCgUIEQAAAA==.Dragondznut:BAAANQADCggIDwAAAA==.Drfrostie:BAAANQAECgYIBgAAAA==.Driatin:BAAANQAECgEIAQAAAA==.',
Du='Durø:BAABNQAECn8rAAITAAgKcCVLCQBBAwATAAgKcCVLCQBBAwAAAA==.',
['Dè']='Dègenerate:BAABNQAECn8wAAIUAAkKVyEaBQAmAwAUAAkKVyEaBQAmAwAAAA==.',
Ed='Eddy:BAABNQAECn8fAAIVAAkK/Q6zFQAJAgAVAAkK/Q6zFQAJAgAAAA==.',
Ei='Eilae:BAAANQADCgcIBwAAAA==.Einherjarr:BAAANQADCgQJBAAAAA==.',
El='Eldumpling:BAAANQAECgcIEQAAAA==.Elefante:BAAANQADCgYICwAAAA==.',
Ep='Epicnym:BAAANQAECgYIEgAAAA==.',
Es='Esdeath:BAABNQAECn8XAAQWAAYKeAxYWgA4AQAWAAYKeAxYWgA4AQAHAAIK+QjhxQBbAAAXAAMK4gE+uABUAAAAAA==.',
Ev='Evoberg:BAAANQABCgYIBgABNQAECgUIBQANAAAAAA==.',
Ex='Extenze:BAABNQAECn8VAAITAAcK2xmUIwApAgATAAcK2xmUIwApAgAAAA==.',
Ez='Ezykiah:BAAANQADCggIFQAAAA==.',
Fe='Feda:BAAANQADCgQIBAAAAA==.Ferryman:BAAANQAECgUIEAAAAA==.',
Fi='Findria:BAAANQADCgYIBgABNQAECgkJJgALAP8kAA==.',
Fo='Forphium:BAACNQAFFH8QAAMYAAUKggrhCABcAQAYAAUKwgfhCABcAQAZAAEKTQu8HwBHAAA1AAQKfycAAxgACQpfHvUOAIgCABgACArIH/UOAIgCABkAAQrnFd+YAEQAAAAA.',
Fr='Fredolf:BAAANQADCgQJBAAAAA==.Freespirit:BAAANQAECgcIDAABNQAFFAYIGwAaAEskAA==.Friarkuck:BAAANQADCgEIAQAAAA==.Frierenn:BAAANQABCggIEAAAAA==.Frostieheals:BAAANQAECgMIAwAAAA==.',
Ga='Gahlina:BAAANQAECgEIAQAAAA==.Gambaaddict:BAABNQAECn8ZAAIbAAcKGBQPCgDdAQAbAAcKGBQPCgDdAQAAAA==.Ganhammer:BAAANQADCgIIAgAAAA==.Garshan:BAAANQAECgMIAwAAAA==.',
Ge='Genestarwind:BAAANQAECgQICAAAAA==.',
Gh='Ghexn:BAAANQADCgIIAgAAAA==.',
Gi='Gilleyy:BAAANQAECgQICQAAAA==.Gird:BAABNQAECn8bAAIcAAcKJxI+eACsAQAcAAcKJxI+eACsAQAAAA==.Girdlock:BAAANQAECgIIAgAAAA==.',
Gn='Gnymesis:BAAANQADCgYICwAAAA==.',
Go='Goatmonger:BAAANQAECggICgAAAA==.Goinpostal:BAAANQADCgYICwAAAA==.Goldblade:BAAANQAECggICAAAAA==.Gordek:BAABNQAECn8VAAIDAAgKdhJ+nADlAQADAAgKdhJ+nADlAQAAAA==.',
Gr='Grahra:BAAANQABCgIIBAAAAA==.Grantaron:BAABNQAECn8mAAIDAAgKpx2EVwCMAgADAAgKpx2EVwCMAgAAAA==.Grimskul:BAABNQAECn8nAAIHAAkKLxmBMABqAgAHAAkKLxmBMABqAgAAAA==.Grntitan:BAAANQADCgcIFwAAAA==.Gruid:BAAANQADCgYIBgAAAA==.',
Gw='Gwoohoori:BAAANQAECggIDQAAAA==.',
Ha='Halukari:BAAANQADCggIDAABNQAFFAUICQAOAB0IAA==.Haléon:BAAANQAECgUIDgAAAA==.Hamnier:BAAANQABCgcIDAAAAA==.Harfnan:BAAANQADCgYICQAAAA==.Harperlee:BAAANQADCgUIBQAAAA==.Harrin:BAAANQADCggIDgAAAA==.',
He='Headshotty:BAAANQAECgQJCAAAAA==.Hellfire:BAAANQADCgYIBgAAAA==.Hezrel:BAAANQAECgQIBgAAAA==.',
Hi='Hinal:BAAANQAECgYIEgAAAA==.',
Ho='Holyenabler:BAAANQAECgYIEAAAAA==.Honzo:BAAANQAFFAEIAQAAAA==.',
Hu='Hungor:BAAANQABCgQIBAAAAA==.',
Ic='Iceberg:BAAANQADCgEIAQABNQAECgUIBQANAAAAAA==.Icecrystal:BAAANQABCgIIAgAAAA==.',
Ih='Iheartbailey:BAAANQADCgQIBAAAAA==.',
Im='Imcruel:BAACNQAFFH8XAAIRAAYKexpxDQAHAgARAAYKexpxDQAHAgA1AAQKfzQAAhEACQqsIkEPAJYDABEACQqsIkEPAJYDAAAA.Iminyë:BAAANQAECgEIAQAAAA==.',
Io='Iorese:BAAANQADCggIDwAAAA==.',
Ir='Iriana:BAEANQADCgYIMQAAAA==.',
Ja='Jabes:BAAANQAECgUIBQAAAA==.Jackiegan:BAAANQADCgEIAQAAAA==.Jagershamer:BAAANQAECgcIBwABNQAECggIBwANAAAAAA==.Jasperine:BAAANQAECgcIDQABNQAFFAYIGwAaAEskAA==.',
Je='Jenneldots:BAAANQAECgUIEAABNQAECgYICgANAAAAAA==.Jerce:BAAANQADCgUICQAAAA==.',
Jo='Johnnyhuntz:BAAANQADCgYICAAAAA==.',
Ju='Juacqer:BAAANQADCgYIDwAAAA==.Junamara:BAAANQAECgQICQAAAA==.',
Ka='Kaant:BAABNQAECn8bAAMKAAYKIxd2egCvAQAKAAUKPhl2egCvAQAIAAYKgA/epQAjAQAAAA==.Kaetiegh:BAAANQADCgUICgAAAA==.Kaidevyn:BAABNQAECn8bAAIWAAgKHRJuPQDRAQAWAAgKHRJuPQDRAQAAAA==.Kardead:BAAANQAECgEIAQAAAA==.Kat:BAAANQADCgQICAAAAA==.',
Kb='Kbang:BAAANQAECgIIAgAAAA==.',
Ke='Keiran:BAABNQAECn8pAAILAAgKKyHbLADlAgALAAgKKyHbLADlAgAAAA==.Kenix:BAAANQADCgUICAABNQADCgYICgANAAAAAA==.',
Kh='Khalnerys:BAAANQAECgUIEwAAAA==.Khaotick:BAEBNQAECn8nAAQFAAkK3hgHVABWAgAFAAgKAxgHVABWAgAdAAQK5A66PADNAAAeAAEKAADUMgAtAAABNQAECggIEgANAAAAAA==.Khoulock:BAABNQAECn8hAAQFAAkK6B/+LADPAgAFAAkKfR/+LADPAgAdAAYK4B/MFwCtAQAeAAEKAAD3KwA+AAAAAA==.',
Ki='Kimmi:BAAANQAECgUIBQAAAA==.Kimmispally:BAAANQADCggICAAAAA==.Kiro:BAAANQADCgYIDAAAAA==.',
Ko='Kotawar:BAAANQAECgMIAwAAAA==.Kozana:BAAANQADCgIIAgAAAA==.',
Kt='Kthxbye:BAAANQAECggIBwAAAA==.',
Ku='Kuraishin:BAABNQAECn8iAAIfAAkKdh61BgD7AgAfAAkKdh61BgD7AgAAAA==.Kuterr:BAAANQADCgUIBQAAAA==.',
Ky='Kyrae:BAAANQADCgYIEAABNQAECgYIDwANAAAAAA==.Kyrub:BAAANQABCggICAAAAA==.',
La='Latheal:BAAANQADCgYIEwAAAA==.Latto:BAAANQAECgUIDwABNQAECgYICgANAAAAAA==.',
Le='Lengex:BAAANQAECgUIBAAAAA==.Lero:BAAANQAECgIIAgAAAA==.Levatan:BAAANQAECgEIAQAAAA==.Lexoh:BAAANQAECgQIAgAAAA==.',
Li='Lilieth:BAAANQADCgUIDwAAAA==.Liltankarmor:BAAANQAECgYICgAAAA==.Lindir:BAABNQAECn8mAAILAAkK/yRwDAB6AwALAAkK/yRwDAB6AwAAAA==.Liquid:BAABNQAECn8iAAMaAAkKNBrZFQCtAgAaAAkKNBrZFQCtAgAgAAEKtAPdLQAoAAAAAA==.Litasfk:BAAANQAECgQICAAAAA==.Liuni:BAABNQAECn8hAAIhAAgKiRS1EQDIAQAhAAgKiRS1EQDIAQAAAA==.',
Lo='Lobopeste:BAABNQAECn8bAAIXAAYKQw6KeAASAQAXAAYKQw6KeAASAQAAAA==.Loborocco:BAAANQADCgIIAgAAAA==.Lobotomi:BAAANQADCgYIDgAAAA==.Lorantell:BAAANQADCgUIBQAAAA==.Lorelynn:BAABNQAECn8lAAIdAAcKBBq0CgBLAgAdAAcKBBq0CgBLAgAAAA==.Loðbrók:BAAANQADCgYIDAAAAA==.',
Lu='Luci:BAAANQADCgQIBAABNQAECgYICgANAAAAAA==.Luckycritz:BAAANQAECgEIAQABNQAFFAMIBwAKAEwUAA==.Lucìan:BAABNQAECn8fAAIJAAYK6yGlHQA/AgAJAAYK6yGlHQA/AgAAAA==.Luna:BAAANQAECgQIBAABNQAECgkJGwAOAPYbAA==.Lunaclair:BAAANQAECgcIEgABNQAECgkJIgAfAHYeAA==.Lunarielle:BAAANQAECgQIBgAAAA==.',
Ma='Mabrito:BAAANQAECgcIDgABNQAFFAcIGAACAIUVAA==.Macfly:BAABNQAECn8tAAILAAgKwhxMUQB5AgALAAgKwhxMUQB5AgAAAA==.Macneel:BAAANQADCgEIAQABNQADCgYIEwANAAAAAA==.Magicmissile:BAAANQADCgQIBAABNQAECgkJKAAPAMQbAA==.Malevalous:BAAANQADCgQICQABNQAECgcIHgAHAHIZAA==.Mancath:BAABNQAECn8eAAIDAAkKRxiEYQBxAgADAAkKRxiEYQBxAgAAAA==.Maplè:BAAANQADCgYIBgABNQAECgEIAQANAAAAAA==.Marlei:BAAANQAECgUICwABNQAECgYIDAANAAAAAA==.Maru:BAAANQADCgcIBwABNQAECgkJJgAKANMWAA==.Maxzang:BAAANQABCggIEAAAAA==.',
Me='Medenà:BAAANQADCgUICAAAAA==.Meeko:BAACNQAFFH8FAAIiAAMKOxu4DwD3AAAiAAMKOxu4DwD3AAA1AAQKfxkAAiIACQoeHKkOALwCACIACQoeHKkOALwCAAE1AAUUBwgPACIAuBYA.Melfie:BAAANQAECgEIAQAAAA==.',
Mi='Midoriya:BAAANQAECggIDQAAAA==.Mihoshi:BAAANQADCgUIBQAAAA==.Mistjack:BAAANQADCggICAAAAA==.',
Mo='Moldyjack:BAAANQAECgIIAwAAAA==.Morphium:BAAANQAECgYIBgABNQAFFAUIEAAYAIIKAA==.Mortiis:BAAANQADCgMIAwAAAA==.',
My='Myzyry:BAABNQAECn8YAAIPAAgKZhIFigD/AQAPAAgKZhIFigD/AQAAAA==.',
['Mä']='Märtyr:BAAANQADCgUIBQAAAA==.',
['Må']='Måze:BAAANQAECgQIBAAAAA==.',
['Më']='Mërlïn:BAAANQADCgYIBgAAAA==.',
Na='Nards:BAAANQAECggICgAAAA==.Nazdormu:BAAANQAECgQICQAAAA==.',
Ne='Neisen:BAAANQAECgQICQAAAA==.Neptune:BAAANQADCggICAAAAA==.Nevare:BAAANQAECgcICwAAAA==.',
Ni='Nite:BAABNQAECn8rAAIRAAkK0RXVlABWAgARAAkK0RXVlABWAgAAAA==.',
No='Nou:BAEANQAECggIBwABNQAECggIEgANAAAAAA==.',
Nu='Nubi:BAAANQADCgIIAgAAAA==.Nugent:BAAANQAECggIEwAAAA==.',
Ny='Nymmie:BAAANQADCggIDwAAAA==.Nymofthedead:BAAANQADCgcIBwAAAA==.',
Oa='Oakgrove:BAAANQADCgIIAgAAAA==.',
Ok='Okarun:BAAANQADCgEIAQAAAA==.',
On='Oneforall:BAABNQAECn8uAAIcAAkKGRtrKgC8AgAcAAkKGRtrKgC8AgAAAA==.',
Or='Orphen:BAAANQAECgQIBAAAAA==.',
Pa='Pailly:BAAANQABCgQIBAAAAA==.Papalion:BAABNQAECn8dAAILAAcKdgv6qQCtAQALAAcKdgv6qQCtAQAAAA==.Paryl:BAAANQAECgUIEQAAAA==.Pawbs:BAAANQADCgYIBgAAAA==.',
Pe='Peanuts:BAAANQAECggICAAAAA==.',
Pi='Pikake:BAAANQADCgUICQAAAA==.Pinklilydrd:BAAANQADCgYIDwAAAA==.',
Pl='Plaindonut:BAABNQAECn8oAAMJAAkKiyFSBwBLAwAJAAkKiyFSBwBLAwACAAEKAABBowBPAAAAAA==.Pluffeh:BAAANQADCgQIBAABNQAECgMIBQANAAAAAA==.',
Pm='Pmoney:BAAANQAECgYIBgAAAA==.',
Pr='Prissidebow:BAAANQADCgYIBgAAAA==.Prissygalore:BAAANQADCgEIAQAAAA==.',
Pu='Puddinpie:BAAANQADCgEIAQAAAA==.Punkhazard:BAAANQAECgEIAQAAAA==.Putras:BAAANQABCgIIAgAAAA==.',
Qu='Quartz:BAAANQAECgYICAABNQAECggIJQAPAGkmAA==.',
Ra='Ranor:BAAANQAECgIIAgABNQAECggIIQAhAIkUAA==.Ravenbrook:BAABNQAECn8wAAIQAAkKqCYrAAD4AwAQAAkKqCYrAAD4AwAAAA==.Ravus:BAAANQADCgIIAgAAAA==.Rawrr:BAAANQAECgUIEQAAAA==.Raxie:BAACNQAFFH8JAAQOAAUKHQhiGgATAQAOAAQKVQliGgATAQAaAAMK6QMwEADFAAAgAAEKSQFTBQAxAAA1AAQKfysABBoACQqCFJAdAFICABoACQqCFJAdAFICACAABwo6EYQLAIYBAA4AAwopGDe4AOoAAAAA.',
Re='Reddfoxx:BAAANQAECgcIDQAAAA==.Resepuff:BAAANQADCggIEAAAAA==.',
Rh='Rhymunky:BAAANQADCgMIAwAAAA==.',
Ri='Rifthor:BAAANQADCgYIBgAAAA==.Ripmxi:BAAANQAECgYIEgAAAA==.',
Ru='Runelight:BAAANQADCgMIAwABNQAECgkJIgAIAD0aAA==.Runeshock:BAABNQAECn8iAAIIAAkKPRr8NgCBAgAIAAkKPRr8NgCBAgAAAA==.Runesummon:BAAANQADCggICAAAAA==.Rupertgiless:BAACNQAFFH8UAAIFAAYKoROQCQDTAQAFAAYKoROQCQDTAQA1AAQKfysAAgUACQqPHfgyALoCAAUACQqPHfgyALoCAAAA.',
Sa='Sainttristan:BAAANQABCgEIAQAAAA==.Saluran:BAAANQABCgYIBgAAAA==.Sanitariums:BAAANQADCgQIBAABNQADCgYIEAANAAAAAA==.Sannea:BAAANQADCgUICgABNQAECgYIDAANAAAAAA==.Sarcastyx:BAAANQAECgYIEwAAAA==.Saværo:BAAANQADCgMIBAAAAA==.Saxines:BAAANQAECgMIBAAAAA==.',
Sc='Scaliefox:BAAANQADCgQIBAABNQAECgYIGwAOAL4RAA==.Schwarznacht:BAAANQAECgQIBAAAAA==.',
Se='Seekndestroy:BAABNQAECn8aAAIKAAcKywe6pgBDAQAKAAcKywe6pgBDAQAAAA==.Semperfimack:BAAANQADCgQJBAAAAA==.',
Sh='Shankkerz:BAAANQAECgcIEAAAAA==.',
Si='Simonx:BAAANQAECgcIDgAAAA==.Sindusk:BAAANQAECgYIDAAAAA==.Sitzho:BAAANQADCggIGgAAAA==.',
Sk='Skeleton:BAAANQABCgIIAgAAAA==.Skullblade:BAAANQAECgQICAAAAA==.Skybringer:BAABNQAECn8ZAAIDAAcKrAXf9QArAQADAAcKrAXf9QArAQAAAA==.Skydras:BAABNQAECn8pAAMXAAkKfxx7JQCOAgAXAAgKLhx7JQCOAgAHAAcKPRO7YwB+AQAAAA==.',
Sm='Smolbeans:BAAANQADCgQIBAAAAA==.Smoothscales:BAAANQADCgUIBQAAAA==.',
So='Sonofgrumpy:BAAANQADCggIEAABNQAECgcIEAANAAAAAA==.Sorphium:BAAANQAECgUICQABNQAFFAUIEAAYAIIKAA==.Soxxy:BAAANQADCgEIAQABNQAECgYICgANAAAAAA==.',
Sp='Sparhawk:BAAANQADCgYIEQAAAA==.',
St='Stham:BAAANQADCgQIBQAAAA==.Stormyprissi:BAAANQADCgUIDQAAAA==.Strombjorn:BAAANQAECgEIAQAAAA==.',
Ta='Talie:BAAANQAECgIIAwABNQAECgMIBQANAAAAAA==.Tasireth:BAAANQADCgMIAwAAAA==.',
Te='Tessi:BAABNQAECn8hAAMEAAcKcQl2HAAIAQAEAAYKWQt2HAAIAQARAAUK/wFsgQG7AAAAAA==.Testamental:BAAANQAECgIJAgAAAA==.',
Th='Thaloran:BAAANQADCgcICAAAAA==.Thalrian:BAAANQAECgcIDAABNQAECgkJLQAPAD8jAA==.Theberes:BAAANQAECgEIAQAAAA==.Thelance:BAAANQABCggIDQAAAA==.Theylive:BAAANQADCgcIBwAAAA==.Thighs:BAAANQAECgQIBgAAAA==.Thordanil:BAAANQAECgYIEAAAAA==.',
Ti='Tiahina:BAAANQADCgUIBQAAAA==.Tioklarus:BAAANQADCggICQAAAA==.',
To='Tokifuji:BAAANQADCgIIAgABNQADCgYIBgANAAAAAA==.Tourettes:BAAANQADCggJCAAAAA==.Toya:BAABNQAECn8lAAMYAAkKQhUfEgBfAgAYAAkKQhUfEgBfAgAZAAQKZwWKfQCzAAAAAA==.',
Tr='Transfurmer:BAAANQADCgMIAwAAAA==.Trashdk:BAAANQADCgcIBwAAAA==.Trevain:BAAANQADCgYIEwAAAA==.Trivia:BAAANQADCgcIJAAAAA==.Truthordare:BAAANQAECgQICgAAAA==.',
Tu='Turtei:BAAANQADCggICAABNQAFFAYIGAAjAE0mAA==.Turtl:BAACNQAFFH8YAAIjAAYKTSZnAQCmAgAjAAYKTSZnAQCmAgA1AAQKfyoAAiMACQruJiMBAN4DACMACQruJiMBAN4DAAAA.',
Ty='Tylenolz:BAAANQADCgYIDAAAAA==.',
Ug='Uglypetguy:BAAANQADCgEIAQAAAA==.Uglypriest:BAAANQADCggIDgAAAA==.Uglyrogue:BAAANQAECgIIAgAAAA==.',
Ul='Ulgrym:BAAANQADCgUIEwAAAA==.',
Un='Unbalancéd:BAAANQADCgYIEAAAAA==.Unbroken:BAAANQABCgMIAgAAAA==.',
Va='Vaeadin:BAAANQAECgEIAQAAAA==.Vahra:BAAANQADCgYIDwAAAA==.Valantis:BAAANQAECgQIBAAAAA==.Valgaskav:BAABNQAECn8VAAIDAAcKQiTHUACfAgADAAcKQiTHUACfAgAAAA==.Valkor:BAAANQADCgIIAgAAAA==.Valric:BAAANQAECgIIAgAAAA==.',
Ve='Vegasnight:BAAANQADCggIEwAAAA==.Vella:BAAANQAECgEIAQAAAA==.Venithan:BAAANQAECgYIDwAAAA==.Verdesoul:BAAANQADCgQIBAABNQAECgUIDQANAAAAAA==.',
Vi='Vikkrum:BAAANQADCgYICwABNQADCgYIEwANAAAAAA==.Virani:BAAANQAECgYICQAAAA==.',
Vo='Voladro:BAAANQAECgIIAgAAAA==.Volanie:BAAANQADCgYIBgAAAA==.Volos:BAAANQAECgUIEwAAAA==.Vordaman:BAABNQAECn8pAAMHAAcKoBi5UwDAAQAHAAcKoBi5UwDAAQAWAAEKYAVBsQArAAAAAA==.',
Vy='Vynír:BAACNQAFFH8IAAMdAAQKGxGtDwCXAAAFAAMKkg0IJwDNAAAdAAIKBw2tDwCXAAA1AAQKfyQAAwUACQoqIeIxAL4CAAUACArhIOIxAL4CAB0ABApsHCMoADYBAAAA.',
Wa='Waandur:BAAANQADCgEIAQAAAA==.Waghoba:BAACNQAFFH8GAAIfAAIK0hRUAwCbAAAfAAIK0hRUAwCbAAA1AAQKf04AAh8ACQpEJkMAAAQEAB8ACQpEJkMAAAQEAAAA.Waito:BAAANQADCggIDQAAAA==.Wandä:BAAANQAECgUIEwAAAA==.Warborn:BAAANQADCggIDAAAAA==.Warrionomous:BAABNQAECn8oAAIPAAkKxBv4UgCOAgAPAAkKxBv4UgCOAgAAAA==.Washu:BAABNQAECn8jAAMkAAkKZxWuHwCZAgAkAAkKZxWuHwCZAgAGAAQK8AUiJwB5AAAAAA==.',
We='Wetkittyy:BAAANQABCgUICAAAAA==.',
Wh='Whobetter:BAAANQADCgYICQAAAA==.',
Wi='Winterous:BAAANQAECgQIBgAAAA==.',
Wo='Wonderbread:BAABNQAECn8tAAIDAAgKMxO3lwDvAQADAAgKMxO3lwDvAQAAAA==.',
['Wá']='Wáshu:BAAANQAECgQIBAAAAA==.',
Xa='Xaani:BAAANQAECgIIAgAAAA==.',
Xe='Xenan:BAABNQAECn8YAAIDAAYKvwrS6ABDAQADAAYKvwrS6ABDAQAAAA==.',
Xt='Xtrolldinary:BAAANQAECgEIAQAAAA==.',
Ye='Yeastmode:BAAANQAECgYIEAAAAA==.',
Yi='Yingsol:BAAANQAECgIIAgABNQAECgYIDwANAAAAAA==.',
Yo='Yonahh:BAAANQAECgUIDAAAAA==.',
Yv='Yvelthilios:BAAANQADCgcICgAAAA==.',
Za='Zangsha:BAAANQADCgcIBwAAAA==.',
Ze='Zeebra:BAABNQAECn8VAAILAAYKkw/9uQCLAQALAAYKkw/9uQCLAQAAAA==.Zeg:BAABNQAECn8eAAMIAAkKIx7gHwDoAgAIAAkKIx7gHwDoAgAKAAIK1gsdEAFlAAAAAA==.Zega:BAAANQADCgcIBwAAAA==.Zegafur:BAAANQAECgIIAgAAAA==.',
Zi='Zillionbucks:BAAANQAFFAEJAQAAAA==.Zillionbúcks:BAAANQAECgUICQABNQAFFAEJAQANAAAAAA==.',
Zu='Zulg:BAAANQADCgQJBAAAAA==.Zulgore:BAAANQAECgYIBgAAAA==.Zullee:BAAANQABCggIFgAAAA==.',
['Zê']='Zêddicus:BAABNQAECn8mAAMdAAgKGRKhJQBGAQAFAAYKpg+vqgB4AQAdAAUKvhShJQBGAQAAAA==.',
['Áq']='Áquafina:BAABNQAECn8nAAIRAAkK6Qz9xAD5AQARAAkK6Qz9xAD5AQAAAA==.',
['Ðö']='Ðö:BAAANQAECgUIDQAAAA==.',
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
