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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abc:BAAANQADCgIIAgAAAA==.',
Ag='Agrippa:BAAANQAECgQIBAAAAA==.',
Ah='Ahndhrez:BAAANQADCgQIBAAAAA==.',
Ai='Aidric:BAAANQADCgcIDAAAAA==.Airwavez:BAAANQAECgYICQAAAA==.',
Ak='Akriel:BAAANQAECgQIBgAAAA==.',
Al='Albrecht:BAAANQADCgEIAQAAAA==.Altra:BAAANQAECgQIBQAAAA==.Alumit:BAAANQAECgEIAQAAAA==.',
Am='Amoeta:BAAANQAECgEIAQAAAA==.',
An='Angryapples:BAAANQADCgMIAwAAAA==.',
Ap='Approved:BAAANQADCgYIBQAAAA==.',
Ar='Arconos:BAAANQADCgYIDAABNQAECgcICwABAAAAAA==.',
As='Asomyrh:BAAANQADCggIDgAAAA==.',
Au='Aurial:BAAANQADCgMIAwAAAA==.',
Ba='Babygirl:BAAANQAECgMIAwAAAA==.Bananer:BAAANQAECgQIBAAAAA==.Banonzarath:BAAANQADCggICAAAAA==.Baulie:BAAANQADCgMIBAAAAA==.',
Be='Bekroh:BAAANQADCggIDQAAAA==.',
Bi='Bigdaddyd:BAAANQADCggIDQAAAA==.Bioodlion:BAAANQAECgEIAQAAAA==.Bipolar:BAAANQADCggIDQAAAA==.Bippysmasher:BAAANQAECgEIAQAAAA==.Bishmanistic:BAAANQADCgcIBwAAAA==.',
Bl='Blacblood:BAAANQAECgEIAQAAAA==.Blindweiss:BAAANQADCgcIBwABNQAECgcICwABAAAAAA==.Blinkies:BAAANQAECgQIBAAAAA==.',
Bo='Bontao:BAAANQAECgcICwAAAA==.Bontaopanda:BAAANQADCgcIDQABNQAECgcICwABAAAAAA==.Boomies:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Borstenne:BAAANQAECgQIBQAAAA==.Bosco:BAAANQADCgQIBAAAAA==.',
Br='Bresepls:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.Breseshh:BAAANQAECgQIBQAAAA==.Brickbow:BAAANQADCgYIBgAAAA==.Brickette:BAAANQADCgcIDQABNQAECgcICwABAAAAAA==.Bricklicker:BAAANQADCgYICAAAAA==.Bricksquad:BAAANQAECgQIBAAAAA==.Brickthrow:BAAANQAECgcICwAAAA==.',
Bu='Burgerburn:BAAANQADCgYIBwAAAA==.',
By='Bytheway:BAAANQADCggICgAAAA==.',
['Bé']='Béstt:BAAANQADCgMIAwAAAA==.',
Ca='Cadilak:BAAANQAECgQIBQAAAA==.Caelesti:BAAANQADCgYICwAAAA==.Camlin:BAAANQADCgYIBgAAAA==.',
Ch='Cheapshotjoe:BAAANQADCgEIAQAAAA==.Chelbur:BAAANQAECgEIAQAAAA==.Chowderhead:BAAANQAECgQICAAAAA==.',
Ci='Cileb:BAAANQADCggIEAAAAA==.Civik:BAAANQADCgYIBgAAAA==.',
Co='Conchsniffer:BAAANQAECgUIBgAAAA==.Copperit:BAAANQAECgEIAQAAAA==.Cornburglar:BAAANQAECgIIAwAAAA==.',
Cr='Crunchwrap:BAAANQADCgYIBgAAAA==.',
['Câ']='Câlisse:BAAANQAECgUIBgABNQAECgYIBgABAAAAAA==.',
Da='Daddiedk:BAAANQAECgQIBAAAAA==.Damncats:BAAANQAECgEIAgAAAA==.Danielsboone:BAAANQADCgYICwAAAA==.Darkmare:BAAANQAECgQIBQAAAA==.',
De='Deadhippocow:BAAANQADCgYIDAAAAA==.Dearth:BAEANQAECgEIAQABNQAECgIIAgABAAAAAA==.Deathbane:BAAANQADCgUICAAAAA==.Deathwavez:BAAANQADCgcIBwAAAA==.Demayy:BAAANQADCggIDwAAAA==.Demona:BAAANQADCgQIBAAAAA==.Demonix:BAAANQADCggIDAAAAA==.Derptron:BAAANQAECgIIAgAAAA==.',
Di='Dilutedqt:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Dilutedret:BAAANQADCgMIAwABNQAECgQIBAABAAAAAA==.Dinobrass:BAAANQAECgIIAgAAAA==.Dirge:BAAANQADCggIDAAAAA==.Dirktheshiny:BAAANQAECgUIBgAAAA==.Dirtylöbster:BAAANQAECggIDgAAAA==.Disabel:BAAANQADCggICAAAAA==.',
Dj='Djinsurgent:BAAANQADCggICgAAAA==.',
Do='Doobysnacks:BAAANQAECgEIAQAAAA==.Doolittle:BAAANQADCgYICwAAAA==.Dorfies:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.',
Dr='Drewmee:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Droovani:BAAANQAECgEIAQAAAA==.Drunkenyeti:BAAANQADCgUIBgAAAA==.',
Du='Duckbeak:BAAANQADCgYIBgAAAA==.',
['Dæ']='Dæmona:BAAANQAECgUIBgAAAA==.',
Eb='Ebk:BAAANQAECgEIAQAAAA==.Ebkx:BAAANQADCgEIAQAAAA==.',
El='Eladus:BAAANQAECgEIAgAAAA==.Elesus:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.',
Fa='Faithpasse:BAAANQADCggIDgAAAA==.',
Fe='Felondar:BAAANQADCgYICwAAAA==.Ferarro:BAAANQADCggICAAAAA==.',
Fi='Finnadin:BAAANQADCgcICQAAAA==.Finns:BAAANQADCgcIBwAAAA==.Fistuu:BAAANQADCgUIBQAAAA==.',
Fl='Flysky:BAAANQAECgcICwAAAA==.',
Fo='Foxsake:BAAANQADCgQIBAAAAA==.',
Fu='Fuzzydeeps:BAAANQADCgYICQAAAA==.',
Ga='Garduuk:BAAANQADCggIDwAAAA==.',
Ge='Gearth:BAAANQAECgUIBgAAAA==.',
Gr='Gravey:BAAANQAECgQIBAAAAA==.Grrahtahtah:BAAANQAECgcICwAAAA==.',
Ha='Hammerinfred:BAAANQADCggIDQAAAA==.',
Hi='Hippayman:BAAANQAECgIIAgAAAA==.Hippysmasher:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.',
Ho='Holyhooters:BAAANQADCggIDgAAAA==.Holypablo:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Honour:BAAANQADCggIDwAAAA==.',
Hr='Hrathdemon:BAAANQAECgQIBQAAAA==.Hrathion:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.',
Hu='Hupa:BAAANQAECgYICQAAAA==.Hurtsdonut:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Huulis:BAAANQADCggICAAAAA==.',
Ic='Ickeetard:BAAANQADCgcIBwAAAA==.',
Id='Idiotbreath:BAAANQAECgQIBAAAAA==.',
Ie='Ieatcheeks:BAAANQADCgUIBQAAAA==.Ieyasu:BAAANQAECgQIBAABNQAECgUICAABAAAAAA==.',
Ig='Ignitus:BAAANQAECgEIAQAAAA==.',
In='Insulinshot:BAAANQADCgYICgAAAA==.',
It='Itsmagharszn:BAAANQADCgEIAQAAAA==.',
Ja='Jabronipie:BAAANQADCggIBQAAAA==.',
Jh='Jhana:BAAANQADCgEIAQABNQADCgMIAwABAAAAAA==.',
Jo='Josh:BAAANQADCgYICwAAAA==.',
Jy='Jyve:BAAANQAECgIIAgAAAA==.',
Ka='Kailin:BAAANQADCgQIBAAAAA==.Kamanactali:BAAANQADCgYICwAAAA==.Kaneko:BAAANQADCgcIBwABNQAECgUICAABAAAAAA==.Katalina:BAAANQAECgUIBgAAAA==.',
Kh='Kham:BAAANQAECgEIAgAAAA==.',
Ki='Kirren:BAAANQADCgIIAgAAAA==.',
La='Lavashiza:BAAANQAECgEIAQAAAA==.',
Le='Leadzorz:BAAANQADCgYICQAAAA==.',
Li='Liltotem:BAAANQAECgMIBQAAAA==.Linaria:BAAANQADCgUIBQAAAA==.Lizzymonk:BAAANQAECgQIBQAAAA==.',
Lo='Lockdownlol:BAAANQAECgQIBAAAAA==.',
Lu='Luluh:BAAANQADCggIDwAAAA==.',
Ma='Maddog:BAAANQAECgEIAQAAAA==.Maebell:BAAANQADCgYICAABNQAECgQIBAABAAAAAA==.Mageslayer:BAAANQADCgcIBQAAAA==.Magrun:BAAANQADCgUIBQAAAA==.Matt:BAAANQAECgQIBQAAAA==.Mavrik:BAAANQADCggIDwAAAA==.',
Me='Meatmagic:BAAANQADCgIIAgAAAA==.Megapunk:BAAANQADCgUIBgAAAA==.Melanyie:BAAANQADCgMIAwAAAA==.Meudayr:BAAANQADCggIEAAAAA==.',
Mi='Mischifgg:BAAANQADCgYIBgAAAA==.',
Mo='Moobear:BAAANQAECgEIAQAAAA==.Moogie:BAAANQAECgcIDwAAAA==.Moozlock:BAAANQAECgEIAQAAAA==.Morgiana:BAAANQAECgQIBAAAAA==.Moscovio:BAAANQAFFAEIAQAAAA==.Mosspaws:BAAANQAECgQIBAAAAA==.',
Mt='Mtndewyou:BAAANQADCgcIDQAAAA==.',
Na='Napok:BAAANQADCgEIAQAAAA==.',
Ni='Nihr:BAAANQADCgUIBQAAAA==.Ninkarrak:BAAANQADCgYICwAAAA==.',
Nm='Nme:BAAANQAECgIIAgAAAA==.',
No='Nocturnos:BAAANQAECgEIAQAAAA==.Novamancer:BAAANQADCgYIDgAAAA==.',
Ny='Nymage:BAAANQAECgIIAgAAAA==.',
Ok='Okaerisan:BAAANQADCgMIAwAAAA==.',
Ol='Olord:BAAANQADCgEIAQAAAA==.',
Or='Orack:BAAANQADCgcIDAAAAA==.',
Ou='Outlast:BAAANQADCgYIBgAAAA==.',
Ow='Owch:BAAANQABCgIIAgABNQADCggIEAABAAAAAA==.',
Pa='Panblind:BAAANQAECgcICwAAAA==.Parmageddon:BAAANQAECgQIBQAAAA==.Parmrageiano:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.',
Pe='Peanought:BAAANQADCgcIDQAAAA==.Peetfix:BAAANQAECgQIBAAAAA==.Pepsipink:BAAANQADCgYIBgAAAA==.',
Pi='Picklegrip:BAAANQADCggIDAAAAA==.Pijak:BAAANQADCgYICwAAAA==.',
Pl='Planetina:BAAANQADCgcIBwAAAA==.',
Po='Poah:BAAANQAECggICQAAAA==.',
Pr='Pruflas:BAAANQAECgEIAQAAAA==.',
Ps='Psycodk:BAAANQAECgIIAgAAAA==.',
Pu='Pumpin:BAAANQADCgcIDAAAAA==.Punkthor:BAAANQADCggIDQAAAA==.',
['Pø']='Pø:BAAANQADCgcIBwAAAA==.',
Qk='Qkn:BAAANQADCgUICQAAAA==.',
Ra='Ratoncita:BAAANQADCgUIBQAAAA==.Razerblade:BAAANQADCgEIAQAAAA==.',
Re='Reisar:BAAANQADCgEIAQAAAA==.Rennera:BAAANQADCgUICQAAAA==.Revalation:BAAANQADCggIEAAAAA==.',
Ri='Riachu:BAAANQADCgQIBAAAAA==.Ribeyejoe:BAAANQADCgMIAwAAAA==.',
Ro='Roken:BAAANQADCggICAAAAA==.',
Sa='Sagan:BAEANQADCgQIBAABNQADCggICgABAAAAAA==.Sandasa:BAAANQAECgMIBAAAAA==.Sanivanth:BAAANQADCgQIBAAAAA==.Saucerdote:BAAANQAECgIIAgAAAA==.Saxon:BAAANQADCggIDAAAAA==.',
Se='Selinfinite:BAAANQAECgIIAgAAAA==.Selkie:BAAANQADCgcIDAAAAA==.Serenitynow:BAAANQADCgQIBAAAAA==.',
Sh='Shadowmaven:BAAANQADCgcICgAAAA==.Shakakhan:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Shamshielder:BAEANQAECgYICwAAAA==.Sharick:BAAANQADCgYICQAAAA==.Shawlee:BAAANQAECgMIAwAAAA==.Shellwit:BAAANQADCgcICwABNQAECgQIBAABAAAAAA==.Shetmage:BAAANQADCgcIBwABNQAECgcICwABAAAAAA==.Shettrah:BAAANQAECgcICwAAAA==.Shwoobs:BAAANQADCgQIBAAAAA==.',
Si='Sijious:BAAANQADCgcIEQAAAA==.Singularity:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Sk='Skyland:BAAANQADCgcIBwABNQAECgcICwABAAAAAA==.',
So='Somi:BAAANQAECgQIBQAAAA==.',
St='Stabbystab:BAAANQAECgEIAQABNQADCgEIAQABAAAAAA==.Stankydk:BAAANQAECgcICwAAAA==.Stankyleg:BAAANQADCgcIDQAAAA==.Stewie:BAAANQAECgEIAQAAAA==.',
Su='Subrogue:BAAANQAECgQIBAABNQAECgcICwABAAAAAA==.',
Sy='Sylphrena:BAAANQAECgQIBQAAAA==.',
Ta='Tacow:BAAANQADCgcIDQAAAA==.Talethen:BAAANQADCggIDAAAAA==.',
Th='Thedrood:BAAANQADCggIDwAAAA==.',
To='Tohk:BAAANQAECgcICwAAAA==.Tollee:BAAANQADCggIDwAAAA==.Tontiamat:BAAANQADCggIDwAAAA==.Tontier:BAAANQADCgYICwABNQADCggIDwABAAAAAA==.Tormero:BAAANQADCgcIBwAAAA==.Touchyfred:BAAANQADCgQIBAAAAA==.',
Tr='Treily:BAAANQAECgEIAgAAAA==.Truestorm:BAAANQADCggIAgAAAA==.',
Tu='Tuchi:BAAANQAECgYICAAAAA==.',
['Tà']='Tàcobelle:BAAANQADCgYICwAAAA==.',
Va='Vanicton:BAAANQAECgUIBwAAAA==.',
Ve='Ve:BAAANQADCggIEAAAAA==.Vegh:BAAANQAECgQIBAAAAA==.Veldcat:BAAANQADCgcICwAAAA==.Veriale:BAAANQADCgYICwAAAA==.Verra:BAAANQAECgEIAQAAAA==.',
Vi='Vitriol:BAAANQADCgIIAgAAAA==.',
Wa='Wampa:BAAANQADCgYIBgAAAA==.Wangstah:BAAANQADCgcIDAAAAA==.Wartogoteam:BAAANQAECgQIBQAAAA==.',
We='Weiss:BAAANQAECgcICwAAAA==.',
Wf='Wf:BAAANQAECgQICAAAAA==.',
Wo='Woog:BAAANQADCgYIBgAAAA==.',
Wy='Wyldspirit:BAAANQADCgYICwAAAA==.',
Ya='Yagrum:BAAANQADCgYIBgAAAA==.',
Yo='Yoddaa:BAAANQADCgMIAwABNQADCggIDAABAAAAAA==.',
Ze='Zergen:BAAANQADCgYIBgAAAA==.',
Zh='Zhenya:BAAANQAECgQIBQAAAA==.',
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
