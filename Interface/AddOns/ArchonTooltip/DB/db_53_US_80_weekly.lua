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

local lookup = {'Mage-Arcane','Paladin-Retribution','Paladin-Holy','Evoker-Preservation','Warrior-Arms','Druid-Restoration','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Mage-Frost','Druid-Feral','Warrior-Protection','DeathKnight-Blood','Hunter-BeastMastery','Mage-Fire','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','Hunter-Marksmanship','Paladin-Protection','Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Warrior-Fury','Evoker-Devastation','Hunter-Survival','Warlock-Affliction','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction',}
local provider = {region='US',realm='Dunemaul',name='US',type='weekly',zone=53,date='2026-11-03',data={Al='Aletalle:BAAANQAECgQIBAAAAA==.Allice:BAABNQAECn8rAAIBAAkKMRhxRQAYAgABAAkKMRhxRQAYAgAAAA==.Alsheyra:BAAANQADCgYICgAAAA==.Alterion:BAAANQABCgQICgAAAA==.',
An='Anxious:BAAANQADCgYIEwAAAA==.',
As='Ashwalker:BAABNQAECn8bAAMCAAcKDQrA6ADSAAACAAYKyQbA6ADSAAADAAYKdgJ83gDCAAAAAA==.',
Au='Aughyst:BAAANQAECgYICwAAAA==.Augnyxia:BAAANQAECgQICgAAAA==.Augtism:BAAANQAECgEIAQAAAA==.Augtysm:BAAANQADCggICQAAAA==.Augy:BAAANQAECgcICwAAAA==.',
Ba='Bandobras:BAAANQADCgcIDwAAAA==.Bangtwinkdh:BAAANQAECgIIAgABNQAFFAgIGAAEABEVAA==.',
Be='Berafii:BAAANQADCgEIAQAAAA==.',
Bh='Bhorg:BAAANQADCgMIAwAAAA==.',
Bl='Blackdust:BAAANQADCggIDQAAAA==.Blast:BAAANQAECggICgABNQAFFAcIHwAFAGQiAA==.Blasters:BAAANQADCgcIEgAAAA==.Bloodjury:BAABNQAECn8bAAICAAgKywwVyACMAQACAAgKywwVyACMAQAAAA==.Blossom:BAAANQADCgEIAQAAAA==.',
Bo='Boejo:BAAANQAECgcIEgAAAA==.Boonktown:BAAANQAECgUIBgAAAA==.Borellus:BAAANQADCgEIAQAAAA==.',
Br='Broken:BAAANQADCgYICAAAAA==.',
Bu='Bunga:BAAANQAECgEIAQAAAA==.Bungis:BAAANQAECggIEQAAAA==.Bushetti:BAABNQAECn8XAAMGAAkKphbFHgA4AgAGAAgKSBbFHgA4AgAHAAIKAADcnwBfAAAAAA==.',
Ca='Casperface:BAABNQAECn8pAAMIAAoKxxMRcwDHAQAIAAgKTA4RcwDHAQAJAAMK1AodxABkAAAAAA==.Cazisham:BAABNQAECn8bAAIKAAgK0wHpLQCKAAAKAAgK0wHpLQCKAAAAAA==.',
Ce='Cestus:BAAANQAECgcJDQAAAA==.Cevianne:BAAANQAECgIIAgAAAA==.',
Ci='Ciaphis:BAABNQAECn80AAICAAkKzgoLlABjAQACAAkKzgoLlABjAQAAAA==.Cinnabuns:BAAANQADCgQIBAAAAA==.',
Co='Coal:BAABNQAECn8uAAILAAoKxiIBAgDzAgALAAoKxiIBAgDzAgAAAA==.Coltonater:BAACNQAFFH8TAAIBAAcKmRoPCwBwAQABAAcKmRoPCwBwAQA1AAQKf18AAgEACgonJgACAO4DAAEACgonJgACAO4DAAAA.',
['Cá']='Cáséy:BAACNQAFFH8QAAMMAAUKgRf/AACSAQAMAAUKgRf/AACSAQABAAEKAADvRgAAAAA1AAQKf0YAAwwACgruIrEBAHADAAwACgruIrEBAHADAAEAAwqGErUpAU8AAAAA.',
['Cä']='Cäsey:BAAANQAECgQIBAABNQAFFAUIEAAMAIEXAA==.',
Da='Darkshroud:BAAANQAECgUIDQAAAA==.Datbi:BAABNQAECn8pAAMHAAoK0xGyOAApAgAHAAoKuA+yOAApAgANAAMK6he5JgCMAAAAAA==.Daugi:BAABNQAECn8nAAMOAAoKyR7lBwDXAgAOAAcKSyPlBwDXAgAFAAoK7RcwPwAYAgAAAA==.',
De='Deathangel:BAAANQAECgYICwAAAA==.Deathdeamon:BAAANQADCgMIAwAAAA==.Deathdylan:BAACNQAFFH8HAAIPAAMKPg4UEwCpAAAPAAMKPg4UEwCpAAA1AAQKfzMAAg8ACgrBH6ANAKMCAA8ACgrBH6ANAKMCAAAA.Delice:BAAANQAECggICAAAAA==.Demonikal:BAAANQAECgQIBAAAAA==.Demonware:BAAANQAECgQIBQAAAA==.Demítríus:BAABNQAECn8VAAIQAAgK+AZwoAAtAQAQAAgK+AZwoAAtAQAAAA==.Dethh:BAABNQAECn8lAAIQAAcKPxPssQCgAQAQAAcKPxPssQCgAQAAAA==.',
Di='Didona:BAAANQADCgYIBgAAAA==.Distortion:BAAANQAECgQIBgAAAA==.Divineflava:BAAANQAECgUIBgABNQAFFAQICgABAPMTAA==.',
Do='Dobby:BAAANQADCggIDQAAAA==.',
Dr='Drakeo:BAAANQAECgYIEwAAAA==.Draximus:BAABNQAECn8ZAAIQAAcK6RSNjwBOAQAQAAcK6RSNjwBOAQAAAA==.Drougenin:BAAANQAECggICAABNQAECgoKLgALAMYiAA==.Drpumper:BAAANQAECgcIEwAAAA==.Druqz:BAACNQAFFH8HAAIMAAMKnAJ8CwBcAAAMAAMKnAJ8CwBcAAA1AAQKfysAAgwACgoVE4UJADoCAAwACgoVE4UJADoCAAAA.Druski:BAAANQADCgEIAQAAAA==.Drævn:BAABNQAECn82AAIRAAoK3hl7AQAZAgARAAoK3hl7AQAZAgAAAA==.',
Du='Dum:BAACNQAFFH8SAAQLAAYK1BksAwDhAAASAAMKwxzcCgAgAQALAAMKGh0sAwDhAAATAAMKzhRwFgCIAAA1AAQKfzgABBIACgpjJXQGAOACABIACgoXJXQGAOACAAsABwqLGsYKACkCABMABArgIXdXAC0BAAAA.Duragon:BAABNQAECn8fAAIFAAgK+gM9DgHAAAAFAAgK+gM9DgHAAAAAAA==.Durkagon:BAAANQAECgQIBwAAAA==.',
Dw='Dwimbear:BAAANQADCgEIBAAAAA==.Dwinnet:BAAANQADCgEIBAAAAA==.',
El='Eldin:BAACNQAFFH8HAAIUAAIKDA9KAQCOAAAUAAIKDA9KAQCOAAA1AAQKfzEABBQACgpJJFgBAEYDABQACgo2JFgBAEYDABUAAQpqJaLEAGsAABYAAQoAAKtkAAAAAAAA.',
En='Endofdays:BAABNQAECn8lAAMXAAkKKRu+DQB5AgAXAAkKKRu+DQB5AgAPAAEKgwaN2wAjAAAAAA==.Enro:BAACNQAFFH8IAAITAAMK1Az5CwDVAAATAAMK1Az5CwDVAAA1AAQKfzYAAxMACgrpHNERAG0CABMACgrpHNERAG0CABIAAQpeD0NMADsAAAAA.',
Er='Erovia:BAABNQAECn8rAAIQAAoKrRGJgAAMAgAQAAoKrRGJgAAMAgAAAA==.',
Es='Esclipse:BAAANQADCgYIBgAAAA==.',
Et='Etclock:BAAANQADCgYIBgAAAA==.',
Fa='Faeria:BAAANQABCgQIBAAAAA==.Farruq:BAAANQAECgUJCwAAAA==.Fathermoo:BAAANQAECgEIAQAAAA==.',
Fe='Feelsbadmang:BAAANQADCgQIBAABNQAECgoKJwAFAGcfAA==.Fellz:BAAANQADCgIIAgAAAA==.Ferian:BAAANQAECgQIEAAAAA==.Ferios:BAEANQADCgQIBAAAAA==.',
Fi='Fireheartz:BAAANQADCgMIAQAAAA==.',
Fl='Flavaflare:BAACNQAFFH8KAAIBAAQK8xPFKwCfAAABAAQK8xPFKwCfAAA1AAQKf1UAAwEACgpPI9cQAI8DAAEACgpPI9cQAI8DABEAAgrLEYkGAIEAAAAA.',
Fo='Foodex:BAAANQAFFAEIAQAAAA==.Fourleaf:BAACNQAFFH8IAAIYAAMKyg0iDgC6AAAYAAMKyg0iDgC6AAA1AAQKfzYAAxgACgqUHbgKAG4CABgACgqUHbgKAG4CABAAAQqHFucXAU4AAAAA.',
Fr='Frogplushy:BAACNQAFFH8FAAIBAAQKehUgDgBLAQABAAQKehUgDgBLAQA1AAQKfykAAwEACgp+IVU5AD8CAAEACgp+IVU5AD8CAAwAAQoAAC89AAAAAAAA.',
Fu='Furlock:BAAANQAECgQIEQAAAA==.Furral:BAABNQAECn84AAINAAoKWhxJBgBrAgANAAoKWhxJBgBrAgAAAA==.Furretc:BAAANQADCgEIAQAAAA==.',
Ga='Gaeth:BAABNQAECn8rAAIGAAoKxRNFJQD5AQAGAAoKxRNFJQD5AQAAAA==.Gardenhose:BAAANQAECgUICAAAAA==.',
Ge='Gengiss:BAAANQADCgQIBAAAAA==.',
Gi='Gigaret:BAAANQAECgQIBAAAAA==.',
Gl='Gleg:BAACNQAFFH8QAAMJAAMKQRr7FwDgAAAJAAMKQRr7FwDgAAAIAAIKuggTKACKAAA1AAQKfzcAAwkACgpgIpUXABYDAAkACgpgIpUXABYDAAgABApaEKm2AGsAAAAA.',
Go='Goodside:BAAANQADCgYIDAAAAA==.Gotmilky:BAAANQADCgUIBQAAAA==.',
Gr='Grimthebrave:BAABNQAECn8gAAIFAAoKoRr7PQAdAgAFAAoKoRr7PQAdAgAAAA==.Grimthecruel:BAABNQAECn8uAAQSAAoKnxfOGgCBAgASAAoK3hXOGgCBAgALAAQKhRwxEgDxAAATAAEK+RQSjwA9AAAAAA==.Grimthedread:BAAANQAECggICgAAAA==.Gripless:BAAANQADCgQIBAAAAA==.Griselden:BAABNQAECn9CAAISAAoK4SCwCgCHAgASAAoK4SCwCgCHAgAAAA==.Grizzlyras:BAAANQADCggICAAAAA==.',
Gu='Gub:BAAANQAECgQJCwAAAA==.',
Ha='Hannsollo:BAAANQADCgMIAwAAAA==.',
Ho='Holyshock:BAAANQADCgEIAQAAAA==.',
['Hâ']='Hâmburger:BAAANQADCgIIAgAAAA==.',
Ir='Iridessa:BAAANQADCgcIEwAAAA==.',
Is='Ishpoo:BAABNQAECn8xAAMCAAoKdhW2YgByAgACAAoKdhW2YgByAgAZAAEKAABgfwAdAAAAAA==.',
Ji='Jip:BAAANQAECgcICQAAAA==.',
Jl='Jlawm:BAAANQADCgUIBQAAAA==.Jlawq:BAAANQADCgUIBQAAAA==.Jlawzzs:BAABNQAECn82AAIJAAoKehYdTgAsAgAJAAoKehYdTgAsAgAAAA==.',
Jo='Job:BAABNQAECn8/AAITAAoKFSTSBACmAwATAAoKFSTSBACmAwAAAA==.',
Ju='Judgim:BAAANQADCgQIBAABNQAECgQICAAaAAAAAA==.Judoriel:BAAANQAECgYIBgAAAA==.Junkyard:BAAANQADCgcICAAAAA==.',
Ka='Kaimin:BAABNQAECn9EAAIXAAoKBx51GwDnAgAXAAoKBx51GwDnAgAAAA==.Karthas:BAAANQADCgcIDAAAAA==.Karuun:BAAANQAECgUICQABNQAECgoKIQAPAIAMAA==.',
Ke='Kezeshi:BAABNQAECn8ZAAIUAAgKugq5DABsAQAUAAgKugq5DABsAQAAAA==.',
Kh='Khaidralulz:BAABNQAECn83AAMJAAoKxBCvZQDcAQAJAAkKaA6vZQDcAQAKAAUK6BFyHAASAQAAAA==.Khonsu:BAAANQAECgIIAgAAAA==.',
Ki='Kiba:BAABNQAECn8yAAMbAAgKVQ4rGABCAQAbAAcKCRArGABCAQAcAAcKDwsjLQD6AAAAAA==.',
Kr='Kraegen:BAABNQAECn8UAAIZAAgK0Q35MABXAQAZAAgK0Q35MABXAQAAAA==.Kray:BAAANQADCgYIBgAAAA==.',
Ky='Kyofu:BAABNQAECn9GAAMbAAoK1Bz6CgDWAgAbAAoK1Bz6CgDWAgAcAAQKiBaqQgACAQAAAA==.',
La='Larenta:BAABNQAECn80AAIDAAoKKSN1BwCIAwADAAoKKSN1BwCIAwAAAA==.Larethiana:BAACNQAFFH8FAAIGAAUKfhKnBwCAAQAGAAUKfhKnBwCAAQA1AAQKfywAAgYACgqvHygOAO8CAAYACgqvHygOAO8CAAE1AAQKCAgNABoAAAAA.Laria:BAAANQAECggIDQAAAA==.',
Le='Leafmochi:BAAANQAECgQIBQAAAA==.Letloose:BAAANQADCgEIAgAAAA==.',
Li='Lightbright:BAACNQAFFH8FAAICAAIKQAvhHwB+AAACAAIKQAvhHwB+AAA1AAQKfzUAAgIACgqJI14fAMQCAAIACgqJI14fAMQCAAAA.Lildab:BAACNQAFFH8FAAIWAAIKlASuDgBvAAAWAAIKlASuDgBvAAA1AAQKf0QAAhYACgpEEIUUANoBABYACgpEEIUUANoBAAAA.Linashia:BAABNQAECn8tAAIVAAoK7RTqMQBFAgAVAAoK7RTqMQBFAgAAAA==.',
Lo='Lomein:BAAANQADCgMIAQAAAA==.Lostwanderer:BAAANQADCggIDwAAAA==.',
Lu='Luhen:BAAANQADCgYIBgAAAA==.',
Ma='Magicology:BAABNQAECn9hAAIBAAkKkCZ2AQD2AwABAAkKkCZ2AQD2AwAAAA==.Maimim:BAAANQAECgQICAAAAA==.Malacoda:BAABNQAECn82AAITAAoKCx0yGQDRAgATAAoKCx0yGQDRAgAAAA==.Manamommy:BAABNQAECn8bAAIBAAkKaxkWdACVAgABAAkKaxkWdACVAgAAAA==.Marble:BAAANQADCgYIBwAAAA==.',
Me='Merlx:BAAANQADCggIEQAAAA==.',
Mi='Miladee:BAAANQADCgYIBgAAAA==.Mindra:BAABNQAECn8ZAAIQAAgKdxgHZABNAgAQAAgKdxgHZABNAgAAAA==.',
Mo='Moatie:BAAANQADCgQIBQAAAA==.Monkwinnin:BAAANQADCgEIAQAAAA==.Moobundo:BAABNQAECn8cAAMJAAoK7hKQUwCSAQAJAAkKHxOQUwCSAQAIAAEKAABOVwEhAAAAAA==.Moolasses:BAAANQAECgMIAQAAAA==.Moonmama:BAAANQADCgQIBQAAAA==.Moonwren:BAAANQAECggIEQAAAA==.Morgrin:BAAANQAECgYIDwAAAA==.',
Ne='Nezroz:BAAANQAECgYIBgABNQAECggIMAASAIsSAA==.',
Ni='Nicotine:BAAANQAECggIDAAAAA==.Nike:BAABNQAECn8nAAMFAAoKZx8hVwCGAgAFAAkKVB0hVwCGAgAdAAcKwx0MEAA2AQAAAA==.Nipsey:BAAANQADCgYIBgAAAA==.Nitwp:BAABNQAECn87AAMeAAoKyBwOCQDjAgAeAAkKnhsOCQDjAgAEAAYKCQ87MAAbAQAAAA==.Nizo:BAAANQAECgUIDwAAAA==.',
Nj='Njal:BAAANQADCgUIBQAAAA==.',
No='Novastrike:BAACNQAFFH8PAAMIAAUK0QtkEADOAAAIAAQK0QtkEADOAAAJAAIK0gA9KwAzAAA1AAQKfy8AAwgACgqoGyg7AIkCAAgACgqoGyg7AIkCAAkAAwp1A1IHAVkAAAAA.',
Ny='Nymphia:BAAANQAECgUICgAAAA==.Nyrif:BAACNQAFFH8HAAIPAAIKnA06GgBpAAAPAAIKnA06GgBpAAA1AAQKfzIAAg8ACgocHRMeAMECAA8ACgocHRMeAMECAAAA.',
Oj='Ojoon:BAABNQAECn8WAAIBAAcKPwfjHwFXAQABAAcKPwfjHwFXAQAAAA==.',
Om='Omnisllash:BAABNQAECn8jAAIMAAoK6RcrCQBFAgAMAAoK6RcrCQBFAgAAAA==.',
Pa='Pallamb:BAAANQAECgQIBAAAAA==.Pallymaster:BAAANQADCgMIAQAAAA==.',
Ph='Phyter:BAAANQAECgQIBwAAAA==.',
Pi='Pillin:BAAANQAECgcIDwAAAA==.',
Po='Polyestr:BAAANQADCgQIBAAAAA==.Porkchowmein:BAAANQAECgMIAwAAAA==.',
Pr='Previousleon:BAAANQAECggIBAAAAA==.Prosmas:BAAANQAECgEIAQAAAA==.',
Ps='Psylence:BAAANQAECgMIBgAAAA==.Psyrge:BAAANQAECgUIBgAAAA==.',
Qu='Queue:BAABNQAECn8hAAIPAAoKgAyiLQByAQAPAAoKgAyiLQByAQAAAA==.',
Ra='Rathmara:BAAANQAECgIIAgAAAA==.',
Re='Redle:BAAANQADCggIDAAAAA==.',
Rh='Rhordric:BAECNQAFFH8GAAIYAAMK4AalDgCyAAAYAAMK4AalDgCyAAA1AAQKfzoABBgACgqSGTwNAD0CABgACgqEFzwNAD0CABAABwrBEfKcAM0BAB8AAQorB+oUACYAAAAA.',
Ri='Ringa:BAAANQADCgMIAQAAAA==.',
Ro='Roku:BAAANQAECgIIAgAAAA==.Rottenbeef:BAAANQAECgcICwAAAA==.',
Ru='Runicmommy:BAAANQADCgUIBQAAAA==.',
Sa='Saintbull:BAAANQADCgEIAwAAAA==.Samwinchestr:BAAANQAECgMIAwAAAA==.Sanyoalt:BAAANQADCgEIAgAAAA==.',
Sc='Scemo:BAAANQADCgUIBQAAAA==.Scissorsista:BAAANQAECgQIBAAAAA==.',
Se='Sea:BAACNQAFFH8VAAIJAAYK7xsYBQAiAgAJAAYK7xsYBQAiAgA1AAQKfzQAAgkACgr0JP8HAIEDAAkACgr0JP8HAIEDAAAA.Sepsis:BAAANQAECggICQAAAA==.Serendipity:BAAANQAECgQIBwAAAA==.',
Sh='Shadowaurora:BAAANQADCggJCAAAAA==.Shadowrose:BAABNQAECn8fAAMNAAkKXRUhFAC6AQANAAkKXRUhFAC6AQAHAAEKAACcxwAbAAAAAA==.Shamano:BAAANQAECgQIBgABNQAECggIMAAgAIYZAA==.Shanogadin:BAAANQAECgUIDQAAAA==.Shiemi:BAAANQAECgUICgAAAA==.',
Sl='Slashysally:BAAANQADCgMIAQAAAA==.',
So='Soju:BAAANQAECgQIBAAAAA==.Sotospeak:BAAANQABCggIDQAAAA==.',
Sq='Squeaky:BAAANQAECgYIDQAAAA==.',
St='Starshade:BAAANQAECgYIBwAAAA==.Steeldeath:BAAANQADCgEIAQAAAA==.',
Su='Sungodess:BAAANQAECgMIAwAAAA==.',
Sy='Syrupp:BAABNQAECn8mAAIhAAoKoBj1JQBlAgAhAAoKoBj1JQBlAgAAAA==.',
Ta='Tayn:BAAANQADCgcIDQAAAA==.',
Th='Thackery:BAAANQADCggICwAAAA==.Thinsheets:BAAANQAECgEIAQABNQAECggIGwACAMsMAA==.',
Tr='Trenetalan:BAAANQADCgIJAwABNQADCggIEAAaAAAAAA==.Trickledown:BAAANQAECgUIBQAAAA==.',
Ts='Tsavø:BAAANQAECgQJBAAAAA==.',
Tw='Twinkle:BAABNQAECn8YAAIDAAkKShcMUwAhAgADAAkKShcMUwAhAgAAAA==.',
Un='Unholysage:BAABNQAECn8jAAMUAAgK6Q+yEAAeAQAUAAYK4g6yEAAeAQAWAAcKfg0qKQD+AAAAAA==.Untouchable:BAAANQADCgEIAQAAAA==.',
Va='Valathiel:BAAANQADCggICwAAAA==.Valenîx:BAAANQAECgYIBwABNQAECgoKIgAeALcJAA==.',
Ve='Venetrazat:BAABNQAECn9GAAIeAAoKQxm5BQAvAgAeAAoKQxm5BQAvAgAAAA==.Vermithorr:BAAANQAECgEIAQAAAA==.',
Vi='Viserys:BAAANQAECggIEAAAAA==.',
Vo='Vo:BAAANQADCgYIDgAAAA==.Vol:BAAANQADCgUIBQAAAA==.',
Vu='Vulpra:BAABNQAECn8fAAMVAAoK+gvdTwDBAQAVAAkK6gzdTwDBAQAWAAEKAABMbgAAAAAAAA==.',
['Vâ']='Vâlenix:BAABNQAECn8iAAMeAAoKtwmBHQB3AQAeAAkK3QqBHQB3AQAEAAcKIAgdKgBeAQAAAA==.',
['Vä']='Välenix:BAAANQAECgIIAgABNQAECgoKIgAeALcJAA==.',
Wa='Warder:BAABNQAECn8aAAIdAAkKvQ7/DABvAQAdAAkKvQ7/DABvAQAAAA==.',
We='Wewaskangz:BAAANQAECgUIBgAAAA==.',
Wi='Wincks:BAABNQAECn8wAAQgAAgKhhn8BwCZAQAgAAgKhhn8BwCZAQAiAAMKGwrOIQF/AAAjAAEKfA5tdgA3AAAAAA==.',
Xh='Xhosar:BAABNQAECn88AAIfAAoKpRJcBACiAgAfAAoKpRJcBACiAgAAAA==.',
Ya='Yaoden:BAAANQAECgUIBQAAAA==.',
['Yú']='Yúffíe:BAAANQADCgYIBgAAAA==.',
Za='Zachthemage:BAABNQAECn8wAAIBAAoKdQpRmABHAQABAAoKdQpRmABHAQAAAA==.Zackman:BAACNQAFFH8IAAIDAAMKfAa9FAC7AAADAAMKfAa9FAC7AAA1AAQKf0cAAgMACgreFdUvAC8CAAMACgreFdUvAC8CAAAA.',
Zi='Zinatrax:BAAANQADCgYIDAAAAA==.',
Zo='Zombie:BAABNQAECn8iAAIXAAgK8RsVRAAKAgAXAAgK8RsVRAAKAgAAAA==.',
Zu='Zuldrakar:BAAANQADCgUICQAAAA==.Zulrea:BAABNQAECn9IAAIHAAoK1xtWEQB1AgAHAAoK1xtWEQB1AgAAAA==.',
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
