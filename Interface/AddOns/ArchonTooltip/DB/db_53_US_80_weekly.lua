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

local lookup = {'Mage-Arcane','Paladin-Retribution','Paladin-Holy','Evoker-Preservation','Warrior-Arms','Unknown-Unknown','Druid-Restoration','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Mage-Frost','Druid-Feral','Warrior-Protection','DeathKnight-Blood','Hunter-BeastMastery','Mage-Fire','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','Hunter-Marksmanship','Warlock-Affliction','Warlock-Demonology','Paladin-Protection','Monk-Mistweaver','Monk-Windwalker','Warrior-Fury','Evoker-Devastation','Hunter-Survival','DeathKnight-Frost','Warlock-Destruction',}
local provider = {region='US',realm='Dunemaul',name='US',type='weekly',zone=53,date='2026-11-10',data={Al='Aletalle:BAAANQAECgQIBAAAAA==.Allice:BAABNQAECn8sAAIBAAkKMRjCTwASAgABAAkKMRjCTwASAgAAAA==.Alsheyra:BAAANQADCgYICgAAAA==.Alterion:BAAANQAECgEIAQAAAA==.',
An='Anxious:BAAANQADCgYIEwAAAA==.',
As='Ashwalker:BAABNQAECn8bAAMCAAcKDQqXAgHQAAACAAYKyQaXAgHQAAADAAYKdgJ83gDCAAAAAA==.',
Au='Aughyst:BAAANQAECgYIDQAAAA==.Augnyxia:BAAANQAECgUIDAAAAA==.Augtism:BAAANQAECgEIAQAAAA==.Augtysm:BAAANQADCggICAAAAA==.Augy:BAAANQAECgcICwAAAA==.',
Ba='Bandobras:BAAANQADCgcIDgAAAA==.Bangtwinkdh:BAAANQAECggICgABNQAFFAkJGgAEACQUAA==.',
Be='Berafii:BAAANQAECgEIAQAAAA==.',
Bh='Bhorg:BAAANQADCgMIAwAAAA==.',
Bl='Blackdust:BAAANQADCggIDQAAAA==.Blast:BAAANQAECggICgABNQAFFAcIHwAFAGQiAA==.Blasters:BAAANQADCgcIEgAAAA==.Bloodjury:BAABNQAECn8dAAICAAkK1Q48rwBbAQACAAkK1Q48rwBbAQAAAA==.Blossom:BAAANQABCgIIAgABNQABCgYICwAGAAAAAA==.',
Bo='Boejo:BAAANQAECggIEwAAAA==.Boonktown:BAAANQAECggIDgAAAA==.Borellus:BAAANQABCgUICQAAAA==.',
Br='Broken:BAAANQAECgEIBAAAAA==.',
Bu='Bunga:BAAANQAECgEIAQAAAA==.Bungis:BAAANQAECggIEgAAAA==.Bushetti:BAABNQAECn8XAAMHAAkKphbFHgA4AgAHAAgKSBbFHgA4AgAIAAIKAADcnwBfAAAAAA==.',
Ca='Casperface:BAABNQAECn8pAAMJAAoKxxMRcwDHAQAJAAgKTA4RcwDHAQAKAAMK1Ap10wBgAAAAAA==.Cazisham:BAABNQAECn8bAAILAAgK0wHpLQCKAAALAAgK0wHpLQCKAAAAAA==.',
Ce='Cestus:BAAANQAECgcJEAAAAA==.Cevianne:BAAANQAECgIIAgAAAA==.',
Ch='Chanok:BAAANQADCggICAAAAA==.',
Ci='Ciaphis:BAABNQAECn9CAAICAAoKqgyTgAC3AQACAAoKqgyTgAC3AQAAAA==.Cinnabuns:BAAANQADCgQIAwAAAA==.',
Co='Coal:BAABNQAECn8uAAIMAAoKxiJ3AgDsAgAMAAoKxiJ3AgDsAgAAAA==.Coltonater:BAACNQAFFH8TAAIBAAcKmRqRDwD7AQABAAcKmRqRDwD7AQA1AAQKf2cAAgEACgo+JgACAO4DAAEACgo+JgACAO4DAAAA.',
['Cá']='Cáséy:BAACNQAFFH8SAAMNAAYK5RP/AACSAQANAAYK5RP/AACSAQABAAEKAABWTQAAAAA1AAQKf0cAAw0ACgruIrEBAHADAA0ACgruIrEBAHADAAEAAwqGEuw3AU8AAAAA.',
['Cä']='Cäsey:BAAANQAECggIDAABNQAFFAYIEgANAOUTAA==.',
Da='Darkshroud:BAAANQAECgYIDgAAAA==.Datbi:BAABNQAECn8pAAMIAAoK0xGyOAApAgAIAAoKuA+yOAApAgAOAAMK6hdOLQCKAAAAAA==.Daugi:BAABNQAECn8nAAMPAAoKyR7lBwDXAgAPAAcKSyPlBwDXAgAFAAoK7RehSAAVAgAAAA==.',
De='Deathangel:BAAANQAECggIDwAAAA==.Deathdeamon:BAAANQADCgMIAwAAAA==.Deathdylan:BAACNQAFFH8LAAIQAAQKWA5EFgCpAAAQAAQKWA5EFgCpAAA1AAQKfzQAAhAACgrBH9UPAJkCABAACgrBH9UPAJkCAAAA.Delice:BAAANQAECggICwAAAA==.Demonikal:BAAANQAECgQIBAAAAA==.Demonware:BAAANQAECgQIBQAAAA==.Demítríus:BAABNQAECn8bAAIRAAgKWAcxpQBNAQARAAgKWAcxpQBNAQAAAA==.Dethh:BAABNQAECn8lAAIRAAcKPxPssQCgAQARAAcKPxPssQCgAQAAAA==.',
Di='Didona:BAAANQADCgYIBgAAAA==.Distortion:BAAANQAECgQIBgAAAA==.Divineflava:BAAANQAECgUIBgABNQAFFAQICwABAPMTAA==.',
Do='Dobby:BAAANQADCggIDQAAAA==.',
Dr='Drakeo:BAABNQAECn8XAAIHAAcKhAtxOwBFAQAHAAcKhAtxOwBFAQAAAA==.Draximus:BAABNQAECn8gAAIRAAgKzBTMfQCkAQARAAgKzBTMfQCkAQAAAA==.Drougenin:BAAANQAECggICAABNQAECgoKLgAMAMYiAA==.Drpumper:BAAANQAECgcIEwAAAA==.Druqz:BAACNQAFFH8KAAINAAQKBQShBQCsAAANAAQKBQShBQCsAAA1AAQKfysAAg0ACgoVE4UJADoCAA0ACgoVE4UJADoCAAAA.Druski:BAAANQABCgQIBAAAAA==.Drævn:BAABNQAECn82AAISAAoK3hn1AQAFAgASAAoK3hn1AQAFAgAAAA==.',
Du='Dum:BAACNQAFFH8SAAQMAAYK1BksAwDhAAATAAMKwxzcCgAgAQAMAAMKGh0sAwDhAAAUAAMKzhRwFgCIAAA1AAQKfzkABBMACgpjJdoHANMCABMACgoXJdoHANMCAAwABwqLGsYKACkCABQABArgIXdXAC0BAAAA.Duragon:BAABNQAECn8hAAIFAAgKBQQ9DgHAAAAFAAgKBQQ9DgHAAAAAAA==.Durkagon:BAAANQAECgQICgAAAA==.',
Dw='Dwimbear:BAAANQAECgEIAwAAAA==.Dwimhoof:BAAANQAECgEIBAAAAA==.Dwinnet:BAAANQAECgEIAQAAAA==.',
El='Eldin:BAACNQAFFH8KAAIVAAUKlQ6LAAB0AQAVAAUKlQ6LAAB0AQA1AAQKfzIABBUACgpJJFgBAEYDABUACgo2JFgBAEYDABYAAQpqJbjRAGsAABcAAQoAAFNuAAAAAAAA.',
En='Endofdays:BAABNQAECn8rAAMYAAkK1xs4DgCLAgAYAAkK1xs4DgCLAgAQAAEKgwaN2wAjAAAAAA==.Enro:BAACNQAFFH8MAAIUAAQK1Aw/DgDKAAAUAAQK1Aw/DgDKAAA1AAQKfzcAAxQACgrpHOQUAGUCABQACgrpHOQUAGUCABMAAQpeD1FRADsAAAAA.',
Er='Erovia:BAABNQAECn8rAAIRAAoKrRGJgAAMAgARAAoKrRGJgAAMAgAAAA==.',
Es='Esclipse:BAAANQADCgYIBgAAAA==.',
Et='Etclock:BAAANQADCgYIBgAAAA==.',
Fa='Faeria:BAAANQABCgQIBAAAAA==.Farruq:BAAANQAECgUJCwAAAA==.Fathermoo:BAAANQAECgEIAQAAAA==.',
Fe='Feelsbadmang:BAAANQADCgQIBAABNQAECgoKJwAFAGcfAA==.Fellz:BAAANQADCgIIAgAAAA==.Ferer:BAEANQAECgEIAQABNQAFFAQICgAZAJ4HAA==.Ferian:BAAANQAECgQIEAAAAA==.Ferios:BAEANQADCgQIBAAAAA==.',
Fi='Fieth:BAAANQAECgEIAQAAAA==.',
Fl='Flavaflare:BAACNQAFFH8LAAMBAAQK8xNGOQDgAAABAAQK8xNGOQDgAAASAAEKAADdAQAAAAA1AAQKf1oAAwEACgpPI9cQAI8DAAEACgpPI9cQAI8DABIABQriFXoEABwBAAAA.',
Fo='Foodex:BAABNQAECn8UAAIWAAYKzxz/cgDDAQAWAAYKzxz/cgDDAQAAAA==.Fourleaf:BAACNQAFFH8MAAIZAAQKyg2pEADAAAAZAAQKyg2pEADAAAA1AAQKfzcAAxkACgqUHSYMAG0CABkACgqUHSYMAG0CABEAAQqHFmssAUwAAAAA.',
Fr='Frogplushy:BAACNQAFFH8FAAIBAAQKehXrEgBCAQABAAQKehXrEgBCAQA1AAQKfyoAAwEACgp+IQdDADYCAAEACgp+IQdDADYCAA0AAQoAAI1DAAAAAAAA.',
Fu='Furlock:BAABNQAECn8WAAMaAAcK7w0HHQB4AAAbAAcKcApNswDYAAAaAAIKMBIHHQB4AAAAAA==.Furral:BAABNQAECn88AAIOAAoKih62BQClAgAOAAoKih62BQClAgAAAA==.Furretc:BAAANQADCgEIAQAAAA==.',
Ga='Gaeth:BAABNQAECn8rAAIHAAoKxRNFJQD5AQAHAAoKxRNFJQD5AQAAAA==.Gardenhose:BAAANQAECgUICAAAAA==.',
Ge='Gengiss:BAAANQADCgQIBAAAAA==.',
Gi='Gigaret:BAAANQAECgcICAAAAA==.',
Gl='Gleg:BAACNQAFFH8RAAMKAAMKQRr7FwDgAAAKAAMKQRr7FwDgAAAJAAIKuggTKACKAAA1AAQKfzoAAwoACgpgIpUXABYDAAoACgpgIpUXABYDAAkABApaEM3IAGkAAAAA.',
Go='Goodside:BAAANQADCgYIDAAAAA==.',
Gr='Grimthebrave:BAABNQAECn8hAAIFAAoKoRqYRwAZAgAFAAoKoRqYRwAZAgAAAA==.Grimthecruel:BAABNQAECn8vAAQTAAoKAxnOGgCBAgATAAoKQhfOGgCBAgAMAAQKhRysFADuAAAUAAEK+RQSjwA9AAAAAA==.Grimthedread:BAAANQAECggIEAAAAA==.Gripless:BAAANQADCgQIBAAAAA==.Griselden:BAABNQAECn9FAAITAAoKnSEwCwCTAgATAAoKnSEwCwCTAgAAAA==.Grizzlyras:BAAANQADCggICAAAAA==.',
Gu='Gub:BAAANQAECgQJCwAAAA==.',
Ha='Hannsollo:BAAANQADCgMIAwAAAA==.',
Ho='Holyshock:BAAANQABCgYIEAAAAA==.',
['Hâ']='Hâmburger:BAAANQADCgIIAgAAAA==.',
Ir='Iridessa:BAAANQADCgcIEwAAAA==.',
Is='Ishpoo:BAABNQAECn8yAAMCAAoKdhW2YgByAgACAAoKdhW2YgByAgAcAAEKAABgfwAdAAAAAA==.',
Ja='Jangarinna:BAAANQAECgEIBAAAAA==.',
Ji='Jip:BAAANQAECgcIDAAAAA==.',
Jl='Jlawm:BAAANQADCgcIDAAAAA==.Jlawq:BAAANQADCgUIBQAAAA==.Jlawzzs:BAABNQAECn86AAIKAAoKehYdTgAsAgAKAAoKehYdTgAsAgAAAA==.',
Jo='Job:BAABNQAECn9AAAIUAAoKFSTSBACmAwAUAAoKFSTSBACmAwAAAA==.',
Ju='Judgim:BAAANQADCgQIBAABNQAECgUICwAGAAAAAA==.Judoriel:BAAANQAECgYIBgAAAA==.Junkyard:BAAANQADCgcIBwAAAA==.',
Ka='Kaimin:BAABNQAECn9EAAIYAAoKBx51GwDnAgAYAAoKBx51GwDnAgAAAA==.Karthas:BAAANQADCgcIDAAAAA==.Karuun:BAAANQAECgUICQABNQAECgoKIQAQAIAMAA==.',
Ke='Kezeshi:BAABNQAECn8ZAAIVAAgKugq5DABsAQAVAAgKugq5DABsAQAAAA==.',
Kh='Khaidralulz:BAABNQAECn9AAAMLAAoKWA7iDwADAgALAAoKWA7iDwADAgAKAAkKaA6vZQDcAQAAAA==.Khonsu:BAAANQAECgIIAgAAAA==.',
Ki='Kiba:BAABNQAECn85AAMdAAgK2g6LGQBSAQAdAAcKohCLGQBSAQAeAAcKDwu2MQD5AAAAAA==.',
Kr='Kraegen:BAABNQAECn8UAAIcAAgK0Q35MABXAQAcAAgK0Q35MABXAQAAAA==.Kray:BAAANQADCgYIBgAAAA==.',
Ky='Kyofu:BAACNQAFFH8FAAIdAAMKNglSBwC9AAAdAAMKNglSBwC9AAA1AAQKf0oAAx0ACgrUHPoKANYCAB0ACgrUHPoKANYCAB4ABAqIFqpCAAIBAAAA.',
La='Larenta:BAABNQAECn80AAIDAAoKKSO1CQB6AwADAAoKKSO1CQB6AwAAAA==.Larethiana:BAACNQAFFH8FAAIHAAUKfhKnBwCAAQAHAAUKfhKnBwCAAQA1AAQKfy0AAgcACgoAISgOAO8CAAcACgoAISgOAO8CAAE1AAQKCAgNAAYAAAAA.Laria:BAAANQAECggIDQAAAA==.',
Le='Leafmochi:BAAANQAECgQIBQAAAA==.Letloose:BAAANQADCgEIAQAAAA==.',
Li='Lightbright:BAACNQAFFH8FAAICAAIKQAs6JAB+AAACAAIKQAs6JAB+AAA1AAQKfzUAAgIACgqJI+spAB8DAAIACgqJI+spAB8DAAAA.Lildab:BAACNQAFFH8FAAIXAAIKlATpEABrAAAXAAIKlATpEABrAAA1AAQKf08AAhcACgozE6kTAAsCABcACgozE6kTAAsCAAAA.Linashia:BAACNQAFFH8HAAIWAAQKXgv8GQAPAQAWAAQKXgv8GQAPAQA1AAQKfy4AAhYACgo1FfI6ADsCABYACgo1FfI6ADsCAAAA.',
Lo='Lomein:BAAANQAECgEIAQAAAA==.Lostwanderer:BAAANQADCggIDgAAAA==.',
Lu='Luhen:BAAANQADCgYIBgAAAA==.',
Ma='Magicology:BAABNQAECn9hAAIBAAkKkCZ2AQD2AwABAAkKkCZ2AQD2AwAAAA==.Maimim:BAAANQAECgUICwAAAA==.Malacoda:BAABNQAECn84AAIUAAoKCx0yGQDRAgAUAAoKCx0yGQDRAgAAAA==.Manamommy:BAABNQAECn8bAAIBAAkKaxkWdACVAgABAAkKaxkWdACVAgAAAA==.Marble:BAAANQADCgYIBwAAAA==.',
Me='Merlx:BAAANQADCggIEQAAAA==.',
Mi='Miladee:BAAANQADCgYIBgAAAA==.Mindra:BAABNQAECn8ZAAIRAAgKdxgHZABNAgARAAgKdxgHZABNAgAAAA==.',
Mo='Moatie:BAAANQADCgQIBQAAAA==.Moobundo:BAABNQAECn8cAAMKAAoK7hLnXgCEAQAKAAkKHxPnXgCEAQAJAAEKAABOVwEhAAAAAA==.Moolasses:BAAANQAECgMIAQAAAA==.Moonmama:BAAANQADCgQIBAAAAA==.Moonwren:BAAANQAECggIEQAAAA==.Morgrin:BAAANQAECgYIEwAAAA==.',
Ne='Nezroz:BAAANQAECgYIBwABNQAECggINgATALkSAA==.',
Ni='Nicotine:BAAANQAECggIDwAAAA==.Nike:BAABNQAECn8nAAMFAAoKZx8hVwCGAgAFAAkKVB0hVwCGAgAfAAcKwx3JEgAxAQAAAA==.Nipsey:BAAANQAECgEIAQAAAA==.Nitwp:BAABNQAECn88AAMgAAoKPx4OCQDjAgAgAAkKSh0OCQDjAgAEAAYKCQ87MAAbAQAAAA==.Nizo:BAAANQAECgUIDwAAAA==.',
Nj='Njal:BAAANQADCgUIBQAAAA==.',
No='Novastrike:BAACNQAFFH8QAAMJAAYK2Q7XEgDIAAAJAAQK0QvXEgDIAAAKAAMK5wHkIwBvAAA1AAQKfzAAAwkACgqoGyg7AIkCAAkACgqoGyg7AIkCAAoAAwp1A1IHAVkAAAAA.',
Ny='Nymphia:BAAANQAECgUICgAAAA==.Nyrif:BAACNQAFFH8KAAIQAAUKKw3qFgCkAAAQAAUKKw3qFgCkAAA1AAQKfzMAAhAACgocHRMeAMECABAACgocHRMeAMECAAAA.',
Oj='Ojoon:BAABNQAECn8WAAIBAAcKPwfjHwFXAQABAAcKPwfjHwFXAQAAAA==.',
Om='Omnisllash:BAABNQAECn8nAAINAAoKIBgrCQBFAgANAAoKIBgrCQBFAgAAAA==.',
Pa='Pallamb:BAAANQAECgQIBAAAAA==.Pallymaster:BAAANQAECgEIAQAAAA==.',
Ph='Phyter:BAAANQAECgQICwAAAA==.',
Pi='Pillin:BAAANQAECgcIEAAAAA==.',
Po='Polyestr:BAAANQADCgQIBAAAAA==.Porkchowmein:BAAANQAECgMIBAAAAA==.',
Pr='Previousleon:BAAANQAECggIBgAAAA==.Prosmas:BAAANQAECggICwAAAA==.',
Ps='Psyffe:BAAANQAECgEIAQAAAA==.Psylence:BAAANQAECgMICAAAAA==.Psyrge:BAAANQAECgUIBwAAAA==.',
Qu='Queue:BAABNQAECn8hAAIQAAoKgAwvMwBvAQAQAAoKgAwvMwBvAQAAAA==.',
Ra='Ragevirus:BAAANQAECgIIAgAAAA==.Rathmara:BAAANQAECgIIAgAAAA==.',
Re='Redle:BAAANQADCggICgAAAA==.',
Rh='Rhordric:BAECNQAFFH8KAAIZAAQKngd9EQC0AAAZAAQKngd9EQC0AAA1AAQKfzsABBkACgqSGSQPADsCABkACgqEFyQPADsCABEABwrBEfKcAM0BACEAAQorB+oUACYAAAAA.',
Ri='Ringa:BAAANQAECgEIAQAAAA==.',
Ro='Roku:BAAANQAECgIIAgAAAA==.Rottenbeef:BAAANQAECgcIDAAAAA==.',
Ru='Runicmommy:BAAANQADCgUIBQAAAA==.',
Sa='Saintbull:BAAANQABCgYIBwAAAA==.Samwinchestr:BAAANQAECgMIAwAAAA==.Sanyoalt:BAAANQADCgEIAQAAAA==.',
Sc='Scemo:BAAANQADCgUIBQAAAA==.Scissorsista:BAAANQAECgQIBAAAAA==.',
Se='Sea:BAACNQAFFH8VAAIKAAYK7xsYBQAiAgAKAAYK7xsYBQAiAgA1AAQKfzQAAgoACgr0JP8HAIEDAAoACgr0JP8HAIEDAAAA.Sepsis:BAAANQAECggICQAAAA==.Serendipity:BAAANQAECgQICgAAAA==.',
Sh='Shadowaurora:BAAANQADCggJCAAAAA==.Shadowrose:BAABNQAECn8iAAQOAAkKXRUhFAC6AQAOAAkKXRUhFAC6AQAHAAIKQwkrYQBfAAAIAAEKAACcxwAbAAAAAA==.Shamano:BAAANQAECgQICQABNQAECggIMQAaAI4ZAA==.Shanogadin:BAAANQAECgUIDQAAAA==.Sheadas:BAAANQABCgEIAQAAAA==.Shiemi:BAAANQAECgUIDAAAAA==.',
Sl='Slashysally:BAAANQAECgEIAQAAAA==.',
So='Soju:BAAANQAECgQIBQAAAA==.Sotospeak:BAAANQAECgEIAQAAAA==.',
Sq='Squeaky:BAAANQAECgYIEQAAAA==.',
St='Starshade:BAAANQAECgYIBwAAAA==.Steeldeath:BAAANQADCgEIAQAAAA==.',
Su='Sungodess:BAAANQAECgcIAwAAAA==.',
Sy='Syrupp:BAABNQAECn8oAAIiAAoKoBj1JQBlAgAiAAoKoBj1JQBlAgAAAA==.',
Ta='Tayn:BAAANQADCgcIDAAAAA==.',
Th='Thackery:BAAANQADCggICwAAAA==.Thinsheets:BAAANQAECgEIAQABNQAECgkJHQACANUOAA==.',
Tr='Trenetalan:BAAANQADCgIJAgABNQADCggIEAAGAAAAAA==.Trickledown:BAAANQAECgUIBQAAAA==.',
Ts='Tsavø:BAAANQAECgQJBgAAAA==.',
Tw='Twinkle:BAABNQAECn8YAAIDAAkKShcMUwAhAgADAAkKShcMUwAhAgAAAA==.',
Un='Unholysage:BAABNQAECn8kAAMXAAgKVw09JgA7AQAXAAgKVw09JgA7AQAVAAYK4g6yEAAeAQAAAA==.Untouchable:BAAANQADCgEIAQAAAA==.',
Va='Valathiel:BAAANQADCggICwAAAA==.Valenîx:BAAANQAECgYICAABNQAFFAUIBwAEABgQAA==.',
Ve='Venetrazat:BAABNQAECn9OAAIgAAoKARrbBABtAgAgAAoKARrbBABtAgAAAA==.Vermithorr:BAAANQAECgEIAQAAAA==.',
Vi='Viserys:BAAANQAECggIEAAAAA==.',
Vo='Vo:BAAANQAECgEIAQAAAA==.Vol:BAAANQADCgUIBQAAAA==.',
Vu='Vulpra:BAABNQAECn8fAAMWAAoK+gvmWgC8AQAWAAkK6gzmWgC8AQAXAAEKAAAAeQAAAAAAAA==.',
['Vâ']='Vâlenix:BAACNQAFFH8HAAMEAAUKGBDUEAClAAAEAAMKHwnUEAClAAAgAAMKDQE4CABCAAA1AAQKfyMAAyAACgrbCoEdAHcBACAACQorDIEdAHcBAAQABwogCB0qAF4BAAAA.',
['Vä']='Välenix:BAAANQAECgIIAgABNQAFFAUIBwAEABgQAA==.',
Wa='Warder:BAABNQAECn8aAAIfAAkKvQ5oDwBsAQAfAAkKvQ5oDwBsAQAAAA==.',
We='Wewaskangz:BAAANQAECgUICgAAAA==.',
Wi='Wincks:BAABNQAECn8xAAQaAAgKjhkRCgCVAQAaAAgKjhkRCgCVAQAbAAMKGwrOIQF/AAAjAAEKfA5tdgA3AAAAAA==.',
Xh='Xhosar:BAABNQAECn9EAAIhAAoKWBNcBACiAgAhAAoKWBNcBACiAgAAAA==.',
Ya='Yaoden:BAAANQAECgYICwAAAA==.',
['Yú']='Yúffíe:BAAANQADCgYIBgAAAA==.',
Za='Zachthemage:BAABNQAECn8yAAIBAAoKdQpl1QDcAQABAAoKdQpl1QDcAQAAAA==.Zackman:BAACNQAFFH8MAAIDAAQKnwkYEgAIAQADAAQKnwkYEgAIAQA1AAQKf0gAAgMACgreFZs3ACkCAAMACgreFZs3ACkCAAAA.',
Zi='Zinatrax:BAAANQAECgEIAQAAAA==.',
Zo='Zombie:BAABNQAECn8iAAIYAAgK8RsVRAAKAgAYAAgK8RsVRAAKAgAAAA==.',
Zu='Zuldrakar:BAAANQADCgUICQAAAA==.Zulrea:BAABNQAECn9IAAIIAAoK1xsBFABuAgAIAAoK1xsBFABuAgAAAA==.',
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
