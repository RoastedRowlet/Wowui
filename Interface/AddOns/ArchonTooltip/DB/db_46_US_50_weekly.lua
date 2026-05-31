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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Devourer','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Druid-Balance','Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','Priest-Shadow','Priest-Discipline','Druid-Guardian','Druid-Restoration','Monk-Mistweaver','Warlock-Affliction','Warlock-Demonology','Druid-Feral','Warrior-Protection','Unknown-Unknown','Monk-Brewmaster','Monk-Windwalker','Mage-Arcane','DemonHunter-Havoc','Paladin-Holy','Evoker-Augmentation','DemonHunter-Vengeance','Warrior-Fury','DeathKnight-Frost','DeathKnight-Blood','Shaman-Enhancement','Warrior-Arms','Rogue-Assassination',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abelene:BAAALgAECgQJBAAAAA==.Abrâham:BAAALgADCgUJBQAAAA==.',
Ac='Achelis:BAABLgAECn86AAMBAAkJ8CXfAABfAwABAAkJ8CXfAABfAwACAAEJAABJggA/AAAAAA==.',
Ad='Adianitefall:BAAALgAECgIJAgAAAA==.Adorian:BAABLgAECn8cAAIDAAYJ/QnRLwAEAQADAAYJ/QnRLwAEAQAAAA==.Adros:BAABLgAECn8oAAMEAAgJQRQMFQB+AQAEAAgJQRQMFQB+AQAFAAEJHwRhlwEiAAAAAA==.Adrrel:BAAALgADCgIJAgABLgAFFAcJHQAGACkbAA==.Adrrelle:BAACLgAFFH8dAAMGAAcJKRs9DgCpAQAGAAYJbRw9DgCpAQACAAYJaw0YFAD3AAAuAAQKfyUABAIACQncHXcTAJkCAAIACAmXH3cTAJkCAAEABAnaFx03AOgAAAYAAwmpEW64AFIAAAAA.',
Ae='Aelon:BAABLgAECn8cAAIFAAgJxgeTrwAkAQAFAAgJxgeTrwAkAQAAAA==.',
Ah='Aheiro:BAAALgAECgQJBQAAAA==.',
Ai='Ailaith:BAABLgAECn85AAIGAAkJrCD7DgDFAgAGAAkJrCD7DgDFAgAAAA==.',
Ak='Akariliselle:BAABLgAECn8WAAIHAAcJMBopCQCaAQAHAAcJMBopCQCaAQAAAA==.Akarue:BAAALgAECgQJBAAAAA==.Akibafaris:BAAALgAECggJCAAAAA==.Aknologia:BAAALgAECgUJCAAAAA==.',
Al='Al:BAAALgADCggJCAAAAA==.Alan:BAAALgAECgQJBwAAAA==.Alarielle:BAAALgADCgkJEwAAAA==.Aldora:BAAALgADCgkJDAAAAA==.Alirik:BAAALgADCgQJBQAAAA==.Alleriah:BAAALgAECgcJCAABLgAECggJIwAIANUgAA==.Alydrostage:BAABLgAECn8oAAIJAAcJfAeHsAAFAQAJAAcJfAeHsAAFAQAAAA==.Alystriaz:BAABLgAECn8lAAMKAAkJPxqcBQCnAgAKAAkJPxqcBQCnAgALAAEJsQXBJQAqAAAAAA==.Alzheimerz:BAAALgAECgUJBQAAAA==.',
Am='Amaelalin:BAABLgAECn86AAIMAAkJfhuXCQC5AgAMAAkJfhuXCQC5AgAAAA==.Ameliya:BAAALgAECgIJAgAAAA==.Ameng:BAAALgAECgQJBgAAAA==.',
An='Anaralyth:BAAALgAECgUJBgABLgAFFAMJBQANAMITAA==.Andaya:BAACLgAFFH8NAAIOAAQJfiIQFgCGAQAOAAQJfiIQFgCGAQAuAAQKfyMAAw4ACQmrGZQ1AL8BAA4ACQmrGZQ1AL8BAA8AAgndDFd3AGUAAAAA.Andemeli:BAAALgAECggJDwAAAA==.Andevyn:BAAALgAECgQJBAABLgAECggJIwAIANUgAA==.Aninja:BAEALgADCgQJBAABLgAFFAUJEAAQADEaAA==.Anivia:BAABLgAECn8fAAIJAAkJORH5SwDgAQAJAAkJORH5SwDgAQAAAA==.Ankoubailith:BAAALgAECgQJBgAAAA==.',
Ap='Apollon:BAAALgADCgIJAgAAAA==.',
Ar='Arandis:BAABLgAECn8dAAMRAAcJGwmLRADWAAARAAYJ6QmLRADWAAASAAMJegc+VAB7AAAAAA==.Arch:BAAALgAECgQJBQAAAA==.Arcianna:BAABLgAECn8xAAMTAAkJ2B1YBQCZAgATAAkJ2B1YBQCZAgAUAAEJQRFyxgAxAAAAAA==.Arctica:BAABLgAECn8UAAIJAAYJ+gqIvwDsAAAJAAYJ+gqIvwDsAAAAAA==.Arctiq:BAAALgADCgUJCgAAAA==.Arctîc:BAABLgAECn8nAAIJAAgJ5hEUZgCYAQAJAAgJ5hEUZgCYAQAAAA==.Arjurn:BAABLgAECn87AAIJAAkJByABEQDhAgAJAAkJByABEQDhAgAAAA==.Arkro:BAAALgAECgMJBAAAAA==.Armpitbutter:BAABLgAECn87AAIVAAkJqSMpAwB2AwAVAAkJqSMpAwB2AwAAAA==.Artymiss:BAAALgAECggJCwAAAA==.',
As='Asherah:BAABLgAECn8VAAMWAAgJ1wZKEwAUAQAWAAcJrQdKEwAUAQAXAAcJugF84gCAAAAAAA==.Ashireita:BAAALgAECgYJEAABLgAECgcJHQAOALEGAA==.Ashwadawnguh:BAAALgAECgEJAQAAAA==.Astraleth:BAACLgAFFH8FAAINAAMJwhN+KADBAAANAAMJwhN+KADBAAAuAAQKfxUAAxMACAmRFWYSAKcBABMABwntFGYSAKcBAA0ABQlvFQdAAPIAAAAA.',
At='Atama:BAAALgAECgQJBwAAAA==.Atharius:BAAALgADCgEJAQAAAA==.',
Au='Aurturious:BAAALgAECgQJBAAAAA==.Authority:BAAALgAECgMJAwAAAA==.Autry:BAABLgAECn8xAAMYAAkJ1g/UDQC1AQAYAAkJ1g/UDQC1AQAUAAgJUgq0TQBFAQAAAA==.',
Av='Avelina:BAAALgADCgcJDgAAAA==.Avocat:BAABLgAECn8kAAIGAAcJbRs0OADmAQAGAAcJbRs0OADmAQAAAA==.',
Az='Azeria:BAAALgAECgUJCQABLgAFFAcJDwAZAB8dAA==.Azshura:BAAALgADCgYJCQAAAA==.Azzinôth:BAAALgADCgcJBwABLgAECgEJAgAaAAAAAA==.',
Ba='Baekr:BAAALgAECgYJEAAAAA==.Baldr:BAABLgAECn8vAAIFAAkJKhNVRADhAQAFAAkJKhNVRADhAQAAAA==.Balgar:BAABLgAECn8YAAMGAAgJBCPeHQBdAgAGAAgJBCPeHQBdAgACAAUJyxm3PgBgAQAAAA==.Balghas:BAABLgAECn8kAAIFAAgJ1hzQMwBTAgAFAAgJ1hzQMwBTAgAAAA==.Bamz:BAAALgAFFAEJAQABLgAFFAQJDwARAJYWAA==.Bamzhurt:BAAALgAFFAEJAQABLgAFFAQJDwARAJYWAA==.Baumstrum:BAAALgAECgYJDQAAAA==.',
Be='Beezlbubba:BAAALgAECgYJCgAAAA==.Beldam:BAAALgADCgYJBgAAAA==.Belispeak:BAAALgADCgYJBgAAAA==.Bellaboom:BAAALgADCgYJBgAAAA==.Belvkara:BAAALgADCgkJCQAAAA==.Benedictoe:BAAALgADCgYJBgAAAA==.',
Bh='Bhozok:BAABLgAECn83AAIYAAkJvBInDADUAQAYAAkJvBInDADUAQAAAA==.',
Bi='Bint:BAAALgADCgYJBgAAAA==.',
Bl='Bloodpromise:BAAALgADCgMJAwAAAA==.Bloodrayvn:BAABLgAECn8uAAIGAAkJxR2CFACYAgAGAAkJxR2CFACYAgAAAA==.',
Bo='Boomchick:BAAALgAECgMJAwABLgAECggJGwAGAFYeAA==.Boomparapara:BAACLgAFFH8GAAIJAAMJrBEebgDlAAAJAAMJrBEebgDlAAAuAAQKfxwAAgkACQmIHDsmAGwCAAkACQmIHDsmAGwCAAAA.Borrkbuster:BAAALgADCgkJGQAAAA==.Bosta:BAAALgAECgEJAQAAAA==.Botkin:BAAALgADCgEJAQAAAA==.',
Br='Bradley:BAAALgAECgYJDgABLgAECgYJFgAMAEUjAA==.Brandywyne:BAAALgADCgEJAQAAAA==.Brenri:BAABLgAECn8UAAIPAAgJhwE1ZQCZAAAPAAgJhwE1ZQCZAAAAAA==.Brew:BAABLgAECn8kAAMbAAcJwB/bEQAVAgAbAAcJwB/bEQAVAgAcAAEJ0Q0LfQAzAAAAAA==.Brewtality:BAAALgAECgYJBgAAAA==.Brkat:BAAALgAECgIJAgAAAA==.Brughe:BAABLgAECn8rAAIGAAkJJQ1tVgCIAQAGAAkJJQ1tVgCIAQAAAA==.',
Bu='Bubbleoseven:BAAALgADCgYJBgAAAA==.Buttacutta:BAAALgADCgkJIgAAAA==.',
['Bä']='Bäné:BAAALgADCgIJAgAAAA==.',
Ca='Cairn:BAAALgADCgUJBQAAAA==.Caneste:BAACLgAFFH8QAAIRAAYJqhn/CgCGAQARAAYJqhn/CgCGAQAuAAQKfx8AAhEACQm9HfcLAMMCABEACQm9HfcLAMMCAAAA.Capela:BAAALgADCgEJAQAAAA==.Capparelli:BAAALgADCgEJAQAAAA==.Cashoe:BAAALgADCgMJAwAAAA==.Catscan:BAABLgAECn8iAAIUAAkJ4h3MDADlAgAUAAkJ4h3MDADlAgABLgADCgYJBgAaAAAAAA==.Catty:BAABLgAECn8sAAIYAAkJ/BcTBwBKAgAYAAkJ/BcTBwBKAgAAAA==.',
Cb='Cblock:BAAALgAECgEJAQABLgAFFAIJAgAaAAAAAA==.',
Ce='Celestyl:BAABLgAECn8pAAIdAAgJEwv4BQBPAQAdAAgJEwv4BQBPAQAAAA==.',
Ch='Charazard:BAAALgAECgUJCgABLgAECggJJQAKAL8ZAA==.Charming:BAAALgADCgMJAwAAAA==.Cheapbeer:BAAALgAECgcJEwAAAA==.Cheesehead:BAAALgADCggJEgAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chiforged:BAABLgAECn8UAAIcAAYJtAxlQgDdAAAcAAYJtAxlQgDdAAAAAA==.Chillybovine:BAABLgAECn8XAAIJAAYJ8QiQzADXAAAJAAYJ8QiQzADXAAAAAA==.Chromstrasza:BAABLgAECn8ZAAILAAcJHxiYCACTAQALAAcJHxiYCACTAQAAAA==.Chudderly:BAAALgADCgEJAgAAAA==.Chudders:BAAALgADCgIJAgAAAA==.',
Ci='Cirice:BAAALgAECgEJAQAAAA==.',
Cl='Clarence:BAAALgADCgIJAgABLgAFFAgJJQAXAAMaAA==.',
Co='Conjarr:BAABLgAECn8oAAIMAAkJ/hrRGgDbAQAMAAkJ/hrRGgDbAQAAAA==.Cortisol:BAAALgADCgIJAgAAAA==.Corven:BAAALgAECgUJDAAAAA==.Cougarsixsix:BAABLgAECn8cAAIEAAYJoxZkGgAsAQAEAAYJoxZkGgAsAQAAAA==.',
Cr='Crashnburn:BAAALgADCgcJDQAAAA==.Crazyoldbear:BAABLgAECn8cAAIZAAgJ4CNpBgCSAgAZAAgJ4CNpBgCSAgAAAA==.Creideam:BAAALgADCgkJBwAAAA==.Crimos:BAABLgAECn8wAAIQAAkJzRZJOQAHAgAQAAkJzRZJOQAHAgAAAA==.Crystalliney:BAAALgADCgYJBgABLgAFFAQJDQAbAIcmAA==.',
Cy='Cynnai:BAAALgADCgYJBgAAAA==.Cyrena:BAAALgADCgEJAQAAAA==.',
Da='Daerthor:BAABLgAECn8eAAIEAAgJaRf1DwCqAQAEAAgJaRf1DwCqAQAAAA==.Dalind:BAABLgAECn8cAAIUAAYJKwazeQC4AAAUAAYJKwazeQC4AAAAAA==.Dalshiro:BAAALgAECgYJCQAAAA==.Damaclies:BAABLgAECn9AAAMXAAkJcRZlQwDFAQAXAAgJIRRlQwDFAQAHAAUJfBg6FQDjAAAAAA==.Damedolla:BAABLgAECn8fAAMIAAgJYQxCdQAbAQAIAAgJwwpCdQAbAQAeAAUJnw7EQAD3AAAAAA==.Dammerung:BAAALgAECgYJCAAAAA==.Darksyn:BAABLgAECn8YAAIHAAgJrAt2EAAhAQAHAAgJrAt2EAAhAQAAAA==.Darthbane:BAAALgAECggJDgAAAA==.Darthstroyer:BAAALgAFFAQJBAAAAA==.Darude:BAAALgADCgcJEAAAAA==.Dattiffany:BAAALgAECgQJBAAAAA==.',
De='Deadstout:BAAALgAECgQJBgAAAA==.Deepspace:BAABLgAECn8fAAIeAAgJIyZ/AwAFAwAeAAgJIyZ/AwAFAwAAAA==.Deezus:BAAALgADCgMJAwAAAA==.Dejagauth:BAAALgAECgEJAQABLgAECggJFAAfAF0iAA==.Dekkan:BAAALgAECgYJEAAAAA==.Demonedd:BAAALgADCgIJAgAAAA==.Demòn:BAAALgAECgEJAQAAAA==.Denounce:BAABLgAECn8YAAIgAAcJqBc8JACbAQAgAAcJqBc8JACbAQAAAA==.Desdia:BAAALgAECgYJCgAAAA==.',
Di='Dia:BAAALgAECgQJBwAAAA==.Diabetes:BAABLgAFFH8TAAIVAAYJ0Bp4DgDUAQAVAAYJ0Bp4DgDUAQAAAA==.Diastolic:BAAALgADCgUJBQAAAA==.Didyoudie:BAAALgAECgQJBAAAAA==.Diend:BAABLgAECn9EAAIOAAkJTSFhBABcAwAOAAkJTSFhBABcAwAAAA==.Dill:BAAALgAECgEJAQABLgAECgkJOgABAPAlAA==.Dillathis:BAAALgADCgEJAQAAAA==.Discord:BAAALgADCggJCAABLgAECggJGgAhABIgAA==.Dissonanita:BAAALgAECgYJDAAAAA==.',
Dj='Djthelock:BAABLgAECn8pAAMXAAgJihjSQADOAQAXAAcJKBXSQADOAQAHAAQJDhgbGQDGAAAAAA==.',
Do='Dormoon:BAABLgAECn8bAAMiAAgJnQ2EOQBLAQAiAAgJnQ2EOQBLAQAZAAEJIBFvTAAvAAAAAA==.',
Dr='Drac:BAAALgADCgYJCgAAAA==.Dragath:BAAALgAECgYJDgAAAA==.Drakur:BAAALgAECgYJCQAAAA==.Drbrad:BAABLgAECn8WAAMMAAYJRSOMEwAmAgAMAAYJRSOMEwAmAgARAAMJDhBRYgBiAAAAAA==.Dreadfangs:BAAALgADCgQJBQAAAA==.Druen:BAABLgAECn8xAAIYAAkJHB6VAwC9AgAYAAkJHB6VAwC9AgAAAA==.Drunkenpo:BAABLgAECn9AAAIbAAkJEiHxBADnAgAbAAkJEiHxBADnAgAAAA==.Drïzl:BAEALgAECgMJAwABLgAFFAUJEAAQADEaAA==.',
Du='Duckchow:BAAALgADCgYJBgAAAA==.Dugga:BAAALgADCgQJBAAAAA==.Duskmyre:BAABLgAECn8ZAAIIAAgJWgkMiQDwAAAIAAgJWgkMiQDwAAAAAA==.',
Dw='Dwarfoo:BAABLgAECn8WAAIcAAYJWxPiOAAGAQAcAAYJWxPiOAAGAQAAAA==.Dweñde:BAABLgAECn8mAAIXAAkJigrAVgCMAQAXAAkJigrAVgCMAQAAAA==.',
['Dë']='Dëthmetal:BAABLgAECn8UAAIQAAUJnQxfwgD/AAAQAAUJnQxfwgD/AAAAAA==.',
Ed='Eddiemac:BAAALgADCgUJBQAAAA==.Eddrick:BAABLgAECn8pAAMFAAkJxB0JIABxAgAFAAkJSR0JIABxAgAEAAUJdhzXFwBFAQAAAA==.Edoran:BAAALgADCggJCAAAAA==.Edrani:BAAALgAECgYJDgAAAA==.',
Ei='Eilethen:BAABLgAECn8lAAIWAAkJOxqkBAAsAgAWAAkJOxqkBAAsAgAAAA==.',
Ek='Ekassa:BAAALgADCgkJCQAAAA==.',
El='Elaína:BAAALgADCgMJAwABLgAFFAQJDgAWAOcRAA==.Elementoe:BAAALgADCgEJAQABLgADCgYJBgAaAAAAAA==.Elissabethh:BAAALgAECgYJEAAAAA==.Elleryn:BAAALgADCgEJAQABLgAECgYJGQAOALwXAA==.Elminstar:BAAALgADCgIJAgAAAA==.Elêctra:BAAALgAECgEJAgABLgAECgcJCwAaAAAAAA==.',
Em='Employee:BAAALgAECgcJEwAAAA==.',
En='Engo:BAABLgAECn8/AAMMAAkJdiS4AgBkAwAMAAkJdCO4AgBkAwASAAkJ9BvEBwDhAgAAAA==.',
Er='Eradrá:BAACLgAFFH8OAAMWAAQJ5xHBDACPAAAXAAQJBg4ATwAWAQAWAAIJAQzBDACPAAAuAAQKf08AAxYACQnJHegAAA4DABYACQmsG+gAAA4DABcACQnUF0giAEwCAAAA.Erastrasza:BAAALgADCgYJCQAAAA==.Eroza:BAAALgAECgUJBgAAAA==.Ersey:BAAALgAECgQJBAABLgAFFAMJBwAUAO8HAA==.Ersèlla:BAACLgAFFH8HAAIUAAMJ7wcaQACjAAAUAAMJ7wcaQACjAAAuAAQKfy4AAxQACQmMGLUYAG4CABQACQmMGLUYAG4CAA0AAQnYBYONACQAAAAA.Erysira:BAAALgADCgkJCQABLgAECgYJCAAaAAAAAA==.',
Et='Ethan:BAAALgAECgEJAgAAAA==.',
Eu='Eureka:BAABLgAECn8gAAMEAAkJTB18DADjAQAEAAcJ1Rx8DADjAQAFAAcJSRmjWQCnAQAAAA==.',
Ev='Evandra:BAABLgAECn8eAAIOAAgJdhrmIAAwAgAOAAgJdhrmIAAwAgAAAA==.Evanorah:BAABLgAECn8ZAAMHAAYJNwk3HgCiAAAXAAYJXAhwpgDpAAAHAAYJowU3HgCiAAAAAA==.',
Ex='Exïle:BAEALgAECgYJBgABLgAFFAUJEAAQADEaAA==.',
Fa='Faelithia:BAABLgAECn8WAAIMAAYJKA6ONwAJAQAMAAYJKA6ONwAJAQAAAA==.Fatalbrew:BAAALgAECgUJCgAAAA==.',
Fe='Feldush:BAAALgADCgYJBgABLgAECggJJQAKAL8ZAA==.Felforit:BAAALgADCgQJBAAAAA==.Felis:BAAALgAECgYJCgAAAA==.Felkardio:BAAALgAECgIJAgAAAA==.Feloth:BAAALgADCgYJCQAAAA==.Ferheim:BAAALgAECgUJBQAAAA==.Ferhold:BAAALgADCgUJBQAAAA==.Ferrovax:BAAALgADCgYJBgABLgAECgkJIAAIAOgVAA==.',
Fi='Fiddyone:BAABLgAECn8rAAMjAAkJySFFAgDEAgAjAAkJtCFFAgDEAgAQAAgJcR1RPQD5AQAAAA==.Figment:BAAALgADCgYJBgAAAA==.Fireburt:BAAALgADCgUJBQAAAA==.Fireslay:BAABLgAECn8YAAIfAAcJpBwHHgAmAgAfAAcJpBwHHgAmAgAAAA==.',
Fl='Flarefly:BAAALgAECgEJAQAAAA==.Flaya:BAAALgAECgQJCAAAAA==.',
Fo='Fodurzin:BAAALgAECgQJDgAAAA==.Fonta:BAAALgADCgUJCQAAAA==.Fortuna:BAAALgADCgYJBgABLgAECggJGwAGAFYeAA==.Foxingtobi:BAAALgADCgIJAgAAAA==.',
Fr='Frojio:BAABLgAECn8xAAIjAAkJ1BtUBABeAgAjAAkJ1BtUBABeAgAAAA==.Frosten:BAAALgADCgkJMgAAAA==.',
Fu='Furenio:BAABLgAECn8yAAITAAkJ7xcYDAAAAgATAAkJ7xcYDAAAAgAAAA==.',
Fy='Fyyre:BAAALgAECgUJBwAAAA==.',
Ga='Gabaghoul:BAACLgAFFH8NAAIFAAQJUBnoJgBMAQAFAAQJUBnoJgBMAQAuAAQKfzEAAgUACQl3IKsUALICAAUACQl3IKsUALICAAAA.Gaff:BAAALgAECgYJDgAAAA==.Galeana:BAAALgAECgMJAwABLgAECgkJQgAJAPMcAA==.Galvan:BAAALgAECgEJBAAAAA==.Gasheth:BAAALgAECgYJCQAAAA==.',
Gi='Giggleblast:BAAALgADCggJCgAAAA==.',
Gl='Glizzydealer:BAAALgAECgEJAQAAAA==.',
Gr='Grauth:BAAALgADCgEJAQAAAA==.Graycen:BAAALgAECgUJCQAAAA==.Grido:BAAALgADCgkJEQAAAA==.Grimbrindral:BAABLgAECn8hAAMFAAcJ5hZDZAC5AQAFAAcJdBVDZAC5AQAEAAUJghrKFwBZAQAAAA==.Grimston:BAAALgADCgMJAwABLgAECgcJIQAFAOYWAA==.Gruzaxx:BAAALgADCgUJBQAAAA==.',
Gu='Gulishdaniel:BAAALgAFFAMJBAABLgAFFAYJEAARAKoZAA==.',
Ha='Hadin:BAABLgAECn8/AAMJAAkJ/CPTBgA3AwAJAAkJ/CPTBgA3AwAdAAMJqhysDwDHAAAAAA==.Hakeko:BAAALgAECgYJDQABLgAECgYJDwAaAAAAAA==.Halalnt:BAAALgAECgUJBgABLgAFFAIJBQAgAOkaAA==.Hanua:BAAALgADCgcJBwAAAA==.Haozhao:BAABLgAECn89AAMTAAkJTxk9CQA2AgATAAkJTxk9CQA2AgAYAAEJDhSwQQA6AAAAAA==.Hawktuahz:BAAALgAECgMJAwAAAA==.Hazenpryde:BAABLgAECn8YAAITAAYJzhs5GQBgAQATAAYJzhs5GQBgAQAAAA==.',
He='Hearsay:BAABLgAECn8lAAMFAAgJ5QyOgQBRAQAFAAgJ5QyOgQBRAQAfAAIJ6wOieABHAAAAAA==.Hephaistian:BAAALgAECgUJBQAAAA==.Hespera:BAACLgAFFH8IAAMUAAQJJAnvMQDYAAAUAAQJJAnvMQDYAAANAAMJEgV/MACQAAAuAAQKfyMAAxQACQnJIOkYAHACABQACAmiIekYAHACAA0AAwmnFPFIAMsAAAAA.',
Hi='Hirari:BAABLgAECn8dAAMfAAYJBCXiFABQAgAfAAYJBCXiFABQAgAFAAEJFBoGVgFAAAAAAA==.',
Ho='Hodoor:BAAALgADCgUJBQAAAA==.Howlears:BAABLgAECn8oAAIRAAcJUgfOPwDsAAARAAcJUgfOPwDsAAAAAA==.',
Hu='Hulud:BAABLgAECn8XAAMXAAgJVRdQSQDuAQAXAAgJVRdQSQDuAQAHAAEJAADhTAAAAAAAAA==.Husbando:BAAALgAECgMJAwAAAA==.Husey:BAAALgAECgMJBgAAAA==.',
Hy='Hydrangea:BAABLgAECn8VAAIFAAcJBgsurQAHAQAFAAcJBgsurQAHAQAAAA==.Hydrá:BAABLgAECn8aAAIXAAkJvRatKwAeAgAXAAkJvRatKwAeAgAAAA==.Hylan:BAAALgADCgUJBQAAAA==.Hysgar:BAAALgADCgkJDwABLgAECggJFAAfAF0iAA==.',
Ic='Iceamaris:BAABLgAECn8gAAIPAAkJYQvaMQBbAQAPAAkJYQvaMQBbAQAAAA==.Icetiger:BAAALgADCgIJAgAAAA==.Icetigress:BAAALgAECgEJAQAAAA==.',
Ie='Iechu:BAABLgAECn8XAAMbAAgJYQ+FJAB2AQAbAAgJYQ+FJAB2AQAcAAIJ9QYAegBKAAAAAA==.',
In='Innanna:BAAALgADCggJCgABLgAECgcJEAAaAAAAAA==.',
Is='Isildur:BAAALgADCgEJAQAAAA==.Isoth:BAAALgAECgEJAQAAAA==.',
Iv='Ivern:BAACLgAFFH8RAAIUAAcJ8gurDgDeAQAUAAcJ8gurDgDeAQAuAAQKfx0AAxQABgkHHTsvANQBABQABgkHHTsvANQBAA0AAgnRBySIACkAAAAA.Ivysnow:BAAALgAECgEJAQAAAA==.',
Ja='Jadenpryde:BAAALgAECgYJBgABLgAECgYJGAATAM4bAA==.Jaod:BAAALgADCgkJEQAAAA==.Jarndal:BAAALgAECgEJAQAAAA==.Jasmirrae:BAAALgAECgEJAQAAAA==.',
Jd='Jdghoul:BAAALgAECggJDwAAAA==.',
Ji='Jindrac:BAAALgAECgMJBAAAAA==.',
Jo='Jolton:BAAALgADCgYJBwABLgAECgkJLgAIADMiAA==.',
['Jà']='Jàcaranda:BAAALgAECgEJAQAAAA==.',
Ka='Kahnrah:BAAALgADCgkJDAAAAA==.Kalarae:BAAALgAECggJCAAAAA==.Kaltharion:BAAALgAFFAIJBAAAAA==.Kaluren:BAAALgAECgcJCwAAAA==.Kalurok:BAAALgAECgUJBQABLgAECgcJCwAaAAAAAA==.Kana:BAAALgAECgIJAgAAAA==.Kanade:BAABLgAECn8/AAQXAAkJBB17GACFAgAXAAgJ0hx7GACFAgAWAAcJKxXCBwDSAQAHAAMJYwUKTACJAAAAAA==.Kantong:BAABLgAECn8gAAIcAAgJdRlVGADZAQAcAAgJdRlVGADZAQAAAA==.Kapp:BAAALgAECgYJEAAAAA==.Karabar:BAABLgAECn87AAMEAAkJ2yAVBACsAgAEAAkJyh4VBACsAgAFAAgJoyBMIgBlAgAAAA==.Karnnaged:BAAALgADCgYJBwAAAA==.Kasarra:BAABLgAECn8lAAIeAAkJqROLEgDmAQAeAAkJqROLEgDmAQAAAA==.Kayiku:BAAALgADCgkJDgAAAA==.Kazagol:BAABLgAECn87AAIIAAkJ+x0YFwB3AgAIAAkJ+x0YFwB3AgAAAA==.',
Kh='Khalla:BAAALgAECgkJCQAAAA==.Khamaracy:BAABLgAECn8bAAIHAAYJkAnQGQDBAAAHAAYJkAnQGQDBAAAAAA==.Khronni:BAAALgAECgYJCAAAAA==.Khrooze:BAAALgAECgYJEQAAAA==.',
Ki='Kidos:BAAALgAECgQJBgAAAA==.Kiljana:BAAALgAECgEJAQAAAA==.Kimahrí:BAABLgAECn8YAAIkAAYJLwmzMwCyAAAkAAYJLwmzMwCyAAAAAA==.Kittei:BAABLgAECn87AAITAAkJ1w/UFgB3AQATAAkJ1w/UFgB3AQAAAA==.',
Ko='Kojote:BAAALgADCgMJAQAAAA==.Kovalenko:BAAALgAECggJCwAAAA==.',
Ku='Kurick:BAABLgAECn8UAAMfAAgJXSIlDAC3AgAfAAcJQSIlDAC3AgAFAAEJmxUTVgFAAAAAAA==.Kurzul:BAAALgADCgEJAgAAAA==.Kusinluvin:BAAALgADCgEJAQAAAA==.',
Ky='Kyngizzard:BAABLgAECn8fAAIJAAkJSRrlMAA+AgAJAAkJSRrlMAA+AgABLgAFFAIJBQAgAOkaAA==.Kytherin:BAAALgAECgYJDAAAAA==.',
La='Lactase:BAAALgADCgMJAwAAAA==.Langtry:BAAALgADCgcJBgAAAA==.Latte:BAAALgAECgQJBAAAAA==.',
Le='Leblanc:BAAALgAECgEJAQAAAA==.Leeli:BAAALgADCgcJBwAAAA==.Lenity:BAABLgAECn8tAAIDAAcJchSqHgCGAQADAAcJchSqHgCGAQAAAA==.Letty:BAAALgAECgQJBQAAAA==.',
Li='Liabelle:BAAALgADCgIJAgAAAA==.Lightsmite:BAAALgAECgIJAgAAAA==.Lilithene:BAAALgAECgUJBgABLgAECgcJHQAOALEGAA==.Lionbark:BAAALgADCgEJAQAAAA==.Lithpally:BAAALgADCgEJAQAAAA==.Liubeijian:BAAALgADCgYJBgAAAA==.',
Lo='Lokinah:BAABLgAECn8YAAIGAAgJ2gU9iQATAQAGAAgJ2gU9iQATAQAAAA==.Loonytusk:BAAALgADCgQJBAAAAA==.',
Lu='Lucifermadis:BAAALgAECgQJBgAAAA==.Lucoryphus:BAABLgAECn8ZAAIkAAYJgRd6HgBIAQAkAAYJgRd6HgBIAQAAAA==.Lukeduke:BAABLgAFFH8PAAIZAAcJHx08BQDKAQAZAAcJHx08BQDKAQAAAA==.Luketheduke:BAACLgAFFH8ZAAMTAAYJgR6dAgDXAQATAAUJgR6dAgDXAQAYAAEJAAAIBwA3AAAuAAQKfyoAAxMACQkvJR8BAFcDABMACQkvJR8BAFcDABgABAmxFXscAAkBAAEuAAUUBwkPABkAHx0A.Lumilia:BAAALgADCgUJBQAAAA==.Lunaries:BAAALgAECgYJBgAAAA==.Lunä:BAABLgAECn8hAAIOAAkJThRqIgAQAgAOAAkJThRqIgAQAgAAAA==.',
Ly='Lydia:BAABLgAECn8pAAIJAAkJphkRLgBKAgAJAAkJphkRLgBKAgAAAA==.Lynnee:BAAALgADCgEJAQAAAA==.',
['Lô']='Lôckrocks:BAABLgAECn8ZAAIHAAcJxhFsDQBKAQAHAAcJxhFsDQBKAQAAAA==.',
['Lý']='Lýsendra:BAAALgADCggJCQAAAA==.',
Ma='Magictomb:BAABLgAECn8tAAQPAAgJlxWVMQBdAQAPAAgJlxWVMQBdAQAOAAYJ6Q1hcADrAAAlAAQJ4AdWIwCvAAABLgAFFAIJAgAaAAAAAA==.Mahdude:BAAALgAECgEJAQAAAA==.Malastor:BAAALgAECgEJAQABLgAECggJGgAhABIgAA==.Malcontent:BAAALgAECgQJBQABLgAECggJGgAhABIgAA==.Maldazane:BAAALgADCgYJCwAAAA==.Malfeasance:BAAALgADCgkJDQABLgAECggJGgAhABIgAA==.Malidan:BAAALgADCgMJAwAAAA==.Malifel:BAABLgAECn8aAAMhAAgJEiAPBABwAgAhAAgJEiAPBABwAgAIAAEJUAeXEgEhAAAAAA==.Maliss:BAABLgAECn8+AAQBAAkJRRhDEQAVAgABAAkJahdDEQAVAgACAAQJ8RFyHgCmAAAGAAEJoxGpDgE3AAAAAA==.Mallord:BAAALgAECgYJDgABLgAECggJGgAhABIgAA==.Mandarin:BAABLgAECn8uAAIUAAkJeheFGQBnAgAUAAkJeheFGQBnAgAAAA==.Manmythlegnd:BAAALgADCgYJBgAAAA==.Mannik:BAABLgAECn8WAAIXAAcJuBizSQCyAQAXAAcJuBizSQCyAQAAAA==.Marashade:BAAALgADCgQJBAAAAA==.Marashades:BAAALgADCgQJBAABLgAECggJHAAZAOAjAA==.',
Mc='Mcbadden:BAAALgAECgYJCAAAAA==.',
Me='Meditatetoe:BAAALgADCgIJAgABLgADCgYJBgAaAAAAAA==.Melissà:BAAALgADCgMJAwAAAA==.Menesta:BAAALgADCgcJBwABLgAECgQJDgAaAAAAAA==.Mercia:BAABLgAECn8vAAIEAAkJExsUCAA+AgAEAAkJExsUCAA+AgAAAA==.Merekoma:BAABLgAECn8gAAMIAAkJ6BXZLgD2AQAIAAkJZBPZLgD2AQAhAAMJFRPvJABcAAAAAA==.',
Mi='Milarra:BAAALgAECgcJDQAAAA==.Milhouse:BAAALgAECgUJDgAAAA==.Minalan:BAAALgADCgYJCgABLgAECgYJEQAaAAAAAA==.Mingonashoba:BAABLgAECn8bAAIGAAgJFg3TVACMAQAGAAgJFg3TVACMAQAAAA==.Miragosa:BAABLgAECn8mAAMKAAkJYg6VDwDAAQAKAAkJYg6VDwDAAQALAAEJ8AECKAAaAAAAAA==.Misschris:BAABLgAECn8cAAIVAAgJkAgNSQATAQAVAAgJkAgNSQATAQAAAA==.Mizu:BAAALgAECgUJBQAAAA==.',
Mo='Moadeed:BAAALgAECggJCwAAAA==.Mooluv:BAAALgADCgcJCgAAAA==.Moonstrike:BAAALgAECgIJAgAAAA==.Mordrius:BAAALgADCgYJBgAAAA==.Morphmious:BAAALgAECgcJBwAAAA==.Mortesque:BAAALgAECgcJEgAAAA==.',
Mu='Muttblitzed:BAAALgAECgYJEwAAAA==.Muttskî:BAAALgAECgMJAwAAAA==.',
My='Mybutt:BAAALgAECgMJBgAAAA==.Myrothos:BAAALgADCgEJAQAAAA==.Myrrh:BAABLgAECn8YAAMgAAYJdAdBWgCkAAALAAQJ9wYzLQCxAAAgAAYJggZBWgCkAAAAAA==.',
['Mí']='Místermage:BAAALgAECgQJCAAAAA==.',
Na='Nasturtium:BAAALgADCgYJDgAAAA==.Naturestone:BAAALgAFFAIJAgAAAA==.Nausican:BAABLgAECn85AAIjAAkJeBeRBQAyAgAjAAkJeBeRBQAyAgAAAA==.Nazuhda:BAAALgADCgEJAQAAAA==.',
Ne='Necrosector:BAABLgAECn8mAAIFAAgJuRkkRADhAQAFAAgJuRkkRADhAQAAAA==.Necrotherys:BAABLgAECn8vAAIIAAkJPhz/FACHAgAIAAkJPhz/FACHAgAAAA==.Nelandra:BAABLgAECn8cAAIRAAYJRB3aHwCoAQARAAYJRB3aHwCoAQAAAA==.',
Ni='Nicklaus:BAABLgAECn8eAAIDAAYJFwtGLwAIAQADAAYJFwtGLwAIAQAAAA==.Nilrem:BAAALgADCgIJAgAAAA==.Ninelives:BAAALgAECgYJDgAAAA==.Ninjadk:BAECLgAFFH8QAAMQAAUJMRr3SgA8AQAQAAQJMRr3SgA8AQAkAAEJAAA+UwAAAAAuAAQKfzEAAxAACQmyITQMAPsCABAACQmyITQMAPsCACMAAQm4Gx4tAEAAAAAA.',
No='Nocapongfrfr:BAAALgAECgMJAwABLgAFFAQJBAAaAAAAAA==.Nomahuata:BAABLgAECn9DAAIPAAkJ9Be+FAArAgAPAAkJ9Be+FAArAgAAAA==.Nordre:BAAALgAECgMJAwAAAA==.',
Nu='Nufrus:BAAALgADCgYJBgAAAA==.',
Ny='Nyeli:BAAALgAECgIJAgABLgAECgYJGQAOALwXAA==.Nyxi:BAABLgAECn8WAAIOAAYJ7xtoMADYAQAOAAYJ7xtoMADYAQAAAA==.Nyxlee:BAAALgAECgcJBwAAAA==.',
['Né']='Néo:BAAALgAECgUJCAAAAA==.',
['Nó']='Nóóôööôòòpe:BAAALgAECgEJAQABLgAFFAQJBAAaAAAAAA==.',
Og='Ogdruid:BAAALgADCgcJDgAAAA==.',
Ol='Olympian:BAAALgADCgcJBwAAAA==.',
Om='Omanyte:BAAALgADCgcJBwAAAA==.',
On='Onefiftyone:BAABLgAECn8bAAMlAAYJHCXVCAAbAgAlAAYJHCXVCAAbAgAOAAIJnSROfADIAAABLgAECgkJKwAjAMkhAA==.',
Or='Orruk:BAAALgADCgMJAwAAAA==.Orwyn:BAAALgADCgkJEgAAAA==.',
Ov='Overdose:BAAALgADCgMJAwAAAA==.',
Pa='Padmé:BAAALgAECgQJBQAAAA==.Pain:BAAALgAECgUJCwAAAA==.Palanas:BAAALgAFFAEJAQAAAA==.Pallamoo:BAAALgAECgUJBgAAAA==.Palochka:BAAALgAECgUJBQAAAA==.Paradots:BAABLgAECn8WAAIKAAYJwBpLEQChAQAKAAYJwBpLEQChAQABLgADCgYJBgAaAAAAAA==.Paranitis:BAAALgAECggJDAAAAA==.Paranorm:BAAALgADCgEJAQAAAA==.Paraparaboom:BAAALgAECgUJBQABLgAFFAMJBgAJAKwRAA==.',
Pe='Petronella:BAABLgAECn85AAMmAAkJbw3lFgCMAQAmAAkJbw3lFgCMAQAiAAQJ+wNjgwCxAAAAAA==.Pezmage:BAAALgAECgIJBAAAAA==.',
Ph='Phatboi:BAAALgAECgEJAQAAAA==.Pheroth:BAAALgADCgkJEAABLgAECggJGAAHAKwLAA==.',
Pi='Pixystix:BAABLgAECn8fAAIIAAYJOhlgVwBoAQAIAAYJOhlgVwBoAQAAAA==.',
Po='Poisonspain:BAAALgAECgMJAwAAAA==.Popsdh:BAAALgAECggJDwABLgAECgkJIAAEAEwdAA==.Portlukk:BAAALgADCgEJAQABLgAFFAMJCwAGAM0fAA==.Potscold:BAACLgAFFH8QAAIJAAgJARaGDAC5AQAJAAgJARaGDAC5AQAuAAQKf0EAAgkACAnbJbsRAD0DAAkACAnbJbsRAD0DAAAA.Poxi:BAAALgAECgIJAgABLgAECggJGAAJADwdAA==.',
Pr='Prion:BAABLgAECn8cAAIiAAgJexSYJQC1AQAiAAgJexSYJQC1AQAAAA==.',
Pu='Pull:BAABLgAECn8jAAITAAkJnxt0CABJAgATAAkJnxt0CABJAgAAAA==.',
Ra='Radioshack:BAAALgADCggJCAAAAA==.Radkemonko:BAAALgAECgcJDwAAAA==.Raega:BAAALgADCgYJBgAAAA==.Ragerlock:BAAALgADCgEJAQAAAA==.Raivel:BAABLgAECn8ZAAIOAAYJvBcyPwCUAQAOAAYJvBcyPwCUAQAAAA==.Raldaron:BAAALgADCgEJAQAAAA==.Raneyth:BAAALgAECgUJBQAAAA==.Ranith:BAAALgADCgMJAwAAAA==.Ravagèr:BAAALgAECgEJAgAAAA==.',
Rd='Rdbwarrior:BAAALgADCgUJBQAAAA==.',
Re='Redemus:BAAALgADCgEJAQAAAA==.Redwinetoast:BAABLgAECn8bAAIXAAgJSwSIqADlAAAXAAgJSwSIqADlAAAAAA==.Reliala:BAAALgADCgkJEQAAAA==.Reno:BAAALgADCgkJEAAAAA==.Reshyk:BAAALgAECggJEgAAAA==.Resles:BAAALgAECgEJAQAAAA==.Respectwomen:BAAALgADCgEJAQABLgAECgQJBAAaAAAAAA==.',
Rh='Rhobes:BAAALgAECgcJDQAAAA==.Rhondta:BAABLgAECn8eAAIXAAgJXQ+1XgB5AQAXAAgJXQ+1XgB5AQAAAA==.',
Ri='Rickormortis:BAAALgAECgYJCAABLgAECggJHAAVAJAIAA==.Rictus:BAABLgAECn8wAAIJAAkJjSR6BgA7AwAJAAkJjSR6BgA7AwAAAA==.Ringmasterr:BAAALgADCgUJBQAAAA==.Riordaa:BAAALgADCgYJDAAAAA==.Risingdragon:BAABLgAECn8jAAIcAAYJdBTAMQAoAQAcAAYJdBTAMQAoAQAAAA==.',
Ro='Roades:BAAALgADCgcJDAAAAA==.Roboskritch:BAAALgADCgUJBQAAAA==.Ronaj:BAAALgADCgMJBAAAAA==.Royveer:BAAALgADCgYJCQAAAA==.',
Ru='Rumor:BAAALgAECggJEwABLgAECggJJQAFAOUMAA==.Rurry:BAACLgAFFH8YAAIKAAYJpRe+BACuAQAKAAYJpRe+BACuAQAuAAQKfy4ABAoACQnIIrECAEADAAoACQnIIrECAEADAAsABQm6GR4WAI8BACAAAwlVF/RGAL8AAAEuAAUUBwkRABQA8gsA.',
Ry='Ryumi:BAABLgAECn8uAAIIAAkJMyJwFACMAgAIAAkJMyJwFACMAgAAAA==.Ryur:BAAALgAECgQJDgAAAA==.',
Sa='Sabastion:BAAALgAECgYJBgABLgAECggJGgAhABIgAA==.Sacrickficed:BAAALgAECgQJBAABLgAECggJHAAVAJAIAA==.Sahwe:BAAALgAECgYJEwAAAA==.Salocar:BAAALgAECgcJEwAAAA==.Sanafela:BAAALgADCgkJOgAAAA==.Saphisha:BAAALgAECgcJEAAAAA==.Sasora:BAAALgAECgUJCwAAAA==.Saucemagic:BAAALgAECgcJDQAAAA==.Savonah:BAAALgAECgEJAQAAAA==.',
Sc='Scaledaddy:BAABLgAECn8jAAIgAAkJug0HJQCbAQAgAAkJug0HJQCbAQAAAA==.Scalespawn:BAAALgADCgYJBgABLgAFFAcJGgAQACYbAA==.Scaryl:BAAALgAECgYJCgAAAA==.Scourgespawn:BAACLgAFFH8aAAMQAAcJJhsnFADwAQAQAAYJJhsnFADwAQAkAAIJpwigNwAoAAAuAAQKfyoAAxAACQmyIDMkAK0CABAACQmyIDMkAK0CACQABAnhFZAzALIAAAAA.',
Se='Selenë:BAAALgAECgcJEwAAAA==.Sengoku:BAAALgAECgEJAQAAAA==.Serbiscuit:BAAALgAECgUJCgAAAA==.Sereneya:BAAALgADCgcJBwAAAA==.Serenio:BAAALgAECgcJEQAAAA==.Serenval:BAAALgADCgkJCQAAAA==.',
Sh='Shadowshart:BAAALgAECgEJAQAAAA==.Shailora:BAAALgAECgMJAwAAAA==.Shait:BAAALgADCgYJBgAAAA==.Shalis:BAABLgAECn8bAAIGAAgJLBt7NQDwAQAGAAgJLBt7NQDwAQAAAA==.Sharivee:BAAALgAECggJEQAAAA==.Sharko:BAABLgAECn8cAAQEAAgJExeSDwDMAQAEAAcJzhWSDwDMAQAFAAUJhBnTlAAvAQAfAAIJwgOQiwBPAAAAAA==.Shibui:BAABLgAECn8+AAQeAAkJGRjbDAA4AgAeAAkJGRjbDAA4AgAIAAcJvAYvowDNAAAhAAQJQQ5kGgCvAAAAAA==.Shiggles:BAABLgAECn8hAAIQAAkJEBrmIgBmAgAQAAkJEBrmIgBmAgABLgAFFAIJBQAFAHUVAA==.Shinhaein:BAABLgAECn8UAAIJAAYJ2BSRsAB8AQAJAAYJ2BSRsAB8AQABLgAFFAUJFgAQAAMaAA==.Shinxu:BAAALgADCgQJBAAAAA==.Shockazilla:BAABLgAECn82AAMfAAkJbR5GBwAEAwAfAAkJbR5GBwAEAwAFAAMJVw+z/wCWAAAAAA==.Shreddarfort:BAAALgADCgkJFQAAAA==.Shönuff:BAAALgAECgEJAQAAAA==.',
Si='Sigh:BAAALgAFFAEJAQAAAA==.Silverhorn:BAABLgAECn8dAAIFAAcJvBmsXgCbAQAFAAcJvBmsXgCbAQAAAA==.',
Sk='Skoduh:BAABLgAECn8hAAIGAAcJQhwdRgC3AQAGAAcJQhwdRgC3AQAAAA==.Skyelene:BAABLgAECn8dAAMOAAcJsQYVbgDyAAAOAAcJsQYVbgDyAAAPAAcJHxK4TADmAAAAAA==.',
Sl='Slaanesh:BAABLgAECn8ZAAQHAAgJnha6CgB5AQAHAAcJ7hW6CgB5AQAWAAMJlhsqFwDFAAAXAAMJzw5/zQCmAAAAAA==.Sluggo:BAABLgAFFH8GAAIFAAQJ/xHPPQAZAQAFAAQJ/xHPPQAZAQAAAA==.Sluggoboyce:BAACLgAFFH8GAAICAAQJhgR9EwAHAQACAAQJhgR9EwAHAQAuAAQKfyIAAwIACAkLGSEcAEcCAAIACAnYGCEcAEcCAAYABAmEDS6aAJ8AAAAA.',
Sm='Smeagosses:BAAALgAECgEJAQAAAA==.Smokeü:BAAALgAECgcJBwAAAA==.',
So='Solace:BAAALgAECgYJDAAAAA==.Solinaara:BAAALgAECgQJBAAAAA==.Soraka:BAABLgAFFH8KAAISAAQJnQppIgAGAQASAAQJnQppIgAGAQAAAA==.',
Sp='Spiralist:BAABLgAECn8dAAQUAAkJ4xahSQBVAQAUAAgJfBWhSQBVAQANAAYJARlrMgA2AQAYAAIJkAwpOABWAAAAAA==.Spiralmist:BAAALgADCgUJBQAAAA==.',
St='Starge:BAAALgAECgUJBQAAAA==.Steelforged:BAAALgADCgcJBwABLgAECgYJFAAcALQMAA==.Stonedalways:BAABLgAECn8ZAAMOAAYJlBNXTgBaAQAOAAYJlBNXTgBaAQAPAAIJOQbqgwBMAAAAAA==.',
Su='Sunfuri:BAABLgAECn85AAIiAAkJDQqTLwB8AQAiAAkJDQqTLwB8AQAAAA==.Sunjan:BAAALgAECgQJBwAAAA==.Sus:BAACLgAFFH8eAAIeAAcJ7RvTAQACAgAeAAcJ7RvTAQACAgAuAAQKfyUAAh4ACQmXI5cDAEcDAB4ACQmXI5cDAEcDAAAA.Susanoo:BAABLgAECn8ZAAIiAAkJcRRVIADZAQAiAAkJcRRVIADZAQAAAA==.',
Sy='Sylvíadne:BAAALgAECgYJBgAAAA==.',
Sz='Szul:BAAALgADCgcJDAAAAA==.',
Ta='Tachima:BAAALgAECgcJEAABLgAECgkJLgAIADMiAA==.Tactics:BAAALgADCgcJDAAAAA==.Tahitimango:BAABLgAECn8gAAIIAAYJjQNjwQCFAAAIAAYJjQNjwQCFAAAAAA==.Takeko:BAAALgADCgcJDgABLgAECgYJDwAaAAAAAA==.Talanas:BAAALgADCgcJBwAAAA==.Taleria:BAAALgADCgYJGQAAAA==.Taranad:BAAALgAECgcJDAAAAA==.Tarathor:BAABLgAECn8cAAINAAYJZBvzJACKAQANAAYJZBvzJACKAQAAAA==.Tasha:BAAALgAECgEJAwABLgAECggJHAAiAHsUAA==.Tauroctony:BAABLgAECn8eAAITAAgJKiGhBACiAgATAAgJKiGhBACiAgAAAA==.',
Te='Tea:BAAALgAECgYJCgABLgAECgkJOgAMAH4bAA==.Teknofarious:BAAALgAECgEJAwAAAA==.Tenom:BAAALgAECgUJCgAAAA==.',
Th='Thalar:BAAALgAECgIJAgAAAA==.Thaumas:BAAALgADCgEJAQAAAA==.Thelsyn:BAAALgAECgIJAgABLgAECgkJPgABAEUYAA==.Thermite:BAAALgAECgYJBgAAAA==.Thesafe:BAAALgAECgMJAwAAAA==.Thialaa:BAAALgAECgEJAwABLgAECgkJOQAGAKwgAA==.Thialia:BAAALgAECgkJEwABLgAECgkJOQAGAKwgAA==.Thialiaa:BAAALgAECgYJBgABLgAECgkJOQAGAKwgAA==.Thorey:BAAALgAECgEJAQAAAA==.Thornbreaker:BAAALgADCgEJAQAAAA==.Thorthunda:BAAALgAECgQJBgAAAA==.',
Ti='Tinkabella:BAABLgAECn87AAISAAkJLiPkAQCUAwASAAkJLiPkAQCUAwAAAA==.Tizl:BAEALgAECgUJBQABLgAFFAUJEAAQADEaAA==.',
To='Tobiblindpaw:BAAALgAECgUJDQAAAA==.Toenailjuice:BAAALgADCgUJBQABLgAECgkJOwAVAKkjAA==.Torrey:BAABLgAECn8YAAIfAAgJHyVuAwA8AwAfAAgJHyVuAwA8AwAAAA==.',
Tr='Trema:BAAALgAECgEJAgAAAA==.Trix:BAABLgAECn8vAAIOAAgJHw1ETwBXAQAOAAgJHw1ETwBXAQAAAA==.',
Tu='Tulsami:BAAALgAECgIJAwAAAA==.Tulsi:BAABLgAECn83AAInAAkJRSSXAABAAwAnAAkJRSSXAABAAwAAAA==.Tuskoo:BAAALgAECgcJEQAAAA==.',
Ty='Tyrathion:BAAALgAECgMJAwAAAA==.Tyronos:BAABLgAECn8XAAIFAAYJ3hUDowAXAQAFAAYJ3hUDowAXAQAAAA==.',
Uk='Uknôwnforce:BAAALgAECgMJBAAAAA==.',
Un='Unbeetable:BAAALgADCgUJBQAAAA==.',
Va='Valanoth:BAABLgAECn8jAAIIAAgJ1SAmGgBkAgAIAAgJ1SAmGgBkAgAAAA==.Valdr:BAABLgAECn8eAAMgAAgJQRKyKQB+AQAgAAgJQRKyKQB+AQALAAQJowzXKQDQAAAAAA==.Valoryck:BAAALgAECgQJDQABLgAECggJIwAIANUgAA==.Vas:BAAALgAECgMJAwAAAA==.',
Ve='Velielina:BAAALgAECgEJAQAAAA==.Velistos:BAAALgADCgEJAQAAAA==.Vellandrias:BAAALgADCgYJBgAAAA==.Verinda:BAAALgADCgcJDwAAAA==.Vessara:BAAALgADCgUJBQABLgAFFAMJBQANAMITAA==.Vevicenth:BAAALgAECgkJEgAAAA==.',
Vo='Voranth:BAAALgADCgMJAwAAAA==.',
Wa='Warpsbulge:BAACLgAFFH8cAAIJAAYJkh5lCgDMAQAJAAYJkh5lCgDMAQAuAAQKfxsAAwkACQlNIb4hAOwCAAkACQlNIb4hAOwCAB0AAgl2FLQTAIoAAAAA.',
Wh='Whakan:BAAALgAECgEJAgABLgAECgYJGQAkAIEXAA==.',
Wo='Wolfos:BAABLgAECn8fAAITAAkJEiZmAAB2AwATAAkJEiZmAAB2AwAAAA==.',
Wt='Wtfox:BAEALgAECgcJEwABLgAECggJLAAPAEkaAA==.',
Wu='Wulfgange:BAAALgADCgEJAQAAAA==.',
Wy='Wysteri:BAAALgAECgcJEAAAAA==.',
Xa='Xadrai:BAAALgADCgIJAgAAAA==.Xakeko:BAAALgAECgYJDwAAAA==.Xalatos:BAAALgAECgEJAgAAAA==.Xalfein:BAAALgAECgQJBAAAAA==.',
Xi='Xinu:BAAALgADCgYJBgABLgAECgkJQAAGABsdAA==.',
Ya='Yanakana:BAAALgAECgUJBQAAAA==.',
Yd='Ydalise:BAAALgAECgEJAgAAAA==.Ydrassil:BAABLgAECn8VAAITAAkJcxrlBwBXAgATAAkJcxrlBwBXAgABLgAECgkJIAAEAEwdAA==.',
Yi='Yitsuni:BAAALgAECgcJDQAAAA==.',
Za='Zalaeda:BAAALgAECgEJAQAAAA==.Zalena:BAAALgAECgQJCAAAAA==.Zatriani:BAAALgAECgYJCgAAAA==.',
Ze='Zenus:BAABLgAECn8iAAMGAAgJsxWhSACwAQAGAAgJsxWhSACwAQACAAMJqwfjMABFAAAAAA==.Zerina:BAAALgADCgUJBQAAAA==.Zesty:BAAALgADCgMJAwAAAA==.Zeusal:BAABLgAECn8bAAINAAcJdgkyPQD+AAANAAcJdgkyPQD+AAAAAA==.Zeusinator:BAABLgAECn8oAAIGAAkJaxivJAA4AgAGAAkJaxivJAA4AgAAAA==.',
Zi='Zinu:BAABLgAECn9AAAIGAAkJGx3PGAB7AgAGAAkJGx3PGAB7AgAAAA==.Zivalisse:BAAALgAECgUJBwAAAA==.',
Zu='Zulfionn:BAABLgAECn8oAAIGAAkJYArgTACiAQAGAAkJYArgTACiAQAAAA==.',
Zy='Zylah:BAAALgADCgEJAQAAAA==.',
['Áy']='Áyrá:BAABLgAECn8dAAIfAAgJohuRHAAIAgAfAAgJohuRHAAIAgAAAA==.',
['Åp']='Åpollyon:BAAALgAECgYJBwAAAA==.',
['Øu']='Øuroboros:BAABLgAECn8lAAQKAAgJvxngCgAcAgAKAAcJyxrgCgAcAgALAAYJ5hp8FAChAQAgAAQJ1heQRQDHAAAAAA==.',
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
