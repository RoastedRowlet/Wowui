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

local lookup = {'Hunter-Marksmanship','Warrior-Arms','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Holy','Evoker-Preservation','Rogue-Subtlety','Druid-Balance','Druid-Restoration','Druid-Feral','Mage-Arcane','Hunter-BeastMastery','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Warrior-Protection','Monk-Mistweaver','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','Druid-Guardian','Paladin-Retribution','DeathKnight-Blood','Paladin-Protection','Rogue-Assassination','Monk-Brewmaster','Shaman-Restoration','Shaman-Elemental','Warrior-Fury','Hunter-Survival','Warlock-Affliction','Evoker-Devastation',}
local provider = {region='US',realm='Ravenholdt',name='US',type='weekly',zone=53,date='2026-10-13',data={Ah='Ahote:BAAANQAECgUIEwAAAA==.',
Ai='Airrows:BAABNQAECn8dAAIBAAkKkhYXFAC9AgABAAkKkhYXFAC9AgAAAA==.',
Al='Alaois:BAABNQAECn8ZAAICAAcKeBGtpwC1AQACAAcKeBGtpwC1AQAAAA==.Almitywitey:BAAANQAECgYIDAAAAA==.Alphaomega:BAAANQAECgIIAwAAAA==.Alurea:BAAANQAECgIICQAAAA==.Alèxis:BAAANQAECgEIAgAAAA==.',
Am='Ampharosen:BAAANQAECggIDwAAAA==.',
An='Anguthar:BAAANQAECgEIAQAAAA==.Anthredis:BAACNQAFFH8dAAIDAAcK6hYKAgBfAgADAAcK6hYKAgBfAgA1AAQKfyEAAwMACQrCICIRAOMCAAMACQrCICIRAOMCAAQAAgoWCr6BAGkAAAAA.Anvi:BAAANQAECgEIAwAAAA==.',
Ar='Ara:BAACNQAFFH8SAAIFAAgKYSJZAAAhAwAFAAgKYSJZAAAhAwA1AAQKfykAAgUACQqHJm0BANsDAAUACQqHJm0BANsDAAAA.Argonäut:BAABNQAECn8pAAIEAAgKayO7DgArAwAEAAgKayO7DgArAwAAAA==.Arimalo:BAAANQAECgMIBAAAAA==.',
As='Asmindissa:BAAANQAECgMIAwAAAA==.Astragos:BAABNQAECn8dAAIGAAkKtBWEFQBaAgAGAAkKtBWEFQBaAgAAAA==.',
Au='Automedusa:BAAANQADCgYICwAAAA==.',
Az='Azagorod:BAAANQAECgQIBAABNQAECgkJIgAHAIEhAA==.',
Ba='Baern:BAAANQAECgIICQAAAA==.',
Be='Bearricade:BAABNQAECn8oAAQIAAgKABaMNwAtAgAIAAgKABaMNwAtAgAJAAYKNxKROABUAQAKAAIKcw02NABtAAAAAA==.',
Bi='Billamong:BAAANQAECgIICQAAAA==.Biren:BAAANQADCgYIBgAAAA==.',
Bl='Blitzer:BAAANQAECgQICgAAAA==.',
Bo='Bonechill:BAAANQAECgQIBAAAAA==.Boney:BAAANQAECgEIAQAAAA==.',
Br='Brightstorm:BAAANQAECgIIBQAAAA==.Brisket:BAAANQAECggIEwABNQAECggIKAAIAAAWAA==.',
Ca='Calciferkyo:BAABNQAECn8XAAILAAcKHgXXLQE8AQALAAcKHgXXLQE8AQAAAA==.Cassilune:BAAANQADCgcIBwABNQAECgkJMgAFABQaAA==.Catelaya:BAABNQAECn8pAAIMAAkKDRZ+SgCMAgAMAAkKDRZ+SgCMAgAAAA==.',
Ch='Chaosrows:BAAANQADCggICAAAAA==.Chexk:BAABNQAECn8iAAIHAAkKgSGpBABFAwAHAAkKgSGpBABFAwAAAA==.Chixnu:BAAANQAECgQIBwAAAA==.Chushing:BAABNQAECn8qAAINAAkKPR9WDgD4AgANAAkKPR9WDgD4AgAAAA==.',
Co='Come:BAAANQAECgQIBAAAAA==.Conejomalo:BAABNQAECn8ZAAMOAAgKLBNviwDFAQAOAAcKNxJviwDFAQAPAAMKQQ7HQwC1AAAAAA==.',
Cr='Crush:BAAANQAECggICAABNQAFFAUIEwAIALEWAA==.Cryblood:BAAANQAECgQIBwAAAA==.',
Cu='Cutsiecow:BAABNQAECn8sAAIIAAkKRSFgEgAzAwAIAAkKRSFgEgAzAwAAAA==.',
Cy='Cynos:BAAANQADCgEIAQAAAA==.Cynthic:BAAANQAECgQICwAAAA==.',
Da='Daelynn:BAAANQAECgUIEAAAAA==.Daffodil:BAAANQABCgIIBAAAAA==.',
De='Deathpluck:BAAANQADCgUICQABNQAECgcIDAAQAAAAAA==.',
Dj='Djiinar:BAABNQAECn8uAAMRAAkK+hp4DABrAgARAAgK+hp4DABrAgACAAgKCRUIiQABAgAAAA==.Djiink:BAAANQADCgIIAgAAAA==.Djiinra:BAAANQADCgcIBwAAAA==.Djiinz:BAAANQADCgcIBwAAAA==.',
Do='Doomlocke:BAABNQAECn8eAAMNAAgKtwm7MwBzAQANAAgKtwm7MwBzAQASAAMKGgOMQwBaAAAAAA==.',
Eb='Ebonymoon:BAAANQADCgIIAgAAAA==.',
El='Elise:BAACNQAFFH8mAAMTAAkK+SE8AACCAwATAAkK+SE8AACCAwAUAAEKoRhhMwBIAAA1AAQKfyMAAxMACQpoJvwFAHcDABMACQpoJvwFAHcDABQAAQotFj3wAEkAAAAA.',
Em='Em:BAABNQAECn8WAAMTAAcKvQs9OQBYAQATAAcKvQs9OQBYAQAUAAcKSQ1alQBQAQAAAA==.',
En='Enzo:BAAANQAECgMIAwAAAA==.',
Er='Eraline:BAABNQAECn8qAAISAAgKFREyHQCwAQASAAgKFREyHQCwAQAAAA==.Erisa:BAAANQAECgUICgAAAA==.',
Ey='Eyekora:BAAANQADCgMIAwAAAA==.',
Fa='Facehunter:BAAANQAECgIIAwAAAA==.Faelyn:BAAANQADCgUIDAAAAA==.',
Fc='Fcawf:BAAANQADCgMIBQAAAA==.',
Fe='Fearless:BAABNQAECn8eAAIVAAgKCyLZGQDwAgAVAAgKCyLZGQDwAgAAAA==.Felygog:BAAANQADCgQIBwAAAA==.Fenrirblood:BAABNQAECn8bAAQJAAgKQxzpGAByAgAJAAgKQxzpGAByAgAWAAUKkgrrPADEAAAIAAEKAAC6rgA1AAAAAA==.',
Fi='Fiizz:BAAANQAECgEIBAAAAA==.Firecaneost:BAAANQADCgcIBwAAAA==.Fiyer:BAAANQADCgQIBAAAAA==.Fizzlepriest:BAAANQADCggIDgABNQAECggIFQAXAGIXAA==.',
Fr='Fraydun:BAAANQAECgEIAQAAAA==.Frostblood:BAAANQAECgQICgAAAA==.',
Fu='Fuknar:BAAANQADCgUIBQAAAA==.Funk:BAAANQADCgIIAgABNQAFFAYIHAAYAOglAA==.',
Ge='Genivan:BAAANQADCgQICgAAAA==.Genocya:BAAANQAECgYJDQAAAA==.',
Gh='Ghost:BAAANQAECgQICAAAAA==.',
Gi='Gilden:BAAANQAECgUICAAAAA==.',
Gn='Gnot:BAAANQAECgQICQAAAA==.',
Go='Goshujinsama:BAAANQADCgYICAAAAA==.',
Gr='Griz:BAAANQAECgcICQAAAA==.',
Gy='Gyoza:BAAANQAECgIIAgABNQAECggIKAAIAAAWAA==.',
['Gò']='Gòddess:BAAANQAECgUICgAAAA==.',
Ha='Hannahsmad:BAAANQAECgQIBgAAAA==.Harlee:BAAANQAECgUICQAAAA==.Haukkah:BAABNQAECn8gAAIMAAgKEAlSmQDRAQAMAAgKEAlSmQDRAQAAAA==.',
He='Heffalump:BAABNQAECn8dAAIIAAgKoxFUQQDwAQAIAAgKoxFUQQDwAQAAAA==.Hetfield:BAAANQAECgQICAAAAA==.Hexanyth:BAAANQADCgQIBAAAAA==.',
Ho='Holycrves:BAAANQADCgQICAAAAA==.',
['Hï']='Hïbiki:BAAANQADCgQIBQAAAA==.',
If='Ifa:BAAANQADCgQICAAAAA==.',
Im='Impact:BAAANQADCgcIEQABNQAECggIKQAZAHEgAA==.',
In='Inazuma:BAAANQADCgYICwAAAA==.Innerlect:BAAANQADCgYIBgABNQAECggIGgAaAHMKAA==.',
Ir='Iridian:BAAANQAECgUIBQAAAA==.',
Iy='Iyotanka:BAAANQADCgUIDAAAAA==.',
Ja='Jameo:BAABNQAECn8XAAIOAAgKPwl8mwCcAQAOAAgKPwl8mwCcAQABNQAECgcIDAAQAAAAAA==.',
Ji='Jig:BAAANQAECgYIEwABNQAECgcIDAAQAAAAAA==.',
Ju='Juicebox:BAAANQADCggICQABNQAECgkJLgAbABUNAA==.Juuzau:BAAANQAECgQIBgAAAA==.',
['Jå']='Jåmes:BAAANQAECgEIAQAAAA==.',
Ka='Kaners:BAABNQAECn8dAAIHAAgKrh8XCwDBAgAHAAgKrh8XCwDBAgAAAA==.Kathoran:BAABNQAECn8YAAIMAAYKuwcP1wBNAQAMAAYKuwcP1wBNAQAAAA==.Katie:BAAANQAECgMIBAABNQAFFAcIHAAcAO4jAA==.',
Ke='Kealey:BAAANQAECgYICAAAAA==.Kessik:BAAANQAECgYIDAAAAA==.',
Kh='Khaless:BAAANQAECgUICAAAAA==.',
Ki='Kiamors:BAABNQAECn8dAAMdAAgKWAOrtwAeAQAdAAgKWAOrtwAeAQAcAAYKCwGu7ACMAAAAAA==.',
Ko='Kolaid:BAAANQADCgMIBQAAAA==.',
Kr='Kragzug:BAABNQAECn8XAAMCAAcKXBm4lQDiAQACAAcKXBm4lQDiAQAeAAMKbR0rGwDxAAAAAA==.Kreleing:BAAANQADCgIIAgAAAA==.',
La='Labiaminoris:BAAANQADCgQIAwAAAA==.',
Le='Leda:BAAANQADCgUIDAAAAA==.Lexy:BAAANQADCgEIAQAAAA==.',
Li='Lightfighter:BAAANQAECgcIDAAAAA==.Lighthouse:BAACNQAFFH8cAAIYAAYK6CVmBAA0AgAYAAYK6CVmBAA0AgA1AAQKfx8AAxgACQotI9QPAC0DABgACQotI9QPAC0DABUAAwpJFXyhALQAAAAA.Lilkiwi:BAAANQAECgUICQAAAA==.Linley:BAAANQADCggICAAAAA==.',
Lo='Loozer:BAABNQAECn8pAAIfAAkK3RzrAgDzAgAfAAkK3RzrAgDzAgAAAA==.',
Lu='Lunchbox:BAAANQAECgUIDgAAAA==.Lunecy:BAAANQAECgMIBwAAAA==.',
Ly='Lyumi:BAAANQAECgYIDQAAAA==.',
['Lå']='Låz:BAAANQADCggIFQAAAA==.',
Ma='Matty:BAABNQAECn8ZAAIXAAkKLRDBfQAqAgAXAAkKLRDBfQAqAgABNQAFFAYIFQALAJYdAA==.Maxkiwi:BAAANQADCgMJBAAAAA==.Mazikeenx:BAAANQADCgEIAQAAAA==.',
Me='Medie:BAABNQAECn8eAAIUAAgK7RrsRABVAgAUAAgK7RrsRABVAgAAAA==.Melody:BAAANQAECgQIBgAAAA==.',
Mi='Michelle:BAABNQAECn8nAAMFAAgKUSPxFAArAwAFAAgKUSPxFAArAwAXAAEKAACAowEyAAAAAA==.',
Mo='Monstrosity:BAAANQAECgQIBQABNQAECggIDwAQAAAAAA==.',
['Mä']='Mäenard:BAAANQADCgcIFQAAAA==.',
Na='Naji:BAACNQAFFH8MAAQPAAUKcSVnBADSAAAPAAIK3SRnBADSAAAOAAIKmSZoKADAAAAgAAEKAADECwBNAAA1AAQKfysABA8ACQrQI6ELAD0CAA4ABgpTI+tVAFECAA8ABwoyHqELAD0CACAABAqmHzAQAEcBAAAA.',
Ne='Necro:BAAANQADCgUICgAAAA==.Neesa:BAAANQADCgMIAwABNQAFFAMIBgATAGQOAA==.',
Ni='Ninguem:BAAANQAECgUIBwAAAA==.',
No='Noodge:BAAANQADCggIDAAAAA==.Nostariel:BAAANQAECgUICAAAAA==.Noxadin:BAAANQAECgEIAQAAAA==.',
Nu='Nutshotz:BAAANQABCgIIAwAAAA==.',
Pe='Peterpiper:BAABNQAECn8fAAIhAAgK4RRHFAAHAgAhAAgK4RRHFAAHAgAAAA==.',
['Pè']='Pètitemort:BAAANQADCgMIAwAAAA==.',
Ra='Raymane:BAAANQAECgQIBgAAAA==.Rayvash:BAAANQAECgIIAgAAAA==.',
Re='Reverendbdt:BAAANQADCgQIBQABNQAECggIGgAaAHMKAA==.',
Ri='Rivanon:BAAANQADCggICAAAAA==.',
Ro='Rosastrasza:BAAANQADCgYIDQAAAA==.',
Ru='Ruhster:BAAANQADCggIEAAAAA==.Ruthos:BAAANQAECgMIBwAAAA==.',
Ry='Rykka:BAABNQAECn8ZAAIMAAYKPweg4gA2AQAMAAYKPweg4gA2AQAAAA==.Ryukie:BAAANQADCggICgAAAA==.',
Sa='Sathoran:BAAANQADCgQIBAAAAA==.Savall:BAAANQAECgYIDAAAAA==.',
Se='Servatal:BAABNQAECn8WAAIOAAYK2AUv3gAHAQAOAAYK2AUv3gAHAQAAAA==.',
Sh='Sharun:BAAANQAECgUICAAAAA==.Shireska:BAAANQADCggIDAAAAA==.',
Si='Sidehussy:BAABNQAECn8kAAIGAAgK4RgbFgBSAgAGAAgK4RgbFgBSAgAAAA==.',
So='Sorinmarkov:BAAANQAECgEIAgAAAA==.',
Sp='Sploçk:BAAANQAECgEIAgAAAA==.',
Sq='Squirt:BAAANQADCgcIBwABNQAECgQICQAQAAAAAA==.',
St='Stats:BAAANQAECgYIEAAAAA==.Stingerslick:BAABNQAECn8mAAIaAAgKCQviPwDIAQAaAAgKCQviPwDIAQAAAA==.Stoompbda:BAAANQAECgEIAQAAAA==.Stormtusk:BAAANQAECgEIAQABNQAECgQICAAQAAAAAA==.',
Sy='Syehanan:BAAANQADCgcICgAAAA==.',
Ta='Tazrii:BAAANQADCggICAAAAA==.',
Th='Thorfine:BAABNQAECn8fAAMCAAcKBw+dtACUAQACAAcKBw+dtACUAQARAAIKMQffPABMAAAAAA==.',
Ti='Tinymittenz:BAAANQAECgMIBAAAAA==.',
To='Toetaah:BAAANQADCggICAAAAA==.Touraine:BAAANQAECgYIDwAAAA==.',
Tr='Traedalei:BAAANQADCgMIAwAAAA==.Trajann:BAAANQAECgEIAQAAAA==.Trayndra:BAAANQAECgUIBgAAAA==.',
Ty='Tycharious:BAAANQADCggICAABNQAECggIFQAfAPsZAA==.',
Un='Unmei:BAABNQAECn8aAAMdAAgK1wm1rQA0AQAdAAcKxQa1rQA0AQAcAAcKrQRDsAAKAQAAAA==.',
Va='Valkrynd:BAAANQAECgIIAgAAAA==.Valynor:BAAANQAECggICgABNQAECgkJIgAHAIEhAA==.Varaz:BAABNQAECn8ZAAMGAAcKURKQLAA/AQAGAAYKeg+QLAA/AQAhAAUKThG1JAAWAQAAAA==.',
Ve='Vendle:BAABNQAECn8kAAMMAAgKNBuBVgBsAgAMAAgKNBuBVgBsAgABAAEKyQs0jQAwAAAAAA==.',
Wa='Wapow:BAAANQAECgUICgAAAA==.Wazo:BAAANQADCgcIBwAAAA==.',
Wi='Windrunners:BAAANQAECgQIEAAAAA==.',
Xe='Xenophon:BAAANQADCgYICwAAAA==.',
Xo='Xolthoras:BAAANQAECggIDwAAAA==.',
Xu='Xuedk:BAAANQAECgQICgAAAA==.',
Ya='Yaoi:BAAANQAECggICAAAAA==.',
Yo='Yohshee:BAAANQAECgUIBgAAAA==.',
Za='Zap:BAABNQAECn8ZAAIdAAcKng/ZcQDHAQAdAAcKng/ZcQDHAQAAAA==.Zargabaath:BAAANQAECgQIBQAAAA==.',
Ze='Zebranjin:BAAANQADCgUICAAAAA==.Zeldoris:BAABNQAECn8pAAIZAAgKcSA4DADUAgAZAAgKcSA4DADUAgAAAA==.',
Zi='Zirina:BAAANQAECgYICgAAAA==.',
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
