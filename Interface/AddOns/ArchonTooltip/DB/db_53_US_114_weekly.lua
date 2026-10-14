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

local lookup = {'Paladin-Holy','Monk-Mistweaver','Paladin-Retribution','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Warrior-Arms','Unknown-Unknown','Shaman-Restoration','DemonHunter-Devourer','Mage-Arcane','Monk-Windwalker','Shaman-Elemental','Mage-Frost','Rogue-Assassination','DeathKnight-Unholy','DeathKnight-Blood','Paladin-Protection','DemonHunter-Vengeance','Warrior-Fury','Evoker-Preservation','Druid-Balance','Druid-Guardian','Priest-Holy','Shaman-Enhancement',}
local provider = {region='US',realm="Gul'dan",name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abartane:BAAANQADCgcICwAAAA==.',
Al='Allaria:BAAANQAECgEIAQAAAA==.',
Ao='Aoemomma:BAAANQADCgIIAgAAAA==.',
Ap='Applebottom:BAAANQAECggICwAAAA==.',
Ar='Arabella:BAAANQADCgMIAwAAAA==.',
At='Atticon:BAAANQAECgUICQABNQAECgkJIgABACkaAA==.',
Az='Azuuli:BAAANQAECgMJAwAAAA==.',
Bi='Bigbeefycake:BAAANQADCgEIAQAAAA==.',
Bl='Blackthunder:BAAANQADCggIHgAAAA==.',
Bo='Bob:BAABNQAECn8ZAAICAAkKVhI2GAD3AQACAAkKVhI2GAD3AQAAAA==.Boome:BAAANQADCggIHQABNQAECgkJFgADAGwOAA==.',
Bu='Bu:BAAANQAECgYICAABNQAFFAYIEAAEANUSAA==.Budleaf:BAAANQAECgIIAgAAAA==.Bunkley:BAAANQAECgQICQAAAA==.Buttshark:BAAANQADCgUICQAAAA==.',
By='Byege:BAACNQAFFH8RAAMFAAYKgB3NCwCzAQAFAAUK9hzNCwCzAQAGAAIKPRb7CQCpAAA1AAQKfy0ABAUACQqPI8IbABQDAAUACAoRI8IbABQDAAYABwqZG9wOAAwCAAcAAQoAALksADwAAAAA.',
Ca='Casteil:BAAANQADCggIDgAAAA==.',
Ce='Cerbrus:BAABNQAECn8UAAIIAAYKqRemogDBAQAIAAYKqRemogDBAQAAAA==.',
Ch='Champilon:BAAANQADCgQIBAAAAA==.Chaoticus:BAAANQADCggIDgABNQAECgQIBwAJAAAAAA==.Charmahnder:BAAANQADCgQIBAABNQAECgUICQAJAAAAAA==.Chin:BAACNQAFFH8TAAIKAAUKBSJFBwDhAQAKAAUKBSJFBwDhAQA1AAQKfy0AAgoACQq6JRcFAJ4DAAoACQq6JRcFAJ4DAAAA.Chuckles:BAAANQAECgIIBAABNQAECgkJHwALALQeAA==.',
Co='Coma:BAAANQAECgUIDgAAAA==.',
Cr='Crackrock:BAAANQAECgUIBQAAAA==.Crunbard:BAAANQAECgYICQAAAA==.',
Cy='Cyanna:BAAANQABCgMIAwAAAA==.',
Da='Dalirus:BAAANQADCgMIAwABNQAECgkJFgADAGwOAA==.Darci:BAABNQAECn8VAAIMAAcKbx3ekgBaAgAMAAcKbx3ekgBaAgABNQABCgUIBQAJAAAAAA==.Dasbunk:BAAANQAECgQIDwAAAA==.',
De='Deadblue:BAABNQAECn8dAAIGAAcKsA+kFADIAQAGAAcKsA+kFADIAQAAAA==.Deathblows:BAABNQAECn8cAAINAAcKghVBLgCiAQANAAcKghVBLgCiAQAAAA==.',
Dk='Dkpitador:BAAANQAECgEJAQAAAA==.',
Dr='Druidmaster:BAAANQAECgQICQAAAA==.',
Du='Duch:BAAANQAECgUICAAAAA==.Duntuskwime:BAAANQADCgcIBwAAAA==.',
El='Elementia:BAAANQADCggIDAAAAA==.Ellie:BAABNQAECn8jAAIOAAkKdh5iGwAjAwAOAAkKdh5iGwAjAwAAAA==.',
Ev='Evilynn:BAABNQAECn8ZAAIPAAcKmg7ZEgB3AQAPAAcKmg7ZEgB3AQAAAA==.',
Ex='Extinctionus:BAAANQAECgQIBAAAAA==.',
Fa='Fahros:BAAANQADCgYIBgABNQAECgYIDgAJAAAAAA==.',
Fe='Feliciana:BAAANQAECgEIAQAAAA==.',
Fi='Fia:BAAANQAECgUJCgAAAA==.',
Fo='Fondra:BAAANQAECggIAgAAAA==.',
Fu='Fulldps:BAAANQADCgEIAQAAAA==.Funstun:BAABNQAECn8XAAIQAAkKBgYQUQBzAQAQAAkKBgYQUQBzAQAAAA==.',
Go='Gokujang:BAAANQAECgQIBwAAAA==.Gonjah:BAAANQADCgQIBAAAAA==.Gormok:BAAANQAECgMIAwAAAA==.',
Gr='Greendot:BAAANQAFFAEIAQAAAQ==.Greyarrow:BAAANQADCgQIBAAAAA==.',
Gu='Gulvid:BAACNQAFFH8YAAMFAAcK/xAbBAA6AgAFAAcK/xAbBAA6AgAGAAIKbQ2EDwCYAAA1AAQKfzMAAwUACQoAI3AVADMDAAUACQrtInAVADMDAAYABAo4HKIkAEwBAAAA.',
Ha='Hairypennies:BAAANQADCgYJCQAAAA==.Haluak:BAABNQAECn8sAAIOAAgKHB28MwCnAgAOAAgKHB28MwCnAgAAAA==.',
Ho='Houndtamer:BAAANQAECgYIEgAAAA==.',
Hu='Hukkhan:BAAANQAECggICAAAAA==.',
Ig='Igotthunder:BAAANQADCgUIBQAAAA==.',
In='Ineedahpet:BAAANQAECgMIBgABNQAECgQIBwAJAAAAAA==.',
Is='Isomniac:BAAANQAECgQICAAAAA==.',
It='Itshela:BAACNQAFFH8KAAMRAAQKGBtqEQDwAAARAAMKGBtqEQDwAAASAAEKAAC8JgBdAAA1AAQKfyMAAxEACQpGIrIeANECABEACQpGIrIeANECABIABAodCzaLANAAAAAA.',
Ja='Jayrad:BAAANQAECgYIDAAAAA==.',
Je='Jellybeanz:BAAANQADCggIJQAAAA==.',
Jo='Johnnyrage:BAAANQAECggIEwAAAA==.Jordybear:BAAANQAFFAIIAgAAAA==.',
Ka='Kaiige:BAAANQADCggIEAAAAA==.Kairos:BAABNQAECn8hAAMDAAgKSA6zuQCkAQADAAcKwRCzuQCkAQABAAYKTgTUvgD6AAAAAA==.',
Ke='Kenshinth:BAAANQAECgYIDgAAAA==.Ketamin:BAAANQAECgQIBAAAAA==.',
Ki='Kiltro:BAABNQAECn8WAAIRAAUKlhD+gQASAQARAAUKlhD+gQASAQAAAA==.Kimchichi:BAAANQAECgIIAgAAAA==.',
Ko='Kogorko:BAAANQAECgEIAQABNQAECgUICQAJAAAAAA==.',
La='Lapaladin:BAAANQAECgQICQAAAA==.Latoya:BAAANQADCgcJDQAAAA==.',
Le='Lemontea:BAABNQAECn8nAAICAAgKSh5dDQCqAgACAAgKSh5dDQCqAgABNQAFFAEIAQAJAAAAAA==.Lexuus:BAAANQADCgUICAABNQADCggIDgAJAAAAAA==.',
Li='Lilyana:BAAANQADCgUIDQAAAA==.Limpairrow:BAAANQAECggICQAAAA==.Litharidk:BAAANQAECgIIAgAAAA==.Lizzyheals:BAAANQABCggIDQAAAA==.',
Lo='Lookaway:BAAANQADCgUIBQAAAA==.Loxyblue:BAAANQAECgQIBgAAAA==.',
Lu='Luckyxpain:BAABNQAECn8WAAMDAAkKbA6hkAD+AQADAAkKbA6hkAD+AQATAAYKDwzROwAOAQAAAA==.',
Ly='Lykos:BAAANQAECgQIBQAAAA==.',
Ma='Makok:BAABNQAECn8aAAIUAAcKTBU1DQDpAQAUAAcKTBU1DQDpAQAAAA==.Manguu:BAAANQAECgEIAQAAAA==.',
Me='Melancholic:BAABNQAECn8YAAIVAAcK6SGzBgCXAgAVAAcK6SGzBgCXAgAAAA==.',
Mi='Milkingfist:BAABNQAECn8bAAICAAcKvA4TIwBlAQACAAcKvA4TIwBlAQAAAA==.Milkingman:BAAANQAECgQJBgAAAA==.Mirie:BAAANQABCgQIBAAAAA==.Misshell:BAAANQAECgEIAQAAAA==.',
Mm='Mmnmjomg:BAAANQADCgUIBQAAAA==.',
Mo='Mooshmoo:BAAANQABCgIIAgAAAA==.Moundofvenus:BAABNQAECn8fAAILAAkKtB5FEADtAgALAAkKtB5FEADtAgAAAA==.',
Mu='Murog:BAAANQADCgcJFQAAAA==.',
Ne='Nephlok:BAABNQAECn8ZAAIFAAYKdBJyoQCOAQAFAAYKdBJyoQCOAQAAAA==.Nesrin:BAAANQADCgYIBgAAAA==.',
Ni='Nightdisco:BAAANQAECgQIBgAAAA==.',
No='Noctyra:BAAANQADCggICAABNQADCggICAAJAAAAAA==.',
Ny='Nyssaenna:BAAANQADCgMIAwAAAA==.',
['Nô']='Nôçtïs:BAAANQAECggIAQAAAA==.',
Og='Ogtart:BAAANQADCgYIBgAAAA==.Ogthunder:BAAANQADCgYIBgAAAA==.',
Pi='Pips:BAABNQAECn8XAAINAAkK4BfUGwBZAgANAAkK4BfUGwBZAgAAAA==.',
Pu='Pureformance:BAACNQAFFH8XAAIKAAYKQR+kAwBQAgAKAAYKQR+kAwBQAgA1AAQKfywAAgoACQqqJrwAAOEDAAoACQqqJrwAAOEDAAAA.',
Qu='Quiikshot:BAAANQAECggIEgAAAA==.',
Ri='Rivel:BAAANQADCgcIBwABNQAECgUJBQAJAAAAAA==.Rivoric:BAAANQAECgUJBQAAAA==.Rivotril:BAAANQADCgMIBAAAAA==.',
Ro='Rocks:BAAANQAECgQIBAABNQAFFAcIGQAWAPIhAA==.Ronni:BAAANQADCgYIDQABNQAECgUICQAJAAAAAA==.',
Sc='Schango:BAABNQAECn8pAAIFAAgKgwrllwClAQAFAAgKgwrllwClAQAAAA==.Schwiifty:BAAANQADCgQIBAAAAA==.',
Se='Serica:BAAANQAECggIBgAAAA==.',
Sh='Shakazoom:BAABNQAECn8bAAMXAAgKCxDpQADyAQAXAAgKCxDpQADyAQAYAAEK+RMAAAAAAAAAAA==.Shammyhaggar:BAAANQADCgcIDQAAAA==.Shaun:BAABNQAECn8ZAAIZAAkKqCE1JwDLAgAZAAkKqCE1JwDLAgAAAA==.Sheffers:BAAANQAECgUIBwAAAA==.Shepard:BAACNQAFFH8aAAIBAAYKCyQSAwBqAgABAAYKCyQSAwBqAgA1AAQKfyQAAgEACQriJo0AAPEDAAEACQriJo0AAPEDAAAA.Shmorc:BAABNQAECn8ZAAMKAAcKpAkDngA3AQAKAAcKpAkDngA3AQAOAAEKAAA+WgEaAAAAAA==.Shortcandy:BAAANQADCgQIBQAAAA==.',
Sk='Skitz:BAAANQAECgQIBAAAAA==.',
Sl='Slashee:BAAANQADCgIIAgAAAA==.Sleepielight:BAAANQAECgQIBAAAAA==.',
So='Somberwish:BAAANQADCggICAAAAA==.Sortie:BAABNQAECn8ZAAIBAAcKhg+DfgCaAQABAAcKhg+DfgCaAQAAAA==.',
Sp='Spoonz:BAAANQAECgQIBQAAAA==.',
Su='Succinic:BAAANQADCgYICgAAAA==.Superdoom:BAAANQAECgQIBgAAAA==.',
Ta='Tauridin:BAAANQABCgEIAQAAAA==.',
Te='Tegridy:BAAANQADCgUICQAAAA==.',
Th='Thegoldensün:BAABNQAECn82AAMaAAkKOxYzEwAyAgAaAAgKoBczEwAyAgAKAAgKdRKdbwC5AQAAAA==.Thunderrod:BAAANQAECgYIEgAAAA==.',
To='Tolally:BAACNQAFFH8IAAIEAAMKMyEgCwAoAQAEAAMKMyEgCwAoAQA1AAQKfywAAwQACQoAJQYJAFUDAAQACQoAJQYJAFUDABEAAwppIUCBABUBAAAA.Tomes:BAAANQADCgQIBAAAAA==.',
Tw='Twogg:BAAANQAECgYIBgAAAA==.',
Ul='Ulfr:BAAANQAECgMIBQAAAA==.Ulfri:BAAANQAECgQIBAAAAA==.Ulvrik:BAAANQADCgIIAgAAAA==.',
Un='Unknownmage:BAAANQABCgQIBAAAAA==.',
Va='Vaynard:BAAANQAECgUIDAAAAA==.',
Ve='Veyá:BAAANQADCggICAAAAA==.',
Wa='Walkthrew:BAACNQAFFH8UAAMFAAYK9Bi7CwC0AQAFAAUKgBm7CwC0AQAGAAIKfxh8CgCnAAA1AAQKfygAAwUACQoZIm86AKECAAUABwqIJG86AKECAAYABQqiF0YhAGUBAAAA.Warroir:BAAANQAECggIEAAAAA==.Warrsteak:BAAANQABCgQIBAAAAA==.',
Wi='Wishing:BAAANQADCgUIBQAAAA==.',
Wl='Wlkmob:BAAANQAECgQIBgAAAA==.',
Wu='Wunderwazard:BAAANQAECggIEQAAAA==.',
Ya='Yadead:BAABNQAECn8YAAIIAAgKeg5emwDTAQAIAAgKeg5emwDTAQAAAA==.',
Yo='Yourname:BAAANQABCgQIBAAAAA==.',
Za='Zaelinor:BAAANQADCggICAABNQAFFAUIDQANACYVAA==.Zaylen:BAAANQAECgQIBwABNQAFFAUIDQANACYVAA==.',
Ze='Zendjin:BAAANQADCgMIAwAAAA==.Zerog:BAAANQAECgQIDgAAAA==.',
Zi='Zistormstout:BAAANQAECgYIEgAAAA==.',
Zu='Zurmortic:BAABNQAECn8hAAMFAAcKIw1wpQCEAQAFAAcKIw1wpQCEAQAGAAEKIQKPhgAfAAAAAA==.',
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
