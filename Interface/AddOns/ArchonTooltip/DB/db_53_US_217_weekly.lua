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

local lookup = {'Mage-Fire','DeathKnight-Blood','DeathKnight-Frost','Paladin-Holy','Shaman-Elemental','Warlock-Affliction','Evoker-Preservation','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Druid-Guardian','Warlock-Destruction','Warlock-Demonology','Priest-Holy','Mage-Arcane','DeathKnight-Unholy','Druid-Balance','Paladin-Retribution','Warrior-Protection','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Arms','Mage-Frost','Shaman-Enhancement','Paladin-Protection','Druid-Feral','Evoker-Devastation','Unknown-Unknown','Priest-Shadow','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','DemonHunter-Vengeance','Rogue-Outlaw',}
local provider = {region='US',realm='TheVentureCo',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abanados:BAABNQAECn8qAAIBAAkKrQ9sAQC3AQABAAkKrQ9sAQC3AQAAAA==.',
Ae='Aethelra:BAAANQAECgUICQAAAA==.',
Ak='Aken:BAAANQADCgcIBwAAAA==.',
Al='Alivasticus:BAACNQAFFH8GAAICAAMK6AoJGwDCAAACAAMK6AoJGwDCAAA1AAQKfxoAAwIACAp+D6g/AOIAAAIACAp+D6g/AOIAAAMAAQoAAAAAAAAAAAE1AAUUBggLAAQAFxAA.',
Am='Amme:BAAANQAECgQICgAAAA==.',
An='Animorpha:BAAANQADCgYIBgAAAA==.',
As='Asonda:BAEANQAECgUIDQAAAA==.',
Ba='Badvision:BAAANQADCgYICgAAAA==.Bagofluff:BAAANQAECgMIBAABNQAFFAYIFgAFAFIUAA==.Bairon:BAAANQADCgUIBAAAAA==.Bajamama:BAAANQADCgMIAQAAAA==.Baobeikejia:BAABNQAECn8cAAIGAAoK1A8ABADKAQAGAAoK1A8ABADKAQAAAA==.',
Be='Betiff:BAAANQAECgUIEgAAAA==.Betrellis:BAAANQAECgUIBgAAAA==.',
Bl='Bloodydraco:BAABNQAECn8yAAIHAAkK5BqQBwBdAgAHAAkK5BqQBwBdAgAAAA==.',
Ca='Cakebro:BAABNQAECn8cAAQIAAoKAxZiPwBYAQAJAAgKDxNMCQCmAQAIAAYKsxZiPwBYAQAKAAEKcBZWSAFOAAAAAA==.Caliâ:BAAANQAECgYICAAAAA==.Camembert:BAABNQAECn8pAAILAAoK/SP5AwDkAgALAAoK/SP5AwDkAgAAAA==.Carmellion:BAABNQAECn8UAAMMAAYKmQQeSwCeAAANAAYKmQRx7wDrAAAMAAUK2wEeSwCeAAAAAA==.Casii:BAABNQAECn8jAAIOAAgKuQ0CdgC5AQAOAAgKuQ0CdgC5AQAAAA==.',
Ch='Chrollo:BAAANQAECgMIAwABNQAECgoKNAAPANUgAA==.Chubingus:BAABNQAECn8aAAIQAAoKQx4tGgDwAgAQAAoKQx4tGgDwAgAAAA==.Chufeng:BAACNQAFFH8IAAIKAAQKtREVDQDsAAAKAAQKtREVDQDsAAA1AAQKfygAAgoACAraIlQpAPMCAAoACAraIlQpAPMCAAAA.Chumlemagne:BAAANQADCgMJAwAAAA==.',
Co='Cowtastrophy:BAABNQAECn8VAAIRAAYKBAhbRACyAAARAAYKBAhbRACyAAAAAA==.',
Cr='Crizadin:BAAANQABCgYIDAABNQAECgkJKwAKAMwiAA==.Cryp:BAAANQAECgYIEAAAAA==.',
Cy='Cynikal:BAAANQADCgEIAQABNQAECggIIwAOALkNAA==.',
Da='Daemenar:BAAANQAECgQIBQAAAA==.Danaki:BAAANQAECgEIAQABNQAECggIKAANAAsTAA==.Danorace:BAAANQAECgQIBgAAAA==.Darkcurve:BAABNQAECn8hAAISAAoKMhXmSgDWAQASAAoKMhXmSgDWAQAAAA==.Darkhope:BAABNQAECn8rAAICAAoKACT4AwCxAwACAAoKACT4AwCxAwAAAA==.Darla:BAAANQAECgEIAQAAAA==.Dawnest:BAAANQAECgMIAwAAAA==.',
De='Deija:BAAANQAECgUIDgAAAA==.Dekoo:BAABNQAECn8rAAITAAkKgh8yBgAaAgATAAkKgh8yBgAaAgAAAA==.',
Do='Docious:BAAANQADCgYIDQAAAA==.',
Dr='Drakula:BAAANQADCgMIAwAAAA==.Dreadfang:BAABNQAECn83AAIQAAoKXiCMCQCJAgAQAAoKXiCMCQCJAgAAAA==.Droka:BAABNQAECn8nAAIUAAkKrh4xKgC6AgAUAAkKrh4xKgC6AgAAAA==.',
Eu='Eurotophobia:BAABNQAECn8ZAAISAAgK2RAsewBbAQASAAgK2RAsewBbAQAAAA==.',
Ex='Exodia:BAABNQAECn8ZAAIKAAcKiRLziwDyAQAKAAcKiRLziwDyAQAAAA==.',
Fa='Faedeynna:BAAANQADCgIIAgAAAA==.',
Fh='Fhyllo:BAABNQAECn8iAAMVAAkKmRHeHABGAQAVAAkKmRHeHABGAQAWAAEKkwOBbwAkAAAAAA==.',
Fl='Flaaffy:BAABNQAECn8nAAIFAAoK9xEKUQA0AgAFAAoK9xEKUQA0AgAAAA==.',
Fo='Follaglas:BAABNQAECn8lAAIKAAkK9B4FGQA1AwAKAAkK9B4FGQA1AwAAAA==.Fooberdabber:BAAANQABCgUICAAAAA==.',
Ga='Gabriel:BAAANQADCgUIBQAAAA==.Gainor:BAAANQAECgEIAQAAAA==.Gairen:BAAANQAECgcICQAAAA==.Galadisis:BAABNQAECn80AAMTAAoKzSNABQAkAwATAAkKgyNABQAkAwAXAAoK0hw1XAB3AgAAAA==.Gandaelf:BAABNQAECn80AAQPAAoK1SC7LQAyAwAPAAoKnCC7LQAyAwAYAAIKTCPEJgC8AAABAAEKAACsDAA9AAAAAA==.',
Gh='Ghuldana:BAABNQAECn8oAAINAAgKCxPISwCBAQANAAgKCxPISwCBAQAAAA==.',
Gi='Girthzilla:BAAANQAECgUICQAAAA==.',
Gl='Glemin:BAAANQADCgEIAQAAAA==.',
Gr='Greyborn:BAAANQADCgUIBQAAAA==.Gryari:BAAANQAECgUIBwAAAA==.',
Gu='Guldaggar:BAABNQAECn8aAAIFAAgK4BWQWAAZAgAFAAgK4BWQWAAZAgAAAA==.',
Gw='Gwiynevere:BAAANQADCgMIAwAAAA==.',
Ha='Haunter:BAAANQADCgIIAgAAAA==.',
He='Hellao:BAABNQAECn8cAAIRAAoKBxDmPAAPAgARAAoKBxDmPAAPAgAAAA==.Hellmage:BAAANQADCgQIBAAAAA==.',
Hi='Hiroshige:BAAANQADCgQIBAAAAA==.',
Ho='Holysausage:BAAANQADCgYIBgAAAA==.',
Hr='Hrenam:BAAANQAECgUIEwAAAA==.Hrimceald:BAABNQAECn8wAAMUAAoKPho5HgBRAgAUAAoKPho5HgBRAgAFAAYK3hNxXAD4AAAAAA==.',
Hy='Hylts:BAABNQAECn8oAAIZAAcKlAnaEwBJAQAZAAcKlAnaEwBJAQAAAA==.',
Il='Illithian:BAAANQAECgQIBAAAAA==.',
Im='Imalockyo:BAAANQAECgQIBQAAAA==.',
Ja='Javi:BAABNQAECn8yAAMCAAoKGSTKBQCWAwACAAoKGSTKBQCWAwAQAAgKbx/zGACwAQAAAA==.Javiertwo:BAAANQAECgYICgAAAA==.Javioli:BAAANQAECggIEwABNQAECgoKMgACABkkAA==.',
Ka='Kaladin:BAAANQAECgEIAwABNQAECgoKJQACACQkAA==.Kariboose:BAAANQABCgIIAgAAAA==.Kassiandra:BAABNQAECn8sAAMEAAkKpBA/dAC7AQAEAAkKpBA/dAC7AQASAAgK+xBlmgAeAQAAAA==.',
Ke='Kejiabaobei:BAABNQAECn8uAAIKAAoKeCU6DAB8AwAKAAoKeCU6DAB8AwAAAA==.Kevlarprime:BAAANQAECgcIDgAAAA==.Kevsterr:BAABNQAECn8yAAIPAAkK2gn75gC7AQAPAAkK2gn75gC7AQAAAA==.',
Kh='Khaantu:BAABNQAECn8uAAIaAAoKByXPAQC7AwAaAAoKByXPAQC7AwAAAA==.',
Ko='Koryk:BAAANQAECgYJBgAAAA==.',
Kr='Krein:BAAANQAECgQIBAAAAA==.Krünk:BAABNQAECn8wAAIHAAoKARzvDADWAgAHAAoKARzvDADWAgAAAA==.',
La='Lachdanan:BAABNQAECn8cAAIaAAYKVA2oQwDkAAAaAAYKVA2oQwDkAAAAAA==.Lans:BAAANQAECgcIEQAAAA==.Lastritez:BAABNQAECn85AAMSAAoKKxc6PAAJAgASAAoKKxc6PAAJAgAaAAcKGganQAD1AAAAAA==.',
Le='Leafbeard:BAABNQAECn8oAAMbAAkKihP8CwB1AQAbAAkKihP8CwB1AQALAAIKABZxTQBvAAAAAA==.',
Li='Lilean:BAABNQAECn8oAAIKAAkK/hxMLgDiAgAKAAkK/hxMLgDiAgAAAA==.',
Lo='Lokka:BAABNQAECn8ZAAMUAAYKiBSfsAAOAQAUAAUK0xOfsAAOAQAZAAUKQgjQKgC6AAAAAA==.Lolly:BAABNQAECn8WAAIYAAcKlAgUFwBDAQAYAAcKlAgUFwBDAQAAAA==.Longick:BAAANQADCgIIAgAAAA==.Lormont:BAAANQADCgUIBQAAAA==.Loskember:BAAANQADCgQIBAAAAA==.',
Ly='Lyreshade:BAABNQAECn82AAIFAAoKUhyDEwBwAgAFAAoKUhyDEwBwAgAAAA==.',
['Lÿ']='Lÿcâòñ:BAAANQAECgUICQAAAA==.',
Ma='Madbunny:BAAANQADCgQIBAAAAA==.Madriina:BAAANQADCggIFQAAAA==.Mahrah:BAAANQAECgEIAQAAAA==.Malört:BAAANQABCgQIBQAAAA==.Manchego:BAAANQADCgMIAwAAAA==.Mar:BAABNQAECn8WAAIcAAYKNxGHDgDtAAAcAAYKNxGHDgDtAAAAAA==.Mazakiel:BAAANQAECgQIBAAAAA==.',
Me='Melevolence:BAABNQAECn8wAAMNAAoKPhHbZAArAgANAAoKPhHbZAArAgAMAAIKlQSHbwBAAAAAAA==.Mep:BAAANQADCgYIBQABNQAECgYICwAdAAAAAA==.',
Mo='Morticia:BAAANQADCgYICQAAAA==.',
My='Myst:BAAANQADCgEIAQAAAA==.Mythbras:BAAANQADCgYIDQAAAA==.',
['Mù']='Mùfasa:BAABNQAECn8fAAIQAAgKfRHbLQAXAQAQAAgKfRHbLQAXAQAAAA==.',
Na='Navdrag:BAAANQAECgUJCwAAAA==.Naxria:BAAANQAECgYIDAAAAA==.',
Ne='Necroticnuts:BAAANQADCgYICgAAAA==.Nevera:BAAANQADCgMIAwAAAA==.',
Ni='Nili:BAAANQAECggIAQAAAA==.Nimithriel:BAAANQAECgQIBQAAAA==.',
No='Nojzotoi:BAAANQABCgMIAwAAAA==.Notwesa:BAAANQAECgMIBQAAAA==.Notweso:BAABNQAECn8zAAIVAAoKUSNwBACOAwAVAAoKUSNwBACOAwAAAA==.Notwezo:BAAANQAECgEIAgAAAA==.',
Or='Oriari:BAAANQADCgcICAAAAA==.Oroki:BAABNQAECn8YAAILAAYKZQdDNACPAAALAAYKZQdDNACPAAAAAA==.',
Pa='Panay:BAAANQABCgMIAwAAAA==.',
Po='Poovey:BAACNQAFFH8HAAIXAAQKEQnaMQCFAAAXAAQKEQnaMQCFAAA1AAQKfzYAAhcACgojHz0oAEICABcACgojHz0oAEICAAAA.',
Pu='Purpletoe:BAABNQAECn8bAAMOAAkK9RySNQCRAgAOAAgKeBySNQCRAgAeAAEKAAC2gQAoAAAAAA==.Putrificator:BAAANQADCgQIBAAAAA==.',
Py='Pyronae:BAABNQAECn8sAAINAAkK9xHVOgC+AQANAAkK9xHVOgC+AQAAAA==.',
Qi='Qit:BAAANQADCgYICgABNQAECgkJIgAfAJUgAA==.',
Ra='Rargh:BAABNQAECn8ZAAMKAAgKKQ1vyQBvAQAKAAgKGw1vyQBvAQAJAAQKAAxnCQC5AAAAAA==.',
Re='Rebornhope:BAAANQAECgYIBgABNQAECgoKKwACAAAkAA==.Redonkeylous:BAAANQAECgYIEQAAAA==.Redonkurus:BAAANQADCgUICwAAAA==.Rengen:BAABNQAECn8nAAIgAAkKPhdIDQAnAgAgAAkKPhdIDQAnAgAAAA==.Restalkurus:BAAANQADCggIEAAAAA==.Reya:BAABNQAECn8WAAIQAAYKkg5sNADxAAAQAAYKkg5sNADxAAAAAA==.',
Ro='Roft:BAAANQADCggICAAAAA==.',
Ru='Runelord:BAAANQAECgUIBAAAAA==.Ruìn:BAAANQAECgMIAwAAAA==.',
['Rí']='Rían:BAAANQAECgEIAQAAAA==.',
Sa='Saeli:BAAANQAECgcIEQAAAA==.Saeris:BAAANQADCgcIBwAAAA==.Sanamongolos:BAAANQAECggIDgAAAA==.Saraija:BAAANQAECgUIBgABNQAECgUIDgAdAAAAAA==.Sasinko:BAABNQAECn8jAAIGAAkKJhxHBACdAgAGAAkKJhxHBACdAgAAAA==.Sassypants:BAAANQAECgYIBgAAAA==.Sawlrenuk:BAAANQADCgIIAgAAAA==.',
Se='Sentien:BAAANQABCgIIAgAAAA==.Sesshoomaru:BAAANQAECggICAAAAA==.',
Sh='Shadowstripe:BAABNQAECn8gAAIfAAcKuhXPKgDGAQAfAAcKuhXPKgDGAQAAAA==.Shigglez:BAACNQAFFH8KAAIPAAQKUhQQFgDxAAAPAAQKUhQQFgDxAAA1AAQKfyoAAg8ACgqPGaddAJQBAA8ACgqPGaddAJQBAAAA.Shinìgámi:BAAANQABCgUIAwAAAA==.',
Sl='Slapchop:BAABNQAECn8VAAITAAgKYxkEHQBvAQATAAgKYxkEHQBvAQAAAA==.Slop:BAACNQAFFH8eAAITAAcKBRSfAABmAQATAAcKBRSfAABmAQA1AAQKf0AAAhMACgrqIpwBAB0DABMACgrqIpwBAB0DAAAA.',
So='Soteria:BAAANQAECgYIEgABNQAFFAQICAAKALURAA==.',
Su='Sugarpants:BAABNQAECn8ZAAIhAAYKORMqFwAJAQAhAAYKORMqFwAJAQAAAA==.',
Sy='Sydnehektori:BAAANQADCgUIBQAAAA==.Sylphrenaa:BAAANQADCggICAAAAA==.',
Te='Tembtree:BAAANQAECgMICwABNQAECgYIHAAMAFYPAA==.Temlock:BAABNQAECn8cAAIMAAYKVg+pCwDDAAAMAAYKVg+pCwDDAAAAAA==.',
Ti='Tiggerina:BAAANQAECgIIAgAAAA==.',
Tu='Turan:BAAANQAECgMIBAAAAA==.',
Ty='Typhonic:BAAANQAECgYICwAAAA==.Tyrenari:BAAANQADCgEIAQAAAA==.',
Ul='Ultear:BAABNQAECn8jAAMWAAkKcxIkPQDPAQAWAAkKYBIkPQDPAQAiAAUKWxT9EwCiAAAAAA==.',
Va='Valysandra:BAAANQAECgYICQAAAA==.',
Ve='Venthyr:BAAANQAECgMIBAAAAA==.Vetenarae:BAAANQADCggICAABNQAECgcIKAAZAJQJAA==.Vethja:BAAANQAECgUIBwABNQAECgUIDgAdAAAAAA==.',
Vo='Voidhope:BAAANQADCgYICAABNQAECgoKKwACAAAkAA==.Volkren:BAABNQAECn80AAICAAkKPSF/FgD5AgACAAkKPSF/FgD5AgAAAA==.',
Wi='Witherpants:BAAANQAECgcIEQAAAA==.',
Wo='Worshipme:BAAANQAECgMIAwAAAA==.',
Xa='Xandor:BAAANQADCgIIAgABNQAECgoKKwACAAAkAA==.Xaos:BAABNQAECn8rAAIjAAoKkx6sAAC/AgAjAAoKkx6sAAC/AgAAAA==.',
Xi='Xiaowugui:BAAANQAECggIDwAAAA==.',
Ya='Yarrick:BAABNQAECn8pAAIUAAkKwRbWJQAfAgAUAAkKwRbWJQAfAgAAAA==.',
Yu='Yukihime:BAABNQAECn8WAAMCAAkKbhEwLwAxAQACAAkKbhEwLwAxAQAQAAEKMQYz7QAoAAABNQAFFAUIEgAPAEkfAA==.',
Ze='Zelkiri:BAABNQAECn8cAAIRAAYKgAxMPgDMAAARAAYKgAxMPgDMAAAAAA==.Zethlahr:BAABNQAECn83AAMeAAoKEB9MCQBkAgAeAAoKEB9MCQBkAgAOAAEKqxG38wBJAAAAAA==.',
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
