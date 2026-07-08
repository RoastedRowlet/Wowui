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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Devourer','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Monk-Brewmaster','Druid-Guardian','Shaman-Restoration','Shaman-Elemental','Priest-Shadow','Priest-Discipline','Druid-Restoration','Monk-Mistweaver','Druid-Balance','Warlock-Affliction','Warlock-Demonology','Druid-Feral','Warrior-Protection','Unknown-Unknown','Warrior-Arms','Monk-Windwalker','Shaman-Enhancement','Mage-Arcane','Warrior-Fury','DemonHunter-Havoc','DeathKnight-Blood','Paladin-Holy','Evoker-Augmentation','DemonHunter-Vengeance','Mage-Fire','Rogue-Assassination',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abelene:BAAALgAECgQJBAAAAA==.Abrâham:BAAALgADCgUJBQAAAA==.',
Ac='Achelis:BAABLgAECn86AAMBAAkJ8CVZAQBUAwABAAkJ8CVZAQBUAwACAAEJAABJggA/AAAAAA==.',
Ad='Adianitefall:BAAALgAECgUJBgAAAA==.Adorian:BAABLgAECn8kAAIDAAkJUQi8JwBZAQADAAkJUQi8JwBZAQAAAA==.Adros:BAABLgAECn8oAAMEAAgJQRQMFQB+AQAEAAgJQRQMFQB+AQAFAAEJHwS4wgEiAAAAAA==.Adrrel:BAAALgADCgIJAgABLgAFFAgJIQAGAGQYAA==.Adrrelle:BAACLgAFFH8hAAQGAAgJZBjHGwCXAQAGAAYJbRzHGwCXAQABAAQJWg9lFAAqAQACAAYJaw1aEgAWAQAuAAQKfyUABAIACQncHXcTAJkCAAIACAmXH3cTAJkCAAEABAnaF7I7AOIAAAYAAwmpEW64AFIAAAAA.',
Ae='Aelon:BAABLgAECn8cAAIFAAgJxgeTrwAkAQAFAAgJxgeTrwAkAQAAAA==.',
Ah='Aheiro:BAAALgAECgQJCQAAAA==.',
Ai='Ailaith:BAABLgAECn9KAAIGAAkJ0STUAwBTAwAGAAkJ0STUAwBTAwAAAA==.',
Ak='Akariliselle:BAABLgAECn8XAAIHAAcJwRoYCgCkAQAHAAcJwRoYCgCkAQAAAA==.Akarue:BAAALgAECgQJBAAAAA==.Akibafaris:BAABLgAECn8VAAMIAAkJPBteBgB+AQAIAAkJ+hpeBgB+AQAJAAEJCxONOAA7AAAAAA==.Aknologia:BAAALgAECgUJDQAAAA==.',
Al='Al:BAAALgADCggJCAAAAA==.Alan:BAAALgAECgUJCQAAAA==.Alarielle:BAAALgADCgkJEwAAAA==.Alcun:BAAALgAECgIJAwAAAA==.Aldora:BAAALgADCgkJDAAAAA==.Alirik:BAAALgADCgQJBQAAAA==.Alleriah:BAAALgAECgcJCAABLgAECggJIwAKANUgAA==.Alon:BAAALgAECgIJAgAAAA==.Alydrostage:BAABLgAECn8qAAILAAkJhwhnoAA6AQALAAkJhwhnoAA6AQAAAA==.Alystriaz:BAABLgAECn8nAAMMAAkJPxpABgCkAgAMAAkJPxpABgCkAgANAAEJsQWEKQAoAAAAAA==.Alzheimerz:BAAALgAECgUJBQAAAA==.',
Am='Amaelalin:BAABLgAECn9FAAIOAAkJ9h+vBAA1AwAOAAkJ9h+vBAA1AwAAAA==.Amaribo:BAAALgAECgEJAQABLgAFFAUJGgAPAO4mAA==.Ameliya:BAAALgAECgIJAgAAAA==.Ameng:BAAALgAECgQJBgAAAA==.',
An='Anaralestra:BAAALgAFFAEJAgABLgAFFAYJEQAQAAkTAA==.Anaralyth:BAAALgAECgYJCAABLgAFFAYJEQAQAAkTAA==.Andaya:BAACLgAFFH8aAAMRAAUJ9SAZFwCtAQARAAUJ9SAZFwCtAQASAAEJnwNjYAAtAAAuAAQKfyMAAxEACQmrGac8ALwBABEACQmrGac8ALwBABIAAgndDAaGAGQAAAAA.Andemeli:BAABLgAECn8pAAIFAAgJKQ44DQAYAQAFAAgJKQ44DQAYAQAAAA==.Andevyn:BAAALgAECgQJBAABLgAECggJIwAKANUgAA==.Aninja:BAEALgADCgQJBAABLgAFFAYJFQAIAEgdAA==.Anivia:BAABLgAECn8fAAILAAkJORHUVgDZAQALAAkJORHUVgDZAQAAAA==.Ankoubailith:BAAALgAECgQJBgAAAA==.',
Ap='Apollon:BAAALgADCgIJAwAAAA==.',
Ar='Arandis:BAABLgAECn8kAAMTAAgJawwQQwADAQATAAYJXA4QQwADAQAUAAQJkQjdVwChAAAAAA==.Arch:BAAALgAECgQJBQAAAA==.Arcianna:BAABLgAECn8yAAMQAAkJ2B2EBgCVAgAQAAkJ2B2EBgCVAgAVAAEJQRHf0wAxAAAAAA==.Arctica:BAABLgAECn8gAAILAAYJEQ4UEAD7AAALAAYJEQ4UEAD7AAAAAA==.Arctiq:BAAALgADCgUJCgAAAA==.Arctîc:BAABLgAECn8qAAILAAkJFhPRUgDkAQALAAkJFhPRUgDkAQAAAA==.Arjurn:BAABLgAECn87AAILAAkJByBaFADfAgALAAkJByBaFADfAgAAAA==.Arkro:BAAALgAECgMJBAAAAA==.Armpitbutter:BAABLgAECn87AAIWAAkJqSMJBAB1AwAWAAkJqSMJBAB1AwAAAA==.Artymiss:BAABLgAECn8cAAMXAAkJ4RFuIgC2AQAXAAkJ4RFuIgC2AQAVAAYJmRNLVgBQAQAAAA==.',
As='Asherah:BAABLgAECn8mAAQYAAgJHwr0FQAbAQAYAAcJwQj0FQAbAQAZAAcJugFo9AB5AAAHAAIJtA7+BwBbAAAAAA==.Ashireita:BAAALgAECgYJEAABLgAECgkJLgASAMoWAA==.Ashwadawnguh:BAAALgAECgEJAQAAAA==.Astraleth:BAACLgAFFH8RAAQQAAYJCRMyHACvAAAXAAMJqxVRLgDNAAAQAAUJmQsyHACvAAAVAAEJcwJVcwAzAAAuAAQKfx0AAxAACQluGgISANABABAABwkaFwISANABABcABwmpGRUIAMUAAAAA.',
At='Atama:BAAALgAECgQJBwAAAA==.Atharius:BAAALgADCgEJAQAAAA==.',
Au='Aurturious:BAAALgAECgQJBAAAAA==.Authority:BAAALgAECgMJAwAAAA==.Autry:BAABLgAECn8xAAMaAAkJ1g9tEACwAQAaAAkJ1g9tEACwAQAVAAgJUgpZUwBCAQAAAA==.',
Av='Avelina:BAAALgADCgkJFAAAAA==.Avocat:BAABLgAECn8uAAIGAAkJiRsjFwCcAgAGAAkJiRsjFwCcAgAAAA==.',
Ay='Ayrilia:BAAALgAECgYJCAABLgAFFAYJEQAQAAkTAA==.Ayshama:BAAALgAECgYJCgAAAA==.',
Az='Azeria:BAAALgAECgUJCQABLgAFFAgJEwAbABceAA==.Azetbur:BAAALgAECgQJBAAAAA==.Azshura:BAAALgAECgYJBwAAAA==.Azzinôth:BAAALgADCgcJBwABLgAECgEJAgAcAAAAAA==.',
Ba='Baekr:BAAALgAECgYJEAAAAA==.Baldr:BAABLgAECn8wAAIFAAkJKhM+TQDfAQAFAAkJKhM+TQDfAQAAAA==.Balgar:BAABLgAECn8aAAMGAAkJeCP7JABPAgAGAAkJeCP7JABPAgACAAUJyxm3PgBgAQAAAA==.Balghas:BAABLgAECn8kAAIFAAgJ1hzQMwBTAgAFAAgJ1hzQMwBTAgAAAA==.Bamz:BAAALgAFFAEJAQABLgAFFAUJHAAOAGMUAA==.Bamzhurt:BAABLgAFFH8FAAIdAAMJZxGcJgDTAAAdAAMJZxGcJgDTAAABLgAFFAUJHAAOAGMUAA==.Baumstrum:BAAALgAECgYJDQAAAA==.',
Be='Bearlydrae:BAAALgAECgMJBAAAAA==.Beezlbubba:BAAALgAECgYJDAAAAA==.Beldam:BAAALgADCgYJBgAAAA==.Belispeak:BAAALgADCgYJBgAAAA==.Bellaboom:BAAALgADCgYJBgAAAA==.Belvkara:BAAALgADCgkJCQAAAA==.Benedictoe:BAAALgADCgYJBgAAAA==.',
Bh='Bhozok:BAABLgAECn83AAIaAAkJvBI/DgDSAQAaAAkJvBI/DgDSAQAAAA==.',
Bi='Bint:BAAALgAECgEJAQAAAA==.',
Bl='Bloodpromise:BAAALgADCgMJAwAAAA==.Bloodrayvn:BAABLgAECn8wAAIGAAkJxR18GACUAgAGAAkJxR18GACUAgAAAA==.',
Bo='Boomchick:BAAALgAECgMJAwABLgAECgkJIAAGAOAdAA==.Boomparapara:BAACLgAFFH8QAAILAAQJ3xf0TQBDAQALAAQJ3xf0TQBDAQAuAAQKfycAAgsACQl9IKURAPACAAsACQl9IKURAPACAAAA.Borrkbuster:BAAALgAECgQJBAAAAA==.Bosta:BAAALgAECgQJDAAAAA==.Botkin:BAAALgADCgEJAQAAAA==.',
Br='Bradley:BAAALgAECgYJDgABLgAECggJGAAOAMogAA==.Brandywyne:BAAALgADCgEJAQAAAA==.Brenri:BAABLgAECn8eAAISAAkJwgPEVgDgAAASAAkJwgPEVgDgAAAAAA==.Brew:BAABLgAECn8mAAMPAAkJ4BrzEwAQAgAPAAkJ4BrzEwAQAgAeAAEJ0Q0LfQAzAAAAAA==.Brewtality:BAABLgAFFH8GAAIWAAQJPBUAFADmAAAWAAQJPBUAFADmAAABLgAFFAIJBQAVAMUSAA==.Brkat:BAAALgAECgIJAgAAAA==.Brughe:BAABLgAECn8tAAIGAAkJlw4TZAB9AQAGAAkJlw4TZAB9AQAAAA==.',
Bu='Bubbleoseven:BAAALgADCgYJBgABLgAFFAIJBQAVAMUSAA==.Burntbum:BAAALgAECgYJBgAAAA==.Buttacutta:BAAALgAECgEJAQAAAA==.',
['Bä']='Bäné:BAAALgADCgIJAgAAAA==.',
Ca='Cairn:BAAALgADCgUJBQAAAA==.Camaracy:BAAALgAECgUJBgAAAA==.Caneste:BAACLgAFFH8QAAITAAYJqhm2DwBwAQATAAYJqhm2DwBwAQAuAAQKfx8AAhMACQm9HfcLAMMCABMACQm9HfcLAMMCAAAA.Capela:BAAALgADCgEJAQAAAA==.Capparelli:BAAALgADCgEJAQAAAA==.Cashoe:BAAALgADCgMJAwAAAA==.Catscan:BAACLgAFFH8FAAIVAAIJxRIsVgBuAAAVAAIJxRIsVgBuAAAuAAQKfyIAAhUACQniHV0OAOUCABUACQniHV0OAOUCAAAA.Catty:BAABLgAECn8vAAIaAAkJ/BeDCABEAgAaAAkJ/BeDCABEAgAAAA==.',
Cb='Cblock:BAAALgAECgUJBQABLgAFFAMJCgAfANAIAA==.',
Ce='Celeano:BAAALgADCgkJCQABLgAECgQJBAAcAAAAAA==.Celestyl:BAABLgAECn8xAAIgAAkJ6wy4BQB2AQAgAAkJ6wy4BQB2AQAAAA==.',
Ch='Charazard:BAAALgAECgUJCgABLgAECggJJQAMAL8ZAA==.Charming:BAAALgADCgMJAwAAAA==.Cheapbeer:BAABLgAECn8VAAIFAAkJVgir2ADnAAAFAAkJVgir2ADnAAAAAA==.Cheesehead:BAAALgADCggJEgAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chiforged:BAABLgAECn8XAAIeAAgJlBOJBQDhAAAeAAgJlBOJBQDhAAAAAA==.Chillybovine:BAABLgAECn8bAAILAAcJCQqUsAAgAQALAAcJCQqUsAAgAQAAAA==.Chromstrasza:BAABLgAECn8ZAAINAAcJHxjBCQCJAQANAAcJHxjBCQCJAQAAAA==.Chudderly:BAAALgADCgEJAgAAAA==.Chudders:BAAALgADCgIJAgAAAA==.',
Ci='Cirice:BAAALgAECgEJBAAAAA==.Citrouille:BAAALgAECgEJAgAAAA==.',
Cl='Clarence:BAAALgADCgIJAgABLgAFFAkJJgAZADMXAA==.Clonazepam:BAAALgAECgUJCQABLgAECgkJJAADAFEIAA==.',
Co='Comitus:BAABLgAECn9JAAMdAAkJBhBlFwCgAQAdAAkJBhBlFwCgAQAhAAQJawVjgwCxAAAAAA==.Conjar:BAAALgAECgIJAgAAAA==.Conjarr:BAABLgAECn8zAAIOAAkJHRyEAgC/AQAOAAkJHRyEAgC/AQAAAA==.Cortisol:BAAALgADCgIJAgAAAA==.Corven:BAAALgAECgUJDAAAAA==.Cougardk:BAAALgAECgIJAgAAAA==.Cougarsixsix:BAABLgAECn8lAAIEAAgJTBbLGABWAQAEAAgJTBbLGABWAQAAAA==.Cougarwar:BAAALgAECgMJBgAAAA==.',
Cr='Crashnburn:BAAALgADCgcJDQAAAA==.Crazyoldbear:BAABLgAECn8eAAIbAAkJmCPuAwDuAgAbAAkJmCPuAwDuAgAAAA==.Creideam:BAAALgADCgkJBwAAAA==.Crimos:BAABLgAECn8wAAIIAAkJzRbsQAAAAgAIAAkJzRbsQAAAAgAAAA==.Crystalliney:BAAALgADCgYJBgABLgAFFAUJGgAPAO4mAA==.',
Cy='Cynnai:BAAALgADCgYJBgAAAA==.Cyrena:BAAALgAECgEJAQAAAA==.',
Da='Daerthor:BAABLgAECn8iAAIEAAkJOBo8CgAnAgAEAAkJOBo8CgAnAgAAAA==.Dalind:BAABLgAECn8kAAIVAAkJGghfaQD4AAAVAAkJGghfaQD4AAAAAA==.Dalora:BAAALgAECgEJAQAAAA==.Dalshiro:BAAALgAECgYJCQAAAA==.Damaclies:BAABLgAECn9QAAMZAAkJmhiABQBnAQAZAAgJmRaABQBnAQAHAAUJfBgDGADiAAAAAA==.Damedolla:BAABLgAECn8fAAMKAAgJYQzDfwAgAQAKAAgJwwrDfwAgAQAiAAUJnw7EQAD3AAAAAA==.Dammerung:BAAALgAECgYJCAAAAA==.Darksyn:BAABLgAECn8fAAIHAAkJjw2BEgAiAQAHAAkJjw2BEgAiAQAAAA==.Darthbane:BAABLgAECn8VAAMIAAkJnAn8EwC7AAAJAAgJHgXbHADnAAAIAAQJZA78EwC7AAAAAA==.Darthghidora:BAAALgADCgkJEQAAAA==.Darthstroyer:BAABLgAFFH8FAAQJAAUJwgUhGgC5AAAJAAMJjgYhGgC5AAAIAAEJXQMcFwE9AAAjAAEJAACBYwAAAAAAAA==.Darude:BAAALgADCgcJEAAAAA==.Dashoka:BAAALgAECgEJAQAAAA==.Dattiffany:BAAALgAECgUJBQAAAA==.Dawnfist:BAAALgADCggJCAAAAA==.',
De='Deadstout:BAABLgAECn8VAAQJAAYJERyDAgAdAQAjAAQJqxxEIQBIAQAJAAYJphGDAgAdAQAIAAEJUQCrqgENAAAAAA==.Deathevan:BAAALgAECggJDgABLgAECgkJLgAKADMiAA==.Deepspace:BAABLgAECn8uAAIiAAkJeSaHAACLAwAiAAkJeSaHAACLAwAAAA==.Deezknots:BAAALgAECggJCAAAAA==.Deezus:BAAALgADCgMJAwAAAA==.Dejagauth:BAAALgAECgYJDwABLgAECggJHgAkAPchAA==.Dekkan:BAAALgAECgYJEAAAAA==.Demonedd:BAAALgADCgMJAgAAAA==.Demòn:BAAALgAECgEJAQAAAA==.Desdia:BAABLgAECn8hAAILAAgJ2BgWCwA8AQALAAgJ2BgWCwA8AQAAAA==.',
Di='Dia:BAAALgAECgQJBwAAAA==.Diabetes:BAABLgAFFH8VAAIWAAcJmRoTFwDFAQAWAAcJmRoTFwDFAQAAAA==.Diastolic:BAAALgADCgUJBQAAAA==.Didyoudie:BAAALgAECggJDgAAAA==.Diend:BAABLgAECn9UAAIRAAkJgSTMAQCzAwARAAkJgSTMAQCzAwAAAA==.Dill:BAAALgAECgEJAQABLgAECgkJOgABAPAlAA==.Dillathis:BAAALgADCgEJAQAAAA==.Discord:BAAALgAECgQJBQABLgAFFAMJBAAcAAAAAA==.Dissonanita:BAABLgAECn8eAAIGAAgJwRKnCABxAQAGAAgJwRKnCABxAQAAAA==.',
Dj='Djthelock:BAABLgAECn8sAAMZAAkJuRb8NQABAgAZAAgJxBP8NQABAgAHAAQJDhhPHADEAAAAAA==.',
Do='Dormoon:BAABLgAECn8bAAMhAAgJnQ1/QQA/AQAhAAgJnQ1/QQA/AQAbAAEJIBH9VAAuAAAAAA==.',
Dr='Drac:BAAALgADCgYJCgAAAA==.Draeblade:BAAALgAECgQJBAAAAA==.Dragath:BAAALgAECgYJDgAAAA==.Drakur:BAAALgAECgYJCQAAAA==.Drbrad:BAABLgAECn8YAAQOAAgJyiB5FgAdAgAOAAcJjyJ5FgAdAgATAAMJDhAdcQBgAAAUAAEJaBSyEwBAAAAAAA==.Dreadfangs:BAAALgADCgQJBQAAAA==.Druen:BAABLgAECn8yAAIaAAkJHB53BAC4AgAaAAkJHB53BAC4AgAAAA==.Drunkenpo:BAABLgAECn9QAAQPAAkJ5yH4BADzAgAPAAkJtSH4BADzAgAWAAUJ7hOeUQAoAQAeAAIJqCKoDABiAAAAAA==.Drykin:BAAALgAECgYJCwAAAA==.Drïzl:BAEALgAECgMJAwABLgAFFAYJFQAIAEgdAA==.',
Du='Duckchow:BAAALgADCgYJBgAAAA==.Dugga:BAAALgADCgQJBAAAAA==.Duskmyre:BAABLgAECn8lAAIKAAkJbw0OWQB8AQAKAAkJbw0OWQB8AQAAAA==.',
Dw='Dwarfoo:BAABLgAECn8eAAMeAAkJCxeoPwABAQAeAAcJOBOoPwABAQAWAAYJRw7WDgDHAAAAAA==.Dweñde:BAABLgAECn8nAAIZAAkJigrVYAB+AQAZAAkJigrVYAB+AQAAAA==.',
['Dë']='Dëthmetal:BAABLgAECn8UAAIIAAUJnQxfwgD/AAAIAAUJnQxfwgD/AAAAAA==.',
Ec='Ecthelion:BAAALgAECgEJAQAAAA==.',
Ed='Eddiemac:BAAALgAECgYJCgAAAA==.Eddrick:BAACLgAFFH8LAAIFAAMJthloIgDMAAAFAAMJthloIgDMAAAuAAQKfzcAAwUACQkwH44TAM0CAAUACQkqH44TAM0CAAQABQkvHZ0ZAEwBAAAA.Edoran:BAAALgADCggJCAAAAA==.Edrani:BAAALgAECgYJDgAAAA==.',
Ei='Eilethen:BAABLgAECn8nAAIYAAkJOxocBgAfAgAYAAkJOxocBgAfAgAAAA==.',
Ek='Ekassa:BAAALgADCgkJCQAAAA==.',
El='Elaína:BAAALgADCgMJAwABLgAFFAUJGQAYAMUSAA==.Elementoe:BAAALgADCgEJAQABLgADCgYJBgAcAAAAAA==.Elendil:BAAALgAECgMJAwAAAA==.Elissabethh:BAAALgAECgYJEAAAAA==.Elleryn:BAAALgAECgQJBAABLgAECgYJGQARALwXAA==.Elminstar:BAAALgADCgIJAgAAAA==.Elêctra:BAAALgAECgEJAgABLgAFFAEJAQAcAAAAAA==.',
Em='Employee:BAABLgAECn8VAAIlAAgJ4wvCSAAIAQAlAAgJ4wvCSAAIAQAAAA==.',
En='Engo:BAABLgAECn9EAAMOAAkJdiRnAwBZAwAOAAkJdCNnAwBZAwAUAAkJ9BslCQDhAgAAAA==.',
Er='Eradrá:BAACLgAFFH8ZAAMYAAUJxRJKEQCFAAAZAAUJxRIfVQAcAQAYAAIJAQxKEQCFAAAuAAQKf1AAAxgACQmzHugAAA4DABgACQmsG+gAAA4DABkACQm9GDUiAFkCAAAA.Eragon:BAAALgAECggJDgAAAA==.Erastrasza:BAAALgADCgYJCQAAAA==.Eroza:BAAALgAECgUJBgAAAA==.Ersey:BAAALgAECgQJBAABLgAFFAMJBwAVAO8HAA==.Ersèlla:BAACLgAFFH8HAAIVAAMJ7wdATACMAAAVAAMJ7wdATACMAAAuAAQKfy4AAxUACQmMGHobAGoCABUACQmMGHobAGoCABcAAQnYBSqdACQAAAAA.Erysira:BAAALgADCgkJCQABLgAECggJHQALAFYSAA==.',
Et='Ethan:BAAALgAECgEJAgAAAQ==.',
Eu='Eureka:BAABLgAECn8gAAMEAAkJTB2ADgDbAQAEAAcJ1RyADgDbAQAFAAcJSRnuZQCkAQABLgAFFAMJCAAbAJMbAA==.',
Ev='Evandra:BAABLgAECn8vAAIRAAkJBRzGFgCTAgARAAkJBRzGFgCTAgAAAA==.Evanorah:BAABLgAECn8cAAMHAAcJjwmHIgCcAAAZAAcJYAkMlAAUAQAHAAYJowWHIgCcAAAAAA==.',
Ex='Exïle:BAEALgAECgYJBgABLgAFFAYJFQAIAEgdAA==.',
Fa='Fabio:BAAALgADCgIJAgAAAA==.Faedeyeda:BAAALgAECgEJAgAAAA==.Faelithia:BAABLgAECn8WAAIOAAYJKA4PPQD/AAAOAAYJKA4PPQD/AAAAAA==.Fatalbrew:BAAALgAECgYJCwAAAA==.Fauxyalee:BAAALgADCgkJEgAAAA==.',
Fe='Feldush:BAAALgADCgYJBgABLgAECggJJQAMAL8ZAA==.Felforit:BAAALgADCgQJBAAAAA==.Felis:BAAALgAECgYJCgAAAA==.Felkardio:BAAALgAECgIJAgAAAA==.Feloth:BAAALgAECgEJAQAAAA==.Ferheim:BAAALgAECgYJEwAAAA==.Ferhold:BAAALgADCgYJBwAAAA==.Ferrovax:BAAALgADCgYJBgABLgAECgkJLgAKAPAZAA==.',
Fi='Fiddyone:BAABLgAECn8sAAMJAAkJySEoAwC+AgAJAAkJtCEoAwC+AgAIAAgJcR0pRQDzAQAAAA==.Figment:BAAALgADCgYJBgAAAA==.Fireburt:BAAALgADCgUJBQAAAA==.Fireslay:BAABLgAECn8YAAIkAAcJpBwHHgAmAgAkAAcJpBwHHgAmAgAAAA==.Fizzlegrin:BAAALgAECgIJAgAAAA==.',
Fl='Flarefly:BAAALgAECgEJAQAAAA==.Flaya:BAAALgAECgcJDAAAAA==.',
Fo='Fodurzin:BAABLgAECn8UAAIFAAUJFQ5S0QDxAAAFAAUJFQ5S0QDxAAAAAA==.Fonta:BAAALgAECgMJAwAAAA==.Fortuna:BAAALgADCggJCAABLgAECgkJIAAGAOAdAA==.Foxingtobi:BAAALgADCgIJAgAAAA==.',
Fr='Frojio:BAABLgAECn8zAAIJAAkJ4ByaBQBYAgAJAAkJ4ByaBQBYAgAAAA==.Frosten:BAAALgAECgEJAQAAAA==.',
Fu='Furenio:BAABLgAECn80AAIQAAkJ7xekDgD6AQAQAAkJ7xekDgD6AQAAAA==.',
Fy='Fyyre:BAAALgAECgUJBwAAAA==.',
Ga='Gabaghoul:BAACLgAFFH8YAAIFAAUJFh3zKgBhAQAFAAUJFh3zKgBhAQAuAAQKfzEAAgUACQl3IHoZAKsCAAUACQl3IHoZAKsCAAAA.Gaff:BAAALgAECgkJEwAAAA==.Galeana:BAAALgAECgMJAwABLgAECgkJDQAcAAAAAA==.Galvan:BAAALgAECgEJBAAAAA==.Gasheth:BAAALgAECgYJDQAAAA==.',
Ge='Gentyl:BAAALgAECgQJBAAAAA==.',
Gi='Giggleblast:BAAALgAECgIJAgAAAA==.',
Gl='Glizzydealer:BAAALgAECgEJAQAAAA==.',
Gr='Grauth:BAAALgADCgEJAQAAAA==.Graycen:BAAALgAECgUJCQAAAA==.Grido:BAAALgAECgIJAgAAAA==.Grimbrindral:BAABLgAECn8hAAMFAAcJ5hZDZAC5AQAFAAcJdBVDZAC5AQAEAAUJghrKFwBZAQAAAA==.Grimston:BAAALgADCgMJAwABLgAECgcJIQAFAOYWAA==.Gruzaxx:BAAALgADCgUJBQAAAA==.',
Gu='Gulishdaniel:BAABLgAFFH8GAAIYAAQJJQRRCQDlAAAYAAQJJQRRCQDlAAABLgAFFAYJEAATAKoZAA==.',
Ha='Hadin:BAABLgAECn9NAAMLAAkJMCTGBgBKAwALAAkJMCTGBgBKAwAgAAMJqhysDwDHAAAAAA==.Hakeko:BAAALgAECgcJEQABLgAECggJFgAIAHMTAA==.Halalnt:BAAALgAFFAIJAwAAAA==.Hanua:BAAALgADCgcJBwAAAA==.Haozhao:BAABLgAECn9NAAMQAAkJXRsuCQBYAgAQAAkJXRsuCQBYAgAaAAEJDhQnTwA7AAAAAA==.Hawktuahz:BAAALgAECgMJAwAAAA==.Hazenpryde:BAABLgAECn8fAAIQAAgJahoeEADnAQAQAAgJahoeEADnAQAAAA==.',
He='Hearsay:BAABLgAECn9EAAQFAAgJdREjcACOAQAFAAgJdREjcACOAQAkAAYJXwkdBwDPAAAEAAEJrgf0DwAcAAABLgAECgkJLAAVAHIUAA==.Helden:BAAALgAECgEJAQAAAA==.Hephaistian:BAAALgAECgYJBgAAAA==.Hespera:BAACLgAFFH8VAAMVAAUJFQ9eJgApAQAVAAUJFQ9eJgApAQAXAAMJ8whCOgCQAAAuAAQKfyMAAxUACQnJIOkYAHACABUACAmiIekYAHACABcAAwmnFP5SAMMAAAAA.',
Hi='Hirari:BAABLgAECn8dAAMkAAYJBCWUFwBMAgAkAAYJBCWUFwBMAgAFAAEJFBpjeQFCAAAAAA==.',
Ho='Hodoor:BAAALgAECgYJCAAAAA==.Horsebananas:BAAALgAECgEJAQABLgAECgkJOAABANMcAA==.Howlears:BAABLgAECn8qAAITAAkJHQhOOwAlAQATAAkJHQhOOwAlAQAAAA==.',
Hu='Hulud:BAABLgAECn8YAAMZAAkJfRbiSwC3AQAZAAkJfRbiSwC3AQAHAAEJAADYVAAAAAAAAA==.Husbando:BAAALgAECgMJAwAAAA==.Husey:BAAALgAECgMJBgAAAA==.',
Hy='Hydrangea:BAABLgAECn8dAAIFAAcJ4Q+VkQBPAQAFAAcJ4Q+VkQBPAQAAAA==.Hydrá:BAABLgAECn8aAAIZAAkJvRYCMQAUAgAZAAkJvRYCMQAUAgAAAA==.Hylan:BAAALgADCgUJBQAAAA==.Hysgar:BAAALgAECgUJBQABLgAECggJHgAkAPchAA==.',
Ic='Iceamaris:BAABLgAECn8gAAISAAkJYQv/OABTAQASAAkJYQv/OABTAQAAAA==.Icetiger:BAAALgAECgEJAQAAAA==.Icetigress:BAAALgAECgEJAQAAAA==.',
Ie='Iechu:BAABLgAECn8hAAMPAAgJbBFGIwCQAQAPAAgJbBFGIwCQAQAeAAIJ9QZujABFAAAAAA==.',
In='Innanna:BAAALgADCggJCgABLgAECgcJFgAKAC4SAA==.',
Is='Isoth:BAAALgAECgEJAQAAAA==.',
Iv='Ivern:BAACLgAFFH8VAAIVAAgJ+hGKCAByAgAVAAgJ+hGKCAByAgAuAAQKfx0AAxUABgkHHfgyANIBABUABgkHHfgyANIBABcAAgnRBzWXACkAAAAA.Ivysnow:BAAALgAECgEJAQAAAA==.',
Ja='Jac:BAAALgAECgMJAwABLgAFFAMJBAAcAAAAAA==.Jadenpryde:BAAALgAECgYJBwABLgAECggJHwAQAGoaAA==.Jaod:BAAALgAECgQJAgAAAA==.Jarndal:BAAALgAECgEJAQAAAA==.Jasmirrae:BAAALgAECgEJAQAAAA==.',
Jd='Jdghoul:BAAALgAECggJDwAAAA==.',
Ji='Jian:BAAALgADCgIJAgAAAA==.Jindrac:BAAALgAECgkJDwAAAA==.',
Jo='Jolton:BAAALgADCgYJBwABLgAECgkJLgAKADMiAA==.',
['Jà']='Jàcaranda:BAAALgAECgYJBwAAAA==.',
Ka='Kahnrah:BAAALgADCgkJDAAAAA==.Kalarae:BAAALgAECggJCQAAAA==.Kalarill:BAABLgAECn8eAAIFAAcJZR1rMAA/AgAFAAcJZR1rMAA/AgAAAA==.Kaljeer:BAAALgAECgYJBgAAAA==.Kaltharion:BAABLgAFFH8HAAIMAAQJ6wOCDAB8AAAMAAQJ6wOCDAB8AAAAAA==.Kaluren:BAAALgAECgcJDwAAAA==.Kalurok:BAAALgAECgUJBQABLgAECgcJDwAcAAAAAA==.Kana:BAAALgAECgIJAgAAAA==.Kanade:BAABLgAECn9JAAQZAAkJBh7BFwCVAgAZAAgJ1R3BFwCVAgAYAAcJsRUACQDVAQAHAAQJWAsKTACJAAAAAA==.Kantong:BAABLgAECn8gAAIeAAgJdRmIGwDTAQAeAAgJdRmIGwDTAQAAAA==.Kapp:BAABLgAECn8UAAMhAAgJmwohWADuAAAhAAYJkAkhWADuAAAbAAIJNg0ODAA3AAAAAA==.Karabar:BAABLgAECn87AAMEAAkJ2yAYBQCjAgAEAAkJyh4YBQCjAgAFAAgJoyDzKABfAgAAAA==.Karnnaged:BAAALgADCgYJBwAAAA==.Kasarra:BAABLgAECn8zAAIiAAkJhxX2EwDzAQAiAAkJhxX2EwDzAQAAAA==.Kazagol:BAABLgAECn87AAIKAAkJ+x2rGgB0AgAKAAkJ+x2rGgB0AgAAAA==.',
Ke='Kelintos:BAAALgAECgEJAgABLgAECgkJOAAKAD4cAA==.Keone:BAAALgADCgEJAQAAAA==.Kethysa:BAAALgADCgIJAgAAAA==.',
Kh='Khalla:BAAALgAFFAEJAQAAAA==.Khamaracy:BAABLgAECn8mAAMHAAkJgwqHAwDeAAAHAAkJgwqHAwDeAAAZAAEJsQE6ZQEbAAAAAA==.Khronni:BAAALgAECgYJCQAAAA==.Khrooze:BAAALgAECgYJEQAAAA==.',
Ki='Kidos:BAAALgAECgQJBgAAAA==.Kiljana:BAAALgAECgEJAQAAAA==.Kimahrí:BAABLgAECn8gAAIjAAkJSAd9LwDkAAAjAAkJSAd9LwDkAAAAAA==.Kittei:BAABLgAECn87AAIQAAkJ1w+eGwBwAQAQAAkJ1w+eGwBwAQAAAA==.',
Ko='Kojote:BAAALgADCgMJAQAAAA==.Kovalenko:BAAALgAECggJDgAAAA==.',
Kr='Krepow:BAAALgAECgYJCQAAAA==.',
Ku='Kurick:BAABLgAECn8eAAMkAAgJ9yEvCAAJAwAkAAgJ9yEvCAAJAwAFAAMJLQxWfgE+AAAAAA==.Kurzul:BAAALgADCgEJAgAAAA==.Kusinluvin:BAAALgAECgEJAQAAAA==.',
Ky='Kyngizzard:BAABLgAECn8fAAILAAkJSRrUNwA5AgALAAkJSRrUNwA5AgABLgAFFAIJAwAcAAAAAA==.Kytherin:BAAALgAECgYJDAAAAA==.',
La='Lactase:BAAALgADCgMJAwAAAA==.Lainea:BAAALgAECgMJAQAAAA==.Langtry:BAAALgADCgcJBgAAAA==.Lanoree:BAABLgAECn8WAAQJAAkJfQDJRgAGAAAIAAYJMQAnrAEGAAAJAAkJfQDJRgAGAAAjAAIJAAAAAAAAAAAAAA==.Latte:BAAALgAECgcJCgAAAA==.',
Le='Leblanc:BAAALgAECgEJAQABLgAECgkJGAAFAEEeAA==.Leeli:BAAALgADCgcJBwAAAA==.Lenity:BAACLgAFFH8GAAIDAAIJgQlEFgCPAAADAAIJgQlEFgCPAAAuAAQKf1oAAgMACQkyGrkAAHsCAAMACQkyGrkAAHsCAAAA.Letty:BAAALgAECgQJCAAAAA==.',
Li='Liabelle:BAAALgADCgIJAgAAAA==.Lightsmite:BAAALgAECgIJAgAAAA==.Lilithene:BAAALgAECgUJBgABLgAECgkJLgASAMoWAA==.Lionbark:BAAALgADCgEJAQAAAA==.Lionell:BAAALgADCgUJBgAAAA==.Lithpally:BAAALgADCgEJAQAAAA==.Liubeijian:BAAALgADCgYJBgABLgAECgcJFgAKAC4SAA==.',
Lo='Loan:BAAALgAECgUJBQABLgAECgcJDAAcAAAAAA==.Lokinah:BAABLgAECn8gAAIGAAkJAQjBgAA9AQAGAAkJAQjBgAA9AQAAAA==.Loonytusk:BAAALgADCgQJBAAAAA==.',
Lu='Lucifermadis:BAAALgAECgQJBgAAAA==.Lucoryphus:BAABLgAECn8hAAIjAAcJ1RfYGQCQAQAjAAcJ1RfYGQCQAQAAAA==.Lukeduke:BAABLgAFFH8TAAIbAAgJFx4ZBAAwAgAbAAgJFx4ZBAAwAgAAAA==.Luketheduke:BAACLgAFFH8ZAAMQAAYJgR5RBADGAQAQAAUJgR5RBADGAQAaAAEJAAAIBwA3AAAuAAQKfyoAAxAACQkvJR8BAFcDABAACQkvJR8BAFcDABoABAmxFXscAAkBAAEuAAUUCAkTABsAFx4A.Lumilia:BAAALgADCgUJBQAAAA==.Lunaries:BAAALgAECgYJBgAAAA==.Lunä:BAACLgAFFH8KAAIRAAMJ7R50EAAKAQARAAMJ7R50EAAKAQAuAAQKfycAAhEACQlUFmoiABACABEACQlUFmoiABACAAAA.',
Ly='Lydia:BAABLgAECn8pAAILAAkJphkzNABIAgALAAkJphkzNABIAgAAAA==.Lynnee:BAAALgADCgEJAQAAAA==.',
['Lô']='Lôckrocks:BAABLgAECn8ZAAIHAAcJxhGODwBHAQAHAAcJxhGODwBHAQAAAA==.',
['Lý']='Lýsendra:BAAALgADCggJCQAAAA==.',
Ma='Magickeys:BAAALgAFFAIJAgAAAA==.Magictomb:BAACLgAFFH8KAAMfAAMJ0AjiCAB4AAAfAAMJ0AjiCAB4AAASAAEJrgE5IQA7AAAuAAQKfzIABBIACQltFeU4AFMBABIACAmXFeU4AFMBABEABgnpDTd8AOsAAB8ABgm3DsgEAMkAAAAA.Mahdude:BAAALgAECgEJAQAAAA==.Malastor:BAAALgAECgEJAQABLgAFFAMJBAAcAAAAAA==.Malcontent:BAAALgAECgcJEQABLgAFFAMJBAAcAAAAAA==.Maldazane:BAAALgADCgYJCwAAAA==.Malfeasance:BAAALgAECgYJBgABLgAFFAMJBAAcAAAAAA==.Malidan:BAAALgADCgMJAwAAAA==.Malifel:BAABLgAECn8sAAMmAAkJsiCcAAAkAgAmAAkJsiCcAAAkAgAKAAYJ+BQNBwA4AQABLgAFFAMJBAAcAAAAAA==.Maliss:BAABLgAECn9AAAQBAAkJRRgcFAAEAgABAAkJahccFAAEAgACAAQJ8RHLIQCjAAAGAAEJoxETLwE3AAAAAA==.Mallord:BAAALgAFFAMJBAAAAA==.Mandarin:BAABLgAECn84AAIVAAkJ8hoNEwCzAgAVAAkJ8hoNEwCzAgAAAA==.Manmythlegnd:BAAALgADCgYJBgAAAA==.Mannik:BAABLgAECn8aAAIZAAgJrRmPMgAOAgAZAAgJrRmPMgAOAgAAAA==.Marashade:BAAALgAECgUJBQAAAA==.Marashades:BAAALgAECgUJBgABLgAECgkJHgAbAJgjAA==.Mathemagics:BAAALgAECgIJAgAAAA==.',
Mc='Mcbadden:BAAALgAECgYJCAAAAA==.',
Me='Meditatetoe:BAAALgADCgIJAgABLgADCgYJBgAcAAAAAA==.Melissà:BAAALgADCgMJAwAAAA==.Menesta:BAAALgADCgcJBwABLgAECgUJFAAFABUOAA==.Mercia:BAABLgAECn8wAAIEAAkJExuDCQA3AgAEAAkJExuDCQA3AgAAAA==.Merekoma:BAABLgAECn8uAAMKAAkJ8BkOLQATAgAKAAkJrhUOLQATAgAmAAQJFhY8HQCxAAAAAA==.',
Mi='Milarra:BAABLgAECn8VAAInAAcJMAnaCAD9AAAnAAcJMAnaCAD9AAAAAA==.Milhouse:BAABLgAECn8fAAILAAcJNg2DFQDGAAALAAcJNg2DFQDGAAAAAA==.Minalan:BAAALgADCgYJCgABLgAECgYJEQAcAAAAAA==.Mingonashoba:BAABLgAECn8jAAIGAAkJYw69RgDNAQAGAAkJYw69RgDNAQAAAA==.Miragosa:BAABLgAECn8zAAMMAAkJUA+UDwDSAQAMAAkJUA+UDwDSAQANAAcJ3gg7EAAHAQAAAA==.Misschris:BAABLgAECn8tAAIWAAkJBA1zQABsAQAWAAkJBA1zQABsAQAAAA==.Mistycinamon:BAAALgAECgEJAQAAAA==.Mizu:BAAALgAECgUJBQAAAA==.',
Mo='Moadeed:BAABLgAECn8fAAMQAAkJbxViEgDLAQAQAAkJZxViEgDLAQAXAAMJdA1jCwCCAAAAAA==.Mooluv:BAAALgADCgcJCgAAAA==.Moonstrike:BAAALgAECgIJAgAAAA==.Mordrius:BAAALgADCgYJBgAAAA==.Morphmious:BAAALgAECgcJBwAAAA==.Mortesque:BAAALgAECgcJEgAAAA==.',
Mu='Muttblitzed:BAABLgAECn8aAAIGAAgJnxZNTAC9AQAGAAgJnxZNTAC9AQAAAA==.Muttskî:BAAALgAECgMJAwAAAA==.',
My='Mybutt:BAAALgAECgMJBgAAAA==.Myroku:BAAALgADCgcJBwABLgAFFAMJBAAcAAAAAA==.Myrothos:BAAALgADCgEJAQAAAA==.Myrrh:BAABLgAECn8YAAMlAAYJdAefYQC1AAAlAAYJggafYQC1AAANAAQJ9wYzLQCxAAAAAA==.Mysklef:BAAALgADCgMJAwABLgAECggJHgAkAPchAA==.Mythris:BAAALgAECgkJBQAAAA==.',
['Mí']='Místermage:BAAALgAECgQJCAAAAA==.',
Na='Nadrael:BAAALgAECgEJAwAAAA==.Nasturtium:BAAALgADCgYJDgAAAA==.Nausican:BAABLgAECn9IAAIJAAkJvxo9BACLAgAJAAkJvxo9BACLAgAAAA==.Nazuhda:BAAALgADCgEJAQAAAA==.',
Ne='Necrosector:BAACLgAFFH8KAAIFAAUJAgoqVgADAQAFAAUJAgoqVgADAQAuAAQKfyYAAgUACAm5Gc9OANsBAAUACAm5Gc9OANsBAAAA.Necrotherys:BAABLgAECn84AAIKAAkJPhz0FwCGAgAKAAkJPhz0FwCGAgAAAA==.Nelandra:BAABLgAECn8jAAITAAkJnhlqFgAXAgATAAkJnhlqFgAXAgAAAA==.',
Ni='Nicklaus:BAABLgAECn8oAAIDAAcJlglnLwAjAQADAAcJlglnLwAjAQAAAA==.Nilrem:BAAALgADCgIJAgAAAA==.Ninelives:BAAALgAECgYJDgAAAA==.Ninjadk:BAECLgAFFH8VAAMIAAYJSB1gUABRAQAIAAUJSB1gUABRAQAjAAEJAABVZQAAAAAuAAQKfzEAAwgACQmyIQAPAPQCAAgACQmyIQAPAPQCAAkAAQm4G6U3AD4AAAAA.',
No='Nocapongfrfr:BAAALgAECgMJAwABLgAFFAUJBQAJAMIFAA==.Nomahuata:BAABLgAECn9NAAISAAkJZhkrAwCMAQASAAkJZhkrAwCMAQAAAA==.Nordre:BAAALgAECgMJAwAAAA==.',
Nu='Nufrus:BAAALgAECgEJAQAAAA==.',
Ny='Nyeli:BAAALgAECgYJCwABLgAECgYJGQARALwXAA==.Nyxi:BAABLgAECn8eAAIRAAkJDhjTIABKAgARAAkJDhjTIABKAgAAAA==.Nyxlee:BAAALgAECgcJBwAAAA==.',
['Né']='Néo:BAAALgAECgUJCAAAAA==.',
['Nó']='Nóóôööôòòpe:BAABLgAFFH8HAAIGAAQJpAbyWgDvAAAGAAQJpAbyWgDvAAABLgAFFAUJBQAJAMIFAA==.',
Og='Ogdruid:BAAALgADCgcJDgAAAA==.',
Ok='Okume:BAAALgAECgIJAgAAAA==.',
Ol='Olympian:BAAALgADCgcJBwAAAA==.',
Om='Omanyte:BAAALgADCgcJBwAAAA==.',
On='Onefiftyone:BAABLgAECn8bAAMfAAYJHCVGCgAVAgAfAAYJHCVGCgAVAgARAAIJnSQsigDHAAABLgAECgkJLAAJAMkhAA==.',
Or='Orruk:BAAALgADCgMJAwAAAA==.Orwyn:BAAALgADCgkJEwAAAA==.',
Ov='Overdose:BAAALgADCgMJAwAAAA==.',
Pa='Padmé:BAAALgAECgQJBgAAAA==.Pain:BAAALgAECgUJCwAAAA==.Palanas:BAAALgAFFAEJAQAAAA==.Pallamoo:BAAALgAECgcJCAAAAA==.Palochka:BAAALgAECgcJCQAAAA==.Paradots:BAABLgAECn8WAAIMAAYJwBpqEgCiAQAMAAYJwBpqEgCiAQABLgAFFAIJBQAVAMUSAA==.Paranitis:BAAALgAECggJDAAAAA==.Paranorm:BAAALgADCgEJAQAAAA==.Paraparaboom:BAAALgAECgUJBQABLgAFFAQJEAALAN8XAA==.',
Pe='Pezdormu:BAAALgADCgEJAQAAAA==.Pezmage:BAAALgAECgIJBAAAAA==.',
Ph='Phatboi:BAAALgAECgEJAwAAAA==.Pheroth:BAAALgAECgUJDQABLgAECgkJHwAHAI8NAA==.',
Pi='Pixydaddy:BAAALgAECgkJCAABLgAECgkJMAAKACEaAA==.Pixystix:BAABLgAECn8wAAIKAAkJIRryAgDDAQAKAAkJIRryAgDDAQAAAA==.',
Po='Poisonspain:BAAALgAECgMJAwAAAA==.Popsdh:BAAALgAECggJEwABLgAFFAMJCAAbAJMbAA==.Portlukk:BAAALgADCgEJAQAAAA==.Possibly:BAAALgAECgEJAQAAAA==.Potscold:BAACLgAFFH8QAAILAAgJARaGDAC5AQALAAgJARaGDAC5AQAuAAQKf0EAAgsACAnbJbsRAD0DAAsACAnbJbsRAD0DAAAA.Poxi:BAAALgAECgIJAgABLgAECggJGAALADwdAA==.',
Pr='Prion:BAABLgAECn8fAAIhAAgJ7xT5KQCwAQAhAAgJ7xT5KQCwAQAAAA==.',
Pu='Pull:BAABLgAECn8jAAIQAAkJnxssCgBFAgAQAAkJnxssCgBFAgAAAA==.',
Ra='Radioshack:BAAALgADCggJCAAAAA==.Radkemonko:BAAALgAECgcJDwAAAA==.Raega:BAAALgADCgYJBgAAAA==.Ragerlock:BAAALgADCgEJAQAAAA==.Raivel:BAABLgAECn8ZAAIRAAYJvBf+RgCSAQARAAYJvBf+RgCSAQAAAA==.Raldaron:BAAALgADCgEJAQAAAA==.Rambogg:BAAALgAECgEJAQABLgAFFAgJHAALAOwOAA==.Raneyth:BAAALgAECgcJBwAAAA==.Ranith:BAAALgADCgMJAwAAAA==.Ravagèr:BAAALgAECgEJAgAAAA==.',
Rd='Rdbwarrior:BAAALgADCgUJBQAAAA==.',
Re='Redemus:BAAALgADCgEJAQAAAA==.Redwinetoast:BAABLgAECn8kAAIZAAkJUAWBkQAYAQAZAAkJUAWBkQAYAQAAAA==.Rekllaw:BAAALgAECgIJAgAAAA==.Reliala:BAAALgADCgkJEQAAAA==.Reno:BAAALgAECgcJDAAAAA==.Reshyk:BAABLgAECn8UAAIaAAkJQhyVCwACAgAaAAkJQhyVCwACAgAAAA==.Resles:BAAALgAECgEJAQAAAA==.Respectwomen:BAAALgADCgEJAQABLgAECgQJBAAcAAAAAA==.',
Rh='Rhobes:BAABLgAECn8bAAIhAAgJOxD0BwDtAAAhAAgJOxD0BwDtAAAAAA==.Rhondta:BAABLgAECn8nAAIZAAkJJRLrRQDJAQAZAAkJJRLrRQDJAQAAAA==.',
Ri='Rickormortis:BAABLgAECn8UAAIIAAkJGB1iHgCRAgAIAAkJGB1iHgCRAgABLgAECgkJLQAWAAQNAA==.Rictus:BAABLgAECn8wAAILAAkJjSSLCAA4AwALAAkJjSSLCAA4AwAAAA==.Ringmasterr:BAAALgADCgUJBQAAAA==.Riordaa:BAAALgADCgYJDAAAAA==.Risingdragon:BAABLgAECn8qAAIeAAcJMhOHLgBQAQAeAAcJMhOHLgBQAQAAAA==.',
Ro='Roades:BAAALgADCgcJDAAAAA==.Roboskritch:BAAALgADCgUJBQAAAA==.Ronaj:BAAALgADCgMJBAAAAA==.Rowene:BAAALgAECgIJAgAAAA==.Royveer:BAAALgADCgYJCQAAAA==.',
Ru='Rumor:BAABLgAECn8sAAUVAAkJchS7AgDNAQAVAAkJchS7AgDNAQAaAAcJvxTCEwCDAQAQAAMJlwzmXABVAAAXAAIJdAkLgwBDAAAAAA==.Rurry:BAACLgAFFH8YAAIMAAYJpRe+BACuAQAMAAYJpRe+BACuAQAuAAQKfy4ABAwACQnIIrECAEADAAwACQnIIrECAEADAA0ABQm6GR4WAI8BACUAAwlVF/RGAL8AAAEuAAUUCAkVABUA+hEA.',
Ry='Ryumi:BAABLgAECn8uAAIKAAkJMyJbFwCKAgAKAAkJMyJbFwCKAgAAAA==.Ryur:BAAALgAECgQJDgAAAA==.Ryuuki:BAAALgAECggJEwABLgAECgkJLgAKADMiAA==.',
Sa='Sabastion:BAAALgAECgYJBgABLgAFFAMJBAAcAAAAAA==.Sacrickficed:BAAALgAECgQJBAABLgAECgkJLQAWAAQNAA==.Sahwe:BAABLgAECn8UAAMVAAYJnwz/aQD2AAAVAAYJnwz/aQD2AAAXAAEJ0wcemAAoAAAAAA==.Salchicha:BAAALgADCgEJAQABLgAECgUJFAAFABUOAA==.Salmoo:BAAALgAECgUJCQABLgAECgUJFAAFABUOAA==.Salocar:BAAALgAECgcJEwAAAA==.Sanafela:BAAALgADCgkJXgAAAA==.Saphisha:BAABLgAECn8UAAIeAAgJVxcIIACtAQAeAAgJVxcIIACtAQAAAA==.Sasora:BAAALgAECgUJCwAAAA==.Saucemagic:BAAALgAECgcJDQAAAA==.Savonah:BAAALgAECgUJBgAAAA==.',
Sc='Scaledaddy:BAABLgAECn8jAAIlAAkJug0HKgCYAQAlAAkJug0HKgCYAQAAAA==.Scalespawn:BAAALgADCgYJBgABLgAFFAgJHgAIAEwZAA==.Scaryl:BAABLgAECn8WAAIXAAgJAQlXBwDVAAAXAAgJAQlXBwDVAAAAAA==.Scourgespawn:BAACLgAFFH8eAAQIAAgJTBlWJADcAQAIAAYJJhtWJADcAQAJAAQJgxJzDAA3AQAjAAIJpwjBQwAnAAAuAAQKfyoAAwgACQmyIDMkAK0CAAgACQmyIDMkAK0CACMABAnhFXI5AK0AAAAA.',
Se='Searthenio:BAAALgAECggJCQAAAA==.Selenë:BAABLgAECn8eAAMOAAcJyhbkHQDWAQAOAAcJyhbkHQDWAQATAAEJxwF/nAAWAAAAAA==.Sengoku:BAAALgAECgEJAQAAAA==.Seraz:BAAALgADCgkJCAAAAA==.Serbiscuit:BAAALgAECgUJCgAAAA==.Sereneya:BAAALgAECgYJBgAAAA==.Serenio:BAAALgAECgcJEQAAAA==.Serenval:BAAALgAECgEJAQAAAA==.',
Sh='Shadowshart:BAAALgAECgEJAQAAAA==.Shadus:BAAALgAECgUJBQAAAA==.Shadyaf:BAAALgAECgEJAQAAAA==.Shailora:BAAALgAECgQJAwAAAA==.Shait:BAAALgADCgYJBgAAAA==.Shalis:BAABLgAECn8sAAIGAAkJWxxzHAB6AgAGAAkJWxxzHAB6AgAAAA==.Sharivee:BAABLgAECn8cAAMLAAkJ6SDgEgDpAgALAAkJuh/gEgDpAgAgAAUJWB0pCAB3AQAAAA==.Sharko:BAABLgAECn8cAAQEAAgJExeSDwDMAQAEAAcJzhWSDwDMAQAFAAUJhBkxqQApAQAkAAIJwgOQiwBPAAAAAA==.Sharvalee:BAAALgAECgUJBQAAAA==.Shibui:BAABLgAECn9WAAQiAAkJ6RrtCgB5AgAiAAkJ6RrtCgB5AgAKAAcJvAYvowDNAAAmAAQJQQ6RHQCvAAAAAA==.Shifthead:BAAALgAFFAEJAQABLgAFFAUJBQAJAMIFAA==.Shiggles:BAABLgAECn8iAAIIAAkJEBp+KABfAgAIAAkJEBp+KABfAgABLgAFFAIJCAAFANQcAA==.Shinhaein:BAABLgAECn8jAAILAAgJ0BMIDAAvAQALAAgJ0BMIDAAvAQABLgAFFAYJHAAIAN4VAA==.Shinxu:BAAALgADCgQJBAAAAA==.Shizmael:BAABLgAECn8VAAILAAYJXQknEwDaAAALAAYJXQknEwDaAAAAAA==.Shockazilla:BAABLgAECn83AAMkAAkJbR7fCAD9AgAkAAkJbR7fCAD9AgAFAAMJVw+z/wCWAAAAAA==.Shreddarfort:BAAALgADCgkJFQAAAA==.Shönuff:BAAALgAECgEJAQAAAA==.',
Si='Sigh:BAAALgAFFAEJAQAAAA==.Silverhorn:BAABLgAECn8pAAIFAAcJFx3XTQDeAQAFAAcJFx3XTQDeAQAAAA==.',
Sk='Skoduh:BAABLgAECn8kAAIGAAkJWhoRVACnAQAGAAkJWhoRVACnAQAAAA==.Skyelene:BAABLgAECn8uAAMSAAkJyhZiFwAqAgASAAkJyhZiFwAqAgARAAcJvwa+egDvAAAAAA==.',
Sl='Slaanesh:BAABLgAECn8hAAQHAAkJ3RZaDAB5AQAZAAcJNBK9TQCxAQAHAAcJOBZaDAB5AQAYAAMJlhsqFwDFAAAAAA==.Sluggo:BAABLgAFFH8HAAIFAAUJzxFGLABdAQAFAAUJzxFGLABdAQAAAA==.Sluggoboyce:BAACLgAFFH8GAAICAAQJhgR9EwAHAQACAAQJhgR9EwAHAQAuAAQKfyIAAwIACAkLGSEcAEcCAAIACAnYGCEcAEcCAAYABAmEDS6aAJ8AAAAA.',
Sm='Smeagosses:BAAALgAECgEJAQAAAA==.Smokeü:BAAALgAECgcJBwAAAA==.',
So='Solace:BAABLgAECn8kAAIKAAkJhx/NAQAsAgAKAAkJhx/NAQAsAgAAAA==.Solinaara:BAAALgAECgQJBAAAAA==.Soraka:BAABLgAFFH8LAAIUAAQJnQpWKwD2AAAUAAQJnQpWKwD2AAAAAA==.Soulstoner:BAAALgAECgEJAwAAAA==.',
Sp='Spiralist:BAABLgAECn8dAAQVAAkJ4xajTgBUAQAVAAgJfBWjTgBUAQAXAAYJARm6NwA2AQAaAAIJkAwIQwBVAAAAAA==.Spiralmist:BAAALgADCgUJBQAAAA==.Spiritdragon:BAAALgAECgEJAQAAAA==.',
St='Starge:BAAALgAECgUJBQAAAA==.Steelforged:BAAALgADCgkJEAABLgAECggJFwAeAJQTAA==.Stico:BAAALgAECgIJAQAAAA==.Stonedalways:BAABLgAECn8iAAMRAAkJGxAyPwCxAQARAAgJphAyPwCxAQASAAQJmgWDiwBZAAAAAA==.',
Su='Sunfuri:BAABLgAECn85AAIhAAkJDQo0NgBvAQAhAAkJDQo0NgBvAQAAAA==.Sunjan:BAAALgAECgQJBwAAAA==.Sus:BAACLgAFFH8hAAIiAAcJ7RtyAwABAgAiAAcJ7RtyAwABAgAuAAQKfyUAAiIACQmXI5cDAEcDACIACQmXI5cDAEcDAAAA.Susanoo:BAABLgAECn8bAAIhAAkJihdpJADRAQAhAAkJihdpJADRAQAAAA==.',
Sy='Sylvíadne:BAAALgAECgYJBgAAAA==.',
Sz='Szul:BAAALgADCgcJDAAAAA==.',
Ta='Taalia:BAAALgAECgUJCQABLgAECgkJJAAVABoIAA==.Tachima:BAAALgAECgcJEAABLgAECgkJLgAKADMiAA==.Tactics:BAAALgADCgcJDAAAAA==.Tahitimango:BAABLgAECn8pAAIKAAcJXQRT0gCPAAAKAAcJXQRT0gCPAAAAAA==.Takeko:BAAALgADCgcJDgABLgAECggJFgAIAHMTAA==.Talanas:BAAALgADCgcJBwAAAA==.Taleria:BAAALgADCgYJIgAAAA==.Taranad:BAAALgAECgcJDAAAAA==.Tarathor:BAABLgAECn8pAAIXAAkJuBr1AQDUAQAXAAkJuBr1AQDUAQAAAA==.Tarn:BAAALgAECgEJAQAAAA==.Tasha:BAAALgAECgEJAwABLgAECggJHwAhAO8UAA==.Tauroctony:BAABLgAECn8eAAIQAAgJKiGhBACiAgAQAAgJKiGhBACiAgAAAA==.',
Te='Tea:BAABLgAECn8XAAMbAAgJKgzEIQAiAQAbAAgJKgzEIQAiAQAhAAUJFAQhfgB9AAABLgAECgkJRQAOAPYfAA==.Teknofarious:BAAALgAECgEJBAAAAA==.Tenom:BAAALgAECgUJCgAAAA==.',
Th='Thalar:BAAALgAECgIJAgAAAA==.Thaumas:BAAALgADCgEJAQAAAA==.Thelsyn:BAAALgAECgIJAgABLgAECgkJQAABAEUYAA==.Thermite:BAAALgAECgYJBgAAAA==.Thesafe:BAAALgAECgMJBAAAAA==.Thialaa:BAAALgAECgEJAwABLgAECgkJSgAGANEkAA==.Thialia:BAAALgAECgkJEwABLgAECgkJSgAGANEkAA==.Thialiaa:BAAALgAECgYJBwABLgAECgkJSgAGANEkAA==.Thoralon:BAAALgADCgEJAQAAAA==.Thorey:BAAALgAECgEJAQAAAA==.Thornbreaker:BAAALgADCgEJAQAAAA==.Thorthunda:BAAALgAECgQJBgAAAA==.',
Ti='Tinkabella:BAABLgAECn87AAIUAAkJLiNoAgCSAwAUAAkJLiNoAgCSAwAAAA==.Tizl:BAEALgAECgUJBQABLgAFFAYJFQAIAEgdAA==.',
Tm='Tmgwolf:BAAALgAECgEJAQAAAA==.',
To='Tobi:BAAALgADCgQJBAAAAA==.Tobiblindpaw:BAAALgAECgYJDwAAAA==.Tobinir:BAAALgADCgkJCQAAAA==.Toenailjuice:BAAALgADCgUJBQABLgAECgkJOwAWAKkjAA==.Togo:BAAALgAECgYJBgAAAA==.Torrey:BAABLgAECn8YAAIkAAgJHyVuAwA8AwAkAAgJHyVuAwA8AwAAAA==.Tovarek:BAAALgADCgkJCwAAAA==.',
Tr='Trema:BAAALgAECgUJBwAAAA==.Trix:BAABLgAECn8vAAIRAAgJHw1pWABVAQARAAgJHw1pWABVAQAAAA==.Trounces:BAABLgAECn8gAAIlAAcJtRnnAgBfAQAlAAcJtRnnAgBfAQAAAA==.Truesmoke:BAAALgAECgEJAQAAAA==.',
Tu='Tulsami:BAAALgAECgIJAwAAAA==.Tulsi:BAABLgAECn88AAIoAAkJYyS0AAA+AwAoAAkJYyS0AAA+AwAAAA==.Tuskoo:BAAALgAECgcJEQAAAA==.',
Ty='Tyrathion:BAAALgAECgMJAwAAAA==.Tyronos:BAABLgAECn8hAAIFAAkJQxkNLQBMAgAFAAkJQxkNLQBMAgAAAA==.',
Uk='Uknôwnforce:BAAALgAECgMJBAAAAA==.',
Un='Unbeetable:BAAALgADCgUJBQAAAA==.',
Va='Vaeltharion:BAAALgADCgEJAQAAAA==.Valanoth:BAABLgAECn8jAAIKAAgJ1SBiHQBkAgAKAAgJ1SBiHQBkAgAAAA==.Valdr:BAABLgAECn8hAAMlAAkJchPRIgDEAQAlAAkJchPRIgDEAQANAAQJowzXKQDQAAAAAA==.Valoryck:BAAALgAECgQJDQABLgAECggJIwAKANUgAA==.Vas:BAAALgAECgQJCgAAAA==.',
Ve='Velielina:BAAALgAECgEJAQAAAA==.Velistos:BAAALgADCgEJAQAAAA==.Vellandrias:BAAALgADCgYJBgAAAA==.Verinda:BAAALgADCgcJDwAAAA==.Vessara:BAAALgAECgEJAQABLgAFFAYJEQAQAAkTAA==.Vevicenth:BAAALgAECgkJEwAAAA==.',
Vo='Voodoolily:BAAALgAECgUJBwAAAA==.Voranth:BAAALgAECgEJAQAAAA==.',
Wa='Warenio:BAAALgAECgUJBQAAAA==.Warpsbulge:BAACLgAFFH8gAAILAAcJ2x1lCgDMAQALAAcJ2x1lCgDMAQAuAAQKfxsAAwsACQlNIb4hAOwCAAsACQlNIb4hAOwCACAAAgl2FLQTAIoAAAAA.',
Wh='Whakan:BAAALgAECgEJAgABLgAECgcJIQAjANUXAA==.',
Wo='Wolfos:BAABLgAECn8fAAIQAAkJEiaSAABwAwAQAAkJEiaSAABwAwAAAA==.',
Wt='Wtfox:BAEBLgAECn8dAAMTAAgJ5xHPBgDuAAATAAgJ5xHPBgDuAAAUAAQJZQJUdAA/AAABLgAECgkJNQASAJMbAA==.',
Wu='Wulfgange:BAAALgADCgEJAQAAAA==.',
Wy='Wysteri:BAABLgAECn8WAAIKAAcJLhLsZgBYAQAKAAcJLhLsZgBYAQAAAA==.',
Xa='Xadrai:BAAALgADCgIJAgAAAA==.Xakeko:BAABLgAECn8WAAQIAAgJcxO1rgAWAQAIAAUJsxO1rgAWAQAJAAUJlRCXHgDYAAAjAAIJ+BZpDQBBAAAAAA==.Xalatos:BAAALgAECgEJAgAAAA==.Xalfein:BAAALgAECgQJBQAAAA==.',
Xi='Xinu:BAAALgAECgcJBwABLgAECgkJRQAGANogAA==.',
Ya='Yanakana:BAAALgAECgcJCwAAAA==.',
Yd='Ydalise:BAAALgAECgEJAgAAAA==.Ydrassil:BAABLgAECn8VAAIQAAkJcxpuCQBTAgAQAAkJcxpuCQBTAgABLgAFFAMJCAAbAJMbAA==.',
Yi='Yitsuni:BAAALgAECgcJDQAAAA==.',
Za='Zakeko:BAAALgAECgMJBgABLgAECggJFgAIAHMTAA==.Zalaeda:BAAALgAECgEJAQAAAA==.Zalena:BAAALgAECgQJCAAAAA==.Zatriani:BAAALgAECgYJCgAAAA==.',
Ze='Zenus:BAABLgAECn8iAAMGAAgJsxWAVACmAQAGAAgJsxWAVACmAQACAAMJqwevNwBAAAAAAA==.Zerina:BAAALgADCgUJBQAAAA==.Zesty:BAAALgADCgMJAwAAAA==.Zeusal:BAABLgAECn8hAAIXAAcJjQ+VNgA8AQAXAAcJjQ+VNgA8AQAAAA==.Zeusinator:BAABLgAECn8sAAIGAAkJzxnyIwBTAgAGAAkJzxnyIwBTAgAAAA==.',
Zi='Zinu:BAABLgAECn9FAAIGAAkJ2iDrEwCzAgAGAAkJ2iDrEwCzAgAAAA==.Zivalisse:BAAALgAECgUJCAAAAA==.',
Zu='Zulfionn:BAABLgAECn8oAAIGAAkJYApUWQCYAQAGAAkJYApUWQCYAQAAAA==.',
Zy='Zylah:BAAALgADCgEJAQAAAA==.',
['Áy']='Áyrá:BAABLgAECn8uAAIkAAkJGxujGABCAgAkAAkJGxujGABCAgAAAA==.',
['Åp']='Åpollyon:BAAALgAECgYJBwAAAA==.',
['Øu']='Øuroboros:BAABLgAECn8lAAQMAAgJvxnNCwAbAgAMAAcJyxrNCwAbAgANAAYJ5hp8FAChAQAlAAQJ1heQRQDHAAAAAA==.',
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
