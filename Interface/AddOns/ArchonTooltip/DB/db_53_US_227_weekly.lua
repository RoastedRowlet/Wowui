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

local lookup = {'Mage-Arcane','Warlock-Demonology','Warlock-Destruction','DeathKnight-Frost','Warlock-Affliction','Warrior-Protection','Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Shaman-Enhancement','Paladin-Holy','Warrior-Arms','Warrior-Fury','Shaman-Elemental','Priest-Shadow','DeathKnight-Unholy','Evoker-Devastation','Druid-Restoration','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Brewmaster','DemonHunter-Vengeance','Priest-Holy','Paladin-Retribution','Evoker-Preservation','Mage-Frost','Priest-Discipline','Evoker-Augmentation','Druid-Guardian','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Absu:BAAANQAECgEIAQAAAA==.',
Ag='Agoneer:BAAANQAECgMIAwAAAA==.',
Am='Amairah:BAABNQAECn8jAAIBAAkKeBcUDgD5AQABAAkKeBcUDgD5AQAAAA==.Amarantha:BAABNQAECn8kAAMCAAoKDQmJIwBgAQACAAkKZwmJIwBgAQADAAYKZgT2NQDqAAAAAA==.',
An='Anaesthetize:BAAANQADCgMIBAAAAA==.Angelinalizy:BAAANQADCgMIAwAAAA==.Animagon:BAAANQADCgYIBgAAAA==.Animaker:BAABNQAECn8tAAIEAAkK5RetKgBGAgAEAAkK5RetKgBGAgAAAA==.Anngus:BAAANQAECgMIBAAAAA==.',
As='Ashido:BAAANQADCgUIBwAAAA==.Astreos:BAACNQAFFH8fAAQDAAcKoBySAQAbAQACAAQKZBQwFgBEAQADAAMKcCOSAQAbAQAFAAEKAABBBgBwAAA1AAQKfyoABAMACgpxJLcCACsDAAMACQr5IbcCACsDAAIABQp6GnigAJUBAAUABgqTJAEDAEEBAAAA.Astryd:BAAANQADCgMIBQAAAA==.',
At='Atticus:BAAANQAECgYIDAAAAA==.',
Au='Aurhon:BAAANQADCgQIBAAAAA==.',
Az='Azmoniä:BAAANQAECggICAAAAA==.Azorahaidh:BAAANQAFFAUIBwAAAQ==.',
Ba='Bagawgwah:BAAANQADCgQIBAAAAA==.Balzinya:BAAANQADCgQIBAAAAA==.Bandurie:BAAANQADCgYICQAAAA==.Baultier:BAAANQAECgEIAQAAAA==.',
Be='Beraxes:BAABNQAECn8sAAIGAAoK8xv/BQALAwAGAAoK8xv/BQALAwAAAA==.Bethäny:BAAANQADCgcICQAAAA==.',
Bl='Blackshiva:BAAANQAECgUIBQAAAA==.Blasser:BAAANQADCgYIBgAAAA==.Bloodhøøfkâi:BAAANQAECgEIAQABNQAECggIEQAHAAAAAA==.Bluemaple:BAAANQADCgcIDAAAAA==.',
Bn='Bnoi:BAAANQAECgIIAgAAAA==.',
Bo='Bose:BAAANQAECgEIAQAAAA==.',
Br='Breadpitt:BAAANQADCgcICAAAAA==.Bronnd:BAAANQAECgQIBwAAAA==.',
Bu='Bullbeer:BAAANQADCgMIAwAAAA==.Bulsy:BAABNQAECn85AAIIAAoKriQCAwDXAwAIAAoKriQCAwDXAwAAAA==.',
Ca='Calamidade:BAABNQAECn8tAAMJAAkK5A8jeACjAQAJAAkK5A8jeACjAQAKAAIKiwCxNQA5AAAAAA==.Capwnd:BAAANQADCggIDwAAAA==.',
Ce='Ceeheston:BAAANQADCgQIBQAAAA==.Celebrimbor:BAACNQAFFH8HAAILAAQK/BDdCADsAAALAAQK/BDdCADsAAA1AAQKfzgAAgsACgokHL4mAM4CAAsACgokHL4mAM4CAAAA.Cerryan:BAAANQAECgMICAAAAA==.Cexar:BAAANQAECgQIBgAAAA==.',
Ch='Churo:BAAANQADCgUIBQAAAA==.',
Cl='Clother:BAACNQAFFH8RAAIMAAcKehy8BgBVAgAMAAcKehy8BgBVAgA1AAQKfzQAAwwACQq4JRwSAHQDAAwACQq4JRwSAHQDAA0AAQqNJf0oAGcAAAAA.Cloud:BAACNQAFFH8JAAIMAAQK6h6XBgASAQAMAAQK6h6XBgASAQA1AAQKf0QAAgwACgolJDAOAIkDAAwACgolJDAOAIkDAAAA.',
Co='Coltist:BAAANQAECgQIBAAAAA==.Cormbread:BAAANQADCggICAAAAA==.',
Cr='Cravenfrost:BAAANQADCgYIFAAAAA==.',
Cu='Curses:BAABNQAECn8aAAICAAcK1BNDdAAFAgACAAcK1BNDdAAFAgAAAA==.',
Da='Daddypie:BAAANQAECgYIBgABNQAECgkJJwACACQhAA==.Dantheman:BAAANQADCgcIDwAAAA==.Darkwand:BAAANQADCgUIBQAAAA==.David:BAAANQADCgYIBgABNQAECgkJGQAIAK8YAA==.',
De='Deathkanight:BAAANQADCgYIBgAAAA==.Desubea:BAAANQADCgYIDAAAAA==.',
Dj='Djaztech:BAACNQAFFH8OAAMNAAUKVByEAgC8AAAMAAQKJxx8FwBmAQANAAIKWiaEAgC8AAA1AAQKfycAAwwACgqzIyEbAEsDAAwACgqxIyEbAEsDAA0ABQqAJCUOANABAAAA.',
Do='Doc:BAAANQAECgQICwAAAA==.',
Dr='Draha:BAAANQAECgUIEAABNQAECgkJFgANAP4WAA==.Drshockêr:BAABNQAECn87AAQJAAoKviGoDQBUAwAJAAoKviGoDQBUAwAOAAIKAQheGwFZAAAKAAEKZQbDNwAwAAAAAA==.Drugdhealer:BAAANQADCggIEAAAAA==.Druidbull:BAAANQAECgIIAgAAAA==.',
Du='Dumbledore:BAAANQAECggIBwAAAA==.Dunthat:BAAANQAECgQIBQAAAA==.Duthir:BAAANQADCgIIAgABNQAFFAUICAAPALwRAA==.',
Ea='Earthgrinder:BAAANQADCgUIBQABNQAECgoKLAAKAFsWAA==.',
Eg='Egrok:BAAANQAECgYIDAAAAA==.',
Em='Emaeel:BAAANQADCggIDAAAAA==.Emporia:BAAANQAECgUICAAAAA==.',
En='Enhangi:BAAANQADCgIIAgAAAA==.',
Er='Erissel:BAAANQAECgUIDgAAAA==.Erowyn:BAAANQADCgUIBgAAAA==.',
Es='Esso:BAACNQAFFH8HAAIQAAQKBxbPFQCuAAAQAAQKBxbPFQCuAAA1AAQKfysAAxAACgo+HVIcAOICABAACgo+HVIcAOICAAQABArLF9hoAPwAAAAA.Estupink:BAAANQAECggIDgAAAA==.',
Fa='Faelure:BAAANQAECgIIBQAAAA==.',
Fi='Fiending:BAAANQADCggIDwAAAA==.Finnarius:BAAANQADCgYIBgAAAA==.',
Fo='Foros:BAAANQAECgcIEAAAAA==.',
Fr='Fryiertuck:BAAANQAECgYIDwAAAA==.',
Ga='Gabil:BAABNQAECn8dAAIRAAcKjwVDIgA5AQARAAcKjwVDIgA5AQAAAA==.',
Ge='Gendorosan:BAABNQAECn8dAAISAAcK8SO8BAAeAgASAAcK8SO8BAAeAgAAAA==.',
Gn='Gnork:BAAANQAECgEIAQAAAA==.',
Go='Goldwolf:BAAANQADCgcIBwAAAA==.',
Gr='Grayfoxx:BAABNQAECn8eAAMQAAcKixYzTgDbAQAQAAcKChUzTgDbAQATAAUKVBN6fgAAAQAAAA==.Grìmmgor:BAACNQAFFH8bAAMQAAcK5xyYAgAdAgAQAAYKex+YAgAdAgAEAAQKlxZKAwAVAQA1AAQKfzcAAxAACgoFJLgEAKoDABAACQpjJrgEAKoDAAQABAoaH58PAIgBAAAA.',
Ha='Halbrand:BAAANQAECgIIAgABNQAFFAQIBwALAPwQAA==.Hanet:BAAANQADCgMIAwAAAA==.',
He='Hellstomper:BAAANQAECgQIDAAAAA==.Heygrlhey:BAABNQAECn8qAAIIAAoK3iHAGQAyAwAIAAoK3iHAGQAyAwAAAA==.',
Hi='Hieronymous:BAAANQAECggIEAAAAA==.Hisokana:BAAANQADCgIIAgAAAA==.',
Hu='Hunna:BAABNQAECn8eAAIIAAYKtBRzYQDoAAAIAAYKtBRzYQDoAAAAAA==.Hurtzdonit:BAAANQAECgYIDgAAAA==.',
Il='Illusion:BAABNQAECn80AAMUAAoKJR9SDABIAwAUAAoKJR9SDABIAwAVAAgKHw1DMwCoAQABNQAECgoKNAAUACUfAA==.Ilmerel:BAAANQAECggIDQAAAA==.',
Im='Imawhitedot:BAAANQAECgIIAgAAAA==.Immatos:BAAANQAECgcIEQAAAA==.',
In='Inebriated:BAABNQAECn8aAAIIAAgKMgf9SgAdAQAIAAgKMgf9SgAdAQAAAA==.',
Is='Iselune:BAAANQADCggICgAAAA==.',
Ja='Jambi:BAAANQAECgQIBAAAAA==.Jankash:BAAANQADCgEIAQAAAA==.',
Je='Jeremiahjnsn:BAAANQADCgQIBAAAAA==.',
Ju='Jukeboxhero:BAAANQADCgIIAgAAAA==.',
['Jê']='Jêanne:BAABNQAECn8YAAIEAAgKQBAnSwCNAQAEAAgKQBAnSwCNAQAAAA==.',
Ka='Kael:BAAANQAECgIIBAAAAA==.Kaveka:BAAANQAECgEIAQAAAA==.',
Ke='Kenoobi:BAAANQAECgEIAQAAAA==.',
Kh='Khán:BAAANQADCgYIBwAAAA==.',
Ki='Killjaeden:BAAANQABCgIIAgAAAA==.',
Ko='Koralin:BAAANQADCgEIAQAAAA==.Kou:BAAANQAECgMIAwAAAA==.',
Kr='Kredrel:BAAANQAECgQIBgABNQAFFAQIBwAWAPgMAA==.',
Ks='Ksauce:BAAANQAECgQIDwAAAA==.',
Ky='Kynan:BAAANQADCggIGwABNQAECgoKNgAXAFoVAA==.Kynon:BAAANQAECgUIBQABNQAECgoKNgAXAFoVAA==.Kyran:BAABNQAECn82AAMXAAoKWhX2CwALAgAXAAoKWhX2CwALAgAUAAUK2g8jLQC4AAAAAA==.Kyro:BAAANQADCggICAAAAA==.',
La='Lahughey:BAAANQADCgYICwAAAA==.Lamurun:BAAANQADCggIBwAAAA==.Lathina:BAABNQAECn8jAAMKAAoKgSLCBwD/AgAKAAoKgSLCBwD/AgAOAAEKuhd/JQFGAAAAAA==.Lavendere:BAAANQAECgYIDQABNQAFFAUICAAPALwRAA==.',
Li='Lilynilly:BAAANQAECgMIAwAAAA==.Linafox:BAABNQAECn8WAAIBAAgKvQS+BQGEAQABAAgKvQS+BQGEAQAAAA==.Linta:BAAANQADCgIIAgABNQADCgcIDAAHAAAAAA==.',
Ll='Lluvia:BAABNQAECn8fAAIBAAkKqwYPNQBVAQABAAkKqwYPNQBVAQAAAA==.',
Lo='Lokix:BAAANQAECgMICAAAAA==.Lothsblood:BAAANQADCgUICAAAAA==.',
Ly='Lysistratta:BAABNQAECn8dAAITAAcKbwgLcAA1AQATAAcKbwgLcAA1AQAAAA==.',
Ma='Magimal:BAAANQAECgQJCAABNQADCggIDAAHAAAAAA==.Maldrakesus:BAAANQAECgcIDwABNQADCggIDAAHAAAAAA==.Mariebenoit:BAAANQADCgUIDQAAAA==.Marquista:BAAANQADCggIOAAAAA==.',
Mc='Mcsmitey:BAAANQADCggICAABNQAECgoKLAAKAFsWAA==.',
Me='Meatypoo:BAAANQAECgYIDQAAAA==.Meladaris:BAAANQAECgIIAwAAAA==.Meloncrusher:BAAANQADCgYICgAAAA==.Mey:BAABNQAECn8qAAIYAAkKuBWrMgA0AQAYAAkKuBWrMgA0AQAAAA==.',
Mi='Missperfect:BAAANQAECgEIAQAAAA==.Mitenalla:BAACNQAFFH8HAAIZAAQK6hZZIgCXAAAZAAQK6hZZIgCXAAA1AAQKfyYAAhkACgpdIjknACkDABkACgpdIjknACkDAAAA.',
Mo='Monsolo:BAAANQAECgMIAwABNQAECgoKOwAJAL4hAA==.Moosefluid:BAAANQAECgIIAgAAAA==.Morrdred:BAAANQAECggICgABNQAECggIEAAHAAAAAA==.',
My='Myoue:BAAANQAECgQIBgAAAA==.Mysticraven:BAAANQADCgYIBwAAAA==.',
Na='Nagendra:BAABNQAECn8tAAIRAAkKnxptCQDbAgARAAkKnxptCQDbAgAAAA==.',
Ne='Nemains:BAAANQAECgIIAgAAAA==.Neoptolemos:BAAANQAECgMIBAAAAA==.',
Ni='Nicnevin:BAABNQAECn8WAAIRAAgK1waKHQB2AQARAAgK1waKHQB2AQAAAA==.Nieko:BAAANQAECggIDgAAAA==.Nikolos:BAAANQADCgYIBgAAAA==.Nitrochrist:BAABNQAECn8tAAICAAkKuQ8WOwAaAQACAAkKuQ8WOwAaAQAAAA==.Nixxy:BAAANQADCgQIBAABNQAFFAQICwAaAMcLAA==.',
No='Nokimi:BAAANQABCgIIAgAAAA==.Nordathair:BAAANQAECgIIAwAAAA==.Nori:BAACNQAFFH8qAAMbAAcK8yY9AABJAQABAAYKtSE7BACLAgAbAAMKyCY9AABJAQA1AAQKfycAAwEACgqmJXELAKgDAAEACgqmJXELAKgDABsAAQpGJRU3AGAAAAAA.',
Nu='Nuala:BAAANQADCggIDgAAAA==.',
Ny='Nyxza:BAAANQAECggIEAAAAA==.',
['Nï']='Nïeko:BAAANQAECggICAAAAA==.',
Or='Original:BAAANQADCgUIBQAAAA==.Originals:BAAANQADCgUIBQAAAA==.',
Pa='Painfulpoo:BAAANQAECgQIBAAAAA==.Papagorgio:BAAANQABCgcIBgAAAA==.Parsemae:BAACNQAFFH8FAAMBAAQKwAlqKQBDAAABAAMKJQtqKQBDAAAbAAEK9wbrFABCAAA1AAQKfycAAwEACgqwE0+WAFMCAAEACgqwE0+WAFMCABsAAQqsD7waADYAAAAA.Pastries:BAAANQADCggICQABNQAFFAcIHwADAKAcAA==.',
Pi='Pitlin:BAABNQAECn8hAAQcAAgKzR8MCADrAQAYAAgKex1VNgCPAgAcAAYKAB0MCADrAQAPAAEKMQcCgAArAAAAAA==.',
Pm='Pmsavenger:BAAANQABCgcICwABNQAECgQIBAAHAAAAAA==.',
Po='Post:BAAANQADCgUIBgAAAA==.',
Pr='Priestalisha:BAACNQAFFH8XAAIYAAYK0CMmBwAhAgAYAAYK0CMmBwAhAgA1AAQKf0QAAhgACQqnJiwAAAoEABgACQqnJiwAAAoEAAAA.',
Ps='Psiphon:BAAANQADCgQIBAAAAA==.',
Qh='Qhhee:BAAANQADCgQIBAAAAA==.',
Ra='Raelana:BAAANQAECgMICAAAAA==.Ransome:BAAANQADCgEIAQAAAA==.Rawsteak:BAABNQAECn8kAAITAAoKTCA0AwBIAgATAAoKTCA0AwBIAgAAAA==.',
Re='Redcrow:BAAANQAECgMJBQAAAA==.Redhanded:BAAANQAECggICAAAAA==.Reshocker:BAAANQADCgUIBQAAAA==.Restosexualz:BAAANQAECgIIAwAAAA==.',
Ri='Rixxiee:BAAANQAECggICgABNQAFFAQICwAaAMcLAA==.Rixxy:BAACNQAFFH8LAAIaAAQKxwvrDgAVAQAaAAQKxwvrDgAVAQA1AAQKf1IABBoACgqwIMQEAGIDABoACgqwIMQEAGIDABEACApWEaUTABQCAB0AAgooCr8gAFIAAAAA.',
Ro='Roastbeefdr:BAABNQAECn8bAAMQAAgKYB+pUQDNAQAQAAcKQSGpUQDNAQAEAAUKWRQfYAAlAQAAAA==.Root:BAAANQADCgQIBAAAAA==.',
Ru='Rusladh:BAAANQADCggICAAAAA==.',
Sa='Saisaith:BAACNQAFFH8IAAMPAAUKvBErEgCgAAAPAAQKvBErEgCgAAAYAAIKIQXgHQBFAAA1AAQKfy8AAg8ACgo8HksNABcDAA8ACgo8HksNABcDAAAA.Sanguinbella:BAAANQAECgEIAgAAAA==.Saturday:BAAANQAECgIIAQAAAA==.Savadar:BAAANQAECgMICAAAAA==.Saymourcox:BAAANQAECgMIAwAAAA==.',
Se='Setareh:BAAANQAECgQICwAAAA==.',
Sh='Shakira:BAAANQADCgQIBAAAAA==.Shakuru:BAABNQAECn8qAAIbAAoK8RCoCgAdAgAbAAoK8RCoCgAdAgAAAA==.Shkar:BAABNQAECn87AAINAAkKYh3EAwARAwANAAkKYh3EAwARAwAAAA==.Shokan:BAAANQADCgUICQAAAA==.',
Si='Silandrya:BAAANQAECgEIAQAAAA==.',
Sj='Sjaridin:BAEANQADCgcIBwABNQAFFAUIEwAeAO4BAA==.',
Sl='Slenderama:BAAANQADCgYIBgAAAA==.',
Sm='Smawbrawl:BAAANQADCgUIBQAAAA==.',
So='Sock:BAABNQAECn8UAAIWAAcKiQ2YGgA6AQAWAAcKiQ2YGgA6AQAAAA==.Soulintosh:BAABNQAECn8VAAIZAAYKYhdJzQCBAQAZAAYKYhdJzQCBAQAAAA==.',
St='Stickylock:BAAANQADCgcIDQAAAA==.',
Su='Sule:BAEBNQAECn8WAAIBAAgKng2Z4ADHAQABAAgKng2Z4ADHAQAAAA==.',
Sy='Syriais:BAAANQADCgEIAQAAAA==.',
['Sä']='Sämuel:BAAANQADCgUIBgAAAA==.',
Ta='Tatyniana:BAAANQADCgUIBQABNQAECggIAQAHAAAAAA==.Taurengee:BAAANQADCgUJBQAAAA==.',
Te='Tenzin:BAAANQAECgEIAQAAAA==.',
Th='Thhee:BAABNQAECn8cAAIfAAcKsxIBQADNAQAfAAcKsxIBQADNAQAAAA==.Thromm:BAAANQAECgEIAQAAAA==.',
Tr='Trigger:BAAANQADCgMIBQAAAA==.',
Ts='Tsuro:BAAANQAECgEIBAAAAA==.',
Tw='Twotonsoffun:BAAANQADCgYIBgABNQAECgoKGQABAD4NAA==.',
Tz='Tzunami:BAAANQAECgQICgAAAA==.',
Un='Uncletoucher:BAABNQAECn8VAAIBAAcKoyCkkABeAgABAAcKoyCkkABeAgAAAA==.Unholylife:BAAANQAECgIIAgAAAA==.',
Ut='Utena:BAABNQAECn8xAAIVAAoKyhz9CgAtAwAVAAoKyhz9CgAtAwAAAA==.',
Ve='Velleynyia:BAEANQAECgYIBgABNQAECggIFgABAJ4NAA==.Velocet:BAACNQAFFH8HAAMfAAQKJgaeGACJAAAfAAMKJgaeGACJAAAgAAEKAABhEAAAAAA1AAQKfzAAAx8ACgqBF1kiAHMCAB8ACgqBF1kiAHMCACAABwqpC9AmAJABAAAA.Vetlance:BAAANQADCgMIAwAAAA==.',
Vi='Vimpira:BAAANQADCgUIBQAAAA==.',
Vo='Voidbloom:BAAANQADCgYIBgABNQAECgoKLAAKAFsWAA==.',
Vy='Vynagos:BAAANQADCgQIBwAAAA==.',
['Vå']='Vålkyrïë:BAAANQAECgEIAQAAAA==.',
Wa='Waghdaddy:BAAANQAECgYJCgAAAA==.Wannatry:BAAANQADCgQIBAAAAA==.',
We='Weeknave:BAAANQADCgUIBQAAAA==.',
Wi='Wichawayya:BAAANQADCgMIAwAAAA==.Windripper:BAABNQAECn8sAAIKAAoKWxacAQBaAgAKAAoKWxacAQBaAgAAAA==.',
Wo='Wobiwabi:BAAANQABCgIIAgAAAA==.Wokedeath:BAAANQAECgQIBAAAAA==.',
Wr='Wratheon:BAACNQAFFH8HAAIWAAQK+Az6CACFAAAWAAQK+Az6CACFAAA1AAQKf0AAAhYACgrBGxUFABYDABYACgrBGxUFABYDAAAA.',
Wu='Wuji:BAAANQAECgEIAwAAAA==.',
Xa='Xablau:BAAANQADCgYIBgAAAA==.Xanthus:BAAANQADCgIIAgAAAA==.',
Xe='Xebec:BAAANQADCgQIBAAAAA==.',
['Xí']='Xí:BAAANQADCgQJBAAAAA==.',
Za='Zanuker:BAAANQADCgUIBQAAAA==.',
Zo='Zoie:BAAANQADCggICQAAAA==.',
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
