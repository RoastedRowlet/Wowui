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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','Priest-Holy','Paladin-Protection','Mage-Arcane','Mage-Frost','Paladin-Retribution','Shaman-Elemental','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Blood','Hunter-Survival',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=53,date='2026-09-15',data={Ad='Adversary:BAAANQADCgIIAgAAAA==.',
Ae='Aennish:BAAANQABCgIIBgAAAA==.',
Ag='Aglaranna:BAAANQADCgYIBgAAAA==.Agross:BAAANQADCggIDgAAAA==.',
Ai='Airibeth:BAAANQADCggIDgAAAA==.Aiyanna:BAAANQADCgMIBAABNQAECgIIAgABAAAAAA==.',
Al='Alric:BAAANQAECgQIBwAAAA==.Althalos:BAAANQABCgQIBgAAAA==.',
Ao='Aothanu:BAAANQADCgEIAQAAAA==.',
Ap='Aprit:BAAANQADCgMIAwAAAA==.',
Ar='Aracia:BAAANQADCgMIAwAAAA==.Ardhammer:BAAANQADCgcIDQAAAA==.Arragorn:BAAANQAECgYIDwAAAA==.',
As='Astal:BAABNQAECoEZAAICAAgJniEKCgC6AgACAAgJniEKCgC6AgAAAA==.',
At='Ate:BAAANQAECgUICQAAAA==.',
Au='Aurathur:BAAANQADCgYIFQAAAA==.',
Av='Avyl:BAAANQADCgEIAQAAAA==.',
Az='Azalenne:BAAANQAECgIIAgABNQAECgQIBgABAAAAAA==.Azriella:BAAANQADCgcIEgAAAA==.Azuren:BAAANQAECgUICQAAAA==.',
Ba='Bacon:BAAANQAECgUIDAAAAA==.Bamboozled:BAAANQADCgQIBAABNQAECgUICQABAAAAAA==.Bankai:BAAANQAECgcIDQAAAA==.',
Be='Beardedtroll:BAAANQAECgYIBgABNQAECgYICgABAAAAAA==.Beefstrasz:BAABNQAECoEcAAIDAAgJOw+LMwDRAQADAAgJOw+LMwDRAQAAAA==.Beyla:BAAANQAECgEIAQAAAA==.',
Bi='Bishamon:BAAANQAECgEIAQAAAA==.',
Bl='Blank:BAAANQAECgMIAwAAAA==.Bleau:BAAANQADCggICgAAAA==.Blethings:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Bloodhornbob:BAAANQADCgUIDgAAAA==.Bloodrayna:BAAANQADCgUIBQAAAA==.Bloodymary:BAAANQAECgYIDwAAAA==.Bluebarrie:BAAANQADCgUICQAAAA==.Bluwolferine:BAAANQAECgQICQAAAA==.',
Bo='Boolzeye:BAAANQABCgQICAAAAA==.Bowl:BAABNQAECoEcAAIEAAgJyiGzBAD4AgAEAAgJyiGzBAD4AgAAAA==.',
Br='Branchling:BAAANQADCgEIAQABNQAECgkJGwAFAMIdAA==.Breaklimit:BAAANQADCgYIBgAAAA==.',
Bu='Butterkip:BAAANQAFFAIIAgAAAA==.',
Ce='Cellan:BAAANQADCgYIEwAAAA==.',
Ch='Cheww:BAAANQAECgQIBgAAAA==.Chlorofõrm:BAAANQADCggIFAAAAA==.Chokonit:BAAANQAECgMIBAAAAA==.Chopahoe:BAAANQAECgUICQAAAA==.Chudlock:BAAANQADCgYIBwABNQAECgcIEQABAAAAAA==.Chumpcooker:BAAANQADCgUIBQAAAA==.',
Cl='Clamius:BAABNQAECoEbAAMFAAkJ/yP2CgCHAwAFAAkJTCP2CgCHAwAGAAIJ0SOKFACxAAAAAA==.Cliff:BAAANQAECgUICQAAAA==.',
Co='Coldstone:BAAANQADCgMIBAAAAA==.Conduit:BAAANQAECgcIDgAAAA==.Coombrain:BAAANQADCgIIAwAAAA==.Cotopla:BAAANQAECgQICAAAAA==.',
Da='Darkart:BAAANQADCgYICgAAAA==.',
De='Deathlentlez:BAAANQAECgMIAwAAAA==.Deepséeded:BAAANQADCgEIAQAAAA==.Delphyne:BAAANQADCgYIBgAAAA==.Demonià:BAAANQADCgYIEAAAAA==.',
Di='Dinkleberg:BAAANQABCgUIBgAAAA==.Disçiple:BAAANQADCggIEgAAAA==.',
Dj='Djazz:BAAANQADCgMIAwAAAA==.',
Dr='Drowsee:BAAANQADCgYIEAAAAA==.',
['Dà']='Dàrkscythe:BAAANQADCgEIAQAAAA==.',
Ea='Eazywin:BAAANQADCgUIBQAAAA==.',
Eh='Ehlsi:BAAANQAECgUIBQAAAA==.',
Ei='Eirinny:BAAANQADCggIDgAAAA==.',
El='Elindez:BAAANQADCgcIDQAAAA==.Elyviel:BAAANQAECgQIBgAAAA==.',
Em='Emyrson:BAAANQADCgEIAQAAAA==.',
Eo='Eowen:BAAANQAECgQICQAAAA==.',
Ez='Ezmee:BAAANQADCggIGgAAAA==.',
Fa='Faelicia:BAAANQADCgQIBAAAAA==.',
Fr='Frostdruid:BAAANQADCgEIAQAAAA==.',
Fu='Fundip:BAAANQAECgIIAgAAAA==.',
Fy='Fythra:BAAANQADCgcIFAAAAA==.Fythri:BAAANQADCgUICQABNQADCgcIFAABAAAAAA==.',
Ga='Gart:BAAANQADCgcIBwAAAA==.',
Gi='Gibbii:BAAANQADCgUIBQABNQAECgUIDQABAAAAAA==.Gibhasarms:BAAANQADCgYIBgABNQAECgUIDQABAAAAAA==.Giblock:BAAANQAECgUIDQAAAA==.Ginju:BAAANQAECgUICQAAAA==.',
Go='Golomojek:BAAANQADCgYICAAAAA==.Govs:BAAANQADCgMIAwAAAA==.',
Gr='Gralmerte:BAAANQAECgUICgAAAA==.Grawfern:BAAANQAECgYICwAAAA==.Graziella:BAAANQADCgYICQABNQAECgEIAQABAAAAAA==.',
Gu='Guldave:BAAANQADCgMIAwAAAA==.Guthrie:BAAANQADCggIEgAAAA==.',
['Gø']='Gødøfwarz:BAAANQAECggICAAAAA==.',
Ha='Haether:BAAANQAECgUIBQAAAA==.',
He='Healforbeer:BAAANQADCgQIBAAAAA==.Healulngtime:BAAANQADCgQIBwAAAA==.Heiling:BAAANQAECgQIBgAAAA==.Hext:BAAANQADCgQIBAABNQAECgUIDgABAAAAAA==.',
Ho='Holygral:BAAANQABCgYIDQABNQAECgUICgABAAAAAA==.Holymun:BAAANQABCgQIBAABNQAECgIIAgABAAAAAA==.Holyox:BAAANQAECgUICQAAAA==.',
Ht='Hturtle:BAAANQAECgIIAgAAAA==.',
Hy='Hyrri:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.',
Ig='Ignuskore:BAAANQAECgEIAQAAAA==.',
Im='Imdatroll:BAAANQADCgMIAwABNQAECgYICgABAAAAAA==.',
In='Inexorable:BAABNQAECoEUAAIHAAgJqhxmHwCqAgAHAAgJqhxmHwCqAgAAAA==.',
Io='Iolegnaro:BAAANQAECgYIDgABNQAECgkJGQAIAEUmAA==.',
Ir='Ironfel:BAAANQADCgQIBAAAAA==.',
It='Itches:BAABNQAECoEiAAIJAAkJBiV2AQC2AwAJAAkJBiV2AQC2AwAAAA==.',
Iz='Izry:BAAANQAECgUIBQAAAA==.',
Ja='Jaason:BAAANQAECgUICgAAAA==.Jalen:BAAANQABCgQIBAAAAA==.Janvi:BAAANQADCgMIAwAAAA==.Jarico:BAAANQADCgYIEAABNQAECgIIAgABAAAAAA==.',
Jh='Jhunts:BAAANQAECgYICwAAAA==.',
Ji='Jinfuse:BAAANQAECgQICAAAAA==.',
Jp='Jpdh:BAAANQAECgYIDgAAAA==.Jpdumb:BAAANQADCggICAABNQAECgYIDgABAAAAAA==.',
Ju='Juddory:BAAANQADCggIGAAAAA==.Junksvil:BAAANQAECgIIAgAAAA==.',
['Jø']='Jøhnwick:BAAANQADCgIIAgAAAA==.',
Kh='Khalyon:BAAANQAECgYIDgAAAA==.',
Ki='Killerelf:BAAANQADCgUIBQAAAA==.',
Ko='Koa:BAAANQAECgEIAQAAAA==.Korinth:BAEANQAECgcIEgAAAA==.',
Kr='Kriaalis:BAAANQADCgEIAQAAAA==.',
Ku='Kunitsu:BAAANQAECgMIAwAAAA==.',
Ky='Kyra:BAAANQADCggICwAAAA==.Kyril:BAABNQAECoEWAAIHAAgJAB7pGQDSAgAHAAgJAB7pGQDSAgAAAA==.',
La='Lagabriela:BAAANQAECgQICQAAAA==.Lazuli:BAAANQADCgQIBAABNQAECgUIDAABAAAAAA==.',
Le='Legault:BAAANQAECgMIBAAAAA==.Legionofboom:BAAANQADCgIIAgAAAA==.Lethfel:BAAANQAECgEIAQAAAA==.',
Li='Lillithfaust:BAAANQAECgEIAQAAAA==.Limbø:BAAANQADCgcICQAAAA==.Lionfury:BAAANQADCgcIEQABNQAECgYIEQABAAAAAA==.Lionguard:BAAANQAECgYIEQAAAA==.Livie:BAAANQADCgcIFgAAAA==.',
Lo='Loca:BAAANQAECgUICQAAAA==.Lonelylad:BAAANQABCgIIAgAAAA==.Loraddesmos:BAAANQAECgQIBgAAAA==.Loáth:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Lu='Lucance:BAAANQADCgQIBAAAAA==.',
Ly='Lyship:BAAANQAECgIIAgAAAA==.',
Ma='Maeg:BAAANQAECgYICgAAAA==.Mahll:BAAANQADCggIEQABNQAECgYIDwABAAAAAA==.Maidenchina:BAAANQADCgQICAAAAA==.Maleveck:BAAANQAECgQIBAAAAA==.Marcdofu:BAAANQADCgQIBAAAAA==.Mardista:BAAANQADCgYIBgAAAA==.',
Mc='Mctanker:BAAANQAECgEIAQAAAA==.',
Me='Meascii:BAAANQAECgQIBAAAAA==.Megavolt:BAAANQADCggICAABNQAECgkJIgAJAAYlAA==.Megs:BAAANQADCgcIEwAAAA==.Merc:BAABNQAECoEcAAIJAAkJsx7cBQAbAwAJAAkJsx7cBQAbAwAAAA==.',
Mi='Miluo:BAAANQAECgMIBQABNQAECgUIBgABAAAAAA==.Mindpuck:BAAANQADCgcIDAAAAA==.Mintchyp:BAAANQAECgQIBAAAAA==.Mirefighter:BAAANQADCgUIBQABNQAECgcIEQABAAAAAA==.Mirespike:BAAANQAECgcIEQAAAA==.Mistbrew:BAAANQADCgYIDQAAAA==.',
Mo='Mommacougar:BAAANQADCgIIAgAAAA==.Moon:BAAANQADCgUIBQAAAA==.Morlis:BAAANQADCgUIDQAAAA==.Morlock:BAAANQAECgUICAAAAA==.Morningstahr:BAAANQAECgYIDAAAAA==.',
Mu='Munion:BAAANQAECgIIAgAAAA==.',
Mv='Mvp:BAAANQADCgQIBAAAAA==.',
['Më']='Mëdpac:BAAANQAECgUICwAAAA==.',
['Mô']='Môrningstar:BAAANQADCgUIBQAAAA==.',
Na='Naaruto:BAAANQADCgEIAQAAAA==.Nanako:BAAANQADCgYIEAAAAA==.Naravanta:BAAANQADCgUIBQAAAA==.Naughtyreapr:BAAANQADCgEIAQABNQADCggIEwABAAAAAA==.Naughtyvoked:BAAANQADCgQIBAABNQADCggIEwABAAAAAA==.',
Ne='Nevicus:BAAANQADCgEIAQAAAA==.',
Ni='Nickayla:BAAANQADCgcIEgAAAA==.Nikkaya:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Nimblecow:BAAANQADCgEIAQAAAA==.',
No='Noobacleese:BAAANQAECgUICQAAAA==.Noraviae:BAAANQADCgMIBgAAAA==.',
Ny='Nyghtrider:BAAANQAECgIIAgAAAA==.Nymëra:BAAANQAECgQIBQAAAA==.Nyneeve:BAAANQAECgMIBQAAAA==.',
Ol='Olgrin:BAAANQADCgUIBQAAAA==.',
On='Oneslice:BAAANQADCgYIBgAAAA==.',
Or='Orw:BAAANQADCgMIAwAAAA==.',
Pa='Palpatinee:BAAANQAECgUIBQAAAA==.Papitochulo:BAAANQADCgUIBQAAAA==.Parabelum:BAAANQADCgYICAAAAA==.Partita:BAAANQAECgEIAQAAAA==.',
Pb='Pbób:BAAANQADCgMIAwAAAA==.',
Pe='Percocetpete:BAAANQAECggIDQAAAA==.Peregrine:BAAANQADCgIIAgAAAA==.',
Ph='Phaet:BAABNQAECoEbAAMKAAgJnh97IgBiAgAKAAcJuR97IgBiAgALAAQJBxXbIgAiAQAAAA==.Phaux:BAAANQADCgUIDQAAAA==.',
Pi='Piper:BAAANQADCgQICAAAAA==.',
Pl='Plâgue:BAAANQAECgYICwAAAA==.',
Pu='Punslug:BAAANQADCgMIAwABNQAECgYIEwABAAAAAA==.Puntthegnome:BAAANQADCgEIAQABNQAECgkJGwAFAMIdAA==.',
Ra='Rainforest:BAAANQAECgIIAgAAAA==.Ramden:BAAANQAECgUICQAAAA==.Rampant:BAAANQAECgEIAQAAAA==.Rampscii:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Randolier:BAAANQAECgUICQAAAA==.Ratherton:BAABNQAECoEbAAIFAAkJwh3xKgDlAgAFAAkJwh3xKgDlAgAAAA==.Rathtard:BAAANQAECgUIBgABNQAECgkJGwAFAMIdAA==.Razz:BAAANQABCgIIAgAAAA==.',
Re='Resoluteone:BAAANQAECgYIDAAAAA==.Retnu:BAAANQADCgQICAAAAA==.Revytwohand:BAABNQAECoEcAAIJAAgJxxsHDwBLAgAJAAgJxxsHDwBLAgAAAA==.',
Rh='Rhok:BAAANQADCgYIBgAAAA==.',
Ro='Robonome:BAAANQADCgUIBQAAAA==.',
Ru='Rumii:BAAANQAECgIIAwAAAA==.',
['Rë']='Rëápër:BAAANQADCgIIAgAAAA==.',
Sa='Sabeladys:BAAANQAECgUIBQAAAA==.Saifir:BAAANQAECgQIBwAAAA==.Sardmagia:BAAANQAECgIIAgABNQAECgUICAABAAAAAA==.Sardmongo:BAAANQAECgEIAQAAAA==.Sarduccini:BAAANQAECgUICAAAAA==.',
Sh='Shiftken:BAAANQADCgMIAwAAAA==.Shoktherapy:BAAANQAECgEIAQAAAA==.',
Si='Silvalus:BAAANQADCgMIBAABNQADCgUIBQABAAAAAA==.Silvertide:BAAANQAECgQICQAAAA==.Sin:BAAANQADCgMIAwAAAA==.',
Sk='Skyeforce:BAAANQADCggIDgAAAA==.',
Sl='Slipknoth:BAAANQAECgEIAQAAAA==.',
So='Soi:BAAANQAECgUIBgAAAA==.Sondaar:BAAANQABCgQICQAAAA==.Sonoforak:BAAANQAECgMIAwAAAA==.',
Sp='Sped:BAAANQAECgUICAAAAA==.',
St='Stiffyhaze:BAAANQAECgQIBAAAAA==.Stingyr:BAAANQADCgcICwABNQADCggIEgABAAAAAA==.Stormslight:BAAANQADCgYIBgAAAA==.Stormsteel:BAAANQADCgYIBgAAAA==.Stossel:BAAANQADCggIEwAAAA==.',
Sw='Sweetie:BAAANQADCgYICgAAAA==.',
Ta='Talas:BAAANQAECgUICQAAAA==.Tanksabunch:BAAANQAECgcICgABNQAFFAUIDAAMAOMcAA==.',
Te='Tehmay:BAAANQADCgIIAgAAAA==.Tenssid:BAAANQADCggIFQAAAA==.',
Th='Thorclap:BAAANQAECgEIAQAAAA==.',
Ti='Tim:BAAANQADCggICgABNQAECgYIEgABAAAAAA==.',
To='Tooru:BAABNQAECoEcAAMNAAgJShnhMAA2AgANAAcJPBrhMAA2AgAMAAgJug+TGgDpAQAAAA==.',
Tw='Twinkles:BAAANQAECgUICwAAAA==.Twotoetimmy:BAAANQAECgIIAgAAAA==.',
Ul='Ulysius:BAAANQAECgQICgAAAA==.',
Va='Valkisek:BAAANQAECgYICwAAAA==.Vallarfax:BAAANQAECgUICQAAAA==.Vandro:BAAANQAECgUIDgAAAA==.Vashdk:BAABNQAECoEcAAIOAAgJLyRyCAAyAwAOAAgJLyRyCAAyAwAAAA==.',
Ve='Velcyn:BAAANQAFFAEIAgAAAA==.Veloranas:BAAANQAECgUICwAAAA==.Venôm:BAAANQADCgQIBAAAAA==.Vespyr:BAAANQADCggIEgAAAA==.Vewdoo:BAAANQAFFAEIAQAAAA==.Vexiara:BAAANQADCgcIDwABNQAECgQIBgABAAAAAA==.',
Vi='Vizimir:BAAANQADCggIFAAAAA==.',
Vy='Vynstabbin:BAAANQAECgQIBQAAAA==.',
Wa='Warfarin:BAAANQADCgMIAwAAAA==.Wascii:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
We='Weaken:BAAANQAECgYIBgAAAA==.',
Wi='Willy:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Wizkerbizkit:BAAANQAECgEIAgAAAA==.',
Wo='Wolfcaza:BAAANQADCgcIDgAAAA==.Wolvesbane:BAAANQAECggICAAAAA==.Wooshira:BAAANQADCgUIDgAAAA==.',
Wy='Wyrmheal:BAAANQAECgYIDAAAAA==.Wyvvie:BAAANQAECgIIAwAAAA==.',
Ya='Yamihime:BAAANQAECgUICQAAAA==.Yatiri:BAAANQAECgIIAgAAAA==.',
Za='Zalinis:BAAANQADCgYICAAAAA==.',
Ze='Zeaket:BAACNQAFFIEFAAIPAAMJzho6AAAkAQAPAAMJzho6AAAkAQA1AAQKgSEAAg8ACQnpJDgAAM4DAA8ACQnpJDgAAM4DAAAA.Zephyr:BAAANQADCgYIDgABNQADCggIEgABAAAAAA==.Zerrayna:BAAANQADCgYICwAAAA==.Zeçhs:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.',
Zi='Zinbad:BAAANQADCgYIEQAAAA==.',
Zo='Zorcan:BAAANQADCgcIFgAAAA==.',
Zu='Zugzugz:BAAANQAECggICAAAAA==.Zulfilith:BAAANQADCgUIDQAAAA==.',
['Zà']='Zàrgothrax:BAAANQADCgYIBgAAAA==.',
['Ãi']='Ãinz:BAAANQADCgIIAgAAAA==.',
['Ða']='Ðachee:BAAANQAECgQIBgAAAA==.',
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
