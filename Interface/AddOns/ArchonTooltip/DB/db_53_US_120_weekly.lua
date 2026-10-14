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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','Priest-Holy','Hunter-BeastMastery','DemonHunter-Devourer','Paladin-Protection','Rogue-Assassination','Warrior-Arms','Priest-Shadow','Paladin-Holy','DemonHunter-Havoc','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Druid-Feral','Mage-Arcane','Rogue-Subtlety','Paladin-Retribution','Monk-Windwalker','DemonHunter-Vengeance','Druid-Restoration','Mage-Frost','Evoker-Preservation','Evoker-Augmentation','Druid-Balance','Druid-Guardian',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abberleigh:BAAANQAECgEIAQAAAA==.Abron:BAAANQAECgEIAQAAAA==.',
Ad='Adahma:BAAANQADCgYICwABNQAECgUIDgABAAAAAA==.Adelerock:BAAANQAECgUIBQAAAA==.',
Ae='Aerostotle:BAAANQAECgYIBgAAAA==.',
Ag='Aganoth:BAAANQAECgcJEAAAAA==.',
Al='Alaraa:BAAANQADCgUIBwABNQAECgYIHwACAJoYAA==.Algonq:BAAANQADCgYIIQABNQAECgUIDgABAAAAAA==.Alkamaz:BAAANQAECgYIEwAAAA==.Alkiris:BAAANQADCgEIAQABNQADCggICAABAAAAAA==.Alstar:BAAANQAECggIEQAAAA==.Alynis:BAAANQADCgQIBAAAAA==.',
Am='Amathus:BAABNQAECn83AAQDAAgKpRRjBgBGAgADAAgKpRRjBgBGAgAEAAYKRhBBvwBIAQAFAAEKUwaufwAsAAAAAA==.',
An='Andarial:BAAANQAECgQIBAAAAA==.Andreth:BAAANQAECgEIAQAAAA==.Anoxyn:BAAANQAECgQIBAAAAA==.Anthe:BAAANQADCgUIFAAAAA==.',
Ar='Arcanmaggy:BAAANQADCgcIEAABNQAECgkJIgAEAFoRAA==.Arcee:BAAANQADCgQIBgAAAA==.Ares:BAAANQAECgQICQABNQADCgMJAwABAAAAAA==.Aryxi:BAAANQADCgUJBQABNQADCgMJAwABAAAAAA==.',
As='Asiägo:BAAANQABCgcJCgAAAA==.',
At='Atlas:BAAANQAECgMIAwAAAA==.',
Ba='Baelhal:BAABNQAECn8nAAIGAAgKKxFoTADBAQAGAAgKKxFoTADBAQAAAA==.',
Be='Bearypotter:BAAANQADCgUIBQAAAA==.Benedin:BAAANQADCgcJDAABNQAECggIHwAHABEeAA==.',
Bi='Bigtex:BAAANQAECgUIDgAAAA==.Biped:BAABNQAECn8cAAIDAAcKHxglCAAOAgADAAcKHxglCAAOAgAAAA==.Bishul:BAAANQAECgQIBAAAAA==.',
Bl='Blackdeath:BAAANQAECggIEQAAAA==.Bloodsport:BAAANQADCgIIAgAAAA==.',
Bo='Bofadees:BAAANQADCggIFAAAAA==.Boloevo:BAAANQADCgUIBQABNQAECgYIEgABAAAAAA==.Bolopal:BAAANQAECgIIAgABNQAECgYIEgABAAAAAA==.Boolin:BAAANQADCgQIBAABNQAECgkJJAAFAN4eAA==.Boomstique:BAAANQAECgUIDgAAAA==.Boondocka:BAABNQAECn8oAAIIAAkKzhZfTwB+AgAIAAkKzhZfTwB+AgAAAA==.',
Br='Brex:BAAANQAECggIAQAAAA==.Brissennissa:BAABNQAECn8sAAIJAAkK5hyZEgDUAgAJAAkK5hyZEgDUAgAAAA==.Brokkr:BAAANQADCggIEwAAAA==.Bronar:BAAANQADCgMIAwAAAA==.Brutalís:BAAANQAECgYIEwAAAA==.Brèwtality:BAAANQADCgUICwAAAA==.',
Bt='Btrain:BAAANQAECgMIBwAAAA==.',
Bu='Bubblebae:BAAANQADCggIFgABNQAECgYICgABAAAAAA==.',
['Bó']='Bóunty:BAAANQAECgUIEwAAAA==.',
Ca='Calypsto:BAAANQAECgIIAgAAAA==.',
Ce='Cenobité:BAAANQAECgUIDgAAAA==.',
Ch='Chialing:BAAANQAECgUICwAAAA==.Chichi:BAAANQAECggICQAAAA==.Chickenhead:BAAANQAECgEIAgAAAA==.Chip:BAAANQADCgYIFQAAAA==.Chuckfinley:BAAANQAECgIIAwAAAA==.Chuong:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.',
Ci='Cirax:BAAANQAECgUIDQAAAA==.',
Cl='Classic:BAAANQADCgYIDQABNQAECgUIDgABAAAAAA==.Cleetess:BAAANQADCgQICAAAAA==.Clenton:BAABNQAECn8lAAIKAAcKuA1gNAA+AQAKAAcKuA1gNAA+AQAAAA==.',
Co='Cosplay:BAAANQAECgcICgABNQAECgkJGQALACAbAA==.',
Cr='Crichton:BAABNQAECn8xAAIJAAkKoyOfBwBXAwAJAAkKoyOfBwBXAwAAAA==.Crowford:BAAANQAECgUICwAAAA==.',
Cy='Cyris:BAAANQADCgUICwABNQAECgUIDQABAAAAAA==.',
['Cá']='Cástle:BAAANQAECgQIBwAAAA==.',
Da='Daevahna:BAAANQADCggIEQAAAA==.Dak:BAABNQAECn8iAAIKAAgK8xscEgB9AgAKAAgK8xscEgB9AgAAAA==.Dakstorm:BAAANQAECggIDQABNQAECggIIgAKAPMbAA==.Darkmiza:BAABNQAECn8iAAIEAAkKWhGZbwAMAgAEAAkKWhGZbwAMAgAAAA==.',
De='Deadmangalad:BAAANQADCgYIGwAAAA==.Deedees:BAAANQAECgQICQAAAA==.Demonhandler:BAAANQADCgUICQAAAA==.Demonikk:BAAANQAECgQIBAAAAA==.Deo:BAAANQAECgYIDAABNQAECgkJGQALACAbAA==.Depression:BAAANQAECggIBgAAAA==.',
Di='Diioo:BAAANQAECgMIBQAAAA==.Dirtnåp:BAAANQADCgYIFAAAAA==.Diskbänk:BAAANQADCgUIBQAAAA==.',
Dr='Dragontoast:BAAANQAECgEIAQAAAA==.Drama:BAAANQAECgUIBQAAAA==.Druidïan:BAAANQAECgYIDAAAAA==.',
Dy='Dynwor:BAAANQADCggICgAAAA==.',
Ea='Easme:BAAANQAECgcIEAAAAA==.',
El='Elaric:BAAANQAECgQIBAAAAA==.',
En='Engi:BAABNQAECn8eAAIMAAcK6RG/jwDwAQAMAAcK6RG/jwDwAQAAAA==.Enhuna:BAAANQADCgIIAgAAAA==.',
Es='Escaper:BAABNQAECn8hAAICAAgKwxTTMgAPAgACAAgKwxTTMgAPAgAAAA==.',
Ev='Eversteel:BAAANQADCgUIBQABNQAECgUIDgABAAAAAA==.',
Ex='Extrema:BAAANQAECgEIAQAAAA==.',
Fe='Felesha:BAAANQADCgQIBAAAAA==.',
Fh='Fhait:BAAANQADCgYIIwABNQAECgUIDgABAAAAAA==.',
Fi='Fionab:BAAANQADCgIIAgAAAA==.',
Fo='Foxfu:BAAANQADCgYICwAAAA==.',
Fu='Fujika:BAAANQADCgQICAAAAA==.',
Ga='Galadan:BAAANQAECgUIDgABNQADCgYIGwABAAAAAA==.Garrekton:BAABNQAECn8fAAMHAAgKER4QPgBvAgAHAAgKER4QPgBvAgANAAEKAADggwAjAAAAAA==.Gaskelmarg:BAAANQADCgUIFwAAAA==.',
Ge='Gellane:BAAANQAECgMIAwAAAA==.',
Gh='Ghozt:BAAANQADCgUICgABNQAECgQIBwABAAAAAA==.',
Gl='Glory:BAABNQAECn8lAAIOAAkKfRifLQCuAgAOAAkKfRifLQCuAgAAAA==.',
Go='Goldtusk:BAAANQAECgUIDQAAAA==.',
Gr='Graveyard:BAAANQADCgcICwABNQAECgQIBwABAAAAAA==.Grundler:BAAANQAECgEIAQAAAA==.Gryphone:BAAANQADCggIEAAAAA==.',
Ha='Hakmud:BAAANQADCgYIFQAAAA==.Harandee:BAAANQADCgYICwAAAA==.Hasmus:BAAANQADCgUIBQAAAA==.Haufa:BAAANQAECgIIAwAAAA==.',
He='Headstrong:BAAANQADCgcIBwAAAA==.Hettokal:BAAANQADCgQIBAAAAA==.Heximal:BAAANQADCgQIBwABNQAECgkJKAAIAM4WAA==.',
Ho='Hondojoe:BAEBNQAECn8bAAMHAAgKrRMxbADVAQAHAAgKrRMxbADVAQANAAQKpg3FTQDZAAAAAA==.Honeydrake:BAAANQAECggIEQAAAA==.Hopewell:BAAANQAECgUIDgAAAA==.',
Hu='Hugnsnuggle:BAAANQAECgUIDgABNQAECgUIDgABAAAAAA==.Huhu:BAAANQAECgcICgAAAA==.Humilitas:BAAANQADCgUICQAAAA==.',
Ib='Ibn:BAABNQAECn8YAAIMAAcKwgUe1QBAAQAMAAcKwgUe1QBAAQAAAA==.',
Il='Illadus:BAAANQADCgYICwAAAA==.Illidab:BAABNQAECn8iAAIPAAkKZx0gFAD5AgAPAAkKZx0gFAD5AgAAAA==.',
In='Infectus:BAABNQAECn8XAAMQAAgKdwOcqgCcAAAQAAgKTQOcqgCcAAACAAgKcwHNkQBsAAAAAA==.',
Ir='Irielle:BAAANQADCgUIGwAAAA==.',
Iv='Ivylyn:BAAANQAECgUICQAAAA==.',
Ix='Ixiyá:BAABNQAECn8ZAAIRAAkKjSMHBQCfAwARAAkKjSMHBQCfAwAAAA==.Ixií:BAAANQADCgYIBgAAAA==.Ixì:BAAANQADCgEIAQAAAA==.',
Ja='Jakbenimble:BAAANQADCgcIDQAAAA==.Jakeyprogue:BAAANQAECgMIBAAAAA==.Jakota:BAAANQADCgUIEQAAAA==.Jakskeleton:BAAANQAECgQIDgAAAA==.',
Je='Jeamica:BAAANQADCggICAAAAA==.Jethroy:BAAANQADCgQIBAAAAA==.',
Jo='Joerollin:BAEANQADCggICQABNQAECggIGwAHAK0TAA==.',
Ju='Judax:BAABNQAECn8tAAISAAkKXRXvTgA5AgASAAkKXRXvTgA5AgAAAA==.Justagirl:BAAANQAECgUIDgAAAA==.Juti:BAAANQADCgUIEQAAAA==.Juvu:BAAANQADCgQIBAAAAA==.',
Ka='Kadooka:BAABNQAECn8VAAIIAAcKEReqiwDvAQAIAAcKEReqiwDvAQAAAA==.Kahlyn:BAAANQADCgQIBAAAAA==.Kai:BAAANQAECgYIEAAAAA==.Kaldaran:BAAANQADCgcIBwABNQAFFAEIAQABAAAAAA==.Kallan:BAAANQADCgQJBAABNQAECgUIDgABAAAAAA==.Kaléanor:BAAANQAFFAEIAQAAAA==.Karen:BAAANQADCgUIBwAAAA==.Katabell:BAAANQAECgUIDgAAAA==.Katira:BAAANQADCgUIDgAAAA==.',
Ke='Keeganw:BAAANQAECgUIDAAAAA==.Keelay:BAAANQAECgcIDwAAAA==.Kelste:BAAANQAECggIDQAAAA==.',
Ki='Killaclowns:BAAANQADCgUIEwAAAA==.Kimiko:BAAANQADCgUICQAAAA==.Kioki:BAAANQADCgYICAAAAA==.',
Kl='Klitess:BAAANQADCgIIAgAAAA==.',
Ko='Koffcmorbius:BAAANQADCgUIFAAAAA==.Kostian:BAAANQADCgUICQABNQAECgUIDgABAAAAAA==.',
Kr='Kraken:BAABNQAECn8kAAIFAAkK3h6kAQBpAwAFAAkK3h6kAQBpAwAAAA==.',
Ku='Kubb:BAAANQAECgUIDQAAAA==.',
Kw='Kweh:BAACNQAFFH8GAAITAAMKOBQ3AgD8AAATAAMKOBQ3AgD8AAA1AAQKfyYAAhMACQpmHgUGAA8DABMACQpmHgUGAA8DAAAA.',
['Kê']='Kêlsen:BAAANQAECgEIAQAAAA==.',
La='Laero:BAAANQADCgYICwABNQAECgUIDQABAAAAAA==.Larrissa:BAAANQADCgUIFAAAAA==.Laurlynn:BAAANQADCgYICwAAAA==.',
Le='Lenwe:BAAANQAECgQIBQAAAA==.Lettuceprey:BAAANQAECgMIBAAAAA==.',
Li='Lierise:BAAANQADCgcIDgAAAA==.Lilindra:BAABNQAECn8fAAQCAAYKmhjsWwAwAQACAAUK7hTsWwAwAQAQAAUKbhdxgAAYAQAGAAEKAAAs0AArAAAAAA==.Lillymay:BAAANQAECgEIAQAAAA==.Lilspazz:BAAANQADCgQIBAAAAA==.',
Ll='Lluiz:BAAANQADCgYICgAAAA==.',
Lo='Lockdeath:BAAANQADCgcIDAAAAA==.Logoruk:BAAANQADCgQIBAAAAA==.Lorelleya:BAAANQADCgEIAQAAAA==.Loxia:BAAANQAECgQIBAAAAA==.',
Lu='Lucille:BAAANQADCgYIBgAAAA==.Luckett:BAAANQADCgMJAwAAAA==.Lui:BAAANQAECgIIAgAAAA==.Lumi:BAAANQAECgUIDAAAAA==.',
Ma='Maavarra:BAAANQAECgUICwAAAA==.Madischa:BAAANQADCgYIBgAAAA==.Madshaggy:BAABNQAECn8fAAIKAAcKQR1QGQAoAgAKAAcKQR1QGQAoAgAAAA==.Magicdance:BAAANQAECgUIBQAAAA==.Magikern:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.Mahallomi:BAAANQADCgQIBAABNQAECgUIDgABAAAAAA==.Maldreth:BAAANQADCgYIBgAAAA==.Maxlin:BAAANQAECgYIDQAAAA==.',
Me='Mehänemäntä:BAAANQADCggIEgAAAA==.Melarii:BAAANQADCgYIDQAAAA==.Merixa:BAAANQAECgQIBQAAAA==.',
Mi='Misstreater:BAAANQAECgUIBgAAAA==.',
Mo='Momentomori:BAAANQAECgYIEgAAAA==.Monbeau:BAABNQAECn8fAAIUAAkKnRbBYgC5AgAUAAkKnRbBYgC5AgAAAA==.Monocerotis:BAABNQAECn8dAAICAAkKWQ/YNwDxAQACAAkKWQ/YNwDxAQAAAA==.Moosebear:BAAANQADCgYIBgAAAA==.Morishima:BAABNQAECn81AAMLAAkKrRsPEwDgAgALAAkKpBsPEwDgAgAVAAcKsheUGwD2AQAAAA==.',
Mu='Multipàss:BAAANQADCgQIBQAAAA==.',
My='Mydarling:BAACNQAFFH8IAAMOAAUK/BPgFgDtAAAOAAMK6AzgFgDtAAAWAAMK0wM3IACdAAA1AAQKfykAAxYACQr6GEd3ADoCABYACQr6GEd3ADoCAA4ABQrrDROyABYBAAAA.Mymoon:BAAANQAECgUIDAAAAA==.Myris:BAABNQAECn8bAAIQAAgKFBw2LQB8AgAQAAgKFBw2LQB8AgAAAA==.',
['Mî']='Mîsgüïdëð:BAAANQADCggIIAAAAA==.',
Na='Naturalchi:BAABNQAECn8bAAIXAAcK1SE+FQCmAgAXAAcK1SE+FQCmAgAAAA==.',
Nb='Nbi:BAAANQAECgEIAQAAAA==.',
Ne='Nefilion:BAAANQAECgEIAQAAAA==.Nefy:BAAANQADCgMIAwAAAA==.Nezin:BAAANQADCgMJAwAAAA==.',
Ni='Niselo:BAAANQADCgUIBQAAAA==.',
No='Nohzul:BAACNQAFFH8MAAISAAUKFR1bCwCxAQASAAUKFR1bCwCxAQA1AAQKfxoAAhIACQo6IxgVAEkDABIACQo6IxgVAEkDAAAA.Nomik:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.Nonah:BAAANQADCgYIBwAAAA==.',
Nu='Nullspace:BAAANQAECggIEwAAAA==.',
['Ní']='Níght:BAAANQAECgEIAQAAAA==.',
Or='Orgresh:BAAANQADCggICAAAAA==.Orym:BAAANQAECgQICgAAAA==.',
Pa='Palacia:BAABNQAECn8XAAMKAAcKoRDYMABUAQAKAAYK9xPYMABUAQAWAAQKqAPFXQGBAAAAAA==.Pallythetank:BAAANQAECgUIDgAAAA==.Pappabeary:BAAANQADCgIIAwAAAA==.',
Pe='Peerow:BAAANQADCgUIFgAAAA==.Petrichorica:BAAANQADCgcICgAAAA==.',
Pi='Pintobeans:BAAANQAECgcIEQAAAA==.',
Pr='Primeatheist:BAAANQAECgcICgAAAA==.',
Pu='Puuhceew:BAAANQAECgcIEwAAAA==.',
Ra='Rainbrews:BAAANQAECgEIAQAAAA==.Rainera:BAABNQAECn8gAAIDAAcKMiJ4AwC+AgADAAcKMiJ4AwC+AgABNQAFFAMIBwAYAMwhAA==.Ramanas:BAAANQAECgMIAwAAAA==.Ramrod:BAAANQAECgUJBwAAAA==.Ramstank:BAAANQAECgMIBQAAAA==.Rattles:BAAANQAECgIIAwAAAA==.',
Re='Redgicide:BAAANQAECgYIDwABNQAECgkJKAAIAM4WAA==.Releafme:BAACNQAFFH8MAAIZAAUKUBy8BQCzAQAZAAUKUBy8BQCzAQA1AAQKfywAAhkACQqyJZgBALwDABkACQqyJZgBALwDAAAA.Resurgencê:BAAANQAECgUIDgAAAA==.',
Ri='Riordan:BAABNQAECn8VAAIWAAYKJwzy4gBPAQAWAAYKJwzy4gBPAQAAAA==.',
Ro='Rojeton:BAAANQADCgIIAgAAAA==.Rothema:BAAANQAECgUIDAAAAA==.Routh:BAAANQAECgEIAQAAAA==.',
Ru='Rubee:BAAANQADCgMIAwAAAA==.',
Rw='Rwlmaster:BAABNQAECn8eAAIGAAcKLxMLRADoAQAGAAcKLxMLRADoAQAAAA==.',
Sa='Sandwiches:BAAANQAECgEIAQAAAA==.',
Sc='Scerra:BAABNQAECn8eAAMCAAgKtReYKwA8AgACAAgKtReYKwA8AgAQAAMKogJZvwBoAAAAAA==.Scridders:BAAANQAECgcIDgAAAA==.Scridderz:BAAANQAECgEIAQAAAA==.Scriddle:BAAANQAECgQIBAAAAA==.',
Se='Secre:BAAANQADCgQJBAAAAA==.Sellandre:BAAANQADCgYIBgABNQAECgcIDwABAAAAAA==.Seru:BAAANQAECgEIAQAAAA==.',
Sh='Shamarha:BAAANQAECgUIEAAAAA==.Shamonbo:BAAANQADCgUIBQABNQAECgkJHwAUAJ0WAA==.Sharriavolf:BAABNQAECn8cAAMEAAcKPR1omACkAQAEAAUK+RxomACkAQAFAAIKox3fSACkAAAAAA==.Shreder:BAAANQADCgIIAgAAAA==.Shuma:BAAANQADCgUIBgAAAA==.',
Si='Simichaelton:BAECNQAFFH8GAAMaAAIKTBFuEgBJAAAUAAEKbRKyVgBQAAAaAAEKKxBuEgBJAAA1AAQKfy8AAxoACQp0GbcaABoBABQACApUE3quACQCABoABAp+HLcaABoBAAAA.Sinahi:BAAANQAECgEIAQAAAA==.Sinpal:BAAANQAECgcIDAAAAA==.Sinthea:BAAANQAECggIAgAAAA==.',
Sn='Sneakysoul:BAABNQAECn8ZAAILAAkKIBvUFwC5AgALAAkKIBvUFwC5AgAAAA==.',
So='Solyn:BAAANQAECgYIEQAAAA==.Sonic:BAAANQADCgUIBQAAAA==.',
Sp='Spagooti:BAAANQAECgUICQAAAA==.Spanxya:BAAANQADCgQIBAAAAA==.Spartaaxd:BAAANQAECgcIEwAAAA==.',
St='Stabbard:BAAANQADCgQIBAAAAA==.Stagerrind:BAAANQADCgMIAwAAAA==.Steiner:BAAANQADCgMIAwAAAA==.Stejamarha:BAAANQADCgQIBAAAAA==.',
Su='Sugarseer:BAABNQAECn8WAAIRAAgKWRdxUgAZAgARAAgKWRdxUgAZAgAAAA==.Suka:BAAANQADCgYIHgAAAA==.Suzi:BAAANQAECgUICwAAAA==.',
Sw='Swiftleaf:BAAANQADCggICAAAAA==.',
Sy='Syevoid:BAAANQADCgIIAwAAAA==.Sylentcurse:BAAANQAECgUIBgABNQAECgYIEwABAAAAAA==.Sylentstorm:BAAANQAECgEIAQABNQAECgYIEwABAAAAAA==.Sylentwolvez:BAAANQAECgUIBgAAAA==.Syleta:BAAANQADCgEIAQABNQAECgYIHwACAJoYAA==.Sylvarus:BAAANQADCgQIBAAAAA==.',
Ta='Tabraxis:BAAANQADCgEJAQAAAA==.Tagalorc:BAABNQAECn8ZAAIUAAcK6ApaAAGKAQAUAAcK6ApaAAGKAQAAAA==.Takamaki:BAAANQADCgUIEgAAAA==.Tanksbacon:BAAANQAECgUIBQAAAA==.',
Te='Teana:BAAANQAECgcIEAAAAA==.Tempestas:BAAANQADCgUIBgAAAA==.',
Th='Thelegendáry:BAABNQAECn8jAAIRAAgKQhzjNgCBAgARAAgKQhzjNgCBAgAAAA==.Themigrant:BAAANQABCgMIAwAAAA==.Thorgrimm:BAAANQADCgYIBgAAAA==.Thraine:BAAANQAECgUICQAAAA==.Threedog:BAAANQADCgIIAgAAAA==.',
Ti='Tione:BAAANQAECgUIEAAAAA==.',
To='Toadvoker:BAABNQAECn8dAAMbAAkK5hXeEwBvAgAbAAkK5hXeEwBvAgAcAAEKxwDxKAARAAAAAA==.Topao:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.Toriee:BAAANQABCgIIBAAAAA==.Totembish:BAAANQAECgYIEAAAAA==.',
Tr='Trisstan:BAAANQAECgUIDgAAAA==.Trollthrall:BAAANQADCggICwAAAA==.',
Ty='Tyster:BAABNQAECn8eAAIWAAkKHx3TXQB7AgAWAAkKHx3TXQB7AgAAAA==.',
['Tï']='Tïghtgrïp:BAABNQAECn8aAAQCAAkK7xdCJABrAgACAAkKpBdCJABrAgAGAAYKGxWFXQB5AQAQAAIK2gifzABPAAAAAA==.',
['Tø']='Tørmented:BAAANQADCgUIBQAAAA==.',
Un='Undol:BAAANQADCgYIFAABNQAECgUIDQABAAAAAA==.',
Va='Vandress:BAAANQADCgMIAQABNQADCggICAABAAAAAA==.',
Ve='Velobeef:BAAANQADCgEIAQAAAA==.Veloth:BAACNQAFFH8SAAMaAAYKQhT+AACPAQAaAAUKQhT+AACPAQAUAAMKbA3lOADcAAA1AAQKfzYAAxoACQoKJZEBAHQDABoACQoPJJEBAHQDABQACQqYHohGAPYCAAAA.Verminus:BAABNQAECn8ZAAQZAAgKSgx1NQBrAQAZAAcKIAx1NQBrAQAdAAYKCgaKcgD8AAATAAEK6gZ3RgApAAAAAA==.',
Vi='Viggle:BAAANQADCgUICAABNQAECgUIDgABAAAAAA==.Viho:BAABNQAECn8iAAIWAAgKvhPjlwDvAQAWAAgKvhPjlwDvAQAAAA==.Vilekin:BAAANQAECgUIBQAAAA==.Vithaxa:BAAANQAECgIIBAAAAA==.',
Vo='Voidra:BAAANQAECgEIAQAAAA==.',
Vy='Vyinson:BAAANQAECgQIBAABNQAECgUIDQABAAAAAA==.',
Wa='Warloque:BAAANQADCgMJAwAAAA==.',
We='Weechuup:BAAANQAECgMIAwAAAA==.',
Wi='Wifeotusk:BAAANQAECgQIBAAAAA==.Wiggle:BAAANQADCgYICwAAAA==.Willmar:BAAANQAECgQIDAAAAA==.Window:BAAANQADCggICAABNQAECgQIBwABAAAAAA==.Windrun:BAAANQAECgQIBgAAAA==.',
Wo='Wolf:BAABNQAECn8YAAIeAAkKVRIsGQDbAQAeAAkKVRIsGQDbAQAAAA==.Woodtique:BAAANQADCgUIFgAAAA==.',
Wu='Wulthan:BAAANQADCgYICwAAAA==.',
Xa='Xandercruise:BAAANQAECgEIAQAAAA==.',
Xu='Xuchilbara:BAAANQAECgUIEQAAAA==.',
Ya='Yamato:BAAANQAECgUICQAAAA==.',
Za='Zaledron:BAAANQAECgcICgAAAA==.',
Zb='Zbelladonna:BAAANQADCggIEgABNQAECgkJPAACAPoiAA==.',
Ze='Zezera:BAAANQAECgEIAQAAAA==.',
Zh='Zhades:BAABNQAECn88AAMCAAkK+iJxBQCHAwACAAkK+iJxBQCHAwAQAAkKOBFSWgCjAQAAAA==.Zhort:BAAANQAECgIIAgAAAA==.',
Zi='Zioki:BAAANQADCggICAAAAA==.',
Zo='Zodgul:BAAANQADCggICAAAAA==.Zomby:BAEANQADCggICAABNQAFFAIIBgAaAEwRAA==.',
Zu='Zultan:BAABNQAECn8oAAIEAAgKswvYiQDJAQAEAAgKswvYiQDJAQAAAA==.',
Zy='Zynblasted:BAAANQADCgQIBAAAAA==.Zynhunter:BAAANQADCgUIDwAAAA==.',
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
