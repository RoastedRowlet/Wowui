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

local lookup = {'Hunter-Marksmanship','DeathKnight-Frost','DeathKnight-Blood','Mage-Arcane','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Unholy','Shaman-Restoration','Paladin-Holy','Paladin-Retribution','Druid-Restoration','Warlock-Destruction','Warlock-Demonology','Monk-Windwalker','Warrior-Fury','Rogue-Subtlety','DemonHunter-Havoc','Priest-Discipline','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','DemonHunter-Devourer','Druid-Balance','DemonHunter-Vengeance','Shaman-Elemental','Monk-Brewmaster','Priest-Holy','Warrior-Arms','Priest-Shadow',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abc:BAAANQADCgIIAgAAAA==.',
Ae='Aeviee:BAAANQADCgQJBAAAAA==.',
Ag='Agrippa:BAAANQAECgcJDwAAAA==.',
Ah='Ahndhrez:BAAANQADCgUICQAAAA==.',
Ai='Aidric:BAAANQAECgQIBwAAAA==.Airwavez:BAABNQAECoEkAAIBAAkKIBuXDADcAgABAAkKIBuXDADcAgAAAA==.',
Ak='Akriel:BAAANQAECgYIDQAAAA==.',
Al='Albrecht:BAAANQADCgEIAQAAAA==.Aldeor:BAAANQADCgMIAwAAAA==.Altra:BAABNQAECoEbAAMCAAgKERVPHQATAgACAAgKERVPHQATAgADAAEKEQUbpAAkAAAAAA==.Alumit:BAAANQAECgYJDwAAAA==.',
Am='Amoeta:BAAANQAECgcJEAAAAA==.',
An='Andor:BAAANQADCgMJAwAAAA==.Angelique:BAAANQAECgUJCgAAAA==.Angry:BAAANQADCgYICgAAAA==.Angryapples:BAAANQAECgQJBQAAAA==.Annihilation:BAAANQADCgUIBQAAAA==.',
Ap='Approved:BAAANQADCgYIBQAAAA==.',
Ar='Arconos:BAAANQADCgYIDAABNQAECgkJHwAEAPYgAA==.',
As='Ashguard:BAAANQADCgUJBQAAAA==.Asomyrh:BAAANQAECgYJDwAAAA==.',
Au='Aurial:BAAANQADCgMIAwAAAA==.',
Ba='Babygirl:BAAANQAECgYICAAAAA==.Bananer:BAAANQAECgQICAAAAA==.Banonzarath:BAAANQADCggICAAAAA==.Barrysoetoro:BAAANQADCgcIDAAAAA==.Baulie:BAAANQAECgQIBAAAAA==.',
Be='Beefstick:BAAANQADCgYIBgAAAA==.Bekroh:BAAANQAECgYIEAAAAA==.Bestt:BAAANQAECgQJBAAAAA==.',
Bi='Bigdaddyd:BAAANQAECgMJBQAAAA==.Bigdonk:BAAANQADCggJCAAAAA==.Bigocagler:BAAANQADCggIEAAAAA==.Bioodlion:BAAANQAECgcIDQAAAA==.Bipolar:BAAANQAECgMIBgAAAA==.Bippysmasher:BAAANQAECgcJEAAAAA==.Bishmanistic:BAAANQAECgQICgAAAA==.',
Bl='Blacblood:BAAANQAECgEIAQAAAA==.Blindweiss:BAAANQADCgcIBwABNQAECgkJHwAEAPYgAA==.Blinkies:BAAANQAECggJEgAAAA==.',
Bo='Bontao:BAABNQAECoEiAAIFAAkK6B12FAABAwAFAAkK6B12FAABAwAAAA==.Bontaopanda:BAAANQADCgcIEwABNQAECgkJIgAFAOgdAA==.Boomies:BAAANQADCgQJBAABNQAECggJEgAGAAAAAA==.Borstenne:BAABNQAECoEYAAIHAAcK3iMUFgC8AgAHAAcK3iMUFgC8AgAAAA==.Bosco:BAAANQADCgQIBAAAAA==.',
Br='Bresepls:BAAANQAECgIJAwABNQAECggJGwAIAOogAA==.Breseshh:BAABNQAECoEbAAIIAAgK6iDMDwAKAwAIAAgK6iDMDwAKAwAAAA==.Brickbeard:BAAANQAECgMIAwAAAA==.Brickbow:BAAANQADCgYIBgAAAA==.Brickette:BAAANQADCgcIEwABNQAFFAMIBQAJAAAHAA==.Bricklicker:BAAANQAECgMIAwAAAA==.Bricksquad:BAAANQAECgcJDQAAAA==.Brickthrow:BAACNQAFFIEFAAIJAAMKAAenCwDlAAAJAAMKAAenCwDlAAA1AAQKgR8AAwkACQpDGi8ZAMYCAAkACQpDGi8ZAMYCAAoAAQr5D+sRAT4AAAAA.',
Bu='Burgerburn:BAAANQADCgcIEwAAAA==.',
By='Bytheway:BAAANQAECgMJAwAAAA==.',
['Bé']='Béstt:BAAANQAECgYIDQAAAA==.',
Ca='Cadilak:BAABNQAECoEaAAILAAgKihRsFQAYAgALAAgKihRsFQAYAgAAAA==.Caelesti:BAAANQAECgEJAQAAAA==.Camlin:BAAANQADCggIDgAAAA==.Catrina:BAEANQADCggICAABNQAECggJDAAGAAAAAA==.',
Ch='Cheapshotjoe:BAAANQADCgEIAQAAAA==.Chelbur:BAAANQAECgIJAwAAAA==.Chowderhead:BAABNQAECoEaAAMMAAkKUxa1BgCCAgAMAAkKUxa1BgCCAgANAAEK9wz+5QA0AAAAAA==.',
Ci='Cileb:BAAANQAECgYJDwAAAA==.Civik:BAAANQADCgYIBgAAAA==.',
Co='Cocio:BAAANQAECgUICQABNQAECgcJEgAGAAAAAA==.Conchsniffer:BAABNQAECoEdAAIKAAkK3RxtIQDkAgAKAAkK3RxtIQDkAgAAAA==.Conrack:BAAANQADCggJCAAAAA==.Copperit:BAAANQAECgcJDwAAAA==.Cornburglar:BAAANQAECgcJEgAAAA==.Corrona:BAEANQADCggJCAABNQAECggJDAAGAAAAAA==.',
Cr='Crunchwrap:BAAANQAECgQIBgAAAA==.',
['Câ']='Câlisse:BAABNQAECoEiAAIOAAkKeiHPBABZAwAOAAkKeiHPBABZAwAAAA==.',
Da='Daddiedk:BAABNQAECoEWAAICAAcK/xYEHwADAgACAAcK/xYEHwADAgAAAA==.Damncats:BAABNQAECoEWAAIPAAUKHAsgEAAZAQAPAAUKHAsgEAAZAQAAAA==.Danielsboone:BAAANQAECgMJAwAAAA==.Darkmare:BAABNQAECoEYAAIQAAgKkxX1EAA7AgAQAAgKkxX1EAA7AgAAAA==.Darknemesis:BAAANQADCgcIDAABNQADCggICAAGAAAAAA==.',
De='Deadhippocow:BAAANQAECgQICwAAAA==.Dearth:BAEANQAECggJDAAAAA==.Deathbane:BAAANQAECgQJBAAAAA==.Deathwavez:BAAANQAECggJCgAAAA==.Demayy:BAAANQAECgUIDAAAAA==.Demona:BAAANQAECgMIBAAAAA==.Demonix:BAAANQAECgUICQAAAA==.Derptron:BAAANQAECgYJDQAAAA==.',
Di='Dilutedqt:BAAANQAECgcJEQAAAA==.Dilutedret:BAAANQADCgMIAwABNQAECgcJEQAGAAAAAA==.Dinobrass:BAAANQAECgcJEwAAAA==.Dirge:BAAANQAECgUIDAAAAA==.Dirktheshiny:BAABNQAECoEeAAIKAAgKUxqQPQBdAgAKAAgKUxqQPQBdAgAAAA==.Dirtylöbster:BAABNQAECoEmAAIEAAkK0h4EJAAoAwAEAAkK0h4EJAAoAwAAAA==.Disabel:BAAANQADCggICAAAAA==.Distracto:BAAANQAECggICgAAAA==.',
Dj='Djinsurgent:BAAANQAECgMJBgAAAA==.',
Dl='Dltdjr:BAAANQAECgQIBAABNQAECgcJEQAGAAAAAA==.',
Do='Doobysnacks:BAAANQAECgcJEAAAAA==.Doolittle:BAAANQADCgYICwAAAA==.Dorfies:BAAANQADCgcJCAABNQAECggJEgAGAAAAAA==.Dorns:BAAANQADCgEIAQAAAA==.',
Dr='Dralock:BAAANQAECgQIBAABNQADCgYIBgAGAAAAAA==.Dreamyeti:BAAANQADCgEIAQAAAA==.Dreats:BAAANQADCgEJAQAAAA==.Drewmee:BAAANQAECgYJBgAAAA==.Droovani:BAAANQAECgUICgABNQAECgYJBgAGAAAAAA==.Drunkenyeti:BAAANQADCgcIEAAAAA==.',
Du='Duckbeak:BAAANQAECgIIAgAAAA==.Duwork:BAAANQAECgQICgAAAA==.',
['Dæ']='Dæmona:BAABNQAECoEfAAIRAAgK4RSkHwAfAgARAAgK4RSkHwAfAgAAAA==.',
Eb='Ebk:BAAANQAECgcICQAAAA==.Ebkx:BAAANQAECgEIAQAAAA==.',
El='Eladus:BAAANQAECgQJCwAAAA==.Elesus:BAAANQADCgIJAgABNQAECgkJHAASAEcdAA==.',
Em='Emblaze:BAAANQADCgUIBQAAAA==.Emrys:BAAANQADCgMIAwAAAA==.',
En='Enhshaman:BAAANQAECgMIBAABNQAFFAUICwABAGEXAA==.',
Fa='Faithpasse:BAAANQAECgQJBwAAAA==.',
Fe='Felondar:BAAANQAECgYJDAAAAA==.Ferarro:BAAANQAECgYJCwAAAA==.',
Fi='Finnadin:BAAANQADCgcIDQAAAA==.Finns:BAAANQAECgMJBAAAAA==.Firulais:BAAANQAECgUICAAAAA==.Fistuu:BAAANQADCgUIBQAAAA==.',
Fl='Flysky:BAACNQAFFIEFAAITAAMKZBKJCAD+AAATAAMKZBKJCAD+AAA1AAQKgR8ABBMACQqUIvsDAE8DABMACQqUIvsDAE8DABQABAotHzYJAF4BABUABQoWFyMaAEcBAAAA.',
Fo='Foxsake:BAAANQADCgQIBAAAAA==.',
Fu='Futurefist:BAAANQADCggICAAAAA==.',
Ga='Garduuk:BAAANQAECgUJDAAAAA==.',
Ge='Gearth:BAABNQAECoEYAAIWAAcK7hwVCwBdAgAWAAcK7hwVCwBdAgAAAA==.',
Gl='Glucose:BAAANQAECgQJBAAAAA==.',
Go='Gonah:BAAANQAECgUIBQAAAA==.Gotlieb:BAAANQAECgEJAQAAAA==.',
Gr='Gravey:BAABNQAECoEWAAIDAAcKKBqQKAAVAgADAAcKKBqQKAAVAgAAAA==.Grogger:BAAANQADCgUIBQAAAA==.Grrahtahtah:BAACNQAFFIELAAIBAAUKYRfIBAClAQABAAUKYRfIBAClAQA1AAQKgSQAAwEACQr3IJgFAFcDAAEACQrUIJgFAFcDAAUAAQo7E73lAE0AAAAA.',
Gy='Gymble:BAAANQADCgMJAwAAAA==.',
Ha='Hakkim:BAAANQADCggICAAAAA==.Hammerinfred:BAAANQAECgEIAQAAAA==.',
He='Heavyguard:BAAANQABCgIIAgAAAA==.',
Hi='Hippayman:BAAANQAECgIJBAAAAA==.Hippysmasher:BAAANQADCggICAABNQAECgcJEAAGAAAAAA==.',
Ho='Holyhooters:BAAANQAECgUICwAAAA==.Holypablo:BAAANQADCgYJDgABNQAECgcJEgAGAAAAAA==.Honour:BAAANQAECgUIDAAAAA==.',
Hr='Hrathdemon:BAABNQAECoEaAAIXAAgK4iF8CgAKAwAXAAgK4iF8CgAKAwAAAA==.Hrathion:BAAANQADCgcJDQABNQAECggJGgAXAOIhAA==.',
Hu='Hupa:BAABNQAECoEbAAIKAAcK4CIsLQCmAgAKAAcK4CIsLQCmAgAAAA==.Hurtsdonut:BAAANQAECgQJCAABNQAECgkJHAASAEcdAA==.Huulis:BAAANQADCggICAAAAA==.',
Ia='Iamheyo:BAAANQAECgUJBQAAAA==.',
Ic='Ickeetard:BAAANQADCgcJBwAAAA==.',
Id='Idiotbreath:BAAANQAECgYIDwAAAA==.',
Ie='Ieatcheeks:BAAANQAECgUICQAAAA==.Ieyasu:BAABNQAECoEZAAIYAAgKNxOPKAAkAgAYAAgKNxOPKAAkAgAAAA==.',
Ig='Ignitus:BAAANQAECgQIBQAAAA==.',
Ik='Ikuchi:BAAANQADCgYJBgAAAA==.',
Il='Illpownyou:BAAANQADCgcIBwABNQAECgMJBQAGAAAAAA==.',
In='Insulinshot:BAAANQAECgIIAwAAAA==.',
Ir='Ironguard:BAAANQABCgMIAwAAAA==.',
It='Itsmagharszn:BAAANQADCgEIAQAAAA==.',
Ja='Jabronipie:BAAANQADCggIBQAAAA==.',
Je='Jessica:BAAANQAECgEIAgAAAA==.',
Jh='Jhana:BAAANQADCgUICQAAAA==.',
Jj='Jjooaacchhim:BAAANQAECgQIBAAAAA==.',
Jo='Josh:BAAANQADCgYJEQAAAA==.',
Ju='Junglefever:BAAANQADCgYIBgAAAA==.',
Jy='Jyve:BAAANQAECgYIEgAAAA==.',
Ka='Kailin:BAAANQADCgUIBQAAAA==.Kamanactali:BAAANQADCgYIEQAAAA==.Kamele:BAAANQADCgEJAQAAAA==.Kaneko:BAAANQAECgQIBAABNQAECggIGQAYADcTAA==.Katalina:BAABNQAECoEZAAMZAAYKCBTODQA5AQARAAYKzRDDNABZAQAZAAYKBA7ODQA5AQAAAA==.',
Ke='Kelstormhoof:BAAANQADCgcIEQABNQADCggICAAGAAAAAA==.',
Kh='Kham:BAAANQAFFAEIAQAAAA==.',
Ki='Kirren:BAAANQADCgIIAgAAAA==.',
Kl='Klais:BAAANQADCgQIBQAAAA==.',
Ko='Kokeovrdose:BAAANQABCgQIBAABNQADCgYICgAGAAAAAA==.',
La='Lavashiza:BAAANQAECgQICgAAAA==.',
Le='Leadzorz:BAAANQADCgYIDwAAAA==.Leedaddydk:BAAANQABCgQIBgAAAA==.Legday:BAAANQAECgMIAwAAAA==.',
Li='Liltotem:BAABNQAECoEVAAMIAAcKfhIOWgCCAQAIAAYKXhMOWgCCAQAaAAIKBQf7twB6AAAAAA==.Linaria:BAAANQADCgUIBQAAAA==.Lizzymonk:BAABNQAECoEaAAIbAAgKjiANBADtAgAbAAgKjiANBADtAgAAAA==.',
Lo='Lockdownlol:BAAANQAECgQIEAABNQAECgcJEQAGAAAAAA==.',
Lu='Luluh:BAAANQAECgQJDQAAAA==.',
Ma='Maddog:BAAANQAECgUJCgAAAA==.Maebell:BAAANQAECgQIBgABNQAECgcJEQAGAAAAAA==.Mageslayer:BAAANQAECgUICQAAAA==.Magicpewfred:BAAANQADCgIJAgAAAA==.Magrun:BAAANQADCgUJCQAAAA==.Maiggee:BAAANQADCgcJBwAAAA==.Matt:BAABNQAECoEbAAIFAAgK9R4CIAC8AgAFAAgK9R4CIAC8AgAAAA==.Mavrik:BAAANQAECgUJDAAAAA==.',
Me='Meatmagic:BAAANQADCgIJAgAAAA==.Megapunk:BAAANQADCgcJFAAAAA==.Melanyie:BAAANQADCgMIAwAAAA==.Melfìce:BAAANQADCgYIBgAAAA==.Meudayr:BAAANQAECgYJDwAAAA==.',
Mi='Millarolly:BAAANQADCgYICAAAAA==.Mischifdk:BAAANQADCgEJAQAAAA==.Mischifdots:BAAANQADCgcIDAAAAA==.Mischifgg:BAAANQAECgUJCwAAAA==.Mittenss:BAAANQADCggICQAAAA==.',
Mn='Mndgblnfred:BAAANQADCgEIAQAAAA==.',
Mo='Mojorisinn:BAAANQAECgQIBAAAAA==.Moobear:BAAANQAECgcJEAAAAA==.Moogie:BAABNQAECoEnAAIEAAkKIxxwRAC+AgAEAAkKIxxwRAC+AgAAAA==.Moozlock:BAAANQAECgEIAQAAAA==.Morgiana:BAAANQAECgYIDwAAAA==.Moscovio:BAACNQAFFIELAAMNAAUKDBNPBwBJAQANAAQKJhZPBwBJAQAMAAIKtQllCgCeAAA1AAQKgSQAAw0ACQqUIeIPAA4DAA0ACQo1IeIPAA4DAAwAAQqtGdRZAEsAAAAA.Mosspaws:BAAANQAECgUICAAAAA==.',
Mt='Mtndewyou:BAAANQAECgUJCQAAAA==.',
Na='Napok:BAAANQAECgIIAwAAAA==.',
Ni='Nihr:BAAANQAECgQIBAAAAA==.Ninkarrak:BAAANQADCgYIEQAAAA==.',
Nm='Nme:BAAANQAECgYJDwAAAA==.',
No='Nocturnos:BAAANQAECgUIBgAAAA==.Novamancer:BAAANQAECgEIAQAAAA==.',
Nu='Nuph:BAAANQAECgQIBQAAAA==.',
Ny='Nymage:BAAANQAECgYICwAAAA==.',
Og='Ogdaddy:BAAANQADCggICAAAAA==.',
Ok='Okaerisan:BAAANQADCgMIAwAAAA==.',
Ol='Olord:BAAANQADCgEJAgAAAA==.',
Or='Orack:BAAANQAECgQJBgAAAA==.',
Ou='Outlast:BAAANQADCgYIBgAAAA==.',
Ow='Owch:BAAANQABCgIIAgABNQAECgYJDwAGAAAAAA==.',
Pa='Panblind:BAACNQAFFIEFAAMZAAMKrhzyAAAAAQAZAAMKkhnyAAAAAQAXAAIKwhlkCAC4AAA1AAQKgR8AAxcACQqfILELAPcCABcACQpbHbELAPcCABkAAwrlIvMNADYBAAAA.Parmageddon:BAABNQAECoEbAAIDAAgKehhOJgAlAgADAAgKehhOJgAlAgAAAA==.Parmrageiano:BAAANQADCgUIBQABNQAECggJGwADAHoYAA==.',
Pe='Peanought:BAAANQAECgUIDAAAAA==.Peetfix:BAABNQAECoEXAAMaAAcKJBXVSQDLAQAaAAcKJBXVSQDLAQAIAAMKOB8VfgALAQAAAA==.Pepsipink:BAAANQAECgEJAQAAAA==.',
Ph='Phèdre:BAEANQAECgMIBAABNQAFFAUJCAAKACcTAA==.',
Pi='Picklegrip:BAAANQAECgYJDwAAAA==.Pijak:BAAANQADCgYIEQAAAA==.',
Pl='Planetina:BAAANQADCgcIBwAAAA==.',
Po='Poah:BAABNQAECoEUAAIOAAgKzx/pCQDpAgAOAAgKzx/pCQDpAgAAAA==.Portalcombat:BAAANQAECgIIAgAAAA==.',
Pr='Prettynhealz:BAAANQADCgIIAgAAAA==.Pruflas:BAAANQAECgEIAgAAAA==.',
Ps='Psycodk:BAAANQAECgYICAAAAA==.',
Pu='Pumpin:BAAANQAECgMIBAAAAA==.Punkthor:BAAANQAECgMJBgAAAA==.Purgemepappy:BAAANQADCgYIDAAAAA==.Putitinme:BAAANQABCgIIAgAAAA==.',
['Pø']='Pø:BAAANQAECgUJCwAAAA==.',
Qk='Qkn:BAAANQADCgcIFgAAAA==.',
Ra='Raf:BAAANQAECgYJCwAAAA==.Ratoncita:BAAANQADCgUIBQAAAA==.Rayzee:BAAANQAECgEIAQAAAA==.',
Re='Reisar:BAAANQADCgEIAQAAAA==.Rennera:BAAANQADCgYJDwAAAA==.Revalation:BAAANQAECgQICAAAAA==.',
Ri='Riachu:BAAANQAECgUJDQAAAA==.Ribeyejoe:BAAANQAECgIJBAAAAA==.',
Ro='Roadblock:BAAANQAECgYICgAAAA==.Roboorc:BAAANQABCgEJAQAAAA==.Roken:BAAANQADCggICAAAAA==.Rorymcilroy:BAAANQAECgcIDgAAAA==.',
Sa='Sagan:BAEANQADCgQIBAABNQAECgUJCQAGAAAAAA==.Saifrah:BAAANQADCgEJAQAAAA==.Sandasa:BAAANQAECgMIBAAAAA==.Sanivanth:BAAANQADCgQIBAAAAA==.Saucerdote:BAAANQAECgYIDQAAAA==.Saxon:BAAANQAECgEIAQAAAA==.',
Se='Selenix:BAAANQADCgYJBgAAAA==.Selinfinite:BAAANQAECggIEQAAAA==.Selkie:BAAANQAECgQIBAAAAA==.Serenitynow:BAAANQAECgQIBAAAAA==.',
Sg='Sgge:BAAANQADCgYIBgAAAA==.',
Sh='Shadowmaven:BAAANQADCgcJCgAAAA==.Shakakhan:BAAANQAECgQIDgABNQAECgcJEQAGAAAAAA==.Shammer:BAEANQADCggIBgABNQAECgkJIgADAIIbAA==.Shamshielder:BAEBNQAECoEiAAMDAAkKghtRFwCgAgADAAkKghtRFwCgAgACAAMK4AcJXwBjAAAAAA==.Sharick:BAAANQADCgYICQAAAA==.Shawdrake:BAAANQADCgcIBwABNQAECgYIEgAGAAAAAA==.Shawlee:BAAANQAECgYIEgAAAA==.Shetmage:BAAANQAECgQJCQABNQAECgkJIQAYABgZAA==.Shettrah:BAABNQAECoEhAAIYAAkKGBmKGAC0AgAYAAkKGBmKGAC0AgAAAA==.Shottdown:BAAANQADCgUIBQAAAA==.Shwoobs:BAAANQAECgEIAQAAAA==.',
Si='Sigasunanvil:BAAANQAECgQIBAAAAA==.Sijious:BAAANQADCggIHwAAAA==.Singularity:BAAANQAECgMIBQABNQAECgcJEQAGAAAAAA==.',
Sk='Skanktank:BAAANQAECgYJBgAAAA==.Skyland:BAAANQADCgcIBwABNQAFFAMIBQATAGQSAA==.',
Sl='Slinkies:BAAANQADCgYICQABNQAECggJEgAGAAAAAA==.Slipknife:BAAANQAECgYJCwAAAA==.',
So='Somi:BAAANQAECgcJEQAAAA==.',
St='Stabbystab:BAAANQAECgYIDQABNQADCgEJAgAGAAAAAA==.Stankydk:BAAANQAECgcIEgAAAA==.Stankyleg:BAAANQAFFAIJAwAAAA==.Stewie:BAAANQAECgYIDgAAAA==.Stinkbombs:BAAANQAECgEIAQAAAA==.Stinkies:BAAANQAECgUIBgABNQAECggJEgAGAAAAAA==.',
Su='Subrogue:BAAANQAECgQICQABNQAFFAUICwABAGEXAA==.Sunlest:BAAANQADCgcJEQAAAA==.',
Sy='Sylphrena:BAABNQAECoEaAAIcAAgKhRgnLQBGAgAcAAgKhRgnLQBGAgAAAA==.',
Ta='Tacow:BAAANQAECgUIDAAAAA==.Talethen:BAAANQAECgMJBQAAAA==.',
Te='Telaragehoof:BAAANQADCggICAAAAA==.',
Th='Thedrood:BAAANQAECgcJEgAAAA==.',
To='Tohk:BAABNQAECoEgAAIRAAkKjyHfCAA1AwARAAkKjyHfCAA1AwAAAA==.Tollee:BAAANQAECgQIBAAAAA==.Tontiamat:BAAANQAECgUIDAAAAA==.Tontier:BAAANQAECgEJAQABNQAECgUIDAAGAAAAAA==.Tormero:BAAANQADCgcIBwAAAA==.Totembeans:BAAANQAECgQIBQAAAA==.Touchyfred:BAAANQADCgcJCQAAAA==.Toxicfury:BAAANQABCgUIBAAAAA==.',
Tr='Traash:BAAANQABCgIIAgAAAA==.Treily:BAAANQAECgMJCQAAAA==.Tricket:BAAANQAECgQICAAAAA==.Trolloladin:BAAANQADCggJDwAAAA==.Truestorm:BAAANQAECgUIBwAAAA==.',
Tu='Tuchi:BAABNQAECoEZAAIEAAgKkBpIaQBVAgAEAAgKkBpIaQBVAgAAAA==.',
['Tà']='Tàcobelle:BAAANQADCgYIEAAAAA==.',
Va='Vanicton:BAABNQAECoEYAAIIAAgKqyEIDAAsAwAIAAgKqyEIDAAsAwAAAA==.',
Ve='Ve:BAAANQAECgYJDwAAAA==.Vegh:BAABNQAECoEWAAIRAAcKuRp2HAA+AgARAAcKuRp2HAA+AgAAAA==.Velaei:BAAANQAECgEJAQAAAA==.Veldcat:BAAANQAECgUJBgAAAA==.Velddk:BAAANQADCggICAAAAA==.Veriale:BAAANQADCgYICwAAAA==.Verra:BAAANQAECgQIBwAAAA==.',
Vi='Vitriol:BAAANQAECgMIBAAAAA==.',
Wa='Wampa:BAAANQAECgEIAgAAAA==.Wanderblue:BAAANQAECgMIAwAAAA==.Wangstah:BAAANQAECgQIBwAAAA==.Warshaw:BAAANQABCgEJAQABNQAECgYIEgAGAAAAAA==.Wartogoteam:BAABNQAECoEfAAIdAAgKOxcHVAAdAgAdAAgKOxcHVAAdAgAAAA==.Waytogoteam:BAAANQADCgMIAwAAAA==.',
We='Weiss:BAABNQAECoEfAAIEAAkK9iBJHwA6AwAEAAkK9iBJHwA6AwAAAA==.',
Wf='Wf:BAABNQAECoEeAAMWAAgKhA0YDQAqAgAWAAgKhA0YDQAqAgAIAAQKQAmYoACrAAAAAA==.',
Wo='Woog:BAAANQADCgYIBgAAAA==.Worsthunterx:BAAANQAFFAEIAQABNQAFFAUIDQAeAE8jAA==.',
Wy='Wyldspirit:BAAANQAECgMJAwAAAA==.Wyreless:BAAANQAECgQIBwABNQAECgcJEAAGAAAAAA==.',
Ya='Yaass:BAAANQADCggJCAABNQAECggIHgAWAIQNAA==.Yagrum:BAAANQAECgEJAQAAAA==.Yahikko:BAAANQAECggJEQAAAA==.',
Ye='Yem:BAAANQAECgYIBgAAAA==.',
Yo='Yoddaa:BAAANQAECgQIBQABNQAECgUICQAGAAAAAA==.',
Ze='Zergen:BAAANQADCgYIBgAAAA==.Zetsu:BAAANQAECggIAwABNQAECggJEQAGAAAAAA==.',
Zh='Zhenya:BAABNQAECoEbAAIEAAgKsgyklADkAQAEAAgKsgyklADkAQAAAA==.',
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
