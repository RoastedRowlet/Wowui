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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Arcane','Paladin-Protection','Warrior-Arms','Priest-Shadow','Rogue-Subtlety','Rogue-Assassination','Warlock-Destruction','Warlock-Affliction','Shaman-Elemental','Evoker-Preservation','Paladin-Holy','Priest-Discipline','Monk-Windwalker','Druid-Feral',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaril:BAAANQADCgUICwAAAQ==.',
Ab='Abrams:BAAANQAECgcIDwAAAA==.Absínthè:BAAANQABCgQIBAAAAA==.',
Ag='Agnass:BAAANQADCgQIBQAAAA==.',
Ak='Akina:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Al='Aldea:BAAANQADCgYIBgAAAA==.Alirrayiia:BAAANQAECgYIEAAAAA==.Allystar:BAAANQADCgUICQAAAA==.Alvidor:BAAANQAECgMIBAAAAA==.',
Am='Amachine:BAAANQADCggIDgABNQAECgkJHgACAOoiAA==.Amybabe:BAAANQADCgYIBgAAAA==.',
An='Anorivia:BAAANQAECgQIBwAAAA==.',
Ap='Apollossham:BAAANQAECgMIBQAAAA==.',
Ar='Arkagob:BAAANQADCgcIBwAAAA==.Arragora:BAAANQAECgQIBQAAAA==.Arrowdynamix:BAAANQAECgYIBgAAAA==.',
As='Ashyani:BAAANQADCgUIBQAAAA==.',
At='Atlan:BAAANQADCgUIBQABNQAECgMIBgABAAAAAA==.',
Ba='Babbayagga:BAAANQAECgUIBgAAAA==.Baji:BAAANQAECgUIDAAAAA==.Barefaall:BAABNQAECoEiAAMDAAkJpCNFBwBdAwADAAgJCiZFBwBdAwAEAAIJOxhTOACaAAAAAA==.Barefalls:BAAANQAECgIIAwABNQAECgkJIgADAKQjAA==.Baénoth:BAAANQABCgQIBgAAAA==.',
Be='Bergonator:BAAANQADCggIEAAAAA==.Berrodiah:BAAANQADCgcIDAABNQAECgQICAABAAAAAA==.Bestlays:BAAANQADCgUIBQAAAA==.Bettiepage:BAAANQADCgEIAQAAAA==.',
Bh='Bheiroth:BAAANQAECgQICAAAAA==.',
Bl='Blackchapell:BAAANQABCgYICQAAAA==.Blewmyload:BAAANQADCggIBgAAAA==.Bluett:BAAANQADCgIIAgAAAA==.',
Bo='Bogertus:BAAANQAECgQIDQAAAA==.',
Br='Brein:BAAANQAECgMIBAAAAA==.',
Bu='Bucketeer:BAAANQAECgMIBAAAAA==.Burzona:BAAANQABCgMIAwAAAA==.',
Ca='Cameltoetoe:BAAANQAECgEIAgAAAA==.Canaprey:BAAANQAECgQIBAAAAA==.Catshunter:BAAANQADCgYIDAAAAA==.',
Ce='Celaa:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Celebrían:BAAANQADCgUICAAAAA==.Celor:BAAANQABCgQIBgAAAA==.',
Ch='Chanka:BAAANQADCgYICQAAAA==.Chantillary:BAAANQADCgQIBQAAAA==.Charise:BAAANQADCggIGQAAAA==.Cheesy:BAAANQADCgYIDAAAAA==.Chopzullee:BAAANQADCgYIDAAAAA==.',
Ci='Cinnaz:BAAANQAECgUICgABNQAECggIFwAFAK0NAA==.',
Cl='Clortho:BAAANQAECgEIAQAAAA==.',
Co='Colbiw:BAAANQABCgIIAgAAAA==.Colljack:BAACNQAFFIEFAAIGAAMJeRwxAgAMAQAGAAMJeRwxAgAMAQA1AAQKgR8AAgYACQkbJOgAAL4DAAYACQkbJOgAAL4DAAAA.Corvath:BAAANQAECgMIBAAAAA==.',
Cr='Cryptoe:BAABNQAECoEWAAIFAAkJ+BYeNwC0AgAFAAkJ+BYeNwC0AgAAAA==.',
Da='Daedelus:BAAANQAECgIIAwAAAA==.Daglon:BAAANQADCgcIBwAAAA==.Daraedra:BAAANQADCgcIEAAAAA==.Dardolur:BAAANQADCgIIAgAAAA==.Darknìght:BAAANQADCgcIBwAAAA==.Darkslayer:BAAANQADCgMIBQAAAA==.Darkthyr:BAAANQAECgEIAQAAAA==.',
De='Deeznutticus:BAABNQAECoEYAAIHAAkJTB2NFwANAwAHAAkJTB2NFwANAwAAAA==.Demonspud:BAAANQAECgUICgAAAA==.Dersan:BAAANQADCgIIAgAAAA==.Destriant:BAAANQAECgUICwAAAA==.Devourer:BAAANQABCgMIAwAAAA==.Deylia:BAAANQADCgYIDAABNQAECggIGQAIACgPAA==.',
Dh='Dhori:BAAANQADCgQIBQAAAA==.',
Di='Dillion:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Dionin:BAAANQADCgUICgAAAA==.Disappear:BAAANQADCgYIBgABNQAECggIFwAFAK0NAA==.Dizzyhealz:BAAANQADCgMIBQAAAA==.Dizzyhuntres:BAAANQADCgYIBwAAAA==.',
Do='Dooberto:BAAANQAECgQIBQAAAA==.Dooburt:BAAANQAECgEIAQAAAA==.',
Dr='Dracaric:BAAANQADCgYIBgAAAA==.Draeca:BAAANQADCgQIBAAAAA==.Dragondznut:BAAANQADCgQIBAAAAA==.Drfrostie:BAAANQAECgQIBAAAAA==.Driatin:BAAANQAECgEIAQAAAA==.',
Du='Durø:BAAANQAECgUIDQAAAA==.',
['Dè']='Dègenerate:BAAANQAECgUIDQAAAA==.',
Ed='Eddy:BAAANQAECgYICAAAAA==.',
El='Eldumpling:BAAANQAECgMIBAAAAA==.',
Ep='Epicnym:BAAANQADCggIFgAAAA==.',
Es='Esdeath:BAAANQAECgQIBgAAAA==.',
Ex='Extenze:BAAANQAECgQIBQAAAA==.',
Fe='Feda:BAAANQADCgQIBAAAAA==.Ferryman:BAAANQAECgEIAQAAAA==.',
Fi='Findria:BAAANQADCgYIBgABNQAECgYIEwABAAAAAA==.',
Fo='Forphium:BAABNQAECoEeAAMJAAkJdxyzCAC1AgAJAAgJSR2zCAC1AgAKAAEJ5xXAQwBNAAAAAA==.',
Fr='Freespirit:BAAANQAECgcIDAABNQAFFAUICwAIANofAA==.Friarkuck:BAAANQADCgEIAQAAAA==.',
Ga='Gahlina:BAAANQADCgcIFgAAAA==.Gambaaddict:BAAANQAECgQIBAAAAA==.Garshan:BAAANQADCgYIDAAAAA==.',
Gh='Ghexn:BAAANQADCgIIAgAAAA==.',
Gi='Gilleyy:BAAANQAECgMIBQAAAA==.Gird:BAAANQAECgIIAgAAAA==.',
Gn='Gnymesis:BAAANQADCgUIBQAAAA==.',
Go='Goatmonger:BAAANQAECgEIAQAAAA==.Goinpostal:BAAANQADCgYICwAAAA==.Goldblade:BAAANQAECggICAAAAA==.Gordek:BAAANQAECgUIBwAAAA==.',
Gr='Grahra:BAAANQABCgIIBAAAAA==.Grantaron:BAAANQAECgUICgAAAA==.Grimskul:BAAANQAECgYIDwAAAA==.Grntitan:BAAANQADCgMIBgAAAA==.Gruid:BAAANQADCgYIBgAAAA==.',
Gw='Gwoohoori:BAAANQADCgQIBAAAAA==.',
Ha='Halukari:BAAANQADCggIDAABNQAECggIGQAIACgPAA==.Haléon:BAAANQAECgUIBgAAAA==.Harrin:BAAANQADCggICAAAAA==.',
He='Headshotty:BAAANQAECgMIBAAAAA==.Hellfire:BAAANQADCgYIBgAAAA==.Hezrel:BAAANQADCgYIBwAAAA==.',
Hi='Hinal:BAAANQAECgEIAQAAAA==.',
Ho='Holyenabler:BAAANQAECgUICgAAAA==.',
Hu='Hungor:BAAANQABCgQIBAAAAA==.',
Ih='Iheartbailey:BAAANQADCgQIBAAAAA==.',
Im='Imcruel:BAABNQAECoEgAAIFAAkJFiCfFABOAwAFAAkJFiCfFABOAwAAAA==.',
Io='Iorese:BAAANQADCggIDwAAAA==.',
Ir='Iriana:BAEANQADCgYIDwAAAA==.',
Ja='Jagershamer:BAAANQAECgQIBAAAAA==.Jasperine:BAAANQAECgUIBwABNQAFFAUICwAIANofAA==.',
Je='Jenneldots:BAAANQAECgQICAABNQAECgYICQABAAAAAA==.Jerce:BAAANQADCgUICQAAAA==.',
Jo='Johnnyhuntz:BAAANQADCgYICAAAAA==.',
Ju='Juacqer:BAAANQADCgQIBQAAAA==.Junamara:BAAANQAECgEIAQAAAA==.',
Ka='Kaant:BAAANQAECgMIBAAAAA==.Kaetiegh:BAAANQADCgEIAQAAAA==.Kaidevyn:BAAANQAECgQIBgAAAA==.Kat:BAAANQADCgQIBAAAAA==.',
Kb='Kbang:BAAANQAECgIIAgAAAA==.',
Ke='Keiran:BAAANQAECgUICgAAAA==.Kenix:BAAANQADCgUICAABNQADCgYICgABAAAAAA==.',
Kh='Khalnerys:BAAANQAECgEIAQAAAA==.Khaotick:BAEANQAECgcIDQABNQAECgUIBQABAAAAAA==.Khoulock:BAABNQAECoEYAAQCAAkJnB4YCQAjAwACAAkJER4YCQAjAwALAAYJ7hq7EADNAQAMAAEJJhlyGABGAAAAAA==.',
Ki='Kimmi:BAAANQAECgMIAwAAAA==.Kiro:BAAANQADCgYIBgAAAA==.',
Ko='Kotawar:BAAANQADCgMIAwAAAA==.Kozana:BAAANQADCgIIAgAAAA==.',
Kt='Kthxbye:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.',
Ku='Kuraishin:BAAANQAECgYIEAAAAA==.Kuterr:BAAANQADCgUIBQAAAA==.',
Ky='Kyrae:BAAANQADCgYIEAABNQAECgEIAQABAAAAAA==.',
La='Lagspike:BAABNQAECoEXAAIFAAgJrQ0gdADrAQAFAAgJrQ0gdADrAQAAAA==.Latheal:BAAANQADCgMIAwAAAA==.Latto:BAAANQAECgUIBQABNQAECgYICQABAAAAAA==.',
Le='Lengex:BAAANQADCgEIAQAAAA==.Lero:BAAANQAECgIIAgAAAA==.Lexoh:BAAANQAECgQIAgAAAA==.',
Li='Lilieth:BAAANQADCgQIBQAAAA==.Liltankarmor:BAAANQAECgYICQAAAA==.Lindir:BAAANQAECgYIEwAAAA==.Liquid:BAAANQAECgUICgAAAA==.Litasfk:BAAANQAECgQICAAAAA==.Liuni:BAAANQAECgQICAAAAA==.',
Lo='Lobopeste:BAAANQAECgMIBAAAAA==.Lorelynn:BAAANQAECgUICQAAAA==.Loðbrók:BAAANQADCgYIDAAAAA==.',
Lu='Luci:BAAANQADCgQIBAABNQAECgYICQABAAAAAA==.Luckycritz:BAAANQAECgEIAQABNQAECgkJGQANABUfAA==.Lucìan:BAAANQAECgMIBgAAAA==.Luna:BAAANQAECgQIBAAAAA==.Lunaclair:BAAANQAECgEIAQABNQAECgYIEAABAAAAAA==.Lunarielle:BAAANQAECgQIBgAAAA==.',
Ma='Mabrito:BAAANQAECgcIDgABNQAFFAMIBQAKANUjAA==.Macfly:BAAANQAECgYIDAAAAA==.Macneel:BAAANQADCgEIAQABNQADCgUIBQABAAAAAA==.Magicmissile:BAAANQADCgQIBAABNQAECgkJHQAHAKAbAA==.Malevalous:BAAANQADCgQICQABNQAECgIIAwABAAAAAA==.Mancath:BAAANQAECgMIAwAAAA==.Maplè:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Marlei:BAAANQAECgEIAQAAAA==.Maru:BAAANQADCgcIBwABNQAECgUIDAABAAAAAA==.',
Me='Medenà:BAAANQADCgUICAAAAA==.Meeko:BAAANQAECgcIBwABNQAFFAUICQAOAFYYAA==.Melfie:BAAANQADCgQIBAAAAA==.',
Mi='Midoriya:BAAANQADCgcICQAAAA==.Mistjack:BAAANQADCggICAAAAA==.',
Mo='Moldyjack:BAAANQAECgEIAQAAAA==.Mortiis:BAAANQADCgMIAwAAAA==.',
My='Myzyry:BAAANQAECgIIBAAAAA==.',
['Må']='Måze:BAAANQADCgIIAgAAAA==.',
['Më']='Mërlïn:BAAANQADCgYIBgAAAA==.',
Na='Nards:BAAANQAECggICAAAAA==.Nazdormu:BAAANQAECgIIAgAAAA==.',
Ne='Neisen:BAAANQAECgIIAgAAAA==.Nevare:BAAANQADCgYIBgAAAA==.',
Nu='Nubi:BAAANQADCgIIAgAAAA==.Nugent:BAAANQAECgUICQAAAA==.',
Oa='Oakgrove:BAAANQADCgIIAgAAAA==.',
On='Oneforall:BAABNQAECoEWAAIPAAgJFBiXIABiAgAPAAgJFBiXIABiAgAAAA==.',
Pa='Pailly:BAAANQABCgQIBAAAAA==.Papalion:BAAANQAECgIIAwAAAA==.Paryl:BAAANQAECgMIAwAAAA==.Pawbs:BAAANQADCgYIBgAAAA==.',
Pi='Pikake:BAAANQADCgQIBAAAAA==.Pinklilydrd:BAAANQADCgYICQAAAA==.',
Pl='Plaindonut:BAAANQAECgUICgAAAA==.',
Pr='Prissygalore:BAAANQADCgEIAQAAAA==.',
Pu='Putras:BAAANQABCgIIAgAAAA==.',
Ra='Ravenbrook:BAAANQAECgcIEgAAAA==.Ravus:BAAANQADCgIIAgAAAA==.Rawrr:BAAANQAECgEIAQAAAA==.Raxie:BAABNQAECoEZAAMIAAgJKA/DFAAXAgAIAAgJKA/DFAAXAgAQAAYJlxKIBwB7AQAAAA==.',
Re='Reddfoxx:BAAANQADCgUIBwAAAA==.Resepuff:BAAANQADCggIEAAAAA==.',
Rh='Rhymunky:BAAANQADCgMIAwAAAA==.',
Ri='Rifthor:BAAANQADCgYIBgAAAA==.Ripmxi:BAAANQAECgQIBwAAAA==.',
Ru='Runelight:BAAANQADCgMIAwABNQAECgcIDwABAAAAAA==.Runeshock:BAAANQAECgcIDwAAAA==.Rupertgiless:BAABNQAECoEeAAICAAkJNRsmDgDwAgACAAkJNRsmDgDwAgAAAA==.',
Sa='Saluran:BAAANQABCgYIBgAAAA==.Sannea:BAAANQADCgUICgABNQAECgEIAQABAAAAAA==.Sarcastyx:BAAANQAECgUIBwAAAA==.Saxines:BAAANQADCggIFgAAAA==.',
Sc='Schwarznacht:BAAANQADCgYICwAAAA==.',
Se='Seekndestroy:BAAANQAECgIIAwAAAA==.',
Sh='Shankkerz:BAAANQAECgMIAwAAAA==.',
Si='Sindusk:BAAANQAECgYIDAAAAA==.Sitzho:BAAANQADCgMIBQAAAA==.',
Sk='Skeleton:BAAANQABCgIIAgAAAA==.Skullblade:BAAANQAECgEIAQAAAA==.Skybringer:BAAANQADCggIJgAAAA==.Skydras:BAAANQAECgYIDwAAAA==.',
Sm='Smoothscales:BAAANQADCgUIBQAAAA==.',
So='Sonofgrumpy:BAAANQADCggIEAABNQAECgQIBAABAAAAAA==.Sorphium:BAAANQAECgUICQABNQAECgkJHgAJAHccAA==.Soxxy:BAAANQADCgEIAQABNQAECgYICQABAAAAAA==.',
Sp='Sparhawk:BAAANQADCgYIEQAAAA==.',
St='Stormyprissi:BAAANQADCgQIBAAAAA==.Strombjorn:BAAANQAECgEIAQAAAA==.',
Ta='Talie:BAAANQABCgQIBAAAAA==.Tasireth:BAAANQADCgMIAwAAAA==.',
Te='Tessi:BAAANQAECgYIEwAAAA==.Testamental:BAAANQAECgIIAgAAAA==.',
Th='Thalrian:BAAANQAECgEIAQABNQAECgUIDQABAAAAAA==.Theylive:BAAANQADCgcIBwAAAA==.Thighs:BAAANQAECgQIBgAAAA==.',
Ti='Tiahina:BAAANQADCgUIBQAAAA==.',
To='Tourettes:BAAANQADCggICAAAAA==.Toya:BAAANQAECgUIBwAAAA==.',
Tr='Trevain:BAAANQADCgQIBAABNQADCgUIBQABAAAAAA==.Trivia:BAAANQADCgcIFgAAAA==.Truthordare:BAAANQAECgEIAQAAAA==.',
Tu='Turtei:BAAANQADCggICAABNQAFFAMIBQARABAkAA==.Turtl:BAACNQAFFIEFAAIRAAMJECTEAgBJAQARAAMJECTEAgBJAQA1AAQKgR4AAhEACQmxJg4AAA8EABEACQmxJg4AAA8EAAAA.',
Ul='Ulgrym:BAAANQADCgQIBQAAAA==.',
Un='Unbalancéd:BAAANQADCgUICQAAAA==.Unbroken:BAAANQABCgMIAgAAAA==.',
Va='Vaeadin:BAAANQADCgcIFgAAAA==.Vahra:BAAANQADCgMIBAAAAA==.Valantis:BAAANQAECgQIBAAAAA==.Valgaskav:BAAANQAECgQIBwAAAA==.Valkor:BAAANQADCgIIAgAAAA==.Valric:BAAANQADCgYICgAAAA==.',
Ve='Vegasnight:BAAANQADCgYICwAAAA==.Venithan:BAAANQAECgEIAQAAAA==.',
Vi='Vikkrum:BAAANQADCgUIBQAAAA==.Virani:BAAANQAECgUIBQAAAA==.',
Vo='Volanie:BAAANQADCgYIBgAAAA==.Volos:BAAANQAECgEIAQAAAA==.Vordaman:BAAANQAECgUIDQAAAA==.',
Vy='Vynír:BAAANQAFFAEIAQAAAA==.',
Wa='Waghoba:BAABNQAECoEhAAISAAkJeCSVAADAAwASAAkJeCSVAADAAwAAAA==.Wandä:BAAANQAECgQICAAAAA==.Warborn:BAAANQADCgQIBAAAAA==.Warrionomous:BAABNQAECoEdAAIHAAkJoBt/IADTAgAHAAkJoBt/IADTAgAAAA==.Washu:BAAANQAECgUIBwAAAA==.',
We='Wetkittyy:BAAANQABCgUICAAAAA==.',
Wh='Whobetter:BAAANQADCgYICQAAAA==.',
Wi='Winterous:BAAANQAECgIIAgAAAA==.',
Wo='Wonderbread:BAAANQAECgYIDQAAAA==.',
Xa='Xaani:BAAANQAECgIIAgAAAA==.',
Xe='Xenan:BAAANQAECgIIAgAAAA==.',
Xt='Xtrolldinary:BAAANQADCgYICQAAAA==.',
Ye='Yeastmode:BAAANQADCgQIBAAAAA==.',
Yo='Yonahh:BAAANQAECgMIBAAAAA==.',
Yv='Yvelthilios:BAAANQADCgcICgAAAA==.',
Ze='Zeebra:BAAANQAECgQIBQAAAA==.Zeg:BAAANQAECgQICQAAAA==.Zega:BAAANQADCgcIBwAAAA==.Zegafur:BAAANQADCgQIBAAAAA==.',
Zi='Zillionbucks:BAAANQAFFAEIAQAAAA==.Zillionbúcks:BAAANQAECgUICQABNQAFFAEIAQABAAAAAA==.',
Zu='Zulgore:BAAANQAECgYIBgAAAA==.',
['Zê']='Zêddicus:BAAANQAECgMIBwAAAA==.',
['Áq']='Áquafina:BAAANQAECgUICAAAAA==.',
['Ðö']='Ðö:BAAANQAECgMIAwAAAA==.',
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
