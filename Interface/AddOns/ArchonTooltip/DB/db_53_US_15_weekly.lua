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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Warlock-Demonology','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Arms','Warrior-Fury','Mage-Arcane','Paladin-Protection','Priest-Shadow','DemonHunter-Devourer','Warrior-Protection','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Unholy','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Shaman-Elemental','Druid-Balance','Evoker-Preservation','Paladin-Holy','Priest-Discipline','Shaman-Restoration','DeathKnight-Blood','Mage-Frost','Monk-Windwalker','DeathKnight-Frost',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaril:BAAANQADCgUJDwAAAQ==.',
Ab='Abrams:BAAANQAECggIEAAAAA==.Absínthè:BAAANQABCgQIBAAAAA==.',
Ag='Agnass:BAAANQADCgQJCQAAAA==.',
Ak='Akina:BAAANQADCggIDwABNQAECgQJBQABAAAAAA==.',
Al='Aldea:BAAANQADCgYIBgAAAA==.Alirrayiia:BAABNQAECoEVAAICAAcKvQ2ldACgAQACAAcKvQ2ldACgAQAAAA==.Allystar:BAAANQADCgUJCQAAAA==.Alvidor:BAAANQAECgQJCAAAAA==.',
Am='Amachine:BAAANQADCggIDgABNQAFFAQJCQADADkjAA==.Amethen:BAAANQAECgMIAwAAAA==.Amybabe:BAAANQAECgIIAgAAAA==.',
An='Anorivia:BAAANQAECgUJDAAAAA==.',
Ap='Apolloerosp:BAAANQADCgcIBwABNQAECgUICwABAAAAAA==.Apollossham:BAAANQAECgUICwAAAA==.',
Ar='Arkagob:BAAANQADCgcIBwAAAA==.Arragora:BAAANQAECgQIBQAAAA==.Arrowdynamix:BAAANQAECgYIBwAAAA==.',
As='Ashyani:BAAANQADCgUIBQAAAA==.',
At='Atlan:BAAANQADCgUIBQABNQAECgQICgABAAAAAA==.',
Au='Aurnhadon:BAAANQABCggIDAAAAA==.',
Ba='Babbayagga:BAAANQAECgUICAAAAA==.Baji:BAAANQAECgYJDQAAAA==.Barefaall:BAACNQAFFIEHAAMEAAYKbhCXAgC6AQAEAAUKJxGXAgC6AQAFAAEK1QxeFQBJAAA1AAQKgSoAAwQACQrDIzEJAGMDAAQACAotJjEJAGMDAAUAAgo7GBxFAJMAAAAA.Barefalls:BAAANQAECgIIAwABNQAFFAYIBwAEAG4QAA==.Baénoth:BAAANQABCgQIBwAAAA==.',
Be='Bergonator:BAAANQADCggIFgAAAA==.Berrodiah:BAAANQADCgcIDQABNQAECgQJDAABAAAAAA==.Bestlays:BAAANQADCgUIBQAAAA==.Bettiepage:BAAANQADCgEIAQAAAA==.',
Bh='Bheiroth:BAAANQAECgUJDQAAAA==.',
Bl='Blackchapell:BAAANQABCgYICQAAAA==.Blewmyload:BAAANQADCggIBgAAAA==.Bluett:BAAANQADCgQJBgAAAA==.',
Bo='Bogertus:BAABNQAECoEVAAMGAAgKnyITGQAhAwAGAAgKnyITGQAhAwAHAAEKDiEFHABfAAAAAA==.',
Br='Brein:BAAANQAECgQJCAAAAA==.',
Bu='Bucketeer:BAAANQAECgUICQAAAA==.Burzona:BAAANQABCgMIAwAAAA==.',
Ca='Cameltoetoe:BAAANQAECgEIAgAAAA==.Canaprey:BAAANQAECgUICQAAAA==.Catshunter:BAAANQADCgYIDAAAAA==.',
Ce='Celaa:BAAANQADCgQIBAABNQAECgQJBQABAAAAAA==.Celebrían:BAAANQADCgUJCAAAAA==.Celor:BAAANQABCgQIBgAAAA==.',
Ch='Chanka:BAAANQADCgYICQAAAA==.Chantillary:BAAANQADCgQJCQAAAA==.Charise:BAAANQAECgMJAwAAAA==.Cheesy:BAAANQADCgYIDAAAAA==.Chopzullee:BAAANQADCgYIDAAAAA==.',
Ci='Cinnaz:BAAANQAECgUJCgABNQAECggIHgAIANARAA==.',
Cl='Clortho:BAAANQAECgIJAwAAAA==.',
Co='Colbiw:BAAANQABCgIIAwAAAA==.Colljack:BAACNQAFFIEKAAIJAAUKIB1rAQDRAQAJAAUKIB1rAQDRAQA1AAQKgSIAAgkACQpJJH8BALIDAAkACQpJJH8BALIDAAAA.Corvath:BAAANQAECgQJBQAAAA==.',
Cr='Cryptoe:BAABNQAECoEfAAIIAAkKjRsFMAD/AgAIAAkKjRsFMAD/AgAAAA==.',
Da='Daedelus:BAAANQAECgIIBQAAAA==.Daglon:BAAANQADCgcIBwAAAA==.Daraedra:BAAANQADCgcIFgAAAA==.Dardolur:BAAANQADCgIIAgAAAA==.Darknìght:BAAANQADCgcJDQAAAA==.Darkslayer:BAAANQADCgMIBQAAAA==.Darkthyr:BAAANQAECgQIBQAAAA==.',
De='Deeznutticus:BAACNQAFFIEFAAIGAAIKnhg8FACwAAAGAAIKnhg8FACwAAA1AAQKgR0AAgYACQrUHcQfAPsCAAYACQrUHcQfAPsCAAAA.Demonspud:BAAANQAECgYIEAAAAA==.Dersan:BAAANQADCgIIAgAAAA==.Destriant:BAAANQAECgYIEQAAAA==.Devourer:BAAANQABCgMIAwAAAA==.Dewburt:BAAANQADCgUJBQAAAA==.Deylia:BAAANQADCgYIDAABNQAECggIIQAKAJwTAA==.',
Dh='Dhori:BAAANQADCgQJCQAAAA==.',
Di='Dillion:BAAANQAECgEIAQABNQAECgMJBgABAAAAAA==.Dionin:BAAANQADCgUICgAAAA==.Disappear:BAAANQADCgYICgABNQAECggIHgAIANARAA==.Dizzyhealz:BAAANQADCgMIBQAAAA==.Dizzyhuntres:BAAANQADCgYIBwAAAA==.',
Do='Dooberto:BAAANQAECgUIBgAAAA==.Dooburt:BAAANQAECgEIAQAAAA==.',
Dr='Dracaric:BAAANQADCgYIBgAAAA==.Draeca:BAAANQADCgQJCAAAAA==.Dragondznut:BAAANQADCgUIBgAAAA==.Drfrostie:BAAANQAECgUIBQAAAA==.Driatin:BAAANQAECgEIAQAAAA==.',
Du='Durø:BAABNQAECoEUAAILAAcK6B5UEwCLAgALAAcK6B5UEwCLAgAAAA==.',
['Dè']='Dègenerate:BAABNQAECoEVAAIMAAgKsSFgAwAMAwAMAAgKsSFgAwAMAwAAAA==.',
Ed='Eddy:BAAANQAECgcIDQAAAA==.',
Ei='Einherjarr:BAAANQADCgQJBAAAAA==.',
El='Eldumpling:BAAANQAECgMIBAAAAA==.',
Ep='Epicnym:BAAANQAECgIJAgAAAA==.',
Es='Esdeath:BAAANQAECgQJBgAAAA==.',
Ex='Extenze:BAAANQAECgQJCQAAAA==.',
Fe='Feda:BAAANQADCgQIBAAAAA==.Ferryman:BAAANQAECgIIAwAAAA==.',
Fi='Findria:BAAANQADCgYIBgABNQAECggIGwAEAOUiAA==.',
Fo='Forphium:BAABNQAECoEfAAMNAAkKdxwaCwCYAgANAAgKSR0aCwCYAgAOAAEK5xWrWQBIAAAAAA==.',
Fr='Fredolf:BAAANQADCgQJBAAAAA==.Freespirit:BAAANQAECgcIDAABNQAFFAYIEQAKANkeAA==.Friarkuck:BAAANQADCgEIAQAAAA==.',
Ga='Gahlina:BAAANQADCgcJFgAAAA==.Gambaaddict:BAAANQAECgUJCQAAAA==.Garshan:BAAANQAECgIJAgAAAA==.',
Gh='Ghexn:BAAANQADCgIIAgAAAA==.',
Gi='Gilleyy:BAAANQAECgMIBQAAAA==.Gird:BAAANQAECgUJBwAAAA==.Girdlock:BAAANQADCgIJAgAAAA==.',
Gn='Gnymesis:BAAANQADCgUIBQAAAA==.',
Go='Goatmonger:BAAANQAECgQIBQAAAA==.Goinpostal:BAAANQADCgYICwAAAA==.Goldblade:BAAANQAECggICAAAAA==.Gordek:BAAANQAECgYJDQAAAA==.',
Gr='Grahra:BAAANQABCgIIBQAAAA==.Grantaron:BAAANQAECgYIEAAAAA==.Grimskul:BAABNQAECoEWAAIPAAgKYRIPKwARAgAPAAgKYRIPKwARAgAAAA==.Grntitan:BAAANQADCgQJCgAAAA==.Gruid:BAAANQADCgYIBgAAAA==.',
Gw='Gwoohoori:BAAANQADCgQIBAAAAA==.',
Ha='Halukari:BAAANQADCggIDAABNQAECggIIQAKAJwTAA==.Haléon:BAAANQAECgUJBgAAAA==.Hamnier:BAAANQABCgMJBAAAAA==.Harrin:BAAANQADCggICAAAAA==.',
He='Headshotty:BAAANQAECgQJCAAAAA==.Hellfire:BAAANQADCgYIBgAAAA==.Hezrel:BAAANQAECgIIAgAAAA==.',
Hi='Hinal:BAAANQAECgMJBAAAAA==.',
Ho='Holyenabler:BAAANQAECgYIEAAAAA==.',
Hu='Hungor:BAAANQABCgQIBAAAAA==.',
Ih='Iheartbailey:BAAANQADCgQIBAAAAA==.',
Im='Imcruel:BAACNQAFFIEIAAIIAAMK2RuUFgAMAQAIAAMK2RuUFgAMAQA1AAQKgSUAAggACQqRIA8cAEYDAAgACQqRIA8cAEYDAAAA.',
Io='Iorese:BAAANQADCggIDwAAAA==.',
Ir='Iriana:BAEANQADCgYIGwAAAA==.',
Ja='Jackiegan:BAAANQADCgEJAQAAAA==.Jagershamer:BAAANQAECgUJBQAAAA==.Jasperine:BAAANQAECgUIBwABNQAFFAYIEQAKANkeAA==.',
Je='Jenneldots:BAAANQAECgQICwABNQAECgYICgABAAAAAA==.Jerce:BAAANQADCgUICQAAAA==.',
Jo='Johnnyhuntz:BAAANQADCgYICAAAAA==.',
Ju='Juacqer:BAAANQADCgQJCQAAAA==.Junamara:BAAANQAECgQIBQAAAA==.',
Ka='Kaant:BAAANQAECgQJCAAAAA==.Kaetiegh:BAAANQADCgQJBQAAAA==.Kaidevyn:BAAANQAECgUJCwAAAA==.Kat:BAAANQADCgQICAAAAA==.',
Kb='Kbang:BAAANQAECgIIAgAAAA==.',
Ke='Keiran:BAAANQAECgYJEAAAAA==.Kenix:BAAANQADCgUICAABNQADCgYICgABAAAAAA==.',
Kh='Khalnerys:BAAANQAECgQIBQAAAA==.Khaotick:BAEBNQAECoEZAAQDAAkKqxDmZwCOAQADAAcKmBHmZwCOAQAQAAQK7AwANwDCAAARAAEKJg0kJAAwAAABNQAECgYJCgABAAAAAA==.Khoulock:BAABNQAECoEhAAQDAAkKBB/0DQAcAwADAAkKsR70DQAcAwAQAAYK7hrMEgDDAQARAAEKJhk5HgBCAAAAAA==.',
Ki='Kimmi:BAAANQAECgMJBAAAAA==.Kimmispally:BAAANQADCggICAAAAA==.Kiro:BAAANQADCgYIDAAAAA==.',
Ko='Kotawar:BAAANQADCgMJAwAAAA==.Kozana:BAAANQADCgIIAgAAAA==.',
Ku='Kuraishin:BAABNQAECoEYAAISAAcKchvzBwA1AgASAAcKchvzBwA1AgAAAA==.Kuterr:BAAANQADCgUIBQAAAA==.',
Ky='Kyrae:BAAANQADCgYIEAABNQAECgUJBQABAAAAAA==.',
La='Latheal:BAAANQADCgMIAwAAAA==.Latto:BAAANQAECgUICgABNQAECgYICgABAAAAAA==.',
Le='Lero:BAAANQAECgIIAgAAAA==.Levatan:BAAANQAECgEIAQAAAA==.Lexoh:BAAANQAECgQIAgAAAA==.',
Li='Lilieth:BAAANQADCgQIBQAAAA==.Liltankarmor:BAAANQAECgYICgAAAA==.Lindir:BAABNQAECoEbAAIEAAgK5SIlFgD1AgAEAAgK5SIlFgD1AgAAAA==.Liquid:BAAANQAECgcJEAAAAA==.Litasfk:BAAANQAECgQICAAAAA==.Liuni:BAAANQAECgUJDQAAAA==.',
Lo='Lobopeste:BAAANQAECgQJCAAAAA==.Lorantell:BAAANQADCgQJBAAAAA==.Lorelynn:BAAANQAECgYIDgAAAA==.Loðbrók:BAAANQADCgYIDAAAAA==.',
Lu='Luci:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.Luckycritz:BAAANQAECgEIAQABNQAECgkJIgATABUfAA==.Lucìan:BAAANQAECgQICgAAAA==.Luna:BAAANQAECgQIBAAAAA==.Lunaclair:BAAANQAECgIJAgABNQAECgcJGAASAHIbAA==.Lunarielle:BAAANQAECgQIBgAAAA==.',
Ma='Mabrito:BAAANQAECgcIDgABNQAFFAUICwAUAEkSAA==.Macfly:BAAANQAECgYIEgAAAA==.Macneel:BAAANQADCgEIAQABNQADCgUJBQABAAAAAA==.Magicmissile:BAAANQADCgQIBAABNQAECgkJIgAGAA8dAA==.Malevalous:BAAANQADCgQICQABNQAECgUJCAABAAAAAA==.Mancath:BAAANQAECgYJCQAAAA==.Maplè:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Marlei:BAAANQAECgQJBQAAAA==.Maru:BAAANQADCgcIBwABNQAECgYJDQABAAAAAA==.',
Me='Medenà:BAAANQADCgUICAAAAA==.Meeko:BAAANQAFFAIIAgABNQAFFAYJCwAVAOEVAA==.Melfie:BAAANQADCgQIBAAAAA==.',
Mi='Midoriya:BAAANQADCgcICQAAAA==.Mistjack:BAAANQADCggICAAAAA==.',
Mo='Moldyjack:BAAANQAECgEIAQAAAA==.Mortiis:BAAANQADCgMIAwAAAA==.',
My='Myzyry:BAAANQAECgcJCwAAAA==.',
['Må']='Måze:BAAANQADCgIIAgAAAA==.',
['Më']='Mërlïn:BAAANQADCgYIBgAAAA==.',
Na='Nards:BAAANQAECggICAAAAA==.Nazdormu:BAAANQAECgQJBgAAAA==.',
Ne='Neisen:BAAANQAECgUIBQAAAA==.Nevare:BAAANQADCgYIBgAAAA==.',
Ni='Nite:BAABNQAECoEeAAIIAAgK0BFkfgAcAgAIAAgK0BFkfgAcAgAAAA==.',
No='Nou:BAEANQAECggIBwABNQAECgYJCgABAAAAAA==.',
Nu='Nubi:BAAANQADCgIIAgAAAA==.Nugent:BAAANQAECgUJDgAAAA==.',
Ny='Nymofthedead:BAAANQADCgcIBwAAAA==.',
Oa='Oakgrove:BAAANQADCgIIAgAAAA==.',
On='Oneforall:BAABNQAECoEdAAIWAAgKWhluKgBcAgAWAAgKWhluKgBcAgAAAA==.',
Pa='Pailly:BAAANQABCgQIBAAAAA==.Papalion:BAAANQAECgIJBQAAAA==.Paryl:BAAANQAECgMJBgAAAA==.Pawbs:BAAANQADCgYIBgAAAA==.',
Pe='Peanuts:BAAANQAECggJAgAAAA==.',
Pi='Pikake:BAAANQADCgUICQAAAA==.Pinklilydrd:BAAANQADCgYJDQAAAA==.',
Pl='Plaindonut:BAAANQAECgcJEAAAAA==.',
Pr='Prissygalore:BAAANQADCgEIAQAAAA==.',
Pu='Putras:BAAANQABCgIIAgAAAA==.',
Ra='Ravenbrook:BAABNQAECoEXAAIHAAkKVyVMAADMAwAHAAkKVyVMAADMAwAAAA==.Ravus:BAAANQADCgIIAgAAAA==.Rawrr:BAAANQAECgIJAwAAAA==.Raxie:BAABNQAECoEhAAMKAAgKnBN6FwAuAgAKAAgKnBN6FwAuAgAXAAYKlxIzCQBrAQAAAA==.',
Re='Reddfoxx:BAAANQADCgUIBwAAAA==.Reexi:BAAANQABCgEIAgAAAA==.Resepuff:BAAANQADCggIEAAAAA==.',
Rh='Rhymunky:BAAANQADCgMIAwAAAA==.',
Ri='Rifthor:BAAANQADCgYIBgAAAA==.Ripmxi:BAAANQAECgUJDAAAAA==.',
Ru='Runelight:BAAANQADCgMIAwABNQAECggIGAAYAOAXAA==.Runeshock:BAABNQAECoEYAAIYAAgK4BeKNQAeAgAYAAgK4BeKNQAeAgAAAA==.Runesummon:BAAANQADCggJCAAAAA==.Rupertgiless:BAACNQAFFIEHAAIDAAQKyRBnBwBHAQADAAQKyRBnBwBHAQA1AAQKgSIAAgMACQrQHNgTAPMCAAMACQrQHNgTAPMCAAAA.',
Sa='Saluran:BAAANQABCgYIBgAAAA==.Sanitariums:BAAANQADCgQJBAABNQADCgUICQABAAAAAA==.Sannea:BAAANQADCgUICgABNQAECgQJBQABAAAAAA==.Sarcastyx:BAAANQAECgYJDQAAAA==.Saxines:BAAANQAECgEIAQAAAA==.',
Sc='Scaliefox:BAAANQADCgQIBAABNQAECgQJCAABAAAAAA==.Schwarznacht:BAAANQADCgYICwAAAA==.',
Se='Seekndestroy:BAAANQAECgIIBQAAAA==.Semperfimack:BAAANQADCgQJBAAAAA==.',
Sh='Shankkerz:BAAANQAECgYICQAAAA==.',
Si='Sindusk:BAAANQAECgYIDAAAAA==.Sitzho:BAAANQADCggJDgAAAA==.',
Sk='Skeleton:BAAANQABCgIIAgAAAA==.Skullblade:BAAANQAECgEJAgAAAA==.Skybringer:BAAANQAECgUIBQAAAA==.Skydras:BAABNQAECoEYAAMPAAcKnhXVNADSAQAPAAcK2BLVNADSAQAZAAMKAxd3bwCyAAAAAA==.',
Sm='Smoothscales:BAAANQADCgUIBQAAAA==.',
So='Sonofgrumpy:BAAANQADCggIEAABNQAECgUICQABAAAAAA==.Sorphium:BAAANQAECgUICQABNQAECgkJHwANAHccAA==.Soxxy:BAAANQADCgEIAQABNQAECgYICgABAAAAAA==.',
Sp='Sparhawk:BAAANQADCgYIEQAAAA==.',
St='Stham:BAAANQADCgQJBQAAAA==.Stormyprissi:BAAANQADCgQJCAAAAA==.Strombjorn:BAAANQAECgEIAQAAAA==.',
Ta='Talie:BAAANQABCgYJCAAAAA==.Tasireth:BAAANQADCgMIAwAAAA==.',
Te='Tessi:BAABNQAECoEZAAMaAAcKagXcHACXAAAIAAUKtQKFIgHNAAAaAAQK+wfcHACXAAAAAA==.Testamental:BAAANQAECgIJAgAAAA==.',
Th='Thalrian:BAAANQAECgEIAQABNQAECggIFQAGAO0dAA==.Theylive:BAAANQADCgcIBwAAAA==.Thighs:BAAANQAECgQIBgAAAA==.Thordanil:BAAANQAECgEJAQAAAA==.',
Ti='Tiahina:BAAANQADCgUIBQAAAA==.',
To='Tourettes:BAAANQADCggJCAAAAA==.Toya:BAAANQAECgYIDgAAAA==.',
Tr='Transfurmer:BAAANQADCgMJAwAAAA==.Trevain:BAAANQADCgQJCAABNQADCgUJBQABAAAAAA==.Trivia:BAAANQADCgcIHAAAAA==.Truthordare:BAAANQAECgIIAwAAAA==.',
Tu='Turtei:BAAANQADCggICAABNQAFFAUICgAbANIiAA==.Turtl:BAACNQAFFIEKAAIbAAUK0iKYAQAWAgAbAAUK0iKYAQAWAgA1AAQKgSEAAhsACQqxJi0AAAYEABsACQqxJi0AAAYEAAAA.',
Ul='Ulgrym:BAAANQADCgQJCQAAAA==.',
Un='Unbalancéd:BAAANQADCgUICQAAAA==.Unbroken:BAAANQABCgMIAgAAAA==.',
Va='Vaeadin:BAAANQADCgcJFgAAAA==.Vahra:BAAANQADCgMIBAAAAA==.Valantis:BAAANQAECgQIBAAAAA==.Valgaskav:BAAANQAECgUIDAAAAA==.Valkor:BAAANQADCgIIAgAAAA==.Valric:BAAANQADCgYIEAAAAA==.',
Ve='Vegasnight:BAAANQADCggIEwAAAA==.Venithan:BAAANQAECgUJBQAAAA==.',
Vi='Vikkrum:BAAANQADCgUJBQAAAA==.Virani:BAAANQAECgUICAAAAA==.',
Vo='Volanie:BAAANQADCgYJBgAAAA==.Volos:BAAANQAECgQIBQAAAA==.Vordaman:BAABNQAECoEUAAMPAAcKtRKXMwDZAQAPAAcKtRKXMwDZAQAcAAEKYAX2bgAyAAAAAA==.',
Vy='Vynír:BAAANQAFFAEJAQAAAA==.',
Wa='Waghoba:BAABNQAECoEpAAISAAkKiyTXAAC3AwASAAkKiyTXAAC3AwAAAA==.Waito:BAAANQADCgUJBQAAAA==.Wandä:BAAANQAECgQJDAAAAA==.Warborn:BAAANQADCgQIBAAAAA==.Warrionomous:BAABNQAECoEiAAIGAAkKDx1/KwC+AgAGAAkKDx1/KwC+AgAAAA==.Washu:BAAANQAECgYJDQAAAA==.',
We='Wetkittyy:BAAANQABCgUJCgAAAA==.',
Wh='Whobetter:BAAANQADCgYICQAAAA==.',
Wi='Winterous:BAAANQAECgQJBgAAAA==.',
Wo='Wonderbread:BAABNQAECoEVAAICAAgKbw2IZQDMAQACAAgKbw2IZQDMAQAAAA==.Woobie:BAAANQABCgEIAQAAAA==.',
Xa='Xaani:BAAANQAECgIIAgAAAA==.',
Xe='Xenan:BAAANQAECgQJBgAAAA==.',
Xt='Xtrolldinary:BAAANQADCgYICQAAAA==.',
Ye='Yeastmode:BAAANQADCgYIBgAAAA==.',
Yo='Yonahh:BAAANQAECgMJBwAAAA==.',
Yv='Yvelthilios:BAAANQADCgcICgAAAA==.',
Ze='Zeebra:BAAANQAECgUJCgAAAA==.Zeg:BAAANQAECgUJDgAAAA==.Zega:BAAANQADCgcJBwAAAA==.Zegafur:BAAANQADCgQJBAAAAA==.',
Zi='Zillionbucks:BAAANQAFFAEJAQAAAA==.Zillionbúcks:BAAANQAECgUICQABNQAFFAEJAQABAAAAAA==.',
Zu='Zulg:BAAANQADCgQJBAAAAA==.Zulgore:BAAANQAECgYIBgAAAA==.',
['Zê']='Zêddicus:BAAANQAECgUJDAAAAA==.',
['Áq']='Áquafina:BAAANQAECgcIDwAAAA==.',
['Ðö']='Ðö:BAAANQAECgUIBQAAAA==.',
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
