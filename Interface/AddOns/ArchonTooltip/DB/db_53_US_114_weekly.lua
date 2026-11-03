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

local lookup = {'Hunter-BeastMastery','Paladin-Holy','Monk-Mistweaver','Paladin-Retribution','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Warrior-Arms','Unknown-Unknown','DemonHunter-Devourer','Mage-Arcane','DeathKnight-Blood','Monk-Windwalker','Mage-Frost','DeathKnight-Unholy','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','Warrior-Protection','Druid-Guardian','Priest-Shadow','DemonHunter-Vengeance','Warrior-Fury','Evoker-Preservation','Druid-Balance','Druid-Restoration','Priest-Holy','Shaman-Enhancement',}
local provider = {region='US',realm="Gul'dan",name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abartane:BAAANQAECgYIBgAAAA==.',
Al='Allaria:BAAANQAECgIIAQAAAA==.Allerya:BAAANQADCgEIAQAAAA==.',
Ao='Aoemomma:BAAANQADCgUIBQAAAA==.',
Ap='Applebottom:BAAANQAECggIDQAAAA==.',
Ar='Arabella:BAAANQADCgMIAwAAAA==.',
At='Atticon:BAABNQAECn8YAAIBAAcKRRe4nQDLAQABAAcKRRe4nQDLAQABNQAECgoKRwACABsiAA==.',
Az='Azuuli:BAAANQAECgUIBwAAAA==.',
Bi='Bigbeefycake:BAAANQADCgEIAQAAAA==.Bigpriest:BAAANQADCgQIBAAAAA==.Bigrogue:BAAANQADCgYIBgAAAA==.',
Bl='Blackthunder:BAAANQAECgEIAQAAAA==.Bluetoyou:BAAANQAECgEIAQAAAA==.',
Bo='Bob:BAABNQAECn8ZAAIDAAkKVhKBGAD3AQADAAkKVhKBGAD3AQAAAA==.Boome:BAAANQADCggIHQABNQAECgoKKQAEAAEXAA==.',
Bu='Bu:BAAANQAECggIEAABNQAFFAcIFQAFAPMUAA==.Budleaf:BAAANQAECgcIDAAAAA==.Bunkley:BAABNQAECn8ZAAMGAAkKOxNAcAAvAQAGAAgKhRFAcAAvAQAHAAQKhwe9pwCFAAAAAA==.Buttshark:BAAANQADCgUICQAAAA==.',
By='Byege:BAACNQAFFH8SAAMIAAcKVhuEDACoAQAIAAYKZBqEDACoAQAJAAIKPRYyCgCmAAA1AAQKf0AABAgACgokJkkKAP8CAAgACQoWJkkKAP8CAAkABwqZG/EOAAwCAAoAAwozJocZAHMAAAAA.',
Ca='Casteil:BAAANQAECgMIAwAAAA==.',
Ce='Cerbrus:BAABNQAECn8eAAILAAcK+Ba2pADBAQALAAcK+Ba2pADBAQAAAA==.',
Ch='Chaoticus:BAAANQADCggIDgABNQAECgQIBwAMAAAAAA==.Charmahnder:BAAANQADCgcICwABNQAECgYIDwAMAAAAAA==.Chin:BAACNQAFFH8ZAAIGAAcKpyIbBAAgAgAGAAcKpyIbBAAgAgA1AAQKf0EAAgYACgr2JT0FAJ0DAAYACgr2JT0FAJ0DAAAA.Chuckles:BAAANQAECgIIBAABNQAECgoKMAANAPkjAA==.',
Co='Coma:BAAANQAECgUIEQAAAA==.',
Cr='Crackrock:BAAANQAECgcIEQAAAA==.Crunbard:BAAANQAECgcICgAAAA==.',
Cy='Cyanna:BAAANQABCgMIAwAAAA==.',
Da='Dalirus:BAAANQAECgIIAgABNQAECgoKKQAEAAEXAA==.Darci:BAABNQAECn8VAAIOAAcKbx1UlABXAgAOAAcKbx1UlABXAgABNQADCgUIBQAMAAAAAA==.Dasbunk:BAABNQAECn8XAAMPAAgKPhIDaABTAQAPAAcK8hMDaABTAQAFAAQK9wgphQBrAAAAAA==.Dascool:BAAANQAECgEIAQAAAA==.',
De='Deadblue:BAABNQAECn8nAAIJAAgKuBPaBgA7AQAJAAgKuBPaBgA7AQAAAA==.Deadpally:BAAANQAECgEIAQAAAA==.Deathblows:BAABNQAECn8tAAIQAAoK5hLCLgCiAQAQAAoK5hLCLgCiAQAAAA==.',
Dk='Dkpitador:BAAANQAECgEJAQAAAA==.',
Dr='Druidmaster:BAAANQAECgQIDwAAAA==.',
Du='Duch:BAAANQAECgUIDAAAAA==.Duntuskwime:BAAANQADCgcIBwAAAA==.',
El='Elementia:BAAANQADCggIDAAAAA==.',
Ev='Evilynn:BAABNQAECn8oAAIRAAcKmg4PEwB3AQARAAcKmg4PEwB3AQAAAA==.',
Ex='Extinctionus:BAAANQAECgYIBQAAAA==.',
Fa='Fahros:BAAANQADCgYIBgABNQAECgYIDgAMAAAAAA==.',
Fe='Feliciana:BAAANQAECgQICgAAAA==.',
Fi='Fia:BAABNQAECn8VAAISAAkKYwnbKQBjAQASAAkKYwnbKQBjAQAAAA==.',
Fl='Float:BAAANQADCgcIBwAAAA==.',
Fo='Fondra:BAAANQAECggIAgAAAA==.',
Fu='Fulldps:BAAANQADCgEIAQAAAA==.Funstun:BAABNQAECn8vAAMTAAoK2ghcJQDzAAAUAAcK+AozYgAyAQATAAoKGQdcJQDzAAAAAA==.',
Ga='Galaxía:BAAANQAECgQIDgAAAA==.',
Go='Gokujang:BAABNQAECn8UAAQVAAYKLxgTLQDdAAAVAAQK4R0TLQDdAAACAAIKiwH9GwE8AAAEAAEKGAfucQExAAAAAA==.Gonjah:BAAANQAECgMIAwAAAA==.Gormok:BAAANQAECgMIAwAAAA==.',
Gr='Greendot:BAAANQAFFAIIAgAAAQ==.Greyarrow:BAAANQADCgQIBAAAAA==.',
Gu='Gulvid:BAACNQAFFH8bAAMIAAgKwxHcBAAnAgAIAAgKwxHcBAAnAgAJAAIKbQ3GDwCVAAA1AAQKf0wABAgACgpdJSgDAFgDAAgACgpdJSgDAFgDAAkABAo4HNwkAEwBAAoAAQq6ICcfAFAAAAAA.',
Ha='Hairypennies:BAAANQADCgYJCQAAAA==.Haluak:BAABNQAECn88AAIHAAoK1RmSNACmAgAHAAoK1RmSNACmAgAAAA==.',
Ho='Houndtamer:BAABNQAECn8oAAIBAAoK4QzvWwDMAQABAAoK4QzvWwDMAQAAAA==.',
Hu='Hukkhan:BAAANQAECggICAAAAA==.',
Ig='Igotthunder:BAAANQADCgUIBQAAAA==.',
In='Ineedahpet:BAAANQAECgMIBgABNQAECgQIBwAMAAAAAA==.',
Is='Isomniac:BAAANQAECgQICAAAAA==.',
It='Itshela:BAACNQAFFH8KAAMSAAQKGBulEQDwAAASAAMKGBulEQDwAAAPAAEKAABMJwBdAAA1AAQKfyMAAxIACQpGIvseANECABIACQpGIvseANECAA8ABAodC2iMANAAAAAA.',
Ja='Jayrad:BAABNQAECn8ZAAIKAAcKnwrVDACQAQAKAAcKnwrVDACQAQAAAA==.',
Jo='Johnnyrage:BAABNQAECn8fAAMWAAoKThejEAAeAgAWAAkKOxejEAAeAgALAAoKbg3qngDPAQAAAA==.Jordybear:BAACNQAFFH8JAAIXAAUKoRVJAwDQAAAXAAUKoRVJAwDQAAA1AAQKfxUAAhcACQrAEXIeAKwBABcACQrAEXIeAKwBAAAA.',
Ka='Kairos:BAABNQAECn8yAAMEAAoKbw/SvACjAQAEAAcKoBTSvACjAQACAAkKGQlbbAA/AQAAAA==.',
Ke='Kenshinth:BAABNQAECn8cAAIYAAcKHhL9LgCsAQAYAAcKHhL9LgCsAQAAAA==.Ketamin:BAAANQAECgQIBAAAAA==.',
Ki='Kiltro:BAABNQAECn8kAAMSAAgKNBIFMwArAQASAAgKNBIFMwArAQAFAAIKowOvpgAnAAAAAA==.Kimchichi:BAAANQAECgYIDgAAAA==.',
Ko='Kogorko:BAAANQAECgEIAQABNQAECgYIDwAMAAAAAA==.',
La='Lapaladin:BAABNQAECn8YAAMCAAYKAAWskgDUAAACAAYKAAWskgDUAAAEAAEKAADq2gEVAAAAAA==.Lapriestess:BAAANQAECgEIAQAAAA==.Latoya:BAAANQADCgcIDQAAAA==.',
Le='Lemontea:BAABNQAECn8oAAIDAAkKGx6iDQCqAgADAAkKGx6iDQCqAgABNQAFFAIIAgAMAAAAAA==.Lexuus:BAAANQADCgUICAABNQAECgMIAwAMAAAAAA==.',
Li='Lilyana:BAAANQADCgUIDQAAAA==.Limpairrow:BAAANQAECggICgAAAA==.Litharidk:BAAANQAECgQIBgAAAA==.Lizzyheals:BAAANQABCggIDQAAAA==.',
Lo='Lookaway:BAAANQADCgUIBQAAAA==.Loxyblue:BAAANQAECgQIEAAAAA==.',
Lu='Luckyxpain:BAABNQAECn8pAAMEAAoKARcxZADNAQAEAAoKARcxZADNAQAVAAcKuwuYPAAOAQAAAA==.',
Ly='Lykos:BAAANQAECgcICAAAAA==.',
Ma='Makok:BAABNQAECn8fAAIZAAgK8RVfDQDqAQAZAAgK8RVfDQDqAQAAAA==.Manguu:BAAANQAECgQIBQAAAA==.Manî:BAAANQADCgYIBgAAAA==.',
Me='Melancholic:BAACNQAFFH8GAAIaAAYK/w6SAAAfAQAaAAYK/w6SAAAfAQA1AAQKfzEAAhoACgouIpYBABQDABoACgouIpYBABQDAAAA.',
Mi='Milkingfist:BAABNQAECn8gAAIDAAcK0g9tIwBlAQADAAcK0g9tIwBlAQAAAA==.Milkingman:BAAANQAECgQJBgAAAA==.Mirie:BAAANQABCgQIBAAAAA==.Misshell:BAAANQAECgEIAQAAAA==.',
Mm='Mmnmjomg:BAAANQADCggICAAAAA==.',
Mo='Moisttotems:BAAANQADCgcICQABNQAECgYIDwAMAAAAAA==.Mooshmoo:BAAANQABCgIIAgAAAA==.Moundofvenus:BAABNQAECn8wAAINAAoK+SOvAwAjAwANAAoK+SOvAwAjAwAAAA==.',
Mu='Murog:BAAANQADCgcIFQAAAA==.',
Ne='Nephlok:BAABNQAECn8pAAIIAAkKIxCLdQBBAQAIAAkKIxCLdQBBAQAAAA==.Nesrin:BAAANQADCgYIBgAAAA==.',
Ni='Nightdisco:BAAANQAECgQIEAAAAA==.',
No='Noctyra:BAAANQADCggICAABNQADCggICAAMAAAAAA==.',
Ny='Nyssaenna:BAAANQADCgMIAwAAAA==.',
Og='Ogtart:BAAANQADCgYIBgAAAA==.Ogthunder:BAAANQADCgYIBgAAAA==.',
Pa='Paidactor:BAABNQAECn8TAAIIAAoKUwNXuQCtAAAIAAoKUwNXuQCtAAAAAA==.',
Pi='Pips:BAABNQAECn8XAAIQAAkK4BcyHABZAgAQAAkK4BcyHABZAgAAAA==.',
Pu='Pureformance:BAACNQAFFH8dAAIGAAcKvSDDAwBPAgAGAAcKvSDDAwBPAgA1AAQKfy8AAgYACgrzJcQAAOEDAAYACgrzJcQAAOEDAAE1AAQKBwgHAAwAAAAA.Purrformance:BAAANQAECgcIBwAAAA==.',
Qu='Quiikshot:BAABNQAECn8WAAIBAAkK4QJf/AALAQABAAkK4QJf/AALAQAAAA==.',
Ra='Rabidtips:BAAANQAECgcICwABNQAECgoKLgADAGARAA==.',
Ri='Rivel:BAAANQADCgcIBwABNQAECgUJBQAMAAAAAA==.Rivoric:BAAANQAECgUJBQAAAA==.Rivotril:BAAANQADCgMIBAAAAA==.',
Ro='Rocks:BAAANQAECgcIDAABNQAFFAgIHQAbAEwfAA==.Ronni:BAAANQAECgEIAQABNQAECgYIDwAMAAAAAA==.',
Sa='Salea:BAAANQADCgYIBgABNQAECgYIDwAMAAAAAA==.Santeria:BAAANQAECgYICwAAAA==.',
Sc='Schango:BAABNQAECn88AAIIAAoKFArSaABiAQAIAAoKFArSaABiAQAAAA==.Schwiifty:BAAANQADCgQIBAAAAA==.',
Se='Serica:BAAANQAECggIBgAAAA==.',
Sh='Shadowmander:BAAANQADCgMIAwAAAA==.Shakazoom:BAABNQAECn8rAAQcAAoKvhENLQBhAQAcAAoKvhENLQBhAQAXAAEK+RPoYQAuAAAdAAEKjAUsbwAkAAAAAA==.Shammyhaggar:BAAANQAECgEIAwAAAA==.Shaun:BAABNQAECn8ZAAIeAAkKqCHqJwDKAgAeAAkKqCHqJwDKAgAAAA==.Sheffers:BAAANQAECgYIBwAAAA==.Shepard:BAACNQAFFH8gAAICAAcKnSMvAwBqAgACAAcKnSMvAwBqAgA1AAQKfyoAAgIACgrkJpMAAPADAAIACgrkJpMAAPADAAAA.Shmorc:BAABNQAECn8oAAMGAAcKZBDicwAkAQAGAAcKZBDicwAkAQAHAAEKAAAcXwEaAAAAAA==.Shortcandy:BAAANQADCgQIBQAAAA==.Shredemdown:BAAANQAECgMIBgAAAA==.Shukaku:BAAANQAECgUICAAAAA==.',
Sk='Skitz:BAAANQAECgQIBAAAAA==.',
Sl='Slashee:BAAANQADCgIIAgAAAA==.Sleepielight:BAAANQAECgYIEQAAAA==.',
So='Somberwish:BAAANQADCggICAAAAA==.Sortie:BAABNQAECn8hAAICAAgKkxE7VgCJAQACAAgKkxE7VgCJAQAAAA==.',
Sp='Spoonz:BAAANQAECgUICgAAAA==.',
Su='Succinic:BAAANQADCgYICgAAAA==.Superdoom:BAAANQAECgYIDgAAAA==.',
Ta='Tauridin:BAAANQABCgEIAQAAAA==.',
Te='Tegridy:BAAANQAECgEIBAAAAA==.',
Th='Thegoldensün:BAABNQAECn82AAMfAAkKOxZqEwAyAgAfAAgKoBdqEwAyAgAGAAgKdRLxcAC5AQAAAA==.Thunderrod:BAABNQAECn8hAAIBAAoKuBDldwCEAQABAAoKuBDldwCEAQAAAA==.',
To='Tolally:BAACNQAFFH8OAAIFAAQKIiKqCwAoAQAFAAQKIiKqCwAoAQA1AAQKfzQAAwUACgpRI1EJAFQDAAUACgpRI1EJAFQDABIAAwppIT2CABUBAAAA.Tomes:BAAANQADCgQIBAAAAA==.',
Tr='Traessa:BAAANQAECgUIBQABNQAECgYIDwAMAAAAAA==.',
Tw='Twogg:BAAANQAECgYICgAAAA==.',
Ul='Ulfr:BAAANQAECgMIBQAAAA==.Ulfri:BAAANQAECgYIBwAAAA==.Ulvrik:BAAANQADCgIIAgAAAA==.',
Un='Unknownmage:BAAANQABCgQIBAAAAA==.Unpaidintern:BAABNQAECn8yAAIHAAoKixu3GwAjAwAHAAoKixu3GwAjAwAAAA==.',
Va='Vanoc:BAAANQAECgQIAQAAAA==.Vastian:BAAANQAECgQIBAAAAA==.Vaynard:BAABNQAECn8XAAQaAAgKIQwoGwD1AAALAAgKCArGowD+AAAaAAQKHREoGwD1AAAWAAEK3RW5NwA6AAAAAA==.',
Ve='Veyá:BAAANQADCggICAAAAA==.',
Vr='Vrandya:BAAANQAECgQIBgAAAA==.',
Wa='Walkthrew:BAACNQAFFH8YAAMIAAYKLxtNDACqAQAIAAUKeRxNDACqAQAJAAIKfxioBACYAAA1AAQKfzkAAwgACgp2JJk7AKECAAgACQqhJJk7AKECAAkABQp/GnwhAGUBAAAA.Warroir:BAAANQAECggIEgAAAA==.Warrsteak:BAAANQABCgQIBAAAAA==.',
Wi='Wishing:BAAANQADCgUIBQAAAA==.',
Wl='Wlkmob:BAAANQAECgQIBgAAAA==.',
Wu='Wunderwazard:BAABNQAECn8gAAIRAAoKohtOBwB9AgARAAoKohtOBwB9AgAAAA==.',
Ya='Yadead:BAABNQAECn8wAAILAAoKlRHRRgD8AQALAAoKlRHRRgD8AQAAAA==.',
Yo='Yourname:BAAANQABCgQIBAAAAA==.',
Za='Zaelinor:BAAANQADCggICAABNQAFFAYIDgAQAFUXAA==.Zaylen:BAABNQAECn8WAAINAAgKJByPIgBRAQANAAgKJByPIgBRAQABNQAFFAYIDgAQAFUXAA==.',
Ze='Zendjin:BAAANQADCgMIAwAAAA==.Zerog:BAABNQAECn8dAAINAAUKphS0QQBBAQANAAUKphS0QQBBAQAAAA==.',
Zi='Zistormstout:BAABNQAECn8mAAIHAAgKQg0xWwA5AQAHAAgKQg0xWwA5AQAAAA==.',
Zu='Zurmortic:BAABNQAECn8yAAQIAAoKCQ41cQBMAQAIAAoKnQ01cQBMAQAKAAEKHA0tJQA5AAAJAAEKIQJFhwAfAAAAAA==.',
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
