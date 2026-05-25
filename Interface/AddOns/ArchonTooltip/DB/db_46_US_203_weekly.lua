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

local lookup = {'Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Unknown-Unknown','Druid-Restoration','Evoker-Augmentation','DeathKnight-Frost','Priest-Shadow','Druid-Balance','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Warrior-Protection','DeathKnight-Unholy','Hunter-BeastMastery','Mage-Frost','DemonHunter-Vengeance','Warrior-Fury','Hunter-Survival','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Priest-Holy','Shaman-Elemental','Paladin-Protection','Mage-Fire','Shaman-Restoration','Rogue-Subtlety','Evoker-Devastation','Shaman-Enhancement','Druid-Guardian','Paladin-Holy','Priest-Discipline','Druid-Feral','Evoker-Preservation','Mage-Arcane','Rogue-Assassination','Warrior-Arms',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Absens:BAABLgAECn8+AAMBAAkJwhLkCACOAQABAAkJhw/kCACOAQACAAgJ0hAwCgCIAQAAAA==.',
Ad='Adorian:BAAALgAECgcJBwABLgAFFAQJDAADAKkfAA==.Adwillon:BAAALgADCgQJBQABLgAECgYJDgAEAAAAAA==.',
Ae='Aedoril:BAAALgADCgEJAQAAAA==.Aelyss:BAAALgADCgQJBAAAAA==.Aerosse:BAAALgADCgEJAQAAAA==.',
Af='Aforceofone:BAAALgAECgQJCwAAAA==.',
Ai='Airdreanna:BAAALgADCgQJBAAAAA==.',
Ak='Akama:BAAALgAECgYJCwABLgAFFAYJGwAFABgdAA==.',
Al='Alivanllan:BAAALgAECgIJAgAAAA==.Alteisen:BAAALgAECgUJBQAAAA==.',
Am='Ambitious:BAAALgAECgMJCgAAAA==.Amerlinn:BAAALgAECgYJDAAAAA==.',
An='Anamuht:BAAALgAECgkJEgABLgAECgkJOQAGABUgAA==.Annaday:BAABLgAECn8gAAIDAAgJtg2eIQAXAQADAAgJtg2eIQAXAQAAAA==.Antiock:BAACLgAFFH8MAAIDAAQJqR/NDABWAQADAAQJqR/NDABWAQAuAAQKfy8AAwMACQn8I/cCAP0CAAMACQn8I/cCAP0CAAcABwnRHIsHANkBAAAA.Anyaesthesia:BAAALgADCgYJBgAAAA==.Anyamonka:BAAALgAECgYJEgAAAA==.',
Ap='Apocalich:BAAALgAECgUJBQAAAA==.',
Aq='Aquenia:BAAALgADCggJDAAAAA==.',
Ar='Aralaith:BAABLgAECn8jAAIIAAgJYiVRBgDQAgAIAAgJYiVRBgDQAgABLgAFFAgJFAAJAEQiAA==.Argonaut:BAAALgAECgIJAgAAAA==.Argul:BAAALgAECgIJAgAAAA==.Ariea:BAAALgADCgYJBgAAAA==.Artoriá:BAAALgAECgEJAQAAAA==.Artto:BAABLgAECn8jAAIKAAYJPxF6oAAVAQAKAAYJPxF6oAAVAQAAAA==.',
As='Asevenhex:BAAALgAECgEJAQAAAA==.Ashbrínger:BAABLgAECn9DAAIKAAkJwyUWAgBtAwAKAAkJwyUWAgBtAwAAAA==.Association:BAAALgADCgQJBAAAAA==.Astrum:BAAALgAECgEJAgAAAA==.Asunã:BAAALgAECgIJAgAAAA==.',
Au='Aurah:BAAALgAECgIJBAAAAA==.',
Av='Averax:BAABLgAECn8pAAMLAAgJaBu+IQAtAgALAAgJaBu+IQAtAgAMAAEJvQ2JbgA3AAAAAA==.Avyrax:BAAALgADCgcJDQABLgAECggJKQALAGgbAA==.',
Ay='Aybara:BAAALgADCgQJBAAAAA==.Aylakaye:BAAALgADCgMJAwAAAA==.Ayraena:BAABLgAECn8ZAAMJAAgJHQh1MwAbAQAJAAgJHQh1MwAbAQAFAAQJEgFVsgA+AAAAAA==.',
Az='Azkariel:BAAALgADCgQJBAAAAA==.Azyrieth:BAAALgADCgEJAQAAAA==.Azzathoth:BAAALgADCgcJDAAAAA==.',
Ba='Babyshoes:BAAALgAECgEJAQAAAA==.Bakedtofu:BAABLgAECn8UAAMBAAYJ7wc9RwCZAAANAAYJ7wdeugC5AAABAAQJGQQ9RwCZAAAAAA==.Bashine:BAABLgAECn8VAAIOAAYJVxlZGACTAQAOAAYJVxlZGACTAQABLgAFFAUJFwAPAB4hAA==.Baylohn:BAABLgAECn8cAAIQAAcJxhfqUgB8AQAQAAcJxhfqUgB8AQAAAA==.',
Be='Bearwrestler:BAABLgAECn8aAAIRAAgJ1Bc0UQDMAQARAAgJ1Bc0UQDMAQABLgAFFAQJDwADAJAgAA==.Beefynugs:BAAALgAECgkJAgAAAA==.',
Bi='Bier:BAAALgAECgQJCAAAAA==.Bigrig:BAAALgAECgkJEgAAAA==.Bitterman:BAABLgAECn8mAAMNAAkJdAxQTgCZAQANAAkJaQxQTgCZAQABAAEJww/ZcAA1AAAAAA==.',
Bj='Bjornvalion:BAAALgADCgQJBAAAAA==.',
Bl='Blackmage:BAAALgAECgEJAQAAAA==.Bladed:BAABLgAECn8bAAQLAAcJKxVyVgBgAQALAAcJqxJyVgBgAQASAAUJuRfhEgDzAAAMAAEJAAB8aQAAAAAAAA==.Blinx:BAAALgADCgQJBAAAAA==.Bloodymess:BAAALgAECgYJCwAAAA==.',
Bo='Boogies:BAAALgADCgQJBwAAAA==.Bovinedivine:BAAALgAECgYJBgABLgAECggJMQAEAAAAAA==.',
Bu='Buffie:BAABLgAECn8ZAAIKAAgJGhoeWADaAQAKAAgJGhoeWADaAQAAAA==.Bullwyf:BAAALgADCgMJAwAAAA==.Bumblbeetuna:BAAALgAECgEJAQAAAA==.',
['Bá']='Bád:BAAALgADCggJDgABLgADCgkJCQAEAAAAAA==.',
Ca='Calduu:BAAALgAECgMJAwAAAA==.Caledia:BAAALgAECgYJEQAAAA==.Callana:BAAALgADCgMJBQAAAA==.Camedra:BAABLgAECn87AAIFAAkJiiS2AQCtAwAFAAkJiiS2AQCtAwAAAA==.Carinancey:BAAALgAECgEJAQAAAA==.Carperoni:BAAALgADCgcJBwAAAA==.Casseous:BAAALgADCgUJBwAAAA==.Catamynyia:BAABLgAECn8fAAIQAAgJJAyMVwBvAQAQAAgJJAyMVwBvAQAAAA==.Caylaetal:BAAALgAECgEJAQAAAA==.',
Cc='Cchaos:BAAALgAECgIJBgAAAA==.',
Ce='Celaborn:BAABLgAECn8bAAITAAgJhBy2IQC+AQATAAgJhBy2IQC+AQAAAA==.',
Ch='Chazaraz:BAABLgAECn8yAAMUAAkJfgyJFADmAQAUAAkJuguJFADmAQAQAAgJEggAcAAyAQAAAA==.Chevy:BAAALgAECgEJAwAAAA==.Chifreak:BAAALgAFFAIJAgABLgAECgcJIAALAPoiAA==.Chillmourne:BAAALgAECgcJEwABLgAECggJFgABAJIIAA==.Chimaira:BAAALgADCgIJAgAAAA==.Chucknoris:BAAALgADCgcJCQAAAA==.Chugbuggins:BAAALgAECgYJDgAAAA==.',
Ci='Cindria:BAABLgAECn8lAAIRAAgJuBAAZACZAQARAAgJuBAAZACZAQAAAA==.',
Cl='Clerks:BAAALgADCgMJAwAAAA==.Cliffgate:BAAALgADCgMJAwAAAA==.',
Co='Conduction:BAAALgAECgUJCAAAAA==.Corenthia:BAAALgAECgQJBAAAAA==.',
Cp='Cptbonez:BAAALgAECgYJEgABLgAECgkJKQAVAEYTAA==.',
Cr='Crankadin:BAAALgADCgUJBQABLgAECgIJBAAEAAAAAA==.Crankchi:BAAALgADCgYJBwABLgAECgIJBAAEAAAAAA==.Crazz:BAAALgADCgEJAQAAAA==.Crewz:BAAALgADCgQJBAAAAA==.Crooky:BAAALgADCgcJBwABLgAFFAUJGQAPALwcAA==.Crucifiiks:BAAALgAECgQJBQAAAA==.Cruciö:BAAALgAECgEJAQAAAA==.Crànk:BAAALgAECgIJBAAAAA==.',
Cu='Curveball:BAAALgAECgQJBgABLgAECgkJJgANAHQMAA==.',
Da='Dalearnhardt:BAAALgADCgcJDgABLgAECgcJEgAEAAAAAA==.Damerlin:BAAALgAECgcJDQAAAA==.Darkstär:BAABLgAECn87AAIDAAkJBx3bBgCNAgADAAkJBx3bBgCNAgAAAA==.Darkwood:BAAALgADCgEJAgAAAA==.Dauc:BAAALgADCgEJAQAAAA==.',
De='Deacon:BAABLgAECn8pAAQVAAgJ+wZXRQDJAAAVAAYJnwNXRQDJAAAWAAUJmgqmSwCqAAAXAAQJNgQiVQB7AAAAAA==.Deadmantooth:BAAALgADCgYJBgABLgAECggJKQABANwZAA==.Deardren:BAAALgAECgUJBQAAAA==.Deathknights:BAAALgAFFAEJAQAAAA==.Deathtrol:BAAALgAECggJCAAAAA==.Deeanne:BAAALgAECgQJBwAAAA==.Deepdeuce:BAAALgAECgQJBAAAAA==.Deepfriar:BAABLgAECn87AAMYAAkJEiN4BQAFAwAYAAkJEiN4BQAFAwAIAAcJMRTYIwCCAQAAAA==.Deidra:BAAALgADCgMJAwAAAA==.Demonhunts:BAABLgAFFH8HAAILAAQJfwgOQAD9AAALAAQJfwgOQAD9AAAAAA==.Demonmore:BAABLgAECn8jAAMMAAgJxAvWIAA2AQAMAAgJ2ArWIAA2AQASAAUJWQpaGwCYAAAAAA==.Derailed:BAAALgAECgQJBwAAAA==.Dethwing:BAAALgADCggJDAAAAA==.Devilfrost:BAAALgAECgEJAQABLgAECgMJBgAEAAAAAA==.Dewshine:BAAALgAECgYJCwAAAA==.',
Dh='Dhampir:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Dhgeek:BAAALgAECgIJAwAAAA==.',
Di='Diablognomis:BAAALgAECgQJBwAAAA==.Dingô:BAAALgADCggJGAAAAA==.Dirtman:BAABLgAECn8kAAIZAAgJKxnHHwC4AQAZAAgJKxnHHwC4AQAAAA==.',
Dk='Dkrise:BAAALgAECgMJAwABLgAECggJJAAGAFcLAA==.',
Dn='Dneoh:BAAALgAECgkJCAABLgAFFAMJCgAJAOciAA==.',
Do='Donald:BAAALgADCgQJBAAAAA==.Donny:BAABLgAECn8gAAMKAAgJMB2fKQA5AgAKAAgJMB2fKQA5AgAaAAEJWw+FRAAsAAAAAA==.Doodyshamala:BAAALgAECgIJAwAAAA==.Dooky:BAAALgAECgEJAQABLgAFFAUJGQAPALwcAA==.Doozey:BAACLgAFFH8KAAILAAQJNBUCLgAxAQALAAQJNBUCLgAxAQAuAAQKfyYAAwsACQlrHogfADoCAAsACAl4IIgfADoCABIAAQkSEHwnAEMAAAAA.Dorigis:BAAALgADCgkJMAABLgAECgkJHAAOAJAgAA==.Dotdotdotded:BAABLgAECn8WAAINAAgJuAWugAAjAQANAAgJuAWugAAjAQAAAA==.',
Dr='Drewdog:BAABLgAECn8pAAMQAAYJjheBZQBLAQAQAAYJeBeBZQBLAQAUAAYJKQzyKwAgAQAAAA==.Droid:BAAALgAECgEJAgAAAA==.Drunkgerardo:BAAALgAECgQJBQAAAA==.Drunkzen:BAAALgAECgUJBQAAAA==.Druyesil:BAAALgAECgEJAgAAAA==.',
Du='Dubes:BAABLgAECn84AAIRAAkJdhdgKgBUAgARAAkJdhdgKgBUAgAAAA==.',
['Dá']='Dárkthorn:BAAALgAECgIJBAAAAA==.',
['Dö']='Dökkálfar:BAAALgAECgEJAQAAAA==.',
Ea='Easybreezin:BAAALgAECgUJDAAAAA==.',
Ei='Eirote:BAABLgAECn86AAIbAAkJDRobAQCQAgAbAAkJDRobAQCQAgAAAA==.',
El='Elarris:BAAALgADCgcJCAAAAA==.Eldari:BAABLgAECn8YAAIJAAgJ2hsDFgD2AQAJAAgJ2hsDFgD2AQAAAA==.Elem:BAACLgAFFH8PAAIcAAYJUwiQFQBwAQAcAAYJUwiQFQBwAQAuAAQKfyMAAhwACAmcIFMYAFMCABwACAmcIFMYAFMCAAAA.Elm:BAAALgAECgYJEAAAAA==.Elyssaena:BAAALgAECgYJEAAAAA==.',
Em='Emiliachan:BAAALgAECgcJCwAAAA==.',
En='Enzojr:BAACLgAFFH8GAAIdAAQJZRllDwBdAQAdAAQJZRllDwBdAQAuAAQKfzoAAh0ACQm3I9ADAOsCAB0ACQm3I9ADAOsCAAAA.',
Ep='Ephixa:BAAALgAECgYJDwAAAA==.',
Er='Eridanos:BAAALgADCgYJBgAAAA==.Erisiel:BAAALgAECgEJAQAAAA==.Eruelle:BAACLgAFFH8GAAILAAQJNyEHGwCDAQALAAQJNyEHGwCDAQAuAAQKfxcAAgsACQlvIo0EACwDAAsACQlvIo0EACwDAAEuAAUUCAkUAAkARCIA.',
Ev='Evoke:BAABLgAECn8fAAMGAAgJgyF3CgDOAgAGAAgJdB93CgDOAgAeAAYJZyBaDQAEAgAAAA==.',
Ey='Eye:BAACLgAFFH8IAAIfAAMJBiEqBgAnAQAfAAMJBiEqBgAnAQAuAAQKfyAAAx8ACQnRIEcFAGUCAB8ACQnRIEcFAGUCABkAAQmZDN2PACgAAAAA.',
['Eí']='Eís:BAAALgADCgYJCwAAAA==.',
Fa='Faeira:BAAALgAECgcJCQAAAA==.Faloril:BAAALgAECgIJAwAAAA==.Falsara:BAAALgAECgQJBAAAAA==.Faranth:BAABLgAECn85AAIGAAkJsx4vBwDPAgAGAAkJsx4vBwDPAgAAAA==.Faronyr:BAAALgAECgEJAQAAAA==.',
Fe='Felboi:BAAALgAECgUJDgAAAA==.Felorc:BAAALgAECgIJAwAAAA==.Felynne:BAAALgAECgcJDgAAAA==.Fenrík:BAAALgADCgIJAgAAAA==.Feo:BAABLgAECn8ZAAILAAgJnxdyOwC4AQALAAgJnxdyOwC4AQAAAA==.Ferum:BAABLgAECn8/AAMFAAkJ/iKQAwByAwAFAAkJ/iKQAwByAwAJAAYJuRAONgAMAQAAAA==.',
Fi='Fionnan:BAABLgAECn80AAIgAAkJcgg2IQAAAQAgAAkJcgg2IQAAAQABLgAECgkJOwAcAEoOAA==.',
Fo='Forest:BAACLgAFFH8MAAQJAAQJpxFUGQAjAQAJAAQJpxFUGQAjAQAFAAIJZwaMTQBqAAAgAAIJtggWHQBgAAAuAAQKfysAAwkACQkCHCkNAMYCAAkACQkCHCkNAMYCAAUAAwn3G/hhAO4AAAAA.',
Fr='Fretless:BAAALgADCgYJCgAAAA==.Frixley:BAAALgAECggJCQAAAA==.Friérén:BAAALgAECgEJAQAAAA==.Frostedrayne:BAAALgADCgUJBQAAAA==.Frostthrower:BAAALgAECgEJAgAAAA==.Fryeguy:BAAALgAECggJEwAAAA==.',
Fu='Funkysoup:BAAALgADCgYJBgAAAA==.',
Fy='Fyodor:BAAALgAECgIJBQAAAA==.',
['Fè']='Fèresha:BAAALgAECgkJEgAAAA==.',
Ga='Gallium:BAABLgAECn8aAAIhAAkJnBZ+FABEAgAhAAkJnBZ+FABEAgAAAA==.Gazerbeam:BAAALgAECgYJDwAAAA==.',
Ge='Geelock:BAAALgADCggJFgAAAA==.Gehena:BAAALgAFFAIJAgABLgAFFAIJAwAEAAAAAQ==.Gemsareyum:BAAALgAECgYJDgABLgAFFAUJMgAQAGolAA==.Gesht:BAABLgAECn8YAAIKAAgJSg58gwBHAQAKAAgJSg58gwBHAQAAAA==.',
Gh='Ghostfreak:BAAALgADCgYJBgAAAA==.',
Gi='Gidgetz:BAAALgADCgMJAwAAAA==.',
Gl='Glamourkills:BAAALgADCgcJDQAAAA==.',
Go='Goldenbell:BAAALgAECgUJBQAAAA==.Goof:BAABLgAECn82AAIhAAkJ+A6EMwCvAQAhAAkJ+A6EMwCvAQAAAA==.Goontas:BAAALgAECgMJBAAAAA==.',
Gr='Grimsheèper:BAAALgAECgMJBAAAAA==.Grish:BAAALgAECgYJEwAAAA==.Griz:BAAALgAECgQJCAAAAA==.Grollnar:BAAALgAECgEJAQABLgAECgkJDwAEAAAAAA==.Grossevache:BAAALgAECgYJEAAAAA==.Gròws:BAAALgAECgkJBwAAAA==.',
Ha='Haddor:BAABLgAECn8jAAIaAAgJphmHCQAIAgAaAAgJphmHCQAIAgAAAA==.Haelexi:BAAALgADCgcJDQAAAA==.Halujoxar:BAAALgADCgcJDgABLgAECggJMQAEAAAAAA==.Hamonkulous:BAAALgADCgcJCAAAAA==.Hankerin:BAAALgADCgcJCAAAAA==.Harandar:BAAALgAECgEJAQAAAA==.Harpomage:BAAALgADCgcJCQAAAA==.Hatcher:BAAALgAECgEJAQAAAA==.Haunter:BAABLgAECn8fAAMDAAgJwyGaGwBNAQAPAAUJpiJmYwDJAQADAAUJlR6aGwBNAQAAAA==.Hayleigh:BAACLgAFFH8bAAIFAAYJGB2rBwAlAgAFAAYJGB2rBwAlAgAuAAQKfzEAAgUACQmEIkYEAGADAAUACQmEIkYEAGADAAAA.',
He='Heimdallr:BAAALgAECgEJAQAAAA==.Heisenborg:BAAALgAECgUJBQAAAA==.Hellbreezy:BAAALgAECgkJEAAAAA==.Helldin:BAABLgAECn8nAAIKAAYJ3hWPhgBBAQAKAAYJ3hWPhgBBAQAAAA==.Hellenfeller:BAABLgAECn8cAAIMAAYJhRSZIAA4AQAMAAYJhRSZIAA4AQAAAA==.',
Hi='Hilitepriest:BAABLgAECn8bAAMiAAgJ0Rk7EQAzAgAiAAgJQBk7EQAzAgAYAAIJ1BZvaACLAAAAAA==.Hittomi:BAAALgAECgYJBgAAAA==.',
Ho='Holific:BAABLgAECn87AAIKAAkJARfBJwBCAgAKAAkJARfBJwBCAgAAAA==.Honeychild:BAAALgAECgYJCgAAAA==.Hotrodranger:BAAALgAECgcJEgAAAA==.Hottub:BAAALgAECgEJAQAAAA==.',
Hu='Huckleberry:BAAALgADCggJDQAAAA==.',
Hv='Hvac:BAABLgAECn8vAAIRAAkJywy5VQC+AQARAAkJywy5VQC+AQAAAA==.',
Ic='Iceovo:BAAALgADCgEJAQAAAA==.Icycritties:BAABLgAECn8VAAIRAAYJhQ0lvQBoAQARAAYJhQ0lvQBoAQAAAA==.',
Id='Idovoodew:BAAALgADCgUJCAAAAA==.',
Ih='Iheals:BAAALgAECgMJCQAAAA==.',
Im='Imjustadruid:BAAALgADCgUJBAAAAA==.Immortal:BAABLgAECn8YAAIPAAkJeBhCIQBgAgAPAAkJeBhCIQBgAgAAAA==.Implants:BAAALgADCggJCQAAAA==.',
In='Incarnate:BAAALgAECgcJDQAAAA==.Incarnated:BAACLgAFFH8MAAIPAAMJ8iDlVQAiAQAPAAMJ8iDlVQAiAQAuAAQKfy4AAg8ACQl3I1EJAAkDAA8ACQl3I1EJAAkDAAAA.Inflammation:BAAALgADCgcJDwABLgAECgUJCAAEAAAAAA==.',
Ir='Irocc:BAAALgAECgMJBwAAAA==.',
Is='Ishankyou:BAAALgAECgEJAQAAAA==.Istara:BAAALgADCgcJDQABLgAFFAYJFgARANcgAA==.',
Iu='Iu:BAAALgADCgEJAgAAAA==.',
Ja='Jackdowe:BAAALgAECgQJBAAAAA==.Jackfash:BAAALgADCgUJBQAAAA==.Jadecross:BAABLgAECn8VAAIXAAcJyhWKKACZAQAXAAcJyhWKKACZAQAAAA==.Jalenhunter:BAAALgADCgUJCAAAAA==.',
Je='Jedith:BAAALgAECgQJBAAAAA==.Jerambae:BAAALgAECgYJEgAAAA==.Jerryatric:BAAALgAECgkJEgAAAA==.',
Jo='Joelah:BAAALgAECgcJDwAAAA==.Joshua:BAAALgAECgYJDAAAAA==.',
Ju='Justincasê:BAAALgADCgcJEQAAAA==.',
['Jâ']='Jây:BAAALgADCgQJBAAAAA==.',
Ka='Kalfeen:BAABLgAECn8ZAAMgAAYJwB0bEACqAQAgAAYJwB0bEACqAQAjAAEJ+wYVRAAoAAAAAA==.Kallikan:BAABLgAECn8kAAIgAAgJzBSQEgCKAQAgAAgJzBSQEgCKAQAAAA==.Kamidk:BAABLgAFFH8GAAIPAAQJ1g2/kACrAAAPAAQJ1g2/kACrAAABLgAFFAQJCQALAAMXAA==.Kanmojo:BAAALgADCgQJBQAAAA==.Kashume:BAABLgAECn8bAAIfAAkJngKNFwAIAQAfAAkJngKNFwAIAQAAAA==.Kasteen:BAAALgAECgQJCgAAAA==.Kazon:BAAALgADCgcJCgABLgAFFAQJDAADAKkfAA==.Kaøs:BAAALgAECgEJAQAAAA==.',
Kd='Kdoggparker:BAAALgAECgIJAwAAAA==.',
Ke='Kementari:BAAALgAECgQJBQAAAA==.Kenzaki:BAACLgAFFH8QAAIKAAUJmQrIOQAYAQAKAAUJmQrIOQAYAQAuAAQKfzQAAgoACAmFGoJHANABAAoACAmFGoJHANABAAAA.',
Kh='Khaosreborn:BAAALgAECgUJEAAAAA==.Khaotic:BAAALgADCgMJAwABLgADCgQJBAAEAAAAAA==.',
Ki='Kiiren:BAAALgAECgEJAQABLgAECgYJGQAgAMAdAA==.Kilaaz:BAAALgAECgUJEQAAAA==.Kilaz:BAAALgADCgUJBQAAAA==.',
Kn='Knuts:BAACLgAFFH8HAAIVAAQJBRbwGAAvAQAVAAQJBRbwGAAvAQAuAAQKfxYAAhUACQlUGOwZALcBABUACQlUGOwZALcBAAAA.',
Ko='Korius:BAAALgAECgUJBQAAAA==.Ková:BAAALgAECggJEAAAAA==.',
Kr='Krutesiq:BAAALgADCgkJCQAAAA==.',
Ku='Kuani:BAAALgAECgYJBwABLgAECggJMQAXAEohAA==.Kullman:BAAALgADCgYJCgAAAA==.Kungfupapa:BAAALgAECgEJAQAAAA==.Kungfurry:BAAALgAECgUJCAAAAA==.Kurobozu:BAAALgAECgQJBAABLgAECgkJOQAGABUgAA==.Kutherrek:BAAALgAECgEJAQAAAA==.Kuubar:BAABLgAECn8hAAIHAAgJ5RNxCwB7AQAHAAgJ5RNxCwB7AQAAAA==.',
Ky='Kyian:BAAALgAECgMJAwAAAA==.',
La='Ladaeze:BAAALgADCgIJAgAAAA==.Ladiesnutz:BAABLgAECn8XAAQkAAgJKyCIFABfAQAkAAQJ4R+IFABfAQAeAAUJThszCwBDAQAGAAUJ/hSUMQA7AQAAAA==.Law:BAAALgAECgEJAQABLgAFFAYJGwAFABgdAA==.Laz:BAAALgADCgMJAwAAAA==.Lazerous:BAAALgADCgYJBgAAAA==.',
Le='Leafá:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.Lealoo:BAABLgAECn8kAAIKAAcJYRYDWwCdAQAKAAcJYRYDWwCdAQABLgAECggJKwAMAKcRAA==.Leghorn:BAAALgADCgIJAgABLgAECgYJGQAgAMAdAA==.Legolard:BAABLgAECn8cAAIOAAkJkCA3BADHAgAOAAkJkCA3BADHAgAAAA==.Lever:BAAALgADCggJCQAAAA==.',
Li='Liath:BAAALgAECgQJCAAAAA==.Lightsky:BAAALgADCgIJAQAAAA==.Lildèbbíe:BAABLgAECn8oAAIRAAgJMg3rZgCSAQARAAgJMg3rZgCSAQAAAA==.Lilspoon:BAAALgADCgMJAwAAAA==.Liltrapstarx:BAAALgAECgQJCAAAAA==.Linddori:BAABLgAECn8mAAIKAAgJphv9MQAXAgAKAAgJphv9MQAXAgAAAA==.Lindmajik:BAAALgAECgQJBgAAAA==.Liori:BAAALgAECgUJDAAAAA==.Lirillïa:BAAALgADCggJDQABLgAECggJJgAKAKYbAA==.',
Lo='Lodestone:BAAALgADCgMJAwAAAA==.Loena:BAABLgAECn8iAAIKAAkJXiM8BwAbAwAKAAkJXiM8BwAbAwAAAA==.Lokk:BAAALgAECgQJBAABLgAECgYJDwAEAAAAAA==.',
Lu='Lunabug:BAACLgAFFH8HAAIWAAMJowvSGwDGAAAWAAMJowvSGwDGAAAuAAQKfygAAhYACAl8Hb8WANcBABYACAl8Hb8WANcBAAAA.Lupinos:BAAALgADCgYJCAAAAA==.',
Ly='Lyadra:BAABLgAECn8kAAIYAAkJDBn5GADdAQAYAAkJDBn5GADdAQAAAA==.Lyandre:BAACLgAFFH8NAAMYAAUJhAp9DQA9AQAYAAUJhAp9DQA9AQAiAAQJSQFYJwDFAAAuAAQKfx4AAxgACAlGE4MWACgCABgACAlGE4MWACgCACIAAQnAEENgADgAAAAA.Lydra:BAAALgAECgUJBQAAAA==.Lynna:BAAALgADCgQJBAAAAA==.Lyntoo:BAAALgAECgIJAQAAAA==.Lyntu:BAAALgAECgEJAQAAAA==.',
['Lú']='Lúffy:BAAALgAECgcJBwABLgAECgcJIAALAPoiAA==.',
Ma='Madan:BAABLgAECn8YAAIPAAYJVwWLxgDJAAAPAAYJVwWLxgDJAAAAAA==.Malasminna:BAAALgADCgYJBgAAAA==.Malehorelock:BAAALgAECgEJAQABLgAECggJJgAQACMhAA==.Malicioun:BAAALgADCgEJAQAAAA==.Malkariss:BAABLgAECn8pAAMRAAgJByBoHQCRAgARAAgJByBoHQCRAgAlAAEJ5AjgHAA5AAAAAA==.Mammadruid:BAABLgAECn8qAAMgAAgJ8Qu6HwALAQAgAAgJ8Qu6HwALAQAFAAYJpwuSZwDdAAAAAA==.Maralen:BAAALgADCgcJCQAAAA==.Marann:BAAALgAECgEJAQAAAA==.Matadør:BAAALgAECgcJDAAAAA==.Mathwhiz:BAAALgAECgYJDwABLgAECgkJJgANAHQMAA==.Mauldis:BAABLgAECn8oAAIZAAgJxgpMNwAqAQAZAAgJxgpMNwAqAQAAAA==.Mavgard:BAAALgAECgIJAgAAAA==.Mavgards:BAAALgADCgMJAwABLgAECgIJAgAEAAAAAA==.Maxrebo:BAABLgAECn8bAAIVAAgJoBv7DwAgAgAVAAgJoBv7DwAgAgAAAA==.',
Me='Meatwàd:BAAALgAECgYJCAAAAA==.Mekanzi:BAAALgAECgQJBwAAAA==.Meliõdas:BAAALgAECgUJEQAAAA==.Merebels:BAAALgAECgQJBwABLgAECgYJCwAEAAAAAA==.Merkodisco:BAAALgAECgIJAgAAAA==.',
Mi='Miaka:BAABLgAECn8yAAICAAkJ1xmkAgB4AgACAAkJ1xmkAgB4AgAAAA==.Miakah:BAAALgAECgUJBQAAAA==.Midwest:BAAALgADCgQJBAAAAA==.Minirook:BAAALgADCgEJAQABLgAFFAUJGQAPALwcAA==.Misfire:BAABLgAECn8sAAIQAAkJJBKKLwD0AQAQAAkJJBKKLwD0AQAAAA==.Mistbusters:BAAALgADCgYJBgAAAA==.Mithra:BAAALgAECgEJAQAAAA==.Mithygos:BAABLgAECn8UAAIGAAYJKQRhWgCfAAAGAAYJKQRhWgCfAAAAAA==.Mito:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.',
Mo='Moar:BAAALgAECgEJAgAAAA==.Moghroth:BAABLgAECn8xAAMJAAgJjgvoLABBAQAJAAgJhAvoLABBAQAgAAEJQwtAWgAkAAAAAA==.Molykote:BAAALgAECgMJBQAAAA==.Monks:BAAALgAFFAIJAgAAAA==.Morgiana:BAAALgAECgEJAQAAAA==.',
My='Myhiknee:BAAALgADCgUJCAAAAA==.Myriana:BAAALgAECgQJBwAAAA==.Mystyle:BAAALgADCgcJBwAAAA==.',
['Má']='Mágnus:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâsterdon:BAAALgAECgYJDwAAAA==.',
Na='Nahryn:BAABLgAECn8pAAIFAAgJ8R6MDwC4AgAFAAgJ8R6MDwC4AgAAAA==.Najamei:BAAALgADCgUJBQAAAA==.Najanira:BAAALgADCgYJBgAAAA==.Narya:BAAALgAECgIJAwAAAA==.',
Ne='Nella:BAAALgAECgYJCQABLgAECggJMQAXAEohAA==.Nerbert:BAAALgADCgYJBgABLgAECggJJQAGAI8VAA==.Neretsym:BAABLgAECn8oAAIQAAkJOyD4EAChAgAQAAkJOyD4EAChAgAAAA==.Nevercumdin:BAAALgADCgEJAwAAAA==.',
Ni='Nibbzz:BAACLgAFFH8FAAIiAAMJvQTmJwC/AAAiAAMJvQTmJwC/AAAuAAQKfx0AAiIACQl1FMgZANUBACIACQl1FMgZANUBAAAA.Nineva:BAABLgAECn8eAAIFAAcJ6gP/cgC8AAAFAAcJ6gP/cgC8AAAAAA==.',
No='Nobas:BAABLgAECn87AAMJAAkJignRJgBoAQAJAAkJignRJgBoAQAFAAEJ6wJ05AAhAAAAAA==.',
Nu='Nugs:BAAALgAECgkJBQAAAA==.',
On='Onlyfeet:BAAALgAECgMJBgAAAA==.',
Op='Oppgjør:BAABLgAECn8UAAIhAAkJERdCDgCKAgAhAAkJERdCDgCKAgAAAA==.',
Or='Oreeree:BAAALgAECgYJBwAAAA==.Orenge:BAAALgAECgQJCAAAAA==.Orkus:BAAALgADCgkJCwAAAA==.Ormr:BAABLgAECn8lAAIGAAgJjxXqIwCaAQAGAAgJjxXqIwCaAQAAAA==.Orpsa:BAAALgADCgYJBgAAAA==.',
Os='Osteo:BAABLgAECn8rAAQCAAgJwgbHEgACAQANAAgJXgTkjgAHAQACAAcJnwbHEgACAQABAAcJCALAPwC1AAAAAA==.',
Ou='Ouron:BAABLgAECn8mAAMcAAgJwBVPLgDOAQAcAAcJUxZPLgDOAQAZAAYJtQxFZACyAAAAAA==.',
Pa='Papashrimps:BAACLgAFFH8VAAIRAAUJBRmKPQBIAQARAAUJBRmKPQBIAQAuAAQKfzkAAhEACQl1InULAAcDABEACQl1InULAAcDAAAA.',
Pe='Perash:BAAALgAECgEJAQAAAA==.',
Ph='Phrazes:BAAALgAECgQJBAAAAA==.',
Pi='Pikyu:BAAALgADCgEJAQAAAA==.',
Pl='Placeholder:BAABLgAECn8oAAIaAAgJRhoZCgD8AQAaAAgJRhoZCgD8AQAAAA==.Plaguestingr:BAABLgAECn89AAIQAAkJDSTnBAAmAwAQAAkJDSTnBAAmAwAAAA==.',
Po='Pontifex:BAABLgAECn8fAAIYAAgJpBfOFQD9AQAYAAgJpBfOFQD9AQAAAA==.Portandmorph:BAABLgAECn8fAAIRAAkJgRJyPQAJAgARAAkJgRJyPQAJAgAAAA==.Potlock:BAAALgAECgQJCAAAAA==.',
Pr='Proey:BAABLgAECn86AAMIAAkJuhcaDgBQAgAIAAkJuhcaDgBQAgAiAAUJJhN7NAAVAQAAAA==.Prone:BAABLgAECn87AAIcAAkJSg4cMwC3AQAcAAkJSg4cMwC3AQAAAA==.',
Ps='Psychokiller:BAAALgADCgYJBgAAAA==.',
Pu='Puf:BAAALgAECgMJBwAAAA==.Pumpidan:BAAALgAECgIJBQAAAA==.',
Py='Pyrelyn:BAAALgADCgEJAQAAAA==.',
Qr='Qròw:BAAALgADCgMJAwAAAA==.',
Qu='Quinnifred:BAAALgAECgMJAgAAAA==.',
Ra='Raakotah:BAABLgAECn9DAAIJAAkJYCRsAgA6AwAJAAkJYCRsAgA6AwAAAA==.Raelo:BAABLgAECn8lAAIfAAgJlAz0EABmAQAfAAgJlAz0EABmAQAAAA==.Raiseurmug:BAABLgAECn8pAAIVAAkJRhO4FADpAQAVAAkJRhO4FADpAQAAAA==.Rakash:BAACLgAFFH8MAAIPAAQJlBkHNgBXAQAPAAQJlBkHNgBXAQAuAAQKfycAAg8ACQmTIK0gAL8CAA8ACQmTIK0gAL8CAAAA.Rarg:BAAALgAECgYJBwABLgAFFAYJDwAOACsaAA==.Rascaldragon:BAAALgAECgQJBQAAAA==.Ravenlark:BAABLgAECn8YAAINAAgJzQb/fQAoAQANAAgJzQb/fQAoAQAAAA==.Ravia:BAABLgAECn8gAAMLAAcJ+iLgIAAyAgALAAcJMyLgIAAyAgASAAUJUiE4CQDdAQAAAA==.Razuki:BAAALgAECgYJEwABLgAECgkJNAAhAIsiAA==.',
Re='Reddale:BAAALgADCgcJDAAAAA==.Redeamer:BAAALgAECgEJAgAAAA==.Resco:BAACLgAFFH8lAAITAAcJCxp1AgADAgATAAcJCxp1AgADAgAuAAQKfzcAAhMACQnaJHMGAD8DABMACQnaJHMGAD8DAAAA.Rescotwo:BAAALgAECgYJDgAAAA==.',
Ri='Riddle:BAABLgAECn8YAAIcAAkJcgdrZQDzAAAcAAkJcgdrZQDzAAAAAA==.Rimeouo:BAAALgADCgEJAQAAAA==.Rize:BAAALgAECgMJAwABLgAECggJJAAGAFcLAA==.',
Ro='Rocksolid:BAAALgADCgUJBgAAAA==.Ronnie:BAAALgAECgQJBQAAAA==.Rook:BAACLgAFFH8ZAAMPAAUJvBwPQQBDAQAPAAQJvBwPQQBDAQADAAEJAADhSgAAAAAuAAQKfygAAg8ACAmwIikXAPACAA8ACAmwIikXAPACAAAA.Rookmonger:BAAALgAECgUJBQABLgAFFAUJGQAPALwcAA==.Rosenrott:BAAALgAFFAIJAwAAAA==.Rosepiercer:BAABLgAECn8tAAIQAAgJhyM2EQCeAgAQAAgJhyM2EQCeAgAAAA==.Rosies:BAAALgAECgUJBwAAAA==.Rouz:BAABLgAECn8cAAIeAAYJeA+QDQAVAQAeAAYJeA+QDQAVAQAAAA==.',
Ry='Ryenoh:BAAALgADCgYJBgAAAA==.Ryoto:BAACLgAFFH8RAAMGAAQJTiSKGQBBAQAGAAMJ8CSKGQBBAQAeAAIJZiK4CABoAAAuAAQKfxsAAwYACQmHJQQVABICAAYACQmHJQQVABICAB4AAwkXJCMmAPIAAAAA.',
Sa='Sadness:BAAALgADCgYJBwAAAA==.Saelyz:BAAALgADCgQJBAAAAA==.Saetha:BAAALgAECgcJEgAAAA==.Samandean:BAABLgAECn8rAAIMAAgJpxE6GACKAQAMAAgJpxE6GACKAQAAAA==.Santhallibar:BAABLgAECn8iAAImAAgJuwL+EQDgAAAmAAgJuwL+EQDgAAAAAA==.Sarasvati:BAABLgAECn8iAAIFAAgJ9BySEgCXAgAFAAgJ9BySEgCXAgAAAA==.Saster:BAABLgAECn8gAAIPAAgJUCKcFwCXAgAPAAgJUCKcFwCXAgAAAA==.Sathrel:BAAALgADCgIJAgABLgAECgkJBwAEAAAAAA==.',
Sc='Scrabs:BAAALgAECgkJDwAAAA==.',
Se='Sellena:BAABLgAECn8lAAIfAAgJHRScDACxAQAfAAgJHRScDACxAQABLgAECggJKwAMAKcRAA==.Sementha:BAAALgADCgcJDgABLgAECgYJCQAEAAAAAA==.Senpai:BAABLgAECn8UAAIXAAYJyRxQIQCpAQAXAAYJyRxQIQCpAQABLgAFFAYJGwAFABgdAA==.Sephyra:BAAALgAECggJCAAAAA==.',
Sh='Shadowmyst:BAAALgADCgQJCgAAAA==.Shaken:BAAALgAECgIJAgAAAA==.Shandow:BAACLgAFFH8UAAIRAAUJ5hkUOQBQAQARAAUJ5hkUOQBQAQAuAAQKf0YAAhEACQlfJKUGADkDABEACQlfJKUGADkDAAAA.Shango:BAAALgADCgcJCQAAAA==.Shanshunt:BAAALgADCgUJBgABLgAFFAUJFAARAOYZAA==.Shansoracle:BAACLgAFFH8MAAIYAAUJJQ3wDABFAQAYAAUJJQ3wDABFAQAuAAQKfxsAAhgACQkcHn4EAB0DABgACQkcHn4EAB0DAAEuAAUUBQkUABEA5hkA.Shed:BAACLgAFFH8NAAIZAAUJYhuLDwBjAQAZAAUJYhuLDwBjAQAuAAQKfy0AAhkACAltIZYNAMgCABkACAltIZYNAMgCAAAA.Sheislegend:BAAALgAECgUJCAAAAA==.Shelby:BAABLgAECn8wAAMYAAgJwRsyDwBOAgAYAAgJwRsyDwBOAgAIAAUJcRAKNgAXAQAAAA==.Shmoon:BAEALgAECgIJAgABLgAECgQJBAAEAAAAAA==.Shmuckman:BAAALgADCgkJEwAAAA==.Shoty:BAAALgAECgMJAwABLgAFFAUJGQAPALwcAA==.',
Si='Siccinok:BAABLgAECn8hAAIRAAgJhhGtaACOAQARAAgJhhGtaACOAQAAAA==.Silicá:BAAALgADCgkJCQABLgAECgIJAgAEAAAAAA==.Sindorian:BAABLgAECn8mAAMQAAgJIyERJwAdAgAQAAYJHSIRJwAdAgAUAAgJfh4hEgD+AQAAAA==.',
Sk='Skrimphorn:BAAALgAECgEJAQAAAA==.',
Sl='Slimped:BAAALgAECgcJCAAAAA==.',
Sm='Smurricane:BAAALgAECgUJCAAAAA==.',
Sn='Snowybato:BAAALgAECgQJBwAAAA==.',
So='Solandor:BAABLgAECn8yAAQOAAkJNCLKAgD5AgAOAAkJ1iDKAgD5AgATAAgJ6B3CFwCOAgAnAAMJnRmrQgCGAAAAAA==.Solar:BAAALgAECgQJCAAAAA==.Solarial:BAAALgAECgUJEQAAAA==.Solastra:BAABLgAECn8lAAIhAAgJvxm3EQBiAgAhAAgJvxm3EQBiAgAAAA==.Soramai:BAAALgADCgcJDwAAAA==.Soth:BAABLgAECn87AAIPAAkJtRmXHwBpAgAPAAkJtRmXHwBpAgAAAA==.',
Sp='Sparticusdru:BAAALgAECgcJEQAAAA==.Spore:BAAALgAECgMJAwAAAA==.',
Sq='Sqaw:BAAALgAECgEJAQAAAA==.',
St='Starkadia:BAAALgAECgYJBgAAAA==.Staryxia:BAACLgAFFH8VAAMHAAUJHxenBwA2AQAHAAQJHxenBwA2AQADAAEJAACiNgAAAAAuAAQKfy0AAgcACQmhIUsBAPYCAAcACQmhIUsBAPYCAAAA.Steamdruid:BAAALgAECgYJEQAAAA==.Stonecookies:BAABLgAECn8dAAMNAAgJ/AhrcgA/AQANAAgJ7QdrcgA/AQABAAUJ7AYySQCTAAAAAA==.Stonecross:BAAALgAECgYJCgAAAA==.Stonehard:BAAALgAECgEJAQAAAA==.Stoneldo:BAAALgADCgEJAQAAAA==.Stonetotem:BAAALgAECgYJCQAAAA==.Stormbolt:BAABLgAECn87AAIJAAkJxxRqEgAbAgAJAAkJxxRqEgAbAgAAAA==.Stormspirit:BAAALgADCgkJEAAAAA==.Striggen:BAAALgAECgUJDgAAAA==.',
Su='Succystrazsa:BAAALgADCgIJAgAAAA==.Sugarsham:BAAALgAECgcJEAAAAA==.Sulwen:BAACLgAFFH8UAAIJAAgJRCLvAAA9AgAJAAgJRCLvAAA9AgAuAAQKfyAAAgkACQmQJswEAPQCAAkACQmQJswEAPQCAAAA.Sumerset:BAAALgAECgMJBgAAAA==.Sunnydee:BAAALgAECgYJCwAAAA==.Supaflytnt:BAAALgAECgUJCAAAAA==.Sustia:BAAALgAECgYJEQAAAA==.',
Ta='Tacopie:BAAALgAECgQJBgAAAA==.Taera:BAABLgAECn8xAAIXAAgJSiFYCADiAgAXAAgJSiFYCADiAgAAAA==.Taika:BAAALgADCgkJDwAAAA==.Tailchaser:BAAALgADCgcJBwAAAA==.Talanazar:BAABLgAECn85AAQGAAkJFSCqBAAFAwAGAAkJFSCqBAAFAwAeAAYJgR2AFAChAQAkAAIJdg7sKQBuAAAAAA==.Talavenn:BAABLgAECn8ZAAILAAcJIhAUZgA0AQALAAcJIhAUZgA0AQAAAA==.Tallish:BAABLgAECn8dAAILAAgJbg33egA3AQALAAgJbg33egA3AQAAAA==.Tarage:BAAALgAECgIJAgAAAA==.Taterchip:BAABLgAECn8fAAITAAYJwBY3NwBEAQATAAYJwBY3NwBEAQAAAA==.Taylia:BAAALgAECgQJBgAAAA==.',
Te='Teaorix:BAAALgADCgQJBAAAAA==.Teds:BAAALgADCgUJBQAAAA==.Temporary:BAAALgADCgYJBgAAAA==.Tempus:BAAALgAECgYJEwAAAA==.Teradoxx:BAAALgAECgYJDgAAAA==.Teriko:BAABLgAECn82AAMPAAkJGx7FFgCcAgAPAAkJGx7FFgCcAgADAAEJywTbWAAVAAAAAA==.Teviro:BAAALgAECgQJBAABLgAECgkJPQAUAEkhAA==.',
Th='Thanks:BAAALgAECgEJAQAAAA==.Thequixote:BAAALgADCgEJAQAAAA==.Therizino:BAAALgADCgQJBAAAAA==.Thrashy:BAAALgAECgQJCAAAAA==.Thrum:BAAALgAECgEJAQAAAA==.',
Ti='Tinkerballa:BAAALgAECgEJAQAAAA==.',
To='Toxictotes:BAAALgAECgIJAwAAAA==.',
Tw='Twiddleado:BAABLgAECn8uAAIRAAkJpxPWOAAZAgARAAkJpxPWOAAZAgAAAA==.Twinkie:BAAALgAECggJCAABLgAECgcJIAALAPoiAA==.Twinkle:BAAALgADCgEJAQAAAA==.',
Ty='Tylor:BAAALgAECgYJDwAAAA==.',
['Tå']='Tåkete:BAAALgAECgYJCwAAAA==.',
Uk='Ukuindadookr:BAAALgADCgYJBgAAAA==.',
Um='Ume:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.',
Un='Unta:BAAALgAECgYJCQAAAA==.',
Va='Valaera:BAAALgAECgUJDAAAAA==.Valenora:BAABLgAECn8XAAIBAAgJzBrtBQDYAQABAAgJzBrtBQDYAQAAAA==.Valise:BAABLgAECn8YAAICAAYJrwRWFwDNAAACAAYJrwRWFwDNAAAAAA==.Varielle:BAAALgAECgYJCQAAAA==.Varuz:BAAALgAECgQJBgABLgAECgYJDwAEAAAAAA==.Vaticamt:BAAALgAECgUJBQAAAA==.',
Ve='Vecxx:BAAALgADCgUJBQAAAA==.Velanie:BAAALgAECggJDAAAAA==.Velanise:BAAALgADCgMJAwAAAA==.Velight:BAAALgADCgEJAQAAAA==.Velinara:BAAALgAECgEJAQAAAA==.Velindroz:BAAALgAECgMJBgAAAA==.Veloras:BAAALgAECgEJAQAAAA==.Verene:BAABLgAECn8iAAIcAAgJCRfRIQAXAgAcAAgJCRfRIQAXAgAAAA==.Verinari:BAAALgAECgQJBAAAAA==.',
Vi='Viperc:BAAALgADCgMJAwABLgAECgUJEQAEAAAAAA==.Vipul:BAAALgAECgEJAQABLgAECgYJDgAEAAAAAA==.Viridria:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.Virridian:BAABLgAECn8zAAIQAAkJBiDUCQDnAgAQAAkJBiDUCQDnAgAAAA==.Virrigosa:BAAALgADCgcJBwAAAA==.Vistia:BAAALgADCgEJAQAAAA==.',
Vl='Vlado:BAAALgADCgMJAwAAAA==.',
Vo='Vodalus:BAAALgADCgUJBQAAAA==.Voideria:BAAALgAECgQJBgAAAA==.Voolock:BAAALgADCggJCQAAAA==.',
Vy='Vyshana:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.',
Wa='Wallofshame:BAABLgAECn8lAAIhAAkJxh0gCwC3AgAhAAkJxh0gCwC3AgAAAA==.Walt:BAAALgADCgIJAgAAAA==.Warchef:BAAALgADCgYJCgABLgAECggJKQARAAcgAA==.Warriorclaps:BAAALgADCggJDgAAAA==.Wartooth:BAABLgAECn8pAAMBAAgJ3Bn6CACMAQABAAYJWxv6CACMAQANAAUJcBNNfgAnAQAAAA==.Wassergott:BAAALgADCgIJAgAAAA==.',
We='Webicus:BAABLgAECn8hAAIOAAgJGxUKFACGAQAOAAgJGxUKFACGAQAAAA==.Weezzer:BAAALgADCgQJBAAAAA==.Wendee:BAABLgAECn8kAAMYAAgJdAGnQgC5AAAYAAgJdAGnQgC5AAAIAAUJdQTkSwCoAAAAAA==.',
Wh='Whitefóx:BAACLgAFFH8JAAIaAAQJQAxyBwDVAAAaAAQJQAxyBwDVAAAuAAQKfxcAAhoACQmxF5oHADUCABoACQmxF5oHADUCAAEuAAUUBQkUABEA5hkA.Whitley:BAABLgAECn8jAAIcAAkJkR/2BAA/AwAcAAkJkR/2BAA/AwAAAA==.',
Wi='Wijing:BAAALgAECgIJAgAAAA==.',
Wo='Wolololo:BAAALgAECgEJAQABLgAECggJIAAPAFAiAA==.',
['Wü']='Wülfsa:BAAALgAECgUJBQAAAA==.',
Xa='Xanthium:BAABLgAECn8YAAIYAAYJzwE3SQCUAAAYAAYJzwE3SQCUAAAAAA==.Xanzib:BAAALgADCgYJBgAAAA==.Xaphy:BAAALgAECgYJCwAAAA==.Xardots:BAABLgAECn8lAAIBAAgJohUkCQCIAQABAAgJohUkCQCIAQABLgAECggJMQAEAAAAAA==.',
Xe='Xeetali:BAAALgADCgYJBgAAAA==.',
Xi='Xiareth:BAABLgAECn8pAAMkAAgJ5Q05FgBFAQAkAAcJKA05FgBFAQAeAAEJkAbGIgAsAAAAAA==.',
Xt='Xtronger:BAABLgAECn8gAAIFAAgJmRa2KgDeAQAFAAgJmRa2KgDeAQAAAA==.',
['Xá']='Xároth:BAAALgAECggJMQAAAQ==.',
Ya='Yaddi:BAAALgAECgMJAwAAAA==.Yarrow:BAAALgADCgkJCQAAAA==.',
Ye='Yeeyee:BAAALgAECgkJEgAAAA==.',
Za='Zalik:BAAALgAECgMJAwAAAA==.',
Ze='Zeebo:BAAALgAECgUJCgAAAA==.Zest:BAABLgAECn8pAAMkAAkJ2BBmCwD/AQAkAAkJ2BBmCwD/AQAGAAIJkAiAaQBmAAAAAA==.',
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
