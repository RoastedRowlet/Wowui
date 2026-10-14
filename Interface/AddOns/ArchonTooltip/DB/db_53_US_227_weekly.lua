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

local lookup = {'Mage-Arcane','Warlock-Destruction','Warlock-Demonology','DeathKnight-Frost','Warlock-Affliction','Warrior-Protection','Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Shaman-Enhancement','Paladin-Holy','Warrior-Arms','Warrior-Fury','Shaman-Elemental','Priest-Shadow','DeathKnight-Unholy','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Brewmaster','DemonHunter-Vengeance','Priest-Holy','Paladin-Retribution','Evoker-Devastation','Evoker-Preservation','Mage-Frost','Priest-Discipline','DeathKnight-Blood','Evoker-Augmentation','Druid-Guardian','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Absu:BAAANQAECgEIAQAAAA==.',
Ag='Agoneer:BAAANQAECgMIAwAAAA==.',
Am='Amairah:BAABNQAECn8bAAIBAAgKahdxmwBJAgABAAgKahdxmwBJAgAAAA==.Amarantha:BAABNQAECn8aAAMCAAgKDQS9NQDqAAACAAYK/gO9NQDqAAADAAQKKQT0EwGaAAAAAA==.',
An='Anaesthetize:BAAANQADCgEIAQAAAA==.Angelinalizy:BAAANQADCgMIAwAAAA==.Animagon:BAAANQADCgYIBgAAAA==.Animaker:BAABNQAECn8pAAIEAAgKpxnHKQBHAgAEAAgKpxnHKQBHAgAAAA==.Anngus:BAAANQAECgMIBAAAAA==.',
As='Ashido:BAAANQADCgUIBQAAAA==.Astreos:BAACNQAFFH8fAAQCAAcKoByQAQAcAQADAAQKZBTsFQBKAQACAAMKcCOQAQAcAQAFAAEKAAATBgBwAAA1AAQKfycABAIACQrOJLYCACsDAAIACQr5IbYCACsDAAUABQpQIxkKANgBAAMABQp6GjOeAJUBAAAA.Astryd:BAAANQADCgMIBQAAAA==.',
At='Atticus:BAAANQAECgUIBgAAAA==.',
Au='Aurhon:BAAANQADCgQIBAAAAA==.',
Az='Azorahaidh:BAAANQAFFAUIBwAAAQ==.',
Ba='Bagawgwah:BAAANQADCgQIBAAAAA==.Balzinya:BAAANQADCgQIBAAAAA==.Bandurie:BAAANQADCgYICQAAAA==.Baultier:BAAANQAECgEIAQAAAA==.',
Be='Beraxes:BAABNQAECn8lAAIGAAkKfh7mBQALAwAGAAkKfh7mBQALAwAAAA==.Bethäny:BAAANQADCgcICQAAAA==.',
Bl='Blackshiva:BAAANQAECgUIBQAAAA==.Blasser:BAAANQADCgYIBgAAAA==.Bloodhøøfkâi:BAAANQADCgcIHwABNQAECgcIEAAHAAAAAA==.Bluemaple:BAAANQADCgcIDAAAAA==.',
Bn='Bnoi:BAAANQAECgIIAgAAAA==.',
Bo='Bose:BAAANQAECgEIAQAAAA==.',
Br='Breadpitt:BAAANQADCgcICAAAAA==.Bronnd:BAAANQAECgQIBwAAAA==.',
Bu='Bullbeer:BAAANQADCgMIAwAAAA==.Bulsy:BAABNQAECn8zAAIIAAkKaiXxAgDXAwAIAAkKaiXxAgDXAwAAAA==.',
Ca='Calamidade:BAABNQAECn8pAAMJAAgK3A3QdgCjAQAJAAgK3A3QdgCjAQAKAAIKiwAKNQA5AAAAAA==.Capwnd:BAAANQADCggIDAAAAA==.',
Ce='Ceeheston:BAAANQADCgMIAwAAAA==.Celebrimbor:BAABNQAECn80AAILAAkK4hpeJgDOAgALAAkK4hpeJgDOAgAAAA==.Cerryan:BAAANQAECgIIBgAAAA==.Cexar:BAAANQAECgQIBgAAAA==.',
Ch='Churo:BAAANQADCgUIBQAAAA==.',
Cl='Clother:BAACNQAFFH8RAAIMAAcKehx0BgBWAgAMAAcKehx0BgBWAgA1AAQKfzQAAwwACQq4JZsRAHUDAAwACQq4JZsRAHUDAA0AAQqNJXAoAGcAAAAA.Cloud:BAACNQAFFH8FAAIMAAMKXRi0HgANAQAMAAMKXRi0HgANAQA1AAQKfz8AAgwACQroI90NAIoDAAwACQroI90NAIoDAAAA.',
Co='Coltist:BAAANQAECgQIBAAAAA==.Cormbread:BAAANQADCggICAAAAA==.',
Cr='Cravenfrost:BAAANQADCgYIDwAAAA==.',
Cu='Curses:BAABNQAECn8aAAIDAAcK1BNZcgAGAgADAAcK1BNZcgAGAgAAAA==.',
Da='Dantheman:BAAANQADCgcIDwAAAA==.Darkwand:BAAANQADCgUIBQAAAA==.David:BAAANQADCgYIBgABNQAECggIEQAHAAAAAA==.',
De='Deathkanight:BAAANQADCgYIBgAAAA==.Desubea:BAAANQADCgYIDAAAAA==.',
Dj='Djaztech:BAACNQAFFH8OAAMNAAUKVBx5AgC8AAAMAAQKJxzPFgBnAQANAAIKWiZ5AgC8AAA1AAQKfyUAAwwACQqiI5MaAEwDAAwACQqgI5MaAEwDAA0ABQqAJAMOANABAAAA.',
Do='Doc:BAAANQAECgQIBgAAAA==.',
Dr='Draha:BAAANQAECgUIDwAAAA==.Drshockêr:BAABNQAECn85AAQJAAkKkSJoDQBUAwAJAAkKkSJoDQBUAwAOAAIKAQhJFwFZAAAKAAEKZQYeNwAwAAAAAA==.Drugdhealer:BAAANQADCggIEAAAAA==.Druidbull:BAAANQAECgIIAgAAAA==.',
Du='Dumbledore:BAAANQAECggIBwAAAA==.Dunthat:BAAANQAECgQIBQAAAA==.Duthir:BAAANQADCgIIAgABNQAFFAIIBQAPANgTAA==.',
Ea='Earthgrinder:BAAANQADCgUIBQABNQAECggIIgAKAB4YAA==.',
Eg='Egrok:BAAANQAECgYIDAAAAA==.',
Em='Emaeel:BAAANQADCggIDAAAAA==.Emporia:BAAANQAECgUICAAAAA==.',
En='Enhangi:BAAANQADCgIIAgAAAA==.',
Er='Erissel:BAAANQAECgUIDgABNQAECgcIBwAHAAAAAA==.Erowyn:BAAANQADCgUIBgAAAA==.',
Es='Esso:BAACNQAFFH8FAAIQAAIK2hh+FQCuAAAQAAIK2hh+FQCuAAA1AAQKfyoAAxAACQo+HwscAOICABAACQo+HwscAOICAAQABArLF8JmAPwAAAAA.Estupink:BAAANQAECggIDgAAAA==.',
Fa='Faelure:BAAANQAECgIIBQAAAA==.',
Fi='Fiending:BAAANQADCggIDwAAAA==.Finnarius:BAAANQADCgYIBgAAAA==.',
Fo='Foros:BAAANQAECgcIDgAAAA==.',
Fr='Fryiertuck:BAAANQAECgYICwAAAA==.',
Ga='Gabil:BAAANQAECgYIEgAAAA==.',
Ge='Gendorosan:BAAANQAECgYIEgAAAA==.',
Gn='Gnork:BAAANQAECgEIAQAAAA==.',
Go='Goldwolf:BAAANQADCgcIBwAAAA==.',
Gr='Grayfoxx:BAAANQAECgYIEwAAAA==.Grìmmgor:BAACNQAFFH8WAAMQAAcK5xyGAgAdAgAQAAYKex+GAgAdAgAEAAEKlxIGGgBeAAA1AAQKfzIAAhAACQpjJp0EAKoDABAACQpjJp0EAKoDAAAA.',
Ha='Halbrand:BAAANQAECgIIAgABNQAECgkJNAALAOIaAA==.Hanet:BAAANQADCgMIAwAAAA==.',
He='Hellstomper:BAAANQAECgQIDAAAAA==.Heygrlhey:BAABNQAECn8pAAIIAAkKHiJWGQAzAwAIAAkKHiJWGQAzAwAAAA==.',
Hi='Hieronymous:BAAANQAECggIEAAAAA==.Hisokana:BAAANQADCgIIAgAAAA==.',
Hu='Hunna:BAAANQAECgUIEwAAAA==.Hurtzdonit:BAAANQAECgYIDgAAAA==.',
Il='Illusion:BAABNQAECn8wAAMRAAkKTCASDABIAwARAAkKTCASDABIAwASAAgKHw2yMgCoAQABNQAECgkKMAARAEwgAA==.Ilmerel:BAAANQAECggIDQAAAA==.',
Im='Imawhitedot:BAAANQAECgIIAgAAAA==.Immatos:BAAANQAECgcIDQAAAA==.',
In='Inebriated:BAAANQAECgYIEAAAAA==.',
Is='Iselune:BAAANQADCggICQAAAA==.',
Ja='Jambi:BAAANQAECgQIBAAAAA==.Jankash:BAAANQADCgEIAQAAAA==.',
Je='Jeremiahjnsn:BAAANQADCgQIBAAAAA==.',
Ju='Jukeboxhero:BAAANQADCgIIAgAAAA==.',
['Jê']='Jêanne:BAAANQAECgYIEAAAAA==.',
Ka='Kael:BAAANQAECgIIAgAAAA==.Kaveka:BAAANQAECgEIAQAAAA==.',
Kh='Khán:BAAANQADCgYIBwAAAA==.',
Ki='Killjaeden:BAAANQABCgIIAgAAAA==.',
Ko='Koralin:BAAANQADCgEIAQAAAA==.Kou:BAAANQAECgEIAQAAAA==.',
Kr='Kredrel:BAAANQAECgQIBgABNQAFFAIIBQATAOMQAA==.',
Ks='Ksauce:BAAANQAECgQIDwAAAA==.',
Ky='Kynan:BAAANQADCggIGwABNQAECgkJLgAUAH0UAA==.Kynon:BAAANQAECgQIBAABNQAECgkJLgAUAH0UAA==.Kyran:BAABNQAECn8uAAMUAAkKfRTSCwALAgAUAAkKfRTSCwALAgARAAQKswviZgDYAAAAAA==.Kyro:BAAANQADCggICAAAAA==.',
La='Lahughey:BAAANQADCgYICwAAAA==.Lamurun:BAAANQADCggIBwAAAA==.Lathina:BAABNQAECn8gAAMKAAkKsiGRBwACAwAKAAkKsiGRBwACAwAOAAEKuhdZIQFGAAAAAA==.Lavendere:BAAANQAECgYIDQABNQAFFAIIBQAPANgTAA==.',
Li='Linafox:BAAANQAECgcIEQAAAA==.Linta:BAAANQADCgIIAgABNQADCgcIDAAHAAAAAA==.',
Ll='Lluvia:BAABNQAECn8XAAIBAAgKOAeh8gCjAQABAAgKOAeh8gCjAQAAAA==.',
Lo='Lokix:BAAANQAECgIIBgAAAA==.Lothsblood:BAAANQADCgUICAAAAA==.',
Ly='Lysistratta:BAAANQAECgYIEwAAAA==.',
Ma='Magimal:BAAANQAECgQJCAABNQADCggIDAAHAAAAAA==.Maldrakesus:BAAANQAECgYICwABNQADCggIDAAHAAAAAA==.Mariebenoit:BAAANQADCgQICAAAAA==.Marquista:BAAANQADCggIMAAAAA==.',
Mc='Mcsmitey:BAAANQADCggICAABNQAECggIIgAKAB4YAA==.',
Me='Meatypoo:BAAANQAECgYIDQAAAA==.Meladaris:BAAANQAECgIIAwAAAA==.Meloncrusher:BAAANQADCgUIBQAAAA==.Mey:BAABNQAECn8kAAIVAAgKlhTTYwDxAQAVAAgKlhTTYwDxAQAAAA==.',
Mi='Missperfect:BAAANQAECgEIAQAAAA==.Mitenalla:BAACNQAFFH8FAAIWAAIKshh7IQCXAAAWAAIKshh7IQCXAAA1AAQKfyUAAhYACQoNI0YmACoDABYACQoNI0YmACoDAAAA.',
Mo='Monsolo:BAAANQAECgIIAQABNQAECgkJOQAJAJEiAA==.Moosefluid:BAAANQAECgIIAgAAAA==.Morrdred:BAAANQAECggICgABNQAECggIEAAHAAAAAA==.Mossberger:BAAANQADCggIEAAAAA==.',
My='Myoue:BAAANQAECgMIBQAAAA==.Mysticraven:BAAANQADCgYIBwAAAA==.',
Na='Nagendra:BAABNQAECn8tAAIXAAkKnxpQCQDcAgAXAAkKnxpQCQDcAgAAAA==.',
Ne='Neoptolemos:BAAANQAECgMIBAAAAA==.',
Ni='Nicnevin:BAAANQAECggIEQAAAA==.Nieko:BAAANQAECggIDgAAAA==.Nikolos:BAAANQADCgYIBgAAAA==.Nitrochrist:BAABNQAECn8pAAIDAAgKKw+iggDbAQADAAgKKw+iggDbAQAAAA==.Nixxy:BAAANQADCgQIBAABNQAFFAQICwAYAMcLAA==.',
No='Nokimi:BAAANQABCgIIAgAAAA==.Nordathair:BAAANQAECgEIAgAAAA==.Nori:BAACNQAFFH8jAAMBAAcK5CbvAwCLAgABAAYKtSHvAwCLAgAZAAMKeiZpAQBXAQA1AAQKfyYAAwEACQrPJg8LAKsDAAEACQrPJg8LAKsDABkAAQpGJWU2AGAAAAAA.',
Nu='Nuala:BAAANQADCggIDgAAAA==.',
Ny='Nyxza:BAAANQAECgYIDQAAAA==.',
['Nï']='Nïeko:BAAANQAECggICAAAAA==.',
Or='Original:BAAANQADCgUIBQAAAA==.Originals:BAAANQADCgUIBQAAAA==.',
Pa='Painfulpoo:BAAANQAECgQIBAAAAA==.Parsemae:BAABNQAECn8kAAMBAAkKWRTlkwBYAgABAAkKWRTlkwBYAgAZAAEKAgQ6UgAfAAAAAA==.Pastries:BAAANQADCggICQABNQAFFAcIHwACAKAcAA==.',
Pi='Pitlin:BAABNQAECn8gAAQaAAgK/R75BwDrAQAVAAgKqxx1NQCPAgAaAAYKAB35BwDrAQAPAAEKMQdOfgArAAAAAA==.',
Pm='Pmsavenger:BAAANQABCgcICwABNQAECgQIBAAHAAAAAA==.',
Po='Post:BAAANQADCgEIAQAAAA==.',
Pr='Priestalisha:BAACNQAFFH8TAAIVAAUKyiTUBgAhAgAVAAUKyiTUBgAhAgA1AAQKf0QAAhUACQqnJikAAAoEABUACQqnJikAAAoEAAAA.',
Ps='Psiphon:BAAANQADCgQIBAAAAA==.',
Qh='Qhhee:BAAANQADCgQIBAAAAA==.',
Ra='Raelana:BAAANQAECgIIBgAAAA==.Ransome:BAAANQADCgEIAQAAAA==.Rawsteak:BAABNQAECn8cAAIbAAgKXiH3FAACAwAbAAgKXiH3FAACAwAAAA==.',
Re='Redcrow:BAAANQAECgMJBQAAAA==.Reshocker:BAAANQADCgUIBQAAAA==.Restosexualz:BAAANQAECgIIAwAAAA==.',
Ri='Rixxiee:BAAANQAECggIBgABNQAFFAQICwAYAMcLAA==.Rixxy:BAACNQAFFH8LAAIYAAQKxwupDgAVAQAYAAQKxwupDgAVAQA1AAQKf08ABBgACQrwILQGADsDABgACQrwILQGADsDABcACApWEXgTABUCABwAAgooClwgAFIAAAAA.',
Ro='Roastbeefdr:BAABNQAECn8bAAMQAAgKYB/qUADMAQAQAAcKQSHqUADMAQAEAAUKWRQpXgAlAQAAAA==.Root:BAAANQADCgQIBAAAAA==.',
Sa='Saisaith:BAACNQAFFH8FAAMPAAIK2BPbEQCgAAAPAAIK2BPbEQCgAAAVAAEK6QXdOAA6AAA1AAQKfy4AAg8ACQrxHyINABcDAA8ACQrxHyINABcDAAAA.Sand:BAAANQAECgcIBwAAAA==.Sanguinbella:BAAANQAECgEIAQAAAA==.Saturday:BAAANQAECgEIAQAAAA==.Savadar:BAAANQAECgIIBgAAAA==.Saymourcox:BAAANQAECgMIAwAAAA==.',
Se='Setareh:BAAANQAECgQICAAAAA==.',
Sh='Shakira:BAAANQADCgQIBAAAAA==.Shakuru:BAABNQAECn8mAAIZAAkKWRJ8CgAdAgAZAAkKWRJ8CgAdAgAAAA==.Shkar:BAABNQAECn87AAINAAkKYh2/AwARAwANAAkKYh2/AwARAwAAAA==.Shokan:BAAANQADCgUICQAAAA==.',
Si='Silandrya:BAAANQAECgEIAQAAAA==.',
Sj='Sjaridin:BAEANQADCgcIBwABNQAFFAUIDgAdAD4BAA==.',
Sl='Slenderama:BAAANQADCgYIBgAAAA==.',
Sm='Smawbrawl:BAAANQADCgUIBQAAAA==.',
So='Sock:BAAANQAECgYIEAAAAA==.Soulintosh:BAABNQAECn8VAAIWAAYKYhf4yQCBAQAWAAYKYhf4yQCBAQAAAA==.',
St='Stickylock:BAAANQADCgcICAAAAA==.',
Su='Sule:BAEBNQAECn8WAAIBAAgKng1O3gDIAQABAAgKng1O3gDIAQAAAA==.',
Sy='Syriais:BAAANQADCgEIAQAAAA==.',
['Sä']='Sämuel:BAAANQADCgMJAwAAAA==.',
Ta='Tatyniana:BAAANQADCgUIBQABNQAECggIAQAHAAAAAA==.Taurengee:BAAANQADCgUJBQAAAA==.',
Te='Tenzin:BAAANQAECgEIAQAAAA==.',
Th='Thhee:BAAANQAECgYIEgAAAA==.Thromm:BAAANQAECgEIAQAAAA==.',
Tr='Trigger:BAAANQADCgMIBQAAAA==.',
Ts='Tsuro:BAAANQAECgEIAwAAAA==.',
Tw='Twotonsoffun:BAAANQADCgYIBgABNQAECgkJGAABALQNAA==.',
Tz='Tzunami:BAAANQAECgQICgAAAA==.',
Ud='Udernonsense:BAAANQADCgMIAwAAAA==.',
Un='Uncletoucher:BAAANQAECgYIEQAAAA==.Unholylife:BAAANQAECgIIAgAAAA==.',
Ut='Utena:BAABNQAECn8tAAISAAkKQx7JCgAuAwASAAkKQx7JCgAuAwAAAA==.',
Ve='Velleynyia:BAEANQAECgYIBgABNQAECggIFgABAJ4NAA==.Velocet:BAACNQAFFH8FAAIeAAIKSAcMGACJAAAeAAIKSAcMGACJAAA1AAQKfy8AAx4ACQpVFsIhAHMCAB4ACQpVFsIhAHMCAB8ABwqpC2AmAJABAAAA.Vetlance:BAAANQADCgMIAwAAAA==.',
Vi='Vimpira:BAAANQADCgUIBQAAAA==.',
Vo='Voidbloom:BAAANQADCgYIBgABNQAECggIIgAKAB4YAA==.',
Vy='Vynagos:BAAANQADCgQIBwAAAA==.',
['Vå']='Vålkyrïë:BAAANQAECgEIAQAAAA==.',
Wa='Waghdaddy:BAAANQAECgYJCgAAAA==.Wannatry:BAAANQADCgQIBAAAAA==.',
We='Weeknave:BAAANQADCgUIBQAAAA==.',
Wi='Wichawayya:BAAANQADCgMIAwAAAA==.Windripper:BAABNQAECn8iAAIKAAgKHhhLDwBzAgAKAAgKHhhLDwBzAgAAAA==.',
Wo='Wobiwabi:BAAANQABCgIIAgAAAA==.Wokedeath:BAAANQAECgQIBAAAAA==.',
Wr='Wratheon:BAACNQAFFH8FAAITAAIK4xDHCACFAAATAAIK4xDHCACFAAA1AAQKfzgAAhMACQpLHggFABYDABMACQpLHggFABYDAAAA.',
Wu='Wuji:BAAANQAECgEIAwAAAA==.',
Xa='Xablau:BAAANQADCgYIBgAAAA==.Xanthus:BAAANQADCgIIAgAAAA==.',
Xe='Xebec:BAAANQADCgQIBAAAAA==.',
['Xí']='Xí:BAAANQADCgQJBAAAAA==.',
Za='Zanuker:BAAANQADCgUIBQAAAA==.',
Zo='Zoie:BAAANQADCgQIBAAAAA==.',
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
