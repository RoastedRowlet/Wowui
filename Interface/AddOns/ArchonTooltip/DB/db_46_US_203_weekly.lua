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

local lookup = {'Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Unknown-Unknown','Druid-Restoration','Priest-Discipline','Priest-Shadow','Priest-Holy','Evoker-Augmentation','DeathKnight-Frost','Druid-Balance','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Warrior-Protection','DeathKnight-Unholy','Hunter-BeastMastery','Mage-Frost','DemonHunter-Vengeance','Warrior-Fury','Hunter-Survival','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Shaman-Elemental','Paladin-Protection','Mage-Fire','Shaman-Restoration','Rogue-Subtlety','Evoker-Devastation','Shaman-Enhancement','Druid-Guardian','Paladin-Holy','Druid-Feral','Evoker-Preservation','Mage-Arcane','Rogue-Assassination','Warrior-Arms','Rogue-Outlaw',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Absens:BAABLgAECn8+AAMBAAkJwhIhCgCEAQABAAkJhw8hCgCEAQACAAgJ0hDuCwB7AQAAAA==.',
Ad='Adorian:BAAALgAECgcJBwABLgAFFAQJEAADAKkfAA==.Adwillon:BAAALgADCgQJBQABLgAECgYJDgAEAAAAAA==.',
Ae='Aedoril:BAAALgADCgEJAQAAAA==.Aelyss:BAAALgADCgQJBAAAAA==.Aerosse:BAAALgADCgEJAQAAAA==.',
Af='Aforceofone:BAAALgAECgQJEQAAAA==.',
Ai='Airdreanna:BAAALgADCgQJBAAAAA==.',
Ak='Akama:BAAALgAECgYJCwABLgAFFAcJHAAFAJ8cAA==.',
Al='Alivanllan:BAAALgAECgIJAgAAAA==.Alteisen:BAAALgAECgUJBQAAAA==.',
Am='Ambitious:BAAALgAECgMJCgAAAA==.Amerlinn:BAAALgAECgYJDAAAAA==.',
An='Anamuht:BAABLgAECn8aAAQGAAkJnhLoFgD9AQAGAAgJeBPoFgD9AQAHAAkJ1BCoHQC5AQAIAAYJHhCzLwA6AQABLgAECgkJOgAJABUgAA==.Andryn:BAAALgAECgEJAQAAAA==.Annaday:BAABLgAECn8gAAIDAAgJtg10JAAVAQADAAgJtg10JAAVAQAAAA==.Antiock:BAACLgAFFH8QAAMDAAQJqR87EABFAQADAAQJqR87EABFAQAKAAQJVBNuCQAyAQAuAAQKfy8AAwMACQn8I5EDAPUCAAMACQn8I5EDAPUCAAoABwnRHK0IANIBAAAA.Anyaesthesia:BAAALgADCgYJBgAAAA==.Anyamonka:BAAALgAECgYJEgAAAA==.',
Ap='Apocalich:BAAALgAECgUJBQAAAA==.Appalachia:BAAALgADCgIJAgAAAA==.',
Aq='Aquenia:BAAALgADCggJDAAAAA==.',
Ar='Aralaith:BAABLgAECn8jAAIHAAgJYiVeBwDBAgAHAAgJYiVeBwDBAgABLgAFFAgJFAALAEQiAA==.Argonaut:BAAALgAECgIJAgAAAA==.Argul:BAAALgAECgIJAgAAAA==.Ariea:BAAALgADCgYJBgAAAA==.Artoriá:BAAALgAECgEJAQAAAA==.Artto:BAABLgAECn8qAAIMAAcJnw+rkwAwAQAMAAcJnw+rkwAwAQAAAA==.',
As='Asevenhex:BAAALgAECgEJAQAAAA==.Ashbrínger:BAABLgAECn9HAAIMAAkJDCY0AgBoAwAMAAkJDCY0AgBoAwAAAA==.Association:BAAALgAECgMJAwAAAA==.Astrum:BAAALgAECgEJAgAAAA==.Asunã:BAAALgAECgIJAgAAAA==.',
Au='Aurah:BAAALgAECgIJBAAAAA==.',
Av='Averax:BAABLgAECn8xAAMNAAgJfR2YHABUAgANAAgJfR2YHABUAgAOAAEJvQ2JbgA3AAAAAA==.Avyrax:BAAALgADCgcJDQABLgAECggJMQANAH0dAA==.',
Ay='Aybara:BAAALgADCgQJBAAAAA==.Aylakaye:BAAALgADCgMJAwAAAA==.Ayraena:BAABLgAECn8ZAAMLAAgJHQiuNwAaAQALAAgJHQiuNwAaAQAFAAQJEgGzugA+AAAAAA==.',
Az='Azkariel:BAAALgADCgQJBAAAAA==.Azyrieth:BAAALgADCgEJAQAAAA==.Azzathoth:BAAALgADCgcJDAAAAA==.',
Ba='Babyshoes:BAAALgAECgEJAQAAAA==.Bakedtofu:BAABLgAECn8UAAMBAAYJ7wc9RwCZAAAPAAYJ7wfzxAC1AAABAAQJGQQ9RwCZAAAAAA==.Bashine:BAABLgAECn8VAAIQAAYJVxlZGACTAQAQAAYJVxlZGACTAQABLgAFFAYJGAARAJkfAA==.Baylohn:BAABLgAECn8lAAISAAkJhRaOKQAhAgASAAkJhRaOKQAhAgAAAA==.',
Be='Bearwrestler:BAABLgAECn8aAAITAAgJ1BdOWwC0AQATAAgJ1BdOWwC0AQABLgAFFAQJDwADAJAgAA==.Beefynugs:BAAALgAECgkJAgAAAA==.',
Bi='Bier:BAAALgAECgQJCgAAAA==.Bigrig:BAAALgAECgkJEwAAAA==.Bitterman:BAABLgAECn8vAAMPAAkJQhgXHABtAgAPAAkJQhgXHABtAgABAAEJww/ZcAA1AAAAAA==.',
Bj='Bjornvalion:BAAALgADCgQJBAAAAA==.',
Bl='Blackmage:BAAALgAECgEJAQAAAA==.Bladed:BAABLgAECn8dAAQUAAcJJhoqDQBnAQAUAAYJChsqDQBnAQANAAcJqxLoXABZAQAOAAEJAACPdAAAAAAAAA==.Blinx:BAAALgADCgQJBAAAAA==.Bloodymess:BAAALgAECgcJDAAAAA==.',
Bo='Boogies:BAAALgADCgQJBwAAAA==.Bovinedivine:BAAALgAECgYJBgABLgAECgkJNAAEAAAAAA==.',
Bu='Buffie:BAABLgAECn8ZAAIMAAgJGhoeWADaAQAMAAgJGhoeWADaAQAAAA==.Bullwyf:BAAALgADCgMJAwAAAA==.Bumblbeetuna:BAAALgAECgMJAwAAAA==.',
['Bá']='Bád:BAAALgADCggJDgABLgAECgUJBQAEAAAAAA==.',
Ca='Calduu:BAAALgAECgQJCAAAAA==.Caledia:BAAALgAECgYJEQAAAA==.Callana:BAAALgADCgMJBQAAAA==.Camedra:BAABLgAECn9EAAIFAAkJkCS7AQC1AwAFAAkJkCS7AQC1AwAAAA==.Carinancey:BAAALgAECgEJAQAAAA==.Carperoni:BAAALgADCgcJBwAAAA==.Casseous:BAAALgADCgUJBwAAAA==.Catamynyia:BAABLgAECn8fAAISAAgJJAx8XwBvAQASAAgJJAx8XwBvAQAAAA==.Caylaetal:BAAALgAECgEJAQAAAA==.',
Cc='Cchaos:BAAALgAECgIJBgAAAA==.',
Ce='Celaborn:BAABLgAECn8bAAIVAAgJhBxOJQC3AQAVAAgJhBxOJQC3AQAAAA==.Cerwan:BAAALgADCgMJAwAAAA==.',
Ch='Chazaraz:BAABLgAECn86AAMWAAkJNA2uFQDpAQAWAAkJcQyuFQDpAQASAAgJEgiJegAxAQAAAA==.Chevy:BAAALgAECgEJAwAAAA==.Chifreak:BAAALgAFFAIJAgABLgAECggJIgANAAQjAA==.Chillmourne:BAAALgAECgcJEwABLgAECggJFgABAJIIAA==.Chimaira:BAAALgADCgIJAgAAAA==.Chucknoris:BAAALgAECgMJAwAAAA==.Chugbuggins:BAAALgAECgYJDgAAAA==.',
Ci='Cindria:BAABLgAECn8lAAITAAgJuBCMcAB/AQATAAgJuBCMcAB/AQAAAA==.',
Cl='Clerks:BAAALgAECgEJAQAAAA==.Cliffgate:BAAALgADCgMJAwAAAA==.',
Co='Conduction:BAAALgAECgUJCAAAAA==.Corenthia:BAAALgAECgUJCAAAAA==.',
Cp='Cptbonez:BAAALgAECgYJEgABLgAECgkJKQAXAEYTAA==.',
Cr='Crankadin:BAAALgADCgUJBQABLgAECgIJBAAEAAAAAA==.Crankchi:BAAALgADCgYJBwABLgAECgIJBAAEAAAAAA==.Crazz:BAAALgADCgEJAQAAAA==.Crewz:BAAALgADCgQJBAAAAA==.Crooky:BAAALgADCgcJBwABLgAFFAYJGwARANUbAA==.Crucifiiks:BAAALgAECgQJBQAAAA==.Cruciö:BAAALgAECgEJAQAAAA==.Crànk:BAAALgAECgIJBAAAAA==.',
Cu='Curveball:BAAALgAECggJDAABLgAECgkJLwAPAEIYAA==.',
Da='Dalearnhardt:BAAALgADCgcJDgABLgAECgcJEgAEAAAAAA==.Damerlin:BAAALgAECgcJEgAAAA==.Darkstär:BAABLgAECn9EAAIDAAkJNB01BwCVAgADAAkJNB01BwCVAgAAAA==.Darkwood:BAAALgADCgEJAgAAAA==.Dauc:BAAALgADCgEJAQAAAA==.',
De='Deacon:BAABLgAECn8xAAQXAAgJewiPOAAJAQAXAAgJJwaPOAAJAQAYAAUJmgr9UQCqAAAZAAUJfQSydwB4AAAAAA==.Deadmantooth:BAAALgADCgYJBgABLgAECggJMQABAH8cAA==.Deardren:BAAALgAECgUJBQAAAA==.Deathknights:BAAALgAFFAEJAQAAAA==.Deathtrol:BAAALgAECggJCQAAAA==.Deeanne:BAAALgAECgQJBwAAAA==.Deepdeuce:BAAALgAECgQJBAAAAA==.Deepfriar:BAABLgAECn9EAAMIAAkJ4CO3AQCNAwAIAAkJ4CO3AQCNAwAHAAcJMRQSJwB0AQAAAA==.Deidra:BAAALgADCgMJAwAAAA==.Demonhunts:BAABLgAFFH8HAAINAAQJfwjSSADzAAANAAQJfwjSSADzAAAAAA==.Demonmore:BAABLgAECn8jAAMOAAgJxAt4JAAwAQAOAAgJ2Ap4JAAwAQAUAAUJWQqMHQCVAAAAAA==.Derailed:BAAALgAECgQJBwAAAA==.Dethwing:BAAALgAECgEJAQAAAA==.Devilfrost:BAAALgAECgEJAQABLgAECgMJBgAEAAAAAA==.Dewshine:BAAALgAECgYJCwAAAA==.',
Dh='Dhampir:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Dhgeek:BAAALgAECgMJBQAAAA==.',
Di='Diablognomis:BAAALgAECgUJDAAAAA==.Dingô:BAAALgAECgQJBAAAAA==.Dirtman:BAABLgAECn8qAAIaAAgJuRvIGgDzAQAaAAgJuRvIGgDzAQAAAA==.',
Dk='Dkrise:BAAALgAECgMJAwABLgAECgkJJgAJAFELAA==.',
Dn='Dneoh:BAAALgAECgkJCAABLgAFFAMJCgALAOciAA==.',
Do='Donald:BAAALgADCgQJBAAAAA==.Donny:BAABLgAECn8kAAMMAAgJMB23LgAtAgAMAAgJMB23LgAtAgAbAAEJWw8fSgAsAAAAAA==.Doodyshamala:BAAALgAECgQJBwAAAA==.Dooky:BAAALgAECgEJAQABLgAFFAYJGwARANUbAA==.Doozey:BAACLgAFFH8OAAINAAQJJxaeMwAuAQANAAQJJxaeMwAuAQAuAAQKfycAAw0ACQniHnQcAKcCAA0ACAl4IHQcAKcCABQAAQnNEyIqAEUAAAAA.Dorigis:BAAALgADCgkJMAABLgAECgkJIAAQABcjAA==.Dotdotdotded:BAABLgAECn8WAAIPAAgJuAU5iQAdAQAPAAgJuAU5iQAdAQAAAA==.',
Dr='Drewdog:BAABLgAECn8uAAMWAAgJ7RRpHACrAQAWAAgJgQ5pHACrAQASAAYJeBe4bwBJAQAAAA==.Droid:BAAALgAECgEJAgAAAA==.Drunkgerardo:BAAALgAECgQJBQAAAA==.Drunkzen:BAAALgAECgUJBQAAAA==.Druyesil:BAAALgAECgEJAgAAAA==.',
Du='Dubes:BAABLgAECn9BAAITAAkJzBj9JAByAgATAAkJzBj9JAByAgAAAA==.Dunbartian:BAAALgAECgYJBwAAAA==.',
['Dá']='Dárkthorn:BAAALgAECgIJBAAAAA==.',
['Dö']='Dökkálfar:BAAALgAECgEJAQAAAA==.',
Ea='Easybreezin:BAAALgAECgUJDAAAAA==.',
Ei='Eirote:BAABLgAECn9DAAIcAAkJtBpOAQCLAgAcAAkJtBpOAQCLAgAAAA==.',
El='Elarris:BAAALgAECgUJBQAAAA==.Eldari:BAABLgAECn8YAAILAAgJ2htGGADzAQALAAgJ2htGGADzAQAAAA==.Elem:BAACLgAFFH8PAAIdAAYJUwjoGwBfAQAdAAYJUwjoGwBfAQAuAAQKfyMAAh0ACAmcIFMYAFMCAB0ACAmcIFMYAFMCAAAA.Ellyssanna:BAAALgAECgEJAQAAAA==.Elm:BAAALgAECgYJEAAAAA==.Elyssaena:BAAALgAECgYJEgAAAA==.',
Em='Emiliachan:BAAALgAECgcJCwAAAA==.',
En='Enzojr:BAACLgAFFH8IAAIeAAQJAxpxEQBcAQAeAAQJAxpxEQBcAQAuAAQKf0IAAh4ACQkBJIECACMDAB4ACQkBJIECACMDAAAA.',
Ep='Ephixa:BAAALgAECgYJDwAAAA==.',
Er='Eridanos:BAAALgADCgYJBgAAAA==.Erisiel:BAAALgAECgEJAQAAAA==.Eruelle:BAACLgAFFH8JAAINAAQJ2yKfHQCPAQANAAQJ2yKfHQCPAQAuAAQKfxsAAg0ACQnRIgYEADgDAA0ACQnRIgYEADgDAAEuAAUUCAkUAAsARCIA.Erzå:BAAALgAECgEJAQAAAA==.',
Ev='Evoke:BAABLgAECn8fAAMJAAgJgyF3CgDOAgAJAAgJdB93CgDOAgAfAAYJZyBaDQAEAgAAAA==.',
Ey='Eye:BAACLgAFFH8IAAIgAAMJBiHbBwAjAQAgAAMJBiHbBwAjAQAuAAQKfyAAAyAACQnRICQGAGACACAACQnRICQGAGACABoAAQmZDN2PACgAAAAA.',
['Eí']='Eís:BAAALgADCgYJCwAAAA==.',
Fa='Faeira:BAAALgAECgcJCQAAAA==.Faloril:BAAALgAECgMJBQAAAA==.Falsara:BAAALgAECgQJBAAAAA==.Faranth:BAABLgAECn9CAAIJAAkJMSDABQDrAgAJAAkJMSDABQDrAgAAAA==.Faronyr:BAAALgAECgEJAQAAAA==.',
Fe='Felboi:BAAALgAECgUJDgAAAA==.Felknight:BAAALgADCgYJBgAAAA==.Felorc:BAAALgAECgQJBwAAAA==.Felynne:BAAALgAECgcJDgAAAA==.Fenrík:BAAALgADCgIJAgAAAA==.Feo:BAABLgAECn8ZAAINAAgJnxdsPwCzAQANAAgJnxdsPwCzAQAAAA==.Ferum:BAABLgAECn9IAAMFAAkJNiUuAQDHAwAFAAkJNiUuAQDHAwALAAYJuRB/OgAMAQAAAA==.',
Fi='Fionnan:BAABLgAECn89AAIhAAkJpg3XGABkAQAhAAkJpg3XGABkAQABLgAECgkJRAAdAG8OAA==.',
Fo='Forest:BAACLgAFFH8MAAQLAAQJpxH3HQAFAQALAAQJpxH3HQAFAQAFAAIJZwbSUwBoAAAhAAIJtghvJABeAAAuAAQKfy4AAwsACQl6HSkNAMYCAAsACQl6HSkNAMYCAAUAAwn3G7ZmAO4AAAAA.',
Fr='Fretless:BAAALgADCgYJCgAAAA==.Frixley:BAAALgAECgkJCwAAAA==.Friérén:BAAALgAECgEJAQAAAA==.Frostedrayne:BAAALgADCgUJBQAAAA==.Frostthrower:BAAALgAECgEJAgAAAA==.Fryeguy:BAAALgAECggJEwAAAA==.',
Fu='Funkysoup:BAAALgADCgYJBgAAAA==.',
Fy='Fyodor:BAAALgAECgIJBQAAAA==.',
['Fè']='Fèresha:BAAALgAECgkJEgAAAA==.',
['Fò']='Fòrced:BAAALgAECgYJBgAAAA==.',
Ga='Gallium:BAABLgAECn8aAAIiAAkJnBZ6FgBAAgAiAAkJnBZ6FgBAAgAAAA==.Gazerbeam:BAAALgAFFAEJAQAAAA==.',
Ge='Geelock:BAAALgADCggJFgAAAA==.Gehena:BAAALgAFFAIJAgABLgAFFAIJAwAEAAAAAQ==.Gemsareyum:BAAALgAECgYJDgABLgAFFAUJOAASAGolAA==.Gesht:BAABLgAECn8YAAIMAAgJSg6FlwAqAQAMAAgJSg6FlwAqAQAAAA==.',
Gh='Ghostfreak:BAAALgAECgUJBgAAAA==.',
Gi='Gidgetz:BAAALgADCgMJAwAAAA==.',
Gl='Glamourkills:BAAALgADCgcJDQAAAA==.Gleipnir:BAAALgAECgIJAgAAAA==.',
Go='Goldenbell:BAAALgAECgUJBQAAAA==.Goof:BAABLgAECn82AAIiAAkJ9Q7pLQCQAQAiAAkJ9Q7pLQCQAQAAAA==.Goontas:BAAALgAECgMJBAAAAA==.',
Gr='Grimsheèper:BAAALgAECgMJBAAAAA==.Grish:BAABLgAECn8ZAAIgAAYJHgbFHwDQAAAgAAYJHgbFHwDQAAAAAA==.Griz:BAAALgAECgQJCAAAAA==.Grollnar:BAAALgAECgEJAQABLgAECgkJDwAEAAAAAA==.Grossevache:BAAALgAECgYJEAAAAA==.Gròws:BAAALgAECgkJBwAAAA==.',
Ha='Haddor:BAABLgAECn8mAAMbAAgJ6xrhCQAVAgAbAAgJ6xrhCQAVAgAMAAEJWwQ6nwEcAAAAAA==.Haelexi:BAAALgAECgMJAwAAAA==.Halujoxar:BAAALgADCgcJDgABLgAECgkJNAAEAAAAAA==.Hamonkulous:BAAALgADCgcJCAAAAA==.Hankerin:BAAALgADCgcJCAAAAA==.Harandar:BAAALgAECgEJAQAAAA==.Harpomage:BAAALgADCgcJCQAAAA==.Hatcher:BAAALgAECgEJAQAAAA==.Haunter:BAABLgAECn8gAAMRAAgJwyG9aACAAQARAAYJLR+9aACAAQADAAUJlR5hHgBJAQAAAA==.Hayleigh:BAACLgAFFH8cAAIFAAcJnxx5BQB4AgAFAAcJnxx5BQB4AgAuAAQKfzEAAgUACQmEIv0EAFwDAAUACQmEIv0EAFwDAAAA.',
He='Heimdallr:BAAALgAECgEJAQAAAA==.Heisenborg:BAAALgAECgUJBQAAAA==.Hellbreezy:BAAALgAECgkJEAAAAA==.Helldin:BAABLgAECn8nAAIMAAYJ3hVBkAA2AQAMAAYJ3hVBkAA2AQAAAA==.Hellenfeller:BAABLgAECn8cAAIOAAYJhRQCJAA0AQAOAAYJhRQCJAA0AQAAAA==.',
Hi='Hilitepriest:BAABLgAECn8bAAMGAAgJ0RkXEwApAgAGAAgJQBkXEwApAgAIAAIJ1BZvaACLAAAAAA==.Hittomi:BAAALgAECgYJBgAAAA==.',
Ho='Holific:BAABLgAECn9EAAIMAAkJPhe9KwA5AgAMAAkJPhe9KwA5AgAAAA==.Honeychild:BAAALgAECgYJCgAAAA==.Hotrodranger:BAAALgAECgcJEgAAAA==.Hottub:BAAALgAECgEJAQAAAA==.',
Hu='Huckleberry:BAAALgADCggJDQAAAA==.',
Hv='Hvac:BAABLgAECn81AAITAAkJywwHXgCsAQATAAkJywwHXgCsAQAAAA==.',
Ic='Iceovo:BAAALgADCgEJAQAAAA==.Icycritties:BAABLgAECn8YAAITAAYJehAlvQBoAQATAAYJehAlvQBoAQAAAA==.',
Id='Idovoodew:BAAALgADCgUJCAAAAA==.',
Ih='Iheals:BAAALgAECgMJCQAAAA==.',
Im='Imjustadruid:BAAALgADCggJCgAAAA==.Immortal:BAABLgAECn8fAAIRAAkJBxlrIgBpAgARAAkJBxlrIgBpAgAAAA==.Implants:BAAALgADCggJCQAAAA==.',
In='Incarnate:BAAALgAECgcJEAAAAA==.Incarnated:BAACLgAFFH8QAAMRAAUJ1xtJYwAYAQARAAQJ8iBJYwAYAQAKAAMJoRKuDgDrAAAuAAQKfzIAAxEACQnII2ALAAIDABEACQl3I2ALAAIDAAoAAgnlJRQYAOEAAAAA.Inflammation:BAAALgADCgcJDwABLgAECgUJCAAEAAAAAA==.',
Ir='Irocc:BAAALgAECgMJCgAAAA==.',
Is='Ishankyou:BAAALgAECgEJAQAAAA==.Istara:BAAALgADCgcJDQABLgAFFAcJGAATACYdAA==.',
Iu='Iu:BAAALgADCgEJAgAAAA==.',
Ja='Jackdowe:BAAALgAECgQJBAAAAA==.Jackfash:BAAALgADCgcJDQAAAA==.Jadecross:BAABLgAECn8WAAIZAAcJSxZkKwCnAQAZAAcJSxZkKwCnAQAAAA==.Jalenhunter:BAAALgADCgUJCAAAAA==.',
Je='Jedith:BAAALgAECgQJBAAAAA==.Jerambae:BAAALgAECgYJEgAAAA==.Jerryatric:BAABLgAECn8WAAIMAAkJIgyJZwCGAQAMAAkJIgyJZwCGAQAAAA==.',
Jo='Joelah:BAAALgAECgcJDwAAAA==.Joshua:BAAALgAECgYJDAAAAA==.',
Ju='Justincasê:BAAALgADCgcJEgAAAA==.',
['Jâ']='Jây:BAAALgADCgQJBAAAAA==.',
Ka='Kalfeen:BAABLgAECn8bAAMhAAcJbh6LCwAKAgAhAAcJbh6LCwAKAgAjAAEJ+wa+TQAkAAAAAA==.Kallikan:BAABLgAECn8kAAIhAAgJzBQvFQCIAQAhAAgJzBQvFQCIAQAAAA==.Kamidk:BAABLgAFFH8HAAIRAAQJ1g1QpgCfAAARAAQJ1g1QpgCfAAABLgAFFAQJCgANAAMXAA==.Kanmojo:BAAALgADCgQJBQAAAA==.Kashume:BAABLgAECn8bAAIgAAkJngJlGgAIAQAgAAkJngJlGgAIAQAAAA==.Kasteen:BAAALgAECgUJCwAAAA==.Kazon:BAAALgADCgcJCgABLgAFFAQJEAADAKkfAA==.Kaøs:BAAALgAECgEJAQAAAA==.',
Kd='Kdoggparker:BAAALgAECgIJAwAAAA==.',
Ke='Kementari:BAAALgAECgQJBQAAAA==.Kenzaki:BAACLgAFFH8QAAIMAAUJmQptRQAIAQAMAAUJmQptRQAIAQAuAAQKfzQAAgwACAmFGl5PAMEBAAwACAmFGl5PAMEBAAAA.',
Kh='Khaosreborn:BAAALgAECgUJEAAAAA==.Khaotic:BAAALgADCgMJAwABLgADCgQJBAAEAAAAAA==.',
Ki='Kiiren:BAAALgAECgEJAQABLgAECgcJGwAhAG4eAA==.Kilaaz:BAABLgAECn8VAAIMAAUJzCTDbgB2AQAMAAUJzCTDbgB2AQAAAA==.Kilaz:BAAALgADCgUJBQAAAA==.',
Kn='Knuts:BAACLgAFFH8HAAIXAAQJBRZxHQAkAQAXAAQJBRZxHQAkAQAuAAQKfxYAAhcACQlUGCkcALIBABcACQlUGCkcALIBAAAA.',
Ko='Korius:BAAALgAECgUJBQAAAA==.Ková:BAABLgAECn8YAAISAAgJ1hlpLQAQAgASAAgJ1hlpLQAQAgAAAA==.',
Kr='Krutesiq:BAAALgADCgkJCQAAAA==.',
Ku='Kuani:BAAALgAECgYJBwABLgAECggJMwAZAIshAA==.Kullman:BAAALgADCgYJCgAAAA==.Kungfupapa:BAAALgAECgQJBQAAAA==.Kungfurry:BAAALgAECgUJCAAAAA==.Kurobozu:BAAALgAECgQJBAABLgAECgkJOgAJABUgAA==.Kutherrek:BAAALgAECgEJAQAAAA==.Kuubar:BAABLgAECn8hAAIKAAgJ5RNoDQBwAQAKAAgJ5RNoDQBwAQAAAA==.',
Ky='Kyian:BAAALgAECgMJAwAAAA==.',
La='Ladaeze:BAAALgADCgIJAgAAAA==.Ladiesnutz:BAABLgAECn8aAAQkAAkJuh7DFQBfAQAkAAQJ4R/DFQBfAQAfAAUJThv5CwBCAQAJAAcJehSUMQA7AQAAAA==.Law:BAAALgAECgEJAQABLgAFFAcJHAAFAJ8cAA==.Laz:BAAALgADCgMJAwAAAA==.Lazerous:BAAALgADCgYJBgAAAA==.',
Le='Leafá:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.Lealoo:BAABLgAECn8rAAIMAAcJ/xoJRgDcAQAMAAcJ/xoJRgDcAQABLgAECgkJNAAOANQVAA==.Leghorn:BAAALgADCgIJAgABLgAECgcJGwAhAG4eAA==.Legolard:BAABLgAECn8gAAIQAAkJFyOXAgANAwAQAAkJFyOXAgANAwAAAA==.Lever:BAAALgADCggJCQAAAA==.',
Li='Liath:BAAALgAECgUJCQAAAA==.Lightsky:BAAALgADCgIJAQAAAA==.Lildèbbíe:BAABLgAECn8oAAITAAgJMg2PcgB6AQATAAgJMg2PcgB6AQAAAA==.Lilspoon:BAAALgADCgMJAwAAAA==.Liltrapstarx:BAAALgAECgQJCAAAAA==.Linddori:BAABLgAECn8oAAIMAAgJphtmNwALAgAMAAgJphtmNwALAgAAAA==.Lindmajik:BAAALgAECgQJBgAAAA==.Liori:BAAALgAECgcJEgAAAA==.Lirillïa:BAAALgADCggJDQABLgAECggJKAAMAKYbAA==.',
Lo='Lodestone:BAAALgADCgMJAwAAAA==.Loena:BAABLgAECn8iAAIMAAkJXiMFCQANAwAMAAkJXiMFCQANAwAAAA==.Lokk:BAAALgAECgQJBAABLgAECgYJDwAEAAAAAA==.Lovelydread:BAAALgAECgQJBAAAAA==.',
Lu='Lunabug:BAACLgAFFH8HAAIYAAMJowt9IAC+AAAYAAMJowt9IAC+AAAuAAQKfygAAhgACAl8HeoYANMBABgACAl8HeoYANMBAAAA.Lupinos:BAAALgADCgYJCAAAAA==.',
Ly='Lyadra:BAABLgAECn8tAAIIAAkJ+B3hBQAIAwAIAAkJ+B3hBQAIAwAAAA==.Lyandre:BAACLgAFFH8NAAMIAAUJhApnEAAnAQAIAAUJhApnEAAnAQAGAAQJSQG5LAC2AAAuAAQKfx4AAwgACAlGE4MWACgCAAgACAlGE4MWACgCAAYAAQnAELpoADUAAAAA.Lydra:BAAALgAECgUJBQAAAA==.Lynna:BAAALgADCgQJBAAAAA==.Lyntoo:BAAALgAECgIJAQAAAA==.Lyntu:BAAALgAECgEJAQAAAA==.',
['Lú']='Lúffy:BAAALgAECgcJBwABLgAECggJIgANAAQjAA==.',
Ma='Maania:BAAALgADCgEJAQAAAA==.Madan:BAABLgAECn8eAAIRAAYJuQWn0gDMAAARAAYJuQWn0gDMAAAAAA==.Malasminna:BAAALgADCgYJBgAAAA==.Malehorelock:BAAALgAECgYJBwABLgAECggJKwAWAB8hAA==.Malicioun:BAAALgADCgEJAQAAAA==.Malkariss:BAABLgAECn8vAAMTAAgJNSDcHwCKAgATAAgJNSDcHwCKAgAlAAEJ5AjgHAA5AAAAAA==.Mammadruid:BAABLgAECn8yAAMhAAgJ0w2hHwAqAQAhAAgJ0w2hHwAqAQAFAAYJpwuDbADdAAAAAA==.Maralen:BAAALgADCgcJCQAAAA==.Marann:BAAALgAECgEJAQAAAA==.Matadør:BAAALgAECgcJDAAAAA==.Mathwhiz:BAAALgAECgYJDwABLgAECgkJLwAPAEIYAA==.Mauldis:BAABLgAECn8wAAIaAAgJvAueNwA+AQAaAAgJvAueNwA+AQAAAA==.Mavgard:BAAALgAECgIJAgAAAA==.Mavgards:BAAALgADCgMJAwABLgAECgIJAgAEAAAAAA==.Maxrebo:BAABLgAECn8eAAIXAAgJoBtYEQAcAgAXAAgJoBtYEQAcAgAAAA==.',
Me='Meatwàd:BAAALgAECgYJCAAAAA==.Mekanzi:BAAALgAECgQJCwAAAA==.Meliõdas:BAAALgAECgUJEQAAAA==.Merebels:BAAALgAECgQJBwABLgAECgYJCwAEAAAAAA==.Merkodisco:BAAALgAECgIJAgAAAA==.',
Mi='Miaka:BAABLgAECn87AAICAAkJ4xzAAQC9AgACAAkJ4xzAAQC9AgAAAA==.Miakah:BAAALgAECgUJBQAAAA==.Midwest:BAAALgADCgQJBAAAAA==.Minirook:BAAALgADCgEJAQABLgAFFAYJGwARANUbAA==.Misfire:BAABLgAECn81AAISAAkJnRWPJAA5AgASAAkJnRWPJAA5AgAAAA==.Mistbusters:BAAALgAECgYJCAAAAA==.Mithra:BAAALgAECgEJAQAAAA==.Mithygos:BAABLgAECn8ZAAIJAAgJWwRxTgDNAAAJAAgJWwRxTgDNAAAAAA==.Mito:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.',
Mo='Moar:BAAALgAECgEJAgAAAA==.Moghroth:BAABLgAECn8zAAMLAAgJQg2FLQBSAQALAAgJOQ2FLQBSAQAhAAEJQwteaAAkAAAAAA==.Molykote:BAAALgAECgMJBgAAAA==.Monks:BAAALgAFFAIJAgAAAA==.Morgiana:BAAALgAECgEJAQAAAA==.',
My='Myhiknee:BAAALgADCgUJCAAAAA==.Myriana:BAAALgAECgQJBwAAAA==.Mystyle:BAAALgADCgcJBwAAAA==.',
['Má']='Mágnus:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâsterdon:BAAALgAECgYJDwAAAA==.',
Na='Nahryn:BAABLgAECn8vAAIFAAgJ8R7pEAC2AgAFAAgJ8R7pEAC2AgAAAA==.Najamei:BAAALgADCgUJBQAAAA==.Najanira:BAAALgADCgYJBgAAAA==.Narya:BAAALgAECgIJAwAAAA==.',
Ne='Nella:BAAALgAECgYJCQABLgAECggJMwAZAIshAA==.Nerbert:BAAALgADCgYJBgABLgAECgkJJwAJAAgVAA==.Neretsym:BAABLgAECn8tAAISAAkJMiBGFACaAgASAAkJMiBGFACaAgAAAA==.Nevercumdin:BAAALgADCgEJAwAAAA==.',
Ni='Nibbzz:BAACLgAFFH8JAAIGAAQJggYnJAD4AAAGAAQJggYnJAD4AAAuAAQKfx0AAgYACQl1FL0dAL0BAAYACQl1FL0dAL0BAAAA.Nineva:BAABLgAECn8eAAIFAAcJ6gO9eAC7AAAFAAcJ6gO9eAC7AAAAAA==.',
No='Nobas:BAABLgAECn9EAAMLAAkJVgvEJgB+AQALAAkJVgvEJgB+AQAFAAEJ6wJ05AAhAAAAAA==.',
Nu='Nugs:BAAALgAECgkJBQAAAA==.',
Ok='Okelani:BAAALgAECgEJAQAAAA==.',
On='Onlyfeet:BAAALgAECgMJBgAAAA==.',
Op='Oppgjør:BAABLgAECn8UAAIiAAkJERfnDwCFAgAiAAkJERfnDwCFAgAAAA==.',
Or='Oreeree:BAAALgAECgYJBwAAAA==.Orenge:BAAALgAECgQJCAAAAA==.Orkus:BAAALgADCgkJCwAAAA==.Ormr:BAABLgAECn8nAAIJAAkJCBXbHADWAQAJAAkJCBXbHADWAQAAAA==.Orpsa:BAAALgADCgYJBgAAAA==.',
Os='Osteo:BAABLgAECn8rAAQCAAgJwgY6FQD7AAAPAAgJXgSOmAACAQACAAcJnwY6FQD7AAABAAcJCALAPwC1AAAAAA==.',
Ou='Ouron:BAABLgAECn8mAAMdAAgJwBXUMgDMAQAdAAcJUxbUMgDMAQAaAAYJtQxFZACyAAAAAA==.',
Pa='Papashrimps:BAACLgAFFH8aAAITAAUJ5RuzPgBQAQATAAUJ5RuzPgBQAQAuAAQKfzkAAhMACQl1ImYNAPoCABMACQl1ImYNAPoCAAAA.',
Pe='Perash:BAAALgAECgEJAQAAAA==.',
Ph='Phrazes:BAAALgAECgQJBAAAAA==.',
Pi='Pikyu:BAAALgADCgEJAQAAAA==.',
Pl='Placeholder:BAABLgAECn8qAAIbAAgJ/hpzCgAKAgAbAAgJ/hpzCgAKAgAAAA==.Plaguestingr:BAABLgAECn9EAAISAAkJDSRYBgAeAwASAAkJDSRYBgAeAwAAAA==.',
Po='Pontifex:BAABLgAECn8lAAIIAAgJrhoSEQBEAgAIAAgJrhoSEQBEAgAAAA==.Portandmorph:BAABLgAECn8oAAITAAkJtxXFNAAtAgATAAkJtxXFNAAtAgAAAA==.Potlock:BAAALgAECgQJDAAAAA==.',
Pr='Proey:BAABLgAECn9DAAMHAAkJAhnJDQBdAgAHAAkJAhnJDQBdAgAGAAUJJhMdOQAGAQAAAA==.Prone:BAABLgAECn9EAAIdAAkJbw69NgC6AQAdAAkJbw69NgC6AQAAAA==.',
Ps='Psychokiller:BAAALgADCgYJBgAAAA==.',
Pu='Puf:BAAALgAECgMJBwAAAA==.Puipui:BAAALgADCgEJAQAAAA==.Pumpidan:BAAALgAECgIJBQAAAA==.',
Py='Pyrelyn:BAAALgADCgEJAQAAAA==.',
Qr='Qròw:BAAALgADCgMJAwAAAA==.',
Qu='Quinnifred:BAAALgAECgQJBgAAAA==.',
Ra='Raakotah:BAABLgAECn9JAAILAAkJKSU6AgBLAwALAAkJKSU6AgBLAwAAAA==.Raelo:BAABLgAECn8nAAIgAAgJ2g2OEQB7AQAgAAgJ2g2OEQB7AQAAAA==.Raiseurmug:BAABLgAECn8pAAIXAAkJRhODFgDlAQAXAAkJRhODFgDlAQAAAA==.Rakash:BAACLgAFFH8QAAIRAAQJBhvsQABPAQARAAQJBhvsQABPAQAuAAQKfyoAAhEACQmTIK0gAL8CABEACQmTIK0gAL8CAAAA.Rarg:BAAALgAFFAIJAgABLgAFFAYJEAAQAOkbAA==.Rascaldragon:BAAALgAECgQJBQAAAA==.Ravenlark:BAABLgAECn8YAAIPAAgJzQYXhgAjAQAPAAgJzQYXhgAjAQAAAA==.Ravia:BAABLgAECn8iAAMNAAgJBCNeEwCUAgANAAgJWiJeEwCUAgAUAAUJUiE4CQDdAQAAAA==.Razuki:BAAALgAECgYJEwABLgAFFAMJBQAiAOgPAA==.',
Re='Reddale:BAAALgADCgcJDAAAAA==.Redeamer:BAAALgAECgEJAgAAAA==.Resco:BAACLgAFFH8nAAIVAAgJIRe5AQBDAgAVAAgJIRe5AQBDAgAuAAQKfz0AAhUACQkDJfwDABcDABUACQkDJfwDABcDAAAA.Rescotwo:BAAALgAECgYJDgAAAA==.',
Ri='Riddle:BAABLgAECn8YAAIdAAkJcgfKbQDyAAAdAAkJcgfKbQDyAAAAAA==.Rimeouo:BAAALgADCgEJAQAAAA==.Rize:BAAALgAECgMJAwABLgAECgkJJgAJAFELAA==.',
Ro='Rocksolid:BAAALgADCgUJBgAAAA==.Ronnie:BAAALgAECgQJBwAAAA==.Rook:BAACLgAFFH8bAAMRAAYJ1RvRJwCPAQARAAUJ1RvRJwCPAQADAAEJAADPVAAAAAAuAAQKfygAAhEACAmwIikXAPACABEACAmwIikXAPACAAAA.Rookmonger:BAAALgAECgUJBQABLgAFFAYJGwARANUbAA==.Rosenrott:BAAALgAFFAIJAwAAAA==.Rosepiercer:BAABLgAECn81AAISAAkJhyM/BgAfAwASAAkJhyM/BgAfAwAAAA==.Rosies:BAAALgAECgUJBwAAAA==.Rouz:BAABLgAECn8cAAIfAAYJeA+YDgARAQAfAAYJeA+YDgARAQAAAA==.',
Ry='Ryenoh:BAAALgADCgYJBgAAAA==.Ryoto:BAACLgAFFH8VAAMJAAQJTiRwEgCcAQAJAAQJ5iNwEgCcAQAfAAIJZiKlCQBnAAAuAAQKfxsAAwkACQmHJUUWAA4CAAkACQmHJUUWAA4CAB8AAwkXJCMmAPIAAAAA.',
Sa='Sadness:BAAALgADCgYJBwAAAA==.Saelyz:BAAALgADCgQJBAAAAA==.Saetha:BAAALgAECggJEwAAAA==.Samandean:BAABLgAECn80AAIOAAkJ1BWxDQAqAgAOAAkJ1BWxDQAqAgAAAA==.Santhallibar:BAABLgAECn8iAAImAAgJuwJTEwDcAAAmAAgJuwJTEwDcAAAAAA==.Sarasvati:BAABLgAECn8iAAIFAAgJ9BwcFACWAgAFAAgJ9BwcFACWAgAAAA==.Saster:BAABLgAECn8hAAIRAAkJgiLbCwD+AgARAAkJgiLbCwD+AgAAAA==.Sathrel:BAAALgADCgIJAgABLgAECgkJBwAEAAAAAA==.',
Sc='Scrabs:BAAALgAECgkJDwAAAA==.',
Se='Sellena:BAABLgAECn8oAAIgAAgJkRSqDQC5AQAgAAgJkRSqDQC5AQABLgAECgkJNAAOANQVAA==.Sementha:BAAALgADCgcJDgABLgAECgYJCQAEAAAAAA==.Senpai:BAABLgAECn8UAAIZAAYJyRxQIQCpAQAZAAYJyRxQIQCpAQABLgAFFAcJHAAFAJ8cAA==.Sephyra:BAAALgAECggJCAAAAA==.',
Sh='Shadowmyst:BAAALgADCgQJCgAAAA==.Shaken:BAAALgAECgIJAgAAAA==.Shandow:BAACLgAFFH8ZAAITAAUJqxx+OwBYAQATAAUJqxx+OwBYAQAuAAQKf0YAAhMACQlfJN8EAFADABMACQlfJN8EAFADAAAA.Shango:BAAALgADCgcJCQAAAA==.Shanshunt:BAAALgADCgUJBgABLgAFFAUJGQATAKscAA==.Shansoracle:BAACLgAFFH8PAAIIAAUJlxW/CACSAQAIAAUJlxW/CACSAQAuAAQKfyEAAggACQlhH20DAEoDAAgACQlhH20DAEoDAAEuAAUUBQkZABMAqxwA.Shed:BAACLgAFFH8RAAIaAAUJUx85EAByAQAaAAUJUx85EAByAQAuAAQKfy0AAhoACAltIZYNAMgCABoACAltIZYNAMgCAAAA.Sheislegend:BAAALgAECgcJEgAAAA==.Shelby:BAABLgAECn8wAAMIAAgJwRv1EABFAgAIAAgJwRv1EABFAgAHAAUJcRA1OQAMAQAAAA==.Shmoon:BAEALgAECgIJAgABLgAECgUJBQAEAAAAAA==.Shmuckman:BAAALgADCgkJEwAAAA==.Shorttotem:BAAALgADCgUJBQAAAA==.Shoty:BAAALgAECgMJAwABLgAFFAYJGwARANUbAA==.',
Si='Siccinok:BAABLgAECn8kAAITAAgJhhGBagCOAQATAAgJhhGBagCOAQAAAA==.Silicá:BAAALgADCgkJCQABLgAECgIJAgAEAAAAAA==.Sindorian:BAABLgAECn8rAAMWAAgJHyHkCACDAgAWAAgJUR/kCACDAgASAAYJHSIRJwAdAgAAAA==.Sink:BAAALgADCgIJAgAAAA==.',
Sk='Skrimphorn:BAAALgAECgEJAQAAAA==.',
Sl='Slimped:BAAALgAECgcJDgAAAA==.',
Sm='Smurricane:BAAALgAECgUJCAAAAA==.',
Sn='Snowybato:BAAALgAECgQJCwAAAA==.',
So='Solandor:BAABLgAECn83AAQQAAkJtCLsAgAAAwAQAAkJjyHsAgAAAwAVAAgJ6B3CFwCOAgAnAAMJnRnoSQCFAAAAAA==.Solar:BAAALgAECgQJCAAAAA==.Solarial:BAAALgAECgUJEQAAAA==.Solastra:BAABLgAECn8tAAIiAAgJeRrWEQBwAgAiAAgJeRrWEQBwAgAAAA==.Soramai:BAAALgADCgcJDwAAAA==.Soth:BAABLgAECn9EAAMRAAkJtRleIwBkAgARAAkJtRleIwBkAgADAAkJQw/MFwCLAQAAAA==.',
Sp='Sparticusdru:BAAALgAECgcJEQAAAA==.Spore:BAAALgAECgMJAwAAAA==.',
Sq='Sqaw:BAAALgAECgEJAQAAAA==.',
St='Starkadia:BAAALgAECgYJBgAAAA==.Staryxia:BAACLgAFFH8aAAMKAAUJQBfsCAA4AQAKAAQJQBfsCAA4AQADAAEJAABRPAAAAAAuAAQKfy0AAgoACQmhIUsBAPYCAAoACQmhIUsBAPYCAAAA.Steamdruid:BAAALgAECgYJEQAAAA==.Stonecookies:BAABLgAECn8dAAMPAAgJ/AhuegA5AQAPAAgJ7QduegA5AQABAAUJ7AYySQCTAAAAAA==.Stonecross:BAAALgAECgYJCgAAAA==.Stonehard:BAAALgAECgEJAQAAAA==.Stoneldo:BAAALgADCgEJAQAAAA==.Stonetotem:BAAALgAECgYJDAAAAA==.Stormbolt:BAABLgAECn9BAAILAAkJWhUmEwAlAgALAAkJWhUmEwAlAgAAAA==.Stormspirit:BAAALgADCgkJEAAAAA==.Striggen:BAABLgAECn8WAAMMAAYJtA8qyADfAAAMAAUJexEqyADfAAAbAAUJDwldNAB2AAAAAA==.',
Su='Succystrazsa:BAAALgADCgIJAgAAAA==.Sugarsham:BAAALgAECgcJEQAAAA==.Sulwen:BAACLgAFFH8UAAILAAgJRCLvAAA9AgALAAgJRCLvAAA9AgAuAAQKfyAAAgsACQmQJvwEAFEDAAsACQmQJvwEAFEDAAAA.Sumerset:BAAALgAECgMJBgAAAA==.Sunnydee:BAAALgAECgYJCwAAAA==.Supaflytnt:BAAALgAECgUJCAAAAA==.Sustia:BAABLgAECn8VAAIoAAgJ1wo/CwBPAQAoAAgJ1wo/CwBPAQAAAA==.',
Ta='Tacopie:BAAALgAECgQJBgAAAA==.Taera:BAABLgAECn8zAAIZAAgJiyENCQDqAgAZAAgJiyENCQDqAgAAAA==.Taika:BAAALgADCgkJDwAAAA==.Tailchaser:BAAALgADCgcJBwAAAA==.Talanazar:BAABLgAECn86AAQJAAkJFSAbBQD6AgAJAAkJFSAbBQD6AgAfAAYJgR2AFAChAQAkAAMJ0A7HJwCWAAAAAA==.Talavenn:BAABLgAECn8bAAINAAgJqhJqRwCYAQANAAgJqhJqRwCYAQAAAA==.Tallish:BAABLgAECn8fAAINAAgJbg33egA3AQANAAgJbg33egA3AQAAAA==.Tarage:BAAALgAECgIJAgAAAA==.Taterchip:BAABLgAECn8jAAMVAAYJ2Ri2NwBTAQAVAAYJhBi2NwBTAQAQAAIJvRa3NgCEAAAAAA==.Taylia:BAAALgAECgQJBgAAAA==.',
Te='Teaorix:BAAALgADCgQJBAAAAA==.Teds:BAAALgADCgUJBQAAAA==.Temporary:BAAALgADCgYJBgAAAA==.Tempus:BAAALgAECgYJEwAAAA==.Teradoxx:BAAALgAECgYJDgAAAA==.Teriko:BAABLgAECn89AAMRAAkJGx4kGgCWAgARAAkJGx4kGgCWAgADAAcJKgryKwDgAAAAAA==.Teviro:BAAALgAECgUJBgABLgAECgkJRgAWAEkhAA==.',
Th='Thanks:BAAALgAECgEJAQAAAA==.Thequixote:BAAALgADCgEJAQAAAA==.Therizino:BAAALgADCgQJBAAAAA==.Thrashy:BAAALgAECgQJCAAAAA==.Thrum:BAAALgAECgEJAQAAAA==.',
Ti='Tinkerballa:BAAALgAECgEJAQAAAA==.',
To='Toxictotes:BAAALgAECgIJBAAAAA==.',
Tw='Twiddleado:BAABLgAECn83AAITAAkJ7RQpNwAkAgATAAkJ7RQpNwAkAgAAAA==.Twinkie:BAAALgAECggJCAABLgAECggJIgANAAQjAA==.Twinkle:BAAALgADCgEJAQAAAA==.',
Ty='Tylor:BAAALgAECgYJDwAAAA==.',
['Tå']='Tåkete:BAAALgAECgYJCwAAAA==.',
Uk='Ukuindadookr:BAAALgADCgYJBgAAAA==.',
Um='Ume:BAAALgAECgEJAQABLgAECgMJBQAEAAAAAA==.',
Un='Unta:BAAALgAECgYJCQAAAA==.',
Va='Valaera:BAAALgAECgcJDwAAAA==.Valenora:BAABLgAECn8YAAIBAAgJzBq6BgDUAQABAAgJzBq6BgDUAQAAAA==.Valise:BAABLgAECn8dAAICAAYJrwR+GgDJAAACAAYJrwR+GgDJAAAAAA==.Varielle:BAAALgAECgYJCQAAAA==.Varuz:BAAALgAECgUJBwABLgAECgYJDwAEAAAAAA==.Varyz:BAAALgAECgUJBQABLgAECgYJDwAEAAAAAA==.Vaticamt:BAAALgAECgUJBQAAAA==.',
Ve='Vecxx:BAAALgADCgUJBQAAAA==.Velanie:BAAALgAECggJDAAAAA==.Velanise:BAAALgADCgMJAwAAAA==.Velight:BAAALgADCgEJAQAAAA==.Velinara:BAAALgAECgEJAQAAAA==.Velindroz:BAAALgAECgMJBgAAAA==.Veloras:BAAALgAECgEJAQAAAA==.Verene:BAABLgAECn8oAAIdAAkJEhY3HQBJAgAdAAkJEhY3HQBJAgAAAA==.Verinari:BAAALgAECgQJBAAAAA==.',
Vi='Vibes:BAAALgAECgkJBQAAAA==.Viperc:BAEALgADCgMJAwABLgAECgYJFQACAPsDAA==.Vipul:BAAALgAECgEJAQABLgAECgYJDgAEAAAAAA==.Viridria:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.Virridian:BAABLgAECn88AAISAAkJlyBhCQD6AgASAAkJlyBhCQD6AgAAAA==.Virrigosa:BAAALgADCgcJBwAAAA==.Vistia:BAAALgADCgEJAQAAAA==.',
Vl='Vlado:BAAALgAECgEJAQAAAA==.',
Vo='Vodalus:BAAALgADCgUJBQAAAA==.Voideria:BAAALgAECgQJBgAAAA==.Voolock:BAAALgADCggJCQAAAA==.',
Vy='Vyshana:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.',
Wa='Wallofshame:BAABLgAECn8lAAIiAAkJxh2bDACxAgAiAAkJxh2bDACxAgAAAA==.Walt:BAAALgADCgIJAgAAAA==.Warchef:BAAALgADCgYJCgABLgAECggJLwATADUgAA==.Warriorclaps:BAAALgADCggJDgAAAA==.Wartooth:BAABLgAECn8xAAMBAAgJfxxlAwBHAgABAAgJfxxlAwBHAgAPAAUJcBOthQAkAQAAAA==.Wassergott:BAAALgADCgIJAgAAAA==.',
We='Webicus:BAABLgAECn8hAAIQAAgJGxVbFgB8AQAQAAgJGxVbFgB8AQAAAA==.Weezzer:BAAALgADCgQJBAAAAA==.Wendee:BAABLgAECn8tAAMIAAkJgwG+QQDOAAAIAAkJgwG+QQDOAAAHAAUJdQTkSwCoAAAAAA==.',
Wh='Whitefóx:BAACLgAFFH8NAAIbAAQJBhMkBgAIAQAbAAQJBhMkBgAIAQAuAAQKfx0AAhsACQksGyAFAIwCABsACQksGyAFAIwCAAEuAAUUBQkZABMAqxwA.Whitley:BAABLgAECn8sAAMdAAkJ5B8ABgA9AwAdAAkJ5B8ABgA9AwAgAAYJBhQxFgA6AQAAAA==.',
Wi='Wijing:BAAALgAECgIJAgAAAA==.',
Wo='Wolololo:BAAALgAECgEJAQABLgAECgkJIQARAIIiAA==.Worldbreaker:BAAALgADCgEJAQAAAA==.',
['Wü']='Wülfsa:BAAALgAECgUJBQAAAA==.',
Xa='Xanthium:BAABLgAECn8dAAIIAAYJzwHXTQCNAAAIAAYJzwHXTQCNAAAAAA==.Xanzib:BAAALgADCgYJBgAAAA==.Xaphy:BAAALgAECgYJCwAAAA==.Xardots:BAABLgAECn8lAAIBAAgJohUxCgCDAQABAAgJohUxCgCDAQABLgAECgkJNAAEAAAAAA==.',
Xe='Xeetali:BAAALgADCgYJBgAAAA==.',
Xi='Xiareth:BAABLgAECn8xAAMkAAgJ7guKFQBiAQAkAAgJ7guKFQBiAQAfAAEJkAZWJQAsAAAAAA==.',
Xt='Xtronger:BAABLgAECn8gAAIFAAgJmRYkLQDgAQAFAAgJmRYkLQDgAQAAAA==.',
['Xá']='Xároth:BAAALgAECgkJNAAAAQ==.',
Ya='Yaddi:BAAALgAECgQJBQAAAA==.Yarrow:BAAALgADCgkJCQAAAA==.',
Ye='Yeeyee:BAAALgAECgkJEwAAAA==.',
Za='Zalik:BAAALgAECgMJAwAAAA==.',
Ze='Zeebo:BAAALgAECgcJEwAAAA==.Zest:BAABLgAECn8pAAMkAAkJ2BChDAD5AQAkAAkJ2BChDAD5AQAJAAIJkAj1bQBmAAAAAA==.',
Zm='Zmaryjane:BAAALgAECgIJBAAAAA==.',
Zo='Zorakfoghorn:BAAALgADCgIJAgAAAA==.Zorithic:BAAALgAECgQJAwAAAA==.Zorrak:BAAALgAECgQJBQAAAA==.',
Zu='Zulls:BAAALgAECgIJAgAAAA==.',
Zy='Zyde:BAAALgAECgYJDwAAAA==.',
['Zæ']='Zælys:BAAALgAECggJDAAAAA==.',
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
