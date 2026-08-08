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

local lookup = {'Paladin-Holy','Rogue-Subtlety','DeathKnight-Unholy','DemonHunter-Devourer','Paladin-Retribution','Warrior-Fury','Priest-Holy','Priest-Shadow','Monk-Brewmaster','Monk-Windwalker','Warlock-Demonology','Shaman-Elemental','Hunter-BeastMastery','Unknown-Unknown','Mage-Frost','DeathKnight-Frost','Hunter-Marksmanship','Warlock-Destruction','Paladin-Protection','DemonHunter-Havoc','Monk-Mistweaver','DemonHunter-Vengeance','Warrior-Protection','Warlock-Affliction','Rogue-Assassination','Shaman-Restoration','Hunter-Survival','Warrior-Arms','Druid-Restoration','Evoker-Preservation','Evoker-Augmentation','Priest-Discipline','Druid-Balance','Druid-Feral','Shaman-Enhancement','Rogue-Outlaw','Druid-Guardian','DeathKnight-Blood',}
local provider = {region='US',realm='Runetotem',name='US',type='weekly',zone=46,date='2026-08-04',data={Ab='Abert:BAAALgADCgUJBQAAAA==.Abilify:BAAALgAECgEJAgAAAA==.',
Ac='Acts:BAAALgAFFAMJAwAAAA==.',
Ad='Adalinda:BAAALgADCgkJCgABLgAFFAcJHQABAA4ZAA==.',
Ae='Aegeus:BAAALgADCgEJAQABLgAFFAQJEwACADwfAA==.',
Ag='Agnor:BAACLgAFFH8LAAIDAAMJ3BS0PQDiAAADAAMJ3BS0PQDiAAAuAAQKfzYAAgMACAlXGtxAAAACAAMACAlXGtxAAAACAAAA.',
Al='Alatir:BAAALgADCgkJFAAAAA==.Altchoice:BAAALgAECgQJBAABLgAECggJJgABAFUWAA==.Alticus:BAAALgADCgEJAQAAAA==.',
Am='Amithia:BAAALgADCgkJCQAAAA==.',
An='Andrew:BAAALgAECgEJAQABLgAFFAgJFQAEAKQSAA==.Anien:BAAALgAECgYJEQAAAA==.Anklemauler:BAAALgAECgYJBgAAAA==.Anthem:BAAALgAECgYJBgAAAA==.Antibubble:BAABLgAECn8iAAIDAAkJTR+5IwB3AgADAAkJTR+5IwB3AgAAAA==.Antipeta:BAAALgAECgEJAgAAAA==.Anugg:BAAALgAECgEJAQAAAA==.Anwal:BAACLgAFFH8dAAMBAAcJDhlLEAC5AQABAAcJDhlLEAC5AQAFAAEJrAOGhAAuAAAuAAQKfy0AAwEACQlXHLsiAAkCAAEACAlIG7siAAkCAAUACQlCDDN5AHwBAAAA.',
Ar='Argus:BAABLgAECn8wAAIGAAgJHCNjCgC+AgAGAAgJHCNjCgC+AgAAAA==.Arithana:BAABLgAFFH8LAAMHAAQJSwYPJACbAAAHAAQJSwYPJACbAAAIAAEJIAcLQAA3AAABLgAFFAQJDAAJAOEOAA==.Arithbull:BAAALgAFFAIJAgABLgAFFAQJDAAJAOEOAA==.Arithfury:BAAALgAECgIJAgABLgAFFAQJDAAJAOEOAA==.Arithkick:BAACLgAFFH8MAAMJAAQJ4Q4ZKQAEAQAJAAQJ4Q4ZKQAEAQAKAAMJ6wr0KQCpAAAuAAQKfyEAAgkACAlFGW8UAGsCAAkACAlFGW8UAGsCAAAA.Arkaius:BAAALgADCgMJAwAAAA==.Arwenloa:BAAALgAECgIJAgAAAA==.',
As='Asayo:BAAALgAECgUJEgAAAA==.Asherie:BAAALgAECgQJCQABLgAECgkJFgAHAIIRAA==.Aske:BAABLgAECn8oAAILAAkJwBR1OgDwAQALAAkJwBR1OgDwAQAAAA==.Astolan:BAAALgAECgEJAgAAAA==.',
At='Atonga:BAAALgAECgQJBAAAAA==.',
Au='Augtistic:BAAALgAECgcJEQAAAA==.',
Az='Azuresun:BAABLgAECn8hAAIMAAkJ+wtUNgBgAQAMAAkJ+wtUNgBgAQAAAA==.',
Ba='Balerion:BAAALgAECgEJAwAAAA==.Ballak:BAABLgAECn8ZAAINAAcJzRGWVABrAQANAAcJzRGWVABrAQAAAA==.Barlee:BAAALgADCgEJAQABLgAFFAIJAQAOAAAAAA==.Barryobama:BAAALgAECgMJAwAAAA==.',
Be='Beatin:BAAALgAECgUJCgAAAA==.Belenzr:BAAALgADCgEJAQAAAA==.',
Bi='Bigdikley:BAAALgAECgYJEQAAAA==.Biggtater:BAAALgAECgEJAQAAAA==.Bintoo:BAAALgAECgEJAQAAAA==.Birdeye:BAAALgAFFAkJAwAAAA==.Biscüits:BAAALgADCgUJBQAAAA==.',
Bl='Bloodywake:BAAALgAECgYJCQAAAA==.Bloopydoo:BAABLgAECn8gAAIPAAkJNQm2LACXAAAPAAkJNQm2LACXAAAAAA==.Blort:BAAALgADCgEJAQAAAA==.Bláckbird:BAABLgAECn8bAAINAAkJMhohVQCkAQANAAkJMhohVQCkAQAAAA==.',
Bo='Bobbybouche:BAAALgAECgEJAQAAAA==.Bohliang:BAAALgADCgkJEAAAAA==.Boiorix:BAAALgADCgYJDAABLgAECgcJCAAOAAAAAA==.Boltywolty:BAAALgAECgYJCgAAAA==.Borim:BAAALgAECgEJAQAAAA==.',
Br='Bradine:BAAALgADCgUJBQAAAA==.Brandymae:BAAALgAECgMJCAAAAA==.Branholy:BAAALgADCgEJAQAAAA==.Brbpoopin:BAAALgAECgYJDQAAAA==.Brogress:BAAALgAECgEJAQAAAA==.Brotems:BAAALgAECgkJAQAAAA==.Bruwdflight:BAAALgAECgEJAQAAAA==.',
Bu='Bubblebuster:BAAALgAECgYJDAABLgAECgkJIgADAE0fAA==.Buggz:BAAALgADCgEJAQAAAA==.Bumwarrior:BAAALgADCgEJAQAAAA==.Burnphase:BAAALgADCgQJBwAAAA==.',
By='Byrdreisyl:BAAALgAECgQJBAAAAA==.',
Ca='Caosgonewild:BAAALgAECgYJBgAAAA==.Cayde:BAAALgADCgcJCwAAAA==.',
Ce='Celestyal:BAAALgAECgcJCAAAAA==.',
Ch='Chestie:BAABLgAECn8hAAMDAAkJdR1ITwDVAQADAAgJ6x1ITwDVAQAQAAIJOBqPKACPAAAAAA==.Chubbychi:BAAALgAECgIJAgAAAA==.',
Ci='Cinde:BAAALgADCgMJAwABLgAFFAQJEAANADscAA==.Cindy:BAACLgAFFH8QAAINAAQJOxzHMABOAQANAAQJOxzHMABOAQAuAAQKfykAAw0ACQn9HhAOAOECAA0ACQn9HhAOAOECABEAAQneBZ2RACkAAAAA.Cindyx:BAAALgAECgYJDwABLgAFFAQJEAANADscAA==.',
Co='Coast:BAABLgAECn8VAAISAAgJ1wcTGQDaAAASAAgJ1wcTGQDaAAAAAA==.Coldlock:BAAALgAECggJCAABLgAECgkJMAATAAUaAA==.Coldsore:BAABLgAECn8wAAQTAAkJBRqACgAhAgATAAkJ4RmACgAhAgABAAYJ+wZ+UwDqAAAFAAMJMQdwLQGDAAAAAA==.Coldwar:BAAALgADCgcJBwAAAA==.Conjuremoney:BAAALgADCgEJAQAAAA==.Cootpal:BAACLgAFFH8OAAIFAAQJ+RlSKADpAAAFAAQJ+RlSKADpAAAuAAQKfz4AAgUACQkMHoAaAKUCAAUACQkMHoAaAKUCAAAA.Costcohotdog:BAAALgAECgEJAwAAAA==.',
Cr='Crazyloon:BAAALgAECgUJCgAAAA==.Crewgr:BAAALgAECgEJAQABLgAECgEJAQAOAAAAAA==.Crewmix:BAAALgAECgEJAQAAAA==.Crewshield:BAAALgADCgMJAwABLgAECgEJAQAOAAAAAA==.Croe:BAAALgADCgMJAwAAAA==.',
Cy='Cynawyne:BAAALgAFFAIJAgAAAA==.Cynthea:BAAALgAECgkJCgAAAA==.',
['Cö']='Cörinthian:BAAALgAECgkJEAAAAA==.',
Da='Dahm:BAAALgAECgMJBgAAAA==.Dalasaurs:BAACLgAFFH8NAAIGAAMJxxncHADAAAAGAAMJxxncHADAAAAuAAQKfzAAAgYACAmTGKMoABoCAAYACAmTGKMoABoCAAAA.Dalasnipus:BAAALgADCgMJAwAAAA==.Dalbear:BAAALgADCgYJCQAAAA==.Darkpallas:BAAALgAECgYJCAAAAA==.Darkprophetc:BAABLgAECn89AAIPAAkJXQ4XFQAqAQAPAAkJXQ4XFQAqAQAAAA==.',
De='Deathfyre:BAAALgADCgQJBAAAAA==.Deathklaw:BAAALgAECgUJCAAAAA==.Deathnutz:BAAALgAECgEJAQAAAA==.Deluun:BAAALgADCgkJCQAAAA==.Demious:BAABLgAECn8aAAINAAkJqh9PEgC/AgANAAkJqh9PEgC/AgAAAA==.Demiurge:BAAALgAECgkJEAAAAA==.Demonfister:BAACLgAFFH8JAAIGAAMJwQwaOwDFAAAGAAMJwQwaOwDFAAAuAAQKfygAAgYACQn+G0cNAJkCAAYACQn+G0cNAJkCAAAA.Demonkiller:BAABLgAECn8eAAIUAAYJPAZ6QgCsAAAUAAYJPAZ6QgCsAAAAAA==.Denastiest:BAABLgAECn8uAAIEAAkJDA+iTQCdAQAEAAkJDA+iTQCdAQAAAA==.Denji:BAAALgAECggJEAAAAA==.Devistashion:BAAALgAECgEJAQAAAA==.Devvmonk:BAABLgAECn8WAAIVAAcJag0IUAAuAQAVAAcJag0IUAAuAQAAAA==.',
Di='Dindaratwo:BAAALgAFFAMJBAAAAA==.Divinegoat:BAAALgADCgEJAQAAAA==.',
Do='Doe:BAABLgAECn8pAAMWAAcJmyOlBQBIAgAWAAcJmyOlBQBIAgAUAAMJhhD+UgCdAAAAAA==.Dokta:BAABLgAECn8YAAIXAAgJMA+kHABRAQAXAAgJMA+kHABRAQAAAA==.',
Dr='Draflex:BAAALgAECgMJBAAAAA==.Drakonus:BAAALgADCgEJAQAAAA==.Drathal:BAACLgAFFH8HAAIFAAMJ2gLuTwBzAAAFAAMJ2gLuTwBzAAAuAAQKfz0AAgUACQkGCpIfANgAAAUACQkGCpIfANgAAAAA.Drjay:BAAALgADCgkJCwAAAA==.',
Dv='Dvergar:BAAALgAECgYJDAAAAA==.',
Ea='Eatshrooms:BAAALgAECgMJBAAAAA==.',
Ed='Edd:BAAALgAECgQJBAAAAA==.Eddiedean:BAAALgAECgkJBgAAAA==.',
El='Electolytic:BAAALgAECgEJAQAAAA==.Elessarr:BAAALgAECgQJBQABLgAFFAMJCwADANwUAA==.Elfgonewild:BAAALgAECgUJCgAAAA==.Ellessra:BAABLgAECn8mAAIPAAkJWwNFtQAZAQAPAAkJWwNFtQAZAQAAAA==.Elnegrouno:BAABLgAECn8fAAIXAAcJfR/SCgBjAgAXAAcJfR/SCgBjAgAAAA==.Eloper:BAAALgAFFAMJBAAAAA==.',
Em='Emoker:BAAALgAECgQJBAABLgAECgkJGQACAAMYAA==.Emotank:BAAALgAECgUJBgABLgAECggJGgANAFoSAA==.',
Er='Eragone:BAABLgAECn8UAAIPAAYJpwn+IgDHAAAPAAYJpwn+IgDHAAAAAA==.',
Et='Etoro:BAAALgADCgEJAgAAAA==.',
Ev='Evissier:BAACLgAFFH8OAAIYAAQJZh9ZAwBiAQAYAAQJZh9ZAwBiAQAuAAQKfx4AAhgACQljIQcBAAIDABgACQljIQcBAAIDAAAA.',
Ex='Exsequor:BAACLgAFFH8RAAITAAQJIiEnAwB8AQATAAQJIiEnAwB8AQAuAAQKfx0AAxMABgkLIz0TAJYBABMABgkLIz0TAJYBAAUAAQlyB/tQASsAAAAA.',
Ez='Ezuras:BAAALgAECgMJAwAAAA==.',
Fa='Faeyri:BAABLgAECn8vAAIMAAkJzhpEEQBnAgAMAAkJzhpEEQBnAgAAAA==.Fassandin:BAAALgAECgIJAgAAAA==.Fatgandolph:BAAALgAECgIJAgAAAA==.',
Fe='Felli:BAAALgAECgEJAQAAAA==.',
Fi='Fishermon:BAAALgAECgUJCAAAAA==.',
Fl='Flagfarmer:BAABLgAECn8dAAIBAAYJMSY9EQCLAgABAAYJMSY9EQCLAgAAAA==.Flataxe:BAAALgAECgMJAwAAAA==.Flixunt:BAAALgADCgEJAQAAAA==.',
Fo='Foidepas:BAAALgAECgcJDQAAAA==.Fourid:BAAALgAECgQJDAAAAA==.Foxannee:BAAALgAECgMJBgAAAA==.',
Fr='Freezyweezy:BAACLgAFFH8LAAIPAAQJ4Rt2UQA6AQAPAAQJ4Rt2UQA6AQAuAAQKfx8AAg8ACQnoIwseAKgCAA8ACQnoIwseAKgCAAAA.Frostfirer:BAAALgAECgYJAgAAAA==.',
Fu='Fudgeyenuh:BAAALgAECgkJCQAAAA==.',
Fy='Fyrewar:BAAALgAECgMJAwAAAA==.',
['Fú']='Fúry:BAAALgAECgcJCgAAAA==.',
Ga='Gallyn:BAACLgAFFH8TAAICAAQJPB+GEAAFAQACAAQJPB+GEAAFAQAuAAQKfx8AAwIACQkvHjwBAIYCAAIACQkvHjwBAIYCABkAAQkAB5chACoAAAAA.Gamm:BAAALgADCgcJEQAAAA==.Garaal:BAABLgAECn8VAAIGAAgJGwwyRAA1AQAGAAgJGwwyRAA1AQAAAA==.Gaytorade:BAAALgAECgUJBgAAAA==.',
Ge='Geloise:BAAALgAECgMJAwAAAA==.Geoffery:BAAALgAECgEJAQAAAA==.Gerel:BAAALgAECgYJBgAAAA==.',
Gi='Ginyu:BAAALgAFFAIJAgAAAA==.',
Gl='Glacierrock:BAAALgADCgQJCgAAAA==.Gloria:BAABLgAECn8jAAIaAAkJ3gneTQB6AQAaAAkJ3gneTQB6AQAAAA==.',
Go='Gooblicious:BAAALgAECgEJAQAAAA==.Gori:BAAALgAECgIJAgAAAA==.',
Gr='Grail:BAABLgAECn8eAAIFAAcJ4A3apQAvAQAFAAcJ4A3apQAvAQAAAA==.Grelvisse:BAAALgAECgMJBQAAAA==.Grippywippy:BAAALgADCgYJBAAAAA==.',
Gu='Gudren:BAAALgADCgEJAQAAAA==.Guimon:BAAALgAECgMJBAAAAA==.Gunslinger:BAAALgAECgEJAQAAAA==.Guthrekka:BAAALgAECgYJBgAAAA==.',
Gw='Gwenie:BAABLgAECn8mAAILAAkJYhHePQDlAQALAAkJYhHePQDlAQAAAA==.',
Ha='Halenicion:BAAALgAFFAEJAQAAAA==.Haulg:BAAALgADCgMJAwAAAA==.Hauntfrost:BAAALgAECgEJAQAAAA==.Hazél:BAAALgADCgYJBgAAAA==.',
He='Helix:BAAALgAECgIJAgAAAA==.Hellbena:BAAALgAECgcJDgAAAA==.',
Hi='Hippoltyos:BAABLgAECn8tAAIHAAkJnA4fJgCUAQAHAAkJnA4fJgCUAQAAAA==.',
Ho='Honestlee:BAAALgAECgQJBAAAAA==.Honourablee:BAAALgAECgcJCwAAAA==.Hortzul:BAAALgADCgMJAwABLgAFFAcJHQABAA4ZAA==.Hotsaucce:BAAALgADCgEJAQAAAA==.Hotstheboss:BAAALgADCgYJBgAAAA==.Houe:BAAALgADCgUJCAAAAA==.',
Hu='Huffle:BAAALgAECgEJAQAAAA==.Huntardiness:BAABLgAECn8iAAQbAAkJMRSBJQBxAQANAAgJyBNLUAB4AQAbAAkJSguBJQBxAQARAAEJ7g7UPQAuAAAAAA==.Hunterd:BAAALgADCgEJAQAAAA==.',
Hy='Hymnals:BAACLgAFFH8OAAIGAAQJVCYNCgC/AQAGAAQJVCYNCgC/AQAuAAQKfxkAAwYACQkmJe4OANwCAAYACQkmJe4OANwCABwAAgkHGn9UAIQAAAAA.',
Ia='Ianmaris:BAAALgAECgMJAwAAAA==.',
Ic='Icealia:BAAALgAFFAIJAgABLgAFFAUJHAAdAOAHAA==.Icelandite:BAAALgAECgYJBgAAAA==.',
Iv='Ive:BAABLgAECn8jAAQSAAkJpCJ2EQDBAQASAAcJrBt2EQDBAQALAAgJGCI7WgCPAQAYAAIJHBD0JABeAAAAAA==.',
Ja='Jackburton:BAAALgAECgIJAgAAAA==.Jaddie:BAAALgAECgkJEwAAAA==.Jarnunvosk:BAABLgAECn8mAAMeAAkJexasCgA0AgAeAAkJexasCgA0AgAfAAEJbwNxnwAeAAAAAA==.Jasmindinn:BAAALgADCgcJDgAAAA==.Jayber:BAABLgAECn8sAAMgAAgJpRF0IADKAQAgAAgJpRF0IADKAQAIAAEJmQBwngAGAAAAAA==.',
Je='Jezadora:BAAALgADCgEJAQAAAA==.',
Ji='Jimbearlushi:BAAALgAFFAEJAgABLgAFFAgJEwALAM8TAA==.',
Jo='Jolkom:BAAALgAECgMJBgABLgAECgkJGwAXACQcAA==.Jolkret:BAAALgAECgEJAQABLgAECgkJGwAXACQcAA==.',
Ju='Julantis:BAAALgAECgYJBgAAAA==.',
['Jî']='Jîm:BAAALgAECgEJAQAAAA==.',
Ka='Kabball:BAAALgAECgYJDwAAAA==.Kadri:BAAALgAFFAEJAQAAAA==.Kaffee:BAABLgAECn81AAITAAkJ7A9+EwCTAQATAAkJ7A9+EwCTAQAAAA==.Kamasdruid:BAAALgAECggJDAAAAA==.Kamasmage:BAAALgAECgcJBwAAAA==.Kamasmonk:BAAALgAECgYJBwAAAA==.Kamasux:BAAALgADCgYJBwAAAA==.Kandi:BAAALgADCgQJCgAAAA==.Kaviryon:BAAALgAECgEJAwAAAA==.Kaywhy:BAABLgAECn8WAAIIAAkJeRz0JQCcAQAIAAkJeRz0JQCcAQAAAA==.',
Kf='Kfcmanager:BAAALgAECgEJAQAAAA==.',
Ki='Kichack:BAABLgAECn8vAAMKAAkJ+B9GBwDVAgAKAAkJ+B9GBwDVAgAVAAYJDxSoQgBjAQAAAA==.Kimchie:BAAALgAECgEJAgAAAA==.Kitarvie:BAAALgAECgEJAgAAAA==.',
Kj='Kjdh:BAACLgAFFH8TAAIUAAMJUSAWCQAdAQAUAAMJUSAWCQAdAQAuAAQKfysAAhQACQlKIvAJAIoCABQACQlKIvAJAIoCAAAA.',
Kl='Kladuum:BAAALgADCgcJHQAAAA==.',
Kn='Knuckles:BAABLgAECn8VAAIGAAkJTxeMIgDeAQAGAAkJTxeMIgDeAQAAAA==.',
Ko='Kogun:BAAALgAECgQJBAAAAA==.Kowala:BAABLgAECn8cAAIhAAkJvw9HKACPAQAhAAkJvw9HKACPAQAAAA==.Kowpox:BAAALgADCgkJCgAAAA==.Kozalth:BAAALgADCgEJAgAAAA==.',
Kr='Krabi:BAAALgADCgYJCwAAAA==.Kranks:BAAALgAECgEJAQAAAA==.Kreios:BAAALgAECgYJBwAAAA==.Krelo:BAABLgAECn8nAAIaAAkJ0B0pDAD5AgAaAAkJ0B0pDAD5AgAAAA==.',
Kt='Ktom:BAABLgAECn8zAAIMAAkJGiUeAwBAAwAMAAkJGiUeAwBAAwAAAA==.',
Ku='Kurimbory:BAAALgAECgUJBQAAAA==.',
Ky='Kyruan:BAAALgADCgEJAQAAAA==.',
['Ký']='Kýlê:BAABLgAECn8ZAAMNAAgJmwdIUgByAQANAAgJmwdIUgByAQARAAYJ6gLLWQDdAAAAAA==.',
La='Lagolas:BAAALgAECgEJAQAAAA==.Lancelot:BAABLgAECn8VAAIFAAYJ8ArsJAC7AAAFAAYJ8ArsJAC7AAAAAA==.Lanthuil:BAAALgAECgQJBAAAAA==.Lawndown:BAAALgAECgEJAQAAAA==.Lazydruid:BAAALgAECgYJBgAAAA==.',
Le='Leafleaves:BAAALgADCgEJAQAAAA==.',
Li='Lifepooll:BAAALgAECgEJAQABLgAFFAIJAQAOAAAAAA==.Lilyselah:BAAALgADCgYJBwAAAA==.Lindéy:BAAALgAECgYJBgAAAA==.Littlelocky:BAAALgADCgcJEwAAAA==.Liv:BAABLgAECn8UAAIIAAgJtQu6LgBsAQAIAAgJtQu6LgBsAQAAAA==.',
Ll='Llamallab:BAAALgADCgcJBwAAAA==.',
Lo='Lostmyghoul:BAACLgAFFH8GAAIDAAMJTBmBiAD5AAADAAMJTBmBiAD5AAAuAAQKfycAAgMACQkoH+EWAL0CAAMACQkoH+EWAL0CAAAA.Lostwarrior:BAAALgAECgYJCQAAAA==.Louhi:BAAALgAECgUJCgABLgAECgMJCAAOAAAAAA==.',
Lu='Luglug:BAAALgAECgEJAQAAAA==.Lunar:BAACLgAFFH8RAAIhAAQJ0RYNDwAgAQAhAAQJ0RYNDwAgAQAuAAQKfyoAAiEACQnxIbkHANsCACEACQnxIbkHANsCAAAA.Lunasea:BAAALgAECgMJAwAAAA==.',
Ly='Lysol:BAAALgADCgUJBQAAAA==.Lystat:BAAALgAECgYJDgAAAA==.',
Ma='Magicfungus:BAAALgADCgUJCQAAAA==.Magno:BAAALgADCgIJAgAAAA==.Magra:BAABLgAECn8mAAIPAAgJkBWXCADeAQAPAAgJkBWXCADeAQAAAA==.Magêyalook:BAABLgAECn8nAAIPAAgJthmTPwAeAgAPAAgJthmTPwAeAgAAAA==.Mancha:BAAALgAECgEJAgAAAA==.Mangel:BAAALgADCgYJBgAAAA==.Manzz:BAAALgAECgUJCgAAAA==.Marcelline:BAAALgADCgYJEgAAAA==.Mariahscary:BAAALgAFFAIJAgAAAA==.Marisol:BAAALgADCgkJEAAAAA==.Mattob:BAAALgADCgkJDwAAAA==.Maximus:BAAALgADCgkJEAAAAA==.Maznificent:BAAALgAECgUJCAAAAA==.Mazyme:BAAALgADCgQJCQAAAA==.',
Me='Meandmypal:BAACLgAFFH8YAAIbAAkJVh6zAQBLAgAbAAkJVh6zAQBLAgAuAAQKfy4AAhsACQk4JrsAAH4DABsACQk4JrsAAH4DAAAA.Mello:BAABLgAECn86AAIcAAkJxh7wBQCmAgAcAAkJxh7wBQCmAgAAAA==.Mesteris:BAAALgADCgkJFQAAAA==.',
Mi='Mickie:BAAALgAECgEJAQAAAA==.Midiane:BAAALgAECgUJEAAAAA==.Milim:BAAALgAFFAIJAgAAAA==.Mirba:BAABLgAECn8rAAINAAkJbxUULQAoAgANAAkJbxUULQAoAgAAAA==.Missfartmuch:BAAALgADCgEJAQAAAA==.',
Mj='Mjm:BAAALgADCgQJBAAAAA==.',
Mk='Mknight:BAAALgAECgMJAwAAAA==.',
Mo='Mongo:BAABLgAECn8wAAIDAAkJ/R8MEQDkAgADAAkJ/R8MEQDkAgAAAA==.Monochrome:BAAALgAECgIJAgAAAA==.Monsterdeath:BAAALgAECgIJAgAAAA==.Moralinth:BAAALgADCgEJAQAAAA==.Moreicepls:BAABLgAECn8eAAIPAAgJHAyxlgBLAQAPAAgJHAyxlgBLAQAAAA==.Morené:BAAALgAECgQJBgAAAA==.Moxxee:BAAALgADCgkJGwAAAA==.',
Mu='Mushhmelu:BAAALgAECgEJAQAAAA==.',
My='Myiko:BAAALgAECgQJBAAAAA==.Mytharu:BAAALgADCgMJAwAAAA==.',
Na='Nancydru:BAAALgAECgYJBgAAAA==.Nareík:BAACLgAFFH8UAAMUAAQJoQk2GwDIAAAEAAQJCQfJXgDTAAAUAAQJNwg2GwDIAAAuAAQKfyIAAgQACQndEmhVAKMBAAQACQndEmhVAKMBAAAA.',
Ne='Nergal:BAAALgAECgYJCwAAAA==.Neriak:BAAALgAECggJCwAAAA==.Neutrallee:BAAALgAECgEJAQAAAA==.Newa:BAAALgAECgcJEwAAAA==.',
Ni='Nightwater:BAACLgAFFH8cAAIdAAUJ4AeJFwC0AAAdAAUJ4AeJFwC0AAAuAAQKfykABB0ACQmLF6UnABMCAB0ACQmLF6UnABMCACIAAglfCUJEAFMAACEAAQmKCJ+TACwAAAAA.',
Ny='Nystinari:BAAALgADCgIJAgAAAA==.',
['Né']='Nébulien:BAABLgAECn8dAAIjAAgJNx7KCgALAgAjAAgJNx7KCgALAgAAAA==.',
Od='Odile:BAAALgAECgEJAQAAAA==.',
Ok='Okkok:BAABLgAECn8XAAIPAAYJ8hCIwABjAQAPAAYJ8hCIwABjAQAAAA==.',
Ol='Ollee:BAAALgADCgEJAQAAAA==.',
Op='Opp:BAAALgADCgkJDwAAAA==.',
Or='Orchop:BAABLgAECn8YAAIjAAYJgQk1IgDlAAAjAAYJgQk1IgDlAAAAAA==.Orkrist:BAABLgAECn8eAAINAAcJ4BTnHgDfAAANAAcJ4BTnHgDfAAAAAA==.',
Oz='Oz:BAAALgADCgUJBQAAAA==.',
Pa='Paado:BAAALgADCgUJBQAAAA==.Pantryraider:BAAALgAECgkJDwAAAA==.Patriqt:BAAALgAECgEJAQAAAA==.Paulterian:BAAALgAECgcJCQAAAA==.Paymeforpi:BAAALgAECgMJAwAAAA==.',
Pe='Pentagonjr:BAABLgAECn8XAAINAAYJHATdLQCQAAANAAYJHATdLQCQAAAAAA==.',
Ph='Phelaeshio:BAABLgAECn8eAAIDAAkJOxxlJgBqAgADAAkJOxxlJgBqAgAAAA==.',
Po='Poam:BAAALgAECgUJBQAAAA==.Poldalina:BAAALgADCgkJGwAAAA==.Power:BAABLgAECn8UAAIDAAcJQQr3pwAgAQADAAcJQQr3pwAgAQAAAA==.',
Pr='Primevil:BAAALgADCgQJBAAAAA==.Prosthetic:BAAALgAECgEJAQAAAA==.Proverbs:BAABLgAFFH8HAAIPAAQJyBOKKwAgAQAPAAQJyBOKKwAgAQAAAA==.',
Ps='Psalm:BAAALgADCgUJBQAAAA==.',
Pu='Pumplord:BAAALgAECgcJEQAAAA==.Punchyou:BAAALgADCgEJAQAAAA==.',
['På']='Pårts:BAAALgAFFAIJAQAAAA==.',
['Pù']='Pùff:BAAALgAECgUJCQAAAA==.',
Qu='Quazeemoto:BAAALgAECgEJAQAAAA==.',
Ra='Radish:BAAALgADCgkJEAAAAA==.Raeyna:BAAALgAECgIJBAABLgAECgkJIwASAKQiAA==.Raffern:BAAALgAECgMJAwAAAA==.Rainknuckles:BAABLgAECn8mAAIBAAgJVRYCJgDYAQABAAgJVRYCJgDYAQAAAA==.Rakaha:BAAALgADCgUJBQAAAA==.Ratcheet:BAAALgAECgIJAwAAAA==.Rayshano:BAABLgAECn8WAAITAAcJBRr/EgCZAQATAAcJBRr/EgCZAQABLgAFFAgJBAAOAAAAAA==.',
Re='Recklessone:BAAALgAFFAIJBAAAAA==.Renewedfaith:BAAALgAECgEJAQAAAA==.Resia:BAAALgADCgQJAQAAAA==.Revocsid:BAAALgADCgkJFgAAAA==.Rezza:BAAALgADCgEJAQAAAA==.',
Rg='Rgb:BAAALgAFFAIJAwAAAA==.',
Ri='Rikka:BAAALgADCgMJAwAAAA==.Rivalt:BAAALgAECgMJAwAAAA==.',
Ro='Rottingtree:BAABLgAECn8zAAIPAAgJkxn2BgARAgAPAAgJkxn2BgARAgAAAA==.',
Ru='Rudettne:BAAALgADCgEJAQAAAA==.Rustynails:BAABLgAECn85AAIkAAkJGSTNAAAiAwAkAAkJGSTNAAAiAwAAAA==.',
Sa='Saffire:BAAALgADCgcJBwAAAA==.Salina:BAAALgAECgEJAQABLgAECgkJJgAOAAAAAA==.Saly:BAAALgADCgIJAQABLgADCggJDgAOAAAAAA==.Samwitch:BAABLgAECn8WAAISAAUJUgk6CgCCAAASAAUJUgk6CgCCAAAAAA==.Sappaho:BAAALgADCgYJBwAAAA==.Satheirel:BAAALgADCgYJBwAAAA==.Savanti:BAAALgAECgEJAQAAAA==.Sazzul:BAAALgAECgkJEwAAAA==.',
Sc='Scott:BAACLgAFFH8XAAIXAAYJIyA+AwBiAQAXAAYJIyA+AwBiAQAuAAQKfyUAAhcACQlnJNQDABMDABcACQlnJNQDABMDAAAA.Screamor:BAAALgAECgEJAQAAAA==.Screams:BAAALgADCgEJAQAAAA==.Screamz:BAABLgAECn8eAAIUAAYJ6RgvJgBIAQAUAAYJ6RgvJgBIAQAAAA==.Scynx:BAAALgAFFAMJBAAAAA==.',
Se='Seaka:BAACLgAFFH8TAAMdAAQJmRHREgDpAAAdAAQJmRHREgDpAAAhAAMJRQytGgChAAAuAAQKfzEABCEACQmKGNASAD8CACEACQmKGNASAD8CAB0ABwlhFnJAAJABACUAAgnGDqBcAFUAAAAA.Sebas:BAAALgAECgEJAQAAAA==.Sent:BAAALgADCggJDgAAAA==.Serion:BAAALgAECgQJBQABLgAFFAEJAQAOAAAAAA==.Sernix:BAABLgAECn8oAAIaAAgJKxx9FgCWAgAaAAgJKxx9FgCWAgAAAA==.',
Sh='Shadegrim:BAAALgAECgQJBgAAAA==.Shadespawn:BAAALgADCgEJAQAAAA==.Shadowloons:BAAALgAECgEJAQAAAA==.Shaeia:BAACLgAFFH8IAAIMAAMJzxCEEQDcAAAMAAMJzxCEEQDcAAAuAAQKfx8AAgwACQn0HLcNAMYCAAwACQn0HLcNAMYCAAAA.Shamanic:BAAALgAECgIJAgAAAA==.Shamany:BAAALgADCgEJAQAAAA==.Shambat:BAAALgADCgYJBgAAAA==.Shangi:BAAALgADCgMJAgABLgAFFAQJEQATACIhAA==.Shekinah:BAAALgADCgEJAQAAAA==.Shen:BAAALgAECgQJBgAAAA==.Shiftyfans:BAAALgADCgMJAwABLgAECgcJEQAOAAAAAA==.',
Si='Siatrath:BAAALgAECgEJAQABLgAFFAQJEQATACIhAA==.Sivtekeda:BAAALgAECgQJCQAAAA==.',
Sk='Sktibrew:BAACLgAFFH8TAAIJAAYJgSF1BACRAQAJAAYJgSF1BACRAQAuAAQKfxsAAgkACAlTHhMRAI8CAAkACAlTHhMRAI8CAAAA.',
Sl='Slamin:BAAALgAECgYJCwAAAA==.Slash:BAABLgAECn8kAAIUAAkJxRcGFADyAQAUAAkJxRcGFADyAQAAAA==.Slyavane:BAABLgAECn84AAQYAAkJqBX4BgAHAgAYAAkJqBX4BgAHAgASAAcJawdBHADEAAALAAQJWwQE4QCYAAAAAA==.Slyice:BAAALgAECgEJBgAAAA==.',
Sm='Smokess:BAACLgAFFH8QAAMTAAUJmBotBQA3AQATAAUJmBotBQA3AQAFAAMJDxQiFgD7AAAuAAQKfx8AAxMACAnkIRQMAAQCABMACAnKHRQMAAQCAAUACAlAGZZKAAMCAAEuAAUUCAkiABcAvhcA.',
Sn='Snold:BAAALgAECgEJAQAAAA==.Snowwind:BAABLgAECn8jAAIHAAgJhArrMwA2AQAHAAgJhArrMwA2AQAAAA==.',
So='Solthea:BAAALgAECgkJCAAAAA==.Solymar:BAAALgAECgkJBwAAAA==.Sonar:BAABLgAECn8qAAINAAkJ8h9ZGgCHAgANAAkJ8h9ZGgCHAgAAAA==.Sonasai:BAAALgADCgkJGwAAAA==.Sonnybear:BAAALgADCgUJEQAAAA==.Soulhatcher:BAAALgAECgUJEgAAAA==.Soxs:BAABLgAECn8qAAMVAAkJNBo5EACiAgAVAAkJNBo5EACiAgAKAAIJTg+LdABnAAAAAA==.',
Sp='Spectrelok:BAAALgAECgIJAgAAAA==.Spookymoo:BAAALgADCgQJBAAAAA==.',
St='Stabbywabby:BAAALgAECgYJBwAAAA==.Stardris:BAABLgAECn8bAAIEAAgJawKIqAC/AAAEAAgJawKIqAC/AAAAAA==.Stenaris:BAAALgAECgYJBwAAAA==.Stompygnome:BAABLgAECn8UAAMXAAkJwxnZDgD9AQAXAAkJwxnZDgD9AQAcAAEJzA13ewAuAAAAAA==.Strooth:BAAALgADCgQJBAAAAA==.',
Ta='Talavel:BAAALgADCgIJAgAAAA==.Tartanus:BAABLgAECn8tAAIEAAkJXxdmLgANAgAEAAkJXxdmLgANAgAAAA==.Taulogit:BAAALgAECgIJAgAAAA==.Tayzetv:BAAALgAECgMJAwABLgAFFAMJBwAjAGcOAA==.',
Te='Tekki:BAAALgAECgYJBwAAAA==.Tentaclepwn:BAAALgADCgMJAwAAAA==.Teramiah:BAAALgADCgcJFAAAAA==.',
Th='Thanestra:BAAALgAECgkJCAAAAA==.Theadona:BAABLgAECn8pAAIFAAgJXB3MLQBJAgAFAAgJXB3MLQBJAgAAAA==.Thorall:BAAALgADCgkJDwAAAA==.Thylight:BAAALgADCgQJBwAAAA==.',
Ti='Tidalus:BAAALgADCgcJBAAAAA==.Tikcus:BAAALgADCgcJEAAAAA==.Tils:BAAALgADCggJDwAAAA==.Tippy:BAACLgAFFH8eAAMQAAYJmxpTBAC/AQAQAAUJmxpTBAC/AQAmAAIJuQF6RgAeAAAuAAQKfzYABBAACQloITsDALkCABAACQkQITsDALkCAAMAAwkNBskDAXAAACYAAgl1DmJLAGIAAAAA.',
To='Toastedwings:BAAALgADCgcJDwAAAA==.Tombstone:BAAALgAECgYJEgAAAA==.Toowongfoo:BAACLgAFFH8gAAIKAAcJyR1yBQDFAQAKAAcJyR1yBQDFAQAuAAQKfykAAgoACQkuJLwDACQDAAoACQkuJLwDACQDAAAA.',
Tr='Trewer:BAAALgADCgIJAgAAAA==.Trisara:BAABLgAECn81AAIhAAkJrwi7NQBAAQAhAAkJrwi7NQBAAQAAAA==.',
Tu='Tunechi:BAAALgAECgEJAgAAAA==.',
Ty='Tygrana:BAAALgAECgEJAQAAAA==.Tyradora:BAAALgAECgEJAQAAAA==.Tytannia:BAAALgADCgEJAQAAAA==.',
['Tö']='Töteman:BAABLgAECn8qAAIMAAcJlBa6LACSAQAMAAcJlBa6LACSAQAAAA==.',
['Tÿ']='Tÿtann:BAAALgAECgMJAwAAAA==.',
Ug='Uglysham:BAAALgAECgIJAgAAAA==.',
Um='Umbranecros:BAAALgAECgEJBQAAAA==.',
Un='Underdog:BAABLgAECn8kAAMRAAgJ6Bj8AQB9AQARAAgJ6Bj8AQB9AQANAAEJAADjVQEAAAAAAA==.',
Up='Upthere:BAAALgADCgQJBAABLgAECgcJFgAVAGoNAA==.',
Va='Vaerie:BAAALgAECgEJAQAAAA==.Vaern:BAABLgAECn8fAAIiAAgJtB1HCABLAgAiAAgJtB1HCABLAgAAAA==.Vaethorn:BAAALgAFFAgJBAAAAA==.Vagindivin:BAABLgAECn8UAAMWAAkJrxfRAQCkAQAWAAcJSR3RAQCkAQAUAAMJawdjVwBgAAAAAA==.Valrie:BAAALgAECgMJAwAAAA==.Valyteil:BAAALgAFFAEJAQAAAA==.Vastril:BAAALgAECgEJAwAAAA==.',
Ve='Venngance:BAABLgAECn8vAAQQAAkJxSMYBACTAgAQAAkJaB8YBACTAgAmAAYJZiTVFwCdAQADAAYJExSZrgAWAQAAAA==.',
Vi='Vireal:BAAALgADCgIJAgABLgAFFAMJCwADANwUAA==.Virus:BAAALgAECgkJEgAAAA==.Vitner:BAAALgADCgMJAwAAAA==.',
Vo='Voidkity:BAAALgAECgQJBwAAAA==.Voidpriest:BAAALgAECgEJAQAAAA==.Voodoodoo:BAAALgAECgkJAgAAAA==.',
Vy='Vyrlet:BAAALgAECgEJAQAAAA==.',
Wa='Wakax:BAAALgAECgEJAgAAAA==.Walberson:BAAALgADCgYJBgAAAA==.Warfield:BAABLgAECn8hAAMlAAkJ/RMAFAC3AQAlAAkJ/RMAFAC3AQAiAAEJWgMBZAAcAAAAAA==.',
Wf='Wfbot:BAAALgAECgEJAQAAAA==.',
Wh='Whosbondt:BAAALgAECgYJEgAAAA==.',
Wi='Winafred:BAAALgAECgEJAQAAAA==.Wittwicky:BAAALgAECgEJAQAAAA==.',
Wk='Wkeyonly:BAABLgAECn8fAAIEAAkJYRVXYABoAQAEAAkJYRVXYABoAQAAAA==.',
Wo='Woody:BAAALgADCgUJBQAAAA==.Wooter:BAAALgADCgYJDAAAAA==.Worthy:BAAALgAECgkJAwAAAA==.',
Wr='Wrathsome:BAABLgAECn8vAAIdAAkJmRTtJQAfAgAdAAkJmRTtJQAfAgAAAA==.',
Wu='Wunderbilly:BAAALgADCgEJAQAAAA==.',
Wy='Wyterd:BAAALgAECgIJAgAAAA==.',
['Wí']='Wísp:BAAALgAECgEJAQAAAA==.',
Xa='Xaernach:BAAALgAECgEJAQAAAA==.Xalome:BAAALgAECgcJDAAAAA==.',
Xl='Xloon:BAAALgAECgEJAQAAAA==.',
Xy='Xypherus:BAAALgADCgkJDgAAAA==.',
['Xá']='Xándarl:BAAALgAECgMJBAAAAA==.',
Ya='Yakoda:BAAALgADCgUJBQAAAA==.Yaldabaoth:BAAALgAECgcJBQABLgAECgkJEAAOAAAAAA==.',
Ye='Yello:BAAALgAECgYJCwAAAA==.',
Yo='Yobo:BAAALgADCgEJAQAAAA==.',
Za='Zaio:BAAALgAECgYJCQAAAA==.Zarkus:BAAALgAFFAEJAQAAAA==.Zaruknark:BAAALgAECgEJAQAAAA==.',
Ze='Zelphi:BAAALgAECgQJCAAAAA==.Zenha:BAAALgADCgEJAQAAAA==.Zephaadella:BAAALgAECgEJAQAAAA==.Zephyrynn:BAAALgADCgEJAQAAAA==.',
Zh='Zhuzi:BAAALgADCgkJDwAAAA==.',
Zs='Zshmokez:BAACLgAFFH8iAAIXAAgJvhcxBQC9AQAXAAgJvhcxBQC9AQAuAAQKfxsAAhcACQmrH3sFAL8CABcACQmrH3sFAL8CAAAA.',
['Âl']='Âlliyâ:BAAALgAECgEJAgAAAA==.',
['Åy']='Åylå:BAAALgAECgEJAQABLgAECgkJGQACAAMYAA==.',
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
