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

local lookup = {'Mage-Frost','Unknown-Unknown','Hunter-BeastMastery','Rogue-Outlaw','Warrior-Arms','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','Rogue-Assassination','Druid-Guardian',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=53,date='2026-09-15',data={Ad='Adhira:BAAANQADCgYIDQAAAA==.',
Ae='Aegennai:BAAANQAECgMIAwAAAA==.Aegondk:BAEANQAFFAEIAQAAAA==.Aelias:BAAANQADCgcIFQAAAA==.Aevaela:BAAANQAECgYIDQAAAA==.',
Ag='Agilaz:BAAANQAECgQIBgAAAA==.',
Ak='Akey:BAAANQADCggIDgAAAQ==.Akhae:BAAANQAECgYIDgAAAA==.',
Al='Albinism:BAAANQAECgEIAQAAAA==.Alcadeias:BAAANQADCgcIEwAAAA==.Alethiah:BAAANQAECgEIAQAAAA==.Allastor:BAAANQADCgIIAgAAAA==.',
An='Anaeda:BAAANQAECgIIAwAAAA==.Andrömëdä:BAAANQADCggIEAAAAA==.Angryjim:BAAANQADCgUIBQAAAA==.Anubisre:BAAANQADCgQIBQAAAA==.Anzulay:BAAANQADCgMIAwAAAA==.',
Aq='Aquindra:BAAANQADCgYICwAAAA==.',
Ar='Aralleda:BAAANQABCgIIAgAAAA==.Arccane:BAAANQAECgIIAgAAAA==.Arthar:BAAANQAECgcIEgAAAA==.',
As='Ashvyth:BAAANQAECgQIBQAAAA==.',
Aw='Awwyeah:BAAANQADCgIIAgABNQAECgkJHgABANIcAA==.',
Az='Azuredeath:BAAANQABCgQIBAAAAA==.Azurehope:BAAANQABCgUIBQAAAA==.',
Ba='Baconpancake:BAAANQADCgcIDgAAAA==.Baldpunch:BAAANQADCggIFgAAAA==.Balinor:BAAANQADCgcIBwAAAA==.Ballz:BAAANQADCgYIBgAAAA==.Balom:BAAANQADCgcIBwAAAA==.Balomdruid:BAAANQADCgUIBQABNQADCgcIBwACAAAAAA==.Barnabus:BAAANQAECgIIBgAAAA==.',
Be='Beachbecrazy:BAAANQAECgQIBAAAAA==.Beaj:BAAANQADCggIEAAAAA==.Beastlypläyä:BAAANQADCgIIAgAAAA==.Belládonna:BAAANQADCggICAAAAA==.Bessarion:BAAANQADCgUIAgAAAA==.',
Bi='Bigandbeefy:BAAANQAECgEIAQAAAA==.Bilac:BAAANQADCgEIAQABNQAECgYIDwACAAAAAA==.',
Bl='Blusoleil:BAAANQADCggIEAAAAA==.',
Bo='Bonerblast:BAAANQADCggICgAAAA==.Boston:BAAANQAECgYIBwAAAA==.',
Br='Branches:BAAANQAECgUIBgAAAA==.Brewtholomew:BAAANQAECgUICgAAAA==.Briggsey:BAAANQAECgMIBAAAAA==.Briznot:BAAANQAECgEIAQAAAA==.Bruh:BAAANQAECgQIBAAAAA==.Bryce:BAAANQAECgEIAQAAAA==.Brèanna:BAAANQADCgMIBQAAAA==.',
Bu='Bubbadubya:BAAANQADCgYIEAAAAA==.Bunnyfu:BAAANQADCgcIDQABNQAECgYIDwACAAAAAA==.Burningwolf:BAAANQAECgQICAAAAA==.',
['Bó']='Bórs:BAAANQAECgMIBAAAAA==.',
Ca='Caiden:BAAANQADCgcIDQAAAA==.Caitlyn:BAAANQADCgEIAQAAAA==.Caleesia:BAAANQADCgYICwAAAA==.Carnìfex:BAAANQADCgcIFwAAAA==.Caskaerta:BAAANQADCgYIBgAAAA==.Catbrin:BAAANQAECgIIAgAAAA==.',
Ce='Cerà:BAAANQADCggIEAAAAA==.',
Ch='Chapslop:BAAANQADCgcIDAAAAA==.Cheetah:BAAANQADCgMIBQAAAA==.',
Cl='Clizee:BAAANQABCgQIAwAAAA==.Clobberben:BAAANQADCgQIBAAAAA==.Cloudbreaker:BAAANQADCggIBwAAAA==.',
Co='Cobramage:BAAANQAECgEIAQAAAA==.Constellate:BAAANQAECgQIBQAAAA==.Cotterpins:BAAANQAECgEIAQAAAA==.',
Cr='Cruicible:BAAANQADCgcIDAAAAA==.',
Cy='Cybrkatz:BAAANQADCgIIAgAAAA==.',
Cz='Cztalone:BAAANQADCgQIBAAAAA==.',
['Cè']='Cèlane:BAAANQAECgUICwAAAA==.',
Da='Damitsu:BAEANQADCgYIEQABNQADCggIGAACAAAAAA==.Damnitsu:BAEANQADCggIGAAAAA==.Darckside:BAAANQADCgUIBQAAAA==.Dazen:BAAANQADCgMIBQAAAA==.',
De='Deadflexy:BAAANQAECgEIAQAAAA==.Deathberry:BAAANQAECgQIBgAAAA==.Deathdoodles:BAAANQADCggIDwABNQAECgcIDQACAAAAAA==.Deathvoker:BAAANQADCgYICwAAAA==.Deekan:BAAANQAECgQIBQAAAA==.Dejavù:BAAANQAECgIIAgAAAA==.Demonblood:BAAANQAECgUICgAAAA==.Deräth:BAAANQAECgIIAgAAAA==.Devlik:BAAANQADCgYIBwAAAA==.Dew:BAAANQADCgYIBgABNQADCgYICgACAAAAAA==.',
Di='Dimensius:BAAANQAECgQIBQAAAA==.Dinkalopogis:BAAANQADCgQICQAAAA==.Dionne:BAAANQAECgEIAQAAAA==.Ditsie:BAAANQADCggIEgAAAA==.',
Dm='Dmega:BAAANQADCggIGgAAAA==.',
Do='Dogfunk:BAAANQABCgYICgAAAA==.',
Dr='Dragea:BAAANQAECgEIAQAAAA==.Dragondude:BAAANQAECgQIBAAAAA==.Dragonsgrasp:BAAANQADCgUIBAAAAA==.Drizzít:BAAANQAECgUIBQAAAA==.',
Du='Durango:BAAANQAECgEIAQAAAA==.',
Dy='Dyelin:BAAANQAECgQIBQAAAA==.',
El='Elylle:BAAANQADCgMIBAABNQADCgYIBgACAAAAAA==.Elyron:BAAANQAECgQIBQAAAA==.',
En='Endofall:BAAANQAECgEIAgAAAA==.',
Ep='Epiczimbabue:BAAANQADCgEIAQAAAA==.',
Es='Esrahaddon:BAAANQAECgUICQAAAA==.Estella:BAAANQADCgYIBgAAAA==.',
Et='Et:BAAANQAECgEIAQAAAA==.Etheri:BAAANQADCgYICgAAAA==.',
Ez='Ezhra:BAAANQABCgEIAQABNQADCgYICwACAAAAAA==.Ezind:BAAANQADCggICAAAAA==.',
Fa='Fakename:BAAANQAECgQIBAAAAA==.Fakesaint:BAAANQAECgUIDAAAAA==.Fangstorm:BAAANQAECgQIBQAAAA==.Farorê:BAAANQADCgYIDAAAAA==.Fazz:BAAANQADCgYICQAAAA==.',
Fe='Feldruid:BAAANQAECgQIBQAAAA==.Felup:BAAANQAECgUICwAAAA==.',
Fo='Folstagg:BAAANQADCgcIDAAAAA==.Foreverem:BAAANQADCgYIBgAAAA==.',
Fr='Frostynewf:BAAANQADCgYIBgAAAA==.',
Fu='Fujitora:BAAANQAECgQIBwAAAA==.',
Gi='Gideòn:BAAANQADCgQIBAAAAA==.',
Gl='Glenys:BAAANQADCgEIAQAAAA==.',
Go='Gopao:BAAANQADCgUIAgABNQAECgEIAQACAAAAAA==.',
Gr='Graxus:BAAANQADCgYICgAAAA==.Greth:BAAANQADCgYIEAAAAA==.Grimlin:BAAANQADCggIBgAAAA==.',
Gu='Gudge:BAAANQAECgYIDwAAAA==.Gummypenguin:BAAANQAECgcIEAABNQAECgkJJwADAKMkAA==.',
Ha='Hadhox:BAAANQADCgcIGAABNQAECgQIBAACAAAAAA==.Hathdox:BAAANQAECgQIBAAAAA==.Hawkulees:BAAANQADCgYIDQAAAA==.Hazelnoot:BAAANQAECgUICwAAAA==.',
He='Healzofdeath:BAAANQADCgcIDAAAAA==.Hegaphie:BAAANQADCgEIAQAAAA==.Hexcist:BAAANQAECgQIBAAAAA==.',
Hi='Hitsuryu:BAAANQAECgMIAwAAAA==.',
Ho='Hochma:BAAANQADCgEIAQAAAA==.Hokogo:BAAANQADCgEIAQAAAA==.Holdon:BAAANQAECgUICgAAAA==.Hollyanne:BAAANQAECgEIAQAAAA==.Hoonicorn:BAAANQADCgEIAQABNQADCgIIAgACAAAAAA==.Hornsharp:BAAANQADCgcIDgAAAA==.',
Hu='Hunalli:BAAANQADCgUIBwABNQAECgYIDwACAAAAAA==.Hunilla:BAAANQADCggIDgABNQAECgYIDwACAAAAAA==.',
Ia='Iamu:BAAANQADCgQICgAAAA==.',
Ib='Ibris:BAAANQADCgMIBQAAAA==.',
Ic='Iconius:BAAANQADCgMIBQAAAA==.',
Ie='Ieatwetsocks:BAAANQAECgYIEwAAAA==.',
Ig='Ignivar:BAAANQADCgYIFAAAAA==.',
In='Indra:BAAANQADCggIAwAAAA==.Innexshaman:BAAANQADCgYIBgABNQADCggIEAACAAAAAA==.Insaint:BAAANQAECgQIBAAAAA==.',
Ir='Ironfield:BAAANQAECgUIBgABNQADCgUIBQACAAAAAA==.Irony:BAAANQAECgMIAgAAAA==.Irtank:BAAANQADCgEIAQAAAA==.',
Is='Isabellë:BAAANQAECgQIBgAAAA==.',
Je='Jessamine:BAAANQAECgUICwAAAA==.Jetta:BAAANQAECgEIAQAAAA==.Jezzak:BAAANQAECgQIBgABNQAECgQICQACAAAAAA==.',
Jo='John:BAABNQAECoEfAAIEAAcJ8SJDAwCXAgAEAAcJ8SJDAwCXAgAAAA==.Jorien:BAAANQAECgUICAAAAA==.',
Jp='Jp:BAAANQADCgQIBQABNQAECgQIBAACAAAAAA==.Jpd:BAAANQAECgQIBAAAAA==.',
Ju='Justadwarf:BAAANQADCgcICQAAAA==.Juston:BAAANQAECgUIBQAAAA==.',
Ka='Kaboonsky:BAAANQAECgQICQAAAA==.Kaeamani:BAAANQADCgYIBwAAAA==.Kaenaya:BAAANQADCgIIAgAAAA==.Kamikori:BAAANQAECgMIAwAAAA==.Kardell:BAAANQADCgYIDAAAAA==.Kardels:BAAANQADCgQIBAABNQADCgYIDAACAAAAAA==.Karnadaz:BAABNQAECoEdAAIFAAkJFRisJQC2AgAFAAkJFRisJQC2AgAAAA==.Karnkarn:BAAANQAECgQIBAAAAA==.Karnn:BAAANQADCggIDgAAAA==.Katalight:BAAANQADCgEIAQABNQADCggIDQACAAAAAA==.',
Ke='Keho:BAAANQAECgIIAwABNQAECgUIDwACAAAAAA==.',
Ki='Kiascendance:BAAANQAECgYIEAAAAA==.',
Ko='Kolosho:BAAANQADCgcIEwAAAA==.Korxana:BAAANQAECgQIBAAAAA==.Korxon:BAAANQAECgYIDgAAAA==.Kotus:BAAANQADCgcIDQAAAA==.',
Ks='Ksyusha:BAAANQADCggICAAAAA==.',
Ky='Kyfess:BAAANQADCggIBwABNQADCggICAACAAAAAA==.',
['Kä']='Kämi:BAAANQADCgUIBgABNQAECgEIAQACAAAAAA==.',
La='Lanuadra:BAAANQAECgYIDQAAAA==.Lawry:BAAANQAECgYIBgAAAA==.',
Le='Leasidhe:BAAANQADCgcIDgABNQADCgQIBAACAAAAAA==.Lethalbimbo:BAAANQADCgMIBQAAAA==.',
Lg='Lghtninstorm:BAAANQADCgEIAQAAAA==.',
Li='Likhan:BAAANQABCgQIBAABNQADCgcIBwACAAAAAA==.Lillié:BAAANQABCgIIAQAAAA==.Lilysham:BAABNQAECoEfAAMGAAkJcCGoCwALAwAGAAkJcCGoCwALAwAHAAYJQBOyQwCeAQAAAA==.Lindar:BAAANQABCgMIBAAAAA==.Linddrel:BAAANQAECgEIAgAAAA==.',
Lo='Lomea:BAAANQADCgYIBgAAAA==.Lonarius:BAAANQABCgQIBQAAAA==.',
Lu='Lunasblood:BAAANQABCgIIAgAAAA==.',
['Lá']='Ládylumps:BAAANQADCgcIBwABNQAECgQIBAACAAAAAA==.',
['Lø']='Løllîe:BAAANQADCgYIBgAAAA==.',
Ma='Macarius:BAAANQAECgEIAQAAAA==.Macdee:BAAANQADCgMIAwABNQAECgQICAACAAAAAA==.Magatai:BAAANQADCgUIBQAAAA==.Mageless:BAAANQADCgIIAgAAAA==.Magpie:BAAANQADCgYIDAAAAA==.Maimed:BAAANQAECgIIAgAAAA==.Malotan:BAAANQABCgEIAQABNQABCggICAACAAAAAA==.Manaster:BAAANQADCggIEAAAAA==.Manpriest:BAAANQADCgEIAQAAAA==.Maravanna:BAAANQADCgEIAQAAAA==.Martlok:BAAANQAECgEIAQAAAA==.Mathas:BAAANQADCgYIDQAAAA==.Maynis:BAAANQABCgQIBgAAAA==.Maysaveyou:BAAANQADCgQIBAAAAA==.',
Mc='Mcbrynhammer:BAAANQADCgUICwAAAA==.',
Me='Meanwhile:BAAANQADCgUIAgAAAA==.Meowmixx:BAAANQABCgUIBQAAAA==.Merkii:BAAANQADCgYIBgABNQAECgYIBgACAAAAAA==.',
Mi='Micflinigan:BAAANQAECgQIBAAAAA==.Milkymoomoo:BAAANQADCgQIBAAAAA==.Minarii:BAAANQAECgEIAQAAAA==.Minilove:BAAANQADCgIIAwAAAA==.Mishelö:BAAANQADCgYIBAAAAA==.Misla:BAAANQABCgYIBgAAAA==.',
Mo='Mochimochi:BAAANQADCgQIBAAAAA==.Mommieuppies:BAAANQADCgcICAAAAA==.Momomochi:BAAANQADCgcIBwAAAA==.Moonshae:BAAANQAECgUICwAAAA==.Mortalbion:BAAANQADCggIEgAAAA==.',
My='Mystiquè:BAAANQADCgYIEAAAAA==.',
Na='Naithin:BAAANQAECgEIAQAAAA==.Nalarah:BAAANQADCgQIBAAAAA==.Naviriel:BAAANQADCgYIAwABNQAECgEIAQACAAAAAA==.',
Ne='Nerrf:BAAANQADCgUIBQAAAA==.',
Ni='Nightray:BAAANQAECgQIBgABNQAECgcIEgACAAAAAA==.',
No='Noknik:BAAANQABCggICAAAAA==.Nonsocial:BAABNQAFFIEHAAIIAAYJog3SAADHAQAIAAYJog3SAADHAQAAAA==.Noriisa:BAAANQAECgQICQAAAA==.Notamathguy:BAAANQADCggIDgAAAA==.Noudders:BAAANQAECgQIBgAAAA==.',
Ny='Nyvak:BAAANQADCgcIDgAAAA==.',
Od='Odinhand:BAAANQAECgUICwAAAA==.',
Oh='Ohgreatdink:BAAANQADCgYIBgAAAA==.',
Ol='Oliissa:BAAANQADCgYIEAAAAA==.',
Oz='Ozwäldo:BAAANQAECgcIEwAAAA==.',
Pa='Pandapí:BAAANQADCgYIBgAAAA==.Panduh:BAAANQAECgcIDgAAAA==.Pandóra:BAAANQADCgcIDgAAAA==.Pariousa:BAABNQAECoEdAAIJAAkJWCL9AgBaAwAJAAkJWCL9AgBaAwAAAA==.',
Pe='Peppermintxo:BAAANQADCgYICQABNQADCgIIAgACAAAAAA==.',
Ph='Phaite:BAAANQAECggIAQAAAA==.',
Pi='Pinkeepink:BAAANQADCgYIFgAAAA==.',
Po='Popacooldown:BAAANQADCgUIBwAAAA==.',
Pr='Pres:BAAANQAECgIIAwAAAA==.Prild:BAAANQABCgQIBgAAAA==.',
Pu='Pumpernickle:BAAANQAECgQIBAAAAA==.',
Ra='Rahzon:BAAANQAECgIIAgAAAA==.Ralganor:BAAANQAECgUICwAAAA==.Ralzin:BAAANQADCgUIDQAAAA==.Ramanash:BAAANQADCgQICAAAAA==.Raynlight:BAAANQADCggIHQAAAA==.',
Re='Ren:BAAANQADCgUIBwAAAA==.Retacus:BAAANQADCgYICwAAAA==.',
Ri='Rina:BAAANQAFFAEIAQAAAA==.Ringadingg:BAAANQAECgQIBQAAAA==.',
Ro='Rosequartz:BAAANQADCggIDQAAAA==.',
Ry='Rydia:BAAANQAECgIIAwAAAA==.',
Sa='Saladin:BAAANQADCgUIBgAAAA==.Sankatlantis:BAAANQADCgYICgAAAA==.Sarka:BAAANQADCgcIBwAAAA==.Sasquatch:BAAANQAECgEIAQAAAA==.Saunkae:BAAANQAECgEIAQAAAA==.',
Sc='Scony:BAAANQAECgQIBQAAAA==.Scribs:BAAANQADCgcIEAAAAA==.Scyphen:BAAANQADCgYICQAAAA==.',
Se='Seegon:BAAANQABCgYIBQAAAA==.Seismic:BAAANQADCggICAAAAA==.Sephirain:BAAANQADCgMIAwAAAA==.Sevelement:BAAANQAECgMIAwABNQAECgYIDQACAAAAAA==.Severànce:BAAANQAECgYIDQAAAA==.Sevivify:BAAANQADCgIIAwABNQAECgYIDQACAAAAAA==.',
Sh='Shablammy:BAAANQAECgMIAwAAAA==.Shadowginni:BAAANQAECgIIAgAAAA==.Shadownome:BAAANQADCgMIBQAAAA==.Shammygand:BAAANQADCgUIBQABNQAECgQIBgACAAAAAA==.Shanker:BAAANQADCgMIAwAAAA==.Shefu:BAAANQAECgMIBQAAAA==.Shfifty:BAAANQAECgcIDQAAAA==.Shutupbird:BAAANQAECgQIBgAAAA==.',
Si='Silris:BAAANQADCgMIAwAAAA==.',
Sk='Skydragon:BAAANQADCgYIEQAAAA==.',
Sl='Slay:BAAANQADCggIDQABNQAECgUICAACAAAAAA==.Slonk:BAAANQADCggIEgAAAA==.',
So='Sofia:BAAANQAECgEIAQAAAA==.',
Sp='Sparrtacus:BAAANQABCgUIBwAAAA==.Spiritly:BAAANQAECgEIAQAAAA==.Sploof:BAAANQADCggIDgAAAA==.Sprynt:BAAANQAECgMIAwAAAA==.',
St='Staples:BAAANQADCgUIAgABNQAECgEIAQACAAAAAA==.Starlighter:BAAANQADCgYIBgAAAA==.Starmist:BAAANQADCgYIEAAAAA==.Stubly:BAAANQADCgQIBAAAAA==.',
Su='Sunfyrie:BAAANQADCggIFgAAAA==.',
Sw='Sweèt:BAAANQADCgYICwAAAA==.',
Ta='Tagrit:BAAANQADCgUIBQAAAA==.Taldieth:BAAANQADCggIDwAAAA==.Taurdk:BAAANQAECgEIAgAAAA==.Taylorshift:BAAANQAECgQIBAAAAA==.',
Te='Teaar:BAAANQADCgUIBQABNQAECgUICAACAAAAAA==.Teetau:BAAANQAECgQIBQAAAA==.',
Th='Thadregosa:BAAANQAECgQIBQAAAA==.Thalsan:BAAANQABCgIIAgAAAA==.Thander:BAAANQADCgYIDwAAAA==.Therlisa:BAAANQADCggICAAAAA==.Thordar:BAAANQABCggICwAAAA==.',
Ti='Tibbotanical:BAAANQADCgUIBQAAAA==.Tiberius:BAAANQABCgIIAQAAAA==.Tiffy:BAAANQADCgYIDwAAAA==.Tirna:BAAANQAECgEIAQAAAA==.Tirnotham:BAAANQADCggIDgAAAA==.',
Tm='Tmtglizzy:BAAANQAECgQIBQAAAA==.',
To='Tokalu:BAAANQAECgEIAQAAAA==.Tonjudsonson:BAABNQAECoEdAAIKAAkJMyL4AACLAwAKAAkJMyL4AACLAwAAAA==.Torath:BAAANQADCgUIBQABNQADCgYIDwACAAAAAA==.',
Tu='Turdimer:BAAANQADCgYIEgAAAA==.',
Tw='Twiki:BAAANQAECgEIAQAAAA==.Twobricks:BAAANQAECgUICwAAAA==.',
Ty='Tyrssana:BAAANQADCggIDgABNQAECgYIDAACAAAAAA==.',
['Tö']='Töketsu:BAAANQADCgYIBgAAAA==.',
Uh='Uhmerica:BAAANQAECgUICwAAAA==.',
Ur='Urdeadtoo:BAAANQAECgMIAgAAAA==.Urlacher:BAAANQADCgEIAQAAAA==.Urthkwayk:BAAANQADCgYIBgAAAA==.',
Va='Vaedryn:BAAANQADCgUIBQAAAA==.Vaterunser:BAAANQADCggIDgAAAA==.Vazoom:BAAANQAECgIIAwAAAA==.',
Ve='Velskud:BAAANQADCgYIDwAAAA==.Vertexx:BAAANQADCgYIBgAAAA==.',
Vi='Vierth:BAAANQADCgIIAgABNQADCgYIBgACAAAAAA==.Vinhar:BAAANQADCgUICAAAAA==.Visea:BAAANQADCgIIAgABNQADCgYIBgACAAAAAA==.',
Vo='Voidsavage:BAAANQADCgYIFAAAAA==.Voidwing:BAAANQAECgQIBAAAAA==.Volic:BAAANQAECgQIBQAAAQ==.Vollken:BAAANQADCgYICAAAAA==.Voznje:BAAANQAECgEIBAAAAA==.',
We='Wesleypipes:BAAANQAECgQIBgAAAA==.',
Wh='Whisteria:BAAANQADCgYIBgAAAA==.',
Wi='Wizalf:BAAANQADCggICgAAAA==.',
Wo='Wodalpala:BAAANQAECgcIBwAAAA==.Wolfmato:BAAANQAECgYICwAAAA==.',
Wy='Wynne:BAAANQADCgYICgAAAA==.',
Xa='Xalabro:BAAANQAECgMIAwAAAA==.',
Xe='Xerxeis:BAAANQABCgYICAABNQADCgcIEwACAAAAAA==.',
Xo='Xousa:BAAANQADCgQIBgABNQAECgkJHQAJAFgiAA==.',
Yh='Yhorn:BAAANQADCgcIBwABNQAECgkJHwAGAHAhAA==.',
Ys='Yssuplef:BAAANQADCggIDgAAAA==.',
Za='Zaiyra:BAAANQADCgcIDwAAAA==.Zakoor:BAAANQADCgYIFAAAAA==.Zareena:BAAANQADCgYIEAAAAA==.Zarnia:BAAANQADCgMIAwAAAA==.Zarrock:BAAANQADCgIIAgAAAA==.Zavatan:BAAANQADCgQIBwAAAA==.',
Ze='Zebbyzebzeb:BAAANQADCgYIEwAAAA==.Zekia:BAAANQAECgQICAAAAA==.Zepirra:BAAANQABCgcIDgAAAA==.Zerm:BAAANQAECgQICAAAAA==.',
Zi='Zinnkura:BAAANQADCggICgAAAA==.',
Zo='Zorsa:BAAANQADCgYIFgAAAA==.',
Zu='Zuljawn:BAAANQAECgQIBQAAAA==.',
Zy='Zyphos:BAAANQADCgIIAgAAAA==.',
['Ñô']='Ñôg:BAAANQADCggICQAAAA==.',
['Ød']='Ødis:BAAANQADCggIEQAAAA==.',
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
