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

local lookup = {'Mage-Frost','Warlock-Destruction','Druid-Balance','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Priest-Holy','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Shaman-Enhancement','Paladin-Protection','Shaman-Elemental','Evoker-Preservation','DemonHunter-Vengeance','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Unknown-Unknown','Shaman-Restoration','Paladin-Holy','Druid-Restoration','Priest-Shadow','Monk-Brewmaster','Druid-Feral','DeathKnight-Frost','Hunter-Survival','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Havoc','Priest-Discipline','Mage-Arcane','Mage-Fire','Rogue-Assassination',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=46,date='2026-06-28',data={Ab='Abomination:BAAALgADCgMJAwAAAA==.',
Ad='Adune:BAAALgAECgQJBQAAAA==.',
Ae='Aeidail:BAACLgAFFH8eAAIBAAcJTRhJJwDaAQABAAcJTRhJJwDaAQAuAAQKfyoAAgEACAnUI0McAAUDAAEACAnUI0McAAUDAAAA.Aelaria:BAAALgADCgMJAwAAAA==.Aeviria:BAABLgAECn8oAAICAAgJtRVxCADGAQACAAgJtRVxCADGAQAAAA==.',
Ag='Agraceful:BAACLgAFFH8MAAIDAAMJEAffNwCeAAADAAMJEAffNwCeAAAuAAQKfx8AAgMACQm8EjkfAM4BAAMACQm8EjkfAM4BAAAA.',
Ai='Ailee:BAAALgAECgYJDAAAAA==.Aios:BAAALgAECgIJAgAAAA==.Aiza:BAACLgAFFH8PAAIEAAMJ7QtvGwDFAAAEAAMJ7QtvGwDFAAAuAAQKfzgAAwQACQmXGb8dAHICAAQACQmXGb8dAHICAAUAAQkAAA1JAAAAAAAA.',
Al='Alaber:BAAALgAECgUJCAAAAA==.Aldanil:BAAALgADCgMJAwAAAA==.Allarria:BAAALgADCgYJBwABLgAECgkJJgAGAFogAA==.',
Am='Ampersand:BAAALgAECgMJBwAAAA==.',
An='Animalfriend:BAAALgAECgIJBAAAAA==.Anklesmasher:BAABLgAECn8UAAIHAAcJ/A4fPAAQAQAHAAcJ/A4fPAAQAQAAAA==.Antisocial:BAACLgAFFH8IAAIEAAMJgwydgwC+AAAEAAMJgwydgwC+AAAuAAQKfxkAAgQABglwGsBpAJABAAQABglwGsBpAJABAAEuAAUUAgkJAAgA0x4A.Antonidus:BAAALgAECgYJEgAAAA==.Anyah:BAABLgAECn8dAAIDAAgJqgRECQBzAAADAAgJqgRECQBzAAAAAA==.',
Ap='Apolloo:BAAALgADCgMJAwAAAA==.',
Aq='Aquadora:BAAALgAECgEJAQAAAA==.',
Ar='Arfaz:BAABLgAECn81AAMIAAkJwxqvQAABAgAIAAkJyRmvQAABAgAJAAYJWAoXOQCvAAAAAA==.Armbrost:BAAALgAECgYJCgAAAA==.Arthemis:BAAALgAECgEJAQAAAA==.Artimås:BAAALgADCgcJCAAAAA==.Arwynne:BAAALgADCgMJAwAAAA==.Arçano:BAAALgAECgEJAQABLgAECgkJGQAKADkTAA==.',
As='Ascension:BAAALgADCgcJBgABLgAFFAQJCAAEACEYAA==.Astrastar:BAABLgAECn8bAAMEAAYJ0wKg4wCVAAAEAAYJ0wKg4wCVAAACAAEJcgDDgAAOAAAAAA==.',
Au='Auralyn:BAAALgADCgMJBQAAAA==.Aurius:BAAALgAECgcJAgAAAA==.',
Av='Avarin:BAAALgADCgEJAQAAAA==.',
Ay='Aymont:BAAALgAECgQJBQAAAA==.',
Ba='Baerd:BAABLgAECn8aAAILAAcJZhPqKwBqAQALAAcJZhPqKwBqAQAAAA==.Baji:BAAALgAECgkJBwAAAA==.Barlz:BAAALgAECgEJAQAAAA==.',
Be='Beanpaste:BAAALgAECgcJAQABLgAFFAMJEAAIAHcZAA==.Beanutbutter:BAAALgADCgIJAgABLgAFFAMJEAAIAHcZAA==.Beaty:BAAALgAECgIJAgAAAA==.Bebby:BAABLgAECn8iAAMJAAcJJgOjBgB2AAAJAAYJKgOjBgB2AAAIAAIJaQJVeAEwAAAAAA==.Belonara:BAAALgAECgEJAQAAAA==.Belwolf:BAABLgAECn8UAAIIAAUJwApn6ADKAAAIAAUJwApn6ADKAAAAAA==.Bergstrom:BAABLgAECn80AAIMAAkJuhnAMAA+AgAMAAkJuhnAMAA+AgAAAA==.Bethanymarie:BAAALgAECgEJAQAAAA==.Betrayer:BAAALgADCgQJAwABLgAFFAQJCAAEACEYAA==.',
Bi='Biancaneve:BAACLgAFFH8FAAILAAMJsg8kJACaAAALAAMJsg8kJACaAAAuAAQKfx0AAgsACAk2GGcDADgBAAsACAk2GGcDADgBAAAA.Bighero:BAACLgAFFH8QAAIGAAMJSQsEagC4AAAGAAMJSQsEagC4AAAuAAQKfyAAAgYACQk9EVlvAFYBAAYACQk9EVlvAFYBAAAA.Bigmike:BAAALgAECgEJAgAAAA==.',
Bl='Blakkjezus:BAAALgAECgcJCwAAAA==.Blessednugie:BAAALgAECgcJEAAAAA==.Blitzbolts:BAAALgAECgEJAgAAAA==.Bludo:BAACLgAFFH8UAAMNAAcJKxCiDADfAAAOAAQJ+wqAHQADAQANAAUJHRWiDADfAAAuAAQKfx4AAw0ACQl6IWgZAIACAA0ACAk5GWgZAIACAA4ABgl9HFMYADYBAAAA.',
Bo='Boe:BAABLgAECn8pAAIPAAkJNAr5EwB6AQAPAAkJNAr5EwB6AQAAAA==.Bomba:BAAALgAECgUJCgAAAA==.Bombacløt:BAABLgAECn80AAMEAAkJphDwRQDJAQAEAAkJKBDwRQDJAQACAAcJbg6pFAAIAQAAAA==.Bowdirte:BAAALgAECgUJBwAAAA==.',
Br='Brastin:BAABLgAECn86AAIQAAkJkyJHAgASAwAQAAkJkyJHAgASAwABLgAFFAYJEwARAAoMAA==.Brenell:BAACLgAFFH8IAAIBAAMJgRLhiwDBAAABAAMJgRLhiwDBAAAuAAQKfzsAAgEACQmwIX0RAPECAAEACQmwIX0RAPECAAAA.',
Bu='Bu:BAAALgAECgYJDQABLgAECgYJHQASALgdAA==.Bubblehearth:BAAALgAECgYJCQABLgAFFAMJBgAGADgNAA==.Buffet:BAABLgAECn8aAAIBAAYJ0BHqrQAlAQABAAYJ0BHqrQAlAQABLgAFFAMJBgAGADgNAA==.Buhlitz:BAAALgAECgEJAgAAAA==.Butterbean:BAAALgADCgMJBQAAAA==.',
By='Bynis:BAABLgAECn8gAAIGAAkJDRVHSACtAQAGAAkJDRVHSACtAQAAAA==.',
Ca='Cabëla:BAAALgADCgUJBQAAAA==.Cactusjack:BAAALgADCgUJBQAAAA==.Cadorex:BAAALgADCgEJAQAAAA==.Caffeinefree:BAAALgADCggJBwAAAA==.Calacolinda:BAAALgAECgQJBgAAAA==.Calamari:BAAALgAECgEJAQAAAA==.Cavakworm:BAAALgADCgEJAQAAAA==.Caylin:BAAALgADCgUJBgAAAA==.Cayusedemon:BAAALgADCgEJAQAAAA==.Cayusemage:BAAALgADCgkJFwAAAA==.Cayusevoid:BAAALgADCgcJBwAAAA==.',
Ce='Celestiall:BAAALgAECgYJBgAAAA==.Ceridwyn:BAAALgAECgQJBQAAAA==.',
Ch='Chariscrushr:BAAALgAECgQJCAABLgAFFAQJBgAKAPMHAA==.Cheesecurd:BAAALgAECgUJCwAAAA==.Chen:BAAALgADCgIJAgAAAA==.Choal:BAAALgAECgEJAQAAAA==.Chokaho:BAAALgAECgQJBgAAAA==.Chubberoni:BAAALgAECgUJBwAAAA==.',
Ci='Cinnamongirl:BAAALgAECgcJEgAAAA==.',
Co='Corahin:BAABLgAECn8bAAIRAAYJGxASRAA5AQARAAYJGxASRAA5AQAAAA==.Corious:BAAALgAECgQJCQAAAA==.Cosmos:BAAALgAECgYJDQAAAA==.Cougarhunter:BAAALgAECgkJEAAAAA==.',
Cr='Crixux:BAAALgADCgMJAQAAAA==.Crokus:BAAALgADCggJCAAAAA==.',
Cu='Cuecumba:BAABLgAECn8uAAITAAkJICZ2AABbAwATAAkJICZ2AABbAwAAAA==.',
Da='Daemonerror:BAAALgAECgUJBQABLgAECgkJSQAUAKIjAA==.Dalren:BAACLgAFFH8iAAMVAAgJCxxuBQCjAQAVAAgJCxxuBQCjAQAWAAIJuwNtCwBLAAAuAAQKf0wAAxUACQnIJf0BAGEDABUACQnIJf0BAGEDABYABgnyIEMMABcCAAAA.Dalryn:BAAALgAECgYJDQABLgAFFAgJIgAVAAscAA==.Dalvix:BAAALgADCgEJAQABLgAECgkJJgAGAFogAA==.Damocles:BAABLgAECn8YAAIBAAYJlwwqyAD9AAABAAYJlwwqyAD9AAAAAA==.Danazel:BAAALgADCgMJBQAAAA==.Dartagnan:BAACLgAFFH8PAAIXAAMJnhwUUQAIAQAXAAMJnhwUUQAIAQAuAAQKfycAAxcACQnLHTpJAMYBABcABwkLHzpJAMYBABgABgn3FI8bANEAAAAA.Darthmaul:BAABLgAECn8wAAIDAAkJyhHNHwDKAQADAAkJyhHNHwDKAQAAAA==.',
De='Deay:BAAALgADCgQJAQAAAA==.Delexa:BAAALgADCgkJQAAAAA==.Demonicnugie:BAAALgADCgEJAQAAAA==.Dendiian:BAABLgAECn8WAAIZAAcJBxQeJwAdAQAZAAcJBxQeJwAdAQAAAA==.',
Di='Didipullthat:BAAALgAECgMJAwABLgAFFAMJBgAGADgNAA==.Diem:BAABLgAECn8dAAIXAAgJyw1rQQCqAQAXAAgJyw1rQQCqAQAAAA==.Dinendal:BAAALgADCgYJBgAAAA==.Dirtydotss:BAABLgAECn8VAAMFAAcJFwfXEgD/AAAFAAYJYQbXEgD/AAAEAAYJ5wSTzQC3AAAAAA==.Discernment:BAAALgAECgEJAQAAAA==.Divigitives:BAAALgAECgQJBAAAAA==.',
Do='Docrivan:BAAALgAECgYJCwAAAA==.Docsassist:BAAALgAECgMJAwABLgAECgYJCwAaAAAAAA==.Doregit:BAABLgAECn83AAINAAkJIx/LCwCrAgANAAkJIx/LCwCrAgAAAA==.Dowedoes:BAABLgAECn89AAIMAAkJgheVNgAnAgAMAAkJgheVNgAnAgAAAA==.',
Dr='Drachula:BAABLgAECn8bAAIbAAcJTRalOwDAAQAbAAcJTRalOwDAAQAAAA==.Dracultra:BAAALgAECgUJBwABLgAECgkJIgAcANQfAA==.Drakcheese:BAAALgADCgUJBQAAAA==.Dreolan:BAABLgAECn9NAAIdAAkJQhmKFACmAgAdAAkJQhmKFACmAgAAAA==.Drnatemonk:BAABLgAFFH8IAAIUAAQJdhGcDQAFAQAUAAQJdhGcDQAFAQAAAA==.Drynnai:BAAALgADCgEJAgAAAA==.',
Dy='Dyala:BAACLgAFFH8QAAMdAAMJjg8URACjAAAdAAMJjg8URACjAAADAAMJMwSSOgCOAAAuAAQKfyMAAx0ACQkDErNmAAABAB0ACQkDErNmAAABAAMABAkoDt5OANEAAAAA.',
['Dö']='Dönövan:BAABLgAECn8zAAIMAAkJAhX9RQD0AQAMAAkJAhX9RQD0AQAAAA==.',
Eg='Eggyolk:BAAALgAECgUJBwABLgAECgkJTwAGAAMQAA==.',
El='Elapst:BAAALgAECgIJAgAAAA==.Elastwo:BAAALgADCgcJEgABLgAECgIJAgAaAAAAAA==.Eloise:BAABLgAECn8aAAILAAgJMw+dLQBgAQALAAgJMw+dLQBgAQAAAA==.Elvenbane:BAABLgAECn8nAAIeAAkJrRO3HADfAQAeAAkJrRO3HADfAQAAAA==.',
Em='Emily:BAAALgAECgYJDAAAAA==.Emry:BAAALgADCgYJBgABLgAECgcJHQAUADkPAA==.',
En='Enable:BAEBLgAECn8gAAIfAAkJVRxUCgCOAgAfAAkJVRxUCgCOAgABLgAECgkJNAAQAE8iAA==.',
Ep='Epictool:BAAALgAECggJCwAAAA==.',
Et='Ethereal:BAAALgAECgEJAQAAAA==.',
Ew='Ew:BAACLgAFFH8IAAIXAAMJXBKcJQCgAAAXAAMJXBKcJQCgAAAuAAQKfxQAAhcABwlLHWwmACACABcABwlLHWwmACACAAEuAAUUAgkJAAgA0x4A.',
Ex='Extrathick:BAAALgAECgMJAwAAAA==.',
Fa='Fabel:BAEBLgAECn80AAIQAAgJTyJeBwBoAgAQAAgJTyJeBwBoAgAAAA==.Falahad:BAAALgAECgEJAQABLgAFFAMJDwADAD4OAA==.Faltree:BAACLgAFFH8PAAMDAAMJPg7XMwCxAAADAAMJPg7XMwCxAAAdAAIJuhVnUgB6AAAuAAQKfyEABB0ACQkeFf5TAFcBAB0ACAkrFP5TAFcBAAMACAkOF0wyAFEBACAAAQnfAUo6AB8AAAAA.Fathershale:BAAALgAECgUJCAAAAA==.',
Fi='Firelord:BAAALgADCgEJAQAAAA==.Fistingmilk:BAAALgADCgUJBgABLgAECgUJDgAaAAAAAA==.',
Fo='Foulcor:BAABLgAECn8dAAMcAAkJ7B6LFwBNAgAcAAgJlB6LFwBNAgAMAAcJRhEwmQBDAQAAAA==.',
Fr='Freakadeek:BAABLgAECn8VAAQhAAkJaw1DIQDEAAAIAAUJ0Aid1wDeAAAhAAMJnhdDIQDEAAAJAAYJgwTWTgBXAAAAAA==.Freâkadeek:BAAALgAECgIJBQABLgAECgkJFQAhAGsNAA==.Freäk:BAAALgADCgMJAwABLgAECgkJFQAhAGsNAA==.Frieren:BAABLgAECn8+AAIBAAkJsBY3PwAfAgABAAkJsBY3PwAfAgAAAA==.Frink:BAAALgAECgEJAQABLgAECgkJPQAiAOEkAA==.Frostlord:BAAALgAECgIJAgAAAA==.',
Fu='Fundetected:BAAALgAFFAIJAgABLgAFFAMJBgAGADgNAA==.Furyofthenug:BAAALgAECgQJBAAAAA==.Fuzzywuzzy:BAAALgAECgUJBQABLgAECgYJHQASALgdAA==.',
Ga='Gabbyo:BAABLgAECn8lAAIdAAkJ/Ad2VAA+AQAdAAkJ/Ad2VAA+AQAAAA==.Galadorn:BAABLgAECn8mAAIGAAkJWiC/DwDFAgAGAAkJWiC/DwDFAgAAAA==.Gallgamesh:BAAALgADCgIJAgAAAA==.Garfall:BAAALgAECgcJDgAAAA==.Garga:BAAALgADCgMJBAABLgAECgQJBAAaAAAAAA==.',
Ge='Geirvaldr:BAAALgAECgYJBgAAAA==.Gerdash:BAAALgAECgMJBAAAAA==.Gerred:BAACLgAFFH8IAAIOAAMJPRj0IwDfAAAOAAMJPRj0IwDfAAAuAAQKfx8AAw4ACAnNGn8NABACAA4ACAk1Gn8NABACAA0ABAlFFB5mAMQAAAAA.',
Gh='Ghallow:BAABLgAECn8fAAIPAAgJHRwuAQB+AQAPAAgJHRwuAQB+AQAAAA==.Ghosty:BAACLgAFFH8JAAIjAAQJOxWRIAAhAQAjAAQJOxWRIAAhAQAuAAQKfyoAAiMABwlQIFgUAP8BACMABwlQIFgUAP8BAAAA.',
Gi='Gimp:BAAALgAECgEJAgAAAA==.',
Gl='Gladur:BAABLgAFFH8GAAMHAAYJyAzzHwDZAAAHAAUJtwzzHwDZAAAUAAEJmQGAZQAxAAABLgAFFAcJHgABAE0YAA==.',
Go='Goldenflame:BAAALgAECgUJBwAAAA==.Goldenlily:BAAALgAECgYJEgAAAA==.Goldenmunc:BAABLgAECn8tAAIBAAkJNxfsNQBBAgABAAkJNxfsNQBBAgAAAA==.Goldenone:BAAALgAECgQJBQAAAA==.Goldenpants:BAABLgAECn8nAAINAAkJjxM8IgDgAQANAAkJjxM8IgDgAQAAAA==.',
Gr='Grievous:BAABLgAECn89AAITAAkJOyW4AABKAwATAAkJOyW4AABKAwAAAA==.',
['Gû']='Gûrth:BAAALgADCgcJBwAAAA==.',
Ha='Hailmary:BAABLgAECn8oAAILAAkJEiV8AQCoAwALAAkJEiV8AQCoAwAAAA==.Halcrux:BAAALgAECgIJAgAAAA==.Halvard:BAAALgADCgMJBQAAAA==.Harusen:BAABLgAECn8cAAIkAAkJFR9EAgCmAgAkAAkJFR9EAgCmAgAAAA==.Havgnwltrav:BAAALgADCgcJBgAAAA==.',
He='Healaga:BAAALgAECgYJBgABLgAECgkJNQAIAMMaAA==.',
Hh='Hhoonnzz:BAABLgAFFH8KAAIjAAMJChP5EACYAAAjAAMJChP5EACYAAABLgAFFAIJCQAIANMeAA==.',
Hi='Hildalsind:BAAALgADCgkJCQABLgAFFAMJCQABAIMdAA==.',
Ho='Homestar:BAAALgADCgEJAQAAAA==.Hooll:BAAALgAECgIJAgAAAA==.Hornreaper:BAABLgAECn8bAAIVAAYJ5hfvJACVAQAVAAYJ5hfvJACVAQAAAA==.Hotshot:BAAALgAECgMJAwAAAA==.',
Hu='Hubbabubbajr:BAAALgAECgMJAwABLgAECgkJMwAdAIIbAA==.Hubert:BAAALgADCgEJAgAAAA==.Huracan:BAAALgAECgEJAgAAAA==.Hurin:BAAALgAECgcJDgAAAA==.Huur:BAAALgAECgEJAQABLgAECgEJAQAaAAAAAA==.',
Hy='Hyetta:BAAALgAECgQJBgABLgAECgkJHAAkABUfAA==.Hyir:BAAALgADCgYJBwABLgAFFAQJHgAHAOEfAA==.',
Il='Ilavengu:BAAALgAECgMJBQABLgAFFAQJFgAbADEmAA==.Illiya:BAABLgAECn8VAAILAAYJ+AsxRADZAAALAAYJ+AsxRADZAAAAAA==.',
Ir='Irôn:BAAALgAECgEJAQAAAA==.',
Iu='Iutara:BAAALgAECgYJDAAAAA==.',
Ja='Jaalein:BAAALgADCgcJDgAAAA==.Jayonor:BAABLgAECn80AAQRAAkJthVkGgAOAgARAAkJthVkGgAOAgAPAAYJ9we4GgAeAQAbAAcJ5AZmcQAIAQAAAA==.',
Je='Jek:BAAALgAECgYJBgAAAA==.',
Jo='Joryu:BAAALgADCgIJAwAAAA==.',
Ju='Juicycucci:BAAALgAECgcJEgABLgAFFAMJBgAGADgNAA==.',
Ka='Kaevrielle:BAECLgAFFH8IAAITAAMJfBXUCADGAAATAAMJfBXUCADGAAAuAAQKfx4AAxMACQmOG2IHAAwCABMACQmOG2IHAAwCACUAAQlWCol4ACcAAAAA.Kaison:BAABLgAECn8XAAMeAAkJEQigMQBVAQAeAAkJEQigMQBVAQAmAAcJBAtMNQBAAQABLgAECgkJIAAGAA0VAA==.Kaladîn:BAAALgAECgMJAwABLgAFFAcJHgABAE0YAA==.Kalii:BAAALgADCgQJBAAAAA==.Kamel:BAAALgADCgcJDQAAAA==.Kardin:BAAALgADCgEJAQAAAA==.Karwin:BAABLgAECn8bAAIBAAgJ/xRCaACsAQABAAgJ/xRCaACsAQAAAA==.Katakuri:BAAALgAECgEJAgAAAA==.',
Ke='Keeper:BAAALgAFFAEJAQABLgAFFAUJDQAMAJsiAA==.Keeperodark:BAABLgAECn8YAAIEAAgJKxfxAwBrAQAEAAgJKxfxAwBrAQABLgAFFAUJDQAMAJsiAA==.Keeperolight:BAACLgAFFH8NAAIMAAUJmyLDCwAzAQAMAAUJmyLDCwAzAQAuAAQKf1MAAwwACQlUJeYEAFADAAwACQlUJeYEAFADABwAAQmBGBSQAEAAAAAA.Kemanorel:BAAALgADCgcJDgABLgAECgkJJwAeAK0TAA==.',
Ki='Kianth:BAAALgADCgkJEgAAAA==.Killkat:BAABLgAECn8uAAIBAAkJgxhiNQBDAgABAAkJgxhiNQBDAgAAAA==.',
Ko='Kodera:BAABLgAECn8dAAMSAAYJuB3ZDQDyAQASAAYJuB3ZDQDyAQAWAAQJwhzKDgAfAQAAAA==.Koojo:BAAALgAECgcJCAAAAA==.Kosma:BAAALgAECgYJBgAAAA==.Kovae:BAAALgADCgEJAQAAAA==.',
Kr='Kraken:BAAALgADCgUJBQAAAA==.',
Ku='Kusheddruid:BAAALgADCgMJBQAAAA==.',
Ky='Kyaritin:BAAALgAECgMJAwABLgAECgYJCgAaAAAAAA==.Kyokei:BAAALgAECgEJAQAAAA==.',
La='Laiho:BAAALgADCgUJCAAAAA==.Lans:BAABLgAECn8UAAQnAAkJIQ0hDQD4AAAnAAUJ2AkhDQD4AAABAAQJ1Q80zAD3AAAoAAQJAwkBCQDKAAAAAA==.Larew:BAACLgAFFH8FAAIMAAMJbgfXfgC4AAAMAAMJbgfXfgC4AAAuAAQKfy8AAgwACQnfGfMnAGQCAAwACQnfGfMnAGQCAAAA.Lazytemplar:BAAALgADCgMJAwABLgAFFAIJAgAaAAAAAA==.',
Le='Lealla:BAABLgAECn89AAIDAAkJlCI8BQAIAwADAAkJlCI8BQAIAwAAAA==.Lechevalier:BAAALgAFFAIJAwABLgAFFAMJBgAGADgNAA==.Leodin:BAAALgAECgEJAgAAAA==.Leorus:BAAALgAECgIJAgAAAA==.Lethhunt:BAACLgAFFH8YAAMYAAgJNgs+EABdAQAYAAgJlQk+EABdAQAXAAIJWw4MGgCeAAAuAAQKfy4AAxgACQncHpwGACgCABgACQlgHpwGACgCABcAAgk+JFKHANIAAAAA.',
Li='Lilmistfox:BAAALgAECgUJBwABLgAFFAQJFgAbADEmAA==.Lioh:BAAALgAECgQJBAAAAA==.Lizardgang:BAABLgAECn8UAAIXAAYJ0xiXewBIAQAXAAYJ0xiXewBIAQAAAA==.',
Lo='Loganshu:BAAALgAECgkJDgAAAA==.Lokan:BAACLgAFFH8RAAMiAAMJWRkcHQDoAAAiAAMJWRkcHQDoAAAXAAEJwgjlqABFAAAuAAQKfywAAyIACQlHHqkIAJQCACIACQlHHqkIAJQCABcAAQn+CiMyATYAAAAA.Lots:BAACLgAFFH8RAAIEAAMJhhtjZwD3AAAEAAMJhhtjZwD3AAAuAAQKfycAAwQACQktIgIrAC4CAAQACAliIgIrAC4CAAIABAngHkcsAA0BAAAA.',
Lu='Ludacast:BAAALgADCgIJAgAAAA==.Ludafists:BAAALgADCgcJDAAAAA==.Ludakris:BAABLgAECn8eAAIQAAkJfxhLCwATAgAQAAkJfxhLCwATAgAAAA==.Lumanoth:BAAALgAECgYJBgAAAA==.',
Ly='Lyna:BAABLgAECn8gAAIbAAkJpROdPwCvAQAbAAkJpROdPwCvAQAAAA==.Lynaya:BAAALgADCgIJAgAAAA==.',
['Lí']='Líonheart:BAABLgAECn8eAAMcAAcJYBePPgBKAQAcAAcJYBePPgBKAQAMAAYJFgvJ0wDuAAAAAA==.',
['Lî']='Lîghtless:BAACLgAFFH8PAAIBAAYJBhqgGABoAQABAAYJBhqgGABoAQAuAAQKfxcAAgEACAmfJUchAO4CAAEACAmfJUchAO4CAAAA.',
['Lú']='Lúckally:BAAALgADCgQJBAABLgAECgYJCgAaAAAAAA==.Lúckÿ:BAAALgAECgYJCgAAAA==.',
Ma='Magetheo:BAAALgADCgIJAgAAAA==.Magicpanda:BAAALgAECgUJCwAAAA==.Mahina:BAAALgAECgIJAgAAAA==.Malik:BAAALgADCgIJAgAAAA==.Marcille:BAABLgAECn8nAAIBAAgJ2RO7dwCKAQABAAgJ2RO7dwCKAQAAAA==.Masyledian:BAAALgAECgIJBAABLgAECgcJIgAIAHwZAA==.Mathor:BAAALgAECgEJAgAAAA==.Mavrbg:BAAALgAECgQJBQAAAA==.Mayhaps:BAABLgAECn9EAAMXAAkJFRuBJwBBAgAXAAkJFRuBJwBBAgAYAAEJZACpmgAYAAAAAA==.',
Mc='Mcbain:BAABLgAECn89AAIiAAkJ4STWAQA9AwAiAAkJ4STWAQA9AwAAAA==.',
Me='Melinia:BAAALgAECgEJAQABLgAECgEJAgAaAAAAAA==.Melrine:BAAALgADCgMJAwAAAA==.Mentaltitty:BAABLgAECn8gAAIBAAkJgxKGSwD5AQABAAkJgxKGSwD5AQAAAA==.Meret:BAAALgADCgMJBQAAAA==.',
Mi='Minerwor:BAAALgAECgYJCgAAAA==.Mirrayla:BAAALgADCgYJBgAAAA==.Misty:BAAALgADCgYJBgAAAA==.',
Mm='Mmisty:BAABLgAECn9IAAIDAAkJghmMDwBnAgADAAkJghmMDwBnAgAAAA==.',
Mo='Moarthretplz:BAAALgAECgUJCQABLgAFFAQJFgAbADEmAA==.Mohji:BAAALgAFFAEJAQABLgAFFAcJGgAmAOwUAA==.Moldynuggets:BAAALgAECgYJDQAAAA==.Momometaru:BAABLgAECn8kAAQEAAkJgRaCQQDYAQAEAAkJfhOCQQDYAQACAAUJNhRyJgAsAQAFAAMJzxrGJgCMAAAAAA==.Monsterbee:BAABLgAECn9MAAIEAAkJ1BXiKwAqAgAEAAkJ1BXiKwAqAgAAAA==.',
Mu='Mustypizza:BAABLgAECn8uAAICAAkJihjJBAAsAgACAAkJihjJBAAsAgAAAA==.',
Mx='Mxicancowboy:BAAALgADCgEJAgAAAA==.',
My='Mystery:BAABLgAECn89AAMSAAkJNiC9AgAzAwASAAkJNiC9AgAzAwAWAAUJXhELEAAKAQAAAA==.',
['Mê']='Mêøwzêr:BAAALgAECggJEwAAAA==.',
['Mÿ']='Mÿst:BAAALgAECgMJBAAAAA==.',
Na='Nak:BAAALgAECgYJBgAAAA==.Narashi:BAAALgAECgQJCAAAAA==.Naril:BAAALgADCgUJBQAAAA==.Nats:BAABLgAECn8pAAIbAAgJSxGrCQDQAAAbAAgJSxGrCQDQAAAAAA==.',
Ne='Neameny:BAABLgAECn89AAIXAAkJGBObOwDxAQAXAAkJGBObOwDxAQAAAA==.',
Ni='Nianji:BAAALgADCgYJDgAAAA==.Nightstar:BAAALgADCgMJAwAAAA==.Nightworld:BAAALgADCgcJDgAAAA==.',
No='Noctum:BAAALgAECgcJBwAAAA==.Nordicpally:BAAALgADCgQJBAAAAA==.Notbomba:BAAALgAECgEJAwAAAA==.Notgim:BAAALgADCggJCAAAAA==.',
Nu='Nualrossan:BAAALgADCgYJCAAAAA==.Nubrac:BAAALgAECgkJEwAAAA==.',
Ny='Nylux:BAAALgAECgYJDwAAAA==.',
Ob='Oblivion:BAACLgAFFH8IAAIEAAQJIRhjGgDKAAAEAAQJIRhjGgDKAAAuAAQKfz4AAwQACQmfJLUGACUDAAQACQmfJLUGACUDAAIAAQkAAFFdAFcAAAAA.',
Og='Ogrebreath:BAAALgAECgUJBwAAAA==.',
Oo='Oostren:BAAALgAECgEJAgAAAA==.',
Or='Orsyp:BAAALgADCgkJGgAAAA==.',
Pa='Palockie:BAAALgADCgEJAQAAAA==.Pandas:BAABLgAECn8hAAIRAAkJAhF6JwCxAQARAAkJAhF6JwCxAQAAAA==.Partyrocker:BAABLgAECn8XAAIiAAcJag79KgBKAQAiAAcJag79KgBKAQABLgAECgkJFQAhAGsNAA==.Paynë:BAAALgAECgYJDAAAAA==.',
Pi='Pixae:BAACLgAFFH8PAAISAAMJjwdDIwCHAAASAAMJjwdDIwCHAAAuAAQKfyEAAhIACAm5Cm8ZAD8BABIACAm5Cm8ZAD8BAAAA.Pixiechaos:BAAALgAECgQJCAAAAA==.',
Po='Poliahu:BAABLgAECn8ZAAIXAAcJKwxSlAAXAQAXAAcJKwxSlAAXAQAAAA==.Porthoss:BAAALgADCggJDwAAAA==.Powerplant:BAACLgAFFH8ZAAIXAAgJViDRDQD6AQAXAAgJViDRDQD6AQAuAAQKfyYAAhcACQkgJCgIAA4DABcACQkgJCgIAA4DAAAA.Poyoram:BAAALgADCgEJAQAAAA==.',
Pr='Pryi:BAAALgADCgcJBwABLgAFFAMJBwAMAO0IAA==.',
Py='Pyralys:BAABLgAECn85AAMLAAkJGBFmHADjAQALAAkJGBFmHADjAQAeAAMJqQJBiAAxAAAAAA==.',
['Pä']='Pärts:BAAALgAECgUJBQABLgAFFAYJCwAiAEITAA==.',
Qu='Quizac:BAAALgADCgMJBQAAAA==.',
Ra='Rabidghost:BAAALgADCgYJBgAAAA==.Ragemonk:BAAALgAECgUJDgABLgAFFAIJAgAaAAAAAA==.Ragetality:BAAALgAFFAIJAgAAAA==.Rahken:BAAALgADCgQJBAAAAA==.Rakthera:BAAALgADCgcJBwAAAA==.Rallaster:BAAALgAECgYJBgABLgAECgkJJwAeAK0TAA==.Ramaria:BAAALgADCgkJCQABLgAECgkJJgAGAFogAA==.Raserei:BAABLgAFFH8JAAINAAMJIhf2LwDwAAANAAMJIhf2LwDwAAAAAA==.Rasputain:BAAALgADCgYJCgAAAA==.Rasputein:BAAALgADCgcJBwAAAA==.Rattelyr:BAAALgAECgYJDgAAAA==.Ravara:BAAALgADCgYJBgABLgAECgkJJgAGAFogAA==.Rawb:BAACLgAFFH8KAAINAAMJjxTzMwDhAAANAAMJjxTzMwDhAAAuAAQKfx8AAw0ACAmyG74YACgCAA0ACAmyG74YACgCAAoABglmFr0uAM0AAAEuAAUUAgkJAAgA0x4A.Razgaurd:BAAALgAECgMJAwAAAA==.',
Re='Recolada:BAAALgAECggJCAAAAA==.Regice:BAAALgAECgcJBwABLgAFFAQJEgAJAJYaAA==.Regicee:BAACLgAFFH8SAAMJAAQJlhrLBQA4AQAJAAQJlhrLBQA4AQAIAAEJGwlZawA8AAAuAAQKf04AAwkACQn8Il0EAO8CAAkACQn8Il0EAO8CAAgABQlnEwr+AK8AAAAA.Retam:BAAALgAECgcJDgAAAA==.Revakos:BAAALgADCgMJAwAAAA==.',
Rh='Rhysandra:BAAALgAECgQJCQAAAA==.',
Ri='Ribble:BAAALgADCgMJAwAAAA==.Riffraff:BAAALgAECgcJBAAAAA==.Rindou:BAAALgAECgkJBAAAAA==.Ripcord:BAAALgAECgUJDQAAAA==.Ripem:BAAALgADCgYJBgAAAA==.Ripperoni:BAAALgAECgcJDQAAAA==.Rizek:BAAALgAECgUJBgABLgAECgcJHQAUADkPAA==.Rizzx:BAAALgAECgEJAQAAAA==.',
Ro='Rockdyou:BAABLgAECn8nAAIIAAkJ+R51JABzAgAIAAkJ+R51JABzAgAAAA==.Roglef:BAAALgAECgQJCQAAAA==.Rogmesh:BAAALgAECgUJBQAAAA==.Rotlobster:BAABLgAECn8aAAIFAAkJAB71AQDEAgAFAAkJAB71AQDEAgAAAA==.Roxxy:BAAALgAECgQJBAAAAA==.',
Ru='Rundvelt:BAACLgAFFH8RAAIQAAMJeA0IDwCQAAAQAAMJeA0IDwCQAAAuAAQKfyQAAhAACQlSEQwVAIABABAACQlSEQwVAIABAAAA.',
Sa='Sage:BAAALgADCgcJCAAAAA==.Sandwich:BAAALgAECgcJCAAAAA==.Saphíra:BAAALgAFFAIJAQABLgAFFAcJHgABAE0YAA==.Sapkick:BAAALgAECgQJBwAAAA==.',
Se='Serdragon:BAAALgADCgQJBAAAAA==.Sertian:BAAALgAECgEJAQAAAA==.Servoid:BAAALgAECgUJCQAAAA==.',
Sh='Shando:BAAALgAECgEJAQAAAA==.Shiftstyle:BAEALgAECgEJAQAAAA==.Shtanky:BAACLgAFFH8PAAIKAAMJaBFHHgClAAAKAAMJaBFHHgClAAAuAAQKfyQAAgoACQnHD7MWAI4BAAoACQnHD7MWAI4BAAAA.',
Si='Silentsocks:BAAALgAECgUJDAAAAA==.Sixsixsix:BAAALgAECgcJCgABLgAFFAIJCQAIANMeAA==.',
Sk='Skoogz:BAABLgAECn8UAAMJAAYJbBRZJgAhAQAJAAYJCBRZJgAhAQAIAAQJ5A+a1QDhAAAAAA==.',
Sm='Smackdowne:BAAALgADCgIJAgAAAA==.',
So='Soggyy:BAAALgADCgYJCwAAAA==.Solar:BAABLgAECn8VAAQHAAcJyRkxLwBtAQAHAAYJCxYxLwBtAQAfAAYJrhzoOABmAQAUAAEJUwL71wAaAAAAAA==.Soulfulgingr:BAABLgAECn8aAAIRAAcJmgqdTgD8AAARAAcJmgqdTgD8AAAAAA==.',
St='Starlagosa:BAAALgADCgYJCQAAAA==.Sturm:BAAALgAECgMJAwAAAA==.Styx:BAAALgAECgMJAwAAAA==.',
Su='Sunbake:BAABLgAECn8XAAMLAAYJIQdqBwCRAAALAAYJIQdqBwCRAAAeAAEJ5gYqkAAqAAAAAA==.',
Sw='Sweetbbyraze:BAACLgAFFH8dAAMWAAYJvxyoBQAIAQAVAAYJeRmaIQBTAQAWAAQJQCGoBQAIAQAuAAQKfyYAAxYACAkpIVIGAJACABYABwm8IVIGAJACABUAAwnyHI9rAJkAAAAA.',
Sy='Sylaena:BAABLgAECn8oAAIYAAgJVQoeFAAgAQAYAAgJVQoeFAAgAQAAAA==.Sylvrstorm:BAAALgAECgcJDQAAAA==.',
['Së']='Sërënity:BAABLgAECn8XAAIdAAUJjg4qBwCqAAAdAAUJjg4qBwCqAAAAAA==.',
['Sí']='Sín:BAAALgAECgcJDAABLgAFFAIJCQAIANMeAA==.',
Ta='Talipally:BAACLgAFFH8HAAIMAAMJ7QjMewC+AAAMAAMJ7QjMewC+AAAuAAQKfxwAAgwACQkyEM14AH0BAAwACQkyEM14AH0BAAAA.Talishammy:BAAALgAECgMJAwABLgAFFAMJBwAMAO0IAA==.Taliwhacker:BAAALgAFFAEJAQABLgAFFAMJBwAMAO0IAA==.Talonleafgrd:BAAALgAECgkJCgAAAA==.Tanaka:BAABLgAECn8gAAIIAAgJgBMJWgC4AQAIAAgJgBMJWgC4AQAAAA==.Tanisong:BAAALgAECgQJDQAAAA==.Tassadar:BAAALgAECgUJCAAAAA==.',
Te='Teldo:BAAALgADCgMJBQAAAA==.Tepeyollotl:BAAALgADCgEJAQAAAA==.Terayus:BAAALgADCgcJDAAAAA==.Teyliah:BAAALgADCgMJAwAAAA==.',
Tf='Tf:BAAALgAECgYJBgABLgAFFAIJCQAIANMeAA==.',
Th='Thalor:BAAALgAECgUJBQABLgAFFAQJBgAKAPMHAA==.Thekingpunch:BAABLgAECn9JAAMUAAkJoiO5BwAhAwAUAAkJoiO5BwAhAwAHAAEJahZWjwBCAAAAAA==.Thenle:BAAALgADCggJDgAAAA==.Thline:BAAALgADCgMJBQAAAA==.Thunderblitz:BAABLgAECn8rAAIcAAkJdgknMwCIAQAcAAkJdgknMwCIAQAAAA==.Thurmus:BAAALgADCgkJQAAAAA==.Thánatos:BAAALgADCgMJAwAAAA==.',
Ti='Tillwar:BAABLgAECn87AAINAAkJKh2pEAByAgANAAkJKh2pEAByAgAAAA==.Tinymonk:BAAALgAECgMJAwAAAA==.',
To='Tofu:BAACLgAFFH8JAAIIAAMJ5Bx6hwD6AAAIAAMJ5Bx6hwD6AAAuAAQKf0QAAwgACQlIHvEVAMQCAAgACQlIHvEVAMQCAAkABwmjFrwaAIgBAAAA.Tokanya:BAAALgAECgEJAQAAAA==.Tortillachip:BAAALgAECgEJAgAAAA==.Toxidot:BAAALgAECgEJAQAAAA==.',
Tr='Treibh:BAABLgAECn8qAAIdAAkJCxilFwCJAgAdAAkJCxilFwCJAgAAAA==.Trelephant:BAAALgAECgMJBQAAAA==.Trulydps:BAABLgAECn8vAAIXAAkJ4hQKLwAgAgAXAAkJ4hQKLwAgAgAAAA==.Trulyog:BAAALgAECgQJBAABLgAECgkJLwAXAOIUAA==.',
Tu='Tubbsmcgee:BAACLgAFFH8eAAIbAAYJ6x8cCABFAgAbAAYJ6x8cCABFAgAuAAQKfyUAAhsACQkrJLgHAPkCABsACQkrJLgHAPkCAAEuAAUUBgkeABsA6x8A.Tukkit:BAAALgAECgYJDgAAAA==.',
Tw='Twistedshot:BAAALgADCggJCAAAAA==.Twizzler:BAABLgAECn9TAAIBAAkJZQi/fgB6AQABAAkJZQi/fgB6AQAAAA==.',
Ty='Tyraniik:BAAALgADCgYJCAAAAA==.',
['Të']='Tërris:BAABLgAECn8cAAIJAAkJQBHkGgCGAQAJAAkJQBHkGgCGAQAAAA==.',
['Tî']='Tîlldeath:BAAALgAECgUJBwAAAA==.',
['Tõ']='Tõaster:BAAALgADCgQJBAABLgAECgkJJgAGAFogAA==.',
Uj='Uji:BAAALgADCgEJAQAAAA==.',
Ur='Urowndad:BAAALgAECgUJBQABLgAECggJFgAMAL0TAA==.Urownmother:BAAALgADCgUJBQABLgAECggJFgAMAL0TAA==.',
Va='Vaellian:BAAALgAECgYJDAAAAA==.Vallez:BAECLgAFFH8VAAMcAAMJoh/GIwACAQAcAAMJoh/GIwACAQAMAAMJ/g1fcwDMAAAuAAQKfyoAAxwACQmqHQMSAIMCABwACQmqHQMSAIMCAAwAAwmiDWpGAWYAAAAA.Vanillaghost:BAAALgADCgIJAQAAAA==.Varnusshadow:BAAALgAECgUJBgAAAA==.',
Ve='Vearik:BAAALgAECgUJBwAAAA==.Velladoree:BAABLgAECn8mAAIUAAgJlAsvCgDTAAAUAAgJlAsvCgDTAAAAAA==.Vendaryn:BAAALgADCggJCAAAAA==.Vexahlia:BAAALgADCgMJAwAAAA==.',
Vg='Vgurlpally:BAAALgADCgYJBgAAAA==.',
Vy='Vynlorlan:BAAALgADCgMJAwABLgAECgMJBAAaAAAAAA==.',
Wa='Walkindead:BAAALgAECgQJBgAAAA==.Waveygravee:BAAALgAECgIJAwAAAA==.Wavyghoul:BAAALgAECgEJAQAAAA==.Wavygraivy:BAABLgAECn8eAAIbAAcJihQXTACAAQAbAAcJihQXTACAAQAAAA==.Wavygravey:BAAALgADCgQJBAAAAA==.',
We='Wedragon:BAABLgAECn8UAAMUAAYJ+RNkBwAVAQAUAAYJ+RNkBwAVAQAHAAMJygdFbgB1AAAAAA==.',
Wh='Wheelchair:BAACLgAFFH8LAAIIAAQJOxv7bwAeAQAIAAQJOxv7bwAeAQAuAAQKfxwAAggACAkSJF0SAA4DAAgACAkSJF0SAA4DAAAA.',
Wo='Woofwoof:BAAALgAFFAIJAgAAAA==.',
Wu='Wullemage:BAAALgADCgcJEwABLgAFFAcJHwAjALAaAA==.',
['Wå']='Wåsp:BAABLgAECn9PAAIGAAkJAxAHUACVAQAGAAkJAxAHUACVAQAAAA==.',
Xb='Xb:BAAALgAECgcJBQAAAA==.',
Xh='Xhexana:BAABLgAECn84AAIbAAkJTRcBHQBkAgAbAAkJTRcBHQBkAgABLgAECgkJPQAXABgTAA==.',
Xi='Xiaopo:BAAALgAECgEJAQABLgAFFAQJFgAbADEmAA==.',
Xr='Xrael:BAAALgAECgEJAQABLgAFFAMJEwAHACMiAA==.Xrayl:BAACLgAFFH8TAAMHAAMJIyKYEwAgAQAHAAMJIyKYEwAgAQAfAAMJxAxDOwC5AAAuAAQKfyUAAwcACQnoIMwNAGkCAAcACAmrIcwNAGkCAB8AAQmOG/N9AE8AAAAA.',
Xz='Xzerocool:BAABLgAECn8WAAQMAAgJvRNCiQBeAQAMAAgJvRNCiQBeAQAQAAIJshNmPABqAAAcAAEJmQOznQAiAAAAAA==.',
Ya='Yaniaa:BAAALgADCgcJBwAAAA==.Yannii:BAAALgADCgcJDgAAAA==.',
Ye='Yenko:BAAALgADCgIJAgAAAA==.',
Yo='Yolo:BAAALgADCgcJCwAAAA==.Yoshikazu:BAAALgAECgcJCgAAAA==.Yoyoboy:BAAALgAECgEJAgAAAA==.',
Za='Zaarah:BAAALgAECgYJDAAAAA==.',
Ze='Zellek:BAAALgADCgEJAQAAAA==.Zendezoth:BAABLgAECn8jAAIWAAkJpRmcAwBZAgAWAAkJpRmcAwBZAgAAAA==.Zephik:BAAALgADCgEJAQAAAA==.Zerofrost:BAABLgAECn8uAAIBAAkJsBl0PAAoAgABAAkJsBl0PAAoAgAAAA==.Zerrìc:BAAALgAECgYJDQAAAA==.Zevra:BAAALgADCgMJAwAAAA==.',
Zh='Zhiva:BAABLgAECn82AAIDAAkJ1Q6VNQBBAQADAAkJ1Q6VNQBBAQAAAA==.',
Zu='Zul:BAACLgAFFH8ZAAIjAAMJXiOfIgAQAQAjAAMJXiOfIgAQAQAuAAQKfzMAAyMACQkwI+oHAKkCACMACQkwI+oHAKkCACkAAQnLAkMiACQAAAAA.',
Zy='Zykoz:BAABLgAECn8uAAIjAAkJpCGMBADzAgAjAAkJpCGMBADzAgAAAA==.',
['Ða']='Ðamned:BAABLgAECn8YAAIRAAYJ8hvELgCnAQARAAYJ8hvELgCnAQABLgAFFAIJCQAIANMeAA==.',
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
