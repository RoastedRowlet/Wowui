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

local lookup = {'Mage-Arcane','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Unknown-Unknown','Warlock-Demonology','Warrior-Fury','Paladin-Retribution','Paladin-Holy','Druid-Balance','Mage-Frost','Warlock-Destruction','Warrior-Arms','Rogue-Assassination','Monk-Brewmaster','Warrior-Protection','DemonHunter-Havoc','Mage-Fire','Shaman-Restoration','Druid-Restoration','Paladin-Protection','Warlock-Affliction','Priest-Shadow','Priest-Holy','Evoker-Devastation','Evoker-Preservation','Shaman-Enhancement','DemonHunter-Devourer','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Priest-Discipline','Hunter-Marksmanship','DeathKnight-Blood','Hunter-Survival','Rogue-Subtlety','Rogue-Outlaw','Druid-Guardian','DemonHunter-Vengeance',}
local provider = {region='US',realm='Firetree',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Acanthiex:BAAANQADCgcJBwAAAA==.Ackbar:BAAANQAECgMJAwAAAA==.',
Ad='Adondias:BAAANQAECgcIEQAAAA==.',
Ae='Aelana:BAAANQAECgcJDgAAAA==.',
Ak='Akryllic:BAAANQAECgYIDgAAAA==.',
Al='Alamora:BAAANQAECgYIBgAAAA==.Aldari:BAABNQAECoEXAAIBAAkK8CLOGQBQAwABAAkK8CLOGQBQAwAAAA==.Allydk:BAABNQAECoEdAAMCAAgKuh6EFADLAgACAAgKwh2EFADLAgADAAEKOwrIagA7AAAAAA==.Almorn:BAAANQAECgIIAgAAAA==.Alondrius:BAAANQADCgIJAgAAAA==.Altrag:BAABNQAECoEeAAIEAAgKnBcHOQBRAgAEAAgKnBcHOQBRAgAAAA==.Aluc:BAAANQAECgYJCwAAAA==.',
An='Angestrypee:BAAANQAECgIIAgABNQAECggIKgABAJoRAA==.Anslayer:BAAANQADCggIEQAAAA==.',
Ar='Archön:BAAANQAECgYJDwAAAA==.Arctodus:BAAANQADCggICAAAAA==.Arks:BAAANQAECgQIBQAAAA==.',
As='Asperges:BAAANQAECgcIEgAAAA==.Astrellia:BAAANQADCgUIBwABNQADCggICAAFAAAAAA==.',
Av='Averly:BAAANQADCgUIBQABNQAECgcJHAAGAI4YAA==.Avralynia:BAAANQAECgQJBgAAAA==.Avrella:BAAANQADCgYJCwABNQAECgQJBgAFAAAAAA==.',
Ba='Babydaddyx:BAACNQAFFIEHAAIEAAQKqhpqBAB4AQAEAAQKqhpqBAB4AQA1AAQKgSIAAgQACQorJlYBAOEDAAQACQorJlYBAOEDAAE1AAQKCAgbAAcAQyEA.Baconn:BAABNQAECoEbAAIIAAkKmiMKCQCQAwAIAAkKmiMKCQCQAwAAAA==.Balun:BAAANQAECgQJBgAAAA==.',
Be='Beefdido:BAAANQAECgYIEgAAAA==.Beefstew:BAAANQAECgcJDAAAAA==.Belithe:BAAANQAECgQIBgAAAA==.Belletrixya:BAAANQAECgUIDAAAAA==.Belrandir:BAAANQADCgYICgAAAA==.Berrymanalow:BAAANQADCgYIBgAAAA==.',
Bi='Bijtoo:BAAANQAECgUIDgAAAA==.Bingsoo:BAABNQAECoEdAAIBAAgKGhQfdwAvAgABAAgKGhQfdwAvAgAAAA==.Birdlaw:BAAANQADCgEJAQAAAA==.',
Bj='Bjarki:BAAANQADCgYIBgAAAA==.Bjorney:BAAANQAECgcJEAAAAA==.',
Bl='Blankspace:BAAANQAECgUIDgAAAA==.Blasphemar:BAAANQADCggJDAAAAA==.Blindvngence:BAAANQAECgcIDwAAAA==.Bloodrayne:BAAANQAECgEJAgAAAA==.Bluedruid:BAAANQAFFAEIAQAAAA==.Blusloane:BAAANQAECgEIAQAAAA==.',
Bo='Bonkdeath:BAAANQADCgYJCgABNQAFFAEIAQAFAAAAAA==.Booms:BAAANQADCgYICwAAAA==.',
Br='Braintrust:BAAANQADCgcIBwAAAA==.Brewkkake:BAAANQADCgcIBwAAAA==.Brezanyou:BAAANQADCgIIAgABNQAECggIFgAJAAQHAA==.Brobafett:BAAANQAECgUIDwAAAA==.Brøx:BAAANQAECgUJDgAAAA==.',
Bu='Bubbleblood:BAAANQADCgMIAwAAAA==.Bumfightbob:BAAANQAECgQIBQAAAA==.Bunnyboy:BAAANQAECgEJAQAAAA==.Burlen:BAABNQAECoEfAAIBAAkKvSKKDgCFAwABAAkKvSKKDgCFAwAAAA==.',
['Bê']='Bênitora:BAABNQAECoEaAAIKAAgK8w3kMADhAQAKAAgK8w3kMADhAQAAAA==.',
['Bî']='Bîrth:BAABNQAECoEbAAMLAAgKix8LBgAeAgALAAYKLSELBgAeAgABAAcKMRgrhAANAgAAAA==.',
Ca='Calic:BAABNQAECoEcAAMGAAcKjhj8aQCHAQAGAAUKdRj8aQCHAQAMAAIKzRiaQwCSAAAAAA==.Calryuu:BAAANQAECgYJEAAAAA==.Caltrask:BAAANQAECgIIAgAAAA==.Cambiön:BAABNQAECoEhAAILAAgKhSH9AQD+AgALAAgKhSH9AQD+AgAAAA==.Capslock:BAAANQAECgEJAQABNQAECgIIAwAFAAAAAA==.',
Ce='Cenno:BAAANQAECgcJCgAAAA==.Cern:BAAANQAECgMJAwAAAA==.',
Ch='Chadaclysm:BAAANQADCggJEgAAAA==.Chadotcom:BAAANQADCgQIBgAAAA==.Chantyu:BAAANQADCggIEAABNQAECggIFgAJAAQHAA==.Chickenman:BAABNQAECoEfAAINAAgKHB6jMwCaAgANAAgKHB6jMwCaAgAAAA==.Chinpokomon:BAAANQAECgcIFQAAAQ==.Choncc:BAAANQAECgUICAAAAA==.Chonkykong:BAAANQAECgcJEQAAAA==.Chubbychi:BAAANQADCgIIAgABNQAECggIFgAJAAQHAA==.Chuppy:BAAANQADCgcIDAABNQAECgUIDgAFAAAAAA==.',
Ci='Cinnapaw:BAAANQAECgEIAQAAAA==.',
Co='Codytwo:BAAANQAECgIIAgAAAA==.Coldstrype:BAABNQAECoEqAAIBAAgKmhHddwAtAgABAAgKmhHddwAtAgAAAA==.Cole:BAAANQAECgYIDgAAAA==.Collonel:BAAANQAECgIIAgAAAA==.Connquest:BAAANQAECgEIAgAAAA==.Costcobeef:BAAANQADCggIDgABNQADCggIEgAFAAAAAA==.Couchlocked:BAAANQADCggJCQAAAA==.',
Cp='Cpt:BAAANQADCgQJBQAAAA==.Cptpeals:BAAANQADCggJDQAAAA==.Cptsneck:BAAANQADCgMJAwAAAA==.Cpttan:BAAANQAECgUJCQAAAA==.',
Cr='Critykity:BAAANQAECgcJBwAAAA==.Critymage:BAAANQADCgEJAQAAAA==.Critypally:BAAANQAECgUICwAAAA==.Crunkpickles:BAAANQADCggIIAAAAA==.',
Cv='Cvrcvss:BAAANQAECgcIDQAAAA==.',
Da='Dabadjuju:BAAANQADCgYJDAABNQAECgIIAgAFAAAAAA==.Daerik:BAAANQAECgYIEQAAAA==.Dagoonfather:BAABNQAECoEgAAIOAAcKKRaRHQD2AQAOAAcKKRaRHQD2AQAAAA==.Dandochi:BAAANQAECgQIBQABNQAFFAMJBgAJAHshAA==.Dandorllan:BAACNQAFFIEGAAMJAAMKeyH2DADFAAAJAAIKyCH2DADFAAAIAAEKnQFCHQA8AAA1AAQKgSQAAwkACQo0JUIBAM8DAAkACQo0JUIBAM8DAAgABQrZIFBtALUBAAAA.Dandowaz:BAAANQAECgQIBwABNQAFFAMJBgAJAHshAA==.Dandyrandy:BAABNQAECoEdAAMJAAgKnxVdMAA9AgAJAAgKnxVdMAA9AgAIAAEKWARwLAEtAAAAAA==.Dani:BAAANQAECgEIAgAAAA==.Dayday:BAAANQAECggICAAAAA==.Dazzazn:BAAANQAECgQJBQAAAA==.',
De='Deadstal:BAAANQAECggIDgAAAA==.Deathmaw:BAAANQABCgUIBQAAAA==.Decious:BAAANQAECgEJAQAAAA==.Dedoinmyass:BAAANQADCgQIBAAAAA==.Deepfist:BAABNQAECoEYAAIPAAgKgCHKAwD+AgAPAAgKgCHKAwD+AgAAAA==.Defjam:BAAANQAECgYIEAAAAA==.Deidren:BAAANQABCgMIAwAAAA==.Delblade:BAAANQAECgIIAgAAAA==.Delicia:BAAANQAECgYJDgAAAA==.Dellbelphine:BAABNQAECoEXAAMIAAcK6hh2UwAJAgAIAAcK6hh2UwAJAgAJAAQKYArMlwDWAAAAAA==.Demonskii:BAAANQAECgYIDQABNQAFFAEIAQAFAAAAAA==.Demton:BAAANQAECgUICAAAAA==.Deusdux:BAAANQADCgMIAwAAAA==.',
Dh='Dhjck:BAAANQAECgUICgAAAA==.',
Di='Diatonic:BAAANQAECggIEQAAAA==.Direkau:BAABNQAECoEdAAIQAAgKoiRFAgBKAwAQAAgKoiRFAgBKAwAAAA==.',
Do='Docroegames:BAAANQABCgcJDAAAAA==.Dojaz:BAABNQAECoEZAAIRAAgKNQ33JADrAQARAAgKNQ33JADrAQAAAA==.Dontouch:BAAANQAECgIJAgAAAA==.Dorager:BAAANQADCgYICAAAAA==.',
Dr='Draconica:BAAANQAECgIIBAAAAA==.Dragedo:BAAANQADCgIIAgAAAA==.Dragonfella:BAAANQAECgMJBgAAAA==.Dragonkid:BAAANQADCgEIAQAAAA==.Drakewarden:BAAANQADCgUIBQABNQAECgYJDAAFAAAAAA==.Draktha:BAAANQAECgIIAwAAAA==.Dreddful:BAABNQAECoEbAAISAAgKWhUtAQBaAgASAAgKWhUtAQBaAgAAAA==.Drer:BAAANQADCgMJAwAAAA==.Drkelso:BAAANQAECgUIDgAAAA==.',
Du='Duchalu:BAABNQAECoEYAAMNAAgKpAk3dACvAQANAAgKpAk3dACvAQAHAAEKwgl0IwAxAAAAAA==.Durtbag:BAAANQABCgMIAwAAAA==.Dusklite:BAAANQADCgUIBQAAAA==.',
Eb='Ebbas:BAAANQADCgQIBgAAAA==.',
Ei='Eione:BAAANQAECgYJEwAAAA==.',
El='Elend:BAAANQAECgQJBgAAAA==.Elinez:BAAANQAECgUIBgAAAA==.Ellcrys:BAAANQADCggJDwAAAA==.Elvinshiznic:BAAANQAECgUJCQAAAA==.',
Em='Emagine:BAABNQAECoEWAAITAAkKtB2YDgAUAwATAAkKtB2YDgAUAwAAAA==.Embra:BAAANQADCgcJDAAAAA==.Emeraldbeast:BAAANQAECgcJEgAAAA==.',
En='Endela:BAAANQADCggIBwABNQADCggICAAFAAAAAA==.Endelan:BAAANQADCgMIAwABNQADCggICAAFAAAAAA==.Endelen:BAAANQAECgEIAQAAAA==.',
Er='Erissra:BAAANQADCgMIAwAAAA==.Eroeda:BAAANQAECgYJCwAAAA==.',
Es='Escanør:BAAANQADCgcICQABNQAECggJHwANABweAA==.',
Ex='Exo:BAABNQAECoEdAAIUAAgKTCRFBQA0AwAUAAgKTCRFBQA0AwAAAA==.Exylan:BAABNQAECoEXAAIIAAgKKxdMSwAnAgAIAAgKKxdMSwAnAgAAAA==.',
Ez='Ezsmash:BAAANQAECggIEAAAAA==.',
Fa='Fatgrlfriend:BAABNQAECoEeAAIIAAkKXCJbDQBpAwAIAAkKXCJbDQBpAwABNQAECggIGwAHAEMhAA==.',
Fe='Ferachio:BAAANQAECgIIAgAAAA==.',
Ff='Ffreshmage:BAAANQAECgMJAwABNQAECgkJGAAGAB8jAA==.',
Fh='Fhud:BAAANQADCgIIAwAAAA==.',
Fi='Fierysquish:BAAANQADCggIDAAAAA==.Filmnoir:BAAANQAECgYJDwAAAA==.Fistferge:BAAANQADCgEIAQABNQAECggJGwAVAIchAA==.',
Fl='Flinah:BAAANQABCgIJAgAAAA==.',
Fo='Foosaa:BAAANQAECgMJAwAAAA==.Forbearance:BAABNQAECoEdAAIVAAgKsRwLCgCOAgAVAAgKsRwLCgCOAgAAAA==.Forgotss:BAAANQAECgQJBAAAAA==.',
Fr='Franco:BAAANQAECgcJDwAAAA==.Freshfresh:BAAANQADCggICAABNQAECgkJGAAGAB8jAA==.Freshlock:BAABNQAECoEYAAQGAAkKHyOrJwCEAgAGAAcKgiCrJwCEAgAMAAQK/CHpHABnAQAWAAIK9SFvEADAAAAAAA==.Fright:BAAANQAECgUIBgAAAA==.Friska:BAAANQAECgUJCAAAAA==.Frostyp:BAACNQAFFIEIAAIXAAMKCQonCADiAAAXAAMKCQonCADiAAA1AAQKgSMAAxcACQoDG3YNAMkCABcACQoDG3YNAMkCABgAAQrCAa20ACQAAAAA.',
Fu='Funken:BAAANQADCggJFAAAAA==.',
Fy='Fyre:BAAANQADCgUJBgABNQAECgkJGAAZACAWAA==.Fyrebird:BAABNQAECoEYAAMZAAkKIBZwCwBpAgAZAAkKIBZwCwBpAgAaAAMKOgtfLwCdAAAAAA==.',
Ga='Gahamachita:BAAANQADCgEIAQAAAA==.Galadhriel:BAABNQAECoEYAAIUAAgKdxgrEgBGAgAUAAgKdxgrEgBGAgAAAA==.Galadima:BAABNQAECoEYAAIJAAgKXB1/HACwAgAJAAgKXB1/HACwAgAAAA==.Ganador:BAABNQAECoEdAAMGAAgKbR6ILABuAgAGAAcKvx6ILABuAgAMAAIKtRrVQgCVAAAAAA==.Garglon:BAAANQADCggICgAAAA==.Gatorrc:BAAANQADCgMJAwAAAA==.Gazzerfroz:BAAANQADCgYIBgABNQAECgMJAwAFAAAAAA==.',
Gh='Ghostingyou:BAAANQADCgUJBgABNQAFFAEIAQAFAAAAAA==.',
Gi='Gilburt:BAABNQAFFIEMAAIGAAUKKBD+BAB9AQAGAAUKKBD+BAB9AQAAAA==.Gileon:BAAANQAECgcICQAAAA==.',
Gn='Gnomeofdeath:BAAANQAECgYJCQAAAA==.',
Go='Gomgar:BAAANQADCgUICAAAAA==.Gorg:BAAANQAECgcJEQAAAA==.',
Gr='Grashoppa:BAAANQADCgcIEQAAAA==.Greentide:BAABNQAECoEZAAITAAkKrxTcLgA/AgATAAkKrxTcLgA/AgAAAA==.Grimmothy:BAAANQADCggJEAAAAA==.Grimore:BAAANQAECgUICQAAAA==.Groovybun:BAAANQADCgYIBgAAAA==.',
Gu='Guccimaybe:BAABNQAECoEZAAIbAAcKfQ1NEADiAQAbAAcKfQ1NEADiAQAAAA==.',
Gw='Gwynastrasza:BAACNQAFFIEUAAIaAAcKNxNiAQBcAgAaAAcKNxNiAQBcAgA1AAQKgRgAAhoACQrGHIoIAOUCABoACQrGHIoIAOUCAAAA.Gwynneth:BAAANQAECgMJAwABNQAFFAcJFAAaADcTAA==.',
['Gü']='Güy:BAAANQAECgMIAwAAAA==.',
Ha='Haleluya:BAAANQADCgYIDgABNQAECgMIBAAFAAAAAA==.Halepurr:BAAANQAECgMIBAAAAA==.Halogenrofl:BAAANQAECgcJDgAAAA==.Hammerferge:BAABNQAECoEbAAIVAAgKhyFoBgD2AgAVAAgKhyFoBgD2AgAAAA==.Hangezoë:BAAANQAECggIDgAAAQ==.Happa:BAABNQAECoEgAAIPAAgKCRZYCgACAgAPAAgKCRZYCgACAgAAAA==.Harbngerkhan:BAAANQAECgUJDgAAAA==.Hardok:BAAANQADCgEIAQAAAA==.Hashishi:BAAANQADCgEIAQAAAA==.',
He='Healroy:BAAANQADCggIHgAAAA==.Heidt:BAAANQAECgUJDQAAAA==.Hellica:BAAANQADCgcIDgAAAA==.',
Ho='Holibeef:BAABNQAECoEWAAMJAAgKBAc5WACTAQAJAAgKBAc5WACTAQAIAAEK2AEnPAEgAAAAAA==.Holysquish:BAABNQAECoEfAAIIAAkKSh2WKwCuAgAIAAkKSh2WKwCuAgAAAA==.Homoglobin:BAAANQADCgYIBgAAAA==.Honeydemon:BAABNQAECoEdAAIRAAgKthMBIAAbAgARAAgKthMBIAAbAgAAAA==.Honeydue:BAAANQADCgEJAwABNQAECgkJGAAZACAWAA==.Hongis:BAABNQAECoEXAAMBAAcK9hY7iQD/AQABAAcK9hY7iQD/AQALAAEKTQUiNwAmAAAAAA==.Horsefuneral:BAAANQADCgQIBAABNQADCggIIAAFAAAAAA==.Hotdogsteve:BAAANQADCgMIAwAAAA==.',
Hu='Huge:BAAANQAECgcJDAAAAA==.Humi:BAAANQADCgYICwAAAA==.Huntskii:BAAANQAFFAEIAQAAAA==.',
Hw='Hwaryeong:BAAANQAECgEIAgAAAA==.',
Ia='Iamluck:BAABNQAECoEeAAIcAAkKnh6uCgAGAwAcAAkKnh6uCgAGAwAAAA==.Iamluçk:BAAANQAFFAMIAwAAAA==.',
Ic='Iceleaf:BAAANQAECgYICwAAAA==.',
Il='Ileinaa:BAABNQAECoEoAAIYAAgKnBexKQBYAgAYAAgKnBexKQBYAgAAAA==.Iliketrains:BAAANQAECgYJCAAAAA==.Ilovegrizzly:BAAANQAECgUJAgABNQAECggIEgAFAAAAAA==.',
In='Indicud:BAAANQAECgEIAgAAAA==.Introvert:BAAANQABCgMIAwAAAA==.Invvictis:BAAANQAECgcIDgAAAA==.',
Is='Isele:BAAANQADCgEIAQABNQADCggICAAFAAAAAA==.',
Ja='Jaymazing:BAAANQADCggJCAABNQAECgcJEwAFAAAAAA==.Jaysaurus:BAAANQAECgcJEwAAAA==.Jazzey:BAABNQAECoEbAAICAAkKhxsSFQDGAgACAAkKhxsSFQDGAgAAAA==.',
Je='Jestyrddk:BAAANQAECgUICgABNQAECgYJBgAFAAAAAA==.',
Jo='Jodox:BAAANQADCgMJAQAAAA==.Joehendry:BAAANQADCgcIEAAAAA==.Johnathonn:BAAANQAECgMJBAAAAA==.Joj:BAAANQAECgYIDQAAAA==.Jonthecron:BAAANQAECgUIDQAAAA==.Jormot:BAAANQADCgYJBwABNQAECgkJGAAZACAWAA==.Jowl:BAAANQADCgMIAwAAAA==.',
Ju='Juck:BAAANQAECggIDQAAAA==.Junkyo:BAAANQAECgEIAgAAAA==.Justamage:BAAANQAECgYIDgAAAA==.Juw:BAAANQAECgEIAQAAAA==.',
Ka='Kalundia:BAAANQAECgYIDAAAAA==.Karkshammy:BAABNQAECoEYAAIdAAkKFxp3IACsAgAdAAkKFxp3IACsAgAAAA==.',
Ke='Keane:BAABNQAECoEdAAINAAgK6gkzdQCsAQANAAgK6gkzdQCsAQAAAA==.Kellelor:BAAANQADCgQIBAAAAA==.Kelpie:BAAANQAECgEIAwAAAA==.',
Kh='Khanquest:BAAANQAECgEIAQAAAA==.',
Ki='Killkillkill:BAAANQADCggJEAAAAA==.Kindassuddy:BAABNQAECoEkAAIBAAkKtxlOSwCpAgABAAkKtxlOSwCpAgAAAA==.Kinvardar:BAAANQAECgMIAwAAAA==.Kirbbslav:BAAANQADCgEIAQABNQAFFAYJCwAJAGoVAA==.Kirbislav:BAAANQAECgMIAwABNQAFFAYJCwAJAGoVAA==.Kirbslav:BAACNQAFFIELAAIJAAYKahVQAgALAgAJAAYKahVQAgALAgA1AAQKgSQAAgkACQrGIhoFAIQDAAkACQrGIhoFAIQDAAAA.Kirklandbeef:BAAANQADCggIEgAAAA==.Kittykillerr:BAAANQADCgcJBwABNQAECggIGwAHAEMhAA==.',
Kn='Knata:BAAANQADCgcICwAAAA==.Kniavez:BAAANQAECgYJCwAAAA==.',
Kr='Krack:BAAANQAECgMIAwAAAA==.Krak:BAAANQAECgEIAwABNQAECgMIAwAFAAAAAA==.Kruugh:BAAANQAECgQJBwAAAA==.',
Ku='Kuler:BAAANQAECgYIDQAAAA==.Kungfustuff:BAAANQADCgUIBQABNQAECgQIBwAFAAAAAA==.Kunguska:BAAANQADCgQIAgAAAA==.',
['Kè']='Kèèn:BAABNQAECoEXAAIIAAcKpSAtPQBeAgAIAAcKpSAtPQBeAgAAAA==.',
['Kì']='Kìt:BAAANQADCggIEQAAAA==.',
['Kí']='Kítkat:BAAANQADCgIIAgABNQADCggIEQAFAAAAAA==.',
['Kÿ']='Kÿra:BAAANQADCgYIBgAAAA==.',
La='Lavage:BAAANQAECgEJAQAAAA==.',
Le='Lectra:BAAANQABCgcICAAAAA==.Lengthypally:BAAANQADCggICAAAAA==.',
Li='Liakä:BAAANQAECgQIBAABNQAECgUIBQAFAAAAAA==.Lilbeaner:BAAANQADCggJDgAAAA==.Liratha:BAAANQAECgYJBgAAAA==.',
Lo='Lodoss:BAAANQAECgcJEAAAAA==.Lorienb:BAAANQAECgcIEwAAAA==.',
Lu='Luckehlock:BAACNQAFFIELAAIWAAUK3CUYAAAtAgAWAAUK3CUYAAAtAgA1AAQKgSYAAhYACQrmJgMAABkEABYACQrmJgMAABkEAAAA.Lunaea:BAAANQAECgUJCQAAAA==.Luxcn:BAAANQADCgUJBwAAAA==.',
['Lú']='Lúffy:BAAANQAECgYIBgABNQAECgcJDQAFAAAAAA==.',
Ma='Macdorn:BAAANQAECgYIBgAAAA==.Macgibbins:BAAANQAECgQIBAAAAA==.Macgillivray:BAAANQAECgYIDAAAAA==.Magewindu:BAAANQAECgQJCAAAAA==.Magus:BAAANQAECgQICwABNQAECgkJIAAKAMAmAA==.Malakar:BAAANQAECgEIAQAAAA==.Mardin:BAAANQADCgEJAQAAAA==.Marhuon:BAAANQADCgEIAQAAAA==.Mavus:BAAANQADCgYIBgAAAA==.',
Me='Meanmyst:BAAANQAECgIIAgAAAA==.',
Mi='Midgardsomr:BAAANQAECgYICgAAAA==.Mightbane:BAAANQAECggICwAAAA==.Mikebroowwnn:BAAANQADCgEIAQAAAA==.Milkmytotems:BAAANQAECgQIBAABNQAECggIGwAHAEMhAA==.Minagozap:BAAANQAECgYICwAAAA==.Minityr:BAAANQAECgYIEAAAAA==.Minoritee:BAAANQAECgQIBwAAAA==.Mizukï:BAAANQAECgUIDAAAAA==.',
Mo='Molyver:BAABNQAECoEbAAMeAAgKCBoSEQBlAgAeAAgKCBoSEQBlAgAfAAEKBAOIOwAlAAAAAA==.Momak:BAAANQADCgUICAABNQAECgcJEgAFAAAAAA==.Mommey:BAABNQAECoEcAAQgAAkKwB0wAgC/AgAgAAgKJh4wAgC/AgAXAAcK8hvUFgA3AgAYAAQKqBxvXABnAQAAAA==.Moonmellow:BAAANQAECgIIAwAAAA==.Moosin:BAAANQADCgYIBgAAAA==.Morel:BAAANQADCgYIBgAAAA==.Mositas:BAAANQABCgIIAgAAAA==.',
Mp='Mpatt:BAAANQADCgUIBgAAAA==.',
Mu='Munder:BAAANQAECgQJCwAAAA==.Murlockscry:BAAANQADCggJGAAAAA==.Musculate:BAABNQAECoEZAAIhAAkKISHrBQBQAwAhAAkKISHrBQBQAwAAAA==.',
Mv='Mvdi:BAAANQAECgUICgAAAA==.',
My='Myranda:BAAANQADCgYJBgAAAA==.',
['Mï']='Mïssionary:BAAANQAECgIIAgAAAA==.',
Na='Nartou:BAAANQAECgMJAwAAAA==.',
Ne='Necrofearlia:BAAANQAECgUIDQAAAA==.Nekoashley:BAAANQAECgEIAgAAAA==.',
Ni='Nick:BAABNQAECoEgAAIKAAkKwCaxAADvAwAKAAkKwCaxAADvAwAAAA==.Nightangelxx:BAAANQADCgYJEAAAAA==.',
No='Noodle:BAAANQADCgEIAQAAAA==.Noolore:BAABNQAECoEiAAICAAkKRiFnCQBMAwACAAkKRiFnCQBMAwAAAA==.Nosferatu:BAAANQAECgIJAgAAAA==.Notrico:BAAANQADCgQIBAAAAA==.',
Nu='Nurfhammer:BAAANQADCgEIAQABNQAECgUIDgAFAAAAAA==.Nurfshock:BAAANQAECgUIDgAAAA==.',
Oa='Oasis:BAAANQADCgYJCAAAAA==.',
Ok='Okaybutwhy:BAAANQADCgYIBgABNQAECgkJIAAIAG8lAA==.Okiedk:BAAANQAECgQJBAAAAA==.',
On='Onefelswoop:BAAANQAECgMJAwAAAA==.',
Ox='Oxen:BAABNQAECoEXAAMiAAcKXBuWLQD1AQAiAAYKehyWLQD1AQACAAUKrw5yVQAlAQAAAA==.',
Pe='Penniee:BAAANQADCgUJBQAAAA==.Penniwing:BAAANQAECgYJEAAAAA==.Percival:BAECNQAFFIEMAAIhAAUKzB/vAgDmAQAhAAUKzB/vAgDmAQA1AAQKgSMAAyEACQpBJecCAJYDACEACQpBJecCAJYDAAQAAQoID0LxAD4AAAAA.',
Ph='Phaedra:BAAANQAECgcIFQAAAQ==.Phealdh:BAAANQAECgUIDgAAAA==.',
Pi='Pillargodx:BAAANQADCgQIBAAAAA==.Pixr:BAAANQAECggICAAAAA==.',
Pl='Plague:BAABNQAECoEcAAICAAgKMBrhHAB/AgACAAgKMBrhHAB/AgAAAA==.',
Po='Police:BAAANQABCgQJBAABNQAECgcJEgAFAAAAAA==.',
Pu='Pudpull:BAAANQADCgYIBgAAAA==.Pullbarg:BAAANQADCggJHwAAAA==.',
Py='Pyru:BAAANQAECgQIBAAAAA==.',
['Pï']='Pïng:BAAANQAECgUIBQAAAA==.',
Qu='Quest:BAAANQAECgEIAwAAAA==.Quickwinnter:BAAANQAECggIEgAAAA==.Quickwinterg:BAAANQAECggJCgABNQAECggIEgAFAAAAAA==.Quickwinterm:BAAANQAECggJCAABNQAECggIEgAFAAAAAA==.',
Ra='Raantok:BAAANQADCgYIBgABNQAECgIIAwAFAAAAAA==.Raantokdh:BAAANQADCgUICQABNQAECgIIAwAFAAAAAA==.Raantoks:BAAANQAECgIIAwAAAA==.Rachet:BAAANQAECgQJBAAAAA==.Racoondots:BAAANQADCgYIBgAAAA==.Rakhár:BAAANQAECgEIAQAAAA==.Rakkdos:BAAANQAECgQIBAAAAA==.Rastaboss:BAAANQADCgUIBQAAAA==.Ratpackleadr:BAAANQAECgEIAQAAAA==.Rayado:BAABNQAECoEfAAMJAAkKNhCqMgAyAgAJAAkKNhCqMgAyAgAIAAEKFgXKKwEuAAAAAA==.Rayadobane:BAAANQADCggICAAAAA==.Rayadosun:BAAANQADCgIIAgAAAA==.',
Re='Rebalanced:BAAANQAECgIJAgAAAA==.Rebelscum:BAAANQADCgUIBQAAAA==.Reggienoble:BAABNQAECoEcAAIjAAkKzyKtAAB2AwAjAAkKzyKtAAB2AwAAAA==.Rekerî:BAAANQADCgEJAQABNQAFFAYJDwAhALAeAA==.Resoran:BAAANQADCggJBgAAAA==.',
Ri='Rijit:BAAANQADCgYIDAAAAA==.Rineda:BAAANQADCgQJBAAAAA==.Rinzlrr:BAAANQAECggIEwAAAA==.Rippinzynz:BAAANQADCgIIAgAAAA==.',
Ro='Rockyshocky:BAAANQABCgQIBAABNQAECgYJCQAFAAAAAA==.Rohrn:BAAANQAECgYIDQAAAA==.Rol:BAAANQAECgIJBAAAAA==.Rosahugs:BAAANQAECgUICAAAAA==.',
Ru='Ruggishbone:BAAANQAECgQJBAAAAA==.Ruinedmyth:BAAANQAECgUICAAAAA==.',
Sa='Saintsnetie:BAAANQAECgUJBwAAAA==.',
Sc='Scottyknows:BAAANQAECgUICgAAAA==.Scredwin:BAABNQAECoEYAAIMAAgKWQ84DgD4AQAMAAgKWQ84DgD4AQAAAA==.Scrubadub:BAAANQAECgYJDgAAAA==.',
Se='Seeks:BAAANQADCgQIBAAAAA==.Senorbobo:BAABNQAECoEZAAINAAgKNBg0TAA5AgANAAgKNBg0TAA5AgAAAA==.Senorxx:BAAANQAECgIJAgABNQAECggJGQANADQYAA==.Sern:BAAANQADCggICAAAAA==.Serni:BAAANQAECgMJBgAAAA==.',
Sh='Shadei:BAAANQAECgIIBAAAAA==.Shadora:BAAANQADCgYIBgAAAA==.Shadowslite:BAAANQAECgQICAAAAA==.Shadowwolf:BAAANQADCgYIBgAAAA==.Sham:BAABNQAECoEhAAMGAAgKJB9YOAA8AgAGAAcKpR1YOAA8AgAMAAUK0RjlGgB6AQAAAA==.Shamancheese:BAAANQADCgYIBgABNQADCggIEgAFAAAAAA==.Shammpaignn:BAAANQAECgMIAwAAAA==.Shampayn:BAAANQAECgEIAQAAAA==.Shanksinatrá:BAACNQAFFIEOAAMOAAUKdiD2BQDIAAAkAAMKPCC5BQApAQAOAAIKzCD2BQDIAAA1AAQKgSYABCQACQrpJLIKAKACACQABgpqJrIKAKACAA4ABgprHzsaABkCACUAAgqPEKMSAHMAAAAA.Shatt:BAAANQAECgcIDAAAAA==.Shedari:BAABNQAECoEeAAMIAAkKrBEiYgDXAQAIAAgKwBAiYgDXAQAVAAEKCBn6RQBDAAAAAA==.Shiftyjd:BAAANQADCgQIBAABNQADCgcICwAFAAAAAA==.Sholyver:BAAANQAECgMIAwAAAA==.Shourix:BAABNQAECoEbAAIHAAgKQyGxAgDQAgAHAAgKQyGxAgDQAgAAAA==.',
Si='Sifushocks:BAAANQAECgYJDQAAAA==.Sihnn:BAABNQAECoEbAAIYAAgK1B3TFQDRAgAYAAgK1B3TFQDRAgAAAA==.Simzerker:BAACNQAFFIEJAAINAAQKMBtwCgBUAQANAAQKMBtwCgBUAQA1AAQKgR8AAw0ACQpVI+0NAGsDAA0ACQpVI+0NAGsDAAcAAgrLET8aAHAAAAAA.Sitacha:BAAANQADCgEIAQAAAA==.',
Sk='Skrugeduc:BAAANQADCgYIDAABNQAECgMIAwAFAAAAAA==.',
Sl='Slamina:BAAANQAECgUIBgAAAA==.Slowly:BAAANQAFFAIJAgAAAA==.',
Sm='Smarts:BAAANQAECgYICgAAAA==.',
Sn='Sniiffle:BAAANQAECgYJDgAAAA==.Snowba:BAAANQADCgcICAAAAA==.',
Sp='Sparrowheart:BAAANQADCgYICAAAAA==.Spellcrackle:BAAANQADCgcIBgABNQAECggIFgAJAAQHAA==.Sprucejenner:BAABNQAECoEYAAMKAAgKMxXJJABFAgAKAAgKMxXJJABFAgAmAAMKEgXMKABqAAAAAA==.',
Ss='Ssudds:BAAANQAECgcJDAABNQAECgkJJAABALcZAA==.Ssuddy:BAAANQADCgYIBgABNQAECgkJJAABALcZAA==.',
St='Starkisses:BAABNQAECoEcAAIEAAgKWCKIFQD5AgAEAAgKWCKIFQD5AgAAAA==.Styrthe:BAACNQAFFIEKAAIfAAUKMBp+AQC6AQAfAAUKMBp+AQC6AQA1AAQKgSMAAx8ACQqKF7wJAJQCAB8ACQqKF7wJAJQCAA8AAwo5EWoZALkAAAAA.',
Su='Surventval:BAAANQAECgIIAgABNQAECggIEwAFAAAAAA==.',
Sw='Sweetpickles:BAAANQADCgYIDAAAAA==.',
Sy='Symphony:BAAANQADCggICAABNQAECggIEQAFAAAAAA==.',
['Sí']='Síra:BAAANQADCgIIAgABNQAECggIIQAJALUeAA==.',
Ta='Taeka:BAAANQAECgIJAgAAAA==.Taeshira:BAABNQAECoEeAAIXAAgKMxkVEACeAgAXAAgKMxkVEACeAgAAAA==.Talkimas:BAABNQAECoEYAAMEAAgKQRdhMAByAgAEAAgKQRdhMAByAgAhAAMK2ArTQwCaAAAAAA==.Talvisota:BAAANQAECgUJDgAAAA==.Tarirn:BAABNQAECoEYAAMCAAgK0yL7CwAqAwACAAgKhSL7CwAqAwADAAEKih+PYABeAAAAAA==.Taunkaa:BAAANQAECgQIBgAAAA==.',
Te='Tekoslul:BAACNQAFFIEFAAIRAAMKNR1/BgAeAQARAAMKNR1/BgAeAQA1AAQKgRcAAhEACQoDJMwEAH0DABEACQoDJMwEAH0DAAAA.Tekosmage:BAAANQABCgYICQAAAA==.Tekosxd:BAAANQAECgMJAwABNQAFFAMJBQARADUdAA==.Tekosxo:BAAANQAECgIJAgABNQAFFAMJBQARADUdAA==.Teldragoose:BAAANQAECgcJDwAAAA==.Tendeda:BAABNQAECoEXAAMBAAkKwxq2XQB1AgABAAgK9Rm2XQB1AgALAAIKvxWeHgCFAAAAAA==.',
Th='Thalunar:BAABNQAECoEYAAIEAAcKqhT8TQAIAgAEAAcKqhT8TQAIAgAAAA==.Thatonedruid:BAAANQADCgYIBgABNQAECggJGQANADQYAA==.Thelegendone:BAABNQAECoEkAAIJAAkKaSHyBwBeAwAJAAkKaSHyBwBeAwAAAA==.Thepenisadin:BAAANQAECgYICgAAAA==.Thorck:BAAANQAECgUJDAAAAA==.Thugnakmunga:BAAANQADCggIGAAAAA==.',
Ti='Tidens:BAAANQAECgEJAQAAAA==.Tinklewinkle:BAAANQAECgcJEwAAAA==.Tinygiant:BAAANQAECgUIBAAAAA==.Tirra:BAAANQADCgQIBAAAAA==.',
To='Tokapolo:BAAANQAECgYJCgAAAA==.Topshelfelf:BAAANQAECgUJCAAAAA==.',
Tr='Tresdin:BAAANQAECgcIEwAAAA==.Tresemme:BAAANQAECgUICQAAAA==.',
Ts='Tsohg:BAAANQAECgMIAwAAAA==.',
Tu='Tul:BAAANQAECgQJBgABNQAECgYJCwAFAAAAAA==.Tumlock:BAAANQAECgYIDAAAAA==.Turrok:BAAANQAECgcJEwAAAA==.',
['Tï']='Tïgra:BAABNQAECoEYAAIcAAgK9g+zHQAQAgAcAAgK9g+zHQAQAgAAAA==.',
Ua='Uandikillhim:BAABNQAECoEbAAIgAAkKmxtBAQAMAwAgAAkKmxtBAQAMAwAAAA==.',
Um='Umbrä:BAAANQABCgIIAgAAAA==.',
Un='Undeadbones:BAAANQAECgIIAgAAAA==.Unfading:BAAANQAECgcJEwAAAA==.Unholyknight:BAABNQAECoEXAAMCAAcKWQrwQACRAQACAAcKWQrwQACRAQAiAAYKegLMZwDQAAAAAA==.',
Ur='Urban:BAABNQAECoEdAAIBAAkK1yIFIAA3AwABAAkK1yIFIAA3AwAAAA==.Urtark:BAABNQAECoEbAAIHAAgK8hxwAwCiAgAHAAgK8hxwAwCiAgAAAA==.',
Us='Usui:BAAANQADCgUIBQAAAA==.',
Va='Vadym:BAAANQAECgIJBQAAAA==.Vail:BAAANQADCgEIAQABNQAECggIFwAIACsXAA==.Varalic:BAAANQAECggJEgABNQAECgkJGwAcAAQfAA==.Varandra:BAAANQADCgQJBAABNQAECggIFwAIACsXAA==.Vashet:BAAANQADCgcIBwAAAA==.',
Ve='Veleno:BAAANQABCgIIAgAAAA==.Ventrois:BAAANQAECgcJDwABNQAECggIEwAFAAAAAA==.Vespera:BAAANQABCgQIAgAAAA==.Veylynn:BAAANQADCgEIAQAAAA==.',
Vo='Voidalic:BAABNQAECoEbAAMcAAkKBB81EQCmAgAcAAkKnBs1EQCmAgARAAMKQyB1PAAWAQAAAA==.Voidrend:BAACNQAFFIEMAAMcAAUKbxG0AwCmAQAcAAUK5RC0AwCmAQARAAIKegrKCwCVAAA1AAQKgSYABBwACQqMHvEKAAIDABwACQpjHvEKAAIDABEABQqHEmE5ADEBACcAAQojEUgeADQAAAAA.',
Vu='Vuloolu:BAAANQAECgMJAwAAAA==.',
Vy='Vynese:BAAANQADCgUIBQAAAA==.',
['Vø']='Vøgue:BAABNQAECoEcAAIOAAgK+QqWIADXAQAOAAgK+QqWIADXAQAAAA==.',
Wa='Warbidet:BAAANQAECgcIDQAAAA==.Warmason:BAAANQAECgUIEAAAAA==.Washed:BAAANQAECgYJEgAAAA==.',
We='Wealthy:BAABNQAECoEYAAIYAAgKGBtWHgCZAgAYAAgKGBtWHgCZAgAAAA==.',
Wh='Whispere:BAAANQAECgcJEAAAAA==.',
Wi='Wiiska:BAAANQADCgQIBAAAAA==.',
Wr='Wrred:BAAANQAECgIJAgAAAA==.',
Ye='Yetifunk:BAAANQADCgcJEQAAAA==.',
Yo='Yoloswagging:BAAANQADCgEIAQABNQAECgYICwAFAAAAAA==.Yougotfuxed:BAAANQADCgEIAQAAAA==.Yourpal:BAABNQAECoEbAAIIAAgKnBb+RQA7AgAIAAgKnBb+RQA7AgAAAA==.',
Ze='Zemi:BAABNQAECoEcAAIbAAgKjQmLDwDzAQAbAAgKjQmLDwDzAQAAAA==.Zenethrius:BAAANQABCgUJBAAAAA==.Zenlol:BAAANQAECgIJAgABNQAECgcJDgAFAAAAAA==.Zephang:BAABNQAECoEWAAIeAAgKbg/nGwDJAQAeAAgKbg/nGwDJAQAAAA==.Zeros:BAAANQADCgYIBgAAAA==.Zevalia:BAAANQAECgUJDgAAAA==.',
Zl='Zlowwchain:BAAANQADCgUIBQAAAA==.',
Zo='Zophia:BAAANQADCgUIBwAAAA==.',
Zu='Zugrotic:BAAANQAECgcJEgAAAA==.Zumy:BAABNQAECoEbAAIdAAgKyyH0EwAPAwAdAAgKyyH0EwAPAwAAAA==.Zuzzy:BAAANQAECgEJAgAAAA==.',
['ße']='ßelle:BAAANQADCggJDQAAAA==.',
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
