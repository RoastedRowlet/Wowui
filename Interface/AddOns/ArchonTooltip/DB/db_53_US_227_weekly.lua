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

local lookup = {'Mage-Arcane','Warlock-Demonology','Warlock-Destruction','DeathKnight-Frost','Warlock-Affliction','Warrior-Protection','Druid-Guardian','Hunter-BeastMastery','Shaman-Restoration','Shaman-Enhancement','Paladin-Holy','Warrior-Arms','Warrior-Fury','Hunter-Survival','Shaman-Elemental','Priest-Shadow','Unknown-Unknown','DeathKnight-Unholy','Evoker-Devastation','Druid-Restoration','Druid-Balance','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Brewmaster','DemonHunter-Vengeance','Evoker-Preservation','Priest-Holy','Paladin-Retribution','Mage-Frost','Priest-Discipline','Evoker-Augmentation','Monk-Windwalker','Paladin-Protection','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Absu:BAAANQAECgEIAQAAAA==.',
Ag='Agoneer:BAAANQAECgMIAwAAAA==.',
Am='Amairah:BAABNQAECn8rAAIBAAkK0xgIOwAHAgABAAkK0xgIOwAHAgAAAA==.Amarantha:BAABNQAECn8kAAMCAAoKDQlGXwBGAQACAAkKZwlGXwBGAQADAAYKZgT2NQDqAAAAAA==.',
An='Anaesthetize:BAAANQADCgMIBwAAAA==.Angelinalizy:BAAANQADCgMIAwAAAA==.Animagon:BAAANQADCgYIBgAAAA==.Animaker:BAABNQAECn81AAIEAAkK8hitKgBGAgAEAAkK8hitKgBGAgAAAA==.Anngus:BAAANQAECgMIBAAAAA==.',
As='Ashalethen:BAAANQABCgQIBQAAAA==.Ashido:BAAANQADCgUIBwAAAA==.Astreos:BAACNQAFFH8hAAQDAAgKzxySAQAbAQACAAQKZBQwFgBEAQADAAMKcCOSAQAbAQAFAAIKuh2nBABgAAA1AAQKfzMABAMACgocJbcCACsDAAMACQquIrcCACsDAAUABgqlJPEEAJoBAAIABQp6GnigAJUBAAAA.Astryd:BAAANQADCgMIBwAAAA==.',
At='Atticus:BAAANQAECgcIEQAAAA==.',
Au='Aurhon:BAAANQADCgQIBAAAAA==.',
Az='Azmoniä:BAAANQAECggICAAAAA==.Azorahaidh:BAAANQAFFAYICAAAAQ==.',
Ba='Bagawgwah:BAAANQADCgQIBAAAAA==.Balzinya:BAAANQADCgQIBAAAAA==.Bandurie:BAAANQADCgYICQAAAA==.Baultier:BAAANQAECgEIAQAAAA==.',
Be='Beraxes:BAABNQAECn81AAIGAAoKwx3/BQALAwAGAAoKwx3/BQALAwAAAA==.Berkano:BAAANQADCgIIAgAAAA==.Bethäny:BAAANQADCgcICQAAAA==.',
Bl='Blackshiva:BAAANQAECgUIBwAAAA==.Blasser:BAAANQADCgYIBgAAAA==.Bloodhøøfkâi:BAAANQAECgEIAQABNQAECgkJFAAHAGMbAA==.Bluemaple:BAAANQAECgUIBQAAAA==.',
Bn='Bnoi:BAAANQAECgIIAgAAAA==.',
Bo='Bose:BAAANQAECgEIAQAAAA==.',
Br='Breadpitt:BAAANQADCgcICAAAAA==.Bronnd:BAAANQAECgQIBwAAAA==.',
Bu='Bullbeer:BAAANQADCgMIAwAAAA==.Bulsy:BAABNQAECn9GAAIIAAoK9iUCAwDXAwAIAAoK9iUCAwDXAwAAAA==.',
Ca='Calamidade:BAABNQAECn81AAMJAAkKnhEhRgB9AQAJAAkKnhEhRgB9AQAKAAMKzgHvJgBKAAAAAA==.Capwnd:BAAANQADCggIDwAAAA==.',
Ce='Ceeheston:BAAANQADCgQIBQAAAA==.Celebrimbor:BAACNQAFFH8JAAILAAUKlRSvBwB9AQALAAUKlRSvBwB9AQA1AAQKf0EAAgsACgooIe4MAPwCAAsACgooIe4MAPwCAAAA.Cerryan:BAAANQAECgMICgAAAA==.Cexar:BAAANQAECgQIBgAAAA==.',
Ch='Churo:BAAANQADCgUIBQAAAA==.',
Cl='Clother:BAACNQAFFH8RAAIMAAcKehy8BgBVAgAMAAcKehy8BgBVAgA1AAQKfzQAAwwACQq4JRwSAHQDAAwACQq4JRwSAHQDAA0AAQqNJf0oAGcAAAAA.Cloud:BAACNQAFFH8OAAIMAAUKBhvXBgBkAQAMAAUKBhvXBgBkAQA1AAQKf04AAgwACgqUJDAOAIkDAAwACgqUJDAOAIkDAAAA.',
Co='Coltist:BAAANQAECgQIBAAAAA==.Cormbread:BAAANQADCggICAAAAA==.',
Cr='Cravenfrost:BAAANQADCgYIFAAAAA==.Crypticwolf:BAAANQADCgMIAwAAAA==.',
Cu='Curses:BAABNQAECn8iAAICAAoKmRDSMwDcAQACAAoKmRDSMwDcAQAAAA==.',
Da='Daddypie:BAAANQAECggIEAAAAA==.Dantheman:BAAANQADCgcIDwAAAA==.Darkwand:BAAANQADCgUIBQAAAA==.Dartisaic:BAAANQADCgQIBAAAAA==.David:BAAANQADCgYIBgABNQAECgoKHwAOAOAaAA==.Dazed:BAAANQAECggICAAAAA==.',
De='Deathkanight:BAAANQADCgYIBgAAAA==.Desubea:BAAANQADCgYIDAAAAA==.',
Dj='Djaztech:BAACNQAFFH8RAAMNAAYKzRyEAgC8AAAMAAYKqxx8FwBmAQANAAIKWiaEAgC8AAA1AAQKfy8AAwwACgq+IyEbAEsDAAwACgq8IyEbAEsDAA0ABQqAJCUOANABAAAA.',
Do='Doc:BAAANQAECgUIEAAAAA==.',
Dr='Draha:BAAANQAECgUIEAABNQAECgoKHgANANYaAA==.Drshockêr:BAABNQAECn8+AAQJAAoKviGoDQBUAwAJAAoKviGoDQBUAwAPAAIKAQheGwFZAAAKAAEKZQbDNwAwAAAAAA==.Drugdhealer:BAAANQADCggIEAAAAA==.Druidbull:BAAANQAECgIIBAAAAA==.',
Du='Dumbledore:BAAANQAECggIBwAAAA==.Dunthat:BAAANQAECgQIBQAAAA==.Duthir:BAAANQADCgIIAgABNQAFFAUICAAQALwRAA==.',
Ea='Earthgrinder:BAAANQADCgUIBQABNQAECgoKLAAKAFsWAA==.',
Eg='Egrok:BAAANQAECgYIDAAAAA==.',
Em='Emaeel:BAAANQADCggIDAAAAA==.Emporia:BAAANQAECgUICAAAAA==.',
En='Enhangi:BAAANQADCgIIAgAAAA==.',
Er='Eraser:BAAANQAECgYIBgAAAA==.Erissel:BAAANQAECgUIDgABNQAECgcIDQARAAAAAA==.Erowyn:BAAANQADCgUIBgAAAA==.',
Es='Esso:BAACNQAFFH8HAAISAAQKBxbPFQCuAAASAAQKBxbPFQCuAAA1AAQKfysAAxIACgo+HVIcAOICABIACgo+HVIcAOICAAQABArLF9hoAPwAAAAA.Estupink:BAAANQAECggIDgAAAA==.',
Fa='Faelure:BAAANQAECgIIBQAAAA==.',
Fi='Fiending:BAAANQADCggIDwAAAA==.Finnarius:BAAANQADCgYIBgAAAA==.',
Fo='Foros:BAAANQAECgcIEQAAAA==.',
Fr='Fryiertuck:BAAANQAECgYIDwAAAA==.',
Ga='Gabil:BAABNQAECn8jAAITAAcKvAW9EADGAAATAAcKvAW9EADGAAAAAA==.',
Ge='Gendorosan:BAABNQAECn8jAAMUAAcKVCTFCQCnAgAUAAcKVCTFCQCnAgAVAAEKyQBweQAWAAAAAA==.',
Gn='Gnork:BAAANQAECgEIAQAAAA==.',
Go='Goldwolf:BAAANQADCgcIBwAAAA==.Gothpally:BAAANQAECgIIAgAAAA==.',
Gr='Grayfoxx:BAABNQAECn8kAAMSAAcKixYzTgDbAQASAAcKChUzTgDbAQAWAAcK2A/sPgDlAAAAAA==.Grìmmgor:BAACNQAFFH8bAAMSAAcK5xyYAgAdAgASAAYKex+YAgAdAgAEAAQKlxaFBgAIAQA1AAQKfz4AAxIACgoOJLgEAKoDABIACQpjJrgEAKoDAAQACQo7IfcEAB0DAAAA.',
Ha='Halbrand:BAAANQAECgIIAgABNQAFFAUICQALAJUUAA==.Hanet:BAAANQADCgMIBQAAAA==.',
He='Hellstomper:BAAANQAECgQIDAAAAA==.Heygrlhey:BAABNQAECn8qAAIIAAoK3iHAGQAyAwAIAAoK3iHAGQAyAwAAAA==.',
Hi='Hieronymous:BAAANQAECggIEAAAAA==.Hisokana:BAAANQADCgIIAgAAAA==.',
Hu='Hunna:BAABNQAECn8jAAIIAAYKtBQWogDCAQAIAAYKtBQWogDCAQAAAA==.Hurtzdonit:BAAANQAECgYIDgAAAA==.',
Il='Illusion:BAABNQAECn8/AAMXAAoKfSBSDABIAwAXAAoKfSBSDABIAwAYAAgKHw1DMwCoAQABNQAECgoKPwAXAH0gAA==.Ilmerel:BAAANQAECggIDQAAAA==.',
Im='Imass:BAAANQADCgIIAgABNQADCgcIBwARAAAAAA==.Imawhitedot:BAAANQAECgIIAgAAAA==.Immatos:BAABNQAECn8aAAIMAAkKQw48UgCMAQAMAAkKQw48UgCMAQAAAA==.',
In='Inebriated:BAABNQAECn8aAAIIAAgKMgetkwAKAQAIAAgKMgetkwAKAQAAAA==.',
Is='Iselune:BAAANQADCggICgAAAA==.',
Ja='Jambi:BAAANQAECgUIBgAAAA==.Jankash:BAAANQADCgEIAQAAAA==.',
Je='Jeremiahjnsn:BAAANQADCgQIBAAAAA==.',
Ju='Jukeboxhero:BAAANQADCgIIAgAAAA==.',
['Jê']='Jêanne:BAABNQAECn8ZAAIEAAgKQBAnSwCNAQAEAAgKQBAnSwCNAQAAAA==.',
Ka='Kael:BAAANQAECgIIBQAAAA==.Kaveka:BAAANQAECgEIAQAAAA==.',
Ke='Kenoobi:BAAANQAECggIBwAAAA==.Kermitted:BAAANQAECgEIAQABNQAECgoKKwAKAJEiAA==.',
Kh='Khán:BAAANQADCgYIBwAAAA==.',
Ki='Killjaeden:BAAANQABCgIIAgAAAA==.Kit:BAAANQAECgMIAgAAAA==.',
Ko='Koralin:BAAANQADCgEIAQAAAA==.Kou:BAAANQAECgQIBAAAAA==.',
Kr='Kredrel:BAAANQAECgQIBgABNQAFFAQIBwAZAPgMAA==.',
Ks='Ksauce:BAABNQAECn8UAAIBAAUKegGpnQGKAAABAAUKegGpnQGKAAAAAA==.',
Ky='Kynan:BAAANQAECgQIAwABNQAECgoKPgAaAE4bAA==.Kynon:BAAANQAECgYIBgABNQAECgoKPgAaAE4bAA==.Kyran:BAABNQAECn8+AAMaAAoKThudAwBCAgAaAAoKThudAwBCAgAXAAUK2g+uRgCtAAAAAA==.Kyro:BAAANQADCggICAAAAA==.',
La='Lahughey:BAAANQADCgYICwAAAA==.Lamurun:BAAANQADCggIBwAAAA==.Lathina:BAABNQAECn8rAAMKAAoKkSLCBwD/AgAKAAoKkSLCBwD/AgAPAAEKuhd/JQFGAAAAAA==.Lavendere:BAAANQAECgYIDQABNQAFFAUICAAQALwRAA==.',
Li='Lilynilly:BAAANQAECgUIBQAAAA==.Linafox:BAABNQAECn8XAAIBAAkKBgW+BQGEAQABAAkKBgW+BQGEAQAAAA==.Linta:BAAANQADCgcIBwAAAA==.',
Ll='Lluvia:BAABNQAECn8jAAIBAAoKewZxcgBgAQABAAoKewZxcgBgAQAAAA==.',
Lo='Lokix:BAAANQAECgIICgAAAA==.Lothsblood:BAAANQADCgUICgAAAA==.',
Ly='Lysistratta:BAABNQAECn8jAAIWAAcKbwgnRQDNAAAWAAcKbwgnRQDNAAAAAA==.',
Ma='Magimal:BAAANQAECgQJCAABNQADCggIDAARAAAAAA==.Maldrakesus:BAABNQAECn8YAAMbAAcKIhRkGQDjAAAbAAUK8Q1kGQDjAAATAAcK5gfPDwDWAAABNQADCggIDAARAAAAAA==.Mariebenoit:BAAANQADCgUIDQAAAA==.Marquista:BAAANQADCggIQAAAAA==.',
Mc='Mcsmitey:BAAANQADCggICAABNQAECgoKLAAKAFsWAA==.',
Me='Meatypoo:BAAANQAECgYIDQAAAA==.Meladaris:BAAANQAECgIIAwAAAA==.Meloncrusher:BAAANQADCgYICgAAAA==.Mey:BAABNQAECn8tAAIcAAkKuBUcZQDwAQAcAAkKuBUcZQDwAQAAAA==.',
Mi='Missperfect:BAAANQAECgEIAQAAAA==.Mitenalla:BAACNQAFFH8HAAIdAAQK6hZZIgCXAAAdAAQK6hZZIgCXAAA1AAQKfygAAh0ACgpdIjknACkDAB0ACgpdIjknACkDAAAA.',
Mo='Monsolo:BAAANQAECgUIBwABNQAECgoKPgAJAL4hAA==.Moosefluid:BAAANQAECgIIAgAAAA==.Morrdred:BAAANQAECggICgABNQAECggIEAARAAAAAA==.',
My='Myoue:BAAANQAECgQIBwAAAA==.Mysticraven:BAAANQADCgYIBwAAAA==.',
Na='Nagendra:BAABNQAECn82AAITAAoK9hqUAwBZAgATAAoK9hqUAwBZAgAAAA==.',
Ne='Nemains:BAAANQAECgIIAgAAAA==.Neoptolemos:BAAANQAECgMIBAAAAA==.',
Ni='Nicnevin:BAABNQAECn8XAAITAAkKmAaKHQB2AQATAAkKmAaKHQB2AQAAAA==.Nieko:BAAANQAECggIDgAAAA==.Nikolos:BAAANQADCgYIBgAAAA==.Nitrochrist:BAABNQAECn81AAICAAkKiRJTSACMAQACAAkKiRJTSACMAQAAAA==.Nixxy:BAAANQADCgQIBAABNQAFFAUIDgAbACwLAA==.',
No='Nokimi:BAAANQABCgIIAgAAAA==.Nordathair:BAAANQAECgIIBQAAAA==.Nori:BAACNQAFFH8rAAMeAAcK8yaNAAA/AQABAAYKtSE7BACLAgAeAAMKyCaNAAA/AQA1AAQKfygAAwEACgrBJnELAKgDAAEACgrBJnELAKgDAB4AAQpGJRU3AGAAAAAA.',
Nu='Nuala:BAAANQADCggIDgAAAA==.',
Ny='Nyxza:BAABNQAECn8XAAIIAAkKAhm9SwC6AQAIAAkKAhm9SwC6AQAAAA==.',
['Nï']='Nïeko:BAAANQAECggICAAAAA==.',
Or='Original:BAAANQADCgUIBQAAAA==.Originals:BAAANQADCgUIBQAAAA==.',
Pa='Painfulpoo:BAAANQAECgQIBAAAAA==.Papagorgio:BAAANQABCgcIBgAAAA==.Parsemae:BAACNQAFFH8FAAMBAAQKwAlMOgBBAAAeAAEK9wbrFABCAAABAAMKJQtMOgBBAAA1AAQKfykAAwEACgqWFE+WAFMCAAEACgqWFE+WAFMCAB4AAQqsD2stADMAAAAA.Pastries:BAAANQADCggICQABNQAFFAgIIQADAM8cAA==.',
Pi='Pitlin:BAABNQAECn8jAAQfAAoKOh8MCADrAQAcAAoKXx1VNgCPAgAfAAYKAB0MCADrAQAQAAEKMQcCgAArAAAAAA==.',
Pm='Pmsavenger:BAAANQABCgcICwABNQAECgUIBgARAAAAAA==.',
Po='Post:BAAANQAECgQIAgAAAA==.',
Pr='Priestalisha:BAACNQAFFH8XAAIcAAYK0CMmBwAhAgAcAAYK0CMmBwAhAgA1AAQKf0wAAhwACgowJSwAAAoEABwACgowJSwAAAoEAAAA.',
Ps='Psiphon:BAAANQADCgQIBAAAAA==.',
Qh='Qhhee:BAAANQADCgQIBAAAAA==.',
Ra='Raelana:BAAANQAECgIICgAAAA==.Ransome:BAAANQADCgEIAQAAAA==.Rawsteak:BAABNQAECn8uAAIWAAoKnCCyDAB8AgAWAAoKnCCyDAB8AgAAAA==.',
Re='Redcrow:BAAANQAECgMIBQAAAA==.Redhanded:BAAANQAECggICAAAAA==.Reshocker:BAAANQADCgUIBQAAAA==.Restosexualz:BAAANQAECgIIAwAAAA==.',
Ri='Rixxiee:BAAANQAECggIDQABNQAFFAUIDgAbACwLAA==.Rixxy:BAACNQAFFH8OAAIbAAUKLAsbCgDOAAAbAAUKLAsbCgDOAAA1AAQKf1wABBsACgocIcQEAGIDABsACgocIcQEAGIDABMACApWEaUTABQCACAAAgooCr8gAFIAAAAA.',
Ro='Roastbeefdr:BAABNQAECn8bAAMSAAgKYB+pUQDNAQASAAcKQSGpUQDNAQAEAAUKWRQfYAAlAQAAAA==.Root:BAAANQADCgQIBAAAAA==.',
Ru='Rusladh:BAAANQADCggICAAAAA==.',
Sa='Saisaith:BAACNQAFFH8IAAMQAAUKvBErEgCgAAAQAAQKvBErEgCgAAAcAAIKIQUEKgBDAAA1AAQKfzQAAhAACgrDHksNABcDABAACgrDHksNABcDAAAA.Sand:BAAANQAECggICQAAAA==.Sanguinbella:BAAANQAECgEIAgAAAA==.Saturday:BAAANQAECgIIAQAAAA==.Savadar:BAAANQAECgIICgAAAA==.Saymourcox:BAAANQAECgMIAwAAAA==.',
Se='Setareh:BAAANQAECgUIDQAAAA==.',
Sh='Shakira:BAAANQADCgQIBAAAAA==.Shakuru:BAABNQAECn8wAAIeAAoKKBKoCgAdAgAeAAoKKBKoCgAdAgAAAA==.Shkar:BAABNQAECn87AAINAAkKYh3EAwARAwANAAkKYh3EAwARAwAAAA==.Shokan:BAAANQADCgUICQAAAA==.',
Si='Silandrya:BAAANQAECgMIBAAAAA==.',
Sj='Sjaridin:BAEANQADCgcIBwABNQAFFAYIFAAHAKsBAA==.',
Sl='Slenderama:BAAANQADCgYIBgAAAA==.',
Sm='Smawbrawl:BAAANQADCgUIBQAAAA==.',
So='Sock:BAABNQAECn8WAAMZAAgKlQyYGgA6AQAZAAcKiQ2YGgA6AQAhAAIK0gcUTQAnAAAAAA==.Soulintosh:BAABNQAECn8VAAIdAAYKYhdJzQCBAQAdAAYKYhdJzQCBAQAAAA==.',
St='Stickylock:BAAANQADCgcIDQAAAA==.Stubs:BAAANQABCggIFwAAAA==.',
Su='Sule:BAEBNQAECn8WAAIBAAgKng2Z4ADHAQABAAgKng2Z4ADHAQAAAA==.',
Sy='Syriais:BAAANQADCgEIAQAAAA==.',
['Sä']='Sämuel:BAAANQADCgUIBgAAAA==.',
Ta='Tatyniana:BAAANQADCgUIBQABNQAECgkJGwAiAF4XAA==.Taurengee:BAAANQADCgUJBQAAAA==.',
Te='Tenzin:BAAANQAECgEIAQAAAA==.',
Th='Thhee:BAABNQAECn8iAAIjAAcKyRSZFwA+AQAjAAcKyRSZFwA+AQAAAA==.Thromm:BAAANQAECgEIAQAAAA==.',
Tr='Trigger:BAAANQADCgMIBwAAAA==.',
Ts='Tsuro:BAAANQAECgEIBAAAAA==.',
Tw='Twotonsoffun:BAAANQADCgYIBgABNQAECgoKGgABABEOAA==.',
Tz='Tzunami:BAAANQAECgQICgAAAA==.',
Ud='Udernonsense:BAAANQADCgMIAwAAAA==.',
Un='Uncletoucher:BAABNQAECn8VAAIBAAcKoyCkkABeAgABAAcKoyCkkABeAgAAAA==.Unholylife:BAAANQAECgIIAgAAAA==.',
Ut='Utena:BAABNQAECn84AAIYAAoK+iD9CgAtAwAYAAoK+iD9CgAtAwAAAA==.',
Va='Valinta:BAAANQADCgEIAQAAAA==.',
Ve='Velleynyia:BAEANQAECggICwABNQAECggIFgABAJ4NAA==.Velocet:BAACNQAFFH8HAAMjAAQKJgaeGACJAAAjAAMKJgaeGACJAAAkAAEKAADnHAAAAAA1AAQKfzoAAyMACgqxFxESAG4BACQABwpgDdAmAJABACMACgqxFxESAG4BAAAA.Vetlance:BAAANQADCgMIAwAAAA==.',
Vi='Vimpira:BAAANQADCgUIBQAAAA==.',
Vo='Voidbloom:BAAANQADCgYIBgABNQAECgoKLAAKAFsWAA==.',
Vy='Vynagos:BAAANQADCgQIBwAAAA==.',
['Vå']='Vålkyrïë:BAAANQAECgEIAQAAAA==.',
Wa='Waghdaddy:BAAANQAECgYJCgAAAA==.Wannatry:BAAANQADCgQIBAAAAA==.',
We='Weeknave:BAAANQADCgUIBQAAAA==.',
Wi='Wichawayya:BAAANQADCgMIAwAAAA==.Windripper:BAABNQAECn8sAAIKAAoKWxauCQAVAgAKAAoKWxauCQAVAgAAAA==.',
Wo='Wobiwabi:BAAANQABCgIIAgAAAA==.Wokedeath:BAAANQAECgQIBAAAAA==.',
Wr='Wratheon:BAACNQAFFH8HAAIZAAQK+Az6CACFAAAZAAQK+Az6CACFAAA1AAQKf08AAhkACgrPHR0DAFgCABkACgrPHR0DAFgCAAAA.',
Wu='Wuji:BAAANQAECgIIBQAAAA==.',
Xa='Xablau:BAAANQADCgYIBgAAAA==.Xanthus:BAAANQADCgIIAgAAAA==.',
Xe='Xebec:BAAANQADCgQIBAAAAA==.',
['Xí']='Xí:BAAANQADCgQJBAAAAA==.',
Za='Zanuker:BAAANQADCgUIBQAAAA==.',
Zo='Zoie:BAAANQAECgEIAQAAAA==.',
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
