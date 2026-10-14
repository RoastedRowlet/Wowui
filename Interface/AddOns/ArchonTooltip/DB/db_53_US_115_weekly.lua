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

local lookup = {'Unknown-Unknown','Mage-Arcane','Rogue-Assassination','Mage-Frost','Warrior-Arms','Druid-Balance','Druid-Restoration','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Subtlety','Paladin-Retribution','Paladin-Holy','Druid-Feral','Paladin-Protection','Evoker-Devastation','DeathKnight-Blood','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','Evoker-Augmentation','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Druid-Guardian','DemonHunter-Devourer','Monk-Windwalker','DemonHunter-Havoc','Mage-Fire','DemonHunter-Vengeance',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aamion:BAAANQAECgQIEQAAAA==.',
Ab='Abo:BAAANQAECggIEQAAAA==.',
Ae='Aeonfire:BAAANQAECgEIAQABNQAECggICgABAAAAAA==.',
Ak='Akame:BAAANQAFFAIIAgAAAA==.',
Al='Alykard:BAABNQAECn8cAAICAAgKOAeq+ACYAQACAAgKOAeq+ACYAQAAAA==.',
Am='Amateur:BAABNQAECn8iAAIDAAkKxhlZGwCfAgADAAkKxhlZGwCfAgAAAA==.Amazing:BAAANQAECgYIBgABNQAECgkJIgADAMYZAA==.',
An='Andronicas:BAAANQAECgYICwAAAA==.Aneira:BAABNQAECn8xAAIEAAkKeBC2CgAXAgAEAAkKeBC2CgAXAgAAAA==.',
As='Asaki:BAAANQADCggICAAAAA==.Aspect:BAAANQAECgQIBAABNQAECggICgABAAAAAA==.',
Av='Avi:BAAANQAECgQICAABNQAECgkJWgAFAHUaAA==.',
Ba='Baesuzy:BAABNQAECn8ZAAICAAcKSQzx8ACmAQACAAcKSQzx8ACmAQAAAA==.Baragas:BAAANQAECgYIDAAAAA==.',
Be='Belle:BAAANQADCgcICAAAAA==.Benkei:BAAANQAECgUIDgAAAA==.',
Bg='Bgc:BAAANQABCgYICQAAAA==.',
Bl='Blackds:BAAANQABCgQIBAAAAA==.Blain:BAAANQAECggICwAAAA==.',
Bo='Bosammana:BAAANQADCgMJAwAAAA==.',
Bu='Budin:BAAANQADCgIIAgAAAA==.',
Ca='Cannibal:BAAANQAECgcIEwAAAA==.Capri:BAABNQAECn8nAAIGAAcKsAsFVwB2AQAGAAcKsAsFVwB2AQAAAA==.Casiopia:BAAANQADCgQIBQAAAA==.',
Ch='Choomoo:BAABNQAECn8aAAIHAAkKxBniEADKAgAHAAkKxBniEADKAgABNQAFFAQIBwAIAAwIAA==.Chopstix:BAAANQADCgYIDAAAAA==.Chromie:BAAANQAECggICQAAAA==.',
Cr='Crikey:BAABNQAECn8wAAMJAAkKqhlUOQC8AgAJAAkKqhlUOQC8AgAKAAYKhg0fRQArAQAAAA==.',
Cv='Cvdruid:BAAANQADCgUIBQAAAA==.',
Da='Daga:BAAANQAECgcICQAAAA==.',
De='Definitely:BAABNQAECn80AAIEAAkKqCJrAgBDAwAEAAkKqCJrAgBDAwAAAA==.Desaix:BAABNQAECn8ZAAILAAcKEBWgHgDZAQALAAcKEBWgHgDZAQAAAA==.Desariana:BAABNQAECn8fAAIMAAkKkRLhfAAsAgAMAAkKkRLhfAAsAgAAAA==.Devimon:BAAANQAECgQIBAAAAA==.Dewasixseven:BAAANQADCgQIBAAAAA==.',
Dh='Dhunt:BAAANQABCgMIAQAAAA==.',
Do='Dormas:BAAANQAECgUICgAAAA==.Doug:BAAANQAECgQICAAAAA==.',
Dr='Drakeon:BAAANQADCgcJBwABNQAECgkJWgAFAHUaAA==.Drizzts:BAAANQADCgQIBQAAAA==.',
Dw='Dwarfpally:BAAANQAECgMIBgAAAA==.',
El='Eldh:BAAANQADCgEIAQAAAA==.Eldk:BAAANQAECgYIDgAAAA==.Elisoly:BAABNQAECn8eAAINAAcK5RIWeACtAQANAAcK5RIWeACtAQAAAA==.',
Em='Emrald:BAAANQAECgIIAwAAAA==.',
En='Endlessly:BAABNQAECn8VAAIOAAkK4hteBgAFAwAOAAkK4hteBgAFAwAAAA==.',
Er='Errimage:BAAANQADCgYIBwABNQAECgQIBAABAAAAAA==.Erritwo:BAAANQAECgQIBAAAAA==.',
Et='Etro:BAABNQAECn8lAAIPAAgKcCLACgDtAgAPAAgKcCLACgDtAgAAAA==.',
Ev='Evelinar:BAAANQADCggIEwAAAA==.Evoslex:BAABNQAECn8uAAIQAAkKGiJQAwByAwAQAAkKGiJQAwByAwAAAA==.',
Ex='Exo:BAECNQAFFH8RAAIRAAYKlhlkDACJAQARAAYKlhlkDACJAQA1AAQKf0YAAhEACQp3Iy4JAG8DABEACQp3Iy4JAG8DAAAA.',
Fa='Facerolleh:BAACNQAFFH8fAAIFAAcK4x0iAwCyAgAFAAcK4x0iAwCyAgA1AAQKfzQAAgUACQonJDITAG4DAAUACQonJDITAG4DAAAA.Fatedx:BAAANQAECgcIEwAAAA==.',
Fe='Feelgoodinc:BAAANQAECgMIAwAAAA==.',
Fi='Fistdaddy:BAAANQAECgUIBQAAAA==.Fiz:BAACNQAFFH8GAAIFAAMKvAyIJQDPAAAFAAMKvAyIJQDPAAA1AAQKfy4AAgUACQpxHERoAFQCAAUACQpxHERoAFQCAAAA.',
Fu='Fuknazum:BAAANQAECgIIAgAAAA==.',
Ga='Galara:BAAANQAECgEIAQAAAA==.',
Gr='Grandpriest:BAAANQAECgUIBwABNQAECgcIDQABAAAAAA==.Grimoirsingh:BAAANQAECgEIAQAAAA==.Grimveil:BAABNQAECn8xAAISAAkKQyLXDwA3AwASAAkKQyLXDwA3AwAAAA==.',
['Gô']='Gôku:BAAANQADCgYIBgAAAA==.',
Ha='Harafar:BAACNQAFFH8HAAIGAAQK+gVRFgD9AAAGAAQK+gVRFgD9AAA1AAQKfykAAgYACQrhF6YqAIACAAYACQrhF6YqAIACAAAA.',
He='Hellbourne:BAAANQAECgUICgAAAA==.',
Hi='Hibiki:BAAANQADCgIIAgAAAA==.',
Ho='Hogreveal:BAAANQADCgEIAQAAAA==.Hollykibbler:BAAANQAECgQIBAAAAA==.Holyclstrfuk:BAAANQADCgYIBgAAAA==.Horsé:BAAANQADCggIEgAAAA==.',
Hu='Huntslex:BAAANQAECgQIBgABNQAECgkJLgAQABoiAA==.',
Il='Illidam:BAAANQAECgYICgAAAA==.',
It='Itskiohte:BAAANQAECgYJEAAAAA==.',
Ja='Jaedaa:BAAANQAECgcJBwABNQAFFAUIEQARAGYWAA==.Jaedamend:BAABNQAECn8VAAMTAAkKFBnYNQCNAgATAAgKhhrYNQCNAgAUAAcKfhGALgCtAQABNQAFFAUIEQARAGYWAA==.',
Je='Jertbirt:BAAANQAECgEIAQAAAA==.',
Ka='Kalzaketh:BAABNQAECn8wAAIVAAcKFw3VDQBqAQAVAAcKFw3VDQBqAQAAAA==.Kashari:BAAANQAECgQICAABNQAECgkJWgATAFESAA==.Katali:BAAANQAECgMIAgAAAA==.Kaypop:BAAANQADCgQIBwABNQAFFAYIFgAJAPUYAA==.Kazo:BAACNQAFFH8IAAITAAQKDRHFFgA6AQATAAQKDRHFFgA6AQA1AAQKfycABBMACQq/ICAkANkCABMACQq/ICAkANkCABYAAQpoIyAfAGUAABQAAQpQE35zADwAAAAA.Kazuggar:BAACNQAFFH8hAAIXAAUK+xmyCgCeAQAXAAUK+xmyCgCeAQA1AAQKf0AAAxcACQrsIwAOAFADABcACQrsIwAOAFADABgAAgqDFqYJAXEAAAAA.Kazzn:BAAANQAECgYIEAAAAA==.',
Ke='Kell:BAAANQAECgYICAAAAA==.',
Ki='Kibbler:BAAANQAECgIIAwAAAA==.Killerman:BAAANQAECgUIBQAAAA==.',
Ku='Kucabara:BAAANQAECgQIBQABNQAECgYIDAABAAAAAA==.Kungpew:BAAANQAECgIIAgAAAA==.',
Kw='Kwichang:BAAANQAECgQICAAAAA==.',
Ky='Kyndariae:BAABNQAECn8fAAITAAcKdg0oigBzAQATAAcKdg0oigBzAQAAAA==.',
La='Lagman:BAAANQADCgEIAQAAAA==.',
Li='Lickynose:BAABNQAECn8lAAICAAgKXCHEZgCwAgACAAgKXCHEZgCwAgAAAA==.',
Ma='Mahou:BAAANQAECgQIBQAAAA==.Malcador:BAAANQAFFAEIAQAAAA==.Mantisar:BAABNQAECn8ZAAIMAAcKqgrU3QBZAQAMAAcKqgrU3QBZAQAAAA==.Marmite:BAAANQAECgYIDAAAAA==.',
Mi='Mightyhunt:BAAANQAECgcIDgAAAA==.Mirrorimage:BAABNQAECn8XAAMUAAkKuhvWEwDFAgAUAAkKuhvWEwDFAgATAAMKUwLH4wByAAABNQAFFAQICQAUAIYYAA==.Mirrorx:BAACNQAFFH8JAAIUAAQKhhjACQBeAQAUAAQKhhjACQBeAQA1AAQKfy0AAxQACQoJIcgMABwDABQACQoJIcgMABwDABMACAq7DWF5AKoBAAAA.',
Mo='Moosfel:BAAANQAECgQJBgAAAA==.',
Mt='Mtzz:BAAANQAECgUIEAAAAA==.',
Mu='Mudkrab:BAAANQAECgEIAQAAAA==.',
My='Mylie:BAAANQADCgIIAgAAAA==.Mystdragon:BAACNQAFFH8JAAIZAAQKAxOxDQAsAQAZAAQKAxOxDQAsAQA1AAQKfxkAAxkACQpnH4IMANsCABkACQpnH4IMANsCABUABArFGJgQACsBAAE1AAUUBggvAAgA8SQA.Mystweaverr:BAACNQAFFH8vAAIIAAYK8STDAACAAgAIAAYK8STDAACAAgA1AAQKfzoAAggACQpvJo0BALUDAAgACQpvJo0BALUDAAAA.',
Na='Naddar:BAABNQAECn8mAAINAAgKShdRSABDAgANAAgKShdRSABDAgAAAA==.Narp:BAAANQADCgQIBAAAAA==.',
Ng='Nganga:BAABNQAECn8eAAMXAAgKgx9DQwBRAgAXAAcKCyFDQwBRAgAYAAcKeBvxTwA1AgAAAA==.',
Ni='Nikonii:BAABNQAECn8bAAILAAcKIxvxFQAxAgALAAcKIxvxFQAxAgAAAA==.',
Ov='Ovaries:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
Pa='Paktam:BAAANQAECgYIDAAAAA==.Paladron:BAAANQAECgIIAgAAAA==.Palakudaliaq:BAAANQADCggICAAAAA==.Palaynslea:BAABNQAECn8mAAINAAkK+w27XQD8AQANAAkK+w27XQD8AQAAAA==.Parse:BAABNQAECn9IAAMDAAkK6B1wEgDmAgADAAkKUx1wEgDmAgALAAUKeh02JQCaAQAAAA==.',
Pe='Perceptor:BAAANQAECgIIAgABNQAECgkJJwAaAEAfAA==.',
Pr='Prothero:BAACNQAFFH8JAAICAAUKexAEJABfAQACAAUKexAEJABfAQA1AAQKfyMAAgIACQr7I88uAC8DAAIACQr7I88uAC8DAAAA.Proyo:BAAANQAECgUIDgAAAA==.',
['På']='Påthor:BAABNQAECn8eAAIGAAcKvxW2QgDnAQAGAAcKvxW2QgDnAQAAAA==.',
Ql='Ql:BAAANQADCgYIBgAAAA==.',
Ra='Raijinn:BAABNQAECn8fAAMXAAgK2iGaLQCpAgAXAAcKniKaLQCpAgAYAAcKlxnMVgAcAgAAAA==.Raizex:BAAANQADCggJDwAAAA==.Ratbarstard:BAABNQAECn9GAAICAAkKlBteXwDAAgACAAkKlBteXwDAAgAAAA==.Rawtoor:BAABNQAECn8sAAIbAAkKTh/SBwBTAwAbAAkKTh/SBwBTAwAAAA==.',
Ri='Ridgelock:BAAANQAECgIIAgAAAA==.Ridgerock:BAABNQAECn8aAAMRAAgKJx8XHwC3AgARAAgKJx8XHwC3AgASAAEKPgNG7wAlAAAAAA==.Riggse:BAAANQAECggIEQABNQAFFAcIHQAFAP4lAA==.Riggspal:BAAANQAECggICgABNQAFFAcIHQAFAP4lAA==.',
Ro='Roadkill:BAABNQAECn8jAAIRAAkKjCC/EgAVAwARAAkKjCC/EgAVAwAAAA==.Rolltoor:BAACNQAFFH8IAAIcAAUKpxFTCABcAQAcAAUKpxFTCABcAQA1AAQKfykAAhwACQq+IswMAAoDABwACQq+IswMAAoDAAAA.',
Ru='Ruínation:BAAANQAECgQIBgABNQAECggIHgAXAIMfAA==.',
Sa='Saiko:BAABNQAECn8hAAMdAAkK0hT3MAAcAgAdAAkKcRP3MAAcAgAbAAQKxhIuTwDeAAAAAA==.Sansa:BAAANQAECgcIDgAAAA==.Saso:BAACNQAFFH8TAAMCAAUK4hq+IwBhAQACAAQK7Ru+IwBhAQAEAAIKjxIGCACYAAA1AAQKfzIAAwIACQqmJDIbAGkDAAIACQqmJDIbAGkDAAQAAgqNIiwoALAAAAAA.Sastroll:BAAANQAECgMIAwABNQAFFAUIEwACAOIaAA==.',
Sc='Scroll:BAAANQAECgcIDQAAAA==.',
Se='Serbitar:BAAANQADCggJGAAAAA==.',
Sh='Shadow:BAABNQAECn8WAAIbAAgKdBYzKgDsAQAbAAgKdBYzKgDsAQAAAA==.Shandrilah:BAABNQAECn8YAAMGAAYKJw5aXgBTAQAGAAYKJw5aXgBTAQAHAAIKuAV2bABMAAAAAA==.Shialebuff:BAAANQAECgcIDwAAAA==.',
Si='Silphy:BAAANQAECgUICwABNQAECgkJMAASADQcAA==.Sindar:BAAANQAECgIIAgAAAA==.Siphon:BAAANQADCgcIEAAAAA==.Siscomp:BAABNQAECn9aAAIFAAkKdRo1TQCfAgAFAAkKdRo1TQCfAgAAAA==.Sixth:BAAANQADCggIEAAAAA==.',
Sk='Skoog:BAABNQAECn8aAAIFAAgKDxU9jQD3AQAFAAgKDxU9jQD3AQAAAA==.Sky:BAACNQAFFH8JAAMTAAQKlxLgJQCeAAATAAQKjRDgJQCeAAAWAAEKsBsaBABHAAA1AAQKfzEABBMACQrjIxMLAGgDABMACApoJRMLAGgDABYABAruHboPACwBABQAAQqhG4RxAEEAAAAA.',
Sn='Snarkshot:BAAANQADCgEIAQAAAA==.Snugglepuff:BAABNQAECn8dAAIFAAgKtBIzlQDjAQAFAAgKtBIzlQDjAQAAAA==.',
So='Sock:BAAANQAECggIBAAAAA==.Sonarius:BAACNQAFFH8FAAMCAAIKUhczQACsAAACAAIKUhczQACsAAAeAAEKCARPAQA/AAA1AAQKfy8ABAIACQqaI4EVAH0DAAIACQqaI4EVAH0DAB4AAQr9HzMKAF0AAAQAAQqiHp49AEgAAAAA.',
Sp='Sparkster:BAABNQAECn8eAAIFAAgK6RyxXwBrAgAFAAgK6RyxXwBrAgAAAA==.',
Su='Sundae:BAAANQAECgYIEAAAAA==.',
Sy='Sylvie:BAABNQAECn8eAAIJAAkKWhRnWQBlAgAJAAkKWhRnWQBlAgAAAA==.Syreith:BAAANQADCgYIBgAAAA==.',
['Så']='Sådistic:BAAANQAECgQIBQAAAA==.',
['Sý']='Sýlvanas:BAAANQABCgYIBgAAAA==.',
Ti='Tidders:BAABNQAECn8lAAIKAAgKSx9BHQBlAgAKAAgKSx9BHQBlAgAAAA==.Tikiwoki:BAAANQAECgcIDwAAAA==.Tiramisu:BAAANQAECggIEAAAAA==.',
Tr='Trilldi:BAAANQADCggJEAAAAA==.Tritone:BAAANQAECgEIAQAAAA==.',
Ty='Tyladrhas:BAABNQAECn8VAAIfAAcKuhgmDgDVAQAfAAcKuhgmDgDVAQAAAA==.Tyrismaximus:BAAANQAECgMIBAAAAA==.',
Up='Up:BAABNQAECn8kAAIQAAgKBB7JCwCoAgAQAAgKBB7JCwCoAgAAAA==.',
Va='Vaelus:BAAANQABCgIIAgAAAA==.Varina:BAAANQAECgIJAgAAAA==.',
Ve='Velorah:BAAANQAECgQIBAAAAA==.Velsaert:BAAANQADCgUJBAAAAA==.',
Vo='Volatilegas:BAAANQAECgYIDQAAAA==.',
Vu='Vulken:BAABNQAECn9gAAIJAAkK6RtrOgC5AgAJAAkK6RtrOgC5AgAAAA==.',
Wi='Winnìng:BAAANQAECgQICAAAAA==.',
Ya='Yamazaki:BAAANQAECgYIBgAAAA==.',
Ye='Yessuh:BAAANQAECgEIAgAAAA==.',
Zi='Zihon:BAAANQAECgUIBQAAAA==.',
Zo='Zombi:BAAANQAECgEIAQAAAA==.Zombiepanda:BAAANQADCgYIGgAAAA==.Zoomer:BAABNQAECn8nAAIfAAgKTQmpFgA/AQAfAAgKTQmpFgA/AQABNQAFFAQICQAUAIYYAA==.',
Zu='Zubb:BAAANQADCgUIBQABNQAECgcIHAACALwXAA==.Zugg:BAAANQAECgUICQABNQAECgcIHAACALwXAA==.Zupp:BAABNQAECn8cAAICAAcKvBfmugANAgACAAcKvBfmugANAgAAAA==.Zuqq:BAAANQAECgYIDQABNQAECgcIHAACALwXAA==.',
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
