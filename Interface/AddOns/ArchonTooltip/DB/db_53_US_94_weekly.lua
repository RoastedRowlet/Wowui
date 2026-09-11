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

local lookup = {'Warrior-Arms','Unknown-Unknown','Evoker-Devastation','Monk-Mistweaver','Druid-Balance',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aarchon:BAAANQAECgIIAgAAAA==.',
Ad='Aduin:BAAANQADCgQIBAAAAA==.',
Ae='Aedarelyn:BAAANQADCgUICgAAAA==.Aellita:BAAANQADCgQIBAAAAA==.',
Af='Afkinlife:BAAANQADCgYIBwAAAA==.',
Ak='Akky:BAAANQADCggIFAAAAA==.Aksafiya:BAAANQAECgIIBAAAAA==.',
Al='Alaras:BAAANQAECgcIDwAAAA==.Allaras:BAAANQADCgYIBgAAAA==.Allistaris:BAAANQADCgcIEwAAAA==.Allrianne:BAAANQADCgMIBgAAAA==.Alphá:BAAANQAECgQIBAAAAA==.Althoraty:BAAANQAECgIIAgAAAA==.Alyx:BAAANQADCgcICAAAAA==.',
An='Andoros:BAAANQAECgEIAgAAAA==.Anzurath:BAAANQAECgIIAgAAAA==.',
Ap='Apheron:BAAANQAECgMIAwAAAA==.Applebow:BAAANQADCgcIEAAAAA==.Apples:BAAANQADCggICAAAAA==.',
Ar='Arknova:BAAANQAECgQIBAAAAA==.Arylin:BAAANQAECgEIAQAAAA==.',
As='Ashkinassi:BAEANQADCgUIBgAAAA==.Asiain:BAAANQAECgUIBgABNQAECgkJFgABAKEfAA==.Asnabel:BAAANQADCgYIDQAAAA==.',
At='Atvar:BAAANQADCggICAAAAA==.',
Au='Autumndeath:BAAANQADCgYIBwAAAA==.',
Av='Avinger:BAAANQABCgYIBwAAAA==.',
Ay='Ayden:BAAANQAECgYICwAAAA==.',
Az='Azrim:BAAANQADCgUICAAAAA==.Azureis:BAAANQADCgcICAAAAA==.',
Be='Belthar:BAAANQAECgIIBAAAAA==.',
Bl='Blee:BAAANQADCgYIFAAAAA==.Bluudclaaw:BAAANQADCgMIAwAAAA==.',
Bo='Boomhauer:BAAANQADCgcIEAAAAA==.',
Br='Braelia:BAAANQAECgEIAQAAAA==.Braetwo:BAAANQABCgUIBQABNQAECgEIAQACAAAAAA==.Breye:BAAANQAECgEIAQAAAA==.Brindria:BAAANQADCgQIBAAAAA==.Brood:BAAANQAECgQIBgAAAA==.Brundles:BAAANQAECgIIAgAAAA==.',
Bu='Bubblepopper:BAAANQAECgEIAQAAAA==.Bunky:BAAANQADCggIFAAAAA==.',
Ca='Cailaranel:BAAANQAECgEIAQAAAA==.Calaul:BAAANQAECgIIAgAAAA==.Calenbraga:BAAANQADCgYIGgAAAA==.Calisim:BAAANQADCgYIEAAAAA==.Caloh:BAAANQADCgYIDgAAAA==.Cantholdagro:BAAANQAECgEIAQAAAA==.Cassamaria:BAAANQAECgIIAgAAAA==.Cataryn:BAAANQAECgIIAgAAAA==.Catt:BAAANQAECgQIBAAAAA==.Cattlerage:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.',
Ce='Cellebur:BAAANQADCgUIDAAAAA==.Ceta:BAAANQAECgEIAQAAAA==.',
Ch='Chalfus:BAAANQAECgEIAQAAAA==.Chaszmyr:BAAANQADCgcIBwAAAA==.',
Ci='Cinamen:BAAANQADCgcIGAAAAA==.Cizean:BAAANQADCgcIDAAAAA==.',
Cl='Clare:BAAANQABCgQIBAABNQAECgIIAgACAAAAAA==.Closetofsmut:BAAANQADCgcIBwAAAA==.',
Cr='Craivan:BAAANQADCgUICQAAAA==.Crendoal:BAAANQADCgIIAgABNQAECgMIBgACAAAAAA==.Crilly:BAAANQAECgMIAwAAAA==.Crumpler:BAAANQADCgYIBgAAAA==.',
Cy='Cyroka:BAAANQADCgYIEAAAAA==.Cytroncutoff:BAAANQADCgQIBAAAAA==.',
Da='Dalastish:BAAANQADCggICAAAAA==.Damia:BAAANQADCgcIEAAAAA==.Danobun:BAAANQAECgUIBQAAAA==.Darkfoxcr:BAAANQABCgIIBAAAAA==.Darsithis:BAAANQADCgcIEAAAAA==.',
De='Deadite:BAAANQAECgIIAgAAAA==.Delvarrieth:BAAANQADCgcIDgAAAA==.Denth:BAAANQADCgYIDwAAAA==.Dercuur:BAAANQAECgEIAQAAAA==.',
Dr='Dragonkiss:BAAANQADCgQIBwAAAA==.Drakmyrdok:BAAANQADCgQICAAAAA==.Dravorik:BAAANQADCgYIBwAAAA==.Dregoth:BAAANQADCggIFAAAAA==.Drumpnelf:BAAANQADCgMIAwAAAA==.',
Ds='Dshivà:BAAANQADCggIDgAAAA==.',
['Dá']='Dárkbeard:BAAANQADCgUIBQAAAA==.',
Ek='Ekneirg:BAAANQAECgEIAQAAAA==.',
El='Elynth:BAAANQAECgIIAgAAAA==.',
En='Endlessyueh:BAAANQADCgQIBgAAAA==.',
Ex='Extragrippy:BAAANQADCgMIAwAAAA==.',
Fa='Fajathyme:BAAANQADCgUIDgAAAA==.Falunia:BAAANQAECgQIAwAAAA==.Farrseer:BAAANQADCggIEQAAAA==.Fastburn:BAAANQAECgIIAgAAAA==.Fasthandslez:BAAANQADCgYIDAAAAA==.',
Fe='Felscythe:BAAANQADCgcIEQAAAA==.',
Fi='Fierrastar:BAAANQADCggIGQAAAA==.Finshao:BAAANQADCgcIEQAAAA==.',
Fl='Flemish:BAAANQADCgcIEAAAAA==.Flextame:BAAANQADCgUICQAAAA==.Flipalicious:BAAANQAECgQIBgAAAA==.Flipmode:BAAANQADCgEIAQAAAA==.',
Fo='Foxwynn:BAAANQABCgIIAgAAAA==.',
Fr='Freyalise:BAAANQAECgEIAQAAAA==.Freyjah:BAAANQADCgUIBQAAAA==.',
Fu='Furriousyueh:BAAANQADCgUICwAAAA==.',
Ga='Gaia:BAAANQADCggIEgAAAA==.Gallimaufrey:BAAANQADCgcIFAAAAA==.Garodan:BAAANQADCgcIDQAAAA==.',
Ge='Gerbo:BAAANQAECgQIBQAAAA==.',
Gi='Gianavel:BAAANQAECgIIAgAAAA==.Ginodh:BAAANQAECgIIAgAAAA==.Ginopally:BAAANQADCgMIAwABNQAECgIIAgACAAAAAA==.Ginoshaman:BAAANQADCgUIBgABNQAECgIIAgACAAAAAA==.Ginovoker:BAAANQADCgYICQABNQAECgIIAgACAAAAAA==.',
Gr='Gronke:BAAANQADCgcICgABNQAECgEIAQACAAAAAA==.Grubetsella:BAAANQAECgMIBgAAAA==.Grugachur:BAAANQADCgcIEQAAAA==.',
Gu='Gutray:BAAANQADCgcIBwAAAA==.',
Gy='Gyda:BAAANQADCgQICAAAAA==.',
Ha='Haralambos:BAAANQADCgMIBgAAAA==.Harlar:BAAANQADCgIIBAAAAA==.Hatebug:BAAANQAECgIIAgAAAA==.',
He='Helbrede:BAAANQADCgIIAwAAAA==.Heledosia:BAAANQADCgcICwAAAA==.',
Ho='Hordkilla:BAAANQADCggIDwAAAA==.Hownowbrncw:BAAANQAECgIIAgAAAA==.',
Hy='Hyce:BAAANQAECgEIAQAAAA==.',
In='Insoniacyun:BAAANQADCgMICQAAAA==.',
Is='Iselian:BAAANQADCggIDQAAAQ==.',
Jb='Jbshami:BAAANQAECgEIAQAAAA==.',
Je='Jenisys:BAAANQADCgYIBgAAAA==.Jenzak:BAAANQAECgEIAQAAAA==.Jetfires:BAAANQAECgQIBwAAAA==.',
Ji='Jinger:BAAANQADCggIEwAAAA==.',
Jo='Jordstrasza:BAAANQADCgYIBgAAAA==.Jozhua:BAAANQADCgcICAAAAA==.',
Ka='Kaedren:BAAANQADCgQIBQAAAA==.Kaelorien:BAAANQADCgYICwAAAA==.Kalazaad:BAAANQADCggIEgAAAA==.Kaldevayn:BAAANQADCgYIEwAAAA==.Kaliantha:BAAANQADCgEIAQAAAA==.Kalto:BAAANQADCgMIAwAAAA==.Kardanis:BAAANQAECgIIAgAAAA==.Kashe:BAAANQADCgUICwAAAA==.Kassaine:BAAANQADCgEIAQAAAA==.Kasume:BAAANQAECgQIBQAAAA==.Katavia:BAAANQAECgIIAgAAAA==.Katrazath:BAAANQADCgUICgAAAA==.Kaydencia:BAAANQABCgIIBAAAAA==.',
Kh='Khiana:BAAANQADCgIIAgABNQAECgIIAgACAAAAAA==.',
Ki='Kiddow:BAAANQADCgUIDAAAAA==.Kierea:BAAANQADCgcIBwAAAA==.Kilrah:BAAANQADCgEIAQAAAA==.Kitamii:BAAANQADCgEIAQAAAA==.',
Ko='Kokujin:BAAANQAECgIIAgAAAA==.',
Kr='Kraevok:BAAANQADCgMIBwAAAA==.Kraugug:BAAANQADCgQIBAAAAA==.Kringlë:BAAANQAECgQIBgAAAA==.',
Ku='Kunu:BAAANQADCgUIBQABNQAECgUIBgACAAAAAA==.Kurumi:BAAANQADCgYIDAAAAA==.',
Kw='Kwo:BAAANQADCgQIBAAAAA==.',
Ky='Kymma:BAAANQADCgcIEAAAAA==.',
La='Laviz:BAAANQADCgYIBwAAAA==.Lazengann:BAAANQADCggIFQAAAA==.',
Le='Leafbane:BAAANQAECgUICQAAAA==.Legevia:BAAANQADCgcIDAAAAA==.Leiris:BAAANQAECgEIAQAAAA==.Lejusticier:BAAANQADCggICAAAAA==.Leonaa:BAAANQADCgQIBAAAAA==.Leucetios:BAAANQADCgYIBgAAAA==.',
Li='Liarace:BAAANQAECgQIBAAAAA==.Lightbeard:BAAANQADCgYIEAAAAA==.Lightforge:BAAANQAECgEIAQAAAA==.Lithika:BAAANQADCgYIBAAAAA==.',
Lo='Lorredain:BAAANQADCgQIBAAAAA==.Lothwen:BAAANQADCgQIBgAAAA==.Louisachan:BAAANQAECgEIAQAAAA==.',
Lu='Luxinine:BAAANQAECgIIAgAAAA==.',
Ma='Madhawi:BAAANQAECgEIAQAAAA==.Magamon:BAAANQAECgIIAgAAAA==.Malfuriia:BAAANQADCgcIEQAAAA==.Mamboke:BAAANQADCgUIBQAAAA==.Margerdria:BAAANQADCgUICQAAAA==.Mauugrim:BAAANQADCgYIDwAAAA==.Maxowen:BAAANQADCgcIEQAAAA==.Maxxramas:BAAANQADCgUIBQAAAA==.',
Me='Mearadan:BAAANQADCggIFwAAAA==.Meatsweats:BAAANQADCgcIDwAAAA==.Megg:BAAANQADCgYIBgAAAA==.Mekh:BAAANQADCgcIEQAAAA==.Mel:BAAANQADCgMIBAAAAA==.Melanara:BAAANQADCggIFgAAAA==.Melstrom:BAAANQADCgQICAAAAA==.Meticuluslyn:BAAANQADCgYIEAAAAA==.',
Mi='Milkmaiden:BAAANQADCgMIBAAAAA==.Milkthisbull:BAAANQADCgMIAwAAAA==.Mixler:BAAANQADCgcIDgAAAA==.',
Mm='Mmeow:BAAANQADCgUICgABNQAECgQIBAACAAAAAA==.',
Mo='Moirine:BAAANQADCgcIEQAAAA==.',
Mu='Murdrmitts:BAAANQADCgQIBAAAAA==.Mustikka:BAAANQADCgIIAgABNQADCgUICAACAAAAAA==.',
My='Myuriyanka:BAAANQAECgQIBQAAAA==.',
['Mæ']='Mælstrôm:BAAANQABCgMIAwAAAA==.',
Na='Naahommii:BAAANQADCgUIBQAAAA==.Naeri:BAAANQADCgcIBwAAAA==.Nagualli:BAAANQADCggICAAAAA==.Naieve:BAAANQADCggIFAAAAA==.Nastychungus:BAAANQAECgcIDgAAAA==.',
Ne='Negargra:BAAANQADCgYICgAAAA==.Nephadin:BAAANQADCgcIDwAAAA==.',
Ni='Nighttiger:BAAANQADCggICgAAAA==.Nikooli:BAAANQADCgcIDwAAAA==.',
No='Noopsie:BAAANQADCgUIFAAAAA==.Nooters:BAAANQADCggIDAABNQAECgkJGwADAC0jAA==.Notbaldmonk:BAAANQADCgMIAwAAAA==.Notbaldpries:BAAANQAECgEIAQAAAA==.',
Ny='Nyteweaver:BAAANQADCgcIEQAAAA==.',
Od='Oderica:BAAANQADCgcICAAAAA==.',
Os='Oscarmikey:BAAANQAECggIDQAAAA==.',
Ot='Ottoshot:BAAANQADCgcIEQAAAA==.',
Ov='Overlordock:BAAANQADCgcIBwAAAA==.',
['Oö']='Oöps:BAAANQADCggIDwAAAA==.',
Pa='Panamone:BAAANQABCgEIAQAAAA==.Pandamaster:BAAANQAECgMIBQAAAA==.',
Pe='Pendragon:BAAANQADCgQIBAAAAA==.',
Pl='Plagues:BAAANQADCggIDQAAAA==.',
Po='Porterhouze:BAAANQABCgIIAgABNQADCgYIDAACAAAAAA==.',
Pr='Priianka:BAAANQADCgEIAQAAAA==.',
Pu='Puchi:BAABNQAECoEYAAIEAAkJcR+WAgAdAwAEAAkJcR+WAgAdAwAAAA==.Pug:BAAANQADCggICwAAAA==.',
Ra='Raynecira:BAAANQADCgYIDwAAAA==.',
Re='Reihino:BAAANQADCgcIDwAAAA==.Remixidora:BAAANQAECgQIBAABNQAECggIEQACAAAAAA==.Reyrocko:BAAANQAECgEIAQAAAA==.Rezdh:BAAANQAECgQIBAABNQAECgYIDAACAAAAAA==.Reznal:BAAANQAECgMIAwABNQAECgYIDAACAAAAAA==.',
Rh='Rhage:BAAANQADCgIIAwAAAA==.Rhunyaye:BAAANQADCgIIAgAAAA==.',
Ri='Rico:BAAANQADCgIIAgAAAA==.',
Ro='Rokthul:BAAANQADCgYIBgAAAA==.Rooroo:BAAANQADCgYIBgAAAA==.Rottingturky:BAAANQADCggICAAAAA==.Roxane:BAAANQADCggIFAAAAA==.',
Ru='Runningelk:BAAANQAECgEIAQAAAA==.',
Ry='Ryeti:BAAANQADCgcIBwAAAA==.',
Sa='Sahalia:BAAANQADCgUIDAAAAA==.Saintulrick:BAAANQADCgcIBwAAAA==.Sajuice:BAAANQAECgIIAgAAAA==.Sanitas:BAAANQADCgYIDwAAAA==.',
Se='Seeyen:BAAANQAECgYIBAAAAA==.Seren:BAAANQADCgIIAgABNQADCggIEAACAAAAAA==.',
Sh='Shaaydo:BAAANQADCgMIAwAAAA==.Shaayllee:BAAANQAECgIIAQAAAA==.Shaggyp:BAAANQADCgUIBQAAAA==.Shamump:BAAANQADCgcIBwAAAA==.Sharyl:BAAANQABCgYIBgAAAA==.Shehasnoname:BAAANQADCgYICAAAAA==.Shehulk:BAAANQAECgQIBAAAAA==.Ships:BAAANQAECgEIAQAAAA==.',
Si='Silf:BAAANQADCgQIBQAAAA==.Sizastrax:BAAANQADCgEIAQAAAA==.',
Sk='Skibbward:BAAANQADCgQIBAABNQAECgMIAwACAAAAAA==.Skrektwo:BAAANQAECgMIAwAAAA==.',
Sm='Smackdogg:BAACNQAFFIEHAAIFAAUJqBZWAQDJAQAFAAUJqBZWAQDJAQA1AAQKgRoAAgUACQnFJMUCAJcDAAUACQnFJMUCAJcDAAAA.',
So='Solarspark:BAAANQAECgQIBQAAAA==.Sonomonom:BAAANQADCggIEAAAAA==.Sorvina:BAAANQAECgUIBwAAAA==.Soulflame:BAAANQAECgIIAgAAAA==.',
Sp='Spriggs:BAAANQADCgMIBAAAAA==.',
St='Stregnor:BAAANQAECgEIAQAAAA==.Styggi:BAAANQADCggICAAAAA==.Stygy:BAAANQADCgcIBwABNQADCggICAACAAAAAA==.',
Su='Sumyunguy:BAAANQAECgEIAQAAAA==.',
Sy='Sylunia:BAAANQAECgEIAQAAAA==.',
Ta='Tachi:BAAANQADCgcIDAABNQAECgIIAgACAAAAAA==.Tachie:BAAANQAECgIIAgAAAA==.',
Te='Tezzerae:BAAANQADCgcIEQAAAA==.',
Th='Theistica:BAAANQADCgcIEAAAAA==.Therin:BAAANQAECgIIAgAAAA==.Thodi:BAAANQABCgYICgAAAA==.',
To='Tongshi:BAAANQABCgYICAAAAA==.Toofast:BAAANQADCggIFQAAAA==.Toofurrious:BAAANQADCgIIAgAAAA==.',
Tr='Trifus:BAAANQADCgcIDwAAAA==.',
Ty='Tylae:BAAANQADCgQIBwAAAA==.',
Ut='Utheli:BAAANQAECgYICgAAAA==.',
Va='Vaildora:BAAANQADCgYIDQABNQAECgIIAgACAAAAAA==.Valdra:BAAANQAECgEIAQAAAA==.Vane:BAAANQADCgEIAQAAAA==.Vanillacain:BAAANQADCgMIAwAAAA==.',
Vi='Violent:BAAANQADCgIIAgAAAA==.Viralprepped:BAAANQADCgMIBgAAAA==.',
Vl='Vlonet:BAAANQAECgQIBgAAAA==.',
Vn='Vnasty:BAAANQAECgIIAgABNQAECgcIDgACAAAAAA==.',
Wi='Wilken:BAAANQADCgYIDwAAAA==.Wink:BAAANQADCgUIBQABNQADCggICwACAAAAAA==.Wiva:BAAANQAECgIIAgAAAA==.',
Wo='Wolfsokol:BAAANQAECgUIBQAAAA==.',
Wr='Wreckoner:BAAANQAECgIIAgAAAA==.',
Xa='Xavencia:BAAANQADCgYICgAAAA==.',
Yk='Yknub:BAAANQADCggIDgAAAA==.',
Yu='Yukiakari:BAAANQADCgQIBQAAAA==.',
Za='Zakainu:BAAANQAECgEIAQAAAA==.Zallister:BAAANQADCgYICgAAAA==.Zarathoszan:BAAANQAECgIIAgAAAA==.',
Ze='Zedator:BAAANQAECgQIBAAAAA==.Zelgaddis:BAAANQADCggIFAAAAA==.Zenanor:BAAANQADCgMIAwAAAA==.',
Zr='Zriana:BAAANQADCgcICAAAAA==.',
Zs='Zsarilya:BAAANQADCgcIEAAAAA==.',
Zu='Zurgen:BAAANQAECgEIAQAAAA==.',
['Êc']='Êclipse:BAEANQAECgIIAgAAAA==.',
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
