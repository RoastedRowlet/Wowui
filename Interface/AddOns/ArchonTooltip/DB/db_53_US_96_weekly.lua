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

local lookup = {'Mage-Arcane','Unknown-Unknown','Hunter-BeastMastery','Paladin-Retribution','Warrior-Arms','Paladin-Holy','Priest-Shadow','Priest-Holy','Evoker-Preservation','Monk-Brewmaster','DemonHunter-Devourer','DeathKnight-Unholy','Warlock-Affliction','Druid-Balance','Priest-Discipline','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Paladin-Protection','Warrior-Fury','Monk-Mistweaver','Mage-Frost','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Elemental',}
local provider = {region='US',realm='Firetree',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Acanthiex:BAAANQADCgYIBgAAAA==.Ackbar:BAAANQAECgMIAwAAAA==.',
Ad='Adondias:BAAANQAECgYICgAAAA==.',
Ae='Aelana:BAAANQAECgUIBwAAAA==.',
Ag='Agrevail:BAAANQADCgYIBgAAAA==.',
Ak='Akryllic:BAAANQAECgQICAAAAA==.',
Al='Alamora:BAAANQAECgUIBQAAAA==.Aldari:BAAANQAECggIEgAAAA==.Allydk:BAAANQAECgcIEgAAAA==.Almorn:BAAANQAECgIIAgAAAA==.Alondrius:BAAANQADCgIIAgAAAA==.Altrag:BAAANQAECgcIEwAAAA==.Aluc:BAAANQAECgUICgAAAA==.',
An='Angestrypee:BAAANQAECgIIAgABNQAECgcIGwABAAUOAA==.Anslayer:BAAANQADCggIEQAAAA==.',
Ar='Archön:BAAANQAECgUICQAAAA==.Arctodus:BAAANQADCggICAAAAA==.Arks:BAAANQAECgQIBQAAAA==.',
As='Asperges:BAAANQAECgYIDAAAAA==.Astrellia:BAAANQADCgUIBwABNQADCggICAACAAAAAA==.',
Av='Averly:BAAANQADCgUIBQABNQAECgYIDQACAAAAAA==.Avralynia:BAAANQAECgIIAgAAAA==.Avrella:BAAANQADCgUIBQAAAA==.',
Ba='Babydaddyx:BAABNQAECoEZAAIDAAkJ2CVAAgC8AwADAAkJ2CVAAgC8AwABNQAECgcIDgACAAAAAA==.Baconn:BAABNQAECoEZAAIEAAkJBCNwBQCgAwAEAAkJBCNwBQCgAwAAAA==.Balun:BAAANQAECgEIAgAAAA==.',
Be='Beefdido:BAAANQAECgYIDAAAAA==.Beefstew:BAAANQAECgQIBgAAAA==.Belithe:BAAANQAECgIIAgAAAA==.Belletrixya:BAAANQAECgQIBgAAAA==.Belrandir:BAAANQADCgYICgAAAA==.Berrymanalow:BAAANQADCgYIBgAAAA==.',
Bi='Bijtoo:BAAANQAECgUICQAAAA==.Bingsoo:BAAANQAECgcIEgAAAA==.',
Bj='Bjarki:BAAANQADCgYIBgAAAA==.Bjorney:BAAANQAECgUICQAAAA==.',
Bl='Blankspace:BAAANQAECgUICgAAAA==.Blasphemar:BAAANQADCgYICQAAAA==.Blindvngence:BAAANQAECgYIDQAAAA==.Blizkit:BAAANQADCggIDQAAAA==.Bloodrayne:BAAANQAECgEIAgAAAA==.Bluedruid:BAAANQAFFAEIAQAAAA==.Blusloane:BAAANQAECgEIAQAAAA==.',
Bo='Bonkdeath:BAAANQADCgYICgABNQAFFAEIAQACAAAAAA==.Booms:BAAANQADCgYICwAAAA==.',
Br='Braintrust:BAAANQADCgcIBwAAAA==.Brezanyou:BAAANQADCgIIAgABNQAECgYIDwACAAAAAA==.Brobafett:BAAANQAECgQICAAAAA==.Brøx:BAAANQAECgUICQAAAA==.',
Bu='Bubbleblood:BAAANQADCgMIAwAAAA==.Bumfightbob:BAAANQADCggICQAAAA==.Bunnyboy:BAAANQADCggIEgAAAA==.Burlen:BAABNQAECoEXAAIBAAkJGSEXDQB6AwABAAkJGSEXDQB6AwAAAA==.',
['Bê']='Bênitora:BAAANQAECgcIEQAAAA==.',
['Bî']='Bîrth:BAAANQAECgYIEAAAAA==.',
Ca='Calic:BAAANQAECgYIDQAAAA==.Calryuu:BAAANQAECgUICgAAAA==.Cambiön:BAAANQAECgcIEAAAAA==.Capslock:BAAANQADCggIDAAAAA==.',
Ce='Cenno:BAAANQAECgMIAwAAAA==.Cern:BAAANQAECgMIAgAAAA==.',
Ch='Chadaclysm:BAAANQADCgcICgAAAA==.Chadotcom:BAAANQADCgQIBgAAAA==.Chantyu:BAAANQADCggIEAABNQAECgYIDwACAAAAAA==.Chickenman:BAABNQAECoEYAAIFAAgJ0BpgMwBuAgAFAAgJ0BpgMwBuAgAAAA==.Chinpokomon:BAAANQAECgcIDgAAAQ==.Choncc:BAAANQAECgUIBgAAAA==.Chonkykong:BAAANQAECgYICgAAAA==.Chubbychi:BAAANQADCgIIAgABNQAECgYIDwACAAAAAA==.Chuppy:BAAANQADCgcIDAAAAA==.',
Ci='Cinnapaw:BAAANQAECgEIAQAAAA==.',
Co='Codytwo:BAAANQAECgIIAgAAAA==.Coldstrype:BAABNQAECoEbAAIBAAcJBQ4YhwC4AQABAAcJBQ4YhwC4AQAAAA==.Cole:BAAANQAECgQICAAAAA==.Collonel:BAAANQAECgIIAgAAAA==.Connquest:BAAANQAECgEIAgAAAA==.Costcobeef:BAAANQADCggIDgAAAA==.Couchlocked:BAAANQADCgEIAQAAAA==.',
Cp='Cpt:BAAANQADCgEIAQAAAA==.Cptpeals:BAAANQADCgYIBgAAAA==.Cpttan:BAAANQAECgQIBAAAAA==.',
Cr='Critykity:BAAANQADCggIEAAAAA==.Critypally:BAAANQAECgUICwAAAA==.Crunkpickles:BAAANQADCggIFwAAAA==.',
Cv='Cvrcvss:BAAANQAECgcIDQAAAA==.',
Da='Dabadjuju:BAAANQADCgYIDAABNQAECgIIAgACAAAAAA==.Daerik:BAAANQAECgYIEQAAAA==.Dagoonfather:BAAANQAECgYIDgAAAA==.Dandochi:BAAANQAECgQIBAABNQAECgkJGQAGAFokAA==.Dandorllan:BAABNQAECoEZAAMGAAkJWiRAAQDCAwAGAAkJWiRAAQDCAwAEAAUJyyC3SgDLAQAAAA==.Dandowaz:BAAANQAECgQIBgABNQAECgkJGQAGAFokAA==.Dandyrandy:BAAANQAECgcIEgAAAA==.Dani:BAAANQAECgEIAgAAAA==.Dayday:BAAANQAECggICAAAAA==.Dazzazn:BAAANQAECgQIBQAAAA==.',
De='Deadstal:BAAANQAECggIBwAAAA==.Deathmaw:BAAANQABCgUIBQAAAA==.Decious:BAAANQADCgYIBgAAAA==.Deepfist:BAAANQAECgYIDQAAAA==.Defjam:BAAANQAECgYICgAAAA==.Deidren:BAAANQABCgMIAwAAAA==.Delblade:BAAANQAECgIIAgAAAA==.Delicia:BAAANQAECgQICAAAAA==.Dellbelphine:BAAANQAECgUIDgAAAA==.Demonskii:BAAANQAECgQIBQABNQAFFAEIAQACAAAAAA==.Demton:BAAANQAECgUICAAAAA==.Deusdux:BAAANQADCgMIAwAAAA==.',
Dh='Dhjck:BAAANQAECgUICgAAAA==.',
Di='Diatonic:BAAANQAECgcIDwAAAA==.Direkau:BAAANQAECgcIEgAAAA==.',
Do='Docroegames:BAAANQABCgcICgAAAA==.Dojaz:BAAANQAECgcIDgAAAA==.Dontouch:BAAANQAECgIIAgAAAA==.Dorager:BAAANQADCgYICAAAAA==.',
Dr='Draconica:BAAANQAECgEIAgAAAA==.Dragedo:BAAANQADCgIIAgAAAA==.Dragonfella:BAAANQAECgMIBQAAAA==.Dragonkid:BAAANQADCgEIAQAAAA==.Drakewarden:BAAANQADCgUIBQABNQAECgUICwACAAAAAA==.Draktha:BAAANQAECgEIAgAAAA==.Dreddful:BAAANQAECgYIEQAAAA==.Drkelso:BAAANQAECgUICQAAAA==.',
Du='Duchalu:BAAANQAECgYIDQAAAA==.Durtbag:BAAANQABCgMIAwAAAA==.Dusklite:BAAANQADCgUIBQAAAA==.',
Eb='Ebbas:BAAANQADCgQIBgAAAA==.',
Ei='Eione:BAAANQAECgYIDQAAAA==.',
El='Elend:BAAANQAECgIIAgAAAA==.Elinez:BAAANQAECgQIBQAAAA==.Ellcrys:BAAANQADCgcICAAAAA==.Elvinshiznic:BAAANQAECgMIBAAAAA==.',
Em='Emagine:BAAANQAECgcIDAAAAA==.Embra:BAAANQADCgcIDAAAAA==.Emeraldbeast:BAAANQAECgcIEgAAAA==.',
En='Endela:BAAANQADCggIBwABNQADCggICAACAAAAAA==.Endelan:BAAANQADCgMIAwABNQADCggICAACAAAAAA==.',
Er='Erissra:BAAANQADCgMIAwAAAA==.Eroeda:BAAANQAECgQIBQAAAA==.',
Es='Escanør:BAAANQADCgcICQABNQAECggIGAAFANAaAA==.',
Ex='Exo:BAAANQAECgcIEgAAAA==.Exylan:BAAANQAECgYIDwAAAA==.',
Ez='Ezsmash:BAAANQAECggIDwAAAA==.',
Fa='Fatgrlfriend:BAABNQAECoEWAAIEAAcJKiFlJACLAgAEAAcJKiFlJACLAgABNQAECgcIDgACAAAAAA==.',
Fe='Ferachio:BAAANQAECgIIAgAAAA==.',
Fh='Fhud:BAAANQADCgIIAwAAAA==.',
Fi='Fierysquish:BAAANQADCggIDAAAAA==.Filmnoir:BAAANQAECgUICQAAAA==.Fistferge:BAAANQADCgEIAQABNQAECgcIEQACAAAAAA==.',
Fl='Flinah:BAAANQABCgIIAgAAAA==.',
Fo='Foosaa:BAAANQADCgcIDgAAAA==.Forbearance:BAAANQAECgcIEgAAAA==.',
Fr='Franco:BAAANQAECgQICAAAAA==.Freshfresh:BAAANQADCggICAABNQAFFAIIAgACAAAAAA==.Freshlock:BAAANQAFFAIIAgAAAA==.Fright:BAAANQAECgUIBgAAAA==.Friska:BAAANQAECgUICAAAAA==.Frostyp:BAABNQAECoEgAAMHAAkJTxlVCgDcAgAHAAkJTxlVCgDcAgAIAAEJwgGRkgAlAAAAAA==.',
Fu='Funken:BAAANQADCgYIDAAAAA==.',
Fy='Fyre:BAAANQADCgUIBQABNQAECgcIEQACAAAAAA==.Fyrebird:BAAANQAECgcIEQAAAA==.',
Ga='Gahamachita:BAAANQADCgEIAQAAAA==.Galadhriel:BAAANQAECgYIDQAAAA==.Galadima:BAAANQAECggIDwAAAA==.Ganador:BAAANQAECgcIEgAAAA==.Garglon:BAAANQADCggICgAAAA==.Gatorrc:BAAANQADCgMIAwAAAA==.Gazzerfroz:BAAANQADCgYIBgAAAA==.',
Ge='Gellert:BAAANQAFFAMIBQAAAQ==.',
Gh='Ghostingyou:BAAANQADCgEIAQABNQAFFAEIAQACAAAAAA==.',
Gi='Gileon:BAAANQAECgcICQAAAA==.',
Gn='Gnomeofdeath:BAAANQAECgUIBgAAAA==.',
Go='Gomgar:BAAANQADCgQIBAAAAA==.Gorg:BAAANQAECgcIEAAAAA==.',
Gr='Grashoppa:BAAANQADCgcIEQAAAA==.Greentide:BAAANQAECgYIDQAAAA==.Grimmothy:BAAANQADCggICAAAAA==.Grimore:BAAANQAECgUICQAAAA==.Groovybun:BAAANQADCgYIBgAAAA==.',
Gu='Guccimaybe:BAAANQAECgcIEwAAAA==.',
Gw='Gwynastrasza:BAABNQAFFIEOAAIJAAUJVRXYAgCtAQAJAAUJVRXYAgCtAQAAAA==.Gwynneth:BAAANQAECgMIAwABNQAFFAUIDgAJAFUVAA==.',
['Gü']='Güy:BAAANQADCgYIBgAAAA==.',
Ha='Haleluya:BAAANQADCgYIDgABNQAECgMIBAACAAAAAA==.Halepurr:BAAANQAECgMIBAAAAA==.Halogenrofl:BAAANQAECgQIBwAAAA==.Hammerferge:BAAANQAECgcIEQAAAA==.Hangezoë:BAAANQAECggIDgABNQAFFAMIBQACAAAAAQ==.Happa:BAABNQAECoEbAAIKAAgJvhK4CADzAQAKAAgJvhK4CADzAQAAAA==.Harbngerkhan:BAAANQAECgUICgAAAA==.Hardok:BAAANQADCgEIAQAAAA==.',
He='Healroy:BAAANQADCggIFwAAAA==.Heidt:BAAANQAECgQICAAAAA==.Hellica:BAAANQADCgcIBwAAAA==.',
Ho='Holibeef:BAAANQAECgYIDwAAAA==.Holysquish:BAABNQAECoEbAAIEAAkJyBrzHgCtAgAEAAkJyBrzHgCtAgAAAA==.Homoglobin:BAAANQADCgYIBgAAAA==.Honeydemon:BAAANQAECgcIEgAAAA==.Honeydue:BAAANQADCgEIAgABNQAECgcIEQACAAAAAA==.Hongis:BAAANQAECgcIEAAAAA==.Hotdogsteve:BAAANQADCgMIAwAAAA==.',
Hu='Huge:BAAANQAECgcICgAAAA==.Humi:BAAANQADCgYICwAAAA==.Huntskii:BAAANQAFFAEIAQAAAA==.',
Hw='Hwaryeong:BAAANQADCgYIEQAAAA==.',
Ia='Iamluck:BAABNQAECoEbAAILAAgJCh15DQDCAgALAAgJCh15DQDCAgAAAA==.Iamluçk:BAAANQAFFAMIAwAAAA==.',
Ic='Iceleaf:BAAANQAECgYICwAAAA==.',
Il='Ileinaa:BAABNQAECoEYAAIIAAcJZxSwNwC5AQAIAAcJZxSwNwC5AQAAAA==.Iliketrains:BAAANQAECgIIAgAAAA==.Ilovegrizzly:BAAANQAECgUIAQABNQAECggICQACAAAAAA==.',
In='Indicud:BAAANQAECgEIAgAAAA==.Introvert:BAAANQABCgMIAwAAAA==.Invvictis:BAAANQAECgYIDQAAAA==.',
Is='Isele:BAAANQADCgEIAQABNQADCggICAACAAAAAA==.',
Ja='Jaymazing:BAAANQADCggICAABNQAECgcIDAACAAAAAA==.Jaysaurus:BAAANQAECgcIDAAAAA==.Jazzey:BAABNQAECoEZAAIMAAkJvRiWEQDHAgAMAAkJvRiWEQDHAgAAAA==.',
Je='Jestyrddk:BAAANQAECgUICgAAAA==.',
Jo='Jodox:BAAANQADCgMIAQAAAA==.Joehendry:BAAANQADCgcIEAAAAA==.Johnathonn:BAAANQAECgMIAwAAAA==.Joj:BAAANQAECgYIBwAAAA==.Jonthecron:BAAANQAECgUICQAAAA==.Jormot:BAAANQADCgYIBwABNQAECgcIEQACAAAAAA==.',
Ju='Juck:BAAANQAECgcICgAAAA==.Junkyo:BAAANQADCgYIBgAAAA==.Justamage:BAAANQAECgUICAAAAA==.Juw:BAAANQAECgEIAQAAAA==.',
Ka='Kalundia:BAAANQAECgYIDAAAAA==.Karkshammy:BAAANQAECgcIEQAAAA==.',
Ke='Keane:BAAANQAECgcIEgAAAA==.Kellelor:BAAANQADCgQIBAAAAA==.Kelpie:BAAANQAECgEIAgAAAA==.',
Kh='Khanquest:BAAANQADCgUICgAAAA==.',
Ki='Killkillkill:BAAANQADCggICAAAAA==.Kindassuddy:BAABNQAECoEjAAIBAAkJ0RhqNgC3AgABAAkJ0RhqNgC3AgAAAA==.Kinvardar:BAAANQADCgYIBgAAAA==.Kirbbslav:BAAANQADCgEIAQABNQAFFAUIBgAGAI0WAA==.Kirbislav:BAAANQAECgMIAwABNQAFFAUIBgAGAI0WAA==.Kirbslav:BAACNQAFFIEGAAIGAAUJjRaGAgC5AQAGAAUJjRaGAgC5AQA1AAQKgSEAAgYACQnGIhMDAJMDAAYACQnGIhMDAJMDAAAA.Kirklandbeef:BAAANQADCggIDQABNQADCggIDgACAAAAAA==.Kittykillerr:BAAANQADCgcIBwABNQAECgcIDgACAAAAAA==.',
Kn='Knata:BAAANQADCgcIBwAAAA==.Kniavez:BAAANQAECgUICgAAAA==.',
Kr='Krack:BAAANQAECgMIAwAAAA==.Krak:BAAANQAECgEIAwABNQAECgMIAwACAAAAAA==.Kruugh:BAAANQAECgMIAwAAAA==.',
Ku='Kuler:BAAANQAECgQIBQAAAA==.Kungfustuff:BAAANQADCgUIBQAAAA==.Kunguska:BAAANQADCgQIAgAAAA==.',
['Kè']='Kèèn:BAABNQAECoEXAAIEAAcJpSBDJgB/AgAEAAcJpSBDJgB/AgAAAA==.',
['Kí']='Kítkat:BAAANQADCgIIAgABNQADCggIDQACAAAAAA==.',
['Kÿ']='Kÿra:BAAANQADCgYIBgAAAA==.',
Le='Lectra:BAAANQABCgcICAAAAA==.Lengthypally:BAAANQADCggICAAAAA==.',
Li='Lilbeaner:BAAANQADCgcIBwAAAA==.',
Lo='Lodoss:BAAANQAECgYIDwAAAA==.Lorienb:BAAANQAECgYIDgAAAA==.',
Lu='Luckehlock:BAACNQAFFIEHAAINAAQJ9SMVAADBAQANAAQJ9SMVAADBAQA1AAQKgR8AAg0ACQnQJgQAABAEAA0ACQnQJgQAABAEAAAA.Lunaea:BAAANQAECgMIBAAAAA==.Luxcn:BAAANQADCgUIBwAAAA==.',
['Lú']='Lúffy:BAAANQAECgYIBgAAAA==.',
Ma='Macdorn:BAAANQAECgYIBgAAAA==.Macgibbins:BAAANQAECgMIAwAAAA==.Macgillivray:BAAANQAECgYIBgAAAA==.Magewindu:BAAANQAECgMIBQAAAA==.Magus:BAAANQAECgQICwABNQAECgkJIAAOAMAmAA==.Malakar:BAAANQAECgEIAQAAAA==.Marhuon:BAAANQADCgEIAQAAAA==.Mavus:BAAANQADCgYIBgAAAA==.',
Me='Meanmyst:BAAANQAECgIIAgAAAA==.',
Mi='Midgardsomr:BAAANQAECgYICAAAAA==.Mightbane:BAAANQAECggICAAAAA==.Minagozap:BAAANQAECgMIBQAAAA==.Minityr:BAAANQAECgYICgAAAA==.Minoritee:BAAANQAECgQIBwAAAA==.Mizukï:BAAANQAECgUICQAAAA==.',
Mo='Molyver:BAAANQAECgcIEgAAAA==.Momak:BAAANQADCgUICAABNQAECgUICwACAAAAAA==.Mommey:BAABNQAECoEYAAQPAAkJER2kAQDSAgAPAAgJJh6kAQDSAgAHAAcJ3BuQEQBMAgAIAAEJaRTFgwBMAAAAAA==.Moonmellow:BAAANQAECgEIAQAAAA==.Moosin:BAAANQADCgYIBgAAAA==.Morel:BAAANQADCgYIBgAAAA==.Mositas:BAAANQABCgIIAgAAAA==.',
Mp='Mpatt:BAAANQADCgUIBgAAAA==.',
Mu='Munder:BAAANQAECgQICAAAAA==.Murlockscry:BAAANQADCggIGAAAAA==.Musculate:BAAANQAECggIEAAAAA==.',
Mv='Mvdi:BAAANQAECgQIBAAAAA==.',
['Mï']='Mïssionary:BAAANQAECgIIAgAAAA==.',
Na='Nartou:BAAANQABCgEIAQABNQADCgYIBgACAAAAAA==.',
Ne='Necrofearlia:BAAANQAECgUICgAAAA==.Nekoashley:BAAANQADCgYIEQAAAA==.',
Ni='Nick:BAABNQAECoEgAAIOAAkJwCZKAAACBAAOAAkJwCZKAAACBAAAAA==.Nightangelxx:BAAANQADCgUICgAAAA==.',
No='Noodle:BAAANQADCgEIAQAAAA==.Noolore:BAABNQAECoEeAAIMAAkJ2yCbBwBSAwAMAAkJ2yCbBwBSAwAAAA==.Nosferatu:BAAANQADCgUICQAAAA==.Notrico:BAAANQADCgQIBAAAAA==.',
Nu='Nurfhammer:BAAANQADCgEIAQABNQAECgUICQACAAAAAA==.Nurfshock:BAAANQAECgUICQAAAA==.',
Oa='Oasis:BAAANQADCgYIBgAAAA==.',
Ok='Okaybutwhy:BAAANQADCgYIBgABNQAECgkJFwAEABskAA==.Okiedk:BAAANQADCgcIBwAAAA==.',
Ox='Oxen:BAAANQAECgYIDgAAAA==.',
Pa='Padraig:BAAANQADCgYIBgABNQADCgcIBwACAAAAAA==.Palendela:BAAANQAECgEIAQAAAA==.',
Pe='Penniee:BAAANQADCgUIBQAAAA==.Penniwing:BAAANQAECgUICgAAAA==.Percival:BAECNQAFFIEHAAIQAAQJcyCCAwCOAQAQAAQJcyCCAwCOAQA1AAQKgSAAAxAACQn/JE8CAJoDABAACQn/JE8CAJoDAAMAAQkID0HHAD8AAAAA.',
Ph='Phaedra:BAAANQAECgcIDgAAAQ==.Phealdh:BAAANQAECgUICQAAAA==.',
Pi='Pillargodx:BAAANQADCgQIBAAAAA==.Pixr:BAAANQAECggICAAAAA==.',
Pl='Plague:BAABNQAECoEVAAIMAAgJtxXrHwA7AgAMAAgJtxXrHwA7AgAAAA==.',
Pu='Pudpull:BAAANQADCgYIBgAAAA==.Pullbarg:BAAANQADCggIGwAAAA==.',
Py='Pyru:BAAANQAECgQIBAAAAA==.',
['Pï']='Pïng:BAAANQAECgQIBAAAAA==.',
Qu='Quest:BAAANQAECgEIAgAAAA==.Quickwinnter:BAAANQAECgcIDAABNQAECggICQACAAAAAA==.Quickwinterg:BAAANQAECggICQAAAA==.Quickwinterm:BAAANQAECgEIAQABNQAECggICQACAAAAAA==.',
Ra='Raantok:BAAANQADCgYIBgABNQADCggIDAACAAAAAA==.Raantokdh:BAAANQADCgUICQABNQADCggIDAACAAAAAA==.Raantoks:BAAANQADCgcICwABNQADCggIDAACAAAAAA==.Rachet:BAAANQADCgcIDwAAAA==.Racoondots:BAAANQADCgYIBgAAAA==.Rakhár:BAAANQAECgEIAQAAAA==.Rakkdos:BAAANQAECgQIBAAAAA==.Rastaboss:BAAANQADCgUIBQAAAA==.Ratpackleadr:BAAANQAECgEIAQAAAA==.Rayado:BAAANQAECgcIEQAAAA==.Rayadobane:BAAANQADCggICAAAAA==.Rayadosun:BAAANQADCgIIAgAAAA==.',
Re='Rebelscum:BAAANQADCgUIBQAAAA==.Reggienoble:BAAANQAECgcIEQAAAA==.Rekerî:BAAANQADCgEIAQABNQAFFAUICQAQAH8TAA==.Resoran:BAAANQADCggIBgAAAA==.',
Ri='Rijit:BAAANQADCgYIDAAAAA==.Rineda:BAAANQADCgQIBAAAAA==.Rinzlrr:BAAANQAECgYIDAABNQAECgYIDQACAAAAAA==.Rippinzynz:BAAANQADCgIIAgAAAA==.',
Ro='Rockyshocky:BAAANQABCgQIBAABNQAECgUIBgACAAAAAA==.Rohrn:BAAANQAECgQIBwAAAA==.Rol:BAAANQAECgIIAwAAAA==.Rosahugs:BAAANQAECgIIAgAAAA==.',
Ru='Ruggishbone:BAAANQAECgQIBAAAAA==.Ruinedmyth:BAAANQAECgQIBQAAAA==.',
Sa='Saintsnetie:BAAANQAECgUIBwAAAA==.',
Sc='Scottyknows:BAAANQAECgQIBQAAAA==.Scredwin:BAAANQAECgYIDQAAAA==.Scrubadub:BAAANQAECgYICwAAAA==.',
Se='Seeks:BAAANQADCgQIBAAAAA==.Senorbobo:BAAANQAECgYIDgAAAA==.Senorxx:BAAANQADCgYIDQABNQAECgYIDgACAAAAAA==.Serni:BAAANQAECgMIBAAAAA==.',
Sh='Shadei:BAAANQAECgIIBAAAAA==.Shadora:BAAANQADCgYIBgAAAA==.Shadowslite:BAAANQAECgMIBAAAAA==.Sham:BAABNQAECoEaAAMRAAgJEx7jJQBPAgARAAcJSB3jJQBPAgASAAUJwRW5GwBfAQAAAA==.Shamancheese:BAAANQADCgYIBgABNQADCggIDgACAAAAAA==.Shammpaignn:BAAANQADCgYIBgAAAA==.Shampayn:BAAANQAECgEIAQAAAA==.Shanksinatrá:BAACNQAFFIEJAAMTAAUJDRUPAwDKAAAUAAMJOA5gBAAOAQATAAIJTR8PAwDKAAA1AAQKgSIABBQACQnJJI0JAKICABQABgk5Jo0JAKICABMABglrH2sRACcCABUAAgmPEC8QAHsAAAAA.Shatt:BAAANQAECgUIBwAAAA==.Shedari:BAABNQAECoEVAAMEAAgJIxDdXACIAQAEAAcJ3g7dXACIAQAWAAEJCBnSOABCAAAAAA==.Shiftyjd:BAAANQADCgQIBAABNQADCgcICwACAAAAAA==.Shourix:BAAANQAECgcIDgAAAA==.',
Si='Sifushocks:BAAANQAECgUIBwAAAA==.Sihnn:BAAANQAECgcIEQAAAA==.Simzerker:BAABNQAECoEbAAMFAAkJPCOFCQCBAwAFAAkJPCOFCQCBAwAXAAIJyxFXFQBxAAAAAA==.Sitacha:BAAANQADCgEIAQAAAA==.',
Sk='Skrugeduc:BAAANQADCgYIDAABNQAECgMIAwACAAAAAA==.',
Sl='Slamina:BAAANQAECgEIAQAAAA==.Slowly:BAAANQAFFAIIAgAAAA==.',
Sm='Smarts:BAAANQAECgQIBAAAAA==.',
Sn='Sniiffle:BAAANQAECgQICAAAAA==.Snowba:BAAANQADCgcICAAAAA==.',
Sp='Sparrowheart:BAAANQADCgYICAAAAA==.Spellcrackle:BAAANQADCgcIBgABNQAECgYIDwACAAAAAA==.Sprucejenner:BAAANQAECgYIDQAAAA==.',
Ss='Ssudds:BAAANQAECgUIBQABNQAECgkJIwABANEYAA==.Ssuddy:BAAANQADCgYIBgABNQAECgkJIwABANEYAA==.',
St='Starkisses:BAAANQAECgcIEgAAAA==.Styrthe:BAABNQAECoEgAAMYAAkJihc5BwCmAgAYAAkJihc5BwCmAgAKAAMJORHXFADCAAAAAA==.',
Su='Surventval:BAAANQAECgEIAQABNQAECgYIDQACAAAAAA==.',
Sw='Sweetpickles:BAAANQADCgYIBgAAAA==.',
Sy='Symphony:BAAANQADCggICAABNQAECgcIDwACAAAAAA==.',
['Sí']='Síra:BAAANQADCgIIAgABNQAECggIGQAGAJweAA==.',
Ta='Taeka:BAAANQAECgIIAgAAAA==.Taeshira:BAAANQAECgcIEwAAAA==.Talkimas:BAAANQAECgYIDQAAAA==.Talvisota:BAAANQAECgUICQAAAA==.Tarirn:BAAANQAFFAIIAgAAAA==.Taunkaa:BAAANQAECgIIAgAAAA==.',
Te='Tekoslul:BAAANQAFFAIIAgAAAA==.Tekosmage:BAAANQABCgYICQAAAA==.Tekosxd:BAAANQADCggICAABNQAFFAIIAgACAAAAAA==.Teldragoose:BAAANQAECgUICAAAAA==.Tendeda:BAABNQAECoEXAAMBAAkJwxr4QACPAgABAAgJ9Rn4QACPAgAZAAIJvxXfFwCLAAAAAA==.',
Th='Thalunar:BAAANQAECgcIEAAAAA==.Thatonedruid:BAAANQADCgYIBgABNQAECgYIDgACAAAAAA==.Thelegendone:BAABNQAECoEgAAIGAAkJgCB2BgBUAwAGAAkJgCB2BgBUAwAAAA==.Thepenisadin:BAAANQAECgYICgAAAA==.Thorck:BAAANQAECgQICAAAAA==.Thugnakmunga:BAAANQADCggIEQAAAA==.Thundrcheeks:BAAANQAECgUIBgABNQAFFAMIBwAMAJ0bAA==.',
Ti='Tidens:BAAANQAECgEIAQAAAA==.Tinklewinkle:BAAANQAECgUIDAAAAA==.Tinygiant:BAAANQAECgMIAwAAAA==.Tirra:BAAANQADCgQIBAAAAA==.',
To='Tokapolo:BAAANQAECgQIBAAAAA==.Topshelfelf:BAAANQAECgMIAwAAAA==.',
Tr='Tresdin:BAAANQAECgcIDAAAAA==.Tresemme:BAAANQAECgMIBQAAAA==.',
Ts='Tsohg:BAAANQAECgMIAwAAAA==.',
Tu='Tul:BAAANQAECgIIAgABNQAECgYICAACAAAAAA==.Tumlock:BAAANQAECgQIBgAAAA==.Turrok:BAAANQAECgUIDAAAAA==.',
['Tï']='Tïgra:BAAANQAECgYIDQAAAA==.',
Ua='Uandikillhim:BAAANQAECggIEgAAAA==.',
Um='Umbrä:BAAANQABCgIIAgAAAA==.',
Un='Undeadbones:BAAANQAECgIIAgAAAA==.Unfading:BAAANQAECgYIDAAAAA==.Unholyknight:BAAANQAECgYIEAAAAA==.',
Ur='Urban:BAABNQAECoEdAAIBAAkJ1yIXEgBcAwABAAkJ1yIXEgBcAwAAAA==.Urtark:BAAANQAECgYIEAAAAA==.',
Us='Usui:BAAANQADCgUIBQAAAA==.',
Va='Vadym:BAAANQAECgIIBQAAAA==.Vail:BAAANQADCgEIAQABNQAECgYIDwACAAAAAA==.Varalic:BAAANQAECggIDAABNQAECgkJGAALAJYcAA==.Varandra:BAAANQADCgQIBAABNQAECgYIDwACAAAAAA==.Vashet:BAAANQADCgcIBwAAAA==.',
Ve='Veleno:BAAANQABCgIIAgAAAA==.Ventrois:BAAANQAECgYIDQAAAA==.Vespera:BAAANQABCgQIAgAAAA==.Veylynn:BAAANQADCgEIAQAAAA==.',
Vo='Voidalic:BAABNQAECoEYAAMLAAkJlhy7DQC9AgALAAkJnBu7DQC9AgAaAAIJpRclPgCgAAAAAA==.Voidrend:BAACNQAFFIEHAAMLAAQJXg6eAwBPAQALAAQJsQ2eAwBPAQAaAAEJRw36CgBOAAA1AAQKgSIABAsACQljHm8IABkDAAsACQljHm8IABkDABoAAwk0Dzo9AKgAABsAAQkjETAXADQAAAAA.',
Vy='Vynese:BAAANQADCgUIBQAAAA==.',
['Vø']='Vøgue:BAAANQAECgcIEgAAAA==.',
Wa='Warbidet:BAAANQAECgUIBgAAAA==.Warmason:BAAANQAECgYIDAAAAA==.Washed:BAAANQAECgUIDAAAAA==.',
We='Wealthy:BAAANQAECgYIDQAAAA==.',
Wh='Whispere:BAAANQAECgcIDgAAAA==.',
Wi='Wiiska:BAAANQADCgQIBAAAAA==.',
Wr='Wrred:BAAANQAECgIIAgAAAA==.',
Ye='Yetifunk:BAAANQADCgcIEQAAAA==.',
Yo='Yoloswagging:BAAANQADCgEIAQABNQAECgYICwACAAAAAA==.Yougotfuxed:BAAANQADCgEIAQAAAA==.Yourpal:BAAANQAECgcIEwAAAA==.',
Ze='Zemi:BAAANQAECgcIEgAAAA==.Zenethrius:BAAANQABCgUIBAAAAA==.Zephang:BAAANQAECgcIEgAAAA==.Zeros:BAAANQADCgYIBgAAAA==.Zevalia:BAAANQAECgQICQAAAA==.',
Zl='Zlowwchain:BAAANQADCgUIBQAAAA==.',
Zo='Zophia:BAAANQADCgUIBwAAAA==.',
Zu='Zugrotic:BAAANQAECgUICwAAAA==.Zumy:BAABNQAECoEVAAIcAAgJvx8XEgDyAgAcAAgJvx8XEgDyAgAAAA==.Zuzzy:BAAANQAECgEIAQAAAA==.',
['ße']='ßelle:BAAANQADCgUIBQAAAA==.',
['ßl']='ßlade:BAAANQADCgUIBQAAAA==.',
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
