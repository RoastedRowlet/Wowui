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

local lookup = {'Mage-Fire','DeathKnight-Blood','DeathKnight-Frost','Paladin-Holy','Shaman-Elemental','Evoker-Preservation','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Druid-Guardian','Priest-Holy','Mage-Arcane','DeathKnight-Unholy','Warlock-Demonology','Paladin-Retribution','Warrior-Protection','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Arms','Mage-Frost','Druid-Balance','Shaman-Enhancement','Paladin-Protection','Druid-Feral','Warlock-Destruction','Unknown-Unknown','Priest-Shadow','Monk-Windwalker','Monk-Brewmaster','Warlock-Affliction','DemonHunter-Vengeance','Rogue-Outlaw',}
local provider = {region='US',realm='TheVentureCo',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abanados:BAABNQAECn8lAAIBAAkKhg66AAB7AQABAAkKhg66AAB7AQAAAA==.',
Ae='Aethelra:BAAANQAECgQIBAAAAA==.',
Ak='Aken:BAAANQADCgcIBwAAAA==.',
Al='Alivasticus:BAACNQAFFH8GAAICAAMK6AoJGwDCAAACAAMK6AoJGwDCAAA1AAQKfxoAAwIACAp+D38iAO4AAAIACAp+D38iAO4AAAMAAQoAAAAAAAAAAAE1AAUUBggLAAQAFxAA.',
Am='Amme:BAAANQAECgUIBgAAAA==.',
An='Animorpha:BAAANQADCgYIBgAAAA==.',
As='Asonda:BAEANQAECgUIDQAAAA==.',
Ba='Badvision:BAAANQADCgYICgAAAA==.Bagofluff:BAAANQAECgMIBAABNQAFFAYIFgAFAFIUAA==.Bajamama:BAAANQADCgMIAQAAAA==.Baobeikejia:BAAANQAECggIEgAAAA==.',
Be='Betiff:BAAANQAECgUIEQAAAA==.Betrellis:BAAANQAECgIIAgAAAA==.',
Bl='Bloodydraco:BAABNQAECn8sAAIGAAkKcxeDAgASAgAGAAkKcxeDAgASAgAAAA==.',
Ca='Cakebro:BAABNQAECn8ZAAQHAAgK2xliPwBYAQAIAAYKHRtMCQCmAQAHAAUKHRhiPwBYAQAJAAEKcBZWSAFOAAAAAA==.Caliâ:BAAANQAECgUIBQAAAA==.Camembert:BAABNQAECn8jAAIKAAoKiCK5AAAAAwAKAAoKiCK5AAAAAwAAAA==.Carmellion:BAAANQAECgUIEgAAAA==.Casii:BAABNQAECn8jAAILAAgKuQ0CdgC5AQALAAgKuQ0CdgC5AQAAAA==.',
Ch='Chrollo:BAAANQAECgMIAwABNQAECgoKLgAMANUgAA==.Chubingus:BAABNQAECn8WAAINAAoKCx0tGgDwAgANAAoKCx0tGgDwAgAAAA==.Chufeng:BAACNQAFFH8HAAIJAAMKtREpBwDyAAAJAAMKtREpBwDyAAA1AAQKfyEAAgkACAqqIlQpAPMCAAkACAqqIlQpAPMCAAAA.Chumlemagne:BAAANQADCgMJAwAAAA==.',
Co='Cowtastrophy:BAAANQAECgYIDQAAAA==.',
Cr='Crizadin:BAAANQABCgYIDAABNQAECgkJJwAJAKgiAA==.Cryp:BAAANQAECgYIEAAAAA==.',
Cy='Cynikal:BAAANQADCgEIAQABNQAECggIIwALALkNAA==.',
Da='Daemenar:BAAANQAECgEIAQAAAA==.Danaki:BAAANQAECgEIAQABNQAECggIIQAOAAsTAA==.Danorace:BAAANQAECgQIBgAAAA==.Darkcurve:BAABNQAECn8dAAIPAAkKIhYEHwCmAQAPAAkKIhYEHwCmAQAAAA==.Darkhope:BAABNQAECn8hAAICAAoK1iP4AwCxAwACAAoK1iP4AwCxAwAAAA==.Darla:BAAANQADCggIEQAAAA==.Dawnest:BAAANQAECgMIAwAAAA==.',
De='Deija:BAAANQAECgUIDQAAAA==.Dekoo:BAABNQAECn8mAAIQAAkK+B44AgDwAQAQAAkK+B44AgDwAQAAAA==.',
Do='Docious:BAAANQADCgYIDQAAAA==.',
Dr='Drakula:BAAANQADCgMIAwAAAA==.Dreadfang:BAABNQAECn8xAAINAAoKIB6DAQCSAgANAAoKIB6DAQCSAgAAAA==.Droka:BAABNQAECn8nAAIRAAkKrh6ACAA7AgARAAkKrh6ACAA7AgAAAA==.',
Eu='Eurotophobia:BAAANQAECgYIDwAAAA==.',
Ex='Exodia:BAABNQAECn8ZAAIJAAcKiRLziwDyAQAJAAcKiRLziwDyAQAAAA==.',
Fa='Faedeynna:BAAANQADCgIIAgAAAA==.',
Fh='Fhyllo:BAABNQAECn8aAAMSAAgKBhMKMADBAQASAAgKBhMKMADBAQATAAEKkwN2VgAkAAAAAA==.',
Fl='Flaaffy:BAABNQAECn8mAAIFAAoKfxAKUQA0AgAFAAoKfxAKUQA0AgAAAA==.',
Fo='Follaglas:BAABNQAECn8lAAIJAAkK9B4FGQA1AwAJAAkK9B4FGQA1AwAAAA==.Fooberdabber:BAAANQABCgUICAAAAA==.',
Ga='Gabriel:BAAANQADCgUIBQAAAA==.Gairen:BAAANQAECgYICQAAAA==.Galadisis:BAABNQAECn8uAAMQAAoKmiBABQAkAwAQAAgKViJABQAkAwAUAAoK0hxhDwDeAQAAAA==.Gandaelf:BAABNQAECn8uAAQMAAoK1SC7LQAyAwAMAAoKnCC7LQAyAwAVAAIKTCPEJgC8AAABAAEKAACsDAA9AAAAAA==.',
Gh='Ghuldana:BAABNQAECn8hAAIOAAgKCxPRFgCZAQAOAAgKCxPRFgCZAQAAAA==.',
Gi='Girthzilla:BAAANQAECgMIBAAAAA==.',
Gl='Glemin:BAAANQADCgEIAQAAAA==.',
Gr='Greyborn:BAAANQADCgUIBQAAAA==.Gryari:BAAANQAECgUIBwAAAA==.',
Gu='Guldaggar:BAABNQAECn8aAAIFAAgK4BWQWAAZAgAFAAgK4BWQWAAZAgAAAA==.',
Gw='Gwiynevere:BAAANQADCgMIAwAAAA==.',
Ha='Haunter:BAAANQADCgIIAgAAAA==.',
He='Hellao:BAABNQAECn8cAAIWAAoKBxCzEwA9AQAWAAoKBxCzEwA9AQAAAA==.Hellmage:BAAANQADCgQIBAAAAA==.',
Hi='Hiroshige:BAAANQADCgQIBAAAAA==.',
Ho='Holysausage:BAAANQADCgYIBgAAAA==.',
Hr='Hrenam:BAAANQAECgUIEwAAAA==.Hrimceald:BAABNQAECn8nAAMRAAoKDBcLDgDuAQARAAoKDBcLDgDuAQAFAAEKAAA8qAAAAAAAAA==.',
Hy='Hylts:BAABNQAECn8iAAIXAAcKlAliCQBeAQAXAAcKlAliCQBeAQAAAA==.',
Il='Illithian:BAAANQAECgMIAwAAAA==.',
Im='Imalockyo:BAAANQAECgQIBQAAAA==.',
Ja='Javi:BAABNQAECn8sAAMCAAoKGSTKBQCWAwACAAoKGSTKBQCWAwANAAQKWSE0ZAB/AQAAAA==.Javiertwo:BAAANQAECgUIBgAAAA==.Javioli:BAAANQAECggIDwABNQAECgoKLAACABkkAA==.',
Ka='Kaladin:BAAANQAECgEIAwABNQAECgoKIQACAA8hAA==.Kariboose:BAAANQABCgIIAgAAAA==.Kassiandra:BAABNQAECn8nAAMEAAkKrxI/dAC7AQAEAAgKaxE/dAC7AQAPAAgK+xBtQwA/AQAAAA==.',
Ke='Kejiabaobei:BAABNQAECn8oAAIJAAoKzyI6DAB8AwAJAAoKzyI6DAB8AwAAAA==.Kevlarprime:BAAANQAECgQICgAAAA==.Kevsterr:BAABNQAECn8rAAIMAAgKBQqNcgDXAAAMAAgKBQqNcgDXAAAAAA==.',
Kh='Khaantu:BAABNQAECn8uAAIYAAoKByXPAQC7AwAYAAoKByXPAQC7AwAAAA==.',
Ko='Koryk:BAAANQAECgYJBgAAAA==.',
Kr='Krein:BAAANQAECgQIBAAAAA==.Krünk:BAABNQAECn8sAAIGAAoKVRvvDADWAgAGAAoKVRvvDADWAgAAAA==.',
La='Lachdanan:BAABNQAECn8XAAIYAAYKXQxmHwCZAAAYAAYKXQxmHwCZAAAAAA==.Lans:BAAANQAECgUIDAAAAA==.Lastritez:BAABNQAECn81AAMPAAoKpBbCCgAyAgAPAAoKpBbCCgAyAgAYAAcKGganQAD1AAAAAA==.',
Le='Leafbeard:BAABNQAECn8iAAMZAAgKORN7BgBLAQAZAAgKORN7BgBLAQAKAAIKABZxTQBvAAAAAA==.',
Li='Lilean:BAABNQAECn8oAAIJAAkK/hxMLgDiAgAJAAkK/hxMLgDiAgAAAA==.',
Lo='Lokka:BAAANQAECgUIEAAAAA==.Lolly:BAABNQAECn8WAAIVAAcKlAgUFwBDAQAVAAcKlAgUFwBDAQAAAA==.Longick:BAAANQADCgIIAgAAAA==.Lormont:BAAANQADCgUIBQAAAA==.Loskember:BAAANQADCgQIBAAAAA==.',
Ly='Lyreshade:BAABNQAECn8wAAIFAAoKphkuBABAAgAFAAoKphkuBABAAgAAAA==.',
['Lÿ']='Lÿcâòñ:BAAANQAECgUICQAAAA==.',
Ma='Madbunny:BAAANQADCgQIBAAAAA==.Madriina:BAAANQADCggIFQAAAA==.Mahrah:BAAANQAECgEIAQAAAA==.Malört:BAAANQABCgQIBQAAAA==.Manchego:BAAANQADCgMIAwAAAA==.Mar:BAAANQAECgYIDgAAAA==.Mazakiel:BAAANQAECgQIBAAAAA==.',
Me='Melevolence:BAABNQAECn8qAAMOAAoKKRHbZAArAgAOAAoKKRHbZAArAgAaAAIKlQSHbwBAAAAAAA==.Mep:BAAANQADCgYIBQABNQAECgUICQAbAAAAAA==.',
Mo='Morticia:BAAANQADCgYICQAAAA==.',
My='Myst:BAAANQADCgEIAQAAAA==.Mythbras:BAAANQADCgYIDQAAAA==.',
['Mù']='Mùfasa:BAABNQAECn8eAAINAAcKrBJiHwDwAAANAAcKrBJiHwDwAAAAAA==.',
Na='Navdrag:BAAANQAECgUJCwAAAA==.Naxria:BAAANQAECgYIDAAAAA==.',
Ne='Necroticnuts:BAAANQADCgYICgAAAA==.Nevera:BAAANQADCgMIAwAAAA==.',
Ni='Nili:BAAANQAECggIAQAAAA==.Nimithriel:BAAANQAECgQIBQAAAA==.',
No='Notwesa:BAAANQAECgMIBQAAAA==.Notweso:BAABNQAECn8tAAISAAoKRiMIAgBUAgASAAoKRiMIAgBUAgAAAA==.Notwezo:BAAANQAECgEIAgAAAA==.',
Or='Oriari:BAAANQADCgcICAAAAA==.Oroki:BAAANQAECgYIDwAAAA==.',
Pa='Panay:BAAANQABCgMIAwAAAA==.',
Po='Poovey:BAACNQAFFH8HAAIUAAQKEQnaMQCFAAAUAAQKEQnaMQCFAAA1AAQKfy0AAhQACgoRH009ANMCABQACgoRH009ANMCAAAA.',
Pu='Purpletoe:BAABNQAECn8bAAMLAAkK9RySNQCRAgALAAgKeBySNQCRAgAcAAEKAAC2gQAoAAAAAA==.Putrificator:BAAANQADCgQIBAAAAA==.',
Py='Pyronae:BAABNQAECn8nAAIOAAkKuhGYFACkAQAOAAkKuhGYFACkAQAAAA==.',
Qi='Qit:BAAANQADCgYICgABNQAECggIHAAdADwiAA==.',
Ra='Rargh:BAAANQAECggIEgAAAA==.',
Re='Rebornhope:BAAANQAECgYIBgABNQAECgoKIQACANYjAA==.Redonkeylous:BAAANQAECgUICwAAAA==.Redonkurus:BAAANQADCgQIBAAAAA==.Rengen:BAABNQAECn8iAAIeAAkKkhZIDQAnAgAeAAkKkhZIDQAnAgAAAA==.Restalkurus:BAAANQADCggIEAAAAA==.Reya:BAAANQAECgYIDgAAAA==.',
Ro='Roft:BAAANQADCggICAAAAA==.',
Ru='Runelord:BAAANQAECgUIBAAAAA==.Ruìn:BAAANQAECgMIAwAAAA==.',
['Rí']='Rían:BAAANQADCgUIBQAAAA==.',
Sa='Saeli:BAAANQAECgcIEQAAAA==.Saeris:BAAANQADCgcIBwAAAA==.Sanamongolos:BAAANQAECgcIDAAAAA==.Saraija:BAAANQAECgUIBgABNQAECgUIDQAbAAAAAA==.Sasinko:BAABNQAECn8jAAIfAAkKJhzLAAD9AQAfAAkKJhzLAAD9AQAAAA==.Sassypants:BAAANQAECgYIBgAAAA==.Sawlrenuk:BAAANQADCgIIAgAAAA==.',
Se='Sentien:BAAANQABCgIIAgAAAA==.Sesshoomaru:BAAANQAECggICAAAAA==.',
Sh='Shadowstripe:BAABNQAECn8gAAIdAAcKuhXPKgDGAQAdAAcKuhXPKgDGAQAAAA==.Shigglez:BAACNQAFFH8HAAIMAAQKIQyCDwDjAAAMAAQKIQyCDwDjAAA1AAQKfyUAAgwACgqPGVApAHQBAAwACgqPGVApAHQBAAAA.Shinìgámi:BAAANQABCgUIAwAAAA==.',
Sl='Slapchop:BAABNQAECn8VAAIQAAgKYxkEHQBvAQAQAAgKYxkEHQBvAQAAAA==.Slop:BAACNQAFFH8eAAIQAAcKBRRLAAB7AQAQAAcKBRRLAAB7AQA1AAQKfzYAAhAACgrgHwkFACsDABAACgrgHwkFACsDAAAA.',
So='Soteria:BAAANQAECgYIEgABNQAFFAMIBwAJALURAA==.',
Su='Sugarpants:BAAANQAECgUIEwAAAA==.',
Sy='Sydnehektori:BAAANQADCgUIBQAAAA==.Sylphrenaa:BAAANQADCggICAAAAA==.',
Te='Tembtree:BAAANQAECgMICAABNQAECgYIFwAaABUOAA==.Temlock:BAABNQAECn8XAAIaAAYKFQ6FBQDPAAAaAAYKFQ6FBQDPAAAAAA==.',
Ti='Tiggerina:BAAANQAECgIIAgAAAA==.',
Tu='Turan:BAAANQAECgMIBAAAAA==.',
Ty='Typhonic:BAAANQAECgUICQAAAA==.Tyrenari:BAAANQADCgEIAQAAAA==.',
Ul='Ultear:BAABNQAECn8eAAMgAAgKTBMbCwC3AAATAAgKNhMkPQDPAQAgAAUKWxQbCwC3AAAAAA==.',
Va='Valysandra:BAAANQAECgQIBAAAAA==.',
Ve='Venthyr:BAAANQAECgMIBAAAAA==.Vetenarae:BAAANQADCggICAABNQAECgcIIgAXAJQJAA==.Vethja:BAAANQAECgMIAwABNQAECgUIDQAbAAAAAA==.',
Vo='Voidhope:BAAANQADCgYICAABNQAECgoKIQACANYjAA==.Volkren:BAABNQAECn8xAAICAAkKsyDWBAAHAgACAAkKsyDWBAAHAgAAAA==.',
Wi='Witherpants:BAAANQAECgcIDQAAAA==.',
Wo='Worshipme:BAAANQAECgMIAwAAAA==.',
Xa='Xandor:BAAANQADCgIIAgABNQAECgoKIQACANYjAA==.Xaos:BAABNQAECn8iAAIhAAoKtBt6AAANAgAhAAoKtBt6AAANAgAAAA==.',
Xi='Xiaowugui:BAAANQAECggIDgAAAA==.',
Ya='Yarrick:BAABNQAECn8jAAIRAAgKihU/YQDqAQARAAgKihU/YQDqAQAAAA==.',
Yu='Yukihime:BAAANQAECgcIDgABNQAFFAUICAAMAFEXAA==.',
Ze='Zelkiri:BAABNQAECn8YAAIWAAYKgAyXIwDZAAAWAAYKgAyXIwDZAAAAAA==.Zethlahr:BAABNQAECn8xAAMcAAoKEB9HAQCXAgAcAAoKEB9HAQCXAgALAAEKqxG38wBJAAAAAA==.',
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
