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

local lookup = {'Mage-Frost','Warlock-Destruction','Druid-Balance','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Priest-Holy','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Shaman-Enhancement','Paladin-Protection','Shaman-Elemental','Evoker-Preservation','DemonHunter-Vengeance','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Unknown-Unknown','Shaman-Restoration','Paladin-Holy','Druid-Restoration','Priest-Shadow','Monk-Brewmaster','Druid-Feral','DeathKnight-Frost','Hunter-Survival','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Havoc','Priest-Discipline','Rogue-Assassination',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=46,date='2026-05-31',data={Ab='Abomination:BAAALgADCgMJAwAAAA==.',
Ad='Adune:BAAALgAECgMJBAAAAA==.',
Ae='Aeidail:BAACLgAFFH8cAAIBAAcJTRjIGADxAQABAAcJTRjIGADxAQAuAAQKfyYAAgEACAmnI0McAAUDAAEACAmnI0McAAUDAAAA.Aelaria:BAAALgADCgMJAwAAAA==.Aeviria:BAABLgAECn8lAAICAAgJTBVbBwDEAQACAAgJTBVbBwDEAQAAAA==.',
Ag='Agraceful:BAACLgAFFH8JAAIDAAMJMAapLwCbAAADAAMJMAapLwCbAAAuAAQKfx0AAgMACAnwEgMmAIQBAAMACAnwEgMmAIQBAAAA.',
Ai='Ailee:BAAALgAECgYJDAAAAA==.Aios:BAAALgADCgcJCQAAAA==.Aiza:BAACLgAFFH8LAAIEAAMJeAR0egCxAAAEAAMJeAR0egCxAAAuAAQKfy4AAwQACQnqE8U+ANYBAAQACQnqE8U+ANYBAAUAAQkAAPQ3AB0AAAAA.',
Al='Alaber:BAAALgAECgUJBQAAAA==.Aldanil:BAAALgADCgMJAwAAAA==.Allarria:BAAALgADCgEJAQABLgAECgkJJgAGAFogAA==.',
An='Animalfriend:BAAALgAECgIJAgAAAA==.Anklesmasher:BAABLgAECn8UAAIHAAcJ/A43NAAfAQAHAAcJ/A43NAAfAQAAAA==.Anyah:BAAALgAECgcJEQAAAA==.',
Ap='Apolloo:BAAALgADCgMJAwAAAA==.',
Aq='Aquadora:BAAALgAECgEJAQAAAA==.',
Ar='Arfaz:BAABLgAECn8rAAMIAAcJQB28TADLAQAIAAcJ0Ru8TADLAQAJAAYJWAogMwC3AAAAAA==.Armbrost:BAAALgAECgYJCgAAAA==.Artimås:BAAALgADCgcJCAAAAA==.Arwynne:BAAALgADCgMJAwAAAA==.Arçano:BAAALgAECgEJAQABLgAECgkJGQAKADkTAA==.',
As='Ascension:BAAALgADCgcJBgABLgAECgkJPgAEAJ8kAA==.Astrastar:BAABLgAECn8bAAMEAAYJ0wJw1ACdAAAEAAYJ0wJw1ACdAAACAAEJcgDDgAAOAAAAAA==.',
Au='Auralyn:BAAALgADCgIJAgAAAA==.',
Av='Avarin:BAAALgADCgEJAQAAAA==.',
Ay='Aymont:BAAALgAECgQJBQAAAA==.',
Ba='Baerd:BAABLgAECn8aAAILAAcJZhMaKAByAQALAAcJZhMaKAByAQAAAA==.Baji:BAAALgAECgkJBwAAAA==.Barlz:BAAALgAECgEJAQAAAA==.',
Be='Beanpaste:BAAALgAECgcJAQABLgAFFAMJDAAIAHcXAA==.Beanutbutter:BAAALgADCgIJAgABLgAFFAMJDAAIAHcXAA==.Beaty:BAAALgAECgIJAgAAAA==.Bebby:BAABLgAECn8UAAMJAAcJEQKSQgBrAAAJAAYJ3gGSQgBrAAAIAAIJaQIqUwExAAAAAA==.Belonara:BAAALgADCgUJDAAAAA==.Belwolf:BAAALgAECgUJEAAAAA==.Bergstrom:BAABLgAECn80AAIMAAkJuhlLKgBBAgAMAAkJuhlLKgBBAgAAAA==.Bethanymarie:BAAALgAECgEJAQAAAA==.Betrayer:BAAALgADCgQJAwABLgAECgkJPgAEAJ8kAA==.',
Bi='Biancaneve:BAAALgAECgYJCgAAAA==.Bighero:BAACLgAFFH8MAAIGAAMJ+AbsXgC0AAAGAAMJ+AbsXgC0AAAuAAQKfxwAAgYACAmsEVlvAFYBAAYACAmsEVlvAFYBAAAA.Bigmike:BAAALgAECgEJAgAAAA==.',
Bl='Blakkjezus:BAAALgAECgcJDQAAAA==.Blitzbolts:BAAALgAECgEJAgAAAA==.Bludo:BAACLgAFFH8QAAMNAAYJNBKgHAAsAQANAAUJHRWgHAAsAQAOAAMJpAzxIADGAAAuAAQKfx4AAw0ACQl6IWgZAIACAA0ACAk5GWgZAIACAA4ABgl9HFMYADYBAAAA.',
Bo='Boe:BAABLgAECn8hAAIPAAgJ6wixFQBFAQAPAAgJ6wixFQBFAQAAAA==.Bomba:BAAALgAECgQJBQAAAA==.Bombacløt:BAABLgAECn8pAAMEAAkJpg+0RwC5AQAEAAkJQQ60RwC5AQACAAcJbg7oEQASAQAAAA==.Bowdirte:BAAALgAECgUJBwAAAA==.',
Br='Brastin:BAABLgAECn8yAAIQAAkJ+iCEAgDyAgAQAAkJ+iCEAgDyAgABLgAFFAUJEQARAIQMAA==.Brenell:BAACLgAFFH8FAAIBAAIJQRPxjACWAAABAAIJQRPxjACWAAAuAAQKfzkAAgEACQmwIZoOAPICAAEACQmwIZoOAPICAAAA.',
Bu='Bu:BAAALgAECgUJBwABLgAECgYJGwASALgdAA==.Bubblehearth:BAAALgAECgYJCQABLgAECgkJKAAGAHwaAA==.Buffet:BAAALgAECgYJDwABLgAECgkJKAAGAHwaAA==.Buhlitz:BAAALgAECgEJAgAAAA==.Butterbean:BAAALgADCgIJAgAAAA==.',
By='Bynis:BAABLgAECn8fAAIGAAkJfRRURQChAQAGAAkJfRRURQChAQAAAA==.',
Ca='Cabëla:BAAALgADCgUJBQAAAA==.Cactusjack:BAAALgADCgUJBQAAAA==.Cadorex:BAAALgADCgEJAQAAAA==.Caffeinefree:BAAALgADCggJBwAAAA==.Calacolinda:BAAALgAECgQJBgAAAA==.Calamari:BAAALgAECgEJAQAAAA==.Cavakworm:BAAALgADCgEJAQAAAA==.Caylin:BAAALgADCgUJBgAAAA==.Cayusedemon:BAAALgADCgEJAQAAAA==.Cayusemage:BAAALgADCgkJCgAAAA==.',
Ce='Ceridwyn:BAAALgAECgEJAQAAAA==.',
Ch='Chariscrushr:BAAALgAECgQJCAABLgAFFAcJGQAHAF0YAA==.Chen:BAAALgADCgIJAgAAAA==.Choal:BAAALgAECgEJAQAAAA==.Chokaho:BAAALgAECgMJAwAAAA==.',
Ci='Cinnamongirl:BAAALgAECgcJEgAAAA==.',
Co='Corahin:BAABLgAECn8bAAIRAAYJGxASRAA5AQARAAYJGxASRAA5AQAAAA==.Corious:BAAALgAECgQJCQAAAA==.Cosmos:BAAALgAECgYJDQAAAA==.Cougarhunter:BAAALgAECgkJEAAAAA==.',
Cr='Crixux:BAAALgADCgMJAQAAAA==.Crokus:BAAALgADCggJCAAAAA==.',
Cu='Cuecumba:BAABLgAECn8uAAITAAkJICZOAABkAwATAAkJICZOAABkAwAAAA==.',
Da='Daemonerror:BAAALgAECgUJBQABLgAECggJNwAUAJUiAA==.Dalren:BAACLgAFFH8YAAMVAAYJah5HEQCtAQAVAAUJah5HEQCtAQAWAAIJuwNtCwBLAAAuAAQKfz8AAxUACQlIJfoEAP4CABUACQkLJfoEAP4CABYABgnyIEMMABcCAAAA.Dalryn:BAAALgAECgYJDQABLgAFFAYJGAAVAGoeAA==.Dalvix:BAAALgADCgEJAQABLgAECgkJJgAGAFogAA==.Damocles:BAABLgAECn8YAAIBAAYJlwwatwD8AAABAAYJlwwatwD8AAAAAA==.Danazel:BAAALgADCgIJAgAAAA==.Dartagnan:BAACLgAFFH8KAAIXAAMJVhwKQwADAQAXAAMJVhwKQwADAQAuAAQKfyMAAxcACAl3HWRgAG8BABcABgneHmRgAG8BABgABgn3FKoYANkAAAAA.Darthmaul:BAABLgAECn8wAAIDAAkJyhEfHADQAQADAAkJyhEfHADQAQAAAA==.',
De='Deay:BAAALgADCgQJAQAAAA==.Delexa:BAAALgADCgkJOQAAAA==.Dendiian:BAABLgAECn8UAAIZAAYJXxWAIQAgAQAZAAYJXxWAIQAgAQAAAA==.',
Di='Didipullthat:BAAALgADCgYJFwABLgAECgkJKAAGAHwaAA==.Diem:BAABLgAECn8dAAIXAAgJyw1rQQCqAQAXAAgJyw1rQQCqAQAAAA==.Dirtydotss:BAABLgAECn8VAAMFAAcJFwfXEgD/AAAFAAYJYQbXEgD/AAAEAAYJ5wSNvwDBAAAAAA==.Divigitives:BAAALgAECgQJBAAAAA==.',
Do='Docrivan:BAAALgAECgYJCwAAAA==.Docsassist:BAAALgAECgMJAwABLgAECgYJCwAaAAAAAA==.Doregit:BAABLgAECn8rAAINAAkJAR3GDQCAAgANAAkJAR3GDQCAAgAAAA==.Dowedoes:BAABLgAECn89AAIMAAkJghdTLwArAgAMAAkJghdTLwArAgAAAA==.',
Dr='Drachula:BAABLgAECn8aAAIbAAYJTRbMRACBAQAbAAYJTRbMRACBAQAAAA==.Dracultra:BAAALgAECgUJBwABLgAECgkJIAAcAF0fAA==.Drakcheese:BAAALgADCgUJBQAAAA==.Dreolan:BAABLgAECn9AAAIdAAkJuhPOJgAHAgAdAAkJuhPOJgAHAgAAAA==.Drynnai:BAAALgADCgEJAgAAAA==.',
Dy='Dyala:BAACLgAFFH8LAAMdAAMJjg8OOQC7AAAdAAMJjg8OOQC7AAADAAMJ8AJtMgCHAAAuAAQKfx8AAx0ACAmNErdfADMBAB0ACAmNErdfADMBAAMAAgk0CmFvAFIAAAAA.',
['Dö']='Dönövan:BAABLgAECn8nAAIMAAkJRhHUTQDGAQAMAAkJRhHUTQDGAQAAAA==.',
El='Elastwo:BAAALgADCgcJDQAAAA==.Eloise:BAAALgAECgcJEwAAAA==.Elvenbane:BAABLgAECn8mAAIeAAkJrRO/GADmAQAeAAkJrRO/GADmAQAAAA==.',
Em='Emily:BAAALgAECgYJDAAAAA==.Emry:BAAALgADCgYJBgABLgAECgcJHQAUADkPAA==.',
En='Enable:BAEBLgAECn8gAAIfAAkJVRz8CACTAgAfAAkJVRz8CACTAgABLgAECggJLwAQAE8iAA==.',
Ep='Epictool:BAAALgAECggJCwAAAA==.',
Et='Ethereal:BAAALgAECgEJAQAAAA==.',
Ex='Extrathick:BAAALgAECgMJAwAAAA==.',
Fa='Fabel:BAEBLgAECn8vAAIQAAgJTyJNBgBvAgAQAAgJTyJNBgBvAgAAAA==.Falahad:BAAALgAECgEJAQABLgAFFAMJDAADAD4OAA==.Faltree:BAACLgAFFH8MAAMDAAMJPg6cKwCxAAADAAMJPg6cKwCxAAAdAAIJ6RPySACDAAAuAAQKfx8ABB0ACAmwGP5TAFcBAB0ABglPGP5TAFcBAAMACAkOF+wtAFEBACAAAQnfAUo6AB8AAAAA.Fathershale:BAAALgADCggJFwAAAA==.',
Fi='Firelord:BAAALgADCgEJAQAAAA==.',
Fo='Foulcor:BAABLgAECn8cAAMcAAgJlB7pFABRAgAcAAgJlB7pFABRAgAMAAYJ5xCsswD+AAAAAA==.',
Fr='Freakadeek:BAABLgAECn8VAAQhAAkJaw2vGgDKAAAIAAUJ0AhnwgDlAAAhAAMJnhevGgDKAAAJAAYJgwSZRgBbAAAAAA==.Freâkadeek:BAAALgAECgIJAwABLgAECgkJFQAhAGsNAA==.Freäk:BAAALgADCgMJAwABLgAECgkJFQAhAGsNAA==.Frieren:BAABLgAECn89AAIBAAkJ6xXuOAAfAgABAAkJ6xXuOAAfAgAAAA==.Frink:BAAALgAECgEJAQABLgAECgkJPQAiAOEkAA==.Frostlord:BAAALgAECgIJAgAAAA==.',
Fu='Fundetected:BAAALgAECgUJCAABLgAECgkJKAAGAHwaAA==.Furyofthenug:BAAALgADCgcJCgAAAA==.',
Ga='Gabbyo:BAABLgAECn8hAAIdAAcJkQcwaQDpAAAdAAcJkQcwaQDpAAAAAA==.Galadorn:BAABLgAECn8mAAIGAAkJWiCHDQDHAgAGAAkJWiCHDQDHAgAAAA==.Gallgamesh:BAAALgADCgIJAgAAAA==.Garfall:BAAALgAECgcJDgAAAA==.Garga:BAAALgADCgMJBAABLgAECgMJAwAaAAAAAA==.',
Ge='Geirvaldr:BAAALgAECgYJBgAAAA==.Gerdash:BAAALgAECgMJBAAAAA==.Gerred:BAABLgAECn8ZAAMOAAcJnhimFACkAQAOAAcJ7BemFACkAQANAAQJRRRWXADKAAAAAA==.',
Gh='Ghallow:BAABLgAECn8YAAIPAAYJFReSEgBwAQAPAAYJFReSEgBwAQAAAA==.Ghosty:BAACLgAFFH8JAAIjAAQJOxWkGgApAQAjAAQJOxWkGgApAQAuAAQKfyoAAiMABwlQIKkRAAUCACMABwlQIKkRAAUCAAAA.',
Gi='Gimp:BAAALgAECgEJAgAAAA==.',
Gl='Gladur:BAABLgAFFH8GAAMHAAYJyAwsGQDtAAAHAAUJtwwsGQDtAAAUAAEJmQFSUAAxAAABLgAFFAcJHAABAE0YAA==.',
Go='Goldenflame:BAAALgAECgUJBwAAAA==.Goldenlily:BAAALgAECgYJEgAAAA==.Goldenmunc:BAABLgAECn8tAAIBAAkJNxfbLwBDAgABAAkJNxfbLwBDAgAAAA==.Goldenone:BAAALgAECgQJBQAAAA==.Goldenpants:BAABLgAECn8nAAINAAkJjxNCHgDrAQANAAkJjxNCHgDrAQAAAA==.',
Gr='Grievous:BAABLgAECn89AAITAAkJOyWAAABRAwATAAkJOyWAAABRAwAAAA==.',
['Gû']='Gûrth:BAAALgADCgcJBwAAAA==.',
Ha='Hailmary:BAABLgAECn8oAAILAAkJEiUaAQCyAwALAAkJEiUaAQCyAwAAAA==.Halcrux:BAAALgAECgIJAgAAAA==.Halvard:BAAALgADCgIJAgAAAA==.Harusen:BAABLgAECn8cAAIkAAkJFR/2AQCmAgAkAAkJFR/2AQCmAgAAAA==.',
He='Healaga:BAAALgAECgYJBgABLgAECgcJKwAIAEAdAA==.',
Hi='Hildalsind:BAAALgADCgkJCQABLgAFFAMJCQABAIMdAA==.',
Ho='Homestar:BAAALgADCgEJAQAAAA==.Hooll:BAAALgAECgIJAgAAAA==.Hornreaper:BAABLgAECn8bAAIVAAYJ5hfvJACVAQAVAAYJ5hfvJACVAQAAAA==.Hotshot:BAAALgAECgMJAwAAAA==.',
Hu='Hubbabubbajr:BAAALgAECgEJAQABLgAECgkJMwAdAIIbAA==.Hubert:BAAALgADCgEJAgAAAA==.Hurin:BAAALgAECgcJDgAAAA==.Huur:BAAALgAECgEJAQABLgAECgEJAQAaAAAAAA==.',
Hy='Hyetta:BAAALgAECgQJBgABLgAECgkJHAAkABUfAA==.Hyir:BAAALgADCgYJBwABLgAFFAMJEAAHAFMhAA==.',
Il='Illiya:BAAALgAECgUJEAAAAA==.',
Ir='Irôn:BAAALgAECgEJAQAAAA==.',
Iu='Iutara:BAAALgAECgYJDAAAAA==.',
Ja='Jaalein:BAAALgADCgcJDgAAAA==.Jayonor:BAABLgAECn80AAQRAAkJthX0FgAWAgARAAkJthX0FgAWAgAPAAYJ9we4GgAeAQAbAAcJ5AY+ZwAJAQAAAA==.',
Je='Jek:BAAALgAECgUJBQAAAA==.',
Jo='Joryu:BAAALgADCgIJAwAAAA==.',
Ju='Juicycucci:BAAALgAECgcJEgABLgAECgkJKAAGAHwaAA==.',
Ka='Kaevrielle:BAEBLgAECn8eAAMTAAkJjhtbBgAYAgATAAkJjhtbBgAYAgAlAAEJVgrUagAnAAAAAA==.Kaison:BAAALgAECgkJEAABLgAECgkJHwAGAH0UAA==.Kaladîn:BAAALgAECgMJAwABLgAFFAcJHAABAE0YAA==.Kalii:BAAALgADCgQJBAAAAA==.Kamel:BAAALgADCgYJBgAAAA==.Karwin:BAABLgAECn8ZAAIBAAcJhhRrgQBbAQABAAcJhhRrgQBbAQAAAA==.Katakuri:BAAALgAECgEJAgAAAA==.',
Ke='Keeper:BAAALgAECgUJBwABLgAECgkJSgAMAPckAA==.Keeperodark:BAAALgAECggJEAABLgAECgkJSgAMAPckAA==.Keeperolight:BAABLgAECn9KAAMMAAkJ9yRmBQA5AwAMAAkJ9yRmBQA5AwAcAAEJgRgUkABAAAAAAA==.Kemanorel:BAAALgADCgcJDgABLgAECgkJJgAeAK0TAA==.',
Ki='Kianth:BAAALgADCgkJEgAAAA==.Killkat:BAABLgAECn8uAAIBAAkJgxi2LwBEAgABAAkJgxi2LwBEAgAAAA==.',
Ko='Kodera:BAABLgAECn8bAAMSAAYJuB3lDAD1AQASAAYJuB3lDAD1AQAWAAQJNxuXDQAiAQAAAA==.Koojo:BAAALgAECgcJCAAAAA==.Kovae:BAAALgADCgEJAQAAAA==.',
Kr='Kraken:BAAALgADCgUJBQAAAA==.',
Ku='Kusheddruid:BAAALgADCgIJAgAAAA==.',
Ky='Kyaritin:BAAALgAECgMJAwABLgAECgYJCgAaAAAAAA==.Kyokei:BAAALgAECgEJAQAAAA==.',
La='Laiho:BAAALgADCgUJCAAAAA==.Lans:BAAALgAFFAEJAgAAAA==.Larew:BAACLgAFFH8FAAIMAAMJbgd4ZgDDAAAMAAMJbgd4ZgDDAAAuAAQKfycAAgwACAn4FzRGAN0BAAwACAn4FzRGAN0BAAAA.Lazytemplar:BAAALgADCgMJAwABLgAECgUJDgAaAAAAAA==.',
Le='Lealla:BAABLgAECn89AAIDAAkJlCJWBAAMAwADAAkJlCJWBAAMAwAAAA==.Lechevalier:BAAALgAECgcJDAABLgAECgkJKAAGAHwaAA==.Leodin:BAAALgAECgEJAgAAAA==.Leorus:BAAALgAECgIJAgAAAA==.Lethhunt:BAACLgAFFH8SAAMYAAYJPQ0eEQAhAQAYAAYJ9QoeEQAhAQAXAAIJWw4MGgCeAAAuAAQKfy4AAxgACQncHqkFADICABgACQlgHqkFADICABcAAgk+JFKHANIAAAAA.',
Li='Lilmistfox:BAAALgAECgUJBwABLgAFFAQJEgAbADEmAA==.Lioh:BAAALgAECgQJBAAAAA==.Lizardgang:BAAALgAECgYJEwAAAA==.',
Lo='Loganshu:BAAALgAECgIJBAAAAA==.Lokan:BAACLgAFFH8MAAMiAAMJjhj7FwD6AAAiAAMJjhj7FwD6AAAXAAEJwggdiwBFAAAuAAQKfygAAiIACAnTHcoNAD8CACIACAnTHcoNAD8CAAAA.Lots:BAACLgAFFH8MAAIEAAMJhhsSVwD/AAAEAAMJhhsSVwD/AAAuAAQKfyUAAwQACAnWI4gvAE8CAAQABwlaJIgvAE8CAAIABAngHkcsAA0BAAAA.',
Lu='Ludacast:BAAALgADCgIJAgAAAA==.Ludafists:BAAALgADCgcJDAAAAA==.Ludakris:BAABLgAECn8eAAIQAAkJfxjUCQAYAgAQAAkJfxjUCQAYAgAAAA==.Lumanoth:BAAALgAECgYJBgAAAA==.',
Ly='Lyna:BAABLgAECn8gAAIbAAkJpRNhOQCwAQAbAAkJpRNhOQCwAQAAAA==.Lynaya:BAAALgADCgIJAgAAAA==.',
['Lí']='Líonheart:BAABLgAECn8VAAMcAAYJ+BkWQgAlAQAcAAYJ+BkWQgAlAQAMAAEJQwSrVQEoAAAAAA==.',
['Lî']='Lîghtless:BAACLgAFFH8PAAIBAAYJBhr9LQCGAQABAAYJBhr9LQCGAQAuAAQKfxcAAgEACAmfJUchAO4CAAEACAmfJUchAO4CAAAA.',
['Lú']='Lúckally:BAAALgADCgQJBAABLgAECgYJCgAaAAAAAA==.Lúckÿ:BAAALgAECgYJCgAAAA==.',
Ma='Magicpanda:BAAALgAECgQJBAAAAA==.Mahina:BAAALgAECgIJAgAAAA==.Marcille:BAABLgAECn8nAAIBAAgJ2RMHbQCJAQABAAgJ2RMHbQCJAQAAAA==.Masyledian:BAAALgAECgIJAgAAAA==.Mathor:BAAALgAECgEJAgAAAA==.Mavrbg:BAAALgAECgQJBQAAAA==.Mayhaps:BAABLgAECn9EAAMXAAkJFRviIABOAgAXAAkJFRviIABOAgAYAAEJZACpmgAYAAAAAA==.',
Mc='Mcbain:BAABLgAECn89AAIiAAkJ4SRSAQBIAwAiAAkJ4SRSAQBIAwAAAA==.',
Me='Melrine:BAAALgADCgMJAwAAAA==.Mentaltitty:BAABLgAECn8fAAIBAAgJyxNRWgC3AQABAAgJyxNRWgC3AQAAAA==.Meret:BAAALgADCgIJAgAAAA==.',
Mi='Minerwor:BAAALgAECgUJBwAAAA==.Mirrayla:BAAALgADCgYJBgAAAA==.Misty:BAAALgADCgYJBgAAAA==.',
Mm='Mmisty:BAABLgAECn9BAAIDAAkJghk/DQBvAgADAAkJghk/DQBvAgAAAA==.',
Mo='Moarthretplz:BAAALgAECgUJCQABLgAFFAQJEgAbADEmAA==.Mohji:BAAALgAFFAEJAQABLgAFFAcJGgAmAOwUAA==.Momometaru:BAABLgAECn8kAAQEAAkJgRYNOgDmAQAEAAkJfhMNOgDmAQACAAUJNhRyJgAsAQAFAAMJzxqHIQCNAAAAAA==.Monsterbee:BAABLgAECn9BAAIEAAkJthEpNwDxAQAEAAkJthEpNwDxAQAAAA==.',
Mu='Mustypizza:BAABLgAECn8uAAICAAkJihjkAwA1AgACAAkJihjkAwA1AgAAAA==.',
Mx='Mxicancowboy:BAAALgADCgEJAgAAAA==.',
My='Mystery:BAABLgAECn89AAMSAAkJNiB6AgA3AwASAAkJNiB6AgA3AwAWAAUJXhFGDgAWAQAAAA==.',
['Mê']='Mêøwzêr:BAAALgAECggJEwAAAA==.',
['Mÿ']='Mÿst:BAAALgAECgMJBAAAAA==.',
Na='Narashi:BAAALgAECgQJBgAAAA==.Naril:BAAALgADCgUJBQAAAA==.Nats:BAABLgAECn8kAAIbAAgJSxGwOACfAQAbAAgJSxGwOACfAQAAAA==.',
Ne='Neameny:BAABLgAECn89AAIXAAkJGBNHMgD+AQAXAAkJGBNHMgD+AQAAAA==.',
Ni='Nianji:BAAALgADCgYJDgAAAA==.Nightstar:BAAALgADCgMJAwAAAA==.Nightworld:BAAALgADCgcJDgAAAA==.',
No='Noctum:BAAALgAECgUJBQAAAA==.Nordicpally:BAAALgADCgQJBAAAAA==.Notgim:BAAALgADCggJCAAAAA==.',
Nu='Nualrossan:BAAALgADCgMJAgAAAA==.Nubrac:BAAALgAECggJEgAAAA==.',
Ny='Nylux:BAAALgAECgYJDwAAAA==.',
Ob='Oblivion:BAABLgAECn8+AAMEAAkJnyRYBQAwAwAEAAkJnyRYBQAwAwACAAEJAABRXQBXAAAAAA==.',
Oo='Oostren:BAAALgAECgEJAgAAAA==.',
Or='Orsyp:BAAALgADCgkJGgAAAA==.',
Pa='Palockie:BAAALgADCgEJAQAAAA==.Pandas:BAABLgAECn8hAAIRAAkJAhGAIgC6AQARAAkJAhGAIgC6AQAAAA==.Partyrocker:BAABLgAECn8XAAIiAAcJag51JwBVAQAiAAcJag51JwBVAQABLgAECgkJFQAhAGsNAA==.',
Pi='Pixae:BAACLgAFFH8MAAISAAMJjwdlHgCmAAASAAMJjwdlHgCmAAAuAAQKfx8AAhIABwlOC54aAB4BABIABwlOC54aAB4BAAAA.Pixiechaos:BAAALgAECgQJCAAAAA==.',
Po='Poliahu:BAAALgAECgYJEQAAAA==.Porthoss:BAAALgADCggJDwAAAA==.Powerplant:BAACLgAFFH8VAAIXAAYJaiExDwCkAQAXAAYJaiExDwCkAQAuAAQKfyYAAhcACQkgJCgIAA4DABcACQkgJCgIAA4DAAAA.Poyoram:BAAALgADCgEJAQAAAA==.',
Py='Pyralys:BAABLgAECn85AAMLAAkJGBG7GADyAQALAAkJGBG7GADyAQAeAAMJqQKweAAzAAAAAA==.',
Qu='Quizac:BAAALgADCgIJAgAAAA==.',
Ra='Ragemonk:BAAALgAECgUJDgAAAA==.Ragetality:BAAALgAECgUJBgABLgAECgUJDgAaAAAAAA==.Rakthera:BAAALgADCgcJBwAAAA==.Ramaria:BAAALgADCgkJCQABLgAECgkJJgAGAFogAA==.Raserei:BAAALgAFFAIJAgAAAA==.Rasputain:BAAALgADCgYJCgAAAA==.Rasputein:BAAALgADCgcJBwAAAA==.Rattelyr:BAAALgAECgYJCgAAAA==.Ravara:BAAALgADCgYJBgABLgAECgkJJgAGAFogAA==.Rayné:BAAALgAECgcJDgAAAA==.Razgaurd:BAAALgAECgMJAwAAAA==.',
Re='Regice:BAAALgAECgcJBwABLgAFFAIJBgAJAEgdAA==.Regicee:BAACLgAFFH8GAAIJAAIJSB1zIwCqAAAJAAIJSB1zIwCqAAAuAAQKfzkAAwkACQndIAwFAM0CAAkACQndIAwFAM0CAAgABAm3CEgBAY0AAAAA.Retam:BAAALgAECgEJAQAAAA==.Revakos:BAAALgADCgMJAwAAAA==.',
Rh='Rhysandra:BAAALgAECgQJCQAAAA==.',
Ri='Ribble:BAAALgADCgMJAwAAAA==.Riffraff:BAAALgAECgcJBAAAAA==.Ripcord:BAAALgAECgUJCAAAAA==.Ripem:BAAALgADCgYJBgAAAA==.Ripperoni:BAAALgAECgEJAgAAAA==.Rizek:BAAALgAECgUJBgABLgAECgcJHQAUADkPAA==.Rizzx:BAAALgAECgEJAQAAAA==.',
Ro='Rockdyou:BAABLgAECn8kAAIIAAkJ3R5xIgBqAgAIAAkJ3R5xIgBqAgAAAA==.Roglef:BAAALgAECgQJCQAAAA==.Rotlobster:BAABLgAECn8VAAIFAAcJih5MBQAYAgAFAAcJih5MBQAYAgAAAA==.Roxxy:BAAALgAECgQJBAAAAA==.',
Ru='Rundvelt:BAACLgAFFH8MAAIQAAMJeA3rCwCcAAAQAAMJeA3rCwCcAAAuAAQKfyAAAhAACAkREosWAFQBABAACAkREosWAFQBAAAA.',
Sa='Sage:BAAALgADCgcJCAAAAA==.Sandwich:BAAALgAECgcJCAAAAA==.Saphíra:BAAALgAFFAIJAQABLgAFFAcJHAABAE0YAA==.Sapkick:BAAALgAECgQJBwAAAA==.',
Se='Serdragon:BAAALgADCgQJBAAAAA==.Servoid:BAAALgAECgUJCQAAAA==.',
Sh='Shando:BAAALgAECgEJAQAAAA==.Shiftstyle:BAEALgAECgEJAQAAAA==.Shtanky:BAACLgAFFH8KAAIKAAMJaBFgGQC3AAAKAAMJaBFgGQC3AAAuAAQKfyAAAgoACAkGDngbAEYBAAoACAkGDngbAEYBAAAA.',
Si='Silentsocks:BAAALgAECgUJDAAAAA==.Sixsixsix:BAAALgAECgcJCgABLgAFFAIJCAAIANMeAA==.',
Sk='Skoogz:BAAALgAECgkJEQAAAA==.',
So='Soggyy:BAAALgADCgYJCwAAAA==.Solar:BAABLgAECn8VAAQHAAcJyRkxLwBtAQAHAAYJCxYxLwBtAQAfAAYJrhzoOABmAQAUAAEJUwLgtAAaAAAAAA==.Soulfulgingr:BAAALgAECgYJCgAAAA==.',
St='Starlagosa:BAAALgADCgYJCQAAAA==.Sturm:BAAALgAECgMJAwAAAA==.Styx:BAAALgAECgMJAwAAAA==.',
Su='Sunbake:BAAALgAECgUJCgAAAA==.',
Sw='Sweetbbyraze:BAACLgAFFH8TAAMWAAUJmhtjBwCvAAAVAAUJ2w/xEgDoAAAWAAMJmRZjBwCvAAAuAAQKfyYAAxYACAkpIVIGAJACABYABwm8IVIGAJACABUAAwnyHB5eAJsAAAAA.',
Sy='Sylaena:BAABLgAECn8iAAIYAAgJBgoHEgAnAQAYAAgJBgoHEgAnAQAAAA==.Sylvrstorm:BAAALgAECgUJCwAAAA==.',
['Së']='Sërënity:BAAALgAECgQJCwAAAA==.',
['Sí']='Sín:BAAALgAECgcJDAABLgAFFAIJCAAIANMeAA==.',
Ta='Talipally:BAACLgAFFH8HAAIMAAMJ7Qi4YwDKAAAMAAMJ7Qi4YwDKAAAuAAQKfxwAAgwACQkyEJlvAHYBAAwACQkyEJlvAHYBAAAA.Talishammy:BAAALgAECgMJAwABLgAFFAMJBwAMAO0IAA==.Taliwhacker:BAAALgAECgYJBgABLgAFFAMJBwAMAO0IAA==.Talonleafgrd:BAAALgAECgEJAQAAAA==.Tanaka:BAABLgAECn8gAAIIAAgJgBMKUQC/AQAIAAgJgBMKUQC/AQAAAA==.Tanisong:BAAALgAECgQJCgAAAA==.Tassadar:BAAALgAECgUJCAAAAA==.',
Te='Teldo:BAAALgADCgIJAgAAAA==.Tepeyollotl:BAAALgADCgEJAQAAAA==.Terayus:BAAALgADCgcJDAAAAA==.Teyliah:BAAALgADCgMJAwAAAA==.',
Tf='Tf:BAAALgAECgYJBgABLgAFFAIJCAAIANMeAA==.',
Th='Thekingpunch:BAABLgAECn83AAMUAAgJlSKXBwAKAwAUAAgJlSKXBwAKAwAHAAEJMQtdmgAqAAAAAA==.Thenle:BAAALgADCggJDgAAAA==.Thline:BAAALgADCgIJAgAAAA==.Thunderblitz:BAABLgAECn8oAAIcAAkJvgilMACCAQAcAAkJvgilMACCAQAAAA==.Thurmus:BAAALgADCgkJOQAAAA==.',
Ti='Tillwar:BAABLgAECn87AAINAAkJKh0sDgB8AgANAAkJKh0sDgB8AgAAAA==.Tinymonk:BAAALgADCgYJBwAAAA==.',
To='Tofu:BAABLgAECn80AAMIAAkJJB07FgCwAgAIAAkJJB07FgCwAgAJAAEJtADaYwANAAAAAA==.Tokanya:BAAALgAECgEJAQAAAA==.Tortillachip:BAAALgAECgEJAgAAAA==.Toxidot:BAAALgAECgEJAQAAAA==.',
Tr='Treibh:BAABLgAECn8qAAIdAAkJCxiSFQCLAgAdAAkJCxiSFQCLAgAAAA==.Trelephant:BAAALgAECgMJBQAAAA==.Trulydps:BAABLgAECn8kAAIXAAkJRg+8OwDbAQAXAAkJRg+8OwDbAQAAAA==.Trulyog:BAAALgAECgQJBAAAAA==.',
Tu='Tubbsmcgee:BAACLgAFFH8YAAIbAAYJ6x9JBABUAgAbAAYJ6x9JBABUAgAuAAQKfyUAAhsACQkrJLgHAPkCABsACQkrJLgHAPkCAAAA.Tukkit:BAAALgAECgUJDAAAAA==.',
Tw='Twistedshot:BAAALgADCggJCAAAAA==.Twizzler:BAABLgAECn9FAAIBAAkJiAU9jQBDAQABAAkJiAU9jQBDAQAAAA==.',
Ty='Tyraniik:BAAALgADCgYJCAAAAA==.',
['Të']='Tërris:BAABLgAECn8aAAIJAAgJ9xD8HQBOAQAJAAgJ9xD8HQBOAQAAAA==.',
['Tî']='Tîlldeath:BAAALgAECgUJBwAAAA==.',
Uj='Uji:BAAALgADCgEJAQAAAA==.',
Ur='Urowndad:BAAALgAECgUJBQABLgAECggJFgAMAL0TAA==.Urownmother:BAAALgADCgUJBQABLgAECggJFgAMAL0TAA==.',
Va='Vaellian:BAAALgAECgYJDAAAAA==.Vallez:BAECLgAFFH8QAAMcAAMJoh9PHwAPAQAcAAMJoh9PHwAPAQAMAAIJKQN8pgA8AAAuAAQKfyYAAxwACAneHjIWAF8CABwACAneHjIWAF8CAAwAAgnbCa9FATIAAAAA.Vanillaghost:BAAALgADCgIJAQAAAA==.Varnusshadow:BAAALgAECgEJAQAAAA==.',
Ve='Vearik:BAAALgADCggJDQAAAA==.Velladoree:BAABLgAECn8YAAIUAAgJXgc4VADsAAAUAAgJXgc4VADsAAAAAA==.Vendaryn:BAAALgADCggJCAAAAA==.Vexahlia:BAAALgADCgMJAwAAAA==.',
Vg='Vgurlpally:BAAALgADCgYJBgAAAA==.',
Vy='Vynlorlan:BAAALgADCgMJAwABLgAECgMJBAAaAAAAAA==.',
Wa='Waveygravee:BAAALgAECgIJAwAAAA==.Wavygraivy:BAABLgAECn8WAAIbAAYJ2BXORACBAQAbAAYJ2BXORACBAQAAAA==.',
We='Wedragon:BAAALgAECgQJDgAAAA==.',
Wh='Wheelchair:BAACLgAFFH8LAAIIAAQJOxtAWQApAQAIAAQJOxtAWQApAQAuAAQKfxwAAggACAkSJF0SAA4DAAgACAkSJF0SAA4DAAAA.',
Wo='Woofwoof:BAAALgAFFAIJAgAAAA==.',
Wu='Wullemage:BAAALgADCgcJEwABLgAFFAYJGgAjAGkcAA==.',
['Wå']='Wåsp:BAABLgAECn8cAAIGAAcJyAZ6ngDIAAAGAAcJyAZ6ngDIAAAAAA==.',
Xb='Xb:BAAALgAECgcJBQAAAA==.',
Xh='Xhexana:BAABLgAECn8wAAIbAAkJdBW8IQAsAgAbAAkJdBW8IQAsAgABLgAECgkJPQAXABgTAA==.',
Xi='Xiaopo:BAAALgAECgEJAQABLgAFFAQJEgAbADEmAA==.',
Xr='Xrael:BAAALgAECgEJAQABLgAFFAMJDgAHANQhAA==.Xrayl:BAACLgAFFH8OAAMHAAMJ1CEIEQAiAQAHAAMJ1CEIEQAiAQAfAAMJxAzQNAC8AAAuAAQKfyEAAwcACAlsIawSABcCAAcABwlmIqwSABcCAB8AAQmOG/N9AE8AAAAA.',
Xz='Xzerocool:BAABLgAECn8WAAQMAAgJvRPIfgBXAQAMAAgJvRPIfgBXAQAQAAIJshMqNgBuAAAcAAEJmQMkkwAiAAAAAA==.',
Ya='Yannii:BAAALgADCgcJDgAAAA==.',
Ye='Yenko:BAAALgADCgIJAgAAAA==.',
Yo='Yolo:BAAALgADCgcJCwAAAA==.Yoshikazu:BAAALgAECgYJBwAAAA==.Yoyoboy:BAAALgADCgEJAQAAAA==.',
Za='Zaarah:BAAALgAECgMJAwAAAA==.',
Ze='Zellek:BAAALgADCgEJAQAAAA==.Zendezoth:BAABLgAECn8jAAIWAAkJpRkvAwBeAgAWAAkJpRkvAwBeAgAAAA==.Zephik:BAAALgADCgEJAQAAAA==.Zerofrost:BAABLgAECn8lAAIBAAkJDRiSOQAdAgABAAkJDRiSOQAdAgAAAA==.Zevra:BAAALgADCgMJAwAAAA==.',
Zh='Zhiva:BAABLgAECn8rAAIDAAcJMQtrPAAEAQADAAcJMQtrPAAEAQAAAA==.',
Zu='Zul:BAACLgAFFH8UAAIjAAMJXiOrGwAhAQAjAAMJXiOrGwAhAQAuAAQKfzEAAyMACAkFJAsMANcCACMACAkFJAsMANcCACcAAQnLAkMiACQAAAAA.',
Zy='Zykoz:BAABLgAECn8uAAIjAAkJpCGXAwD9AgAjAAkJpCGXAwD9AgAAAA==.',
['Ða']='Ðamned:BAABLgAECn8YAAIRAAYJ8hvELgCnAQARAAYJ8hvELgCnAQABLgAFFAIJCAAIANMeAA==.',
['Ÿo']='Ÿoshi:BAABLgAECn8bAAIXAAgJhQ/8TQB/AQAXAAgJhQ/8TQB/AQAAAA==.',
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
