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

local lookup = {'Paladin-Holy','Paladin-Protection','Paladin-Retribution','Warrior-Protection','Warrior-Arms','Shaman-Enhancement','DeathKnight-Blood','Hunter-BeastMastery','DeathKnight-Unholy','Shaman-Elemental','Rogue-Assassination','Mage-Frost','Warlock-Demonology','Shaman-Restoration','Rogue-Subtlety','Evoker-Devastation','Evoker-Preservation','Mage-Arcane','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','Priest-Holy','Monk-Mistweaver','Druid-Guardian','Priest-Shadow','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Windwalker','Druid-Feral','Druid-Balance','Druid-Restoration','DeathKnight-Frost','Hunter-Marksmanship','Unknown-Unknown','Hunter-Survival','Priest-Discipline','Evoker-Augmentation','Warrior-Fury',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abaddôn:BAAANQADCgYIBgAAAA==.',
Ad='Adirolf:BAAANQAECgYIDwAAAA==.',
Ae='Aedonis:BAAANQAECgUIBwAAAA==.Aenlori:BAAANQADCgYIBgABNQAFFAcIDgABADIQAA==.Aenlorie:BAACNQAFFH8OAAMBAAcKMhD1DgB1AQABAAYKswz1DgB1AQACAAEKfAMrEgA7AAA1AAQKf0cABAEACgo4GyQVABADAAEACgo4GyQVABADAAMABQr9Fi3uAEABAAIABAryE7pJAMUAAAAA.',
Ag='Ag:BAAANQADCgMIAgAAAA==.Agesilaus:BAAANQADCgEIAQAAAA==.Aggathon:BAEBNQAECn83AAMEAAoKvREkEAC1AQAEAAoKvREkEAC1AQAFAAQKvQTs5wCkAAAAAA==.',
Ak='Akebono:BAAANQADCgUIBQAAAA==.Akusai:BAAANQADCgYIEgABNQAECgQIGAAGAL4DAA==.',
Al='Aldebaran:BAAANQAECgQIBwAAAA==.Alhae:BAAANQABCgcIDgAAAA==.Alphatanker:BAACNQAFFH8JAAIHAAMKFCYOEQBGAQAHAAMKFCYOEQBGAQA1AAQKfzcAAgcACgrKJnsAAPkDAAcACgrKJnsAAPkDAAAA.',
Am='Amakadavra:BAAANQABCgEIAQAAAA==.',
Ar='Argentino:BAAANQAECgIIBQAAAA==.',
As='Ashke:BAABNQAECn8/AAIIAAoKUhg3QQBSAgAIAAoKUhg3QQBSAgAAAA==.',
Au='Aurica:BAAANQAECgYIBwAAAA==.',
Ax='Axes:BAABNQAECn8YAAIJAAUKbxH1eQAzAQAJAAUKbxH1eQAzAQAAAA==.',
Ba='Badlucklouie:BAABNQAECn87AAIKAAoK6hoYMgAPAgAKAAoK6hoYMgAPAgAAAA==.Badpenny:BAAANQAECgEIAQAAAA==.Bajenkas:BAAANQADCgYIBgAAAA==.Balfas:BAAANQAECgUIDQAAAA==.',
Be='Beaupeep:BAABNQAECn8YAAIGAAQKvgPfLQCDAAAGAAQKvgPfLQCDAAAAAA==.Beesty:BAAANQAECgMIBQAAAA==.',
Bi='Bighorner:BAAANQADCgQIBAAAAA==.Bigkahunas:BAAANQAECgEIAQAAAA==.Bigwarlock:BAAANQAECgMIBQAAAA==.Bindicrippa:BAAANQADCgcIFAAAAA==.',
Bl='Blackwater:BAABNQAECn8nAAILAAgKABx7NAAJAgALAAgKABx7NAAJAgAAAA==.Blissey:BAAANQABCgYICgABNQAECgoKRgAMAN0iAA==.Bloodstyx:BAAANQAECgQIBwABNQAECgoKLQAHAF0hAA==.',
Bo='Bobi:BAAANQAECgYIDAAAAA==.Boyacky:BAAANQAECgQIBAAAAA==.',
Br='Braiglock:BAABNQAECn8jAAINAAcKFwhirgD3AAANAAcKFwhirgD3AAAAAA==.Bratty:BAAANQADCggIDgAAAA==.',
Bu='Bucko:BAABNQAECn8wAAIIAAoKgRe+TAA1AgAIAAoKgRe+TAA1AgAAAA==.',
By='Bygz:BAABNQAECn8aAAMKAAcKwSJbTQBBAgAKAAcKwSJbTQBBAgAOAAQK2B6wdgBPAQABNQAFFAkJHAAPANUcAA==.',
['Bé']='Béésty:BAAANQAECgMICQAAAA==.',
Ca='Caarjack:BAACNQAFFH8MAAMQAAYKywyoAwDEAAAQAAQKcg+oAwDEAAARAAMKIwp7FAB9AAA1AAQKfzgAAxEACgr8GWAQAKMCABEACQoyGWAQAKMCABAABwpcGaYPAEYBAAAA.Caarlite:BAAANQADCgQIBAAAAA==.Callmefury:BAABNQAECn8bAAIFAAoKKRh0PQBMAgAFAAoKKRh0PQBMAgAAAA==.Callmeheal:BAAANQAECgUIEQAAAA==.Callmemommy:BAAANQAECgEIAQAAAA==.Casserole:BAABNQAECn8dAAISAAkKMxSK1wDYAQASAAkKMxSK1wDYAQAAAA==.Catadelic:BAABNQAECn87AAIIAAoK1QwfbADqAQAIAAoK1QwfbADqAQAAAA==.',
Ce='Celestial:BAABNQAECn80AAMTAAoKNxToBAC3AQATAAoKNxToBAC3AQAUAAIKzgPAIwBhAAAAAA==.',
Ch='Chewwbacca:BAABNQAECn8aAAQTAAgKyB2NBADhAgATAAgKyB2NBADhAgAUAAEKXhRGKQBHAAANAAEKNAl2RgEwAAAAAA==.Chewwy:BAAANQADCgUIBQABNQAECggIGgATAMgdAA==.Chewwyy:BAAANQADCggICgABNQAECggIGgATAMgdAA==.Chuwy:BAAANQADCgMIAwABNQAECggIGgATAMgdAA==.Chyse:BAAANQABCggIFAAAAA==.',
Cl='Clap:BAAANQADCgYIBgAAAA==.Cleombrotus:BAAANQADCgQIBAAAAA==.',
Cu='Cuzigothigh:BAAANQABCgIIAwAAAA==.',
Da='Darkdemon:BAACNQAFFH8OAAIVAAcKiRC7AwBmAQAVAAcKiRC7AwBmAQA1AAQKf2YAAhUACgoBJa0CALEDABUACgoBJa0CALEDAAAA.Darkladyann:BAABNQAECn8iAAIWAAkKWBM4cgCFAQAWAAkKWBM4cgCFAQAAAA==.Darkxnemesis:BAABNQAECn8UAAIKAAgKxBRuXQBvAQAKAAgKxBRuXQBvAQAAAA==.',
De='Deadlee:BAABNQAECn9HAAIXAAoKEh5uBgAjAwAXAAoKEh5uBgAjAwAAAA==.Deadnehen:BAAANQAECgEIAQABNQAECgoKLAAYAK0iAA==.Deathphish:BAABNQAECn86AAMHAAoKsxdCHgAJAgAHAAoKUBdCHgAJAgAJAAoKCxBHLQB/AQAAAA==.Dentfry:BAABNQAECn8XAAIWAAkKtROYZwDoAQAWAAkKtROYZwDoAQAAAA==.Derfla:BAAANQAECgcIEgAAAA==.Deshler:BAABNQAECn8bAAMEAAYK5BMiIgA6AQAEAAYK5BMiIgA6AQAFAAEKbQRkXQEpAAAAAA==.Dethblazé:BAABNQAECn8YAAIOAAUKgxiGdABVAQAOAAUKgxiGdABVAQAAAA==.Dethbringér:BAAANQAECgQICAAAAA==.Dethdian:BAAANQAECgMIAwAAAA==.Detthshot:BAAANQAECgQIDAAAAA==.Dezign:BAABNQAECn8hAAMWAAoKLCL5EQA5AwAWAAoKLCL5EQA5AwAZAAYK2BGwLAAhAQABNQAFFAgIIAAMAAMdAA==.',
Di='Dildro:BAABNQAECn8VAAMEAAUKRQ4rMwB1AAAFAAUK2ApD8wD5AAAEAAUKRAsrMwB1AAAAAA==.Dimhammer:BAAANQAECgUIBAAAAA==.Dirtyblonde:BAAANQAECgMIAwAAAA==.Ditlutz:BAABNQAECn9AAAICAAoKsCXbAQBjAwACAAoKsCXbAQBjAwAAAA==.',
Do='Dom:BAACNQAFFH8UAAIFAAcKjRWgDACFAQAFAAcKjRWgDACFAQA1AAQKfzMAAgUACgqNIeQlAKkCAAUACgqNIeQlAKkCAAAA.Doronjo:BAAANQADCggIDAAAAA==.Dorz:BAAANQAECgMIAwAAAA==.Dotrammy:BAAANQADCgcICQAAAA==.',
Du='Dupeslicate:BAABNQAECn8YAAISAAoKyw5a3ADPAQASAAoKyw5a3ADPAQAAAA==.',
Dw='Dwanco:BAAANQADCgEIAQAAAA==.Dwarfussy:BAAANQADCgMIAwAAAA==.',
Dy='Dybby:BAABNQAECn8eAAISAAkKIBhxbADZAQASAAkKIBhxbADZAQAAAA==.Dylexek:BAAANQADCgEIAQAAAA==.Dynamite:BAAANQADCgQIBAAAAA==.',
['Dé']='Détth:BAAANQAECgQIEQAAAA==.',
El='Elderoth:BAABNQAECn8dAAISAAoKGRkVYwC4AgASAAoKGRkVYwC4AgAAAA==.Elfsky:BAAANQADCgUJBQAAAA==.',
En='Endlessnight:BAABNQAECn8tAAIHAAoKXSHMHQDDAgAHAAoKXSHMHQDDAgAAAA==.Envion:BAAANQADCgMIAwAAAA==.',
Er='Erica:BAAANQAECgQIBAAAAA==.',
['Eä']='Eärendil:BAABNQAECn8dAAIWAAkKCQO5kQAkAQAWAAkKCQO5kQAkAQAAAA==.',
Fa='Faebryn:BAAANQADCggIFAAAAA==.Faevor:BAABNQAECn81AAMKAAoKbRG/QQDNAQAKAAoKbRG/QQDNAQAOAAMKKRy1zADOAAAAAA==.',
Fe='Femfatal:BAAANQAECgQIBAABNQAECgoKLQAHAF0hAA==.Fenirean:BAAANQAECgUIBwAAAA==.',
Fl='Flirts:BAAANQADCgYICgAAAA==.',
Fo='Forcas:BAABNQAECn9KAAMaAAoKGCHpBACDAgAaAAkKZiHpBACDAgAbAAoKbxPAIgD1AQAAAA==.',
Fu='Fundus:BAABNQAECn8aAAIHAAoKXRSgHQAPAgAHAAoKXRSgHQAPAgAAAA==.',
Ga='Gamarrick:BAABNQAECn8XAAIZAAoK6QYqNgDjAAAZAAoK6QYqNgDjAAAAAA==.',
Ge='Germain:BAAANQADCgIIAgAAAA==.',
Gn='Gnometzu:BAAANQADCggIDgAAAA==.',
Go='Golddicmove:BAAANQAECgQIEQAAAA==.',
Gr='Gremmel:BAAANQAECggICQAAAA==.Griever:BAACNQAFFH8GAAMTAAMKvQ8hBwCMAAATAAIKxQ4hBwCMAAANAAEKrhEpNwBLAAA1AAQKf1UABBQACgpBIEMPAEIBAA0ABwrCHTSBAOMBABQABAqGG0MPAEIBABMAAwoFIpArACIBAAAA.',
Gu='Guillak:BAABNQAECn8pAAMNAAkKKRBEawCWAQANAAkKKRBEawCWAQATAAIK6Qn+ZABaAAAAAA==.',
Ha='Hadroldel:BAABNQAECn8xAAIIAAoK4xmrMACCAgAIAAoK4xmrMACCAgAAAA==.Hammond:BAAANQADCgMICAAAAA==.Hanraktah:BAAANQADCgUIBQAAAA==.Harlem:BAAANQABCgQIBAAAAA==.Harxx:BAAANQADCgUICgAAAA==.Hatka:BAABNQAECn8iAAMOAAcKfhiOTADgAQAOAAcKfhiOTADgAQAKAAMKkwQw3gBZAAABNQAECgoKGAAXAO4OAA==.Hattori:BAAANQABCgUIBQAAAA==.',
Hi='Higurashi:BAAANQABCgQIBwAAAA==.',
Ho='Holymanson:BAAANQAECgMJAwAAAA==.Hoofington:BAABNQAECn8xAAIYAAgKQR8cFQDtAQAYAAgKQR8cFQDtAQAAAA==.Howlingdoom:BAAANQADCgYIBgAAAA==.',
Hy='Hylexerr:BAAANQAECgMIAwAAAA==.',
Ib='Ibull:BAAANQADCggICQAAAA==.',
If='Iffy:BAABNQAECn8rAAIIAAoKbhwFSQCRAgAIAAoKbhwFSQCRAgAAAA==.',
Il='Ilian:BAABNQAECn8bAAIcAAkK3xhoHABWAgAcAAkK3xhoHABWAgAAAA==.',
In='Iniquity:BAAANQADCggIFAAAAA==.',
It='It:BAAANQAECgUIBQAAAA==.',
Ja='Jabiso:BAABNQAECn8oAAIKAAoKehJ3UgAvAgAKAAoKehJ3UgAvAgAAAA==.Jackthebeast:BAAANQAECgEIAQABNQAECgoKLAAKAPEfAA==.Jackthefel:BAAANQAECgUIBQABNQAECgoKLAAKAPEfAA==.Jackthetotem:BAABNQAECn8sAAIKAAoK8R/UHgASAwAKAAoK8R/UHgASAwAAAA==.Jain:BAAANQAECgYIBwAAAA==.Javaxpress:BAAANQAECgUICQAAAA==.',
Jd='Jdmagisdh:BAAANQAECgIIAgABNQAECgoKPQAdAPYlAA==.Jdmagisdk:BAAANQAECgMIAwABNQAECgoKPQAdAPYlAA==.Jdmagisdruid:BAABNQAECn89AAMdAAoK9iWrAACDAwAdAAoK9iWrAACDAwAeAAIKbx3IjgCbAAAAAA==.Jdmagisevokr:BAAANQAECgMIBAABNQAECgoKPQAdAPYlAA==.Jdmagishuntr:BAAANQAECgMIBAABNQAECgoKPQAdAPYlAA==.Jdmagislock:BAAANQAECgIIAgABNQAECgoKPQAdAPYlAA==.Jdmagismage:BAAANQAECgQIBAABNQAECgoKPQAdAPYlAA==.Jdmagismonk:BAAANQAECgQIAwABNQAECgoKPQAdAPYlAA==.Jdmagispally:BAAANQAECgQIAwABNQAECgoKPQAdAPYlAA==.Jdmagisprst:BAAANQAECgQIAwABNQAECgoKPQAdAPYlAA==.Jdmagisrogue:BAAANQAECgMIBAABNQAECgoKPQAdAPYlAA==.Jdmagissham:BAAANQAECgUIBAABNQAECgoKPQAdAPYlAA==.Jdmagiswarr:BAAANQAECgMIAwABNQAECgoKPQAdAPYlAA==.',
Je='Jeanne:BAABNQAECn86AAMZAAoKjgYHJgBUAQAZAAoKjgYHJgBUAQAWAAgKPgHF1gCkAAAAAA==.Jedoniah:BAAANQAECggIEAAAAA==.Jezabel:BAAANQADCgIIAgAAAA==.',
Ji='Jizzdiddy:BAAANQAECgUIBAAAAA==.',
Jo='Jolnir:BAAANQAECgQIBAABNQAECgoKQAADAI0gAA==.Jorcingmyshi:BAAANQAECggIEwAAAA==.Jorhmont:BAAANQADCgUIBQAAAA==.',
Ju='Juan:BAABNQAECn88AAMfAAkKKReVHQAWAgAfAAkKKReVHQAWAgAeAAIK+QOtkAArAAAAAA==.Jumpeor:BAACNQAFFH8RAAMDAAgKyxfWBAAUAgADAAcKEBjWBAAUAgACAAEKcBZ/DwBOAAA1AAQKfz4AAgMACgqFJWEEANcDAAMACgqFJWEEANcDAAAA.',
Ka='Kanig:BAAANQADCggJEgAAAA==.Kassey:BAAANQAECgEIAQAAAA==.Katacola:BAACNQAFFH8YAAIfAAcKgRlKAwAYAgAfAAcKgRlKAwAYAgA1AAQKfzcAAx8ACgq1JM0FAGYDAB8ACgq1JM0FAGYDAB4ABwp5Fn8yAHcBAAAA.',
Ke='Keg:BAAANQAECgQIBQAAAA==.Kendrys:BAABNQAECn8VAAQHAAkKLxAyZABhAQAHAAkK4Q8yZABhAQAgAAUK2wnHbQDnAAAJAAIKuwRf0QBLAAAAAA==.Kethria:BAAANQAECggIDgABNQAECgkJOwAIAEgjAA==.Kevenal:BAABNQAECn8uAAIhAAoKLh9aEADlAgAhAAoKLh9aEADlAgAAAA==.Keyainor:BAAANQADCggIDgABNQAECgcIDQAiAAAAAA==.',
Ki='Kikiliki:BAABNQAECn8VAAIIAAYKWg8o5wAzAQAIAAYKWg8o5wAzAQAAAA==.Killmartin:BAABNQAECn8YAAIgAAgKewEwogBKAAAgAAgKewEwogBKAAAAAA==.Kinneas:BAABNQAECn8bAAIDAAkKvxYSUAClAgADAAkKvxYSUAClAgAAAA==.Kizmit:BAAANQAECgUIBQAAAA==.',
Kl='Klënz:BAAANQAECgEIAQAAAA==.',
Ko='Koa:BAAANQAECgQIBwAAAA==.',
Ku='Kurau:BAABNQAECn8UAAIjAAcK6gS8CwAwAQAjAAcK6gS8CwAwAQAAAA==.Kurzal:BAABNQAECn8YAAIOAAoK9AtiZgCDAQAOAAoK9AtiZgCDAQAAAA==.',
Ky='Kyraz:BAACNQAFFH8cAAMPAAkK1RznAgBTAgAPAAcKRB7nAgBTAgALAAcK8BxgAwAuAgA1AAQKfyAAAw8ACgo0JpQBAIYDAA8ACQo0JpQBAIYDAAsACQrgIrcHAFkDAAAA.',
La='Lacie:BAABNQAECn8jAAIIAAYK5AfszgBjAQAIAAYK5AfszgBjAQAAAA==.Lavos:BAAANQAECggIDAABNQAECgoKOAADAM4eAA==.',
Le='Leela:BAAANQAECggICAAAAA==.Lexy:BAAANQAECgEIAQABNQAECgoKPgAVAOIfAA==.',
Li='Lily:BAAANQAECgQIBAAAAA==.',
Lo='Lokiel:BAAANQAECgQICAAAAA==.Lokifurion:BAABNQAECn83AAMfAAoKtA/DIwDZAQAfAAoKtA/DIwDZAQAeAAQKHgMvkwCLAAAAAA==.',
Lu='Lunitari:BAAANQAECgIIBgAAAA==.',
Ly='Lyaenna:BAABNQAECn8oAAIWAAoKLhr6JwCvAgAWAAoKLhr6JwCvAgAAAA==.',
Ma='Mageshir:BAAANQAECggIBwAAAA==.Magrat:BAAANQAECgUIBQAAAA==.Mahu:BAAANQAECgQICAAAAA==.Malchi:BAAANQAECgUIBQABNQAFFAgIGgALADgdAA==.Maletherion:BAABNQAECn89AAIhAAoKJRnkDQBeAgAhAAoKJRnkDQBeAgAAAA==.Maltherion:BAABNQAECn8iAAMbAAoKHRpWIACXAgAbAAoKHRpWIACXAgAVAAEKAAA9dAAmAAAAAA==.Margareetah:BAAANQAECgQIEwAAAA==.Martinix:BAAANQAECggIDwAAAA==.Mathielshank:BAAANQADCgUIBQAAAA==.',
Me='Meglamonk:BAABNQAECn8dAAIcAAgKSQleLgAnAQAcAAgKSQleLgAnAQAAAA==.',
Mi='Milarca:BAAANQABCgYIDQAAAA==.Minireaper:BAAANQADCgMIAwAAAA==.Misbehavin:BAAANQADCgQIBAAAAA==.',
Mj='Mjolnir:BAABNQAECn9AAAIDAAoKjSC8GQD7AgADAAoKjSC8GQD7AgAAAA==.',
Mo='Mochizuko:BAAANQABCgIIAgAAAA==.Mongke:BAAANQADCggICAAAAA==.Mononokè:BAAANQABCgIIAgAAAA==.Moonre:BAAANQADCgYIEgAAAA==.',
Mu='Mubvan:BAAANQAECgYIDwAAAA==.Mushroommans:BAAANQAECgQIBgABNQAFFAMIBgAVAPMhAA==.',
My='Mystaris:BAAANQADCgYICgAAAA==.',
Na='Namôr:BAAANQAECgEIAQAAAA==.Narzel:BAAANQAECgYIDgAAAA==.Nashîr:BAABNQAECn8sAAIFAAoKNRXPYgDXAQAFAAoKNRXPYgDXAQAAAA==.Navybum:BAABNQAECn8gAAIQAAUKoga/HAB+AAAQAAUKoga/HAB+AAAAAA==.',
Ne='Nehemiah:BAABNQAECn9GAAMEAAoKHiOrAgAkAwAEAAoKHiOrAgAkAwAFAAEKPxovRQFHAAAAAA==.Nequin:BAABNQAECn8zAAIBAAoK5B7jDwBAAwABAAoK5B7jDwBAAwABNQAECgoKOAAOAOMgAA==.Nequins:BAAANQAECgcIEAABNQAECgoKOAAOAOMgAA==.Nequinss:BAABNQAECn84AAIOAAoK4yB7JgDLAgAOAAoK4yB7JgDLAgAAAA==.Nevermore:BAAANQAECgEIAQAAAA==.',
Ni='Nicabar:BAABNQAECn9CAAINAAoKZgmdkAA5AQANAAoKZgmdkAA5AQAAAA==.Nilfheim:BAAANQAECgUIBwAAAA==.Nivla:BAAANQABCgMIAwAAAA==.',
No='Noadie:BAAANQAECgcIBgAAAA==.Noehtyar:BAABNQAECn8gAAIIAAcK8gmuxQAmAQAIAAcK8gmuxQAmAQAAAA==.Noie:BAABNQAECn8eAAIMAAoKFgTVIADQAAAMAAoKFgTVIADQAAAAAA==.Novadd:BAAANQADCgUIBQAAAA==.Novä:BAAANQAECgQIBAAAAA==.Noztalgia:BAAANQAECgQIBwAAAA==.',
['Në']='Nëklaüs:BAABNQAECn8kAAIHAAYKsRWqZgBYAQAHAAYKsRWqZgBYAQAAAA==.',
Od='Odanarratite:BAAANQAECgEIAQAAAA==.Odanarrayne:BAAANQADCgcIBwAAAA==.Oditte:BAAANQADCggIDgAAAA==.Odysseuss:BAAANQAECgQICgAAAA==.',
Oi='Oilliphéist:BAAANQAECgQIBQAAAA==.',
On='Onewithyou:BAAANQADCgEIAQAAAA==.Onimaru:BAAANQABCgEIAQAAAA==.',
Or='Ornot:BAACNQAFFH8FAAIOAAIKyAfPJgBvAAAOAAIKyAfPJgBvAAA1AAQKfzwAAg4ACgp1EL5bAPwBAA4ACgp1EL5bAPwBAAAA.',
Os='Oshdruid:BAAANQADCgYICwAAAA==.',
Pa='Paislìe:BAAANQADCggICAAAAA==.Palacola:BAAANQAECgcIBwABNQAFFAgIGAAfAIEZAA==.Pandurbear:BAAANQAECgEIAQAAAA==.Paperplate:BAABNQAECn8xAAIBAAoKKhZ8LgBpAgABAAoKKhZ8LgBpAgABNQAECgoKSgASABgOAA==.Paws:BAAANQADCgMJBgAAAA==.',
Pe='Peposhammy:BAAANQADCgUIBQAAAA==.',
Ph='Phuul:BAAANQADCgMIAwABNQAECgYIBgAiAAAAAA==.Phuulith:BAAANQADCgYIEQABNQAECgYIBgAiAAAAAA==.',
Pr='Provost:BAABNQAECn84AAIDAAoKzh6GPAB1AgADAAoKzh6GPAB1AgAAAA==.',
Ps='Psychonoia:BAABNQAECn8eAAIZAAoKbRJmKgDUAQAZAAoKbRJmKgDUAQAAAA==.',
Pu='Pumperdogx:BAAANQADCgYIBgABNQAFFAMICQAHABQmAA==.Pumpkinpîe:BAAANQADCgYIBgAAAA==.',
Qu='Quadritrix:BAAANQADCgQIBAAAAA==.Quanx:BAAANQAECgcICAAAAA==.Quark:BAAANQAECgIIAgAAAA==.',
Ra='Ratacola:BAAANQAECgQIBgABNQAFFAgIGAAfAIEZAA==.',
Re='Remulüs:BAABNQAECn8+AAMVAAoK4h/IDwD1AgAVAAoK4h/IDwD1AgAbAAUKlRJRWQAiAQAAAA==.Reoãn:BAAANQABCgQIBgABNQADCgUIBQAiAAAAAA==.',
Ri='Riah:BAAANQAECgIIAQAAAA==.Riilyn:BAABNQAECn87AAMLAAoK8xiaHQCTAgALAAkKERmaHQCTAgAPAAoKzRLiNgAgAgAAAA==.',
['Rø']='Røean:BAAANQADCgUIBQAAAA==.',
Sa='Saintmartin:BAAANQAECggIBgAAAA==.Sanktis:BAAANQADCggIFgAAAA==.',
Sb='Sbcarpenter:BAAANQAECgMIAgAAAA==.',
Sc='Scawmfhealz:BAAANQABCgMIAwAAAA==.Scecretzs:BAAANQADCgYIEQAAAA==.',
Se='Sebone:BAAANQADCggIDQAAAA==.Secretz:BAABNQAECn8fAAQWAAkK3hwuNwBhAgAWAAkKdxwuNwBhAgAkAAMKjw0gGgCaAAAZAAQKgQo2RwCOAAAAAA==.Sedrelari:BAABNQAECn87AAMIAAkKSCMzIAAXAwAIAAgKwCIzIAAXAwAjAAgKnBwaBwASAgAAAA==.Seizethesol:BAAANQAECgYIDAAAAA==.Sengseng:BAAANQADCgUIBgAAAA==.Sephirøth:BAAANQAECgcICgAAAA==.Sepsis:BAAANQAECgUIDQAAAA==.Serjaime:BAAANQABCgQICAAAAA==.Sesamo:BAACNQAFFH8IAAIDAAQKOA7AJQCFAAADAAQKOA7AJQCFAAA1AAQKfy8AAgMACgqQHDtIALwCAAMACgqQHDtIALwCAAAA.',
Sh='Shadedstørmz:BAAANQAECgMIBwAAAA==.Shocks:BAABNQAECn8eAAIKAAUKHxApuwAcAQAKAAUKHxApuwAcAQAAAA==.Shoppers:BAAANQAECgQIBAABNQAFFAcIEQAJAD0iAA==.Shé:BAABNQAECn8lAAICAAkK9xg8HQABAgACAAkK9xg8HQABAgAAAA==.',
Si='Sixoneseven:BAAANQAECgMIBQAAAA==.Sixseven:BAABNQAECn8wAAMVAAoKahGpHADCAQAVAAoKahGpHADCAQAaAAoKZAuvEQAuAQAAAA==.',
Sk='Skaarlett:BAAANQAECgQIBAAAAA==.Skone:BAABNQAECn8dAAMBAAgKlgmWhQCKAQABAAgKlgmWhQCKAQADAAEKEQPazQEhAAAAAA==.',
Sm='Smarthen:BAAANQABCgQIBAABNQAECgoKLAAYAK0iAA==.Smolhatka:BAABNQAECn8YAAIXAAoK7g4vEgDmAQAXAAoK7g4vEgDmAQAAAA==.',
Sn='Snickers:BAABNQAECn8bAAIlAAkK0g8MDACZAQAlAAkK0g8MDACZAQAAAA==.',
So='Solarian:BAABNQAECn8vAAIVAAgK7hJsMAC/AQAVAAgK7hJsMAC/AQAAAA==.',
St='Starosa:BAAANQADCgEIAQAAAA==.Startle:BAAANQADCggIIQAAAA==.Steelbreeze:BAABNQAECn8TAAIIAAQK3g20+QC+AAAIAAQK3g20+QC+AAAAAA==.Storms:BAACNQAFFH8IAAMMAAMK/xeuDwBUAAASAAIKShJITgCJAAAMAAEKsx2uDwBUAAA1AAQKf0QAAxIACgrmIqBNAOYCABIACgpqHqBNAOYCAAwAAwrdJAcYADkBAAAA.Stoutbringer:BAAANQAECgYICQAAAA==.Stride:BAAANQABCgMIAwABNQAECgoKIgAQADUXAA==.Strikes:BAABNQAECn8gAAIPAAoKZhx0GAC7AgAPAAoKZhx0GAC7AgAAAA==.Stronknehen:BAAANQAECgQIBAABNQAECgoKLAAYAK0iAA==.',
Sy='Sylvaedir:BAAANQADCggICQAAAA==.',
['Sö']='Sören:BAABNQAECn8lAAIHAAgKuw+ARwAfAQAHAAgKuw+ARwAfAQAAAA==.',
Ta='Taomi:BAABNQAECn80AAIOAAoKYRQwNQBGAgAOAAoKYRQwNQBGAgAAAA==.',
Te='Teaka:BAAANQAECgQIBwAAAA==.Tenspeed:BAABNQAECn8mAAIVAAkK6xQaIQCWAQAVAAkK6xQaIQCWAQAAAA==.Teof:BAAANQAECgUIBQAAAA==.Terelle:BAAANQAECgcIDwABNQAECggIHQABAJYJAA==.Terellesguy:BAAANQADCgQIBAABNQAECgoKOwAKAOoaAA==.Tetsuro:BAAANQADCgUIBwAAAA==.',
Th='Thire:BAAANQADCggICwABNQAECggIHQABAJYJAA==.Throwglaive:BAABNQAECn8XAAIbAAgKsRwGNAAMAgAbAAgKsRwGNAAMAgABNQAFFAkJHAAPANUcAA==.',
Ti='Tidereign:BAABNQAECn8lAAIeAAoKNQ6iKwCkAQAeAAoKNQ6iKwCkAQAAAA==.Tinytotems:BAABNQAECn8zAAIOAAoKKhonNgBBAgAOAAoKKhonNgBBAgAAAA==.Tiriell:BAABNQAECn8jAAIDAAkKUBUFewA1AgADAAkKUBUFewA1AgAAAA==.',
To='Toe:BAACNQAFFH8FAAISAAMKCAn7OgDYAAASAAMKCAn7OgDYAAA1AAQKfxkAAhIACgrKIe8mAEUDABIACgrKIe8mAEUDAAAA.Touchmee:BAAANQADCgcIAQAAAA==.',
Tr='Trausti:BAAANQAECgUJCQAAAA==.Treehen:BAABNQAECn8sAAIYAAoKrSLIBABXAwAYAAoKrSLIBABXAwAAAA==.Trinanah:BAACNQAFFH8UAAMZAAYKegZjCAANAQAZAAYKegZjCAANAQAWAAEKdgCuOwA3AAA1AAQKfzUAAhkACgoOFbInAO0BABkACgoOFbInAO0BAAAA.Troltsky:BAAANQADCgQIBAAAAA==.',
['Tô']='Tôrunn:BAAANQAECgYICwABNQAECgoKHgAZAG0SAA==.',
Ut='Uthandric:BAAANQAECgQIBAABNQAECgoKQAACALAlAA==.',
Va='Valariann:BAAANQADCggICAABNQAECgoKQgAPAGgcAA==.Valeriux:BAAANQADCgUJAwAAAA==.Valgal:BAABNQAECn8aAAIIAAYKkAiD5gDjAAAIAAYKkAiD5gDjAAAAAA==.Valiraste:BAABNQAECn9KAAINAAoKahrFJAB+AgANAAoKahrFJAB+AgABNQAECgkJIgAWAFgTAA==.Valor:BAAANQAECgUIBgABNQAECgoKOAADAM4eAA==.Vantois:BAAANQAECgIIAgAAAA==.Vapor:BAAANQADCgQIBAAAAA==.Varalina:BAAANQAECgQIBgAAAA==.',
Vi='Viital:BAAANQADCgYIBgAAAA==.Vischar:BAAANQADCgUIBwAAAA==.',
Vo='Voidmommy:BAAANQABCgEIAQAAAA==.',
Wa='Washbeans:BAACNQAFFH8NAAMgAAQKKB3GDwDWAAAgAAMKfxvGDwDWAAAJAAMKqBu3CwCdAAA1AAQKfycAAyAACQpyHkchAIMCACAACQpyHkchAIMCAAkAAgoWGsGwAJEAAAAA.Wayne:BAAANQABCgQIAgAAAA==.',
We='Wef:BAABNQAECn86AAIIAAoKvgwfcwDZAQAIAAoKvgwfcwDZAQAAAA==.Weledronys:BAAANQADCgYICwAAAA==.',
Wh='Whyse:BAABNQAECn9KAAISAAoKGA5rZQDqAQASAAoKGA5rZQDqAQAAAA==.',
Wi='Wings:BAABNQAECn8iAAMQAAoKNRfEDACWAgAQAAoKNRfEDACWAgAlAAEKmw3FHQAyAAAAAA==.Wintel:BAAANQAECgEIAQAAAA==.Wizaes:BAAANQAECgEIAQAAAA==.',
Wo='Woolybullie:BAAANQADCgcIBwABNQAECgcIDQAiAAAAAA==.',
Xa='Xanza:BAAANQADCggIEQAAAA==.',
Ya='Yamzaio:BAAANQADCgUJBwAAAA==.',
Yo='Yo:BAAANQADCgcIDAAAAA==.',
Za='Zancrafter:BAAANQADCgIIAgABNQAFFAQIDQAVAAsXAA==.Zanduwuin:BAACNQAFFH8NAAIVAAQKCxekCQDIAAAVAAQKCxekCQDIAAA1AAQKfzAAAxUACgqnG/MQAOgCABUACgqnG/MQAOgCABoAAwqfCxwoAHUAAAAA.Zanvoker:BAABNQAECn8nAAQlAAkKNRfsBwAjAgAlAAkK1RbsBwAjAgAQAAYKThFzHwBeAQARAAcKJQnZKgBWAQABNQAFFAQIDQAVAAsXAA==.Zargar:BAABNQAECn80AAICAAoKuxzYCgCIAgACAAoKuxzYCgCIAgAAAA==.',
Zl='Zlatah:BAAANQADCgUIBQAAAA==.',
Zo='Zorttok:BAAANQAECgEIAQAAAA==.',
Zu='Zukkario:BAACNQAFFH8UAAMFAAYKXSN1BwBIAgAFAAYKBCN1BwBIAgAmAAQKxR8BAQB6AQA1AAQKfy4AAwUACgoIJsUXAFoDAAUACgrmJcUXAFoDACYAAgq0GgInAHUAAAE1AAUUCQkcAA8A1RwA.',
Zy='Zyp:BAAANQAECgYICQAAAA==.',
['Âx']='Âxel:BAABNQAECn83AAIOAAoKtyOwDwA/AwAOAAoKtyOwDwA/AwAAAA==.',
['År']='Årgon:BAABNQAECn8+AAIJAAoKtxscJACxAgAJAAoKtxscJACxAgAAAA==.',
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
