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

local lookup = {'Mage-Frost','Warlock-Destruction','Druid-Balance','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Priest-Holy','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Shaman-Enhancement','Paladin-Protection','Shaman-Elemental','Evoker-Preservation','DemonHunter-Vengeance','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Unknown-Unknown','Shaman-Restoration','Paladin-Holy','Druid-Restoration','Priest-Shadow','Monk-Brewmaster','Druid-Feral','DeathKnight-Frost','Hunter-Survival','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Havoc','Priest-Discipline','Mage-Arcane','Mage-Fire','Rogue-Assassination',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=46,date='2026-06-21',data={Ab='Abomination:BAAALgADCgMJAwAAAA==.',
Ad='Adune:BAAALgAECgQJBQAAAA==.',
Ae='Aeidail:BAACLgAFFH8dAAIBAAcJTRhIJwDaAQABAAcJTRhIJwDaAQAuAAQKfyoAAgEACAnUI0McAAUDAAEACAnUI0McAAUDAAAA.Aelaria:BAAALgADCgMJAwAAAA==.Aeviria:BAABLgAECn8oAAICAAgJtRVxCADGAQACAAgJtRVxCADGAQAAAA==.',
Ag='Agraceful:BAACLgAFFH8MAAIDAAMJEAfgNwCeAAADAAMJEAfgNwCeAAAuAAQKfx8AAgMACQm8EjUfAM4BAAMACQm8EjUfAM4BAAAA.',
Ai='Ailee:BAAALgAECgYJDAAAAA==.Aios:BAAALgAECgIJAgAAAA==.Aiza:BAACLgAFFH8MAAIEAAMJSQX7igCwAAAEAAMJSQX7igCwAAAuAAQKfzgAAwQACQmXGb8dAHICAAQACQmXGb8dAHICAAUAAQkAAA1JAAAAAAAA.',
Al='Alaber:BAAALgAECgUJCAAAAA==.Aldanil:BAAALgADCgMJAwAAAA==.Allarria:BAAALgADCgYJBwABLgAECgkJJgAGAFogAA==.',
Am='Ampersand:BAAALgAECgMJBwAAAA==.',
An='Animalfriend:BAAALgAECgIJBAAAAA==.Anklesmasher:BAABLgAECn8UAAIHAAcJ/A4ePAAQAQAHAAcJ/A4ePAAQAQAAAA==.Antonidus:BAAALgAECgUJCwAAAA==.Anyah:BAABLgAECn8dAAIDAAgJqgQwBAB3AAADAAgJqgQwBAB3AAAAAA==.',
Ap='Apolloo:BAAALgADCgMJAwAAAA==.',
Aq='Aquadora:BAAALgAECgEJAQAAAA==.',
Ar='Arfaz:BAABLgAECn80AAMIAAgJNhuqQAABAgAIAAgJGBqqQAABAgAJAAYJWAoUOQCvAAAAAA==.Armbrost:BAAALgAECgYJCgAAAA==.Artimås:BAAALgADCgcJCAAAAA==.Arwynne:BAAALgADCgMJAwAAAA==.Arçano:BAAALgAECgEJAQABLgAECgkJGQAKADkTAA==.',
As='Ascension:BAAALgADCgcJBgABLgAFFAMJBQAEAPUcAA==.Astrastar:BAABLgAECn8bAAMEAAYJ0wKj4wCVAAAEAAYJ0wKj4wCVAAACAAEJcgDDgAAOAAAAAA==.',
Au='Auralyn:BAAALgADCgMJBQAAAA==.Aurius:BAAALgAECgcJAgAAAA==.',
Av='Avarin:BAAALgADCgEJAQAAAA==.',
Ay='Aymont:BAAALgAECgQJBQAAAA==.',
Ba='Baerd:BAABLgAECn8aAAILAAcJZhPnKwBqAQALAAcJZhPnKwBqAQAAAA==.Baji:BAAALgAECgkJBwAAAA==.Barlz:BAAALgAECgEJAQAAAA==.',
Be='Beanpaste:BAAALgAECgcJAQABLgAFFAMJEAAIAHcZAA==.Beanutbutter:BAAALgADCgIJAgABLgAFFAMJEAAIAHcZAA==.Beaty:BAAALgAECgIJAgAAAA==.Bebby:BAABLgAECn8cAAMJAAcJYgJbRwBwAAAJAAYJPwJbRwBwAAAIAAIJaQJReAEwAAAAAA==.Belonara:BAAALgAECgEJAQAAAA==.Belwolf:BAABLgAECn8UAAIIAAUJwApi6ADKAAAIAAUJwApi6ADKAAAAAA==.Bergstrom:BAABLgAECn80AAIMAAkJuhm+MAA+AgAMAAkJuhm+MAA+AgAAAA==.Bethanymarie:BAAALgAECgEJAQAAAA==.Betrayer:BAAALgADCgQJAwABLgAFFAMJBQAEAPUcAA==.',
Bi='Biancaneve:BAACLgAFFH8FAAILAAMJsg8hJACaAAALAAMJsg8hJACaAAAuAAQKfxsAAgsABwmcGNMbAOkBAAsABwmcGNMbAOkBAAAA.Bighero:BAACLgAFFH8QAAIGAAMJSQsHagC4AAAGAAMJSQsHagC4AAAuAAQKfyAAAgYACQk9EVlvAFYBAAYACQk9EVlvAFYBAAAA.Bigmike:BAAALgAECgEJAgAAAA==.',
Bl='Blakkjezus:BAAALgAECgcJCwAAAA==.Blessednugie:BAAALgAECgcJDwAAAA==.Blitzbolts:BAAALgAECgEJAgAAAA==.Bludo:BAACLgAFFH8RAAMNAAcJKxCEHQADAQAOAAUJHRX5IwAkAQANAAQJ+wqEHQADAQAuAAQKfx4AAw4ACQl6IWgZAIACAA4ACAk5GWgZAIACAA0ABgl9HFMYADYBAAAA.',
Bo='Boe:BAABLgAECn8oAAIPAAkJNAr5EwB6AQAPAAkJNAr5EwB6AQAAAA==.Bomba:BAAALgAECgUJCQAAAA==.Bombacløt:BAABLgAECn8yAAMEAAkJphDuRQDJAQAEAAkJKBDuRQDJAQACAAcJbg6pFAAIAQAAAA==.Bowdirte:BAAALgAECgUJBwAAAA==.',
Br='Brastin:BAABLgAECn86AAIQAAkJkyJHAgASAwAQAAkJkyJHAgASAwABLgAFFAYJEwARAAoMAA==.Brenell:BAACLgAFFH8IAAIBAAMJgRLfiwDBAAABAAMJgRLfiwDBAAAuAAQKfzsAAgEACQmwIX8RAPECAAEACQmwIX8RAPECAAAA.',
Bu='Bu:BAAALgAECgYJDQABLgAECgYJHQASALgdAA==.Bubblehearth:BAAALgAECgYJCQABLgAFFAMJBQAGAPMKAA==.Buffet:BAABLgAECn8aAAIBAAYJ0BHmrQAlAQABAAYJ0BHmrQAlAQABLgAFFAMJBQAGAPMKAA==.Buhlitz:BAAALgAECgEJAgAAAA==.Butterbean:BAAALgADCgMJBQAAAA==.',
By='Bynis:BAABLgAECn8gAAIGAAkJDRVHSACuAQAGAAkJDRVHSACuAQAAAA==.',
Ca='Cabëla:BAAALgADCgUJBQAAAA==.Cactusjack:BAAALgADCgUJBQAAAA==.Cadorex:BAAALgADCgEJAQAAAA==.Caffeinefree:BAAALgADCggJBwAAAA==.Calacolinda:BAAALgAECgQJBgAAAA==.Calamari:BAAALgAECgEJAQAAAA==.Cavakworm:BAAALgADCgEJAQAAAA==.Caylin:BAAALgADCgUJBgAAAA==.Cayusedemon:BAAALgADCgEJAQAAAA==.Cayusemage:BAAALgADCgkJFQAAAA==.Cayusevoid:BAAALgADCgcJBwAAAA==.',
Ce='Ceridwyn:BAAALgAECgQJBQAAAA==.',
Ch='Chariscrushr:BAAALgAECgQJCAABLgAFFAgJIAAHAKAaAA==.Cheesecurd:BAAALgAECgQJBAAAAA==.Chen:BAAALgADCgIJAgAAAA==.Choal:BAAALgAECgEJAQAAAA==.Chokaho:BAAALgAECgQJBgAAAA==.Chubberoni:BAAALgAECgUJBwAAAA==.',
Ci='Cinnamongirl:BAAALgAECgcJEgAAAA==.',
Co='Corahin:BAABLgAECn8bAAIRAAYJGxASRAA5AQARAAYJGxASRAA5AQAAAA==.Corious:BAAALgAECgQJCQAAAA==.Cosmos:BAAALgAECgYJDQAAAA==.Cougarhunter:BAAALgAECgkJEAAAAA==.',
Cr='Crixux:BAAALgADCgMJAQAAAA==.Crokus:BAAALgADCggJCAAAAA==.',
Cu='Cuecumba:BAABLgAECn8uAAITAAkJICZ2AABbAwATAAkJICZ2AABbAwAAAA==.',
Da='Daemonerror:BAAALgAECgUJBQABLgAECgkJSQAUAKIjAA==.Dalren:BAACLgAFFH8aAAMVAAcJ/RzlEQDuAQAVAAYJ/RzlEQDuAQAWAAIJuwNtCwBLAAAuAAQKf0wAAxUACQnIJf0BAGEDABUACQnIJf0BAGEDABYABgnyIEMMABcCAAAA.Dalryn:BAAALgAECgYJDQABLgAFFAcJGgAVAP0cAA==.Dalvix:BAAALgADCgEJAQABLgAECgkJJgAGAFogAA==.Damocles:BAABLgAECn8YAAIBAAYJlwwlyAD9AAABAAYJlwwlyAD9AAAAAA==.Danazel:BAAALgADCgMJBQAAAA==.Dartagnan:BAACLgAFFH8PAAIXAAMJnhwPUQAIAQAXAAMJnhwPUQAIAQAuAAQKfycAAxcACQnLHTlJAMYBABcABwkLHzlJAMYBABgABgn3FI8bANEAAAAA.Darthmaul:BAABLgAECn8wAAIDAAkJyhHKHwDKAQADAAkJyhHKHwDKAQAAAA==.',
De='Deay:BAAALgADCgQJAQAAAA==.Delexa:BAAALgADCgkJQAAAAA==.Demonicnugie:BAAALgADCgEJAQAAAA==.Dendiian:BAABLgAECn8VAAIZAAYJ1hUgJwAdAQAZAAYJ1hUgJwAdAQAAAA==.',
Di='Didipullthat:BAAALgAECgMJAwABLgAFFAMJBQAGAPMKAA==.Diem:BAABLgAECn8dAAIXAAgJyw1rQQCqAQAXAAgJyw1rQQCqAQAAAA==.Dinendal:BAAALgADCgYJBgAAAA==.Dirtydotss:BAABLgAECn8VAAMFAAcJFwfXEgD/AAAFAAYJYQbXEgD/AAAEAAYJ5wSVzQC3AAAAAA==.Discernment:BAAALgAECgEJAQAAAA==.Divigitives:BAAALgAECgQJBAAAAA==.',
Do='Docrivan:BAAALgAECgYJCwAAAA==.Docsassist:BAAALgAECgMJAwABLgAECgYJCwAaAAAAAA==.Doregit:BAABLgAECn81AAIOAAkJIx/KCwCrAgAOAAkJIx/KCwCrAgAAAA==.Dowedoes:BAABLgAECn89AAIMAAkJgheXNgAnAgAMAAkJgheXNgAnAgAAAA==.',
Dr='Drachula:BAABLgAECn8bAAIbAAcJTRaiOwDAAQAbAAcJTRaiOwDAAQAAAA==.Dracultra:BAAALgAECgUJBwABLgAECgkJIAAcAF0fAA==.Drakcheese:BAAALgADCgUJBQAAAA==.Dreolan:BAABLgAECn9NAAIdAAkJQhmKFACmAgAdAAkJQhmKFACmAgAAAA==.Drynnai:BAAALgADCgEJAgAAAA==.',
Dy='Dyala:BAACLgAFFH8QAAMdAAMJjg8XRACjAAAdAAMJjg8XRACjAAADAAMJMwSUOgCOAAAuAAQKfyMAAx0ACQkDErZmAAABAB0ACQkDErZmAAABAAMABAkoDttOANEAAAAA.',
['Dö']='Dönövan:BAABLgAECn8xAAIMAAkJdBT9RQD0AQAMAAkJdBT9RQD0AQAAAA==.',
Eg='Eggyolk:BAAALgAECgQJBQABLgAECgkJRwAGALkPAA==.',
El='Elapst:BAAALgAECgEJAQAAAA==.Elastwo:BAAALgADCgcJEgABLgAECgEJAQAaAAAAAA==.Eloise:BAABLgAECn8aAAILAAgJMw+aLQBgAQALAAgJMw+aLQBgAQAAAA==.Elvenbane:BAABLgAECn8nAAIeAAkJrRO3HADfAQAeAAkJrRO3HADfAQAAAA==.',
Em='Emily:BAAALgAECgYJDAAAAA==.Emry:BAAALgADCgYJBgABLgAECgcJHQAUADkPAA==.',
En='Enable:BAEBLgAECn8gAAIfAAkJVRxUCgCOAgAfAAkJVRxUCgCOAgABLgAECgkJNAAQAE8iAA==.',
Ep='Epictool:BAAALgAECggJCwAAAA==.',
Et='Ethereal:BAAALgAECgEJAQAAAA==.',
Ew='Ew:BAACLgAFFH8GAAIXAAIJGRZ/GABWAAAXAAIJGRZ/GABWAAAuAAQKfxQAAhcABwlLHWwmACACABcABwlLHWwmACACAAEuAAUUAgkIAAgA0x4A.',
Ex='Extrathick:BAAALgAECgMJAwAAAA==.',
Fa='Fabel:BAEBLgAECn80AAIQAAgJTyJeBwBoAgAQAAgJTyJeBwBoAgAAAA==.Falahad:BAAALgAECgEJAQABLgAFFAMJDwADAD4OAA==.Faltree:BAACLgAFFH8PAAMDAAMJPg7XMwCxAAADAAMJPg7XMwCxAAAdAAIJuhVmUgB6AAAuAAQKfyEABB0ACQkeFf5TAFcBAB0ACAkrFP5TAFcBAAMACAkOF0kyAFEBACAAAQnfAUo6AB8AAAAA.Fathershale:BAAALgAECgUJCAAAAA==.',
Fi='Firelord:BAAALgADCgEJAQAAAA==.',
Fo='Foulcor:BAABLgAECn8dAAMcAAkJ7B6OFwBNAgAcAAgJlB6OFwBNAgAMAAcJRhExmQBDAQAAAA==.',
Fr='Freakadeek:BAABLgAECn8VAAQhAAkJaw1EIQDEAAAIAAUJ0AiV1wDeAAAhAAMJnhdEIQDEAAAJAAYJgwTUTgBXAAAAAA==.Freâkadeek:BAAALgAECgIJBQABLgAECgkJFQAhAGsNAA==.Freäk:BAAALgADCgMJAwABLgAECgkJFQAhAGsNAA==.Frieren:BAABLgAECn89AAIBAAkJ6xU4PwAfAgABAAkJ6xU4PwAfAgAAAA==.Frink:BAAALgAECgEJAQABLgAECgkJPQAiAOEkAA==.Frostlord:BAAALgAECgIJAgAAAA==.',
Fu='Fundetected:BAAALgAFFAIJAgABLgAFFAMJBQAGAPMKAA==.Furyofthenug:BAAALgADCgcJCgAAAA==.Fuzzywuzzy:BAAALgAECgUJBQABLgAECgYJHQASALgdAA==.',
Ga='Gabbyo:BAABLgAECn8lAAIdAAkJ/Ad5VAA+AQAdAAkJ/Ad5VAA+AQAAAA==.Galadorn:BAABLgAECn8mAAIGAAkJWiDADwDFAgAGAAkJWiDADwDFAgAAAA==.Gallgamesh:BAAALgADCgIJAgAAAA==.Garfall:BAAALgAECgcJDgAAAA==.Garga:BAAALgADCgMJBAABLgAECgQJBAAaAAAAAA==.',
Ge='Geirvaldr:BAAALgAECgYJBgAAAA==.Gerdash:BAAALgAECgMJBAAAAA==.Gerred:BAACLgAFFH8HAAINAAMJPRj3IwDfAAANAAMJPRj3IwDfAAAuAAQKfx8AAw0ACAnNGoANABACAA0ACAk1GoANABACAA4ABAlFFBpmAMQAAAAA.',
Gh='Ghallow:BAABLgAECn8bAAIPAAgJahibCgAQAgAPAAgJahibCgAQAgAAAA==.Ghosty:BAACLgAFFH8JAAIjAAQJOxWQIAAhAQAjAAQJOxWQIAAhAQAuAAQKfyoAAiMABwlQIFcUAP8BACMABwlQIFcUAP8BAAAA.',
Gi='Gimp:BAAALgAECgEJAgAAAA==.',
Gl='Gladur:BAABLgAFFH8GAAMHAAYJyAzxHwDZAAAHAAUJtwzxHwDZAAAUAAEJmQF9ZQAxAAABLgAFFAcJHQABAE0YAA==.',
Go='Goldenflame:BAAALgAECgUJBwAAAA==.Goldenlily:BAAALgAECgYJEgAAAA==.Goldenmunc:BAABLgAECn8tAAIBAAkJNxftNQBBAgABAAkJNxftNQBBAgAAAA==.Goldenone:BAAALgAECgQJBQAAAA==.Goldenpants:BAABLgAECn8nAAIOAAkJjxM6IgDgAQAOAAkJjxM6IgDgAQAAAA==.',
Gr='Grievous:BAABLgAECn89AAITAAkJOyW4AABKAwATAAkJOyW4AABKAwAAAA==.',
['Gû']='Gûrth:BAAALgADCgcJBwAAAA==.',
Ha='Hailmary:BAABLgAECn8oAAILAAkJEiV9AQCoAwALAAkJEiV9AQCoAwAAAA==.Halcrux:BAAALgAECgIJAgAAAA==.Halvard:BAAALgADCgMJBQAAAA==.Harusen:BAABLgAECn8cAAIkAAkJFR9EAgCmAgAkAAkJFR9EAgCmAgAAAA==.Havgnwltrav:BAAALgADCgcJBgAAAA==.',
He='Healaga:BAAALgAECgYJBgABLgAECggJNAAIADYbAA==.',
Hi='Hildalsind:BAAALgADCgkJCQABLgAFFAMJCQABAIMdAA==.',
Ho='Homestar:BAAALgADCgEJAQAAAA==.Hooll:BAAALgAECgIJAgAAAA==.Hornreaper:BAABLgAECn8bAAIVAAYJ5hfvJACVAQAVAAYJ5hfvJACVAQAAAA==.Hotshot:BAAALgAECgMJAwAAAA==.',
Hu='Hubbabubbajr:BAAALgAECgMJAwABLgAECgkJMwAdAIIbAA==.Hubert:BAAALgADCgEJAgAAAA==.Huracan:BAAALgAECgEJAQAAAA==.Hurin:BAAALgAECgcJDgAAAA==.Huur:BAAALgAECgEJAQABLgAECgEJAQAaAAAAAA==.',
Hy='Hyetta:BAAALgAECgQJBgABLgAECgkJHAAkABUfAA==.Hyir:BAAALgADCgYJBwABLgAFFAQJGAAHAIUeAA==.',
Il='Ilavengu:BAAALgAECgMJBQABLgAFFAQJFgAbADEmAA==.Illiya:BAABLgAECn8UAAILAAUJ5QwsRADZAAALAAUJ5QwsRADZAAAAAA==.',
Ir='Irôn:BAAALgAECgEJAQAAAA==.',
Iu='Iutara:BAAALgAECgYJDAAAAA==.',
Ja='Jaalein:BAAALgADCgcJDgAAAA==.Jayonor:BAABLgAECn80AAQRAAkJthVkGgAOAgARAAkJthVkGgAOAgAPAAYJ9we4GgAeAQAbAAcJ5AZlcQAIAQAAAA==.',
Je='Jek:BAAALgAECgUJBQAAAA==.',
Jo='Joryu:BAAALgADCgIJAwAAAA==.',
Ju='Juicycucci:BAAALgAECgcJEgABLgAFFAMJBQAGAPMKAA==.',
Ka='Kaevrielle:BAECLgAFFH8IAAITAAMJfBXTCADGAAATAAMJfBXTCADGAAAuAAQKfx4AAxMACQmOG2MHAAwCABMACQmOG2MHAAwCACUAAQlWCod4ACcAAAAA.Kaison:BAABLgAECn8XAAMeAAkJEQieMQBVAQAeAAkJEQieMQBVAQAmAAcJBAtNNQBAAQABLgAECgkJIAAGAA0VAA==.Kaladîn:BAAALgAECgMJAwABLgAFFAcJHQABAE0YAA==.Kalii:BAAALgADCgQJBAAAAA==.Kamel:BAAALgADCgcJDQAAAA==.Kardin:BAAALgADCgEJAQAAAA==.Karwin:BAABLgAECn8bAAIBAAgJ/xRCaACsAQABAAgJ/xRCaACsAQAAAA==.Katakuri:BAAALgAECgEJAgAAAA==.',
Ke='Keeper:BAAALgAECgYJDAABLgAFFAUJCQAMAK0gAA==.Keeperodark:BAABLgAECn8YAAIEAAgJKxfFAQBrAQAEAAgJKxfFAQBrAQABLgAFFAUJCQAMAK0gAA==.Keeperolight:BAACLgAFFH8JAAIMAAUJrSAQBQAeAQAMAAUJrSAQBQAeAQAuAAQKf1MAAwwACQlUJeUEAFADAAwACQlUJeUEAFADABwAAQmBGBSQAEAAAAAA.Kemanorel:BAAALgADCgcJDgABLgAECgkJJwAeAK0TAA==.',
Ki='Kianth:BAAALgADCgkJEgAAAA==.Killkat:BAABLgAECn8uAAIBAAkJgxhkNQBDAgABAAkJgxhkNQBDAgAAAA==.',
Ko='Kodera:BAABLgAECn8dAAMSAAYJuB3ZDQDyAQASAAYJuB3ZDQDyAQAWAAQJwhzKDgAfAQAAAA==.Koojo:BAAALgAECgcJCAAAAA==.Kosma:BAAALgAECgYJBgAAAA==.Kovae:BAAALgADCgEJAQAAAA==.',
Kr='Kraken:BAAALgADCgUJBQAAAA==.',
Ku='Kusheddruid:BAAALgADCgMJBQAAAA==.',
Ky='Kyaritin:BAAALgAECgMJAwABLgAECgYJCgAaAAAAAA==.Kyokei:BAAALgAECgEJAQAAAA==.',
La='Laiho:BAAALgADCgUJCAAAAA==.Lans:BAABLgAECn8UAAQnAAkJIQ0hDQD4AAAnAAUJ2AkhDQD4AAABAAQJ1Q8vzAD3AAAoAAQJAwkBCQDKAAAAAA==.Larew:BAACLgAFFH8FAAIMAAMJbgfWfgC4AAAMAAMJbgfWfgC4AAAuAAQKfy8AAgwACQnfGfMnAGQCAAwACQnfGfMnAGQCAAAA.Lazytemplar:BAAALgADCgMJAwABLgAFFAEJAQAaAAAAAA==.',
Le='Lealla:BAABLgAECn89AAIDAAkJlCI8BQAIAwADAAkJlCI8BQAIAwAAAA==.Lechevalier:BAAALgAFFAIJAwABLgAFFAMJBQAGAPMKAA==.Leodin:BAAALgAECgEJAgAAAA==.Leorus:BAAALgAECgIJAgAAAA==.Lethhunt:BAACLgAFFH8UAAMYAAcJxQxBEABdAQAYAAcJ3gpBEABdAQAXAAIJWw4MGgCeAAAuAAQKfy4AAxgACQncHpwGACgCABgACQlgHpwGACgCABcAAgk+JFKHANIAAAAA.',
Li='Lilmistfox:BAAALgAECgUJBwABLgAFFAQJFgAbADEmAA==.Lioh:BAAALgAECgQJBAAAAA==.Lizardgang:BAABLgAECn8UAAIXAAYJ0xiWewBIAQAXAAYJ0xiWewBIAQAAAA==.',
Lo='Loganshu:BAAALgAECggJDAAAAA==.Lokan:BAACLgAFFH8RAAMiAAMJWRkcHQDoAAAiAAMJWRkcHQDoAAAXAAEJwgjhqABFAAAuAAQKfywAAyIACQlHHqoIAJQCACIACQlHHqoIAJQCABcAAQn+CiAyATYAAAAA.Lots:BAACLgAFFH8RAAIEAAMJhhtgZwD3AAAEAAMJhhtgZwD3AAAuAAQKfycAAwQACQktIgIrAC4CAAQACAliIgIrAC4CAAIABAngHkcsAA0BAAAA.',
Lu='Ludacast:BAAALgADCgIJAgAAAA==.Ludafists:BAAALgADCgcJDAAAAA==.Ludakris:BAABLgAECn8eAAIQAAkJfxhLCwATAgAQAAkJfxhLCwATAgAAAA==.Lumanoth:BAAALgAECgYJBgAAAA==.',
Ly='Lyna:BAABLgAECn8gAAIbAAkJpROaPwCvAQAbAAkJpROaPwCvAQAAAA==.Lynaya:BAAALgADCgIJAgAAAA==.',
['Lí']='Líonheart:BAABLgAECn8dAAMcAAcJYBeNPgBKAQAcAAcJYBeNPgBKAQAMAAYJFgvJ0wDuAAAAAA==.',
['Lî']='Lîghtless:BAACLgAFFH8PAAIBAAYJBhqgGABoAQABAAYJBhqgGABoAQAuAAQKfxcAAgEACAmfJUchAO4CAAEACAmfJUchAO4CAAAA.',
['Lú']='Lúckally:BAAALgADCgQJBAABLgAECgYJCgAaAAAAAA==.Lúckÿ:BAAALgAECgYJCgAAAA==.',
Ma='Magetheo:BAAALgADCgIJAgAAAA==.Magicpanda:BAAALgAECgUJCwAAAA==.Mahina:BAAALgAECgIJAgAAAA==.Malik:BAAALgADCgIJAgAAAA==.Marcille:BAABLgAECn8nAAIBAAgJ2RO6dwCKAQABAAgJ2RO6dwCKAQAAAA==.Masyledian:BAAALgAECgIJBAAAAA==.Mathor:BAAALgAECgEJAgAAAA==.Mavrbg:BAAALgAECgQJBQAAAA==.Mayhaps:BAABLgAECn9EAAMXAAkJFRuDJwBBAgAXAAkJFRuDJwBBAgAYAAEJZACpmgAYAAAAAA==.',
Mc='Mcbain:BAABLgAECn89AAIiAAkJ4STXAQA9AwAiAAkJ4STXAQA9AwAAAA==.',
Me='Melinia:BAAALgAECgEJAQABLgAECgEJAgAaAAAAAA==.Melrine:BAAALgADCgMJAwAAAA==.Mentaltitty:BAABLgAECn8gAAIBAAkJgxKISwD5AQABAAkJgxKISwD5AQAAAA==.Meret:BAAALgADCgMJBQAAAA==.',
Mi='Minerwor:BAAALgAECgUJCQAAAA==.Mirrayla:BAAALgADCgYJBgAAAA==.Misty:BAAALgADCgYJBgAAAA==.',
Mm='Mmisty:BAABLgAECn9IAAIDAAkJghmKDwBnAgADAAkJghmKDwBnAgAAAA==.',
Mo='Moarthretplz:BAAALgAECgUJCQABLgAFFAQJFgAbADEmAA==.Mohji:BAAALgAFFAEJAQABLgAFFAcJGgAmAOwUAA==.Moldynuggets:BAAALgAECgQJCAAAAA==.Momometaru:BAABLgAECn8kAAQEAAkJgRaBQQDYAQAEAAkJfhOBQQDYAQACAAUJNhRyJgAsAQAFAAMJzxrGJgCMAAAAAA==.Monsterbee:BAABLgAECn9MAAIEAAkJ1BXjKwAqAgAEAAkJ1BXjKwAqAgAAAA==.',
Mu='Mustypizza:BAABLgAECn8uAAICAAkJihjIBAAsAgACAAkJihjIBAAsAgAAAA==.',
Mx='Mxicancowboy:BAAALgADCgEJAgAAAA==.',
My='Mystery:BAABLgAECn89AAMSAAkJNiC9AgAzAwASAAkJNiC9AgAzAwAWAAUJXhELEAAKAQAAAA==.',
['Mê']='Mêøwzêr:BAAALgAECggJEwAAAA==.',
['Mÿ']='Mÿst:BAAALgAECgMJBAAAAA==.',
Na='Nak:BAAALgAECgYJBgAAAA==.Narashi:BAAALgAECgQJCAAAAA==.Naril:BAAALgADCgUJBQAAAA==.Nats:BAABLgAECn8kAAIbAAgJSxGwOACfAQAbAAgJSxGwOACfAQAAAA==.',
Ne='Neameny:BAABLgAECn89AAIXAAkJGBOdOwDxAQAXAAkJGBOdOwDxAQAAAA==.',
Ni='Nianji:BAAALgADCgYJDgAAAA==.Nightstar:BAAALgADCgMJAwAAAA==.Nightworld:BAAALgADCgcJDgAAAA==.',
No='Noctum:BAAALgAECgYJBgAAAA==.Nordicpally:BAAALgADCgQJBAAAAA==.Notbomba:BAAALgAECgEJAwAAAA==.Notgim:BAAALgADCggJCAAAAA==.',
Nu='Nualrossan:BAAALgADCgYJCAAAAA==.Nubrac:BAAALgAECgkJEwAAAA==.',
Ny='Nylux:BAAALgAECgYJDwAAAA==.',
Ob='Oblivion:BAACLgAFFH8FAAIEAAMJ9Rx0YgACAQAEAAMJ9Rx0YgACAQAuAAQKfz4AAwQACQmfJLQGACUDAAQACQmfJLQGACUDAAIAAQkAAFFdAFcAAAAA.',
Oo='Oostren:BAAALgAECgEJAgAAAA==.',
Or='Orsyp:BAAALgADCgkJGgAAAA==.',
Pa='Palockie:BAAALgADCgEJAQAAAA==.Pandas:BAABLgAECn8hAAIRAAkJAhF6JwCxAQARAAkJAhF6JwCxAQAAAA==.Partyrocker:BAABLgAECn8XAAIiAAcJag76KgBKAQAiAAcJag76KgBKAQABLgAECgkJFQAhAGsNAA==.Paynë:BAAALgAECgYJBgAAAA==.',
Pi='Pixae:BAACLgAFFH8PAAISAAMJjwdCIwCHAAASAAMJjwdCIwCHAAAuAAQKfyEAAhIACAm5Cm8ZAD8BABIACAm5Cm8ZAD8BAAAA.Pixiechaos:BAAALgAECgQJCAAAAA==.',
Po='Poliahu:BAABLgAECn8XAAIXAAYJvQxQlAAXAQAXAAYJvQxQlAAXAQAAAA==.Porthoss:BAAALgADCggJDwAAAA==.Powerplant:BAACLgAFFH8YAAIXAAcJox/UDQD6AQAXAAcJox/UDQD6AQAuAAQKfyYAAhcACQkgJCgIAA4DABcACQkgJCgIAA4DAAAA.Poyoram:BAAALgADCgEJAQAAAA==.',
Pr='Pryi:BAAALgADCgcJBwABLgAFFAMJBwAMAO0IAA==.',
Py='Pyralys:BAABLgAECn85AAMLAAkJGBFjHADjAQALAAkJGBFjHADjAQAeAAMJqQI8iAAxAAAAAA==.',
Qu='Quizac:BAAALgADCgMJBQAAAA==.',
Ra='Rabidghost:BAAALgADCgYJBgAAAA==.Ragemonk:BAAALgAECgUJDgABLgAFFAEJAQAaAAAAAA==.Ragetality:BAAALgAFFAEJAQAAAA==.Rahken:BAAALgADCgEJAQAAAA==.Rakthera:BAAALgADCgcJBwAAAA==.Rallaster:BAAALgAECgYJBgABLgAECgkJJwAeAK0TAA==.Ramaria:BAAALgADCgkJCQABLgAECgkJJgAGAFogAA==.Raserei:BAABLgAFFH8JAAIOAAMJIhfyLwDwAAAOAAMJIhfyLwDwAAAAAA==.Rasputain:BAAALgADCgYJCgAAAA==.Rasputein:BAAALgADCgcJBwAAAA==.Rattelyr:BAAALgAECgYJDgAAAA==.Ravara:BAAALgADCgYJBgABLgAECgkJJgAGAFogAA==.Razgaurd:BAAALgAECgMJAwAAAA==.',
Re='Recolada:BAAALgAECggJCAAAAA==.Regice:BAAALgAECgcJBwABLgAFFAQJDQAJAF4XAA==.Regicee:BAACLgAFFH8NAAIJAAQJXhceGQAeAQAJAAQJXhceGQAeAQAuAAQKf0cAAwkACQmEIl4EAO8CAAkACQmEIl4EAO8CAAgABAlJEAL+AK8AAAAA.Retam:BAAALgAECgcJDgAAAA==.Revakos:BAAALgADCgMJAwAAAA==.',
Rh='Rhysandra:BAAALgAECgQJCQAAAA==.',
Ri='Ribble:BAAALgADCgMJAwAAAA==.Riffraff:BAAALgAECgcJBAAAAA==.Rindou:BAAALgAECgkJBAAAAA==.Ripcord:BAAALgAECgUJCgAAAA==.Ripem:BAAALgADCgYJBgAAAA==.Ripperoni:BAAALgAECgcJDQAAAA==.Rizek:BAAALgAECgUJBgABLgAECgcJHQAUADkPAA==.Rizzx:BAAALgAECgEJAQAAAA==.',
Ro='Rockdyou:BAABLgAECn8nAAIIAAkJ+R51JABzAgAIAAkJ+R51JABzAgAAAA==.Roglef:BAAALgAECgQJCQAAAA==.Rotlobster:BAABLgAECn8aAAIFAAkJAB71AQDEAgAFAAkJAB71AQDEAgAAAA==.Roxxy:BAAALgAECgQJBAAAAA==.',
Ru='Rundvelt:BAACLgAFFH8RAAIQAAMJeA0IDwCQAAAQAAMJeA0IDwCQAAAuAAQKfyQAAhAACQlSEQwVAIABABAACQlSEQwVAIABAAAA.',
Sa='Sage:BAAALgADCgcJCAAAAA==.Sandwich:BAAALgAECgcJCAAAAA==.Saphíra:BAAALgAFFAIJAQABLgAFFAcJHQABAE0YAA==.Sapkick:BAAALgAECgQJBwAAAA==.',
Se='Serdragon:BAAALgADCgQJBAAAAA==.Sertian:BAAALgAECgEJAQAAAA==.Servoid:BAAALgAECgUJCQAAAA==.',
Sh='Shando:BAAALgAECgEJAQAAAA==.Shiftstyle:BAEALgAECgEJAQAAAA==.Shtanky:BAACLgAFFH8PAAIKAAMJaBFFHgClAAAKAAMJaBFFHgClAAAuAAQKfyQAAgoACQnHD7QWAI4BAAoACQnHD7QWAI4BAAAA.',
Si='Silentsocks:BAAALgAECgUJDAAAAA==.Sixsixsix:BAAALgAECgcJCgABLgAFFAIJCAAIANMeAA==.',
Sk='Skoogz:BAABLgAECn8UAAMJAAYJbBRYJgAhAQAJAAYJCBRYJgAhAQAIAAQJ5A+O1QDhAAAAAA==.',
Sm='Smackdowne:BAAALgADCgIJAgAAAA==.',
So='Soggyy:BAAALgADCgYJCwAAAA==.Solar:BAABLgAECn8VAAQHAAcJyRkxLwBtAQAHAAYJCxYxLwBtAQAfAAYJrhzoOABmAQAUAAEJUwL61wAaAAAAAA==.Soulfulgingr:BAABLgAECn8aAAIRAAcJmgqXBAB0AAARAAcJmgqXBAB0AAAAAA==.',
St='Starlagosa:BAAALgADCgYJCQAAAA==.Sturm:BAAALgAECgMJAwAAAA==.Styx:BAAALgAECgMJAwAAAA==.',
Su='Sunbake:BAAALgAECgUJEQAAAA==.',
Sw='Sweetbbyraze:BAACLgAFFH8cAAMWAAUJLiGpBQAIAQAVAAUJFh2dIQBTAQAWAAQJQCGpBQAIAQAuAAQKfyYAAxYACAkpIVIGAJACABYABwm8IVIGAJACABUAAwnyHI9rAJkAAAAA.',
Sy='Sylaena:BAABLgAECn8oAAIYAAgJVQoeFAAgAQAYAAgJVQoeFAAgAQAAAA==.Sylvrstorm:BAAALgAECgcJDQAAAA==.',
['Së']='Sërënity:BAABLgAECn8XAAIdAAUJjg5IAwCqAAAdAAUJjg5IAwCqAAAAAA==.',
['Sí']='Sín:BAAALgAECgcJDAABLgAFFAIJCAAIANMeAA==.',
Ta='Talipally:BAACLgAFFH8HAAIMAAMJ7QjLewC+AAAMAAMJ7QjLewC+AAAuAAQKfxwAAgwACQkyEM54AH0BAAwACQkyEM54AH0BAAAA.Talishammy:BAAALgAECgMJAwABLgAFFAMJBwAMAO0IAA==.Taliwhacker:BAAALgAFFAEJAQABLgAFFAMJBwAMAO0IAA==.Talonleafgrd:BAAALgAECgkJCgAAAA==.Tanaka:BAABLgAECn8gAAIIAAgJgBMHWgC4AQAIAAgJgBMHWgC4AQAAAA==.Tanisong:BAAALgAECgQJDAAAAA==.Tassadar:BAAALgAECgUJCAAAAA==.',
Te='Teldo:BAAALgADCgMJBQAAAA==.Tepeyollotl:BAAALgADCgEJAQAAAA==.Terayus:BAAALgADCgcJDAAAAA==.Teyliah:BAAALgADCgMJAwAAAA==.',
Tf='Tf:BAAALgAECgYJBgABLgAFFAIJCAAIANMeAA==.',
Th='Thekingpunch:BAABLgAECn9JAAMUAAkJoiO6BwAhAwAUAAkJoiO6BwAhAwAHAAEJahZVjwBCAAAAAA==.Thenle:BAAALgADCggJDgAAAA==.Thline:BAAALgADCgMJBQAAAA==.Thunderblitz:BAABLgAECn8rAAIcAAkJdgknMwCIAQAcAAkJdgknMwCIAQAAAA==.Thurmus:BAAALgADCgkJQAAAAA==.',
Ti='Tillwar:BAABLgAECn87AAIOAAkJKh2pEAByAgAOAAkJKh2pEAByAgAAAA==.Tinymonk:BAAALgAECgMJAwAAAA==.',
To='Tofu:BAACLgAFFH8JAAIIAAMJ5Bx4hwD6AAAIAAMJ5Bx4hwD6AAAuAAQKf0QAAwgACQlIHvAVAMQCAAgACQlIHvAVAMQCAAkABwmjFroaAIgBAAAA.Tokanya:BAAALgAECgEJAQAAAA==.Tortillachip:BAAALgAECgEJAgAAAA==.Toxidot:BAAALgAECgEJAQAAAA==.',
Tr='Treibh:BAABLgAECn8qAAIdAAkJCxilFwCJAgAdAAkJCxilFwCJAgAAAA==.Trelephant:BAAALgAECgMJBQAAAA==.Trulydps:BAABLgAECn8vAAIXAAkJ4hQMLwAgAgAXAAkJ4hQMLwAgAgAAAA==.Trulyog:BAAALgAECgQJBAABLgAECgkJLwAXAOIUAA==.',
Tu='Tubbsmcgee:BAACLgAFFH8YAAIbAAYJ6x8hCABFAgAbAAYJ6x8hCABFAgAuAAQKfyUAAhsACQkrJLgHAPkCABsACQkrJLgHAPkCAAEuAAUUBgkYABsA6x8A.Tukkit:BAAALgAECgYJDgAAAA==.',
Tw='Twistedshot:BAAALgADCggJCAAAAA==.Twizzler:BAABLgAECn9TAAIBAAkJZQjAfgB6AQABAAkJZQjAfgB6AQAAAA==.',
Ty='Tyraniik:BAAALgADCgYJCAAAAA==.',
['Të']='Tërris:BAABLgAECn8cAAIJAAkJQBHiGgCGAQAJAAkJQBHiGgCGAQAAAA==.',
['Tî']='Tîlldeath:BAAALgAECgUJBwAAAA==.',
['Tõ']='Tõaster:BAAALgADCgQJBAABLgAECgkJJgAGAFogAA==.',
Uj='Uji:BAAALgADCgEJAQAAAA==.',
Ur='Urowndad:BAAALgAECgUJBQABLgAECggJFgAMAL0TAA==.Urownmother:BAAALgADCgUJBQABLgAECggJFgAMAL0TAA==.',
Va='Vaellian:BAAALgAECgYJDAAAAA==.Vallez:BAECLgAFFH8VAAMcAAMJoh/GIwACAQAcAAMJoh/GIwACAQAMAAMJ/g1hcwDMAAAuAAQKfyoAAxwACQmqHQQSAIMCABwACQmqHQQSAIMCAAwAAwmiDWdGAWYAAAAA.Vanillaghost:BAAALgADCgIJAQAAAA==.Varnusshadow:BAAALgAECgUJBgAAAA==.',
Ve='Vearik:BAAALgAECgUJBwAAAA==.Velladoree:BAABLgAECn8gAAIUAAgJiwnnWQALAQAUAAgJiwnnWQALAQAAAA==.Vendaryn:BAAALgADCggJCAAAAA==.Vexahlia:BAAALgADCgMJAwAAAA==.',
Vg='Vgurlpally:BAAALgADCgYJBgAAAA==.',
Vy='Vynlorlan:BAAALgADCgMJAwABLgAECgMJBAAaAAAAAA==.',
Wa='Walkindead:BAAALgAECgQJBgAAAA==.Waveygravee:BAAALgAECgIJAwAAAA==.Wavyghoul:BAAALgAECgEJAQAAAA==.Wavygraivy:BAABLgAECn8cAAIbAAYJ2BUUTACAAQAbAAYJ2BUUTACAAQAAAA==.',
We='Wedragon:BAAALgAECgYJEwAAAA==.',
Wh='Wheelchair:BAACLgAFFH8LAAIIAAQJOxv7bwAeAQAIAAQJOxv7bwAeAQAuAAQKfxwAAggACAkSJF0SAA4DAAgACAkSJF0SAA4DAAAA.',
Wo='Woofwoof:BAAALgAFFAIJAgAAAA==.',
Wu='Wullemage:BAAALgADCgcJEwABLgAFFAcJHwAjALAaAA==.',
['Wå']='Wåsp:BAABLgAECn9HAAIGAAkJuQ8LUACVAQAGAAkJuQ8LUACVAQAAAA==.',
Xb='Xb:BAAALgAECgcJBQAAAA==.',
Xh='Xhexana:BAABLgAECn84AAIbAAkJTRf/HABlAgAbAAkJTRf/HABlAgABLgAECgkJPQAXABgTAA==.',
Xi='Xiaopo:BAAALgAECgEJAQABLgAFFAQJFgAbADEmAA==.',
Xr='Xrael:BAAALgAECgEJAQABLgAFFAMJEwAHACMiAA==.Xrayl:BAACLgAFFH8TAAMHAAMJIyKZEwAgAQAHAAMJIyKZEwAgAQAfAAMJxAxEOwC5AAAuAAQKfyUAAwcACQnoIMwNAGkCAAcACAmrIcwNAGkCAB8AAQmOG/N9AE8AAAAA.',
Xz='Xzerocool:BAABLgAECn8WAAQMAAgJvRNCiQBeAQAMAAgJvRNCiQBeAQAQAAIJshNmPABqAAAcAAEJmQO0nQAiAAAAAA==.',
Ya='Yaniaa:BAAALgADCgcJBwAAAA==.Yannii:BAAALgADCgcJDgAAAA==.',
Ye='Yenko:BAAALgADCgIJAgAAAA==.',
Yo='Yolo:BAAALgADCgcJCwAAAA==.Yoshikazu:BAAALgAECgYJCQAAAA==.Yoyoboy:BAAALgAECgEJAQAAAA==.',
Za='Zaarah:BAAALgAECgMJBgAAAA==.',
Ze='Zellek:BAAALgADCgEJAQAAAA==.Zendezoth:BAABLgAECn8jAAIWAAkJpRmcAwBZAgAWAAkJpRmcAwBZAgAAAA==.Zephik:BAAALgADCgEJAQAAAA==.Zerofrost:BAABLgAECn8sAAIBAAkJqxl1PAAoAgABAAkJqxl1PAAoAgAAAA==.Zerrìc:BAAALgAECgQJBAAAAA==.Zevra:BAAALgADCgMJAwAAAA==.',
Zh='Zhiva:BAABLgAECn81AAIDAAgJxw2UNQBBAQADAAgJxw2UNQBBAQAAAA==.',
Zu='Zul:BAACLgAFFH8ZAAIjAAMJXiOeIgAQAQAjAAMJXiOeIgAQAQAuAAQKfzMAAyMACQkwI+gHAKkCACMACQkwI+gHAKkCACkAAQnLAkMiACQAAAAA.',
Zy='Zykoz:BAABLgAECn8uAAIjAAkJpCGMBADzAgAjAAkJpCGMBADzAgAAAA==.',
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
