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

local lookup = {'Mage-Arcane','Warlock-Demonology','Warlock-Destruction','DeathKnight-Frost','Warlock-Affliction','Paladin-Holy','Warrior-Protection','Druid-Guardian','Hunter-BeastMastery','Shaman-Restoration','Shaman-Enhancement','Warrior-Arms','Warrior-Fury','Hunter-Survival','Priest-Discipline','Priest-Holy','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Unholy','Monk-Brewmaster','Monk-Windwalker','Druid-Restoration','Druid-Balance','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Devourer','Unknown-Unknown','DemonHunter-Vengeance','Paladin-Retribution','Mage-Frost','Paladin-Protection','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Absu:BAAANQAECgEIAQAAAA==.',
Ag='Agoneer:BAAANQAECgMIAwAAAA==.',
Am='Amairah:BAABNQAECn80AAIBAAkKxxv+OwA2AgABAAkKxxv+OwA2AgAAAA==.Amarantha:BAABNQAECn8oAAMCAAoK+AnJagBdAQACAAkKjQrJagBdAQADAAYKZgT2NQDqAAAAAA==.',
An='Anaesthetize:BAAANQADCgMIBwAAAA==.Angelinalizy:BAAANQAECgUIBQAAAA==.Animagon:BAAANQADCgYIBgAAAA==.Animaker:BAABNQAECn85AAIEAAoKlhitKgBGAgAEAAoKlhitKgBGAgAAAA==.Anngus:BAAANQAECgMIBAAAAA==.',
As='Ashalethen:BAAANQABCgQIBQAAAA==.Ashido:BAAANQAECgYIBwAAAA==.Astreos:BAACNQAFFH8hAAQDAAgKzxySAQAbAQACAAQKZBQwFgBEAQADAAMKcCOSAQAbAQAFAAIKuh1BBgBwAAA1AAQKfzQABAMACgocJbcCACsDAAMACQquIrcCACsDAAUABgqlJCsKANgBAAIABgojHHigAJUBAAAA.Astryd:BAAANQADCgMICQAAAA==.',
At='Atticus:BAABNQAECn8fAAIGAAkKlxAWOgD8AQAGAAkKlxAWOgD8AQAAAA==.',
Au='Aurhon:BAAANQADCgQIBAAAAA==.',
Az='Azmoniä:BAAANQAECggICAAAAA==.Azorahaidh:BAAANQAFFAYICAAAAQ==.',
Ba='Bagawgwah:BAAANQADCgQIBAAAAA==.Balzinya:BAAANQADCgQIBAAAAA==.Bandurie:BAAANQADCgYICQAAAA==.Baultier:BAAANQAECgEIAQAAAA==.',
Be='Beraxes:BAABNQAECn89AAIHAAoKox//BQALAwAHAAoKox//BQALAwAAAA==.Berkano:BAAANQADCgMIBAAAAA==.Bethäny:BAAANQADCgcICQAAAA==.',
Bl='Blackshiva:BAAANQAECgUIDAAAAA==.Blasser:BAAANQADCgYIBgAAAA==.Bloodhøøfkâi:BAAANQAECgEIAQABNQAECgkJFAAIAGMbAA==.Bluemaple:BAAANQAECgUICAAAAA==.',
Bn='Bnoi:BAAANQAECgIIAgAAAA==.',
Bo='Bose:BAAANQAECgEIAQAAAA==.',
Br='Breadpitt:BAAANQAECgUIBQAAAA==.Bronnd:BAAANQAECgQIBwAAAA==.',
Bu='Bullbeer:BAAANQADCgMIAwAAAA==.Bulsy:BAABNQAECn9OAAIJAAoKJiYCAwDXAwAJAAoKJiYCAwDXAwAAAA==.',
Ca='Calamidade:BAABNQAECn85AAMKAAoKzxJOSQC7AQAKAAoKzxJOSQC7AQALAAMKzgEnLQBIAAAAAA==.',
Ce='Ceeheston:BAAANQADCgQIBgAAAA==.Celebrimbor:BAACNQAFFH8JAAIGAAUKlRQ8CgBxAQAGAAUKlRQ8CgBxAQA1AAQKf0UAAgYACgooIQ8UAOwCAAYACgooIQ8UAOwCAAAA.Cerryan:BAAANQAECgQIDgAAAA==.Cexar:BAAANQAECgQIBgAAAA==.',
Ch='Churo:BAAANQADCgUIBQAAAA==.',
Cl='Clother:BAACNQAFFH8RAAIMAAcKehy8BgBVAgAMAAcKehy8BgBVAgA1AAQKfzQAAwwACQq4JRwSAHQDAAwACQq4JRwSAHQDAA0AAQqNJf0oAGcAAAAA.Cloud:BAACNQAFFH8OAAIMAAUKBhs9CgBXAQAMAAUKBhs9CgBXAQA1AAQKf1EAAgwACgqUJDAOAIkDAAwACgqUJDAOAIkDAAAA.',
Co='Coltist:BAAANQAECgQIBAAAAA==.Cormbread:BAAANQADCggICAAAAA==.',
Cr='Cravenfrost:BAAANQADCgYIFgAAAA==.Crypticwolf:BAAANQADCgMIAwAAAA==.',
Cu='Curses:BAABNQAECn8kAAICAAoKARNSPQDsAQACAAoKARNSPQDsAQAAAA==.',
Da='Daddypie:BAAANQAECggIEQAAAA==.Dantheman:BAAANQADCgcIDwAAAA==.Darkwand:BAAANQADCgUIBQAAAA==.Dartisaic:BAAANQADCgQIBAAAAA==.David:BAAANQADCgYIBgABNQAECgoKKQAOAMgcAA==.Dazed:BAAANQAECggICgAAAA==.',
De='Deathkanight:BAAANQADCgYIBgAAAA==.Desubea:BAAANQADCgYIDAAAAA==.',
Dj='Djaztech:BAACNQAFFH8RAAMNAAYKzRyEAgC8AAAMAAYKqxx8FwBmAQANAAIKWiaEAgC8AAA1AAQKfzAAAwwACgogJCEbAEsDAAwACgoeJCEbAEsDAA0ABQqAJCUOANABAAAA.',
Do='Doc:BAABNQAECn8eAAQPAAoKFQ4xEAAmAQAQAAoKCwtuTQDJAQAPAAUK+RExEAAmAQARAAIKcwP7bwBJAAAAAA==.',
Dr='Draha:BAABNQAECn8aAAQSAAcKmxBzLABFAQASAAYKqQ1zLABFAQATAAUKpAyZKwDJAAAUAAMK/BD/DwCxAAABNQAECgoKKwAHAMseAA==.Dreadhunter:BAAANQADCgMIAwAAAA==.Drshockêr:BAABNQAECn9CAAQKAAoKfyKoDQBUAwAKAAoKfyKoDQBUAwAVAAIKsQxeGwFZAAALAAEKZQbDNwAwAAAAAA==.Drugdhealer:BAAANQADCggIEAAAAA==.Druidbull:BAAANQAECgMIBQAAAA==.',
Du='Dumbledore:BAAANQAECggIBwAAAA==.Dunthat:BAAANQAECgUIBQAAAA==.Duthir:BAAANQADCgIIAgABNQAFFAYICQARAKkTAA==.',
Ea='Earthgrinder:BAAANQADCgUIBQABNQAECgoKMAALAFsWAA==.',
Eg='Egrok:BAAANQAECgcIDgAAAA==.',
Em='Emaeel:BAAANQADCggIDAAAAA==.Emporia:BAAANQAECgUICAAAAA==.',
En='Enhangi:BAAANQADCgIIAgAAAA==.',
Er='Eraser:BAAANQAECgYIBwAAAA==.Erissel:BAAANQAECgUIDgAAAA==.Erowyn:BAAANQADCgUIBgAAAA==.',
Es='Esso:BAACNQAFFH8IAAIWAAUKyBJSCQCgAAAWAAUKyBJSCQCgAAA1AAQKfysAAxYACgo+HVIcAOICABYACgo+HVIcAOICAAQABArLF9hoAPwAAAAA.Estupink:BAAANQAECggIDgAAAA==.',
Fa='Faelure:BAAANQAECgIIBQAAAA==.',
Fi='Fiending:BAAANQADCggIDwAAAA==.Finnarius:BAAANQADCgYIBgAAAA==.',
Fo='Foros:BAAANQAECggIEgAAAA==.',
Fr='Fryiertuck:BAABNQAECn8UAAMXAAgKqATzHgD4AAAXAAgKqATzHgD4AAAYAAUKMgHhYwBPAAAAAA==.',
Ga='Gabil:BAABNQAECn8kAAITAAgKtQWxEQDsAAATAAgKtQWxEQDsAAAAAA==.',
Ge='Gendorosan:BAABNQAECn8kAAMZAAgKZSNCCgDwAgAZAAgKZSNCCgDwAgAaAAEKyQBMigAVAAAAAA==.',
Gn='Gnork:BAAANQAECgEIAQAAAA==.',
Go='Goldwolf:BAAANQADCgcIBwAAAA==.Gothpally:BAAANQAECgIIBAAAAA==.',
Gr='Grayfoxx:BAABNQAECn8lAAMWAAgK9xUzTgDbAQAWAAgKthQzTgDbAQAbAAcK2A8PTQDfAAAAAA==.Grìmmgor:BAACNQAFFH8bAAMWAAcK5xyYAgAdAgAWAAYKex+YAgAdAgAEAAQKlxYnCQAAAQA1AAQKf0QAAxYACgoOJLgEAKoDABYACQpjJrgEAKoDAAQACgo7IRgJAAMDAAAA.',
Ha='Halbrand:BAAANQAECgIIAgABNQAFFAUICQAGAJUUAA==.Hanet:BAAANQADCgMIBwAAAA==.',
He='Hellstomper:BAAANQAECgQIDAAAAA==.Heygrlhey:BAABNQAECn8qAAIJAAoK3iHAGQAyAwAJAAoK3iHAGQAyAwAAAA==.',
Hi='Hieronymous:BAAANQAECggIEAAAAA==.Hisokana:BAAANQADCgIIAgAAAA==.',
Hu='Hunna:BAABNQAECn8jAAIJAAYKtBQWogDCAQAJAAYKtBQWogDCAQAAAA==.Hurtzdonit:BAABNQAECn8VAAICAAkKTxKyjADHAQACAAkKTxKyjADHAQAAAA==.',
Il='Illusion:BAABNQAECn8/AAMcAAoKdCBSDABIAwAcAAoKdCBSDABIAwAdAAgKHw1DMwCoAQABNQAECgoKPwAcAHQgAA==.Ilmerel:BAAANQAECggIDQAAAA==.',
Im='Imass:BAAANQADCgUIBgABNQADCggICwAeAAAAAA==.Immatos:BAABNQAECn8aAAIMAAkKQw7fagCHAQAMAAkKQw7fagCHAQAAAA==.',
In='Inebriated:BAABNQAECn8aAAIJAAgKMgcgxgB1AQAJAAgKMgcgxgB1AQAAAA==.',
Is='Iselune:BAAANQADCggICgAAAA==.',
Ja='Jambi:BAAANQAECgUIBgAAAA==.Jankash:BAAANQADCgEIAQAAAA==.',
Je='Jeebüs:BAAANQAECgMIAgAAAA==.Jeremiahjnsn:BAAANQADCgQIBAAAAA==.',
Ju='Jukeboxhero:BAAANQADCgIIAgAAAA==.',
['Jê']='Jêanne:BAABNQAECn8ZAAIEAAgKQBAnSwCNAQAEAAgKQBAnSwCNAQAAAA==.',
Ka='Kael:BAAANQAECgMIBQAAAA==.Kaveka:BAAANQAECgEIAQAAAA==.',
Ke='Kenoobi:BAAANQAECggIDwAAAA==.Kermitted:BAAANQAECgQIBgABNQAECgoKKwALAJEiAA==.',
Kh='Khán:BAAANQADCgYIBwAAAA==.',
Ki='Killjaeden:BAAANQABCgIIAgAAAA==.Kit:BAAANQAECgMIBQAAAA==.',
Ko='Koralin:BAAANQADCgEIAQAAAA==.Kou:BAAANQAECgYICQAAAA==.',
Kr='Kredrel:BAAANQAECggIEQABNQAFFAUICAAXAHgMAA==.',
Ks='Ksauce:BAABNQAECn8VAAIBAAYK6AGpnQGKAAABAAYK6AGpnQGKAAAAAA==.',
Ky='Kynan:BAAANQAECgQIAwABNQAECgoKRQAfAHAdAA==.Kynon:BAAANQAECgYIBgABNQAECgoKRQAfAHAdAA==.Kyran:BAABNQAECn9FAAMfAAoKcB1qBABmAgAfAAoKcB1qBABmAgAcAAcKYRHhNgAtAQAAAA==.Kyro:BAAANQADCggICAAAAA==.',
La='Lahughey:BAAANQADCgYICwAAAA==.Lamurun:BAAANQADCggIBwAAAA==.Lathina:BAABNQAECn8rAAMLAAoKkSLCBwD/AgALAAoKkSLCBwD/AgAVAAEKuhd/JQFGAAAAAA==.Lavendere:BAAANQAECgYIDQABNQAFFAYICQARAKkTAA==.',
Li='Lilynilly:BAAANQAECgUIBQAAAA==.Linafox:BAABNQAECn8YAAIBAAoKPQW+BQGEAQABAAoKPQW+BQGEAQAAAA==.Linta:BAAANQADCggICwAAAA==.',
Ll='Lluvia:BAABNQAECn8nAAIBAAoKjwZujwBZAQABAAoKjwZujwBZAQAAAA==.',
Lo='Lokix:BAAANQAECgQIDgAAAA==.Lothsblood:BAAANQADCgUIDAAAAA==.',
Ly='Lysistratta:BAABNQAECn8kAAIbAAgK+wgcRwD3AAAbAAgK+wgcRwD3AAAAAA==.',
Ma='Magimal:BAAANQAECgQJCAABNQADCggIDAAeAAAAAA==.Maldrakesus:BAABNQAECn8ZAAMTAAgKbwfyEAD5AAATAAgKbwfyEAD5AAASAAUK8Q0dHwDfAAABNQADCggIDAAeAAAAAA==.Mariebenoit:BAAANQADCgUIDwAAAA==.Marquista:BAAANQADCggISAAAAA==.',
Mc='Mcsmitey:BAAANQADCggICAABNQAECgoKMAALAFsWAA==.',
Me='Meatypoo:BAAANQAECgYIDQAAAA==.Meladaris:BAAANQAECgIIAwAAAA==.Meloncrusher:BAAANQADCgYICwAAAA==.Mey:BAABNQAECn82AAIQAAoKgRXJTgDFAQAQAAoKgRXJTgDFAQAAAA==.',
Mi='Missperfect:BAAANQAECgEIAQAAAA==.Mitenalla:BAACNQAFFH8IAAIgAAUKSxShGQCbAAAgAAUKSxShGQCbAAA1AAQKfy4AAiAACgq4IjknACkDACAACgq4IjknACkDAAAA.',
Mo='Monsolo:BAAANQAECgYICAABNQAECgoKQgAKAH8iAA==.Moosefluid:BAAANQAECgIIAgAAAA==.Morrdred:BAAANQAECggICgABNQAECggIEAAeAAAAAA==.Mossberger:BAAANQADCggIEAAAAA==.',
My='Myoue:BAAANQAECgUICAAAAA==.Mysticraven:BAAANQADCgYIBwAAAA==.',
Na='Nagendra:BAABNQAECn82AAITAAoK9hovBQBGAgATAAoK9hovBQBGAgAAAA==.',
Ne='Nemains:BAAANQAECgIIBAAAAA==.Neoptolemos:BAAANQAECgQIBAAAAA==.',
Ni='Nicnevin:BAABNQAECn8YAAITAAoKoQeKHQB2AQATAAoKoQeKHQB2AQAAAA==.Nieko:BAAANQAECggIDgAAAA==.Nikolos:BAAANQADCgYIDAAAAA==.Nitrochrist:BAABNQAECn8+AAICAAoKsxd3MwATAgACAAoKsxd3MwATAgAAAA==.Nixxy:BAAANQADCgQIBAABNQAFFAUIDgASACwLAA==.',
No='Nokimi:BAAANQABCgIIAgAAAA==.Nordathair:BAAANQAECgMIBgAAAA==.Nori:BAACNQAFFH8tAAMBAAgKniU7BACLAgABAAcKKSE7BACLAgAhAAMKyCblAAA5AQA1AAQKfykAAwEACgrMJnELAKgDAAEACgrMJnELAKgDACEAAQpGJRU3AGAAAAAA.',
Nu='Nuala:BAAANQADCggIDgAAAA==.',
Ny='Nyxza:BAABNQAECn8bAAIJAAoKixuBOAA2AgAJAAoKixuBOAA2AgAAAA==.',
['Nï']='Nïeko:BAAANQAECggICAAAAA==.',
Or='Original:BAAANQAECggICAAAAA==.Originals:BAAANQAECggICAAAAA==.',
Pa='Painfulpoo:BAAANQAECgQIBAAAAA==.Papagorgio:BAAANQABCgcIBgAAAA==.Parsemae:BAACNQAFFH8FAAMBAAQKwAlNQwBBAAAhAAEK9wbrFABCAAABAAMKJQtNQwBBAAA1AAQKfyoAAwEACgqWFE+WAFMCAAEACgqWFE+WAFMCACEAAQqsD7A3ADIAAAAA.Pastries:BAAANQADCggICQABNQAFFAgIIQADAM8cAA==.',
Pi='Pitlin:BAABNQAECn8jAAQPAAoKOh8MCADrAQAQAAoKXx1VNgCPAgAPAAYKAB0MCADrAQARAAEKMQcCgAArAAAAAA==.',
Pm='Pmsavenger:BAAANQABCgcICwABNQAECgUIBgAeAAAAAA==.',
Po='Post:BAAANQAECgQIBgAAAA==.',
Pr='Priestalisha:BAACNQAFFH8XAAIQAAYK0CMmBwAhAgAQAAYK0CMmBwAhAgA1AAQKf08AAhAACgqjJiwAAAoEABAACgqjJiwAAAoEAAAA.',
Ps='Psiphon:BAAANQADCgQIBAAAAA==.',
Qh='Qhhee:BAAANQADCgQIBAAAAA==.',
Ra='Raelana:BAAANQAECgQIDgAAAA==.Ransome:BAAANQADCgEIAQAAAA==.Raspberrie:BAAANQADCgQIBAAAAA==.Rawsteak:BAABNQAECn8zAAIbAAoKwSFMDgCZAgAbAAoKwSFMDgCZAgAAAA==.',
Re='Redcrow:BAAANQAECgMIBQAAAA==.Redhanded:BAAANQAECggICgAAAA==.Reshocker:BAAANQADCgUIBQAAAA==.Restosexualz:BAAANQAECgIIAwAAAA==.',
Ri='Rixxiee:BAABNQAECn8YAAIQAAkKYSBoGQDeAgAQAAkKYSBoGQDeAgABNQAFFAUIDgASACwLAA==.Rixxy:BAACNQAFFH8OAAISAAUKLAvrDgAVAQASAAUKLAvrDgAVAQA1AAQKf2UABBIACgocIcQEAGIDABIACgocIcQEAGIDABMACApWEaUTABQCABQAAgooCr8gAFIAAAAA.',
Ro='Roastbeefdr:BAABNQAECn8bAAMWAAgKYB+pUQDNAQAWAAcKQSGpUQDNAQAEAAUKWRQfYAAlAQAAAA==.Root:BAAANQADCgQIBAAAAA==.',
Ru='Runeyugi:BAAANQADCgMIAwAAAA==.Rusladh:BAAANQADCggICAAAAA==.',
Sa='Saisaith:BAACNQAFFH8JAAMRAAYKqRMrEgCgAAARAAQKvBErEgCgAAAQAAMKSgZxIwCQAAA1AAQKfzgAAhEACgrDHksNABcDABEACgrDHksNABcDAAAA.Sand:BAAANQAECggIEgAAAA==.Sanguinbella:BAAANQAECgIIAgAAAA==.Saturday:BAAANQAECgIIAQAAAA==.Savadar:BAAANQAECgQIDgAAAA==.Saymourcox:BAAANQAECgMIAwAAAA==.',
Se='Setareh:BAAANQAECgUIDQAAAA==.',
Sh='Shakira:BAAANQADCgQIBAAAAA==.Shakuru:BAABNQAECn82AAIhAAoKKBKoCgAdAgAhAAoKKBKoCgAdAgAAAA==.Shkar:BAABNQAECn9BAAINAAoK6xnEAwARAwANAAoK6xnEAwARAwAAAA==.Shokan:BAAANQAECggIBwAAAA==.',
Si='Silandrya:BAAANQAECgMIBAAAAA==.',
Sj='Sjaridin:BAEANQADCgcIBwABNQAFFAcIFQAIALABAA==.',
Sl='Slenderama:BAAANQAECgQIBAAAAA==.',
Sm='Smawbrawl:BAAANQADCgUIBQAAAA==.',
So='Sock:BAABNQAECn8WAAMXAAgKlQyYGgA6AQAXAAcKiQ2YGgA6AQAYAAIK0gcYWAAlAAAAAA==.Soulintosh:BAABNQAECn8VAAIgAAYKYhdJzQCBAQAgAAYKYhdJzQCBAQAAAA==.',
St='Stickylock:BAAANQADCgcIDQAAAA==.Stubs:BAAANQABCggIFwAAAA==.',
Su='Sule:BAEBNQAECn8WAAIBAAgKng2Z4ADHAQABAAgKng2Z4ADHAQAAAA==.',
Sy='Syriais:BAAANQADCgEIAQAAAA==.',
['Sä']='Sämuel:BAAANQADCggICgAAAA==.',
Ta='Tatyniana:BAAANQADCgUIBQABNQAECgkJHQAiAMwXAA==.Taurengee:BAAANQADCgUJBQAAAA==.',
Te='Tenzin:BAAANQAECgEIAQAAAA==.',
Th='Thhee:BAABNQAECn8jAAIjAAgK0BM6FQBpAQAjAAgK0BM6FQBpAQAAAA==.Thromm:BAAANQAECgEIAQAAAA==.',
Tr='Trigger:BAAANQADCgMICQAAAA==.',
Ts='Tsuro:BAAANQAECgIIBQAAAA==.',
Tw='Twotonsoffun:BAAANQADCgYIBgABNQAECgoKGgABABEOAA==.',
Tz='Tzunami:BAAANQAECgQICgAAAA==.',
Un='Uncletoucher:BAABNQAECn8VAAIBAAcKoyCkkABeAgABAAcKoyCkkABeAgAAAA==.Unholylife:BAAANQAECgIIAgAAAA==.',
Ut='Utena:BAABNQAECn9AAAIdAAoK+iD9CgAtAwAdAAoK+iD9CgAtAwAAAA==.',
Va='Valinta:BAAANQADCgEIAQAAAA==.',
Ve='Velleynyia:BAEANQAECggICwABNQAECggIFgABAJ4NAA==.Velocet:BAACNQAFFH8IAAMjAAUKKQbBCACPAAAjAAQKKQbBCACPAAAkAAEKAACqIwAAAAA1AAQKfzoAAyMACgqxF1kiAHMCACMACgqxF1kiAHMCACQABwpgDdAmAJABAAAA.Vetlance:BAAANQADCgMIAwAAAA==.',
Vi='Vimpira:BAAANQADCgUIBQAAAA==.',
Vo='Voidbloom:BAAANQADCgYIBgABNQAECgoKMAALAFsWAA==.',
Vy='Vynagos:BAAANQADCgQIBwAAAA==.',
['Vå']='Vålkyrïë:BAAANQAECgEIAQAAAA==.',
Wa='Waghdaddy:BAAANQAECgYJCgAAAA==.Wannatry:BAAANQADCgQIBAAAAA==.',
We='Weeknave:BAAANQADCgUIBQAAAA==.',
Wi='Wichawayya:BAAANQADCgMIAwAAAA==.Windripper:BAABNQAECn8wAAILAAoKWxbQDQACAgALAAoKWxbQDQACAgAAAA==.',
Wo='Wobiwabi:BAAANQABCgIIAgAAAA==.Wokedeath:BAAANQAECgQIBAAAAA==.',
Wr='Wratheon:BAACNQAFFH8IAAIXAAUKeAz6BQCAAAAXAAUKeAz6BQCAAAA1AAQKf1gAAhcACgq5HlcDAIoCABcACgq5HlcDAIoCAAAA.',
Wu='Wuji:BAAANQAECgMIBwAAAA==.',
Xa='Xablau:BAAANQADCgYIBgAAAA==.Xanthus:BAAANQADCgIIAgAAAA==.',
Xe='Xebec:BAAANQADCgQIBAAAAA==.',
['Xí']='Xí:BAAANQADCgQJBAAAAA==.',
Za='Zaddyy:BAAANQAECggIAgAAAA==.Zanuker:BAAANQADCgUIBQAAAA==.',
Zo='Zoie:BAAANQAECgUIBQAAAA==.',
['Øc']='Øctavia:BAAANQADCgIIAgAAAA==.',
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
