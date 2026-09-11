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

local lookup = {'Unknown-Unknown','Priest-Shadow','Priest-Holy','Evoker-Preservation','Mage-Arcane','Paladin-Holy','Warlock-Affliction','Druid-Balance','Hunter-Marksmanship','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Unholy','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance',}
local provider = {region='US',realm='Firetree',name='US',type='weekly',zone=53,date='2026-09-08',data={Ad='Adondias:BAAANQAECgUIBwAAAA==.',
Ae='Aelana:BAAANQAECgUIBwAAAA==.',
Ak='Akryllic:BAAANQAECgMIBAAAAA==.',
Al='Alamora:BAAANQADCggIDAAAAA==.Aldari:BAAANQAECgcIDwAAAA==.Allydk:BAAANQAECgcICwAAAA==.Almorn:BAAANQADCggICAAAAA==.Alondrius:BAAANQADCgIIAgAAAA==.Altrag:BAAANQAECgYIDAAAAA==.Aluc:BAAANQAECgUIBwAAAA==.',
An='Angestrypee:BAAANQAECgIIAgABNQAECgYICwABAAAAAA==.Anslayer:BAAANQADCgUICgAAAA==.',
Ar='Archön:BAAANQAECgQIBAAAAA==.Arks:BAAANQAECgEIAQAAAA==.',
As='Asperges:BAAANQAECgIIAgAAAA==.Astrellia:BAAANQADCgIIAgAAAA==.',
Av='Averly:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.Avralynia:BAAANQAECgIIAgAAAA==.Avrella:BAAANQADCgUIBQAAAA==.',
Ba='Babydaddyx:BAAANQAFFAEIAQABNQAECgUIBgABAAAAAA==.Baconn:BAAANQAECgcIDwAAAA==.Balun:BAAANQAECgEIAQAAAA==.',
Be='Beefdido:BAAANQAECgQIBgAAAA==.Beefstew:BAAANQAECgQIBgAAAA==.Belithe:BAAANQADCgcIEQAAAA==.Belletrixya:BAAANQAECgIIAgAAAA==.Belrandir:BAAANQADCgYICgAAAA==.Berrymanalow:BAAANQADCgYIBgAAAA==.',
Bi='Bijtoo:BAAANQAECgUIBAAAAA==.Bingsoo:BAAANQAECgYICwAAAA==.',
Bj='Bjarki:BAAANQADCgYIBgAAAA==.Bjorney:BAAANQAECgQIBAAAAA==.',
Bl='Blankspace:BAAANQAECgQIBQAAAA==.Blasphemar:BAAANQADCgMIAwAAAA==.Blindvngence:BAAANQAECgUIBwAAAA==.Blizkit:BAAANQADCgYIBgAAAA==.Bloodrayne:BAAANQAECgEIAQAAAA==.Bluedruid:BAAANQAECgQIBAAAAA==.Blusloane:BAAANQADCgQICAAAAA==.',
Bo='Bonkdeath:BAAANQADCgYICgABNQAECgQIBAABAAAAAA==.Booms:BAAANQADCgYICwAAAA==.',
Br='Braintrust:BAAANQADCgcIBwAAAA==.Brezanyou:BAAANQADCgIIAgABNQAECgYICgABAAAAAA==.Brobafett:BAAANQADCggIFgAAAA==.Brøx:BAAANQAECgUIBAAAAA==.',
Bu='Bubbleblood:BAAANQADCgMIAwAAAA==.Bunnyboy:BAAANQADCgYICgAAAA==.Burlen:BAAANQAECggIDwAAAA==.',
['Bê']='Bênitora:BAAANQAECgYICgAAAA==.',
['Bî']='Bîrth:BAAANQAECgcICgAAAA==.',
Ca='Calic:BAAANQAECgQIBgAAAA==.Calryuu:BAAANQAECgQIBQAAAA==.Cambiön:BAAANQAECgYIDAAAAA==.Capslock:BAAANQADCgQIBAABNQADCgUICQABAAAAAA==.Casziel:BAAANQADCgUIBQAAAA==.',
Ce='Cern:BAAANQAECgIIAgAAAA==.',
Ch='Chadaclysm:BAAANQADCgMIAwAAAA==.Chadotcom:BAAANQADCgQIBgAAAA==.Chantyu:BAAANQADCggICAABNQAECgYICgABAAAAAA==.Chickenman:BAAANQAECgcIEAAAAA==.Chinpokomon:BAAANQAECgYIBwAAAQ==.Choncc:BAAANQAECgUIBgAAAA==.Chonkykong:BAAANQAECgIIBAAAAA==.Chubbychi:BAAANQADCgIIAgABNQAECgYICgABAAAAAA==.Chuppy:BAAANQADCgUIBQAAAA==.',
Co='Codytwo:BAAANQADCgYIBwABNQADCgYIDAABAAAAAA==.Coldstrype:BAAANQAECgYICwAAAA==.Cole:BAAANQAECgMIBAAAAA==.Collonel:BAAANQADCgYIBgAAAA==.Connquest:BAAANQAECgEIAgAAAA==.Costcobeef:BAAANQADCggIDgAAAA==.Couchlocked:BAAANQABCgQIBAAAAA==.',
Cp='Cpttan:BAAANQAECgQIBAAAAA==.',
Cr='Critykity:BAAANQADCggICQAAAA==.Critypally:BAAANQAECgUIBgAAAA==.Crunkpickles:BAAANQADCggIDAAAAA==.',
Cv='Cvrcvss:BAAANQAECgUIBgAAAA==.',
Da='Dabadjuju:BAAANQADCgYIDAAAAA==.Daerik:BAAANQAECgcICwAAAA==.Dagoonfather:BAAANQAECgYICQAAAA==.Dandorllan:BAAANQAFFAEIAQAAAA==.Dandowaz:BAAANQAECgQIBQABNQAFFAEIAQABAAAAAA==.Dandyrandy:BAAANQAECgcICwAAAA==.Dani:BAAANQAECgEIAgAAAA==.Dayday:BAAANQADCggIBwAAAA==.Dazzazn:BAAANQAECgEIAQAAAA==.',
De='Deathmaw:BAAANQABCgUIBQAAAA==.Decious:BAAANQADCgYIBgAAAA==.Deepfist:BAAANQAECgUIBwAAAA==.Defjam:BAAANQAECgQIBAAAAA==.Deidren:BAAANQABCgMIAwAAAA==.Delblade:BAAANQADCgcIDQAAAA==.Delicia:BAAANQAECgMIBAAAAA==.Dellbelphine:BAAANQAECgUICgAAAA==.Demonskii:BAAANQAECgQIBQAAAA==.Demton:BAAANQAECgUIBQAAAA==.',
Dh='Dhjck:BAAANQAECgUICgAAAA==.',
Di='Diatonic:BAAANQAECgYICwAAAA==.Direkau:BAAANQAECgcICwAAAA==.',
Do='Docroegames:BAAANQABCgYICQAAAA==.Dojaz:BAAANQAECgcIBwAAAA==.Dontouch:BAAANQADCggIFgAAAA==.Dorager:BAAANQADCgYICAAAAA==.',
Dr='Draconica:BAAANQAECgEIAgAAAA==.Dragedo:BAAANQADCgIIAgAAAA==.Dragonfella:BAAANQAECgIIAgAAAA==.Dragonkid:BAAANQADCgEIAQAAAA==.Drakewarden:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.Draktha:BAAANQAECgEIAgAAAA==.Dreddful:BAAANQAECgYICwAAAA==.Drkelso:BAAANQAECgUIBAAAAA==.',
Du='Duchalu:BAAANQAECgUIBwAAAA==.Dusklite:BAAANQADCgUIBQAAAA==.',
Eb='Ebbas:BAAANQADCgQIBgAAAA==.',
Ei='Eione:BAAANQAECgUIBwAAAA==.',
El='Elend:BAAANQADCgIIAgAAAA==.Elinez:BAAANQAECgIIAgAAAA==.Ellcrys:BAAANQADCgEIAQAAAA==.Elvinshiznic:BAAANQADCgQIBAAAAA==.',
Em='Emagine:BAAANQAECgUIBQAAAA==.Embra:BAAANQADCgcICgAAAA==.Emeraldbeast:BAAANQAECgcICwAAAA==.',
En='Endela:BAAANQADCggIBwAAAA==.Endelan:BAAANQADCgMIAwABNQADCggIBwABAAAAAA==.',
Er='Eroeda:BAAANQAECgQIBQAAAA==.',
Es='Escanør:BAAANQADCgcICQABNQAECgcIEAABAAAAAA==.',
Ex='Exo:BAAANQAECgYICwAAAA==.Exylan:BAAANQAECgYICgAAAA==.',
Ez='Ezsmash:BAAANQAECggIDgAAAA==.',
Fa='Fatgrlfriend:BAAANQAECgYIDwABNQAECgUIBgABAAAAAA==.',
Fe='Ferachio:BAAANQAECgIIAgAAAA==.',
Fh='Fhud:BAAANQADCgEIAQAAAA==.',
Fi='Fierysquish:BAAANQADCggIDAAAAA==.Filmnoir:BAAANQAECgQIBAAAAA==.',
Fl='Flinah:BAAANQABCgIIAgAAAA==.',
Fo='Foosaa:BAAANQADCgcIDgAAAA==.Forbearance:BAAANQAECgcICwAAAA==.',
Fr='Franco:BAAANQAECgQIBAAAAA==.Freshfresh:BAAANQADCggICAABNQAECggIDwABAAAAAA==.Freshlock:BAAANQAECggIDwAAAA==.Fright:BAAANQAECgUIBgAAAA==.Friska:BAAANQAECgQIBAAAAA==.Frostyp:BAABNQAECoEYAAMCAAkJJBcDCADXAgACAAkJJBcDCADXAgADAAEJwgETbwAoAAAAAA==.',
Fu='Funken:BAAANQADCgYIBwAAAA==.',
Fy='Fyre:BAAANQADCgEIAQABNQAECgcICgABAAAAAA==.Fyrebird:BAAANQAECgcICgAAAA==.',
Ga='Gahamachita:BAAANQADCgEIAQAAAA==.Galadhriel:BAAANQAECgUIBwAAAA==.Galadima:BAAANQAECgQIBgAAAA==.Ganador:BAAANQAECgcICwAAAA==.Garglon:BAAANQADCggICgAAAA==.Gatorrc:BAAANQADCgMIAwAAAA==.Gazzerfroz:BAAANQADCgYIBgAAAA==.',
Ge='Gellert:BAAANQAFFAIIAgAAAQ==.',
Gh='Ghostingyou:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.',
Gi='Gileon:BAAANQAECgcICAAAAA==.',
Gn='Gnomeofdeath:BAAANQAECgUIBgAAAA==.',
Go='Gorg:BAAANQAECgUICQAAAA==.',
Gr='Grashoppa:BAAANQADCgcIEQAAAA==.Greentide:BAAANQAECgUIBwAAAA==.Grimmothy:BAAANQADCggICAAAAA==.Grimore:BAAANQAECgUICQAAAA==.Groovybun:BAAANQADCgYIBgAAAA==.',
Gu='Guccimaybe:BAAANQAECgYIDAAAAA==.',
Gw='Gwynastrasza:BAABNQAFFIEJAAIEAAUJ2hReAQC7AQAEAAUJ2hReAQC7AQAAAA==.Gwynneth:BAAANQAECgMIAwABNQAFFAUICQAEANoUAA==.',
['Gü']='Güy:BAAANQADCgYIBgAAAA==.',
Ha='Haleluya:BAAANQADCgYICwABNQAECgMIBAABAAAAAA==.Halepurr:BAAANQAECgMIBAAAAA==.Halogenrofl:BAAANQAECgQIBwAAAA==.Hammerferge:BAAANQAECgYICgAAAA==.Hangezoë:BAAANQAECggIDgABNQAFFAIIAgABAAAAAQ==.Happa:BAAANQAECgcIEAAAAA==.Harbngerkhan:BAAANQAECgQIBQAAAA==.Hardok:BAAANQADCgEIAQAAAA==.',
He='Healroy:BAAANQADCggIEAAAAA==.Heidt:BAAANQAECgMIBAAAAA==.',
Ho='Holibeef:BAAANQAECgYICgAAAA==.Holysquish:BAAANQAECgcIDwAAAA==.Homoglobin:BAAANQADCgYIBgAAAA==.Honeydemon:BAAANQAECgcICwAAAA==.Hongis:BAAANQAECgUICQAAAA==.Hotdogsteve:BAAANQADCgMIAwAAAA==.',
Hu='Huge:BAAANQAECggICQAAAA==.Humi:BAAANQADCgYICwAAAA==.Huntskii:BAAANQAECgQIBQABNQAECgQIBQABAAAAAA==.',
Hw='Hwaryeong:BAAANQADCgYICwAAAA==.',
Ia='Iamluck:BAAANQAECgcIEQAAAA==.Iamluçk:BAAANQAECggICAAAAA==.',
Ic='Iceleaf:BAAANQAECgQIBQAAAA==.',
Il='Ileinaa:BAAANQAECgUICwAAAA==.Iliketrains:BAAANQAECgIIAgAAAA==.Ilovegrizzly:BAAANQAECgUIAQABNQAECgUICQABAAAAAA==.',
In='Indicud:BAAANQAECgEIAgAAAA==.Invvictis:BAAANQAECgUIBwAAAA==.',
Is='Isele:BAAANQADCgEIAQABNQADCggIBwABAAAAAA==.',
Ja='Jaymazing:BAAANQADCggICAABNQAECgcIDAABAAAAAA==.Jaysaurus:BAAANQAECgcIDAAAAA==.Jazzey:BAAANQAECggIEQAAAA==.',
Je='Jestyrddk:BAAANQAECgQIBQAAAA==.',
Jo='Jodox:BAAANQADCgMIAQAAAA==.Joehendry:BAAANQADCgcIEAAAAA==.Johnathonn:BAAANQAECgMIAwAAAA==.Joj:BAAANQAECgIIAQAAAA==.Jonthecron:BAAANQAECgQIBAAAAA==.Jormot:BAAANQADCgEIAQABNQAECgcICgABAAAAAA==.',
Ju='Juck:BAAANQAECgcIBwAAAA==.Justamage:BAAANQAECgIIAwAAAA==.Juw:BAAANQADCgcIBwAAAA==.',
Ka='Kalundia:BAAANQAECgUIBgAAAA==.Karkshammy:BAAANQAECggICgAAAA==.',
Ke='Keane:BAAANQAECgYICwAAAA==.Kellelor:BAAANQADCgQIBAAAAA==.Kelpie:BAAANQAECgEIAgAAAA==.',
Kh='Khanquest:BAAANQADCgQIBQAAAA==.',
Ki='Killkillkill:BAAANQABCgMIAwAAAA==.Kindassuddy:BAABNQAECoEdAAIFAAkJKRjPIQDMAgAFAAkJKRjPIQDMAgAAAA==.Kinvardar:BAAANQADCgYIBgAAAA==.Kirbbslav:BAAANQADCgEIAQABNQAECgkJGAAGAP8dAA==.Kirbislav:BAAANQAECgMIAwABNQAECgkJGAAGAP8dAA==.Kirbslav:BAABNQAECoEYAAIGAAkJ/x3GBQA0AwAGAAkJ/x3GBQA0AwAAAA==.Kirklandbeef:BAAANQADCgUIBQABNQADCggIDgABAAAAAA==.Kittykillerr:BAAANQADCgcIBwABNQAECgUIBgABAAAAAA==.',
Kn='Knata:BAAANQADCgcIBwAAAA==.Kniavez:BAAANQAECgUIBwAAAA==.',
Kr='Krak:BAAANQAECgEIAgAAAA==.Kruugh:BAAANQADCggIDQAAAA==.',
Ku='Kuler:BAAANQAECgQIBQAAAA==.Kungfustuff:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Kunguska:BAAANQADCgQIAgAAAA==.',
['Kè']='Kèèn:BAAANQAECgcIEQAAAA==.',
['Kí']='Kítkat:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.',
['Kÿ']='Kÿra:BAAANQADCgYIBgAAAA==.',
Le='Lectra:BAAANQABCgUIBgAAAA==.Lengthypally:BAAANQADCggICAAAAA==.',
Lo='Lodoss:BAAANQAECgUICQAAAA==.Lorienb:BAAANQAECgQICAAAAA==.',
Lu='Luckehlock:BAABNQAECoEYAAIHAAkJoSYDAAAIBAAHAAkJoSYDAAAIBAAAAA==.Lunaea:BAAANQAECgEIAQAAAA==.Luxcn:BAAANQADCgQIBAAAAA==.',
['Lú']='Lúffy:BAAANQADCggICAABNQAECgMIAwABAAAAAA==.',
Ma='Macdorn:BAAANQAECgYIBgAAAA==.Macgibbins:BAAANQAECgQIAwAAAA==.Magewindu:BAAANQAECgIIAgAAAA==.Magus:BAAANQAECgIIBwABNQAECgkJGAAIAD8mAA==.Malakar:BAAANQAECgEIAQAAAA==.Marhuon:BAAANQADCgEIAQAAAA==.Mavus:BAAANQADCgYIBgAAAA==.',
Me='Meanmyst:BAAANQADCgYICQAAAA==.',
Mi='Midgardsomr:BAAANQAECgEIAgAAAA==.Minagozap:BAAANQAECgIIAgAAAA==.Minityr:BAAANQAECgQIBAAAAA==.Minoritee:BAAANQAECgQIBQAAAA==.Mizukï:BAAANQAECgUIBAAAAA==.',
Mo='Molyver:BAAANQAECgYICwAAAA==.Momak:BAAANQADCgUICAABNQAECgQIBgABAAAAAA==.Mommey:BAAANQAECggIDQAAAA==.Moonmellow:BAAANQADCggIDAAAAA==.Moosin:BAAANQADCgYIBgAAAA==.Morel:BAAANQADCgYIBgAAAA==.Mositas:BAAANQABCgIIAgAAAA==.',
Mp='Mpatt:BAAANQADCgUIBgAAAA==.',
Mu='Munder:BAAANQAECgMIBAAAAA==.Murlockscry:BAAANQADCggIEAAAAA==.Musculate:BAAANQAECgcICAAAAA==.',
Mv='Mvdi:BAAANQADCggICAAAAA==.',
['Mï']='Mïssionary:BAAANQADCggIDwAAAA==.',
Na='Nartou:BAAANQABCgEIAQABNQADCgYIBgABAAAAAA==.',
Ne='Necrofearlia:BAAANQAECgUIBgAAAA==.Nekoashley:BAAANQADCgYICwAAAA==.',
Ni='Nick:BAABNQAECoEYAAIIAAkJPyZbAADyAwAIAAkJPyZbAADyAwAAAA==.Nightangelxx:BAAANQADCgUICgAAAA==.',
No='Noodle:BAAANQADCgEIAQAAAA==.Noolore:BAAANQAECggIEgAAAA==.Nosferatu:BAAANQADCgUICQAAAA==.',
Nu='Nurfhammer:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.Nurfshock:BAAANQAECgQIBAAAAA==.',
Ok='Okaybutwhy:BAAANQADCgYIBgAAAA==.Okiedk:BAAANQADCgcIBwAAAA==.',
Ox='Oxen:BAAANQAECgQICAAAAA==.',
Pa='Palendela:BAAANQAECgEIAQAAAA==.',
Pe='Penniee:BAAANQADCgUIBQAAAA==.Penniwing:BAAANQAECgQIBQAAAA==.Percival:BAEBNQAECoEYAAMJAAkJTyP0AQCZAwAJAAkJTyP0AQCZAwAKAAEJCA+VkgBAAAAAAA==.',
Ph='Phaedra:BAAANQAECgYIBwAAAQ==.Phealdh:BAAANQAECgUIBAAAAA==.',
Pi='Pillargodx:BAAANQADCgQIBAAAAA==.',
Pl='Plague:BAAANQAECgYIDQAAAA==.',
Pu='Pudpull:BAAANQADCgYIBgAAAA==.Pullbarg:BAAANQADCggIFwAAAA==.',
['Pï']='Pïng:BAAANQADCggIDgAAAA==.',
Qu='Quest:BAAANQAECgEIAQAAAA==.Quickwinnter:BAAANQAECgUICQAAAA==.Quickwinterg:BAAANQAECgEIAQABNQAECgUICQABAAAAAA==.Quickwinterm:BAAANQADCggICAABNQAECgUICQABAAAAAA==.',
Ra='Raantok:BAAANQABCgYIBgABNQADCgUICQABAAAAAA==.Raantokdh:BAAANQADCgUICQAAAA==.Raantoks:BAAANQADCgQIBAABNQADCgUICQABAAAAAA==.Rachet:BAAANQADCgYIDgAAAA==.Racoondots:BAAANQADCgYIBgAAAA==.Rakhár:BAAANQAECgEIAQAAAA==.Rakkdos:BAAANQADCgcIBwAAAA==.Rastaboss:BAAANQADCgUIBQAAAA==.Ratpackleadr:BAAANQAECgEIAQAAAA==.Rayado:BAAANQAECgYICQAAAA==.Rayadobane:BAAANQADCggICAAAAA==.',
Re='Rebelscum:BAAANQADCgUIBQAAAA==.Reggienoble:BAAANQAECgcICgAAAA==.Rekerî:BAAANQADCgEIAQABNQAECgkJFwAJANQiAA==.Resoran:BAAANQADCggIBgAAAA==.',
Ri='Rijit:BAAANQADCgYIDAAAAA==.Rinzlrr:BAAANQAECgYIBgABNQAECgYICwABAAAAAA==.Rippinzynz:BAAANQADCgIIAgAAAA==.',
Ro='Rockyshocky:BAAANQABCgQIBAABNQAECgUIBgABAAAAAA==.Rohrn:BAAANQAECgMIAwAAAA==.Rol:BAAANQAECgIIAwAAAA==.Rosahugs:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Ru='Ruggishbone:BAAANQAECgQIBAAAAA==.Ruinedmyth:BAAANQAECgEIAQAAAA==.',
Sa='Saintsnetie:BAAANQAECgIIAgAAAA==.',
Sc='Scottyknows:BAAANQAECgEIAQAAAA==.Scredwin:BAAANQAECgUIBwABNQAECgYIBwABAAAAAA==.Scrubadub:BAAANQAECgUIBwAAAA==.',
Se='Seeks:BAAANQABCgQIBQAAAA==.Senorbobo:BAAANQAECgUICAAAAA==.Senorxx:BAAANQADCgUIBwABNQAECgUICAABAAAAAA==.Serni:BAAANQAECgMIAwAAAA==.',
Sh='Shadei:BAAANQAECgIIBAAAAA==.Shadora:BAAANQADCgYIBgAAAA==.Shadowslite:BAAANQAECgEIAQAAAA==.Sham:BAAANQAECgcIDwAAAA==.Shamancheese:BAAANQADCgYIBgABNQADCggIDgABAAAAAA==.Shampayn:BAAANQADCgEIAQAAAA==.Shanksinatrá:BAABNQAECoEZAAQLAAkJnyITCgAfAgAMAAYJbSB2DAA7AgALAAYJwh4TCgAfAgANAAIJjxAHDQB/AAAAAA==.Shatt:BAAANQAECgIIAgAAAA==.Shedari:BAAANQAECgcIDQAAAA==.Shiftyjd:BAAANQADCgQIBAAAAA==.Shourix:BAAANQAECgUIBgAAAA==.',
Si='Sifushocks:BAAANQAECgMIAgAAAA==.Sihnn:BAAANQAECgUICgAAAA==.Simzerker:BAAANQAFFAMIAwAAAA==.Sitacha:BAAANQADCgEIAQAAAA==.',
Sk='Skrugeduc:BAAANQADCgYIDAAAAA==.',
Sl='Slamina:BAAANQAECgEIAQAAAA==.',
Sm='Smarts:BAAANQADCgcICQAAAA==.',
Sn='Sniiffle:BAAANQAECgMIBAAAAA==.Snowba:BAAANQADCgcICAAAAA==.',
Sp='Sparrowheart:BAAANQADCgYIBgAAAA==.Spellcrackle:BAAANQADCgcIBgABNQAECgYICgABAAAAAA==.Sprucejenner:BAAANQAECgUIBwAAAA==.',
Ss='Ssudds:BAAANQADCgUIBQABNQAECgkJHQAFACkYAA==.Ssuddy:BAAANQADCgYIBgABNQAECgkJHQAFACkYAA==.',
St='Starkisses:BAAANQAECgcICwAAAA==.Styrthe:BAABNQAECoEYAAMOAAkJGxS4BgBqAgAOAAkJGxS4BgBqAgAPAAMJORHJDwDPAAAAAA==.',
Su='Surventval:BAAANQADCgYIBwABNQAECgYICwABAAAAAA==.',
Sy='Symphony:BAAANQADCggICAABNQAECgYICwABAAAAAA==.',
['Sí']='Síra:BAAANQADCgIIAgABNQAECgYIDgABAAAAAA==.',
Ta='Taeka:BAAANQADCgYICQAAAA==.Taeshira:BAAANQAECgcIDAAAAA==.Talkimas:BAAANQAECgUIBwAAAA==.Talvisota:BAAANQAECgUIBAAAAA==.Tarirn:BAAANQAFFAIIAgAAAA==.Taunkaa:BAAANQADCggICAAAAA==.',
Te='Tekoslul:BAAANQAECggIDwAAAA==.Tekosmage:BAAANQABCgYICQAAAA==.Tekosxd:BAAANQADCggICAABNQAECggIDwABAAAAAA==.Teldragoose:BAAANQAECgMIAwAAAA==.Tendeda:BAAANQAECgcIDAAAAA==.',
Th='Thalunar:BAAANQAECgUICQAAAA==.Thatonedruid:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.Thelegendone:BAABNQAECoEXAAIGAAkJ6xxiBgAoAwAGAAkJ6xxiBgAoAwAAAA==.Thepenisadin:BAAANQAECgQIBAAAAA==.Thorck:BAAANQAECgQIBAAAAA==.Thugnakmunga:BAAANQADCggIDAAAAA==.Thundrcheeks:BAAANQAECgUIBQABNQAECgkJGgAQACwmAA==.',
Ti='Tidens:BAAANQADCgYIBgAAAA==.Tinklewinkle:BAAANQAECgQIBwAAAA==.Tirra:BAAANQADCgQIBAAAAA==.',
To='Tokapolo:BAAANQAECgQIBAAAAA==.Topher:BAAANQADCggIAQABNQAECggICQABAAAAAA==.Topshelfelf:BAAANQADCgcIEwAAAA==.',
Tr='Tresdin:BAAANQAECgQIBQAAAA==.Tresemme:BAAANQAECgIIAgAAAA==.',
Ts='Tsohg:BAAANQADCgUIBQABNQADCgYIDAABAAAAAA==.',
Tu='Tul:BAAANQAECgIIAgAAAA==.Tumlock:BAAANQAECgEIAgAAAA==.Turrok:BAAANQAECgUIBwAAAA==.',
['Tï']='Tïgra:BAAANQAECgUIBwAAAA==.',
Ua='Uandikillhim:BAAANQAECgYICgAAAA==.',
Um='Umbrä:BAAANQABCgIIAgAAAA==.',
Un='Undeadbones:BAAANQAECgIIAgAAAA==.Unfading:BAAANQAECgQIBgAAAA==.Unholyknight:BAAANQAECgYICgAAAA==.',
Ur='Urban:BAABNQAECoEVAAIFAAkJ5CBKDwBCAwAFAAkJ5CBKDwBCAwAAAA==.Urtark:BAAANQAECgcICgAAAA==.',
Us='Usui:BAAANQADCgUIBQAAAA==.',
Va='Vadym:BAAANQAECgIIAwAAAA==.Vail:BAAANQADCgEIAQABNQAECgYICgABAAAAAA==.Varalic:BAAANQAECggIBgABNQAECggIEwABAAAAAA==.Varandra:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.Vashet:BAAANQADCgcIBwAAAA==.',
Ve='Ventrois:BAAANQAECgYICwAAAA==.Veylynn:BAAANQADCgEIAQAAAA==.',
Vo='Voidalic:BAAANQAECggIEwAAAA==.Voidrend:BAABNQAECoEZAAQRAAkJ4B2oBgAfAwARAAkJ4B2oBgAfAwASAAIJkhFdLwBuAAATAAEJIxGSEAA1AAAAAA==.',
Vy='Vynese:BAAANQADCgUIBQAAAA==.',
['Vø']='Vøgue:BAAANQAECgcICwAAAA==.',
Wa='Warbidet:BAAANQADCgMIAwAAAA==.Warmason:BAAANQAECgUIBwAAAA==.Washed:BAAANQAECgUIBwAAAA==.',
We='Wealthy:BAAANQAECgUIBwAAAA==.',
Wh='Whispere:BAAANQAECgUICwAAAA==.',
Wi='Wiiska:BAAANQADCgQIBAAAAA==.',
Wr='Wrred:BAAANQADCgYIDAAAAA==.',
Ye='Yetifunk:BAAANQADCgYICgAAAA==.',
Yo='Yoloswagging:BAAANQADCgEIAQABNQAECgYICwABAAAAAA==.Yougotfuxed:BAAANQADCgEIAQAAAA==.Yourpal:BAAANQAECgcIDQAAAA==.',
Ze='Zemi:BAAANQAECgcICwAAAA==.Zenethrius:BAAANQABCgUIBAAAAA==.Zephang:BAAANQAECgcICwAAAA==.Zeros:BAAANQADCgYIBgAAAA==.Zevalia:BAAANQAECgQIBQAAAA==.',
Zl='Zlowwchain:BAAANQADCgUIBQAAAA==.',
Zo='Zophia:BAAANQADCgUIBwAAAA==.',
Zu='Zugrotic:BAAANQAECgQIBgAAAA==.Zumy:BAAANQAECgYIDwAAAA==.Zuzzy:BAAANQAECgEIAQAAAA==.',
['ßl']='ßlade:BAAANQABCgUIBQAAAA==.',
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
