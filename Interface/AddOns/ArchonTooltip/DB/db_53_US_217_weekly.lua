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

local lookup = {'Mage-Fire','DeathKnight-Blood','DeathKnight-Frost','Paladin-Holy','Priest-Holy','Priest-Discipline','Shaman-Elemental','Warlock-Affliction','Shaman-Restoration','Evoker-Preservation','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Druid-Guardian','Warlock-Destruction','Warlock-Demonology','Mage-Arcane','DeathKnight-Unholy','Druid-Balance','Paladin-Retribution','Warrior-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Arms','Mage-Frost','Shaman-Enhancement','Rogue-Assassination','Paladin-Protection','Rogue-Subtlety','Druid-Feral','Evoker-Devastation','Unknown-Unknown','Priest-Shadow','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','DemonHunter-Vengeance','Rogue-Outlaw',}
local provider = {region='US',realm='TheVentureCo',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abanados:BAABNQAECn8sAAIBAAoKcg91AgDBAQABAAoKcg91AgDBAQAAAA==.',
Ae='Aethelra:BAAANQAECgYICgAAAA==.',
Ak='Aken:BAAANQADCgcIBwAAAA==.',
Al='Alivasticus:BAACNQAFFH8GAAICAAMK6AoJGwDCAAACAAMK6AoJGwDCAAA1AAQKfxoAAwIACAp+D1BXANQAAAIACAp+D1BXANQAAAMAAQoAAAAAAAAAAAE1AAUUBwgMAAQAxhAA.',
Am='Amme:BAAANQAECgQIEQAAAA==.',
An='Animorpha:BAAANQADCgYIBgAAAA==.',
As='Asonda:BAEBNQAECn8aAAMFAAkK8RjWLwBvAgAFAAkK8RjWLwBvAgAGAAEKFRVaJgA9AAAAAA==.',
Ba='Badvision:BAAANQADCgYICgAAAA==.Bagofluff:BAAANQAECgMIBAABNQAFFAcIFwAHAPsQAA==.Bajamama:BAAANQADCgMIAQAAAA==.Baobeikejia:BAABNQAECn8gAAIIAAoK+w9jCgDRAQAIAAoK+w9jCgDRAQAAAA==.',
Be='Betiff:BAABNQAECn8aAAMJAAkKjBtsKwBjAgAJAAgKax1sKwBjAgAHAAUKrA4RowBPAQAAAA==.Betrellis:BAAANQAECgQIBgAAAA==.',
Bl='Bloodydraco:BAABNQAECn84AAIKAAkKJhwgCwBlAgAKAAkKJhwgCwBlAgAAAA==.',
Ca='Cakebro:BAABNQAECn8eAAQLAAoKAxZiPwBYAQAMAAgKDxNMCQCmAQALAAcKsxZiPwBYAQANAAEKcBZWSAFOAAAAAA==.Caliâ:BAAANQAECgYIDgAAAA==.Camembert:BAABNQAECn8vAAIOAAoKNiSpBQA9AwAOAAoKNiSpBQA9AwAAAA==.Carmellion:BAABNQAECn8UAAMPAAYKmQQeSwCeAAAQAAYKmQRx7wDrAAAPAAUK2wEeSwCeAAAAAA==.Casii:BAABNQAECn8rAAIFAAoKuA4CdgC5AQAFAAoKuA4CdgC5AQAAAA==.',
Ch='Chalino:BAAANQABCgMIAwAAAA==.Chrollo:BAAANQAECgMIAwABNQAECgoKOwARAGshAA==.Chubingus:BAABNQAECn8fAAISAAoK/B8tGgDwAgASAAoK/B8tGgDwAgAAAA==.Chufeng:BAACNQAFFH8MAAINAAQKMBhFEQDyAAANAAQKMBhFEQDyAAA1AAQKfzMAAg0ACQqiIxYMACQDAA0ACQqiIxYMACQDAAAA.Chumlemagne:BAAANQADCgMJAwAAAA==.',
Co='Cowtastrophy:BAABNQAECn8dAAITAAkKyQjmNgBFAQATAAkKyQjmNgBFAQAAAA==.',
Cr='Crizadin:BAAANQABCgYIDAABNQAECgkJLAANABkjAA==.Cryp:BAAANQAECgYIEAAAAA==.',
Cy='Cynikal:BAAANQADCgEIAQABNQAECgoKKwAFALgOAA==.',
Da='Daemenar:BAAANQAECgQIBQAAAA==.Danaki:BAAANQAECgUIBgABNQAECgkJMgAQAE8VAA==.Danorace:BAAANQAECgUIBgAAAA==.Darkcurve:BAABNQAECn8uAAIUAAoKHRiOSwA4AgAUAAoKHRiOSwA4AgAAAA==.Darkhope:BAABNQAECn85AAICAAoKjCT4AwCxAwACAAoKjCT4AwCxAwAAAA==.Darla:BAAANQAECgEIAQAAAA==.Dawnest:BAAANQAECgMIAwAAAA==.',
De='Deija:BAAANQAECgcIEAAAAA==.Dekoo:BAABNQAECn8tAAIVAAoKfB8YCABOAgAVAAoKfB8YCABOAgAAAA==.',
Do='Docious:BAAANQADCgYIDQAAAA==.',
Dr='Drakula:BAAANQADCgMIAwAAAA==.Dreadfang:BAABNQAECn89AAISAAoKLCHlDACdAgASAAoKLCHlDACdAgAAAA==.Droka:BAABNQAECn8pAAIJAAoK2x4xKgC6AgAJAAoK2x4xKgC6AgAAAA==.',
Eu='Eurotophobia:BAABNQAECn8dAAIUAAgK2RCbtABRAQAUAAgK2RCbtABRAQAAAA==.',
Ex='Exodia:BAABNQAECn8bAAINAAgKuxLziwDyAQANAAgKuxLziwDyAQAAAA==.',
Fa='Faedeynna:BAAANQADCgIIAgAAAA==.',
Fh='Fhyllo:BAABNQAECn8kAAMWAAkKIxIKMADBAQAWAAkKIxIKMADBAQAXAAEKkwM6iAAgAAAAAA==.',
Fl='Flaaffy:BAABNQAECn8pAAIHAAoKVhQKUQA0AgAHAAoKVhQKUQA0AgAAAA==.',
Fo='Follaglas:BAABNQAECn8lAAINAAkK9B4FGQA1AwANAAkK9B4FGQA1AwAAAA==.Fooberdabber:BAAANQABCgUICAAAAA==.',
Ga='Gabriel:BAAANQADCgUIBQAAAA==.Gainor:BAAANQAECgEIAQAAAA==.Gairen:BAAANQAECgYICQAAAA==.Galadisis:BAABNQAECn86AAMVAAoKzSNABQAkAwAVAAkKgyNABQAkAwAYAAoK0hyHQwAnAgAAAA==.Gandaelf:BAABNQAECn87AAQRAAoKayG7LQAyAwARAAoKMiG7LQAyAwAZAAMKpB0tHwDJAAABAAEKAACsDAA9AAAAAA==.',
Gh='Ghuldana:BAABNQAECn8yAAIQAAkKTxXoSgDhAQAQAAkKTxXoSgDhAQAAAA==.',
Gi='Girthzilla:BAAANQAECgUIDwAAAA==.',
Gl='Glemin:BAAANQADCgEIAQAAAA==.',
Gr='Greyborn:BAAANQADCgUIBQAAAA==.Gryari:BAAANQAECgYIBwAAAA==.',
Gu='Guldaggar:BAABNQAECn8aAAIHAAgK4BWQWAAZAgAHAAgK4BWQWAAZAgAAAA==.',
Gw='Gwiynevere:BAAANQADCgMIAwAAAA==.',
Ha='Haunter:BAAANQADCgIIAgAAAA==.',
He='Hellao:BAABNQAECn8cAAITAAoKBxDmPAAPAgATAAoKBxDmPAAPAgAAAA==.Hellmage:BAAANQADCgQIBAAAAA==.',
Hi='Hiroshige:BAAANQADCgQIBAAAAA==.',
Ho='Holysausage:BAAANQADCgYIBgAAAA==.',
Hr='Hrenam:BAAANQAECgUIEwAAAA==.Hrimceald:BAABNQAECn8+AAMJAAoKjRtqJgB/AgAJAAoKjRtqJgB/AgAHAAYK3hPogwDxAAAAAA==.',
Hy='Hylts:BAABNQAECn8vAAIaAAcKNAqbGgBSAQAaAAcKNAqbGgBSAQAAAA==.',
Il='Illithian:BAAANQAECgUIBQAAAA==.',
Im='Imalockyo:BAAANQAECgQIBQAAAA==.',
Ja='Javi:BAABNQAECn8+AAMCAAoKcCXKBQCWAwACAAoKcCXKBQCWAwASAAgKOSLwEwBDAgAAAA==.Javiertwo:BAABNQAECn8dAAIbAAkKrBRZDgDVAQAbAAkKrBRZDgDVAQAAAA==.Javioli:BAABNQAECn8hAAQcAAkK8iBBFABiAgAcAAYK9yNBFABiAgAUAAcKEBw1ZQD1AQAEAAIKlQgH3ABPAAABNQAECgoKPgACAHAlAA==.',
Ka='Kaladin:BAAANQAECgEIAwABNQAFFAIIBgACABAZAA==.Kariboose:BAAANQABCgIIAgAAAA==.Kassiandra:BAABNQAECn8uAAMEAAoKqRI/dAC7AQAEAAkKpBA/dAC7AQAUAAoKjw/mngB6AQAAAA==.',
Ke='Kejiabaobei:BAABNQAECn8wAAINAAoKoiU6DAB8AwANAAoKoiU6DAB8AwAAAA==.Kevlarprime:BAAANQAECgcIEwAAAA==.Kevsterr:BAABNQAECn85AAIRAAoKPgqopABJAQARAAoKPgqopABJAQAAAA==.',
Kh='Khaantu:BAABNQAECn8uAAIcAAoKByXPAQC7AwAcAAoKByXPAQC7AwAAAA==.',
Ko='Koryk:BAAANQAECgYJBgAAAA==.',
Kr='Krein:BAAANQAECgQIBAAAAA==.Krünk:BAABNQAECn82AAIKAAoKARzvDADWAgAKAAoKARzvDADWAgAAAA==.',
Kw='Kwahalli:BAAANQABCgIIAgAAAA==.',
La='Lachdanan:BAABNQAECn8lAAIcAAkKxQraKAAWAQAcAAkKxQraKAAWAQAAAA==.Lans:BAABNQAECn8XAAMdAAgK4g90UQChAQAdAAgKgQ90UQChAQAbAAUKEwr9LgDLAAAAAA==.Lastritez:BAABNQAECn9KAAMUAAoKjBnFSwA3AgAUAAoKjBnFSwA3AgAcAAcKGganQAD1AAAAAA==.',
Le='Leafbeard:BAABNQAECn8xAAMeAAkKlBrCBwBiAgAeAAkKlBrCBwBiAgAOAAIKABZxTQBvAAAAAA==.',
Li='Lilean:BAABNQAECn8oAAINAAkK/hxMLgDiAgANAAkK/hxMLgDiAgAAAA==.',
Lo='Lokka:BAABNQAECn8iAAMaAAkKlg05FAC5AQAaAAkKlg05FAC5AQAJAAUK0xOfsAAOAQAAAA==.Lolly:BAABNQAECn8WAAIZAAcKlAgUFwBDAQAZAAcKlAgUFwBDAQAAAA==.Longick:BAAANQADCgIIAgAAAA==.Lormont:BAAANQADCgUIBQAAAA==.Loskember:BAAANQADCgQIBAAAAA==.',
Ly='Lyreshade:BAABNQAECn87AAIHAAoKZxzTIQBWAgAHAAoKZxzTIQBWAgAAAA==.',
['Lÿ']='Lÿcâòñ:BAAANQAECgYICQAAAA==.',
Ma='Madbunny:BAAANQADCgQIBAAAAA==.Madriina:BAAANQADCggIFQAAAA==.Mahrah:BAAANQAECgEIAQAAAA==.Malignä:BAAANQADCgMIBAAAAA==.Malört:BAAANQABCgQIBQAAAA==.Manchego:BAAANQADCgMIAwAAAA==.Mar:BAABNQAECn8fAAIfAAkKGBGHCgCuAQAfAAkKGBGHCgCuAQAAAA==.Mazakiel:BAAANQAECgQIBAAAAA==.',
Me='Melevolence:BAABNQAECn82AAMQAAoKaxHbZAArAgAQAAoKaxHbZAArAgAPAAIKlQSHbwBAAAAAAA==.Mep:BAAANQADCgYIBQABNQAECgUICwAgAAAAAA==.',
Mo='Morticia:BAAANQADCgYICQAAAA==.',
My='Myst:BAAANQADCgEIAQAAAA==.',
['Mù']='Mùfasa:BAABNQAECn8gAAISAAgKfREtYQCLAQASAAgKfREtYQCLAQAAAA==.',
Na='Navdrag:BAAANQAECgUJCwAAAA==.Naxria:BAAANQAECgYIDAAAAA==.',
Ne='Necroticnuts:BAAANQADCgYICgAAAA==.Nevera:BAAANQADCgMIAwAAAA==.',
Ni='Nili:BAAANQAECggIAQAAAA==.Nimithriel:BAAANQAECgQIBQAAAA==.',
No='Nojzotoi:BAAANQABCgMIAwAAAA==.Notwesa:BAAANQAECgMIBQAAAA==.Notweso:BAABNQAECn85AAIWAAoKeCRwBACOAwAWAAoKeCRwBACOAwAAAA==.Notwezo:BAAANQAECgEIAgAAAA==.',
Or='Oriari:BAAANQADCgcICAAAAA==.Oroki:BAABNQAECn8hAAIOAAkK6QfVLwAAAQAOAAkK6QfVLwAAAQAAAA==.',
Pa='Panay:BAAANQABCgMIAwAAAA==.',
Po='Poovey:BAACNQAFFH8IAAIYAAUK8QuzIwCTAAAYAAUK8QuzIwCTAAA1AAQKfz4AAhgACgpWHyovAHQCABgACgpWHyovAHQCAAAA.',
Pu='Purpletoe:BAABNQAECn8bAAMFAAkK9RySNQCRAgAFAAgKeBySNQCRAgAhAAEKAAC2gQAoAAAAAA==.Putrificator:BAAANQADCgQIBAAAAA==.',
Py='Pyronae:BAABNQAECn8uAAIQAAoKaxEBTADdAQAQAAoKaxEBTADdAQAAAA==.',
Qi='Qit:BAAANQADCgYICgABNQAECgkJJQAiAJUgAA==.',
Ra='Rargh:BAABNQAECn8hAAMNAAoK4RIucgC/AQANAAoK4RIucgC/AQAMAAQKAAwnDQCuAAAAAA==.',
Re='Rebornhope:BAAANQAECgYIBgABNQAECgoKOQACAIwkAA==.Redonkeylous:BAABNQAECn8bAAMcAAgKGw1YJAA2AQAcAAgKGw1YJAA2AQAUAAEKdAcijwEwAAAAAA==.Redonkurus:BAAANQAECgYIDQAAAA==.Rengen:BAABNQAECn8pAAIjAAoKfRdIDQAnAgAjAAoKfRdIDQAnAgAAAA==.Restalkurus:BAAANQADCggIEAAAAA==.Reya:BAABNQAECn8eAAISAAkKqg7PJQCeAQASAAkKqg7PJQCeAQAAAA==.',
Ro='Roft:BAAANQADCggICAAAAA==.',
Ru='Runelord:BAAANQAECgcIBAAAAA==.Ruìn:BAAANQAECgMIAwAAAA==.',
['Rí']='Rían:BAAANQAECgEIAQAAAA==.',
Sa='Saeli:BAAANQAECgcIEQAAAA==.Saeris:BAAANQADCgcIBwAAAA==.Sanamongolos:BAABNQAECn8hAAIEAAoKZx50EAAsAwAEAAoKZx50EAAsAwAAAA==.Saraija:BAAANQAECgYICgABNQAECgcIEAAgAAAAAA==.Sasinko:BAABNQAECn8pAAIIAAoKrBpHBACdAgAIAAoKrBpHBACdAgAAAA==.Sassypants:BAAANQAECgYIBgAAAA==.Sawlrenuk:BAAANQADCgIIAgAAAA==.',
Se='Sentien:BAAANQABCgIIAgAAAA==.Sesshoomaru:BAAANQAECggICAAAAA==.',
Sh='Shadowstripe:BAABNQAECn8lAAIiAAkKtBPPKgDGAQAiAAkKtBPPKgDGAQAAAA==.Shigglez:BAACNQAFFH8PAAIRAAUKiRrzHQD3AAARAAUKiRrzHQD3AAA1AAQKfywAAhEACgpHGqiRAFwCABEACgpHGqiRAFwCAAAA.Shinìgámi:BAAANQABCgUIAwAAAA==.',
Sl='Slapchop:BAABNQAECn8WAAIVAAgKYxkEHQBvAQAVAAgKYxkEHQBvAQAAAA==.Slop:BAACNQAFFH8gAAIVAAgKSRO9AACcAQAVAAgKSRO9AACcAQA1AAQKf1QAAhUACgqTI2QCACUDABUACgqTI2QCACUDAAAA.',
So='Soteria:BAABNQAECn8cAAIYAAYKchSdiQBbAQAYAAYKchSdiQBbAQABNQAFFAQIDAANADAYAA==.',
Su='Sugarpants:BAABNQAECn8oAAIkAAgKWBR9EwC2AQAkAAgKWBR9EwC2AQAAAA==.Summit:BAAANQAECgUICAAAAA==.',
Sy='Sydnehektori:BAAANQADCgUIBQAAAA==.Sylphrenaa:BAAANQADCggICAAAAA==.',
Te='Tembtree:BAABNQAECn8WAAITAAgK8wyFPgAcAQATAAgK8wyFPgAcAQAAAA==.Temlock:BAABNQAECn8lAAIPAAkKMw7+BgBUAQAPAAkKMw7+BgBUAQABNQAECggIFgATAPMMAA==.',
Ti='Tiggerina:BAAANQAECgIIAgAAAA==.',
Tr='Treebones:BAAANQADCgEIAQAAAA==.',
Tu='Turan:BAAANQAECgMIBAAAAA==.',
Ty='Typhonic:BAAANQAECgUICwAAAA==.Tyrenari:BAAANQADCgEIAQAAAA==.',
Ul='Ultear:BAABNQAECn8lAAMXAAoKCRS1NQBbAQAXAAoK+BO1NQBbAQAlAAUKWxRlHACYAAAAAA==.',
Va='Valysandra:BAABNQAECn8XAAIQAAgK2hD6cQBwAQAQAAgK2hD6cQBwAQAAAA==.',
Ve='Venthyr:BAAANQAECgMIBAAAAA==.Vetenarae:BAAANQADCggICAABNQAECgcILwAaADQKAA==.Vethja:BAAANQAECgQICAABNQAECgcIEAAgAAAAAA==.',
Vo='Voidhope:BAAANQADCgYICAABNQAECgoKOQACAIwkAA==.Volkren:BAABNQAECn9FAAICAAoKUCE9DADJAgACAAoKUCE9DADJAgAAAA==.',
Wi='Witherpants:BAABNQAECn8eAAIQAAoKSQzGYgCZAQAQAAoKSQzGYgCZAQAAAA==.',
Wo='Worshipme:BAAANQAECgMIAwAAAA==.',
Xa='Xandor:BAAANQADCgIIAgABNQAECgoKOQACAIwkAA==.Xaos:BAABNQAECn85AAImAAoK6CFvAAAhAwAmAAoK6CFvAAAhAwAAAA==.',
Xi='Xiaowugui:BAABNQAECn8dAAITAAoKyBLFKwCNAQATAAoKyBLFKwCNAQAAAA==.',
Ya='Yarrick:BAABNQAECn8vAAIJAAkKaBnJLwBLAgAJAAkKaBnJLwBLAgAAAA==.',
Yu='Yukihime:BAABNQAECn8WAAMCAAkKbhGSUwCmAQACAAkKbhGSUwCmAQASAAEKMQYz7QAoAAABNQAFFAUIEgARAEkfAA==.',
Ze='Zelkiri:BAABNQAECn8lAAITAAkKpAzXLgB3AQATAAkKpAzXLgB3AQAAAA==.Zethlahr:BAABNQAECn83AAMhAAoKEB/6DwD2AgAhAAoKEB/6DwD2AgAFAAEKqxG38wBJAAAAAA==.',
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
