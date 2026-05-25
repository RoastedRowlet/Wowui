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

local lookup = {'Mage-Frost','Warlock-Destruction','Druid-Balance','Warlock-Demonology','Warlock-Affliction','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Priest-Holy','Paladin-Retribution','DemonHunter-Devourer','Warrior-Fury','Warrior-Arms','Shaman-Enhancement','Paladin-Protection','Shaman-Elemental','Evoker-Preservation','Monk-Windwalker','DemonHunter-Vengeance','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Unknown-Unknown','Shaman-Restoration','Paladin-Holy','Druid-Restoration','Priest-Shadow','Monk-Brewmaster','Druid-Feral','DeathKnight-Frost','Hunter-Survival','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Havoc','Priest-Discipline','Rogue-Assassination',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=46,date='2026-05-24',data={Ab='Abomination:BAAALgADCgMJAwAAAA==.',
Ae='Aeidail:BAACLgAFFH8bAAIBAAYJQhzmHACyAQABAAYJQhzmHACyAQAuAAQKfyQAAgEACAmnI0McAAUDAAEACAmnI0McAAUDAAAA.Aelaria:BAAALgADCgMJAwAAAA==.Aeviria:BAABLgAECn8dAAICAAgJZhOyBwCrAQACAAgJZhOyBwCrAQAAAA==.',
Ag='Agraceful:BAACLgAFFH8HAAIDAAMJrQS/KgCrAAADAAMJrQS/KgCrAAAuAAQKfxwAAgMACAmYEmEkAH0BAAMACAmYEmEkAH0BAAAA.',
Ai='Ailee:BAAALgAECgYJDAAAAA==.Aios:BAAALgADCgcJCQAAAA==.Aiza:BAACLgAFFH8LAAIEAAMJeAQjbwC5AAAEAAMJeAQjbwC5AAAuAAQKfy0AAwQACQnqExc5AN8BAAQACQnqExc5AN8BAAUAAQkAAPQ3AB0AAAAA.',
Al='Alaber:BAAALgAECgUJBQAAAA==.Aldanil:BAAALgADCgMJAwAAAA==.',
An='Animalfriend:BAAALgAECgIJAgAAAA==.Anklesmasher:BAAALgAECgcJEwAAAA==.Anyah:BAAALgAECgQJCwAAAA==.',
Ap='Apolloo:BAAALgADCgMJAwAAAA==.',
Aq='Aquadora:BAAALgAECgEJAQAAAA==.',
Ar='Arfaz:BAABLgAECn8kAAMGAAcJARuWVgCgAQAGAAcJkhmWVgCgAQAHAAYJWAoqLwC6AAAAAA==.Armbrost:BAAALgAECgYJCgAAAA==.Artimås:BAAALgADCgcJCAAAAA==.Arwynne:BAAALgADCgMJAwAAAA==.Arçano:BAAALgAECgEJAQABLgAECgkJGQAIADkTAA==.',
As='Ascension:BAAALgADCgcJBgABLgAECgkJPgAEAJ8kAA==.Astrastar:BAABLgAECn8YAAMEAAYJsQJKywCdAAAEAAYJsQJKywCdAAACAAEJcgDDgAAOAAAAAA==.',
Av='Avarin:BAAALgADCgEJAQAAAA==.',
Ay='Aymont:BAAALgAECgQJBQAAAA==.',
Ba='Baerd:BAABLgAECn8aAAIJAAcJZhM0JQB5AQAJAAcJZhM0JQB5AQAAAA==.Baji:BAAALgAECgkJBwAAAA==.Barlz:BAAALgAECgEJAQAAAA==.',
Be='Beanpaste:BAAALgAECgcJAQABLgAFFAMJCgAGANwUAA==.Beanutbutter:BAAALgADCgIJAgABLgAFFAMJCgAGANwUAA==.Beaty:BAAALgAECgIJAgAAAA==.Bebby:BAAALgAECgYJEAAAAA==.Belonara:BAAALgADCgMJBwAAAA==.Belwolf:BAAALgAECgQJDwAAAA==.Bergstrom:BAABLgAECn80AAIKAAkJuhm2JABTAgAKAAkJuhm2JABTAgAAAA==.Bethanymarie:BAAALgAECgEJAQAAAA==.Betrayer:BAAALgADCgQJAwABLgAECgkJPgAEAJ8kAA==.',
Bi='Biancaneve:BAAALgAECgQJBAAAAA==.Bighero:BAACLgAFFH8KAAILAAMJ+AZTVQC7AAALAAMJ+AZTVQC7AAAuAAQKfxsAAgsACAlZEVlvAFYBAAsACAlZEVlvAFYBAAAA.Bigmike:BAAALgAECgEJAgAAAA==.',
Bl='Blakkjezus:BAAALgAECgQJBwAAAA==.Blitzbolts:BAAALgAECgEJAgAAAA==.Bludo:BAACLgAFFH8OAAMMAAUJfxV8GAAvAQAMAAUJHRV8GAAvAQANAAIJdBDVJACBAAAuAAQKfx4AAwwACQl6IWgZAIACAAwACAk5GWgZAIACAA0ABgl9HFMYADYBAAAA.',
Bo='Boe:BAABLgAECn8hAAIOAAgJ6whtEwBFAQAOAAgJ6whtEwBFAQAAAA==.Bomba:BAAALgAECgEJAQAAAA==.Bombacløt:BAABLgAECn8mAAMCAAgJ6w4aEAAXAQAEAAgJAA2JXgBxAQACAAcJbg4aEAAXAQAAAA==.Bowdirte:BAAALgAECgUJBwAAAA==.',
Br='Brastin:BAABLgAECn8yAAIPAAkJ+iAdAgD2AgAPAAkJ+iAdAgD2AgABLgAFFAQJDAAQAIQMAA==.Brenell:BAABLgAECn85AAIBAAkJsCFUDAABAwABAAkJsCFUDAABAwAAAA==.',
Bu='Bu:BAAALgAECgUJBQABLgAECgYJGAARAIQcAA==.Bubblehearth:BAAALgAECgYJBQABLgAECgkJJwALANEZAA==.Buffet:BAAALgAECgYJCQABLgAECgkJJwALANEZAA==.Buhlitz:BAAALgAECgEJAgAAAA==.',
By='Bynis:BAABLgAECn8fAAILAAkJfRTLPwCrAQALAAkJfRTLPwCrAQAAAA==.',
Ca='Cabëla:BAAALgADCgUJBQAAAA==.Cactusjack:BAAALgADCgUJBQAAAA==.Cadorex:BAAALgADCgEJAQAAAA==.Caffeinefree:BAAALgADCggJBwAAAA==.Calacolinda:BAAALgAECgQJBgAAAA==.Cavakworm:BAAALgADCgEJAQAAAA==.Caylin:BAAALgADCgUJBgAAAA==.Cayusedemon:BAAALgADCgEJAQAAAA==.Cayusemage:BAAALgADCgkJCQAAAA==.',
Ce='Ceridwyn:BAAALgAECgEJAQAAAA==.',
Ch='Chariscrushr:BAAALgAECgQJCAABLgAFFAcJGQASAF0YAA==.Chen:BAAALgADCgIJAgAAAA==.Choal:BAAALgAECgEJAQAAAA==.Chokaho:BAAALgAECgMJAwAAAA==.',
Ci='Cinnamongirl:BAAALgAECgcJEgAAAA==.',
Co='Corahin:BAABLgAECn8bAAIQAAYJGxASRAA5AQAQAAYJGxASRAA5AQAAAA==.Corious:BAAALgAECgQJCQAAAA==.Cosmos:BAAALgAECgYJDQAAAA==.Cougarhunter:BAAALgAECgkJEAAAAA==.',
Cr='Crokus:BAAALgADCggJCAAAAA==.',
Cu='Cuecumba:BAABLgAECn8uAAITAAkJICY6AABpAwATAAkJICY6AABpAwAAAA==.',
Da='Daemonerror:BAAALgAECgUJBQABLgAECggJMAAUAJUiAA==.Dalren:BAACLgAFFH8WAAMVAAUJ2R96FQBjAQAVAAQJ2R96FQBjAQAWAAIJuwNtCwBLAAAuAAQKfzsAAxUACQlIJYsEAAsDABUACQkLJYsEAAsDABYABgnyIEMMABcCAAAA.Dalryn:BAAALgAECgYJDQABLgAFFAUJFgAVANkfAA==.Dalvix:BAAALgADCgEJAQABLgAECgkJJgALAFogAA==.Damocles:BAABLgAECn8YAAIBAAYJlwy1rQANAQABAAYJlwy1rQANAQAAAA==.Dartagnan:BAACLgAFFH8IAAIXAAMJVhyqNwANAQAXAAMJVhyqNwANAQAuAAQKfyIAAxcACAmkHAdgAFsBABcABgnoHQdgAFsBABgABgn3FAkXANsAAAAA.Darthmaul:BAABLgAECn8wAAIDAAkJyhGEGQDWAQADAAkJyhGEGQDWAQAAAA==.',
De='Deay:BAAALgADCgQJAQAAAA==.Delexa:BAAALgADCgkJMAAAAA==.Dendiian:BAABLgAECn8UAAIZAAYJXxVVHQAjAQAZAAYJXxVVHQAjAQAAAA==.',
Di='Didipullthat:BAAALgADCgYJFwABLgAECgkJJwALANEZAA==.Diem:BAABLgAECn8dAAIXAAgJyw1rQQCqAQAXAAgJyw1rQQCqAQAAAA==.Dirtydotss:BAABLgAECn8VAAMFAAcJFwfXEgD/AAAFAAYJYQbXEgD/AAAEAAYJ5wTKtQDEAAAAAA==.Divigitives:BAAALgAECgQJBAAAAA==.',
Do='Docrivan:BAAALgAECgYJCwAAAA==.Docsassist:BAAALgAECgMJAwABLgAECgYJCwAaAAAAAA==.Doregit:BAABLgAECn8oAAIMAAgJRRzuEwAvAgAMAAgJRRzuEwAvAgAAAA==.Dowedoes:BAABLgAECn89AAIKAAkJghe0KQA7AgAKAAkJghe0KQA7AgAAAA==.',
Dr='Drachula:BAABLgAECn8YAAIbAAYJTRYZPwCDAQAbAAYJTRYZPwCDAQAAAA==.Dracultra:BAAALgAECgUJBwABLgAECgkJIAAcAF0fAA==.Drakcheese:BAAALgADCgUJBQAAAA==.Dreolan:BAABLgAECn89AAIdAAkJGBGALADXAQAdAAkJGBGALADXAQAAAA==.Drynnai:BAAALgADCgEJAgAAAA==.',
Dy='Dyala:BAACLgAFFH8JAAMdAAMJjg8MMwDHAAAdAAMJjg8MMwDHAAADAAMJ8AI/LACdAAAuAAQKfx4AAx0ACAlLErdfADMBAB0ACAlLErdfADMBAAMAAgk0CjVoAFIAAAAA.',
['Dö']='Dönövan:BAABLgAECn8kAAIKAAgJORClYgCNAQAKAAgJORClYgCNAQAAAA==.',
El='Elastwo:BAAALgADCgcJBwAAAA==.Eloise:BAAALgAECgcJEQAAAA==.Elvenbane:BAABLgAECn8mAAIeAAkJrRO9FgDxAQAeAAkJrRO9FgDxAQAAAA==.',
Em='Emily:BAAALgAECgYJDAAAAA==.Emry:BAAALgADCgYJBgABLgAECgcJHQAUADkPAA==.',
En='Enable:BAEBLgAECn8gAAIfAAkJVRwECACYAgAfAAkJVRwECACYAgABLgAECggJLwAPAE8iAA==.',
Ep='Epictool:BAAALgAECggJCwAAAA==.',
Et='Ethereal:BAAALgAECgEJAQAAAA==.',
Fa='Fabel:BAEBLgAECn8vAAIPAAgJTyJnBQB0AgAPAAgJTyJnBQB0AgAAAA==.Falahad:BAAALgAECgEJAQABLgAFFAMJCgADALINAA==.Faltree:BAACLgAFFH8KAAMDAAMJsg1vJgDLAAADAAMJsg1vJgDLAAAdAAIJ6RPEQwCHAAAuAAQKfx8ABB0ACAmwGP5TAFcBAB0ABglPGP5TAFcBAAMACAkOF6kqAFEBACAAAQnfAUo6AB8AAAAA.Fathershale:BAAALgADCgcJEQAAAA==.',
Fi='Firelord:BAAALgADCgEJAQAAAA==.',
Fo='Foulcor:BAABLgAECn8cAAMcAAgJlB4QEwBWAgAcAAgJlB4QEwBWAgAKAAYJ5xCGpgANAQAAAA==.',
Fr='Freakadeek:BAABLgAECn8VAAQhAAkJaw00GADMAAAGAAUJ0AjftQDlAAAhAAMJnhc0GADMAAAHAAYJgwSUQQBcAAAAAA==.Freâkadeek:BAAALgAECgIJAwABLgAECgkJFQAhAGsNAA==.Freäk:BAAALgADCgMJAwABLgAECgkJFQAhAGsNAA==.Frieren:BAABLgAECn80AAIBAAgJ/hOmWwCxAQABAAgJ/hOmWwCxAQAAAA==.Frink:BAAALgAECgEJAQABLgAECgkJPQAiAOEkAA==.Frostlord:BAAALgAECgIJAgAAAA==.',
Fu='Fundetected:BAAALgAECgUJCAABLgAECgkJJwALANEZAA==.Furyofthenug:BAAALgADCgcJCgAAAA==.',
Ga='Gabbyo:BAABLgAECn8hAAIdAAcJkQeHZADpAAAdAAcJkQeHZADpAAAAAA==.Galadorn:BAABLgAECn8mAAILAAkJWiD9CwDOAgALAAkJWiD9CwDOAgAAAA==.Gallgamesh:BAAALgADCgIJAgAAAA==.Garfall:BAAALgAECgcJDgAAAA==.Garga:BAAALgADCgMJBAAAAA==.',
Ge='Geirvaldr:BAAALgAECgYJBgAAAA==.Gerdash:BAAALgAECgMJBAAAAA==.Gerred:BAABLgAECn8WAAMNAAcJehjOEgCoAQANAAcJyBfOEgCoAQAMAAQJRRQ8VgDNAAAAAA==.',
Gh='Ghallow:BAABLgAECn8WAAIOAAYJihbQEABuAQAOAAYJihbQEABuAQAAAA==.Ghosty:BAACLgAFFH8JAAIjAAQJOxULFwAzAQAjAAQJOxULFwAzAQAuAAQKfyoAAiMABwlQIMUPAA8CACMABwlQIMUPAA8CAAAA.',
Gi='Gimp:BAAALgAECgEJAgAAAA==.',
Gl='Gladur:BAAALgAFFAEJAQABLgAFFAYJGwABAEIcAA==.',
Go='Goldenflame:BAAALgAECgUJBwAAAA==.Goldenlily:BAAALgAECgYJEgAAAA==.Goldenmunc:BAABLgAECn8tAAIBAAkJNxfvKwBOAgABAAkJNxfvKwBOAgAAAA==.Goldenone:BAAALgAECgQJBQAAAA==.Goldenpants:BAABLgAECn8nAAIMAAkJjxNSGwDxAQAMAAkJjxNSGwDxAQAAAA==.',
Gr='Grievous:BAABLgAECn89AAITAAkJOyVcAABYAwATAAkJOyVcAABYAwAAAA==.',
['Gû']='Gûrth:BAAALgADCgcJBwAAAA==.',
Ha='Hailmary:BAABLgAECn8oAAIJAAkJEiXRAAC5AwAJAAkJEiXRAAC5AwAAAA==.Harusen:BAABLgAECn8cAAIkAAkJFR+1AQCqAgAkAAkJFR+1AQCqAgAAAA==.',
Hi='Hildalsind:BAAALgADCgkJCQABLgAFFAMJCQABAIMdAA==.',
Ho='Homestar:BAAALgADCgEJAQAAAA==.Hooll:BAAALgAECgIJAgAAAA==.Hornreaper:BAABLgAECn8bAAIVAAYJ5hfvJACVAQAVAAYJ5hfvJACVAQAAAA==.Hotshot:BAAALgAECgMJAwAAAA==.',
Hu='Hubbabubbajr:BAAALgAECgEJAQABLgAECgkJMwAdAIIbAA==.Hubert:BAAALgADCgEJAQAAAA==.Hurin:BAAALgAECgcJDgAAAA==.Huur:BAAALgAECgEJAQABLgAECgEJAQAaAAAAAA==.',
Hy='Hyetta:BAAALgAECgQJBgABLgAECgkJHAAkABUfAA==.Hyir:BAAALgADCgYJBwABLgAFFAMJDQASAKkdAA==.',
Il='Illiya:BAAALgAECgQJDwAAAA==.',
Ir='Irôn:BAAALgAECgEJAQAAAA==.',
Iu='Iutara:BAAALgAECgYJBgAAAA==.',
Ja='Jaalein:BAAALgADCgcJDgAAAA==.Jayonor:BAABLgAECn80AAQQAAkJthW9FAAbAgAQAAkJthW9FAAbAgAOAAYJ9we4GgAeAQAbAAcJ5AbQXwAJAQAAAA==.',
Je='Jek:BAAALgAECgUJBQAAAA==.',
Jo='Joryu:BAAALgADCgIJAwAAAA==.',
Ju='Juicycucci:BAAALgAECgcJEQABLgAECgkJJwALANEZAA==.',
Ka='Kaevrielle:BAEBLgAECn8eAAMTAAkJjhvHBQAdAgATAAkJjhvHBQAdAgAlAAEJVgplYQAnAAAAAA==.Kaison:BAAALgAECgkJEAABLgAECgkJHwALAH0UAA==.Kaladîn:BAAALgAECgMJAwABLgAFFAYJGwABAEIcAA==.Kalii:BAAALgADCgQJBAAAAA==.Kamel:BAAALgADCgYJBgAAAA==.Karwin:BAABLgAECn8ZAAIBAAcJhhQCeABuAQABAAcJhhQCeABuAQAAAA==.Katakuri:BAAALgAECgEJAgAAAA==.',
Ke='Keeper:BAAALgAECgUJBwABLgAECgkJQwAKAL4kAA==.Keeperodark:BAAALgAECggJEAABLgAECgkJQwAKAL4kAA==.Keeperolight:BAABLgAECn9DAAMKAAkJviQLBQA7AwAKAAkJviQLBQA7AwAcAAEJgRgUkABAAAAAAA==.Kemanorel:BAAALgADCgcJDgABLgAECgkJJgAeAK0TAA==.',
Ki='Kianth:BAAALgADCgkJEgAAAA==.Killkat:BAABLgAECn8uAAIBAAkJgxjeKgBTAgABAAkJgxjeKgBTAgAAAA==.',
Ko='Kodera:BAABLgAECn8YAAMRAAYJhBwaDQDeAQARAAYJhBwaDQDeAQAWAAQJNxv5DAAkAQAAAA==.Koojo:BAAALgAECgcJCAAAAA==.Kovae:BAAALgADCgEJAQAAAA==.',
Kr='Kraken:BAAALgADCgUJBQAAAA==.',
Ky='Kyaritin:BAAALgAECgMJAwABLgAECgYJCgAaAAAAAA==.Kyokei:BAAALgAECgEJAQAAAA==.',
La='Laiho:BAAALgADCgUJCAAAAA==.Lans:BAAALgAFFAEJAgAAAA==.Larew:BAABLgAECn8gAAIKAAgJiBe4RgDVAQAKAAgJiBe4RgDVAQAAAA==.Lazytemplar:BAAALgADCgMJAwABLgAECgUJDgAaAAAAAA==.',
Le='Lealla:BAABLgAECn89AAIDAAkJlCKyAwARAwADAAkJlCKyAwARAwAAAA==.Leodin:BAAALgAECgEJAgAAAA==.Leorus:BAAALgAECgIJAgAAAA==.Lethhunt:BAACLgAFFH8QAAMYAAUJfxCVEAASAQAYAAUJpQ2VEAASAQAXAAIJWw4MGgCeAAAuAAQKfy4AAxgACQncHgAFADwCABgACQlgHgAFADwCABcAAgk+JFKHANIAAAAA.',
Li='Lilmistfox:BAAALgAECgUJBwABLgAFFAQJDgAbAPUkAA==.Lioh:BAAALgAECgQJBAAAAA==.Lizardgang:BAAALgAECgYJEQAAAA==.',
Lo='Loganshu:BAAALgAECgIJAgAAAA==.Lokan:BAACLgAFFH8KAAMiAAMJjhjRFAACAQAiAAMJjhjRFAACAQAXAAEJwghpewBFAAAuAAQKfycAAiIACAmcGzMPACACACIACAmcGzMPACACAAAA.Lots:BAACLgAFFH8KAAIEAAMJhhtZTQAKAQAEAAMJhhtZTQAKAQAuAAQKfyQAAwQACAntIIgvAE8CAAQABwn1IIgvAE8CAAIABAngHkcsAA0BAAAA.',
Lu='Ludacast:BAAALgADCgIJAgAAAA==.Ludafists:BAAALgADCgcJDAAAAA==.Ludakris:BAABLgAECn8dAAIPAAkJfxi3CAAcAgAPAAkJfxi3CAAcAgAAAA==.Lumanoth:BAAALgAECgYJBgAAAA==.',
Ly='Lyna:BAABLgAECn8gAAIbAAkJpROkNACzAQAbAAkJpROkNACzAQAAAA==.Lynaya:BAAALgADCgIJAgAAAA==.',
['Lí']='Líonheart:BAABLgAECn8UAAMcAAYJ+BlqPgAnAQAcAAYJ+BlqPgAnAQAKAAEJQwSrVQEoAAAAAA==.',
['Lî']='Lîghtless:BAACLgAFFH8PAAIBAAYJBhpxJACUAQABAAYJBhpxJACUAQAuAAQKfxcAAgEACAmfJUchAO4CAAEACAmfJUchAO4CAAAA.',
['Lú']='Lúckally:BAAALgADCgQJBAABLgAECgYJCgAaAAAAAA==.Lúckÿ:BAAALgAECgYJCgAAAA==.',
Ma='Mahina:BAAALgAECgIJAgAAAA==.Marcille:BAABLgAECn8nAAIBAAgJ2RNHYwCeAQABAAgJ2RNHYwCeAQAAAA==.Masyledian:BAAALgAECgIJAgAAAA==.Mathor:BAAALgAECgEJAgAAAA==.Mavrbg:BAAALgAECgQJBQAAAA==.Mayhaps:BAABLgAECn9EAAMXAAkJFRv3GwBVAgAXAAkJFRv3GwBVAgAYAAEJZACpmgAYAAAAAA==.',
Mc='Mcbain:BAABLgAECn89AAIiAAkJ4SQNAQBOAwAiAAkJ4SQNAQBOAwAAAA==.',
Me='Melrine:BAAALgADCgMJAwAAAA==.Mentaltitty:BAABLgAECn8fAAIBAAgJyxOGVADEAQABAAgJyxOGVADEAQAAAA==.',
Mi='Minerwor:BAAALgAECgQJBQAAAA==.Mirrayla:BAAALgADCgYJBgAAAA==.Misty:BAAALgADCgYJBgAAAA==.',
Mm='Mmisty:BAABLgAECn85AAIDAAkJXRVpEQApAgADAAkJXRVpEQApAgAAAA==.',
Mo='Moarthretplz:BAAALgAECgUJCQABLgAFFAQJDgAbAPUkAA==.Mohji:BAAALgAFFAEJAQABLgAFFAcJGgAmAOwUAA==.Momometaru:BAABLgAECn8jAAQEAAgJNRehSQCpAQAEAAgJwxOhSQCpAQACAAUJNhRyJgAsAQAFAAMJzxroHQCRAAAAAA==.Monsterbee:BAABLgAECn86AAIEAAkJkhGSMgD4AQAEAAkJkhGSMgD4AQAAAA==.',
Mu='Mustypizza:BAABLgAECn8uAAICAAkJihhMAwA/AgACAAkJihhMAwA/AgAAAA==.',
Mx='Mxicancowboy:BAAALgADCgEJAgAAAA==.',
My='Mystery:BAABLgAECn89AAMRAAkJNiA2AgA5AwARAAkJNiA2AgA5AwAWAAUJXhFlDQAcAQAAAA==.',
['Mê']='Mêøwzêr:BAAALgAECggJEwAAAA==.',
['Mÿ']='Mÿst:BAAALgAECgMJBAAAAA==.',
Na='Narashi:BAAALgAECgQJBgAAAA==.Naril:BAAALgADCgUJBQAAAA==.Nats:BAABLgAECn8kAAIbAAgJSxGwOACfAQAbAAgJSxGwOACfAQAAAA==.',
Ne='Neameny:BAABLgAECn89AAIXAAkJGBNlLQD+AQAXAAkJGBNlLQD+AQAAAA==.',
Ni='Nianji:BAAALgADCgYJDgAAAA==.Nightstar:BAAALgADCgMJAwAAAA==.Nightworld:BAAALgADCgcJDgAAAA==.',
No='Noctum:BAAALgAECgUJBQAAAA==.Nordicpally:BAAALgADCgQJBAAAAA==.Notgim:BAAALgADCggJCAAAAA==.',
Nu='Nualrossan:BAAALgADCgMJAgAAAA==.Nubrac:BAAALgAECggJEgAAAA==.',
Ny='Nylux:BAAALgAECgYJDwAAAA==.',
Ob='Oblivion:BAABLgAECn8+AAMEAAkJnySVBAA3AwAEAAkJnySVBAA3AwACAAEJAABRXQBXAAAAAA==.',
Oo='Oostren:BAAALgAECgEJAgAAAA==.',
Or='Orsyp:BAAALgADCgkJGgAAAA==.',
Pa='Palockie:BAAALgADCgEJAQAAAA==.Pandas:BAABLgAECn8hAAIQAAkJAhGFHwC9AQAQAAkJAhGFHwC9AQAAAA==.Partyrocker:BAABLgAECn8XAAIiAAcJag7wJABXAQAiAAcJag7wJABXAQABLgAECgkJFQAhAGsNAA==.',
Pi='Pixae:BAACLgAFFH8KAAIRAAMJ2wY0HACpAAARAAMJ2wY0HACpAAAuAAQKfx4AAhEABwlgCicaABQBABEABwlgCicaABQBAAAA.Pixiechaos:BAAALgAECgMJBQAAAA==.',
Po='Poliahu:BAAALgAECgQJCQAAAA==.Porthoss:BAAALgADCggJDwAAAA==.Powerplant:BAACLgAFFH8VAAIXAAYJaiHPCQCuAQAXAAYJaiHPCQCuAQAuAAQKfyYAAhcACQkgJCgIAA4DABcACQkgJCgIAA4DAAAA.Poyoram:BAAALgADCgEJAQAAAA==.',
Py='Pyralys:BAABLgAECn85AAMJAAkJGBFSFgD6AQAJAAkJGBFSFgD6AQAeAAMJqQI8cQAzAAAAAA==.',
Ra='Ragemonk:BAAALgAECgUJDgAAAA==.Ragetality:BAAALgADCgEJAQABLgAECgUJDgAaAAAAAA==.Rakthera:BAAALgADCgcJBwAAAA==.Ramaria:BAAALgADCgkJCQABLgAECgkJJgALAFogAA==.Raserei:BAAALgAECgYJBgAAAA==.Rasputain:BAAALgADCgYJCgAAAA==.Rasputein:BAAALgADCgcJBwAAAA==.Rattelyr:BAAALgAECgYJCgAAAA==.Ravara:BAAALgADCgYJBgABLgAECgkJJgALAFogAA==.Rayné:BAAALgAECgQJBwAAAA==.Razgaurd:BAAALgAECgMJAwAAAA==.',
Re='Regice:BAAALgAECgcJBwABLgAECgkJNgAHAN0gAA==.Regicee:BAABLgAECn82AAMHAAkJ3SBDBADUAgAHAAkJ3SBDBADUAgAGAAQJtwim8ACNAAAAAA==.Retam:BAAALgAECgEJAQAAAA==.Revakos:BAAALgADCgMJAwAAAA==.',
Rh='Rhysandra:BAAALgAECgQJCQAAAA==.',
Ri='Ribble:BAAALgADCgMJAwAAAA==.Riffraff:BAAALgAECgcJBAAAAA==.Ripcord:BAAALgAECgUJCAAAAA==.Ripem:BAAALgADCgYJBgAAAA==.Ripperoni:BAAALgAECgEJAgAAAA==.Rizek:BAAALgAECgUJBgABLgAECgcJHQAUADkPAA==.Rizzx:BAAALgAECgEJAQAAAA==.',
Ro='Rockdyou:BAABLgAECn8jAAIGAAgJRB4DNgAGAgAGAAgJRB4DNgAGAgAAAA==.Roglef:BAAALgAECgQJCQAAAA==.Rotlobster:BAAALgAECgcJEAAAAA==.Roxxy:BAAALgAECgQJBAAAAA==.',
Ru='Rundvelt:BAACLgAFFH8KAAIPAAMJeA1oCgCiAAAPAAMJeA1oCgCiAAAuAAQKfx8AAg8ACAmoEOIWAD8BAA8ACAmoEOIWAD8BAAAA.',
Sa='Sage:BAAALgADCgcJCAAAAA==.Sandwich:BAAALgAECgcJCAAAAA==.Saphíra:BAAALgAFFAEJAQABLgAFFAYJGwABAEIcAA==.Sapkick:BAAALgAECgQJBwAAAA==.',
Se='Serdragon:BAAALgADCgQJBAAAAA==.Servoid:BAAALgAECgUJCQAAAA==.',
Sh='Shando:BAAALgAECgEJAQAAAA==.Shiftstyle:BAEALgAECgEJAQAAAA==.Shtanky:BAACLgAFFH8KAAIIAAMJaBFJFgDGAAAIAAMJaBFJFgDGAAAuAAQKfx8AAggACAnFC0ocAC0BAAgACAnFC0ocAC0BAAAA.',
Si='Silentsocks:BAAALgAECgUJDAAAAA==.Sixsixsix:BAAALgAECgcJCgABLgAFFAIJCAAGANMeAA==.',
Sk='Skoogz:BAAALgAECgkJDQAAAA==.',
So='Soggyy:BAAALgADCgYJCwAAAA==.Solar:BAABLgAECn8VAAQSAAcJyRkxLwBtAQASAAYJCxYxLwBtAQAfAAYJrhzoOABmAQAUAAEJUwKEngAbAAAAAA==.Soulfulgingr:BAAALgAECgQJBAAAAA==.',
St='Starlagosa:BAAALgADCgYJCQAAAA==.Sturm:BAAALgAECgMJAwAAAA==.Styx:BAAALgAECgMJAwAAAA==.',
Su='Sunbake:BAAALgAECgUJBwAAAA==.',
Sw='Sweetbbyraze:BAACLgAFFH8RAAMWAAQJrxiOBgC0AAAVAAQJ7wzxEgDoAAAWAAMJmRaOBgC0AAAuAAQKfyYAAxYACAkpIVIGAJACABYABwm8IVIGAJACABUAAwnyHFdcAJwAAAAA.',
Sy='Sylaena:BAABLgAECn8bAAIYAAgJLQbsFADyAAAYAAgJLQbsFADyAAAAAA==.Sylvrstorm:BAAALgAECgQJCAAAAA==.',
['Së']='Sërënity:BAAALgAECgQJCwAAAA==.',
['Sí']='Sín:BAAALgAECgcJDAABLgAFFAIJCAAGANMeAA==.',
Ta='Talipally:BAABLgAECn8bAAIKAAkJlw9PYwCMAQAKAAkJlw9PYwCMAQAAAA==.Talishammy:BAAALgAECgMJAwABLgAECgkJGwAKAJcPAA==.Taliwhacker:BAAALgADCgYJEQABLgAECgkJGwAKAJcPAA==.Talonleafgrd:BAAALgAECgEJAQAAAA==.Tanaka:BAABLgAECn8gAAIGAAgJgBN5SgDDAQAGAAgJgBN5SgDDAQAAAA==.Tanisong:BAAALgAECgQJBwAAAA==.Tassadar:BAAALgAECgQJBwAAAA==.',
Te='Tepeyollotl:BAAALgADCgEJAQAAAA==.Terayus:BAAALgADCgcJDAAAAA==.Teyliah:BAAALgADCgMJAwAAAA==.',
Tf='Tf:BAAALgAECgYJBgABLgAFFAIJCAAGANMeAA==.',
Th='Thekingpunch:BAABLgAECn8wAAIUAAgJlSLEBgALAwAUAAgJlSLEBgALAwAAAA==.Thenle:BAAALgADCggJDgAAAA==.Thunderblitz:BAABLgAECn8dAAIcAAgJcwfaOgA4AQAcAAgJcwfaOgA4AQAAAA==.Thurmus:BAAALgADCgkJMAAAAA==.',
Ti='Tillwar:BAABLgAECn87AAIMAAkJKh1PDACDAgAMAAkJKh1PDACDAgAAAA==.Tinymonk:BAAALgADCgMJAwAAAA==.',
To='Tofu:BAABLgAECn8tAAIGAAkJohr2GACRAgAGAAkJohr2GACRAgAAAA==.Tokanya:BAAALgAECgEJAQAAAA==.Tortillachip:BAAALgAECgEJAgAAAA==.Toxidot:BAAALgAECgEJAQAAAA==.',
Tr='Treibh:BAABLgAECn8pAAIdAAkJXxe6FQB6AgAdAAkJXxe6FQB6AgAAAA==.Trelephant:BAAALgAECgMJBQAAAA==.Trulydps:BAABLgAECn8hAAIXAAgJpQ7kTwCHAQAXAAgJpQ7kTwCHAQAAAA==.Trulyog:BAAALgAECgQJBAAAAA==.',
Tu='Tubbsmcgee:BAACLgAFFH8XAAIbAAUJQyNNBgASAgAbAAUJQyNNBgASAgAuAAQKfyUAAhsACQkrJLgHAPkCABsACQkrJLgHAPkCAAAA.Tukkit:BAAALgAECgMJBgAAAA==.',
Tw='Twistedshot:BAAALgADCggJCAAAAA==.Twizzler:BAABLgAECn88AAIBAAkJIwWPggBYAQABAAkJIwWPggBYAQAAAA==.',
Ty='Tyraniik:BAAALgADCgYJCAAAAA==.',
['Të']='Tërris:BAABLgAECn8aAAIHAAgJ9xBaGwBSAQAHAAgJ9xBaGwBSAQAAAA==.',
['Tî']='Tîlldeath:BAAALgAECgUJBwAAAA==.',
Uj='Uji:BAAALgADCgEJAQAAAA==.',
Ur='Urowndad:BAAALgAECgUJBQABLgAECggJFgAKAL0TAA==.Urownmother:BAAALgADCgUJBQABLgAECggJFgAKAL0TAA==.',
Va='Vaellian:BAAALgAECgYJDAAAAA==.Vallez:BAECLgAFFH8NAAMcAAMJdB/jGwATAQAcAAMJdB/jGwATAQAKAAEJawLNlgA9AAAuAAQKfyUAAxwACAneHjIWAF8CABwACAneHjIWAF8CAAoAAgnbCa9FATIAAAAA.Vanillaghost:BAAALgADCgIJAQAAAA==.Varnusshadow:BAAALgAECgEJAQAAAA==.',
Ve='Vearik:BAAALgADCgcJCwAAAA==.Velladoree:BAABLgAECn8VAAIUAAgJBAfYSgDsAAAUAAgJBAfYSgDsAAAAAA==.Vendaryn:BAAALgADCggJCAAAAA==.Vexahlia:BAAALgADCgMJAwAAAA==.',
Vg='Vgurlpally:BAAALgADCgYJBgAAAA==.',
Vy='Vynlorlan:BAAALgADCgMJAwABLgAECgMJBAAaAAAAAA==.',
Wa='Waveygravee:BAAALgAECgIJAwAAAA==.Wavygraivy:BAABLgAECn8UAAIbAAYJ2BVFPwCCAQAbAAYJ2BVFPwCCAQAAAA==.',
We='Wedragon:BAAALgAECgQJDgAAAA==.',
Wh='Wheelchair:BAACLgAFFH8KAAIGAAQJOxuVTAAzAQAGAAQJOxuVTAAzAQAuAAQKfxwAAgYACAkSJF0SAA4DAAYACAkSJF0SAA4DAAAA.',
Wo='Woofwoof:BAAALgAECgMJAwAAAA==.',
Wu='Wullemage:BAAALgADCgcJEwABLgAFFAYJGgAjAGkcAA==.',
['Wå']='Wåsp:BAABLgAECn8UAAILAAYJoga8nwC6AAALAAYJoga8nwC6AAAAAA==.',
Xb='Xb:BAAALgAECgcJBQAAAA==.',
Xh='Xhexana:BAABLgAECn8wAAIbAAkJdBVZHgAwAgAbAAkJdBVZHgAwAgABLgAECgkJPQAXABgTAA==.',
Xr='Xrael:BAAALgAECgEJAQABLgAFFAMJDAASANQhAA==.Xrayl:BAACLgAFFH8MAAMSAAMJ1CFYDgAqAQASAAMJ1CFYDgAqAQAfAAEJEA5XTABDAAAuAAQKfyAAAxIACAlZH7kUAO0BABIABwn7H7kUAO0BAB8AAQmOG/N9AE8AAAAA.',
Xz='Xzerocool:BAABLgAECn8WAAQKAAgJvROgbQB1AQAKAAgJvROgbQB1AQAPAAIJshM+MgBvAAAcAAEJmQMkjAAiAAAAAA==.',
Ya='Yannii:BAAALgADCgcJDgAAAA==.',
Ye='Yenko:BAAALgADCgIJAgAAAA==.',
Yo='Yolo:BAAALgADCgcJCwAAAA==.Yoshikazu:BAAALgAECgYJBgAAAA==.Yoyoboy:BAAALgADCgEJAQAAAA==.',
Za='Zaarah:BAAALgAECgMJAwAAAA==.',
Ze='Zellek:BAAALgADCgEJAQAAAA==.Zendezoth:BAABLgAECn8dAAIWAAgJuxU+BgDJAQAWAAgJuxU+BgDJAQAAAA==.Zephik:BAAALgADCgEJAQAAAA==.Zerofrost:BAABLgAECn8iAAIBAAgJiRfhTgDVAQABAAgJiRfhTgDVAQAAAA==.Zevra:BAAALgADCgMJAwAAAA==.',
Zh='Zhiva:BAABLgAECn8kAAIDAAYJewt8QwDQAAADAAYJewt8QwDQAAAAAA==.',
Zu='Zul:BAACLgAFFH8SAAIjAAMJXiPDGAAlAQAjAAMJXiPDGAAlAQAuAAQKfy8AAyMACAkEIwsMANcCACMACAkEIwsMANcCACcAAQnLAkMiACQAAAAA.',
Zy='Zykoz:BAABLgAECn8uAAIjAAkJpCH0AgAIAwAjAAkJpCH0AgAIAwAAAA==.',
['Ða']='Ðamned:BAABLgAECn8YAAIQAAYJ8hvELgCnAQAQAAYJ8hvELgCnAQABLgAFFAIJCAAGANMeAA==.',
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
