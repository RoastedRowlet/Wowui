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

local lookup = {'Priest-Shadow','Monk-Mistweaver','Monk-Windwalker','Unknown-Unknown','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Paladin-Retribution','Mage-Frost','Warrior-Arms','Warrior-Fury','Druid-Restoration','Druid-Balance','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Holy','Druid-Feral','Paladin-Protection','Evoker-Devastation','DeathKnight-Blood','DemonHunter-Havoc','DeathKnight-Unholy','Priest-Holy','Evoker-Augmentation','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Druid-Guardian','DemonHunter-Devourer','DeathKnight-Frost','Mage-Fire','DemonHunter-Vengeance','Warlock-Destruction',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aamion:BAABNQAECn8bAAIBAAUKPwnyTADhAAABAAUKPwnyTADhAAAAAA==.',
Ab='Abo:BAABNQAECn8UAAMCAAkKlADvLwA1AAACAAkKlADvLwA1AAADAAEKxwAMggAEAAAAAA==.',
Ae='Aeonfire:BAAANQAECgEIAQABNQAECggICwAEAAAAAA==.',
Ak='Akame:BAAANQAFFAMIAgAAAA==.',
Al='Alykard:BAABNQAECn8eAAIFAAoK+QX4+gCXAQAFAAoK+QX4+gCXAQAAAA==.',
Am='Amateur:BAABNQAECn8rAAMGAAoKzhi8CgDXAQAGAAoKlxi8CgDXAQAHAAEKfQpwnQAwAAAAAA==.Amazing:BAAANQAECgYIBgABNQAECgoKKwAGAM4YAA==.',
An='Andronicas:BAABNQAECn8WAAIIAAkKGgoA4QBZAQAIAAkKGgoA4QBZAQAAAA==.Aneira:BAABNQAECn80AAIJAAoKjg/pCgAXAgAJAAoKjg/pCgAXAgAAAA==.',
As='Asaki:BAAANQADCggICAAAAA==.Aspect:BAAANQAECgQIBAABNQAECggICwAEAAAAAA==.',
Av='Avi:BAAANQAECgYIEgABNQAECgoKZgAKACEaAA==.',
Ba='Baesuzy:BAABNQAECn8jAAIFAAgKsQ1zcwBdAQAFAAgKsQ1zcwBdAQAAAA==.Baragas:BAAANQAECgUIEQAAAA==.',
Be='Belle:BAAANQADCgcICAAAAA==.Benkei:BAABNQAECn8YAAILAAkK9BuJBQD7AQALAAkK9BuJBQD7AQAAAA==.Berzerker:BAAANQABCgYICgAAAA==.',
Bg='Bgc:BAAANQAECgEIAgAAAA==.',
Bl='Blackds:BAAANQABCgQIBAAAAA==.Blain:BAAANQAECggIEwAAAA==.',
Bo='Book:BAAANQAECgEIAQABNQAECgoKGQACAOkOAA==.Bosammana:BAAANQADCgMJAwAAAA==.',
Bu='Bubblôseven:BAAANQAECgcICAAAAA==.Budin:BAAANQADCgIIAgAAAA==.',
Ca='Cannibal:BAABNQAECn8gAAIMAAkKMh2fDQBVAgAMAAkKMh2fDQBVAgAAAA==.Capri:BAABNQAECn8pAAINAAgKjAriVwB2AQANAAgKjAriVwB2AQAAAA==.Casiopia:BAAANQADCgQIBQAAAA==.',
Ch='Choomoo:BAABNQAECn8lAAIMAAoKdBwnEQDKAgAMAAoKdBwnEQDKAgABNQAFFAQIBwACAAwIAA==.Chopstix:BAAANQADCgYIDAAAAA==.Chromie:BAAANQAECggIDgAAAA==.',
Co='Comet:BAAANQAECgcIBwAAAA==.',
Cr='Crikey:BAABNQAECn9BAAMOAAoKXh1TGACUAgAOAAoKXh1TGACUAgAPAAYKhg3lRQArAQAAAA==.',
Cv='Cvdruid:BAAANQADCgUIBQAAAA==.',
Da='Daga:BAAANQAECgcICwAAAA==.',
De='Definitely:BAACNQAFFH8FAAMJAAIK8xfdAwCoAAAJAAIK8xfdAwCoAAAFAAEKphAMNgBPAAA1AAQKf0AAAgkACgrdInwCAEIDAAkACgrdInwCAEIDAAAA.Demonich:BAAANQADCgUIBQAAAA==.Desaix:BAABNQAECn8ZAAIHAAcKEBUDHwDYAQAHAAcKEBUDHwDYAQAAAA==.Desariana:BAABNQAECn8mAAIIAAoKsBLvfgArAgAIAAoKsBLvfgArAgAAAA==.Devimon:BAAANQAECgQIBQAAAA==.Dewasixseven:BAAANQADCgQIBAAAAA==.',
Dh='Dhunt:BAAANQABCgMIAQAAAA==.',
Do='Dormas:BAAANQAECgYIDQAAAA==.Doug:BAAANQAECgQICAAAAA==.',
Dr='Drakeon:BAAANQADCgcJBwABNQAECgoKZgAKACEaAA==.Drizzts:BAAANQAECgEIBgAAAA==.',
Dw='Dwarfpally:BAAANQAECgMIBgAAAA==.',
El='Eldh:BAAANQADCgEIAQAAAA==.Eldk:BAAANQAECggIEgAAAA==.Elisoly:BAABNQAECn8lAAIQAAgKUBMyeQCtAQAQAAgKUBMyeQCtAQAAAA==.',
Em='Emrald:BAAANQAECgIIAwAAAA==.',
En='Endlessly:BAABNQAECn8fAAIRAAoKLhyEBgAFAwARAAoKLhyEBgAFAwAAAA==.',
Er='Errimage:BAAANQAECgEIAgABNQAECgQIBQAEAAAAAA==.Erritwo:BAAANQAECgQIBQAAAA==.',
Et='Etro:BAABNQAECn8wAAISAAoKjCTlBgB3AgASAAoKjCTlBgB3AgAAAA==.',
Ev='Evelinar:BAAANQAECgEIAQAAAA==.Evoslex:BAABNQAECn88AAITAAoKLiJvAwBxAwATAAoKLiJvAwBxAwAAAA==.',
Ex='Exo:BAECNQAFFH8SAAIUAAcKgxezDACJAQAUAAcKgxezDACJAQA1AAQKf1AAAhQACgqWJEYJAG4DABQACgqWJEYJAG4DAAAA.',
Fa='Facerolleh:BAACNQAFFH8kAAIKAAcKRh9XAwCxAgAKAAcKRh9XAwCxAgA1AAQKfzwAAgoACgqAJJ0TAG0DAAoACgqAJJ0TAG0DAAAA.Fatedx:BAABNQAECn8cAAIVAAgKzQtoQwCnAQAVAAgKzQtoQwCnAQAAAA==.',
Fe='Feelgoodinc:BAAANQAECgMIAwAAAA==.Feint:BAABNQAECn9sAAMGAAoKpyHIBACAAgAGAAoKNx7IBACAAgAHAAcKgRzgLgC7AQAAAA==.',
Fi='Fistdaddy:BAAANQAECgUIBQAAAA==.Fiz:BAACNQAFFH8HAAIKAAQKbg85JgDPAAAKAAQKbg85JgDPAAA1AAQKf0UAAgoACgpaIz0HADYDAAoACgpaIz0HADYDAAAA.',
Fl='Flora:BAAANQADCgQIBAAAAA==.',
Fu='Fuknazum:BAAANQAECgIIAgAAAA==.',
Ga='Galara:BAAANQAECgIIAgAAAA==.',
Gi='Giveroflife:BAAANQAECgIIBgAAAA==.',
Gr='Grandpriest:BAAANQAECgUICAABNQAECgkJHgAIAJgNAA==.Grimoirsingh:BAAANQAECgEIAQAAAA==.Grimveil:BAABNQAECn8+AAIWAAoK0SKsAwAXAwAWAAoK0SKsAwAXAwAAAA==.',
['Gô']='Gôku:BAAANQADCgYIBgAAAA==.',
Ha='Harafar:BAACNQAFFH8PAAMNAAUK6AYgDgC9AAANAAQK6AYgDgC9AAAMAAEKXQO0EQA8AAA1AAQKfzYAAg0ACgpOGQsRADcCAA0ACgpOGQsRADcCAAAA.',
He='Hellbourne:BAAANQAECgUICgAAAA==.',
Hi='Hibiki:BAAANQADCgIIAgAAAA==.',
Ho='Hogreveal:BAAANQAECgQIBQAAAA==.Hollykibbler:BAAANQAECgQIBAAAAA==.Holyclstrfuk:BAAANQADCgYIBgAAAA==.Horsé:BAAANQADCggIEgAAAA==.',
Hu='Huntslex:BAAANQAECgcIDQABNQAECgoKPAATAC4iAA==.',
Il='Illidam:BAAANQAECgcIEwAAAA==.',
It='Itskiohte:BAAANQAECgYJEwAAAA==.',
Ja='Jaedaa:BAAANQAECgcJBwABNQAFFAUIEQAUAGYWAA==.Jaedamend:BAABNQAECn8oAAMXAAoKmiWnAAA5BAAXAAoKmiWnAAA5BAABAAcKfhH7LgCsAQABNQAFFAUIEQAUAGYWAA==.',
Je='Jertbirt:BAAANQAECgEIAQAAAA==.',
Ka='Kaelthuzzad:BAAANQAECgEIAQAAAA==.Kalzaketh:BAABNQAECn8zAAIYAAgKYgv8DQBqAQAYAAgKYgv8DQBqAQAAAA==.Kashari:BAAANQAECgQIDQABNQAECgoKawAXALAXAA==.Katali:BAAANQAECgUICwAAAA==.Kaypop:BAAANQADCgQIBwABNQAFFAcIGQAOAHUUAA==.Kazo:BAACNQAFFH8MAAIXAAQKiBepDwAxAQAXAAQKiBepDwAxAQA1AAQKfzQABBcACgp9IMYkANkCABcACgp9IMYkANkCABkAAQpoI3cfAGUAAAEAAQpQEwd1ADwAAAAA.Kazuggar:BAACNQAFFH8mAAIaAAYKVRj6CgCeAQAaAAYKVRj6CgCeAQA1AAQKf0oAAxoACgpgJEYOAE8DABoACgpgJEYOAE8DABsAAgqDFlENAXEAAAAA.Kazzn:BAABNQAECn8jAAMMAAoKtxq8CwB8AgAMAAoKtxq8CwB8AgANAAEKYwVKtgAsAAAAAA==.',
Ke='Kell:BAAANQAECgYICgAAAA==.',
Ki='Kibbler:BAAANQAECgIIAwAAAA==.Killerman:BAAANQAECgUIBQAAAA==.',
Kn='Knucklez:BAAANQADCgYIAwAAAA==.',
Ku='Kucabara:BAAANQAECgQIBgABNQAECgUIEQAEAAAAAA==.Kungpew:BAAANQAECgIIAgAAAA==.',
Kw='Kwichang:BAABNQAECn8hAAMFAAoKZg2scABkAQAFAAgKkw6scABkAQAJAAMKIQucGQClAAAAAA==.',
Ky='Kyndariae:BAABNQAECn8hAAIXAAgKDQ2piwBzAQAXAAgKDQ2piwBzAQAAAA==.',
La='Lagman:BAAANQADCgEIAQAAAA==.',
Li='Lickynose:BAABNQAECn8yAAIFAAoKRCJWNAAgAgAFAAoKRCJWNAAgAgAAAA==.',
Ma='Mahou:BAAANQAECgQIBQAAAA==.Malcador:BAABNQAECn8aAAINAAoKVxVLGADVAQANAAoKVxVLGADVAQAAAA==.Mantisar:BAABNQAECn8dAAIIAAkKDgox4QBZAQAIAAkKDgox4QBZAQAAAA==.Marmite:BAABNQAECn8fAAIcAAgK/haNCgD6AQAcAAgK/haNCgD6AQAAAA==.Mayene:BAAANQAECgEIAQABNQAECgYIEwAEAAAAAA==.Mazoku:BAAANQAECgEIAQAAAA==.',
Me='Menethil:BAAANQABCgIIAgAAAA==.',
Mi='Mightyhunt:BAAANQAECggIEwAAAA==.Miracoli:BAAANQAECgEIAQAAAA==.Mirrorimage:BAABNQAECn8qAAMBAAoKyRoMFADFAgABAAoKyRoMFADFAgAXAAMKUwL55gByAAABNQAFFAQICQABAIYYAA==.Mirrorx:BAACNQAFFH8JAAIBAAQKhhgECgBdAQABAAQKhhgECgBdAQA1AAQKfzcAAwEACgq5IPkMABsDAAEACgq5IPkMABsDABcACArODbh6AKoBAAAA.',
Mo='Moosfel:BAAANQAECgQJBgAAAA==.Mortaliass:BAAANQAECgEIAQAAAA==.',
Mt='Mtzz:BAAANQAECgYIEgAAAA==.',
Mu='Mudkrab:BAAANQAECgIIAwAAAA==.',
My='Mylie:BAAANQADCgIIAgAAAA==.Mystdragon:BAACNQAFFH8JAAIcAAQKAxP5DQAsAQAcAAQKAxP5DQAsAQA1AAQKfx8AAxwACQpnH5kMANsCABwACQpnH5kMANsCABgABArwGccQACsBAAE1AAUUBwg3AAIAlSEA.Mystweaverr:BAACNQAFFH83AAICAAcKlSHPAAB+AgACAAcKlSHPAAB+AgA1AAQKf04AAgIACgotJpcBALUDAAIACgotJpcBALUDAAAA.',
Na='Naddar:BAABNQAECn8qAAIQAAkKaBhBSQBCAgAQAAkKaBhBSQBCAgAAAA==.Narp:BAAANQADCgQIBAAAAA==.',
Ng='Nganga:BAABNQAECn8kAAMaAAoKzBksRABQAgAaAAoKzBksRABQAgAbAAcKeBvzUAA1AgAAAA==.',
Ni='Nikonii:BAABNQAECn8oAAIHAAkKOBgaKgDZAQAHAAkKOBgaKgDZAQAAAA==.',
Ov='Ovaries:BAAANQADCgUIBQABNQADCgYIBgAEAAAAAA==.',
Pa='Paktam:BAAANQAECgYIDAAAAA==.Paladron:BAAANQAECgIIAgAAAA==.Palakudaliaq:BAAANQAECgEIAQAAAA==.Palaynslea:BAABNQAECn8uAAIQAAoKrA7oXgD8AQAQAAoKrA7oXgD8AQAAAA==.',
Pe='Perceptor:BAAANQAECgIIAgABNQAECgoKMwAdAAweAA==.',
Pr='Prothero:BAACNQAFFH8JAAIFAAUKexD4JABgAQAFAAUKexD4JABgAQA1AAQKfzMAAgUACgoIJaMGACwDAAUACgoIJaMGACwDAAAA.Proyo:BAABNQAECn8dAAIFAAcKCRmNewBMAQAFAAcKCRmNewBMAQAAAA==.',
['På']='Påthor:BAABNQAECn8lAAINAAgKCRaVKgA1AQANAAgKCRaVKgA1AQAAAA==.',
Ql='Ql:BAAANQADCgYIBgAAAA==.',
Ra='Raijinn:BAABNQAECn8pAAMaAAkKRSK6HQBVAgAaAAgK/SK6HQBVAgAbAAcKlxnvVwAbAgAAAA==.Raizex:BAAANQAECgEIAQAAAA==.Ratbarstard:BAABNQAECn9VAAIFAAoKfRv1XwC/AgAFAAoKfRv1XwC/AgAAAA==.Rawtoor:BAABNQAECn86AAIeAAoKFR7yBwBSAwAeAAoKFR7yBwBSAwAAAA==.',
Ri='Ridgelock:BAAANQAECgIIAgAAAA==.Ridgemonk:BAAANQAECgIIBAAAAA==.Ridgerock:BAACNQAFFH8HAAIUAAMKgRKxDQC9AAAUAAMKgRKxDQC9AAA1AAQKfyIAAxQACQrQH4AfALcCABQACQrQH4AfALcCABYAAQo+A/vxACUAAAAA.Riggse:BAAANQAECggIEQABNQAFFAgIHwAKAGkkAA==.Riggspal:BAAANQAECggICwABNQAFFAgIHwAKAGkkAA==.',
Ro='Roadkill:BAABNQAECn8pAAIUAAoKhB8LEwAUAwAUAAoKhB8LEwAUAwAAAA==.Rolltoor:BAACNQAFFH8MAAIDAAcKzxFHBQDyAAADAAcKzxFHBQDyAAA1AAQKfysAAgMACgrsIgQNAAoDAAMACgrsIgQNAAoDAAAA.',
Ru='Ruínation:BAAANQAECgUICwABNQAECgoKJAAaAMwZAA==.',
Sa='Sagittarimon:BAAANQAECgIIAwAAAA==.Saiko:BAABNQAECn8hAAMVAAkK0hSjMQAcAgAVAAkKcROjMQAcAgAeAAQKxhI6UADeAAAAAA==.Sansa:BAAANQAECgcIDwAAAA==.Saso:BAACNQAFFH8XAAMFAAYK5RXKJABhAQAFAAUK7hTKJABhAQAJAAIKShM3CACYAAA1AAQKf0EAAwUACgrWI9wbAGcDAAUACgq1I9wbAGcDAAkABAqjI4kOACEBAAAA.Sastroll:BAAANQAECgMIAwABNQAFFAYIFwAFAOUVAA==.',
Sc='Scatius:BAAANQADCggICAAAAA==.Scroll:BAABNQAECn8ZAAICAAoK6Q7bCwDbAQACAAoK6Q7bCwDbAQAAAA==.',
Se='Sellais:BAAANQADCgYIBgABNQADCgYIBgAEAAAAAA==.Serbitar:BAAANQADCggIGAAAAA==.',
Sh='Shadow:BAABNQAECn8WAAIeAAgKdBapKgDsAQAeAAgKdBapKgDsAQAAAA==.Shandrilah:BAABNQAECn8YAAMNAAYKJw5AXwBTAQANAAYKJw5AXwBTAQAMAAIKuAU9bgBMAAAAAA==.Shialebuff:BAABNQAECn8VAAMXAAkKWxa6WwAOAgAXAAkKWxa6WwAOAgABAAEKqRKWcQBEAAAAAA==.Shijin:BAAANQADCgQIBAABNQADCgYIBgAEAAAAAA==.',
Si='Silphy:BAABNQAECn8jAAMWAAoKuBUyGAC5AQAWAAcKPxgyGAC5AQAfAAcKoA4wYgAcAQAAAA==.Sindar:BAAANQAECgIIAgAAAA==.Siphon:BAAANQAECgEIAQAAAA==.Siscomp:BAABNQAECn9mAAIKAAoKIRpsTgCeAgAKAAoKIRpsTgCeAgAAAA==.Sixth:BAAANQADCggIEAAAAA==.',
Sk='Skoog:BAABNQAECn8dAAIKAAkKfhXyjgD3AQAKAAkKfhXyjgD3AQAAAA==.Sky:BAACNQAFFH8KAAMXAAUKuhKiJgCeAAAXAAUKGBGiJgCeAAAZAAEKsBskBABHAAA1AAQKfz8ABBcACgo2IkoLAGgDABcACQpgI0oLAGgDABkABAruHc4PACwBAAEAAQqhGwBzAEAAAAAA.',
Sn='Snarkshot:BAAANQADCgEIAQAAAA==.Snugglepuff:BAABNQAECn8nAAIKAAoK5hLBYwBZAQAKAAoK5hLBYwBZAQAAAA==.',
So='Sock:BAAANQAECggIBAAAAA==.Sonarius:BAACNQAFFH8GAAMFAAIKUhd6QQCrAAAFAAIKUhd6QQCrAAAgAAEKCARTAQA/AAA1AAQKfzYABAUACgpHIxwWAHsDAAUACgpHIxwWAHsDACAAAQr9H1MKAF0AAAkAAQqiHmk+AEgAAAAA.',
Sp='Sparkster:BAABNQAECn8gAAIKAAgK6RwjYQBqAgAKAAgK6RwjYQBqAgAAAA==.',
Su='Sundae:BAAANQAECgYIEwAAAA==.',
Sy='Sylvie:BAACNQAFFH8HAAIOAAMK0QzvDQDkAAAOAAMK0QzvDQDkAAA1AAQKfycAAg4ACgoMFehaAGQCAA4ACgoMFehaAGQCAAAA.Syreith:BAAANQADCgYIBgAAAA==.',
['Så']='Sådistic:BAAANQAECgQIBQAAAA==.',
['Sý']='Sýlvanas:BAAANQABCgYIBgAAAA==.',
Ti='Tidders:BAABNQAECn8sAAIPAAoKThupHQBkAgAPAAoKThupHQBkAgAAAA==.Tikiwoki:BAAANQAECgcIEgAAAA==.Tiramisu:BAABNQAECn8cAAMMAAoKEx3jGAB2AgAMAAkKdBzjGAB2AgANAAMK5w17kACVAAAAAA==.',
Tr='Trilldi:BAAANQADCggJEAAAAA==.Tritone:BAAANQAECgEIAQAAAA==.',
Ty='Tyladrhas:BAABNQAECn8aAAMhAAgKxhlWDgDWAQAhAAgKxhlWDgDWAQAVAAEK9Qm0ZAA+AAAAAA==.Tyrismaximus:BAAANQAECgMIBgAAAA==.',
Up='Up:BAABNQAECn8vAAITAAoKXxzsCwCnAgATAAoKXxzsCwCnAgAAAA==.',
Va='Vaelus:BAAANQABCgIIAgAAAA==.Varina:BAAANQAECgIJAwAAAA==.',
Ve='Velorah:BAAANQAECgUICgAAAA==.Velsaert:BAAANQADCgUJBAAAAA==.',
Vo='Volatilegas:BAAANQAECgYIEgAAAA==.',
Vu='Vulken:BAABNQAECn9wAAIOAAoKoRwYGQCQAgAOAAoKoRwYGQCQAgAAAA==.',
Wi='Winnìng:BAAANQAECgQICAAAAA==.',
Ya='Yamazaki:BAAANQAECgYIBgAAAA==.',
Ye='Yessuh:BAAANQAECgEIAgAAAA==.',
Zi='Zihon:BAAANQAECgUIBQAAAA==.',
Zo='Zombi:BAAANQAECgEIAQAAAA==.Zombiepanda:BAAANQAECgMIBwAAAA==.Zoomer:BAABNQAECn8nAAIhAAgKTQnsFgA/AQAhAAgKTQnsFgA/AQABNQAFFAQICQABAIYYAA==.',
Zu='Zubb:BAAANQADCgUIBQABNQAECggIHgAFABIUAA==.Zugg:BAABNQAECn8UAAIiAAcK/BewDwACAgAiAAcK/BewDwACAgABNQAECggIHgAFABIUAA==.Zupp:BAABNQAECn8eAAIFAAgKEhSZvQAJAgAFAAgKEhSZvQAJAgAAAA==.Zuqq:BAAANQAECgYIEAABNQAECggIHgAFABIUAA==.',
['Ér']='Ér:BAAANQAECgIIAgAAAA==.',
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
