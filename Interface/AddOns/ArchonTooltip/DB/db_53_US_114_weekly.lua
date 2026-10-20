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

local lookup = {'Paladin-Holy','Monk-Mistweaver','Paladin-Retribution','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Warrior-Arms','Unknown-Unknown','Shaman-Restoration','DemonHunter-Devourer','Mage-Arcane','Monk-Windwalker','Mage-Frost','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Druid-Guardian','Priest-Shadow','Paladin-Protection','DemonHunter-Vengeance','Warrior-Fury','Evoker-Preservation','Druid-Balance','Priest-Holy','Shaman-Enhancement',}
local provider = {region='US',realm="Gul'dan",name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abartane:BAAANQAECgYIBgAAAA==.',
Al='Allaria:BAAANQAECgIIAwAAAA==.',
Ao='Aoemomma:BAAANQADCgUIBQAAAA==.',
Ap='Applebottom:BAAANQAECggICwAAAA==.',
Ar='Arabella:BAAANQADCgMIAwAAAA==.',
At='Atticon:BAAANQAECgcIDwABNQAECgoKLwABALkeAA==.',
Az='Azuuli:BAAANQAECgMJAwAAAA==.',
Bi='Bigbeefycake:BAAANQADCgEIAQAAAA==.Bigpriest:BAAANQADCgQIBAAAAA==.',
Bo='Bob:BAABNQAECn8ZAAICAAkKVhKBGAD3AQACAAkKVhKBGAD3AQAAAA==.Boome:BAAANQADCggIHQABNQAECgoKHAADAL8SAA==.',
Bu='Bu:BAAANQAECgYICAABNQAFFAcIFQAEAPMUAA==.Budleaf:BAAANQAECgIIAwAAAA==.Bunkley:BAAANQAECgUIEAAAAA==.Buttshark:BAAANQADCgUICQAAAA==.',
By='Byege:BAACNQAFFH8SAAMFAAcKVhuEDACoAQAFAAYKZBqEDACoAQAGAAIKPRYyCgCmAAA1AAQKfy4ABAUACgrWInocABMDAAUACQpPInocABMDAAYABwqZG/EOAAwCAAcAAQoAACktADwAAAAA.',
Ca='Casteil:BAAANQAECgMIAgAAAA==.',
Ce='Cerbrus:BAABNQAECn8aAAIIAAYKqRpsQwAbAQAIAAYKqRpsQwAbAQAAAA==.',
Ch='Champilon:BAAANQAECgEIAQAAAA==.Chaoticus:BAAANQAECgEIAgABNQAECgQICAAJAAAAAA==.Charmahnder:BAAANQADCgQIBAABNQAECgUIBgAJAAAAAA==.Chin:BAACNQAFFH8YAAIKAAYKDSK7AgDFAQAKAAYKDSK7AgDFAQA1AAQKfzEAAgoACgpaJT0FAJ0DAAoACgpaJT0FAJ0DAAAA.Chuckles:BAAANQAECgIIBAABNQAECgoKIgALAJkfAA==.',
Co='Coma:BAAANQAECgUIEQAAAA==.',
Cr='Crackrock:BAAANQAECgYICwAAAA==.Crunbard:BAAANQAECgcICgAAAA==.',
Cy='Cyanna:BAAANQABCgMIAwAAAA==.',
Da='Dalirus:BAAANQADCgMIAwABNQAECgoKHAADAL8SAA==.Darci:BAABNQAECn8VAAIMAAcKbx1UlABXAgAMAAcKbx1UlABXAgABNQABCgUIBQAJAAAAAA==.Dasbunk:BAAANQAECgQIEgAAAA==.',
De='Deadblue:BAABNQAECn8kAAIGAAcKFBT5AgAmAQAGAAcKFBT5AgAmAQAAAA==.Deathblows:BAABNQAECn8jAAINAAkKgBDCLgCiAQANAAkKgBDCLgCiAQAAAA==.',
Dk='Dkpitador:BAAANQAECgEJAwAAAA==.',
Dr='Druidmaster:BAAANQAECgQICQAAAA==.',
Du='Duch:BAAANQAECgUIDAAAAA==.Duntuskwime:BAAANQADCgcIBwAAAA==.',
El='Elementia:BAAANQAECgEIAQAAAA==.',
Ev='Evilynn:BAABNQAECn8eAAIOAAcKmg4PEwB3AQAOAAcKmg4PEwB3AQAAAA==.',
Ex='Extinctionus:BAAANQAECgQIBQAAAA==.',
Fa='Fahros:BAAANQADCgYIBgABNQAECgYIEQAJAAAAAA==.',
Fe='Feliciana:BAAANQAECgMIBgAAAA==.',
Fi='Fia:BAAANQAECgYIDAAAAA==.',
Fo='Fondra:BAAANQAECggIAgAAAA==.',
Fu='Fulldps:BAAANQADCgEIAQAAAA==.Funstun:BAABNQAECn8fAAMPAAoK+wbaFwAJAQAPAAoK+wbaFwAJAQAQAAEK+gbEUQAzAAAAAA==.',
Go='Gokujang:BAAANQAECgQICwAAAA==.Gonjah:BAAANQADCgQIBAAAAA==.Gormok:BAAANQAECgMIAwAAAA==.',
Gr='Greendot:BAAANQAFFAIIAgAAAQ==.Greyarrow:BAAANQADCgQIBAAAAA==.',
Gu='Gulvid:BAACNQAFFH8YAAMFAAcK/xDcBAAnAgAFAAcK/xDcBAAnAgAGAAIKbQ3GDwCVAAA1AAQKfzkABAUACgobI8wKAP0BAAUACgoLI8wKAP0BAAYABAo4HNwkAEwBAAcAAQq6IJIMAGUAAAAA.',
Ha='Hairypennies:BAAANQADCgYJCQAAAA==.Haluak:BAABNQAECn8wAAIRAAoKFRmSNACmAgARAAoKFRmSNACmAgAAAA==.',
Ho='Houndtamer:BAABNQAECn8cAAISAAcKyw7jNABTAQASAAcKyw7jNABTAQAAAA==.',
Hu='Hukkhan:BAAANQAECggICAAAAA==.',
Ig='Igotthunder:BAAANQADCgUIBQAAAA==.',
In='Ineedahpet:BAAANQAECgMIBgABNQAECgQICAAJAAAAAA==.',
Is='Isomniac:BAAANQAECgQICAAAAA==.',
It='Itshela:BAACNQAFFH8KAAMTAAQKGBulEQDwAAATAAMKGBulEQDwAAAUAAEKAABMJwBdAAA1AAQKfyMAAxMACQpGIvseANECABMACQpGIvseANECABQABAodC2iMANAAAAAA.',
Ja='Jayrad:BAABNQAECn8UAAIHAAcKnwrVDACQAQAHAAcKnwrVDACQAQAAAA==.',
Je='Jellybeanz:BAAANQAECgEIBwAAAA==.',
Jo='Johnnyrage:BAABNQAECn8cAAMVAAkKOxejEAAeAgAVAAkKOxejEAAeAgAIAAkK8gvqngDPAQAAAA==.Jordybear:BAACNQAFFH8FAAIWAAMKlQisBgCVAAAWAAMKlQisBgCVAAA1AAQKfxUAAhYACQrAEQ0PABoBABYACQrAEQ0PABoBAAAA.',
Ka='Kaiige:BAAANQAECgEIAQAAAA==.Kairos:BAABNQAECn8nAAMDAAoKXgvSvACjAQADAAcKwRDSvACjAQABAAkKjQZmNAATAQAAAA==.',
Ke='Kenshinth:BAABNQAECn8XAAIXAAcK9hH9LgCsAQAXAAcK9hH9LgCsAQAAAA==.Ketamin:BAAANQAECgQIBAAAAA==.',
Ki='Kiltro:BAABNQAECn8eAAMTAAcK1g2JIgDeAAATAAcK1g2JIgDeAAAEAAIKowOJbQArAAAAAA==.Kimchichi:BAAANQAECgQIBgAAAA==.',
Ko='Kogorko:BAAANQAECgEIAQABNQAECgUIBgAJAAAAAA==.',
Ku='Kualoloa:BAAANQAECgEIAgAAAA==.',
La='Lapaladin:BAAANQAECgYIEQAAAA==.Latoya:BAAANQADCgcIDQAAAA==.',
Le='Lemontea:BAABNQAECn8nAAICAAgKSh6iDQCqAgACAAgKSh6iDQCqAgABNQAFFAIIAgAJAAAAAA==.Lexuus:BAAANQAECgEIAQABNQAECgMIAgAJAAAAAA==.',
Li='Lilyana:BAAANQADCgUIDQAAAA==.Limpairrow:BAAANQAECggIDAAAAA==.Litharidk:BAAANQAECgIIAgAAAA==.Lizzyheals:BAAANQAECgEIAQAAAA==.',
Lo='Lookaway:BAAANQADCgUIBQAAAA==.Loxyblue:BAAANQAECgQICgAAAA==.',
Lu='Luckyxpain:BAABNQAECn8cAAMDAAoKvxKyNgBdAQADAAoKvxKyNgBdAQAYAAYKDwyYPAAOAQAAAA==.',
Ly='Lykos:BAAANQAECgQICQAAAA==.',
Ma='Makok:BAABNQAECn8aAAIZAAcKTBVfDQDqAQAZAAcKTBVfDQDqAQAAAA==.Manguu:BAAANQAECgQIBQAAAA==.',
Me='Melancholic:BAABNQAECn8fAAIaAAgKwB8oAgDJAQAaAAgKwB8oAgDJAQAAAA==.',
Mi='Milkingfist:BAABNQAECn8gAAICAAcK0g/vDQD4AAACAAcK0g/vDQD4AAAAAA==.Milkingman:BAAANQAECgQJCAAAAA==.Mirie:BAAANQABCgQIBAAAAA==.Misshell:BAAANQAECgEIAQAAAA==.',
Mm='Mmnmjomg:BAAANQADCggICAAAAA==.',
Mo='Mooshmoo:BAAANQABCgIIAgAAAA==.Moundofvenus:BAABNQAECn8iAAILAAoKmR99EADtAgALAAoKmR99EADtAgAAAA==.',
Mu='Murog:BAAANQADCgcJFQAAAA==.',
Ne='Nephlok:BAABNQAECn8fAAIFAAcKqxABVwDUAAAFAAcKqxABVwDUAAAAAA==.Nesrin:BAAANQADCgYIBgAAAA==.',
Ni='Nightdisco:BAAANQAECgQICgAAAA==.',
No='Noctyra:BAAANQADCggICAABNQADCggICAAJAAAAAA==.',
Ny='Nyssaenna:BAAANQADCgMIAwAAAA==.',
['Nô']='Nôçtïs:BAAANQAECggIAQAAAA==.',
Og='Ogtart:BAAANQADCgYIBgAAAA==.Ogthunder:BAAANQADCgYIBgAAAA==.',
Pi='Pips:BAABNQAECn8XAAINAAkK4BcyHABZAgANAAkK4BcyHABZAgAAAA==.',
Pu='Pureformance:BAACNQAFFH8dAAIKAAcKvSA7AQAwAgAKAAcKvSA7AQAwAgA1AAQKfy0AAgoACgp6JMQAAOEDAAoACgp6JMQAAOEDAAAA.',
Qu='Quiikshot:BAABNQAECn8UAAISAAkK4QJf/AALAQASAAkK4QJf/AALAQAAAA==.',
Ri='Rivel:BAAANQADCgcIBwABNQAECgUJBQAJAAAAAA==.Rivoric:BAAANQAECgUJBQAAAA==.Rivotril:BAAANQADCgMIBAAAAA==.',
Ro='Rocks:BAAANQAECgYIBwABNQAFFAcIGgAbAPIhAA==.Ronni:BAAANQADCggIEAABNQAECgUIBgAJAAAAAA==.',
Sa='Santeria:BAAANQADCggIDAAAAA==.',
Sc='Schango:BAABNQAECn8zAAIFAAoK1Qn8HAB7AQAFAAoK1Qn8HAB7AQAAAA==.Schwiifty:BAAANQAECgEIAQAAAA==.',
Se='Serica:BAAANQAECggIBgAAAA==.',
Sh='Shadowmander:BAAANQADCgMIAwAAAA==.Shakazoom:BAABNQAECn8hAAMcAAoKww98QQDyAQAcAAoKww98QQDyAQAWAAEK+RPUOQAyAAAAAA==.Shammyhaggar:BAAANQADCggIDQAAAA==.Shaun:BAABNQAECn8ZAAIdAAkKqCHqJwDKAgAdAAkKqCHqJwDKAgAAAA==.Sheffers:BAAANQAECgYICQAAAA==.Shepard:BAACNQAFFH8gAAIBAAcKnSMvAwBqAgABAAcKnSMvAwBqAgA1AAQKfycAAgEACgrKJpMAAPADAAEACgrKJpMAAPADAAAA.Shmorc:BAABNQAECn8eAAMKAAcKHgtvQQDmAAAKAAcKHgtvQQDmAAARAAEKAAAcXwEaAAAAAA==.Shortcandy:BAAANQADCgQIBQAAAA==.Shukaku:BAAANQAECgUIBQAAAA==.',
Sk='Skitz:BAAANQAECgQIBgAAAA==.',
Sl='Slashee:BAAANQADCgIIAgAAAA==.Sleepielight:BAAANQAECgYICQAAAA==.',
So='Somberwish:BAAANQADCggICAAAAA==.Sortie:BAABNQAECn8gAAIBAAcK3xJxHQB2AQABAAcK3xJxHQB2AQAAAA==.',
Sp='Spoonz:BAAANQAECgQIBgAAAA==.',
Su='Succinic:BAAANQADCgYICgAAAA==.Superdoom:BAAANQAECgUICAAAAA==.',
Ta='Tauridin:BAAANQAECgEIAQAAAA==.',
Te='Tegridy:BAAANQAECgEIBQAAAA==.',
Th='Thegoldensün:BAABNQAECn82AAMeAAkKOxZqEwAyAgAeAAgKoBdqEwAyAgAKAAgKdRLxcAC5AQAAAA==.Thunderrod:BAABNQAECn8aAAISAAgKlBEcSQAhAQASAAgKlBEcSQAhAQAAAA==.',
To='Tolally:BAACNQAFFH8LAAIEAAMKMyHwBADpAAAEAAMKMyHwBADpAAA1AAQKfy8AAwQACgrZIlEJAFQDAAQACgrZIlEJAFQDABMAAwppIT2CABUBAAAA.Tomes:BAAANQADCgQIBAAAAA==.',
Tr='Traessa:BAAANQAECgMIAwABNQAECgUIBgAJAAAAAA==.',
Tw='Twogg:BAAANQAECgcICAAAAA==.',
Ul='Ulfr:BAAANQAECgMIBQAAAA==.Ulfri:BAAANQAECgQIBAAAAA==.Ulvrik:BAAANQADCgIIAgAAAA==.',
Un='Unknownmage:BAAANQABCgQIBAAAAA==.Unpaidintern:BAABNQAECn8mAAIRAAoKixu3GwAjAwARAAoKixu3GwAjAwAAAA==.',
Va='Vaedroxz:BAAANQAECgEIAQAAAA==.Vaynard:BAABNQAECn8WAAQaAAcKkwsoGwD1AAAaAAQKHREoGwD1AAAIAAcKDwmyYwDRAAAVAAEK3RXVHgBGAAAAAA==.',
Ve='Veyá:BAAANQADCggICAAAAA==.',
Vr='Vrandya:BAAANQAECgIIAgAAAA==.',
Wa='Walkthrew:BAACNQAFFH8XAAMGAAYKLxv8AQCuAAAFAAUKeRxNDACqAQAGAAIKfxj8AQCuAAA1AAQKfywAAwUACgroIYYWAJsBAAUACArgI4YWAJsBAAYABQqiF3whAGUBAAAA.Warroir:BAAANQAECggIEQAAAA==.Warrsteak:BAAANQABCgQIBAAAAA==.',
Wi='Wishing:BAAANQADCgUIBQAAAA==.',
Wl='Wlkmob:BAAANQAECgQICAAAAA==.',
Wu='Wunderwazard:BAABNQAECn8XAAIOAAoKcRpOBwB9AgAOAAoKcRpOBwB9AgAAAA==.',
Ya='Yadead:BAABNQAECn8hAAIIAAkKPg68JgBrAQAIAAkKPg68JgBrAQAAAA==.',
Yo='Yourname:BAAANQABCgQIBAAAAA==.',
Za='Zaelinor:BAAANQADCggICAABNQAFFAUIDQANACYVAA==.Zaylen:BAAANQAECggIDgABNQAFFAUIDQANACYVAA==.',
Ze='Zendjin:BAAANQADCgMIAwAAAA==.Zerog:BAAANQAECgUIDgAAAA==.',
Zi='Zistormstout:BAABNQAECn8cAAIRAAcKiA26JgAhAQARAAcKiA26JgAhAQAAAA==.',
Zu='Zurmortic:BAABNQAECn8iAAMFAAgKkgympwCEAQAFAAgKkgympwCEAQAGAAEKIQJFhwAfAAAAAA==.',
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
