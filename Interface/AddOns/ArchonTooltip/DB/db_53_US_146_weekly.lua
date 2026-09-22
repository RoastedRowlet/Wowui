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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','Shaman-Enhancement','Priest-Holy','DeathKnight-Blood','Paladin-Protection','Mage-Arcane','Priest-Shadow','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Paladin-Holy','Paladin-Retribution','Monk-Windwalker','DemonHunter-Devourer','DemonHunter-Vengeance','Druid-Feral','Druid-Balance','Warlock-Demonology','Warlock-Destruction','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=53,date='2026-09-22',data={Ad='Adrenalin:BAAANQADCgYIBgAAAA==.Adversary:BAAANQADCgcICQAAAA==.',
Ae='Aennish:BAAANQABCgIIBgAAAA==.',
Ag='Aglaranna:BAAANQADCgYIBgAAAA==.Agross:BAAANQADCggIDgAAAA==.',
Ai='Airibeth:BAAANQAECgMJAgAAAA==.Aiyanna:BAAANQADCgMJBAABNQAECgQIBgABAAAAAA==.',
Al='Alric:BAAANQAECgYIDQAAAA==.Althalos:BAAANQABCgQIBgAAAA==.',
Ao='Aothanu:BAAANQADCgEIAQAAAA==.',
Ap='Aprit:BAAANQADCgMIAwAAAA==.',
Ar='Aracia:BAAANQADCgMIAwAAAA==.Ardhammer:BAAANQAECgQJBAAAAA==.Arragorn:BAAANQAECgYIDwAAAA==.',
As='Asendra:BAAANQAECgQIBAAAAA==.Astal:BAABNQAECoEdAAICAAkKoyEFCwD4AgACAAkKoyEFCwD4AgAAAA==.',
At='Ate:BAAANQAECgYJDwAAAA==.',
Au='Aurathur:BAAANQADCggJHQAAAA==.',
Av='Avyl:BAAANQADCgEJAQABNQAECgIIAgABAAAAAA==.',
Ay='Ayannar:BAAANQABCgIIAgAAAA==.',
Az='Azalenne:BAAANQAECgIIAgABNQAECgQIBgABAAAAAA==.Azriella:BAAANQADCgcJGQAAAA==.Azuren:BAAANQAECgYIDwAAAA==.',
Ba='Bacon:BAAANQAECgYIEgAAAA==.Bamboozled:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Bankai:BAABNQAECoEXAAIDAAgKyCIaAwBJAwADAAgKyCIaAwBJAwAAAA==.',
Be='Beardedtroll:BAAANQAECggJBgAAAA==.Beefstrasz:BAABNQAECoEiAAIEAAkK7BAmMwAnAgAEAAkK7BAmMwAnAgAAAA==.Beyla:BAAANQAECgQJBQAAAA==.',
Bh='Bhalecgos:BAAANQADCgQJBAABNQADCgYICAABAAAAAA==.',
Bi='Bishamon:BAAANQAECgEIAgAAAA==.',
Bl='Blank:BAAANQAECgMIAwAAAA==.Bleau:BAAANQAECgMJAwAAAA==.Blethings:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.Bloodhornbob:BAAANQADCgUJDgAAAA==.Bloodrayna:BAAANQADCgUIBQAAAA==.Bloodráyne:BAAANQADCgMIAwAAAA==.Bloodymary:BAABNQAECoEZAAIFAAgKwRLXLwDnAQAFAAgKwRLXLwDnAQAAAA==.Bluebarrie:BAAANQADCgUICQAAAA==.Bluwolferine:BAAANQAECgYIDwAAAA==.',
Bo='Boolzeye:BAAANQABCgQICAAAAA==.Bowl:BAABNQAECoEkAAIGAAkKLSFuBAA3AwAGAAkKLSFuBAA3AwAAAA==.',
Br='Branchling:BAAANQADCgYIBwABNQAFFAUICQAHAKAOAA==.Breaklimit:BAAANQADCggIDQAAAA==.',
Bu='Butterkip:BAABNQAECoEZAAIIAAkKohZCEACbAgAIAAkKohZCEACbAgAAAA==.',
Ce='Cellan:BAAANQADCgYIEwAAAA==.',
Ch='Chewdawgg:BAAANQADCggJAQAAAA==.Cheww:BAAANQAECgYICAAAAA==.Chlorofõrm:BAAANQAECgMIAwAAAA==.Chokonit:BAAANQAECgMIBAAAAA==.Chopahoe:BAAANQAECgYJDwAAAA==.Chudlock:BAAANQADCggJDwAAAA==.Chumpcooker:BAAANQADCgYIBgAAAA==.',
Cl='Clamius:BAABNQAECoEfAAMHAAkKwSRaDwCBAwAHAAkKxSNaDwCBAwAJAAMKzyQvEQAaAQAAAA==.Cliff:BAAANQAECgYJDwAAAA==.',
Co='Coldstone:BAAANQADCgMIBAAAAA==.Conduit:BAABNQAECoEZAAMKAAkKUiINBgBwAwAKAAkKUiINBgBwAwALAAIKhxkFrwCXAAAAAA==.Coombrain:BAAANQADCgIIAwAAAA==.Cosmic:BAAANQADCgYIBgAAAA==.Cotopla:BAAANQAECgQJDAAAAA==.',
Cr='Crimsondream:BAAANQADCgcIBwAAAA==.',
Da='Dagov:BAAANQAECgIIAgAAAA==.Darkart:BAAANQADCgYICgAAAA==.Darkshivers:BAAANQADCgcIBwABNQADCggJDwABAAAAAA==.',
De='Deathlentlez:BAAANQAECgYICQAAAA==.Deepséeded:BAAANQADCgEIAQAAAA==.Delphyne:BAAANQADCgYIBgAAAA==.Demonhunter:BAAANQAECgQIBAAAAA==.Demonià:BAAANQADCgYJEAAAAA==.',
Di='Dinkleberg:BAAANQABCgUIBgAAAA==.Disçiple:BAAANQADCggJEgAAAA==.',
Dj='Djazz:BAAANQADCgMJAwAAAA==.',
Dr='Drowsee:BAAANQADCgYJEAAAAA==.',
['Dà']='Dàrkscythe:BAAANQADCgEIAQAAAA==.',
Ea='Eazywin:BAAANQADCgUIBQAAAA==.',
Eh='Ehlsi:BAAANQAECgYICwAAAA==.',
Ei='Eirinny:BAAANQADCggIDgAAAA==.',
El='Elindez:BAAANQAECgQIBAAAAA==.Elyviel:BAAANQAECgQIBgAAAA==.',
Em='Emyrson:BAAANQADCgEIAQAAAA==.',
En='Encantado:BAAANQADCggJCAAAAA==.',
Eo='Eowen:BAAANQAECgQJDQAAAA==.',
Ep='Epitaph:BAAANQADCgUJBQAAAA==.',
Ez='Ezmee:BAAANQADCggIIgAAAA==.',
Fa='Faelicia:BAAANQADCgQJBwAAAA==.',
Fr='Frostdruid:BAAANQADCgEIAQAAAA==.Frowmae:BAAANQAECgIIAgAAAA==.',
Fu='Fundip:BAAANQAECgMIBQAAAA==.',
Fy='Fythra:BAAANQADCggIGgAAAA==.Fythri:BAAANQADCgYIDwABNQADCggIGgABAAAAAA==.',
Ga='Gart:BAAANQADCgcIBwAAAA==.',
Gi='Gibbii:BAAANQADCgUIBQABNQAECgYIEgABAAAAAA==.Gibhasarms:BAAANQADCgYIBgABNQAECgYIEgABAAAAAA==.Giblock:BAAANQAECgYIEgAAAA==.Ginju:BAAANQAECgYJDwAAAA==.',
Go='Golomojek:BAAANQADCgYICAAAAA==.Govs:BAAANQADCgMIAwAAAA==.',
Gr='Gralmerte:BAAANQAECgUJDwAAAA==.Grawfern:BAAANQAECgYIDAAAAA==.Graziella:BAAANQADCgYICQABNQAECgQJBQABAAAAAA==.',
Gu='Guldave:BAAANQADCgQIBwAAAA==.Guthrie:BAAANQAECgQJBAAAAA==.',
['Gø']='Gødøfwarz:BAAANQAECggICAAAAA==.',
Ha='Haether:BAAANQAECgYICwAAAA==.',
He='Healforbeer:BAAANQADCgQIBAAAAA==.Healulngtime:BAAANQADCgQIBwAAAA==.Heiling:BAAANQAECgQJCgAAAA==.Hext:BAAANQADCgQIBAABNQAECgcIFwAMACcSAA==.',
Ho='Holygral:BAAANQABCgYIEgABNQAECgUJDwABAAAAAA==.Holymun:BAAANQABCgQIBAABNQAECgQJBAABAAAAAA==.Holyox:BAAANQAECgYJDwAAAA==.',
Ht='Hturtle:BAAANQAECgIIAgAAAA==.Hturtledk:BAAANQAECggIAgAAAA==.',
Hy='Hyrri:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.',
['Hü']='Hüntress:BAAANQAECgQIBAAAAA==.',
Ig='Ignuskore:BAAANQAECgEJAQAAAA==.',
Im='Imdatroll:BAAANQADCgMIAwABNQAECggJBgABAAAAAA==.',
In='Inexorable:BAABNQAECoEXAAINAAgKdCDXIwDWAgANAAgKdCDXIwDWAgAAAA==.Interesting:BAAANQADCgYIBgAAAA==.',
Io='Iolegnaro:BAAANQAECgYIEQABNQAFFAQICAALAColAA==.',
Ir='Ironfel:BAAANQADCgQIBAAAAA==.',
It='Itches:BAACNQAFFIEJAAIOAAUKpxmiAgCyAQAOAAUKpxmiAgCyAQA1AAQKgScAAg4ACQopJdwBALMDAA4ACQopJdwBALMDAAAA.',
Iz='Izry:BAAANQAECgYJCwAAAA==.',
Ja='Jaason:BAAANQAECgYIEAAAAA==.Jalen:BAAANQABCgQIBAABNQABCgYJCAABAAAAAA==.Janvi:BAAANQADCgMIAwAAAA==.Jarico:BAAANQADCgcJFgABNQAECgQIBgABAAAAAA==.',
Jh='Jhunts:BAAANQAECgYICwAAAA==.',
Ji='Jinfuse:BAAANQAECgYJDgAAAA==.',
Jp='Jpdh:BAABNQAECoEWAAMPAAgKVRqsHAAbAgAPAAcKQxmsHAAbAgAQAAEK0yFOGQBkAAAAAA==.Jpdumb:BAAANQADCggJCAABNQAECggIFgAPAFUaAA==.',
Ju='Juddory:BAAANQAECgIJAgAAAA==.Junksvil:BAAANQAECgQIBgAAAA==.',
['Jø']='Jøhnwick:BAAANQADCgIIAgAAAA==.',
Kh='Khalyon:BAABNQAECoEZAAIHAAcK/Rk7gAAXAgAHAAcK/Rk7gAAXAgAAAA==.',
Ki='Killerelf:BAAANQADCgUIBQAAAA==.',
Ko='Koa:BAAANQAECgEIAQAAAA==.Korinth:BAEBNQAECoEbAAMNAAkKXRUUQgBKAgANAAkKCBQUQgBKAgAGAAIKGR3HNACtAAAAAA==.',
Kr='Kriaalis:BAAANQADCgEIAQAAAA==.',
Ku='Kunitsu:BAAANQAECgQIBwAAAA==.',
Ky='Kyra:BAAANQADCggJDgAAAA==.Kyril:BAABNQAECoEcAAINAAkKAyEtEABTAwANAAkKAyEtEABTAwAAAA==.',
La='Lagabriela:BAAANQAECgQJDQAAAA==.Lazuli:BAAANQADCgQIBAABNQAECgYIEgABAAAAAA==.',
Le='Legault:BAAANQAECgUJCQAAAA==.Legionofboom:BAAANQADCgIIAgAAAA==.Lethfel:BAAANQAECgUIBgAAAA==.',
Li='Lillithfaust:BAAANQAECgEIAQAAAA==.Limbø:BAAANQADCggIEQAAAA==.Lionfury:BAAANQAECgEJAQABNQAECgcIEwABAAAAAA==.Lionguard:BAAANQAECgcIEwAAAA==.Livie:BAAANQADCgcJHQAAAA==.',
Lo='Loca:BAAANQAECgYJDwAAAA==.Lonelylad:BAAANQABCgIIAgAAAA==.Loraddesmos:BAAANQAECgYJDAAAAA==.Loáth:BAAANQADCgcIBwABNQAECgEJAQABAAAAAA==.',
Lu='Lucance:BAAANQADCgQIBAAAAA==.',
Ly='Lyship:BAAANQAECgIIAgAAAA==.',
Ma='Maeg:BAAANQAECgYICgABNQAECggJBgABAAAAAA==.Mahll:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Maidenchina:BAAANQAECgMIAwAAAA==.Maleveck:BAAANQAECgYIBgAAAA==.Marcato:BAAANQADCgEIAQABNQAECgQJBQABAAAAAA==.Marcdofu:BAAANQADCgQIBAAAAA==.Mardista:BAAANQADCgYIBgAAAA==.',
Mc='Mctanker:BAAANQAECgEJAQAAAA==.',
Me='Meascii:BAAANQAECgcICwAAAA==.Megavolt:BAAANQADCggICAABNQAFFAUICQAOAKcZAA==.Megs:BAAANQADCggJEwAAAA==.Memebeams:BAAANQAECgEJAQAAAA==.Merc:BAABNQAECoEeAAIOAAkKsh8DCAAQAwAOAAkKsh8DCAAQAwAAAA==.',
Mi='Miluo:BAAANQAECgMIBQABNQAECgYIDAABAAAAAA==.Mindpuck:BAAANQADCgcIDAAAAA==.Mintchyp:BAAANQAECgQIBAAAAA==.Mirefighter:BAAANQAECgIIAgABNQAECgkJHAARAO0gAA==.Mirespike:BAABNQAECoEcAAMRAAkK7SCeAgAvAwARAAkK7SCeAgAvAwASAAEK+w/jggAwAAAAAA==.Missroxy:BAAANQADCgEIAQAAAA==.Mistbrew:BAAANQADCgcIDgAAAA==.',
Mo='Mommacougar:BAAANQADCgIJAgAAAA==.Moon:BAAANQADCgUICgAAAA==.Morlis:BAAANQADCgYIEwAAAA==.Morlock:BAAANQAECgYJDgAAAA==.Morningstahr:BAAANQAECgYIEQAAAA==.',
Mu='Munion:BAAANQAECgQJBAAAAA==.',
Mv='Mvp:BAAANQADCgQIBAAAAA==.',
['Mô']='Môrningstar:BAAANQADCgUIBQAAAA==.',
Na='Naaruto:BAAANQADCgEIAQAAAA==.Nanako:BAAANQADCgYIFgAAAA==.Naravanta:BAAANQADCgUIBQAAAA==.Naughtyreapr:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.Naughtyvoked:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.',
Ne='Nevicus:BAAANQADCgEJAQAAAA==.',
Ni='Nickayla:BAAANQADCgcJGQAAAA==.Nikkaya:BAAANQADCgYJBgABNQAECgQIBgABAAAAAA==.Nimblecow:BAAANQADCgEIAQAAAA==.',
No='Noobacleese:BAAANQAECgYJDwAAAA==.Noraviae:BAAANQADCgMIBgAAAA==.',
Ny='Nyghtrider:BAAANQAECgQIBgAAAA==.Nymëra:BAAANQAECgUJCgAAAA==.Nyneeve:BAAANQAECgYJCwAAAA==.',
Od='Odinshunter:BAAANQADCgIIAgAAAA==.',
Ol='Olgrin:BAAANQADCgUIBQABNQADCgcJCwABAAAAAA==.',
On='Onepunch:BAAANQADCgcIBwAAAA==.Oneslice:BAAANQADCgYIBgAAAA==.',
Or='Orw:BAAANQADCgMIAwAAAA==.',
Pa='Palpatinee:BAAANQAECgUIBQAAAA==.Papitochulo:BAAANQADCgUIBQAAAA==.Parabelum:BAAANQADCgYICAAAAA==.Partita:BAAANQAECgQJBQAAAA==.',
Pb='Pbób:BAAANQAECggIAQAAAA==.',
Pe='Percocetpete:BAAANQAECggIEAAAAA==.Peregrine:BAAANQADCgIIAgAAAA==.',
Ph='Phaet:BAABNQAECoEfAAMTAAkK8x+ZHQC3AgATAAgKFSCZHQC3AgAUAAQKBxWyJwAUAQAAAA==.Phaux:BAAANQADCgYIEwAAAA==.',
Pi='Piper:BAAANQADCgQJCAAAAA==.',
Pl='Plâgue:BAAANQAECgcIEgAAAA==.',
Pr='Prot:BAAANQADCgUJBQAAAA==.',
Pu='Punslug:BAAANQADCgMIAwABNQAECgcJFQARABcmAA==.Puntthegnome:BAAANQADCgEIAQABNQAFFAUICQAHAKAOAA==.',
Ra='Rainforest:BAAANQAECgQIBgAAAA==.Ramden:BAAANQAECgUICgAAAA==.Rampant:BAAANQAECgYIBwAAAA==.Rampscii:BAAANQADCgMIAwABNQAECgYIBwABAAAAAA==.Randolier:BAAANQAECgYJDwAAAA==.Ratherton:BAACNQAFFIEJAAIHAAUKoA7hCwCiAQAHAAUKoA7hCwCiAQA1AAQKgSAAAgcACQqLHiw0APECAAcACQqLHiw0APECAAAA.Rathtard:BAAANQAECgYJDAABNQAFFAUICQAHAKAOAA==.Rauzer:BAAANQABCgIJAgAAAA==.Razz:BAAANQABCgIIAgAAAA==.',
Re='Renuwu:BAABNQAECoEXAAIEAAcKwgcHYABYAQAEAAcKwgcHYABYAQAAAA==.Resoluteone:BAAANQAECgYJEgAAAA==.Retnu:BAAANQADCgQICAAAAA==.Revytwohand:BAABNQAECoEiAAIOAAkKcxtLDgCYAgAOAAkKcxtLDgCYAgAAAA==.',
Rh='Rhok:BAAANQADCgcIDQAAAA==.',
Ro='Robonome:BAAANQADCgUIBQAAAA==.',
Ru='Rumii:BAAANQAECgIIAwAAAA==.',
['Rë']='Rëápër:BAAANQADCgIIAgAAAA==.',
Sa='Sabeladys:BAAANQAECgYJCQAAAA==.Saifir:BAAANQAECgYIDQAAAA==.Sardmagia:BAAANQAECgIIAgABNQAECgUJDAABAAAAAA==.Sardmongo:BAAANQAECgEIAQAAAA==.Sarduccini:BAAANQAECgUJDAAAAA==.',
Sh='Shiftken:BAAANQADCgMIAwAAAA==.Shoktherapy:BAAANQAECgUJBgAAAA==.',
Si='Silvalus:BAAANQADCgcJCwAAAA==.Silvertide:BAAANQAECgYIDwAAAA==.Sin:BAAANQADCgMIAwAAAA==.',
Sk='Skyeforce:BAAANQADCggIDgAAAA==.',
Sl='Slipknoth:BAAANQAECgEIAQAAAA==.',
So='Soi:BAAANQAECgYIDAAAAA==.Solvent:BAAANQADCgYIBgAAAA==.Sondaar:BAAANQABCgYICwAAAA==.Sonoforak:BAAANQAECgMJAwAAAA==.',
Sp='Sped:BAAANQAECgYIDgAAAA==.',
St='Stiffyhaze:BAAANQAECgQIBAAAAA==.Stingyr:BAAANQADCggIEgABNQADCggIGgABAAAAAA==.Stormslight:BAAANQADCgcIDQAAAA==.Stormsteel:BAAANQADCgYIBgAAAA==.Stossel:BAAANQAECgQJBAAAAA==.',
Sw='Sweetie:BAAANQADCgYICgAAAA==.',
Ta='Talas:BAAANQAECgYJDwAAAA==.Tanksabunch:BAAANQAECggIDQABNQAFFAYIEQAVAB0hAA==.',
Te='Tehmay:BAAANQADCgIIAgAAAA==.Tenssid:BAAANQADCggJFQAAAA==.',
Th='Thorclap:BAAANQAECgEJAQAAAA==.',
Ti='Tim:BAAANQADCggJCgABNQAECgYIEwABAAAAAA==.',
To='Tooru:BAABNQAECoEgAAMWAAkKuBveJwCWAgAWAAgK2RzeJwCWAgAVAAgKug9WIQDTAQAAAA==.',
Tr='Triena:BAAANQADCggJCAAAAA==.',
Tw='Twinkles:BAAANQAECgYJEQAAAA==.Twotoetimmy:BAAANQAECgIJAgAAAA==.',
Ul='Ulysius:BAAANQAECgYJEAAAAA==.',
Un='Unfazed:BAAANQADCgIIAgAAAA==.',
Va='Valkisek:BAAANQAECgYJCwAAAA==.Vallarfax:BAAANQAECgYJDwAAAA==.Vandro:BAABNQAECoEXAAIMAAcKJxLhTgC2AQAMAAcKJxLhTgC2AQAAAA==.Vashdk:BAABNQAECoEgAAIFAAkKayM+BgBvAwAFAAkKayM+BgBvAwAAAA==.',
Ve='Velcyn:BAAANQAFFAEIAgAAAA==.Veloranas:BAABNQAECoEWAAMHAAkKuw9qdQAzAgAHAAkKhgxqdQAzAgAJAAMK3xH2GAC8AAAAAA==.Venjince:BAAANQADCgYIBgAAAA==.Venôm:BAAANQADCgQIBAAAAA==.Vespyr:BAAANQADCggIGgAAAA==.Vewdoo:BAAANQAFFAEIAQAAAA==.Vexiara:BAAANQADCgcIDwABNQAECgQIBgABAAAAAA==.',
Vi='Vizimir:BAAANQADCggJGwAAAA==.',
Vy='Vynstabbin:BAAANQAECgUJCgAAAA==.',
Wa='Warfarin:BAAANQADCgMIAwAAAA==.Wascii:BAAANQAECgEIAQABNQAECgYIBwABAAAAAA==.',
We='Weaken:BAAANQAECgYIBgAAAA==.',
Wi='Willy:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Wizkerbizkit:BAAANQAECgMJBQAAAA==.',
Wo='Wolfcaza:BAAANQADCgcIDgAAAA==.Wolvesbane:BAAANQAECggICAAAAA==.Wooshira:BAAANQADCgUIDgAAAA==.',
Wy='Wyrmheal:BAAANQAECgYIEgAAAA==.Wyvvie:BAAANQAECgIJAwAAAA==.',
Ya='Yamihime:BAAANQAECgYJDwAAAA==.Yatiri:BAAANQAECgQIBAAAAA==.',
Za='Zalinis:BAAANQADCgYICAAAAA==.Zambas:BAAANQAECgMIAwAAAA==.',
Ze='Zeaket:BAACNQAFFIEKAAIXAAUKthgoAADqAQAXAAUKthgoAADqAQA1AAQKgSUAAhcACQrpJE8AAL0DABcACQrpJE8AAL0DAAAA.Zephyr:BAAANQADCgYJFAABNQADCggIGgABAAAAAA==.Zerrayna:BAAANQADCgYICwAAAA==.Zeçhs:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.',
Zi='Zinbad:BAAANQADCgYJFAAAAA==.',
Zo='Zorcan:BAAANQADCggIHgAAAA==.',
Zu='Zugzugz:BAAANQAECggICAAAAA==.Zulfilith:BAAANQADCgYIEwAAAA==.',
['Zà']='Zàrgothrax:BAAANQADCgYIBgAAAA==.',
['Ãi']='Ãinz:BAAANQADCgIIAgAAAA==.',
['Ða']='Ðachee:BAAANQAECgQJBgAAAA==.',
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
