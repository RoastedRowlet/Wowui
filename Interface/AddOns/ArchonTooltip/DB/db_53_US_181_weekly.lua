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

local lookup = {'Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Restoration','Paladin-Retribution','Warrior-Arms','Priest-Holy','Hunter-BeastMastery','Unknown-Unknown','Monk-Windwalker','DeathKnight-Blood','Warrior-Fury','Druid-Restoration','Evoker-Preservation','Rogue-Assassination','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Monk-Brewmaster','Priest-Shadow','DemonHunter-Havoc','Shaman-Elemental','Druid-Balance','Mage-Frost','Hunter-Survival','DemonHunter-Devourer','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='Runetotem',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abert:BAAANQAECgUIBgAAAA==.',
Ac='Acts:BAAANQADCgYICgAAAA==.',
Ad='Adalinda:BAAANQADCgQIBAABNQAECgkJIQABAO0aAA==.Adrelorà:BAAANQADCgcIDQAAAA==.',
Ae='Aerähn:BAAANQABCggIJgAAAA==.',
Ag='Agathahaknes:BAAANQADCgEIAQAAAA==.Agnor:BAABNQAECn8gAAICAAcKrBYsTADhAQACAAcKrBYsTADhAQAAAA==.',
Ai='Aindria:BAAANQADCggICAAAAA==.',
Al='Alatir:BAAANQADCgUICAAAAA==.',
Am='Ameri:BAAANQAECgEIAQABNQAFFAYIDwADAHEaAA==.Ammeka:BAAANQABCggIEgAAAA==.',
An='Anahline:BAAANQAECgEIAQAAAA==.Andre:BAAANQAECgUICQABNQAFFAQICAAEAA4KAA==.Anjaini:BAAANQADCgEJAQAAAA==.Antibubble:BAABNQAECn8tAAIDAAkKrSG9EwDsAgADAAkKrSG9EwDsAgAAAA==.Anwal:BAABNQAECn8hAAMBAAkK7Rr2KgC6AgABAAkK7Rr2KgC6AgAFAAcKRQ5r4ABUAQAAAA==.',
Ar='Arceilth:BAAANQADCgcIDAAAAA==.Argus:BAAANQADCgIIAgAAAA==.Arissidis:BAAANQADCgYIBgAAAA==.Arithfury:BAABNQAECn8fAAIGAAgK+xgRagBPAgAGAAgK+xgRagBPAgAAAA==.Arkaius:BAAANQADCggICgAAAA==.Articuno:BAAANQADCgUICQAAAA==.Arwenloa:BAAANQAECgEIAQABNQAECgcIFAAEAKAOAA==.',
As='Ashwynn:BAAANQAECgUIBwAAAA==.Aske:BAAANQADCgcIDwAAAA==.',
At='Atalnoa:BAAANQADCgYICAAAAA==.',
Au='Aura:BAAANQADCgIIAgABNQAECgcIGgAHALEVAA==.',
Az='Azuresun:BAAANQAECgUIEQAAAA==.',
Ba='Ballak:BAAANQAECgIIAwAAAA==.Bambeeno:BAAANQABCgYIBgAAAA==.Barnardo:BAAANQABCgIJAgAAAA==.Bassmasta:BAABNQAECn8hAAIIAAkKaCHmGwAnAwAIAAkKaCHmGwAnAwAAAA==.Baston:BAAANQADCgQIBAAAAA==.',
Be='Beatin:BAAANQAECgQICAAAAA==.Bentö:BAAANQADCgcIBwAAAA==.Beny:BAAANQAECgYIEQAAAA==.',
Bl='Blackskillz:BAAANQAECgMIBwABNQAECggIIgAGAJ8TAA==.Bloodstorm:BAAANQAECgEIAwAAAA==.Bloopydoo:BAAANQAECgQIBgAAAA==.',
Bo='Boiorix:BAAANQADCgEIAQABNQAECgQIBwAJAAAAAA==.Borim:BAAANQAECgQIBgAAAA==.',
Br='Braincell:BAAANQAECgEIAQAAAA==.Brassidas:BAAANQAECgEIAQAAAA==.Brbpoopin:BAAANQADCgMIAwAAAA==.Bromancehomo:BAAANQADCgUIBgAAAA==.Brotems:BAAANQAECgEIAQAAAA==.Bruwdfyre:BAAANQAECggIEwAAAA==.',
Bu='Bubbleshield:BAAANQADCgcIBwAAAA==.',
Ca='Castani:BAAANQAECgYICgAAAA==.',
Ce='Celestyal:BAAANQAECgQIBwAAAA==.',
Ch='Choshi:BAAANQADCgMIAwABNQAECgQIDQAJAAAAAA==.',
Ci='Cindy:BAAANQAECgQIBAABNQAECggIGAAKAFgYAA==.',
Co='Confidential:BAAANQADCgIIAgAAAA==.Cootpal:BAABNQAECn8uAAIFAAkKIRvyTwCiAgAFAAkKIRvyTwCiAgAAAA==.',
Cr='Crazyloon:BAAANQAECgUIEwAAAA==.',
Cy='Cynawyne:BAAANQAECgEIAQAAAA==.Cynthea:BAAANQABCgQIBwAAAA==.',
['Cö']='Cörinthian:BAAANQADCgEIAQAAAA==.',
Da='Daddybod:BAABNQAECn8XAAMDAAkKLQwRRwCcAQADAAgKLQwRRwCcAQALAAMKhgYvrgBsAAAAAA==.Dalasaursrex:BAABNQAECn8kAAMGAAkKsRsCTwCZAgAGAAkKsRsCTwCZAgAMAAEKAAAZOQAhAAAAAA==.Dangerfiëld:BAAANQAECgEIAwAAAA==.Dawnwell:BAAANQADCgYICgAAAA==.',
De='Deadfisch:BAAANQADCgQIBAABNQADCggIGQAJAAAAAA==.Deathknig:BAAANQADCggICAAAAA==.Demious:BAABNQAECn8UAAIIAAcK6RHLjQDqAQAIAAcK6RHLjQDqAQAAAA==.Demmu:BAAANQAECgEIAQAAAA==.Demonfister:BAAANQAECgYICAAAAA==.Demonkiller:BAAANQAECgEIAwAAAA==.Desorion:BAAANQAECgEIBAAAAA==.Dethstriker:BAAANQAECgcIEwAAAA==.Dethwyrm:BAAANQABCgIIAgAAAA==.Devolu:BAAANQAECgEIAQAAAA==.',
Di='Didi:BAAANQADCggIAQAAAA==.Dilfzdormu:BAAANQADCgYIBgAAAA==.Dindaratwo:BAABNQAECn8fAAINAAgKdQnXMwB3AQANAAgKdQnXMwB3AQAAAA==.',
Dj='Djunglebook:BAAANQAECgUIBQAAAA==.',
Do='Dokta:BAAANQAECgUIDAAAAA==.Dontula:BAAANQAECgIIAgAAAA==.',
Dr='Drathal:BAAANQAECgQIBQAAAA==.Druaa:BAAANQADCgQIBAABNQAECgQIDQAJAAAAAA==.',
Du='Dumolin:BAAANQAECgEIAQAAAA==.',
Ec='Eclïpse:BAAANQAECgEIAQAAAA==.',
Ed='Eddiedean:BAAANQAECgcIEQAAAA==.Edric:BAAANQADCgcIDAAAAA==.',
El='Electolytic:BAAANQAECgQIBAAAAA==.Elfgonewild:BAAANQADCgUIBgAAAA==.Ellessra:BAAANQADCgcIDwAAAA==.Elma:BAAANQADCggICAAAAA==.Elnegrouno:BAABNQAECn8iAAIGAAgKnxNieQAoAgAGAAgKnxNieQAoAgAAAA==.',
Er='Eragone:BAAANQAECgEIAQAAAA==.Eragora:BAAANQADCgQIAwAAAA==.Errdrick:BAAANQAECgQIBwAAAA==.',
Et='Etoro:BAAANQADCgIIAgAAAA==.',
Fa='Faeyri:BAAANQADCgcIDwAAAA==.Fawntastic:BAAANQADCggIEAAAAA==.',
Fe='Feeri:BAAANQAECgEJAQAAAA==.Feyrbrand:BAABNQAECn8cAAIOAAgKuw3WIgCvAQAOAAgKuw3WIgCvAQAAAA==.',
Fi='Fischticuffs:BAAANQADCggIGQAAAA==.',
Fo='Fourid:BAAANQAECggIEAAAAA==.',
Fr='Frostfirer:BAAANQADCgIIAgAAAA==.',
Ga='Gallyn:BAABNQAECn8pAAIPAAkKjxmsGACzAgAPAAkKjxmsGACzAgAAAA==.',
Gi='Giizmo:BAAANQADCgYIBgAAAA==.Giled:BAAANQADCggICAAAAA==.',
Gl='Glacierrock:BAAANQADCgMIAwAAAA==.Gloria:BAABNQAECn8bAAIEAAgKgxagWwD5AQAEAAgKgxagWwD5AQAAAA==.Glyndor:BAAANQADCgYIBgAAAA==.',
Gr='Grogar:BAAANQAECgEIAQAAAA==.',
Gu='Gunslinger:BAAANQAECgUIDwAAAA==.',
Ha='Halenicion:BAAANQAECgIIAQAAAA==.Hankthetank:BAAANQADCgYIBgAAAA==.',
Hi='Hippoltyos:BAABNQAECn8gAAIHAAgKIBAtcgDCAQAHAAgKIBAtcgDCAQAAAA==.',
Ho='Honestlee:BAAANQADCgMIAwAAAA==.Honourablee:BAAANQADCgQIBAAAAA==.',
Hu='Hunkacrap:BAAANQABCgIIAgAAAA==.Huntaa:BAAANQAECgEIAQABNQAECgQIDQAJAAAAAA==.Huntardiness:BAAANQAECggIEQAAAA==.',
Hy='Hymnals:BAACNQAFFH8KAAMMAAQKxiBnAQAsAQAMAAMKjCNnAQAsAQAGAAMKRRmXIgDkAAA1AAQKfxcAAwYACQrNJfEkACMDAAYACQqHJPEkACMDAAwAAgp2JuUbAOcAAAAA.',
Ic='Icealia:BAAANQAECgEIAQABNQAECgkJJAANANwSAA==.',
Is='Isus:BAAANQAECgMIBgAAAA==.',
Iv='Ive:BAABNQAECn81AAQQAAkKAyLpGAAhAwAQAAgKByLpGAAhAwARAAQK5SL3DQBzAQASAAMKGyBvLQAWAQAAAA==.',
Ja='Jadeflower:BAAANQADCgcIBwAAAA==.Jarnunvosk:BAAANQADCgMIAwAAAA==.Jasmindinn:BAAANQAECgYIBwAAAA==.Jayber:BAAANQAECgEIAQAAAA==.',
Ji='Jimbearlushi:BAACNQAFFH8LAAIKAAQKOheiCQAuAQAKAAQKOheiCQAuAQA1AAQKfyEAAwoACQrjGk8fADICAAoACQqmGU8fADICABMABwr9FUcVAIwBAAAA.',
Ju='Judelly:BAAANQAECgIIAgAAAA==.Juicebox:BAAANQAECgYIBwAAAA==.Justjakk:BAAANQADCgEIAgAAAA==.',
Ka='Kabball:BAAANQAECgEIAQAAAA==.Kabr:BAAANQADCgYICQAAAA==.Kalez:BAAANQAECgEIAQAAAA==.Kalibar:BAAANQAECgMIBgAAAA==.Kamakaz:BAAANQAECggIEgAAAA==.Kamasdruid:BAAANQAECggIBwAAAA==.Kamasmage:BAAANQAECgYIBQAAAA==.Kandi:BAAANQADCgMIAwAAAA==.Kaviryon:BAAANQADCgIIBAAAAA==.Kaywhy:BAABNQAECn8oAAIUAAgKDx1PEQDkAgAUAAgKDx1PEQDkAgAAAA==.',
Ki='Kichack:BAAANQADCgMJBQAAAA==.Kimchie:BAAANQADCgMIAwAAAA==.Kinqanduin:BAAANQADCggIFAAAAA==.',
Kj='Kjdh:BAABNQAECn8wAAIVAAkKqCBnCwBQAwAVAAkKqCBnCwBQAwAAAA==.',
Kn='Knuckles:BAAANQAECgQICQAAAA==.',
Ko='Koanu:BAAANQAECgEIAQAAAA==.Kob:BAABNQAECn8VAAQQAAcKVwjXugBTAQAQAAcKAAjXugBTAQARAAEKTAirLwA1AAASAAEKNgEyiAAaAAAAAA==.Kogun:BAAANQAECgEIAQAAAA==.Kozalth:BAAANQADCgcIFwAAAA==.',
Kt='Ktom:BAABNQAECn8oAAIWAAkKBiAqEwBWAwAWAAkKBiAqEwBWAwAAAA==.',
Ku='Kurayami:BAAANQAECgQIBAAAAA==.',
La='Lancelot:BAAANQAECgIIAgAAAA==.Lawndown:BAAANQADCgIIAgAAAA==.Lawnsifer:BAAANQADCgMIAwAAAA==.',
Li='Litchlord:BAAANQADCgYIBgAAAA==.Liv:BAAANQAECgUIBwAAAA==.',
Lo='Loax:BAAANQADCgUJBQAAAA==.Loek:BAAANQADCgUIBQAAAA==.Longpong:BAAANQAECgQICgAAAA==.Louhi:BAAANQAECgEIAgAAAA==.Loveshaq:BAAANQAECgUIBgAAAA==.',
Lu='Lunar:BAABNQAECn8dAAIXAAkKPhd9JgCcAgAXAAkKPhd9JgCcAgAAAA==.',
Ly='Lystat:BAAANQAECgQIBAAAAA==.',
Ma='Magra:BAABNQAECn8VAAIYAAcKxw7uEACVAQAYAAcKxw7uEACVAQAAAA==.Magêyalook:BAAANQADCgMIAwABNQAECgYIEgAJAAAAAA==.Malogg:BAAANQABCggIEwAAAA==.Manzz:BAAANQADCggICAAAAA==.Mariahscary:BAABNQAECn8iAAIQAAcKwA8zlACvAQAQAAcKwA8zlACvAQAAAA==.Marisol:BAAANQAECgEIAQAAAA==.Maskimxul:BAAANQABCgEIAQAAAA==.Mattob:BAAANQADCgYIDgAAAA==.Maznificent:BAAANQADCgUIEgAAAA==.',
Me='Meandmypal:BAACNQAFFH8PAAIZAAYK9yBCAABAAgAZAAYK9yBCAABAAgA1AAQKfycAAhkACQr9JCQBAHIDABkACQr9JCQBAHIDAAAA.Meatspinz:BAAANQADCggIDQAAAA==.Meesodead:BAAANQAECgYIDQAAAA==.Mello:BAAANQAECgcIEwAAAA==.Mesteris:BAAANQADCggICAAAAA==.Metalhead:BAAANQADCgYIBgAAAA==.',
Mi='Midiane:BAAANQAECgIIAwAAAA==.Miney:BAAANQAECgEIAQAAAA==.Mirba:BAAANQADCgcIDwAAAA==.',
Mk='Mknight:BAAANQAECgMIDQAAAA==.',
Mo='Moments:BAAANQADCggICAAAAA==.Monsterdeath:BAAANQAECgIJAgAAAA==.',
['Må']='Måladroit:BAAANQADCgIIAgAAAA==.',
Na='Nareík:BAABNQAECn8hAAMVAAkK8RCPOgDcAQAVAAgKYhCPOgDcAQAaAAgKCAshNgCNAQAAAA==.Nazarath:BAAANQABCgIIAgAAAA==.',
Ne='Neeru:BAAANQABCgIIAgABNQAECgEIAQAJAAAAAA==.Neriak:BAABNQAECn8jAAIXAAcKJBR9RwDKAQAXAAcKJBR9RwDKAQAAAA==.Newa:BAAANQAECgEIAQAAAA==.',
Ni='Nightwater:BAABNQAECn8kAAMNAAkK3BKsIAAgAgANAAkK3BKsIAAgAgAXAAEKEAWYswAtAAAAAA==.',
Or='Orchop:BAAANQADCgUIBgAAAA==.Orenrim:BAAANQADCgMIAwABNQAECgQIBQAJAAAAAA==.',
Os='Osanyin:BAAANQADCgcIFQABNQAECgIIBAAJAAAAAA==.',
Pa='Paado:BAAANQADCgEIAQAAAA==.Paulterian:BAAANQAECgQIBAAAAA==.',
Pf='Pffthmgcdrgn:BAAANQAECgEIAQAAAA==.',
Ph='Phinehas:BAAANQADCggJCAAAAA==.',
Po='Poldalina:BAAANQADCgcIFQAAAA==.',
Pr='Pr:BAAANQADCgYIBgAAAA==.Priesaa:BAAANQAECgQICAABNQAECgQIDQAJAAAAAA==.',
Pu='Pumplord:BAAANQADCgIIAgAAAA==.',
Qe='Qeynos:BAABNQAECn8VAAMCAAYKvBDocwBEAQACAAYKvBDocwBEAQALAAEKAACr2QAiAAAAAA==.',
Qu='Quazeemoto:BAAANQAECgQICgAAAA==.',
Ra='Raalen:BAAANQABCgUICQAAAA==.Rainknuckles:BAABNQAECn8iAAIBAAkK3hhAMQCeAgABAAkK3hhAMQCeAgAAAA==.Ratrenot:BAAANQAECgEIAgAAAA==.Ravael:BAAANQADCgUIBwAAAA==.Rayshano:BAAANQADCggICAABNQAECgcIDQAJAAAAAA==.',
Re='Resia:BAAANQADCggIEAAAAA==.Retailsucks:BAAANQADCgcIEAAAAA==.Revocsid:BAAANQADCgYIDgAAAA==.Rezza:BAAANQADCgUIBgAAAA==.',
Ri='Ridethewave:BAAANQADCgIIAgAAAA==.',
Ro='Rottingtree:BAAANQAECgYICwAAAA==.',
Ru='Rustynails:BAABNQAECn8gAAIbAAkKjxbdBACxAgAbAAkKjxbdBACxAgAAAA==.',
Ry='Ryvalz:BAAANQAECgcIBwAAAA==.',
Sa='Sacrafischal:BAAANQADCgcIBwAAAA==.Sazzul:BAAANQAECgMIBQAAAA==.',
Sc='Scynx:BAAANQAECgEIBQAAAA==.',
Se='Seaka:BAABNQAECn8sAAMNAAkK0BafGAB1AgANAAkK0BafGAB1AgAXAAMKFhH2jwCRAAAAAA==.Sernix:BAAANQAECgMIDgAAAA==.',
Sh='Shadegrim:BAAANQAECgEIAgAAAA==.Shamanic:BAAANQADCggIHAAAAA==.Shamany:BAAANQAECgQIDQAAAA==.Shamnick:BAAANQAECgYIBgAAAA==.Shariya:BAAANQADCgQIBAAAAA==.Shiftyfans:BAAANQADCgcIFQAAAA==.Shivon:BAAANQAECgQIBQAAAA==.',
Sl='Slamin:BAAANQADCgYIBwAAAA==.',
Sn='Snowaxe:BAAANQADCgIIAgAAAA==.Snowwind:BAAANQAECgIIBAAAAA==.',
So='Solthea:BAAANQABCgMIBAAAAA==.Sonar:BAABNQAECn8tAAIIAAkKAx8aJwD5AgAIAAkKAx8aJwD5AgAAAA==.Sonasham:BAAANQADCgcIFQAAAA==.Sonnybear:BAAANQADCgcIFQAAAA==.Soulhatcher:BAAANQADCgEIAQAAAA==.Soulslinger:BAAANQABCgQIBQAAAA==.Soxs:BAAANQAECgUICgAAAA==.',
Sp='Spawnofdeath:BAAANQAECgIIBQAAAA==.Spectrelok:BAAANQAECgMIBwAAAA==.Spectrepunch:BAAANQAECgUICQAAAA==.',
St='Steàlthy:BAAANQAECgYIEgAAAA==.Stickychikn:BAAANQADCgYIBgAAAA==.Stompygnome:BAAANQAECgQICAAAAA==.',
Sy='Syrila:BAAANQAECgUIDQAAAA==.',
Ta='Tartanus:BAAANQADCgQIBAAAAA==.Tayzetv:BAAANQADCgcIBwABNQAECgQICAAJAAAAAA==.',
Te='Teramiah:BAAANQADCgMIAwAAAA==.',
Th='Thebe:BAAANQAECgEIAQAAAA==.Thorall:BAAANQADCgQIAwAAAA==.Thylight:BAAANQADCgIIAgAAAA==.',
Ti='Tippy:BAACNQAFFH8PAAIDAAYKcRq6AwDlAQADAAYKcRq6AwDlAQA1AAQKfygAAgMACQp+JLURAP0CAAMACQp+JLURAP0CAAAA.',
To='Tombstone:BAABNQAECn8oAAIPAAkKkxj/GQCpAgAPAAkKkxj/GQCpAgAAAA==.Toowongfoo:BAACNQAFFH8PAAIKAAUKqQ9CCABeAQAKAAUKqQ9CCABeAQA1AAQKfykAAgoACQoEHh4VAKgCAAoACQoEHh4VAKgCAAAA.',
Tu='Tunechi:BAAANQAECgEIAQAAAA==.',
Ug='Uglysham:BAABNQAECn8YAAIEAAYKhhm4cgCwAQAEAAYKhhm4cgCwAQAAAA==.',
Um='Umbranecros:BAAANQADCgEIAQAAAA==.',
Un='Underdog:BAAANQAECgYIDQAAAA==.',
Us='Usui:BAAANQADCgUIBQAAAA==.',
Va='Vaerie:BAAANQADCgYIBgAAAA==.Vagindivin:BAAANQAECggIEQAAAA==.Valyteil:BAAANQAECgIIAwAAAA==.',
Ve='Venngance:BAAANQADCgYIBgAAAA==.',
Vi='Virus:BAAANQAECgQICQAAAA==.',
Vo='Voidkity:BAAANQAECgQIBwAAAA==.',
Wa='Wakax:BAAANQAECgQIDAAAAA==.Walberson:BAAANQADCgcIBwAAAA==.Walkleydk:BAAANQAECggICAAAAA==.Warfield:BAAANQAECgUIEwAAAA==.Warmoose:BAAANQAECgEIAQABNQAECggIEQAJAAAAAA==.',
We='Weediez:BAAANQADCgYJCAAAAA==.',
Wi='Wildfrost:BAABNQAECn8XAAIcAAQKHQKkjwGgAAAcAAQKHQKkjwGgAAAAAA==.Willienelson:BAAANQAECggIDgAAAA==.',
Wr='Wrathsome:BAAANQADCgcIDwAAAA==.',
Wy='Wyrmboy:BAAANQABCgQIBQAAAA==.Wyterd:BAAANQAECgYIEgAAAA==.',
Xa='Xaernach:BAAANQADCgQIBgAAAA==.Xalome:BAAANQAECgEIAQAAAA==.',
Xo='Xoxo:BAAANQAFFAEIAQAAAA==.',
Za='Zarkus:BAAANQAECgEIAQAAAA==.Zaruknark:BAAANQAECgUICwAAAA==.',
['Àl']='Àlexia:BAAANQAECgIJBAAAAA==.',
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
