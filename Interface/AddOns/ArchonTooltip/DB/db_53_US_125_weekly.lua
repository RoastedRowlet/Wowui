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

local lookup = {'Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood',}
local provider = {region='US',realm="Jubei'Thos",name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Activion:BAAANQADCgMIAwAAAA==.',
Ad='Adelanaa:BAAANQAECgUICAAAAA==.Adrasta:BAAANQADCgYICwAAAA==.Adriell:BAAANQAECgIIAgAAAA==.Adura:BAAANQADCgEIAQAAAA==.',
Ae='Aelathe:BAAANQAECgIIAgAAAA==.Aerys:BAAANQABCgIIAgAAAA==.',
Ak='Akey:BAAANQAECgEIAQAAAA==.',
Al='Alamwah:BAAANQADCgEIAQABNQADCgYICQABAAAAAA==.Alaroo:BAAANQABCgIIBAAAAA==.Alektra:BAAANQAECgIIAgAAAA==.Alexella:BAAANQADCgcICQAAAA==.Allerfala:BAAANQADCgQIBAAAAA==.Alliete:BAAANQADCgIIAgAAAA==.Allya:BAAANQADCgMIAQAAAA==.Aloine:BAAANQAECgQIBAAAAA==.',
Am='Amogus:BAAANQADCgUIBQAAAA==.',
An='Anqu:BAAANQADCgMIAwAAAA==.',
Ar='Arbitera:BAAANQAECgIIAgAAAA==.Arzir:BAAANQAECgEIAgAAAA==.',
As='Asmonjoel:BAAANQADCgcIBwAAAA==.Assumi:BAAANQADCgEIAQAAAA==.',
Au='Audree:BAAANQADCgYIBAAAAA==.',
Av='Avoide:BAAANQADCgYICAAAAA==.',
Az='Azamat:BAAANQADCgUIBQAAAA==.Azuredemonx:BAAANQADCgYIBgAAAA==.',
Ba='Backup:BAAANQAECgIIAgAAAA==.',
Bb='Bbajer:BAAANQAECgEIAQAAAA==.Bbqporkbuns:BAAANQAECgQIBwAAAA==.',
Be='Bearzy:BAAANQAECgEIAgAAAA==.Belledormi:BAAANQADCgYIDAAAAA==.Bellest:BAAANQAECgEIAQAAAA==.Benji:BAAANQAECgYICQAAAA==.',
Bf='Bfev:BAAANQAECgEIAQAAAA==.',
Bg='Bggestthighs:BAAANQAECgQIBQABNQAECgYICgABAAAAAA==.',
Bi='Bid:BAAANQADCggIDQAAAA==.Bigado:BAAANQADCggICgAAAA==.Bigarms:BAAANQADCgQIBAABNQADCgcIBwABAAAAAA==.Biggesthighz:BAAANQAECgYICgAAAA==.',
Bl='Bluee:BAAANQADCgYICwAAAA==.',
Bo='Boohbooh:BAAANQADCgUIBQAAAA==.Boomakus:BAAANQAECgYICQAAAA==.',
Br='Brewskie:BAAANQADCgEIAQAAAA==.Brodess:BAAANQAECgUICQAAAA==.Brody:BAAANQAECgYIBwAAAA==.Bromorc:BAAANQADCgQIBgAAAA==.Broner:BAAANQADCggIEAAAAA==.Bronlite:BAAANQADCgIIAwAAAA==.Brotherlee:BAAANQADCgcICwAAAA==.',
Bu='Bubski:BAAANQADCgMIAwAAAA==.Bulimio:BAAANQADCgIIAgAAAA==.Bunzbunnie:BAAANQADCgYIDAAAAA==.Bunzbunny:BAAANQADCgIIAgAAAA==.Buratt:BAAANQADCgQIBgAAAA==.',
['Bé']='Béllâ:BAAANQADCggIAgAAAA==.',
['Bõ']='Bõggie:BAAANQAECgYICgAAAA==.',
Ca='Capacitør:BAAANQADCggICgAAAA==.Cardib:BAAANQAECgQIBQAAAA==.Cattamend:BAAANQAECgMIAwAAAA==.Cattazap:BAAANQAECgEIAgAAAA==.Cauliflawer:BAAANQAECgEIAQAAAA==.Cavoda:BAAANQADCgMIAwAAAA==.',
Ch='Chakrakhan:BAAANQAECgEIAQAAAA==.Char:BAAANQADCgQIBAAAAA==.Chase:BAAANQADCggIDgAAAA==.Chinadh:BAAANQAECgcIDQAAAA==.Chinamage:BAAANQAECgIIAgABNQAECgcIDQABAAAAAA==.Chopzuey:BAAANQADCgQICAAAAA==.Chugtiki:BAAANQAECgQIBQAAAA==.Chuunky:BAAANQABCgIIAgAAAA==.',
Ci='Cinderaz:BAAANQADCgQIBgAAAA==.',
Cl='Clikboomboom:BAAANQADCgEIAQAAAA==.',
Co='Cones:BAAANQADCgEIAQABNQADCgcIBwABAAAAAA==.Conesy:BAAANQADCgYIBAAAAA==.Cordeilia:BAAANQAECgYICgAAAA==.Corruptax:BAAANQADCgcIDgAAAA==.',
Cr='Critsaquino:BAAANQAECgMIAQAAAA==.Crotchsniffa:BAAANQADCggICAAAAA==.',
Cy='Cyberlust:BAAANQADCggICAAAAA==.Cyklar:BAAANQADCgQIBgAAAA==.',
Da='Daddydevito:BAAANQAECgQIBAAAAA==.Dames:BAAANQADCgYIBgAAAA==.Danky:BAAANQADCggIDwAAAA==.Daqueta:BAAANQADCgUIAwAAAA==.Daquetawar:BAAANQADCgYICQAAAA==.Darkniggura:BAAANQADCgcIBwAAAA==.Darkpal:BAAANQAECgMIAwAAAA==.Dazgrim:BAAANQAECgIIAgABNQAECgMIBQABAAAAAA==.Dazzi:BAAANQADCgYIDAAAAA==.',
De='Deathdaddy:BAAANQADCgUIBwAAAA==.Decapitation:BAAANQAECgMIAwAAAA==.Defacedd:BAAANQADCgQIBAAAAA==.Deify:BAAANQADCgUIBgAAAA==.Deliaz:BAAANQADCgQIBgAAAA==.',
Di='Dismarryx:BAAANQAECgEIAQAAAA==.',
Dj='Djapana:BAAANQADCgIIAgAAAA==.',
Dn='Dnomm:BAAANQADCgQIBgAAAA==.',
Do='Dogmuffin:BAAANQADCgMIAwAAAA==.',
Dr='Drakyon:BAAANQADCgYIBgAAAA==.Dreaddlord:BAAANQADCgQIBQABNQAECgEIAQABAAAAAA==.Dreadiedude:BAAANQAECgEIAQAAAA==.Drowlie:BAAANQADCgYIBgAAAA==.',
Du='Durrin:BAAANQADCggIDQAAAA==.Dutchman:BAAANQADCggIDQAAAA==.',
Ef='Effectus:BAAANQAECgMIAwAAAA==.',
Ei='Eith:BAAANQAECgIIAQAAAA==.',
El='Elele:BAAANQABCgQIBAAAAA==.Eljay:BAAANQAECgQIBAAAAA==.Ellell:BAAANQAECgIIBAAAAA==.',
Em='Emberly:BAAANQADCgEIAQAAAA==.',
En='Endersfault:BAAANQAECgQIBQAAAA==.',
Ep='Epicdemoness:BAAANQAECgMIAwAAAA==.',
Er='Eroni:BAAANQADCggICAAAAA==.',
Eu='Euphea:BAAANQADCgEIAQAAAA==.',
Ev='Evaelfie:BAAANQAECgQIBwAAAA==.',
Fe='Felicia:BAAANQAECgIIAgAAAA==.Fellordkiki:BAAANQAECgMIBAAAAA==.',
Fi='Filthydh:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.Filthypally:BAAANQAECgUIBgAAAA==.Fivëam:BAAANQABCgIIAgAAAA==.',
Fl='Flashheart:BAAANQADCgcIBwAAAA==.Fleabag:BAAANQADCgMIAwAAAA==.',
Fo='Foxe:BAEANQADCgMIAwABNQADCgYIBgABAAAAAA==.',
Fr='Freezefauker:BAAANQAECgEIAQAAAA==.Fridge:BAAANQADCgYICQAAAA==.Frostxfury:BAAANQADCgYIBgAAAA==.Frøstynips:BAABNQAECoEfAAICAAkJUCRMAwBCAwACAAkJUCRMAwBCAwAAAA==.',
Fu='Furysgrip:BAAANQAECgQIBQAAAA==.',
Ga='Gabagool:BAAANQADCggIDwAAAA==.Gaidal:BAAANQADCgcICwAAAA==.Galafrey:BAAANQADCgIIAgABNQAECgUIBgABAAAAAA==.Garaktou:BAAANQADCgQICAAAAA==.',
Ge='Gekyum:BAAANQAECgcIDAAAAA==.Getinmyspit:BAAANQAECgMIAwAAAA==.',
Gi='Gidyana:BAAANQADCgYICwAAAA==.Girlsnight:BAAANQADCgQIBwAAAA==.',
Gl='Glancelot:BAAANQADCgYIBwAAAA==.Glipglorp:BAAANQADCgQIBAAAAA==.',
Go='Gommo:BAAANQADCgIIAgAAAA==.Gorbad:BAAANQADCggIDQAAAA==.',
Gr='Groundizzle:BAAANQADCggICAAAAA==.',
Gu='Guanyu:BAAANQADCgcIDQAAAA==.Guccisosa:BAAANQADCgYIBgAAAA==.Guineamon:BAAANQADCgEIAQAAAA==.',
Ha='Haruk:BAAANQAECgQIBAAAAA==.',
He='Heatfist:BAAANQADCgcICgAAAA==.Heåls:BAAANQADCgcIDQAAAA==.',
Ho='Hoelishock:BAAANQADCgcIBwAAAA==.Hollynova:BAAANQADCgcIDAAAAA==.Holychad:BAAANQAECgMIBAAAAA==.Honeydew:BAAANQAFFAEIAQAAAA==.Honganteresa:BAAANQADCggICAAAAA==.Hoofmax:BAAANQADCgIIAgAAAA==.',
['Hø']='Høtdøts:BAAANQAECgEIAQAAAA==.',
Il='Illidank:BAAANQAECgMIAQAAAA==.',
Im='Imperiex:BAAANQADCgEIAQAAAA==.',
Io='Ionsw:BAAANQAECgQIBAAAAA==.',
Ja='Jackillz:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Jatzsy:BAAANQADCgYIDAAAAA==.Jayar:BAAANQAECgEIAQAAAA==.',
Je='Jee:BAAANQADCgYIBwAAAA==.Jescon:BAAANQAECgIIAgAAAA==.Jeé:BAAANQADCgUIBQAAAA==.',
Ji='Jiamil:BAAANQAECgIIAwAAAA==.Jigolow:BAAANQADCgUIBQAAAA==.',
Jo='Johlissa:BAAANQAECgIIAgAAAA==.',
Ju='Jubber:BAAANQADCggICwAAAA==.',
Ka='Kadashy:BAAANQAECgEIAQAAAA==.Kaherd:BAAANQADCgYIBgAAAA==.Kamikasi:BAAANQADCgMIBAAAAA==.Karytheca:BAAANQADCgYIBAAAAA==.Katae:BAAANQAECgYICgAAAA==.Kayrali:BAAANQADCgIIAgAAAA==.',
Ke='Kegaz:BAAANQADCgMIAwAAAA==.Kegward:BAAANQADCgUIBQAAAA==.Kendd:BAAANQAFFAEIAQAAAA==.Kerrigân:BAAANQADCgIIAgAAAA==.',
Ki='Kithari:BAAANQAECgEIAQAAAA==.',
Kn='Knickerbits:BAAANQABCgEIAQAAAA==.Knotting:BAAANQADCggIDgAAAA==.',
Ko='Kollateral:BAAANQADCgYICwAAAA==.',
Kr='Krankiekunt:BAAANQAECgYICQAAAA==.Krellhim:BAAANQADCgMIAwAAAA==.',
Ku='Kuanija:BAAANQAECgQIBAAAAA==.',
La='Landwalker:BAAANQAECgYICQAAAA==.Langas:BAAANQADCggICAABNQAECgYIBgABAAAAAA==.Langasbrew:BAAANQAECgYIBgAAAA==.Latorius:BAAANQAECgEIAQAAAA==.Lavaloadz:BAAANQADCgUIBQAAAA==.Lazziel:BAAANQADCgcIDQAAAA==.',
Le='Lexavis:BAAANQAECgcICwABNQAECgEIAgABAAAAAA==.Leyiast:BAAANQADCgYICgAAAA==.Leyissa:BAAANQADCgIIAgABNQADCgYICgABAAAAAA==.',
Lh='Lheo:BAAANQADCgYICAAAAA==.',
Li='Liggma:BAAANQAECgEIAQAAAA==.Lilwhite:BAAANQADCgYICQAAAA==.',
Lo='Lockaboom:BAAANQADCgMIAwAAAA==.Loldruid:BAAANQAECgEIAQAAAA==.Lom:BAAANQADCgUIBQAAAA==.Lomzz:BAAANQADCgIIAgAAAA==.',
Ly='Lycan:BAAANQADCgEIAQAAAA==.Lynarium:BAAANQAECgEIAQAAAA==.',
Ma='Magepill:BAAANQADCgQIBAAAAA==.Magharitta:BAAANQAECgEIAQAAAA==.Mahwae:BAAANQADCgIIAwAAAA==.Manoliso:BAAANQADCgIIBAAAAA==.',
Me='Medesin:BAAANQADCgQIBgAAAA==.Mekhanite:BAAANQAECgEIAQAAAA==.',
Mi='Milspec:BAAANQADCggICAAAAA==.Minami:BAAANQAECgEIAQAAAA==.Minhiriath:BAAANQADCgQIBAAAAA==.Mintbadger:BAAANQADCgUIBwAAAA==.',
Mo='Mochimask:BAAANQADCgIIAgAAAA==.Moetown:BAAANQADCggICAABNQAECgcIDwABAAAAAA==.Moistmaker:BAAANQAECgIIBAAAAA==.Momotaku:BAAANQADCggIDwAAAA==.Monalisa:BAAANQADCgYICAAAAA==.Monkmon:BAAANQADCgIIAgABNQADCggICwABAAAAAA==.Moonoo:BAAANQADCgUIBQAAAA==.Morena:BAAANQADCgUIBgAAAA==.Morgaina:BAAANQADCgcIDQAAAA==.',
Mu='Muffinman:BAAANQADCggIAgABNQAECgYIBgABAAAAAA==.Muscleclub:BAAANQADCgcIBwAAAA==.',
Na='Naeff:BAAANQADCggIBQAAAA==.Natria:BAAANQADCgcIBwAAAA==.Naya:BAAANQAECgQIBAAAAA==.',
Ne='Nerfdelag:BAAANQAECgIIAgAAAA==.Nerfgün:BAAANQAECgUIBgAAAA==.',
No='Nonippies:BAAANQAECgEIAQAAAA==.',
Ns='Nsi:BAAANQADCgUIBQAAAA==.',
Nu='Nutsdormu:BAAANQAECgQIBgAAAA==.',
Ny='Nythe:BAAANQADCgEIAQAAAA==.Nyxmoona:BAAANQADCgQIBgAAAA==.',
['Nà']='Nàishà:BAAANQADCggICwAAAA==.',
Ob='Obskurer:BAAANQADCgcIDAAAAA==.',
Od='Odinwolf:BAAANQAECgMIBAABNQAECgcIDAABAAAAAA==.',
Oj='Ojisancage:BAAANQAECgIIBAAAAA==.',
Om='Omnitract:BAAANQADCgYIBQAAAA==.',
Or='Orinys:BAAANQADCgYIBgAAAA==.Orkky:BAAANQAECgIIAgAAAA==.',
Pa='Page:BAAANQAECgYICQAAAA==.Pakurruun:BAAANQADCgYIBgAAAA==.Pallatress:BAAANQADCgQIBgAAAA==.Pandor:BAAANQADCgEIAQAAAA==.Panginoon:BAAANQAECgQIBAAAAA==.Paparìch:BAAANQAECgQIBgAAAA==.Paphio:BAAANQADCgYICgAAAA==.',
Pe='Pesh:BAAANQADCgQIBwAAAA==.',
Pg='Pgundry:BAAANQADCggIDgAAAA==.',
Pi='Piddlesworth:BAAANQADCggIEQAAAA==.Piergeiron:BAAANQADCgYICwAAAA==.Pinkyblue:BAAANQAECgQIBQAAAA==.Pipssqeek:BAAANQADCgUIBQAAAA==.',
Pj='Pjw:BAAANQAECgUICAAAAA==.',
Pl='Plarrior:BAAANQADCgMIAwAAAA==.Plip:BAAANQAECgQICQAAAA==.',
Po='Pokerrface:BAAANQADCggICAAAAA==.Poobumhead:BAAANQADCgYIBgAAAA==.Powerheal:BAAANQADCggIBAAAAA==.',
Pr='Prftlybalncd:BAAANQAECgQICAABNQAECgUICAABAAAAAA==.Priapus:BAAANQABCgMIAwAAAA==.Probably:BAABNQAECoEiAAQDAAkJRxyJAgB2AgADAAgJPxyJAgB2AgAEAAEJ/xwGPABbAAACAAEJ5xMpRgBSAAAAAA==.',
Pu='Pudgeyp:BAAANQAECgMIAwAAAA==.Punj:BAAANQADCgUIBQAAAA==.Puntarr:BAAANQADCgUIBwAAAA==.Puppybonks:BAAANQAECgIIAgAAAA==.',
Pw='Pwrbottom:BAAANQAECgMIAgAAAA==.',
Qi='Qibla:BAAANQAECgIIAgAAAA==.',
Qu='Quarizma:BAAANQAECgcIEgAAAA==.',
Ra='Raxe:BAEANQADCgYIBgAAAA==.',
Re='Reaperoffire:BAAANQADCgcICwAAAA==.Repliod:BAAANQAECgEIAQAAAA==.Restho:BAAANQAECgUIBwAAAA==.Revarix:BAAANQAECgIIAgAAAA==.',
Rh='Rhaella:BAAANQAECgEIAQAAAA==.Rhuiser:BAAANQAECgQICAAAAA==.Rhuno:BAAANQABCgEIAQAAAA==.',
Ri='Ritéboys:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.Ritëboys:BAAANQAECgQIBgAAAA==.',
Ro='Rocketjuice:BAAANQAECgEIAgAAAA==.',
Ru='Rutee:BAAANQAECgMIAwAAAA==.',
Sa='Safk:BAAANQAECgQIBAAAAA==.Saleina:BAAANQADCgIIAwAAAA==.Sandiwang:BAAANQADCgIIAgAAAA==.Sartoc:BAAANQAECgEIAQABNQAECgUIBgABAAAAAA==.',
Sc='Scabbo:BAAANQADCgcICwAAAA==.Scalesoul:BAAANQAECgQIBAAAAQ==.',
Se='Seiferoth:BAAANQAECgcIDAAAAA==.Sergantcolen:BAAANQAECgEIAQAAAA==.Señornanna:BAAANQADCgQIBAAAAA==.',
Sh='Shaddai:BAAANQAECgEIAQAAAA==.Shadowofevil:BAAANQADCggIEAAAAA==.Shalavoo:BAAANQADCgYIBAAAAA==.Shamankiller:BAAANQAECgMIBQAAAA==.Shamazzle:BAAANQAECgEIAQAAAA==.Shamlen:BAAANQADCggIIAAAAA==.Shinieedruid:BAAANQAECgMIBAAAAA==.Shions:BAAANQADCgYIBgAAAA==.Shockostoob:BAAANQADCggIDQAAAA==.',
Si='Sinequanon:BAAANQAECgYIBwAAAA==.Sinfulbeast:BAAANQAECgQIBQAAAA==.Sippycup:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
Sk='Skulv:BAAANQAECgcIDAAAAA==.',
Sl='Slakzor:BAAANQADCgQIAwAAAA==.Slammed:BAAANQADCggICwAAAA==.Slopain:BAAANQADCggICgAAAA==.Slåppery:BAAANQAECgcICAAAAA==.',
Sm='Smashy:BAAANQADCgQIBAAAAA==.',
Sn='Snorlax:BAAANQAECgIIAgAAAA==.Snort:BAAANQADCgUIBQAAAA==.',
So='Sona:BAAANQADCgYIBgAAAA==.Soresu:BAAANQADCgIIAgAAAA==.Soundwit:BAAANQADCggIHQAAAA==.',
Sp='Sparrowstalk:BAAANQADCgEIAQAAAA==.Spindrift:BAAANQADCggIDQAAAA==.Spoonyy:BAAANQAECgcICwAAAA==.',
Sq='Squanchie:BAAANQAECgEIAQAAAA==.',
St='Steinlarger:BAAANQAECgMIAwAAAA==.Storrmbender:BAAANQAECgMIAwAAAA==.Stoutbrew:BAAANQADCggICQAAAA==.Strípe:BAAANQADCgQIBAAAAA==.Stuy:BAAANQAECgUICAAAAA==.Stãria:BAAANQADCggIBwAAAA==.Störme:BAAANQADCgQIBAAAAA==.',
Su='Sugarburst:BAAANQADCggICwAAAA==.',
Sw='Swak:BAAANQAECgQIBwAAAA==.Switchskin:BAAANQAECgYICAAAAA==.',
Ta='Tallinor:BAAANQADCgYIBgAAAA==.Taumast:BAAANQADCgMIAwABNQADCggICAABAAAAAA==.Tauter:BAAANQADCgMIBQAAAA==.Tazzee:BAAANQADCgYIDAAAAA==.',
Te='Temperature:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Th='Thalia:BAAANQAECgQIBQAAAA==.Thottydot:BAAANQAECgEIAQAAAA==.Thox:BAAANQADCgIIAgAAAA==.Thyranux:BAAANQADCgMIBAAAAA==.',
Ti='Tienchi:BAAANQAECgIIAgAAAA==.Tierk:BAAANQADCggICAABNQAECgYICQABAAAAAA==.Tim:BAAANQAECgQIBAAAAA==.',
Tl='Tlo:BAAANQADCgcIBwABNQAECggIDgABAAAAAA==.',
To='Tollmemaybe:BAAANQAECgEIAQAAAA==.Tormént:BAAANQAECgQIBAAAAA==.',
Tr='Transport:BAAANQAECgEIAQAAAA==.Traumatizer:BAAANQADCgEIAQAAAA==.Trenbolone:BAAANQADCgIIAgAAAA==.Tronix:BAAANQAECgMIAwAAAA==.',
Tu='Tubbquake:BAAANQAECgEIAQAAAA==.',
Tw='Twatasaurus:BAAANQADCgQIBwAAAA==.',
['Tî']='Tîmmeh:BAAANQAECgEIAQAAAA==.',
Ub='Ubica:BAAANQAECgQIBAAAAA==.',
Un='Unholykníght:BAAANQADCgEIAQAAAA==.Unvoid:BAAANQAECgIIBAAAAA==.',
Ur='Urzog:BAAANQADCgUIBQAAAA==.',
Us='Useacooldown:BAAANQADCgcIBwAAAA==.',
Va='Valithor:BAAANQADCgUIBQAAAA==.Valkyrion:BAAANQAECgcICgAAAA==.',
Ve='Velathri:BAAANQADCggIDQAAAA==.Velenlerolan:BAAANQAFFAEIAQAAAA==.Velrayne:BAAANQAECgEIAQAAAA==.Verailde:BAAANQADCgMIBAAAAA==.Verathriel:BAAANQABCgIIAgAAAA==.Verilence:BAAANQAECgMIAwAAAA==.Veventhius:BAAANQADCgIIAgAAAA==.Vext:BAAANQADCgMIAwAAAA==.',
Vo='Vorndryad:BAAANQADCgcIDgAAAA==.',
Vy='Vynburn:BAAANQAECgQIBAAAAA==.',
Wa='Warmon:BAAANQADCgYICQAAAA==.Watson:BAAANQADCggIDgAAAA==.Waveryy:BAAANQADCgMIBgAAAA==.',
We='Wemblitz:BAAANQADCgQIBgAAAA==.Wesh:BAAANQAECgUIBwAAAA==.',
Wh='Whio:BAAANQADCggIDQAAAA==.Whtclass:BAAANQADCgYIBgAAAA==.',
Wi='Wintersfence:BAAANQADCgYIBQAAAA==.',
Wk='Wkwk:BAAANQADCgIIAgAAAA==.',
Wp='Wpd:BAAANQAECgUIBgAAAA==.',
['Wî']='Wîngman:BAAANQADCggIFgAAAA==.',
Xe='Xenoruin:BAAANQAECgEIAQAAAA==.',
Yo='Yorkie:BAAANQAECgYICgAAAA==.Yoyogi:BAAANQADCgYIBwAAAA==.',
Yu='Yui:BAAANQADCggICAABNQAECgMIBAABAAAAAA==.Yurarzir:BAAANQAECgQIBAAAAA==.',
Za='Zanisha:BAAANQADCgYIBgAAAA==.Zaz:BAAANQADCgYIBgAAAA==.',
Ze='Zelendorm:BAAANQAECgIIAgAAAA==.',
['ßa']='ßaccycønes:BAAANQADCgYICwAAAA==.',
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
