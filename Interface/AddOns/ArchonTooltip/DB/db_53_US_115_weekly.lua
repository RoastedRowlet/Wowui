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

local lookup = {'Priest-Shadow','Monk-Mistweaver','Monk-Windwalker','Unknown-Unknown','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Paladin-Retribution','Mage-Frost','Priest-Holy','Warrior-Arms','Warrior-Fury','Druid-Restoration','Druid-Balance','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Holy','Druid-Feral','Paladin-Protection','Evoker-Devastation','DeathKnight-Blood','DemonHunter-Havoc','DeathKnight-Unholy','DemonHunter-Devourer','Evoker-Augmentation','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Druid-Guardian','Mage-Fire','DemonHunter-Vengeance','Warlock-Destruction',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aamion:BAABNQAECn8gAAIBAAgKiQjOLgDZAAABAAgKiQjOLgDZAAAAAA==.',
Ab='Abo:BAABNQAECn8UAAMCAAkKlACGNwAvAAACAAkKlACGNwAvAAADAAEKxwAMggAEAAAAAA==.',
Ae='Aeonfire:BAAANQAECgEIAQABNQAECggICwAEAAAAAA==.',
Ak='Akame:BAAANQAFFAMIAgAAAA==.',
Al='Alykard:BAABNQAECn8eAAIFAAoK+QX4+gCXAQAFAAoK+QX4+gCXAQAAAA==.',
Am='Amateur:BAABNQAECn80AAMGAAoKYhmyDgC5AQAHAAkKoQ7pNQDkAQAGAAoKlxiyDgC5AQAAAA==.Amazing:BAAANQAECgYIBgABNQAECgoKNAAGAGIZAA==.',
An='Andronicas:BAABNQAECn8bAAIIAAkKgAoA4QBZAQAIAAkKgAoA4QBZAQAAAA==.Aneira:BAABNQAECn85AAIJAAoKjg/pCgAXAgAJAAoKjg/pCgAXAgAAAA==.',
As='Asaki:BAAANQADCggICAAAAA==.Aspect:BAAANQAECgQIBAABNQAECggICwAEAAAAAA==.',
Av='Avi:BAABNQAECn8cAAIKAAoKxgiKUAC+AQAKAAoKxgiKUAC+AQABNQAECgoKZgALACEaAA==.',
Ba='Baesuzy:BAABNQAECn8rAAIFAAgK1A/tgAB5AQAFAAgK1A/tgAB5AQAAAA==.Baragas:BAAANQAECgUIDgAAAA==.',
Be='Belle:BAAANQADCgcICAAAAA==.Benkei:BAABNQAECn8cAAIMAAkK9Bv2BwDqAQAMAAkK9Bv2BwDqAQAAAA==.Berzerker:BAAANQABCgYICgAAAA==.',
Bg='Bgc:BAAANQABCgYICQAAAA==.',
Bl='Blackds:BAAANQABCgQIBAAAAA==.Blain:BAABNQAECn8UAAILAAgK4RPcqgCyAQALAAgK4RPcqgCyAQAAAA==.',
Bo='Book:BAAANQAECgEIAQABNQAECgoKHQACAOkOAA==.Bosammana:BAAANQADCgUIBwAAAA==.',
Bu='Bubblôseven:BAAANQAECggIDAAAAA==.Budin:BAAANQADCgIIAgAAAA==.',
Ca='Cannibal:BAABNQAECn8iAAINAAkKMh0fEwBNAgANAAkKMh0fEwBNAgAAAA==.Capri:BAABNQAECn8pAAIOAAgKjAriVwB2AQAOAAgKjAriVwB2AQAAAA==.Casiopia:BAAANQADCgQIBQAAAA==.',
Ch='Choomoo:BAABNQAECn8sAAINAAoKwByRDgCbAgANAAoKwByRDgCbAgABNQAFFAQIBwACAAwIAA==.Chopstix:BAAANQADCgYIDAAAAA==.Chromie:BAAANQAECggIDQAAAA==.',
Co='Comet:BAAANQAECgcICQAAAA==.',
Cr='Crikey:BAABNQAECn9BAAMPAAoKXh1fKAByAgAPAAoKXh1fKAByAgAQAAYKhg3lRQArAQAAAA==.',
Cv='Cvdruid:BAAANQADCgUIBQAAAA==.',
Da='Daga:BAAANQAECggICwAAAA==.',
De='Definitely:BAACNQAFFH8GAAMJAAMK8xfaBQCdAAAJAAMK8xfaBQCdAAAFAAEKphDWPwBMAAA1AAQKf0kAAgkACgoJI3wCAEIDAAkACgoJI3wCAEIDAAAA.Demonich:BAAANQADCgUIBQAAAA==.Desaix:BAABNQAECn8ZAAIHAAcKEBUDHwDYAQAHAAcKEBUDHwDYAQAAAA==.Desariana:BAABNQAECn8nAAIIAAoKsBLvfgArAgAIAAoKsBLvfgArAgAAAA==.Devimon:BAAANQAECgQIBAAAAA==.Dewasixseven:BAAANQADCgQIBAAAAA==.',
Dh='Dhunt:BAAANQABCgMIAQAAAA==.',
Do='Dormas:BAAANQAECgcIDQAAAA==.Doug:BAAANQAECgQICAAAAA==.',
Dr='Drakeon:BAAANQADCgcJBwABNQAECgoKZgALACEaAA==.Drizzts:BAAANQAECgEIAwAAAA==.',
Dw='Dwarfpally:BAAANQAECgMIBgAAAA==.',
El='Eldh:BAAANQADCgEIAQAAAA==.Eldk:BAAANQAECggIEQAAAA==.Elisoly:BAABNQAECn8sAAIRAAgKbxOcUwCSAQARAAgKbxOcUwCSAQAAAA==.',
Em='Emrald:BAAANQAECgIIAwAAAA==.',
En='Endlessly:BAABNQAECn8oAAISAAoKzB6EBgAFAwASAAoKzB6EBgAFAwAAAA==.',
Er='Erritwo:BAAANQAECgQIBAAAAA==.',
Et='Etro:BAABNQAECn83AAITAAoKPSUSBQDzAgATAAoKPSUSBQDzAgAAAA==.',
Ev='Evelinar:BAAANQAECgEIAQAAAA==.Evoslex:BAABNQAECn9GAAIUAAoKqCKkAQAPAwAUAAoKqCKkAQAPAwAAAA==.',
Ex='Exo:BAECNQAFFH8SAAIVAAcKgxezDACJAQAVAAcKgxezDACJAQA1AAQKf1IAAhUACgqWJEYJAG4DABUACgqWJEYJAG4DAAAA.',
Fa='Facerolleh:BAACNQAFFH8mAAILAAgKARtXAwCxAgALAAgKARtXAwCxAgA1AAQKf0QAAgsACgouJnMEAGUDAAsACgouJnMEAGUDAAAA.Fatedx:BAABNQAECn8jAAIWAAoKaAxfKACMAQAWAAoKaAxfKACMAQAAAA==.',
Fe='Feelgoodinc:BAAANQAECgMIAwAAAA==.Feint:BAACNQAFFH8FAAMGAAEKVhTiDQBPAAAGAAEKVhTiDQBPAAAHAAEKRQx2IABJAAA1AAQKf3QAAwYACgrGISYHAGICAAcACQpCHD8cAHgCAAYACgo3HiYHAGICAAAA.',
Fi='Fistdaddy:BAAANQAECgUIBQAAAA==.Fiz:BAACNQAFFH8HAAILAAQKbg85JgDPAAALAAQKbg85JgDPAAA1AAQKf1gAAgsACgqsI7QKAC4DAAsACgqsI7QKAC4DAAAA.',
Fl='Flora:BAAANQADCgQIBAAAAA==.',
Fu='Fuknazum:BAAANQAECgIIAgAAAA==.',
Ga='Galara:BAAANQAECgIIAgAAAA==.',
Gi='Giveroflife:BAAANQAECgIIBgAAAA==.',
Gr='Grandpriest:BAAANQAECgUIBwABNQAECgoKKAAIAJYQAA==.Grimoirsingh:BAAANQAECgEIAQAAAA==.Grimveil:BAABNQAECn9IAAIXAAoKZiOrBAAeAwAXAAoKZiOrBAAeAwAAAA==.',
['Gô']='Gôku:BAAANQADCgYIBgAAAA==.',
Ha='Harafar:BAACNQAFFH8QAAMOAAYKlwUCDQDrAAAOAAUKlwUCDQDrAAANAAEKXQOWFQA5AAA1AAQKfz8AAg4ACgq2GogSAGMCAA4ACgq2GogSAGMCAAAA.',
He='Hellbourne:BAAANQAECgUICgAAAA==.',
Hi='Hibiki:BAAANQADCgIIAgAAAA==.',
Ho='Hogreveal:BAAANQAECgUIBQAAAA==.Hollykibbler:BAAANQAECgQIBAAAAA==.Holyclstrfuk:BAAANQADCgYIBgAAAA==.Horsé:BAAANQADCggIEgAAAA==.',
Hu='Huntslex:BAAANQAECgYIEQABNQAECgoKRgAUAKgiAA==.',
Il='Illidam:BAABNQAECn8UAAIYAAkKnRAPNQCbAQAYAAkKnRAPNQCbAQAAAA==.',
It='Itskiohte:BAAANQAECgcIEAAAAA==.',
Ja='Jaedaa:BAAANQAECgcJBwABNQAFFAUIEQAVAGYWAA==.Jaedamend:BAABNQAECn8yAAMKAAoKmiVhAQArBAAKAAoKmiVhAQArBAABAAcKfhH7LgCsAQABNQAFFAUIEQAVAGYWAA==.',
Je='Jertbirt:BAAANQAECgEIAQAAAA==.',
Ka='Kalzaketh:BAABNQAECn8zAAIZAAgKYgv8DQBqAQAZAAgKYgv8DQBqAQAAAA==.Kashari:BAAANQAECgQICwABNQAECgoKdQAKAJgYAA==.Katali:BAAANQAECgUIDQAAAA==.Kaypop:BAAANQADCgQIBwABNQAFFAcIGgAPAHUUAA==.Kazo:BAACNQAFFH8MAAIKAAQKiBc3FAAtAQAKAAQKiBc3FAAtAQA1AAQKfz0ABAoACgqfIMYkANkCAAoACgqfIMYkANkCAAEACArADboaAIYBABoAAQpoI3cfAGUAAAAA.Kazuggar:BAACNQAFFH8nAAIbAAYKVRj6CgCeAQAbAAYKVRj6CgCeAQA1AAQKf1IAAxsACgpgJEYOAE8DABsACgpgJEYOAE8DABwACQoFFZRJAHUBAAAA.Kazzn:BAABNQAECn8jAAMNAAoKtxrAEQBlAgANAAoKtxrAEQBlAgAOAAEKYwVKtgAsAAABNQAFFAQIDAAKAIgXAA==.',
Ke='Kell:BAAANQAECgYICAAAAA==.',
Ki='Kibbler:BAAANQAECgIIAwAAAA==.Killerman:BAAANQAECgUIBQAAAA==.',
Kn='Knucklez:BAAANQADCgYIAwAAAA==.',
Ko='Korosensei:BAAANQAECgEIAQAAAA==.',
Ku='Kucabara:BAAANQAECgQIBQABNQAECgUIDgAEAAAAAA==.Kungpew:BAAANQAECgIIAgAAAA==.',
Kw='Kwichang:BAABNQAECn8oAAMJAAoKSBBTEgApAQAFAAkKlw60cgCaAQAJAAYKbQ9TEgApAQAAAA==.',
Ky='Kyndariae:BAABNQAECn8hAAIKAAgKDQ2piwBzAQAKAAgKDQ2piwBzAQAAAA==.',
La='Lagman:BAAANQADCgEIAQAAAA==.',
Li='Lickynose:BAABNQAECn85AAIFAAoKbSJUIgCbAgAFAAoKbSJUIgCbAgAAAA==.',
Ma='Mahou:BAAANQAECgUIBwAAAA==.Malcador:BAABNQAECn8gAAIOAAoKRhjeFgAtAgAOAAoKRhjeFgAtAgAAAA==.Mantisar:BAABNQAECn8dAAIIAAkKDgox4QBZAQAIAAkKDgox4QBZAQAAAA==.Marmite:BAABNQAECn8lAAIdAAgK/hYgDgDyAQAdAAgK/hYgDgDyAQAAAA==.Mayene:BAAANQAECgEIAQABNQAECggIAQAEAAAAAA==.',
Me='Menethil:BAAANQABCgIIAgAAAA==.',
Mi='Mightyhunt:BAABNQAECn8ZAAIPAAoKsBv8TgDxAQAPAAoKsBv8TgDxAQAAAA==.Mirrorimage:BAABNQAECn8qAAMBAAoKyRoMFADFAgABAAoKyRoMFADFAgAKAAMKUwL55gByAAABNQAFFAQICQABAIYYAA==.Mirrorx:BAACNQAFFH8JAAIBAAQKhhgECgBdAQABAAQKhhgECgBdAQA1AAQKfz8AAwEACgowIfkMABsDAAEACgowIfkMABsDAAoACArODbh6AKoBAAAA.',
Mo='Moosfel:BAAANQAECgQJBgAAAA==.Mortaliass:BAAANQAECgEIAQAAAA==.',
Mt='Mtzz:BAAANQAECgYIEgAAAA==.',
Mu='Mudkrab:BAAANQAECgIIBAAAAA==.',
My='Mylie:BAAANQADCgIIAgAAAA==.Mystdragon:BAACNQAFFH8JAAIdAAQKAxP5DQAsAQAdAAQKAxP5DQAsAQA1AAQKfx8AAx0ACQpnH5kMANsCAB0ACQpnH5kMANsCABkABArwGccQACsBAAE1AAUUBwg3AAIAlSEA.Mystweaverr:BAACNQAFFH83AAICAAcKlSHPAAB+AgACAAcKlSHPAAB+AgA1AAQKf1AAAgIACgotJpcBALUDAAIACgotJpcBALUDAAAA.',
Na='Naddar:BAABNQAECn8qAAIRAAkKaBhBSQBCAgARAAkKaBhBSQBCAgAAAA==.Narp:BAAANQADCgQIBAAAAA==.',
Ng='Nganga:BAABNQAECn8rAAMbAAoKaxosRABQAgAbAAoKaxosRABQAgAcAAgKShjzUAA1AgAAAA==.',
Ni='Nikonii:BAABNQAECn8qAAIHAAkKOBg9FgAwAgAHAAkKOBg9FgAwAgAAAA==.',
Ov='Ovaries:BAAANQADCgUIBQABNQADCgYIBgAEAAAAAA==.',
Pa='Paktam:BAAANQAECgYIDAAAAA==.Paladron:BAAANQAECgIIAgAAAA==.Palakudaliaq:BAAANQADCggICAAAAA==.Palaynslea:BAABNQAECn8uAAIRAAoKrA7oXgD8AQARAAoKrA7oXgD8AQAAAA==.',
Pe='Perceptor:BAAANQAECgIIAgABNQAECgoKNwAeAIgfAA==.',
Pr='Prothero:BAACNQAFFH8KAAIFAAYKDxD4JABgAQAFAAYKDxD4JABgAQA1AAQKfzwAAgUACgpUJTcGAEcDAAUACgpUJTcGAEcDAAAA.Proyo:BAABNQAECn8hAAIFAAgKEBlMcACgAQAFAAgKEBlMcACgAQAAAA==.',
['På']='Påthor:BAABNQAECn8sAAIOAAgKPhiaLgBWAQAOAAgKPhiaLgBWAQAAAA==.',
Ql='Ql:BAAANQADCgYIBgAAAA==.',
Ra='Raijinn:BAABNQAECn8vAAMbAAoKayLEDAA7AwAbAAoKayLEDAA7AwAcAAcKlxnvVwAbAgAAAA==.Raizex:BAAANQADCggJDwAAAA==.Ratbarstard:BAACNQAFFH8FAAIFAAIK5Ae3SQAAAAAFAAIK5Ae3SQAAAAA1AAQKf1sAAgUACgoJHOQ7ADYCAAUACgoJHOQ7ADYCAAAA.Rawtoor:BAABNQAECn86AAIYAAoKFR7yBwBSAwAYAAoKFR7yBwBSAwAAAA==.',
Ri='Ridgelock:BAAANQAECgQIBAAAAA==.Ridgemonk:BAAANQAECgIIBgAAAA==.Ridgerock:BAACNQAFFH8KAAIVAAMKFhTEEAC+AAAVAAMKFhTEEAC+AAA1AAQKfyMAAxUACQrQH4AfALcCABUACQrQH4AfALcCABcAAQo+A/vxACUAAAAA.Riggse:BAAANQAECggIEQABNQAFFAgIHwALAGkkAA==.Riggspal:BAAANQAECggICwABNQAFFAgIHwALAGkkAA==.',
Ro='Roadkill:BAABNQAECn8pAAIVAAoKhB8LEwAUAwAVAAoKhB8LEwAUAwAAAA==.Rolltoor:BAACNQAFFH8MAAIDAAcKzxGkBgDwAAADAAcKzxGkBgDwAAA1AAQKfywAAgMACgrsIgQNAAoDAAMACgrsIgQNAAoDAAAA.',
Ru='Ruínation:BAAANQAECgUICwABNQAECgoKKwAbAGsaAA==.',
Sa='Sagittarimon:BAAANQAECgMIBQAAAA==.Saiko:BAABNQAECn8hAAMWAAkK0hSjMQAcAgAWAAkKcROjMQAcAgAYAAQKxhI6UADeAAAAAA==.Sansa:BAAANQAECgcIDgAAAA==.Saso:BAACNQAFFH8XAAMFAAYK5RXKJABhAQAFAAUK7hTKJABhAQAJAAIKShM3CACYAAA1AAQKf0sAAwUACgr6JNwbAGcDAAUACgrYJNwbAGcDAAkABArPI7cRADEBAAAA.Sastroll:BAAANQAECgMIAwABNQAFFAYIFwAFAOUVAA==.',
Sc='Scatius:BAAANQADCggICAAAAA==.Scroll:BAABNQAECn8dAAMCAAoK6Q55EADGAQACAAoK6Q55EADGAQADAAMK5AeEPQCNAAAAAA==.',
Se='Sellais:BAAANQADCgYIBgABNQADCgYIBgAEAAAAAA==.Serbitar:BAAANQADCggIGAAAAA==.',
Sh='Shadow:BAABNQAECn8WAAIYAAgKdBapKgDsAQAYAAgKdBapKgDsAQAAAA==.Shakes:BAAANQAECgMIBAAAAA==.Shandrilah:BAABNQAECn8YAAMOAAYKJw5AXwBTAQAOAAYKJw5AXwBTAQANAAIKuAU9bgBMAAAAAA==.Shialebuff:BAABNQAECn8YAAMKAAoKeBgUOwAXAgAKAAoKeBgUOwAXAgABAAEKqRKWcQBEAAAAAA==.Shijin:BAAANQADCgQIBAABNQADCgYIBgAEAAAAAA==.',
Si='Silphy:BAAANQAECggIKwABNQAECgoKRwAXAHseAQ==.Sindar:BAAANQAECgIIAgAAAA==.Siphon:BAAANQADCgcIEAAAAA==.Siscomp:BAABNQAECn9mAAILAAoKIRpsTgCeAgALAAoKIRpsTgCeAgAAAA==.Sixth:BAAANQADCggIEAAAAA==.',
Sk='Skoog:BAABNQAECn8dAAILAAkKfhXyjgD3AQALAAkKfhXyjgD3AQAAAA==.Sky:BAACNQAFFH8JAAMKAAQKlxKiJgCeAAAKAAQKjRCiJgCeAAAaAAEKsBskBABHAAA1AAQKf0kABAoACgqxJHgIAI0DAAoACgrvIngIAI0DABoABAruHc4PACwBAAEAAQqhGwBzAEAAAAAA.',
Sn='Snarkshot:BAAANQADCgEIAQAAAA==.Snugglepuff:BAABNQAECn8nAAILAAoK5hIClwDjAQALAAoK5hIClwDjAQAAAA==.',
So='Sock:BAAANQAECggIBAAAAA==.Sonarius:BAACNQAFFH8JAAMFAAMKMhigGQD5AAAFAAMKMhigGQD5AAAfAAEKCARTAQA/AAA1AAQKfzgABAUACgpVJBwWAHsDAAUACgpVJBwWAHsDAB8AAQr9H1MKAF0AAAkAAQqiHmk+AEgAAAAA.',
Sp='Sparkster:BAABNQAECn80AAILAAoKaxkjYQBqAgALAAoKaxkjYQBqAgAAAA==.',
Su='Sundae:BAAANQAECgYIEAAAAA==.',
Sy='Sylvie:BAACNQAFFH8KAAIPAAMK0QwmEgDfAAAPAAMK0QwmEgDfAAA1AAQKfygAAg8ACgoMFehaAGQCAA8ACgoMFehaAGQCAAAA.Syreith:BAAANQADCgYIBgAAAA==.',
['Så']='Sådistic:BAAANQAECgQIBQAAAA==.',
['Sý']='Sýlvanas:BAAANQABCgYIBgAAAA==.',
Ti='Tidders:BAABNQAECn8yAAMQAAoKzhupHQBkAgAQAAoKzhupHQBkAgAPAAMKNxOPzgDQAAAAAA==.Tikiwoki:BAAANQAECgcIDwAAAA==.Tiramisu:BAABNQAECn8cAAMNAAoKEx3jGAB2AgANAAkKdBzjGAB2AgAOAAMK5w17kACVAAAAAA==.',
Tr='Trilldi:BAAANQADCggJEAAAAA==.Tritone:BAAANQAECgEIAQAAAA==.',
Ty='Tyladrhas:BAABNQAECn8cAAMgAAgKOhpWDgDWAQAgAAgKOhpWDgDWAQAWAAEK9Qk4cgA5AAAAAA==.Tyrismaximus:BAAANQAECgMIBAAAAA==.',
Up='Up:BAABNQAECn82AAIUAAoKYB21BQAwAgAUAAoKYB21BQAwAgAAAA==.',
Va='Vaelus:BAAANQABCgIIAgAAAA==.Varina:BAAANQAECgIJAgAAAA==.',
Ve='Velorah:BAAANQAECgYICgAAAA==.Velsaert:BAAANQADCgUJBAAAAA==.',
Vo='Volatilegas:BAAANQAECgYIDQAAAA==.',
Vu='Vulken:BAABNQAECn92AAIPAAoK3BzTJQB9AgAPAAoK3BzTJQB9AgAAAA==.',
Wa='Was:BAAANQAECggIDwABNQAFFAcIJQAPAFwbAA==.',
Wi='Winnìng:BAAANQAECgQICAAAAA==.',
Ya='Yamazaki:BAAANQAECgYIBgAAAA==.',
Ye='Yessuh:BAAANQAECgEIAgAAAA==.',
Zi='Zihon:BAAANQAECgUIBQAAAA==.',
Zo='Zombi:BAAANQAECgEIAQAAAA==.Zombiepanda:BAAANQAECgQIBQAAAA==.Zoomer:BAABNQAECn8nAAIgAAgKTQnsFgA/AQAgAAgKTQnsFgA/AQABNQAFFAQICQABAIYYAA==.',
Zu='Zubb:BAAANQADCgUIBQABNQAECggIHgAFABIUAA==.Zugg:BAABNQAECn8UAAIhAAcK/BewDwACAgAhAAcK/BewDwACAgABNQAECggIHgAFABIUAA==.Zupp:BAABNQAECn8eAAIFAAgKEhSZvQAJAgAFAAgKEhSZvQAJAgAAAA==.Zuqq:BAAANQAECgYIDgABNQAECggIHgAFABIUAA==.',
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
