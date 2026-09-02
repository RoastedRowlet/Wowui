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

local lookup = {'Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='Firetree',name='US',type='weekly',zone=53,date='2026-09-01',data={Ad='Adondias:BAAANQAECgIIAgAAAA==.',
Ae='Aelana:BAAANQAECgIIAgAAAA==.',
Ak='Akryllic:BAAANQAECgEIAQAAAA==.',
Al='Alamora:BAAANQADCgQIBAAAAA==.Aldari:BAAANQAECgYICAAAAA==.Allydk:BAAANQAECgUIBQAAAA==.Almorn:BAAANQADCggICAAAAA==.Alondrius:BAAANQADCgIIAgAAAA==.Altrag:BAAANQAECgUIBgAAAA==.Aluc:BAAANQAECgIIAgAAAA==.',
An='Angestrypee:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.Anslayer:BAAANQADCgUICgAAAA==.',
Ar='Archön:BAAANQADCgIIAgAAAA==.Arks:BAAANQADCgcIEgAAAA==.',
As='Asperges:BAAANQAECgEIAQAAAA==.',
Av='Averly:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Avralynia:BAAANQADCgcIDAAAAA==.Avrella:BAAANQADCgIIAgAAAA==.',
Ba='Babydaddyx:BAAANQAECgcICwABNQAECgEIAQABAAAAAA==.Baconn:BAAANQAECgYICQAAAA==.Balun:BAAANQAECgEIAQAAAA==.',
Be='Beefdido:BAAANQAECgIIAgAAAA==.Beefstew:BAAANQAECgIIAgAAAA==.Belithe:BAAANQADCgYICgAAAA==.Belletrixya:BAAANQADCggIDAAAAA==.Belrandir:BAAANQADCgQIBAAAAA==.Berrymanalow:BAAANQADCgYIBgAAAA==.',
Bi='Bijtoo:BAAANQADCggIDgAAAA==.Bingsoo:BAAANQAECgUIBQAAAA==.',
Bj='Bjorney:BAAANQADCggIDgAAAA==.',
Bl='Blankspace:BAAANQAECgEIAQAAAA==.Blasphemar:BAAANQADCgMIAwAAAA==.Blindvngence:BAAANQAECgEIAgAAAA==.Blizkit:BAAANQADCgQIBAAAAA==.Bluedruid:BAAANQADCgEIAQAAAA==.Blusloane:BAAANQADCgQIBAAAAA==.',
Bo='Bonkdeath:BAAANQADCgYICgABNQADCgEIAQABAAAAAA==.Booms:BAAANQADCgYICwAAAA==.',
Br='Braintrust:BAAANQADCgcIBwAAAA==.Brezanyou:BAAANQADCgIIAgABNQAECgMIBAABAAAAAA==.Brobafett:BAAANQADCgYIBgAAAA==.Brøx:BAAANQADCggIDgAAAA==.',
Bu='Bubbleblood:BAAANQADCgMIAwAAAA==.Bunnyboy:BAAANQADCgYIBQAAAA==.Burlen:BAAANQAECgUICAAAAA==.',
['Bê']='Bênitora:BAAANQAECgQIBQAAAA==.',
['Bî']='Bîrth:BAAANQAECgQIBAAAAA==.',
Ca='Calic:BAAANQAECgIIAgAAAA==.Calryuu:BAAANQAECgEIAQAAAA==.Cambiön:BAAANQAECgQIBgAAAA==.',
Ce='Cern:BAAANQADCggICAAAAA==.',
Ch='Chadaclysm:BAAANQADCgMIAwAAAA==.Chadotcom:BAAANQADCgQIBgAAAA==.Chickenman:BAAANQAECgcIDAAAAA==.Chinpokomon:BAAANQAECgEIAQAAAQ==.Choncc:BAAANQAECgEIAQAAAA==.Chonkykong:BAAANQAECgIIAgAAAA==.Chubbychi:BAAANQADCgIIAgABNQAECgMIBAABAAAAAA==.',
Co='Codytwo:BAAANQADCgYIBwABNQADCgYIDAABAAAAAA==.Coldstrype:BAAANQAECgMIAwAAAA==.Cole:BAAANQAECgEIAQAAAA==.Collonel:BAAANQADCgYIBgAAAA==.Connquest:BAAANQAECgEIAgAAAA==.Costcobeef:BAAANQADCgYICwAAAA==.',
Cp='Cpttan:BAAANQADCggICAAAAA==.',
Cr='Critypally:BAAANQAECgIIAgAAAA==.Crunkpickles:BAAANQADCgQIBAAAAA==.',
Cv='Cvrcvss:BAAANQAECgEIAQAAAA==.',
Da='Dabadjuju:BAAANQADCgYIDAAAAA==.Daerik:BAAANQAECgUIBQAAAA==.Dagoonfather:BAAANQAECgMIAwAAAA==.Dandorllan:BAAANQAECgQIBgAAAA==.Dandowaz:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.Dandyrandy:BAAANQAECgUIBQAAAA==.Dani:BAAANQADCgUIDAAAAA==.Dazzazn:BAAANQADCgcICwAAAA==.',
De='Decious:BAAANQADCgYIBgAAAA==.Deepfist:BAAANQAECgIIAgAAAA==.Defjam:BAAANQADCgcIBwAAAA==.Deidren:BAAANQABCgMIAwAAAA==.Delblade:BAAANQADCgYIBgAAAA==.Delicia:BAAANQAECgEIAQAAAA==.Dellbelphine:BAAANQAECgMIBQAAAA==.Demonskii:BAAANQAECgEIAQAAAA==.Demton:BAAANQADCggIEAAAAA==.',
Dh='Dhjck:BAAANQAECgUICgAAAA==.',
Di='Diatonic:BAAANQAECgQIBQAAAA==.Direkau:BAAANQAECgUIBQAAAA==.',
Do='Dojaz:BAAANQAECgEIAQAAAA==.Dontouch:BAAANQADCggIDgAAAA==.Dorager:BAAANQADCgYICAAAAA==.',
Dr='Draconica:BAAANQAECgEIAgAAAA==.Dragedo:BAAANQADCgIIAgAAAA==.Dragonfella:BAAANQAECgEIAQAAAA==.Dragonkid:BAAANQADCgEIAQAAAA==.Draktha:BAAANQAECgEIAQAAAA==.Dreddful:BAAANQAECgUIBQAAAA==.Drkelso:BAAANQADCggIDgAAAA==.',
Du='Duchalu:BAAANQAECgIIAgAAAA==.Dusklite:BAAANQADCgUIBQAAAA==.',
Eb='Ebbas:BAAANQADCgIIBAAAAA==.',
Ei='Eione:BAAANQAECgIIAgAAAA==.',
El='Elinez:BAAANQADCgcICwAAAA==.Elvinshiznic:BAAANQADCgQIBAAAAA==.',
Em='Emagine:BAAANQAECgUIBQAAAA==.Embra:BAAANQADCgMIAwAAAA==.Emeraldbeast:BAAANQAECgQIBAAAAA==.',
En='Endela:BAAANQADCggIBwAAAA==.Endelan:BAAANQADCgMIAwABNQADCggIBwABAAAAAA==.',
Er='Eroeda:BAAANQAECgEIAQAAAA==.',
Es='Escanør:BAAANQADCgcICQABNQAECgcIDAABAAAAAA==.',
Ex='Exo:BAAANQAECgUIBQAAAA==.Exylan:BAAANQAECgUIBAAAAA==.',
Ez='Ezsmash:BAAANQAECgUIBQAAAA==.',
Fe='Ferachio:BAAANQADCggIEAAAAA==.',
Fi='Fierysquish:BAAANQADCgQIBAAAAA==.Filmnoir:BAAANQADCgQIBAAAAA==.',
Fo='Foosaa:BAAANQADCgcIBwAAAA==.Forbearance:BAAANQAECgUIBQAAAA==.',
Fr='Franco:BAAANQADCggIEAAAAA==.Freshfresh:BAAANQADCggICAABNQAECgYICAABAAAAAA==.Freshlock:BAAANQAECgYICAAAAA==.Fright:BAAANQAECgEIAQAAAA==.Friska:BAAANQADCgYIBgAAAA==.Frostyp:BAAANQAECggIDgAAAA==.',
Fu='Funken:BAAANQADCgYIBwAAAA==.',
Fy='Fyre:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.Fyrebird:BAAANQAECgMIAwAAAA==.',
Ga='Gahamachita:BAAANQADCgEIAQAAAA==.Galadhriel:BAAANQAECgIIAgAAAA==.Galadima:BAAANQAECgQIBQAAAA==.Ganador:BAAANQAECgUIBQAAAA==.Garglon:BAAANQADCggICAAAAA==.Gatorrc:BAAANQADCgMIAwAAAA==.Gazzerfroz:BAAANQADCgYIBgAAAA==.',
Gi='Gileon:BAAANQAECgEIAQAAAA==.',
Gn='Gnomeofdeath:BAAANQAECgEIAQAAAA==.',
Go='Gorg:BAAANQAECgQIBwAAAA==.',
Gr='Grashoppa:BAAANQADCgUICgAAAA==.Greentide:BAAANQAECgQIBAAAAA==.Grimore:BAAANQAECgQIBAAAAA==.Groovybun:BAAANQADCgYIBgAAAA==.',
Gu='Guccimaybe:BAAANQAECgQIBgAAAA==.',
Ha='Haleluya:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Halepurr:BAAANQAECgMIAwAAAA==.Halogenrofl:BAAANQAECgMIAwAAAA==.Hammerferge:BAAANQAECgQIBAAAAA==.Hangezoë:BAAANQAECggIDgAAAQ==.Happa:BAAANQAECgYICQAAAA==.Harbngerkhan:BAAANQAECgMIAwAAAA==.Hardok:BAAANQADCgEIAQAAAA==.',
He='Healroy:BAAANQADCggICAAAAA==.Heidt:BAAANQAECgEIAQAAAA==.Hellica:BAAANQABCgQIBwAAAA==.',
Ho='Holibeef:BAAANQAECgMIBAAAAA==.Holysquish:BAAANQAECgYICAAAAA==.Homoglobin:BAAANQADCgYIBgAAAA==.Honeydemon:BAAANQAECgUIBQAAAA==.Hongis:BAAANQAECgQIBAAAAA==.Hotdogsteve:BAAANQADCgMIAwAAAA==.',
Hu='Huge:BAAANQAECgIIAgAAAA==.Huntskii:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.',
Hw='Hwaryeong:BAAANQADCgUIBQAAAA==.',
Ia='Iamluck:BAAANQAECgcICgAAAA==.Iamluçk:BAAANQADCggICAAAAA==.',
Ic='Iceleaf:BAAANQAECgEIAQAAAA==.',
Il='Ileinaa:BAAANQAECgIIBAAAAA==.Iliketrains:BAAANQADCggICAAAAA==.',
In='Indicud:BAAANQAECgEIAgAAAA==.Invvictis:BAAANQAECgEIAgAAAA==.',
Is='Isele:BAAANQADCgEIAQABNQADCggIBwABAAAAAA==.',
Ja='Jaymazing:BAAANQADCggICAABNQAECgYIBgABAAAAAA==.Jaysaurus:BAAANQAECgYIBgAAAA==.Jazzey:BAAANQAECgUICQAAAA==.',
Je='Jestyrddk:BAAANQAECgEIAQAAAA==.',
Jo='Jodox:BAAANQADCgMIAQAAAA==.Joehendry:BAAANQADCgcICgAAAA==.Johnathonn:BAAANQADCgUIBQAAAA==.Joj:BAAANQADCgcICQAAAA==.Jonthecron:BAAANQADCggIDgAAAA==.Jormot:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.',
Ju='Justamage:BAAANQAECgEIAQAAAA==.',
Ka='Kalundia:BAAANQAECgEIAQAAAA==.Karkshammy:BAAANQAECgIIAwAAAA==.',
Ke='Keane:BAAANQAECgQIBQAAAA==.Kellelor:BAAANQADCgQIBAAAAA==.',
Kh='Khanquest:BAAANQADCgMIAwAAAA==.',
Ki='Killkillkill:BAAANQABCgIIAgAAAA==.Kindassuddy:BAAANQAECgcIDAAAAA==.Kirbbslav:BAAANQADCgEIAQABNQAECggIDgABAAAAAA==.Kirbislav:BAAANQAECgMIAwABNQAECggIDgABAAAAAA==.Kirbslav:BAAANQAECggIDgAAAA==.Kirklandbeef:BAAANQADCgUIBQABNQADCgYICwABAAAAAA==.',
Kn='Knata:BAAANQADCgcIBwAAAA==.Kniavez:BAAANQAECgIIAgAAAA==.',
Kr='Krak:BAAANQAECgEIAQAAAA==.Kruugh:BAAANQADCggIDQAAAA==.',
Ku='Kungfustuff:BAAANQADCgUIBQAAAA==.Kunguska:BAAANQADCgQIAgAAAA==.',
['Kè']='Kèèn:BAAANQAECgcICgAAAA==.',
['Kÿ']='Kÿra:BAAANQADCgYIBgAAAA==.',
Le='Lectra:BAAANQABCgQIAwAAAA==.',
Lo='Lodoss:BAAANQAECgMIBAAAAA==.Lorienb:BAAANQAECgQIBAAAAA==.',
Lu='Luckehlock:BAAANQAECggIDgAAAA==.Lunaea:BAAANQADCggIDgAAAA==.',
Ma='Macgibbins:BAAANQAECgMIAwAAAA==.Magewindu:BAAANQADCggIDAAAAA==.Magus:BAAANQAECgIIAwABNQAECggIDgABAAAAAA==.Malakar:BAAANQAECgEIAQAAAA==.Mavus:BAAANQADCgYIBgAAAA==.',
Me='Meanmyst:BAAANQADCgYICQAAAA==.',
Mi='Midgardsomr:BAAANQAECgEIAQAAAA==.Minityr:BAAANQADCgcICgAAAA==.Minoritee:BAAANQAECgMIAwAAAA==.Mizukï:BAAANQADCggIDgAAAA==.',
Mo='Molyver:BAAANQAECgUIBQAAAA==.Momak:BAAANQADCgUICAABNQAECgIIAgABAAAAAA==.Mommey:BAAANQAECgUIBQAAAA==.Moonmellow:BAAANQADCgYICgAAAA==.Moosin:BAAANQADCgYIBgAAAA==.',
Mp='Mpatt:BAAANQADCgIIAgAAAA==.',
Mu='Munder:BAAANQAECgEIAQAAAA==.Murlockscry:BAAANQADCgYICAAAAA==.Musculate:BAAANQAECgEIAQAAAA==.',
Mv='Mvdi:BAAANQADCggICAAAAA==.',
['Mï']='Mïssionary:BAAANQADCgcIBwAAAA==.',
Na='Nartou:BAAANQABCgEIAQABNQADCgYIBgABAAAAAA==.',
Ne='Necrofearlia:BAAANQAECgIIAgAAAA==.Nekoashley:BAAANQADCgUIBQAAAA==.',
Ni='Nick:BAAANQAECggIDgAAAA==.Nightangelxx:BAAANQADCgUICgAAAA==.',
No='Noodle:BAAANQADCgEIAQAAAA==.Noolore:BAAANQAECgcICgAAAA==.Nosferatu:BAAANQADCgUICQAAAA==.',
Nu='Nurfhammer:BAAANQADCgEIAQABNQADCggIDgABAAAAAA==.Nurfshock:BAAANQADCggIDgAAAA==.',
Ox='Oxen:BAAANQAECgIIAgAAAA==.',
Pe='Penniee:BAAANQADCgUIBQAAAA==.Penniwing:BAAANQAECgEIAQAAAA==.Percival:BAEANQAECggIDgAAAA==.',
Ph='Phaedra:BAAANQAECgEIAQAAAQ==.Phealdh:BAAANQADCggIDgAAAA==.',
Pi='Pillargodx:BAAANQADCgQIBAAAAA==.',
Pl='Plague:BAAANQAECgQIBwAAAA==.',
Pu='Pudpull:BAAANQADCgYIBgAAAA==.Pullbarg:BAAANQADCggIEAAAAA==.',
['Pï']='Pïng:BAAANQADCggICAAAAA==.',
Qu='Quickwinnter:BAAANQAECgQIBAAAAA==.Quickwinterg:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
Ra='Raantokdh:BAAANQADCgUIBQAAAA==.Rachet:BAAANQADCgYICAAAAA==.Racoondots:BAAANQADCgYIBgAAAA==.Rakhár:BAAANQAECgEIAQAAAA==.Rastaboss:BAAANQADCgUIBQAAAA==.Ratpackleadr:BAAANQAECgEIAQAAAA==.Rayado:BAAANQAECgUIBwAAAA==.',
Re='Reggienoble:BAAANQAECgMIAwAAAA==.Rekerî:BAAANQADCgEIAQABNQAECggIDgABAAAAAA==.Resoran:BAAANQADCggIBgAAAA==.',
Ri='Rijit:BAAANQADCgYICwAAAA==.Rinzlrr:BAAANQADCggIDgABNQAECgQIBQABAAAAAA==.',
Ro='Rohrn:BAAANQAECgEIAQAAAA==.Rol:BAAANQAECgIIAwAAAA==.',
Ru='Ruggishbone:BAAANQADCgYICQAAAA==.Ruinedmyth:BAAANQADCgQIBAAAAA==.',
Sa='Saintsnetie:BAAANQADCggICQAAAA==.',
Sc='Scottyknows:BAAANQAECgEIAQAAAA==.Scredwin:BAAANQAECgIIAgAAAA==.Scrubadub:BAAANQAECgIIAgAAAA==.',
Se='Seeks:BAAANQABCgQIBQAAAA==.Senorbobo:BAAANQAECgMIAwAAAA==.Senorxx:BAAANQADCgUIBwABNQAECgMIAwABAAAAAA==.Serni:BAAANQAECgMIAwAAAA==.',
Sh='Shadei:BAAANQAECgIIBAAAAA==.Shadowslite:BAAANQADCgMIAwAAAA==.Shadowwolf:BAAANQADCgYIBgAAAA==.Sham:BAAANQAECgYICQAAAA==.Shamancheese:BAAANQADCgYIBgABNQADCgYICwABAAAAAA==.Shampayn:BAAANQADCgEIAQAAAA==.Shanksinatrá:BAABNQAECoEQAAQCAAkJOB40AwBCAgACAAYJfh40AwBCAgADAAUJ5RUEEQCDAQAEAAIJjxABCQCBAAAAAA==.Shatt:BAAANQAECgIIAgAAAA==.Shedari:BAAANQAECgUIBgAAAA==.Shiftyjd:BAAANQADCgQIBAAAAA==.Shourix:BAAANQAECgEIAQAAAA==.',
Si='Sifushocks:BAAANQADCgcIEwAAAA==.Sihnn:BAAANQAECgQIBQAAAA==.Simzerker:BAAANQAECgcICQAAAA==.Sitacha:BAAANQADCgEIAQAAAA==.',
Sk='Skrugeduc:BAAANQADCgEIAQAAAA==.',
Sm='Smarts:BAAANQADCgcICQAAAA==.',
Sn='Sniiffle:BAAANQAECgEIAQAAAA==.Snowba:BAAANQADCgIIAgAAAA==.',
Sp='Spellcrackle:BAAANQADCgcIBgABNQAECgMIBAABAAAAAA==.Sprucejenner:BAAANQAECgIIAgAAAA==.',
St='Starkisses:BAAANQAECgUIBQAAAA==.Stopthecapp:BAAANQAECgQICAABNQAECgEIAQABAAAAAA==.Styrthe:BAAANQAECggIDgAAAA==.',
Su='Surventval:BAAANQADCgYIBwABNQAECgQIBQABAAAAAA==.',
Sy='Symphony:BAAANQADCggICAABNQAECgQIBQABAAAAAA==.',
['Sí']='Síra:BAAANQADCgIIAgABNQAECgYICAABAAAAAA==.',
Ta='Taeka:BAAANQADCgYICQAAAA==.Taeshira:BAAANQAECgQIBQAAAA==.Talkimas:BAAANQAECgIIAgAAAA==.Talvisota:BAAANQADCggIDgAAAA==.Tarirn:BAAANQAECgUICAAAAA==.',
Te='Tekoslul:BAAANQAECgYICAAAAA==.Tekosmage:BAAANQABCgMIAwAAAA==.Tekosxd:BAAANQADCggICAABNQAECgYICAABAAAAAA==.Teldragoose:BAAANQADCggIDAAAAA==.Tendeda:BAAANQAECgQIBQAAAA==.',
Th='Thalunar:BAAANQAECgQIBAAAAA==.Thelegendone:BAAANQAECgYIDAAAAA==.Thorck:BAAANQADCggIDAAAAA==.Thugnakmunga:BAAANQADCgQIBAAAAA==.Thundrcheeks:BAAANQAECgUIBAABNQAFFAEIAQABAAAAAA==.',
Ti='Tinklewinkle:BAAANQAECgMIAwAAAA==.Tirra:BAAANQADCgQIBAAAAA==.',
To='Tokapolo:BAAANQADCgcIDQAAAA==.Topshelfelf:BAAANQADCgcIDAAAAA==.',
Tr='Tresdin:BAAANQAECgQIBQAAAA==.Tresemme:BAAANQADCggIDAAAAA==.',
Ts='Tsohg:BAAANQADCgUIBQAAAA==.',
Tu='Tul:BAAANQADCgYIBgAAAA==.Tumlock:BAAANQAECgEIAQAAAA==.Turrok:BAAANQAECgIIAwAAAA==.',
['Tï']='Tïgra:BAAANQAECgIIAgAAAA==.',
Ua='Uandikillhim:BAAANQAECgQIBAAAAA==.',
Un='Undeadbones:BAAANQADCggIEAAAAA==.Unfading:BAAANQAECgIIAgAAAA==.Unholyknight:BAAANQAECgQIBAAAAA==.',
Ur='Urban:BAAANQAECggIDAAAAA==.Urtark:BAAANQAECgQIBAAAAA==.',
Us='Usui:BAAANQADCgUIBQAAAA==.',
Va='Vadym:BAAANQADCgYIDAAAAA==.Varalic:BAAANQADCgIIAgABNQAECgcICwABAAAAAA==.Varandra:BAAANQADCgQIBAABNQAECgUIBAABAAAAAA==.',
Ve='Ventrois:BAAANQAECgQIBQAAAA==.Veylynn:BAAANQADCgEIAQAAAA==.',
Vo='Voidalic:BAAANQAECgcICwAAAA==.Voidrend:BAAANQAECggIDgAAAA==.',
Vy='Vynese:BAAANQADCgUIBQAAAA==.',
['Vø']='Vøgue:BAAANQAECgUIBQAAAA==.',
Wa='Warbidet:BAAANQADCgIIAgAAAA==.Warmason:BAAANQAECgIIAgAAAA==.Washed:BAAANQAECgIIAgAAAA==.',
We='Wealthy:BAAANQAECgIIAgAAAA==.',
Wh='Whispere:BAAANQAECgQIBgAAAA==.',
Wi='Wiiska:BAAANQABCgQIBAAAAA==.',
Wr='Wrred:BAAANQADCgYIDAAAAA==.',
Ye='Yetifunk:BAAANQADCgYICgAAAA==.',
Yo='Yoloswagging:BAAANQADCgEIAQABNQAECgYICwABAAAAAA==.Yougotfuxed:BAAANQADCgEIAQAAAA==.Yourpal:BAAANQAECgQIBgAAAA==.',
Ze='Zemi:BAAANQAECgUIBQAAAA==.Zephang:BAAANQAECgQIBAAAAA==.Zevalia:BAAANQAECgEIAQAAAA==.',
Zl='Zlowwchain:BAAANQADCgUIBQAAAA==.',
Zo='Zophia:BAAANQADCgUIBwAAAA==.',
Zu='Zugrotic:BAAANQAECgIIAgAAAA==.Zumy:BAAANQAECgYICQAAAA==.',
['ßl']='ßlade:BAAANQABCgIIAgAAAA==.',
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
