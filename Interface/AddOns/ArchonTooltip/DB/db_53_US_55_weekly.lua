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

local lookup = {'Hunter-Marksmanship','Mage-Arcane','Hunter-BeastMastery','Unknown-Unknown','Paladin-Holy','Warlock-Destruction','Paladin-Retribution','Monk-Windwalker','DemonHunter-Havoc','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','DemonHunter-Devourer','DeathKnight-Blood','DeathKnight-Frost','Druid-Balance',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abc:BAAANQADCgIIAgAAAA==.',
Ae='Aeviee:BAAANQADCgQIBAAAAA==.',
Ag='Agrippa:BAAANQAECgQICAAAAA==.',
Ah='Ahndhrez:BAAANQADCgQIBAAAAA==.',
Ai='Aidric:BAAANQAECgMIAwAAAA==.Airwavez:BAABNQAECoEcAAIBAAkJqBhwEQBvAgABAAkJqBhwEQBvAgAAAA==.',
Ak='Akriel:BAAANQAECgUICwAAAA==.',
Al='Albrecht:BAAANQADCgEIAQAAAA==.Altra:BAAANQAECgYIEAAAAA==.Alumit:BAAANQAECgUICQAAAA==.',
Am='Amoeta:BAAANQAECgUICQAAAA==.',
An='Angelique:BAAANQAECgQIBQAAAA==.Angry:BAAANQADCgYICgAAAA==.Angryapples:BAAANQAECgQIBQAAAA==.Annihilation:BAAANQADCgUIBQAAAA==.',
Ap='Approved:BAAANQADCgYIBQAAAA==.',
Ar='Arconos:BAAANQADCgYIDAABNQAECgkJHAACANUfAA==.',
As='Asomyrh:BAAANQAECgUICQAAAA==.',
Au='Aurial:BAAANQADCgMIAwAAAA==.',
Ba='Babygirl:BAAANQAECgYIBwAAAA==.Bananer:BAAANQAECgQICAAAAA==.Banonzarath:BAAANQADCggICAAAAA==.Barrysoetoro:BAAANQADCgcIDAAAAA==.Baulie:BAAANQAECgQIBAAAAA==.',
Be='Beefstick:BAAANQADCgYIBgAAAA==.Bekroh:BAAANQAECgYICgAAAA==.',
Bi='Bigdaddyd:BAAANQAECgIIAgAAAA==.Bigdonk:BAAANQADCggICAAAAA==.Bigocagler:BAAANQADCggIEAAAAA==.Bioodlion:BAAANQAECgUIBgAAAA==.Bipolar:BAAANQAECgIIAwAAAA==.Bippysmasher:BAAANQAECgUICQAAAA==.Bishmanistic:BAAANQAECgQIBgAAAA==.',
Bl='Blacblood:BAAANQAECgEIAQAAAA==.Blindweiss:BAAANQADCgcIBwABNQAECgkJHAACANUfAA==.Blinkies:BAAANQAECggIEAAAAA==.',
Bo='Bontao:BAABNQAECoEcAAIDAAkJyhmpFQDLAgADAAkJyhmpFQDLAgAAAA==.Bontaopanda:BAAANQADCgcIEwABNQAECgkJHAADAMoZAA==.Boomies:BAAANQADCgQIBAABNQAECggIEAAEAAAAAA==.Borstenne:BAAANQAECgYIEAAAAA==.Bosco:BAAANQADCgQIBAAAAA==.',
Br='Bresepls:BAAANQAECgEIAQABNQAECgYIEAAEAAAAAA==.Breseshh:BAAANQAECgYIEAAAAA==.Brickbeard:BAAANQAECgMIAwAAAA==.Brickbow:BAAANQADCgYIBgAAAA==.Brickette:BAAANQADCgcIEwABNQAECgkJHAAFADEZAA==.Bricklicker:BAAANQAECgMIAwAAAA==.Bricksquad:BAAANQAECgcIDAAAAA==.Brickthrow:BAABNQAECoEcAAIFAAkJMRldEgDPAgAFAAkJMRldEgDPAgAAAA==.',
Bu='Burgerburn:BAAANQADCgcIEwAAAA==.',
By='Bytheway:BAAANQAECgIIAgAAAA==.',
['Bé']='Béstt:BAAANQAECgYICgAAAA==.',
Ca='Cadilak:BAAANQAECgYIEAAAAA==.Caelesti:BAAANQADCggIGgAAAA==.Camlin:BAAANQADCggIDgAAAA==.Catrina:BAEANQADCggICAABNQAECggICAAEAAAAAA==.',
Ch='Cheapshotjoe:BAAANQADCgEIAQAAAA==.Chelbur:BAAANQAECgEIAQAAAA==.Chowderhead:BAABNQAECoEZAAIGAAkJUxayBQCVAgAGAAkJUxayBQCVAgAAAA==.',
Ci='Cileb:BAAANQAECgUICQAAAA==.Civik:BAAANQADCgYIBgAAAA==.',
Co='Cocio:BAAANQAECgIIBAABNQAECgUICwAEAAAAAA==.Conchsniffer:BAABNQAECoEVAAIHAAgJZxjMRADkAQAHAAgJZxjMRADkAQAAAA==.Copperit:BAAANQAECgQICAAAAA==.Cornburglar:BAAANQAECgUICwAAAA==.Corrona:BAEANQADCggICAABNQAECggICAAEAAAAAA==.',
Cr='Crunchwrap:BAAANQAECgIIAgAAAA==.',
['Câ']='Câlisse:BAABNQAECoEbAAIIAAkJNx+/BAA8AwAIAAkJNx+/BAA8AwAAAA==.',
Da='Daddiedk:BAAANQAECgYIDwAAAA==.Damncats:BAAANQAECgQIEAAAAA==.Danielsboone:BAAANQADCggIGgAAAA==.Darkmare:BAAANQAECgUIDQAAAA==.Darknemesis:BAAANQADCgcIDAABNQADCggICAAEAAAAAA==.',
De='Deadhippocow:BAAANQAECgQIBwAAAA==.Dearth:BAEANQAECgcIBAABNQAECggICAAEAAAAAA==.Deathbane:BAAANQADCgUICAAAAA==.Deathwavez:BAAANQAECggIBwAAAA==.Demayy:BAAANQAECgQIBwAAAA==.Demona:BAAANQAECgMIBAAAAA==.Demonix:BAAANQAECgMIBAAAAA==.Derptron:BAAANQAECgUIBwAAAA==.',
Di='Dilutedqt:BAAANQAECgUICgAAAA==.Dilutedret:BAAANQADCgMIAwABNQAECgUICgAEAAAAAA==.Dinobrass:BAAANQAECgYIDAAAAA==.Dirge:BAAANQAECgQIBwAAAA==.Dirktheshiny:BAAANQAECgcIEwAAAA==.Dirtylöbster:BAABNQAECoEfAAICAAkJXBxcIAATAwACAAkJXBxcIAATAwAAAA==.Disabel:BAAANQADCggICAAAAA==.Distracto:BAAANQAECggICAAAAA==.',
Dj='Djinsurgent:BAAANQAECgIIAwAAAA==.',
Do='Doobysnacks:BAAANQAECgUICQAAAA==.Doolittle:BAAANQADCgYICwAAAA==.Dorfies:BAAANQADCgcICAABNQAECggIEAAEAAAAAA==.Dorns:BAAANQADCgEIAQAAAA==.',
Dr='Dralock:BAAANQAECgQIBAABNQADCgYIBgAEAAAAAA==.Dreamyeti:BAAANQADCgEIAQAAAA==.Drewmee:BAAANQADCgYIBgABNQAECgUICgAEAAAAAA==.Droovani:BAAANQAECgUICgAAAA==.Drunkenyeti:BAAANQADCgcIEAAAAA==.',
Du='Duckbeak:BAAANQADCggIFAAAAA==.Duwork:BAAANQAECgQICAAAAA==.',
['Dæ']='Dæmona:BAABNQAECoEXAAIJAAgJbhMqFwAmAgAJAAgJbhMqFwAmAgAAAA==.',
Eb='Ebk:BAAANQAECgcICQAAAA==.Ebkx:BAAANQAECgEIAQAAAA==.',
El='Eladus:BAAANQAECgQICgAAAA==.Elesus:BAAANQADCgIIAgABNQAECgcIEQAEAAAAAA==.',
Em='Emblaze:BAAANQADCgUIBQAAAA==.Emrys:BAAANQADCgMIAwAAAA==.',
En='Enhshaman:BAAANQAECgIIAwABNQAFFAUIBgABADsSAA==.',
Fa='Faithpasse:BAAANQAECgQIBgAAAA==.',
Fe='Felondar:BAAANQAECgUIBgAAAA==.Ferarro:BAAANQAECgUIBQAAAA==.',
Fi='Finnadin:BAAANQADCgcIDQAAAA==.Finns:BAAANQAECgIIAwAAAA==.Firulais:BAAANQAECgMIAwAAAA==.Fistuu:BAAANQADCgUIBQAAAA==.',
Fl='Flysky:BAABNQAECoEcAAQKAAkJAyLAAgBcAwAKAAkJAyLAAgBcAwALAAQJLR8wBwBqAQAMAAUJFhf8FQBWAQAAAA==.',
Fo='Foxsake:BAAANQADCgQIBAAAAA==.',
Fu='Futurefist:BAAANQADCggICAAAAA==.',
Ga='Garduuk:BAAANQAECgQIBwAAAA==.',
Ge='Gearth:BAAANQAECgcIEgAAAA==.',
Gl='Glucose:BAAANQADCgQIBQAAAA==.',
Go='Gotlieb:BAAANQADCggIEQAAAA==.',
Gr='Gravey:BAAANQAECgYIDwAAAA==.Grogger:BAAANQADCgEIAQAAAA==.Grrahtahtah:BAACNQAFFIEGAAIBAAUJOxJxAwCQAQABAAUJOxJxAwCQAQA1AAQKgR0AAwEACQmpINMEAFMDAAEACQmFINMEAFMDAAMAAQk7E7q7AFEAAAAA.',
Gy='Gymble:BAAANQADCgIIAgAAAA==.',
Ha='Hammerinfred:BAAANQAECgEIAQAAAA==.',
Hi='Hippayman:BAAANQAECgIIAgAAAA==.Hippysmasher:BAAANQADCggICAABNQAECgUICQAEAAAAAA==.',
Ho='Holyhooters:BAAANQAECgQIBgAAAA==.Holypablo:BAAANQADCgYICgABNQAECgUICgAEAAAAAA==.Honour:BAAANQAECgQIBwAAAA==.',
Hr='Hrathdemon:BAAANQAECgYIEAAAAA==.Hrathion:BAAANQADCgYIDAABNQAECgYIEAAEAAAAAA==.',
Hu='Hupa:BAABNQAECoEUAAIHAAcJjCJXHwCrAgAHAAcJjCJXHwCrAgAAAA==.Hurtsdonut:BAAANQAECgQICAABNQAECgcIEQAEAAAAAA==.Huulis:BAAANQADCggICAAAAA==.',
Ia='Iamheyo:BAAANQADCgQIBAAAAA==.',
Ic='Ickeetard:BAAANQADCgcIBwAAAA==.',
Id='Idiotbreath:BAAANQAECgYIDwAAAA==.',
Ie='Ieatcheeks:BAAANQAECgUICQAAAA==.Ieyasu:BAAANQAECgcIEQAAAA==.',
Ig='Ignitus:BAAANQAECgQIBQAAAA==.',
Il='Illpownyou:BAAANQADCgcIBwABNQAECgIIBAAEAAAAAA==.',
In='Insulinshot:BAAANQAECgIIAwAAAA==.',
Ir='Ironguard:BAAANQABCgMIAwAAAA==.',
It='Itsmagharszn:BAAANQADCgEIAQAAAA==.',
Ja='Jabronipie:BAAANQADCggIBQAAAA==.',
Jh='Jhana:BAAANQADCgUICQAAAA==.',
Jj='Jjooaacchhim:BAAANQAECgQIBAAAAA==.',
Jo='Josh:BAAANQADCgYIEQAAAA==.',
Ju='Junglefever:BAAANQADCgYIBgAAAA==.',
Jy='Jyve:BAAANQAECgYIDQAAAA==.',
Ka='Kailin:BAAANQADCgUIBQAAAA==.Kamanactali:BAAANQADCgYIEQAAAA==.Kaneko:BAAANQADCgcIBwABNQAECgcIEQAEAAAAAA==.Katalina:BAAANQAECgUIEAAAAA==.',
Ke='Kelstormhoof:BAAANQADCgcIEQABNQADCggICAAEAAAAAA==.',
Kh='Kham:BAAANQAECgcIDgAAAA==.',
Ki='Kirren:BAAANQADCgIIAgAAAA==.',
Kl='Klais:BAAANQADCgIIAgAAAA==.',
Ko='Kokeovrdose:BAAANQABCgQIBAABNQADCgYICgAEAAAAAA==.',
La='Lavashiza:BAAANQAECgQIBwAAAA==.',
Le='Leadzorz:BAAANQADCgYIDwAAAA==.Leedaddydk:BAAANQABCgIIAgAAAA==.Legday:BAAANQAECgMIAwAAAA==.',
Li='Liltotem:BAAANQAECgYIDgAAAA==.Linaria:BAAANQADCgUIBQAAAA==.Lizzymonk:BAAANQAECgYIEAAAAA==.',
Lo='Lockdownlol:BAAANQAECgQIEAABNQAECgUICgAEAAAAAA==.',
Lu='Luluh:BAAANQAECgQICAAAAA==.',
Ma='Maddog:BAAANQAECgQICQAAAA==.Maebell:BAAANQAECgMIAwABNQAECgUICgAEAAAAAA==.Mageslayer:BAAANQAECgMIBAAAAA==.Magrun:BAAANQADCgUICQAAAA==.Maiggee:BAAANQADCgYIBgAAAA==.Matt:BAAANQAECgYIEAAAAA==.Mavrik:BAAANQAECgQIBwAAAA==.',
Me='Meatmagic:BAAANQADCgIIAgAAAA==.Megapunk:BAAANQADCgcIDgAAAA==.Melanyie:BAAANQADCgMIAwAAAA==.Melfìce:BAAANQADCgYIBgAAAA==.Meudayr:BAAANQAECgUICQAAAA==.',
Mi='Millarolly:BAAANQADCgYICAAAAA==.Mischifdots:BAAANQADCgUICQAAAA==.Mischifgg:BAAANQAECgQIBgAAAA==.Mittenss:BAAANQADCggICQAAAA==.',
Mn='Mndgblnfred:BAAANQADCgEIAQAAAA==.',
Mo='Mojorisinn:BAAANQAECgQIBAAAAA==.Moobear:BAAANQAECgYICQAAAA==.Moogie:BAABNQAECoEgAAICAAkJlRlbPQCcAgACAAkJlRlbPQCcAgAAAA==.Moozlock:BAAANQAECgEIAQAAAA==.Morgiana:BAAANQAECgYIDwAAAA==.Moscovio:BAACNQAFFIEGAAINAAMJbRZqBgAHAQANAAMJbRZqBgAHAQA1AAQKgSAAAg0ACQl3H0kLAAsDAA0ACQl3H0kLAAsDAAAA.Mosspaws:BAAANQAECgUICAAAAA==.',
Mt='Mtndewyou:BAAANQAECgMIBAAAAA==.',
Na='Napok:BAAANQAECgIIAgAAAA==.',
Ni='Nihr:BAAANQAECgMIAwAAAA==.Ninkarrak:BAAANQADCgYIEQAAAA==.',
Nm='Nme:BAAANQAECgQICQAAAA==.',
No='Nocturnos:BAAANQAECgEIAQAAAA==.Novamancer:BAAANQAECgEIAQAAAA==.',
Nu='Nuph:BAAANQAECgQIBQAAAA==.',
Ny='Nymage:BAAANQAECgMIBAAAAA==.',
Og='Ogdaddy:BAAANQADCggICAAAAA==.',
Ok='Okaerisan:BAAANQADCgMIAwAAAA==.',
Ol='Olord:BAAANQADCgEIAQAAAA==.',
Or='Orack:BAAANQAECgMIBAAAAA==.',
Ou='Outlast:BAAANQADCgYIBgAAAA==.',
Ow='Owch:BAAANQABCgIIAgABNQAECgUICQAEAAAAAA==.',
Pa='Panblind:BAABNQAECoEcAAIOAAkJWx1NCQALAwAOAAkJWx1NCQALAwAAAA==.Parmageddon:BAAANQAECgYIEAAAAA==.Parmrageiano:BAAANQADCgUIBQABNQAECgYIEAAEAAAAAA==.',
Pe='Peanought:BAAANQAECgQIBwAAAA==.Peetfix:BAAANQAECgYIDwAAAA==.Pepsipink:BAAANQADCgYIBgAAAA==.',
Ph='Phèdre:BAEANQAECgIIAgABNQAECgkJGgAHAK0fAA==.',
Pi='Picklegrip:BAAANQAECgUICQAAAA==.Pijak:BAAANQADCgYIEQAAAA==.',
Pl='Planetina:BAAANQADCgcIBwAAAA==.',
Po='Poah:BAAANQAFFAIIAgAAAA==.',
Pr='Prettynhealz:BAAANQADCgIIAgAAAA==.Pruflas:BAAANQAECgEIAgAAAA==.',
Ps='Psycodk:BAAANQAECgIIAgAAAA==.',
Pu='Pumpin:BAAANQAECgEIAQAAAA==.Punkthor:BAAANQAECgIIAwAAAA==.Purgemepappy:BAAANQADCgYIDAAAAA==.Putitinme:BAAANQABCgIIAgAAAA==.',
['Pø']='Pø:BAAANQAECgQIBgAAAA==.',
Qk='Qkn:BAAANQADCgcIFgAAAA==.',
Ra='Raf:BAAANQAECgUIBQAAAA==.Ratoncita:BAAANQADCgUIBQAAAA==.Rayzee:BAAANQAECgEIAQAAAA==.',
Re='Reisar:BAAANQADCgEIAQAAAA==.Rennera:BAAANQADCgUIDAAAAA==.Revalation:BAAANQAECgQICAAAAA==.',
Ri='Riachu:BAAANQAECgUICQAAAA==.Ribeyejoe:BAAANQAECgEIAwAAAA==.',
Ro='Roadblock:BAAANQAECgQIBAAAAA==.Roboorc:BAAANQABCgEIAQAAAA==.Roken:BAAANQADCggICAAAAA==.Rorymcilroy:BAAANQAECgYIBwAAAA==.',
Sa='Sagan:BAEANQADCgQIBAABNQAECgQIBQAEAAAAAA==.Sandasa:BAAANQAECgMIBAAAAA==.Sanivanth:BAAANQADCgQIBAAAAA==.Saucerdote:BAAANQAECgUIBwAAAA==.Saxon:BAAANQAECgEIAQAAAA==.',
Se='Selenix:BAAANQADCgYIBgAAAA==.Selinfinite:BAAANQAECggIDwAAAA==.Selkie:BAAANQADCggIFAAAAA==.Serenitynow:BAAANQAECgQIBAAAAA==.',
Sg='Sgge:BAAANQADCgYIBgAAAA==.',
Sh='Shadowmaven:BAAANQADCgcICgAAAA==.Shakakhan:BAAANQAECgQICwABNQAECgUICgAEAAAAAA==.Shammer:BAEANQADCggIBgABNQAECgkJGwAPANAaAA==.Shamshielder:BAEBNQAECoEbAAMPAAkJ0BrSEgChAgAPAAkJ0BrSEgChAgAQAAMJ4AeGRABlAAAAAA==.Sharick:BAAANQADCgYICQAAAA==.Shawdrake:BAAANQADCgcIBwABNQAECgUIDAAEAAAAAA==.Shawlee:BAAANQAECgUIDAAAAA==.Shetmage:BAAANQAECgMIBQABNQAECgkJHQARAJMYAA==.Shettrah:BAABNQAECoEdAAIRAAkJkxiuEgDKAgARAAkJkxiuEgDKAgAAAA==.Shottdown:BAAANQADCgUIBQAAAA==.Shwoobs:BAAANQAECgEIAQAAAA==.',
Si='Sigasunanvil:BAAANQAECgQIBAAAAA==.Sijious:BAAANQADCggIHwAAAA==.Singularity:BAAANQAECgMIAwABNQAECgUICgAEAAAAAA==.',
Sk='Skanktank:BAAANQAECgUIBQAAAA==.Skyland:BAAANQADCgcIBwABNQAECgkJHAAKAAMiAA==.',
Sl='Slinkies:BAAANQADCgYICQAAAA==.Slipknife:BAAANQAECgUIBQAAAA==.',
So='Somi:BAAANQAECgUICgAAAA==.',
St='Stabbystab:BAAANQAECgYICwABNQADCgEIAQAEAAAAAA==.Stankydk:BAAANQAECgcIEgAAAA==.Stankyleg:BAAANQAFFAIIAgAAAA==.Stewie:BAAANQAECgUICAAAAA==.Stinkbombs:BAAANQADCgIIAgAAAA==.Stinkies:BAAANQAECgEIAQABNQAECggIEAAEAAAAAA==.',
Su='Subrogue:BAAANQAECgQICQABNQAFFAUIBgABADsSAA==.Sunlest:BAAANQADCgYICgAAAA==.',
Sy='Sylphrena:BAAANQAECgYIEAAAAA==.',
Ta='Tacow:BAAANQAECgUIBwAAAA==.Talethen:BAAANQAECgIIBAAAAA==.',
Te='Telaragehoof:BAAANQADCggICAAAAA==.',
Th='Thedrood:BAAANQAECgYICwAAAA==.',
To='Tohk:BAABNQAECoEdAAIJAAkJKiG3BQBLAwAJAAkJKiG3BQBLAwAAAA==.Tollee:BAAANQAECgQIBAAAAA==.Tontiamat:BAAANQAECgQIBwAAAA==.Tontier:BAAANQADCggIFgABNQAECgQIBwAEAAAAAA==.Tormero:BAAANQADCgcIBwAAAA==.Totembeans:BAAANQAECgQIBQAAAA==.Touchyfred:BAAANQADCgYICAAAAA==.Toxicfury:BAAANQABCgUIBAAAAA==.',
Tr='Traash:BAAANQABCgIIAgAAAA==.Treily:BAAANQAECgMICAAAAA==.Tricket:BAAANQAECgQICAAAAA==.Trolloladin:BAAANQADCggIDAAAAA==.Truestorm:BAAANQAECgQIAwAAAA==.',
Tu='Tuchi:BAABNQAECoEZAAICAAgJkBqSSwBqAgACAAgJkBqSSwBqAgAAAA==.',
['Tà']='Tàcobelle:BAAANQADCgYIEAAAAA==.',
Va='Vanicton:BAAANQAECgYIEAAAAA==.',
Ve='Ve:BAAANQAECgUICQAAAA==.Vegh:BAAANQAECgYIDwAAAA==.Velaei:BAAANQADCgYIBgAAAA==.Veldcat:BAAANQAECgEIAQAAAA==.Velddk:BAAANQADCggICAAAAA==.Veriale:BAAANQADCgYICwAAAA==.Verra:BAAANQAECgIIAwAAAA==.',
Vi='Vitriol:BAAANQAECgMIBAAAAA==.',
Wa='Wampa:BAAANQAECgEIAgAAAA==.Wanderblue:BAAANQAECgMIAwAAAA==.Wangstah:BAAANQAECgMIAwAAAA==.Wartogoteam:BAAANQAECgcIEwAAAA==.Waytogoteam:BAAANQADCgMIAwAAAA==.',
We='Weiss:BAABNQAECoEcAAICAAkJ1R/JFgBCAwACAAkJ1R/JFgBCAwAAAA==.',
Wf='Wf:BAAANQAECgYIEwAAAA==.',
Wo='Woog:BAAANQADCgYIBgAAAA==.',
Wy='Wyldspirit:BAAANQADCggIGgAAAA==.Wyreless:BAAANQAECgQIBwABNQAECgUICQAEAAAAAA==.',
Ya='Yaass:BAAANQADCggICAABNQAECgYIEwAEAAAAAA==.Yagrum:BAAANQAECgEIAQAAAA==.Yahikko:BAAANQAECggIDgAAAA==.',
Yo='Yoddaa:BAAANQAECgQIBQABNQAECgMIBAAEAAAAAA==.',
Ze='Zergen:BAAANQADCgYIBgAAAA==.',
Zh='Zhenya:BAAANQAECgYIEAAAAA==.',
Zu='Zuga:BAAANQAECgEIAQAAAA==.',
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
