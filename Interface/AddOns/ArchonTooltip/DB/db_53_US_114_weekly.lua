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

local lookup = {'Hunter-BeastMastery','Paladin-Holy','Monk-Mistweaver','Paladin-Retribution','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Warrior-Arms','Unknown-Unknown','DemonHunter-Devourer','Mage-Arcane','DeathKnight-Blood','Monk-Windwalker','Mage-Frost','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Unholy','Warrior-Protection','Druid-Guardian','Priest-Shadow','Paladin-Protection','DemonHunter-Vengeance','Warrior-Fury','Evoker-Preservation','Druid-Balance','Priest-Holy','Shaman-Enhancement',}
local provider = {region='US',realm="Gul'dan",name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abartane:BAAANQAECgYIBgAAAA==.',
Al='Allaria:BAAANQAECgIIAwAAAA==.',
Ao='Aoemomma:BAAANQADCgUIBQAAAA==.',
Ap='Applebottom:BAAANQAECggIDQAAAA==.',
Ar='Arabella:BAAANQADCgMIAwAAAA==.',
At='Atticon:BAABNQAECn8XAAIBAAcK8RW4nQDLAQABAAcK8RW4nQDLAQABNQAECgoKPgACAIUhAA==.',
Az='Azuuli:BAAANQAECgMIBAAAAA==.',
Bi='Bigbeefycake:BAAANQADCgEIAQAAAA==.Bigpriest:BAAANQADCgQIBAAAAA==.',
Bl='Blackthunder:BAAANQAECgEIAQAAAA==.',
Bo='Bob:BAABNQAECn8ZAAIDAAkKVhKBGAD3AQADAAkKVhKBGAD3AQAAAA==.Boome:BAAANQADCggIHQABNQAECgoKJAAEAD0VAA==.',
Bu='Bu:BAAANQAECggIEAABNQAFFAcIFQAFAPMUAA==.Budleaf:BAAANQAECgYICQAAAA==.Bunkley:BAABNQAECn8VAAMGAAkKjxIeXwAhAQAGAAgKxBAeXwAhAQAHAAMKLwhjpwBXAAAAAA==.Buttshark:BAAANQADCgUICQAAAA==.',
By='Byege:BAACNQAFFH8SAAMIAAcKVhuEDACoAQAIAAYKZBqEDACoAQAJAAIKPRYyCgCmAAA1AAQKfzkABAgACgokJv4FAA4DAAgACQoWJv4FAA4DAAkABwqZG/EOAAwCAAoAAQoAACktADwAAAAA.',
Ca='Casteil:BAAANQAECgMIAwAAAA==.',
Ce='Cerbrus:BAABNQAECn8eAAILAAcK+BYydwAoAQALAAcK+BYydwAoAQAAAA==.',
Ch='Champilon:BAAANQAECgEIAQAAAA==.Chaoticus:BAAANQAECgEIAgABNQAECgQICAAMAAAAAA==.Charmahnder:BAAANQADCgQIBAABNQAECgYIDAAMAAAAAA==.Chin:BAACNQAFFH8ZAAIGAAcKpyKeAgAnAgAGAAcKpyKeAgAnAgA1AAQKfzoAAgYACgr2JT0FAJ0DAAYACgr2JT0FAJ0DAAAA.Chuckles:BAAANQAECgIIBAABNQAECgoKKgANAJojAA==.',
Co='Coma:BAAANQAECgUIEwAAAA==.',
Cr='Crackrock:BAAANQAECgUIEQAAAA==.Crunbard:BAAANQAECgcICgAAAA==.',
Cy='Cyanna:BAAANQABCgMIAwAAAA==.',
Da='Dalirus:BAAANQAECgIIAgABNQAECgoKJAAEAD0VAA==.Darci:BAABNQAECn8VAAIOAAcKbx1UlABXAgAOAAcKbx1UlABXAgABNQADCgUIBQAMAAAAAA==.Dasbunk:BAABNQAECn8UAAMPAAcKyBMDaABTAQAPAAcKyBMDaABTAQAFAAIKkwkAmABkAAAAAA==.Dascool:BAAANQAECgEIAQAAAA==.',
De='Deadblue:BAABNQAECn8lAAIJAAcKFBRCBwAFAQAJAAcKFBRCBwAFAQAAAA==.Deathblows:BAABNQAECn8pAAIQAAoKLBLpHQA6AQAQAAoKLBLpHQA6AQAAAA==.',
Dk='Dkpitador:BAAANQAECgEJAwAAAA==.',
Dr='Druidmaster:BAAANQAECgQIDAAAAA==.',
Du='Duch:BAAANQAECgUIDAAAAA==.Duntuskwime:BAAANQADCgcIBwAAAA==.',
El='Elementia:BAAANQAECgEIAQAAAA==.',
Ev='Evilynn:BAABNQAECn8jAAIRAAcKmg4PEwB3AQARAAcKmg4PEwB3AQAAAA==.',
Ex='Extinctionus:BAAANQAECgQIBQAAAA==.',
Fa='Fahros:BAAANQADCgYIBgABNQAECgYIEQAMAAAAAA==.',
Fe='Feliciana:BAAANQAECgMICQAAAA==.',
Fi='Fia:BAAANQAECgYIDQAAAA==.',
Fl='Float:BAAANQADCgYIBQAAAA==.',
Fo='Fondra:BAAANQAECggIAgAAAA==.',
Fu='Fulldps:BAAANQADCgEIAQAAAA==.Funstun:BAABNQAECn8mAAMSAAoKTQiTIAAAAQASAAoKGQeTIAAAAQATAAUKhQqXbACxAAAAAA==.',
Ga='Galaxía:BAAANQAECgMICAAAAA==.',
Go='Gokujang:BAAANQAECgQIEAAAAA==.Gonjah:BAAANQAECgEIAQAAAA==.Gormok:BAAANQAECgMIAwAAAA==.',
Gr='Greendot:BAAANQAFFAIIAgAAAQ==.Greyarrow:BAAANQADCgQIBAAAAA==.',
Gu='Gulvid:BAACNQAFFH8ZAAMIAAcK/xDcBAAnAgAIAAcK/xDcBAAnAgAJAAIKbQ3GDwCVAAA1AAQKf0MABAgACgrvJCcCAFUDAAgACgrvJCcCAFUDAAkABAo4HNwkAEwBAAoAAQq6INYUAF0AAAAA.',
Ha='Hairypennies:BAAANQADCgYJCQAAAA==.Haluak:BAABNQAECn82AAIHAAoKyRmSNACmAgAHAAoKyRmSNACmAgAAAA==.',
Ho='Houndtamer:BAABNQAECn8mAAIBAAoK4QxXQADiAQABAAoK4QxXQADiAQAAAA==.',
Hu='Hukkhan:BAAANQAECggICAAAAA==.',
Ig='Igotthunder:BAAANQADCgUIBQAAAA==.',
In='Ineedahpet:BAAANQAECgMIBgABNQAECgQICAAMAAAAAA==.',
Is='Isomniac:BAAANQAECgQICAAAAA==.',
It='Itshela:BAACNQAFFH8KAAMUAAQKGBulEQDwAAAUAAMKGBulEQDwAAAPAAEKAABMJwBdAAA1AAQKfyMAAxQACQpGIvseANECABQACQpGIvseANECAA8ABAodC2iMANAAAAAA.',
Ja='Jayrad:BAABNQAECn8UAAIKAAcKnwrVDACQAQAKAAcKnwrVDACQAQAAAA==.',
Je='Jellybeanz:BAAANQAECgEIBwAAAA==.',
Jo='Johnnyrage:BAABNQAECn8eAAMVAAoKThejEAAeAgAVAAkKOxejEAAeAgALAAoKbg3qngDPAQAAAA==.Jordybear:BAACNQAFFH8JAAIWAAUKoRV9AgDVAAAWAAUKoRV9AgDVAAA1AAQKfxUAAhYACQrAEXIeAKwBABYACQrAEXIeAKwBAAAA.',
Ka='Kaiige:BAAANQAECgEIAQAAAA==.Kairos:BAABNQAECn8tAAMEAAoKvgzSvACjAQAEAAcKrBHSvACjAQACAAkKBQiGVwA9AQAAAA==.',
Ke='Kenshinth:BAABNQAECn8YAAIXAAcK9hH9LgCsAQAXAAcK9hH9LgCsAQAAAA==.Ketamin:BAAANQAECgQIBAAAAA==.',
Ki='Kiltro:BAABNQAECn8gAAMUAAcKow4pOQDXAAAUAAcKow4pOQDXAAAFAAIKowPejwAqAAAAAA==.Kimchichi:BAAANQAECgQICwAAAA==.',
Ko='Kogorko:BAAANQAECgEIAQABNQAECgYIDAAMAAAAAA==.',
Ku='Kualoloa:BAAANQAECgEIAgAAAA==.',
La='Lapaladin:BAABNQAECn8YAAMCAAYKAAXMdwDcAAACAAYKAAXMdwDcAAAEAAEKAADq2gEVAAAAAA==.Latoya:BAAANQADCgcIDQAAAA==.',
Le='Lemontea:BAABNQAECn8oAAIDAAkKGx6iDQCqAgADAAkKGx6iDQCqAgABNQAFFAIIAgAMAAAAAA==.Lexuus:BAAANQAECgEIAQABNQAECgMIAwAMAAAAAA==.',
Li='Lilyana:BAAANQADCgUIDQAAAA==.Limpairrow:BAAANQAECggIDAAAAA==.Litharidk:BAAANQAECgQIBgAAAA==.Lizzyheals:BAAANQAECgEIAQAAAA==.',
Lo='Lookaway:BAAANQADCgUIBQAAAA==.Loxyblue:BAAANQAECgQIEAAAAA==.',
Lu='Luckyxpain:BAABNQAECn8kAAMEAAoKPRW5kgD/AQAEAAoKPRW5kgD/AQAYAAYKDwyYPAAOAQAAAA==.',
Ly='Lykos:BAAANQAECgUICwAAAA==.',
Ma='Makok:BAABNQAECn8bAAIZAAgKIRVfDQDqAQAZAAgKIRVfDQDqAQAAAA==.Manguu:BAAANQAECgQIBgAAAA==.Manî:BAAANQADCgYIBgAAAA==.',
Me='Melancholic:BAACNQAFFH8FAAIaAAUK7Q7fAADWAAAaAAUK7Q7fAADWAAA1AAQKfygAAhoACgqMHzADAHQCABoACgqMHzADAHQCAAAA.',
Mi='Milkingfist:BAABNQAECn8gAAIDAAcK0g9tIwBlAQADAAcK0g9tIwBlAQAAAA==.Milkingman:BAAANQAECgQJCAAAAA==.Mirie:BAAANQABCgQIBAAAAA==.Misshell:BAAANQAECgEIAQAAAA==.',
Mm='Mmnmjomg:BAAANQADCggICAAAAA==.',
Mo='Moisttotems:BAAANQADCgcICQABNQAECgYIDAAMAAAAAA==.Mooshmoo:BAAANQABCgIIAgAAAA==.Moundofvenus:BAABNQAECn8qAAINAAoKmiP4BQC6AgANAAoKmiP4BQC6AgAAAA==.',
Mu='Murog:BAAANQADCgcIFQAAAA==.',
Ne='Nephlok:BAABNQAECn8jAAIIAAkKRA/LYgA9AQAIAAkKRA/LYgA9AQAAAA==.Nesrin:BAAANQADCgYIBgAAAA==.',
Ni='Nightdisco:BAAANQAECgQIEAAAAA==.',
No='Noctyra:BAAANQADCggICAABNQADCggICAAMAAAAAA==.',
Ny='Nyssaenna:BAAANQADCgMIAwAAAA==.',
Og='Ogtart:BAAANQADCgYIBgAAAA==.Ogthunder:BAAANQADCgYIBgAAAA==.',
Pa='Paidactor:BAAANQAECggIEgAAAA==.',
Pi='Pips:BAABNQAECn8XAAIQAAkK4BcyHABZAgAQAAkK4BcyHABZAgAAAA==.',
Pu='Pureformance:BAACNQAFFH8dAAIGAAcKvSDDAwBPAgAGAAcKvSDDAwBPAgA1AAQKfy4AAgYACgp6JMQAAOEDAAYACgp6JMQAAOEDAAAA.',
Qu='Quiikshot:BAABNQAECn8UAAIBAAkK4QJf/AALAQABAAkK4QJf/AALAQAAAA==.',
Ra='Rabidtips:BAAANQAECgcIBwABNQAECgkJKAADADIPAA==.',
Ri='Rivel:BAAANQADCgcIBwABNQAECgUJBQAMAAAAAA==.Rivoric:BAAANQAECgUJBQAAAA==.Rivotril:BAAANQADCgMIBAAAAA==.',
Ro='Rocks:BAAANQAECgYICQABNQAFFAcIGwAbAPIhAA==.Ronni:BAAANQAECgEIAQABNQAECgYIDAAMAAAAAA==.',
Sa='Salea:BAAANQADCgYIBgABNQAECgYIDAAMAAAAAA==.Santeria:BAAANQAECgQIBAAAAA==.',
Sc='Schango:BAABNQAECn88AAIIAAoKFAqfTwB1AQAIAAoKFAqfTwB1AQAAAA==.Schwiifty:BAAANQAECgEIAQAAAA==.',
Se='Serica:BAAANQAECggIBgAAAA==.',
Sh='Shadowmander:BAAANQADCgMIAwAAAA==.Shakazoom:BAABNQAECn8lAAMcAAoKdBF8QQDyAQAcAAoKdBF8QQDyAQAWAAEK+RPfUgAuAAAAAA==.Shammyhaggar:BAAANQAECgEIAgAAAA==.Shaun:BAABNQAECn8ZAAIdAAkKqCHqJwDKAgAdAAkKqCHqJwDKAgAAAA==.Sheffers:BAAANQAECgYICQAAAA==.Shepard:BAACNQAFFH8gAAICAAcKnSMvAwBqAgACAAcKnSMvAwBqAgA1AAQKfykAAgIACgrKJpMAAPADAAIACgrKJpMAAPADAAAA.Shmorc:BAABNQAECn8jAAMGAAcKHgu8nwA3AQAGAAcKHgu8nwA3AQAHAAEKAAAcXwEaAAAAAA==.Shortcandy:BAAANQADCgQIBQAAAA==.Shredemdown:BAAANQAECgIIBAAAAA==.Shukaku:BAAANQAECgUIBQAAAA==.',
Sk='Skitz:BAAANQAECgQIBgAAAA==.',
Sl='Slashee:BAAANQADCgIIAgAAAA==.Sleepielight:BAAANQAECgYIDwAAAA==.',
So='Somberwish:BAAANQADCggICAAAAA==.Sortie:BAABNQAECn8gAAICAAcK3xJhTABlAQACAAcK3xJhTABlAQAAAA==.',
Sp='Spoonz:BAAANQAECgUICwAAAA==.',
Su='Succinic:BAAANQADCgYICgAAAA==.Superdoom:BAAANQAECgUIDwAAAA==.',
Ta='Tauridin:BAAANQAECgEIAQAAAA==.',
Te='Tegridy:BAAANQAECgEICAAAAA==.',
Th='Thegoldensün:BAABNQAECn82AAMeAAkKOxZqEwAyAgAeAAgKoBdqEwAyAgAGAAgKdRLxcAC5AQAAAA==.Thunderrod:BAABNQAECn8dAAIBAAgKnBESlwDaAQABAAgKnBESlwDaAQAAAA==.',
To='Tolally:BAACNQAFFH8NAAIFAAQKIiIoCADrAAAFAAQKIiIoCADrAAA1AAQKfzMAAwUACgrzIlEJAFQDAAUACgrzIlEJAFQDABQAAwppIT2CABUBAAAA.Tomes:BAAANQADCgQIBAAAAA==.',
Tr='Traessa:BAAANQAECgUIBQABNQAECgYIDAAMAAAAAA==.',
Tw='Twogg:BAAANQAECgYICwAAAA==.',
Ul='Ulfr:BAAANQAECgMIBQAAAA==.Ulfri:BAAANQAECgYIBwAAAA==.Ulvrik:BAAANQADCgIIAgAAAA==.',
Un='Unknownmage:BAAANQABCgQIBAAAAA==.Unpaidintern:BAABNQAECn8qAAIHAAoKixu3GwAjAwAHAAoKixu3GwAjAwAAAA==.',
Va='Vaedroxz:BAAANQAECgEIAQAAAA==.Vaynard:BAABNQAECn8WAAQaAAcKkwsoGwD1AAAaAAQKHREoGwD1AAALAAcKDwlfpgC/AAAVAAEK3RUFLgA8AAAAAA==.',
Ve='Veyá:BAAANQADCggICAAAAA==.',
Vr='Vrandya:BAAANQAECgIIAgAAAA==.',
Wa='Walkthrew:BAACNQAFFH8YAAMIAAYKLxtNDACqAQAIAAUKeRxNDACqAQAJAAIKfxhvAwCiAAA1AAQKfzEAAwgACgpnI5k7AKECAAgACQqhJJk7AKECAAkABQqiF3whAGUBAAAA.Warroir:BAAANQAECggIEQAAAA==.Warrsteak:BAAANQABCgQIBAAAAA==.',
Wi='Wishing:BAAANQADCgUIBQAAAA==.',
Wl='Wlkmob:BAAANQAECgQICAAAAA==.',
Wu='Wunderwazard:BAABNQAECn8cAAIRAAoK7BpOBwB9AgARAAoK7BpOBwB9AgAAAA==.',
Ya='Yadead:BAABNQAECn8pAAILAAoKlQ7TPgDVAQALAAoKlQ7TPgDVAQAAAA==.',
Yo='Yourname:BAAANQABCgQIBAAAAA==.',
Za='Zaelinor:BAAANQADCggICAABNQAFFAYIDgAQAFUXAA==.Zaylen:BAABNQAECn8UAAINAAgKJBykGgBcAQANAAgKJBykGgBcAQABNQAFFAYIDgAQAFUXAA==.',
Ze='Zendjin:BAAANQADCgMIAwAAAA==.Zerog:BAABNQAECn8YAAINAAUKphS0QQBBAQANAAUKphS0QQBBAQAAAA==.',
Zi='Zistormstout:BAABNQAECn8iAAIHAAgKQg1TRwA5AQAHAAgKQg1TRwA5AQAAAA==.',
Zu='Zurmortic:BAABNQAECn8pAAMIAAgKLg2mpwCEAQAIAAgKLg2mpwCEAQAJAAEKIQJFhwAfAAAAAA==.',
['Ðe']='Ðemøn:BAAANQAECgMIAQAAAA==.',
['Ðë']='Ðëmøn:BAAANQAECggIAwAAAA==.',
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
