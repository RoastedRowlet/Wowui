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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Devourer','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Monk-Brewmaster','Druid-Guardian','Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','Priest-Shadow','Priest-Discipline','Druid-Restoration','Monk-Mistweaver','Druid-Balance','Warlock-Affliction','Warlock-Demonology','Druid-Feral','Warrior-Protection','Unknown-Unknown','Warrior-Arms','Monk-Windwalker','Shaman-Enhancement','Mage-Arcane','Warrior-Fury','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Evoker-Augmentation','DemonHunter-Vengeance','Mage-Fire','Rogue-Assassination',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abelene:BAAALgAECgQJBAAAAA==.Abrâham:BAAALgADCgUJBQAAAA==.',
Ac='Achelis:BAABLgAECn86AAMBAAkJ8CVZAQBUAwABAAkJ8CVZAQBUAwACAAEJAABJggA/AAAAAA==.',
Ad='Adianitefall:BAAALgAECgUJBgAAAA==.Adorian:BAABLgAECn8jAAIDAAkJUQi8JwBZAQADAAkJUQi8JwBZAQAAAA==.Adros:BAABLgAECn8oAAMEAAgJQRQMFQB+AQAEAAgJQRQMFQB+AQAFAAEJHwS4wgEiAAAAAA==.Adrrel:BAAALgADCgIJAgABLgAFFAgJIQAGAGQYAA==.Adrrelle:BAACLgAFFH8hAAQGAAgJZBjHGwCXAQAGAAYJbRzHGwCXAQABAAQJWg9lFAAqAQACAAYJaw1aEgAWAQAuAAQKfyUABAIACQncHXcTAJkCAAIACAmXH3cTAJkCAAEABAnaF7I7AOIAAAYAAwmpEW64AFIAAAAA.',
Ae='Aelon:BAABLgAECn8cAAIFAAgJxgeTrwAkAQAFAAgJxgeTrwAkAQAAAA==.',
Ah='Aheiro:BAAALgAECgQJCQAAAA==.',
Ai='Ailaith:BAABLgAECn9JAAIGAAkJ0STUAwBTAwAGAAkJ0STUAwBTAwAAAA==.',
Ak='Akariliselle:BAABLgAECn8XAAIHAAcJwRoYCgCkAQAHAAcJwRoYCgCkAQAAAA==.Akarue:BAAALgAECgQJBAAAAA==.Akibafaris:BAAALgAECgkJEgAAAA==.Aknologia:BAAALgAECgUJDQAAAA==.',
Al='Al:BAAALgADCggJCAAAAA==.Alan:BAAALgAECgUJCQAAAA==.Alarielle:BAAALgADCgkJEwAAAA==.Alcun:BAAALgAECgIJAwAAAA==.Aldora:BAAALgADCgkJDAAAAA==.Alirik:BAAALgADCgQJBQAAAA==.Alleriah:BAAALgAECgcJCAABLgAECggJIwAIANUgAA==.Alon:BAAALgAECgIJAgAAAA==.Alydrostage:BAABLgAECn8qAAIJAAkJhwhnoAA6AQAJAAkJhwhnoAA6AQAAAA==.Alystriaz:BAABLgAECn8mAAMKAAkJPxpABgCkAgAKAAkJPxpABgCkAgALAAEJsQWEKQAoAAAAAA==.Alzheimerz:BAAALgAECgUJBQAAAA==.',
Am='Amaelalin:BAABLgAECn9EAAIMAAkJ9h+vBAA1AwAMAAkJ9h+vBAA1AwAAAA==.Amaribo:BAAALgAECgEJAQABLgAFFAUJGQANAO4mAA==.Ameliya:BAAALgAECgIJAgAAAA==.Ameng:BAAALgAECgQJBgAAAA==.',
An='Anaralyth:BAAALgAECgYJCAABLgAFFAUJEAAOAPYTAA==.Andaya:BAACLgAFFH8ZAAMPAAUJ9SAZFwCtAQAPAAUJ9SAZFwCtAQAQAAEJnwNjYAAtAAAuAAQKfyMAAw8ACQmrGac8ALwBAA8ACQmrGac8ALwBABAAAgndDAaGAGQAAAAA.Andemeli:BAABLgAECn8oAAIFAAgJKQ5vCAAlAQAFAAgJKQ5vCAAlAQAAAA==.Andevyn:BAAALgAECgQJBAABLgAECggJIwAIANUgAA==.Aninja:BAEALgADCgQJBAABLgAFFAUJFAARAHYeAA==.Anivia:BAABLgAECn8fAAIJAAkJORHUVgDZAQAJAAkJORHUVgDZAQAAAA==.Ankoubailith:BAAALgAECgQJBgAAAA==.',
Ap='Apollon:BAAALgADCgIJAwAAAA==.',
Ar='Arandis:BAABLgAECn8kAAMSAAgJawwQQwADAQASAAYJXA4QQwADAQATAAQJkQjdVwChAAAAAA==.Arch:BAAALgAECgQJBQAAAA==.Arcianna:BAABLgAECn8yAAMOAAkJ2B2EBgCVAgAOAAkJ2B2EBgCVAgAUAAEJQRHf0wAxAAAAAA==.Arctica:BAABLgAECn8gAAIJAAYJEQ7bCgADAQAJAAYJEQ7bCgADAQAAAA==.Arctiq:BAAALgADCgUJCgAAAA==.Arctîc:BAABLgAECn8qAAIJAAkJFhPRUgDkAQAJAAkJFhPRUgDkAQAAAA==.Arjurn:BAABLgAECn87AAIJAAkJByBaFADfAgAJAAkJByBaFADfAgAAAA==.Arkro:BAAALgAECgMJBAAAAA==.Armpitbutter:BAABLgAECn87AAIVAAkJqSMJBAB1AwAVAAkJqSMJBAB1AwAAAA==.Artymiss:BAABLgAECn8cAAMWAAkJ5hFuIgC2AQAWAAkJ5hFuIgC2AQAUAAYJmRNLVgBQAQAAAA==.',
As='Asherah:BAABLgAECn8hAAMXAAgJhgf0FQAbAQAXAAcJegj0FQAbAQAYAAcJugFo9AB5AAAAAA==.Ashireita:BAAALgAECgYJEAABLgAECgkJLgAQAMoWAA==.Ashwadawnguh:BAAALgAECgEJAQAAAA==.Astraleth:BAACLgAFFH8QAAQOAAUJ9hMyHACvAAAWAAMJqxVRLgDNAAAOAAQJqgoyHACvAAAUAAEJcwJVcwAzAAAuAAQKfxsAAw4ACQniGAISANABAA4ABwkaFwISANABABYABgm5F9ZFAPUAAAAA.',
At='Atama:BAAALgAECgQJBwAAAA==.Atharius:BAAALgADCgEJAQAAAA==.',
Au='Aurturious:BAAALgAECgQJBAAAAA==.Authority:BAAALgAECgMJAwAAAA==.Autry:BAABLgAECn8xAAMZAAkJ1g9tEACwAQAZAAkJ1g9tEACwAQAUAAgJUgpZUwBCAQAAAA==.',
Av='Avelina:BAAALgADCgkJFAAAAA==.Avocat:BAABLgAECn8uAAIGAAkJiRsjFwCcAgAGAAkJiRsjFwCcAgAAAA==.',
Ay='Ayrilia:BAAALgAECgYJCAABLgAFFAUJEAAOAPYTAA==.Ayshama:BAAALgAECgQJBAAAAA==.',
Az='Azeria:BAAALgAECgUJCQABLgAFFAgJEwAaABceAA==.Azetbur:BAAALgAECgQJBAAAAA==.Azshura:BAAALgAECgYJBgAAAA==.Azzinôth:BAAALgADCgcJBwABLgAECgEJAgAbAAAAAA==.',
Ba='Baekr:BAAALgAECgYJEAAAAA==.Baldr:BAABLgAECn8wAAIFAAkJKhM+TQDfAQAFAAkJKhM+TQDfAQAAAA==.Balgar:BAABLgAECn8aAAMGAAkJhCP7JABPAgAGAAkJhCP7JABPAgACAAUJyxm3PgBgAQAAAA==.Balghas:BAABLgAECn8kAAIFAAgJ1hzQMwBTAgAFAAgJ1hzQMwBTAgAAAA==.Bamz:BAAALgAFFAEJAQABLgAFFAUJHAAMAGMUAA==.Bamzhurt:BAABLgAFFH8FAAIcAAMJZxGcJgDTAAAcAAMJZxGcJgDTAAABLgAFFAUJHAAMAGMUAA==.Baumstrum:BAAALgAECgYJDQAAAA==.',
Be='Bearlydrae:BAAALgAECgEJAgAAAA==.Beezlbubba:BAAALgAECgYJDAAAAA==.Beldam:BAAALgADCgYJBgAAAA==.Belispeak:BAAALgADCgYJBgAAAA==.Bellaboom:BAAALgADCgYJBgAAAA==.Belvkara:BAAALgADCgkJCQAAAA==.Benedictoe:BAAALgADCgYJBgAAAA==.',
Bh='Bhozok:BAABLgAECn83AAIZAAkJvBI/DgDSAQAZAAkJvBI/DgDSAQAAAA==.',
Bi='Bint:BAAALgAECgEJAQAAAA==.',
Bl='Bloodpromise:BAAALgADCgMJAwAAAA==.Bloodrayvn:BAABLgAECn8wAAIGAAkJxR18GACUAgAGAAkJxR18GACUAgAAAA==.',
Bo='Boomchick:BAAALgAECgMJAwABLgAECgkJIAAGAOAdAA==.Boomparapara:BAACLgAFFH8OAAIJAAQJ3xf0TQBDAQAJAAQJ3xf0TQBDAQAuAAQKfycAAgkACQl9IKURAPACAAkACQl9IKURAPACAAAA.Borrkbuster:BAAALgAECgQJBAAAAA==.Bosta:BAAALgAECgQJCwAAAA==.Botkin:BAAALgADCgEJAQAAAA==.',
Br='Bradley:BAAALgAECgYJDgABLgAECgcJFwAMAJkiAA==.Brandywyne:BAAALgADCgEJAQAAAA==.Brenri:BAABLgAECn8eAAIQAAkJwgPEVgDgAAAQAAkJwgPEVgDgAAAAAA==.Brew:BAABLgAECn8lAAMNAAgJLxzzEwAQAgANAAgJLxzzEwAQAgAdAAEJ0Q0LfQAzAAAAAA==.Brewtality:BAABLgAFFH8GAAIVAAQJPBUMDgDvAAAVAAQJPBUMDgDvAAABLgAFFAIJBQAUAMUSAA==.Brkat:BAAALgAECgIJAgAAAA==.Brughe:BAABLgAECn8sAAIGAAkJJQ0TZAB9AQAGAAkJJQ0TZAB9AQAAAA==.',
Bu='Bubbleoseven:BAAALgADCgYJBgABLgAFFAIJBQAUAMUSAA==.Burntbum:BAAALgAECgUJBQAAAA==.Buttacutta:BAAALgADCgkJRgAAAA==.',
['Bä']='Bäné:BAAALgADCgIJAgAAAA==.',
Ca='Cairn:BAAALgADCgUJBQAAAA==.Camaracy:BAAALgAECgQJBAAAAA==.Caneste:BAACLgAFFH8QAAISAAYJqhm2DwBwAQASAAYJqhm2DwBwAQAuAAQKfx8AAhIACQm9HfcLAMMCABIACQm9HfcLAMMCAAAA.Capela:BAAALgADCgEJAQAAAA==.Capparelli:BAAALgADCgEJAQAAAA==.Cashoe:BAAALgADCgMJAwAAAA==.Catscan:BAACLgAFFH8FAAIUAAIJxRIsVgBuAAAUAAIJxRIsVgBuAAAuAAQKfyIAAhQACQniHV0OAOUCABQACQniHV0OAOUCAAAA.Catty:BAABLgAECn8vAAIZAAkJ/BeDCABEAgAZAAkJ/BeDCABEAgAAAA==.',
Cb='Cblock:BAAALgAECgUJBQABLgAFFAMJCAAeANAIAA==.',
Ce='Celeano:BAAALgADCgkJCQABLgAECgQJBAAbAAAAAA==.Celestyl:BAABLgAECn8wAAIfAAkJ6wy4BQB2AQAfAAkJ6wy4BQB2AQAAAA==.',
Ch='Charazard:BAAALgAECgUJCgABLgAECggJJQAKAL8ZAA==.Charming:BAAALgADCgMJAwAAAA==.Cheapbeer:BAABLgAECn8VAAIFAAkJVgir2ADnAAAFAAkJVgir2ADnAAAAAA==.Cheesehead:BAAALgADCggJEgAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chiforged:BAABLgAECn8UAAIdAAYJtAylSwDTAAAdAAYJtAylSwDTAAAAAA==.Chillybovine:BAABLgAECn8bAAIJAAcJCQqUsAAgAQAJAAcJCQqUsAAgAQAAAA==.Chromstrasza:BAABLgAECn8ZAAILAAcJHxjBCQCJAQALAAcJHxjBCQCJAQAAAA==.Chudderly:BAAALgADCgEJAgAAAA==.Chudders:BAAALgADCgIJAgAAAA==.',
Ci='Cirice:BAAALgAECgEJBAAAAA==.Citrouille:BAAALgAECgEJAgAAAA==.',
Cl='Clarence:BAAALgADCgIJAgABLgAFFAgJJQAYAAMaAA==.Clonazepam:BAAALgAECgQJBAABLgAECgkJIwADAFEIAA==.',
Co='Comitus:BAABLgAECn9IAAMcAAkJBhBlFwCgAQAcAAkJBhBlFwCgAQAgAAQJ+wNjgwCxAAAAAA==.Conjar:BAAALgAECgIJAgAAAA==.Conjarr:BAABLgAECn8zAAIMAAkJHRyxAQDEAQAMAAkJHRyxAQDEAQAAAA==.Cortisol:BAAALgADCgIJAgAAAA==.Corven:BAAALgAECgUJDAAAAA==.Cougardk:BAAALgAECgIJAgAAAA==.Cougarsixsix:BAABLgAECn8iAAIEAAgJnBXLGABWAQAEAAgJnBXLGABWAQAAAA==.Cougarwar:BAAALgAECgMJAwAAAA==.',
Cr='Crashnburn:BAAALgADCgcJDQAAAA==.Crazyoldbear:BAABLgAECn8eAAIaAAkJmCPuAwDuAgAaAAkJmCPuAwDuAgAAAA==.Creideam:BAAALgADCgkJBwAAAA==.Crimos:BAABLgAECn8wAAIRAAkJzRbsQAAAAgARAAkJzRbsQAAAAgAAAA==.Crystalliney:BAAALgADCgYJBgABLgAFFAUJGQANAO4mAA==.',
Cy='Cynnai:BAAALgADCgYJBgAAAA==.Cyrena:BAAALgADCgEJAQAAAA==.',
Da='Daerthor:BAABLgAECn8iAAIEAAkJOBo8CgAnAgAEAAkJOBo8CgAnAgAAAA==.Dalind:BAABLgAECn8jAAIUAAkJ0gZfaQD4AAAUAAkJ0gZfaQD4AAAAAA==.Dalshiro:BAAALgAECgYJCQAAAA==.Damaclies:BAABLgAECn9IAAMYAAkJTBgLPwDgAQAYAAgJQBYLPwDgAQAHAAUJfBgDGADiAAAAAA==.Damedolla:BAABLgAECn8fAAMIAAgJYQzDfwAgAQAIAAgJwwrDfwAgAQAhAAUJnw7EQAD3AAAAAA==.Dammerung:BAAALgAECgYJCAAAAA==.Darksyn:BAABLgAECn8fAAIHAAkJnA2BEgAiAQAHAAkJnA2BEgAiAQAAAA==.Darthbane:BAABLgAECn8VAAMRAAkJxgmFDADLAAAiAAgJHgXbHADnAAARAAQJuQ6FDADLAAAAAA==.Darthghidora:BAAALgADCgkJEQAAAA==.Darthstroyer:BAABLgAFFH8FAAQiAAUJwgUhGgC5AAAiAAMJjgYhGgC5AAARAAEJXQMcFwE9AAAjAAEJAACBYwAAAAAAAA==.Darude:BAAALgADCgcJEAAAAA==.Dashoka:BAAALgAECgEJAQAAAA==.Dattiffany:BAAALgAECgUJBQAAAA==.Dawnfist:BAAALgADCggJCAAAAA==.',
De='Deadstout:BAABLgAECn8VAAQiAAYJERyiAQAYAQAjAAQJqxxEIQBIAQAiAAYJphGiAQAYAQARAAEJUQCrqgENAAAAAA==.Deathevan:BAAALgAECggJDgABLgAECgkJLgAIADMiAA==.Deepspace:BAABLgAECn8uAAIhAAkJeSaHAACLAwAhAAkJeSaHAACLAwAAAA==.Deezknots:BAAALgAECggJCAAAAA==.Deezus:BAAALgADCgMJAwAAAA==.Dejagauth:BAAALgAECgYJDwABLgAECggJHQAkAPchAA==.Dekkan:BAAALgAECgYJEAAAAA==.Demonedd:BAAALgADCgMJAgAAAA==.Demòn:BAAALgAECgEJAQAAAA==.Desdia:BAABLgAECn8hAAIJAAgJCBkLBwBJAQAJAAgJCBkLBwBJAQAAAA==.',
Di='Dia:BAAALgAECgQJBwAAAA==.Diabetes:BAABLgAFFH8VAAIVAAcJzhoTFwDFAQAVAAcJzhoTFwDFAQAAAA==.Diastolic:BAAALgADCgUJBQAAAA==.Didyoudie:BAAALgAECggJDQAAAA==.Diend:BAABLgAECn9TAAIPAAkJgSTMAQCzAwAPAAkJgSTMAQCzAwAAAA==.Dill:BAAALgAECgEJAQABLgAECgkJOgABAPAlAA==.Dillathis:BAAALgADCgEJAQAAAA==.Discord:BAAALgAECgQJBQABLgAFFAMJBAAbAAAAAA==.Dissonanita:BAABLgAECn8YAAIGAAgJjBHpaQBuAQAGAAgJjBHpaQBuAQAAAA==.',
Dj='Djthelock:BAABLgAECn8sAAMYAAkJuRb8NQABAgAYAAgJxBP8NQABAgAHAAQJDhhPHADEAAAAAA==.',
Do='Dormoon:BAABLgAECn8bAAMgAAgJnQ1/QQA/AQAgAAgJnQ1/QQA/AQAaAAEJIBH9VAAuAAAAAA==.',
Dr='Drac:BAAALgADCgYJCgAAAA==.Draeblade:BAAALgAECgQJBAAAAA==.Dragath:BAAALgAECgYJDgAAAA==.Drakur:BAAALgAECgYJCQAAAA==.Drbrad:BAABLgAECn8XAAMMAAcJmSJ5FgAdAgAMAAcJmSJ5FgAdAgASAAMJDhAdcQBgAAAAAA==.Dreadfangs:BAAALgADCgQJBQAAAA==.Druen:BAABLgAECn8yAAIZAAkJHB53BAC4AgAZAAkJHB53BAC4AgAAAA==.Drunkenpo:BAABLgAECn9PAAQNAAkJ5yH4BADzAgANAAkJtSH4BADzAgAVAAUJ7hOeUQAoAQAdAAIJqCKxCABjAAAAAA==.Drykin:BAAALgAECgYJCwAAAA==.Drïzl:BAEALgAECgMJAwABLgAFFAUJFAARAHYeAA==.',
Du='Duckchow:BAAALgADCgYJBgAAAA==.Dugga:BAAALgADCgQJBAAAAA==.Duskmyre:BAABLgAECn8lAAIIAAkJbw0OWQB8AQAIAAkJbw0OWQB8AQAAAA==.',
Dw='Dwarfoo:BAABLgAECn8bAAMdAAkJBxeoPwABAQAdAAcJMxOoPwABAQAVAAMJlgjBmQBlAAAAAA==.Dweñde:BAABLgAECn8nAAIYAAkJigrVYAB+AQAYAAkJigrVYAB+AQAAAA==.',
['Dë']='Dëthmetal:BAABLgAECn8UAAIRAAUJnQxfwgD/AAARAAUJnQxfwgD/AAAAAA==.',
Ec='Ecthelion:BAAALgAECgEJAQAAAA==.',
Ed='Eddiemac:BAAALgAECgYJCgAAAA==.Eddrick:BAACLgAFFH8KAAIFAAMJthlHGQDLAAAFAAMJthlHGQDLAAAuAAQKfzcAAwUACQkwH44TAM0CAAUACQkqH44TAM0CAAQABQkvHZ0ZAEwBAAAA.Edoran:BAAALgADCggJCAAAAA==.Edrani:BAAALgAECgYJDgAAAA==.',
Ei='Eilethen:BAABLgAECn8mAAIXAAkJOxocBgAfAgAXAAkJOxocBgAfAgAAAA==.',
Ek='Ekassa:BAAALgADCgkJCQAAAA==.',
El='Elaína:BAAALgADCgMJAwABLgAFFAUJGQAXAMUSAA==.Elementoe:BAAALgADCgEJAQABLgADCgYJBgAbAAAAAA==.Elendil:BAAALgAECgMJAwAAAA==.Elissabethh:BAAALgAECgYJEAAAAA==.Elleryn:BAAALgAECgQJBAABLgAECgYJGQAPALwXAA==.Elminstar:BAAALgADCgIJAgAAAA==.Elêctra:BAAALgAECgEJAgABLgAFFAEJAQAbAAAAAA==.',
Em='Employee:BAABLgAECn8VAAIlAAgJ4wvCSAAIAQAlAAgJ4wvCSAAIAQAAAA==.',
En='Engo:BAABLgAECn9EAAMMAAkJdiRnAwBZAwAMAAkJdCNnAwBZAwATAAkJ9BslCQDhAgAAAA==.',
Er='Eradrá:BAACLgAFFH8ZAAMXAAUJxRJKEQCFAAAYAAUJxRIfVQAcAQAXAAIJAQxKEQCFAAAuAAQKf1AAAxcACQmzHugAAA4DABcACQmsG+gAAA4DABgACQm9GDUiAFkCAAAA.Eragon:BAAALgAECggJDgAAAA==.Erastrasza:BAAALgADCgYJCQAAAA==.Eroza:BAAALgAECgUJBgAAAA==.Ersey:BAAALgAECgQJBAABLgAFFAMJBwAUAO8HAA==.Ersèlla:BAACLgAFFH8HAAIUAAMJ7wdATACMAAAUAAMJ7wdATACMAAAuAAQKfy4AAxQACQmMGHobAGoCABQACQmMGHobAGoCABYAAQnYBSqdACQAAAAA.Erysira:BAAALgADCgkJCQABLgAECggJGwAJAEIRAA==.',
Et='Ethan:BAAALgAECgEJAgAAAQ==.',
Eu='Eureka:BAABLgAECn8gAAMEAAkJTB2ADgDbAQAEAAcJ1RyADgDbAQAFAAcJSRnuZQCkAQABLgAFFAMJBQAaAHoZAA==.',
Ev='Evandra:BAABLgAECn8vAAIPAAkJCxzGFgCTAgAPAAkJCxzGFgCTAgAAAA==.Evanorah:BAABLgAECn8cAAMHAAcJjwmHIgCcAAAYAAcJYAkMlAAUAQAHAAYJowWHIgCcAAAAAA==.',
Ex='Exïle:BAEALgAECgYJBgABLgAFFAUJFAARAHYeAA==.',
Fa='Faelithia:BAABLgAECn8WAAIMAAYJKA4PPQD/AAAMAAYJKA4PPQD/AAAAAA==.Fatalbrew:BAAALgAECgYJCwAAAA==.Fauxyalee:BAAALgADCgkJEgAAAA==.',
Fe='Feldush:BAAALgADCgYJBgABLgAECggJJQAKAL8ZAA==.Felforit:BAAALgADCgQJBAAAAA==.Felis:BAAALgAECgYJCgAAAA==.Felkardio:BAAALgAECgIJAgAAAA==.Feloth:BAAALgADCgYJCQAAAA==.Ferheim:BAAALgAECgYJDwAAAA==.Ferhold:BAAALgADCgYJBwAAAA==.Ferrovax:BAAALgADCgYJBgABLgAECgkJLQAIACYZAA==.',
Fi='Fiddyone:BAABLgAECn8sAAMiAAkJySEoAwC+AgAiAAkJtCEoAwC+AgARAAgJcR0pRQDzAQAAAA==.Figment:BAAALgADCgYJBgAAAA==.Fireburt:BAAALgADCgUJBQAAAA==.Fireslay:BAABLgAECn8YAAIkAAcJpBwHHgAmAgAkAAcJpBwHHgAmAgAAAA==.Fizzlegrin:BAAALgAECgIJAgAAAA==.',
Fl='Flarefly:BAAALgAECgEJAQAAAA==.Flaya:BAAALgAECgcJDAAAAA==.',
Fo='Fodurzin:BAAALgAECgUJEwAAAA==.Fonta:BAAALgAECgMJAwAAAA==.Fortuna:BAAALgADCgYJBgABLgAECgkJIAAGAOAdAA==.Foxingtobi:BAAALgADCgIJAgAAAA==.',
Fr='Frojio:BAABLgAECn8zAAIiAAkJ2hyaBQBYAgAiAAkJ2hyaBQBYAgAAAA==.Frosten:BAAALgAECgEJAQAAAA==.',
Fu='Furenio:BAABLgAECn8yAAIOAAkJ7xekDgD6AQAOAAkJ7xekDgD6AQAAAA==.',
Fy='Fyyre:BAAALgAECgUJBwAAAA==.',
Ga='Gabaghoul:BAACLgAFFH8YAAIFAAUJFh3zKgBhAQAFAAUJFh3zKgBhAQAuAAQKfzEAAgUACQl3IHoZAKsCAAUACQl3IHoZAKsCAAAA.Gaff:BAAALgAECgkJEwAAAA==.Galeana:BAAALgAECgMJAwABLgAECgkJXQAJAPAeAA==.Galvan:BAAALgAECgEJBAAAAA==.Gasheth:BAAALgAECgYJDQAAAA==.',
Ge='Gentyl:BAAALgAECgQJBAAAAA==.',
Gi='Giggleblast:BAAALgAECgIJAgAAAA==.',
Gl='Glizzydealer:BAAALgAECgEJAQAAAA==.',
Gr='Grauth:BAAALgADCgEJAQAAAA==.Graycen:BAAALgAECgUJCQAAAA==.Grido:BAAALgAECgIJAgAAAA==.Grimbrindral:BAABLgAECn8hAAMFAAcJ5hZDZAC5AQAFAAcJdBVDZAC5AQAEAAUJghrKFwBZAQAAAA==.Grimston:BAAALgADCgMJAwABLgAECgcJIQAFAOYWAA==.Gruzaxx:BAAALgADCgUJBQAAAA==.',
Gu='Gulishdaniel:BAABLgAFFH8GAAIXAAQJJQRRCQDlAAAXAAQJJQRRCQDlAAABLgAFFAYJEAASAKoZAA==.',
Ha='Hadin:BAABLgAECn9MAAMJAAkJMCTGBgBKAwAJAAkJMCTGBgBKAwAfAAMJqhysDwDHAAAAAA==.Hakeko:BAAALgAECgcJEAABLgAECggJFAARAIgRAA==.Halalnt:BAAALgAFFAIJAgAAAA==.Hanua:BAAALgADCgcJBwAAAA==.Haozhao:BAABLgAECn9MAAMOAAkJXRsuCQBYAgAOAAkJXRsuCQBYAgAZAAEJDhQnTwA7AAAAAA==.Hawktuahz:BAAALgAECgMJAwAAAA==.Hazenpryde:BAABLgAECn8fAAIOAAgJahoeEADnAQAOAAgJahoeEADnAQAAAA==.',
He='Hearsay:BAABLgAECn9DAAMFAAgJdREjcACOAQAFAAgJdREjcACOAQAkAAYJXwmoBADsAAABLgAECgkJJwAZAE4VAA==.Helden:BAAALgAECgEJAQAAAA==.Hephaistian:BAAALgAECgYJBgAAAA==.Hespera:BAACLgAFFH8UAAMUAAUJFQ9eJgApAQAUAAUJFQ9eJgApAQAWAAMJ8whCOgCQAAAuAAQKfyMAAxQACQnJIOkYAHACABQACAmiIekYAHACABYAAwmnFP5SAMMAAAAA.',
Hi='Hirari:BAABLgAECn8dAAMkAAYJBCWUFwBMAgAkAAYJBCWUFwBMAgAFAAEJFBpjeQFCAAAAAA==.',
Ho='Hodoor:BAAALgAECgEJAQAAAA==.Howlears:BAABLgAECn8qAAISAAkJHghOOwAlAQASAAkJHghOOwAlAQAAAA==.',
Hu='Hulud:BAABLgAECn8YAAMYAAkJfRbiSwC3AQAYAAkJfRbiSwC3AQAHAAEJAADYVAAAAAAAAA==.Husbando:BAAALgAECgMJAwAAAA==.Husey:BAAALgAECgMJBgAAAA==.',
Hy='Hydrangea:BAABLgAECn8dAAIFAAcJ4Q+VkQBPAQAFAAcJ4Q+VkQBPAQAAAA==.Hydrá:BAABLgAECn8aAAIYAAkJvRYCMQAUAgAYAAkJvRYCMQAUAgAAAA==.Hylan:BAAALgADCgUJBQAAAA==.Hysgar:BAAALgAECgUJBQABLgAECggJHQAkAPchAA==.',
Ic='Iceamaris:BAABLgAECn8gAAIQAAkJYQv/OABTAQAQAAkJYQv/OABTAQAAAA==.Icetiger:BAAALgAECgEJAQAAAA==.Icetigress:BAAALgAECgEJAQAAAA==.',
Ie='Iechu:BAABLgAECn8gAAMNAAgJbBFGIwCQAQANAAgJbBFGIwCQAQAdAAIJ9QZujABFAAAAAA==.',
In='Innanna:BAAALgADCggJCgABLgAECgcJFgAIAC4SAA==.',
Is='Isoth:BAAALgAECgEJAQAAAA==.',
Iv='Ivern:BAACLgAFFH8VAAIUAAgJ+hGKCAByAgAUAAgJ+hGKCAByAgAuAAQKfx0AAxQABgkHHfgyANIBABQABgkHHfgyANIBABYAAgnRBzWXACkAAAAA.Ivysnow:BAAALgAECgEJAQAAAA==.',
Ja='Jac:BAAALgAECgMJAwABLgAFFAMJBAAbAAAAAA==.Jadenpryde:BAAALgAECgYJBwABLgAECggJHwAOAGoaAA==.Jaod:BAAALgAECgQJAgAAAA==.Jarndal:BAAALgAECgEJAQAAAA==.Jasmirrae:BAAALgAECgEJAQAAAA==.',
Jd='Jdghoul:BAAALgAECggJDwAAAA==.',
Ji='Jian:BAAALgADCgIJAgAAAA==.Jindrac:BAAALgAECgkJDwAAAA==.',
Jo='Jolton:BAAALgADCgYJBwABLgAECgkJLgAIADMiAA==.',
['Jà']='Jàcaranda:BAAALgAECgYJBwAAAA==.',
Ka='Kahnrah:BAAALgADCgkJDAAAAA==.Kalarae:BAAALgAECggJCQAAAA==.Kalarill:BAABLgAECn8eAAIFAAcJZR1rMAA/AgAFAAcJZR1rMAA/AgAAAA==.Kaljeer:BAAALgAECgUJBQAAAA==.Kaltharion:BAABLgAFFH8HAAIKAAQJ6wMRCQB8AAAKAAQJ6wMRCQB8AAAAAA==.Kaluren:BAAALgAECgcJDwAAAA==.Kalurok:BAAALgAECgUJBQABLgAECgcJDwAbAAAAAA==.Kana:BAAALgAECgIJAgAAAA==.Kanade:BAABLgAECn9IAAQYAAkJBh7BFwCVAgAYAAgJ1R3BFwCVAgAXAAcJsRUACQDVAQAHAAQJWAsKTACJAAAAAA==.Kantong:BAABLgAECn8gAAIdAAgJdRmIGwDTAQAdAAgJdRmIGwDTAQAAAA==.Kapp:BAAALgAECgcJEwAAAA==.Karabar:BAABLgAECn87AAMEAAkJ2yAYBQCjAgAEAAkJyh4YBQCjAgAFAAgJoyDzKABfAgAAAA==.Karnnaged:BAAALgADCgYJBwAAAA==.Kasarra:BAABLgAECn8zAAIhAAkJhxX2EwDzAQAhAAkJhxX2EwDzAQAAAA==.Kazagol:BAABLgAECn87AAIIAAkJ+x2rGgB0AgAIAAkJ+x2rGgB0AgAAAA==.',
Ke='Kelintos:BAAALgAECgEJAgABLgAECgkJOAAIAD4cAA==.Keone:BAAALgADCgEJAQAAAA==.',
Kh='Khalla:BAAALgAFFAEJAQAAAA==.Khamaracy:BAABLgAECn8iAAMHAAkJuwlGFgD1AAAHAAkJuwlGFgD1AAAYAAEJsQE6ZQEbAAAAAA==.Khronni:BAAALgAECgYJCQAAAA==.Khrooze:BAAALgAECgYJEQAAAA==.',
Ki='Kidos:BAAALgAECgQJBgAAAA==.Kiljana:BAAALgAECgEJAQAAAA==.Kimahrí:BAABLgAECn8fAAIjAAkJSQd9LwDkAAAjAAkJSQd9LwDkAAAAAA==.Kittei:BAABLgAECn87AAIOAAkJ1w+eGwBwAQAOAAkJ1w+eGwBwAQAAAA==.',
Ko='Kojote:BAAALgADCgMJAQAAAA==.Kovalenko:BAAALgAECggJDgAAAA==.',
Kr='Krepow:BAAALgAECgYJCQAAAA==.',
Ku='Kurick:BAABLgAECn8dAAMkAAgJ9yEvCAAJAwAkAAgJ9yEvCAAJAwAFAAMJLQxWfgE+AAAAAA==.Kurzul:BAAALgADCgEJAgAAAA==.Kusinluvin:BAAALgAECgEJAQAAAA==.',
Ky='Kyngizzard:BAABLgAECn8fAAIJAAkJSRrUNwA5AgAJAAkJSRrUNwA5AgABLgAFFAIJAgAbAAAAAA==.Kytherin:BAAALgAECgYJDAAAAA==.',
La='Lactase:BAAALgADCgMJAwAAAA==.Lainea:BAAALgAECgMJAQAAAA==.Langtry:BAAALgADCgcJBgAAAA==.Lanoree:BAABLgAECn8WAAQiAAkJfQDJRgAGAAARAAYJMQAnrAEGAAAiAAkJfQDJRgAGAAAjAAIJAAAAAAAAAAAAAA==.Latte:BAAALgAECgcJCgAAAA==.',
Le='Leblanc:BAAALgAECgEJAQABLgAECgkJGAAFAMUeAA==.Leeli:BAAALgADCgcJBwAAAA==.Lenity:BAABLgAECn9RAAIDAAkJnhmHAACDAgADAAkJnhmHAACDAgAAAA==.Letty:BAAALgAECgQJCAAAAA==.',
Li='Liabelle:BAAALgADCgIJAgAAAA==.Lightsmite:BAAALgAECgIJAgAAAA==.Lilithene:BAAALgAECgUJBgABLgAECgkJLgAQAMoWAA==.Lionbark:BAAALgADCgEJAQAAAA==.Lionell:BAAALgADCgUJBgAAAA==.Lithpally:BAAALgADCgEJAQAAAA==.Liubeijian:BAAALgADCgYJBgABLgAECgcJFgAIAC4SAA==.',
Lo='Loan:BAAALgAECgQJBAABLgAECgUJBQAbAAAAAA==.Lokinah:BAABLgAECn8gAAIGAAkJ/gfBgAA9AQAGAAkJ/gfBgAA9AQAAAA==.Loonytusk:BAAALgADCgQJBAAAAA==.',
Lu='Lucifermadis:BAAALgAECgQJBgAAAA==.Lucoryphus:BAABLgAECn8hAAIjAAcJ1RfYGQCQAQAjAAcJ1RfYGQCQAQAAAA==.Lukeduke:BAABLgAFFH8TAAIaAAgJFx4ZBAAwAgAaAAgJFx4ZBAAwAgAAAA==.Luketheduke:BAACLgAFFH8ZAAMOAAYJgR5RBADGAQAOAAUJgR5RBADGAQAZAAEJAAAIBwA3AAAuAAQKfyoAAw4ACQkvJR8BAFcDAA4ACQkvJR8BAFcDABkABAmxFXscAAkBAAEuAAUUCAkTABoAFx4A.Lumilia:BAAALgADCgUJBQAAAA==.Lunaries:BAAALgAECgYJBgAAAA==.Lunä:BAACLgAFFH8IAAIPAAMJMBwpDAD6AAAPAAMJMBwpDAD6AAAuAAQKfyYAAg8ACQlUFmoiABACAA8ACQlUFmoiABACAAAA.',
Ly='Lydia:BAABLgAECn8pAAIJAAkJphkzNABIAgAJAAkJphkzNABIAgAAAA==.Lynnee:BAAALgADCgEJAQAAAA==.',
['Lô']='Lôckrocks:BAABLgAECn8ZAAIHAAcJxhGODwBHAQAHAAcJxhGODwBHAQAAAA==.',
['Lý']='Lýsendra:BAAALgADCggJCQAAAA==.',
Ma='Magickeys:BAAALgAFFAIJAgAAAA==.Magictomb:BAACLgAFFH8IAAMeAAMJ0Aj1EAC4AAAeAAMJ0Aj1EAC4AAAQAAEJrgE5IQA7AAAuAAQKfy8ABBAACAmXFeU4AFMBABAACAmXFeU4AFMBAA8ABgnpDTd8AOsAAB4ABQkzCjIiAOUAAAAA.Mahdude:BAAALgAECgEJAQAAAA==.Malastor:BAAALgAECgEJAQABLgAFFAMJBAAbAAAAAA==.Malcontent:BAAALgAECgcJEQABLgAFFAMJBAAbAAAAAA==.Maldazane:BAAALgADCgYJCwAAAA==.Malfeasance:BAAALgADCgkJDQABLgAFFAMJBAAbAAAAAA==.Malidan:BAAALgADCgMJAwAAAA==.Malifel:BAABLgAECn8mAAMmAAkJvSBjAAA2AgAmAAkJvSBjAAA2AgAIAAEJUAddMAEhAAABLgAFFAMJBAAbAAAAAA==.Maliss:BAABLgAECn8/AAQBAAkJRRgcFAAEAgABAAkJahccFAAEAgACAAQJ8RHLIQCjAAAGAAEJoxETLwE3AAAAAA==.Mallord:BAAALgAFFAMJBAAAAA==.Mandarin:BAABLgAECn84AAIUAAkJ8hoNEwCzAgAUAAkJ8hoNEwCzAgAAAA==.Manmythlegnd:BAAALgADCgYJBgAAAA==.Mannik:BAABLgAECn8aAAIYAAgJrRmPMgAOAgAYAAgJrRmPMgAOAgAAAA==.Marashade:BAAALgAECgUJBQAAAA==.Marashades:BAAALgAECgUJBgABLgAECgkJHgAaAJgjAA==.',
Mc='Mcbadden:BAAALgAECgYJCAAAAA==.',
Me='Meditatetoe:BAAALgADCgIJAgABLgADCgYJBgAbAAAAAA==.Melissà:BAAALgADCgMJAwAAAA==.Menesta:BAAALgADCgcJBwABLgAECgUJEwAbAAAAAA==.Mercia:BAABLgAECn8wAAIEAAkJExuDCQA3AgAEAAkJExuDCQA3AgAAAA==.Merekoma:BAABLgAECn8tAAMIAAkJJhkOLQATAgAIAAkJ5RQOLQATAgAmAAQJFhY8HQCxAAAAAA==.',
Mi='Milarra:BAABLgAECn8VAAInAAcJMAnaCAD9AAAnAAcJMAnaCAD9AAAAAA==.Milhouse:BAABLgAECn8dAAIJAAcJXgxqDwDFAAAJAAcJXgxqDwDFAAAAAA==.Minalan:BAAALgADCgYJCgABLgAECgYJEQAbAAAAAA==.Mingonashoba:BAABLgAECn8iAAIGAAkJYw69RgDNAQAGAAkJYw69RgDNAQAAAA==.Miragosa:BAABLgAECn8zAAMKAAkJUA+UDwDSAQAKAAkJUA+UDwDSAQALAAcJ3gg7EAAHAQAAAA==.Misschris:BAABLgAECn8tAAIVAAkJBA1zQABsAQAVAAkJBA1zQABsAQAAAA==.Mistycinamon:BAAALgAECgEJAQAAAA==.Mizu:BAAALgAECgUJBQAAAA==.',
Mo='Moadeed:BAABLgAECn8fAAMOAAkJbhViEgDLAQAOAAkJZhViEgDLAQAWAAMJdA0OCACFAAAAAA==.Mooluv:BAAALgADCgcJCgAAAA==.Moonstrike:BAAALgAECgIJAgAAAA==.Mordrius:BAAALgADCgYJBgAAAA==.Morphmious:BAAALgAECgcJBwAAAA==.Mortesque:BAAALgAECgcJEgAAAA==.',
Mu='Muttblitzed:BAABLgAECn8aAAIGAAgJnxZNTAC9AQAGAAgJnxZNTAC9AQAAAA==.Muttskî:BAAALgAECgMJAwAAAA==.',
My='Mybutt:BAAALgAECgMJBgAAAA==.Myroku:BAAALgADCgcJBwABLgAFFAMJBAAbAAAAAA==.Myrothos:BAAALgADCgEJAQAAAA==.Myrrh:BAABLgAECn8YAAMlAAYJdAefYQC1AAAlAAYJggafYQC1AAALAAQJ9wYzLQCxAAAAAA==.Mysklef:BAAALgADCgMJAwABLgAECggJHQAkAPchAA==.Mythris:BAAALgAECgkJBQAAAA==.',
['Mí']='Místermage:BAAALgAECgQJCAAAAA==.',
Na='Nadrael:BAAALgAECgEJAwAAAA==.Nasturtium:BAAALgADCgYJDgAAAA==.Nausican:BAABLgAECn9IAAIiAAkJvxo9BACLAgAiAAkJvxo9BACLAgAAAA==.Nazuhda:BAAALgADCgEJAQAAAA==.',
Ne='Necrosector:BAACLgAFFH8KAAIFAAUJAgoqVgADAQAFAAUJAgoqVgADAQAuAAQKfyYAAgUACAm5Gc9OANsBAAUACAm5Gc9OANsBAAAA.Necrotherys:BAABLgAECn84AAIIAAkJPhz0FwCGAgAIAAkJPhz0FwCGAgAAAA==.Nelandra:BAABLgAECn8jAAISAAkJnBlqFgAXAgASAAkJnBlqFgAXAgAAAA==.',
Ni='Nicklaus:BAABLgAECn8oAAIDAAcJlglnLwAjAQADAAcJlglnLwAjAQAAAA==.Nilrem:BAAALgADCgIJAgAAAA==.Ninelives:BAAALgAECgYJDgAAAA==.Ninjadk:BAECLgAFFH8UAAMRAAUJdh5gUABRAQARAAQJdh5gUABRAQAjAAEJAABVZQAAAAAuAAQKfzEAAxEACQmyIQAPAPQCABEACQmyIQAPAPQCACIAAQm4G6U3AD4AAAAA.',
No='Nocapongfrfr:BAAALgAECgMJAwABLgAFFAUJBQAiAMIFAA==.Nomahuata:BAABLgAECn9NAAIQAAkJZhkFAgCSAQAQAAkJZhkFAgCSAQAAAA==.Nordre:BAAALgAECgMJAwAAAA==.',
Nu='Nufrus:BAAALgAECgEJAQAAAA==.',
Ny='Nyeli:BAAALgAECgQJBwABLgAECgYJGQAPALwXAA==.Nyxi:BAABLgAECn8dAAIPAAgJABnTIABKAgAPAAgJABnTIABKAgAAAA==.Nyxlee:BAAALgAECgcJBwAAAA==.',
['Né']='Néo:BAAALgAECgUJCAAAAA==.',
['Nó']='Nóóôööôòòpe:BAABLgAFFH8HAAIGAAQJpAbyWgDvAAAGAAQJpAbyWgDvAAABLgAFFAUJBQAiAMIFAA==.',
Og='Ogdruid:BAAALgADCgcJDgAAAA==.',
Ok='Okume:BAAALgAECgIJAgAAAA==.',
Ol='Olympian:BAAALgADCgcJBwAAAA==.',
Om='Omanyte:BAAALgADCgcJBwAAAA==.',
On='Onefiftyone:BAABLgAECn8bAAMeAAYJHCVGCgAVAgAeAAYJHCVGCgAVAgAPAAIJnSQsigDHAAABLgAECgkJLAAiAMkhAA==.',
Or='Orruk:BAAALgADCgMJAwAAAA==.Orwyn:BAAALgADCgkJEwAAAA==.',
Ov='Overdose:BAAALgADCgMJAwAAAA==.',
Pa='Padmé:BAAALgAECgQJBgAAAA==.Pain:BAAALgAECgUJCwAAAA==.Palanas:BAAALgAFFAEJAQAAAA==.Pallamoo:BAAALgAECgcJCAAAAA==.Palochka:BAAALgAECgcJCQAAAA==.Paradots:BAABLgAECn8WAAIKAAYJwBpqEgCiAQAKAAYJwBpqEgCiAQABLgAFFAIJBQAUAMUSAA==.Paranitis:BAAALgAECggJDAAAAA==.Paranorm:BAAALgADCgEJAQAAAA==.Paraparaboom:BAAALgAECgUJBQABLgAFFAQJDgAJAN8XAA==.',
Pe='Pezdormu:BAAALgADCgEJAQAAAA==.Pezmage:BAAALgAECgIJBAAAAA==.',
Ph='Phatboi:BAAALgAECgEJAwAAAA==.Pheroth:BAAALgAECgUJDQABLgAECgkJHwAHAJwNAA==.',
Pi='Pixystix:BAABLgAECn8qAAIIAAkJeBkuAwB0AQAIAAkJeBkuAwB0AQAAAA==.',
Po='Poisonspain:BAAALgAECgMJAwAAAA==.Popsdh:BAAALgAECggJEwABLgAFFAMJBQAaAHoZAA==.Portlukk:BAAALgADCgEJAQAAAA==.Possibly:BAAALgAECgEJAQAAAA==.Potscold:BAACLgAFFH8QAAIJAAgJARaGDAC5AQAJAAgJARaGDAC5AQAuAAQKf0EAAgkACAnbJbsRAD0DAAkACAnbJbsRAD0DAAAA.Poxi:BAAALgAECgIJAgABLgAECggJGAAJADwdAA==.',
Pr='Prion:BAABLgAECn8fAAIgAAgJ7xT5KQCwAQAgAAgJ7xT5KQCwAQAAAA==.',
Pu='Pull:BAABLgAECn8jAAIOAAkJnxssCgBFAgAOAAkJnxssCgBFAgAAAA==.',
Ra='Radioshack:BAAALgADCggJCAAAAA==.Radkemonko:BAAALgAECgcJDwAAAA==.Raega:BAAALgADCgYJBgAAAA==.Ragerlock:BAAALgADCgEJAQAAAA==.Raivel:BAABLgAECn8ZAAIPAAYJvBf+RgCSAQAPAAYJvBf+RgCSAQAAAA==.Raldaron:BAAALgADCgEJAQAAAA==.Rambogg:BAAALgAECgEJAQABLgAFFAcJGwAJAM0QAA==.Raneyth:BAAALgAECgcJBwAAAA==.Ranith:BAAALgADCgMJAwAAAA==.Ravagèr:BAAALgAECgEJAgAAAA==.',
Rd='Rdbwarrior:BAAALgADCgUJBQAAAA==.',
Re='Redemus:BAAALgADCgEJAQAAAA==.Redwinetoast:BAABLgAECn8kAAIYAAkJUAWBkQAYAQAYAAkJUAWBkQAYAQAAAA==.Rekllaw:BAAALgAECgIJAgAAAA==.Reliala:BAAALgADCgkJEQAAAA==.Reno:BAAALgAECgUJBQAAAA==.Reshyk:BAABLgAECn8UAAIZAAkJOxyVCwACAgAZAAkJOxyVCwACAgAAAA==.Resles:BAAALgAECgEJAQAAAA==.Respectwomen:BAAALgADCgEJAQABLgAECgQJBAAbAAAAAA==.',
Rh='Rhobes:BAABLgAECn8bAAIgAAgJOxBoBQDxAAAgAAgJOxBoBQDxAAAAAA==.Rhondta:BAABLgAECn8nAAIYAAkJJRLrRQDJAQAYAAkJJRLrRQDJAQAAAA==.',
Ri='Rickormortis:BAABLgAECn8UAAIRAAkJGB1iHgCRAgARAAkJGB1iHgCRAgABLgAECgkJLQAVAAQNAA==.Rictus:BAABLgAECn8wAAIJAAkJjSSLCAA4AwAJAAkJjSSLCAA4AwAAAA==.Ringmasterr:BAAALgADCgUJBQAAAA==.Riordaa:BAAALgADCgYJDAAAAA==.Risingdragon:BAABLgAECn8qAAIdAAcJMhOHLgBQAQAdAAcJMhOHLgBQAQAAAA==.',
Ro='Roades:BAAALgADCgcJDAAAAA==.Roboskritch:BAAALgADCgUJBQAAAA==.Ronaj:BAAALgADCgMJBAAAAA==.Rowene:BAAALgAECgIJAgAAAA==.Royveer:BAAALgADCgYJCQAAAA==.',
Ru='Rumor:BAABLgAECn8nAAUZAAkJThXCEwCDAQAZAAcJvxTCEwCDAQAUAAgJqQp8YQARAQAOAAMJlwzmXABVAAAWAAIJdAkLgwBDAAAAAA==.Rurry:BAACLgAFFH8YAAIKAAYJpRe+BACuAQAKAAYJpRe+BACuAQAuAAQKfy4ABAoACQnIIrECAEADAAoACQnIIrECAEADAAsABQm6GR4WAI8BACUAAwlVF/RGAL8AAAEuAAUUCAkVABQA+hEA.',
Ry='Ryumi:BAABLgAECn8uAAIIAAkJMyJbFwCKAgAIAAkJMyJbFwCKAgAAAA==.Ryur:BAAALgAECgQJDgAAAA==.Ryuuki:BAAALgAECgYJBgABLgAECgkJLgAIADMiAA==.',
Sa='Sabastion:BAAALgAECgYJBgABLgAFFAMJBAAbAAAAAA==.Sacrickficed:BAAALgAECgQJBAABLgAECgkJLQAVAAQNAA==.Sahwe:BAABLgAECn8UAAMUAAYJnwz/aQD2AAAUAAYJnwz/aQD2AAAWAAEJ0wcemAAoAAAAAA==.Salmoo:BAAALgAECgMJBAABLgAECgUJEwAbAAAAAA==.Salocar:BAAALgAECgcJEwAAAA==.Sanafela:BAAALgADCgkJXgAAAA==.Saphisha:BAABLgAECn8UAAIdAAgJVxcIIACtAQAdAAgJVxcIIACtAQAAAA==.Sasora:BAAALgAECgUJCwAAAA==.Saucemagic:BAAALgAECgcJDQAAAA==.Savonah:BAAALgAECgUJBgAAAA==.',
Sc='Scaledaddy:BAABLgAECn8jAAIlAAkJug0HKgCYAQAlAAkJug0HKgCYAQAAAA==.Scalespawn:BAAALgADCgYJBgABLgAFFAgJHgARAEwZAA==.Scaryl:BAABLgAECn8WAAIWAAgJGQmyBADmAAAWAAgJGQmyBADmAAAAAA==.Scourgespawn:BAACLgAFFH8eAAQRAAgJTBlWJADcAQARAAYJJhtWJADcAQAiAAQJgxJzDAA3AQAjAAIJpwjBQwAnAAAuAAQKfyoAAxEACQmyIDMkAK0CABEACQmyIDMkAK0CACMABAnhFXI5AK0AAAAA.',
Se='Searthenio:BAAALgAECggJCAAAAA==.Selenë:BAABLgAECn8eAAMMAAcJyhbkHQDWAQAMAAcJyhbkHQDWAQASAAEJxwF/nAAWAAAAAA==.Sengoku:BAAALgAECgEJAQAAAA==.Seraz:BAAALgADCgkJCAAAAA==.Serbiscuit:BAAALgAECgUJCgAAAA==.Sereneya:BAAALgAECgYJBgAAAA==.Serenio:BAAALgAECgcJEQAAAA==.Serenval:BAAALgAECgEJAQAAAA==.',
Sh='Shadowshart:BAAALgAECgEJAQAAAA==.Shadus:BAAALgAECgUJBQAAAA==.Shadyaf:BAAALgAECgEJAQAAAA==.Shailora:BAAALgAECgMJAwAAAA==.Shait:BAAALgADCgYJBgAAAA==.Shalis:BAABLgAECn8sAAIGAAkJWxxzHAB6AgAGAAkJWxxzHAB6AgAAAA==.Sharivee:BAABLgAECn8cAAMJAAkJ6SDgEgDpAgAJAAkJuh/gEgDpAgAfAAUJWB0pCAB3AQAAAA==.Sharko:BAABLgAECn8cAAQEAAgJExeSDwDMAQAEAAcJzhWSDwDMAQAFAAUJhBkxqQApAQAkAAIJwgOQiwBPAAAAAA==.Sharvalee:BAAALgAECgUJBQAAAA==.Shibui:BAABLgAECn9VAAQhAAkJ6RrtCgB5AgAhAAkJ6RrtCgB5AgAIAAcJvAYvowDNAAAmAAQJQQ6RHQCvAAAAAA==.Shifthead:BAAALgADCgIJAgABLgAFFAUJBQAiAMIFAA==.Shiggles:BAABLgAECn8iAAIRAAkJEBp+KABfAgARAAkJEBp+KABfAgABLgAFFAIJBwAFAPwbAA==.Shinhaein:BAABLgAECn8jAAIJAAgJ0BNuBwBBAQAJAAgJ0BNuBwBBAQABLgAFFAYJGwARAN4VAA==.Shinxu:BAAALgADCgQJBAAAAA==.Shizmael:BAABLgAECn8UAAIJAAYJXQkADQDhAAAJAAYJXQkADQDhAAAAAA==.Shockazilla:BAABLgAECn83AAMkAAkJbR7fCAD9AgAkAAkJbR7fCAD9AgAFAAMJVw+z/wCWAAAAAA==.Shreddarfort:BAAALgADCgkJFQAAAA==.Shönuff:BAAALgAECgEJAQAAAA==.',
Si='Sigh:BAAALgAFFAEJAQAAAA==.Silverhorn:BAABLgAECn8kAAIFAAcJNxzXTQDeAQAFAAcJNxzXTQDeAQAAAA==.',
Sk='Skoduh:BAABLgAECn8iAAIGAAgJqhwRVACnAQAGAAgJqhwRVACnAQAAAA==.Skyelene:BAABLgAECn8uAAMQAAkJyhZiFwAqAgAQAAkJyhZiFwAqAgAPAAcJvwa+egDvAAAAAA==.',
Sl='Slaanesh:BAABLgAECn8hAAQHAAkJ3RZaDAB5AQAYAAcJNBK9TQCxAQAHAAcJOBZaDAB5AQAXAAMJlhsqFwDFAAAAAA==.Sluggo:BAABLgAFFH8HAAIFAAUJzxFGLABdAQAFAAUJzxFGLABdAQAAAA==.Sluggoboyce:BAACLgAFFH8GAAICAAQJhgR9EwAHAQACAAQJhgR9EwAHAQAuAAQKfyIAAwIACAkLGSEcAEcCAAIACAnYGCEcAEcCAAYABAmEDS6aAJ8AAAAA.',
Sm='Smeagosses:BAAALgAECgEJAQAAAA==.Smokeü:BAAALgAECgcJBwAAAA==.',
So='Solace:BAABLgAECn8iAAIIAAgJCSGgAQDwAQAIAAgJCSGgAQDwAQAAAA==.Solinaara:BAAALgAECgQJBAAAAA==.Soraka:BAABLgAFFH8LAAITAAQJnQpWKwD2AAATAAQJnQpWKwD2AAAAAA==.Soulstoner:BAAALgAECgEJAgAAAA==.',
Sp='Spiralist:BAABLgAECn8dAAQUAAkJ4xajTgBUAQAUAAgJfBWjTgBUAQAWAAYJARm6NwA2AQAZAAIJkAwIQwBVAAAAAA==.Spiralmist:BAAALgADCgUJBQAAAA==.',
St='Starge:BAAALgAECgUJBQAAAA==.Steelforged:BAAALgADCgkJEAABLgAECgYJFAAdALQMAA==.Stonedalways:BAABLgAECn8hAAMPAAgJphAyPwCxAQAPAAgJphAyPwCxAQAQAAMJvQSDiwBZAAAAAA==.',
Su='Sunfuri:BAABLgAECn85AAIgAAkJDQo0NgBvAQAgAAkJDQo0NgBvAQAAAA==.Sunjan:BAAALgAECgQJBwAAAA==.Sus:BAACLgAFFH8hAAIhAAcJ7RtyAwABAgAhAAcJ7RtyAwABAgAuAAQKfyUAAiEACQmXI5cDAEcDACEACQmXI5cDAEcDAAAA.Susanoo:BAABLgAECn8ZAAIgAAkJcRRpJADRAQAgAAkJcRRpJADRAQAAAA==.',
Sy='Sylvíadne:BAAALgAECgYJBgAAAA==.',
Sz='Szul:BAAALgADCgcJDAAAAA==.',
Ta='Taalia:BAAALgAECgQJBAABLgAECgkJIwAUANIGAA==.Tachima:BAAALgAECgcJEAABLgAECgkJLgAIADMiAA==.Tactics:BAAALgADCgcJDAAAAA==.Tahitimango:BAABLgAECn8pAAIIAAcJYwRT0gCPAAAIAAcJYwRT0gCPAAAAAA==.Takeko:BAAALgADCgcJDgABLgAECggJFAARAIgRAA==.Talanas:BAAALgADCgcJBwAAAA==.Taleria:BAAALgADCgYJIgAAAA==.Taranad:BAAALgAECgcJDAAAAA==.Tarathor:BAABLgAECn8jAAIWAAkJDRokGAAMAgAWAAkJDRokGAAMAgAAAA==.Tasha:BAAALgAECgEJAwABLgAECggJHwAgAO8UAA==.Tauroctony:BAABLgAECn8eAAIOAAgJKiGhBACiAgAOAAgJKiGhBACiAgAAAA==.',
Te='Tea:BAABLgAECn8XAAMaAAgJKgzEIQAiAQAaAAgJKgzEIQAiAQAgAAUJFAQhfgB9AAABLgAECgkJRAAMAPYfAA==.Teknofarious:BAAALgAECgEJBAAAAA==.Tenom:BAAALgAECgUJCgAAAA==.',
Th='Thalar:BAAALgAECgIJAgAAAA==.Thaumas:BAAALgADCgEJAQAAAA==.Thelsyn:BAAALgAECgIJAgABLgAECgkJPwABAEUYAA==.Thermite:BAAALgAECgYJBgAAAA==.Thesafe:BAAALgAECgMJBAAAAA==.Thialaa:BAAALgAECgEJAwABLgAECgkJSQAGANEkAA==.Thialia:BAAALgAECgkJEwABLgAECgkJSQAGANEkAA==.Thialiaa:BAAALgAECgYJBwABLgAECgkJSQAGANEkAA==.Thoralon:BAAALgADCgEJAQAAAA==.Thorey:BAAALgAECgEJAQAAAA==.Thornbreaker:BAAALgADCgEJAQAAAA==.Thorthunda:BAAALgAECgQJBgAAAA==.',
Ti='Tinkabella:BAABLgAECn87AAITAAkJLiNoAgCSAwATAAkJLiNoAgCSAwAAAA==.Tizl:BAEALgAECgUJBQABLgAFFAUJFAARAHYeAA==.',
Tm='Tmgwolf:BAAALgADCgUJCAAAAA==.',
To='Tobi:BAAALgADCgQJBAAAAA==.Tobiblindpaw:BAAALgAECgYJDwAAAA==.Tobinir:BAAALgADCgkJCQAAAA==.Toenailjuice:BAAALgADCgUJBQABLgAECgkJOwAVAKkjAA==.Togo:BAAALgAECgYJBgAAAA==.Torrey:BAABLgAECn8YAAIkAAgJHyVuAwA8AwAkAAgJHyVuAwA8AwAAAA==.Tovarek:BAAALgADCgIJAgAAAA==.',
Tr='Trema:BAAALgAECgQJBgAAAA==.Trix:BAABLgAECn8vAAIPAAgJHw1pWABVAQAPAAgJHw1pWABVAQAAAA==.Trounces:BAABLgAECn8gAAIlAAcJtRnkAQBgAQAlAAcJtRnkAQBgAQAAAA==.',
Tu='Tulsami:BAAALgAECgIJAwAAAA==.Tulsi:BAABLgAECn88AAIoAAkJYyS0AAA+AwAoAAkJYyS0AAA+AwAAAA==.Tuskoo:BAAALgAECgcJEQAAAA==.',
Ty='Tyrathion:BAAALgAECgMJAwAAAA==.Tyronos:BAABLgAECn8hAAIFAAkJQxkNLQBMAgAFAAkJQxkNLQBMAgAAAA==.',
Uk='Uknôwnforce:BAAALgAECgMJBAAAAA==.',
Un='Unbeetable:BAAALgADCgUJBQAAAA==.',
Va='Vaeltharion:BAAALgADCgEJAQAAAA==.Valanoth:BAABLgAECn8jAAIIAAgJ1SBiHQBkAgAIAAgJ1SBiHQBkAgAAAA==.Valdr:BAABLgAECn8hAAMlAAkJfRPRIgDEAQAlAAkJfRPRIgDEAQALAAQJowzXKQDQAAAAAA==.Valoryck:BAAALgAECgQJDQABLgAECggJIwAIANUgAA==.Vas:BAAALgAECgMJBgAAAA==.',
Ve='Velielina:BAAALgAECgEJAQAAAA==.Velistos:BAAALgADCgEJAQAAAA==.Vellandrias:BAAALgADCgYJBgAAAA==.Verinda:BAAALgADCgcJDwAAAA==.Vessara:BAAALgAECgEJAQABLgAFFAUJEAAOAPYTAA==.Vevicenth:BAAALgAECgkJEgAAAA==.',
Vo='Voodoolily:BAAALgAECgUJBgAAAA==.Voranth:BAAALgAECgEJAQAAAA==.',
Wa='Warpsbulge:BAACLgAFFH8gAAIJAAcJ2x1lCgDMAQAJAAcJ2x1lCgDMAQAuAAQKfxsAAwkACQlNIb4hAOwCAAkACQlNIb4hAOwCAB8AAgl2FLQTAIoAAAAA.',
Wh='Whakan:BAAALgAECgEJAgABLgAECgcJIQAjANUXAA==.',
Wo='Wolfos:BAABLgAECn8fAAIOAAkJEiaSAABwAwAOAAkJEiaSAABwAwAAAA==.',
Wt='Wtfox:BAEBLgAECn8dAAMSAAgJ5xGDBADwAAASAAgJ5xGDBADwAAATAAQJZQJUdAA/AAABLgAECgkJNQAQAKQbAA==.',
Wu='Wulfgange:BAAALgADCgEJAQAAAA==.',
Wy='Wysteri:BAABLgAECn8WAAIIAAcJLhLsZgBYAQAIAAcJLhLsZgBYAQAAAA==.',
Xa='Xadrai:BAAALgADCgIJAgAAAA==.Xakeko:BAABLgAECn8UAAQRAAgJiBG1rgAWAQARAAUJsxO1rgAWAQAiAAUJlRCXHgDYAAAjAAEJAACIDQAAAAAAAA==.Xalatos:BAAALgAECgEJAgAAAA==.Xalfein:BAAALgAECgQJBAAAAA==.',
Xi='Xinu:BAAALgAECgcJBwABLgAECgkJRQAGANogAA==.',
Ya='Yanakana:BAAALgAECgcJCwAAAA==.',
Yd='Ydalise:BAAALgAECgEJAgAAAA==.Ydrassil:BAABLgAECn8VAAIOAAkJcxpuCQBTAgAOAAkJcxpuCQBTAgABLgAFFAMJBQAaAHoZAA==.',
Yi='Yitsuni:BAAALgAECgcJDQAAAA==.',
Za='Zakeko:BAAALgAECgMJAwABLgAECggJFAARAIgRAA==.Zalaeda:BAAALgAECgEJAQAAAA==.Zalena:BAAALgAECgQJCAAAAA==.Zatriani:BAAALgAECgYJCgAAAA==.',
Ze='Zenus:BAABLgAECn8iAAMGAAgJsxWAVACmAQAGAAgJsxWAVACmAQACAAMJqwevNwBAAAAAAA==.Zerina:BAAALgADCgUJBQAAAA==.Zesty:BAAALgADCgMJAwAAAA==.Zeusal:BAABLgAECn8hAAIWAAcJjQ+VNgA8AQAWAAcJjQ+VNgA8AQAAAA==.Zeusinator:BAABLgAECn8sAAIGAAkJzxnyIwBTAgAGAAkJzxnyIwBTAgAAAA==.',
Zi='Zinu:BAABLgAECn9FAAIGAAkJ2iDrEwCzAgAGAAkJ2iDrEwCzAgAAAA==.Zivalisse:BAAALgAECgUJCAAAAA==.',
Zu='Zulfionn:BAABLgAECn8oAAIGAAkJYApUWQCYAQAGAAkJYApUWQCYAQAAAA==.',
Zy='Zylah:BAAALgADCgEJAQAAAA==.',
['Áy']='Áyrá:BAABLgAECn8uAAIkAAkJGxujGABCAgAkAAkJGxujGABCAgAAAA==.',
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
