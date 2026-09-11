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

local lookup = {'Unknown-Unknown','Mage-Arcane','Warlock-Demonology','Paladin-Retribution',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abc:BAAANQADCgIIAgAAAA==.',
Ae='Aeviee:BAAANQABCgUIBQAAAA==.',
Ag='Agrippa:BAAANQAECgQICAAAAA==.',
Ah='Ahndhrez:BAAANQADCgQIBAAAAA==.',
Ai='Aidric:BAAANQADCggIFAAAAA==.Airwavez:BAAANQAECgcIEAAAAA==.',
Ak='Akriel:BAAANQAECgUICwAAAA==.',
Al='Albrecht:BAAANQADCgEIAQAAAA==.Altra:BAAANQAECgUICgAAAA==.Alumit:BAAANQAECgMIBAAAAA==.',
Am='Amoeta:BAAANQAECgMIBAAAAA==.',
An='Angelique:BAAANQAECgEIAQAAAA==.Angry:BAAANQADCgQIBAAAAA==.Angryapples:BAAANQADCgMIAwAAAA==.Annihilation:BAAANQADCgQIBAAAAA==.',
Ap='Approved:BAAANQADCgYIBQAAAA==.',
Ar='Arconos:BAAANQADCgYIDAABNQAECgcIEQABAAAAAA==.',
As='Asomyrh:BAAANQAECgQIBAAAAA==.',
Au='Aurial:BAAANQADCgMIAwAAAA==.',
Ba='Babygirl:BAAANQAECgUIBgAAAA==.Bananer:BAAANQAECgQICAAAAA==.Banonzarath:BAAANQADCggICAAAAA==.Barrysoetoro:BAAANQADCgYIBgAAAA==.Baulie:BAAANQADCgMIBAAAAA==.',
Be='Bekroh:BAAANQAECgQIBAAAAA==.',
Bi='Bigdaddyd:BAAANQADCggIFQAAAA==.Bigdonk:BAAANQADCggICAAAAA==.Bigocagler:BAAANQADCggICAAAAA==.Bioodlion:BAAANQAECgQIBQAAAA==.Bipolar:BAAANQAECgEIAQAAAA==.Bippysmasher:BAAANQAECgQIBQAAAA==.Bishmanistic:BAAANQAECgIIAgAAAA==.',
Bl='Blacblood:BAAANQAECgEIAQAAAA==.Blindweiss:BAAANQADCgcIBwABNQAECgcIEQABAAAAAA==.Blinkies:BAAANQAECgcICwAAAA==.',
Bo='Bontao:BAAANQAECgcIEgAAAA==.Bontaopanda:BAAANQADCgcIEwABNQAECgcIEgABAAAAAA==.Boomies:BAAANQADCgQIBAABNQAECgcICwABAAAAAA==.Borstenne:BAAANQAECgUICgAAAA==.Bosco:BAAANQADCgQIBAAAAA==.',
Br='Bresepls:BAAANQADCgYICwABNQAECgUICgABAAAAAA==.Breseshh:BAAANQAECgUICgAAAA==.Brickbow:BAAANQADCgYIBgAAAA==.Brickette:BAAANQADCgcIEwABNQAECgcIEgABAAAAAA==.Bricklicker:BAAANQAECgMIAwAAAA==.Bricksquad:BAAANQAECgYICgAAAA==.Brickthrow:BAAANQAECgcIEgAAAA==.',
Bu='Burgerburn:BAAANQADCgYICgAAAA==.',
By='Bytheway:BAAANQAECgEIAQAAAA==.',
['Bé']='Béstt:BAAANQAECgQIBAAAAA==.',
Ca='Cadilak:BAAANQAECgUICgAAAA==.Caelesti:BAAANQADCgcIEgAAAA==.Camlin:BAAANQADCggIDgAAAA==.',
Ch='Cheapshotjoe:BAAANQADCgEIAQAAAA==.Chelbur:BAAANQAECgEIAQAAAA==.Chowderhead:BAAANQAECgcIDwAAAA==.',
Ci='Cileb:BAAANQAECgQIBAAAAA==.Civik:BAAANQADCgYIBgAAAA==.',
Co='Conchsniffer:BAAANQAECgYIDAAAAA==.Copperit:BAAANQAECgQIBQAAAA==.Cornburglar:BAAANQAECgQIBwAAAA==.Corrona:BAEANQADCggICAABNQAECgYICAABAAAAAA==.',
Cr='Crunchwrap:BAAANQADCggIDgAAAA==.',
['Câ']='Câlisse:BAAANQAECggIDwAAAA==.',
Da='Daddiedk:BAAANQAECgUICQAAAA==.Damncats:BAAANQAECgMICAAAAA==.Danielsboone:BAAANQADCgcIEgAAAA==.Darkmare:BAAANQAECgUICgAAAA==.Darknemesis:BAAANQADCgcIBwABNQADCggICAABAAAAAA==.',
De='Deadhippocow:BAAANQAECgMIAwAAAA==.Dearth:BAEANQAECgMIBAABNQAECgYICAABAAAAAA==.Deathbane:BAAANQADCgUICAAAAA==.Deathwavez:BAAANQADCgcIBwAAAA==.Demayy:BAAANQAECgMIAwAAAA==.Demona:BAAANQADCgQIBAAAAA==.Demonix:BAAANQAECgEIAQAAAA==.Derptron:BAAANQAECgIIAgAAAA==.',
Di='Dilutedqt:BAAANQAECgMIBQABNQAECgQIDAABAAAAAA==.Dilutedret:BAAANQADCgMIAwABNQAECgQIDAABAAAAAA==.Dinobrass:BAAANQAECgQIBgAAAA==.Dirge:BAAANQAECgMIAwAAAA==.Dirktheshiny:BAAANQAECgYIDAAAAA==.Dirtylöbster:BAABNQAECoEXAAICAAkJCBsdFAAgAwACAAkJCBsdFAAgAwAAAA==.Disabel:BAAANQADCggICAAAAA==.',
Dj='Djinsurgent:BAAANQAECgEIAQAAAA==.',
Do='Doobysnacks:BAAANQAECgQIBQAAAA==.Doolittle:BAAANQADCgYICwAAAA==.Dorfies:BAAANQADCgcICAABNQAECgcICwABAAAAAA==.',
Dr='Dralock:BAAANQADCgcIBwABNQADCgYIBgABAAAAAA==.Drewmee:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Droovani:BAAANQAECgQIBQAAAA==.Drunkenyeti:BAAANQADCgYICwAAAA==.',
Du='Duckbeak:BAAANQADCggIDQAAAA==.Duwork:BAAANQAECgQIBAAAAA==.',
['Dæ']='Dæmona:BAAANQAECgcIDQAAAA==.',
Eb='Ebk:BAAANQAECgYIBQAAAA==.Ebkx:BAAANQADCgUIBgAAAA==.',
El='Eladus:BAAANQAECgEIAgAAAA==.Elesus:BAAANQADCgIIAgABNQAECgYICgABAAAAAA==.',
Em='Emblaze:BAAANQADCgUIBQAAAA==.',
En='Enhshaman:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.',
Fa='Faithpasse:BAAANQAECgIIAgAAAA==.',
Fe='Felondar:BAAANQAECgEIAQAAAA==.Ferarro:BAAANQADCggICAAAAA==.',
Fi='Finnadin:BAAANQADCgcIDQAAAA==.Finns:BAAANQAECgEIAQAAAA==.Fistuu:BAAANQADCgUIBQAAAA==.',
Fl='Flysky:BAAANQAECgcIEgAAAA==.',
Fo='Foxsake:BAAANQADCgQIBAAAAA==.',
Fu='Futurefist:BAAANQADCggICAAAAA==.Fuzzydeeps:BAAANQADCggICQAAAA==.',
Ga='Garduuk:BAAANQAECgMIAwAAAA==.',
Ge='Gearth:BAAANQAECgYIDAAAAA==.',
Go='Gotlieb:BAAANQADCgUIBQAAAA==.',
Gr='Gravey:BAAANQAECgUICQAAAA==.Grogger:BAAANQABCgIIAgAAAA==.Grrahtahtah:BAAANQAFFAEIAQAAAA==.',
Ha='Hammerinfred:BAAANQAECgEIAQAAAA==.',
Hi='Hippayman:BAAANQAECgIIAgAAAA==.Hippysmasher:BAAANQADCggICAABNQAECgQIBQABAAAAAA==.',
Ho='Holyhooters:BAAANQAECgIIAgAAAA==.Holypablo:BAAANQADCgYICgABNQAECgQIBgABAAAAAA==.Honour:BAAANQAECgMIAwAAAA==.',
Hr='Hrathdemon:BAAANQAECgUICgAAAA==.Hrathion:BAAANQADCgYIDAABNQAECgUICgABAAAAAA==.',
Hu='Hupa:BAAANQAECgYIDQAAAA==.Hurtsdonut:BAAANQAECgQIBAABNQAECgYICgABAAAAAA==.Huulis:BAAANQADCggICAAAAA==.',
Ic='Ickeetard:BAAANQADCgcIBwAAAA==.',
Id='Idiotbreath:BAAANQAECgUICQAAAA==.',
Ie='Ieatcheeks:BAAANQAECgQIBAAAAA==.Ieyasu:BAAANQAECgYICgAAAA==.',
Ig='Ignitus:BAAANQAECgEIAgAAAA==.',
In='Insulinshot:BAAANQADCggIEgAAAA==.',
It='Itsmagharszn:BAAANQADCgEIAQAAAA==.',
Ja='Jabronipie:BAAANQADCggIBQAAAA==.',
Jh='Jhana:BAAANQADCgQIBQAAAA==.',
Jj='Jjooaacchhim:BAAANQAECgQIBAAAAA==.',
Jo='Josh:BAAANQADCgYIEQAAAA==.',
Ju='Junglefever:BAAANQADCgYIBgAAAA==.',
Jy='Jyve:BAAANQAECgUIBwAAAA==.',
Ka='Kailin:BAAANQADCgUIBQAAAA==.Kamanactali:BAAANQADCgYIEQAAAA==.Kaneko:BAAANQADCgcIBwABNQAECgYICgABAAAAAA==.Katalina:BAAANQAECgUIDAAAAA==.',
Ke='Kelstormhoof:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.',
Kh='Kham:BAAANQAECgUIBwAAAA==.',
Ki='Kirren:BAAANQADCgIIAgAAAA==.',
Ko='Kokeovrdose:BAAANQABCgQIBAABNQADCgQIBAABAAAAAA==.',
La='Lavashiza:BAAANQAECgIIAwAAAA==.',
Le='Leadzorz:BAAANQADCgYIDwAAAA==.Leedaddydk:BAAANQABCgIIAgAAAA==.Legday:BAAANQADCgYIBgAAAA==.',
Li='Liltotem:BAAANQAECgQICQAAAA==.Linaria:BAAANQADCgUIBQAAAA==.Lizzymonk:BAAANQAECgUICgAAAA==.',
Lo='Lockdownlol:BAAANQAECgQIDAAAAA==.',
Lu='Luluh:BAAANQAECgMIBQAAAA==.',
Ma='Maddog:BAAANQAECgQIBQAAAA==.Maebell:BAAANQADCgYIDgABNQAECgQIDAABAAAAAA==.Mageslayer:BAAANQAECgEIAQAAAA==.Magrun:BAAANQADCgUICQAAAA==.Matt:BAAANQAECgUICgAAAA==.Mavrik:BAAANQAECgMIAwAAAA==.',
Me='Meatmagic:BAAANQADCgIIAgAAAA==.Megapunk:BAAANQADCgYIBwAAAA==.Melanyie:BAAANQADCgMIAwAAAA==.Melfìce:BAAANQADCgYIBgAAAA==.Meudayr:BAAANQAECgQIBAAAAA==.',
Mi='Millarolly:BAAANQADCgYIBgAAAA==.Mischifdots:BAAANQADCgUIBQAAAA==.Mischifgg:BAAANQAECgIIAgAAAA==.Mittenss:BAAANQADCggICQAAAA==.',
Mo='Mojorisinn:BAAANQAECgQIBAAAAA==.Moobear:BAAANQAECgQIBQAAAA==.Moogie:BAABNQAECoEYAAICAAkJdBbULQCMAgACAAkJdBbULQCMAgAAAA==.Moozlock:BAAANQAECgEIAQAAAA==.Morgiana:BAAANQAECgUICQAAAA==.Moscovio:BAABNQAECoEXAAIDAAkJ2ByQBQAQAwADAAkJ2ByQBQAQAwAAAA==.Mosspaws:BAAANQAECgQIBwAAAA==.',
Mt='Mtndewyou:BAAANQAECgMIAwAAAA==.',
Na='Napok:BAAANQADCgEIAQAAAA==.',
Ni='Nihr:BAAANQADCggIDQAAAA==.Ninkarrak:BAAANQADCgYIEQAAAA==.',
Nm='Nme:BAAANQAECgQIBgAAAA==.',
No='Nocturnos:BAAANQAECgEIAQAAAA==.Novamancer:BAAANQAECgEIAQAAAA==.',
Nu='Nuph:BAAANQABCgYIBgAAAA==.',
Ny='Nymage:BAAANQAECgIIAgAAAA==.',
Og='Ogdaddy:BAAANQADCggICAAAAA==.',
Ok='Okaerisan:BAAANQADCgMIAwAAAA==.',
Ol='Olord:BAAANQADCgEIAQAAAA==.',
Or='Orack:BAAANQAECgEIAQAAAA==.',
Ou='Outlast:BAAANQADCgYIBgAAAA==.',
Ow='Owch:BAAANQABCgIIAgABNQAECgQIBAABAAAAAA==.',
Pa='Panblind:BAAANQAECgcIEgAAAA==.Parmageddon:BAAANQAECgUICgAAAA==.Parmrageiano:BAAANQADCgUIBQABNQAECgUICgABAAAAAA==.',
Pe='Peanought:BAAANQAECgMIAwAAAA==.Peetfix:BAAANQAECgUICQAAAA==.Pepsipink:BAAANQADCgYIBgAAAA==.',
Ph='Phèdre:BAEANQAECgEIAQABNQAECgkJGAAEAKMgAA==.',
Pi='Picklegrip:BAAANQAECgQIBAAAAA==.Pijak:BAAANQADCgYIEQAAAA==.',
Pl='Planetina:BAAANQADCgcIBwAAAA==.',
Po='Poah:BAAANQAFFAIIAgAAAA==.',
Pr='Pruflas:BAAANQAECgEIAgAAAA==.',
Ps='Psycodk:BAAANQAECgIIAgAAAA==.',
Pu='Pumpin:BAAANQAECgEIAQAAAA==.Punkthor:BAAANQAECgEIAQAAAA==.Purgemepappy:BAAANQADCgYIBgAAAA==.',
['Pø']='Pø:BAAANQAECgIIAgAAAA==.',
Qk='Qkn:BAAANQADCgYIDwAAAA==.',
Ra='Raf:BAAANQADCgUIBQAAAA==.Ratoncita:BAAANQADCgUIBQAAAA==.Rayzee:BAAANQADCgQIBAAAAA==.',
Re='Reisar:BAAANQADCgEIAQAAAA==.Rennera:BAAANQADCgUICQAAAA==.Revalation:BAAANQAECgQIBAAAAA==.',
Ri='Riachu:BAAANQAECgQIBAAAAA==.Ribeyejoe:BAAANQAECgEIAQAAAA==.',
Ro='Roboorc:BAAANQABCgEIAQAAAA==.Roken:BAAANQADCggICAAAAA==.Rorymcilroy:BAAANQAECgEIAQAAAA==.',
Sa='Sagan:BAEANQADCgQIBAABNQAECgIIAgABAAAAAA==.Sandasa:BAAANQAECgMIBAAAAA==.Sanivanth:BAAANQADCgQIBAAAAA==.Saucerdote:BAAANQAECgQIBgAAAA==.Saxon:BAAANQAECgEIAQAAAA==.',
Se='Selinfinite:BAAANQAECgUIBwAAAA==.Selkie:BAAANQADCggIFAAAAA==.Serenitynow:BAAANQAECgQIBAAAAA==.',
Sg='Sgge:BAAANQADCgYIBgAAAA==.',
Sh='Shadowmaven:BAAANQADCgcICgAAAA==.Shakakhan:BAAANQAECgQIBwABNQAECgQIDAABAAAAAA==.Shammer:BAEANQADCgYIBgABNQAECgcIEgABAAAAAA==.Shamshielder:BAEANQAECgcIEgAAAA==.Sharick:BAAANQADCgYICQAAAA==.Shawdrake:BAAANQADCgcIBwABNQAECgQIBwABAAAAAA==.Shawlee:BAAANQAECgQIBwAAAA==.Shellcow:BAAANQADCgYICQABNQAECgcICwABAAAAAA==.Shellwit:BAAANQADCgcICwABNQAECgcICwABAAAAAA==.Shetmage:BAAANQAECgMIAwABNQAECgcIEgABAAAAAA==.Shettrah:BAAANQAECgcIEgAAAA==.Shottdown:BAAANQADCgEIAQAAAA==.Shwoobs:BAAANQADCgQICAAAAA==.',
Si='Sijious:BAAANQADCggIEwAAAA==.Singularity:BAAANQADCgYIBgABNQAECgQIDAABAAAAAA==.',
Sk='Skyland:BAAANQADCgcIBwABNQAECgcIEgABAAAAAA==.',
So='Somi:BAAANQAECgUICgAAAA==.',
St='Stabbystab:BAAANQAECgQIBQABNQADCgEIAQABAAAAAA==.Stankydk:BAAANQAECgcIEgAAAA==.Stankyleg:BAAANQADCggIEAAAAA==.Stewie:BAAANQAECgQIBQAAAA==.Stinkbombs:BAAANQADCgIIAgAAAA==.',
Su='Subrogue:BAAANQAECgQICQABNQAFFAEIAQABAAAAAA==.Sunlest:BAAANQADCgYIBgAAAA==.',
Sy='Sylphrena:BAAANQAECgUICgAAAA==.',
Ta='Tacow:BAAANQAECgIIAgAAAA==.Talethen:BAAANQAECgEIAQAAAA==.',
Te='Telaragehoof:BAAANQADCggICAAAAA==.',
Th='Thedrood:BAAANQAECgUIBQAAAA==.',
To='Tohk:BAAANQAECgcIEgAAAA==.Tollee:BAAANQAECgQIBAAAAA==.Tontiamat:BAAANQAECgMIAwAAAA==.Tontier:BAAANQADCgcIDgABNQAECgMIAwABAAAAAA==.Tormero:BAAANQADCgcIBwAAAA==.Totembeans:BAAANQABCgYIBgAAAA==.Touchyfred:BAAANQADCgYICAAAAA==.Toxicfury:BAAANQABCgUIBAAAAA==.',
Tr='Traash:BAAANQABCgIIAgAAAA==.Treily:BAAANQAECgMICAAAAA==.Tricket:BAAANQAECgQIBAAAAA==.Trolloladin:BAAANQADCgYIBwAAAA==.Truestorm:BAAANQAECgMIAwAAAA==.',
Tu='Tuchi:BAAANQAECgcIDwAAAA==.',
['Tà']='Tàcobelle:BAAANQADCgYIEAAAAA==.',
Va='Vanicton:BAAANQAECgUICgAAAA==.',
Ve='Ve:BAAANQAECgQIBAAAAA==.Vegh:BAAANQAECgUICQAAAA==.Veldcat:BAAANQADCggIEwAAAA==.Veriale:BAAANQADCgYICwAAAA==.Verra:BAAANQAECgEIAQAAAA==.',
Vi='Vitriol:BAAANQAECgEIAQAAAA==.',
Wa='Wampa:BAAANQAECgEIAQAAAA==.Wanderblue:BAAANQADCgYIBgAAAA==.Wangstah:BAAANQADCggIFAAAAA==.Wartogoteam:BAAANQAECgcIDAAAAA==.',
We='Weiss:BAAANQAECgcIEQAAAA==.',
Wf='Wf:BAAANQAECgUIDQAAAA==.',
Wo='Woog:BAAANQADCgYIBgAAAA==.',
Wy='Wyldspirit:BAAANQADCgcIEgAAAA==.Wyreless:BAAANQAECgMIAwABNQAECgMIBAABAAAAAA==.',
Ya='Yaass:BAAANQADCggICAABNQAECgUIDQABAAAAAA==.Yagrum:BAAANQADCgYIDAAAAA==.Yahikko:BAAANQAECgYIBgAAAA==.',
Yo='Yoddaa:BAAANQADCgUICAABNQAECgEIAQABAAAAAA==.',
Ze='Zergen:BAAANQADCgYIBgAAAA==.',
Zh='Zhenya:BAAANQAECgUICgAAAA==.',
['Ôb']='Ôbelix:BAAANQADCggICAAAAA==.',
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
