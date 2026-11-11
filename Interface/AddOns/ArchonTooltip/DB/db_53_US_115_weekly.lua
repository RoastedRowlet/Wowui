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

local lookup = {'Priest-Shadow','Unknown-Unknown','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Paladin-Retribution','Mage-Frost','Priest-Holy','Warrior-Arms','Warrior-Fury','Druid-Restoration','Druid-Balance','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Holy','Druid-Feral','Paladin-Protection','Evoker-Devastation','DeathKnight-Blood','DemonHunter-Havoc','DeathKnight-Unholy','DemonHunter-Devourer','Evoker-Augmentation','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Druid-Guardian','Monk-Windwalker','Mage-Fire','DemonHunter-Vengeance','Warlock-Destruction',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aamion:BAABNQAECn8jAAIBAAgKIgmjKQAgAQABAAgKIgmjKQAgAQAAAA==.',
Ab='Abo:BAAANQAECggIEwAAAA==.',
Ae='Aeonfire:BAAANQAECgEIAQABNQAECggICgACAAAAAA==.',
Ak='Akame:BAAANQAFFAIIAwAAAA==.',
Al='Alykard:BAABNQAECn8eAAIDAAoK+QX4+gCXAQADAAoK+QX4+gCXAQAAAA==.',
Am='Amateur:BAABNQAECn80AAMEAAoKYhlqEAC0AQAFAAkKoQ6KPQDvAQAEAAoKlxhqEAC0AQAAAA==.Amazing:BAAANQAECgYIBgABNQAECgoKNAAEAGIZAA==.',
An='Andronicas:BAABNQAECn8cAAIGAAkK/AoA4QBZAQAGAAkK/AoA4QBZAQAAAA==.Aneira:BAABNQAECn86AAIHAAoKjg/pCgAXAgAHAAoKjg/pCgAXAgAAAA==.',
As='Asaki:BAAANQADCggICAAAAA==.Aspect:BAAANQAECgQIBAABNQAECggICgACAAAAAA==.',
Av='Avi:BAABNQAECn8iAAIIAAoKMwkyWwC7AQAIAAoKMwkyWwC7AQABNQAECgoKdAAJAF4bAA==.',
Ba='Baesuzy:BAABNQAECn8rAAIDAAgK1A8xjQB5AQADAAgK1A8xjQB5AQAAAA==.Baragas:BAAANQAECgUIDQAAAA==.',
Be='Belle:BAAANQADCgcICAAAAA==.Benkei:BAABNQAECn8cAAIKAAkK9BuoCQDmAQAKAAkK9BuoCQDmAQAAAA==.Berzerker:BAAANQABCgYICgAAAA==.',
Bg='Bgc:BAAANQABCgYICQAAAA==.',
Bl='Blackds:BAAANQABCgQIBAAAAA==.Blain:BAABNQAECn8UAAIJAAgK4RPcqgCyAQAJAAgK4RPcqgCyAQAAAA==.',
Bo='Bosammana:BAAANQADCgUIBwAAAA==.',
Bu='Bubblôseven:BAAANQAECggICgAAAA==.Budin:BAAANQADCgIIAgAAAA==.',
Ca='Cannibal:BAABNQAECn8iAAILAAkKMh29FgBLAgALAAkKMh29FgBLAgAAAA==.Capri:BAABNQAECn8rAAIMAAkKtQriVwB2AQAMAAkKtQriVwB2AQAAAA==.Casiopia:BAAANQADCgQIBQAAAA==.',
Ch='Choomoo:BAABNQAECn81AAILAAoKsR1XDQDdAgALAAoKsR1XDQDdAgABNQAFFAQIBwANAAwIAA==.Chopstix:BAAANQADCgYIDAAAAA==.Chromie:BAAANQAECggICwAAAA==.',
Co='Comet:BAAANQAECgcICQAAAA==.',
Cr='Crikey:BAABNQAECn9BAAMOAAoKXh1NMgBsAgAOAAoKXh1NMgBsAgAPAAYKhg3lRQArAQAAAA==.',
Cv='Cvdruid:BAAANQADCgUIBQAAAA==.',
Da='Daga:BAAANQAECggIDwAAAA==.',
De='Definitely:BAACNQAFFH8GAAMHAAMK8xfzBgCaAAAHAAMK8xfzBgCaAAADAAEKphCERgBJAAA1AAQKf1IAAgcACgpvI3wCAEIDAAcACgpvI3wCAEIDAAAA.Demonich:BAAANQADCgUIBQAAAA==.Desaix:BAABNQAECn8ZAAIFAAcKEBUDHwDYAQAFAAcKEBUDHwDYAQAAAA==.Desariana:BAABNQAECn8nAAIGAAoKsBLvfgArAgAGAAoKsBLvfgArAgAAAA==.Devimon:BAAANQAECgQIBAAAAA==.Dewasixseven:BAAANQADCgQIBAAAAA==.',
Dh='Dhunt:BAAANQABCgMIAQAAAA==.',
Do='Dormas:BAAANQAECgcIDQAAAA==.Doug:BAAANQAECgQICAAAAA==.',
Dr='Drakeon:BAAANQADCgcJBwABNQAECgoKdAAJAF4bAA==.Drizzts:BAAANQADCgQIBQAAAA==.',
Dw='Dwarfpally:BAAANQAECgMIBgAAAA==.',
Ei='Eira:BAAANQADCgMIAwABNQADCgYIBgACAAAAAA==.',
El='Eldh:BAAANQADCgEIAQAAAA==.Eldk:BAAANQAECggIEAAAAA==.Elisoly:BAABNQAECn8sAAIQAAgKbxNWXwCIAQAQAAgKbxNWXwCIAQAAAA==.',
Em='Emrald:BAAANQAECgIIAwAAAA==.',
En='Endlessly:BAABNQAECn8oAAIRAAoKzB6EBgAFAwARAAoKzB6EBgAFAwAAAA==.',
Er='Erritwo:BAAANQAECgQIBAAAAA==.',
Et='Etro:BAABNQAECn89AAISAAoKQiUEBgDvAgASAAoKQiUEBgDvAgAAAA==.',
Ev='Evoslex:BAABNQAECn9LAAITAAoKgSOkAQAeAwATAAoKgSOkAQAeAwAAAA==.',
Ex='Exo:BAECNQAFFH8SAAIUAAcKgxezDACJAQAUAAcKgxezDACJAQA1AAQKf1MAAhQACgqWJEYJAG4DABQACgqWJEYJAG4DAAAA.',
Fa='Facerolleh:BAACNQAFFH8mAAIJAAgKARtXAwCxAgAJAAgKARtXAwCxAgA1AAQKf0cAAgkACgoxJnQEAGkDAAkACgoxJnQEAGkDAAAA.Fatedx:BAABNQAECn8mAAIVAAoKlAz2KwCaAQAVAAoKlAz2KwCaAQAAAA==.',
Fe='Feelgoodinc:BAAANQAECgMIAwAAAA==.Feint:BAACNQAFFH8FAAMEAAEKVhTmEABKAAAEAAEKVhTmEABKAAAFAAEKRQx+JABJAAA1AAQKf3wAAwQACgrGIWYIAFYCAAUACQqIHL0fAIACAAQACgo3HmYIAFYCAAAA.',
Fi='Fistdaddy:BAAANQAECgUIBQAAAA==.Fiz:BAACNQAFFH8HAAIJAAQKbg85JgDPAAAJAAQKbg85JgDPAAA1AAQKf1gAAgkACgqsI3UNACMDAAkACgqsI3UNACMDAAAA.',
Fl='Flora:BAAANQADCgQIBAAAAA==.',
Fu='Fuknazum:BAAANQAECgIIAgAAAA==.',
Ga='Galara:BAAANQAECgQIBQAAAA==.',
Gr='Grandpriest:BAAANQAECgUIBwABNQAECggIDQACAAAAAA==.Grimoirsingh:BAAANQAECgEIAQAAAA==.Grimveil:BAABNQAECn9MAAIWAAoKpyMwBQAfAwAWAAoKpyMwBQAfAwAAAA==.',
['Gô']='Gôku:BAAANQADCgYIBgAAAA==.',
Ha='Harafar:BAACNQAFFH8QAAMMAAYKlwX1DwDlAAAMAAUKlwX1DwDlAAALAAEKXQOtFwA4AAA1AAQKf0UAAgwACgr8GlkUAGkCAAwACgr8GlkUAGkCAAAA.',
He='Hellbourne:BAAANQAECgUICgAAAA==.',
Hi='Hibiki:BAAANQADCgIIAgAAAA==.',
Ho='Hogreveal:BAAANQAECgUIAwAAAA==.Hollykibbler:BAAANQAECgQIBAAAAA==.Holyclstrfuk:BAAANQADCgYIBgAAAA==.Horsé:BAAANQADCggIEgAAAA==.',
Hu='Huntslex:BAAANQAECgYIEAABNQAECgoKSwATAIEjAA==.',
Il='Illidam:BAABNQAECn8XAAIXAAkKRxMPNQCbAQAXAAkKRxMPNQCbAQAAAA==.',
It='Itskiohte:BAAANQAECgcIEAAAAA==.',
Ja='Jaedaa:BAAANQAECgcJBwABNQAFFAUIEQAUAGYWAA==.Jaedamend:BAABNQAECn88AAMIAAoKqCWpAQAmBAAIAAoKqCWpAQAmBAABAAcKfhH7LgCsAQABNQAFFAUIEQAUAGYWAA==.',
Je='Jertbirt:BAAANQAECgEIAQAAAA==.',
Ka='Kalzaketh:BAABNQAECn8zAAIYAAgKYgv8DQBqAQAYAAgKYgv8DQBqAQAAAA==.Kashari:BAAANQAECgQICwABNQAECgoKiQAIAP0YAA==.Katali:BAAANQAECgUIDgAAAA==.Kaypop:BAAANQADCgQIBwABNQAFFAcIGgAOAHUUAA==.Kazo:BAACNQAFFH8MAAIIAAQKiBdcFwA6AQAIAAQKiBdcFwA6AQA1AAQKf0kABAgACgq/IosZAPkCAAgACgq/IosZAPkCAAEACArADSMeAIUBABkAAQpoI3cfAGUAAAAA.Kazuggar:BAACNQAFFH8nAAIaAAYKVRj6CgCeAQAaAAYKVRj6CgCeAQA1AAQKf1UAAxoACgqvJEYOAE8DABoACgqvJEYOAE8DABsACQoFFQhAAL0BAAAA.Kazzn:BAABNQAECn8jAAMLAAoKtxovFQBiAgALAAoKtxovFQBiAgAMAAEKYwVKtgAsAAABNQAFFAQIDAAIAIgXAA==.',
Ke='Kell:BAAANQAECgYICAAAAA==.',
Ki='Kibbler:BAAANQAECgIIAwAAAA==.Killerman:BAAANQAECgUIBQAAAA==.',
Kn='Knucklez:BAAANQADCgYIAwAAAA==.',
Ko='Korosensei:BAAANQAECggICAAAAA==.',
Ku='Kucabara:BAAANQAECgQIBQABNQAECgUIDQACAAAAAA==.Kungpew:BAAANQAECgIIAgAAAA==.',
Kw='Kwichang:BAABNQAECn8rAAMHAAoKjRGKEABmAQADAAkKlw67fwCYAQAHAAcKwg+KEABmAQAAAA==.',
Ky='Kyndariae:BAABNQAECn8jAAIIAAkKfA2piwBzAQAIAAkKfA2piwBzAQAAAA==.',
La='Lagman:BAAANQADCgEIAQAAAA==.',
Li='Lickynose:BAABNQAECn8/AAIDAAoKbSLoJgCYAgADAAoKbSLoJgCYAgAAAA==.',
Ma='Mahou:BAAANQAECgUIBwAAAA==.Malcador:BAABNQAECn8iAAIMAAoKyhh9FwBEAgAMAAoKyhh9FwBEAgAAAA==.Mantisar:BAABNQAECn8dAAIGAAkKDgox4QBZAQAGAAkKDgox4QBZAQAAAA==.Marmite:BAABNQAECn8lAAIcAAgK/hYJEADvAQAcAAgK/hYJEADvAQAAAA==.Mayene:BAAANQAECgEIAQABNQAECggICQACAAAAAA==.',
Me='Menethil:BAAANQABCgIIAgAAAA==.',
Mi='Mightyhunt:BAABNQAECn8ZAAIOAAoKsBvCYgDoAQAOAAoKsBvCYgDoAQAAAA==.Mirrorimage:BAABNQAECn8qAAMBAAoKyRoMFADFAgABAAoKyRoMFADFAgAIAAMKUwL55gByAAABNQAFFAQICQABAIYYAA==.Mirrorx:BAACNQAFFH8JAAIBAAQKhhgECgBdAQABAAQKhhgECgBdAQA1AAQKf0UAAwEACgpBIfkMABsDAAEACgpBIfkMABsDAAgACArODbh6AKoBAAAA.',
Mo='Moosfel:BAAANQAECgQJBgAAAA==.',
Mt='Mtzz:BAAANQAECgYIEQAAAA==.',
Mu='Mudkrab:BAAANQAECgIIAgAAAA==.',
My='Mylie:BAAANQADCgIIAgAAAA==.Mystdragon:BAACNQAFFH8JAAIcAAQKAxP5DQAsAQAcAAQKAxP5DQAsAQA1AAQKfx8AAxwACQpnH5kMANsCABwACQpnH5kMANsCABgABArwGccQACsBAAE1AAUUBwg3AA0AlSEA.Mystweaverr:BAACNQAFFH83AAINAAcKlSHPAAB+AgANAAcKlSHPAAB+AgA1AAQKf1AAAg0ACgotJpcBALUDAA0ACgotJpcBALUDAAAA.',
Na='Naddar:BAABNQAECn8qAAIQAAkKaBhBSQBCAgAQAAkKaBhBSQBCAgAAAA==.Narp:BAAANQADCgQIBAAAAA==.',
Ng='Nganga:BAABNQAECn8rAAMaAAoKaxosRABQAgAaAAoKaxosRABQAgAbAAgKShjzUAA1AgAAAA==.',
Ni='Nikonii:BAABNQAECn8qAAIFAAkKOBg9FgAwAgAFAAkKOBg9FgAwAgAAAA==.',
Ov='Ovaries:BAAANQADCgUIBQABNQADCgYIBgACAAAAAA==.',
Pa='Paktam:BAAANQAECgYIDAAAAA==.Paladron:BAAANQAECgIIAgAAAA==.Palakudaliaq:BAAANQADCggICAAAAA==.Palaynslea:BAABNQAECn8uAAIQAAoKrA7oXgD8AQAQAAoKrA7oXgD8AQAAAA==.',
Pe='Perceptor:BAAANQAECgIIAgABNQAECgoKNwAdAIgfAA==.',
Pr='Prothero:BAACNQAFFH8KAAIDAAYKDxD4JABgAQADAAYKDxD4JABgAQA1AAQKfz0AAgMACgq5JfwFAFADAAMACgq5JfwFAFADAAAA.Proyo:BAABNQAECn8mAAIDAAgKfhqUcQC6AQADAAgKfhqUcQC6AQAAAA==.',
['På']='Påthor:BAABNQAECn8sAAIMAAgKPhiONABSAQAMAAgKPhiONABSAQAAAA==.',
Ql='Ql:BAAANQADCgYIBgAAAA==.',
Ra='Ragingpally:BAAANQAECgMIAwAAAA==.Raijinn:BAABNQAECn8vAAMaAAoKayLoDwAtAwAaAAoKayLoDwAtAwAbAAcKlxnvVwAbAgAAAA==.Raizex:BAAANQADCggJDwAAAA==.Ratbarstard:BAACNQAFFH8FAAIDAAIK5AcEUAAAAAADAAIK5AcEUAAAAAA1AAQKf2EAAgMACgqsHPMvAHUCAAMACgqsHPMvAHUCAAAA.Rawtoor:BAABNQAECn86AAIXAAoKFR7yBwBSAwAXAAoKFR7yBwBSAwAAAA==.',
Ri='Ridgelock:BAAANQAECgQIBAAAAA==.Ridgemonk:BAAANQAECgIIAgAAAA==.Ridgerock:BAACNQAFFH8KAAIUAAMKFhRqFAC3AAAUAAMKFhRqFAC3AAA1AAQKfyQAAxQACQrQH4AfALcCABQACQrQH4AfALcCABYAAQo+A/vxACUAAAAA.Riggse:BAAANQAECggIEQABNQAFFAgIHwAJAGkkAA==.Riggspal:BAAANQAECggICgABNQAFFAgIHwAJAGkkAA==.',
Ro='Roadkill:BAABNQAECn8pAAIUAAoKhB8LEwAUAwAUAAoKhB8LEwAUAwAAAA==.Rolltoor:BAACNQAFFH8MAAIeAAcKzxGJCABcAQAeAAcKzxGJCABcAQA1AAQKfywAAh4ACgrsIgQNAAoDAB4ACgrsIgQNAAoDAAAA.',
Ru='Ruínation:BAAANQAECgUICgABNQAECgoKKwAaAGsaAA==.',
Sa='Sagittarimon:BAAANQAECgMIAwAAAA==.Saiko:BAABNQAECn8hAAMVAAkK0hSjMQAcAgAVAAkKcROjMQAcAgAXAAQKxhI6UADeAAAAAA==.Sansa:BAAANQAECgcIDgAAAA==.Saso:BAACNQAFFH8XAAMDAAYK5RXKJABhAQADAAUK7hTKJABhAQAHAAIKShM3CACYAAA1AAQKf1QABAMACgr6JNwbAGcDAAMACgrYJNwbAGcDAAcABArPI9wUAC0BAB8AAgqAGRYKAE4AAAAA.Sastroll:BAAANQAECgMIAwABNQAFFAYIFwADAOUVAA==.',
Sc='Scatius:BAAANQADCggICAAAAA==.Scroll:BAABNQAECn8dAAMNAAoK6Q70EgC/AQANAAoK6Q70EgC/AQAeAAMK5AdQQwCKAAAAAA==.',
Se='Sellais:BAAANQADCgYIBgABNQADCgYIBgACAAAAAA==.Sepphiroth:BAAANQADCgQIBAAAAA==.Serbitar:BAAANQADCggIGAAAAA==.',
Sh='Shadow:BAABNQAECn8WAAIXAAgKdBapKgDsAQAXAAgKdBapKgDsAQAAAA==.Shakes:BAAANQAECgIIAwAAAA==.Shandrilah:BAABNQAECn8aAAMMAAcK6wxAXwBTAQAMAAcK6wxAXwBTAQALAAIKuAU9bgBMAAAAAA==.Shialebuff:BAABNQAECn8YAAMIAAoKeBh3RAARAgAIAAoKeBh3RAARAgABAAEKqRKWcQBEAAAAAA==.Shijin:BAAANQADCgQIBAABNQADCgYIBgACAAAAAA==.',
Si='Silphy:BAAANQAECggILwABNQAECgoKTQAWAJMfAQ==.Sindar:BAAANQAECgIIAgAAAA==.Siphon:BAAANQADCgcIEAAAAA==.Siscomp:BAABNQAECn90AAIJAAoKXhtrMQBsAgAJAAoKXhtrMQBsAgAAAA==.Sixth:BAAANQADCggIEAAAAA==.',
Sk='Skoog:BAABNQAECn8dAAIJAAkKfhXyjgD3AQAJAAkKfhXyjgD3AQAAAA==.Sky:BAACNQAFFH8KAAMIAAUK3hOiJgCeAAAIAAUKOxKiJgCeAAAZAAEKsBskBABHAAA1AAQKf0oABAgACgqxJEoLAGgDAAgACgrvIkoLAGgDABkABAruHc4PACwBAAEAAQqhGwBzAEAAAAAA.',
Sn='Snarkshot:BAAANQADCgEIAQAAAA==.Snugglepuff:BAABNQAECn8nAAIJAAoK5hIClwDjAQAJAAoK5hIClwDjAQAAAA==.',
So='Sock:BAAANQAECggIBAAAAA==.Sonarius:BAACNQAFFH8JAAMDAAMKMhguHwDyAAADAAMKMhguHwDyAAAfAAEKCARTAQA/AAA1AAQKfzgABAMACgpVJBwWAHsDAAMACgpVJBwWAHsDAB8AAQr9H1MKAF0AAAcAAQqiHmk+AEgAAAAA.',
Sp='Sparkster:BAABNQAECn9FAAIJAAoKmx2RKgCJAgAJAAoKmx2RKgCJAgAAAA==.',
Su='Sundae:BAAANQAECgYIEAAAAA==.',
Sy='Sylvie:BAACNQAFFH8KAAIOAAMK0Qz3FADaAAAOAAMK0Qz3FADaAAA1AAQKfygAAg4ACgoMFehaAGQCAA4ACgoMFehaAGQCAAAA.Syreith:BAAANQADCgYIBgAAAA==.',
['Så']='Sådistic:BAAANQAECgQIBQAAAA==.',
['Sý']='Sýlvanas:BAAANQADCgEIAQAAAA==.',
Ti='Tidders:BAABNQAECn84AAMPAAoKDxypHQBkAgAPAAoKzhupHQBkAgAOAAgKAw5weQCuAQAAAA==.Tikiwoki:BAAANQAECgcIDwAAAA==.Tiramisu:BAABNQAECn8cAAMLAAoKEx3jGAB2AgALAAkKdBzjGAB2AgAMAAMK5w17kACVAAAAAA==.',
Tr='Trilldi:BAAANQADCggJEAAAAA==.Tritone:BAAANQAECgEIAQAAAA==.',
Ty='Tyladrhas:BAABNQAECn8fAAMgAAkK5Bs7CwCLAQAgAAkK5Bs7CwCLAQAVAAEK9QlaewA5AAAAAA==.Tyrismaximus:BAAANQAECgMIBAAAAA==.',
Up='Up:BAABNQAECn88AAITAAoKhR0+BgA2AgATAAoKhR0+BgA2AgAAAA==.',
Va='Vaelus:BAAANQABCgIIAgAAAA==.Varina:BAAANQAECgIJAgAAAA==.',
Ve='Velorah:BAAANQAECgcIDwAAAA==.Velsaert:BAAANQADCgUJBAAAAA==.',
Vo='Volatilegas:BAAANQAECgYIDQAAAA==.',
Vu='Vulken:BAABNQAECn+GAAIOAAoKeh/DHQC+AgAOAAoKeh/DHQC+AgAAAA==.',
Wa='Was:BAAANQAECggIDgABNQAFFAcIJQAOAFwbAA==.',
Wi='Winnìng:BAAANQAECgQICAAAAA==.',
Ya='Yamazaki:BAAANQAECgYIBgAAAA==.',
Ye='Yessuh:BAAANQAECgEIAgAAAA==.',
Za='Zandasham:BAAANQAECggICAAAAA==.',
Zi='Zihon:BAAANQAECgUIBQAAAA==.',
Zo='Zombi:BAAANQAECgEIAQAAAA==.Zombiepanda:BAAANQAECgQIBAAAAA==.Zoomer:BAABNQAECn8nAAIgAAgKTQnsFgA/AQAgAAgKTQnsFgA/AQABNQAFFAQICQABAIYYAA==.',
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
