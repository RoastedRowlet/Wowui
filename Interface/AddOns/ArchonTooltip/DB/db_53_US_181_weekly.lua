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

local lookup = {'Paladin-Holy','DeathKnight-Frost','Paladin-Retribution','Unknown-Unknown','Monk-Windwalker','Monk-Brewmaster','Hunter-Survival','Druid-Restoration','Druid-Balance','Hunter-BeastMastery',}
local provider = {region='US',realm='Runetotem',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Acts:BAAANQADCgYICgAAAA==.',
Ad='Adalinda:BAAANQADCgQIBAABNQAECggIGgABAF0aAA==.Adrelorà:BAAANQADCgYIBgAAAA==.',
Ag='Agathahaknes:BAAANQADCgEIAQAAAA==.Agnor:BAAANQAECgMIDQAAAA==.',
Ai='Aindria:BAAANQADCggICAAAAA==.',
Al='Alatir:BAAANQADCgUICAAAAA==.',
Am='Ameri:BAAANQAECgEIAQABNQAFFAQJBgACALAVAA==.',
An='Anjaini:BAAANQADCgEJAQAAAA==.Antibubble:BAAANQAECgcJEgAAAA==.Anwal:BAABNQAECoEaAAMBAAgKXRpFJgBzAgABAAgKXRpFJgBzAgADAAcK5w2HgQB6AQAAAA==.',
Ar='Arceilth:BAAANQADCgcIDAAAAA==.Argus:BAAANQADCgIIAgAAAA==.Arithfury:BAAANQAECgcJEgAAAA==.Arkaius:BAAANQADCggICgAAAA==.Articuno:BAAANQADCgUICQAAAA==.',
As='Ashwynn:BAAANQADCggICAAAAA==.Aske:BAAANQADCgcIDwAAAA==.',
At='Atalnoa:BAAANQADCgYICAAAAA==.',
Au='Aura:BAAANQADCgIIAgABNQAECgQIBgAEAAAAAA==.',
Az='Azuresun:BAAANQAECgQJBAAAAA==.',
Ba='Ballak:BAAANQAECgIIAgAAAA==.Bambeeno:BAAANQABCgYIBgAAAA==.Barnardo:BAAANQABCgIJAgAAAA==.Bassmasta:BAAANQAECgcICQAAAA==.Baston:BAAANQADCgQIBAAAAA==.',
Be='Beatin:BAAANQAECgQIBwAAAA==.Bentö:BAAANQADCgcJBwAAAA==.',
Bl='Bloodstorm:BAAANQAECgEIAQAAAA==.Bloopydoo:BAAANQADCggJAwAAAA==.',
Bo='Boiorix:BAAANQADCgEIAQABNQADCgMIAwAEAAAAAA==.Borim:BAAANQAECgEIAgAAAA==.',
Br='Brassidas:BAAANQAECgEJAQAAAA==.Brbpoopin:BAAANQADCgMIAwAAAA==.Bromancehomo:BAAANQADCgUIBgAAAA==.Bruwdfyre:BAAANQAECgMIBgAAAA==.',
Ce='Celestyal:BAAANQADCgMIAwAAAA==.',
Ch='Choshi:BAAANQADCgMIAwABNQAECgEIAQAEAAAAAA==.',
Co='Confidential:BAAANQADCgIIAgAAAA==.Cootpal:BAABNQAECoEXAAIDAAgKVxqiPABhAgADAAgKVxqiPABhAgAAAA==.',
Cr='Crazyloon:BAAANQAECgUIDAAAAA==.',
Cy='Cynawyne:BAAANQABCgMIAwAAAA==.Cynthea:BAAANQABCgQIBwAAAA==.',
['Cö']='Cörinthian:BAAANQADCgEIAQAAAA==.',
Da='Daddybod:BAAANQAECgIIAwAAAA==.Dalasaursrex:BAAANQAECgcJEgAAAA==.Dangerfiëld:BAAANQAECgEIAQAAAA==.Dawnwell:BAAANQADCgYIBgAAAA==.',
De='Deathknig:BAAANQADCggICAAAAA==.Demious:BAAANQAECgYICwAAAA==.Demonfister:BAAANQAECgYICAAAAA==.Demonkiller:BAAANQAECgEJAQAAAA==.Desorion:BAAANQABCgIIAgAAAA==.Dethstriker:BAAANQAECgQJBgAAAA==.Dethwyrm:BAAANQABCgIIAgAAAA==.Devolu:BAAANQADCgQIBwAAAA==.',
Di='Dilfzdormu:BAAANQADCgYIBgAAAA==.Dindaratwo:BAAANQAECgcJEgAAAA==.',
Dj='Djunglebook:BAAANQADCgYIBgAAAA==.',
Do='Dokta:BAAANQAECgMJAwAAAA==.Dontula:BAAANQAECgIIAgAAAA==.',
Dr='Drathal:BAAANQAECgQIBAAAAA==.Druaa:BAAANQADCgQJBAABNQAECgEIAQAEAAAAAA==.',
Ec='Eclïpse:BAAANQABCgIIAgAAAA==.',
Ed='Eddiedean:BAAANQAECgQJCQAAAA==.Edric:BAAANQADCgUIBQAAAA==.',
El='Electolytic:BAAANQADCggIEwAAAA==.Elfgonewild:BAAANQADCgEIAQAAAA==.Ellessra:BAAANQADCgcIDwAAAA==.Elma:BAAANQADCgYIBgAAAA==.Elnegrouno:BAAANQAECgQIBwAAAA==.',
Er='Eragone:BAAANQADCggICAAAAA==.Errdrick:BAAANQAECgQIBAAAAA==.',
Fa='Faeyri:BAAANQADCgcIDwAAAA==.Fawntastic:BAAANQADCgYJDAAAAA==.',
Fe='Feeri:BAAANQAECgEJAQAAAA==.Feyrbrand:BAAANQAECgQJBgABNQADCggICAAEAAAAAA==.',
Fi='Fischticuffs:BAAANQADCgUICQAAAA==.',
Fo='Fourid:BAAANQAECgUIBAAAAA==.',
Fr='Frostfirer:BAAANQADCgIIAgAAAA==.',
Ga='Gallyn:BAAANQAECgYJEQAAAA==.',
Gi='Giled:BAAANQADCggICAAAAA==.',
Gl='Glacierrock:BAAANQADCgMIAwAAAA==.Gloria:BAAANQAECgYJEAAAAA==.Glyndor:BAAANQADCgYIBgAAAA==.',
Gr='Grogar:BAAANQADCgIIAgAAAA==.',
Gu='Gunslinger:BAAANQAECgUICQAAAA==.',
Ha='Halenicion:BAAANQAECgIIAQAAAA==.Hankthetank:BAAANQADCgYIBgAAAA==.',
Hi='Hippoltyos:BAAANQAECgUICwAAAA==.',
Ho='Honestlee:BAAANQADCgMIAwAAAA==.Honourablee:BAAANQADCgIIAgAAAA==.',
Hu='Hunkacrap:BAAANQABCgIIAgAAAA==.Huntardiness:BAAANQAECgQJBQAAAA==.',
Hy='Hymnals:BAAANQAFFAEIAQAAAA==.',
Is='Isus:BAAANQAECgMIAwAAAA==.',
Iv='Ive:BAAANQAECgYIEQAAAA==.',
Ja='Jadeflower:BAAANQADCgcIBwAAAA==.Jarnunvosk:BAAANQADCgMIAwAAAA==.Jasmindinn:BAAANQADCgYIDAAAAA==.Jayber:BAAANQAECgEIAQAAAA==.',
Ji='Jimbearlushi:BAABNQAECoEbAAMFAAkKmxfUEwA7AgAFAAkKoxPUEwA7AgAGAAcKfRdxDQCyAQAAAA==.',
Ju='Judelly:BAAANQADCgMIAwAAAA==.',
Ka='Kabball:BAAANQADCgYIBgAAAA==.Kabr:BAAANQADCgYICQAAAA==.Kalez:BAAANQADCgYICQAAAA==.Kalibar:BAAANQAECgEJAQAAAA==.Kamakaz:BAAANQAECgUJBQAAAA==.Kandi:BAAANQADCgMIAwAAAA==.Kaywhy:BAAANQAECgYIEAAAAA==.',
Ki='Kichack:BAAANQADCgMJBQAAAA==.Kimchie:BAAANQADCgMIAwAAAA==.Kinqanduin:BAAANQADCgcICAAAAA==.',
Kj='Kjdh:BAAANQAECgUJEAAAAA==.',
Kn='Knuckles:BAAANQAECgEJAQAAAA==.',
Ko='Koanu:BAAANQABCgUIBQAAAA==.Kob:BAAANQAECggJBwAAAA==.Kogun:BAAANQADCgYJBgAAAA==.Kozalth:BAAANQADCgcIFwAAAA==.',
Kt='Ktom:BAAANQAECgcIEQAAAA==.',
Ku='Kurayami:BAAANQAECgQIBAAAAA==.',
La='Lancelot:BAAANQADCgYIDAAAAA==.Lawndown:BAAANQADCgIIAgAAAA==.Lawnsifer:BAAANQADCgMIAwAAAA==.',
Li='Litchlord:BAAANQADCgYIBgAAAA==.Liv:BAAANQAECgIJAgAAAA==.',
Lo='Loax:BAAANQADCgUJBQAAAA==.Loek:BAAANQADCgUIBQAAAA==.Longpong:BAAANQAECgQICgAAAA==.Louhi:BAAANQADCgcIEAAAAA==.Loveshaq:BAAANQAECgUIBQAAAA==.',
Lu='Lunar:BAAANQAECgYIDQAAAA==.',
Ma='Magra:BAAANQAECgUIBgAAAA==.Magêyalook:BAAANQADCgMIAwABNQAECgQJBQAEAAAAAA==.Mariahscary:BAAANQAECgYJEAAAAA==.Maskimxul:BAAANQABCgEIAQAAAA==.Mattob:BAAANQADCgUICAAAAA==.Maznificent:BAAANQADCgQIBAAAAA==.',
Me='Meandmypal:BAABNQAECoEfAAIHAAkKsCR5AACdAwAHAAkKsCR5AACdAwAAAA==.Meatspinz:BAAANQADCggIDQAAAA==.Meesodead:BAAANQAECgUJCQAAAA==.Mello:BAAANQAECgUIDAAAAA==.Mesteris:BAAANQADCggICAAAAA==.Metalhead:BAAANQADCgYIBgAAAA==.',
Mi='Midiane:BAAANQADCgYIDgAAAA==.Mirba:BAAANQADCgcIDwAAAA==.',
Mo='Moments:BAAANQADCggICAAAAA==.Monsterdeath:BAAANQAECgIJAgAAAA==.',
['Må']='Måladroit:BAAANQADCgIIAgAAAA==.',
Na='Nareík:BAAANQAECgcJEgAAAA==.Nazarath:BAAANQABCgIIAgAAAA==.',
Ne='Neriak:BAAANQAECgYIDQAAAA==.Newa:BAAANQADCgUIBQAAAA==.',
Ni='Nightwater:BAABNQAECoEYAAMIAAgK2xKTFwD5AQAIAAgK2xKTFwD5AQAJAAEKEAWYgwAvAAAAAA==.',
Or='Orchop:BAAANQADCgUIBgAAAA==.Orenrim:BAAANQADCgMIAwAAAA==.',
Os='Osanyin:BAAANQADCgUICAAAAA==.',
Pa='Paado:BAAANQADCgEIAQAAAA==.Paulterian:BAAANQAECgQIBAAAAA==.',
Pf='Pffthmgcdrgn:BAAANQADCgQIBAAAAA==.',
Ph='Phinehas:BAAANQADCggJCAAAAA==.',
Po='Poldalina:BAAANQADCgUICAAAAA==.',
Pr='Pr:BAAANQADCgYIBgAAAA==.Priesaa:BAAANQADCgcICwABNQAECgEIAQAEAAAAAA==.',
Pu='Pumplord:BAAANQADCgIIAgAAAA==.',
Qe='Qeynos:BAAANQAECgEIAQAAAA==.',
Qu='Quazeemoto:BAAANQADCgEIAQAAAA==.',
Ra='Rainknuckles:BAAANQAECgYJCwAAAA==.Ratrenot:BAAANQADCggIDAAAAA==.Rayshano:BAAANQADCggICAABNQAECgcJCwAEAAAAAA==.',
Re='Resia:BAAANQADCggIEAAAAA==.Revocsid:BAAANQADCgUICAAAAA==.Rezza:BAAANQADCgUJBgAAAA==.',
Ri='Ridethewave:BAAANQADCgIIAgAAAA==.',
Ro='Rottingtree:BAAANQAECgEJAQAAAA==.',
Ru='Rustynails:BAAANQAECgcJCAAAAA==.',
Sa='Sazzul:BAAANQAECgEJAQAAAA==.',
Sc='Scynx:BAAANQAECgEIAQAAAA==.',
Se='Seaka:BAABNQAECoEYAAMIAAgKGxV/FQAXAgAIAAgKGxV/FQAXAgAJAAMK7QlXagCRAAAAAA==.Sernix:BAAANQAECgEIAQAAAA==.',
Sh='Shadegrim:BAAANQAECgEIAQAAAA==.Shamanic:BAAANQADCggIFgAAAA==.Shamany:BAAANQAECgEIAQAAAA==.Shariya:BAAANQADCgQIBAAAAA==.Shiftyfans:BAAANQADCgUICAAAAA==.',
Sl='Slamin:BAAANQADCgYIBwAAAA==.',
Sn='Snowwind:BAAANQADCgUICAAAAA==.',
So='Solthea:BAAANQABCgMIBAAAAA==.Sonar:BAABNQAECoEXAAIKAAgKmRKEQAA1AgAKAAgKmRKEQAA1AgAAAA==.Sonasham:BAAANQADCgUICAAAAA==.Sonnybear:BAAANQADCgUICAAAAA==.Soulhatcher:BAAANQADCgEIAQAAAA==.Soulslinger:BAAANQABCgQIBQAAAA==.Soxs:BAAANQAECgUICQAAAA==.',
Sp='Spawnofdeath:BAAANQADCggIDQAAAA==.Spectrelok:BAAANQAECgMIBAAAAA==.Spectrepunch:BAAANQAECgEIAQAAAA==.',
St='Steàlthy:BAAANQAECgQJBQAAAA==.Stompygnome:BAAANQAECgEJAQAAAA==.',
Ta='Tartanus:BAAANQADCgQIBAAAAA==.Tayzetv:BAAANQADCgcIBwABNQAECgQIBQAEAAAAAA==.',
Te='Teramiah:BAAANQADCgMIAwAAAA==.',
Th='Thebe:BAAANQADCgYIEwAAAA==.Thorall:BAAANQADCgQIAwAAAA==.',
Ti='Tippy:BAACNQAFFIEGAAICAAQKsBVRAwBWAQACAAQKsBVRAwBWAQA1AAQKgSMAAgIACQoTI88FAFUDAAIACQoTI88FAFUDAAAA.',
To='Tombstone:BAAANQAECgcIEQAAAA==.Toowongfoo:BAABNQAECoEgAAIFAAkKRxo+DgCZAgAFAAkKRxo+DgCZAgAAAA==.',
Ug='Uglysham:BAAANQAECgUICQAAAA==.',
Um='Umbranecros:BAAANQADCgEIAQAAAA==.',
Un='Underdog:BAAANQAECgEIAgAAAA==.',
Us='Usui:BAAANQADCgUIBQAAAA==.',
Va='Vaerie:BAAANQADCgYIBgAAAA==.Vagindivin:BAAANQADCggICQAAAA==.',
Ve='Venngance:BAAANQADCgYIBgAAAA==.',
Vi='Virus:BAAANQAECgEJAQAAAA==.',
Vo='Voidkity:BAAANQAECgQIBAAAAA==.',
Wa='Wakax:BAAANQADCggIFwAAAA==.Warfield:BAAANQAECgUIDAAAAA==.Warmoose:BAAANQADCggICAABNQADCggICQAEAAAAAA==.',
We='Weediez:BAAANQADCgYJCAAAAA==.',
Wi='Wildfrost:BAAANQAECgMIDgAAAA==.Willienelson:BAAANQAECggICgAAAA==.',
Wr='Wrathsome:BAAANQADCgcIDwAAAA==.',
Wy='Wyrmboy:BAAANQABCgQIBQAAAA==.Wyterd:BAAANQAECgIIAwAAAA==.',
Xa='Xaernach:BAAANQADCgQIBgAAAA==.Xalome:BAAANQADCgUIEwAAAA==.',
Xo='Xoxo:BAAANQAECgQIBwAAAA==.',
Za='Zarkus:BAAANQADCggJEwAAAA==.Zaruknark:BAAANQAECgUIBwAAAA==.',
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
