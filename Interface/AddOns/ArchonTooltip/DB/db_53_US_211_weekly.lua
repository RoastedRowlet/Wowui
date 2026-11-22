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

local lookup = {'Paladin-Protection','Monk-Windwalker','Warrior-Arms','Paladin-Retribution','Monk-Brewmaster','Priest-Holy','Shaman-Restoration','DemonHunter-Devourer','Druid-Restoration','Unknown-Unknown','Rogue-Assassination','Hunter-Survival','Druid-Balance','DeathKnight-Blood','Shaman-Elemental','Mage-Arcane','Warrior-Protection','Warrior-Fury','Paladin-Holy','DemonHunter-Vengeance','Druid-Feral','Hunter-BeastMastery','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Mage-Frost','Priest-Discipline','DemonHunter-Havoc','Priest-Shadow','Evoker-Augmentation','Monk-Mistweaver','Hunter-Marksmanship','Shaman-Enhancement','Rogue-Subtlety','DeathKnight-Frost','Rogue-Outlaw','Druid-Guardian','Evoker-Devastation','Warlock-Affliction','Mage-Fire','Evoker-Preservation',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abysslicker:BAAANQADCggIFAAAAA==.',
Ac='Achooe:BAABNQAECn8yAAIBAAgKIwSCPAC5AAABAAgKIwSCPAC5AAAAAA==.Acrylic:BAAANQAECgIIAQAAAA==.',
Ad='Ado:BAABNQAECn8WAAICAAoK3A9sIwCAAQACAAoK3A9sIwCAAQAAAA==.Adrel:BAAANQAECgYIBQAAAA==.Adversity:BAACNQAFFH8JAAIDAAUKNhyzJQDTAAADAAUKNhyzJQDTAAA1AAQKfx4AAgMACgoZIj0nAKMCAAMACgoZIj0nAKMCAAAA.',
Ae='Aegeus:BAAANQADCggICQAAAA==.Aenil:BAAANQADCgMIAwAAAA==.Aevintz:BAAANQAECgcICgAAAA==.',
Ai='Aiolii:BAABNQAECn8eAAIEAAgKCRMFyQBDAQAEAAgKCRMFyQBDAQAAAA==.Aisling:BAAANQADCgQIBAAAAA==.',
Ak='Akiras:BAAANQABCgYIDAAAAA==.',
Al='Alanala:BAAANQABCgQIBAAAAA==.Alarielle:BAAANQAECgIIAgABNQAECggIKQAFAKYgAA==.Alcestis:BAAANQADCgIIAgAAAA==.Aldea:BAAANQAECgUIEAABNQAECgoKLQAGAA0dAA==.Alexeika:BAAANQAECgYIBgAAAA==.Aliseadyn:BAAANQAECgEIAQABNQAECggIFgAHAJscAA==.Alyndrya:BAABNQAECn9cAAIIAAoK1hNDGADxAQAIAAoK1hNDGADxAQAAAA==.',
Am='Amithralia:BAABNQAECn8xAAIJAAoKZCEwCQBBAwAJAAoKZCEwCQBBAwAAAA==.',
An='Anejo:BAAANQAECgQIBAAAAA==.Ankari:BAAANQADCgEIAQAAAA==.Anorodiomm:BAAANQADCgUIBQAAAA==.Ansdusk:BAAANQAECggIEwAAAA==.Anzarna:BAAANQAECgUIBwABNQAECgUIDwAKAAAAAA==.',
Ao='Aohikari:BAAANQAECgQICAABNQAFFAgIGwAHANEXAA==.',
Ap='Apples:BAAANQADCgMIAwAAAA==.Aprigity:BAABNQAECn8aAAILAAoKxQ+9DwDMAQALAAoKxQ+9DwDMAQAAAA==.',
Aq='Aquaten:BAABNQAECn8lAAIMAAgKWxN1BwCpAQAMAAgKWxN1BwCpAQAAAA==.',
Ar='Arashinigon:BAABNQAECn8kAAMNAAgKfw0fPgAyAQANAAcKhAwfPgAyAQAJAAYKoxE6QQAdAQAAAA==.Arcafrost:BAAANQAECggIAQAAAA==.Arceus:BAABNQAECn8UAAIOAAYKKgc0XwDHAAAOAAYKKgc0XwDHAAAAAA==.Arick:BAABNQAECn8VAAIEAAgK3hS7zgB+AQAEAAgK3hS7zgB+AQAAAA==.Ark:BAABNQAECn9nAAMHAAoK+iYSAAAFBAAHAAoK+iYSAAAFBAAPAAIKQiGE2wBeAAAAAA==.',
At='Atanker:BAAANQADCgMIAwAAAA==.',
Au='Aunn:BAAANQAECgYICgAAAA==.Aureia:BAABNQAECn8UAAMPAAkKOB24SQBQAgAPAAkKOB24SQBQAgAHAAEKHA3pHAEzAAAAAA==.Auriea:BAAANQAECgQIAgABNQAECgkJFAAPADgdAA==.',
Ax='Axon:BAABNQAECn88AAIQAAoKXQ7XZADsAQAQAAoKXQ7XZADsAQAAAA==.',
Ay='Aybarak:BAAANQAECgcIBwAAAA==.',
Ba='Baaku:BAAANQAECgUIBgAAAA==.Baelhay:BAABNQAECn8mAAMRAAgK1wNLKQC0AAARAAgK1wNLKQC0AAASAAEKAABjOwAcAAAAAA==.Ballard:BAAANQADCgMIAwAAAA==.Barrelroll:BAAANQADCggIEwAAAA==.Bashon:BAABNQAECn9TAAMHAAoKwB2fGQDpAgAHAAoKwB2fGQDpAgAPAAEKAAABWQEgAAAAAA==.Battlebot:BAAANQAECgUIDAAAAA==.',
Be='Beet:BAABNQAECn85AAICAAkKOyFXCwCqAgACAAkKOyFXCwCqAgAAAA==.Belgaron:BAAANQAECggIEgABNQAECgoKRgACAHIYAA==.Belitha:BAABNQAECn8yAAIIAAoKOSH3DAAUAwAIAAoKOSH3DAAUAwAAAA==.Belmaris:BAABNQAECn83AAILAAoK3Bm9CABcAgALAAoK3Bm9CABcAgAAAA==.Beriana:BAAANQAECgQIBAABNQAECgoKHgATABARAA==.Betëlgeuse:BAAANQADCgUICQAAAA==.',
Bi='Bigcupcakes:BAAANQAECgUICgAAAA==.Bigdruid:BAAANQAECgIIAwABNQAECggICwAKAAAAAA==.Biloughah:BAAANQAECgIIAgAAAA==.Bimbosuzi:BAAANQAECgUIDAAAAA==.Bingbing:BAAANQADCgUIBAAAAA==.Binghealing:BAAANQADCgEIAQAAAA==.',
Bl='Blasteyes:BAABNQAECn8uAAIUAAkKAxyKCQBOAgAUAAkKAxyKCQBOAgAAAA==.Bloomharvest:BAAANQADCgEIAQAAAA==.Bluegrass:BAABNQAECn9IAAIVAAoKfiJuAwALAwAVAAoKfiJuAwALAwAAAA==.',
Bo='Borc:BAAANQADCgcIGwAAAA==.Borik:BAABNQAECn8pAAIFAAgKpiAQBQBaAgAFAAgKpiAQBQBaAgAAAA==.',
Br='Brat:BAAANQADCgcIBwABNQAFFAkJMAAGANgcAA==.Brighteye:BAAANQAECgQIBAAAAA==.Brindis:BAAANQAECgYIDgAAAA==.Brisket:BAAANQADCggIJAABNQAECgEIAQAKAAAAAA==.Brutalicious:BAAANQADCgIIAgAAAA==.',
Bu='Bubblebut:BAABNQAECn8/AAITAAoKsx8TEQA0AwATAAoKsx8TEQA0AwAAAA==.Bubbs:BAAANQADCgQIBAABNQAECgoKQgACAAslAA==.Buckme:BAABNQAECn8pAAIWAAoK4RiyMwDRAgAWAAoK4RiyMwDRAgAAAA==.Bulova:BAAANQAECgQIBAAAAA==.Bunnygirl:BAAANQAECgIIAgABNQAFFAkJJAAXAFEfAA==.Busen:BAAANQADCggIHQAAAA==.',
By='Byungsoon:BAAANQADCgQIBAAAAA==.',
['Bà']='Bàal:BAABNQAECn8hAAMXAAoKqxJjUwBcAgAXAAoKqxJjUwBcAgAYAAEKNxFMcwA7AAAAAA==.',
Ca='Caiphage:BAAANQAECgIIAgAAAA==.Caladelm:BAABNQAECn8dAAIEAAgK6BMAowCIAQAEAAgK6BMAowCIAQAAAA==.Caralhan:BAABNQAECn8aAAIZAAgK8grEOAA2AQAZAAgK8grEOAA2AQAAAA==.Castelo:BAAANQAECggIEQAAAA==.',
Ce='Cedra:BAABNQAECn9RAAMQAAoKDSSQGAByAwAQAAoK9iOQGAByAwAaAAIKnh9nJwClAAAAAA==.Cegeo:BAABNQAECn81AAIYAAoKWhOJBADJAQAYAAoKWhOJBADJAQAAAA==.Celari:BAAANQAECgEIAQAAAA==.Celinari:BAAANQADCgEIAQAAAA==.Centric:BAAANQADCgcIBwAAAA==.',
Ch='Cheepdeeps:BAABNQAECn9GAAIDAAoKvRyELQCIAgADAAoKvRyELQCIAgAAAA==.Chelea:BAAANQADCggIFAAAAA==.Chidora:BAAANQADCgcIBwAAAA==.Chocoworm:BAAANQADCgMIAgAAAA==.Chìpotle:BAAANQADCgYICgAAAA==.',
Ci='Ciennajewel:BAABNQAECn8mAAIGAAoK2hVIMQB9AgAGAAoK2hVIMQB9AgAAAA==.Cirdle:BAABNQAECn8yAAIWAAgKiBKceADLAQAWAAgKiBKceADLAQAAAA==.',
Co='Cobalt:BAACNQAFFH8LAAIXAAQKLA7EHQDDAAAXAAQKLA7EHQDDAAA1AAQKfywAAhcACgqxHrwgAAEDABcACgqxHrwgAAEDAAE1AAUUBggKABcAexEA.Coolkid:BAAANQAECgMJBAAAAA==.Corntard:BAAANQADCggIGAAAAA==.',
Cr='Crazynlazy:BAABNQAECn8bAAIPAAcKcgOy0QDwAAAPAAcKcgOy0QDwAAAAAA==.Creamtastic:BAAANQAECgIIAgABNQAECgoKOAAHAPUfAA==.Crucifixea:BAABNQAECn8sAAMTAAkKEBRNSABGAgATAAgKoBVNSABGAgABAAkK/xPaIQBfAQABNQAFFAUIDgAGAAARAA==.Cruxsader:BAAANQADCggIEAAAAA==.Crystyl:BAABNQAECn8lAAIaAAgKGA5OEwBYAQAaAAgKGA5OEwBYAQAAAA==.',
Ct='Ctesias:BAAANQADCgYIBgAAAA==.',
Cu='Cuddly:BAAANQAECgcIBwABNQAFFAkJGwAbAMoYAA==.Cute:BAAANQAECgYIBgABNQAFFAkJMAAGANgcAA==.',
Cy='Cymoril:BAABNQAECn9EAAIDAAoKZhsfPgBJAgADAAoKZhsfPgBJAgAAAA==.',
Da='Daamass:BAAANQAECgIIAgAAAA==.Dagyrr:BAAANQADCgEIAQAAAA==.Dalman:BAAANQAECgQIBgAAAA==.Dalmin:BAAANQADCggICAAAAA==.Dalov:BAABNQAECn8lAAIWAAoKLRttRQBIAgAWAAoKLRttRQBIAgAAAA==.Darkcarnival:BAABNQAECn8wAAIXAAoKDBJrUADjAQAXAAoKDBJrUADjAQAAAA==.Darkkill:BAAANQADCgMIAwABNQAECgoKKQAHAFQjAA==.Darthraider:BAABNQAECn8aAAIZAAYKlwUIVwCqAAAZAAYKlwUIVwCqAAAAAA==.Dasnotgood:BAAANQADCggIHwAAAA==.',
De='Deemon:BAABNQAECn8lAAMIAAoKQBb4MgCqAQAIAAcKtxj4MgCqAQAcAAUKJhJ1XQCtAAAAAA==.Delathatha:BAAANQADCgcICwAAAA==.Demiish:BAAANQADCgEIAQAAAA==.Demorjan:BAAANQADCggIFgAAAA==.Denard:BAAANQADCggIFQABNQAECgEIAQAKAAAAAA==.Denarias:BAAANQADCgUIBQABNQAECgUIDwAKAAAAAA==.Denevien:BAABNQAECn8eAAMGAAkKoRUbVgDkAQAGAAgKMRUbVgDkAQAdAAIKeAYtdwA4AAAAAA==.Desdemona:BAABNQAECn8rAAIBAAgKxxBnKgAiAQABAAgKxxBnKgAiAQAAAA==.Dethiaris:BAABNQAECn8XAAIZAAgK8hRXKgCSAQAZAAgK8hRXKgCSAQAAAA==.',
Di='Diablojr:BAAANQAECgUIDAAAAA==.Dianimal:BAAANQAECgMIAwAAAA==.Distroya:BAAANQAECgQIBAAAAA==.',
Dk='Dkaiseremp:BAABNQAECn8kAAIeAAoK3AftCwCcAQAeAAoK3AftCwCcAQABNQAECgoKKQARAJcGAA==.',
Do='Dobutsu:BAABNQAECn8fAAINAAoKyhzpEACkAgANAAoKyhzpEACkAgAAAA==.Dog:BAACNQAFFH8aAAIfAAUKyCaHAgAfAgAfAAUKyCaHAgAfAgA1AAQKfwwBAh8ACgoOJwIAAKMEAB8ACgoOJwIAAKMEAAAA.Doomace:BAABNQAECn9DAAMEAAoKnBS8fwAqAgAEAAoKnBS8fwAqAgABAAEKwgFHdAAaAAAAAA==.',
Dr='Draaka:BAAANQADCgYIDgAAAA==.Dragee:BAAANQAECgYIBgABNQAECgoKJQAIAEAWAA==.Dragon:BAABNQAECn8YAAMMAAoKTRiwAwBkAgAMAAkKNRewAwBkAgAWAAMKKRWGEgGNAAAAAA==.Driftyshaman:BAAANQAECgUICwAAAA==.Droopy:BAAANQAECgcIEwAAAA==.Dræghoule:BAABNQAECn8jAAIZAAgKhgiiOwAnAQAZAAgKhgiiOwAnAQAAAA==.',
Du='Durnik:BAABNQAECn82AAMWAAoKeyFzEQAKAwAWAAoKeyFzEQAKAwAgAAMKPgiSTwBlAAABNQAECgoKRgACAHIYAA==.',
Dw='Dworflundgrn:BAABNQAECn8qAAIhAAoKkAeDGACLAQAhAAoKkAeDGACLAQAAAA==.',
Dy='Dyamí:BAABNQAECn84AAIQAAoKzxRzSAA0AgAQAAoKzxRzSAA0AgAAAA==.',
['Dá']='Dánte:BAAANQAECgYICQAAAA==.',
Eg='Eglosira:BAAANQADCgMIBQAAAA==.',
El='Elbuhero:BAABNQAECn8qAAMJAAgKJwezNgBmAQAJAAgKJwezNgBmAQANAAUK+xX/XQBZAQAAAA==.Eldiablo:BAAANQAECgMIBwAAAA==.Electric:BAABNQAECn8UAAIPAAUKxQjx1QDoAAAPAAUKxQjx1QDoAAAAAA==.Elementstone:BAAANQAECgIIAgAAAA==.Elendish:BAAANQADCgIIAgAAAA==.Eleven:BAABNQAECn84AAIQAAoKogrniACWAQAQAAoKogrniACWAQAAAA==.Eliasevo:BAAANQADCgcICQABNQAECgoKKQAHAFQjAA==.Elrythe:BAABNQAECn9RAAIWAAoKECFzIwCxAgAWAAoKECFzIwCxAgAAAA==.',
Er='Eraleth:BAAANQAECgUICwABNQAECgoKMgAIADkhAA==.',
Et='Etarnus:BAAANQADCggIFQAAAA==.',
Fa='Faben:BAAANQADCgUIBQAAAA==.Faced:BAAANQAECgUICwAAAA==.Fatalii:BAABNQAECn8WAAMiAAgKmxSwXQCTAQAiAAcKxRCwXQCTAQALAAYKahQCTQCNAQAAAA==.',
Fe='Felebash:BAABNQAECn8YAAIDAAYKHwnQxADrAAADAAYKHwnQxADrAAAAAA==.Felfireflux:BAAANQADCgYIDAAAAA==.Fellirane:BAAANQADCgUIBQAAAA==.',
Fi='Fistdaddy:BAAANQADCgYJDwAAAA==.',
Fl='Floofies:BAABNQAECn9BAAIhAAoK+yRXAQCtAwAhAAoK+yRXAQCtAwAAAA==.Floofndoom:BAAANQAECgUIBQABNQAECgoKQQAhAPskAA==.Floofthulu:BAAANQAECgEIAQABNQAECgoKQQAhAPskAA==.Fluffalo:BAABNQAECn9EAAIPAAoKqSMmCAA4AwAPAAoKqSMmCAA4AwABNQAECgoKQQAhAPskAA==.',
Fo='Foxypocket:BAABNQAECn8iAAILAAgKTAoZHgA2AQALAAgKTAoZHgA2AQAAAA==.',
Fr='Franksredhot:BAABNQAECn8fAAIPAAcKlxWeeAAjAQAPAAcKlxWeeAAjAQAAAA==.Fredrickk:BAABNQAECn8WAAIHAAgKmxzuRAAAAgAHAAgKmxzuRAAAAgAAAA==.',
Fu='Furcas:BAAANQAECgIIAgAAAA==.Furrglur:BAAANQAECgIIAgABNQAECgoKQQAhAPskAA==.Furrylight:BAAANQAECgIIAQABNQAECgoKMwAHABojAA==.Furryphase:BAABNQAECn8zAAMHAAoKGiN2DABfAwAHAAoKGiN2DABfAwAPAAMKlQW74gBTAAAAAA==.Fuzzington:BAAANQAECgcICwABNQAECgoKQQAhAPskAA==.Fuzzydunlop:BAAANQAECgIIAgAAAA==.',
Fz='Fzoul:BAAANQAECgMIAwAAAA==.',
Ga='Gaith:BAAANQAECgYIBgAAAA==.Galnier:BAABNQAECn8aAAIEAAoKpBCjfwDOAQAEAAoKpBCjfwDOAQAAAA==.Gandoomi:BAAANQABCgIIAgAAAA==.',
Gh='Ghosted:BAAANQAECgMIBQAAAA==.',
Gl='Glaecia:BAAANQADCgEIAQAAAA==.Glaur:BAABNQAECn8zAAIHAAoK3hcsLQBvAgAHAAoK3hcsLQBvAgAAAA==.',
Go='Goatjira:BAAANQAECgQIBgAAAA==.',
Gr='Greygorypack:BAEANQADCgUIBQAAAA==.Grimgor:BAAANQAECgQIBAABNQAECggIHgAjAFUbAA==.Gripisrdy:BAABNQAECn8wAAQZAAoKmBgyOgA6AgAZAAcKxR4yOgA6AgAjAAcK2hjWSgCPAQAOAAQK8gulqACAAAAAAA==.Grippindeez:BAABNQAECn8yAAMOAAkKUxZTLwCSAQAOAAUKnhxTLwCSAQAjAAkK1wyFSQByAQAAAA==.',
Gu='Gunslingr:BAABNQAECn88AAMkAAoKXSEuAwAIAwAkAAoKECAuAwAIAwAiAAkKhhipIQCEAgAAAA==.',
Gw='Gweetow:BAAANQAECgEIAQAAAA==.',
Gy='Gymsharklyfe:BAAANQAECggIBgAAAA==.',
Ha='Habanero:BAAANQAECggICAAAAA==.Hairyjolene:BAAANQADCggIEgAAAA==.Handsome:BAABNQAECn83AAMgAAoKqx0zCwCIAgAgAAoK/BwzCwCIAgAWAAcKFBfMxwByAQABNQAFFAUIDgAGAAARAA==.',
He='Headpats:BAACNQAFFH8LAAITAAUKgxRKDQB0AQATAAUKgxRKDQB0AQA1AAQKfx8AAhMACgpsH0QYAPUCABMACgpsH0QYAPUCAAE1AAUUCQkbABsAyhgA.Hearthisrdy:BAAANQAECgYIBgAAAA==.Hel:BAAANQADCgUIBQAAAA==.Helgrim:BAAANQADCgUIBQAAAA==.Helmshammer:BAAANQAECgYIBgAAAA==.Hexwhisper:BAAANQAECgQIBAAAAA==.Heycarlos:BAABNQAECn9AAAMjAAkKkCKTBgB5AwAjAAkKkCKTBgB5AwAZAAIKrwfJzQBRAAAAAA==.',
Hi='Hikaripala:BAAANQADCgYIBgABNQAFFAgIGwAHANEXAA==.Hikarishaman:BAACNQAFFH8bAAMHAAgK0ReZCgClAQAHAAYKghWZCgClAQAPAAQKmhuMEgBGAQA1AAQKfzkAAw8ACgrPHF8lAFICAA8ACgrPHF8lAFICAAcACgpNHChPACgCAAAA.Hime:BAABNQAECn8zAAIEAAoKCAj1ugBcAQAEAAoKCAj1ugBcAQAAAA==.',
Ho='Holyblimblam:BAAANQAECgMIBwAAAA==.Honeypieheal:BAAANQAECgMIAwAAAA==.Horabad:BAAANQAECgUIEAAAAA==.Hosemachine:BAACNQAFFH8FAAIZAAMKPQbkCQC8AAAZAAMKPQbkCQC8AAA1AAQKfxkAAhkACApaGQs6ADsCABkACApaGQs6ADsCAAAA.',
Hu='Hulque:BAAANQADCgYIBgAAAA==.Humper:BAAANQADCgEIAQAAAA==.Huntley:BAAANQADCggICAABNQAECgEIAQAKAAAAAA==.',
['Hè']='Hèri:BAAANQAECgQIBAAAAA==.Hèrifire:BAABNQAECn8ZAAMQAAYK6xPw4gDoAAAQAAUKchXw4gDoAAAaAAIKLg7mLQB3AAAAAA==.',
Ic='Icyshadow:BAABNQAECn8nAAMdAAcKDg1mMAAHAQAdAAcKDg1mMAAHAQAGAAQKUxRmowDzAAAAAA==.',
Id='Idouna:BAAANQADCgEIAQAAAA==.',
Ih='Ihalo:BAAANQAECgYIEAAAAA==.',
Il='Illinesh:BAAANQADCgYICgAAAA==.',
Ir='Ironpaw:BAAANQAECgUJDAAAAA==.',
It='Ithildur:BAAANQADCgQIBAAAAA==.',
Ja='Jadde:BAAANQADCgYIBgAAAA==.Jadienne:BAAANQAECgQIDAAAAA==.Jalapeñø:BAAANQAECgIIAQAAAA==.Jameson:BAAANQAECgUIDAAAAA==.Jamiel:BAAANQABCgMIAwAAAA==.Jangewinde:BAAANQAECgUIDwAAAA==.Jasmind:BAABNQAECn8tAAMJAAoK5xEGHAAoAgAJAAoK5xEGHAAoAgANAAIKgQaokgAoAAAAAA==.Jaywu:BAAANQADCggICAAAAA==.',
Je='Jenarra:BAAANQADCgYICgAAAA==.',
Ji='Jiwà:BAABNQAECn86AAMHAAkKARQuVgAPAgAHAAkKARQuVgAPAgAPAAcKnwKexgAFAQAAAA==.',
Jo='Joecool:BAAANQAECgcIBwAAAA==.Joshjb:BAAANQAECgIIAgAAAA==.Joss:BAAANQADCgIIAgAAAA==.',
Ka='Kaguro:BAABNQAECn8/AAMLAAoK1Ba0CgAsAgALAAoKnha0CgAsAgAkAAkK8w5WCgDWAQAAAA==.Kaibab:BAAANQADCgEIAQAAAA==.Kakwaa:BAAANQAECgIJAwAAAA==.Kalix:BAAANQABCgUICAAAAA==.Kaliyah:BAAANQAECgYIDwAAAA==.Kattrin:BAAANQAECgEIAQAAAA==.Kayleebear:BAAANQADCgQIBAAAAA==.Kaythande:BAAANQAECgMIAwABNQAECggIFgAHAJscAA==.',
Ke='Keistav:BAAANQAECgIIAgAAAA==.Kerplaa:BAAANQADCgMIAwAAAA==.Keyadistor:BAABNQAECn8eAAQjAAgKVRvdPgDPAQAjAAgKpBrdPgDPAQAOAAMKCx5fbACdAAAZAAEKAACz5gAuAAAAAA==.',
Kh='Khamûl:BAAANQADCgEIAQAAAA==.Khazabrew:BAABNQAECn8xAAIFAAoKNh3ZBgDXAgAFAAoKNh3ZBgDXAgAAAA==.',
Ki='Kiamara:BAABNQAECn8nAAIXAAgKMQWkrAD7AAAXAAgKMQWkrAD7AAAAAA==.Kinderlin:BAABNQAECn9SAAIEAAoKvhnETgA/AgAEAAoKvhnETgA/AgAAAA==.Kirboom:BAAANQAECgYIBQAAAA==.Kirbun:BAABNQAECn8xAAIQAAkK/xyJZwCvAgAQAAkK/xyJZwCvAgAAAA==.Kizchaos:BAAANQAECgMIBAAAAA==.',
Ko='Komurash:BAABNQAECn84AAMDAAoK8RiGQABBAgADAAoK8RiGQABBAgARAAIKRgM8PABVAAAAAA==.Korstruck:BAAANQAECgUIBQAAAA==.Kotys:BAAANQADCgUIBQAAAA==.',
Kr='Kravvelocity:BAAANQAECggIDQAAAA==.',
Ku='Kungbrew:BAAANQAECgEIAQABNQAECgcIJwAdAA4NAA==.',
La='Lancaban:BAAANQADCggIHQAAAQ==.Lastiri:BAAANQABCgIIAgAAAA==.',
Le='Lethalarrow:BAABNQAECn8nAAIWAAoKoAs+fADDAQAWAAoKoAs+fADDAQAAAA==.Lethalpally:BAAANQADCggIEgAAAA==.Lewismr:BAAANQADCgUIDQABNQAECgoKQwAEAPYVAA==.Lewisr:BAABNQAECn9DAAIEAAoK9hX/XAAaAgAEAAoK9hX/XAAaAgAAAA==.',
Li='Ligahoo:BAAANQADCggIDwAAAA==.Lilysweets:BAAANQADCgcICgAAAA==.',
Lo='Loralynn:BAAANQAECgQIBQABNQAFFAIIBQAEALkDAA==.Lorianne:BAABNQAECn8iAAMPAAoKTgsiXQBwAQAPAAkKVAwiXQBwAQAHAAUKiQlNvACgAAABNQAFFAIIBQAEALkDAA==.Lorryanne:BAACNQAFFH8FAAIEAAIKuQPaKgBqAAAEAAIKuQPaKgBqAAA1AAQKf1MAAxMACgqgGFE7AHcCABMACgqgGFE7AHcCAAQACgrxD3R+ANABAAAA.',
Lu='Lucianas:BAAANQAECggIEwAAAA==.Lunacat:BAAANQAECgQICQABNQADCgYJDwAKAAAAAA==.Luxdaddy:BAABNQAECn8jAAIGAAkKSxuuKgCgAgAGAAkKSxuuKgCgAgABNQADCgYJDwAKAAAAAA==.',
Ly='Lysi:BAABNQAECn8iAAIWAAgK+BQpfQDAAQAWAAgK+BQpfQDAAQAAAA==.',
Ma='Madaea:BAABNQAECn8oAAIfAAoKoRqGEgBUAgAfAAoKoRqGEgBUAgAAAA==.Madameuyen:BAAANQAECgQICwAAAA==.Madlyn:BAAANQAECgQIDwAAAA==.Magepuppy:BAABNQAECn8cAAMQAAgK+hQ/ygDxAQAQAAcKTxU/ygDxAQAaAAEKTxM9QABEAAAAAA==.Makavali:BAABNQAECn85AAMJAAoKDhibEwCRAgAJAAkK6RmbEwCRAgANAAkKTBHYPwApAQAAAA==.Makavalii:BAABNQAECn9TAAMEAAkK9xUzeAA8AgAEAAkK9xUzeAA8AgATAAkKCxM/UAArAgABNQAECgoKOQAJAA4YAA==.Malanimus:BAAANQAECgYICgAAAA==.Malevola:BAAANQAECgEIAQAAAA==.Malholis:BAAANQAECgcIEgAAAA==.Mandorallen:BAAANQAECgQIBAABNQAECgoKRgACAHIYAA==.Matagi:BAABNQAECn87AAIWAAoKGhXvVwBrAgAWAAoKGhXvVwBrAgAAAA==.Mate:BAAANQADCgUICAABNQAECgEIAQAKAAAAAA==.',
Me='Meatloaf:BAAANQADCgQIBAAAAA==.Meeseks:BAABNQAECn83AAIZAAoKQxuZGwAIAgAZAAoKQxuZGwAIAgAAAA==.Megabyte:BAAANQAECgQJBAAAAA==.Melbeast:BAABNQAECn8dAAIWAAgKKhg8dADXAQAWAAgKKhg8dADXAQAAAA==.Melorea:BAAANQAECgIIAgAAAA==.Merdin:BAABNQAECn8iAAIQAAgKow1khgCbAQAQAAgKow1khgCbAQAAAA==.Methmartion:BAABNQAECn8hAAIYAAcKdwmPFgCoAAAYAAcKdwmPFgCoAAAAAA==.',
Mi='Mignon:BAAANQAECgEIAQAAAA==.Milougheh:BAAANQAECggIAgAAAA==.Minós:BAAANQADCgUIBQAAAA==.Mish:BAAANQAECgQIBAAAAA==.Missiah:BAABNQAECn8yAAIBAAoKjAehJwA0AQABAAoKjAehJwA0AQAAAA==.',
Mo='Moirane:BAAANQADCgQIBAAAAA==.Molfise:BAAANQADCgYIBQAAAA==.Monna:BAAANQABCgIIAgAAAA==.Moonfell:BAABNQAECn8uAAIGAAoKaBJSaQCiAQAGAAoKaBJSaQCiAQAAAA==.Moonlilly:BAABNQAECn8mAAIRAAgKTgaEIgDmAAARAAgKTgaEIgDmAAAAAA==.Mopp:BAABNQAECn8UAAMDAAQKYwe0+gB+AAADAAQKwwW0+gB+AAARAAEKKAqTRwAmAAAAAA==.Morganthe:BAAANQADCggIEAAAAA==.Mornîngstar:BAAANQAECgcIEQAAAA==.',
Mu='Mugatoo:BAAANQAECggIBAAAAA==.',
Mx='Mxtemlen:BAAANQAECgQIBAABNQAECggIHAATAHcSAA==.',
My='Mylilhunter:BAABNQAECn8qAAIWAAkKGAu8hwCpAQAWAAkKGAu8hwCpAQAAAA==.Myrtheli:BAAANQADCggICAABNQAECgoKLQAGAA0dAA==.Mysticx:BAAANQAECggICAAAAA==.',
Na='Nachtelf:BAABNQAECn9LAAIWAAoKER0cOQBoAgAWAAoKER0cOQBoAgAAAA==.Nagan:BAAANQAECgYIDAAAAA==.Natadawn:BAAANQADCgYIBgAAAA==.Natalone:BAABNQAECn9IAAIaAAoKLST1AQBhAwAaAAoKLST1AQBhAwAAAA==.Nathel:BAABNQAECn8oAAMaAAgKNAXQIADQAAAaAAgKNAXQIADQAAAQAAcKcgKsAwGuAAAAAA==.',
Ne='Nerisa:BAAANQADCgUIBQAAAA==.',
Ni='Nikjani:BAAANQADCgQIBAAAAA==.Nirra:BAAANQAECgQIBwAAAA==.',
No='Noctis:BAAANQAECgYICwAAAA==.Notoriginal:BAABNQAECn80AAIZAAoKaRExHQD5AQAZAAoKaRExHQD5AQAAAA==.Novatron:BAABNQAECn8nAAQhAAgK1QURIQAZAQAhAAgKMQURIQAZAQAPAAQKbwbQxgB9AAAHAAMK7wCRFwE8AAAAAA==.',
Nu='Nuance:BAAANQAECgIIAgAAAA==.Nuked:BAABNQAECn8UAAIQAAYKuxddAAGNAQAQAAYKuxddAAGNAQAAAA==.',
['Né']='Néith:BAAANQADCgQIBAAAAA==.',
Od='Odor:BAAANQAECgQIBwAAAA==.',
Og='Ograskygazer:BAABNQAECn8lAAIJAAgKDAVAQwD5AAAJAAgKDAVAQwD5AAAAAA==.',
Oi='Oieg:BAAANQABCgUIBAAAAA==.',
Om='Omee:BAABNQAECn8rAAMcAAoKHRDLMQCLAQAcAAkKEw/LMQCLAQAIAAgKrAztKgBAAQAAAA==.Omegaone:BAAANQADCgcIBwAAAA==.',
On='Oneil:BAAANQADCgMJAwAAAA==.Onlyshrimps:BAAANQAECgYIBgAAAA==.',
Op='Ophela:BAAANQAECgEIAQAAAA==.',
Or='Oralena:BAABNQAECn8mAAIWAAgKeAT32AAAAQAWAAgKeAT32AAAAQAAAA==.Orioncheats:BAABNQAECn9DAAMZAAoKtxYGIQDZAQAZAAoKiRYGIQDZAQAOAAgKlhNTNgBtAQAAAA==.',
Ow='Owo:BAAANQAECgEIAQAAAA==.',
Ox='Oxygën:BAABNQAECn8wAAIQAAoKpBQcVwAOAgAQAAoKpBQcVwAOAgAAAA==.',
Pa='Palomita:BAAANQADCgIIAgAAAA==.',
Pe='Ped:BAAANQAECgEIAQABNQAECgoKLQAGAA0dAA==.Pedaramun:BAAANQAECgcIBwABNQAECgoKLQAGAA0dAA==.Pedarias:BAABNQAECn8tAAMGAAoKDR2CFwAbAwAGAAoKDR2CFwAbAwAdAAEKAABTlgANAAAAAA==.Peon:BAAANQAECgYIDwAAAA==.Perstephanie:BAAANQADCgQIBAAAAA==.',
Ph='Pharune:BAABNQAECn82AAIlAAoKwBD9GwCjAQAlAAoKwBD9GwCjAQAAAA==.Phredrick:BAAANQAECgUIEAAAAA==.',
Pi='Piemanninty:BAAANQAECgIJBQAAAA==.',
Pl='Plandemic:BAAANQAECgEIAQAAAA==.',
Po='Pockithealz:BAAANQADCgQIBAABNQAECggIFgAiAJsUAA==.Pointnshoot:BAAANQADCgQIBwABNQAECggIKgAKAAAAAA==.Pokerface:BAAANQAECgYIDAAAAA==.Ponky:BAAANQAECgIIAgABNQAECgoKNAATAHgbAA==.Poongwoon:BAAANQADCgMIAwAAAA==.Pounces:BAACNQAFFH8GAAIJAAQKBxKhCgApAQAJAAQKBxKhCgApAQA1AAQKfxYAAgkACQplHRIfAAYCAAkACQplHRIfAAYCAAE1AAUUCQkbABsAyhgA.',
Pr='Precious:BAABNQAECn8wAAIGAAoKpiUaAQBCBAAGAAoKpiUaAQBCBAABNQAFFAkJMAAGANgcAA==.',
Pu='Puppet:BAAANQAECgcIEAABNQAFFAkJMAAGANgcAA==.',
Py='Pymura:BAAANQADCgQIBAAAAA==.',
['Pí']='Píongá:BAAANQADCgEIAQAAAA==.',
Qe='Qee:BAAANQAECgEIAQABNQAECgoKJQAIAEAWAA==.',
Qu='Quattro:BAABNQAECn8lAAImAAkKkg4DDQCAAQAmAAkKkg4DDQCAAQAAAA==.',
Ra='Racecar:BAAANQAECgUIDQAAAA==.Raezil:BAAANQAECgQICQABNQAECgoKIQAXAKsSAA==.Raivyn:BAABNQAECn9GAAICAAoKchjnEwAoAgACAAoKchjnEwAoAgAAAA==.Rathmora:BAAANQADCggIJAAAAA==.Raylaira:BAAANQAECgUIDwAAAA==.Raziel:BAAANQAECgYIBgAAAA==.',
Re='Redbeard:BAAANQAECgUIBgAAAA==.Remnants:BAAANQADCggIEwAAAA==.Renard:BAABNQAECn9LAAMJAAoKAiRjAwCSAwAJAAoKAiRjAwCSAwANAAQK2xHyXACuAAAAAA==.Reposado:BAABNQAECn8lAAIjAAkKpBogHgBZAgAjAAkKpBogHgBZAgAAAA==.Revelare:BAABNQAECn8wAAIHAAoKJhUNSgDrAQAHAAoKJhUNSgDrAQAAAA==.Rexbie:BAAANQAECgcICwAAAA==.',
Rh='Rhylee:BAAANQAECgUIDgAAAA==.',
Ri='Rianne:BAAANQADCgUIBQAAAA==.Riptidepod:BAABNQAECn84AAMHAAoK9R+FEwAcAwAHAAoK9R+FEwAcAwAPAAEKAACrRgErAAAAAA==.',
Rm='Rmplstiltskn:BAAANQADCgUICQAAAA==.',
Ro='Robberttrest:BAABNQAECn8cAAIWAAUKWwl87QAmAQAWAAUKWwl87QAmAQAAAA==.Rockyhunter:BAAANQAECggIEgABNQAECgoKQwAOAKoeAA==.Rockyhunterr:BAABNQAECn9DAAIOAAoKqh7zEQAdAwAOAAoKqh7zEQAdAwAAAA==.Rockymage:BAAANQADCgYIBgAAAA==.Rockyrogue:BAAANQADCggICAABNQAECgoKQwAOAKoeAA==.Rockywarlock:BAAANQAECgEIAQABNQAECgoKQwAOAKoeAA==.Rockywarrior:BAAANQADCgYICgABNQAECgoKQwAOAKoeAA==.Ronaeminnda:BAAANQABCgQIBAAAAA==.Rooth:BAABNQAECn8ZAAImAAgKlQu6EAAvAQAmAAgKlQu6EAAvAQAAAA==.Roryn:BAABNQAECn9TAAIEAAoK3iWuCQBQAwAEAAoK3iWuCQBQAwAAAA==.',
Ru='Rubï:BAABNQAECn8qAAISAAoKKCSiAQAwAwASAAoKKCSiAQAwAwAAAA==.Ruggburn:BAAANQAECgYICQABNQAECgoKMgAaAE0bAA==.Rugiaas:BAACNQAFFH8rAAITAAgKMSEsAgD1AgATAAgKMSEsAgD1AgA1AAQKf0MAAxMACgofJc4EAKoDABMACgofJc4EAKoDAAQABArUGM35ACsBAAAA.Rugian:BAAANQAECgQIBQABNQAFFAgIKwATADEhAA==.Rugis:BAAANQAECgMIBQABNQAFFAgIKwATADEhAA==.',
Ry='Ryuka:BAAANQAECgcIEQAAAA==.',
['Râ']='Râezil:BAAANQADCgIIAgABNQAECgoKIQAXAKsSAA==.',
Sa='Samyria:BAAANQAECgYICQAAAA==.Sapphiriana:BAAANQADCgIIAgABNQAECggIGQAmAJULAA==.Saprates:BAAANQADCgMIAwAAAA==.Satyaru:BAABNQAECn80AAQFAAoKEBHsEQDHAQAFAAgKag/sEQDHAQAfAAkKKQ3UGAB0AQACAAQKsg6yQACtAAAAAA==.',
Se='Sedona:BAABNQAECn8ZAAInAAgKCwO3GAC+AAAnAAgKCwO3GAC+AAAAAA==.Selarra:BAABNQAECn8pAAIGAAoKEw9cfACkAQAGAAoKEw9cfACkAQAAAA==.Seric:BAABNQAECn80AAMRAAoKtw0pGwCHAQARAAkKtg4pGwCHAQADAAkK4gfnlgBSAQAAAA==.Sethuriel:BAAANQAECggIEAAAAA==.',
Sh='Shadowdancèr:BAAANQADCgEJAQAAAA==.Shadowlocke:BAAANQADCgYICAAAAA==.Shalzith:BAAANQAECgEIAQAAAA==.Shenandoah:BAAANQADCgYIBgAAAA==.Shockadelica:BAAANQADCgYIBgAAAA==.',
Si='Sitheretta:BAAANQAECgUICQAAAA==.',
Sk='Skoto:BAAANQAECggICwAAAA==.',
Sm='Smartfood:BAABNQAECn8eAAIDAAkK0wxloAA9AQADAAkK0wxloAA9AQAAAA==.Smoochybooty:BAAANQAECgMIBAAAAA==.',
Sn='Snuggy:BAAANQAECgIIAgAAAA==.',
So='Solnar:BAABNQAECn8cAAMTAAgKdxJZYAD3AQATAAgKdxJZYAD3AQAEAAQK8QyVRwGuAAAAAA==.Soupspoon:BAAANQAECggIBAAAAA==.',
Sp='Specter:BAAANQAECggICAAAAA==.Splashdaddy:BAACNQAFFH8PAAIHAAgKFw/ICQCzAQAHAAgKFw/ICQCzAQA1AAQKf0UAAgcACgrxIqYaAAUDAAcACgrxIqYaAAUDAAE1AAMKBgkPAAoAAAAA.Spoiled:BAAANQADCggICAABNQAFFAkJMAAGANgcAA==.',
Sr='Srìracha:BAAANQAECggIDwAAAA==.',
St='Staks:BAAANQADCgcIFAAAAA==.Starii:BAABNQAECn8nAAMHAAgKxwXmjwAHAQAHAAgKxwXmjwAHAQAPAAMKJwMK8wA+AAAAAA==.Stormieskye:BAABNQAECn9BAAIPAAoKJhbSMgALAgAPAAoKJhbSMgALAgAAAA==.Striga:BAAANQADCgcIBwAAAA==.',
Su='Summonme:BAAANQAECgIIAgAAAA==.Suzume:BAAANQAECgQIBAABNQAFFAgIGwAHANEXAA==.',
Sw='Sweetshot:BAAANQADCgEIAQAAAA==.',
Sy='Sylvancura:BAAANQADCgQIBAAAAA==.Synestra:BAABNQAECn8cAAIlAAYKjRpmIgCEAQAlAAYKjRpmIgCEAQAAAA==.',
Ta='Taea:BAABNQAECn8cAAMHAAgKuyF1MQBYAgAHAAcKEyF1MQBYAgAPAAEKAACMKAEAAAAAAA==.Taeus:BAACNQAFFH8GAAMQAAIKIxGSSgBJAAAQAAIKIxGSSgBJAAAaAAEKAAAzGQAAAAA1AAQKf0AABBoACgpWIeIGAIsCABoACgrFIOIGAIsCABAACQqWG9/TAN8BACgAAQo/D3MMAD8AAAAA.Taintedkoma:BAAANQAECgUIBwABNQAECgcIIQAYAHcJAA==.Talagark:BAAANQADCgYIBgAAAA==.Talanat:BAAANQADCgIIAgAAAA==.Taurenator:BAABNQAECn8eAAIRAAoKQyCkBgD5AgARAAoKQyCkBgD5AgAAAA==.',
Te='Tearinass:BAAANQAECgcIBwAAAA==.Teheez:BAAANQADCgIIAgAAAA==.Tenthrol:BAAANQABCgMIBQAAAA==.Teranidas:BAAANQAECgUICgABNQAECgUIDwAKAAAAAA==.Teratrendera:BAABNQAECn8oAAIpAAgKPyA5BwDpAgApAAgKPyA5BwDpAgAAAA==.Teron:BAAANQAECgMJBAAAAA==.Tesx:BAAANQAECgIIAQAAAA==.',
Th='Thavis:BAABNQAECn8+AAMYAAoKWBWSDgDeAAAXAAoKDBI6VQDUAQAYAAUKqRaSDgDeAAAAAA==.Thdoris:BAAANQADCgQIBAAAAA==.Therele:BAAANQAECgQIBAAAAA==.Thetimelord:BAAANQAECgMIBQAAAA==.Thewarrior:BAABNQAECn8dAAMSAAoK9hgZDgCfAQADAAoKdRS3XwDgAQASAAcK5hsZDgCfAQAAAA==.Thrask:BAAANQADCgQIBAAAAA==.',
Ti='Ticktac:BAAANQAECgcIBgAAAA==.Tik:BAAANQADCggIDgAAAA==.Tilted:BAABNQAECn8qAAMEAAoKQBxiMACgAgAEAAoKQBxiMACgAgABAAEKAAAvfgAAAAAAAA==.Tiltêd:BAAANQAECgYIDAAAAA==.Tinkr:BAABNQAECn89AAIOAAoK4xpXFgBWAgAOAAoK4xpXFgBWAgAAAA==.',
To='Tobi:BAAANQADCgYIBgAAAA==.Toewzix:BAAANQAECgQIBAAAAA==.Tom:BAAANQAECgUICAABNQAECgoKIQAXAKsSAA==.Torrey:BAABNQAECn8rAAMUAAoKbgsmEQA2AQAIAAoK+QmuNACdAQAUAAoKrAkmEQA2AQAAAA==.Totemsareus:BAABNQAECn8pAAMHAAoKVCMgCACAAwAHAAoKVCMgCACAAwAPAAIKigdZFQFjAAAAAA==.Toxx:BAAANQAECgYIBgABNQAECgoKKwAcAB0QAA==.',
Tr='Tradd:BAACNQAFFH8OAAIGAAUKABFMGAA5AQAGAAUKABFMGAA5AQA1AAQKf0wABAYACgpVIyMOAFMDAAYACgpVIyMOAFMDAB0ACgoRFGkTACYCABsABwrDDr4MAGwBAAAA.Trallor:BAABNQAECn8pAAMDAAoKhw0VvgCBAQADAAkKlA0VvgCBAQARAAQKGg11LQCZAAAAAA==.Trhall:BAAANQAECgQIDwAAAA==.Tristyana:BAABNQAECn9GAAIWAAoKqBKxXgAKAgAWAAoKqBKxXgAKAgAAAA==.',
Ts='Tsiddahn:BAABNQAECn84AAIGAAoKhxqmKADHAgAGAAoKhxqmKADHAgAAAA==.Tsunâde:BAABNQAECn9CAAMCAAoKCyWqAwA+AwACAAoKCyWqAwA+AwAfAAcKExIpIwDyAAAAAA==.',
Tw='Twanu:BAAANQAECgUICQAAAA==.',
Ty='Tylurien:BAABNQAECn82AAITAAoK9CXWBQC/AwATAAoK9CXWBQC/AwAAAA==.Tyrael:BAABNQAECn82AAMBAAoKQw/9HQCAAQABAAoKQw/9HQCAAQATAAEKYwJrEAEVAAABNQADCgMIBgAKAAAAAA==.',
Uk='Ukon:BAAANQADCgYIBgAAAA==.',
Ul='Ulangi:BAAANQAECgEIAQAAAA==.',
Un='Un:BAAANQADCgcIAQAAAA==.',
Ur='Urbanprey:BAABNQAECn8rAAIYAAkKrgtGCgAiAQAYAAkKrgtGCgAiAQAAAA==.',
Va='Valenhi:BAAANQAECgIIAQAAAA==.Valkoinen:BAAANQADCgMIBgAAAA==.Valora:BAABNQAECn9FAAIGAAoKjh6AHwDiAgAGAAoKjh6AHwDiAgAAAA==.Valoria:BAAANQAECgIIAwAAAA==.Vanille:BAABNQAECn8lAAMJAAgKVwQKSwDRAAAJAAgKVwQKSwDRAAAlAAQKtgjWUQB4AAAAAA==.Vargen:BAAANQAECgcIDAAAAA==.Varonika:BAAANQAECgUIBwAAAA==.Vayla:BAABNQAECn8/AAIRAAkKpB3vBwBtAgARAAkKpB3vBwBtAgAAAA==.',
Vb='Vbv:BAAANQAECgcICgAAAA==.',
Ve='Veal:BAAANQADCgYIBgABNQAECgoKKQAGABMPAA==.Vedik:BAAANQAECgYIEwAAAA==.Vegasduc:BAAANQADCgQIBAAAAA==.Vegasducks:BAABNQAECn80AAIQAAoKgwi4gACoAQAQAAoKgwi4gACoAQAAAA==.Velara:BAAANQADCgYIDAAAAA==.Veld:BAABNQAECn8VAAIIAAgKYg+rMwClAQAIAAgKYg+rMwClAQAAAA==.Velithara:BAAANQADCgYJBgAAAA==.Velura:BAAANQAECggICAAAAA==.Veralyn:BAAANQADCgUICgAAAA==.',
Vi='Violet:BAABNQAECn8mAAIEAAYKCAZUDAEKAQAEAAYKCAZUDAEKAQAAAA==.',
Vy='Vyla:BAAANQABCgcIDAAAAA==.',
['Vè']='Vèngeance:BAAANQAECgUIBQAAAA==.',
Wa='Wardancer:BAAANQAECgUIBQAAAA==.Warfise:BAABNQAECn8bAAIRAAgKDRcpEgCWAQARAAgKDRcpEgCWAQAAAA==.Warspriest:BAABNQAECn8wAAIdAAoK6Rm4DwBdAgAdAAoK6Rm4DwBdAgAAAA==.Warwizard:BAABNQAECn9bAAITAAoKlyUmAgATBAATAAoKlyUmAgATBAAAAA==.',
Wd='Wdemperor:BAABNQAECn8pAAQRAAoKlwbiIAD1AAARAAkKMgTiIAD1AAASAAYKZQd0IQCfAAADAAMKzgPiRgFDAAAAAA==.',
We='Webin:BAAANQAECgEIAQAAAA==.',
Wh='Whispaknight:BAAANQAECgEIAQABNQAECgEIAQAKAAAAAA==.Whisperwiind:BAAANQADCgcIBwABNQAECgEIAQAKAAAAAA==.Whisperz:BAAANQADCgYIBgABNQAECgEIAQAKAAAAAA==.',
Wi='Wickedywaque:BAAANQADCgUIBQAAAA==.Wickerchickn:BAAANQAECgQJBwAAAA==.Wiisper:BAAANQAECgEIAQAAAA==.Wilshammy:BAAANQAECgIIAwAAAA==.Winterhunter:BAAANQADCgEIAQAAAA==.',
Wo='Wonkyponky:BAABNQAECn80AAITAAoKeBvdJwDJAgATAAoKeBvdJwDJAgAAAA==.',
Wr='Wrathbarrage:BAABNQAECn8XAAIWAAgKvBLAjADxAQAWAAgKvBLAjADxAQABNQAECgoKSAAlAPcVAA==.Wrathchoi:BAAANQAECgYIBgAAAA==.Wrathstorm:BAABNQAECn9IAAMlAAoK9xUIGADLAQAlAAoK9xUIGADLAQAVAAEKKQrpTAAvAAAAAA==.',
Ya='Yazahk:BAAANQADCggIFgABNQAECgYIBgAKAAAAAA==.Yazjani:BAAANQADCgIIAgAAAA==.Yazoth:BAAANQADCgEIAQAAAA==.Yazoura:BAAANQADCggIDwAAAA==.Yazwynn:BAAANQADCgcIDgAAAA==.',
Ye='Yezgraine:BAACNQAFFH8cAAIOAAgK+SHKAQCdAgAOAAgK+SHKAQCdAgA1AAQKfzkAAw4ACgqHJVwCAGADAA4ACgqHJVwCAGADACMABAr3GqmFAJ8AAAAA.',
Yo='Yookock:BAAANQADCggIDgAAAA==.',
Yz='Yzaak:BAAANQAECgYIBgAAAA==.',
Za='Zagyg:BAAANQADCgQIBAAAAA==.',
Ze='Zeddiccus:BAABNQAECn8jAAMaAAoK9ByQGAAdAQAQAAcKpRybkgCBAQAaAAQKohqQGAAdAQAAAA==.Zeva:BAABNQAECn8bAAIdAAgKdAaSMwDzAAAdAAgKdAaSMwDzAAAAAA==.',
Zo='Zonzmik:BAAANQADCggICgAAAA==.Zorrokiller:BAAANQADCgQIBAAAAA==.Zorvoth:BAAANQADCgQIBAABNQAECgUIDwAKAAAAAA==.',
Zu='Zurazaee:BAABNQAECn8mAAIGAAgKfyDnHwDgAgAGAAgKfyDnHwDgAgAAAA==.',
['Él']='Élle:BAAANQADCgcICAAAAA==.',
['Ér']='Éric:BAABNQAECn9GAAIlAAoKwgotKQBAAQAlAAoKwgotKQBAAQAAAA==.',
['Ïr']='Ïridescent:BAAANQAECgIIAgAAAA==.',
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
