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

local lookup = {'Monk-Mistweaver','Unknown-Unknown','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Shaman-Restoration','DemonHunter-Devourer','Monk-Windwalker','Shaman-Elemental','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Paladin-Retribution','Paladin-Holy','Evoker-Preservation','Priest-Holy','Shaman-Enhancement',}
local provider = {region='US',realm="Gul'dan",name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abartane:BAAANQADCgcICwAAAA==.',
Al='Allaria:BAAANQAECgEIAQAAAA==.',
Ao='Aoemomma:BAAANQADCgIIAgAAAA==.',
Ap='Applebottom:BAAANQAECggICAAAAA==.',
Ar='Arabella:BAAANQADCgMIAwAAAA==.',
Az='Azuuli:BAAANQAECgMJAwAAAA==.',
Bi='Bigbeefycake:BAAANQADCgEIAQAAAA==.',
Bl='Blackthunder:BAAANQADCggIFgAAAA==.',
Bo='Bob:BAABNQAECoEZAAIBAAkKVhL6FAD/AQABAAkKVhL6FAD/AQAAAA==.Boome:BAAANQADCggIHQABNQAECgYIDQACAAAAAA==.',
Bu='Bu:BAAANQAECgYICAABNQAFFAYIDgADAK8SAA==.Budleaf:BAAANQAECgIIAgAAAA==.Bunkley:BAAANQAECgQIBAAAAA==.Buttshark:BAAANQADCgUICQAAAA==.',
By='Byege:BAACNQAFFIEMAAMEAAYKnRNXCQCnAQAEAAUK4BFXCQCnAQAFAAIKwxRaCwCkAAA1AAQKgScABAQACQoGI98XABQDAAQACApwIt8XABQDAAUABwp1HMINABACAAYAAQpKEu8nAD4AAAAA.',
Ca='Casteil:BAAANQADCggIDgAAAA==.',
Ce='Cerbrus:BAAANQAECggIDwAAAA==.',
Ch='Champilon:BAAANQADCgQIBAAAAA==.Chaoticus:BAAANQADCggIDgABNQAECgQIBwACAAAAAA==.Charmahnder:BAAANQADCgQJBAABNQAECgUICQACAAAAAA==.Chin:BAACNQAFFIEOAAIHAAUKBSIqBQD5AQAHAAUKBSIqBQD5AQA1AAQKgSkAAgcACQq6JWQDAKUDAAcACQq6JWQDAKUDAAAA.Chuckles:BAAANQAECgIIBAABNQAECgkJGQAIADkdAA==.',
Co='Coma:BAAANQAECgUIDgAAAA==.',
Cr='Crackrock:BAAANQADCgcICAAAAA==.Crunbard:BAAANQAECgUICAAAAA==.',
Cy='Cyanna:BAAANQABCgMIAwAAAA==.',
Da='Dalirus:BAAANQADCgMIAwABNQAECgYIDQACAAAAAA==.Darci:BAAANQAECgYIEAAAAA==.Dasbunk:BAAANQAECgQIDgAAAA==.',
De='Deadblue:BAAANQAECgUIEQAAAA==.Deathblows:BAABNQAECoEVAAIJAAcKAhPbKQCcAQAJAAcKAhPbKQCcAQAAAA==.',
Dk='Dkpitador:BAAANQAECgEJAQAAAA==.',
Dr='Druidmaster:BAAANQAECgQIBAAAAA==.',
Du='Duch:BAAANQAECgUICAAAAA==.Duntuskwime:BAAANQADCgEIAQAAAA==.',
El='Elementia:BAAANQADCggIDAAAAA==.Ellie:BAABNQAECoEbAAIKAAkKZR9CFgAuAwAKAAkKZR9CFgAuAwAAAA==.',
Ev='Evilynn:BAAANQAECgYIEAAAAA==.',
Ex='Extinctionus:BAAANQADCgQIBAAAAA==.',
Fa='Fahros:BAAANQADCgYIBgABNQAECgcIEAALAL8jAA==.',
Fe='Feliciana:BAAANQADCggIHAAAAA==.',
Fi='Fia:BAAANQAECgUJCgAAAA==.',
Fo='Fondra:BAAANQAECgYIAgAAAA==.',
Fu='Fulldps:BAAANQADCgEIAQAAAA==.Funstun:BAAANQAECggIEAAAAA==.',
Go='Gokujang:BAAANQAECgQIBwAAAA==.Gonjah:BAAANQADCgQIBAAAAA==.Gormok:BAAANQAECgIIAgAAAA==.',
Gr='Greyarrow:BAAANQADCgQIBAAAAA==.',
Gu='Gulvid:BAACNQAFFIESAAMEAAYK2w8TBwDNAQAEAAYKpA4TBwDNAQAFAAIKTgiRDwCQAAA1AAQKgTAAAwQACQoMI1UQAD0DAAQACQr9IlUQAD0DAAUABAo4HKYiAFABAAAA.',
Ha='Hairypennies:BAAANQADCgYJCQAAAA==.Haluak:BAABNQAECoElAAIKAAgKlxwULACqAgAKAAgKlxwULACqAgAAAA==.',
Ho='Houndtamer:BAAANQAECgYIDAAAAA==.',
Hu='Hukkhan:BAAANQAECggICAAAAA==.',
In='Ineedahpet:BAAANQAECgMIBgABNQAECgQIBwACAAAAAA==.',
Is='Isomniac:BAAANQAECgQICAAAAA==.',
It='Itshela:BAACNQAFFIEKAAMMAAQK/ByeDgDwAAAMAAMKGBueDgDwAAANAAEKpiLnIQBgAAA1AAQKgSMAAwwACQp+IvcYAN0CAAwACQp+IvcYAN0CAA0ABArQEMJ/ANQAAAAA.',
Ja='Jayrad:BAAANQAECgYICwAAAA==.',
Jo='Johnnyrage:BAAANQAECggIDgAAAA==.Jordybear:BAAANQAECgUIDgAAAA==.',
Ka='Kaiige:BAAANQADCggIEAAAAA==.Kairos:BAABNQAECoEZAAMOAAcKGg8P6wAMAQAOAAYKTBEP6wAMAQAPAAYKTgTaqgD/AAAAAA==.',
Ke='Kenshinth:BAAANQAECgYICQAAAA==.Ketamin:BAAANQAECgQIBAAAAA==.',
Ki='Kiltro:BAAANQAECgUIDwAAAA==.Kimchichi:BAAANQAECgIIAgAAAA==.',
Ko='Kogorko:BAAANQAECgEIAQABNQAECgUICQACAAAAAA==.',
La='Lapaladin:BAAANQAECgUIBQAAAA==.Latoya:BAAANQADCgcJDQAAAA==.',
Le='Lemontea:BAABNQAECoEnAAIBAAgKSh4FCwC5AgABAAgKSh4FCwC5AgAAAA==.Lexuus:BAAANQADCgUICAABNQADCggIDgACAAAAAA==.',
Li='Lilyana:BAAANQADCgUIDQAAAA==.Limpairrow:BAAANQAECgUICQAAAA==.Litharidk:BAAANQAECgIIAgAAAA==.Lizzyheals:BAAANQABCggIDQAAAA==.',
Lo='Lookaway:BAAANQADCgUIBQAAAA==.Loxyblue:BAAANQAECgUIBgAAAA==.',
Lu='Luckyxpain:BAAANQAECgYIDQAAAA==.',
Ly='Lykos:BAAANQAECgUIBAAAAA==.',
Ma='Makok:BAAANQAECgYIEAAAAA==.Manguu:BAAANQADCgIIAgAAAA==.',
Me='Melancholic:BAAANQAECgUIEgAAAA==.',
Mi='Milkingfist:BAAANQAECgYIEQAAAA==.Milkingman:BAAANQAECgQJBgAAAA==.Mirie:BAAANQABCgQIBAAAAA==.Misshell:BAAANQADCgEIAQAAAA==.',
Mm='Mmnmjomg:BAAANQADCgUIBQAAAA==.',
Mo='Mooshmoo:BAAANQABCgIIAgAAAA==.Moundofvenus:BAABNQAECoEZAAIIAAkKOR3ADgDuAgAIAAkKOR3ADgDuAgAAAA==.',
Mu='Murog:BAAANQADCgcJFQAAAA==.',
Ne='Nephlok:BAAANQAECgUIEQAAAA==.Nesrin:BAAANQADCgYIBgAAAA==.',
Ni='Nightdisco:BAAANQAECgUIBgAAAA==.',
No='Noctyra:BAAANQADCggICAABNQADCggICAACAAAAAA==.',
Ny='Nyssaenna:BAAANQADCgMIAwAAAA==.',
['Nô']='Nôçtïs:BAAANQAECggIAQAAAA==.',
Og='Ogtart:BAAANQADCgYIBgAAAA==.Ogthunder:BAAANQADCgYIBgAAAA==.',
Pi='Pips:BAABNQAECoEXAAIJAAkKwRngFgBtAgAJAAkKwRngFgBtAgAAAA==.',
Pu='Pureformance:BAACNQAFFIERAAIHAAUKKCP+BAD+AQAHAAUKKCP+BAD+AQA1AAQKgSkAAgcACQqqJmoAAOQDAAcACQqqJmoAAOQDAAAA.',
Qu='Quiikshot:BAAANQAECggIDQAAAA==.',
Ri='Rivel:BAAANQADCgcIBwABNQAECgUJBQACAAAAAA==.Rivoric:BAAANQAECgUJBQAAAA==.Rivotril:BAAANQADCgMIBAAAAA==.',
Ro='Rocks:BAAANQAECgQIBAABNQAFFAcIGAAQAPIhAA==.Ronni:BAAANQADCgYIDQABNQAECgUICQACAAAAAA==.',
Sc='Schango:BAABNQAECoEhAAIEAAgKdwlWigCeAQAEAAgKdwlWigCeAQAAAA==.Schwiifty:BAAANQADCgQIBAAAAA==.',
Se='Serica:BAAANQAECggIBgAAAA==.',
Sh='Shakazoom:BAAANQAECggIEgAAAA==.Shammyhaggar:BAAANQADCgcIBwAAAA==.Shaun:BAABNQAECoEZAAIRAAkKqCHPHwDVAgARAAkKqCHPHwDVAgAAAA==.Sheffers:BAAANQAECgQIBQAAAA==.Shepard:BAACNQAFFIEVAAIPAAYKJSM2AgBuAgAPAAYKJSM2AgBuAgA1AAQKgSIAAg8ACQriJlQAAPgDAA8ACQriJlQAAPgDAAAA.Shmorc:BAAANQAECgYIEAAAAA==.Shortcandy:BAAANQADCgQIBQAAAA==.',
Sk='Skitz:BAAANQAECgQIBAAAAA==.',
Sl='Slashee:BAAANQADCgIIAgAAAA==.Sleepielight:BAAANQADCgYIBQAAAA==.',
So='Somberwish:BAAANQADCggICAAAAA==.Sortie:BAAANQAECgUIEQAAAA==.',
Sp='Spoonz:BAAANQAECgIIAQAAAA==.',
Su='Succinic:BAAANQADCgYICgAAAA==.Superdoom:BAAANQAECgEIAgAAAA==.',
Ta='Tauridin:BAAANQABCgEIAQAAAA==.',
Te='Tegridy:BAAANQADCgUICQAAAA==.',
Th='Thegoldensün:BAABNQAECoE2AAMSAAkK2hYXDwBeAgASAAgK+hcXDwBeAgAHAAgKdRIwYgC4AQAAAA==.Thunderrod:BAAANQAECgQIDAAAAA==.',
To='Tolally:BAACNQAFFIEFAAIDAAMKxCA6BwA3AQADAAMKxCA6BwA3AQA1AAQKgSkAAwMACQrNJLAFAHUDAAMACQrNJLAFAHUDAAwAAwppIUd2ABcBAAAA.Tomes:BAAANQADCgQIBAAAAA==.',
Tw='Twogg:BAAANQADCgcIDwAAAA==.',
Ul='Ulfr:BAAANQAECgMIBQAAAA==.Ulfri:BAAANQADCgcICwAAAA==.Ulvrik:BAAANQADCgIIAgAAAA==.',
Un='Unknownmage:BAAANQABCgQIBAAAAA==.',
Va='Vaynard:BAAANQAECgQIBwAAAA==.',
Ve='Veyá:BAAANQADCggICAAAAA==.',
Wa='Walkthrew:BAACNQAFFIEOAAMEAAUKXhlOEABOAQAEAAQK4hlOEABOAQAFAAEKTxelFQBVAAA1AAQKgSYAAwQACQo9Ih0vALACAAQABwrgIx0vALACAAUABQqiGn4fAGoBAAAA.Warroir:BAAANQAECggICAAAAA==.Warrsteak:BAAANQABCgQIBAAAAA==.',
Wi='Wishing:BAAANQADCgUIBQAAAA==.',
Wl='Wlkmob:BAAANQAECgQIBgAAAA==.',
Wu='Wunderwazard:BAAANQAECgYIDgAAAA==.',
Ya='Yadead:BAAANQAECgYIEAAAAA==.',
Yo='Yourname:BAAANQABCgQIBAAAAA==.',
Za='Zaelinor:BAAANQADCggICAABNQAFFAQIDAAJAMkUAA==.Zaylen:BAAANQAECgMIAwABNQAFFAQIDAAJAMkUAA==.',
Ze='Zendjin:BAAANQADCgMIAwAAAA==.Zerog:BAAANQAECgQICgAAAA==.',
Zi='Zistormstout:BAAANQAECgYIDAAAAA==.',
Zu='Zurmortic:BAABNQAECoEaAAMEAAcKNQjDpABbAQAEAAcKNQjDpABbAQAFAAEKIQIAgAAhAAAAAA==.',
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
