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

local lookup = {'Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Unknown-Unknown','DemonHunter-Devourer','Paladin-Retribution','Druid-Restoration','Priest-Discipline','Priest-Shadow','Priest-Holy','Evoker-Augmentation','DeathKnight-Frost','Monk-Windwalker','Druid-Balance','DemonHunter-Havoc','Warlock-Demonology','Warrior-Protection','DeathKnight-Unholy','Hunter-BeastMastery','Mage-Frost','DemonHunter-Vengeance','Druid-Guardian','Warrior-Fury','Monk-Mistweaver','Hunter-Survival','Monk-Brewmaster','Paladin-Holy','Shaman-Elemental','Shaman-Restoration','Paladin-Protection','Warrior-Arms','Mage-Fire','Rogue-Subtlety','Evoker-Devastation','Shaman-Enhancement','Druid-Feral','Evoker-Preservation','Mage-Arcane','Rogue-Assassination','Rogue-Outlaw','Hunter-Marksmanship',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=46,date='2026-07-28',data={Ab='Absens:BAABLgAECn8+AAMBAAkJwhIeDAB9AQABAAkJhw8eDAB9AQACAAgJ0hBkDgB2AQAAAA==.',
Ad='Adorian:BAAALgAFFAEJAQABLgAFFAQJFAADABMhAA==.Adwillon:BAAALgADCgQJBQABLgAFFAEJAQAEAAAAAA==.',
Ae='Aedoril:BAAALgADCgEJAQAAAA==.Aellea:BAAALgADCgkJCQAAAA==.Aelyss:BAAALgADCgQJBAAAAA==.Aerosse:BAAALgAECgMJAwAAAA==.Aether:BAAALgAECgYJBwABLgAECgkJVAAFADQjAA==.',
Af='Aforceofone:BAABLgAECn8WAAIGAAUJagx42gDlAAAGAAUJagx42gDlAAAAAA==.',
Ai='Airdreanna:BAAALgADCgQJBAAAAA==.',
Ak='Akama:BAAALgAECgcJDAABLgAFFAgJIQAHAOwZAA==.',
Al='Alessian:BAAALgADCgEJAQAAAA==.Alex:BAAALgADCgUJBQAAAA==.Alivanllan:BAAALgAECgIJAgAAAA==.Alteisen:BAAALgAECgUJBQAAAA==.',
Am='Ambitious:BAAALgAECgMJCgAAAA==.Amerlinn:BAAALgAECgYJDAAAAA==.',
An='Anamuht:BAABLgAECn8sAAQIAAkJnhK3GgD6AQAIAAgJeBO3GgD6AQAJAAkJcx0SAwDxAQAKAAYJHhDdNAAxAQABLgAECgkJPwALAFsiAA==.Andryn:BAAALgAECgMJBQAAAA==.Annaday:BAABLgAECn8lAAIDAAkJgQ0PIQBKAQADAAkJgQ0PIQBKAQAAAA==.Antiock:BAACLgAFFH8UAAMDAAQJEyHSEQBsAQADAAQJEyHSEQBsAQAMAAQJVBNlDgAmAQAuAAQKfzIAAwMACQlxJJ8EAOgCAAMACQlxJJ8EAOgCAAwABwnRHIsKANQBAAAA.Anyaesthesia:BAAALgADCgYJBgAAAA==.Anyamonka:BAABLgAECn8dAAINAAYJChunBgAWAQANAAYJChunBgAWAQAAAA==.',
Ao='Aotc:BAAALgADCgMJAwAAAA==.',
Ap='Apocalich:BAAALgAECgUJBgAAAA==.Apostacy:BAAALgAECggJCAAAAA==.Appalachia:BAAALgAECgUJCQAAAA==.',
Aq='Aquenia:BAAALgADCggJDAAAAA==.',
Ar='Aralaith:BAABLgAECn8pAAIJAAgJcCUNCADOAgAJAAgJcCUNCADOAgABLgAFFAkJMAAOAM0mAA==.Argonaut:BAAALgAECgIJAgAAAA==.Argul:BAAALgAECgIJAgAAAA==.Ariea:BAAALgADCgYJBgAAAA==.Armata:BAAALgAECgMJAwABLgAFFAgJIQAHAOwZAA==.Artoriá:BAAALgAECgEJAQAAAA==.Artto:BAABLgAECn83AAIGAAkJHxOpFgAKAQAGAAkJHxOpFgAKAQAAAA==.',
As='Asevenhex:BAAALgAECgEJAQAAAA==.Ashbrínger:BAABLgAECn9HAAIGAAkJDCZuAwBjAwAGAAkJDCZuAwBjAwAAAA==.Association:BAAALgAECgMJAwAAAA==.Astrum:BAAALgAECgEJAgAAAA==.Asunã:BAAALgAECgIJAwABLgAECgEJAQAEAAAAAA==.',
At='Atico:BAAALgAECgIJAgAAAA==.',
Au='Aurah:BAAALgAECgIJBAAAAA==.',
Av='Averax:BAABLgAECn9UAAMFAAkJNCOSAQDDAgAFAAkJNCOSAQDDAgAPAAEJvQ2JbgA3AAAAAA==.Avylbrew:BAAALgAECgMJAwAAAA==.Avyrax:BAAALgAECgEJAgABLgAECgkJVAAFADQjAA==.',
Ay='Aybara:BAAALgADCgQJBAAAAA==.Aylakaye:BAAALgAECgMJAwAAAA==.Ayraena:BAABLgAECn8ZAAMOAAgJHQjtPQAYAQAOAAgJHQjtPQAYAQAHAAQJEgEuyAA9AAAAAA==.',
Az='Aziz:BAAALgADCgEJAQAAAA==.Azkariel:BAAALgAECgEJAwAAAA==.Azyrieth:BAAALgADCgEJAQAAAA==.Azzathoth:BAAALgADCgcJDAAAAA==.',
Ba='Babybilly:BAAALgAECgEJAgAAAA==.Babyshoes:BAAALgAECgEJAQAAAA==.Backpack:BAAALgAECggJDAAAAA==.Bakedtofu:BAABLgAECn8UAAMBAAYJ7wc9RwCZAAAQAAYJ7wcO1QCsAAABAAQJGQQ9RwCZAAAAAA==.Bananawaffle:BAAALgAECgMJBAAAAA==.Basement:BAAALgAECgMJAgABLgAFFAYJFQAOANQaAA==.Bashine:BAABLgAECn8WAAIRAAYJVxlZGACTAQARAAYJVxlZGACTAQABLgAFFAgJHgASADsfAA==.Baylohn:BAABLgAECn8lAAITAAkJhRaFMwAOAgATAAkJhRaFMwAOAgAAAA==.',
Be='Bearwrestler:BAABLgAECn8aAAIUAAgJ1BfVYgC5AQAUAAgJ1BfVYgC5AQABLgAFFAQJDwADAJAgAA==.Beefynugs:BAAALgAECgkJAgAAAA==.Betch:BAAALgAECgkJCQABLgAECgkJGQAOABMhAA==.',
Bi='Bier:BAAALgAECgUJDgAAAA==.Bigjos:BAAALgAECgUJBQAAAA==.Bigrig:BAABLgAECn8dAAITAAkJgAX/LQB+AAATAAkJgAX/LQB+AAAAAA==.Bitterman:BAABLgAECn8zAAMQAAkJQhiIIABiAgAQAAkJQhiIIABiAgABAAEJww/ZcAA1AAAAAA==.',
Bj='Bjornvalion:BAAALgADCgQJBAAAAA==.',
Bl='Blackmage:BAAALgAECgEJAQAAAA==.Bladed:BAABLgAECn8wAAQFAAkJEhqVBADXAQAFAAkJlxeVBADXAQAVAAYJChvADgBlAQAPAAQJFxIRQgCuAAAAAA==.Blinkerfluid:BAAALgADCgIJAgAAAA==.Blinx:BAAALgADCgQJBAAAAA==.Bloodymess:BAABLgAECn8aAAISAAgJQAqrhABaAQASAAgJQAqrhABaAQAAAA==.',
Bo='Bohikeog:BAAALgAECgMJAwAAAA==.Boogies:BAAALgADCgQJBwAAAA==.Bovinedivine:BAAALgAECgYJBgABLgAFFAEJAQAEAAAAAA==.Bowyardee:BAAALgAECgEJAQAAAA==.',
Bu='Buffie:BAABLgAECn8ZAAIGAAgJGhoeWADaAQAGAAgJGhoeWADaAQAAAA==.Bullwyf:BAAALgADCgMJAwAAAA==.Bumblbeetuna:BAAALgAECgMJAwAAAA==.',
['Bá']='Bád:BAAALgAECgIJAgABLgAECgcJKQAWAPARAA==.',
Ca='Calduu:BAAALgAECgQJCAAAAA==.Caledia:BAAALgAECgYJEQAAAA==.Callana:BAAALgADCgMJBQAAAA==.Camedra:BAABLgAECn9KAAIHAAkJqiQsAgCxAwAHAAkJqiQsAgCxAwAAAA==.Carinancey:BAAALgAECgQJBQAAAA==.Carperoni:BAAALgADCgcJBwAAAA==.Casseous:BAAALgADCgUJBwAAAA==.Castrada:BAAALgAECgUJBQABLgAECgkJWQAGAEIaAA==.Catamynyia:BAABLgAECn8qAAITAAkJIhBaSQDFAQATAAkJIhBaSQDFAQAAAA==.Caylaetal:BAAALgAECgEJAQAAAA==.',
Cc='Cchaos:BAAALgAECgIJBgAAAA==.',
Ce='Celaborn:BAABLgAECn8hAAIXAAkJjx4UBgB1AQAXAAkJjx4UBgB1AQAAAA==.Celice:BAAALgAECgcJBwABLgAFFAMJCgAYAE4dAA==.Cerwan:BAAALgADCgMJAwAAAA==.',
Ch='Chaotiiks:BAAALgAECgEJAQAAAA==.Chazaraz:BAABLgAECn8/AAMZAAkJVxElEwAOAgAZAAkJABElEwAOAgATAAgJEgibiwAoAQAAAA==.Chazsquatch:BAAALgAECgUJCgABLgAECgkJPwAZAFcRAA==.Chevy:BAAALgAECgEJAwAAAA==.Chifreak:BAAALgAFFAIJAgABLgAFFAQJBwAFAMEXAA==.Chillmourne:BAAALgAECgcJEwABLgAECggJCQAEAAAAAA==.Chimaira:BAAALgADCgIJAgAAAA==.Chimmythedk:BAAALgAECgMJAwAAAA==.Chucknoris:BAAALgAECgYJEwAAAA==.Chugbuggins:BAAALgAECgYJEwABLgAFFAEJAQAEAAAAAA==.',
Ci='Cindria:BAABLgAECn8lAAIUAAgJuBA1eQCGAQAUAAgJuBA1eQCGAQAAAA==.',
Cl='Clare:BAAALgAECgEJAwABLgAECgEJAQAEAAAAAA==.Clerks:BAAALgAECgIJAgAAAA==.Cliffgate:BAAALgADCgMJAwAAAA==.',
Co='Colaitis:BAAALgADCgIJAgAAAA==.Conduction:BAAALgAECgUJCAAAAA==.Corenthia:BAAALgAECgYJEwAAAA==.',
Cp='Cptbonez:BAAALgAECgYJEgABLgAECgkJMgAaAPQVAA==.',
Cr='Crankadin:BAAALgAECgEJAwABLgAECgIJBAAEAAAAAA==.Crankchi:BAAALgAECgIJAwABLgAECgIJBAAEAAAAAA==.Crazz:BAAALgADCgEJAQAAAA==.Crewz:BAAALgADCgQJBAAAAA==.Crooky:BAAALgADCgcJBwABLgAFFAcJIAASACobAA==.Crucifiiks:BAABLgAFFH8HAAIbAAMJxxB9FACtAAAbAAMJxxB9FACtAAAAAA==.Cruciö:BAAALgAECgEJAQAAAA==.Crànk:BAAALgAECgIJBAAAAA==.Cránk:BAAALgAECgEJAQABLgAECgIJBAAEAAAAAA==.Crãnk:BAAALgAECgIJAwABLgAECgIJBAAEAAAAAA==.',
Cu='Cullyeskie:BAAALgAECgMJAwAAAA==.Curveball:BAABLgAECn8kAAMcAAkJCRAwBgBvAQAcAAkJCRAwBgBvAQAdAAgJBwv3FgC8AAABLgAECgkJMwAQAEIYAA==.',
Cy='Cyniar:BAABLgAECn8iAAIOAAgJog5cBwA4AQAOAAgJog5cBwA4AQAAAA==.',
Da='Dalearnhardt:BAAALgADCgcJDgABLgAECgcJEgAEAAAAAA==.Damerlin:BAABLgAECn8bAAMGAAgJ7hGteQB7AQAGAAgJkA+teQB7AQAeAAQJcwolPgBkAAAAAA==.Damzel:BAAALgAECgMJAwAAAA==.Darkhuntress:BAAALgAECgcJBwAAAA==.Darkstär:BAABLgAECn9LAAIDAAkJDh/dBgCwAgADAAkJDh/dBgCwAgAAAA==.Darkun:BAAALgAFFAEJAQABLgAFFAMJBwALACsIAA==.Darkwood:BAAALgADCgEJAgAAAA==.Dauc:BAAALgADCgEJAQAAAA==.Davesdemise:BAAALgAECgcJDAAAAA==.',
De='Deacon:BAABLgAECn9nAAQaAAkJCQs9AwBhAQAaAAkJCQs9AwBhAQANAAUJmgpaXQChAAAYAAUJfQRdkQB2AAAAAA==.Deadmantooth:BAAALgADCgYJBgABLgAECgkJWgABALkdAA==.Deardren:BAAALgAECgUJBQAAAA==.Deathcorps:BAAALgAECgMJAwAAAA==.Deathgripbtw:BAAALgAECgMJAwAAAA==.Deathknights:BAAALgAFFAEJAQAAAA==.Deathtrol:BAAALgAECggJDwAAAA==.Deeanne:BAAALgAECgQJBwAAAA==.Deepdeuce:BAAALgAECgYJCgAAAA==.Deepfriar:BAABLgAECn9SAAMKAAkJSiWaAQChAwAKAAkJSiWaAQChAwAJAAcJMRSXLAByAQAAAA==.Deidra:BAAALgADCgMJAwAAAA==.Demonhunts:BAABLgAFFH8MAAIFAAUJhAsxWQDkAAAFAAUJhAsxWQDkAAAAAA==.Demoniiks:BAAALgAECgYJBgAAAA==.Demonmore:BAABLgAECn8jAAMPAAgJxAsUKwAnAQAPAAgJ2AoUKwAnAQAVAAUJWQoJIQCVAAAAAA==.Deneer:BAAALgAECgMJAwABLgAECgkJJQAfAL8aAA==.Derailed:BAAALgAECgQJBwAAAA==.Dethwing:BAAALgAECgUJBgAAAA==.Devilfrost:BAAALgAECgEJAQABLgAECgQJBwAEAAAAAA==.Dewshine:BAAALgAECgcJDQAAAA==.',
Dh='Dhampir:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Dhgeek:BAAALgAECgUJDwAAAA==.',
Di='Diablognomis:BAABLgAECn8jAAINAAcJwBihAwCMAQANAAcJwBihAwCMAQAAAA==.Diarmac:BAAALgAECgcJDgABLgAECgkJXgAdAOUQAA==.Dingô:BAAALgAECgQJBgAAAA==.Dirtman:BAACLgAFFH8FAAIcAAQJDw5xKQDvAAAcAAQJDw5xKQDvAAAuAAQKfzMAAhwACQlFHdsSAFgCABwACQlFHdsSAFgCAAAA.',
Dk='Dkrise:BAAALgAECgMJAwABLgAFFAMJBwALACsIAA==.',
Dn='Dneoh:BAAALgAECgkJCAABLgAFFAMJCgAOAOciAA==.',
Do='Dolphina:BAAALgAECgIJAgAAAA==.Donald:BAAALgADCgQJBAAAAA==.Donny:BAABLgAECn9GAAMGAAkJLx3fBABRAgAGAAkJEB3fBABRAgAeAAMJIxzTCAC+AAAAAA==.Doodyshamala:BAABLgAECn8VAAIdAAUJbx5/CwBXAQAdAAUJbx5/CwBXAQAAAA==.Dooky:BAAALgAECgYJBwABLgAFFAcJIAASACobAA==.Doozey:BAACLgAFFH8QAAIFAAQJJxYWRAAbAQAFAAQJJxYWRAAbAQAuAAQKfykAAwUACQniHu0bAGwCAAUACQlaHu0bAGwCABUAAQnNE9wxADwAAAAA.Dorigis:BAAALgAECgMJBgABLgAECgkJLwARAOEjAA==.Dotdotdotded:BAABLgAECn8WAAIQAAgJuAWjlgAPAQAQAAgJuAWjlgAPAQAAAA==.',
Dr='Dragonic:BAAALgAECgEJAQABLgAFFAgJIQAHAOwZAA==.Drewdog:BAABLgAECn9ZAAMZAAkJ0xjGAQD/AQAZAAkJPhbGAQD/AQATAAcJ/BcuFAApAQAAAA==.Drfeelgoods:BAAALgADCggJCAAAAA==.Droid:BAAALgAECgEJAgAAAA==.Drunkgerardo:BAAALgAECgQJBQAAAA==.Drunkzen:BAAALgAECgUJCAAAAA==.Druyesil:BAAALgAECgEJAgAAAA==.',
Du='Dubes:BAABLgAECn9GAAIUAAkJQhq5JwB7AgAUAAkJQhq5JwB7AgAAAA==.Dullblade:BAAALgADCgQJBAAAAA==.Dunbartian:BAABLgAECn8iAAIRAAgJehYYAwCRAQARAAgJehYYAwCRAQAAAA==.Duskfang:BAAALgAECgYJCgAAAA==.',
['Dá']='Dárkthorn:BAAALgAECgYJCgAAAA==.',
['Dö']='Dökkálfar:BAAALgAECgEJAQAAAA==.',
Ea='Easybreezin:BAAALgAECgUJDAAAAA==.',
Eg='Eggceptional:BAAALgADCgUJBQAAAA==.',
Ei='Eirote:BAABLgAECn9YAAIgAAkJhx1NAQCpAgAgAAkJhx1NAQCpAgAAAA==.',
El='Elarris:BAAALgAECgcJDQAAAA==.Eldari:BAABLgAECn8YAAIOAAgJ2htdGwDwAQAOAAgJ2htdGwDwAQAAAA==.Eledron:BAAALgAECgcJBwAAAA==.Elem:BAACLgAFFH8PAAIdAAYJUwjuKABCAQAdAAYJUwjuKABCAQAuAAQKfyMAAh0ACAmcIFMYAFMCAB0ACAmcIFMYAFMCAAAA.Ellyssanna:BAAALgAECgQJCAAAAA==.Elm:BAAALgAECgYJEAAAAA==.Elvina:BAAALgAECgEJAQAAAA==.Elyssaena:BAAALgAECgYJEgAAAA==.',
Em='Emiliachan:BAAALgAECgcJCwAAAA==.',
En='Enzojr:BAACLgAFFH8RAAIhAAUJqxtdFgBZAQAhAAUJqxtdFgBZAQAuAAQKf0QAAiEACQlZJGQCADYDACEACQlZJGQCADYDAAAA.',
Ep='Ephixa:BAABLgAFFH8FAAISAAIJJAZcBgFYAAASAAIJJAZcBgFYAAAAAA==.',
Er='Eridanos:BAAALgADCgYJBgAAAA==.Erisiel:BAAALgAECgEJAQAAAA==.Eruelle:BAACLgAFFH8UAAIFAAYJcCU5CQApAgAFAAYJcCU5CQApAgAuAAQKfyEAAgUACQneJbYBAHADAAUACQneJbYBAHADAAEuAAUUCQkwAA4AzSYA.Erzå:BAAALgAECgEJAgABLgAECgEJAQAEAAAAAA==.',
Ev='Evoke:BAABLgAECn8fAAMLAAgJgyF3CgDOAgALAAgJdB93CgDOAgAiAAYJZyBaDQAEAgAAAA==.',
Ey='Eye:BAACLgAFFH8MAAIjAAQJBiGrCgAUAQAjAAQJBiGrCgAUAQAuAAQKfyAAAyMACQnRIHIHAFYCACMACQnRIHIHAFYCABwAAQmZDN2PACgAAAAA.',
['Eí']='Eís:BAAALgADCgYJCwAAAA==.',
Fa='Faeira:BAAALgAECgcJCQAAAA==.Faloril:BAAALgAECgUJEAAAAA==.Falsara:BAAALgAECgQJBAAAAA==.Faranth:BAABLgAECn9HAAILAAkJbiGKBQAHAwALAAkJbiGKBQAHAwAAAA==.Faronyr:BAAALgAECgEJAQAAAA==.',
Fe='Felboi:BAAALgAECgUJDgAAAA==.Felknight:BAAALgAECgUJCQAAAA==.Felorc:BAAALgAECgQJBwAAAA==.Felynne:BAABLgAECn8cAAMBAAkJbQYxBwC5AAABAAkJbQYxBwC5AAAQAAIJYAKLOQAnAAAAAA==.Fenrík:BAAALgADCgIJAgAAAA==.Feo:BAABLgAECn8eAAIFAAkJexkaJwAvAgAFAAkJexkaJwAvAgAAAA==.Ferkme:BAAALgADCggJCAAAAA==.Ferum:BAABLgAECn9iAAMHAAkJQCWEAQDDAwAHAAkJQCWEAQDDAwAOAAkJyRurCwCaAgAAAA==.',
Fi='Fionnan:BAABLgAECn9HAAIWAAkJPg90GgB6AQAWAAkJPg90GgB6AQABLgAECgkJXgAdAOUQAA==.Firepriest:BAAALgAECgIJAgAAAA==.',
Fo='Forest:BAACLgAFFH8SAAQOAAUJjhQ0IQAWAQAOAAUJjhQ0IQAWAQAHAAIJZwbdYQBXAAAWAAIJtgjNMQBXAAAuAAQKfy4AAw4ACQl6HSkNAMYCAA4ACQl6HSkNAMYCAAcAAwn3GwZtAO0AAAAA.',
Fr='Fraoch:BAAALgAECgcJDAABLgAECgkJSQAOAMwNAA==.Fretless:BAAALgADCgYJCgAAAA==.Frixley:BAAALgAFFAIJAgAAAA==.Friérén:BAAALgAECgEJBAABLgAECgEJAQAEAAAAAA==.Frostedrayne:BAAALgADCgUJBQAAAA==.Frostthrower:BAAALgAECgEJAgAAAA==.Fryeguy:BAAALgAECggJEwAAAA==.',
Fu='Funkysoup:BAAALgAFFAEJAQAAAA==.',
Fy='Fyodor:BAAALgAECgIJBQAAAA==.',
['Fè']='Fèlt:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Fèresha:BAAALgAECgkJEgAAAA==.',
['Fò']='Fòrced:BAABLgAFFH8JAAITAAMJvQRlPQCuAAATAAMJvQRlPQCuAAAAAA==.',
Ga='Gallium:BAABLgAECn8kAAIbAAkJIBi4FABoAgAbAAkJIBi4FABoAgAAAA==.Gannicus:BAAALgAECgEJAQAAAA==.Gazerbeam:BAABLgAECn8VAAIFAAgJAw+abwBEAQAFAAgJAw+abwBEAQAAAA==.',
Ge='Geekshamlama:BAAALgAECgEJAQAAAA==.Geelock:BAAALgADCggJFgAAAA==.Gehena:BAAALgAFFAIJAgABLgAFFAQJCQATAPwaAQ==.Gemsareyum:BAAALgAECgYJDgABLgAFFAcJRgATAKIgAA==.Geode:BAAALgAECgcJDQAAAA==.Gesht:BAABLgAECn8jAAIGAAkJDRHvcwCGAQAGAAkJDRHvcwCGAQAAAA==.Getemwet:BAAALgAECgEJAQAAAA==.',
Gh='Ghostfreak:BAAALgAECgUJBgAAAA==.',
Gi='Gibwibbler:BAAALgADCgEJAQAAAA==.Gidgetz:BAAALgADCgMJAwAAAA==.',
Gl='Glamourkills:BAAALgADCgcJDQAAAA==.Gleipnir:BAAALgAECgMJBQAAAA==.',
Go='Gojirra:BAAALgAECgYJEAAAAA==.Goldenbell:BAAALgAECgUJBQAAAA==.Goof:BAABLgAECn82AAIbAAkJ9Q6bMgCLAQAbAAkJ9Q6bMgCLAQAAAA==.Goontas:BAAALgAECgMJBAAAAA==.',
Gr='Grimsheèper:BAAALgAECgMJBAAAAA==.Grish:BAABLgAECn8ZAAIjAAYJHgaPJQDKAAAjAAYJHgaPJQDKAAAAAA==.Griz:BAAALgAECgQJCAAAAA==.Grollnar:BAAALgAECgEJAQABLgAECgkJDwAEAAAAAA==.Grossevache:BAAALgAECgYJEAAAAA==.Gròws:BAAALgAECgkJBwAAAA==.',
Ha='Haddor:BAABLgAECn8zAAMeAAkJRxytAQAUAgAeAAkJRxytAQAUAgAGAAEJWwRjvQElAAAAAA==.Haelexi:BAAALgAECgUJDwAAAA==.Halujoxar:BAAALgADCgcJDgABLgAFFAEJAQAEAAAAAA==.Hammered:BAAALgAECgcJBwAAAA==.Hamonkulous:BAAALgADCgcJCAAAAA==.Hankerin:BAAALgADCgcJCgAAAA==.Harandar:BAAALgAECgEJAQAAAA==.Harleÿquinn:BAAALgAECgMJAwAAAA==.Harpomage:BAAALgAECgEJAwAAAA==.Hatcher:BAAALgAECgEJAQAAAA==.Haunter:BAABLgAECn8yAAQDAAkJryDwAQBPAgADAAgJzR7wAQBPAgAMAAgJ/RtTAgCeAQASAAYJLR+6dAB6AQAAAA==.Hayleigh:BAACLgAFFH8hAAIHAAgJ7BlRBgCkAgAHAAgJ7BlRBgCkAgAuAAQKfzEAAgcACQmEIgMGAFgDAAcACQmEIgMGAFgDAAAA.',
He='Heimdallr:BAAALgAECgEJAQAAAA==.Heisenborg:BAAALgAECgUJBQAAAA==.Hellbreezy:BAAALgAECgkJEAAAAA==.Helldin:BAABLgAECn8nAAIGAAYJ3hXZogAzAQAGAAYJ3hXZogAzAQAAAA==.Hellenfeller:BAABLgAECn82AAIPAAkJ3hNuBACRAQAPAAkJ3hNuBACRAQAAAA==.Hertrick:BAAALgADCgQJBAAAAA==.',
Hi='Hilitepriest:BAABLgAECn8bAAMIAAgJ0RlvFgAlAgAIAAgJQBlvFgAlAgAKAAIJ1BZvaACLAAAAAA==.Himacini:BAAALgAFFAEJAQABLgAFFAgJIQAHAOwZAA==.Himothyjr:BAAALgAECgUJBQAAAA==.Hittomi:BAAALgAECgYJBgAAAA==.',
Ho='Holific:BAABLgAECn9ZAAIGAAkJQhrVBgD/AQAGAAkJQhrVBgD/AQAAAA==.Honeychild:BAAALgAECgYJCgAAAA==.Hotrodranger:BAAALgAECgcJEgAAAA==.Hottub:BAAALgAECgUJBQAAAA==.',
Hs='Hshyomouth:BAAALgADCgcJBwABLgAECgcJEgAEAAAAAA==.',
Hu='Huckleberry:BAAALgAECgUJBQAAAA==.Hut:BAABLgAFFH8VAAIOAAYJ1BqZEwCBAQAOAAYJ1BqZEwCBAQAAAA==.',
Hv='Hvac:BAABLgAECn89AAIUAAkJIw4yYwC4AQAUAAkJIw4yYwC4AQAAAA==.',
Hy='Hypearione:BAAALgAECgIJAgAAAA==.',
Ia='Ialan:BAAALgADCgQJBgAAAA==.',
Ic='Iceovo:BAAALgADCgEJAQAAAA==.Ichabod:BAAALgAECgEJAQABLgAECgkJJwALAAgVAA==.Icycritties:BAABLgAECn8YAAIUAAYJehAlvQBoAQAUAAYJehAlvQBoAQAAAA==.',
Id='Idovoodew:BAAALgADCgUJCAAAAA==.',
Ih='Iheals:BAAALgAECgMJCQAAAA==.',
Il='Ilaz:BAAALgAECgMJAwAAAA==.Illidon:BAAALgAECgEJAwABLgAECgkJRgAGAC8dAA==.',
Im='Imjustadruid:BAAALgADCggJCwAAAA==.Immortal:BAABLgAECn8mAAMSAAkJBxn0JwBiAgASAAkJBxn0JwBiAgADAAcJtAy5KAAPAQAAAA==.Implants:BAAALgADCggJCQAAAA==.',
In='Incarnate:BAAALgAECgcJEAABLgAFFAUJEgASAGccAA==.Incarnated:BAACLgAFFH8SAAMSAAUJZxxkdQAXAQASAAQJsSFkdQAXAQAMAAMJoRIDFQDjAAAuAAQKfzQAAxIACQnII3cOAPgCABIACQl3I3cOAPgCAAwAAwmBIlIVAC8BAAAA.Inflammation:BAAALgADCgcJDwABLgAECgUJCAAEAAAAAA==.',
Ir='Irocc:BAAALgAECgUJEgAAAA==.Irís:BAAALgAECgEJAgABLgAECgEJAQAEAAAAAA==.',
Is='Ishankyou:BAAALgAECgEJAQAAAA==.Ispithotfire:BAAALgAECgQJBgAAAA==.Istara:BAAALgADCgcJDQABLgAFFAgJHwAUANIfAA==.',
Iu='Iu:BAAALgADCgEJAgAAAA==.',
Ja='Jackdowe:BAAALgAECgQJBAAAAA==.Jackfash:BAAALgADCgcJDQAAAA==.Jadecross:BAABLgAECn8WAAIYAAcJSxYtMwCqAQAYAAcJSxYtMwCqAQAAAA==.Jakiechan:BAAALgAECgEJAQAAAA==.Jalenhunter:BAAALgADCgUJCAAAAA==.',
Je='Jedith:BAAALgAECgcJCQAAAA==.Jerambae:BAABLgAECn8YAAIgAAYJyBWYBACTAQAgAAYJyBWYBACTAQAAAA==.Jerryatric:BAABLgAECn8kAAIGAAkJYxUsEABJAQAGAAkJYxUsEABJAQAAAA==.',
Jk='Jkmno:BAAALgADCgcJBwABLgAECgEJAQAEAAAAAA==.',
Jo='Joelah:BAAALgAECgcJDwAAAA==.Joshua:BAAALgAECgYJDAAAAA==.',
Ju='Justincasê:BAAALgADCggJFQAAAA==.',
['Jà']='Jàvan:BAAALgAFFAMJAwAAAA==.',
['Jâ']='Jây:BAAALgADCgQJBAAAAA==.',
Ka='Kalarian:BAAALgAECgMJAwAAAA==.Kalfeen:BAACLgAFFH8FAAMkAAMJ6xNICQCGAAAkAAIJzxRICQCGAAAWAAEJIxJYPQA2AAAuAAQKfygAAxYACQkLIE4GAJwCABYACQkLIE4GAJwCACQAAQn7BsNeACMAAAAA.Kallikan:BAABLgAECn9cAAIWAAkJ5x+8AADiAgAWAAkJ5x+8AADiAgAAAA==.Kamidk:BAABLgAFFH8JAAISAAQJOhKfXQCUAAASAAQJOhKfXQCUAAABLgAFFAUJEwAFACAeAA==.Kanmojo:BAAALgADCgQJBQAAAA==.Kashume:BAABLgAECn8bAAIjAAkJngINHwABAQAjAAkJngINHwABAQAAAA==.Kasteen:BAABLgAECn8VAAIcAAYJSAWhdwCGAAAcAAYJSAWhdwCGAAAAAA==.Kazon:BAAALgADCgcJCgABLgAFFAQJFAADABMhAA==.Kaøs:BAAALgAECgEJAQAAAA==.',
Kd='Kdoggparker:BAAALgAECgIJAwAAAA==.',
Ke='Kementari:BAAALgAECgYJDQAAAA==.Kenner:BAAALgAECgEJAQAAAA==.Kenzaki:BAACLgAFFH8XAAIGAAUJmQrTWQD8AAAGAAUJmQrTWQD8AAAuAAQKfzgAAgYACQl7G9czADECAAYACQl7G9czADECAAAA.Kesha:BAAALgAECgYJBgABLgAECgkJNwAKABEaAA==.',
Kh='Khaosreborn:BAAALgAECgUJEAAAAA==.Khaotic:BAAALgAECgMJAwAAAA==.',
Ki='Kickin:BAAALgAECgEJAQAAAA==.Kiiren:BAAALgAECgEJAQABLgAFFAMJBQAkAOsTAA==.Kilaaz:BAABLgAECn8VAAIGAAUJzCTrfAB0AQAGAAUJzCTrfAB0AQAAAA==.Kilaz:BAAALgADCgUJBQAAAA==.',
Kn='Knuts:BAACLgAFFH8HAAIaAAQJBRZBJAAZAQAaAAQJBRZBJAAZAQAuAAQKfxYAAhoACQlUGOAeAK8BABoACQlUGOAeAK8BAAAA.',
Ko='Korius:BAAALgAECgUJBQAAAA==.Ková:BAABLgAECn8yAAITAAkJZxljBwD3AQATAAkJZxljBwD3AQAAAA==.',
Kr='Krutesiq:BAAALgADCgkJCQAAAA==.',
Ku='Kuani:BAAALgAECgYJCQABLgAFFAMJCgAYAE4dAA==.Kullman:BAAALgADCgYJCgAAAA==.Kungfupapa:BAAALgAECgQJDAABLgAECgkJFwAOAOoZAA==.Kungfurry:BAAALgAECgUJCAAAAA==.Kurobozu:BAAALgAECgUJCQABLgAECgkJPwALAFsiAA==.Kutherrek:BAAALgAECgEJAQAAAA==.Kuubar:BAABLgAECn8oAAIMAAkJeBZECQDxAQAMAAkJeBZECQDxAQAAAA==.',
Ky='Kyian:BAAALgAECgMJAwAAAA==.',
La='Lacus:BAAALgAECgYJDgAAAA==.Ladaeze:BAAALgADCgIJAgAAAA==.Ladiesnutz:BAACLgAFFH8FAAILAAUJ4RY2KgAfAQALAAUJ4RY2KgAfAQAuAAQKfxoABCUACQm6HhMXAF4BACUABAnhHxMXAF4BAAsABwl6FJQxADsBACIABQlOGysNADsBAAAA.Lagren:BAAALgAECgQJBwAAAA==.Lalatiina:BAAALgAECgIJAgABLgAFFAQJBwAFAMEXAA==.Lathray:BAAALgAECgMJAwAAAA==.Law:BAAALgAECgEJAwABLgAFFAgJIQAHAOwZAA==.Laz:BAAALgADCgMJAwAAAA==.Lazerous:BAAALgADCgYJBgAAAA==.Lazur:BAAALgAECgUJBQAAAA==.',
Le='Leafá:BAAALgAECgEJAgABLgAECgEJAQAEAAAAAA==.Lealoo:BAABLgAECn85AAIGAAkJ4R1KLABQAgAGAAkJ4R1KLABQAgABLgAECgkJSwAPALIaAA==.Leghorn:BAAALgADCgIJAgABLgAFFAMJBQAkAOsTAA==.Legolard:BAABLgAECn8vAAMRAAkJ4SM1AwAGAwARAAkJ4SM1AwAGAwAXAAQJgSHkCgAGAQAAAA==.Lever:BAAALgADCggJCQAAAA==.',
Li='Liath:BAABLgAECn8dAAIKAAcJURhlIwCoAQAKAAcJURhlIwCoAQAAAA==.Liathano:BAAALgAECgQJBwAAAA==.Lichtenberg:BAAALgAECgMJBAABLgAECgkJPwALAFsiAA==.Lightsky:BAAALgADCgIJAQAAAA==.Lildèbbíe:BAABLgAECn8oAAIUAAgJMg3cfAB+AQAUAAgJMg3cfAB+AQAAAA==.Lilspoon:BAAALgADCgYJAwAAAA==.Liltrapstarx:BAAALgAECgQJCAAAAA==.Linddori:BAABLgAECn89AAIGAAkJCR6tAwCSAgAGAAkJCR6tAwCSAgAAAA==.Lindmajik:BAAALgAECgQJBgAAAA==.Liori:BAABLgAECn8oAAIGAAgJ2wpYGwDlAAAGAAgJ2wpYGwDlAAAAAA==.Lirillïa:BAAALgAECgQJBAABLgAECgkJPQAGAAkeAA==.',
Ll='Llyana:BAAALgAECgkJEAABLgAECgkJRwALAG4hAA==.',
Lo='Locdon:BAAALgAECgQJBQABLgAECgkJRgAGAC8dAA==.Lodestone:BAAALgAECgUJCAAAAA==.Loena:BAABLgAECn8iAAIGAAkJXiPHCwAHAwAGAAkJXiPHCwAHAwAAAA==.Lohrick:BAAALgAECgMJAwAAAA==.Lokk:BAAALgAECgcJDAABLgAECgcJDQAEAAAAAA==.Longnuts:BAAALgAECgEJAgAAAA==.Lovelydread:BAAALgAECgUJBgAAAA==.',
Lu='Lunabug:BAACLgAFFH8HAAINAAMJowsDKQCtAAANAAMJowsDKQCtAAAuAAQKfygAAg0ACAl8HSUcAM4BAA0ACAl8HSUcAM4BAAAA.Lupinos:BAAALgADCgYJCAAAAA==.Luquier:BAAALgAECgcJBwABLgAECgkJTQAZAJEhAA==.',
Ly='Lyada:BAAALgAECggJDwAAAA==.Lyadra:BAABLgAECn9CAAIKAAkJrSCTBQAhAwAKAAkJrSCTBQAhAwAAAA==.Lyandre:BAACLgAFFH8NAAMKAAUJhAoXFgAPAQAKAAUJhAoXFgAPAQAIAAQJSQGZNwCrAAAuAAQKfx4AAwoACAlGE4MWACgCAAoACAlGE4MWACgCAAgAAQnAEHJ5ADIAAAAA.Lydra:BAAALgAECgUJBQAAAA==.Lynna:BAAALgADCgQJBAAAAA==.Lyntoo:BAAALgAECgIJAQAAAA==.Lyntu:BAAALgAECgEJAQAAAA==.Lyrissa:BAAALgAECgcJDgAAAA==.',
['Lú']='Lúffy:BAAALgAECgcJCAABLgAFFAQJBwAFAMEXAA==.',
Ma='Maania:BAAALgAECgcJBwAAAA==.Madan:BAABLgAECn89AAISAAkJ0g6YCACiAQASAAkJ0g6YCACiAQAAAA==.Malasminna:BAAALgADCgYJBgAAAA==.Malehorelock:BAAALgAECgYJBwABLgAECggJOAAZAGEhAA==.Malicioun:BAAALgADCgEJAQAAAA==.Malkariss:BAABLgAECn9qAAMUAAkJXiPSAQAvAwAUAAkJXiPSAQAvAwAmAAEJ5AjgHAA5AAAAAA==.Mammadruid:BAABLgAECn9PAAMWAAkJMBENBACAAQAWAAkJMBENBACAAQAHAAYJpwv+cgDcAAAAAA==.Manbearetc:BAAALgAECgUJBQAAAA==.Maralen:BAAALgADCgcJCQAAAA==.Marann:BAAALgAECgYJBgAAAA==.Matadør:BAAALgAECgcJDAAAAA==.Mathwhiz:BAABLgAECn8gAAQbAAYJMRfTPQBOAQAbAAYJMRfTPQBOAQAGAAUJ7gzv6ADTAAAeAAYJ7gAWEQBQAAABLgAECgkJMwAQAEIYAA==.Mauldis:BAABLgAECn9mAAIcAAkJThbeAgAYAgAcAAkJThbeAgAYAgAAAA==.Mavgard:BAAALgAECgIJAgAAAA==.Mavgards:BAAALgADCgMJAwABLgAECgIJAgAEAAAAAA==.Maxrebo:BAABLgAECn8eAAIaAAgJoBtOEwAXAgAaAAgJoBtOEwAXAgAAAA==.',
Me='Meatwàd:BAAALgAECgcJDAAAAA==.Mekanzi:BAAALgAECgUJDQAAAA==.Meliõdas:BAAALgAECgUJEQAAAA==.Merebels:BAAALgAECgQJBwABLgAECggJDwAEAAAAAA==.Merkodisco:BAAALgAECgIJAgAAAA==.Mesi:BAAALgAECgEJAQAAAA==.',
Mi='Miaka:BAABLgAECn9CAAICAAkJESEmAQD9AgACAAkJESEmAQD9AgAAAA==.Miakah:BAABLgAECn8UAAMCAAcJDxnHCQDGAQACAAcJDxnHCQDGAQABAAUJjglmMQD0AAAAAA==.Mibellabella:BAAALgADCgMJAwAAAA==.Midwest:BAAALgADCgQJBAAAAA==.Minigoonta:BAAALgAECgMJAwAAAA==.Minirook:BAAALgADCgEJAQABLgAFFAcJIAASACobAA==.Misfire:BAABLgAECn9UAAITAAkJ3BUFCwChAQATAAkJ3BUFCwChAQAAAA==.Mistbusters:BAABLgAECn8WAAIYAAYJdxF+WgAJAQAYAAYJdxF+WgAJAQAAAA==.Mithra:BAAALgAECgEJAQAAAA==.Mithygos:BAABLgAECn8bAAILAAgJdAVtVADeAAALAAgJdAVtVADeAAAAAA==.Mito:BAAALgAECgIJAgABLgAECgEJAQAEAAAAAA==.',
Mo='Moar:BAAALgAECgEJAgAAAA==.Mogad:BAAALgAECgcJBwAAAA==.Moghroth:BAABLgAECn9AAAMOAAkJYA+aJwCTAQAOAAkJWA+aJwCTAQAWAAEJQwvIfwAiAAAAAA==.Molykote:BAAALgAECgQJCwAAAA==.Monks:BAAALgAFFAIJAgAAAA==.Monsterbabe:BAAALgADCgYJCgAAAA==.Moreleath:BAAALgAECgIJAwAAAA==.Morgiana:BAAALgAECgEJAwABLgAECgEJAQAEAAAAAA==.Mowiewowie:BAAALgAECgEJAQAAAA==.',
Mu='Mugzypatron:BAAALgADCgUJBgAAAA==.',
My='Myhiknee:BAAALgAECgEJAQAAAA==.Myriana:BAAALgAECgQJBwAAAA==.Myrkr:BAAALgAECgEJAgAAAA==.Mysticnugs:BAAALgAFFAEJBAAAAA==.Mystyle:BAAALgADCgcJBwAAAA==.',
['Má']='Mágnus:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâsterdon:BAABLgAECn8UAAIdAAcJ/hfqRQCWAQAdAAcJ/hfqRQCWAQAAAA==.',
['Mã']='Mãtador:BAAALgAFFAEJAgAAAA==.',
Na='Nahryn:BAABLgAECn9qAAIHAAkJqyHlAAA6AwAHAAkJqyHlAAA6AwAAAA==.Najamei:BAAALgADCgUJBQAAAA==.Najanira:BAAALgADCgYJBgAAAA==.Narya:BAAALgAECgIJAwAAAA==.Nathazar:BAAALgAECgkJCQAAAA==.',
Ne='Neia:BAAALgAECgIJAgAAAA==.Nella:BAAALgAECgYJCQABLgAFFAMJCgAYAE4dAA==.Nerbert:BAAALgADCgYJBgABLgAECgkJJwALAAgVAA==.Neretsym:BAABLgAECn8vAAITAAkJMiDoGQCKAgATAAkJMiDoGQCKAgAAAA==.Nergal:BAAALgAECgUJBwAAAA==.Nevercumdin:BAAALgADCgEJAwAAAA==.',
Ni='Nibbzz:BAACLgAFFH8KAAIIAAUJlwVWJQAiAQAIAAUJlwVWJQAiAQAuAAQKfx0AAggACQl1FNYhAMABAAgACQl1FNYhAMABAAAA.Nineva:BAABLgAECn8mAAIHAAkJpgV3aQD4AAAHAAkJpgV3aQD4AAAAAA==.',
No='Nobas:BAABLgAECn9JAAMOAAkJzA10KACNAQAOAAkJzA10KACNAQAHAAEJ6wJ05AAhAAAAAA==.',
Nu='Nugs:BAAALgAECgkJBQAAAA==.',
Ok='Okelani:BAAALgAECgEJAQAAAA==.',
Om='Omen:BAAALgAECggJCQAAAA==.',
On='Onlyfeet:BAAALgAECgQJBwAAAA==.',
Op='Oppgjør:BAABLgAECn8WAAIbAAkJ3RhvEACUAgAbAAkJ3RhvEACUAgAAAA==.',
Or='Oreeree:BAAALgAECgYJBwAAAA==.Orenge:BAAALgAECgQJCAAAAA==.Orkus:BAAALgADCgkJCwAAAA==.Ormr:BAABLgAECn8nAAILAAkJCBXqHwDZAQALAAkJCBXqHwDZAQAAAA==.Orpsa:BAAALgADCgYJBgAAAA==.',
Os='Osteo:BAABLgAECn8uAAQCAAgJDwftFAAmAQACAAgJyAbtFAAmAQAQAAgJXgQ+pgD0AAABAAcJCALAPwC1AAAAAA==.',
Ou='Ouron:BAABLgAECn8mAAMdAAgJwBWIOQDJAQAdAAcJUxaIOQDJAQAcAAYJtQxFZACyAAAAAA==.',
Pa='Papashrimps:BAACLgAFFH8gAAIUAAcJbRgWUQA7AQAUAAcJbRgWUQA7AQAuAAQKfzkAAhQACQl1IuEQAPUCABQACQl1IuEQAPUCAAAA.',
Pe='Penelopee:BAAALgADCgUJBwAAAA==.Perash:BAAALgAECgEJAQAAAA==.',
Ph='Phaere:BAAALgADCgEJAQAAAA==.Phanora:BAAALgAECgEJAgABLgAECgEJAQAEAAAAAA==.Phatcowz:BAAALgADCggJCAAAAA==.Phrazes:BAAALgAECgQJBAAAAA==.',
Pi='Pikyu:BAAALgADCgEJAQAAAA==.Pipsi:BAAALgADCgYJBgAAAA==.',
Pl='Placeholder:BAABLgAECn82AAIeAAkJWR96BAC3AgAeAAkJWR96BAC3AgAAAA==.Plaguestingr:BAABLgAECn9EAAITAAkJDSQfCQAQAwATAAkJDSQfCQAQAwAAAA==.',
Po='Pontifex:BAABLgAECn9GAAIKAAkJdxz0AQBmAgAKAAkJdxz0AQBmAgAAAA==.Poporobo:BAAALgADCgEJAQAAAA==.Portandmorph:BAABLgAECn89AAIUAAkJnRgaBwD2AQAUAAkJnRgaBwD2AQAAAA==.Potlock:BAABLgAECn8VAAMQAAgJbAv1pQD1AAAQAAUJLwr1pQD1AAACAAMJhA7iKwBsAAAAAA==.',
Pr='Prayinmantís:BAAALgADCgkJCQAAAA==.Proey:BAABLgAECn9DAAMJAAkJAhlREABZAgAJAAkJAhlREABZAgAIAAUJJhMpQQAGAQAAAA==.Prone:BAABLgAECn9eAAMdAAkJ5RCtCQB+AQAdAAkJ5RCtCQB+AQAcAAYJewnxWwDQAAAAAA==.',
Ps='Psychokiller:BAAALgADCgYJBgAAAA==.',
Pu='Puf:BAAALgAECgMJBwAAAA==.Puipui:BAAALgAECgEJAgAAAA==.Pumpidan:BAAALgAECgIJBQAAAA==.',
Py='Pyrelyn:BAAALgADCgEJAQAAAA==.',
Qr='Qròw:BAAALgADCgMJAwAAAA==.',
Qu='Quinnifred:BAAALgAECgUJDQAAAA==.',
Ra='Raakotah:BAABLgAECn9JAAIOAAkJKSXCAgBFAwAOAAkJKSXCAgBFAwAAAA==.Raasclaat:BAAALgAECgEJAQAAAA==.Raelo:BAABLgAECn8zAAIjAAkJERaSCQAjAgAjAAkJERaSCQAjAgAAAA==.Raijun:BAAALgAECgUJBQABLgAFFAMJBwALACsIAA==.Raiseurmug:BAABLgAECn8yAAIaAAkJ9BUsFAANAgAaAAkJ9BUsFAANAgAAAA==.Rakash:BAACLgAFFH8WAAISAAUJBhtsWQBAAQASAAUJBhtsWQBAAQAuAAQKfywAAhIACQmTIK0gAL8CABIACQmTIK0gAL8CAAAA.Rarg:BAABLgAFFH8FAAIDAAMJ7xV7EQDMAAADAAMJ7xV7EQDMAAABLgAFFAgJEgARAP0aAA==.Rascaldragon:BAAALgAECgQJBQAAAA==.Ravenlark:BAABLgAECn8ZAAIQAAkJigbregBDAQAQAAkJigbregBDAQAAAA==.Ravia:BAACLgAFFH8HAAIFAAQJwRfBMACtAAAFAAQJwRfBMACtAAAuAAQKfyYAAwUACQlAI2wJAAEDAAUACQmrImwJAAEDABUABQlSITgJAN0BAAAA.Razien:BAAALgADCgEJAQAAAA==.Razuki:BAAALgAECgYJEwABLgAFFAQJDAAbALETAA==.',
Re='Reddale:BAAALgADCgcJDAAAAA==.Redeamer:BAAALgAECgEJAgAAAA==.Reneelyn:BAAALgADCgMJAwAAAA==.Resco:BAACLgAFFH8qAAIXAAkJpBdqBAAvAgAXAAkJpBdqBAAvAgAuAAQKfz0AAhcACQkDJV4FAAsDABcACQkDJV4FAAsDAAAA.Rescotwo:BAAALgAECgYJDgAAAA==.',
Rh='Rhozak:BAABLgAECn8UAAIDAAgJFxtgAgAaAgADAAgJFxtgAgAaAgABLgAECgkJPQAGAAkeAA==.',
Ri='Riddle:BAABLgAECn8pAAIdAAkJTxDFCACVAQAdAAkJTxDFCACVAQAAAA==.Rikitiki:BAAALgAECgEJAQAAAA==.Rimeouo:BAAALgADCgEJAQAAAA==.Rize:BAAALgAECgMJAwABLgAFFAMJBwALACsIAA==.',
Ro='Rocksolid:BAAALgADCgUJBgAAAA==.Ronnie:BAAALgAECgQJBwAAAA==.Rook:BAACLgAFFH8gAAMSAAcJKhsrGwB6AQASAAYJKhsrGwB6AQADAAEJAAAjZwAAAAAuAAQKfykAAhIACAkTIykXAPACABIACAkTIykXAPACAAAA.Rookmonger:BAAALgAECgUJBQABLgAFFAcJIAASACobAA==.Rosenrott:BAABLgAFFH8JAAITAAQJ/BqHFwBSAQATAAQJ/BqHFwBSAQAAAA==.Rosepiercer:BAABLgAECn9AAAITAAkJsSMfCAAbAwATAAkJsSMfCAAbAwAAAA==.Rosies:BAAALgAECgUJBwAAAA==.Rouz:BAABLgAECn8lAAIiAAkJgQ8bAQCoAQAiAAkJgQ8bAQCoAQAAAA==.',
Ru='Rulia:BAAALgAECgMJAwAAAA==.',
Ry='Ryenoh:BAAALgADCgYJBgAAAA==.Rynnoria:BAAALgAECgEJAQAAAA==.Ryoto:BAACLgAFFH8hAAMLAAYJACJlGwCHAQALAAUJrCFlGwCHAQAiAAMJZyLEAwCtAAAuAAQKfxwAAwsACQmHJXMZAAoCAAsACQmHJXMZAAoCACIAAwkXJCMmAPIAAAAA.',
Sa='Sadness:BAAALgADCgYJBwAAAA==.Saelyz:BAAALgADCgQJBAAAAA==.Saetha:BAABLgAECn8eAAIkAAkJtA04BAApAQAkAAkJtA04BAApAQAAAA==.Samandean:BAABLgAECn9LAAIPAAkJshryCgB4AgAPAAkJshryCgB4AgAAAA==.Santhallibar:BAABLgAECn8nAAInAAkJeQPjEQAHAQAnAAkJeQPjEQAHAQAAAA==.Santooth:BAAALgAECgkJEgABLgAECgkJWgABALkdAA==.Sarasvati:BAABLgAECn8nAAIHAAkJoxrlEQDAAgAHAAkJoxrlEQDAAgAAAA==.Saster:BAABLgAECn8hAAISAAkJgiL8DgD0AgASAAkJgiL8DgD0AgAAAA==.Sataniiks:BAAALgADCgEJAQAAAA==.Sathrel:BAAALgADCgIJAgABLgAECgkJBwAEAAAAAA==.',
Sc='Scizophrenia:BAAALgAECgQJBwAAAA==.Scoops:BAAALgAECgcJBwABLgAFFAUJEgASAGccAA==.Scrabs:BAAALgAECgkJDwAAAA==.',
Se='Sellena:BAABLgAECn8uAAIjAAkJMRTmCgAJAgAjAAkJMRTmCgAJAgABLgAECgkJSwAPALIaAA==.Sementha:BAAALgADCgcJDgABLgAECgYJCQAEAAAAAA==.Senpai:BAABLgAECn8UAAIYAAYJyRxQIQCpAQAYAAYJyRxQIQCpAQABLgAFFAgJIQAHAOwZAA==.Sephyra:BAABLgAECn8fAAIRAAkJZAoGBQAlAQARAAkJZAoGBQAlAQAAAA==.',
Sh='Shadowmyst:BAAALgADCgQJCgAAAA==.Shaken:BAAALgAECgUJBgAAAA==.Shandow:BAACLgAFFH8aAAIUAAYJJRlvTwA/AQAUAAYJJRlvTwA/AQAuAAQKf1AAAhQACQmuJFkGAFADABQACQmuJFkGAFADAAAA.Shandowdrag:BAAALgAFFAQJBAABLgAFFAYJGgAUACUZAA==.Shango:BAAALgADCgcJCQAAAA==.Shanshunt:BAAALgAFFAIJAgABLgAFFAYJGgAUACUZAA==.Shansoracle:BAACLgAFFH8dAAIKAAYJvBhDBwDhAQAKAAYJvBhDBwDhAQAuAAQKfyEAAgoACQlhHywEAEIDAAoACQlhHywEAEIDAAEuAAUUBgkaABQAJRkA.Shed:BAACLgAFFH8SAAIcAAUJUx+EFwBgAQAcAAUJUx+EFwBgAQAuAAQKfy0AAhwACAltIZYNAMgCABwACAltIZYNAMgCAAEuAAUUBgkVAA4A1BoA.Sheislegend:BAABLgAECn8cAAIKAAcJpBdkHgDSAQAKAAcJpBdkHgDSAQAAAA==.Shelby:BAABLgAECn83AAMKAAkJERrXDwBrAgAKAAkJERrXDwBrAgAJAAUJcRCoQAANAQAAAA==.Sherminater:BAAALgAECgQJBAAAAA==.Shmoon:BAEALgAECgIJAgABLgAECgUJBgAEAAAAAA==.Shmuckman:BAAALgADCgkJEwAAAA==.Shocked:BAAALgAECgkJBgABLgAECgkJGQAOABMhAA==.Shorttotem:BAAALgADCgUJBQAAAA==.Shoty:BAAALgAECgMJAwABLgAFFAcJIAASACobAA==.Shrimpiness:BAAALgAECgEJAQAAAA==.Shäpeshifter:BAAALgADCgQJBAAAAA==.',
Si='Siccinok:BAABLgAECn9LAAIUAAgJlhiECgCfAQAUAAgJlhiECgCfAQAAAA==.Silicá:BAAALgADCgkJCQABLgAECgEJAQAEAAAAAA==.Sindorian:BAABLgAECn84AAMZAAgJYSFQCQCJAgAZAAgJECBQCQCJAgATAAYJHSIRJwAdAgAAAA==.Sink:BAAALgAECgUJBQAAAA==.Sithlord:BAAALgADCgMJAwAAAA==.Sixhundrdlbs:BAABLgAFFH8GAAIFAAQJtBGzIAAHAQAFAAQJtBGzIAAHAQABLgAFFAUJEgASAGccAA==.Sixseven:BAAALgADCgkJCgABLgAFFAQJBwAFAMEXAA==.',
Sk='Skrimphorn:BAAALgAECgEJAQAAAA==.',
Sl='Slanginbolts:BAAALgADCgYJBgAAAA==.Slimped:BAABLgAECn8cAAMNAAkJcBi4HgC3AQANAAkJihK4HgC3AQAaAAgJNxNTKgBjAQAAAA==.',
Sm='Smurricane:BAAALgAECgUJCAAAAA==.',
Sn='Snowybato:BAAALgAECgUJEgAAAA==.',
So='Solana:BAAALgAECgEJAQAAAA==.Solanwarr:BAABLgAECn89AAQRAAkJTCNDAwAEAwARAAkJKCJDAwAEAwAXAAgJ6B3CFwCOAgAfAAMJnRnAVACDAAABLgAFFAMJBgALAIEMAA==.Solar:BAAALgAECgQJCAAAAA==.Solarial:BAABLgAECn8UAAIUAAcJEBEsLgCAAAAUAAcJEBEsLgCAAAAAAA==.Solastra:BAABLgAECn9oAAIbAAkJDB+mAAAQAwAbAAkJDB+mAAAQAwAAAA==.Sommer:BAAALgAECgcJBwABLgAECgkJTQAOAGUZAA==.Soramai:BAAALgADCgcJDwAAAA==.Soth:BAABLgAECn9JAAMSAAkJ1Ro0JAB0AgASAAkJ1Ro0JAB0AgADAAkJdw92GwCBAQAAAA==.',
Sp='Sparticusdru:BAABLgAECn8WAAIkAAkJih3mBwBVAgAkAAkJih3mBwBVAgAAAA==.Spartpally:BAAALgAECgMJAwAAAA==.Spore:BAAALgAECgMJAwAAAA==.',
Sq='Sqaw:BAAALgAECgEJAQAAAA==.',
St='Starkadia:BAAALgAECgYJBgAAAA==.Staryxia:BAACLgAFFH8gAAMMAAcJ2BKKDAA2AQAMAAYJ2BKKDAA2AQADAAEJAAAySQAAAAAuAAQKfy0AAgwACQmhIUsBAPYCAAwACQmhIUsBAPYCAAAA.Steamdruid:BAAALgAECgYJEQABLgAECgcJEAAEAAAAAA==.Steephany:BAAALgAECgIJAwAAAA==.Stonecookies:BAABLgAECn8kAAMQAAkJ0Qn5bABiAQAQAAkJmgn5bABiAQABAAUJ7AYySQCTAAAAAA==.Stonecross:BAAALgAECgYJCgAAAA==.Stonehard:BAAALgAECgMJAwAAAA==.Stoneldo:BAAALgADCgEJAQAAAA==.Stonetotem:BAAALgAECgYJDAAAAA==.Stormbolt:BAABLgAECn9NAAIOAAkJZRluEwA5AgAOAAkJZRluEwA5AgAAAA==.Stormspirit:BAAALgAECgMJAwAAAA==.Striggen:BAABLgAECn8iAAMGAAkJRRhHFQAWAQAGAAgJPhdHFQAWAQAeAAYJiQ0gEABXAAAAAA==.',
Su='Succystrazsa:BAAALgADCgIJAgAAAA==.Sugarsham:BAABLgAECn8iAAQdAAkJGhZFJwAjAgAdAAkJGhZFJwAjAgAcAAYJ9QaaZwCwAAAjAAQJjgNVJgByAAAAAA==.Sulwen:BAACLgAFFH8wAAIOAAkJzSYLAACTAwAOAAkJzSYLAACTAwAuAAQKfyAAAg4ACQmQJvwEAFEDAA4ACQmQJvwEAFEDAAAA.Sumerset:BAAALgAECgMJBgAAAA==.Sundave:BAAALgAECgYJBgAAAA==.Sunnydee:BAAALgAECggJDwAAAA==.Supaflytnt:BAAALgAECgUJCAAAAA==.Survialspart:BAAALgAECgMJAwAAAA==.Sustia:BAABLgAECn8XAAIoAAgJAg6LDABIAQAoAAgJAg6LDABIAQAAAA==.',
Sy='Syrelina:BAAALgAECgQJBAABLgAFFAQJBwAFAMEXAA==.',
Ta='Tacopie:BAAALgAECgQJBgAAAA==.Taera:BAACLgAFFH8KAAIYAAMJTh3YGwDeAAAYAAMJTh3YGwDeAAAuAAQKfzoAAhgACQmtImUEAGsDABgACQmtImUEAGsDAAAA.Taika:BAAALgADCgkJDwAAAA==.Tailchaser:BAAALgADCgcJBwAAAA==.Talanazar:BAABLgAECn8/AAQLAAkJWyKVBAAeAwALAAkJWyKVBAAeAwAiAAYJgR2AFAChAQAlAAMJ0A7KKgCVAAAAAA==.Talavenn:BAABLgAECn9DAAIFAAkJ6Bw/AwAdAgAFAAkJ6Bw/AwAdAgAAAA==.Tallish:BAABLgAECn8iAAIFAAkJ6wyDnQDnAAAFAAkJ6wyDnQDnAAAAAA==.Taltraxar:BAAALgAECgEJAQABLgAFFAEJAQAEAAAAAA==.Tarage:BAAALgAECgIJAgAAAA==.Tashael:BAAALgAFFAEJAQABLgAFFAMJBQAkAOsTAA==.Taterchip:BAABLgAECn85AAMXAAkJcR0CAwAGAgAXAAkJOx0CAwAGAgARAAIJvRa8PAB/AAAAAA==.Taylia:BAAALgAECgQJBgAAAA==.',
Te='Teaorix:BAAALgADCgQJBAAAAA==.Teds:BAABLgAECn8VAAMPAAYJsRD+CAD6AAAPAAYJsRD+CAD6AAAFAAIJFAqALgBGAAAAAA==.Temporary:BAAALgADCgYJBgAAAA==.Tempus:BAABLgAECn8VAAIGAAgJ9ATiyAD8AAAGAAgJ9ATiyAD8AAAAAA==.Teradoxx:BAAALgAECgYJDgAAAA==.Teriko:BAABLgAECn9GAAMSAAkJ3h4BGgCrAgASAAkJ3h4BGgCrAgADAAcJKgrWMQDWAAAAAA==.Ternock:BAAALgAECgYJDwAAAA==.Terran:BAAALgAECgcJCwABLgAECgkJVAAFADQjAA==.Teviro:BAAALgAECgUJBwABLgAECgkJTQAZAJEhAA==.',
Th='Thanks:BAAALgAECgEJAQAAAA==.Thequixote:BAAALgAECgIJAgAAAA==.Therizino:BAAALgADCgQJBAAAAA==.Thrashy:BAAALgAECgQJCAAAAA==.Thrum:BAAALgAECgkJCwAAAA==.',
Ti='Tictok:BAAALgADCgcJCgAAAA==.Tinkerballa:BAAALgAECgEJAQAAAA==.',
To='Tonkatsu:BAAALgAECgEJAQAAAA==.Tots:BAAALgAFFAEJAQAAAA==.Touchmyudder:BAAALgADCgQJBAABLgADCgcJDQAEAAAAAA==.Toxictotes:BAAALgAECgMJBQAAAA==.',
Ts='Tsargeras:BAAALgAECgQJBAAAAA==.',
Tw='Twiddleado:BAABLgAECn9MAAIUAAkJIBk7LwBcAgAUAAkJIBk7LwBcAgAAAA==.Twinkie:BAAALgAECggJCAABLgAFFAQJBwAFAMEXAA==.Twinkle:BAAALgADCgEJAQAAAA==.',
Ty='Ty:BAAALgAFFAEJAQAAAA==.Tylor:BAAALgAECgYJDwAAAA==.Tyzy:BAAALgAECgEJAQAAAA==.',
['Tå']='Tåkete:BAAALgAECgYJCwAAAA==.',
Uk='Ukuindadookr:BAAALgADCgYJBgAAAA==.',
Um='Ume:BAAALgAECgEJAQABLgAECgQJCAAEAAAAAA==.',
Un='Unta:BAAALgAECgYJCQAAAA==.Unwanted:BAAALgAECgYJBgAAAA==.',
Va='Valaera:BAAALgAECgcJDwAAAA==.Valenora:BAABLgAECn8eAAIBAAkJ3h2NAgCOAgABAAkJ3h2NAgCOAgAAAA==.Valise:BAABLgAECn8wAAICAAkJ0gR5HwDFAAACAAkJ0gR5HwDFAAAAAA==.Varielle:BAAALgAECgYJCQAAAA==.Varuz:BAAALgAECgcJDQAAAA==.Varyz:BAAALgAECgUJBQABLgAECgcJDQAEAAAAAA==.Vaticamt:BAAALgAECgYJBwAAAA==.',
Ve='Vecxx:BAAALgADCgUJBQAAAA==.Velanie:BAAALgAECggJDgAAAA==.Velanise:BAAALgADCgMJAwAAAA==.Velcrostrips:BAAALgAECgEJAQAAAA==.Velight:BAAALgADCgEJAQAAAA==.Velinara:BAAALgAECgEJAQAAAA==.Velindroz:BAAALgAECgMJBgAAAA==.Veloon:BAAALgADCgEJAQAAAA==.Veloras:BAAALgAECgEJAQAAAA==.Verene:BAABLgAECn8qAAIdAAkJuRatIQBFAgAdAAkJuRatIQBFAgAAAA==.Verinari:BAAALgAECgQJBAABLgAECgkJKgAdALkWAA==.',
Vi='Vibes:BAAALgAECgkJBgABLgAECgkJGQAOABMhAA==.Violett:BAAALgAFFAcJAgAAAA==.Viperc:BAEALgADCgMJAwABLgAECgkJMQABAJQLAA==.Vipul:BAAALgAFFAEJAgAAAA==.Viridria:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.Virridian:BAABLgAECn9ZAAITAAkJfyGQCwD3AgATAAkJfyGQCwD3AgAAAA==.Virrigosa:BAAALgAECgYJBgAAAA==.Vistia:BAAALgADCgEJAQAAAA==.Vityazi:BAAALgAECgMJBgABLgAECgkJJwAnAHkDAA==.',
Vl='Vlado:BAAALgAECgYJDAAAAA==.',
Vo='Vodalus:BAAALgADCgUJBQAAAA==.Voideria:BAAALgAECgQJBgAAAA==.Voodoorick:BAAALgAECgEJAgAAAA==.Voolock:BAAALgADCgkJDwAAAA==.',
Vy='Vyshana:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.',
Wa='Walbert:BAAALgAFFAcJBAAAAA==.Wallofshame:BAABLgAECn8uAAMbAAkJxh3sDQC1AgAbAAkJxh3sDQC1AgAGAAQJXg4z6QDTAAAAAA==.Walt:BAAALgADCgIJAgAAAA==.Warchef:BAAALgADCgYJCgABLgAECgkJagAUAF4jAA==.Warriorclaps:BAAALgADCggJDgAAAA==.Wartooth:BAABLgAECn9aAAMBAAkJuR2jAwBWAgAQAAgJFBrwAgBoAgABAAgJ0h2jAwBWAgAAAA==.Wassergott:BAAALgADCgIJAgAAAA==.',
We='Webchi:BAAALgAECgMJAwAAAA==.Webicus:BAABLgAECn8mAAIRAAkJ1BOqEgDBAQARAAkJ1BOqEgDBAQAAAA==.Weezzer:BAAALgADCgQJBAAAAA==.Wegha:BAAALgAECgMJBgAAAA==.Wendee:BAABLgAECn9DAAMKAAkJNQJxQgDiAAAKAAkJNQJxQgDiAAAJAAgJ+gPiXgCcAAAAAA==.',
Wh='Whitefóx:BAACLgAFFH8UAAIeAAUJLRTPBwD9AAAeAAUJLRTPBwD9AAAuAAQKfx4AAh4ACQmYG+wFAIwCAB4ACQmYG+wFAIwCAAEuAAUUBgkaABQAJRkA.Whitley:BAABLgAECn8wAAQdAAkJEyE5BgBNAwAdAAkJEyE5BgBNAwAjAAcJrxWAEgCOAQAcAAEJcB+cGwBYAAAAAA==.',
Wi='Wijing:BAAALgAECgIJAgAAAA==.',
Wo='Wolololo:BAAALgAECgEJAQABLgAECgkJIQASAIIiAA==.Wooden:BAABLgAECn8WAAMTAAkJRBnSBQArAgATAAkJRBnSBQArAgApAAIJOQ6VCwA3AAAAAA==.Worldbreaker:BAAALgADCgEJAQAAAA==.',
['Wü']='Wülfsa:BAAALgAECgUJBQAAAA==.',
Xa='Xampu:BAAALgAECgEJAQAAAA==.Xanthium:BAABLgAECn8wAAIKAAkJogHfVQCEAAAKAAkJogHfVQCEAAAAAA==.Xanzib:BAAALgADCgYJBgAAAA==.Xaphy:BAABLgAECn8VAAIKAAcJ2CCaDQCMAgAKAAcJ2CCaDQCMAgAAAA==.Xardots:BAABLgAECn8lAAIBAAgJohUcDAB9AQABAAgJohUcDAB9AQABLgAFFAEJAQAEAAAAAA==.Xardral:BAAALgAECgcJBwABLgAFFAEJAQAEAAAAAA==.',
Xe='Xeelynn:BAAALgAECgMJAwAAAA==.Xeetali:BAAALgADCgYJBgAAAA==.',
Xi='Xiareth:BAABLgAECn9eAAQlAAkJTA14AwAlAQAlAAkJTA14AwAlAQALAAEJPgqxGwAsAAAiAAEJkAbiKAAqAAAAAA==.',
Xt='Xtronger:BAABLgAECn8gAAIHAAgJmRY/MADhAQAHAAgJmRY/MADhAQAAAA==.',
Xy='Xyra:BAAALgADCgUJBQAAAA==.',
['Xá']='Xároth:BAAALgAFFAEJAQAAAQ==.',
Ya='Yaddi:BAAALgAECgUJCAAAAA==.Yarrow:BAAALgADCgkJEgAAAA==.',
Ye='Yeeyee:BAABLgAECn8ZAAIOAAkJEyG3BQD9AgAOAAkJEyG3BQD9AgAAAA==.',
Yo='Youngjeezy:BAAALgADCgUJCAAAAA==.',
Za='Zackor:BAABLgAECn8YAAIXAAgJmw03BwBSAQAXAAgJmw03BwBSAQAAAA==.Zadoe:BAAALgAECgUJBQAAAA==.Zalik:BAAALgAECgMJAwAAAA==.',
Ze='Zeebo:BAABLgAECn8UAAMiAAcJwwyPDgAiAQAiAAcJwwyPDgAiAQAlAAUJawwQIwDWAAAAAA==.Zest:BAABLgAECn8pAAMlAAkJ2BDMDQDzAQAlAAkJ2BDMDQDzAQALAAIJkAhCfwBgAAAAAA==.',
Zm='Zmaryjane:BAAALgAECgIJBAAAAA==.',
Zo='Zorakfoghorn:BAAALgADCgIJAgAAAA==.Zorakk:BAAALgAECgYJCgAAAA==.Zorithic:BAAALgAECgQJAwAAAA==.Zorrak:BAAALgAECgQJBQAAAA==.',
Zu='Zulls:BAAALgAECgIJAgAAAA==.',
Zy='Zyde:BAABLgAECn8WAAMXAAYJIx3JBgBeAQAXAAYJIx3JBgBeAQAfAAIJABviEgBJAAABLgAECgcJDQAEAAAAAA==.',
['Zæ']='Zælys:BAAALgAECgkJEQAAAA==.',
['År']='Årthas:BAAALgADCgEJAQAAAA==.',
['Øa']='Øake:BAAALgAECgEJAQAAAA==.',
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
