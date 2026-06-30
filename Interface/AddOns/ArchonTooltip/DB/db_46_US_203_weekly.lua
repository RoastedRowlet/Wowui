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

local lookup = {'Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Unknown-Unknown','Paladin-Retribution','Druid-Restoration','Priest-Discipline','Priest-Shadow','Priest-Holy','Evoker-Augmentation','DeathKnight-Frost','Monk-Windwalker','Druid-Balance','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Warrior-Protection','DeathKnight-Unholy','Hunter-BeastMastery','Mage-Frost','DemonHunter-Vengeance','Druid-Guardian','Warrior-Fury','Monk-Mistweaver','Hunter-Survival','Monk-Brewmaster','Shaman-Elemental','Shaman-Restoration','Paladin-Protection','Mage-Fire','Rogue-Subtlety','Evoker-Devastation','Shaman-Enhancement','Paladin-Holy','Druid-Feral','Evoker-Preservation','Mage-Arcane','Rogue-Assassination','Warrior-Arms','Rogue-Outlaw',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Absens:BAABLgAECn8+AAMBAAkJwhIeDAB9AQABAAkJhw8eDAB9AQACAAgJ0hBkDgB2AQAAAA==.',
Ad='Adorian:BAAALgAFFAEJAQABLgAFFAQJFAADABMhAA==.Adwillon:BAAALgADCgQJBQABLgAECgYJEwAEAAAAAA==.',
Ae='Aedoril:BAAALgADCgEJAQAAAA==.Aellea:BAAALgADCgkJCQAAAA==.Aelyss:BAAALgADCgQJBAAAAA==.Aerosse:BAAALgAECgMJAwAAAA==.',
Af='Aforceofone:BAABLgAECn8UAAIFAAUJPQp42gDlAAAFAAUJPQp42gDlAAAAAA==.',
Ai='Airdreanna:BAAALgADCgQJBAAAAA==.',
Ak='Akama:BAAALgAECgcJDAABLgAFFAgJIAAGAOwZAA==.',
Al='Alivanllan:BAAALgAECgIJAgAAAA==.Alteisen:BAAALgAECgUJBQAAAA==.',
Am='Ambitious:BAAALgAECgMJCgAAAA==.Amerlinn:BAAALgAECgYJDAAAAA==.',
An='Anamuht:BAABLgAECn8lAAQHAAkJnhK3GgD6AQAHAAgJeBO3GgD6AQAIAAkJQR1+AQC4AQAJAAYJHhDdNAAxAQABLgAECgkJPgAKAFsiAA==.Andryn:BAAALgAECgMJAwAAAA==.Annaday:BAABLgAECn8lAAIDAAkJgQ0PIQBKAQADAAkJgQ0PIQBKAQAAAA==.Antiock:BAACLgAFFH8UAAMDAAQJEyHSEQBsAQADAAQJEyHSEQBsAQALAAQJVBNlDgAmAQAuAAQKfzAAAwMACQn8I58EAOgCAAMACQn8I58EAOgCAAsABwnRHIsKANQBAAAA.Anyaesthesia:BAAALgADCgYJBgAAAA==.Anyamonka:BAABLgAECn8YAAIMAAYJWRr6JgB/AQAMAAYJWRr6JgB/AQAAAA==.',
Ap='Apocalich:BAAALgAECgUJBgAAAA==.Appalachia:BAAALgAECgUJBgAAAA==.',
Aq='Aquenia:BAAALgADCggJDAAAAA==.',
Ar='Aralaith:BAABLgAECn8pAAIIAAgJcCUNCADOAgAIAAgJcCUNCADOAgABLgAFFAkJFgANABwgAA==.Argonaut:BAAALgAECgIJAgAAAA==.Argul:BAAALgAECgIJAgAAAA==.Ariea:BAAALgADCgYJBgAAAA==.Armata:BAAALgAECgMJAwABLgAFFAgJIAAGAOwZAA==.Artoriá:BAAALgAECgEJAQAAAA==.Artto:BAABLgAECn83AAIFAAkJHxNaCQASAQAFAAkJHxNaCQASAQAAAA==.',
As='Asevenhex:BAAALgAECgEJAQAAAA==.Ashbrínger:BAABLgAECn9HAAIFAAkJDCZuAwBjAwAFAAkJDCZuAwBjAwAAAA==.Association:BAAALgAECgMJAwAAAA==.Astrum:BAAALgAECgEJAgAAAA==.Asunã:BAAALgAECgIJAgABLgAECgEJAQAEAAAAAA==.',
At='Atico:BAAALgAECgIJAgAAAA==.',
Au='Aurah:BAAALgAECgIJBAAAAA==.',
Av='Averax:BAABLgAECn9JAAMOAAkJNCHLCgDzAgAOAAkJNCHLCgDzAgAPAAEJvQ2JbgA3AAAAAA==.Avylbrew:BAAALgAECgMJAwAAAA==.Avyrax:BAAALgAECgEJAgABLgAECgkJSQAOADQhAA==.',
Ay='Aybara:BAAALgADCgQJBAAAAA==.Aylakaye:BAAALgADCgMJAwAAAA==.Ayraena:BAABLgAECn8ZAAMNAAgJHQjtPQAYAQANAAgJHQjtPQAYAQAGAAQJEgEuyAA9AAAAAA==.',
Az='Azkariel:BAAALgAECgEJAwAAAA==.Azyrieth:BAAALgADCgEJAQAAAA==.Azzathoth:BAAALgADCgcJDAAAAA==.',
Ba='Babyshoes:BAAALgAECgEJAQAAAA==.Backpack:BAAALgAECggJDAAAAA==.Bakedtofu:BAABLgAECn8UAAMBAAYJ7wc9RwCZAAAQAAYJ7wcO1QCsAAABAAQJGQQ9RwCZAAAAAA==.Bananawaffle:BAAALgAECgMJAwAAAA==.Basement:BAAALgAECgMJAgABLgAFFAYJFQANANQaAA==.Bashine:BAABLgAECn8WAAIRAAYJVxlZGACTAQARAAYJVxlZGACTAQABLgAFFAcJHQASAPMeAA==.Baylohn:BAABLgAECn8lAAITAAkJhRaFMwAOAgATAAkJhRaFMwAOAgAAAA==.',
Be='Bearwrestler:BAABLgAECn8aAAIUAAgJ1BfVYgC5AQAUAAgJ1BfVYgC5AQABLgAFFAQJDwADAJAgAA==.Beefynugs:BAAALgAECgkJAgAAAA==.',
Bi='Bier:BAAALgAECgUJDgAAAA==.Bigrig:BAABLgAECn8dAAITAAkJgAUlFACWAAATAAkJgAUlFACWAAAAAA==.Bitterman:BAABLgAECn8zAAMQAAkJQhiIIABiAgAQAAkJQhiIIABiAgABAAEJww/ZcAA1AAAAAA==.',
Bj='Bjornvalion:BAAALgADCgQJBAAAAA==.',
Bl='Blackmage:BAAALgAECgEJAQAAAA==.Bladed:BAABLgAECn8mAAQVAAgJiBnADgBlAQAOAAgJTxFAVgCEAQAVAAYJChvADgBlAQAPAAQJFxIRQgCuAAAAAA==.Blinkerfluid:BAAALgADCgIJAgAAAA==.Blinx:BAAALgADCgQJBAAAAA==.Bloodymess:BAABLgAECn8aAAISAAgJQAqrhABaAQASAAgJQAqrhABaAQAAAA==.',
Bo='Bohikeog:BAAALgAECgIJAgAAAA==.Boogies:BAAALgADCgQJBwAAAA==.Bovinedivine:BAAALgAECgYJBgABLgAFFAEJAQAEAAAAAA==.Bowyardee:BAAALgAECgEJAQAAAA==.',
Bu='Buffie:BAABLgAECn8ZAAIFAAgJGhoeWADaAQAFAAgJGhoeWADaAQAAAA==.Bullwyf:BAAALgADCgMJAwAAAA==.Bumblbeetuna:BAAALgAECgMJAwAAAA==.',
['Bá']='Bád:BAAALgADCggJDgABLgAECgYJIgAWAPIRAA==.',
Ca='Calduu:BAAALgAECgQJCAAAAA==.Caledia:BAAALgAECgYJEQAAAA==.Callana:BAAALgADCgMJBQAAAA==.Camedra:BAABLgAECn9KAAIGAAkJnCQsAgCxAwAGAAkJnCQsAgCxAwAAAA==.Carinancey:BAAALgAECgQJBQAAAA==.Carperoni:BAAALgADCgcJBwAAAA==.Casseous:BAAALgADCgUJBwAAAA==.Castrada:BAAALgAECgUJBQABLgAECgkJWAAFAEIaAA==.Catamynyia:BAABLgAECn8nAAITAAkJQg9aSQDFAQATAAkJQg9aSQDFAQAAAA==.Caylaetal:BAAALgAECgEJAQAAAA==.',
Cc='Cchaos:BAAALgAECgIJBgAAAA==.',
Ce='Celaborn:BAABLgAECn8hAAIXAAkJjx5ZAgCBAQAXAAkJjx5ZAgCBAQAAAA==.Celice:BAAALgAECgcJBwABLgAFFAMJCAAYANMTAA==.Cerwan:BAAALgADCgMJAwAAAA==.',
Ch='Chazaraz:BAABLgAECn8+AAMZAAkJVxElEwAOAgAZAAkJABElEwAOAgATAAgJEgibiwAoAQAAAA==.Chazsquatch:BAAALgAECgUJCgABLgAECgkJPgAZAFcRAA==.Chevy:BAAALgAECgEJAwAAAA==.Chifreak:BAAALgAFFAIJAgABLgAFFAQJBQAOAEsWAA==.Chillmourne:BAAALgAECgcJEwABLgAECgEJAQAEAAAAAA==.Chimaira:BAAALgADCgIJAgAAAA==.Chucknoris:BAAALgAECgUJEgAAAA==.Chugbuggins:BAAALgAECgYJEwAAAA==.',
Ci='Cindria:BAABLgAECn8lAAIUAAgJuBA1eQCGAQAUAAgJuBA1eQCGAQAAAA==.',
Cl='Clare:BAAALgAECgEJAgABLgAECgEJAQAEAAAAAA==.Clerks:BAAALgAECgIJAgAAAA==.Cliffgate:BAAALgADCgMJAwAAAA==.',
Co='Colaitis:BAAALgADCgIJAgAAAA==.Conduction:BAAALgAECgUJCAAAAA==.Corenthia:BAAALgAECgYJEwAAAA==.',
Cp='Cptbonez:BAAALgAECgYJEgABLgAECgkJMgAaAPQVAA==.',
Cr='Crankadin:BAAALgAECgEJAgABLgAECgIJBAAEAAAAAA==.Crankchi:BAAALgAECgIJAwABLgAECgIJBAAEAAAAAA==.Crazz:BAAALgADCgEJAQAAAA==.Crewz:BAAALgADCgQJBAAAAA==.Crooky:BAAALgADCgcJBwABLgAFFAYJHwASACQcAA==.Crucifiiks:BAAALgAFFAIJAgAAAA==.Cruciö:BAAALgAECgEJAQAAAA==.Crànk:BAAALgAECgIJBAAAAA==.Cránk:BAAALgAECgEJAQABLgAECgIJBAAEAAAAAA==.Crãnk:BAAALgAECgIJAwABLgAECgIJBAAEAAAAAA==.',
Cu='Cullyeskie:BAAALgAECgMJAwAAAA==.Curveball:BAABLgAECn8dAAMbAAkJww80AgCEAQAbAAkJww80AgCEAQAcAAgJwwkiWgBQAQABLgAECgkJMwAQAEIYAA==.',
Cy='Cyniar:BAABLgAECn8bAAINAAgJcQt8AwAiAQANAAgJcQt8AwAiAQAAAA==.',
Da='Dalearnhardt:BAAALgADCgcJDgABLgAECgcJEgAEAAAAAA==.Damerlin:BAABLgAECn8bAAMFAAgJ7hGteQB7AQAFAAgJkA+teQB7AQAdAAQJcwolPgBkAAAAAA==.Damzel:BAAALgAECgMJAwAAAA==.Darkhuntress:BAAALgAECgcJBwAAAA==.Darkstär:BAABLgAECn9KAAIDAAkJDh/dBgCwAgADAAkJDh/dBgCwAgAAAA==.Darkun:BAAALgAECgUJCgABLgAECgkJNAAKAJkUAA==.Darkwood:BAAALgADCgEJAgAAAA==.Dauc:BAAALgADCgEJAQAAAA==.Davesdemise:BAAALgAECgUJBQAAAA==.',
De='Deacon:BAABLgAECn9IAAQaAAkJxgi7AgDkAAAaAAkJhwe7AgDkAAAMAAUJmgpaXQChAAAYAAUJfQRdkQB2AAAAAA==.Deadmantooth:BAAALgADCgYJBgABLgAECgkJTQABAF4cAA==.Deardren:BAAALgAECgUJBQAAAA==.Deathcorps:BAAALgAECgMJAwAAAA==.Deathgripbtw:BAAALgAECgMJAwAAAA==.Deathknights:BAAALgAFFAEJAQAAAA==.Deathtrol:BAAALgAECggJDwAAAA==.Deeanne:BAAALgAECgQJBwAAAA==.Deepdeuce:BAAALgAECgYJCgAAAA==.Deepfriar:BAABLgAECn9RAAMJAAkJLCWaAQChAwAJAAkJLCWaAQChAwAIAAcJMRSXLAByAQAAAA==.Deidra:BAAALgADCgMJAwAAAA==.Demonhunts:BAABLgAFFH8KAAIOAAUJgQkxWQDkAAAOAAUJgQkxWQDkAAAAAA==.Demonmore:BAABLgAECn8jAAMPAAgJxAsUKwAnAQAPAAgJ2AoUKwAnAQAVAAUJWQoJIQCVAAAAAA==.Derailed:BAAALgAECgQJBwAAAA==.Dethwing:BAAALgAECgIJAgAAAA==.Devilfrost:BAAALgAECgEJAQABLgAECgMJBgAEAAAAAA==.Dewshine:BAAALgAECgcJDQAAAA==.',
Dh='Dhampir:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Dhgeek:BAAALgAECgUJCgAAAA==.',
Di='Diablognomis:BAABLgAECn8eAAIMAAYJyxq5AQBnAQAMAAYJyxq5AQBnAQAAAA==.Diarmac:BAAALgAECgcJDgABLgAECgkJXQAcAPcPAA==.Dingô:BAAALgAECgQJBgAAAA==.Dirtman:BAACLgAFFH8FAAIbAAQJDw5xKQDvAAAbAAQJDw5xKQDvAAAuAAQKfy0AAhsACQkHHdsSAFgCABsACQkHHdsSAFgCAAAA.',
Dk='Dkrise:BAAALgAECgMJAwABLgAECgkJNAAKAJkUAA==.',
Dn='Dneoh:BAAALgAECgkJCAABLgAFFAMJCgANAOciAA==.',
Do='Dolphina:BAAALgAECgIJAgAAAA==.Donald:BAAALgADCgQJBAAAAA==.Donny:BAABLgAECn88AAMFAAgJxB57AwDGAQAFAAgJoR57AwDGAQAdAAMJIxyIAwDDAAAAAA==.Doodyshamala:BAAALgAECgUJEAAAAA==.Dooky:BAAALgAECgYJBwABLgAFFAYJHwASACQcAA==.Doozey:BAACLgAFFH8QAAIOAAQJJxYWRAAbAQAOAAQJJxYWRAAbAQAuAAQKfykAAw4ACQniHu0bAGwCAA4ACQlaHu0bAGwCABUAAQnNE9wxADwAAAAA.Dorigis:BAAALgAECgMJAwABLgAECgkJKQARAE8jAA==.Dotdotdotded:BAABLgAECn8WAAIQAAgJuAWjlgAPAQAQAAgJuAWjlgAPAQAAAA==.',
Dr='Drewdog:BAABLgAECn9MAAMZAAkJIRiqAAAoAgAZAAkJyBWqAAAoAgATAAcJJBfNCgAOAQAAAA==.Droid:BAAALgAECgEJAgAAAA==.Drunkgerardo:BAAALgAECgQJBQAAAA==.Drunkzen:BAAALgAECgUJCAAAAA==.Druyesil:BAAALgAECgEJAgAAAA==.',
Du='Dubes:BAABLgAECn9FAAIUAAkJABq5JwB7AgAUAAkJABq5JwB7AgAAAA==.Dunbartian:BAABLgAECn8XAAIRAAcJuxb4AQA4AQARAAcJuxb4AQA4AQAAAA==.Duskfang:BAAALgAECgQJBQAAAA==.',
['Dá']='Dárkthorn:BAAALgAECgIJBAAAAA==.',
['Dö']='Dökkálfar:BAAALgAECgEJAQAAAA==.',
Ea='Easybreezin:BAAALgAECgUJDAAAAA==.',
Ei='Eirote:BAABLgAECn9XAAIeAAkJhx1NAQCpAgAeAAkJhx1NAQCpAgAAAA==.',
El='Elarris:BAAALgAECgcJDQAAAA==.Eldari:BAABLgAECn8YAAINAAgJ2htdGwDwAQANAAgJ2htdGwDwAQAAAA==.Elem:BAACLgAFFH8PAAIcAAYJUwjuKABCAQAcAAYJUwjuKABCAQAuAAQKfyMAAhwACAmcIFMYAFMCABwACAmcIFMYAFMCAAAA.Ellyssanna:BAAALgAECgQJCAAAAA==.Elm:BAAALgAECgYJEAAAAA==.Elvina:BAAALgAECgEJAQAAAA==.Elyssaena:BAAALgAECgYJEgAAAA==.',
Em='Emiliachan:BAAALgAECgcJCwAAAA==.',
En='Enzojr:BAACLgAFFH8QAAIfAAQJqxtdFgBZAQAfAAQJqxtdFgBZAQAuAAQKf0QAAh8ACQlZJGQCADYDAB8ACQlZJGQCADYDAAAA.',
Ep='Ephixa:BAABLgAFFH8FAAISAAIJJAZcBgFYAAASAAIJJAZcBgFYAAAAAA==.',
Er='Eridanos:BAAALgADCgYJBgAAAA==.Erisiel:BAAALgAECgEJAQAAAA==.Eruelle:BAACLgAFFH8NAAIOAAQJICTUIwCgAQAOAAQJICTUIwCgAQAuAAQKfyEAAg4ACQneJbYBAHADAA4ACQneJbYBAHADAAEuAAUUCQkWAA0AHCAA.Erzå:BAAALgAECgEJAgABLgAECgEJAQAEAAAAAA==.',
Ev='Evoke:BAABLgAECn8fAAMKAAgJgyF3CgDOAgAKAAgJdB93CgDOAgAgAAYJZyBaDQAEAgAAAA==.',
Ey='Eye:BAACLgAFFH8KAAIhAAQJBiGrCgAUAQAhAAQJBiGrCgAUAQAuAAQKfyAAAyEACQnRIHIHAFYCACEACQnRIHIHAFYCABsAAQmZDN2PACgAAAAA.',
['Eí']='Eís:BAAALgADCgYJCwAAAA==.',
Fa='Faeira:BAAALgAECgcJCQAAAA==.Faloril:BAAALgAECgUJDAAAAA==.Falsara:BAAALgAECgQJBAAAAA==.Faranth:BAABLgAECn9GAAIKAAkJcyGKBQAHAwAKAAkJcyGKBQAHAwAAAA==.Faronyr:BAAALgAECgEJAQAAAA==.',
Fe='Felboi:BAAALgAECgUJDgAAAA==.Felknight:BAAALgAECgUJCQAAAA==.Felorc:BAAALgAECgQJBwAAAA==.Felynne:BAABLgAECn8ZAAIBAAkJbAbxAgDFAAABAAkJbAbxAgDFAAAAAA==.Fenrík:BAAALgADCgIJAgAAAA==.Feo:BAABLgAECn8eAAIOAAkJexkaJwAvAgAOAAkJexkaJwAvAgAAAA==.Ferum:BAABLgAECn9aAAMGAAkJQCWEAQDDAwAGAAkJQCWEAQDDAwANAAkJyRurCwCaAgAAAA==.',
Fi='Fionnan:BAABLgAECn9HAAIWAAkJPg90GgB6AQAWAAkJPg90GgB6AQABLgAECgkJXQAcAPcPAA==.Firepriest:BAAALgAECgIJAgAAAA==.',
Fo='Forest:BAACLgAFFH8QAAQNAAUJjhQ0IQAWAQANAAUJjhQ0IQAWAQAGAAIJZwbdYQBXAAAWAAIJtgjNMQBXAAAuAAQKfy4AAw0ACQl6HSkNAMYCAA0ACQl6HSkNAMYCAAYAAwn3GwZtAO0AAAAA.',
Fr='Fraoch:BAAALgAECgcJDAABLgAECgkJSAANACYNAA==.Fretless:BAAALgADCgYJCgAAAA==.Frixley:BAAALgAFFAIJAgAAAA==.Friérén:BAAALgAECgEJBAABLgAECgEJAQAEAAAAAA==.Frostedrayne:BAAALgADCgUJBQAAAA==.Frostthrower:BAAALgAECgEJAgAAAA==.Fryeguy:BAAALgAECggJEwAAAA==.',
Fu='Funkysoup:BAAALgADCgYJBgAAAA==.',
Fy='Fyodor:BAAALgAECgIJBQAAAA==.',
['Fè']='Fèlt:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Fèresha:BAAALgAECgkJEgAAAA==.',
['Fò']='Fòrced:BAAALgAFFAIJAwAAAA==.',
Ga='Gallium:BAABLgAECn8kAAIiAAkJIBi4FABoAgAiAAkJIBi4FABoAgAAAA==.Gazerbeam:BAABLgAECn8VAAIOAAgJAw+abwBEAQAOAAgJAw+abwBEAQAAAA==.',
Ge='Geekshamlama:BAAALgAECgEJAQAAAA==.Geelock:BAAALgADCggJFgAAAA==.Gehena:BAAALgAFFAIJAgABLgAFFAIJBQATACQfAQ==.Gemsareyum:BAAALgAECgYJDgABLgAFFAcJQgATAKIgAA==.Geode:BAAALgAECgcJDQAAAA==.Gesht:BAABLgAECn8gAAIFAAkJDRHvcwCGAQAFAAkJDRHvcwCGAQAAAA==.Getemwet:BAAALgAECgEJAQAAAA==.',
Gh='Ghostfreak:BAAALgAECgUJBgAAAA==.',
Gi='Gidgetz:BAAALgADCgMJAwAAAA==.',
Gl='Glamourkills:BAAALgADCgcJDQAAAA==.Gleipnir:BAAALgAECgMJBQAAAA==.',
Go='Gojirra:BAAALgAECgYJDwAAAA==.Goldenbell:BAAALgAECgUJBQAAAA==.Goof:BAABLgAECn82AAIiAAkJ9Q6bMgCLAQAiAAkJ9Q6bMgCLAQAAAA==.Goontas:BAAALgAECgMJBAAAAA==.',
Gr='Grimsheèper:BAAALgAECgMJBAAAAA==.Grish:BAABLgAECn8ZAAIhAAYJHgaPJQDKAAAhAAYJHgaPJQDKAAAAAA==.Griz:BAAALgAECgQJCAAAAA==.Grollnar:BAAALgAECgEJAQABLgAECgkJDwAEAAAAAA==.Grossevache:BAAALgAECgYJEAAAAA==.Gròws:BAAALgAECgkJBwAAAA==.',
Ha='Haddor:BAABLgAECn8sAAMdAAkJXBo7CABVAgAdAAkJXBo7CABVAgAFAAEJWwRjvQElAAAAAA==.Haelexi:BAAALgAECgUJDwAAAA==.Halujoxar:BAAALgADCgcJDgABLgAFFAEJAQAEAAAAAA==.Hamonkulous:BAAALgADCgcJCAAAAA==.Hankerin:BAAALgADCgcJCgAAAA==.Harandar:BAAALgAECgEJAQAAAA==.Harleÿquinn:BAAALgAECgIJAgAAAA==.Harpomage:BAAALgAECgEJAgAAAA==.Hatcher:BAAALgAECgEJAQAAAA==.Haunter:BAABLgAECn8jAAQSAAkJiiC6dAB6AQASAAYJLR+6dAB6AQADAAUJlR4pIgBBAQALAAMJUBvgJACpAAAAAA==.Hayleigh:BAACLgAFFH8gAAIGAAgJ7BlRBgCkAgAGAAgJ7BlRBgCkAgAuAAQKfzEAAgYACQmEIgMGAFgDAAYACQmEIgMGAFgDAAAA.',
He='Heimdallr:BAAALgAECgEJAQAAAA==.Heisenborg:BAAALgAECgUJBQAAAA==.Hellbreezy:BAAALgAECgkJEAAAAA==.Helldin:BAABLgAECn8nAAIFAAYJ3hXZogAzAQAFAAYJ3hXZogAzAQAAAA==.Hellenfeller:BAABLgAECn8rAAIPAAkJBRQJBADiAAAPAAkJBRQJBADiAAAAAA==.',
Hi='Hilitepriest:BAABLgAECn8bAAMHAAgJ0RlvFgAlAgAHAAgJQBlvFgAlAgAJAAIJ1BZvaACLAAAAAA==.Himothyjr:BAAALgAECgUJBQAAAA==.Hittomi:BAAALgAECgYJBgAAAA==.',
Ho='Holific:BAABLgAECn9YAAIFAAkJQhq1AgD7AQAFAAkJQhq1AgD7AQAAAA==.Honeychild:BAAALgAECgYJCgAAAA==.Hotrodranger:BAAALgAECgcJEgAAAA==.Hottub:BAAALgAECgUJBQAAAA==.',
Hu='Huckleberry:BAAALgAECgUJBQAAAA==.Hut:BAABLgAFFH8VAAINAAYJ1BqZEwCBAQANAAYJ1BqZEwCBAQAAAA==.',
Hv='Hvac:BAABLgAECn89AAIUAAkJIw4yYwC4AQAUAAkJIw4yYwC4AQAAAA==.',
Hy='Hypearione:BAAALgADCgIJAgAAAA==.',
Ia='Ialan:BAAALgADCgQJBgAAAA==.',
Ic='Iceovo:BAAALgADCgEJAQAAAA==.Ichabod:BAAALgAECgEJAQABLgAECgkJJwAKAAgVAA==.Icycritties:BAABLgAECn8YAAIUAAYJehAlvQBoAQAUAAYJehAlvQBoAQAAAA==.',
Id='Idovoodew:BAAALgADCgUJCAAAAA==.',
Ih='Iheals:BAAALgAECgMJCQAAAA==.',
Il='Illidon:BAAALgAECgEJAQAAAA==.',
Im='Imjustadruid:BAAALgADCggJCwAAAA==.Immortal:BAABLgAECn8mAAMSAAkJBxn0JwBiAgASAAkJBxn0JwBiAgADAAcJtAy5KAAPAQAAAA==.Implants:BAAALgADCggJCQAAAA==.',
In='Incarnate:BAAALgAECgcJEAABLgAFFAUJEQASACscAA==.Incarnated:BAACLgAFFH8RAAMSAAUJKxxkdQAXAQASAAQJYiFkdQAXAQALAAMJoRIDFQDjAAAuAAQKfzQAAxIACQnII3cOAPgCABIACQl3I3cOAPgCAAsAAwmBIlIVAC8BAAAA.Inflammation:BAAALgADCgcJDwABLgAECgUJCAAEAAAAAA==.',
Ir='Irocc:BAAALgAECgUJEgAAAA==.Irís:BAAALgAECgEJAgABLgAECgEJAQAEAAAAAA==.',
Is='Ishankyou:BAAALgAECgEJAQAAAA==.Ispithotfire:BAAALgAECgMJBQAAAA==.Istara:BAAALgADCgcJDQABLgAFFAgJHwAUANIfAA==.',
Iu='Iu:BAAALgADCgEJAgAAAA==.',
Ja='Jackdowe:BAAALgAECgQJBAAAAA==.Jackfash:BAAALgADCgcJDQAAAA==.Jadecross:BAABLgAECn8WAAIYAAcJSxYtMwCqAQAYAAcJSxYtMwCqAQAAAA==.Jalenhunter:BAAALgADCgUJCAAAAA==.',
Je='Jedith:BAAALgAECgcJCQAAAA==.Jerambae:BAABLgAECn8YAAIeAAYJyBWYBACTAQAeAAYJyBWYBACTAQAAAA==.Jerryatric:BAABLgAECn8cAAIFAAkJeBAnbgCSAQAFAAkJeBAnbgCSAQAAAA==.',
Jk='Jkmno:BAAALgADCgcJBwAAAA==.',
Jo='Joelah:BAAALgAECgcJDwAAAA==.Joshua:BAAALgAECgYJDAAAAA==.',
Ju='Justincasê:BAAALgADCggJFQAAAA==.',
['Jà']='Jàvan:BAAALgAFFAMJAwAAAA==.',
['Jâ']='Jây:BAAALgADCgQJBAAAAA==.',
Ka='Kalarian:BAAALgAECgMJAwAAAA==.Kalfeen:BAABLgAECn8hAAMWAAgJlSFOBgCcAgAWAAgJlSFOBgCcAgAjAAEJ+wbDXgAjAAAAAA==.Kallikan:BAABLgAECn89AAIWAAkJyRpoCgA/AgAWAAkJyRpoCgA/AgAAAA==.Kamidk:BAABLgAFFH8HAAISAAQJ1g1aygCZAAASAAQJ1g1aygCZAAABLgAFFAUJEwAOACAeAA==.Kanmojo:BAAALgADCgQJBQAAAA==.Kashume:BAABLgAECn8bAAIhAAkJngINHwABAQAhAAkJngINHwABAQAAAA==.Kasteen:BAABLgAECn8VAAIbAAYJSAVaDABaAAAbAAYJSAVaDABaAAAAAA==.Kazon:BAAALgADCgcJCgABLgAFFAQJFAADABMhAA==.Kaøs:BAAALgAECgEJAQAAAA==.',
Kd='Kdoggparker:BAAALgAECgIJAwAAAA==.',
Ke='Kementari:BAAALgAECgYJCgAAAA==.Kenner:BAAALgAECgEJAQAAAA==.Kenzaki:BAACLgAFFH8WAAIFAAUJmQrTWQD8AAAFAAUJmQrTWQD8AAAuAAQKfzgAAgUACQl7G9czADECAAUACQl7G9czADECAAAA.Kesha:BAAALgAECgYJBgABLgAECgkJNQAJABEaAA==.',
Kh='Khaosreborn:BAAALgAECgUJEAAAAA==.Khaotic:BAAALgADCgMJAwABLgADCgQJBAAEAAAAAA==.',
Ki='Kickin:BAAALgAECgEJAQAAAA==.Kiiren:BAAALgAECgEJAQABLgAECggJIQAWAJUhAA==.Kilaaz:BAABLgAECn8VAAIFAAUJzCTrfAB0AQAFAAUJzCTrfAB0AQAAAA==.Kilaz:BAAALgADCgUJBQAAAA==.',
Kn='Knuts:BAACLgAFFH8HAAIaAAQJBRZBJAAZAQAaAAQJBRZBJAAZAQAuAAQKfxYAAhoACQlUGOAeAK8BABoACQlUGOAeAK8BAAAA.',
Ko='Korius:BAAALgAECgUJBQAAAA==.Ková:BAABLgAECn8rAAITAAgJmBrcNAAJAgATAAgJmBrcNAAJAgAAAA==.',
Kr='Krutesiq:BAAALgADCgkJCQAAAA==.',
Ku='Kuani:BAAALgAECgYJCQABLgAFFAMJCAAYANMTAA==.Kullman:BAAALgADCgYJCgAAAA==.Kungfupapa:BAAALgAECgQJCgAAAA==.Kungfurry:BAAALgAECgUJCAAAAA==.Kurobozu:BAAALgAECgUJCQABLgAECgkJPgAKAFsiAA==.Kutherrek:BAAALgAECgEJAQAAAA==.Kuubar:BAABLgAECn8mAAILAAkJ/RVECQDxAQALAAkJ/RVECQDxAQAAAA==.',
Ky='Kyian:BAAALgAECgMJAwAAAA==.',
La='Lacus:BAAALgAECgYJDgAAAA==.Ladaeze:BAAALgADCgIJAgAAAA==.Ladiesnutz:BAACLgAFFH8FAAIKAAUJ4RY2KgAfAQAKAAUJ4RY2KgAfAQAuAAQKfxoABCQACQm6HhMXAF4BACQABAnhHxMXAF4BAAoABwl6FJQxADsBACAABQlOGysNADsBAAAA.Lalatiina:BAAALgAECgIJAgABLgAFFAQJBQAOAEsWAA==.Lathray:BAAALgAECgMJAwAAAA==.Law:BAAALgAECgEJAwABLgAFFAgJIAAGAOwZAA==.Laz:BAAALgADCgMJAwAAAA==.Lazerous:BAAALgADCgYJBgAAAA==.',
Le='Leafá:BAAALgAECgEJAgABLgAECgEJAQAEAAAAAA==.Lealoo:BAABLgAECn81AAIFAAkJwR0gBQB6AQAFAAkJwR0gBQB6AQABLgAECgkJSwAPALIaAA==.Leghorn:BAAALgADCgIJAgABLgAECggJIQAWAJUhAA==.Legolard:BAABLgAECn8pAAMRAAkJTyM1AwAGAwARAAkJTyM1AwAGAwAXAAQJgSGQBAAMAQAAAA==.Lever:BAAALgADCggJCQAAAA==.',
Li='Liath:BAABLgAECn8YAAIJAAYJlBplIwCoAQAJAAYJlBplIwCoAQAAAA==.Liathano:BAAALgAECgQJBwAAAA==.Lichtenberg:BAAALgAECgMJBAABLgAECgkJPgAKAFsiAA==.Lightsky:BAAALgADCgIJAQAAAA==.Lildèbbíe:BAABLgAECn8oAAIUAAgJMg3cfAB+AQAUAAgJMg3cfAB+AQAAAA==.Lilspoon:BAAALgADCgYJAwAAAA==.Liltrapstarx:BAAALgAECgQJCAAAAA==.Linddori:BAABLgAECn8uAAIFAAkJPhm9MAA+AgAFAAkJPhm9MAA+AgAAAA==.Lindmajik:BAAALgAECgQJBgAAAA==.Liori:BAABLgAECn8oAAIFAAgJ2goCCwD2AAAFAAgJ2goCCwD2AAAAAA==.Lirillïa:BAAALgADCggJDQABLgAECgkJLgAFAD4ZAA==.',
Ll='Llyana:BAAALgAECgkJEAABLgAECgkJRgAKAHMhAA==.',
Lo='Lodestone:BAAALgADCgMJAwAAAA==.Loena:BAABLgAECn8iAAIFAAkJXiPHCwAHAwAFAAkJXiPHCwAHAwAAAA==.Lokk:BAAALgAECgYJCQABLgAECgYJEAAEAAAAAA==.Longnuts:BAAALgAECgEJAgAAAA==.Lovelydread:BAAALgAECgUJBgAAAA==.',
Lu='Lunabug:BAACLgAFFH8HAAIMAAMJowsDKQCtAAAMAAMJowsDKQCtAAAuAAQKfygAAgwACAl8HSUcAM4BAAwACAl8HSUcAM4BAAAA.Lupinos:BAAALgADCgYJCAAAAA==.Luquier:BAAALgAECgcJBwABLgAECgkJTQAZAA4iAA==.',
Ly='Lyada:BAAALgAECggJDQAAAA==.Lyadra:BAABLgAECn89AAIJAAkJhR+TBQAhAwAJAAkJhR+TBQAhAwAAAA==.Lyandre:BAACLgAFFH8NAAMJAAUJhAoXFgAPAQAJAAUJhAoXFgAPAQAHAAQJSQGZNwCrAAAuAAQKfx4AAwkACAlGE4MWACgCAAkACAlGE4MWACgCAAcAAQnAEHJ5ADIAAAAA.Lydra:BAAALgAECgUJBQAAAA==.Lynna:BAAALgADCgQJBAAAAA==.Lyntoo:BAAALgAECgIJAQAAAA==.Lyntu:BAAALgAECgEJAQAAAA==.Lyrissa:BAAALgAECgcJDgAAAA==.',
['Lú']='Lúffy:BAAALgAECgcJBwABLgAFFAQJBQAOAEsWAA==.',
Ma='Maania:BAAALgAECgcJBwAAAA==.Madan:BAABLgAECn8rAAISAAkJfQo3CwDbAAASAAkJfQo3CwDbAAAAAA==.Malasminna:BAAALgADCgYJBgAAAA==.Malehorelock:BAAALgAECgYJBwABLgAECggJMwAZAFUhAA==.Malicioun:BAAALgADCgEJAQAAAA==.Malkariss:BAABLgAECn9LAAMUAAkJZiE7DQAPAwAUAAkJZiE7DQAPAwAlAAEJ5AjgHAA5AAAAAA==.Mammadruid:BAABLgAECn9IAAMWAAkJhg8AAwAXAQAWAAkJhg8AAwAXAQAGAAYJpwv+cgDcAAAAAA==.Manbearetc:BAAALgAECgMJAwAAAA==.Maralen:BAAALgADCgcJCQAAAA==.Marann:BAAALgAECgEJAQAAAA==.Matadør:BAAALgAECgcJDAAAAA==.Mathwhiz:BAABLgAECn8gAAQiAAYJMRfTPQBOAQAiAAYJMRfTPQBOAQAFAAUJ7gzv6ADTAAAdAAYJ7gD5BgBbAAABLgAECgkJMwAQAEIYAA==.Mauldis:BAABLgAECn9MAAIbAAkJtg7ABAD0AAAbAAkJtg7ABAD0AAAAAA==.Mavgard:BAAALgAECgIJAgAAAA==.Mavgards:BAAALgADCgMJAwABLgAECgIJAgAEAAAAAA==.Maxrebo:BAABLgAECn8eAAIaAAgJoBtOEwAXAgAaAAgJoBtOEwAXAgAAAA==.',
Me='Meatwàd:BAAALgAECgcJDAAAAA==.Mekanzi:BAAALgAECgUJDQAAAA==.Meliõdas:BAAALgAECgUJEQAAAA==.Merebels:BAAALgAECgQJBwABLgAECggJDwAEAAAAAA==.Merkodisco:BAAALgAECgIJAgAAAA==.',
Mi='Miaka:BAABLgAECn9CAAICAAkJESEmAQD9AgACAAkJESEmAQD9AgAAAA==.Miakah:BAAALgAECgcJEwAAAA==.Midwest:BAAALgADCgQJBAAAAA==.Minigoonta:BAAALgAECgMJAwAAAA==.Minirook:BAAALgADCgEJAQABLgAFFAYJHwASACQcAA==.Misfire:BAABLgAECn9NAAITAAkJEha3AwDMAQATAAkJEha3AwDMAQAAAA==.Mistbusters:BAABLgAECn8WAAIYAAYJdxF+WgAJAQAYAAYJdxF+WgAJAQAAAA==.Mithra:BAAALgAECgEJAQAAAA==.Mithygos:BAABLgAECn8bAAIKAAgJdAVtVADeAAAKAAgJdAVtVADeAAAAAA==.Mito:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.',
Mo='Moar:BAAALgAECgEJAgAAAA==.Mogad:BAAALgAECgcJBwAAAA==.Moghroth:BAABLgAECn8+AAMNAAkJxg2aJwCTAQANAAkJvg2aJwCTAQAWAAEJQwvIfwAiAAAAAA==.Molykote:BAAALgAECgQJCwAAAA==.Monks:BAAALgAFFAIJAgAAAA==.Monsterbabe:BAAALgADCgUJBQAAAA==.Moreleath:BAAALgADCgEJAQAAAA==.Morgiana:BAAALgAECgEJAwABLgAECgEJAQAEAAAAAA==.',
My='Myhiknee:BAAALgAECgEJAQAAAA==.Myriana:BAAALgAECgQJBwAAAA==.Mysticnugs:BAAALgAFFAEJAgAAAA==.Mystyle:BAAALgADCgcJBwAAAA==.',
['Má']='Mágnus:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâsterdon:BAAALgAECgcJEAAAAA==.',
['Mã']='Mãtador:BAAALgAFFAEJAgAAAA==.',
Na='Nahryn:BAABLgAECn9LAAIGAAkJVCDbCAAqAwAGAAkJVCDbCAAqAwAAAA==.Najamei:BAAALgADCgUJBQAAAA==.Najanira:BAAALgADCgYJBgAAAA==.Narya:BAAALgAECgIJAwAAAA==.Nathazar:BAAALgAECgkJCQAAAA==.',
Ne='Neia:BAAALgAECgEJAQAAAA==.Nella:BAAALgAECgYJCQABLgAFFAMJCAAYANMTAA==.Nerbert:BAAALgADCgYJBgABLgAECgkJJwAKAAgVAA==.Neretsym:BAABLgAECn8vAAITAAkJMiDoGQCKAgATAAkJMiDoGQCKAgAAAA==.Nergal:BAAALgAECgEJAgAAAA==.Nevercumdin:BAAALgADCgEJAwAAAA==.',
Ni='Nibbzz:BAACLgAFFH8KAAIHAAUJlwVWJQAiAQAHAAUJlwVWJQAiAQAuAAQKfx0AAgcACQl1FNYhAMABAAcACQl1FNYhAMABAAAA.Nineva:BAABLgAECn8mAAIGAAkJpgV3aQD4AAAGAAkJpgV3aQD4AAAAAA==.',
No='Nobas:BAABLgAECn9IAAMNAAkJJg10KACNAQANAAkJJg10KACNAQAGAAEJ6wJ05AAhAAAAAA==.',
Nu='Nugs:BAAALgAECgkJBQAAAA==.',
Ok='Okelani:BAAALgAECgEJAQAAAA==.',
Om='Omen:BAAALgAECggJAgAAAA==.',
On='Onlyfeet:BAAALgAECgMJBgAAAA==.',
Op='Oppgjør:BAABLgAECn8WAAIiAAkJ3RhvEACUAgAiAAkJ3RhvEACUAgAAAA==.',
Or='Oreeree:BAAALgAECgYJBwAAAA==.Orenge:BAAALgAECgQJCAAAAA==.Orkus:BAAALgADCgkJCwAAAA==.Ormr:BAABLgAECn8nAAIKAAkJCBXqHwDZAQAKAAkJCBXqHwDZAQAAAA==.Orpsa:BAAALgADCgYJBgAAAA==.',
Os='Osteo:BAABLgAECn8uAAQCAAgJDwftFAAmAQACAAgJyAbtFAAmAQAQAAgJXgQ+pgD0AAABAAcJCALAPwC1AAAAAA==.',
Ou='Ouron:BAABLgAECn8mAAMcAAgJwBWIOQDJAQAcAAcJUxaIOQDJAQAbAAYJtQxFZACyAAAAAA==.',
Pa='Papashrimps:BAACLgAFFH8fAAIUAAYJohgWUQA7AQAUAAYJohgWUQA7AQAuAAQKfzkAAhQACQl1IuEQAPUCABQACQl1IuEQAPUCAAAA.',
Pe='Penelopee:BAAALgADCgUJBwAAAA==.Perash:BAAALgAECgEJAQAAAA==.',
Ph='Phaere:BAAALgADCgEJAQAAAA==.Phrazes:BAAALgAECgQJBAAAAA==.',
Pi='Pikyu:BAAALgADCgEJAQAAAA==.',
Pl='Placeholder:BAABLgAECn81AAIdAAkJWR96BAC3AgAdAAkJWR96BAC3AgAAAA==.Plaguestingr:BAABLgAECn9EAAITAAkJDSQfCQAQAwATAAkJDSQfCQAQAwAAAA==.',
Po='Pontifex:BAABLgAECn8xAAIJAAkJIhpfAQDrAQAJAAkJIhpfAQDrAQAAAA==.Poporobo:BAAALgADCgEJAQAAAA==.Portandmorph:BAABLgAECn84AAIUAAkJnRjJAgAJAgAUAAkJnRjJAgAJAgAAAA==.Potlock:BAABLgAECn8VAAMQAAgJbAv1pQD1AAAQAAUJLwr1pQD1AAACAAMJhA7iKwBsAAAAAA==.',
Pr='Prayinmantís:BAAALgADCgkJCQAAAA==.Proey:BAABLgAECn9DAAMIAAkJAhlREABZAgAIAAkJAhlREABZAgAHAAUJJhMpQQAGAQAAAA==.Prone:BAABLgAECn9dAAMcAAkJ9w+FAwCPAQAcAAkJ9w+FAwCPAQAbAAYJewnxWwDQAAAAAA==.',
Ps='Psychokiller:BAAALgADCgYJBgAAAA==.',
Pu='Puf:BAAALgAECgMJBwAAAA==.Puipui:BAAALgAECgEJAgAAAA==.Pumpidan:BAAALgAECgIJBQAAAA==.',
Py='Pyrelyn:BAAALgADCgEJAQAAAA==.',
Qr='Qròw:BAAALgADCgMJAwAAAA==.',
Qu='Quinnifred:BAAALgAECgUJCgAAAA==.',
Ra='Raakotah:BAABLgAECn9JAAINAAkJKSXCAgBFAwANAAkJKSXCAgBFAwAAAA==.Raelo:BAABLgAECn8yAAIhAAkJERaSCQAjAgAhAAkJERaSCQAjAgAAAA==.Raijun:BAAALgAECgUJBQABLgAECgkJNAAKAJkUAA==.Raiseurmug:BAABLgAECn8yAAIaAAkJ9BUsFAANAgAaAAkJ9BUsFAANAgAAAA==.Rakash:BAACLgAFFH8UAAISAAUJBhtsWQBAAQASAAUJBhtsWQBAAQAuAAQKfywAAhIACQmTIK0gAL8CABIACQmTIK0gAL8CAAAA.Rarg:BAAALgAFFAIJAgABLgAFFAgJEgARAP0aAA==.Rascaldragon:BAAALgAECgQJBQAAAA==.Ravenlark:BAABLgAECn8ZAAIQAAkJigbregBDAQAQAAkJigbregBDAQAAAA==.Ravia:BAACLgAFFH8FAAIOAAQJSxYxXQDYAAAOAAQJSxYxXQDYAAAuAAQKfyYAAw4ACQlAI2wJAAEDAA4ACQmrImwJAAEDABUABQlSITgJAN0BAAAA.Razuki:BAAALgAECgYJEwABLgAFFAQJDAAiALETAA==.',
Re='Reddale:BAAALgADCgcJDAAAAA==.Redeamer:BAAALgAECgEJAgAAAA==.Resco:BAACLgAFFH8nAAIXAAgJIRdqBAAvAgAXAAgJIRdqBAAvAgAuAAQKfz0AAhcACQkDJV4FAAsDABcACQkDJV4FAAsDAAAA.Rescotwo:BAAALgAECgYJDgAAAA==.',
Rh='Rhozak:BAAALgAECgcJCAABLgAECgkJLgAFAD4ZAA==.',
Ri='Riddle:BAABLgAECn8cAAIcAAkJFgk8bAAXAQAcAAkJFgk8bAAXAQAAAA==.Rimeouo:BAAALgADCgEJAQAAAA==.Rize:BAAALgAECgMJAwABLgAECgkJNAAKAJkUAA==.',
Ro='Rocksolid:BAAALgADCgUJBgAAAA==.Ronnie:BAAALgAECgQJBwAAAA==.Rook:BAACLgAFFH8fAAMSAAYJJByQEABMAQASAAUJJByQEABMAQADAAEJAAAjZwAAAAAuAAQKfykAAhIACAkTIykXAPACABIACAkTIykXAPACAAAA.Rookmonger:BAAALgAECgUJBQABLgAFFAYJHwASACQcAA==.Rosenrott:BAABLgAFFH8FAAITAAIJJB8nHQDBAAATAAIJJB8nHQDBAAAAAA==.Rosepiercer:BAABLgAECn9AAAITAAkJsSMfCAAbAwATAAkJsSMfCAAbAwAAAA==.Rosies:BAAALgAECgUJBwAAAA==.Rouz:BAABLgAECn8cAAIgAAYJeA+KEAACAQAgAAYJeA+KEAACAQAAAA==.',
Ru='Rulia:BAAALgAECgMJAwAAAA==.',
Ry='Ryenoh:BAAALgADCgYJBgAAAA==.Rynnoria:BAAALgAECgEJAQAAAA==.Ryoto:BAACLgAFFH8fAAMKAAUJTiRlGwCHAQAKAAQJ5iNlGwCHAQAgAAMJZyJ3AQDIAAAuAAQKfxwAAwoACQmHJXMZAAoCAAoACQmHJXMZAAoCACAAAwkXJCMmAPIAAAAA.',
Sa='Sadness:BAAALgADCgYJBwAAAA==.Saelyz:BAAALgADCgQJBAAAAA==.Saetha:BAABLgAECn8eAAIjAAkJvg1vAQBEAQAjAAkJvg1vAQBEAQAAAA==.Samandean:BAABLgAECn9LAAIPAAkJshryCgB4AgAPAAkJshryCgB4AgAAAA==.Santhallibar:BAABLgAECn8nAAImAAkJeQPjEQAHAQAmAAkJeQPjEQAHAQAAAA==.Sarasvati:BAABLgAECn8nAAIGAAkJoxrlEQDAAgAGAAkJoxrlEQDAAgAAAA==.Saster:BAABLgAECn8hAAISAAkJgiL8DgD0AgASAAkJgiL8DgD0AgAAAA==.Sathrel:BAAALgADCgIJAgABLgAECgkJBwAEAAAAAA==.',
Sc='Scoops:BAAALgAECgcJBwABLgAFFAUJEQASACscAA==.Scrabs:BAAALgAECgkJDwAAAA==.',
Se='Sellena:BAABLgAECn8uAAIhAAkJMRTmCgAJAgAhAAkJMRTmCgAJAgABLgAECgkJSwAPALIaAA==.Sementha:BAAALgADCgcJDgABLgAECgYJCQAEAAAAAA==.Senpai:BAABLgAECn8UAAIYAAYJyRxQIQCpAQAYAAYJyRxQIQCpAQABLgAFFAgJIAAGAOwZAA==.Sephyra:BAABLgAECn8YAAIRAAkJDQoJAgAwAQARAAkJDQoJAgAwAQAAAA==.',
Sh='Shadowmyst:BAAALgADCgQJCgAAAA==.Shaken:BAAALgAECgIJAgAAAA==.Shandow:BAACLgAFFH8ZAAIUAAUJqxxvTwA/AQAUAAUJqxxvTwA/AQAuAAQKf0wAAhQACQlfJFkGAFADABQACQlfJFkGAFADAAAA.Shango:BAAALgADCgcJCQAAAA==.Shanshunt:BAAALgAFFAIJAgABLgAFFAUJGQAUAKscAA==.Shansoracle:BAACLgAFFH8YAAIJAAYJvBhDBwDhAQAJAAYJvBhDBwDhAQAuAAQKfyEAAgkACQlhHywEAEIDAAkACQlhHywEAEIDAAEuAAUUBQkZABQAqxwA.Shed:BAACLgAFFH8SAAIbAAUJUx+EFwBgAQAbAAUJUx+EFwBgAQAuAAQKfy0AAhsACAltIZYNAMgCABsACAltIZYNAMgCAAEuAAUUBgkVAA0A1BoA.Sheislegend:BAABLgAECn8cAAIJAAcJpBdkHgDSAQAJAAcJpBdkHgDSAQAAAA==.Shelby:BAABLgAECn81AAMJAAkJERrXDwBrAgAJAAkJERrXDwBrAgAIAAUJcRCoQAANAQAAAA==.Sherminater:BAAALgAECgQJBAAAAA==.Shmoon:BAEALgAECgIJAgABLgAECgUJBgAEAAAAAA==.Shmuckman:BAAALgADCgkJEwAAAA==.Shorttotem:BAAALgADCgUJBQAAAA==.Shoty:BAAALgAECgMJAwABLgAFFAYJHwASACQcAA==.',
Si='Siccinok:BAABLgAECn82AAIUAAgJbBZtVwDXAQAUAAgJbBZtVwDXAQAAAA==.Silicá:BAAALgADCgkJCQABLgAECgEJAQAEAAAAAA==.Sindorian:BAABLgAECn8zAAMZAAgJVSFQCQCJAgAZAAgJ7R9QCQCJAgATAAYJHSIRJwAdAgAAAA==.Sink:BAAALgADCgIJAgAAAA==.Sithlord:BAAALgADCgMJAwAAAA==.Sixhundrdlbs:BAAALgAFFAEJAQABLgAFFAUJEQASACscAA==.Sixseven:BAAALgADCgkJCgABLgAFFAQJBQAOAEsWAA==.',
Sk='Skrimphorn:BAAALgAECgEJAQAAAA==.',
Sl='Slanginbolts:BAAALgADCgYJBgAAAA==.Slimped:BAABLgAECn8bAAMMAAkJqhi4HgC3AQAMAAkJkRK4HgC3AQAaAAgJehNTKgBjAQAAAA==.',
Sm='Smurricane:BAAALgAECgUJCAAAAA==.',
Sn='Snowybato:BAAALgAECgUJEgAAAA==.',
So='Solanwarr:BAABLgAECn89AAQRAAkJTCNDAwAEAwARAAkJKCJDAwAEAwAXAAgJ6B3CFwCOAgAnAAMJnRnAVACDAAABLgAFFAMJAwAEAAAAAA==.Solar:BAAALgAECgQJCAAAAA==.Solarial:BAAALgAFFAEJAQAAAA==.Solastra:BAABLgAECn9JAAIiAAkJ6h2/CQDvAgAiAAkJ6h2/CQDvAgAAAA==.Sommer:BAAALgAECgcJBwABLgAECgkJTAANAGIZAA==.Soramai:BAAALgADCgcJDwAAAA==.Soth:BAABLgAECn9IAAMSAAkJ1Ro0JAB0AgASAAkJ1Ro0JAB0AgADAAkJQw92GwCBAQAAAA==.',
Sp='Sparticusdru:BAABLgAECn8WAAIjAAkJih3mBwBVAgAjAAkJih3mBwBVAgAAAA==.Spartpally:BAAALgAECgMJAwAAAA==.Spore:BAAALgAECgMJAwAAAA==.',
Sq='Sqaw:BAAALgAECgEJAQAAAA==.',
St='Starkadia:BAAALgAECgYJBgAAAA==.Staryxia:BAACLgAFFH8fAAMLAAYJ/BSKDAA2AQALAAUJ/BSKDAA2AQADAAEJAAAySQAAAAAuAAQKfy0AAgsACQmhIUsBAPYCAAsACQmhIUsBAPYCAAAA.Steamdruid:BAAALgAECgYJEQAAAA==.Steephany:BAAALgADCgEJAQAAAA==.Stonecookies:BAABLgAECn8hAAMQAAkJKgn5bABiAQAQAAkJPQj5bABiAQABAAUJ7AYySQCTAAAAAA==.Stonecross:BAAALgAECgYJCgAAAA==.Stonehard:BAAALgAECgMJAwAAAA==.Stoneldo:BAAALgADCgEJAQAAAA==.Stonetotem:BAAALgAECgYJDAAAAA==.Stormbolt:BAABLgAECn9MAAINAAkJYhluEwA5AgANAAkJYhluEwA5AgAAAA==.Stormspirit:BAAALgADCgkJEAAAAA==.Striggen:BAABLgAECn8eAAMFAAcJtxa4xAACAQAFAAYJ+BS4xAACAQAdAAYJiQ3tBgBcAAAAAA==.',
Su='Succystrazsa:BAAALgADCgIJAgAAAA==.Sugarsham:BAABLgAECn8hAAQcAAgJ8hZFJwAjAgAcAAgJ8hZFJwAjAgAbAAYJ9QaaZwCwAAAhAAQJjgNVJgByAAAAAA==.Sulwen:BAACLgAFFH8WAAINAAkJHCDvAAA9AgANAAkJHCDvAAA9AgAuAAQKfyAAAg0ACQmQJvwEAFEDAA0ACQmQJvwEAFEDAAAA.Sumerset:BAAALgAECgMJBgAAAA==.Sunnydee:BAAALgAECggJDwAAAA==.Supaflytnt:BAAALgAECgUJCAAAAA==.Sustia:BAABLgAECn8XAAIoAAgJAg6LDABIAQAoAAgJAg6LDABIAQAAAA==.',
Sy='Syrelina:BAAALgAECgQJBAABLgAFFAQJBQAOAEsWAA==.',
Ta='Tacopie:BAAALgAECgQJBgAAAA==.Taera:BAACLgAFFH8IAAIYAAMJ0xPLOgC6AAAYAAMJ0xPLOgC6AAAuAAQKfzgAAhgACQmtImUEAGsDABgACQmtImUEAGsDAAAA.Taika:BAAALgADCgkJDwAAAA==.Tailchaser:BAAALgADCgcJBwAAAA==.Talanazar:BAABLgAECn8+AAQKAAkJWyKVBAAeAwAKAAkJWyKVBAAeAwAgAAYJgR2AFAChAQAkAAMJ0A7KKgCVAAAAAA==.Talavenn:BAABLgAECn88AAIOAAkJjBt/AgCbAQAOAAkJjBt/AgCbAQAAAA==.Tallish:BAABLgAECn8iAAIOAAkJ6wyDnQDnAAAOAAkJ6wyDnQDnAAAAAA==.Tarage:BAAALgAECgIJAgAAAA==.Taterchip:BAABLgAECn8vAAMXAAgJER13GgAaAgAXAAgJ1Bx3GgAaAgARAAIJvRa8PAB/AAAAAA==.Taylia:BAAALgAECgQJBgAAAA==.',
Te='Teaorix:BAAALgADCgQJBAAAAA==.Teds:BAAALgAECgQJBAAAAA==.Temporary:BAAALgADCgYJBgAAAA==.Tempus:BAABLgAECn8VAAIFAAgJ9ATiyAD8AAAFAAgJ9ATiyAD8AAAAAA==.Teradoxx:BAAALgAECgYJDgAAAA==.Teriko:BAABLgAECn8/AAMSAAkJ3h4BGgCrAgASAAkJ3h4BGgCrAgADAAcJKgrWMQDWAAAAAA==.Ternock:BAAALgAECgQJBQAAAA==.Terran:BAAALgAECgMJBQABLgAECgkJSQAOADQhAA==.Teviro:BAAALgAECgUJBwABLgAECgkJTQAZAA4iAA==.',
Th='Thanks:BAAALgAECgEJAQAAAA==.Thequixote:BAAALgADCgEJAQAAAA==.Therizino:BAAALgADCgQJBAAAAA==.Thrashy:BAAALgAECgQJCAAAAA==.Thrum:BAAALgAECgkJCwAAAA==.',
Ti='Tictok:BAAALgADCgcJCQAAAA==.Tinkerballa:BAAALgAECgEJAQAAAA==.',
To='Tonkatsu:BAAALgAECgEJAQAAAA==.Toxictotes:BAAALgAECgMJBQAAAA==.',
Ts='Tsargeras:BAAALgAECgQJBAAAAA==.',
Tw='Twiddleado:BAABLgAECn9HAAIUAAkJIBk7LwBcAgAUAAkJIBk7LwBcAgAAAA==.Twinkie:BAAALgAECggJCAABLgAFFAQJBQAOAEsWAA==.Twinkle:BAAALgADCgEJAQAAAA==.',
Ty='Ty:BAAALgAFFAEJAQAAAA==.Tylor:BAAALgAECgYJDwAAAA==.',
['Tå']='Tåkete:BAAALgAECgYJCwAAAA==.',
Uk='Ukuindadookr:BAAALgADCgYJBgAAAA==.',
Um='Ume:BAAALgAECgEJAQABLgAECgQJCAAEAAAAAA==.',
Un='Unta:BAAALgAECgYJCQAAAA==.',
Va='Valaera:BAAALgAECgcJDwAAAA==.Valenora:BAABLgAECn8eAAIBAAkJ3h2NAgCOAgABAAkJ3h2NAgCOAgAAAA==.Valise:BAABLgAECn8wAAICAAkJ2wTPAwCMAAACAAkJ2wTPAwCMAAAAAA==.Varielle:BAAALgAECgYJCQAAAA==.Varuz:BAAALgAECgUJBwABLgAECgYJEAAEAAAAAA==.Varyz:BAAALgAECgUJBQABLgAECgYJEAAEAAAAAA==.Vaticamt:BAAALgAECgUJBgAAAA==.',
Ve='Vecxx:BAAALgADCgUJBQAAAA==.Velanie:BAAALgAECggJDgAAAA==.Velanise:BAAALgADCgMJAwAAAA==.Velcrostrips:BAAALgAECgEJAQAAAA==.Velight:BAAALgADCgEJAQAAAA==.Velinara:BAAALgAECgEJAQAAAA==.Velindroz:BAAALgAECgMJBgAAAA==.Veloras:BAAALgAECgEJAQAAAA==.Verene:BAABLgAECn8qAAIcAAkJuRatIQBFAgAcAAkJuRatIQBFAgAAAA==.Verinari:BAAALgAECgQJBAABLgAECgkJKgAcALkWAA==.',
Vi='Vibes:BAAALgAECgkJBgABLgAECgkJGQANABMhAA==.Violett:BAAALgAFFAUJAgAAAA==.Viperc:BAEALgADCgMJAwABLgAECgYJKgACAAAIAA==.Vipul:BAAALgAECgEJAgABLgAECgYJDgAEAAAAAA==.Viridria:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.Virridian:BAABLgAECn9TAAITAAkJRCFnAQCgAgATAAkJRCFnAQCgAgAAAA==.Virrigosa:BAAALgAECgYJBgAAAA==.Vistia:BAAALgADCgEJAQAAAA==.Vityazi:BAAALgAECgMJAwABLgAECgkJJwAmAHkDAA==.',
Vl='Vlado:BAAALgAECgEJAgAAAA==.',
Vo='Vodalus:BAAALgADCgUJBQAAAA==.Voideria:BAAALgAECgQJBgAAAA==.Voolock:BAAALgADCgkJDwAAAA==.',
Vy='Vyshana:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.',
Wa='Walbert:BAAALgAFFAcJBAAAAA==.Wallofshame:BAABLgAECn8uAAMiAAkJxh3sDQC1AgAiAAkJxh3sDQC1AgAFAAQJXg4z6QDTAAAAAA==.Walt:BAAALgADCgIJAgAAAA==.Warchef:BAAALgADCgYJCgABLgAECgkJSwAUAGYhAA==.Warriorclaps:BAAALgADCggJDgAAAA==.Wartooth:BAABLgAECn9NAAMBAAkJXhyjAwBWAgABAAgJ0h2jAwBWAgAQAAgJsxaiAwBrAQAAAA==.Wassergott:BAAALgADCgIJAgAAAA==.',
We='Webicus:BAABLgAECn8mAAIRAAkJ1BOqEgDBAQARAAkJ1BOqEgDBAQAAAA==.Weezzer:BAAALgADCgQJBAAAAA==.Wegha:BAAALgAECgMJAwAAAA==.Wendee:BAABLgAECn9DAAMJAAkJNQJxQgDiAAAJAAkJNQJxQgDiAAAIAAgJ+gPiXgCcAAAAAA==.',
Wh='Whitefóx:BAACLgAFFH8UAAIdAAUJLRTPBwD9AAAdAAUJLRTPBwD9AAAuAAQKfx4AAh0ACQmYG+wFAIwCAB0ACQmYG+wFAIwCAAEuAAUUBQkZABQAqxwA.Whitley:BAABLgAECn8vAAMcAAkJEyE5BgBNAwAcAAkJEyE5BgBNAwAhAAcJrxWAEgCOAQAAAA==.',
Wi='Wijing:BAAALgAECgIJAgAAAA==.',
Wo='Wolololo:BAAALgAECgEJAQABLgAECgkJIQASAIIiAA==.Wooden:BAAALgAECgQJBwAAAA==.Worldbreaker:BAAALgADCgEJAQAAAA==.',
['Wü']='Wülfsa:BAAALgAECgUJBQAAAA==.',
Xa='Xampu:BAAALgAECgEJAQAAAA==.Xanthium:BAABLgAECn8wAAIJAAkJogHfVQCEAAAJAAkJogHfVQCEAAAAAA==.Xanzib:BAAALgADCgYJBgAAAA==.Xaphy:BAABLgAECn8VAAIJAAcJ2CCaDQCMAgAJAAcJ2CCaDQCMAgAAAA==.Xardots:BAABLgAECn8lAAIBAAgJohUcDAB9AQABAAgJohUcDAB9AQABLgAFFAEJAQAEAAAAAA==.Xardral:BAAALgAECgcJBwABLgAFFAEJAQAEAAAAAA==.',
Xe='Xeelynn:BAAALgAECgMJAwAAAA==.Xeetali:BAAALgADCgYJBgAAAA==.',
Xi='Xiareth:BAABLgAECn9NAAQkAAkJjAxVEwCUAQAkAAkJjAxVEwCUAQAKAAEJPgqXDgAtAAAgAAEJkAbiKAAqAAAAAA==.',
Xt='Xtronger:BAABLgAECn8gAAIGAAgJmRY/MADhAQAGAAgJmRY/MADhAQAAAA==.',
['Xá']='Xároth:BAAALgAFFAEJAQAAAQ==.',
Ya='Yaddi:BAAALgAECgQJBgAAAA==.Yarrow:BAAALgADCgkJEgAAAA==.',
Ye='Yeeyee:BAABLgAECn8ZAAINAAkJEyG3BQD9AgANAAkJEyG3BQD9AgAAAA==.',
Za='Zackor:BAAALgAECggJEQAAAA==.Zalik:BAAALgAECgMJAwAAAA==.',
Ze='Zeebo:BAABLgAECn8UAAMgAAcJwwyPDgAiAQAgAAcJwwyPDgAiAQAkAAUJawwQIwDWAAAAAA==.Zest:BAABLgAECn8pAAMkAAkJ2BDMDQDzAQAkAAkJ2BDMDQDzAQAKAAIJkAhCfwBgAAAAAA==.',
Zm='Zmaryjane:BAAALgAECgIJBAAAAA==.',
Zo='Zorakfoghorn:BAAALgADCgIJAgAAAA==.Zorakk:BAAALgAECgYJCgAAAA==.Zorithic:BAAALgAECgQJAwAAAA==.Zorrak:BAAALgAECgQJBQAAAA==.',
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
