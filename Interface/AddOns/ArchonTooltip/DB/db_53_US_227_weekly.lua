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

local lookup = {'Unknown-Unknown','Mage-Arcane','Warlock-Destruction','Warlock-Demonology','DeathKnight-Frost','Warlock-Affliction','Paladin-Holy','Warrior-Protection','Druid-Guardian','Hunter-BeastMastery','Shaman-Restoration','Shaman-Enhancement','Warrior-Arms','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Discipline','Priest-Holy','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Unholy','Monk-Brewmaster','Monk-Windwalker','Druid-Restoration','Druid-Balance','DeathKnight-Blood','DemonHunter-Devourer','Paladin-Protection','Mage-Frost','Paladin-Retribution','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Absu:BAAANQAECgEIAQAAAA==.',
Ag='Agoneer:BAAANQAECgMIAwAAAA==.',
Al='Alezandre:BAAANQAECgMIAwABNQAECgUICwABAAAAAA==.',
Am='Amairah:BAABNQAECn9BAAICAAoK0htNLgCHAgACAAoK0htNLgCHAgAAAA==.Amarantha:BAABNQAECn8wAAMDAAoKzQr2NQDqAAAEAAkKfwuheAB0AQADAAYKZgT2NQDqAAAAAA==.',
An='Anaesthetize:BAAANQADCgMIBwAAAA==.Angelinalizy:BAAANQAECgUIBQAAAA==.Animagon:BAAANQADCgYIBgAAAA==.Animaker:BAABNQAECn85AAIFAAoKlhitKgBGAgAFAAoKlhitKgBGAgAAAA==.Anngus:BAAANQAECgMIBAAAAA==.',
As='Ashalethen:BAAANQABCgQIBQAAAA==.Ashido:BAAANQAECgYIBwAAAA==.Astreos:BAACNQAFFH8jAAQDAAkK8RiSAQAbAQAEAAUKug8wFgBEAQADAAMKcCOSAQAbAQAGAAIKuh1BBgBwAAA1AAQKfzYABAMACgqlJbcCACsDAAMACQquIrcCACsDAAYABgqlJCsKANgBAAQABgpZHXigAJUBAAAA.Astryd:BAAANQADCgMIDAAAAA==.',
At='Atticus:BAABNQAECn8lAAIHAAoKTBCzQAASAgAHAAoKTBCzQAASAgAAAA==.',
Au='Aurhon:BAAANQADCgQIBAAAAA==.',
Az='Azmoniä:BAAANQAECggICAAAAA==.Azorahaidh:BAAANQAFFAYICAAAAQ==.',
Ba='Bagawgwah:BAAANQADCgQIBAAAAA==.Balzinya:BAAANQADCgQIBAAAAA==.Bandurie:BAAANQADCgYICQAAAA==.Baultier:BAAANQAECgEIAQAAAA==.',
Be='Beraxes:BAABNQAECn9BAAIIAAoKox//BQALAwAIAAoKox//BQALAwAAAA==.Berkano:BAAANQADCgMIBwAAAA==.Bethäny:BAAANQADCgcICQAAAA==.',
Bl='Blackshiva:BAAANQAECgUIDAAAAA==.Blasser:BAAANQADCgYIBgAAAA==.Bloodhøøfkâi:BAAANQAECgEIAQABNQAECgkJFAAJAGMbAA==.Bluemaple:BAAANQAECgUICAAAAA==.',
Bn='Bnoi:BAAANQAECgIIAgAAAA==.',
Bo='Bose:BAAANQAECgEIAQAAAA==.',
Br='Breadpitt:BAAANQAECgUIBQAAAA==.Bronnd:BAAANQAECgQIBwAAAA==.',
Bu='Bullbeer:BAAANQADCgMIAwAAAA==.Bulsy:BAABNQAECn9OAAIKAAoKJiYCAwDXAwAKAAoKJiYCAwDXAwAAAA==.',
Ca='Calamidade:BAABNQAECn85AAMLAAoKzxJaXAClAQALAAoKzxJaXAClAQAMAAMKzgHXMwBIAAAAAA==.',
Ce='Ceeheston:BAAANQADCgQIBgAAAA==.Celebrimbor:BAACNQAFFH8KAAIHAAYKVxKSCgCuAQAHAAYKVxKSCgCuAQA1AAQKf0YAAgcACgooIQ0cANkCAAcACgooIQ0cANkCAAAA.Cerryan:BAABNQAECn8fAAIHAAcKLw9hdABYAQAHAAcKLw9hdABYAQAAAA==.Cexar:BAAANQAECgQIBgAAAA==.',
Ch='Churo:BAAANQADCgUIBQAAAA==.',
Cl='Clother:BAACNQAFFH8RAAINAAcKehy8BgBVAgANAAcKehy8BgBVAgA1AAQKfzQAAw0ACQq4JRwSAHQDAA0ACQq4JRwSAHQDAA4AAQqNJf0oAGcAAAAA.Cloud:BAACNQAFFH8QAAINAAYKIxcRDACPAQANAAYKIxcRDACPAQA1AAQKf1EAAg0ACgqUJDAOAIkDAA0ACgqUJDAOAIkDAAAA.',
Co='Coltist:BAAANQAECgQIBAAAAA==.Cormbread:BAAANQADCggICAAAAA==.',
Cr='Cravenfrost:BAAANQAECgUIBQAAAA==.Crypticwolf:BAAANQADCgMIAwAAAA==.',
Cu='Curses:BAABNQAECn8lAAIEAAoKPxRFRAAIAgAEAAoKPxRFRAAIAgAAAA==.',
Da='Daddypie:BAABNQAECn8bAAMPAAkKbRwIHwATAgAPAAgK2BsIHwATAgAQAAQKxxlbGQDOAAAAAA==.Dantheman:BAAANQADCgcIDwAAAA==.Darkwand:BAAANQADCgUIBQAAAA==.Dartisaic:BAAANQADCgQIBAAAAA==.David:BAAANQADCgYIBgABNQAECgoKMwAKAMwdAA==.Dazed:BAAANQAECggICgAAAA==.',
De='Deathkanight:BAAANQADCgYIBgAAAA==.Desubea:BAAANQADCgYIDAAAAA==.',
Dj='Djaztech:BAACNQAFFH8RAAMOAAYKzRyEAgC8AAANAAYKqxx8FwBmAQAOAAIKWiaEAgC8AAA1AAQKfzIAAw0ACgopJCEbAEsDAA0ACgonJCEbAEsDAA4ABQqAJCUOANABAAAA.',
Do='Doc:BAABNQAECn8rAAQRAAoKeBIxEAAmAQASAAoKqg/1ZQCuAQARAAUK+RExEAAmAQATAAIKcwP7bwBJAAAAAA==.',
Dr='Draha:BAABNQAECn8aAAQUAAcKmxBzLABFAQAUAAYKqQ1zLABFAQAVAAUKpAyZKwDJAAAWAAMK/BD6EgCwAAABNQAECgoKPAAIAJ0gAA==.Dreadhunter:BAAANQADCgMIAwAAAA==.Drshockêr:BAABNQAECn9GAAQLAAoKfyKoDQBUAwALAAoKfyKoDQBUAwAXAAIKsQxeGwFZAAAMAAEKZQbDNwAwAAAAAA==.Drugdhealer:BAAANQADCggIEAAAAA==.Druidbull:BAAANQAECgQIDQAAAA==.',
Du='Dumbledore:BAAANQAECggIBwAAAA==.Dunthat:BAAANQAECgQIBQAAAA==.Duthir:BAAANQADCgIIAgABNQAFFAYICQATAKkTAA==.',
Ea='Earthgrinder:BAAANQADCgUIBQABNQAECgoKMAAMAFsWAA==.',
Eg='Egrok:BAAANQAECgcIDgAAAA==.',
Em='Emaeel:BAAANQADCggIDAAAAA==.Emporia:BAAANQAECgUICAAAAA==.',
En='Enhangi:BAAANQADCgIIAgAAAA==.',
Er='Eraser:BAAANQAECgYIBwAAAA==.Erissel:BAAANQAECgUIDgABNQAECgcIDQABAAAAAA==.Erowyn:BAAANQADCgUIBgAAAA==.',
Es='Esso:BAACNQAFFH8IAAIYAAUKyBK+CwCcAAAYAAUKyBK+CwCcAAA1AAQKfy8AAxgACgoxHlIcAOICABgACgoxHlIcAOICAAUABArLF9hoAPwAAAAA.Estupink:BAAANQAECggIDgAAAA==.',
Fa='Faelure:BAAANQAECgIIBQAAAA==.',
Fe='Fenrix:BAAANQADCgIIAgAAAA==.',
Fi='Fiending:BAAANQADCggIDwAAAA==.Finnarius:BAAANQADCgYIBgAAAA==.',
Fo='Foros:BAABNQAECn8hAAIHAAoK2x/9IQDlAgAHAAoK2x/9IQDlAgAAAA==.',
Fr='Fryiertuck:BAABNQAECn8VAAMZAAkKIwXJFwC2AAAZAAkKIwXJFwC2AAAaAAUKMgHhYwBPAAAAAA==.',
Ga='Gabil:BAABNQAECn8lAAIVAAkK8AVhEgARAQAVAAkK8AVhEgARAQAAAA==.',
Ge='Gendorosan:BAABNQAECn8lAAMbAAkKlyJTCQA/AwAbAAkKlyJTCQA/AwAcAAEKyQDLmgAVAAAAAA==.',
Gn='Gnork:BAAANQAECgIIAgAAAA==.',
Go='Goldwolf:BAAANQADCgcIBwAAAA==.Gothpally:BAAANQAECgIIBAABNQAECggICQABAAAAAA==.',
Gr='Grayfoxx:BAABNQAECn8mAAMYAAkKWBYzTgDbAQAYAAkKRRUzTgDbAQAdAAcK2A+tWQDYAAAAAA==.Grazbibazz:BAAANQAECgUIBQABNQAECgoKQQACANIbAA==.Grìmmgor:BAACNQAFFH8dAAMYAAgKbB2YAgAdAgAYAAcKlx+YAgAdAgAFAAQKlxYzDQD4AAA1AAQKf00AAxgACgqhJLgEAKoDABgACQpjJrgEAKoDAAUACgrNIS8MAPgCAAAA.',
Ha='Halbrand:BAAANQAECgIIAgABNQAFFAYICgAHAFcSAA==.Hanet:BAAANQADCgMIBwAAAA==.',
He='Hellstomper:BAAANQAECgQIDAAAAA==.Heygrlhey:BAABNQAECn8qAAIKAAoK3iHAGQAyAwAKAAoK3iHAGQAyAwAAAA==.',
Hi='Hieronymous:BAAANQAECggIEAAAAA==.Hisokana:BAAANQADCgIIAgAAAA==.',
Hu='Hunna:BAABNQAECn8tAAIKAAgKzBB1mgB/AQAKAAgKzBB1mgB/AQAAAA==.Hurtzdonit:BAABNQAECn8VAAIEAAkKTxKyjADHAQAEAAkKTxKyjADHAQAAAA==.',
Il='Illusion:BAABNQAECn8/AAMPAAoKdCBSDABIAwAPAAoKdCBSDABIAwAeAAgKHw1DMwCoAQABNQAECgoKPwAPAHQgAA==.Ilmerel:BAAANQAECggIDQAAAA==.',
Im='Imass:BAAANQADCgUIBgABNQADCggIDAABAAAAAA==.Immatos:BAABNQAECn8aAAINAAkKQw45ggCCAQANAAkKQw45ggCCAQAAAA==.',
In='Inebriated:BAABNQAECn8aAAIKAAgKMgcgxgB1AQAKAAgKMgcgxgB1AQAAAA==.',
Is='Iselune:BAAANQADCggICgAAAA==.',
Ja='Jambi:BAAANQAECgYIDAAAAA==.Jankash:BAAANQADCgEIAQAAAA==.',
Je='Jeebüs:BAAANQAECgMIAgAAAA==.Jeremiahjnsn:BAAANQADCgQIBAAAAA==.',
Ju='Jukeboxhero:BAAANQADCgIIAgAAAA==.',
['Jê']='Jêanne:BAABNQAECn8aAAIFAAkK+Q8nSwCNAQAFAAkK+Q8nSwCNAQAAAA==.',
Ka='Kael:BAAANQAECgMIBQAAAA==.Kaveka:BAAANQAECgEIAQAAAA==.',
Ke='Kenoobi:BAABNQAECn8eAAICAAoKHw+fYgDxAQACAAoKHw+fYgDxAQAAAA==.Kermitted:BAAANQAECgQIBgABNQAECgoKKwAMAJEiAA==.',
Kh='Khán:BAAANQADCgYIBwAAAA==.',
Ki='Killjaeden:BAAANQABCgIIAgAAAA==.Kit:BAAANQAECgMIBQAAAA==.',
Ko='Koralin:BAAANQADCgEIAQAAAA==.Kou:BAAANQAECgYICQAAAA==.',
Kr='Kredrel:BAABNQAECn8eAAIfAAoKwBDqGQCkAQAfAAoKwBDqGQCkAQABNQAFFAUICAAZAHgMAA==.',
Ks='Ksauce:BAABNQAECn8VAAICAAYK6AGpnQGKAAACAAYK6AGpnQGKAAAAAA==.',
Ky='Kynan:BAAANQAECgQIAwABNQAECgoKRgAQAHAdAA==.Kynon:BAAANQAECgYIBgABNQAECgoKRgAQAHAdAA==.Kyran:BAABNQAECn9GAAMQAAoKcB28BQBeAgAQAAoKcB28BQBeAgAPAAcKYRE2QwAmAQAAAA==.Kyro:BAAANQADCggICAAAAA==.',
La='Lahughey:BAAANQADCgYICwAAAA==.Lamurun:BAAANQADCggIBwAAAA==.Lathina:BAABNQAECn8rAAMMAAoKkSLCBwD/AgAMAAoKkSLCBwD/AgAXAAEKuhd/JQFGAAAAAA==.Lavendere:BAAANQAECgYIDQABNQAFFAYICQATAKkTAA==.',
Li='Lilynilly:BAAANQAECgYIBgAAAA==.Linafox:BAABNQAECn8qAAMgAAoKWgmlEACEAQAgAAoKPQmlEACEAQACAAoKqwZKsgBAAQAAAA==.Linta:BAAANQADCggIDAAAAA==.',
Ll='Lluvia:BAABNQAECn8nAAICAAoKjwYQpwBWAQACAAoKjwYQpwBWAQAAAA==.',
Lo='Lokix:BAABNQAECn8fAAIYAAcKMRv8JwCiAQAYAAcKMRv8JwCiAQAAAA==.Lothsblood:BAAANQADCgUIDAAAAA==.',
Ly='Lysistratta:BAABNQAECn8lAAIdAAkK1QgtSwAQAQAdAAkK1QgtSwAQAQAAAA==.',
Ma='Magimal:BAAANQAECgQJCAABNQADCggIDAABAAAAAA==.Maldrakesus:BAABNQAECn8aAAMUAAkKYhI5IAAMAQAUAAYKUw05IAAMAQAVAAgKbwftEwD3AAABNQADCggIDAABAAAAAA==.Mariebenoit:BAAANQAECgUIBQAAAA==.Marquista:BAAANQAECgcIBwAAAA==.',
Mc='Mcsmitey:BAAANQADCggICAABNQAECgoKMAAMAFsWAA==.',
Me='Meatypoo:BAAANQAECgYIDQAAAA==.Meladaris:BAAANQAECgUICAAAAA==.Meloncrusher:BAAANQAECgEIAQAAAA==.Mey:BAABNQAECn9CAAISAAoKgRWgWADbAQASAAoKgRWgWADbAQAAAA==.',
Mi='Missperfect:BAAANQAECgEIAQAAAA==.Mitenalla:BAACNQAFFH8IAAIhAAUKSxQwIQCXAAAhAAUKSxQwIQCXAAA1AAQKfzAAAiEACgq4IjknACkDACEACgq4IjknACkDAAAA.',
Mo='Monsolo:BAAANQAECgYICAABNQAECgoKRgALAH8iAA==.Moosefluid:BAAANQAECgIIAgAAAA==.Morrdred:BAAANQAECggICgABNQAECggIEAABAAAAAA==.Mossberger:BAAANQADCggIEAAAAA==.',
My='Myoue:BAAANQAECgUICAAAAA==.Mysticraven:BAAANQADCgYIBwAAAA==.',
Na='Nagendra:BAABNQAECn82AAIVAAoK9hptCQDbAgAVAAoK9hptCQDbAgAAAA==.',
Ne='Nemains:BAAANQAECgIIBAAAAA==.Neoptolemos:BAAANQAECgQIBAAAAA==.',
Ni='Nicnevin:BAABNQAECn8qAAMVAAoKqQl2DgBfAQAVAAoKhAl2DgBfAQAWAAMKPAXeFgB1AAAAAA==.Nieko:BAAANQAECggIDgAAAA==.Nikolos:BAAANQADCgYIDAAAAA==.Nitrochrist:BAABNQAECn8+AAIEAAoKsxdCQgAPAgAEAAoKsxdCQgAPAgAAAA==.Nixxy:BAAANQADCgQIBAABNQAFFAYIDwAUAI4JAA==.',
No='Nokimi:BAAANQABCgIIAgAAAA==.Nordathair:BAAANQAECgUICgAAAA==.Nori:BAACNQAFFH8tAAMCAAgKniU7BACLAgACAAcKKSE7BACLAgAgAAMKyCZ1AQBXAQA1AAQKfyoAAwIACgrMJnELAKgDAAIACgrMJnELAKgDACAAAQpGJRU3AGAAAAAA.',
Nu='Nuala:BAAANQADCggIDgAAAA==.',
Ny='Nyxza:BAABNQAECn8lAAIKAAoKoxx2JwChAgAKAAoKoxx2JwChAgAAAA==.',
['Nï']='Nïeko:BAAANQAECggICAAAAA==.',
Or='Original:BAAANQAECggICAAAAA==.Originals:BAAANQAECggICAAAAA==.',
Pa='Painfulpoo:BAAANQAECgQIBAAAAA==.Papagorgio:BAAANQABCgcIBgAAAA==.Parsemae:BAACNQAFFH8FAAMCAAQKwAnpVwBRAAACAAMKJQvpVwBRAAAgAAEK9wbrFABCAAA1AAQKfy0AAwIACgqxFU+WAFMCAAIACgqxFU+WAFMCACAAAQrDE+A8AD8AAAAA.Pastries:BAAANQADCggICQABNQAFFAkJIwADAPEYAA==.',
Pi='Pitlin:BAABNQAECn8jAAQRAAoKOh8MCADrAQASAAoKXx1VNgCPAgARAAYKAB0MCADrAQATAAEKMQcCgAArAAAAAA==.',
Pm='Pmsavenger:BAAANQABCgcICwABNQAECgYIDAABAAAAAA==.',
Po='Post:BAAANQAECgQICAAAAA==.',
Pr='Priestalisha:BAACNQAFFH8XAAISAAYK0CMmBwAhAgASAAYK0CMmBwAhAgA1AAQKf1AAAhIACgqvJiwAAAoEABIACgqvJiwAAAoEAAAA.',
Ps='Psiphon:BAAANQADCgQIBAAAAA==.',
Qh='Qhhee:BAAANQADCgQIBAAAAA==.',
Ra='Raelana:BAABNQAECn8fAAIfAAcKmgqwNgDWAAAfAAcKmgqwNgDWAAAAAA==.Ransome:BAAANQADCgEIAQAAAA==.Raspberrie:BAAANQADCgQIBAAAAA==.Rawsteak:BAABNQAECn87AAIdAAoKASKoDwClAgAdAAoKASKoDwClAgAAAA==.',
Re='Redcrow:BAAANQAECgMIBQAAAA==.Redhanded:BAAANQAECggICgAAAA==.Reshocker:BAAANQADCgUIBQAAAA==.Restosexualz:BAAANQAECgIIAwAAAA==.',
Ri='Rixxiee:BAABNQAECn8YAAISAAkKYSBrIwDJAgASAAkKYSBrIwDJAgABNQAFFAYIDwAUAI4JAA==.Rixxy:BAACNQAFFH8PAAIUAAYKjgmyDQAOAQAUAAYKjgmyDQAOAQA1AAQKf3IABBQACgocIcQEAGIDABQACgocIcQEAGIDABUACApWEaUTABQCABYAAgooCr8gAFIAAAAA.',
Ro='Roastbeefdr:BAABNQAECn8bAAMYAAgKYB+pUQDNAQAYAAcKQSGpUQDNAQAFAAUKWRQfYAAlAQAAAA==.Root:BAAANQADCgQIBAAAAA==.',
Ru='Runeyugi:BAAANQADCgMIAwAAAA==.Rusladh:BAAANQADCggICAAAAA==.',
Sa='Saisaith:BAACNQAFFH8JAAMTAAYKqRMrEgCgAAATAAQKvBErEgCgAAASAAMKSgZQKwCLAAA1AAQKfz0AAxMACgrDHksNABcDABMACgrDHksNABcDABIAAgofJAmyAM4AAAAA.Sand:BAABNQAECn8XAAIdAAkKOBmBFQBfAgAdAAkKOBmBFQBfAgAAAA==.Sanguinbella:BAAANQAECgIIAgAAAA==.Saturday:BAAANQAECgEIAQAAAA==.Savadar:BAABNQAECn8fAAIPAAcKLRPcPgA/AQAPAAcKLRPcPgA/AQAAAA==.Saymourcox:BAAANQAECgMIAwAAAA==.',
Se='Setareh:BAAANQAECgYIDgAAAA==.',
Sh='Shakira:BAAANQADCgQIBAAAAA==.Shakuru:BAABNQAECn82AAIgAAoKKBKoCgAdAgAgAAoKKBKoCgAdAgAAAA==.Shkar:BAABNQAECn9GAAIOAAoKiR3EAwARAwAOAAoKiR3EAwARAwAAAA==.Shokan:BAAANQAECggIBwAAAA==.',
Si='Silandrya:BAAANQAECgMIBAAAAA==.',
Sj='Sjaridin:BAEANQADCgcIBwABNQAFFAcIFQAJALABAA==.',
Sl='Slenderama:BAAANQAECgQIDAAAAA==.',
Sm='Smawbrawl:BAAANQADCgUIBQAAAA==.',
So='Sock:BAABNQAECn8XAAMZAAgK9wyYGgA6AQAZAAcKiQ2YGgA6AQAaAAIKGgogYgApAAAAAA==.Soulintosh:BAABNQAECn8VAAIhAAYKYhdJzQCBAQAhAAYKYhdJzQCBAQAAAA==.',
St='Stepsiss:BAAANQAECggICQAAAA==.Stickylock:BAAANQADCgcIDQAAAA==.Stubs:BAAANQABCggIFwAAAA==.',
Su='Sule:BAEBNQAECn8WAAICAAgKng2Z4ADHAQACAAgKng2Z4ADHAQAAAA==.',
Sy='Syriais:BAAANQADCgEIAQAAAA==.',
['Sä']='Sämuel:BAAANQADCggICgAAAA==.',
Ta='Tatyniana:BAAANQADCgUIBQABNQAECgoKJgAfAJgaAA==.Taurengee:BAAANQADCgUJBQAAAA==.',
Te='Tenzin:BAAANQAECgEIAQAAAA==.',
Th='Thhee:BAABNQAECn8kAAIiAAkKQBNxEwCZAQAiAAkKQBNxEwCZAQAAAA==.Thorell:BAAANQAECgQIBAAAAA==.Thromm:BAAANQAECgEIAQAAAA==.',
Tr='Trigger:BAAANQADCgMIDAAAAA==.',
Ts='Tsuro:BAAANQAECgQICAAAAA==.',
Tw='Twotonsoffun:BAAANQADCgYIBgABNQAECgoKGgACABEOAA==.',
Tz='Tzunami:BAAANQAECgUICwAAAA==.',
Ud='Udernonsense:BAAANQADCgMIAwAAAA==.',
Un='Uncletoucher:BAABNQAECn8XAAICAAgK/h6kkABeAgACAAgK/h6kkABeAgAAAA==.Unholylife:BAAANQAECgIIAgAAAA==.',
Ut='Utena:BAABNQAECn9XAAIeAAoKuSHiBwDcAgAeAAoKuSHiBwDcAgAAAA==.',
Va='Valinta:BAAANQADCgEIAQAAAA==.',
Ve='Velleynyia:BAEANQAECggICwABNQAECggIFgACAJ4NAA==.Velocet:BAACNQAFFH8IAAMiAAUKKQZ7DACPAAAiAAQKKQZ7DACPAAAjAAEKAACLKwAAAAA1AAQKf1AAAyIACgohGyoPANUBACMACgoHEgE+AAUCACIACgohGyoPANUBAAAA.Vetlance:BAAANQADCgMIAwAAAA==.',
Vi='Vimpira:BAAANQADCgUIBQAAAA==.',
Vo='Voidbloom:BAAANQADCgYIBgABNQAECgoKMAAMAFsWAA==.',
Vy='Vynagos:BAAANQADCgQIBwAAAA==.',
['Vå']='Vålkyrïë:BAAANQAECgEIAQAAAA==.',
Wa='Waghdaddy:BAAANQAECgYICgAAAA==.Wannatry:BAAANQADCgQIBAAAAA==.',
We='Weeknave:BAAANQADCgUIBQAAAA==.',
Wi='Wichawayya:BAAANQADCgMIAwAAAA==.Windripper:BAABNQAECn8wAAIMAAoKWxZ6DwBxAgAMAAoKWxZ6DwBxAgAAAA==.',
Wo='Wobiwabi:BAAANQABCgIIAgAAAA==.Wokedeath:BAAANQAECgQIBAAAAA==.',
Wr='Wratheon:BAACNQAFFH8IAAIZAAUKeAy0BwB4AAAZAAUKeAy0BwB4AAA1AAQKf1kAAhkACgq5HjAEAIYCABkACgq5HjAEAIYCAAAA.',
Wu='Wuji:BAAANQAECgMICgAAAA==.',
Xa='Xablau:BAAANQADCgYIBgAAAA==.Xanthus:BAAANQADCgIIAgAAAA==.',
Xe='Xebec:BAAANQADCgQIBAAAAA==.',
['Xí']='Xí:BAAANQADCgQJBAAAAA==.',
Za='Zaddyy:BAAANQAECggIAwAAAA==.Zanuker:BAAANQADCgUIBQAAAA==.',
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
