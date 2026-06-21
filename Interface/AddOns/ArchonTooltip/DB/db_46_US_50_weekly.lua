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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Devourer','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Druid-Guardian','Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','Priest-Shadow','Priest-Discipline','Druid-Restoration','Monk-Mistweaver','Druid-Balance','Warlock-Affliction','Warlock-Demonology','Druid-Feral','Warrior-Protection','Unknown-Unknown','Monk-Brewmaster','Monk-Windwalker','Shaman-Enhancement','Mage-Arcane','Warrior-Arms','Warrior-Fury','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Evoker-Augmentation','DemonHunter-Vengeance','Mage-Fire','Rogue-Assassination',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abelene:BAAALgAECgQJBAAAAA==.Abrâham:BAAALgADCgUJBQAAAA==.',
Ac='Achelis:BAABLgAECn86AAMBAAkJ8CVZAQBUAwABAAkJ8CVZAQBUAwACAAEJAABJggA/AAAAAA==.',
Ad='Adianitefall:BAAALgAECgQJBAAAAA==.Adorian:BAABLgAECn8hAAIDAAgJbwi7JwBZAQADAAgJbwi7JwBZAQAAAA==.Adros:BAABLgAECn8oAAMEAAgJQRQMFQB+AQAEAAgJQRQMFQB+AQAFAAEJHwS1wgEiAAAAAA==.Adrrel:BAAALgADCgIJAgABLgAFFAgJIQAGAGQYAA==.Adrrelle:BAACLgAFFH8hAAQGAAgJZBjJGwCXAQAGAAYJbRzJGwCXAQABAAQJWg9lFAAqAQACAAYJaw1aEgAWAQAuAAQKfyUABAIACQncHXcTAJkCAAIACAmXH3cTAJkCAAEABAnaF687AOIAAAYAAwmpEW64AFIAAAAA.',
Ae='Aelon:BAABLgAECn8cAAIFAAgJxgeTrwAkAQAFAAgJxgeTrwAkAQAAAA==.',
Ah='Aheiro:BAAALgAECgQJCQAAAA==.',
Ai='Ailaith:BAABLgAECn9IAAIGAAkJlSTVAwBTAwAGAAkJlSTVAwBTAwAAAA==.',
Ak='Akariliselle:BAABLgAECn8XAAIHAAcJwRoYCgCkAQAHAAcJwRoYCgCkAQAAAA==.Akarue:BAAALgAECgQJBAAAAA==.Akibafaris:BAAALgAECgkJEgAAAA==.Aknologia:BAAALgAECgUJDQAAAA==.',
Al='Al:BAAALgADCggJCAAAAA==.Alan:BAAALgAECgUJCQAAAA==.Alarielle:BAAALgADCgkJEwAAAA==.Alcun:BAAALgAECgEJAQAAAA==.Aldora:BAAALgADCgkJDAAAAA==.Alirik:BAAALgADCgQJBQAAAA==.Alleriah:BAAALgAECgcJCAABLgAECggJIwAIANUgAA==.Alon:BAAALgAECgIJAgAAAA==.Alydrostage:BAABLgAECn8pAAIJAAgJLgdmoAA6AQAJAAgJLgdmoAA6AQAAAA==.Alystriaz:BAABLgAECn8mAAMKAAkJPxpBBgCkAgAKAAkJPxpBBgCkAgALAAEJsQWEKQAoAAAAAA==.Alzheimerz:BAAALgAECgUJBQAAAA==.',
Am='Amaelalin:BAABLgAECn9EAAIMAAkJ9h+wBAA1AwAMAAkJ9h+wBAA1AwAAAA==.Ameliya:BAAALgAECgIJAgAAAA==.Ameng:BAAALgAECgQJBgAAAA==.',
An='Anaralyth:BAAALgAECgYJCAABLgAFFAUJDwANAPYTAA==.Andaya:BAACLgAFFH8XAAMOAAUJ+RsgFwCtAQAOAAUJ+RsgFwCtAQAPAAEJnwNkYAAtAAAuAAQKfyMAAw4ACQmrGag8ALwBAA4ACQmrGag8ALwBAA8AAgndDAiGAGQAAAAA.Andemeli:BAABLgAECn8bAAIFAAgJSQ3+igBbAQAFAAgJSQ3+igBbAQAAAA==.Andevyn:BAAALgAECgQJBAABLgAECggJIwAIANUgAA==.Aninja:BAEALgADCgQJBAABLgAFFAUJFAAQAHYeAA==.Anivia:BAABLgAECn8fAAIJAAkJORHUVgDZAQAJAAkJORHUVgDZAQAAAA==.Ankoubailith:BAAALgAECgQJBgAAAA==.',
Ap='Apollon:BAAALgADCgIJAwAAAA==.',
Ar='Arandis:BAABLgAECn8kAAMRAAgJawwKQwADAQARAAYJXA4KQwADAQASAAQJkQjdVwChAAAAAA==.Arch:BAAALgAECgQJBQAAAA==.Arcianna:BAABLgAECn8xAAMNAAkJ2B2EBgCVAgANAAkJ2B2EBgCVAgATAAEJQRHe0wAxAAAAAA==.Arctica:BAABLgAECn8XAAIJAAYJYQujygD5AAAJAAYJYQujygD5AAAAAA==.Arctiq:BAAALgADCgUJCgAAAA==.Arctîc:BAABLgAECn8qAAIJAAkJFhPSUgDkAQAJAAkJFhPSUgDkAQAAAA==.Arjurn:BAABLgAECn87AAIJAAkJByBeFADfAgAJAAkJByBeFADfAgAAAA==.Arkro:BAAALgAECgMJBAAAAA==.Armpitbutter:BAABLgAECn87AAIUAAkJqSMKBAB1AwAUAAkJqSMKBAB1AwAAAA==.Artymiss:BAABLgAECn8ZAAMVAAkJbBBoIgC2AQAVAAkJbBBoIgC2AQATAAYJmRNLVgBQAQAAAA==.',
As='Asherah:BAABLgAECn8gAAMWAAgJhgf0FQAbAQAWAAcJegj0FQAbAQAXAAcJugFn9AB5AAAAAA==.Ashireita:BAAALgAECgYJEAABLgAECgkJLgAPAMoWAA==.Ashwadawnguh:BAAALgAECgEJAQAAAA==.Astraleth:BAACLgAFFH8PAAQNAAUJ9hMwHACvAAAVAAMJqxVWLgDNAAANAAQJqgowHACvAAATAAEJcwJXcwAzAAAuAAQKfxsAAw0ACQniGAISANABAA0ABwkaFwISANABABUABgm5F9FFAPUAAAAA.',
At='Atama:BAAALgAECgQJBwAAAA==.Atharius:BAAALgADCgEJAQAAAA==.',
Au='Aurturious:BAAALgAECgQJBAAAAA==.Authority:BAAALgAECgMJAwAAAA==.Autry:BAABLgAECn8xAAMYAAkJ1g9rEACwAQAYAAkJ1g9rEACwAQATAAgJUgpdUwBCAQAAAA==.',
Av='Avelina:BAAALgADCgkJFAAAAA==.Avocat:BAABLgAECn8uAAIGAAkJiRslFwCcAgAGAAkJiRslFwCcAgAAAA==.',
Ay='Ayrilia:BAAALgAECgYJCAABLgAFFAUJDwANAPYTAA==.',
Az='Azeria:BAAALgAECgUJCQABLgAFFAgJEwAZABceAA==.Azshura:BAAALgAECgEJAQAAAA==.Azzinôth:BAAALgADCgcJBwABLgAECgEJAgAaAAAAAA==.',
Ba='Baekr:BAAALgAECgYJEAAAAA==.Baldr:BAABLgAECn8vAAIFAAkJKhNBTQDfAQAFAAkJKhNBTQDfAQAAAA==.Balgar:BAABLgAECn8aAAMGAAkJhCP8JABPAgAGAAkJhCP8JABPAgACAAUJyxm3PgBgAQAAAA==.Balghas:BAABLgAECn8kAAIFAAgJ1hzQMwBTAgAFAAgJ1hzQMwBTAgAAAA==.Bamz:BAAALgAFFAEJAQABLgAFFAUJGwAMAGMUAA==.Bamzhurt:BAAALgAFFAMJBAABLgAFFAUJGwAMAGMUAA==.Baumstrum:BAAALgAECgYJDQAAAA==.',
Be='Bearlydrae:BAAALgAECgEJAgAAAA==.Beezlbubba:BAAALgAECgYJDAAAAA==.Beldam:BAAALgADCgYJBgAAAA==.Belispeak:BAAALgADCgYJBgAAAA==.Bellaboom:BAAALgADCgYJBgAAAA==.Belvkara:BAAALgADCgkJCQAAAA==.Benedictoe:BAAALgADCgYJBgAAAA==.',
Bh='Bhozok:BAABLgAECn83AAIYAAkJvBI+DgDSAQAYAAkJvBI+DgDSAQAAAA==.',
Bi='Bint:BAAALgAECgEJAQAAAA==.',
Bl='Bloodpromise:BAAALgADCgMJAwAAAA==.Bloodrayvn:BAABLgAECn8wAAIGAAkJxR1+GACUAgAGAAkJxR1+GACUAgAAAA==.',
Bo='Boomchick:BAAALgAECgMJAwABLgAECgkJIAAGAOAdAA==.Boomparapara:BAACLgAFFH8OAAIJAAQJ3xcOTgBDAQAJAAQJ3xcOTgBDAQAuAAQKfyYAAgkACQl9IKkRAPACAAkACQl9IKkRAPACAAAA.Borrkbuster:BAAALgAECgQJBAAAAA==.Bosta:BAAALgAECgQJBgAAAA==.Botkin:BAAALgADCgEJAQAAAA==.',
Br='Bradley:BAAALgAECgYJDgABLgAECgcJFwAMAJkiAA==.Brandywyne:BAAALgADCgEJAQAAAA==.Brenri:BAABLgAECn8dAAIPAAkJmAPBVgDgAAAPAAkJmAPBVgDgAAAAAA==.Brew:BAABLgAECn8lAAMbAAgJLxzyEwAQAgAbAAgJLxzyEwAQAgAcAAEJ0Q0LfQAzAAAAAA==.Brewtality:BAAALgAFFAEJAQABLgAFFAIJBQATAMUSAA==.Brkat:BAAALgAECgIJAgAAAA==.Brughe:BAABLgAECn8rAAIGAAkJJQ0XZAB9AQAGAAkJJQ0XZAB9AQAAAA==.',
Bu='Bubbleoseven:BAAALgADCgYJBgABLgAFFAIJBQATAMUSAA==.Buttacutta:BAAALgADCgkJPQAAAA==.',
['Bä']='Bäné:BAAALgADCgIJAgAAAA==.',
Ca='Cairn:BAAALgADCgUJBQAAAA==.Caneste:BAACLgAFFH8QAAIRAAYJqhm2DwBwAQARAAYJqhm2DwBwAQAuAAQKfx8AAhEACQm9HfcLAMMCABEACQm9HfcLAMMCAAAA.Capela:BAAALgADCgEJAQAAAA==.Capparelli:BAAALgADCgEJAQAAAA==.Cashoe:BAAALgADCgMJAwAAAA==.Catscan:BAACLgAFFH8FAAITAAIJxRIvVgBuAAATAAIJxRIvVgBuAAAuAAQKfyIAAhMACQniHV0OAOUCABMACQniHV0OAOUCAAAA.Catty:BAABLgAECn8vAAIYAAkJ/BeCCABEAgAYAAkJ/BeCCABEAgAAAA==.',
Cb='Cblock:BAAALgAECgUJBQABLgAFFAMJBwAdANAIAA==.',
Ce='Celeano:BAAALgADCgkJCQABLgAECgQJBAAaAAAAAA==.Celestyl:BAABLgAECn8vAAIeAAkJjgy4BQB2AQAeAAkJjgy4BQB2AQAAAA==.',
Ch='Charazard:BAAALgAECgUJCgABLgAECggJJQAKAL8ZAA==.Charming:BAAALgADCgMJAwAAAA==.Cheapbeer:BAABLgAECn8VAAIFAAkJVgir2ADnAAAFAAkJVgir2ADnAAAAAA==.Cheesehead:BAAALgADCggJEgAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chiforged:BAABLgAECn8UAAIcAAYJtAyjSwDTAAAcAAYJtAyjSwDTAAAAAA==.Chillybovine:BAABLgAECn8bAAIJAAcJCQqOsAAgAQAJAAcJCQqOsAAgAQAAAA==.Chromstrasza:BAABLgAECn8ZAAILAAcJHxjBCQCJAQALAAcJHxjBCQCJAQAAAA==.Chudderly:BAAALgADCgEJAgAAAA==.Chudders:BAAALgADCgIJAgAAAA==.',
Ci='Cirice:BAAALgAECgEJAwAAAA==.Citrouille:BAAALgAECgEJAgAAAA==.',
Cl='Clarence:BAAALgADCgIJAgABLgAFFAgJJQAXAAMaAA==.',
Co='Comitus:BAABLgAECn9HAAMfAAkJmw9kFwCgAQAfAAkJmw9kFwCgAQAgAAQJ+wNjgwCxAAAAAA==.Conjar:BAAALgAECgIJAgAAAA==.Conjarr:BAABLgAECn8tAAIMAAkJ/hrhHQDWAQAMAAkJ/hrhHQDWAQAAAA==.Cortisol:BAAALgADCgIJAgAAAA==.Corven:BAAALgAECgUJDAAAAA==.Cougardk:BAAALgAECgIJAgAAAA==.Cougarsixsix:BAABLgAECn8fAAIEAAcJzhTLGABWAQAEAAcJzhTLGABWAQAAAA==.',
Cr='Crashnburn:BAAALgADCgcJDQAAAA==.Crazyoldbear:BAABLgAECn8eAAIZAAkJmCPvAwDuAgAZAAkJmCPvAwDuAgAAAA==.Creideam:BAAALgADCgkJBwAAAA==.Crimos:BAABLgAECn8wAAIQAAkJzRbpQAAAAgAQAAkJzRbpQAAAAgAAAA==.Crystalliney:BAAALgADCgYJBgABLgAFFAUJFwAbAO4mAA==.',
Cy='Cynnai:BAAALgADCgYJBgAAAA==.Cyrena:BAAALgADCgEJAQAAAA==.',
Da='Daerthor:BAABLgAECn8iAAIEAAkJOBo8CgAnAgAEAAkJOBo8CgAnAgAAAA==.Dalind:BAABLgAECn8hAAITAAgJqgZjaQD4AAATAAgJqgZjaQD4AAAAAA==.Dalshiro:BAAALgAECgYJCQAAAA==.Damaclies:BAABLgAECn9IAAMXAAkJTBgJPwDgAQAXAAgJQBYJPwDgAQAHAAUJfBgBGADiAAAAAA==.Damedolla:BAABLgAECn8fAAMIAAgJYQzCfwAgAQAIAAgJwwrCfwAgAQAhAAUJnw7EQAD3AAAAAA==.Dammerung:BAAALgAECgYJCAAAAA==.Darksyn:BAABLgAECn8cAAIHAAgJVAx/EgAiAQAHAAgJVAx/EgAiAQAAAA==.Darthbane:BAAALgAECggJEgAAAA==.Darthghidora:BAAALgADCggJCAAAAA==.Darthstroyer:BAABLgAFFH8FAAQiAAUJwgUjGgC5AAAiAAMJjgYjGgC5AAAQAAEJXQMiFwE9AAAjAAEJAACDYwAAAAAAAA==.Darude:BAAALgADCgcJEAAAAA==.Dashoka:BAAALgAECgEJAQAAAA==.Dattiffany:BAAALgAECgUJBQAAAA==.Dawnfist:BAAALgADCggJCAAAAA==.',
De='Deadstout:BAAALgAECgQJDwAAAA==.Deathevan:BAAALgAECggJDgABLgAECgkJLgAIADMiAA==.Deepspace:BAABLgAECn8uAAIhAAkJeSaHAACLAwAhAAkJeSaHAACLAwAAAA==.Deezknots:BAAALgAECggJCAAAAA==.Deezus:BAAALgADCgMJAwAAAA==.Dejagauth:BAAALgAECgYJCwABLgAECggJFQAkAKwhAA==.Dekkan:BAAALgAECgYJEAAAAA==.Demonedd:BAAALgADCgMJAgAAAA==.Demòn:BAAALgAECgEJAQAAAA==.Denounce:BAABLgAECn8eAAIlAAcJfBmnAABmAQAlAAcJfBmnAABmAQABLgAECgYJFgAYAIYgAA==.Desdia:BAABLgAECn8fAAIJAAgJCBlEAwAkAQAJAAgJCBlEAwAkAQAAAA==.',
Di='Dia:BAAALgAECgQJBwAAAA==.Diabetes:BAABLgAFFH8VAAIUAAcJzhoVFwDFAQAUAAcJzhoVFwDFAQAAAA==.Diastolic:BAAALgADCgUJBQAAAA==.Didyoudie:BAAALgAECggJDAAAAA==.Diend:BAABLgAECn9SAAIOAAkJgCTMAQCzAwAOAAkJgCTMAQCzAwAAAA==.Dill:BAAALgAECgEJAQABLgAECgkJOgABAPAlAA==.Dillathis:BAAALgADCgEJAQAAAA==.Discord:BAAALgAECgQJBQABLgAFFAMJBAAaAAAAAA==.Dissonanita:BAABLgAECn8XAAIGAAgJsg/raQBuAQAGAAgJsg/raQBuAQAAAA==.',
Dj='Djthelock:BAABLgAECn8sAAMXAAkJuRb6NQABAgAXAAgJxBP6NQABAgAHAAQJDhhNHADEAAAAAA==.',
Do='Dormoon:BAABLgAECn8bAAMgAAgJnQ19QQA/AQAgAAgJnQ19QQA/AQAZAAEJIBH6VAAuAAAAAA==.',
Dr='Drac:BAAALgADCgYJCgAAAA==.Dragath:BAAALgAECgYJDgAAAA==.Drakur:BAAALgAECgYJCQAAAA==.Drbrad:BAABLgAECn8XAAMMAAcJmSJ4FgAdAgAMAAcJmSJ4FgAdAgARAAMJDhAScQBgAAAAAA==.Dreadfangs:BAAALgADCgQJBQAAAA==.Druen:BAABLgAECn8xAAIYAAkJHB52BAC4AgAYAAkJHB52BAC4AgAAAA==.Drunkenpo:BAABLgAECn9OAAQbAAkJ5yH4BADzAgAbAAkJtSH4BADzAgAUAAUJ7hOfUQAoAQAcAAEJ4yN+cwBpAAAAAA==.Drykin:BAAALgAECgYJCwAAAA==.Drïzl:BAEALgAECgMJAwABLgAFFAUJFAAQAHYeAA==.',
Du='Duckchow:BAAALgADCgYJBgAAAA==.Dugga:BAAALgADCgQJBAAAAA==.Duskmyre:BAABLgAECn8lAAIIAAkJbw0OWQB8AQAIAAkJbw0OWQB8AQAAAA==.',
Dw='Dwarfoo:BAABLgAECn8ZAAMcAAgJrxemPwABAQAcAAYJWxOmPwABAQAUAAMJjwi8mQBlAAAAAA==.Dweñde:BAABLgAECn8nAAIXAAkJigrVYAB+AQAXAAkJigrVYAB+AQAAAA==.',
['Dë']='Dëthmetal:BAABLgAECn8UAAIQAAUJnQxfwgD/AAAQAAUJnQxfwgD/AAAAAA==.',
Ed='Eddiemac:BAAALgAECgYJCgAAAA==.Eddrick:BAACLgAFFH8HAAIFAAMJdxk3WwD6AAAFAAMJdxk3WwD6AAAuAAQKfzcAAwUACQkwH4wTAM0CAAUACQkqH4wTAM0CAAQABQkvHZ0ZAEwBAAAA.Edoran:BAAALgADCggJCAAAAA==.Edrani:BAAALgAECgYJDgAAAA==.',
Ei='Eilethen:BAABLgAECn8mAAIWAAkJOxocBgAfAgAWAAkJOxocBgAfAgAAAA==.',
Ek='Ekassa:BAAALgADCgkJCQAAAA==.',
El='Elaína:BAAALgADCgMJAwABLgAFFAUJGQAWAMUSAA==.Elementoe:BAAALgADCgEJAQABLgADCgYJBgAaAAAAAA==.Elendil:BAAALgAECgMJAwAAAA==.Elissabethh:BAAALgAECgYJEAAAAA==.Elleryn:BAAALgADCgEJAQABLgAECgYJGQAOALwXAA==.Elminstar:BAAALgADCgIJAgAAAA==.Elêctra:BAAALgAECgEJAgABLgAECgkJDgAaAAAAAA==.',
Em='Employee:BAABLgAECn8VAAIlAAgJ4wvASAAIAQAlAAgJ4wvASAAIAQAAAA==.',
En='Engo:BAABLgAECn9EAAMMAAkJdiRoAwBZAwAMAAkJdCNoAwBZAwASAAkJ9BslCQDhAgAAAA==.',
Er='Eradrá:BAACLgAFFH8ZAAMWAAUJxRJJEQCFAAAXAAUJxRI2VQAcAQAWAAIJAQxJEQCFAAAuAAQKf1AAAxYACQmzHugAAA4DABYACQmsG+gAAA4DABcACQm9GDQiAFkCAAAA.Eragon:BAAALgAECggJDgAAAA==.Erastrasza:BAAALgADCgYJCQAAAA==.Eroza:BAAALgAECgUJBgAAAA==.Ersey:BAAALgAECgQJBAABLgAFFAMJBwATAO8HAA==.Ersèlla:BAACLgAFFH8HAAITAAMJ7wdHTACMAAATAAMJ7wdHTACMAAAuAAQKfy4AAxMACQmMGHwbAGoCABMACQmMGHwbAGoCABUAAQnYBSWdACQAAAAA.Erysira:BAAALgADCgkJCQABLgAECggJGQAJAOsQAA==.',
Et='Ethan:BAAALgAECgEJAgAAAQ==.',
Eu='Eureka:BAABLgAECn8gAAMEAAkJTB2ADgDbAQAEAAcJ1RyADgDbAQAFAAcJSRnxZQCkAQAAAA==.',
Ev='Evandra:BAABLgAECn8vAAIOAAkJCxzGFgCTAgAOAAkJCxzGFgCTAgAAAA==.Evanorah:BAABLgAECn8cAAMHAAcJjwmFIgCcAAAXAAcJYAkIlAAUAQAHAAYJowWFIgCcAAAAAA==.',
Ex='Exïle:BAEALgAECgYJBgABLgAFFAUJFAAQAHYeAA==.',
Fa='Faelithia:BAABLgAECn8WAAIMAAYJKA4KPQD/AAAMAAYJKA4KPQD/AAAAAA==.Fatalbrew:BAAALgAECgYJCwAAAA==.Fauxyalee:BAAALgADCgkJEgAAAA==.',
Fe='Feldush:BAAALgADCgYJBgABLgAECggJJQAKAL8ZAA==.Felforit:BAAALgADCgQJBAAAAA==.Felis:BAAALgAECgYJCgAAAA==.Felkardio:BAAALgAECgIJAgAAAA==.Feloth:BAAALgADCgYJCQAAAA==.Ferheim:BAAALgAECgYJDwAAAA==.Ferhold:BAAALgADCgYJBgAAAA==.Ferrovax:BAAALgADCgYJBgABLgAECgkJLQAIACYZAA==.',
Fi='Fiddyone:BAABLgAECn8sAAMiAAkJySEoAwC+AgAiAAkJtCEoAwC+AgAQAAgJcR0lRQDzAQAAAA==.Figment:BAAALgADCgYJBgAAAA==.Fireburt:BAAALgADCgUJBQAAAA==.Fireslay:BAABLgAECn8YAAIkAAcJpBwHHgAmAgAkAAcJpBwHHgAmAgAAAA==.Fizzlegrin:BAAALgAECgIJAgAAAA==.',
Fl='Flarefly:BAAALgAECgEJAQAAAA==.Flaya:BAAALgAECgcJDAAAAA==.',
Fo='Fodurzin:BAAALgAECgUJEwAAAA==.Fonta:BAAALgAECgMJAwAAAA==.Fortuna:BAAALgADCgYJBgABLgAECgkJIAAGAOAdAA==.Foxingtobi:BAAALgADCgIJAgAAAA==.',
Fr='Frojio:BAABLgAECn8yAAIiAAkJ1BuZBQBYAgAiAAkJ1BuZBQBYAgAAAA==.Frosten:BAAALgADCgkJPwAAAA==.',
Fu='Furenio:BAABLgAECn8yAAINAAkJ7xelDgD6AQANAAkJ7xelDgD6AQAAAA==.',
Fy='Fyyre:BAAALgAECgUJBwAAAA==.',
Ga='Gabaghoul:BAACLgAFFH8YAAIFAAUJFh0JKwBhAQAFAAUJFh0JKwBhAQAuAAQKfzEAAgUACQl3IHkZAKsCAAUACQl3IHkZAKsCAAAA.Gaff:BAAALgAECgkJEwAAAA==.Galeana:BAAALgAECgMJAwABLgAECgkJXQAJAPAeAA==.Galvan:BAAALgAECgEJBAAAAA==.Gasheth:BAAALgAECgYJDQAAAA==.',
Ge='Gentyl:BAAALgAECgQJBAAAAA==.',
Gi='Giggleblast:BAAALgAECgIJAgAAAA==.',
Gl='Glizzydealer:BAAALgAECgEJAQAAAA==.',
Gr='Grauth:BAAALgADCgEJAQAAAA==.Graycen:BAAALgAECgUJCQAAAA==.Grido:BAAALgAECgIJAgAAAA==.Grimbrindral:BAABLgAECn8hAAMFAAcJ5hZDZAC5AQAFAAcJdBVDZAC5AQAEAAUJghrKFwBZAQAAAA==.Grimston:BAAALgADCgMJAwABLgAECgcJIQAFAOYWAA==.Gruzaxx:BAAALgADCgUJBQAAAA==.',
Gu='Gulishdaniel:BAABLgAFFH8GAAIWAAQJJQRRCQDlAAAWAAQJJQRRCQDlAAABLgAFFAYJEAARAKoZAA==.',
Ha='Hadin:BAABLgAECn9MAAMJAAkJMCTGBgBKAwAJAAkJMCTGBgBKAwAeAAMJqhysDwDHAAAAAA==.Hakeko:BAAALgAECgYJDgABLgAECggJEwAaAAAAAA==.Halalnt:BAAALgAFFAEJAQABLgAFFAIJBQAlAOkaAA==.Hanua:BAAALgADCgcJBwAAAA==.Haozhao:BAABLgAECn9LAAMNAAkJxhouCQBYAgANAAkJxhouCQBYAgAYAAEJDhQmTwA7AAAAAA==.Hawktuahz:BAAALgAECgMJAwAAAA==.Hazenpryde:BAABLgAECn8fAAINAAgJahofEADnAQANAAgJahofEADnAQAAAA==.',
He='Hearsay:BAABLgAECn83AAMFAAgJdREmcACOAQAFAAgJdREmcACOAQAkAAIJ6wP/gQBHAAAAAA==.Hephaistian:BAAALgAECgUJBQAAAA==.Hespera:BAACLgAFFH8SAAMTAAUJFQ9mJgApAQATAAUJFQ9mJgApAQAVAAMJEgVIOgCQAAAuAAQKfyMAAxMACQnJIOkYAHACABMACAmiIekYAHACABUAAwmnFPVSAMMAAAAA.',
Hi='Hirari:BAABLgAECn8dAAMkAAYJBCWXFwBMAgAkAAYJBCWXFwBMAgAFAAEJFBpgeQFCAAAAAA==.',
Ho='Hodoor:BAAALgADCgUJBQAAAA==.Howlears:BAABLgAECn8pAAIRAAgJoQdKOwAlAQARAAgJoQdKOwAlAQAAAA==.',
Hu='Hulud:BAABLgAECn8YAAMXAAkJfRbhSwC3AQAXAAkJfRbhSwC3AQAHAAEJAADbVAAAAAAAAA==.Husbando:BAAALgAECgMJAwAAAA==.Husey:BAAALgAECgMJBgAAAA==.',
Hy='Hydrangea:BAABLgAECn8dAAIFAAcJ4Q+WkQBPAQAFAAcJ4Q+WkQBPAQAAAA==.Hydrá:BAABLgAECn8aAAIXAAkJvRYCMQAUAgAXAAkJvRYCMQAUAgAAAA==.Hylan:BAAALgADCgUJBQAAAA==.Hysgar:BAAALgAECgUJBQABLgAECggJFQAkAKwhAA==.',
Ic='Iceamaris:BAABLgAECn8gAAIPAAkJYQv9OABTAQAPAAkJYQv9OABTAQAAAA==.Icetiger:BAAALgAECgEJAQAAAA==.Icetigress:BAAALgAECgEJAQAAAA==.',
Ie='Iechu:BAABLgAECn8gAAMbAAgJbBFEIwCQAQAbAAgJbBFEIwCQAQAcAAIJ9QZwjABFAAAAAA==.',
In='Innanna:BAAALgADCggJCgABLgAECgcJFgAIAC4SAA==.',
Is='Isoth:BAAALgAECgEJAQAAAA==.',
Iv='Ivern:BAACLgAFFH8VAAITAAgJ+hGOCAByAgATAAgJ+hGOCAByAgAuAAQKfx0AAxMABgkHHfoyANIBABMABgkHHfoyANIBABUAAgnRBzCXACkAAAAA.Ivysnow:BAAALgAECgEJAQAAAA==.',
Ja='Jac:BAAALgAECgMJAwABLgAFFAMJBAAaAAAAAA==.Jadenpryde:BAAALgAECgYJBgABLgAECggJHwANAGoaAA==.Jaod:BAAALgAECgQJAgAAAA==.Jarndal:BAAALgAECgEJAQAAAA==.Jasmirrae:BAAALgAECgEJAQAAAA==.',
Jd='Jdghoul:BAAALgAECggJDwAAAA==.',
Ji='Jian:BAAALgADCgIJAgAAAA==.Jindrac:BAAALgAECggJDAAAAA==.',
Jo='Jolton:BAAALgADCgYJBwABLgAECgkJLgAIADMiAA==.',
['Jà']='Jàcaranda:BAAALgAECgYJBwAAAA==.',
Ka='Kahnrah:BAAALgADCgkJDAAAAA==.Kalarae:BAAALgAECggJCQAAAA==.Kalarill:BAABLgAECn8eAAIFAAcJZR1tMAA/AgAFAAcJZR1tMAA/AgAAAA==.Kaltharion:BAAALgAFFAIJBAAAAA==.Kaluren:BAAALgAECgcJDwAAAA==.Kalurok:BAAALgAECgUJBQABLgAECgcJDwAaAAAAAA==.Kana:BAAALgAECgIJAgAAAA==.Kanade:BAABLgAECn9HAAQXAAkJBh7BFwCVAgAXAAgJ1R3BFwCVAgAWAAcJsRX/CADVAQAHAAQJWAsKTACJAAAAAA==.Kantong:BAABLgAECn8gAAIcAAgJdRmIGwDTAQAcAAgJdRmIGwDTAQAAAA==.Kapp:BAAALgAECgcJEwAAAA==.Karabar:BAABLgAECn87AAMEAAkJ2yAYBQCjAgAEAAkJyh4YBQCjAgAFAAgJoyD0KABfAgAAAA==.Karnnaged:BAAALgADCgYJBwAAAA==.Kasarra:BAABLgAECn8zAAIhAAkJhxX3EwDzAQAhAAkJhxX3EwDzAQAAAA==.Kayiku:BAAALgADCgkJFwAAAA==.Kazagol:BAABLgAECn87AAIIAAkJ+x2tGgB0AgAIAAkJ+x2tGgB0AgAAAA==.',
Ke='Kelintos:BAAALgAECgEJAgABLgAECgkJOAAIAD4cAA==.Keone:BAAALgADCgEJAQAAAA==.',
Kh='Khalla:BAAALgAFFAEJAQAAAA==.Khamaracy:BAABLgAECn8gAAMHAAgJWwhFFgD1AAAHAAgJWwhFFgD1AAAXAAEJsQE6ZQEbAAAAAA==.Khronni:BAAALgAECgYJCQAAAA==.Khrooze:BAAALgAECgYJEQAAAA==.',
Ki='Kidos:BAAALgAECgQJBgAAAA==.Kiljana:BAAALgAECgEJAQAAAA==.Kimahrí:BAABLgAECn8dAAIjAAgJGwh6LwDkAAAjAAgJGwh6LwDkAAAAAA==.Kittei:BAABLgAECn87AAINAAkJ1w+eGwBwAQANAAkJ1w+eGwBwAQAAAA==.',
Ko='Kojote:BAAALgADCgMJAQAAAA==.Kovalenko:BAAALgAECggJDgAAAA==.',
Ku='Kurick:BAABLgAECn8VAAMkAAgJrCEvCAAJAwAkAAgJrCEvCAAJAwAFAAEJmxVVfgE+AAAAAA==.Kurzul:BAAALgADCgEJAgAAAA==.Kusinluvin:BAAALgAECgEJAQAAAA==.',
Ky='Kyngizzard:BAABLgAECn8fAAIJAAkJSRrWNwA5AgAJAAkJSRrWNwA5AgABLgAFFAIJBQAlAOkaAA==.Kytherin:BAAALgAECgYJDAAAAA==.',
La='Lactase:BAAALgADCgMJAwAAAA==.Lainea:BAAALgAECgMJAQAAAA==.Langtry:BAAALgADCgcJBgAAAA==.Latte:BAAALgAECgcJCgAAAA==.',
Le='Leblanc:BAAALgAECgEJAQABLgAECgkJGAAFAMUeAA==.Leeli:BAAALgADCgcJBwAAAA==.Lenity:BAABLgAECn9IAAIDAAkJsRdDAAA+AgADAAkJsRdDAAA+AgAAAA==.Letty:BAAALgAECgQJCAAAAA==.',
Li='Liabelle:BAAALgADCgIJAgAAAA==.Lightsmite:BAAALgAECgIJAgAAAA==.Lilithene:BAAALgAECgUJBgABLgAECgkJLgAPAMoWAA==.Lionbark:BAAALgADCgEJAQAAAA==.Lithpally:BAAALgADCgEJAQAAAA==.Liubeijian:BAAALgADCgYJBgABLgAECgcJFgAIAC4SAA==.',
Lo='Loan:BAAALgADCgQJAwABLgADCgkJEAAaAAAAAA==.Lokinah:BAABLgAECn8dAAIGAAgJqgfEgAA9AQAGAAgJqgfEgAA9AQAAAA==.Loonytusk:BAAALgADCgQJBAAAAA==.',
Lu='Lucifermadis:BAAALgAECgQJBgAAAA==.Lucoryphus:BAABLgAECn8hAAIjAAcJ1RfXGQCQAQAjAAcJ1RfXGQCQAQAAAA==.Lukeduke:BAABLgAFFH8TAAIZAAgJFx4bBAAvAgAZAAgJFx4bBAAvAgAAAA==.Luketheduke:BAACLgAFFH8ZAAMNAAYJgR5RBADGAQANAAUJgR5RBADGAQAYAAEJAAAIBwA3AAAuAAQKfyoAAw0ACQkvJR8BAFcDAA0ACQkvJR8BAFcDABgABAmxFXscAAkBAAEuAAUUCAkTABkAFx4A.Lumilia:BAAALgADCgUJBQAAAA==.Lunaries:BAAALgAECgYJBgAAAA==.Lunä:BAACLgAFFH8GAAIOAAMJMByHAwAAAQAOAAMJMByHAwAAAQAuAAQKfyYAAg4ACQlUFmoiABACAA4ACQlUFmoiABACAAAA.',
Ly='Lydia:BAABLgAECn8pAAIJAAkJphk2NABIAgAJAAkJphk2NABIAgAAAA==.Lynnee:BAAALgADCgEJAQAAAA==.',
['Lô']='Lôckrocks:BAABLgAECn8ZAAIHAAcJxhGODwBHAQAHAAcJxhGODwBHAQAAAA==.',
['Lý']='Lýsendra:BAAALgADCggJCQAAAA==.',
Ma='Magickeys:BAAALgAFFAIJAgAAAA==.Magictomb:BAACLgAFFH8HAAMdAAMJ0Aj3EAC4AAAdAAMJ0Aj3EAC4AAAPAAEJrgE5IQA7AAAuAAQKfy8ABA8ACAmXFeE4AFMBAA8ACAmXFeE4AFMBAA4ABgnpDTB8AOsAAB0ABQkzCjMiAOUAAAAA.Mahdude:BAAALgAECgEJAQAAAA==.Malastor:BAAALgAECgEJAQABLgAFFAMJBAAaAAAAAA==.Malcontent:BAAALgAECgcJDAABLgAFFAMJBAAaAAAAAA==.Maldazane:BAAALgADCgYJCwAAAA==.Malfeasance:BAAALgADCgkJDQABLgAFFAMJBAAaAAAAAA==.Malidan:BAAALgADCgMJAwAAAA==.Malifel:BAABLgAECn8eAAMmAAgJAyFEBACBAgAmAAgJAyFEBACBAgAIAAEJUAdYMAEhAAABLgAFFAMJBAAaAAAAAA==.Maliss:BAABLgAECn8+AAQBAAkJRRgfFAAEAgABAAkJahcfFAAEAgACAAQJ8RHKIQCjAAAGAAEJoxEPLwE3AAAAAA==.Mallord:BAAALgAFFAMJBAAAAA==.Mandarin:BAABLgAECn84AAITAAkJ8hoMEwCzAgATAAkJ8hoMEwCzAgAAAA==.Manmythlegnd:BAAALgADCgYJBgAAAA==.Mannik:BAABLgAECn8aAAIXAAgJrRmOMgAOAgAXAAgJrRmOMgAOAgAAAA==.Marashade:BAAALgAECgUJBQAAAA==.Marashades:BAAALgAECgUJBgABLgAECgkJHgAZAJgjAA==.',
Mc='Mcbadden:BAAALgAECgYJCAAAAA==.',
Me='Meditatetoe:BAAALgADCgIJAgABLgADCgYJBgAaAAAAAA==.Melissà:BAAALgADCgMJAwAAAA==.Menesta:BAAALgADCgcJBwABLgAECgUJEwAaAAAAAA==.Mercia:BAABLgAECn8vAAIEAAkJExuDCQA3AgAEAAkJExuDCQA3AgAAAA==.Merekoma:BAABLgAECn8tAAMIAAkJJhkPLQATAgAIAAkJ5RQPLQATAgAmAAQJFhY6HQCxAAAAAA==.',
Mi='Milarra:BAABLgAECn8VAAInAAcJMAnZCAD9AAAnAAcJMAnZCAD9AAAAAA==.Milhouse:BAABLgAECn8VAAIJAAcJuwqoqAAtAQAJAAcJuwqoqAAtAQAAAA==.Minalan:BAAALgADCgYJCgABLgAECgYJEQAaAAAAAA==.Mingonashoba:BAABLgAECn8hAAIGAAkJLA67RgDNAQAGAAkJLA67RgDNAQAAAA==.Miragosa:BAABLgAECn8yAAMKAAkJUA+VDwDSAQAKAAkJUA+VDwDSAQALAAcJ3gg7EAAHAQAAAA==.Misschris:BAABLgAECn8tAAIUAAkJBA1zQABsAQAUAAkJBA1zQABsAQAAAA==.Mistycinamon:BAAALgADCgYJBgAAAA==.Mizu:BAAALgAECgUJBQAAAA==.',
Mo='Moadeed:BAABLgAECn8ZAAINAAkJNRNiEgDLAQANAAkJNRNiEgDLAQAAAA==.Mooluv:BAAALgADCgcJCgAAAA==.Moonstrike:BAAALgAECgIJAgAAAA==.Mordrius:BAAALgADCgYJBgAAAA==.Morphmious:BAAALgAECgcJBwAAAA==.Mortesque:BAAALgAECgcJEgAAAA==.',
Mu='Muttblitzed:BAABLgAECn8aAAIGAAgJnxZlBADzAAAGAAgJnxZlBADzAAAAAA==.Muttskî:BAAALgAECgMJAwAAAA==.',
My='Mybutt:BAAALgAECgMJBgAAAA==.Myroku:BAAALgADCgcJBwABLgAFFAMJBAAaAAAAAA==.Myrothos:BAAALgADCgEJAQAAAA==.Myrrh:BAABLgAECn8YAAMlAAYJdAedYQC1AAAlAAYJggadYQC1AAALAAQJ9wYzLQCxAAAAAA==.Mythris:BAAALgAECgkJBQAAAA==.',
['Mí']='Místermage:BAAALgAECgQJCAAAAA==.',
Na='Nadrael:BAAALgAECgEJAwAAAA==.Nasturtium:BAAALgADCgYJDgAAAA==.Nausican:BAABLgAECn9IAAIiAAkJvxo9BACLAgAiAAkJvxo9BACLAgAAAA==.Nazuhda:BAAALgADCgEJAQAAAA==.',
Ne='Necrosector:BAACLgAFFH8KAAIFAAUJAgo3VgADAQAFAAUJAgo3VgADAQAuAAQKfyYAAgUACAm5GdJOANsBAAUACAm5GdJOANsBAAAA.Necrotherys:BAABLgAECn84AAIIAAkJPhz0FwCGAgAIAAkJPhz0FwCGAgAAAA==.Nelandra:BAABLgAECn8hAAIRAAgJKxlqFgAXAgARAAgJKxlqFgAXAgAAAA==.',
Ni='Nicklaus:BAABLgAECn8oAAIDAAcJlglmLwAjAQADAAcJlglmLwAjAQAAAA==.Nilrem:BAAALgADCgIJAgAAAA==.Ninelives:BAAALgAECgYJDgAAAA==.Ninjadk:BAECLgAFFH8UAAMQAAUJdh5lUABRAQAQAAQJdh5lUABRAQAjAAEJAABZZQAAAAAuAAQKfzEAAxAACQmyIf8OAPQCABAACQmyIf8OAPQCACIAAQm4G6M3AD4AAAAA.',
No='Nocapongfrfr:BAAALgAECgMJAwABLgAFFAUJBQAiAMIFAA==.Nomahuata:BAABLgAECn9IAAIPAAkJyhh6FQA9AgAPAAkJyhh6FQA9AgAAAA==.Nordre:BAAALgAECgMJAwAAAA==.',
Nu='Nufrus:BAAALgAECgEJAQAAAA==.',
Ny='Nyeli:BAAALgAECgQJBwABLgAECgYJGQAOALwXAA==.Nyxi:BAABLgAECn8dAAIOAAgJABnTIABKAgAOAAgJABnTIABKAgAAAA==.Nyxlee:BAAALgAECgcJBwAAAA==.',
['Né']='Néo:BAAALgAECgUJCAAAAA==.',
['Nó']='Nóóôööôòòpe:BAABLgAFFH8GAAIGAAQJpAbzWgDvAAAGAAQJpAbzWgDvAAABLgAFFAUJBQAiAMIFAA==.',
Og='Ogdruid:BAAALgADCgcJDgAAAA==.',
Ok='Okume:BAAALgAECgIJAgAAAA==.',
Ol='Olympian:BAAALgADCgcJBwAAAA==.',
Om='Omanyte:BAAALgADCgcJBwAAAA==.',
On='Onefiftyone:BAABLgAECn8bAAMdAAYJHCVICgAVAgAdAAYJHCVICgAVAgAOAAIJnSQmigDHAAABLgAECgkJLAAiAMkhAA==.',
Or='Orruk:BAAALgADCgMJAwAAAA==.Orwyn:BAAALgADCgkJEwAAAA==.',
Ov='Overdose:BAAALgADCgMJAwAAAA==.',
Pa='Padmé:BAAALgAECgQJBgAAAA==.Pain:BAAALgAECgUJCwAAAA==.Palanas:BAAALgAFFAEJAQAAAA==.Pallamoo:BAAALgAECgcJCAAAAA==.Palochka:BAAALgAECgcJBwAAAA==.Paradots:BAABLgAECn8WAAIKAAYJwBpqEgCiAQAKAAYJwBpqEgCiAQABLgAFFAIJBQATAMUSAA==.Paranitis:BAAALgAECggJDAAAAA==.Paranorm:BAAALgADCgEJAQAAAA==.Paraparaboom:BAAALgAECgUJBQABLgAFFAQJDgAJAN8XAA==.',
Pe='Pezdormu:BAAALgADCgEJAQAAAA==.Pezmage:BAAALgAECgIJBAAAAA==.',
Ph='Phatboi:BAAALgAECgEJAwAAAA==.Pheroth:BAAALgAECgUJCgABLgAECggJHAAHAFQMAA==.',
Pi='Pixystix:BAABLgAECn8kAAIIAAgJmxieNAD0AQAIAAgJmxieNAD0AQAAAA==.',
Po='Poisonspain:BAAALgAECgMJAwAAAA==.Popsdh:BAAALgAECggJEwABLgAECgkJIAAEAEwdAA==.Portlukk:BAAALgADCgEJAQABLgAFFAQJFgAGAPsZAA==.Possibly:BAAALgAECgEJAQAAAA==.Potscold:BAACLgAFFH8QAAIJAAgJARaGDAC5AQAJAAgJARaGDAC5AQAuAAQKf0EAAgkACAnbJbsRAD0DAAkACAnbJbsRAD0DAAAA.Poxi:BAAALgAECgIJAgABLgAECggJGAAJADwdAA==.',
Pr='Prion:BAABLgAECn8fAAIgAAgJ7xT3KQCwAQAgAAgJ7xT3KQCwAQAAAA==.',
Pu='Pull:BAABLgAECn8jAAINAAkJnxssCgBFAgANAAkJnxssCgBFAgAAAA==.',
Ra='Radioshack:BAAALgADCggJCAAAAA==.Radkemonko:BAAALgAECgcJDwAAAA==.Raega:BAAALgADCgYJBgAAAA==.Ragerlock:BAAALgADCgEJAQAAAA==.Raivel:BAABLgAECn8ZAAIOAAYJvBf6RgCSAQAOAAYJvBf6RgCSAQAAAA==.Raldaron:BAAALgADCgEJAQAAAA==.Rambogg:BAAALgAECgEJAQABLgAFFAcJGwAJAM0QAA==.Raneyth:BAAALgAECgcJBwAAAA==.Ranith:BAAALgADCgMJAwAAAA==.Ravagèr:BAAALgAECgEJAgAAAA==.',
Rd='Rdbwarrior:BAAALgADCgUJBQAAAA==.',
Re='Redemus:BAAALgADCgEJAQAAAA==.Redwinetoast:BAABLgAECn8kAAIXAAkJUAV+kQAYAQAXAAkJUAV+kQAYAQAAAA==.Rekllaw:BAAALgAECgEJAQAAAA==.Reliala:BAAALgADCgkJEQAAAA==.Reno:BAAALgADCgkJEAAAAA==.Reshyk:BAABLgAECn8UAAIYAAkJOxyUCwACAgAYAAkJOxyUCwACAgAAAA==.Resles:BAAALgAECgEJAQAAAA==.Respectwomen:BAAALgADCgEJAQABLgAECgQJBAAaAAAAAA==.',
Rh='Rhobes:BAABLgAECn8bAAIgAAgJOxDjAQD1AAAgAAgJOxDjAQD1AAAAAA==.Rhondta:BAABLgAECn8nAAIXAAkJJRLqRQDJAQAXAAkJJRLqRQDJAQAAAA==.',
Ri='Rickormortis:BAABLgAECn8UAAIQAAkJGB1iHgCRAgAQAAkJGB1iHgCRAgABLgAECgkJLQAUAAQNAA==.Rictus:BAABLgAECn8wAAIJAAkJjSSNCAA4AwAJAAkJjSSNCAA4AwAAAA==.Ringmasterr:BAAALgADCgUJBQAAAA==.Riordaa:BAAALgADCgYJDAAAAA==.Risingdragon:BAABLgAECn8qAAIcAAcJMhOFLgBQAQAcAAcJMhOFLgBQAQAAAA==.',
Ro='Roades:BAAALgADCgcJDAAAAA==.Roboskritch:BAAALgADCgUJBQAAAA==.Ronaj:BAAALgADCgMJBAAAAA==.Rowene:BAAALgAECgIJAgAAAA==.Royveer:BAAALgADCgYJCQAAAA==.',
Ru='Rumor:BAABLgAECn8kAAUYAAgJcRXAEwCDAQAYAAcJvxTAEwCDAQATAAcJ4Qp/YQARAQANAAMJlwzkXABVAAAVAAIJdAkLgwBDAAABLgAECggJNwAFAHURAA==.Rurry:BAACLgAFFH8YAAIKAAYJpRe+BACuAQAKAAYJpRe+BACuAQAuAAQKfy4ABAoACQnIIrECAEADAAoACQnIIrECAEADAAsABQm6GR4WAI8BACUAAwlVF/RGAL8AAAEuAAUUCAkVABMA+hEA.',
Ry='Ryumi:BAABLgAECn8uAAIIAAkJMyJdFwCKAgAIAAkJMyJdFwCKAgAAAA==.Ryur:BAAALgAECgQJDgAAAA==.Ryuuki:BAAALgAECgEJAQABLgAECgkJLgAIADMiAA==.',
Sa='Sabastion:BAAALgAECgYJBgABLgAFFAMJBAAaAAAAAA==.Sacrickficed:BAAALgAECgQJBAABLgAECgkJLQAUAAQNAA==.Sahwe:BAABLgAECn8UAAMTAAYJnwwCagD2AAATAAYJnwwCagD2AAAVAAEJ0wcZmAAoAAAAAA==.Salmoo:BAAALgADCgMJAwABLgAECgUJEwAaAAAAAA==.Salocar:BAAALgAECgcJEwAAAA==.Sanafela:BAAALgADCgkJVQAAAA==.Saphisha:BAABLgAECn8UAAIcAAgJVxcIIACtAQAcAAgJVxcIIACtAQAAAA==.Sasora:BAAALgAECgUJCwAAAA==.Saucemagic:BAAALgAECgcJDQAAAA==.Savonah:BAAALgAECgUJBgAAAA==.',
Sc='Scaledaddy:BAABLgAECn8jAAIlAAkJug0GKgCYAQAlAAkJug0GKgCYAQAAAA==.Scalespawn:BAAALgADCgYJBgABLgAFFAgJHgAQAEwZAA==.Scaryl:BAAALgAECgcJEAAAAA==.Scourgespawn:BAACLgAFFH8eAAQQAAgJTBlsJADcAQAQAAYJJhtsJADcAQAiAAQJgxJ2DAA3AQAjAAIJpwjEQwAnAAAuAAQKfyoAAxAACQmyIDMkAK0CABAACQmyIDMkAK0CACMABAnhFXE5AK0AAAAA.',
Se='Searthenio:BAAALgAECggJCAAAAA==.Selenë:BAABLgAECn8eAAMMAAcJyhbiHQDWAQAMAAcJyhbiHQDWAQARAAEJxwF3nAAWAAAAAA==.Sengoku:BAAALgAECgEJAQAAAA==.Serbiscuit:BAAALgAECgUJCgAAAA==.Sereneya:BAAALgAECgYJBgAAAA==.Serenio:BAAALgAECgcJEQAAAA==.Serenval:BAAALgAECgEJAQAAAA==.',
Sh='Shadowshart:BAAALgAECgEJAQAAAA==.Shailora:BAAALgAECgMJAwAAAA==.Shait:BAAALgADCgYJBgAAAA==.Shalis:BAABLgAECn8sAAIGAAkJWxx0HAB6AgAGAAkJWxx0HAB6AgAAAA==.Sharivee:BAABLgAECn8cAAMJAAkJ6SDlEgDpAgAJAAkJuh/lEgDpAgAeAAUJWB0pCAB3AQAAAA==.Sharko:BAABLgAECn8cAAQEAAgJExeSDwDMAQAEAAcJzhWSDwDMAQAFAAUJhBkyqQApAQAkAAIJwgOQiwBPAAAAAA==.Sharvalee:BAAALgAECgUJBQAAAA==.Shibui:BAABLgAECn9UAAQhAAkJ6RruCgB5AgAhAAkJ6RruCgB5AgAIAAcJvAYvowDNAAAmAAQJQQ6QHQCvAAAAAA==.Shiggles:BAABLgAECn8iAAIQAAkJEBp9KABfAgAQAAkJEBp9KABfAgABLgAFFAIJBQAFAHUVAA==.Shinhaein:BAABLgAECn8jAAIJAAgJ0BOFAgBJAQAJAAgJ0BOFAgBJAQABLgAFFAYJGgAQAN4VAA==.Shinxu:BAAALgADCgQJBAAAAA==.Shizmael:BAAALgAECgYJDAAAAA==.Shockazilla:BAABLgAECn83AAMkAAkJbR7fCAD9AgAkAAkJbR7fCAD9AgAFAAMJVw+z/wCWAAAAAA==.Shreddarfort:BAAALgADCgkJFQAAAA==.Shönuff:BAAALgAECgEJAQAAAA==.',
Si='Sigh:BAAALgAFFAEJAQAAAA==.Silverhorn:BAABLgAECn8kAAIFAAcJNxzbTQDeAQAFAAcJNxzbTQDeAQAAAA==.',
Sk='Skoduh:BAABLgAECn8iAAIGAAgJqhwRVACnAQAGAAgJqhwRVACnAQAAAA==.Skyelene:BAABLgAECn8uAAMPAAkJyhZjFwAqAgAPAAkJyhZjFwAqAgAOAAcJvwa3egDvAAAAAA==.',
Sl='Slaanesh:BAABLgAECn8hAAQHAAkJ3RZaDAB5AQAXAAcJNBK8TQCxAQAHAAcJOBZaDAB5AQAWAAMJlhsqFwDFAAAAAA==.Sluggo:BAABLgAFFH8HAAIFAAUJzxFWLABdAQAFAAUJzxFWLABdAQAAAA==.Sluggoboyce:BAACLgAFFH8GAAICAAQJhgR9EwAHAQACAAQJhgR9EwAHAQAuAAQKfyIAAwIACAkLGSEcAEcCAAIACAnYGCEcAEcCAAYABAmEDS6aAJ8AAAAA.',
Sm='Smeagosses:BAAALgAECgEJAQAAAA==.Smokeü:BAAALgAECgcJBwAAAA==.',
So='Solace:BAABLgAECn8gAAIIAAgJoCAVAQBrAQAIAAgJoCAVAQBrAQAAAA==.Solinaara:BAAALgAECgQJBAAAAA==.Soraka:BAABLgAFFH8LAAISAAQJnQpaKwD2AAASAAQJnQpaKwD2AAAAAA==.Soulstoner:BAAALgAECgEJAQAAAA==.',
Sp='Spiralist:BAABLgAECn8dAAQTAAkJ4xakTgBUAQATAAgJfBWkTgBUAQAVAAYJARm2NwA2AQAYAAIJkAwJQwBVAAAAAA==.Spiralmist:BAAALgADCgUJBQAAAA==.',
St='Starge:BAAALgAECgUJBQAAAA==.Steelforged:BAAALgADCgkJEAABLgAECgYJFAAcALQMAA==.Stonedalways:BAABLgAECn8hAAMOAAgJphAvPwCxAQAOAAgJphAvPwCxAQAPAAMJvQSEiwBZAAAAAA==.',
Su='Sunfuri:BAABLgAECn85AAIgAAkJDQozNgBvAQAgAAkJDQozNgBvAQAAAA==.Sunjan:BAAALgAECgQJBwAAAA==.Sus:BAACLgAFFH8hAAIhAAcJ7RtyAwABAgAhAAcJ7RtyAwABAgAuAAQKfyUAAiEACQmXI5cDAEcDACEACQmXI5cDAEcDAAAA.Susanoo:BAABLgAECn8ZAAIgAAkJcRRoJADRAQAgAAkJcRRoJADRAQAAAA==.',
Sy='Sylvíadne:BAAALgAECgYJBgAAAA==.',
Sz='Szul:BAAALgADCgcJDAAAAA==.',
Ta='Tachima:BAAALgAECgcJEAABLgAECgkJLgAIADMiAA==.Tactics:BAAALgADCgcJDAAAAA==.Tahitimango:BAABLgAECn8mAAIIAAYJmgNP0gCPAAAIAAYJmgNP0gCPAAAAAA==.Takeko:BAAALgADCgcJDgABLgAECggJEwAaAAAAAA==.Talanas:BAAALgADCgcJBwAAAA==.Taleria:BAAALgADCgYJHwAAAA==.Taranad:BAAALgAECgcJDAAAAA==.Tarathor:BAABLgAECn8hAAIVAAgJuBkiGAAMAgAVAAgJuBkiGAAMAgAAAA==.Tasha:BAAALgAECgEJAwABLgAECggJHwAgAO8UAA==.Tauroctony:BAABLgAECn8eAAINAAgJKiGhBACiAgANAAgJKiGhBACiAgAAAA==.',
Te='Tea:BAABLgAECn8WAAMZAAgJHQzEIQAiAQAZAAgJHQzEIQAiAQAgAAUJFAQffgB9AAABLgAECgkJRAAMAPYfAA==.Teknofarious:BAAALgAECgEJBAAAAA==.Tenom:BAAALgAECgUJCgAAAA==.',
Th='Thalar:BAAALgAECgIJAgAAAA==.Thaumas:BAAALgADCgEJAQAAAA==.Thelsyn:BAAALgAECgIJAgABLgAECgkJPgABAEUYAA==.Thermite:BAAALgAECgYJBgAAAA==.Thesafe:BAAALgAECgMJBAAAAA==.Thialaa:BAAALgAECgEJAwABLgAECgkJSAAGAJUkAA==.Thialia:BAAALgAECgkJEwABLgAECgkJSAAGAJUkAA==.Thialiaa:BAAALgAECgYJBwABLgAECgkJSAAGAJUkAA==.Thorey:BAAALgAECgEJAQAAAA==.Thornbreaker:BAAALgADCgEJAQAAAA==.Thorthunda:BAAALgAECgQJBgAAAA==.',
Ti='Tinkabella:BAABLgAECn87AAISAAkJLiNpAgCSAwASAAkJLiNpAgCSAwAAAA==.Tizl:BAEALgAECgUJBQABLgAFFAUJFAAQAHYeAA==.',
To='Tobi:BAAALgADCgQJBAAAAA==.Tobiblindpaw:BAAALgAECgYJDwAAAA==.Tobinir:BAAALgADCgkJCQAAAA==.Toenailjuice:BAAALgADCgUJBQABLgAECgkJOwAUAKkjAA==.Togo:BAAALgAECgYJBgAAAA==.Torrey:BAABLgAECn8YAAIkAAgJHyVuAwA8AwAkAAgJHyVuAwA8AwAAAA==.Tovarek:BAAALgADCgIJAgAAAA==.',
Tr='Trema:BAAALgAECgEJAgAAAA==.Trix:BAABLgAECn8vAAIOAAgJHw1kWABWAQAOAAgJHw1kWABWAQAAAA==.',
Tu='Tulsami:BAAALgAECgIJAwAAAA==.Tulsi:BAABLgAECn88AAIoAAkJYyS0AAA+AwAoAAkJYyS0AAA+AwAAAA==.Tuskoo:BAAALgAECgcJEQAAAA==.',
Ty='Tyrathion:BAAALgAECgMJAwAAAA==.Tyronos:BAABLgAECn8hAAIFAAkJQxkQLQBMAgAFAAkJQxkQLQBMAgAAAA==.',
Uk='Uknôwnforce:BAAALgAECgMJBAAAAA==.',
Un='Unbeetable:BAAALgADCgUJBQAAAA==.',
Va='Vaeltharion:BAAALgADCgEJAQAAAA==.Valanoth:BAABLgAECn8jAAIIAAgJ1SBkHQBkAgAIAAgJ1SBkHQBkAgAAAA==.Valdr:BAABLgAECn8hAAMlAAkJfRPQIgDEAQAlAAkJfRPQIgDEAQALAAQJowzXKQDQAAAAAA==.Valoryck:BAAALgAECgQJDQABLgAECggJIwAIANUgAA==.Vas:BAAALgAECgMJBgAAAA==.',
Ve='Velielina:BAAALgAECgEJAQAAAA==.Velistos:BAAALgADCgEJAQAAAA==.Vellandrias:BAAALgADCgYJBgAAAA==.Verinda:BAAALgADCgcJDwAAAA==.Vessara:BAAALgAECgEJAQABLgAFFAUJDwANAPYTAA==.Vevicenth:BAAALgAECgkJEgAAAA==.',
Vo='Voodoolily:BAAALgAECgUJBgAAAA==.Voranth:BAAALgAECgEJAQAAAA==.',
Wa='Warpsbulge:BAACLgAFFH8gAAIJAAcJ2x1lCgDMAQAJAAcJ2x1lCgDMAQAuAAQKfxsAAwkACQlNIb4hAOwCAAkACQlNIb4hAOwCAB4AAgl2FLQTAIoAAAAA.',
Wh='Whakan:BAAALgAECgEJAgABLgAECgcJIQAjANUXAA==.',
Wo='Wolfos:BAABLgAECn8fAAINAAkJEiaSAABwAwANAAkJEiaSAABwAwAAAA==.',
Wt='Wtfox:BAEBLgAECn8ZAAMRAAgJTg/fLwBfAQARAAgJTg/fLwBfAQASAAQJZQJSdAA/AAABLgAECgkJMwAPAKQbAA==.',
Wu='Wulfgange:BAAALgADCgEJAQAAAA==.',
Wy='Wysteri:BAABLgAECn8WAAIIAAcJLhLsZgBYAQAIAAcJLhLsZgBYAQAAAA==.',
Xa='Xadrai:BAAALgADCgIJAgAAAA==.Xakeko:BAAALgAECggJEwAAAA==.Xalatos:BAAALgAECgEJAgAAAA==.Xalfein:BAAALgAECgQJBAAAAA==.',
Xi='Xinu:BAAALgAECgcJBwABLgAECgkJRAAGANogAA==.',
Ya='Yanakana:BAAALgAECgcJBwAAAA==.',
Yd='Ydalise:BAAALgAECgEJAgAAAA==.Ydrassil:BAABLgAECn8VAAINAAkJcxpvCQBTAgANAAkJcxpvCQBTAgABLgAECgkJIAAEAEwdAA==.',
Yi='Yitsuni:BAAALgAECgcJDQAAAA==.',
Za='Zalaeda:BAAALgAECgEJAQAAAA==.Zalena:BAAALgAECgQJCAAAAA==.Zatriani:BAAALgAECgYJCgAAAA==.',
Ze='Zenus:BAABLgAECn8iAAMGAAgJsxWBVACmAQAGAAgJsxWBVACmAQACAAMJqwexNwBAAAAAAA==.Zerina:BAAALgADCgUJBQAAAA==.Zesty:BAAALgADCgMJAwAAAA==.Zeusal:BAABLgAECn8hAAIVAAcJjQ+SNgA8AQAVAAcJjQ+SNgA8AQAAAA==.Zeusinator:BAABLgAECn8sAAIGAAkJzxnzIwBTAgAGAAkJzxnzIwBTAgAAAA==.',
Zi='Zinu:BAABLgAECn9EAAIGAAkJ2iDtEwCzAgAGAAkJ2iDtEwCzAgAAAA==.Zivalisse:BAAALgAECgUJCAAAAA==.',
Zu='Zulfionn:BAABLgAECn8oAAIGAAkJYApVWQCYAQAGAAkJYApVWQCYAQAAAA==.',
Zy='Zylah:BAAALgADCgEJAQAAAA==.',
['Áy']='Áyrá:BAABLgAECn8uAAIkAAkJGxukGABCAgAkAAkJGxukGABCAgAAAA==.',
['Åp']='Åpollyon:BAAALgAECgYJBwAAAA==.',
['Øu']='Øuroboros:BAABLgAECn8lAAQKAAgJvxnNCwAbAgAKAAcJyxrNCwAbAgALAAYJ5hp8FAChAQAlAAQJ1heQRQDHAAAAAA==.',
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
