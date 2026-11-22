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

local lookup = {'Priest-Shadow','Unknown-Unknown','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Paladin-Retribution','Mage-Frost','Priest-Holy','Warrior-Arms','Warrior-Fury','Druid-Restoration','Druid-Balance','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Holy','Druid-Feral','Paladin-Protection','Evoker-Devastation','DeathKnight-Blood','DemonHunter-Havoc','DeathKnight-Unholy','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Augmentation','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Druid-Guardian','Monk-Windwalker','Mage-Fire','Warlock-Destruction',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aamion:BAABNQAECn8kAAIBAAkKuwjRJwBGAQABAAkKuwjRJwBGAQAAAA==.',
Ab='Abo:BAAANQAECggIEwAAAA==.',
Ae='Aeonfire:BAAANQAECgEIAQABNQAECggICgACAAAAAA==.',
Ak='Akame:BAAANQAFFAQIAwAAAA==.',
Al='Alykard:BAABNQAECn8eAAIDAAoK+QX4+gCXAQADAAoK+QX4+gCXAQAAAA==.',
Am='Amateur:BAABNQAECn80AAMEAAoKYhm9EQCvAQAFAAkKoQ6pQwDvAQAEAAoKlxi9EQCvAQAAAA==.Amazing:BAAANQAECgYIBgABNQAECgoKNAAEAGIZAA==.',
An='Andronicas:BAABNQAECn8gAAIGAAkKBAwL0gA0AQAGAAkKBAwL0gA0AQAAAA==.Aneira:BAABNQAECn86AAIHAAoKjg/pCgAXAgAHAAoKjg/pCgAXAgAAAA==.',
As='Asaki:BAAANQADCggICAAAAA==.Aspect:BAAANQAECgQIBAABNQAECggICgACAAAAAA==.',
Au='Aurius:BAAANQAECggIEAAAAA==.',
Av='Avi:BAABNQAECn8iAAIIAAoKMwlIZACzAQAIAAoKMwlIZACzAQABNQAECgoKegAJAF4bAA==.',
Ba='Baesuzy:BAABNQAECn8rAAIDAAgK1A8KlgB5AQADAAgK1A8KlgB5AQAAAA==.Baragas:BAAANQAECgUIDQAAAA==.',
Be='Belle:BAAANQADCgcICAAAAA==.Benkei:BAABNQAECn8cAAIKAAkK9BsDCwDgAQAKAAkK9BsDCwDgAQAAAA==.Berzerker:BAAANQABCgYICgAAAA==.',
Bg='Bgc:BAAANQABCgYICQAAAA==.',
Bl='Blackds:BAAANQABCgQIBAAAAA==.Blain:BAABNQAECn8UAAIJAAgK4RPcqgCyAQAJAAgK4RPcqgCyAQAAAA==.',
Bo='Bosammana:BAAANQADCgcIDgAAAA==.',
Bu='Bubblôseven:BAAANQAECggICgAAAA==.Budin:BAAANQADCgIIAgAAAA==.',
Ca='Cannibal:BAABNQAECn8iAAILAAkKMh01GQBIAgALAAkKMh01GQBIAgAAAA==.Capri:BAABNQAECn8rAAIMAAkKtQriVwB2AQAMAAkKtQriVwB2AQAAAA==.Casiopia:BAAANQADCgQIBQAAAA==.',
Ch='Choomoo:BAABNQAECn84AAILAAoKiB5TDQDzAgALAAoKiB5TDQDzAgABNQAFFAQICAANAGYIAA==.Chopstix:BAAANQADCgYIDAAAAA==.Chromie:BAAANQAECggICwAAAA==.',
Co='Comet:BAAANQAECgcICQAAAA==.',
Cr='Crikey:BAABNQAECn9BAAMOAAoKXh19OgC7AgAOAAoKXh19OgC7AgAPAAYKhg3lRQArAQAAAA==.',
Cv='Cvdruid:BAAANQADCgUIBQAAAA==.',
Da='Daga:BAABNQAECn8YAAMEAAoKywvnUAB6AQAEAAkK/AfnUAB6AQAFAAcK9Q7tfwAoAQAAAA==.',
De='Definitely:BAACNQAFFH8GAAMHAAMK8xcOCACaAAAHAAMK8xcOCACaAAADAAEKphC2SgBJAAA1AAQKf1IAAgcACgpvI3wCAEIDAAcACgpvI3wCAEIDAAAA.Demonich:BAAANQADCgUIBQAAAA==.Desaix:BAABNQAECn8ZAAIFAAcKEBUDHwDYAQAFAAcKEBUDHwDYAQAAAA==.Desariana:BAABNQAECn8nAAIGAAoKsBLvfgArAgAGAAoKsBLvfgArAgAAAA==.Devimon:BAAANQAECgQIBAAAAA==.Dewasixseven:BAAANQADCgQIBAAAAA==.',
Dh='Dhunt:BAAANQABCgMIAQABNQABCgQIAwACAAAAAA==.',
Do='Dormas:BAAANQAECgcIDQAAAA==.Doug:BAAANQAECgQICAAAAA==.',
Dr='Drakeon:BAAANQAECgcICgABNQAECgoKegAJAF4bAA==.Drizzts:BAAANQADCgQIBQAAAA==.',
Dw='Dwarfpally:BAAANQAECgMIBgAAAA==.',
Ei='Eira:BAAANQADCgMIAwABNQADCgYIBgACAAAAAA==.',
El='Eldh:BAAANQADCgEIAQAAAA==.Eldk:BAAANQAECggIEAAAAA==.Elisoly:BAABNQAECn8sAAIQAAgKbxOQZwCAAQAQAAgKbxOQZwCAAQAAAA==.',
Em='Emrald:BAAANQAECgIIAwAAAA==.',
En='Endlessly:BAABNQAECn8oAAIRAAoKzB6EBgAFAwARAAoKzB6EBgAFAwAAAA==.',
Er='Erritwo:BAAANQAECgQIBAAAAA==.',
Et='Etro:BAABNQAECn9CAAISAAoKVCVgBgDxAgASAAoKVCVgBgDxAgAAAA==.',
Ev='Evelinar:BAAANQADCggIEwAAAA==.Evoslex:BAABNQAECn9LAAITAAoKgSPVAQAbAwATAAoKgSPVAQAbAwAAAA==.',
Ex='Exo:BAECNQAFFH8TAAIUAAgK2RizDACJAQAUAAgK2RizDACJAQA1AAQKf1MAAhQACgqWJEYJAG4DABQACgqWJEYJAG4DAAAA.',
Fa='Facerolleh:BAACNQAFFH8mAAIJAAgKARtXAwCxAgAJAAgKARtXAwCxAgA1AAQKf0kAAgkACgoxJvkEAGcDAAkACgoxJvkEAGcDAAAA.Fatedx:BAABNQAECn8rAAIVAAoKsg5ILACvAQAVAAoKsg5ILACvAQAAAA==.',
Fe='Feelgoodinc:BAAANQAECgMIAwAAAA==.Feint:BAACNQAFFH8FAAMEAAEKVhT8EgBKAAAEAAEKVhT8EgBKAAAFAAEKRQyNJwBJAAA1AAQKf4QAAwQACgrGITAJAFACAAUACQrhHMMhAIQCAAQACgo3HjAJAFACAAAA.',
Fi='Fistdaddy:BAAANQAECgUIBQAAAA==.Fiz:BAACNQAFFH8IAAIJAAUKDw85JgDPAAAJAAUKDw85JgDPAAA1AAQKf1gAAgkACgqsI3cPABsDAAkACgqsI3cPABsDAAAA.',
Fl='Flora:BAAANQADCgQIBAAAAA==.',
Fu='Fuknazum:BAAANQAECgIIAgAAAA==.',
Ga='Galara:BAAANQAECgQIBQAAAA==.',
Gr='Grandpriest:BAAANQAECgUIBwABNQAECggIDQACAAAAAA==.Grimoirsingh:BAAANQAECgEIAQAAAA==.Grimveil:BAABNQAECn9MAAIWAAoKpyPpBQAZAwAWAAoKpyPpBQAZAwAAAA==.',
['Gô']='Gôku:BAAANQADCgYIBgAAAA==.',
Ha='Harafar:BAACNQAFFH8QAAMMAAYKlwVIEgDkAAAMAAUKlwVIEgDkAAALAAEKXQNSGQA4AAA1AAQKf0UAAgwACgr8Gt4VAGgCAAwACgr8Gt4VAGgCAAAA.',
He='Hellbourne:BAAANQAECgUICgAAAA==.',
Hi='Hibiki:BAAANQADCgIIAgAAAA==.',
Ho='Hogreveal:BAAANQAECgUIAwAAAA==.Hollykibbler:BAAANQAECgQIBAAAAA==.Holyclstrfuk:BAAANQADCgYIBgAAAA==.Horsé:BAAANQADCggIEgAAAA==.',
Hu='Huntslex:BAAANQAECgYIEAABNQAECgoKSwATAIEjAA==.',
Il='Illidam:BAABNQAECn8YAAMXAAkKLBQPNQCbAQAXAAkKRxMPNQCbAQAYAAEKSiGtJQBhAAAAAA==.',
It='Itskiohte:BAAANQAECgcIEAAAAA==.',
Ja='Jaedaa:BAAANQAECgcJBwABNQAFFAUIEQAUAGYWAA==.Jaedamend:BAABNQAECn9GAAMIAAoKqCUqAgAjBAAIAAoKqCUqAgAjBAABAAcKfhH7LgCsAQABNQAFFAUIEQAUAGYWAA==.',
Je='Jertbirt:BAAANQAECgEIAQAAAA==.',
Ka='Kalzaketh:BAABNQAECn8zAAIZAAgKYgv8DQBqAQAZAAgKYgv8DQBqAQAAAA==.Kashari:BAAANQAECgQICwABNQAECgoKnQAIAP0YAA==.Katali:BAAANQAECgUIDwAAAA==.Kaypop:BAAANQADCgQIBwABNQAFFAgIGwAOAA8TAA==.Kazo:BAACNQAFFH8MAAIIAAQKiBdcFwA6AQAIAAQKiBdcFwA6AQA1AAQKf0kABAgACgq/IncdAPACAAgACgq/IncdAPACAAEACArADY8gAIUBABoAAQpoI3cfAGUAAAAA.Kazuggar:BAACNQAFFH8nAAIbAAYKVRj6CgCeAQAbAAYKVRj6CgCeAQA1AAQKf1YAAxsACgqvJEYOAE8DABsACgqvJEYOAE8DABwACQoFFUZHALgBAAAA.Kazzn:BAABNQAECn8pAAMLAAoKtxprFwBgAgALAAoKtxprFwBgAgAMAAMK2wVKtgAsAAABNQAFFAQIDAAIAIgXAA==.',
Ke='Kell:BAAANQAECgcICAAAAA==.',
Ki='Kibbler:BAAANQAECgIIAwAAAA==.Killerman:BAAANQAECgUIBQAAAA==.',
Kn='Knucklez:BAAANQADCgYIAwAAAA==.',
Ko='Korosensei:BAAANQAECggICwAAAA==.',
Ku='Kucabara:BAAANQAECgQIBQABNQAECgUIDQACAAAAAA==.Kungpew:BAAANQAECgIIAgAAAA==.',
Kw='Kwichang:BAABNQAECn8vAAMHAAoKGBM1CwDuAQAHAAoKBhE1CwDuAQADAAkKlw5ZiACXAQAAAA==.',
Ky='Kyndariae:BAABNQAECn8jAAIIAAkKfA2piwBzAQAIAAkKfA2piwBzAQAAAA==.',
La='Lagman:BAAANQADCgEIAQAAAA==.',
Li='Lickynose:BAABNQAECn9EAAIDAAoKbyMLHgDJAgADAAoKbyMLHgDJAgAAAA==.',
Ma='Mahou:BAAANQAECgUIBwAAAA==.Malcador:BAABNQAECn8iAAIMAAoKyhhfGQBCAgAMAAoKyhhfGQBCAgAAAA==.Mantisar:BAABNQAECn8dAAIGAAkKDgox4QBZAQAGAAkKDgox4QBZAQAAAA==.Marmite:BAABNQAECn8qAAIdAAgK/hY7EQDvAQAdAAgK/hY7EQDvAQAAAA==.Mayene:BAAANQAECgEIAQABNQAECgQIBgACAAAAAA==.',
Me='Menethil:BAAANQABCgIIAgAAAA==.',
Mi='Mightyhunt:BAABNQAECn8ZAAIOAAoKsBvNbwDhAQAOAAoKsBvNbwDhAQAAAA==.Mirrorimage:BAABNQAECn8qAAMBAAoKyRoMFADFAgABAAoKyRoMFADFAgAIAAMKUwL55gByAAABNQAFFAUICgABABEaAA==.Mirrorx:BAACNQAFFH8KAAIBAAUKERoECgBdAQABAAUKERoECgBdAQA1AAQKf0oAAwEACgpBIfkMABsDAAEACgpBIfkMABsDAAgACArODbh6AKoBAAAA.',
Mo='Moosfel:BAAANQAECgQJBgAAAA==.',
Mt='Mtzz:BAAANQAECgYIEQAAAA==.',
Mu='Mudkrab:BAAANQAECgIIAgAAAA==.',
My='Mylie:BAAANQADCgIIAgAAAA==.Mystdragon:BAACNQAFFH8JAAIdAAQKAxP5DQAsAQAdAAQKAxP5DQAsAQA1AAQKfx8AAx0ACQpnH5kMANsCAB0ACQpnH5kMANsCABkABArwGccQACsBAAE1AAUUCAg4AA0AISAA.Mystweaverr:BAACNQAFFH84AAINAAgKISDPAAB+AgANAAgKISDPAAB+AgA1AAQKf1AAAg0ACgotJpcBALUDAA0ACgotJpcBALUDAAAA.',
Na='Naddar:BAABNQAECn8qAAIQAAkKaBhBSQBCAgAQAAkKaBhBSQBCAgAAAA==.Narp:BAAANQADCgQIBAAAAA==.',
Ng='Nganga:BAABNQAECn8wAAMbAAoKaxosRABQAgAbAAoKaxosRABQAgAcAAkKcBnzUAA1AgAAAA==.',
Ni='Nikonii:BAABNQAECn8qAAIFAAkKOBg9FgAwAgAFAAkKOBg9FgAwAgAAAA==.',
Ov='Ovaries:BAAANQADCgUIBQABNQADCgYIBgACAAAAAA==.',
Pa='Paktam:BAAANQAECgYIDAAAAA==.Paladron:BAAANQAECgIIAgAAAA==.Palakudaliaq:BAAANQADCggICAAAAA==.Palaynslea:BAABNQAECn8uAAIQAAoKrA7oXgD8AQAQAAoKrA7oXgD8AQAAAA==.',
Pe='Perceptor:BAAANQAECgIIAgABNQAECgoKNwAeAIgfAA==.',
Pr='Prothero:BAACNQAFFH8LAAIDAAcKdRL4JABgAQADAAcKdRL4JABgAQA1AAQKfz4AAgMACgq5JQ8HAEwDAAMACgq5JQ8HAEwDAAAA.Proyo:BAABNQAECn8mAAIDAAgKfhpiegC4AQADAAgKfhpiegC4AQAAAA==.',
['På']='Påthor:BAABNQAECn8sAAIMAAgKPhhYQwDnAQAMAAgKPhhYQwDnAQAAAA==.',
Ql='Ql:BAAANQADCgYIBgAAAA==.',
Ra='Ragingpally:BAAANQAECgYICQAAAA==.Raijinn:BAABNQAECn8vAAMbAAoKayJ8EgAlAwAbAAoKayJ8EgAlAwAcAAcKlxnvVwAbAgAAAA==.Raizex:BAAANQADCggJDwAAAA==.Ratbarstard:BAACNQAFFH8FAAIDAAIK5AcOYABFAAADAAIK5AcOYABFAAA1AAQKf2EAAgMACgqsHEw0AHICAAMACgqsHEw0AHICAAAA.Rawtoor:BAABNQAECn86AAIXAAoKFR7yBwBSAwAXAAoKFR7yBwBSAwAAAA==.',
Ri='Ridgelock:BAAANQAECgQIBAAAAA==.Ridgemonk:BAAANQAECgIIAgAAAA==.Ridgerock:BAACNQAFFH8KAAIUAAMKFhScFwCwAAAUAAMKFhScFwCwAAA1AAQKfyUAAxQACQrQH4AfALcCABQACQrQH4AfALcCABYAAQo+A/vxACUAAAAA.Riggse:BAAANQAECggIEQABNQAFFAkJIAAJACkhAA==.Riggspal:BAAANQAECggICgABNQAFFAkJIAAJACkhAA==.',
Ro='Roadkill:BAABNQAECn8pAAIUAAoKhB8LEwAUAwAUAAoKhB8LEwAUAwAAAA==.Rolltoor:BAACNQAFFH8MAAIfAAcKzxGJCABcAQAfAAcKzxGJCABcAQA1AAQKfywAAh8ACgrsIgQNAAoDAB8ACgrsIgQNAAoDAAAA.',
Ru='Ruínation:BAAANQAECgUICgABNQAECgoKMAAbAGsaAA==.',
Sa='Sagittarimon:BAAANQAECgMIAwAAAA==.Saiko:BAABNQAECn8hAAMVAAkK0hSjMQAcAgAVAAkKcROjMQAcAgAXAAQKxhI6UADeAAAAAA==.Sansa:BAAANQAECgcIDgAAAA==.Saso:BAACNQAFFH8XAAMDAAYK5RXKJABhAQADAAUK7hTKJABhAQAHAAIKShM3CACYAAA1AAQKf1QABAMACgr6JNwbAGcDAAMACgrYJNwbAGcDAAcABArPI1YXACsBACAAAgqAGTYLAE4AAAAA.Sastroll:BAAANQAECgMIAwABNQAFFAYIFwADAOUVAA==.',
Sc='Scatius:BAAANQADCggICAAAAA==.Scroll:BAABNQAECn8dAAMNAAoK6Q61FAC5AQANAAoK6Q61FAC5AQAfAAMK5AdNRwCKAAAAAA==.',
Se='Sellais:BAAANQADCgYIBgABNQADCgYIBgACAAAAAA==.Sepphiroth:BAAANQADCgcICAAAAA==.Serbitar:BAAANQADCggIGAAAAA==.',
Sh='Shadow:BAABNQAECn8WAAIXAAgKdBapKgDsAQAXAAgKdBapKgDsAQAAAA==.Shakes:BAAANQAECgIIAwAAAA==.Shandrilah:BAABNQAECn8cAAMMAAcK6wxAXwBTAQAMAAcK6wxAXwBTAQALAAIKuAU9bgBMAAAAAA==.Shialebuff:BAABNQAECn8YAAMIAAoKeBiNTAAGAgAIAAoKeBiNTAAGAgABAAEKqRKWcQBEAAAAAA==.Shijin:BAAANQADCgQIBAABNQADCgYIBgACAAAAAA==.',
Si='Silphy:BAAANQAECggIMgABNQAECgoKUAAWAJMfAQ==.Sindar:BAAANQAECgIIAgAAAA==.Siphon:BAAANQADCgcIEAAAAA==.Siscomp:BAABNQAECn96AAIJAAoKXhu3NABsAgAJAAoKXhu3NABsAgAAAA==.Sixth:BAAANQADCggIEAAAAA==.',
Sk='Skoog:BAABNQAECn8dAAIJAAkKfhXyjgD3AQAJAAkKfhXyjgD3AQAAAA==.Sky:BAACNQAFFH8KAAMIAAUK3hOiJgCeAAAIAAUKPBKiJgCeAAAaAAEKsBskBABHAAA1AAQKf0oABAgACgqxJEoLAGgDAAgACgrvIkoLAGgDABoABAruHc4PACwBAAEAAQqhGwBzAEAAAAAA.',
Sn='Snarkshot:BAAANQADCgEIAQAAAA==.Snugglepuff:BAABNQAECn8sAAIJAAoKIxMClwDjAQAJAAoKIxMClwDjAQAAAA==.',
So='Sock:BAAANQAECggIBAAAAA==.Sonarius:BAACNQAFFH8JAAMDAAMKMhjNJADlAAADAAMKMhjNJADlAAAgAAEKCARTAQA/AAA1AAQKfzgABAMACgpVJBwWAHsDAAMACgpVJBwWAHsDACAAAQr9H1MKAF0AAAcAAQqiHmk+AEgAAAAA.',
Sp='Sparkster:BAABNQAECn9FAAIJAAoKmx3XLgCDAgAJAAoKmx3XLgCDAgAAAA==.',
Su='Sundae:BAAANQAECgYIEAAAAA==.',
Sy='Sylvie:BAACNQAFFH8KAAIOAAMK0QxYFwDYAAAOAAMK0QxYFwDYAAA1AAQKfygAAg4ACgoMFehaAGQCAA4ACgoMFehaAGQCAAAA.Syreith:BAAANQADCgYIBgAAAA==.',
['Så']='Sådistic:BAAANQAECgQIBQAAAA==.',
['Sý']='Sýlvanas:BAAANQADCgEIAQAAAA==.',
Ti='Tidders:BAABNQAECn89AAMPAAoKFhypHQBkAgAPAAoKzhupHQBkAgAOAAgKWRK9bADpAQAAAA==.Tikiwoki:BAAANQAECgcIDwAAAA==.Tiramisu:BAABNQAECn8cAAMLAAoKEx3jGAB2AgALAAkKdBzjGAB2AgAMAAMK5w17kACVAAAAAA==.',
Tr='Trilldi:BAAANQADCggJEAAAAA==.Tritone:BAAANQAECgEIAQAAAA==.',
Ty='Tyladrhas:BAABNQAECn8hAAMYAAkK6BtwDACLAQAYAAkK6BtwDACLAQAVAAEK9QnhgQA5AAAAAA==.Tyrismaximus:BAAANQAECgMIBAAAAA==.',
Up='Up:BAABNQAECn9BAAITAAoKhh7aBQBZAgATAAoKhh7aBQBZAgAAAA==.',
Va='Vaelus:BAAANQABCgIIAgAAAA==.Varina:BAAANQAECgIJAgAAAA==.',
Ve='Velorah:BAAANQAECggIEgAAAA==.Velsaert:BAAANQADCgUJBAAAAA==.',
Vo='Volatilegas:BAAANQAECgYIDQAAAA==.',
Vu='Vulken:BAABNQAECn+GAAIOAAoKeh8EIwCzAgAOAAoKeh8EIwCzAgAAAA==.',
Wa='Was:BAAANQAECggIDgABNQAFFAcIJQAOAFwbAA==.',
Wi='Winnìng:BAAANQAECgQICAAAAA==.',
Ya='Yamazaki:BAAANQAECgYIBgAAAA==.',
Ye='Yessuh:BAAANQAECgEIAgAAAA==.',
Za='Zandasham:BAAANQAECggICAAAAA==.',
Zi='Zihon:BAAANQAECgUIBQAAAA==.',
Zo='Zombi:BAAANQAECgEIAQAAAA==.Zombiepanda:BAAANQAECgQIBAAAAA==.Zoomer:BAABNQAECn8nAAIYAAgKTQnsFgA/AQAYAAgKTQnsFgA/AQABNQAFFAUICgABABEaAA==.',
Zu='Zubb:BAAANQADCgUIBQABNQAECggIHgADABIUAA==.Zugg:BAABNQAECn8UAAIhAAcK/BewDwACAgAhAAcK/BewDwACAgABNQAECggIHgADABIUAA==.Zupp:BAABNQAECn8eAAIDAAgKEhSZvQAJAgADAAgKEhSZvQAJAgAAAA==.Zuqq:BAAANQAECgYIDQABNQAECggIHgADABIUAA==.',
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
