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

local lookup = {'DemonHunter-Havoc','Hunter-BeastMastery','Unknown-Unknown','Monk-Brewmaster','Druid-Balance','DeathKnight-Blood','Warlock-Demonology','Paladin-Holy','DemonHunter-Devourer','Priest-Holy','Priest-Shadow','Paladin-Retribution','DeathKnight-Unholy','Warlock-Destruction','Mage-Arcane','Mage-Fire','Warrior-Arms','Warrior-Fury','Warrior-Protection','Monk-Mistweaver','Hunter-Survival','Shaman-Restoration','Priest-Discipline','Druid-Feral','Paladin-Protection','Shaman-Elemental','Druid-Guardian','Shaman-Enhancement','Monk-Windwalker','Mage-Frost','Hunter-Marksmanship',}
local provider = {region='US',realm='SistersofElune',name='US',type='weekly',zone=53,date='2026-11-17',data={Ae='Aerria:BAAANQADCggICQAAAA==.',
Al='Althenara:BAAANQAECgQIBAAAAA==.Alysard:BAABNQAECn8hAAIBAAoK6xJWLgAzAgABAAoK6xJWLgAzAgAAAA==.',
Am='Amaurine:BAAANQAECgIIBAAAAA==.',
An='Anoras:BAAANQADCgcIEAAAAA==.',
Ar='Aratfu:BAAANQAECgcIEAABNQAECgkJKgACAAsWAA==.Araycadia:BAAANQAECggICAAAAA==.Archivus:BAAANQADCgYIBgAAAA==.Armsfuryprot:BAAANQADCgUIBQABNQADCggIEAADAAAAAA==.Arteymis:BAAANQADCgQIBAABNQAECgoKPgAEALAjAA==.Arui:BAABNQAECn8iAAIFAAcKeBghOwBDAQAFAAcKeBghOwBDAQAAAA==.',
At='Athania:BAAANQAECgYICgABNQAECgkJIQAGAHISAA==.Athornia:BAAANQADCgUIBQAAAA==.',
Au='Aumery:BAABNQAECn82AAIGAAoKzRPjKQCzAQAGAAoKzRPjKQCzAQAAAA==.Autoflick:BAAANQADCgYJBgAAAA==.',
Aw='Awwee:BAAANQADCgUJBQAAAA==.',
Az='Azinozdk:BAAANQAECgMIAwABNQAECggIFAAHAEkPAA==.Azinozl:BAABNQAECn8UAAIHAAgKSQ/9fQBmAQAHAAgKSQ/9fQBmAQAAAA==.Azinozpaly:BAABNQAECn8dAAIIAAoKPBowJQDWAgAIAAoKPBowJQDWAgABNQAECggIFAAHAEkPAA==.Azurite:BAABNQAECn8WAAIHAAgKlAqWnACfAQAHAAgKlAqWnACfAQAAAA==.',
Ba='Baelthos:BAABNQAECn8pAAMJAAcKGxWBKgBEAQABAAYKwQ9qSgB6AQAJAAcKGhWBKgBEAQAAAA==.Barebut:BAAANQADCgEIAQAAAA==.',
Be='Belleslock:BAAANQADCgYIBgABNQAECgoKGwAKAM8VAA==.Bermon:BAAANQADCgYIDAABNQAECgoKNgAGAM0TAA==.Berrypunch:BAAANQADCggIJgAAAA==.Bezzlkhan:BAAANQADCgIIAgAAAA==.',
Bi='Bingo:BAAANQAECgQICAAAAA==.',
Bl='Bluebyyou:BAABNQAECn8UAAILAAYKfAp5QgAfAQALAAYKfAp5QgAfAQAAAA==.',
Bo='Borgor:BAAANQADCgEIAQAAAA==.',
Bu='Bubblé:BAABNQAECn80AAMKAAoK0h2ERAAmAgAKAAoK0h2ERAAmAgALAAYKJAq6RwD/AAAAAA==.Bustei:BAAANQAECgEIAQAAAA==.',
Ca='Caelion:BAABNQAECn8pAAMIAAkKGiLNGAAWAwAIAAkKGiLNGAAWAwAMAAMKwgznYgFnAAAAAA==.Cannex:BAABNQAECn8kAAINAAkKShh5HgDuAQANAAkKShh5HgDuAQAAAA==.',
Ce='Celestia:BAAANQAECgUICwABNQAECggICwADAAAAAA==.',
Cl='Clarinet:BAAANQAECgEIAQABNQAECggIEQADAAAAAA==.Clarinetbdk:BAAANQAECggIEQAAAA==.',
Co='Coomerlord:BAAANQABCgYIBgAAAA==.',
Da='Daki:BAAANQADCggIKQABNQAECgkJKwANABoLAA==.Darkersoul:BAAANQAECgUIBQAAAA==.',
De='Deathhunter:BAAANQABCgQIBAAAAA==.Deekon:BAABNQAECn8pAAMHAAkK+he3WADKAQAHAAkK+he3WADKAQAOAAEKugbAfwAsAAAAAA==.Delryn:BAAANQAECgQIBQAAAA==.Deshand:BAAANQABCgEIAQAAAA==.Deyvian:BAAANQADCgQIBAAAAA==.',
Do='Dooplikit:BAAANQADCgYIEwAAAA==.',
Dp='Dpn:BAABNQAECn8qAAMPAAoKnB/hHQBgAwAPAAoKnB/hHQBgAwAQAAEK1AtlDAA/AAABNQAECgQIBwADAAAAAA==.',
Dr='Draxil:BAAANQADCgcICgAAAA==.Druish:BAAANQAECgYIBQAAAA==.',
Du='Durpp:BAABNQAECn8pAAMRAAcKyxcmnwDPAQARAAcKyxcmnwDPAQASAAEKGgnjNQA0AAAAAA==.Dusyk:BAAANQAECgIIBAAAAA==.',
['Dä']='Däisymäy:BAAANQADCgEIAQABNQAECgoKQwACAIccAA==.',
Eg='Egud:BAABNQAECn8/AAITAAoKUxSqEACsAQATAAoKUxSqEACsAQAAAA==.',
El='Elipse:BAAANQADCgUIBgAAAA==.Eliri:BAABNQAECn8cAAIUAAgKCB0UEgBbAgAUAAgKCB0UEgBbAgABNQAFFAIIAgADAAAAAA==.Ellenad:BAAANQAECgIIAwAAAA==.',
En='Enemy:BAAANQAECgUICQABNQAECgkJIQAVAPcUAA==.',
Es='Estia:BAAANQABCgEIAQAAAA==.',
Ev='Everflux:BAABNQAECn8pAAIKAAcK5yL0QQBkAgAKAAcK5yL0QQBkAgAAAA==.Evo:BAABNQAECn8hAAMVAAkK9xTqBQBNAgAVAAgKDxPqBQBNAgACAAcKzhG0sABRAQAAAA==.',
Ey='Ey:BAAANQAECgIIAgAAAA==.',
Fa='Farisu:BAACNQAFFH8XAAMGAAcKRB8aBwDDAQAGAAcKRB8aBwDDAQANAAUKdhLXCQB2AQA1AAQKfyYAAw0ACgp7Ho0zAF0CAA0ACgrbGo0zAF0CAAYABgocHSpfAMcAAAAA.',
Fe='Feoran:BAAANQADCgIIAgAAAA==.',
Fj='Fjara:BAAANQADCgYIBgAAAA==.',
Fl='Flick:BAAANQAECgQIBAAAAA==.',
Fr='Frontallover:BAAANQADCgEIAQABNQAFFAIIAgADAAAAAA==.',
Ge='Georish:BAAANQAECgYICQAAAA==.',
Gi='Gilgamësh:BAAANQADCgIIAgAAAA==.Ginseng:BAABNQAECn8mAAIWAAkKTBvDLwBiAgAWAAkKTBvDLwBiAgAAAA==.Giritos:BAAANQADCgYIBgABNQAECgkJIwAIAOkfAA==.Girthquake:BAABNQAECn9KAAIWAAoK3iS/BwCdAwAWAAoK3iS/BwCdAwAAAA==.',
Go='Goregasm:BAAANQADCgEIAQABNQAECgcICQADAAAAAA==.Gorg:BAAANQADCgMIAwAAAA==.',
['Gé']='Gémini:BAAANQAECgYICQAAAA==.',
Ha='Haavoc:BAAANQAECgEIAQABNQAECgoKOAARAHEKAA==.Hagul:BAAANQAECgQIBwAAAA==.Hakuad:BAAANQADCgIIAgAAAA==.Halanhar:BAAANQADCgcICgAAAA==.',
He='Hellrocker:BAAANQAECgQIDwAAAA==.Hermione:BAABNQAECn8qAAIPAAoKCxd+RQA9AgAPAAoKCxd+RQA9AgABNQAECgEIAQADAAAAAA==.Hestia:BAAANQABCgQIBAAAAA==.',
Ho='Holynova:BAAANQADCgIIAgAAAA==.Holyvader:BAAANQADCggICAAAAA==.Hotnspicy:BAAANQADCggICwABNQADCggIEAADAAAAAA==.',
Hu='Hukhan:BAAANQABCgYICAAAAA==.Huraaki:BAAANQAECgMIAwAAAA==.',
In='Innis:BAABNQAECn8hAAMKAAoKfBvURgBSAgAKAAoKfBvURgBSAgAXAAEKVwcELQAqAAAAAA==.',
Ir='Irine:BAAANQAECgYIEwAAAA==.Irore:BAAANQAECgYIDwAAAA==.',
It='Itszoi:BAAANQADCgIIAgAAAA==.',
Je='Jenjyandi:BAAANQADCggIGAABNQAECgcIKQAWAJcKAA==.Jetahnna:BAABNQAECn8jAAICAAcKtAU16QDdAAACAAcKtAU16QDdAAAAAA==.',
Ji='Jibbs:BAAANQADCggIEgAAAA==.',
Jo='Jozlinn:BAABNQAECn8+AAMLAAoKlwZUMQABAQALAAkKPAVUMQABAQAKAAEKDwML/gAnAAAAAA==.',
Ka='Kaeldar:BAAANQAECgIIBQAAAA==.Kajadin:BAABNQAECn8pAAIWAAcKlwr/jQAMAQAWAAcKlwr/jQAMAQAAAA==.Karatedonkey:BAABNQAECn8oAAIYAAcKvxIcHAArAQAYAAcKvxIcHAArAQAAAA==.Kardai:BAEBNQAECn8pAAIGAAcKoxHDWACQAQAGAAcKoxHDWACQAQAAAA==.Katreia:BAABNQAECn8WAAIZAAoKeRmkFQDVAQAZAAoKeRmkFQDVAQABNQAFFAcIGwAGABYWAA==.Kazimas:BAAANQADCgcJFQAAAA==.',
Kh='Khalcite:BAABNQAECn8pAAIZAAcKmBv8HgDvAQAZAAcKmBv8HgDvAQAAAA==.',
Ki='Kittyshaman:BAABNQAECn88AAIaAAoKXQlYZQBXAQAaAAoKXQlYZQBXAQAAAA==.',
Kr='Kristyleigh:BAAANQABCgQIBAAAAA==.',
Ku='Kurono:BAABNQAECn8iAAICAAcKhAvbyAAgAQACAAcKhAvbyAAgAQAAAA==.Kuross:BAAANQAECgQICgAAAA==.',
La='Laermeluion:BAABNQAECn8gAAIbAAoKMB8EBwAaAwAbAAoKMB8EBwAaAwABNQAFFAcIGwAGABYWAA==.Larra:BAABNQAECn9DAAICAAoKhxwlLgCKAgACAAoKhxwlLgCKAgAAAA==.',
Le='Leen:BAAANQAECgEIAQAAAA==.Lefthian:BAABNQAECn8kAAMZAAoKAxRIFgDMAQAZAAoKpRNIFgDMAQAMAAMKKww9cwFqAAAAAA==.Leonidas:BAAANQADCggICAAAAA==.',
Lf='Lftwentyones:BAAANQADCgYICwABNQAFFAIIAgADAAAAAA==.',
Li='Limptriscuit:BAAANQADCgYIBgAAAA==.Linua:BAAANQAECgEIAQAAAA==.',
Lo='Loshing:BAABNQAECn8dAAIEAAcKBAa4FgDCAAAEAAcKBAa4FgDCAAAAAA==.',
Lu='Lunakae:BAAANQADCgIIAgAAAA==.',
Ma='Macumba:BAAANQADCggIDwAAAA==.Madeline:BAABNQAECn8gAAILAAoKZh79FgCiAgALAAoKZh79FgCiAgAAAA==.Malafar:BAABNQAECn8WAAIPAAgKtRCfywDvAQAPAAgKtRCfywDvAQAAAA==.Maranwae:BAABNQAECn8/AAMWAAoKgxxpGgDjAgAWAAoKgxxpGgDjAgAaAAMKEQiPEwFmAAAAAA==.Masochist:BAABNQAECn8pAAIIAAoKSR+mEAA4AwAIAAoKSR+mEAA4AwABNQAECgEIAQADAAAAAA==.',
Me='Melokoi:BAAANQAECgEIAgAAAA==.Merlose:BAAANQAECgIJAwAAAA==.',
Mi='Mieditos:BAAANQAECgQIDAABNQAECgkJIwAIAOkfAA==.Minirocks:BAABNQAECn83AAMcAAoKQxcoDwAhAgAcAAoKQxcoDwAhAgAWAAcKPBXddACtAQAAAA==.',
Mo='Moondivine:BAAANQAECgEIAQABNQAECgcICAADAAAAAA==.Moonfaith:BAAANQAECgcICAAAAA==.Moosader:BAAANQADCggINgAAAA==.',
Na='Naleana:BAAANQADCgcIKAAAAA==.Narzwaz:BAABNQAECn8pAAIdAAcKahkIKQDXAQAdAAcKahkIKQDXAQAAAA==.Nataly:BAABNQAECn8mAAIKAAYKFyHUUAAxAgAKAAYKFyHUUAAxAgAAAA==.',
Ne='Nellyfurtado:BAAANQADCgcIBwABNQAECgYIHQAKANsTAA==.Neytri:BAABNQAECn8/AAICAAoKExJ2UAAsAgACAAoKExJ2UAAsAgAAAA==.',
Ni='Nightmoon:BAAANQADCgYIBQAAAA==.',
No='Nommo:BAAANQAECgYICQABNQAECgYIFAALAHwKAA==.Nophica:BAABNQAECn8sAAMTAAgK1gi2GwAlAQATAAgK1gi2GwAlAQASAAMKpARDKgBhAAAAAA==.Novaxian:BAAANQAECgUICQAAAA==.Noxicous:BAAANQADCggIEAAAAA==.',
Nz='Nzoth:BAAANQAECgcIDgABNQAECggIEgADAAAAAA==.',
On='Oneeyedwilly:BAAANQADCgcIBwAAAA==.',
Os='Osaka:BAABNQAECn8pAAIWAAcKaCPjJQCYAgAWAAcKaCPjJQCYAgAAAA==.',
Pa='Pantheain:BAAANQADCgMIAwAAAA==.Patches:BAAANQAECgYIDAAAAA==.',
Pe='Petsteiner:BAAANQADCggIEAAAAA==.',
Pl='Plagos:BAAANQADCgQIBQAAAA==.',
Po='Pouncival:BAAANQADCgEIAQAAAA==.',
Pr='Prahumn:BAABNQAECn8+AAQKAAoKgCExEgBIAwAKAAoKgCExEgBIAwAXAAIKewoGFABZAAALAAEKAABOiwAfAAAAAA==.',
Pu='Purplicious:BAAANQAECgIIAgAAAA==.',
Py='Pymilocs:BAABNQAECn8sAAIaAAkKjx7UKQDZAgAaAAkKjx7UKQDZAgAAAA==.',
Qi='Qixx:BAABNQAECn8dAAIaAAcKygmGiQD6AAAaAAcKygmGiQD6AAAAAA==.',
Qu='Quint:BAAANQADCgcIEgAAAA==.',
Ra='Rabore:BAAANQAECgMIAwAAAA==.Raktal:BAAANQABCgIIAgAAAA==.Ralee:BAABNQAECn8rAAINAAkKGgssNQBKAQANAAkKGgssNQBKAQAAAA==.Ralienne:BAABNQAECn8VAAIeAAUKkgkHKwCMAAAeAAUKkgkHKwCMAAABNQAECgkJKwANABoLAA==.Ravinia:BAAANQADCgEIAQAAAA==.',
Re='Rem:BAAANQAECgEIAQAAAA==.Rennai:BAAANQAECgUICAAAAA==.',
Rh='Rhaemira:BAAANQAECgUIBQAAAA==.',
Ri='Richter:BAAANQADCggIIAAAAA==.Rin:BAEBNQAECn82AAIUAAoKKx3YBwDxAgAUAAoKKx3YBwDxAgAAAA==.',
Ro='Rogelink:BAAANQADCgYIBgAAAA==.Rosan:BAAANQAECgQIBgAAAA==.Royakan:BAAANQABCgUIBwAAAA==.',
Ru='Rumtumtugger:BAAANQADCgUIBQAAAA==.',
Sa='Sableanne:BAAANQAECgQIBQAAAA==.Samoset:BAABNQAECn8hAAIKAAcKQQnelQAYAQAKAAcKQQnelQAYAQAAAA==.Sasten:BAAANQADCgMIAwAAAA==.',
Se='Serosion:BAAANQADCgcIBwAAAA==.',
Sh='Shaile:BAABNQAECn8hAAIGAAkKchJDLwCTAQAGAAkKchJDLwCTAQAAAA==.Shalu:BAAANQADCgEIAgAAAA==.Shammysham:BAAANQADCggIGgAAAA==.Shaymis:BAAANQABCggICwAAAA==.Sheepstealer:BAAANQADCgYIBgAAAA==.Shifthappons:BAAANQADCgUIBQAAAA==.Shockisha:BAAANQAECgUIBgAAAA==.Shogoth:BAAANQADCgEIAQAAAA==.Shortnstormy:BAAANQAFFAIIAwAAAA==.',
Si='Sightseer:BAABNQAECn8ZAAICAAkKPwcxqwCuAQACAAkKPwcxqwCuAQAAAA==.Silverthorn:BAABNQAECn8zAAIMAAoKtg/iewDVAQAMAAoKtg/iewDVAQAAAA==.',
Sk='Skrom:BAAANQADCgIIAgAAAA==.',
Sn='Sney:BAAANQAECgEIAQABNQAECgkJKwANABoLAA==.',
Su='Suotokahn:BAAANQADCgUIBQAAAA==.',
Sw='Sweetti:BAAANQADCgcIBwABNQAECgoKQwACAIccAA==.',
Sy='Sybbil:BAAANQADCgQIBAAAAA==.',
Ta='Tad:BAAANQAECgYIDAAAAA==.Taeltaa:BAABNQAECn8WAAIdAAgK5ANgRQCVAAAdAAgK5ANgRQCVAAAAAA==.Takara:BAAANQABCggIIAAAAA==.Taken:BAABNQAECn8kAAIPAAcK3ARR4wDnAAAPAAcK3ARR4wDnAAAAAA==.Tanksteiner:BAAANQADCgEIAQABNQADCggIEAADAAAAAA==.Tarvinus:BAAANQAECgEIAQAAAA==.Tazra:BAABNQAECn8+AAIMAAoKvSHvJADNAgAMAAoKvSHvJADNAgAAAA==.',
Th='Theshammslam:BAAANQADCgMIAwAAAA==.Thomaz:BAABNQAECn8kAAMSAAoKBAmvGQAIAQARAAkKtQjyswCbAQASAAYK2QivGQAIAQAAAA==.Thx:BAAANQAECgIIAgAAAA==.Thörin:BAAANQADCgEIAQAAAA==.',
Ti='Tiarini:BAAANQADCggIQQAAAA==.Tilee:BAAANQADCgUIDwAAAA==.Tirel:BAAANQAECgYIBgAAAA==.',
To='Tondri:BAABNQAECn9CAAIIAAoK6Bx6JQCbAgAIAAoK6Bx6JQCbAgAAAA==.Tonkatruck:BAAANQAECgQICwAAAA==.Tooholy:BAAANQAECgIIAgAAAA==.',
Tr='Traice:BAAANQABCgYICQAAAA==.',
Tu='Tuyenlotus:BAABNQAECn87AAIcAAoKJh0vCgB6AgAcAAoKJh0vCgB6AgAAAA==.',
['Tò']='Tòkkí:BAAANQAECgUIBQAAAA==.',
Va='Vahnya:BAABNQAECn8rAAIaAAkKkRSVXgAGAgAaAAkKkRSVXgAGAgAAAA==.Varkalun:BAAANQAECggIDgABNQAFFAcIGwAGABYWAA==.',
Ve='Venekor:BAAANQADCggICQAAAA==.',
Vi='Vicarrion:BAABNQAECn8dAAIMAAgKQQbX6gAMAQAMAAgKQQbX6gAMAQAAAA==.Viscera:BAAANQADCgIIAwAAAA==.Vitesse:BAAANQADCgcIBwAAAA==.',
Vl='Vlane:BAAANQADCgEIAQAAAA==.',
Vr='Vrat:BAABNQAECn8qAAICAAkKCxbPbwAyAgACAAkKCxbPbwAyAgAAAA==.',
['Ví']='Ví:BAAANQAECggIDwAAAA==.',
Wa='Warfare:BAABNQAECn84AAIRAAoKcQognwA/AQARAAoKcQognwA/AQAAAA==.Warxie:BAAANQADCggIDgABNQAECggICwADAAAAAA==.',
We='Wendrix:BAAANQADCggICAAAAA==.',
Wi='Wilbert:BAAANQADCgcICQAAAA==.Winxie:BAAANQAECgMIBwABNQAECggICwADAAAAAA==.',
Wt='Wtfoxtrot:BAAANQADCggICAAAAA==.',
Yo='Yourmageisty:BAABNQAECn8qAAMPAAoKmxdJkABfAgAPAAoKLBdJkABfAgAeAAQKNhh4IgDXAAAAAA==.',
Yu='Yulíana:BAABNQAECn8fAAMKAAoKaB/NLACUAgAKAAoKaB/NLACUAgALAAEKAAAafAAAAAAAAA==.',
Za='Zakýe:BAAANQADCgEIAQAAAA==.Zanot:BAAANQADCgQIBAAAAA==.',
Zc='Zcart:BAABNQAECn8sAAMCAAkKnhNQawDsAQACAAkKnhNQawDsAQAfAAIKAABjfABSAAAAAA==.',
Ze='Zelara:BAAANQAECggIBwAAAA==.Zeluxum:BAAANQAECgEJAQABNQAECgkJJAANAEoYAA==.Zerkio:BAABNQAECn8eAAIWAAkKpxMKRQBNAgAWAAkKpxMKRQBNAgAAAA==.Zertloc:BAACNQAFFH8NAAIaAAQKtRTYEgDYAAAaAAQKtRTYEgDYAAA1AAQKf10AAxoACgpdI+YLABIDABoACgpdI+YLABIDABYAAQr2BBAdATMAAAAA.',
Zi='Zieda:BAABNQAECn8cAAIFAAkKfQnRMQB7AQAFAAkKfQnRMQB7AQAAAA==.',
Zo='Zoids:BAAANQADCgEIAQAAAA==.',
Zu='Zulix:BAAANQADCgEIAQAAAA==.Zulixx:BAAANQADCgQIBQAAAA==.',
Zy='Zyriatchi:BAAANQAECgMIAwAAAA==.',
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
