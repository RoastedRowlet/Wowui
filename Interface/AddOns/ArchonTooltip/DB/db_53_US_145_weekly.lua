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

local lookup = {'Unknown-Unknown','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Devourer','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Druid-Balance','Druid-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Elemental','Shaman-Restoration','Evoker-Preservation','Druid-Feral','DemonHunter-Havoc','DeathKnight-Frost','Shaman-Enhancement','Priest-Holy','Priest-Discipline','Mage-Arcane','Mage-Frost','DeathKnight-Blood',}
local provider = {region='US',realm='Lothar',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aaliara:BAAANQAECgMIAwAAAA==.',
Ac='Ackreser:BAAANQADCggIDAAAAA==.',
Ae='Aeven:BAAANQADCgEIAQABNQAECggIEAABAAAAAA==.',
Ai='Aidan:BAACNQAFFIESAAMCAAgJriUDAAAVAwACAAcJmSUDAAAVAwADAAEJQibcAQB0AAA1AAQKgRkAAwIACQn7JeQAAL4DAAIACQn7JeQAAL4DAAMAAgmaJgcPAOQAAAAA.Aidhan:BAABNQAECoEXAAIEAAkJBySqAgCIAwAEAAkJBySqAgCIAwABNQAFFAgIEgACAK4lAA==.Aileron:BAAANQAECgcIEAAAAA==.Airlin:BAAANQADCgQIBAAAAA==.',
Al='Alcore:BAAANQADCgMIAwAAAA==.Aldrigor:BAAANQAECgIIAgAAAA==.Alett:BAAANQADCgcIDgAAAA==.Alivathus:BAAANQAECgcIDQAAAA==.Alsong:BAAANQADCgUIDAAAAA==.Alvart:BAAANQADCggIDQAAAA==.',
Am='Ambervoid:BAAANQAECgMIBQAAAA==.',
Ar='Arbark:BAABNQAECoEXAAQFAAkJ3SM7AAB3AwAFAAgJjiU7AAB3AwAGAAgJXiAmCgDKAgAHAAQJRR5+GwBLAQAAAA==.Archdemon:BAAANQADCgUIBQAAAA==.Arcnfrost:BAAANQADCgQIBAAAAA==.Ardone:BAAANQABCgIIAgAAAA==.Arkadis:BAAANQADCgMIAgAAAA==.Armina:BAAANQAECgYIBgAAAA==.Arrothin:BAAANQABCgYICgAAAA==.',
As='Asdanoth:BAAANQADCggICwAAAA==.Ashenbrawl:BAAANQAECgcIDQAAAA==.Ashenclaw:BAAANQADCgcIEAAAAA==.Aspinks:BAAANQADCggIDgABNQAECgYICgABAAAAAA==.',
Au='Auxie:BAAANQAECgUIBwAAAA==.',
Av='Avatipup:BAAANQADCggICgAAAA==.',
Aw='Aweinon:BAAANQADCgQIBAAAAA==.',
Ay='Aydin:BAACNQAFFIEFAAIIAAQJcRJ6AwBQAQAIAAQJcRJ6AwBQAQA1AAQKgRgAAggACQkFJfgEAJcDAAgACQkFJfgEAJcDAAE1AAUUCAgSAAIAriUA.Aylan:BAAANQADCgMIAwAAAA==.',
Az='Azelous:BAAANQADCggICAABNQAECgYIDQABAAAAAA==.Azumaa:BAAANQADCgYIEAAAAA==.Azurath:BAAANQADCgIIAgAAAA==.Azureth:BAAANQADCgEIAQAAAA==.',
Ba='Bainironwind:BAAANQADCgUIBQAAAA==.Baiwushi:BAAANQAECgIIAgAAAA==.Ballock:BAAANQADCggICAAAAA==.Balázs:BAAANQAECgEIAQAAAA==.',
Be='Becbec:BAAANQADCgYICgAAAA==.Belaghal:BAAANQADCgUIBQAAAA==.Ben:BAAANQAECgEIAQABNQAECgEIAgABAAAAAA==.Bestricer:BAAANQAECgIIAgABNQAFFAcIDwACAFYTAA==.',
Bi='Biggles:BAEBNQAECoEYAAMJAAkJzhJFFwA7AgAJAAgJwBJFFwA7AgAKAAgJ2xU7DAALAgAAAA==.Bighuntarizo:BAAANQADCggIEAAAAA==.',
Bl='Blobney:BAACNQAFFIEHAAMGAAYJ6hRXAQBhAQAGAAQJ0RVXAQBhAQAHAAIJHBP+AgC4AAA1AAQKgRcAAwYACQnzJboGAPsCAAYABwnYJboGAPsCAAcABwkKIxoEAL4CAAAA.Bluechip:BAAANQAECgIIAwAAAA==.Blueeagle:BAABNQAECoEWAAMLAAgJGSPEBwDyAgALAAgJuSLEBwDyAgAMAAEJQCZCgQB0AAAAAA==.Bluespell:BAAANQAECgIIAwABNQAECggIFgALABkjAA==.',
Bo='Bolts:BAAANQADCgYIEgAAAA==.Borak:BAAANQADCgQIBAABNQAECgYIDQABAAAAAA==.',
Br='Braezlor:BAAANQADCgcIBwAAAA==.Brewdarymor:BAAANQADCggICAABNQAECgcIDAABAAAAAA==.Broaahhaha:BAAANQADCggIDQAAAA==.',
Bu='Bulletsponge:BAAANQADCgEIAQABNQADCgYIDQABAAAAAA==.Butterflyy:BAAANQAECgUICQAAAA==.',
Ca='Caelena:BAAANQAECgIIAgAAAA==.',
Ce='Celestial:BAAANQAECgUICAAAAA==.',
Ch='Chilltest:BAAANQAECgQIBwAAAA==.Chronobacon:BAAANQADCgYICgABNQAECgcIDAABAAAAAA==.Chupacabra:BAAANQADCgcIEQAAAA==.Chuyz:BAAANQAECgcICAAAAA==.Chuyzz:BAAANQAECgIIBAAAAA==.',
Cl='Clawdene:BAAANQADCgEIAQAAAA==.Clickchi:BAAANQADCgYICQAAAA==.Cloudwarrior:BAAANQADCgEIAQABNQAFFAIIAgABAAAAAA==.',
Co='Cokediet:BAAANQADCggICgAAAA==.Cooties:BAAANQADCgUIBQABNQADCggICQABAAAAAA==.Cordeliaa:BAAANQADCggIDgAAAA==.Coven:BAAANQADCgYICgAAAA==.',
Cr='Crunch:BAAANQAECgcIDAAAAA==.',
Cy='Cynderelle:BAAANQADCgMIBAAAAA==.Cynikka:BAAANQAECgQIBgAAAA==.Cynthor:BAAANQAECgQIBAAAAA==.',
Da='Dadtothebone:BAAANQADCgUIBQAAAA==.Daghahi:BAAANQAECgQIBQAAAA==.Daishanar:BAAANQAECgMIAwAAAA==.Dalethyr:BAAANQAECgQIBAAAAA==.Darkseid:BAAANQADCgQIBAAAAA==.Darthflame:BAAANQADCgUIBQABNQAECgUICAABAAAAAA==.Dawuffman:BAAANQADCggIGAAAAA==.',
De='Deathdruid:BAAANQAECgMIAwAAAA==.Delmus:BAAANQAECgEIAQAAAA==.Delphinae:BAAANQADCgcIEQAAAA==.Demontwink:BAAANQADCggIFwAAAA==.Devera:BAABNQAECoEXAAIJAAkJpxSGEgB7AgAJAAkJpxSGEgB7AgAAAA==.',
Di='Dinkylock:BAAANQADCgYICgAAAA==.Dirtykahuna:BAAANQADCggIEwAAAA==.Discosticks:BAAANQADCggIDQAAAA==.Distress:BAAANQADCgUIBQAAAA==.',
Do='Dojoshaman:BAAANQAECgYICgAAAA==.Doodman:BAAANQAECgQIBAAAAA==.',
Dr='Dragondeez:BAAANQADCgUIBQABNQAECgMIBQABAAAAAA==.Drwn:BAAANQADCggICAAAAA==.',
Du='Duckroll:BAAANQADCgMIBAAAAA==.Dustmaster:BAAANQABCgIIBgAAAA==.',
Dw='Dwelknarr:BAAANQADCgcIDwAAAA==.',
Ea='Eadric:BAAANQADCggIEAAAAA==.Earendur:BAAANQADCgUIDQAAAA==.Earthfury:BAAANQAECgIIAgAAAA==.',
Ed='Edallen:BAAANQAECgEIAQAAAA==.',
Ee='Eelyroc:BAAANQADCgMIAwAAAA==.',
El='Elbrujo:BAAANQAECgMIAwAAAA==.',
Em='Emaytete:BAAANQADCgcIBwAAAA==.Emayteteheww:BAAANQAECgEIAQAAAA==.Emillyra:BAAANQADCgYIDgAAAA==.',
Ep='Ephemra:BAAANQADCggIBwAAAA==.',
Es='Esteban:BAAANQADCggIEwAAAA==.',
Ev='Evokethywikd:BAAANQADCgMIAwABNQABCgIIAgABAAAAAA==.',
Fa='Fahx:BAAANQADCgQIBAAAAA==.Falwyn:BAAANQADCgYIBgAAAA==.Famidore:BAAANQADCgIIBAAAAA==.',
Fe='Felflamel:BAAANQAECgUICAAAAA==.Feltest:BAAANQAECgQIBAAAAA==.Ferdinan:BAAANQAECgIIAQAAAA==.',
Fl='Flashter:BAAANQAECgUIBQAAAA==.Fluffycuddle:BAAANQADCgUICQAAAA==.',
Fo='Forrealzies:BAAANQADCgYIDAAAAA==.Fortunato:BAAANQADCgEIAQAAAA==.',
Fr='Frankhs:BAAANQADCgQIBAAAAA==.',
Ga='Galdrel:BAAANQAECgEIAQAAAA==.Gallince:BAAANQAFFAMIAwAAAA==.Garbich:BAAANQADCgEIAgABNQADCgcIBwABAAAAAA==.Gary:BAAANQAECgEIAQAAAA==.',
Ge='Gerhart:BAAANQADCgcIEQAAAA==.',
Gh='Ghostsham:BAACNQAFFIENAAINAAYJrB4sAABuAgANAAYJrB4sAABuAgA1AAQKgRsAAw0ACQnOIocBAMYDAA0ACQnOIocBAMYDAA4AAwl+AmZxAJIAAAAA.Ghðst:BAAANQAECgQIBAABNQAFFAYIDQANAKweAA==.',
Gi='Gilgamet:BAAANQADCgEIAQAAAA==.Gizmito:BAAANQADCgEIAQAAAA==.',
Gl='Glizzyman:BAAANQAECgQIBgAAAA==.',
Go='Go:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Goldoran:BAAANQADCgIIAgAAAA==.Gonette:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.Goniff:BAAANQAECgUICAAAAA==.Goransk:BAAANQADCggIDgAAAA==.',
Gr='Gracelious:BAAANQAECgcIDgAAAA==.Graebeard:BAAANQADCgUICwAAAA==.Graehame:BAAANQADCgQIBwAAAA==.Greyshadow:BAAANQADCgUIBQAAAA==.Grüb:BAAANQADCgYIDQAAAA==.',
Gu='Guitar:BAAANQABCgUIBQAAAA==.Guntran:BAAANQAECgUICQAAAA==.Gurkha:BAAANQADCgYIBgAAAA==.Gurthock:BAAANQAECgYICgAAAA==.',
Gw='Gwenixx:BAAANQADCgYIDwAAAA==.',
He='Headhuntin:BAAANQADCggICwAAAA==.Heatfang:BAAANQADCgcICQAAAA==.Hellione:BAAANQADCgYIEgAAAA==.Hellmaree:BAAANQADCgEIAQAAAA==.Helltest:BAAANQADCgQIBAAAAA==.',
Ho='Holywater:BAAANQAECgQIBQAAAA==.Honkinhammer:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Hotdogman:BAACNQAFFIEMAAILAAYJVRanAAAZAgALAAYJVRanAAAZAgA1AAQKgRYAAgsACQm/JJUBAKgDAAsACQm/JJUBAKgDAAE1AAMKAggCAAEAAAAA.Hotdumpling:BAAANQADCgMIAgAAAA==.',
Hy='Hyle:BAAANQAECgEIAQAAAA==.',
Il='Illuminator:BAAANQADCgYIDwAAAA==.',
In='Inspectadeck:BAABNQAECoEXAAMGAAkJ8RfDDACqAgAGAAkJ8RfDDACqAgAHAAIJ7wU0QgBkAAAAAA==.',
Is='Istariel:BAAANQAECgIIAgABNQAFFAYIDQANAKweAA==.',
It='Ithoron:BAAANQAECgUIBwAAAA==.',
Ja='Jazu:BAAANQAECgEIAQAAAA==.',
Je='Jerks:BAAANQAECgQIBgAAAA==.',
Jo='Jost:BAAANQADCgMIAwABNQAECgUIBgABAAAAAA==.Joval:BAAANQADCgYIDwAAAA==.Jozeph:BAAANQAECgEIAgAAAA==.',
['Jà']='Jàmie:BAAANQADCgEIAQAAAA==.',
Ka='Kaalar:BAAANQAECgUIBwAAAA==.Kalichnakov:BAAANQABCgIIAgAAAA==.Kamoura:BAAANQAECgQIBQAAAA==.Kapeta:BAAANQADCggIDwAAAA==.Karmen:BAABNQAECoEYAAIPAAkJASLyAACWAwAPAAkJASLyAACWAwAAAA==.Karnatron:BAAANQADCgYIDwAAAA==.Karnvoid:BAAANQADCgIIAgABNQADCgYIDwABAAAAAA==.Katalain:BAAANQADCggICQABNQAECgcIDgABAAAAAA==.',
Ke='Keattz:BAACNQAFFIEMAAIIAAcJHxBpAACHAgAIAAcJHxBpAACHAgA1AAQKgRsAAggACQm1JQICAM4DAAgACQm1JQICAM4DAAE1AAQKBwgMAAEAAAAA.Keattzxd:BAAANQAECgcIDAAAAA==.Keedill:BAAANQAECgMIAwAAAA==.Keelu:BAAANQADCgEIAQAAAA==.Keggerz:BAAANQADCgcIDAAAAA==.Kennagi:BAAANQAECgQIBgAAAA==.Kenshunterl:BAAANQADCgcIEQAAAA==.',
Kh='Khanzen:BAAANQADCggICAAAAA==.Khathgar:BAAANQAECgEIAQABNQAECgcIDAABAAAAAA==.Khovastis:BAABNQAECoEYAAMJAAkJnhalGAApAgAJAAgJjxalGAApAgAQAAIJkhZ8DgCKAAAAAA==.',
Ki='Kianll:BAAANQADCgcICAAAAA==.Kitchntabls:BAABNQAECoEYAAMRAAkJXCVgAADqAwARAAkJXCVgAADqAwAEAAMJ/w+ZNAC3AAAAAA==.',
Kj='Kjirou:BAAANQAECgIIAwAAAA==.',
Ko='Koenji:BAAANQAFFAIIAgAAAA==.Korgrim:BAAANQADCggIDQAAAA==.',
Ky='Kymal:BAAANQADCggIDgAAAA==.Kyndel:BAAANQADCgQIBwAAAA==.Kyndrah:BAAANQAECgcIDgABNQADCgQIBwABAAAAAA==.',
['Kä']='Käne:BAAANQAECgEIAQAAAA==.',
['Kì']='Kìn:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.',
['Kí']='Kín:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.',
La='Lableue:BAAANQADCggICQAAAA==.Lavacask:BAAANQADCgcIDwAAAA==.',
Le='Leodk:BAAANQAFFAIIAwABNQAECggIFQASAE8lAA==.Lerann:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Levey:BAAANQAECggIDgAAAA==.',
Li='Lick:BAAANQAECgMIAwABNQAECgEIAQABAAAAAA==.Lict:BAAANQAECgcIEAABNQAECgEIAQABAAAAAA==.Liekki:BAAANQADCgEIAQABNQADCgcIDwABAAAAAA==.Lillea:BAAANQADCggIFAAAAA==.Listurfiend:BAAANQADCgIIAgAAAA==.',
Lo='Loktalaan:BAABNQAECoEXAAITAAkJ3BMMBAC1AgATAAkJ3BMMBAC1AgAAAA==.Lothlorian:BAAANQADCgEIAQAAAA==.',
Lu='Luan:BAAANQAECgQIBAAAAA==.Lucien:BAAANQAECgcIDgAAAA==.Lute:BAAANQAECgUICQAAAA==.',
Ly='Lyfeguard:BAAANQADCggIDgAAAA==.',
Ma='Machoke:BAAANQADCgYIDQAAAA==.Mahito:BAAANQAECgYICgAAAA==.Malenia:BAAANQAFFAEIAQAAAA==.Malume:BAAANQADCgYICAAAAA==.Malyon:BAAANQADCgEIAQAAAA==.Malístra:BAAANQADCggICgAAAA==.Manaless:BAAANQAECgEIAQABNQAECggIFQASAE8lAA==.Marderer:BAAANQAECgQIBQAAAA==.Masakari:BAAANQAECgQIBQAAAA==.Materia:BAAANQADCgcIBwAAAA==.Mathmagician:BAAANQAECgMIBQAAAA==.Maulfarm:BAAANQAFFAEIAQAAAA==.Mazz:BAAANQABCgYIBgABNQADCgYIEAABAAAAAA==.Mazzlock:BAAANQADCgYIEAAAAA==.',
Me='Megameow:BAAANQAECgcIDAAAAA==.Mercuria:BAAANQADCgMIAwAAAA==.Metaclass:BAAANQAECgIIAgAAAA==.',
Mi='Mitrixx:BAAANQADCggIEwAAAA==.',
Mo='Mobius:BAAANQADCgQIBAAAAA==.Mokuo:BAAANQADCgUIBQAAAA==.Moonthorn:BAAANQADCggIEwAAAA==.Mort:BAAANQADCgcIEQAAAA==.Moxou:BAAANQAECgEIAQABNQAFFAIIAwABAAAAAA==.Moxxou:BAAANQAFFAIIAwAAAA==.Moyi:BAAANQADCgcIBwAAAA==.',
Mu='Mulch:BAAANQAECgYICQAAAA==.',
My='Mybelle:BAAANQADCgIIAgAAAA==.Mysticle:BAAANQADCgUICAAAAA==.Mythaltis:BAAANQAECgMIBAAAAA==.',
Na='Naizhruk:BAAANQADCgEIAQAAAA==.Nall:BAAANQADCgIIBAAAAA==.Naoh:BAAANQADCgQIBAAAAA==.Narache:BAAANQADCgYIBwAAAA==.Naul:BAAANQAECgYICQAAAA==.Naull:BAAANQAECgEIAgAAAA==.Naysayer:BAAANQADCgEIAQAAAA==.Naúl:BAAANQADCgUIBQAAAA==.',
Ne='Necrokai:BAAANQAECgMIAwAAAA==.Necroscourge:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Neighter:BAAANQADCgcIEwAAAA==.Nerevar:BAAANQADCgYIDQAAAA==.Netal:BAAANQAECgIIAgAAAA==.Nevergoback:BAAANQADCgcICwABNQAECgQIBQABAAAAAA==.',
Ni='Ninejuanjuan:BAAANQAECgUICAAAAA==.Nishikienrai:BAAANQADCgUIBQAAAA==.',
No='Nochit:BAABNQAECoEZAAIJAAkJYiZ2AADqAwAJAAkJYiZ2AADqAwAAAA==.Noctula:BAAANQAECgQIBgABNQAECgMIAwABAAAAAA==.Norne:BAAANQAECgcIDQAAAA==.Nowfaleena:BAAANQADCggICAAAAA==.',
Ny='Nytkiller:BAAANQAECgEIAQAAAA==.Nyzul:BAAANQADCgcIDwABNQAECgEIAQABAAAAAA==.',
Oa='Oatie:BAAANQADCgUIAwAAAA==.',
Oc='Oceanic:BAAANQADCggICAAAAA==.',
Od='Odlinn:BAAANQAECgMIAwABNQAECgYICQABAAAAAA==.',
On='Onlyhorns:BAAANQADCgcIBwABNQAECgYIDAABAAAAAA==.',
Op='Opalia:BAAANQADCgcIEwAAAA==.Opallea:BAAANQADCgYIDwABNQADCgYIDwABAAAAAA==.',
Or='Orch:BAAANQAECgEIAQAAAQ==.',
Ov='Overclocked:BAAANQAECgYICgAAAA==.',
Pa='Paddington:BAAANQAECgQIBAAAAA==.Pahbi:BAAANQADCgYIBwAAAA==.Paul:BAAANQAECgEIAgAAAA==.',
Pe='Pendojo:BAAANQADCgMIAwAAAA==.Pendomage:BAAANQAECgEIAQAAAA==.',
Pi='Pip:BAABNQAECoEWAAMNAAkJPRj2FQBvAgANAAgJDBj2FQBvAgAOAAIJDwPTeABxAAABNQAECgkJFwAJAKcUAA==.Pipium:BAABNQAECoEWAAIFAAkJ1SHIAADSAgAFAAkJ1SHIAADSAgABNQAECgkJFwAJAKcUAA==.',
Po='Pookiehandz:BAAANQAECgQIBQAAAA==.Porpul:BAAANQAECgIIAgAAAA==.Powery:BAAANQADCgYIBgAAAA==.',
Pr='Prophet:BAAANQADCgcIBwAAAA==.',
Pu='Purples:BAAANQAECgMIAwAAAA==.Purpul:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.',
Qa='Qawxz:BAAANQADCgUIBQAAAA==.',
Ra='Raikan:BAAANQAECgQIBgAAAA==.Rainwater:BAAANQADCgEIAQAAAA==.Raisyns:BAABNQAECoEYAAMUAAkJbiF1AQCRAwAUAAkJbiF1AQCRAwAVAAEJkBzWEgBEAAAAAA==.Rammic:BAAANQADCgIIAgAAAA==.Randstohl:BAAANQADCggIDgAAAA==.Ratakhan:BAAANQADCgUICAAAAA==.Raulothim:BAAANQAECgMIAwAAAA==.',
Re='Rebell:BAAANQAECggIAgAAAA==.Reny:BAAANQAECgEIAQAAAA==.Repentance:BAAANQADCgEIAQABNQADCgYIBwABAAAAAA==.Retribussy:BAAANQAECgQIBQAAAA==.',
Ri='Ricemachinex:BAAANQAECgYICAABNQAFFAcIDwACAFYTAA==.',
Ro='Rocthar:BAAANQAECgUIBwAAAA==.Roguelite:BAAANQADCgEIAQABNQAECggIFQASAE8lAA==.Romarus:BAAANQADCggIDgAAAA==.Romeoposter:BAAANQADCggICAAAAA==.',
Ru='Rukarazyll:BAAANQADCgcIEgAAAA==.Rumble:BAAANQADCgIIAgAAAA==.',
Ry='Ryunohige:BAAANQADCggICAAAAA==.',
['Rú']='Rúúsh:BAAANQADCgcICAAAAA==.',
Sa='Safeword:BAAANQADCgQIBwAAAA==.Saihua:BAAANQADCgYIBgAAAA==.Saintjonn:BAAANQAECgcIDgAAAA==.Sarthdidius:BAAANQAECgUIBwAAAA==.Sassparilluh:BAAANQADCgYIDwAAAA==.Savalla:BAAANQADCgYIBgAAAA==.',
Sc='Schadenfreud:BAAANQAECgQIBQAAAA==.Scholoman:BAAANQADCggIDgAAAA==.Scratchbelly:BAAANQADCgUIBQAAAA==.',
Se='Senpai:BAABNQAECoEXAAMWAAkJhhw4FwAMAwAWAAkJixs4FwAMAwAXAAEJ5R8xFwBRAAAAAA==.Seoli:BAAANQADCgYICAAAAA==.Serenya:BAAANQADCgYIBgAAAA==.',
Sh='Shalanthra:BAAANQADCgcICgAAAA==.Shamallow:BAAANQADCgQIBAAAAA==.Shammunition:BAAANQAECgYIDAAAAA==.Shartz:BAAANQADCggIFAAAAA==.Shaysa:BAEANQAECgEIAQAAAA==.Sheraa:BAAANQADCgcIDwAAAA==.Shinigamisan:BAAANQAECgQIBQAAAA==.Shynox:BAAANQAECgEIAQAAAA==.',
Si='Sinnerchrono:BAAANQADCggIBwAAAA==.Sinnwoo:BAAANQABCgQIBgAAAA==.Sitharco:BAAANQAECgIIAgAAAA==.',
Sm='Smorc:BAAANQAECgUIBQAAAA==.',
Sn='Snackwitch:BAAANQADCgcIEQAAAA==.Sneaki:BAAANQAECgEIAQABNQAECgUIBwABAAAAAA==.',
So='Sommin:BAAANQADCgYICgAAAA==.Sorakah:BAAANQAECgMIBAAAAA==.Soulviper:BAAANQAECggIEwAAAA==.',
Sp='Spankmyflank:BAAANQADCgYIDwAAAA==.',
Sq='Squaleon:BAAANQADCgQIBAAAAA==.',
St='Stabbyfinch:BAAANQADCgYIDAAAAA==.Steplok:BAAANQADCgYIBgAAAA==.Stonestriker:BAAANQADCgcIEQAAAA==.Stooben:BAAANQAECgYICgAAAA==.Sturge:BAAANQADCgYICAAAAA==.',
Su='Supahsayajin:BAAANQAECgYIDwABNQABCgIIAgABAAAAAA==.',
Sw='Sweetbee:BAAANQAECgIIAgAAAA==.Swole:BAAANQAECgQIBQAAAA==.',
Sy='Syanalody:BAAANQADCgUIDgAAAA==.Sylarz:BAAANQADCggICAABNQAECgcIDAABAAAAAA==.Sylenn:BAAANQADCgYICQAAAA==.Syn:BAAANQAECgQIBQAAAA==.Synchro:BAAANQADCgQIBAAAAA==.',
Ta='Tanstaafl:BAAANQAECgQIBgAAAA==.Taralom:BAAANQADCgcIEQAAAA==.Taurenspurb:BAAANQADCgYIBgAAAA==.Taz:BAEANQAECggICwAAAA==.',
Te='Tenebrix:BAAANQAECgEIAQAAAA==.',
Th='Thadex:BAAANQAECgYICgAAAA==.Thedood:BAAANQADCgYIBgAAAA==.Theldrid:BAAANQAECgYICwAAAA==.Thepallyguy:BAAANQADCgcIDwABNQAECgMIAwABAAAAAA==.Thepriestguy:BAAANQAECgMIAwAAAA==.Theralethia:BAAANQADCgEIAQAAAA==.Therian:BAAANQADCgIIAgAAAA==.Theshamanguy:BAAANQADCggICAABNQAECgMIAwABAAAAAA==.Thorseas:BAAANQAECgMIBAAAAA==.Thunderkill:BAAANQADCgYICwAAAA==.',
Ti='Tirissa:BAAANQADCgEIAQAAAA==.',
To='Tooyew:BAAANQADCgcIBwABNQAFFAIIAgABAAAAAA==.Tooyoo:BAAANQAFFAIIAgAAAA==.Torpedotaka:BAAANQAECgMIBAAAAA==.',
Tp='Tpala:BAAANQAECgQIBwAAAA==.',
Tr='Triggerfarm:BAAANQAECgQIBAAAAA==.Tristis:BAAANQADCgYICgAAAA==.',
Tu='Turthunt:BAACNQAFFIEFAAILAAQJBBxsAgBtAQALAAQJBBxsAgBtAQA1AAQKgRoAAwsACQkpI98KALMCAAsABwlxIt8KALMCAAwABgmRIswuANoBAAAA.',
Tw='Twinns:BAAANQADCgUIBQAAAA==.',
Ty='Tyesham:BAAANQADCgYICQABNQAECgEIAQABAAAAAA==.Tyice:BAAANQAECgEIAQAAAA==.',
Ur='Urak:BAAANQADCgYIBgAAAA==.',
Va='Valaidpriest:BAAANQAECgUIBwAAAA==.Valoth:BAAANQADCgUICAAAAA==.Vanelura:BAAANQADCgUIDAAAAA==.',
Ve='Velorth:BAAANQADCgYIBgAAAA==.',
Vr='Vrahmageddon:BAAANQAECgEIAQAAAA==.',
Vy='Vynlorin:BAABNQAECoEYAAIYAAkJxxN+FAA9AgAYAAkJxxN+FAA9AgAAAA==.',
Wa='Wahstella:BAACNQAFFIELAAIWAAYJDgt0AQD+AQAWAAYJDgt0AQD+AQA1AAQKgSMAAxYACQk/H7EMAFcDABYACQmwHrEMAFcDABcAAgm0I+gMANQAAAAA.Waraight:BAACNQAFFIEGAAIYAAQJ0Q4PAwAWAQAYAAQJ0Q4PAwAWAQA1AAQKgRgAAhgACQmRIysCAKADABgACQmRIysCAKADAAAA.Wardrarth:BAAANQAECgYIBgAAAA==.Waterdroplet:BAAANQADCgcICgAAAA==.',
Wh='Whodofthunk:BAAANQADCgYIDQAAAA==.',
Wi='Wighttrash:BAAANQAECgQIBAABNQAECgQIBAABAAAAAA==.Wilferth:BAAANQAECgYICgAAAA==.Wirl:BAAANQADCggICAAAAA==.',
Wo='Woozi:BAAANQAFFAEIAQAAAA==.',
Wr='Wrinklz:BAAANQAECgYICwAAAA==.Wrlymoonbat:BAAANQADCgEIAQAAAA==.',
Wu='Wuggles:BAAANQADCggICAAAAA==.',
Xa='Xavierson:BAAANQADCggIFAAAAA==.',
Xe='Xelot:BAAANQADCggICAAAAA==.',
Xi='Xilone:BAAANQADCgUICQAAAA==.',
Ya='Yangchengfu:BAAANQAECgIIAgAAAA==.',
Yi='Yi:BAAANQAECgEIAQAAAA==.',
Za='Zaaga:BAAANQAECgEIAQAAAA==.Zamon:BAAANQADCgUIBQAAAA==.Zamyk:BAAANQADCgIIAgAAAA==.Zaqor:BAAANQABCgIIAgAAAA==.Zarf:BAAANQAECgYICQAAAA==.Zariq:BAAANQADCgUIBQAAAA==.Zayra:BAAANQADCgUIBQAAAA==.',
Ze='Zeld:BAAANQAECgQIBQAAAA==.Zelgius:BAAANQAECgYICwAAAA==.Zenfel:BAAANQAECgEIAQAAAA==.',
Zh='Zhulee:BAAANQAECgQIBQAAAA==.',
Zi='Zikaja:BAAANQADCggIEgABNQAECgkJGAAYAMcTAA==.Zir:BAAANQAECgUIBgAAAA==.',
Zo='Zoark:BAAANQADCgYIDgAAAA==.Zorgap:BAAANQAECgQIBAAAAA==.',
Zu='Zuggwithin:BAAANQAECgMIAwAAAA==.',
Zy='Zygo:BAAANQAECgEIAQAAAA==.Zyprexen:BAAANQADCgYIDgAAAA==.Zyprexius:BAAANQAECgUIBwAAAA==.',
['Ða']='Ðadgar:BAAANQADCgYICwAAAA==.',
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
