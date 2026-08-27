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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Frost','Evoker-Preservation','DemonHunter-Devourer','Mage-Frost','Evoker-Devastation','Priest-Holy','Monk-Brewmaster','Unknown-Unknown','Druid-Guardian','Shaman-Restoration','Shaman-Elemental','Priest-Shadow','Priest-Discipline','Druid-Restoration','Monk-Mistweaver','Druid-Balance','Warlock-Affliction','Warlock-Demonology','Druid-Feral','Warrior-Protection','Warrior-Arms','Warrior-Fury','Monk-Windwalker','Shaman-Enhancement','Mage-Arcane','DemonHunter-Havoc','DeathKnight-Blood','Paladin-Holy','Evoker-Augmentation','DemonHunter-Vengeance','Mage-Fire','Rogue-Assassination',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=46,date='2026-08-25',data={Ab='Abelene:BAAALgAECgQJBAAAAA==.Abrâham:BAAALgADCgUJBQAAAA==.',
Ac='Achelis:BAABLgAECn86AAMBAAkJ8CVZAQBUAwABAAkJ8CVZAQBUAwACAAEJAABJggA/AAAAAA==.',
Ad='Adianitefall:BAAALgAECgUJBgAAAA==.Adorian:BAABLgAECn8nAAIDAAkJMgqdCgDHAAADAAkJMgqdCgDHAAAAAA==.Adros:BAABLgAECn8oAAMEAAgJQRQMFQB+AQAEAAgJQRQMFQB+AQAFAAEJHwS4wgEiAAAAAA==.Adrrel:BAAALgADCgIJAgABLgAFFAkJIgAGAJAYAA==.Adrrelle:BAACLgAFFH8iAAQGAAkJkBjHGwCXAQAGAAcJ/BvHGwCXAQABAAQJWg9lFAAqAQACAAYJaw1aEgAWAQAuAAQKfyUABAIACQncHXcTAJkCAAIACAmXH3cTAJkCAAEABAnaF7I7AOIAAAYAAwmpEW64AFIAAAAA.',
Ae='Aelon:BAABLgAECn8cAAIFAAgJxgeTrwAkAQAFAAgJxgeTrwAkAQAAAA==.',
Ah='Aheiro:BAAALgAECgQJCQAAAA==.',
Ai='Ailaith:BAABLgAECn9KAAIGAAkJ0STUAwBTAwAGAAkJ0STUAwBTAwAAAA==.',
Ak='Akariliselle:BAABLgAECn8aAAIHAAkJfh0YCgCkAQAHAAkJfh0YCgCkAQAAAA==.Akarue:BAAALgAECgQJBAAAAA==.Akibafaris:BAABLgAECn8uAAMIAAkJ+R5+AwC0AgAIAAkJsx5+AwC0AgAJAAUJ6RtDBABLAQAAAA==.Aknologia:BAAALgAECgUJDQAAAA==.',
Al='Al:BAAALgADCggJCAAAAA==.Alan:BAAALgAECgUJCQAAAA==.Alarielle:BAAALgADCgkJEwAAAA==.Albion:BAAALgAECgQJBAABLgAECgkJJQAKAL8ZAA==.Alcun:BAAALgAECgIJAwAAAA==.Aldora:BAAALgADCgkJDAAAAA==.Alen:BAAALgAECgEJAgAAAA==.Alirik:BAAALgADCgQJCQAAAA==.Alleriah:BAAALgAECgcJCAABLgAECggJIwALANUgAA==.Alon:BAAALgAECgIJAgAAAA==.Alydrostage:BAABLgAECn8qAAIMAAkJhwhnoAA6AQAMAAkJhwhnoAA6AQAAAA==.Alystriaz:BAABLgAECn8oAAMKAAkJPxpABgCkAgAKAAkJPxpABgCkAgANAAEJsQWEKQAoAAAAAA==.Alzheimerz:BAAALgAECgUJBQAAAA==.',
Am='Amaelalin:BAABLgAECn9FAAIOAAkJ9h+vBAA1AwAOAAkJ9h+vBAA1AwAAAA==.Amaribo:BAAALgAECgEJAQABLgAFFAYJHAAPAHsmAA==.Ameliya:BAAALgAECgIJAgAAAA==.Ameng:BAAALgAECgQJBgAAAA==.',
An='Ananiel:BAAALgAECgEJAQABLgAECgIJAgAQAAAAAA==.Anaralestra:BAAALgAFFAEJAgABLgAFFAYJEQARAAkTAA==.Anaralyth:BAAALgAECgYJCAABLgAFFAYJEQARAAkTAA==.Andaya:BAACLgAFFH8cAAMSAAYJqB8ZFwCtAQASAAYJqB8ZFwCtAQATAAEJnwNjYAAtAAAuAAQKfyMAAxIACQmrGac8ALwBABIACQmrGac8ALwBABMAAgndDAaGAGQAAAAA.Andemeli:BAABLgAECn8tAAIFAAkJrRAqDQCVAQAFAAkJrRAqDQCVAQAAAA==.Andevyn:BAAALgAECgQJBAABLgAECggJIwALANUgAA==.Aninja:BAEALgADCgQJBAABLgAFFAgJFwAIAMMYAA==.Anivia:BAABLgAECn8gAAIMAAkJ4xLUVgDZAQAMAAkJ4xLUVgDZAQAAAA==.Ankoubailith:BAAALgAECgQJBgAAAA==.',
Ap='Apollon:BAAALgADCgIJAwAAAA==.',
Ar='Arandis:BAABLgAECn8kAAMUAAgJawwQQwADAQAUAAYJXA4QQwADAQAVAAQJkQjdVwChAAAAAA==.Arch:BAAALgAECgUJCQAAAA==.Arcianna:BAABLgAECn8yAAMRAAkJ2B2EBgCVAgARAAkJ2B2EBgCVAgAWAAEJQRHf0wAxAAAAAA==.Arctica:BAABLgAECn8hAAIMAAYJpw7wHgDoAAAMAAYJpw7wHgDoAAAAAA==.Arctiq:BAAALgADCgUJCgAAAA==.Arctîc:BAABLgAECn8qAAIMAAkJFhPRUgDkAQAMAAkJFhPRUgDkAQAAAA==.Arjurn:BAABLgAECn87AAIMAAkJByBaFADfAgAMAAkJByBaFADfAgAAAA==.Arkro:BAAALgAECgMJBAAAAA==.Armpitbutter:BAABLgAECn87AAIXAAkJqSMJBAB1AwAXAAkJqSMJBAB1AwAAAA==.Artymiss:BAABLgAECn8kAAMYAAkJ/RORBQCZAQAYAAkJ/RORBQCZAQAWAAYJmRNLVgBQAQAAAA==.',
As='Asherah:BAABLgAECn8uAAQZAAgJHwr0FQAbAQAZAAcJZgn0FQAbAQAaAAcJugFo9AB5AAAHAAIJtA5BDgBeAAAAAA==.Ashireita:BAAALgAECgYJEAABLgAECgkJLgATAMoWAA==.Ashwadawnguh:BAAALgAECgEJAQAAAA==.Astraleth:BAACLgAFFH8RAAQRAAYJCRMyHACvAAAYAAMJqxVRLgDNAAARAAUJmQsyHACvAAAWAAEJcwJVcwAzAAAuAAQKfx4AAxEACQmwGgISANABABEABwkaFwISANABABgABwkBGsAPAMYAAAAA.',
At='Atama:BAAALgAECgQJBwAAAA==.Atharius:BAAALgADCgEJAQAAAA==.',
Au='Aurturious:BAAALgAECgUJBQAAAA==.Authority:BAAALgAECgMJAwAAAA==.Autry:BAABLgAECn8xAAMbAAkJ1g9tEACwAQAbAAkJ1g9tEACwAQAWAAgJUgpZUwBCAQAAAA==.',
Av='Avelina:BAAALgADCgkJFAAAAA==.Avocat:BAABLgAECn8uAAIGAAkJiRsjFwCcAgAGAAkJiRsjFwCcAgAAAA==.',
Ay='Ayrilia:BAAALgAECgYJCAABLgAFFAYJEQARAAkTAA==.Ayshama:BAAALgAECgYJEQAAAA==.',
Az='Azeria:BAAALgAECgUJCQABLgAFFAkJFAAcAN0eAA==.Azetbur:BAAALgAECgQJBAAAAA==.Azorah:BAAALgADCgMJAwAAAA==.Azshura:BAAALgAECgYJBwAAAA==.Azzinôth:BAAALgADCgcJBwABLgAECgEJAgAQAAAAAA==.',
Ba='Baekr:BAAALgAECgYJEAAAAA==.Baldr:BAABLgAECn8wAAIFAAkJKhM+TQDfAQAFAAkJKhM+TQDfAQAAAA==.Balgar:BAABLgAECn8aAAMGAAkJeCP7JABPAgAGAAkJeCP7JABPAgACAAUJyxm3PgBgAQAAAA==.Balghas:BAABLgAECn8kAAIFAAgJ1hzQMwBTAgAFAAgJ1hzQMwBTAgAAAA==.Bammz:BAABLgAFFH8FAAIdAAMJZxGcJgDTAAAdAAMJZxGcJgDTAAAAAA==.Bamz:BAAALgAFFAEJAQABLgAFFAYJHQAUAO4ZAA==.Bastia:BAABLgAECn8ZAAIeAAYJlwf5FgCTAAAeAAYJlwf5FgCTAAAAAA==.Baumstrum:BAAALgAECgYJDQAAAA==.',
Be='Bearlydrae:BAAALgAECgMJBAAAAA==.Beezlbubba:BAAALgAECgYJDwAAAA==.Beldam:BAAALgADCgYJBgAAAA==.Belispeak:BAAALgADCgYJBgAAAA==.Bellaboom:BAAALgADCgYJBgAAAA==.Belvkara:BAAALgADCgkJCQAAAA==.Benedictoe:BAAALgADCgYJBgAAAA==.',
Bh='Bhozok:BAABLgAECn83AAIbAAkJvBI/DgDSAQAbAAkJvBI/DgDSAQAAAA==.',
Bi='Bigtbag:BAAALgAECgEJAQAAAA==.Bint:BAAALgAECgEJAQAAAA==.',
Bl='Bloodpromise:BAAALgADCgMJAwAAAA==.Bloodrayvn:BAABLgAECn8wAAIGAAkJxR18GACUAgAGAAkJxR18GACUAgAAAA==.',
Bo='Boomchick:BAAALgAECgMJAwABLgAECgkJIAAGAOAdAA==.Boomparapara:BAACLgAFFH8QAAIMAAQJ3xf0TQBDAQAMAAQJ3xf0TQBDAQAuAAQKfycAAgwACQl9IKURAPACAAwACQl9IKURAPACAAAA.Booshido:BAAALgAECgEJAgAAAA==.Borrkbuster:BAAALgAECgQJBAAAAA==.Botkin:BAAALgADCgEJAQAAAA==.Bowan:BAAALgAECgEJAQAAAA==.',
Br='Bradley:BAAALgAECgYJDgABLgAECggJGAAOAMogAA==.Brandywyne:BAAALgADCgEJAQAAAA==.Brenri:BAABLgAECn8eAAITAAkJwgPEVgDgAAATAAkJwgPEVgDgAAAAAA==.Brew:BAABLgAECn8mAAMPAAkJ4BrzEwAQAgAPAAkJ4BrzEwAQAgAfAAEJ0Q0LfQAzAAAAAA==.Brewtality:BAABLgAFFH8JAAIXAAQJChj9GAAGAQAXAAQJChj9GAAGAQABLgAFFAMJCQAWACUWAA==.Brkat:BAAALgAECgIJAgAAAA==.Brughe:BAABLgAECn8tAAIGAAkJlw4TZAB9AQAGAAkJlw4TZAB9AQAAAA==.',
Bu='Bubbleoseven:BAAALgADCgYJBgABLgAFFAMJCQAWACUWAA==.Burntbum:BAAALgAECgYJBwAAAA==.Buttacutta:BAAALgADCgkJRgAAAA==.',
['Bä']='Bäné:BAAALgADCgIJAgAAAA==.',
Ca='Cahoots:BAAALgAECgEJAQAAAA==.Cairn:BAAALgADCgUJBQAAAA==.Camaracy:BAAALgAECgYJEQAAAA==.Caneste:BAACLgAFFH8QAAIUAAYJqhm2DwBwAQAUAAYJqhm2DwBwAQAuAAQKfx8AAhQACQm9HfcLAMMCABQACQm9HfcLAMMCAAAA.Capela:BAAALgAECgMJAwAAAA==.Capparelli:BAAALgADCgEJAQAAAA==.Cashoe:BAAALgADCgMJAwAAAA==.Catscan:BAACLgAFFH8JAAIWAAMJJRZGFwC6AAAWAAMJJRZGFwC6AAAuAAQKfyIAAhYACQniHV0OAOUCABYACQniHV0OAOUCAAAA.Catty:BAABLgAECn8wAAIbAAkJ/BeDCABEAgAbAAkJ/BeDCABEAgAAAA==.',
Cb='Cblock:BAAALgAECgUJBQABLgAFFAMJDAAgAPALAA==.',
Ce='Celeano:BAAALgADCgkJCQABLgAECgQJBAAQAAAAAA==.Celestyl:BAABLgAECn8xAAIhAAkJ6wy4BQB2AQAhAAkJ6wy4BQB2AQAAAA==.',
Ch='Charazard:BAAALgAECgUJCgABLgAECgkJJQAKAL8ZAA==.Charming:BAAALgADCgMJAwAAAA==.Cheapbeer:BAABLgAECn8VAAIFAAkJVgir2ADnAAAFAAkJVgir2ADnAAAAAA==.Cheesehead:BAAALgADCggJEgAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chiforged:BAABLgAECn8XAAIfAAgJlBPwCQDgAAAfAAgJlBPwCQDgAAAAAA==.Chillybovine:BAABLgAECn8bAAIMAAcJCQqUsAAgAQAMAAcJCQqUsAAgAQAAAA==.Choppa:BAABLgAFFH8GAAIPAAMJpRdcEADSAAAPAAMJpRdcEADSAAAAAA==.Chromstrasza:BAABLgAECn8ZAAINAAcJHxjBCQCJAQANAAcJHxjBCQCJAQAAAA==.Chudderly:BAAALgADCgEJAgAAAA==.Chudders:BAAALgADCgIJAgAAAA==.',
Ci='Cinnia:BAAALgAECgMJAwAAAA==.Cirice:BAAALgAECgEJBgAAAA==.Citrouille:BAAALgAECgEJAgAAAA==.',
Cl='Clarence:BAAALgADCgIJAgABLgAFFAkJLgAaAMkXAA==.Clonazepam:BAAALgAECgUJDgABLgAECgkJJwADADIKAA==.',
Co='Comitus:BAABLgAECn9JAAMdAAkJBhBlFwCgAQAdAAkJBhBlFwCgAQAeAAQJawVjgwCxAAAAAA==.Conjar:BAAALgAECgIJAgAAAA==.Conjarr:BAABLgAECn80AAIOAAkJHRyuBADEAQAOAAkJHRyuBADEAQAAAA==.Cortisol:BAAALgADCgIJAgAAAA==.Corven:BAAALgAECgUJDAAAAA==.Corvinus:BAAALgAECgQJBAAAAA==.Cougardk:BAAALgAECgIJAgAAAA==.Cougarshammy:BAAALgAECgcJCAAAAA==.Cougarsixsix:BAABLgAECn8pAAIEAAkJYBrmAwCGAQAEAAkJYBrmAwCGAQAAAA==.Cougarwar:BAAALgAECgUJCwAAAA==.',
Cr='Crashnburn:BAAALgADCgcJDQAAAA==.Crazyoldbear:BAABLgAECn8eAAIcAAkJmCPuAwDuAgAcAAkJmCPuAwDuAgAAAA==.Creideam:BAAALgADCgkJBwAAAA==.Crimos:BAABLgAECn8wAAIIAAkJzRbsQAAAAgAIAAkJzRbsQAAAAgAAAA==.Crystalliney:BAAALgADCgYJBgABLgAFFAYJHAAPAHsmAA==.',
Cy='Cynnai:BAAALgADCgYJBgAAAA==.Cyrena:BAAALgAECgEJAQAAAA==.',
Da='Daerthor:BAABLgAECn8iAAIEAAkJOBo8CgAnAgAEAAkJOBo8CgAnAgAAAA==.Dalind:BAABLgAECn8nAAIWAAkJyggrEACtAAAWAAkJyggrEACtAAAAAA==.Dalora:BAAALgAECgEJAQAAAA==.Dalshiro:BAAALgAECgYJCQAAAA==.Damaclies:BAABLgAECn9fAAMaAAkJ6hmWBwCjAQAaAAgJzxeWBwCjAQAHAAUJ/xgDGADiAAAAAA==.Damedolla:BAABLgAECn8fAAMLAAgJYQzDfwAgAQALAAgJwwrDfwAgAQAiAAUJnw7EQAD3AAAAAA==.Dammerung:BAAALgAECgYJCQAAAA==.Darksyn:BAABLgAECn8fAAIHAAkJjw2BEgAiAQAHAAkJjw2BEgAiAQAAAA==.Darthbane:BAABLgAECn8WAAMIAAkJ7AlcGgDhAAAJAAgJHgXbHADnAAAIAAQJAw9cGgDhAAAAAA==.Darthghidora:BAAALgADCgkJEQAAAA==.Darthstroyer:BAABLgAFFH8FAAQJAAUJwgUhGgC5AAAJAAMJjgYhGgC5AAAIAAEJXQMcFwE9AAAjAAEJAACBYwAAAAABLgAFFAUJCAAGABcIAA==.Darthyokai:BAAALgADCgMJAwAAAA==.Darude:BAAALgADCgcJEAAAAA==.Dashoka:BAAALgAECgEJAQAAAA==.Dattiffany:BAAALgAECgUJBQAAAA==.Dawnfist:BAAALgADCggJCAAAAA==.',
De='Deadstout:BAABLgAECn8VAAQJAAYJERxsBQAfAQAjAAQJqxxEIQBIAQAJAAYJphFsBQAfAQAIAAEJUQCrqgENAAAAAA==.Deathevan:BAAALgAECggJDgABLgAECgkJLgALADMiAA==.Deezknots:BAAALgAECggJCAAAAA==.Deezus:BAAALgADCgMJAwAAAA==.Dejagauth:BAAALgAECgYJDwABLgAECgkJJwAkANgfAA==.Dekkan:BAAALgAECgYJEAAAAA==.Demonedd:BAAALgADCgMJAgAAAA==.Demòn:BAAALgAECgEJAQAAAA==.Denwarenji:BAAALgAECgQJBAABLgAECgkJLgAIAPkeAA==.Desdia:BAABLgAECn8iAAIMAAgJ2BhCSgD8AQAMAAgJ2BhCSgD8AQAAAA==.',
Di='Dia:BAAALgAECgQJBwAAAA==.Diabetes:BAABLgAFFH8VAAIXAAcJmRoTFwDFAQAXAAcJmRoTFwDFAQAAAA==.Diastolic:BAAALgADCgUJBQAAAA==.Didyoudie:BAAALgAECggJDgAAAA==.Diend:BAABLgAECn9UAAISAAkJgSTMAQCzAwASAAkJgSTMAQCzAwAAAA==.Dill:BAAALgAECgEJAQABLgAECgkJOgABAPAlAA==.Dillathis:BAAALgADCgEJAQAAAA==.Discord:BAAALgAECgQJBQABLgAFFAMJBAAQAAAAAA==.Dissonanita:BAABLgAECn8jAAIGAAkJQhjcBwAOAgAGAAkJQhjcBwAOAgAAAA==.',
Dj='Djthelock:BAABLgAECn8sAAMaAAkJuRb8NQABAgAaAAgJxBP8NQABAgAHAAQJDhhPHADEAAAAAA==.',
Do='Doctachris:BAAALgAECgEJAwAAAA==.Domodios:BAAALgADCgIJAgABLgAFFAMJBAAQAAAAAA==.Dormoon:BAABLgAECn8bAAMeAAgJnQ1/QQA/AQAeAAgJnQ1/QQA/AQAcAAEJIBH9VAAuAAAAAA==.',
Dr='Drac:BAAALgADCgYJCgAAAA==.Draeblade:BAAALgAECgUJBQAAAA==.Dragath:BAAALgAECgYJDgAAAA==.Drakur:BAAALgAECgYJCQAAAA==.Drbrad:BAABLgAECn8YAAQOAAgJyiB5FgAdAgAOAAcJjyJ5FgAdAgAUAAMJDhAdcQBgAAAVAAEJaBT3IQBDAAAAAA==.Dreadfangs:BAAALgADCgQJBQAAAA==.Druen:BAABLgAECn8yAAIbAAkJHB53BAC4AgAbAAkJHB53BAC4AgAAAA==.Drunkenpo:BAABLgAECn9QAAQPAAkJ5yH4BADzAgAPAAkJtSH4BADzAgAXAAUJ7hOeUQAoAQAfAAIJqCLTFQBeAAAAAA==.Drykin:BAAALgAECgYJCwAAAA==.Drïzl:BAEALgAECgMJAwABLgAFFAgJFwAIAMMYAA==.',
Du='Duckchow:BAAALgADCgYJBgAAAA==.Dugga:BAAALgADCgQJBAAAAA==.Duskmyre:BAABLgAECn8lAAILAAkJbw0OWQB8AQALAAkJbw0OWQB8AQAAAA==.',
Dw='Dwarfoo:BAABLgAECn8fAAMXAAkJnw4xEwABAQAXAAcJAA8xEwABAQAfAAcJOBOoPwABAQAAAA==.Dweñde:BAABLgAECn8nAAIaAAkJigrVYAB+AQAaAAkJigrVYAB+AQAAAA==.',
['Dë']='Dëthmetal:BAABLgAECn8UAAIIAAUJnQxfwgD/AAAIAAUJnQxfwgD/AAAAAA==.',
Ec='Ecthelion:BAAALgAECgYJCQAAAA==.',
Ed='Eddiemac:BAAALgAECgYJCgAAAA==.Eddrick:BAACLgAFFH8OAAIFAAQJuxqHHwAOAQAFAAQJuxqHHwAOAQAuAAQKf0IAAwUACQkaII4TAM0CAAUACQkqH44TAM0CAAQABQmAIPYEAFABAAAA.Edoran:BAAALgADCggJCAAAAA==.Edrani:BAAALgAECgYJDgAAAA==.',
Ei='Eilethen:BAABLgAECn8nAAIZAAkJOxocBgAfAgAZAAkJOxocBgAfAgAAAA==.',
Ek='Ekassa:BAAALgADCgkJCQAAAA==.',
El='Elaína:BAAALgADCgMJAwABLgAFFAUJGQAZAMUSAA==.Elementoe:BAAALgADCgEJAQABLgADCgYJBgAQAAAAAA==.Elendil:BAAALgAECgMJAwAAAA==.Elissabethh:BAAALgAECgYJEAAAAA==.Elleryn:BAAALgAECgQJBAABLgAECgkJEAAQAAAAAA==.Elminstar:BAAALgADCgIJAgAAAA==.Elsore:BAAALgADCgEJAQABLgAECgcJEgAQAAAAAA==.Elêctra:BAAALgAECgEJAgABLgAFFAEJAQAQAAAAAA==.',
Em='Employee:BAABLgAECn8VAAIlAAgJ4wvCSAAIAQAlAAgJ4wvCSAAIAQAAAA==.',
En='Engo:BAABLgAECn9EAAMOAAkJdiRnAwBZAwAOAAkJdCNnAwBZAwAVAAkJ9BslCQDhAgAAAA==.',
Er='Eradrá:BAACLgAFFH8ZAAMZAAUJxRJKEQCFAAAaAAUJxRIfVQAcAQAZAAIJAQxKEQCFAAAuAAQKf1AAAxkACQmzHugAAA4DABkACQmsG+gAAA4DABoACQm9GDUiAFkCAAAA.Eragon:BAAALgAECggJDgAAAA==.Erastrasza:BAAALgADCgYJCQAAAA==.Eroza:BAAALgAECgUJBgAAAA==.Ersey:BAAALgAECgQJBAABLgAFFAMJBwAWAO8HAA==.Ersèlla:BAACLgAFFH8HAAIWAAMJ7wdATACMAAAWAAMJ7wdATACMAAAuAAQKfy4AAxYACQmMGHobAGoCABYACQmMGHobAGoCABgAAQnYBSqdACQAAAAA.Erysira:BAAALgADCgkJCQABLgAECgkJKgAMAGEXAA==.',
Et='Ethan:BAAALgAECgEJAgAAAQ==.',
Eu='Eureka:BAABLgAECn8gAAMEAAkJTB2ADgDbAQAEAAcJ1RyADgDbAQAFAAcJSRnuZQCkAQABLgAFFAMJBgAPAKUXAA==.',
Ev='Evandra:BAABLgAECn8vAAISAAkJBRzGFgCTAgASAAkJBRzGFgCTAgAAAA==.Evanorah:BAABLgAECn8fAAMHAAkJ2QmHIgCcAAAaAAkJtgkMlAAUAQAHAAYJowWHIgCcAAAAAA==.',
Ex='Exïle:BAEALgAECgYJBgABLgAFFAgJFwAIAMMYAA==.',
Fa='Fabio:BAAALgADCgIJAgAAAA==.Faedeyeda:BAAALgAECgEJAgAAAA==.Faelithia:BAABLgAECn8WAAIOAAYJKA4PPQD/AAAOAAYJKA4PPQD/AAAAAA==.Fatalbrew:BAAALgAECgYJCwAAAA==.Fauxyalee:BAAALgADCgkJEgAAAA==.',
Fe='Feldush:BAAALgADCgYJBgABLgAECgkJJQAKAL8ZAA==.Felforit:BAAALgADCgQJBAAAAA==.Felis:BAAALgAECgYJCgAAAA==.Felkardio:BAAALgAECgIJAgAAAA==.Feloth:BAAALgAECgUJDQAAAA==.Ferheim:BAAALgAECgYJEwAAAA==.Ferhold:BAAALgAECgEJAQAAAA==.Ferrovax:BAAALgADCgYJBgABLgAECgkJLgALAPAZAA==.',
Fi='Fiddyone:BAABLgAECn8sAAMJAAkJySEoAwC+AgAJAAkJtCEoAwC+AgAIAAgJcR0pRQDzAQAAAA==.Figment:BAAALgADCgYJBgAAAA==.Firebolt:BAAALgAECgUJBQAAAA==.Fireburt:BAAALgADCgUJBQAAAA==.Fireslay:BAABLgAECn8YAAIkAAcJpBwHHgAmAgAkAAcJpBwHHgAmAgAAAA==.Fizzlegrin:BAAALgAECgIJAgAAAA==.',
Fl='Flarefly:BAAALgAECgEJAQAAAA==.Flaya:BAAALgAECgcJDAAAAA==.',
Fo='Fodurzin:BAABLgAECn8dAAMEAAcJmhVqBQA/AQAEAAYJRRZqBQA/AQAFAAUJ5xK2MwCIAAAAAA==.Fonta:BAAALgAECgMJAwAAAA==.Fortuna:BAAALgADCggJCAABLgAECgkJIAAGAOAdAA==.Foxingtobi:BAAALgADCgIJAgAAAA==.',
Fr='Frojio:BAABLgAECn8zAAIJAAkJ4ByaBQBYAgAJAAkJ4ByaBQBYAgAAAA==.Frosten:BAAALgAECgEJAQAAAA==.',
Fu='Furenio:BAABLgAECn80AAIRAAkJ7xekDgD6AQARAAkJ7xekDgD6AQAAAA==.',
Fy='Fyyre:BAAALgAECgUJBwAAAA==.',
Ga='Gabaghoul:BAACLgAFFH8YAAIFAAUJFh3zKgBhAQAFAAUJFh3zKgBhAQAuAAQKfzEAAgUACQl3IHoZAKsCAAUACQl3IHoZAKsCAAAA.Gaff:BAAALgAECgkJEwAAAA==.Galeana:BAAALgAECgMJAwABLgAECgkJXQAMAPAeAA==.Galvan:BAAALgAECgEJBAAAAA==.Gasheth:BAAALgAECgYJDQAAAA==.',
Ge='Gentyl:BAAALgAECgQJBgAAAA==.',
Gi='Giggleblast:BAAALgAECgIJAgAAAA==.',
Gl='Gladius:BAAALgAECgEJAgAAAA==.Glizzydealer:BAAALgAECgEJAQAAAA==.',
Gr='Grauth:BAAALgADCgEJAQAAAA==.Graycen:BAAALgAECgUJCQAAAA==.Grido:BAAALgAECgIJAgAAAA==.Grimbrindral:BAABLgAECn8hAAMFAAcJ5hZDZAC5AQAFAAcJdBVDZAC5AQAEAAUJghrKFwBZAQAAAA==.Grimston:BAAALgADCgMJAwABLgAECgcJIQAFAOYWAA==.Gruzaxx:BAAALgADCgUJBQAAAA==.',
Gu='Gulishdaniel:BAABLgAFFH8GAAIZAAQJJQRRCQDlAAAZAAQJJQRRCQDlAAABLgAFFAYJEAAUAKoZAA==.',
Ha='Hadin:BAABLgAECn9NAAMMAAkJMCTGBgBKAwAMAAkJMCTGBgBKAwAhAAMJqhysDwDHAAAAAA==.Hakeko:BAABLgAECn8aAAIBAAkJpheKAQA7AgABAAkJpheKAQA7AgAAAA==.Halalnt:BAABLgAFFH8FAAIIAAIJixsuiABQAAAIAAIJixsuiABQAAAAAA==.Hanua:BAAALgADCgcJBwAAAA==.Haozhao:BAABLgAECn9NAAMRAAkJXRsuCQBYAgARAAkJXRsuCQBYAgAbAAEJDhQnTwA7AAAAAA==.Hawktuahz:BAAALgAECgMJAwAAAA==.Hazenpryde:BAABLgAECn8iAAIRAAkJuRkeEADnAQARAAkJuRkeEADnAQAAAA==.',
He='Hearsay:BAABLgAECn9EAAQFAAgJdREjcACOAQAFAAgJdREjcACOAQAkAAYJXwm+DQDUAAAEAAEJrgfoHAAbAAABLgAECgkJLAAWAHIUAA==.Hecatamu:BAAALgAECgEJAQAAAA==.Helden:BAAALgAECgEJAQAAAA==.Hephaistian:BAAALgAECgYJBgAAAA==.Hespera:BAACLgAFFH8XAAMWAAYJPw9eJgApAQAWAAYJPw9eJgApAQAYAAMJ8whCOgCQAAAuAAQKfyMAAxYACQnJIOkYAHACABYACAmiIekYAHACABgAAwmnFP5SAMMAAAAA.',
Hi='Hirari:BAABLgAECn8dAAMkAAYJBCWUFwBMAgAkAAYJBCWUFwBMAgAFAAEJFBpjeQFCAAAAAA==.',
Ho='Hodoor:BAAALgAECgYJCAAAAA==.Horsebananas:BAAALgAECgYJDgABLgAECgkJRQABANwdAA==.Howlears:BAABLgAECn8qAAIUAAkJHQhOOwAlAQAUAAkJHQhOOwAlAQAAAA==.Hozzmer:BAAALgADCgYJBgAAAA==.',
Hu='Hulud:BAABLgAECn8YAAMaAAkJfRbiSwC3AQAaAAkJfRbiSwC3AQAHAAEJAADYVAAAAAAAAA==.Husbando:BAAALgAECgYJCAAAAA==.Husey:BAAALgAECgMJBgAAAA==.',
Hy='Hydrangea:BAABLgAECn8dAAIFAAcJ4Q+VkQBPAQAFAAcJ4Q+VkQBPAQAAAA==.Hydrá:BAABLgAECn8aAAIaAAkJvRYCMQAUAgAaAAkJvRYCMQAUAgAAAA==.Hylan:BAAALgADCgUJBQAAAA==.Hyped:BAAALgAECgEJAQAAAA==.Hysgar:BAAALgAECgYJBgABLgAECgkJJwAkANgfAA==.',
Ic='Iceamaris:BAABLgAECn8gAAITAAkJYQv/OABTAQATAAkJYQv/OABTAQAAAA==.Icetiger:BAAALgAECgIJAwAAAA==.Icetigress:BAAALgAECgEJAQAAAA==.',
Ie='Iechu:BAABLgAECn8uAAQPAAkJJBFsAwBwAQAPAAkJJBFsAwBwAQAXAAMJKxFxHwCVAAAfAAIJ9QZujABFAAAAAA==.',
In='Innanna:BAAALgADCggJCgABLgAECgcJFgALAC4SAA==.',
Is='Isoth:BAAALgAECgEJAQAAAA==.',
Iv='Ivern:BAACLgAFFH8WAAIWAAkJLhKKCAByAgAWAAkJLhKKCAByAgAuAAQKfx0AAxYABgkHHfgyANIBABYABgkHHfgyANIBABgAAgnRBzWXACkAAAAA.Ivysnow:BAAALgAECgEJAQAAAA==.',
Ja='Jac:BAAALgAECgMJAwABLgAFFAMJBAAQAAAAAA==.Jadenpryde:BAAALgAECgYJBgABLgAECgkJIgARALkZAA==.Jaod:BAAALgAECgQJAgAAAA==.Jarndal:BAAALgAECgEJAQAAAA==.Jasmirrae:BAAALgAECgEJAQAAAA==.',
Jd='Jdfel:BAAALgAECggJDwAAAA==.Jdghoul:BAABLgAECn8aAAQjAAkJYxyyAwDYAQAjAAkJnRuyAwDYAQAIAAUJZRD8JQCkAAAJAAEJtwMJRAAdAAAAAA==.',
Ji='Jian:BAAALgADCgIJAgAAAA==.Jindrac:BAABLgAECn8XAAMZAAkJBBF6AgCTAQAZAAkJBBF6AgCTAQAaAAEJ0QlLUwErAAAAAA==.',
Jo='Jolton:BAAALgADCgYJBwABLgAECgkJLgALADMiAA==.',
['Jà']='Jàcaranda:BAAALgAECgkJDwAAAA==.',
Ka='Kaedor:BAAALgAECgYJDQAAAA==.Kahnrah:BAAALgADCgkJDAAAAA==.Kalarae:BAAALgAECggJCQAAAA==.Kalarill:BAABLgAECn8eAAIFAAcJZR1rMAA/AgAFAAcJZR1rMAA/AgAAAA==.Kaljeer:BAAALgAECgkJEAAAAA==.Kalki:BAAALgAECgEJAgAAAA==.Kaltharion:BAABLgAFFH8IAAIKAAQJ6wNPEwB1AAAKAAQJ6wNPEwB1AAAAAA==.Kaluren:BAAALgAFFAEJAQAAAA==.Kalurok:BAAALgAECgUJBQABLgAFFAEJAQAQAAAAAA==.Kana:BAAALgAECgIJAgAAAA==.Kanade:BAABLgAECn9JAAQaAAkJBh7BFwCVAgAaAAgJ1R3BFwCVAgAZAAcJsRUACQDVAQAHAAQJWAsKTACJAAAAAA==.Kantong:BAABLgAECn8gAAIfAAgJdRmIGwDTAQAfAAgJdRmIGwDTAQAAAA==.Kapp:BAABLgAECn8UAAMeAAgJmwohWADuAAAeAAYJkAkhWADuAAAcAAIJNg2tFAA3AAAAAA==.Karabar:BAABLgAECn87AAMEAAkJ2yAYBQCjAgAEAAkJyh4YBQCjAgAFAAgJoyDzKABfAgAAAA==.Karnnaged:BAAALgADCgYJBwAAAA==.Kasarra:BAABLgAECn87AAIiAAkJFBd2AwDyAQAiAAkJFBd2AwDyAQAAAA==.Kazagol:BAABLgAECn87AAILAAkJ+x2rGgB0AgALAAkJ+x2rGgB0AgAAAA==.',
Ke='Kelintos:BAAALgAECgEJAgABLgAECgkJOAALAD4cAA==.Keone:BAAALgADCgEJAQAAAA==.Kethysa:BAAALgADCgIJAgAAAA==.',
Kh='Khalla:BAAALgAFFAEJAQAAAA==.Khalli:BAAALgAFFAIJAgAAAA==.Khamaracy:BAABLgAECn8sAAMHAAkJThChAgCQAQAHAAkJThChAgCQAQAaAAEJsQE6ZQEbAAAAAA==.Khronni:BAAALgAECgcJCQAAAA==.Khrooze:BAAALgAECgYJEQAAAA==.',
Ki='Kidos:BAAALgAECgQJBgAAAA==.Kiljana:BAAALgAECgEJAQAAAA==.Kimahrí:BAABLgAECn8jAAIjAAkJWQssDACxAAAjAAkJWQssDACxAAAAAA==.Kitez:BAAALgAECgMJBgAAAA==.Kittei:BAABLgAECn87AAIRAAkJ1w+eGwBwAQARAAkJ1w+eGwBwAQAAAA==.',
Ko='Kojote:BAAALgADCgMJAQAAAA==.Kovalenko:BAAALgAECggJDgAAAA==.',
Kp='Kpopdh:BAAALgAECgMJAwABLgAFFAIJBQAIAIsbAA==.',
Kr='Krepow:BAAALgAECgcJCgAAAA==.Kryptus:BAAALgAECgIJAgAAAA==.',
Ku='Kuczej:BAAALgAECgMJBAAAAA==.Kurick:BAABLgAECn8nAAQkAAkJ2B8QAQDrAgAkAAkJ2B8QAQDrAgAEAAYJ1xoUBAB+AQAFAAMJLQxWfgE+AAAAAA==.Kurzul:BAAALgADCgEJAgAAAA==.Kusinluvin:BAAALgAECgEJAQAAAA==.',
Ky='Kyngizzard:BAABLgAECn8fAAIMAAkJSRrUNwA5AgAMAAkJSRrUNwA5AgABLgAFFAIJBQAIAIsbAA==.Kytherin:BAAALgAECgYJDAAAAA==.',
La='Lactase:BAAALgADCgMJAwAAAA==.Lainea:BAAALgAECgMJAQAAAA==.Langtry:BAAALgADCgcJBgAAAA==.Lanoree:BAABLgAECn8WAAQJAAkJfQDJRgAGAAAIAAYJMQAnrAEGAAAJAAkJfQDJRgAGAAAjAAIJAAAAAAAAAAAAAA==.Latte:BAAALgAECgcJCgAAAA==.Lazy:BAAALgADCgMJAwAAAA==.',
Le='Leblanc:BAAALgAECgEJAQABLgAECgkJGAAFAEEeAA==.Leeli:BAAALgADCgcJBwAAAA==.Lemmeheal:BAAALgADCgMJAwAAAA==.Lenity:BAACLgAFFH8MAAIDAAIJ2g+LHgCOAAADAAIJ2g+LHgCOAAAuAAQKf10AAgMACQkyGn0BAG0CAAMACQkyGn0BAG0CAAAA.Letty:BAAALgAECgQJCQAAAA==.',
Li='Liabelle:BAAALgADCgIJAgAAAA==.Lightsmite:BAAALgAECgIJAgAAAA==.Lilithene:BAAALgAECgUJBgABLgAECgkJLgATAMoWAA==.Linkas:BAAALgAECgEJAQAAAA==.Lionbark:BAAALgADCgEJAQAAAA==.Lionell:BAAALgADCgUJBgAAAA==.Lithpally:BAAALgADCgEJAQAAAA==.Liubeijian:BAAALgADCgYJBgABLgAECgcJFgALAC4SAA==.',
Lo='Loan:BAAALgAECgUJBQABLgAECgkJFgAlAEkYAA==.Locharn:BAAALgAECgMJAwAAAA==.Lokinah:BAABLgAECn8gAAIGAAkJAQjBgAA9AQAGAAkJAQjBgAA9AQAAAA==.Loonytusk:BAAALgADCgQJBAAAAA==.Lorian:BAAALgADCgcJBwAAAA==.',
Lu='Lucifermadis:BAAALgAECgQJBgAAAA==.Lucoryphus:BAABLgAECn8kAAIjAAkJQhjYGQCQAQAjAAkJQhjYGQCQAQAAAA==.Lukas:BAAALgADCgMJAwAAAA==.Lukeduke:BAABLgAFFH8UAAIcAAkJ3R4ZBAAwAgAcAAkJ3R4ZBAAwAgAAAA==.Luketheduke:BAACLgAFFH8ZAAMRAAYJgR5RBADGAQARAAUJgR5RBADGAQAbAAEJAAAIBwA3AAAuAAQKfyoAAxEACQkvJR8BAFcDABEACQkvJR8BAFcDABsABAmxFXscAAkBAAEuAAUUCQkUABwA3R4A.Lumilia:BAAALgADCgUJBQAAAA==.Lunaries:BAAALgAECgYJCgAAAA==.Lunä:BAACLgAFFH8MAAISAAMJ7R4bGwD0AAASAAMJ7R4bGwD0AAAuAAQKfygAAxIACQlUFmoiABACABIACQlUFmoiABACABMAAQmLEKwsADEAAAAA.',
Ly='Lydia:BAABLgAECn8pAAIMAAkJphkzNABIAgAMAAkJphkzNABIAgAAAA==.Lynnee:BAAALgADCgEJAQAAAA==.',
['Lô']='Lôckrocks:BAABLgAECn8ZAAIHAAcJxhGODwBHAQAHAAcJxhGODwBHAQAAAA==.',
['Lý']='Lýsendra:BAAALgADCggJCQAAAA==.',
Ma='Magickeys:BAAALgAFFAIJAgAAAA==.Magictomb:BAACLgAFFH8MAAMgAAMJ8AuWDQCAAAAgAAMJ8AuWDQCAAAATAAEJrgE5IQA7AAAuAAQKfzYABCAACQlWFrUCAKgBACAACAkgE7UCAKgBABMACAmXFeU4AFMBABIABgnpDTd8AOsAAAAA.Mahdude:BAAALgAECgEJAwAAAA==.Malastor:BAAALgAECgEJAQABLgAFFAMJBAAQAAAAAA==.Malcontent:BAAALgAECgcJEQABLgAFFAMJBAAQAAAAAA==.Maldazane:BAAALgADCgYJCwAAAA==.Malfeasance:BAAALgAECgYJBgABLgAFFAMJBAAQAAAAAA==.Malidan:BAAALgADCgMJAwAAAA==.Malifel:BAABLgAECn8sAAMmAAkJsiAnAQAmAgAmAAkJsiAnAQAmAgALAAYJ+BQTDQAyAQABLgAFFAMJBAAQAAAAAA==.Maliss:BAABLgAECn9AAAQBAAkJRRgcFAAEAgABAAkJahccFAAEAgACAAQJ8RHLIQCjAAAGAAEJoxETLwE3AAAAAA==.Mallord:BAAALgAFFAMJBAAAAA==.Mandarin:BAABLgAECn84AAIWAAkJ8hoNEwCzAgAWAAkJ8hoNEwCzAgAAAA==.Manmythlegnd:BAAALgADCgYJBgAAAA==.Mannik:BAABLgAECn8aAAIaAAgJrRmPMgAOAgAaAAgJrRmPMgAOAgAAAA==.Marashade:BAAALgAECgUJBQAAAA==.Marashades:BAAALgAECgUJBgABLgAECgkJHgAcAJgjAA==.Mathemagics:BAAALgAECgIJAgAAAA==.',
Mc='Mcbadden:BAAALgAECgYJCAAAAA==.',
Me='Meditatetoe:BAAALgADCgIJAgABLgADCgYJBgAQAAAAAA==.Melabrin:BAAALgADCgkJCQAAAA==.Menesta:BAAALgADCgcJBwABLgAECgcJHQAEAJoVAA==.Mercia:BAABLgAECn8wAAIEAAkJExuDCQA3AgAEAAkJExuDCQA3AgAAAA==.Merekoma:BAABLgAECn8uAAMLAAkJ8BkOLQATAgALAAkJrhUOLQATAgAmAAQJFhY8HQCxAAAAAA==.',
Mi='Milarra:BAABLgAECn8VAAInAAcJMAnaCAD9AAAnAAcJMAnaCAD9AAAAAA==.Milhouse:BAABLgAECn8fAAIMAAcJNg0PKQCzAAAMAAcJNg0PKQCzAAAAAA==.Minalan:BAAALgADCgYJCgABLgAECgYJEQAQAAAAAA==.Mingonashoba:BAABLgAECn8jAAIGAAkJYw69RgDNAQAGAAkJYw69RgDNAQAAAA==.Miragosa:BAABLgAECn80AAMKAAkJUA+UDwDSAQAKAAkJUA+UDwDSAQANAAgJCAk7EAAHAQAAAA==.Misschris:BAABLgAECn8tAAIXAAkJBA1zQABsAQAXAAkJBA1zQABsAQAAAA==.Mistycinamon:BAAALgAECgEJAQAAAA==.Mizu:BAAALgAECgUJBQAAAA==.',
Mo='Moadeed:BAABLgAECn8oAAMRAAkJSBdiEgDLAQARAAkJ0RViEgDLAQAYAAUJChcvCwALAQAAAA==.Mooluv:BAAALgADCgcJCgAAAA==.Moonstrike:BAAALgAECgIJAgAAAA==.Mordrius:BAAALgADCgYJBgAAAA==.Morphmious:BAAALgAECgcJBwAAAA==.Mortesque:BAABLgAECn8ZAAQjAAcJZhgKBQCDAQAjAAcJJBYKBQCDAQAIAAcJZROChwByAQAJAAUJ2RDcDgC0AAAAAA==.',
Mu='Muttblitzed:BAABLgAECn8aAAIGAAgJnxZNTAC9AQAGAAgJnxZNTAC9AQAAAA==.Muttskî:BAAALgAECgMJAwAAAA==.',
My='Mybutt:BAAALgAECgMJBgAAAA==.Myroku:BAAALgADCgcJBwABLgAFFAMJBAAQAAAAAA==.Myrothos:BAAALgADCgEJAQAAAA==.Myrrh:BAABLgAECn8aAAMlAAgJSgmBEwBhAAANAAQJ9wYzLQCxAAAlAAgJnQiBEwBhAAAAAA==.Mysklef:BAAALgADCgMJAwABLgAECgkJJwAkANgfAA==.Mythris:BAAALgAECgkJBQAAAA==.',
['Mí']='Místermage:BAAALgAECgQJCAAAAA==.',
Na='Nadrael:BAAALgAECgEJAwAAAA==.Nasturtium:BAAALgADCgYJDgAAAA==.Nausican:BAACLgAFFH8JAAIJAAMJbQneDwCwAAAJAAMJbQneDwCwAAAuAAQKf00AAgkACQkUHD0EAIsCAAkACQkUHD0EAIsCAAAA.Nazuhda:BAAALgADCgEJAQAAAA==.',
Ne='Necrosector:BAACLgAFFH8KAAIFAAUJAgoqVgADAQAFAAUJAgoqVgADAQAuAAQKfyYAAgUACAm5Gc9OANsBAAUACAm5Gc9OANsBAAAA.Necrotherys:BAABLgAECn84AAILAAkJPhz0FwCGAgALAAkJPhz0FwCGAgAAAA==.Nelandra:BAABLgAECn8mAAIUAAkJ1hxqFgAXAgAUAAkJ1hxqFgAXAgAAAA==.Nerdius:BAAALgAECgEJAQAAAA==.Net:BAAALgAECgQJBAABLgAECgkJFgAlAEkYAA==.Netherforged:BAAALgAECgMJAwAAAA==.',
Ni='Nicklaus:BAABLgAECn8oAAIDAAcJlglnLwAjAQADAAcJlglnLwAjAQAAAA==.Nilrem:BAAALgADCgIJAgAAAA==.Ninelives:BAAALgAECgYJDgAAAA==.Ninjadk:BAECLgAFFH8XAAMIAAgJwxhgUABRAQAIAAcJwxhgUABRAQAjAAEJAABVZQAAAAAuAAQKfzMAAwgACQn5IgAPAPQCAAgACQn5IgAPAPQCAAkAAgldGv4SAEkAAAAA.',
No='Nocapongfrfr:BAAALgAECgMJAwABLgAFFAUJCAAGABcIAA==.Nomahuata:BAACLgAFFH8LAAITAAMJ2gwAIACkAAATAAMJ2gwAIACkAAAuAAQKf00AAhMACQlmGXkVAD0CABMACQlmGXkVAD0CAAAA.Nordre:BAAALgAECgMJAwAAAA==.',
Nu='Nufrus:BAAALgAECgUJBQAAAA==.',
Ny='Nyeli:BAAALgAECgkJEAAAAA==.Nyxi:BAABLgAECn8eAAISAAkJDhjTIABKAgASAAkJDhjTIABKAgAAAA==.Nyxlee:BAAALgAECgcJBwAAAA==.',
['Né']='Néo:BAAALgAECgUJCAAAAA==.',
['Nó']='Nóóôööôòòpe:BAABLgAFFH8IAAMGAAUJFwjyWgDvAAAGAAQJpAbyWgDvAAACAAEJ4A0CHABHAAAAAA==.',
Og='Ogdruid:BAAALgADCgcJDgAAAA==.',
Ok='Okume:BAAALgAECgIJAgAAAA==.',
Ol='Olympian:BAAALgADCgcJBwAAAA==.',
Om='Omanyte:BAAALgADCgcJBwAAAA==.',
On='Onefiftyone:BAABLgAECn8bAAMgAAYJHCVGCgAVAgAgAAYJHCVGCgAVAgASAAIJnSQsigDHAAABLgAECgkJLAAJAMkhAA==.',
Or='Oromë:BAAALgAECgEJAQAAAA==.Orruk:BAAALgADCgMJAwAAAA==.Orwyn:BAAALgAECgMJAwAAAA==.',
Ov='Overdose:BAAALgADCgMJAwAAAA==.',
Pa='Padmé:BAAALgAECgQJBgAAAA==.Pain:BAAALgAECgUJCwAAAA==.Palanas:BAAALgAFFAEJAQAAAA==.Pallamoo:BAAALgAECgcJCAAAAA==.Palochka:BAAALgAECggJCgAAAA==.Paltator:BAAALgAECggJCAAAAA==.Paradots:BAABLgAECn8WAAIKAAYJwBpqEgCiAQAKAAYJwBpqEgCiAQABLgAFFAMJCQAWACUWAA==.Paranitis:BAAALgAECggJDAAAAA==.Paranorm:BAAALgADCgEJAQAAAA==.Paraparaboom:BAAALgAECgUJBQABLgAFFAQJEAAMAN8XAA==.',
Pe='Pezdormu:BAAALgADCgEJAQAAAA==.Pezmage:BAAALgAECgIJBAAAAA==.',
Ph='Phatboi:BAAALgAECgEJAwAAAA==.Pheroth:BAAALgAECgUJDQABLgAECgkJHwAHAI8NAA==.',
Pi='Pixydaddy:BAABLgAECn8WAAMRAAcJgh2OAgD2AQARAAcJgh2OAgD2AQAbAAcJGgSyFgAzAAABLgAECgkJMwALAI4bAA==.Pixystix:BAABLgAECn8zAAILAAkJjhsUAwBNAgALAAkJjhsUAwBNAgAAAA==.',
Po='Poisonspain:BAAALgAECgMJAwAAAA==.Popsdh:BAAALgAECggJEwABLgAFFAMJBgAPAKUXAA==.Portlukk:BAAALgADCgEJAQABLgAFFAUJHAAGAPobAA==.Possibly:BAAALgAECgEJAQAAAA==.Potsomancy:BAACLgAFFH8eAAIMAAkJbhxTBQDJAgAMAAkJbhxTBQDJAgAuAAQKf0EAAgwACAnbJbsRAD0DAAwACAnbJbsRAD0DAAAA.Poxi:BAAALgAECgIJAgABLgAECggJGAAMADwdAA==.',
Pr='Prion:BAABLgAECn8fAAIeAAgJ7xT5KQCwAQAeAAgJ7xT5KQCwAQAAAA==.',
Pu='Pull:BAABLgAECn8jAAIRAAkJnxssCgBFAgARAAkJnxssCgBFAgAAAA==.',
Ra='Radioshack:BAAALgADCggJCAAAAA==.Radkemonko:BAAALgAECgcJDwAAAA==.Raega:BAAALgADCgYJBgAAAA==.Raemon:BAAALgADCgUJBQAAAA==.Ragerlock:BAAALgADCgEJAQAAAA==.Raivel:BAABLgAECn8ZAAISAAYJvBf+RgCSAQASAAYJvBf+RgCSAQABLgAECgkJEAAQAAAAAA==.Raldaron:BAAALgADCgEJAQAAAA==.Rambogg:BAAALgAFFAIJAgABLgAFFAgJHAAMAOwOAA==.Ramprices:BAABLgAECn8uAAIiAAkJeSaHAACLAwAiAAkJeSaHAACLAwAAAA==.Randalthor:BAAALgAECgUJBQABLgAECgkJVwAiACgbAA==.Raneyth:BAAALgAECggJCAAAAA==.Ranith:BAAALgADCgMJAwAAAA==.Ravagèr:BAAALgAECgEJAgAAAA==.',
Rd='Rdbwarrior:BAAALgADCgUJBQAAAA==.',
Re='Redemus:BAAALgADCgEJAQAAAA==.Redwinetoast:BAABLgAECn8kAAIaAAkJUAWBkQAYAQAaAAkJUAWBkQAYAQAAAA==.Rekimaru:BAAALgAECgEJAQAAAA==.Rekllaw:BAAALgAECgIJAgAAAA==.Reliala:BAAALgADCgkJEQAAAA==.Reno:BAABLgAECn8WAAMlAAkJSRjOAwCIAQAlAAgJ4hLOAwCIAQANAAYJqhqZAQCDAQAAAA==.Reshyk:BAABLgAECn8UAAIbAAkJQhyVCwACAgAbAAkJQhyVCwACAgAAAA==.Resles:BAAALgAECgEJAQAAAA==.Respectwomen:BAAALgADCgEJAQABLgAECgQJBAAQAAAAAA==.',
Rh='Rhobes:BAABLgAECn8bAAIeAAgJOxCJMwB8AQAeAAgJOxCJMwB8AQAAAA==.Rhondta:BAABLgAECn8nAAIaAAkJJRLrRQDJAQAaAAkJJRLrRQDJAQAAAA==.',
Ri='Rickormortis:BAABLgAECn8UAAIIAAkJGB1iHgCRAgAIAAkJGB1iHgCRAgABLgAECgkJLQAXAAQNAA==.Rictus:BAABLgAECn8wAAIMAAkJjSSLCAA4AwAMAAkJjSSLCAA4AwAAAA==.Riiree:BAAALgAECgEJAQAAAA==.Ringmasterr:BAAALgADCgUJBQAAAA==.Riordaa:BAAALgAECgQJBAAAAA==.Risingdragon:BAABLgAECn8qAAIfAAcJMhOHLgBQAQAfAAcJMhOHLgBQAQAAAA==.',
Ro='Roades:BAAALgADCgcJDAAAAA==.Roboskritch:BAAALgADCgUJBQAAAA==.Ronaj:BAAALgADCgMJBAAAAA==.Rorsham:BAAALgAECgEJAQABLgAFFAkJFgAWAC4SAA==.Rowene:BAAALgAECgIJAgAAAA==.Royveer:BAAALgADCgYJCQAAAA==.',
Ru='Rumor:BAABLgAECn8sAAUWAAkJchT1BADNAQAWAAkJchT1BADNAQAbAAcJvxTCEwCDAQARAAMJlwzmXABVAAAYAAIJdAkLgwBDAAAAAA==.Rurry:BAACLgAFFH8YAAIKAAYJpRe+BACuAQAKAAYJpRe+BACuAQAuAAQKfy4ABAoACQnIIrECAEADAAoACQnIIrECAEADAA0ABQm6GR4WAI8BACUAAwlVF/RGAL8AAAEuAAUUCQkWABYALhIA.',
Ry='Ryumi:BAABLgAECn8uAAILAAkJMyJbFwCKAgALAAkJMyJbFwCKAgAAAA==.Ryur:BAAALgAECgQJDgAAAA==.Ryuuki:BAABLgAECn8iAAMIAAkJDx8uAwDHAgAIAAkJeB4uAwDHAgAjAAUJvBElCgDUAAABLgAECgkJLgALADMiAA==.',
Sa='Sabastion:BAAALgAECgYJBgABLgAFFAMJBAAQAAAAAA==.Sacrickficed:BAAALgAECgQJBAABLgAECgkJLQAXAAQNAA==.Safetysham:BAAALgAECgEJAQAAAA==.Sahwe:BAABLgAECn8UAAMWAAYJnwz/aQD2AAAWAAYJnwz/aQD2AAAYAAEJ0wcemAAoAAAAAA==.Salchicha:BAAALgADCgEJAQABLgAECgcJHQAEAJoVAA==.Salmoo:BAABLgAECn8WAAISAAYJhRnSCAC2AQASAAYJhRnSCAC2AQABLgAECgcJHQAEAJoVAA==.Salocar:BAAALgAECgcJEwAAAA==.Sanafela:BAAALgADCgkJXgAAAA==.Saphisha:BAABLgAECn8UAAIfAAgJVxcIIACtAQAfAAgJVxcIIACtAQAAAA==.Sarÿna:BAAALgADCgIJAgABLgAECgkJLAAWAHIUAA==.Sasora:BAAALgAECgUJCwAAAA==.Saucemagic:BAAALgAECgcJDQAAAA==.Savonah:BAAALgAECgUJBgAAAA==.',
Sc='Scaledaddy:BAABLgAECn8jAAIlAAkJug0HKgCYAQAlAAkJug0HKgCYAQAAAA==.Scalespawn:BAAALgADCgYJBgABLgAFFAkJHwAIALoYAA==.Scaryl:BAABLgAECn8ZAAIYAAkJMgtPCwAJAQAYAAkJMgtPCwAJAQAAAA==.Scoom:BAAALgAECgMJAwAAAA==.Scourgespawn:BAACLgAFFH8fAAQIAAkJuhhWJADcAQAIAAcJPBpWJADcAQAJAAQJgxJzDAA3AQAjAAIJpwjBQwAnAAAuAAQKfyoAAwgACQmyIDMkAK0CAAgACQmyIDMkAK0CACMABAnhFXI5AK0AAAAA.',
Se='Searthenio:BAAALgAECggJCQAAAA==.Selenë:BAACLgAFFH8FAAIOAAMJDxy5CwDxAAAOAAMJDxy5CwDxAAAuAAQKfx8AAw4ABwliGOQdANYBAA4ABwliGOQdANYBABQAAQnHAX+cABYAAAAA.Sengoku:BAAALgAECgEJAQAAAA==.Seraz:BAAALgADCgkJCAAAAA==.Serbiscuit:BAAALgAECgUJDwAAAA==.Sereneya:BAAALgAECgYJCwAAAA==.Serenio:BAAALgAECgcJEQAAAA==.Serenval:BAAALgAECgUJBgAAAA==.',
Sh='Shadowshart:BAAALgAECgEJAQAAAA==.Shadus:BAAALgAECgUJBQAAAA==.Shadyaf:BAAALgAECgEJAQAAAA==.Shailora:BAAALgAECgQJAwAAAA==.Shait:BAAALgADCgYJBgAAAA==.Shalis:BAABLgAECn8sAAIGAAkJWxxzHAB6AgAGAAkJWxxzHAB6AgAAAA==.Shalora:BAAALgAECgUJBgAAAA==.Sharivee:BAABLgAECn8cAAMMAAkJ6SDgEgDpAgAMAAkJuh/gEgDpAgAhAAUJWB0pCAB3AQAAAA==.Sharko:BAABLgAECn8cAAQEAAgJExeSDwDMAQAEAAcJzhWSDwDMAQAFAAUJhBkxqQApAQAkAAIJwgOQiwBPAAAAAA==.Sharvalee:BAAALgAECgUJBQAAAA==.Shibui:BAABLgAECn9XAAQiAAkJKBvtCgB5AgAiAAkJKBvtCgB5AgALAAcJvAYvowDNAAAmAAQJQQ6RHQCvAAAAAA==.Shifthead:BAAALgAFFAEJAQABLgAFFAUJCAAGABcIAA==.Shiggles:BAABLgAECn8iAAIIAAkJEBp+KABfAgAIAAkJEBp+KABfAgABLgAFFAIJCAAFANQcAA==.Shinhaein:BAABLgAECn8jAAIMAAgJ0BP+FQArAQAMAAgJ0BP+FQArAQABLgAFFAYJHAAIAN4VAA==.Shinxu:BAAALgADCgQJBAAAAA==.Shizmael:BAABLgAECn8WAAIMAAYJDwu0IQDXAAAMAAYJDwu0IQDXAAAAAA==.Shockazilla:BAABLgAECn83AAMkAAkJbR7fCAD9AgAkAAkJbR7fCAD9AgAFAAMJVw+z/wCWAAAAAA==.Shreddarfort:BAAALgADCgkJFQAAAA==.Shönuff:BAAALgAECgEJAQAAAA==.',
Si='Sigh:BAAALgAFFAEJAQAAAA==.Silverhorn:BAABLgAECn8xAAIFAAkJ0B4WBACfAgAFAAkJ0B4WBACfAgAAAA==.',
Sk='Skoduh:BAABLgAECn8kAAIGAAkJWhoRVACnAQAGAAkJWhoRVACnAQAAAA==.Skyelene:BAABLgAECn8uAAMTAAkJyhZiFwAqAgATAAkJyhZiFwAqAgASAAcJvwa+egDvAAAAAA==.',
Sl='Slaanesh:BAABLgAECn8hAAQHAAkJ3RZaDAB5AQAaAAcJNBK9TQCxAQAHAAcJOBZaDAB5AQAZAAMJlhsqFwDFAAAAAA==.Sluggo:BAABLgAFFH8IAAIFAAYJshFGLABdAQAFAAYJshFGLABdAQAAAA==.Sluggoboyce:BAACLgAFFH8GAAICAAQJhgR9EwAHAQACAAQJhgR9EwAHAQAuAAQKfyIAAwIACAkLGSEcAEcCAAIACAnYGCEcAEcCAAYABAmEDS6aAJ8AAAAA.',
Sm='Smeagosses:BAAALgAECgEJAQAAAA==.',
So='Solace:BAABLgAECn8oAAILAAkJmR9/AgB6AgALAAkJmR9/AgB6AgAAAA==.Solinaara:BAAALgAECgQJBwAAAA==.Somalice:BAAALgAECgcJBwABLgAECgkJJwADADIKAA==.Soraka:BAABLgAFFH8LAAIVAAQJnQpWKwD2AAAVAAQJnQpWKwD2AAAAAA==.Soulstoner:BAAALgAECgEJAwAAAA==.',
Sp='Spiralist:BAABLgAECn8dAAQWAAkJ4xajTgBUAQAWAAgJfBWjTgBUAQAYAAYJARm6NwA2AQAbAAIJkAwIQwBVAAAAAA==.Spiralmist:BAAALgADCgUJBQAAAA==.Spiritdragon:BAAALgAECgEJAQAAAA==.',
St='Starge:BAAALgAECgUJBQAAAA==.Steelforged:BAAALgADCgkJEAABLgAECggJFwAfAJQTAA==.Stonedalways:BAABLgAECn8iAAMSAAkJGxAyPwCxAQASAAgJphAyPwCxAQATAAQJmgWDiwBZAAAAAA==.',
Su='Sunfuri:BAABLgAECn85AAIeAAkJDQo0NgBvAQAeAAkJDQo0NgBvAQAAAA==.Sunjan:BAAALgAECgQJBwAAAA==.Sus:BAACLgAFFH8iAAIiAAgJchpyAwABAgAiAAgJchpyAwABAgAuAAQKfyUAAiIACQmXI5cDAEcDACIACQmXI5cDAEcDAAAA.Susanoo:BAABLgAECn8bAAIeAAkJihdpJADRAQAeAAkJihdpJADRAQAAAA==.',
Sy='Sylvíadne:BAAALgAECgYJBgAAAA==.',
Sz='Szezc:BAAALgAECgEJAQAAAA==.Szul:BAAALgADCgcJDAAAAA==.',
Ta='Taalia:BAABLgAECn8XAAISAAcJxxMtCQCuAQASAAcJxxMtCQCuAQABLgAECgkJJwAWAMoIAA==.Tachima:BAAALgAECgcJEAABLgAECgkJLgALADMiAA==.Tactics:BAAALgADCgcJDAAAAA==.Tahitimango:BAABLgAECn8pAAILAAcJXQRT0gCPAAALAAcJXQRT0gCPAAAAAA==.Takeko:BAAALgADCgcJDgABLgAECgkJGgABAKYXAA==.Talanas:BAAALgADCgcJBwAAAA==.Taleria:BAAALgADCgYJIgAAAA==.Talonas:BAAALgAECgIJBAAAAA==.Tamarrion:BAAALgAECgQJBAABLgAECgkJEAAQAAAAAA==.Taranad:BAAALgAECgcJDAAAAA==.Tarathor:BAABLgAECn85AAIYAAkJvh2qAQCfAgAYAAkJvh2qAQCfAgAAAA==.Tarn:BAAALgAECgEJAQAAAA==.Tasha:BAAALgAECgEJAwABLgAECggJHwAeAO8UAA==.Tauroctony:BAABLgAECn8eAAIRAAgJKiGhBACiAgARAAgJKiGhBACiAgAAAA==.',
Te='Tea:BAABLgAECn8XAAMcAAgJKgzEIQAiAQAcAAgJKgzEIQAiAQAeAAUJFAQhfgB9AAABLgAECgkJRQAOAPYfAA==.Teknofarious:BAAALgAECgEJBAAAAA==.Tenom:BAAALgAECgUJCgAAAA==.',
Th='Thalar:BAAALgAECgIJAgAAAA==.Thaumas:BAAALgADCgEJAQAAAA==.Thelsyn:BAAALgAECgIJAgABLgAECgkJQAABAEUYAA==.Thermite:BAAALgAECgYJBgAAAA==.Thesafe:BAAALgAECgMJBQAAAA==.Thialaa:BAAALgAECgEJAwABLgAECgkJSgAGANEkAA==.Thialia:BAAALgAECgkJEwABLgAECgkJSgAGANEkAA==.Thialiaa:BAAALgAECgYJBwABLgAECgkJSgAGANEkAA==.Thoralon:BAAALgADCgEJAQAAAA==.Thorey:BAAALgAECgEJAQAAAA==.Thorgrumn:BAAALgADCgkJFQAAAA==.Thornbreaker:BAAALgADCgEJAQAAAA==.Thorthunda:BAAALgAECgQJBgAAAA==.',
Ti='Tinkabella:BAABLgAECn87AAIVAAkJLiNoAgCSAwAVAAkJLiNoAgCSAwAAAA==.Tizl:BAEALgAECgUJBQABLgAFFAgJFwAIAMMYAA==.',
Tm='Tmgwolf:BAAALgAECgYJDwAAAA==.',
To='Tobi:BAAALgADCgQJBAAAAA==.Tobiblindpaw:BAAALgAECgYJDwAAAA==.Tobinir:BAAALgADCgkJDQAAAA==.Toenailjuice:BAAALgADCgUJBQABLgAECgkJOwAXAKkjAA==.Togo:BAAALgAECgYJBgAAAA==.Torrey:BAABLgAECn8YAAIkAAgJHyVuAwA8AwAkAAgJHyVuAwA8AwAAAA==.Totemicrick:BAAALgAECgEJAgABLgAECgkJLQAXAAQNAA==.Tovarek:BAAALgADCgkJCwAAAA==.',
Tr='Trema:BAAALgAECgYJDwAAAA==.Trix:BAABLgAECn8vAAISAAgJHw1pWABVAQASAAgJHw1pWABVAQAAAA==.Trounces:BAACLgAFFH8IAAIlAAMJKBhwGwDNAAAlAAMJKBhwGwDNAAAuAAQKfyIAAiUABwkWG24EAGoBACUABwkWG24EAGoBAAAA.Truesmoke:BAAALgAECgEJAQAAAA==.',
Tu='Tulsami:BAAALgAECgIJAwAAAA==.Tulsi:BAABLgAECn88AAIoAAkJYyS0AAA+AwAoAAkJYyS0AAA+AwAAAA==.Tuskoo:BAAALgAECgcJEQAAAA==.',
Ty='Tyrathion:BAAALgAECgMJAwAAAA==.Tyronos:BAABLgAECn8hAAIFAAkJQxkNLQBMAgAFAAkJQxkNLQBMAgAAAA==.',
Uk='Uknôwnforce:BAAALgAECgMJBAAAAA==.',
Un='Unbeetable:BAAALgADCgUJBQAAAA==.',
Va='Vaeltharion:BAAALgADCgEJAQAAAA==.Valanoth:BAABLgAECn8jAAILAAgJ1SBiHQBkAgALAAgJ1SBiHQBkAgAAAA==.Valdr:BAABLgAECn8hAAMlAAkJchPRIgDEAQAlAAkJchPRIgDEAQANAAQJowzXKQDQAAAAAA==.Valoryck:BAAALgAECgQJDQABLgAECggJIwALANUgAA==.Vas:BAAALgAECgQJCgAAAA==.',
Ve='Velielina:BAAALgAECgEJAQAAAA==.Velistos:BAAALgADCgEJAQAAAA==.Vellandrias:BAAALgADCgYJBgAAAA==.Verinda:BAAALgADCgcJDwAAAA==.Vesperr:BAAALgAECgQJDAAAAA==.Vessara:BAAALgAECgEJAQABLgAFFAYJEQARAAkTAA==.Vevicenth:BAABLgAECn8VAAInAAkJ3gi7BgBEAQAnAAkJ3gi7BgBEAQAAAA==.',
Vh='Vhaidra:BAAALgAECgQJBAAAAA==.',
Vo='Voodoolily:BAAALgAECgUJBwAAAA==.Voranth:BAAALgAECgMJAwAAAA==.',
Wa='Warenio:BAAALgAECgkJCgAAAA==.Warick:BAAALgAECgMJBQAAAA==.Warpsbulge:BAACLgAFFH8gAAIMAAcJ2x1lCgDMAQAMAAcJ2x1lCgDMAQAuAAQKfxsAAwwACQlNIb4hAOwCAAwACQlNIb4hAOwCACEAAgl2FLQTAIoAAAAA.',
Wh='Whakan:BAAALgAECgEJAgABLgAECgkJJAAjAEIYAA==.Whippedtator:BAAALgAECgEJAQAAAA==.',
Wo='Wolfos:BAABLgAECn8fAAIRAAkJEiaSAABwAwARAAkJEiaSAABwAwABLgAFFAMJBQAXAOMbAA==.',
Wt='Wtfox:BAEBLgAECn8tAAMUAAkJARizAgAvAgAUAAkJARizAgAvAgAVAAQJZQJUdAA/AAAAAA==.',
Wu='Wulfgange:BAAALgADCgEJAQAAAA==.',
Wy='Wysteri:BAABLgAECn8WAAILAAcJLhLsZgBYAQALAAcJLhLsZgBYAQAAAA==.',
Xa='Xadrai:BAAALgADCgIJAgAAAA==.Xakeko:BAABLgAECn8dAAQjAAgJuRn4AwDBAQAjAAcJ/hn4AwDBAQAIAAUJsxO1rgAWAQAJAAUJlRCXHgDYAAABLgAECgkJGgABAKYXAA==.Xalatos:BAAALgAECgEJAwAAAA==.Xalfein:BAAALgAECgQJBgAAAA==.',
Xi='Xinu:BAAALgAECgcJBwABLgAECgkJRQAGANogAA==.',
Ya='Yanakana:BAAALgAECggJDAAAAA==.',
Yd='Ydalise:BAAALgAECgEJAgAAAA==.Ydrassil:BAACLgAFFH8FAAIRAAMJwRAsEwCOAAARAAMJwRAsEwCOAAAuAAQKfxYAAhEACQkdG24JAFMCABEACQkdG24JAFMCAAEuAAUUAwkGAA8ApRcA.',
Yi='Yitsuni:BAAALgAECgcJDQAAAA==.',
Za='Zakeko:BAAALgAECgQJBwABLgAECgkJGgABAKYXAA==.Zalaeda:BAAALgAECgEJAQAAAA==.Zalena:BAAALgAECgQJCAAAAA==.Zatriani:BAAALgAECgYJCgAAAA==.',
Ze='Zenus:BAABLgAECn8iAAMGAAgJsxWAVACmAQAGAAgJsxWAVACmAQACAAMJqwevNwBAAAAAAA==.Zerina:BAAALgADCgUJBQAAAA==.Zesty:BAAALgADCgMJAwAAAA==.Zeusal:BAABLgAECn8hAAIYAAcJjQ+VNgA8AQAYAAcJjQ+VNgA8AQAAAA==.Zeusinator:BAABLgAECn8sAAIGAAkJzxnyIwBTAgAGAAkJzxnyIwBTAgAAAA==.',
Zi='Zinu:BAABLgAECn9FAAIGAAkJ2iDrEwCzAgAGAAkJ2iDrEwCzAgAAAA==.Zivalisse:BAAALgAECgUJCAAAAA==.',
Zu='Zukarius:BAAALgAECgEJAQABLgAECgkJJwAkANgfAA==.Zulfionn:BAABLgAECn8oAAIGAAkJYApUWQCYAQAGAAkJYApUWQCYAQAAAA==.',
Zy='Zylah:BAAALgADCgEJAQAAAA==.',
['Áy']='Áyrá:BAABLgAECn8uAAIkAAkJGxujGABCAgAkAAkJGxujGABCAgAAAA==.',
['Åp']='Åpollyon:BAAALgAECgYJBwAAAA==.',
['Øu']='Øuroboros:BAABLgAECn8lAAQKAAgJvxnNCwAbAgAKAAcJyxrNCwAbAgANAAYJ5hp8FAChAQAlAAQJ1heQRQDHAAAAAA==.',
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
