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

local lookup = {'Mage-Arcane','Paladin-Retribution','Paladin-Holy','DemonHunter-Havoc','Evoker-Devastation','Warrior-Arms','Mage-Frost','Druid-Restoration','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Priest-Holy','Druid-Feral','Warrior-Protection','DeathKnight-Blood','Hunter-BeastMastery','Mage-Fire','DemonHunter-Devourer','Priest-Discipline','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Hunter-Marksmanship','Warlock-Affliction','Warlock-Demonology','Paladin-Protection','Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Warrior-Fury','Evoker-Preservation','Hunter-Survival','Warlock-Destruction',}
local provider = {region='US',realm='Dunemaul',name='US',type='weekly',zone=53,date='2026-11-17',data={Al='Aletalle:BAAANQAECgQIBAAAAA==.Allice:BAABNQAECn8sAAIBAAkKMRhNVgAQAgABAAkKMRhNVgAQAgAAAA==.Alsheyra:BAAANQADCgYICgAAAA==.Alterion:BAAANQABCgQICgAAAA==.',
An='Anxious:BAAANQADCgYIEwAAAA==.',
As='Ashwalker:BAABNQAECn8bAAMCAAcKDQrGEQHOAAACAAYKyQbGEQHOAAADAAYKdgJ83gDCAAAAAA==.',
Au='Aughyst:BAAANQAECgYICwAAAA==.Augnyxia:BAAANQAECgUICgAAAA==.Augtism:BAAANQAECgEIAQAAAA==.Augtysm:BAAANQADCggICAAAAA==.Augy:BAAANQAECgcICwAAAA==.',
Ba='Bandobras:BAAANQADCgcIDgAAAA==.Bangtwinkdh:BAABNQAECn8XAAIEAAoKPxpZFQByAgAEAAoKPxpZFQByAgABNQAFFAkJIwAFADUhAA==.',
Bh='Bhorg:BAAANQADCgMIAwAAAA==.',
Bl='Blackdust:BAAANQADCggIDQAAAA==.Blast:BAAANQAECggICgABNQAFFAgIIQAGAD0hAA==.Blasters:BAAANQADCgcIEgAAAA==.Bloodjury:BAABNQAECn8gAAICAAkKVhDYsABuAQACAAkKVhDYsABuAQAAAA==.Blossom:BAAANQABCgIIAgAAAA==.',
Bo='Boejo:BAAANQAECggIEwAAAA==.Boonktown:BAABNQAECn8ZAAIHAAoKewthDgCtAQAHAAoKewthDgCtAQAAAA==.Borellus:BAAANQABCgUICQAAAA==.',
Bu='Bunga:BAAANQAECgEIAQAAAA==.Bungis:BAAANQAECggIEQAAAA==.Bushetti:BAABNQAECn8XAAMIAAkKphbFHgA4AgAIAAgKSBbFHgA4AgAJAAIKAADcnwBfAAAAAA==.',
Ca='Casperface:BAABNQAECn8pAAMKAAoKxxMRcwDHAQAKAAgKTA4RcwDHAQALAAMK1AoD3ABgAAAAAA==.Cazisham:BAABNQAECn8bAAIMAAgK0wHpLQCKAAAMAAgK0wHpLQCKAAAAAA==.',
Ce='Cestus:BAAANQAECgcJDQAAAA==.Cevianne:BAAANQAECgIIAgAAAA==.',
Ch='Chanok:BAAANQADCggICAAAAA==.',
Ci='Ciaphis:BAABNQAECn9MAAICAAoKrgzDjACyAQACAAoKrgzDjACyAQAAAA==.Cinnabuns:BAAANQADCgQIAwAAAA==.',
Co='Coal:BAABNQAECn8uAAINAAoKxiK/AgDqAgANAAoKxiK/AgDqAgAAAA==.Coltonater:BAACNQAFFH8TAAIBAAcKmRqRDwD7AQABAAcKmRqRDwD7AQA1AAQKf2sAAgEACgo+JgACAO4DAAEACgo+JgACAO4DAAAA.',
['Cá']='Cáséy:BAACNQAFFH8SAAMHAAYK5RP/AACSAQAHAAYK5RP/AACSAQABAAEKAAApUgAAAAA1AAQKf0gAAwcACgruIrEBAHADAAcACgruIrEBAHADAAEAAwqGElpBAU8AAAAA.',
['Cä']='Cäsey:BAABNQAECn8YAAIOAAoKGwqcYgC4AQAOAAoKGwqcYgC4AQABNQAFFAYIEgAHAOUTAA==.',
Da='Darkshroud:BAAANQAECgYIDgAAAA==.Datbi:BAABNQAECn8pAAMJAAoK0xGyOAApAgAJAAoKuA+yOAApAgAPAAMK6hcAMgCJAAAAAA==.Daugi:BAABNQAECn8nAAMQAAoKyR7lBwDXAgAQAAcKSyPlBwDXAgAGAAoK7Re4TgASAgAAAA==.',
De='Deathangel:BAAANQAECgcIDAAAAA==.Deathdeamon:BAAANQADCgMIAwAAAA==.Deathdylan:BAACNQAFFH8LAAIRAAQKWA6kGQChAAARAAQKWA6kGQChAAA1AAQKfzQAAhEACgrBHxERAJICABEACgrBHxERAJICAAAA.Delice:BAAANQAECggICgAAAA==.Demonikal:BAAANQAECgQIBAAAAA==.Demonware:BAAANQAECgQIBQAAAA==.Demítríus:BAABNQAECn8iAAISAAkKxgfomQCBAQASAAkKxgfomQCBAQAAAA==.Dethh:BAABNQAECn8lAAISAAcKPxPssQCgAQASAAcKPxPssQCgAQAAAA==.',
Di='Didona:BAAANQADCgYIBgAAAA==.Dionarose:BAAANQAECgEIAQAAAA==.Distortion:BAAANQAECgQIBgAAAA==.Divineflava:BAAANQAECgUIBgABNQAFFAQIDAABAPMTAA==.',
Do='Dobby:BAAANQADCggIDQAAAA==.',
Dr='Drakeo:BAAANQAECgYIEwAAAA==.Draximus:BAABNQAECn8jAAISAAkKsRRRbgDlAQASAAkKsRRRbgDlAQAAAA==.Drougenin:BAAANQAECggICAABNQAECgoKLgANAMYiAA==.Drpumper:BAAANQAECgcIEwAAAA==.Druqz:BAACNQAFFH8MAAIHAAQKygQpBgCxAAAHAAQKygQpBgCxAAA1AAQKfysAAgcACgoVE4UJADoCAAcACgoVE4UJADoCAAAA.Druski:BAAANQABCgQIBAAAAA==.Drævn:BAABNQAECn82AAITAAoK3hk3AgACAgATAAoK3hk3AgACAgAAAA==.',
Du='Dum:BAACNQAFFH8UAAQNAAcKbhcsAwDhAAAUAAQKyhfcCgAgAQANAAMKGh0sAwDhAAAEAAMKzhRwFgCIAAA1AAQKf0MABBQACgqwJX8CAE4DABQACgpqJX8CAE4DAA0ABwqLGsYKACkCAAQABArgIXdXAC0BAAAA.Duragon:BAABNQAECn8iAAIGAAkKrQTZ6QCgAAAGAAkKrQTZ6QCgAAAAAA==.Durkagon:BAAANQAECgQIBwAAAA==.',
Dw='Dwimbear:BAAANQABCgIIAgAAAA==.Dwinnet:BAAANQABCgQICQAAAA==.',
El='Eldin:BAACNQAFFH8KAAIVAAUKlQ6aAABtAQAVAAUKlQ6aAABtAQA1AAQKfzIABBUACgpJJFgBAEYDABUACgo2JFgBAEYDAA4AAQpqJebaAGkAABYAAQoAAB11AAAAAAAA.',
En='Endofdays:BAABNQAECn8vAAQXAAkK1xuhDwCGAgAXAAkK1xuhDwCGAgAYAAIKoAnHsgA3AAARAAEKgwaN2wAjAAAAAA==.Enro:BAACNQAFFH8MAAIEAAQK1AweEADJAAAEAAQK1AweEADJAAA1AAQKfzcAAwQACgrpHMoWAGMCAAQACgrpHMoWAGMCABQAAQpeDwBUADsAAAAA.',
Er='Erovia:BAABNQAECn8rAAISAAoKrRGJgAAMAgASAAoKrRGJgAAMAgAAAA==.',
Es='Esclipse:BAAANQADCgYIBgAAAA==.',
Et='Etclock:BAAANQADCgYIBgAAAA==.',
Fa='Faeria:BAAANQABCgQIBAAAAA==.Farruq:BAAANQAECgUJCwAAAA==.Fathermoo:BAAANQAECgEIAQAAAA==.',
Fe='Feelsbadmang:BAAANQADCgQIBAABNQAECgoKJwAGAGcfAA==.Fellz:BAAANQADCgIIAgAAAA==.Ferian:BAAANQAECgQIEAAAAA==.Ferios:BAEANQADCgQIBAAAAA==.',
Fl='Flavaflare:BAACNQAFFH8MAAMBAAQK8xNGOQDgAAABAAQK8xNGOQDgAAATAAEKAAA3AgAAAAA1AAQKf1sAAwEACgpPI9cQAI8DAAEACgpPI9cQAI8DABMABQriFQkFABsBAAAA.Flavashamy:BAAANQADCgMIAwABNQAFFAQIDAABAPMTAA==.',
Fo='Foodex:BAAANQAFFAEIAQAAAA==.Fourleaf:BAACNQAFFH8MAAIZAAQKyg1REwC+AAAZAAQKyg1REwC+AAA1AAQKfzcAAxkACgqUHTcNAGgCABkACgqUHTcNAGgCABIAAQqHFl45AUwAAAAA.',
Fr='Frogplushy:BAACNQAFFH8FAAIBAAQKehU3FwA4AQABAAQKehU3FwA4AQA1AAQKfyoAAwEACgp+IaxJADECAAEACgp+IaxJADECAAcAAQoAAD1IAAAAAAAA.',
Fu='Furlock:BAABNQAECn8WAAMaAAcK7w1/HwB4AAAbAAcKcAqpvQDWAAAaAAIKMBJ/HwB4AAAAAA==.Furral:BAABNQAECn88AAIPAAoKih5pBgCfAgAPAAoKih5pBgCfAgAAAA==.Furretc:BAAANQADCgEIAQAAAA==.',
Ga='Gaeth:BAABNQAECn8rAAIIAAoKxRNFJQD5AQAIAAoKxRNFJQD5AQAAAA==.Gardenhose:BAAANQAECgUICAAAAA==.',
Ge='Gengiss:BAAANQADCgQIBAAAAA==.',
Gi='Gigaret:BAAANQAECgcICAAAAA==.',
Gl='Gleg:BAACNQAFFH8RAAMLAAMKQRr7FwDgAAALAAMKQRr7FwDgAAAKAAIKuggTKACKAAA1AAQKfzoAAwsACgpgIpUXABYDAAsACgpgIpUXABYDAAoABApaEInTAGkAAAAA.',
Go='Goodside:BAAANQADCgYIDAAAAA==.',
Gr='Grimthebrave:BAABNQAECn8jAAIGAAoKAhwXQABDAgAGAAoKAhwXQABDAgAAAA==.Grimthecruel:BAABNQAECn82AAQUAAoK4BkuFAAhAgAUAAoKIhkuFAAhAgANAAQKhRypFgDsAAAEAAEK+RQSjwA9AAAAAA==.Grimthedread:BAABNQAECn8XAAIbAAoKkwpJnAAfAQAbAAoKkwpJnAAfAQAAAA==.Gripless:BAAANQADCgQIBAAAAA==.Griselden:BAABNQAECn9FAAIUAAoKnSFZDACNAgAUAAoKnSFZDACNAgAAAA==.Grizzlyras:BAAANQADCggICAAAAA==.',
Gu='Gub:BAAANQAECgQJCwAAAA==.',
Ha='Hannsollo:BAAANQADCgMIAwAAAA==.',
Ho='Holyshock:BAAANQABCgYIEAAAAA==.',
['Hâ']='Hâmburger:BAAANQADCgIIAgAAAA==.',
Ir='Iridessa:BAAANQADCgcIEwAAAA==.',
Is='Ishpoo:BAABNQAECn8zAAMCAAoKdhW2YgByAgACAAoKdhW2YgByAgAcAAEKAABgfwAdAAAAAA==.',
Ji='Jip:BAAANQAECgcICQAAAA==.',
Jl='Jlawm:BAAANQADCgcIDAAAAA==.Jlawq:BAAANQADCgUIBQAAAA==.Jlawzzs:BAABNQAECn8+AAMLAAoKehYdTgAsAgALAAoKehYdTgAsAgAKAAQK/Q+9qgCxAAAAAA==.',
Jo='Job:BAABNQAECn9AAAIEAAoKFSTSBACmAwAEAAoKFSTSBACmAwAAAA==.',
Ju='Judgim:BAAANQADCgQIBAABNQAECgUICgAdAAAAAA==.Judoriel:BAAANQAECgYIBwAAAA==.Junkyard:BAAANQADCgcIBwAAAA==.',
Ka='Kaimin:BAABNQAECn9GAAIXAAoKBx51GwDnAgAXAAoKBx51GwDnAgAAAA==.Karthas:BAAANQADCgcIDAAAAA==.Karuun:BAAANQAECgUICQABNQAECgoKIQARAIAMAA==.',
Ke='Kezeshi:BAABNQAECn8ZAAIVAAgKugq5DABsAQAVAAgKugq5DABsAQAAAA==.',
Kh='Khaidralulz:BAABNQAECn9BAAMMAAoKXw5tEQAAAgAMAAoKXw5tEQAAAgALAAkKaA6vZQDcAQAAAA==.Khonsu:BAAANQAECgIIAgAAAA==.',
Ki='Kiba:BAABNQAECn9AAAMeAAkK5g5IFwCLAQAeAAgKdhBIFwCLAQAfAAcKdQukNAD7AAAAAA==.',
Kr='Kraegen:BAABNQAECn8UAAIcAAgK0Q35MABXAQAcAAgK0Q35MABXAQAAAA==.Kray:BAAANQADCgYIBgAAAA==.',
Ky='Kyofu:BAACNQAFFH8GAAIeAAQKVwraBgAAAQAeAAQKVwraBgAAAQA1AAQKf0sAAx4ACgrUHPoKANYCAB4ACgrUHPoKANYCAB8ABAqIFqpCAAIBAAAA.',
La='Larenta:BAABNQAECn82AAIDAAoKKSMrDABmAwADAAoKKSMrDABmAwAAAA==.Larethiana:BAACNQAFFH8FAAIIAAUKfhKnBwCAAQAIAAUKfhKnBwCAAQA1AAQKfy0AAggACgoAISgOAO8CAAgACgoAISgOAO8CAAE1AAQKCAgNAB0AAAAA.Laria:BAAANQAECggIDQAAAA==.',
Le='Leafmochi:BAAANQAECgQIBQAAAA==.Letloose:BAAANQADCgEIAQAAAA==.',
Li='Lightbright:BAACNQAFFH8FAAICAAIKQAvNJwB8AAACAAIKQAvNJwB8AAA1AAQKfzUAAgIACgqJI+spAB8DAAIACgqJI+spAB8DAAAA.Lildab:BAACNQAFFH8FAAIWAAIKlASaEgBrAAAWAAIKlASaEgBrAAA1AAQKf1UAAhYACgqPFEIUABkCABYACgqPFEIUABkCAAAA.Linashia:BAACNQAFFH8HAAIOAAQKXgtgHQAHAQAOAAQKXgtgHQAHAQA1AAQKfy4AAg4ACgo1FWpCADACAA4ACgo1FWpCADACAAAA.',
Lo='Lostwanderer:BAAANQADCggIDgAAAA==.',
Lu='Luhen:BAAANQADCgYIBgAAAA==.',
Ma='Magicology:BAABNQAECn9hAAIBAAkKkCZ2AQD2AwABAAkKkCZ2AQD2AwAAAA==.Maimim:BAAANQAECgUICgAAAA==.Malacoda:BAABNQAECn85AAIEAAoKCx0yGQDRAgAEAAoKCx0yGQDRAgAAAA==.Manamommy:BAABNQAECn8bAAIBAAkKaxkWdACVAgABAAkKaxkWdACVAgAAAA==.Marble:BAAANQADCgYIBwAAAA==.',
Me='Merlx:BAAANQADCggIEQAAAA==.',
Mi='Miladee:BAAANQADCgYIBgAAAA==.Mindra:BAABNQAECn8ZAAISAAgKdxgHZABNAgASAAgKdxgHZABNAgAAAA==.',
Mo='Moatie:BAAANQADCgQIBQAAAA==.Moobundo:BAABNQAECn8cAAMLAAoK7hJSZwB/AQALAAkKHxNSZwB/AQAKAAEKAABOVwEhAAAAAA==.Moolasses:BAAANQAECgMIAQAAAA==.Moonmama:BAAANQADCgQIBAAAAA==.Moonwren:BAAANQAECggIEQAAAA==.Morgrin:BAAANQAECgYIDwAAAA==.',
Ne='Necropox:BAAANQADCgMIAwAAAA==.Nezroz:BAAANQAECgYIBgABNQAECggIPQAUAGATAA==.',
Ni='Nicotine:BAAANQAECggIDAAAAA==.Nike:BAABNQAECn8nAAMGAAoKZx8hVwCGAgAGAAkKVB0hVwCGAgAgAAcKwx2gFAAuAQAAAA==.Nipsey:BAAANQADCgYIBgAAAA==.Nitwp:BAABNQAECn89AAMFAAoKPx4OCQDjAgAFAAkKSh0OCQDjAgAhAAYKCQ87MAAbAQAAAA==.Nizo:BAAANQAECgUIDwAAAA==.',
Nj='Njal:BAAANQADCgUIBQAAAA==.',
No='Novastrike:BAACNQAFFH8QAAMKAAYK2Q7QFADIAAAKAAQK0QvQFADIAAALAAMK5wHZJgBvAAA1AAQKfzEAAwoACgqoGyg7AIkCAAoACgqoGyg7AIkCAAsAAwp1A1IHAVkAAAAA.',
Ny='Nymphia:BAAANQAECgUICgAAAA==.Nyrif:BAACNQAFFH8KAAIRAAUKKw1LGgCdAAARAAUKKw1LGgCdAAA1AAQKfzMAAhEACgocHRMeAMECABEACgocHRMeAMECAAAA.',
Oj='Ojoon:BAABNQAECn8WAAIBAAcKPwfjHwFXAQABAAcKPwfjHwFXAQAAAA==.',
Om='Omnisllash:BAABNQAECn8nAAIHAAoKIBgrCQBFAgAHAAoKIBgrCQBFAgAAAA==.',
Pa='Pallamb:BAAANQAECgQIBAAAAA==.',
Ph='Phyter:BAAANQAECgQIBwAAAA==.',
Pi='Pillin:BAAANQAECgcIEAAAAA==.',
Po='Polyestr:BAAANQADCgQIBAAAAA==.Porkchowmein:BAAANQAECgMIAwAAAA==.',
Pr='Previousleon:BAAANQAECggIBAAAAA==.Prosmas:BAAANQAECggIDgAAAA==.',
Ps='Psylence:BAAANQAECgMIBgAAAA==.Psyrge:BAAANQAECgUIBgAAAA==.',
Qu='Queue:BAABNQAECn8hAAIRAAoKgAyRNwBmAQARAAoKgAyRNwBmAQAAAA==.',
Ra='Ragevirus:BAAANQAECgIIAgAAAA==.Rathmara:BAAANQAECgIIAgAAAA==.',
Re='Redle:BAAANQADCggICgAAAA==.',
Rh='Rhordric:BAECNQAFFH8KAAIZAAQKngc3FACyAAAZAAQKngc3FACyAAA1AAQKfzsABBkACgqSGXQQADYCABkACgqEF3QQADYCABIABwrBEfKcAM0BACIAAQorB+oUACYAAAAA.',
Ro='Roku:BAAANQAECgIIAgAAAA==.Rottenbeef:BAAANQAECgcICwAAAA==.',
Ru='Runicmommy:BAAANQADCgUIBQAAAA==.',
Sa='Saintbull:BAAANQABCgYIBwAAAA==.Samwinchestr:BAAANQAECgMIAwAAAA==.Sanyoalt:BAAANQADCgEIAQAAAA==.',
Sc='Scemo:BAAANQADCgUIBQAAAA==.Scissorsista:BAAANQAECgQICAAAAA==.',
Se='Sea:BAACNQAFFH8VAAILAAYK7xsYBQAiAgALAAYK7xsYBQAiAgA1AAQKfzgAAgsACgocJf8HAIEDAAsACgocJf8HAIEDAAAA.Sepsis:BAAANQAECggICQAAAA==.Serendipity:BAAANQAECgQIBwAAAA==.',
Sh='Shadowaurora:BAAANQADCggJCAAAAA==.Shadowrose:BAABNQAECn8iAAQPAAkKXRUhFAC6AQAPAAkKXRUhFAC6AQAIAAIKQwk9ZwBeAAAJAAEKAACcxwAbAAAAAA==.Shamano:BAAANQAECgQIBgABNQAECggIMQAaAI4ZAA==.Shanogadin:BAAANQAECgUIDQAAAA==.Sheadas:BAAANQABCgEIAQAAAA==.Shiemi:BAAANQAECgUICgAAAA==.',
So='Soju:BAAANQAECgQIBQAAAA==.Sotospeak:BAAANQABCggIDQAAAA==.',
Sq='Squeaky:BAABNQAECn8YAAICAAYKqgNmSwGoAAACAAYKqgNmSwGoAAAAAA==.',
St='Starshade:BAAANQAECgYIBwAAAA==.Steeldeath:BAAANQADCgEIAQAAAA==.',
Su='Sungodess:BAAANQAECgcIAwAAAA==.',
Sy='Syrupp:BAABNQAECn8sAAIYAAoKEBn1JQBlAgAYAAoKEBn1JQBlAgAAAA==.',
Ta='Tayn:BAAANQADCgcIDAAAAA==.',
Th='Thackery:BAAANQADCggICwAAAA==.Thinsheets:BAAANQAECgEIAQABNQAECgkJIAACAFYQAA==.',
Tr='Trenetalan:BAAANQADCgIJAgABNQADCggIEAAdAAAAAA==.Trickledown:BAAANQAECgUIBQAAAA==.',
Ts='Tsavø:BAAANQAECgQJBAAAAA==.',
Tw='Twinkle:BAABNQAECn8YAAIDAAkKShcMUwAhAgADAAkKShcMUwAhAgAAAA==.',
Un='Unholysage:BAABNQAECn8nAAMWAAkKRwwfKQA7AQAWAAgKVw0fKQA7AQAVAAcKug2yEAAeAQAAAA==.Unholysmurfh:BAAANQAECgEIAQAAAA==.Untouchable:BAAANQADCgEIAQAAAA==.',
Va='Valathiel:BAAANQADCggICwAAAA==.Valenîx:BAAANQAECgYIBwABNQAFFAUIBwAhABgQAA==.',
Ve='Venetrazat:BAABNQAECn9WAAIFAAoKARo9BQBwAgAFAAoKARo9BQBwAgAAAA==.Vermithorr:BAAANQAECgEIAQAAAA==.',
Vi='Viserys:BAAANQAECggIEAAAAA==.',
Vo='Vo:BAAANQADCgYIDQAAAA==.Vol:BAAANQADCgUIBQAAAA==.',
Vu='Vulpra:BAABNQAECn8fAAMOAAoK+gsjZQCwAQAOAAkK6gwjZQCwAQAWAAEKAABAgAAAAAAAAA==.',
['Vâ']='Vâlenix:BAACNQAFFH8HAAMhAAUKGBBzEgClAAAhAAMKHwlzEgClAAAFAAMKDQGICABBAAA1AAQKfyMAAwUACgrbCoEdAHcBAAUACQorDIEdAHcBACEABwogCB0qAF4BAAAA.',
['Vä']='Välenix:BAAANQAECgIIAgABNQAFFAUIBwAhABgQAA==.',
Wa='Warder:BAABNQAECn8aAAIgAAkKvQ4kEQBnAQAgAAkKvQ4kEQBnAQAAAA==.',
We='Wewaskangz:BAAANQAECgUIBgAAAA==.',
Wi='Wincks:BAABNQAECn8xAAQaAAgKjhl0CwCPAQAaAAgKjhl0CwCPAQAbAAMKGwrOIQF/AAAjAAEKfA5tdgA3AAAAAA==.',
Xh='Xhosar:BAABNQAECn9EAAIiAAoKWBNcBACiAgAiAAoKWBNcBACiAgAAAA==.',
Ya='Yaoden:BAAANQAECgYICwAAAA==.',
['Yú']='Yúffíe:BAAANQADCgYIBgAAAA==.',
Za='Zachthemage:BAABNQAECn82AAIBAAoK4ArLlgB3AQABAAoK4ArLlgB3AQAAAA==.Zackman:BAACNQAFFH8MAAIDAAQKnwk/FAACAQADAAQKnwk/FAACAQA1AAQKf0kAAgMACgreFZs9ACACAAMACgreFZs9ACACAAAA.',
Zi='Zinatrax:BAAANQADCgYIDAAAAA==.',
Zo='Zombie:BAABNQAECn8iAAIXAAgK8RsVRAAKAgAXAAgK8RsVRAAKAgAAAA==.',
Zu='Zuldrakar:BAAANQADCgUICQAAAA==.Zulrea:BAABNQAECn9IAAIJAAoK1xt6FQBsAgAJAAoK1xt6FQBsAgAAAA==.',
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
