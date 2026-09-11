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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Mage-Arcane',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=53,date='2026-09-08',data={Ad='Adhira:BAAANQADCgYIDAAAAA==.',
Ae='Aegennai:BAAANQADCggIFQAAAA==.Aegondk:BAEANQAECgcICAAAAA==.Aelias:BAAANQADCgcIEAAAAA==.Aevaela:BAAANQAECgUIBwAAAA==.',
Ag='Agilaz:BAAANQAECgIIAgAAAA==.',
Ak='Akey:BAAANQADCggIDgAAAQ==.Akhae:BAAANQAECgUICAAAAA==.',
Al='Albinism:BAAANQADCgcIEAAAAA==.Alcadeias:BAAANQADCgcIDgAAAA==.Alethiah:BAAANQADCgQIBQAAAA==.',
An='Anaeda:BAAANQAECgIIAQAAAA==.Andrömëdä:BAAANQADCgcICAAAAA==.Angryjim:BAAANQADCgUIBQAAAA==.Anubisre:BAAANQADCgQIBQAAAA==.Anzulay:BAAANQADCgMIAwAAAA==.',
Aq='Aquindra:BAAANQADCgYIBgAAAA==.',
Ar='Aralleda:BAAANQABCgIIAgAAAA==.Arccane:BAAANQADCgcICQAAAA==.Arthar:BAAANQAECgYICQAAAA==.',
As='Ashvyth:BAAANQAECgEIAQAAAA==.',
Aw='Awwyeah:BAAANQADCgIIAgAAAQ==.',
Az='Azuredeath:BAAANQABCgIIAgAAAA==.',
Ba='Baconpancake:BAAANQADCgcIBwAAAA==.Baldpunch:BAAANQADCgcIDgAAAA==.Balinor:BAAANQADCgYIBgAAAA==.Ballz:BAAANQADCgYIBgAAAA==.Balomdruid:BAAANQADCgUIBQAAAA==.Barnabus:BAAANQAECgIIBAAAAA==.',
Be='Beachbecrazy:BAAANQADCgcIDQAAAA==.Beaj:BAAANQADCgcICAAAAA==.Beastlypläyä:BAAANQADCgIIAgAAAA==.Belládonna:BAAANQADCggICAAAAA==.Bessarion:BAAANQABCgUIBgAAAA==.',
Bi='Bilac:BAAANQADCgEIAQABNQAECgYICgABAAAAAA==.',
Bl='Blusoleil:BAAANQADCgcICAAAAA==.',
Bo='Bonerblast:BAAANQADCggICgAAAA==.Boston:BAAANQAECgEIAQAAAA==.',
Br='Branches:BAAANQAECgEIAQAAAA==.Brewtholomew:BAAANQAECgQIBQAAAA==.Briggsey:BAAANQAECgEIAQAAAA==.Briznot:BAAANQADCggIFAAAAA==.Bruh:BAAANQAECgQIBAAAAA==.Bryce:BAAANQADCgcICwAAAA==.Brèanna:BAAANQADCgIIAgAAAA==.',
Bu='Bubbadubya:BAAANQADCgUICgAAAA==.Bunnyfu:BAAANQADCgcICAABNQAECgYICgABAAAAAA==.Burningwolf:BAAANQAECgMIBAAAAA==.',
['Bó']='Bórs:BAAANQAECgMIAgAAAA==.',
Ca='Caiden:BAAANQADCgYIBgAAAA==.Caitlyn:BAAANQADCgEIAQAAAA==.Caleesia:BAAANQADCgUICgAAAA==.Carnìfex:BAAANQADCgcIEAAAAA==.Caskaerta:BAAANQADCgYIBgAAAA==.Catbrin:BAAANQADCggIFQAAAA==.',
Ce='Cerà:BAAANQADCgYICAAAAA==.',
Ch='Chapslop:BAAANQADCgcIDAAAAA==.Cheetah:BAAANQADCgIIAgAAAA==.',
Cl='Clizee:BAAANQABCgQIAwAAAA==.Clobberben:BAAANQADCgQIBAAAAA==.Cloudbreaker:BAAANQADCgUIBQAAAA==.',
Co='Cobramage:BAAANQADCgQIBAAAAA==.Constellate:BAAANQAECgEIAQAAAA==.Cotterpins:BAAANQADCggIFAAAAA==.',
Cr='Cruicible:BAAANQADCgcICQAAAA==.',
Cy='Cybrkatz:BAAANQADCgIIAgAAAA==.',
Cz='Cztalone:BAAANQADCgQIBAAAAA==.',
['Cè']='Cèlane:BAAANQAECgQIBgAAAA==.',
Da='Damitsu:BAEANQADCgYICwABNQADCgcIEAABAAAAAA==.Damnitsu:BAEANQADCgcIEAAAAA==.Darckside:BAAANQADCgUIBQAAAA==.Dazen:BAAANQADCgIIAgAAAA==.',
De='Deadflexy:BAAANQADCggIDgAAAA==.Deathberry:BAAANQAECgIIAgAAAA==.Deathdoodles:BAAANQADCgcICAABNQAECgQIBgABAAAAAA==.Deathvoker:BAAANQADCgYICwAAAA==.Deekan:BAAANQAECgIIAQAAAA==.Dejavù:BAAANQADCgIIAQAAAA==.Demonblood:BAAANQAECgQIBQAAAA==.Deräth:BAAANQADCggICgAAAA==.Devlik:BAAANQADCgYIBwAAAA==.Dew:BAAANQADCgYIBgAAAA==.',
Di='Dimensius:BAAANQAECgQIBQAAAA==.Dinkalopogis:BAAANQADCgQICQAAAA==.Ditsie:BAAANQADCgUICgAAAA==.',
Dm='Dmega:BAAANQADCgYIEgAAAA==.',
Do='Dogfunk:BAAANQABCgYICAAAAA==.',
Dr='Dragea:BAAANQADCggICAAAAA==.Dragondude:BAAANQADCggIFgAAAA==.Dragonsgrasp:BAAANQADCgUIBAAAAA==.',
Du='Durango:BAAANQADCggICwAAAA==.',
Dy='Dyelin:BAAANQAECgEIAQAAAA==.',
El='Elylle:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.Elyron:BAAANQAECgEIAQAAAA==.',
En='Endofall:BAAANQAECgEIAgAAAA==.',
Ep='Epiczimbabue:BAAANQADCgEIAQAAAA==.',
Es='Esrahaddon:BAAANQAECgMIBAAAAA==.',
Et='Et:BAAANQAECgEIAQAAAA==.Etheri:BAAANQADCgYICgAAAA==.',
Ez='Ezhra:BAAANQABCgEIAQABNQADCgUICgABAAAAAA==.Ezind:BAAANQADCgYIBgAAAA==.',
Fa='Fakename:BAAANQAECgQIBAAAAA==.Fakesaint:BAAANQAECgQIBwAAAA==.Fangstorm:BAAANQAECgEIAQAAAA==.Farorê:BAAANQADCgYIDAAAAA==.Fazz:BAAANQADCgQIBAAAAA==.',
Fe='Feldruid:BAAANQAECgEIAgAAAA==.Felup:BAAANQAECgQIBgAAAA==.',
Fo='Folstagg:BAAANQADCgcIDAAAAA==.',
Fr='Frostynewf:BAAANQADCgYIBgAAAA==.',
Fu='Fujitora:BAAANQAECgMIAwAAAA==.',
Gl='Glenys:BAAANQADCgEIAQAAAA==.',
Gr='Graxus:BAAANQADCgYICgAAAA==.Greth:BAAANQADCgUICgAAAA==.Grimlin:BAAANQADCgUIBAAAAA==.Grimshotzz:BAAANQAECgEIAQAAAA==.',
Gu='Gudge:BAAANQAECgYICgAAAA==.Gummypenguin:BAAANQAECgcIDwABNQAECgkJHgACABokAA==.',
Ha='Hadhox:BAAANQADCgYIEAABNQADCgYIEAABAAAAAA==.Hathdox:BAAANQADCgYIEAAAAA==.Hawkulees:BAAANQADCgQIBwAAAA==.Hazelnoot:BAAANQAECgQIBgAAAA==.',
He='Healzofdeath:BAAANQADCgUIBQAAAA==.Hegaphie:BAAANQADCgEIAQAAAA==.Hexcist:BAAANQADCggIDQAAAA==.',
Hi='Hitsuryu:BAAANQADCggIFQAAAA==.',
Ho='Hochma:BAAANQADCgEIAQAAAA==.Hokogo:BAAANQADCgEIAQAAAA==.Holdon:BAAANQAECgUIBQAAAA==.Hollyanne:BAAANQAECgEIAQAAAA==.Hoonicorn:BAAANQADCgEIAQABNQADCgIIAgABAAAAAA==.Hornsharp:BAAANQADCgUIBwAAAA==.',
Hu='Hunalli:BAAANQADCgUIBwABNQAECgYICgABAAAAAA==.Hunilla:BAAANQADCggIDQABNQAECgYICgABAAAAAA==.',
Ia='Iamu:BAAANQADCgQIBwAAAA==.',
Ib='Ibris:BAAANQADCgIIAgAAAA==.',
Ic='Iconius:BAAANQADCgIIAgAAAA==.',
Ie='Ieatwetsocks:BAAANQAECgYIDQAAAA==.',
Ig='Ignivar:BAAANQADCgYIDgAAAA==.',
In='Indra:BAAANQADCgEIAQAAAA==.Insaint:BAAANQADCgcIDAAAAA==.',
Ir='Ironfield:BAAANQAECgEIAQAAAA==.Irony:BAAANQAECgMIAgAAAA==.Irtank:BAAANQADCgEIAQAAAA==.',
Is='Isabellë:BAAANQAECgIIAgAAAA==.',
Je='Jessamine:BAAANQAECgQIBgAAAA==.Jetta:BAAANQADCgcIEAAAAA==.Jezzak:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.',
Jo='John:BAAANQAECgYIEQAAAA==.Jorien:BAAANQAECgMIAwAAAA==.',
Jp='Jp:BAAANQADCgQIBQAAAA==.Jpd:BAAANQADCgQIBQABNQADCgQIBQABAAAAAA==.',
Ju='Justadwarf:BAAANQADCgcICQAAAA==.Juston:BAAANQADCggIDgAAAA==.',
Ka='Kaboonsky:BAAANQAECgQIBQAAAA==.Kaeamani:BAAANQADCgYIBwAAAA==.Kaenaya:BAAANQADCgIIAgAAAA==.Kamikori:BAAANQADCggIFQAAAA==.Kardell:BAAANQADCgYIDAAAAA==.Kardels:BAAANQADCgQIBAABNQADCgYIDAABAAAAAA==.Karnadaz:BAAANQAECggIEgAAAA==.Karnkarn:BAAANQAECgQIBAAAAA==.Karnn:BAAANQADCggIDgAAAA==.Katalight:BAAANQADCgEIAQABNQADCgUIBQABAAAAAA==.',
Ke='Keho:BAAANQAECgIIAgAAAA==.',
Ki='Kiascendance:BAAANQAECgUICgAAAA==.',
Ko='Kolosho:BAAANQADCgcIEwAAAA==.Korxana:BAAANQADCgcICQAAAA==.Korxon:BAAANQAECgUICQAAAA==.Kotus:BAAANQADCgcIDQAAAA==.',
Ks='Ksyusha:BAAANQADCggICAAAAA==.',
Ky='Kyfess:BAAANQADCgYIBQABNQADCgYIBgABAAAAAA==.',
['Kä']='Kämi:BAAANQADCgUIBgABNQADCgcIFgABAAAAAA==.',
La='Lanuadra:BAAANQAECgYIBwAAAA==.',
Le='Leasidhe:BAAANQADCgcIDgABNQADCgQIBAABAAAAAA==.Lethalbimbo:BAAANQADCgIIAgAAAA==.',
Lg='Lghtninstorm:BAAANQADCgEIAQAAAA==.',
Li='Likhan:BAAANQABCgQIBAABNQADCgcIBwABAAAAAA==.Lillié:BAAANQABCgIIAQAAAA==.Lilysham:BAABNQAECoEXAAIDAAkJ9CCtBgAdAwADAAkJ9CCtBgAdAwAAAA==.Lindar:BAAANQABCgIIAwAAAA==.Linddrel:BAAANQAECgEIAQAAAA==.',
Lo='Lomea:BAAANQADCgYIBgAAAA==.Lonarius:BAAANQABCgQIBQAAAA==.',
['Lø']='Løllîe:BAAANQADCgYIBgAAAA==.',
Ma='Macarius:BAAANQADCggIEwAAAA==.Macdee:BAAANQADCgMIAwABNQADCggIDQABAAAAAA==.Magatai:BAAANQADCgUIBQAAAA==.Mageless:BAAANQADCgIIAgAAAA==.Magpie:BAAANQADCgYIDAAAAA==.Maimed:BAAANQADCggIEwAAAA==.Malotan:BAAANQABCgEIAQABNQABCgQIBgABAAAAAA==.Manaster:BAAANQADCgcICAAAAA==.Maravanna:BAAANQADCgEIAQAAAA==.Martlok:BAAANQADCggIFAAAAA==.Mathas:BAAANQADCgYICgAAAA==.Maynis:BAAANQABCgQIBgAAAA==.Maysaveyou:BAAANQABCgIIAgAAAA==.',
Mc='Mcbrynhammer:BAAANQADCgMIBgAAAA==.',
Me='Merkii:BAAANQADCgYIBgABNQADCgcIDgABAAAAAA==.',
Mi='Micflinigan:BAAANQADCggIEwAAAA==.Milkymoomoo:BAAANQADCgQIBAAAAA==.Minarii:BAAANQAECgEIAQAAAA==.Minilove:BAAANQADCgIIAgAAAA==.Mishelö:BAAANQADCgQIBAAAAA==.',
Mo='Mochimochi:BAAANQADCgQIBAAAAA==.Mommieuppies:BAAANQADCgcIBwAAAA==.Moonshae:BAAANQAECgQIBgAAAA==.Mortalbion:BAAANQADCggIEgAAAA==.',
My='Mystiquè:BAAANQADCgUICgAAAA==.',
Na='Naithin:BAAANQAECgEIAQAAAA==.Nalarah:BAAANQADCgEIAQAAAA==.Naviriel:BAAANQADCgEIAQABNQADCggIEwABAAAAAA==.',
Ne='Nerrf:BAAANQADCgUIBQAAAA==.',
Ni='Nightray:BAAANQAECgQIBAABNQAECgYICQABAAAAAA==.',
No='Noknik:BAAANQABCgQIBgAAAA==.Nonsocial:BAAANQAFFAEIAQABNQAECgkJGAAEACohAA==.Noriisa:BAAANQAECgQIBQAAAA==.Notamathguy:BAAANQADCggIDgAAAA==.Noudders:BAAANQAECgIIAgAAAA==.',
Ny='Nyvak:BAAANQADCgcIBwAAAA==.',
Od='Odinhand:BAAANQAECgQIBgAAAA==.',
Ol='Oliissa:BAAANQADCgUICgAAAA==.',
Oz='Ozwäldo:BAAANQAECgcIDwAAAA==.',
Pa='Pandapí:BAAANQADCgYIBgAAAA==.Panduh:BAAANQAECgYIBwAAAA==.Pandóra:BAAANQADCgcICQAAAA==.Pariousa:BAAANQAECggIEwAAAA==.',
Pe='Peppermintxo:BAAANQADCgMIAwABNQADCgIIAgABAAAAAA==.',
Ph='Phaite:BAAANQAECggIAQAAAA==.',
Pi='Pinkeepink:BAAANQADCgYIEAAAAA==.',
Po='Popacooldown:BAAANQADCgQIBAAAAA==.',
Pr='Pres:BAAANQAECgIIAgAAAA==.Prild:BAAANQABCgQIBgAAAA==.',
Pu='Pumpernickle:BAAANQAECgQIBAAAAA==.',
Ra='Rahzon:BAAANQADCggICwAAAA==.Ralganor:BAAANQAECgQIBgAAAA==.Ralzin:BAAANQADCgUICAAAAA==.Ramanash:BAAANQADCgQICAAAAA==.Raynlight:BAAANQADCggIFQAAAA==.',
Re='Ren:BAAANQADCgIIAgAAAA==.Retacus:BAAANQADCgYICwAAAA==.',
Ri='Rina:BAAANQAFFAEIAQAAAA==.Ringadingg:BAAANQAECgEIAQAAAA==.',
Ro='Rosequartz:BAAANQADCggICAAAAA==.',
Ry='Rydia:BAAANQAECgEIAQAAAA==.',
Sa='Saladin:BAAANQADCgUIBgAAAA==.Sankatlantis:BAAANQADCgYIBQABNQADCgYIBgABAAAAAA==.Sarka:BAAANQADCgcIBwAAAA==.Sasquatch:BAAANQADCggIFAAAAA==.',
Sc='Scony:BAAANQAECgEIAQAAAA==.Scribs:BAAANQADCgYICQAAAA==.Scyphen:BAAANQADCgQIBAAAAA==.',
Se='Seegon:BAAANQABCgYIBQAAAA==.Seismic:BAAANQADCggICAAAAA==.Sephirain:BAAANQADCgMIAwAAAA==.Sevelement:BAAANQADCgMIAwABNQAECgUIBwABAAAAAA==.Severànce:BAAANQAECgUIBwAAAA==.Sevivify:BAAANQADCgIIAwABNQAECgUIBwABAAAAAA==.',
Sh='Shablammy:BAAANQADCggIFQAAAA==.Shadowginni:BAAANQADCgcIDAAAAA==.Shadownome:BAAANQADCgIIAgAAAA==.Shammygand:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Shanker:BAAANQADCgMIAwAAAA==.Shefu:BAAANQAECgMIBQAAAA==.Shfifty:BAAANQAECgQIBgAAAA==.Shutupbird:BAAANQAECgMIAwAAAA==.',
Si='Silris:BAAANQADCgMIAwAAAA==.',
Sk='Skydragon:BAAANQADCgUICwAAAA==.',
Sl='Slay:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Slonk:BAAANQADCgYIEAAAAA==.',
So='Sofia:BAAANQADCggIFAAAAA==.',
Sp='Sparrtacus:BAAANQABCgQIBgAAAA==.Spiritly:BAAANQADCgUIBQAAAA==.Sploof:BAAANQADCggIDgAAAA==.',
St='Starlighter:BAAANQADCgYIBgAAAA==.Starmist:BAAANQADCgUICgAAAA==.Stubly:BAAANQADCgQIBAAAAA==.',
Su='Sunfyrie:BAAANQADCggIDgAAAA==.',
Sw='Sweèt:BAAANQADCgYIBgAAAA==.',
Ta='Tagrit:BAAANQADCgUIBQAAAA==.Taldieth:BAAANQADCgcIBwAAAA==.Taurdk:BAAANQAECgEIAQAAAA==.Taylorshift:BAAANQAECgQIBAAAAA==.',
Te='Teaar:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Teetau:BAAANQAECgEIAQAAAA==.',
Th='Thadregosa:BAAANQAECgEIAQAAAA==.Thalsan:BAAANQABCgIIAgAAAA==.Thander:BAAANQADCgYICQAAAA==.Therlisa:BAAANQADCggICAAAAA==.',
Ti='Tiberius:BAAANQABCgIIAQAAAA==.Tiffy:BAAANQADCgUICQAAAA==.Tirna:BAAANQAECgEIAQAAAA==.Tirnotham:BAAANQADCggIDgAAAA==.',
Tm='Tmtglizzy:BAAANQAECgIIAgAAAA==.',
To='Tokalu:BAAANQADCggIEwAAAA==.Tonjudsonson:BAAANQAECggIEgAAAA==.Torath:BAAANQADCgUIBQABNQADCgYICQABAAAAAA==.',
Tu='Turdimer:BAAANQADCgYIDQAAAA==.',
Tw='Twiki:BAAANQADCggIFQAAAA==.Twobricks:BAAANQAECgQIBgAAAA==.',
Ty='Tyrssana:BAAANQADCggIDgABNQAECgYICgABAAAAAA==.',
Uh='Uhmerica:BAAANQAECgQIBgAAAA==.',
Ur='Urdeadtoo:BAAANQAECgEIAQAAAA==.Urthkwayk:BAAANQADCgYIBgAAAA==.',
Va='Vaedryn:BAAANQADCgUIBQAAAA==.Vaterunser:BAAANQADCggIDgAAAA==.Vazoom:BAAANQAECgIIAwAAAA==.',
Ve='Velskud:BAAANQADCgUICgAAAA==.',
Vi='Vierth:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Vinhar:BAAANQADCgUICAAAAA==.Visea:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.',
Vo='Voidsavage:BAAANQADCgYIDgAAAA==.Voidwing:BAAANQAECgQIBAAAAA==.Volic:BAAANQAECgEIAQAAAQ==.Vollken:BAAANQADCgIIAgAAAA==.Voznje:BAAANQAECgEIAwAAAA==.',
We='Wesleypipes:BAAANQAECgIIAgAAAA==.',
Wh='Whisteria:BAAANQADCgYIBgAAAA==.',
Wi='Wizalf:BAAANQADCgYIBgAAAA==.',
Wo='Wolfmato:BAAANQAECgYICgAAAA==.',
Wy='Wynne:BAAANQADCgYICgAAAA==.',
Xa='Xalabro:BAAANQADCggIFQAAAA==.',
Xe='Xerxeis:BAAANQABCgYICAABNQADCgcIEwABAAAAAA==.',
Xo='Xousa:BAAANQADCgQIBgABNQAECggIEwABAAAAAA==.',
Yh='Yhorn:BAAANQADCgcIBwABNQAECgkJFwADAPQgAA==.',
Ys='Yssuplef:BAAANQADCggIDgAAAA==.',
Za='Zaiyra:BAAANQADCgcICAAAAA==.Zakoor:BAAANQADCgYIDgAAAA==.Zareena:BAAANQADCgYICgAAAA==.Zarnia:BAAANQADCgMIAwAAAA==.Zarrock:BAAANQADCgIIAgAAAA==.Zavatan:BAAANQADCgQIBwAAAA==.',
Ze='Zebbyzebzeb:BAAANQADCgYIDQAAAA==.Zekia:BAAANQAECgQIBAAAAA==.Zerm:BAAANQAECgMIBAAAAA==.',
Zi='Zinnkura:BAAANQADCggICgAAAA==.',
Zo='Zorsa:BAAANQADCgYIEAAAAA==.',
Zu='Zuljawn:BAAANQAECgEIAQAAAA==.',
Zy='Zyphos:BAAANQADCgIIAgAAAA==.',
['Ñô']='Ñôg:BAAANQADCgEIAQAAAA==.',
['Ød']='Ødis:BAAANQADCgcICQAAAA==.',
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
