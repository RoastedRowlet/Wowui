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

local lookup = {'Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Unknown-Unknown','Druid-Restoration','Priest-Discipline','Priest-Shadow','Priest-Holy','Evoker-Augmentation','DeathKnight-Frost','Monk-Windwalker','Druid-Balance','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Shaman-Elemental','Warrior-Protection','DeathKnight-Unholy','Hunter-BeastMastery','Mage-Frost','DemonHunter-Vengeance','Warrior-Fury','Monk-Mistweaver','Hunter-Survival','Monk-Brewmaster','Paladin-Protection','Shaman-Restoration','Mage-Fire','Rogue-Subtlety','Evoker-Devastation','Shaman-Enhancement','Druid-Guardian','Paladin-Holy','Druid-Feral','Evoker-Preservation','Mage-Arcane','Rogue-Assassination','Warrior-Arms','Rogue-Outlaw',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Absens:BAABLgAECn8+AAMBAAkJwhIMCwCBAQABAAkJhw8MCwCBAQACAAgJ0hAPDQB4AQAAAA==.',
Ad='Adorian:BAAALgAFFAEJAQABLgAFFAQJEAADAKkfAA==.Adwillon:BAAALgADCgQJBQABLgAECgYJEAAEAAAAAA==.',
Ae='Aedoril:BAAALgADCgEJAQAAAA==.Aellea:BAAALgADCgkJCQAAAA==.Aelyss:BAAALgADCgQJBAAAAA==.Aerosse:BAAALgAECgMJAwAAAA==.',
Af='Aforceofone:BAAALgAECgQJEQAAAA==.',
Ai='Airdreanna:BAAALgADCgQJBAAAAA==.',
Ak='Akama:BAAALgAECgcJDAABLgAFFAcJHQAFAJ8cAA==.',
Al='Alivanllan:BAAALgAECgIJAgAAAA==.Alteisen:BAAALgAECgUJBQAAAA==.',
Am='Ambitious:BAAALgAECgMJCgAAAA==.Amerlinn:BAAALgAECgYJDAAAAA==.',
An='Anamuht:BAABLgAECn8aAAQGAAkJnhLaGAD9AQAGAAgJeBPaGAD9AQAHAAkJ1BCcHQDQAQAIAAYJHhAeMgAzAQABLgAECgkJOgAJABUgAA==.Andryn:BAAALgAECgEJAQAAAA==.Annaday:BAABLgAECn8lAAIDAAkJgQ2+HgBUAQADAAkJgQ2+HgBUAQAAAA==.Antiock:BAACLgAFFH8QAAMDAAQJqR+uEwA6AQADAAQJqR+uEwA6AQAKAAQJVBOxCwAmAQAuAAQKfzAAAwMACQn8IxcEAPACAAMACQn8IxcEAPACAAoABwnRHKMJANcBAAAA.Anyaesthesia:BAAALgADCgYJBgAAAA==.Anyamonka:BAABLgAECn8YAAILAAYJWRreJACAAQALAAYJWRreJACAAQAAAA==.',
Ap='Apocalich:BAAALgAECgUJBQAAAA==.Appalachia:BAAALgADCgIJAgAAAA==.',
Aq='Aquenia:BAAALgADCggJDAAAAA==.',
Ar='Aralaith:BAABLgAECn8jAAIHAAgJYiUqCADIAgAHAAgJYiUqCADIAgABLgAFFAgJFAAMAEQiAA==.Argonaut:BAAALgAECgIJAgAAAA==.Argul:BAAALgAECgIJAgAAAA==.Ariea:BAAALgADCgYJBgAAAA==.Artoriá:BAAALgAECgEJAQAAAA==.Artto:BAABLgAECn8tAAINAAgJNQ9regBuAQANAAgJNQ9regBuAQAAAA==.',
As='Asevenhex:BAAALgAECgEJAQAAAA==.Ashbrínger:BAABLgAECn9HAAINAAkJDCa2AgBoAwANAAkJDCa2AgBoAwAAAA==.Association:BAAALgAECgMJAwAAAA==.Astrum:BAAALgAECgEJAgAAAA==.Asunã:BAAALgAECgIJAgABLgAECgEJAQAEAAAAAA==.',
Au='Aurah:BAAALgAECgIJBAAAAA==.',
Av='Averax:BAABLgAECn85AAMOAAgJxR71GAB1AgAOAAgJxR71GAB1AgAPAAEJvQ2JbgA3AAAAAA==.Avyrax:BAAALgADCgcJDQABLgAECggJOQAOAMUeAA==.',
Ay='Aybara:BAAALgADCgQJBAAAAA==.Aylakaye:BAAALgADCgMJAwAAAA==.Ayraena:BAABLgAECn8ZAAMMAAgJHQibOgAZAQAMAAgJHQibOgAZAQAFAAQJEgGOwQA9AAAAAA==.',
Az='Azkariel:BAAALgADCgQJBAAAAA==.Azyrieth:BAAALgADCgEJAQAAAA==.Azzathoth:BAAALgADCgcJDAAAAA==.',
Ba='Babyshoes:BAAALgAECgEJAQAAAA==.Bakedtofu:BAABLgAECn8UAAMBAAYJ7wc9RwCZAAAQAAYJ7wdhzACxAAABAAQJGQQ9RwCZAAAAAA==.Basement:BAAALgAECgMJAgABLgAFFAUJEQARAFMfAA==.Bashine:BAABLgAECn8VAAISAAYJVxlZGACTAQASAAYJVxlZGACTAQABLgAFFAcJHQATAPMeAA==.Baylohn:BAABLgAECn8lAAIUAAkJhRYcLgAZAgAUAAkJhRYcLgAZAgAAAA==.',
Be='Bearwrestler:BAABLgAECn8aAAIVAAgJ1BcFXQDCAQAVAAgJ1BcFXQDCAQABLgAFFAQJDwADAJAgAA==.Beefynugs:BAAALgAECgkJAgAAAA==.',
Bi='Bier:BAAALgAECgUJDgAAAA==.Bigrig:BAABLgAECn8YAAIUAAgJZQUGqwDcAAAUAAgJZQUGqwDcAAAAAA==.Bitterman:BAABLgAECn8xAAMQAAkJQhj8HQBqAgAQAAkJQhj8HQBqAgABAAEJww/ZcAA1AAAAAA==.',
Bj='Bjornvalion:BAAALgADCgQJBAAAAA==.',
Bl='Blackmage:BAAALgAECgEJAQAAAA==.Bladed:BAABLgAECn8lAAQWAAgJiBnZDQBlAQAWAAYJChvZDQBlAQAOAAcJuhLiXwBeAQAPAAQJFxIwPQCwAAAAAA==.Blinkerfluid:BAAALgADCgIJAgAAAA==.Blinx:BAAALgADCgQJBAAAAA==.Bloodymess:BAAALgAECggJEAAAAA==.',
Bo='Bohikeog:BAAALgADCgYJBgAAAA==.Boogies:BAAALgADCgQJBwAAAA==.Bovinedivine:BAAALgAECgYJBgABLgAECgkJOAAEAAAAAA==.',
Bu='Buffie:BAABLgAECn8ZAAINAAgJGhoeWADaAQANAAgJGhoeWADaAQAAAA==.Bullwyf:BAAALgADCgMJAwAAAA==.Bumblbeetuna:BAAALgAECgMJAwAAAA==.',
['Bá']='Bád:BAAALgADCggJDgABLgAECgUJCAAEAAAAAA==.',
Ca='Calduu:BAAALgAECgQJCAAAAA==.Caledia:BAAALgAECgYJEQAAAA==.Callana:BAAALgADCgMJBQAAAA==.Camedra:BAABLgAECn9GAAIFAAkJkCTsAQCzAwAFAAkJkCTsAQCzAwAAAA==.Carinancey:BAAALgAECgQJBQAAAA==.Carperoni:BAAALgADCgcJBwAAAA==.Casseous:BAAALgADCgUJBwAAAA==.Castrada:BAAALgAECgUJBQABLgAECgkJRgANAD4XAA==.Catamynyia:BAABLgAECn8kAAIUAAkJpQ4cQwDMAQAUAAkJpQ4cQwDMAQAAAA==.Caylaetal:BAAALgAECgEJAQAAAA==.',
Cc='Cchaos:BAAALgAECgIJBgAAAA==.',
Ce='Celaborn:BAABLgAECn8dAAIXAAkJ/hwBGgAXAgAXAAkJ/hwBGgAXAgAAAA==.Celice:BAAALgAECgUJBQABLgAFFAMJBQAYAKkTAA==.Cerwan:BAAALgADCgMJAwAAAA==.',
Ch='Chazaraz:BAABLgAECn88AAMZAAkJNA2+FgDpAQAZAAkJmgy+FgDpAQAUAAgJEgghggAtAQAAAA==.Chazsquatch:BAAALgAECgUJBQABLgAECgkJPAAZADQNAA==.Chevy:BAAALgAECgEJAwAAAA==.Chifreak:BAAALgAFFAIJAgABLgAECgkJJgAOAEAjAA==.Chillmourne:BAAALgAECgcJEwABLgAECggJFgABAJIIAA==.Chimaira:BAAALgADCgIJAgAAAA==.Chucknoris:BAAALgAECgMJBgAAAA==.Chugbuggins:BAAALgAECgYJEAAAAA==.',
Ci='Cindria:BAABLgAECn8lAAIVAAgJuBCMcQCRAQAVAAgJuBCMcQCRAQAAAA==.',
Cl='Clerks:BAAALgAECgIJAgAAAA==.Cliffgate:BAAALgADCgMJAwAAAA==.',
Co='Conduction:BAAALgAECgUJCAAAAA==.Corenthia:BAAALgAECgUJCAAAAA==.',
Cp='Cptbonez:BAAALgAECgYJEgABLgAECgkJKQAaAEYTAA==.',
Cr='Crankadin:BAAALgADCgUJBQABLgAECgIJBAAEAAAAAA==.Crankchi:BAAALgADCgYJBwABLgAECgIJBAAEAAAAAA==.Crazz:BAAALgADCgEJAQAAAA==.Crewz:BAAALgADCgQJBAAAAA==.Crooky:BAAALgADCgcJBwABLgAFFAYJGwATANUbAA==.Crucifiiks:BAAALgAECgQJBgAAAA==.Cruciö:BAAALgAECgEJAQAAAA==.Crànk:BAAALgAECgIJBAAAAA==.Crãnk:BAAALgAECgIJAgABLgAECgIJBAAEAAAAAA==.',
Cu='Curveball:BAAALgAECggJDAABLgAECgkJMQAQAEIYAA==.',
Cy='Cyniar:BAAALgAECgYJBgAAAA==.',
Da='Dalearnhardt:BAAALgADCgcJDgABLgAECgcJEgAEAAAAAA==.Damerlin:BAABLgAECn8UAAMNAAgJvAprkABFAQANAAgJvAprkABFAQAbAAQJ+QMEOwBkAAAAAA==.Darkhuntress:BAAALgAECgUJBQAAAA==.Darkstär:BAABLgAECn9GAAIDAAkJiB17BwCaAgADAAkJiB17BwCaAgAAAA==.Darkun:BAAALgAECgUJBQABLgAECgkJLAAJAC8TAA==.Darkwood:BAAALgADCgEJAgAAAA==.Dauc:BAAALgADCgEJAQAAAA==.',
De='Deacon:BAABLgAECn85AAQaAAgJHAnyNwAVAQAaAAgJOgfyNwAVAQALAAUJmgqtVwCkAAAYAAUJfQRdgwB3AAAAAA==.Deadmantooth:BAAALgADCgYJBgABLgAECggJOQABANIdAA==.Deardren:BAAALgAECgUJBQAAAA==.Deathknights:BAAALgAFFAEJAQAAAA==.Deathtrol:BAAALgAECggJCQAAAA==.Deeanne:BAAALgAECgQJBwAAAA==.Deepdeuce:BAAALgAECgQJBAAAAA==.Deepfriar:BAABLgAECn9KAAMIAAkJ4CP1AQCFAwAIAAkJ4CP1AQCFAwAHAAcJMRQiKgB5AQAAAA==.Deidra:BAAALgADCgMJAwAAAA==.Demonhunts:BAABLgAFFH8JAAIOAAUJfwhpUADrAAAOAAUJfwhpUADrAAAAAA==.Demonmore:BAABLgAECn8jAAMPAAgJxAuWJwArAQAPAAgJ2AqWJwArAQAWAAUJWQoVHwCVAAAAAA==.Derailed:BAAALgAECgQJBwAAAA==.Dethwing:BAAALgAECgEJAQAAAA==.Devilfrost:BAAALgAECgEJAQABLgAECgMJBgAEAAAAAA==.Dewshine:BAAALgAECgYJCwAAAA==.',
Dh='Dhampir:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Dhgeek:BAAALgAECgMJBQAAAA==.',
Di='Diablognomis:BAAALgAECgUJEQAAAA==.Diarmac:BAAALgAECgUJBQABLgAECgkJRgAcAG8OAA==.Dingô:BAAALgAECgQJBgAAAA==.Dirtman:BAABLgAECn8sAAIRAAkJpBxnEQBaAgARAAkJpBxnEQBaAgAAAA==.',
Dk='Dkrise:BAAALgAECgMJAwABLgAECgkJLAAJAC8TAA==.',
Dn='Dneoh:BAAALgAECgkJCAABLgAFFAMJCgAMAOciAA==.',
Do='Donald:BAAALgADCgQJBAAAAA==.Donny:BAABLgAECn8oAAMNAAgJnx0ZLABGAgANAAgJnx0ZLABGAgAbAAEJWw/qTQAsAAAAAA==.Doodyshamala:BAAALgAECgQJCQAAAA==.Dooky:BAAALgAECgYJBwABLgAFFAYJGwATANUbAA==.Doozey:BAACLgAFFH8OAAIOAAQJJxbCOwAjAQAOAAQJJxbCOwAjAQAuAAQKfykAAw4ACQniHjwaAG0CAA4ACQlaHjwaAG0CABYAAQnNE8AuADwAAAAA.Dorigis:BAAALgADCgkJMAABLgAECgkJIAASABcjAA==.Dotdotdotded:BAABLgAECn8WAAIQAAgJuAUKjwAYAQAQAAgJuAUKjwAYAQAAAA==.',
Dr='Drewdog:BAABLgAECn82AAMZAAgJ7RSEHAC0AQAZAAgJ9g6EHAC0AQAUAAYJeBecdwBDAQAAAA==.Droid:BAAALgAECgEJAgAAAA==.Drunkgerardo:BAAALgAECgQJBQAAAA==.Drunkzen:BAAALgAECgUJBQAAAA==.Druyesil:BAAALgAECgEJAgAAAA==.',
Du='Dubes:BAABLgAECn9BAAIVAAkJzBi0JwB1AgAVAAkJzBi0JwB1AgAAAA==.Dunbartian:BAAALgAECgcJCAAAAA==.Duskfang:BAAALgADCgUJAQAAAA==.',
['Dá']='Dárkthorn:BAAALgAECgIJBAAAAA==.',
['Dö']='Dökkálfar:BAAALgAECgEJAQAAAA==.',
Ea='Easybreezin:BAAALgAECgUJDAAAAA==.',
Ei='Eirote:BAABLgAECn9KAAIdAAkJtBqeAQB0AgAdAAkJtBqeAQB0AgAAAA==.',
El='Elarris:BAAALgAECgcJBwAAAA==.Eldari:BAABLgAECn8YAAIMAAgJ2hvRGQDwAQAMAAgJ2hvRGQDwAQAAAA==.Elem:BAACLgAFFH8PAAIcAAYJUwikIgBIAQAcAAYJUwikIgBIAQAuAAQKfyMAAhwACAmcIFMYAFMCABwACAmcIFMYAFMCAAAA.Ellyssanna:BAAALgAECgMJBAAAAA==.Elm:BAAALgAECgYJEAAAAA==.Elyssaena:BAAALgAECgYJEgAAAA==.',
Em='Emiliachan:BAAALgAECgcJCwAAAA==.',
En='Enzojr:BAACLgAFFH8MAAIeAAQJqxs/EwBeAQAeAAQJqxs/EwBeAQAuAAQKf0QAAh4ACQlZJBcCADoDAB4ACQlZJBcCADoDAAAA.',
Ep='Ephixa:BAAALgAECgYJDwAAAA==.',
Er='Eridanos:BAAALgADCgYJBgAAAA==.Erisiel:BAAALgAECgEJAQAAAA==.Eruelle:BAACLgAFFH8JAAIOAAQJ2yKCIwCFAQAOAAQJ2yKCIwCFAQAuAAQKfyAAAg4ACQnRIkAEADsDAA4ACQnRIkAEADsDAAEuAAUUCAkUAAwARCIA.Erzå:BAAALgAECgEJAgABLgAECgEJAQAEAAAAAA==.',
Ev='Evoke:BAABLgAECn8fAAMJAAgJgyF3CgDOAgAJAAgJdB93CgDOAgAfAAYJZyBaDQAEAgAAAA==.',
Ey='Eye:BAACLgAFFH8KAAIgAAQJBiEHCQAdAQAgAAQJBiEHCQAdAQAuAAQKfyAAAyAACQnRINAGAFoCACAACQnRINAGAFoCABEAAQmZDN2PACgAAAAA.',
['Eí']='Eís:BAAALgADCgYJCwAAAA==.',
Fa='Faeira:BAAALgAECgcJCQAAAA==.Faloril:BAAALgAECgMJBwAAAA==.Falsara:BAAALgAECgQJBAAAAA==.Faranth:BAABLgAECn9CAAIJAAkJMSBBBgDxAgAJAAkJMSBBBgDxAgAAAA==.Faronyr:BAAALgAECgEJAQAAAA==.',
Fe='Feer:BAAALgAECgQJAQAAAA==.Felboi:BAAALgAECgUJDgAAAA==.Felknight:BAAALgAECgIJAgAAAA==.Felorc:BAAALgAECgQJBwAAAA==.Felynne:BAAALgAECgcJEQAAAA==.Fenrík:BAAALgADCgIJAgAAAA==.Feo:BAABLgAECn8eAAIOAAkJexkTJQAuAgAOAAkJexkTJQAuAgAAAA==.Ferum:BAABLgAECn9RAAMFAAkJQCVOAQDGAwAFAAkJQCVOAQDGAwAMAAYJuRB7PQALAQAAAA==.',
Fi='Fionnan:BAABLgAECn9FAAIhAAkJkQ4aGQBzAQAhAAkJkQ4aGQBzAQABLgAECgkJRgAcAG8OAA==.',
Fo='Forest:BAACLgAFFH8OAAQMAAUJjhRxHQAaAQAMAAUJjhRxHQAaAQAFAAIJZwZnWQBiAAAhAAIJtgguKgBZAAAuAAQKfy4AAwwACQl6HSkNAMYCAAwACQl6HSkNAMYCAAUAAwn3G9ZpAO0AAAAA.',
Fr='Fraoch:BAAALgAECgUJBQABLgAECgkJRgAMAFYLAA==.Fretless:BAAALgADCgYJCgAAAA==.Frixley:BAAALgAFFAIJAgAAAA==.Friérén:BAAALgAECgEJAwABLgAECgEJAQAEAAAAAA==.Frostedrayne:BAAALgADCgUJBQAAAA==.Frostthrower:BAAALgAECgEJAgAAAA==.Fryeguy:BAAALgAECggJEwAAAA==.',
Fu='Funkysoup:BAAALgADCgYJBgAAAA==.',
Fy='Fyodor:BAAALgAECgIJBQAAAA==.',
['Fè']='Fèresha:BAAALgAECgkJEgAAAA==.',
['Fò']='Fòrced:BAAALgAECggJDQAAAA==.',
Ga='Gallium:BAABLgAECn8iAAIiAAkJIBhoEwBrAgAiAAkJIBhoEwBrAgAAAA==.Gazerbeam:BAAALgAFFAEJAQAAAA==.',
Ge='Geelock:BAAALgADCggJFgAAAA==.Gehena:BAAALgAFFAIJAgABLgAFFAIJAwAEAAAAAQ==.Gemsareyum:BAAALgAECgYJDgABLgAFFAYJPAAUAKQiAA==.Gesht:BAABLgAECn8dAAINAAkJVRAobACLAQANAAkJVRAobACLAQAAAA==.Getemwet:BAAALgAECgEJAQAAAA==.',
Gh='Ghostfreak:BAAALgAECgUJBgAAAA==.',
Gi='Gidgetz:BAAALgADCgMJAwAAAA==.',
Gl='Glamourkills:BAAALgADCgcJDQAAAA==.Gleipnir:BAAALgAECgIJAgAAAA==.',
Go='Goldenbell:BAAALgAECgUJBQAAAA==.Goof:BAABLgAECn82AAIiAAkJ9Q4wMACOAQAiAAkJ9Q4wMACOAQAAAA==.Goontas:BAAALgAECgMJBAAAAA==.',
Gr='Grimsheèper:BAAALgAECgMJBAAAAA==.Grish:BAABLgAECn8ZAAIgAAYJHgZoIgDQAAAgAAYJHgZoIgDQAAAAAA==.Griz:BAAALgAECgQJCAAAAA==.Grollnar:BAAALgAECgEJAQABLgAECgkJDwAEAAAAAA==.Grossevache:BAAALgAECgYJEAAAAA==.Gròws:BAAALgAECgkJBwAAAA==.',
Ha='Haddor:BAABLgAECn8rAAMbAAkJJxq1BwBUAgAbAAkJJxq1BwBUAgANAAEJWwSRpgElAAAAAA==.Haelexi:BAAALgAECgMJBgAAAA==.Halujoxar:BAAALgADCgcJDgABLgAECgkJOAAEAAAAAA==.Hamonkulous:BAAALgADCgcJCAAAAA==.Hankerin:BAAALgADCgcJCgAAAA==.Harandar:BAAALgAECgEJAQAAAA==.Harleÿquinn:BAAALgAECgEJAQAAAA==.Harpomage:BAAALgADCgcJCQAAAA==.Hatcher:BAAALgAECgEJAQAAAA==.Haunter:BAABLgAECn8iAAQTAAkJiiB6bgB/AQATAAYJLR96bgB/AQADAAUJlR5WIABGAQAKAAIJrxurIQCtAAAAAA==.Hayleigh:BAACLgAFFH8dAAIFAAcJnxwLBwBxAgAFAAcJnxwLBwBxAgAuAAQKfzEAAgUACQmEImwFAFoDAAUACQmEImwFAFoDAAAA.',
He='Heimdallr:BAAALgAECgEJAQAAAA==.Heisenborg:BAAALgAECgUJBQAAAA==.Hellbreezy:BAAALgAECgkJEAAAAA==.Helldin:BAABLgAECn8nAAINAAYJ3hX3mQA1AQANAAYJ3hX3mQA1AQAAAA==.Hellenfeller:BAABLgAECn8iAAIPAAYJ9RUfJABEAQAPAAYJ9RUfJABEAQAAAA==.',
Hi='Hilitepriest:BAABLgAECn8bAAMGAAgJ0RnEFAApAgAGAAgJQBnEFAApAgAIAAIJ1BZvaACLAAAAAA==.Hittomi:BAAALgAECgYJBgAAAA==.',
Ho='Holific:BAABLgAECn9GAAINAAkJPheTLwA3AgANAAkJPheTLwA3AgAAAA==.Honeychild:BAAALgAECgYJCgAAAA==.Hotrodranger:BAAALgAECgcJEgAAAA==.Hottub:BAAALgAECgUJBQAAAA==.',
Hu='Huckleberry:BAAALgADCggJDQAAAA==.Hut:BAABLgAFFH8HAAIMAAUJOw9+JwDhAAAMAAUJOw9+JwDhAAABLgAFFAUJEQARAFMfAA==.',
Hv='Hvac:BAABLgAECn81AAIVAAkJywwVYQC3AQAVAAkJywwVYQC3AQAAAA==.',
Hy='Hypearione:BAAALgADCgIJAgAAAA==.',
Ia='Ialan:BAAALgADCgIJAgAAAA==.',
Ic='Iceovo:BAAALgADCgEJAQAAAA==.Icycritties:BAABLgAECn8YAAIVAAYJehAlvQBoAQAVAAYJehAlvQBoAQAAAA==.',
Id='Idovoodew:BAAALgADCgUJCAAAAA==.',
Ih='Iheals:BAAALgAECgMJCQAAAA==.',
Il='Illidon:BAAALgADCgYJBgAAAA==.',
Im='Imjustadruid:BAAALgADCggJCgAAAA==.Immortal:BAABLgAECn8fAAITAAkJBxkmJQBnAgATAAkJBxkmJQBnAgAAAA==.Implants:BAAALgADCggJCQAAAA==.',
In='Incarnate:BAAALgAECgcJEAAAAA==.Incarnated:BAACLgAFFH8RAAMTAAUJJRzmaAAeAQATAAQJWiHmaAAeAQAKAAMJoRJ8EQDjAAAuAAQKfzMAAxMACQnII9oMAP4CABMACQl3I9oMAP4CAAoAAwmBIqQTADIBAAAA.Inflammation:BAAALgADCgcJDwABLgAECgUJCAAEAAAAAA==.',
Ir='Irocc:BAAALgAECgUJEQAAAA==.',
Is='Ishankyou:BAAALgAECgEJAQAAAA==.Ispithotfire:BAAALgADCgMJAwAAAA==.Istara:BAAALgADCgcJDQABLgAFFAcJHAAVAC8fAA==.',
Iu='Iu:BAAALgADCgEJAgAAAA==.',
Ja='Jackdowe:BAAALgAECgQJBAAAAA==.Jackfash:BAAALgADCgcJDQAAAA==.Jadecross:BAABLgAECn8WAAIYAAcJSxYrLwCoAQAYAAcJSxYrLwCoAQAAAA==.Jalenhunter:BAAALgADCgUJCAAAAA==.',
Je='Jedith:BAAALgAECgcJCQAAAA==.Jerambae:BAABLgAECn8VAAIdAAYJyBWYBACTAQAdAAYJyBWYBACTAQAAAA==.Jerryatric:BAABLgAECn8WAAINAAkJIgzZagCOAQANAAkJIgzZagCOAQAAAA==.',
Jo='Joelah:BAAALgAECgcJDwAAAA==.Joshua:BAAALgAECgYJDAAAAA==.',
Ju='Justincasê:BAAALgADCggJEwAAAA==.',
['Jâ']='Jây:BAAALgADCgQJBAAAAA==.',
Ka='Kalfeen:BAABLgAECn8bAAMhAAcJbh6aDAAHAgAhAAcJbh6aDAAHAgAjAAEJ+wavVQAjAAAAAA==.Kallikan:BAABLgAECn8sAAIhAAgJ2hdvDwDdAQAhAAgJ2hdvDwDdAQAAAA==.Kamidk:BAABLgAFFH8HAAITAAQJ1g15tgCeAAATAAQJ1g15tgCeAAABLgAFFAUJDAAOAHcYAA==.Kanmojo:BAAALgADCgQJBQAAAA==.Kashume:BAABLgAECn8bAAIgAAkJngKhHAAGAQAgAAkJngKhHAAGAQAAAA==.Kasteen:BAAALgAECgUJEAAAAA==.Kazon:BAAALgADCgcJCgABLgAFFAQJEAADAKkfAA==.Kaøs:BAAALgAECgEJAQAAAA==.',
Kd='Kdoggparker:BAAALgAECgIJAwAAAA==.',
Ke='Kementari:BAAALgAECgQJBQAAAA==.Kenner:BAAALgAECgEJAQAAAA==.Kenzaki:BAACLgAFFH8QAAINAAUJmQoqTwAAAQANAAUJmQoqTwAAAQAuAAQKfzYAAg0ACQnDGb86AA0CAA0ACQnDGb86AA0CAAAA.Kesha:BAAALgAECgQJBAABLgAECgkJNAAIABEaAA==.',
Kh='Khaosreborn:BAAALgAECgUJEAAAAA==.Khaotic:BAAALgADCgMJAwABLgADCgQJBAAEAAAAAA==.',
Ki='Kiiren:BAAALgAECgEJAQABLgAECgcJGwAhAG4eAA==.Kilaaz:BAABLgAECn8VAAINAAUJzCRMdgB2AQANAAUJzCRMdgB2AQAAAA==.Kilaz:BAAALgADCgUJBQAAAA==.',
Kn='Knuts:BAACLgAFFH8HAAIaAAQJBRaNIAAfAQAaAAQJBRaNIAAfAQAuAAQKfxYAAhoACQlUGIMdALEBABoACQlUGIMdALEBAAAA.',
Ko='Korius:BAAALgAECgUJBQAAAA==.Ková:BAABLgAECn8gAAIUAAgJABoMMAARAgAUAAgJABoMMAARAgAAAA==.',
Kr='Krutesiq:BAAALgADCgkJCQAAAA==.',
Ku='Kuani:BAAALgAECgYJCQABLgAFFAMJBQAYAKkTAA==.Kullman:BAAALgADCgYJCgAAAA==.Kungfupapa:BAAALgAECgQJBwAAAA==.Kungfurry:BAAALgAECgUJCAAAAA==.Kurobozu:BAAALgAECgQJBAABLgAECgkJOgAJABUgAA==.Kutherrek:BAAALgAECgEJAQAAAA==.Kuubar:BAABLgAECn8lAAIKAAkJ/RUnCAD8AQAKAAkJ/RUnCAD8AQAAAA==.',
Ky='Kyian:BAAALgAECgMJAwAAAA==.',
La='Lacus:BAAALgAECgMJAwAAAA==.Ladaeze:BAAALgADCgIJAgAAAA==.Ladiesnutz:BAACLgAFFH8FAAIJAAUJ4Rb6IwArAQAJAAUJ4Rb6IwArAQAuAAQKfxoABCQACQm6HoMWAF8BACQABAnhH4MWAF8BAB8ABQlOG3gMAD0BAAkABwl6FJQxADsBAAAA.Law:BAAALgAECgEJAgABLgAFFAcJHQAFAJ8cAA==.Laz:BAAALgADCgMJAwAAAA==.Lazerous:BAAALgADCgYJBgAAAA==.',
Le='Leafá:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Lealoo:BAABLgAECn8sAAINAAgJeBorNQAhAgANAAgJeBorNQAhAgABLgAECgkJPAAPAB4XAA==.Leghorn:BAAALgADCgIJAgABLgAECgcJGwAhAG4eAA==.Legolard:BAABLgAECn8gAAISAAkJFyMOAwADAwASAAkJFyMOAwADAwAAAA==.Lever:BAAALgADCggJCQAAAA==.',
Li='Liath:BAAALgAECgUJDgAAAA==.Liathano:BAAALgAECgIJAgAAAA==.Lightsky:BAAALgADCgIJAQAAAA==.Lildèbbíe:BAABLgAECn8oAAIVAAgJMg1NdQCIAQAVAAgJMg1NdQCIAQAAAA==.Lilspoon:BAAALgADCgMJAwAAAA==.Liltrapstarx:BAAALgAECgQJCAAAAA==.Linddori:BAABLgAECn8qAAINAAgJphvcOwAJAgANAAgJphvcOwAJAgAAAA==.Lindmajik:BAAALgAECgQJBgAAAA==.Liori:BAAALgAECgcJEgAAAA==.Lirillïa:BAAALgADCggJDQABLgAECggJKgANAKYbAA==.',
Ll='Llyana:BAAALgAECgcJBwABLgAECgkJQgAJADEgAA==.',
Lo='Lodestone:BAAALgADCgMJAwAAAA==.Loena:BAABLgAECn8iAAINAAkJXiNPCgAMAwANAAkJXiNPCgAMAwAAAA==.Lokk:BAAALgAECgYJCQABLgAECgYJDwAEAAAAAA==.Lovelydread:BAAALgAECgQJBQAAAA==.',
Lu='Lunabug:BAACLgAFFH8HAAILAAMJowsmJAC7AAALAAMJowsmJAC7AAAuAAQKfygAAgsACAl8HXgaANABAAsACAl8HXgaANABAAAA.Lupinos:BAAALgADCgYJCAAAAA==.',
Ly='Lyada:BAAALgAECgUJBQAAAA==.Lyadra:BAABLgAECn8wAAIIAAkJuB6YBQAUAwAIAAkJuB6YBQAUAwAAAA==.Lyandre:BAACLgAFFH8NAAMIAAUJhApREwAWAQAIAAUJhApREwAWAQAGAAQJSQG8MQCuAAAuAAQKfx4AAwgACAlGE4MWACgCAAgACAlGE4MWACgCAAYAAQnAEOxvADUAAAAA.Lydra:BAAALgAECgUJBQAAAA==.Lynna:BAAALgADCgQJBAAAAA==.Lyntoo:BAAALgAECgIJAQAAAA==.Lyntu:BAAALgAECgEJAQAAAA==.Lyrissa:BAAALgAECgUJBQAAAA==.',
['Lú']='Lúffy:BAAALgAECgcJBwABLgAECgkJJgAOAEAjAA==.',
Ma='Maania:BAAALgADCgEJAQAAAA==.Madan:BAABLgAECn8eAAITAAYJuQVl3QDMAAATAAYJuQVl3QDMAAAAAA==.Malasminna:BAAALgADCgYJBgAAAA==.Malehorelock:BAAALgAECgYJBwABLgAECggJLAAZAB8hAA==.Malicioun:BAAALgADCgEJAQAAAA==.Malkariss:BAABLgAECn83AAMVAAgJpyBPHwCcAgAVAAgJpyBPHwCcAgAlAAEJ5AjgHAA5AAAAAA==.Mammadruid:BAABLgAECn87AAMhAAkJtg1GHABYAQAhAAkJtg1GHABYAQAFAAYJpwuRbwDcAAAAAA==.Manbearetc:BAAALgAECgMJAwAAAA==.Maralen:BAAALgADCgcJCQAAAA==.Marann:BAAALgAECgEJAQAAAA==.Matadør:BAAALgAECgcJDAAAAA==.Mathwhiz:BAABLgAECn8VAAMiAAYJMRdiOwBPAQAiAAYJMRdiOwBPAQANAAMJmgVKCwGAAAABLgAECgkJMQAQAEIYAA==.Mauldis:BAABLgAECn84AAIRAAgJKg3SOABEAQARAAgJKg3SOABEAQAAAA==.Mavgard:BAAALgAECgIJAgAAAA==.Mavgards:BAAALgADCgMJAwABLgAECgIJAgAEAAAAAA==.Maxrebo:BAABLgAECn8eAAIaAAgJoBtFEgAaAgAaAAgJoBtFEgAaAgAAAA==.',
Me='Meatwàd:BAAALgAECgYJCAAAAA==.Mekanzi:BAAALgAECgQJDAAAAA==.Meliõdas:BAAALgAECgUJEQAAAA==.Merebels:BAAALgAECgQJBwABLgAECggJCwAEAAAAAA==.Merkodisco:BAAALgAECgIJAgAAAA==.',
Mi='Miaka:BAABLgAECn89AAICAAkJ4xwWAgC0AgACAAkJ4xwWAgC0AgAAAA==.Miakah:BAAALgAECgUJCgAAAA==.Midwest:BAAALgADCgQJBAAAAA==.Minirook:BAAALgADCgEJAQABLgAFFAYJGwATANUbAA==.Misfire:BAABLgAECn89AAIUAAkJnRVlKAAyAgAUAAkJnRVlKAAyAgAAAA==.Mistbusters:BAAALgAECgYJDgAAAA==.Mithra:BAAALgAECgEJAQAAAA==.Mithygos:BAABLgAECn8ZAAIJAAgJWwR5TwDkAAAJAAgJWwR5TwDkAAAAAA==.Mito:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.',
Mo='Moar:BAAALgAECgEJAgAAAA==.Moghroth:BAABLgAECn87AAMMAAkJxg3fJACXAQAMAAkJvg3fJACXAQAhAAEJQwvDcgAjAAAAAA==.Molykote:BAAALgAECgMJBgAAAA==.Monks:BAAALgAFFAIJAgAAAA==.Morgiana:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.',
My='Myhiknee:BAAALgADCgUJCAAAAA==.Myriana:BAAALgAECgQJBwAAAA==.Mystyle:BAAALgADCgcJBwAAAA==.',
['Má']='Mágnus:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâsterdon:BAAALgAECgYJDwAAAA==.',
['Mã']='Mãtador:BAAALgAECgEJAgAAAA==.',
Na='Nahryn:BAABLgAECn83AAIFAAgJ8R7JEQC2AgAFAAgJ8R7JEQC2AgAAAA==.Najamei:BAAALgADCgUJBQAAAA==.Najanira:BAAALgADCgYJBgAAAA==.Narya:BAAALgAECgIJAwAAAA==.',
Ne='Nella:BAAALgAECgYJCQABLgAFFAMJBQAYAKkTAA==.Nerbert:BAAALgADCgYJBgABLgAECgkJJwAJAAgVAA==.Neretsym:BAABLgAECn8tAAIUAAkJMiDYFgCSAgAUAAkJMiDYFgCSAgAAAA==.Nevercumdin:BAAALgADCgEJAwAAAA==.',
Ni='Nibbzz:BAACLgAFFH8KAAIGAAUJlwXmIAAmAQAGAAUJlwXmIAAmAQAuAAQKfx0AAgYACQl1FMAeAMoBAAYACQl1FMAeAMoBAAAA.Nineva:BAABLgAECn8jAAIFAAkJ/QOiZQD6AAAFAAkJ/QOiZQD6AAAAAA==.',
No='Nobas:BAABLgAECn9GAAMMAAkJVgtpKQB5AQAMAAkJVgtpKQB5AQAFAAEJ6wJ05AAhAAAAAA==.',
Nu='Nugs:BAAALgAECgkJBQAAAA==.',
Ok='Okelani:BAAALgAECgEJAQAAAA==.',
On='Onlyfeet:BAAALgAECgMJBgAAAA==.',
Op='Oppgjør:BAABLgAECn8WAAIiAAkJ3RhmDwCXAgAiAAkJ3RhmDwCXAgAAAA==.',
Or='Oreeree:BAAALgAECgYJBwAAAA==.Orenge:BAAALgAECgQJCAAAAA==.Orkus:BAAALgADCgkJCwAAAA==.Ormr:BAABLgAECn8nAAIJAAkJCBUxHgDeAQAJAAkJCBUxHgDeAQAAAA==.Orpsa:BAAALgADCgYJBgAAAA==.',
Os='Osteo:BAABLgAECn8uAAQCAAgJDwcLEwAoAQACAAgJyAYLEwAoAQAQAAgJXgT2nQD+AAABAAcJCALAPwC1AAAAAA==.',
Ou='Ouron:BAABLgAECn8mAAMcAAgJwBU5NgDKAQAcAAcJUxY5NgDKAQARAAYJtQxFZACyAAAAAA==.',
Pa='Papashrimps:BAACLgAFFH8eAAIVAAUJ5RusSABJAQAVAAUJ5RusSABJAQAuAAQKfzkAAhUACQl1IiAPAPwCABUACQl1IiAPAPwCAAAA.',
Pe='Perash:BAAALgAECgEJAQAAAA==.',
Ph='Phrazes:BAAALgAECgQJBAAAAA==.',
Pi='Pikyu:BAAALgADCgEJAQAAAA==.',
Pl='Placeholder:BAABLgAECn8yAAIbAAkJeBzDBQCFAgAbAAkJeBzDBQCFAgAAAA==.Plaguestingr:BAABLgAECn9EAAIUAAkJDSSuBwAYAwAUAAkJDSSuBwAYAwAAAA==.',
Po='Pontifex:BAABLgAECn8rAAIIAAkJOxkkDACXAgAIAAkJOxkkDACXAgAAAA==.Portandmorph:BAABLgAECn8wAAIVAAkJ5hWENwA0AgAVAAkJ5hWENwA0AgAAAA==.Potlock:BAAALgAECgUJDgAAAA==.',
Pr='Prayinmantís:BAAALgADCgkJCQAAAA==.Proey:BAABLgAECn9DAAMHAAkJAhnFDgBlAgAHAAkJAhnFDgBlAgAGAAUJJhNRPQAJAQAAAA==.Prone:BAABLgAECn9GAAMcAAkJbw5GOgC4AQAcAAkJbw5GOgC4AQARAAEJdAYaogAqAAAAAA==.',
Ps='Psychokiller:BAAALgADCgYJBgAAAA==.',
Pu='Puf:BAAALgAECgMJBwAAAA==.Puipui:BAAALgADCgEJAQAAAA==.Pumpidan:BAAALgAECgIJBQAAAA==.',
Py='Pyrelyn:BAAALgADCgEJAQAAAA==.',
Qr='Qròw:BAAALgADCgMJAwAAAA==.',
Qu='Quinnifred:BAAALgAECgQJBgAAAA==.',
Ra='Raakotah:BAABLgAECn9JAAIMAAkJKSVyAgBIAwAMAAkJKSVyAgBIAwAAAA==.Raelo:BAABLgAECn8vAAIgAAkJpxP1CQAPAgAgAAkJpxP1CQAPAgAAAA==.Raiseurmug:BAABLgAECn8pAAIaAAkJRhOWFwDjAQAaAAkJRhOWFwDjAQAAAA==.Rakash:BAACLgAFFH8SAAITAAUJBhvNTABIAQATAAUJBhvNTABIAQAuAAQKfywAAhMACQmTIK0gAL8CABMACQmTIK0gAL8CAAAA.Rarg:BAAALgAFFAIJAgABLgAFFAYJEAASAOkbAA==.Rascaldragon:BAAALgAECgQJBQAAAA==.Ravenlark:BAABLgAECn8ZAAIQAAkJigaEdABMAQAQAAkJigaEdABMAQAAAA==.Ravia:BAABLgAECn8mAAMOAAkJQCOMCAADAwAOAAkJqyKMCAADAwAWAAUJUiE4CQDdAQAAAA==.Razuki:BAAALgAECgYJEwABLgAFFAQJCQAiAOIQAA==.',
Re='Reddale:BAAALgADCgcJDAAAAA==.Redeamer:BAAALgAECgEJAgAAAA==.Resco:BAACLgAFFH8nAAIXAAgJIRftAgA1AgAXAAgJIRftAgA1AgAuAAQKfz0AAhcACQkDJaoEABIDABcACQkDJaoEABIDAAAA.Rescotwo:BAAALgAECgYJDgAAAA==.',
Ri='Riddle:BAABLgAECn8aAAIcAAkJcgescwDxAAAcAAkJcgescwDxAAAAAA==.Rimeouo:BAAALgADCgEJAQAAAA==.Rize:BAAALgAECgMJAwABLgAECgkJLAAJAC8TAA==.',
Ro='Rocksolid:BAAALgADCgUJBgAAAA==.Ronnie:BAAALgAECgQJBwAAAA==.Rook:BAACLgAFFH8bAAMTAAYJ1RvQLwCMAQATAAUJ1RvQLwCMAQADAAEJAAAKXQAAAAAuAAQKfykAAhMACAkTIykXAPACABMACAkTIykXAPACAAAA.Rookmonger:BAAALgAECgUJBQABLgAFFAYJGwATANUbAA==.Rosenrott:BAAALgAFFAIJAwAAAA==.Rosepiercer:BAABLgAECn82AAIUAAkJhyOPBwAZAwAUAAkJhyOPBwAZAwAAAA==.Rosies:BAAALgAECgUJBwAAAA==.Rouz:BAABLgAECn8cAAIfAAYJeA98DwAHAQAfAAYJeA98DwAHAQAAAA==.',
Ry='Ryenoh:BAAALgADCgYJBgAAAA==.Ryoto:BAACLgAFFH8ZAAMJAAUJTiRGFgCVAQAJAAQJ5iNGFgCVAQAfAAMJZyJgCgBoAAAuAAQKfxwAAwkACQmHJV0YAAwCAAkACQmHJV0YAAwCAB8AAwkXJCMmAPIAAAAA.',
Sa='Sadness:BAAALgADCgYJBwAAAA==.Saelyz:BAAALgADCgQJBAAAAA==.Saetha:BAABLgAECn8UAAIjAAgJtAzTGAA3AQAjAAgJtAzTGAA3AQAAAA==.Samandean:BAABLgAECn88AAIPAAkJHhe/DQA4AgAPAAkJHhe/DQA4AgAAAA==.Santhallibar:BAABLgAECn8nAAImAAkJeQMdEQAIAQAmAAkJeQMdEQAIAQAAAA==.Sarasvati:BAABLgAECn8nAAIFAAkJoxqnEADEAgAFAAkJoxqnEADEAgAAAA==.Saster:BAABLgAECn8hAAITAAkJgiJYDQD6AgATAAkJgiJYDQD6AgAAAA==.Sathrel:BAAALgADCgIJAgABLgAECgkJBwAEAAAAAA==.',
Sc='Scrabs:BAAALgAECgkJDwAAAA==.',
Se='Sellena:BAABLgAECn8tAAIgAAkJMRQLCgANAgAgAAkJMRQLCgANAgABLgAECgkJPAAPAB4XAA==.Sementha:BAAALgADCgcJDgABLgAECgYJCQAEAAAAAA==.Senpai:BAABLgAECn8UAAIYAAYJyRxQIQCpAQAYAAYJyRxQIQCpAQABLgAFFAcJHQAFAJ8cAA==.Sephyra:BAAALgAECgkJEAAAAA==.',
Sh='Shadowmyst:BAAALgADCgQJCgAAAA==.Shaken:BAAALgAECgIJAgAAAA==.Shandow:BAACLgAFFH8ZAAIVAAUJqxwoRgBOAQAVAAUJqxwoRgBOAQAuAAQKf0YAAhUACQlfJJkFAFQDABUACQlfJJkFAFQDAAAA.Shango:BAAALgADCgcJCQAAAA==.Shanshunt:BAAALgAECgYJCAABLgAFFAUJGQAVAKscAA==.Shansoracle:BAACLgAFFH8XAAIIAAUJOBp1CQCaAQAIAAUJOBp1CQCaAQAuAAQKfyEAAggACQlhH9oDAEMDAAgACQlhH9oDAEMDAAEuAAUUBQkZABUAqxwA.Shed:BAACLgAFFH8RAAIRAAUJUx9lEwBqAQARAAUJUx9lEwBqAQAuAAQKfy0AAhEACAltIZYNAMgCABEACAltIZYNAMgCAAAA.Sheislegend:BAABLgAECn8XAAIIAAcJthWzHwC4AQAIAAcJthWzHwC4AQAAAA==.Shelby:BAABLgAECn80AAMIAAkJERqQDgBvAgAIAAkJERqQDgBvAgAHAAUJcRC8PQASAQAAAA==.Shmoon:BAEALgAECgIJAgABLgAECgUJBgAEAAAAAA==.Shmuckman:BAAALgADCgkJEwAAAA==.Shorttotem:BAAALgADCgUJBQAAAA==.Shoty:BAAALgAECgMJAwABLgAFFAYJGwATANUbAA==.',
Si='Siccinok:BAABLgAECn8vAAIVAAgJlRV3WQDLAQAVAAgJlRV3WQDLAQAAAA==.Silicá:BAAALgADCgkJCQABLgAECgEJAQAEAAAAAA==.Sindorian:BAABLgAECn8sAAMZAAgJHyGnCQB/AgAZAAgJUR+nCQB/AgAUAAYJHSIRJwAdAgAAAA==.Sink:BAAALgADCgIJAgAAAA==.Sithlord:BAAALgADCgMJAwAAAA==.',
Sk='Skrimphorn:BAAALgAECgEJAQAAAA==.',
Sl='Slimped:BAAALgAECgcJDgAAAA==.',
Sm='Smurricane:BAAALgAECgUJCAAAAA==.',
Sn='Snowybato:BAAALgAECgQJDQAAAA==.',
So='Solanwarr:BAABLgAECn88AAQSAAkJTCPaAgAKAwASAAkJKCLaAgAKAwAXAAgJ6B3CFwCOAgAnAAMJnRl6TwCEAAAAAA==.Solar:BAAALgAECgQJCAAAAA==.Solarial:BAAALgAECgUJEgAAAA==.Solastra:BAABLgAECn81AAIiAAgJbRtxEACKAgAiAAgJbRtxEACKAgAAAA==.Sommer:BAAALgAECgUJBQABLgAECgkJQwAMAFoVAA==.Soramai:BAAALgADCgcJDwAAAA==.Soth:BAABLgAECn9EAAMTAAkJtRklJgBiAgATAAkJtRklJgBiAgADAAkJQw97GQCJAQAAAA==.',
Sp='Sparticusdru:BAABLgAECn8WAAIjAAkJih09BwBXAgAjAAkJih09BwBXAgAAAA==.Spore:BAAALgAECgMJAwAAAA==.',
Sq='Sqaw:BAAALgAECgEJAQAAAA==.',
St='Starkadia:BAAALgAECgYJBgAAAA==.Staryxia:BAACLgAFFH8eAAMKAAUJIxoJCgA2AQAKAAQJIxoJCgA2AQADAAEJAADAQQAAAAAuAAQKfy0AAgoACQmhIUsBAPYCAAoACQmhIUsBAPYCAAAA.Steamdruid:BAAALgAECgYJEQAAAA==.Stonecookies:BAABLgAECn8hAAMQAAkJKgn5ZQBtAQAQAAkJPQj5ZQBtAQABAAUJ7AYySQCTAAAAAA==.Stonecross:BAAALgAECgYJCgAAAA==.Stonehard:BAAALgAECgEJAQAAAA==.Stoneldo:BAAALgADCgEJAQAAAA==.Stonetotem:BAAALgAECgYJDAAAAA==.Stormbolt:BAABLgAECn9DAAIMAAkJWhXBFAAgAgAMAAkJWhXBFAAgAgAAAA==.Stormspirit:BAAALgADCgkJEAAAAA==.Striggen:BAABLgAECn8YAAMNAAYJtA850gDjAAANAAUJexE50gDjAAAbAAUJDwkENwB2AAAAAA==.',
Su='Succystrazsa:BAAALgADCgIJAgAAAA==.Sugarsham:BAABLgAECn8VAAQcAAcJrhOOPACuAQAcAAcJrhOOPACuAQARAAYJ9QadYQCwAAAgAAQJjgNVJgByAAAAAA==.Sulwen:BAACLgAFFH8UAAIMAAgJRCLvAAA9AgAMAAgJRCLvAAA9AgAuAAQKfyAAAgwACQmQJvwEAFEDAAwACQmQJvwEAFEDAAAA.Sumerset:BAAALgAECgMJBgAAAA==.Sunnydee:BAAALgAECggJCwAAAA==.Supaflytnt:BAAALgAECgUJCAAAAA==.Sustia:BAABLgAECn8VAAIoAAgJ1wrcCwBNAQAoAAgJ1wrcCwBNAQAAAA==.',
Sy='Syrelina:BAAALgAECgQJBAABLgAECgkJJgAOAEAjAA==.',
Ta='Tacopie:BAAALgAECgQJBgAAAA==.Taera:BAACLgAFFH8FAAIYAAMJqRPcMQDEAAAYAAMJqRPcMQDEAAAuAAQKfzcAAhgACQmtIvgDAGsDABgACQmtIvgDAGsDAAAA.Taika:BAAALgADCgkJDwAAAA==.Tailchaser:BAAALgADCgcJBwAAAA==.Talanazar:BAABLgAECn86AAQJAAkJFSCEBQABAwAJAAkJFSCEBQABAwAfAAYJgR2AFAChAQAkAAMJ0A4zKQCWAAAAAA==.Talavenn:BAABLgAECn8mAAIOAAgJHRWGQAC8AQAOAAgJHRWGQAC8AQAAAA==.Tallish:BAABLgAECn8iAAIOAAkJ6wxVlgDmAAAOAAkJ6wxVlgDmAAAAAA==.Tarage:BAAALgAECgIJAgAAAA==.Taterchip:BAABLgAECn8lAAMXAAYJSxmvOABcAQAXAAYJ9RivOABcAQASAAIJvRZiOQCBAAAAAA==.Taylia:BAAALgAECgQJBgAAAA==.',
Te='Teaorix:BAAALgADCgQJBAAAAA==.Teds:BAAALgADCgUJBQAAAA==.Temporary:BAAALgADCgYJBgAAAA==.Tempus:BAABLgAECn8VAAINAAgJ9AQvvQAAAQANAAgJ9AQvvQAAAQAAAA==.Teradoxx:BAAALgAECgYJDgAAAA==.Teriko:BAABLgAECn8/AAMTAAkJ3h7hFwCvAgATAAkJ3h7hFwCvAgADAAcJKgqOLgDeAAAAAA==.Terran:BAAALgAECgEJAQABLgAECggJOQAOAMUeAA==.Teviro:BAAALgAECgUJBgABLgAECgkJRgAZAEkhAA==.',
Th='Thanks:BAAALgAECgEJAQAAAA==.Thequixote:BAAALgADCgEJAQAAAA==.Therizino:BAAALgADCgQJBAAAAA==.Thrashy:BAAALgAECgQJCAAAAA==.Thrum:BAAALgAECgEJAQAAAA==.',
Ti='Tinkerballa:BAAALgAECgEJAQAAAA==.',
To='Toxictotes:BAAALgAECgIJBAAAAA==.',
Tw='Twiddleado:BAABLgAECn9AAAIVAAkJDRjAMABPAgAVAAkJDRjAMABPAgAAAA==.Twinkie:BAAALgAECggJCAABLgAECgkJJgAOAEAjAA==.Twinkle:BAAALgADCgEJAQAAAA==.',
Ty='Ty:BAAALgAFFAEJAQAAAA==.Tylor:BAAALgAECgYJDwAAAA==.',
['Tå']='Tåkete:BAAALgAECgYJCwAAAA==.',
Uk='Ukuindadookr:BAAALgADCgYJBgAAAA==.',
Um='Ume:BAAALgAECgEJAQABLgAECgMJBwAEAAAAAA==.',
Un='Unta:BAAALgAECgYJCQAAAA==.',
Va='Valaera:BAAALgAECgcJDwAAAA==.Valenora:BAABLgAECn8dAAIBAAkJ4BzHAgB4AgABAAkJ4BzHAgB4AgAAAA==.Valise:BAABLgAECn8jAAICAAYJrwTJHADHAAACAAYJrwTJHADHAAAAAA==.Varielle:BAAALgAECgYJCQAAAA==.Varuz:BAAALgAECgUJBwABLgAECgYJDwAEAAAAAA==.Varyz:BAAALgAECgUJBQABLgAECgYJDwAEAAAAAA==.Vaticamt:BAAALgAECgUJBQAAAA==.',
Ve='Vecxx:BAAALgADCgUJBQAAAA==.Velanie:BAAALgAECggJDgAAAA==.Velanise:BAAALgADCgMJAwAAAA==.Velight:BAAALgADCgEJAQAAAA==.Velinara:BAAALgAECgEJAQAAAA==.Velindroz:BAAALgAECgMJBgAAAA==.Veloras:BAAALgAECgEJAQAAAA==.Verene:BAABLgAECn8oAAIcAAkJEhaAHwBGAgAcAAkJEhaAHwBGAgAAAA==.Verinari:BAAALgAECgQJBAAAAA==.',
Vi='Vibes:BAAALgAECgkJBQAAAA==.Viperc:BAEALgADCgMJAwABLgAECgYJGgACAPkEAA==.Vipul:BAAALgAECgEJAgABLgAECgYJDgAEAAAAAA==.Viridria:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.Virridian:BAABLgAECn9EAAIUAAkJlyAHCwDzAgAUAAkJlyAHCwDzAgAAAA==.Virrigosa:BAAALgADCgcJBwAAAA==.Vistia:BAAALgADCgEJAQAAAA==.',
Vl='Vlado:BAAALgAECgEJAQAAAA==.',
Vo='Vodalus:BAAALgADCgUJBQAAAA==.Voideria:BAAALgAECgQJBgAAAA==.Voolock:BAAALgADCggJCQAAAA==.',
Vy='Vyshana:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.',
Wa='Wallofshame:BAABLgAECn8qAAMiAAkJxh3pDAC3AgAiAAkJxh3pDAC3AgANAAQJXg6N3gDTAAAAAA==.Walt:BAAALgADCgIJAgAAAA==.Warchef:BAAALgADCgYJCgABLgAECggJNwAVAKcgAA==.Warriorclaps:BAAALgADCggJDgAAAA==.Wartooth:BAABLgAECn85AAMBAAgJ0h1CAwBbAgABAAgJ0h1CAwBbAgAQAAUJcBM5hgAoAQAAAA==.Wassergott:BAAALgADCgIJAgAAAA==.',
We='Webicus:BAABLgAECn8mAAISAAkJ1BNTEQDHAQASAAkJ1BNTEQDHAQAAAA==.Weezzer:BAAALgADCgQJBAAAAA==.Wendee:BAABLgAECn80AAMIAAkJwAFMQwDOAAAIAAkJwAFMQwDOAAAHAAUJdQTkSwCoAAAAAA==.',
Wh='Whitefóx:BAACLgAFFH8QAAIbAAQJzxP0BgABAQAbAAQJzxP0BgABAQAuAAQKfx4AAhsACQmYG1kFAJACABsACQmYG1kFAJACAAEuAAUUBQkZABUAqxwA.Whitley:BAABLgAECn8tAAMcAAkJ5B++BgA6AwAcAAkJ5B++BgA6AwAgAAYJBhTjFwA5AQAAAA==.',
Wi='Wijing:BAAALgAECgIJAgAAAA==.',
Wo='Wolololo:BAAALgAECgEJAQABLgAECgkJIQATAIIiAA==.Wooden:BAAALgAECgEJAQAAAA==.Worldbreaker:BAAALgADCgEJAQAAAA==.',
['Wü']='Wülfsa:BAAALgAECgUJBQAAAA==.',
Xa='Xanthium:BAABLgAECn8jAAIIAAYJzwGqUQCGAAAIAAYJzwGqUQCGAAAAAA==.Xanzib:BAAALgADCgYJBgAAAA==.Xaphy:BAAALgAECgYJDwAAAA==.Xardots:BAABLgAECn8lAAIBAAgJohX5CgCCAQABAAgJohX5CgCCAQABLgAECgkJOAAEAAAAAA==.Xardral:BAAALgAECgQJBAABLgAECgkJOAAEAAAAAA==.',
Xe='Xeetali:BAAALgADCgYJBgAAAA==.',
Xi='Xiareth:BAABLgAECn85AAMkAAgJ7gtRFgBiAQAkAAgJ7gtRFgBiAQAfAAEJkAY8JwAqAAAAAA==.',
Xt='Xtronger:BAABLgAECn8gAAIFAAgJmRbCLgDgAQAFAAgJmRbCLgDgAQAAAA==.',
['Xá']='Xároth:BAAALgAECgkJOAAAAQ==.',
Ya='Yaddi:BAAALgAECgQJBgAAAA==.Yarrow:BAAALgADCgkJEgAAAA==.',
Ye='Yeeyee:BAABLgAECn8WAAIMAAgJuSElCgCoAgAMAAgJuSElCgCoAgAAAA==.',
Za='Zalik:BAAALgAECgMJAwAAAA==.',
Ze='Zeebo:BAAALgAECgcJEwAAAA==.Zest:BAABLgAECn8pAAMkAAkJ2BAXDQD4AQAkAAkJ2BAXDQD4AQAJAAIJkAhqdwBjAAAAAA==.',
Zm='Zmaryjane:BAAALgAECgIJBAAAAA==.',
Zo='Zorakfoghorn:BAAALgADCgIJAgAAAA==.Zorithic:BAAALgAECgQJAwAAAA==.Zorrak:BAAALgAECgQJBQAAAA==.',
Zu='Zulls:BAAALgAECgIJAgAAAA==.',
Zy='Zyde:BAAALgAECgYJDwAAAA==.',
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
