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

local lookup = {'Unknown-Unknown','Priest-Holy','DeathKnight-Unholy','DeathKnight-Frost',}
local provider = {region='US',realm='Alleria',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abnalem:BAAANQADCgIIAgAAAA==.',
Ai='Aisele:BAAANQADCgYICgAAAA==.',
Al='Alathir:BAAANQADCgYIBgAAAA==.Alluri:BAAANQAECgIIAgAAAA==.Althemia:BAAANQADCgUIBgAAAA==.Alunamora:BAAANQAECgIIAwAAAA==.Alwind:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.',
An='Analani:BAAANQADCgQIBgAAAA==.Anali:BAAANQADCgYIBgAAAA==.Angis:BAAANQADCgQIBgAAAA==.Angryheals:BAAANQADCgYIBgAAAA==.Ansfrid:BAAANQADCgQIBgAAAA==.',
Ap='Apøllø:BAAANQADCggICgAAAA==.',
Aq='Aquatofana:BAAANQADCgYIBgAAAA==.',
Ar='Arcamancer:BAAANQADCgUICgAAAA==.Arinthal:BAAANQADCgYICQAAAA==.Arril:BAAANQADCgYIEAAAAA==.Artemissy:BAAANQADCgEIAQAAAA==.Artiis:BAAANQADCggICAAAAA==.',
As='Ashlieghee:BAAANQADCggIDwAAAA==.Astien:BAAANQADCgYICwAAAA==.',
Au='Audric:BAAANQADCgYIBwAAAA==.',
Av='Avelen:BAAANQAECgIIAwAAAA==.Avha:BAAANQADCgYICwAAAA==.Avistero:BAAANQADCgIIAgAAAA==.',
Ax='Axel:BAAANQAECgQIBAAAAA==.',
Ay='Aylden:BAAANQAECgQICAAAAA==.Aylshm:BAAANQADCgYIDgAAAA==.Ayrene:BAAANQABCgQIBAABNQAECgUIBQABAAAAAA==.',
Az='Azenazar:BAAANQADCgEIAQAAAA==.',
Ba='Bailas:BAAANQADCgEIAQAAAA==.',
Be='Beastmehr:BAAANQADCgcIBwABNQAECgQIBwABAAAAAA==.Beauregardl:BAAANQADCgYICwAAAA==.Belwyn:BAAANQADCgUIBgAAAA==.Benjofamin:BAAANQADCgYIBgAAAA==.',
Bi='Bitesize:BAEANQAECgQIBwAAAA==.',
Bl='Blakelivly:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Blashster:BAAANQAECgQIBwAAAA==.',
Bo='Bonemilker:BAAANQAECgcIDQAAAA==.Bopeep:BAAANQAECgQIBAAAAA==.',
Br='Breelyssa:BAAANQADCgUIBQAAAA==.Brenna:BAAANQADCgcIBwAAAA==.Brewslèé:BAAANQABCgIIAgAAAA==.Brighter:BAAANQAECgQIBwAAAA==.Brightsize:BAEANQADCgcIBwABNQAECgQIBwABAAAAAA==.Broncopally:BAAANQADCgQIBAAAAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.',
Ca='Caledwar:BAAANQADCgYICQAAAA==.Calthirstrap:BAAANQAECgcICwAAAA==.Carare:BAAANQADCgQIBAAAAA==.Carnàge:BAAANQADCgMIBAAAAA==.',
Ce='Ceefack:BAAANQADCgUICgAAAA==.Cethin:BAAANQADCgUIBgAAAA==.',
Ch='Cheedar:BAAANQAECgYICQAAAA==.Cherylindrea:BAAANQADCgEIAQAAAA==.Chillwombat:BAAANQADCgIIAgAAAA==.',
Cl='Clayvicar:BAAANQAECgQIBwAAAA==.',
Co='Coridane:BAAANQADCgYICgAAAA==.Corwinfiron:BAAANQADCggICAAAAA==.',
Cr='Crosse:BAAANQADCgUICQAAAA==.Cruellà:BAAANQADCgUICAAAAA==.Cryptcrawler:BAAANQADCgUIBwAAAA==.',
Cy='Cythera:BAAANQAECgcIDQAAAA==.',
['Cá']='Cámus:BAAANQAECgEIAQAAAA==.',
Da='Daammy:BAAANQADCgQIBAAAAA==.Dagren:BAAANQADCggICwAAAA==.Daisy:BAAANQABCgIIAwABNQABCgIIBAABAAAAAA==.Daphine:BAAANQADCgEIAQAAAA==.Darimonk:BAAANQADCgEIAQABNQADCgQIBAABAAAAAA==.Darivara:BAAANQADCgQIBAAAAA==.Darkbeautie:BAAANQADCgUICQAAAA==.Darkcarbon:BAAANQADCgYIEgAAAA==.Darmin:BAAANQABCgQIBAAAAA==.',
De='Deathmask:BAAANQADCgUIBQAAAA==.Deathspal:BAAANQAECgQIBAAAAA==.Dessembrae:BAAANQAECgQIBwAAAA==.Dewkiez:BAEANQAECgQIBwAAAA==.',
Di='Diabolicarl:BAAANQADCggIDgAAAA==.',
Do='Doubledragin:BAAANQAECgQIBQAAAA==.',
Dr='Dragonbelly:BAAANQABCgIIBAAAAA==.Dragondeez:BAAANQABCgQIBAABNQADCgYICgABAAAAAA==.Druidgirls:BAAANQAECgQIBwAAAA==.',
Du='Durogdem:BAAANQADCgYIBgAAAA==.Duskfire:BAAANQABCgIIAgAAAA==.',
Ea='Earthaggie:BAAANQADCgEIAQAAAA==.',
Ed='Edirae:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.',
El='Elenora:BAAANQADCggIDgAAAA==.Ellesmere:BAAANQADCgUICAAAAA==.Elye:BAAANQADCgYIBgAAAA==.',
Em='Emiru:BAAANQADCgUIBQAAAA==.',
En='Encore:BAAANQAECgQIBwAAAA==.',
Eo='Eousphorus:BAAANQAECgUIBwAAAA==.',
Er='Erathen:BAAANQADCggICAAAAA==.',
Eu='Euden:BAAANQADCgQIBAAAAA==.',
Ev='Evelleion:BAAANQADCgQIBAAAAA==.',
Ex='Exoticlord:BAAANQADCgUICQAAAA==.',
Fe='Fenryyr:BAAANQADCgIIAgAAAA==.',
Fi='Fierygrace:BAAANQADCgUIBwAAAA==.Fischl:BAAANQADCgYIDQAAAA==.',
Fl='Flameth:BAAANQAECgQIBgAAAA==.Flirtywombat:BAAANQADCgQIBwAAAA==.',
Fr='Freezrorburn:BAAANQABCgIIAgAAAA==.',
Fu='Fujitto:BAAANQADCgIIAgAAAA==.Fumanchu:BAAANQAECgQIBQAAAA==.',
Ga='Gaamora:BAAANQADCgIIAgAAAA==.Gainsborough:BAAANQAECgQIBAAAAA==.Garagos:BAAANQAECgQIBwAAAA==.',
Ge='Gebuss:BAAANQAECgEIAQAAAA==.',
Gl='Glenraven:BAAANQADCgUIBwAAAA==.',
Go='Goochaddi:BAAANQAECgUIBgAAAA==.',
Gr='Grïpnrïp:BAAANQADCgUICAAAAA==.',
Ha='Halifaxx:BAAANQAECgcICwAAAA==.Harmaa:BAAANQADCgYICgAAAA==.Hawknor:BAAANQADCgYICwAAAA==.',
He='Healthcare:BAAANQAECgUICwABNQAFFAUIBgACAGcHAA==.Heartilly:BAAANQAECgcIDQAAAA==.Herm:BAAANQAECgQIBwAAAA==.',
Ho='Holyfu:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Holysky:BAAANQADCgYIEgAAAA==.Holytim:BAAANQADCggICAAAAA==.Honnik:BAAANQABCgIIAgAAAA==.How:BAAANQAECgIIAwAAAA==.',
Ig='Ignöred:BAAANQADCggICAAAAA==.',
Il='Illidæn:BAAANQAECgMIAwAAAA==.',
Im='Imperîus:BAAANQADCgUIBQABNQAECgcIDQABAAAAAA==.',
In='Inaniel:BAAANQAECgIIAgAAAA==.Inq:BAAANQAECgQIBAAAAA==.',
Ir='Iridaceaë:BAAANQADCgcIDgABNQADCgYIBgABAAAAAA==.Iryris:BAAANQADCggIEAAAAA==.',
Is='Isedeath:BAAANQAECgQIBwAAAA==.Istvankh:BAAANQABCgMIBAABNQADCgEIAQABAAAAAA==.',
Ja='Jaholin:BAAANQADCgEIAQAAAA==.Jaxarus:BAAANQADCgEIAQAAAA==.',
Je='Jenaveive:BAAANQADCgYIBgAAAA==.Jethoisi:BAAANQAECgYICgAAAA==.',
Jn='Jnex:BAAANQAECgEIAQAAAA==.',
Jr='Jrrtrolkien:BAAANQADCgQIBAAAAA==.',
Ju='Judgepain:BAAANQADCgQIBAAAAA==.Judgmental:BAAANQAECgMIAwAAAA==.',
Ka='Kaelysong:BAAANQADCgUIBwAAAA==.Kairah:BAAANQADCgUIBwAAAA==.Kalï:BAAANQADCgYICQAAAA==.Karlil:BAAANQADCgcIBwAAAA==.Kasiene:BAAANQADCgUIBQAAAA==.Kathenset:BAAANQADCgcIDAAAAA==.Kazbea:BAAANQADCgIIAgAAAA==.Kazeral:BAAANQAECgYICAAAAA==.',
Ke='Keener:BAAANQADCgYICQAAAA==.Kelvin:BAAANQABCgQIBAAAAA==.Kerrla:BAAANQADCgcIBwABNQAECgYICAABAAAAAA==.Keylleth:BAAANQADCgQIBgAAAA==.',
Kh='Khalanie:BAAANQADCgcIDQAAAA==.Khamnox:BAAANQADCgYICwAAAA==.Khionia:BAAANQADCggIDwAAAA==.',
Ki='Kidthefrist:BAAANQADCgUIBQAAAA==.Kielnmsoftly:BAAANQADCgYIBgAAAA==.Kilaia:BAAANQADCgUIBwAAAA==.Kirru:BAAANQADCgUICQAAAA==.',
Kn='Knoble:BAAANQADCgQIBAAAAA==.',
Kr='Kreaton:BAAANQADCggIDQAAAA==.Kryt:BAAANQAECgQIBgAAAA==.',
Kx='Kxchiki:BAAANQAECgEIAQAAAA==.',
La='Laei:BAAANQADCggIEAAAAA==.Laserfingies:BAAANQABCgIIAgAAAA==.Lastsun:BAAANQADCgIIAgAAAA==.Lavacakes:BAAANQAECgQIBwAAAA==.',
Le='Lelantoz:BAAANQADCgcIDQAAAA==.Leliel:BAAANQABCgMIBQAAAA==.',
Li='Lidan:BAAANQADCgYICgAAAA==.Liebli:BAAANQADCgQIBAAAAA==.Liltank:BAAANQADCgYICQAAAA==.',
Lo='Logyn:BAAANQADCgIIAgAAAA==.Lotsalock:BAAANQADCgUIBQAAAA==.',
Lu='Luna:BAAANQAECgEIAQAAAA==.Lunarluvgood:BAAANQAECgEIAQAAAA==.',
Ly='Lyrelia:BAAANQADCgYICwAAAA==.',
Ma='Madmetal:BAAANQAECgMIAwAAAA==.Mado:BAAANQADCgcIDAAAAA==.Magicky:BAAANQADCgYICgAAAA==.Mahlkier:BAAANQADCgEIAQAAAA==.Maikego:BAAANQADCgMIAwAAAA==.Malchelo:BAAANQADCgEIAQAAAA==.Malfhunter:BAAANQAECgQIBwAAAA==.Malfshammy:BAAANQADCgcIBwAAAA==.Maligosa:BAAANQADCgIIAgAAAA==.Mantodea:BAAANQADCgUIBwAAAA==.Marmin:BAAANQADCggIDgAAAA==.Marymae:BAAANQADCgEIAQAAAA==.',
Me='Meatstick:BAAANQADCgEIAQAAAA==.Meikai:BAAANQADCgcIDAAAAA==.Melillia:BAAANQADCgIIAgAAAA==.Melted:BAAANQAECgYIBwAAAA==.Merdocki:BAAANQAECgQIBwAAAA==.Merdra:BAAANQAECgEIAQAAAA==.Merdre:BAAANQAECgQIBwAAAA==.',
Mi='Michealhunt:BAAANQADCgIIAgAAAA==.Midory:BAAANQADCgYICwAAAA==.Midranaira:BAAANQADCgEIAQAAAA==.Milkymocha:BAAANQADCgUICQAAAA==.Misscorona:BAAANQADCgMIBQAAAA==.Mistyque:BAAANQADCgQIBgAAAA==.Mithrond:BAAANQADCgEIAQAAAA==.',
Mo='Monalea:BAAANQADCgQIBgABNQAECgIIAgABAAAAAA==.Morcant:BAAANQADCgYIBgAAAA==.Morianoley:BAAANQADCgQIBgAAAA==.Morlu:BAAANQADCgIIAgAAAA==.Mortenson:BAAANQAECgEIAQAAAA==.Mortïmer:BAAANQAECgEIAQAAAA==.Mousee:BAAANQADCgQIBAAAAA==.',
Ms='Msdonnapally:BAAANQADCgUIBwAAAA==.',
['Mö']='Möñk:BAAANQADCgQIBAAAAA==.',
Na='Narallia:BAAANQADCgIIAgAAAA==.Narios:BAAANQADCgYICwAAAA==.',
Ne='Nediem:BAAANQADCgQIBAAAAA==.Neral:BAAANQADCgMIAwAAAA==.',
Ni='Nightmehr:BAAANQAECgQIBwAAAA==.Nightshade:BAAANQADCgYIBgAAAA==.',
No='Nosaj:BAAANQAECgQIBwAAAA==.Novalee:BAAANQADCgEIAQAAAA==.',
Ny='Nyki:BAAANQADCgMIAwAAAA==.',
Od='Odlaw:BAAANQADCgYIDAAAAA==.',
Ol='Olaria:BAAANQADCgYICQAAAA==.Olinax:BAAANQAECgEIAQAAAA==.',
Om='Omalmalha:BAAANQADCgQIBAAAAA==.',
On='Onedruidtion:BAAANQADCgUIBQAAAA==.',
Or='Orlos:BAAANQADCgYICQABNQADCgYICQABAAAAAA==.Oräkk:BAAANQAECgQIBAAAAA==.',
Pa='Padrin:BAAANQADCgQIBAAAAA==.Pandapaws:BAAANQAECgQIBgAAAA==.Papaflask:BAAANQADCgIIBAAAAA==.Parthal:BAAANQADCgEIAQAAAA==.Partyhardly:BAAANQADCggIDwAAAA==.',
Pd='Pdiddi:BAAANQADCgcIDAAAAA==.',
Pe='Pellaeon:BAAANQAECgQIBQAAAA==.Pelt:BAAANQAECgMIBgAAAA==.',
Ph='Phlan:BAEANQADCggIDgAAAA==.Phrostir:BAAANQAECggICAAAAA==.',
Pi='Picklechips:BAAANQADCgEIAQAAAA==.Pillgrimm:BAAANQADCggIDgAAAA==.',
Po='Pointee:BAAANQADCgYICgAAAA==.Poisson:BAAANQAECgQIBQAAAA==.Pookiez:BAEANQADCgcIBwABNQAECgQIBwABAAAAAA==.',
Pr='Providence:BAAANQAECgQIBwAAAA==.',
Qu='Quickmend:BAAANQADCgcIBwAAAA==.Quickpaw:BAAANQAECgQIBwAAAA==.',
Ra='Radell:BAAANQADCgIIAgAAAA==.Rageproof:BAAANQADCgUICgAAAA==.Ragged:BAAANQADCggIDgAAAA==.Raidbloom:BAEANQADCgYICwABNQAECgcIDAABAAAAAA==.Raidshock:BAEANQAECgcIDAAAAA==.Rainsinger:BAAANQADCgUIBwAAAA==.Ramook:BAEANQADCgQIBgAAAA==.Randomchar:BAAANQAECgQIBwAAAA==.Rastann:BAAANQAECgQIBwAAAA==.Ratsdrack:BAAANQADCgMIAwAAAA==.Razdor:BAAANQADCgUIBgAAAA==.',
Re='Reapertoo:BAABNQAECoENAAMDAAgJOSFxEgASAgADAAYJoh5xEgASAgAEAAQJUx5+BwBjAQAAAA==.Redbaron:BAAANQAECgEIAQAAAA==.Reetep:BAAANQADCgUIBwAAAA==.Regeth:BAAANQADCgcIBwAAAA==.',
Ro='Rozalin:BAAANQAECgQIBwAAAA==.',
Ry='Ryoshi:BAAANQAECgQIBwAAAA==.',
['Rò']='Ròòszy:BAAANQADCgYIBwAAAA==.',
Sa='Sacredswords:BAAANQAECgUIBwAAAA==.Sanguinius:BAAANQAECgIIAgAAAA==.Sapphiremist:BAAANQADCgYICwAAAA==.Sayen:BAAANQADCgYIBgAAAA==.',
Sc='Scachity:BAAANQAECgEIAQAAAA==.Scan:BAAANQAECgQIBwAAAA==.Schein:BAAANQAECgEIAgAAAA==.',
Se='Sepulchre:BAAANQAECgQIBQAAAA==.',
Sh='Shadesfault:BAAANQADCgEIAQAAAA==.Shaundakul:BAAANQADCggICAAAAA==.Shnozberries:BAAANQADCgEIAQAAAA==.Shortnstack:BAAANQADCgYICwAAAA==.Shãdow:BAAANQADCgUIBQAAAA==.',
Si='Simori:BAAANQADCgIIAgAAAA==.Sindrel:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.',
Sk='Skawalker:BAAANQAECgQIBwAAAA==.',
Sl='Slaed:BAAANQADCgMIAwAAAA==.Slaynne:BAAANQAECgUIBwAAAA==.',
Sm='Smäug:BAAANQAECgYIDAAAAA==.',
Sn='Snailas:BAAANQADCgEIAQAAAA==.',
So='Sodomn:BAAANQADCgQIBAAAAA==.Solria:BAAANQADCgcIBwAAAA==.Sonnytyphoon:BAAANQADCgYIBgAAAA==.',
Sp='Spex:BAAANQADCgEIAQAAAA==.',
St='Starnex:BAAANQADCgYIBgAAAA==.Styx:BAAANQAECgYICwAAAA==.',
Su='Sukfööt:BAAANQAECgQIBAAAAA==.Sumbatadh:BAAANQADCgUIBAAAAA==.Sunnytyphoon:BAAANQAECgEIAQAAAA==.',
Sw='Swiftholy:BAAANQAECgEIAQAAAA==.',
Sy='Sylvestris:BAAANQAECgEIAQAAAA==.',
Ta='Taiyana:BAAANQADCgcIBwAAAA==.Tangie:BAAANQADCgIIAgAAAA==.Tanklorswift:BAAANQADCgUIBQAAAA==.Tastemycrits:BAAANQADCggICAABNQAECgUIBgABAAAAAA==.',
Td='Tdog:BAAANQADCgMIAwAAAA==.',
Te='Teapot:BAAANQABCgIIAgAAAA==.Tedoseirum:BAAANQAECgQIBAAAAA==.Terpyu:BAAANQADCgEIAQAAAA==.Texasslasher:BAAANQADCgYIBgAAAA==.',
Th='Thedtwo:BAAANQADCgcICwAAAA==.Thorgarrus:BAAANQAECgQIBwAAAA==.',
Ti='Timvoker:BAAANQADCgYIBgAAAA==.',
To='Toddie:BAAANQADCggIDQAAAA==.Tormod:BAAANQADCgcIDQAAAA==.Tourmod:BAAANQADCgUICAAAAA==.',
Tr='Trakkarz:BAAANQADCggIDwAAAA==.Traps:BAAANQADCgUIBQAAAA==.Trashypanda:BAAANQAECgcICQAAAA==.Trays:BAAANQADCgQIBAAAAA==.Tressilly:BAAANQAECgQIBQAAAA==.Trogdorr:BAAANQAECgQIBwAAAA==.Trutert:BAAANQADCgUICgAAAA==.Tryana:BAAANQADCggIDgAAAA==.Trystiana:BAAANQADCgMIBAAAAA==.',
Ty='Tyr:BAAANQAECgQIBQAAAA==.Tyrnova:BAAANQADCggICAAAAA==.',
['Tö']='Töshïrö:BAAANQADCgIIAgAAAA==.',
Uh='Uhope:BAAANQADCgYIBgAAAA==.',
Um='Umbravolt:BAAANQAECgQIBwAAAA==.',
Va='Vaeris:BAAANQADCgQIBwAAAA==.Vakero:BAAANQADCgYICwAAAA==.Valess:BAAANQADCgUIBgAAAA==.Valros:BAAANQADCgYICgAAAA==.Vapor:BAAANQABCgIIAgAAAA==.Vaythan:BAAANQABCgMIAgAAAA==.',
Vi='Victorius:BAAANQADCggICAAAAA==.Viridesa:BAAANQADCgUIBwAAAA==.',
Vo='Voidcore:BAAANQAECgEIAQAAAA==.Voidwalker:BAAANQADCgYIBgABNQAECgcIDQABAAAAAA==.',
Vy='Vysera:BAAANQADCgEIAQAAAA==.',
Wa='Warfarmer:BAAANQADCgYICAAAAA==.',
We='Werenal:BAAANQADCgQIBAAAAA==.',
Wh='Whis:BAAANQADCgYICwAAAA==.Whispernight:BAAANQADCgEIAQAAAA==.',
Wi='Widja:BAAANQADCgEIAQAAAA==.Wiimage:BAAANQAECgQIBQAAAA==.Wiivinelight:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.Wildhus:BAAANQAECgIIAgAAAA==.',
['Wî']='Wîca:BAAANQAECgMIBAAAAA==.',
Xe='Xenowolf:BAAANQADCgQIBAABNQADCgUICQABAAAAAA==.',
Xv='Xvire:BAAANQADCgUIBwAAAA==.',
['Xû']='Xûrû:BAAANQADCgQIAwAAAA==.',
Yc='Yce:BAAANQADCgYICwAAAA==.',
Yo='Yokersen:BAAANQADCggIDgAAAA==.',
Za='Zaeladen:BAAANQADCgUIBwAAAA==.Zambonii:BAAANQADCgcIBwABNQAECgQIBwABAAAAAA==.Zamlock:BAAANQAECgQIBwAAAA==.Zanya:BAAANQADCgUIBwAAAA==.',
Ze='Zeiko:BAAANQADCggIDgAAAA==.Zestychip:BAAANQADCgEIAQAAAA==.Zeäl:BAAANQADCgUIBQAAAA==.',
Zh='Zhaoyun:BAAANQADCgUICQAAAA==.',
Zi='Zilkir:BAAANQAECgQIBwAAAA==.Ziran:BAAANQAECgQIBAAAAA==.Zivadhim:BAAANQADCgIIAgAAAA==.',
Zl='Zlyth:BAAANQADCgUICgAAAA==.',
Zz='Zzvzz:BAAANQADCgYIBgAAAA==.',
['Är']='Ärtrix:BAAANQADCgUIBQAAAA==.',
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
