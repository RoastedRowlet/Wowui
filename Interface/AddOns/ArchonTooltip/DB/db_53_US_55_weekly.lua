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

local lookup = {'Rogue-Assassination','Hunter-Marksmanship','DeathKnight-Frost','DeathKnight-Blood','Druid-Guardian','Mage-Arcane','Paladin-Holy','Druid-Balance','Druid-Restoration','Paladin-Retribution','DemonHunter-Devourer','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Unholy','Shaman-Restoration','Warlock-Destruction','Warlock-Demonology','Warrior-Arms','Monk-Windwalker','Warrior-Fury','Rogue-Subtlety','DemonHunter-Havoc','Priest-Discipline','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','Priest-Holy','DemonHunter-Vengeance','Shaman-Elemental','Monk-Brewmaster','Mage-Frost','Priest-Shadow',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abc:BAAANQADCgIIAgAAAA==.',
Ae='Aeviee:BAAANQADCgQJBAAAAA==.',
Ag='Agrippa:BAABNQAECoEYAAIBAAgKbQwzKQDdAQABAAgKbQwzKQDdAQAAAA==.',
Ah='Ahndhrez:BAAANQADCgcIDwAAAA==.',
Ai='Aidric:BAAANQAECgQIBwAAAA==.Airwavez:BAABNQAECoEpAAICAAkKxRsvEADBAgACAAkKxRsvEADBAgAAAA==.',
Ak='Akriel:BAAANQAECgcIDwAAAA==.',
Al='Albrecht:BAAANQADCgEIAQAAAA==.Aldeor:BAAANQADCgMIAwAAAA==.Altra:BAABNQAECoEiAAMDAAgKGxhYIgAnAgADAAgKGxhYIgAnAgAEAAEKEQWhuAAkAAAAAA==.Alumit:BAAANQAECgYJDwAAAA==.',
Am='Amoeta:BAABNQAECoEcAAIFAAgKNRiZCwA6AgAFAAgKNRiZCwA6AgAAAA==.',
An='Andor:BAAANQADCgYICQAAAA==.Angelique:BAAANQAECgUIDwAAAA==.Angry:BAAANQADCgYICgAAAA==.Angryapples:BAAANQAECgQJBQAAAA==.Annihilation:BAAANQADCgUIBQAAAA==.',
Ap='Approved:BAAANQADCgYIBQAAAA==.',
Ar='Arconos:BAAANQADCgYIDAABNQAFFAUICQAGAPQXAA==.',
As='Ashguard:BAAANQADCgUJBQAAAA==.Asomyrh:BAABNQAECoEVAAIHAAcKTg3PZACaAQAHAAcKTg3PZACaAQAAAA==.',
Au='Aurial:BAAANQADCgMIAwAAAA==.',
Ba='Babygirl:BAAANQAECgYICQAAAA==.Bananer:BAAANQAECgQICAAAAA==.Banonzarath:BAAANQADCggICAAAAA==.Barrysoetoro:BAAANQADCgcIDAAAAA==.Baulie:BAAANQAECgQIBAAAAA==.',
Be='Beefstick:BAAANQADCggIDgAAAA==.Bekroh:BAABNQAECoEYAAMIAAcKKRdoNwDkAQAIAAcKKRdoNwDkAQAJAAEKbATHXgAqAAAAAA==.Bestt:BAAANQAECgQIBAAAAA==.',
Bi='Bigdaddyd:BAAANQAECgQICQAAAA==.Bigdonk:BAAANQADCggJCAAAAA==.Bigocagler:BAAANQADCggIFgAAAA==.Bioodlion:BAABNQAECoEUAAIKAAcKDgzCnQB4AQAKAAcKDgzCnQB4AQAAAA==.Bipolar:BAAANQAECgQICgAAAA==.Bippysmasher:BAABNQAECoEXAAILAAgKBBXOHgAfAgALAAgKBBXOHgAfAgAAAA==.Bishmanistic:BAAANQAECgQICwAAAA==.',
Bl='Blacblood:BAAANQAECgEIAQAAAA==.Blindweiss:BAAANQADCgcIBwABNQAFFAUICQAGAPQXAA==.Blinkies:BAAANQAECggIEwAAAA==.',
Bo='Bontao:BAACNQAFFIEIAAIMAAUKChbJBACxAQAMAAUKChbJBACxAQA1AAQKgSUAAgwACQowHh8eAOkCAAwACQowHh8eAOkCAAAA.Bontaopanda:BAAANQADCgcIEwABNQAFFAUICAAMAAoWAA==.Boomies:BAAANQADCgQJBAABNQAECggIEwANAAAAAA==.Borstenne:BAABNQAECoEfAAIOAAgKqSSiDAAsAwAOAAgKqSSiDAAsAwAAAA==.Bosco:BAAANQADCgQIBAAAAA==.',
Br='Bresepls:BAAANQAECgIIBAABNQAECggIIgAPAO4gAA==.Breseshh:BAABNQAECoEiAAIPAAgK7iD7FQDxAgAPAAgK7iD7FQDxAgAAAA==.Brickbeard:BAAANQAECgMIAwAAAA==.Brickbow:BAAANQADCgYIBgAAAA==.Brickette:BAAANQAECgcIBwABNQAFFAUICgAHACkJAA==.Bricklicker:BAAANQAECgMIAwAAAA==.Bricksquad:BAAANQAECgcIDgAAAA==.Brickthrow:BAACNQAFFIEKAAIHAAUKKQkiCQB7AQAHAAUKKQkiCQB7AQA1AAQKgSIAAwcACQoKHPYXAO8CAAcACQoKHPYXAO8CAAoAAQr5D2FAATwAAAAA.',
Bu='Burgerburn:BAAANQAECgEIAgAAAA==.',
By='Bytheway:BAAANQAECgMIAwAAAA==.',
['Bé']='Béstt:BAAANQAECgcIEgAAAA==.',
Ca='Cadilak:BAABNQAECoEhAAMJAAgK4xT/GgANAgAJAAgK4xT/GgANAgAIAAMK8g38cwClAAAAAA==.Caelesti:BAAANQAECgIIAwAAAA==.Camlin:BAAANQADCggIDgAAAA==.',
Ch='Cheapshotjoe:BAAANQADCgEIAQAAAA==.Chelbur:BAAANQAECgIJAwAAAA==.Chowderhead:BAABNQAECoEaAAMQAAkKUxbPBwBzAgAQAAkKUxbPBwBzAgARAAEK9wx6CgExAAAAAA==.',
Ci='Cileb:BAABNQAECoEYAAIGAAgKWSB1OQD3AgAGAAgKWSB1OQD3AgAAAA==.Civik:BAAANQADCgYIBgAAAA==.',
Co='Cocio:BAAANQAECgUIDgABNQAECggIGgASAFgbAA==.Conchsniffer:BAABNQAECoEmAAMKAAkKCB5DKQDoAgAKAAkKCB5DKQDoAgAHAAEKPQFHBQEVAAAAAA==.Conrack:BAAANQADCggJCAAAAA==.Copperit:BAABNQAECoEVAAIEAAcKPyRlFgDLAgAEAAcKPyRlFgDLAgAAAA==.Cornburglar:BAABNQAECoEaAAISAAgKWBv2TwBaAgASAAgKWBv2TwBaAgAAAA==.Corrona:BAEANQADCggJCAABNQAECggJDAANAAAAAA==.',
Cr='Creatlach:BAAANQADCgYIBgABNQAFFAUICQAPAFoRAA==.Crime:BAAANQAECgIIAgABNQAECgkJKQATAN4jAA==.Crunchwrap:BAAANQAECgUICwAAAA==.',
['Câ']='Câlisse:BAABNQAECoEpAAITAAkK3iMAAwCYAwATAAkK3iMAAwCYAwAAAA==.',
Da='Daddiedk:BAABNQAECoEdAAIDAAcKbBokJgAHAgADAAcKbBokJgAHAgAAAA==.Damncats:BAABNQAECoEdAAIUAAcKVQ7EDACdAQAUAAcKVQ7EDACdAQAAAA==.Danielsboone:BAAANQAECgQIBwAAAA==.Darkmare:BAABNQAECoEfAAMVAAgK0xjYEABQAgAVAAgKkBfYEABQAgABAAIK3wqmZgB0AAAAAA==.Darknemesis:BAAANQADCgcIDAABNQADCggICAANAAAAAA==.',
De='Deadhippocow:BAAANQAECgUIDAAAAA==.Dearth:BAEANQAECggJDAAAAA==.Deathbane:BAAANQAECgUICQAAAA==.Deathwavez:BAABNQAECoEMAAIDAAcKMgmqTQD6AAADAAcKMgmqTQD6AAAAAA==.Deckard:BAEANQAECggICAABNQAECggJDAANAAAAAA==.Demayy:BAAANQAECgcIEwAAAA==.Demona:BAAANQAECgQICAAAAA==.Demonix:BAAANQAECgYIDwAAAA==.Derptron:BAAANQAECgYIDgAAAA==.',
Di='Dilutedqt:BAABNQAECoEeAAIGAAkKehtUQQDhAgAGAAkKehtUQQDhAgAAAA==.Dilutedret:BAAANQADCgMIAwABNQAECgkJHgAGAHobAA==.Dinobrass:BAABNQAECoEaAAIMAAcKsA1oegC7AQAMAAcKsA1oegC7AQAAAA==.Dirge:BAAANQAECgYIDwAAAA==.Dirktheshiny:BAABNQAECoEmAAMKAAkKuRvMTwBVAgAKAAgKgRrMTwBVAgAHAAEKzwZN7QA2AAAAAA==.Dirtylöbster:BAABNQAECoEtAAIGAAkKUx8VMAARAwAGAAkKUx8VMAARAwAAAA==.Disabel:BAAANQADCggICAAAAA==.Distracto:BAAANQAECggIDQAAAA==.',
Dj='Djinsurgent:BAAANQAECgQICgAAAA==.',
Dl='Dltdjr:BAAANQAECgQIBgABNQAECgkJHgAGAHobAA==.',
Do='Doobysnacks:BAABNQAECoEWAAIEAAcKFCTTFgDHAgAEAAcKFCTTFgDHAgAAAA==.Doolittle:BAAANQADCggIEwAAAA==.Dorfies:BAAANQADCgcJCAABNQAECggIEwANAAAAAA==.Dorns:BAAANQADCgEIAQAAAA==.',
Dr='Dralock:BAAANQAECgQIBAABNQADCgYIBgANAAAAAA==.Dreamyeti:BAAANQADCgEIAQAAAA==.Dreats:BAAANQADCgEJAQAAAA==.Drewmee:BAAANQAECgYIBgAAAA==.Droovani:BAAANQAECgUICgABNQAECgYIBgANAAAAAA==.Drunkenyeti:BAAANQADCgcIEAAAAA==.',
Du='Duckbeak:BAAANQAECgQIBQAAAA==.Duwork:BAAANQAECgcIEQAAAA==.',
['Dæ']='Dæmona:BAABNQAECoEfAAIWAAgK4RTCKQD9AQAWAAgK4RTCKQD9AQAAAA==.',
Eb='Ebk:BAAANQAECgcICgAAAA==.Ebkx:BAAANQAECgEIAQAAAA==.',
El='Eladus:BAAANQAECgYIEQAAAA==.Elesus:BAAANQADCgIJAgABNQAECgkJJQAXAEcdAA==.',
Em='Emblaze:BAAANQADCgUIBQAAAA==.Emrys:BAAANQADCgMIAwAAAA==.',
En='Enhshaman:BAAANQAECgQICAABNQAFFAUIDgACAOEYAA==.',
Fa='Faithpasse:BAAANQAECgUIDAAAAA==.',
Fe='Felondar:BAAANQAECgYIEQAAAA==.Ferarro:BAAANQAECgcIEQAAAA==.',
Fi='Finnadin:BAAANQADCgcIDQAAAA==.Finns:BAAANQAECgQICAAAAA==.Firulais:BAAANQAECgYIDgAAAA==.Fistuu:BAAANQADCgUIBQAAAA==.',
Fl='Flysky:BAACNQAFFIEKAAIYAAUK0BR4BgCiAQAYAAUK0BR4BgCiAQA1AAQKgSIABBgACQqUIj0FAEEDABgACQqUIj0FAEEDABkABArNIIkKAGwBABoABQoWFzEdADwBAAAA.',
Fo='Foxsake:BAAANQADCgQIBAAAAA==.',
Fu='Fumbles:BAAANQAECgEIAQAAAA==.Futurefist:BAAANQADCggICAAAAA==.',
Ga='Garduuk:BAAANQAECgcIEwAAAA==.',
Ge='Gearth:BAABNQAECoEbAAIbAAcK7hzpDQBOAgAbAAcK7hzpDQBOAgAAAA==.',
Gl='Glucose:BAAANQAECgYICgAAAA==.',
Go='Gonah:BAAANQAECgUICgAAAA==.Gotlieb:BAAANQAECgIIAwAAAA==.',
Gr='Gravey:BAABNQAECoEdAAIEAAcKHx0QJwBOAgAEAAcKHx0QJwBOAgAAAA==.Grogger:BAAANQADCgUIBQAAAA==.Grrahtahtah:BAACNQAFFIEOAAICAAUK4RgYBwCSAQACAAUK4RgYBwCSAQA1AAQKgSYAAwIACQrOIrcFAGEDAAIACQrOIrcFAGEDAAwAAQo7E/IJAUwAAAAA.',
Gy='Gymble:BAAANQAECggIAQAAAA==.',
Ha='Hakkim:BAAANQADCggICAAAAA==.Hammerinfred:BAAANQAECgIIAgAAAA==.',
He='Heavyguard:BAAANQABCgIIAgAAAA==.',
Hi='Hidann:BAAANQAECggIBwABNQAECgkJGAARAEARAA==.Himeko:BAAANQAECgEIAgABNQAFFAUICQAGAPQXAA==.Hippayman:BAAANQAECgIIBAAAAA==.Hippysmasher:BAAANQADCggICAABNQAECggIFwALAAQVAA==.',
Ho='Holyhooters:BAAANQAECgUICwAAAA==.Holypablo:BAAANQADCgYJDgABNQAECgkJFgAcAMMVAA==.Honour:BAAANQAECgcIEwAAAA==.',
Hr='Hrathdemon:BAABNQAECoEhAAILAAgK1SL1CgASAwALAAgK1SL1CgASAwAAAA==.Hrathion:BAAANQADCggIDwABNQAECggIIQALANUiAA==.',
Hu='Hupa:BAABNQAECoEiAAIKAAcKcSOKNAC4AgAKAAcKcSOKNAC4AgAAAA==.Hurtsdonut:BAAANQAECgQJCAABNQAECgkJJQAXAEcdAA==.Huulis:BAAANQADCggICAAAAA==.',
Ia='Iamheyo:BAAANQAECgYICAAAAA==.',
Ic='Ickeetard:BAAANQADCgcJBwAAAA==.',
Id='Idiotbreath:BAAANQAECgYIDwAAAA==.',
Ie='Ieatcheeks:BAAANQAECgUIDAAAAA==.Ieyasu:BAEBNQAECoEgAAIIAAkKzhR/JABzAgAIAAkKzhR/JABzAgAAAA==.',
Ig='Ignitus:BAAANQAECgQIBwAAAA==.',
Ik='Ikuchi:BAAANQADCgYJBgAAAA==.',
Il='Illpownyou:BAAANQADCgcIBwABNQAECgQICQANAAAAAA==.',
In='Insulinshot:BAAANQAECgIIAwAAAA==.',
Ir='Ironguard:BAAANQABCgMIAwAAAA==.',
It='Itsmagharszn:BAAANQADCgEIAQAAAA==.',
Ja='Jabronipie:BAAANQADCggIBQAAAA==.',
Je='Jessica:BAAANQAECgQIBgAAAA==.',
Jh='Jhana:BAAANQADCgUICQAAAA==.',
Jj='Jjooaacchhim:BAAANQAECgQIBAAAAA==.',
Jo='Josh:BAAANQADCgYJEQAAAA==.',
Ju='Junglefever:BAAANQADCgYIBgAAAA==.',
Jy='Jyve:BAABNQAECoEdAAIMAAgKsBCPWgASAgAMAAgKsBCPWgASAgAAAA==.',
Ka='Kailin:BAAANQADCgcICAAAAA==.Kakashi:BAAANQADCgYIBgAAAA==.Kamadan:BAAANQAECgMIAwAAAA==.Kamanactali:BAAANQADCggIGQAAAA==.Kamele:BAAANQADCgEJAQAAAA==.Kaneko:BAEANQAECgYICAABNQAECgkJIAAIAM4UAA==.Katalina:BAABNQAECoEeAAMdAAYKpBQ5EQA3AQAWAAYKaRFpPwBSAQAdAAYKBg85EQA3AQAAAA==.',
Ke='Kelstormhoof:BAAANQADCgcIEQABNQADCggICAANAAAAAA==.',
Kh='Kham:BAAANQAFFAEIAQAAAA==.',
Ki='Kirren:BAAANQADCgIIAgAAAA==.',
Kl='Klais:BAAANQADCgQIBQAAAA==.',
Ko='Kokeovrdose:BAAANQABCgQIBAABNQADCgYICgANAAAAAA==.',
La='Lavashiza:BAAANQAECgUICwAAAA==.',
Le='Leadzorz:BAAANQADCggIFwAAAA==.Leedaddydk:BAAANQABCgUICgAAAA==.Leeoflight:BAAANQABCgQIBAAAAA==.Legday:BAAANQAECgMIAwAAAA==.',
Li='Liltotem:BAABNQAECoEcAAMPAAcK8BKSWwCoAQAPAAcK8BKSWwCoAQAeAAQKygfnrQDhAAAAAA==.Linaria:BAAANQADCgUIBQAAAA==.Lizzymonk:BAABNQAECoEhAAIfAAgKiyFrBAD+AgAfAAgKiyFrBAD+AgAAAA==.',
Lo='Lockdownlol:BAAANQAECgUIEwABNQAECgkJHgAGAHobAA==.',
Lu='Luluh:BAAANQAECgQJDQAAAA==.',
Ma='Maddog:BAAANQAECgYIEAAAAA==.Maebell:BAAANQAECgQICAABNQAECgkJHgAGAHobAA==.Mageslayer:BAAANQAECgYIDwAAAA==.Magicpewfred:BAAANQADCgIJAgAAAA==.Magrun:BAAANQADCgUJCQAAAA==.Maiggee:BAAANQADCgcJBwAAAA==.Matt:BAABNQAECoEiAAIMAAgKSSDSJADLAgAMAAgKSSDSJADLAgAAAA==.Mavrik:BAAANQAECgYIEgAAAA==.',
Me='Meatmagic:BAAANQADCgIJAgAAAA==.Megapunk:BAAANQADCgcIGgAAAA==.Melanyie:BAAANQADCgMIAwAAAA==.Melfìce:BAAANQADCgYIBgAAAA==.Meudayr:BAABNQAECoEXAAIFAAgKDRtBCQB0AgAFAAgKDRtBCQB0AgAAAA==.',
Mi='Millarolly:BAAANQADCggIEAAAAA==.Mischifdk:BAAANQADCgIIAgAAAA==.Mischifdots:BAAANQADCgcIDgAAAA==.Mischifgg:BAAANQAECgYIEQAAAA==.Mittenss:BAAANQADCggICQAAAA==.',
Mn='Mndgblnfred:BAAANQADCgEIAQAAAA==.',
Mo='Mojorisinn:BAAANQAECgQIBAAAAA==.Moobear:BAABNQAECoEWAAIFAAcKuiLOBgC7AgAFAAcKuiLOBgC7AgAAAA==.Moogie:BAABNQAECoEnAAIGAAkKIxy1WQChAgAGAAkKIxy1WQChAgAAAA==.Moozlock:BAAANQAECgEIAQAAAA==.Morgiana:BAAANQAECgYIDwAAAA==.Moscovio:BAACNQAFFIEQAAMRAAUK/xNfDABCAQARAAQKGxdfDABCAQAQAAIKKgovDQCbAAA1AAQKgScAAxEACQqUIU4YAPgCABEACQo1IU4YAPgCABAAAQqtGUdhAEkAAAAA.Mosspaws:BAAANQAECgUICAAAAA==.',
Mt='Mtndewyou:BAAANQAECgYIDwAAAA==.',
My='Myrothan:BAAANQAECgIIAgAAAA==.',
Na='Napok:BAAANQAECgIIAwAAAA==.',
Ni='Nihr:BAAANQAECgQIBAAAAA==.Ninkarrak:BAAANQADCggIGQAAAA==.',
Nm='Nme:BAABNQAECoEWAAIGAAcKfQle0ACUAQAGAAcKfQle0ACUAQAAAA==.',
No='Nocturnos:BAAANQAECgUICwAAAA==.Novamancer:BAAANQAECgEIAQAAAA==.',
Nu='Nuph:BAAANQAECgQIBQAAAA==.',
Ny='Nymage:BAAANQAECgcIEgAAAA==.',
Og='Ogdaddy:BAAANQADCggICAAAAA==.',
Ok='Okaerisan:BAAANQADCgMIAwAAAA==.',
Ol='Olord:BAAANQADCgEJAgAAAA==.',
Or='Orack:BAAANQAECgUICwAAAA==.',
Ou='Outlast:BAAANQADCgYIBgAAAA==.',
Ow='Owch:BAAANQABCgIIAgABNQAECggIFwAFAA0bAA==.',
Pa='Panblind:BAACNQAFFIEKAAMLAAUKEhvXAwDUAQALAAUKEhvXAwDUAQAdAAMKkhmXAQD7AAA1AAQKgSIAAwsACQqfIFMOAOMCAAsACQqJHlMOAOMCAB0AAwrlInMRADEBAAAA.Pandington:BAAANQADCgMIAwAAAA==.Parmageddon:BAABNQAECoEiAAIEAAgKehjhLwATAgAEAAgKehjhLwATAgAAAA==.Parmrageiano:BAAANQADCgUIBQABNQAECggIIgAEAHoYAA==.',
Pe='Peanought:BAAANQAECgYIEgAAAA==.Peetfix:BAABNQAECoEeAAMeAAgKPBd9TAD1AQAeAAcKOxh9TAD1AQAPAAQKZRsafgA7AQAAAA==.Pepsipink:BAAANQAECgEIAQAAAA==.',
Ph='Phèdre:BAEANQAFFAEIAQABNQAFFAUIDAAKAOQQAA==.',
Pi='Picklegrip:BAAANQAECgYJDwAAAA==.Pijak:BAAANQADCggIGQAAAA==.',
Pl='Planetina:BAAANQADCgcIBwAAAA==.',
Po='Poah:BAABNQAECoEUAAITAAgKzx8HDgDHAgATAAgKzx8HDgDHAgAAAA==.Portalcombat:BAAANQAECgIIAgAAAA==.',
Pr='Prettynhealz:BAAANQADCgIIAgAAAA==.Pruflas:BAAANQAECgEIAgAAAA==.',
Ps='Psycodk:BAAANQAECgYICAAAAA==.',
Pu='Pumpin:BAAANQAECgMIBAAAAA==.Punkthor:BAAANQAECgQICgAAAA==.Purgemepappy:BAAANQADCgYIDAAAAA==.Putitinme:BAAANQABCgIIAgAAAA==.',
['Pø']='Pø:BAAANQAECgUICwAAAA==.',
Qk='Qkn:BAAANQADCgcIGQAAAA==.',
Ra='Raf:BAAANQAECgcIDAAAAA==.Ratoncita:BAAANQADCgUIBQAAAA==.Rayzee:BAAANQAECgEIAQAAAA==.',
Re='Reisar:BAAANQADCgEIAQAAAA==.Rennera:BAAANQADCgcIEgAAAA==.Revalation:BAAANQAECgYIDgAAAA==.',
Ri='Riachu:BAAANQAECgUIDQAAAA==.Ribeyejoe:BAAANQAECgQIBgAAAA==.',
Ro='Roadblock:BAAANQAECgYIDwAAAA==.Roboorc:BAAANQABCgEJAQAAAA==.Roken:BAAANQADCggICAAAAA==.Rorymcilroy:BAABNQAECoEVAAMPAAcKbRvCOwAoAgAPAAcKbRvCOwAoAgAeAAMK9Q0FxQCnAAAAAA==.',
Sa='Sagan:BAEANQADCgQIBAABNQAECgYIDwANAAAAAA==.Saifrah:BAAANQADCggICQAAAA==.Sandasa:BAAANQAECgMIBAAAAA==.Sanivanth:BAAANQADCgQIBAAAAA==.Saucerdote:BAAANQAECgYIDQAAAA==.Saxon:BAAANQAECgEIAQAAAA==.',
Se='Selenix:BAAANQADCgYIBgAAAA==.Selinfinite:BAAANQAECggIEwAAAA==.Selkie:BAAANQAECgUICQAAAA==.Serenitynow:BAAANQAECgQIBAAAAA==.',
Sg='Sgge:BAAANQADCgYIBgAAAA==.',
Sh='Shadowmaven:BAAANQADCgcIDgAAAA==.Shakakhan:BAAANQAECgUIEwABNQAECgkJHgAGAHobAA==.Shammer:BAEANQADCggIBgABNQAECgkJIgAEAIIbAA==.Shamshielder:BAEBNQAECoEiAAMEAAkKghtqHgCJAgAEAAkKghtqHgCJAgADAAMK4Ae7dQBZAAAAAA==.Sharick:BAAANQADCgYICQAAAA==.Shawdrake:BAAANQADCggIDQABNQAECgcIGwAPAEcSAA==.Shawlee:BAABNQAECoEbAAMPAAcKRxJoYgCPAQAPAAcKRxJoYgCPAQAeAAEKjwR8EQEnAAAAAA==.Shetmage:BAAANQAECgcIEAABNQAFFAUIBwAIAFIMAA==.Shettrah:BAACNQAFFIEHAAIIAAUKUgx3CgBrAQAIAAUKUgx3CgBrAQA1AAQKgSUAAggACQpPGwkaAMkCAAgACQpPGwkaAMkCAAAA.Shottdown:BAAANQADCgUIBQAAAA==.Shwoobs:BAAANQAECgEIAQAAAA==.',
Si='Sigasunanvil:BAAANQAECgQIBAAAAA==.Sijious:BAAANQADCggIHwAAAA==.Silhõuette:BAAANQADCggICAAAAA==.Singularity:BAAANQAECgMIBQABNQAECgkJHgAGAHobAA==.',
Sk='Skanktank:BAAANQAECgcIDQAAAA==.Skyland:BAAANQADCgcIBwABNQAFFAUICgAYANAUAA==.',
Sl='Slinkies:BAAANQADCgYICQABNQAECggIEwANAAAAAA==.Slipknife:BAAANQAECgcIEQAAAA==.',
So='Somi:BAABNQAECoEbAAIHAAgK0B2tIwCrAgAHAAgK0B2tIwCrAgAAAA==.',
St='Stabbystab:BAAANQAECgYIDQABNQADCgEJAgANAAAAAA==.Stankydk:BAAANQAECgcIEgAAAA==.Stankyleg:BAABNQAFFIEGAAMMAAMKEgjQHACEAAACAAIKBAsYFgCHAAAMAAIK/ALQHACEAAAAAA==.Stewie:BAABNQAECoEUAAITAAYK/AhwMQAcAQATAAYK/AhwMQAcAQAAAA==.Stinkbombs:BAAANQAECgEIAQAAAA==.Stinkies:BAAANQAECgUIBgABNQAECggIEwANAAAAAA==.',
Su='Subrogue:BAAANQAECgQICQABNQAFFAUIDgACAOEYAA==.Sunlest:BAAANQADCgcIFQAAAA==.',
Sy='Sylphrena:BAABNQAECoEhAAIcAAgKHBslMQBhAgAcAAgKHBslMQBhAgAAAA==.',
Ta='Tacow:BAAANQAECgUIDAAAAA==.Talethen:BAAANQAECgQICQAAAA==.',
Te='Telaragehoof:BAAANQADCggICAAAAA==.',
Th='Thedrood:BAABNQAECoEeAAIJAAgK4x23DQC9AgAJAAgK4x23DQC9AgAAAA==.Thorfyna:BAAANQADCggICAAAAA==.',
Ti='Tiptronic:BAAANQADCggIEAAAAA==.',
To='Tohk:BAACNQAFFIEHAAIWAAMKaxoBCgAHAQAWAAMKaxoBCgAHAQA1AAQKgSMAAhYACQqPIZkNAAsDABYACQqPIZkNAAsDAAAA.Tollee:BAAANQAECgQIBAAAAA==.Tontiamat:BAAANQAECgcIEwAAAA==.Tontier:BAAANQAECgIIAwABNQAECgcIEwANAAAAAA==.Tormero:BAAANQADCgcIBwAAAA==.Totembeans:BAAANQAECgQIBQAAAA==.Touchyfred:BAAANQADCggIEQAAAA==.Toxicfury:BAAANQABCgUIBAAAAA==.',
Tr='Traash:BAAANQABCgIIAgAAAA==.Treily:BAAANQAECgMICwAAAA==.Tricket:BAAANQAECgQICAAAAA==.Trolloladin:BAAANQADCggJDwAAAA==.Truestorm:BAAANQAECgYIDQAAAA==.',
Tu='Tuchi:BAABNQAECoEZAAIGAAgKkBp2hQA3AgAGAAgKkBp2hQA3AgAAAA==.',
['Tà']='Tàcobelle:BAAANQADCgYIEAAAAA==.',
Va='Vanicton:BAABNQAECoEfAAIPAAgKqyHIDwAeAwAPAAgKqyHIDwAeAwAAAA==.',
Ve='Ve:BAABNQAECoEXAAMPAAgK7Rp3OwApAgAPAAcKLBp3OwApAgAbAAYKbxhUFADMAQAAAA==.Vegh:BAABNQAECoEdAAIWAAcKRR2SHgBdAgAWAAcKRR2SHgBdAgAAAA==.Velaei:BAAANQAECgEJAQAAAA==.Veldcat:BAAANQAECgUICwAAAA==.Velddk:BAAANQADCggICAAAAA==.Veriale:BAAANQADCggIEwAAAA==.Verra:BAAANQAECgUIDAAAAA==.',
Vi='Vitriol:BAAANQAECgMIBAAAAA==.',
Wa='Wampa:BAAANQAECgEIAgAAAA==.Wanderblue:BAAANQAECgMIAwAAAA==.Wangstah:BAAANQAECgUIDAAAAA==.Warshaw:BAAANQABCgEIAQABNQAECgcIGwAPAEcSAA==.Wartogoteam:BAABNQAECoEnAAISAAkKJxhwSQBwAgASAAkKJxhwSQBwAgAAAA==.Waytogoteam:BAAANQADCgMIAwAAAA==.',
We='Weiss:BAACNQAFFIEJAAMGAAUK9BfBFgBgAQAGAAQKjRjBFgBgAQAgAAEKkxX/CgBRAAA1AAQKgSIAAgYACQrZITQhAEEDAAYACQrZITQhAEEDAAAA.',
Wf='Wf:BAABNQAECoEiAAMbAAgKfg4nEAAhAgAbAAgKfg4nEAAhAgAPAAUKyAdZrAC/AAAAAA==.',
Wo='Woog:BAAANQADCgYIBgAAAA==.Worsthunterx:BAAANQAFFAEIAQABNQAFFAUIDQAhAE8jAA==.',
Wy='Wyldspirit:BAAANQAECgQIBwAAAA==.Wyreless:BAAANQAECgUIDAABNQAECggIHAAFADUYAA==.',
Ya='Yaass:BAAANQADCggJCAABNQAECggIIgAbAH4OAA==.Yagrum:BAAANQAECgEJAQAAAA==.Yahikko:BAABNQAECoEYAAIRAAkKQBEUYQDlAQARAAkKQBEUYQDlAQAAAA==.',
Ye='Yem:BAAANQAECgcIDAAAAA==.',
Yo='Yoddaa:BAAANQAECggIDAABNQAECgYIDwANAAAAAA==.',
Ze='Zergen:BAAANQADCgYIBgAAAA==.Zetsu:BAAANQAECggIBwABNQAECgkJGAARAEARAA==.',
Zh='Zhenya:BAABNQAECoEiAAIGAAgKRw0OrwDZAQAGAAgKRw0OrwDZAQAAAA==.',
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
