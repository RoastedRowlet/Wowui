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

local lookup = {'Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Unknown-Unknown','Druid-Restoration','Priest-Shadow','Priest-Discipline','Priest-Holy','Evoker-Augmentation','DeathKnight-Frost','Monk-Windwalker','Druid-Balance','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Shaman-Elemental','Warrior-Protection','DeathKnight-Unholy','Hunter-BeastMastery','Mage-Frost','DemonHunter-Vengeance','Druid-Guardian','Warrior-Fury','Monk-Mistweaver','Hunter-Survival','Monk-Brewmaster','Paladin-Protection','Shaman-Restoration','Mage-Fire','Rogue-Subtlety','Evoker-Devastation','Shaman-Enhancement','Paladin-Holy','Druid-Feral','Evoker-Preservation','Mage-Arcane','Rogue-Assassination','Warrior-Arms','Rogue-Outlaw',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Absens:BAABLgAECn8+AAMBAAkJwhLcCwB9AQABAAkJhw/cCwB9AQACAAgJ0hD6DQB3AQAAAA==.',
Ad='Adorian:BAAALgAFFAEJAQABLgAFFAQJFAADABMhAA==.Adwillon:BAAALgADCgQJBQABLgAECgYJEwAEAAAAAA==.',
Ae='Aedoril:BAAALgADCgEJAQAAAA==.Aellea:BAAALgADCgkJCQAAAA==.Aelyss:BAAALgADCgQJBAAAAA==.Aerosse:BAAALgAECgMJAwAAAA==.',
Af='Aforceofone:BAAALgAECgQJEQAAAA==.',
Ai='Airdreanna:BAAALgADCgQJBAAAAA==.',
Ak='Akama:BAAALgAECgcJDAABLgAFFAgJHgAFAOwZAA==.',
Al='Alivanllan:BAAALgAECgIJAgAAAA==.Alteisen:BAAALgAECgUJBQAAAA==.',
Am='Ambitious:BAAALgAECgMJCgAAAA==.Amerlinn:BAAALgAECgYJDAAAAA==.',
An='Anamuht:BAABLgAECn8eAAQGAAkJCRUxFwAOAgAGAAkJCRUxFwAOAgAHAAgJeBMsGgD8AQAIAAYJHhD8MwAxAQABLgAECgkJPAAJAFsiAA==.Andryn:BAAALgAECgEJAQAAAA==.Annaday:BAABLgAECn8lAAIDAAkJgQ2BIABMAQADAAkJgQ2BIABMAQAAAA==.Antiock:BAACLgAFFH8UAAMDAAQJEyHjEABwAQADAAQJEyHjEABwAQAKAAQJVBOcDQAmAQAuAAQKfzAAAwMACQn8I30EAOoCAAMACQn8I30EAOoCAAoABwnRHFkKANUBAAAA.Anyaesthesia:BAAALgADCgYJBgAAAA==.Anyamonka:BAABLgAECn8YAAILAAYJWRpSJgB/AQALAAYJWRpSJgB/AQAAAA==.',
Ap='Apocalich:BAAALgAECgUJBQAAAA==.Appalachia:BAAALgAECgUJBQAAAA==.',
Aq='Aquenia:BAAALgADCggJDAAAAA==.',
Ar='Aralaith:BAABLgAECn8lAAIGAAgJcCXuBwDQAgAGAAgJcCXuBwDQAgABLgAFFAgJFAAMAEQiAA==.Argonaut:BAAALgAECgIJAgAAAA==.Argul:BAAALgAECgIJAgAAAA==.Ariea:BAAALgADCgYJBgAAAA==.Artoriá:BAAALgAECgEJAQAAAA==.Artto:BAABLgAECn8wAAINAAgJ9w9UeQB5AQANAAgJ9w9UeQB5AQAAAA==.',
As='Asevenhex:BAAALgAECgEJAQAAAA==.Ashbrínger:BAABLgAECn9HAAINAAkJDCYzAwBlAwANAAkJDCYzAwBlAwAAAA==.Association:BAAALgAECgMJAwAAAA==.Astrum:BAAALgAECgEJAgAAAA==.Asunã:BAAALgAECgIJAgABLgAECgEJAQAEAAAAAA==.',
Au='Aurah:BAAALgAECgIJBAAAAA==.',
Av='Averax:BAABLgAECn9BAAMOAAkJ2h+ECwDpAgAOAAkJ2h+ECwDpAgAPAAEJvQ2JbgA3AAAAAA==.Avyrax:BAAALgADCgcJDQABLgAECgkJQQAOANofAA==.',
Ay='Aybara:BAAALgADCgQJBAAAAA==.Aylakaye:BAAALgADCgMJAwAAAA==.Ayraena:BAABLgAECn8ZAAMMAAgJHQgCPQAYAQAMAAgJHQgCPQAYAQAFAAQJEgEwxgA9AAAAAA==.',
Az='Azkariel:BAAALgADCgQJBAAAAA==.Azyrieth:BAAALgADCgEJAQAAAA==.Azzathoth:BAAALgADCgcJDAAAAA==.',
Ba='Babyshoes:BAAALgAECgEJAQAAAA==.Backpack:BAAALgAECgUJBQAAAA==.Bakedtofu:BAABLgAECn8UAAMBAAYJ7wc9RwCZAAAQAAYJ7wcN0gCvAAABAAQJGQQ9RwCZAAAAAA==.Basement:BAAALgAECgMJAgABLgAFFAUJEgARAFMfAA==.Bashine:BAABLgAECn8VAAISAAYJVxlZGACTAQASAAYJVxlZGACTAQABLgAFFAcJHQATAPMeAA==.Baylohn:BAABLgAECn8lAAIUAAkJhRZQMgAPAgAUAAkJhRZQMgAPAgAAAA==.',
Be='Bearwrestler:BAABLgAECn8aAAIVAAgJ1Bc7YQC6AQAVAAgJ1Bc7YQC6AQABLgAFFAQJDwADAJAgAA==.Beefynugs:BAAALgAECgkJAgAAAA==.',
Bi='Bier:BAAALgAECgUJDgAAAA==.Bigrig:BAABLgAECn8YAAIUAAgJZQUvsgDZAAAUAAgJZQUvsgDZAAAAAA==.Bitterman:BAABLgAECn8zAAMQAAkJQhj1HwBjAgAQAAkJQhj1HwBjAgABAAEJww/ZcAA1AAAAAA==.',
Bj='Bjornvalion:BAAALgADCgQJBAAAAA==.',
Bl='Blackmage:BAAALgAECgEJAQAAAA==.Bladed:BAABLgAECn8mAAQWAAgJiBl9DgBlAQAOAAgJTxEmVQCEAQAWAAYJCht9DgBlAQAPAAQJFxKlQACvAAAAAA==.Blinkerfluid:BAAALgADCgIJAgAAAA==.Blinx:BAAALgADCgQJBAAAAA==.Bloodymess:BAABLgAECn8ZAAITAAgJQAq7gQBdAQATAAgJQAq7gQBdAQAAAA==.',
Bo='Bohikeog:BAAALgADCgYJBgAAAA==.Boogies:BAAALgADCgQJBwAAAA==.Bovinedivine:BAAALgAECgYJBgABLgAECgkJOQAEAAAAAA==.Bowyardee:BAAALgAECgEJAQAAAA==.',
Bu='Buffie:BAABLgAECn8ZAAINAAgJGhoeWADaAQANAAgJGhoeWADaAQAAAA==.Bullwyf:BAAALgADCgMJAwAAAA==.Bumblbeetuna:BAAALgAECgMJAwAAAA==.',
['Bá']='Bád:BAAALgADCggJDgABLgAECgYJFwAXADQOAA==.',
Ca='Calduu:BAAALgAECgQJCAAAAA==.Caledia:BAAALgAECgYJEQAAAA==.Callana:BAAALgADCgMJBQAAAA==.Camedra:BAABLgAECn9IAAIFAAkJlCQWAgCyAwAFAAkJlCQWAgCyAwAAAA==.Carinancey:BAAALgAECgQJBQAAAA==.Carperoni:BAAALgADCgcJBwAAAA==.Casseous:BAAALgADCgUJBwAAAA==.Castrada:BAAALgAECgUJBQABLgAECgkJTQANAHYZAA==.Catamynyia:BAABLgAECn8kAAIUAAkJpQ7TRwDFAQAUAAkJpQ7TRwDFAQAAAA==.Caylaetal:BAAALgAECgEJAQAAAA==.',
Cc='Cchaos:BAAALgAECgIJBgAAAA==.',
Ce='Celaborn:BAABLgAECn8dAAIYAAkJ/hyiGwAPAgAYAAkJ/hyiGwAPAgAAAA==.Celice:BAAALgAECgcJBwABLgAFFAMJBwAZANMTAA==.Cerwan:BAAALgADCgMJAwAAAA==.',
Ch='Chazaraz:BAABLgAECn8+AAMaAAkJVxG8EgATAgAaAAkJABG8EgATAgAUAAgJEgjxiAAoAQAAAA==.Chazsquatch:BAAALgAECgUJCgABLgAECgkJPgAaAFcRAA==.Chevy:BAAALgAECgEJAwAAAA==.Chifreak:BAAALgAFFAIJAgABLgAECgkJJgAOAEAjAA==.Chillmourne:BAAALgAECgcJEwABLgAECggJFgABAJIIAA==.Chimaira:BAAALgADCgIJAgAAAA==.Chucknoris:BAAALgAECgQJCgAAAA==.Chugbuggins:BAAALgAECgYJEwAAAA==.',
Ci='Cindria:BAABLgAECn8lAAIVAAgJuBBPdwCHAQAVAAgJuBBPdwCHAQAAAA==.',
Cl='Clerks:BAAALgAECgIJAgAAAA==.Cliffgate:BAAALgADCgMJAwAAAA==.',
Co='Colaitis:BAAALgADCgIJAgAAAA==.Conduction:BAAALgAECgUJCAAAAA==.Corenthia:BAAALgAECgUJDQAAAA==.',
Cp='Cptbonez:BAAALgAECgYJEgABLgAECgkJMAAbAPQVAA==.',
Cr='Crankadin:BAAALgAECgEJAQABLgAECgIJBAAEAAAAAA==.Crankchi:BAAALgAECgEJAgABLgAECgIJBAAEAAAAAA==.Crazz:BAAALgADCgEJAQAAAA==.Crewz:BAAALgADCgQJBAAAAA==.Crooky:BAAALgADCgcJBwABLgAFFAYJGwATANUbAA==.Crucifiiks:BAAALgAFFAIJAgAAAA==.Cruciö:BAAALgAECgEJAQAAAA==.Crànk:BAAALgAECgIJBAAAAA==.Cránk:BAAALgAECgEJAQABLgAECgIJBAAEAAAAAA==.Crãnk:BAAALgAECgIJAgABLgAECgIJBAAEAAAAAA==.',
Cu='Curveball:BAAALgAECgkJEQABLgAECgkJMwAQAEIYAA==.',
Cy='Cyniar:BAAALgAECgcJDQAAAA==.',
Da='Dalearnhardt:BAAALgADCgcJDgABLgAECgcJEgAEAAAAAA==.Damerlin:BAABLgAECn8XAAMNAAgJjQ+vdgB+AQANAAgJjQ+vdgB+AQAcAAQJ+QNUPQBkAAAAAA==.Damzel:BAAALgAECgMJAwAAAA==.Darkhuntress:BAAALgAECgcJBwAAAA==.Darkstär:BAABLgAECn9IAAIDAAkJDh+nBgCyAgADAAkJDh+nBgCyAgAAAA==.Darkun:BAAALgAECgUJBQABLgAECgkJLQAJABsUAA==.Darkwood:BAAALgADCgEJAgAAAA==.Dauc:BAAALgADCgEJAQAAAA==.',
De='Deacon:BAABLgAECn9CAAQbAAkJNQiTMAA+AQAbAAkJvgaTMAA+AQALAAUJmgpGWwCkAAAZAAUJfQS9jAB2AAAAAA==.Deadmantooth:BAAALgADCgYJBgABLgAECgkJQgABAGUbAA==.Deardren:BAAALgAECgUJBQAAAA==.Deathgripbtw:BAAALgAECgMJAwAAAA==.Deathknights:BAAALgAFFAEJAQAAAA==.Deathtrol:BAAALgAECggJCQAAAA==.Deeanne:BAAALgAECgQJBwAAAA==.Deepdeuce:BAAALgAECgUJCQAAAA==.Deepfriar:BAABLgAECn9OAAMIAAkJ7iSOAQCiAwAIAAkJ7iSOAQCiAwAGAAcJMRQSLABzAQAAAA==.Deidra:BAAALgADCgMJAwAAAA==.Demonhunts:BAABLgAFFH8JAAIOAAUJfwjWVgDkAAAOAAUJfwjWVgDkAAAAAA==.Demonmore:BAABLgAECn8jAAMPAAgJxAvKKQAqAQAPAAgJ2ArKKQAqAQAWAAUJWQp1IACVAAAAAA==.Derailed:BAAALgAECgQJBwAAAA==.Dethwing:BAAALgAECgIJAgAAAA==.Devilfrost:BAAALgAECgEJAQABLgAECgMJBgAEAAAAAA==.Dewshine:BAAALgAECgYJCwAAAA==.',
Dh='Dhampir:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Dhgeek:BAAALgAECgQJCAAAAA==.',
Di='Diablognomis:BAABLgAECn8XAAILAAYJJRooJgCAAQALAAYJJRooJgCAAQAAAA==.Diarmac:BAAALgAECgcJDAABLgAECgkJTQAdAKYOAA==.Dingô:BAAALgAECgQJBgAAAA==.Dirtman:BAABLgAECn8sAAIRAAkJpByDEgBYAgARAAkJpByDEgBYAgAAAA==.',
Dk='Dkrise:BAAALgAECgMJAwABLgAECgkJLQAJABsUAA==.',
Dn='Dneoh:BAAALgAECgkJCAABLgAFFAMJCgAMAOciAA==.',
Do='Donald:BAAALgADCgQJBAAAAA==.Donny:BAABLgAECn8tAAMNAAgJsx3SLgBDAgANAAgJnx3SLgBDAgAcAAIJuhYzNwB/AAAAAA==.Doodyshamala:BAAALgAECgUJDgAAAA==.Dooky:BAAALgAECgYJBwABLgAFFAYJGwATANUbAA==.Doozey:BAACLgAFFH8OAAIOAAQJJxaRQQAcAQAOAAQJJxaRQQAcAQAuAAQKfykAAw4ACQniHnYbAGwCAA4ACQlaHnYbAGwCABYAAQnNE/IwADwAAAAA.Dorigis:BAAALgADCgkJNQABLgAECgkJJgASAE8jAA==.Dotdotdotded:BAABLgAECn8WAAIQAAgJuAV8lAATAQAQAAgJuAV8lAATAQAAAA==.',
Dr='Drewdog:BAABLgAECn87AAMaAAgJbBf7GQDPAQAaAAgJfxL7GQDPAQAUAAcJpxXSZAB2AQAAAA==.Droid:BAAALgAECgEJAgAAAA==.Drunkgerardo:BAAALgAECgQJBQAAAA==.Drunkzen:BAAALgAECgUJCAAAAA==.Druyesil:BAAALgAECgEJAgAAAA==.',
Du='Dubes:BAABLgAECn9DAAIVAAkJmhkJJwB8AgAVAAkJmhkJJwB8AgAAAA==.Dunbartian:BAAALgAECgcJCgAAAA==.Duskfang:BAAALgADCgUJAQAAAA==.',
['Dá']='Dárkthorn:BAAALgAECgIJBAAAAA==.',
['Dö']='Dökkálfar:BAAALgAECgEJAQAAAA==.',
Ea='Easybreezin:BAAALgAECgUJDAAAAA==.',
Ei='Eirote:BAABLgAECn9TAAIeAAkJhx0/AQCrAgAeAAkJhx0/AQCrAgAAAA==.',
El='Elarris:BAAALgAECgcJDAAAAA==.Eldari:BAABLgAECn8YAAIMAAgJ2hsVGwDvAQAMAAgJ2hsVGwDvAQAAAA==.Elem:BAACLgAFFH8PAAIdAAYJUwhMJwBCAQAdAAYJUwhMJwBCAQAuAAQKfyMAAh0ACAmcIFMYAFMCAB0ACAmcIFMYAFMCAAAA.Ellyssanna:BAAALgAECgMJBAAAAA==.Elm:BAAALgAECgYJEAAAAA==.Elyssaena:BAAALgAECgYJEgAAAA==.',
Em='Emiliachan:BAAALgAECgcJCwAAAA==.',
En='Enzojr:BAACLgAFFH8QAAIfAAQJqxtKFQBbAQAfAAQJqxtKFQBbAQAuAAQKf0QAAh8ACQlZJE8CADcDAB8ACQlZJE8CADcDAAAA.',
Ep='Ephixa:BAAALgAFFAIJAwAAAA==.',
Er='Eridanos:BAAALgADCgYJBgAAAA==.Erisiel:BAAALgAECgEJAQAAAA==.Eruelle:BAACLgAFFH8MAAIOAAQJICSAIQCjAQAOAAQJICSAIQCjAQAuAAQKfyEAAg4ACQneJaEBAHADAA4ACQneJaEBAHADAAEuAAUUCAkUAAwARCIA.Erzå:BAAALgAECgEJAgABLgAECgEJAQAEAAAAAA==.',
Ev='Evoke:BAABLgAECn8fAAMJAAgJgyF3CgDOAgAJAAgJdB93CgDOAgAgAAYJZyBaDQAEAgAAAA==.',
Ey='Eye:BAACLgAFFH8KAAIhAAQJBiE8CgAYAQAhAAQJBiE8CgAYAQAuAAQKfyAAAyEACQnRIDwHAFcCACEACQnRIDwHAFcCABEAAQmZDN2PACgAAAAA.',
['Eí']='Eís:BAAALgADCgYJCwAAAA==.',
Fa='Faeira:BAAALgAECgcJCQAAAA==.Faloril:BAAALgAECgQJCgAAAA==.Falsara:BAAALgAECgQJBAAAAA==.Faranth:BAABLgAECn9EAAIJAAkJJiFmBQAIAwAJAAkJJiFmBQAIAwAAAA==.Faronyr:BAAALgAECgEJAQAAAA==.',
Fe='Feer:BAAALgAECgQJAQAAAA==.Felboi:BAAALgAECgUJDgAAAA==.Felknight:BAAALgAECgUJBwAAAA==.Felorc:BAAALgAECgQJBwAAAA==.Felynne:BAAALgAECgcJEQAAAA==.Fenrík:BAAALgADCgIJAgAAAA==.Feo:BAABLgAECn8eAAIOAAkJexmOJgAvAgAOAAkJexmOJgAvAgAAAA==.Ferum:BAABLgAECn9aAAMFAAkJQCVsAQDEAwAFAAkJQCVsAQDEAwAMAAkJyRtJCwCdAgAAAA==.',
Fi='Fionnan:BAABLgAECn9HAAIXAAkJPg/LGQB6AQAXAAkJPg/LGQB6AQABLgAECgkJTQAdAKYOAA==.',
Fo='Forest:BAACLgAFFH8OAAQMAAUJjhQhIAAXAQAMAAUJjhQhIAAXAQAXAAIJtghqLwBZAAAFAAIJZwbtXwBXAAAuAAQKfy4AAwwACQl6HSkNAMYCAAwACQl6HSkNAMYCAAUAAwn3GylsAO0AAAAA.',
Fr='Fraoch:BAAALgAECgcJDAABLgAECgkJSAAMACYNAA==.Fretless:BAAALgADCgYJCgAAAA==.Frixley:BAAALgAFFAIJAgAAAA==.Friérén:BAAALgAECgEJBAABLgAECgEJAQAEAAAAAA==.Frostedrayne:BAAALgADCgUJBQAAAA==.Frostthrower:BAAALgAECgEJAgAAAA==.Fryeguy:BAAALgAECggJEwAAAA==.',
Fu='Funkysoup:BAAALgADCgYJBgAAAA==.',
Fy='Fyodor:BAAALgAECgIJBQAAAA==.',
['Fè']='Fèresha:BAAALgAECgkJEgAAAA==.',
['Fò']='Fòrced:BAAALgAECggJDQAAAA==.',
Ga='Gallium:BAABLgAECn8kAAIiAAkJIBhbFABpAgAiAAkJIBhbFABpAgAAAA==.Gazerbeam:BAAALgAFFAEJAQAAAA==.',
Ge='Geelock:BAAALgADCggJFgAAAA==.Gehena:BAAALgAFFAIJAgABLgAFFAIJAwAEAAAAAQ==.Gemsareyum:BAAALgAECgYJDgABLgAFFAcJQgAUAKIgAA==.Geode:BAAALgAECgUJBQAAAA==.Gesht:BAABLgAECn8dAAINAAkJVRBBcQCJAQANAAkJVRBBcQCJAQAAAA==.Getemwet:BAAALgAECgEJAQAAAA==.',
Gh='Ghostfreak:BAAALgAECgUJBgAAAA==.',
Gi='Gidgetz:BAAALgADCgMJAwAAAA==.',
Gl='Glamourkills:BAAALgADCgcJDQAAAA==.Gleipnir:BAAALgAECgMJBAAAAA==.',
Go='Gojirra:BAAALgAECgUJCQAAAA==.Goldenbell:BAAALgAECgUJBQAAAA==.Goof:BAABLgAECn82AAIiAAkJ9Q7CMQCNAQAiAAkJ9Q7CMQCNAQAAAA==.Goontas:BAAALgAECgMJBAAAAA==.',
Gr='Grimsheèper:BAAALgAECgMJBAAAAA==.Grish:BAABLgAECn8ZAAIhAAYJHgaeJADKAAAhAAYJHgaeJADKAAAAAA==.Griz:BAAALgAECgQJCAAAAA==.Grollnar:BAAALgAECgEJAQABLgAECgkJDwAEAAAAAA==.Grossevache:BAAALgAECgYJEAAAAA==.Gròws:BAAALgAECgkJBwAAAA==.',
Ha='Haddor:BAABLgAECn8sAAMcAAkJXBoSCABVAgAcAAkJXBoSCABVAgANAAEJWwQMtgElAAAAAA==.Haelexi:BAAALgAECgQJCgAAAA==.Halujoxar:BAAALgADCgcJDgABLgAECgkJOQAEAAAAAA==.Hamonkulous:BAAALgADCgcJCAAAAA==.Hankerin:BAAALgADCgcJCgAAAA==.Harandar:BAAALgAECgEJAQAAAA==.Harleÿquinn:BAAALgAECgEJAQAAAA==.Harpomage:BAAALgADCgcJCQAAAA==.Hatcher:BAAALgAECgEJAQAAAA==.Haunter:BAABLgAECn8iAAQTAAkJiiBPcwB7AQATAAYJLR9PcwB7AQADAAUJlR6ZIQBDAQAKAAIJrxsQJACqAAAAAA==.Hayleigh:BAACLgAFFH8eAAIFAAgJ7BmzBQCnAgAFAAgJ7BmzBQCnAgAuAAQKfzEAAgUACQmEItQFAFgDAAUACQmEItQFAFgDAAAA.',
He='Heimdallr:BAAALgAECgEJAQAAAA==.Heisenborg:BAAALgAECgUJBQAAAA==.Hellbreezy:BAAALgAECgkJEAAAAA==.Helldin:BAABLgAECn8nAAINAAYJ3hVRoAA0AQANAAYJ3hVRoAA0AQAAAA==.Hellenfeller:BAABLgAECn8nAAIPAAYJ9RUQJgBDAQAPAAYJ9RUQJgBDAQAAAA==.',
Hi='Hilitepriest:BAABLgAECn8bAAMHAAgJ0RmmFQApAgAHAAgJQBmmFQApAgAIAAIJ1BZvaACLAAAAAA==.Hittomi:BAAALgAECgYJBgAAAA==.',
Ho='Holific:BAABLgAECn9NAAINAAkJdhmiKABeAgANAAkJdhmiKABeAgAAAA==.Honeychild:BAAALgAECgYJCgAAAA==.Hotrodranger:BAAALgAECgcJEgAAAA==.Hottub:BAAALgAECgUJBQAAAA==.',
Hu='Huckleberry:BAAALgAECgUJBQAAAA==.Hut:BAABLgAFFH8MAAIMAAUJ9RWzHQAmAQAMAAUJ9RWzHQAmAQABLgAFFAUJEgARAFMfAA==.',
Hv='Hvac:BAABLgAECn87AAIVAAkJ9g2aYQC5AQAVAAkJ9g2aYQC5AQAAAA==.',
Hy='Hypearione:BAAALgADCgIJAgAAAA==.',
Ia='Ialan:BAAALgADCgQJBgAAAA==.',
Ic='Iceovo:BAAALgADCgEJAQAAAA==.Icycritties:BAABLgAECn8YAAIVAAYJehAlvQBoAQAVAAYJehAlvQBoAQAAAA==.',
Id='Idovoodew:BAAALgADCgUJCAAAAA==.',
Ih='Iheals:BAAALgAECgMJCQAAAA==.',
Il='Illidon:BAAALgADCgYJBgAAAA==.',
Im='Imjustadruid:BAAALgADCggJCwAAAA==.Immortal:BAABLgAECn8mAAMTAAkJBxk1JwBjAgATAAkJBxk1JwBjAgADAAcJtAwSKAARAQAAAA==.Implants:BAAALgADCggJCQAAAA==.',
In='Incarnate:BAAALgAECgcJEAAAAA==.Incarnated:BAACLgAFFH8RAAMTAAUJKxw1cgAZAQATAAQJYiE1cgAZAQAKAAMJoRLuEwDjAAAuAAQKfzMAAxMACQnIIxEOAPoCABMACQl3IxEOAPoCAAoAAwmBIt8UADEBAAAA.Inflammation:BAAALgADCgcJDwABLgAECgUJCAAEAAAAAA==.',
Ir='Irocc:BAAALgAECgUJEQAAAA==.Irís:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.',
Is='Ishankyou:BAAALgAECgEJAQAAAA==.Ispithotfire:BAAALgAECgMJAwAAAA==.Istara:BAAALgADCgcJDQABLgAFFAcJHgAVABIhAA==.',
Iu='Iu:BAAALgADCgEJAgAAAA==.',
Ja='Jackdowe:BAAALgAECgQJBAAAAA==.Jackfash:BAAALgADCgcJDQAAAA==.Jadecross:BAABLgAECn8WAAIZAAcJSxYEMgCpAQAZAAcJSxYEMgCpAQAAAA==.Jalenhunter:BAAALgADCgUJCAAAAA==.',
Je='Jedith:BAAALgAECgcJCQAAAA==.Jerambae:BAABLgAECn8YAAIeAAYJyBWYBACTAQAeAAYJyBWYBACTAQAAAA==.Jerryatric:BAABLgAECn8XAAINAAkJhQyHawCVAQANAAkJhQyHawCVAQAAAA==.',
Jk='Jkmno:BAAALgADCgcJBwAAAA==.',
Jo='Joelah:BAAALgAECgcJDwAAAA==.Joshua:BAAALgAECgYJDAAAAA==.',
Ju='Justincasê:BAAALgADCggJFQAAAA==.',
['Jâ']='Jây:BAAALgADCgQJBAAAAA==.',
Ka='Kalarian:BAAALgAECgMJAwAAAA==.Kalfeen:BAABLgAECn8gAAMXAAcJayFaCgA7AgAXAAcJayFaCgA7AgAjAAEJ+wbRWwAjAAAAAA==.Kallikan:BAABLgAECn80AAIXAAkJFhkxCgA+AgAXAAkJFhkxCgA+AgAAAA==.Kamidk:BAABLgAFFH8HAAITAAQJ1g0/xgCZAAATAAQJ1g0/xgCZAAABLgAFFAUJEAAOACAeAA==.Kanmojo:BAAALgADCgQJBQAAAA==.Kashume:BAABLgAECn8bAAIhAAkJngJTHgACAQAhAAkJngJTHgACAQAAAA==.Kasteen:BAAALgAECgUJEAAAAA==.Kazon:BAAALgADCgcJCgABLgAFFAQJFAADABMhAA==.Kaøs:BAAALgAECgEJAQAAAA==.',
Kd='Kdoggparker:BAAALgAECgIJAwAAAA==.',
Ke='Kementari:BAAALgAECgQJBQAAAA==.Kenner:BAAALgAECgEJAQAAAA==.Kenzaki:BAACLgAFFH8UAAINAAUJmQquVgD9AAANAAUJmQquVgD9AAAuAAQKfzgAAg0ACQl7GwgzADECAA0ACQl7GwgzADECAAAA.Kesha:BAAALgAECgYJBgABLgAECgkJNAAIABEaAA==.',
Kh='Khaosreborn:BAAALgAECgUJEAAAAA==.Khaotic:BAAALgADCgMJAwABLgADCgQJBAAEAAAAAA==.',
Ki='Kiiren:BAAALgAECgEJAQABLgAECgcJIAAXAGshAA==.Kilaaz:BAABLgAECn8VAAINAAUJzCR1ewB1AQANAAUJzCR1ewB1AQAAAA==.Kilaz:BAAALgADCgUJBQAAAA==.',
Kn='Knuts:BAACLgAFFH8HAAIbAAQJBRYhIwAaAQAbAAQJBRYhIwAaAQAuAAQKfxYAAhsACQlUGIQeAK8BABsACQlUGIQeAK8BAAAA.',
Ko='Korius:BAAALgAECgUJBQAAAA==.Ková:BAABLgAECn8mAAIUAAgJABptMwAKAgAUAAgJABptMwAKAgAAAA==.',
Kr='Krutesiq:BAAALgADCgkJCQAAAA==.',
Ku='Kuani:BAAALgAECgYJCQABLgAFFAMJBwAZANMTAA==.Kullman:BAAALgADCgYJCgAAAA==.Kungfupapa:BAAALgAECgQJCAAAAA==.Kungfurry:BAAALgAECgUJCAAAAA==.Kurobozu:BAAALgAECgUJCQABLgAECgkJPAAJAFsiAA==.Kutherrek:BAAALgAECgEJAQAAAA==.Kuubar:BAABLgAECn8lAAIKAAkJ/RX/CAD2AQAKAAkJ/RX/CAD2AQAAAA==.',
Ky='Kyian:BAAALgAECgMJAwAAAA==.',
La='Lacus:BAAALgAECgYJCAAAAA==.Ladaeze:BAAALgADCgIJAgAAAA==.Ladiesnutz:BAACLgAFFH8FAAIJAAUJ4RYwKAAlAQAJAAUJ4RYwKAAlAQAuAAQKfxoABCQACQm6HtcWAF4BACQABAnhH9cWAF4BAAkABwl6FJQxADsBACAABQlOG/cMADsBAAAA.Lalatiina:BAAALgAECgIJAgABLgAECgkJJgAOAEAjAA==.Law:BAAALgAECgEJAgABLgAFFAgJHgAFAOwZAA==.Laz:BAAALgADCgMJAwAAAA==.Lazerous:BAAALgADCgYJBgAAAA==.',
Le='Leafá:BAAALgAECgEJAgABLgAECgEJAQAEAAAAAA==.Lealoo:BAABLgAECn8wAAINAAgJHB18KwBRAgANAAgJHB18KwBRAgABLgAECgkJQwAPABAZAA==.Leghorn:BAAALgADCgIJAgABLgAECgcJIAAXAGshAA==.Legolard:BAABLgAECn8mAAMSAAkJTyMlAwAHAwASAAkJTyMlAwAHAwAYAAQJ7yDiRwAlAQAAAA==.Lever:BAAALgADCggJCQAAAA==.',
Li='Liath:BAABLgAECn8UAAIIAAYJGBnMIgCoAQAIAAYJGBnMIgCoAQAAAA==.Liathano:BAAALgAECgIJAgAAAA==.Lichtenberg:BAAALgAECgMJAwABLgAECgkJPAAJAFsiAA==.Lightsky:BAAALgADCgIJAQAAAA==.Lildèbbíe:BAABLgAECn8oAAIVAAgJMg1eewB+AQAVAAgJMg1eewB+AQAAAA==.Lilspoon:BAAALgADCgMJAwAAAA==.Liltrapstarx:BAAALgAECgQJCAAAAA==.Linddori:BAABLgAECn8uAAINAAkJPhndLwA/AgANAAkJPhndLwA/AgAAAA==.Lindmajik:BAAALgAECgQJBgAAAA==.Liori:BAABLgAECn8eAAINAAcJrAV53gDdAAANAAcJrAV53gDdAAAAAA==.Lirillïa:BAAALgADCggJDQABLgAECgkJLgANAD4ZAA==.',
Ll='Llyana:BAAALgAECgkJDgABLgAECgkJRAAJACYhAA==.',
Lo='Lodestone:BAAALgADCgMJAwAAAA==.Loena:BAABLgAECn8iAAINAAkJXiNpCwAIAwANAAkJXiNpCwAIAwAAAA==.Lokk:BAAALgAECgYJCQABLgAECgYJEAAEAAAAAA==.Lovelydread:BAAALgAECgUJBgAAAA==.',
Lu='Lunabug:BAACLgAFFH8HAAILAAMJowusJwCtAAALAAMJowusJwCtAAAuAAQKfygAAgsACAl8HaMbAM4BAAsACAl8HaMbAM4BAAAA.Lupinos:BAAALgADCgYJCAAAAA==.',
Ly='Lyada:BAAALgAECgUJBQAAAA==.Lyadra:BAABLgAECn83AAIIAAkJTx9uBQAhAwAIAAkJTx9uBQAhAwAAAA==.Lyandre:BAACLgAFFH8NAAMIAAUJhApVFQARAQAIAAUJhApVFQARAQAHAAQJSQHKNQCsAAAuAAQKfx4AAwgACAlGE4MWACgCAAgACAlGE4MWACgCAAcAAQnAEHJ2ADMAAAAA.Lydra:BAAALgAECgUJBQAAAA==.Lynna:BAAALgADCgQJBAAAAA==.Lyntoo:BAAALgAECgIJAQAAAA==.Lyntu:BAAALgAECgEJAQAAAA==.Lyrissa:BAAALgAECgcJDAAAAA==.',
['Lú']='Lúffy:BAAALgAECgcJBwABLgAECgkJJgAOAEAjAA==.',
Ma='Maania:BAAALgAECgUJBQAAAA==.Madan:BAABLgAECn8kAAITAAYJmAgi0QDkAAATAAYJmAgi0QDkAAAAAA==.Malasminna:BAAALgADCgYJBgAAAA==.Malehorelock:BAAALgAECgYJBwABLgAECggJMQAaAFUhAA==.Malicioun:BAAALgADCgEJAQAAAA==.Malkariss:BAABLgAECn9AAAMVAAkJNSE5DQANAwAVAAkJNSE5DQANAwAlAAEJ5AjgHAA5AAAAAA==.Mammadruid:BAABLgAECn9BAAMXAAkJDQ8JGgB4AQAXAAkJDQ8JGgB4AQAFAAYJpwsscgDbAAAAAA==.Manbearetc:BAAALgAECgMJAwAAAA==.Maralen:BAAALgADCgcJCQAAAA==.Marann:BAAALgAECgEJAQAAAA==.Matadør:BAAALgAECgcJDAAAAA==.Mathwhiz:BAABLgAECn8aAAMiAAYJMRcjPQBOAQAiAAYJMRcjPQBOAQANAAUJ7gxB5gDTAAABLgAECgkJMwAQAEIYAA==.Mauldis:BAABLgAECn9BAAIRAAkJ3wzaMAB3AQARAAkJ3wzaMAB3AQAAAA==.Mavgard:BAAALgAECgIJAgAAAA==.Mavgards:BAAALgADCgMJAwABLgAECgIJAgAEAAAAAA==.Maxrebo:BAABLgAECn8eAAIbAAgJoBsOEwAYAgAbAAgJoBsOEwAYAgAAAA==.',
Me='Meatwàd:BAAALgAECgYJCgAAAA==.Mekanzi:BAAALgAECgUJDQAAAA==.Meliõdas:BAAALgAECgUJEQAAAA==.Merebels:BAAALgAECgQJBwABLgAECggJDgAEAAAAAA==.Merkodisco:BAAALgAECgIJAgAAAA==.',
Mi='Miaka:BAABLgAECn8/AAICAAkJESEZAQD/AgACAAkJESEZAQD/AgAAAA==.Miakah:BAAALgAECgcJEQAAAA==.Midwest:BAAALgADCgQJBAAAAA==.Minirook:BAAALgADCgEJAQABLgAFFAYJGwATANUbAA==.Misfire:BAABLgAECn8/AAIUAAkJnRXBKwAqAgAUAAkJnRXBKwAqAgAAAA==.Mistbusters:BAABLgAECn8UAAIZAAYJxw5PWAAIAQAZAAYJxw5PWAAIAQAAAA==.Mithra:BAAALgAECgEJAQAAAA==.Mithygos:BAABLgAECn8ZAAIJAAgJWwR4UgDhAAAJAAgJWwR4UgDhAAAAAA==.Mito:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.',
Mo='Moar:BAAALgAECgEJAgAAAA==.Mogad:BAAALgAECgcJBwAAAA==.Moghroth:BAABLgAECn89AAMMAAkJxg13JgCWAQAMAAkJvg13JgCWAQAXAAEJQwvSewAiAAAAAA==.Molykote:BAAALgAECgQJCgAAAA==.Monks:BAAALgAFFAIJAgAAAA==.Morgiana:BAAALgAECgEJAgABLgAECgEJAQAEAAAAAA==.',
Mu='Murderevan:BAAALgAECgYJBgAAAA==.',
My='Myhiknee:BAAALgADCggJDQAAAA==.Myriana:BAAALgAECgQJBwAAAA==.Mystyle:BAAALgADCgcJBwAAAA==.',
['Má']='Mágnus:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâsterdon:BAAALgAECgYJDwAAAA==.',
['Mã']='Mãtador:BAAALgAFFAEJAQAAAA==.',
Na='Nahryn:BAABLgAECn9AAAIFAAkJ8R+zCAArAwAFAAkJ8R+zCAArAwAAAA==.Najamei:BAAALgADCgUJBQAAAA==.Najanira:BAAALgADCgYJBgAAAA==.Narya:BAAALgAECgIJAwAAAA==.',
Ne='Neia:BAAALgAECgEJAQAAAA==.Nella:BAAALgAECgYJCQABLgAFFAMJBwAZANMTAA==.Nerbert:BAAALgADCgYJBgABLgAECgkJJwAJAAgVAA==.Neretsym:BAABLgAECn8vAAIUAAkJMiDzGACLAgAUAAkJMiDzGACLAgAAAA==.Nevercumdin:BAAALgADCgEJAwAAAA==.',
Ni='Nibbzz:BAACLgAFFH8KAAIHAAUJlwUBJAAjAQAHAAUJlwUBJAAjAQAuAAQKfx0AAgcACQl1FJ8gAMcBAAcACQl1FJ8gAMcBAAAA.Nineva:BAABLgAECn8jAAIFAAkJ/QNYaAD5AAAFAAkJ/QNYaAD5AAAAAA==.',
No='Nobas:BAABLgAECn9IAAMMAAkJJg1bJwCQAQAMAAkJJg1bJwCQAQAFAAEJ6wJ05AAhAAAAAA==.',
Nu='Nugs:BAAALgAECgkJBQAAAA==.',
Ok='Okelani:BAAALgAECgEJAQAAAA==.',
On='Onlyfeet:BAAALgAECgMJBgAAAA==.',
Op='Oppgjør:BAABLgAECn8WAAIiAAkJ3RgxEACVAgAiAAkJ3RgxEACVAgAAAA==.',
Or='Oreeree:BAAALgAECgYJBwAAAA==.Orenge:BAAALgAECgQJCAAAAA==.Orkus:BAAALgADCgkJCwAAAA==.Ormr:BAABLgAECn8nAAIJAAkJCBVHHwDcAQAJAAkJCBVHHwDcAQAAAA==.Orpsa:BAAALgADCgYJBgAAAA==.',
Os='Osteo:BAABLgAECn8uAAQCAAgJDwdOFAAnAQACAAgJyAZOFAAnAQAQAAgJXgR+pAD3AAABAAcJCALAPwC1AAAAAA==.',
Ou='Ouron:BAABLgAECn8mAAMdAAgJwBWMOADJAQAdAAcJUxaMOADJAQARAAYJtQxFZACyAAAAAA==.',
Pa='Papashrimps:BAACLgAFFH8eAAIVAAUJ5RsJUABFAQAVAAUJ5RsJUABFAQAuAAQKfzkAAhUACQl1ImwQAPYCABUACQl1ImwQAPYCAAAA.',
Pe='Perash:BAAALgAECgEJAQAAAA==.',
Ph='Phrazes:BAAALgAECgQJBAAAAA==.',
Pi='Pikyu:BAAALgADCgEJAQAAAA==.',
Pl='Placeholder:BAABLgAECn80AAIcAAkJlx5fBAC3AgAcAAkJlx5fBAC3AgAAAA==.Plaguestingr:BAABLgAECn9EAAIUAAkJDSSuCAASAwAUAAkJDSSuCAASAwAAAA==.',
Po='Pontifex:BAABLgAECn8rAAIIAAkJOxkADQCTAgAIAAkJOxkADQCTAgAAAA==.Portandmorph:BAABLgAECn8wAAIVAAkJ5hUQOwAqAgAVAAkJ5hUQOwAqAgAAAA==.Potlock:BAABLgAECn8VAAMQAAgJbAuLowD5AAAQAAUJLwqLowD5AAACAAMJhA7JKgBsAAAAAA==.',
Pr='Prayinmantís:BAAALgADCgkJCQAAAA==.Proey:BAABLgAECn9DAAMGAAkJAhnQDwBfAgAGAAkJAhnQDwBfAgAHAAUJJhNYQAAIAQAAAA==.Prone:BAABLgAECn9NAAMdAAkJpg5bPAC5AQAdAAkJpg5bPAC5AQARAAYJewlMWgDRAAAAAA==.',
Ps='Psychokiller:BAAALgADCgYJBgAAAA==.',
Pu='Puf:BAAALgAECgMJBwAAAA==.Puipui:BAAALgADCgEJAgAAAA==.Pumpidan:BAAALgAECgIJBQAAAA==.',
Py='Pyrelyn:BAAALgADCgEJAQAAAA==.',
Qr='Qròw:BAAALgADCgMJAwAAAA==.',
Qu='Quinnifred:BAAALgAECgQJBgAAAA==.',
Ra='Raakotah:BAABLgAECn9JAAIMAAkJKSWnAgBGAwAMAAkJKSWnAgBGAwAAAA==.Raelo:BAABLgAECn8xAAIhAAkJThVeCQAkAgAhAAkJThVeCQAkAgAAAA==.Raiseurmug:BAABLgAECn8wAAIbAAkJ9BXiEwAOAgAbAAkJ9BXiEwAOAgAAAA==.Rakash:BAACLgAFFH8SAAITAAUJBhs9VgBCAQATAAUJBhs9VgBCAQAuAAQKfywAAhMACQmTIK0gAL8CABMACQmTIK0gAL8CAAAA.Rarg:BAAALgAFFAIJAgABLgAFFAcJEQASABsaAA==.Rascaldragon:BAAALgAECgQJBQAAAA==.Ravenlark:BAABLgAECn8ZAAIQAAkJigYieQBGAQAQAAkJigYieQBGAQAAAA==.Ravia:BAABLgAECn8mAAMOAAkJQCMzCQABAwAOAAkJqyIzCQABAwAWAAUJUiE4CQDdAQAAAA==.Razuki:BAAALgAECgYJEwABLgAFFAQJCQAiAOIQAA==.',
Re='Reddale:BAAALgADCgcJDAAAAA==.Redeamer:BAAALgAECgEJAgAAAA==.Resco:BAACLgAFFH8nAAIYAAgJIRf0AwAwAgAYAAgJIRf0AwAwAgAuAAQKfz0AAhgACQkDJS8FAA0DABgACQkDJS8FAA0DAAAA.Rescotwo:BAAALgAECgYJDgAAAA==.',
Ri='Riddle:BAABLgAECn8cAAIdAAkJFgl4agAXAQAdAAkJFgl4agAXAQAAAA==.Rimeouo:BAAALgADCgEJAQAAAA==.Rize:BAAALgAECgMJAwABLgAECgkJLQAJABsUAA==.',
Ro='Rocksolid:BAAALgADCgUJBgAAAA==.Ronnie:BAAALgAECgQJBwAAAA==.Rook:BAACLgAFFH8bAAMTAAYJ1RtmNwCHAQATAAUJ1RtmNwCHAQADAAEJAADIYwAAAAAuAAQKfykAAhMACAkTIykXAPACABMACAkTIykXAPACAAAA.Rookmonger:BAAALgAECgUJBQABLgAFFAYJGwATANUbAA==.Rosenrott:BAAALgAFFAIJAwAAAA==.Rosepiercer:BAABLgAECn89AAIUAAkJsSOrBwAcAwAUAAkJsSOrBwAcAwAAAA==.Rosies:BAAALgAECgUJBwAAAA==.Rouz:BAABLgAECn8cAAIgAAYJeA9IEAACAQAgAAYJeA9IEAACAQAAAA==.',
Ry='Ryenoh:BAAALgADCgYJBgAAAA==.Ryoto:BAACLgAFFH8ZAAMJAAUJTiTlGQCMAQAJAAQJ5iPlGQCMAQAgAAMJZyIyCwBmAAAuAAQKfxwAAwkACQmHJSMZAAsCAAkACQmHJSMZAAsCACAAAwkXJCMmAPIAAAAA.',
Sa='Sadness:BAAALgADCgYJBwAAAA==.Saelyz:BAAALgADCgQJBAAAAA==.Saetha:BAABLgAECn8WAAIjAAkJGA0SFgBiAQAjAAkJGA0SFgBiAQAAAA==.Samandean:BAABLgAECn9DAAIPAAkJEBmRDABaAgAPAAkJEBmRDABaAgAAAA==.Santhallibar:BAABLgAECn8nAAImAAkJeQO3EQAHAQAmAAkJeQO3EQAHAQAAAA==.Sarasvati:BAABLgAECn8nAAIFAAkJoxqEEQDCAgAFAAkJoxqEEQDCAgAAAA==.Saster:BAABLgAECn8hAAITAAkJgiKVDgD1AgATAAkJgiKVDgD1AgAAAA==.Sathrel:BAAALgADCgIJAgABLgAECgkJBwAEAAAAAA==.',
Sc='Scoops:BAAALgAECgcJAgABLgAECgcJEAAEAAAAAA==.Scrabs:BAAALgAECgkJDwAAAA==.',
Se='Sellena:BAABLgAECn8uAAIhAAkJMRSdCgAKAgAhAAkJMRSdCgAKAgABLgAECgkJQwAPABAZAA==.Sementha:BAAALgADCgcJDgABLgAECgYJCQAEAAAAAA==.Senpai:BAABLgAECn8UAAIZAAYJyRxQIQCpAQAZAAYJyRxQIQCpAQABLgAFFAgJHgAFAOwZAA==.Sephyra:BAAALgAECgkJEAAAAA==.',
Sh='Shadowmyst:BAAALgADCgQJCgAAAA==.Shaken:BAAALgAECgIJAgAAAA==.Shandow:BAACLgAFFH8ZAAIVAAUJqxyVTABNAQAVAAUJqxyVTABNAQAuAAQKf0wAAhUACQlfJAoGAFEDABUACQlfJAoGAFEDAAAA.Shango:BAAALgADCgcJCQAAAA==.Shanshunt:BAAALgAECgYJCAABLgAFFAUJGQAVAKscAA==.Shansoracle:BAACLgAFFH8YAAIIAAYJvBivBgDkAQAIAAYJvBivBgDkAQAuAAQKfyEAAggACQlhHxwEAEIDAAgACQlhHxwEAEIDAAEuAAUUBQkZABUAqxwA.Shed:BAACLgAFFH8SAAIRAAUJUx8SFgBiAQARAAUJUx8SFgBiAQAuAAQKfy0AAhEACAltIZYNAMgCABEACAltIZYNAMgCAAAA.Sheislegend:BAABLgAECn8cAAIIAAcJpBfKHQDSAQAIAAcJpBfKHQDSAQAAAA==.Shelby:BAABLgAECn80AAMIAAkJERqSDwBsAgAIAAkJERqSDwBsAgAGAAUJcRAYQAANAQAAAA==.Shmoon:BAEALgAECgIJAgABLgAECgUJBgAEAAAAAA==.Shmuckman:BAAALgADCgkJEwAAAA==.Shorttotem:BAAALgADCgUJBQAAAA==.Shoty:BAAALgAECgMJAwABLgAFFAYJGwATANUbAA==.',
Si='Siccinok:BAABLgAECn8wAAIVAAgJbBb2VQDYAQAVAAgJbBb2VQDYAQAAAA==.Silicá:BAAALgADCgkJCQABLgAECgEJAQAEAAAAAA==.Sindorian:BAABLgAECn8xAAMaAAgJVSEvCQCLAgAaAAgJ7R8vCQCLAgAUAAYJHSIRJwAdAgAAAA==.Sink:BAAALgADCgIJAgAAAA==.Sithlord:BAAALgADCgMJAwAAAA==.',
Sk='Skrimphorn:BAAALgAECgEJAQAAAA==.',
Sl='Slimped:BAAALgAECgkJEwAAAA==.',
Sm='Smurricane:BAAALgAECgUJCAAAAA==.',
Sn='Snowybato:BAAALgAECgUJEgAAAA==.',
So='Solanwarr:BAABLgAECn88AAQSAAkJTCMvAwAFAwASAAkJKCIvAwAFAwAYAAgJ6B3CFwCOAgAnAAMJnRmxUgCDAAAAAA==.Solar:BAAALgAECgQJCAAAAA==.Solarial:BAAALgAFFAEJAQAAAA==.Solastra:BAABLgAECn8+AAIiAAkJHhyLCQDwAgAiAAkJHhyLCQDwAgAAAA==.Sommer:BAAALgAECgUJBQABLgAECgkJSgAMAN0XAA==.Soramai:BAAALgADCgcJDwAAAA==.Soth:BAABLgAECn9GAAMTAAkJ1RqrIwB1AgATAAkJ1RqrIwB1AgADAAkJQw/wGgCDAQAAAA==.',
Sp='Sparticusdru:BAABLgAECn8WAAIjAAkJih3DBwBUAgAjAAkJih3DBwBUAgAAAA==.Spore:BAAALgAECgMJAwAAAA==.',
Sq='Sqaw:BAAALgAECgEJAQAAAA==.',
St='Starkadia:BAAALgAECgYJBgAAAA==.Staryxia:BAACLgAFFH8eAAMKAAUJIxrECwA2AQAKAAQJIxrECwA2AQADAAEJAACwRgAAAAAuAAQKfy0AAgoACQmhIUsBAPYCAAoACQmhIUsBAPYCAAAA.Steamdruid:BAAALgAECgYJEQAAAA==.Stonecookies:BAABLgAECn8hAAMQAAkJKgn5agBlAQAQAAkJPQj5agBlAQABAAUJ7AYySQCTAAAAAA==.Stonecross:BAAALgAECgYJCgAAAA==.Stonehard:BAAALgAECgMJAwAAAA==.Stoneldo:BAAALgADCgEJAQAAAA==.Stonetotem:BAAALgAECgYJDAAAAA==.Stormbolt:BAABLgAECn9KAAIMAAkJ3RfMEgA9AgAMAAkJ3RfMEgA9AgAAAA==.Stormspirit:BAAALgADCgkJEAAAAA==.Striggen:BAABLgAECn8cAAMNAAYJHhJKwAAFAQANAAUJ9BRKwAAFAQAcAAUJDwkZOQB2AAAAAA==.',
Su='Succystrazsa:BAAALgADCgIJAgAAAA==.Sugarsham:BAABLgAECn8ZAAQdAAgJihXXKgALAgAdAAgJihXXKgALAgARAAYJ9Qb1ZQCwAAAhAAQJjgNVJgByAAAAAA==.Sulwen:BAACLgAFFH8UAAIMAAgJRCLvAAA9AgAMAAgJRCLvAAA9AgAuAAQKfyAAAgwACQmQJvwEAFEDAAwACQmQJvwEAFEDAAAA.Sumerset:BAAALgAECgMJBgAAAA==.Sunnydee:BAAALgAECggJDgAAAA==.Supaflytnt:BAAALgAECgUJCAAAAA==.Sustia:BAABLgAECn8VAAIoAAgJ1wpLDABNAQAoAAgJ1wpLDABNAQAAAA==.',
Sy='Syrelina:BAAALgAECgQJBAABLgAECgkJJgAOAEAjAA==.',
Ta='Tacopie:BAAALgAECgQJBgAAAA==.Taera:BAACLgAFFH8HAAIZAAMJ0xMiOAC7AAAZAAMJ0xMiOAC7AAAuAAQKfzcAAhkACQmtIkwEAGsDABkACQmtIkwEAGsDAAAA.Taika:BAAALgADCgkJDwAAAA==.Tailchaser:BAAALgADCgcJBwAAAA==.Talanazar:BAABLgAECn88AAQJAAkJWyJ6BAAfAwAJAAkJWyJ6BAAfAwAgAAYJgR2AFAChAQAkAAMJ0A5HKgCVAAAAAA==.Talavenn:BAABLgAECn8uAAIOAAgJaxlCLQAPAgAOAAgJaxlCLQAPAgAAAA==.Tallish:BAABLgAECn8iAAIOAAkJ6wxHmwDnAAAOAAkJ6wxHmwDnAAAAAA==.Tarage:BAAALgAECgIJAgAAAA==.Taterchip:BAABLgAECn8oAAMYAAgJlRZ5IwDWAQAYAAgJWBZ5IwDWAQASAAIJvRayOwCAAAAAAA==.Taylia:BAAALgAECgQJBgAAAA==.',
Te='Teaorix:BAAALgADCgQJBAAAAA==.Teds:BAAALgADCgUJBQAAAA==.Temporary:BAAALgADCgYJBgAAAA==.Tempus:BAABLgAECn8VAAINAAgJ9ARYxQD+AAANAAgJ9ARYxQD+AAAAAA==.Teradoxx:BAAALgAECgYJDgAAAA==.Teriko:BAABLgAECn8/AAMTAAkJ3h6FGQCrAgATAAkJ3h6FGQCrAgADAAcJKgp6MADaAAAAAA==.Terran:BAAALgAECgEJAwABLgAECgkJQQAOANofAA==.Teviro:BAAALgAECgUJBgABLgAECgkJSAAaAEkhAA==.',
Th='Thanks:BAAALgAECgEJAQAAAA==.Thequixote:BAAALgADCgEJAQAAAA==.Therizino:BAAALgADCgQJBAAAAA==.Thrashy:BAAALgAECgQJCAAAAA==.Thrum:BAAALgAECgEJAQAAAA==.',
Ti='Tinkerballa:BAAALgAECgEJAQAAAA==.',
To='Toxictotes:BAAALgAECgMJBQAAAA==.',
Ts='Tsargeras:BAAALgAECgMJAwAAAA==.',
Tw='Twiddleado:BAABLgAECn9AAAIVAAkJDRj0MgBKAgAVAAkJDRj0MgBKAgAAAA==.Twinkie:BAAALgAECggJCAABLgAECgkJJgAOAEAjAA==.Twinkle:BAAALgADCgEJAQAAAA==.',
Ty='Ty:BAAALgAFFAEJAQAAAA==.Tylor:BAAALgAECgYJDwAAAA==.',
['Tå']='Tåkete:BAAALgAECgYJCwAAAA==.',
Uk='Ukuindadookr:BAAALgADCgYJBgAAAA==.',
Um='Ume:BAAALgAECgEJAQABLgAECgMJBwAEAAAAAA==.',
Un='Unta:BAAALgAECgYJCQAAAA==.',
Va='Valaera:BAAALgAECgcJDwAAAA==.Valenora:BAABLgAECn8eAAIBAAkJ3h1zAgCPAgABAAkJ3h1zAgCPAgAAAA==.Valise:BAABLgAECn8pAAICAAYJrwSlHgDGAAACAAYJrwSlHgDGAAAAAA==.Varielle:BAAALgAECgYJCQAAAA==.Varuz:BAAALgAECgUJBwABLgAECgYJEAAEAAAAAA==.Varyz:BAAALgAECgUJBQABLgAECgYJEAAEAAAAAA==.Vaticamt:BAAALgAECgUJBQAAAA==.',
Ve='Vecxx:BAAALgADCgUJBQAAAA==.Velanie:BAAALgAECggJDgAAAA==.Velanise:BAAALgADCgMJAwAAAA==.Velight:BAAALgADCgEJAQAAAA==.Velinara:BAAALgAECgEJAQAAAA==.Velindroz:BAAALgAECgMJBgAAAA==.Veloras:BAAALgAECgEJAQAAAA==.Verene:BAABLgAECn8oAAIdAAkJEhYAIQBFAgAdAAkJEhYAIQBFAgAAAA==.Verinari:BAAALgAECgQJBAAAAA==.',
Vi='Vibes:BAAALgAECgkJBgAAAA==.Viperc:BAEALgADCgMJAwABLgAECgYJIAACAEwFAA==.Vipul:BAAALgAECgEJAgABLgAECgYJDgAEAAAAAA==.Viridria:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.Virridian:BAABLgAECn9LAAIUAAkJxyAXCwD5AgAUAAkJxyAXCwD5AgAAAA==.Virrigosa:BAAALgADCgcJBwAAAA==.Vistia:BAAALgADCgEJAQAAAA==.',
Vl='Vlado:BAAALgAECgEJAgAAAA==.',
Vo='Vodalus:BAAALgADCgUJBQAAAA==.Voideria:BAAALgAECgQJBgAAAA==.Voolock:BAAALgADCgkJDwAAAA==.',
Vy='Vyshana:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.',
Wa='Wallofshame:BAABLgAECn8uAAMiAAkJxh2tDQC2AgAiAAkJxh2tDQC2AgANAAQJXg6g5gDTAAAAAA==.Walt:BAAALgADCgIJAgAAAA==.Warchef:BAAALgADCgYJCgABLgAECgkJQAAVADUhAA==.Warriorclaps:BAAALgADCggJDgAAAA==.Wartooth:BAABLgAECn9CAAMBAAkJZRt7AwBYAgABAAgJ0h17AwBYAgAQAAgJIxHWQQDVAQAAAA==.Wassergott:BAAALgADCgIJAgAAAA==.',
We='Webicus:BAABLgAECn8mAAISAAkJ1BNREgDCAQASAAkJ1BNREgDCAQAAAA==.Weezzer:BAAALgADCgQJBAAAAA==.Wendee:BAABLgAECn87AAMIAAkJNQJ4QQDiAAAIAAkJNQJ4QQDiAAAGAAUJdQTkSwCoAAAAAA==.',
Wh='Whitefóx:BAACLgAFFH8UAAIcAAUJLRR1BwD/AAAcAAUJLRR1BwD/AAAuAAQKfx4AAhwACQmYG8YFAI0CABwACQmYG8YFAI0CAAEuAAUUBQkZABUAqxwA.Whitley:BAABLgAECn8vAAMdAAkJEyEMBgBNAwAdAAkJEyEMBgBNAwAhAAcJrxUIEgCQAQAAAA==.',
Wi='Wijing:BAAALgAECgIJAgAAAA==.',
Wo='Wolololo:BAAALgAECgEJAQABLgAECgkJIQATAIIiAA==.Wooden:BAAALgAECgMJBQAAAA==.Worldbreaker:BAAALgADCgEJAQAAAA==.',
['Wü']='Wülfsa:BAAALgAECgUJBQAAAA==.',
Xa='Xampu:BAAALgAECgEJAQAAAA==.Xanthium:BAABLgAECn8pAAIIAAYJzwGaVACEAAAIAAYJzwGaVACEAAAAAA==.Xanzib:BAAALgADCgYJBgAAAA==.Xaphy:BAAALgAECgcJEQAAAA==.Xardots:BAABLgAECn8lAAIBAAgJohXSCwB+AQABAAgJohXSCwB+AQABLgAECgkJOQAEAAAAAA==.Xardral:BAAALgAECgcJBwABLgAECgkJOQAEAAAAAA==.',
Xe='Xeelynn:BAAALgAECgMJAwAAAA==.Xeetali:BAAALgADCgYJBgAAAA==.',
Xi='Xiareth:BAABLgAECn9CAAQkAAkJfQwlEwCTAQAkAAkJfQwlEwCTAQAgAAEJkAY6KAAqAAAJAAEJVAQWmgAkAAAAAA==.',
Xt='Xtronger:BAABLgAECn8gAAIFAAgJmRbyLwDhAQAFAAgJmRbyLwDhAQAAAA==.',
['Xá']='Xároth:BAAALgAECgkJOQAAAQ==.',
Ya='Yaddi:BAAALgAECgQJBgAAAA==.Yarrow:BAAALgADCgkJEgAAAA==.',
Ye='Yeeyee:BAABLgAECn8ZAAIMAAkJEyGdBQD9AgAMAAkJEyGdBQD9AgAAAA==.',
Za='Zackor:BAAALgAECgcJBwAAAA==.Zalik:BAAALgAECgMJAwAAAA==.',
Ze='Zeebo:BAAALgAECgcJEwAAAA==.Zest:BAABLgAECn8pAAMkAAkJ2BClDQDyAQAkAAkJ2BClDQDyAQAJAAIJkAjuewBjAAAAAA==.',
Zm='Zmaryjane:BAAALgAECgIJBAAAAA==.',
Zo='Zorakfoghorn:BAAALgADCgIJAgAAAA==.Zorakk:BAAALgAECgMJAwAAAA==.Zorithic:BAAALgAECgQJAwAAAA==.Zorrak:BAAALgAECgQJBQAAAA==.',
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
