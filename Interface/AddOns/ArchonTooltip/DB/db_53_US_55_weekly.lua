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

local lookup = {'Rogue-Assassination','Hunter-Marksmanship','DeathKnight-Frost','DeathKnight-Blood','Druid-Guardian','Mage-Frost','Paladin-Holy','Druid-Balance','Druid-Restoration','Paladin-Retribution','DemonHunter-Devourer','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Mage-Arcane','Warrior-Arms','Monk-Windwalker','Warrior-Fury','Rogue-Subtlety','Monk-Mistweaver','Warlock-Affliction','DemonHunter-Havoc','Priest-Discipline','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','Priest-Holy','DemonHunter-Vengeance','Monk-Brewmaster','Paladin-Protection','Priest-Shadow',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abc:BAAANQADCgIIAgAAAA==.',
Ac='Acheniris:BAAANQADCgEIAQAAAA==.',
Ae='Aeviee:BAAANQAECgEIAQAAAA==.',
Ag='Aglain:BAAANQAECgEIAQAAAA==.Agrippa:BAABNQAECoEaAAIBAAkKXww2LQD9AQABAAkKXww2LQD9AQAAAA==.',
Ah='Ahndhrez:BAAANQAECgQIBQAAAA==.',
Ai='Aidric:BAAANQAECgQIBwAAAA==.Airwavez:BAACNQAFFIEHAAICAAQKKRM+DQA+AQACAAQKKRM+DQA+AQA1AAQKgSwAAgIACQrFG0QUAKgCAAIACQrFG0QUAKgCAAAA.',
Ak='Akriel:BAAANQAECgcIEQAAAA==.',
Al='Albrecht:BAAANQAECgEIAQAAAA==.Aldeor:BAAANQAECgIIAgAAAA==.Altra:BAABNQAECoEkAAMDAAkKDhe8IwBGAgADAAkKDhe8IwBGAgAEAAEKEQVCyQAkAAAAAA==.Alumit:BAAANQAECgYJEwAAAA==.',
Am='Amoeta:BAABNQAECoEjAAIFAAgKkRomDABoAgAFAAgKkRomDABoAgAAAA==.',
An='Andor:BAAANQADCgYIDQAAAA==.Angelique:BAAANQAECgUIEAAAAA==.Angry:BAAANQADCgYICgAAAA==.Angryapples:BAAANQAECgQJBwAAAA==.Annihilation:BAAANQADCgUIBQAAAA==.',
Ap='Approved:BAAANQADCgYIBQAAAA==.',
Ar='Arconos:BAAANQADCgYIDAABNQAFFAUIDgAGADMYAA==.',
As='Ashguard:BAAANQADCgUJBQAAAA==.Asomyrh:BAABNQAECoEXAAIHAAcKAg9jagCxAQAHAAcKAg9jagCxAQAAAA==.',
Au='Aurial:BAAANQADCgMIAwAAAA==.Auriala:BAAANQAECgEIAgAAAA==.',
Ba='Babygirl:BAAANQAECgYICgAAAA==.Bananer:BAAANQAECgQICwAAAA==.Banonzarath:BAAANQADCggICAAAAA==.Barrysoetoro:BAAANQADCgcIDAAAAA==.Baulie:BAAANQAECgQIBwAAAA==.',
Be='Beefstick:BAAANQADCggIFgAAAA==.Bekroh:BAABNQAECoEYAAMIAAcKKRd1PwDTAQAIAAcKKRd1PwDTAQAJAAEKbASwawAoAAAAAA==.Bestt:BAAANQAECgQIBAAAAA==.',
Bi='Bigdaddyd:BAAANQAECgYIEQAAAA==.Bigdonk:BAAANQADCggJCAAAAA==.Bigocagler:BAAANQADCggIFgAAAA==.Bioodlion:BAABNQAECoEbAAIKAAcKyg4lpwCZAQAKAAcKyg4lpwCZAQAAAA==.Bipolar:BAAANQAECgYIEgAAAA==.Bippysmasher:BAABNQAECoEXAAILAAgKBBUBIwASAgALAAgKBBUBIwASAgAAAA==.Bishmanistic:BAAANQAECgUIDwAAAA==.',
Bl='Blacblood:BAAANQAECgEIAgAAAA==.Blindweiss:BAAANQADCgcIBwABNQAFFAUIDgAGADMYAA==.Blinkies:BAAANQAECggIEwAAAA==.',
Bo='Bontao:BAACNQAFFIEKAAIMAAUKpxZyBwCtAQAMAAUKpxZyBwCtAQA1AAQKgScAAgwACQowHoErAMoCAAwACQowHoErAMoCAAAA.Bontaopanda:BAAANQAECgEIAQABNQAFFAUICgAMAKcWAA==.Boomies:BAAANQADCgQJBAABNQAECggIEwANAAAAAA==.Borstenne:BAABNQAECoEkAAIOAAkKUCRoCABsAwAOAAkKUCRoCABsAwAAAA==.Bosco:BAAANQADCgQIBAAAAA==.',
Br='Bresepls:BAAANQAECgIIBQABNQAECgkJKAAPAEQeAA==.Breseshh:BAABNQAECoEoAAMPAAkKRB5KEgAeAwAPAAkKRB5KEgAeAwAQAAMK9hfdvADqAAAAAA==.Brickbeard:BAAANQAECgMIBAAAAA==.Brickbow:BAAANQADCgYIBgAAAA==.Brickette:BAAANQAECgcICAABNQAFFAUIDwAHAJMNAA==.Bricklicker:BAAANQAECgMIBAAAAA==.Bricksquad:BAAANQAECgcIDgAAAA==.Brickthrow:BAACNQAFFIEPAAIHAAUKkw0/CwCFAQAHAAUKkw0/CwCFAQA1AAQKgSQAAwcACQpnHD4dAOgCAAcACQpnHD4dAOgCAAoAAQr5DxhrAToAAAAA.',
Bu='Budhistpalm:BAAANQAECgMIAwAAAA==.Burgerburn:BAAANQAECgEIAgAAAA==.',
By='Bytheway:BAAANQAECgYICgAAAA==.',
['Bé']='Béstt:BAABNQAECoEUAAIQAAgKcBkJPABdAgAQAAgKcBkJPABdAgAAAA==.',
Ca='Cadilak:BAABNQAECoEkAAMJAAkKHRkZEwCUAgAJAAkKHRkZEwCUAgAIAAMK8g3PfwCjAAAAAA==.Caelesti:BAAANQAECgMICAAAAA==.Camlin:BAAANQADCggIDgAAAA==.Cassanndra:BAEANQAECggIAQABNQAECggIDQANAAAAAA==.',
Ch='Cheapshotjoe:BAAANQADCgEIAQAAAA==.Chelbur:BAAANQAECgIJBAAAAA==.Chowderhead:BAABNQAECoEdAAMRAAkKUxbrCABiAgARAAkKUxbrCABiAgASAAIKpRRJAwGHAAAAAA==.',
Ci='Cileb:BAABNQAECoEaAAITAAgK6iAKQQD0AgATAAgK6iAKQQD0AgAAAA==.Civik:BAAANQADCgYIBgAAAA==.',
Co='Cocio:BAABNQAECoEXAAIUAAcKzRPgjgDQAQAUAAcKzRPgjgDQAQABNQAECgkJJQAUAB4bAA==.Conchsniffer:BAABNQAECoEwAAMKAAkKqB8WJwAOAwAKAAkKqB8WJwAOAwAHAAEKPQGAHwEVAAAAAA==.Conrack:BAAANQADCggJCAAAAA==.Copperit:BAABNQAECoEVAAIEAAcKPyQcGwC+AgAEAAcKPyQcGwC+AgAAAA==.Cornburglar:BAABNQAECoElAAIUAAkKHhuYRQCgAgAUAAkKHhuYRQCgAgAAAA==.Corrona:BAEANQADCggJCAABNQAECggIDQANAAAAAA==.Cowtaclysmic:BAAANQAECgYIBgAAAA==.',
Cr='Creatlach:BAAANQADCgYIBgABNQAFFAUIDgAPAAoVAA==.Crime:BAAANQAECgYICQABNQAECgkJMQAVACYkAA==.Crunchwrap:BAAANQAECgUIEAAAAA==.',
Cu='Curseus:BAAANQADCgUIBQAAAA==.',
['Câ']='Câlisse:BAABNQAECoExAAIVAAkKJiSMAwCTAwAVAAkKJiSMAwCTAwAAAA==.',
Da='Daddiedk:BAABNQAECoEdAAIDAAcKbBqgLwDvAQADAAcKbBqgLwDvAQAAAA==.Damncats:BAABNQAECoEjAAIWAAcKnQ6+DgCdAQAWAAcKnQ6+DgCdAQAAAA==.Dandinn:BAAANQADCggICAAAAA==.Danielsboone:BAAANQAECgQICwAAAA==.Darkmare:BAABNQAECoEjAAMXAAkK7xeiDgB9AgAXAAkK0BaiDgB9AgABAAIK3wpxeQBxAAAAAA==.Darknemesis:BAAANQADCgcIDAABNQADCggICAANAAAAAA==.',
De='Deadhippocow:BAABNQAECoEUAAIJAAcKvBzhGgA3AgAJAAcKvBzhGgA3AgAAAA==.Dearth:BAEANQAECggIDQAAAA==.Deathbane:BAAANQAECgcIEwAAAA==.Deathwavez:BAABNQAECoEMAAIDAAcKMglCWQD1AAADAAcKMglCWQD1AAAAAA==.Deckard:BAEANQAECggICAABNQAECggIDQANAAAAAA==.Demayy:BAABNQAECoEbAAIYAAgK7g2fHACOAQAYAAgK7g2fHACOAQAAAA==.Demona:BAAANQAECgQICQAAAA==.Demonix:BAABNQAECoEaAAMZAAcKTx47CwCQAQASAAYKah57XgAaAgAZAAUK3Bo7CwCQAQAAAA==.Derptron:BAABNQAECoEVAAIGAAcKKRbECwDNAQAGAAcKKRbECwDNAQAAAA==.',
Di='Dilutedqt:BAABNQAECoEnAAITAAkKqx4SMwAYAwATAAkKqx4SMwAYAwAAAA==.Dilutedret:BAAANQAECgQIBgABNQAECgkJJwATAKseAA==.Dinobrass:BAABNQAECoEiAAIMAAgKzxbwTgBaAgAMAAgKzxbwTgBaAgAAAA==.Dirge:BAABNQAECoEbAAIOAAgKKBA5SwDBAQAOAAgKKBA5SwDBAQAAAA==.Dirktheshiny:BAABNQAECoEpAAMKAAkKmRnJUwBxAgAKAAkKmRnJUwBxAgAHAAIKNggL7ABwAAAAAA==.Dirtylöbster:BAABNQAECoEuAAITAAkK2x+YOwACAwATAAkK2x+YOwACAwAAAA==.Disabel:BAAANQADCggICAAAAA==.Distracto:BAAANQAECggIEAAAAA==.',
Dj='Djinsurgent:BAAANQAECgYIEgAAAA==.',
Dl='Dltdjr:BAAANQAECgQICwABNQAECgkJJwATAKseAA==.',
Do='Doobysnacks:BAABNQAECoEWAAIEAAcKFCTQGwC4AgAEAAcKFCTQGwC4AgAAAA==.Doolittle:BAAANQAECgIIAgAAAA==.Dorfies:BAAANQADCgcJCAABNQAECggIEwANAAAAAA==.Dorns:BAAANQADCgEIAQAAAA==.',
Dr='Dralock:BAAANQAECgQIBQABNQADCgYIBgANAAAAAA==.Dreamyeti:BAAANQADCgEIAQAAAA==.Dreats:BAAANQADCgUIBgAAAA==.Drewmee:BAAANQAECgcIDgAAAA==.Droovani:BAAANQAECgUICwABNQAECgcIDgANAAAAAA==.Drunkenyeti:BAAANQAECgEIAQAAAA==.',
Du='Duckbeak:BAAANQAECgQICQAAAA==.Duwork:BAABNQAECoEdAAIIAAkKcBrxHgC3AgAIAAkKcBrxHgC3AgAAAA==.',
['Dæ']='Dæmona:BAABNQAECoEnAAIaAAkKcxW1IgBfAgAaAAkKcxW1IgBfAgAAAA==.',
Eb='Ebk:BAAANQAECgcICwAAAA==.Ebkx:BAAANQAECgEIBAAAAA==.',
El='Eladus:BAAANQAECgYIEQAAAA==.Elesus:BAAANQAECgEIAQABNQAECgkJKAAbAEcdAA==.',
Em='Emblaze:BAAANQADCgUIBQAAAA==.Emrys:BAAANQADCgYIBgAAAA==.',
En='Enhshaman:BAAANQAECgQICAABNQAFFAYIFAACAMQYAA==.',
Ev='Evilinne:BAAANQADCgYIBgAAAA==.',
Fa='Faithpasse:BAABNQAECoEVAAIYAAYKrAoOKAAIAQAYAAYKrAoOKAAIAQAAAA==.',
Fe='Felondar:BAABNQAECoEZAAIaAAcKoAoSRABrAQAaAAcKoAoSRABrAQAAAA==.Ferarro:BAAANQAECgcIEwAAAA==.',
Fi='Finnadin:BAAANQADCgcIDQAAAA==.Finns:BAAANQAECgYIDgAAAA==.Firulais:BAABNQAECoEYAAIMAAcKqxCefQDjAQAMAAcKqxCefQDjAQAAAA==.Fistuu:BAAANQAECgEIAQAAAA==.',
Fl='Flysky:BAACNQAFFIEPAAIcAAUK5xR9CACLAQAcAAUK5xR9CACLAQA1AAQKgSQABBwACQqUIlwGADYDABwACQqUIlwGADYDAB0ABArNIJEMAGIBAB4ABQoWF3MgADIBAAAA.',
Fo='Foxsake:BAAANQADCgQIBAAAAA==.',
Fr='Frostwyrm:BAAANQADCgYIBgAAAA==.',
Fu='Fumbles:BAAANQAECgEIAQAAAA==.Futurefist:BAAANQADCggICAAAAA==.',
Ga='Garduuk:BAABNQAECoEfAAMJAAgK+B5MDgDQAgAJAAgK+B5MDgDQAgAIAAEKbSL3jwBhAAAAAA==.',
Ge='Gearth:BAABNQAECoEbAAIfAAcK7hwLEQA6AgAfAAcK7hwLEQA6AgAAAA==.Ger:BAAANQADCgYIDAABNQAECggIHgATAKAPAA==.',
Gl='Glucose:BAAANQAECgcIEAAAAA==.',
Go='Gonah:BAAANQAECgUIDgAAAA==.Gotlieb:BAAANQAECgMICAAAAA==.',
Gr='Gravey:BAABNQAECoEdAAIEAAcKHx0eLgBAAgAEAAcKHx0eLgBAAgAAAA==.Grogger:BAAANQADCgUIBQAAAA==.Grrahtahtah:BAACNQAFFIEUAAICAAYKxBjMBAD1AQACAAYKxBjMBAD1AQA1AAQKgSoAAwIACQrOIrYHAEkDAAIACQrOIrYHAEkDAAwAAQo7E+0qAUoAAAAA.',
Gy='Gymble:BAAANQAECggIAQAAAA==.',
Ha='Hakkim:BAAANQADCggICAAAAA==.Hammerinfred:BAAANQAECgIIAgAAAA==.',
He='Heavyguard:BAAANQABCgIIAgAAAA==.',
Hi='Hidann:BAAANQAECggIBwABNQAECgkJGgASALgSAA==.Himeko:BAAANQAECgMIBgABNQAFFAUIDgAGADMYAA==.Hippayman:BAAANQAECgMIBgAAAA==.Hippysmasher:BAAANQADCggICAABNQAECggIFwALAAQVAA==.',
Ho='Holyhooters:BAABNQAECoEXAAIKAAkKHhYjVwBnAgAKAAkKHhYjVwBnAgAAAA==.Holypablo:BAAANQAECgQIBAABNQAECgkJGQAgAMMVAA==.Honour:BAABNQAECoEfAAIKAAgK9xraTwB9AgAKAAgK9xraTwB9AgAAAA==.',
Hr='Hrathdemon:BAABNQAECoEoAAILAAkK9h/NCAA/AwALAAkK9h/NCAA/AwAAAA==.Hrathion:BAAANQAECgYIBwABNQAECgkJKAALAPYfAA==.',
Hu='Hupa:BAABNQAECoEiAAIKAAcKcSNlRgCcAgAKAAcKcSNlRgCcAgAAAA==.Hurtsdonut:BAAANQAECgQJCAABNQAECgkJKAAbAEcdAA==.Huulis:BAAANQADCggICAAAAA==.',
Ia='Iamheyo:BAAANQAECgYIDgAAAA==.',
Ic='Ickeetard:BAAANQADCgcJBwAAAA==.',
Id='Idiotbreath:BAAANQAECgYIEAAAAA==.',
Ie='Ieatcheeks:BAAANQAECgUIDwAAAA==.Ieyasu:BAEBNQAECoEoAAIIAAkKFRdYJACOAgAIAAkKFRdYJACOAgAAAA==.',
Ig='Ignitus:BAAANQAECgQIDQAAAA==.',
Ik='Ikuchi:BAAANQADCgYJBgAAAA==.',
Il='Illidornsina:BAAANQADCggICAABNQADCgEIAQANAAAAAA==.Illpownyou:BAAANQADCgcIBwABNQAECgYIEQANAAAAAA==.',
In='Indigò:BAAANQAECgIIAgAAAA==.Insulinshot:BAAANQAECgIIBAAAAA==.',
Ir='Ironguard:BAAANQABCgMIAwAAAA==.',
It='Itsmagharszn:BAAANQADCgEIAQAAAA==.',
Ja='Jabronipie:BAAANQADCggIBQAAAA==.',
Je='Jessica:BAAANQAECgQICgAAAA==.',
Jh='Jhana:BAAANQAECgEIAQAAAA==.',
Jj='Jjooaacchhim:BAAANQAECgQIBgAAAA==.',
Jo='Josh:BAAANQAECgIIAgAAAA==.',
Ju='Junglefever:BAAANQADCgYIBgAAAA==.',
Jy='Jyve:BAABNQAECoEkAAIMAAgKmBGiZgAcAgAMAAgKmBGiZgAcAgAAAA==.',
Ka='Kailin:BAAANQAECgIIAgAAAA==.Kailoon:BAAANQADCggICAAAAA==.Kakashi:BAAANQADCgYIDAAAAA==.Kalda:BAAANQAECgIIAgAAAA==.Kamadan:BAAANQAECgMIAwAAAA==.Kamanactali:BAAANQADCggIGQAAAA==.Kamele:BAAANQADCgEJAQAAAA==.Kaneko:BAEANQAECgYIDwABNQAECgkJKAAIABUXAA==.Katalina:BAABNQAECoElAAMhAAcKfRYaDADYAQAhAAcKbRYaDADYAQAaAAYKaRHySQBEAQAAAA==.',
Ke='Kelstormhoof:BAAANQADCgcIEQABNQADCggICAANAAAAAA==.',
Kh='Kham:BAABNQAECoEVAAIWAAkKtRt5BADPAgAWAAkKtRt5BADPAgAAAA==.',
Ki='Kirren:BAAANQADCgIIAgAAAA==.',
Kl='Klais:BAAANQADCgQIBQAAAA==.',
Ko='Kokeovrdose:BAAANQABCgQIBAABNQADCgYICgANAAAAAA==.Konet:BAAANQADCgMIAwAAAA==.',
La='Lavashiza:BAAANQAECgYIEgAAAA==.',
Le='Leadzorz:BAAANQAECgIIAgAAAA==.Leedaddydk:BAAANQAECgEIAQAAAA==.Leeoflight:BAAANQABCgQIBQAAAA==.Legday:BAAANQAECgUIBQAAAA==.',
Li='Liltotem:BAABNQAECoEkAAMPAAgKBxFKYQC7AQAPAAgKBxFKYQC7AQAQAAQKygfRxQDYAAAAAA==.Linaria:BAAANQADCgUIBQAAAA==.Lizzydk:BAAANQAECgMIAwAAAA==.Lizzymonk:BAABNQAECoEjAAIiAAkKuyBpAwBEAwAiAAkKuyBpAwBEAwAAAA==.',
Lo='Lockdownlol:BAABNQAECoEeAAMMAAcKoSA9WwA5AgAMAAYKSCM9WwA5AgACAAYKcBpHKgDWAQABNQAECgkJJwATAKseAA==.',
Lu='Luluh:BAAANQAECgQIDwAAAA==.',
Ma='Maddog:BAABNQAECoEYAAIRAAcKOQwfHgB1AQARAAcKOQwfHgB1AQAAAA==.Maebell:BAAANQAECgYIDwABNQAECgkJJwATAKseAA==.Mageslayer:BAABNQAECoEaAAMXAAcKWxgvFwAVAgAXAAcKWxgvFwAVAgABAAEK5QlzhgA8AAAAAA==.Magicpewfred:BAAANQADCgQIBAAAAA==.Magrun:BAAANQADCgUJCQAAAA==.Maiggee:BAAANQAECgEIAQAAAA==.Matt:BAABNQAECoEoAAIMAAkK0SCOEgBAAwAMAAkK0SCOEgBAAwAAAA==.Mavrik:BAABNQAECoEeAAMUAAgKGQ49kwDEAQAUAAgKZA09kwDEAQAWAAQK2AykGwDJAAAAAA==.',
Me='Meatmagic:BAAANQADCgIIAgAAAA==.Megapunk:BAAANQADCggIHwAAAA==.Melanyie:BAAANQADCgMIAwAAAA==.Melfìce:BAAANQADCgYIBgAAAA==.Meudayr:BAABNQAECoEZAAIFAAgKfxupCwByAgAFAAgKfxupCwByAgAAAA==.',
Mi='Millarolly:BAAANQADCggIEAAAAA==.Mischifbomb:BAAANQADCgIIAgAAAA==.Mischifdk:BAAANQAECgEIAQAAAA==.Mischifdots:BAAANQAECgEIAgAAAA==.Mischifgg:BAABNQAECoEYAAIgAAcKLBbgYwDBAQAgAAcKLBbgYwDBAQAAAA==.Mischïf:BAAANQADCgYIBwAAAA==.Mittenss:BAAANQADCggICQAAAA==.',
Mn='Mndgblnfred:BAAANQADCgEIAQAAAA==.',
Mo='Mojorisinn:BAAANQAECgQIBAAAAA==.Moobear:BAABNQAECoEiAAIFAAgKQCMbBQAmAwAFAAgKQCMbBQAmAwAAAA==.Moogie:BAABNQAECoEnAAITAAkKIxzfagCUAgATAAkKIxzfagCUAgAAAA==.Moozlock:BAAANQAECgEIAQAAAA==.Morgiana:BAAANQAECgYIEgABNQAECggIAgANAAAAAA==.Moscovio:BAACNQAFFIEWAAMSAAYKNxUKCQCsAQASAAUKEhcKCQCsAQARAAIKXAw0DgCZAAA1AAQKgSoAAxIACQqUIVIhAOgCABIACQo1IVIhAOgCABEAAQqtGQJnAEcAAAAA.Mosspaws:BAAANQAECgUICAAAAA==.',
Mt='Mtndewyou:BAABNQAECoEZAAIjAAYKVxY/JgCAAQAjAAYKVxY/JgCAAQAAAA==.',
My='Myrothan:BAAANQAECgQICAAAAA==.',
Na='Napok:BAAANQAECgMIBgAAAA==.',
Ni='Nihr:BAAANQAECgUIBwAAAA==.Ninkarrak:BAAANQAECgIIAgAAAA==.',
Nm='Nme:BAABNQAECoEdAAITAAgK5AnByQDNAQATAAgK5AnByQDNAQAAAA==.',
No='Nocturnos:BAAANQAECgUIDgAAAA==.Nonfiction:BAAANQAECgUIBQABNQAECgkJKQAKAJkZAA==.Novamancer:BAAANQAECgEIAgAAAA==.',
Nu='Nuph:BAAANQAECgQIBwAAAA==.',
Ny='Nymage:BAABNQAECoEaAAIGAAgKWhNJCQAPAgAGAAgKWhNJCQAPAgAAAA==.',
Ok='Okaerisan:BAAANQADCgMIAwAAAA==.',
Ol='Olord:BAAANQADCgEIAgAAAA==.',
Or='Orack:BAABNQAECoEVAAIJAAcKgRi6HwACAgAJAAcKgRi6HwACAgAAAA==.',
Ou='Outlast:BAAANQADCgYIBgAAAA==.',
Ow='Owch:BAAANQABCgIIAgABNQAECggIGQAFAH8bAA==.',
Pa='Panblind:BAACNQAFFIEPAAMLAAUK8hzPBADPAQALAAUK8hzPBADPAQAhAAMKkhlBAgDvAAA1AAQKgSQAAwsACQqfIFEPAOkCAAsACQobH1EPAOkCACEAAwrlIgsVACkBAAAA.Pandington:BAAANQADCgQIBgAAAA==.Parmageddon:BAABNQAECoEkAAIEAAkKzhkaKABkAgAEAAkKzhkaKABkAgAAAA==.Parmrageiano:BAAANQAECgQIBAABNQAECgkJJAAEAM4ZAA==.',
Pe='Peanought:BAABNQAECoEaAAQDAAcK6wmeSwBAAQADAAcKNgieSwBAAQAEAAUKzAgafwDXAAAOAAMKWAYPqgB5AAAAAA==.Peetfix:BAABNQAECoEeAAMQAAgKPBfkWwDgAQAQAAcKOxjkWwDgAQAPAAQKZRuJjgA2AQAAAA==.Pepsipink:BAAANQAECgEIAQAAAA==.',
Ph='Phelon:BAAANQAECgYIBgABNQAFFAYIEwAkAJgbAA==.Phèdre:BAEANQAFFAEIAQABNQAFFAUIEAAKAKQSAA==.',
Pi='Picklegrip:BAABNQAECoEZAAIUAAcKvhBGngCmAQAUAAcKvhBGngCmAQAAAA==.Pijak:BAAANQAECgIIAgAAAA==.',
Pl='Planetina:BAAANQADCgcIBwAAAA==.',
Po='Poah:BAABNQAECoEUAAIVAAgKzx/UEQCwAgAVAAgKzx/UEQCwAgAAAA==.Portalcombat:BAAANQAECgIIAgAAAA==.',
Pr='Prettynhealz:BAAANQADCgIIAgAAAA==.Pruflas:BAAANQAECgEIBAAAAA==.',
Ps='Psycodk:BAAANQAECgYICQAAAA==.',
Pu='Pumpin:BAAANQAECgMIBAAAAA==.Punkthor:BAAANQAECgYIEgAAAA==.Purgemepappy:BAAANQADCgYIDAAAAA==.Putitinme:BAAANQAECgEIAQAAAA==.',
['Pø']='Pø:BAAANQAECgYIEgAAAA==.',
Qk='Qkn:BAAANQADCgcIGQAAAA==.',
Ra='Raf:BAABNQAECoEWAAMQAAkK0SHzCgCEAwAQAAkK0SHzCgCEAwAPAAIKixUQ4gB4AAAAAA==.Ragnor:BAAANQAECgIIAgAAAA==.Ratoncita:BAAANQADCgUIBQAAAA==.Rayzee:BAAANQAECgEIAgAAAA==.',
Re='Reisar:BAAANQADCgMIAwAAAA==.Rennera:BAAANQADCgcIEgAAAA==.Revalation:BAABNQAECoEUAAMJAAcKJhv5GwAqAgAJAAcKJhv5GwAqAgAIAAEKkw0cpwAoAAAAAA==.',
Ri='Riachu:BAAANQAECgUIDwAAAA==.Ribeyejoe:BAAANQAECgQIBgAAAA==.',
Ro='Roadblock:BAAANQAECgcIEQAAAA==.Roboorc:BAAANQAECgEIAwAAAA==.Roken:BAAANQADCggICAAAAA==.Rorymcilroy:BAABNQAECoEVAAMPAAcKbRvyRgAbAgAPAAcKbRvyRgAbAgAQAAMK9Q2b3QCiAAAAAA==.',
Sa='Sacrament:BAAANQAECgQIBAABNQAECgkJMQAVACYkAA==.Sagan:BAEANQADCgQIBAABNQAECggIFAAgAJMeAA==.Saifrah:BAAANQADCggICQAAAA==.Sandasa:BAAANQAECgMIBQAAAA==.Sanivanth:BAAANQADCgQIBAAAAA==.Saragos:BAAANQAECgEIAQABNQAFFAUIDgAGADMYAA==.Saucerdote:BAAANQAECgcIEQAAAA==.Saxon:BAAANQAECgEIAgAAAA==.',
Se='Selenix:BAAANQADCgYIBgAAAA==.Selinfinite:BAABNQAECoEWAAIaAAkKph6eGgCiAgAaAAkKph6eGgCiAgAAAA==.Selkie:BAAANQAECgUIDgAAAA==.Serenitynow:BAAANQAECgQIBAAAAA==.',
Sg='Sgge:BAAANQADCgYIBgAAAA==.',
Sh='Shadowmaven:BAAANQADCgcIDgAAAA==.Shakakhan:BAABNQAECoEaAAIQAAYKLCHnQQBDAgAQAAYKLCHnQQBDAgABNQAECgkJJwATAKseAA==.Shammer:BAEANQADCggIBgABNQAECgkJIgAEAIMbAA==.Shamshielder:BAEBNQAECoEiAAMEAAkKgxtHJQB2AgAEAAkKgxtHJQB2AgADAAMK4AfxgwBaAAAAAA==.Sharick:BAAANQAECgIIAgAAAA==.Shawdrake:BAAANQAECgUIBQABNQAECggIJAAPAPESAA==.Shawlee:BAABNQAECoEkAAMPAAgK8RIuWwDQAQAPAAgK8RIuWwDQAQAQAAEKjwQVLwElAAAAAA==.Shetmage:BAABNQAECoEbAAITAAgKPRG0owAaAgATAAgKPRG0owAaAgABNQAFFAUIDAAIAO0QAA==.Shettrah:BAACNQAFFIEMAAIIAAUK7RA7DAB4AQAIAAUK7RA7DAB4AQA1AAQKgScAAggACQpqHBMcAM0CAAgACQpqHBMcAM0CAAAA.Shottdown:BAAANQADCgUIBQAAAA==.Shwoobs:BAAANQAECgEIAwAAAA==.',
Si='Sigasunanvil:BAAANQAECgQIBQAAAA==.Sijious:BAAANQADCggIHwAAAA==.Silhõuette:BAAANQADCggICAAAAA==.Singularity:BAAANQAECgQIDgABNQAECgkJJwATAKseAA==.',
Sk='Skanktank:BAABNQAECoEVAAIUAAgKuRpLRQChAgAUAAgKuRpLRQChAgAAAA==.Skora:BAAANQAECggIAgAAAA==.Skyland:BAAANQADCgcIBwABNQAFFAUIDwAcAOcUAA==.',
Sl='Slinkies:BAAANQADCgYICQABNQAECggIEwANAAAAAA==.Slipknife:BAAANQAECgcIEwAAAA==.',
So='Somi:BAABNQAECoEbAAIHAAgK0B0zKwChAgAHAAgK0B0zKwChAgAAAA==.',
St='Stabbystab:BAAANQAECgYIDwABNQADCgEIAgANAAAAAA==.Stankydk:BAABNQAECoEUAAIOAAgK2xUVTgCzAQAOAAgK2xUVTgCzAQAAAA==.Stankyleg:BAABNQAFFIEJAAMMAAQKOQnhFgDLAAAMAAMKoQXhFgDLAAACAAIKywwpGQCJAAAAAA==.Stewie:BAABNQAECoEVAAIVAAcKGwmTNAA6AQAVAAcKGwmTNAA6AQAAAA==.Stinkbombs:BAAANQAECgMIBQAAAA==.Stinkies:BAAANQAECgUIBgABNQAECggIEwANAAAAAA==.',
Su='Subrogue:BAAANQAECgQICQABNQAFFAYIFAACAMQYAA==.Sunlest:BAAANQADCgcIGgAAAA==.',
Sw='Swaayshooter:BAAANQAECgUIBQABNQAECgkJKwABACwgAA==.',
Sy='Sylphrena:BAABNQAECoEjAAIgAAkKmxmvKwCbAgAgAAkKmxmvKwCbAgAAAA==.Sylvanniia:BAAANQAECgMIAQABNQAFFAcIFQAdANcWAA==.Sylvas:BAAANQAECgEIAQAAAA==.',
Ta='Tacow:BAAANQAECgUIDQAAAA==.Talethen:BAAANQAECgYIEQAAAA==.',
Te='Telaragehoof:BAAANQADCggICAAAAA==.',
Th='Thedrood:BAABNQAECoEmAAIJAAgKpx54EAC0AgAJAAgKpx54EAC0AgAAAA==.Thorfyna:BAAANQADCggICAAAAA==.',
Ti='Tiptronic:BAAANQADCggIFgAAAA==.',
To='Tohk:BAACNQAFFIEKAAIaAAQKoBgKCgBNAQAaAAQKoBgKCgBNAQA1AAQKgSUAAhoACQpxIuoPAAkDABoACQpxIuoPAAkDAAAA.Tollee:BAAANQAECgQIBAAAAA==.Tontiamat:BAABNQAECoEfAAIeAAgKFxHmEwDwAQAeAAgKFxHmEwDwAQAAAA==.Tontier:BAAANQAECgQICQABNQAECggIHwAeABcRAA==.Tormero:BAAANQAECgEIAQAAAA==.Totembeans:BAAANQAECgQIBwAAAA==.Touchyfred:BAAANQADCggIEQAAAA==.Toxicfury:BAAANQABCgUIBAAAAA==.',
Tr='Traash:BAAANQABCgIIAgAAAA==.Treily:BAAANQAECgMIDQAAAA==.Tricket:BAAANQAECgQICgAAAA==.Trolloladin:BAAANQADCggJDwAAAA==.Truestorm:BAABNQAECoEYAAIKAAgKOwg7ugBvAQAKAAgKOwg7ugBvAQAAAA==.',
Tu='Tuchi:BAABNQAECoEZAAITAAgKkBrGnAApAgATAAgKkBrGnAApAgAAAA==.Turak:BAAANQAECgEIAgAAAA==.',
['Tà']='Tàcobelle:BAAANQAECgQIBAAAAA==.',
Va='Vanicton:BAABNQAECoEfAAIPAAgKqyERFQALAwAPAAgKqyERFQALAwAAAA==.',
Ve='Ve:BAABNQAECoEZAAMPAAgKbBzpQwAmAgAPAAcK4RvpQwAmAgAfAAYKbxiiFwDAAQAAAA==.Vegh:BAABNQAECoEiAAIaAAgKlxzjHACOAgAaAAgKlxzjHACOAgAAAA==.Velaei:BAAANQAECgEJAQAAAA==.Veldcat:BAAANQAECgYIDAAAAA==.Velddk:BAAANQADCggICAAAAA==.Velerai:BAAANQAECgEIAwAAAA==.Veriale:BAAANQAECgIIAgAAAA==.Verra:BAABNQAECoETAAIKAAYKOxBMxQBYAQAKAAYKOxBMxQBYAQAAAA==.',
Vi='Vitriol:BAAANQAECgMIBQAAAA==.',
Wa='Wampa:BAAANQAECgEIAgAAAA==.Wanderblue:BAAANQAECgMIAwAAAA==.Wangstah:BAABNQAECoEXAAIMAAkKhxMDXgAyAgAMAAkKhxMDXgAyAgAAAA==.Warshaw:BAAANQABCgEIAQABNQAECggIJAAPAPESAA==.Wartogoteam:BAABNQAECoEvAAIUAAkK7RpvPgC3AgAUAAkK7RpvPgC3AgAAAA==.Waytogoteam:BAAANQADCgMIAwAAAA==.',
We='Weiss:BAACNQAFFIEOAAMGAAUKMxgzBQCnAAATAAQK2xghHQBfAQAGAAIKehkzBQCnAAA1AAQKgSMAAhMACQpLIqAnADkDABMACQpLIqAnADkDAAAA.',
Wf='Wf:BAABNQAECoEpAAMfAAgKiQ7uEgAWAgAfAAgKiQ7uEgAWAgAPAAYKdwfZrgDkAAAAAA==.',
Wo='Woog:BAAANQADCgYIBgAAAA==.Worsthunterx:BAAANQAFFAEIAQABNQAFFAUIDQAkAE8jAA==.',
Wy='Wyldspirit:BAAANQAECgQICwAAAA==.Wyreless:BAAANQAECgUIEgABNQAECggIIwAFAJEaAA==.',
Ya='Yaass:BAAANQADCggJCAABNQAECggIKQAfAIkOAA==.Yagrum:BAAANQAECgEJAQAAAA==.Yahikko:BAABNQAECoEaAAISAAkKuBITYgAQAgASAAkKuBITYgAQAgAAAA==.',
Ye='Yem:BAAANQAECgcIDgAAAA==.',
Yo='Yoddaa:BAABNQAECoEVAAMbAAkKdhc+DABgAQAgAAgKiRCxUAAHAgAbAAQKhR4+DABgAQABNQAECgcIGgAZAE8eAA==.',
Ze='Zergen:BAAANQADCgYIBgAAAA==.Zetsu:BAAANQAECggIDQABNQAECgkJGgASALgSAA==.',
Zh='Zhenya:BAABNQAECoEkAAITAAkKvw12pwASAgATAAkKvw12pwASAgAAAA==.',
Zu='Zuga:BAAANQAECgQIBwAAAA==.',
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
