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

local lookup = {'DemonHunter-Havoc','Hunter-BeastMastery','Monk-Brewmaster','Druid-Balance','DeathKnight-Blood','Unknown-Unknown','Paladin-Holy','Warlock-Demonology','DemonHunter-Devourer','Priest-Shadow','Priest-Holy','Paladin-Retribution','DeathKnight-Unholy','Warlock-Destruction','Mage-Arcane','Mage-Fire','Warrior-Arms','Warrior-Fury','Warrior-Protection','Monk-Mistweaver','Hunter-Survival','Shaman-Restoration','Priest-Discipline','Druid-Feral','Paladin-Protection','Shaman-Elemental','Druid-Guardian','Shaman-Enhancement','Monk-Windwalker','Mage-Frost','Hunter-Marksmanship',}
local provider = {region='US',realm='SistersofElune',name='US',type='weekly',zone=53,date='2026-11-03',data={Ae='Aerria:BAAANQADCggICAAAAA==.',
Al='Althenara:BAAANQAECgQIBAAAAA==.Alysard:BAABNQAECn8hAAIBAAoK6xJWLgAzAgABAAoK6xJWLgAzAgAAAA==.',
Am='Amaurine:BAAANQAECgIIBAAAAA==.',
An='Anoras:BAAANQADCgcIEAAAAA==.',
Ar='Aratfu:BAAANQAECgcIEAABNQAECgkJKgACAAsWAA==.Araycadia:BAAANQAECggICAAAAA==.Archivus:BAAANQADCgYIBgAAAA==.Arteymis:BAAANQADCgQIBAABNQAECgkJNgADAE0jAA==.Arui:BAABNQAECn8cAAIEAAYKRRoFSQDFAQAEAAYKRRoFSQDFAQAAAA==.',
At='Athania:BAAANQAECgYICgABNQAECgkJIQAFAHISAA==.Athornia:BAAANQADCgUIBQAAAA==.',
Au='Aumery:BAABNQAECn8vAAIFAAgKoROsPgAcAQAFAAgKoROsPgAcAQAAAA==.Autoflick:BAAANQADCgYJBgAAAA==.',
Aw='Awwee:BAAANQADCgUJBQAAAA==.',
Az='Azinozdk:BAAANQAECgMIAgABNQAFFAIIAgAGAAAAAA==.Azinozl:BAAANQAFFAIIAgAAAA==.Azinozpaly:BAABNQAECn8cAAIHAAoK8RkwJQDWAgAHAAoK8RkwJQDWAgABNQAFFAIIAgAGAAAAAA==.Azurite:BAABNQAECn8WAAIIAAgKlAqWnACfAQAIAAgKlAqWnACfAQAAAA==.',
Ba='Baelthos:BAABNQAECn8jAAMJAAcKGxUqJABCAQABAAYKwQ9qSgB6AQAJAAcKzxQqJABCAQAAAA==.Barebut:BAAANQADCgEIAQAAAA==.',
Be='Belleslock:BAAANQADCgYIBgABNQAECgcIEwAGAAAAAA==.Bermon:BAAANQADCgYIDAABNQAECggILwAFAKETAA==.Berrypunch:BAAANQADCggIGAAAAA==.Bezzlkhan:BAAANQADCgIIAgAAAA==.',
Bi='Bingo:BAAANQAECgQICAAAAA==.',
Bl='Bluebyyou:BAABNQAECn8UAAIKAAYKfAp5QgAfAQAKAAYKfAp5QgAfAQAAAA==.',
Bo='Borgor:BAAANQADCgEIAQAAAA==.',
Bu='Bubblé:BAABNQAECn8nAAMLAAoKjxx8PQAMAgALAAoKjxx8PQAMAgAKAAUKZwu6RwD/AAAAAA==.Bustei:BAAANQAECgEIAQAAAA==.',
Ca='Caelion:BAABNQAECn8pAAMHAAkKGiLNGAAWAwAHAAkKGiLNGAAWAwAMAAMKwgzLNgFoAAAAAA==.Cannex:BAABNQAECn8kAAINAAkKShiEGAD3AQANAAkKShiEGAD3AQAAAA==.',
Ce='Celestia:BAAANQAECgUICwABNQAECggICAAGAAAAAA==.',
Cl='Clarinet:BAAANQABCgEIAQABNQAECggIEAAGAAAAAA==.Clarinetbdk:BAAANQAECggIEAAAAA==.',
Co='Coomerlord:BAAANQABCgYIBgAAAA==.',
Da='Daki:BAAANQADCgUIEgABNQAECgkJKwANABoLAA==.Darkersoul:BAAANQAECgUIBQAAAA==.',
De='Deathhunter:BAAANQABCgQIBAAAAA==.Deekon:BAABNQAECn8pAAMIAAkK+hdARQDQAQAIAAkK+hdARQDQAQAOAAEKugbAfwAsAAAAAA==.Delryn:BAAANQAECgQIBQAAAA==.Deshand:BAAANQABCgEIAQAAAA==.Deyvian:BAAANQADCgQIBAAAAA==.',
Do='Dooplikit:BAAANQADCgYIEwAAAA==.',
Dp='Dpn:BAABNQAECn8qAAMPAAoKnB/hHQBgAwAPAAoKnB/hHQBgAwAQAAEK1AtlDAA/AAABNQAECgQIBwAGAAAAAA==.',
Dr='Draxil:BAAANQADCgcICgAAAA==.Druish:BAAANQADCgYICgAAAA==.',
Du='Durpp:BAABNQAECn8jAAMRAAcKxRcmnwDPAQARAAcKxRcmnwDPAQASAAEKGgmKKwA1AAAAAA==.Dusyk:BAAANQAECgIIBAAAAA==.',
['Dä']='Däisymäy:BAAANQADCgEIAQABNQAECgkJMwACAFcZAA==.',
Eg='Egud:BAABNQAECn8vAAITAAgK6hdvEAAhAgATAAgK6hdvEAAhAgAAAA==.',
El='Elipse:BAAANQADCgUIBgAAAA==.Eliri:BAABNQAECn8cAAIUAAgKCB0UEgBbAgAUAAgKCB0UEgBbAgABNQAFFAIIAgAGAAAAAA==.Ellenad:BAAANQAECgIIAwAAAA==.',
En='Enemy:BAAANQAECgUICQABNQAECgkJIQAVAPcUAA==.',
Es='Estia:BAAANQABCgEIAQAAAA==.',
Ev='Everflux:BAABNQAECn8oAAILAAcK5yL0QQBkAgALAAcK5yL0QQBkAgAAAA==.Evo:BAABNQAECn8hAAMVAAkK9xTqBQBNAgAVAAgKDxPqBQBNAgACAAcKzhGckgBIAQAAAA==.',
Ey='Ey:BAAANQAECgIIAgAAAA==.',
Fa='Farisu:BAACNQAFFH8XAAMFAAcKRB9xAwDYAQAFAAcKRB9xAwDYAQANAAUKdhLXCQB2AQA1AAQKfyUAAw0ACgp7Ho0zAF0CAA0ACgrbGo0zAF0CAAUABgocHf9SAMoAAAAA.',
Fe='Feoran:BAAANQADCgIIAgAAAA==.',
Fj='Fjara:BAAANQADCgYIBgAAAA==.',
Fl='Flick:BAAANQAECgQIBAAAAA==.',
Fr='Frontallover:BAAANQADCgEIAQABNQAFFAIIAgAGAAAAAA==.',
Ge='Georish:BAAANQAECgYICQAAAA==.',
Gi='Gilgamësh:BAAANQADCgIIAgAAAA==.Ginseng:BAABNQAECn8mAAIWAAkKTBv9IwBzAgAWAAkKTBv9IwBzAgAAAA==.Giritos:BAAANQADCgYIBgABNQAECgcIEQAGAAAAAA==.Girthquake:BAABNQAECn84AAIWAAoK4CNwBwCFAwAWAAoK4CNwBwCFAwAAAA==.',
Go='Gorg:BAAANQADCgMIAwAAAA==.',
['Gé']='Gémini:BAAANQAECgYICQAAAA==.',
Ha='Haavoc:BAAANQAECgEIAQABNQAECgoKMAARAD8JAA==.Hagul:BAAANQAECgQIBQAAAA==.Hakuad:BAAANQADCgIIAgAAAA==.Halanhar:BAAANQADCgcICgAAAA==.',
He='Hellrocker:BAAANQAECgQIDwAAAA==.Hermione:BAABNQAECn8jAAIPAAoKjhTnQgAgAgAPAAoKjhTnQgAgAgABNQAECgIIAQAGAAAAAA==.Hestia:BAAANQABCgQIBAAAAA==.',
Ho='Holynova:BAAANQADCgIIAgAAAA==.Holyvader:BAAANQADCggICAAAAA==.Hotnspicy:BAAANQADCgcICAAAAA==.',
Hu='Hukhan:BAAANQABCgYICAAAAA==.Huraaki:BAAANQAECgMIAwAAAA==.',
In='Innis:BAABNQAECn8hAAMLAAoKfBvURgBSAgALAAoKfBvURgBSAgAXAAEKVwcELQAqAAAAAA==.',
Ir='Irine:BAAANQAECgYIEwAAAA==.Irore:BAAANQAECgYIDwAAAA==.',
It='Itszoi:BAAANQADCgIIAgAAAA==.',
Je='Jenjyandi:BAAANQADCgcIDAABNQAECgcIIwAWAHYKAA==.Jetahnna:BAABNQAECn8dAAICAAYK/QWk5ACnAAACAAYK/QWk5ACnAAAAAA==.',
Ji='Jibbs:BAAANQADCggIEgAAAA==.',
Jo='Jozlinn:BAABNQAECn83AAIKAAkKMAXBKAACAQAKAAkKMAXBKAACAQAAAA==.',
Ka='Kaeldar:BAAANQAECgIIBQAAAA==.Kajadin:BAABNQAECn8jAAIWAAcKdgp6dwAZAQAWAAcKdgp6dwAZAQAAAA==.Karatedonkey:BAABNQAECn8iAAIYAAcK8RErFgAhAQAYAAcK8RErFgAhAQAAAA==.Kardai:BAEBNQAECn8jAAIFAAcKoxHDWACQAQAFAAcKoxHDWACQAQAAAA==.Katreia:BAABNQAECn8WAAIZAAoKeRmdEADkAQAZAAoKeRmdEADkAQABNQAFFAYIGQAFAAEZAA==.Kazimas:BAAANQADCgcJFQAAAA==.',
Kh='Khalcite:BAABNQAECn8jAAIZAAcKmBv8HgDvAQAZAAcKmBv8HgDvAQAAAA==.',
Ki='Kittyshaman:BAABNQAECn80AAIaAAoK7wf4VgBHAQAaAAoK7wf4VgBHAQAAAA==.',
Kr='Kristyleigh:BAAANQABCgQIBAAAAA==.',
Ku='Kurono:BAABNQAECn8iAAICAAcKhAvgpAAjAQACAAcKhAvgpAAjAQAAAA==.Kuross:BAAANQAECgQICgAAAA==.',
La='Laermeluion:BAABNQAECn8fAAIbAAoKMB8EBwAaAwAbAAoKMB8EBwAaAwABNQAFFAYIGQAFAAEZAA==.Larra:BAABNQAECn8zAAICAAkKVxlXRgAKAgACAAkKVxlXRgAKAgAAAA==.',
Le='Leen:BAAANQAECgEIAQAAAA==.Lefthian:BAABNQAECn8cAAMZAAoKYRM4EgDJAQAZAAoKYRM4EgDJAQAMAAIKvQs9cwFqAAAAAA==.Leonidas:BAAANQADCggICAAAAA==.',
Lf='Lftwentyones:BAAANQADCgYICwABNQAFFAIIAgAGAAAAAA==.',
Li='Limptriscuit:BAAANQADCgYIBgAAAA==.Linua:BAAANQADCgYICgAAAA==.',
Lo='Loshing:BAAANQAECgQIDQAAAA==.',
Lu='Lunakae:BAAANQADCgIIAgAAAA==.',
Ma='Macumba:BAAANQADCggIDwAAAA==.Madeline:BAABNQAECn8gAAIKAAoKZh79FgCiAgAKAAoKZh79FgCiAgAAAA==.Malafar:BAABNQAECn8WAAIPAAgKtRCfywDvAQAPAAgKtRCfywDvAQAAAA==.Maranwae:BAABNQAECn86AAMWAAoKkB5JGQC/AgAWAAkKoR1JGQC/AgAaAAMKEQiPEwFmAAAAAA==.Masochist:BAABNQAECn8jAAIHAAoK/R09DwAgAwAHAAoK/R09DwAgAwABNQAECgIIAQAGAAAAAA==.',
Me='Melokoi:BAAANQAECgEIAgAAAA==.Merlose:BAAANQAECgIJAwAAAA==.',
Mi='Mieditos:BAAANQAECgUIDAABNQAECgcIEQAGAAAAAA==.Minirocks:BAABNQAECn83AAMcAAoKQxcADAAlAgAcAAoKQxcADAAlAgAWAAcKPBXddACtAQAAAA==.',
Mo='Moondivine:BAAANQAECgEIAQABNQAECgcICAAGAAAAAA==.Moonfaith:BAAANQAECgcICAAAAA==.Moosader:BAAANQADCggIKAAAAA==.',
Na='Naleana:BAAANQADCgcIJAAAAA==.Narzwaz:BAABNQAECn8jAAIdAAcKMRkIKQDXAQAdAAcKMRkIKQDXAQAAAA==.Nataly:BAABNQAECn8lAAILAAYKFyHUUAAxAgALAAYKFyHUUAAxAgAAAA==.',
Ne='Nellyfurtado:BAAANQADCgcIBwABNQAECgYIHQALANsTAA==.Neytri:BAABNQAECn8vAAICAAgK3g+MfgB1AQACAAgK3g+MfgB1AQAAAA==.',
Ni='Nightmoon:BAAANQADCgYIBQAAAA==.',
No='Nommo:BAAANQAECgYICQABNQAECgYIFAAKAHwKAA==.Nophica:BAABNQAECn8jAAMTAAcK8AdYGwDvAAATAAcK8AdYGwDvAAASAAMKpATbIQBiAAAAAA==.Novaxian:BAAANQAECgUICQAAAA==.Noxicous:BAAANQADCggIEAAAAA==.',
Nz='Nzoth:BAAANQAECgcIDgABNQAECggIEgAGAAAAAA==.',
On='Oneeyedwilly:BAAANQADCgcIBwAAAA==.',
Os='Osaka:BAABNQAECn8jAAIWAAcK9iKGHQCfAgAWAAcK9iKGHQCfAgAAAA==.',
Pa='Pantheain:BAAANQADCgMIAwAAAA==.Patches:BAAANQAECgYIDAAAAA==.',
Pl='Plagos:BAAANQADCgQIBQAAAA==.',
Po='Pouncival:BAAANQADCgEIAQAAAA==.',
Pr='Prahumn:BAABNQAECn8+AAQLAAoKgCG/CwBiAwALAAoKgCG/CwBiAwAXAAIKewovEABeAAAKAAEKAABOiwAfAAAAAA==.',
Pu='Purplicious:BAAANQAECgIIAgAAAA==.',
Py='Pymilocs:BAABNQAECn8sAAIaAAkKjx7UKQDZAgAaAAkKjx7UKQDZAgAAAA==.',
Qi='Qixx:BAABNQAECn8dAAIaAAcKygkVcgD6AAAaAAcKygkVcgD6AAAAAA==.',
Qu='Quint:BAAANQADCgcIEAAAAA==.',
Ra='Rabore:BAAANQAECgMIAwAAAA==.Raktal:BAAANQABCgIIAgAAAA==.Ralee:BAABNQAECn8rAAINAAkKGgvKLABPAQANAAkKGgvKLABPAQAAAA==.Ralienne:BAAANQAECgEIAgABNQAECgkJKwANABoLAA==.Ravinia:BAAANQADCgEIAQAAAA==.',
Re='Rem:BAAANQAECgEIAQAAAA==.Rennai:BAAANQAECgYICAAAAA==.',
Rh='Rhaemira:BAAANQAECgUIBQAAAA==.',
Ri='Richter:BAAANQADCggIIAAAAA==.Rin:BAEBNQAECn8oAAIUAAkK8R1BCACqAgAUAAkK8R1BCACqAgAAAA==.',
Ro='Rogelink:BAAANQADCgYIBgAAAA==.Rosan:BAAANQAECgMIBQAAAA==.Royakan:BAAANQABCgUIBwAAAA==.',
Ru='Rumtumtugger:BAAANQADCgUIBQAAAA==.',
Sa='Sableanne:BAAANQADCgYIAQAAAA==.Samoset:BAABNQAECn8bAAILAAcKFgkOgAAeAQALAAcKFgkOgAAeAQAAAA==.Sasten:BAAANQADCgMIAwAAAA==.',
Se='Serosion:BAAANQADCgcIBwAAAA==.',
Sh='Shaile:BAABNQAECn8hAAIFAAkKchL9JQChAQAFAAkKchL9JQChAQAAAA==.Shalu:BAAANQABCgUIBQAAAA==.Shammysham:BAAANQADCggIGgAAAA==.Shaymis:BAAANQABCggICwAAAA==.Sheepstealer:BAAANQADCgYIBgAAAA==.Shifthappons:BAAANQADCgUIBQAAAA==.Shockisha:BAAANQAECgUIBgAAAA==.Shogoth:BAAANQADCgEIAQAAAA==.Shortnstormy:BAAANQAFFAEIAQAAAA==.',
Si='Sightseer:BAABNQAECn8YAAICAAgK4gYxqwCuAQACAAgK4gYxqwCuAQAAAA==.Silverthorn:BAABNQAECn8qAAIMAAoKcA+RYgDRAQAMAAoKcA+RYgDRAQAAAA==.',
Sk='Skrom:BAAANQADCgIIAgAAAA==.',
Sn='Sney:BAAANQAECgEIAQABNQAECgkJKwANABoLAA==.',
Su='Suotokahn:BAAANQADCgUIBQAAAA==.',
Sw='Sweetti:BAAANQADCgcIBwABNQAECgkJMwACAFcZAA==.',
Sy='Sybbil:BAAANQADCgQIBAAAAA==.',
Ta='Tad:BAAANQAECgYIDAAAAA==.Taeltaa:BAAANQAECgYIEQAAAA==.Takara:BAAANQABCggIIAAAAA==.Taken:BAABNQAECn8fAAIPAAcKVwSF0QDcAAAPAAcKVwSF0QDcAAAAAA==.Tarvinus:BAAANQAECgEIAQAAAA==.Tazra:BAABNQAECn82AAIMAAoKpSG5KAAkAwAMAAoKpSG5KAAkAwAAAA==.',
Th='Theshammslam:BAAANQADCgMIAwAAAA==.Thomaz:BAABNQAECn8kAAMSAAoKBAmvGQAIAQARAAkKtQjyswCbAQASAAYK2QivGQAIAQAAAA==.Thx:BAAANQAECgIIAgAAAA==.',
Ti='Tiarini:BAAANQADCggIPwAAAA==.Tilee:BAAANQADCgUIDgAAAA==.Tirel:BAAANQADCgUIBQAAAA==.',
To='Tondri:BAABNQAECn86AAIHAAoK6BzJGwCtAgAHAAoK6BzJGwCtAgAAAA==.Tonkatruck:BAAANQAECgQICwAAAA==.',
Tr='Traice:BAAANQABCgYICQAAAA==.',
Tu='Tuyenlotus:BAABNQAECn87AAIcAAoKJh2ZBwCHAgAcAAoKJh2ZBwCHAgAAAA==.',
['Tò']='Tòkkí:BAAANQAECgUIBQAAAA==.',
Va='Vahnya:BAABNQAECn8rAAIaAAkKkRRYQQCUAQAaAAkKkRRYQQCUAQAAAA==.Varkalun:BAAANQAECgYIBgABNQAFFAYIGQAFAAEZAA==.',
Ve='Venekor:BAAANQADCggICQAAAA==.',
Vi='Vicarrion:BAABNQAECn8dAAIMAAgKQQaGyQAEAQAMAAgKQQaGyQAEAQAAAA==.Viscera:BAAANQADCgIIAwAAAA==.Vitesse:BAAANQADCgcIBwAAAA==.',
Vl='Vlane:BAAANQADCgEIAQAAAA==.',
Vr='Vrat:BAABNQAECn8qAAICAAkKCxbPbwAyAgACAAkKCxbPbwAyAgAAAA==.',
['Ví']='Ví:BAAANQAECgYIDQAAAA==.',
Wa='Warfare:BAABNQAECn8wAAIRAAoKPwmOlwAaAQARAAoKPwmOlwAaAQAAAA==.Warxie:BAAANQADCggIDgABNQAECggICAAGAAAAAA==.',
We='Wendrix:BAAANQADCggICAAAAA==.',
Wi='Wilbert:BAAANQADCgcICAAAAA==.Winxie:BAAANQAECgMIBwABNQAECggICAAGAAAAAA==.',
Wt='Wtfoxtrot:BAAANQADCggICAAAAA==.',
Yo='Yourmageisty:BAABNQAECn8hAAMPAAkKCxdJkABfAgAPAAkKyBZJkABfAgAeAAMKVhl4IgDXAAAAAA==.',
Yu='Yulíana:BAABNQAECn8dAAMLAAkKCR83NAA4AgALAAkKCR83NAA4AgAKAAEKAADiagAAAAAAAA==.',
Za='Zanot:BAAANQADCgQIBAAAAA==.',
Zc='Zcart:BAABNQAECn8sAAMCAAkKnhMcUgDoAQACAAkKnhMcUgDoAQAfAAIKAABjfABSAAAAAA==.',
Ze='Zelara:BAAANQAECggIBwAAAA==.Zeluxum:BAAANQAECgEJAQABNQAECgkJJAANAEoYAA==.Zerkio:BAABNQAECn8eAAIWAAkKpxMKRQBNAgAWAAkKpxMKRQBNAgAAAA==.Zertloc:BAACNQAFFH8NAAIaAAQKtRR6DgDeAAAaAAQKtRR6DgDeAAA1AAQKf1UAAxoACgp/Ij8NAO0CABoACgp/Ij8NAO0CABYAAQr2BBAdATMAAAAA.',
Zi='Zieda:BAABNQAECn8XAAIEAAgK7wYUNgApAQAEAAgK7wYUNgApAQAAAA==.',
Zo='Zoids:BAAANQADCgEIAQAAAA==.',
Zu='Zulix:BAAANQADCgEIAQAAAA==.Zulixx:BAAANQADCgQIBAAAAA==.',
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
