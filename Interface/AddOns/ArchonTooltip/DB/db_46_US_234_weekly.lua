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

local lookup = {'Mage-Frost','Warlock-Destruction','Druid-Balance','Warlock-Demonology','Warlock-Affliction','DeathKnight-Blood','DeathKnight-Unholy','Unknown-Unknown','Priest-Holy','Paladin-Retribution','DemonHunter-Devourer','Warrior-Fury','Warrior-Arms','Shaman-Enhancement','Paladin-Protection','Shaman-Elemental','Monk-Windwalker','DemonHunter-Vengeance','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Paladin-Holy','Druid-Restoration','Priest-Shadow','Monk-Brewmaster','Druid-Feral','Hunter-Survival','Rogue-Subtlety','Rogue-Outlaw','Shaman-Restoration','DemonHunter-Havoc','Evoker-Preservation','Priest-Discipline','Warrior-Protection','Rogue-Assassination',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=46,date='2026-05-17',data={Ab='Abomination:BAAALgADCgMJAwAAAA==.',
Ae='Aeidail:BAACLgAFFH8XAAIBAAYJJBtPFwCuAQABAAYJJBtPFwCuAQAuAAQKfyQAAgEACAmnI0McAAUDAAEACAmnI0McAAUDAAAA.Aelaria:BAAALgADCgMJAwAAAA==.Aeviria:BAABLgAECn8XAAICAAgJpgzXCwA8AQACAAgJpgzXCwA8AQAAAA==.',
Ag='Agraceful:BAACLgAFFH8HAAIDAAMJrQR0JACuAAADAAMJrQR0JACuAAAuAAQKfxwAAgMACAmYEu4fAHwBAAMACAmYEu4fAHwBAAAA.',
Ai='Ailee:BAAALgAECgYJDAAAAA==.Aios:BAAALgADCgcJCQAAAA==.Aiza:BAACLgAFFH8KAAIEAAMJYQQVYQC7AAAEAAMJYQQVYQC7AAAuAAQKfyoAAwQACAnMEkBEAP8BAAQACAnMEkBEAP8BAAUAAQkAAPQ3AB0AAAAA.',
Al='Aldanil:BAAALgADCgMJAwAAAA==.',
An='Animalfriend:BAAALgAECgIJAgAAAA==.Anklesmasher:BAAALgAECgYJEAAAAA==.Anyah:BAAALgAECgQJCwAAAA==.',
Ap='Apolloo:BAAALgADCgMJAwAAAA==.',
Ar='Arfaz:BAABLgAECn8dAAMGAAYJ9hS7KQC9AAAHAAUJBhXPoQDtAAAGAAYJWAq7KQC9AAAAAA==.Armbrost:BAAALgAECgYJCQAAAA==.Artimås:BAAALgADCgcJCAAAAA==.Arwynne:BAAALgADCgMJAwAAAA==.Arçano:BAAALgAECgEJAQABLgAECggJEwAIAAAAAA==.',
As='Ascension:BAAALgADCgcJBgABLgAECgkJNgAEABIkAA==.Astrastar:BAAALgAECgYJEgAAAA==.',
Av='Avarin:BAAALgADCgEJAQAAAA==.',
Ay='Aymont:BAAALgAECgQJBQAAAA==.',
Ba='Baerd:BAABLgAECn8aAAIJAAcJZhPeIACAAQAJAAcJZhPeIACAAQAAAA==.Barlz:BAAALgAECgEJAQAAAA==.',
Be='Beanpaste:BAAALgAECgcJAQABLgAFFAMJBwAHANwUAA==.Beanutbutter:BAAALgADCgIJAgABLgAFFAMJBwAHANwUAA==.Beaty:BAAALgAECgIJAgAAAA==.Bebby:BAAALgAECgYJEAAAAA==.Belonara:BAAALgADCgIJBAAAAA==.Belwolf:BAAALgAECgMJCwAAAA==.Bergstrom:BAABLgAECn8zAAIKAAkJuBkPHQBeAgAKAAkJuBkPHQBeAgAAAA==.Bethanymarie:BAAALgAECgEJAQAAAA==.Betrayer:BAAALgADCgQJAwABLgAECgkJNgAEABIkAA==.',
Bi='Biancaneve:BAAALgAECgMJAwAAAA==.Bighero:BAACLgAFFH8HAAILAAMJ8gUZSwC/AAALAAMJ8gUZSwC/AAAuAAQKfxsAAgsACAlVEVlvAFYBAAsACAlVEVlvAFYBAAAA.Bigmike:BAAALgADCgEJAQAAAA==.',
Bl='Blakkjezus:BAAALgAECgQJBwAAAA==.Blitzbolts:BAAALgAECgEJAgAAAA==.Bludo:BAACLgAFFH8MAAMMAAQJfxXkEgA4AQAMAAQJHRXkEgA4AQANAAEJTxuFIgBRAAAuAAQKfx4AAwwACQl6IWgZAIACAAwACAk5GWgZAIACAA0ABgl9HFMYADYBAAAA.',
Bo='Boe:BAABLgAECn8dAAIOAAgJgQgSEQA+AQAOAAgJgQgSEQA+AQAAAA==.Bombacløt:BAABLgAECn8gAAMCAAgJ6w64DgARAQAEAAgJvgwGVwBnAQACAAcJbQ64DgARAQAAAA==.Bowdirte:BAAALgAECgUJBwAAAA==.',
Br='Brastin:BAABLgAECn8pAAIPAAkJNx48AwCiAgAPAAkJNx48AwCiAgABLgAFFAQJDAAQAIQMAA==.Brenell:BAABLgAECn8tAAIBAAkJxiAqFwCdAgABAAkJxiAqFwCdAgAAAA==.',
Bu='Bubblehearth:BAAALgAECgYJBQABLgAECgkJIQALAEwYAA==.Buffet:BAAALgAECgQJBAABLgAECgkJIQALAEwYAA==.Buhlitz:BAAALgAECgEJAgAAAA==.',
By='Bynis:BAABLgAECn8fAAILAAkJbhQkOQCkAQALAAkJbhQkOQCkAQAAAA==.',
Ca='Cabëla:BAAALgADCgUJBQAAAA==.Cactusjack:BAAALgADCgUJBQAAAA==.Cadorex:BAAALgADCgEJAQAAAA==.Caffeinefree:BAAALgADCggJBwAAAA==.Calacolinda:BAAALgAECgQJBgAAAA==.Cavakworm:BAAALgADCgEJAQAAAA==.Caylin:BAAALgADCgUJBgAAAA==.Cayusedemon:BAAALgADCgEJAQAAAA==.Cayusemage:BAAALgADCgkJCQAAAA==.',
Ch='Chariscrushr:BAAALgAECgQJBAABLgAFFAYJFwARABccAA==.Chen:BAAALgADCgIJAgAAAA==.Choal:BAAALgAECgEJAQAAAA==.',
Ci='Cinnamongirl:BAAALgAECgcJEgAAAA==.',
Co='Corahin:BAABLgAECn8bAAIQAAYJGxASRAA5AQAQAAYJGxASRAA5AQAAAA==.Corious:BAAALgAECgQJCQAAAA==.Cosmos:BAAALgAECgYJDQAAAA==.Cougarhunter:BAAALgAECgcJBwAAAA==.',
Cr='Crokus:BAAALgADCggJCAAAAA==.',
Cu='Cuecumba:BAABLgAECn8lAAISAAgJsyVSAQDpAgASAAgJsyVSAQDpAgAAAA==.',
Da='Daemonerror:BAAALgAECgUJBQABLgAECgcJKgATAI0jAA==.Dalren:BAACLgAFFH8UAAMUAAQJ2R9/EABzAQAUAAQJ2R9/EABzAQAVAAEJuwNtCwBLAAAuAAQKfzsAAxQACQlIJcsDAAoDABQACQkLJcsDAAoDABUABgnyIEMMABcCAAAA.Dalryn:BAAALgAECgYJDQABLgAFFAQJFAAUANkfAA==.Dalvix:BAAALgADCgEJAQABLgAECggJJAALAFcfAA==.Damocles:BAABLgAECn8YAAIBAAYJlwwOnAASAQABAAYJlwwOnAASAQAAAA==.Dartagnan:BAACLgAFFH8FAAIWAAMJpBd+MgD9AAAWAAMJpBd+MgD9AAAuAAQKfyIAAxYACAmkHLpQAGYBABYABgnnHbpQAGYBABcABgn3FNwUANsAAAAA.Darthmaul:BAABLgAECn8oAAIDAAkJug9uGgCrAQADAAkJug9uGgCrAQAAAA==.',
De='Deay:BAAALgADCgQJAQAAAA==.Delexa:BAAALgADCgkJMAAAAA==.Dendiian:BAABLgAECn8UAAIYAAYJXxUQGAAnAQAYAAYJXxUQGAAnAQAAAA==.',
Di='Didipullthat:BAAALgADCgYJFwABLgAECgkJIQALAEwYAA==.Diem:BAABLgAECn8dAAIWAAgJyw2mSgB4AQAWAAgJyw2mSgB4AQAAAA==.Dirtydotss:BAABLgAECn8VAAMFAAcJFwfXEgD/AAAFAAYJYQbXEgD/AAAEAAYJ5wTKqAC+AAAAAA==.Divigitives:BAAALgAECgQJBAAAAA==.',
Do='Docrivan:BAAALgAECgYJCwAAAA==.Docsassist:BAAALgAECgMJAwABLgAECgYJCwAIAAAAAA==.Doregit:BAABLgAECn8jAAIMAAgJOhzmEQAnAgAMAAgJOhzmEQAnAgAAAA==.Dowedoes:BAABLgAECn81AAIKAAkJCRfxKQAbAgAKAAkJCRfxKQAbAgAAAA==.',
Dr='Drachula:BAAALgAECgYJEgAAAA==.Dracultra:BAAALgAECgIJAgABLgAECgkJIAAZAF0fAA==.Drakcheese:BAAALgADCgUJBQAAAA==.Dreolan:BAABLgAECn8yAAIaAAkJfQ8+LwCqAQAaAAkJfQ8+LwCqAQAAAA==.Drynnai:BAAALgADCgEJAgAAAA==.',
Dy='Dyala:BAACLgAFFH8GAAMaAAMJjg9vLADKAAAaAAMJjg9vLADKAAADAAEJ2wE9OAAyAAAuAAQKfx4AAxoACAlLErdfADMBABoACAlLErdfADMBAAMAAgk0CmdeAFIAAAAA.',
['Dö']='Dönövan:BAABLgAECn8eAAIKAAgJ8Q/bVACPAQAKAAgJ8Q/bVACPAQAAAA==.',
El='Eloise:BAAALgAECgYJDQAAAA==.Elvenbane:BAABLgAECn8mAAIbAAkJrxPWEgD3AQAbAAkJrxPWEgD3AQAAAA==.',
Em='Emily:BAAALgAECgYJDAAAAA==.Emry:BAAALgADCgYJBgABLgAECgcJHQATADgPAA==.',
En='Enable:BAEBLgAECn8YAAIcAAkJNRc0DwASAgAcAAkJNRc0DwASAgABLgAECggJLwAPAE8iAA==.',
Ep='Epictool:BAAALgAECggJCwAAAA==.',
Et='Ethereal:BAAALgAECgEJAQAAAA==.',
Fa='Fabel:BAEBLgAECn8vAAIPAAgJTyJDBAB6AgAPAAgJTyJDBAB6AgAAAA==.Falahad:BAAALgAECgEJAQABLgAFFAMJBwADAHEKAA==.Faltree:BAACLgAFFH8HAAMDAAMJcQrPIQDGAAADAAMJcQrPIQDGAAAaAAIJ6RPzOgCJAAAuAAQKfx8ABBoACAmxGP5TAFcBABoABglPGP5TAFcBAAMACAkLFzYlAFQBAB0AAQnfAUo6AB8AAAAA.Fathershale:BAAALgADCgcJDgAAAA==.',
Fi='Firelord:BAAALgADCgEJAQAAAA==.',
Fo='Foulcor:BAABLgAECn8cAAMZAAgJkx6sDwBfAgAZAAgJkx6sDwBfAgAKAAYJ5xCijwAVAQAAAA==.',
Fr='Freakadeek:BAAALgAECggJEQAAAA==.Freâkadeek:BAAALgAECgIJAwABLgAECggJEQAIAAAAAA==.Freäk:BAAALgADCgMJAwABLgAECggJEQAIAAAAAA==.Frieren:BAABLgAECn8sAAIBAAgJQxP2VgCgAQABAAgJQxP2VgCgAQAAAA==.Frink:BAAALgAECgEJAQABLgAECgkJNQAeAF0jAA==.',
Fu='Fundetected:BAAALgAECgMJAwABLgAECgkJIQALAEwYAA==.Furyofthenug:BAAALgADCgMJAwAAAA==.',
Ga='Gabbyo:BAABLgAECn8aAAIaAAcJJAWRZwDGAAAaAAcJJAWRZwDGAAAAAA==.Galadorn:BAABLgAECn8kAAILAAgJVx8FFgBbAgALAAgJVx8FFgBbAgAAAA==.Gallgamesh:BAAALgADCgIJAgAAAA==.Garfall:BAAALgAECgcJDAAAAA==.Garga:BAAALgADCgMJBAABLgAECgEJAQAIAAAAAA==.',
Ge='Gerdash:BAAALgAECgMJBAAAAA==.Gerred:BAAALgAECgcJEgAAAA==.',
Gh='Ghallow:BAAALgAECgQJEAAAAA==.Ghosty:BAACLgAFFH8JAAIfAAQJOxWSEgA4AQAfAAQJOxWSEgA4AQAuAAQKfyUAAh8ABwlQIJIUAG4CAB8ABwlQIJIUAG4CAAAA.',
Gi='Gimp:BAAALgAECgEJAQAAAA==.',
Gl='Gladur:BAAALgAFFAEJAQABLgAFFAYJFwABACQbAA==.',
Go='Goldenflame:BAAALgAECgUJBgAAAA==.Goldenlily:BAAALgAECgYJEgAAAA==.Goldenmunc:BAABLgAECn8kAAIBAAgJdhVyRADVAQABAAgJdhVyRADVAQAAAA==.Goldenone:BAAALgAECgQJBQAAAA==.Goldenpants:BAABLgAECn8eAAIMAAgJahOiIgCdAQAMAAgJahOiIgCdAQAAAA==.',
Gr='Grievous:BAABLgAECn81AAISAAkJFiVZAABRAwASAAkJFiVZAABRAwAAAA==.',
['Gû']='Gûrth:BAAALgADCgcJBwAAAA==.',
Ha='Hailmary:BAABLgAECn8fAAIJAAgJgCUpAgBcAwAJAAgJgCUpAgBcAwAAAA==.Harusen:BAABLgAECn8YAAIgAAkJ9h7JAQCUAgAgAAkJ9h7JAQCUAgAAAA==.',
Hi='Hildalsind:BAAALgADCgkJCQABLgAFFAMJCQABAIMdAA==.',
Ho='Homestar:BAAALgADCgEJAQAAAA==.Hooll:BAAALgAECgIJAgAAAA==.Hornreaper:BAABLgAECn8bAAIUAAYJ5hfvJACVAQAUAAYJ5hfvJACVAQAAAA==.Hotshot:BAAALgAECgMJAwAAAA==.',
Hu='Hubbabubbajr:BAAALgAECgEJAQABLgAECgkJKgAaAOgaAA==.Hurin:BAAALgAECgcJDgAAAA==.Huur:BAAALgAECgEJAQAAAA==.',
Hy='Hyetta:BAAALgAECgQJBgABLgAECgkJGAAgAPYeAA==.Hyir:BAAALgADCgYJBwABLgAFFAMJCgARANQbAA==.',
Il='Illiya:BAAALgAECgQJCwAAAA==.',
Ir='Irôn:BAAALgAECgEJAQAAAA==.',
Iu='Iutara:BAAALgAECgYJBgAAAA==.',
Ja='Jaalein:BAAALgADCgcJDgAAAA==.Jayonor:BAABLgAECn8sAAQQAAkJMBCLHQCtAQAQAAkJMBCLHQCtAQAOAAYJ9we4GgAeAQAhAAcJ5AblVAAJAQAAAA==.',
Je='Jek:BAAALgAECgUJBQAAAA==.',
Jo='Joryu:BAAALgADCgIJAwAAAA==.',
Ju='Juicycucci:BAAALgAECgcJDQABLgAECgkJIQALAEwYAA==.',
Ka='Kaevrielle:BAEBLgAECn8eAAMSAAkJjBuZBAAoAgASAAkJjBuZBAAoAgAiAAEJVgqqUgAuAAAAAA==.Kaison:BAAALgAECgcJBwABLgAECgkJHwALAG4UAA==.Kaladîn:BAAALgAECgMJAwABLgAFFAYJFwABACQbAA==.Kalii:BAAALgADCgQJBAAAAA==.Kamel:BAAALgADCgYJBgAAAA==.Karwin:BAABLgAECn8YAAIBAAYJ2BXmgwA7AQABAAYJ2BXmgwA7AQAAAA==.Katakuri:BAAALgAECgEJAgAAAA==.',
Ke='Keeper:BAAALgAECgUJBwABLgAECgkJOgAKAL0kAA==.Keeperodark:BAAALgAECggJEAABLgAECgkJOgAKAL0kAA==.Keeperolight:BAABLgAECn86AAMKAAkJvST4AwA7AwAKAAkJvST4AwA7AwAZAAEJgRgUkABAAAAAAA==.Kemanorel:BAAALgADCgcJDgABLgAECgkJJgAbAK8TAA==.',
Ki='Kianth:BAAALgADCgkJEgAAAA==.Killkat:BAABLgAECn8lAAIBAAgJEBgAPQDuAQABAAgJEBgAPQDuAQAAAA==.',
Ko='Kodera:BAABLgAECn8YAAMjAAYJhBx3CwDjAQAjAAYJhBx3CwDjAQAVAAQJNxsrCwAsAQAAAA==.Koojo:BAAALgADCgQJBQAAAA==.Kovae:BAAALgADCgEJAQAAAA==.',
Kr='Kraken:BAAALgADCgUJBQAAAA==.',
Ky='Kyaritin:BAAALgAECgMJAwABLgAECgYJCgAIAAAAAA==.Kyokei:BAAALgAECgEJAQAAAA==.',
La='Laiho:BAAALgADCgUJCAAAAA==.Lans:BAAALgAFFAEJAQAAAA==.Larew:BAABLgAECn8fAAIKAAgJChYcSQCvAQAKAAgJChYcSQCvAQAAAA==.Lazytemplar:BAAALgADCgMJAwABLgAECgUJDAAIAAAAAA==.',
Le='Lealla:BAABLgAECn81AAIDAAkJ5SCoBADhAgADAAkJ5SCoBADhAgAAAA==.Leodin:BAAALgAECgEJAgAAAA==.Leorus:BAAALgAECgIJAgAAAA==.Lethhunt:BAACLgAFFH8PAAMXAAQJfxAyDQAbAQAXAAQJpQ0yDQAbAQAWAAIJWw4MGgCeAAAuAAQKfyoAAxcACQldHuEHAMMBABcACQlTG+EHAMMBABYAAgk+JFKHANIAAAAA.',
Li='Lilmistfox:BAAALgAECgUJBwABLgAECgcJDwAIAAAAAA==.Lioh:BAAALgAECgQJBAAAAA==.Lizardgang:BAAALgAECgYJDQAAAA==.',
Lo='Loganshu:BAAALgADCgcJEgAAAA==.Lokan:BAACLgAFFH8HAAIeAAMJWRh0EQAHAQAeAAMJWRh0EQAHAQAuAAQKfycAAh4ACAmcG1QMACoCAB4ACAmcG1QMACoCAAAA.Lots:BAACLgAFFH8HAAIEAAMJnxreQAANAQAEAAMJnxreQAANAQAuAAQKfyQAAwQACAnsIIgvAE8CAAQABwn1IIgvAE8CAAIABAneHkcsAA0BAAAA.',
Lu='Ludacast:BAAALgADCgIJAgAAAA==.Ludafists:BAAALgADCgcJDAAAAA==.Ludakris:BAABLgAECn8cAAIPAAgJphgvCgDcAQAPAAgJphgvCgDcAQAAAA==.Lumanoth:BAAALgAECgYJBgAAAA==.',
Ly='Lyna:BAABLgAECn8gAAIhAAkJpRNkLQC1AQAhAAkJpRNkLQC1AQAAAA==.Lynaya:BAAALgADCgIJAgAAAA==.',
['Lí']='Líonheart:BAABLgAECn8UAAMZAAYJ+Bk5OAApAQAZAAYJ+Bk5OAApAQAKAAEJQwSrVQEoAAAAAA==.',
['Lî']='Lîghtless:BAACLgAFFH8PAAIBAAYJBhpoGQClAQABAAYJBhpoGQClAQAuAAQKfxcAAgEACAmfJUchAO4CAAEACAmfJUchAO4CAAAA.',
['Lú']='Lúckally:BAAALgADCgQJBAABLgAECgYJCgAIAAAAAA==.Lúckÿ:BAAALgAECgYJCgAAAA==.',
Ma='Mahina:BAAALgAECgIJAgAAAA==.Marcille:BAABLgAECn8mAAIBAAcJpxQJhgDFAQABAAcJpxQJhgDFAQAAAA==.Mathor:BAAALgAECgEJAgAAAA==.Mavrbg:BAAALgAECgQJBQAAAA==.Mayhaps:BAABLgAECn87AAMWAAkJjhrFFwBWAgAWAAkJjhrFFwBWAgAXAAEJZACpmgAYAAAAAA==.',
Mc='Mcbain:BAABLgAECn81AAIeAAkJXSNSAQAsAwAeAAkJXSNSAQAsAwAAAA==.',
Me='Melrine:BAAALgADCgMJAwAAAA==.Mentaltitty:BAABLgAECn8YAAIBAAgJSBKGUgCrAQABAAgJSBKGUgCrAQAAAA==.',
Mi='Minerwor:BAAALgAECgMJBAAAAA==.Mirrayla:BAAALgADCgYJBgAAAA==.Misty:BAAALgADCgYJBgAAAA==.',
Mm='Mmisty:BAABLgAECn8zAAIDAAkJgRD7FwDDAQADAAkJgRD7FwDDAQAAAA==.',
Mo='Moarthretplz:BAAALgAECgUJCQABLgAECgcJDwAIAAAAAA==.Mohji:BAAALgAFFAEJAQABLgAFFAcJGgAkAOgUAA==.Momometaru:BAABLgAECn8jAAQEAAgJNBeWPwCrAQAEAAgJwhOWPwCrAQACAAUJNhRyJgAsAQAFAAMJzxqVGACUAAAAAA==.Monsterbee:BAABLgAECn8xAAIEAAkJsw0sQACpAQAEAAkJsw0sQACpAQAAAA==.',
Mu='Mustypizza:BAABLgAECn8lAAICAAgJPxcrBQDTAQACAAgJPxcrBQDTAQAAAA==.',
Mx='Mxicancowboy:BAAALgADCgEJAgAAAA==.',
My='Mystery:BAABLgAECn81AAMjAAkJNSDNAQA/AwAjAAkJNSDNAQA/AwAVAAQJ/BAIDwDgAAAAAA==.',
['Mê']='Mêøwzêr:BAAALgAECggJEwAAAA==.',
['Mÿ']='Mÿst:BAAALgAECgMJBAAAAA==.',
Na='Narashi:BAAALgAECgQJBAAAAA==.Naril:BAAALgADCgUJBQAAAA==.Nats:BAABLgAECn8kAAIhAAgJSxGwOACfAQAhAAgJSxGwOACfAQAAAA==.',
Ne='Neameny:BAABLgAECn81AAIWAAkJYRHFLQDhAQAWAAkJYRHFLQDhAQAAAA==.',
Ni='Nianji:BAAALgADCgYJCwAAAA==.Nightstar:BAAALgADCgMJAwAAAA==.Nightworld:BAAALgADCgcJDgAAAA==.',
No='Noctum:BAAALgAECgUJBQAAAA==.Nordicpally:BAAALgADCgQJBAAAAA==.Notgim:BAAALgADCggJCAAAAA==.',
Nu='Nualrossan:BAAALgADCgMJAgAAAA==.Nubrac:BAAALgAECggJEgAAAA==.',
Ny='Nylux:BAAALgAECgYJDwAAAA==.',
Ob='Oblivion:BAABLgAECn82AAMEAAkJEiRaBQAWAwAEAAkJEiRaBQAWAwACAAEJAABRXQBXAAAAAA==.',
Oo='Oostren:BAAALgAECgEJAgAAAA==.',
Or='Orsyp:BAAALgADCgkJGgAAAA==.',
Pa='Palockie:BAAALgADCgEJAQAAAA==.Pandas:BAABLgAECn8YAAIQAAgJVQ8QKQBdAQAQAAgJVQ8QKQBdAQAAAA==.Partyrocker:BAABLgAECn8WAAIeAAcJag4bIABfAQAeAAcJag4bIABfAQABLgAECggJEQAIAAAAAA==.',
Pi='Pixae:BAACLgAFFH8HAAIjAAMJ1ASlGQCjAAAjAAMJ1ASlGQCjAAAuAAQKfx4AAiMABwlgCo8XABkBACMABwlgCo8XABkBAAAA.Pixiechaos:BAAALgAECgIJAgAAAA==.',
Po='Poliahu:BAAALgAECgQJBwAAAA==.Porthoss:BAAALgADCggJDgAAAA==.Powerplant:BAACLgAFFH8TAAIWAAUJbCJAEgBmAQAWAAUJbCJAEgBmAQAuAAQKfyYAAhYACQkcJCgIAA4DABYACQkcJCgIAA4DAAAA.Poyoram:BAAALgADCgEJAQAAAA==.',
Py='Pyralys:BAABLgAECn8xAAMJAAkJxw0CGwCzAQAJAAkJxw0CGwCzAQAbAAMJqQLMaAAvAAAAAA==.',
Ra='Ragemonk:BAAALgAECgUJDAAAAA==.Ragetality:BAAALgADCgEJAQABLgAECgUJDAAIAAAAAA==.Rakthera:BAAALgADCgcJBwAAAA==.Raserei:BAAALgADCgYJBwAAAA==.Rasputain:BAAALgADCgYJCgAAAA==.Rasputein:BAAALgADCgcJBwAAAA==.Ravara:BAAALgADCgYJBgABLgAECggJJAALAFcfAA==.Rayné:BAAALgADCgcJCwAAAA==.Razgaurd:BAAALgAECgMJAwAAAA==.',
Re='Regice:BAAALgAECgcJBwABLgAECgkJLgAGAJkfAA==.Regicee:BAABLgAECn8uAAMGAAkJmR8qBQCjAgAGAAkJmR8qBQCjAgAHAAQJtwhZ1ACXAAAAAA==.Retam:BAAALgADCgYJEQAAAA==.Revakos:BAAALgADCgMJAwAAAA==.',
Rh='Rhysandra:BAAALgAECgQJCQAAAA==.',
Ri='Ribble:BAAALgADCgMJAwAAAA==.Riffraff:BAAALgAECgcJAwAAAA==.Ripcord:BAAALgAECgUJCAAAAA==.Ripperoni:BAAALgAECgEJAgAAAA==.Rizek:BAAALgAECgUJBgABLgAECgcJHQATADgPAA==.Rizzx:BAAALgAECgEJAQABLgAECgEJAQAIAAAAAA==.',
Ro='Rockdyou:BAABLgAECn8jAAIHAAgJPx4ALAAVAgAHAAgJPx4ALAAVAgAAAA==.Roglef:BAAALgAECgQJCQAAAA==.Rotlobster:BAAALgAECgYJCQAAAA==.Roxxy:BAAALgAECgQJBAAAAA==.',
Ru='Rundvelt:BAACLgAFFH8HAAIPAAMJeA1vCACmAAAPAAMJeA1vCACmAAAuAAQKfx8AAg8ACAmpEEYUAD0BAA8ACAmpEEYUAD0BAAAA.',
Sa='Sage:BAAALgADCgcJCAAAAA==.Sandwich:BAAALgAECgcJCAAAAA==.Sapkick:BAAALgAECgQJBwAAAA==.',
Se='Serdragon:BAAALgADCgQJBAAAAA==.Servoid:BAAALgAECgUJCQAAAA==.',
Sh='Shando:BAAALgAECgEJAQAAAA==.Shiftstyle:BAEALgAECgEJAQAAAA==.Shtanky:BAACLgAFFH8HAAIlAAMJoQ2CFAC2AAAlAAMJoQ2CFAC2AAAuAAQKfx8AAiUACAnEC/gYADEBACUACAnEC/gYADEBAAAA.',
Si='Silentsocks:BAAALgAECgUJDAAAAA==.Sixsixsix:BAAALgAECgcJCgABLgAFFAIJCAAHANMeAA==.',
Sk='Skoogz:BAAALgAECgkJCgAAAA==.',
So='Soggyy:BAAALgADCgYJCwAAAA==.Solar:BAABLgAECn8VAAQRAAcJyRkxLwBtAQARAAYJCxYxLwBtAQAcAAYJrhzoOABmAQATAAEJUwIhhQAbAAAAAA==.Soulfulgingr:BAAALgAECgMJAwAAAA==.',
St='Starlagosa:BAAALgADCgYJCQAAAA==.Styx:BAAALgAECgMJAwAAAA==.',
Su='Sunbake:BAAALgAECgUJBwAAAA==.',
Sw='Sweetbbyraze:BAACLgAFFH8NAAMVAAQJfReRBQC7AAAUAAQJvQvxEgDoAAAVAAMJmRaRBQC7AAAuAAQKfyYAAxUACAkpIVIGAJACABUABwm8IVIGAJACABQAAwnyHEdSAJ0AAAAA.',
Sy='Sylaena:BAABLgAECn8UAAIXAAgJqAMkGAC5AAAXAAgJqAMkGAC5AAAAAA==.Sylvrstorm:BAAALgAECgMJAwAAAA==.',
['Së']='Sërënity:BAAALgAECgQJCwAAAA==.',
['Sí']='Sín:BAAALgAECgcJDAABLgAFFAIJCAAHANMeAA==.',
Ta='Talipally:BAABLgAECn8bAAIKAAkJlw8tVQCOAQAKAAkJlw8tVQCOAQAAAA==.Taliwhacker:BAAALgADCgYJEAABLgAECgkJGwAKAJcPAA==.Talonleafgrd:BAAALgADCgYJBgAAAA==.Tanaka:BAABLgAECn8YAAIHAAcJvxGAXwByAQAHAAcJvxGAXwByAQAAAA==.Tanisong:BAAALgAECgMJBQAAAA==.Tassadar:BAAALgAECgQJBgAAAA==.',
Te='Tepeyollotl:BAAALgADCgEJAQAAAA==.Terayus:BAAALgADCgcJDAAAAA==.Teyliah:BAAALgADCgMJAwAAAA==.',
Tf='Tf:BAAALgAECgYJBgABLgAFFAIJCAAHANMeAA==.',
Th='Thekingpunch:BAABLgAECn8qAAITAAcJjSN4CQCwAgATAAcJjSN4CQCwAgAAAA==.Thenle:BAAALgADCggJDgAAAA==.Thunderblitz:BAABLgAECn8bAAIZAAcJPgiOOgAcAQAZAAcJPgiOOgAcAQAAAA==.Thurmus:BAAALgADCgkJMAAAAA==.',
Ti='Tillwar:BAABLgAECn8zAAIMAAkJ+RyNCgCBAgAMAAkJ+RyNCgCBAgAAAA==.',
To='Tofu:BAABLgAECn8iAAIHAAkJgxeUJwApAgAHAAkJgxeUJwApAgAAAA==.Tortillachip:BAAALgAECgEJAgAAAA==.Toxidot:BAAALgAECgEJAQAAAA==.',
Tr='Treibh:BAABLgAECn8hAAIaAAkJfBNIHgAXAgAaAAkJfBNIHgAXAgAAAA==.Trelephant:BAAALgAECgMJBQAAAA==.Trulydps:BAABLgAECn8fAAIWAAgJMw1rSQB8AQAWAAgJMw1rSQB8AQAAAA==.Trulyog:BAAALgAECgQJBAAAAA==.',
Tu='Tubbsmcgee:BAACLgAFFH8WAAIhAAQJMCY4CQDAAQAhAAQJMCY4CQDAAQAuAAQKfyUAAiEACQkrJLgHAPkCACEACQkrJLgHAPkCAAAA.Tukkit:BAAALgAECgMJAwAAAA==.',
Tw='Twistedshot:BAAALgADCggJCAAAAA==.Twizzler:BAABLgAECn8zAAIBAAkJnASjfABJAQABAAkJnASjfABJAQAAAA==.',
Ty='Tyraniik:BAAALgADCgYJCAAAAA==.',
['Të']='Tërris:BAAALgAECgcJEwAAAA==.',
['Tî']='Tîlldeath:BAAALgAECgUJBwAAAA==.',
Uj='Uji:BAAALgADCgEJAQAAAA==.',
Ur='Urowndad:BAAALgAECgUJBQABLgAECggJFgAKAL0TAA==.Urownmother:BAAALgADCgUJBQABLgAECggJFgAKAL0TAA==.',
Va='Vaellian:BAAALgAECgYJDAAAAA==.Vallez:BAECLgAFFH8KAAMZAAMJYRdVHgDoAAAZAAMJYRdVHgDoAAAKAAEJawJjgAA/AAAuAAQKfyUAAxkACAneHg8QAFoCABkACAneHg8QAFoCAAoAAgnbCa9FATIAAAAA.Vanillaghost:BAAALgADCgIJAQAAAA==.Varnusshadow:BAAALgAECgEJAQAAAA==.',
Ve='Vearik:BAAALgADCgcJCwAAAA==.Velladoree:BAAALgAECgYJDwAAAA==.Vendaryn:BAAALgADCggJCAAAAA==.Vexahlia:BAAALgADCgMJAwAAAA==.',
Vg='Vgurlpally:BAAALgADCgYJBgAAAA==.',
Vy='Vynlorlan:BAAALgADCgMJAwABLgAECgMJBAAIAAAAAA==.',
Wa='Waveygravee:BAAALgAECgIJAwAAAA==.Wavygraivy:BAAALgAECgYJDQAAAA==.',
We='Wedragon:BAAALgAECgQJCAAAAA==.',
Wh='Wheelchair:BAACLgAFFH8KAAIHAAQJOxvHOwBEAQAHAAQJOxvHOwBEAQAuAAQKfxwAAgcACAkSJF0SAA4DAAcACAkSJF0SAA4DAAAA.',
Wo='Woofwoof:BAAALgAECgEJAQAAAA==.',
Wu='Wullemage:BAAALgADCgcJEwABLgAFFAYJGgAfAGkcAA==.',
['Wå']='Wåsp:BAAALgAECgQJBwAAAA==.',
Xb='Xb:BAAALgAECgcJBQAAAA==.',
Xh='Xhexana:BAABLgAECn8nAAIhAAkJdBWdGQA0AgAhAAkJdBWdGQA0AgABLgAECgkJNQAWAGERAA==.',
Xr='Xrael:BAAALgAECgEJAQABLgAFFAMJCQARAJMfAA==.Xrayl:BAACLgAFFH8JAAMRAAMJkx8fDgAYAQARAAMJkx8fDgAYAQAcAAEJEA5yRQBEAAAuAAQKfyAAAxEACAlXH24RAPUBABEABwn4H24RAPUBABwAAQmOG/N9AE8AAAAA.',
Xz='Xzerocool:BAABLgAECn8WAAQKAAgJvRPYXgB3AQAKAAgJvRPYXgB3AQAPAAIJsBNGLgBqAAAZAAEJmQMgggAiAAAAAA==.',
Ya='Yannii:BAAALgADCgcJDgAAAA==.',
Ye='Yenko:BAAALgADCgIJAgAAAA==.',
Yo='Yolo:BAAALgADCgcJCwAAAA==.Yoshikazu:BAAALgAECgUJBQAAAA==.Yoyoboy:BAAALgADCgEJAQAAAA==.',
Za='Zaarah:BAAALgADCgMJAwAAAA==.',
Ze='Zellek:BAAALgADCgEJAQAAAA==.Zendezoth:BAABLgAECn8bAAIVAAgJ2BMoBgCxAQAVAAgJ2BMoBgCxAQAAAA==.Zephik:BAAALgADCgEJAQAAAA==.Zerofrost:BAABLgAECn8gAAIBAAgJWxXgSADHAQABAAgJWxXgSADHAQAAAA==.Zevra:BAAALgADCgMJAwAAAA==.',
Zh='Zhiva:BAABLgAECn8eAAIDAAYJTQqqPgDJAAADAAYJTQqqPgDJAAAAAA==.',
Zu='Zul:BAACLgAFFH8PAAIfAAMJXiPIEwAwAQAfAAMJXiPIEwAwAQAuAAQKfy8AAx8ACAkFIy4JAE8CAB8ACAkFIy4JAE8CACYAAQnLAkMiACQAAAAA.',
Zy='Zykoz:BAABLgAECn8lAAIfAAgJFSIuBgCOAgAfAAgJFSIuBgCOAgAAAA==.',
['Ða']='Ðamned:BAABLgAECn8YAAIQAAYJ8hvELgCnAQAQAAYJ8hvELgCnAQABLgAFFAIJCAAHANMeAA==.',
['Ÿo']='Ÿoshi:BAABLgAECn8bAAIWAAgJhQ/8TQB/AQAWAAgJhQ/8TQB/AQAAAA==.',
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
