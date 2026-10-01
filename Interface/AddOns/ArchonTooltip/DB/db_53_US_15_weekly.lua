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

local lookup = {'Druid-Guardian','Druid-Balance','Unknown-Unknown','Paladin-Retribution','Warlock-Demonology','DemonHunter-Vengeance','Shaman-Elemental','Shaman-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Arms','Warrior-Fury','Mage-Arcane','Paladin-Protection','Priest-Shadow','DemonHunter-Devourer','Warrior-Protection','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Unholy','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Evoker-Preservation','Paladin-Holy','Druid-Restoration','Priest-Discipline','DeathKnight-Blood','Mage-Frost','Monk-Windwalker','DeathKnight-Frost',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaril:BAAANQADCgUIFQAAAQ==.',
Ab='Abrams:BAABNQAECoEYAAMBAAgKxgxnHQApAQACAAgKvAfXRQCGAQABAAYKaQ5nHQApAQAAAA==.Absínthè:BAAANQABCgQIBAAAAA==.',
Ag='Agnass:BAAANQADCgUIDgAAAA==.',
Ak='Akina:BAAANQADCggIFwABNQAECgUICgADAAAAAA==.',
Al='Alcholic:BAAANQAECgEIAQAAAA==.Aldea:BAAANQADCgYIBgAAAA==.Alialista:BAAANQAECgYIBgAAAA==.Alirrayiia:BAABNQAECoEbAAIEAAgKmg48fgDKAQAEAAgKmg48fgDKAQAAAA==.Allmight:BAAANQADCgEIAQAAAA==.Allystar:BAAANQADCgUICgAAAA==.Alvidor:BAAANQAECgUIDQAAAA==.',
Am='Amachine:BAAANQADCggIDgABNQAFFAUIDgAFACUmAA==.Amethen:BAAANQAECgMIBAAAAA==.Amybabe:BAAANQAECgIIAwAAAA==.',
An='Andydufresne:BAAANQAECgEIAQABNQAECggIHgAGAPEgAA==.Anorivia:BAAANQAECgYIEgAAAA==.',
Ap='Apolloerosp:BAAANQAECgEIAQABNQAECgcIEgADAAAAAA==.Apollossham:BAAANQAECgcIEgAAAA==.',
Ar='Araluen:BAAANQABCgMIAwAAAA==.Arkagob:BAAANQADCgcIBwAAAA==.Arragora:BAAANQAECgQIBQAAAA==.Arrowdynamix:BAAANQAECgYIDQAAAA==.',
As='Ashyani:BAAANQADCgUIBQAAAA==.',
At='Atlan:BAAANQADCgUIBQABNQAECgQIDgADAAAAAA==.',
Au='Aurnhadon:BAAANQABCggIDAAAAA==.',
Ba='Babbayagga:BAAANQAECgYIDAAAAA==.Baji:BAABNQAECoEVAAMHAAgKuRpwRQASAgAHAAcK/BhwRQASAgAIAAcKpxaWVwC3AQAAAA==.Barefaall:BAACNQAFFIEIAAMJAAYKbhBLBQCkAQAJAAUKJxFLBQCkAQAKAAEK1QxAGwBGAAA1AAQKgTMAAwkACQo6JWgOAEoDAAkACAotJmgOAEoDAAoABgr5G0IhAAMCAAAA.Barefalls:BAAANQAECgUIBwABNQAFFAYICAAJAG4QAA==.Baénoth:BAAANQABCgQIBgAAAA==.',
Be='Beastmastery:BAAANQAECggICAAAAA==.Bellucci:BAAANQADCgYIBgABNQAECgUICwADAAAAAA==.Berglock:BAAANQADCgcIBwAAAA==.Bergonator:BAAANQADCggIIAAAAA==.Berrodiah:BAAANQADCgcIDQABNQAECgUIEQADAAAAAA==.Bestlays:BAAANQADCgUIBQAAAA==.Bettiepage:BAAANQADCgIIAgAAAA==.',
Bh='Bheiroth:BAAANQAECgYIEwAAAA==.',
Bl='Blackchapell:BAAANQABCgYICQAAAA==.Blewmyload:BAAANQADCggIBgAAAA==.Bluett:BAAANQADCgUICwAAAA==.',
Bo='Bogertus:BAABNQAECoEdAAMLAAgKRyZsDACCAwALAAgKRyZsDACCAwAMAAEKDiFNIQBaAAAAAA==.Boomertunes:BAAANQADCgQIBAAAAA==.',
Br='Brein:BAAANQAECgUIDQAAAA==.',
Bu='Bucketeer:BAAANQAECgUICQAAAA==.Burzona:BAAANQABCgMIAwAAAA==.',
Ca='Cameltoetoe:BAAANQAECgEIAgAAAA==.Canaprey:BAAANQAECgYIDwAAAA==.Cathogin:BAAANQADCgYIBgAAAA==.Catshunter:BAAANQADCgYIDAAAAA==.',
Ce='Celaa:BAAANQADCgQIBAABNQAECgUICgADAAAAAA==.Celebrían:BAAANQADCgUJCAAAAA==.Celor:BAAANQABCgQIBgAAAA==.',
Ch='Chanka:BAAANQADCgYICQAAAA==.Chantillary:BAAANQADCgUIDgAAAA==.Charise:BAAANQAECgQIBwAAAA==.Cheesy:BAAANQADCgYIDAAAAA==.Chopzullee:BAAANQADCgYIDAAAAA==.',
Ci='Cinnaz:BAAANQAECgUICwABNQAECgkJIgANAAERAA==.',
Cl='Clortho:BAAANQAECgIIBAAAAA==.',
Co='Colbiw:BAAANQABCgIIAgAAAA==.Colljack:BAACNQAFFIEPAAIOAAUK9h/ZAQDUAQAOAAUK9h/ZAQDUAQA1AAQKgSUAAg4ACQqjJCMCAJkDAA4ACQqjJCMCAJkDAAAA.Corvath:BAAANQAECgQICQAAAA==.',
Cr='Cryptoe:BAABNQAECoEpAAINAAkKUB7BLgAVAwANAAkKUB7BLgAVAwAAAA==.',
Da='Daedelus:BAAANQAECgYICwAAAA==.Daglon:BAAANQAECgEIAQAAAA==.Daraedra:BAAANQADCgcIGwAAAA==.Dardolur:BAAANQADCgIIAgAAAA==.Darknìght:BAAANQAECgQIBAAAAA==.Darkslayer:BAAANQADCgMIBQAAAA==.Darkthyr:BAAANQAECgQIBQAAAA==.',
De='Deeznutticus:BAACNQAFFIEIAAILAAMKvRGjFAD8AAALAAMKvRGjFAD8AAA1AAQKgSIAAgsACQouHrIlAPsCAAsACQouHrIlAPsCAAAA.Demonspud:BAAANQAECgYIEAAAAA==.Dersan:BAAANQADCgIIAgAAAA==.Destriant:BAABNQAECoEcAAIOAAgKcR+KCgCzAgAOAAgKcR+KCgCzAgAAAA==.Devourer:BAAANQABCgMIAwAAAA==.Dewburt:BAAANQADCgUJBQAAAA==.Deylia:BAAANQADCgYIDAABNQAECgkJJgAPAH0UAA==.',
Dh='Dhori:BAAANQADCgUIDgAAAA==.',
Di='Dillion:BAAANQAECgEIAQABNQAECgUICwADAAAAAA==.Dionin:BAAANQADCgUICgAAAA==.Dirtychai:BAAANQADCgMIAwAAAA==.Disappear:BAAANQADCgYICgABNQAECgkJIgANAAERAA==.Dizzyhealz:BAAANQADCgMIBQAAAA==.Dizzyhuntres:BAAANQADCgYIBwAAAA==.',
Do='Dooberto:BAAANQAECgYICgAAAA==.Dooburt:BAAANQAECgQIBgAAAA==.',
Dr='Dracaric:BAAANQADCgYIBgAAAA==.Draeca:BAAANQADCgQIDAAAAA==.Dragondznut:BAAANQADCggIDwAAAA==.Drfrostie:BAAANQAECgUIBQAAAA==.Driatin:BAAANQAECgEIAQAAAA==.',
Du='Durø:BAABNQAECoEbAAIQAAcK2iJyEADHAgAQAAcK2iJyEADHAgAAAA==.',
['Dè']='Dègenerate:BAABNQAECoEeAAIRAAgKJSOQAwAkAwARAAgKJSOQAwAkAwAAAA==.',
Ed='Eddy:BAAANQAECggIEwAAAA==.',
Ei='Einherjarr:BAAANQADCgQJBAAAAA==.',
El='Eldumpling:BAAANQAECgYICgAAAA==.Elefante:BAAANQADCgUIBQAAAA==.',
Ep='Epicnym:BAAANQAECgUIBwAAAA==.',
Es='Esdeath:BAAANQAECgUICwAAAA==.',
Ex='Extenze:BAAANQAECgUIDgAAAA==.',
Ez='Ezykiah:BAAANQABCgQIBQAAAA==.',
Fe='Feda:BAAANQADCgQIBAAAAA==.Ferryman:BAAANQAECgQIBwAAAA==.',
Fi='Findria:BAAANQADCgYIBgABNQAECggIHgAJADgkAA==.',
Fo='Forphium:BAACNQAFFIEHAAMSAAQK0AhdCQDsAAASAAMKPApdCQDsAAATAAEKjASNFgBGAAA1AAQKgSIAAxIACQr2HKQNAIACABIACArYHaQNAIACABMAAQrnFRhvAEcAAAAA.',
Fr='Fredolf:BAAANQADCgQJBAAAAA==.Freespirit:BAAANQAECgcIDAABNQAFFAYIFQAPADoiAA==.Friarkuck:BAAANQADCgEIAQAAAA==.Frostieheals:BAAANQABCgcICgAAAA==.',
Ga='Gahlina:BAAANQADCggIHgAAAA==.Gambaaddict:BAAANQAECgYIDwAAAA==.Garshan:BAAANQAECgMIAwAAAA==.',
Gh='Ghexn:BAAANQADCgIIAgAAAA==.',
Gi='Gilleyy:BAAANQAECgQICQAAAA==.Gird:BAAANQAECgYIDQAAAA==.Girdlock:BAAANQADCggICgAAAA==.',
Gn='Gnymesis:BAAANQADCgYICwAAAA==.',
Go='Goatmonger:BAAANQAECggIBQAAAA==.Goinpostal:BAAANQADCgYICwAAAA==.Goldblade:BAAANQAECggICAAAAA==.Gordek:BAAANQAECgYIEwAAAA==.',
Gr='Grahra:BAAANQABCgIIBAAAAA==.Grantaron:BAABNQAECoEZAAIEAAgKThz6QwB+AgAEAAgKThz6QwB+AgAAAA==.Grimskul:BAABNQAECoEbAAIUAAgK1BVALwAZAgAUAAgK1BVALwAZAgAAAA==.Grntitan:BAAANQADCgQJCgAAAA==.Gruid:BAAANQADCgYIBgAAAA==.',
Gw='Gwoohoori:BAAANQAECgMIAgAAAA==.',
Ha='Halukari:BAAANQADCggIDAABNQAECgkJJgAPAH0UAA==.Haléon:BAAANQAECgUICAAAAA==.Hamnier:BAAANQABCgcICAAAAA==.Harrin:BAAANQADCggICAAAAA==.',
He='Headshotty:BAAANQAECgQJCAAAAA==.Hellfire:BAAANQADCgYIBgAAAA==.Hezrel:BAAANQAECgQIBAAAAA==.',
Hi='Hinal:BAAANQAECgMIBwAAAA==.',
Ho='Holyenabler:BAAANQAECgYIEAAAAA==.Honzo:BAAANQAECgYIBAAAAA==.',
Hu='Hungor:BAAANQABCgQIBAAAAA==.',
Ic='Icecrystal:BAAANQABCgIIAgAAAA==.',
Ih='Iheartbailey:BAAANQADCgQIBAAAAA==.',
Im='Imcruel:BAACNQAFFIENAAINAAUK7RQxEwCKAQANAAUK7RQxEwCKAQA1AAQKgSoAAg0ACQoCIuQbAFQDAA0ACQoCIuQbAFQDAAAA.',
Io='Iorese:BAAANQADCggIDwAAAA==.',
Ir='Iriana:BAEANQADCgYIJQAAAA==.',
Ja='Jackiegan:BAAANQADCgEJAQAAAA==.Jagershamer:BAAANQAECgUJBQAAAA==.Jasperine:BAAANQAECgUIBwABNQAFFAYIFQAPADoiAA==.',
Je='Jenneldots:BAAANQAECgQIDgABNQAECgYICgADAAAAAA==.Jerce:BAAANQADCgUICQAAAA==.',
Jo='Johnnyhuntz:BAAANQADCgYICAAAAA==.',
Ju='Juacqer:BAAANQADCgQJCQAAAA==.Junamara:BAAANQAECgQICQAAAA==.',
Ka='Kaant:BAAANQAECgUIDQAAAA==.Kaetiegh:BAAANQADCgUICgAAAA==.Kaidevyn:BAAANQAECgYIEQAAAA==.Kardead:BAAANQADCgYIBwAAAA==.Kat:BAAANQADCgQICAAAAA==.',
Kb='Kbang:BAAANQAECgIIAgAAAA==.',
Ke='Keiran:BAABNQAECoEbAAIJAAgK8h4GJwDBAgAJAAgK8h4GJwDBAgAAAA==.Kenix:BAAANQADCgUICAABNQADCgYICgADAAAAAA==.',
Kh='Khalnerys:BAAANQAECgQICQAAAA==.Khaotick:BAEBNQAECoEiAAQFAAkKXhgORABFAgAFAAgKqhcORABFAgAVAAQK5A5tNQDXAAAWAAEKJg2JKQAvAAABNQAECgcICwADAAAAAA==.Khoulock:BAABNQAECoEhAAQFAAkKBB8wFwD+AgAFAAkKsR4wFwD+AgAVAAYK7hoGFQC5AQAWAAEKJhlPIwBAAAAAAA==.',
Ki='Kimmi:BAAANQAECgQIBQAAAA==.Kimmispally:BAAANQADCggICAAAAA==.Kiro:BAAANQADCgYIDAAAAA==.',
Ko='Kotawar:BAAANQAECgMIAwAAAA==.Kozana:BAAANQADCgIIAgAAAA==.',
Ku='Kuraishin:BAABNQAECoEaAAIXAAcKchu1CgAeAgAXAAcKchu1CgAeAgAAAA==.Kuterr:BAAANQADCgUIBQAAAA==.',
Ky='Kyrae:BAAANQADCgYIEAABNQAECgYICgADAAAAAA==.Kyrub:BAAANQABCggICAAAAA==.',
La='Latheal:BAAANQADCgUICAAAAA==.Latto:BAAANQAECgUICwABNQAECgYICgADAAAAAA==.',
Le='Lero:BAAANQAECgIIAgAAAA==.Levatan:BAAANQAECgEIAQAAAA==.Lexoh:BAAANQAECgQIAgAAAA==.',
Li='Lilieth:BAAANQADCgUICgAAAA==.Liltankarmor:BAAANQAECgYICgAAAA==.Lindir:BAABNQAECoEeAAIJAAgKOCQSGQAEAwAJAAgKOCQSGQAEAwAAAA==.Liquid:BAAANQAECgcIEwAAAA==.Litasfk:BAAANQAECgQICAAAAA==.Liuni:BAAANQAECgYIEwAAAA==.',
Lo='Lobopeste:BAAANQAECgUIDQAAAA==.Lobotomi:BAAANQADCgYIBgAAAA==.Lorantell:BAAANQADCgUIBQAAAA==.Lorelynn:BAABNQAECoEYAAIVAAcK0xbHDQAKAgAVAAcK0xbHDQAKAgAAAA==.Loðbrók:BAAANQADCgYIDAAAAA==.',
Lu='Luci:BAAANQADCgQIBAABNQAECgYICgADAAAAAA==.Luckycritz:BAAANQAECgEIAQABNQAECgkJKgAHAJEfAA==.Lucìan:BAAANQAECgQIDgAAAA==.Luna:BAAANQAECgQIBAABNQAFFAEIAQADAAAAAA==.Lunaclair:BAAANQAECgMIBAABNQAECgcIGgAXAHIbAA==.Lunarielle:BAAANQAECgQIBgAAAA==.',
Ma='Mabrito:BAAANQAECgcIDgABNQAFFAcIEQACAOwTAA==.Macfly:BAABNQAECoEdAAIJAAcKNBr4WAAWAgAJAAcKNBr4WAAWAgAAAA==.Macneel:BAAANQADCgEIAQABNQADCgUIDQADAAAAAA==.Magicmissile:BAAANQADCgQIBAABNQAECgkJJAALAA8dAA==.Malevalous:BAAANQADCgQICQABNQAECgUIDAADAAAAAA==.Mancath:BAAANQAECgcIEAAAAA==.Maplè:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.Marlei:BAAANQAECgUICgAAAA==.Maru:BAAANQADCgcIBwABNQAECggIFQAHALkaAA==.Maxzang:BAAANQABCggIEAAAAA==.',
Me='Medenà:BAAANQADCgUICAAAAA==.Meeko:BAAANQAFFAIIAgABNQAFFAYIDAAYABgWAA==.Melfie:BAAANQAECgEIAQAAAA==.',
Mi='Midoriya:BAAANQAECgUIBQAAAA==.Mistjack:BAAANQADCggICAAAAA==.',
Mo='Moldyjack:BAAANQAECgEIAQAAAA==.Mortiis:BAAANQADCgMIAwAAAA==.',
Mu='Murderbot:BAAANQAECggIBAAAAA==.',
My='Myzyry:BAAANQAECgcJCwAAAA==.',
['Mä']='Märtyr:BAAANQADCgUIBQAAAA==.',
['Må']='Måze:BAAANQADCgIIAgAAAA==.',
['Më']='Mërlïn:BAAANQADCgYIBgAAAA==.',
Na='Nards:BAAANQAECggICAAAAA==.Nazdormu:BAAANQAECgQICQAAAA==.',
Ne='Neisen:BAAANQAECgQIBgAAAA==.Nevare:BAAANQAECgUIBgAAAA==.',
Ni='Nite:BAABNQAECoEiAAINAAkKARHugQA/AgANAAkKARHugQA/AgAAAA==.',
No='Nou:BAEANQAECggIBwABNQAECgcICwADAAAAAA==.',
Nu='Nubi:BAAANQADCgIIAgAAAA==.Nugent:BAAANQAECgYIDwAAAA==.',
Ny='Nymofthedead:BAAANQADCgcIBwAAAA==.',
Oa='Oakgrove:BAAANQADCgIIAgAAAA==.',
Ok='Okarun:BAAANQADCgEIAQAAAA==.',
On='Oneforall:BAABNQAECoElAAIZAAkKRRmlJACmAgAZAAkKRRmlJACmAgAAAA==.',
Pa='Pailly:BAAANQABCgQIBAAAAA==.Papalion:BAAANQAECgYIDAAAAA==.Paryl:BAAANQAECgUICwAAAA==.Pawbs:BAAANQADCgYIBgAAAA==.',
Pe='Peanuts:BAAANQAECggIAwAAAA==.',
Pi='Pikake:BAAANQADCgUICQAAAA==.Pinklilydrd:BAAANQADCgYIDgAAAA==.',
Pl='Plaindonut:BAABNQAECoEaAAMaAAgKsyLJCAAKAwAaAAgKsyLJCAAKAwACAAEKPRcqjABBAAAAAA==.',
Pm='Pmoney:BAAANQABCgEIAQAAAA==.',
Pr='Prissygalore:BAAANQADCgEIAQAAAA==.',
Pu='Putras:BAAANQABCgIIAgAAAA==.',
Ra='Ravenbrook:BAABNQAECoEiAAIMAAkKDyZDAADoAwAMAAkKDyZDAADoAwAAAA==.Ravus:BAAANQADCgIIAgAAAA==.Rawrr:BAAANQAECgQIBwAAAA==.Raxie:BAABNQAECoEmAAMPAAkKfRSjFgBiAgAPAAkKfRSjFgBiAgAbAAcKOhGvCAChAQAAAA==.',
Re='Reddfoxx:BAAANQAECgIIAgAAAA==.Resepuff:BAAANQADCggIEAAAAA==.',
Rh='Rhymunky:BAAANQADCgMIAwAAAA==.',
Ri='Rifthor:BAAANQADCgYIBgAAAA==.Ripmxi:BAAANQAECgYIEgAAAA==.',
Ru='Runelight:BAAANQADCgMIAwABNQAECggIGwAIADMbAA==.Runeshock:BAABNQAECoEbAAIIAAgKMxv0MABaAgAIAAgKMxv0MABaAgAAAA==.Runesummon:BAAANQADCggICAAAAA==.Rupertgiless:BAACNQAFFIELAAIFAAUKOxIyCACFAQAFAAUKOxIyCACFAQA1AAQKgSUAAgUACQpLHX8aAO0CAAUACQpLHX8aAO0CAAAA.',
Sa='Saluran:BAAANQABCgYIBgAAAA==.Sanitariums:BAAANQADCgQIBAABNQADCgUICgADAAAAAA==.Sannea:BAAANQADCgUICgABNQAECgUICgADAAAAAA==.Sarcastyx:BAAANQAECgYIEwAAAA==.Saxines:BAAANQAECgEIAQAAAA==.',
Sc='Scaliefox:BAAANQADCgQIBAABNQAECgUIDQADAAAAAA==.Schwarznacht:BAAANQADCgYICwAAAA==.',
Se='Seekndestroy:BAAANQAECgYICwAAAA==.Semperfimack:BAAANQADCgQJBAAAAA==.',
Sh='Shankkerz:BAAANQAECgcIEAAAAA==.',
Si='Simonx:BAAANQAECgEIAQAAAA==.Sindusk:BAAANQAECgYIDAAAAA==.Sitzho:BAAANQADCggIFgAAAA==.',
Sk='Skeleton:BAAANQABCgIIAgAAAA==.Skullblade:BAAANQAECgIIBAAAAA==.Skybringer:BAAANQAECgUIDAAAAA==.Skydras:BAABNQAECoEfAAMcAAgKqBlFMAARAgAcAAcK0BlFMAARAgAUAAcK2BIRSACQAQAAAA==.',
Sm='Smoothscales:BAAANQADCgUIBQAAAA==.',
So='Sonofgrumpy:BAAANQADCggIEAABNQAECgYIDwADAAAAAA==.Sorphium:BAAANQAECgUICQABNQAFFAQIBwASANAIAA==.Soxxy:BAAANQADCgEIAQABNQAECgYICgADAAAAAA==.',
Sp='Sparhawk:BAAANQADCgYIEQAAAA==.',
St='Stham:BAAANQADCgQIBQAAAA==.Stormyprissi:BAAANQADCgUIDQAAAA==.Strombjorn:BAAANQAECgEIAQAAAA==.',
Ta='Talie:BAAANQAECgEIAQAAAA==.Tasireth:BAAANQADCgMIAwAAAA==.',
Te='Tessi:BAABNQAECoEbAAMdAAcKFwf8GwDMAAAdAAUKLAn8GwDMAAANAAUKtQKsRwHGAAAAAA==.Testamental:BAAANQAECgIJAgAAAA==.',
Th='Thaloran:BAAANQADCgYIBgAAAA==.Thalrian:BAAANQAECgUIBgABNQAECggIHAALAOkeAA==.Theberes:BAAANQADCgcIBwAAAA==.Theylive:BAAANQADCgcIBwAAAA==.Thighs:BAAANQAECgQIBgAAAA==.Thordanil:BAAANQAECgEIAgAAAA==.',
Ti='Tiahina:BAAANQADCgUIBQAAAA==.',
To='Tourettes:BAAANQADCggJCAAAAA==.Toya:BAABNQAECoEWAAMSAAcKXw7hHQC8AQASAAcKXw7hHQC8AQATAAMKiQWEYQCLAAAAAA==.',
Tr='Transfurmer:BAAANQADCgMIAwAAAA==.Trevain:BAAANQADCgUIDQAAAA==.Trivia:BAAANQADCgcIIQAAAA==.Truthordare:BAAANQAECgIIBAAAAA==.',
Tu='Turtei:BAAANQADCggICAABNQAFFAUIDwAeANQlAA==.Turtl:BAACNQAFFIEPAAIeAAUK1CXxAQA1AgAeAAUK1CXxAQA1AgA1AAQKgSQAAh4ACQqxJlgAAPYDAB4ACQqxJlgAAPYDAAAA.',
Ug='Uglypetguy:BAAANQADCgEIAQAAAA==.Uglyrogue:BAAANQADCgUIBQAAAA==.',
Ul='Ulgrym:BAAANQADCgUIDgAAAA==.',
Un='Unbalancéd:BAAANQADCgUICgAAAA==.Unbroken:BAAANQABCgMIAgAAAA==.',
Va='Vaeadin:BAAANQADCggIHgAAAA==.Vahra:BAAANQADCgUICQAAAA==.Valantis:BAAANQAECgQIBAAAAA==.Valgaskav:BAAANQAFFAEIAQAAAA==.Valkor:BAAANQADCgIIAgAAAA==.Valric:BAAANQADCgYIEAAAAA==.',
Ve='Vegasnight:BAAANQADCggIEwAAAA==.Venithan:BAAANQAECgYICgAAAA==.',
Vi='Vikkrum:BAAANQADCgUJBQABNQADCgUIDQADAAAAAA==.Virani:BAAANQAECgUICAAAAA==.',
Vo='Voladro:BAAANQAECgEIAQAAAA==.Volanie:BAAANQADCgYIBgAAAA==.Volos:BAAANQAECgQICQAAAA==.Vordaman:BAABNQAECoEaAAMUAAcKMBfjPADIAQAUAAcKMBfjPADIAQAfAAEKYAV0hwAuAAAAAA==.',
Vy='Vynír:BAABNQAECoEaAAMFAAkKth/aOwBhAgAFAAgKUR/aOwBhAgAVAAQKexJIMQDsAAAAAA==.',
Wa='Waghoba:BAACNQAFFIEGAAIXAAIK0hQUAgCnAAAXAAIK0hQUAgCnAAA1AAQKgTMAAhcACQrsJMUAAMoDABcACQrsJMUAAMoDAAAA.Waito:BAAANQADCggIDQAAAA==.Wandä:BAAANQAECgUIEQAAAA==.Warborn:BAAANQADCgQIBAAAAA==.Warrionomous:BAABNQAECoEkAAILAAkKDx0bOgCmAgALAAkKDx0bOgCmAgAAAA==.Washu:BAAANQAECgYIEgAAAA==.',
We='Wetkittyy:BAAANQABCgUJCAAAAA==.',
Wh='Whobetter:BAAANQADCgYICQAAAA==.',
Wi='Winterous:BAAANQAECgQIBgAAAA==.',
Wo='Wonderbread:BAABNQAECoEcAAIEAAgK0A4bfQDNAQAEAAgK0A4bfQDNAQAAAA==.',
['Wá']='Wáshu:BAAANQADCgYIBgAAAA==.',
Xa='Xaani:BAAANQAECgIIAgAAAA==.',
Xe='Xenan:BAAANQAECgUICwAAAA==.',
Xt='Xtrolldinary:BAAANQADCgYICQAAAA==.',
Ye='Yeastmode:BAAANQAECgUIBQAAAA==.',
Yo='Yonahh:BAAANQAECgUIDAAAAA==.',
Yv='Yvelthilios:BAAANQADCgcICgAAAA==.',
Za='Zangsha:BAAANQADCgcIBwAAAA==.',
Ze='Zeebra:BAAANQAECgUIDwAAAA==.Zeg:BAABNQAECoEWAAMIAAgKmxuaJwCJAgAIAAgKmxuaJwCJAgAHAAIK1gvX2wBpAAAAAA==.Zega:BAAANQADCgcIBwAAAA==.Zegafur:BAAANQADCggIDAAAAA==.',
Zi='Zillionbucks:BAAANQAFFAEJAQAAAA==.Zillionbúcks:BAAANQAECgUICQABNQAFFAEJAQADAAAAAA==.',
Zu='Zulg:BAAANQADCgQJBAAAAA==.Zulgore:BAAANQAECgYIBgAAAA==.Zullee:BAAANQABCggIEgAAAA==.',
['Zê']='Zêddicus:BAAANQAECgYIEgAAAA==.',
['Áq']='Áquafina:BAABNQAECoEYAAINAAgKLApvvgC3AQANAAgKLApvvgC3AQAAAA==.',
['Ðö']='Ðö:BAAANQAECgUICQAAAA==.',
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
