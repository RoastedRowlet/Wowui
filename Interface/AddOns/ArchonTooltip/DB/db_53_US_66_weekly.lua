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

local lookup = {'Paladin-Holy','Paladin-Protection','Paladin-Retribution','Warrior-Protection','DeathKnight-Blood','Hunter-BeastMastery','Shaman-Elemental','Rogue-Assassination','Warrior-Arms','Evoker-Preservation','Evoker-Devastation','Mage-Arcane','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','DemonHunter-Devourer','Monk-Mistweaver','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','Mage-Frost','DemonHunter-Vengeance','Monk-Windwalker','Druid-Feral','Druid-Balance','Druid-Restoration','Hunter-Marksmanship','Unknown-Unknown','Hunter-Survival','Rogue-Subtlety','DemonHunter-Havoc','Shaman-Restoration','Druid-Guardian','Evoker-Augmentation','DeathKnight-Frost','Warrior-Fury',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abaddôn:BAAANQADCgYIBgAAAA==.',
Ad='Adirolf:BAAANQAECgQIBgAAAA==.',
Ae='Aenlori:BAAANQADCgYIBgABNQAFFAYIDQABAFYSAA==.Aenlorie:BAACNQAFFH8NAAMBAAYKVhKODgB1AQABAAUKkQ6ODgB1AQACAAEKfAPYEQA7AAA1AAQKfzMABAEACQrpDO9hAPABAAEACQrpDO9hAPABAAMABQoDFWPqAEABAAIABAryE8tIAMYAAAAA.',
Ag='Ag:BAAANQADCgMIAgAAAA==.Agesilaus:BAAANQADCgEIAQAAAA==.Aggathon:BAEBNQAECn8dAAIEAAcKThAMGwCEAQAEAAcKThAMGwCEAQAAAA==.',
Ak='Akebono:BAAANQADCgUJBQAAAA==.',
Al='Aldebaran:BAAANQAECgQIBwAAAA==.Alphatanker:BAACNQAFFH8JAAIFAAMKFCafEABGAQAFAAMKFCafEABGAQA1AAQKfzQAAgUACQrHJnoAAPkDAAUACQrHJnoAAPkDAAAA.',
Ar='Argentino:BAAANQAECgEJAQAAAA==.',
As='Ashke:BAABNQAECn8iAAIGAAgKfRbVaQA9AgAGAAgKfRbVaQA9AgAAAA==.',
Au='Aurica:BAAANQAECgEIAgAAAA==.',
Ax='Axes:BAAANQAECgQICAAAAA==.',
Ba='Badlucklouie:BAABNQAECn8hAAIHAAgKpBtDPQB+AgAHAAgKpBtDPQB+AgAAAA==.Badpenny:BAAANQADCgYIFwAAAA==.Bajenkas:BAAANQADCgYIBgAAAA==.Balfas:BAAANQAECgUIDQAAAA==.',
Be='Beaupeep:BAAANQADCggINwAAAA==.',
Bi='Bighorner:BAAANQADCgQIBAAAAA==.Bindicrippa:BAAANQADCgcIFAAAAA==.',
Bl='Blackwater:BAABNQAECn8iAAIIAAcK3xl7MwAJAgAIAAcK3xl7MwAJAgAAAA==.Bloodstyx:BAAANQAECgMIAwABNQAECggIHQAFAFMfAA==.',
Bo='Bobi:BAAANQAECgQIBAAAAA==.Boyacky:BAAANQADCgEIAQAAAA==.',
Br='Braiglock:BAAANQAECgUICwAAAA==.Bratty:BAAANQADCgUICwAAAA==.',
Bu='Bucko:BAABNQAECn8cAAIGAAcKBxn9dQAhAgAGAAcKBxn9dQAhAgAAAA==.',
By='Bygz:BAAANQAECgYIDwABNQAFFAYIFAAJAF0jAA==.',
['Bé']='Béésty:BAAANQAECgIIAgAAAA==.',
Ca='Caarjack:BAABNQAECn8nAAMKAAkKMhk1EACkAgAKAAkKMhk1EACkAgALAAQKFBj6JQAFAQAAAA==.Callmefury:BAAANQAECgUICQAAAA==.Callmeheal:BAAANQAECgMIBAAAAA==.Callmemommy:BAAANQADCgUIBQAAAA==.Casserole:BAABNQAECn8bAAIMAAcKGRRj1QDZAQAMAAcKGRRj1QDZAQAAAA==.Catadelic:BAABNQAECn8kAAIGAAgKjgo/jgDpAQAGAAgKjgo/jgDpAQAAAA==.',
Ce='Celestial:BAABNQAECn8gAAMNAAcKNxTHEgDcAQANAAcKNxTHEgDcAQAOAAIKzgNnIwBhAAAAAA==.',
Ch='Chewwbacca:BAABNQAECn8aAAQNAAgKyB2GBADhAgANAAgKyB2GBADhAgAOAAEKXhTeKABHAAAPAAEKNAmhQgEwAAAAAA==.Chewwy:BAAANQADCgUIBQABNQAECggIGgANAMgdAA==.Chewwyy:BAAANQADCggICgABNQAECggIGgANAMgdAA==.Chud:BAAANQADCgYICQAAAA==.Chuwy:BAAANQADCgMIAwABNQAECggIGgANAMgdAA==.Chyse:BAAANQABCggIEAAAAA==.',
Cl='Clap:BAAANQADCgYIBgAAAA==.',
Cu='Cuzigothigh:BAAANQABCgEIAQAAAA==.',
Da='Darkdemon:BAABNQAECn8+AAIQAAkK8yOXAgCyAwAQAAkK8yOXAgCyAwAAAA==.Darkladyann:BAAANQAFFAEIAQAAAA==.Darkxnemesis:BAAANQAECgYIBwAAAA==.',
De='Deadlee:BAABNQAECn8eAAIRAAgKsBzmDgCPAgARAAgKsBzmDgCPAgAAAA==.Deathphish:BAABNQAECn8dAAMSAAgKORJiXgCSAQASAAcKzRBiXgCSAQAFAAUKrhBhcQAsAQAAAA==.Dentfry:BAAANQAFFAEIAQAAAA==.Derfla:BAAANQAECgQIBwAAAA==.Deshler:BAAANQAECggICQAAAA==.Dethblazé:BAAANQAECgQIBAAAAA==.Dezign:BAABNQAECn8VAAMTAAkKqSCXEQA6AwATAAkKqSCXEQA6AwAUAAEK+gXmfgAqAAABNQAFFAYIGAAVAJ4hAA==.',
Di='Dildro:BAAANQAECgQICQAAAA==.Ditlutz:BAABNQAECn8bAAICAAgKdyObBwAmAwACAAgKdyObBwAmAwAAAA==.',
Do='Dom:BAACNQAFFH8JAAIJAAYK1A1UDgDJAQAJAAYK1A1UDgDJAQA1AAQKfyMAAgkACQqXH8tAAMUCAAkACQqXH8tAAMUCAAAA.Doronjo:BAAANQADCggIDAAAAA==.Dorz:BAAANQADCgcIEgAAAA==.Dotrammy:BAAANQADCgcICQAAAA==.',
Du='Dupeslicate:BAAANQAECgYIDgAAAA==.',
Dw='Dwanco:BAAANQADCgEIAQAAAA==.Dwarfussy:BAAANQADCgMIAwAAAA==.',
Dy='Dybby:BAAANQAECgYIEQAAAA==.Dylexek:BAAANQADCgEIAQAAAA==.Dynamite:BAAANQADCgQIBAAAAA==.',
['Dé']='Détth:BAAANQAECgMIBQAAAA==.',
El='Elderoth:BAAANQAECggIEAAAAA==.Elfsky:BAAANQADCgUJBQAAAA==.',
En='Endlessnight:BAABNQAECn8dAAIFAAgKUx91HQDDAgAFAAgKUx91HQDDAgAAAA==.',
Er='Erica:BAAANQAECgQIBAAAAA==.',
['Eä']='Eärendil:BAAANQAECgUIBQAAAA==.',
Fa='Faebryn:BAAANQADCggIFAAAAA==.Faevor:BAAANQAECgYIDgAAAA==.',
Fe='Femfatal:BAAANQAECgQIBAABNQAECggIHQAFAFMfAA==.Fenirean:BAAANQAECgQIBQAAAA==.',
Fl='Flirts:BAAANQADCgYICgAAAA==.',
Fo='Forcas:BAABNQAECn8bAAIWAAcKiiLqBgChAgAWAAcKiiLqBgChAgAAAA==.',
Fu='Fundus:BAAANQAECgIIAgAAAA==.',
Ga='Gamarrick:BAAANQAECgcIDwAAAA==.',
Ge='Germain:BAAANQADCgIIAgAAAA==.',
Gn='Gnometzu:BAAANQADCggIDgAAAA==.',
Go='Golddicmove:BAAANQAECgIIAgAAAA==.',
Gr='Gremmel:BAAANQADCgcICQAAAA==.Griever:BAABNQAECn8+AAQNAAkK1x5ZKwAiAQAPAAYKTxxXfwDjAQANAAMKBSJZKwAiAQAOAAEKGBaJKABIAAAAAA==.',
Gu='Guillak:BAABNQAECn8YAAMPAAcKHQ+FtgBcAQAPAAYKYw6FtgBcAQANAAIK6QlxZABaAAAAAA==.',
Ha='Hadroldel:BAAANQAECgcICgAAAA==.Hammond:BAAANQADCgMICAAAAA==.Hanraktah:BAAANQADCgUIBQAAAA==.Harlem:BAAANQABCgQIBAAAAA==.Harxx:BAAANQADCgUICgAAAA==.Hatka:BAAANQAECgUICQAAAA==.Hattori:BAAANQABCgUIBQAAAA==.',
Hi='Higurashi:BAAANQABCgQIBwAAAA==.',
Ho='Holymanson:BAAANQAECgMJAwAAAA==.Hoofington:BAAANQAECgUIDwAAAA==.Howlingdoom:BAAANQADCgYIBgAAAA==.',
Hy='Hylexerr:BAAANQAECgEIAgAAAA==.',
Ib='Ibull:BAAANQADCggICQAAAA==.',
If='Iffy:BAABNQAECn8gAAIGAAgKDhz/RwCSAgAGAAgKDhz/RwCSAgAAAA==.',
Il='Ilian:BAABNQAECn8bAAIXAAkK3xgVHABWAgAXAAkK3xgVHABWAgAAAA==.',
In='Iniquity:BAAANQADCggIFAAAAA==.',
Ja='Jabiso:BAABNQAECn8cAAIHAAgKVRFSUQAwAgAHAAgKVRFSUQAwAgAAAA==.Jackthebeast:BAAANQAECgEIAQABNQAECgkJGwAHAPEfAA==.Jackthefel:BAAANQAECgQJBQABNQAECgkJGwAHAPEfAA==.Jackthetotem:BAABNQAECn8bAAIHAAkK8R9gHgASAwAHAAkK8R9gHgASAwAAAA==.Jain:BAAANQAECgEIAgAAAA==.',
Jd='Jdmagisdruid:BAABNQAECn8aAAMYAAgKYiM4BABLAwAYAAgKYiM4BABLAwAZAAIKrRtIjQCbAAAAAA==.',
Je='Jeanne:BAAANQAECgYIEgAAAA==.Jezabel:BAAANQADCgIIAgAAAA==.',
Jo='Jorcingmyshi:BAAANQAECgcIEgAAAA==.Jorhmont:BAAANQADCgUIBQAAAA==.',
Ju='Juan:BAABNQAECn8bAAIaAAYKLRlrLAC1AQAaAAYKLRlrLAC1AQAAAA==.Jumpeor:BAACNQAFFH8QAAMDAAcKnxh/BAAZAgADAAYKKhl/BAAZAgACAAEKcBY/DwBOAAA1AAQKfzAAAgMACQquJj4EANcDAAMACQquJj4EANcDAAAA.',
Ka='Kanig:BAAANQADCggJEgAAAA==.Kassey:BAAANQADCgYIGAAAAA==.Katacola:BAACNQAFFH8XAAIaAAYK4xsMAwAbAgAaAAYK4xsMAwAbAgA1AAQKfyoAAhoACQqpJLAFAGYDABoACQqpJLAFAGYDAAAA.',
Ke='Kenaf:BAAANQADCgQIBwAAAA==.Kendrys:BAAANQAECgcIEwAAAA==.Kevenal:BAABNQAECn8bAAIbAAkK4holEADmAgAbAAkK4holEADmAgAAAA==.Keyainor:BAAANQADCggICAABNQAECgMIBQAcAAAAAA==.',
Ki='Kikiliki:BAAANQAECgQIEQAAAA==.Killmartin:BAAANQAECggIEAAAAA==.Kinneas:BAABNQAECn8bAAIDAAkKvxaSTgClAgADAAkKvxaSTgClAgAAAA==.Kizmit:BAAANQAECgEIAQAAAA==.',
Kl='Klënz:BAAANQAECgEIAQAAAA==.',
Ko='Koa:BAAANQAECgQIBwAAAA==.',
Ku='Kurau:BAABNQAECn8UAAIdAAcK6gSeCwAvAQAdAAcK6gSeCwAvAQAAAA==.Kurzal:BAAANQAECgUIDAAAAA==.',
Ky='Kyraz:BAABNQAFFH8TAAMIAAYK4CA6AwAuAgAIAAYK4CA6AwAuAgAeAAMKxgXYDADWAAABNQAFFAYIFAAJAF0jAA==.',
La='Lacie:BAABNQAECn8VAAIGAAYKwgc4zABkAQAGAAYKwgc4zABkAQAAAA==.',
Le='Lexy:BAAANQAECgEIAQABNQAECggIIwAQAKsfAA==.',
Lo='Lokiel:BAAANQAECgQICAAAAA==.Lokifurion:BAABNQAECn8aAAMaAAgKBg4iOQBQAQAaAAcK/QwiOQBQAQAZAAQKHgOUkQCLAAAAAA==.',
Lu='Lunitari:BAAANQAECgIIAgAAAA==.',
Ly='Lyaenna:BAAANQAECgcIEwAAAA==.',
Ma='Mageshir:BAAANQADCgYICQAAAA==.Magrat:BAAANQADCgIIAgAAAA==.Mahu:BAAANQAECgQIBAAAAA==.Maletherion:BAABNQAECn8bAAIbAAgKAhMLKgD4AQAbAAgKAhMLKgD4AQAAAA==.Maltherion:BAABNQAECn8ZAAMfAAgK3B3OHwCYAgAfAAgK3B3OHwCYAgAQAAEKAABecgAmAAAAAA==.Margareetah:BAAANQAECgIIAgAAAA==.',
Me='Meglamonk:BAAANQAECgUICAAAAA==.',
Mi='Milarca:BAAANQABCgYIDQAAAA==.Minireaper:BAAANQADCgMIAwAAAA==.Misbehavin:BAAANQADCgQIBAAAAA==.',
Mj='Mjolnir:BAABNQAECn8bAAIDAAgK2RrLYABzAgADAAgK2RrLYABzAgAAAA==.',
Mo='Mochizuko:BAAANQABCgIIAgAAAA==.Mongke:BAAANQABCggICAAAAA==.Moonre:BAAANQADCgYIEgAAAA==.',
Mu='Mubvan:BAAANQABCgMIAwAAAA==.Mushroommans:BAAANQAECgQIBgABNQAFFAMIBQAQAPMhAA==.',
My='Mystaris:BAAANQADCgYICgAAAA==.',
Na='Namôr:BAAANQADCgYIEgAAAA==.Narzel:BAAANQAECgUIBwAAAA==.Nashîr:BAAANQAECgcIEQAAAA==.Navybum:BAAANQAECgQICAAAAA==.',
Ne='Nehemiah:BAABNQAECn8hAAMEAAgKaiIABgAJAwAEAAgKaiIABgAJAwAJAAEKPxruQAFHAAAAAA==.Nequin:BAABNQAECn8eAAIBAAgK+RuoNgCHAgABAAgK+RuoNgCHAgABNQAECggIIAAgAFcfAA==.Nequins:BAAANQAECgMIAwABNQAECggIIAAgAFcfAA==.Nequinss:BAABNQAECn8gAAIgAAgKVx/2JQDLAgAgAAgKVx/2JQDLAgAAAA==.Nevermore:BAAANQAECgEIAQAAAA==.',
Ni='Nicabar:BAABNQAECn8jAAIPAAgKPge7qAB8AQAPAAgKPge7qAB8AQAAAA==.Nilfheim:BAAANQAECgUIBwAAAA==.Nivla:BAAANQABCgMIAwAAAA==.',
No='Noadie:BAAANQAECgcIBgAAAA==.Noehtyar:BAAANQAECgUICwAAAA==.Noie:BAAANQAECgUIDQAAAA==.Novadd:BAAANQADCgUIBQAAAA==.Novä:BAAANQAECgQIBAAAAA==.Noztalgia:BAAANQAECgQIBwAAAA==.',
['Në']='Nëklaüs:BAAANQAECgQIEQAAAA==.',
Od='Odanarratite:BAAANQAECgEIAQAAAA==.Odanarrayne:BAAANQADCgcIBwAAAA==.Oditte:BAAANQADCggIDgAAAA==.',
Oi='Oilliphéist:BAAANQAECgUIBQAAAA==.',
On='Onewithyou:BAAANQADCgEIAQAAAA==.Onimaru:BAAANQABCgEIAQAAAA==.',
Or='Ornot:BAABNQAECn8rAAIgAAkKDhG1WgD8AQAgAAkKDhG1WgD8AQAAAA==.',
Os='Oshdruid:BAAANQADCgYICwAAAA==.',
Pa='Paislìe:BAAANQADCggIAgAAAA==.Palacola:BAAANQAECgEIAQAAAA==.Pandurbear:BAAANQADCgYIGAAAAA==.Paperplate:BAAANQAECgUIDgABNQAECgcIIAAMAH0NAA==.Paws:BAAANQADCgMJBgAAAA==.',
Pe='Peposhammy:BAAANQADCgUIBQAAAA==.',
Ph='Phuulith:BAAANQADCgYIEQAAAA==.',
Pr='Provost:BAABNQAECn8jAAIDAAgKth5nRQDBAgADAAgKth5nRQDBAgAAAA==.',
Ps='Psychonoia:BAAANQAECggIEAAAAA==.',
Pu='Pumperdogx:BAAANQADCgYIBgABNQAFFAMICQAFABQmAA==.Pumpkinpîe:BAAANQADCgYIBgAAAA==.',
Qu='Quadritrix:BAAANQADCgQIBAAAAA==.Quanx:BAAANQAECgcICAAAAA==.Quark:BAAANQAECgIIAgAAAA==.',
Ra='Ratacola:BAAANQAECgQIBgAAAA==.',
Re='Remulüs:BAABNQAECn8jAAMQAAgKqx9fDwD2AgAQAAgKqx9fDwD2AgAfAAUKlRI2WAAiAQAAAA==.Reoãn:BAAANQABCgQIBgABNQADCgUIBQAcAAAAAA==.',
Ri='Riah:BAAANQAECgEIAQAAAA==.Riilyn:BAABNQAECn8iAAIIAAgKXRr0HACTAgAIAAgKXRr0HACTAgAAAA==.',
['Rø']='Røean:BAAANQADCgUIBQAAAA==.',
Sa='Sanktis:BAAANQADCggIFgAAAA==.',
Sb='Sbcarpenter:BAAANQAECgMIAgAAAA==.',
Sc='Scawmfhealz:BAAANQABCgMIAwAAAA==.Scecretzs:BAAANQADCgYIEQAAAA==.',
Se='Sebone:BAAANQADCggIDQAAAA==.Secretz:BAAANQAECgUIDQAAAA==.Sedrelari:BAABNQAECn8rAAMGAAkKRCOoHwAXAwAGAAgKuyKoHwAXAwAdAAcKqB0IBwASAgAAAA==.Sengseng:BAAANQADCgUIBgAAAA==.Sepsis:BAAANQAECgUICQAAAA==.Serjaime:BAAANQABCgQJCAAAAA==.Sesamo:BAABNQAECn8kAAIDAAkKJh7QRgC9AgADAAkKJh7QRgC9AgAAAA==.',
Sh='Shadedstørmz:BAAANQAECgMIBQAAAA==.Shocks:BAAANQAECgQICQAAAA==.Shé:BAABNQAECn8YAAICAAgKhhbnHAACAgACAAgKhhbnHAACAgAAAA==.',
Si='Sixoneseven:BAAANQAECgMIAwAAAA==.Sixseven:BAABNQAECn8ZAAMQAAgKuhCOKgDpAQAQAAgKtRCOKgDpAQAWAAYKNA1BHAD0AAAAAA==.',
Sk='Skaarlett:BAAANQAECgMIBAAAAA==.Skone:BAABNQAECn8cAAMBAAgKCglfhACKAQABAAgKCglfhACKAQADAAEKEQNgxwEhAAAAAA==.',
Sm='Smarthen:BAAANQABCgQIBAABNQAECgkJGgAhAFYgAA==.',
Sn='Snickers:BAABNQAECn8ZAAIiAAcKPhLuCwCZAQAiAAcKPhLuCwCZAQAAAA==.',
So='Solarian:BAABNQAECn8bAAIQAAcKMBTVLwC/AQAQAAcKMBTVLwC/AQAAAA==.',
St='Starosa:BAAANQADCgEIAQAAAA==.Startle:BAAANQADCgcIHgAAAA==.Steelbreeze:BAAANQAECgIIAgAAAA==.Storms:BAABNQAECn8wAAMMAAkKiCHOTADoAgAMAAkKZxzOTADoAgAVAAMK3STCFwA5AQAAAA==.Stoutbringer:BAAANQADCgcIHgAAAA==.Stride:BAAANQABCgMIAwABNQAECgkJGwALAD8VAA==.',
Sy='Sylvaedir:BAAANQADCggICQAAAA==.',
['Sö']='Sören:BAAANQAECgYIEgAAAA==.',
Ta='Taomi:BAAANQAECgcIDQAAAA==.',
Te='Teaka:BAAANQADCggIGAAAAA==.Tenspeed:BAAANQAECgYIEwAAAA==.Teof:BAAANQAECgUIBQAAAA==.Terellesguy:BAAANQADCgQIBAABNQAECggIIQAHAKQbAA==.Tetsuro:BAAANQADCgUIBwAAAA==.',
Th='Thire:BAAANQADCgcICwABNQAECggIHAABAAoJAA==.Throwglaive:BAAANQAECgcIEAABNQAFFAYIFAAJAF0jAA==.',
Ti='Tidereign:BAAANQAECgQICAAAAA==.Tinytotems:BAABNQAECn8dAAIgAAgKwRehTgAnAgAgAAgKwRehTgAnAgAAAA==.Tiriell:BAABNQAECn8jAAIDAAkKUBUyeQA1AgADAAkKUBUyeQA1AgAAAA==.',
To='Toe:BAACNQAFFH8FAAIMAAMKCAnCOQDYAAAMAAMKCAnCOQDYAAA1AAQKfxgAAgwACQqUIVImAEcDAAwACQqUIVImAEcDAAAA.Touchmee:BAAANQADCgcIAQAAAA==.',
Tr='Trausti:BAAANQAECgUJCQAAAA==.Treehen:BAABNQAECn8aAAIhAAkKViDCBABVAwAhAAkKViDCBABVAwAAAA==.Trinanah:BAABNQAECn8kAAIUAAkK7BJSJwDtAQAUAAkK7BJSJwDtAQAAAA==.Troltsky:BAAANQADCgQIBAAAAA==.',
Va='Valariann:BAAANQADCggICAABNQAECgkJLgAeAOsXAA==.Valeriux:BAAANQADCgUJAwAAAA==.Valgal:BAAANQAECgYIBwAAAA==.Valiraste:BAABNQAECn8iAAIPAAkKVBSxSAB1AgAPAAkKVBSxSAB1AgABNQAFFAEIAQAcAAAAAA==.Valor:BAAANQAECgEIAQABNQAECggIIwADALYeAA==.Vapor:BAAANQADCgQIBAAAAA==.Varalina:BAAANQAECgQJBgAAAA==.',
Vi='Viital:BAAANQADCgYIBgAAAA==.Vischar:BAAANQADCgUIBwAAAA==.',
Vo='Voidmommy:BAAANQABCgEIAQAAAA==.',
Wa='Washbeans:BAACNQAFFH8GAAMjAAMKbBgqDgDvAAAjAAMKbBgqDgDvAAASAAEK6wmNIABIAAA1AAQKfycAAyMACQpyHqkgAIQCACMACQpyHqkgAIQCABIAAgoWGiCvAJAAAAAA.Wayne:BAAANQABCgQIAgAAAA==.',
We='Wef:BAABNQAECn8YAAIGAAgK0wxjjwDnAQAGAAgK0wxjjwDnAQAAAA==.Weledronys:BAAANQADCgUICgAAAA==.',
Wh='Whyse:BAABNQAECn8gAAIMAAcKfQ1m7wCoAQAMAAcKfQ1m7wCoAQAAAA==.',
Wi='Wings:BAABNQAECn8bAAILAAkKPxWkDACWAgALAAkKPxWkDACWAgAAAA==.Wintel:BAAANQADCgYIBwAAAA==.Wizaes:BAAANQAECgEIAQAAAA==.',
Xa='Xanza:BAAANQADCgYIDgAAAA==.',
Ya='Yamzaio:BAAANQADCgUJBwAAAA==.',
Yo='Yo:BAAANQADCgcIDAAAAA==.',
Za='Zancrafter:BAAANQADCgIIAgABNQAFFAMIBgAQAAsXAA==.Zanduwuin:BAACNQAFFH8GAAIQAAMKCxc1DADtAAAQAAMKCxc1DADtAAA1AAQKfykAAxAACQr5HbAQAOgCABAACQr5HbAQAOgCABYAAwqfC4QnAHUAAAAA.Zanvoker:BAABNQAECn8nAAQiAAkKNRfdBwAjAgAiAAkK1RbdBwAjAgALAAYKThEwHwBeAQAKAAcKJQmMKgBWAQABNQAFFAMIBgAQAAsXAA==.Zargar:BAAANQAECgUIEAAAAA==.',
Zo='Zorttok:BAAANQAECgEIAQAAAA==.',
Zu='Zukkario:BAACNQAFFH8UAAMJAAYKXSMeBwBIAgAJAAYKBCMeBwBIAgAkAAQKxR/9AAB6AQA1AAQKfyQAAwkACQpjJjQXAFsDAAkACQo9JjQXAFsDACQAAQr3JoMmAHUAAAAA.',
Zy='Zyp:BAAANQAECgEIAQAAAA==.',
['Âx']='Âxel:BAABNQAECn8jAAIgAAgKZSRSEgA0AwAgAAgKZSRSEgA0AwAAAA==.',
['År']='Årgon:BAABNQAECn8qAAISAAkKIxy+IwCxAgASAAkKIxy+IwCxAgAAAA==.',
['ße']='ßen:BAAANQADCgUIBQAAAA==.',
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
