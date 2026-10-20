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

local lookup = {'Paladin-Holy','Paladin-Protection','Paladin-Retribution','Warrior-Protection','Warrior-Arms','Unknown-Unknown','DeathKnight-Blood','Hunter-BeastMastery','Shaman-Elemental','Rogue-Assassination','Shaman-Restoration','Rogue-Subtlety','Evoker-Preservation','Evoker-Devastation','Mage-Arcane','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','DemonHunter-Devourer','Monk-Mistweaver','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','Mage-Frost','DemonHunter-Vengeance','DemonHunter-Havoc','Druid-Guardian','Monk-Windwalker','Druid-Feral','Druid-Balance','Druid-Restoration','Hunter-Marksmanship','Hunter-Survival','Evoker-Augmentation','DeathKnight-Frost','Warrior-Fury',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abaddôn:BAAANQADCgYIBgAAAA==.',
Ad='Adirolf:BAAANQAECgQIBgAAAA==.',
Ae='Aenlori:BAAANQADCgYIBgABNQAFFAYIDQABAFYSAA==.Aenlorie:BAACNQAFFH8NAAMBAAYKVhL1DgB1AQABAAUKkQ71DgB1AQACAAEKfAMrEgA7AAA1AAQKfzYABAEACgoeDihjAO8BAAEACgoeDihjAO8BAAMABQr9Fi3uAEABAAIABAryE7pJAMUAAAAA.',
Ag='Ag:BAAANQADCgMIAgAAAA==.Agesilaus:BAAANQADCgEIAQAAAA==.Aggathon:BAEBNQAECn8lAAMEAAgKsQ54GwCDAQAEAAcKThB4GwCDAQAFAAQKvQTKcwC0AAAAAA==.',
Ak='Akebono:BAAANQADCgUJBQAAAA==.Akusai:BAAANQADCgYIBgABNQADCggINwAGAAAAAA==.',
Al='Aldebaran:BAAANQAECgQIBwAAAA==.Alphatanker:BAACNQAFFH8JAAIHAAMKFCYOEQBGAQAHAAMKFCYOEQBGAQA1AAQKfzYAAgcACgrKJnsAAPkDAAcACgrKJnsAAPkDAAAA.',
Ar='Argentino:BAAANQAECgIIAwAAAA==.',
As='Ashke:BAABNQAECn8lAAIIAAkK3xWDawA8AgAIAAkK3xWDawA8AgAAAA==.',
Au='Aurica:BAAANQAECgYIBwAAAA==.',
Ax='Axes:BAAANQAECgUICQAAAA==.',
Ba='Badlucklouie:BAABNQAECn8iAAIJAAgKpBsaPgB9AgAJAAgKpBsaPgB9AgAAAA==.Badpenny:BAAANQAECgEIAQAAAA==.Bajenkas:BAAANQADCgYIBgAAAA==.Balfas:BAAANQAECgUIDQAAAA==.',
Be='Beaupeep:BAAANQADCggINwAAAA==.',
Bi='Bighorner:BAAANQADCgQIBAAAAA==.Bigkahunas:BAAANQAECgEIAQAAAA==.Bindicrippa:BAAANQADCgcIFAAAAA==.',
Bl='Blackwater:BAABNQAECn8kAAIKAAcKTBp7NAAJAgAKAAcKTBp7NAAJAgAAAA==.Bloodstyx:BAAANQAECgUIBwABNQAECgoKJAAHABMhAA==.',
Bo='Bobi:BAAANQAECgQIBAAAAA==.Boyacky:BAAANQADCgEIAQAAAA==.',
Br='Braiglock:BAAANQAECgUIEQAAAA==.Bratty:BAAANQADCgcIDQAAAA==.',
Bu='Bucko:BAABNQAECn8iAAIIAAcKYxkCRAAtAQAIAAcKYxkCRAAtAQAAAA==.',
By='Bygz:BAABNQAECn8UAAMJAAcKuR5bTQBBAgAJAAYKXSJbTQBBAgALAAQK2B75HgBuAQABNQAFFAcIGQAMAAUeAA==.',
['Bé']='Béésty:BAAANQAECgIIAgAAAA==.',
Ca='Caarjack:BAABNQAECn8rAAMNAAoKHxhgEACjAgANAAkKMhlgEACjAgAOAAYKJRNyCgDBAAAAAA==.Callmefury:BAAANQAECgYIDwAAAA==.Callmeheal:BAAANQAECgMIBAAAAA==.Callmemommy:BAAANQADCgUIBQAAAA==.Casserole:BAABNQAECn8bAAIPAAcKGRSK1wDYAQAPAAcKGRSK1wDYAQAAAA==.Catadelic:BAABNQAECn8lAAIIAAgKjgpWkADoAQAIAAgKjgpWkADoAQAAAA==.',
Ce='Celestial:BAABNQAECn8kAAMQAAkKghLuEgDcAQAQAAkKghLuEgDcAQARAAIKzgPAIwBhAAAAAA==.',
Ch='Chewwbacca:BAABNQAECn8aAAQQAAgKyB2NBADhAgAQAAgKyB2NBADhAgARAAEKXhRGKQBHAAASAAEKNAl2RgEwAAAAAA==.Chewwy:BAAANQADCgUIBQABNQAECggIGgAQAMgdAA==.Chewwyy:BAAANQADCggICgABNQAECggIGgAQAMgdAA==.Chud:BAAANQADCgYICQAAAA==.Chuwy:BAAANQADCgMIAwABNQAECggIGgAQAMgdAA==.Chyse:BAAANQABCggIEgAAAA==.',
Cl='Clap:BAAANQADCgYIBgAAAA==.',
Cu='Cuzigothigh:BAAANQABCgIIAwAAAA==.',
Da='Darkdemon:BAABNQAECn9FAAITAAoKpCKtAgCxAwATAAoKpCKtAgCxAwAAAA==.Darkladyann:BAAANQAFFAEIAQAAAA==.Darkxnemesis:BAAANQAECgYIDQAAAA==.',
De='Deadlee:BAABNQAECn8nAAIUAAkKzhySAQCmAgAUAAkKzhySAQCmAgAAAA==.Deathphish:BAABNQAECn8lAAMHAAgKdRN3IAD6AAAVAAcKzRBfXwCSAQAHAAYKVRF3IAD6AAAAAA==.Dentfry:BAABNQAECn8UAAIWAAkKqhOYZwDoAQAWAAkKqhOYZwDoAQAAAA==.Derfla:BAAANQAECgQIBwAAAA==.Deshler:BAAANQAECggIDQAAAA==.Dethblazé:BAAANQAECgQIBAAAAA==.Dezign:BAABNQAECn8WAAMWAAoKViD5EQA5AwAWAAoKViD5EQA5AwAXAAEK+gWegAAqAAABNQAFFAcIHgAYADshAA==.',
Di='Dildro:BAAANQAECgQICQAAAA==.Dirtyblonde:BAAANQAECgMIAwAAAA==.Ditlutz:BAABNQAECn8kAAICAAkKUCPYAADaAgACAAkKUCPYAADaAgAAAA==.',
Do='Dom:BAACNQAFFH8OAAIFAAYK1A2+DgDIAQAFAAYK1A2+DgDIAQA1AAQKfyYAAgUACgqUHK9BAMUCAAUACgqUHK9BAMUCAAAA.Doronjo:BAAANQADCggIDAAAAA==.Dorz:BAAANQADCgcIEgAAAA==.Dotrammy:BAAANQADCgcICQAAAA==.',
Du='Dupeslicate:BAAANQAECgcIDwAAAA==.',
Dw='Dwanco:BAAANQADCgEIAQAAAA==.Dwarfussy:BAAANQADCgMIAwAAAA==.',
Dy='Dybby:BAABNQAECn8UAAIPAAcKyRdRugAPAgAPAAcKyRdRugAPAgAAAA==.Dylexek:BAAANQADCgEIAQAAAA==.Dynamite:BAAANQADCgQIBAAAAA==.',
['Dé']='Détth:BAAANQAECgMIBQAAAA==.',
El='Elderoth:BAABNQAECn8ZAAIPAAoK0RUVYwC4AgAPAAoK0RUVYwC4AgAAAA==.Elfsky:BAAANQADCgUJBQAAAA==.',
En='Endlessnight:BAABNQAECn8kAAIHAAoKEyHzAgBZAgAHAAoKEyHzAgBZAgAAAA==.',
Er='Erica:BAAANQAECgQIBAAAAA==.',
['Eä']='Eärendil:BAAANQAECgUIBwAAAA==.',
Fa='Faebryn:BAAANQADCggIFAAAAA==.Faevor:BAABNQAECn8cAAMJAAkKBg/+DwCVAQAJAAkKBg/+DwCVAQALAAMKKRy1zADOAAAAAA==.',
Fe='Femfatal:BAAANQAECgQIBAABNQAECgoKJAAHABMhAA==.Fenirean:BAAANQAECgYIBwAAAA==.',
Fl='Flirts:BAAANQADCgYICgAAAA==.',
Fo='Forcas:BAABNQAECn8iAAMZAAgKSh+DAgCmAQAZAAcKiiKDAgCmAQAaAAEKCg/vSgBCAAAAAA==.',
Fu='Fundus:BAAANQAECgIIAwAAAA==.',
Ga='Gamarrick:BAAANQAECgcIDwAAAA==.',
Ge='Germain:BAAANQADCgIIAgAAAA==.',
Gn='Gnometzu:BAAANQADCggIDgAAAA==.',
Go='Golddicmove:BAAANQAECgQIBgAAAA==.',
Gr='Gremmel:BAAANQADCgcICQAAAA==.Griever:BAABNQAECn9EAAQQAAoKcxuQKwAiAQASAAcKYxc0gQDjAQAQAAMKBSKQKwAiAQARAAEKGBbxKABIAAAAAA==.',
Gu='Guillak:BAABNQAECn8eAAMSAAcKiBBOLQBAAQASAAcKiBBOLQBAAQAQAAIK6Qn+ZABaAAAAAA==.',
Ha='Hadroldel:BAAANQAECgcIDQAAAA==.Hammond:BAAANQADCgMICAAAAA==.Hanraktah:BAAANQADCgUIBQAAAA==.Harlem:BAAANQABCgQIBAAAAA==.Harxx:BAAANQADCgUICgAAAA==.Hatka:BAAANQAECgUIDwAAAA==.Hattori:BAAANQABCgUIBQAAAA==.',
Hi='Higurashi:BAAANQABCgQIBwAAAA==.',
Ho='Holymanson:BAAANQAECgMJAwAAAA==.Hoofington:BAABNQAECn8ZAAIbAAcKYx+tCQBgAQAbAAcKYx+tCQBgAQAAAA==.Howlingdoom:BAAANQADCgYIBgAAAA==.',
Hy='Hylexerr:BAAANQAECgEIAgAAAA==.',
Ib='Ibull:BAAANQADCggICQAAAA==.',
If='Iffy:BAABNQAECn8jAAIIAAkK2BoFSQCRAgAIAAkK2BoFSQCRAgAAAA==.',
Il='Ilian:BAABNQAECn8bAAIcAAkK3xhoHABWAgAcAAkK3xhoHABWAgAAAA==.',
In='Iniquity:BAAANQADCggIFAAAAA==.',
Ja='Jabiso:BAABNQAECn8hAAIJAAkKvxB3UgAvAgAJAAkKvxB3UgAvAgAAAA==.Jackthebeast:BAAANQAECgEIAQABNQAECgoKHQAJAJQeAA==.Jackthefel:BAAANQAECgUIBQABNQAECgoKHQAJAJQeAA==.Jackthetotem:BAABNQAECn8dAAIJAAoKlB7UHgASAwAJAAoKlB7UHgASAwAAAA==.Jain:BAAANQAECgYIBwAAAA==.',
Jd='Jdmagisdruid:BAABNQAECn8jAAMdAAkK4SLpAABoAgAdAAkK4SLpAABoAgAeAAIKbx0WRABXAAAAAA==.Jdmagislock:BAAANQAECgIIAgABNQAECgkJIwAdAOEiAA==.',
Je='Jeanne:BAABNQAECn8fAAMWAAkKZAHF1gCkAAAWAAgKGQHF1gCkAAAXAAcKugTFHgCUAAAAAA==.Jezabel:BAAANQADCgIIAgAAAA==.',
Jo='Jolnir:BAAANQADCgcIBwABNQAECgkJJAADAIYaAA==.Jorcingmyshi:BAAANQAECgcIEgAAAA==.Jorhmont:BAAANQADCgUIBQAAAA==.',
Ju='Juan:BAABNQAECn8iAAMfAAcK4xZ1FwAHAQAfAAcK4xZ1FwAHAQAeAAEKAAB+YgAAAAAAAA==.Jumpeor:BAACNQAFFH8QAAMDAAcKnxjWBAAUAgADAAYKKhnWBAAUAgACAAEKcBZ/DwBOAAA1AAQKfzQAAgMACgpQJWEEANcDAAMACgpQJWEEANcDAAAA.',
Ka='Kanig:BAAANQADCggJEgAAAA==.Kassey:BAAANQAECgEIAQAAAA==.Katacola:BAACNQAFFH8XAAIfAAYK4xtKAwAYAgAfAAYK4xtKAwAYAgA1AAQKfysAAh8ACgqiJM0FAGYDAB8ACgqiJM0FAGYDAAAA.',
Ke='Kenaf:BAAANQADCgQIBwAAAA==.Kendrys:BAAANQAECgcIEwAAAA==.Kevenal:BAABNQAECn8lAAIgAAoKPB6MAQCIAgAgAAoKPB6MAQCIAgAAAA==.Keyainor:BAAANQADCggICAABNQAECgUICgAGAAAAAA==.',
Ki='Kikiliki:BAAANQAECgUIEgAAAA==.Killmartin:BAAANQAECggIEAAAAA==.Kinneas:BAABNQAECn8bAAIDAAkKvxYSUAClAgADAAkKvxYSUAClAgAAAA==.Kizmit:BAAANQAECgIIAgAAAA==.',
Kl='Klënz:BAAANQAECgEIAQAAAA==.',
Ko='Koa:BAAANQAECgQIBwAAAA==.',
Ku='Kurau:BAABNQAECn8UAAIhAAcK6gS8CwAwAQAhAAcK6gS8CwAwAQAAAA==.Kurzal:BAAANQAECgYIEQAAAA==.',
Ky='Kyraz:BAACNQAFFH8ZAAMMAAcKBR6wAAD4AQAKAAYK4CBgAwAuAgAMAAYKFBywAAD4AQA1AAQKfxQAAwoACgosI7cHAFkDAAoACQrgIrcHAFkDAAwAAQpDJd45AG8AAAAA.',
La='Lacie:BAABNQAECn8dAAIIAAYK5AcBUQAQAQAIAAYK5AcBUQAQAQAAAA==.Lavos:BAAANQAECgQIAwABNQAECgkJJQADABYeAA==.',
Le='Lexy:BAAANQAECgEIAQABNQAECgkJKAATADUeAA==.',
Lo='Lokiel:BAAANQAECgQICAAAAA==.Lokifurion:BAABNQAECn8hAAMfAAgKwg6VDgBYAQAfAAgKwg6VDgBYAQAeAAQKHgMvkwCLAAAAAA==.',
Lu='Lunitari:BAAANQAECgIIAgAAAA==.',
Ly='Lyaenna:BAABNQAECn8aAAIWAAgK1BdOJgBmAQAWAAgK1BdOJgBmAQAAAA==.',
Ma='Mageshir:BAAANQADCgYICQAAAA==.Magrat:BAAANQADCgIIAgAAAA==.Mahu:BAAANQAECgQIBAAAAA==.Malchi:BAAANQAECgUIBQABNQAFFAYIFwAKADEcAA==.Maletherion:BAABNQAECn8jAAIgAAkKChMvBwB0AQAgAAkKChMvBwB0AQAAAA==.Maltherion:BAABNQAECn8hAAMaAAoKHRpWIACXAgAaAAoKHRpWIACXAgATAAEKAAA9dAAmAAAAAA==.Margareetah:BAAANQAECgUIBAAAAA==.',
Me='Meglamonk:BAAANQAECgUICAAAAA==.',
Mi='Milarca:BAAANQABCgYIDQAAAA==.Minireaper:BAAANQADCgMIAwAAAA==.Misbehavin:BAAANQADCgQIBAAAAA==.',
Mj='Mjolnir:BAABNQAECn8kAAIDAAkKhhpUDAAgAgADAAkKhhpUDAAgAgAAAA==.',
Mo='Mochizuko:BAAANQABCgIIAgAAAA==.Mongke:BAAANQADCggICAAAAA==.Moonre:BAAANQADCgYIEgAAAA==.',
Mu='Mubvan:BAAANQABCgMIAwAAAA==.Mushroommans:BAAANQAECgQIBgABNQAFFAMIBgATAPMhAA==.',
My='Mystaris:BAAANQADCgYICgAAAA==.',
Na='Namôr:BAAANQAECgEIAQAAAA==.Narzel:BAAANQAECgUIBwAAAA==.Nashîr:BAABNQAECn8bAAIFAAgK6xLGKwBaAQAFAAgK6xLGKwBaAQAAAA==.Navybum:BAAANQAECgQICQAAAA==.',
Ne='Nehemiah:BAABNQAECn8qAAMEAAkKYiAVAQB7AgAEAAkKYiAVAQB7AgAFAAEKPxovRQFHAAAAAA==.Nequin:BAABNQAECn8gAAIBAAkKpBs6NwCHAgABAAkKpBs6NwCHAgABNQAECgkJKQALAPYeAA==.Nequins:BAAANQAECgUICAABNQAECgkJKQALAPYeAA==.Nequinss:BAABNQAECn8pAAILAAkK9h5FBgBvAgALAAkK9h5FBgBvAgAAAA==.Nevermore:BAAANQAECgEIAQAAAA==.',
Ni='Nicabar:BAABNQAECn8pAAISAAgKqwfCYADBAAASAAgKqwfCYADBAAAAAA==.Nilfheim:BAAANQAECgUIBwAAAA==.Nivla:BAAANQABCgMIAwAAAA==.',
No='Noadie:BAAANQAECgcIBgAAAA==.Noehtyar:BAAANQAECgUIDwAAAA==.Noie:BAAANQAECgcIEAAAAA==.Novadd:BAAANQADCgUIBQAAAA==.Novä:BAAANQAECgQIBAAAAA==.Noztalgia:BAAANQAECgQIBwAAAA==.',
['Në']='Nëklaüs:BAABNQAECn8bAAIHAAYKbhUSJADmAAAHAAYKbhUSJADmAAAAAA==.',
Od='Odanarratite:BAAANQAECgEIAQAAAA==.Odanarrayne:BAAANQADCgcIBwAAAA==.Oditte:BAAANQADCggIDgAAAA==.',
Oi='Oilliphéist:BAAANQAECgUIBQAAAA==.',
On='Onewithyou:BAAANQADCgEIAQAAAA==.Onimaru:BAAANQAECgEIAQAAAA==.',
Or='Ornot:BAABNQAECn8vAAILAAoK0w++WwD8AQALAAoK0w++WwD8AQAAAA==.',
Os='Oshdruid:BAAANQADCgYICwAAAA==.',
Pa='Paislìe:BAAANQADCggIAgAAAA==.Palacola:BAAANQAECgEIAQAAAA==.Pandurbear:BAAANQAECgEIAQAAAA==.Paperplate:BAAANQAECgYIEAABNQAECgcIIwAPAH0NAA==.Paws:BAAANQADCgMJBgAAAA==.',
Pe='Peposhammy:BAAANQADCgUIBQAAAA==.',
Ph='Phuulith:BAAANQADCgYIEQAAAA==.',
Pr='Provost:BAABNQAECn8lAAIDAAkKFh4BRwC/AgADAAkKFh4BRwC/AgAAAA==.',
Ps='Psychonoia:BAABNQAECn8XAAIXAAcKTBVmKgDUAQAXAAcKTBVmKgDUAQAAAA==.',
Pu='Pumperdogx:BAAANQADCgYIBgABNQAFFAMICQAHABQmAA==.Pumpkinpîe:BAAANQADCgYIBgAAAA==.',
Qu='Quadritrix:BAAANQADCgQIBAAAAA==.Quanx:BAAANQAECgcICAAAAA==.Quark:BAAANQAECgIIAgAAAA==.',
Ra='Ratacola:BAAANQAECgQIBgAAAA==.',
Re='Remulüs:BAABNQAECn8oAAMTAAkKNR7IDwD1AgATAAkKNR7IDwD1AgAaAAUKlRJRWQAiAQAAAA==.Reoãn:BAAANQABCgQIBgABNQADCgUIBQAGAAAAAA==.',
Ri='Riah:BAAANQAECgEIAQAAAA==.Riilyn:BAABNQAECn8jAAIKAAkKERmaHQCTAgAKAAkKERmaHQCTAgAAAA==.',
['Rø']='Røean:BAAANQADCgUIBQAAAA==.',
Sa='Sanktis:BAAANQADCggIFgAAAA==.',
Sb='Sbcarpenter:BAAANQAECgMIAgAAAA==.',
Sc='Scawmfhealz:BAAANQABCgMIAwAAAA==.Scecretzs:BAAANQADCgYIEQAAAA==.',
Se='Sebone:BAAANQADCggIDQAAAA==.Secretz:BAAANQAECgYIEgAAAA==.Sedrelari:BAABNQAECn8vAAMIAAkKSCMzIAAXAwAIAAgKwCIzIAAXAwAhAAcKqB0aBwASAgAAAA==.Seizethesol:BAAANQAECgEIAQAAAA==.Sengseng:BAAANQADCgUIBgAAAA==.Sephirøth:BAAANQAECgQIBAAAAA==.Sepsis:BAAANQAECgUICQAAAA==.Serjaime:BAAANQAECgEIAQAAAA==.Sesamo:BAABNQAECn8nAAIDAAkK2R47SAC8AgADAAkK2R47SAC8AgAAAA==.',
Sh='Shadedstørmz:BAAANQAECgMIBQAAAA==.Shocks:BAAANQAECgUICgAAAA==.Shé:BAABNQAECn8bAAICAAgKjxY8HQABAgACAAgKjxY8HQABAgAAAA==.',
Si='Sixoneseven:BAAANQAECgQIBgAAAA==.Sixseven:BAABNQAECn8jAAMZAAoK1g4YBABeAQATAAgKtRACKwDpAQAZAAoKZAsYBABeAQAAAA==.',
Sk='Skaarlett:BAAANQAECgMIBAAAAA==.Skone:BAABNQAECn8dAAMBAAgKlgmWhQCKAQABAAgKlgmWhQCKAQADAAEKEQPazQEhAAAAAA==.',
Sm='Smarthen:BAAANQABCgQIBAABNQAECgoKIAAbAGAhAA==.Smolhatka:BAAANQAECgQIBAABNQAECgUIDwAGAAAAAA==.',
Sn='Snickers:BAABNQAECn8ZAAIiAAcKPhIMDACZAQAiAAcKPhIMDACZAQAAAA==.',
So='Solarian:BAABNQAECn8hAAITAAcK8BSwDgA+AQATAAcK8BSwDgA+AQAAAA==.',
St='Starosa:BAAANQADCgEIAQAAAA==.Startle:BAAANQADCgcIHgAAAA==.Steelbreeze:BAAANQAECgQIBgAAAA==.Storms:BAABNQAECn82AAMPAAoKVCJGJgB9AQAPAAoK1x1GJgB9AQAYAAMK3SQHGAA5AQAAAA==.Stoutbringer:BAAANQAECgQIBAAAAA==.Stride:BAAANQABCgMIAwABNQAECgoKHwAOADUXAA==.Strikes:BAAANQAECgUIBQAAAA==.',
Sy='Sylvaedir:BAAANQADCggICQAAAA==.',
['Sö']='Sören:BAABNQAECn8UAAIHAAcKexCCZABgAQAHAAcKexCCZABgAQAAAA==.',
Ta='Taomi:BAABNQAECn8YAAILAAkKpRJdCgAcAgALAAkKpRJdCgAcAgAAAA==.',
Te='Teaka:BAAANQAECgQIBAAAAA==.Tenspeed:BAABNQAECn8cAAITAAcK+hb0FgD2AAATAAcK+hb0FgD2AAAAAA==.Teof:BAAANQAECgUIBQAAAA==.Terelle:BAAANQADCggICAABNQAECggIHQABAJYJAA==.Terellesguy:BAAANQADCgQIBAABNQAECggIIgAJAKQbAA==.Tetsuro:BAAANQADCgUIBwAAAA==.',
Th='Thire:BAAANQADCggICwABNQAECggIHQABAJYJAA==.Throwglaive:BAAANQAECgcIEwABNQAFFAcIGQAMAAUeAA==.',
Ti='Tidereign:BAAANQAECgYIDQAAAA==.Tinytotems:BAABNQAECn8lAAILAAkKRBqADQD0AQALAAkKRBqADQD0AQAAAA==.Tiriell:BAABNQAECn8jAAIDAAkKUBUFewA1AgADAAkKUBUFewA1AgAAAA==.',
To='Toe:BAACNQAFFH8FAAIPAAMKCAn7OgDYAAAPAAMKCAn7OgDYAAA1AAQKfxkAAg8ACgrKIe8mAEUDAA8ACgrKIe8mAEUDAAAA.Touchmee:BAAANQADCgcIAQAAAA==.',
Tr='Trausti:BAAANQAECgUJCQAAAA==.Treehen:BAABNQAECn8gAAIbAAoKYCFwAgAvAgAbAAoKYCFwAgAvAgAAAA==.Trinanah:BAACNQAFFH8GAAIXAAMKMAJSCABxAAAXAAMKMAJSCABxAAA1AAQKfygAAhcACgrVEbInAO0BABcACgrVEbInAO0BAAAA.Troltsky:BAAANQADCgQIBAAAAA==.',
['Tô']='Tôrunn:BAAANQAECgUIBgABNQAECggIFwAXAEwVAA==.',
Va='Valariann:BAAANQADCggICAABNQAECgoKMQAMAA4YAA==.Valeriux:BAAANQADCgUJAwAAAA==.Valgal:BAAANQAECgYICwAAAA==.Valiraste:BAABNQAECn8pAAISAAoKExZAIABuAQASAAoKExZAIABuAQABNQAFFAEIAQAGAAAAAA==.Valor:BAAANQAECgEIAQABNQAECgkJJQADABYeAA==.Vapor:BAAANQADCgQIBAAAAA==.Varalina:BAAANQAECgQJBgAAAA==.',
Vi='Viital:BAAANQADCgYIBgAAAA==.Vischar:BAAANQADCgUIBwAAAA==.',
Vo='Voidmommy:BAAANQABCgEIAQAAAA==.',
Wa='Washbeans:BAACNQAFFH8KAAMjAAQKfxt5BADyAAAjAAMKfxt5BADyAAAVAAIK6wm3CgAAAAA1AAQKfycAAyMACQpyHkchAIMCACMACQpyHkchAIMCABUAAgoWGsGwAJEAAAAA.Wayne:BAAANQABCgQIAgAAAA==.',
We='Wef:BAABNQAECn8aAAIIAAgK0wyFkQDmAQAIAAgK0wyFkQDmAQAAAA==.Weledronys:BAAANQADCgUICgAAAA==.',
Wh='Whyse:BAABNQAECn8jAAIPAAcKfQ2e8QCnAQAPAAcKfQ2e8QCnAQAAAA==.',
Wi='Wings:BAABNQAECn8fAAIOAAoKNRfEDACWAgAOAAoKNRfEDACWAgAAAA==.Wintel:BAAANQADCgYIBwAAAA==.Wizaes:BAAANQAECgEIAQAAAA==.',
Wo='Woolybullie:BAAANQADCgcIBwABNQAECgUICgAGAAAAAA==.',
Xa='Xanza:BAAANQADCgYIDgAAAA==.',
Ya='Yamzaio:BAAANQADCgUJBwAAAA==.',
Yo='Yo:BAAANQADCgcIDAAAAA==.',
Za='Zancrafter:BAAANQADCgIIAgABNQAFFAMICQATAAsXAA==.Zanduwuin:BAACNQAFFH8JAAITAAMKCxd7BADQAAATAAMKCxd7BADQAAA1AAQKfy0AAxMACgq7GvMQAOgCABMACgq7GvMQAOgCABkAAwqfCxwoAHUAAAAA.Zanvoker:BAABNQAECn8nAAQiAAkKNRfsBwAjAgAiAAkK1RbsBwAjAgAOAAYKThFzHwBeAQANAAcKJQnZKgBWAQABNQAFFAMICQATAAsXAA==.Zargar:BAABNQAECn8ZAAICAAcKOxhjCgBTAQACAAcKOxhjCgBTAQAAAA==.',
Zo='Zorttok:BAAANQAECgEIAQAAAA==.',
Zu='Zukkario:BAACNQAFFH8UAAMFAAYKXSN1BwBIAgAFAAYKBCN1BwBIAgAkAAQKxR8BAQB6AQA1AAQKfyUAAwUACgr6JcUXAFoDAAUACgrYJcUXAFoDACQAAQr3JgInAHUAAAE1AAUUBwgZAAwABR4A.',
Zy='Zyp:BAAANQAECgIIAgAAAA==.',
['Âx']='Âxel:BAABNQAECn8jAAILAAgKZSSvEgAzAwALAAgKZSSvEgAzAwAAAA==.',
['År']='Årgon:BAABNQAECn8vAAIVAAoKkhocJACxAgAVAAoKkhocJACxAgAAAA==.',
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
