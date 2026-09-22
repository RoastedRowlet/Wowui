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

local lookup = {'Warlock-Demonology','Unknown-Unknown','Warrior-Protection','Rogue-Subtlety','Evoker-Preservation','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Havoc','Hunter-Marksmanship','Mage-Arcane','Shaman-Restoration','Warrior-Fury','Warrior-Arms','Warlock-Affliction','Druid-Guardian','Evoker-Devastation','Hunter-BeastMastery','Druid-Restoration','Druid-Balance','Monk-Mistweaver','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Acotas:BAAANQADCgQJAwAAAA==.',
Af='Affli:BAABNQAECoEdAAIBAAgKNB2aHAC9AgABAAgKNB2aHAC9AgAAAA==.',
Ai='Aiunar:BAAANQAECgUJCwAAAA==.Aiupriesty:BAAANQAECgEJAgABNQAECgUJCwACAAAAAA==.',
Ak='Aka:BAAANQADCgIIAgAAAA==.Akaza:BAAANQADCggIDAAAAA==.',
Al='Alastiria:BAAANQAECgEJAQAAAA==.Aleinara:BAAANQAECgMIBQAAAA==.',
Am='Amazngrace:BAAANQADCgYIBgAAAA==.',
An='Andsey:BAAANQADCgYIBgABNQAECgMJBAACAAAAAA==.Annore:BAAANQAECgUIDQAAAA==.',
Aq='Aquelius:BAAANQAECgEJAQAAAA==.Aqular:BAAANQAECgQIDgAAAA==.',
Ar='Argyre:BAABNQAECoEdAAIDAAgKsSQ+AgBNAwADAAgKsSQ+AgBNAwAAAA==.Artifice:BAABNQAECoEVAAIEAAkK7SCNAgB1AwAEAAkK7SCNAgB1AwAAAA==.',
As='Asynic:BAAANQADCggICAAAAA==.Asynicl:BAAANQADCgYIBgAAAA==.',
Aw='Awooing:BAAANQADCggIDgABNQAECgQICQACAAAAAA==.',
Az='Azaziel:BAAANQAECgcJEQAAAA==.Azells:BAAANQADCgEIAQABNQAECgkJHwAFAIghAA==.',
Ba='Bariesh:BAAANQADCgQIBAAAAA==.',
Be='Bearface:BAAANQADCgUIBQAAAA==.Behindyou:BAAANQADCgcJCQAAAA==.Belgaria:BAAANQADCgYIDgAAAA==.Berryknight:BAAANQAECgMJBAAAAA==.Bewlzeye:BAAANQAECgEIAQAAAA==.',
Bi='Bigjonmachne:BAAANQAECgQIDQABNQAECggIGQAGAJQfAA==.Binky:BAAANQADCgUIBQAAAA==.',
Bl='Blackdog:BAAANQAECgIIAwAAAA==.Blackguyy:BAAANQAECgUIEAAAAA==.Bloodletter:BAAANQABCgIIAgAAAA==.Bloodsail:BAAANQADCgYJBgAAAA==.',
Bo='Bollux:BAAANQAECgcJEgAAAA==.Bonetatter:BAAANQADCggIEAAAAA==.Bongonnaink:BAAANQAECgYJDQAAAA==.Bownyxia:BAAANQAECgYJBwABNQAFFAYJDQAHAG4XAA==.Bowties:BAACNQAFFIENAAQHAAYKbhdUAQDiAQAHAAUKohlUAQDiAQAIAAIKCBWlCACpAAAJAAEKbAx2IAAoAAA1AAQKgSoABAcACQrgJSsCAM0DAAcACQoKJSsCAM0DAAgABQoJI2QgAPYBAAkAAgrjDA+DAGsAAAAA.',
Br='Brewfú:BAAANQADCgIJAgAAAA==.Brotie:BAACNQAFFIEFAAIKAAIKnw62CwCWAAAKAAIKnw62CwCWAAA1AAQKgSAAAgoACQoQHFwPANUCAAoACQoQHFwPANUCAAE1AAUUBgkNAAcAbhcA.',
Bt='Btmanight:BAAANQADCggICAABNQAECgYIDgACAAAAAA==.',
Bu='Bullshiift:BAAANQADCgYIBgAAAA==.Burntbiscuit:BAAANQADCgUIBQAAAA==.Buugada:BAAANQADCggJEQAAAA==.',
Ca='Caedo:BAAANQADCgIIAgABNQADCgMIAwACAAAAAA==.Calischism:BAAANQAECgEJAgAAAA==.Canadiangoos:BAAANQADCgUJBQAAAA==.Cantspell:BAAANQAECgIJAgAAAA==.Carobnica:BAAANQADCgQJBAABNQADCgYJBgACAAAAAA==.Cavantes:BAAANQADCgIIAgAAAA==.',
Ce='Celaris:BAAANQADCggIEwAAAA==.Cell:BAAANQABCgIIAgAAAA==.Celleyna:BAAANQABCggICQAAAA==.',
Ch='Chataykay:BAAANQADCgQIBQAAAA==.Chathsong:BAAANQADCggICAAAAA==.Chichichikin:BAAANQADCgcIBwAAAA==.Chunkyclaps:BAAANQADCgEIAQAAAA==.',
Ci='Citrus:BAAANQAECgcJEwAAAA==.',
Cn='Cn:BAABNQAECoEXAAIGAAgKISFlHQD6AgAGAAgKISFlHQD6AgAAAA==.',
Co='Codeman:BAAANQAECgYJDQAAAA==.Cordine:BAAANQADCgYIBgAAAA==.',
Cp='Cptinsaneo:BAACNQAFFIEFAAIHAAMKshIIBQAXAQAHAAMKshIIBQAXAQA1AAQKgRgAAgcACQrCGtMWALUCAAcACQrCGtMWALUCAAAA.',
Cr='Crimdh:BAAANQAECgQJBAABNQAFFAMIAwACAAAAAA==.Crimdk:BAAANQAECgUIBwABNQAFFAMIAwACAAAAAA==.',
Cz='Czin:BAAANQAECgIIAgAAAA==.',
Da='Dalén:BAAANQADCgUIBQAAAA==.',
De='Deathverses:BAACNQAFFIEHAAILAAQKxSTxAwC8AQALAAQKxSTxAwC8AQA1AAQKgT8AAgsACQq3JmYAAPYDAAsACQq3JmYAAPYDAAAA.Demonbiscuit:BAABNQAECoEeAAIKAAgKAybCBAB+AwAKAAgKAybCBAB+AwAAAA==.Denarkis:BAAANQADCgQIBAAAAA==.Derpydawg:BAAANQADCgYIBgABNQAECgkJFwAMAC0SAA==.Destructus:BAAANQAECgEIAgAAAA==.Deviancy:BAAANQAECgYJEAAAAA==.Devocean:BAAANQADCgUIBQAAAA==.Dexxt:BAAANQAECgIJAgAAAA==.',
Di='Dikslapp:BAAANQAECgUIBQAAAA==.Dirlin:BAAANQADCgQIBAAAAA==.Ditto:BAAANQADCggJNgAAAA==.',
Dl='Dlitinaro:BAAANQAECgYIDAAAAA==.',
Do='Donoph:BAAANQAECgYIDQAAAA==.Doomar:BAAANQAECgcJEwAAAA==.Dordire:BAAANQAECgEJAQAAAA==.Dotzilla:BAAANQADCgEIAQAAAA==.',
Dr='Dragindznuts:BAAANQADCgQIBAAAAA==.Drayn:BAABNQAECoEYAAIBAAgKrh0JHQC6AgABAAgKrh0JHQC6AgAAAA==.Dreaveous:BAAANQAECgcJEgAAAA==.Drugar:BAAANQAECgEJAgAAAA==.',
Du='Duint:BAAANQADCgcJDAAAAA==.',
Eb='Eborsisk:BAAANQADCgEIAQAAAA==.',
Ec='Eclipsion:BAAANQAECgMJBAAAAA==.',
Ee='Eelane:BAAANQAECgQICQAAAA==.',
El='Elementali:BAAANQADCggICAAAAA==.Ell:BAAANQADCgYJDgAAAA==.',
En='Endurall:BAAANQADCgQIBAABNQAECgcJEwACAAAAAA==.',
Er='Eradication:BAAANQAECgcIDQAAAA==.',
Et='Etheria:BAAANQAECgEIAQABNQAFFAMJBQANAHoRAA==.',
Ev='Evilexo:BAAANQADCgcIBwAAAA==.',
Ex='Exxotic:BAAANQABCgIIAgAAAA==.',
Fa='Faedia:BAAANQABCgYIDAABNQAECgMJBAACAAAAAA==.Fahlafflez:BAABNQAECoEYAAMOAAgKZg72BwDlAQAOAAgKZg72BwDlAQAPAAYKZgZnqAAIAQAAAA==.Fahros:BAABNQAECoEQAAIMAAcKvyMkZgBdAgAMAAcKvyMkZgBdAgAAAA==.Farkhaz:BAAANQADCggICAAAAA==.Faydron:BAAANQADCgMJAwABNQAECgQICAACAAAAAA==.',
Fe='Felful:BAAANQAECgMIAwABNQAECggJHwAGAPMbAA==.',
Ff='Ffloyd:BAAANQADCgcIBwAAAA==.',
Fi='Fingielock:BAAANQAECgMJAwAAAA==.Firedeezball:BAAANQADCgcIBwAAAA==.Fishinfridge:BAAANQAECgcICQAAAA==.',
Fl='Flloyd:BAAANQAECgcJEAAAAA==.Floÿd:BAAANQADCgYIDAAAAA==.Fløyd:BAAANQADCgYIBgAAAA==.',
Fo='Folid:BAAANQADCgMIAgAAAA==.Fortwooh:BAAANQADCgYJBgAAAA==.',
Fr='Francy:BAAANQAECgUJCAAAAA==.',
Fu='Fuzzyspells:BAAANQADCgcIEQAAAA==.',
Ga='Gambling:BAAANQADCggICAAAAA==.Gatzul:BAAANQADCgMIBAABNQADCggICAACAAAAAA==.',
Gh='Ghostbladez:BAAANQAECgQJCAAAAA==.',
Gi='Gib:BAAANQADCgMIAwAAAA==.',
Gn='Gnomaste:BAAANQADCgYIBgAAAA==.',
Go='Gomga:BAAANQADCggICAABNQAECggJHwAGAPMbAA==.Goththighs:BAACNQAFFIEKAAIMAAUKFh2KBgDwAQAMAAUKFh2KBgDwAQA1AAQKgR0AAgwACQorJKcZAFEDAAwACQorJKcZAFEDAAAA.',
Gr='Grawler:BAAANQADCgYIBwAAAA==.Grimdk:BAAANQAECgIIBAAAAA==.Grissa:BAAANQAECggICQAAAA==.',
Gu='Gumgumfury:BAAANQADCggJEQAAAA==.',
Ha='Halzlok:BAAANQAECgQJCgAAAA==.Harmful:BAAANQADCgcIBwABNQAECggIGwAQAA4hAA==.',
He='Herøn:BAAANQADCgYICgAAAA==.',
Hi='Hilarie:BAAANQADCgYICwAAAA==.',
Hu='Hunterschmax:BAAANQAECgYIDwAAAA==.',
Ic='Icemachine:BAAANQABCgUIBwAAAA==.',
Ih='Ihot:BAAANQAECgEIAgAAAA==.',
Ik='Ikayhaimahn:BAABNQAECoEaAAIRAAkKCSMoAQCcAwARAAkKCSMoAQCcAwAAAA==.',
In='Incideranus:BAAANQADCggIBAAAAA==.Indishaman:BAABNQAECoEaAAINAAgKWCRRCgA8AwANAAgKWCRRCgA8AwAAAA==.',
Ir='Iris:BAAANQADCgMJAwAAAA==.Ironbound:BAAANQADCgUJBQABNQAECgUIDAACAAAAAA==.',
Iv='Ivoric:BAAANQAECggJCAAAAA==.',
Ja='Jabronygos:BAABNQAECoEjAAISAAkKEiBbBAAtAwASAAkKEiBbBAAtAwAAAA==.Jarnroz:BAAANQADCgIIAgAAAA==.',
Je='Jeatalena:BAAANQAECgQIBAAAAA==.',
Jh='Jhara:BAAANQAECgMJBAAAAA==.',
Jo='Joeheals:BAAANQADCgUIBwAAAA==.',
Ju='Junior:BAAANQAECgEIAQABNQAECgkJHwAFAIghAA==.',
Ka='Kablinkiaa:BAAANQADCgYICAAAAA==.Kaendas:BAAANQAECgEIAQAAAA==.Kaizayu:BAAANQADCggICQAAAA==.Kalier:BAAANQADCgYIBgAAAA==.Kalypso:BAAANQAECgMJAwAAAA==.Kamekazi:BAAANQADCgcIBwAAAA==.Katastrophic:BAAANQADCggIEwAAAA==.Katieylyn:BAAANQAECgUIBgABNQAECgkJHwAFAIghAA==.',
Ke='Keelanllan:BAAANQADCgYIDgAAAA==.Keilun:BAEANQADCgIIAgAAAA==.Kertzz:BAAANQADCgcIFAABNQADCggIEAACAAAAAA==.Kew:BAAANQAECgEIAQAAAA==.',
Kn='Kneecromance:BAAANQAECgEJAQAAAA==.Knightxl:BAAANQADCgEIAQAAAA==.',
Ko='Kokuten:BAAANQADCgQIBAABNQAFFAMJBQANAHoRAA==.Koral:BAAANQADCggIEwAAAA==.',
Ku='Kungfuhealya:BAAANQAECgMIBQAAAA==.Kurog:BAAANQABCgEIAQAAAA==.',
La='Larrydale:BAAANQADCgYICwAAAA==.',
Le='Lea:BAAANQADCgcIBwABNQADCgYIBgACAAAAAA==.Lefica:BAAANQABCgIJAgAAAA==.Legacyx:BAAANQADCgcIDAABNQAECgcIDQACAAAAAA==.Leonardorich:BAAANQADCgcIEQAAAA==.Leondis:BAABNQAECoEdAAITAAgKOxtFKwCHAgATAAgKOxtFKwCHAgAAAA==.Lexifu:BAABNQAECoEgAAMUAAkKyyCeBABFAwAUAAkKyyCeBABFAwAVAAUKMg2cUwADAQAAAA==.Lexipriest:BAAANQAECgYIBgAAAA==.Leylla:BAAANQADCgIIAQABNQADCggIEAACAAAAAA==.',
Li='Lightful:BAABNQAECoEfAAIGAAgK8xsXMACXAgAGAAgK8xsXMACXAgAAAA==.Lilbro:BAABNQAECoEdAAIPAAkKZyOZCQCOAwAPAAkKZyOZCQCOAwAAAA==.Lit:BAAANQADCggIDQABNQAECggIGwAQAA4hAA==.',
Lo='Lokii:BAAANQABCgMIAwAAAA==.',
Lu='Lumosmaxiima:BAAANQADCggIDgAAAA==.',
Ma='Madamme:BAAANQAECgYJDQAAAA==.Madkingzack:BAAANQAECgUJBwAAAA==.Maevea:BAAANQAECgMIAwAAAA==.Malagig:BAAANQADCgIJAgAAAA==.Malaviolence:BAAANQABCgcJBwAAAA==.Malistavias:BAAANQAECgMIBQAAAA==.Malliki:BAAANQAECgUIBQAAAA==.Marnangus:BAAANQAECgcIDwABNQADCgIIAgACAAAAAA==.Marnolkas:BAAANQADCgQIBAABNQADCgcIDwACAAAAAA==.Mathan:BAAANQAECgYIDwAAAA==.Maudib:BAAANQAECgcIEgAAAA==.Mawile:BAAANQAECgQJCQAAAA==.',
Me='Meesha:BAAANQADCgcIEgAAAA==.Mehunta:BAAANQADCgIIAgAAAA==.Melinarra:BAAANQAECgQIBAAAAA==.Messe:BAAANQAECgcJEwAAAA==.Methious:BAAANQAECgIJAgAAAA==.',
Mi='Milicious:BAAANQABCgMJBQAAAA==.',
Mo='Molatile:BAAANQAECgMIAwAAAA==.Montu:BAAANQADCggICAAAAA==.Moogyver:BAAANQABCggJDgAAAA==.Moonsguard:BAAANQADCgcJFgAAAA==.Moovit:BAAANQADCggIEwAAAA==.Mordekaíser:BAAANQAECgIIAgAAAA==.Moth:BAAANQAECgQJCAAAAA==.',
Mu='Murre:BAAANQADCgYJBgAAAA==.',
Na='Nasmiuu:BAAANQAECgIIAgAAAA==.',
Ne='Nekfury:BAAANQAECgEIAQAAAA==.Nepeta:BAAANQAECgUJCgAAAA==.Nevenel:BAAANQADCgMIAwAAAA==.',
Ni='Nivan:BAAANQAECgEJAQAAAA==.Niço:BAAANQAECgcICQAAAA==.',
No='Nocturnall:BAAANQADCgQIBAAAAA==.Noicce:BAAANQAECgcJEwAAAA==.Noicewar:BAAANQAECgIIAgAAAA==.Notcrims:BAAANQAFFAMIAwAAAA==.Notcrym:BAAANQAECgEIAQABNQAFFAMIAwACAAAAAA==.',
Nu='Nutz:BAAANQAECggICAAAAA==.',
Oa='Oakmoss:BAAANQAECgcICgAAAA==.',
Or='Orcleave:BAAANQAECgcICQAAAA==.Orwan:BAAANQAECgQIBgAAAA==.',
Pi='Pisslowmage:BAAANQABCgUIBwABNQAECgcICQACAAAAAA==.',
Pr='Pristene:BAAANQADCggJCwAAAA==.',
Qu='Quorra:BAAANQADCgUJBgAAAA==.',
Ra='Ragecakes:BAAANQADCgYIBQAAAA==.Rakagar:BAAANQAECgMIBAAAAA==.Raktot:BAAANQADCgEIAQAAAA==.Razluz:BAAANQADCgUJCAAAAA==.',
Re='Reue:BAABNQAECoEhAAIWAAkKXw/FDgAZAgAWAAkKXw/FDgAZAgAAAA==.',
Rh='Rhaegos:BAAANQADCgcIDwAAAA==.',
Ri='Riggzz:BAAANQAECgIIAgAAAA==.',
Ru='Ruuna:BAAANQABCgIIAgAAAA==.',
['Rí']='Rígg:BAAANQAECgEIAQAAAA==.',
Sa='Salla:BAAANQADCggICwAAAA==.',
Sc='Schmaximus:BAAANQADCgYJDgABNQAECgYIDwACAAAAAA==.Scrapyjack:BAAANQAECgUICAABNQAECgYIDAACAAAAAA==.',
Se='Senna:BAAANQADCgMIAwAAAA==.',
Sh='Shale:BAABNQAECoEYAAIFAAgKYwwAGQC9AQAFAAgKYwwAGQC9AQAAAA==.Shammit:BAAANQADCgIIAgAAAA==.Shammytyme:BAAANQAECgYIEQAAAA==.Shampow:BAAANQAECgQJBgAAAA==.Shamyhagar:BAAANQADCgQIBAAAAA==.Shangtsung:BAABNQAECoEnAAMUAAkK9yEcBABTAwAUAAkK9yEcBABTAwAVAAIKZwzsbwB0AAAAAA==.Sharaiya:BAAANQAECgYJDQAAAA==.Sharkmanfive:BAAANQAECgQICAAAAA==.Shaure:BAAANQADCgIIAgAAAA==.Shearwater:BAAANQAECgQICgAAAA==.',
Si='Silversesu:BAAANQAECgEJAQABNQAECgYJDgACAAAAAA==.',
Sk='Skirtero:BAAANQADCgYJBgAAAA==.',
Sl='Slava:BAAANQAECggJDwAAAA==.Sledgehammer:BAAANQADCgIIAgAAAA==.Sleepytoker:BAAANQADCgYJBgAAAA==.',
So='Soltergeist:BAAANQAECgcIEQAAAA==.',
Sp='Spine:BAAANQADCggIFQAAAA==.',
Ss='Ssyd:BAAANQADCggICAAAAA==.',
St='Steaknshock:BAAANQADCgMIBQAAAA==.Stormhoofs:BAABNQAECoEmAAIXAAkKhSN1AQCSAwAXAAkKhSN1AQCSAwAAAA==.',
Su='Subzone:BAAANQAECgcJDgAAAA==.Sumnabiscuit:BAABNQAECoEXAAIMAAkKLRLtagBRAgAMAAkKLRLtagBRAgAAAA==.Sunder:BAAANQADCgUIBQABNQAECggJHwAGAPMbAA==.Sunmaster:BAAANQAECgUJCwAAAA==.Supercharged:BAAANQADCggICAAAAA==.',
Ta='Tackshi:BAAANQADCggIDAAAAA==.Tankinit:BAAANQADCggJFgAAAA==.Tarea:BAAANQADCgQIBwAAAA==.Tatterbone:BAAANQADCgYJCgABNQADCggIEAACAAAAAA==.',
Te='Temufuzzy:BAAANQADCgEJAQAAAA==.Tenzink:BAAANQAECgcJEQAAAA==.',
Tf='Tflow:BAAANQAECgYIEAAAAA==.',
Th='Théworld:BAAANQABCgIIBAABNQADCgcJFgACAAAAAA==.',
Ti='Tindranga:BAAANQADCgcJHgAAAA==.Titansgrippy:BAAANQAECgYJBgAAAA==.',
To='Tolbert:BAAANQADCgMIAwABNQADCgYJBgACAAAAAA==.Totemir:BAAANQAECgYIEwAAAA==.',
Tr='Trammatize:BAAANQAECgYIEAAAAA==.Triptamean:BAAANQADCgYJDwAAAA==.',
Tw='Twobladebray:BAAANQAECgcIEQAAAA==.',
Un='Unglaus:BAAANQAECgYIBgAAAA==.',
Uz='Uzington:BAABNQAECoEeAAIDAAkKOiBWAgBGAwADAAkKOiBWAgBGAwAAAA==.',
Va='Valeta:BAAANQADCggIGwAAAA==.Valzlok:BAAANQADCgYICwAAAA==.Vanessa:BAAANQAECgYICgAAAA==.Vanillacream:BAAANQADCgMIAwAAAA==.Vayth:BAAANQADCggICAAAAA==.',
Ve='Veilthorn:BAAANQADCgYJCwAAAA==.Velinieron:BAAANQAECgYICAAAAA==.Velithiri:BAAANQAECgQJDgAAAA==.Vellash:BAAANQADCgEIAQAAAA==.',
Vi='Vilencia:BAAANQABCgUICQAAAA==.Vince:BAAANQADCgUJBgAAAA==.Vinny:BAAANQABCgIIAgAAAA==.',
Vo='Vonulter:BAAANQAECgQJBwAAAA==.',
Vy='Vylon:BAAANQAECgUICAAAAA==.Vynlandis:BAAANQAECgEIAQAAAA==.Vyrel:BAAANQADCgYICgAAAA==.',
['Vê']='Vêga:BAAANQAECgcIBwABNQAECgkJFwAMAC0SAA==.',
Wa='Warbezerker:BAAANQADCgcIBwAAAA==.',
We='Weenbean:BAAANQAECgYICAAAAA==.',
Wh='Whakoopa:BAAANQAECgQIBAAAAA==.Whispertree:BAAANQAECgcJEgAAAA==.Whìspèr:BAAANQAECgIIAgAAAA==.',
Wi='Wilddonut:BAAANQADCgQJBAAAAA==.Wixypoo:BAAANQAECgEIAQAAAA==.',
Wo='Woodnzhood:BAAANQAECgIJAwAAAA==.',
Wr='Wrylah:BAAANQAECgYICwAAAA==.',
Wu='Wuxian:BAAANQADCgYIBgABNQAFFAMJBQANAHoRAA==.',
Wy='Wyyn:BAAANQADCggJIAAAAA==.',
Xa='Xanboi:BAAANQAECgYJDQAAAA==.',
Yi='Yikkle:BAAANQABCgIIAwAAAA==.',
Ys='Ysar:BAAANQAECgQJCAAAAA==.',
Yu='Yumzug:BAAANQADCgQIBAAAAA==.',
['Yô']='Yôshi:BAAANQAECggICAAAAA==.',
Ze='Zeebu:BAAANQAECgQIBQAAAA==.',
Zh='Zhilan:BAABNQAECoEaAAIUAAYK9gsfKQAwAQAUAAYK9gsfKQAwAQAAAA==.',
Zo='Zoda:BAAANQADCgQIBgAAAA==.Zoko:BAAANQAECgEIAQAAAA==.',
Zu='Zurgadhunter:BAAANQAECgYJEAAAAA==.Zuzuk:BAAANQADCgMIAwAAAA==.Zuzuki:BAAANQADCgQIBAAAAA==.',
['Zú']='Zúz:BAAANQAECgIIAgAAAA==.',
['Ða']='Ðalinor:BAAANQADCggICAAAAA==.',
['Ðe']='Ðemaea:BAAANQADCgUIAwAAAA==.',
['Ði']='Ðittø:BAAANQADCgIIAgABNQADCggJNgACAAAAAA==.',
['Øc']='Øctø:BAAANQABCgEIAQAAAA==.',
['Ør']='Øreø:BAABNQAECoEYAAIYAAgKChz7AwCPAgAYAAgKChz7AwCPAgAAAA==.',
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
