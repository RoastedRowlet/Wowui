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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Enhancement','Priest-Holy','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Mage-Arcane','Mage-Frost','Warlock-Demonology','Evoker-Devastation','Evoker-Preservation',}
local provider = {region='US',realm='Alleria',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abnalem:BAAANQADCgIIAgAAAA==.',
Ae='Aeakos:BAAANQAECgIIAwABNQAECgQIBwABAAAAAA==.',
Ai='Aisele:BAAANQADCgYICgAAAA==.',
Al='Alastor:BAAANQADCgUIBQAAAA==.Alathir:BAAANQADCgcIBwAAAA==.Alluri:BAAANQAECgMIBQAAAA==.Althemia:BAAANQADCgUIBgAAAA==.Alunamora:BAAANQAECgUICAAAAA==.Alwind:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.',
An='Analani:BAAANQADCgYIDAAAAA==.Anali:BAAANQADCgcIBgAAAA==.Angis:BAAANQADCgQIBwAAAA==.Angryheals:BAAANQADCgcIBgAAAA==.Ansfrid:BAAANQADCgQIBgAAAA==.',
Ap='Apøllø:BAAANQAECgUIBQAAAA==.',
Aq='Aquatofana:BAAANQAECgQIBAAAAA==.',
Ar='Aranel:BAAANQADCgYIBgAAAA==.Arcamancer:BAAANQADCgUICgAAAA==.Arinthal:BAAANQADCgcIDQAAAA==.Arril:BAAANQADCgcIGQAAAA==.Artemissy:BAAANQADCgEIAgAAAA==.Artiis:BAAANQADCggICAAAAA==.',
As='Ashlieghee:BAAANQAECgQIBAAAAA==.Astien:BAAANQADCgcIEgAAAA==.',
Au='Audric:BAAANQADCgYIBwAAAA==.',
Av='Avelen:BAAANQAECgQIBwAAAA==.Avha:BAAANQADCgcIDwAAAA==.Avistero:BAAANQADCgUIBwAAAA==.',
Ax='Axel:BAAANQAECgYICgAAAA==.',
Ay='Aylden:BAAANQAECgYIDgAAAA==.Aylshm:BAAANQADCgYIFAAAAA==.Ayrene:BAAANQADCgEIAQAAAA==.',
Az='Azenazar:BAAANQADCgEIAQAAAA==.Azsharianna:BAAANQABCgYICgAAAA==.',
Ba='Bailas:BAAANQADCgYIBwAAAA==.Battousai:BAAANQADCgMIAwAAAA==.',
Be='Beastmehr:BAAANQADCgcIBwABNQAECgcIDgABAAAAAA==.Beauregardl:BAAANQADCgcIDwAAAA==.Bellina:BAAANQADCgcIBwAAAA==.Belwyn:BAAANQADCgUIBgAAAA==.Benjofamin:BAAANQADCgYIDAAAAA==.',
Bi='Bitesize:BAEANQAECgcIDgAAAA==.',
Bl='Blakelivly:BAAANQAECgUIBgABNQAECgUIBgABAAAAAA==.Blashster:BAAANQAECgcIDgAAAA==.',
Bo='Bonemilker:BAABNQAECoEXAAMCAAkJeCS6AQByAwACAAkJMyS6AQByAwADAAMJ/hRaTADRAAAAAA==.Bopeep:BAAANQAECgUIBQAAAA==.',
Br='Breelyssa:BAAANQADCgUIBQAAAA==.Brenna:BAAANQAECgMIAwAAAA==.Brewslèé:BAAANQABCgQIBAAAAA==.Brighter:BAAANQAECgYIDQAAAA==.Brightsize:BAEANQADCggICAABNQAECgcIDgABAAAAAA==.Broncopally:BAAANQADCgQIBAAAAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.',
Ca='Caledwar:BAAANQADCggIEQAAAA==.Calthirstrap:BAAANQAECggIEwAAAA==.Carare:BAAANQADCgYICgAAAA==.Carnàge:BAAANQAECgMIAwAAAA==.',
Ce='Ceefack:BAAANQADCgYIEAAAAA==.Cethin:BAAANQADCgUICwAAAA==.',
Ch='Chaargee:BAAANQADCgYIBgAAAA==.Cheedar:BAAANQAFFAEIAQAAAA==.Cherylindrea:BAAANQADCgEIAgAAAA==.Chillwombat:BAAANQADCgQIBgAAAA==.',
Cl='Clayvicar:BAAANQAECgYIDQAAAA==.',
Co='Coridane:BAAANQAECgEIAQAAAA==.Corwinfiron:BAAANQAECgEIAQAAAA==.',
Cr='Crosse:BAAANQADCgUICQAAAA==.Cruellà:BAAANQADCgYIDgAAAA==.Cryptcrawler:BAAANQADCggIDwAAAA==.',
Cu='Curkage:BAAANQADCgIIAgAAAA==.',
Cy='Cythera:BAABNQAECoEYAAIEAAkJVSOYAAC0AwAEAAkJVSOYAAC0AwAAAA==.',
['Cá']='Cámus:BAAANQAECgIIAwAAAA==.',
Da='Daammy:BAAANQADCgYICgAAAA==.Dagren:BAAANQADCggIEQAAAA==.Daisy:BAAANQABCgQIBQABNQABCgQIBgABAAAAAA==.Daphine:BAAANQADCgEIAgAAAA==.Darimonk:BAAANQADCgEIAQABNQADCgYICgABAAAAAA==.Darivara:BAAANQADCgYICgAAAA==.Darkbeautie:BAAANQADCgYIDwAAAA==.Darkcarbon:BAAANQADCgcIGwAAAA==.Darmin:BAAANQABCgQIBAAAAA==.',
De='Deathmain:BAAANQADCgIIAgABNQAECgUICwABAAAAAA==.Deathmask:BAAANQADCgUIBQAAAA==.Deathspal:BAAANQAECgUICwAAAA==.Dessembrae:BAAANQAECgYIDQAAAA==.Dewkiez:BAEANQAECgYIDQAAAA==.',
Di='Diabolicarl:BAAANQAECgIIAgAAAA==.Diri:BAAANQADCggICAABNQAECgcIDAABAAAAAA==.',
Do='Docphanan:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.Dookiez:BAEANQADCggICAABNQAECgYIDQABAAAAAA==.Doubledragin:BAAANQAECgQICQAAAA==.',
Dr='Dractini:BAAANQADCgMIAwABNQAFFAYICwAFAE8QAA==.Dragonbelly:BAAANQABCgQIBgAAAA==.Dragondeez:BAAANQABCgQIBAABNQADCgcIEQABAAAAAA==.Dragore:BAAANQADCgUIBgAAAA==.Druidgirls:BAAANQAECgcIDgAAAA==.',
Du='Durogdem:BAAANQADCgYIBgAAAA==.Duskfire:BAAANQABCgIIAgAAAA==.',
Ea='Earthaggie:BAAANQADCgEIAgAAAA==.',
Ed='Ederon:BAAANQABCgYIBgAAAA==.Edirae:BAAANQADCgcIBwABNQAECgUICQABAAAAAA==.',
El='Elenora:BAAANQAECgEIAQAAAA==.Ellesmere:BAAANQADCgUICAABNQAFFAYICwAGAF0bAA==.Elye:BAAANQADCggIDAAAAA==.',
Em='Emer:BAAANQAECgQIBAAAAA==.Emiru:BAAANQADCgUIBQAAAA==.',
En='Encore:BAAANQAECgQIDQAAAA==.',
Eo='Eousphorus:BAAANQAECgYIDQAAAA==.',
Er='Erathen:BAAANQADCggICgAAAA==.',
Es='Esplan:BAAANQAECgIIAQABNQAECgUIBgABAAAAAA==.',
Eu='Euden:BAAANQADCgQIBAAAAA==.',
Ev='Evelleion:BAAANQADCggIDAAAAA==.',
Ex='Exoticlord:BAAANQADCgUICQAAAA==.',
Fe='Felhayde:BAAANQADCgYIBgAAAA==.Fenryyr:BAAANQADCgIIAgAAAA==.',
Fi='Fierygrace:BAAANQADCgcIEAAAAA==.Fischl:BAAANQADCgcIEwAAAA==.',
Fl='Flameth:BAAANQAECgYIDAAAAA==.Flirtywombat:BAAANQADCgUIDAAAAA==.',
Fr='Freezrorburn:BAAANQABCgIIAgAAAA==.Frõst:BAAANQABCgMIAwAAAA==.',
Fu='Fujitto:BAAANQADCgIIAgAAAA==.Fumanchu:BAAANQAECgYICwAAAA==.',
Ga='Gaamora:BAAANQADCgIIAwAAAA==.Gainsborough:BAAANQAECgcICwABNQAECgkJGAAHAH4ZAA==.Garagos:BAAANQAECgYIDQAAAA==.',
Ge='Gebuss:BAAANQAECgcICAAAAA==.',
Gl='Glenraven:BAAANQADCgYIDAAAAA==.',
Go='Golokan:BAAANQADCgYIDAAAAA==.Goochaddi:BAAANQAECgcIDAAAAA==.',
Gr='Grïpnrïp:BAAANQAECgEIAQAAAA==.',
Ha='Halifaxx:BAAANQAECgcIDwAAAA==.Haraboo:BAAANQADCggICAAAAA==.Harmaa:BAAANQADCggIEgAAAA==.Havengul:BAAANQADCggIAwAAAA==.Hawknor:BAAANQADCgcIEQAAAA==.',
He='Healthcare:BAABNQAECoEXAAMHAAgJkA0iKADVAQAHAAgJkA0iKADVAQAIAAUJbw0dRwAvAQABNQAFFAYICwAFAE8QAA==.Healthplan:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.Heartilly:BAABNQAECoEYAAIHAAkJfhneDgClAgAHAAkJfhneDgClAgAAAA==.Herm:BAAANQAECgYIDQAAAA==.',
Ho='Holyfu:BAAANQAECgMIAwABNQAECgYICwABAAAAAA==.Holysky:BAAANQADCgYIFAAAAA==.Holytim:BAAANQAECgQIBAAAAA==.Honeypackz:BAAANQADCgYIBwAAAA==.Honnik:BAAANQABCgIIAgAAAA==.Hotpink:BAAANQADCgEIAQAAAA==.How:BAAANQAECgcICgAAAA==.',
Hu='Humongulus:BAAANQAECgEIAQAAAA==.',
Ig='Ignöred:BAAANQAECgQIBAAAAA==.',
Il='Illidæn:BAAANQAECgQIBwAAAA==.',
Im='Imperîus:BAAANQADCgUIBQABNQAECgkJFwACAHgkAA==.',
In='Inaniel:BAAANQAECgMIBAAAAA==.Inq:BAABNQAECoEMAAMJAAcJ5A6rbwCRAQAJAAcJWA2rbwCRAQAKAAEJLgv4HwAxAAAAAA==.',
Ir='Iridaceaë:BAAANQAECgIIAgABNQAECgEIAQABAAAAAA==.Iryris:BAAANQADCggIHQAAAA==.',
Is='Isedeath:BAAANQAECgYIDQAAAA==.Istvankh:BAAANQABCgMIBAABNQADCgEIAQABAAAAAA==.',
Ja='Jaholin:BAAANQADCgEIAQAAAA==.Jarhead:BAAANQADCgIIAgAAAA==.Jaxarus:BAAANQADCgEIAQAAAA==.',
Je='Jenaveive:BAAANQADCgYIBgABNQAECgIIAwABAAAAAA==.Jethoisi:BAAANQAECgYIEAAAAA==.',
Jn='Jnex:BAAANQAECgEIAQAAAA==.',
Jo='Jongani:BAAANQAECgEIAQABNQAECgYIEAABAAAAAA==.',
Jr='Jrrtrolkien:BAAANQADCgQIBAAAAA==.',
Ju='Judgepain:BAAANQADCgUIBQAAAA==.Judgmental:BAAANQAECgUICAAAAA==.',
Ka='Kaelysong:BAAANQADCgUIDAAAAA==.Kairah:BAAANQADCgUICQAAAA==.Kaivig:BAAANQADCgYIBgAAAA==.Kalï:BAAANQADCgYICQAAAA==.Karlil:BAAANQADCggIDwAAAA==.Kasiene:BAAANQADCgUICgAAAA==.Kasnay:BAAANQADCgQIBAAAAA==.Kathenset:BAAANQAECgIIAgAAAA==.Kazbea:BAAANQADCgQIBgAAAA==.Kazeral:BAAANQAECgcIDgAAAA==.Kazzi:BAAANQADCgIIAgAAAA==.',
Ke='Keener:BAAANQAECgEIAQAAAA==.Kelvin:BAAANQABCgQIBAAAAA==.Kerrla:BAAANQADCgcIBwABNQAECgcIDgABAAAAAA==.Keylleth:BAAANQADCgUICAAAAA==.',
Kh='Khalanie:BAAANQAECgMIAwAAAA==.Khamnox:BAAANQADCggIEQAAAA==.Khionia:BAAANQAECgIIAgAAAA==.',
Ki='Kidthefrist:BAAANQADCgUIBQAAAA==.Kielnmsoftly:BAAANQADCgYIBgAAAA==.Kilaia:BAAANQADCggIDwAAAA==.Kirru:BAAANQADCgUICQAAAA==.',
Kn='Knoble:BAAANQADCgQIBAAAAA==.',
Kr='Kreaton:BAAANQADCggIFQAAAA==.Kryt:BAAANQAECgUICwAAAA==.',
Ku='Kuponia:BAAANQABCgIIAgAAAA==.',
Kw='Kwichangpain:BAAANQADCgYIBgAAAA==.',
Kx='Kxchiki:BAAANQAECgMIBAAAAA==.',
La='Laaklem:BAAANQADCgUIBQAAAA==.Laei:BAAANQADCggIEAAAAA==.Laserfingies:BAAANQADCgQIBAAAAA==.Lastsun:BAAANQADCgIIAgAAAA==.Lavacakes:BAAANQAECgYIDQAAAA==.Lawndartz:BAAANQADCgYIBgAAAA==.',
Le='Lelantoz:BAAANQAECgIIAgAAAA==.Leliel:BAAANQABCgMIBQAAAA==.Leqoofus:BAAANQADCgIIAgABNQADCgQIBAABAAAAAA==.',
Li='Lidan:BAAANQADCggIEgAAAA==.Liebli:BAAANQADCgQIBAAAAA==.Liltank:BAAANQADCgYICQAAAA==.Limity:BAAANQADCgIIAgAAAA==.Linaradice:BAAANQAECgIIAgAAAA==.',
Lo='Logyn:BAAANQADCgIIAgAAAA==.Lonelyspark:BAAANQADCgIIAgAAAA==.Lotsalock:BAAANQADCgUIBQAAAA==.',
Lu='Lucifur:BAAANQADCgMIAwAAAA==.Luna:BAAANQAECgQIBQAAAA==.Lunarluvgood:BAAANQAECgUIBgAAAA==.',
Ly='Lyrelia:BAAANQADCgcIDwAAAA==.',
Ma='Madmetal:BAAANQAECgQIBgAAAA==.Mado:BAAANQAECgIIAgAAAA==.Magicky:BAAANQADCgcIEQAAAA==.Mahlkier:BAAANQADCgEIAgAAAA==.Maikego:BAAANQADCgMIAwAAAA==.Mairadin:BAAANQABCgYICgAAAA==.Malchelo:BAAANQADCgEIAQAAAA==.Malfhunter:BAAANQAECgYIDQAAAA==.Malfshammy:BAAANQADCgcIBwAAAA==.Maligosa:BAAANQADCgQIBgAAAA==.Mantodea:BAAANQADCgUICQAAAA==.Marmin:BAAANQAECgQIBAAAAA==.Marymae:BAAANQADCgEIAgAAAA==.',
Me='Meatstick:BAAANQADCgEIAQAAAA==.Meikai:BAAANQAECgIIAgAAAA==.Melillia:BAAANQAECgEIAgAAAA==.Melted:BAAANQAFFAEIAQAAAA==.Merdocki:BAAANQAECgYIDQAAAA==.Merdra:BAAANQAECgQIBQAAAA==.Merdre:BAAANQAECgYIDQAAAA==.',
Mi='Michealhunt:BAAANQADCgIIAgAAAA==.Midory:BAAANQAECgMIAwAAAA==.Midranaira:BAAANQADCgEIAQAAAA==.Milda:BAAANQADCgEIAQAAAA==.Milkymocha:BAAANQADCgUICQAAAA==.Misscorona:BAAANQADCgUICgAAAA==.Mistyque:BAAANQADCgYIDAAAAA==.Mithrond:BAAANQADCgEIAQAAAA==.',
Mo='Monalea:BAAANQADCgQIBgABNQAECgQIBgABAAAAAA==.Morcant:BAAANQADCgcICgAAAA==.Morianoley:BAAANQADCgYIDAAAAA==.Morlu:BAAANQADCggICgAAAA==.Mortenson:BAAANQAECgEIAQAAAA==.Mortïmer:BAAANQAECgEIAgAAAA==.Mousee:BAAANQADCgYICgAAAA==.',
Ms='Msdonnapally:BAAANQADCgUICwAAAA==.',
My='Myxian:BAEANQADCgcIBwABNQAECgcIDgABAAAAAA==.',
['Mö']='Möñk:BAAANQADCgQIBQAAAA==.',
Na='Narallia:BAAANQADCgYICAAAAA==.Narios:BAAANQADCgcIEgAAAA==.',
Ne='Nediem:BAAANQADCgQIBQAAAA==.Neral:BAAANQADCgMIAwAAAA==.',
Ni='Nightmehr:BAAANQAECgcIDgAAAA==.Nightshade:BAAANQADCgcIDQAAAA==.',
No='Nosaj:BAAANQAECgYIDQAAAA==.Novalee:BAAANQADCgEIAQAAAA==.',
Ny='Nyki:BAAANQADCgMIAwAAAA==.',
Od='Odlaw:BAAANQADCgYIEQAAAA==.',
Ol='Olaria:BAAANQAECgEIAQAAAA==.Olinax:BAAANQAECgUIBgAAAA==.',
Om='Omalmalha:BAAANQADCgQIBAAAAA==.',
On='Onedruidtion:BAAANQADCgUIBQAAAA==.',
Or='Orionmoon:BAAANQAECgYIBgAAAA==.Orlos:BAAANQADCggIEQABNQAECgEIAQABAAAAAA==.Oräkk:BAAANQAECgcIDwAAAA==.',
Pa='Padrin:BAAANQADCgUIBQAAAA==.Pandapaws:BAAANQAECgcIDQAAAA==.Papaflask:BAAANQADCgYIDgAAAA==.Parthal:BAAANQADCgEIAQAAAA==.Partyhardly:BAAANQAECgQIBAAAAA==.Pavle:BAAANQAECgIIAgAAAA==.',
Pd='Pdiddi:BAAANQAECgEIAQAAAA==.',
Pe='Pellaeon:BAAANQAECgcIDAAAAA==.Pelt:BAAANQAECgUICwAAAA==.Petmasta:BAAANQABCgEIAQABNQABCgQIBAABAAAAAA==.',
Ph='Phlan:BAEANQAECgQIBAAAAA==.Phrostir:BAAANQAECggIEAAAAA==.',
Pi='Picklechips:BAAANQADCgEIAQAAAA==.Pillgrimm:BAAANQADCggIFwAAAA==.Pillsburyman:BAAANQAECgEIAQAAAA==.',
Po='Pointee:BAAANQADCgYICgAAAA==.Poisson:BAAANQAECgcIDAAAAA==.Pokoxo:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Pookiez:BAEANQADCggIDQABNQAECgYIDQABAAAAAA==.',
Pr='Providence:BAAANQAECgYIDQAAAA==.',
Qu='Quickmend:BAAANQADCggIDwAAAA==.Quickpaw:BAAANQAECgcIDgAAAA==.',
Ra='Raccoons:BAAANQADCgMIAwABNQAECgkJFwALAF4XAA==.Radell:BAAANQADCgIIAgAAAA==.Rageproof:BAAANQAECgEIAQAAAA==.Ragged:BAAANQADCggIFQAAAA==.Raidbloom:BAEANQADCgYIEAABNQAECggIFwAGAE8PAA==.Raidshock:BAEBNQAECoEXAAIGAAgJTw9EIwD8AQAGAAgJTw9EIwD8AQAAAA==.Rainsinger:BAAANQADCgUIDAAAAA==.Ramook:BAEANQADCgQICQAAAA==.Randomchar:BAAANQAECgYIDQAAAA==.Rankor:BAAANQADCgYIBgABNQAECgYIDQABAAAAAA==.Rastann:BAAANQAECgcIDgAAAA==.Ratsdrack:BAAANQADCgMIAwAAAA==.Razdor:BAAANQADCgUIBgAAAA==.',
Re='Reapertoo:BAABNQAECoEWAAMCAAkJ6yEFBAD9AgACAAkJER0FBAD9AgADAAYJoh6PIgDlAQAAAA==.Recreant:BAAANQADCgYIBgAAAA==.Redbaron:BAAANQAECgQIBQAAAA==.Reetep:BAAANQADCgUICQAAAA==.Regeth:BAAANQADCggIDwAAAA==.',
Ro='Rolas:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Rozalin:BAAANQAECgYIDQAAAA==.',
Ru='Rustywarlock:BAAANQABCgQIBAAAAA==.',
Ry='Ryoshi:BAAANQAECgYIDQAAAA==.',
['Rò']='Ròòszy:BAAANQADCgYIBwAAAA==.',
Sa='Sacredswords:BAAANQAECgYIDQAAAA==.Sanguinius:BAAANQAECgUIBwAAAA==.Sapphiremist:BAAANQADCgcIEgAAAA==.Sayen:BAAANQAECgYIBgAAAA==.',
Sc='Scachity:BAAANQAECgQIBQAAAA==.Scan:BAAANQAECgcIDgAAAA==.Schein:BAAANQAECgQIBwAAAA==.',
Se='Sepulchre:BAAANQAECgUICgAAAA==.',
Sh='Shadesfault:BAAANQADCgEIAgAAAA==.Shaundakul:BAAANQAECgMIAwAAAA==.Shnozberries:BAAANQADCgEIAQAAAA==.Shockhart:BAAANQADCgcIBwAAAA==.Shortnstack:BAAANQADCgcIEAAAAA==.Shãdow:BAAANQADCgUIBQAAAA==.',
Si='Simori:BAAANQADCgIIAgAAAA==.Sindrel:BAAANQADCgYIBgABNQAECgcIEAABAAAAAA==.',
Sk='Skawalker:BAAANQAECgcIDgAAAA==.',
Sl='Slaed:BAAANQADCgYIBwAAAA==.Slaynne:BAAANQAECgcIDwAAAA==.',
Sm='Smäug:BAABNQAECoEXAAMMAAkJ3CE8AwAoAwAMAAgJiyI8AwAoAwANAAEJLwHSKQAuAAAAAA==.',
Sn='Snailas:BAAANQADCgEIAQAAAA==.',
So='Sodomn:BAAANQADCgQIBAAAAA==.Solria:BAAANQAECgIIAgAAAA==.Sonnytyphoon:BAAANQADCgYIBgAAAA==.',
Sp='Spex:BAAANQADCgEIAQAAAA==.',
St='Starnex:BAAANQADCgYIBgAAAA==.Statyrea:BAAANQADCgUIBQAAAA==.Styx:BAAANQAECgcIEgAAAA==.',
Su='Sukfööt:BAAANQAECgYICgAAAA==.Sumbatadh:BAAANQAECgEIAQAAAA==.Sunnytyphoon:BAAANQAECgQIBQAAAA==.',
Sw='Swiftholy:BAAANQAECgQIBQAAAA==.',
Sy='Sylvestris:BAAANQAECgQIBQAAAA==.',
Ta='Taiyana:BAAANQADCgcIBwAAAA==.Tangie:BAAANQADCggICgAAAA==.Tankjob:BAAANQADCgYIBgAAAA==.Tanklorswift:BAAANQADCgUIBQAAAA==.Tastemycrits:BAAANQADCggICAABNQAECgcIDAABAAAAAA==.',
Td='Tdog:BAAANQADCggICwAAAA==.',
Te='Teapot:BAAANQABCgIIAgAAAA==.Tedoseirum:BAAANQAECgUICQAAAA==.Terpyu:BAAANQADCgEIAQAAAA==.Texasbilly:BAAANQADCgYIBgAAAA==.Texasredneck:BAAANQADCgYIBgAAAA==.Texasslasher:BAAANQADCgYIBgAAAA==.',
Th='Thedtwo:BAAANQADCgcIDAAAAA==.Thorgarrus:BAAANQAECgcIDgAAAA==.',
Ti='Timvoker:BAAANQADCgYIBgAAAA==.',
To='Toddie:BAAANQAECgIIAgAAAA==.Tommyj:BAAANQADCggICAAAAA==.Tormod:BAAANQAECgMIAwAAAA==.Tourmod:BAAANQAECgEIAQAAAA==.',
Tr='Trakkarz:BAAANQADCggIFgAAAA==.Traps:BAAANQADCgUIBQAAAA==.Trashypanda:BAAANQAECggIEQAAAA==.Trays:BAAANQADCgYIBgAAAA==.Tressilly:BAAANQAECgYICwAAAA==.Trinagirl:BAAANQADCgYIBgAAAA==.Trogdorr:BAAANQAECgYIDQAAAA==.Trutert:BAAANQADCgYIEAAAAA==.Tryana:BAAANQADCggIFgAAAA==.Trystiana:BAAANQADCgMIBAAAAA==.',
Tt='Ttania:BAAANQADCgIIAgAAAA==.',
Ty='Tyr:BAAANQAECgYICwAAAA==.Tyrnova:BAAANQADCggICAAAAA==.',
['Tö']='Töshïrö:BAAANQADCgIIAgAAAA==.',
Uh='Uhope:BAAANQADCgcIBgAAAA==.',
Um='Umbravolt:BAAANQAECgcIDgAAAA==.',
Un='Unravel:BAAANQADCgEIAQAAAA==.',
Va='Vaeris:BAAANQADCgUICwAAAA==.Vakero:BAAANQADCggIDwAAAA==.Valess:BAAANQADCggIDgAAAA==.Valros:BAAANQADCgYICgAAAA==.Vapor:BAAANQABCgIIAgAAAA==.Vaythan:BAAANQADCggICAAAAA==.',
Ve='Venchris:BAAANQADCgUIBAAAAA==.',
Vh='Vhiz:BAAANQAECgQIBAAAAA==.',
Vi='Victorius:BAAANQADCggICAAAAA==.Viridesa:BAAANQADCgUIBwAAAA==.',
Vo='Voidcore:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.Voidwalker:BAAANQADCgYICQABNQAECgkJGAAEAFUjAA==.',
Vy='Vysera:BAAANQADCgUIBgAAAA==.',
Wa='Warfarmer:BAAANQADCgcIDAAAAA==.Warhawke:BAAANQADCgMIAwAAAA==.',
We='Werenal:BAAANQADCgYICgAAAA==.',
Wh='Whis:BAAANQADCgcIEQAAAA==.Whispernight:BAAANQADCgEIAgAAAA==.',
Wi='Widja:BAAANQADCgEIAgAAAA==.Wiimage:BAAANQAECgQIBQAAAA==.Wiivinelight:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.Wildhus:BAAANQAECgQIBgAAAA==.',
Wy='Wyckdd:BAAANQADCgYIBgAAAA==.',
['Wå']='Wåffle:BAAANQADCggICAABNQAECgcICAABAAAAAA==.',
['Wî']='Wîca:BAAANQAECgQICAAAAA==.',
Xe='Xenowolf:BAAANQADCgQIBAABNQADCgYIDwABAAAAAA==.',
Xv='Xvire:BAAANQADCgUICgAAAA==.',
['Xû']='Xûrû:BAAANQADCgYICQAAAA==.',
Yc='Yce:BAAANQADCgcIFAAAAA==.',
Yo='Yokersen:BAAANQADCggIDgAAAA==.',
Za='Zaeladen:BAAANQADCgUICQAAAA==.Zambonii:BAAANQADCggIDwABNQAECgcIDgABAAAAAA==.Zamlock:BAAANQAECgcIDgAAAA==.Zanya:BAAANQADCgUICQAAAA==.',
Ze='Zeiko:BAAANQADCggIDgAAAA==.Zestychip:BAAANQADCgYIBwAAAA==.Zeäl:BAAANQADCgUIBQAAAA==.',
Zh='Zhaoyun:BAAANQADCgUICQAAAA==.',
Zi='Zilkir:BAEANQAECgYIDQAAAA==.Ziran:BAAANQAECggICQAAAA==.Zivadhim:BAAANQADCgIIAgAAAA==.',
Zl='Zlyth:BAAANQAECgEIAQAAAA==.',
Zz='Zzvzz:BAAANQADCgYIBgAAAA==.',
['Är']='Ärtrix:BAAANQADCgUIBQAAAA==.',
['Èn']='Ènyo:BAAANQADCgUIBQAAAA==.',
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
