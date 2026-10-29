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

local lookup = {'Paladin-Holy','Paladin-Protection','Paladin-Retribution','Warrior-Protection','Warrior-Arms','Unknown-Unknown','DeathKnight-Blood','Hunter-BeastMastery','Shaman-Elemental','Rogue-Assassination','Warlock-Demonology','Shaman-Restoration','Rogue-Subtlety','Evoker-Devastation','Evoker-Preservation','Mage-Arcane','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','Monk-Mistweaver','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','Mage-Frost','DemonHunter-Vengeance','DemonHunter-Havoc','Druid-Guardian','Monk-Windwalker','Druid-Feral','Druid-Balance','Druid-Restoration','DeathKnight-Frost','Hunter-Marksmanship','Hunter-Survival','Evoker-Augmentation','Warrior-Fury',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abaddôn:BAAANQADCgYIBgAAAA==.',
Ad='Adirolf:BAAANQAECgUICwAAAA==.',
Ae='Aenlori:BAAANQADCgYIBgABNQAFFAYIDQABAFYSAA==.Aenlorie:BAACNQAFFH8NAAMBAAYKVhL1DgB1AQABAAUKkQ71DgB1AQACAAEKfAMrEgA7AAA1AAQKfzgABAEACgrFDihjAO8BAAEACgrFDihjAO8BAAMABQr9Fi3uAEABAAIABAryE7pJAMUAAAAA.',
Ag='Ag:BAAANQADCgMIAgAAAA==.Agesilaus:BAAANQADCgEIAQAAAA==.Aggathon:BAEBNQAECn8uAAMEAAkKpRBLDAB2AQAEAAkKpRBLDAB2AQAFAAQKvQSfsgCnAAAAAA==.',
Ak='Akebono:BAAANQADCgUIBQAAAA==.Akusai:BAAANQADCgYIBgABNQAECgQICAAGAAAAAA==.',
Al='Aldebaran:BAAANQAECgQIBwAAAA==.Alphatanker:BAACNQAFFH8JAAIHAAMKFCYOEQBGAQAHAAMKFCYOEQBGAQA1AAQKfzcAAgcACgrKJnsAAPkDAAcACgrKJnsAAPkDAAAA.',
Ar='Argentino:BAAANQAECgIIBQAAAA==.',
As='Ashke:BAABNQAECn8wAAIIAAoK1xWoJgBIAgAIAAoK1xWoJgBIAgAAAA==.',
Au='Aurica:BAAANQAECgYIBwAAAA==.',
Ax='Axes:BAAANQAECgQICwAAAA==.',
Ba='Badlucklouie:BAABNQAECn8oAAIJAAkKuhoaPgB9AgAJAAkKuhoaPgB9AgAAAA==.Badpenny:BAAANQAECgEIAQAAAA==.Bajenkas:BAAANQADCgYIBgAAAA==.Balfas:BAAANQAECgUIDQAAAA==.',
Be='Beaupeep:BAAANQAECgQICAAAAA==.',
Bi='Bighorner:BAAANQADCgQIBAAAAA==.Bigkahunas:BAAANQAECgEIAQAAAA==.Bigwarlock:BAAANQAECgIIAgAAAA==.Bindicrippa:BAAANQADCgcIFAAAAA==.',
Bl='Blackwater:BAABNQAECn8nAAIKAAgKABx7NAAJAgAKAAgKABx7NAAJAgAAAA==.Bloodstyx:BAAANQAECgQIBwABNQAECgoKKwAHAF0hAA==.',
Bo='Bobi:BAAANQAECgQIBQAAAA==.Boyacky:BAAANQADCgEIAQAAAA==.',
Br='Braiglock:BAABNQAECn8WAAILAAcKFActmgC7AAALAAcKFActmgC7AAAAAA==.Bratty:BAAANQADCggIDgAAAA==.',
Bu='Bucko:BAABNQAECn8qAAIIAAgKqxhNTQC1AQAIAAgKqxhNTQC1AQAAAA==.',
By='Bygz:BAABNQAECn8XAAMJAAcK1yBbTQBBAgAJAAYKXSJbTQBBAgAMAAQK2B6gTQBfAQABNQAFFAgIGwANAHEfAA==.',
['Bé']='Béésty:BAAANQAECgIIAwAAAA==.',
Ca='Caarjack:BAACNQAFFH8GAAMOAAMK3wsUBACCAAAOAAMK3wsUBACCAAAPAAEKCRRZGABDAAA1AAQKfy8AAw8ACgofGGAQAKMCAA8ACQoyGWAQAKMCAA4ABgpHFfAQAMMAAAAA.Callmefury:BAAANQAECgYIDgAAAA==.Callmeheal:BAAANQAECgUICAAAAA==.Callmemommy:BAAANQAECgEIAQAAAA==.Casserole:BAABNQAECn8dAAIQAAkKMxSK1wDYAQAQAAkKMxSK1wDYAQAAAA==.Catadelic:BAABNQAECn8uAAIIAAkKSAs+VACgAQAIAAkKSAs+VACgAQAAAA==.',
Ce='Celestial:BAABNQAECn8sAAMRAAkKJRRqAwCPAQARAAkKJRRqAwCPAQASAAIKzgPAIwBhAAAAAA==.',
Ch='Chewwbacca:BAABNQAECn8aAAQRAAgKyB2NBADhAgARAAgKyB2NBADhAgASAAEKXhRGKQBHAAALAAEKNAl2RgEwAAAAAA==.Chewwy:BAAANQADCgUIBQABNQAECggIGgARAMgdAA==.Chewwyy:BAAANQADCggICgABNQAECggIGgARAMgdAA==.Chud:BAAANQADCgYICQAAAA==.Chuwy:BAAANQADCgMIAwABNQAECggIGgARAMgdAA==.Chyse:BAAANQABCggIEgAAAA==.',
Cl='Clap:BAAANQADCgYIBgAAAA==.Cleombrotus:BAAANQADCgQIBAAAAA==.',
Cu='Cuzigothigh:BAAANQABCgIIAwAAAA==.',
Da='Darkdemon:BAACNQAFFH8HAAITAAYKPwrEAwARAQATAAYKPwrEAwARAQA1AAQKf1IAAhMACgqEJK0CALEDABMACgqEJK0CALEDAAAA.Darkladyann:BAAANQAFFAEIAQAAAA==.Darkxnemesis:BAABNQAECn8UAAIJAAgKxBTZNQB/AQAJAAgKxBTZNQB/AQAAAA==.',
De='Deadlee:BAABNQAECn8wAAIUAAkKzR1QBQDPAgAUAAkKzR1QBQDPAgAAAA==.Deathphish:BAABNQAECn8uAAMHAAkKNxaLHACuAQAHAAkKxRWLHACuAQAVAAcKzRBfXwCSAQAAAA==.Dentfry:BAABNQAECn8WAAIWAAkKtROYZwDoAQAWAAkKtROYZwDoAQAAAA==.Derfla:BAAANQAECgUIDAAAAA==.Deshler:BAABNQAECn8WAAMEAAYK2hKdGADPAAAEAAYK2hKdGADPAAAFAAEKbQRkXQEpAAAAAA==.Dethblazé:BAAANQAECgQIBwAAAA==.Dezign:BAABNQAECn8fAAMWAAoK4CH5EQA5AwAWAAoK4CH5EQA5AwAXAAYK2BF9HAAnAQABNQAFFAcIHgAYADshAA==.',
Di='Dildro:BAAANQAECgQIDQAAAA==.Dimhammer:BAAANQAECgUIBAAAAA==.Dirtyblonde:BAAANQAECgMIAwAAAA==.Ditlutz:BAABNQAECn8tAAICAAkKkSWOAwD2AgACAAkKkSWOAwD2AgAAAA==.',
Do='Dom:BAACNQAFFH8PAAIFAAcKiwzkCAA1AQAFAAcKiwzkCAA1AQA1AAQKfzEAAgUACgqNIekRANYCAAUACgqNIekRANYCAAAA.Doronjo:BAAANQADCggIDAAAAA==.Dorz:BAAANQADCgcIFAAAAA==.Dotrammy:BAAANQADCgcICQAAAA==.',
Du='Dupeslicate:BAABNQAECn8VAAIQAAkK7g5a3ADPAQAQAAkK7g5a3ADPAQAAAA==.',
Dw='Dwanco:BAAANQADCgEIAQAAAA==.Dwarfussy:BAAANQADCgMIAwAAAA==.',
Dy='Dybby:BAABNQAECn8WAAIQAAcKyRdRugAPAgAQAAcKyRdRugAPAgAAAA==.Dylexek:BAAANQADCgEIAQAAAA==.Dynamite:BAAANQADCgQIBAAAAA==.',
['Dé']='Détth:BAAANQAECgQICQAAAA==.',
El='Elderoth:BAABNQAECn8dAAIQAAoKGRkVYwC4AgAQAAoKGRkVYwC4AgAAAA==.Elfsky:BAAANQADCgUJBQAAAA==.',
En='Endlessnight:BAABNQAECn8rAAIHAAoKXSG2DgBaAgAHAAoKXSG2DgBaAgAAAA==.',
Er='Erica:BAAANQAECgQIBAAAAA==.',
['Eä']='Eärendil:BAAANQAECgcIDgAAAA==.',
Fa='Faebryn:BAAANQADCggIFAAAAA==.Faevor:BAABNQAECn8lAAMJAAkKZxA8NgB9AQAJAAkKZxA8NgB9AQAMAAMKKRy1zADOAAAAAA==.',
Fe='Femfatal:BAAANQAECgQIBAABNQAECgoKKwAHAF0hAA==.Fenirean:BAAANQAECgQIBgAAAA==.',
Fl='Flirts:BAAANQADCgYICgAAAA==.',
Fo='Forcas:BAABNQAECn87AAMZAAkKpR46BAAcAgAZAAgKcSE6BAAcAgAaAAkKIA+UIACRAQAAAA==.',
Fu='Fundus:BAAANQAECggICgAAAA==.',
Ga='Gamarrick:BAABNQAECn8XAAIXAAoK6QZJJADkAAAXAAoK6QZJJADkAAAAAA==.',
Ge='Germain:BAAANQADCgIIAgAAAA==.',
Gn='Gnometzu:BAAANQADCggIDgAAAA==.',
Go='Golddicmove:BAAANQAECgQIBgAAAA==.',
Gr='Gremmel:BAAANQADCggIDgAAAA==.Griever:BAABNQAECn9IAAQRAAoKRB6QKwAiAQALAAcK5Bs0gQDjAQARAAMKBSKQKwAiAQASAAEKGBbxKABIAAAAAA==.',
Gu='Guillak:BAABNQAECn8lAAMLAAgKjw8nVQBjAQALAAgKjw8nVQBjAQARAAIK6Qn+ZABaAAAAAA==.',
Ha='Hadroldel:BAABNQAECn8XAAIIAAoKTBPWNQAIAgAIAAoKTBPWNQAIAgAAAA==.Hammond:BAAANQADCgMICAAAAA==.Hanraktah:BAAANQADCgUIBQAAAA==.Harlem:BAAANQABCgQIBAAAAA==.Harxx:BAAANQADCgUICgAAAA==.Hatka:BAAANQAECgUIEgAAAA==.Hattori:BAAANQABCgUIBQAAAA==.',
Hi='Higurashi:BAAANQABCgQIBwAAAA==.',
Ho='Holymanson:BAAANQAECgMJAwAAAA==.Hoofington:BAABNQAECn8dAAIbAAcKYx+iFAAcAgAbAAcKYx+iFAAcAgAAAA==.Howlingdoom:BAAANQADCgYIBgAAAA==.',
Hy='Hylexerr:BAAANQAECgEIAgAAAA==.',
Ib='Ibull:BAAANQADCggICQAAAA==.',
If='Iffy:BAABNQAECn8mAAIIAAkK3xoFSQCRAgAIAAkK3xoFSQCRAgAAAA==.',
Il='Ilian:BAABNQAECn8bAAIcAAkK3xhoHABWAgAcAAkK3xhoHABWAgAAAA==.',
In='Iniquity:BAAANQADCggIFAAAAA==.',
Ja='Jabiso:BAABNQAECn8lAAIJAAoKsxB3UgAvAgAJAAoKsxB3UgAvAgAAAA==.Jackthebeast:BAAANQAECgEIAQABNQAECgoKIwAJAIwfAA==.Jackthefel:BAAANQAECgUIBQABNQAECgoKIwAJAIwfAA==.Jackthetotem:BAABNQAECn8jAAIJAAoKjB/UHgASAwAJAAoKjB/UHgASAwAAAA==.Jain:BAAANQAECgYIBwAAAA==.',
Jd='Jdmagisdruid:BAABNQAECn8sAAMdAAkKBSVLAgDpAgAdAAkKBSVLAgDpAgAeAAIKbx3IjgCbAAAAAA==.',
Je='Jeanne:BAABNQAECn8oAAMXAAkK0AlsIgD0AAAXAAgKvgVsIgD0AAAWAAgKPQHF1gCkAAAAAA==.Jedoniah:BAAANQAECgMIAwAAAA==.Jezabel:BAAANQADCgIIAgAAAA==.',
Jo='Jolnir:BAAANQADCgcIBwABNQAECgkJLQADALEaAA==.Jorcingmyshi:BAAANQAECggIEwAAAA==.Jorhmont:BAAANQADCgUIBQAAAA==.',
Ju='Juan:BAABNQAECn8pAAMfAAcKLhk5HQB5AQAfAAcKLhk5HQB5AQAeAAEKAAAYgwAAAAAAAA==.Jumpeor:BAACNQAFFH8QAAMDAAcKnxjWBAAUAgADAAYKKhnWBAAUAgACAAEKcBZ/DwBOAAA1AAQKfzQAAgMACgpQJWEEANcDAAMACgpQJWEEANcDAAAA.',
Ka='Kanig:BAAANQADCggJEgAAAA==.Kassey:BAAANQAECgEIAQAAAA==.Katacola:BAACNQAFFH8YAAIfAAcKgRlKAwAYAgAfAAcKgRlKAwAYAgA1AAQKfzYAAx8ACgq1JM0FAGYDAB8ACgq1JM0FAGYDAB4ABwp5FokfAIoBAAAA.',
Ke='Kenaf:BAAANQADCgQIBwAAAA==.Kendrys:BAABNQAECn8VAAQHAAkKLxAyZABhAQAHAAkK4Q8yZABhAQAgAAUK2wnHbQDnAAAVAAIKuwRf0QBLAAAAAA==.Kethria:BAAANQABCgIIAgABNQAECgkJMgAIAEgjAA==.Kevenal:BAABNQAECn8sAAIhAAoKLh9fBwCGAgAhAAoKLh9fBwCGAgAAAA==.Keyainor:BAAANQADCggIDgABNQAECgUICQAGAAAAAA==.',
Ki='Kikiliki:BAABNQAECn8VAAIIAAYKWg8o5wAzAQAIAAYKWg8o5wAzAQAAAA==.Killmartin:BAAANQAECggIEAAAAA==.Kinneas:BAABNQAECn8bAAIDAAkKvxYSUAClAgADAAkKvxYSUAClAgAAAA==.Kizmit:BAAANQAECgEIAQAAAA==.',
Kl='Klënz:BAAANQAECgEIAQAAAA==.',
Ko='Koa:BAAANQAECgQIBwAAAA==.',
Ku='Kurau:BAABNQAECn8UAAIiAAcK6gS8CwAwAQAiAAcK6gS8CwAwAQAAAA==.Kurzal:BAAANQAECgYIEQAAAA==.',
Ky='Kyraz:BAACNQAFFH8bAAMNAAgKcR/gAABTAgANAAcKRB7gAABTAgAKAAYK4CBgAwAuAgA1AAQKfx4AAw0ACgo0Jh0BAIEDAA0ACQo0Jh0BAIEDAAoACQrgIrcHAFkDAAAA.',
La='Lacie:BAABNQAECn8jAAIIAAYK5AdSmAAAAQAIAAYK5AdSmAAAAQAAAA==.Lavos:BAAANQAECgUIBQABNQAECgoKKgADAHwdAA==.',
Le='Leela:BAAANQAECggICAAAAA==.Lexy:BAAANQAECgEIAQABNQAECgkJMQATAD8eAA==.',
Lo='Lokiel:BAAANQAECgQICAAAAA==.Lokifurion:BAABNQAECn8qAAMfAAkKaRASFwC/AQAfAAkKaRASFwC/AQAeAAQKHgMvkwCLAAAAAA==.',
Lu='Lunitari:BAAANQAECgIIBAAAAA==.',
Ly='Lyaenna:BAABNQAECn8jAAIWAAkKshujFwCmAgAWAAkKshujFwCmAgAAAA==.',
Ma='Mageshir:BAAANQAECgYIBgAAAA==.Magrat:BAAANQADCgIIAgAAAA==.Mahu:BAAANQAECgQIBAAAAA==.Malchi:BAAANQAECgUIBQABNQAFFAcIGAAKALYeAA==.Maletherion:BAABNQAECn8sAAIhAAkKeRM1EADDAQAhAAkKeRM1EADDAQAAAA==.Maltherion:BAABNQAECn8iAAMaAAoKHRpWIACXAgAaAAoKHRpWIACXAgATAAEKAAA9dAAmAAAAAA==.Margareetah:BAAANQAECgQICAAAAA==.Martinix:BAAANQAECggIBwAAAA==.',
Me='Meglamonk:BAAANQAECgUICwAAAA==.',
Mi='Milarca:BAAANQABCgYIDQAAAA==.Minireaper:BAAANQADCgMIAwAAAA==.Misbehavin:BAAANQADCgQIBAAAAA==.',
Mj='Mjolnir:BAABNQAECn8tAAIDAAkKsRo9QgDzAQADAAkKsRo9QgDzAQAAAA==.',
Mo='Mochizuko:BAAANQABCgIIAgAAAA==.Mongke:BAAANQADCggICAAAAA==.Moonre:BAAANQADCgYIEgAAAA==.',
Mu='Mubvan:BAAANQAECgcIBgAAAA==.Mushroommans:BAAANQAECgQIBgABNQAFFAMIBgATAPMhAA==.',
My='Mystaris:BAAANQADCgYICgAAAA==.',
Na='Namôr:BAAANQAECgEIAQAAAA==.Narzel:BAAANQAECgUICQAAAA==.Nashîr:BAABNQAECn8fAAIFAAoKzhGCSACtAQAFAAoKzhGCSACtAQAAAA==.Navybum:BAAANQAECgQIDAAAAA==.',
Ne='Nehemiah:BAABNQAECn8zAAMEAAkKiSEUBgAJAwAEAAkKiSEUBgAJAwAFAAEKPxovRQFHAAAAAA==.Nequin:BAABNQAECn8mAAIBAAoKMhw6NwCHAgABAAoKMhw6NwCHAgABNQAECgoKLQAMABAgAA==.Nequins:BAAANQAECgYIDQABNQAECgoKLQAMABAgAA==.Nequinss:BAABNQAECn8tAAIMAAoKECB2EgC5AgAMAAoKECB2EgC5AgAAAA==.Nevermore:BAAANQAECgEIAQAAAA==.',
Ni='Nicabar:BAABNQAECn8vAAILAAgK8wf9qgB8AQALAAgK8wf9qgB8AQAAAA==.Nilfheim:BAAANQAECgUIBwAAAA==.Nivla:BAAANQABCgMIAwAAAA==.',
No='Noadie:BAAANQAECgcIBgAAAA==.Noehtyar:BAAANQAECgUIEQAAAA==.Noie:BAABNQAECn8WAAIYAAgKBQJRLQCTAAAYAAgKBQJRLQCTAAAAAA==.Novadd:BAAANQADCgUIBQAAAA==.Novä:BAAANQAECgQIBAAAAA==.Noztalgia:BAAANQAECgQIBwAAAA==.',
['Në']='Nëklaüs:BAABNQAECn8gAAIHAAYKbhULQgDYAAAHAAYKbhULQgDYAAAAAA==.',
Od='Odanarratite:BAAANQAECgEIAQAAAA==.Odanarrayne:BAAANQADCgcIBwAAAA==.Oditte:BAAANQADCggIDgAAAA==.Odysseuss:BAAANQAECgMIBAAAAA==.',
Oi='Oilliphéist:BAAANQAECgUIBQAAAA==.',
On='Onewithyou:BAAANQADCgEIAQAAAA==.Onimaru:BAAANQABCgEIAQAAAA==.',
Or='Ornot:BAABNQAECn8zAAIMAAoK5Q++WwD8AQAMAAoK5Q++WwD8AQAAAA==.',
Os='Oshdruid:BAAANQADCgYICwAAAA==.',
Pa='Paislìe:BAAANQADCggICAAAAA==.Palacola:BAAANQAECgcIBwABNQAFFAgIGAAfAIEZAA==.Pandurbear:BAAANQAECgEIAQAAAA==.Paperplate:BAABNQAECn8bAAIBAAgKFBKkSQBwAQABAAgKFBKkSQBwAQAAAA==.Paws:BAAANQADCgMJBgAAAA==.',
Pe='Peposhammy:BAAANQADCgUIBQAAAA==.',
Ph='Phuul:BAAANQADCgMIAwABNQADCgYIEQAGAAAAAA==.Phuulith:BAAANQADCgYIEQAAAA==.',
Pr='Provost:BAABNQAECn8qAAIDAAoKfB0BRwC/AgADAAoKfB0BRwC/AgAAAA==.',
Ps='Psychonoia:BAABNQAECn8aAAIXAAkKtBJmKgDUAQAXAAkKtBJmKgDUAQAAAA==.',
Pu='Pumperdogx:BAAANQADCgYIBgABNQAFFAMICQAHABQmAA==.Pumpkinpîe:BAAANQADCgYIBgAAAA==.',
Qu='Quadritrix:BAAANQADCgQIBAAAAA==.Quanx:BAAANQAECgcICAAAAA==.Quark:BAAANQAECgIIAgAAAA==.',
Ra='Ratacola:BAAANQAECgQIBgABNQAFFAgIGAAfAIEZAA==.',
Re='Remulüs:BAABNQAECn8xAAMTAAkKPx7IDwD1AgATAAkKPx7IDwD1AgAaAAUKlRJRWQAiAQAAAA==.Reoãn:BAAANQABCgQIBgABNQADCgUIBQAGAAAAAA==.',
Ri='Riah:BAAANQAECgEIAQAAAA==.Riilyn:BAABNQAECn8nAAMKAAoKmxiaHQCTAgAKAAkKERmaHQCTAgANAAQKexNqZQDJAAAAAA==.',
['Rø']='Røean:BAAANQADCgUIBQAAAA==.',
Sa='Saintmartin:BAAANQAECggIBgAAAA==.Sanktis:BAAANQADCggIFgAAAA==.',
Sb='Sbcarpenter:BAAANQAECgMIAgAAAA==.',
Sc='Scawmfhealz:BAAANQABCgMIAwAAAA==.Scecretzs:BAAANQADCgYIEQAAAA==.',
Se='Sebone:BAAANQADCggIDQAAAA==.Secretz:BAAANQAECgUIEwAAAA==.Sedrelari:BAABNQAECn8yAAMIAAkKSCMzIAAXAwAIAAgKwCIzIAAXAwAiAAcKqB0aBwASAgAAAA==.Sengseng:BAAANQADCgUIBgAAAA==.Sephirøth:BAAANQAECgcICgAAAA==.Sepsis:BAAANQAECgUICQAAAA==.Sesamo:BAACNQAFFH8GAAIDAAIKOA4OFwCNAAADAAIKOA4OFwCNAAA1AAQKfysAAgMACgr+GztIALwCAAMACgr+GztIALwCAAAA.',
Sh='Shadedstørmz:BAAANQAECgMIBwAAAA==.Shocks:BAAANQAECgQIDgAAAA==.Shé:BAABNQAECn8eAAICAAgKjxY8HQABAgACAAgKjxY8HQABAgAAAA==.',
Si='Sixoneseven:BAAANQAECgQIBQAAAA==.Sixseven:BAABNQAECn8tAAMTAAoKahF5EADhAQATAAoKahF5EADhAQAZAAoKZAtqCgA9AQAAAA==.',
Sk='Skaarlett:BAAANQAECgQIBAAAAA==.Skone:BAABNQAECn8dAAMBAAgKlgmWhQCKAQABAAgKlgmWhQCKAQADAAEKEQPazQEhAAAAAA==.',
Sm='Smarthen:BAAANQABCgQIBAABNQAECgoKJAAbAKoiAA==.Smolhatka:BAAANQAECgQIBQABNQAECgUIEgAGAAAAAA==.',
Sn='Snickers:BAABNQAECn8bAAIjAAkK0g8MDACZAQAjAAkK0g8MDACZAQAAAA==.',
So='Solarian:BAABNQAECn8oAAITAAgK7hKPGwBSAQATAAgK7hKPGwBSAQAAAA==.',
St='Starosa:BAAANQADCgEIAQAAAA==.Startle:BAAANQADCgcIIAAAAA==.Steelbreeze:BAAANQAECgQICgAAAA==.Storms:BAACNQAFFH8GAAMQAAMKQBVITgCJAAAQAAIKShJITgCJAAAYAAEKNhhxDABOAAA1AAQKf0EAAxAACgrmIqBNAOYCABAACgpqHqBNAOYCABgAAwrdJAcYADkBAAAA.Stoutbringer:BAAANQAECgUIBwAAAA==.Stride:BAAANQABCgMIAwABNQAECgoKIAAOADUXAA==.Strikes:BAAANQAFFAEIAQAAAA==.Stronknehen:BAAANQAECgQIBAABNQAECgoKJAAbAKoiAA==.',
Sy='Sylvaedir:BAAANQADCggICQAAAA==.',
['Sö']='Sören:BAABNQAECn8aAAIHAAcKexAQPgDpAAAHAAcKexAQPgDpAAAAAA==.',
Ta='Taomi:BAABNQAECn8hAAIMAAkK2hN2JgAbAgAMAAkK2hN2JgAbAgAAAA==.',
Te='Teaka:BAAANQAECgQIBwAAAA==.Tenspeed:BAABNQAECn8kAAITAAgKDRb0GABuAQATAAgKDRb0GABuAQAAAA==.Teof:BAAANQAECgUIBQAAAA==.Terelle:BAAANQAECgQIBAABNQAECggIHQABAJYJAA==.Terellesguy:BAAANQADCgQIBAABNQAECgkJKAAJALoaAA==.Tetsuro:BAAANQADCgUIBwAAAA==.',
Th='Thire:BAAANQADCggICwABNQAECggIHQABAJYJAA==.Throwglaive:BAABNQAECn8VAAIaAAgK2BsGNAAMAgAaAAgK2BsGNAAMAgABNQAFFAgIGwANAHEfAA==.',
Ti='Tidereign:BAAANQAECgYIDQAAAA==.Tinytotems:BAABNQAECn8uAAIMAAkKSBpBLQDxAQAMAAkKSBpBLQDxAQAAAA==.Tiriell:BAABNQAECn8jAAIDAAkKUBUFewA1AgADAAkKUBUFewA1AgAAAA==.',
To='Toe:BAACNQAFFH8FAAIQAAMKCAn7OgDYAAAQAAMKCAn7OgDYAAA1AAQKfxkAAhAACgrKIe8mAEUDABAACgrKIe8mAEUDAAAA.Touchmee:BAAANQADCgcIAQAAAA==.',
Tr='Trausti:BAAANQAECgUJCQAAAA==.Treehen:BAABNQAECn8kAAIbAAoKqiLIBABXAwAbAAoKqiLIBABXAwAAAA==.Trinanah:BAACNQAFFH8IAAIXAAMKMQTKCwB/AAAXAAMKMQTKCwB/AAA1AAQKfywAAhcACgpRErInAO0BABcACgpRErInAO0BAAAA.Troltsky:BAAANQADCgQIBAAAAA==.',
['Tô']='Tôrunn:BAAANQAECgUICgABNQAECgkJGgAXALQSAA==.',
Va='Valariann:BAAANQADCggICAABNQAECgoKNgANAE4aAA==.Valeriux:BAAANQADCgUJAwAAAA==.Valgal:BAABNQAECn8VAAIIAAYKSgjaqwDWAAAIAAYKSgjaqwDWAAAAAA==.Valiraste:BAABNQAECn8xAAILAAoKNBenJQAgAgALAAoKNBenJQAgAgABNQAFFAEIAQAGAAAAAA==.Valor:BAAANQAECgEIAQABNQAECgoKKgADAHwdAA==.Vantois:BAAANQADCgMIAwAAAA==.Vapor:BAAANQADCgQIBAAAAA==.Varalina:BAAANQAECgQIBgAAAA==.',
Vi='Viital:BAAANQADCgYIBgAAAA==.Vischar:BAAANQADCgUIBwAAAA==.',
Vo='Voidmommy:BAAANQABCgEIAQAAAA==.',
Wa='Washbeans:BAACNQAFFH8MAAMgAAQKKB0+CADqAAAgAAMKfxs+CADqAAAVAAMKqBv2BgCxAAA1AAQKfycAAyAACQpyHkchAIMCACAACQpyHkchAIMCABUAAgoWGsGwAJEAAAAA.Wayne:BAAANQABCgQIAgAAAA==.',
We='Wef:BAABNQAECn8jAAIIAAkKrgxHXwCBAQAIAAkKrgxHXwCBAQAAAA==.Weledronys:BAAANQADCgYICwAAAA==.',
Wh='Whyse:BAABNQAECn8rAAIQAAcKww5YkgAfAQAQAAcKww5YkgAfAQABNQAECggIGwABABQSAA==.',
Wi='Wings:BAABNQAECn8gAAIOAAoKNRfEDACWAgAOAAoKNRfEDACWAgAAAA==.Wintel:BAAANQADCgYIBwAAAA==.Wizaes:BAAANQAECgEIAQAAAA==.',
Wo='Woolybullie:BAAANQADCgcIBwABNQAECgUICQAGAAAAAA==.',
Xa='Xanza:BAAANQADCggIEQAAAA==.',
Ya='Yamzaio:BAAANQADCgUJBwAAAA==.',
Yo='Yo:BAAANQADCgcIDAAAAA==.',
Za='Zancrafter:BAAANQADCgIIAgABNQAFFAQIDQATAAsXAA==.Zanduwuin:BAACNQAFFH8NAAITAAQKCxcQBgDZAAATAAQKCxcQBgDZAAA1AAQKfzAAAxMACgqnG/MQAOgCABMACgqnG/MQAOgCABkAAwqfCxwoAHUAAAAA.Zanvoker:BAABNQAECn8nAAQjAAkKNRfsBwAjAgAjAAkK1RbsBwAjAgAOAAYKThFzHwBeAQAPAAcKJQnZKgBWAQABNQAFFAQIDQATAAsXAA==.Zargar:BAABNQAECn8fAAICAAgKGhmREACXAQACAAgKGhmREACXAQAAAA==.',
Zl='Zlatah:BAAANQADCgUIBQAAAA==.',
Zo='Zorttok:BAAANQAECgEIAQAAAA==.',
Zu='Zukkario:BAACNQAFFH8UAAMFAAYKXSN1BwBIAgAFAAYKBCN1BwBIAgAkAAQKxR8BAQB6AQA1AAQKfysAAwUACgoIJsUXAFoDAAUACgrmJcUXAFoDACQAAgq0GgInAHUAAAE1AAUUCAgbAA0AcR8A.',
Zy='Zyp:BAAANQAECgQIBAAAAA==.',
['Âx']='Âxel:BAABNQAECn8oAAIMAAoKcSOvEgAzAwAMAAoKcSOvEgAzAwAAAA==.',
['År']='Årgon:BAABNQAECn8wAAIVAAoKkhocJACxAgAVAAoKkhocJACxAgAAAA==.',
['ße']='ßen:BAAANQADCgcIDQAAAA==.',
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
