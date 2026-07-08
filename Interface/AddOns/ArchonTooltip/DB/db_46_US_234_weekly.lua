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

local lookup = {'Mage-Frost','Warlock-Destruction','Druid-Balance','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Priest-Holy','Paladin-Retribution','Paladin-Holy','Warrior-Fury','Warrior-Arms','Shaman-Enhancement','Paladin-Protection','Shaman-Elemental','Evoker-Preservation','DemonHunter-Vengeance','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Unknown-Unknown','Shaman-Restoration','Druid-Restoration','Priest-Shadow','Monk-Brewmaster','Druid-Feral','DeathKnight-Frost','Hunter-Survival','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Havoc','Priest-Discipline','Mage-Arcane','Mage-Fire','Rogue-Assassination',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abomination:BAAALgADCgMJAwAAAA==.',
Ad='Adune:BAAALgAECgQJBQAAAA==.',
Ae='Aeidail:BAACLgAFFH8eAAIBAAcJTRhJJwDaAQABAAcJTRhJJwDaAQAuAAQKfy0AAgEACQnlI0McAAUDAAEACQnlI0McAAUDAAAA.Aelaria:BAAALgADCgMJAwAAAA==.Aeviria:BAABLgAECn8oAAICAAgJtRVxCADGAQACAAgJtRVxCADGAQAAAA==.',
Ag='Agraceful:BAACLgAFFH8OAAIDAAMJEAc4FgBvAAADAAMJEAc4FgBvAAAuAAQKfx8AAgMACQm8EjkfAM4BAAMACQm8EjkfAM4BAAAA.',
Ai='Ailee:BAAALgAECgYJDAAAAA==.Aios:BAAALgAECgIJAgAAAA==.Aiza:BAACLgAFFH8PAAIEAAMJ7QsSJQDCAAAEAAMJ7QsSJQDCAAAuAAQKfzgAAwQACQmXGb8dAHICAAQACQmXGb8dAHICAAUAAQkAAA1JAAAAAAAA.',
Al='Alaber:BAAALgAECgUJCAAAAA==.Aldanil:BAAALgADCgMJAwAAAA==.Allarria:BAAALgADCgYJBwABLgAECgkJJgAGAFogAA==.',
Am='Ampersand:BAAALgAECgMJCAAAAA==.',
An='Animalfriend:BAAALgAECgQJCAAAAA==.Anklesmasher:BAABLgAECn8VAAIHAAgJcA4fPAAQAQAHAAgJcA4fPAAQAQAAAA==.Antisocial:BAACLgAFFH8IAAIEAAMJgwydgwC+AAAEAAMJgwydgwC+AAAuAAQKfxkAAgQABglwGsBpAJABAAQABglwGsBpAJABAAEuAAUUAgkJAAgA0x4A.Antonidus:BAAALgAECgYJEgAAAA==.Anyah:BAABLgAECn8dAAIDAAgJqgRoDABwAAADAAgJqgRoDABwAAAAAA==.',
Ap='Apolloo:BAAALgADCgMJAwAAAA==.',
Aq='Aquadora:BAAALgAECgEJAQAAAA==.',
Ar='Arfaz:BAABLgAECn82AAMIAAkJwBqvQAABAgAIAAkJxRmvQAABAgAJAAYJWAoXOQCvAAAAAA==.Armbrost:BAAALgAECgYJCgAAAA==.Arthemis:BAAALgAECgEJAgAAAA==.Artimås:BAAALgADCgcJCAAAAA==.Arwynne:BAAALgADCgMJAwAAAA==.Arçano:BAAALgAECgEJAQABLgAECgkJGQAKADkTAA==.',
As='Ascension:BAAALgADCgcJBgABLgAFFAQJCwAEAJ4ZAA==.Astrastar:BAABLgAECn8bAAMEAAYJ0wKg4wCVAAAEAAYJ0wKg4wCVAAACAAEJcgDDgAAOAAAAAA==.',
Au='Auralyn:BAAALgADCgMJBQAAAA==.Aurius:BAAALgAECgcJAgAAAA==.',
Av='Avarin:BAAALgADCgEJAQAAAA==.',
Ay='Aymont:BAAALgAECgQJBQAAAA==.',
Ba='Baerd:BAABLgAECn8aAAILAAcJZhPqKwBqAQALAAcJZhPqKwBqAQAAAA==.Baji:BAAALgAECgkJBwAAAA==.Barlz:BAAALgAECgEJAQAAAA==.',
Be='Beanpaste:BAAALgAECgcJAQABLgAFFAMJEAAIAHcZAA==.Beanutbutter:BAAALgADCgIJAgABLgAFFAMJEAAIAHcZAA==.Beaty:BAAALgAECgIJAgAAAA==.Bebby:BAABLgAECn8mAAMJAAgJUwPKBgCqAAAJAAgJIgPKBgCqAAAIAAIJaQJVeAEwAAAAAA==.Belonara:BAAALgAECgEJAQAAAA==.Belwolf:BAABLgAECn8UAAIIAAUJwApn6ADKAAAIAAUJwApn6ADKAAAAAA==.Bergstrom:BAABLgAECn80AAIMAAkJuhnAMAA+AgAMAAkJuhnAMAA+AgAAAA==.Bethanymarie:BAAALgAECgEJAQAAAA==.Betrayer:BAAALgADCgQJAwABLgAFFAQJCwAEAJ4ZAA==.',
Bi='Biancaneve:BAACLgAFFH8GAAILAAMJ9Q8kJACaAAALAAMJ9Q8kJACaAAAuAAQKfyEAAgsACQkMG3EBAC0CAAsACQkMG3EBAC0CAAAA.Bighero:BAACLgAFFH8QAAIGAAMJSQsEagC4AAAGAAMJSQsEagC4AAAuAAQKfyAAAgYACQk9EVlvAFYBAAYACQk9EVlvAFYBAAAA.Bigmike:BAAALgAECgEJAgAAAA==.',
Bl='Blakkjezus:BAAALgAECgcJCwAAAA==.Blessednugie:BAABLgAECn8VAAMNAAcJuBheBQARAQANAAcJuBheBQARAQAMAAIJPA33QAArAAAAAA==.Blitzbolts:BAAALgAECgEJAgAAAA==.Bludo:BAACLgAFFH8UAAMOAAcJKxChEQDWAAAPAAQJ+wqAHQADAQAOAAUJHRWhEQDWAAAuAAQKfx4AAw4ACQl6IWgZAIACAA4ACAk5GWgZAIACAA8ABgl9HFMYADYBAAAA.',
Bo='Boe:BAABLgAECn8pAAIQAAkJNAr5EwB6AQAQAAkJNAr5EwB6AQAAAA==.Bomba:BAAALgAECgUJDQAAAA==.Bombacløt:BAABLgAECn80AAMEAAkJkxDwRQDJAQAEAAkJFRDwRQDJAQACAAcJbg6pFAAIAQAAAA==.Bowdirte:BAAALgAECgUJBwAAAA==.',
Br='Brastin:BAABLgAECn86AAIRAAkJkyJHAgASAwARAAkJkyJHAgASAwABLgAFFAYJEwASAAoMAA==.Brenell:BAACLgAFFH8IAAIBAAMJgRLhiwDBAAABAAMJgRLhiwDBAAAuAAQKfzsAAgEACQmwIX0RAPECAAEACQmwIX0RAPECAAAA.',
Bu='Bu:BAAALgAECgYJDQABLgAECgYJHQATALgdAA==.Bubblehearth:BAAALgAECgYJCQABLgAFFAMJCAAGADgNAA==.Buffet:BAABLgAECn8aAAIBAAYJ0BHqrQAlAQABAAYJ0BHqrQAlAQABLgAFFAMJCAAGADgNAA==.Buhlitz:BAAALgAECgEJAgAAAA==.Butterbean:BAAALgADCgMJBQAAAA==.',
By='Bynis:BAABLgAECn8gAAIGAAkJDRVHSACtAQAGAAkJDRVHSACtAQAAAA==.',
Ca='Cabëla:BAAALgADCgUJBQAAAA==.Cactusjack:BAAALgADCgUJBQAAAA==.Cadorex:BAAALgADCgEJAQAAAA==.Caffeinefree:BAAALgADCggJBwAAAA==.Calacolinda:BAAALgAECgQJBgAAAA==.Calamari:BAAALgAECgEJAQAAAA==.Cavakworm:BAAALgADCgEJAQAAAA==.Caylin:BAAALgADCgUJBgAAAA==.Cayusedemon:BAAALgADCgEJAQAAAA==.Cayusemage:BAAALgADCgkJFwAAAA==.Cayusevoid:BAAALgADCgcJBwAAAA==.',
Ce='Celestiall:BAAALgAECgYJBgAAAA==.Ceridwyn:BAAALgAECgQJBQAAAA==.',
Ch='Chariscrushr:BAAALgAECgQJCAABLgAFFAQJBgAKAPMHAA==.Cheesecurd:BAAALgAECgcJDgAAAA==.Chen:BAAALgADCgIJAgAAAA==.Choal:BAAALgAECgEJAQAAAA==.Chokaho:BAAALgAECgQJBgAAAA==.Chubberoni:BAAALgAECgUJBwAAAA==.',
Ci='Cinnamongirl:BAAALgAECgcJEgAAAA==.',
Co='Corahin:BAABLgAECn8bAAISAAYJGxASRAA5AQASAAYJGxASRAA5AQAAAA==.Corious:BAAALgAECgQJCQAAAA==.Cosmos:BAAALgAECgYJDQAAAA==.Cougarhunter:BAAALgAECgkJEAAAAA==.',
Cr='Crixux:BAAALgADCgMJAQAAAA==.Crokus:BAAALgADCggJCAAAAA==.',
Cu='Cuecumba:BAABLgAECn8uAAIUAAkJICZ2AABbAwAUAAkJICZ2AABbAwAAAA==.',
Da='Daemonerror:BAAALgAECgUJBQABLgAECgkJTAAVAKIjAA==.Dalren:BAACLgAFFH8mAAMWAAgJJh1QBgDGAQAWAAgJJh1QBgDGAQAXAAIJuwNtCwBLAAAuAAQKf00AAxYACQnIJf0BAGEDABYACQnIJf0BAGEDABcABgnyIEMMABcCAAAA.Dalryn:BAAALgAECgYJDQABLgAFFAgJJgAWACYdAA==.Dalvix:BAAALgADCgEJAQABLgAECgkJJgAGAFogAA==.Damocles:BAABLgAECn8YAAIBAAYJlwwqyAD9AAABAAYJlwwqyAD9AAAAAA==.Danazel:BAAALgADCgMJBQAAAA==.Dartagnan:BAACLgAFFH8QAAIYAAMJnhwUUQAIAQAYAAMJnhwUUQAIAQAuAAQKfygAAxgACQnLHTpJAMYBABgABwkLHzpJAMYBABkABgn3FI8bANEAAAAA.Darthmaul:BAABLgAECn8wAAIDAAkJyhHNHwDKAQADAAkJyhHNHwDKAQAAAA==.',
De='Deay:BAAALgADCgQJAQAAAA==.Delexa:BAAALgADCgkJQAAAAA==.Demonicnugie:BAAALgADCgEJAQAAAA==.Dendiian:BAABLgAECn8WAAIaAAcJ4RMeJwAdAQAaAAcJ4RMeJwAdAQAAAA==.',
Di='Didipullthat:BAAALgAECgMJAwABLgAFFAMJCAAGADgNAA==.Diem:BAABLgAECn8dAAIYAAgJyw1rQQCqAQAYAAgJyw1rQQCqAQAAAA==.Dinendal:BAAALgADCgYJBgAAAA==.Dirtydotss:BAABLgAECn8VAAMFAAcJFwfXEgD/AAAFAAYJYQbXEgD/AAAEAAYJ5wSTzQC3AAAAAA==.Discernment:BAAALgAECgEJAQAAAA==.Divigitives:BAAALgAECgQJBAAAAA==.',
Do='Docrivan:BAAALgAECgYJCwAAAA==.Docsassist:BAAALgAECgMJAwABLgAECgYJCwAbAAAAAA==.Doregit:BAABLgAECn83AAIOAAkJIx/LCwCrAgAOAAkJIx/LCwCrAgAAAA==.Dowedoes:BAABLgAECn89AAIMAAkJgheVNgAnAgAMAAkJgheVNgAnAgAAAA==.',
Dr='Drachula:BAABLgAECn8bAAIcAAcJTRalOwDAAQAcAAcJTRalOwDAAQAAAA==.Dracultra:BAAALgAECgUJBwABLgAECgkJJgANAJ4hAA==.Drakcheese:BAAALgADCgUJBQAAAA==.Dreolan:BAABLgAECn9OAAIdAAkJ5xqKFACmAgAdAAkJ5xqKFACmAgAAAA==.Drnatemonk:BAABLgAFFH8NAAIVAAUJ5w+bDgA0AQAVAAUJ6A+bDgA0AQAAAA==.Drynnai:BAAALgADCgEJAgAAAA==.',
Dy='Dyala:BAACLgAFFH8QAAMdAAMJjg8URACjAAAdAAMJjg8URACjAAADAAMJMwSSOgCOAAAuAAQKfyMAAx0ACQkDErNmAAABAB0ACQkDErNmAAABAAMABAkoDt5OANEAAAAA.',
['Dö']='Dönövan:BAABLgAECn8zAAIMAAkJAhX9RQD0AQAMAAkJAhX9RQD0AQAAAA==.',
Eg='Eggyolk:BAAALgAECgkJDwAAAA==.',
El='Elapst:BAAALgAECgIJAgAAAA==.Elastwo:BAAALgADCgcJEgABLgAECgIJAgAbAAAAAA==.Eloise:BAABLgAECn8aAAILAAgJMw+dLQBgAQALAAgJMw+dLQBgAQAAAA==.Elvenbane:BAABLgAECn8nAAIeAAkJrRO3HADfAQAeAAkJrRO3HADfAQAAAA==.',
Em='Emily:BAAALgAECgYJDAAAAA==.Emry:BAAALgADCgYJBgABLgAECgcJHQAVADkPAA==.',
En='Enable:BAEBLgAECn8gAAIfAAkJVRxUCgCOAgAfAAkJVRxUCgCOAgABLgAECgkJNAARAE8iAA==.',
Ep='Epictool:BAAALgAECggJCwAAAA==.',
Et='Ethereal:BAAALgAECgEJAQAAAA==.Etö:BAAALgAECgEJAQABLgAECgQJBgAbAAAAAA==.',
Ew='Ew:BAACLgAFFH8IAAIYAAMJXBL4MgCdAAAYAAMJXBL4MgCdAAAuAAQKfxQAAhgABwlLHWwmACACABgABwlLHWwmACACAAEuAAUUAgkJAAgA0x4A.',
Ex='Extrathick:BAAALgAECgMJAwAAAA==.',
Fa='Fabel:BAEBLgAECn80AAIRAAgJTyJeBwBoAgARAAgJTyJeBwBoAgAAAA==.Falahad:BAAALgAECgEJAQABLgAFFAMJDwADAD4OAA==.Faltree:BAACLgAFFH8PAAMDAAMJPg7XMwCxAAADAAMJPg7XMwCxAAAdAAIJuhVnUgB6AAAuAAQKfyEABB0ACQkeFf5TAFcBAB0ACAkrFP5TAFcBAAMACAkOF0wyAFEBACAAAQnfAUo6AB8AAAAA.Fathershale:BAAALgAECgUJCAAAAA==.',
Fi='Firelord:BAAALgADCgEJAQAAAA==.Fistingmilk:BAAALgAECgYJBwAAAA==.',
Fo='Foulcor:BAABLgAECn8dAAMNAAkJ7B6LFwBNAgANAAgJlB6LFwBNAgAMAAcJRhEwmQBDAQAAAA==.',
Fr='Freakadeek:BAABLgAECn8VAAQhAAkJaw1DIQDEAAAIAAUJ0Aid1wDeAAAhAAMJnhdDIQDEAAAJAAYJgwTWTgBXAAAAAA==.Freâkadeek:BAAALgAECgIJBQABLgAECgkJFQAhAGsNAA==.Freäk:BAAALgADCgMJAwABLgAECgkJFQAhAGsNAA==.Frieren:BAABLgAECn8+AAIBAAkJsBY3PwAfAgABAAkJsBY3PwAfAgAAAA==.Frink:BAAALgAECgEJAQABLgAECgkJPQAiAOEkAA==.Frostlord:BAAALgAECgIJAgAAAA==.',
Fu='Fundetected:BAAALgAFFAIJAgABLgAFFAMJCAAGADgNAA==.Furyofthenug:BAAALgAECgQJBAAAAA==.Fuzzywuzzy:BAAALgAECgUJBQABLgAECgYJHQATALgdAA==.',
Ga='Gabbyo:BAABLgAECn8lAAIdAAkJ/Ad2VAA+AQAdAAkJ/Ad2VAA+AQAAAA==.Galadorn:BAABLgAECn8mAAIGAAkJWiC/DwDFAgAGAAkJWiC/DwDFAgAAAA==.Gallgamesh:BAAALgADCgIJAgAAAA==.Garfall:BAAALgAECgcJDgAAAA==.Garga:BAAALgADCgMJBAABLgAECgQJBAAbAAAAAA==.',
Ge='Geirvaldr:BAAALgAECgYJBgAAAA==.Gerdash:BAAALgAECgMJBAAAAA==.Gerred:BAACLgAFFH8JAAIPAAMJPRj0IwDfAAAPAAMJPRj0IwDfAAAuAAQKfx8AAw8ACAnNGn8NABACAA8ACAk1Gn8NABACAA4ABAlFFB5mAMQAAAAA.',
Gh='Ghallow:BAABLgAECn8gAAIQAAkJnBsRAQDDAQAQAAkJnBsRAQDDAQAAAA==.Ghosty:BAACLgAFFH8JAAIjAAQJOxWRIAAhAQAjAAQJOxWRIAAhAQAuAAQKfyoAAiMABwlQIFgUAP8BACMABwlQIFgUAP8BAAAA.',
Gi='Gimp:BAAALgAECgEJAgAAAA==.',
Gl='Gladur:BAABLgAFFH8GAAMHAAYJyAzzHwDZAAAHAAUJtwzzHwDZAAAVAAEJmQGAZQAxAAABLgAFFAcJHgABAE0YAA==.',
Go='Goldenflame:BAAALgAECgUJBwAAAA==.Goldenlily:BAAALgAECgYJEgAAAA==.Goldenmunc:BAABLgAECn8tAAIBAAkJNxfsNQBBAgABAAkJNxfsNQBBAgAAAA==.Goldenone:BAAALgAECggJCQAAAA==.Goldenpants:BAABLgAECn8nAAIOAAkJjxM8IgDgAQAOAAkJjxM8IgDgAQAAAA==.',
Gr='Grandesaxx:BAAALgAECgEJAQAAAA==.Grievous:BAABLgAECn89AAIUAAkJOyW4AABKAwAUAAkJOyW4AABKAwAAAA==.',
['Gû']='Gûrth:BAAALgADCgcJBwAAAA==.',
Ha='Hailmary:BAABLgAECn8oAAILAAkJEiV8AQCoAwALAAkJEiV8AQCoAwAAAA==.Halcrux:BAAALgAECgIJAgAAAA==.Halvard:BAAALgADCgMJBQAAAA==.Harusen:BAABLgAECn8cAAIkAAkJFR9EAgCmAgAkAAkJFR9EAgCmAgAAAA==.Havgnwltrav:BAAALgADCgcJBgAAAA==.',
He='Healaga:BAAALgAECgYJBgABLgAECgkJNgAIAMAaAA==.',
Hh='Hhoonnzz:BAABLgAFFH8LAAIjAAMJChOmJwDrAAAjAAMJChOmJwDrAAABLgAFFAIJCQAIANMeAA==.',
Hi='Hildalsind:BAAALgADCgkJCQABLgAFFAMJCQABAIMdAA==.',
Ho='Homestar:BAAALgADCgEJAQAAAA==.Hooll:BAAALgAECgIJAgAAAA==.Hornreaper:BAABLgAECn8bAAIWAAYJ5hfvJACVAQAWAAYJ5hfvJACVAQAAAA==.Hotshot:BAAALgAECgMJAwAAAA==.',
Hu='Hubbabubbajr:BAAALgAECgMJAwABLgAECgkJMwAdAIIbAA==.Hubert:BAAALgADCgEJAgAAAA==.Huracan:BAAALgAECgEJAgAAAA==.Hurin:BAAALgAECgcJDgAAAA==.Huur:BAAALgAECgEJAQABLgAECgEJAQAbAAAAAA==.',
Hy='Hyetta:BAAALgAECgQJBgABLgAECgkJHAAkABUfAA==.Hyir:BAAALgADCgYJBwABLgAFFAQJHgAHAOEfAA==.',
Il='Ilavengu:BAAALgAECgMJBQABLgAFFAQJFgAcADEmAA==.Illiya:BAABLgAECn8VAAILAAYJ+AsxRADZAAALAAYJ+AsxRADZAAAAAA==.',
Ir='Irôn:BAAALgAECgEJAQAAAA==.',
Iu='Iutara:BAAALgAECgYJDAAAAA==.',
Ja='Jaalein:BAAALgADCgcJDgAAAA==.Jayonor:BAABLgAECn80AAQSAAkJthVkGgAOAgASAAkJthVkGgAOAgAQAAYJ9we4GgAeAQAcAAcJ5AZmcQAIAQAAAA==.',
Je='Jek:BAAALgAECgYJBgAAAA==.',
Jo='Joryu:BAAALgADCgIJAwAAAA==.',
Ju='Juicycucci:BAAALgAECgcJEgABLgAFFAMJCAAGADgNAA==.',
Ka='Kaevrielle:BAECLgAFFH8JAAIUAAMJfBXUCADGAAAUAAMJfBXUCADGAAAuAAQKfx4AAxQACQmOG2IHAAwCABQACQmOG2IHAAwCACUAAQlWCol4ACcAAAAA.Kaison:BAABLgAECn8XAAMeAAkJEQigMQBVAQAeAAkJEQigMQBVAQAmAAcJBAtMNQBAAQABLgAECgkJIAAGAA0VAA==.Kaladîn:BAAALgAECgMJAwABLgAFFAcJHgABAE0YAA==.Kalii:BAAALgADCgQJBAAAAA==.Kamel:BAAALgADCgcJDQAAAA==.Kardin:BAAALgADCgEJAQAAAA==.Karwin:BAABLgAECn8bAAIBAAgJ/xRCaACsAQABAAgJ/xRCaACsAQAAAA==.Katakuri:BAAALgAECgEJAgAAAA==.',
Ke='Keeper:BAAALgAFFAIJAwABLgAFFAUJDQAMAJsiAA==.Keeperodark:BAACLgAFFH8FAAIEAAMJXgZdLACqAAAEAAMJXgZdLACqAAAuAAQKfxgAAgQACAkrF3UFAGgBAAQACAkrF3UFAGgBAAEuAAUUBQkNAAwAmyIA.Keeperolight:BAACLgAFFH8NAAIMAAUJmyLUEAArAQAMAAUJmyLUEAArAQAuAAQKf1MAAwwACQlUJeYEAFADAAwACQlUJeYEAFADAA0AAQmBGBSQAEAAAAAA.Kemanorel:BAAALgADCgcJDgABLgAECgkJJwAeAK0TAA==.',
Ki='Kianth:BAAALgADCgkJEgAAAA==.Killkat:BAABLgAECn8uAAIBAAkJgxhiNQBDAgABAAkJgxhiNQBDAgAAAA==.',
Ko='Kodera:BAABLgAECn8dAAMTAAYJuB3ZDQDyAQATAAYJuB3ZDQDyAQAXAAQJwhzKDgAfAQAAAA==.Koojo:BAAALgAECgcJCAAAAA==.Kosma:BAAALgAECgYJBgAAAA==.Kovae:BAAALgADCgEJAQAAAA==.',
Kr='Kraken:BAAALgADCgUJBQAAAA==.',
Ku='Kusheddruid:BAAALgADCgMJBQAAAA==.',
Ky='Kyaritin:BAAALgAECgMJAwABLgAECgYJCgAbAAAAAA==.Kyokei:BAAALgAECgEJAQAAAA==.',
La='Laiho:BAAALgADCgUJCAAAAA==.Lans:BAABLgAECn8UAAQnAAkJIQ0hDQD4AAAnAAUJ2AkhDQD4AAABAAQJ1Q80zAD3AAAoAAQJAwkBCQDKAAAAAA==.Larew:BAACLgAFFH8FAAIMAAMJbgfXfgC4AAAMAAMJbgfXfgC4AAAuAAQKfy8AAgwACQnfGfMnAGQCAAwACQnfGfMnAGQCAAAA.Lazytemplar:BAAALgADCgMJAwABLgAFFAIJBAAbAAAAAA==.',
Le='Lealla:BAABLgAECn89AAIDAAkJlCI8BQAIAwADAAkJlCI8BQAIAwAAAA==.Lechevalier:BAAALgAFFAIJAwABLgAFFAMJCAAGADgNAA==.Leodin:BAAALgAECgEJAgAAAA==.Leorus:BAAALgAECgIJAgAAAA==.Lethhunt:BAACLgAFFH8bAAMZAAgJNgs+EABdAQAZAAgJlQk+EABdAQAYAAQJpAzCIQDnAAAuAAQKfy4AAxkACQncHpwGACgCABkACQlgHpwGACgCABgAAgk+JFKHANIAAAAA.',
Li='Lilmistfox:BAAALgAECgUJBwABLgAFFAQJFgAcADEmAA==.Lioh:BAAALgAECgQJBAAAAA==.Lizardgang:BAABLgAECn8UAAIYAAYJ0xiXewBIAQAYAAYJ0xiXewBIAQAAAA==.',
Lo='Loganshu:BAAALgAECgkJDgAAAA==.Lokan:BAACLgAFFH8RAAMiAAMJWRkcHQDoAAAiAAMJWRkcHQDoAAAYAAEJwgjlqABFAAAuAAQKfywAAyIACQlHHqkIAJQCACIACQlHHqkIAJQCABgAAQn+CiMyATYAAAAA.Lots:BAACLgAFFH8RAAIEAAMJhhtjZwD3AAAEAAMJhhtjZwD3AAAuAAQKfycAAwQACQktIgIrAC4CAAQACAliIgIrAC4CAAIABAngHkcsAA0BAAAA.',
Lu='Ludacast:BAAALgADCgIJAgAAAA==.Ludafists:BAAALgADCgcJDAAAAA==.Ludakris:BAABLgAECn8eAAIRAAkJfxhLCwATAgARAAkJfxhLCwATAgAAAA==.Lumanoth:BAAALgAECgYJBgAAAA==.',
Ly='Lyna:BAABLgAECn8gAAIcAAkJpROdPwCvAQAcAAkJpROdPwCvAQAAAA==.Lynaya:BAAALgADCgIJAgAAAA==.',
['Lí']='Líonheart:BAABLgAECn8eAAMNAAcJYBePPgBKAQANAAcJYBePPgBKAQAMAAYJFgvJ0wDuAAAAAA==.',
['Lî']='Lîghtless:BAACLgAFFH8PAAIBAAYJBhqgGABoAQABAAYJBhqgGABoAQAuAAQKfxcAAgEACAmfJUchAO4CAAEACAmfJUchAO4CAAAA.',
['Lú']='Lúckally:BAAALgADCgQJBAABLgAECgYJCgAbAAAAAA==.Lúckÿ:BAAALgAECgYJCgAAAA==.',
Ma='Magetheo:BAAALgADCgIJAgAAAA==.Magicpanda:BAAALgAECgUJCwAAAA==.Mahina:BAAALgAECgMJAgAAAA==.Malik:BAAALgADCgIJAgAAAA==.Marcille:BAABLgAECn8nAAIBAAgJ2RO7dwCKAQABAAgJ2RO7dwCKAQAAAA==.Masyledian:BAAALgAECgIJBAABLgAECgcJIgAIAHwZAA==.Mathor:BAAALgAECgEJAgAAAA==.Mavrbg:BAAALgAECgQJBQAAAA==.Mayhaps:BAABLgAECn9EAAMYAAkJFRuBJwBBAgAYAAkJFRuBJwBBAgAZAAEJZACpmgAYAAAAAA==.',
Mc='Mcbain:BAABLgAECn89AAIiAAkJ4STWAQA9AwAiAAkJ4STWAQA9AwAAAA==.',
Me='Melinia:BAAALgAECgEJAQABLgAECgEJAgAbAAAAAA==.Melrine:BAAALgADCgMJAwAAAA==.Mentaltitty:BAABLgAECn8gAAIBAAkJgxKGSwD5AQABAAkJgxKGSwD5AQAAAA==.Meret:BAAALgADCgMJBQAAAA==.',
Mi='Minerwor:BAAALgAECgYJCgAAAA==.Mirrayla:BAAALgADCgYJBgAAAA==.Misty:BAAALgADCgYJBgAAAA==.',
Mm='Mmisty:BAABLgAECn9IAAIDAAkJghmMDwBnAgADAAkJghmMDwBnAgAAAA==.',
Mo='Moarthretplz:BAAALgAECgUJCQABLgAFFAQJFgAcADEmAA==.Mohji:BAAALgAFFAEJAQABLgAFFAgJGwAmAPQSAA==.Moldynuggets:BAAALgAECgYJDgAAAA==.Momometaru:BAABLgAECn8kAAQEAAkJgRaCQQDYAQAEAAkJfhOCQQDYAQACAAUJNhRyJgAsAQAFAAMJzxrGJgCMAAAAAA==.Monsterbee:BAABLgAECn9MAAIEAAkJ1BXiKwAqAgAEAAkJ1BXiKwAqAgAAAA==.',
Mu='Mustypizza:BAABLgAECn8uAAICAAkJihjJBAAsAgACAAkJihjJBAAsAgAAAA==.',
Mx='Mxicancowboy:BAAALgADCgEJAgAAAA==.',
My='Mystery:BAABLgAECn89AAMTAAkJNiC9AgAzAwATAAkJNiC9AgAzAwAXAAUJXhELEAAKAQAAAA==.',
['Mê']='Mêøwzêr:BAAALgAECggJEwAAAA==.',
['Mÿ']='Mÿst:BAAALgAECgMJBAAAAA==.',
Na='Nak:BAAALgAECgYJBgAAAA==.Narashi:BAAALgAECgQJCAAAAA==.Naril:BAAALgADCgUJBQAAAA==.Nats:BAABLgAECn8pAAIcAAgJSxEeDQDQAAAcAAgJSxEeDQDQAAAAAA==.',
Ne='Neameny:BAABLgAECn89AAIYAAkJGBObOwDxAQAYAAkJGBObOwDxAQAAAA==.',
Ni='Nianji:BAAALgADCgYJDgAAAA==.Nightstar:BAAALgAECgEJAQAAAA==.Nightworld:BAAALgADCgcJDgAAAA==.',
No='Noctum:BAAALgAECggJDgAAAA==.Nordicpally:BAAALgADCgQJBAAAAA==.Notbomba:BAAALgAECgEJAwAAAA==.Notgim:BAAALgADCggJCAAAAA==.',
Nu='Nualrossan:BAAALgADCgYJCAAAAA==.Nubrac:BAAALgAECgkJEwAAAA==.',
Ny='Nylux:BAAALgAECgYJDwAAAA==.',
Ob='Oblivion:BAACLgAFFH8LAAIEAAQJnhnLHwDaAAAEAAQJnhnLHwDaAAAuAAQKfz4AAwQACQmfJLUGACUDAAQACQmfJLUGACUDAAIAAQkAAFFdAFcAAAAA.',
Og='Ogrebreath:BAAALgAECgUJBwAAAA==.',
Oo='Oostren:BAAALgAECgEJAgAAAA==.',
Or='Orsyp:BAAALgADCgkJGgAAAA==.',
Pa='Palockie:BAAALgADCgEJAQAAAA==.Pandas:BAABLgAECn8hAAISAAkJAhF6JwCxAQASAAkJAhF6JwCxAQAAAA==.Partyrocker:BAABLgAECn8XAAIiAAcJag79KgBKAQAiAAcJag79KgBKAQABLgAECgkJFQAhAGsNAA==.Paynë:BAAALgAECgYJDQAAAA==.',
Pi='Pixae:BAACLgAFFH8PAAITAAMJjwdDIwCHAAATAAMJjwdDIwCHAAAuAAQKfyEAAhMACAm5Cm8ZAD8BABMACAm5Cm8ZAD8BAAAA.Pixiechaos:BAAALgAECgQJCAAAAA==.',
Po='Poliahu:BAABLgAECn8dAAIYAAkJFww+EQD1AAAYAAkJFww+EQD1AAAAAA==.Porthoss:BAAALgADCggJDwAAAA==.Powerplant:BAACLgAFFH8ZAAIYAAgJViDRDQD6AQAYAAgJViDRDQD6AQAuAAQKfyYAAhgACQkgJCgIAA4DABgACQkgJCgIAA4DAAAA.Poyoram:BAAALgADCgEJAQAAAA==.',
Pr='Pryi:BAAALgADCgcJBwABLgAFFAMJBwAMAO0IAA==.',
Py='Pyralys:BAABLgAECn85AAMLAAkJGBFmHADjAQALAAkJGBFmHADjAQAeAAMJqQJBiAAxAAAAAA==.',
['Pä']='Pärts:BAAALgAECgUJBQABLgAFFAYJCwAiAEITAA==.',
Qu='Quizac:BAAALgADCgMJBQAAAA==.',
Ra='Rabidghost:BAAALgADCgYJBgAAAA==.Ragemonk:BAAALgAECgUJDgABLgAFFAIJBAAbAAAAAA==.Ragetality:BAAALgAFFAIJBAAAAA==.Rahken:BAAALgADCgQJBAAAAA==.Rakthera:BAAALgADCgcJBwAAAA==.Rallaster:BAAALgAECgYJBgABLgAECgkJJwAeAK0TAA==.Ramaria:BAAALgADCgkJCQABLgAECgkJJgAGAFogAA==.Raserei:BAABLgAFFH8KAAIOAAMJIhf2LwDwAAAOAAMJIhf2LwDwAAAAAA==.Rasputain:BAAALgADCgYJCgAAAA==.Rasputein:BAAALgADCgcJBwAAAA==.Rattelyr:BAAALgAECgYJDgAAAA==.Ravara:BAAALgADCgYJBgABLgAECgkJJgAGAFogAA==.Rawb:BAACLgAFFH8KAAIOAAMJjxTzMwDhAAAOAAMJjxTzMwDhAAAuAAQKfx8AAw4ACAmyG74YACgCAA4ACAmyG74YACgCAAoABglmFr0uAM0AAAEuAAUUAgkJAAgA0x4A.Razgaurd:BAAALgAECgMJAwAAAA==.',
Re='Recolada:BAAALgAECggJCAAAAA==.Regice:BAAALgAECgcJBwABLgAFFAQJEwAJAC8bAA==.Regicee:BAACLgAFFH8TAAMJAAQJLxurBwA2AQAJAAQJLxurBwA2AQAIAAEJGwkChAA6AAAuAAQKf1IAAwkACQkKI10EAO8CAAkACQkKI10EAO8CAAgABwm5EZ8UALYAAAAA.Retam:BAAALgAECgcJDgAAAA==.Revakos:BAAALgADCgMJAwAAAA==.',
Rh='Rhysandra:BAAALgAECgQJCQAAAA==.',
Ri='Ribble:BAAALgADCgMJAwAAAA==.Riffraff:BAAALgAFFAEJAQAAAA==.Rindou:BAAALgAECgkJBAAAAA==.Ripcord:BAAALgAECgUJDQAAAA==.Ripem:BAAALgADCgYJBgAAAA==.Ripperoni:BAAALgAECgcJDQAAAA==.Rizek:BAAALgAECgUJBgABLgAECgcJHQAVADkPAA==.Rizzx:BAAALgAECgEJAQAAAA==.',
Ro='Rockdyou:BAABLgAECn8nAAIIAAkJ+R51JABzAgAIAAkJ+R51JABzAgAAAA==.Roglef:BAAALgAECgQJCQAAAA==.Rogmesh:BAAALgAECgYJCgAAAA==.Rotlobster:BAABLgAECn8aAAIFAAkJAB71AQDEAgAFAAkJAB71AQDEAgAAAA==.Roxxy:BAAALgAECgQJBAAAAA==.',
Ru='Rundvelt:BAACLgAFFH8RAAIRAAMJeA0IDwCQAAARAAMJeA0IDwCQAAAuAAQKfyQAAhEACQlSEQwVAIABABEACQlSEQwVAIABAAAA.',
['Rà']='Ràgëquit:BAAALgAECgEJAQAAAA==.',
Sa='Sage:BAAALgADCgcJCAAAAA==.Sandwich:BAAALgAECgcJCAAAAA==.Saphíra:BAAALgAFFAIJAQABLgAFFAcJHgABAE0YAA==.Sapkick:BAAALgAECgQJBwAAAA==.',
Se='Serdragon:BAAALgADCgQJBAAAAA==.Sertian:BAAALgAECgEJAQAAAA==.Servoid:BAAALgAECgUJCQAAAA==.',
Sh='Shando:BAAALgAECgEJAQAAAA==.Shiftstyle:BAEALgAECgEJAQAAAA==.Shtanky:BAACLgAFFH8PAAIKAAMJaBFHHgClAAAKAAMJaBFHHgClAAAuAAQKfyQAAgoACQnHD7MWAI4BAAoACQnHD7MWAI4BAAAA.',
Si='Silentsocks:BAAALgAECgUJDAAAAA==.Sixsixsix:BAAALgAECgcJCgABLgAFFAIJCQAIANMeAA==.',
Sk='Skoogz:BAABLgAECn8VAAMJAAcJGhNZJgAhAQAJAAcJxhJZJgAhAQAIAAQJ5A+a1QDhAAAAAA==.',
Sm='Smackdowne:BAAALgADCgIJAgAAAA==.',
So='Sofakingséxy:BAAALgAECgMJAwABLgAFFAMJCAAGADgNAA==.Soggyy:BAAALgADCgYJCwAAAA==.Solar:BAABLgAECn8VAAQHAAcJyRkxLwBtAQAHAAYJCxYxLwBtAQAfAAYJrhzoOABmAQAVAAEJUwL71wAaAAAAAA==.Soulfulgingr:BAABLgAECn8eAAISAAgJhAxIBQAnAQASAAgJhAxIBQAnAQAAAA==.',
St='Starlagosa:BAAALgADCgYJCQAAAA==.Sturm:BAAALgAECgMJAwAAAA==.Styx:BAAALgAECgMJAwAAAA==.',
Su='Sunbake:BAABLgAECn8bAAMLAAgJ7QXNCACqAAALAAgJ7QXNCACqAAAeAAEJ5gYqkAAqAAAAAA==.',
Sw='Sweetbbyraze:BAACLgAFFH8dAAMXAAYJvxyoBQAIAQAWAAYJeRmaIQBTAQAXAAQJQCGoBQAIAQAuAAQKfyYAAxcACAkpIVIGAJACABcABwm8IVIGAJACABYAAwnxHI9rAJkAAAAA.',
Sy='Sylaena:BAABLgAECn8oAAIZAAgJVQoeFAAgAQAZAAgJVQoeFAAgAQAAAA==.Sylvrstorm:BAAALgAECgcJDQAAAA==.',
['Së']='Sërënity:BAABLgAECn8XAAIdAAUJjg6GCQCqAAAdAAUJjg6GCQCqAAAAAA==.',
['Sí']='Sín:BAAALgAECgcJDAABLgAFFAIJCQAIANMeAA==.',
Ta='Talipally:BAACLgAFFH8HAAIMAAMJ7QjMewC+AAAMAAMJ7QjMewC+AAAuAAQKfxwAAgwACQkyEM14AH0BAAwACQkyEM14AH0BAAAA.Talishammy:BAAALgAECgMJAwABLgAFFAMJBwAMAO0IAA==.Taliwhacker:BAAALgAFFAEJAQABLgAFFAMJBwAMAO0IAA==.Talonleafgrd:BAAALgAECgkJCgAAAA==.Tanaka:BAABLgAECn8gAAIIAAgJgBMJWgC4AQAIAAgJgBMJWgC4AQAAAA==.Tanisong:BAAALgAECgQJDQAAAA==.Tassadar:BAAALgAECgUJCAAAAA==.',
Te='Teldo:BAAALgADCgMJBQAAAA==.Tepeyollotl:BAAALgADCgEJAQAAAA==.Terayus:BAAALgADCgcJDAAAAA==.Teyliah:BAAALgADCgMJAwAAAA==.',
Tf='Tf:BAAALgAECgYJBgABLgAFFAIJCQAIANMeAA==.',
Th='Thalor:BAAALgAECgUJBQABLgAFFAQJBgAKAPMHAA==.Thekingpunch:BAABLgAECn9MAAMVAAkJoiO5BwAhAwAVAAkJoiO5BwAhAwAHAAEJahZWjwBCAAAAAA==.Thenle:BAAALgADCggJEQAAAA==.Thline:BAAALgADCgMJBQAAAA==.Thunderblitz:BAABLgAECn8rAAINAAkJdgknMwCIAQANAAkJdgknMwCIAQAAAA==.Thurmus:BAAALgADCgkJQAAAAA==.Thánatos:BAAALgADCgMJAwAAAA==.',
Ti='Tillwar:BAABLgAECn87AAIOAAkJKh2pEAByAgAOAAkJKh2pEAByAgAAAA==.Tinymonk:BAAALgAECgMJAwAAAA==.',
To='Tofu:BAACLgAFFH8KAAIIAAMJ3B16hwD6AAAIAAMJ3B16hwD6AAAuAAQKf0UAAwgACQnEHvEVAMQCAAgACQnEHvEVAMQCAAkABwmjFrwaAIgBAAAA.Tokanya:BAAALgAECgEJAQAAAA==.Tortillachip:BAAALgAECgEJAgAAAA==.Toxidot:BAAALgAECgEJAQAAAA==.',
Tr='Treibh:BAABLgAECn8qAAIdAAkJCxilFwCJAgAdAAkJCxilFwCJAgAAAA==.Trelephant:BAAALgAECgMJBQAAAA==.Trulydps:BAABLgAECn8vAAIYAAkJ4xQKLwAgAgAYAAkJ4xQKLwAgAgAAAA==.Trulyog:BAAALgAECgQJBAABLgAECgkJLwAYAOMUAA==.',
Tu='Tubbsmcgee:BAACLgAFFH8fAAIcAAYJ6x8cCABFAgAcAAYJ6x8cCABFAgAuAAQKfyUAAhwACQkrJLgHAPkCABwACQkrJLgHAPkCAAEuAAUUBgkfABwA6x8A.Tukkit:BAAALgAECgYJDwAAAA==.',
Tw='Twistedshot:BAAALgADCggJCAAAAA==.Twizzler:BAABLgAECn9TAAIBAAkJZQi/fgB6AQABAAkJZQi/fgB6AQAAAA==.',
Ty='Tyraniik:BAAALgADCgYJCAAAAA==.',
['Të']='Tërris:BAABLgAECn8eAAIJAAkJQBHkGgCGAQAJAAkJQBHkGgCGAQAAAA==.',
['Tî']='Tîlldeath:BAAALgAECgUJBwAAAA==.',
['Tõ']='Tõaster:BAAALgADCgQJBAABLgAECgkJJgAGAFogAA==.',
Uj='Uji:BAAALgADCgEJAQAAAA==.',
Ur='Urowndad:BAAALgAECgUJBQABLgAECggJFgAMAL0TAA==.Urownmother:BAAALgADCgUJBQABLgAECggJFgAMAL0TAA==.',
Va='Vaellian:BAAALgAECgYJDAAAAA==.Vallez:BAECLgAFFH8WAAMNAAMJISDGIwACAQANAAMJISDGIwACAQAMAAMJ/g1fcwDMAAAuAAQKfyoAAw0ACQmqHQMSAIMCAA0ACQmqHQMSAIMCAAwAAwmiDWpGAWYAAAAA.Vanillaghost:BAAALgADCgIJAQAAAA==.Varnusshadow:BAAALgAECgUJBgAAAA==.',
Ve='Vearik:BAAALgAECgUJBwAAAA==.Velladoree:BAABLgAECn8mAAIVAAgJlAvfDQDTAAAVAAgJlAvfDQDTAAAAAA==.Vendaryn:BAAALgADCggJCAAAAA==.Vexahlia:BAAALgADCgMJAwAAAA==.',
Vg='Vgurlpally:BAAALgADCgYJBgAAAA==.',
Vy='Vynlorlan:BAAALgADCgMJAwABLgAECgMJBAAbAAAAAA==.',
Wa='Walkindead:BAAALgAECgQJBgAAAA==.Waveygravee:BAAALgAECgIJAwAAAA==.Wavyghoul:BAAALgAECgEJAQAAAA==.Wavygraivy:BAABLgAECn8eAAIcAAcJfBQXTACAAQAcAAcJfBQXTACAAQAAAA==.Wavygravey:BAAALgADCgQJBAAAAA==.',
We='Wedragon:BAABLgAECn8UAAMVAAYJ+RMPCgAWAQAVAAYJ+RMPCgAWAQAHAAMJygdFbgB1AAAAAA==.',
Wh='Wheelchair:BAACLgAFFH8LAAIIAAQJOxv7bwAeAQAIAAQJOxv7bwAeAQAuAAQKfxwAAggACAkSJF0SAA4DAAgACAkSJF0SAA4DAAAA.',
Wo='Woofwoof:BAAALgAFFAIJAgAAAA==.',
Wu='Wullemage:BAAALgADCgcJEwABLgAFFAcJHwAjALAaAA==.',
['Wå']='Wåsp:BAABLgAECn9PAAIGAAkJAxAHUACVAQAGAAkJAxAHUACVAQABLgAECgkJDwAbAAAAAA==.',
Xb='Xb:BAAALgAECgcJBQAAAA==.',
Xh='Xhexana:BAABLgAECn84AAIcAAkJTRcBHQBkAgAcAAkJTRcBHQBkAgABLgAECgkJPQAYABgTAA==.',
Xi='Xiaopo:BAAALgAECgEJAQABLgAFFAQJFgAcADEmAA==.',
Xr='Xrael:BAAALgAECgEJAQABLgAFFAMJEwAHACMiAA==.Xrayl:BAACLgAFFH8TAAMHAAMJIyKYEwAgAQAHAAMJIyKYEwAgAQAfAAMJxAxDOwC5AAAuAAQKfyUAAwcACQnoIMwNAGkCAAcACAmrIcwNAGkCAB8AAQmOG/N9AE8AAAAA.',
Xz='Xzerocool:BAABLgAECn8WAAQMAAgJvRNCiQBeAQAMAAgJvRNCiQBeAQARAAIJshNmPABqAAANAAEJmQOznQAiAAAAAA==.',
Ya='Yaniaa:BAAALgADCgcJBwAAAA==.Yannii:BAAALgADCgcJDgAAAA==.',
Ye='Yenko:BAAALgADCgIJAgAAAA==.',
Yo='Yolo:BAAALgADCgcJCwAAAA==.Yoshikazu:BAAALgAECgcJCgAAAA==.Yoyoboy:BAAALgAECgEJAwAAAA==.',
Za='Zaarah:BAAALgAECgYJDAAAAA==.',
Ze='Zellek:BAAALgADCgEJAQAAAA==.Zendezoth:BAABLgAECn8jAAIXAAkJpRmcAwBZAgAXAAkJpRmcAwBZAgAAAA==.Zephik:BAAALgADCgEJAQAAAA==.Zerofrost:BAABLgAECn8uAAIBAAkJrxl0PAAoAgABAAkJrxl0PAAoAgAAAA==.Zerrìc:BAAALgAECgcJEAAAAA==.Zevra:BAAALgADCgMJAwAAAA==.',
Zh='Zhiva:BAABLgAECn83AAIDAAkJpg6VNQBBAQADAAkJpg6VNQBBAQAAAA==.',
Zu='Zul:BAACLgAFFH8ZAAIjAAMJXiOfIgAQAQAjAAMJXiOfIgAQAQAuAAQKfzMAAyMACQkwI+oHAKkCACMACQkwI+oHAKkCACkAAQnLAkMiACQAAAAA.',
Zy='Zykoz:BAABLgAECn8uAAIjAAkJpCGMBADzAgAjAAkJpCGMBADzAgAAAA==.',
['Ða']='Ðamned:BAABLgAECn8YAAISAAYJ8hvELgCnAQASAAYJ8hvELgCnAQABLgAFFAIJCQAIANMeAA==.',
['Ÿo']='Ÿoshi:BAABLgAECn8bAAIYAAgJhQ/8TQB/AQAYAAgJhQ/8TQB/AQAAAA==.',
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
