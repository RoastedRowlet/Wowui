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

local lookup = {'Mage-Frost','Warlock-Destruction','Druid-Balance','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Priest-Holy','Paladin-Retribution','Paladin-Holy','Warrior-Arms','Warrior-Fury','Shaman-Enhancement','Paladin-Protection','Shaman-Elemental','Evoker-Preservation','Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Vengeance','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Shaman-Restoration','Druid-Restoration','Priest-Shadow','Monk-Brewmaster','Druid-Feral','DeathKnight-Frost','Hunter-Survival','Rogue-Outlaw','DemonHunter-Havoc','Priest-Discipline','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=46,date='2026-08-25',data={Ab='Abomination:BAAALgADCgMJAwAAAA==.',
Ad='Addruid:BAAALgAECgEJAQAAAA==.Adune:BAAALgAECgQJBQAAAA==.',
Ae='Aeidail:BAACLgAFFH8jAAIBAAkJHRdJJwDaAQABAAkJHRdJJwDaAQAuAAQKfy8AAgEACQnlI0McAAUDAAEACQnlI0McAAUDAAAA.Aelaria:BAAALgADCgMJAwAAAA==.Aeviria:BAABLgAECn8oAAICAAgJtRVxCADGAQACAAgJtRVxCADGAQAAAA==.',
Ag='Agraceful:BAACLgAFFH8OAAIDAAMJEAffNwCeAAADAAMJEAffNwCeAAAuAAQKfx8AAgMACQm8EjkfAM4BAAMACQm8EjkfAM4BAAAA.',
Ai='Ailee:BAAALgAECgYJDAAAAA==.Aios:BAAALgAECgIJAgAAAA==.Aiza:BAACLgAFFH8QAAIEAAMJfgyeOACqAAAEAAMJfgyeOACqAAAuAAQKfzgAAwQACQmXGb8dAHICAAQACQmXGb8dAHICAAUAAQkAAA1JAAAAAAAA.',
Al='Alaber:BAAALgAECgUJCAAAAA==.Aldanil:BAAALgADCgMJAwAAAA==.Allarria:BAAALgADCgYJBwABLgAECgkJJgAGAFogAA==.',
Am='Ampersand:BAAALgAECgMJCQAAAA==.',
An='Angrypants:BAAALgADCgUJBQAAAA==.Animalfriend:BAAALgAECgYJDgAAAA==.Anklesmasher:BAABLgAECn8WAAIHAAgJcA4fPAAQAQAHAAgJcA4fPAAQAQAAAA==.Antisocial:BAACLgAFFH8JAAIEAAMJcg9IQgCQAAAEAAMJcg9IQgCQAAAuAAQKfxkAAgQABglwGsBpAJABAAQABglwGsBpAJABAAEuAAUUAgkJAAgA0x4A.Antonidus:BAAALgAECgYJEgAAAA==.Anyah:BAABLgAECn8dAAIDAAgJqgQKVAC/AAADAAgJqgQKVAC/AAAAAA==.',
Ap='Apolloo:BAAALgADCgMJAwAAAA==.',
Aq='Aquadora:BAAALgAECgEJAQAAAA==.',
Ar='Ardicon:BAAALgADCgMJAwAAAA==.Arfaz:BAABLgAECn8/AAMIAAkJ6RztBABUAgAIAAkJPhztBABUAgAJAAYJWAoXOQCvAAAAAA==.Armbrost:BAAALgAECgYJCgAAAA==.Arthemis:BAAALgAECgEJAgAAAA==.Artimås:BAAALgADCgcJCAAAAA==.Arwynne:BAAALgADCgMJAwAAAA==.Arçano:BAAALgAECgEJAQABLgAECgkJGQAKADkTAA==.',
As='Ascension:BAAALgADCgcJBgABLgAFFAQJCwAEAJ4ZAA==.Astrastar:BAABLgAECn8bAAMEAAYJ0wKg4wCVAAAEAAYJ0wKg4wCVAAACAAEJcgDDgAAOAAAAAA==.',
Au='Auralyn:BAAALgADCgMJBQAAAA==.',
Av='Avarin:BAAALgADCgEJAQAAAA==.',
Ay='Aymont:BAAALgAECgQJBQAAAA==.',
Ba='Baerd:BAABLgAECn8aAAILAAcJZhPqKwBqAQALAAcJZhPqKwBqAQAAAA==.Barlz:BAAALgAECgEJAQAAAA==.',
Be='Beanpaste:BAAALgAECgcJAQABLgAFFAMJEAAIAHcZAA==.Beanutbutter:BAAALgADCgIJAgABLgAFFAMJEAAIAHcZAA==.Beaty:BAAALgAECgIJAgAAAA==.Bebby:BAABLgAECn8mAAMJAAgJUwMHDQCkAAAJAAgJIgMHDQCkAAAIAAIJaQJVeAEwAAAAAA==.Belienn:BAAALgAECgEJAQAAAA==.Belonara:BAAALgAECgEJAQAAAA==.Belwolf:BAABLgAECn8VAAIIAAYJZAtn6ADKAAAIAAYJZAtn6ADKAAAAAA==.Bergstrom:BAABLgAECn80AAIMAAkJuhnAMAA+AgAMAAkJuhnAMAA+AgAAAA==.Bethanymarie:BAAALgAECgEJAQAAAA==.Betrayer:BAAALgADCgQJAwABLgAFFAQJCwAEAJ4ZAA==.',
Bi='Biancaneve:BAACLgAFFH8HAAILAAMJ9Q8kJACaAAALAAMJ9Q8kJACaAAAuAAQKfzYAAgsACQmeHTsBAOUCAAsACQmeHTsBAOUCAAAA.Bigbruisa:BAAALgAECgMJBgAAAA==.Bighero:BAACLgAFFH8QAAIGAAMJSQsEagC4AAAGAAMJSQsEagC4AAAuAAQKfyAAAgYACQk9EVlvAFYBAAYACQk9EVlvAFYBAAAA.Bigmike:BAAALgAECgEJAgAAAA==.',
Bl='Blackmelody:BAAALgAECgEJAQAAAA==.Blakkjezus:BAAALgAECgcJCwAAAA==.Blessednugie:BAABLgAECn8VAAMNAAcJuBiLCgAUAQANAAcJuBiLCgAUAQAMAAIJPA3DaQAqAAAAAA==.Blitzbolts:BAAALgAECgEJAgAAAA==.Bludo:BAACLgAFFH8UAAMOAAcJKxCAHQADAQAPAAUJHRX8IwAkAQAOAAQJ+wqAHQADAQAuAAQKfx4AAw8ACQl6IWgZAIACAA8ACAk5GWgZAIACAA4ABgl9HFMYADYBAAAA.',
Bo='Boe:BAABLgAECn8tAAIQAAkJgAr5EwB6AQAQAAkJgAr5EwB6AQAAAA==.Bomba:BAAALgAECgUJDQAAAA==.Bombacløt:BAABLgAECn80AAMEAAkJkxDwRQDJAQAEAAkJFRDwRQDJAQACAAcJbg6pFAAIAQAAAA==.Bowdirte:BAAALgAECgUJBwAAAA==.',
Br='Brastin:BAABLgAECn86AAIRAAkJkyJHAgASAwARAAkJkyJHAgASAwABLgAFFAcJFQASAD4LAA==.Brenell:BAACLgAFFH8IAAIBAAMJgRLhiwDBAAABAAMJgRLhiwDBAAAuAAQKfzsAAgEACQmwIX0RAPECAAEACQmwIX0RAPECAAAA.',
Bu='Bu:BAAALgAECgYJDQABLgAECgYJHQATALgdAA==.Bubblehearth:BAAALgAECgYJCQABLgAFFAMJBAAUAAAAAA==.Buhlitz:BAAALgAECgEJAgAAAA==.Butterbean:BAAALgADCgMJBQAAAA==.',
By='Bynis:BAABLgAECn8gAAIGAAkJDRVHSACtAQAGAAkJDRVHSACtAQAAAA==.',
Ca='Cabëla:BAAALgADCgUJBQAAAA==.Cactusjack:BAAALgADCgUJBQAAAA==.Cadorex:BAAALgADCgEJAQAAAA==.Caffeinefree:BAAALgADCggJBwAAAA==.Calacolinda:BAABLgAECn8ZAAMNAAcJkAtRCQAwAQANAAcJkAtRCQAwAQAMAAQJVQYUFAGhAAAAAA==.Calamari:BAAALgAECgEJAQAAAA==.Cavakworm:BAAALgADCgEJAQAAAA==.Caylin:BAAALgADCgUJBgAAAA==.Cayusedemon:BAAALgADCgEJAQAAAA==.Cayusemage:BAAALgADCgkJGAAAAA==.Cayusevoid:BAAALgADCgcJBwAAAA==.',
Ce='Celestiall:BAAALgAECgYJBwAAAA==.Ceridwyn:BAAALgAECgUJBgAAAA==.',
Ch='Chadalonius:BAAALgAECgUJBQABLgAFFAcJHwAVALAaAA==.Chariscrushr:BAAALgAECgQJCAABLgAFFAkJNAAHAMYbAA==.Cheesecurd:BAABLgAECn8cAAMVAAkJIhtgAQCCAgAVAAkJzRpgAQCCAgAWAAMJwhaxAwDSAAAAAA==.Chen:BAAALgADCgIJAgAAAA==.Choal:BAAALgAECgEJAQAAAA==.Chokaho:BAAALgAECgQJBgAAAA==.Chubberoni:BAAALgAECgUJBwAAAA==.',
Ci='Cinnamongirl:BAAALgAECgcJEgAAAA==.',
Co='Cora:BAAALgADCgEJAQAAAA==.Corahin:BAABLgAECn8bAAISAAYJGxASRAA5AQASAAYJGxASRAA5AQAAAA==.Corious:BAAALgAECgQJCQAAAA==.Cosmos:BAAALgAECgYJDQAAAA==.Cougarhunter:BAAALgAECgkJEAAAAA==.',
Cr='Crixux:BAAALgADCgYJAQAAAA==.Crokus:BAAALgADCggJCAAAAA==.',
Cu='Cuecumba:BAABLgAECn8uAAIXAAkJICZ2AABbAwAXAAkJICZ2AABbAwAAAA==.',
Da='Daemonerror:BAAALgAECgUJBQABLgAECgkJTgAYAKIjAA==.Dalren:BAACLgAFFH84AAMZAAkJJSAIAwDGAgAZAAkJJSAIAwDGAgAaAAMJUBNiBgBcAAAuAAQKf04AAxkACQniJf0BAGEDABkACQnIJf0BAGEDABoABwnLIUMMABcCAAAA.Dalryn:BAAALgAECgYJDQABLgAFFAkJOAAZACUgAA==.Dalvix:BAAALgADCgEJAQABLgAECgkJJgAGAFogAA==.Damballàh:BAAALgADCgIJAgAAAA==.Damocles:BAABLgAECn8YAAIBAAYJlwwqyAD9AAABAAYJlwwqyAD9AAAAAA==.Danazel:BAAALgADCgMJBQAAAA==.Dartagnan:BAACLgAFFH8QAAIbAAMJnhwUUQAIAQAbAAMJnhwUUQAIAQAuAAQKfygAAxsACQnLHTpJAMYBABsABwkLHzpJAMYBABwABgn3FI8bANEAAAAA.Darthmaul:BAABLgAECn8wAAIDAAkJyhHNHwDKAQADAAkJyhHNHwDKAQAAAA==.',
De='Deay:BAAALgADCgQJAQAAAA==.Delexa:BAAALgADCgkJQAAAAA==.Demonicnugie:BAAALgADCgEJAQAAAA==.Dendiian:BAABLgAECn8YAAIdAAkJqRIeJwAdAQAdAAkJqRIeJwAdAQAAAA==.',
Di='Didipullthat:BAAALgAECgcJEAABLgAFFAMJBAAUAAAAAA==.Diem:BAABLgAECn8dAAIbAAgJyw1rQQCqAQAbAAgJyw1rQQCqAQAAAA==.Dinendal:BAAALgADCgYJBgAAAA==.Dirtydotss:BAABLgAECn8VAAMFAAcJFwfXEgD/AAAFAAYJYQbXEgD/AAAEAAYJ5wSTzQC3AAAAAA==.Discernment:BAAALgAECgEJAQAAAA==.Divigitives:BAAALgAECgQJBAAAAA==.',
Do='Docrivan:BAAALgAECgYJCwAAAA==.Docsassist:BAAALgAECgMJAwABLgAECgYJCwAUAAAAAA==.Doregit:BAABLgAECn83AAIPAAkJIx/LCwCrAgAPAAkJIx/LCwCrAgAAAA==.Doros:BAAALgADCgYJCwAAAA==.Dowedoes:BAABLgAECn89AAIMAAkJgheVNgAnAgAMAAkJgheVNgAnAgAAAA==.',
Dr='Drachula:BAABLgAECn8cAAIeAAgJ4BSlOwDAAQAeAAgJ4BSlOwDAAQAAAA==.Dracultra:BAAALgAECgUJBwABLgAFFAMJBQANAJokAA==.Drakcheese:BAAALgADCgUJBQAAAA==.Dreolan:BAABLgAECn9nAAIfAAkJVB2ZAQDUAgAfAAkJVB2ZAQDUAgAAAA==.Drnatemonk:BAABLgAFFH8OAAIYAAYJSg7tEwBHAQAYAAYJSg7tEwBHAQABLgAFFAcJMgAIAA0jAA==.Drynnai:BAAALgADCgEJAgAAAA==.Dràúgr:BAAALgADCgMJAwABLgAECgYJCgAUAAAAAA==.',
Dy='Dyala:BAACLgAFFH8QAAMfAAMJjg8URACjAAAfAAMJjg8URACjAAADAAMJMwSSOgCOAAAuAAQKfyMAAx8ACQkDErNmAAABAB8ACQkDErNmAAABAAMABAkoDt5OANEAAAAA.',
['Dé']='Déathlyhèals:BAAALgAECgQJBAAAAA==.',
['Dö']='Dönövan:BAABLgAECn8zAAIMAAkJAhX9RQD0AQAMAAkJAhX9RQD0AQAAAA==.',
Eg='Eggyolk:BAABLgAECn8fAAIdAAkJHBZkAgABAgAdAAkJHBZkAgABAgAAAA==.',
El='Elapst:BAAALgAECgIJAgAAAA==.Elastwo:BAAALgAECgEJAQABLgAECgIJAgAUAAAAAA==.Eloise:BAABLgAECn8aAAILAAgJMw+dLQBgAQALAAgJMw+dLQBgAQAAAA==.Elvenbane:BAABLgAECn8nAAIgAAkJrRO3HADfAQAgAAkJrRO3HADfAQAAAA==.',
Em='Emily:BAAALgAECgYJDAAAAA==.Emry:BAAALgADCgYJBgABLgAECgcJHQAYADkPAA==.',
En='Enable:BAEBLgAECn8gAAIhAAkJVRxUCgCOAgAhAAkJVRxUCgCOAgABLgAECgkJNAARAE8iAA==.',
Ep='Epictool:BAAALgAECggJCwAAAA==.',
Et='Ethereal:BAAALgAECgEJAQAAAA==.Etö:BAAALgAECgUJCAABLgAECgQJBgAUAAAAAA==.',
Ew='Ew:BAACLgAFFH8MAAIbAAMJQx0bJwAJAQAbAAMJQx0bJwAJAQAuAAQKfxgAAhsACAn3HmwmACACABsACAn3HmwmACACAAEuAAUUAgkJAAgA0x4A.',
Ex='Extrathick:BAAALgAECgMJAwAAAA==.',
Fa='Fabel:BAEBLgAECn80AAIRAAgJTyJeBwBoAgARAAgJTyJeBwBoAgAAAA==.Falahad:BAAALgAECgEJAQABLgAFFAMJDwADAD4OAA==.Faltree:BAACLgAFFH8PAAMDAAMJPg7XMwCxAAADAAMJPg7XMwCxAAAfAAIJuhVnUgB6AAAuAAQKfyEABB8ACQkeFf5TAFcBAB8ACAkrFP5TAFcBAAMACAkOF0wyAFEBACIAAQnfAUo6AB8AAAAA.Fathershale:BAAALgAECgUJCAAAAA==.',
Fi='Firelord:BAAALgADCgEJAQAAAA==.Fistingmilk:BAAALgAECgYJBwAAAA==.',
Fo='Foulcor:BAABLgAECn8dAAMNAAkJ7B6LFwBNAgANAAgJlB6LFwBNAgAMAAcJRhEwmQBDAQAAAA==.',
Fr='Freakadeek:BAABLgAECn8VAAQjAAkJaw1DIQDEAAAIAAUJ0Aid1wDeAAAjAAMJnhdDIQDEAAAJAAYJgwTWTgBXAAAAAA==.Freâkadeek:BAAALgAECgIJBQABLgAECgkJFQAjAGsNAA==.Freäk:BAAALgADCgMJAwABLgAECgkJFQAjAGsNAA==.Frieren:BAABLgAECn8+AAIBAAkJsBY3PwAfAgABAAkJsBY3PwAfAgAAAA==.Frink:BAAALgAECgEJAQABLgAECgkJPQAkAOEkAA==.Frostlord:BAAALgAECgIJAgAAAA==.',
Fu='Funnelquakes:BAABLgAECn8aAAIBAAYJ0BHqrQAlAQABAAYJ0BHqrQAlAQABLgAFFAMJBAAUAAAAAA==.Furlining:BAAALgADCgQJAwABLgAFFAMJBwAMAO0IAA==.Furyofthenug:BAAALgAECgQJBAAAAA==.Fuzzywuzzy:BAAALgAECgUJBQABLgAECgYJHQATALgdAA==.',
Ga='Gabbyo:BAABLgAECn8lAAIfAAkJ/Ad2VAA+AQAfAAkJ/Ad2VAA+AQAAAA==.Galadorn:BAABLgAECn8mAAIGAAkJWiC/DwDFAgAGAAkJWiC/DwDFAgAAAA==.Gallgamesh:BAAALgADCgIJAgAAAA==.Garfall:BAAALgAECgcJDgAAAA==.Garga:BAAALgADCgMJBAABLgAECgUJBQAUAAAAAA==.',
Ge='Geirvaldr:BAAALgAECgYJBgAAAA==.Gerdash:BAAALgAECgMJBAAAAA==.Gerred:BAACLgAFFH8KAAIOAAMJPRj0IwDfAAAOAAMJPRj0IwDfAAAuAAQKfyUAAw4ACQndHEECAM0BAA4ACQm7HEECAM0BAA8ABAlFFB5mAMQAAAAA.',
Gh='Ghallow:BAABLgAECn8gAAIQAAkJnBuWAgCxAQAQAAkJnBuWAgCxAQAAAA==.Ghosty:BAACLgAFFH8JAAIVAAQJOxWRIAAhAQAVAAQJOxWRIAAhAQAuAAQKfyoAAhUABwlQIFgUAP8BABUABwlQIFgUAP8BAAAA.',
Gi='Gimp:BAAALgAECgcJCAAAAA==.',
Gl='Gladur:BAABLgAFFH8GAAMHAAYJyAzzHwDZAAAHAAUJtwzzHwDZAAAYAAEJmQGAZQAxAAABLgAFFAkJIwABAB0XAA==.',
Go='Goldenflame:BAAALgAECgUJBwAAAA==.Goldenlily:BAAALgAECgYJEgAAAA==.Goldenmunc:BAABLgAECn8tAAIBAAkJNxfsNQBBAgABAAkJNxfsNQBBAgAAAA==.Goldenone:BAAALgAECggJCQAAAA==.Goldenpants:BAABLgAECn8nAAIPAAkJjxM8IgDgAQAPAAkJjxM8IgDgAQAAAA==.',
Gr='Grandesaxx:BAAALgAECgEJAQAAAA==.Grievous:BAABLgAECn89AAIXAAkJOyW4AABKAwAXAAkJOyW4AABKAwAAAA==.',
Gu='Guinton:BAAALgADCgMJAwAAAA==.',
['Gû']='Gûrth:BAAALgADCgcJBwAAAA==.',
Ha='Hailmary:BAABLgAECn8oAAILAAkJEiV8AQCoAwALAAkJEiV8AQCoAwAAAA==.Halcrux:BAAALgAECgQJBAAAAA==.Halvard:BAAALgADCgMJBQAAAA==.Harusen:BAABLgAECn8cAAIlAAkJFR9EAgCmAgAlAAkJFR9EAgCmAgAAAA==.Havgnwltrav:BAAALgADCgcJBgAAAA==.',
He='Healaga:BAAALgAECgYJBgABLgAECgkJPwAIAOkcAA==.',
Hh='Hhoonnzz:BAABLgAFFH8NAAIVAAMJChOmJwDrAAAVAAMJChOmJwDrAAABLgAFFAIJCQAIANMeAA==.',
Hi='Hildalsind:BAAALgADCgkJCQABLgAFFAMJCQABAIMdAA==.',
Ho='Homestar:BAAALgADCgEJAQAAAA==.Hooll:BAAALgAECgIJAgAAAA==.Hornreaper:BAABLgAECn8bAAIZAAYJ5hfvJACVAQAZAAYJ5hfvJACVAQAAAA==.Hotshot:BAAALgAECgMJAwAAAA==.Hozak:BAAALgAECgQJBAAAAA==.',
Hu='Hubbabubbajr:BAAALgAECgMJAwABLgAECgkJMwAfAIIbAA==.Hubert:BAAALgADCgEJAgAAAA==.Huracan:BAAALgAECgEJAgAAAA==.Hurin:BAAALgAECgcJDgAAAA==.Huur:BAAALgAECgEJAQABLgAECgEJAQAUAAAAAA==.',
Hy='Hyetta:BAAALgAECgQJBgABLgAECgkJHAAlABUfAA==.Hyir:BAAALgADCgYJBwABLgAFFAQJHgAHAOEfAA==.Hylonome:BAAALgAECgQJBAABLgABCgYJBgAUAAAAAA==.',
Ic='Icecold:BAAALgAECgQJBQAAAA==.',
Il='Ilavengu:BAAALgAECgMJBQABLgAFFAQJFgAeADEmAA==.Illiya:BAABLgAECn8ZAAILAAkJdQstEQCQAAALAAkJdQstEQCQAAAAAA==.',
Ir='Irôn:BAAALgAECgEJAQAAAA==.',
Is='Isochu:BAAALgAECgMJAwAAAA==.',
Iu='Iutara:BAAALgAECgYJDAAAAA==.',
Ja='Jaalein:BAAALgADCgcJDgAAAA==.Jayonor:BAABLgAECn80AAQSAAkJthVkGgAOAgASAAkJthVkGgAOAgAQAAYJ9we4GgAeAQAeAAcJ5AZmcQAIAQAAAA==.',
Je='Jek:BAAALgAECgYJBgAAAA==.',
Jo='Joryu:BAAALgADCgIJAwAAAA==.',
Ju='Juicycucci:BAAALgAECgcJEgABLgAFFAMJBAAUAAAAAA==.',
['Jö']='Jörmungandrr:BAAALgAECgcJBwABLgAECgQJBgAUAAAAAA==.',
Ka='Kaevrielle:BAECLgAFFH8KAAIXAAMJFhfUCADGAAAXAAMJFhfUCADGAAAuAAQKfx4AAxcACQmOG2IHAAwCABcACQmOG2IHAAwCACYAAQlWCol4ACcAAAAA.Kaison:BAABLgAECn8XAAMgAAkJEQigMQBVAQAgAAkJEQigMQBVAQAnAAcJBAtMNQBAAQABLgAECgkJIAAGAA0VAA==.Kaladîn:BAAALgAECgMJAwABLgAFFAkJIwABAB0XAA==.Kalii:BAAALgADCgQJBAAAAA==.Kamel:BAAALgADCgcJDQAAAA==.Kardin:BAAALgADCgEJAQAAAA==.Karwin:BAABLgAECn8bAAIBAAgJ/xRCaACsAQABAAgJ/xRCaACsAQAAAA==.Katakuri:BAAALgAECgEJAgAAAA==.',
Ke='Keeper:BAABLgAFFH8KAAIWAAUJKRtmAQBYAQAWAAUJKRtmAQBYAQABLgAFFAYJFwAMAEsdAA==.Keeperodark:BAACLgAFFH8RAAMEAAYJLxGgGQBZAQAEAAYJLxGgGQBZAQACAAEJegHkFQAYAAAuAAQKfxgAAgQACAkrF0EKAF4BAAQACAkrF0EKAF4BAAEuAAUUBgkXAAwASx0A.Keeperolight:BAACLgAFFH8XAAIMAAYJSx0PDgCbAQAMAAYJSx0PDgCbAQAuAAQKf1UAAwwACQlUJeYEAFADAAwACQlUJeYEAFADAA0AAQmBGBSQAEAAAAAA.Kemanorel:BAAALgADCgcJDgABLgAECgkJJwAgAK0TAA==.Kerli:BAAALgADCgEJAQAAAA==.',
Ki='Kianth:BAAALgADCgkJEgAAAA==.Killkat:BAABLgAECn8uAAIBAAkJgxhiNQBDAgABAAkJgxhiNQBDAgAAAA==.',
Ko='Kodera:BAABLgAECn8dAAMTAAYJuB3ZDQDyAQATAAYJuB3ZDQDyAQAaAAQJwhzKDgAfAQAAAA==.Koojo:BAAALgAECggJCgAAAA==.Kosma:BAAALgAECgYJBgAAAA==.Kovae:BAAALgADCgEJAQAAAA==.',
Kr='Kraken:BAAALgADCgUJBQAAAA==.',
Ku='Kusheddruid:BAAALgADCgMJBQAAAA==.',
Ky='Kyaritin:BAAALgAECgMJAwABLgAECgYJCgAUAAAAAA==.Kyokei:BAAALgAECgEJAQAAAA==.',
La='Laiho:BAAALgADCgUJCAAAAA==.Lans:BAABLgAECn8UAAQoAAkJIQ0hDQD4AAAoAAUJ2AkhDQD4AAABAAQJ1Q80zAD3AAApAAQJAwkBCQDKAAAAAA==.Larew:BAACLgAFFH8JAAIMAAMJyAldTAB8AAAMAAMJyAldTAB8AAAuAAQKfzQAAgwACQnfGfMnAGQCAAwACQnfGfMnAGQCAAAA.Lazytemplar:BAAALgADCgMJAwABLgAFFAMJBAAUAAAAAA==.',
Le='Lealla:BAABLgAECn89AAIDAAkJlCI8BQAIAwADAAkJlCI8BQAIAwAAAA==.Lechevalier:BAAALgAFFAIJBAABLgAFFAMJBAAUAAAAAA==.Leodin:BAAALgAECgEJAgAAAA==.Leorus:BAAALgAECgIJAgAAAA==.Lethhunt:BAACLgAFFH8cAAMcAAgJHQ0+EABdAQAcAAgJlQk+EABdAQAbAAQJQBLbLADwAAAuAAQKfy4AAxwACQncHpwGACgCABwACQlgHpwGACgCABsAAgk+JFKHANIAAAAA.',
Li='Lilmistfox:BAAALgAECgUJBwABLgAFFAQJFgAeADEmAA==.Lioh:BAAALgAECgQJBAAAAA==.Lizardgang:BAABLgAECn8XAAIbAAcJERYLJwC+AAAbAAcJERYLJwC+AAAAAA==.',
Lo='Loganshu:BAAALgAECgkJDgAAAA==.Lokan:BAACLgAFFH8RAAMkAAMJWRkcHQDoAAAkAAMJWRkcHQDoAAAbAAEJwgjlqABFAAAuAAQKfywAAyQACQlHHqkIAJQCACQACQlHHqkIAJQCABsAAQn+CiMyATYAAAAA.Lots:BAACLgAFFH8RAAIEAAMJhhtjZwD3AAAEAAMJhhtjZwD3AAAuAAQKfycAAwQACQktIgIrAC4CAAQACAliIgIrAC4CAAIABAngHkcsAA0BAAAA.',
Lu='Ludacast:BAAALgADCgIJAgAAAA==.Ludafists:BAAALgADCgcJDAAAAA==.Ludakris:BAABLgAECn8eAAIRAAkJfxhLCwATAgARAAkJfxhLCwATAgAAAA==.Lumanoth:BAAALgAECgYJBgAAAA==.',
Ly='Lyna:BAABLgAECn8gAAIeAAkJpROdPwCvAQAeAAkJpROdPwCvAQAAAA==.Lynaya:BAAALgADCgIJAgAAAA==.',
['Lí']='Líonheart:BAABLgAECn8eAAMNAAcJYBePPgBKAQANAAcJYBePPgBKAQAMAAYJFgvJ0wDuAAAAAA==.',
['Lî']='Lîghtless:BAACLgAFFH8PAAIBAAYJBhqgGABoAQABAAYJBhqgGABoAQAuAAQKfxcAAgEACAmfJUchAO4CAAEACAmfJUchAO4CAAAA.',
['Lú']='Lúckally:BAAALgADCgQJBAABLgAECgYJCgAUAAAAAA==.Lúckÿ:BAAALgAECgYJCgAAAA==.',
Ma='Magetheo:BAAALgADCgIJAgAAAA==.Magicpanda:BAAALgAECgUJCwAAAA==.Mahina:BAAALgAFFAEJAQAAAA==.Malik:BAAALgADCgIJAgAAAA==.Marcille:BAABLgAECn8nAAIBAAgJ2RO7dwCKAQABAAgJ2RO7dwCKAQAAAA==.Masyledian:BAAALgAECgQJCAABLgAECggJIwAIAPwaAA==.Mathor:BAAALgAECgEJAgAAAA==.Mavrbg:BAAALgAECgQJBQAAAA==.Mayhaps:BAABLgAECn9EAAMbAAkJFRuBJwBBAgAbAAkJFRuBJwBBAgAcAAEJZACpmgAYAAAAAA==.',
Mc='Mcbain:BAABLgAECn89AAIkAAkJ4STWAQA9AwAkAAkJ4STWAQA9AwAAAA==.',
Me='Melinia:BAAALgAECgEJAQABLgAECgcJCAAUAAAAAA==.Melrine:BAAALgADCgMJAwAAAA==.Mentaltitty:BAABLgAECn8gAAIBAAkJgxKGSwD5AQABAAkJgxKGSwD5AQAAAA==.Meret:BAAALgADCgMJBQAAAA==.',
Mi='Minerwor:BAAALgAECggJDAAAAA==.Mirrayla:BAAALgADCgYJBgAAAA==.Misty:BAAALgADCgYJBgAAAA==.',
Mm='Mmisty:BAABLgAECn9IAAIDAAkJghmMDwBnAgADAAkJghmMDwBnAgAAAA==.',
Mo='Moarthretplz:BAAALgAECgUJCQABLgAFFAQJFgAeADEmAA==.Mohji:BAAALgAFFAEJAQABLgAFFAkJIwAnADkTAA==.Moldynuggets:BAAALgAECgYJCwAAAA==.Momometaru:BAACLgAFFH8IAAMFAAQJMwv0BQDOAAAFAAMJ3wv0BQDOAAAEAAIJQglwZgA7AAAuAAQKfyQABAQACQmBFoJBANgBAAQACQl+E4JBANgBAAIABQk2FHImACwBAAUAAwnPGsYmAIwAAAAA.Monsterbee:BAACLgAFFH8QAAIEAAUJgg0zJwDyAAAEAAUJgg0zJwDyAAAuAAQKf04AAgQACQlEFuIrACoCAAQACQlEFuIrACoCAAAA.',
Mu='Mustypizza:BAABLgAECn8uAAICAAkJihjJBAAsAgACAAkJihjJBAAsAgAAAA==.',
Mx='Mxicancowboy:BAAALgADCgEJAgAAAA==.',
My='Mystery:BAABLgAECn89AAMTAAkJNiC9AgAzAwATAAkJNiC9AgAzAwAaAAUJXhELEAAKAQAAAA==.',
['Mê']='Mêøwzêr:BAAALgAECggJEwAAAA==.',
['Mÿ']='Mÿst:BAAALgAECgMJBAAAAA==.',
Na='Nak:BAAALgAECgYJBgAAAA==.Nanuk:BAAALgAECgEJAQAAAA==.Narashi:BAAALgAECgQJCAAAAA==.Naril:BAAALgADCgUJBQAAAA==.Nats:BAABLgAECn8tAAMeAAkJ9w8iFgDnAAAeAAkJ9w8iFgDnAAASAAMJZw0/GAB/AAAAAA==.',
Ne='Neameny:BAABLgAECn89AAIbAAkJGBObOwDxAQAbAAkJGBObOwDxAQAAAA==.',
Nh='Nhojj:BAAALgAECgIJAgAAAA==.',
Ni='Nianji:BAAALgADCgYJDgAAAA==.Nightstar:BAAALgAECgEJAQAAAA==.Nightworld:BAAALgADCgcJDgAAAA==.',
No='Noctum:BAABLgAECn8cAAIFAAkJxxflAABSAgAFAAkJxxflAABSAgAAAA==.Nordicpally:BAAALgADCgQJBAAAAA==.Notbomba:BAAALgAECgEJAwAAAA==.Notgim:BAAALgADCggJCAAAAA==.',
Nu='Nualrossan:BAAALgADCgYJCAAAAA==.Nubrac:BAAALgAECgkJEwAAAA==.',
Ny='Nylux:BAAALgAECgYJDwAAAA==.',
Ob='Obit:BAAALgADCggJDAAAAA==.Oblivion:BAACLgAFFH8LAAIEAAQJnhmwMwC5AAAEAAQJnhmwMwC5AAAuAAQKfz4AAwQACQmfJLUGACUDAAQACQmfJLUGACUDAAIAAQkAAFFdAFcAAAAA.',
Og='Ogrebreath:BAAALgAECgUJBwAAAA==.',
Oo='Oostren:BAAALgAECgEJAgAAAA==.',
Or='Orsyp:BAAALgADCgkJGgAAAA==.',
Pa='Paazuzu:BAAALgADCgEJAQAAAA==.Pallyshore:BAAALgADCgEJAQAAAA==.Palockie:BAAALgADCgEJAQAAAA==.Pandas:BAABLgAECn8hAAISAAkJAhF6JwCxAQASAAkJAhF6JwCxAQAAAA==.Partyrocker:BAABLgAECn8XAAIkAAcJag79KgBKAQAkAAcJag79KgBKAQABLgAECgkJFQAjAGsNAA==.Paynë:BAAALgAECgYJDQAAAA==.',
Pi='Pixae:BAACLgAFFH8PAAITAAMJjwdDIwCHAAATAAMJjwdDIwCHAAAuAAQKfyEAAhMACAm5Cm8ZAD8BABMACAm5Cm8ZAD8BAAAA.Pixiechaos:BAAALgAECgQJCAABLgAECgcJHgAXANwJAA==.',
Po='Poliahu:BAABLgAECn8dAAIbAAkJFwyNHwDoAAAbAAkJFwyNHwDoAAAAAA==.Porthoss:BAAALgADCggJDwAAAA==.Powerplant:BAACLgAFFH8aAAIbAAgJViDRDQD6AQAbAAgJViDRDQD6AQAuAAQKfyYAAhsACQkgJCgIAA4DABsACQkgJCgIAA4DAAAA.Poyoram:BAAALgADCgEJAQAAAA==.',
Pr='Prinsesa:BAAALgAECgEJAQAAAA==.Pryi:BAAALgAECgQJBgABLgAFFAMJBwAMAO0IAA==.',
Py='Pyralys:BAABLgAECn85AAMLAAkJGBFmHADjAQALAAkJGBFmHADjAQAgAAMJqQJBiAAxAAAAAA==.',
['Pä']='Pärts:BAAALgAECgUJBQABLgAFFAYJCwAkAEITAA==.',
Qu='Questus:BAAALgADCgUJBQAAAA==.Quizac:BAAALgADCgMJBQAAAA==.',
Ra='Rabidghost:BAAALgADCgYJBgAAAA==.Ragedk:BAAALgAFFAMJBAAAAA==.Ragemonk:BAAALgAECgUJDgABLgAFFAMJBAAUAAAAAA==.Ragetality:BAAALgAFFAIJBAABLgAFFAMJBAAUAAAAAA==.Rahken:BAAALgADCgQJBAAAAA==.Rakthera:BAAALgADCgcJBwAAAA==.Rallaster:BAAALgAECgYJBgABLgAECgkJJwAgAK0TAA==.Ramaria:BAAALgADCgkJCQABLgAECgkJJgAGAFogAA==.Raserei:BAABLgAFFH8KAAIPAAMJIhf2LwDwAAAPAAMJIhf2LwDwAAAAAA==.Rasputain:BAAALgADCgYJCgAAAA==.Rasputein:BAAALgADCgcJBwAAAA==.Rattelyr:BAAALgAECgYJDgAAAA==.Ravara:BAAALgADCgYJBgABLgAECgkJJgAGAFogAA==.Rawb:BAACLgAFFH8MAAIPAAMJjxTzMwDhAAAPAAMJjxTzMwDhAAAuAAQKfx8AAw8ACAmyG74YACgCAA8ACAmyG74YACgCAAoABglmFr0uAM0AAAEuAAUUAgkJAAgA0x4A.Razgaurd:BAAALgAECgMJAwAAAA==.',
Re='Recolada:BAAALgAECggJCAAAAA==.Regice:BAAALgAECgcJBwABLgAFFAQJFQAJAC8bAA==.Regicee:BAACLgAFFH8VAAMJAAQJLxtSDQAhAQAJAAQJLxtSDQAhAQAIAAEJGwnqqgA1AAAuAAQKf1sAAwkACQluI10EAO8CAAkACQluI10EAO8CAAgABwm5ESQiALYAAAAA.Retam:BAAALgAECgcJDgAAAA==.Revakos:BAAALgADCgMJAwAAAA==.',
Rh='Rhysandra:BAAALgAECgQJCQAAAA==.',
Ri='Ribble:BAAALgADCgMJAwAAAA==.Riffraff:BAAALgAFFAcJAQAAAA==.Rindou:BAAALgAECgkJBAAAAA==.Ripcord:BAAALgAECgUJDwAAAA==.Ripem:BAAALgADCgYJBgAAAA==.Ripperoni:BAAALgAECgcJDQAAAA==.Rizek:BAAALgAECgUJBgABLgAECgcJHQAYADkPAA==.Rizzx:BAAALgAECgEJAQAAAA==.',
Ro='Rockdyou:BAABLgAECn8nAAIIAAkJ+R51JABzAgAIAAkJ+R51JABzAgAAAA==.Roglef:BAAALgAECgQJCQAAAA==.Rogmesh:BAAALgAECgcJEAAAAA==.Rotlobster:BAACLgAFFH8IAAIFAAUJCR30AQBnAQAFAAUJCR30AQBnAQAuAAQKfxoAAgUACQkAHvUBAMQCAAUACQkAHvUBAMQCAAEuAAUUAgkFABAAaRUA.Roxxy:BAAALgAECgQJBAAAAA==.',
Ru='Rudal:BAAALgADCgYJBgAAAA==.Rundvelt:BAACLgAFFH8RAAIRAAMJeA0IDwCQAAARAAMJeA0IDwCQAAAuAAQKfyQAAhEACQlSEQwVAIABABEACQlSEQwVAIABAAAA.',
['Rà']='Ràgëquit:BAAALgAECgEJAQAAAA==.',
Sa='Sage:BAAALgADCgcJCAAAAA==.Sandwich:BAAALgAECgcJCAAAAA==.Saphíra:BAAALgAFFAIJAQABLgAFFAkJIwABAB0XAA==.Sapkick:BAAALgAECgQJBwAAAA==.',
Se='Serdragon:BAAALgADCgQJBAAAAA==.Sertian:BAAALgAECgEJAQAAAA==.Servoid:BAAALgAECgUJCQAAAA==.',
Sh='Shamuljacksn:BAAALgAECgQJCAAAAA==.Shando:BAAALgAECgEJAQAAAA==.Shiftstyle:BAEALgAECgEJAQAAAA==.Shtanky:BAACLgAFFH8PAAIKAAMJaBFHHgClAAAKAAMJaBFHHgClAAAuAAQKfyQAAgoACQnHD7MWAI4BAAoACQnHD7MWAI4BAAAA.',
Si='Silentjin:BAAALgADCgYJCQAAAA==.Silentsocks:BAAALgAECgUJDAAAAA==.Sixsixsix:BAAALgAECgcJCwABLgAFFAIJCQAIANMeAA==.',
Sk='Skoogz:BAABLgAECn8WAAMJAAgJiRJZJgAhAQAJAAgJQRJZJgAhAQAIAAQJ5A+a1QDhAAAAAA==.',
Sm='Smackdowne:BAAALgADCgIJAgAAAA==.',
So='Sofakingséxy:BAAALgAECgMJAwABLgAFFAMJBAAUAAAAAA==.Soggi:BAAALgADCgUJBQAAAA==.Soggyy:BAAALgADCgYJCwAAAA==.Sogsy:BAAALgAECgYJBgAAAA==.Solar:BAABLgAECn8VAAQHAAcJyRkxLwBtAQAHAAYJCxYxLwBtAQAhAAYJrhzoOABmAQAYAAEJUwL71wAaAAABLgAFFAUJBgAGAMcBAA==.Soulfulgingr:BAABLgAECn8zAAISAAkJjBqJAgBoAgASAAkJjBqJAgBoAgAAAA==.Soulkeeper:BAAALgADCgIJAgABLgAFFAYJFwAMAEsdAA==.',
Sp='Spiteful:BAAALgAECgQJBAAAAA==.',
St='Starlagosa:BAAALgADCgYJCQAAAA==.Stonedraider:BAAALgAECgEJAQAAAA==.Sturm:BAAALgAECgMJAwAAAA==.Styx:BAAALgAECgMJAwAAAA==.',
Su='Sunbake:BAABLgAECn8bAAMLAAgJ7QUSDwCtAAALAAgJ7QUSDwCtAAAgAAEJ5gYqkAAqAAAAAA==.',
Sw='Sweetbbyraze:BAACLgAFFH8eAAMaAAcJwBqoBQAIAQAZAAcJBhiaIQBTAQAaAAQJQCGoBQAIAQAuAAQKfygAAxoACQnuIFIGAJACABoABwm8IVIGAJACABkABAm7HTYNAKIAAAAA.',
Sy='Sylaena:BAABLgAECn8oAAIcAAgJVQoeFAAgAQAcAAgJVQoeFAAgAQAAAA==.Sylvrstorm:BAAALgAECgcJDQAAAA==.',
['Së']='Sërënity:BAABLgAECn8XAAIfAAUJjg5cEACqAAAfAAUJjg5cEACqAAAAAA==.',
['Sí']='Sín:BAAALgAECgcJDAABLgAFFAIJCQAIANMeAA==.',
Ta='Tali:BAAALgAECgEJAQABLgAFFAMJBwAMAO0IAA==.Talidh:BAAALgADCgIJAgAAAA==.Talipally:BAACLgAFFH8HAAIMAAMJ7QjMewC+AAAMAAMJ7QjMewC+AAAuAAQKfxwAAgwACQkyEM14AH0BAAwACQkyEM14AH0BAAAA.Talishammy:BAAALgAECgYJCAABLgAFFAMJBwAMAO0IAA==.Taliwhacker:BAAALgAFFAEJAQABLgAFFAMJBwAMAO0IAA==.Talonleafgrd:BAAALgAECgkJCgAAAA==.Tanaka:BAABLgAECn8gAAIIAAgJgBMJWgC4AQAIAAgJgBMJWgC4AQAAAA==.Tanisong:BAAALgAECgQJDQAAAA==.Tassadar:BAAALgAECgUJCAAAAA==.',
Te='Teldo:BAAALgADCgMJBQAAAA==.Tepeyollotl:BAAALgADCgEJAQAAAA==.Terayus:BAAALgADCgcJDAAAAA==.Teyliah:BAAALgADCgMJAwAAAA==.',
Tf='Tf:BAAALgAECgYJBgABLgAFFAIJCQAIANMeAA==.',
Th='Thalor:BAAALgAECgUJBQABLgAFFAkJNAAHAMYbAA==.Thekingpunch:BAABLgAECn9OAAMYAAkJoiO5BwAhAwAYAAkJoiO5BwAhAwAHAAEJahZWjwBCAAAAAA==.Thenle:BAAALgADCggJFwAAAA==.Thline:BAAALgADCgMJBQAAAA==.Thunderblitz:BAABLgAECn8rAAINAAkJdgknMwCIAQANAAkJdgknMwCIAQAAAA==.Thurmus:BAAALgADCgkJQAAAAA==.Thánatos:BAAALgADCgMJAwAAAA==.Théhuntréss:BAAALgADCgEJAQAAAA==.',
Ti='Tillwar:BAABLgAECn87AAIPAAkJKh2pEAByAgAPAAkJKh2pEAByAgAAAA==.Tinymonk:BAAALgAECgMJAwAAAA==.Tiàna:BAAALgADCgUJBQAAAA==.',
To='Tofu:BAACLgAFFH8LAAIIAAMJ3B16hwD6AAAIAAMJ3B16hwD6AAAuAAQKf0kABAgACQnEHvEVAMQCAAgACQnEHvEVAMQCAAkABwmjFrwaAIgBACMAAwnHFicMAIcAAAAA.Tokanya:BAAALgAECgEJAQAAAA==.Tortillachip:BAAALgAECgEJAgAAAA==.Toxidot:BAAALgAECgEJAQAAAA==.',
Tr='Treibh:BAABLgAECn8qAAIfAAkJCxilFwCJAgAfAAkJCxilFwCJAgAAAA==.Trelephant:BAAALgAECgMJBQAAAA==.Trulydps:BAABLgAECn8vAAIbAAkJ4xQKLwAgAgAbAAkJ4xQKLwAgAgAAAA==.Trulyog:BAAALgAECgQJBAABLgAECgkJLwAbAOMUAA==.',
Tu='Tubbsmcgee:BAACLgAFFH8tAAIeAAkJiCEqAQD0AgAeAAkJiCEqAQD0AgAuAAQKfyUAAh4ACQkrJLgHAPkCAB4ACQkrJLgHAPkCAAEuAAUUCQktAB4AiCEA.Tukkit:BAAALgAECgYJDwAAAA==.',
Tw='Twistedshot:BAAALgADCggJCAAAAA==.Twizzler:BAABLgAECn9TAAIBAAkJZQi/fgB6AQABAAkJZQi/fgB6AQAAAA==.',
Ty='Tyraniik:BAAALgADCgYJCAAAAA==.',
['Të']='Tërris:BAABLgAECn8eAAIJAAkJQBHkGgCGAQAJAAkJQBHkGgCGAQAAAA==.',
['Tî']='Tîlldeath:BAAALgAECgUJBwAAAA==.',
['Tõ']='Tõaster:BAAALgADCgQJBAABLgAECgkJJgAGAFogAA==.',
Uj='Uji:BAAALgADCgEJAQAAAA==.',
Ur='Urowndad:BAAALgAECgUJBQABLgAECggJFgAMAL0TAA==.Urownmother:BAAALgADCgUJBQABLgAECggJFgAMAL0TAA==.',
Va='Vaellian:BAAALgAECgYJDAAAAA==.Vallez:BAECLgAFFH8XAAMNAAQJzh3GIwACAQANAAQJzh3GIwACAQAMAAMJ/g1fcwDMAAAuAAQKfyoAAw0ACQmqHQMSAIMCAA0ACQmqHQMSAIMCAAwAAwmiDWpGAWYAAAAA.Vanillaghost:BAAALgADCgIJAQAAAA==.Varnusshadow:BAAALgAECgUJBgAAAA==.',
Ve='Vearik:BAAALgAECgUJBwAAAA==.Velladoree:BAABLgAECn8mAAIYAAgJlAteFwDTAAAYAAgJlAteFwDTAAAAAA==.Vendaryn:BAAALgADCggJCAAAAA==.Vexahlia:BAAALgADCgMJAwAAAA==.',
Vg='Vgurlpally:BAAALgADCgYJCQAAAA==.',
Vy='Vynlorlan:BAAALgADCgMJAwABLgAECgMJBAAUAAAAAA==.',
Wa='Walkindead:BAAALgAECgQJBgAAAA==.Waveygravee:BAAALgAECgIJAwAAAA==.Wavyghoul:BAAALgAECgEJAQAAAA==.Wavygraivy:BAABLgAECn8gAAIeAAkJjhIXTACAAQAeAAkJjhIXTACAAQAAAA==.Wavygravey:BAAALgADCgQJBAAAAA==.',
We='Wedragon:BAABLgAECn8bAAMYAAYJ8BtwBgDZAQAYAAYJ8BtwBgDZAQAHAAMJygdFbgB1AAAAAA==.',
Wh='Whatashocker:BAAALgAFFAMJBAAAAA==.Wheelchair:BAACLgAFFH8LAAIIAAQJOxv7bwAeAQAIAAQJOxv7bwAeAQAuAAQKfxwAAggACAkSJF0SAA4DAAgACAkSJF0SAA4DAAAA.',
Wo='Woofwoof:BAAALgAFFAIJAgAAAA==.',
Wu='Wullemage:BAAALgADCgcJEwABLgAFFAcJHwAVALAaAA==.',
['Wå']='Wåsp:BAABLgAECn9RAAIGAAkJAxAHUACVAQAGAAkJAxAHUACVAQABLgAECgkJHwAdABwWAA==.',
Xb='Xb:BAAALgAECgcJBQAAAA==.',
Xh='Xhexana:BAABLgAECn84AAIeAAkJTRcBHQBkAgAeAAkJTRcBHQBkAgABLgAECgkJPQAbABgTAA==.',
Xi='Xiaopo:BAAALgAECgEJAQABLgAFFAQJFgAeADEmAA==.',
Xr='Xrael:BAAALgAECgEJAQABLgAFFAMJEwAHACMiAA==.Xrayl:BAACLgAFFH8TAAMHAAMJIyKYEwAgAQAHAAMJIyKYEwAgAQAhAAMJxAxDOwC5AAAuAAQKfyUAAwcACQnoIMwNAGkCAAcACAmrIcwNAGkCACEAAQmOG/N9AE8AAAAA.',
Xz='Xzerocool:BAABLgAECn8WAAQMAAgJvRNCiQBeAQAMAAgJvRNCiQBeAQARAAIJshNmPABqAAANAAEJmQOznQAiAAAAAA==.',
Ya='Yaniaa:BAAALgADCgcJBwAAAA==.Yannii:BAAALgADCgcJDgAAAA==.',
Ye='Yenko:BAAALgADCgIJAgAAAA==.',
Yo='Yolo:BAAALgADCgcJCwAAAA==.Yoshikazu:BAAALgAECgkJDAAAAA==.Yoyoboy:BAAALgAECgIJBwAAAA==.',
Za='Zaarah:BAAALgAECgYJDAAAAA==.',
Ze='Zealot:BAAALgAECgcJBwAAAA==.Zellek:BAAALgADCgEJAQAAAA==.Zendezoth:BAABLgAECn8jAAIaAAkJpRmcAwBZAgAaAAkJpRmcAwBZAgAAAA==.Zephik:BAAALgADCgEJAQAAAA==.Zerofrost:BAABLgAECn8uAAIBAAkJrxl0PAAoAgABAAkJrxl0PAAoAgAAAA==.Zerrìc:BAAALgAECgcJEAAAAA==.Zevra:BAAALgADCgMJAwAAAA==.',
Zh='Zhiva:BAABLgAECn9AAAIDAAkJ3hH0BQCLAQADAAkJ3hH0BQCLAQAAAA==.',
Zu='Zul:BAACLgAFFH8ZAAIVAAMJXiOfIgAQAQAVAAMJXiOfIgAQAQAuAAQKfzMAAxUACQkwI+oHAKkCABUACQkwI+oHAKkCABYAAQnLAkMiACQAAAAA.',
Zy='Zykoz:BAABLgAECn8uAAIVAAkJpCGMBADzAgAVAAkJpCGMBADzAgAAAA==.',
['Ða']='Ðamned:BAACLgAFFH8HAAMQAAMJpRROCADcAAAQAAMJpRROCADcAAASAAEJNwMJYAAtAAAuAAQKfxwABBIACAnNG8QuAKcBABIABgnyG8QuAKcBABAAAgkKHjEKAKwAAB4AAglyB7IzAEUAAAEuAAUUAgkJAAgA0x4A.',
['Ÿo']='Ÿoshi:BAABLgAECn8bAAIbAAgJhQ/8TQB/AQAbAAgJhQ/8TQB/AQAAAA==.',
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
