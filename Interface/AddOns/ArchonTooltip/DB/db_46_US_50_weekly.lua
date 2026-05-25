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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Devourer','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','Priest-Shadow','Priest-Discipline','Druid-Guardian','Druid-Restoration','Monk-Mistweaver','Druid-Feral','Warrior-Protection','Monk-Brewmaster','Monk-Windwalker','Mage-Arcane','Warlock-Demonology','DemonHunter-Havoc','Evoker-Augmentation','Warrior-Fury','Warlock-Affliction','Druid-Balance','DeathKnight-Frost','Paladin-Holy','DeathKnight-Blood','Shaman-Enhancement','DemonHunter-Vengeance','Warrior-Arms','Rogue-Assassination',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abelene:BAAALgAECgQJBAAAAA==.Abrâham:BAAALgADCgUJBQAAAA==.',
Ac='Achelis:BAABLgAECn86AAMBAAkJ8CWnAABlAwABAAkJ8CWnAABlAwACAAEJAABJggA/AAAAAA==.',
Ad='Adianitefall:BAAALgAECgIJAgAAAA==.Adorian:BAABLgAECn8WAAIDAAYJjwiHLwDyAAADAAYJjwiHLwDyAAAAAA==.Adros:BAABLgAECn8oAAMEAAgJQRQMFQB+AQAEAAgJQRQMFQB+AQAFAAEJHwSLfgEjAAAAAA==.Adrrel:BAAALgADCgIJAgABLgAFFAcJHQAGACkbAA==.Adrrelle:BAACLgAFFH8dAAMGAAcJKRurCQCrAQAGAAYJbRyrCQCrAQACAAYJaw3EEAANAQAuAAQKfyUABAIACQncHXcTAJkCAAIACAmXH3cTAJkCAAEABAnaF0AzAO0AAAYAAwmpEW64AFIAAAAA.',
Ae='Aelon:BAABLgAECn8cAAIFAAgJxgeTrwAkAQAFAAgJxgeTrwAkAQAAAA==.',
Ah='Aheiro:BAAALgAECgMJAwAAAA==.',
Ai='Ailaith:BAABLgAECn81AAIGAAkJ/R+HEQCcAgAGAAkJ/R+HEQCcAgAAAA==.',
Ak='Akariliselle:BAABLgAECn8WAAIHAAcJMBomCACfAQAHAAcJMBomCACfAQAAAA==.Akarue:BAAALgAECgQJBAAAAA==.Akibafaris:BAAALgAECgQJBAAAAA==.Aknologia:BAAALgAECgUJCAAAAA==.',
Al='Al:BAAALgADCggJCAAAAA==.Alan:BAAALgAECgQJBwAAAA==.Alarielle:BAAALgADCgkJEQAAAA==.Aldora:BAAALgADCgkJDAAAAA==.Alirik:BAAALgADCgQJBQAAAA==.Alleriah:BAAALgAECgcJCAABLgAECggJIwAIANUgAA==.Alydrostage:BAABLgAECn8hAAIJAAYJFAYBxwDhAAAJAAYJFAYBxwDhAAAAAA==.Alystriaz:BAABLgAECn8iAAMKAAgJqhgwCQA0AgAKAAgJqhgwCQA0AgALAAEJsQUzIwAqAAAAAA==.Alzheimerz:BAAALgAECgUJBQAAAA==.',
Am='Amaelalin:BAABLgAECn82AAIMAAkJ7RNtFgD3AQAMAAkJ7RNtFgD3AQAAAA==.Ameliya:BAAALgAECgIJAgAAAA==.Ameng:BAAALgAECgQJBgAAAA==.',
An='Anaralyth:BAAALgAECgUJBQABLgAFFAIJAgANAAAAAA==.Andaya:BAACLgAFFH8JAAIOAAMJzyEsIwAgAQAOAAMJzyEsIwAgAQAuAAQKfyMAAw4ACQmrGcIwAMIBAA4ACQmrGcIwAMIBAA8AAgndDDNuAGYAAAAA.Andemeli:BAAALgAECgYJBgAAAA==.Andevyn:BAAALgAECgQJBAABLgAECggJIwAIANUgAA==.Aninja:BAEALgADCgQJBAABLgAFFAQJDgAQADEaAA==.Anivia:BAABLgAECn8cAAIJAAgJNBL6XwCjAQAJAAgJNBL6XwCjAQAAAA==.Ankoubailith:BAAALgAECgQJBgAAAA==.',
Ap='Apollon:BAAALgADCgIJAgAAAA==.',
Ar='Arandis:BAABLgAECn8WAAMRAAYJsQiFPwDnAAARAAYJsQiFPwDnAAASAAIJ2Qe6WgBKAAAAAA==.Arch:BAAALgAECgQJBQAAAA==.Arcianna:BAABLgAECn8uAAMTAAkJkh26BACYAgATAAkJkh26BACYAgAUAAEJQREwvQAxAAAAAA==.Arctica:BAAALgAECgUJDwAAAA==.Arctiq:BAAALgADCgUJCgAAAA==.Arctîc:BAABLgAECn8iAAIJAAgJThGSYwCaAQAJAAgJThGSYwCaAQAAAA==.Arjurn:BAABLgAECn87AAIJAAkJByCCDgDvAgAJAAkJByCCDgDvAgAAAA==.Arkro:BAAALgADCgYJBgAAAA==.Armpitbutter:BAABLgAECn87AAIVAAkJqSO+AgB4AwAVAAkJqSO+AgB4AwAAAA==.Artymiss:BAAALgAECggJCwAAAA==.',
As='Asherah:BAAALgAECgcJDAAAAA==.Ashireita:BAAALgAECgYJEAABLgAECgcJHQAOALEGAA==.Astraleth:BAAALgAFFAIJAgAAAA==.',
At='Atama:BAAALgAECgMJAwAAAA==.Atharius:BAAALgADCgEJAQAAAA==.',
Au='Authority:BAAALgAECgMJAwAAAA==.Autry:BAABLgAECn8xAAMWAAkJ1g81DADAAQAWAAkJ1g81DADAAQAUAAgJUgqMSQBGAQAAAA==.',
Av='Avelina:BAAALgADCgcJDgAAAA==.Avocat:BAABLgAECn8YAAIGAAcJdhPtWQBoAQAGAAcJdhPtWQBoAQAAAA==.',
Az='Azeria:BAAALgAECgUJCQABLgAFFAcJDwAXAB8dAA==.Azshura:BAAALgADCgYJCQAAAA==.Azzinôth:BAAALgADCgcJBwABLgAECgEJAgANAAAAAA==.',
Ba='Baekr:BAAALgAECgYJEAAAAA==.Baldr:BAABLgAECn8sAAIFAAkJEBJ9PgDsAQAFAAkJEBJ9PgDsAQAAAA==.Balgar:BAABLgAECn8YAAMGAAgJBCMQGQBnAgAGAAgJBCMQGQBnAgACAAUJyxm3PgBgAQAAAA==.Balghas:BAABLgAECn8kAAIFAAgJ1hzQMwBTAgAFAAgJ1hzQMwBTAgAAAA==.Bamz:BAAALgAFFAEJAQABLgAFFAQJDgAMAH8KAA==.Bamzhurt:BAAALgAFFAEJAQABLgAFFAQJDgAMAH8KAA==.Baumstrum:BAAALgAECgYJDQAAAA==.',
Be='Beezlbubba:BAAALgAECgYJCQAAAA==.Beldam:BAAALgADCgYJBgAAAA==.Belispeak:BAAALgADCgYJBgAAAA==.Bellaboom:BAAALgADCgYJBgAAAA==.Belvkara:BAAALgADCgkJCQAAAA==.Benedictoe:BAAALgADCgYJBgAAAA==.',
Bh='Bhozok:BAABLgAECn83AAIWAAkJvBKJCgDiAQAWAAkJvBKJCgDiAQAAAA==.',
Bi='Bint:BAAALgADCgYJBgAAAA==.',
Bl='Bloodpromise:BAAALgADCgMJAwAAAA==.Bloodrayvn:BAABLgAECn8nAAIGAAgJtR22IQA0AgAGAAgJtR22IQA0AgAAAA==.',
Bo='Boomchick:BAAALgAECgMJAwABLgAECggJFQAGALEdAA==.Boomparapara:BAABLgAECn8YAAIJAAgJaRvvPwABAgAJAAgJaRvvPwABAgAAAA==.Borrkbuster:BAAALgADCgkJGQAAAA==.Bosta:BAAALgADCggJDAAAAA==.Botkin:BAAALgADCgEJAQAAAA==.',
Br='Bradley:BAAALgAECgYJDgABLgAECgYJFgAMAEUjAA==.Brandywyne:BAAALgADCgEJAQAAAA==.Brenri:BAAALgAECggJEAAAAA==.Brew:BAABLgAECn8jAAMYAAcJhB8JEQASAgAYAAcJhB8JEQASAgAZAAEJ0Q0LfQAzAAAAAA==.Brkat:BAAALgADCgYJBwAAAA==.Brughe:BAABLgAECn8nAAIGAAkJvwnqXgBcAQAGAAkJvwnqXgBcAQAAAA==.',
Bu='Bubbleoseven:BAAALgADCgYJBgAAAA==.Buttacutta:BAAALgADCgkJIgAAAA==.',
['Bä']='Bäné:BAAALgADCgIJAgAAAA==.',
Ca='Cairn:BAAALgADCgUJBQAAAA==.Caneste:BAACLgAFFH8QAAIRAAYJqhnPBwChAQARAAYJqhnPBwChAQAuAAQKfx0AAhEACQm9HfcLAMMCABEACQm9HfcLAMMCAAAA.Capela:BAAALgADCgEJAQAAAA==.Capparelli:BAAALgADCgEJAQAAAA==.Cashoe:BAAALgADCgMJAwAAAA==.Catscan:BAABLgAECn8iAAIUAAkJ4h2/CwDlAgAUAAkJ4h2/CwDlAgABLgADCgYJBgANAAAAAA==.Catty:BAABLgAECn8sAAIWAAkJ/BcTBgBXAgAWAAkJ/BcTBgBXAgAAAA==.',
Ce='Celestyl:BAABLgAECn8mAAIaAAgJEwtRBQBZAQAaAAgJEwtRBQBZAQAAAA==.',
Ch='Charazard:BAAALgAECgUJCgABLgAECggJJQAKAL8ZAA==.Charming:BAAALgADCgMJAwAAAA==.Cheapbeer:BAAALgAECgcJEwAAAA==.Cheesehead:BAAALgADCggJEgAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chiforged:BAAALgAECgYJEAAAAA==.Chillybovine:BAABLgAECn8WAAIJAAYJ8QgPuwD0AAAJAAYJ8QgPuwD0AAAAAA==.Chromstrasza:BAABLgAECn8ZAAILAAcJHxjxBwCVAQALAAcJHxjxBwCVAQAAAA==.Chudderly:BAAALgADCgEJAgAAAA==.Chudders:BAAALgADCgIJAgAAAA==.',
Ci='Cirice:BAAALgAECgEJAQAAAA==.',
Cl='Clarence:BAAALgADCgIJAgABLgAFFAgJIQAbAKUYAA==.',
Co='Conjarr:BAABLgAECn8oAAIMAAkJ/hqLGADhAQAMAAkJ/hqLGADhAQAAAA==.Cortisol:BAAALgADCgIJAgAAAA==.Corven:BAAALgAECgUJDAAAAA==.Cougarsixsix:BAABLgAECn8WAAIEAAYJgBXmGgATAQAEAAYJgBXmGgATAQAAAA==.',
Cr='Crashnburn:BAAALgADCgcJDQAAAA==.Crazyoldbear:BAABLgAECn8cAAIXAAgJ4COKBQCdAgAXAAgJ4COKBQCdAgAAAA==.Creideam:BAAALgADCgkJBwAAAA==.Crimos:BAABLgAECn8wAAIQAAkJzRbmMwALAgAQAAkJzRbmMwALAgAAAA==.Crystalliney:BAAALgADCgYJBgABLgAFFAMJCQAYAOUmAA==.',
Cy='Cynnai:BAAALgADCgYJBgAAAA==.Cyrena:BAAALgADCgEJAQAAAA==.',
Da='Daerthor:BAABLgAECn8eAAIEAAgJaRd3DgCuAQAEAAgJaRd3DgCuAQAAAA==.Dalind:BAABLgAECn8WAAIUAAYJvwUwdwCwAAAUAAYJvwUwdwCwAAAAAA==.Dalshiro:BAAALgAECgYJCQAAAA==.Damaclies:BAABLgAECn8vAAMbAAkJtxW7QQC/AQAbAAgJ0hO7QQC/AQAHAAUJkhfBFADcAAAAAA==.Damedolla:BAABLgAECn8fAAMIAAgJYQx/aQAsAQAIAAgJwwp/aQAsAQAcAAUJnw7EQAD3AAAAAA==.Dammerung:BAAALgAECgYJCAAAAA==.Darksyn:BAABLgAECn8VAAIHAAYJlQsJFgDSAAAHAAYJlQsJFgDSAAAAAA==.Darthbane:BAAALgAECgYJCwAAAA==.Darthstroyer:BAAALgAFFAEJAQABLgAFFAQJEAAdAJ8QAA==.Darude:BAAALgADCgcJEAAAAA==.',
De='Deadstout:BAAALgAECgQJBQAAAA==.Deepspace:BAABLgAECn8fAAIcAAgJIybUAgALAwAcAAgJIybUAgALAwAAAA==.Deezus:BAAALgADCgMJAwAAAA==.Dejagauth:BAAALgADCgkJGgAAAA==.Dekkan:BAAALgAECgYJEAAAAA==.Demòn:BAAALgAECgEJAQAAAA==.Denounce:BAABLgAECn8YAAIdAAcJqBc8JACbAQAdAAcJqBc8JACbAQAAAA==.Desdia:BAAALgAECgYJCgAAAA==.',
Di='Dia:BAAALgAECgMJAwAAAA==.Diabetes:BAABLgAFFH8RAAIVAAUJfRt0EQCIAQAVAAUJfRt0EQCIAQAAAA==.Diastolic:BAAALgADCgUJBQAAAA==.Diend:BAABLgAECn9AAAIOAAkJaSCXBQAzAwAOAAkJaSCXBQAzAwAAAA==.Dill:BAAALgAECgEJAQABLgAECgkJOgABAPAlAA==.Dillathis:BAAALgADCgEJAQAAAA==.Discord:BAAALgADCgcJBwABLgAECggJEgANAAAAAA==.Dissonanita:BAAALgAECgYJCwAAAA==.',
Dj='Djthelock:BAABLgAECn8kAAMbAAgJYxUMSACsAQAbAAcJ0hEMSACsAQAHAAQJDhjZFwDEAAAAAA==.',
Do='Dormoon:BAABLgAECn8bAAMeAAgJnQ1VNABSAQAeAAgJnQ1VNABSAQAXAAEJIBH3RgAxAAAAAA==.',
Dr='Drac:BAAALgADCgYJCgAAAA==.Dragath:BAAALgAECgYJDgAAAA==.Drakur:BAAALgAECgYJCQAAAA==.Drbrad:BAABLgAECn8WAAMMAAYJRSO8EQAtAgAMAAYJRSO8EQAtAgARAAMJDhDkXABkAAAAAA==.Dreadfangs:BAAALgADCgQJBQAAAA==.Druen:BAABLgAECn8uAAIWAAkJ6By1AwCtAgAWAAkJ6By1AwCtAgAAAA==.Drunkenpo:BAABLgAECn9AAAIYAAkJEiFBBADrAgAYAAkJEiFBBADrAgAAAA==.Drïzl:BAEALgAECgMJAwABLgAFFAQJDgAQADEaAA==.',
Du='Duckchow:BAAALgADCgYJBgAAAA==.Dugga:BAAALgADCgQJBAAAAA==.Duskmyre:BAABLgAECn8ZAAIIAAgJWglSewACAQAIAAgJWglSewACAQAAAA==.',
Dw='Dwarfoo:BAABLgAECn8WAAIZAAYJWxNONAAIAQAZAAYJWxNONAAIAQAAAA==.Dweñde:BAABLgAECn8gAAIbAAgJzwiIcQBBAQAbAAgJzwiIcQBBAQAAAA==.',
['Dë']='Dëthmetal:BAABLgAECn8UAAIQAAUJnQxfwgD/AAAQAAUJnQxfwgD/AAAAAA==.',
Ed='Eddrick:BAABLgAECn8iAAMFAAgJ2hx1MAAdAgAFAAgJ2hx1MAAdAgAEAAIJag2PRwAkAAAAAA==.Edoran:BAAALgADCggJCAAAAA==.Edrani:BAAALgAECgYJDQAAAA==.',
Ei='Eilethen:BAABLgAECn8hAAIfAAgJ7RoWBgDsAQAfAAgJ7RoWBgDsAQAAAA==.',
Ek='Ekassa:BAAALgADCgkJCQAAAA==.',
El='Elaína:BAAALgADCgMJAwABLgAFFAQJCgAfAO8QAA==.Elementoe:BAAALgADCgEJAQABLgADCgYJBgANAAAAAA==.Elissabethh:BAAALgAECgYJEAAAAA==.Elleryn:BAAALgADCgEJAQABLgAECgYJEwANAAAAAA==.Elminstar:BAAALgADCgIJAgAAAA==.Elêctra:BAAALgAECgEJAQABLgAECgYJCgANAAAAAA==.',
Em='Employee:BAAALgAECgcJEwAAAA==.',
En='Engo:BAABLgAECn82AAMMAAkJdiQ0AgBsAwAMAAkJdCM0AgBsAwASAAgJvxeCEAA+AgAAAA==.',
Er='Eradrá:BAACLgAFFH8KAAMfAAQJ7xArCgCHAAAbAAQJBg4bRgAYAQAfAAIJEQorCgCHAAAuAAQKf04AAx8ACQnJHegAAA4DAB8ACQmsG+gAAA4DABsACQnUF4ofAE4CAAAA.Erastrasza:BAAALgADCgYJCQAAAA==.Eroza:BAAALgAECgUJBgAAAA==.Ersey:BAAALgAECgQJBAABLgAECggJLAAUAHkZAA==.Ersèlla:BAABLgAECn8sAAMUAAgJeRkrIAAiAgAUAAgJeRkrIAAiAgAgAAEJ2AUngwAkAAAAAA==.Erysira:BAAALgADCgkJCQABLgAECgIJAgANAAAAAA==.',
Et='Ethan:BAAALgAECgEJAgAAAA==.',
Eu='Eureka:BAABLgAECn8gAAMEAAkJTB1DCwDmAQAEAAcJ1RxDCwDmAQAFAAcJSRmSUQC1AQAAAA==.',
Ev='Evandra:BAABLgAECn8eAAIOAAgJdhpsHQA0AgAOAAgJdhpsHQA0AgAAAA==.Evanorah:BAABLgAECn8ZAAMHAAYJNwnKGwCnAAAbAAYJXAglnQDtAAAHAAYJowXKGwCnAAAAAA==.',
Ex='Exïle:BAEALgAECgYJBgABLgAFFAQJDgAQADEaAA==.',
Fa='Faelithia:BAABLgAECn8WAAIMAAYJKA7pMwARAQAMAAYJKA7pMwARAQAAAA==.Fatalbrew:BAAALgAECgUJCQAAAA==.',
Fe='Feldush:BAAALgADCgYJBgABLgAECggJJQAKAL8ZAA==.Felforit:BAAALgADCgQJBAAAAA==.Felis:BAAALgAECgYJCgAAAA==.Felkardio:BAAALgAECgIJAgAAAA==.Feloth:BAAALgADCgQJBAAAAA==.Ferheim:BAAALgAECgUJBQAAAA==.Ferrovax:BAAALgADCgYJBgABLgAECgYJGAAIAIEVAA==.',
Fi='Fiddyone:BAABLgAECn8rAAMhAAkJySHcAQDQAgAhAAkJtCHcAQDQAgAQAAgJcR1rNwD/AQAAAA==.Figment:BAAALgADCgYJBgAAAA==.Fireburt:BAAALgADCgUJBQAAAA==.Fireslay:BAABLgAECn8YAAIiAAcJpBwHHgAmAgAiAAcJpBwHHgAmAgAAAA==.',
Fl='Flarefly:BAAALgAECgEJAQAAAA==.Flaya:BAAALgAECgQJBwAAAA==.',
Fo='Fodurzin:BAAALgAECgQJDAAAAA==.Fonta:BAAALgADCgUJBwAAAA==.Fortuna:BAAALgADCgYJBgABLgAECggJFQAGALEdAA==.Foxingtobi:BAAALgADCgIJAgAAAA==.',
Fr='Frojio:BAABLgAECn8xAAIhAAkJ1BumAwBnAgAhAAkJ1BumAwBnAgAAAA==.Frosten:BAAALgADCgkJMAAAAA==.',
Fu='Furenio:BAABLgAECn8uAAITAAkJ5BeSCgAAAgATAAkJ5BeSCgAAAgAAAA==.',
Fy='Fyyre:BAAALgAECgUJBwAAAA==.',
Ga='Gabaghoul:BAACLgAFFH8JAAIFAAQJHhjUIQBQAQAFAAQJHhjUIQBQAQAuAAQKfywAAgUACQl3IFkRAMICAAUACQl3IFkRAMICAAAA.Gaff:BAAALgAECgYJDgAAAA==.Galvan:BAAALgAECgEJBAAAAA==.Gasheth:BAAALgAECgUJCAAAAA==.',
Gi='Giggleblast:BAAALgADCggJCgAAAA==.',
Gl='Glizzydealer:BAAALgAECgEJAQAAAA==.',
Gr='Grauth:BAAALgADCgEJAQAAAA==.Graycen:BAAALgAECgUJCQAAAA==.Grido:BAAALgADCgkJEQAAAA==.Grimbrindral:BAABLgAECn8hAAMFAAcJ5hZDZAC5AQAFAAcJdBVDZAC5AQAEAAUJghrKFwBZAQAAAA==.Grimston:BAAALgADCgMJAwABLgAECgcJIQAFAOYWAA==.Gruzaxx:BAAALgADCgUJBQAAAA==.',
Gu='Gulishdaniel:BAAALgAFFAMJAwABLgAFFAYJEAARAKoZAA==.',
Ha='Hadin:BAABLgAECn88AAMJAAkJciNqBwAwAwAJAAkJciNqBwAwAwAaAAMJqhysDwDHAAAAAA==.Hakeko:BAAALgAECgYJDAAAAA==.Halalnt:BAAALgAECgMJAwABLgAFFAIJBQAdAOkaAA==.Hanua:BAAALgADCgcJBwAAAA==.Haozhao:BAABLgAECn85AAMTAAkJ4Bj/CAAhAgATAAkJ4Bj/CAAhAgAWAAEJDhSDOgA6AAAAAA==.Hawktuahz:BAAALgAECgMJAwAAAA==.Hazenpryde:BAABLgAECn8YAAITAAYJzhsRFgBkAQATAAYJzhsRFgBkAQAAAA==.',
He='Hearsay:BAABLgAECn8dAAMFAAcJcQlAnAAcAQAFAAcJcQlAnAAcAQAiAAIJ6wNCcgBIAAABLgAECggJDQANAAAAAA==.Hephaistian:BAAALgADCgkJGgAAAA==.Hespera:BAABLgAECn8jAAMUAAkJySDpGABwAgAUAAgJoiHpGABwAgAgAAMJpxRSQwDNAAAAAA==.',
Hi='Hirari:BAABLgAECn8dAAMiAAYJBCUqEwBSAgAiAAYJBCUqEwBSAgAFAAEJFBqiPAFEAAAAAA==.',
Ho='Hodoor:BAAALgADCgUJBQAAAA==.Howlears:BAABLgAECn8hAAIRAAYJiQXpRQDLAAARAAYJiQXpRQDLAAAAAA==.',
Hu='Hulud:BAABLgAECn8XAAMbAAgJVRdQSQDuAQAbAAgJVRdQSQDuAQAHAAEJAABCSAAAAAAAAA==.Husbando:BAAALgADCggJCgAAAA==.Husey:BAAALgAECgMJBgAAAA==.',
Hy='Hydrangea:BAAALgAECgcJEgAAAA==.Hydrá:BAABLgAECn8aAAIbAAkJvRZXJwAlAgAbAAkJvRZXJwAlAgAAAA==.Hylan:BAAALgADCgUJBQAAAA==.Hysgar:BAAALgADCgkJDwABLgAECgYJDAANAAAAAA==.',
Ic='Iceamaris:BAABLgAECn8cAAIPAAkJYQvjLQBdAQAPAAkJYQvjLQBdAQAAAA==.Icetiger:BAAALgADCgIJAgAAAA==.Icetigress:BAAALgAECgEJAQAAAA==.',
Ie='Iechu:BAABLgAECn8VAAMYAAgJdA0/JwBXAQAYAAgJdA0/JwBXAQAZAAIJ9QY7bwBLAAAAAA==.',
In='Innanna:BAAALgADCggJCgABLgAECgYJDQANAAAAAA==.',
Is='Isoth:BAAALgAECgEJAQAAAA==.',
Iv='Ivern:BAACLgAFFH8RAAIUAAcJ8gtZCwDpAQAUAAcJ8gtZCwDpAQAuAAQKfx0AAxQABgkHHXwsANQBABQABgkHHXwsANQBACAAAgnRBzF+ACkAAAAA.Ivysnow:BAAALgAECgEJAQAAAA==.',
Ja='Jaod:BAAALgADCgkJEQAAAA==.',
Jd='Jdghoul:BAAALgAECggJDwAAAA==.',
Ji='Jindrac:BAAALgAECgMJBAAAAA==.',
Jo='Jolton:BAAALgADCgYJBwABLgAECgkJKgAIADMiAA==.',
['Jà']='Jàcaranda:BAAALgAECgEJAQAAAA==.',
Ka='Kahnrah:BAAALgADCgkJDAAAAA==.Kalarae:BAAALgAECgcJBwAAAA==.Kaltharion:BAAALgAECgUJDAAAAA==.Kaluren:BAAALgAECgcJCwAAAA==.Kalurok:BAAALgAECgUJBQABLgAECgcJCwANAAAAAA==.Kana:BAAALgAECgIJAgAAAA==.Kanade:BAABLgAECn87AAQbAAkJ8BtYHABgAgAbAAgJvxtYHABgAgAfAAcJKxV2BgDfAQAHAAMJYwUKTACJAAAAAA==.Kantong:BAABLgAECn8gAAIZAAgJdRlHFgDbAQAZAAgJdRlHFgDbAQAAAA==.Kapp:BAAALgAECgYJCwAAAA==.Karabar:BAABLgAECn87AAMEAAkJ2yCCAwCxAgAEAAkJyh6CAwCxAgAFAAgJoyAmHgBzAgAAAA==.Kasarra:BAABLgAECn8lAAIcAAkJqRN8EADsAQAcAAkJqRN8EADsAQAAAA==.Kayiku:BAAALgADCgkJDgAAAA==.Kazagol:BAABLgAECn87AAIIAAkJ+x3PFACAAgAIAAkJ+x3PFACAAgAAAA==.',
Kh='Khalla:BAAALgAECgEJAQAAAA==.Khamaracy:BAABLgAECn8VAAIHAAYJBgdXGgCyAAAHAAYJBgdXGgCyAAAAAA==.Khronni:BAAALgAECgYJCAAAAA==.Khrooze:BAAALgAECgYJEQAAAA==.',
Ki='Kidos:BAAALgAECgQJBgAAAA==.Kiljana:BAAALgAECgEJAQAAAA==.Kimahrí:BAABLgAECn8WAAIjAAYJCAnYMACsAAAjAAYJCAnYMACsAAAAAA==.Kittei:BAABLgAECn87AAITAAkJ1w8JFAB6AQATAAkJ1w8JFAB6AQAAAA==.',
Ko='Kojote:BAAALgADCgMJAQAAAA==.Kovalenko:BAAALgAECgMJBQAAAA==.',
Ku='Kurick:BAAALgAECgYJDAAAAA==.Kurzul:BAAALgADCgEJAgAAAA==.Kusinluvin:BAAALgADCgEJAQAAAA==.',
Ky='Kyngizzard:BAABLgAECn8eAAIJAAgJXRlrRgDsAQAJAAgJXRlrRgDsAQABLgAFFAIJBQAdAOkaAA==.Kytherin:BAAALgAECgYJBgAAAA==.',
La='Lactase:BAAALgADCgMJAwAAAA==.Latte:BAAALgAECgQJBAAAAA==.',
Le='Leblanc:BAAALgAECgEJAQAAAA==.Leeli:BAAALgADCgcJBwAAAA==.Lenity:BAABLgAECn8lAAIDAAYJqBVTJABEAQADAAYJqBVTJABEAQAAAA==.Letty:BAAALgAECgQJBQAAAA==.',
Li='Liabelle:BAAALgADCgIJAgAAAA==.Lightsmite:BAAALgAECgIJAgAAAA==.Lilithene:BAAALgAECgUJBgABLgAECgcJHQAOALEGAA==.Lionbark:BAAALgADCgEJAQAAAA==.Lithpally:BAAALgADCgEJAQAAAA==.Liubeijian:BAAALgADCgYJBgAAAA==.',
Lo='Lokinah:BAABLgAECn8VAAIGAAYJ6AQTpgC7AAAGAAYJ6AQTpgC7AAAAAA==.Loonytusk:BAAALgADCgQJBAAAAA==.',
Lu='Lucifermadis:BAAALgAECgQJBgAAAA==.Lucoryphus:BAABLgAECn8ZAAIjAAYJgRfQGwBLAQAjAAYJgRfQGwBLAQAAAA==.Lukeduke:BAABLgAFFH8PAAIXAAcJHx1/AwDkAQAXAAcJHx1/AwDkAQAAAA==.Luketheduke:BAACLgAFFH8ZAAMTAAYJgR7qAQDbAQATAAUJgR7qAQDbAQAWAAEJAAAIBwA3AAAuAAQKfyoAAxMACQkvJR8BAFcDABMACQkvJR8BAFcDABYABAmxFXscAAkBAAEuAAUUBwkPABcAHx0A.Lumilia:BAAALgADCgUJBQAAAA==.Lunä:BAABLgAECn8fAAIOAAkJThRqIgAQAgAOAAkJThRqIgAQAgAAAA==.',
Ly='Lydia:BAABLgAECn8pAAIJAAkJphklKgBVAgAJAAkJphklKgBVAgAAAA==.Lynnee:BAAALgADCgEJAQAAAA==.',
['Lô']='Lôckrocks:BAABLgAECn8VAAIHAAcJLxHrDABCAQAHAAcJLxHrDABCAQAAAA==.',
['Lý']='Lýsendra:BAAALgADCggJCQAAAA==.',
Ma='Magictomb:BAABLgAECn8tAAQPAAgJlxVvLQBgAQAPAAgJlxVvLQBgAQAOAAYJ6Q3gZwDrAAAkAAQJ4Ad8HwCvAAABLgAFFAIJAgANAAAAAA==.Mahdude:BAAALgADCgEJAQAAAA==.Malastor:BAAALgAECgEJAQABLgAECggJEgANAAAAAA==.Malcontent:BAAALgAECgQJBQABLgAECggJEgANAAAAAA==.Maldazane:BAAALgADCgYJCwAAAA==.Malfeasance:BAAALgADCgkJDQABLgAECggJEgANAAAAAA==.Malidan:BAAALgADCgMJAwAAAA==.Malifel:BAAALgAECggJEgAAAA==.Maliss:BAABLgAECn8+AAQBAAkJRRjADwAZAgABAAkJahfADwAZAgACAAQJ8RGSHACnAAAGAAEJoxHV8AA8AAAAAA==.Mallord:BAAALgAECgYJDgABLgAECggJEgANAAAAAA==.Mandarin:BAABLgAECn8nAAIUAAgJ/hmRGgBNAgAUAAgJ/hmRGgBNAgAAAA==.Manmythlegnd:BAAALgADCgYJBgAAAA==.Mannik:BAABLgAECn8UAAIbAAcJERiYSgCkAQAbAAcJERiYSgCkAQAAAA==.Marashades:BAAALgADCgQJBAABLgAECggJHAAXAOAjAA==.',
Mc='Mcbadden:BAAALgAECgYJCAAAAA==.',
Me='Meditatetoe:BAAALgADCgIJAgABLgADCgYJBgANAAAAAA==.Melissà:BAAALgADCgMJAwAAAA==.Menesta:BAAALgADCgcJBwABLgAECgQJDAANAAAAAA==.Mercia:BAABLgAECn8sAAIEAAkJABjTCQABAgAEAAkJABjTCQABAgAAAA==.Merekoma:BAABLgAECn8YAAMIAAYJgRU6dQAQAQAIAAYJ1BM6dQAQAQAlAAMJKw9zJABfAAAAAA==.',
Mi='Milarra:BAAALgAECgcJDAAAAA==.Milhouse:BAAALgAECgQJCQAAAA==.Minalan:BAAALgADCgYJCgABLgAECgYJEQANAAAAAA==.Mingonashoba:BAABLgAECn8YAAIGAAgJkQweTwCHAQAGAAgJkQweTwCHAQAAAA==.Miragosa:BAABLgAECn8hAAMKAAkJlgQ/KgAgAQAKAAkJlgQ/KgAgAQALAAEJ8AESJQAaAAAAAA==.Misschris:BAABLgAECn8cAAIVAAgJkAisPwAWAQAVAAgJkAisPwAWAQAAAA==.Mizu:BAAALgAECgUJBQAAAA==.',
Mo='Moadeed:BAAALgAECggJCwAAAA==.Mooluv:BAAALgADCgcJCgAAAA==.Moonstrike:BAAALgAECgIJAgAAAA==.Mordrius:BAAALgADCgYJBgAAAA==.Mortesque:BAAALgAECgcJEgAAAA==.',
Mu='Muttblitzed:BAAALgAECgYJDwAAAA==.Muttskî:BAAALgAECgMJAwAAAA==.',
My='Mybutt:BAAALgAECgMJBgAAAA==.Myrothos:BAAALgADCgEJAQAAAA==.Myrrh:BAABLgAECn8YAAMdAAYJdAdQUADCAAAdAAYJggZQUADCAAALAAQJ9wYzLQCxAAAAAA==.',
['Mí']='Místermage:BAAALgAECgQJCAAAAA==.',
Na='Nasturtium:BAAALgADCgYJDgAAAA==.Naturestone:BAAALgAFFAIJAgAAAA==.Nausican:BAABLgAECn8xAAIhAAkJ6BXLBQASAgAhAAkJ6BXLBQASAgAAAA==.Nazuhda:BAAALgADCgEJAQAAAA==.',
Ne='Necrosector:BAABLgAECn8mAAIFAAgJuRn+OwDzAQAFAAgJuRn+OwDzAQAAAA==.Necrotherys:BAABLgAECn8oAAIIAAgJ3RyAHwA6AgAIAAgJ3RyAHwA6AgAAAA==.Nelandra:BAABLgAECn8WAAIRAAYJWRtPIwCGAQARAAYJWRtPIwCGAQAAAA==.',
Ni='Nicklaus:BAABLgAECn8YAAIDAAYJvwlCLgD6AAADAAYJvwlCLgD6AAAAAA==.Nilrem:BAAALgADCgIJAgAAAA==.Ninelives:BAAALgAECgYJDgAAAA==.Ninjadk:BAECLgAFFH8OAAIQAAQJMRrmOwBMAQAQAAQJMRrmOwBMAQAuAAQKfzEAAxAACQmyIUsKAP8CABAACQmyIUsKAP8CACEAAQm4G9AnAEAAAAAA.',
No='Nocapongfrfr:BAAALgAECgMJAwABLgAFFAQJEAAdAJ8QAA==.Nomahuata:BAABLgAECn9BAAIPAAkJ9BeHEgAwAgAPAAkJ9BeHEgAwAgAAAA==.Nordre:BAAALgAECgMJAwAAAA==.',
Nu='Nufrus:BAAALgADCgYJBgAAAA==.',
Ny='Nyeli:BAAALgAECgIJAgABLgAECgYJEwANAAAAAA==.Nyxi:BAAALgAECgYJEQAAAA==.Nyxlee:BAAALgAECgcJBwAAAA==.',
['Né']='Néo:BAAALgAECgUJCAAAAA==.',
['Nó']='Nóóôööôòòpe:BAAALgAECgEJAQABLgAFFAQJEAAdAJ8QAA==.',
Og='Ogdruid:BAAALgADCgcJDgAAAA==.',
Ol='Olympian:BAAALgADCgcJBwAAAA==.',
Om='Omanyte:BAAALgADCgcJBwAAAA==.',
On='Onefiftyone:BAABLgAECn8bAAMkAAYJHCXJBwAdAgAkAAYJHCXJBwAdAgAOAAIJnSS9cgDJAAABLgAECgkJKwAhAMkhAA==.',
Or='Orruk:BAAALgADCgMJAwAAAA==.Orwyn:BAAALgADCgkJEgAAAA==.',
Ov='Overdose:BAAALgADCgMJAwAAAA==.',
Pa='Padmé:BAAALgAECgQJBQAAAA==.Pain:BAAALgAECgQJBAAAAA==.Palanas:BAAALgAFFAEJAQAAAA==.Pallamoo:BAAALgADCgYJBgAAAA==.Palochka:BAAALgAECgUJBQAAAA==.Paradots:BAABLgAECn8WAAIKAAYJwBpMEACgAQAKAAYJwBpMEACgAQABLgADCgYJBgANAAAAAA==.Paranitis:BAAALgAECggJDAAAAA==.Paranorm:BAAALgADCgEJAQAAAA==.Paraparaboom:BAAALgAECgUJBQABLgAECggJGAAJAGkbAA==.',
Pe='Petronella:BAABLgAECn81AAMmAAkJbw3CEwCZAQAmAAkJbw3CEwCZAQAeAAQJ+wNjgwCxAAAAAA==.Pezmage:BAAALgAECgIJBAAAAA==.',
Ph='Phatboi:BAAALgADCgIJAwAAAA==.Pheroth:BAAALgADCgkJEAABLgAECgYJFQAHAJULAA==.',
Pi='Pixystix:BAABLgAECn8ZAAIIAAYJDRmxUwBoAQAIAAYJDRmxUwBoAQAAAA==.',
Po='Poisonspain:BAAALgAECgMJAwAAAA==.Popsdh:BAAALgAECgcJDgABLgAECgkJIAAEAEwdAA==.Potscold:BAACLgAFFH8PAAIJAAcJJhWGDAC5AQAJAAcJJhWGDAC5AQAuAAQKf0EAAgkACAnbJbsRAD0DAAkACAnbJbsRAD0DAAAA.Poxi:BAAALgAECgIJAgABLgAECggJGAAJADwdAA==.',
Pr='Prion:BAABLgAECn8bAAIeAAcJBhZNKwCCAQAeAAcJBhZNKwCCAQAAAA==.',
Pu='Pull:BAABLgAECn8gAAITAAgJOhw/CgAGAgATAAgJOhw/CgAGAgAAAA==.',
Ra='Radioshack:BAAALgADCggJCAAAAA==.Radkemonko:BAAALgAECgcJDwAAAA==.Raega:BAAALgADCgYJBgAAAA==.Ragerlock:BAAALgADCgEJAQAAAA==.Raivel:BAAALgAECgYJEwAAAA==.Raldaron:BAAALgADCgEJAQAAAA==.Raneyth:BAAALgAECgUJBQAAAA==.Ravagèr:BAAALgAECgEJAgAAAA==.',
Rd='Rdbwarrior:BAAALgADCgUJBQAAAA==.',
Re='Redemus:BAAALgADCgEJAQAAAA==.Redwinetoast:BAABLgAECn8bAAIbAAgJSwQCnwDqAAAbAAgJSwQCnwDqAAAAAA==.Reliala:BAAALgADCgkJEQAAAA==.Reno:BAAALgADCgkJEAAAAA==.Reshyk:BAAALgAECggJEgAAAA==.Resles:BAAALgAECgEJAQAAAA==.Respectwomen:BAAALgADCgEJAQABLgAECgQJBAANAAAAAA==.',
Rh='Rhobes:BAAALgAECgcJCwAAAA==.Rhondta:BAABLgAECn8eAAIbAAgJXQ8WWAB/AQAbAAgJXQ8WWAB/AQAAAA==.',
Ri='Rickormortis:BAAALgAECgYJCAABLgAECggJHAAVAJAIAA==.Rictus:BAABLgAECn8wAAIJAAkJjSRjBQBKAwAJAAkJjSRjBQBKAwAAAA==.Ringmasterr:BAAALgADCgUJBQAAAA==.Riordaa:BAAALgADCgYJDAAAAA==.Risingdragon:BAABLgAECn8iAAIZAAYJdBTLLQApAQAZAAYJdBTLLQApAQAAAA==.',
Ro='Roades:BAAALgADCgcJDAAAAA==.Roboskritch:BAAALgADCgUJBQAAAA==.Ronaj:BAAALgADCgMJBAAAAA==.Royveer:BAAALgADCgYJCQAAAA==.',
Ru='Rumor:BAAALgAECggJDQAAAA==.Rurry:BAACLgAFFH8YAAIKAAYJpRe+BACuAQAKAAYJpRe+BACuAQAuAAQKfy4ABAoACQnIIrECAEADAAoACQnIIrECAEADAAsABQm6GR4WAI8BAB0AAwlVF/RGAL8AAAEuAAUUBwkRABQA8gsA.',
Ry='Ryumi:BAABLgAECn8qAAIIAAkJMyJFEgCTAgAIAAkJMyJFEgCTAgAAAA==.Ryur:BAAALgAECgQJDgAAAA==.',
Sa='Sabastion:BAAALgAECgYJBgABLgAECggJEgANAAAAAA==.Sacrickficed:BAAALgAECgQJBAABLgAECggJHAAVAJAIAA==.Sahwe:BAAALgAECgYJDgAAAA==.Salocar:BAAALgAECgcJEwAAAA==.Sanafela:BAAALgADCgkJOgAAAA==.Saphisha:BAAALgAECgcJEAAAAA==.Sasora:BAAALgAECgUJCgAAAA==.Saucemagic:BAAALgAECgcJDQAAAA==.Savonah:BAAALgAECgEJAQAAAA==.',
Sc='Scaledaddy:BAABLgAECn8dAAIdAAkJDg18JACXAQAdAAkJDg18JACXAQAAAA==.Scalespawn:BAAALgADCgYJBgABLgAFFAcJGgAQACYbAA==.Scaryl:BAAALgAECgYJBgAAAA==.Scourgespawn:BAACLgAFFH8aAAMQAAcJJht/DAADAgAQAAYJJht/DAADAgAjAAIJpwjMMAAvAAAuAAQKfyoAAxAACQmyIDMkAK0CABAACQmyIDMkAK0CACMABAnhFV4vALQAAAAA.',
Se='Selenë:BAAALgAECgUJDQAAAA==.Sengoku:BAAALgAECgEJAQAAAA==.Serbiscuit:BAAALgAECgUJCgAAAA==.Sereneya:BAAALgADCgcJBwAAAA==.Serenio:BAAALgAECgQJBAAAAA==.Serenval:BAAALgADCgkJCQAAAA==.',
Sh='Shadowshart:BAAALgAECgEJAQAAAA==.Shait:BAAALgADCgYJBgAAAA==.Shalis:BAABLgAECn8bAAIGAAgJLBs+MADxAQAGAAgJLBs+MADxAQAAAA==.Sharivee:BAAALgAECggJEQAAAA==.Sharko:BAABLgAECn8cAAQEAAgJExeSDwDMAQAEAAcJzhWSDwDMAQAFAAUJhBlUjAA4AQAiAAIJwgOQiwBPAAAAAA==.Shibui:BAABLgAECn86AAMcAAkJGRhBCwA+AgAcAAkJGRhBCwA+AgAIAAcJvAYvowDNAAAAAA==.Shiggles:BAABLgAECn8bAAIQAAkJvxmJIwBVAgAQAAkJvxmJIwBVAgABLgAFFAIJBQAFAHUVAA==.Shinhaein:BAABLgAECn8UAAIJAAYJ2BSRsAB8AQAJAAYJ2BSRsAB8AQABLgAFFAQJEQAQAAMaAA==.Shinxu:BAAALgADCgQJBAAAAA==.Shockazilla:BAABLgAECn82AAMiAAkJbR5NBgAJAwAiAAkJbR5NBgAJAwAFAAMJVw+z/wCWAAAAAA==.Shreddarfort:BAAALgADCgkJFQAAAA==.Shönuff:BAAALgAECgEJAQAAAA==.',
Si='Sigh:BAAALgAFFAEJAQAAAA==.Silverhorn:BAABLgAECn8XAAIFAAcJixazdABlAQAFAAcJixazdABlAQAAAA==.',
Sk='Skoduh:BAABLgAECn8gAAIGAAcJQhw7PQDAAQAGAAcJQhw7PQDAAQAAAA==.Skyelene:BAABLgAECn8dAAMOAAcJsQbOZQDyAAAOAAcJsQbOZQDyAAAPAAcJHxIoRwDmAAAAAA==.',
Sl='Slaanesh:BAABLgAECn8YAAQHAAcJ6hbyDABCAQAHAAYJJhbyDABCAQAfAAMJlhsqFwDFAAAbAAMJzw5DxACmAAAAAA==.Sluggo:BAABLgAFFH8GAAIFAAQJ/xEtMwAoAQAFAAQJ/xEtMwAoAQAAAA==.Sluggoboyce:BAACLgAFFH8GAAICAAQJhgR9EwAHAQACAAQJhgR9EwAHAQAuAAQKfyIAAwIACAkLGSEcAEcCAAIACAnYGCEcAEcCAAYABAmEDS6aAJ8AAAAA.',
Sm='Smeagosses:BAAALgAECgEJAQAAAA==.Smokeü:BAAALgAECgcJBwAAAA==.',
So='Solace:BAAALgAECgYJDAAAAA==.Solinaara:BAAALgADCgEJAQAAAA==.Soraka:BAABLgAFFH8KAAISAAQJnQrTHQAbAQASAAQJnQrTHQAbAQAAAA==.',
Sp='Spiralist:BAABLgAECn8cAAQgAAgJCRuZLgA3AQAgAAYJARmZLgA3AQAUAAcJXhfHUQAlAQAWAAIJkAyVMQBaAAAAAA==.Spiralmist:BAAALgADCgUJBQAAAA==.',
St='Starge:BAAALgAECgUJBQAAAA==.Steelforged:BAAALgADCgcJBwABLgAECgYJEAANAAAAAA==.Stonedalways:BAAALgAECgYJEgAAAA==.',
Su='Sunfuri:BAABLgAECn85AAIeAAkJDQolKwCDAQAeAAkJDQolKwCDAQAAAA==.Sunjan:BAAALgAECgMJAwAAAA==.Sus:BAACLgAFFH8eAAIcAAcJ7RsDAQAgAgAcAAcJ7RsDAQAgAgAuAAQKfyUAAhwACQmXI5cDAEcDABwACQmXI5cDAEcDAAAA.Susanoo:BAABLgAECn8YAAIeAAkJcRQPHQDhAQAeAAkJcRQPHQDhAQAAAA==.',
Sy='Sylvíadne:BAAALgAECgYJBgAAAA==.',
Sz='Szul:BAAALgADCgcJDAAAAA==.',
Ta='Tachima:BAAALgAECgQJBAABLgAECgkJKgAIADMiAA==.Tactics:BAAALgADCgcJDAAAAA==.Tahitimango:BAABLgAECn8aAAIIAAYJOwMYugCDAAAIAAYJOwMYugCDAAAAAA==.Takeko:BAAALgADCgcJDgABLgAECgYJDAANAAAAAA==.Talanas:BAAALgADCgcJBwAAAA==.Taleria:BAAALgADCgYJFgAAAA==.Taranad:BAAALgAECgcJDAAAAA==.Tarathor:BAABLgAECn8WAAIgAAYJmxjKKABaAQAgAAYJmxjKKABaAQAAAA==.Tasha:BAAALgAECgEJAwABLgAECgcJGwAeAAYWAA==.Tauroctony:BAABLgAECn8eAAITAAgJKiGhBACiAgATAAgJKiGhBACiAgAAAA==.',
Te='Tea:BAAALgAECgYJCgABLgAECgkJNgAMAO0TAA==.Teknofarious:BAAALgAECgEJAgAAAA==.Tenom:BAAALgAECgUJCgAAAA==.',
Th='Thalar:BAAALgAECgIJAgAAAA==.Thaumas:BAAALgADCgEJAQAAAA==.Thelsyn:BAAALgAECgIJAgABLgAECgkJPgABAEUYAA==.Thesafe:BAAALgAECgMJAwAAAA==.Thialaa:BAAALgAECgEJAwABLgAECgkJNQAGAP0fAA==.Thialia:BAAALgAECgkJEwABLgAECgkJNQAGAP0fAA==.Thorey:BAAALgAECgEJAQAAAA==.Thornbreaker:BAAALgADCgEJAQAAAA==.Thorthunda:BAAALgAECgQJBgAAAA==.',
Ti='Tinkabella:BAABLgAECn87AAISAAkJLiOZAQCgAwASAAkJLiOZAQCgAwAAAA==.Tizl:BAEALgAECgUJBQABLgAFFAQJDgAQADEaAA==.',
To='Tobiblindpaw:BAAALgAECgUJCQAAAA==.Toenailjuice:BAAALgADCgUJBQABLgAECgkJOwAVAKkjAA==.Torrey:BAABLgAECn8YAAIiAAgJHyVuAwA8AwAiAAgJHyVuAwA8AwAAAA==.',
Tr='Trema:BAAALgAECgEJAgAAAA==.Trix:BAABLgAECn8vAAIOAAgJHw3rSABXAQAOAAgJHw3rSABXAQAAAA==.',
Tu='Tulsami:BAAALgAECgIJAgAAAA==.Tulsi:BAABLgAECn83AAInAAkJRSR/AABIAwAnAAkJRSR/AABIAwAAAA==.Tuskoo:BAAALgAECgcJEQAAAA==.',
Ty='Tyrathion:BAAALgAECgMJAwAAAA==.Tyronos:BAABLgAECn8XAAIFAAYJ3hWhlwAkAQAFAAYJ3hWhlwAkAQAAAA==.',
Uk='Uknôwnforce:BAAALgAECgMJBAAAAA==.',
Un='Unbeetable:BAAALgADCgUJBQAAAA==.',
Va='Valanoth:BAABLgAECn8jAAIIAAgJ1SCcFwBrAgAIAAgJ1SCcFwBrAgAAAA==.Valdr:BAABLgAECn8eAAMdAAgJQRLUJgCJAQAdAAgJQRLUJgCJAQALAAQJowzXKQDQAAAAAA==.Valoryck:BAAALgAECgQJDQABLgAECggJIwAIANUgAA==.Vas:BAAALgADCgYJHAAAAA==.',
Ve='Velielina:BAAALgAECgEJAQAAAA==.Velistos:BAAALgADCgEJAQAAAA==.Vellandrias:BAAALgADCgYJBgAAAA==.Verinda:BAAALgADCgcJDwAAAA==.Vessara:BAAALgADCgUJBQABLgAFFAIJAgANAAAAAA==.Vevicenth:BAAALgAECgkJDgAAAA==.',
Vo='Voranth:BAAALgADCgMJAwAAAA==.',
Wa='Warpsbulge:BAACLgAFFH8cAAIJAAYJkh5lCgDMAQAJAAYJkh5lCgDMAQAuAAQKfxsAAwkACQlNIb4hAOwCAAkACQlNIb4hAOwCABoAAgl2FLQTAIoAAAAA.',
Wh='Whakan:BAAALgAECgEJAgABLgAECgYJGQAjAIEXAA==.',
Wo='Wolfos:BAABLgAECn8fAAITAAkJEiZPAAB4AwATAAkJEiZPAAB4AwAAAA==.',
Wt='Wtfox:BAEALgAECgYJDwABLgAECggJKAAPAG4XAA==.',
Wu='Wulfgange:BAAALgADCgEJAQAAAA==.',
Wy='Wysteri:BAAALgAECgYJDQAAAA==.',
Xa='Xadrai:BAAALgADCgIJAgAAAA==.Xakeko:BAAALgAECgQJCgABLgAECgYJDAANAAAAAA==.Xalatos:BAAALgAECgEJAQAAAA==.Xalfein:BAAALgADCgkJKwAAAA==.',
Xi='Xinu:BAAALgADCgYJBgABLgAECgkJQAAGABsdAA==.',
Ya='Yanakana:BAAALgAECgUJBQAAAA==.',
Yd='Ydalise:BAAALgAECgEJAgAAAA==.Ydrassil:BAAALgAECggJEwABLgAECgkJIAAEAEwdAA==.',
Yi='Yitsuni:BAAALgAECgcJDQAAAA==.',
Za='Zalaeda:BAAALgAECgEJAQAAAA==.Zalena:BAAALgAECgQJCAAAAA==.Zatriani:BAAALgAECgYJCgAAAA==.',
Ze='Zenus:BAABLgAECn8iAAMGAAgJsxWjQQCxAQAGAAgJsxWjQQCxAQACAAMJqwfOLQBGAAAAAA==.Zerina:BAAALgADCgUJBQAAAA==.Zesty:BAAALgADCgMJAwAAAA==.Zeusal:BAABLgAECn8VAAIgAAcJyQb1PQDmAAAgAAcJyQb1PQDmAAAAAA==.Zeusinator:BAABLgAECn8hAAIGAAgJ/Ba1NgDYAQAGAAgJ/Ba1NgDYAQAAAA==.',
Zi='Zinu:BAABLgAECn9AAAIGAAkJGx1GFACHAgAGAAkJGx1GFACHAgAAAA==.Zivalisse:BAAALgAECgQJBAAAAA==.',
Zu='Zulfionn:BAABLgAECn8hAAIGAAgJeAqjWQBpAQAGAAgJeAqjWQBpAQAAAA==.',
['Áy']='Áyrá:BAABLgAECn8dAAIiAAgJohs+GgAMAgAiAAgJohs+GgAMAgAAAA==.',
['Åp']='Åpollyon:BAAALgAECgIJAgAAAA==.',
['Øu']='Øuroboros:BAABLgAECn8lAAQKAAgJvxkaCgAcAgAKAAcJyxoaCgAcAgALAAYJ5hp8FAChAQAdAAQJ1heQRQDHAAAAAA==.',
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
