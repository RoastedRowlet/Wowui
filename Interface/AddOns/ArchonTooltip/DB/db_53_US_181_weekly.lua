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

local lookup = {'Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Restoration','Paladin-Retribution','Warrior-Arms','Unknown-Unknown','Hunter-BeastMastery','Warrior-Fury','Druid-Restoration','Rogue-Assassination','Priest-Holy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Monk-Windwalker','Monk-Brewmaster','Priest-Shadow','DemonHunter-Havoc','Shaman-Elemental','Druid-Balance','Hunter-Survival','DemonHunter-Devourer','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='Runetotem',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abert:BAAANQAECgUIBgAAAA==.',
Ac='Acts:BAAANQADCgYICgAAAA==.',
Ad='Adalinda:BAAANQADCgQIBAABNQAECgkJHgABAO0aAA==.Adrelorà:BAAANQADCgcIDQAAAA==.',
Ae='Aerähn:BAAANQABCggIHgAAAA==.',
Ag='Agathahaknes:BAAANQADCgEIAQAAAA==.Agnor:BAABNQAECoEXAAICAAUKJRj0ZgBQAQACAAUKJRj0ZgBQAQAAAA==.',
Ai='Aindria:BAAANQADCggICAAAAA==.',
Al='Alatir:BAAANQADCgUICAAAAA==.',
Am='Ameri:BAAANQAECgEIAQABNQAFFAYIDwADAPIYAA==.Ammeka:BAAANQABCggIEAAAAA==.',
An='Anahline:BAAANQAECgEIAQAAAA==.Andre:BAAANQAECgUIBgABNQAECgkJIgAEAAMeAA==.Anjaini:BAAANQADCgEJAQAAAA==.Antibubble:BAABNQAECoEmAAIDAAkKIB9ZEgDbAgADAAkKIB9ZEgDbAgAAAA==.Anwal:BAABNQAECoEeAAMBAAkK7RpWJADCAgABAAkK7RpWJADCAgAFAAcK5w3OwgBdAQAAAA==.',
Ar='Arceilth:BAAANQADCgcIDAAAAA==.Argus:BAAANQADCgIIAgAAAA==.Arissidis:BAAANQADCgYIBgAAAA==.Arithfury:BAABNQAECoEcAAIGAAcKbhngdwANAgAGAAcKbhngdwANAgAAAA==.Arkaius:BAAANQADCggICgAAAA==.Articuno:BAAANQADCgUICQAAAA==.',
As='Ashwynn:BAAANQAECgUIBQAAAA==.Aske:BAAANQADCgcIDwAAAA==.',
At='Atalnoa:BAAANQADCgYICAAAAA==.',
Au='Aura:BAAANQADCgIIAgABNQAECgYIEQAHAAAAAA==.',
Az='Azuresun:BAAANQAECgQIDAAAAA==.',
Ba='Ballak:BAAANQAECgIIAgAAAA==.Bambeeno:BAAANQABCgYIBgAAAA==.Barnardo:BAAANQABCgIJAgAAAA==.Bassmasta:BAABNQAECoEbAAIIAAkK9R+7EgA+AwAIAAkK9R+7EgA+AwAAAA==.Baston:BAAANQADCgQIBAAAAA==.',
Be='Beatin:BAAANQAECgQIBwAAAA==.Bentö:BAAANQADCgcJBwAAAA==.Beny:BAAANQAECgYIDAAAAA==.',
Bl='Blackskillz:BAAANQAECgMIAwABNQAECggIHAAGALUVAA==.Bloodstorm:BAAANQAECgEIAQAAAA==.Bloopydoo:BAAANQAECgQIBAAAAA==.',
Bo='Boiorix:BAAANQADCgEIAQABNQAECgQIBQAHAAAAAA==.Borim:BAAANQAECgQIBgAAAA==.',
Br='Brassidas:BAAANQAECgEIAQAAAA==.Brbpoopin:BAAANQADCgMIAwAAAA==.Bromancehomo:BAAANQADCgUIBgAAAA==.Bruwdfyre:BAAANQAECgcIDwAAAA==.',
Ca='Castani:BAAANQAECgUICQAAAA==.',
Ce='Celestyal:BAAANQAECgQIBQAAAA==.',
Ch='Choshi:BAAANQADCgMIAwABNQAECgQIBgAHAAAAAA==.',
Co='Confidential:BAAANQADCgIIAgAAAA==.Cootpal:BAABNQAECoEoAAIFAAkKshqKRQCfAgAFAAkKshqKRQCfAgAAAA==.',
Cr='Crazyloon:BAAANQAECgUIEAAAAA==.',
Cy='Cynawyne:BAAANQABCgMIAwABNQADCgcIFQAHAAAAAA==.Cynthea:BAAANQABCgQIBwAAAA==.',
['Cö']='Cörinthian:BAAANQADCgEIAQAAAA==.',
Da='Daddybod:BAAANQAECgYIDgAAAA==.Dalasaursrex:BAABNQAECoEjAAMGAAgKMhy6TwB/AgAGAAgKMhy6TwB/AgAJAAEKqgMNMwAhAAAAAA==.Dangerfiëld:BAAANQAECgEIAQAAAA==.Dawnwell:BAAANQADCgYICgAAAA==.',
De='Deadfisch:BAAANQADCgQIBAABNQADCggIGQAHAAAAAA==.Deathknig:BAAANQADCggICAAAAA==.Demious:BAAANQAECgYIEQAAAA==.Demonfister:BAAANQAECgYICAAAAA==.Demonkiller:BAAANQAECgEJAQAAAA==.Desorion:BAAANQABCgIIAgAAAA==.Dethstriker:BAAANQAECgYIDAAAAA==.Dethwyrm:BAAANQABCgIIAgAAAA==.Devolu:BAAANQADCgUICAAAAA==.',
Di='Didi:BAAANQADCggIAQAAAA==.Dilfzdormu:BAAANQADCgYIBgAAAA==.Dindaratwo:BAABNQAECoEcAAIKAAcKLAqRMQBaAQAKAAcKLAqRMQBaAQAAAA==.',
Dj='Djunglebook:BAAANQADCggIFgAAAA==.',
Do='Dokta:BAAANQAECgUICAAAAA==.Dontula:BAAANQAECgIIAgAAAA==.',
Dr='Drathal:BAAANQAECgQIBAAAAA==.Druaa:BAAANQADCgQIBAABNQAECgQIBgAHAAAAAA==.',
Ec='Eclïpse:BAAANQABCgIIAgAAAA==.',
Ed='Eddiedean:BAAANQAECgYIDgAAAA==.Edric:BAAANQADCgUIBQAAAA==.',
El='Electolytic:BAAANQAECgQIAwAAAA==.Elfgonewild:BAAANQADCgUIBgAAAA==.Ellessra:BAAANQADCgcIDwAAAA==.Elma:BAAANQADCggICAAAAA==.Elnegrouno:BAABNQAECoEcAAIGAAgKtRVlZgA9AgAGAAgKtRVlZgA9AgAAAA==.',
Er='Eragone:BAAANQADCggICAAAAA==.Errdrick:BAAANQAECgQIBAAAAA==.',
Et='Etoro:BAAANQADCgIIAgAAAA==.',
Fa='Faeyri:BAAANQADCgcIDwAAAA==.Fawntastic:BAAANQADCggIEAAAAA==.',
Fe='Feeri:BAAANQAECgEJAQAAAA==.Feyrbrand:BAAANQAECgcIEgABNQAECgEIAQAHAAAAAA==.',
Fi='Fischticuffs:BAAANQADCggIGQAAAA==.',
Fo='Fourid:BAAANQAECgcIDQAAAA==.',
Fr='Frostfirer:BAAANQADCgIIAgAAAA==.',
Ga='Gallyn:BAABNQAECoEiAAILAAkKPRnEFwCXAgALAAkKPRnEFwCXAgAAAA==.',
Gi='Giizmo:BAAANQADCgYIBgAAAA==.Giled:BAAANQADCggICAAAAA==.',
Gl='Glacierrock:BAAANQADCgMIAwAAAA==.Gloria:BAABNQAECoEZAAIEAAgKIxSPWwDOAQAEAAgKIxSPWwDOAQAAAA==.Glyndor:BAAANQADCgYIBgAAAA==.',
Gr='Grogar:BAAANQADCgIIAgAAAA==.',
Gu='Gunslinger:BAAANQAECgUIDQAAAA==.',
Ha='Halenicion:BAAANQAECgIIAQAAAA==.Hankthetank:BAAANQADCgYIBgAAAA==.',
Hi='Hippoltyos:BAABNQAECoEZAAIMAAcKdhG8cACTAQAMAAcKdhG8cACTAQAAAA==.',
Ho='Honestlee:BAAANQADCgMIAwAAAA==.Honourablee:BAAANQADCgQIBAAAAA==.',
Hu='Hunkacrap:BAAANQABCgIIAgAAAA==.Huntaa:BAAANQADCggICAABNQAECgQIBgAHAAAAAA==.Huntardiness:BAAANQAECgYIDAAAAA==.',
Hy='Hymnals:BAACNQAFFIEHAAMJAAQKmRseAQAkAQAJAAMKuBseAQAkAQAGAAMKRRmoGwDsAAA1AAQKgRUAAwYACQokJUsaAEIDAAYACQp6JEsaAEIDAAkAAgr+JCMaAN0AAAAA.',
Ic='Icealia:BAAANQAECgEIAQABNQAECgkJIQAKANsSAA==.',
Is='Isus:BAAANQAECgMIAwAAAA==.',
Iv='Ive:BAABNQAECoErAAQNAAgKyh41PgB8AgANAAcKWB41PgB8AgAOAAQK1x/ODABnAQAPAAMKGyACKwAZAQAAAA==.',
Ja='Jadeflower:BAAANQADCgcIBwAAAA==.Jarnunvosk:BAAANQADCgMIAwAAAA==.Jasmindinn:BAAANQADCgYIDAAAAA==.Jayber:BAAANQAECgEIAQAAAA==.',
Ji='Jimbearlushi:BAACNQAFFIEIAAIQAAQK3BD6BwAqAQAQAAQK3BD6BwAqAQA1AAQKgR8AAxAACQqgGngbADQCABAACQqoFngbADQCABEABwp9F+4SAJYBAAAA.',
Ju='Judelly:BAAANQADCgMIAwAAAA==.Justjakk:BAAANQADCgEIAgAAAA==.',
Ka='Kabball:BAAANQADCgYIBgAAAA==.Kabr:BAAANQADCgYICQAAAA==.Kalez:BAAANQADCgYICQAAAA==.Kalibar:BAAANQAECgIIAwAAAA==.Kamakaz:BAAANQAECgUICQAAAA==.Kamasmage:BAAANQAECgYIBQAAAA==.Kandi:BAAANQADCgMIAwAAAA==.Kaviryon:BAAANQADCgEIAQAAAA==.Kaywhy:BAABNQAECoEfAAISAAgKsRy/EgC3AgASAAgKsRy/EgC3AgAAAA==.',
Ki='Kichack:BAAANQADCgMJBQAAAA==.Kimchie:BAAANQADCgMIAwAAAA==.Kinqanduin:BAAANQADCggIFAAAAA==.',
Kj='Kjdh:BAABNQAECoEmAAITAAkKFB/DEAABAwATAAkKFB/DEAABAwAAAA==.',
Kn='Knuckles:BAAANQAECgMIBQAAAA==.',
Ko='Koanu:BAAANQADCgQIBAAAAA==.Kob:BAAANQAECggIDgAAAA==.Kogun:BAAANQADCggIDwAAAA==.Kozalth:BAAANQADCgcIFwAAAA==.',
Kt='Ktom:BAABNQAECoEhAAIUAAkKiR6CGgATAwAUAAkKiR6CGgATAwAAAA==.',
Ku='Kurayami:BAAANQAECgQIBAAAAA==.',
La='Lancelot:BAAANQAECgIIAgAAAA==.Lawndown:BAAANQADCgIIAgAAAA==.Lawnsifer:BAAANQADCgMIAwAAAA==.',
Li='Litchlord:BAAANQADCgYIBgAAAA==.Liv:BAAANQAECgUIBwAAAA==.',
Lo='Loax:BAAANQADCgUJBQAAAA==.Loek:BAAANQADCgUIBQAAAA==.Longpong:BAAANQAECgQICgAAAA==.Louhi:BAAANQAECgEIAQAAAA==.Loveshaq:BAAANQAECgUIBQAAAA==.',
Lu='Lunar:BAABNQAECoEYAAIVAAgKuBfcMAA1AgAVAAgKuBfcMAA1AgAAAA==.',
Ly='Lystat:BAAANQADCgQIBAAAAA==.',
Ma='Magra:BAAANQAECgUICgAAAA==.Magêyalook:BAAANQADCgMIAwABNQAECgYIEAAHAAAAAA==.Malogg:BAAANQABCggIEQAAAA==.Mariahscary:BAABNQAECoEcAAINAAcKGxAbiACkAQANAAcKGxAbiACkAQAAAA==.Marisol:BAAANQADCgYICwAAAA==.Maskimxul:BAAANQABCgEIAQAAAA==.Mattob:BAAANQADCgYIDgAAAA==.Maznificent:BAAANQADCgUIDgAAAA==.',
Me='Meandmypal:BAACNQAFFIELAAIWAAUKRBh0AADEAQAWAAUKRBh0AADEAQA1AAQKgSQAAhYACQrKJP0AAHYDABYACQrKJP0AAHYDAAAA.Meatspinz:BAAANQADCggIDQAAAA==.Meesodead:BAAANQAECgUIDAAAAA==.Mello:BAAANQAECgcIEQAAAA==.Mesteris:BAAANQADCggICAAAAA==.Metalhead:BAAANQADCgYIBgAAAA==.',
Mi='Midiane:BAAANQAECgIIAgAAAA==.Mirba:BAAANQADCgcIDwAAAA==.',
Mk='Mknight:BAAANQAECgMIBwAAAA==.',
Mo='Moments:BAAANQADCggICAAAAA==.Monsterdeath:BAAANQAECgIJAgAAAA==.',
['Må']='Måladroit:BAAANQADCgIIAgAAAA==.',
Na='Nareík:BAABNQAECoEeAAMTAAgK+xHcOAC3AQATAAcKKhLcOAC3AQAXAAcKNQtFOQBSAQAAAA==.Nazarath:BAAANQABCgIIAgAAAA==.',
Ne='Neriak:BAABNQAECoEeAAIVAAcKORXGQADLAQAVAAcKORXGQADLAQAAAA==.Newa:BAAANQAECgEIAQAAAA==.',
Ni='Nightwater:BAABNQAECoEhAAMKAAkK2xJCGwAzAgAKAAkK2xJCGwAzAgAVAAEKEAU2pAAtAAAAAA==.',
Or='Orchop:BAAANQADCgUIBgAAAA==.Orenrim:BAAANQADCgMIAwABNQAECgQIBAAHAAAAAA==.',
Os='Osanyin:BAAANQADCgYIDgABNQADCgcIEQAHAAAAAA==.',
Pa='Paado:BAAANQADCgEIAQAAAA==.Paulterian:BAAANQAECgQIBAAAAA==.',
Pf='Pffthmgcdrgn:BAAANQADCgQICAAAAA==.',
Ph='Phinehas:BAAANQADCggJCAAAAA==.',
Po='Poldalina:BAAANQADCgYIDgAAAA==.',
Pr='Pr:BAAANQADCgYIBgAAAA==.Priesaa:BAAANQAECgIIAgABNQAECgQIBgAHAAAAAA==.',
Pu='Pumplord:BAAANQADCgIIAgAAAA==.',
Qe='Qeynos:BAAANQAECgUICgAAAA==.',
Qu='Quazeemoto:BAAANQAECgIIAgAAAA==.',
Ra='Raalen:BAAANQABCgUICQAAAA==.Rainknuckles:BAABNQAECoEcAAIBAAgKHRjbOgBcAgABAAgKHRjbOgBcAgAAAA==.Ratrenot:BAAANQADCggIDAAAAA==.Ravael:BAAANQADCgUIBwAAAA==.Rayshano:BAAANQADCggICAABNQAECgcICwAHAAAAAA==.',
Re='Resia:BAAANQADCggIEAAAAA==.Retailsucks:BAAANQADCgUICQAAAA==.Revocsid:BAAANQADCgYIDgAAAA==.Rezza:BAAANQADCgUIBgAAAA==.',
Ri='Ridethewave:BAAANQADCgIIAgAAAA==.',
Ro='Rottingtree:BAAANQAECgQIBQAAAA==.',
Ru='Rustynails:BAABNQAECoEZAAIYAAgKLhaVBgBMAgAYAAgKLhaVBgBMAgAAAA==.',
Ry='Ryvalz:BAAANQAECgIIAgAAAA==.',
Sa='Sazzul:BAAANQAECgMIBQAAAA==.',
Sc='Scynx:BAAANQAECgEIAgAAAA==.',
Se='Seaka:BAABNQAECoElAAMKAAgKixgHGQBNAgAKAAgKixgHGQBNAgAVAAMK7QkqhwCEAAAAAA==.Sernix:BAAANQAECgMIBgAAAA==.',
Sh='Shadegrim:BAAANQAECgEIAQAAAA==.Shamanic:BAAANQADCggIHAAAAA==.Shamany:BAAANQAECgQIBgAAAA==.Shariya:BAAANQADCgQIBAAAAA==.Shiftyfans:BAAANQADCgYIDgAAAA==.',
Sl='Slamin:BAAANQADCgYIBwAAAA==.',
Sn='Snowaxe:BAAANQADCgIIAgAAAA==.Snowwind:BAAANQADCgYIDgAAAA==.',
So='Solthea:BAAANQABCgMIBAAAAA==.Sonar:BAABNQAECoEnAAIIAAkK5R1sGwARAwAIAAkK5R1sGwARAwAAAA==.Sonasham:BAAANQADCgYIDgAAAA==.Sonnybear:BAAANQADCgYIDgAAAA==.Soulhatcher:BAAANQADCgEIAQAAAA==.Soulslinger:BAAANQABCgQIBQAAAA==.Soxs:BAAANQAECgUICQAAAA==.',
Sp='Spawnofdeath:BAAANQAECgIIAwAAAA==.Spectrelok:BAAANQAECgMIBAAAAA==.Spectrepunch:BAAANQAECgUIBgAAAA==.',
St='Steàlthy:BAAANQAECgYIEAAAAA==.Stickychikn:BAAANQADCgYIBgAAAA==.Stompygnome:BAAANQAECgMIBAAAAA==.',
Sy='Syrila:BAAANQAECgQIBgAAAA==.',
Ta='Tartanus:BAAANQADCgQIBAAAAA==.Tayzetv:BAAANQADCgcIBwABNQAECgQIBQAHAAAAAA==.',
Te='Teramiah:BAAANQADCgMIAwAAAA==.',
Th='Thebe:BAAANQADCgYIEwAAAA==.Thorall:BAAANQADCgQIAwAAAA==.Thylight:BAAANQADCgIIAgAAAA==.',
Ti='Tippy:BAACNQAFFIEPAAIDAAYK8hjMAQAEAgADAAYK8hjMAQAEAgA1AAQKgScAAgMACQqBI2kMABsDAAMACQqBI2kMABsDAAAA.',
To='Tombstone:BAABNQAECoEhAAILAAkKZhdmGQCJAgALAAkKZhdmGQCJAgAAAA==.Toowongfoo:BAACNQAFFIEMAAIQAAUKsQrpBgBUAQAQAAUKsQrpBgBUAQA1AAQKgSYAAhAACQoMHXMTAJsCABAACQoMHXMTAJsCAAAA.',
Ug='Uglysham:BAAANQAECgUIEgAAAA==.',
Um='Umbranecros:BAAANQADCgEIAQAAAA==.',
Un='Underdog:BAAANQAECgUIBwAAAA==.',
Us='Usui:BAAANQADCgUIBQAAAA==.',
Va='Vaerie:BAAANQADCgYIBgAAAA==.Vagindivin:BAAANQAECgYIBgAAAA==.Valyteil:BAAANQAECgEIAQAAAA==.',
Ve='Venngance:BAAANQADCgYIBgAAAA==.',
Vi='Virus:BAAANQAECgMIBQAAAA==.',
Vo='Voidkity:BAAANQAECgQIBAAAAA==.',
Wa='Wakax:BAAANQAECgQIBQAAAA==.Walberson:BAAANQADCgcIBwAAAA==.Warfield:BAAANQAECgUIEQAAAA==.Warmoose:BAAANQADCggICAABNQAECgYIBgAHAAAAAA==.',
We='Weediez:BAAANQADCgYJCAAAAA==.',
Wi='Wildfrost:BAABNQAECoEVAAIZAAQKmQLzcwGnAAAZAAQKmQLzcwGnAAAAAA==.Willienelson:BAAANQAECggIDQAAAA==.',
Wr='Wrathsome:BAAANQADCgcIDwAAAA==.',
Wy='Wyrmboy:BAAANQABCgQIBQAAAA==.Wyterd:BAAANQAECgUIDAAAAA==.',
Xa='Xaernach:BAAANQADCgQIBgAAAA==.Xalome:BAAANQADCgUIEwAAAA==.',
Xo='Xoxo:BAAANQAFFAEIAQAAAA==.',
Za='Zarkus:BAAANQADCggIFAAAAA==.Zaruknark:BAAANQAECgUICwAAAA==.',
['Àl']='Àlexia:BAAANQAECgIJAwAAAA==.',
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
