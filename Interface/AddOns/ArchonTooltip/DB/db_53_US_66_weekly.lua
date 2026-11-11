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

local lookup = {'Paladin-Holy','Paladin-Protection','Paladin-Retribution','Warrior-Protection','Warrior-Arms','Unknown-Unknown','DeathKnight-Blood','Hunter-BeastMastery','Shaman-Elemental','Rogue-Assassination','Mage-Frost','Warlock-Demonology','Shaman-Restoration','Rogue-Subtlety','Evoker-Devastation','Evoker-Preservation','Mage-Arcane','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','Priest-Holy','Monk-Mistweaver','Druid-Guardian','DeathKnight-Unholy','Priest-Shadow','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Windwalker','Druid-Feral','Druid-Balance','Druid-Restoration','DeathKnight-Frost','Hunter-Marksmanship','Hunter-Survival','Priest-Discipline','Evoker-Augmentation','Warrior-Fury',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abaddôn:BAAANQADCgYIBgAAAA==.',
Ad='Adirolf:BAAANQAECgYIEgAAAA==.',
Ae='Aedonis:BAAANQAECgUIBwAAAA==.Aenlori:BAAANQADCgYIBgABNQAFFAcIDgABADIQAA==.Aenlorie:BAACNQAFFH8OAAMBAAcKMhD1DgB1AQABAAYKswz1DgB1AQACAAEKfAMrEgA7AAA1AAQKf0cABAEACgo4G4USABgDAAEACgo4G4USABgDAAMABQr9Fi3uAEABAAIABAryE7pJAMUAAAAA.',
Ag='Ag:BAAANQADCgMIAgAAAA==.Agesilaus:BAAANQADCgEIAQAAAA==.Aggathon:BAEBNQAECn83AAMEAAoKvRGDDgC3AQAEAAoKvRGDDgC3AQAFAAQKvQSj3QCkAAAAAA==.',
Ak='Akebono:BAAANQADCgUIBQAAAA==.Akusai:BAAANQADCgYIEgABNQAECgQIEAAGAAAAAA==.',
Al='Aldebaran:BAAANQAECgQICAAAAA==.Alhae:BAAANQABCgcIDgAAAA==.Alphatanker:BAACNQAFFH8JAAIHAAMKFCYOEQBGAQAHAAMKFCYOEQBGAQA1AAQKfzcAAgcACgrKJnsAAPkDAAcACgrKJnsAAPkDAAAA.',
Am='Amakadavra:BAAANQABCgEIAQAAAA==.',
Ar='Argentino:BAAANQAECgIIBQAAAA==.',
As='Ashke:BAABNQAECn89AAIIAAoKUhgGOgBVAgAIAAoKUhgGOgBVAgAAAA==.',
Au='Aurica:BAAANQAECgYIBwAAAA==.',
Ax='Axes:BAAANQAECgQIEwAAAA==.',
Ba='Badlucklouie:BAABNQAECn83AAIJAAoK+hmIMQD8AQAJAAoK+hmIMQD8AQAAAA==.Badpenny:BAAANQAECgEIAQAAAA==.Bajenkas:BAAANQADCgYIBgAAAA==.Balfas:BAAANQAECgUIDwAAAA==.',
Be='Beaupeep:BAAANQAECgQIEAAAAA==.Beesty:BAAANQAECgMIBAAAAA==.',
Bi='Bighorner:BAAANQADCgQIBAAAAA==.Bigkahunas:BAAANQAECgEIAQAAAA==.Bigwarlock:BAAANQAECgMIBQAAAA==.Bindicrippa:BAAANQADCgcIFAAAAA==.',
Bl='Blackwater:BAABNQAECn8nAAIKAAgKABx7NAAJAgAKAAgKABx7NAAJAgAAAA==.Blissey:BAAANQABCgYICgABNQAECgoKRgALAN0iAA==.Bloodstyx:BAAANQAECgQICAABNQAECgoKLQAHAF0hAA==.',
Bo='Bobi:BAAANQAECgUIDAAAAA==.Boyacky:BAAANQAECgQIBAAAAA==.',
Br='Braiglock:BAABNQAECn8eAAIMAAcK5QccpwDzAAAMAAcK5QccpwDzAAAAAA==.Bratty:BAAANQADCggIDgAAAA==.',
Bu='Bucko:BAABNQAECn8wAAIIAAoKgRcyRAA4AgAIAAoKgRcyRAA4AgAAAA==.',
By='Bygz:BAABNQAECn8aAAMJAAcKwSJbTQBBAgAJAAcKwSJbTQBBAgANAAQK2B5qbgBRAQABNQAFFAkJHAAOANUcAA==.',
['Bé']='Béésty:BAAANQAECgMICAAAAA==.',
Ca='Caarjack:BAACNQAFFH8HAAMPAAQK3wvBBQB5AAAPAAMK3wvBBQB5AAAQAAIKCQtZGABDAAA1AAQKfzcAAxAACgr8GWAQAKMCABAACQoyGWAQAKMCAA8ABwpUGbQOAEUBAAAA.Callmefury:BAAANQAECgYIEgAAAA==.Callmeheal:BAAANQAECgUIEgAAAA==.Callmemommy:BAAANQAECgEIAQAAAA==.Casserole:BAABNQAECn8dAAIRAAkKMxSK1wDYAQARAAkKMxSK1wDYAQAAAA==.Catadelic:BAABNQAECn83AAIIAAoK1Qx6YQDrAQAIAAoK1Qx6YQDrAQAAAA==.',
Ce='Celestial:BAABNQAECn8zAAMSAAoKNxRsBAC4AQASAAoKNxRsBAC4AQATAAIKzgPAIwBhAAAAAA==.',
Ch='Chewwbacca:BAABNQAECn8aAAQSAAgKyB2NBADhAgASAAgKyB2NBADhAgATAAEKXhRGKQBHAAAMAAEKNAl2RgEwAAAAAA==.Chewwy:BAAANQADCgUIBQABNQAECggIGgASAMgdAA==.Chewwyy:BAAANQADCggICgABNQAECggIGgASAMgdAA==.Chud:BAAANQAECgEIAgAAAA==.Chuwy:BAAANQADCgMIAwABNQAECggIGgASAMgdAA==.Chyse:BAAANQABCggIFAAAAA==.',
Cl='Clap:BAAANQADCgYIBgAAAA==.Cleombrotus:BAAANQADCgQIBAAAAA==.',
Cu='Cuzigothigh:BAAANQABCgIIAwAAAA==.',
Da='Darkdemon:BAACNQAFFH8OAAIUAAcKiRAMAwB3AQAUAAcKiRAMAwB3AQA1AAQKf18AAhQACgoBJa0CALEDABQACgoBJa0CALEDAAAA.Darkladyann:BAABNQAECn8eAAIVAAkKWBNJaQCJAQAVAAkKWBNJaQCJAQABNQAECgoKQAAMAAoaAA==.Darkxnemesis:BAABNQAECn8UAAIJAAgKxBRJVQBwAQAJAAgKxBRJVQBwAQAAAA==.',
De='Deadlee:BAABNQAECn89AAIWAAoKZh2HBgAOAwAWAAoKZh2HBgAOAwAAAA==.Deadnehen:BAAANQAECgEIAQABNQAECgoKLAAXAK0iAA==.Deathphish:BAABNQAECn82AAMHAAoKwxaOIADnAQAHAAoKYBaOIADnAQAYAAoKCxAlKgCAAQAAAA==.Dentfry:BAABNQAECn8XAAIVAAkKtROYZwDoAQAVAAkKtROYZwDoAQAAAA==.Derfla:BAAANQAECgYIEwAAAA==.Deshler:BAABNQAECn8bAAMEAAYK5BNsIQDZAAAEAAYK5BNsIQDZAAAFAAEKbQRkXQEpAAAAAA==.Dethblazé:BAAANQAECgQIEgAAAA==.Dethbringér:BAAANQAECgMIBAAAAA==.Detthshot:BAAANQAECgQICAAAAA==.Dezign:BAABNQAECn8hAAMVAAoKLCL5EQA5AwAVAAoKLCL5EQA5AwAZAAYK2BF/KQAhAQABNQAFFAgIIAALAAMdAA==.',
Di='Dildro:BAABNQAECn8VAAMEAAUKRQ6xLwB1AAAFAAUK2ApD8wD5AAAEAAUKRAuxLwB1AAAAAA==.Dimhammer:BAAANQAECgUIBQAAAA==.Dirtyblonde:BAAANQAECgMIAwAAAA==.Ditlutz:BAABNQAECn82AAICAAoKoiUiAgBXAwACAAoKoiUiAgBXAwAAAA==.',
Do='Dom:BAACNQAFFH8UAAIFAAcKjRUECgCQAQAFAAcKjRUECgCQAQA1AAQKfzMAAgUACgqNITMiAK8CAAUACgqNITMiAK8CAAAA.Doronjo:BAAANQADCggIDAAAAA==.Dorz:BAAANQAECgMIAwAAAA==.Dotrammy:BAAANQADCgcICQAAAA==.',
Du='Dupeslicate:BAABNQAECn8XAAIRAAkK1A9a3ADPAQARAAkK1A9a3ADPAQAAAA==.',
Dw='Dwanco:BAAANQADCgEIAQAAAA==.Dwarfussy:BAAANQADCgMIAwAAAA==.',
Dy='Dybby:BAABNQAECn8dAAIRAAgKTRmQewChAQARAAgKTRmQewChAQAAAA==.Dylexek:BAAANQADCgEIAQAAAA==.Dynamite:BAAANQADCgQIBAAAAA==.',
['Dé']='Détth:BAAANQAECgQIDQAAAA==.',
El='Elderoth:BAABNQAECn8dAAIRAAoKGRkVYwC4AgARAAoKGRkVYwC4AgAAAA==.Elfsky:BAAANQADCgUJBQAAAA==.',
En='Endlessnight:BAABNQAECn8tAAIHAAoKXSGoFgBEAgAHAAoKXSGoFgBEAgAAAA==.Envion:BAAANQADCgMIAwAAAA==.',
Er='Erica:BAAANQAECgQIBAAAAA==.',
['Eä']='Eärendil:BAABNQAECn8dAAIVAAkKCQOCiAAnAQAVAAkKCQOCiAAnAQAAAA==.',
Fa='Faebryn:BAAANQADCggIFAAAAA==.Faevor:BAABNQAECn8rAAMJAAoKbRFTPQDJAQAJAAoKbRFTPQDJAQANAAMKKRy1zADOAAAAAA==.',
Fe='Femfatal:BAAANQAECgQIBAABNQAECgoKLQAHAF0hAA==.Fenirean:BAAANQAECgUICQAAAA==.',
Fl='Flirts:BAAANQAECgEIAQAAAA==.',
Fo='Forcas:BAABNQAECn9HAAMaAAoKmyBIBgAsAgAaAAgK5yFIBgAsAgAbAAoKbxPaHwD4AQAAAA==.',
Fu='Fundus:BAABNQAECn8UAAIHAAoK3BHNIADlAQAHAAoK3BHNIADlAQAAAA==.',
Ga='Gamarrick:BAABNQAECn8XAAIZAAoK6QZpMgDjAAAZAAoK6QZpMgDjAAAAAA==.',
Ge='Germain:BAAANQADCgIIAgAAAA==.',
Gn='Gnometzu:BAAANQADCggIDgAAAA==.',
Go='Golddicmove:BAAANQAECgQIDQAAAA==.',
Gr='Gremmel:BAAANQAECgQIBQAAAA==.Griever:BAACNQAFFH8GAAMSAAMKvQ9kBgCOAAASAAIKxQ5kBgCOAAAMAAEKrhHRMgBNAAA1AAQKf1UABBMACgpBIGQNAEsBAAwABwrCHTSBAOMBABMABAqGG2QNAEsBABIAAwoFIpArACIBAAAA.',
Gu='Guillak:BAABNQAECn8mAAMMAAgK6A+qeABeAQAMAAgK6A+qeABeAQASAAIK6Qn+ZABaAAAAAA==.',
Ha='Hadroldel:BAABNQAECn8rAAIIAAoK4xnpKgCHAgAIAAoK4xnpKgCHAgAAAA==.Hammond:BAAANQADCgMICAAAAA==.Hanraktah:BAAANQADCgUIBQAAAA==.Harlem:BAAANQABCgQIBAAAAA==.Harxx:BAAANQADCgUICgAAAA==.Hatka:BAABNQAECn8cAAINAAYKnxiaVwCeAQANAAYKnxiaVwCeAQABNQAECggIDwAGAAAAAA==.Hattori:BAAANQAECgEIAQAAAA==.',
Hi='Higurashi:BAAANQABCgQIBwAAAA==.',
Ho='Holymanson:BAAANQAECgMJBQAAAA==.Hoofington:BAABNQAECn8qAAIXAAcKYx+iFAAcAgAXAAcKYx+iFAAcAgAAAA==.Howlingdoom:BAAANQADCgYIBgAAAA==.',
Hy='Hylexerr:BAAANQAECgMIAwAAAA==.',
Ib='Ibull:BAAANQADCggICQAAAA==.',
If='Iffy:BAABNQAECn8qAAIIAAoKbhwFSQCRAgAIAAoKbhwFSQCRAgAAAA==.',
Il='Ilian:BAABNQAECn8bAAIcAAkK3xhoHABWAgAcAAkK3xhoHABWAgAAAA==.',
In='Iniquity:BAAANQADCggIFAAAAA==.',
It='It:BAAANQAECgUIBQAAAA==.',
Ja='Jabiso:BAABNQAECn8oAAIJAAoKehJ3UgAvAgAJAAoKehJ3UgAvAgAAAA==.Jackthebeast:BAAANQAECgEIAQABNQAECgoKKQAJAJQfAA==.Jackthefel:BAAANQAECgUIBwABNQAECgoKKQAJAJQfAA==.Jackthetotem:BAABNQAECn8pAAIJAAoKlB/UHgASAwAJAAoKlB/UHgASAwAAAA==.Jain:BAAANQAECgYIBwAAAA==.Javaxpress:BAAANQAECgQIBgAAAA==.',
Jd='Jdmagisdh:BAAANQAECgIIAgABNQAECgoKMwAdADElAA==.Jdmagisdk:BAAANQAECgMIAwABNQAECgoKMwAdADElAA==.Jdmagisdruid:BAABNQAECn8zAAMdAAoKMSX8AQA8AwAdAAoKMSX8AQA8AwAeAAIKbx3IjgCbAAAAAA==.Jdmagisevokr:BAAANQAECgMIAwABNQAECgoKMwAdADElAA==.Jdmagishuntr:BAAANQAECgMIAwABNQAECgoKMwAdADElAA==.Jdmagislock:BAAANQAECgEIAgABNQAECgoKMwAdADElAA==.Jdmagismage:BAAANQAECgQIBAABNQAECgoKMwAdADElAA==.Jdmagismonk:BAAANQAECgIIAgABNQAECgoKMwAdADElAA==.Jdmagispally:BAAANQAECgIIAgABNQAECgoKMwAdADElAA==.Jdmagisprst:BAAANQAECgQIBAABNQAECgoKMwAdADElAA==.Jdmagisrogue:BAAANQAECgMIAwABNQAECgoKMwAdADElAA==.Jdmagissham:BAAANQAECgMIAwABNQAECgoKMwAdADElAA==.Jdmagiswarr:BAAANQAECgQIAwABNQAECgoKMwAdADElAA==.',
Je='Jeanne:BAABNQAECn8wAAMZAAoKlgl1KgAZAQAZAAkKEAZ1KgAZAQAVAAgKPgHF1gCkAAAAAA==.Jedoniah:BAAANQAECggIEAAAAA==.Jezabel:BAAANQADCgIIAgAAAA==.',
Ji='Jizzdiddy:BAAANQAECgUIBAAAAA==.',
Jo='Jolnir:BAAANQAECgQIBAABNQAECgoKNgADAOccAA==.Jorcingmyshi:BAAANQAECggIEwAAAA==.Jorhmont:BAAANQADCgUIBQAAAA==.',
Ju='Juan:BAABNQAECn8zAAMfAAgKoxjsHgDqAQAfAAgKoxjsHgDqAQAeAAIK+QNdigArAAAAAA==.Jumpeor:BAACNQAFFH8RAAMDAAgKyxfWBAAUAgADAAcKEBjWBAAUAgACAAEKcBZ/DwBOAAA1AAQKfz4AAgMACgqFJWEEANcDAAMACgqFJWEEANcDAAAA.',
Ka='Kanig:BAAANQADCggJEgAAAA==.Kassey:BAAANQAECgEIAQAAAA==.Katacola:BAACNQAFFH8YAAIfAAcKgRlKAwAYAgAfAAcKgRlKAwAYAgA1AAQKfzcAAx8ACgq1JM0FAGYDAB8ACgq1JM0FAGYDAB4ABwp5FrEuAHgBAAAA.',
Ke='Keg:BAAANQAECgEIAQAAAA==.Kenaf:BAAANQADCgQIBwAAAA==.Kendrys:BAABNQAECn8VAAQHAAkKLxAyZABhAQAHAAkK4Q8yZABhAQAgAAUK2wnHbQDnAAAYAAIKuwRf0QBLAAAAAA==.Kethria:BAAANQAECggIDgABNQAECgkJOwAIAEgjAA==.Kevenal:BAABNQAECn8uAAIhAAoKLh9aEADlAgAhAAoKLh9aEADlAgAAAA==.Keyainor:BAAANQADCggIDgABNQAECgcIDwAGAAAAAA==.',
Ki='Kikiliki:BAABNQAECn8VAAIIAAYKWg8o5wAzAQAIAAYKWg8o5wAzAQAAAA==.Killmartin:BAABNQAECn8YAAIgAAgKewEwogBKAAAgAAgKewEwogBKAAAAAA==.Kinneas:BAABNQAECn8bAAIDAAkKvxYSUAClAgADAAkKvxYSUAClAgAAAA==.Kizmit:BAAANQAECgUIBwAAAA==.',
Kl='Klënz:BAAANQAECgEIAQAAAA==.',
Ko='Koa:BAAANQAECgQICgAAAA==.',
Ku='Kurau:BAABNQAECn8UAAIiAAcK6gS8CwAwAQAiAAcK6gS8CwAwAQAAAA==.Kurzal:BAABNQAECn8WAAINAAgKIA3ieQAvAQANAAgKIA3ieQAvAQAAAA==.',
Ky='Kyraz:BAACNQAFFH8cAAMOAAkK1RwFAgBUAgAOAAcKRB4FAgBUAgAKAAcK8BxgAwAuAgA1AAQKfyAAAw4ACgo0Jn0BAIYDAA4ACQo0Jn0BAIYDAAoACQrgIrcHAFkDAAAA.',
La='Lacie:BAABNQAECn8jAAIIAAYK5AfszgBjAQAIAAYK5AfszgBjAQAAAA==.Lavos:BAAANQAECgMIBgABNQAECgoKMwADAFUeAA==.',
Le='Leela:BAAANQAECggICAAAAA==.Lexy:BAAANQAECgEIAQABNQAECgoKOgAUAKYfAA==.',
Li='Lily:BAAANQAECgQIBAAAAA==.',
Lo='Lokiel:BAAANQAECgQICgAAAA==.Lokifurion:BAABNQAECn8zAAMfAAoKtA9yIADbAQAfAAoKtA9yIADbAQAeAAQKHgMvkwCLAAAAAA==.Lokisson:BAAANQAECgEIAQAAAA==.',
Lu='Lunitari:BAAANQAECgIIBgAAAA==.',
Ly='Lyaenna:BAABNQAECn8oAAIVAAoKLhrtIgC5AgAVAAoKLhrtIgC5AgAAAA==.',
Ma='Mageshir:BAAANQAECggICAAAAA==.Magrat:BAAANQAECgUIBQAAAA==.Mahu:BAAANQAECgQIBAAAAA==.Malchi:BAAANQAECgUIBQABNQAFFAgIGgAKADgdAA==.Maletherion:BAABNQAECn8zAAIhAAoKLxd8EQAYAgAhAAoKLxd8EQAYAgAAAA==.Maltherion:BAABNQAECn8iAAMbAAoKHRpWIACXAgAbAAoKHRpWIACXAgAUAAEKAAA9dAAmAAAAAA==.Margareetah:BAAANQAECgQIEAAAAA==.Martinix:BAAANQAECggIBwAAAA==.Mathielshank:BAAANQADCgUIBQAAAA==.',
Me='Meglamonk:BAABNQAECn8ZAAIcAAgKSQlAKwAnAQAcAAgKSQlAKwAnAQAAAA==.',
Mi='Milarca:BAAANQABCgYIDQAAAA==.Minireaper:BAAANQADCgMIAwAAAA==.Misbehavin:BAAANQADCgQIBAAAAA==.',
Mj='Mjolnir:BAABNQAECn82AAIDAAoK5xyfPwBcAgADAAoK5xyfPwBcAgAAAA==.',
Mo='Mochizuko:BAAANQABCgIIAgAAAA==.Mongke:BAAANQADCggICAAAAA==.Mononokè:BAAANQABCgIIAgAAAA==.Moonre:BAAANQADCgYIEgAAAA==.',
Mu='Mubvan:BAAANQAECgYIDgAAAA==.Mushroommans:BAAANQAECgQICgABNQAFFAMIBgAUAPMhAA==.',
My='Mystaris:BAAANQADCgYICgAAAA==.',
Na='Namôr:BAAANQAECgEIAQAAAA==.Narzel:BAAANQAECgYIEgAAAA==.Nashîr:BAABNQAECn8oAAIFAAoKNRUGWwDaAQAFAAoKNRUGWwDaAQAAAA==.Navybum:BAABNQAECn8aAAIPAAUKuQXWGwB5AAAPAAUKuQXWGwB5AAAAAA==.',
Ne='Nehemiah:BAABNQAECn88AAMEAAoKKyK2BADIAgAEAAoKKyK2BADIAgAFAAEKPxovRQFHAAAAAA==.Nequin:BAABNQAECn8wAAIBAAoKTx6CDwA1AwABAAoKTx6CDwA1AwABNQAECgoKNQANAOMgAA==.Nequins:BAAANQAECgcIEQABNQAECgoKNQANAOMgAA==.Nequinss:BAABNQAECn81AAINAAoK4yALHwCvAgANAAoK4yALHwCvAgAAAA==.Nevermore:BAAANQAECgEIAQAAAA==.',
Ni='Nicabar:BAABNQAECn88AAIMAAoKZAm0hgA8AQAMAAoKZAm0hgA8AQAAAA==.Nilfheim:BAAANQAECgUICQAAAA==.Nivla:BAAANQAECgEIAQAAAA==.',
No='Noadie:BAAANQAECgcIBgAAAA==.Noehtyar:BAABNQAECn8ZAAIIAAYKQQkK8AAiAQAIAAYKQQkK8AAiAQAAAA==.Noie:BAABNQAECn8dAAILAAoKvAMCIQC8AAALAAoKvAMCIQC8AAAAAA==.Novadd:BAAANQADCgUIBQAAAA==.Novä:BAAANQAECgQIBAAAAA==.Noztalgia:BAAANQAECgQICAAAAA==.',
['Në']='Nëklaüs:BAABNQAECn8kAAIHAAYKsRWqZgBYAQAHAAYKsRWqZgBYAQAAAA==.',
Od='Odanarratite:BAAANQAECgEIAQAAAA==.Odanarrayne:BAAANQAECgEIAQAAAA==.Oditte:BAAANQADCggIDgAAAA==.Odysseuss:BAAANQAECgUICQAAAA==.',
Oi='Oilliphéist:BAAANQAECgUIBwAAAA==.',
On='Onewithyou:BAAANQADCgEIAQAAAA==.Onimaru:BAAANQAECgEIAQAAAA==.',
Or='Ornot:BAACNQAFFH8FAAINAAIKyAfZIwBvAAANAAIKyAfZIwBvAAA1AAQKfzwAAg0ACgp1EL5bAPwBAA0ACgp1EL5bAPwBAAAA.',
Os='Oshdruid:BAAANQADCgYICwAAAA==.',
Pa='Paislìe:BAAANQADCggICAAAAA==.Palacola:BAAANQAECgcIBwABNQAFFAgIGAAfAIEZAA==.Pandurbear:BAAANQAECgEIAQAAAA==.Paperplate:BAABNQAECn8pAAIBAAoK3RS9LgBXAgABAAoK3RS9LgBXAgABNQAECgoKPwARABMNAA==.Paws:BAAANQADCgMJBgAAAA==.',
Pe='Peposhammy:BAAANQADCgUIBQAAAA==.',
Ph='Phuul:BAAANQADCgMIAwABNQAECgYIBgAGAAAAAA==.Phuulith:BAAANQADCgYIEQABNQAECgYIBgAGAAAAAA==.',
Pi='Picantechode:BAAANQAECgEIAgAAAA==.',
Pr='Provost:BAABNQAECn8zAAIDAAoKVR7xPQBiAgADAAoKVR7xPQBiAgAAAA==.',
Ps='Psychonoia:BAABNQAECn8eAAIZAAoKbRJmKgDUAQAZAAoKbRJmKgDUAQAAAA==.',
Pu='Pumperdogx:BAAANQAECgEIAQABNQAFFAMICQAHABQmAA==.Pumpkinpîe:BAAANQADCgYIBgAAAA==.',
Qu='Quadritrix:BAAANQADCgQIBAAAAA==.Quanx:BAAANQAECgcICQAAAA==.Quark:BAAANQAECgIIAgAAAA==.',
Ra='Ratacola:BAAANQAECgQICAABNQAFFAgIGAAfAIEZAA==.',
Re='Remulüs:BAABNQAECn86AAMUAAoKph/IDwD1AgAUAAoKph/IDwD1AgAbAAUKlRJRWQAiAQAAAA==.Reoãn:BAAANQABCgQIBgABNQADCgUIBQAGAAAAAA==.',
Ri='Riah:BAAANQAECgIIAgAAAA==.Riilyn:BAABNQAECn82AAMKAAoKxBiaHQCTAgAKAAkKERmaHQCTAgAOAAoKRxIaMwAbAgAAAA==.',
['Rø']='Røean:BAAANQADCgUIBQAAAA==.',
Sa='Saintmartin:BAAANQAECggIBgAAAA==.Sanktis:BAAANQADCggIFgAAAA==.',
Sb='Sbcarpenter:BAAANQAECgMIAgAAAA==.',
Sc='Scawmfhealz:BAAANQAECgEIAQAAAA==.Scecretzs:BAAANQADCgYIEQAAAA==.',
Se='Sebone:BAAANQADCggIDQAAAA==.Secretz:BAABNQAECn8eAAQVAAgKrB3OPwAkAgAVAAgKOB3OPwAkAgAjAAMKjw0gGgCaAAAZAAQKgQqoQgCOAAAAAA==.Sedrelari:BAABNQAECn87AAMIAAkKSCMzIAAXAwAIAAgKwCIzIAAXAwAiAAgKnBwaBwASAgAAAA==.Seizethesol:BAAANQAECgYICQAAAA==.Sengseng:BAAANQADCgUIBgAAAA==.Sephirøth:BAAANQAECgcICgAAAA==.Sepsis:BAAANQAECgUIEAAAAA==.Serjaime:BAAANQAECgEIAQAAAA==.Sesamo:BAACNQAFFH8IAAIDAAQKOA44IgCHAAADAAQKOA44IgCHAAA1AAQKfy8AAgMACgqQHDtIALwCAAMACgqQHDtIALwCAAAA.',
Sh='Shadedstørmz:BAAANQAECgMIBwAAAA==.Shocks:BAABNQAECn8aAAIJAAUKHxApuwAcAQAJAAUKHxApuwAcAQAAAA==.Shé:BAABNQAECn8kAAICAAkK9xg8HQABAgACAAkK9xg8HQABAgAAAA==.',
Si='Sixoneseven:BAAANQAECgQIBgAAAA==.Sixseven:BAABNQAECn8wAAMUAAoKahFZGgDHAQAUAAoKahFZGgDHAQAaAAoKZAsqEAAuAQAAAA==.',
Sk='Skaarlett:BAAANQAECgQIBgAAAA==.Skone:BAABNQAECn8dAAMBAAgKlgmWhQCKAQABAAgKlgmWhQCKAQADAAEKEQPazQEhAAAAAA==.',
Sm='Smarthen:BAAANQAECgEIBAABNQAECgoKLAAXAK0iAA==.Smolhatka:BAAANQAECggIDwAAAA==.',
Sn='Snickers:BAABNQAECn8bAAIkAAkK0g8MDACZAQAkAAkK0g8MDACZAQAAAA==.',
So='Solarian:BAABNQAECn8vAAIUAAgK7hJsMAC/AQAUAAgK7hJsMAC/AQAAAA==.',
St='Starosa:BAAANQADCgEIAQAAAA==.Startle:BAAANQADCggIIQAAAA==.Steelbreeze:BAAANQAECgQIEQAAAA==.Storms:BAACNQAFFH8IAAMLAAMK/xegDABXAAARAAIKShJITgCJAAALAAEKsx2gDABXAAA1AAQKf0MAAxEACgrmIqBNAOYCABEACgpqHqBNAOYCAAsAAwrdJAcYADkBAAAA.Stoutbringer:BAAANQAECgQICwAAAA==.Stride:BAAANQAECgEIAQABNQAECgoKIgAPADUXAA==.Strikes:BAABNQAECn8aAAIOAAoKvxnuHACRAgAOAAoKvxnuHACRAgAAAA==.Stronknehen:BAAANQAECgQIBAABNQAECgoKLAAXAK0iAA==.',
Sy='Sylvaedir:BAAANQADCggICQAAAA==.',
['Sö']='Sören:BAABNQAECn8lAAIHAAgKuw+vQgAlAQAHAAgKuw+vQgAlAQAAAA==.',
Ta='Taomi:BAABNQAECn8qAAINAAoK8RN9MgA+AgANAAoK8RN9MgA+AgAAAA==.',
Te='Teaka:BAAANQAECgQIBwAAAA==.Tenspeed:BAABNQAECn8mAAIUAAkK6xR+HgCbAQAUAAkK6xR+HgCbAQAAAA==.Teof:BAAANQAECgUIBQAAAA==.Terelle:BAAANQAECgcIDwABNQAECggIHQABAJYJAA==.Terellesguy:BAAANQADCgQIBAABNQAECgoKNwAJAPoZAA==.Tetsuro:BAAANQADCgUIBwAAAA==.',
Th='Thire:BAAANQADCggICwABNQAECggIHQABAJYJAA==.Throwglaive:BAABNQAECn8XAAIbAAgKsRwGNAAMAgAbAAgKsRwGNAAMAgABNQAFFAkJHAAOANUcAA==.',
Ti='Tidereign:BAABNQAECn8gAAIeAAkKWQ6/MgBdAQAeAAkKWQ6/MgBdAQAAAA==.Tinytotems:BAABNQAECn8zAAINAAoKKhpIMQBEAgANAAoKKhpIMQBEAgAAAA==.Tiriell:BAABNQAECn8jAAIDAAkKUBUFewA1AgADAAkKUBUFewA1AgAAAA==.',
To='Toe:BAACNQAFFH8FAAIRAAMKCAn7OgDYAAARAAMKCAn7OgDYAAA1AAQKfxkAAhEACgrKIe8mAEUDABEACgrKIe8mAEUDAAAA.Touchmee:BAAANQADCgcIAQAAAA==.',
Tr='Trausti:BAAANQAECgUJCgAAAA==.Treehen:BAABNQAECn8sAAIXAAoKrSLIBABXAwAXAAoKrSLIBABXAwAAAA==.Trinanah:BAACNQAFFH8PAAMZAAUKBAT3DACwAAAZAAQKBAT3DACwAAAVAAEKdgA1OAA3AAA1AAQKfzQAAhkACgoOFbInAO0BABkACgoOFbInAO0BAAAA.Troltsky:BAAANQADCgQIBAAAAA==.',
['Tô']='Tôrunn:BAAANQAECgYICwABNQAECgoKHgAZAG0SAA==.',
Ut='Uthandric:BAAANQAECgQIBAABNQAECgoKNgACAKIlAA==.',
Va='Valariann:BAAANQADCggICAABNQAECgoKQgAOAGgcAA==.Valeriux:BAAANQADCgUJAwAAAA==.Valgal:BAABNQAECn8aAAIIAAYKkAha2QDjAAAIAAYKkAha2QDjAAAAAA==.Valiraste:BAABNQAECn9AAAIMAAoKCho3IQCBAgAMAAoKCho3IQCBAgAAAA==.Valor:BAAANQAECgEIAgABNQAECgoKMwADAFUeAA==.Vantois:BAAANQADCgMIAwAAAA==.Vapor:BAAANQADCgQIBAAAAA==.Varalina:BAAANQAECgQIBwAAAA==.',
Vi='Viital:BAAANQADCgYIBgAAAA==.Vischar:BAAANQADCgUIBwAAAA==.',
Vo='Voidmommy:BAAANQABCgEIAQAAAA==.',
Wa='Washbeans:BAACNQAFFH8NAAMgAAQKKB2nDQDZAAAgAAMKfxunDQDZAAAYAAMKqBswCgCmAAA1AAQKfycAAyAACQpyHkchAIMCACAACQpyHkchAIMCABgAAgoWGsGwAJEAAAAA.Wayne:BAAANQABCgQIAgAAAA==.',
We='Wef:BAABNQAECn80AAIIAAkKcg1HewCqAQAIAAkKcg1HewCqAQAAAA==.Weledronys:BAAANQADCgYICwAAAA==.',
Wh='Whyse:BAABNQAECn8/AAIRAAoKEw03awDLAQARAAoKEw03awDLAQAAAA==.',
Wi='Wings:BAABNQAECn8iAAMPAAoKNRfEDACWAgAPAAoKNRfEDACWAgAkAAEKmw3VGwA1AAAAAA==.Wintel:BAAANQAECgEIAQAAAA==.Wizaes:BAAANQAECgEIAQAAAA==.',
Wo='Woolybullie:BAAANQADCgcIBwABNQAECgcIDwAGAAAAAA==.',
Xa='Xanza:BAAANQADCggIEQAAAA==.',
Ya='Yamzaio:BAAANQADCgUJBwAAAA==.',
Yo='Yo:BAAANQADCgcIDAAAAA==.',
Za='Zancrafter:BAAANQADCgIIAgABNQAFFAQIDQAUAAsXAA==.Zandk:BAAANQAECgEIAQABNQAFFAQIDQAUAAsXAA==.Zanduwuin:BAACNQAFFH8NAAIUAAQKCxe0CADOAAAUAAQKCxe0CADOAAA1AAQKfzAAAxQACgqnG/MQAOgCABQACgqnG/MQAOgCABoAAwqfCxwoAHUAAAAA.Zanvoker:BAABNQAECn8nAAQkAAkKNRfsBwAjAgAkAAkK1RbsBwAjAgAPAAYKThFzHwBeAQAQAAcKJQnZKgBWAQABNQAFFAQIDQAUAAsXAA==.Zargar:BAABNQAECn8sAAICAAkKOR2WDQA/AgACAAkKOR2WDQA/AgAAAA==.',
Zl='Zlatah:BAAANQADCgUIBQAAAA==.',
Zo='Zorttok:BAAANQAECgEIAQAAAA==.',
Zu='Zukkario:BAACNQAFFH8UAAMFAAYKXSN1BwBIAgAFAAYKBCN1BwBIAgAlAAQKxR8BAQB6AQA1AAQKfy4AAwUACgoIJsUXAFoDAAUACgrmJcUXAFoDACUAAgq0GgInAHUAAAE1AAUUCQkcAA4A1RwA.',
Zy='Zyp:BAAANQAECgYICwAAAA==.',
['Âx']='Âxel:BAABNQAECn8xAAINAAoKtyOcDQBGAwANAAoKtyOcDQBGAwAAAA==.',
['År']='Årgon:BAABNQAECn84AAIYAAoKiRscJACxAgAYAAoKiRscJACxAgAAAA==.',
['ße']='ßen:BAAANQAECgIIAgAAAA==.',
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
