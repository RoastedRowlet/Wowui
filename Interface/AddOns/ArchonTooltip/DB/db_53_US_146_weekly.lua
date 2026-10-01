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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','DeathKnight-Frost','Evoker-Devastation','DemonHunter-Havoc','Shaman-Enhancement','Priest-Holy','DeathKnight-Blood','Mage-Arcane','Paladin-Protection','Priest-Shadow','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Paladin-Holy','Paladin-Retribution','Monk-Windwalker','DemonHunter-Vengeance','Druid-Feral','Druid-Balance','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Warrior-Protection','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=53,date='2026-09-29',data={Ad='Adrenalin:BAAANQAECgIIAgAAAA==.Adversary:BAAANQADCgcICQAAAA==.',
Ae='Aennish:BAAANQABCgIIBgAAAA==.',
Ag='Aglaranna:BAAANQADCgYIBgAAAA==.Agross:BAAANQADCggIDgAAAA==.',
Ai='Airibeth:BAAANQAECgMIAgAAAA==.Aiyanna:BAAANQADCgQIBAABNQAECgQICAABAAAAAA==.',
Al='Alric:BAABNQAECoEXAAICAAgKJhb/GgBJAgACAAgKJhb/GgBJAgAAAA==.Althalos:BAAANQABCgQIBgAAAA==.',
Ao='Aothanu:BAAANQADCgEIAQAAAA==.',
Ap='Aprit:BAAANQADCgMIAwAAAA==.',
Ar='Aracia:BAAANQADCgMIAwAAAA==.Ardhammer:BAAANQAECgQJBAAAAA==.Arragorn:BAAANQAECgYIEwAAAA==.',
As='Asendra:BAAANQAECgQICAAAAA==.Astal:BAABNQAECoEhAAIDAAkKWCKwDAD+AgADAAkKWCKwDAD+AgAAAA==.',
At='Ate:BAAANQAECgcIEgAAAA==.',
Au='Aurathur:BAAANQAECgMIAwAAAA==.',
Av='Avyl:BAAANQADCgEJAQABNQAECgIIAgABAAAAAA==.',
Ay='Ayannar:BAAANQADCgMIAwAAAA==.',
Az='Azalenne:BAAANQAECgIIAgABNQAECgcICgABAAAAAA==.Azriella:BAAANQADCggIIQAAAA==.Azuren:BAABNQAECoEXAAIEAAcKGAy1GACAAQAEAAcKGAy1GACAAQAAAA==.',
Ba='Bacon:BAABNQAECoEeAAIFAAgK5CBEEgDWAgAFAAgK5CBEEgDWAgAAAA==.Bamboozled:BAAANQADCgQIBAABNQAECgYICwABAAAAAA==.Bankai:BAABNQAECoEeAAIGAAgKeyR3AwBQAwAGAAgKeyR3AwBQAwAAAA==.',
Be='Beardedtroll:BAAANQAECggIBgAAAA==.Beefstrasz:BAABNQAECoEmAAIHAAkKgxG7PAAuAgAHAAkKgxG7PAAuAgAAAA==.Beyla:BAAANQAECgUICQAAAA==.',
Bh='Bhalecgos:BAAANQADCgYICgAAAA==.',
Bi='Bishamon:BAAANQAECgEIAwAAAA==.',
Bl='Blank:BAAANQAECgMIAwAAAA==.Bleau:BAAANQAECgQIBwAAAA==.Blethings:BAAANQADCgYIBgABNQAECgUICwABAAAAAA==.Bloodhornbob:BAAANQADCgUIDgAAAA==.Bloodrayna:BAAANQADCgUIBQAAAA==.Bloodráyne:BAAANQADCgMIAwAAAA==.Bloodymary:BAABNQAECoEhAAIIAAgKwRILPADSAQAIAAgKwRILPADSAQAAAA==.Bluebarrie:BAAANQADCgUICQAAAA==.Bluwolferine:BAABNQAECoEXAAIJAAcKNhPCsgDRAQAJAAcKNhPCsgDRAQAAAA==.',
Bo='Boolzeye:BAAANQABCgQICAAAAA==.Bowl:BAABNQAECoEoAAIKAAkKOSKVBQAqAwAKAAkKOSKVBQAqAwAAAA==.',
Br='Branchling:BAAANQADCgYICQABNQAFFAUIDgAJALoPAA==.Breaklimit:BAAANQADCggIDQAAAA==.',
Bu='Butterkip:BAACNQAFFIEIAAILAAQKMg3uBwAqAQALAAQKMg3uBwAqAQA1AAQKgRsAAgsACQrUGRwUAIMCAAsACQrUGRwUAIMCAAAA.',
Ce='Cellan:BAAANQADCgYIEwAAAA==.',
Ch='Chewdawgg:BAAANQADCggJAQAAAA==.Cheww:BAAANQAECgcIEwAAAA==.Chlorofõrm:BAAANQAECgMIBQAAAA==.Chokonit:BAAANQAECgMIBAAAAA==.Choopamelo:BAAANQADCgEIAQAAAA==.Chopahoe:BAAANQAECgcIEgAAAA==.Chudlock:BAAANQADCggJDwABNQAECgkJJgAHACQfAA==.Chumpcooker:BAAANQADCgYIBgAAAA==.',
Cl='Clamius:BAACNQAFFIEHAAMMAAMK7BjXBQBqAAAJAAIKtRIVLwCpAAAMAAEKWSXXBQBqAAA1AAQKgSIAAwkACQrVJBsWAGsDAAkACQrZIxsWAGsDAAwAAwrPJOgVAA4BAAAA.Cliff:BAAANQAECgcIEgAAAA==.',
Co='Coldstone:BAAANQADCgMIBAAAAA==.Conduit:BAABNQAECoEfAAMNAAkKwSQIAgC2AwANAAkKwSQIAgC2AwAOAAIKbSAIvgC6AAAAAA==.Coombrain:BAAANQADCgIIAwAAAA==.Cosmic:BAAANQADCgYIBgAAAA==.Cotopla:BAAANQAECgYIEgAAAA==.',
Cr='Crimsondream:BAAANQADCgcIBwAAAA==.',
Da='Dagov:BAAANQAECgIIAgAAAA==.Darkart:BAAANQADCgYICgAAAA==.Darkshivers:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
De='Deathlentlez:BAAANQAECgYIDgAAAA==.Decaylentlez:BAAANQAECgEIAQABNQAECgYIDgABAAAAAA==.Deepséeded:BAAANQADCgEIAQAAAA==.Delphyne:BAAANQAECgEIAQAAAA==.Demonhunter:BAAANQAECgQICAAAAA==.Demonià:BAAANQAECgEIAQAAAA==.',
Di='Dinkleberg:BAAANQABCgUIBgAAAA==.Disçiple:BAAANQADCggJEgAAAA==.',
Dj='Djazz:BAAANQADCgMIAwAAAA==.',
Dr='Drowsee:BAAANQAECgEIAQAAAA==.',
['Dà']='Dàrkscythe:BAAANQADCgEIAQAAAA==.',
Ea='Eazywin:BAAANQADCgUIBQAAAA==.',
Eh='Ehlsi:BAAANQAECgYIEQAAAA==.',
Ei='Eirinny:BAAANQADCggIDgAAAA==.',
El='Elindez:BAAANQAECgQIBAAAAA==.Elyviel:BAAANQAECgcICgAAAA==.',
Em='Emyrson:BAAANQADCgEIAQAAAA==.',
En='Encantado:BAAANQADCggJCAAAAA==.',
Eo='Eowen:BAAANQAECgYIEwAAAA==.',
Ep='Epitaph:BAAANQADCgUJBQAAAA==.',
Ez='Ezmee:BAAANQADCggIKQAAAA==.',
Fa='Faelicia:BAAANQADCgYIDQAAAA==.',
Fr='Frostdruid:BAAANQADCgEIAQAAAA==.Frowmae:BAAANQAECgUIBwAAAA==.',
Fu='Fundip:BAAANQAECgUIBwAAAA==.',
Fy='Fythra:BAAANQADCggIGwAAAA==.Fythri:BAAANQADCgcIFgABNQADCggIGwABAAAAAA==.',
Ga='Gart:BAAANQADCgcIBwAAAA==.',
Ge='Geolock:BAAANQAECgIIAgAAAA==.',
Gi='Gibbii:BAAANQADCgUIBQABNQAECggIHAAPADMXAA==.Gibhasarms:BAAANQADCgYIBgABNQAECggIHAAPADMXAA==.Giblock:BAABNQAECoEcAAIPAAgKMxdABABaAgAPAAgKMxdABABaAgAAAA==.Ginju:BAAANQAECgcIEgAAAA==.',
Go='Golomojek:BAAANQADCgYICgAAAA==.Govs:BAAANQADCgMIAwAAAA==.',
Gr='Gralmerte:BAAANQAECgYIEAAAAA==.Grawfern:BAAANQAECgYIEAAAAA==.Graziella:BAAANQADCgYICQABNQAECgQJBQABAAAAAA==.',
Gu='Guldave:BAAANQAECgMIAwAAAA==.Guthrie:BAAANQAECgUICQAAAA==.',
['Gø']='Gødøfwarz:BAAANQAECggICAAAAA==.',
Ha='Haether:BAAANQAECgYIDAAAAA==.',
He='Healforbeer:BAAANQADCgQIBAAAAA==.Healulngtime:BAAANQADCgQIBwAAAA==.Heiling:BAAANQAECgYIEAAAAA==.Hext:BAAANQADCgQIBAABNQAECgcIHQAQAKYSAA==.',
Ho='Holygral:BAAANQABCggIFAABNQAECgYIEAABAAAAAA==.Holymun:BAAANQAECgEIAQABNQAECgQJBAABAAAAAA==.Holyox:BAABNQAECoEZAAIRAAcKmQaIugA1AQARAAcKmQaIugA1AQAAAA==.',
Ht='Hturtle:BAAANQAECgIIAgAAAA==.Hturtledk:BAAANQAECggIBAAAAA==.',
Hy='Hyrri:BAAANQADCgMIAwABNQAECgcICgABAAAAAA==.',
['Hü']='Hüntress:BAAANQAECgYICAAAAA==.',
Ig='Ignuskore:BAAANQAECgEJAQAAAA==.',
Im='Imdatroll:BAAANQADCgMIAwABNQAECggIBgABAAAAAA==.Imgibby:BAAANQAECgQIBAABNQAECggIHAAPADMXAA==.',
In='Inexorable:BAABNQAECoEdAAIRAAgKuSKhHgAaAwARAAgKuSKhHgAaAwAAAA==.Interesting:BAAANQADCgYIBgAAAA==.',
Io='Iolegnaro:BAABNQAECoEWAAIJAAcK0yNjTQDBAgAJAAcK0yNjTQDBAgABNQAFFAUIDQAOABIlAA==.',
Ir='Ironfel:BAAANQADCgQIBAAAAA==.',
It='Itches:BAACNQAFFIEPAAISAAYKQR/3AQAxAgASAAYKQR/3AQAxAgA1AAQKgSsAAhIACQoTJqoBAL8DABIACQoTJqoBAL8DAAAA.',
Iz='Izry:BAAANQAECgcIDAAAAA==.',
Ja='Jaason:BAABNQAECoEXAAMDAAcKfxW5MwCiAQADAAcKvBO5MwCiAQAIAAYKMRFaWABMAQAAAA==.Jalen:BAAANQABCgQIBAAAAA==.Janvi:BAAANQADCgMIAwAAAA==.Jarico:BAAANQAECgIIAgABNQAECgQICAABAAAAAA==.',
Jh='Jhunts:BAAANQAECgYICwAAAA==.',
Ji='Jinfizz:BAAANQAECgIIAgAAAA==.Jinfuse:BAAANQAECgcIDwAAAA==.',
Jp='Jpdh:BAABNQAECoEeAAQFAAgKRSBYGwB4AgAFAAcKLR5YGwB4AgACAAcKQxmEIgD6AQATAAIKIiEfGADCAAAAAA==.Jpdumb:BAAANQADCggJCAABNQAECggIHgAFAEUgAA==.',
Ju='Juddory:BAAANQAECgIIBAAAAA==.Junksvil:BAAANQAECgQICAAAAA==.',
['Jø']='Jøhnwick:BAAANQADCgIIAgAAAA==.',
Kh='Khalyon:BAABNQAECoEcAAIJAAgKXRoMdwBZAgAJAAgKXRoMdwBZAgAAAA==.',
Ki='Killerelf:BAAANQADCgUIBQAAAA==.',
Ko='Koa:BAAANQAECgEIAQAAAA==.Korinth:BAEBNQAECoEgAAMRAAkKrBi4SABtAgARAAkKVxe4SABtAgAKAAIKGR0SQQCaAAAAAA==.',
Kr='Kriaalis:BAAANQADCgEIAQAAAA==.',
Ku='Kunitsu:BAAANQAECgQICwAAAA==.',
Ky='Kyra:BAAANQADCggIDgAAAA==.Kyril:BAABNQAECoEjAAIRAAkKAyFAGgAyAwARAAkKAyFAGgAyAwAAAA==.',
['Kæ']='Kælas:BAAANQADCgUIBQAAAA==.',
La='Lagabriela:BAAANQAECgYIEwAAAA==.Lazuli:BAAANQADCgQIBAABNQAECggIHgAFAOQgAA==.',
Le='Legault:BAAANQAECgUIDgAAAA==.Legionofboom:BAAANQADCgIIAgAAAA==.Lemanruss:BAAANQADCgQIBAAAAA==.Lethfel:BAAANQAECgUICwAAAA==.',
Li='Lillithfaust:BAAANQAECgEIAQAAAA==.Limbø:BAAANQAECgIIAgAAAA==.Lionfury:BAAANQAECgQIBQABNQAECggIGQARAL8XAA==.Lionguard:BAABNQAECoEZAAIRAAgKvxftaQAEAgARAAgKvxftaQAEAgAAAA==.Livie:BAAANQADCggIJQAAAA==.',
Lo='Loca:BAABNQAECoEXAAINAAcK2AOLkAAIAQANAAcK2AOLkAAIAQAAAA==.Lonelylad:BAAANQABCgIIAgAAAA==.Loraddesmos:BAAANQAECgcIEwAAAA==.Loáth:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.',
Lu='Lucance:BAAANQADCgQIBAAAAA==.',
Ly='Lyship:BAAANQAECgIIAgAAAA==.',
Ma='Maeg:BAAANQAECgYICgABNQAECggIBgABAAAAAA==.Mahll:BAAANQAECggICwAAAA==.Maidenchina:BAAANQAECgMIAwAAAA==.Maleveck:BAAANQAECgYIBgAAAA==.Marcato:BAAANQADCgEIAQABNQAECgQJBQABAAAAAA==.Marcdofu:BAAANQADCgQIBAAAAA==.Mardista:BAAANQADCgYIBgAAAA==.',
Mc='Mctanker:BAAANQAECgEIAgAAAA==.',
Me='Meascii:BAAANQAECggIEwAAAA==.Megavolt:BAAANQADCggICAABNQAFFAYIDwASAEEfAA==.Megs:BAAANQADCggJEwAAAA==.Memebeams:BAAANQAECgIIAgAAAA==.Merc:BAABNQAECoEhAAISAAkKQCA/CgAEAwASAAkKQCA/CgAEAwAAAA==.',
Mi='Miluo:BAAANQAECgMIBQABNQAECgcIEwABAAAAAA==.Mindpuck:BAAANQADCgcIDAAAAA==.Mintchyp:BAAANQAECgQIBAAAAA==.Mirefighter:BAAANQAECgIIAgABNQAECgkJIAAUAAchAA==.Mirespike:BAABNQAECoEgAAMUAAkKByF4AwAsAwAUAAkKByF4AwAsAwAVAAEK+w8qlAAvAAAAAA==.Missroxy:BAAANQADCgEIAQAAAA==.Mistbrew:BAAANQAECgYIBgAAAA==.',
Mo='Modin:BAAANQAECgIIAgAAAA==.Mommacougar:BAAANQADCgIJAgAAAA==.Moon:BAAANQADCgUICgABNQADCgYICQABAAAAAA==.Morlis:BAAANQADCgcIGgAAAA==.Morlock:BAAANQAECgcIEQAAAA==.Morningstahr:BAABNQAECoEZAAIJAAgK8xjNdABfAgAJAAgK8xjNdABfAgAAAA==.',
Mu='Munion:BAAANQAECgQJBAAAAA==.',
Mv='Mvp:BAAANQADCgQIBAAAAA==.',
['Mô']='Môrningstar:BAAANQADCgUIBQAAAA==.',
Na='Naaruto:BAAANQADCgEIAQAAAA==.Nanako:BAAANQADCgcIHQAAAA==.Naravanta:BAAANQADCgUIBQAAAA==.Naughtyreapr:BAAANQADCgEIAQABNQAECgQIBwABAAAAAA==.Naughtyvoked:BAAANQADCgUICQABNQAECgQIBwABAAAAAA==.',
Ne='Nevicus:BAAANQADCgEJAQAAAA==.',
Ni='Nickayla:BAAANQADCggIIQAAAA==.Nikkaya:BAAANQADCgYJBgABNQAECgQICAABAAAAAA==.Nimblecow:BAAANQADCgEIAQAAAA==.',
No='Noobacleese:BAAANQAECgcIEgAAAA==.Noraviae:BAAANQADCgMIBgAAAA==.',
Ny='Nyghtrider:BAAANQAECgQICAAAAA==.Nymëra:BAAANQAECgUIDwAAAA==.Nyneeve:BAAANQAECgYIDwAAAA==.',
Od='Odinshunter:BAAANQADCgIIAgAAAA==.',
Ol='Olgrin:BAAANQADCgUIBQABNQADCgcIEgABAAAAAA==.',
On='Onepunch:BAAANQADCgcIBwAAAA==.Oneslice:BAAANQADCgYIBgAAAA==.',
Or='Orw:BAAANQADCgMIAwAAAA==.',
Pa='Palpatinee:BAAANQAECgUIBQAAAA==.Papitochulo:BAAANQADCgUIBQAAAA==.Parabelum:BAAANQADCgYICAAAAA==.Partita:BAAANQAECgQJBQAAAA==.',
Pb='Pbób:BAAANQAECggIAwAAAA==.',
Pe='Percocetpete:BAABNQAECoEUAAMHAAkKHxYmMwBYAgAHAAcKuxomMwBYAgALAAgKZAd1MABOAQAAAA==.Peregrine:BAAANQADCgIIAgAAAA==.',
Ph='Phaet:BAABNQAECoEjAAMWAAkKYiAXJwCyAgAWAAgKkiAXJwCyAgAXAAQKBxXPKwALAQAAAA==.Phaux:BAAANQADCgcIGgAAAA==.',
Pi='Piper:BAAANQADCgQICAAAAA==.',
Pl='Plâgue:BAABNQAECoEaAAIYAAgKkR0THwCIAgAYAAgKkR0THwCIAgAAAA==.',
Pr='Prot:BAAANQADCgUJBQAAAA==.',
Pu='Punslug:BAAANQADCgMIAwABNQAECgcIFwAUAB8mAA==.Puntthegnome:BAAANQADCgEIAQABNQAFFAUIDgAJALoPAA==.',
Ra='Rainforest:BAAANQAECgQICAAAAA==.Ramden:BAAANQAECgcIEQAAAA==.Rampant:BAAANQAECgcIDgAAAA==.Rampscii:BAAANQAECgIIAgABNQAECgcIDgABAAAAAA==.Randolier:BAAANQAECgcIEgAAAA==.Ratherton:BAACNQAFFIEOAAIJAAUKug88EgCVAQAJAAUKug88EgCVAQA1AAQKgSoAAgkACQr6IKoVAG0DAAkACQr6IKoVAG0DAAAA.Rathtard:BAAANQAECgcIDwABNQAFFAUIDgAJALoPAA==.Rauzer:BAAANQABCgIJAgAAAA==.Razz:BAAANQABCgIIAgAAAA==.',
Re='Renuwu:BAABNQAECoEfAAIHAAcKMgmDcABeAQAHAAcKMgmDcABeAQAAAA==.Resoluteone:BAABNQAECoEbAAIIAAgK2gUIXQA2AQAIAAgK2gUIXQA2AQAAAA==.Retnu:BAAANQADCgQICAAAAA==.Revelations:BAAANQADCggIDgABNQAECgkJHwANAMEkAA==.Revytwohand:BAABNQAECoEmAAISAAkKAR6qDgC9AgASAAkKAR6qDgC9AgAAAA==.',
Rh='Rhok:BAAANQADCggIFQAAAA==.',
Ro='Robonome:BAAANQADCgUIBQAAAA==.',
Ru='Rumii:BAAANQAECgIIAwAAAA==.',
['Rë']='Rëápër:BAAANQADCgIIAgAAAA==.',
Sa='Sabeladys:BAAANQAECgYICQAAAA==.Saifir:BAAANQAECgYIEAAAAA==.Sardmagia:BAAANQAECgIIAgABNQAECgUJDAABAAAAAA==.Sardmongo:BAAANQAECgEIAQAAAA==.Sarduccini:BAAANQAECgUJDAAAAA==.',
Sh='Shiftken:BAAANQADCgMIAwAAAA==.Shoktherapy:BAAANQAECgUICwAAAA==.',
Si='Silvalus:BAAANQADCgcIEgAAAA==.Silvertide:BAABNQAECoEXAAMOAAcKcRHbWwC9AQAOAAcKcRHbWwC9AQANAAQKnQlYugChAAAAAA==.Sin:BAAANQADCgMIAwAAAA==.',
Sk='Skyeforce:BAAANQADCggIDgAAAA==.',
Sl='Slipknoth:BAAANQAECgEIAQAAAA==.',
So='Soi:BAAANQAECgcIEwAAAA==.Solvent:BAAANQADCgYIBgAAAA==.Sondaar:BAAANQABCgcIDAAAAA==.Sonoforak:BAAANQAECgMJAwAAAA==.',
Sp='Sped:BAABNQAECoEWAAIZAAcKkiBcCACBAgAZAAcKkiBcCACBAgAAAA==.',
St='Staraleena:BAAANQAECgQIBAAAAA==.Stiffyhaze:BAAANQAECgQIBAAAAA==.Stillwët:BAAANQABCggICwAAAA==.Stingyr:BAAANQAECgIIAgAAAA==.Stormslight:BAAANQADCggIFQAAAA==.Stormsteel:BAAANQADCgYIBgAAAA==.Stossel:BAAANQAECgQIBAAAAA==.',
Sw='Sweetie:BAAANQADCgYICgAAAA==.',
Ta='Talas:BAAANQAECgcIEgAAAA==.Tanksabunch:BAAANQAECggIEAABNQAFFAcIEwAaAHAhAA==.',
Te='Tehmay:BAAANQADCgIIAgAAAA==.Tenssid:BAAANQADCggIGAAAAA==.Terrormisu:BAAANQADCgUIBQABNQAECgUIEAABAAAAAA==.',
Th='Thorclap:BAAANQAECgEJAQAAAA==.Thundertaker:BAAANQADCgQIBAAAAA==.',
Ti='Tim:BAAANQADCggJCgABNQAECgcIGQAGALgZAA==.',
To='Tooru:BAABNQAECoEkAAMbAAkK4RtCMwCQAgAbAAgKBx1CMwCQAgAaAAgKug9zKAC6AQAAAA==.',
Tr='Triena:BAAANQADCggJCAAAAA==.Trimas:BAAANQAECgEIAQAAAA==.',
Tw='Twinkles:BAABNQAECoEXAAMQAAgKyg5aVgDPAQAQAAgKyg5aVgDPAQARAAEKzwdLUwEwAAAAAA==.Twotoetimmy:BAAANQAECgIIAgAAAA==.',
Ul='Ulysius:BAAANQAECgYIEwAAAA==.',
Un='Unfazed:BAAANQADCgIIAgAAAA==.',
Va='Valkisek:BAAANQAECgcIEgAAAA==.Vallarfax:BAAANQAECgcIEgAAAA==.Vandro:BAABNQAECoEdAAIQAAcKphI3XgCxAQAQAAcKphI3XgCxAQAAAA==.Vashdk:BAABNQAECoEkAAIIAAkKoCMnBwBvAwAIAAkKoCMnBwBvAwAAAA==.',
Ve='Velcyn:BAAANQAFFAEIAgAAAA==.Veloranas:BAABNQAECoEeAAMJAAkK6xLMdwBXAgAJAAkKQBHMdwBXAgAMAAMK3xEPHwC0AAAAAA==.Venjince:BAAANQADCgYIBgAAAA==.Venôm:BAAANQADCgQIBAAAAA==.Vespyr:BAAANQADCggIIQABNQAECgIIAgABAAAAAA==.Vewdoo:BAAANQAFFAEIAQAAAA==.Vexiara:BAAANQADCgcIDwABNQAECgcICgABAAAAAA==.',
Vi='Vizimir:BAAANQADCggIIwAAAA==.',
Vy='Vynstabbin:BAAANQAECgUJCgAAAA==.',
Wa='Waiwai:BAAANQADCgcIBwAAAA==.Warfarin:BAAANQADCgMIAwAAAA==.Wascii:BAAANQAECgQIBQABNQAECgcIDgABAAAAAA==.',
We='Weaken:BAAANQAECgYIBgAAAA==.',
Wh='Whiskeybear:BAAANQADCgUIBQAAAA==.',
Wi='Willy:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Wizkerbizkit:BAAANQAECgUICgAAAA==.',
Wo='Wolfcaza:BAAANQADCgcIDgAAAA==.Wolvesbane:BAAANQAECggICQAAAA==.Wooshira:BAAANQADCgUIDgAAAA==.',
Wy='Wyrmheal:BAABNQAECoEeAAILAAgKEyGRDADzAgALAAgKEyGRDADzAgAAAA==.Wyvvie:BAAANQAECgcIDgAAAA==.',
Ya='Yamihime:BAABNQAECoEYAAIFAAcKXxrAKAAGAgAFAAcKXxrAKAAGAgAAAA==.Yatiri:BAAANQAECgUIBQAAAA==.',
Za='Zalinis:BAAANQADCgYICAAAAA==.Zambas:BAAANQAECgMIAwAAAA==.',
Ze='Zeaket:BAACNQAFFIEPAAIcAAUKDhw5AADwAQAcAAUKDhw5AADwAQA1AAQKgSgAAhwACQoqJWUAALkDABwACQoqJWUAALkDAAAA.Zephyr:BAAANQADCgYIFQABNQAECgIIAgABAAAAAA==.Zerrayna:BAAANQADCgYICwAAAA==.Zeçhs:BAAANQADCgYIBgABNQAECgcIEwABAAAAAA==.',
Zi='Zinbad:BAAANQADCgYIGgAAAA==.',
Zo='Zorcan:BAAANQADCggIJgAAAA==.',
Zu='Zugzugz:BAAANQAECggICAAAAA==.Zulfilith:BAAANQADCgcIGgAAAA==.',
['Zà']='Zàrgothrax:BAAANQADCgYIBgAAAA==.',
['Ãi']='Ãinz:BAAANQADCgIIAgAAAA==.',
['Ða']='Ðachee:BAAANQAECgUICwAAAA==.',
['Ðo']='Ðora:BAAANQADCgMIAwAAAA==.',
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
