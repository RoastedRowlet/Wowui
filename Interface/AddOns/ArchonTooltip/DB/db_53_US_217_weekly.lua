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

local lookup = {'Mage-Fire','DeathKnight-Blood','DeathKnight-Frost','Paladin-Holy','Shaman-Elemental','Evoker-Preservation','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Druid-Guardian','Priest-Holy','Warlock-Demonology','Warrior-Protection','DeathKnight-Unholy','Shaman-Restoration','Warrior-Arms','Mage-Arcane','Mage-Frost','Shaman-Enhancement','Paladin-Retribution','Paladin-Protection','Druid-Feral','Warlock-Destruction','Unknown-Unknown','DemonHunter-Devourer','Priest-Shadow','Monk-Windwalker','Monk-Brewmaster','Warlock-Affliction','Rogue-Outlaw',}
local provider = {region='US',realm='TheVentureCo',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abanados:BAABNQAECn8eAAIBAAgKdw1AAwDQAQABAAgKdw1AAwDQAQAAAA==.',
Ae='Aethelra:BAAANQAECgMIAwAAAA==.',
Ak='Aken:BAAANQADCgcIBwAAAA==.',
Al='Alivasticus:BAABNQAECn8WAAMCAAcKaA3QdgAYAQACAAcKaA3QdgAYAQADAAEKAAAAAAAAAAABNQAFFAUICgAEAGERAA==.',
Am='Amme:BAAANQAECgQIBAAAAA==.',
An='Animorpha:BAAANQADCgYIBgAAAA==.',
As='Asonda:BAEANQAECgQICAAAAA==.',
Ba='Badvision:BAAANQADCgYICgAAAA==.Bagofluff:BAAANQAECgMIBAABNQAFFAUIFQAFAAEYAA==.Bajamama:BAAANQADCgMIAQAAAA==.Baobeikejia:BAAANQAECgYICwAAAA==.',
Be='Betiff:BAAANQAECgQIDAAAAA==.Betrellis:BAAANQAECgIIAgAAAA==.',
Bl='Bloodydraco:BAABNQAECn8jAAIGAAgKoBn8EgB7AgAGAAgKoBn8EgB7AgAAAA==.',
Ca='Cakebro:BAABNQAECn8ZAAQHAAgK2xmaPgBYAQAIAAYKHRtBCQCmAQAHAAUKHRiaPgBYAQAJAAEKcBYpRAFOAAAAAA==.Caliâ:BAAANQAECgQIBAAAAA==.Camembert:BAABNQAECn8aAAIKAAgK2CSaBQA9AwAKAAgK2CSaBQA9AwAAAA==.Carmellion:BAAANQAECgUIEAAAAA==.Casii:BAABNQAECn8jAAILAAgKuQ2YdAC5AQALAAgKuQ2YdAC5AQAAAA==.',
Ch='Chubingus:BAAANQAECggIEAAAAA==.Chufeng:BAABNQAECn8hAAIJAAgKqiKzKAD0AgAJAAgKqiKzKAD0AgAAAA==.Chumlemagne:BAAANQADCgMJAwAAAA==.',
Co='Cowtastrophy:BAAANQAECgQICAAAAA==.',
Cr='Crizadin:BAAANQABCgYIDAABNQAECggIIgAJANkiAA==.Cryp:BAAANQAECgYIEAAAAA==.',
Cy='Cynikal:BAAANQADCgEIAQABNQAECggIIwALALkNAA==.',
Da='Danaki:BAAANQAECgEIAQABNQAECgcIGgAMAG0RAA==.Danorace:BAAANQAECgQIBgAAAA==.Darkcurve:BAAANQAECgcIEwAAAA==.Darkhope:BAABNQAECn8eAAICAAkK3COODABNAwACAAkK3COODABNAwAAAA==.Darla:BAAANQADCgcIDAAAAA==.Dawnest:BAAANQAECgMIAwAAAA==.',
De='Deija:BAAANQAECgQIDAAAAA==.Dekoo:BAABNQAECn8fAAINAAgK9h66CADDAgANAAgK9h66CADDAgAAAA==.',
Do='Docious:BAAANQADCgYIDQAAAA==.',
Dr='Drakula:BAAANQADCgMIAwAAAA==.Dreadfang:BAABNQAECn8oAAIOAAkKxCApFQAPAwAOAAkKxCApFQAPAwAAAA==.Droka:BAABNQAECn8gAAIPAAgKbB6dKQC7AgAPAAgKbB6dKQC7AgAAAA==.',
Eu='Eurotophobia:BAAANQAECgYICQAAAA==.',
Ex='Exodia:BAAANQAECgYIDgAAAA==.',
Fh='Fhyllo:BAAANQAECgYIEQAAAA==.',
Fl='Flaaffy:BAABNQAECn8kAAIFAAkKTBIIUAA1AgAFAAkKTBIIUAA1AgAAAA==.',
Fo='Follaglas:BAABNQAECn8lAAIJAAkK9B6EGAA2AwAJAAkK9B6EGAA2AwAAAA==.Fooberdabber:BAAANQABCgUICAAAAA==.',
Ga='Gabriel:BAAANQADCgUIBQAAAA==.Gairen:BAAANQAECgUICQAAAA==.Galadisis:BAABNQAECn8oAAMNAAkKqSIwBQAkAwANAAgKViIwBQAkAwAQAAgKXx70WgB4AgAAAA==.Gandaelf:BAABNQAECn8oAAQRAAkKUSHoLAA0AwARAAkKDyHoLAA0AwASAAIKTCM7JgC8AAABAAEKAACBDAA9AAAAAA==.',
Gh='Ghuldana:BAABNQAECn8aAAIMAAcKbRELkAC5AQAMAAcKbRELkAC5AQAAAA==.',
Gi='Girthzilla:BAAANQAECgEIAQAAAA==.',
Gl='Glemin:BAAANQADCgEIAQAAAA==.',
Gr='Greyborn:BAAANQADCgUIBQAAAA==.Gryari:BAAANQAECgUIBwAAAA==.',
Gu='Guldaggar:BAABNQAECn8aAAIFAAgK4BVgVwAaAgAFAAgK4BVgVwAaAgAAAA==.',
Gw='Gwiynevere:BAAANQADCgMIAwAAAA==.',
Ha='Haunter:BAAANQADCgIIAgAAAA==.',
He='Hellao:BAAANQAECggIEgAAAA==.Hellmage:BAAANQADCgQIBAAAAA==.',
Hi='Hiroshige:BAAANQADCgQIBAAAAA==.',
Ho='Holysausage:BAAANQADCgYIBgAAAA==.',
Hr='Hrenam:BAAANQAECgUIEQAAAA==.Hrimceald:BAABNQAECn8dAAIPAAgK6xa2VwAHAgAPAAgK6xa2VwAHAgAAAA==.',
Hy='Hylts:BAABNQAECn8bAAITAAYKqwqDHwBhAQATAAYKqwqDHwBhAQAAAA==.',
Il='Illithian:BAAANQAECgMIAwAAAA==.',
Im='Imalockyo:BAAANQAECgQIBQAAAA==.',
Ja='Javi:BAABNQAECn8mAAMCAAkK/SS2BQCXAwACAAkK/SS2BQCXAwAOAAQKWSEhYwCAAQAAAA==.Javiertwo:BAAANQAECgUIBgAAAA==.Javioli:BAAANQAECggICQABNQAECgkJJgACAP0kAA==.',
Ka='Kaladin:BAAANQAECgEIAwABNQAECgkJHQACAFgjAA==.Kariboose:BAAANQABCgIIAgAAAA==.Kassiandra:BAABNQAECn8gAAMEAAgKBRQxcwC7AQAEAAcKwxIxcwC7AQAUAAcKkg+lxQCKAQAAAA==.',
Ke='Kejiabaobei:BAABNQAECn8iAAIJAAkKSiP6CwB9AwAJAAkKSiP6CwB9AwAAAA==.Kevlarprime:BAAANQAECgMIAwAAAA==.Kevsterr:BAABNQAECn8mAAIRAAgKBQqk5AC8AQARAAgKBQqk5AC8AQAAAA==.',
Kh='Khaantu:BAABNQAECn8tAAIVAAkKQiXMAQC7AwAVAAkKQiXMAQC7AwAAAA==.',
Ko='Koryk:BAAANQAECgYJBgAAAA==.',
Kr='Krein:BAAANQAECgQIBAAAAA==.Krünk:BAABNQAECn8oAAIGAAkKVxvIDADYAgAGAAkKVxvIDADYAgAAAA==.',
Ku='Kumquat:BAAANQABCgIIAgAAAA==.',
La='Lachdanan:BAAANQAECgQIDQAAAA==.Lans:BAAANQAECgUIBgAAAA==.Lastritez:BAABNQAECn8nAAMUAAgKbRUEkwD5AQAUAAgKbRUEkwD5AQAVAAcKGgbrPwD1AAAAAA==.',
Le='Leafbeard:BAABNQAECn8cAAMWAAcKCxToEgDNAQAWAAcKCxToEgDNAQAKAAIKABbLSwBvAAAAAA==.',
Li='Lilean:BAABNQAECn8jAAIJAAkK/hxkLQDkAgAJAAkK/hxkLQDkAgAAAA==.',
Lo='Lokka:BAAANQAECgQIDgAAAA==.Lolly:BAAANQAECgYIEwAAAA==.Longick:BAAANQADCgIIAgAAAA==.Lormont:BAAANQADCgUIBQAAAA==.Loskember:BAAANQADCgQIBAAAAA==.',
Ly='Lyreshade:BAABNQAECn8oAAIFAAkKRhZ8SgBJAgAFAAkKRhZ8SgBJAgAAAA==.',
['Lÿ']='Lÿcâòñ:BAAANQAECgUICQAAAA==.',
Ma='Madbunny:BAAANQADCgQIBAAAAA==.Madriina:BAAANQADCggIFQAAAA==.Mahrah:BAAANQAECgEIAQAAAA==.Malört:BAAANQABCgQIBQAAAA==.Manchego:BAAANQADCgMIAwAAAA==.Mar:BAAANQAECgQICQAAAA==.Mazakiel:BAAANQAECgQIBAAAAA==.',
Me='Melevolence:BAABNQAECn8mAAMMAAkKnBJtYwArAgAMAAkKnBJtYwArAgAXAAIKlQTzbgBAAAAAAA==.Mep:BAAANQADCgUIBQABNQAECgUICQAYAAAAAA==.',
Mo='Morticia:BAAANQADCgYICQAAAA==.',
My='Myst:BAAANQADCgEIAQAAAA==.Mythbras:BAAANQADCgYIDQAAAA==.',
['Mù']='Mùfasa:BAAANQAECgYIEwAAAA==.',
Na='Navdrag:BAAANQAECgUJCwAAAA==.Naxria:BAAANQAECgUIDAAAAA==.',
Ne='Necroticnuts:BAAANQADCgYICgAAAA==.Nevera:BAAANQADCgMIAwAAAA==.',
Ni='Nili:BAAANQAECggIAQAAAA==.Nimithriel:BAAANQAECgQIBQAAAA==.',
No='Notwesa:BAAANQAECgMIBQAAAA==.Notweso:BAABNQAECn8nAAIZAAkKtSJfBACOAwAZAAkKtSJfBACOAwAAAA==.Notwezo:BAAANQAECgEIAgAAAA==.',
Or='Oriari:BAAANQADCgcICAAAAA==.Oroki:BAAANQAECgQICgAAAA==.',
Pa='Panay:BAAANQABCgMIAwAAAA==.',
Po='Poovey:BAACNQAFFH8FAAIQAAIKEQzgMACFAAAQAAIKEQzgMACFAAA1AAQKfywAAhAACQoLH1c8ANMCABAACQoLH1c8ANMCAAAA.',
Pu='Purpletoe:BAABNQAECn8bAAMLAAkK9RzMNACSAgALAAgKeBzMNACSAgAaAAEKAAD/fwAoAAAAAA==.Putrificator:BAAANQADCgQIBAAAAA==.',
Py='Pyronae:BAABNQAECn8gAAIMAAgKKRADewDuAQAMAAgKKRADewDuAQAAAA==.',
Qi='Qit:BAAANQADCgYICgABNQAECggIGQAbAC8iAA==.',
Ra='Rargh:BAAANQAECggICwAAAA==.',
Re='Rebornhope:BAAANQABCggIEwABNQAECgkJHgACANwjAA==.Redonkeylous:BAAANQAECgMIBgAAAA==.Redonkurus:BAAANQADCgQIBAAAAA==.Rengen:BAABNQAECn8fAAIcAAgK4RYfDQAnAgAcAAgK4RYfDQAnAgAAAA==.Restalkurus:BAAANQADCgUIAgAAAA==.Reya:BAAANQAECgQICQAAAA==.',
Ro='Roft:BAAANQADCggICAAAAA==.',
Ru='Runelord:BAAANQAECgUIBAAAAA==.Ruìn:BAAANQAECgMIAwAAAA==.',
['Rí']='Rían:BAAANQADCgUIBQAAAA==.',
Sa='Saeli:BAAANQAECgcIEQAAAA==.Saeris:BAAANQADCgcIBwAAAA==.Sanamongolos:BAAANQAECgUIBgAAAA==.Saraija:BAAANQAECgIIAgABNQAECgQIDAAYAAAAAA==.Sasinko:BAABNQAECn8cAAIdAAgKURw7BACdAgAdAAgKURw7BACdAgAAAA==.Sassypants:BAAANQAECgYIBgAAAA==.Sawlrenuk:BAAANQADCgIIAgAAAA==.',
Se='Sesshoomaru:BAAANQAECggICAAAAA==.',
Sh='Shadowstripe:BAABNQAECn8gAAIbAAcKuhVVKgDGAQAbAAcKuhVVKgDGAQAAAA==.Shigglez:BAABNQAECn8gAAIRAAkKAhkpjwBhAgARAAkKAhkpjwBhAgAAAA==.Shinìgámi:BAAANQABCgUIAwAAAA==.',
Sl='Slapchop:BAAANQAECgcJEQAAAA==.Slop:BAACNQAFFH8XAAINAAYKABaOAQC9AQANAAYKABaOAQC9AQA1AAQKfzIAAg0ACQr6IPQEACwDAA0ACQr6IPQEACwDAAAA.',
So='Soteria:BAAANQAECgUIDQABNQAECggIIQAJAKoiAA==.',
Su='Sugarpants:BAAANQAECgUIEAAAAA==.',
Sy='Sydnehektori:BAAANQADCgUIBQAAAA==.Sylphrenaa:BAAANQADCggICAAAAA==.',
Te='Tembtree:BAAANQAECgQIBQABNQAECgQIDQAYAAAAAA==.Temlock:BAAANQAECgQIDQAAAA==.',
Ti='Tiggerina:BAAANQAECgIIAgAAAA==.',
Tu='Turan:BAAANQAECgMIBAAAAA==.',
Ty='Typhonic:BAAANQAECgUICQAAAA==.Tyrenari:BAAANQADCgEIAQAAAA==.',
Ul='Ultear:BAAANQAECgYIEwAAAA==.',
Ve='Venthyr:BAAANQAECgMIBAAAAA==.Vetenarae:BAAANQADCggICAABNQAECgYIGwATAKsKAA==.Vethja:BAAANQAECgIIAgABNQAECgQIDAAYAAAAAA==.',
Vo='Voidhope:BAAANQADCgYICAABNQAECgkJHgACANwjAA==.Volkren:BAABNQAECn8rAAICAAgKQCMwFgD5AgACAAgKQCMwFgD5AgAAAA==.',
Wi='Witherpants:BAAANQAECgcIDQAAAA==.',
Wo='Worshipme:BAAANQAECgMIAwAAAA==.',
Xa='Xandor:BAAANQADCgIIAgABNQAECgkJHgACANwjAA==.Xaos:BAABNQAECn8ZAAIeAAgK1B1WBQCbAgAeAAgK1B1WBQCbAgAAAA==.',
Xi='Xiaowugui:BAAANQAECgcICgAAAA==.',
Ya='Yarrick:BAABNQAECn8eAAIPAAcKvBcaYADrAQAPAAcKvBcaYADrAQAAAA==.',
Yu='Yukihime:BAAANQAECgcICAABNQAECgkJLAARAH0gAA==.',
Ze='Zelkiri:BAAANQAECgQIDgAAAA==.Zethlahr:BAABNQAECn8oAAMaAAkKuyHBDwD3AgAaAAgKbCHBDwD3AgALAAEKqxFV8ABJAAAAAA==.',
Zo='Zoltan:BAAANQADCgQIBAAAAA==.',
Zu='Zupt:BAAANQADCgQIBAAAAA==.',
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
