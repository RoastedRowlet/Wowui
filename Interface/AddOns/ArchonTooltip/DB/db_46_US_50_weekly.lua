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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Devourer','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Monk-Brewmaster','Unknown-Unknown','Druid-Guardian','Shaman-Restoration','Shaman-Elemental','Priest-Shadow','Priest-Discipline','Druid-Restoration','Monk-Mistweaver','Druid-Balance','Warlock-Affliction','Warlock-Demonology','Druid-Feral','Warrior-Protection','Warrior-Arms','Monk-Windwalker','Shaman-Enhancement','Mage-Arcane','Warrior-Fury','DemonHunter-Havoc','DeathKnight-Blood','Paladin-Holy','Evoker-Augmentation','DemonHunter-Vengeance','Mage-Fire','Rogue-Assassination',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abelene:BAAALgAECgQJBAAAAA==.Abrâham:BAAALgADCgUJBQAAAA==.',
Ac='Achelis:BAABLgAECn86AAMBAAkJ8CVZAQBUAwABAAkJ8CVZAQBUAwACAAEJAABJggA/AAAAAA==.',
Ad='Adianitefall:BAAALgAECgUJBgAAAA==.Adorian:BAABLgAECn8nAAIDAAkJMgoCCADRAAADAAkJMgoCCADRAAAAAA==.Adros:BAABLgAECn8oAAMEAAgJQRQMFQB+AQAEAAgJQRQMFQB+AQAFAAEJHwS4wgEiAAAAAA==.Adrrel:BAAALgADCgIJAgABLgAFFAgJIQAGAGQYAA==.Adrrelle:BAACLgAFFH8hAAQGAAgJZBjHGwCXAQAGAAYJbRzHGwCXAQABAAQJWg9lFAAqAQACAAYJaw1aEgAWAQAuAAQKfyUABAIACQncHXcTAJkCAAIACAmXH3cTAJkCAAEABAnaF7I7AOIAAAYAAwmpEW64AFIAAAAA.',
Ae='Aelon:BAABLgAECn8cAAIFAAgJxgeTrwAkAQAFAAgJxgeTrwAkAQAAAA==.',
Ah='Aheiro:BAAALgAECgQJCQAAAA==.',
Ai='Ailaith:BAABLgAECn9KAAIGAAkJ0STUAwBTAwAGAAkJ0STUAwBTAwAAAA==.',
Ak='Akariliselle:BAABLgAECn8YAAIHAAcJlBsYCgCkAQAHAAcJlBsYCgCkAQAAAA==.Akarue:BAAALgAECgQJBAAAAA==.Akibafaris:BAABLgAECn8kAAMIAAkJsx6ZAgC7AgAIAAkJsx6ZAgC7AgAJAAEJCxONOAA7AAAAAA==.Aknologia:BAAALgAECgUJDQAAAA==.',
Al='Al:BAAALgADCggJCAAAAA==.Alan:BAAALgAECgUJCQAAAA==.Alarielle:BAAALgADCgkJEwAAAA==.Alcun:BAAALgAECgIJAwAAAA==.Aldora:BAAALgADCgkJDAAAAA==.Alen:BAAALgAECgEJAgAAAA==.Alirik:BAAALgADCgQJCQAAAA==.Alleriah:BAAALgAECgcJCAABLgAECggJIwAKANUgAA==.Alon:BAAALgAECgIJAgAAAA==.Alydrostage:BAABLgAECn8qAAILAAkJhwhnoAA6AQALAAkJhwhnoAA6AQAAAA==.Alystriaz:BAABLgAECn8oAAMMAAkJPxpABgCkAgAMAAkJPxpABgCkAgANAAEJsQWEKQAoAAAAAA==.Alzheimerz:BAAALgAECgUJBQAAAA==.',
Am='Amaelalin:BAABLgAECn9FAAIOAAkJ9h+vBAA1AwAOAAkJ9h+vBAA1AwAAAA==.Amaribo:BAAALgAECgEJAQABLgAFFAYJHAAPAHsmAA==.Ameliya:BAAALgAECgIJAgAAAA==.Ameng:BAAALgAECgQJBgAAAA==.',
An='Ananiel:BAAALgAECgEJAQABLgAECgIJAgAQAAAAAA==.Anaralestra:BAAALgAFFAEJAgABLgAFFAYJEQARAAkTAA==.Anaralyth:BAAALgAECgYJCAABLgAFFAYJEQARAAkTAA==.Andaya:BAACLgAFFH8cAAMSAAYJqB8ZFwCtAQASAAYJqB8ZFwCtAQATAAEJnwNjYAAtAAAuAAQKfyMAAxIACQmrGac8ALwBABIACQmrGac8ALwBABMAAgndDAaGAGQAAAAA.Andemeli:BAABLgAECn8qAAIFAAgJsg8aEQAoAQAFAAgJsg8aEQAoAQAAAA==.Andevyn:BAAALgAECgQJBAABLgAECggJIwAKANUgAA==.Aninja:BAEALgADCgQJBAABLgAFFAYJFQAIAEgdAA==.Anivia:BAABLgAECn8gAAILAAkJ4xLUVgDZAQALAAkJ4xLUVgDZAQAAAA==.Ankoubailith:BAAALgAECgQJBgAAAA==.',
Ap='Apollon:BAAALgADCgIJAwAAAA==.',
Ar='Arandis:BAABLgAECn8kAAMUAAgJawwQQwADAQAUAAYJXA4QQwADAQAVAAQJkQjdVwChAAAAAA==.Arch:BAAALgAECgUJBgAAAA==.Arcianna:BAABLgAECn8yAAMRAAkJ2B2EBgCVAgARAAkJ2B2EBgCVAgAWAAEJQRHf0wAxAAAAAA==.Arctica:BAABLgAECn8gAAILAAYJEQ6aFwDwAAALAAYJEQ6aFwDwAAAAAA==.Arctiq:BAAALgADCgUJCgAAAA==.Arctîc:BAABLgAECn8qAAILAAkJFhPRUgDkAQALAAkJFhPRUgDkAQAAAA==.Arjurn:BAABLgAECn87AAILAAkJByBaFADfAgALAAkJByBaFADfAgAAAA==.Arkro:BAAALgAECgMJBAAAAA==.Armpitbutter:BAABLgAECn87AAIXAAkJqSMJBAB1AwAXAAkJqSMJBAB1AwAAAA==.Artymiss:BAABLgAECn8eAAMYAAkJ4RFuIgC2AQAYAAkJ4RFuIgC2AQAWAAYJmRNLVgBQAQAAAA==.',
As='Asherah:BAABLgAECn8qAAQZAAgJHwr0FQAbAQAZAAcJZgn0FQAbAQAaAAcJugFo9AB5AAAHAAIJtA66CgBcAAAAAA==.Ashireita:BAAALgAECgYJEAABLgAECgkJLgATAMoWAA==.Ashwadawnguh:BAAALgAECgEJAQAAAA==.Astraleth:BAACLgAFFH8RAAQRAAYJCRMyHACvAAAYAAMJqxVRLgDNAAARAAUJmQsyHACvAAAWAAEJcwJVcwAzAAAuAAQKfx4AAxEACQmwGgISANABABEABwkaFwISANABABgABwkBGrkKAM0AAAAA.',
At='Atama:BAAALgAECgQJBwAAAA==.Atharius:BAAALgADCgEJAQAAAA==.',
Au='Aurturious:BAAALgAECgUJBQAAAA==.Authority:BAAALgAECgMJAwAAAA==.Autry:BAABLgAECn8xAAMbAAkJ1g9tEACwAQAbAAkJ1g9tEACwAQAWAAgJUgpZUwBCAQAAAA==.',
Av='Avelina:BAAALgADCgkJFAAAAA==.Avocat:BAABLgAECn8uAAIGAAkJiRsjFwCcAgAGAAkJiRsjFwCcAgAAAA==.',
Ay='Ayrilia:BAAALgAECgYJCAABLgAFFAYJEQARAAkTAA==.Ayshama:BAAALgAECgYJEQAAAA==.',
Az='Azeria:BAAALgAECgUJCQABLgAFFAgJEwAcABceAA==.Azetbur:BAAALgAECgQJBAAAAA==.Azshura:BAAALgAECgYJBwAAAA==.Azzinôth:BAAALgADCgcJBwABLgAECgEJAgAQAAAAAA==.',
Ba='Baekr:BAAALgAECgYJEAAAAA==.Baldr:BAABLgAECn8wAAIFAAkJKhM+TQDfAQAFAAkJKhM+TQDfAQAAAA==.Balgar:BAABLgAECn8aAAMGAAkJeCP7JABPAgAGAAkJeCP7JABPAgACAAUJyxm3PgBgAQAAAA==.Balghas:BAABLgAECn8kAAIFAAgJ1hzQMwBTAgAFAAgJ1hzQMwBTAgAAAA==.Bamz:BAAALgAFFAEJAQABLgAFFAYJHQAUAO4ZAA==.Bamzhurt:BAABLgAFFH8FAAIdAAMJZxGcJgDTAAAdAAMJZxGcJgDTAAABLgAFFAYJHQAUAO4ZAA==.Baumstrum:BAAALgAECgYJDQAAAA==.',
Be='Bearlydrae:BAAALgAECgMJBAAAAA==.Beezlbubba:BAAALgAECgYJDwAAAA==.Beldam:BAAALgADCgYJBgAAAA==.Belispeak:BAAALgADCgYJBgAAAA==.Bellaboom:BAAALgADCgYJBgAAAA==.Belvkara:BAAALgADCgkJCQAAAA==.Benedictoe:BAAALgADCgYJBgAAAA==.',
Bh='Bhozok:BAABLgAECn83AAIbAAkJvBI/DgDSAQAbAAkJvBI/DgDSAQAAAA==.',
Bi='Bint:BAAALgAECgEJAQAAAA==.',
Bl='Bloodpromise:BAAALgADCgMJAwAAAA==.Bloodrayvn:BAABLgAECn8wAAIGAAkJxR18GACUAgAGAAkJxR18GACUAgAAAA==.',
Bo='Boomchick:BAAALgAECgMJAwABLgAECgkJIAAGAOAdAA==.Boomparapara:BAACLgAFFH8QAAILAAQJ3xf0TQBDAQALAAQJ3xf0TQBDAQAuAAQKfycAAgsACQl9IKURAPACAAsACQl9IKURAPACAAAA.Borrkbuster:BAAALgAECgQJBAAAAA==.Bosta:BAAALgAECgUJEQAAAA==.Botkin:BAAALgADCgEJAQAAAA==.Bowan:BAAALgAECgEJAQAAAA==.',
Br='Bradley:BAAALgAECgYJDgABLgAECggJGAAOAMogAA==.Brandywyne:BAAALgADCgEJAQAAAA==.Brenri:BAABLgAECn8eAAITAAkJwgPEVgDgAAATAAkJwgPEVgDgAAAAAA==.Brew:BAABLgAECn8mAAMPAAkJ4BrzEwAQAgAPAAkJ4BrzEwAQAgAeAAEJ0Q0LfQAzAAAAAA==.Brewtality:BAABLgAFFH8JAAIXAAQJChiJFQAPAQAXAAQJChiJFQAPAQABLgAFFAIJCAAWANUSAA==.Brkat:BAAALgAECgIJAgAAAA==.Brughe:BAABLgAECn8tAAIGAAkJlw4TZAB9AQAGAAkJlw4TZAB9AQAAAA==.',
Bu='Bubbleoseven:BAAALgADCgYJBgABLgAFFAIJCAAWANUSAA==.Burntbum:BAAALgAECgYJBwAAAA==.Buttacutta:BAAALgADCgkJRgAAAA==.',
['Bä']='Bäné:BAAALgADCgIJAgAAAA==.',
Ca='Cairn:BAAALgADCgUJBQAAAA==.Camaracy:BAAALgAECgYJDQAAAA==.Caneste:BAACLgAFFH8QAAIUAAYJqhm2DwBwAQAUAAYJqhm2DwBwAQAuAAQKfx8AAhQACQm9HfcLAMMCABQACQm9HfcLAMMCAAAA.Capela:BAAALgADCgEJAQAAAA==.Capparelli:BAAALgADCgEJAQAAAA==.Cashoe:BAAALgADCgMJAwAAAA==.Catscan:BAACLgAFFH8IAAIWAAIJ1RJcHgBsAAAWAAIJ1RJcHgBsAAAuAAQKfyIAAhYACQniHV0OAOUCABYACQniHV0OAOUCAAAA.Catty:BAABLgAECn8wAAIbAAkJ/BeDCABEAgAbAAkJ/BeDCABEAgAAAA==.',
Cb='Cblock:BAAALgAECgUJBQABLgAFFAMJCgAfANAIAA==.',
Ce='Celeano:BAAALgADCgkJCQABLgAECgQJBAAQAAAAAA==.Celestyl:BAABLgAECn8xAAIgAAkJ6wy4BQB2AQAgAAkJ6wy4BQB2AQAAAA==.',
Ch='Charazard:BAAALgAECgUJCgABLgAECggJJQAMAL8ZAA==.Charming:BAAALgADCgMJAwAAAA==.Cheapbeer:BAABLgAECn8VAAIFAAkJVgir2ADnAAAFAAkJVgir2ADnAAAAAA==.Cheesehead:BAAALgADCggJEgAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chiforged:BAABLgAECn8XAAIeAAgJlBOSBwDkAAAeAAgJlBOSBwDkAAAAAA==.Chillybovine:BAABLgAECn8bAAILAAcJCQqUsAAgAQALAAcJCQqUsAAgAQAAAA==.Choppa:BAABLgAFFH8GAAIPAAMJpRcWDgDXAAAPAAMJpRcWDgDXAAAAAA==.Chromstrasza:BAABLgAECn8ZAAINAAcJHxjBCQCJAQANAAcJHxjBCQCJAQAAAA==.Chudderly:BAAALgADCgEJAgAAAA==.Chudders:BAAALgADCgIJAgAAAA==.',
Ci='Cirice:BAAALgAECgEJBgAAAA==.Citrouille:BAAALgAECgEJAgAAAA==.',
Cl='Clarence:BAAALgADCgIJAgABLgAFFAkJKgAaAMkXAA==.Clonazepam:BAAALgAECgUJDgABLgAECgkJJwADADIKAA==.',
Co='Comitus:BAABLgAECn9JAAMdAAkJBhBlFwCgAQAdAAkJBhBlFwCgAQAhAAQJawVjgwCxAAAAAA==.Conjar:BAAALgAECgIJAgAAAA==.Conjarr:BAABLgAECn8zAAIOAAkJHRzJAwC3AQAOAAkJHRzJAwC3AQAAAA==.Cortisol:BAAALgADCgIJAgAAAA==.Corven:BAAALgAECgUJDAAAAA==.Corvinus:BAAALgAECgQJBAAAAA==.Cougardk:BAAALgAECgIJAgAAAA==.Cougarshammy:BAAALgAECgEJAQAAAA==.Cougarsixsix:BAABLgAECn8oAAIEAAkJYBrSAgCNAQAEAAkJYBrSAgCNAQAAAA==.Cougarwar:BAAALgAECgUJCwAAAA==.',
Cr='Crashnburn:BAAALgADCgcJDQAAAA==.Crazyoldbear:BAABLgAECn8eAAIcAAkJmCPuAwDuAgAcAAkJmCPuAwDuAgAAAA==.Creideam:BAAALgADCgkJBwAAAA==.Crimos:BAABLgAECn8wAAIIAAkJzRbsQAAAAgAIAAkJzRbsQAAAAgAAAA==.Crystalliney:BAAALgADCgYJBgABLgAFFAYJHAAPAHsmAA==.',
Cy='Cynnai:BAAALgADCgYJBgAAAA==.Cyrena:BAAALgAECgEJAQAAAA==.',
Da='Daerthor:BAABLgAECn8iAAIEAAkJOBo8CgAnAgAEAAkJOBo8CgAnAgAAAA==.Dalind:BAABLgAECn8mAAIWAAkJygi5DACuAAAWAAkJygi5DACuAAAAAA==.Dalora:BAAALgAECgEJAQAAAA==.Dalshiro:BAAALgAECgYJCQAAAA==.Damaclies:BAABLgAECn9aAAMaAAkJtBnhBQChAQAaAAgJkRfhBQChAQAHAAUJ/xgDGADiAAAAAA==.Damedolla:BAABLgAECn8fAAMKAAgJYQzDfwAgAQAKAAgJwwrDfwAgAQAiAAUJnw7EQAD3AAAAAA==.Dammerung:BAAALgAECgYJCAAAAA==.Darksyn:BAABLgAECn8fAAIHAAkJjw2BEgAiAQAHAAkJjw2BEgAiAQAAAA==.Darthbane:BAABLgAECn8VAAMIAAkJnAmRGgC7AAAJAAgJHgXbHADnAAAIAAQJZA6RGgC7AAAAAA==.Darthghidora:BAAALgADCgkJEQAAAA==.Darthstroyer:BAABLgAFFH8FAAQJAAUJwgUhGgC5AAAJAAMJjgYhGgC5AAAIAAEJXQMcFwE9AAAjAAEJAACBYwAAAAAAAA==.Darthyokai:BAAALgADCgMJAwAAAA==.Darude:BAAALgADCgcJEAAAAA==.Dashoka:BAAALgAECgEJAQAAAA==.Dattiffany:BAAALgAECgUJBQAAAA==.Dawnfist:BAAALgADCggJCAAAAA==.',
De='Deadstout:BAABLgAECn8VAAQJAAYJERzoAwAaAQAjAAQJqxxEIQBIAQAJAAYJphHoAwAaAQAIAAEJUQCrqgENAAAAAA==.Deathevan:BAAALgAECggJDgABLgAECgkJLgAKADMiAA==.Deepspace:BAABLgAECn8uAAIiAAkJeSaHAACLAwAiAAkJeSaHAACLAwAAAA==.Deezknots:BAAALgAECggJCAAAAA==.Deezus:BAAALgADCgMJAwAAAA==.Dejagauth:BAAALgAECgYJDwABLgAECggJJAAkAPchAA==.Dekkan:BAAALgAECgYJEAAAAA==.Demonedd:BAAALgADCgMJAgAAAA==.Demòn:BAAALgAECgEJAQAAAA==.Desdia:BAABLgAECn8iAAILAAgJ2BhNDwA+AQALAAgJ2BhNDwA+AQAAAA==.',
Di='Dia:BAAALgAECgQJBwAAAA==.Diabetes:BAABLgAFFH8VAAIXAAcJmRoTFwDFAQAXAAcJmRoTFwDFAQAAAA==.Diastolic:BAAALgADCgUJBQAAAA==.Didyoudie:BAAALgAECggJDgAAAA==.Diend:BAABLgAECn9UAAISAAkJgSTMAQCzAwASAAkJgSTMAQCzAwAAAA==.Dill:BAAALgAECgEJAQABLgAECgkJOgABAPAlAA==.Dillathis:BAAALgADCgEJAQAAAA==.Discord:BAAALgAECgQJBQABLgAFFAMJBAAQAAAAAA==.Dissonanita:BAABLgAECn8eAAIGAAgJwRJFDQBoAQAGAAgJwRJFDQBoAQAAAA==.',
Dj='Djthelock:BAABLgAECn8sAAMaAAkJuRb8NQABAgAaAAgJxBP8NQABAgAHAAQJDhhPHADEAAAAAA==.',
Do='Doctachris:BAAALgAECgEJAgAAAA==.Domodios:BAAALgADCgIJAgABLgAFFAMJBAAQAAAAAA==.Dormoon:BAABLgAECn8bAAMhAAgJnQ1/QQA/AQAhAAgJnQ1/QQA/AQAcAAEJIBH9VAAuAAAAAA==.',
Dr='Drac:BAAALgADCgYJCgAAAA==.Draeblade:BAAALgAECgUJBQAAAA==.Dragath:BAAALgAECgYJDgAAAA==.Drakur:BAAALgAECgYJCQAAAA==.Drbrad:BAABLgAECn8YAAQOAAgJyiB5FgAdAgAOAAcJjyJ5FgAdAgAUAAMJDhAdcQBgAAAVAAEJaBRQGgBEAAAAAA==.Dreadfangs:BAAALgADCgQJBQAAAA==.Druen:BAABLgAECn8yAAIbAAkJHB53BAC4AgAbAAkJHB53BAC4AgAAAA==.Drunkenpo:BAABLgAECn9QAAQPAAkJ5yH4BADzAgAPAAkJtSH4BADzAgAXAAUJ7hOeUQAoAQAeAAIJqCIQEQBgAAAAAA==.Drykin:BAAALgAECgYJCwAAAA==.Drïzl:BAEALgAECgMJAwABLgAFFAYJFQAIAEgdAA==.',
Du='Duckchow:BAAALgADCgYJBgAAAA==.Dugga:BAAALgADCgQJBAAAAA==.Duskmyre:BAABLgAECn8lAAIKAAkJbw0OWQB8AQAKAAkJbw0OWQB8AQAAAA==.',
Dw='Dwarfoo:BAABLgAECn8eAAMeAAkJCxeoPwABAQAeAAcJOBOoPwABAQAXAAYJRw4fFADIAAAAAA==.Dweñde:BAABLgAECn8nAAIaAAkJigrVYAB+AQAaAAkJigrVYAB+AQAAAA==.',
['Dë']='Dëthmetal:BAABLgAECn8UAAIIAAUJnQxfwgD/AAAIAAUJnQxfwgD/AAAAAA==.',
Ec='Ecthelion:BAAALgAECgYJCAAAAA==.',
Ed='Eddiemac:BAAALgAECgYJCgAAAA==.Eddrick:BAACLgAFFH8OAAIFAAQJuxr7GAAbAQAFAAQJuxr7GAAbAQAuAAQKf0EAAwUACQkwHxgEAFoCAAUACQkqHxgEAFoCAAQABQmtHrYFAPcAAAAA.Edoran:BAAALgADCggJCAAAAA==.Edrani:BAAALgAECgYJDgAAAA==.',
Ei='Eilethen:BAABLgAECn8nAAIZAAkJOxocBgAfAgAZAAkJOxocBgAfAgAAAA==.',
Ek='Ekassa:BAAALgADCgkJCQAAAA==.',
El='Elaína:BAAALgADCgMJAwABLgAFFAUJGQAZAMUSAA==.Elementoe:BAAALgADCgEJAQABLgADCgYJBgAQAAAAAA==.Elendil:BAAALgAECgMJAwAAAA==.Elissabethh:BAAALgAECgYJEAAAAA==.Elleryn:BAAALgAECgQJBAABLgAECgYJGQASALwXAA==.Elminstar:BAAALgADCgIJAgAAAA==.Elsore:BAAALgADCgEJAQABLgAECgcJEgAQAAAAAA==.Elêctra:BAAALgAECgEJAgABLgAFFAEJAQAQAAAAAA==.',
Em='Employee:BAABLgAECn8VAAIlAAgJ4wvCSAAIAQAlAAgJ4wvCSAAIAQAAAA==.',
En='Engo:BAABLgAECn9EAAMOAAkJdiRnAwBZAwAOAAkJdCNnAwBZAwAVAAkJ9BslCQDhAgAAAA==.',
Er='Eradrá:BAACLgAFFH8ZAAMZAAUJxRJKEQCFAAAaAAUJxRIfVQAcAQAZAAIJAQxKEQCFAAAuAAQKf1AAAxkACQmzHugAAA4DABkACQmsG+gAAA4DABoACQm9GDUiAFkCAAAA.Eragon:BAAALgAECggJDgAAAA==.Erastrasza:BAAALgADCgYJCQAAAA==.Eroza:BAAALgAECgUJBgAAAA==.Ersey:BAAALgAECgQJBAABLgAFFAMJBwAWAO8HAA==.Ersèlla:BAACLgAFFH8HAAIWAAMJ7wdATACMAAAWAAMJ7wdATACMAAAuAAQKfy4AAxYACQmMGHobAGoCABYACQmMGHobAGoCABgAAQnYBSqdACQAAAAA.Erysira:BAAALgADCgkJCQAAAA==.',
Et='Ethan:BAAALgAECgEJAgAAAQ==.',
Eu='Eureka:BAABLgAECn8gAAMEAAkJTB2ADgDbAQAEAAcJ1RyADgDbAQAFAAcJSRnuZQCkAQABLgAFFAMJBQARAMEQAA==.',
Ev='Evandra:BAABLgAECn8vAAISAAkJBRzGFgCTAgASAAkJBRzGFgCTAgAAAA==.Evanorah:BAABLgAECn8fAAMHAAkJ2QmHIgCcAAAHAAYJowWHIgCcAAAaAAkJtgmBFwCQAAAAAA==.',
Ex='Exïle:BAEALgAECgYJBgABLgAFFAYJFQAIAEgdAA==.',
Fa='Fabio:BAAALgADCgIJAgAAAA==.Faedeyeda:BAAALgAECgEJAgAAAA==.Faelithia:BAABLgAECn8WAAIOAAYJKA4PPQD/AAAOAAYJKA4PPQD/AAAAAA==.Fatalbrew:BAAALgAECgYJCwAAAA==.Fauxyalee:BAAALgADCgkJEgAAAA==.',
Fe='Feldush:BAAALgADCgYJBgABLgAECggJJQAMAL8ZAA==.Felforit:BAAALgADCgQJBAAAAA==.Felis:BAAALgAECgYJCgAAAA==.Felkardio:BAAALgAECgIJAgAAAA==.Feloth:BAAALgAECgUJDQAAAA==.Ferheim:BAAALgAECgYJEwAAAA==.Ferhold:BAAALgAECgEJAQAAAA==.Ferrovax:BAAALgADCgYJBgABLgAECgkJLgAKAPAZAA==.',
Fi='Fiddyone:BAABLgAECn8sAAMJAAkJySEoAwC+AgAJAAkJtCEoAwC+AgAIAAgJcR0pRQDzAQAAAA==.Figment:BAAALgADCgYJBgAAAA==.Fireburt:BAAALgADCgUJBQAAAA==.Fireslay:BAABLgAECn8YAAIkAAcJpBwHHgAmAgAkAAcJpBwHHgAmAgAAAA==.Fizzlegrin:BAAALgAECgIJAgAAAA==.',
Fl='Flarefly:BAAALgAECgEJAQAAAA==.Flaya:BAAALgAECgcJDAAAAA==.',
Fo='Fodurzin:BAABLgAECn8VAAIFAAUJDhBS0QDxAAAFAAUJDhBS0QDxAAABLgAECgYJEgAQAAAAAA==.Fonta:BAAALgAECgMJAwAAAA==.Fortuna:BAAALgADCggJCAABLgAECgkJIAAGAOAdAA==.Foxingtobi:BAAALgADCgIJAgAAAA==.',
Fr='Frojio:BAABLgAECn8zAAIJAAkJ4ByaBQBYAgAJAAkJ4ByaBQBYAgAAAA==.Frosten:BAAALgAECgEJAQAAAA==.',
Fu='Furenio:BAABLgAECn80AAIRAAkJ7xekDgD6AQARAAkJ7xekDgD6AQAAAA==.',
Fy='Fyyre:BAAALgAECgUJBwAAAA==.',
Ga='Gabaghoul:BAACLgAFFH8YAAIFAAUJFh3zKgBhAQAFAAUJFh3zKgBhAQAuAAQKfzEAAgUACQl3IHoZAKsCAAUACQl3IHoZAKsCAAAA.Gaff:BAAALgAECgkJEwAAAA==.Galeana:BAAALgAECgMJAwABLgAECgkJXQALAPAeAA==.Galvan:BAAALgAECgEJBAAAAA==.Gasheth:BAAALgAECgYJDQAAAA==.',
Ge='Gentyl:BAAALgAECgQJBgAAAA==.',
Gi='Giggleblast:BAAALgAECgIJAgAAAA==.',
Gl='Glizzydealer:BAAALgAECgEJAQAAAA==.',
Gr='Grauth:BAAALgADCgEJAQAAAA==.Graycen:BAAALgAECgUJCQAAAA==.Grido:BAAALgAECgIJAgAAAA==.Grimbrindral:BAABLgAECn8hAAMFAAcJ5hZDZAC5AQAFAAcJdBVDZAC5AQAEAAUJghrKFwBZAQAAAA==.Grimston:BAAALgADCgMJAwABLgAECgcJIQAFAOYWAA==.Gruzaxx:BAAALgADCgUJBQAAAA==.',
Gu='Gulishdaniel:BAABLgAFFH8GAAIZAAQJJQRRCQDlAAAZAAQJJQRRCQDlAAABLgAFFAYJEAAUAKoZAA==.',
Ha='Hadin:BAABLgAECn9NAAMLAAkJMCTGBgBKAwALAAkJMCTGBgBKAwAgAAMJqhysDwDHAAAAAA==.Hakeko:BAABLgAECn8ZAAIBAAkJoxcYAQBZAgABAAkJoxcYAQBZAgAAAA==.Halalnt:BAABLgAFFH8FAAIIAAIJixs9eABVAAAIAAIJixs9eABVAAAAAA==.Hanua:BAAALgADCgcJBwAAAA==.Haozhao:BAABLgAECn9NAAMRAAkJXRsuCQBYAgARAAkJXRsuCQBYAgAbAAEJDhQnTwA7AAAAAA==.Hawktuahz:BAAALgAECgMJAwAAAA==.Hazenpryde:BAABLgAECn8iAAIRAAkJuRkeEADnAQARAAkJuRkeEADnAQAAAA==.',
He='Hearsay:BAABLgAECn9EAAQFAAgJdREjcACOAQAFAAgJdREjcACOAQAkAAYJXwnZCQDQAAAEAAEJrgfPFQAcAAABLgAECgkJLAAWAHIUAA==.Helden:BAAALgAECgEJAQAAAA==.Hephaistian:BAAALgAECgYJBgAAAA==.Hespera:BAACLgAFFH8XAAMWAAYJPw9eJgApAQAWAAYJPw9eJgApAQAYAAMJ8whCOgCQAAAuAAQKfyMAAxYACQnJIOkYAHACABYACAmiIekYAHACABgAAwmnFP5SAMMAAAAA.',
Hi='Hirari:BAABLgAECn8dAAMkAAYJBCWUFwBMAgAkAAYJBCWUFwBMAgAFAAEJFBpjeQFCAAAAAA==.',
Ho='Hodoor:BAAALgAECgYJCAAAAA==.Horsebananas:BAAALgAECgQJBQABLgAECgkJQgABANwdAA==.Howlears:BAABLgAECn8qAAIUAAkJHQhOOwAlAQAUAAkJHQhOOwAlAQAAAA==.',
Hu='Hulud:BAABLgAECn8YAAMaAAkJfRbiSwC3AQAaAAkJfRbiSwC3AQAHAAEJAADYVAAAAAAAAA==.Husbando:BAAALgAECgMJAwAAAA==.Husey:BAAALgAECgMJBgAAAA==.',
Hy='Hydrangea:BAABLgAECn8dAAIFAAcJ4Q+VkQBPAQAFAAcJ4Q+VkQBPAQAAAA==.Hydrá:BAABLgAECn8aAAIaAAkJvRYCMQAUAgAaAAkJvRYCMQAUAgAAAA==.Hylan:BAAALgADCgUJBQAAAA==.Hysgar:BAAALgAECgYJBgABLgAECggJJAAkAPchAA==.',
Ic='Iceamaris:BAABLgAECn8gAAITAAkJYQv/OABTAQATAAkJYQv/OABTAQAAAA==.Icetiger:BAAALgAECgIJAwAAAA==.Icetigress:BAAALgAECgEJAQAAAA==.',
Ie='Iechu:BAABLgAECn8hAAMPAAgJbBFGIwCQAQAPAAgJbBFGIwCQAQAeAAIJ9QZujABFAAAAAA==.',
In='Innanna:BAAALgADCggJCgABLgAECgcJFgAKAC4SAA==.',
Is='Isoth:BAAALgAECgEJAQAAAA==.',
Iv='Ivern:BAACLgAFFH8VAAIWAAgJ+hGKCAByAgAWAAgJ+hGKCAByAgAuAAQKfx0AAxYABgkHHfgyANIBABYABgkHHfgyANIBABgAAgnRBzWXACkAAAAA.Ivysnow:BAAALgAECgEJAQAAAA==.',
Ja='Jac:BAAALgAECgMJAwABLgAFFAMJBAAQAAAAAA==.Jadenpryde:BAAALgAECgYJBgABLgAECgkJIgARALkZAA==.Jaod:BAAALgAECgQJAgAAAA==.Jarndal:BAAALgAECgEJAQAAAA==.Jasmirrae:BAAALgAECgEJAQAAAA==.',
Jd='Jdghoul:BAABLgAECn8ZAAQjAAkJURyUAgDjAQAjAAkJihuUAgDjAQAIAAUJZRBRHgClAAAJAAEJtwMJRAAdAAAAAA==.',
Ji='Jian:BAAALgADCgIJAgAAAA==.Jindrac:BAAALgAECgkJEQAAAA==.',
Jo='Jolton:BAAALgADCgYJBwABLgAECgkJLgAKADMiAA==.',
['Jà']='Jàcaranda:BAAALgAECgkJDwAAAA==.',
Ka='Kaedor:BAAALgAECgYJBwAAAA==.Kahnrah:BAAALgADCgkJDAAAAA==.Kalarae:BAAALgAECggJCQAAAA==.Kalarill:BAABLgAECn8eAAIFAAcJZR1rMAA/AgAFAAcJZR1rMAA/AgAAAA==.Kaljeer:BAAALgAECgYJCAAAAA==.Kalki:BAAALgAECgEJAQAAAA==.Kaltharion:BAABLgAFFH8IAAIMAAQJ6wNFEAB8AAAMAAQJ6wNFEAB8AAAAAA==.Kaluren:BAAALgAECgcJDwAAAA==.Kalurok:BAAALgAECgUJBQABLgAECgcJDwAQAAAAAA==.Kana:BAAALgAECgIJAgAAAA==.Kanade:BAABLgAECn9JAAQaAAkJBh7BFwCVAgAaAAgJ1R3BFwCVAgAZAAcJsRUACQDVAQAHAAQJWAsKTACJAAAAAA==.Kantong:BAABLgAECn8gAAIeAAgJdRmIGwDTAQAeAAgJdRmIGwDTAQAAAA==.Kapp:BAABLgAECn8UAAMhAAgJmwohWADuAAAhAAYJkAkhWADuAAAcAAIJNg0lEAA3AAAAAA==.Karabar:BAABLgAECn87AAMEAAkJ2yAYBQCjAgAEAAkJyh4YBQCjAgAFAAgJoyDzKABfAgAAAA==.Karnnaged:BAAALgADCgYJBwAAAA==.Kasarra:BAABLgAECn87AAIiAAkJFBeLAgDzAQAiAAkJFBeLAgDzAQAAAA==.Kazagol:BAABLgAECn87AAIKAAkJ+x2rGgB0AgAKAAkJ+x2rGgB0AgAAAA==.',
Ke='Kelintos:BAAALgAECgEJAgABLgAECgkJOAAKAD4cAA==.Keone:BAAALgADCgEJAQAAAA==.Kethysa:BAAALgADCgIJAgAAAA==.',
Kh='Khalla:BAAALgAFFAEJAQAAAA==.Khalli:BAAALgAFFAIJAgAAAA==.Khamaracy:BAABLgAECn8oAAMHAAkJlA3PAgBEAQAHAAkJlA3PAgBEAQAaAAEJsQE6ZQEbAAAAAA==.Khronni:BAAALgAECgYJCQAAAA==.Khrooze:BAAALgAECgYJEQAAAA==.',
Ki='Kidos:BAAALgAECgQJBgAAAA==.Kiljana:BAAALgAECgEJAQAAAA==.Kimahrí:BAABLgAECn8iAAIjAAkJmQnrCQCdAAAjAAkJmQnrCQCdAAAAAA==.Kitez:BAAALgAECgMJBgAAAA==.Kittei:BAABLgAECn87AAIRAAkJ1w+eGwBwAQARAAkJ1w+eGwBwAQAAAA==.',
Ko='Kojote:BAAALgADCgMJAQAAAA==.Kovalenko:BAAALgAECggJDgAAAA==.',
Kr='Krepow:BAAALgAECgcJCgAAAA==.',
Ku='Kuczej:BAAALgAECgIJAgAAAA==.Kurick:BAABLgAECn8kAAQkAAgJ9yEvCAAJAwAkAAgJ9yEvCAAJAwAEAAYJ1xr4AgCEAQAFAAMJLQxWfgE+AAAAAA==.Kurzul:BAAALgADCgEJAgAAAA==.Kusinluvin:BAAALgAECgEJAQAAAA==.',
Ky='Kyngizzard:BAABLgAECn8fAAILAAkJSRrUNwA5AgALAAkJSRrUNwA5AgABLgAFFAIJBQAIAIsbAA==.Kytherin:BAAALgAECgYJDAAAAA==.',
La='Lactase:BAAALgADCgMJAwAAAA==.Lainea:BAAALgAECgMJAQAAAA==.Langtry:BAAALgADCgcJBgAAAA==.Lanoree:BAABLgAECn8WAAQJAAkJfQDJRgAGAAAIAAYJMQAnrAEGAAAJAAkJfQDJRgAGAAAjAAIJAAAAAAAAAAAAAA==.Latte:BAAALgAECgcJCgAAAA==.',
Le='Leblanc:BAAALgAECgEJAQABLgAECgkJGAAFAEEeAA==.Leeli:BAAALgADCgcJBwAAAA==.Lenity:BAACLgAFFH8KAAIDAAIJSgumGwCMAAADAAIJSgumGwCMAAAuAAQKf1oAAgMACQkyGhUBAHYCAAMACQkyGhUBAHYCAAAA.Letty:BAAALgAECgQJCQAAAA==.',
Li='Liabelle:BAAALgADCgIJAgAAAA==.Lightsmite:BAAALgAECgIJAgAAAA==.Lilithene:BAAALgAECgUJBgABLgAECgkJLgATAMoWAA==.Lionbark:BAAALgADCgEJAQAAAA==.Lionell:BAAALgADCgUJBgAAAA==.Lithpally:BAAALgADCgEJAQAAAA==.Liubeijian:BAAALgADCgYJBgABLgAECgcJFgAKAC4SAA==.',
Lo='Loan:BAAALgAECgUJBQABLgAECgcJDgAQAAAAAA==.Lokinah:BAABLgAECn8gAAIGAAkJAQjBgAA9AQAGAAkJAQjBgAA9AQAAAA==.Loonytusk:BAAALgADCgQJBAAAAA==.Lorian:BAAALgADCgcJBwAAAA==.',
Lu='Lucifermadis:BAAALgAECgQJBgAAAA==.Lucoryphus:BAABLgAECn8kAAIjAAkJQhjYGQCQAQAjAAkJQhjYGQCQAQAAAA==.Lukeduke:BAABLgAFFH8TAAIcAAgJFx4ZBAAwAgAcAAgJFx4ZBAAwAgAAAA==.Luketheduke:BAACLgAFFH8ZAAMRAAYJgR5RBADGAQARAAUJgR5RBADGAQAbAAEJAAAIBwA3AAAuAAQKfyoAAxEACQkvJR8BAFcDABEACQkvJR8BAFcDABsABAmxFXscAAkBAAEuAAUUCAkTABwAFx4A.Lumilia:BAAALgADCgUJBQAAAA==.Lunaries:BAAALgAECgYJCgAAAA==.Lunä:BAACLgAFFH8MAAISAAMJ7R6yFgD/AAASAAMJ7R6yFgD/AAAuAAQKfygAAxIACQlUFmoiABACABIACQlUFmoiABACABMAAQmLEN0hADEAAAAA.',
Ly='Lydia:BAABLgAECn8pAAILAAkJphkzNABIAgALAAkJphkzNABIAgAAAA==.Lynnee:BAAALgADCgEJAQAAAA==.',
['Lô']='Lôckrocks:BAABLgAECn8ZAAIHAAcJxhGODwBHAQAHAAcJxhGODwBHAQAAAA==.',
['Lý']='Lýsendra:BAAALgADCggJCQAAAA==.',
Ma='Magickeys:BAAALgAFFAIJAgAAAA==.Magictomb:BAACLgAFFH8KAAMfAAMJ0AiIDABuAAAfAAMJ0AiIDABuAAATAAEJrgE5IQA7AAAuAAQKfzIABB8ACQlqFXAGAMoAABMACAmXFeU4AFMBABIABgnpDTd8AOsAAB8ABgm0DnAGAMoAAAAA.Mahdude:BAAALgAECgEJAwAAAA==.Malastor:BAAALgAECgEJAQABLgAFFAMJBAAQAAAAAA==.Malcontent:BAAALgAECgcJEQABLgAFFAMJBAAQAAAAAA==.Maldazane:BAAALgADCgYJCwAAAA==.Malfeasance:BAAALgAECgYJBgABLgAFFAMJBAAQAAAAAA==.Malidan:BAAALgADCgMJAwAAAA==.Malifel:BAABLgAECn8sAAMmAAkJsiDnAAAnAgAmAAkJsiDnAAAnAgAKAAYJ+BT6CQA0AQABLgAFFAMJBAAQAAAAAA==.Maliss:BAABLgAECn9AAAQBAAkJRRgcFAAEAgABAAkJahccFAAEAgACAAQJ8RHLIQCjAAAGAAEJoxETLwE3AAAAAA==.Mallord:BAAALgAFFAMJBAAAAA==.Mandarin:BAABLgAECn84AAIWAAkJ8hoNEwCzAgAWAAkJ8hoNEwCzAgAAAA==.Manmythlegnd:BAAALgADCgYJBgAAAA==.Mannik:BAABLgAECn8aAAIaAAgJrRmPMgAOAgAaAAgJrRmPMgAOAgAAAA==.Marashade:BAAALgAECgUJBQAAAA==.Marashades:BAAALgAECgUJBgABLgAECgkJHgAcAJgjAA==.Mathemagics:BAAALgAECgIJAgAAAA==.',
Mc='Mcbadden:BAAALgAECgYJCAAAAA==.',
Me='Meditatetoe:BAAALgADCgIJAgABLgADCgYJBgAQAAAAAA==.Melissà:BAAALgADCgMJAwAAAA==.Menesta:BAAALgADCgcJBwABLgAECgYJEgAQAAAAAA==.Mercia:BAABLgAECn8wAAIEAAkJExuDCQA3AgAEAAkJExuDCQA3AgAAAA==.Merekoma:BAABLgAECn8uAAMKAAkJ8BkOLQATAgAKAAkJrhUOLQATAgAmAAQJFhY8HQCxAAAAAA==.',
Mi='Milarra:BAABLgAECn8VAAInAAcJMAnaCAD9AAAnAAcJMAnaCAD9AAAAAA==.Milhouse:BAABLgAECn8fAAILAAcJNg3GHgC8AAALAAcJNg3GHgC8AAAAAA==.Minalan:BAAALgADCgYJCgABLgAECgYJEQAQAAAAAA==.Mingonashoba:BAABLgAECn8jAAIGAAkJYw69RgDNAQAGAAkJYw69RgDNAQAAAA==.Miragosa:BAABLgAECn8zAAMMAAkJUA+UDwDSAQAMAAkJUA+UDwDSAQANAAcJ3gg7EAAHAQAAAA==.Misschris:BAABLgAECn8tAAIXAAkJBA1zQABsAQAXAAkJBA1zQABsAQAAAA==.Mistycinamon:BAAALgAECgEJAQAAAA==.Mizu:BAAALgAECgUJBQAAAA==.',
Mo='Moadeed:BAABLgAECn8hAAMRAAkJ2RViEgDLAQARAAkJ0RViEgDLAQAYAAMJdA1iEAB5AAAAAA==.Mooluv:BAAALgADCgcJCgAAAA==.Moonstrike:BAAALgAECgIJAgAAAA==.Mordrius:BAAALgADCgYJBgAAAA==.Morphmious:BAAALgAECgcJBwAAAA==.Mortesque:BAAALgAECgcJEgAAAA==.',
Mu='Muttblitzed:BAABLgAECn8aAAIGAAgJnxZNTAC9AQAGAAgJnxZNTAC9AQAAAA==.Muttskî:BAAALgAECgMJAwAAAA==.',
My='Mybutt:BAAALgAECgMJBgAAAA==.Myroku:BAAALgADCgcJBwABLgAFFAMJBAAQAAAAAA==.Myrothos:BAAALgADCgEJAQAAAA==.Myrrh:BAABLgAECn8aAAMlAAgJSgk/DwBtAAANAAQJ9wYzLQCxAAAlAAgJnQg/DwBtAAAAAA==.Mysklef:BAAALgADCgMJAwABLgAECggJJAAkAPchAA==.Mythris:BAAALgAECgkJBQAAAA==.',
['Mí']='Místermage:BAAALgAECgQJCAAAAA==.',
Na='Nadrael:BAAALgAECgEJAwAAAA==.Nasturtium:BAAALgADCgYJDgAAAA==.Nausican:BAACLgAFFH8JAAIJAAMJbQnrDAC3AAAJAAMJbQnrDAC3AAAuAAQKf00AAgkACQkUHD0EAIsCAAkACQkUHD0EAIsCAAAA.Nazuhda:BAAALgADCgEJAQAAAA==.',
Ne='Necrosector:BAACLgAFFH8KAAIFAAUJAgoqVgADAQAFAAUJAgoqVgADAQAuAAQKfyYAAgUACAm5Gc9OANsBAAUACAm5Gc9OANsBAAAA.Necrotherys:BAABLgAECn84AAIKAAkJPhz0FwCGAgAKAAkJPhz0FwCGAgAAAA==.Nelandra:BAABLgAECn8lAAIUAAkJ1hxqFgAXAgAUAAkJ1hxqFgAXAgAAAA==.Net:BAAALgAECgEJAQABLgAECgcJDgAQAAAAAA==.Netherforged:BAAALgAECgMJAwAAAA==.',
Ni='Nicklaus:BAABLgAECn8oAAIDAAcJlglnLwAjAQADAAcJlglnLwAjAQAAAA==.Nilrem:BAAALgADCgIJAgAAAA==.Ninelives:BAAALgAECgYJDgAAAA==.Ninjadk:BAECLgAFFH8VAAMIAAYJSB1gUABRAQAIAAUJSB1gUABRAQAjAAEJAABVZQAAAAAuAAQKfzEAAwgACQmyIQAPAPQCAAgACQmyIQAPAPQCAAkAAQm4G6U3AD4AAAAA.',
No='Nocapongfrfr:BAAALgAECgMJAwABLgAFFAUJBQAJAMIFAA==.Nomahuata:BAACLgAFFH8JAAITAAMJ+goQGwCrAAATAAMJ+goQGwCrAAAuAAQKf00AAhMACQlmGXkVAD0CABMACQlmGXkVAD0CAAAA.Nordre:BAAALgAECgMJAwAAAA==.',
Nu='Nufrus:BAAALgAECgEJAQAAAA==.',
Ny='Nyeli:BAAALgAECgYJCwABLgAECgYJGQASALwXAA==.Nyxi:BAABLgAECn8eAAISAAkJDhjTIABKAgASAAkJDhjTIABKAgAAAA==.Nyxlee:BAAALgAECgcJBwAAAA==.',
['Né']='Néo:BAAALgAECgUJCAAAAA==.',
['Nó']='Nóóôööôòòpe:BAABLgAFFH8HAAIGAAQJpAbyWgDvAAAGAAQJpAbyWgDvAAABLgAFFAUJBQAJAMIFAA==.',
Og='Ogdruid:BAAALgADCgcJDgAAAA==.',
Ok='Okume:BAAALgAECgIJAgAAAA==.',
Ol='Olympian:BAAALgADCgcJBwAAAA==.',
Om='Omanyte:BAAALgADCgcJBwAAAA==.',
On='Onefiftyone:BAABLgAECn8bAAMfAAYJHCVGCgAVAgAfAAYJHCVGCgAVAgASAAIJnSQsigDHAAABLgAECgkJLAAJAMkhAA==.',
Or='Orruk:BAAALgADCgMJAwAAAA==.Orwyn:BAAALgAECgEJAQAAAA==.',
Ov='Overdose:BAAALgADCgMJAwAAAA==.',
Pa='Padmé:BAAALgAECgQJBgAAAA==.Pain:BAAALgAECgUJCwAAAA==.Palanas:BAAALgAFFAEJAQAAAA==.Pallamoo:BAAALgAECgcJCAAAAA==.Palochka:BAAALgAECggJCgAAAA==.Paradots:BAABLgAECn8WAAIMAAYJwBpqEgCiAQAMAAYJwBpqEgCiAQABLgAFFAIJCAAWANUSAA==.Paranitis:BAAALgAECggJDAAAAA==.Paranorm:BAAALgADCgEJAQAAAA==.Paraparaboom:BAAALgAECgUJBQABLgAFFAQJEAALAN8XAA==.',
Pe='Pezdormu:BAAALgADCgEJAQAAAA==.Pezmage:BAAALgAECgIJBAAAAA==.',
Ph='Phatboi:BAAALgAECgEJAwAAAA==.Pheroth:BAAALgAECgUJDQABLgAECgkJHwAHAI8NAA==.',
Pi='Pixydaddy:BAAALgAECgkJDwABLgAECgkJMgAKAN0aAA==.Pixystix:BAABLgAECn8yAAIKAAkJ3RprAgBEAgAKAAkJ3RprAgBEAgAAAA==.',
Po='Poisonspain:BAAALgAECgMJAwAAAA==.Popsdh:BAAALgAECggJEwABLgAFFAMJBQARAMEQAA==.Portlukk:BAAALgADCgEJAQABLgAFFAUJHAAGAPobAA==.Possibly:BAAALgAECgEJAQAAAA==.Potscold:BAACLgAFFH8SAAILAAkJ3BOGDAC5AQALAAkJ3BOGDAC5AQAuAAQKf0EAAgsACAnbJbsRAD0DAAsACAnbJbsRAD0DAAAA.Poxi:BAAALgAECgIJAgABLgAECggJGAALADwdAA==.',
Pr='Prion:BAABLgAECn8fAAIhAAgJ7xT5KQCwAQAhAAgJ7xT5KQCwAQAAAA==.',
Pu='Pull:BAABLgAECn8jAAIRAAkJnxssCgBFAgARAAkJnxssCgBFAgAAAA==.',
Ra='Radioshack:BAAALgADCggJCAAAAA==.Radkemonko:BAAALgAECgcJDwAAAA==.Raega:BAAALgADCgYJBgAAAA==.Raemon:BAAALgADCgUJBQAAAA==.Ragerlock:BAAALgADCgEJAQAAAA==.Raivel:BAABLgAECn8ZAAISAAYJvBf+RgCSAQASAAYJvBf+RgCSAQAAAA==.Raldaron:BAAALgADCgEJAQAAAA==.Rambogg:BAAALgAECgEJAQABLgAFFAgJHAALAOwOAA==.Randalthor:BAAALgAECgUJBQABLgAECgkJVwAiACcbAA==.Raneyth:BAAALgAECggJCAAAAA==.Ranith:BAAALgADCgMJAwAAAA==.Ravagèr:BAAALgAECgEJAgAAAA==.',
Rd='Rdbwarrior:BAAALgADCgUJBQAAAA==.',
Re='Redemus:BAAALgADCgEJAQAAAA==.Redwinetoast:BAABLgAECn8kAAIaAAkJUAWBkQAYAQAaAAkJUAWBkQAYAQAAAA==.Rekllaw:BAAALgAECgIJAgAAAA==.Reliala:BAAALgADCgkJEQAAAA==.Reno:BAAALgAECgcJDgAAAA==.Reshyk:BAABLgAECn8UAAIbAAkJQhyVCwACAgAbAAkJQhyVCwACAgAAAA==.Resles:BAAALgAECgEJAQAAAA==.Respectwomen:BAAALgADCgEJAQABLgAECgQJBAAQAAAAAA==.',
Rh='Rhobes:BAABLgAECn8bAAIhAAgJOxCDCwDjAAAhAAgJOxCDCwDjAAAAAA==.Rhondta:BAABLgAECn8nAAIaAAkJJRLrRQDJAQAaAAkJJRLrRQDJAQAAAA==.',
Ri='Rickormortis:BAABLgAECn8UAAIIAAkJGB1iHgCRAgAIAAkJGB1iHgCRAgABLgAECgkJLQAXAAQNAA==.Rictus:BAABLgAECn8wAAILAAkJjSSLCAA4AwALAAkJjSSLCAA4AwAAAA==.Ringmasterr:BAAALgADCgUJBQAAAA==.Riordaa:BAAALgADCgYJDAAAAA==.Risingdragon:BAABLgAECn8qAAIeAAcJMhOHLgBQAQAeAAcJMhOHLgBQAQAAAA==.',
Ro='Roades:BAAALgADCgcJDAAAAA==.Roboskritch:BAAALgADCgUJBQAAAA==.Ronaj:BAAALgADCgMJBAAAAA==.Rowene:BAAALgAECgIJAgAAAA==.Royveer:BAAALgADCgYJCQAAAA==.',
Ru='Rumor:BAABLgAECn8sAAUWAAkJchSxAwDUAQAWAAkJchSxAwDUAQAbAAcJvxTCEwCDAQARAAMJlwzmXABVAAAYAAIJdAkLgwBDAAAAAA==.Rurry:BAACLgAFFH8YAAIMAAYJpRe+BACuAQAMAAYJpRe+BACuAQAuAAQKfy4ABAwACQnIIrECAEADAAwACQnIIrECAEADAA0ABQm6GR4WAI8BACUAAwlVF/RGAL8AAAEuAAUUCAkVABYA+hEA.',
Ry='Ryumi:BAABLgAECn8uAAIKAAkJMyJbFwCKAgAKAAkJMyJbFwCKAgAAAA==.Ryur:BAAALgAECgQJDgAAAA==.Ryuuki:BAABLgAECn8dAAMIAAkJXR6GAgDBAgAIAAkJxh2GAgDBAgAjAAUJvBE9BwDeAAABLgAECgkJLgAKADMiAA==.',
Sa='Sabastion:BAAALgAECgYJBgABLgAFFAMJBAAQAAAAAA==.Sacrickficed:BAAALgAECgQJBAABLgAECgkJLQAXAAQNAA==.Sahwe:BAABLgAECn8UAAMWAAYJnwz/aQD2AAAWAAYJnwz/aQD2AAAYAAEJ0wcemAAoAAAAAA==.Salchicha:BAAALgADCgEJAQABLgAECgYJEgAQAAAAAA==.Salmoo:BAAALgAECgYJEgAAAA==.Salocar:BAAALgAECgcJEwAAAA==.Sanafela:BAAALgADCgkJXgAAAA==.Saphisha:BAABLgAECn8UAAIeAAgJVxcIIACtAQAeAAgJVxcIIACtAQAAAA==.Sarÿna:BAAALgADCgIJAgABLgAECgkJLAAWAHIUAA==.Sasora:BAAALgAECgUJCwAAAA==.Saucemagic:BAAALgAECgcJDQAAAA==.Savonah:BAAALgAECgUJBgAAAA==.',
Sc='Scaledaddy:BAABLgAECn8jAAIlAAkJug0HKgCYAQAlAAkJug0HKgCYAQAAAA==.Scalespawn:BAAALgADCgYJBgABLgAFFAgJHgAIAEwZAA==.Scaryl:BAABLgAECn8WAAIYAAgJAQmoCgDOAAAYAAgJAQmoCgDOAAAAAA==.Scourgespawn:BAACLgAFFH8eAAQIAAgJTBlWJADcAQAIAAYJJhtWJADcAQAJAAQJgxJzDAA3AQAjAAIJpwjBQwAnAAAuAAQKfyoAAwgACQmyIDMkAK0CAAgACQmyIDMkAK0CACMABAnhFXI5AK0AAAAA.',
Se='Searthenio:BAAALgAECggJCQAAAA==.Selenë:BAABLgAECn8fAAMOAAcJYhjkHQDWAQAOAAcJYhjkHQDWAQAUAAEJxwF/nAAWAAAAAA==.Sengoku:BAAALgAECgEJAQAAAA==.Seraz:BAAALgADCgkJCAAAAA==.Serbiscuit:BAAALgAECgUJDwAAAA==.Sereneya:BAAALgAECgYJCAAAAA==.Serenio:BAAALgAECgcJEQAAAA==.Serenval:BAAALgAECgUJBgAAAA==.',
Sh='Shadowshart:BAAALgAECgEJAQAAAA==.Shadus:BAAALgAECgUJBQAAAA==.Shadyaf:BAAALgAECgEJAQAAAA==.Shailora:BAAALgAECgQJAwAAAA==.Shait:BAAALgADCgYJBgAAAA==.Shalis:BAABLgAECn8sAAIGAAkJWxxzHAB6AgAGAAkJWxxzHAB6AgAAAA==.Shalora:BAAALgAECgQJBAAAAA==.Sharivee:BAABLgAECn8cAAMLAAkJ6SDgEgDpAgALAAkJuh/gEgDpAgAgAAUJWB0pCAB3AQAAAA==.Sharko:BAABLgAECn8cAAQEAAgJExeSDwDMAQAEAAcJzhWSDwDMAQAFAAUJhBkxqQApAQAkAAIJwgOQiwBPAAAAAA==.Sharvalee:BAAALgAECgUJBQAAAA==.Shibui:BAABLgAECn9XAAQiAAkJJxvtCgB5AgAiAAkJJxvtCgB5AgAKAAcJvAYvowDNAAAmAAQJQQ6RHQCvAAAAAA==.Shifthead:BAAALgAFFAEJAQABLgAFFAUJBQAJAMIFAA==.Shiggles:BAABLgAECn8iAAIIAAkJEBp+KABfAgAIAAkJEBp+KABfAgABLgAFFAIJCAAFANQcAA==.Shinhaein:BAABLgAECn8jAAILAAgJ0BM8EAA0AQALAAgJ0BM8EAA0AQABLgAFFAYJHAAIAN4VAA==.Shinxu:BAAALgADCgQJBAAAAA==.Shizmael:BAABLgAECn8WAAILAAYJDwtaGQDgAAALAAYJDwtaGQDgAAAAAA==.Shockazilla:BAABLgAECn83AAMkAAkJbR7fCAD9AgAkAAkJbR7fCAD9AgAFAAMJVw+z/wCWAAAAAA==.Shreddarfort:BAAALgADCgkJFQAAAA==.Shönuff:BAAALgAECgEJAQAAAA==.',
Si='Sigh:BAAALgAFFAEJAQAAAA==.Silverhorn:BAABLgAECn8sAAIFAAgJxh1NBgDyAQAFAAgJxh1NBgDyAQAAAA==.',
Sk='Skoduh:BAABLgAECn8kAAIGAAkJWhoRVACnAQAGAAkJWhoRVACnAQAAAA==.Skyelene:BAABLgAECn8uAAMTAAkJyhZiFwAqAgATAAkJyhZiFwAqAgASAAcJvwa+egDvAAAAAA==.',
Sl='Slaanesh:BAABLgAECn8hAAQHAAkJ3RZaDAB5AQAaAAcJNBK9TQCxAQAHAAcJOBZaDAB5AQAZAAMJlhsqFwDFAAAAAA==.Sluggo:BAABLgAFFH8HAAIFAAUJzxFGLABdAQAFAAUJzxFGLABdAQAAAA==.Sluggoboyce:BAACLgAFFH8GAAICAAQJhgR9EwAHAQACAAQJhgR9EwAHAQAuAAQKfyIAAwIACAkLGSEcAEcCAAIACAnYGCEcAEcCAAYABAmEDS6aAJ8AAAAA.',
Sm='Smeagosses:BAAALgAECgEJAQAAAA==.',
So='Solace:BAABLgAECn8oAAIKAAkJmR/CAQCGAgAKAAkJmR/CAQCGAgAAAA==.Solinaara:BAAALgAECgQJBAAAAA==.Soraka:BAABLgAFFH8LAAIVAAQJnQpWKwD2AAAVAAQJnQpWKwD2AAAAAA==.Soulstoner:BAAALgAECgEJAwAAAA==.',
Sp='Spiralist:BAABLgAECn8dAAQWAAkJ4xajTgBUAQAWAAgJfBWjTgBUAQAYAAYJARm6NwA2AQAbAAIJkAwIQwBVAAAAAA==.Spiralmist:BAAALgADCgUJBQAAAA==.Spiritdragon:BAAALgAECgEJAQAAAA==.',
St='Starge:BAAALgAECgUJBQAAAA==.Steelforged:BAAALgADCgkJEAABLgAECggJFwAeAJQTAA==.Stico:BAAALgAECgIJAQAAAA==.Stonedalways:BAABLgAECn8iAAMSAAkJGxAyPwCxAQASAAgJphAyPwCxAQATAAQJmgWDiwBZAAAAAA==.',
Su='Sunfuri:BAABLgAECn85AAIhAAkJDQo0NgBvAQAhAAkJDQo0NgBvAQAAAA==.Sunjan:BAAALgAECgQJBwAAAA==.Sus:BAACLgAFFH8hAAIiAAcJ7RtyAwABAgAiAAcJ7RtyAwABAgAuAAQKfyUAAiIACQmXI5cDAEcDACIACQmXI5cDAEcDAAAA.Susanoo:BAABLgAECn8bAAIhAAkJihdpJADRAQAhAAkJihdpJADRAQAAAA==.',
Sy='Sylvíadne:BAAALgAECgYJBgAAAA==.',
Sz='Szul:BAAALgADCgcJDAAAAA==.',
Ta='Taalia:BAAALgAECgYJEAABLgAECgkJJgAWAMoIAA==.Tachima:BAAALgAECgcJEAABLgAECgkJLgAKADMiAA==.Tactics:BAAALgADCgcJDAAAAA==.Tahitimango:BAABLgAECn8pAAIKAAcJXQRT0gCPAAAKAAcJXQRT0gCPAAAAAA==.Takeko:BAAALgADCgcJDgABLgAECgkJGQABAKMXAA==.Talanas:BAAALgADCgcJBwAAAA==.Taleria:BAAALgADCgYJIgAAAA==.Talonas:BAAALgAECgEJAQAAAA==.Tamarrion:BAAALgAECgEJAQABLgAECgYJGQASALwXAA==.Taranad:BAAALgAECgcJDAAAAA==.Tarathor:BAABLgAECn8xAAIYAAkJqBxwAQCBAgAYAAkJqBxwAQCBAgAAAA==.Tarn:BAAALgAECgEJAQAAAA==.Tasha:BAAALgAECgEJAwABLgAECggJHwAhAO8UAA==.Tauroctony:BAABLgAECn8eAAIRAAgJKiGhBACiAgARAAgJKiGhBACiAgAAAA==.',
Te='Tea:BAABLgAECn8XAAMcAAgJKgzEIQAiAQAcAAgJKgzEIQAiAQAhAAUJFAQhfgB9AAABLgAECgkJRQAOAPYfAA==.Teknofarious:BAAALgAECgEJBAAAAA==.Tenom:BAAALgAECgUJCgAAAA==.',
Th='Thalar:BAAALgAECgIJAgAAAA==.Thaumas:BAAALgADCgEJAQAAAA==.Thelsyn:BAAALgAECgIJAgABLgAECgkJQAABAEUYAA==.Thermite:BAAALgAECgYJBgAAAA==.Thesafe:BAAALgAECgMJBQAAAA==.Thialaa:BAAALgAECgEJAwABLgAECgkJSgAGANEkAA==.Thialia:BAAALgAECgkJEwABLgAECgkJSgAGANEkAA==.Thialiaa:BAAALgAECgYJBwABLgAECgkJSgAGANEkAA==.Thoralon:BAAALgADCgEJAQAAAA==.Thorey:BAAALgAECgEJAQAAAA==.Thorgrumn:BAAALgADCggJDQAAAA==.Thornbreaker:BAAALgADCgEJAQAAAA==.Thorthunda:BAAALgAECgQJBgAAAA==.',
Ti='Tinkabella:BAABLgAECn87AAIVAAkJLiNoAgCSAwAVAAkJLiNoAgCSAwAAAA==.Tizl:BAEALgAECgUJBQABLgAFFAYJFQAIAEgdAA==.',
Tm='Tmgwolf:BAAALgAECgUJBQAAAA==.',
To='Tobi:BAAALgADCgQJBAAAAA==.Tobiblindpaw:BAAALgAECgYJDwAAAA==.Tobinir:BAAALgADCgkJCQAAAA==.Toenailjuice:BAAALgADCgUJBQABLgAECgkJOwAXAKkjAA==.Togo:BAAALgAECgYJBgAAAA==.Torrey:BAABLgAECn8YAAIkAAgJHyVuAwA8AwAkAAgJHyVuAwA8AwAAAA==.Totemicrick:BAAALgAECgEJAgABLgAECgkJLQAXAAQNAA==.Tovarek:BAAALgADCgkJCwAAAA==.',
Tr='Trema:BAAALgAECgYJDQAAAA==.Trix:BAABLgAECn8vAAISAAgJHw1pWABVAQASAAgJHw1pWABVAQAAAA==.Trounces:BAACLgAFFH8GAAIlAAMJKBjlFgDjAAAlAAMJKBjlFgDjAAAuAAQKfyEAAiUABwm1GR0EAFoBACUABwm1GR0EAFoBAAAA.Truesmoke:BAAALgAECgEJAQAAAA==.',
Tu='Tulsami:BAAALgAECgIJAwAAAA==.Tulsi:BAABLgAECn88AAIoAAkJYyS0AAA+AwAoAAkJYyS0AAA+AwAAAA==.Tuskoo:BAAALgAECgcJEQAAAA==.',
Ty='Tyrathion:BAAALgAECgMJAwAAAA==.Tyronos:BAABLgAECn8hAAIFAAkJQxkNLQBMAgAFAAkJQxkNLQBMAgAAAA==.',
Uk='Uknôwnforce:BAAALgAECgMJBAAAAA==.',
Un='Unbeetable:BAAALgADCgUJBQAAAA==.',
Va='Vaeltharion:BAAALgADCgEJAQAAAA==.Valanoth:BAABLgAECn8jAAIKAAgJ1SBiHQBkAgAKAAgJ1SBiHQBkAgAAAA==.Valdr:BAABLgAECn8hAAMlAAkJchPRIgDEAQAlAAkJchPRIgDEAQANAAQJowzXKQDQAAAAAA==.Valoryck:BAAALgAECgQJDQABLgAECggJIwAKANUgAA==.Vas:BAAALgAECgQJCgAAAA==.',
Ve='Velielina:BAAALgAECgEJAQAAAA==.Velistos:BAAALgADCgEJAQAAAA==.Vellandrias:BAAALgADCgYJBgAAAA==.Verinda:BAAALgADCgcJDwAAAA==.Vesperr:BAAALgAECgQJCAAAAA==.Vessara:BAAALgAECgEJAQABLgAFFAYJEQARAAkTAA==.Vevicenth:BAABLgAECn8UAAInAAkJ3gi7BgBEAQAnAAkJ3gi7BgBEAQAAAA==.',
Vh='Vhaidra:BAAALgAECgQJBAAAAA==.',
Vo='Voodoolily:BAAALgAECgUJBwAAAA==.Voranth:BAAALgAECgEJAQAAAA==.',
Wa='Warenio:BAAALgAECgkJCgAAAA==.Warick:BAAALgADCgMJBAAAAA==.Warpsbulge:BAACLgAFFH8gAAILAAcJ2x1lCgDMAQALAAcJ2x1lCgDMAQAuAAQKfxsAAwsACQlNIb4hAOwCAAsACQlNIb4hAOwCACAAAgl2FLQTAIoAAAAA.',
Wh='Whakan:BAAALgAECgEJAgABLgAECgkJJAAjAEIYAA==.Whippedtator:BAAALgAECgEJAQAAAA==.',
Wo='Wolfos:BAABLgAECn8fAAIRAAkJEiaSAABwAwARAAkJEiaSAABwAwABLgAFFAMJBQAXAOMbAA==.',
Wt='Wtfox:BAEBLgAECn8rAAMUAAkJdxf4AQAwAgAUAAkJdxf4AQAwAgAVAAQJZQJUdAA/AAAAAA==.',
Wu='Wulfgange:BAAALgADCgEJAQAAAA==.',
Wy='Wysteri:BAABLgAECn8WAAIKAAcJLhLsZgBYAQAKAAcJLhLsZgBYAQAAAA==.',
Xa='Xadrai:BAAALgADCgIJAgAAAA==.Xakeko:BAABLgAECn8WAAQIAAgJcxO1rgAWAQAIAAUJsxO1rgAWAQAJAAUJlRCXHgDYAAAjAAIJ+BYjEgBBAAABLgAECgkJGQABAKMXAA==.Xalatos:BAAALgAECgEJAwAAAA==.Xalfein:BAAALgAECgQJBgAAAA==.',
Xi='Xinu:BAAALgAECgcJBwABLgAECgkJRQAGANogAA==.',
Ya='Yanakana:BAAALgAECggJDAAAAA==.',
Yd='Ydalise:BAAALgAECgEJAgAAAA==.Ydrassil:BAACLgAFFH8FAAIRAAMJwRDgDwCaAAARAAMJwRDgDwCaAAAuAAQKfxYAAhEACQkdG24JAFMCABEACQkdG24JAFMCAAAA.',
Yi='Yitsuni:BAAALgAECgcJDQAAAA==.',
Za='Zakeko:BAAALgAECgQJBwABLgAECgkJGQABAKMXAA==.Zalaeda:BAAALgAECgEJAQAAAA==.Zalena:BAAALgAECgQJCAAAAA==.Zatriani:BAAALgAECgYJCgAAAA==.',
Ze='Zenus:BAABLgAECn8iAAMGAAgJsxWAVACmAQAGAAgJsxWAVACmAQACAAMJqwevNwBAAAAAAA==.Zerina:BAAALgADCgUJBQAAAA==.Zesty:BAAALgADCgMJAwAAAA==.Zeusal:BAABLgAECn8hAAIYAAcJjQ+VNgA8AQAYAAcJjQ+VNgA8AQAAAA==.Zeusinator:BAABLgAECn8sAAIGAAkJzxnyIwBTAgAGAAkJzxnyIwBTAgAAAA==.',
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
