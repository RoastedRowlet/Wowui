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

local lookup = {'Paladin-Holy','Paladin-Protection','Paladin-Retribution','Warrior-Protection','Warrior-Arms','Unknown-Unknown','DeathKnight-Blood','Hunter-BeastMastery','Shaman-Elemental','Rogue-Assassination','Mage-Frost','Warlock-Demonology','Shaman-Restoration','Rogue-Subtlety','Evoker-Devastation','Evoker-Preservation','Mage-Arcane','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','Priest-Holy','Monk-Mistweaver','DeathKnight-Unholy','Priest-Shadow','DemonHunter-Vengeance','DemonHunter-Havoc','Druid-Guardian','Monk-Windwalker','Druid-Feral','Druid-Balance','Druid-Restoration','DeathKnight-Frost','Hunter-Marksmanship','Hunter-Survival','Priest-Discipline','Evoker-Augmentation','Warrior-Fury',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abaddôn:BAAANQADCgYIBgAAAA==.',
Ad='Adirolf:BAAANQAECgUIDAAAAA==.',
Ae='Aedonis:BAAANQAECgQIBAAAAA==.Aenlori:BAAANQADCgYIBgABNQAFFAcIDgABADIQAA==.Aenlorie:BAACNQAFFH8OAAMBAAcKMhD1DgB1AQABAAYKswz1DgB1AQACAAEKfAMrEgA7AAA1AAQKf0IABAEACgqnFqkZALwCAAEACgqnFqkZALwCAAMABQr9Fi3uAEABAAIABAryE7pJAMUAAAAA.',
Ag='Ag:BAAANQADCgMIAgAAAA==.Agesilaus:BAAANQADCgEIAQAAAA==.Aggathon:BAEBNQAECn8zAAMEAAoKtRFUDAC7AQAEAAoKtRFUDAC7AQAFAAQKvQRDzgClAAAAAA==.',
Ak='Akebono:BAAANQADCgUIBQAAAA==.Akusai:BAAANQADCgYIEgABNQAECgQIEAAGAAAAAA==.',
Al='Aldebaran:BAAANQAECgQIBwAAAA==.Alhae:BAAANQABCgcIDgAAAA==.Alphatanker:BAACNQAFFH8JAAIHAAMKFCYOEQBGAQAHAAMKFCYOEQBGAQA1AAQKfzcAAgcACgrKJnsAAPkDAAcACgrKJnsAAPkDAAAA.',
Am='Amakadavra:BAAANQABCgEIAQAAAA==.',
Ar='Argentino:BAAANQAECgIIBQAAAA==.',
As='Ashke:BAABNQAECn83AAIIAAoK/BfbMABRAgAIAAoK/BfbMABRAgAAAA==.',
Au='Aurica:BAAANQAECgYIBwAAAA==.',
Ax='Axes:BAAANQAECgUIDQAAAA==.',
Ba='Badlucklouie:BAABNQAECn8wAAIJAAoKCxkaPgB9AgAJAAoKCxkaPgB9AgAAAA==.Badpenny:BAAANQAECgEIAQAAAA==.Bajenkas:BAAANQADCgYIBgAAAA==.Balfas:BAAANQAECgUIDQAAAA==.',
Be='Beaupeep:BAAANQAECgQIEAAAAA==.Beesty:BAAANQAECgIIAgAAAA==.',
Bi='Bighorner:BAAANQADCgQIBAAAAA==.Bigkahunas:BAAANQAECgEIAQAAAA==.Bigwarlock:BAAANQAECgMIBgAAAA==.Bindicrippa:BAAANQADCgcIFAAAAA==.',
Bl='Blackwater:BAABNQAECn8nAAIKAAgKABx7NAAJAgAKAAgKABx7NAAJAgAAAA==.Blissey:BAAANQABCgYICgABNQAECgoKQQALANUiAA==.Bloodstyx:BAAANQAECgQICAABNQAECgoKLQAHAF0hAA==.',
Bo='Bobi:BAAANQAECgQIBgAAAA==.Boyacky:BAAANQADCgEIAQAAAA==.',
Br='Braiglock:BAABNQAECn8ZAAIMAAcK5QdirQDFAAAMAAcK5QdirQDFAAAAAA==.Bratty:BAAANQADCggIDgAAAA==.',
Bu='Bucko:BAABNQAECn8sAAIIAAkK9hd8UgDnAQAIAAkK9hd8UgDnAQAAAA==.',
By='Bygz:BAABNQAECn8ZAAMJAAcKwSJbTQBBAgAJAAcKwSJbTQBBAgANAAQK2B5mZABWAQABNQAFFAgIGwAOAHEfAA==.',
['Bé']='Béésty:BAAANQAECgQIBgAAAA==.',
Ca='Caarjack:BAACNQAFFH8HAAMPAAQK3wsTBQB9AAAPAAMK3wsTBQB9AAAQAAIKCQtZGABDAAA1AAQKfzMAAxAACgr8GWAQAKMCABAACQoyGWAQAKMCAA8ABwqGF4IOACcBAAAA.Callmefury:BAAANQAECgYIDwAAAA==.Callmeheal:BAAANQAECgQIDAAAAA==.Callmemommy:BAAANQAECgEIAQAAAA==.Casserole:BAABNQAECn8dAAIRAAkKMxSK1wDYAQARAAkKMxSK1wDYAQAAAA==.Catadelic:BAABNQAECn8zAAIIAAoKbQzfWQDSAQAIAAoKbQzfWQDSAQAAAA==.',
Ce='Celestial:BAABNQAECn8vAAMSAAkKMBSoBACIAQASAAkKMBSoBACIAQATAAIKzgPAIwBhAAAAAA==.',
Ch='Chewwbacca:BAABNQAECn8aAAQSAAgKyB2NBADhAgASAAgKyB2NBADhAgATAAEKXhRGKQBHAAAMAAEKNAl2RgEwAAAAAA==.Chewwy:BAAANQADCgUIBQABNQAECggIGgASAMgdAA==.Chewwyy:BAAANQADCggICgABNQAECggIGgASAMgdAA==.Chuwy:BAAANQADCgMIAwABNQAECggIGgASAMgdAA==.Chyse:BAAANQABCggIFAAAAA==.',
Cl='Clap:BAAANQADCgYIBgAAAA==.Cleombrotus:BAAANQADCgQIBAAAAA==.',
Cu='Cuzigothigh:BAAANQABCgIIAwAAAA==.',
Da='Darkdemon:BAACNQAFFH8NAAIUAAYKGRELBAAnAQAUAAYKGRELBAAnAQA1AAQKf1wAAhQACgoBJa0CALEDABQACgoBJa0CALEDAAAA.Darkladyann:BAABNQAECn8dAAIVAAkKWBNwYACEAQAVAAkKWBNwYACEAQAAAA==.Darkxnemesis:BAABNQAECn8UAAIJAAgKxBTkSQB0AQAJAAgKxBTkSQB0AQAAAA==.',
De='Deadlee:BAABNQAECn81AAIWAAoKIB30BQADAwAWAAoKIB30BQADAwAAAA==.Deathphish:BAABNQAECn8yAAMHAAoKYxXuJQCiAQAHAAkKxRXuJQCiAQAXAAkKfxD9LgBCAQAAAA==.Dentfry:BAABNQAECn8XAAIVAAkKtROYZwDoAQAVAAkKtROYZwDoAQAAAA==.Derfla:BAAANQAECgYIDQAAAA==.Deshler:BAABNQAECn8bAAMEAAYK5BPUHADgAAAEAAYK5BPUHADgAAAFAAEKbQRkXQEpAAAAAA==.Dethblazé:BAAANQAECgQIDQAAAA==.Dethbringér:BAAANQAECgEIAgAAAA==.Detthshot:BAAANQAECgQIBQAAAA==.Dezign:BAABNQAECn8gAAMVAAoKLCL5EQA5AwAVAAoKLCL5EQA5AwAYAAYK2BG7JAAiAQAAAA==.',
Di='Dildro:BAABNQAECn8VAAMEAAUKRQ49KgB6AAAFAAUK2ApD8wD5AAAEAAUKRAs9KgB6AAAAAA==.Dimhammer:BAAANQAECgUIBAAAAA==.Dirtyblonde:BAAANQAECgMIAwAAAA==.Ditlutz:BAABNQAECn8yAAICAAoKhSXXAQBbAwACAAoKhSXXAQBbAwAAAA==.',
Do='Dom:BAACNQAFFH8UAAIFAAcKjRVRBwCWAQAFAAcKjRVRBwCWAQA1AAQKfzIAAgUACgqNIR4cALwCAAUACgqNIR4cALwCAAAA.Doronjo:BAAANQADCggIDAAAAA==.Dorz:BAAANQADCgcIFAAAAA==.Dotrammy:BAAANQADCgcICQAAAA==.',
Du='Dupeslicate:BAABNQAECn8XAAIRAAkK1A9a3ADPAQARAAkK1A9a3ADPAQAAAA==.',
Dw='Dwanco:BAAANQADCgEIAQAAAA==.Dwarfussy:BAAANQADCgMIAwAAAA==.',
Dy='Dybby:BAABNQAECn8cAAIRAAcKyRdRugAPAgARAAcKyRdRugAPAgAAAA==.Dylexek:BAAANQADCgEIAQAAAA==.Dynamite:BAAANQADCgQIBAAAAA==.',
['Dé']='Détth:BAAANQAECgUIDQAAAA==.',
El='Elderoth:BAABNQAECn8dAAIRAAoKGRkVYwC4AgARAAoKGRkVYwC4AgAAAA==.Elfsky:BAAANQADCgUJBQAAAA==.',
En='Endlessnight:BAABNQAECn8tAAIHAAoKXSEMFABKAgAHAAoKXSEMFABKAgAAAA==.',
Er='Erica:BAAANQAECgQIBAAAAA==.',
['Eä']='Eärendil:BAABNQAECn8WAAIVAAgK3QJCiwD+AAAVAAgK3QJCiwD+AAAAAA==.',
Fa='Faebryn:BAAANQADCggIFAAAAA==.Faevor:BAABNQAECn8qAAMJAAoKDBHvNQDFAQAJAAoKDBHvNQDFAQANAAMKKRy1zADOAAAAAA==.',
Fe='Femfatal:BAAANQAECgQIBAABNQAECgoKLQAHAF0hAA==.Fenirean:BAAANQAECgUIDAAAAA==.',
Fl='Flirts:BAAANQADCgYICgAAAA==.',
Fo='Forcas:BAABNQAECn8/AAMZAAoKPh8FBwChAgAZAAgKcSEFBwChAgAaAAoKaxKqHQDlAQAAAA==.',
Fu='Fundus:BAAANQAECggIEAAAAA==.',
Ga='Gamarrick:BAABNQAECn8XAAIYAAoK6QY1LQDjAAAYAAoK6QY1LQDjAAAAAA==.Garahruon:BAAANQAECgEIAQAAAA==.',
Ge='Germain:BAAANQADCgIIAgAAAA==.',
Gn='Gnometzu:BAAANQADCggIDgAAAA==.',
Go='Golddicmove:BAAANQAECgQICgAAAA==.',
Gr='Gremmel:BAAANQADCggIDgAAAA==.Griever:BAACNQAFFH8GAAMSAAMKvQ+LBQCPAAASAAIKxQ6LBQCPAAAMAAEKrhHMLQBNAAA1AAQKf1IABBMACgqsH7IKAE8BAAwABwruHDSBAOMBABMABAplG7IKAE8BABIAAwoFIpArACIBAAAA.',
Gu='Guillak:BAABNQAECn8lAAMMAAgKjw9tbgBTAQAMAAgKjw9tbgBTAQASAAIK6Qn+ZABaAAAAAA==.',
Ha='Hadroldel:BAABNQAECn8hAAIIAAoKRxhAKwBnAgAIAAoKRxhAKwBnAgAAAA==.Hammond:BAAANQADCgMICAAAAA==.Hanraktah:BAAANQADCgUIBQAAAA==.Harlem:BAAANQABCgQIBAAAAA==.Harxx:BAAANQADCgUICgAAAA==.Hatka:BAABNQAECn8YAAINAAYKjhNoZQBTAQANAAYKjhNoZQBTAQAAAA==.Hattori:BAAANQABCgUIBQAAAA==.',
Hi='Higurashi:BAAANQABCgQIBwAAAA==.',
Ho='Holymanson:BAAANQAECgMJAwAAAA==.Hoofington:BAABNQAECn8jAAIbAAcKYx+iFAAcAgAbAAcKYx+iFAAcAgAAAA==.Howlingdoom:BAAANQADCgYIBgAAAA==.',
Hy='Hylexerr:BAAANQAECgEIAgAAAA==.',
Ib='Ibull:BAAANQADCggICQAAAA==.',
If='Iffy:BAABNQAECn8pAAIIAAkKOxwFSQCRAgAIAAkKOxwFSQCRAgAAAA==.',
Il='Ilian:BAABNQAECn8bAAIcAAkK3xhoHABWAgAcAAkK3xhoHABWAgAAAA==.',
In='Iniquity:BAAANQADCggIFAAAAA==.',
It='It:BAAANQAECgcIBwAAAA==.',
Ja='Jabiso:BAABNQAECn8oAAIJAAoKehJ3UgAvAgAJAAoKehJ3UgAvAgAAAA==.Jackthebeast:BAAANQAECgEIAQABNQAECgoKJQAJAJQfAA==.Jackthefel:BAAANQAECgUIBQABNQAECgoKJQAJAJQfAA==.Jackthetotem:BAABNQAECn8lAAIJAAoKlB/UHgASAwAJAAoKlB/UHgASAwAAAA==.Jain:BAAANQAECgYIBwAAAA==.Javaxpress:BAAANQAECgIIAgAAAA==.',
Jd='Jdmagisdruid:BAABNQAECn8xAAMdAAoKMSWCAQBFAwAdAAoKMSWCAQBFAwAeAAIKbx3IjgCbAAAAAA==.Jdmagishuntr:BAAANQAECgEIAQABNQAECgoKMQAdADElAA==.Jdmagislock:BAAANQAECgIIAwABNQAECgoKMQAdADElAA==.Jdmagisrogue:BAAANQAECgIIAgABNQAECgoKMQAdADElAA==.Jdmagissham:BAAANQAECgIIAgABNQAECgoKMQAdADElAA==.Jdmagiswarr:BAAANQADCgEIAQABNQAECgoKMQAdADElAA==.',
Je='Jeanne:BAABNQAECn8oAAMYAAkK0Al9KwDvAAAYAAgKvgV9KwDvAAAVAAgKPgHF1gCkAAAAAA==.Jedoniah:BAAANQAECgYICgAAAA==.Jezabel:BAAANQADCgIIAgAAAA==.',
Ji='Jizzdiddy:BAAANQAECgUIAwAAAA==.',
Jo='Jolnir:BAAANQADCgcIBwABNQAECgoKMgADAOIcAA==.Jorcingmyshi:BAABNQAECn8UAAINAAkKIxQebQDEAQANAAkKIxQebQDEAQAAAA==.Jorhmont:BAAANQADCgUIBQAAAA==.',
Ju='Juan:BAABNQAECn8xAAMfAAgKoxhMGwDgAQAfAAgKoxhMGwDgAQAeAAIK+QOqgQArAAAAAA==.Jumpeor:BAACNQAFFH8QAAMDAAcKnxjWBAAUAgADAAYKKhnWBAAUAgACAAEKcBZ/DwBOAAA1AAQKfz4AAgMACgqFJWEEANcDAAMACgqFJWEEANcDAAAA.',
Ka='Kanig:BAAANQADCggJEgAAAA==.Kassey:BAAANQAECgEIAQAAAA==.Katacola:BAACNQAFFH8YAAIfAAcKgRlKAwAYAgAfAAcKgRlKAwAYAgA1AAQKfzcAAx8ACgq1JM0FAGYDAB8ACgq1JM0FAGYDAB4ABwp5FnApAHsBAAAA.',
Ke='Keg:BAAANQAECgEIAgAAAA==.Kenaf:BAAANQADCgQIBwAAAA==.Kendrys:BAABNQAECn8VAAQHAAkKLxAyZABhAQAHAAkK4Q8yZABhAQAgAAUK2wnHbQDnAAAXAAIKuwRf0QBLAAAAAA==.Kethria:BAAANQAECgYIBwABNQAECgkJOwAIAEgjAA==.Kevenal:BAABNQAECn8uAAIhAAoKLh9aEADlAgAhAAoKLh9aEADlAgAAAA==.Keyainor:BAAANQADCggIDgABNQAECggIDAAGAAAAAA==.',
Ki='Kikiliki:BAABNQAECn8VAAIIAAYKWg8o5wAzAQAIAAYKWg8o5wAzAQAAAA==.Killmartin:BAABNQAECn8YAAIgAAgKewEwogBKAAAgAAgKewEwogBKAAAAAA==.Kinneas:BAABNQAECn8bAAIDAAkKvxYSUAClAgADAAkKvxYSUAClAgAAAA==.Kizmit:BAAANQAECgEIAwAAAA==.',
Kl='Klënz:BAAANQAECgEIAQAAAA==.',
Ko='Koa:BAAANQAECgQIBwAAAA==.',
Ku='Kurau:BAABNQAECn8UAAIiAAcK6gS8CwAwAQAiAAcK6gS8CwAwAQAAAA==.Kurzal:BAAANQAECgYIEQAAAA==.',
Ky='Kyraz:BAACNQAFFH8bAAMOAAgKcR9sAQBTAgAOAAcKRB5sAQBTAgAKAAYK4CBgAwAuAgA1AAQKfyAAAw4ACgo0JlUBAIIDAA4ACQo0JlUBAIIDAAoACQrgIrcHAFkDAAAA.',
La='Lacie:BAABNQAECn8jAAIIAAYK5AfszgBjAQAIAAYK5AfszgBjAQAAAA==.Laniel:BAAANQAECgEIAQAAAA==.Lavos:BAAANQAECgQIBwABNQAECgoKMwADAFUeAA==.',
Le='Leela:BAAANQAECggICAAAAA==.Lexy:BAAANQAECgEIAQABNQAECgoKNgAUAHcfAA==.',
Lo='Lokiel:BAAANQAECgQICAAAAA==.Lokifurion:BAABNQAECn8vAAMfAAoKtA/yGwDYAQAfAAoKtA/yGwDYAQAeAAQKHgMvkwCLAAAAAA==.',
Lu='Lunitari:BAAANQAECgIIBgAAAA==.',
Ly='Lyaenna:BAABNQAECn8oAAIVAAoKLhrkGwDKAgAVAAoKLhrkGwDKAgAAAA==.',
Ma='Mageshir:BAAANQAECggICQAAAA==.Magrat:BAAANQAECgUIBgAAAA==.Mahu:BAAANQAECgQIBAAAAA==.Malchi:BAAANQAECgUIBQABNQAFFAcIGQAKAPoXAA==.Maletherion:BAABNQAECn8xAAIhAAoKLxfVDgAiAgAhAAoKLxfVDgAiAgAAAA==.Maltherion:BAABNQAECn8iAAMaAAoKHRpWIACXAgAaAAoKHRpWIACXAgAUAAEKAAA9dAAmAAAAAA==.Margareetah:BAAANQAECgQIDAAAAA==.Martinix:BAAANQAECggIBwAAAA==.Mathielshank:BAAANQADCgUIBQAAAA==.',
Me='Meglamonk:BAAANQAECgcIEgAAAA==.',
Mi='Milarca:BAAANQABCgYIDQAAAA==.Minireaper:BAAANQADCgMIAwAAAA==.Misbehavin:BAAANQADCgQIBAAAAA==.',
Mj='Mjolnir:BAABNQAECn8yAAIDAAoK4hz2NQBeAgADAAoK4hz2NQBeAgAAAA==.',
Mo='Mochizuko:BAAANQABCgIIAgAAAA==.Mongke:BAAANQADCggICAAAAA==.Moonre:BAAANQADCgYIEgAAAA==.',
Mu='Mubvan:BAAANQAECgYICgAAAA==.Mushroommans:BAAANQAECgQIBgABNQAFFAMIBgAUAPMhAA==.',
My='Mystaris:BAAANQADCgYICgAAAA==.',
Na='Namôr:BAAANQAECgEIAQAAAA==.Narzel:BAAANQAECgYIDwAAAA==.Nashîr:BAABNQAECn8kAAIFAAoKeBM9WgC4AQAFAAoKeBM9WgC4AQAAAA==.Navybum:BAAANQAECgUIEQAAAA==.',
Ne='Nehemiah:BAABNQAECn84AAMEAAoK/SE7BAC8AgAEAAoK/SE7BAC8AgAFAAEKPxovRQFHAAAAAA==.Nequin:BAABNQAECn8vAAIBAAoKJx6TDAA/AwABAAoKJx6TDAA/AwABNQAECgoKMQANAOMgAA==.Nequins:BAAANQAECgcIEwABNQAECgoKMQANAOMgAA==.Nequinss:BAABNQAECn8xAAINAAoK4yBvGADGAgANAAoK4yBvGADGAgAAAA==.Nevermore:BAAANQAECgEIAQAAAA==.',
Ni='Nicabar:BAABNQAECn81AAIMAAkKAwj9qgB8AQAMAAkKAwj9qgB8AQAAAA==.Nilfheim:BAAANQAECgUIBwAAAA==.Nivla:BAAANQABCgMIAwAAAA==.',
No='Noadie:BAAANQAECgcIBgAAAA==.Noehtyar:BAABNQAECn8VAAIIAAUKQQkK8AAiAQAIAAUKQQkK8AAiAQAAAA==.Noie:BAABNQAECn8ZAAILAAkKxQJRLQCTAAALAAkKxQJRLQCTAAAAAA==.Novadd:BAAANQADCgUIBQAAAA==.Novä:BAAANQAECgQIBAAAAA==.Noztalgia:BAAANQAECgQIBwAAAA==.',
['Në']='Nëklaüs:BAABNQAECn8kAAIHAAYKsRWQSQDsAAAHAAYKsRWQSQDsAAAAAA==.',
Od='Odanarratite:BAAANQAECgEIAQAAAA==.Odanarrayne:BAAANQADCgcIBwAAAA==.Oditte:BAAANQADCggIDgAAAA==.Odysseuss:BAAANQAECgQIBgAAAA==.',
Oi='Oilliphéist:BAAANQAECgUIBQAAAA==.',
On='Onewithyou:BAAANQADCgEIAQAAAA==.Onimaru:BAAANQAECgEIAgAAAA==.',
Or='Ornot:BAABNQAECn83AAINAAoKdRC+WwD8AQANAAoKdRC+WwD8AQAAAA==.',
Os='Oshdruid:BAAANQADCgYICwAAAA==.',
Pa='Paislìe:BAAANQADCggICAAAAA==.Palacola:BAAANQAECgcIBwABNQAFFAgIGAAfAIEZAA==.Pandurbear:BAAANQAECgEIAQAAAA==.Paperplate:BAABNQAECn8iAAIBAAgKARRbVwCFAQABAAgKARRbVwCFAQABNQAECgoKNAARAEwMAA==.Paws:BAAANQADCgMJBgAAAA==.',
Pe='Peposhammy:BAAANQADCgUIBQAAAA==.',
Ph='Phuul:BAAANQADCgMIAwABNQADCgYIEQAGAAAAAA==.Phuulith:BAAANQADCgYIEQAAAA==.',
Pr='Provost:BAABNQAECn8zAAIDAAoKVR6ZNABkAgADAAoKVR6ZNABkAgAAAA==.',
Ps='Psychonoia:BAABNQAECn8eAAIYAAoKbRJmKgDUAQAYAAoKbRJmKgDUAQAAAA==.',
Pu='Pumperdogx:BAAANQADCgYIBgABNQAFFAMICQAHABQmAA==.Pumpkinpîe:BAAANQADCgYIBgAAAA==.',
Qu='Quadritrix:BAAANQADCgQIBAAAAA==.Quanx:BAAANQAECgcICAAAAA==.Quark:BAAANQAECgIIAgAAAA==.',
Ra='Ratacola:BAAANQAECgQIBgABNQAFFAgIGAAfAIEZAA==.',
Re='Remulüs:BAABNQAECn82AAMUAAoKdx/IDwD1AgAUAAoKdx/IDwD1AgAaAAUKlRJRWQAiAQAAAA==.Reoãn:BAAANQABCgQIBgABNQADCgUIBQAGAAAAAA==.',
Ri='Riah:BAAANQAECgEIAQAAAA==.Riilyn:BAABNQAECn8rAAMKAAoKmxiaHQCTAgAKAAkKERmaHQCTAgAOAAYKuQ9xYgAxAQAAAA==.',
['Rø']='Røean:BAAANQADCgUIBQAAAA==.',
Sa='Saintmartin:BAAANQAECggIBgAAAA==.Sanktis:BAAANQADCggIFgAAAA==.',
Sb='Sbcarpenter:BAAANQAECgMIAgAAAA==.',
Sc='Scawmfhealz:BAAANQABCgMIAwAAAA==.Scecretzs:BAAANQADCgYIEQAAAA==.',
Se='Sebone:BAAANQADCggIDQAAAA==.Secretz:BAABNQAECn8aAAQVAAcKSx4WRwDjAQAVAAcKxh0WRwDjAQAjAAMKjw0gGgCaAAAYAAMKlgy8ZwBiAAAAAA==.Sedrelari:BAABNQAECn87AAMIAAkKSCMzIAAXAwAIAAgKwCIzIAAXAwAiAAgKnBwaBwASAgAAAA==.Seizethesol:BAAANQAECgIIBAAAAA==.Sengseng:BAAANQADCgUIBgAAAA==.Sephirøth:BAAANQAECgcICwAAAA==.Sepsis:BAAANQAECgUIDgAAAA==.Serjaime:BAAANQAECgEIAQAAAA==.Sesamo:BAACNQAFFH8IAAIDAAQKOA7+HQCHAAADAAQKOA7+HQCHAAA1AAQKfy0AAgMACgr+GztIALwCAAMACgr+GztIALwCAAAA.',
Sh='Shadedstørmz:BAAANQAECgMIBwAAAA==.Shocks:BAABNQAECn8VAAIJAAUKHxApuwAcAQAJAAUKHxApuwAcAQAAAA==.Shé:BAABNQAECn8hAAICAAkKTRc8HQABAgACAAkKTRc8HQABAgAAAA==.',
Si='Sixoneseven:BAAANQAECgQICAAAAA==.Sixseven:BAABNQAECn8uAAMUAAoKahHGFgDPAQAUAAoKahHGFgDPAQAZAAoKZAu2DQA4AQAAAA==.',
Sk='Skaarlett:BAAANQAECgQIBAAAAA==.Skone:BAABNQAECn8dAAMBAAgKlgmWhQCKAQABAAgKlgmWhQCKAQADAAEKEQPazQEhAAAAAA==.',
Sm='Smarthen:BAAANQABCgQIBAABNQAECgoKLAAbAK0iAA==.Smolhatka:BAAANQAECgQICQABNQAECgYIGAANAI4TAA==.',
Sn='Snickers:BAABNQAECn8bAAIkAAkK0g8MDACZAQAkAAkK0g8MDACZAQAAAA==.',
So='Solarian:BAABNQAECn8pAAIUAAgK7hK5IwBHAQAUAAgK7hK5IwBHAQAAAA==.',
St='Starosa:BAAANQADCgEIAQAAAA==.Startle:BAAANQADCgcIIAAAAA==.Steelbreeze:BAAANQAECgQIDgAAAA==.Storms:BAACNQAFFH8HAAMRAAMKQBVITgCJAAARAAIKShJITgCJAAALAAEKNhg/EQBHAAA1AAQKf0IAAxEACgrmIqBNAOYCABEACgpqHqBNAOYCAAsAAwrdJAcYADkBAAAA.Stoutbringer:BAAANQAECgYIDAAAAA==.Stride:BAAANQABCgMIAwABNQAECgoKIgAPADUXAA==.Strikes:BAABNQAECn8WAAIOAAoKuBavIQBUAgAOAAoKuBavIQBUAgAAAA==.Stronknehen:BAAANQAECgQIBQABNQAECgoKLAAbAK0iAA==.',
Sy='Sylvaedir:BAAANQADCggICQAAAA==.',
['Sö']='Sören:BAABNQAECn8hAAIHAAgKuw/VOwApAQAHAAgKuw/VOwApAQAAAA==.',
Ta='Taomi:BAABNQAECn8mAAINAAoK8ROjKgBMAgANAAoK8ROjKgBMAgAAAA==.',
Te='Teaka:BAAANQAECgQIBwAAAA==.Tenspeed:BAABNQAECn8mAAIUAAkK6xSxGgCgAQAUAAkK6xSxGgCgAQAAAA==.Teof:BAAANQAECgUIBQAAAA==.Terelle:BAAANQAECgUICQABNQAECggIHQABAJYJAA==.Terellesguy:BAAANQADCgQIBAABNQAECgoKMAAJAAsZAA==.Tetsuro:BAAANQADCgUIBwAAAA==.',
Th='Thire:BAAANQADCggICwABNQAECggIHQABAJYJAA==.Throwglaive:BAABNQAECn8XAAIaAAgKsRwGNAAMAgAaAAgKsRwGNAAMAgABNQAFFAgIGwAOAHEfAA==.',
Ti='Tidereign:BAABNQAECn8bAAIeAAkKPQxjNAAzAQAeAAkKPQxjNAAzAQAAAA==.Tinytotems:BAABNQAECn8wAAINAAkKSBpeOwD4AQANAAkKSBpeOwD4AQAAAA==.Tiriell:BAABNQAECn8jAAIDAAkKUBUFewA1AgADAAkKUBUFewA1AgAAAA==.',
To='Toe:BAACNQAFFH8FAAIRAAMKCAn7OgDYAAARAAMKCAn7OgDYAAA1AAQKfxkAAhEACgrKIe8mAEUDABEACgrKIe8mAEUDAAAA.Touchmee:BAAANQADCgcIAQAAAA==.',
Tr='Trausti:BAAANQAECgUJCQAAAA==.Treehen:BAABNQAECn8sAAIbAAoKrSLYBAD3AgAbAAoKrSLYBAD3AgAAAA==.Trinanah:BAACNQAFFH8LAAIYAAQKBAQlCwC0AAAYAAQKBAQlCwC0AAA1AAQKfzAAAhgACgoCFLInAO0BABgACgoCFLInAO0BAAAA.Troltsky:BAAANQADCgQIBAAAAA==.',
['Tô']='Tôrunn:BAAANQAECgYIDAABNQAECgoKHgAYAG0SAA==.',
Va='Valariann:BAAANQADCggICAABNQAECgoKOgAOAGQbAA==.Valeriux:BAAANQADCgUJAwAAAA==.Valgal:BAABNQAECn8aAAIIAAYKkAgYxADlAAAIAAYKkAgYxADlAAAAAA==.Valiraste:BAABNQAECn85AAIMAAoKuhf+LAAuAgAMAAoKuhf+LAAuAgABNQAECgkJHQAVAFgTAA==.Valor:BAAANQAECgEIAQABNQAECgoKMwADAFUeAA==.Vantois:BAAANQADCgMIAwAAAA==.Vapor:BAAANQADCgQIBAAAAA==.Varalina:BAAANQAECgQIBgAAAA==.',
Vi='Viital:BAAANQADCgYIBgAAAA==.Vischar:BAAANQADCgUIBwAAAA==.',
Vo='Voidmommy:BAAANQABCgEIAQAAAA==.',
Wa='Washbeans:BAACNQAFFH8NAAMgAAQKKB1OCwDeAAAgAAMKfxtOCwDeAAAXAAMKqBvCCACrAAA1AAQKfycAAyAACQpyHkchAIMCACAACQpyHkchAIMCABcAAgoWGsGwAJEAAAAA.Wayne:BAAANQABCgQIAgAAAA==.',
We='Wef:BAABNQAECn8rAAIIAAkKLA1begB+AQAIAAkKLA1begB+AQAAAA==.Weledronys:BAAANQADCgYICwAAAA==.',
Wh='Whyse:BAABNQAECn80AAIRAAoKTAxFZwC3AQARAAoKTAxFZwC3AQAAAA==.',
Wi='Wings:BAABNQAECn8iAAMPAAoKNRfEDACWAgAPAAoKNRfEDACWAgAkAAEKmw2HGQA1AAAAAA==.Wintel:BAAANQAECgEIAQAAAA==.Wizaes:BAAANQAECgEIAQAAAA==.',
Wo='Woolybullie:BAAANQADCgcIBwABNQAECggIDAAGAAAAAA==.',
Xa='Xanza:BAAANQADCggIEQAAAA==.',
Ya='Yamzaio:BAAANQADCgUJBwAAAA==.',
Yo='Yo:BAAANQADCgcIDAAAAA==.',
Za='Zancrafter:BAAANQADCgIIAgABNQAFFAQIDQAUAAsXAA==.Zanduwuin:BAACNQAFFH8NAAIUAAQKCxesBwDSAAAUAAQKCxesBwDSAAA1AAQKfzAAAxQACgqnG/MQAOgCABQACgqnG/MQAOgCABkAAwqfCxwoAHUAAAAA.Zanvoker:BAABNQAECn8nAAQkAAkKNRfsBwAjAgAkAAkK1RbsBwAjAgAPAAYKThFzHwBeAQAQAAcKJQnZKgBWAQABNQAFFAQIDQAUAAsXAA==.Zargar:BAABNQAECn8lAAICAAkK1xgSEQDbAQACAAkK1xgSEQDbAQAAAA==.',
Zl='Zlatah:BAAANQADCgUIBQAAAA==.',
Zo='Zorttok:BAAANQAECgEIAQAAAA==.',
Zu='Zukkario:BAACNQAFFH8UAAMFAAYKXSN1BwBIAgAFAAYKBCN1BwBIAgAlAAQKxR8BAQB6AQA1AAQKfy0AAwUACgoIJsUXAFoDAAUACgrmJcUXAFoDACUAAgq0GgInAHUAAAE1AAUUCAgbAA4AcR8A.',
Zy='Zyp:BAAANQAECgUICwAAAA==.',
['Âx']='Âxel:BAABNQAECn8xAAINAAoKtyPjCgBTAwANAAoKtyPjCgBTAwAAAA==.',
['År']='Årgon:BAABNQAECn8yAAIXAAoKkhocJACxAgAXAAoKkhocJACxAgAAAA==.',
['ße']='ßen:BAAANQAECgEIAQAAAA==.',
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
