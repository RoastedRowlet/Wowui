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

local lookup = {'Mage-Arcane','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Unknown-Unknown','Druid-Restoration','Druid-Balance','Shaman-Elemental','Shaman-Restoration','DemonHunter-Vengeance','Mage-Frost','Druid-Feral','Warrior-Protection','DeathKnight-Blood','Hunter-BeastMastery','Mage-Fire','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Warrior-Fury','Hunter-Marksmanship','Paladin-Protection','DeathKnight-Unholy','Shaman-Enhancement','Monk-Mistweaver','Monk-Windwalker','Priest-Shadow','Evoker-Devastation','Evoker-Preservation','Hunter-Survival','Warlock-Affliction','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction',}
local provider = {region='US',realm='Dunemaul',name='US',type='weekly',zone=53,date='2026-10-20',data={Al='Aletalle:BAAANQAECgQIBAAAAA==.Allice:BAABNQAECn8gAAIBAAkK2RU+TwAdAQABAAkK2RU+TwAdAQAAAA==.Alsheyra:BAAANQADCgYICgAAAA==.Alterion:BAAANQABCgQICgAAAA==.',
An='Anxious:BAAANQADCgYIEwAAAA==.',
As='Ashwalker:BAABNQAECn8VAAMCAAcKugZ83gDCAAACAAYKdgJ83gDCAAADAAUKyQY4jgC4AAAAAA==.',
Au='Aughyst:BAAANQAECgMJBwAAAA==.Augnyxia:BAAANQAECgQICgAAAA==.Augtysm:BAAANQADCggICAAAAA==.Augy:BAAANQAECgQIBAAAAA==.',
Ba='Bandobras:BAAANQADCgcIDgAAAA==.',
Bh='Bhorg:BAAANQADCgMIAwAAAA==.',
Bl='Blackdust:BAAANQADCggIDQAAAA==.Blast:BAAANQAECgEIAQABNQAFFAcIHgAEAGQiAA==.Blasters:BAAANQADCgcIEgAAAA==.Bloodjury:BAAANQAECgcIEAAAAA==.Blossom:BAAANQABCgIIAgABNQABCgYICwAFAAAAAA==.',
Bo='Boejo:BAAANQAECgMIBAAAAA==.Borellus:BAAANQABCgUICQAAAA==.',
Br='Broken:BAAANQADCgYIBgAAAA==.',
Bu='Bunga:BAAANQAECgEIAQAAAA==.Bungis:BAAANQAECggIDgAAAA==.Bushetti:BAABNQAECn8XAAMGAAkKphbFHgA4AgAGAAgKSBbFHgA4AgAHAAIKAADcnwBfAAAAAA==.',
Ca='Casperface:BAABNQAECn8mAAMIAAoKJxMRcwDHAQAIAAgKPg4RcwDHAQAJAAMKdQd5ewBfAAAAAA==.Cazisham:BAAANQAECgcIEQAAAA==.',
Ce='Cestus:BAAANQAECgcJDQAAAA==.Cevianne:BAAANQAECgIIAgAAAA==.',
Ci='Ciaphis:BAABNQAECn8cAAIDAAcK/wkShwDCAAADAAcK/wkShwDCAAAAAA==.Cinnabuns:BAAANQADCgQIAwAAAA==.',
Co='Coal:BAABNQAECn8jAAIKAAkKjCLYAwAaAwAKAAkKjCLYAwAaAwAAAA==.Coltonater:BAACNQAFFH8RAAIBAAYKvhiRDwD7AQABAAYKvhiRDwD7AQA1AAQKf00AAgEACgrvJAACAO4DAAEACgrvJAACAO4DAAAA.',
['Cá']='Cáséy:BAACNQAFFH8QAAMLAAUKgRf/AACSAQALAAUKgRf/AACSAQABAAEKAABKLAAAAAA1AAQKfzkAAwsACgqhIXwAAJ0CAAsACgqhIXwAAJ0CAAEAAwqMDXbZAEgAAAAA.',
['Cä']='Cäsey:BAAANQADCgMIAwABNQAFFAUIEAALAIEXAA==.',
Da='Darkshroud:BAAANQAECgMIBQAAAA==.Datbi:BAABNQAECn8pAAMHAAoK0xGyOAApAgAHAAoKuA+yOAApAgAMAAMK6heEEAClAAAAAA==.Daugi:BAABNQAECn8dAAMNAAkK3x7lBwDXAgANAAcKSyPlBwDXAgAEAAkKbhYUGgCdAQAAAA==.',
De='Deathangel:BAAANQAECgYICwAAAA==.Deathdeamon:BAAANQADCgMIAwAAAA==.Deathdylan:BAABNQAECn8nAAIOAAoKKB/9GQDeAgAOAAoKKB/9GQDeAgAAAA==.Delice:BAAANQAECgUIBwAAAA==.Demonikal:BAAANQAECgQIBAAAAA==.Demonware:BAAANQAECgQIBAAAAA==.Demítríus:BAAANQAECgYIDAAAAA==.Dethh:BAABNQAECn8jAAIPAAcKPxM8NQBSAQAPAAcKPxM8NQBSAQAAAA==.',
Di='Didona:BAAANQADCgYIBgAAAA==.Distortion:BAAANQAECgIIAgAAAA==.Divineflava:BAAANQAECgUIBgABNQAFFAQICAABAPMTAA==.',
Do='Dobby:BAAANQADCggIDQAAAA==.',
Dr='Drakeo:BAAANQAECgYIEwAAAA==.Draximus:BAAANQAECgUIDAAAAA==.Drougenin:BAAANQAECggICAABNQAECgkJIwAKAIwiAA==.Drpumper:BAAANQAECgcIEwAAAA==.Druqz:BAABNQAECn8nAAILAAoK+RKFCQA6AgALAAoK+RKFCQA6AgAAAA==.Druski:BAAANQABCgQIBAAAAA==.Drævn:BAABNQAECn8qAAIQAAkKLheCAgAZAgAQAAkKLheCAgAZAgAAAA==.',
Du='Dum:BAACNQAFFH8SAAQKAAYK1BksAwDhAAARAAMKwxzcCgAgAQAKAAMKGh0sAwDhAAASAAMKzhRwFgCIAAA1AAQKfy4ABBEACgpTId4OAP4CABEACgoHId4OAP4CAAoABwqLGsYKACkCABIAAwpnI3dXAC0BAAAA.Duragon:BAABNQAECn8dAAIEAAYKDgM9DgHAAAAEAAYKDgM9DgHAAAAAAA==.Durkagon:BAAANQAECgQIBwAAAA==.',
Dw='Dwimbear:BAAANQABCgIIAgAAAA==.Dwimhoof:BAAANQADCgMIAwAAAA==.Dwinnet:BAAANQABCgQICQAAAA==.',
El='Eldin:BAABNQAECn8nAAMTAAoKWyFYAQBGAwATAAkK5yBYAQBGAwAUAAEKaiVXeQBuAAAAAA==.',
En='Endofdays:BAAANQAECggIEAAAAA==.Enro:BAACNQAFFH8FAAISAAIKRgRXCQCEAAASAAIKRgRXCQCEAAA1AAQKfyoAAxIACgpOGuMhAIwCABIACgpOGuMhAIwCABEAAQpeD1cyAEQAAAAA.',
Er='Erovia:BAABNQAECn8nAAIPAAkKfQ6JgAAMAgAPAAkKfQ6JgAAMAgAAAA==.',
Es='Esclipse:BAAANQADCgYIBgAAAA==.',
Et='Etclock:BAAANQADCgYIBgAAAA==.',
Fa='Faeria:BAAANQABCgQIBAAAAA==.Farruq:BAAANQAECgUJCwAAAA==.Fathermoo:BAAANQAECgEIAQAAAA==.',
Fe='Feelsbadmang:BAAANQADCgQIBAABNQAECgoKIwAVAJ0cAA==.Fellz:BAAANQADCgIIAgAAAA==.Ferian:BAAANQAECgQIEAAAAA==.',
Fl='Flavaflare:BAACNQAFFH8IAAIBAAQK8xNcFwCjAAABAAQK8xNcFwCjAAA1AAQKf0YAAgEACgrcItcQAI8DAAEACgrcItcQAI8DAAAA.',
Fo='Foodex:BAAANQAFFAEIAQAAAA==.Fourleaf:BAACNQAFFH8FAAIWAAIKIBEzCQCMAAAWAAIKIBEzCQCMAAA1AAQKfyoAAhYACgp9HAMWAKsCABYACgp9HAMWAKsCAAAA.',
Fr='Frogplushy:BAABNQAECn8bAAIBAAoKQhwgFADGAQABAAoKQhwgFADGAQAAAA==.',
Fu='Furlock:BAAANQAECgUICwAAAA==.Furral:BAABNQAECn8qAAIMAAoKXRqiBwDlAgAMAAoKXRqiBwDlAgAAAA==.Furretc:BAAANQADCgEIAQAAAA==.',
Ga='Gaeth:BAABNQAECn8rAAIGAAoKxRNFJQD5AQAGAAoKxRNFJQD5AQAAAA==.',
Ge='Gengiss:BAAANQADCgQIBAAAAA==.',
Gl='Gleg:BAACNQAFFH8OAAMJAAMKrBn7FwDgAAAJAAMKrBn7FwDgAAAIAAIKuggTKACKAAA1AAQKfygAAwkACgq0HpUXABYDAAkACgq0HpUXABYDAAgAAQoAAEsvAToAAAAA.',
Go='Goodside:BAAANQADCgYIDAAAAA==.',
Gr='Grimthebrave:BAABNQAECn8XAAIEAAoKuRZ1dgAzAgAEAAoKuRZ1dgAzAgAAAA==.Grimthecruel:BAABNQAECn8lAAMRAAoKlRWYDABTAQARAAoKjRWYDABTAQASAAEK+RQSjwA9AAAAAA==.Grimthedread:BAAANQAECgcIBwAAAA==.Gripless:BAAANQADCgQIBAAAAA==.Griselden:BAABNQAECn8xAAIRAAoKth3hAwDqAQARAAoKth3hAwDqAQAAAA==.Grizzlyras:BAAANQADCggICAAAAA==.',
Gu='Gub:BAAANQAECgQJCwAAAA==.',
Ha='Hannsollo:BAAANQADCgMIAwAAAA==.',
Ho='Holyshock:BAAANQABCgYIEAAAAA==.',
['Hâ']='Hâmburger:BAAANQADCgIIAgAAAA==.',
Ir='Iridessa:BAAANQADCgcIEwAAAA==.',
Is='Ishpoo:BAABNQAECn8tAAMDAAoKdhW2YgByAgADAAoKdhW2YgByAgAXAAEKAABgfwAdAAAAAA==.',
Ja='Jangarinna:BAAANQADCgQIBAAAAA==.',
Ji='Jip:BAAANQAECgUIBgAAAA==.',
Jl='Jlawq:BAAANQADCgUIBQAAAA==.Jlawzzs:BAABNQAECn8rAAIJAAkK+xcdTgAsAgAJAAkK+xcdTgAsAgAAAA==.',
Jo='Job:BAABNQAECn81AAISAAkK+CXSBACmAwASAAkK+CXSBACmAwAAAA==.',
Ju='Judgim:BAAANQADCgQIBAABNQAECgUIBAAFAAAAAA==.Judoriel:BAAANQAECgMIAwAAAA==.Junkyard:BAAANQADCgcIBwAAAA==.',
Ka='Kaimin:BAABNQAECn8zAAIYAAoKkhyIAgBGAgAYAAoKkhyIAgBGAgAAAA==.Karthas:BAAANQADCgUIBQAAAA==.Karuun:BAAANQAECgQIBAABNQAECgkJGQAOALoMAA==.',
Ke='Kezeshi:BAABNQAECn8XAAITAAgKoAm5DABsAQATAAgKoAm5DABsAQAAAA==.',
Kh='Khaidralulz:BAABNQAECn8vAAMJAAoKXBCvZQDcAQAJAAkKaA6vZQDcAQAZAAUKPQ2dDgAWAQAAAA==.Khonsu:BAAANQAECgIIAgAAAA==.',
Ki='Kiba:BAABNQAECn8iAAMaAAYKmQ11EgC8AAAaAAYKmQ11EgC8AAAbAAUKNQqUIwCTAAAAAA==.',
Kr='Kraegen:BAAANQAECggIEQAAAA==.',
Ky='Kyofu:BAABNQAECn87AAMaAAoK1Bz6CgDWAgAaAAoK1Bz6CgDWAgAbAAQKiBaqQgACAQAAAA==.',
La='Larenta:BAABNQAECn8qAAICAAoKiSArDABmAwACAAoKiSArDABmAwAAAA==.Larethiana:BAACNQAFFH8FAAIGAAUKfhKnBwCAAQAGAAUKfhKnBwCAAQA1AAQKfyYAAgYACgqvHygOAO8CAAYACgqvHygOAO8CAAE1AAQKCAgNAAUAAAAA.Laria:BAAANQAECggIDQAAAA==.',
Le='Leafmochi:BAAANQAECgQIBQAAAA==.Letloose:BAAANQADCgEIAQAAAA==.',
Li='Lightbright:BAACNQAFFH8FAAIDAAIKQAudDwCNAAADAAIKQAudDwCNAAA1AAQKfysAAgMACgpBI+spAB8DAAMACgpBI+spAB8DAAAA.Lildab:BAABNQAECn80AAIcAAoKCRDZBwB3AQAcAAoKCRDZBwB3AQAAAA==.Linashia:BAABNQAECn8hAAIUAAkKMRNmTABAAgAUAAkKMRNmTABAAgAAAA==.',
Lo='Lostwanderer:BAAANQADCggIDgAAAA==.',
Lu='Luhen:BAAANQADCgYIBgAAAA==.',
Ma='Magicology:BAABNQAECn9hAAIBAAkKkCZ2AQD2AwABAAkKkCZ2AQD2AwAAAA==.Maimim:BAAANQAECgUIBAAAAA==.Malacoda:BAABNQAECn8tAAISAAoKhhwyGQDRAgASAAoKhhwyGQDRAgAAAA==.Manamommy:BAABNQAECn8aAAIBAAkKABkWdACVAgABAAkKABkWdACVAgAAAA==.Marble:BAAANQADCgYIBwAAAA==.',
Me='Merlx:BAAANQADCggIEQAAAA==.',
Mi='Miladee:BAAANQADCgYIBgAAAA==.Mindra:BAABNQAECn8WAAIPAAgKdxgHZABNAgAPAAgKdxgHZABNAgAAAA==.',
Mo='Moatie:BAAANQADCgQIBQAAAA==.Moobundo:BAABNQAECn8XAAMJAAoKmBBXHwBsAQAJAAkKhxBXHwBsAQAIAAEKAABOVwEhAAAAAA==.Moonmama:BAAANQADCgQIBAAAAA==.Moonwren:BAAANQAECggIEQAAAA==.Morgrin:BAAANQAECgYIDwAAAA==.',
Ne='Nezroz:BAAANQAECgYIBgABNQAECgcIIwARAA4TAA==.',
Ni='Nicotine:BAAANQAECggIDAAAAA==.Nike:BAABNQAECn8jAAMVAAoKnRwuBAB2AQAEAAkKihohVwCGAgAVAAcKwx0uBAB2AQAAAA==.Nipsey:BAAANQADCgYIBgAAAA==.Nitwp:BAABNQAECn80AAMdAAkKnhsOCQDjAgAdAAkKnhsOCQDjAgAeAAUK5w87MAAbAQAAAA==.Nizo:BAAANQAECgUIDwAAAA==.',
Nj='Njal:BAAANQADCgUIBQAAAA==.',
No='Novastrike:BAACNQAFFH8LAAMIAAQKdwajCADIAAAIAAQKdwajCADIAAAJAAEKXQDeNAAlAAA1AAQKfysAAwgACgqrGyg7AIkCAAgACQqsGig7AIkCAAkAAwp1A1IHAVkAAAAA.',
Ny='Nymphia:BAAANQAECgUIBwAAAA==.Nyrif:BAABNQAECn8oAAIOAAoKmhoTHgDBAgAOAAoKmhoTHgDBAgAAAA==.',
Oj='Ojoon:BAABNQAECn8WAAIBAAcKPwdUgADAAAABAAcKPwdUgADAAAAAAA==.',
Om='Omnisllash:BAABNQAECn8WAAILAAgKZxcrCQBFAgALAAgKZxcrCQBFAgAAAA==.',
Pa='Pallamb:BAAANQAECgQIBAAAAA==.',
Ph='Phyter:BAAANQAECgQIBwAAAA==.',
Pi='Pillin:BAAANQAECgYIDAAAAA==.',
Po='Polyestr:BAAANQADCgQIBAAAAA==.Porkchowmein:BAAANQAECgMIAwAAAA==.',
Pr='Previousleon:BAAANQAECggIBAAAAA==.',
Ps='Psylence:BAAANQAECgMIBgAAAA==.Psyrge:BAAANQAECgQIBgAAAA==.',
Qu='Queue:BAABNQAECn8ZAAIOAAkKugwJGAApAQAOAAkKugwJGAApAQAAAA==.',
Re='Redle:BAAANQADCggICgAAAA==.',
Rh='Rhordric:BAEBNQAECn8tAAQWAAoKfRVuKAAGAgAWAAkKrxNuKAAGAgAPAAcKwRHynADNAQAfAAEKKwfqFAAmAAAAAA==.',
Ro='Roku:BAAANQAECgIIAgAAAA==.Rottenbeef:BAAANQAECgcICAAAAA==.',
Ru='Runicmommy:BAAANQADCgUIBQAAAA==.',
Sa='Saintbull:BAAANQABCgYIBwAAAA==.Samwinchestr:BAAANQADCgIIAgAAAA==.Sanyoalt:BAAANQADCgEIAQAAAA==.',
Sc='Scemo:BAAANQADCgUIBQAAAA==.Scissorsista:BAAANQADCgIIAgAAAA==.',
Se='Sea:BAACNQAFFH8VAAIJAAYK7xsYBQAiAgAJAAYK7xsYBQAiAgA1AAQKfyoAAgkACgr0JP8HAIEDAAkACgr0JP8HAIEDAAAA.Sepsis:BAAANQAECggICAAAAA==.Serendipity:BAAANQAECgQIBwAAAA==.',
Sh='Shadowaurora:BAAANQADCggJCAAAAA==.Shadowrose:BAABNQAECn8ZAAMMAAcKMhUhFAC6AQAMAAcKMhUhFAC6AQAHAAEKAACcxwAbAAAAAA==.Shamano:BAAANQAECgQIBgABNQAECgUIIgAgAD0dAA==.Shanogadin:BAAANQAECgQIBgAAAA==.Shiemi:BAAANQAECgUICgAAAA==.',
So='Sotospeak:BAAANQABCggIDQAAAA==.',
Sq='Squeaky:BAAANQAECgYICwAAAA==.',
St='Starshade:BAAANQAECgUIBQAAAA==.Steeldeath:BAAANQADCgEIAQAAAA==.',
Su='Sungodess:BAAANQAECgMIAwAAAA==.',
Sy='Syrupp:BAABNQAECn8fAAIhAAoKehZoEACCAQAhAAoKehZoEACCAQAAAA==.',
Ta='Tayn:BAAANQADCgcJDAAAAA==.',
Th='Thackery:BAAANQADCggICwAAAA==.Thinsheets:BAAANQADCgcICwABNQAECgcIEAAFAAAAAA==.',
Tr='Trenetalan:BAAANQADCgIJAgABNQADCggIEAAFAAAAAA==.',
Ts='Tsavø:BAAANQAECgQJBAAAAA==.',
Tw='Twinkle:BAABNQAECn8YAAICAAkKShd9IQBgAQACAAkKShd9IQBgAQAAAA==.',
Un='Unholysage:BAABNQAECn8dAAMTAAgK6Q+yEAAeAQATAAYK4g6yEAAeAQAcAAcK3wyuEAALAQAAAA==.Untouchable:BAAANQADCgEIAQAAAA==.',
Va='Valenîx:BAAANQAECgYIBwABNQAECgoKHQAdAPwIAA==.',
Ve='Venetrazat:BAABNQAECn86AAIdAAoKUhjfAQDOAQAdAAoKUhjfAQDOAQAAAA==.',
Vo='Vo:BAAANQADCgYIDQAAAA==.Vol:BAAANQADCgUIBQAAAA==.',
Vu='Vulpra:BAABNQAECn8XAAMUAAkK9Ah0JgBlAQAUAAgKoAl0JgBlAQAcAAEKAABhQQAAAAAAAA==.',
['Vâ']='Vâlenix:BAABNQAECn8dAAMdAAoK/AiBHQB3AQAdAAkKCAqBHQB3AQAeAAcKIAgdKgBeAQAAAA==.',
['Vä']='Välenix:BAAANQAECgIIAgABNQAECgoKHQAdAPwIAA==.',
Wa='Warder:BAAANQAECgcIDQAAAA==.',
We='Wewaskangz:BAAANQAECgUIBgAAAA==.',
Wi='Wincks:BAABNQAECn8iAAQgAAUKPR1LDACeAQAgAAUKPR1LDACeAQAiAAIKxArOIQF/AAAjAAEKfA5tdgA3AAAAAA==.',
Xh='Xhosar:BAABNQAECn80AAIfAAoKSxJcBACiAgAfAAoKSxJcBACiAgAAAA==.',
Za='Zachthemage:BAABNQAECn8fAAIBAAgK4gpl1QDcAQABAAgK4gpl1QDcAQAAAA==.Zackman:BAACNQAFFH8FAAICAAIKjQfHDgCBAAACAAIKjQfHDgCBAAA1AAQKfzUAAgIACgoqEDFYABACAAIACgoqEDFYABACAAAA.',
Zi='Zinatrax:BAAANQADCgYIDAAAAA==.',
Zo='Zombie:BAABNQAECn8iAAIYAAgK8RsVRAAKAgAYAAgK8RsVRAAKAgAAAA==.',
Zu='Zuldrakar:BAAANQADCgUICQAAAA==.Zulrea:BAABNQAECn84AAIHAAkKCxt6BAATAgAHAAkKCxt6BAATAgAAAA==.',
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
