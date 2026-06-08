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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Devourer','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Druid-Balance','Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','Priest-Shadow','Priest-Discipline','Druid-Guardian','Druid-Restoration','Monk-Mistweaver','Warlock-Affliction','Warlock-Demonology','Druid-Feral','Warrior-Protection','Unknown-Unknown','Monk-Brewmaster','Monk-Windwalker','Shaman-Enhancement','Mage-Arcane','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Evoker-Augmentation','DemonHunter-Vengeance','Warrior-Fury','Warrior-Arms','Rogue-Assassination',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abelene:BAAALgAECgQJBAAAAA==.Abrâham:BAAALgADCgUJBQAAAA==.',
Ac='Achelis:BAABLgAECn86AAMBAAkJ8CUbAQBbAwABAAkJ8CUbAQBbAwACAAEJAABJggA/AAAAAA==.',
Ad='Adianitefall:BAAALgAECgMJAwAAAA==.Adorian:BAABLgAECn8eAAIDAAcJAwkgLAAqAQADAAcJAwkgLAAqAQAAAA==.Adros:BAABLgAECn8oAAMEAAgJQRQMFQB+AQAEAAgJQRQMFQB+AQAFAAEJHwSTqwEiAAAAAA==.Adrrel:BAAALgADCgIJAgABLgAFFAgJIQAGAGQYAA==.Adrrelle:BAACLgAFFH8hAAQGAAgJZBh6EwClAQAGAAYJbRx6EwClAQABAAQJWg/kEQAtAQACAAYJaw1aEgAWAQAuAAQKfyUABAIACQncHXcTAJkCAAIACAmXH3cTAJkCAAEABAnaF2Y5AOgAAAYAAwmpEW64AFIAAAAA.',
Ae='Aelon:BAABLgAECn8cAAIFAAgJxgeTrwAkAQAFAAgJxgeTrwAkAQAAAA==.',
Ah='Aheiro:BAAALgAECgQJBgAAAA==.',
Ai='Ailaith:BAABLgAECn9GAAIGAAkJlSQPAwBZAwAGAAkJlSQPAwBZAwAAAA==.',
Ak='Akariliselle:BAABLgAECn8XAAIHAAcJwRogCQCnAQAHAAcJwRogCQCnAQAAAA==.Akarue:BAAALgAECgQJBAAAAA==.Akibafaris:BAAALgAECggJCAAAAA==.Aknologia:BAAALgAECgUJCAAAAA==.',
Al='Al:BAAALgADCggJCAAAAA==.Alan:BAAALgAECgUJCAAAAA==.Alarielle:BAAALgADCgkJEwAAAA==.Aldora:BAAALgADCgkJDAAAAA==.Alirik:BAAALgADCgQJBQAAAA==.Alleriah:BAAALgAECgcJCAABLgAECggJIwAIANUgAA==.Alydrostage:BAABLgAECn8oAAIJAAcJfAeGsQAbAQAJAAcJfAeGsQAbAQAAAA==.Alystriaz:BAABLgAECn8lAAMKAAkJPxrqBQCnAgAKAAkJPxrqBQCnAgALAAEJsQW7JwAoAAAAAA==.Alzheimerz:BAAALgAECgUJBQAAAA==.',
Am='Amaelalin:BAABLgAECn9DAAIMAAkJ9h8/BAA4AwAMAAkJ9h8/BAA4AwAAAA==.Ameliya:BAAALgAECgIJAgAAAA==.Ameng:BAAALgAECgQJBgAAAA==.',
An='Anaralyth:BAAALgAECgUJBgABLgAFFAMJCAANAKsVAA==.Andaya:BAACLgAFFH8SAAIOAAUJ+RtBEgC0AQAOAAUJ+RtBEgC0AQAuAAQKfyMAAw4ACQmrGRk5AL0BAA4ACQmrGRk5AL0BAA8AAgndDO99AGQAAAAA.Andemeli:BAABLgAECn8VAAIFAAgJygytgwBcAQAFAAgJygytgwBcAQAAAA==.Andevyn:BAAALgAECgQJBAABLgAECggJIwAIANUgAA==.Aninja:BAEALgADCgQJBAABLgAFFAUJEwAQAHYeAA==.Anivia:BAABLgAECn8fAAIJAAkJORGJUADkAQAJAAkJORGJUADkAQAAAA==.Ankoubailith:BAAALgAECgQJBgAAAA==.',
Ap='Apollon:BAAALgADCgIJAgAAAA==.',
Ar='Arandis:BAABLgAECn8eAAMRAAgJPQnoRQDuAAARAAYJ6QnoRQDuAAASAAQJkQgtUgCkAAAAAA==.Arch:BAAALgAECgQJBQAAAA==.Arcianna:BAABLgAECn8xAAMTAAkJ2B3xBQCWAgATAAkJ2B3xBQCWAgAUAAEJQRGgzAAxAAAAAA==.Arctica:BAABLgAECn8UAAIJAAYJ+grqwAADAQAJAAYJ+grqwAADAQAAAA==.Arctiq:BAAALgADCgUJCgAAAA==.Arctîc:BAABLgAECn8nAAIJAAgJ5hFuawCeAQAJAAgJ5hFuawCeAQAAAA==.Arjurn:BAABLgAECn87AAIJAAkJByCKEgDmAgAJAAkJByCKEgDmAgAAAA==.Arkro:BAAALgAECgMJBAAAAA==.Armpitbutter:BAABLgAECn87AAIVAAkJqSOdAwB1AwAVAAkJqSOdAwB1AwAAAA==.Artymiss:BAAALgAECgkJEQAAAA==.',
As='Asherah:BAABLgAECn8bAAMWAAgJhgcOFAAdAQAWAAcJeggOFAAdAQAXAAcJugGd6gB9AAAAAA==.Ashireita:BAAALgAECgYJEAABLgAECggJJgAPAG0WAA==.Ashwadawnguh:BAAALgAECgEJAQAAAA==.Astraleth:BAACLgAFFH8IAAINAAMJqxUJKgDQAAANAAMJqxUJKgDQAAAuAAQKfxgAAxMACAngFYETAKoBABMABwk9FYETAKoBAA0ABQlvFWdCAPUAAAAA.',
At='Atama:BAAALgAECgQJBwAAAA==.Atharius:BAAALgADCgEJAQAAAA==.',
Au='Aurturious:BAAALgAECgQJBAAAAA==.Authority:BAAALgAECgMJAwAAAA==.Autry:BAABLgAECn8xAAMYAAkJ1g/4DgC1AQAYAAkJ1g/4DgC1AQAUAAgJUgqBUABDAQAAAA==.',
Av='Avelina:BAAALgADCgkJFAAAAA==.Avocat:BAABLgAECn8mAAIGAAgJERsTKgArAgAGAAgJERsTKgArAgAAAA==.',
Az='Azeria:BAAALgAECgUJCQABLgAFFAgJEwAZABceAA==.Azshura:BAAALgAECgEJAQAAAA==.Azzinôth:BAAALgADCgcJBwABLgAECgEJAgAaAAAAAA==.',
Ba='Baekr:BAAALgAECgYJEAAAAA==.Baldr:BAABLgAECn8vAAIFAAkJKhOTRwDlAQAFAAkJKhOTRwDlAQAAAA==.Balgar:BAABLgAECn8YAAMGAAgJBCMsIQBWAgAGAAgJBCMsIQBWAgACAAUJyxm3PgBgAQAAAA==.Balghas:BAABLgAECn8kAAIFAAgJ1hzQMwBTAgAFAAgJ1hzQMwBTAgAAAA==.Bamz:BAAALgAFFAEJAQABLgAFFAUJEwAMAGMUAA==.Bamzhurt:BAAALgAFFAEJAgABLgAFFAUJEwAMAGMUAA==.Baumstrum:BAAALgAECgYJDQAAAA==.',
Be='Beezlbubba:BAAALgAECgUJCgAAAA==.Beldam:BAAALgADCgYJBgAAAA==.Belispeak:BAAALgADCgYJBgAAAA==.Bellaboom:BAAALgADCgYJBgAAAA==.Belvkara:BAAALgADCgkJCQAAAA==.Benedictoe:BAAALgADCgYJBgAAAA==.',
Bh='Bhozok:BAABLgAECn83AAIYAAkJvBI4DQDSAQAYAAkJvBI4DQDSAQAAAA==.',
Bi='Bint:BAAALgAECgEJAQAAAA==.',
Bl='Bloodpromise:BAAALgADCgMJAwAAAA==.Bloodrayvn:BAABLgAECn8vAAIGAAkJxR22FQCbAgAGAAkJxR22FQCbAgAAAA==.',
Bo='Boomchick:BAAALgAECgMJAwABLgAECggJGwAGAFYeAA==.Boomparapara:BAACLgAFFH8JAAIJAAMJKhOgdADnAAAJAAMJKhOgdADnAAAuAAQKfyUAAgkACQnrHp0VANECAAkACQnrHp0VANECAAAA.Borrkbuster:BAAALgAECgQJBAAAAA==.Bosta:BAAALgAECgEJAgAAAA==.Botkin:BAAALgADCgEJAQAAAA==.',
Br='Bradley:BAAALgAECgYJDgABLgAECgYJFgAMAEUjAA==.Brandywyne:BAAALgADCgEJAQAAAA==.Brenri:BAABLgAECn8cAAIPAAgJSgPHWQDHAAAPAAgJSgPHWQDHAAAAAA==.Brew:BAABLgAECn8kAAMbAAcJwB/UEgATAgAbAAcJwB/UEgATAgAcAAEJ0Q0LfQAzAAAAAA==.Brewtality:BAAALgAECgYJCQABLgAECgkJIgAUAOIdAA==.Brkat:BAAALgAECgIJAgAAAA==.Brughe:BAABLgAECn8rAAIGAAkJJQ2tXACDAQAGAAkJJQ2tXACDAQAAAA==.',
Bu='Bubbleoseven:BAAALgADCgYJBgABLgAECgkJIgAUAOIdAA==.Buttacutta:BAAALgADCgkJKwAAAA==.',
['Bä']='Bäné:BAAALgADCgIJAgAAAA==.',
Ca='Cairn:BAAALgADCgUJBQAAAA==.Caneste:BAACLgAFFH8QAAIRAAYJqhluDQB0AQARAAYJqhluDQB0AQAuAAQKfx8AAhEACQm9HfcLAMMCABEACQm9HfcLAMMCAAAA.Capela:BAAALgADCgEJAQAAAA==.Capparelli:BAAALgADCgEJAQAAAA==.Cashoe:BAAALgADCgMJAwAAAA==.Catscan:BAABLgAECn8iAAIUAAkJ4h2RDQDlAgAUAAkJ4h2RDQDlAgAAAA==.Catty:BAABLgAECn8vAAIYAAkJ/Be1BwBIAgAYAAkJ/Be1BwBIAgAAAA==.',
Cb='Cblock:BAAALgAECgUJBQABLgAFFAMJBQAdAJIIAA==.',
Ce='Celestyl:BAABLgAECn8rAAIeAAkJsgozBQB+AQAeAAkJsgozBQB+AQAAAA==.',
Ch='Charazard:BAAALgAECgUJCgABLgAECggJJQAKAL8ZAA==.Charming:BAAALgADCgMJAwAAAA==.Cheapbeer:BAABLgAECn8VAAIFAAkJVgi7zADqAAAFAAkJVgi7zADqAAAAAA==.Cheesehead:BAAALgADCggJEgAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chiforged:BAABLgAECn8UAAIcAAYJtAwcRwDWAAAcAAYJtAwcRwDWAAAAAA==.Chillybovine:BAABLgAECn8ZAAIJAAcJewmzqwAjAQAJAAcJewmzqwAjAQAAAA==.Chromstrasza:BAABLgAECn8ZAAILAAcJHxg7CQCLAQALAAcJHxg7CQCLAQAAAA==.Chudderly:BAAALgADCgEJAgAAAA==.Chudders:BAAALgADCgIJAgAAAA==.',
Ci='Cirice:BAAALgAECgEJAQAAAA==.Citrouille:BAAALgAECgEJAgAAAA==.',
Cl='Clarence:BAAALgADCgIJAgABLgAFFAgJJQAXAAMaAA==.',
Co='Conjarr:BAABLgAECn8pAAIMAAkJ/hrxGwDZAQAMAAkJ/hrxGwDZAQAAAA==.Cortisol:BAAALgADCgIJAgAAAA==.Corven:BAAALgAECgUJDAAAAA==.Cougardk:BAAALgAECgIJAgAAAA==.Cougarsixsix:BAABLgAECn8cAAIEAAYJoxbuGwAqAQAEAAYJoxbuGwAqAQAAAA==.',
Cr='Crashnburn:BAAALgADCgcJDQAAAA==.Crazyoldbear:BAABLgAECn8dAAIZAAgJ4CPRBgCSAgAZAAgJ4CPRBgCSAgAAAA==.Creideam:BAAALgADCgkJBwAAAA==.Crimos:BAABLgAECn8wAAIQAAkJzRbHPAAGAgAQAAkJzRbHPAAGAgAAAA==.Crystalliney:BAAALgADCgYJBgABLgAFFAUJEgAbAOcmAA==.',
Cy='Cynnai:BAAALgADCgYJBgAAAA==.Cyrena:BAAALgADCgEJAQAAAA==.',
Da='Daerthor:BAABLgAECn8fAAIEAAgJaxmrDgDLAQAEAAgJaxmrDgDLAQAAAA==.Dalind:BAABLgAECn8eAAIUAAcJjQbObgDeAAAUAAcJjQbObgDeAAAAAA==.Dalshiro:BAAALgAECgYJCQAAAA==.Damaclies:BAABLgAECn9FAAMXAAkJTBhePADkAQAXAAgJQBZePADkAQAHAAUJfBh+FgDjAAAAAA==.Damedolla:BAABLgAECn8fAAMIAAgJYQyleQAgAQAIAAgJwwqleQAgAQAfAAUJnw7EQAD3AAAAAA==.Dammerung:BAAALgAECgYJCAAAAA==.Darksyn:BAABLgAECn8aAAIHAAgJrAusEQAfAQAHAAgJrAusEQAfAQAAAA==.Darthbane:BAAALgAECggJEAAAAA==.Darthstroyer:BAABLgAFFH8FAAQgAAUJwgXTFQC5AAAgAAMJjgbTFQC5AAAQAAEJXQO4AQE+AAAhAAEJAAC/WQAAAAAAAA==.Darude:BAAALgADCgcJEAAAAA==.Dashoka:BAAALgAECgEJAQAAAA==.Dattiffany:BAAALgAECgUJBQAAAA==.',
De='Deadstout:BAAALgAECgQJDQAAAA==.Deathevan:BAAALgAECgYJBgABLgAECgkJLgAIADMiAA==.Deepspace:BAABLgAECn8oAAIfAAgJaCZLAwAYAwAfAAgJaCZLAwAYAwAAAA==.Deezknots:BAAALgAECggJCAAAAA==.Deezus:BAAALgADCgMJAwAAAA==.Dejagauth:BAAALgAECgYJBwABLgAECggJFQAiAKwhAA==.Dekkan:BAAALgAECgYJEAAAAA==.Demonedd:BAAALgADCgMJAgAAAA==.Demòn:BAAALgAECgEJAQAAAA==.Denounce:BAABLgAECn8YAAIjAAcJqBc8JACbAQAjAAcJqBc8JACbAQAAAA==.Desdia:BAAALgAECgcJEwAAAA==.',
Di='Dia:BAAALgAECgQJBwAAAA==.Diabetes:BAABLgAFFH8TAAIVAAYJ0BorEgDLAQAVAAYJ0BorEgDLAQAAAA==.Diastolic:BAAALgADCgUJBQAAAA==.Didyoudie:BAAALgAECggJDAAAAA==.Diend:BAABLgAECn9RAAIOAAkJgCR4AQC1AwAOAAkJgCR4AQC1AwAAAA==.Dill:BAAALgAECgEJAQABLgAECgkJOgABAPAlAA==.Dillathis:BAAALgADCgEJAQAAAA==.Discord:BAAALgAECgQJBQABLgAECggJHAAkABIgAA==.Dissonanita:BAAALgAECgcJEQAAAA==.',
Dj='Djthelock:BAABLgAECn8pAAMXAAgJihhRRADJAQAXAAcJKBVRRADJAQAHAAQJDhiiGgDGAAAAAA==.',
Do='Dormoon:BAABLgAECn8bAAMlAAgJnQ2RPABLAQAlAAgJnQ2RPABLAQAZAAEJIBFTUAAuAAAAAA==.',
Dr='Drac:BAAALgADCgYJCgAAAA==.Dragath:BAAALgAECgYJDgAAAA==.Drakur:BAAALgAECgYJCQAAAA==.Drbrad:BAABLgAECn8WAAMMAAYJRSPxFAAgAgAMAAYJRSPxFAAgAgARAAMJDhC+agBhAAAAAA==.Dreadfangs:BAAALgADCgQJBQAAAA==.Druen:BAABLgAECn8xAAIYAAkJHB4VBAC6AgAYAAkJHB4VBAC6AgAAAA==.Drunkenpo:BAABLgAECn9NAAQbAAkJ5yGDBAD2AgAbAAkJtSGDBAD2AgAVAAUJ7hOpSgAnAQAcAAEJ4yOebABpAAAAAA==.Drykin:BAAALgAECgYJBgAAAA==.Drïzl:BAEALgAECgMJAwABLgAFFAUJEwAQAHYeAA==.',
Du='Duckchow:BAAALgADCgYJBgAAAA==.Dugga:BAAALgADCgQJBAAAAA==.Duskmyre:BAABLgAECn8iAAIIAAgJXQrAcwAtAQAIAAgJXQrAcwAtAQAAAA==.',
Dw='Dwarfoo:BAABLgAECn8YAAMcAAcJKxZMPAABAQAcAAYJWxNMPAABAQAVAAIJWwjcmgBHAAAAAA==.Dweñde:BAABLgAECn8mAAIXAAkJigpKWwCHAQAXAAkJigpKWwCHAQAAAA==.',
['Dë']='Dëthmetal:BAABLgAECn8UAAIQAAUJnQxfwgD/AAAQAAUJnQxfwgD/AAAAAA==.',
Ed='Eddiemac:BAAALgAECgYJBgAAAA==.Eddrick:BAABLgAECn8tAAMFAAkJ9h3vIgBwAgAFAAkJex3vIgBwAgAEAAUJLx06GABNAQAAAA==.Edoran:BAAALgADCggJCAAAAA==.Edrani:BAAALgAECgYJDgAAAA==.',
Ei='Eilethen:BAABLgAECn8lAAIWAAkJOxpiBQAjAgAWAAkJOxpiBQAjAgAAAA==.',
Ek='Ekassa:BAAALgADCgkJCQAAAA==.',
El='Elaína:BAAALgADCgMJAwABLgAFFAUJEwAWAMUSAA==.Elementoe:BAAALgADCgEJAQABLgADCgYJBgAaAAAAAA==.Elendil:BAAALgADCgEJAQAAAA==.Elissabethh:BAAALgAECgYJEAAAAA==.Elleryn:BAAALgADCgEJAQABLgAECgYJGQAOALwXAA==.Elminstar:BAAALgADCgIJAgAAAA==.Elêctra:BAAALgAECgEJAgABLgAECggJDAAaAAAAAA==.',
Em='Employee:BAAALgAECgcJEwAAAA==.',
En='Engo:BAABLgAECn9EAAMMAAkJdiQPAwBdAwAMAAkJdCMPAwBdAwASAAkJ9BtxCADkAgAAAA==.',
Er='Eradrá:BAACLgAFFH8TAAMWAAUJxRIADwCMAAAXAAUJxRIXTgAdAQAWAAIJAQwADwCMAAAuAAQKf1AAAxYACQmzHugAAA4DABYACQmsG+gAAA4DABcACQm9GN0fAF8CAAAA.Eragon:BAAALgAECggJCQAAAA==.Erastrasza:BAAALgADCgYJCQAAAA==.Eroza:BAAALgAECgUJBgAAAA==.Ersey:BAAALgAECgQJBAABLgAFFAMJBwAUAO8HAA==.Ersèlla:BAACLgAFFH8HAAIUAAMJ7wdjRQCaAAAUAAMJ7wdjRQCaAAAuAAQKfy4AAxQACQmMGAQaAGwCABQACQmMGAQaAGwCAA0AAQnYBeeUACQAAAAA.Erysira:BAAALgADCgkJCQAAAA==.',
Et='Ethan:BAAALgAECgEJAgAAAA==.',
Eu='Eureka:BAABLgAECn8gAAMEAAkJTB2SDQDdAQAEAAcJ1RySDQDdAQAFAAcJSRk+YAClAQAAAA==.',
Ev='Evandra:BAABLgAECn8nAAIOAAgJdhrHIgAwAgAOAAgJdhrHIgAwAgAAAA==.Evanorah:BAABLgAECn8ZAAMHAAYJNwkQIAChAAAXAAYJXAgHrQDkAAAHAAYJowUQIAChAAAAAA==.',
Ex='Exïle:BAEALgAECgYJBgABLgAFFAUJEwAQAHYeAA==.',
Fa='Faelithia:BAABLgAECn8WAAIMAAYJKA5eOgAAAQAMAAYJKA5eOgAAAQAAAA==.Fatalbrew:BAAALgAECgUJCgAAAA==.',
Fe='Feldush:BAAALgADCgYJBgABLgAECggJJQAKAL8ZAA==.Felforit:BAAALgADCgQJBAAAAA==.Felis:BAAALgAECgYJCgAAAA==.Felkardio:BAAALgAECgIJAgAAAA==.Feloth:BAAALgADCgYJCQAAAA==.Ferheim:BAAALgAECgUJBQAAAA==.Ferhold:BAAALgADCgUJBQAAAA==.Ferrovax:BAAALgADCgYJBgABLgAECgkJIgAIALsXAA==.',
Fi='Fiddyone:BAABLgAECn8rAAMgAAkJySG2AgDGAgAgAAkJtCG2AgDGAgAQAAgJcR1JQQD4AQAAAA==.Figment:BAAALgADCgYJBgAAAA==.Fireburt:BAAALgADCgUJBQAAAA==.Fireslay:BAABLgAECn8YAAIiAAcJpBwHHgAmAgAiAAcJpBwHHgAmAgAAAA==.',
Fl='Flarefly:BAAALgAECgEJAQAAAA==.Flaya:BAAALgAECgUJCgAAAA==.',
Fo='Fodurzin:BAAALgAECgUJEAAAAA==.Fonta:BAAALgAECgMJAwAAAA==.Fortuna:BAAALgADCgYJBgABLgAECggJGwAGAFYeAA==.Foxingtobi:BAAALgADCgIJAgAAAA==.',
Fr='Frojio:BAABLgAECn8xAAIgAAkJ1BvsBABgAgAgAAkJ1BvsBABgAgAAAA==.Frosten:BAAALgADCgkJOQAAAA==.',
Fu='Furenio:BAABLgAECn8yAAITAAkJ7xdhDQD7AQATAAkJ7xdhDQD7AQAAAA==.',
Fy='Fyyre:BAAALgAECgUJBwAAAA==.',
Ga='Gabaghoul:BAACLgAFFH8SAAIFAAUJzBszKABVAQAFAAUJzBszKABVAQAuAAQKfzEAAgUACQl3IP8WALACAAUACQl3IP8WALACAAAA.Gaff:BAAALgAECggJEQAAAA==.Galeana:BAAALgAECgMJAwABLgAECgkJTwAJALQeAA==.Galvan:BAAALgAECgEJBAAAAA==.Gasheth:BAAALgAECgYJCwAAAA==.',
Ge='Gentyl:BAAALgAECgMJAwAAAA==.',
Gi='Giggleblast:BAAALgADCggJCgAAAA==.',
Gl='Glizzydealer:BAAALgAECgEJAQAAAA==.',
Gr='Grauth:BAAALgADCgEJAQAAAA==.Graycen:BAAALgAECgUJCQAAAA==.Grido:BAAALgADCgkJEQAAAA==.Grimbrindral:BAABLgAECn8hAAMFAAcJ5hZDZAC5AQAFAAcJdBVDZAC5AQAEAAUJghrKFwBZAQAAAA==.Grimston:BAAALgADCgMJAwABLgAECgcJIQAFAOYWAA==.Gruzaxx:BAAALgADCgUJBQAAAA==.',
Gu='Gulishdaniel:BAABLgAFFH8FAAIWAAMJGgNuDACnAAAWAAMJGgNuDACnAAABLgAFFAYJEAARAKoZAA==.',
Ha='Hadin:BAABLgAECn9LAAMJAAkJMCTXBQBRAwAJAAkJMCTXBQBRAwAeAAMJqhysDwDHAAAAAA==.Hakeko:BAAALgAECgYJDQABLgAECgcJEQAaAAAAAA==.Halalnt:BAAALgAFFAEJAQABLgAFFAIJBQAjAOkaAA==.Hanua:BAAALgADCgcJBwAAAA==.Haozhao:BAABLgAECn9KAAMTAAkJxhpxCABYAgATAAkJxhpxCABYAgAYAAEJDhTWRwA6AAAAAA==.Hawktuahz:BAAALgAECgMJAwAAAA==.Hazenpryde:BAABLgAECn8dAAITAAcJ5BqTEwCqAQATAAcJ5BqTEwCqAQAAAA==.',
He='Hearsay:BAABLgAECn8qAAMFAAgJMA9veAByAQAFAAgJMA9veAByAQAiAAIJ6wMQfQBHAAAAAA==.Hephaistian:BAAALgAECgUJBQAAAA==.Hespera:BAACLgAFFH8NAAMUAAUJlQqIJgAeAQAUAAUJlQqIJgAeAQANAAMJEgX/NACQAAAuAAQKfyMAAxQACQnJIOkYAHACABQACAmiIekYAHACAA0AAwmnFKNNAMcAAAAA.',
Hi='Hirari:BAABLgAECn8dAAMiAAYJBCU9FgBOAgAiAAYJBCU9FgBOAgAFAAEJFBoyZQFCAAAAAA==.',
Ho='Hodoor:BAAALgADCgUJBQAAAA==.Howlears:BAABLgAECn8oAAIRAAcJUgfJQAAEAQARAAcJUgfJQAAEAQAAAA==.',
Hu='Hulud:BAABLgAECn8XAAMXAAgJVRdQSQDuAQAXAAgJVRdQSQDuAQAHAAEJAABtUAAAAAAAAA==.Husbando:BAAALgAECgMJAwAAAA==.Husey:BAAALgAECgMJBgAAAA==.',
Hy='Hydrangea:BAABLgAECn8XAAIFAAcJAwwQqAAfAQAFAAcJAwwQqAAfAQAAAA==.Hydrá:BAABLgAECn8aAAIXAAkJvRYzLgAaAgAXAAkJvRYzLgAaAgAAAA==.Hylan:BAAALgADCgUJBQAAAA==.Hysgar:BAAALgADCgkJDwABLgAECggJFQAiAKwhAA==.',
Ic='Iceamaris:BAABLgAECn8gAAIPAAkJYQu2NQBTAQAPAAkJYQu2NQBTAQAAAA==.Icetiger:BAAALgAECgEJAQAAAA==.Icetigress:BAAALgAECgEJAQAAAA==.',
Ie='Iechu:BAABLgAECn8aAAMbAAgJYQ8cJgB1AQAbAAgJYQ8cJgB1AQAcAAIJ9QbJgwBFAAAAAA==.',
In='Innanna:BAAALgADCggJCgABLgAECgcJEAAaAAAAAA==.',
Is='Isoth:BAAALgAECgEJAQAAAA==.',
Iv='Ivern:BAACLgAFFH8VAAIUAAgJ+hHvBQCMAgAUAAgJ+hHvBQCMAgAuAAQKfx0AAxQABgkHHSQxANIBABQABgkHHSQxANIBAA0AAgnRB0aPACkAAAAA.Ivysnow:BAAALgAECgEJAQAAAA==.',
Ja='Jac:BAAALgAECgMJAwABLgAECggJHAAkABIgAA==.Jadenpryde:BAAALgAECgYJBgABLgAECgcJHQATAOQaAA==.Jaod:BAAALgADCgkJEQAAAA==.Jarndal:BAAALgAECgEJAQAAAA==.Jasmirrae:BAAALgAECgEJAQAAAA==.',
Jd='Jdghoul:BAAALgAECggJDwAAAA==.',
Ji='Jindrac:BAAALgAECgMJBAAAAA==.',
Jo='Jolton:BAAALgADCgYJBwABLgAECgkJLgAIADMiAA==.',
['Jà']='Jàcaranda:BAAALgAECgEJAQAAAA==.',
Ka='Kahnrah:BAAALgADCgkJDAAAAA==.Kalarae:BAAALgAECggJCAAAAA==.Kaltharion:BAAALgAFFAIJBAAAAA==.Kaluren:BAAALgAECgcJDAAAAA==.Kalurok:BAAALgAECgUJBQABLgAECgcJDAAaAAAAAA==.Kana:BAAALgAECgIJAgAAAA==.Kanade:BAABLgAECn9HAAQXAAkJBh4dFgCaAgAXAAgJ1R0dFgCaAgAWAAcJsRURCADaAQAHAAQJWAsKTACJAAAAAA==.Kantong:BAABLgAECn8gAAIcAAgJdRnxGQDVAQAcAAgJdRnxGQDVAQAAAA==.Kapp:BAAALgAECgYJEgAAAA==.Karabar:BAABLgAECn87AAMEAAkJ2yCaBACmAgAEAAkJyh6aBACmAgAFAAgJoyCNJQBkAgAAAA==.Karnnaged:BAAALgADCgYJBwAAAA==.Kasarra:BAABLgAECn8qAAIfAAkJJxSDEwDqAQAfAAkJJxSDEwDqAQAAAA==.Kayiku:BAAALgADCgkJFwAAAA==.Kazagol:BAABLgAECn87AAIIAAkJ+x0mGQB0AgAIAAkJ+x0mGQB0AgAAAA==.',
Ke='Kelintos:BAAALgAECgEJAQAAAA==.',
Kh='Khalla:BAAALgAECgkJCQAAAA==.Khamaracy:BAABLgAECn8dAAIHAAcJsQgmFwDeAAAHAAcJsQgmFwDeAAAAAA==.Khronni:BAAALgAECgYJCQAAAA==.Khrooze:BAAALgAECgYJEQAAAA==.',
Ki='Kidos:BAAALgAECgQJBgAAAA==.Kiljana:BAAALgAECgEJAQAAAA==.Kimahrí:BAABLgAECn8aAAIhAAcJMQmrMADSAAAhAAcJMQmrMADSAAAAAA==.Kittei:BAABLgAECn87AAITAAkJ1w96GQBwAQATAAkJ1w96GQBwAQAAAA==.',
Ko='Kojote:BAAALgADCgMJAQAAAA==.Kovalenko:BAAALgAECggJCwAAAA==.',
Ku='Kurick:BAABLgAECn8VAAMiAAgJrCF5BwALAwAiAAgJrCF5BwALAwAFAAEJmxXcaAE/AAAAAA==.Kurzul:BAAALgADCgEJAgAAAA==.Kusinluvin:BAAALgADCgEJAQAAAA==.',
Ky='Kyngizzard:BAABLgAECn8fAAIJAAkJSRqKMwBEAgAJAAkJSRqKMwBEAgABLgAFFAIJBQAjAOkaAA==.Kytherin:BAAALgAECgYJDAAAAA==.',
La='Lactase:BAAALgADCgMJAwAAAA==.Langtry:BAAALgADCgcJBgAAAA==.Latte:BAAALgAECgUJBQAAAA==.',
Le='Leblanc:BAAALgAECgEJAQAAAA==.Leeli:BAAALgADCgcJBwAAAA==.Lenity:BAABLgAECn82AAIDAAgJJhQbFwDWAQADAAgJJhQbFwDWAQAAAA==.Letty:BAAALgAECgQJBQAAAA==.',
Li='Liabelle:BAAALgADCgIJAgAAAA==.Lightsmite:BAAALgAECgIJAgAAAA==.Lilithene:BAAALgAECgUJBgABLgAECggJJgAPAG0WAA==.Lionbark:BAAALgADCgEJAQAAAA==.Lithpally:BAAALgADCgEJAQAAAA==.Liubeijian:BAAALgADCgYJBgABLgAECgcJEAAaAAAAAA==.',
Lo='Loan:BAAALgADCgQJAwABLgADCgkJEAAaAAAAAA==.Lokinah:BAABLgAECn8bAAIGAAgJgAakhAAoAQAGAAgJgAakhAAoAQAAAA==.Loonytusk:BAAALgADCgQJBAAAAA==.',
Lu='Lucifermadis:BAAALgAECgQJBgAAAA==.Lucoryphus:BAABLgAECn8ZAAIhAAYJgRdsIABGAQAhAAYJgRdsIABGAQAAAA==.Lukeduke:BAABLgAFFH8TAAIZAAgJFx6AAgBMAgAZAAgJFx6AAgBMAgAAAA==.Luketheduke:BAACLgAFFH8ZAAMTAAYJgR5XAwDPAQATAAUJgR5XAwDPAQAYAAEJAAAIBwA3AAAuAAQKfyoAAxMACQkvJR8BAFcDABMACQkvJR8BAFcDABgABAmxFXscAAkBAAEuAAUUCAkTABkAFx4A.Lumilia:BAAALgADCgUJBQAAAA==.Lunaries:BAAALgAECgYJBgAAAA==.Lunä:BAABLgAECn8jAAIOAAkJVBZqIgAQAgAOAAkJVBZqIgAQAgAAAA==.',
Ly='Lydia:BAABLgAECn8pAAIJAAkJphlaMQBNAgAJAAkJphlaMQBNAgAAAA==.Lynnee:BAAALgADCgEJAQAAAA==.',
['Lô']='Lôckrocks:BAABLgAECn8ZAAIHAAcJxhFiDgBJAQAHAAcJxhFiDgBJAQAAAA==.',
['Lý']='Lýsendra:BAAALgADCggJCQAAAA==.',
Ma='Magictomb:BAACLgAFFH8FAAMdAAMJkghQDgDCAAAdAAMJkghQDgDCAAAPAAEJrgE5IQA7AAAuAAQKfy4ABA8ACAmXFWA1AFUBAA8ACAmXFWA1AFUBAA4ABgnpDQl2AOsAAB0ABQnACEUgAOQAAAAA.Mahdude:BAAALgAECgEJAQAAAA==.Malastor:BAAALgAECgEJAQABLgAECggJHAAkABIgAA==.Malcontent:BAAALgAECgQJBQABLgAECggJHAAkABIgAA==.Maldazane:BAAALgADCgYJCwAAAA==.Malfeasance:BAAALgADCgkJDQABLgAECggJHAAkABIgAA==.Malidan:BAAALgADCgMJAwAAAA==.Malifel:BAABLgAECn8cAAMkAAgJEiBsBABsAgAkAAgJEiBsBABsAgAIAAEJUAcTIAEhAAAAAA==.Maliss:BAABLgAECn8+AAQBAAkJRRhnEgASAgABAAkJahdnEgASAgACAAQJ8RG1HwCmAAAGAAEJoxFSHgE3AAAAAA==.Mallord:BAAALgAECgYJDgABLgAECggJHAAkABIgAA==.Mandarin:BAABLgAECn81AAIUAAkJPRmIFQCSAgAUAAkJPRmIFQCSAgAAAA==.Manmythlegnd:BAAALgADCgYJBgAAAA==.Mannik:BAABLgAECn8aAAIXAAgJrRmHLwAVAgAXAAgJrRmHLwAVAgAAAA==.Marashade:BAAALgADCgQJBAAAAA==.Marashades:BAAALgAECgQJBAABLgAECggJHQAZAOAjAA==.',
Mc='Mcbadden:BAAALgAECgYJCAAAAA==.',
Me='Meditatetoe:BAAALgADCgIJAgABLgADCgYJBgAaAAAAAA==.Melissà:BAAALgADCgMJAwAAAA==.Menesta:BAAALgADCgcJBwABLgAECgUJEAAaAAAAAA==.Mercia:BAABLgAECn8vAAIEAAkJExvLCAA6AgAEAAkJExvLCAA6AgAAAA==.Merekoma:BAABLgAECn8iAAMIAAkJuxeQMgDwAQAIAAkJZBOQMgDwAQAkAAQJFhZqGwCyAAAAAA==.',
Mi='Milarra:BAAALgAECgcJDwAAAA==.Milhouse:BAAALgAECgYJEgAAAA==.Minalan:BAAALgADCgYJCgABLgAECgYJEQAaAAAAAA==.Mingonashoba:BAABLgAECn8dAAIGAAkJwg0KQQDTAQAGAAkJwg0KQQDTAQAAAA==.Miragosa:BAABLgAECn8tAAMKAAkJYg4xEADAAQAKAAkJYg4xEADAAQALAAcJ3gg5DwALAQAAAA==.Misschris:BAABLgAECn8lAAIVAAgJBQuMSgAoAQAVAAgJBQuMSgAoAQAAAA==.Mizu:BAAALgAECgUJBQAAAA==.',
Mo='Moadeed:BAAALgAECgkJEQAAAA==.Mooluv:BAAALgADCgcJCgAAAA==.Moonstrike:BAAALgAECgIJAgAAAA==.Mordrius:BAAALgADCgYJBgAAAA==.Morphmious:BAAALgAECgcJBwAAAA==.Mortesque:BAAALgAECgcJEgAAAA==.',
Mu='Muttblitzed:BAABLgAECn8VAAIGAAYJ3xRmbwBWAQAGAAYJ3xRmbwBWAQAAAA==.Muttskî:BAAALgAECgMJAwAAAA==.',
My='Mybutt:BAAALgAECgMJBgAAAA==.Myrothos:BAAALgADCgEJAQAAAA==.Myrrh:BAABLgAECn8YAAMjAAYJdAdpXAC4AAAjAAYJggZpXAC4AAALAAQJ9wYzLQCxAAAAAA==.Mythris:BAAALgAECgkJBQAAAA==.',
['Mí']='Místermage:BAAALgAECgQJCAAAAA==.',
Na='Nadrael:BAAALgAECgEJAQAAAA==.Nasturtium:BAAALgADCgYJDgAAAA==.Naturestone:BAAALgAFFAIJAgABLgAFFAMJBQAdAJIIAA==.Nausican:BAABLgAECn9DAAIgAAkJfxndBABiAgAgAAkJfxndBABiAgAAAA==.Nazuhda:BAAALgADCgEJAQAAAA==.',
Ne='Necrosector:BAACLgAFFH8FAAIFAAQJ+AftUAD8AAAFAAQJ+AftUAD8AAAuAAQKfyYAAgUACAm5Gd9JAN4BAAUACAm5Gd9JAN4BAAAA.Necrotherys:BAABLgAECn82AAIIAAkJPhyiFgCFAgAIAAkJPhyiFgCFAgAAAA==.Nelandra:BAABLgAECn8eAAIRAAcJExyJGQDyAQARAAcJExyJGQDyAQAAAA==.',
Ni='Nicklaus:BAABLgAECn8iAAIDAAcJhQkdLQAiAQADAAcJhQkdLQAiAQAAAA==.Nilrem:BAAALgADCgIJAgAAAA==.Ninelives:BAAALgAECgYJDgAAAA==.Ninjadk:BAECLgAFFH8TAAMQAAUJdh6/RABYAQAQAAQJdh6/RABYAQAhAAEJAABjWwAAAAAuAAQKfzEAAxAACQmyIYINAPkCABAACQmyIYINAPkCACAAAQm4G1IyAEAAAAAA.',
No='Nocapongfrfr:BAAALgAECgMJAwABLgAFFAUJBQAgAMIFAA==.Nomahuata:BAABLgAECn9IAAIPAAkJyhj2EwA/AgAPAAkJyhj2EwA/AgAAAA==.Nordre:BAAALgAECgMJAwAAAA==.',
Nu='Nufrus:BAAALgAECgEJAQAAAA==.',
Ny='Nyeli:BAAALgAECgMJBAABLgAECgYJGQAOALwXAA==.Nyxi:BAABLgAECn8YAAIOAAYJ7xsGMwDZAQAOAAYJ7xsGMwDZAQAAAA==.Nyxlee:BAAALgAECgcJBwAAAA==.',
['Né']='Néo:BAAALgAECgUJCAAAAA==.',
['Nó']='Nóóôööôòòpe:BAAALgAFFAQJBAABLgAFFAUJBQAgAMIFAA==.',
Og='Ogdruid:BAAALgADCgcJDgAAAA==.',
Ok='Okume:BAAALgAECgIJAgAAAA==.',
Ol='Olympian:BAAALgADCgcJBwAAAA==.',
Om='Omanyte:BAAALgADCgcJBwAAAA==.',
On='Onefiftyone:BAABLgAECn8bAAMdAAYJHCVtCQAaAgAdAAYJHCVtCQAaAgAOAAIJnSTFggDIAAABLgAECgkJKwAgAMkhAA==.',
Or='Orruk:BAAALgADCgMJAwAAAA==.Orwyn:BAAALgADCgkJEgAAAA==.',
Ov='Overdose:BAAALgADCgMJAwAAAA==.',
Pa='Padmé:BAAALgAECgQJBgAAAA==.Pain:BAAALgAECgUJCwAAAA==.Palanas:BAAALgAFFAEJAQAAAA==.Pallamoo:BAAALgAECgUJBgAAAA==.Palochka:BAAALgAECgYJBgAAAA==.Paradots:BAABLgAECn8WAAIKAAYJwBrtEQChAQAKAAYJwBrtEQChAQABLgAECgkJIgAUAOIdAA==.Paranitis:BAAALgAECggJDAAAAA==.Paranorm:BAAALgADCgEJAQAAAA==.Paraparaboom:BAAALgAECgUJBQABLgAFFAMJCQAJACoTAA==.',
Pe='Petronella:BAABLgAECn9GAAMmAAkJmw9sFQCoAQAmAAkJmw9sFQCoAQAlAAQJ+wNjgwCxAAAAAA==.Pezdormu:BAAALgADCgIJAgAAAA==.Pezmage:BAAALgAECgIJBAAAAA==.',
Ph='Phatboi:BAAALgAECgEJAgAAAA==.Pheroth:BAAALgAECgQJBAABLgAECggJGgAHAKwLAA==.',
Pi='Pixystix:BAABLgAECn8hAAIIAAcJ2BlgPwC/AQAIAAcJ2BlgPwC/AQAAAA==.',
Po='Poisonspain:BAAALgAECgMJAwAAAA==.Popsdh:BAAALgAECggJEwABLgAECgkJIAAEAEwdAA==.Portlukk:BAAALgADCgEJAQABLgAFFAQJDwAGAKEZAA==.Potscold:BAACLgAFFH8QAAIJAAgJARaGDAC5AQAJAAgJARaGDAC5AQAuAAQKf0EAAgkACAnbJbsRAD0DAAkACAnbJbsRAD0DAAAA.Poxi:BAAALgAECgIJAgABLgAECggJGAAJADwdAA==.',
Pr='Prion:BAABLgAECn8cAAIlAAgJexQdKACzAQAlAAgJexQdKACzAQAAAA==.',
Pu='Pull:BAABLgAECn8jAAITAAkJnxtBCQBFAgATAAkJnxtBCQBFAgAAAA==.',
Ra='Radioshack:BAAALgADCggJCAAAAA==.Radkemonko:BAAALgAECgcJDwAAAA==.Raega:BAAALgADCgYJBgAAAA==.Ragerlock:BAAALgADCgEJAQAAAA==.Raivel:BAABLgAECn8ZAAIOAAYJvBcyQwCTAQAOAAYJvBcyQwCTAQAAAA==.Raldaron:BAAALgADCgEJAQAAAA==.Rambogg:BAAALgADCgcJBwABLgAFFAYJGgAJAIMTAA==.Raneyth:BAAALgAECgYJBgAAAA==.Ranith:BAAALgADCgMJAwAAAA==.Ravagèr:BAAALgAECgEJAgAAAA==.',
Rd='Rdbwarrior:BAAALgADCgUJBQAAAA==.',
Re='Redemus:BAAALgADCgEJAQAAAA==.Redwinetoast:BAABLgAECn8cAAIXAAgJZAQ+rQDjAAAXAAgJZAQ+rQDjAAAAAA==.Rekllaw:BAAALgAECgEJAQAAAA==.Reliala:BAAALgADCgkJEQAAAA==.Reno:BAAALgADCgkJEAAAAA==.Reshyk:BAAALgAECggJEgAAAA==.Resles:BAAALgAECgEJAQAAAA==.Respectwomen:BAAALgADCgEJAQABLgAECgQJBAAaAAAAAA==.',
Rh='Rhobes:BAAALgAECgcJDQAAAA==.Rhondta:BAABLgAECn8fAAIXAAgJKRBuYAB7AQAXAAgJKRBuYAB7AQAAAA==.',
Ri='Rickormortis:BAAALgAECggJEQABLgAECggJJQAVAAULAA==.Rictus:BAABLgAECn8wAAIJAAkJjSRvBwA/AwAJAAkJjSRvBwA/AwAAAA==.Ringmasterr:BAAALgADCgUJBQAAAA==.Riordaa:BAAALgADCgYJDAAAAA==.Risingdragon:BAABLgAECn8qAAIcAAcJMhNuKwBUAQAcAAcJMhNuKwBUAQAAAA==.',
Ro='Roades:BAAALgADCgcJDAAAAA==.Roboskritch:BAAALgADCgUJBQAAAA==.Ronaj:BAAALgADCgMJBAAAAA==.Royveer:BAAALgADCgYJCQAAAA==.',
Ru='Rumor:BAABLgAECn8eAAQYAAgJhRRIEwB4AQAYAAcJrBNIEwB4AQAUAAYJNArpbwDbAAATAAMJlww1VABVAAABLgAECggJKgAFADAPAA==.Rurry:BAACLgAFFH8YAAIKAAYJpRe+BACuAQAKAAYJpRe+BACuAQAuAAQKfy4ABAoACQnIIrECAEADAAoACQnIIrECAEADAAsABQm6GR4WAI8BACMAAwlVF/RGAL8AAAEuAAUUCAkVABQA+hEA.',
Ry='Ryumi:BAABLgAECn8uAAIIAAkJMyLzFQCLAgAIAAkJMyLzFQCLAgAAAA==.Ryur:BAAALgAECgQJDgAAAA==.',
Sa='Sabastion:BAAALgAECgYJBgABLgAECggJHAAkABIgAA==.Sacrickficed:BAAALgAECgQJBAABLgAECggJJQAVAAULAA==.Sahwe:BAABLgAECn8UAAMUAAYJnwwwZwD1AAAUAAYJnwwwZwD1AAANAAEJ0wcAkAAoAAAAAA==.Salocar:BAAALgAECgcJEwAAAA==.Sanafela:BAAALgADCgkJQwAAAA==.Saphisha:BAAALgAECgcJEQAAAA==.Sasora:BAAALgAECgUJCwAAAA==.Saucemagic:BAAALgAECgcJDQAAAA==.Savonah:BAAALgAECgEJAQAAAA==.',
Sc='Scaledaddy:BAABLgAECn8jAAIjAAkJug08JwCfAQAjAAkJug08JwCfAQAAAA==.Scalespawn:BAAALgADCgYJBgABLgAFFAgJHgAQAEwZAA==.Scaryl:BAAALgAECgYJCgAAAA==.Scourgespawn:BAACLgAFFH8eAAQQAAgJTBkTGwDpAQAQAAYJJhsTGwDpAQAgAAQJgxLpCQA4AQAhAAIJpwhbPQAoAAAuAAQKfyoAAxAACQmyIDMkAK0CABAACQmyIDMkAK0CACEABAnhFXY2ALEAAAAA.',
Se='Selenë:BAABLgAECn8YAAMMAAcJohXpHQDIAQAMAAcJohXpHQDIAQARAAEJxwFkkgAWAAAAAA==.Sengoku:BAAALgAECgEJAQAAAA==.Serbiscuit:BAAALgAECgUJCgAAAA==.Sereneya:BAAALgAECgYJBgAAAA==.Serenio:BAAALgAECgcJEQAAAA==.Serenval:BAAALgADCgkJCQAAAA==.',
Sh='Shadowshart:BAAALgAECgEJAQAAAA==.Shailora:BAAALgAECgMJAwAAAA==.Shait:BAAALgADCgYJBgAAAA==.Shalis:BAABLgAECn8kAAIGAAgJahxjKQAtAgAGAAgJahxjKQAtAgAAAA==.Sharivee:BAABLgAECn8ZAAMJAAgJCSGZIgCNAgAJAAgJrx+ZIgCNAgAeAAUJWB0pCAB3AQAAAA==.Sharko:BAABLgAECn8cAAQEAAgJExeSDwDMAQAEAAcJzhWSDwDMAQAFAAUJhBkTnwAtAQAiAAIJwgOQiwBPAAAAAA==.Shibui:BAABLgAECn9LAAQfAAkJSBpYCwBiAgAfAAkJSBpYCwBiAgAIAAcJvAYvowDNAAAkAAQJQQ7PGwCvAAAAAA==.Shiggles:BAABLgAECn8hAAIQAAkJEBqhJQBlAgAQAAkJEBqhJQBlAgABLgAFFAIJBQAFAHUVAA==.Shinhaein:BAABLgAECn8UAAIJAAYJ2BSRsAB8AQAJAAYJ2BSRsAB8AQABLgAFFAUJFwAQAAMaAA==.Shinxu:BAAALgADCgQJBAAAAA==.Shizmael:BAAALgAECgEJAQAAAA==.Shockazilla:BAABLgAECn82AAMiAAkJbR4RCAAAAwAiAAkJbR4RCAAAAwAFAAMJVw+z/wCWAAAAAA==.Shreddarfort:BAAALgADCgkJFQAAAA==.Shönuff:BAAALgAECgEJAQAAAA==.',
Si='Sigh:BAAALgAFFAEJAQAAAA==.Silverhorn:BAABLgAECn8kAAIFAAcJNxyLSADiAQAFAAcJNxyLSADiAQAAAA==.',
Sk='Skoduh:BAABLgAECn8hAAIGAAcJQhwcTQCuAQAGAAcJQhwcTQCuAQAAAA==.Skyelene:BAABLgAECn8mAAMPAAgJbRbTIADPAQAPAAgJbRbTIADPAQAOAAcJvwYAdADwAAAAAA==.',
Sl='Slaanesh:BAABLgAECn8ZAAQHAAgJnhaiCwB3AQAHAAcJ7hWiCwB3AQAWAAMJlhsqFwDFAAAXAAMJzw471ACkAAAAAA==.Sluggo:BAABLgAFFH8HAAIFAAUJzxG3JABhAQAFAAUJzxG3JABhAQAAAA==.Sluggoboyce:BAACLgAFFH8GAAICAAQJhgR9EwAHAQACAAQJhgR9EwAHAQAuAAQKfyIAAwIACAkLGSEcAEcCAAIACAnYGCEcAEcCAAYABAmEDS6aAJ8AAAAA.',
Sm='Smeagosses:BAAALgAECgEJAQAAAA==.Smokeü:BAAALgAECgcJBwAAAA==.',
So='Solace:BAAALgAECgcJEwAAAA==.Solinaara:BAAALgAECgQJBAAAAA==.Soraka:BAABLgAFFH8KAAISAAQJnQqHJgD6AAASAAQJnQqHJgD6AAAAAA==.',
Sp='Spiralist:BAABLgAECn8dAAQUAAkJ4xbpSwBVAQAUAAgJfBXpSwBVAQANAAYJARngNAA2AQAYAAIJkAwtPQBVAAAAAA==.Spiralmist:BAAALgADCgUJBQAAAA==.',
St='Starge:BAAALgAECgUJBQAAAA==.Steelforged:BAAALgADCgcJBwABLgAECgYJFAAcALQMAA==.Stonedalways:BAABLgAECn8cAAMOAAcJ5hbYTgBnAQAOAAYJaxTYTgBnAQAPAAMJvQQtgwBZAAAAAA==.',
Su='Sunfuri:BAABLgAECn85AAIlAAkJDQofMgB8AQAlAAkJDQofMgB8AQAAAA==.Sunjan:BAAALgAECgQJBwAAAA==.Sus:BAACLgAFFH8hAAIfAAcJ7RseAgAaAgAfAAcJ7RseAgAaAgAuAAQKfyUAAh8ACQmXI5cDAEcDAB8ACQmXI5cDAEcDAAAA.Susanoo:BAABLgAECn8ZAAIlAAkJcRSOIgDXAQAlAAkJcRSOIgDXAQAAAA==.',
Sy='Sylvíadne:BAAALgAECgYJBgAAAA==.',
Sz='Szul:BAAALgADCgcJDAAAAA==.',
Ta='Tachima:BAAALgAECgcJEAABLgAECgkJLgAIADMiAA==.Tactics:BAAALgADCgcJDAAAAA==.Tahitimango:BAABLgAECn8gAAIIAAYJjQMdyACOAAAIAAYJjQMdyACOAAAAAA==.Takeko:BAAALgADCgcJDgABLgAECgcJEQAaAAAAAA==.Talanas:BAAALgADCgcJBwAAAA==.Taleria:BAAALgADCgYJGgAAAA==.Taranad:BAAALgAECgcJDAAAAA==.Tarathor:BAABLgAECn8eAAINAAcJrBp2HQDPAQANAAcJrBp2HQDPAQAAAA==.Tasha:BAAALgAECgEJAwABLgAECggJHAAlAHsUAA==.Tauroctony:BAABLgAECn8eAAITAAgJKiGhBACiAgATAAgJKiGhBACiAgAAAA==.',
Te='Tea:BAAALgAECggJEgABLgAECgkJQwAMAPYfAA==.Teknofarious:BAAALgAECgEJAwAAAA==.Tenom:BAAALgAECgUJCgAAAA==.',
Th='Thalar:BAAALgAECgIJAgAAAA==.Thaumas:BAAALgADCgEJAQAAAA==.Thelsyn:BAAALgAECgIJAgABLgAECgkJPgABAEUYAA==.Thermite:BAAALgAECgYJBgAAAA==.Thesafe:BAAALgAECgMJAwAAAA==.Thialaa:BAAALgAECgEJAwABLgAECgkJRgAGAJUkAA==.Thialia:BAAALgAECgkJEwABLgAECgkJRgAGAJUkAA==.Thialiaa:BAAALgAECgYJBwABLgAECgkJRgAGAJUkAA==.Thorey:BAAALgAECgEJAQAAAA==.Thornbreaker:BAAALgADCgEJAQAAAA==.Thorthunda:BAAALgAECgQJBgAAAA==.',
Ti='Tinkabella:BAABLgAECn87AAISAAkJLiMeAgCYAwASAAkJLiMeAgCYAwAAAA==.Tizl:BAEALgAECgUJBQABLgAFFAUJEwAQAHYeAA==.',
To='Tobiblindpaw:BAAALgAECgYJDwAAAA==.Toenailjuice:BAAALgADCgUJBQABLgAECgkJOwAVAKkjAA==.Torrey:BAABLgAECn8YAAIiAAgJHyVuAwA8AwAiAAgJHyVuAwA8AwAAAA==.',
Tr='Trema:BAAALgAECgEJAgAAAA==.Trix:BAABLgAECn8vAAIOAAgJHw3gUwBVAQAOAAgJHw3gUwBVAQAAAA==.',
Tu='Tulsami:BAAALgAECgIJAwAAAA==.Tulsi:BAABLgAECn88AAInAAkJYySgAABBAwAnAAkJYySgAABBAwAAAA==.Tuskoo:BAAALgAECgcJEQAAAA==.',
Ty='Tyrathion:BAAALgAECgMJAwAAAA==.Tyronos:BAABLgAECn8gAAIFAAgJexilQQD3AQAFAAgJexilQQD3AQAAAA==.',
Uk='Uknôwnforce:BAAALgAECgMJBAAAAA==.',
Un='Unbeetable:BAAALgADCgUJBQAAAA==.',
Va='Valanoth:BAABLgAECn8jAAIIAAgJ1SCsGwBkAgAIAAgJ1SCsGwBkAgAAAA==.Valdr:BAABLgAECn8eAAMjAAgJQRLKKwCGAQAjAAgJQRLKKwCGAQALAAQJowzXKQDQAAAAAA==.Valoryck:BAAALgAECgQJDQABLgAECggJIwAIANUgAA==.Vas:BAAALgAECgMJAwAAAA==.',
Ve='Velielina:BAAALgAECgEJAQAAAA==.Velistos:BAAALgADCgEJAQAAAA==.Vellandrias:BAAALgADCgYJBgAAAA==.Verinda:BAAALgADCgcJDwAAAA==.Vessara:BAAALgAECgEJAQABLgAFFAMJCAANAKsVAA==.Vevicenth:BAAALgAECgkJEgAAAA==.',
Vo='Voranth:BAAALgADCgMJAwAAAA==.',
Wa='Warpsbulge:BAACLgAFFH8gAAIJAAcJ2x3YEQBBAgAJAAcJ2x3YEQBBAgAuAAQKfxsAAwkACQlNIb4hAOwCAAkACQlNIb4hAOwCAB4AAgl2FLQTAIoAAAAA.',
Wh='Whakan:BAAALgAECgEJAgABLgAECgYJGQAhAIEXAA==.',
Wo='Wolfos:BAABLgAECn8fAAITAAkJEiZ1AAByAwATAAkJEiZ1AAByAwAAAA==.',
Wt='Wtfox:BAEBLgAECn8VAAMRAAcJEQ7JPgANAQARAAYJgRDJPgANAQASAAQJZQJoawBBAAAAAA==.',
Wu='Wulfgange:BAAALgADCgEJAQAAAA==.',
Wy='Wysteri:BAAALgAECgcJEAAAAA==.',
Xa='Xadrai:BAAALgADCgIJAgAAAA==.Xakeko:BAAALgAECgcJEQAAAA==.Xalatos:BAAALgAECgEJAgAAAA==.Xalfein:BAAALgAECgQJBAAAAA==.',
Xi='Xinu:BAAALgAECgcJBwABLgAECgkJQwAGANgfAA==.',
Ya='Yanakana:BAAALgAECgYJBgAAAA==.',
Yd='Ydalise:BAAALgAECgEJAgAAAA==.Ydrassil:BAABLgAECn8VAAITAAkJcxqnCABTAgATAAkJcxqnCABTAgABLgAECgkJIAAEAEwdAA==.',
Yi='Yitsuni:BAAALgAECgcJDQAAAA==.',
Za='Zalaeda:BAAALgAECgEJAQAAAA==.Zalena:BAAALgAECgQJCAAAAA==.Zatriani:BAAALgAECgYJCgAAAA==.',
Ze='Zenus:BAABLgAECn8iAAMGAAgJsxXNTQCsAQAGAAgJsxXNTQCsAQACAAMJqwfTNABAAAAAAA==.Zerina:BAAALgADCgUJBQAAAA==.Zesty:BAAALgADCgMJAwAAAA==.Zeusal:BAABLgAECn8hAAINAAcJjQ/EMwA8AQANAAcJjQ/EMwA8AQAAAA==.Zeusinator:BAABLgAECn8rAAIGAAkJzxmnIABZAgAGAAkJzxmnIABZAgAAAA==.',
Zi='Zinu:BAABLgAECn9DAAIGAAkJ2B+7EwCpAgAGAAkJ2B+7EwCpAgAAAA==.Zivalisse:BAAALgAECgUJBwAAAA==.',
Zu='Zulfionn:BAABLgAECn8oAAIGAAkJYAqFUgCeAQAGAAkJYAqFUgCeAQAAAA==.',
Zy='Zylah:BAAALgADCgEJAQAAAA==.',
['Áy']='Áyrá:BAABLgAECn8mAAIiAAgJohu1HQAKAgAiAAgJohu1HQAKAgAAAA==.',
['Åp']='Åpollyon:BAAALgAECgYJBwAAAA==.',
['Øu']='Øuroboros:BAABLgAECn8lAAQKAAgJvxlhCwAdAgAKAAcJyxphCwAdAgALAAYJ5hp8FAChAQAjAAQJ1heQRQDHAAAAAA==.',
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
