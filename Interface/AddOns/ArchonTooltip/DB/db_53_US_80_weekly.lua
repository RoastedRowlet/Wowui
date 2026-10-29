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

local lookup = {'Mage-Arcane','Paladin-Retribution','Paladin-Holy','Evoker-Preservation','Warrior-Arms','Unknown-Unknown','Druid-Restoration','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Mage-Frost','Druid-Feral','Warrior-Protection','DeathKnight-Blood','Hunter-BeastMastery','Mage-Fire','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','DeathKnight-Unholy','Hunter-Marksmanship','Paladin-Protection','Monk-Mistweaver','Monk-Windwalker','Priest-Shadow','Warrior-Fury','Evoker-Devastation','Hunter-Survival','Warlock-Affliction','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction',}
local provider = {region='US',realm='Dunemaul',name='US',type='weekly',zone=53,date='2026-10-27',data={Al='Aletalle:BAAANQAECgQIBAAAAA==.Allice:BAABNQAECn8iAAIBAAkKihapqAAwAgABAAkKihapqAAwAgAAAA==.Alsheyra:BAAANQADCgYICgAAAA==.Alterion:BAAANQAECgEIAQAAAA==.',
An='Anxious:BAAANQADCgYIEwAAAA==.',
As='Ashwalker:BAABNQAECn8bAAMCAAcKDQrUwgDYAAACAAYKyQbUwgDYAAADAAYKdgJ83gDCAAAAAA==.',
Au='Aughyst:BAAANQAECgUICwAAAA==.Augnyxia:BAAANQAECgQIDAAAAA==.Augtysm:BAAANQADCggICAAAAA==.Augy:BAAANQAECgcICwAAAA==.',
Ba='Bandobras:BAAANQADCgcIDgAAAA==.Bangtwinkdh:BAAANQAECgIIAgABNQAFFAgIFwAEABEVAA==.',
Be='Berafii:BAAANQAECgEIAQAAAA==.',
Bh='Bhorg:BAAANQADCgMIAwAAAA==.',
Bl='Blackdust:BAAANQADCggIDQAAAA==.Blast:BAAANQAECggICwABNQAFFAcIHwAFAGQiAA==.Blasters:BAAANQADCgcIEgAAAA==.Bloodjury:BAABNQAECn8XAAICAAgKywwVyACMAQACAAgKywwVyACMAQAAAA==.Blossom:BAAANQABCgIIAgABNQABCgYICwAGAAAAAA==.',
Bo='Boejo:BAAANQAECggIDwAAAA==.Boonktown:BAAANQADCgYIBgAAAA==.Borellus:BAAANQABCgUICQAAAA==.',
Br='Broken:BAAANQAECgEIBgAAAA==.',
Bu='Bunga:BAAANQAECgEIAQAAAA==.Bungis:BAABNQAECn8UAAIDAAoKgBjXSgA9AgADAAoKgBjXSgA9AgAAAA==.Bushetti:BAABNQAECn8XAAMHAAkKphbFHgA4AgAHAAgKSBbFHgA4AgAIAAIKAADcnwBfAAAAAA==.',
Ca='Casperface:BAABNQAECn8pAAMJAAoKxxMRcwDHAQAJAAgKTA4RcwDHAQAKAAMK1AqvqQBmAAAAAA==.Cazisham:BAABNQAECn8XAAILAAgKzwHpLQCKAAALAAgKzwHpLQCKAAAAAA==.',
Ce='Cestus:BAAANQAECgcJEAAAAA==.Cevianne:BAAANQAECgIIAwAAAA==.',
Ci='Ciaphis:BAABNQAECn8lAAICAAkK3AlrkgAtAQACAAkK3AlrkgAtAQAAAA==.Cinnabuns:BAAANQADCgQIAwAAAA==.',
Co='Coal:BAABNQAECn8rAAIMAAoKnSJXAQD/AgAMAAoKnSJXAQD/AgAAAA==.Coltonater:BAACNQAFFH8TAAIBAAcKmRrRBgB/AQABAAcKmRrRBgB/AQA1AAQKf1gAAgEACgoQJgACAO4DAAEACgoQJgACAO4DAAAA.',
['Cá']='Cáséy:BAACNQAFFH8QAAMNAAUKgRf/AACSAQANAAUKgRf/AACSAQABAAEKAAA7PQAAAAA1AAQKf0EAAw0ACgrUIrEBAHADAA0ACgrUIrEBAHADAAEAAwqGEnUOAU8AAAAA.',
['Cä']='Cäsey:BAAANQAECgQIBAABNQAFFAUIEAANAIEXAA==.',
Da='Darkshroud:BAAANQAECgQICAAAAA==.Datbi:BAABNQAECn8pAAMIAAoK0xGyOAApAgAIAAoKuA+yOAApAgAOAAMK6hfYHACZAAAAAA==.Daugi:BAABNQAECn8mAAMPAAoKvh7lBwDXAgAPAAcKSyPlBwDXAgAFAAoK4hfALgAfAgAAAA==.',
De='Deathangel:BAAANQAECgYIDgAAAA==.Deathdeamon:BAAANQADCgMIAwAAAA==.Deathdylan:BAACNQAFFH8HAAIQAAMKPg56DgC0AAAQAAMKPg56DgC0AAA1AAQKfyoAAhAACgpPH/0ZAN4CABAACgpPH/0ZAN4CAAAA.Delice:BAAANQAECggICgAAAA==.Demonikal:BAAANQAECgQIBAAAAA==.Demonware:BAAANQAECgQIBAAAAA==.Demítríus:BAAANQAECgcIEwAAAA==.Dethh:BAABNQAECn8lAAIRAAcKPxNLfQA5AQARAAcKPxNLfQA5AQAAAA==.',
Di='Didona:BAAANQADCgYIBgAAAA==.Distortion:BAAANQAECgUIBwAAAA==.Divineflava:BAAANQAECgUIBgABNQAFFAQICQABAPMTAA==.',
Do='Dobby:BAAANQADCggIDQAAAA==.',
Dr='Drakeo:BAABNQAECn8XAAIHAAcKhAtxOwBFAQAHAAcKhAtxOwBFAQAAAA==.Draximus:BAAANQAECgcIEwAAAA==.Drougenin:BAAANQAECggICAABNQAECgoKKwAMAJ0iAA==.Drpumper:BAAANQAECgcIEwAAAA==.Druqz:BAACNQAFFH8FAAINAAMKnAKRDwA5AAANAAMKnAKRDwA5AAA1AAQKfyoAAg0ACgoUE4UJADoCAA0ACgoUE4UJADoCAAAA.Druski:BAAANQABCgQIBAAAAA==.Drævn:BAABNQAECn8wAAISAAoKwheCAgAZAgASAAoKwheCAgAZAgAAAA==.',
Du='Dum:BAACNQAFFH8SAAQMAAYK1BksAwDhAAATAAMKwxzcCgAgAQAMAAMKGh0sAwDhAAAUAAMKzhRwFgCIAAA1AAQKfy8ABBMACgpTId4OAP4CABMACgoHId4OAP4CAAwABwqLGsYKACkCABQABArgIXdXAC0BAAAA.Duragon:BAABNQAECn8fAAIFAAgK+gM9DgHAAAAFAAgK+gM9DgHAAAAAAA==.Durkagon:BAAANQAECgQICgAAAA==.',
Dw='Dwimbear:BAAANQAECgEIAwAAAA==.Dwimhoof:BAAANQAECgEIBQAAAA==.Dwinnet:BAAANQAECgEIAQAAAA==.',
El='Eldin:BAACNQAFFH8FAAIVAAIKawsXAQCPAAAVAAIKawsXAQCPAAA1AAQKfywAAxUACgpJJFgBAEYDABUACgo2JFgBAEYDABYAAQpqJVWrAG0AAAAA.',
En='Endofdays:BAABNQAECn8cAAMXAAkKuhh4DABWAgAXAAkKuhh4DABWAgAQAAEKgwaN2wAjAAAAAA==.Enro:BAACNQAFFH8IAAIUAAMK1AwPCQDYAAAUAAMK1AwPCQDYAAA1AAQKfy0AAxQACgoYHOMhAIwCABQACgoYHOMhAIwCABMAAQpeDydCAD4AAAAA.',
Er='Erovia:BAABNQAECn8rAAIRAAoKrRGJgAAMAgARAAoKrRGJgAAMAgAAAA==.',
Es='Esclipse:BAAANQADCgYIBgAAAA==.',
Et='Etclock:BAAANQADCgYIBgAAAA==.',
Fa='Faeria:BAAANQABCgQIBAAAAA==.Farruq:BAAANQAECgUJCwAAAA==.Fathermoo:BAAANQAECgEIAQAAAA==.',
Fe='Feelsbadmang:BAAANQADCgQIBAABNQAECgoKJwAFAGcfAA==.Fellz:BAAANQADCgIIAgAAAA==.Ferer:BAEANQAECgEIAQABNQAFFAMIBgAYAOAGAA==.Ferian:BAAANQAECgQIEAAAAA==.Ferios:BAEANQADCgMIAwAAAA==.',
Fi='Fieth:BAAANQAECgEIAQAAAA==.',
Fl='Flavaflare:BAACNQAFFH8JAAIBAAQK8xMHJACiAAABAAQK8xMHJACiAAA1AAQKf1AAAgEACgpPI9cQAI8DAAEACgpPI9cQAI8DAAAA.',
Fo='Foodex:BAABNQAECn8UAAIWAAYKzxz/cgDDAQAWAAYKzxz/cgDDAQAAAA==.Fourleaf:BAACNQAFFH8IAAIYAAMKyg1LCgDEAAAYAAMKyg1LCgDEAAA1AAQKfy0AAhgACgpfHQMWAKsCABgACgpfHQMWAKsCAAAA.',
Fr='Frogplushy:BAABNQAECn8jAAIBAAoKmh+MNAAfAgABAAoKmh+MNAAfAgAAAA==.',
Fu='Furlock:BAAANQAECgQIDwAAAA==.Furral:BAABNQAECn80AAIOAAoKVxzDAwCQAgAOAAoKVxzDAwCQAgAAAA==.Furretc:BAAANQADCgEIAQAAAA==.',
Ga='Gaeth:BAABNQAECn8rAAIHAAoKxRNFJQD5AQAHAAoKxRNFJQD5AQAAAA==.Gardenhose:BAAANQAECgYICAAAAA==.',
Ge='Gengiss:BAAANQADCgQIBAAAAA==.',
Gl='Gleg:BAACNQAFFH8PAAMKAAMKrBn7FwDgAAAKAAMKrBn7FwDgAAAJAAIKuggTKACKAAA1AAQKfzIAAwoACgpgIpUXABYDAAoACgpgIpUXABYDAAkAAQoAAEsvAToAAAAA.',
Go='Goodside:BAAANQADCgYIDAAAAA==.',
Gr='Grimthebrave:BAABNQAECn8gAAIFAAoKoRrFKwAuAgAFAAoKoRrFKwAuAgAAAA==.Grimthecruel:BAABNQAECn8uAAQTAAoKnxfOGgCBAgATAAoK3hXOGgCBAgAMAAQKhRzNDQD4AAAUAAEK+RQSjwA9AAAAAA==.Grimthedread:BAAANQAECggIDwAAAA==.Gripless:BAAANQADCgQIBAAAAA==.Griselden:BAABNQAECn87AAITAAoKZh6MCgBNAgATAAoKZh6MCgBNAgAAAA==.Grizzlyras:BAAANQADCggICAAAAA==.',
Gu='Gub:BAAANQAECgQJCwAAAA==.',
Ha='Hannsollo:BAAANQADCgMIAwAAAA==.',
Ho='Holyshock:BAAANQABCgYIEAAAAA==.',
['Hâ']='Hâmburger:BAAANQADCgIIAgAAAA==.',
Ir='Iridessa:BAAANQADCgcIEwAAAA==.',
Is='Ishpoo:BAABNQAECn8vAAMCAAoKdhW2YgByAgACAAoKdhW2YgByAgAZAAEKAABgfwAdAAAAAA==.',
Ja='Jangarinna:BAAANQAECgEIBQAAAA==.',
Ji='Jip:BAAANQAECgcIDQAAAA==.',
Jl='Jlawq:BAAANQADCgUIBQAAAA==.Jlawzzs:BAABNQAECn8xAAIKAAoKehYdTgAsAgAKAAoKehYdTgAsAgAAAA==.',
Jo='Job:BAABNQAECn87AAIUAAoK8CPSBACmAwAUAAoK8CPSBACmAwAAAA==.',
Ju='Judgim:BAAANQADCgQIBAABNQAECgUIBQAGAAAAAA==.Judoriel:BAAANQAECgUIBQAAAA==.Junkyard:BAAANQADCgcIBwAAAA==.',
Ka='Kaimin:BAABNQAECn87AAIXAAoKBx51GwDnAgAXAAoKBx51GwDnAgAAAA==.Karthas:BAAANQADCgUIBQAAAA==.Karuun:BAAANQAECgUIBQABNQAECgoKIQAQAIAMAA==.',
Ke='Kezeshi:BAABNQAECn8XAAIVAAgKoAm5DABsAQAVAAgKoAm5DABsAQAAAA==.',
Kh='Khaidralulz:BAABNQAECn8xAAMKAAoKXBCvZQDcAQAKAAkKaA6vZQDcAQALAAUKPQ0xGQABAQAAAA==.Khonsu:BAAANQAECgIIAgAAAA==.',
Ki='Kiba:BAABNQAECn8qAAMaAAcKCRCCEgBQAQAaAAcKCRCCEgBQAQAbAAUKNQoENgCEAAAAAA==.',
Kr='Kraegen:BAAANQAECggIEgAAAA==.',
Ky='Kyofu:BAABNQAECn9AAAMaAAoK1Bz6CgDWAgAaAAoK1Bz6CgDWAgAbAAQKiBaqQgACAQAAAA==.',
La='Larenta:BAABNQAECn80AAIDAAoKKSMcBACdAwADAAoKKSMcBACdAwAAAA==.Larethiana:BAACNQAFFH8FAAIHAAUKfhKnBwCAAQAHAAUKfhKnBwCAAQA1AAQKfyYAAgcACgqvHygOAO8CAAcACgqvHygOAO8CAAE1AAQKCAgNAAYAAAAA.Laria:BAAANQAECggIDQAAAA==.',
Le='Leafmochi:BAAANQAECgQIBQAAAA==.Letloose:BAAANQADCgEIAQAAAA==.',
Li='Lightbright:BAACNQAFFH8FAAICAAIKQAsDGQCEAAACAAIKQAsDGQCEAAA1AAQKfzQAAgIACgqJI6kRAOsCAAIACgqJI6kRAOsCAAAA.Lildab:BAABNQAECn8+AAIcAAoKHBCPDwDWAQAcAAoKHBCPDwDWAQAAAA==.Linashia:BAABNQAECn8kAAIWAAoKDxJmTABAAgAWAAoKDxJmTABAAgAAAA==.',
Lo='Lomein:BAAANQAECgEIAQAAAA==.Lostwanderer:BAAANQADCggIDgAAAA==.',
Lu='Luhen:BAAANQADCgYIBgAAAA==.',
Ma='Magicology:BAABNQAECn9hAAIBAAkKkCZ2AQD2AwABAAkKkCZ2AQD2AwAAAA==.Maimim:BAAANQAECgUIBQAAAA==.Malacoda:BAABNQAECn8wAAIUAAoKhhwyGQDRAgAUAAoKhhwyGQDRAgAAAA==.Manamommy:BAABNQAECn8bAAIBAAkKaxkWdACVAgABAAkKaxkWdACVAgAAAA==.Marble:BAAANQADCgYIBwAAAA==.',
Me='Merlx:BAAANQADCggIEQAAAA==.',
Mi='Mickrib:BAAANQAECggIAQAAAA==.Miladee:BAAANQADCgYIBgAAAA==.Mindra:BAABNQAECn8XAAIRAAgKdxgHZABNAgARAAgKdxgHZABNAgAAAA==.',
Mo='Moatie:BAAANQADCgQIBQAAAA==.Moobundo:BAABNQAECn8aAAMKAAoKBhImQgCOAQAKAAkKHhImQgCOAQAJAAEKAABOVwEhAAAAAA==.Moolasses:BAAANQAECgMIAwAAAA==.Moonmama:BAAANQADCgQIBAAAAA==.Moonwren:BAAANQAECggIEQAAAA==.Morgrin:BAAANQAECgYIEwAAAA==.',
Ne='Nezroz:BAAANQAECgYIBwABNQAECgcIKQATAE4UAA==.',
Ni='Nicotine:BAAANQAECggIEAAAAA==.Nike:BAABNQAECn8nAAMFAAoKZx8hVwCGAgAFAAkKVB0hVwCGAgAdAAcKwx11CwBFAQAAAA==.Nipsey:BAAANQAECgEIAQAAAA==.Nitwp:BAABNQAECn82AAMeAAoKyBwOCQDjAgAeAAkKnhsOCQDjAgAEAAYKCQ87MAAbAQAAAA==.Nizo:BAAANQAECgUIDwAAAA==.',
Nj='Njal:BAAANQADCgUIBQAAAA==.',
No='Novastrike:BAACNQAFFH8OAAMJAAQK0QvDDADOAAAJAAQK0QvDDADOAAAKAAEKXQDeNAAlAAA1AAQKfy4AAwkACgqoGyg7AIkCAAkACgqoGyg7AIkCAAoAAwp1A1IHAVkAAAAA.',
Ny='Nymphia:BAAANQAECgUICgAAAA==.Nyrif:BAACNQAFFH8FAAIQAAIKKA2qFQBqAAAQAAIKKA2qFQBqAAA1AAQKfy0AAhAACgocHRMeAMECABAACgocHRMeAMECAAAA.',
Oj='Ojoon:BAABNQAECn8WAAIBAAcKPwfjHwFXAQABAAcKPwfjHwFXAQAAAA==.',
Om='Omnisllash:BAABNQAECn8cAAINAAkK3hYrCQBFAgANAAkK3hYrCQBFAgAAAA==.',
Pa='Pallamb:BAAANQAECgQIBAAAAA==.Pallymaster:BAAANQAECgEIAQAAAA==.',
Ph='Phyter:BAAANQAECgQICwAAAA==.',
Pi='Pillin:BAAANQAECgcIDQAAAA==.',
Po='Polyestr:BAAANQADCgQIBAAAAA==.Porkchowmein:BAAANQAECgMIBAAAAA==.',
Pr='Previousleon:BAAANQAECggIBgAAAA==.Prosmas:BAAANQAECgIIAgAAAA==.',
Ps='Psyffe:BAAANQAECgEIAQAAAA==.Psylence:BAAANQAECgMICAAAAA==.Psyrge:BAAANQAECgUIBwAAAA==.',
Qu='Queue:BAABNQAECn8hAAIQAAoKgAzIIgB9AQAQAAoKgAzIIgB9AQAAAA==.',
Re='Redle:BAAANQADCggICgAAAA==.',
Rh='Rhordric:BAECNQAFFH8GAAIYAAMK4Aa8CgC7AAAYAAMK4Aa8CgC7AAA1AAQKfzEABBgACgqVF24oAAYCABgACQoUFm4oAAYCABEABwrBEfKcAM0BAB8AAQorB+oUACYAAAAA.',
Ri='Ringa:BAAANQAECgEIAQAAAA==.',
Ro='Roku:BAAANQAECgIIAgAAAA==.Rottenbeef:BAAANQAECgcIDQAAAA==.',
Ru='Runicmommy:BAAANQADCgUIBQAAAA==.',
Sa='Saintbull:BAAANQABCgYIBwAAAA==.Samwinchestr:BAAANQADCgIIAgAAAA==.Sanyoalt:BAAANQADCgEIAQAAAA==.',
Sc='Scemo:BAAANQADCgUIBQAAAA==.Scissorsista:BAAANQADCgcICQAAAA==.',
Se='Sea:BAACNQAFFH8VAAIKAAYK7xsYBQAiAgAKAAYK7xsYBQAiAgA1AAQKfzQAAgoACgr0JP8HAIEDAAoACgr0JP8HAIEDAAAA.Sepsis:BAAANQAECggICAAAAA==.Serendipity:BAAANQAECgQICgAAAA==.',
Sh='Shadowaurora:BAAANQADCggJCAAAAA==.Shadowrose:BAABNQAECn8eAAMOAAgKLhYhFAC6AQAOAAgKLhYhFAC6AQAIAAEKAACcxwAbAAAAAA==.Shamano:BAAANQAECgQICQABNQAECggIKgAgAFUXAA==.Shanogadin:BAAANQAECgQICAAAAA==.Shiemi:BAAANQAECgUIDAAAAA==.',
Sk='Skirata:BAAANQAECgEIAQAAAA==.',
Sl='Slashysally:BAAANQAECgEIAQAAAA==.',
So='Soju:BAAANQAECgQIBAAAAA==.Sotospeak:BAAANQAECgEIAQAAAA==.',
Sq='Squeaky:BAAANQAECgcIEQAAAA==.',
St='Starshade:BAAANQAECgUIBQAAAA==.Steeldeath:BAAANQADCgEIAQAAAA==.',
Su='Sungodess:BAAANQAECgMIAwAAAA==.',
Sy='Syrupp:BAABNQAECn8mAAIhAAoKoBhkGwDyAQAhAAoKoBhkGwDyAQAAAA==.',
Ta='Tayn:BAAANQADCgcJDAAAAA==.',
Th='Thackery:BAAANQADCggICwAAAA==.Thinsheets:BAAANQAECgEIAQABNQAECggIFwACAMsMAA==.',
Tr='Trenetalan:BAAANQADCgIJAgABNQADCggIEAAGAAAAAA==.Trickledown:BAAANQAECgUIBQAAAA==.',
Ts='Tsavø:BAAANQAECgQJBgAAAA==.',
Tw='Twinkle:BAABNQAECn8YAAIDAAkKShcMUwAhAgADAAkKShcMUwAhAgAAAA==.',
Un='Unholysage:BAABNQAECn8jAAMVAAgK6Q+yEAAeAQAVAAYK4g6yEAAeAQAcAAcKfg1vIAAEAQAAAA==.Untouchable:BAAANQADCgEIAQAAAA==.',
Va='Valathiel:BAAANQADCgUIBQAAAA==.Valenîx:BAAANQAECgYICAABNQAECgoKHgAeAPwIAA==.',
Ve='Venetrazat:BAABNQAECn9AAAIeAAoKQxnZBQDoAQAeAAoKQxnZBQDoAQAAAA==.Vermithorr:BAAANQAECgEIAQAAAA==.',
Vi='Viserys:BAAANQAECgYICAAAAA==.',
Vo='Vo:BAAANQAECgEIAQAAAA==.Vol:BAAANQADCgUIBQAAAA==.',
Vu='Vulpra:BAABNQAECn8eAAMWAAkKtwycRgCWAQAWAAgK3A2cRgCWAQAcAAEKAAADXAAAAAAAAA==.',
['Vâ']='Vâlenix:BAABNQAECn8eAAMeAAoK/AiBHQB3AQAeAAkKCAqBHQB3AQAEAAcKIAgdKgBeAQAAAA==.',
['Vä']='Välenix:BAAANQAECgIIAgABNQAECgoKHgAeAPwIAA==.',
Wa='Warder:BAABNQAECn8UAAIdAAgKVA+jFABVAQAdAAgKVA+jFABVAQAAAA==.',
We='Wewaskangz:BAAANQAECgUICgAAAA==.',
Wi='Wincks:BAABNQAECn8qAAQgAAgKVRcIBgBtAQAgAAcKHBoIBgBtAQAiAAMKGwrOIQF/AAAjAAEKfA5tdgA3AAAAAA==.',
Xh='Xhosar:BAABNQAECn88AAIfAAoKpRJcBACiAgAfAAoKpRJcBACiAgAAAA==.',
['Yú']='Yúffíe:BAAANQADCgYIBgAAAA==.',
Za='Zachthemage:BAABNQAECn8pAAIBAAgKAgtl1QDcAQABAAgKAgtl1QDcAQAAAA==.Zackman:BAACNQAFFH8IAAIDAAMKfAaSEAC/AAADAAMKfAaSEAC/AAA1AAQKfz4AAgMACgpgFf4jACsCAAMACgpgFf4jACsCAAAA.',
Zi='Zinatrax:BAAANQAECgEIAQAAAA==.',
Zo='Zombie:BAABNQAECn8iAAIXAAgK8RsVRAAKAgAXAAgK8RsVRAAKAgAAAA==.',
Zu='Zuldrakar:BAAANQADCgUICQAAAA==.Zulrea:BAABNQAECn9GAAIIAAoK1xv7CwCMAgAIAAoK1xv7CwCMAgAAAA==.',
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
