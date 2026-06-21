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

local lookup = {'Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Unknown-Unknown','Paladin-Retribution','Druid-Restoration','Priest-Discipline','Priest-Shadow','Priest-Holy','Evoker-Augmentation','DeathKnight-Frost','Monk-Windwalker','Druid-Balance','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Warrior-Protection','DeathKnight-Unholy','Hunter-BeastMastery','Mage-Frost','DemonHunter-Vengeance','Druid-Guardian','Warrior-Fury','Monk-Mistweaver','Hunter-Survival','Monk-Brewmaster','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','Mage-Fire','Rogue-Subtlety','Evoker-Devastation','Shaman-Enhancement','Paladin-Holy','Druid-Feral','Evoker-Preservation','Mage-Arcane','Rogue-Assassination','Warrior-Arms','Rogue-Outlaw',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Absens:BAABLgAECn8+AAMBAAkJwhIeDAB9AQABAAkJhw8eDAB9AQACAAgJ0hBkDgB2AQAAAA==.',
Ad='Adorian:BAAALgAFFAEJAQABLgAFFAQJFAADABMhAA==.Adwillon:BAAALgADCgQJBQABLgAECgYJEwAEAAAAAA==.',
Ae='Aedoril:BAAALgADCgEJAQAAAA==.Aellea:BAAALgADCgkJCQAAAA==.Aelyss:BAAALgADCgQJBAAAAA==.Aerosse:BAAALgAECgMJAwAAAA==.',
Af='Aforceofone:BAABLgAECn8UAAIFAAUJPQp22gDlAAAFAAUJPQp22gDlAAAAAA==.',
Ai='Airdreanna:BAAALgADCgQJBAAAAA==.',
Ak='Akama:BAAALgAECgcJDAABLgAFFAgJIAAGAOwZAA==.',
Al='Alivanllan:BAAALgAECgIJAgAAAA==.Alteisen:BAAALgAECgUJBQAAAA==.',
Am='Ambitious:BAAALgAECgMJCgAAAA==.Amerlinn:BAAALgAECgYJDAAAAA==.',
An='Anamuht:BAABLgAECn8kAAQHAAkJnhK2GgD6AQAHAAgJeBO2GgD6AQAIAAkJQR3mAABgAQAJAAYJHhDYNAAxAQABLgAECgkJPgAKAFsiAA==.Andryn:BAAALgAECgEJAQAAAA==.Annaday:BAABLgAECn8lAAIDAAkJgQ0OIQBKAQADAAkJgQ0OIQBKAQAAAA==.Antiock:BAACLgAFFH8UAAMDAAQJEyHZEQBsAQADAAQJEyHZEQBsAQALAAQJVBNkDgAmAQAuAAQKfzAAAwMACQn8I6EEAOgCAAMACQn8I6EEAOgCAAsABwnRHIoKANQBAAAA.Anyaesthesia:BAAALgADCgYJBgAAAA==.Anyamonka:BAABLgAECn8YAAIMAAYJWRr4JgB/AQAMAAYJWRr4JgB/AQAAAA==.',
Ap='Apocalich:BAAALgAECgUJBgAAAA==.Appalachia:BAAALgAECgUJBQAAAA==.',
Aq='Aquenia:BAAALgADCggJDAAAAA==.',
Ar='Aralaith:BAABLgAECn8nAAIIAAgJcCUNCADOAgAIAAgJcCUNCADOAgABLgAFFAgJFQANAEQiAA==.Argonaut:BAAALgAECgIJAgAAAA==.Argul:BAAALgAECgIJAgAAAA==.Ariea:BAAALgADCgYJBgAAAA==.Armata:BAAALgAECgEJAQABLgAFFAgJIAAGAOwZAA==.Artoriá:BAAALgAECgEJAQAAAA==.Artto:BAABLgAECn8zAAIFAAgJmxFaawCYAQAFAAgJmxFaawCYAQAAAA==.',
As='Asevenhex:BAAALgAECgEJAQAAAA==.Ashbrínger:BAABLgAECn9HAAIFAAkJDCZtAwBjAwAFAAkJDCZtAwBjAwAAAA==.Association:BAAALgAECgMJAwAAAA==.Astrum:BAAALgAECgEJAgAAAA==.Asunã:BAAALgAECgIJAgABLgAECgEJAQAEAAAAAA==.',
Au='Aurah:BAAALgAECgIJBAAAAA==.',
Av='Averax:BAABLgAECn9GAAMOAAkJQyDOCgDzAgAOAAkJQyDOCgDzAgAPAAEJvQ2JbgA3AAAAAA==.Avyrax:BAAALgAECgEJAQABLgAECgkJRgAOAEMgAA==.',
Ay='Aybara:BAAALgADCgQJBAAAAA==.Aylakaye:BAAALgADCgMJAwAAAA==.Ayraena:BAABLgAECn8ZAAMNAAgJHQjpPQAYAQANAAgJHQjpPQAYAQAGAAQJEgEvyAA9AAAAAA==.',
Az='Azkariel:BAAALgAECgEJAgAAAA==.Azyrieth:BAAALgADCgEJAQAAAA==.Azzathoth:BAAALgADCgcJDAAAAA==.',
Ba='Babyshoes:BAAALgAECgEJAQAAAA==.Backpack:BAAALgAECgUJBQAAAA==.Bakedtofu:BAABLgAECn8UAAMBAAYJ7wc9RwCZAAAQAAYJ7wcP1QCsAAABAAQJGQQ9RwCZAAAAAA==.Basement:BAAALgAECgMJAgABLgAFFAYJEAANAC8YAA==.Bashine:BAABLgAECn8WAAIRAAYJVxlZGACTAQARAAYJVxlZGACTAQABLgAFFAcJHQASAPMeAA==.Baylohn:BAABLgAECn8lAAITAAkJhRaHMwAOAgATAAkJhRaHMwAOAgAAAA==.',
Be='Bearwrestler:BAABLgAECn8aAAIUAAgJ1BfVYgC5AQAUAAgJ1BfVYgC5AQABLgAFFAQJDwADAJAgAA==.Beefynugs:BAAALgAECgkJAgAAAA==.',
Bi='Bier:BAAALgAECgUJDgAAAA==.Bigrig:BAABLgAECn8dAAITAAkJgAV7BwCYAAATAAkJgAV7BwCYAAAAAA==.Bitterman:BAABLgAECn8zAAMQAAkJQhiIIABiAgAQAAkJQhiIIABiAgABAAEJww/ZcAA1AAAAAA==.',
Bj='Bjornvalion:BAAALgADCgQJBAAAAA==.',
Bl='Blackmage:BAAALgAECgEJAQAAAA==.Bladed:BAABLgAECn8mAAQVAAgJiBnADgBlAQAOAAgJTxFCVgCEAQAVAAYJChvADgBlAQAPAAQJFxIPQgCuAAAAAA==.Blinkerfluid:BAAALgADCgIJAgAAAA==.Blinx:BAAALgADCgQJBAAAAA==.Bloodymess:BAABLgAECn8aAAISAAgJQAqohABaAQASAAgJQAqohABaAQAAAA==.',
Bo='Bohikeog:BAAALgAECgIJAgAAAA==.Boogies:BAAALgADCgQJBwAAAA==.Bovinedivine:BAAALgAECgYJBgABLgAFFAEJAQAEAAAAAA==.Bowyardee:BAAALgAECgEJAQAAAA==.',
Bu='Buffie:BAABLgAECn8ZAAIFAAgJGhoeWADaAQAFAAgJGhoeWADaAQAAAA==.Bullwyf:BAAALgADCgMJAwAAAA==.Bumblbeetuna:BAAALgAECgMJAwAAAA==.',
['Bá']='Bád:BAAALgADCggJDgABLgAECgYJHAAWAEwQAA==.',
Ca='Calduu:BAAALgAECgQJCAAAAA==.Caledia:BAAALgAECgYJEQAAAA==.Callana:BAAALgADCgMJBQAAAA==.Camedra:BAABLgAECn9KAAIGAAkJnCQsAgCxAwAGAAkJnCQsAgCxAwAAAA==.Carinancey:BAAALgAECgQJBQAAAA==.Carperoni:BAAALgADCgcJBwAAAA==.Casseous:BAAALgADCgUJBwAAAA==.Castrada:BAAALgAECgUJBQABLgAECgkJUQAFAAEaAA==.Catamynyia:BAABLgAECn8kAAITAAkJpQ5aSQDFAQATAAkJpQ5aSQDFAQAAAA==.Caylaetal:BAAALgAECgEJAQAAAA==.',
Cc='Cchaos:BAAALgAECgIJBgAAAA==.',
Ce='Celaborn:BAABLgAECn8hAAIXAAkJjx7TAACCAQAXAAkJjx7TAACCAQAAAA==.Celice:BAAALgAECgcJBwABLgAFFAMJCAAYANMTAA==.Cerwan:BAAALgADCgMJAwAAAA==.',
Ch='Chazaraz:BAABLgAECn8+AAMZAAkJVxEnEwAOAgAZAAkJABEnEwAOAgATAAgJEgidiwAoAQAAAA==.Chazsquatch:BAAALgAECgUJCgABLgAECgkJPgAZAFcRAA==.Chevy:BAAALgAECgEJAwAAAA==.Chifreak:BAAALgAFFAIJAgABLgAECgkJJgAOAEAjAA==.Chillmourne:BAAALgAECgcJEwABLgAECggJFgABAJIIAA==.Chimaira:BAAALgADCgIJAgAAAA==.Chucknoris:BAAALgAECgQJDQAAAA==.Chugbuggins:BAAALgAECgYJEwAAAA==.',
Ci='Cindria:BAABLgAECn8lAAIUAAgJuBA1eQCGAQAUAAgJuBA1eQCGAQAAAA==.',
Cl='Clare:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Clerks:BAAALgAECgIJAgAAAA==.Cliffgate:BAAALgADCgMJAwAAAA==.',
Co='Colaitis:BAAALgADCgIJAgAAAA==.Conduction:BAAALgAECgUJCAAAAA==.Corenthia:BAAALgAECgYJEwAAAA==.',
Cp='Cptbonez:BAAALgAECgYJEgABLgAECgkJMgAaAPQVAA==.',
Cr='Crankadin:BAAALgAECgEJAgABLgAECgIJBAAEAAAAAA==.Crankchi:BAAALgAECgIJAwABLgAECgIJBAAEAAAAAA==.Crazz:BAAALgADCgEJAQAAAA==.Crewz:BAAALgADCgQJBAAAAA==.Crooky:BAAALgADCgcJBwABLgAFFAYJHwASACQcAA==.Crucifiiks:BAAALgAFFAIJAgAAAA==.Cruciö:BAAALgAECgEJAQAAAA==.Crànk:BAAALgAECgIJBAAAAA==.Cránk:BAAALgAECgEJAQABLgAECgIJBAAEAAAAAA==.Crãnk:BAAALgAECgIJAwABLgAECgIJBAAEAAAAAA==.',
Cu='Curveball:BAABLgAECn8VAAMbAAkJuwweWgBQAQAbAAgJwwkeWgBQAQAcAAkJmgrUSAARAQABLgAECgkJMwAQAEIYAA==.',
Cy='Cyniar:BAAALgAECgcJEwAAAA==.',
Da='Dalearnhardt:BAAALgADCgcJDgABLgAECgcJEgAEAAAAAA==.Damerlin:BAABLgAECn8XAAMFAAgJjQ+veQB7AQAFAAgJjQ+veQB7AQAdAAQJ+QMlPgBkAAAAAA==.Damzel:BAAALgAECgMJAwAAAA==.Darkhuntress:BAAALgAECgcJBwAAAA==.Darkstär:BAABLgAECn9KAAIDAAkJDh/gBgCwAgADAAkJDh/gBgCwAgAAAA==.Darkun:BAAALgAECgUJCQABLgAECgkJMwAKABsUAA==.Darkwood:BAAALgADCgEJAgAAAA==.Dauc:BAAALgADCgEJAQAAAA==.Davesdemise:BAAALgADCgQJBAAAAA==.',
De='Deacon:BAABLgAECn9CAAQaAAkJNQgQMQA+AQAaAAkJvgYQMQA+AQAMAAUJmgpbXQChAAAYAAUJfQRXkQB2AAAAAA==.Deadmantooth:BAAALgADCgYJBgABLgAECgkJRwABAGUbAA==.Deardren:BAAALgAECgUJBQAAAA==.Deathcorps:BAAALgAECgMJAwAAAA==.Deathgripbtw:BAAALgAECgMJAwAAAA==.Deathknights:BAAALgAFFAEJAQAAAA==.Deathtrol:BAAALgAECggJDwAAAA==.Deeanne:BAAALgAECgQJBwAAAA==.Deepdeuce:BAAALgAECgYJCgAAAA==.Deepfriar:BAABLgAECn9RAAMJAAkJLCWbAQChAwAJAAkJLCWbAQChAwAIAAcJMRSVLAByAQAAAA==.Deidra:BAAALgADCgMJAwAAAA==.Demonhunts:BAABLgAFFH8KAAIOAAUJgQk7WQDkAAAOAAUJgQk7WQDkAAAAAA==.Demonmore:BAABLgAECn8jAAMPAAgJxAsQKwAnAQAPAAgJ2AoQKwAnAQAVAAUJWQoIIQCVAAAAAA==.Derailed:BAAALgAECgQJBwAAAA==.Dethwing:BAAALgAECgIJAgAAAA==.Devilfrost:BAAALgAECgEJAQABLgAECgMJBgAEAAAAAA==.Dewshine:BAAALgAECgYJCwAAAA==.',
Dh='Dhampir:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Dhgeek:BAAALgAECgUJCQAAAA==.',
Di='Diablognomis:BAABLgAECn8YAAIMAAYJLRrXJgB/AQAMAAYJLRrXJgB/AQAAAA==.Diarmac:BAAALgAECgcJDgABLgAECgkJVQAbAKYOAA==.Dingô:BAAALgAECgQJBgAAAA==.Dirtman:BAACLgAFFH8FAAIcAAQJDw5tKQDvAAAcAAQJDw5tKQDvAAAuAAQKfywAAhwACQmkHNwSAFgCABwACQmkHNwSAFgCAAAA.',
Dk='Dkrise:BAAALgAECgMJAwABLgAECgkJMwAKABsUAA==.',
Dn='Dneoh:BAAALgAECgkJCAABLgAFFAMJCgANAOciAA==.',
Do='Donald:BAAALgADCgQJBAAAAA==.Donny:BAABLgAECn8zAAMFAAgJlB7ZKgBWAgAFAAgJdh7ZKgBWAgAdAAMJ6xn2AgBaAAAAAA==.Doodyshamala:BAAALgAECgUJDwAAAA==.Dooky:BAAALgAECgYJBwABLgAFFAYJHwASACQcAA==.Doozey:BAACLgAFFH8PAAIOAAQJJxYgRAAbAQAOAAQJJxYgRAAbAQAuAAQKfykAAw4ACQniHu8bAGwCAA4ACQlaHu8bAGwCABUAAQnNE9oxADwAAAAA.Dorigis:BAAALgADCgkJOwABLgAECgkJJgARAE8jAA==.Dotdotdotded:BAABLgAECn8WAAIQAAgJuAWjlgAPAQAQAAgJuAWjlgAPAQAAAA==.',
Dr='Drewdog:BAABLgAECn9CAAMZAAkJ2RcqEgAYAgAZAAkJfBQqEgAYAgATAAcJJBfPAwAQAQAAAA==.Droid:BAAALgAECgEJAgAAAA==.Drunkgerardo:BAAALgAECgQJBQAAAA==.Drunkzen:BAAALgAECgUJCAAAAA==.Druyesil:BAAALgAECgEJAgAAAA==.',
Du='Dubes:BAABLgAECn9FAAIUAAkJABq8JwB7AgAUAAkJABq8JwB7AgAAAA==.Dunbartian:BAABLgAECn8XAAIRAAcJuxaxAABDAQARAAcJuxaxAABDAQAAAA==.Duskfang:BAAALgAECgEJAgAAAA==.',
['Dá']='Dárkthorn:BAAALgAECgIJBAAAAA==.',
['Dö']='Dökkálfar:BAAALgAECgEJAQAAAA==.',
Ea='Easybreezin:BAAALgAECgUJDAAAAA==.',
Ei='Eirote:BAABLgAECn9XAAIeAAkJhx1NAQCpAgAeAAkJhx1NAQCpAgAAAA==.',
El='Elarris:BAAALgAECgcJDQAAAA==.Eldari:BAABLgAECn8YAAINAAgJ2htbGwDwAQANAAgJ2htbGwDwAQAAAA==.Elem:BAACLgAFFH8PAAIbAAYJUwgAKQBCAQAbAAYJUwgAKQBCAQAuAAQKfyMAAhsACAmcIFMYAFMCABsACAmcIFMYAFMCAAAA.Ellyssanna:BAAALgAECgMJBAAAAA==.Elm:BAAALgAECgYJEAAAAA==.Elyssaena:BAAALgAECgYJEgAAAA==.',
Em='Emiliachan:BAAALgAECgcJCwAAAA==.',
En='Enzojr:BAACLgAFFH8QAAIfAAQJqxtjFgBZAQAfAAQJqxtjFgBZAQAuAAQKf0QAAh8ACQlZJGQCADYDAB8ACQlZJGQCADYDAAAA.',
Ep='Ephixa:BAAALgAFFAIJBAAAAA==.',
Er='Eridanos:BAAALgADCgYJBgAAAA==.Erisiel:BAAALgAECgEJAQAAAA==.Eruelle:BAACLgAFFH8MAAIOAAQJICTnIwCgAQAOAAQJICTnIwCgAQAuAAQKfyEAAg4ACQneJbUBAHADAA4ACQneJbUBAHADAAEuAAUUCAkVAA0ARCIA.Erzå:BAAALgAECgEJAgABLgAECgEJAQAEAAAAAA==.',
Ev='Evoke:BAABLgAECn8fAAMKAAgJgyF3CgDOAgAKAAgJdB93CgDOAgAgAAYJZyBaDQAEAgAAAA==.',
Ey='Eye:BAACLgAFFH8KAAIhAAQJBiGtCgAUAQAhAAQJBiGtCgAUAQAuAAQKfyAAAyEACQnRIHIHAFYCACEACQnRIHIHAFYCABwAAQmZDN2PACgAAAAA.',
['Eí']='Eís:BAAALgADCgYJCwAAAA==.',
Fa='Faeira:BAAALgAECgcJCQAAAA==.Faloril:BAAALgAECgUJCwAAAA==.Falsara:BAAALgAECgQJBAAAAA==.Faranth:BAABLgAECn9GAAIKAAkJcyGKBQAHAwAKAAkJcyGKBQAHAwAAAA==.Faronyr:BAAALgAECgEJAQAAAA==.',
Fe='Felboi:BAAALgAECgUJDgAAAA==.Felknight:BAAALgAECgUJCAAAAA==.Felorc:BAAALgAECgQJBwAAAA==.Felynne:BAABLgAECn8ZAAIBAAkJXQY8AQCyAAABAAkJXQY8AQCyAAAAAA==.Fenrík:BAAALgADCgIJAgAAAA==.Feo:BAABLgAECn8eAAIOAAkJexkeJwAvAgAOAAkJexkeJwAvAgAAAA==.Ferum:BAABLgAECn9aAAMGAAkJQCWEAQDDAwAGAAkJQCWEAQDDAwANAAkJyRuqCwCaAgAAAA==.',
Fi='Fionnan:BAABLgAECn9HAAIWAAkJPg9zGgB6AQAWAAkJPg9zGgB6AQABLgAECgkJVQAbAKYOAA==.Firepriest:BAAALgAECgIJAgAAAA==.',
Fo='Forest:BAACLgAFFH8PAAQNAAUJjhQ7IQAWAQANAAUJjhQ7IQAWAQAGAAIJZwbgYQBXAAAWAAIJtgjOMQBXAAAuAAQKfy4AAw0ACQl6HSkNAMYCAA0ACQl6HSkNAMYCAAYAAwn3GwltAO0AAAAA.',
Fr='Fraoch:BAAALgAECgcJDAABLgAECgkJSAANACYNAA==.Fretless:BAAALgADCgYJCgAAAA==.Frixley:BAAALgAFFAIJAgAAAA==.Friérén:BAAALgAECgEJBAABLgAECgEJAQAEAAAAAA==.Frostedrayne:BAAALgADCgUJBQAAAA==.Frostthrower:BAAALgAECgEJAgAAAA==.Fryeguy:BAAALgAECggJEwAAAA==.',
Fu='Funkysoup:BAAALgADCgYJBgAAAA==.',
Fy='Fyodor:BAAALgAECgIJBQAAAA==.',
['Fè']='Fèresha:BAAALgAECgkJEgAAAA==.',
['Fò']='Fòrced:BAAALgAFFAEJAQAAAA==.',
Ga='Gallium:BAABLgAECn8kAAIiAAkJIBi4FABoAgAiAAkJIBi4FABoAgAAAA==.Gazerbeam:BAAALgAFFAEJAQAAAA==.',
Ge='Geekshamlama:BAAALgADCgEJAQAAAA==.Geelock:BAAALgADCggJFgAAAA==.Gehena:BAAALgAFFAIJAgABLgAFFAIJAwAEAAAAAQ==.Gemsareyum:BAAALgAECgYJDgABLgAFFAcJQgATAKIgAA==.Geode:BAAALgAECgcJDQAAAA==.Gesht:BAABLgAECn8dAAIFAAkJVRDycwCGAQAFAAkJVRDycwCGAQAAAA==.Getemwet:BAAALgAECgEJAQAAAA==.',
Gh='Ghostfreak:BAAALgAECgUJBgAAAA==.',
Gi='Gidgetz:BAAALgADCgMJAwAAAA==.',
Gl='Glamourkills:BAAALgADCgcJDQAAAA==.Gleipnir:BAAALgAECgMJBAAAAA==.',
Go='Gojirra:BAAALgAECgYJDwAAAA==.Goldenbell:BAAALgAECgUJBQAAAA==.Goof:BAABLgAECn82AAIiAAkJ9Q6cMgCLAQAiAAkJ9Q6cMgCLAQAAAA==.Goontas:BAAALgAECgMJBAAAAA==.',
Gr='Grimsheèper:BAAALgAECgMJBAAAAA==.Grish:BAABLgAECn8ZAAIhAAYJHgaQJQDKAAAhAAYJHgaQJQDKAAAAAA==.Griz:BAAALgAECgQJCAAAAA==.Grollnar:BAAALgAECgEJAQABLgAECgkJDwAEAAAAAA==.Grossevache:BAAALgAECgYJEAAAAA==.Gròws:BAAALgAECgkJBwAAAA==.',
Ha='Haddor:BAABLgAECn8sAAMdAAkJXBo7CABVAgAdAAkJXBo7CABVAgAFAAEJWwRgvQElAAAAAA==.Haelexi:BAAALgAECgQJCgAAAA==.Halujoxar:BAAALgADCgcJDgABLgAFFAEJAQAEAAAAAA==.Hamonkulous:BAAALgADCgcJCAAAAA==.Hankerin:BAAALgADCgcJCgAAAA==.Harandar:BAAALgAECgEJAQAAAA==.Harleÿquinn:BAAALgAECgIJAgAAAA==.Harpomage:BAAALgADCgcJCQAAAA==.Hatcher:BAAALgAECgEJAQAAAA==.Haunter:BAABLgAECn8iAAQSAAkJiiC3dAB6AQASAAYJLR+3dAB6AQADAAUJlR4oIgBBAQALAAIJrxvhJACpAAAAAA==.Hayleigh:BAACLgAFFH8gAAIGAAgJ7BlVBgCkAgAGAAgJ7BlVBgCkAgAuAAQKfzEAAgYACQmEIgMGAFgDAAYACQmEIgMGAFgDAAAA.',
He='Heimdallr:BAAALgAECgEJAQAAAA==.Heisenborg:BAAALgAECgUJBQAAAA==.Hellbreezy:BAAALgAECgkJEAAAAA==.Helldin:BAABLgAECn8nAAIFAAYJ3hXZogAzAQAFAAYJ3hXZogAzAQAAAA==.Hellenfeller:BAABLgAECn8nAAIPAAYJ9RXjJgBDAQAPAAYJ9RXjJgBDAQAAAA==.',
Hi='Hilitepriest:BAABLgAECn8bAAMHAAgJ0RluFgAlAgAHAAgJQBluFgAlAgAJAAIJ1BZvaACLAAAAAA==.Hittomi:BAAALgAECgYJBgAAAA==.',
Ho='Holific:BAABLgAECn9RAAIFAAkJARpdJgBrAgAFAAkJARpdJgBrAgAAAA==.Honeychild:BAAALgAECgYJCgAAAA==.Hotrodranger:BAAALgAECgcJEgAAAA==.Hottub:BAAALgAECgUJBQAAAA==.',
Hu='Huckleberry:BAAALgAECgUJBQAAAA==.Hut:BAABLgAFFH8QAAINAAYJLxihEwCBAQANAAYJLxihEwCBAQAAAA==.',
Hv='Hvac:BAABLgAECn89AAIUAAkJIw4wYwC4AQAUAAkJIw4wYwC4AQAAAA==.',
Hy='Hypearione:BAAALgADCgIJAgAAAA==.',
Ia='Ialan:BAAALgADCgQJBgAAAA==.',
Ic='Iceovo:BAAALgADCgEJAQAAAA==.Icycritties:BAABLgAECn8YAAIUAAYJehAlvQBoAQAUAAYJehAlvQBoAQAAAA==.',
Id='Idovoodew:BAAALgADCgUJCAAAAA==.',
Ih='Iheals:BAAALgAECgMJCQAAAA==.',
Il='Illidon:BAAALgAECgEJAQAAAA==.',
Im='Imjustadruid:BAAALgADCggJCwAAAA==.Immortal:BAABLgAECn8mAAMSAAkJBxnzJwBiAgASAAkJBxnzJwBiAgADAAcJtAy2KAAPAQAAAA==.Implants:BAAALgADCggJCQAAAA==.',
In='Incarnate:BAAALgAECgcJEAABLgAFFAUJEQASACscAA==.Incarnated:BAACLgAFFH8RAAMSAAUJKxxrdQAXAQASAAQJYiFrdQAXAQALAAMJoRICFQDjAAAuAAQKfzMAAxIACQnII3YOAPgCABIACQl3I3YOAPgCAAsAAwmBIlIVAC8BAAAA.Inflammation:BAAALgADCgcJDwABLgAECgUJCAAEAAAAAA==.',
Ir='Irocc:BAAALgAECgUJEgAAAA==.Irís:BAAALgAECgEJAgABLgAECgEJAQAEAAAAAA==.',
Is='Ishankyou:BAAALgAECgEJAQAAAA==.Ispithotfire:BAAALgAECgMJAwAAAA==.Istara:BAAALgADCgcJDQABLgAFFAgJHwAUANIfAA==.',
Iu='Iu:BAAALgADCgEJAgAAAA==.',
Ja='Jackdowe:BAAALgAECgQJBAAAAA==.Jackfash:BAAALgADCgcJDQAAAA==.Jadecross:BAABLgAECn8WAAIYAAcJSxYqMwCqAQAYAAcJSxYqMwCqAQAAAA==.Jalenhunter:BAAALgADCgUJCAAAAA==.',
Je='Jedith:BAAALgAECgcJCQAAAA==.Jerambae:BAABLgAECn8YAAIeAAYJyBWYBACTAQAeAAYJyBWYBACTAQAAAA==.Jerryatric:BAABLgAECn8XAAIFAAkJhQwobgCSAQAFAAkJhQwobgCSAQAAAA==.',
Jk='Jkmno:BAAALgADCgcJBwAAAA==.',
Jo='Joelah:BAAALgAECgcJDwAAAA==.Joshua:BAAALgAECgYJDAAAAA==.',
Ju='Justincasê:BAAALgADCggJFQAAAA==.',
['Jâ']='Jây:BAAALgADCgQJBAAAAA==.',
Ka='Kalarian:BAAALgAECgMJAwAAAA==.Kalfeen:BAABLgAECn8hAAMWAAgJlSFOBgCcAgAWAAgJlSFOBgCcAgAjAAEJ+wa+XgAjAAAAAA==.Kallikan:BAABLgAECn83AAIWAAkJsRloCgA/AgAWAAkJsRloCgA/AgAAAA==.Kamidk:BAABLgAFFH8HAAISAAQJ1g1gygCZAAASAAQJ1g1gygCZAAABLgAFFAUJEwAOACAeAA==.Kanmojo:BAAALgADCgQJBQAAAA==.Kashume:BAABLgAECn8bAAIhAAkJngINHwABAQAhAAkJngINHwABAQAAAA==.Kasteen:BAABLgAECn8VAAIcAAYJSAVcBABgAAAcAAYJSAVcBABgAAAAAA==.Kazon:BAAALgADCgcJCgABLgAFFAQJFAADABMhAA==.Kaøs:BAAALgAECgEJAQAAAA==.',
Kd='Kdoggparker:BAAALgAECgIJAwAAAA==.',
Ke='Kementari:BAAALgAECgQJBQAAAA==.Kenner:BAAALgAECgEJAQAAAA==.Kenzaki:BAACLgAFFH8VAAIFAAUJmQrcWQD8AAAFAAUJmQrcWQD8AAAuAAQKfzgAAgUACQl7G9YzADECAAUACQl7G9YzADECAAAA.Kesha:BAAALgAECgYJBgABLgAECgkJNQAJABEaAA==.',
Kh='Khaosreborn:BAAALgAECgUJEAAAAA==.Khaotic:BAAALgADCgMJAwABLgADCgQJBAAEAAAAAA==.',
Ki='Kiiren:BAAALgAECgEJAQABLgAECggJIQAWAJUhAA==.Kilaaz:BAABLgAECn8VAAIFAAUJzCTufAB0AQAFAAUJzCTufAB0AQAAAA==.Kilaz:BAAALgADCgUJBQAAAA==.',
Kn='Knuts:BAACLgAFFH8HAAIaAAQJBRZJJAAZAQAaAAQJBRZJJAAZAQAuAAQKfxYAAhoACQlUGN4eAK8BABoACQlUGN4eAK8BAAAA.',
Ko='Korius:BAAALgAECgUJBQAAAA==.Ková:BAABLgAECn8qAAITAAgJmBrdNAAJAgATAAgJmBrdNAAJAgAAAA==.',
Kr='Krutesiq:BAAALgADCgkJCQAAAA==.',
Ku='Kuani:BAAALgAECgYJCQABLgAFFAMJCAAYANMTAA==.Kullman:BAAALgADCgYJCgAAAA==.Kungfupapa:BAAALgAECgQJCQAAAA==.Kungfurry:BAAALgAECgUJCAAAAA==.Kurobozu:BAAALgAECgUJCQABLgAECgkJPgAKAFsiAA==.Kutherrek:BAAALgAECgEJAQAAAA==.Kuubar:BAABLgAECn8mAAILAAkJ/RVECQDxAQALAAkJ/RVECQDxAQAAAA==.',
Ky='Kyian:BAAALgAECgMJAwAAAA==.',
La='Lacus:BAAALgAECgYJDQAAAA==.Ladaeze:BAAALgADCgIJAgAAAA==.Ladiesnutz:BAACLgAFFH8FAAIKAAUJ4RY6KgAfAQAKAAUJ4RY6KgAfAQAuAAQKfxoABCQACQm6HhMXAF4BACQABAnhHxMXAF4BAAoABwl6FJQxADsBACAABQlOGywNADsBAAAA.Lalatiina:BAAALgAECgIJAgABLgAECgkJJgAOAEAjAA==.Law:BAAALgAECgEJAwABLgAFFAgJIAAGAOwZAA==.Laz:BAAALgADCgMJAwAAAA==.Lazerous:BAAALgADCgYJBgAAAA==.',
Le='Leafá:BAAALgAECgEJAgABLgAECgEJAQAEAAAAAA==.Lealoo:BAABLgAECn81AAIFAAkJwR3HAQCCAQAFAAkJwR3HAQCCAQABLgAECgkJSwAPALIaAA==.Leghorn:BAAALgADCgIJAgABLgAECggJIQAWAJUhAA==.Legolard:BAABLgAECn8mAAMRAAkJTyM1AwAGAwARAAkJTyM1AwAGAwAXAAQJ7yBgSAAkAQAAAA==.Lever:BAAALgADCggJCQAAAA==.',
Li='Liath:BAABLgAECn8VAAIJAAYJlBphIwCoAQAJAAYJlBphIwCoAQAAAA==.Liathano:BAAALgAECgQJBgAAAA==.Lichtenberg:BAAALgAECgMJBAABLgAECgkJPgAKAFsiAA==.Lightsky:BAAALgADCgIJAQAAAA==.Lildèbbíe:BAABLgAECn8oAAIUAAgJMg3efAB+AQAUAAgJMg3efAB+AQAAAA==.Lilspoon:BAAALgADCgMJAwAAAA==.Liltrapstarx:BAAALgAECgQJCAAAAA==.Linddori:BAABLgAECn8uAAIFAAkJPhnBMAA+AgAFAAkJPhnBMAA+AgAAAA==.Lindmajik:BAAALgAECgQJBgAAAA==.Liori:BAABLgAECn8kAAIFAAgJ2grWAwD8AAAFAAgJ2grWAwD8AAAAAA==.Lirillïa:BAAALgADCggJDQABLgAECgkJLgAFAD4ZAA==.',
Ll='Llyana:BAAALgAECgkJEAABLgAECgkJRgAKAHMhAA==.',
Lo='Lodestone:BAAALgADCgMJAwAAAA==.Loena:BAABLgAECn8iAAIFAAkJXiPFCwAHAwAFAAkJXiPFCwAHAwAAAA==.Lokk:BAAALgAECgYJCQABLgAECgYJEAAEAAAAAA==.Longnuts:BAAALgAECgEJAgAAAA==.Lovelydread:BAAALgAECgUJBgAAAA==.',
Lu='Lunabug:BAACLgAFFH8HAAIMAAMJowsFKQCtAAAMAAMJowsFKQCtAAAuAAQKfygAAgwACAl8HSQcAM4BAAwACAl8HSQcAM4BAAAA.Lupinos:BAAALgADCgYJCAAAAA==.',
Ly='Lyada:BAAALgAECgUJBQAAAA==.Lyadra:BAABLgAECn89AAIJAAkJhR+UBQAhAwAJAAkJhR+UBQAhAwAAAA==.Lyandre:BAACLgAFFH8NAAMJAAUJhAoWFgAPAQAJAAUJhAoWFgAPAQAHAAQJSQGgNwCrAAAuAAQKfx4AAwkACAlGE4MWACgCAAkACAlGE4MWACgCAAcAAQnAEHF5ADIAAAAA.Lydra:BAAALgAECgUJBQAAAA==.Lynna:BAAALgADCgQJBAAAAA==.Lyntoo:BAAALgAECgIJAQAAAA==.Lyntu:BAAALgAECgEJAQAAAA==.Lyrissa:BAAALgAECgcJDgAAAA==.',
['Lú']='Lúffy:BAAALgAECgcJBwABLgAECgkJJgAOAEAjAA==.',
Ma='Maania:BAAALgAECgcJBwAAAA==.Madan:BAABLgAECn8nAAISAAgJZQpaBgCYAAASAAgJZQpaBgCYAAAAAA==.Malasminna:BAAALgADCgYJBgAAAA==.Malehorelock:BAAALgAECgYJBwABLgAECggJMgAZAFUhAA==.Malicioun:BAAALgADCgEJAQAAAA==.Malkariss:BAABLgAECn9FAAMUAAkJZiE/DQAPAwAUAAkJZiE/DQAPAwAlAAEJ5AjgHAA5AAAAAA==.Mammadruid:BAABLgAECn9HAAMWAAkJNw9VAQD3AAAWAAkJNw9VAQD3AAAGAAYJpwv/cgDcAAAAAA==.Manbearetc:BAAALgAECgMJAwAAAA==.Maralen:BAAALgADCgcJCQAAAA==.Marann:BAAALgAECgEJAQAAAA==.Matadør:BAAALgAECgcJDAAAAA==.Mathwhiz:BAABLgAECn8gAAQiAAYJMRfRPQBOAQAiAAYJMRfRPQBOAQAFAAUJ7gzs6ADTAAAdAAYJ7gDwAgBbAAABLgAECgkJMwAQAEIYAA==.Mauldis:BAABLgAECn9GAAIcAAkJHQ0gMQB6AQAcAAkJHQ0gMQB6AQAAAA==.Mavgard:BAAALgAECgIJAgAAAA==.Mavgards:BAAALgADCgMJAwABLgAECgIJAgAEAAAAAA==.Maxrebo:BAABLgAECn8eAAIaAAgJoBtOEwAXAgAaAAgJoBtOEwAXAgAAAA==.',
Me='Meatwàd:BAAALgAECgYJCgAAAA==.Mekanzi:BAAALgAECgUJDQAAAA==.Meliõdas:BAAALgAECgUJEQAAAA==.Merebels:BAAALgAECgQJBwABLgAECggJDwAEAAAAAA==.Merkodisco:BAAALgAECgIJAgAAAA==.',
Mi='Miaka:BAABLgAECn9BAAICAAkJESEmAQD9AgACAAkJESEmAQD9AgAAAA==.Miakah:BAAALgAECgcJEwAAAA==.Midwest:BAAALgADCgQJBAAAAA==.Minirook:BAAALgADCgEJAQABLgAFFAYJHwASACQcAA==.Misfire:BAABLgAECn9FAAITAAkJnRXmLAApAgATAAkJnRXmLAApAgAAAA==.Mistbusters:BAABLgAECn8WAAIYAAYJdxF7WgAJAQAYAAYJdxF7WgAJAQAAAA==.Mithra:BAAALgAECgEJAQAAAA==.Mithygos:BAABLgAECn8ZAAIKAAgJWwRtVADeAAAKAAgJWwRtVADeAAAAAA==.Mito:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.',
Mo='Moar:BAAALgAECgEJAgAAAA==.Mogad:BAAALgAECgcJBwAAAA==.Moghroth:BAABLgAECn8+AAMNAAkJxg2XJwCTAQANAAkJvg2XJwCTAQAWAAEJQwvGfwAiAAAAAA==.Molykote:BAAALgAECgQJCwAAAA==.Monks:BAAALgAFFAIJAgAAAA==.Morgiana:BAAALgAECgEJAwABLgAECgEJAQAEAAAAAA==.',
My='Myhiknee:BAAALgADCggJDQAAAA==.Myriana:BAAALgAECgQJBwAAAA==.Mysticnugs:BAAALgAFFAEJAQAAAA==.Mystyle:BAAALgADCgcJBwAAAA==.',
['Má']='Mágnus:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâsterdon:BAAALgAECgcJEAAAAA==.',
['Mã']='Mãtador:BAAALgAFFAEJAgAAAA==.',
Na='Nahryn:BAABLgAECn9FAAIGAAkJ8R/bCAAqAwAGAAkJ8R/bCAAqAwAAAA==.Najamei:BAAALgADCgUJBQAAAA==.Najanira:BAAALgADCgYJBgAAAA==.Narya:BAAALgAECgIJAwAAAA==.',
Ne='Neia:BAAALgAECgEJAQAAAA==.Nella:BAAALgAECgYJCQABLgAFFAMJCAAYANMTAA==.Nerbert:BAAALgADCgYJBgABLgAECgkJJwAKAAgVAA==.Neretsym:BAABLgAECn8vAAITAAkJMiDpGQCKAgATAAkJMiDpGQCKAgAAAA==.Nergal:BAAALgAECgEJAQAAAA==.Nevercumdin:BAAALgADCgEJAwAAAA==.',
Ni='Nibbzz:BAACLgAFFH8KAAIHAAUJlwVdJQAiAQAHAAUJlwVdJQAiAQAuAAQKfx0AAgcACQl1FNMhAMABAAcACQl1FNMhAMABAAAA.Nineva:BAABLgAECn8jAAIGAAkJ/QN6aQD4AAAGAAkJ/QN6aQD4AAAAAA==.',
No='Nobas:BAABLgAECn9IAAMNAAkJJg1xKACNAQANAAkJJg1xKACNAQAGAAEJ6wJ05AAhAAAAAA==.',
Nu='Nugs:BAAALgAECgkJBQAAAA==.',
Ok='Okelani:BAAALgAECgEJAQAAAA==.',
Om='Omen:BAAALgAECgQJAQAAAA==.',
On='Onlyfeet:BAAALgAECgMJBgAAAA==.',
Op='Oppgjør:BAABLgAECn8WAAIiAAkJ3RhwEACUAgAiAAkJ3RhwEACUAgAAAA==.',
Or='Oreeree:BAAALgAECgYJBwAAAA==.Orenge:BAAALgAECgQJCAAAAA==.Orkus:BAAALgADCgkJCwAAAA==.Ormr:BAABLgAECn8nAAIKAAkJCBXrHwDZAQAKAAkJCBXrHwDZAQAAAA==.Orpsa:BAAALgADCgYJBgAAAA==.',
Os='Osteo:BAABLgAECn8uAAQCAAgJDwfuFAAmAQACAAgJyAbuFAAmAQAQAAgJXgQ9pgD0AAABAAcJCALAPwC1AAAAAA==.',
Ou='Ouron:BAABLgAECn8mAAMbAAgJwBWFOQDJAQAbAAcJUxaFOQDJAQAcAAYJtQxFZACyAAAAAA==.',
Pa='Papashrimps:BAACLgAFFH8fAAIUAAYJohgxUQA7AQAUAAYJohgxUQA7AQAuAAQKfzkAAhQACQl1IuIQAPUCABQACQl1IuIQAPUCAAAA.',
Pe='Perash:BAAALgAECgEJAQAAAA==.',
Ph='Phrazes:BAAALgAECgQJBAAAAA==.',
Pi='Pikyu:BAAALgADCgEJAQAAAA==.',
Pl='Placeholder:BAABLgAECn81AAIdAAkJWR96BAC3AgAdAAkJWR96BAC3AgAAAA==.Plaguestingr:BAABLgAECn9EAAITAAkJDSQhCQAQAwATAAkJDSQhCQAQAwAAAA==.',
Po='Pontifex:BAABLgAECn8rAAIJAAkJOxlBDQCTAgAJAAkJOxlBDQCTAgAAAA==.Portandmorph:BAABLgAECn8wAAIUAAkJ5hXfOwAqAgAUAAkJ5hXfOwAqAgAAAA==.Potlock:BAABLgAECn8VAAMQAAgJbAvzpQD1AAAQAAUJLwrzpQD1AAACAAMJhA7hKwBsAAAAAA==.',
Pr='Prayinmantís:BAAALgADCgkJCQAAAA==.Proey:BAABLgAECn9DAAMIAAkJAhlREABZAgAIAAkJAhlREABZAgAHAAUJJhMoQQAGAQAAAA==.Prone:BAABLgAECn9VAAMbAAkJpg68AQBEAQAbAAkJpg68AQBEAQAcAAYJewnvWwDQAAAAAA==.',
Ps='Psychokiller:BAAALgADCgYJBgAAAA==.',
Pu='Puf:BAAALgAECgMJBwAAAA==.Puipui:BAAALgADCgEJAgAAAA==.Pumpidan:BAAALgAECgIJBQAAAA==.',
Py='Pyrelyn:BAAALgADCgEJAQAAAA==.',
Qr='Qròw:BAAALgADCgMJAwAAAA==.',
Qu='Quinnifred:BAAALgAECgQJBgAAAA==.',
Ra='Raakotah:BAABLgAECn9JAAINAAkJKSXCAgBFAwANAAkJKSXCAgBFAwAAAA==.Raelo:BAABLgAECn8yAAIhAAkJERaSCQAjAgAhAAkJERaSCQAjAgAAAA==.Raiseurmug:BAABLgAECn8yAAIaAAkJ9BUrFAANAgAaAAkJ9BUrFAANAgAAAA==.Rakash:BAACLgAFFH8TAAISAAUJBhtyWQBAAQASAAUJBhtyWQBAAQAuAAQKfywAAhIACQmTIK0gAL8CABIACQmTIK0gAL8CAAAA.Rarg:BAAALgAFFAIJAgABLgAFFAcJEQARABsaAA==.Rascaldragon:BAAALgAECgQJBQAAAA==.Ravenlark:BAABLgAECn8ZAAIQAAkJigbregBDAQAQAAkJigbregBDAQAAAA==.Ravia:BAABLgAECn8mAAMOAAkJQCNvCQABAwAOAAkJqyJvCQABAwAVAAUJUiE4CQDdAQAAAA==.Razuki:BAAALgAECgYJEwABLgAFFAQJCQAiAOIQAA==.',
Re='Reddale:BAAALgADCgcJDAAAAA==.Redeamer:BAAALgAECgEJAgAAAA==.Resco:BAACLgAFFH8nAAIXAAgJIRdsBAAvAgAXAAgJIRdsBAAvAgAuAAQKfz0AAhcACQkDJV0FAAsDABcACQkDJV0FAAsDAAAA.Rescotwo:BAAALgAECgYJDgAAAA==.',
Rh='Rhozak:BAAALgAECgcJBwABLgAECgkJLgAFAD4ZAA==.',
Ri='Riddle:BAABLgAECn8cAAIbAAkJFgk1bAAXAQAbAAkJFgk1bAAXAQAAAA==.Rimeouo:BAAALgADCgEJAQAAAA==.Rize:BAAALgAECgMJAwABLgAECgkJMwAKABsUAA==.',
Ro='Rocksolid:BAAALgADCgUJBgAAAA==.Ronnie:BAAALgAECgQJBwAAAA==.Rook:BAACLgAFFH8fAAMSAAYJJBxyBABTAQASAAUJJBxyBABTAQADAAEJAAAoZwAAAAAuAAQKfykAAhIACAkTIykXAPACABIACAkTIykXAPACAAAA.Rookmonger:BAAALgAECgUJBQABLgAFFAYJHwASACQcAA==.Rosenrott:BAAALgAFFAIJAwAAAA==.Rosepiercer:BAABLgAECn9AAAITAAkJsSMhCAAbAwATAAkJsSMhCAAbAwAAAA==.Rosies:BAAALgAECgUJBwAAAA==.Rouz:BAABLgAECn8cAAIgAAYJeA+KEAACAQAgAAYJeA+KEAACAQAAAA==.',
Ry='Ryenoh:BAAALgADCgYJBgAAAA==.Rynnoria:BAAALgADCgIJAgAAAA==.Ryoto:BAACLgAFFH8cAAMKAAUJTiRnGwCHAQAKAAQJ5iNnGwCHAQAgAAMJZyKJCwBmAAAuAAQKfxwAAwoACQmHJXQZAAoCAAoACQmHJXQZAAoCACAAAwkXJCMmAPIAAAAA.',
Sa='Sadness:BAAALgADCgYJBwAAAA==.Saelyz:BAAALgADCgQJBAAAAA==.Saetha:BAABLgAECn8dAAIjAAkJQw2TAAAtAQAjAAkJQw2TAAAtAQAAAA==.Samandean:BAABLgAECn9LAAIPAAkJshr0CgB4AgAPAAkJshr0CgB4AgAAAA==.Santhallibar:BAABLgAECn8nAAImAAkJeQPiEQAHAQAmAAkJeQPiEQAHAQAAAA==.Sarasvati:BAABLgAECn8nAAIGAAkJoxrlEQDAAgAGAAkJoxrlEQDAAgAAAA==.Saster:BAABLgAECn8hAAISAAkJgiL7DgD0AgASAAkJgiL7DgD0AgAAAA==.Sathrel:BAAALgADCgIJAgABLgAECgkJBwAEAAAAAA==.',
Sc='Scoops:BAAALgAECgcJBwABLgAFFAUJEQASACscAA==.Scrabs:BAAALgAECgkJDwAAAA==.',
Se='Sellena:BAABLgAECn8uAAIhAAkJMRTmCgAJAgAhAAkJMRTmCgAJAgABLgAECgkJSwAPALIaAA==.Sementha:BAAALgADCgcJDgABLgAECgYJCQAEAAAAAA==.Senpai:BAABLgAECn8UAAIYAAYJyRxQIQCpAQAYAAYJyRxQIQCpAQABLgAFFAgJIAAGAOwZAA==.Sephyra:BAAALgAECgkJEAAAAA==.',
Sh='Shadowmyst:BAAALgADCgQJCgAAAA==.Shaken:BAAALgAECgIJAgAAAA==.Shandow:BAACLgAFFH8ZAAIUAAUJqxyITwA/AQAUAAUJqxyITwA/AQAuAAQKf0wAAhQACQlfJFgGAFADABQACQlfJFgGAFADAAAA.Shango:BAAALgADCgcJCQAAAA==.Shanshunt:BAAALgAECgYJCAABLgAFFAUJGQAUAKscAA==.Shansoracle:BAACLgAFFH8YAAIJAAYJvBhEBwDhAQAJAAYJvBhEBwDhAQAuAAQKfyEAAgkACQlhHy0EAEIDAAkACQlhHy0EAEIDAAEuAAUUBQkZABQAqxwA.Shed:BAACLgAFFH8SAAIcAAUJUx+HFwBgAQAcAAUJUx+HFwBgAQAuAAQKfy0AAhwACAltIZYNAMgCABwACAltIZYNAMgCAAEuAAUUBgkQAA0ALxgA.Sheislegend:BAABLgAECn8cAAIJAAcJpBdiHgDSAQAJAAcJpBdiHgDSAQAAAA==.Shelby:BAABLgAECn81AAMJAAkJERrWDwBrAgAJAAkJERrWDwBrAgAIAAUJcRCiQAANAQAAAA==.Sherminater:BAAALgAECgQJBAAAAA==.Shmoon:BAEALgAECgIJAgABLgAECgUJBgAEAAAAAA==.Shmuckman:BAAALgADCgkJEwAAAA==.Shorttotem:BAAALgADCgUJBQAAAA==.Shoty:BAAALgAECgMJAwABLgAFFAYJHwASACQcAA==.',
Si='Siccinok:BAABLgAECn81AAIUAAgJbBbrAwAEAQAUAAgJbBbrAwAEAQAAAA==.Silicá:BAAALgADCgkJCQABLgAECgEJAQAEAAAAAA==.Sindorian:BAABLgAECn8yAAMZAAgJVSFRCQCJAgAZAAgJ7R9RCQCJAgATAAYJHSIRJwAdAgAAAA==.Sink:BAAALgADCgIJAgAAAA==.Sithlord:BAAALgADCgMJAwAAAA==.Sixseven:BAAALgADCgkJCgABLgAECgkJJgAOAEAjAA==.',
Sk='Skrimphorn:BAAALgAECgEJAQAAAA==.',
Sl='Slimped:BAABLgAECn8XAAMMAAkJqhi4HgC3AQAMAAkJhBG4HgC3AQAaAAgJehNOKgBjAQAAAA==.',
Sm='Smurricane:BAAALgAECgUJCAAAAA==.',
Sn='Snowybato:BAAALgAECgUJEgAAAA==.',
So='Solanwarr:BAABLgAECn89AAQRAAkJTCNDAwAEAwARAAkJKCJDAwAEAwAXAAgJ6B3CFwCOAgAnAAMJnRm8VACDAAABLgAFFAMJAwAEAAAAAA==.Solar:BAAALgAECgQJCAAAAA==.Solarial:BAAALgAFFAEJAQAAAA==.Solastra:BAABLgAECn9DAAIiAAkJQR2/CQDvAgAiAAkJQR2/CQDvAgAAAA==.Sommer:BAAALgAECgcJBwABLgAECgkJTAANAGIZAA==.Soramai:BAAALgADCgcJDwAAAA==.Soth:BAABLgAECn9IAAMSAAkJ1Ro0JAB0AgASAAkJ1Ro0JAB0AgADAAkJQw91GwCBAQAAAA==.',
Sp='Sparticusdru:BAABLgAECn8WAAIjAAkJih3lBwBVAgAjAAkJih3lBwBVAgAAAA==.Spore:BAAALgAECgMJAwAAAA==.',
Sq='Sqaw:BAAALgAECgEJAQAAAA==.',
St='Starkadia:BAAALgAECgYJBgAAAA==.Staryxia:BAACLgAFFH8fAAMLAAYJ/BSMDAA2AQALAAUJ/BSMDAA2AQADAAEJAAA2SQAAAAAuAAQKfy0AAgsACQmhIUsBAPYCAAsACQmhIUsBAPYCAAAA.Steamdruid:BAAALgAECgYJEQAAAA==.Stonecookies:BAABLgAECn8hAAMQAAkJKgn4bABiAQAQAAkJPQj4bABiAQABAAUJ7AYySQCTAAAAAA==.Stonecross:BAAALgAECgYJCgAAAA==.Stonehard:BAAALgAECgMJAwAAAA==.Stoneldo:BAAALgADCgEJAQAAAA==.Stonetotem:BAAALgAECgYJDAAAAA==.Stormbolt:BAABLgAECn9MAAINAAkJYhltEwA5AgANAAkJYhltEwA5AgAAAA==.Stormspirit:BAAALgADCgkJEAAAAA==.Striggen:BAABLgAECn8cAAMFAAYJHhKzxAACAQAFAAUJ9BSzxAACAQAdAAUJDwnkOQB2AAAAAA==.',
Su='Succystrazsa:BAAALgADCgIJAgAAAA==.Sugarsham:BAABLgAECn8fAAQbAAgJlxZDJwAjAgAbAAgJlxZDJwAjAgAcAAYJ9QaXZwCwAAAhAAQJjgNVJgByAAAAAA==.Sulwen:BAACLgAFFH8VAAINAAgJRCLvAAA9AgANAAgJRCLvAAA9AgAuAAQKfyAAAg0ACQmQJvwEAFEDAA0ACQmQJvwEAFEDAAAA.Sumerset:BAAALgAECgMJBgAAAA==.Sunnydee:BAAALgAECggJDwAAAA==.Supaflytnt:BAAALgAECgUJCAAAAA==.Sustia:BAABLgAECn8VAAIoAAgJ1wqLDABIAQAoAAgJ1wqLDABIAQAAAA==.',
Sy='Syrelina:BAAALgAECgQJBAABLgAECgkJJgAOAEAjAA==.',
Ta='Tacopie:BAAALgAECgQJBgAAAA==.Taera:BAACLgAFFH8IAAIYAAMJ0xPJOgC6AAAYAAMJ0xPJOgC6AAAuAAQKfzgAAhgACQmtImYEAGsDABgACQmtImYEAGsDAAAA.Taika:BAAALgADCgkJDwAAAA==.Tailchaser:BAAALgADCgcJBwAAAA==.Talanazar:BAABLgAECn8+AAQKAAkJWyKVBAAeAwAKAAkJWyKVBAAeAwAgAAYJgR2AFAChAQAkAAMJ0A7JKgCVAAAAAA==.Talavenn:BAABLgAECn8zAAIOAAkJtBraGQB5AgAOAAkJtBraGQB5AgAAAA==.Tallish:BAABLgAECn8iAAIOAAkJ6wyBnQDnAAAOAAkJ6wyBnQDnAAAAAA==.Tarage:BAAALgAECgIJAgAAAA==.Taterchip:BAABLgAECn8sAAMXAAgJABt3GgAaAgAXAAgJwxp3GgAaAgARAAIJvRa6PAB/AAAAAA==.Taylia:BAAALgAECgQJBgAAAA==.',
Te='Teaorix:BAAALgADCgQJBAAAAA==.Teds:BAAALgADCgUJBQAAAA==.Temporary:BAAALgADCgYJBgAAAA==.Tempus:BAABLgAECn8VAAIFAAgJ9ATfyAD8AAAFAAgJ9ATfyAD8AAAAAA==.Teradoxx:BAAALgAECgYJDgAAAA==.Teriko:BAABLgAECn8/AAMSAAkJ3h4AGgCrAgASAAkJ3h4AGgCrAgADAAcJKgrVMQDWAAAAAA==.Ternock:BAAALgADCgYJCgAAAA==.Terran:BAAALgAECgEJAwABLgAECgkJRgAOAEMgAA==.Teviro:BAAALgAECgUJBwABLgAECgkJTQAZAA4iAA==.',
Th='Thanks:BAAALgAECgEJAQAAAA==.Thequixote:BAAALgADCgEJAQAAAA==.Therizino:BAAALgADCgQJBAAAAA==.Thrashy:BAAALgAECgQJCAAAAA==.Thrum:BAAALgAECgcJCAAAAA==.',
Ti='Tinkerballa:BAAALgAECgEJAQAAAA==.',
To='Tonkatsu:BAAALgAECgEJAQAAAA==.Toxictotes:BAAALgAECgMJBQAAAA==.',
Ts='Tsargeras:BAAALgAECgQJBAAAAA==.',
Tw='Twiddleado:BAABLgAECn9HAAIUAAkJIBk+LwBcAgAUAAkJIBk+LwBcAgAAAA==.Twinkie:BAAALgAECggJCAABLgAECgkJJgAOAEAjAA==.Twinkle:BAAALgADCgEJAQAAAA==.',
Ty='Ty:BAAALgAFFAEJAQAAAA==.Tylor:BAAALgAECgYJDwAAAA==.',
['Tå']='Tåkete:BAAALgAECgYJCwAAAA==.',
Uk='Ukuindadookr:BAAALgADCgYJBgAAAA==.',
Um='Ume:BAAALgAECgEJAQABLgAECgQJCAAEAAAAAA==.',
Un='Unta:BAAALgAECgYJCQAAAA==.',
Va='Valaera:BAAALgAECgcJDwAAAA==.Valenora:BAABLgAECn8eAAIBAAkJ3h2NAgCOAgABAAkJ3h2NAgCOAgAAAA==.Valise:BAABLgAECn8sAAICAAgJlQR6HwDFAAACAAgJlQR6HwDFAAAAAA==.Varielle:BAAALgAECgYJCQAAAA==.Varuz:BAAALgAECgUJBwABLgAECgYJEAAEAAAAAA==.Varyz:BAAALgAECgUJBQABLgAECgYJEAAEAAAAAA==.Vaticamt:BAAALgAECgUJBQAAAA==.',
Ve='Vecxx:BAAALgADCgUJBQAAAA==.Velanie:BAAALgAECggJDgAAAA==.Velanise:BAAALgADCgMJAwAAAA==.Velcrostrips:BAAALgAECgEJAQAAAA==.Velight:BAAALgADCgEJAQAAAA==.Velinara:BAAALgAECgEJAQAAAA==.Velindroz:BAAALgAECgMJBgAAAA==.Veloras:BAAALgAECgEJAQAAAA==.Verene:BAABLgAECn8oAAIbAAkJEharIQBFAgAbAAkJEharIQBFAgAAAA==.Verinari:BAAALgAECgQJBAAAAA==.',
Vi='Vibes:BAAALgAECgkJBgABLgAECgkJGQANABMhAA==.Violett:BAAALgAFFAUJAgAAAA==.Viperc:BAEALgADCgMJAwABLgAECgYJJQACAEwFAA==.Vipul:BAAALgAECgEJAgABLgAECgYJDgAEAAAAAA==.Viridria:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.Virridian:BAABLgAECn9LAAITAAkJxyCTCwD3AgATAAkJxyCTCwD3AgAAAA==.Virrigosa:BAAALgAECgYJBgAAAA==.Vistia:BAAALgADCgEJAQAAAA==.',
Vl='Vlado:BAAALgAECgEJAgAAAA==.',
Vo='Vodalus:BAAALgADCgUJBQAAAA==.Voideria:BAAALgAECgQJBgAAAA==.Voolock:BAAALgADCgkJDwAAAA==.',
Vy='Vyshana:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.',
Wa='Walbert:BAAALgAFFAcJBAAAAA==.Wallofshame:BAABLgAECn8uAAMiAAkJxh3sDQC1AgAiAAkJxh3sDQC1AgAFAAQJXg4w6QDTAAAAAA==.Walt:BAAALgADCgIJAgAAAA==.Warchef:BAAALgADCgYJCgABLgAECgkJRQAUAGYhAA==.Warriorclaps:BAAALgADCggJDgAAAA==.Wartooth:BAABLgAECn9HAAMBAAkJZRujAwBWAgABAAgJ0h2jAwBWAgAQAAgJnxS8PQDlAQAAAA==.Wassergott:BAAALgADCgIJAgAAAA==.',
We='Webicus:BAABLgAECn8mAAIRAAkJ1BOqEgDBAQARAAkJ1BOqEgDBAQAAAA==.Weezzer:BAAALgADCgQJBAAAAA==.Wendee:BAABLgAECn9DAAMJAAkJNQJrQgDiAAAJAAkJNQJrQgDiAAAIAAgJ+gPZXgCcAAAAAA==.',
Wh='Whitefóx:BAACLgAFFH8UAAIdAAUJLRTPBwD9AAAdAAUJLRTPBwD9AAAuAAQKfx4AAh0ACQmYG+wFAIwCAB0ACQmYG+wFAIwCAAEuAAUUBQkZABQAqxwA.Whitley:BAABLgAECn8vAAMbAAkJEyE7BgBNAwAbAAkJEyE7BgBNAwAhAAcJrxWBEgCOAQAAAA==.',
Wi='Wijing:BAAALgAECgIJAgAAAA==.',
Wo='Wolololo:BAAALgAECgEJAQABLgAECgkJIQASAIIiAA==.Wooden:BAAALgAECgQJBwAAAA==.Worldbreaker:BAAALgADCgEJAQAAAA==.',
['Wü']='Wülfsa:BAAALgAECgUJBQAAAA==.',
Xa='Xampu:BAAALgAECgEJAQAAAA==.Xanthium:BAABLgAECn8sAAIJAAgJmgHZVQCEAAAJAAgJmgHZVQCEAAAAAA==.Xanzib:BAAALgADCgYJBgAAAA==.Xaphy:BAABLgAECn8VAAIJAAcJ2CCaDQCMAgAJAAcJ2CCaDQCMAgAAAA==.Xardots:BAABLgAECn8lAAIBAAgJohUcDAB9AQABAAgJohUcDAB9AQABLgAFFAEJAQAEAAAAAA==.Xardral:BAAALgAECgcJBwABLgAFFAEJAQAEAAAAAA==.',
Xe='Xeelynn:BAAALgAECgMJAwAAAA==.Xeetali:BAAALgADCgYJBgAAAA==.',
Xi='Xiareth:BAABLgAECn9HAAQkAAkJfQxVEwCUAQAkAAkJfQxVEwCUAQAKAAEJPgr9BQAuAAAgAAEJkAbiKAAqAAAAAA==.',
Xt='Xtronger:BAABLgAECn8gAAIGAAgJmRZBMADhAQAGAAgJmRZBMADhAQAAAA==.',
['Xá']='Xároth:BAAALgAFFAEJAQAAAQ==.',
Ya='Yaddi:BAAALgAECgQJBgAAAA==.Yarrow:BAAALgADCgkJEgAAAA==.',
Ye='Yeeyee:BAABLgAECn8ZAAINAAkJEyG3BQD9AgANAAkJEyG3BQD9AgAAAA==.',
Za='Zackor:BAAALgAECggJCwAAAA==.Zalik:BAAALgAECgMJAwAAAA==.',
Ze='Zeebo:BAAALgAECgcJEwAAAA==.Zest:BAABLgAECn8pAAMkAAkJ2BDMDQDzAQAkAAkJ2BDMDQDzAQAKAAIJkAg/fwBgAAAAAA==.',
Zm='Zmaryjane:BAAALgAECgIJBAAAAA==.',
Zo='Zorakfoghorn:BAAALgADCgIJAgAAAA==.Zorakk:BAAALgAECgYJCAAAAA==.Zorithic:BAAALgAECgQJAwAAAA==.Zorrak:BAAALgAECgQJBQAAAA==.',
Zu='Zulls:BAAALgAECgIJAgAAAA==.',
Zy='Zyde:BAAALgAECgYJEAAAAA==.',
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
