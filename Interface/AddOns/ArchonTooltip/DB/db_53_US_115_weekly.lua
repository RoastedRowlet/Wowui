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

local lookup = {'Priest-Shadow','Unknown-Unknown','Mage-Arcane','Rogue-Assassination','Mage-Frost','Warrior-Arms','Druid-Restoration','Druid-Balance','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Subtlety','Paladin-Retribution','Paladin-Holy','Druid-Feral','Paladin-Protection','Evoker-Devastation','DeathKnight-Blood','DemonHunter-Havoc','DeathKnight-Unholy','Priest-Holy','Evoker-Augmentation','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Druid-Guardian','DemonHunter-Devourer','Monk-Windwalker','DeathKnight-Frost','Mage-Fire','DemonHunter-Vengeance','Warlock-Destruction',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aamion:BAABNQAECn8bAAIBAAUKPwnyTADhAAABAAUKPwnyTADhAAAAAA==.',
Ab='Abo:BAAANQAECggIEQAAAA==.',
Ae='Aeonfire:BAAANQAECgEIAQABNQAECggICgACAAAAAA==.',
Ak='Akame:BAAANQAFFAMIAgAAAA==.',
Al='Alykard:BAABNQAECn8eAAIDAAoK+QX4+gCXAQADAAoK+QX4+gCXAQAAAA==.',
Am='Amateur:BAABNQAECn8jAAIEAAoKpRf1GwCeAgAEAAoKpRf1GwCeAgAAAA==.Amazing:BAAANQAECgYIBgABNQAECgoKIwAEAKUXAA==.',
An='Andronicas:BAAANQAECgcIEAAAAA==.Aneira:BAABNQAECn8xAAIFAAkKeBDpCgAXAgAFAAkKeBDpCgAXAgAAAA==.',
As='Asaki:BAAANQADCggICAAAAA==.Aspect:BAAANQAECgQIBAABNQAECggICgACAAAAAA==.',
Av='Avi:BAAANQAECgcIDwABNQAECgoKXgAGAKoZAA==.',
Ba='Baesuzy:BAABNQAECn8eAAIDAAcKJw9P8wClAQADAAcKJw9P8wClAQAAAA==.Baragas:BAAANQAECgUIEAAAAA==.',
Be='Belle:BAAANQADCgcICAAAAA==.Benkei:BAAANQAECgUIEAAAAA==.',
Bg='Bgc:BAAANQAECgEIAgAAAA==.',
Bl='Blackds:BAAANQABCgQIBAAAAA==.Blain:BAAANQAECggIDgAAAA==.',
Bo='Bosammana:BAAANQADCgMJAwAAAA==.',
Bu='Bubblôseven:BAAANQAECgcIBwAAAA==.Budin:BAAANQADCgIIAgAAAA==.',
Ca='Cannibal:BAABNQAECn8dAAIHAAgKQx3XBAAaAgAHAAgKQx3XBAAaAgAAAA==.Capri:BAABNQAECn8nAAIIAAcKsAviVwB2AQAIAAcKsAviVwB2AQAAAA==.Casiopia:BAAANQADCgQIBQAAAA==.',
Ch='Choomoo:BAABNQAECn8hAAIHAAkKwxsIBwDWAQAHAAkKwxsIBwDWAQABNQAFFAQIBwAJAAwIAA==.Chopstix:BAAANQADCgYIDAAAAA==.Chromie:BAAANQAECggICwAAAA==.',
Cr='Crikey:BAABNQAECn84AAMKAAoKNxuYBQB1AgAKAAoKNxuYBQB1AgALAAYKhg3lRQArAQAAAA==.',
Cv='Cvdruid:BAAANQADCgUIBQAAAA==.',
Da='Daga:BAAANQAECgcICgAAAA==.',
De='Definitely:BAABNQAECn86AAIFAAoK/yB8AgBCAwAFAAoK/yB8AgBCAwAAAA==.Desaix:BAABNQAECn8ZAAIMAAcKEBUDHwDYAQAMAAcKEBUDHwDYAQAAAA==.Desariana:BAABNQAECn8iAAINAAoKsBLvfgArAgANAAoKsBLvfgArAgAAAA==.Devimon:BAAANQAECgQIBQAAAA==.Dewasixseven:BAAANQADCgQIBAAAAA==.',
Dh='Dhunt:BAAANQABCgMIAQAAAA==.',
Do='Dormas:BAAANQAECgYIDQAAAA==.Doug:BAAANQAECgQICAAAAA==.',
Dr='Drakeon:BAAANQADCgcJBwABNQAECgoKXgAGAKoZAA==.Drizzts:BAAANQAECgEIBAAAAA==.',
Dw='Dwarfpally:BAAANQAECgMIBgAAAA==.',
El='Eldh:BAAANQADCgEIAQAAAA==.Eldk:BAAANQAECggIEQAAAA==.Elisoly:BAABNQAECn8kAAIOAAgKUBNRKgA5AQAOAAgKUBNRKgA5AQAAAA==.',
Em='Emrald:BAAANQAECgIIAwAAAA==.',
En='Endlessly:BAABNQAECn8dAAIPAAoKLhyEBgAFAwAPAAoKLhyEBgAFAwAAAA==.',
Er='Errimage:BAAANQAECgEIAgABNQAECgQIBQACAAAAAA==.Erritwo:BAAANQAECgQIBQAAAA==.',
Et='Etro:BAABNQAECn8sAAIQAAoK9SNbAQCLAgAQAAoK9SNbAQCLAgAAAA==.',
Ev='Evelinar:BAAANQADCggIEwAAAA==.Evoslex:BAABNQAECn8yAAIRAAoKXyFvAwBxAwARAAoKXyFvAwBxAwAAAA==.',
Ex='Exo:BAECNQAFFH8RAAISAAYKlhmzDACJAQASAAYKlhmzDACJAQA1AAQKf00AAhIACgouI0YJAG4DABIACgouI0YJAG4DAAAA.',
Fa='Facerolleh:BAACNQAFFH8fAAIGAAcK4x1XAwCxAgAGAAcK4x1XAwCxAgA1AAQKfzgAAgYACgqZI50TAG0DAAYACgqZI50TAG0DAAAA.Fatedx:BAABNQAECn8bAAITAAgKfgu6IgDrAAATAAgKfgu6IgDrAAAAAA==.',
Fe='Feelgoodinc:BAAANQAECgMIAwAAAA==.',
Fi='Fistdaddy:BAAANQAECgUIBQAAAA==.Fiz:BAACNQAFFH8GAAIGAAMKvAw5JgDPAAAGAAMKvAw5JgDPAAA1AAQKfzQAAgYACgoqHcIMAPgBAAYACgoqHcIMAPgBAAAA.',
Fu='Fuknazum:BAAANQAECgIIAgAAAA==.',
Ga='Galara:BAAANQAECgIIAgAAAA==.',
Gi='Giveroflife:BAAANQAECgEIAgAAAA==.',
Gr='Grandpriest:BAAANQAECgUICAABNQAECggIFQANAMQMAA==.Grimoirsingh:BAAANQAECgEIAQAAAA==.Grimveil:BAABNQAECn81AAIUAAoKziH3DwA3AwAUAAoKziH3DwA3AwAAAA==.',
['Gô']='Gôku:BAAANQADCgYIBgAAAA==.',
Ha='Harafar:BAACNQAFFH8LAAMIAAUKOQZPCQDBAAAIAAQKOQZPCQDBAAAHAAEKSgNhDAA8AAA1AAQKfy0AAggACgpVFx4rAIACAAgACgpVFx4rAIACAAAA.',
He='Hellbourne:BAAANQAECgUICgAAAA==.',
Hi='Hibiki:BAAANQADCgIIAgAAAA==.',
Ho='Hogreveal:BAAANQAECgQIBAAAAA==.Hollykibbler:BAAANQAECgQIBAAAAA==.Holyclstrfuk:BAAANQADCgYIBgAAAA==.Horsé:BAAANQADCggIEgAAAA==.',
Hu='Huntslex:BAAANQAECgYICgABNQAECgoKMgARAF8hAA==.',
Il='Illidam:BAAANQAECggIDQAAAA==.',
It='Itskiohte:BAAANQAECgYJEwAAAA==.',
Ja='Jaedaa:BAAANQAECgcJBwABNQAFFAUIEQASAGYWAA==.Jaedamend:BAABNQAECn8eAAMVAAoKUCEyAQCmAwAVAAkKhCMyAQCmAwABAAcKfhH7LgCsAQABNQAFFAUIEQASAGYWAA==.',
Je='Jertbirt:BAAANQAECgEIAQAAAA==.',
Ka='Kaelthuzzad:BAAANQAECgEIAQAAAA==.Kalzaketh:BAABNQAECn8wAAIWAAcKFw38DQBqAQAWAAcKFw38DQBqAQAAAA==.Kashari:BAAANQAECgQIDQABNQAECgoKYQAVAI8SAA==.Katali:BAAANQAECgQIBgAAAA==.Kaypop:BAAANQADCgQIBwABNQAFFAcIGAAKAHUUAA==.Kazo:BAACNQAFFH8MAAIVAAQKiBdGCQA1AQAVAAQKiBdGCQA1AQA1AAQKfzIABBUACgp9IHcIAGACABUACgp9IHcIAGACABcAAQpoI3cfAGUAAAEAAQpQEwd1ADwAAAAA.Kazuggar:BAACNQAFFH8jAAIYAAUK+xn6CgCeAQAYAAUK+xn6CgCeAQA1AAQKf0YAAxgACgrVI0YOAE8DABgACgrVI0YOAE8DABkAAgqDFlENAXEAAAAA.Kazzn:BAABNQAECn8YAAMHAAgKRBhHIQAeAgAHAAgKRBhHIQAeAgAIAAEKYwVKtgAsAAAAAA==.',
Ke='Kell:BAAANQAECgYICgAAAA==.',
Ki='Kibbler:BAAANQAECgIIAwAAAA==.Killerman:BAAANQAECgUIBQAAAA==.',
Ku='Kucabara:BAAANQAECgQIBgABNQAECgUIEAACAAAAAA==.Kungpew:BAAANQAECgIIAgAAAA==.',
Kw='Kwichang:BAAANQAECgUIEQAAAA==.',
Ky='Kyndariae:BAABNQAECn8fAAIVAAcKdg2piwBzAQAVAAcKdg2piwBzAQAAAA==.',
La='Lagman:BAAANQADCgEIAQAAAA==.',
Li='Lickynose:BAABNQAECn8sAAIDAAoKdh41EgDVAQADAAoKdh41EgDVAQAAAA==.',
Ma='Mahou:BAAANQAECgQIBQAAAA==.Malcador:BAAANQAFFAEIAQAAAA==.Mantisar:BAABNQAECn8dAAINAAkKDgqAgADLAAANAAkKDgqAgADLAAAAAA==.Marmite:BAABNQAECn8YAAIaAAgK6BQXAwDtAQAaAAgK6BQXAwDtAQAAAA==.Mayene:BAAANQAECgEIAQAAAA==.Mazoku:BAAANQAECgEIAQAAAA==.',
Mi='Mightyhunt:BAAANQAECgcIEgAAAA==.Miracoli:BAAANQAECgEIAQAAAA==.Mirrorimage:BAABNQAECn8pAAMBAAoKyRrmAgD9AQABAAoKyRrmAgD9AQAVAAMKUwL55gByAAABNQAFFAQICQABAIYYAA==.Mirrorx:BAACNQAFFH8JAAIBAAQKhhgECgBdAQABAAQKhhgECgBdAQA1AAQKfzQAAwEACgq5IBUFAK0BAAEACgq5IBUFAK0BABUACArODbh6AKoBAAAA.',
Mo='Moosfel:BAAANQAECgQJBgAAAA==.',
Mt='Mtzz:BAAANQAECgUIEAAAAA==.',
Mu='Mudkrab:BAAANQAECgEIAQAAAA==.',
My='Mylie:BAAANQADCgIIAgAAAA==.Mystdragon:BAACNQAFFH8JAAIaAAQKAxP5DQAsAQAaAAQKAxP5DQAsAQA1AAQKfx8AAxoACQpnH5kMANsCABoACQpnH5kMANsCABYABArwGTsEAPcAAAE1AAUUBgg1AAkA8SQA.Mystweaverr:BAACNQAFFH81AAIJAAYK8STPAAB+AgAJAAYK8STPAAB+AgA1AAQKfzwAAgkACgotJpcBALUDAAkACgotJpcBALUDAAAA.',
Na='Naddar:BAABNQAECn8qAAIOAAkKaBhBSQBCAgAOAAkKaBhBSQBCAgAAAA==.Narp:BAAANQADCgQIBAAAAA==.',
Ng='Nganga:BAABNQAECn8kAAMZAAoKGxnzUAA1AgAZAAcKeBvzUAA1AgAYAAoKzBmYFACvAQAAAA==.',
Ni='Nikonii:BAABNQAECn8bAAIMAAcKIxs9FgAwAgAMAAcKIxs9FgAwAgAAAA==.',
Ov='Ovaries:BAAANQADCgUIBQABNQADCgYIBgACAAAAAA==.',
Pa='Paktam:BAAANQAECgYIDAAAAA==.Paladron:BAAANQAECgIIAgAAAA==.Palakudaliaq:BAAANQAECgEIAQAAAA==.Palaynslea:BAABNQAECn8uAAIOAAoKrA7oXgD8AQAOAAoKrA7oXgD8AQAAAA==.Parse:BAABNQAECn9ZAAMEAAoKVxtBAgBOAgAEAAoK1hpBAgBOAgAMAAUKeh22JQCZAQAAAA==.',
Pe='Perceptor:BAAANQAECgIIAgABNQAECgoKLwAbAIMdAA==.',
Pr='Prothero:BAACNQAFFH8JAAIDAAUKexD4JABgAQADAAUKexD4JABgAQA1AAQKfykAAgMACgqxI7EvAC0DAAMACgqxI7EvAC0DAAAA.Proyo:BAABNQAECn8dAAIDAAcKCRkiKQB1AQADAAcKCRkiKQB1AQAAAA==.',
['På']='Påthor:BAABNQAECn8kAAIIAAgKCRZxDwBfAQAIAAgKCRZxDwBfAQAAAA==.',
Ql='Ql:BAAANQADCgYIBgAAAA==.',
Ra='Raijinn:BAABNQAECn8kAAMYAAgKTSI+LgCpAgAYAAcKIiM+LgCpAgAZAAcKlxnvVwAbAgAAAA==.Raizex:BAAANQAECgEIAQAAAA==.Ratbarstard:BAABNQAECn9MAAIDAAkK8Bz1XwC/AgADAAkK8Bz1XwC/AgAAAA==.Rawtoor:BAABNQAECn8wAAIcAAoKiBzyBwBSAwAcAAoKiBzyBwBSAwAAAA==.',
Ri='Ridgelock:BAAANQAECgIIAgAAAA==.Ridgemonk:BAAANQAECgIIAgAAAA==.Ridgerock:BAACNQAFFH8FAAISAAMKUhHgCADCAAASAAMKUhHgCADCAAA1AAQKfx4AAxIACQpIH4AfALcCABIACQpIH4AfALcCABQAAQo+A/vxACUAAAAA.Riggse:BAAANQAECggIEQABNQAFFAgIHwAGAGkkAA==.Riggspal:BAAANQAECggICgABNQAFFAgIHwAGAGkkAA==.',
Ro='Roadkill:BAABNQAECn8lAAISAAoKhB8LEwAUAwASAAoKhB8LEwAUAwAAAA==.Rolltoor:BAACNQAFFH8LAAIdAAYKcRKJCABcAQAdAAYKcRKJCABcAQA1AAQKfyoAAh0ACgpyIQQNAAoDAB0ACgpyIQQNAAoDAAAA.',
Ru='Ruínation:BAAANQAECgQIBwABNQAECgoKJAAZABsZAA==.',
Sa='Sagittarimon:BAAANQAECgIIAgAAAA==.Saiko:BAABNQAECn8hAAMTAAkK0hSjMQAcAgATAAkKcROjMQAcAgAcAAQKxhI6UADeAAAAAA==.Sansa:BAAANQAECgcIDwAAAA==.Saso:BAACNQAFFH8XAAMDAAYK5RXKJABhAQADAAUK7hTKJABhAQAFAAIKShM3CACYAAA1AAQKfzcAAwMACgq1I9wbAGcDAAMACgq1I9wbAGcDAAUAAgqNIq0oALAAAAAA.Sastroll:BAAANQAECgMIAwABNQAFFAYIFwADAOUVAA==.',
Sc='Scatius:BAAANQADCggICAAAAA==.Scroll:BAABNQAECn8WAAIJAAkKSg7kBAC0AQAJAAkKSg7kBAC0AQAAAA==.',
Se='Serbitar:BAAANQADCggIGAAAAA==.',
Sh='Shadow:BAABNQAECn8WAAIcAAgKdBapKgDsAQAcAAgKdBapKgDsAQAAAA==.Shandrilah:BAABNQAECn8YAAMIAAYKJw5AXwBTAQAIAAYKJw5AXwBTAQAHAAIKuAU9bgBMAAAAAA==.Shialebuff:BAABNQAECn8UAAMVAAgKlRe6WwAOAgAVAAgKlRe6WwAOAgABAAEKqRKWcQBEAAAAAA==.Shijin:BAAANQADCgQIBAABNQADCgYIBgACAAAAAA==.',
Si='Silphy:BAABNQAECn8ZAAMUAAoKRhEBCQCkAQAUAAcKThMBCQCkAQAeAAcKcQ0wYgAcAQAAAA==.Sindar:BAAANQAECgIIAgAAAA==.Siphon:BAAANQAECgEIAQAAAA==.Siscomp:BAABNQAECn9eAAIGAAoKqhlsTgCeAgAGAAoKqhlsTgCeAgAAAA==.Sixth:BAAANQADCggIEAAAAA==.',
Sk='Skoog:BAABNQAECn8bAAIGAAgKDxXyjgD3AQAGAAgKDxXyjgD3AQAAAA==.Sky:BAACNQAFFH8JAAMVAAQKlxKiJgCeAAAVAAQKjRCiJgCeAAAXAAEKsBskBABHAAA1AAQKfzYABBUACgo2IkoLAGgDABUACQpgI0oLAGgDABcABAruHc4PACwBAAEAAQqhGwBzAEAAAAAA.',
Sn='Snarkshot:BAAANQADCgEIAQAAAA==.Snugglepuff:BAABNQAECn8kAAIGAAoKoRIZJgBtAQAGAAoKoRIZJgBtAQAAAA==.',
So='Sock:BAAANQAECggIBAAAAA==.Sonarius:BAACNQAFFH8GAAMDAAIKUhd6QQCrAAADAAIKUhd6QQCrAAAfAAEKCARTAQA/AAA1AAQKfzMABAMACgpGIBwWAHsDAAMACgpGIBwWAHsDAB8AAQr9H1MKAF0AAAUAAQqiHmk+AEgAAAAA.',
Sp='Sparkster:BAABNQAECn8gAAIGAAgK6RwjYQBqAgAGAAgK6RwjYQBqAgAAAA==.',
Su='Sundae:BAAANQAECgYIEwAAAA==.',
Sy='Sylvie:BAACNQAFFH8FAAIKAAMK9wrOCADcAAAKAAMK9wrOCADcAAA1AAQKfyIAAgoACgqQFOhaAGQCAAoACgqQFOhaAGQCAAAA.Syreith:BAAANQADCgYIBgAAAA==.',
['Så']='Sådistic:BAAANQAECgQIBQAAAA==.',
['Sý']='Sýlvanas:BAAANQABCgYIBgAAAA==.',
Ti='Tidders:BAABNQAECn8sAAILAAoKThvBBwBoAQALAAoKThvBBwBoAQAAAA==.Tikiwoki:BAAANQAECgcIEgAAAA==.Tiramisu:BAABNQAECn8YAAMHAAoKnRsRCwCIAQAHAAkK1RoRCwCIAQAIAAMK5w17kACVAAAAAA==.',
Tr='Trilldi:BAAANQADCggJEAAAAA==.Tritone:BAAANQAECgEIAQAAAA==.',
Ty='Tyladrhas:BAABNQAECn8ZAAMgAAgK0RZWDgDWAQAgAAcK9hhWDgDWAQATAAEK9QnfTAA+AAAAAA==.Tyrismaximus:BAAANQAECgMIBgAAAA==.',
Up='Up:BAABNQAECn8rAAIRAAoKoRu0AQDlAQARAAoKoRu0AQDlAQAAAA==.',
Va='Vaelus:BAAANQABCgIIAgAAAA==.Varina:BAAANQAECgIJAwAAAA==.',
Ve='Velorah:BAAANQAECgQIBQAAAA==.Velsaert:BAAANQADCgUJBAAAAA==.',
Vo='Volatilegas:BAAANQAECgYIEgAAAA==.',
Vu='Vulken:BAABNQAECn9nAAIKAAoKIBvAFADNAQAKAAoKIBvAFADNAQAAAA==.',
Wi='Winnìng:BAAANQAECgQICAAAAA==.',
Ya='Yamazaki:BAAANQAECgYIBgAAAA==.',
Ye='Yessuh:BAAANQAECgEIAgAAAA==.',
Zi='Zihon:BAAANQAECgUIBQAAAA==.',
Zo='Zombi:BAAANQAECgEIAQAAAA==.Zombiepanda:BAAANQAECgMIBgAAAA==.Zoomer:BAABNQAECn8nAAIgAAgKTQnsFgA/AQAgAAgKTQnsFgA/AQABNQAFFAQICQABAIYYAA==.',
Zu='Zubb:BAAANQADCgUIBQABNQAECggIHgADABIUAA==.Zugg:BAABNQAECn8UAAIhAAcK/Bd8AgA/AQAhAAcK/Bd8AgA/AQABNQAECggIHgADABIUAA==.Zupp:BAABNQAECn8eAAIDAAgKEhSZvQAJAgADAAgKEhSZvQAJAgAAAA==.Zuqq:BAAANQAECgYIEAABNQAECggIHgADABIUAA==.',
['Ér']='Ér:BAAANQAECgIIAQAAAA==.',
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
