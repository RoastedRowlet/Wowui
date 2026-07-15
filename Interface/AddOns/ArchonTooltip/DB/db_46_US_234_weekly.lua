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

local lookup = {'Mage-Frost','Warlock-Destruction','Druid-Balance','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Priest-Holy','Paladin-Retribution','Paladin-Holy','Warrior-Arms','Warrior-Fury','Shaman-Enhancement','Paladin-Protection','Shaman-Elemental','Evoker-Preservation','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Vengeance','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Unknown-Unknown','Shaman-Restoration','Druid-Restoration','Priest-Shadow','Monk-Brewmaster','Druid-Feral','DeathKnight-Frost','Hunter-Survival','Rogue-Outlaw','DemonHunter-Havoc','Priest-Discipline','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=46,date='2026-07-12',data={Ab='Abomination:BAAALgADCgMJAwAAAA==.',
Ad='Adune:BAAALgAECgQJBQAAAA==.',
Ae='Aeidail:BAACLgAFFH8fAAIBAAgJWhdJJwDaAQABAAgJWhdJJwDaAQAuAAQKfy0AAgEACQnlI0McAAUDAAEACQnlI0McAAUDAAAA.Aelaria:BAAALgADCgMJAwAAAA==.Aeviria:BAABLgAECn8oAAICAAgJtRVxCADGAQACAAgJtRVxCADGAQAAAA==.',
Ag='Agraceful:BAACLgAFFH8OAAIDAAMJEAfwGQBvAAADAAMJEAfwGQBvAAAuAAQKfx8AAgMACQm8EjkfAM4BAAMACQm8EjkfAM4BAAAA.',
Ai='Ailee:BAAALgAECgYJDAAAAA==.Aios:BAAALgAECgIJAgAAAA==.Aiza:BAACLgAFFH8QAAIEAAMJfgxOKQDFAAAEAAMJfgxOKQDFAAAuAAQKfzgAAwQACQmXGb8dAHICAAQACQmXGb8dAHICAAUAAQkAAA1JAAAAAAAA.',
Al='Alaber:BAAALgAECgUJCAAAAA==.Aldanil:BAAALgADCgMJAwAAAA==.Allarria:BAAALgADCgYJBwABLgAECgkJJgAGAFogAA==.',
Am='Ampersand:BAAALgAECgMJCQAAAA==.',
An='Animalfriend:BAAALgAECgYJDgAAAA==.Anklesmasher:BAABLgAECn8VAAIHAAgJcA4fPAAQAQAHAAgJcA4fPAAQAQAAAA==.Antisocial:BAACLgAFFH8IAAIEAAMJgwydgwC+AAAEAAMJgwydgwC+AAAuAAQKfxkAAgQABglwGsBpAJABAAQABglwGsBpAJABAAEuAAUUAgkJAAgA0x4A.Antonidus:BAAALgAECgYJEgAAAA==.Anyah:BAABLgAECn8dAAIDAAgJqgQKVAC/AAADAAgJqgQKVAC/AAAAAA==.',
Ap='Apolloo:BAAALgADCgMJAwAAAA==.',
Aq='Aquadora:BAAALgAECgEJAQAAAA==.',
Ar='Arfaz:BAABLgAECn88AAMIAAkJyhsGBQDgAQAIAAkJHxsGBQDgAQAJAAYJWAoXOQCvAAAAAA==.Armbrost:BAAALgAECgYJCgAAAA==.Arthemis:BAAALgAECgEJAgAAAA==.Artimås:BAAALgADCgcJCAAAAA==.Arwynne:BAAALgADCgMJAwAAAA==.Arçano:BAAALgAECgEJAQABLgAECgkJGQAKADkTAA==.',
As='Ascension:BAAALgADCgcJBgABLgAFFAQJCwAEAJ4ZAA==.Astrastar:BAABLgAECn8bAAMEAAYJ0wKg4wCVAAAEAAYJ0wKg4wCVAAACAAEJcgDDgAAOAAAAAA==.',
Au='Auralyn:BAAALgADCgMJBQAAAA==.Aurius:BAAALgAECgcJAgAAAA==.',
Av='Avarin:BAAALgADCgEJAQAAAA==.',
Ay='Aymont:BAAALgAECgQJBQAAAA==.',
Ba='Baerd:BAABLgAECn8aAAILAAcJZhPqKwBqAQALAAcJZhPqKwBqAQAAAA==.Baji:BAAALgAECgkJBwAAAA==.Barlz:BAAALgAECgEJAQAAAA==.',
Be='Beanpaste:BAAALgAECgcJAQABLgAFFAMJEAAIAHcZAA==.Beanutbutter:BAAALgADCgIJAgABLgAFFAMJEAAIAHcZAA==.Beaty:BAAALgAECgIJAgAAAA==.Bebby:BAABLgAECn8mAAMJAAgJUwMzCACqAAAJAAgJIgMzCACqAAAIAAIJaQJVeAEwAAAAAA==.Belonara:BAAALgAECgEJAQAAAA==.Belwolf:BAABLgAECn8UAAIIAAUJwApn6ADKAAAIAAUJwApn6ADKAAAAAA==.Bergstrom:BAABLgAECn80AAIMAAkJuhnAMAA+AgAMAAkJuhnAMAA+AgAAAA==.Bethanymarie:BAAALgAECgEJAQAAAA==.Betrayer:BAAALgADCgQJAwABLgAFFAQJCwAEAJ4ZAA==.',
Bi='Biancaneve:BAACLgAFFH8HAAILAAMJ9Q8kJACaAAALAAMJ9Q8kJACaAAAuAAQKfygAAgsACQnRG0kBAHoCAAsACQnRG0kBAHoCAAAA.Bighero:BAACLgAFFH8QAAIGAAMJSQsEagC4AAAGAAMJSQsEagC4AAAuAAQKfyAAAgYACQk9EVlvAFYBAAYACQk9EVlvAFYBAAAA.Bigmike:BAAALgAECgEJAgAAAA==.',
Bl='Blackmelody:BAAALgAECgEJAQAAAA==.Blakkjezus:BAAALgAECgcJCwAAAA==.Blessednugie:BAABLgAECn8VAAMNAAcJuBhzBgASAQANAAcJuBhzBgASAQAMAAIJPA3mSwArAAAAAA==.Blitzbolts:BAAALgAECgEJAgAAAA==.Bludo:BAACLgAFFH8UAAMOAAcJKxCAHQADAQAPAAUJHRX8IwAkAQAOAAQJ+wqAHQADAQAuAAQKfx4AAw8ACQl6IWgZAIACAA8ACAk5GWgZAIACAA4ABgl9HFMYADYBAAAA.',
Bo='Boe:BAABLgAECn8tAAIQAAkJgAr5EwB6AQAQAAkJgAr5EwB6AQAAAA==.Bomba:BAAALgAECgUJDQAAAA==.Bombacløt:BAABLgAECn80AAMEAAkJkxDwRQDJAQAEAAkJFRDwRQDJAQACAAcJbg6pFAAIAQAAAA==.Bowdirte:BAAALgAECgUJBwAAAA==.',
Br='Brastin:BAABLgAECn86AAIRAAkJkyJHAgASAwARAAkJkyJHAgASAwABLgAFFAYJEwASAAoMAA==.Brenell:BAACLgAFFH8IAAIBAAMJgRLhiwDBAAABAAMJgRLhiwDBAAAuAAQKfzsAAgEACQmwIX0RAPECAAEACQmwIX0RAPECAAAA.',
Bu='Bu:BAAALgAECgYJDQABLgAECgYJHQATALgdAA==.Bubblehearth:BAAALgAECgYJCQABLgAFFAMJCAAGADgNAA==.Buffet:BAABLgAECn8aAAIBAAYJ0BHqrQAlAQABAAYJ0BHqrQAlAQABLgAFFAMJCAAGADgNAA==.Buhlitz:BAAALgAECgEJAgAAAA==.Butterbean:BAAALgADCgMJBQAAAA==.',
By='Bynis:BAABLgAECn8gAAIGAAkJDRVHSACtAQAGAAkJDRVHSACtAQAAAA==.',
Ca='Cabëla:BAAALgADCgUJBQAAAA==.Cactusjack:BAAALgADCgUJBQAAAA==.Cadorex:BAAALgADCgEJAQAAAA==.Caffeinefree:BAAALgADCggJBwAAAA==.Calacolinda:BAAALgAECgcJDQAAAA==.Calamari:BAAALgAECgEJAQAAAA==.Cavakworm:BAAALgADCgEJAQAAAA==.Caylin:BAAALgADCgUJBgAAAA==.Cayusedemon:BAAALgADCgEJAQAAAA==.Cayusemage:BAAALgADCgkJFwAAAA==.Cayusevoid:BAAALgADCgcJBwAAAA==.',
Ce='Celestiall:BAAALgAECgYJBgAAAA==.Ceridwyn:BAAALgAECgQJBQAAAA==.',
Ch='Chariscrushr:BAAALgAECgQJCAABLgAFFAQJBgAKAPMHAA==.Cheesecurd:BAABLgAECn8VAAMUAAgJKhatAQDnAQAUAAgJKhatAQDnAQAVAAMJsAuwAwCAAAAAAA==.Chen:BAAALgADCgIJAgAAAA==.Choal:BAAALgAECgEJAQAAAA==.Chokaho:BAAALgAECgQJBgAAAA==.Chubberoni:BAAALgAECgUJBwAAAA==.',
Ci='Cinnamongirl:BAAALgAECgcJEgAAAA==.',
Co='Corahin:BAABLgAECn8bAAISAAYJGxASRAA5AQASAAYJGxASRAA5AQAAAA==.Corious:BAAALgAECgQJCQAAAA==.Cosmos:BAAALgAECgYJDQAAAA==.Cougarhunter:BAAALgAECgkJEAAAAA==.',
Cr='Crixux:BAAALgADCgMJAQAAAA==.Crokus:BAAALgADCggJCAAAAA==.',
Cu='Cuecumba:BAABLgAECn8uAAIWAAkJICZ2AABbAwAWAAkJICZ2AABbAwAAAA==.',
Da='Daemonerror:BAAALgAECgUJBQABLgAECgkJTgAXAKIjAA==.Dalren:BAACLgAFFH8qAAMYAAgJJh0YCAC5AQAYAAgJJh0YCAC5AQAZAAMJUBNDBABmAAAuAAQKf00AAxgACQnIJf0BAGEDABgACQnIJf0BAGEDABkABgnyIEMMABcCAAAA.Dalryn:BAAALgAECgYJDQABLgAFFAgJKgAYACYdAA==.Dalvix:BAAALgADCgEJAQABLgAECgkJJgAGAFogAA==.Damballàh:BAAALgADCgIJAgAAAA==.Damocles:BAABLgAECn8YAAIBAAYJlwwqyAD9AAABAAYJlwwqyAD9AAAAAA==.Danazel:BAAALgADCgMJBQAAAA==.Dartagnan:BAACLgAFFH8QAAIaAAMJnhwUUQAIAQAaAAMJnhwUUQAIAQAuAAQKfygAAxoACQnLHTpJAMYBABoABwkLHzpJAMYBABsABgn3FI8bANEAAAAA.Darthmaul:BAABLgAECn8wAAIDAAkJyhHNHwDKAQADAAkJyhHNHwDKAQAAAA==.',
De='Deay:BAAALgADCgQJAQAAAA==.Delexa:BAAALgADCgkJQAAAAA==.Demonicnugie:BAAALgADCgEJAQAAAA==.Dendiian:BAABLgAECn8XAAIcAAgJ0xIeJwAdAQAcAAgJ0xIeJwAdAQAAAA==.',
Di='Didipullthat:BAAALgAECgcJCgABLgAFFAMJCAAGADgNAA==.Diem:BAABLgAECn8dAAIaAAgJyw1rQQCqAQAaAAgJyw1rQQCqAQAAAA==.Dinendal:BAAALgADCgYJBgAAAA==.Dirtydotss:BAABLgAECn8VAAMFAAcJFwfXEgD/AAAFAAYJYQbXEgD/AAAEAAYJ5wSTzQC3AAAAAA==.Discernment:BAAALgAECgEJAQAAAA==.Divigitives:BAAALgAECgQJBAAAAA==.',
Do='Docrivan:BAAALgAECgYJCwAAAA==.Docsassist:BAAALgAECgMJAwABLgAECgYJCwAdAAAAAA==.Doregit:BAABLgAECn83AAIPAAkJIx/LCwCrAgAPAAkJIx/LCwCrAgAAAA==.Dowedoes:BAABLgAECn89AAIMAAkJgheVNgAnAgAMAAkJgheVNgAnAgAAAA==.',
Dr='Drachula:BAABLgAECn8cAAIeAAgJ4BSlOwDAAQAeAAgJ4BSlOwDAAQAAAA==.Dracultra:BAAALgAECgUJBwABLgAFFAMJBQANAJokAA==.Drakcheese:BAAALgADCgUJBQAAAA==.Dreolan:BAABLgAECn9VAAIfAAkJ5xqKFACmAgAfAAkJ5xqKFACmAgAAAA==.Drnatemonk:BAABLgAFFH8OAAIXAAYJSg6tDgBcAQAXAAYJSg6tDgBcAQABLgAFFAcJMgAIAA0jAA==.Drynnai:BAAALgADCgEJAgAAAA==.',
Dy='Dyala:BAACLgAFFH8QAAMfAAMJjg8URACjAAAfAAMJjg8URACjAAADAAMJMwSSOgCOAAAuAAQKfyMAAx8ACQkDErNmAAABAB8ACQkDErNmAAABAAMABAkoDt5OANEAAAAA.',
['Dö']='Dönövan:BAABLgAECn8zAAIMAAkJAhX9RQD0AQAMAAkJAhX9RQD0AQAAAA==.',
Eg='Eggyolk:BAABLgAECn8YAAIcAAkJERIjAgDEAQAcAAkJERIjAgDEAQAAAA==.',
El='Elapst:BAAALgAECgIJAgAAAA==.Elastwo:BAAALgADCgcJEgABLgAECgIJAgAdAAAAAA==.Eloise:BAABLgAECn8aAAILAAgJMw+dLQBgAQALAAgJMw+dLQBgAQAAAA==.Elvenbane:BAABLgAECn8nAAIgAAkJrRO3HADfAQAgAAkJrRO3HADfAQAAAA==.',
Em='Emily:BAAALgAECgYJDAAAAA==.Emry:BAAALgADCgYJBgABLgAECgcJHQAXADkPAA==.',
En='Enable:BAEBLgAECn8gAAIhAAkJVRxUCgCOAgAhAAkJVRxUCgCOAgABLgAECgkJNAARAE8iAA==.',
Ep='Epictool:BAAALgAECggJCwAAAA==.',
Et='Ethereal:BAAALgAECgEJAQAAAA==.Etö:BAAALgAECgUJBQABLgAECgQJBgAdAAAAAA==.',
Ew='Ew:BAACLgAFFH8JAAIaAAMJRxaIJgDmAAAaAAMJRxaIJgDmAAAuAAQKfxUAAhoACAk0HWwmACACABoACAk0HWwmACACAAEuAAUUAgkJAAgA0x4A.',
Ex='Extrathick:BAAALgAECgMJAwAAAA==.',
Fa='Fabel:BAEBLgAECn80AAIRAAgJTyJeBwBoAgARAAgJTyJeBwBoAgAAAA==.Falahad:BAAALgAECgEJAQABLgAFFAMJDwADAD4OAA==.Faltree:BAACLgAFFH8PAAMDAAMJPg7XMwCxAAADAAMJPg7XMwCxAAAfAAIJuhVnUgB6AAAuAAQKfyEABB8ACQkeFf5TAFcBAB8ACAkrFP5TAFcBAAMACAkOF0wyAFEBACIAAQnfAUo6AB8AAAAA.Fathershale:BAAALgAECgUJCAAAAA==.',
Fi='Firelord:BAAALgADCgEJAQAAAA==.Fistingmilk:BAAALgAECgYJBwAAAA==.',
Fo='Foulcor:BAABLgAECn8dAAMNAAkJ7B6LFwBNAgANAAgJlB6LFwBNAgAMAAcJRhEwmQBDAQAAAA==.',
Fr='Freakadeek:BAABLgAECn8VAAQjAAkJaw1DIQDEAAAIAAUJ0Aid1wDeAAAjAAMJnhdDIQDEAAAJAAYJgwTWTgBXAAAAAA==.Freâkadeek:BAAALgAECgIJBQABLgAECgkJFQAjAGsNAA==.Freäk:BAAALgADCgMJAwABLgAECgkJFQAjAGsNAA==.Frieren:BAABLgAECn8+AAIBAAkJsBY3PwAfAgABAAkJsBY3PwAfAgAAAA==.Frink:BAAALgAECgEJAQABLgAECgkJPQAkAOEkAA==.Frostlord:BAAALgAECgIJAgAAAA==.',
Fu='Fundetected:BAAALgAFFAIJAgABLgAFFAMJCAAGADgNAA==.Furyofthenug:BAAALgAECgQJBAAAAA==.Fuzzywuzzy:BAAALgAECgUJBQABLgAECgYJHQATALgdAA==.',
Ga='Gabbyo:BAABLgAECn8lAAIfAAkJ/Ad2VAA+AQAfAAkJ/Ad2VAA+AQAAAA==.Galadorn:BAABLgAECn8mAAIGAAkJWiC/DwDFAgAGAAkJWiC/DwDFAgAAAA==.Gallgamesh:BAAALgADCgIJAgAAAA==.Garfall:BAAALgAECgcJDgAAAA==.Garga:BAAALgADCgMJBAABLgAECgQJBAAdAAAAAA==.',
Ge='Geirvaldr:BAAALgAECgYJBgAAAA==.Gerdash:BAAALgAECgMJBAAAAA==.Gerred:BAACLgAFFH8JAAIOAAMJPRj0IwDfAAAOAAMJPRj0IwDfAAAuAAQKfyUAAw4ACQndHFUBAM8BAA4ACQm7HFUBAM8BAA8ABAlFFB5mAMQAAAAA.',
Gh='Ghallow:BAABLgAECn8gAAIQAAkJnBt2AQDAAQAQAAkJnBt2AQDAAQAAAA==.Ghosty:BAACLgAFFH8JAAIUAAQJOxWRIAAhAQAUAAQJOxWRIAAhAQAuAAQKfyoAAhQABwlQIFgUAP8BABQABwlQIFgUAP8BAAAA.',
Gi='Gimp:BAAALgAECgEJAgAAAA==.',
Gl='Gladur:BAABLgAFFH8GAAMHAAYJyAzzHwDZAAAHAAUJtwzzHwDZAAAXAAEJmQGAZQAxAAABLgAFFAgJHwABAFoXAA==.',
Go='Goldenflame:BAAALgAECgUJBwAAAA==.Goldenlily:BAAALgAECgYJEgAAAA==.Goldenmunc:BAABLgAECn8tAAIBAAkJNxfsNQBBAgABAAkJNxfsNQBBAgAAAA==.Goldenone:BAAALgAECggJCQAAAA==.Goldenpants:BAABLgAECn8nAAIPAAkJjxM8IgDgAQAPAAkJjxM8IgDgAQAAAA==.',
Gr='Grandesaxx:BAAALgAECgEJAQAAAA==.Grievous:BAABLgAECn89AAIWAAkJOyW4AABKAwAWAAkJOyW4AABKAwAAAA==.',
['Gû']='Gûrth:BAAALgADCgcJBwAAAA==.',
Ha='Hailmary:BAABLgAECn8oAAILAAkJEiV8AQCoAwALAAkJEiV8AQCoAwAAAA==.Halcrux:BAAALgAECgIJAgAAAA==.Halvard:BAAALgADCgMJBQAAAA==.Harusen:BAABLgAECn8cAAIlAAkJFR9EAgCmAgAlAAkJFR9EAgCmAgAAAA==.Havgnwltrav:BAAALgADCgcJBgAAAA==.',
He='Healaga:BAAALgAECgYJBgABLgAECgkJPAAIAMobAA==.',
Hh='Hhoonnzz:BAABLgAFFH8NAAIUAAMJChOmJwDrAAAUAAMJChOmJwDrAAABLgAFFAIJCQAIANMeAA==.',
Hi='Hildalsind:BAAALgADCgkJCQABLgAFFAMJCQABAIMdAA==.',
Ho='Homestar:BAAALgADCgEJAQAAAA==.Hooll:BAAALgAECgIJAgAAAA==.Hornreaper:BAABLgAECn8bAAIYAAYJ5hfvJACVAQAYAAYJ5hfvJACVAQAAAA==.Hotshot:BAAALgAECgMJAwAAAA==.',
Hu='Hubbabubbajr:BAAALgAECgMJAwABLgAECgkJMwAfAIIbAA==.Hubert:BAAALgADCgEJAgAAAA==.Huracan:BAAALgAECgEJAgAAAA==.Hurin:BAAALgAECgcJDgAAAA==.Huur:BAAALgAECgEJAQABLgAECgEJAQAdAAAAAA==.',
Hy='Hyetta:BAAALgAECgQJBgABLgAECgkJHAAlABUfAA==.Hyir:BAAALgADCgYJBwABLgAFFAQJHgAHAOEfAA==.',
Ic='Icecold:BAAALgAECgQJBAAAAA==.',
Il='Ilavengu:BAAALgAECgMJBQABLgAFFAQJFgAeADEmAA==.Illiya:BAABLgAECn8VAAILAAYJ+AsxRADZAAALAAYJ+AsxRADZAAAAAA==.',
Ir='Irôn:BAAALgAECgEJAQAAAA==.',
Iu='Iutara:BAAALgAECgYJDAAAAA==.',
Ja='Jaalein:BAAALgADCgcJDgAAAA==.Jayonor:BAABLgAECn80AAQSAAkJthVkGgAOAgASAAkJthVkGgAOAgAQAAYJ9we4GgAeAQAeAAcJ5AZmcQAIAQAAAA==.',
Je='Jek:BAAALgAECgYJBgAAAA==.',
Jo='Joryu:BAAALgADCgIJAwAAAA==.',
Ju='Juicycucci:BAAALgAECgcJEgABLgAFFAMJCAAGADgNAA==.',
Ka='Kaevrielle:BAECLgAFFH8KAAIWAAMJFhfUCADGAAAWAAMJFhfUCADGAAAuAAQKfx4AAxYACQmOG2IHAAwCABYACQmOG2IHAAwCACYAAQlWCol4ACcAAAAA.Kaison:BAABLgAECn8XAAMgAAkJEQigMQBVAQAgAAkJEQigMQBVAQAnAAcJBAtMNQBAAQABLgAECgkJIAAGAA0VAA==.Kaladîn:BAAALgAECgMJAwABLgAFFAgJHwABAFoXAA==.Kalii:BAAALgADCgQJBAAAAA==.Kamel:BAAALgADCgcJDQAAAA==.Kardin:BAAALgADCgEJAQAAAA==.Karwin:BAABLgAECn8bAAIBAAgJ/xRCaACsAQABAAgJ/xRCaACsAQAAAA==.Katakuri:BAAALgAECgEJAgAAAA==.',
Ke='Keeper:BAAALgAFFAIJAwABLgAFFAUJDwAMAJsiAA==.Keeperodark:BAACLgAFFH8FAAIEAAMJXgbbMwCkAAAEAAMJXgbbMwCkAAAuAAQKfxgAAgQACAkrF8EGAGYBAAQACAkrF8EGAGYBAAEuAAUUBQkPAAwAmyIA.Keeperolight:BAACLgAFFH8PAAIMAAUJmyLtEwAvAQAMAAUJmyLtEwAvAQAuAAQKf1MAAwwACQlUJeYEAFADAAwACQlUJeYEAFADAA0AAQmBGBSQAEAAAAAA.Kemanorel:BAAALgADCgcJDgABLgAECgkJJwAgAK0TAA==.Kerli:BAAALgADCgEJAQAAAA==.',
Ki='Kianth:BAAALgADCgkJEgAAAA==.Killkat:BAABLgAECn8uAAIBAAkJgxhiNQBDAgABAAkJgxhiNQBDAgAAAA==.',
Ko='Kodera:BAABLgAECn8dAAMTAAYJuB3ZDQDyAQATAAYJuB3ZDQDyAQAZAAQJwhzKDgAfAQAAAA==.Koojo:BAAALgAECgcJCAAAAA==.Kosma:BAAALgAECgYJBgAAAA==.Kovae:BAAALgADCgEJAQAAAA==.',
Kr='Kraken:BAAALgADCgUJBQAAAA==.',
Ku='Kusheddruid:BAAALgADCgMJBQAAAA==.',
Ky='Kyaritin:BAAALgAECgMJAwABLgAECgYJCgAdAAAAAA==.Kyokei:BAAALgAECgEJAQAAAA==.',
La='Laiho:BAAALgADCgUJCAAAAA==.Lans:BAABLgAECn8UAAQoAAkJIQ0hDQD4AAAoAAUJ2AkhDQD4AAABAAQJ1Q80zAD3AAApAAQJAwkBCQDKAAAAAA==.Larew:BAACLgAFFH8FAAIMAAMJbgfXfgC4AAAMAAMJbgfXfgC4AAAuAAQKfzEAAgwACQnfGfMnAGQCAAwACQnfGfMnAGQCAAAA.Lazytemplar:BAAALgADCgMJAwABLgAFFAMJAwAdAAAAAA==.',
Le='Lealla:BAABLgAECn89AAIDAAkJlCI8BQAIAwADAAkJlCI8BQAIAwAAAA==.Lechevalier:BAAALgAFFAIJBAABLgAFFAMJCAAGADgNAA==.Leodin:BAAALgAECgEJAgAAAA==.Leorus:BAAALgAECgIJAgAAAA==.Lethhunt:BAACLgAFFH8bAAMbAAgJNgs+EABdAQAbAAgJlQk+EABdAQAaAAQJpAx7KADeAAAuAAQKfy4AAxsACQncHpwGACgCABsACQlgHpwGACgCABoAAgk+JFKHANIAAAAA.',
Li='Lilmistfox:BAAALgAECgUJBwABLgAFFAQJFgAeADEmAA==.Lioh:BAAALgAECgQJBAAAAA==.Lizardgang:BAABLgAECn8XAAIaAAcJERZLGgDHAAAaAAcJERZLGgDHAAAAAA==.',
Lo='Loganshu:BAAALgAECgkJDgAAAA==.Lokan:BAACLgAFFH8RAAMkAAMJWRkcHQDoAAAkAAMJWRkcHQDoAAAaAAEJwgjlqABFAAAuAAQKfywAAyQACQlHHqkIAJQCACQACQlHHqkIAJQCABoAAQn+CiMyATYAAAAA.Lots:BAACLgAFFH8RAAIEAAMJhhtjZwD3AAAEAAMJhhtjZwD3AAAuAAQKfycAAwQACQktIgIrAC4CAAQACAliIgIrAC4CAAIABAngHkcsAA0BAAAA.',
Lu='Ludacast:BAAALgADCgIJAgAAAA==.Ludafists:BAAALgADCgcJDAAAAA==.Ludakris:BAABLgAECn8eAAIRAAkJfxhLCwATAgARAAkJfxhLCwATAgAAAA==.Lumanoth:BAAALgAECgYJBgAAAA==.',
Ly='Lyna:BAABLgAECn8gAAIeAAkJpROdPwCvAQAeAAkJpROdPwCvAQAAAA==.Lynaya:BAAALgADCgIJAgAAAA==.',
['Lí']='Líonheart:BAABLgAECn8eAAMNAAcJYBePPgBKAQANAAcJYBePPgBKAQAMAAYJFgvJ0wDuAAAAAA==.',
['Lî']='Lîghtless:BAACLgAFFH8PAAIBAAYJBhqgGABoAQABAAYJBhqgGABoAQAuAAQKfxcAAgEACAmfJUchAO4CAAEACAmfJUchAO4CAAAA.',
['Lú']='Lúckally:BAAALgADCgQJBAABLgAECgYJCgAdAAAAAA==.Lúckÿ:BAAALgAECgYJCgAAAA==.',
Ma='Magetheo:BAAALgADCgIJAgAAAA==.Magicpanda:BAAALgAECgUJCwAAAA==.Mahina:BAAALgAECgMJAgAAAA==.Malik:BAAALgADCgIJAgAAAA==.Marcille:BAABLgAECn8nAAIBAAgJ2RO7dwCKAQABAAgJ2RO7dwCKAQAAAA==.Masyledian:BAAALgAECgMJBwABLgAECggJIwAIAPwaAA==.Mathor:BAAALgAECgEJAgAAAA==.Mavrbg:BAAALgAECgQJBQAAAA==.Mayhaps:BAABLgAECn9EAAMaAAkJFRuBJwBBAgAaAAkJFRuBJwBBAgAbAAEJZACpmgAYAAAAAA==.',
Mc='Mcbain:BAABLgAECn89AAIkAAkJ4STWAQA9AwAkAAkJ4STWAQA9AwAAAA==.',
Me='Melinia:BAAALgAECgEJAQABLgAECgEJAgAdAAAAAA==.Melrine:BAAALgADCgMJAwAAAA==.Mentaltitty:BAABLgAECn8gAAIBAAkJgxKGSwD5AQABAAkJgxKGSwD5AQAAAA==.Meret:BAAALgADCgMJBQAAAA==.',
Mi='Minerwor:BAAALgAECgcJCwAAAA==.Mirrayla:BAAALgADCgYJBgAAAA==.Misty:BAAALgADCgYJBgAAAA==.',
Mm='Mmisty:BAABLgAECn9IAAIDAAkJghmMDwBnAgADAAkJghmMDwBnAgAAAA==.',
Mo='Moarthretplz:BAAALgAECgUJCQABLgAFFAQJFgAeADEmAA==.Mohji:BAAALgAFFAEJAQABLgAFFAkJHQAnAC8RAA==.Moldynuggets:BAAALgAECgYJDgAAAA==.Momometaru:BAABLgAECn8kAAQEAAkJgRaCQQDYAQAEAAkJfhOCQQDYAQACAAUJNhRyJgAsAQAFAAMJzxrGJgCMAAAAAA==.Monsterbee:BAABLgAECn9MAAIEAAkJ1BXiKwAqAgAEAAkJ1BXiKwAqAgAAAA==.',
Mu='Mustypizza:BAABLgAECn8uAAICAAkJihjJBAAsAgACAAkJihjJBAAsAgAAAA==.',
Mx='Mxicancowboy:BAAALgADCgEJAgAAAA==.',
My='Mystery:BAABLgAECn89AAMTAAkJNiC9AgAzAwATAAkJNiC9AgAzAwAZAAUJXhELEAAKAQAAAA==.',
['Mê']='Mêøwzêr:BAAALgAECggJEwAAAA==.',
['Mÿ']='Mÿst:BAAALgAECgMJBAAAAA==.',
Na='Nak:BAAALgAECgYJBgAAAA==.Nanuk:BAAALgADCgQJBAAAAA==.Narashi:BAAALgAECgQJCAAAAA==.Naril:BAAALgADCgUJBQAAAA==.Nats:BAABLgAECn8qAAIeAAkJ9w/5DQDyAAAeAAkJ9w/5DQDyAAAAAA==.',
Ne='Neameny:BAABLgAECn89AAIaAAkJGBObOwDxAQAaAAkJGBObOwDxAQAAAA==.',
Ni='Nianji:BAAALgADCgYJDgAAAA==.Nightstar:BAAALgAECgEJAQAAAA==.Nightworld:BAAALgADCgcJDgAAAA==.',
No='Noctum:BAAALgAECggJDwAAAA==.Nordicpally:BAAALgADCgQJBAAAAA==.Notbomba:BAAALgAECgEJAwAAAA==.Notgim:BAAALgADCggJCAAAAA==.',
Nu='Nualrossan:BAAALgADCgYJCAAAAA==.Nubrac:BAAALgAECgkJEwAAAA==.',
Ny='Nylux:BAAALgAECgYJDwAAAA==.',
Ob='Oblivion:BAACLgAFFH8LAAIEAAQJnhkZJgDSAAAEAAQJnhkZJgDSAAAuAAQKfz4AAwQACQmfJLUGACUDAAQACQmfJLUGACUDAAIAAQkAAFFdAFcAAAAA.',
Og='Ogrebreath:BAAALgAECgUJBwAAAA==.',
Oo='Oostren:BAAALgAECgEJAgAAAA==.',
Or='Orsyp:BAAALgADCgkJGgAAAA==.',
Pa='Palockie:BAAALgADCgEJAQAAAA==.Pandas:BAABLgAECn8hAAISAAkJAhF6JwCxAQASAAkJAhF6JwCxAQAAAA==.Partyrocker:BAABLgAECn8XAAIkAAcJag79KgBKAQAkAAcJag79KgBKAQABLgAECgkJFQAjAGsNAA==.Paynë:BAAALgAECgYJDQAAAA==.',
Pi='Pixae:BAACLgAFFH8PAAITAAMJjwdDIwCHAAATAAMJjwdDIwCHAAAuAAQKfyEAAhMACAm5Cm8ZAD8BABMACAm5Cm8ZAD8BAAAA.Pixiechaos:BAAALgAECgQJCAAAAA==.',
Po='Poliahu:BAABLgAECn8dAAIaAAkJFwwxFQDwAAAaAAkJFwwxFQDwAAAAAA==.Porthoss:BAAALgADCggJDwAAAA==.Powerplant:BAACLgAFFH8ZAAIaAAgJViDRDQD6AQAaAAgJViDRDQD6AQAuAAQKfyYAAhoACQkgJCgIAA4DABoACQkgJCgIAA4DAAAA.Poyoram:BAAALgADCgEJAQAAAA==.',
Pr='Pryi:BAAALgAECgIJAgABLgAFFAMJBwAMAO0IAA==.',
Py='Pyralys:BAABLgAECn85AAMLAAkJGBFmHADjAQALAAkJGBFmHADjAQAgAAMJqQJBiAAxAAAAAA==.',
['Pä']='Pärts:BAAALgAECgUJBQABLgAFFAYJCwAkAEITAA==.',
Qu='Questus:BAAALgADCgUJBQAAAA==.Quizac:BAAALgADCgMJBQAAAA==.',
Ra='Rabidghost:BAAALgADCgYJBgAAAA==.Ragedk:BAAALgAFFAMJAwAAAA==.Ragemonk:BAAALgAECgUJDgABLgAFFAMJAwAdAAAAAA==.Ragetality:BAAALgAFFAIJBAABLgAFFAMJAwAdAAAAAA==.Rahken:BAAALgADCgQJBAAAAA==.Rakthera:BAAALgADCgcJBwAAAA==.Rallaster:BAAALgAECgYJBgABLgAECgkJJwAgAK0TAA==.Ramaria:BAAALgADCgkJCQABLgAECgkJJgAGAFogAA==.Raserei:BAABLgAFFH8KAAIPAAMJIhf2LwDwAAAPAAMJIhf2LwDwAAAAAA==.Rasputain:BAAALgADCgYJCgAAAA==.Rasputein:BAAALgADCgcJBwAAAA==.Rattelyr:BAAALgAECgYJDgAAAA==.Ravara:BAAALgADCgYJBgABLgAECgkJJgAGAFogAA==.Rawb:BAACLgAFFH8LAAIPAAMJjxTzMwDhAAAPAAMJjxTzMwDhAAAuAAQKfx8AAw8ACAmyG74YACgCAA8ACAmyG74YACgCAAoABglmFr0uAM0AAAEuAAUUAgkJAAgA0x4A.Razgaurd:BAAALgAECgMJAwAAAA==.',
Re='Recolada:BAAALgAECggJCAAAAA==.Regice:BAAALgAECgcJBwABLgAFFAQJFQAJAC8bAA==.Regicee:BAACLgAFFH8VAAMJAAQJLxs3CQAxAQAJAAQJLxs3CQAxAQAIAAEJGwkLkgA5AAAuAAQKf1MAAwkACQkKI10EAO8CAAkACQkKI10EAO8CAAgABwm5Ef8XALcAAAAA.Retam:BAAALgAECgcJDgAAAA==.Revakos:BAAALgADCgMJAwAAAA==.',
Rh='Rhysandra:BAAALgAECgQJCQAAAA==.',
Ri='Ribble:BAAALgADCgMJAwAAAA==.Riffraff:BAAALgAFFAcJAQAAAA==.Rindou:BAAALgAECgkJBAAAAA==.Ripcord:BAAALgAECgUJDwAAAA==.Ripem:BAAALgADCgYJBgAAAA==.Ripperoni:BAAALgAECgcJDQAAAA==.Rizek:BAAALgAECgUJBgABLgAECgcJHQAXADkPAA==.Rizzx:BAAALgAECgEJAQAAAA==.',
Ro='Rockdyou:BAABLgAECn8nAAIIAAkJ+R51JABzAgAIAAkJ+R51JABzAgAAAA==.Roglef:BAAALgAECgQJCQAAAA==.Rogmesh:BAAALgAECgcJEAAAAA==.Rotlobster:BAABLgAECn8aAAIFAAkJAB71AQDEAgAFAAkJAB71AQDEAgAAAA==.Roxxy:BAAALgAECgQJBAAAAA==.',
Ru='Rundvelt:BAACLgAFFH8RAAIRAAMJeA0IDwCQAAARAAMJeA0IDwCQAAAuAAQKfyQAAhEACQlSEQwVAIABABEACQlSEQwVAIABAAAA.',
['Rà']='Ràgëquit:BAAALgAECgEJAQAAAA==.',
Sa='Sage:BAAALgADCgcJCAAAAA==.Sandwich:BAAALgAECgcJCAAAAA==.Saphíra:BAAALgAFFAIJAQABLgAFFAgJHwABAFoXAA==.Sapkick:BAAALgAECgQJBwAAAA==.',
Se='Serdragon:BAAALgADCgQJBAAAAA==.Sertian:BAAALgAECgEJAQAAAA==.Servoid:BAAALgAECgUJCQAAAA==.',
Sh='Shando:BAAALgAECgEJAQAAAA==.Shiftstyle:BAEALgAECgEJAQAAAA==.Shtanky:BAACLgAFFH8PAAIKAAMJaBFHHgClAAAKAAMJaBFHHgClAAAuAAQKfyQAAgoACQnHD7MWAI4BAAoACQnHD7MWAI4BAAAA.',
Si='Silentsocks:BAAALgAECgUJDAAAAA==.Sixsixsix:BAAALgAECgcJCgABLgAFFAIJCQAIANMeAA==.',
Sk='Skoogz:BAABLgAECn8WAAMJAAgJiRJZJgAhAQAJAAgJQRJZJgAhAQAIAAQJ5A+a1QDhAAAAAA==.',
Sm='Smackdowne:BAAALgADCgIJAgAAAA==.',
So='Sofakingséxy:BAAALgAECgMJAwABLgAFFAMJCAAGADgNAA==.Soggyy:BAAALgADCgYJCwAAAA==.Solar:BAABLgAECn8VAAQHAAcJyRkxLwBtAQAHAAYJCxYxLwBtAQAhAAYJrhzoOABmAQAXAAEJUwL71wAaAAAAAA==.Soulfulgingr:BAABLgAECn8lAAISAAgJyRQLAwC9AQASAAgJyRQLAwC9AQAAAA==.',
Sp='Spiteful:BAAALgAECgQJBAAAAA==.',
St='Starlagosa:BAAALgADCgYJCQAAAA==.Sturm:BAAALgAECgMJAwAAAA==.Styx:BAAALgAECgMJAwAAAA==.',
Su='Sunbake:BAABLgAECn8bAAMLAAgJ7QXJCgClAAALAAgJ7QXJCgClAAAgAAEJ5gYqkAAqAAAAAA==.',
Sw='Sweetbbyraze:BAACLgAFFH8dAAMZAAYJvxyoBQAIAQAYAAYJeRmaIQBTAQAZAAQJQCGoBQAIAQAuAAQKfyYAAxkACAkpIVIGAJACABkABwm8IVIGAJACABgAAwnyHI9rAJkAAAAA.',
Sy='Sylaena:BAABLgAECn8oAAIbAAgJVQoeFAAgAQAbAAgJVQoeFAAgAQAAAA==.Sylvrstorm:BAAALgAECgcJDQAAAA==.',
['Së']='Sërënity:BAABLgAECn8XAAIfAAUJjg6UCwCoAAAfAAUJjg6UCwCoAAAAAA==.',
['Sí']='Sín:BAAALgAECgcJDAABLgAFFAIJCQAIANMeAA==.',
Ta='Talidh:BAAALgADCgIJAgAAAA==.Talipally:BAACLgAFFH8HAAIMAAMJ7QjMewC+AAAMAAMJ7QjMewC+AAAuAAQKfxwAAgwACQkyEM14AH0BAAwACQkyEM14AH0BAAAA.Talishammy:BAAALgAECgMJAwABLgAFFAMJBwAMAO0IAA==.Taliwhacker:BAAALgAFFAEJAQABLgAFFAMJBwAMAO0IAA==.Talonleafgrd:BAAALgAECgkJCgAAAA==.Tanaka:BAABLgAECn8gAAIIAAgJgBMJWgC4AQAIAAgJgBMJWgC4AQAAAA==.Tanisong:BAAALgAECgQJDQAAAA==.Tassadar:BAAALgAECgUJCAAAAA==.',
Te='Teldo:BAAALgADCgMJBQAAAA==.Tepeyollotl:BAAALgADCgEJAQAAAA==.Terayus:BAAALgADCgcJDAAAAA==.Teyliah:BAAALgADCgMJAwAAAA==.',
Tf='Tf:BAAALgAECgYJBgABLgAFFAIJCQAIANMeAA==.',
Th='Thalor:BAAALgAECgUJBQABLgAFFAQJBgAKAPMHAA==.Thekingpunch:BAABLgAECn9OAAMXAAkJoiO5BwAhAwAXAAkJoiO5BwAhAwAHAAEJahZWjwBCAAAAAA==.Thenle:BAAALgADCggJFwAAAA==.Thline:BAAALgADCgMJBQAAAA==.Thunderblitz:BAABLgAECn8rAAINAAkJdgknMwCIAQANAAkJdgknMwCIAQAAAA==.Thurmus:BAAALgADCgkJQAAAAA==.Thánatos:BAAALgADCgMJAwAAAA==.',
Ti='Tillwar:BAABLgAECn87AAIPAAkJKh2pEAByAgAPAAkJKh2pEAByAgAAAA==.Tinymonk:BAAALgAECgMJAwAAAA==.',
To='Tofu:BAACLgAFFH8LAAIIAAMJ3B16hwD6AAAIAAMJ3B16hwD6AAAuAAQKf0UAAwgACQnEHvEVAMQCAAgACQnEHvEVAMQCAAkABwmjFrwaAIgBAAAA.Tokanya:BAAALgAECgEJAQAAAA==.Tortillachip:BAAALgAECgEJAgAAAA==.Toxidot:BAAALgAECgEJAQAAAA==.',
Tr='Treibh:BAABLgAECn8qAAIfAAkJCxilFwCJAgAfAAkJCxilFwCJAgAAAA==.Trelephant:BAAALgAECgMJBQAAAA==.Trulydps:BAABLgAECn8vAAIaAAkJ4xQKLwAgAgAaAAkJ4xQKLwAgAgAAAA==.Trulyog:BAAALgAECgQJBAABLgAECgkJLwAaAOMUAA==.',
Tu='Tubbsmcgee:BAACLgAFFH8fAAIeAAYJ6x8cCABFAgAeAAYJ6x8cCABFAgAuAAQKfyUAAh4ACQkrJLgHAPkCAB4ACQkrJLgHAPkCAAEuAAUUBgkfAB4A6x8A.Tukkit:BAAALgAECgYJDwAAAA==.',
Tw='Twistedshot:BAAALgADCggJCAAAAA==.Twizzler:BAABLgAECn9TAAIBAAkJZQi/fgB6AQABAAkJZQi/fgB6AQAAAA==.',
Ty='Tyraniik:BAAALgADCgYJCAAAAA==.',
['Të']='Tërris:BAABLgAECn8eAAIJAAkJQBHkGgCGAQAJAAkJQBHkGgCGAQAAAA==.',
['Tî']='Tîlldeath:BAAALgAECgUJBwAAAA==.',
['Tõ']='Tõaster:BAAALgADCgQJBAABLgAECgkJJgAGAFogAA==.',
Uj='Uji:BAAALgADCgEJAQAAAA==.',
Ur='Urowndad:BAAALgAECgUJBQABLgAECggJFgAMAL0TAA==.Urownmother:BAAALgADCgUJBQABLgAECggJFgAMAL0TAA==.',
Va='Vaellian:BAAALgAECgYJDAAAAA==.Vallez:BAECLgAFFH8WAAMNAAMJISDGIwACAQANAAMJISDGIwACAQAMAAMJ/g1fcwDMAAAuAAQKfyoAAw0ACQmqHQMSAIMCAA0ACQmqHQMSAIMCAAwAAwmiDWpGAWYAAAAA.Vanillaghost:BAAALgADCgIJAQAAAA==.Varnusshadow:BAAALgAECgUJBgAAAA==.',
Ve='Vearik:BAAALgAECgUJBwAAAA==.Velladoree:BAABLgAECn8mAAIXAAgJlAvHEADUAAAXAAgJlAvHEADUAAAAAA==.Vendaryn:BAAALgADCggJCAAAAA==.Vexahlia:BAAALgADCgMJAwAAAA==.',
Vg='Vgurlpally:BAAALgADCgYJCQAAAA==.',
Vy='Vynlorlan:BAAALgADCgMJAwABLgAECgMJBAAdAAAAAA==.',
Wa='Walkindead:BAAALgAECgQJBgAAAA==.Waveygravee:BAAALgAECgIJAwAAAA==.Wavyghoul:BAAALgAECgEJAQAAAA==.Wavygraivy:BAABLgAECn8fAAIeAAgJURMXTACAAQAeAAgJURMXTACAAQAAAA==.Wavygravey:BAAALgADCgQJBAAAAA==.',
We='Wedragon:BAABLgAECn8YAAMXAAYJGxr3BAC9AQAXAAYJGxr3BAC9AQAHAAMJygdFbgB1AAAAAA==.',
Wh='Wheelchair:BAACLgAFFH8LAAIIAAQJOxv7bwAeAQAIAAQJOxv7bwAeAQAuAAQKfxwAAggACAkSJF0SAA4DAAgACAkSJF0SAA4DAAAA.',
Wo='Woofwoof:BAAALgAFFAIJAgAAAA==.',
Wu='Wullemage:BAAALgADCgcJEwABLgAFFAcJHwAUALAaAA==.',
['Wå']='Wåsp:BAABLgAECn9PAAIGAAkJAxAHUACVAQAGAAkJAxAHUACVAQABLgAECgkJGAAcABESAA==.',
Xb='Xb:BAAALgAECgcJBQAAAA==.',
Xh='Xhexana:BAABLgAECn84AAIeAAkJTRcBHQBkAgAeAAkJTRcBHQBkAgABLgAECgkJPQAaABgTAA==.',
Xi='Xiaopo:BAAALgAECgEJAQABLgAFFAQJFgAeADEmAA==.',
Xr='Xrael:BAAALgAECgEJAQABLgAFFAMJEwAHACMiAA==.Xrayl:BAACLgAFFH8TAAMHAAMJIyKYEwAgAQAHAAMJIyKYEwAgAQAhAAMJxAxDOwC5AAAuAAQKfyUAAwcACQnoIMwNAGkCAAcACAmrIcwNAGkCACEAAQmOG/N9AE8AAAAA.',
Xz='Xzerocool:BAABLgAECn8WAAQMAAgJvRNCiQBeAQAMAAgJvRNCiQBeAQARAAIJshNmPABqAAANAAEJmQOznQAiAAAAAA==.',
Ya='Yaniaa:BAAALgADCgcJBwAAAA==.Yannii:BAAALgADCgcJDgAAAA==.',
Ye='Yenko:BAAALgADCgIJAgAAAA==.',
Yo='Yolo:BAAALgADCgcJCwAAAA==.Yoshikazu:BAAALgAECggJCwAAAA==.Yoyoboy:BAAALgAECgIJBAAAAA==.',
Za='Zaarah:BAAALgAECgYJDAAAAA==.',
Ze='Zellek:BAAALgADCgEJAQAAAA==.Zendezoth:BAABLgAECn8jAAIZAAkJpRmcAwBZAgAZAAkJpRmcAwBZAgAAAA==.Zephik:BAAALgADCgEJAQAAAA==.Zerofrost:BAABLgAECn8uAAIBAAkJrxl0PAAoAgABAAkJrxl0PAAoAgAAAA==.Zerrìc:BAAALgAECgcJEAAAAA==.Zevra:BAAALgADCgMJAwAAAA==.',
Zh='Zhiva:BAABLgAECn89AAIDAAkJ/A+hBABUAQADAAkJ/A+hBABUAQAAAA==.',
Zu='Zul:BAACLgAFFH8ZAAIUAAMJXiOfIgAQAQAUAAMJXiOfIgAQAQAuAAQKfzMAAxQACQkwI+oHAKkCABQACQkwI+oHAKkCABUAAQnLAkMiACQAAAAA.',
Zy='Zykoz:BAABLgAECn8uAAIUAAkJpCGMBADzAgAUAAkJpCGMBADzAgAAAA==.',
['Ða']='Ðamned:BAABLgAECn8bAAQSAAcJNxvELgCnAQASAAYJ8hvELgCnAQAQAAEJxBx4DABTAAAeAAIJaAfVJQA9AAABLgAFFAIJCQAIANMeAA==.',
['Ÿo']='Ÿoshi:BAABLgAECn8bAAIaAAgJhQ/8TQB/AQAaAAgJhQ/8TQB/AQAAAA==.',
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
