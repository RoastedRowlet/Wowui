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

local lookup = {'Unknown-Unknown','Hunter-Marksmanship','Hunter-BeastMastery','Monk-Brewmaster',}
local provider = {region='US',realm='Kilrogg',name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Acanoffood:BAAANQADCgQIBQAAAA==.',
Ae='Aeliana:BAAANQADCgcIBwAAAA==.',
Ag='Aglet:BAAANQAECgIIAgAAAA==.',
Ah='Aharon:BAAANQADCgMIAwAAAA==.',
Aj='Ajacz:BAAANQADCgYIBgAAAA==.',
Ak='Akariel:BAAANQAECgMIAwAAAA==.',
Al='Alassomorph:BAAANQADCgYICwAAAA==.Albus:BAAANQAECgMIAwAAAA==.Allayna:BAAANQAECgIIAgAAAA==.Aloha:BAAANQAECgEIAQAAAA==.Alysaliu:BAAANQAECgYIBwAAAA==.',
Am='Amishmage:BAAANQABCgMIAwAAAA==.Amory:BAAANQADCgIIAgABNQADCgYICwABAAAAAA==.',
An='Anchor:BAAANQADCgQIBAAAAA==.Andja:BAAANQAECgQIBQAAAA==.Andromedae:BAAANQADCgcIDQAAAA==.Andurìl:BAAANQADCgcIBwAAAA==.Angela:BAAANQADCgUIBgAAAA==.Angelicshado:BAAANQABCgQIBAAAAA==.',
Ap='Apostasy:BAAANQAECgIIAgAAAA==.',
Ar='Arngrum:BAAANQADCgYICAAAAA==.Arthrex:BAAANQADCgUICgAAAA==.Arturias:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.',
As='Ascendance:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Ashiok:BAAANQADCgMIBQAAAA==.Asmobob:BAAANQADCgYICQAAAA==.',
Au='Augmentin:BAAANQAECgQIBAAAAA==.Autumm:BAAANQADCgQIBwAAAA==.',
Av='Avanie:BAAANQADCgQIBAAAAA==.',
Aw='Aw:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Ay='Ayhae:BAAANQADCgQIBAAAAA==.',
Ba='Babycoffee:BAAANQADCgEIAQAAAA==.Bahamutz:BAAANQADCggIDAAAAA==.Bangbangdou:BAAANQADCggIDgAAAA==.Bastor:BAAANQADCgcIBwAAAA==.',
Be='Bearnekkid:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Bearsgomoo:BAAANQADCgcICwAAAA==.Beneb:BAAANQADCggIDgAAAA==.Benebeorn:BAAANQAECgYICAAAAA==.Benkinobi:BAAANQADCgYIBgAAAA==.',
Bi='Bichewiche:BAAANQADCgEIAQAAAA==.Bigal:BAAANQADCgEIAQABNQADCggIDQABAAAAAA==.Billyjoe:BAAANQADCggIDgAAAA==.Bittronoxus:BAAANQAECgQIBAAAAA==.',
Bj='Bjoran:BAAANQABCgIIAgAAAA==.',
Bl='Blackseraph:BAAANQADCgIIAgAAAA==.Bleys:BAAANQADCgYIBwABNQAECgIIAgABAAAAAA==.Blinky:BAAANQADCgQIBAAAAA==.',
Bo='Bodikhan:BAAANQADCgYIBgAAAA==.',
Br='Braxte:BAAANQAECgIIAgAAAA==.Britziola:BAAANQADCgQIBAABNQADCgYICwABAAAAAA==.Brusalt:BAAANQAECgMIAwAAAA==.',
Bu='Buggies:BAAANQAECgYICAAAAA==.Buggs:BAAANQADCgYIBgABNQAECgYICAABAAAAAA==.Buldozz:BAAANQAECgQIBAAAAA==.Burnination:BAAANQAECgIIAgAAAA==.Burnzie:BAAANQADCgYIBgAAAA==.Butterfayce:BAAANQAECgIIAgAAAA==.',
Ca='Cadastrasz:BAAANQAECgUIBwAAAA==.Cae:BAAANQADCgMIAwAAAA==.Camachopres:BAAANQADCgQIBgAAAA==.Cameocreme:BAAANQADCgYICgAAAA==.',
Ce='Ceenit:BAAANQAECgIIAgAAAA==.',
Ch='Chainedfire:BAAANQADCgQIBAAAAA==.Chasefu:BAAANQADCgQIBAABNQAECgUIBwABAAAAAA==.Chasefury:BAAANQADCgMIAwABNQAECgUIBwABAAAAAA==.Chasemon:BAAANQAECgUIBwAAAA==.Chaser:BAAANQADCgUIBQABNQAECgUIBwABAAAAAA==.Chasergoonie:BAAANQADCgUICQABNQAECgUIBwABAAAAAA==.Chaøtical:BAAANQADCgYICQAAAA==.Chelsilly:BAAANQADCggIDwAAAA==.Chicosan:BAAANQADCgIIBAAAAA==.Chowfu:BAAANQADCgEIAQAAAA==.',
Co='Corien:BAAANQADCgIIAgAAAA==.',
Cr='Crow:BAAANQAECgcIDQAAAQ==.',
Cy='Cyndraexa:BAAANQADCgYICAAAAA==.Cynia:BAAANQADCgYICQAAAA==.Cyrene:BAABNQAFFIEGAAMCAAQJuxDyAABWAQACAAQJuxDyAABWAQADAAEJhBLjAQBWAAAAAA==.',
Da='Daizy:BAAANQADCgYIBgAAAA==.Darthbane:BAAANQADCgYIBgAAAA==.Darthvada:BAAANQADCgYICwAAAA==.Darthzannah:BAAANQABCgQIBAAAAA==.',
De='Demonaria:BAAANQAECgIIAgAAAA==.Denariah:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Derpnface:BAAANQADCgYICAAAAA==.Desecration:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.',
Di='Diablos:BAAANQABCgQIBAAAAA==.Dirgir:BAAANQADCgcIDQAAAA==.Disk:BAAANQAECgYICAAAAA==.Distonia:BAAANQADCgYICQAAAA==.',
Dr='Dracheo:BAAANQAECgYICAAAAA==.Dragonbrr:BAAANQADCgMIAwABNQAECgMIBgABAAAAAA==.Drakmore:BAAANQADCgUIBQABNQADCgYIBwABAAAAAA==.Drakonna:BAAANQADCgYIBwAAAA==.Drazz:BAAANQADCgIIAgABNQADCggIGgABAAAAAA==.Dreygur:BAAANQADCgYIBgAAAA==.Droiden:BAAANQADCgYICgAAAA==.Droidetté:BAAANQABCgQIBAAAAA==.Drotar:BAAANQADCggIDgAAAA==.',
Du='Dumbdog:BAAANQAECgQIBQABNQAECggIDgABAAAAAA==.Dumichauch:BAAANQAECgYICAAAAA==.',
Eg='Egadwall:BAAANQADCgIIAgAAAA==.Eggars:BAAANQADCgYIBgAAAA==.',
Ek='Ekhor:BAAANQADCgQIBAAAAA==.',
Ev='Eviltiger:BAAANQAECgQIBAAAAA==.',
Ew='Ewik:BAAANQAECgIIAgAAAA==.',
Fa='Faent:BAAANQADCggIDgAAAA==.Falimonki:BAAANQADCggIDgAAAA==.Falinora:BAAANQAECgYICAAAAA==.Fantasticfox:BAAANQAECgUIBwAAAA==.Fattyx:BAAANQAECgUICgAAAA==.',
Fe='Felborn:BAAANQABCgMIAgABNQABCgMIAwABAAAAAA==.Felixs:BAAANQADCgYICAAAAA==.Feodin:BAAANQAECgYICAAAAA==.',
Fi='Fistariir:BAAANQADCggICAABNQAECgcICQABAAAAAA==.',
Fl='Flannigan:BAAANQABCgMIAwAAAA==.Flatsham:BAAANQADCgUIBQAAAA==.',
Fr='Friean:BAAANQADCgYIDAAAAA==.Frostitut:BAAANQAECgIIAgAAAA==.',
Fu='Fuzzychunks:BAAANQADCgUIBwAAAA==.',
Ga='Gabapentin:BAAANQADCgQIBAAAAA==.Gano:BAEANQADCggIDgABNQAECgQIBgABAAAAAA==.Gazdk:BAAANQADCgcIDAAAAA==.',
Gl='Glitch:BAAANQADCgUIBQABNQADCgYICQABAAAAAA==.',
Go='Goonthar:BAAANQAECgYIBgAAAA==.Gorethak:BAAANQADCgYIBwAAAA==.',
Gr='Grindrage:BAAANQAECgEIAQAAAA==.Gripmedaddy:BAAANQAECgEIAQAAAA==.Grollgrr:BAAANQADCgUIDAAAAA==.Grompo:BAAANQAECgEIAQAAAA==.Grompy:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Gruffnstuff:BAAANQADCgYICAAAAA==.',
Gy='Gyxx:BAAANQADCggICAAAAA==.',
Ha='Haddice:BAAANQADCgYICwAAAA==.Hammerdaddy:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
He='Heebiejeebie:BAAANQADCgYICwAAAA==.Hellaeus:BAAANQADCggIDQAAAA==.Henne:BAEANQADCgMIAwAAAA==.Heswithme:BAAANQADCgEIAQAAAA==.',
Hi='Hisokä:BAAANQAECgIIAgAAAA==.',
Ho='Holycreambar:BAAANQADCgYICwABNQADCgcICwABAAAAAA==.',
Hu='Huckanimal:BAAANQADCgYIBgAAAA==.Huntingale:BAAANQADCgUIBQAAAA==.Hurajin:BAAANQADCgEIAQAAAA==.',
Hy='Hygelak:BAAANQADCgYICwAAAA==.Hypaxia:BAAANQADCgUICgAAAA==.',
Im='Immoc:BAAANQADCggIDgAAAA==.Impresario:BAAANQADCgYIBgAAAA==.',
In='Infidius:BAAANQADCggICAAAAA==.Intodeep:BAAANQADCggIDQAAAA==.',
Ja='Jagons:BAAANQADCgIIAgAAAA==.Jahfar:BAAANQADCgUIBgAAAA==.Janara:BAAANQADCgYIBgAAAA==.',
Je='Jehtlock:BAAANQAECgIIAgAAAA==.',
Ji='Jimvisible:BAAANQAECgIIAwAAAA==.',
Jo='Johadro:BAAANQADCgYIBgAAAA==.',
Ju='Judgenawt:BAAANQADCgQIBQAAAA==.',
Ka='Kallum:BAAANQAECgEIAQAAAA==.Kaltak:BAAANQADCggIAgAAAA==.Karn:BAAANQAECgIIAgAAAA==.Karzdormi:BAEANQAECgYICAAAAA==.Kassicker:BAAANQADCgYIBgAAAA==.Kayyllynt:BAAANQAECgQIBAAAAA==.',
Ke='Kennaea:BAAANQADCggIDgABNQAECgYICAABAAAAAA==.',
Ki='Kinuye:BAAANQADCggICAAAAA==.',
Kr='Kraio:BAAANQADCgYICwAAAA==.',
La='Lacatrina:BAAANQAECgEIAQAAAA==.Lampard:BAAANQAECgMIAwAAAA==.Langtry:BAAANQADCggIDQABNQAECgMIAwABAAAAAA==.Laraj:BAAANQAECgQIBwAAAA==.Larissaqt:BAEANQAECgcICgAAAA==.Latinhunter:BAAANQADCgYIBgAAAA==.Latinshamy:BAAANQADCgUICQAAAA==.Lavande:BAAANQADCgUIBQAAAA==.',
Le='League:BAAANQADCgUIBQAAAA==.Leara:BAAANQADCggIDgABNQAECgYICAABAAAAAA==.Legomyagro:BAAANQAECgIIAgAAAA==.Lenipi:BAAANQADCgQIBAAAAA==.',
Li='Lightshootx:BAAANQADCgcICwAAAA==.Lilbessy:BAAANQADCgYICwAAAA==.Lizzia:BAAANQADCggIDgAAAA==.',
Lo='Loathe:BAAANQABCgQIBAAAAA==.Lonchainyjr:BAAANQADCgIIAgAAAA==.',
Lu='Lunabellz:BAAANQADCgYICwAAAA==.Lunavia:BAAANQADCgMIAwAAAA==.Luxembourge:BAAANQADCgUIBQAAAA==.',
Ma='Maalgus:BAAANQAECgEIAQAAAA==.Mad:BAAANQADCgEIAQAAAA==.Maery:BAAANQADCgEIAQAAAA==.Maladash:BAAANQADCgIIAgABNQAECgYICAABAAAAAA==.Manachi:BAAANQADCggICAAAAA==.Mananandict:BAAANQADCgYIBgAAAA==.Margoul:BAAANQADCgYIBgAAAA==.Mayyhem:BAAANQAECggIDgAAAA==.',
Mc='Mcallister:BAAANQADCgYICwAAAA==.',
Me='Mechee:BAAANQADCgUICAAAAA==.Mercý:BAAANQADCgEIAQAAAA==.Metch:BAAANQADCgYICQAAAA==.',
Mi='Mimiker:BAAANQAECgYICAAAAA==.Mimilock:BAAANQADCggIDgABNQAECgYICAABAAAAAA==.Minime:BAAANQADCggIEAABNQAFFAEIAQABAAAAAA==.Miniobi:BAAANQADCgUIBQAAAA==.Mizahella:BAAANQADCgEIAQAAAA==.',
Mo='Mobo:BAAANQADCgYICAAAAA==.Mofassa:BAAANQADCgEIAQAAAA==.Mojoso:BAAANQADCgYICwAAAA==.Mondragore:BAAANQAECgQIBAAAAA==.Moonsilver:BAAANQADCggICAAAAA==.Moriko:BAAANQAECgUIBQAAAA==.Mourn:BAAANQAECgYICAAAAA==.',
Mu='Muertomarrow:BAAANQADCgQIBAAAAA==.Mulroth:BAAANQADCgYIBgAAAA==.Mustardseed:BAAANQAECgIIAgAAAA==.',
Na='Naeblis:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Naliannagoat:BAAANQADCgcIBwAAAA==.Narekstwin:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Nasrith:BAAANQAECgIIAgAAAA==.Nastro:BAAANQADCgEIAQAAAA==.Naughtica:BAAANQADCgYICgAAAA==.Navellint:BAAANQADCgUICgAAAA==.Nawtifox:BAAANQADCgYIBgAAAA==.Nawtishot:BAAANQAECgIIAgAAAA==.',
Ne='Neeb:BAAANQADCgYIBgAAAA==.Nekk:BAAANQADCgYICQAAAA==.',
Ni='Niraleth:BAAANQADCgMIBQAAAA==.Nitebrite:BAAANQADCgYICQAAAA==.',
No='Noimia:BAAANQAECgEIAQAAAA==.Normanosborn:BAAANQADCgIIAgAAAA==.Notfali:BAAANQAECgYICAAAAA==.',
Ob='Obscûr:BAAANQADCgYICAAAAA==.',
Ok='Oksanabaiul:BAAANQADCggICAABNQAECgYIBwABAAAAAA==.',
Om='Omgitsashami:BAAANQADCgYICQAAAA==.',
Op='Oprawinfury:BAAANQADCgYIBgAAAA==.',
Or='Orcanist:BAAANQADCgYICQAAAA==.',
Os='Osanyin:BAAANQADCgcIBwAAAA==.',
Pa='Padray:BAAANQAECgYICAAAAA==.Panhia:BAAANQADCgYICgAAAA==.',
Pe='Pen:BAAANQADCggIDgAAAA==.Pepperbottom:BAAANQADCggIDgAAAA==.Perforation:BAAANQAECgQIBQAAAA==.',
Pf='Pfft:BAAANQADCgUICAABNQAECgEIAQABAAAAAA==.',
Ph='Phoebere:BAAANQADCgUIBgAAAA==.Phungi:BAAANQAECgEIAQAAAA==.',
Pi='Pinocclio:BAAANQADCgIIAgAAAA==.',
Po='Pocketwizard:BAAANQADCgYIBgAAAA==.Pomelo:BAAANQADCgUIBwAAAA==.Popeums:BAAANQADCgYIBgAAAA==.Poppyqtpi:BAAANQADCgYICQAAAA==.Poyoh:BAAANQAECgIIAgAAAA==.',
Pr='Pravoce:BAAANQADCggIDgAAAA==.',
Ra='Radjason:BAAANQADCgcIFQAAAA==.Raeagald:BAAANQADCggIDgABNQAECgYICAABAAAAAA==.Raelyni:BAAANQAECgIIAgAAAA==.Rakkah:BAAANQAECgUIBgAAAA==.Rakkuh:BAAANQADCgUICAABNQAECgUIBgABAAAAAA==.Rawrie:BAAANQADCggIDAAAAA==.Rayzorevoker:BAAANQADCgUIBQAAAA==.Rayzorlock:BAAANQADCggICgAAAA==.',
Re='Reconetta:BAAANQAECgMIAwAAAA==.Redhilda:BAAANQADCgQICAAAAA==.Relyk:BAAANQADCgEIAQAAAA==.',
Ro='Rogersoner:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Rotation:BAAANQADCgYICwAAAA==.Rotblade:BAAANQADCggIDwAAAA==.',
Ru='Runandhide:BAAANQADCgMIAwAAAA==.',
Ry='Ryanthomas:BAAANQADCgMIBQAAAA==.',
Sa='Sammabamma:BAAANQAECgEIAQAAAA==.Sapheer:BAAANQADCgQIBAAAAA==.Sathenoth:BAAANQADCgEIAQAAAA==.Sañtoro:BAAANQADCgYICwAAAA==.',
Sc='Scy:BAAANQADCgUICQAAAA==.',
Sh='Shadowmorn:BAAANQADCggIDQAAAA==.Shambali:BAAANQAECgQIBAAAAA==.Shamidozz:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Shandro:BAAANQAECgIIAgAAAA==.Shaniallon:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Shaunï:BAAANQADCgUIBQAAAA==.Showong:BAAANQAECgEIAQAAAA==.',
Si='Silentbruce:BAAANQAECgIIAgABNQAECgYICQABAAAAAA==.Silentchill:BAAANQAECgYICQAAAA==.Sinomen:BAAANQADCggICAABNQAECgkJGgAEAIIdAA==.',
Sk='Skyblue:BAAANQADCgYIBgAAAA==.',
So='Sonarak:BAAANQAECgIIAgAAAA==.Sornafayne:BAAANQADCgQIBAAAAA==.Sorrengail:BAAANQADCgYICwAAAA==.',
Sp='Spy:BAAANQADCgQIBAAAAA==.',
St='Starrie:BAAANQADCggIDgAAAA==.Steelhoof:BAAANQAECgUIBwAAAA==.Steil:BAAANQADCgEIAQAAAA==.Steponmyface:BAAANQADCgcIBwABNQADCgcICwABAAAAAA==.Stonesoul:BAAANQADCgcIBwAAAA==.Stories:BAAANQAECgIIAgAAAA==.Stormfury:BAAANQAECgIIAgAAAA==.Strucker:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Struckrucker:BAAANQAECgIIAgAAAA==.',
Su='Succubussi:BAAANQAECgUIBwAAAA==.Sushie:BAAANQADCgIIAgABNQAECgcIDQABAAAAAA==.',
Sy='Synn:BAAANQADCgQIBAAAAA==.Syvina:BAAANQADCgYICAAAAA==.',
Ta='Tabby:BAAANQADCgEIAQAAAA==.Taconight:BAAANQADCgYICwAAAA==.Tallynz:BAAANQADCggICgAAAA==.Tankornot:BAAANQADCggICAAAAA==.Tarasque:BAAANQADCgEIAQAAAA==.Tarlgreyhair:BAAANQADCgQIBAAAAA==.Tarnished:BAAANQADCgcIBwAAAA==.Tateer:BAAANQADCgYICwABNQADCgIIAgABAAAAAA==.Tateerfel:BAAANQADCgIIAgAAAA==.Tawneestone:BAAANQAECgIIAgAAAA==.',
Te='Teedizzle:BAAANQADCgYIBgAAAA==.Teek:BAAANQADCgYICwAAAA==.Telandaraa:BAAANQAECgUIBgAAAA==.',
Th='Theldara:BAAANQAECgYICAAAAA==.Themock:BAAANQADCgYICAAAAA==.Theresjohnny:BAAANQADCgEIAQAAAA==.Theshift:BAAANQAECgQICAAAAA==.Thoreen:BAAANQADCgEIAQAAAA==.Thrish:BAAANQAECgYIBwAAAA==.Thuggies:BAAANQADCggICAAAAA==.Thunderfist:BAAANQADCggIEAABNQAECgYICAABAAAAAA==.',
To='Totemiclord:BAAANQAECgQIBQAAAA==.',
Ts='Tsavo:BAAANQADCgYICgAAAA==.',
Tu='Tukarm:BAAANQADCgQIBAAAAA==.',
Tw='Twixbolt:BAAANQADCgcICwAAAA==.',
Ub='Ubpriest:BAAANQADCgUICQAAAA==.',
Va='Vampyre:BAAANQADCgIIAgAAAA==.Vayne:BAAANQAECgYICAAAAA==.',
Vi='Vindenna:BAAANQADCggICgAAAA==.Vinge:BAEANQAECgQIBgAAAA==.Violetxx:BAAANQADCgYICwAAAA==.Viral:BAAANQADCgIIAgAAAA==.',
Vo='Voltaic:BAAANQADCgYIDQABNQAECgQIBQABAAAAAA==.',
Vr='Vraylaros:BAAANQAECgIIAgAAAA==.',
Vy='Vyrista:BAAANQADCgYICgAAAA==.Vyrzeth:BAAANQADCgEIAQAAAA==.Vyzualize:BAAANQAECgQIBAAAAA==.',
Wa='Wae:BAAANQADCgYIBgAAAA==.Waknipi:BAAANQADCgEIAQAAAA==.Wartooth:BAAANQADCgYICQAAAA==.Waycaps:BAAANQAECgYICAAAAA==.',
Wh='Wheresjohnny:BAAANQAECgIIAgAAAA==.',
Wi='Wiccked:BAAANQAECgQIBQAAAA==.Wildheitt:BAAANQAECgIIAgAAAA==.Windrange:BAAANQADCggIDgAAAA==.',
Wo='Wonderpally:BAAANQADCgYICgAAAA==.Woodscale:BAAANQADCgEIAQAAAA==.Wovenbones:BAAANQAECgUIBwAAAA==.',
Xx='Xxthequeenbe:BAAANQADCgIIAgAAAA==.',
Ye='Yergat:BAAANQAFFAEIAQAAAA==.',
Yu='Yuhon:BAAANQADCgYIBgAAAA==.Yupa:BAAANQAECgIIAgABNQAECgUIBQABAAAAAA==.Yuzuruhanyu:BAAANQADCgYIBgABNQAECgYIBwABAAAAAA==.',
Za='Zafira:BAAANQADCgcIBwAAAA==.Zainea:BAAANQAECgYICwABNQADCgcIBwABAAAAAA==.',
Ze='Zelblades:BAAANQADCggIDQABNQAECgUIBQABAAAAAA==.Zelrex:BAAANQAECgUIBQAAAA==.Zephyrà:BAAANQADCgUIBQAAAA==.Zerazer:BAAANQADCgIIAgAAAA==.',
Zh='Zhuntyr:BAAANQADCgUICgAAAA==.',
Zi='Ziggedion:BAAANQAECgIIAgAAAA==.Zindar:BAAANQADCgYICQAAAA==.',
Zo='Zolpidem:BAAANQADCgQIBAAAAA==.',
['Zò']='Zòmi:BAAANQAECgUIBgAAAA==.',
['Ár']='Áres:BAAANQAECgIIAgAAAA==.',
['Ðr']='Ðrstrange:BAAANQAECgEIAQAAAA==.',
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
