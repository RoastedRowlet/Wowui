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

local lookup = {'Mage-Frost','Druid-Restoration','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Unknown-Unknown','Paladin-Holy','Shaman-Elemental','Shaman-Restoration','Warlock-Demonology','Warrior-Fury','Paladin-Retribution','Rogue-Assassination','Warlock-Destruction','Priest-Shadow','DemonHunter-Vengeance','Druid-Guardian','Druid-Feral','Priest-Holy','Hunter-Survival','Druid-Balance','Monk-Brewmaster','Warrior-Arms','DeathKnight-Blood','Priest-Discipline','DemonHunter-Havoc','Monk-Windwalker','Warrior-Protection','Mage-Fire','DemonHunter-Devourer','Paladin-Protection','Warlock-Affliction','Evoker-Devastation','Evoker-Preservation','Shaman-Enhancement','Rogue-Subtlety','Hunter-Marksmanship','Monk-Mistweaver','Evoker-Augmentation','Rogue-Outlaw',}
local provider = {region='US',realm='Firetree',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Acanthiex:BAAANQAECgIIAgAAAA==.Ackbar:BAAANQAECgMJAwAAAA==.',
Ad='Adondias:BAABNQAECoEkAAIBAAgK+CTEAQBQAwABAAgK+CTEAQBQAwAAAA==.Adorias:BAAANQADCgYIBgAAAA==.',
Ae='Aelana:BAABNQAECoEZAAIBAAgKkxTWCAAeAgABAAgKkxTWCAAeAgAAAA==.',
Ag='Agrevail:BAAANQAECgUICQAAAA==.',
Ak='Akryllic:BAABNQAECoEfAAICAAgKuyGQCgAEAwACAAgKuyGQCgAEAwAAAA==.',
Al='Alamora:BAAANQAECgcIDQAAAA==.Aldari:BAACNQAFFIEKAAMDAAUKxBJpFgCcAQADAAUKxBJpFgCcAQABAAEK+Bj8DQBNAAA1AAQKgR0AAgMACQqyI8kjAEQDAAMACQqyI8kjAEQDAAAA.Allydk:BAABNQAECoEoAAMEAAkKMSQvCABvAwAEAAkKMSQvCABvAwAFAAEKOwoflAAzAAAAAA==.Almorn:BAAANQAECgQICgAAAA==.Alondrius:BAAANQADCgIIAgAAAA==.Altrag:BAABNQAECoEwAAIGAAkKphjPOwCTAgAGAAkKphjPOwCTAgAAAA==.Aluc:BAAANQAECgcIEgAAAA==.',
An='Angestrypee:BAAANQAECgIIAgABNQAECgcICwAHAAAAAA==.Animaldude:BAAANQAECgcICwAAAA==.Anslayer:BAAANQADCggIEQAAAA==.',
Ar='Archön:BAABNQAECoEbAAIIAAgK/g6qXQDcAQAIAAgK/g6qXQDcAQAAAA==.Arctodus:BAAANQADCggICAAAAA==.Arks:BAAANQAECgUICgAAAA==.Arthùr:BAAANQADCgcIBwAAAA==.',
As='Asperges:BAABNQAECoEbAAMJAAgKoRXxXwDSAQAJAAcK1hbxXwDSAQAKAAcKdA6ydQB7AQAAAA==.Astrellia:BAAANQADCgUICwABNQADCggICAAHAAAAAA==.',
Av='Averly:BAAANQADCgUIBQABNQAECggINgALAPMbAA==.Avralynia:BAAANQAECgUICwAAAA==.Avrella:BAAANQADCgYICwABNQAECgUICwAHAAAAAA==.',
['Aé']='Aéo:BAAANQABCgIIAgAAAA==.',
['Aü']='Aürther:BAAANQADCgEIAQAAAA==.',
Ba='Babydaddyx:BAACNQAFFIEPAAIGAAUKhRoiBgDGAQAGAAUKhRoiBgDGAQA1AAQKgScAAgYACQpmJtwDAMADAAYACQpmJtwDAMADAAE1AAQKCAgrAAwAaCMA.Baconn:BAACNQAFFIEFAAINAAIKTBZYGgCeAAANAAIKTBZYGgCeAAA1AAQKgR0AAg0ACQoJJA4TAGoDAA0ACQoJJA4TAGoDAAAA.Balun:BAAANQAECgYIEAAAAA==.Basalt:BAAANQAECggIBgAAAA==.',
Be='Beefdido:BAABNQAECoEeAAIOAAgKUwxsMQDhAQAOAAgKUwxsMQDhAQAAAA==.Beefstew:BAABNQAECoEYAAIGAAgKQhwFMAC7AgAGAAgKQhwFMAC7AgAAAA==.Belithe:BAAANQAECgUIEAAAAA==.Belletrixya:BAABNQAECoEaAAIGAAcKAxBuggDYAQAGAAcKAxBuggDYAQAAAA==.Belrandir:BAAANQADCgYICgAAAA==.Berrymanalow:BAAANQADCgYIBgAAAA==.',
Bi='Bijtoo:BAABNQAECoEfAAMPAAgKjw8uLAATAQALAAgKlQ5IcwDeAQAPAAUKAg8uLAATAQAAAA==.Bingsoo:BAABNQAECoEoAAIDAAkKRRYoeAB3AgADAAkKRRYoeAB3AgAAAA==.Birdlaw:BAAANQADCgYICQAAAA==.',
Bj='Bjarki:BAAANQADCgYIBgAAAA==.Bjorney:BAABNQAECoEiAAIQAAgKZCA0EADaAgAQAAgKZCA0EADaAgAAAA==.',
Bl='Blankspace:BAAANQAECgcIEAAAAA==.Blasphemar:BAAANQADCggIGAAAAA==.Blindvngence:BAABNQAECoEXAAIRAAgKgRg2CABHAgARAAgKgRg2CABHAgAAAA==.Bloodrayne:BAAANQAECgEJAgAAAA==.Bluedruid:BAABNQAECoEiAAMSAAkKhCR2AQC/AwASAAkKhCR2AQC/AwATAAEKZBpAMABOAAAAAA==.Blusloane:BAAANQAECgEIAQAAAA==.',
Bo='Bonkdeath:BAAANQADCgYJCgABNQAECgkJIgASAIQkAA==.Booms:BAAANQADCgYICwAAAA==.',
Br='Braintrust:BAAANQADCgcIBwAAAA==.Brewkkake:BAAANQAECgUIBQAAAA==.Brezanyou:BAAANQADCgIIAgABNQAECggIHwAIAJAKAA==.Brobafett:BAABNQAECoEfAAIUAAYKxiTpMQCAAgAUAAYKxiTpMQCAAgAAAA==.Brøx:BAABNQAECoEfAAIEAAgK7xxdJQCJAgAEAAgK7xxdJQCJAgAAAA==.',
Bu='Bubbleblood:BAAANQADCgMIAwAAAA==.Bumfightbob:BAABNQAECoEUAAIVAAcKUR8hBQBLAgAVAAcKUR8hBQBLAgAAAA==.Bunnyboy:BAAANQAECgEIAgAAAA==.Burlen:BAABNQAECoEmAAIDAAkK3SKMHQBZAwADAAkK3SKMHQBZAwAAAA==.',
['Bê']='Bênitora:BAABNQAECoEmAAIWAAkKixP8LABQAgAWAAkKixP8LABQAgAAAA==.',
['Bî']='Bîrth:BAABNQAECoEoAAMBAAkKwSCXAwDmAgABAAgKQCKXAwDmAgADAAgKQxn1jQBIAgAAAA==.',
Ca='Calic:BAABNQAECoE2AAMLAAgK8xu0bADwAQALAAYK7Ru0bADwAQAPAAIKBRwNRQCnAAAAAA==.Calryuu:BAABNQAECoEcAAIXAAgKWRKyDwDQAQAXAAgKWRKyDwDQAQAAAA==.Caltrask:BAAANQAECgIIAgAAAA==.Cambiön:BAABNQAECoEzAAIBAAgKdCKqAgAWAwABAAgKdCKqAgAWAwAAAA==.Capslock:BAAANQAECgQICQABNQAECgYIDwAHAAAAAA==.Catharsis:BAAANQAECggIBAAAAA==.',
Ce='Cenno:BAABNQAECoEbAAIEAAgKDA/aTAC5AQAEAAgKDA/aTAC5AQAAAA==.Cern:BAAANQAECgMIBAAAAA==.',
Ch='Chadaclysm:BAAANQADCggJEgAAAA==.Chadotcom:BAAANQADCgQIBgAAAA==.Chantyu:BAAANQADCggIHQABNQAECggIHwAIAJAKAA==.Chickenman:BAABNQAECoEtAAIYAAgKTCC1PQC6AgAYAAgKTCC1PQC6AgAAAA==.Chinpokomon:BAAANQAECggIJQAAAQ==.Choncc:BAAANQAECgYICQAAAA==.Chonkykong:BAABNQAECoElAAIZAAgKyg+jSwCoAQAZAAgKyg+jSwCoAQAAAA==.Chubbychi:BAAANQADCgIIAgABNQAECggIHwAIAJAKAA==.Chuppy:BAAANQADCgcIDAABNQAECgcIHQAYANAbAA==.',
Ci='Cinnapaw:BAAANQAECgEIAQAAAA==.',
Co='Codytwo:BAAANQAECgQICgAAAA==.Coldstrype:BAABNQAECoE/AAIDAAkKyRS4cwCAAgADAAkKyRS4cwCAAgABNQAECgcICwAHAAAAAA==.Cole:BAABNQAECoEfAAIYAAgKnhb5XwBQAgAYAAgKnhb5XwBQAgAAAA==.Collonel:BAAANQAECgQICgAAAA==.Connquest:BAAANQAECgEIAgAAAA==.Costcobeef:BAAANQADCggIDgABNQADCggIEgAHAAAAAA==.Couchlocked:BAAANQADCggIFgAAAA==.',
Cp='Cpt:BAAANQADCgQJBQAAAA==.Cptpeals:BAAANQADCggJDQAAAA==.Cptsneck:BAAANQADCgMJAwAAAA==.Cpttan:BAAANQAECgYICgAAAA==.',
Cr='Criticalmiss:BAAANQADCgMIAwABNQAFFAUIDQAEADEWAA==.Critykity:BAABNQAECoEXAAQTAAgKXRhRCgBgAgATAAgKXRhRCgBgAgASAAIKyww5RQBPAAAWAAEKSQ8hoAA0AAAAAA==.Critymage:BAAANQADCgEJAQAAAA==.Critypally:BAAANQAECgUICwAAAA==.Crunkpickles:BAAANQAECgUIBgAAAA==.',
Cv='Cvrcvss:BAAANQAECgcIDQAAAA==.',
Da='Dabadjuju:BAAANQADCgYIDAABNQAECgQICgAHAAAAAA==.Daerik:BAABNQAECoEgAAIGAAkKwR12JgDfAgAGAAkKwR12JgDfAgAAAA==.Dagoonfather:BAABNQAECoEsAAIOAAcKKRYGMwDWAQAOAAcKKRYGMwDWAQAAAA==.Damarkus:BAAANQADCgQIBgAAAA==.Dandochi:BAAANQAECgQIBgABNQAFFAMIBgAIAHshAA==.Dandorllan:BAACNQAFFIEGAAMIAAMKeyHqFgC6AAAIAAIKyCHqFgC6AAANAAEKnQEaMQAzAAA1AAQKgS8AAwgACQo0JaUCAMADAAgACQo0JaUCAMADAA0ABQrZIHKvAIcBAAAA.Dandowaz:BAAANQAECgQICwABNQAFFAMIBgAIAHshAA==.Dandyrandy:BAABNQAECoEoAAMIAAkKDRcUKwChAgAIAAkKDRcUKwChAgANAAEKWAQ2iAEqAAAAAA==.Dani:BAAANQAECgEIAgAAAA==.Dayday:BAAANQAECggICAAAAA==.Dazzazn:BAAANQAECgUICgAAAA==.Dazzeus:BAAANQAECgUIBQAAAA==.',
De='Deadstal:BAAANQAFFAIIAgAAAA==.Deathmaw:BAAANQABCgUIBQAAAA==.Decious:BAAANQAECgcICAAAAA==.Dedoinmyass:BAAANQADCgQIBAAAAA==.Deeboh:BAAANQADCgQIBAAAAA==.Deepfist:BAABNQAECoEoAAIXAAgKByR/AwBAAwAXAAgKByR/AwBAAwAAAA==.Defjam:BAABNQAECoEjAAMDAAgKxxZT0ADAAQADAAYKUhdT0ADAAQABAAIKKBXFKgB7AAAAAA==.Deidren:BAAANQABCgMIAwAAAA==.Delblade:BAAANQAECgIIAgAAAA==.Delicia:BAABNQAECoEaAAMaAAgKCQmmDgAsAQAaAAYKRwumDgAsAQAUAAcKoQLhlwASAQAAAA==.Dellbelphine:BAABNQAECoElAAMNAAgKmhqZWgBeAgANAAgKmhqZWgBeAgAIAAQKYApxxgDGAAAAAA==.Demonskii:BAABNQAECoEdAAIbAAgKWxk7JQBLAgAbAAgKWxk7JQBLAgABNQAECgkJJAAGAGsiAA==.Demton:BAAANQAECgUICAAAAA==.Deusdux:BAAANQADCgMIAwAAAA==.',
Dh='Dhjck:BAAANQAECgUICgAAAA==.',
Di='Diatonic:BAABNQAECoEbAAIcAAkKShrrEgCiAgAcAAkKShrrEgCiAgAAAA==.Direkau:BAABNQAECoEoAAIdAAkKeiUFAQDDAwAdAAkKeiUFAQDDAwAAAA==.',
Do='Docroegames:BAAANQABCgcJDAAAAA==.Dojaz:BAABNQAECoEkAAIbAAkKaxBDKwAdAgAbAAkKaxBDKwAdAgAAAA==.Domerockk:BAAANQADCgQIBAABNQAECgkJJAANAHghAA==.Dontouch:BAAANQAECgIIAgAAAA==.Doomadin:BAAANQADCggICAAAAA==.Dorager:BAAANQADCgYICAAAAA==.',
Dr='Draconica:BAAANQAECgIIBAAAAA==.Dragedo:BAAANQADCgIIAgAAAA==.Dragonfella:BAAANQAECgUIDgAAAA==.Dragonkid:BAAANQADCgEIAQAAAA==.Drakewarden:BAAANQADCgUIBQABNQAECgkJGQAUAGcfAA==.Draktha:BAAANQAECgQIBwAAAA==.Dreddful:BAABNQAECoEmAAIeAAkK2BZaAQCOAgAeAAkK2BZaAQCOAgAAAA==.Drer:BAAANQADCgMIAwAAAA==.Drkelso:BAABNQAECoEYAAIBAAgKgwg6EQBqAQABAAgKgwg6EQBqAQAAAA==.',
Du='Duchalu:BAABNQAECoEoAAMYAAgK4g4VhgDnAQAYAAgK4g4VhgDnAQAMAAEKwgnyLgAxAAAAAA==.Durtbag:BAAANQABCgMIAwAAAA==.Dusklite:BAAANQADCgUIBQAAAA==.',
Eb='Ebbas:BAAANQAECgQIBAAAAA==.',
Ei='Eione:BAABNQAECoEmAAIWAAgKXRNGOQD8AQAWAAgKXRNGOQD8AQAAAA==.',
El='Elend:BAAANQAECgYIDAAAAA==.Elinez:BAAANQAECgUIBgAAAA==.Ellcrys:BAAANQAECgQIBgAAAA==.Elvinshiznic:BAAANQAECgcIEgAAAA==.',
Em='Emagine:BAABNQAECoEmAAIKAAkKsyEfDgA8AwAKAAkKsyEfDgA8AwAAAA==.Embra:BAAANQADCgcIDAAAAA==.Emeraldbeast:BAABNQAECoEeAAICAAkK6RXCFgBnAgACAAkK6RXCFgBnAgAAAA==.',
En='Endela:BAAANQADCggIBwABNQADCggICAAHAAAAAA==.Endelan:BAAANQADCgMIAwABNQADCggICAAHAAAAAA==.Endelen:BAAANQAECgEIAQAAAA==.',
Er='Erissra:BAAANQADCgMIAwAAAA==.Eroeda:BAAANQAECgYIEQAAAA==.',
Es='Escanør:BAAANQADCgcICQABNQAECggILQAYAEwgAA==.',
Ev='Evilmustdie:BAAANQADCgMIAwAAAA==.',
Ex='Exo:BAABNQAECoEoAAICAAkKFSXVAQCtAwACAAkKFSXVAQCtAwAAAA==.Exylan:BAABNQAECoEkAAINAAkK5BlJRQCfAgANAAkK5BlJRQCfAgAAAA==.',
Ez='Ezsmash:BAAANQAECggIEQAAAA==.',
Fa='Fatgrlfriend:BAABNQAECoEtAAINAAkKqCNfDACTAwANAAkKqCNfDACTAwABNQAECggIKwAMAGgjAA==.',
Fe='Ferachio:BAAANQAECgIIAgAAAA==.',
Ff='Ffreshmage:BAAANQAECgQIBQABNQAFFAUICwAPAL8gAA==.',
Fh='Fhud:BAAANQADCgIIAwAAAA==.',
Fi='Fierysquish:BAAANQADCggIDAAAAA==.Filmnoir:BAABNQAECoEaAAIfAAgK1RHvIwAIAgAfAAgK1RHvIwAIAgAAAA==.Fistferge:BAAANQADCgEIAQABNQAECgkJIQAgAOAhAA==.',
Fl='Flinah:BAAANQABCgIJAgAAAA==.',
Fo='Follia:BAAANQADCgYIBgAAAA==.Foosaa:BAAANQAECgMJAwAAAA==.Forbearance:BAABNQAECoEoAAIgAAkKniH9BABMAwAgAAkKniH9BABMAwAAAA==.Forgotss:BAAANQAECgYIDwAAAA==.',
Fr='Franco:BAABNQAECoEiAAIGAAgKKxAmeADwAQAGAAgKKxAmeADwAQAAAA==.Freshfresh:BAAANQADCggICAABNQAFFAUICwAPAL8gAA==.Freshlock:BAACNQAFFIELAAQPAAUKvyCCAwDXAAAPAAIKBiSCAwDXAAAhAAIK5Br7AgCwAAALAAEK6CUOMABwAAA1AAQKgR4ABAsACQr8I2xBAHICAAsABwo9IWxBAHICAA8ABAq5IlAgAGMBACEAAgr1IQgXALUAAAAA.Fright:BAAANQAECgYICAAAAA==.Friska:BAAANQAECgUIEAAAAA==.Frostyp:BAACNQAFFIETAAIQAAYKSg5gBADYAQAQAAYKSg5gBADYAQA1AAQKgSkAAxAACQrDHMUTAKkCABAACQrDHMUTAKkCABQAAQrCARDtACIAAAAA.',
Fu='Fulldk:BAAANQADCggICAAAAA==.Funken:BAAANQADCggIGgAAAA==.',
Fy='Fyre:BAAANQADCgUJBgABNQAECgkJIQAiAJwYAA==.Fyrebird:BAABNQAECoEhAAMiAAkKnBjHCwCSAgAiAAkKnBjHCwCSAgAjAAQKnAhSOQCuAAAAAA==.',
Ga='Gahamachita:BAAANQADCgEIAQAAAA==.Galadhriel:BAABNQAECoEoAAICAAgKrx/hDQDWAgACAAgKrx/hDQDWAgAAAA==.Galadima:BAABNQAECoEnAAIIAAgK7SDDGgD3AgAIAAgK7SDDGgD3AgAAAA==.Ganador:BAABNQAECoEoAAMLAAkKKSBxJADaAgALAAgKSSBxJADaAgAPAAIKMxzuSQCXAAAAAA==.Garglon:BAAANQADCggICgAAAA==.Gatorrc:BAAANQADCgMJAwAAAA==.Gazzerfroz:BAAANQADCgYIBgABNQAECgYIDgAHAAAAAA==.',
Gh='Ghostingyou:BAAANQAECgQIBAABNQAECgkJIgASAIQkAA==.',
Gi='Gilburt:BAACNQAFFIEWAAILAAYKyRynAwAcAgALAAYKyRynAwAcAgA1AAQKgRkAAgsACAq7HyUyAKUCAAsACAq7HyUyAKUCAAAA.Gileon:BAAANQAECgcIEAAAAA==.',
Gn='Gnomeofdeath:BAAANQAECgYICgAAAA==.',
Go='Gomgar:BAAANQADCggIEgAAAA==.Gorg:BAAANQAECgcIEgAAAA==.',
Gr='Grashoppa:BAAANQADCgcIEQAAAA==.Greentide:BAABNQAECoEmAAIKAAkK1RY8QwApAgAKAAkK1RY8QwApAgAAAA==.Grimmothy:BAAANQADCggIFgAAAA==.Grimore:BAAANQAECgUICQAAAA==.Groovybun:BAAANQADCgYIBgAAAA==.',
Gu='Guccimaybe:BAABNQAECoEeAAIkAAgK6g0QEwATAgAkAAgK6g0QEwATAgAAAA==.',
Gw='Gwynastrasza:BAACNQAFFIEcAAIjAAgKMhVDAQCrAgAjAAgKMhVDAQCrAgA1AAQKgR0AAiMACQrGHEoMAM8CACMACQrGHEoMAM8CAAAA.Gwynneth:BAAANQAECgMJAwABNQAFFAgIHAAjADIVAA==.',
['Gü']='Güy:BAAANQAECgYIDgAAAA==.',
Ha='Haleluya:BAAANQADCgYIDgABNQAECgUIBwAHAAAAAA==.Halepurr:BAAANQAECgUIBwAAAA==.Halogenrofl:BAABNQAECoEiAAIfAAkK/xyNDgDwAgAfAAkK/xyNDgDwAgAAAA==.Hammerferge:BAABNQAECoEhAAIgAAkK4CHEBgAiAwAgAAkK4CHEBgAiAwAAAA==.Hangezoë:BAAANQAECggIDgABNQAFFAYIFgALAMkcAQ==.Happa:BAABNQAECoEpAAIXAAkK9By8BQDlAgAXAAkK9By8BQDlAgAAAA==.Harbngerkhan:BAABNQAECoEXAAMEAAYKuw2ZeAAPAQAEAAUK0Q+ZeAAPAQAZAAUKbAV7iAC5AAAAAA==.Hardok:BAAANQADCgEIAQAAAA==.Hashishi:BAAANQADCgEIAQAAAA==.',
He='Healroy:BAAANQAECgEIAQAAAA==.Heidt:BAAANQAECgYIDgAAAA==.Hellica:BAAANQADCgcIDgAAAA==.',
Ho='Holibeef:BAABNQAECoEfAAMIAAgKkAoGbwCjAQAIAAgKkAoGbwCjAQANAAEK2AE0nAEeAAAAAA==.Holysquish:BAACNQAFFIEMAAINAAUKbBEACQCPAQANAAUKbBEACQCPAQA1AAQKgSoAAg0ACQqmIH4rAP0CAA0ACQqmIH4rAP0CAAAA.Homoglobin:BAAANQAECgQIBAAAAA==.Honeydemon:BAABNQAECoEoAAIbAAkKOxZNJQBKAgAbAAkKOxZNJQBKAgAAAA==.Honeydue:BAAANQADCgEJAwABNQAECgkJIQAiAJwYAA==.Hongis:BAABNQAECoEeAAMDAAcKjRkfpQAXAgADAAcKjRkfpQAXAgABAAEKTQVZSgAgAAAAAA==.Horsefuneral:BAAANQADCgQIBAABNQAECgUIBgAHAAAAAA==.Hotdogsteve:BAAANQADCgMIAwAAAA==.',
Hu='Huge:BAAANQAECgcIDgAAAA==.Humi:BAAANQAECgUICgAAAA==.Huntskii:BAABNQAECoEkAAIGAAkKayLsBwCQAwAGAAkKayLsBwCQAwAAAA==.',
Hw='Hwaryeong:BAAANQAECgEIBQAAAA==.',
Ia='Iamluck:BAABNQAECoEkAAIfAAkKth9SDgDzAgAfAAkKth9SDgDzAgAAAA==.Iamluçk:BAACNQAFFIEKAAIDAAUKvBKRFwCUAQADAAUKvBKRFwCUAQA1AAQKgRwAAgMACQptG2lPANICAAMACQptG2lPANICAAAA.',
Ic='Iceleaf:BAAANQAECgYIEAAAAA==.',
Ig='Igopew:BAAANQAECgQIBAAAAA==.',
Il='Ileinaa:BAABNQAECoE5AAIUAAkKXRbiMACEAgAUAAkKXRbiMACEAgAAAA==.Iliketrains:BAABNQAECoEaAAMJAAgKuxK6aQCzAQAJAAcKZhG6aQCzAQAKAAUK0wKPwAC9AAAAAA==.Ilovegrizzly:BAAANQAECgUIBQABNQAECggIFAANAJgkAA==.',
In='Indicud:BAAANQAECgEIAgAAAA==.Introvert:BAAANQABCgMIAwAAAA==.Invvictis:BAAANQAECgcIDgAAAA==.',
Is='Isele:BAAANQADCgEIAQABNQADCggICAAHAAAAAA==.',
Ja='Jaymazing:BAAANQAECgMIBAABNQAECgkJHwAYAAcaAA==.Jaysaurus:BAABNQAECoEfAAIYAAkKBxrJOwDAAgAYAAkKBxrJOwDAAgAAAA==.Jazzey:BAABNQAECoEdAAIEAAkKuBvZLQBYAgAEAAkKuBvZLQBYAgAAAA==.',
Jc='Jckie:BAAANQAECgMIAwAAAA==.',
Je='Jestyrddk:BAAANQAECgUICgABNQAECggIFwARAKMhAA==.',
Jo='Jodox:BAAANQADCgMIAQAAAA==.Joehendry:BAAANQADCgcIEAAAAA==.Johnathonn:BAAANQAECgMIBAAAAA==.Joj:BAABNQAECoEgAAMUAAgK9hzOMwB3AgAUAAgK9hzOMwB3AgAaAAIKHBt+FwCcAAAAAA==.Jojman:BAAANQABCgYIBgAAAA==.Jonthecron:BAAANQAECgUIEQAAAA==.Jormot:BAAANQADCgYJBwABNQAECgkJIQAiAJwYAA==.Jowl:BAAANQADCgMIAwAAAA==.',
Ju='Juck:BAAANQAECggIDwAAAA==.Junkyo:BAAANQAECgEIBQAAAA==.Justamage:BAABNQAECoEhAAIDAAgKQxbmjABKAgADAAgKQxbmjABKAgAAAA==.Juw:BAAANQAECgEIAQAAAA==.',
Ka='Kalundia:BAAANQAECgYIEgAAAA==.Karkshammy:BAABNQAECoEbAAIJAAkKoxqAMwCFAgAJAAkKoxqAMwCFAgAAAA==.Karlia:BAAANQADCgYICQAAAA==.',
Ke='Keane:BAABNQAECoEqAAIYAAkKAw5gcQAfAgAYAAkKAw5gcQAfAgAAAA==.Kellelor:BAAANQADCgQIBAAAAA==.Kelpie:BAAANQAECgEIAwAAAA==.Kelwind:BAAANQADCgcIBwAAAA==.',
Kh='Khanquest:BAAANQAECgUIBgAAAA==.',
Ki='Killkillkill:BAAANQAECgIIAgAAAA==.Kindassuddy:BAABNQAECoElAAIDAAkKtxmUcQCFAgADAAkKtxmUcQCFAgAAAA==.Kindled:BAAANQAECgYICwAAAA==.Kinvardar:BAAANQAECgYICQAAAA==.Kirbbslav:BAAANQADCgEIAQABNQAFFAcIEwAIABsbAA==.Kirbislav:BAAANQAECgYICAABNQAFFAcIEwAIABsbAA==.Kirbslav:BAACNQAFFIETAAIIAAcKGxvRAQCCAgAIAAcKGxvRAQCCAgA1AAQKgSoAAggACQoHJLwFAJUDAAgACQoHJLwFAJUDAAAA.Kirklandbeef:BAAANQADCggIEgAAAA==.Kittykillerr:BAAANQADCgcJBwABNQAECggIKwAMAGgjAA==.',
Kn='Knata:BAAANQADCgcICwAAAA==.Kniavez:BAABNQAECoEeAAIYAAgKQQ9lgwDvAQAYAAgKQQ9lgwDvAQAAAA==.',
Kr='Krack:BAAANQAECgcIEAAAAA==.Krak:BAAANQAECgEIAwABNQAECgcIEAAHAAAAAA==.Kruugh:BAAANQAECgYIDQAAAA==.',
Ku='Kuler:BAAANQAECgYIEwAAAA==.Kungfustuff:BAAANQADCgUIBQABNQAECgUIDAAHAAAAAA==.Kunguska:BAAANQADCgQIAgAAAA==.Kurome:BAAANQAECgcIBwAAAA==.',
['Kè']='Kèèn:BAABNQAECoEXAAINAAcKpSDwbAApAgANAAcKpSDwbAApAgAAAA==.',
['Kì']='Kìt:BAAANQAECgEIAQAAAA==.',
['Kí']='Kítkat:BAAANQADCgIIAgABNQAECgEIAQAHAAAAAA==.',
['Kÿ']='Kÿra:BAAANQADCgYIBgAAAA==.',
La='Lavage:BAAANQAECgQIBwAAAA==.',
Le='Lectra:BAAANQABCgcICAAAAA==.Lengthypally:BAAANQAECgQIBQAAAA==.',
Li='Liakä:BAAANQAECgcIEAABNQAECgkJFgAGABEQAA==.Lilbeaner:BAAANQAECgYIBAAAAA==.Liratha:BAAANQAECgYICgAAAA==.Lisá:BAAANQAECgIIAgAAAA==.',
Ll='Llahsram:BAAANQAECgQIBwAAAA==.',
Lo='Locholiday:BAAANQADCgQIBAAAAA==.Lodoss:BAABNQAECoEYAAIKAAgK+xiZQwAnAgAKAAgK+xiZQwAnAgAAAA==.Lokhidmartin:BAAANQAECgYICgAAAA==.Lorienb:BAABNQAECoEkAAMQAAkK5g7wIAAKAgAQAAkK5g7wIAAKAgAaAAUKIgWoEwDSAAAAAA==.Lorstin:BAAANQADCgEIAQAAAA==.',
Lu='Luckehlock:BAACNQAFFIEXAAMhAAYKSSYTAACSAgAhAAYKSSYTAACSAgAPAAEKSBGwGABRAAA1AAQKgSwAAiEACQrsJgcAAAsEACEACQrsJgcAAAsEAAAA.Lunaea:BAABNQAECoEYAAMlAAcKsB7rKABkAQAlAAQKvR7rKABkAQAOAAMKnh7+VwAKAQAAAA==.Luxcn:BAAANQADCgUJBwAAAA==.',
['Lú']='Lúffy:BAAANQAECgcICwABNQAECggIEQAHAAAAAA==.',
Ma='Macdorn:BAAANQAECgYIBgAAAA==.Macgibbins:BAAANQAECgQIBAAAAA==.Macgillivray:BAABNQAECoEXAAMNAAgKpht5agAwAgANAAgKpht5agAwAgAgAAgK7Ql9LgA/AQAAAA==.Magewindu:BAABNQAECoEWAAIDAAcKfQ1P2ACwAQADAAcKfQ1P2ACwAQAAAA==.Magus:BAAANQAECgQICwABNQAECgkJIAAWAMAmAA==.Malakar:BAAANQAECgEIAQAAAA==.Mardin:BAAANQADCgEJAQAAAA==.Marhuon:BAAANQADCgEIAQAAAA==.Mats:BAAANQADCggICAAAAA==.Mavus:BAAANQADCgYIBgAAAA==.',
Me='Meanmyst:BAAANQAECgIIAgAAAA==.',
Mi='Midgardsomr:BAAANQAECgYICgAAAA==.Mightbane:BAAANQAECggIEQAAAA==.Mikebroowwnn:BAAANQADCgIIAgAAAA==.Milkmytotems:BAAANQAECggIEgABNQAECggIKwAMAGgjAA==.Minagozap:BAABNQAECoEXAAIJAAcKCxMWYwDHAQAJAAcKCxMWYwDHAQAAAA==.Mininine:BAAANQAECgQIBAAAAA==.Minityr:BAABNQAECoEgAAMIAAgKbhmeOQBhAgAIAAgKbhmeOQBhAgAgAAgK3hMHHwDDAQAAAA==.Minotron:BAAANQADCgUICgABNQAFFAYIDQAmADUYAA==.Mizukï:BAABNQAECoEdAAIUAAgKSB3fKACoAgAUAAgKSB3fKACoAgAAAA==.',
Mo='Molyver:BAABNQAECoElAAMcAAkKBx2/DQDmAgAcAAkKBx2/DQDmAgAnAAEKBAN5SgAlAAAAAA==.Momak:BAAANQADCgUICAABNQAECggIIQAJANIZAA==.Mommey:BAACNQAFFIEKAAIUAAUKtRAzDAChAQAUAAUKtRAzDAChAQA1AAQKgSQABBoACQrWH04DAKoCABoACAomHk4DAKoCABQABgrCHIVQAAgCABAABwryG4ciAPkBAAAA.Moonmellow:BAAANQAECgMICQAAAA==.Moosin:BAAANQADCgYIBgAAAA==.Morel:BAAANQADCgYIBgAAAA==.Mositas:BAAANQABCgIIAgAAAA==.',
Mp='Mpatt:BAAANQADCgUIBgAAAA==.',
Mu='Munder:BAAANQAECgQIDwAAAA==.Murlockscry:BAAANQAECgIIAgAAAA==.Musculate:BAABNQAECoEnAAImAAkKoyOzBACAAwAmAAkKoyOzBACAAwAAAA==.',
Mv='Mvdi:BAABNQAECoEUAAIIAAcKdhyNNwBqAgAIAAcKdhyNNwBqAgAAAA==.',
My='Myranda:BAAANQADCgYJBgAAAA==.',
['Mï']='Mïssionary:BAAANQAECgIIAgAAAA==.',
Na='Nartou:BAAANQAECgYIDgAAAA==.',
Ne='Necrofearlia:BAAANQAECgYIEQAAAA==.Nekoashley:BAAANQAECgEIBQAAAA==.',
Ni='Nick:BAABNQAECoEgAAIWAAkKwCZ6AgDOAwAWAAkKwCZ6AgDOAwAAAA==.Nightangelxx:BAAANQADCgYJEAAAAA==.',
No='Noodle:BAAANQADCgEIAQAAAA==.Noolore:BAACNQAFFIENAAMEAAUKMRb4CQBKAQAEAAQKChr4CQBKAQAZAAEKzQZ+MwAgAAA1AAQKgSsAAgQACQp2IpwTAAUDAAQACQp2IpwTAAUDAAAA.Nosferatu:BAAANQAECgIJAgAAAA==.Notrico:BAAANQADCgQIBAAAAA==.',
Nu='Nurfhammer:BAAANQADCgEIAQABNQAECggIHwAJACMkAA==.Nurfshock:BAABNQAECoEfAAIJAAgKIyQxFAA9AwAJAAgKIyQxFAA9AwAAAA==.',
Oa='Oasis:BAAANQADCgYICAAAAA==.',
Ok='Okaybutwhy:BAAANQADCgYIBgABNQAECgkJJgANAHMlAA==.Okiedk:BAAANQAECgUIDgAAAA==.',
On='Onefelswoop:BAAANQAECgYIDgAAAA==.',
Or='Ortuk:BAAANQADCgMIAwAAAA==.',
Ox='Oxen:BAABNQAECoEfAAMZAAgKDB/ZIACUAgAZAAcKiCDZIACUAgAEAAUKrw7hgADxAAAAAA==.',
Pe='Pegab:BAAANQAECgQIBAAAAA==.Penniee:BAAANQADCggIDQAAAA==.Penniwing:BAABNQAECoEZAAQoAAgKPRW5BwACAgAoAAgKPRW5BwACAgAjAAYKCREmKQBEAQAiAAEKDAmzPAAoAAAAAA==.Percival:BAECNQAFFIEYAAImAAYKKiR4AgBcAgAmAAYKKiR4AgBcAgA1AAQKgSkAAyYACQpBJa8FAGsDACYACQpBJa8FAGsDAAYAAQoID8s3AToAAAAA.',
Ph='Phaedra:BAAANQAECggIJQAAAQ==.Phaidra:BAAANQAECgQICAABNQAECggIJQAHAAAAAQ==.Phealdh:BAABNQAECoEfAAMbAAgKyxuNHwB3AgAbAAgKyxuNHwB3AgAfAAYKugZKPwAhAQAAAA==.',
Pi='Pillargodx:BAAANQADCgQIBAAAAA==.Pixr:BAAANQAECggICAAAAA==.',
Pl='Plague:BAABNQAECoEhAAIEAAkKqxrlLQBXAgAEAAkKqxrlLQBXAgAAAA==.',
Po='Police:BAAANQAECggIAQAAAA==.',
Pu='Pudpull:BAAANQAECgEIAQAAAA==.Pullbarg:BAAANQAECgQIBAAAAA==.',
Py='Pyru:BAAANQAECgQIBwAAAA==.',
['Pï']='Pïng:BAABNQAECoEWAAIGAAkKERBSTwBZAgAGAAkKERBSTwBZAgAAAA==.',
Qu='Quest:BAAANQAECgcIDwAAAA==.Quickwinnter:BAABNQAECoEUAAMNAAgKmCQxJQAXAwANAAgKmCQxJQAXAwAIAAEK2hRA/gBEAAAAAA==.Quickwinterg:BAABNQAECoEUAAMEAAgKURn+NAAxAgAEAAgKURn+NAAxAgAFAAgKSgapbgCgAAABNQAECggIFAANAJgkAA==.Quickwinterm:BAAANQAECggIDAABNQAECggIFAANAJgkAA==.',
Ra='Raandok:BAAANQADCggIEAABNQAECgYIDwAHAAAAAA==.Raantok:BAAANQADCgYIBgABNQAECgYIDwAHAAAAAA==.Raantokdh:BAAANQADCgUICQABNQAECgYIDwAHAAAAAA==.Raantoks:BAAANQAECgYIDwAAAA==.Rachet:BAAANQAECgUIDQAAAA==.Racoondots:BAAANQADCgYIBgAAAA==.Rakhár:BAAANQAECgEIAQAAAA==.Rakkdos:BAAANQAECgQIBAAAAA==.Rastaboss:BAAANQADCgUIBQAAAA==.Ratpackleadr:BAAANQAECgEIAQAAAA==.Rayado:BAABNQAECoErAAMIAAkK1RLbPABTAgAIAAkK1RLbPABTAgANAAEKFgVxhwErAAAAAA==.Rayadobane:BAAANQAECgQIBAAAAA==.Rayadosun:BAAANQADCgIIAgAAAA==.',
Re='Rebalanced:BAAANQAECgIJAgAAAA==.Rebelscum:BAAANQADCgUIBQAAAA==.Redbudz:BAAANQADCgYIBgAAAA==.Reggienoble:BAABNQAECoEkAAIVAAkKTyM/AQBdAwAVAAkKTyM/AQBdAwAAAA==.Rekerî:BAAANQADCgEIAQABNQAFFAcIFwAmAEYfAA==.Resoran:BAAANQADCggJBgAAAA==.',
Ri='Rijit:BAAANQADCgYIDAAAAA==.Rineda:BAAANQADCgUIBgAAAA==.Rinzee:BAAANQADCgEIAQAAAA==.Rinzlrr:BAABNQAECoEiAAIkAAkKWR4/BQAuAwAkAAkKWR4/BQAuAwAAAA==.Rippinzynz:BAAANQADCgIIAgAAAA==.',
Ro='Rockyshocky:BAAANQABCgQIBAABNQAECgYICgAHAAAAAA==.Rohrn:BAABNQAECoEcAAINAAcK1xf5gQDzAQANAAcK1xf5gQDzAQAAAA==.Rol:BAAANQAECgIJBAAAAA==.Rosahugs:BAAANQAECggIDwAAAA==.',
Ru='Ruggishbone:BAAANQAECgUIDgAAAA==.Ruinedmyth:BAAANQAECgcIEAAAAA==.',
Sa='Saintsnetie:BAAANQAECgUIBwAAAA==.',
Sc='Scottyknows:BAABNQAECoEaAAMIAAgKKBoXMACKAgAIAAgKKBoXMACKAgANAAYKjBT/rACNAQAAAA==.Scredwin:BAABNQAECoEoAAMPAAgKrRkjCAB0AgAPAAgKrRkjCAB0AgALAAIK3AYnEgFfAAAAAA==.Scrubadub:BAABNQAECoEdAAMGAAgKHxUhXQA0AgAGAAgKHxUhXQA0AgAmAAEKxwc5fAAzAAAAAA==.',
Se='Sean:BAAANQADCgMIAwABNQAECgcIDwAHAAAAAA==.Seeks:BAAANQADCgQIBAAAAA==.Semizas:BAAANQADCgYIBgAAAA==.Senorbobo:BAABNQAECoEpAAMMAAkKbh13AwD9AgAMAAkKNB13AwD9AgAYAAgKNBgJcwAaAgAAAA==.Senorxx:BAAANQAECgQIBgABNQAECgkJKQAMAG4dAA==.Sern:BAAANQAECgQIBQAAAA==.Serni:BAAANQAECgMIBgAAAA==.',
Sh='Shadei:BAAANQAECgIIBAAAAA==.Shadora:BAAANQADCgYIBgAAAA==.Shadowslite:BAAANQAECgcIEgAAAA==.Shadowwolf:BAAANQADCgYIBgAAAA==.Sham:BAABNQAECoEsAAMLAAkKcB97NwCTAgALAAgK5x17NwCTAgAPAAUKPBm7HgBwAQAAAA==.Shamancheese:BAAANQADCgYIBgABNQADCggIEgAHAAAAAA==.Shammpaignn:BAAANQAECgQICwAAAA==.Shampayn:BAAANQAECgEIAQAAAA==.Shanksinatrá:BAACNQAFFIEZAAMOAAYKTSLrBQCMAQAOAAQKhxvrBQCMAQAlAAQKCxpwBwBtAQA1AAQKgSsABCUACQrdJSsNAJQCACUABgqBJisNAJQCAA4ABgrBIM8pABMCACkAAgqPECsWAGkAAAAA.Shatt:BAABNQAECoEYAAIDAAgKrxvuZACgAgADAAgKrxvuZACgAgAAAA==.Shedari:BAABNQAECoEoAAMNAAkKlhWviADiAQANAAgK4RKviADiAQAgAAQKvhnUNQANAQAAAA==.Shiftyjd:BAAANQADCgQIBAABNQAECgQIBQAHAAAAAA==.Sholyver:BAAANQAECgUICAAAAA==.Shourix:BAABNQAECoErAAIMAAgKaCM0AgBCAwAMAAgKaCM0AgBCAwAAAA==.',
Si='Sifushocks:BAAANQAECgYIEwAAAA==.Sihnn:BAABNQAECoEfAAIUAAkK1xsGGQD6AgAUAAkK1xsGGQD6AgAAAA==.Simzerker:BAACNQAFFIELAAIYAAQKThv9EwBOAQAYAAQKThv9EwBOAQA1AAQKgSMAAxgACQpZJAcVAFwDABgACQpZJAcVAFwDAAwAAgrLEdEjAGsAAAAA.Sitacha:BAAANQADCgEIAQAAAA==.',
Sk='Skrugeduc:BAAANQAECgUICgAAAA==.',
Sl='Slamina:BAAANQAECgYIEwAAAA==.Slowly:BAAANQAFFAIJAgAAAA==.',
Sm='Smarts:BAABNQAECoEbAAIDAAgKHw3EwADfAQADAAgKHw3EwADfAQAAAA==.',
Sn='Sniiffle:BAABNQAECoEhAAICAAgKOxhNGABVAgACAAgKOxhNGABVAgAAAA==.Snowba:BAAANQADCgcICAAAAA==.',
Sp='Sparrowheart:BAAANQADCgYICAAAAA==.Spellcrackle:BAAANQADCggIDgABNQAECggIHwAIAJAKAA==.Sprucejenner:BAABNQAECoEnAAMWAAgKrxe4KgBfAgAWAAgKrxe4KgBfAgASAAMKEgUOQABnAAAAAA==.',
Sq='Squivify:BAAANQAFFAEIAQAAAA==.',
Ss='Ssudds:BAAANQAECggIEwABNQAECgkJJQADALcZAA==.Ssuddy:BAAANQADCgYIBgABNQAECgkJJQADALcZAA==.',
St='Starkisses:BAABNQAECoEnAAIGAAkKACROCwBxAwAGAAkKACROCwBxAwAAAA==.Stormßella:BAAANQADCgYIBgAAAA==.Styrthe:BAACNQAFFIETAAInAAYKIhgeAgD4AQAnAAYKIhgeAgD4AQA1AAQKgSkAAycACQrDGNMNAIECACcACQrDGNMNAIECABcAAwo5Eb4hAKgAAAAA.',
Su='Surventval:BAAANQAECgUICAABNQAECgkJIgAkAFkeAA==.',
Sw='Sweetpickles:BAAANQADCgYIFwAAAA==.',
Sy='Symphony:BAAANQADCggICAABNQAECgkJGwAcAEoaAA==.',
['Sí']='Síra:BAAANQADCgIIAgABNQAECggICwAHAAAAAA==.',
Ta='Taeka:BAAANQAECgQICgAAAA==.Taeshira:BAABNQAECoEhAAIQAAkKJBngEgC1AgAQAAkKJBngEgC1AgAAAA==.Talkimas:BAABNQAECoEoAAMGAAgKlRnLRAB3AgAGAAgKlRnLRAB3AgAmAAUK6QrFQwAHAQAAAA==.Talvisota:BAABNQAECoEfAAIEAAgKPSDVHADCAgAEAAgKPSDVHADCAgAAAA==.Tarirn:BAABNQAECoEfAAMEAAgKECVWEQAXAwAEAAgKwiRWEQAXAwAFAAEKih8KhgBUAAAAAA==.Taunkaa:BAAANQAECgUIEAAAAA==.',
Te='Tekoslul:BAACNQAFFIEMAAIbAAUKMCCvBQDMAQAbAAUKMCCvBQDMAQA1AAQKgR0AAhsACQp0JN4IAF4DABsACQp0JN4IAF4DAAAA.Tekosmage:BAAANQABCgYICQAAAA==.Tekosxd:BAAANQAECgMJAwABNQAFFAUIDAAbADAgAA==.Tekosxo:BAAANQAECgQIBAABNQAFFAUIDAAbADAgAA==.Teldragoose:BAABNQAECoEhAAMCAAgKDheNGwAwAgACAAgKDheNGwAwAgAWAAIKageXkgBYAAAAAA==.Tendeda:BAACNQAFFIEMAAMDAAUKGRc8FACsAQADAAUKGRc8FACsAQABAAEKmgGgEgAzAAA1AAQKgR4AAwMACQoTH/lrAJECAAMACArPHvlrAJECAAEAAgq/FZMrAHUAAAAA.',
Th='Thalunar:BAABNQAECoEdAAIGAAgKExa7WQA9AgAGAAgKExa7WQA9AgAAAA==.Thatonedruid:BAAANQADCgYIBgABNQAECgkJKQAMAG4dAA==.Thelegendone:BAACNQAFFIELAAIIAAQKFRb0DQBMAQAIAAQKFRb0DQBMAQA1AAQKgSoAAggACQrdIR0MAFkDAAgACQrdIR0MAFkDAAAA.Thepenisadin:BAABNQAECoEbAAINAAgKDQ4ckADQAQANAAgKDQ4ckADQAQAAAA==.Thorck:BAABNQAECoEcAAIYAAgKBQofmQC0AQAYAAgKBQofmQC0AQAAAA==.Thrallzballz:BAAANQADCgMIAwAAAA==.Thugnakmunga:BAAANQAECgUIBQAAAA==.',
Ti='Tidens:BAAANQAECgEIAQAAAA==.Tinklewinkle:BAABNQAECoEmAAIDAAgKrB0ybgCMAgADAAgKrB0ybgCMAgAAAA==.Tinygiant:BAAANQAECgUIBAAAAA==.Tirra:BAAANQADCgQIBAAAAA==.',
To='Tokapolo:BAABNQAECoEbAAIJAAgKySJ9GAAgAwAJAAgKySJ9GAAgAwAAAA==.Topshelfelf:BAABNQAECoEZAAMUAAcKcx4nOABlAgAUAAcKcx4nOABlAgAaAAMK3wuFFwCcAAAAAA==.',
Tr='Tresdin:BAABNQAECoEmAAINAAkK/iAVIAAsAwANAAkK/iAVIAAsAwAAAA==.Tresemme:BAABNQAECoEZAAIUAAkKzBmwHQDhAgAUAAkKzBmwHQDhAgAAAA==.',
Ts='Tsohg:BAAANQAECgUICAABNQAECgUICgAHAAAAAA==.',
Tu='Tul:BAAANQAECggIDgAAAA==.Tumlock:BAABNQAECoEYAAMPAAgKOQ8kEQDmAQAPAAgKIg8kEQDmAQALAAEKjgTtJQEyAAAAAA==.Turrok:BAABNQAECoEoAAIlAAkKXx0BBwAFAwAlAAkKXx0BBwAFAwAAAA==.Turtletaunt:BAAANQADCgUIBQAAAA==.',
['Tï']='Tïgra:BAABNQAECoEoAAIfAAgK1BfXHABRAgAfAAgK1BfXHABRAgAAAA==.',
Ua='Uandikillhim:BAABNQAECoEmAAMaAAkK5B26AQASAwAaAAkKqRy6AQASAwAUAAgKYRPxSgAcAgAAAA==.',
Um='Umbrä:BAAANQABCgIIAgAAAA==.',
Un='Undeadbones:BAAANQAECgIIAgAAAA==.Unfading:BAABNQAECoEnAAINAAgKdhq7VABuAgANAAgKdhq7VABuAgAAAA==.Unholyknight:BAABNQAECoElAAMEAAcKMQ9bWwB7AQAEAAcKMQ9bWwB7AQAZAAYKegJZhADGAAAAAA==.',
Ur='Urban:BAACNQAFFIEJAAMBAAQKOw/YBgCQAAADAAMKsA/DLgDhAAABAAIKWQ3YBgCQAAA1AAQKgSAAAgMACQpCI7gtACcDAAMACQpCI7gtACcDAAAA.Urtark:BAABNQAECoEoAAIMAAkK3h2WAwD3AgAMAAkK3h2WAwD3AgAAAA==.',
Us='Usui:BAAANQADCgUIBQAAAA==.',
Va='Vadym:BAAANQAECgQIDQAAAA==.Vail:BAAANQADCgEIAQABNQAECgkJJAANAOQZAA==.Varalic:BAABNQAECoEaAAIOAAgKEx8dEgDLAgAOAAgKEx8dEgDLAgABNQAFFAUIDgAbABMYAA==.Varandra:BAAANQAECgYIBgABNQAECgkJJAANAOQZAA==.Varidas:BAAANQAECggIEAAAAA==.Vasage:BAAANQADCgUIBQAAAA==.Vashet:BAAANQADCgcIBwAAAA==.',
Ve='Veleno:BAAANQABCgIIAgAAAA==.Ventrois:BAAANQAECggIEwABNQAECgkJIgAkAFkeAA==.Vespera:BAAANQABCgQIAgAAAA==.Veylynn:BAAANQADCgEIAQAAAA==.',
Vi='Vilienar:BAAANQAECgIIAgABNQAECgkJJAANAOQZAA==.',
Vo='Voidalic:BAACNQAFFIEOAAIbAAUKExgoBwCfAQAbAAUKExgoBwCfAQA1AAQKgSEAAx8ACQoEH9gYAHsCAB8ACQqcG9gYAHsCABsAAwpDIHhVAP0AAAAA.Voidrend:BAACNQAFFIEYAAMfAAYKQhSdBgCQAQAfAAUKkRSdBgCQAQAbAAMKUgwSDgDkAAA1AAQKgS0ABB8ACQrpIGURAM8CAB8ACQpjHmURAM8CABsABQouF9JFAF8BABEAAQojEWQrADMAAAAA.',
Vu='Vuldon:BAAANQADCgYIBgAAAA==.Vuloolu:BAAANQAECgYIDgAAAA==.',
Vy='Vynese:BAAANQADCgUIBwAAAA==.',
['Vø']='Vøgue:BAABNQAECoEnAAIOAAkKXQ3SKQATAgAOAAkKXQ3SKQATAgAAAA==.',
Wa='Warbidet:BAABNQAECoEbAAINAAgKpB1+RQCfAgANAAgKpB1+RQCfAgAAAA==.Warmason:BAABNQAECoEgAAIYAAYKBAZs0gAWAQAYAAYKBAZs0gAWAQAAAA==.Washed:BAABNQAECoElAAQLAAgKyhQJjACaAQALAAYKQhQJjACaAQAPAAMKrQ+QQwCsAAAhAAIKLBEkHAB5AAAAAA==.',
We='Wealthy:BAABNQAECoEoAAIUAAgKOx1TLQCTAgAUAAgKOx1TLQCTAgAAAA==.',
Wh='Whispere:BAABNQAECoEYAAIDAAkKmBhNfABuAgADAAkKmBhNfABuAgAAAA==.',
Wi='Wiiska:BAAANQADCgQIBAAAAA==.',
Wr='Wrred:BAAANQAECgQICgAAAA==.',
Xp='Xpredator:BAAANQADCgIIAgAAAA==.',
Ye='Yetifunk:BAAANQAECgQIBwAAAA==.',
Yo='Yoloswagging:BAAANQADCgEIAQABNQAECgYICwAHAAAAAA==.Yougotfuxed:BAAANQADCgEIAQAAAA==.Yourpal:BAABNQAECoEnAAINAAgKvR1/RgCbAgANAAgKvR1/RgCbAgAAAA==.',
Ze='Zemi:BAABNQAECoEnAAIkAAkK1g2EDwBXAgAkAAkK1g2EDwBXAgAAAA==.Zenethrius:BAAANQABCgUJBAAAAA==.Zenlol:BAAANQAECgQIBAABNQAECgkJIgAfAP8cAA==.Zephang:BAABNQAECoEWAAIcAAgKbg8DKgCbAQAcAAgKbg8DKgCbAQABNQAFFAEIAQAHAAAAAA==.Zephyubi:BAAANQAFFAEIAQAAAA==.Zeros:BAAANQAECgMIAwAAAA==.Zevalia:BAABNQAECoEZAAIXAAcK6xvrCwApAgAXAAcK6xvrCwApAgAAAA==.',
Zo='Zophia:BAAANQADCgUICQAAAA==.',
Zu='Zugrotic:BAABNQAECoEhAAIJAAgK0hnvOABsAgAJAAgK0hnvOABsAgAAAA==.Zumy:BAABNQAECoEcAAIJAAgKHiILHwD1AgAJAAgKHiILHwD1AgAAAA==.Zuzzy:BAAANQAECgEIAwAAAA==.',
['ße']='ßelle:BAAANQAECgQIBAAAAA==.',
['ßl']='ßlade:BAAANQAECgQIBwAAAA==.',
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
