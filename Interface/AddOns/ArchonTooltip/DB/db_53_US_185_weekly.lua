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

local lookup = {'Warlock-Destruction','Warrior-Arms','Paladin-Retribution','DeathKnight-Frost','Unknown-Unknown','DeathKnight-Blood','Shaman-Restoration','Paladin-Holy','Monk-Brewmaster','Warlock-Demonology','Priest-Holy','Priest-Shadow','Mage-Arcane','Shaman-Elemental','Monk-Windwalker','Mage-Frost','Paladin-Protection','Warrior-Fury','Hunter-BeastMastery','Druid-Feral','Druid-Restoration','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Unholy','Druid-Balance','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Outlaw',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abeblinkin:BAAANQAECgYIEQAAAA==.Aborlight:BAAANQAECgMIAwAAAA==.',
Ad='Adit:BAAANQADCggIDAAAAA==.',
Af='Afrit:BAAANQAECgMIBwAAAA==.',
Ai='Aiwass:BAABNQAECoEYAAIBAAcKbwVDKQAkAQABAAcKbwVDKQAkAQAAAA==.',
Al='Alieah:BAAANQAECgYIBgAAAA==.Alpharius:BAAANQAECgUICwAAAA==.',
Am='Amacoozy:BAABNQAECoEkAAICAAkKdRZdRQChAgACAAkKdRZdRQChAgAAAA==.Amathricus:BAABNQAECoEaAAIDAAYKMwkZ3QAnAQADAAYKMwkZ3QAnAQAAAA==.',
Ar='Arms:BAACNQAFFIEOAAIEAAYKrxKTAgDaAQAEAAYKrxKTAgDaAQA1AAQKgRkAAgQACQpxIS0YAKMCAAQACQpxIS0YAKMCAAAA.Artima:BAAANQADCgMIAwAAAA==.',
As='Ashh:BAAANQADCgcIDQAAAA==.Ashuk:BAAANQADCgEIAQAAAA==.',
At='Athena:BAAANQAECgUIDwAAAA==.',
Au='Augtism:BAEANQADCgIIAgABNQAECgQIBQAFAAAAAA==.Auralei:BAAANQADCgUIBQABNQAECgQICgAFAAAAAA==.',
Az='Azelia:BAAANQAECgIJAgABNQAECgcICAAFAAAAAA==.Azzy:BAAANQAECgcICAAAAA==.',
Be='Bellestri:BAAANQAECgUICAAAAA==.',
Bi='Bigb:BAAANQAECgUIDwAAAA==.Bigface:BAAANQAECgYIBgAAAA==.Bigrod:BAABNQAECoEZAAIGAAkKuQ+9QADcAQAGAAkKuQ+9QADcAQAAAA==.Binks:BAAANQAECgEIAQAAAA==.',
Bl='Black:BAAANQAECgYIEQAAAA==.Blasfoomous:BAACNQAFFIEIAAIGAAQKJA9PEgAAAQAGAAQKJA9PEgAAAQA1AAQKgSgAAgYACQoWHVkaAMQCAAYACQoWHVkaAMQCAAAA.Blu:BAACNQAFFIELAAIHAAUK4h24BwC5AQAHAAUK4h24BwC5AQA1AAQKgR4AAgcACQo/IpILAE8DAAcACQo/IpILAE8DAAAA.',
Bo='Bochese:BAAANQAECgMIAwABNQAECggIHAAIAJkdAA==.',
Br='Brochese:BAAANQADCgQIAQABNQAECggIHAAIAJkdAA==.',
Bu='Bubblewrap:BAAANQADCggICAABNQAFFAQICAAJAI0RAA==.',
['Bá']='Básicc:BAAANQADCgUIBQAAAA==.',
Ca='Canadianguy:BAAANQADCgYIBgABNQAECgYIEQAFAAAAAA==.Cappen:BAAANQADCgIIAgAAAA==.',
Ce='Cedrik:BAAANQAECgMIAwAAAA==.Ceres:BAAANQADCgMIAwAAAA==.',
Cl='Classcarry:BAAANQAECgUIEAABNQAECgkJJgAEAFsiAA==.Claybigsby:BAACNQAFFIEIAAMBAAQKQBWnCQCqAAABAAIKIRanCQCqAAAKAAIKYBSYJwCcAAA1AAQKgSYAAwoACQq9GxBbACQCAAoABwqeGhBbACQCAAEABAoXFfosAA8BAAAA.Clif:BAAANQAECgEIAQAAAA==.',
Co='Constantina:BAABNQAECoEqAAILAAkKZhXsQQA+AgALAAkKZhXsQQA+AgAAAA==.Corven:BAAANQAECgQIBAAAAA==.',
Cr='Crunchycars:BAAANQAECgMIAwAAAA==.',
Cy='Cyleste:BAABNQAECoEaAAMMAAgK3AxRKAC/AQAMAAgK3AxRKAC/AQALAAQK0Q2VrQDUAAAAAA==.',
De='Derpy:BAAANQAECgUIBQAAAA==.',
Dh='Dheevix:BAAANQADCgcIBwABNQAECgkJIQANALMZAA==.',
Di='Divinelady:BAAANQADCggICAAAAA==.',
Dj='Djheals:BAAANQAECgMIAwABNQAECgYIBgAFAAAAAA==.Djmuphasa:BAAANQAECgYIBgAAAA==.Djthrasher:BAAANQAECgQIBgABNQAECgYIBgAFAAAAAA==.',
Dr='Drachese:BAAANQAECgUIBwABNQAECggIHAAIAJkdAA==.Druchese:BAAANQAECgYIEAABNQAECggIHAAIAJkdAA==.',
Ea='Eagleeye:BAAANQAECgYIEQAAAA==.',
Em='Emsley:BAABNQAECoE5AAIOAAkKMQ8ITQAWAgAOAAkKMQ8ITQAWAgAAAA==.',
Er='Eralina:BAAANQADCgUIBQAAAA==.Erebos:BAAANQADCgEIAQAAAA==.Erised:BAAANQADCgYJCgAAAA==.',
Ev='Ev:BAABNQAECoEWAAMJAAgK4xwODAAlAgAJAAUKYSYODAAlAgAPAAcKqg5hMQBVAQAAAA==.',
Ex='Exo:BAABNQAECoEeAAMNAAkKlB7tYACqAgANAAkKuhztYACqAgAQAAIK0CEIKgCBAAAAAA==.',
Fa='Falorin:BAAANQADCgcIDgAAAA==.',
Fl='Floudwing:BAAANQABCgYIDAAAAA==.',
Fn='Fnwarriors:BAAANQADCgcICAAAAA==.',
Fo='Focalors:BAAANQAECgUICQABNQAFFAQICAANABkLAA==.Foobear:BAAANQAECgYIDAABNQAFFAQICAAGACQPAA==.',
Fr='Franchescold:BAAANQAECgYICgAAAA==.',
Fu='Furlock:BAAANQAECgYIEQAAAA==.',
Ga='Gabriel:BAABNQAECoFGAAMRAAkKvhQJFwAbAgARAAkKvhQJFwAbAgADAAEKyAMvkwElAAAAAA==.Galicia:BAAANQAECgQIBAAAAA==.Gantaris:BAAANQAECgQIBgAAAA==.Gaymer:BAAANQAECgQIBwABNQAECgUIDwAFAAAAAA==.',
Gi='Gir:BAAANQAECgQIBgAAAA==.',
Go='Gochese:BAABNQAECoEcAAMIAAgKmR3SIwDEAgAIAAgKmR3SIwDEAgADAAEK8wRPkAEmAAAAAA==.Gorgeous:BAAANQAECgYIBgABNQAECgYIBgAFAAAAAA==.Gothel:BAAANQADCgcIDgAAAA==.',
Gr='Grace:BAAANQAECgcICwAAAA==.Greenseer:BAAANQAECgYICwAAAA==.',
Gt='Gtoffmydruid:BAAANQADCgEIAQABNQADCgUIBQAFAAAAAA==.Gtoffmyface:BAAANQADCgUIBQAAAA==.',
Gw='Gwaralmighty:BAABNQAECoEnAAISAAgKAx72BAC0AgASAAgKAx72BAC0AgAAAA==.',
Gy='Gypo:BAAANQADCggIFAAAAA==.',
Ha='Haagen:BAABNQAECoEaAAITAAcK4A91hQDRAQATAAcK4A91hQDRAQAAAA==.Hamsup:BAABNQAECoEkAAICAAgKHhdJbgAnAgACAAgKHhdJbgAnAgAAAA==.Hatch:BAAANQADCgcICAABNQAECggIFgAJAOMcAA==.',
['Hô']='Hôldem:BAEANQAECgYIEwAAAA==.',
Ic='Icylady:BAAANQADCgYIDAAAAA==.',
If='Ifrita:BAABNQAECoEeAAINAAcKQhINwgDcAQANAAcKQhINwgDcAQAAAA==.Ifrite:BAAANQADCgQJBAAAAA==.',
Ik='Ikur:BAAANQAECgYICwABNQAECgkJKAAIAMsaAA==.',
Im='Imbasoul:BAAANQADCgMIAwAAAA==.Imyerchese:BAAANQADCgYIBgABNQAECggIHAAIAJkdAA==.',
Jo='Jontalo:BAAANQADCgcIDgAAAA==.Jormi:BAABNQAECoEcAAICAAcKGSAjSwCOAgACAAcKGSAjSwCOAgAAAA==.',
Ju='Justthetipp:BAAANQABCgQIBgABNQAECgYIDAAFAAAAAA==.',
Ka='Kalthael:BAAANQABCgYICQAAAA==.Karthus:BAAANQADCgEIAQAAAA==.Kasaurus:BAAANQADCgMIAQAAAA==.Kasura:BAABNQAECoElAAMUAAgKvh4EBwDJAgAUAAgKvh4EBwDJAgAVAAMK1BXsRwDBAAAAAA==.',
Kh='Kharahealer:BAAANQAECgMIAwAAAA==.',
Ki='Kindred:BAAANQADCgYICQAAAA==.Kirihax:BAABNQAECoEYAAIMAAgKDB5eGQBiAgAMAAgKDB5eGQBiAgABNQAFFAYIEwAPAE4gAA==.',
Ko='Kochese:BAAANQAECgUIBQABNQAECggIHAAIAJkdAA==.',
Ku='Kutar:BAAANQADCgcIFAAAAA==.',
Li='Limedro:BAAANQADCgcIFAAAAA==.Limpdaddy:BAAANQAECgIIAgAAAA==.',
Lo='Lochese:BAAANQADCgYIBgABNQAECggIHAAIAJkdAA==.Lockme:BAAANQAECgcICgABNQAFFAYIFQANAJgdAA==.Lotei:BAAANQADCgMIAwAAAA==.',
Ma='Magorrak:BAAANQAECgIIAgAAAA==.Mal:BAACNQAFFIEMAAIWAAUKJyPMAgAJAgAWAAUKJyPMAgAJAgA1AAQKgRcAAxcACQpAH1UaAPMBABcABwofHFUaAPMBABYAAwoxJqFKAE8BAAAA.Mary:BAACNQAFFIEOAAIWAAUK3h8aAwD2AQAWAAUK3h8aAwD2AQA1AAQKgSIAAhYACQqOIxcGAFwDABYACQqOIxcGAFwDAAAA.',
Mc='Mcshammer:BAAANQAECgQIDAAAAA==.',
Me='Mero:BAAANQAECgQICAAAAA==.Metal:BAAANQAECgQIEQAAAA==.',
Mi='Miorine:BAACNQAFFIEIAAMNAAQKGQvRIwAoAQANAAQKGQvRIwAoAQAQAAEKzwJOEgA6AAA1AAQKgSYAAg0ACQoRIh0tACkDAA0ACQoRIh0tACkDAAAA.Mistbehavin:BAACNQAFFIEIAAIJAAQKjRGPBAAYAQAJAAQKjRGPBAAYAQA1AAQKgTQAAgkACQoeHYQFAOwCAAkACQoeHYQFAOwCAAAA.',
Mo='Moginndar:BAABNQAECoEkAAMRAAcKJxHkLwA1AQARAAcK8g/kLwA1AQADAAUKpRAH3wAjAQAAAA==.Moochese:BAAANQAECgQIDQABNQAECggIHAAIAJkdAA==.',
Mu='Muggsy:BAAANQAECgEJAQAAAA==.Munidar:BAAANQAECgYIEQAAAA==.',
My='Mytz:BAAANQAECgMIAwAAAA==.',
['Mï']='Mïnna:BAABNQAECoEbAAMYAAkKMiKaDQA3AwAYAAkKKSKaDQA3AwAEAAIKmhL/fABuAAAAAA==.',
Ne='Nemisai:BAAANQADCgcIEgAAAA==.',
On='Onebuttonwin:BAAANQADCgMIAwAAAA==.',
Op='Optimizer:BAAANQAECgQIBwAAAA==.',
Or='Orionbtch:BAAANQADCgYIDgAAAA==.',
Ov='Overheat:BAAANQAECgYIDgAAAA==.',
Po='Poppy:BAAANQAECgMIBgAAAA==.Portinglol:BAAANQAECgEIAQABNQAECgkJJgAEAFsiAA==.',
Pr='Problem:BAAANQADCgIIAgAAAA==.',
Pu='Pugne:BAAANQAECgcIEgAAAA==.',
Ra='Ratidari:BAAANQAECgUIEAAAAA==.Ratshifter:BAAANQAECgYIBwABNQAECgUIEAAFAAAAAA==.Ravenstorm:BAAANQADCgEIAQAAAA==.',
Re='Red:BAAANQADCgQIBAABNQAECgkJGwAZAKIVAA==.Remmîngton:BAAANQAECgUJCwAAAA==.Retbulls:BAABNQAECoEdAAIDAAgKuiABNQDYAgADAAgKuiABNQDYAgAAAA==.',
Rh='Rhynehardt:BAAANQADCgYIBgAAAA==.',
Ri='Riptidedro:BAABNQAECoEcAAIHAAkKqBuYHwDOAgAHAAkKqBuYHwDOAgAAAA==.',
Ru='Runslikedeer:BAAANQAECgQICAAAAA==.Runé:BAAANQAECgEIAQABNQAECgQICQAFAAAAAA==.',
Sa='Satorugojo:BAAANQABCgIIAgAAAA==.',
Se='Sean:BAACNQAFFIEIAAMNAAQKzQnILgDhAAANAAMKygvILgDhAAAQAAEK1wP2DwBHAAA1AAQKgS4AAw0ACQqKHpI9AP0CAA0ACQqKHpI9AP0CABAAAQrJFm9BADIAAAAA.Serah:BAACNQAFFIEGAAIaAAMKmwfKDwDHAAAaAAMKmwfKDwDHAAA1AAQKgSMAAxoACQrjD14zAN8BABoACApBEV4zAN8BABsACAqBBxcyAI0BAAAA.Sevia:BAAANQADCggIEwAAAA==.',
Sh='Shimakaze:BAAANQAECggIDQABNQAFFAQICAANABkLAA==.Shizaam:BAACNQAFFIEIAAMHAAQKkAuWEwDkAAAHAAMKsQyWEwDkAAAOAAMKOwlmFwDZAAA1AAQKgSkAAw4ACQrcIGAZABoDAA4ACQrcIGAZABoDAAcACArmHCgnAKcCAAAA.Shlommy:BAAANQAECgYIEAAAAA==.',
Si='Silvermage:BAACNQAFFIEVAAINAAYKmB1uBgA2AgANAAYKmB1uBgA2AgA1AAQKgSIAAg0ACQoRJRgjAEcDAA0ACQoRJRgjAEcDAAAA.Sinfxl:BAAANQAECgQICQAAAA==.Sippinsizurp:BAABNQAECoEhAAINAAkKWR89OQAIAwANAAkKWR89OQAIAwAAAA==.',
Sk='Skullmages:BAAANQAECggIEgAAAA==.',
Sl='Slayur:BAAANQAECgcICAAAAA==.Slinkeril:BAAANQADCggIJwAAAA==.Sloppydro:BAABNQAECoEmAAMIAAkK0xDYRAA0AgAIAAkK0xDYRAA0AgADAAIKdwXmVQFUAAAAAA==.',
Sm='Smuckerz:BAAANQAECgEIAgAAAA==.',
So='Socksimus:BAAANQADCgcIEQAAAA==.Sockssham:BAAANQADCggICAAAAA==.Sotari:BAAANQADCgEIAQAAAA==.',
St='Stabberz:BAABNQAECoE5AAIWAAkKMx6RCgAdAwAWAAkKMx6RCgAdAwAAAA==.Stannane:BAAANQADCgUICQABNQADCggIJwAFAAAAAA==.Stellaloona:BAAANQADCgYIFgAAAA==.Sticks:BAAANQADCgYJBgAAAA==.Stinkyhooves:BAEANQADCgQIBgABNQAECgQIBQAFAAAAAA==.Stromboli:BAAANQADCgUJBQAAAA==.',
Su='Sushiroll:BAAANQAECgcIEQABNQAECgkJJgAEAFsiAA==.',
Sw='Sweetsourrex:BAAANQADCgYIBgABNQAECgkJLQAXAFgcAA==.',
Ta='Tamaqua:BAAANQAECgUICwAAAA==.',
Te='Telissa:BAAANQAECgEIAQAAAA==.Temoin:BAAANQAECgEIAQAAAA==.',
Th='Thalor:BAAANQAECgQIBAAAAA==.Thrass:BAAANQAECggIDAAAAA==.',
To='Toobrunner:BAAANQAECgUIBgAAAA==.',
Tr='Trueknight:BAAANQADCgEIAQAAAA==.',
Un='Unholeytoast:BAAANQAECgYICwABNQAFFAQICAAHAJALAA==.',
Va='Vampress:BAAANQAECgMIAwAAAA==.Variam:BAAANQAECgYIDwAAAA==.',
Ve='Velannis:BAABNQAECoEiAAQcAAgKCh9sBACwAgAcAAgKSh5sBACwAgAWAAUKeBeuSABZAQAXAAMKKBcuNgDlAAAAAA==.',
Vo='Voidangel:BAAANQADCggIEgAAAA==.Vonder:BAAANQADCggICAAAAA==.Voodooki:BAAANQADCggIIwAAAA==.',
Vu='Vuo:BAAANQAECgYICwAAAA==.',
Wi='Winze:BAAANQADCggIDgAAAA==.Withdraw:BAAANQADCgUIBQAAAA==.',
Wo='Wochese:BAAANQADCgYICwABNQAECggIHAAIAJkdAA==.',
Wr='Wrath:BAAANQADCggIDAABNQAECgUIDwAFAAAAAA==.',
Wu='Wuchese:BAAANQADCggICAABNQAECggIHAAIAJkdAA==.',
Xf='Xfreshh:BAAANQAECgYICQAAAA==.',
Ya='Yamaa:BAAANQAECgUIBgABNQAECgkJJgANAPwgAA==.Yamadono:BAAANQAECgQIBAABNQAECgkJJgANAPwgAA==.Yamá:BAAANQADCgcIBwABNQAECgkJJgANAPwgAA==.Yamå:BAABNQAECoEmAAINAAkK/CBxOAAKAwANAAkK/CBxOAAKAwAAAA==.',
Yi='Yingzhi:BAAANQADCgIIAgAAAA==.',
Za='Zapchese:BAAANQAECgUICgABNQAECggIHAAIAJkdAA==.',
Zo='Zortok:BAAANQAECgYICgAAAA==.',
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
