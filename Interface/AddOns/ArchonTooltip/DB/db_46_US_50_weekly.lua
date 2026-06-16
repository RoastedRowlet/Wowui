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
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abelene:BAAALgAECgQJBAAAAA==.Abrâham:BAAALgADCgUJBQAAAA==.',
Ac='Achelis:BAABLgAECn86AAMBAAkJ8CU8AQBXAwABAAkJ8CU8AQBXAwACAAEJAABJggA/AAAAAA==.',
Ad='Adianitefall:BAAALgAECgQJBAAAAA==.Adorian:BAABLgAECn8gAAIDAAgJbwgnJwBZAQADAAgJbwgnJwBZAQAAAA==.Adros:BAABLgAECn8oAAMEAAgJQRQMFQB+AQAEAAgJQRQMFQB+AQAFAAEJHwQ0uwEiAAAAAA==.Adrrel:BAAALgADCgIJAgABLgAFFAgJIQAGAGQYAA==.Adrrelle:BAACLgAFFH8hAAQGAAgJZBiHGQCXAQAGAAYJbRyHGQCXAQABAAQJWg/aEwAqAQACAAYJaw1aEgAWAQAuAAQKfyUABAIACQncHXcTAJkCAAIACAmXH3cTAJkCAAEABAnaF+k6AOYAAAYAAwmpEW64AFIAAAAA.',
Ae='Aelon:BAABLgAECn8cAAIFAAgJxgeTrwAkAQAFAAgJxgeTrwAkAQAAAA==.',
Ah='Aheiro:BAAALgAECgQJCQAAAA==.',
Ai='Ailaith:BAABLgAECn9HAAIGAAkJlSSeAwBUAwAGAAkJlSSeAwBUAwAAAA==.',
Ak='Akariliselle:BAABLgAECn8XAAIHAAcJwRrKCQClAQAHAAcJwRrKCQClAQAAAA==.Akarue:BAAALgAECgQJBAAAAA==.Akibafaris:BAAALgAECggJDwAAAA==.Aknologia:BAAALgAECgUJCAAAAA==.',
Al='Al:BAAALgADCggJCAAAAA==.Alan:BAAALgAECgUJCAAAAA==.Alarielle:BAAALgADCgkJEwAAAA==.Aldora:BAAALgADCgkJDAAAAA==.Alirik:BAAALgADCgQJBQAAAA==.Alleriah:BAAALgAECgcJCAABLgAECggJIwAIANUgAA==.Alydrostage:BAABLgAECn8pAAIJAAgJLgcfngA7AQAJAAgJLgcfngA7AQAAAA==.Alystriaz:BAABLgAECn8lAAMKAAkJPxooBgCkAgAKAAkJPxooBgCkAgALAAEJsQXbKAAoAAAAAA==.Alzheimerz:BAAALgAECgUJBQAAAA==.',
Am='Amaelalin:BAABLgAECn9EAAIMAAkJ9h+TBAA1AwAMAAkJ9h+TBAA1AwAAAA==.Ameliya:BAAALgAECgIJAgAAAA==.Ameng:BAAALgAECgQJBgAAAA==.',
An='Anaralyth:BAAALgAECgUJBgABLgAFFAUJDwANAPYTAA==.Andaya:BAACLgAFFH8WAAMOAAUJ+RtwFQCuAQAOAAUJ+RtwFQCuAQAPAAEJnwPZXAAtAAAuAAQKfyMAAw4ACQmrGY87ALwBAA4ACQmrGY87ALwBAA8AAgndDKGDAGQAAAAA.Andemeli:BAABLgAECn8bAAIFAAgJSQ3HhwBeAQAFAAgJSQ3HhwBeAQAAAA==.Andevyn:BAAALgAECgQJBAABLgAECggJIwAIANUgAA==.Aninja:BAEALgADCgQJBAABLgAFFAUJFAAQAHYeAA==.Anivia:BAABLgAECn8fAAIJAAkJORFtVQDZAQAJAAkJORFtVQDZAQAAAA==.Ankoubailith:BAAALgAECgQJBgAAAA==.',
Ap='Apollon:BAAALgADCgIJAwAAAA==.',
Ar='Arandis:BAABLgAECn8kAAMRAAgJawzcQQAGAQARAAYJXA7cQQAGAQASAAQJkQhXVgCiAAAAAA==.Arch:BAAALgAECgQJBQAAAA==.Arcianna:BAABLgAECn8xAAMNAAkJ2B1bBgCVAgANAAkJ2B1bBgCVAgATAAEJQRHI0QAxAAAAAA==.Arctica:BAABLgAECn8WAAIJAAYJ+go/yAD5AAAJAAYJ+go/yAD5AAAAAA==.Arctiq:BAAALgADCgUJCgAAAA==.Arctîc:BAABLgAECn8pAAIJAAkJXRJvUQDlAQAJAAkJXRJvUQDlAQAAAA==.Arjurn:BAABLgAECn87AAIJAAkJByDZEwDgAgAJAAkJByDZEwDgAgAAAA==.Arkro:BAAALgAECgMJBAAAAA==.Armpitbutter:BAABLgAECn87AAIUAAkJqSPzAwB0AwAUAAkJqSPzAwB0AwAAAA==.Artymiss:BAABLgAECn8YAAMVAAkJ+Q+JIQC4AQAVAAkJ+Q+JIQC4AQATAAYJmRNLVgBQAQAAAA==.',
As='Asherah:BAABLgAECn8dAAMWAAgJhgdZFQAcAQAWAAcJeghZFQAcAQAXAAcJugGq8QB7AAAAAA==.Ashireita:BAAALgAECgYJEAABLgAECgkJLAAPAMoWAA==.Ashwadawnguh:BAAALgAECgEJAQAAAA==.Astraleth:BAACLgAFFH8PAAQNAAUJ9hMhGgC2AAAVAAMJqxX4LADOAAANAAQJqgohGgC2AAATAAEJcwLkcAAzAAAuAAQKfxoAAw0ACAm+F4wRAM8BAA0ABwkaF4wRAM8BABUABQlvFeJEAPQAAAAA.',
At='Atama:BAAALgAECgQJBwAAAA==.Atharius:BAAALgADCgEJAQAAAA==.',
Au='Aurturious:BAAALgAECgQJBAAAAA==.Authority:BAAALgAECgMJAwAAAA==.Autry:BAABLgAECn8xAAMYAAkJ1g8dEACvAQAYAAkJ1g8dEACvAQATAAgJUgp7UgBDAQAAAA==.',
Av='Avelina:BAAALgADCgkJFAAAAA==.Avocat:BAABLgAECn8uAAIGAAkJiRtRFgCeAgAGAAkJiRtRFgCeAgAAAA==.',
Ay='Ayrilia:BAAALgAECgUJBwABLgAFFAUJDwANAPYTAA==.',
Az='Azeria:BAAALgAECgUJCQABLgAFFAgJEwAZABceAA==.Azshura:BAAALgAECgEJAQAAAA==.Azzinôth:BAAALgADCgcJBwABLgAECgEJAgAaAAAAAA==.',
Ba='Baekr:BAAALgAECgYJEAAAAA==.Baldr:BAABLgAECn8vAAIFAAkJKhMjSwDjAQAFAAkJKhMjSwDjAQAAAA==.Balgar:BAABLgAECn8YAAMGAAgJBCPgIwBQAgAGAAgJBCPgIwBQAgACAAUJyxm3PgBgAQAAAA==.Balghas:BAABLgAECn8kAAIFAAgJ1hzQMwBTAgAFAAgJ1hzQMwBTAgAAAA==.Bamz:BAAALgAFFAEJAQABLgAFFAUJFwAMAGMUAA==.Bamzhurt:BAAALgAFFAEJAgABLgAFFAUJFwAMAGMUAA==.Baumstrum:BAAALgAECgYJDQAAAA==.',
Be='Bearlydrae:BAAALgAECgEJAQAAAA==.Beezlbubba:BAAALgAECgUJCwAAAA==.Beldam:BAAALgADCgYJBgAAAA==.Belispeak:BAAALgADCgYJBgAAAA==.Bellaboom:BAAALgADCgYJBgAAAA==.Belvkara:BAAALgADCgkJCQAAAA==.Benedictoe:BAAALgADCgYJBgAAAA==.',
Bh='Bhozok:BAABLgAECn83AAIYAAkJvBIGDgDQAQAYAAkJvBIGDgDQAQAAAA==.',
Bi='Bint:BAAALgAECgEJAQAAAA==.',
Bl='Bloodpromise:BAAALgADCgMJAwAAAA==.Bloodrayvn:BAABLgAECn8vAAIGAAkJxR2fFwCVAgAGAAkJxR2fFwCVAgAAAA==.',
Bo='Boomchick:BAAALgAECgMJAwAAAA==.Boomparapara:BAACLgAFFH8NAAIJAAQJ3xebSwBPAQAJAAQJ3xebSwBPAQAuAAQKfyYAAgkACQl9ICsRAPECAAkACQl9ICsRAPECAAAA.Borrkbuster:BAAALgAECgQJBAAAAA==.Bosta:BAAALgAECgQJBgAAAA==.Botkin:BAAALgADCgEJAQAAAA==.',
Br='Bradley:BAAALgAECgYJDgABLgAECgYJFgAMAEUjAA==.Brandywyne:BAAALgADCgEJAQAAAA==.Brenri:BAABLgAECn8dAAIPAAkJmAMKVQDhAAAPAAkJmAMKVQDhAAAAAA==.Brew:BAABLgAECn8kAAMbAAcJwB+uEwARAgAbAAcJwB+uEwARAgAcAAEJ0Q0LfQAzAAAAAA==.Brewtality:BAAALgAFFAEJAQABLgAECgkJIgATAOIdAA==.Brkat:BAAALgAECgIJAgAAAA==.Brughe:BAABLgAECn8rAAIGAAkJJQ0RYgB9AQAGAAkJJQ0RYgB9AQAAAA==.',
Bu='Bubbleoseven:BAAALgADCgYJBgABLgAECgkJIgATAOIdAA==.Buttacutta:BAAALgADCgkJNAAAAA==.',
['Bä']='Bäné:BAAALgADCgIJAgAAAA==.',
Ca='Cairn:BAAALgADCgUJBQAAAA==.Caneste:BAACLgAFFH8QAAIRAAYJqhn9DgBxAQARAAYJqhn9DgBxAQAuAAQKfx8AAhEACQm9HfcLAMMCABEACQm9HfcLAMMCAAAA.Capela:BAAALgADCgEJAQAAAA==.Capparelli:BAAALgADCgEJAQAAAA==.Cashoe:BAAALgADCgMJAwAAAA==.Catscan:BAABLgAECn8iAAITAAkJ4h0mDgDlAgATAAkJ4h0mDgDlAgAAAA==.Catty:BAABLgAECn8vAAIYAAkJ/BdhCABDAgAYAAkJ/BdhCABDAgAAAA==.',
Cb='Cblock:BAAALgAECgUJBQABLgAFFAMJBgAdANAIAA==.',
Ce='Celeano:BAAALgADCgkJCQABLgAECgQJBAAaAAAAAA==.Celestyl:BAABLgAECn8tAAIeAAkJvwqaBQB4AQAeAAkJvwqaBQB4AQAAAA==.',
Ch='Charazard:BAAALgAECgUJCgABLgAECggJJQAKAL8ZAA==.Charming:BAAALgADCgMJAwAAAA==.Cheapbeer:BAABLgAECn8VAAIFAAkJVgju1ADpAAAFAAkJVgju1ADpAAAAAA==.Cheesehead:BAAALgADCggJEgAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chiforged:BAABLgAECn8UAAIcAAYJtAz6SQDWAAAcAAYJtAz6SQDWAAAAAA==.Chillybovine:BAABLgAECn8bAAIJAAcJCQp7rgAgAQAJAAcJCQp7rgAgAQAAAA==.Chromstrasza:BAABLgAECn8ZAAILAAcJHximCQCJAQALAAcJHximCQCJAQAAAA==.Chudderly:BAAALgADCgEJAgAAAA==.Chudders:BAAALgADCgIJAgAAAA==.',
Ci='Cirice:BAAALgAECgEJAQAAAA==.Citrouille:BAAALgAECgEJAgAAAA==.',
Cl='Clarence:BAAALgADCgIJAgABLgAFFAgJJQAXAAMaAA==.',
Co='Comitus:BAABLgAECn9HAAMfAAkJmw/XFgChAQAfAAkJmw/XFgChAQAgAAQJ+wNjgwCxAAAAAA==.Conjar:BAAALgAECgIJAgAAAA==.Conjarr:BAABLgAECn8pAAIMAAkJ/hpNHQDWAQAMAAkJ/hpNHQDWAQAAAA==.Cortisol:BAAALgADCgIJAgAAAA==.Corven:BAAALgAECgUJDAAAAA==.Cougardk:BAAALgAECgIJAgAAAA==.Cougarsixsix:BAABLgAECn8eAAIEAAcJzhR1GABWAQAEAAcJzhR1GABWAQAAAA==.',
Cr='Crashnburn:BAAALgADCgcJDQAAAA==.Crazyoldbear:BAABLgAECn8eAAIZAAkJmCPWAwDvAgAZAAkJmCPWAwDvAgAAAA==.Creideam:BAAALgADCgkJBwAAAA==.Crimos:BAABLgAECn8wAAIQAAkJzRbgPwABAgAQAAkJzRbgPwABAgAAAA==.Crystalliney:BAAALgADCgYJBgABLgAFFAUJFgAbAO4mAA==.',
Cy='Cynnai:BAAALgADCgYJBgAAAA==.Cyrena:BAAALgADCgEJAQAAAA==.',
Da='Daerthor:BAABLgAECn8gAAIEAAkJOBoPCgAnAgAEAAkJOBoPCgAnAgAAAA==.Dalind:BAABLgAECn8gAAITAAgJqgYeaAD5AAATAAgJqgYeaAD5AAAAAA==.Dalshiro:BAAALgAECgYJCQAAAA==.Damaclies:BAABLgAECn9IAAMXAAkJTBhePgDhAQAXAAgJQBZePgDhAQAHAAUJfBiHFwDiAAAAAA==.Damedolla:BAABLgAECn8fAAMIAAgJYQzmfQAgAQAIAAgJwwrmfQAgAQAhAAUJnw7EQAD3AAAAAA==.Dammerung:BAAALgAECgYJCAAAAA==.Darksyn:BAABLgAECn8aAAIHAAgJrAusEgAbAQAHAAgJrAusEgAbAQAAAA==.Darthbane:BAAALgAECggJEAAAAA==.Darthstroyer:BAABLgAFFH8FAAQiAAUJwgXaGAC5AAAiAAMJjgbaGAC5AAAQAAEJXQO/DwE9AAAjAAEJAABEYAAAAAAAAA==.Darude:BAAALgADCgcJEAAAAA==.Dashoka:BAAALgAECgEJAQAAAA==.Dattiffany:BAAALgAECgUJBQAAAA==.',
De='Deadstout:BAAALgAECgQJDgAAAA==.Deathevan:BAAALgAECggJDgABLgAECgkJLgAIADMiAA==.Deepspace:BAABLgAECn8uAAIhAAkJeSZ6AACNAwAhAAkJeSZ6AACNAwAAAA==.Deezknots:BAAALgAECggJCAAAAA==.Deezus:BAAALgADCgMJAwAAAA==.Dejagauth:BAAALgAECgYJCwABLgAECggJFQAkAKwhAA==.Dekkan:BAAALgAECgYJEAAAAA==.Demonedd:BAAALgADCgMJAgAAAA==.Demòn:BAAALgAECgEJAQAAAA==.Denounce:BAABLgAECn8YAAIlAAcJqBc8JACbAQAlAAcJqBc8JACbAQABLgAECgYJFQAYADQgAA==.Desdia:BAABLgAECn8ZAAIJAAcJERmWXQDDAQAJAAcJERmWXQDDAQAAAA==.',
Di='Dia:BAAALgAECgQJBwAAAA==.Diabetes:BAABLgAFFH8UAAIUAAYJ0BqCFQDGAQAUAAYJ0BqCFQDGAQAAAA==.Diastolic:BAAALgADCgUJBQAAAA==.Didyoudie:BAAALgAECggJDAAAAA==.Diend:BAABLgAECn9SAAIOAAkJgCSrAQCzAwAOAAkJgCSrAQCzAwAAAA==.Dill:BAAALgAECgEJAQABLgAECgkJOgABAPAlAA==.Dillathis:BAAALgADCgEJAQAAAA==.Discord:BAAALgAECgQJBQABLgAFFAMJAwAaAAAAAA==.Dissonanita:BAABLgAECn8WAAIGAAcJ0hC1ZwBvAQAGAAcJ0hC1ZwBvAQAAAA==.',
Dj='Djthelock:BAABLgAECn8rAAMXAAkJuRZrNQACAgAXAAgJxBNrNQACAgAHAAQJDhi5GwDFAAAAAA==.',
Do='Dormoon:BAABLgAECn8bAAMgAAgJnQ2rPwBFAQAgAAgJnQ2rPwBFAQAZAAEJIBGHUwAuAAAAAA==.',
Dr='Drac:BAAALgADCgYJCgAAAA==.Dragath:BAAALgAECgYJDgAAAA==.Drakur:BAAALgAECgYJCQAAAA==.Drbrad:BAABLgAECn8WAAMMAAYJRSMbFgAeAgAMAAYJRSMbFgAeAgARAAMJDhDKbgBhAAAAAA==.Dreadfangs:BAAALgADCgQJBQAAAA==.Druen:BAABLgAECn8xAAIYAAkJHB5iBAC4AgAYAAkJHB5iBAC4AgAAAA==.Drunkenpo:BAABLgAECn9OAAQbAAkJ5yHMBAD0AgAbAAkJtSHMBAD0AgAUAAUJ7hN/TwAoAQAcAAEJ4yOTcQBpAAAAAA==.Drykin:BAAALgAECgYJCwAAAA==.Drïzl:BAEALgAECgMJAwABLgAFFAUJFAAQAHYeAA==.',
Du='Duckchow:BAAALgADCgYJBgAAAA==.Dugga:BAAALgADCgQJBAAAAA==.Duskmyre:BAABLgAECn8jAAIIAAkJSwzcVwB8AQAIAAkJSwzcVwB8AQAAAA==.',
Dw='Dwarfoo:BAABLgAECn8ZAAMcAAgJrxedPgABAQAcAAYJWxOdPgABAQAUAAMJjwjAlABlAAAAAA==.Dweñde:BAABLgAECn8mAAIXAAkJigpBXwCBAQAXAAkJigpBXwCBAQAAAA==.',
['Dë']='Dëthmetal:BAABLgAECn8UAAIQAAUJnQxfwgD/AAAQAAUJnQxfwgD/AAAAAA==.',
Ed='Eddiemac:BAAALgAECgYJCgAAAA==.Eddrick:BAACLgAFFH8FAAIFAAIJTxQEiwCTAAAFAAIJTxQEiwCTAAAuAAQKfzIAAwUACQn2HYIZAKgCAAUACQmnHYIZAKgCAAQABQkvHUMZAEwBAAAA.Edoran:BAAALgADCggJCAAAAA==.Edrani:BAAALgAECgYJDgAAAA==.',
Ei='Eilethen:BAABLgAECn8lAAIWAAkJOxr0BQAgAgAWAAkJOxr0BQAgAgAAAA==.',
Ek='Ekassa:BAAALgADCgkJCQAAAA==.',
El='Elaína:BAAALgADCgMJAwABLgAFFAUJGAAWAMUSAA==.Elementoe:BAAALgADCgEJAQABLgADCgYJBgAaAAAAAA==.Elendil:BAAALgAECgMJAwAAAA==.Elissabethh:BAAALgAECgYJEAAAAA==.Elleryn:BAAALgADCgEJAQABLgAECgYJGQAOALwXAA==.Elminstar:BAAALgADCgIJAgAAAA==.Elêctra:BAAALgAECgEJAgABLgAECggJDAAaAAAAAA==.',
Em='Employee:BAABLgAECn8UAAIlAAcJmAumRwAIAQAlAAcJmAumRwAIAQAAAA==.',
En='Engo:BAABLgAECn9EAAMMAAkJdiRRAwBaAwAMAAkJdCNRAwBaAwASAAkJ9BviCADkAgAAAA==.',
Er='Eradrá:BAACLgAFFH8YAAMWAAUJxRK2EACFAAAXAAUJxRLwUgAcAQAWAAIJAQy2EACFAAAuAAQKf1AAAxYACQmzHugAAA4DABYACQmsG+gAAA4DABcACQm9GKAhAFoCAAAA.Eragon:BAAALgAECggJDgAAAA==.Erastrasza:BAAALgADCgYJCQAAAA==.Eroza:BAAALgAECgUJBgAAAA==.Ersey:BAAALgAECgQJBAABLgAFFAMJBwATAO8HAA==.Ersèlla:BAACLgAFFH8HAAITAAMJ7weESgCMAAATAAMJ7weESgCMAAAuAAQKfy4AAxMACQmMGPoaAGsCABMACQmMGPoaAGsCABUAAQnYBV+aACQAAAAA.Erysira:BAAALgADCgkJCQABLgAECgcJFQAJACEQAA==.',
Et='Ethan:BAAALgAECgEJAgAAAQ==.',
Eu='Eureka:BAABLgAECn8gAAMEAAkJTB05DgDcAQAEAAcJ1Rw5DgDcAQAFAAcJSRm4ZACkAQAAAA==.',
Ev='Evandra:BAABLgAECn8tAAIOAAkJGhtbFgCTAgAOAAkJGhtbFgCTAgAAAA==.Evanorah:BAABLgAECn8aAAMHAAcJAwncIQCcAAAXAAcJTQhFlgAQAQAHAAYJowXcIQCcAAAAAA==.',
Ex='Exïle:BAEALgAECgYJBgABLgAFFAUJFAAQAHYeAA==.',
Fa='Faelithia:BAABLgAECn8WAAIMAAYJKA4tPAD/AAAMAAYJKA4tPAD/AAAAAA==.Fatalbrew:BAAALgAECgYJCwAAAA==.Fauxyalee:BAAALgADCgkJCQAAAA==.',
Fe='Feldush:BAAALgADCgYJBgABLgAECggJJQAKAL8ZAA==.Felforit:BAAALgADCgQJBAAAAA==.Felis:BAAALgAECgYJCgAAAA==.Felkardio:BAAALgAECgIJAgAAAA==.Feloth:BAAALgADCgYJCQAAAA==.Ferheim:BAAALgAECgYJDwAAAA==.Ferhold:BAAALgADCgUJBQAAAA==.Ferrovax:BAAALgADCgYJBgABLgAECgkJLQAIACYZAA==.',
Fi='Fiddyone:BAABLgAECn8sAAMiAAkJySESAwDBAgAiAAkJtCESAwDBAgAQAAgJcR1IRADzAQAAAA==.Figment:BAAALgADCgYJBgAAAA==.Fireburt:BAAALgADCgUJBQAAAA==.Fireslay:BAABLgAECn8YAAIkAAcJpBwHHgAmAgAkAAcJpBwHHgAmAgAAAA==.Fizzlegrin:BAAALgAECgIJAgAAAA==.',
Fl='Flarefly:BAAALgAECgEJAQAAAA==.Flaya:BAAALgAECgcJCwAAAA==.',
Fo='Fodurzin:BAAALgAECgUJEwAAAA==.Fonta:BAAALgAECgMJAwAAAA==.Fortuna:BAAALgADCgYJBgABLgAECgMJAwAaAAAAAA==.Foxingtobi:BAAALgADCgIJAgAAAA==.',
Fr='Frojio:BAABLgAECn8xAAIiAAkJ1BtrBQBcAgAiAAkJ1BtrBQBcAgAAAA==.Frosten:BAAALgADCgkJPwAAAA==.',
Fu='Furenio:BAABLgAECn8yAAINAAkJ7xdUDgD6AQANAAkJ7xdUDgD6AQAAAA==.',
Fy='Fyyre:BAAALgAECgUJBwAAAA==.',
Ga='Gabaghoul:BAACLgAFFH8XAAIFAAUJFh1HKABjAQAFAAUJFh1HKABjAQAuAAQKfzEAAgUACQl3IMoYAKwCAAUACQl3IMoYAKwCAAAA.Gaff:BAAALgAECggJEQAAAA==.Galeana:BAAALgAECgMJAwABLgAECgkJXAAJAPAeAA==.Galvan:BAAALgAECgEJBAAAAA==.Gasheth:BAAALgAECgYJDQAAAA==.',
Ge='Gentyl:BAAALgAECgMJAwAAAA==.',
Gi='Giggleblast:BAAALgAECgIJAgAAAA==.',
Gl='Glizzydealer:BAAALgAECgEJAQAAAA==.',
Gr='Grauth:BAAALgADCgEJAQAAAA==.Graycen:BAAALgAECgUJCQAAAA==.Grido:BAAALgADCgkJEQAAAA==.Grimbrindral:BAABLgAECn8hAAMFAAcJ5hZDZAC5AQAFAAcJdBVDZAC5AQAEAAUJghrKFwBZAQAAAA==.Grimston:BAAALgADCgMJAwABLgAECgcJIQAFAOYWAA==.Gruzaxx:BAAALgADCgUJBQAAAA==.',
Gu='Gulishdaniel:BAABLgAFFH8GAAIWAAQJJQT1CADmAAAWAAQJJQT1CADmAAABLgAFFAYJEAARAKoZAA==.',
Ha='Hadin:BAABLgAECn9MAAMJAAkJMCRxBgBMAwAJAAkJMCRxBgBMAwAeAAMJqhysDwDHAAAAAA==.Hakeko:BAAALgAECgYJDgABLgAECggJEgAaAAAAAA==.Halalnt:BAAALgAFFAEJAQABLgAFFAIJBQAlAOkaAA==.Hanua:BAAALgADCgcJBwAAAA==.Haozhao:BAABLgAECn9LAAMNAAkJxhoDCQBYAgANAAkJxhoDCQBYAgAYAAEJDhTbTAA6AAAAAA==.Hawktuahz:BAAALgAECgMJAwAAAA==.Hazenpryde:BAABLgAECn8eAAINAAgJLRq2DwDmAQANAAgJLRq2DwDmAQAAAA==.',
He='Hearsay:BAABLgAECn8wAAMFAAgJHhC3dQCAAQAFAAgJHhC3dQCAAQAkAAIJ6wOYgABHAAAAAA==.Hephaistian:BAAALgAECgUJBQAAAA==.Hespera:BAACLgAFFH8RAAMTAAUJFQ9AJQApAQATAAUJFQ9AJQApAQAVAAMJEgWUOACQAAAuAAQKfyMAAxMACQnJIOkYAHACABMACAmiIekYAHACABUAAwmnFJdQAMYAAAAA.',
Hi='Hirari:BAABLgAECn8dAAMkAAYJBCVCFwBNAgAkAAYJBCVCFwBNAgAFAAEJFBrccgFCAAAAAA==.',
Ho='Hodoor:BAAALgADCgUJBQAAAA==.Howlears:BAABLgAECn8pAAIRAAgJoQfiOQApAQARAAgJoQfiOQApAQAAAA==.',
Hu='Hulud:BAABLgAECn8YAAMXAAkJfRZLSgC7AQAXAAkJfRZLSgC7AQAHAAEJAABpUwAAAAAAAA==.Husbando:BAAALgAECgMJAwAAAA==.Husey:BAAALgAECgMJBgAAAA==.',
Hy='Hydrangea:BAABLgAECn8dAAIFAAcJ4Q9/jgBSAQAFAAcJ4Q9/jgBSAQAAAA==.Hydrá:BAABLgAECn8aAAIXAAkJvRbTLwAXAgAXAAkJvRbTLwAXAgAAAA==.Hylan:BAAALgADCgUJBQAAAA==.Hysgar:BAAALgADCgkJDwABLgAECggJFQAkAKwhAA==.',
Ic='Iceamaris:BAABLgAECn8gAAIPAAkJYQsHOABTAQAPAAkJYQsHOABTAQAAAA==.Icetiger:BAAALgAECgEJAQAAAA==.Icetigress:BAAALgAECgEJAQAAAA==.',
Ie='Iechu:BAABLgAECn8gAAMbAAgJbBHjIgCQAQAbAAgJbBHjIgCQAQAcAAIJ9QbpiQBFAAAAAA==.',
In='Innanna:BAAALgADCggJCgABLgAECgcJFgAIAC4SAA==.',
Is='Isoth:BAAALgAECgEJAQAAAA==.',
Iv='Ivern:BAACLgAFFH8VAAITAAgJ+hHYBwB0AgATAAgJ+hHYBwB0AgAuAAQKfx0AAxMABgkHHYcyANIBABMABgkHHYcyANIBABUAAgnRB4CUACkAAAAA.Ivysnow:BAAALgAECgEJAQAAAA==.',
Ja='Jac:BAAALgAECgMJAwABLgAFFAMJAwAaAAAAAA==.Jadenpryde:BAAALgAECgYJBgABLgAECggJHgANAC0aAA==.Jarndal:BAAALgAECgEJAQAAAA==.Jasmirrae:BAAALgAECgEJAQAAAA==.',
Jd='Jdghoul:BAAALgAECggJDwAAAA==.',
Ji='Jian:BAAALgADCgIJAgAAAA==.Jindrac:BAAALgAECggJCwAAAA==.',
Jo='Jolton:BAAALgADCgYJBwABLgAECgkJLgAIADMiAA==.',
['Jà']='Jàcaranda:BAAALgAECgYJBwAAAA==.',
Ka='Kahnrah:BAAALgADCgkJDAAAAA==.Kalarae:BAAALgAECggJCQAAAA==.Kalarill:BAABLgAECn8eAAIFAAcJZR13LwBAAgAFAAcJZR13LwBAAgAAAA==.Kaltharion:BAAALgAFFAIJBAAAAA==.Kaluren:BAAALgAECgcJDwAAAA==.Kalurok:BAAALgAECgUJBQABLgAECgcJDwAaAAAAAA==.Kana:BAAALgAECgIJAgAAAA==.Kanade:BAABLgAECn9HAAQXAAkJBh40FwCXAgAXAAgJ1R00FwCXAgAWAAcJsRW6CADXAQAHAAQJWAsKTACJAAAAAA==.Kantong:BAABLgAECn8gAAIcAAgJdRkCGwDUAQAcAAgJdRkCGwDUAQAAAA==.Kapp:BAAALgAECgcJEwAAAA==.Karabar:BAABLgAECn87AAMEAAkJ2yD0BACjAgAEAAkJyh70BACjAgAFAAgJoyAcKABgAgAAAA==.Karnnaged:BAAALgADCgYJBwAAAA==.Kasarra:BAABLgAECn8wAAIhAAkJsxSNEwD1AQAhAAkJsxSNEwD1AQAAAA==.Kayiku:BAAALgADCgkJFwAAAA==.Kazagol:BAABLgAECn87AAIIAAkJ+x1GGgB0AgAIAAkJ+x1GGgB0AgAAAA==.',
Ke='Kelintos:BAAALgAECgEJAQAAAA==.Keone:BAAALgADCgEJAQAAAA==.',
Kh='Khalla:BAAALgAFFAEJAQAAAA==.Khamaracy:BAABLgAECn8fAAMHAAgJWwjEFQD2AAAHAAgJWwjEFQD2AAAXAAEJsQGLYAEbAAAAAA==.Khronni:BAAALgAECgYJCQAAAA==.Khrooze:BAAALgAECgYJEQAAAA==.',
Ki='Kidos:BAAALgAECgQJBgAAAA==.Kiljana:BAAALgAECgEJAQAAAA==.Kimahrí:BAABLgAECn8cAAIjAAgJGwiULgDnAAAjAAgJGwiULgDnAAAAAA==.Kittei:BAABLgAECn87AAINAAkJ1w8FGwBwAQANAAkJ1w8FGwBwAQAAAA==.',
Ko='Kojote:BAAALgADCgMJAQAAAA==.Kovalenko:BAAALgAECggJDQAAAA==.',
Ku='Kurick:BAABLgAECn8VAAMkAAgJrCEBCAAKAwAkAAgJrCEBCAAKAwAFAAEJmxWpdwE+AAAAAA==.Kurzul:BAAALgADCgEJAgAAAA==.Kusinluvin:BAAALgADCgEJAQAAAA==.',
Ky='Kyngizzard:BAABLgAECn8fAAIJAAkJSRoRNwA6AgAJAAkJSRoRNwA6AgABLgAFFAIJBQAlAOkaAA==.Kytherin:BAAALgAECgYJDAAAAA==.',
La='Lactase:BAAALgADCgMJAwAAAA==.Lainea:BAAALgAECgMJAQAAAA==.Langtry:BAAALgADCgcJBgAAAA==.Latte:BAAALgAECgcJBwAAAA==.',
Le='Leblanc:BAAALgAECgEJAQABLgAECgkJFwAFACoeAA==.Leeli:BAAALgADCgcJBwAAAA==.Lenity:BAABLgAECn8+AAIDAAgJTBbwEwAAAgADAAgJTBbwEwAAAgAAAA==.Letty:BAAALgAECgQJBQAAAA==.',
Li='Liabelle:BAAALgADCgIJAgAAAA==.Lightsmite:BAAALgAECgIJAgAAAA==.Lilithene:BAAALgAECgUJBgABLgAECgkJLAAPAMoWAA==.Lionbark:BAAALgADCgEJAQAAAA==.Lithpally:BAAALgADCgEJAQAAAA==.Liubeijian:BAAALgADCgYJBgABLgAECgcJFgAIAC4SAA==.',
Lo='Loan:BAAALgADCgQJAwABLgADCgkJEAAaAAAAAA==.Lokinah:BAABLgAECn8bAAIGAAgJgAbwiwAiAQAGAAgJgAbwiwAiAQAAAA==.Loonytusk:BAAALgADCgQJBAAAAA==.',
Lu='Lucifermadis:BAAALgAECgQJBgAAAA==.Lucoryphus:BAABLgAECn8fAAIjAAcJ1RdyGQCRAQAjAAcJ1RdyGQCRAQAAAA==.Lukeduke:BAABLgAFFH8TAAIZAAgJFx6jAwA0AgAZAAgJFx6jAwA0AgAAAA==.Luketheduke:BAACLgAFFH8ZAAMNAAYJgR4FBADJAQANAAUJgR4FBADJAQAYAAEJAAAIBwA3AAAuAAQKfyoAAw0ACQkvJR8BAFcDAA0ACQkvJR8BAFcDABgABAmxFXscAAkBAAEuAAUUCAkTABkAFx4A.Lumilia:BAAALgADCgUJBQAAAA==.Lunaries:BAAALgAECgYJBgAAAA==.Lunä:BAABLgAECn8mAAIOAAkJVBZqIgAQAgAOAAkJVBZqIgAQAgAAAA==.',
Ly='Lydia:BAABLgAECn8pAAIJAAkJphmAMwBIAgAJAAkJphmAMwBIAgAAAA==.Lynnee:BAAALgADCgEJAQAAAA==.',
['Lô']='Lôckrocks:BAABLgAECn8ZAAIHAAcJxhE6DwBHAQAHAAcJxhE6DwBHAQAAAA==.',
['Lý']='Lýsendra:BAAALgADCggJCQAAAA==.',
Ma='Magickeys:BAAALgAFFAIJAgAAAA==.Magictomb:BAACLgAFFH8GAAMdAAMJ0AgnEAC9AAAdAAMJ0AgnEAC9AAAPAAEJrgE5IQA7AAAuAAQKfy8ABA8ACAmXFdY3AFQBAA8ACAmXFdY3AFQBAA4ABgnpDTF6AOsAAB0ABQkzCmAhAOYAAAAA.Mahdude:BAAALgAECgEJAQAAAA==.Malastor:BAAALgAECgEJAQABLgAFFAMJAwAaAAAAAA==.Malcontent:BAAALgAECgQJBQABLgAFFAMJAwAaAAAAAA==.Maldazane:BAAALgADCgYJCwAAAA==.Malfeasance:BAAALgADCgkJDQABLgAFFAMJAwAaAAAAAA==.Malidan:BAAALgADCgMJAwAAAA==.Malifel:BAABLgAECn8cAAMmAAgJEiCuBABrAgAmAAgJEiCuBABrAgAIAAEJUAcyKwEhAAABLgAFFAMJAwAaAAAAAA==.Maliss:BAABLgAECn8+AAQBAAkJRRiMEwAKAgABAAkJaheMEwAKAgACAAQJ8RE4IQCjAAAGAAEJoxFuKAE3AAAAAA==.Mallord:BAAALgAFFAMJAwAAAA==.Mandarin:BAABLgAECn83AAITAAkJ8hrLEgCzAgATAAkJ8hrLEgCzAgAAAA==.Manmythlegnd:BAAALgADCgYJBgAAAA==.Mannik:BAABLgAECn8aAAIXAAgJrRnRMQAPAgAXAAgJrRnRMQAPAgAAAA==.Marashade:BAAALgAECgUJBQAAAA==.Marashades:BAAALgAECgQJBAABLgAECgkJHgAZAJgjAA==.',
Mc='Mcbadden:BAAALgAECgYJCAAAAA==.',
Me='Meditatetoe:BAAALgADCgIJAgABLgADCgYJBgAaAAAAAA==.Melissà:BAAALgADCgMJAwAAAA==.Menesta:BAAALgADCgcJBwABLgAECgUJEwAaAAAAAA==.Mercia:BAABLgAECn8vAAIEAAkJExtSCQA4AgAEAAkJExtSCQA4AgAAAA==.Merekoma:BAABLgAECn8tAAMIAAkJJhloLAATAgAIAAkJ5RRoLAATAgAmAAQJFha6HACxAAAAAA==.',
Mi='Milarra:BAABLgAECn8VAAInAAcJMAmXCAD9AAAnAAcJMAmXCAD9AAAAAA==.Milhouse:BAABLgAECn8UAAIJAAcJswmlpgAtAQAJAAcJswmlpgAtAQAAAA==.Minalan:BAAALgADCgYJCgABLgAECgYJEQAaAAAAAA==.Mingonashoba:BAABLgAECn8fAAIGAAkJwg1MRQDNAQAGAAkJwg1MRQDNAQAAAA==.Miragosa:BAABLgAECn8yAAMKAAkJUA9lDwDSAQAKAAkJUA9lDwDSAQALAAcJ3gj0DwAHAQAAAA==.Misschris:BAABLgAECn8rAAIUAAkJZwzhPgBrAQAUAAkJZwzhPgBrAQAAAA==.Mizu:BAAALgAECgUJBQAAAA==.',
Mo='Moadeed:BAABLgAECn8YAAINAAkJNRPuEQDLAQANAAkJNRPuEQDLAQAAAA==.Mooluv:BAAALgADCgcJCgAAAA==.Moonstrike:BAAALgAECgIJAgAAAA==.Mordrius:BAAALgADCgYJBgAAAA==.Morphmious:BAAALgAECgcJBwAAAA==.Mortesque:BAAALgAECgcJEgAAAA==.',
Mu='Muttblitzed:BAABLgAECn8XAAIGAAgJVxKdSgC9AQAGAAgJVxKdSgC9AQAAAA==.Muttskî:BAAALgAECgMJAwAAAA==.',
My='Mybutt:BAAALgAECgMJBgAAAA==.Myroku:BAAALgADCgcJBwABLgAFFAMJAwAaAAAAAA==.Myrothos:BAAALgADCgEJAQAAAA==.Myrrh:BAABLgAECn8YAAMlAAYJdAcKYAC1AAAlAAYJggYKYAC1AAALAAQJ9wYzLQCxAAAAAA==.Mythris:BAAALgAECgkJBQAAAA==.',
['Mí']='Místermage:BAAALgAECgQJCAAAAA==.',
Na='Nadrael:BAAALgAECgEJAgAAAA==.Nasturtium:BAAALgADCgYJDgAAAA==.Nausican:BAABLgAECn9IAAIiAAkJvxogBACOAgAiAAkJvxogBACOAgAAAA==.Nazuhda:BAAALgADCgEJAQAAAA==.',
Ne='Necrosector:BAACLgAFFH8JAAIFAAQJAgoyUwAEAQAFAAQJAgoyUwAEAQAuAAQKfyYAAgUACAm5GatNANwBAAUACAm5GatNANwBAAAA.Necrotherys:BAABLgAECn84AAIIAAkJPhyjFwCFAgAIAAkJPhyjFwCFAgAAAA==.Nelandra:BAABLgAECn8gAAIRAAgJKxkxFgAYAgARAAgJKxkxFgAYAgAAAA==.',
Ni='Nicklaus:BAABLgAECn8nAAIDAAcJlgmzLgAkAQADAAcJlgmzLgAkAQAAAA==.Nilrem:BAAALgADCgIJAgAAAA==.Ninelives:BAAALgAECgYJDgAAAA==.Ninjadk:BAECLgAFFH8UAAMQAAUJdh4rTQBTAQAQAAQJdh4rTQBTAQAjAAEJAAALYgAAAAAuAAQKfzEAAxAACQmyIaIOAPUCABAACQmyIaIOAPUCACIAAQm4G8I1AEAAAAAA.',
No='Nocapongfrfr:BAAALgAECgMJAwABLgAFFAUJBQAiAMIFAA==.Nomahuata:BAABLgAECn9IAAIPAAkJyhgaFQA9AgAPAAkJyhgaFQA9AgAAAA==.Nordre:BAAALgAECgMJAwAAAA==.',
Nu='Nufrus:BAAALgAECgEJAQAAAA==.',
Ny='Nyeli:BAAALgAECgQJBgABLgAECgYJGQAOALwXAA==.Nyxi:BAABLgAECn8dAAIOAAgJABksIABLAgAOAAgJABksIABLAgAAAA==.Nyxlee:BAAALgAECgcJBwAAAA==.',
['Né']='Néo:BAAALgAECgUJCAAAAA==.',
['Nó']='Nóóôööôòòpe:BAABLgAFFH8FAAIGAAQJggUsVwDvAAAGAAQJggUsVwDvAAABLgAFFAUJBQAiAMIFAA==.',
Og='Ogdruid:BAAALgADCgcJDgAAAA==.',
Ok='Okume:BAAALgAECgIJAgAAAA==.',
Ol='Olympian:BAAALgADCgcJBwAAAA==.',
Om='Omanyte:BAAALgADCgcJBwAAAA==.',
On='Onefiftyone:BAABLgAECn8bAAMdAAYJHCUGCgAWAgAdAAYJHCUGCgAWAgAOAAIJnSTJhwDHAAABLgAECgkJLAAiAMkhAA==.',
Or='Orruk:BAAALgADCgMJAwAAAA==.Orwyn:BAAALgADCgkJEwAAAA==.',
Ov='Overdose:BAAALgADCgMJAwAAAA==.',
Pa='Padmé:BAAALgAECgQJBgAAAA==.Pain:BAAALgAECgUJCwAAAA==.Palanas:BAAALgAFFAEJAQAAAA==.Pallamoo:BAAALgAECgYJBwAAAA==.Palochka:BAAALgAECgcJBwAAAA==.Paradots:BAABLgAECn8WAAIKAAYJwBo1EgCiAQAKAAYJwBo1EgCiAQABLgAECgkJIgATAOIdAA==.Paranitis:BAAALgAECggJDAAAAA==.Paranorm:BAAALgADCgEJAQAAAA==.Paraparaboom:BAAALgAECgUJBQABLgAFFAQJDQAJAN8XAA==.',
Pe='Pezdormu:BAAALgADCgEJAQAAAA==.Pezmage:BAAALgAECgIJBAAAAA==.',
Ph='Phatboi:BAAALgAECgEJAgAAAA==.Pheroth:BAAALgAECgUJCgABLgAECggJGgAHAKwLAA==.',
Pi='Pixystix:BAABLgAECn8jAAIIAAgJmxj0MwDzAQAIAAgJmxj0MwDzAQAAAA==.',
Po='Poisonspain:BAAALgAECgMJAwAAAA==.Popsdh:BAAALgAECggJEwABLgAECgkJIAAEAEwdAA==.Portlukk:BAAALgADCgEJAQABLgAFFAQJEwAGAKEZAA==.Potscold:BAACLgAFFH8QAAIJAAgJARaGDAC5AQAJAAgJARaGDAC5AQAuAAQKf0EAAgkACAnbJbsRAD0DAAkACAnbJbsRAD0DAAAA.Poxi:BAAALgAECgIJAgABLgAECggJGAAJADwdAA==.',
Pr='Prion:BAABLgAECn8eAAIgAAgJ7xRcKQCyAQAgAAgJ7xRcKQCyAQAAAA==.',
Pu='Pull:BAABLgAECn8jAAINAAkJnxv2CQBEAgANAAkJnxv2CQBEAgAAAA==.',
Ra='Radioshack:BAAALgADCggJCAAAAA==.Radkemonko:BAAALgAECgcJDwAAAA==.Raega:BAAALgADCgYJBgAAAA==.Ragerlock:BAAALgADCgEJAQAAAA==.Raivel:BAABLgAECn8ZAAIOAAYJvBfSRQCSAQAOAAYJvBfSRQCSAQAAAA==.Raldaron:BAAALgADCgEJAQAAAA==.Rambogg:BAAALgAECgEJAQABLgAFFAYJGgAJAIMTAA==.Raneyth:BAAALgAECgcJBwAAAA==.Ranith:BAAALgADCgMJAwAAAA==.Ravagèr:BAAALgAECgEJAgAAAA==.',
Rd='Rdbwarrior:BAAALgADCgUJBQAAAA==.',
Re='Redemus:BAAALgADCgEJAQAAAA==.Redwinetoast:BAABLgAECn8iAAIXAAkJwgTnjwAbAQAXAAkJwgTnjwAbAQAAAA==.Rekllaw:BAAALgAECgEJAQAAAA==.Reliala:BAAALgADCgkJEQAAAA==.Reno:BAAALgADCgkJEAAAAA==.Reshyk:BAAALgAECggJEgAAAA==.Resles:BAAALgAECgEJAQAAAA==.Respectwomen:BAAALgADCgEJAQABLgAECgQJBAAaAAAAAA==.',
Rh='Rhobes:BAABLgAECn8VAAIgAAgJlQ4bMgCDAQAgAAgJlQ4bMgCDAQAAAA==.Rhondta:BAABLgAECn8lAAIXAAkJIxGxRADLAQAXAAkJIxGxRADLAQAAAA==.',
Ri='Rickormortis:BAABLgAECn8UAAIQAAkJGB2qHQCTAgAQAAkJGB2qHQCTAgABLgAECgkJKwAUAGcMAA==.Rictus:BAABLgAECn8wAAIJAAkJjSQsCAA5AwAJAAkJjSQsCAA5AwAAAA==.Ringmasterr:BAAALgADCgUJBQAAAA==.Riordaa:BAAALgADCgYJDAAAAA==.Risingdragon:BAABLgAECn8qAAIcAAcJMhPQLQBQAQAcAAcJMhPQLQBQAQAAAA==.',
Ro='Roades:BAAALgADCgcJDAAAAA==.Roboskritch:BAAALgADCgUJBQAAAA==.Ronaj:BAAALgADCgMJBAAAAA==.Royveer:BAAALgADCgYJCQAAAA==.',
Ru='Rumor:BAABLgAECn8iAAUYAAgJcRVcEwCCAQAYAAcJvxRcEwCCAQATAAYJyQuZagDyAAANAAMJlwxIWgBVAAAVAAIJdAnsgABDAAABLgAECggJMAAFAB4QAA==.Rurry:BAACLgAFFH8YAAIKAAYJpRe+BACuAQAKAAYJpRe+BACuAQAuAAQKfy4ABAoACQnIIrECAEADAAoACQnIIrECAEADAAsABQm6GR4WAI8BACUAAwlVF/RGAL8AAAEuAAUUCAkVABMA+hEA.',
Ry='Ryumi:BAABLgAECn8uAAIIAAkJMyL+FgCKAgAIAAkJMyL+FgCKAgAAAA==.Ryur:BAAALgAECgQJDgAAAA==.',
Sa='Sabastion:BAAALgAECgYJBgABLgAFFAMJAwAaAAAAAA==.Sacrickficed:BAAALgAECgQJBAABLgAECgkJKwAUAGcMAA==.Sahwe:BAABLgAECn8UAAMTAAYJnwxCaQD2AAATAAYJnwxCaQD2AAAVAAEJ0wdqlQAoAAAAAA==.Salocar:BAAALgAECgcJEwAAAA==.Sanafela:BAAALgADCgkJTAAAAA==.Saphisha:BAABLgAECn8UAAIcAAgJVxd2HwCuAQAcAAgJVxd2HwCuAQAAAA==.Sasora:BAAALgAECgUJCwAAAA==.Saucemagic:BAAALgAECgcJDQAAAA==.Savonah:BAAALgAECgUJBgAAAA==.',
Sc='Scaledaddy:BAABLgAECn8jAAIlAAkJug0MKQCbAQAlAAkJug0MKQCbAQAAAA==.Scalespawn:BAAALgADCgYJBgABLgAFFAgJHgAQAEwZAA==.Scaryl:BAAALgAECgYJCgAAAA==.Scourgespawn:BAACLgAFFH8eAAQQAAgJTBmYIQDdAQAQAAYJJhuYIQDdAQAiAAQJgxKvCwA3AQAjAAIJpwjHQQAoAAAuAAQKfyoAAxAACQmyIDMkAK0CABAACQmyIDMkAK0CACMABAnhFZ44AK4AAAAA.',
Se='Searthenio:BAAALgAECggJCAAAAA==.Selenë:BAABLgAECn8eAAMMAAcJyhZPHQDWAQAMAAcJyhZPHQDWAQARAAEJxwFhmQAWAAAAAA==.Sengoku:BAAALgAECgEJAQAAAA==.Serbiscuit:BAAALgAECgUJCgAAAA==.Sereneya:BAAALgAECgYJBgAAAA==.Serenio:BAAALgAECgcJEQAAAA==.Serenval:BAAALgAECgEJAQAAAA==.',
Sh='Shadowshart:BAAALgAECgEJAQAAAA==.Shailora:BAAALgAECgMJAwAAAA==.Shait:BAAALgADCgYJBgAAAA==.Shalis:BAABLgAECn8qAAIGAAkJWxx2GwB8AgAGAAkJWxx2GwB8AgAAAA==.Sharivee:BAABLgAECn8aAAMJAAkJ6SBUEgDqAgAJAAkJuh9UEgDqAgAeAAUJWB0pCAB3AQAAAA==.Sharko:BAABLgAECn8cAAQEAAgJExeSDwDMAQAEAAcJzhWSDwDMAQAFAAUJhBnZpgAqAQAkAAIJwgOQiwBPAAAAAA==.Sharvalee:BAAALgAECgUJBQAAAA==.Shibui:BAABLgAECn9RAAQhAAkJ6RqsCgB6AgAhAAkJ6RqsCgB6AgAIAAcJvAYvowDNAAAmAAQJQQ4WHQCvAAAAAA==.Shiggles:BAABLgAECn8iAAIQAAkJEBq5JwBhAgAQAAkJEBq5JwBhAgABLgAFFAIJBQAFAHUVAA==.Shinhaein:BAABLgAECn8cAAIJAAgJJBOpcgCRAQAJAAgJJBOpcgCRAQABLgAFFAUJFwAQAAMaAA==.Shinxu:BAAALgADCgQJBAAAAA==.Shizmael:BAAALgAECgUJBwAAAA==.Shockazilla:BAABLgAECn83AAMkAAkJbR6tCAD+AgAkAAkJbR6tCAD+AgAFAAMJVw+z/wCWAAAAAA==.Shreddarfort:BAAALgADCgkJFQAAAA==.Shönuff:BAAALgAECgEJAQAAAA==.',
Si='Sigh:BAAALgAFFAEJAQAAAA==.Silverhorn:BAABLgAECn8kAAIFAAcJNxyKTADfAQAFAAcJNxyKTADfAQAAAA==.',
Sk='Skoduh:BAABLgAECn8hAAIGAAcJQhwIUgCoAQAGAAcJQhwIUgCoAQAAAA==.Skyelene:BAABLgAECn8sAAMPAAkJyhbyFgArAgAPAAkJyhbyFgArAgAOAAcJvwa/eADvAAAAAA==.',
Sl='Slaanesh:BAABLgAECn8cAAQHAAkJWBUWDAB6AQAHAAcJOBYWDAB6AQAXAAQJyQ0usgDhAAAWAAMJlhsqFwDFAAAAAA==.Sluggo:BAABLgAFFH8HAAIFAAUJzxEJKgBdAQAFAAUJzxEJKgBdAQAAAA==.Sluggoboyce:BAACLgAFFH8GAAICAAQJhgR9EwAHAQACAAQJhgR9EwAHAQAuAAQKfyIAAwIACAkLGSEcAEcCAAIACAnYGCEcAEcCAAYABAmEDS6aAJ8AAAAA.',
Sm='Smeagosses:BAAALgAECgEJAQAAAA==.Smokeü:BAAALgAECgcJBwAAAA==.',
So='Solace:BAABLgAECn8aAAIIAAgJwB/xFgCKAgAIAAgJwB/xFgCKAgAAAA==.Solinaara:BAAALgAECgQJBAAAAA==.Soraka:BAABLgAFFH8KAAISAAQJnQrqKQD4AAASAAQJnQrqKQD4AAAAAA==.Soulstoner:BAAALgADCgYJBgAAAA==.',
Sp='Spiralist:BAABLgAECn8dAAQTAAkJ4xbrTQBUAQATAAgJfBXrTQBUAQAVAAYJARnyNgA1AQAYAAIJkAw3QQBVAAAAAA==.Spiralmist:BAAALgADCgUJBQAAAA==.',
St='Starge:BAAALgAECgUJBQAAAA==.Steelforged:BAAALgADCgkJEAABLgAECgYJFAAcALQMAA==.Stonedalways:BAABLgAECn8hAAMOAAgJphA2PgCxAQAOAAgJphA2PgCxAQAPAAMJvQQJiQBZAAAAAA==.',
Su='Sunfuri:BAABLgAECn85AAIgAAkJDQqsNAB2AQAgAAkJDQqsNAB2AQAAAA==.Sunjan:BAAALgAECgQJBwAAAA==.Sus:BAACLgAFFH8hAAIhAAcJ7Rv4AgAJAgAhAAcJ7Rv4AgAJAgAuAAQKfyUAAiEACQmXI5cDAEcDACEACQmXI5cDAEcDAAAA.Susanoo:BAABLgAECn8ZAAIgAAkJcRTDIwDUAQAgAAkJcRTDIwDUAQAAAA==.',
Sy='Sylvíadne:BAAALgAECgYJBgAAAA==.',
Sz='Szul:BAAALgADCgcJDAAAAA==.',
Ta='Tachima:BAAALgAECgcJEAABLgAECgkJLgAIADMiAA==.Tactics:BAAALgADCgcJDAAAAA==.Tahitimango:BAABLgAECn8mAAIIAAYJmgMDzwCPAAAIAAYJmgMDzwCPAAAAAA==.Takeko:BAAALgADCgcJDgABLgAECggJEgAaAAAAAA==.Talanas:BAAALgADCgcJBwAAAA==.Taleria:BAAALgADCgYJGgAAAA==.Taranad:BAAALgAECgcJDAAAAA==.Tarathor:BAABLgAECn8gAAIVAAgJuBnYFwALAgAVAAgJuBnYFwALAgAAAA==.Tasha:BAAALgAECgEJAwABLgAECggJHgAgAO8UAA==.Tauroctony:BAABLgAECn8eAAINAAgJKiGhBACiAgANAAgJKiGhBACiAgAAAA==.',
Te='Tea:BAABLgAECn8WAAMZAAgJHQw6IQAiAQAZAAgJHQw6IQAiAQAgAAUJFAQrfAB+AAABLgAECgkJRAAMAPYfAA==.Teknofarious:BAAALgAECgEJBAAAAA==.Tenom:BAAALgAECgUJCgAAAA==.',
Th='Thalar:BAAALgAECgIJAgAAAA==.Thaumas:BAAALgADCgEJAQAAAA==.Thelsyn:BAAALgAECgIJAgABLgAECgkJPgABAEUYAA==.Thermite:BAAALgAECgYJBgAAAA==.Thesafe:BAAALgAECgMJAwAAAA==.Thialaa:BAAALgAECgEJAwABLgAECgkJRwAGAJUkAA==.Thialia:BAAALgAECgkJEwABLgAECgkJRwAGAJUkAA==.Thialiaa:BAAALgAECgYJBwABLgAECgkJRwAGAJUkAA==.Thorey:BAAALgAECgEJAQAAAA==.Thornbreaker:BAAALgADCgEJAQAAAA==.Thorthunda:BAAALgAECgQJBgAAAA==.',
Ti='Tinkabella:BAABLgAECn87AAISAAkJLiNSAgCVAwASAAkJLiNSAgCVAwAAAA==.Tizl:BAEALgAECgUJBQABLgAFFAUJFAAQAHYeAA==.',
To='Tobi:BAAALgADCgQJBAAAAA==.Tobiblindpaw:BAAALgAECgYJDwAAAA==.Toenailjuice:BAAALgADCgUJBQABLgAECgkJOwAUAKkjAA==.Togo:BAAALgAECgYJBgAAAA==.Torrey:BAABLgAECn8YAAIkAAgJHyVuAwA8AwAkAAgJHyVuAwA8AwAAAA==.',
Tr='Trema:BAAALgAECgEJAgAAAA==.Trix:BAABLgAECn8vAAIOAAgJHw0EVwBVAQAOAAgJHw0EVwBVAQAAAA==.',
Tu='Tulsami:BAAALgAECgIJAwAAAA==.Tulsi:BAABLgAECn88AAIoAAkJYySzAAA+AwAoAAkJYySzAAA+AwAAAA==.Tuskoo:BAAALgAECgcJEQAAAA==.',
Ty='Tyrathion:BAAALgAECgMJAwAAAA==.Tyronos:BAABLgAECn8hAAIFAAkJQxnGKwBQAgAFAAkJQxnGKwBQAgAAAA==.',
Uk='Uknôwnforce:BAAALgAECgMJBAAAAA==.',
Un='Unbeetable:BAAALgADCgUJBQAAAA==.',
Va='Vaeltharion:BAAALgADCgEJAQAAAA==.Valanoth:BAABLgAECn8jAAIIAAgJ1SDiHABkAgAIAAgJ1SDiHABkAgAAAA==.Valdr:BAABLgAECn8fAAMlAAkJbhFzIgDFAQAlAAkJbhFzIgDFAQALAAQJowzXKQDQAAAAAA==.Valoryck:BAAALgAECgQJDQABLgAECggJIwAIANUgAA==.Vas:BAAALgAECgMJAwAAAA==.',
Ve='Velielina:BAAALgAECgEJAQAAAA==.Velistos:BAAALgADCgEJAQAAAA==.Vellandrias:BAAALgADCgYJBgAAAA==.Verinda:BAAALgADCgcJDwAAAA==.Vessara:BAAALgAECgEJAQABLgAFFAUJDwANAPYTAA==.Vevicenth:BAAALgAECgkJEgAAAA==.',
Vo='Voodoolily:BAAALgADCgkJCQAAAA==.Voranth:BAAALgADCgMJAwAAAA==.',
Wa='Warpsbulge:BAACLgAFFH8gAAIJAAcJ2x1lCgDMAQAJAAcJ2x1lCgDMAQAuAAQKfxsAAwkACQlNIb4hAOwCAAkACQlNIb4hAOwCAB4AAgl2FLQTAIoAAAAA.',
Wh='Whakan:BAAALgAECgEJAgABLgAECgcJHwAjANUXAA==.',
Wo='Wolfos:BAABLgAECn8fAAINAAkJEiaKAABxAwANAAkJEiaKAABxAwAAAA==.',
Wt='Wtfox:BAEBLgAECn8ZAAMRAAgJTg+3LgBkAQARAAgJTg+3LgBkAQASAAQJZQJ0cQBAAAAAAA==.',
Wu='Wulfgange:BAAALgADCgEJAQAAAA==.',
Wy='Wysteri:BAABLgAECn8WAAIIAAcJLhKUZQBYAQAIAAcJLhKUZQBYAQAAAA==.',
Xa='Xadrai:BAAALgADCgIJAgAAAA==.Xakeko:BAAALgAECggJEgAAAA==.Xalatos:BAAALgAECgEJAgAAAA==.Xalfein:BAAALgAECgQJBAAAAA==.',
Xi='Xinu:BAAALgAECgcJBwABLgAECgkJRAAGANogAA==.',
Ya='Yanakana:BAAALgAECgcJBwAAAA==.',
Yd='Ydalise:BAAALgAECgEJAgAAAA==.Ydrassil:BAABLgAECn8VAAINAAkJcxpFCQBTAgANAAkJcxpFCQBTAgABLgAECgkJIAAEAEwdAA==.',
Yi='Yitsuni:BAAALgAECgcJDQAAAA==.',
Za='Zalaeda:BAAALgAECgEJAQAAAA==.Zalena:BAAALgAECgQJCAAAAA==.Zatriani:BAAALgAECgYJCgAAAA==.',
Ze='Zenus:BAABLgAECn8iAAMGAAgJsxXGUgCmAQAGAAgJsxXGUgCmAQACAAMJqwfkNgBAAAAAAA==.Zerina:BAAALgADCgUJBQAAAA==.Zesty:BAAALgADCgMJAwAAAA==.Zeusal:BAABLgAECn8hAAIVAAcJjQ/ONQA7AQAVAAcJjQ/ONQA7AQAAAA==.Zeusinator:BAABLgAECn8rAAIGAAkJzxkJIwBUAgAGAAkJzxkJIwBUAgAAAA==.',
Zi='Zinu:BAABLgAECn9EAAIGAAkJ2iAsEwC0AgAGAAkJ2iAsEwC0AgAAAA==.Zivalisse:BAAALgAECgUJBwAAAA==.',
Zu='Zulfionn:BAABLgAECn8oAAIGAAkJYAqbVwCYAQAGAAkJYAqbVwCYAQAAAA==.',
Zy='Zylah:BAAALgADCgEJAQAAAA==.',
['Áy']='Áyrá:BAABLgAECn8sAAIkAAkJTRlOGABDAgAkAAkJTRlOGABDAgAAAA==.',
['Åp']='Åpollyon:BAAALgAECgYJBwAAAA==.',
['Øu']='Øuroboros:BAABLgAECn8lAAQKAAgJvxmpCwAbAgAKAAcJyxqpCwAbAgALAAYJ5hp8FAChAQAlAAQJ1heQRQDHAAAAAA==.',
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
