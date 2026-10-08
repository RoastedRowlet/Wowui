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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','Priest-Holy','Hunter-BeastMastery','Druid-Restoration','DemonHunter-Devourer','Paladin-Protection','Rogue-Assassination','Warrior-Arms','Priest-Shadow','Paladin-Holy','DemonHunter-Havoc','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Druid-Feral','Mage-Arcane','Rogue-Subtlety','Paladin-Retribution','DemonHunter-Vengeance','Mage-Frost','Evoker-Preservation','Evoker-Augmentation','Druid-Guardian',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abberleigh:BAAANQAECgEIAQAAAA==.Abron:BAAANQADCgMIAwAAAA==.',
Ad='Adahma:BAAANQADCgUIBQABNQAECgQICQABAAAAAA==.Adelerock:BAAANQADCgYICgAAAA==.',
Ae='Aerostotle:BAAANQADCgYIBgAAAA==.',
Ag='Aganoth:BAAANQAECgcJEAAAAA==.',
Al='Alaraa:BAAANQADCgUIBwABNQAECgYIGgACANMTAA==.Algonq:BAAANQADCgYIGwABNQAECgQICQABAAAAAA==.Alkamaz:BAAANQAECgYIDQAAAA==.Alkiris:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Alstar:BAAANQAECgcIDgAAAA==.Alynis:BAAANQADCgQIBAAAAA==.',
Am='Amathus:BAABNQAECoEwAAQDAAgKQxYuBQBRAgADAAgKQxYuBQBRAgAEAAYKIg8frwBCAQAFAAEKUwY/egAsAAAAAA==.',
An='Andarial:BAAANQAECgIIAgAAAA==.Andreth:BAAANQAECgEIAQAAAA==.Anoxyn:BAAANQADCgYIBgAAAA==.Anthe:BAAANQADCgUIEAAAAA==.',
Ar='Arcanmaggy:BAAANQADCgcIEAABNQAECgkJIAAEANsPAA==.Arcee:BAAANQADCgQIBgAAAA==.Ares:BAAANQAECgQIBwABNQADCgMJAwABAAAAAA==.Aryxi:BAAANQADCgUJBQABNQADCgMJAwABAAAAAA==.',
As='Asiägo:BAAANQABCgcJCgAAAA==.',
Ba='Baelhal:BAABNQAECoEfAAIGAAgKghHtSQCwAQAGAAgKghHtSQCwAQAAAA==.',
Be='Bearypotter:BAAANQADCgUIBQAAAA==.Benedin:BAAANQADCgcJDAABNQAECggIHAAHABEeAA==.',
Bi='Bigtex:BAAANQAECgQICQAAAA==.Biped:BAAANQAECgYIEgAAAA==.Bishul:BAAANQADCgEIAQAAAA==.',
Bl='Blackdeath:BAAANQAECggICwAAAA==.',
Bo='Bofadees:BAAANQADCggIFAAAAA==.Boloevo:BAAANQADCgUIBQABNQAECgYIDQABAAAAAA==.Bolopal:BAAANQADCgcIDAABNQAECgYIDQABAAAAAA==.Boomstique:BAAANQAECgQICQAAAA==.Boondocka:BAABNQAECoEoAAIIAAkKxBadPgCKAgAIAAkKxBadPgCKAgAAAA==.',
Br='Brewco:BAACNQAFFIEIAAIJAAUK1xmHBAC5AQAJAAUK1xmHBAC5AQA1AAQKgSoAAgkACQqyJSwBAMQDAAkACQqyJSwBAMQDAAAA.Brex:BAAANQAECggIAQAAAA==.Brissennissa:BAABNQAECoEkAAIKAAkKWRt1EwC2AgAKAAkKWRt1EwC2AgAAAA==.Brokkr:BAAANQADCggIEwAAAA==.Bronar:BAAANQADCgMIAwAAAA==.Brutalís:BAAANQAECgYIDQAAAA==.Brèwtality:BAAANQADCgQIBgAAAA==.',
Bt='Btrain:BAAANQAECgMIBQAAAA==.',
Bu='Bubblebae:BAAANQADCggIFgABNQAECgQIBAABAAAAAA==.',
['Bó']='Bóunty:BAAANQAECgUIDgAAAA==.',
Ca='Calypsto:BAAANQAECgIIAgAAAA==.',
Ce='Cenobité:BAAANQAECgQICQAAAA==.',
Ch='Chialing:BAAANQAECgUICwAAAA==.Chichi:BAAANQAECggICAAAAA==.Chickenhead:BAAANQAECgEIAQAAAA==.Chip:BAAANQADCgUIDwAAAA==.Chuckfinley:BAAANQAECgEIAQAAAA==.',
Ci='Cirax:BAAANQAECgQICAAAAA==.',
Cl='Classic:BAAANQADCgUIBwABNQAECgQICQABAAAAAA==.Cleetess:BAAANQADCgQIBAAAAA==.Clenton:BAABNQAECoEeAAILAAcK4QumLgA+AQALAAcK4QumLgA+AQAAAA==.',
Co='Cosplay:BAAANQAECgcICgABNQAECgkJFgAMAKUbAA==.',
Cr='Crichton:BAABNQAECoEsAAIKAAkKTB+QDwDmAgAKAAkKTB+QDwDmAgAAAA==.Crowford:BAAANQAECgMIBgAAAA==.',
Cy='Cyris:BAAANQADCgUICwABNQAECgQICAABAAAAAA==.',
['Cá']='Cástle:BAAANQAECgQIBwAAAA==.',
Da='Daevahna:BAAANQADCggIEQAAAA==.Dak:BAABNQAECoEaAAILAAcKIRu3GwDlAQALAAcKIRu3GwDlAQAAAA==.Dakstorm:BAAANQAECgUIBQABNQAECgcIGgALACEbAA==.Darkmiza:BAABNQAECoEgAAIEAAkK2w9BYQASAgAEAAkK2w9BYQASAgAAAA==.',
De='Deadmangalad:BAAANQADCgYIFQAAAA==.Deedees:BAAANQAECgQJBgAAAA==.Demonhandler:BAAANQADCgUICQAAAA==.Demonikk:BAAANQADCggIAQAAAA==.Deo:BAAANQAECgYIDAABNQAECgkJFgAMAKUbAA==.Depression:BAAANQAECggIBQAAAA==.',
Di='Diioo:BAAANQAECgMIBQAAAA==.Dirtnåp:BAAANQADCgYIFAAAAA==.Diskbänk:BAAANQADCgUIBQAAAA==.',
Dr='Dragontoast:BAAANQAECgEIAQAAAA==.Drama:BAAANQAECgUIBQAAAA==.Druidïan:BAAANQAECgUICAAAAA==.',
Dy='Dynwor:BAAANQADCggICgAAAA==.',
Ea='Easme:BAAANQAECgYIDwAAAA==.',
El='Elaric:BAAANQAECgIIAgAAAA==.',
En='Engi:BAABNQAECoEaAAINAAcKZBX/hQDoAQANAAcKZBX/hQDoAQAAAA==.Enhuna:BAAANQADCgIIAgAAAA==.',
Es='Escaper:BAABNQAECoEaAAICAAgKkhXtKQAWAgACAAgKkhXtKQAWAgAAAA==.',
Ev='Eversteel:BAAANQADCgUIBQABNQAECgQICQABAAAAAA==.',
Ex='Extrema:BAAANQAECgEIAQAAAA==.',
Fh='Fhait:BAAANQADCgYIHwABNQAECgQICQABAAAAAA==.',
Fi='Fionab:BAAANQADCgIIAgAAAA==.',
Fo='Foxfu:BAAANQADCgYICwAAAA==.',
Fu='Fujika:BAAANQADCgQICAAAAA==.',
Ga='Galadan:BAAANQAECgQICQABNQADCgYIFQABAAAAAA==.Garrekton:BAABNQAECoEcAAMHAAgKER5jNQBwAgAHAAgKER5jNQBwAgAOAAEKqAosdgAmAAAAAA==.Gaskelmarg:BAAANQADCgUIEwAAAA==.',
Ge='Gellane:BAAANQAECgMIAwAAAA==.',
Gh='Ghozt:BAAANQADCgUICgABNQAECgQIBwABAAAAAA==.',
Gl='Glory:BAABNQAECoEeAAIPAAkKehgFJQC+AgAPAAkKehgFJQC+AgAAAA==.',
Go='Goldtusk:BAAANQAECgUIDQAAAA==.',
Gr='Graveyard:BAAANQADCgcICwABNQAECgQIBwABAAAAAA==.Grundler:BAAANQAECgEIAQAAAA==.Gryphone:BAAANQADCggIEAAAAA==.',
Ha='Hakmud:BAAANQADCgYIDwAAAA==.Harandee:BAAANQADCgYICwAAAA==.Hasmus:BAAANQADCgUIBQAAAA==.Haufa:BAAANQAECgIIAwAAAA==.',
He='Headstrong:BAAANQADCgcIBwAAAA==.Hettokal:BAAANQADCgQIBAAAAA==.Heximal:BAAANQADCgQIBwABNQAECgkJKAAIAMQWAA==.',
Ho='Hondojoe:BAABNQAECoEbAAMHAAgKrRMNXQDaAQAHAAgKrRMNXQDaAQAOAAQK3w4sRgDfAAAAAA==.Honeydrake:BAAANQAECgUICwAAAA==.Hopewell:BAAANQAECgQICQAAAA==.',
Hu='Hugnsnuggle:BAAANQAECgQICQABNQAECgQICQABAAAAAA==.Huhu:BAAANQAECgcICgAAAA==.Humilitas:BAAANQADCgUICQAAAA==.',
Ib='Ibn:BAAANQAECgYIDgAAAA==.',
Il='Illadus:BAAANQADCgYICwAAAA==.Illidab:BAABNQAECoEiAAIQAAkKLx5xDwAPAwAQAAkKLx5xDwAPAwAAAA==.',
In='Infectus:BAABNQAECoEXAAMRAAgKBgQSnQCeAAARAAgK4QMSnQCeAAACAAgKJQKFfQBtAAAAAA==.',
Ir='Irielle:BAAANQADCgUIFgAAAA==.',
Iv='Ivylyn:BAAANQAECgYIBQAAAA==.',
Ix='Ixiyá:BAABNQAECoEYAAISAAkKjSPYAwCfAwASAAkKjSPYAwCfAwAAAA==.Ixií:BAAANQADCgYIBgAAAA==.Ixì:BAAANQADCgEIAQAAAA==.',
Ja='Jakbenimble:BAAANQADCgcIDQAAAA==.Jakeyprogue:BAAANQAECgMIBAAAAA==.Jakota:BAAANQADCgUIEQAAAA==.Jakskeleton:BAAANQAECgQICgAAAA==.',
Je='Jethroy:BAAANQADCgQIBAAAAA==.',
Jo='Joerollin:BAAANQADCggICQABNQAECggIGwAHAK0TAA==.',
Ju='Judax:BAABNQAECoElAAITAAkKhRAIVQD4AQATAAkKhRAIVQD4AQAAAA==.Justagirl:BAAANQAECgQICQAAAA==.Juti:BAAANQADCgUIDQAAAA==.Juvu:BAAANQADCgQIBAAAAA==.',
Ka='Kadooka:BAABNQAECoEUAAIIAAYKhxZslwCmAQAIAAYKhxZslwCmAQAAAA==.Kahlyn:BAAANQADCgQIBAAAAA==.Kai:BAAANQAECgYIEAAAAA==.Kaldaran:BAAANQADCgcIBwABNQAECgcIDAABAAAAAA==.Kallan:BAAANQADCgQJBAABNQAECgQICQABAAAAAA==.Kaléanor:BAAANQAECgcIDAAAAA==.Karen:BAAANQADCgUIBwAAAA==.Katabell:BAAANQAECgQICQAAAA==.Katira:BAAANQADCgUIDgAAAA==.',
Ke='Keeganw:BAAANQAECgUIDAAAAA==.Keelay:BAAANQAECgcIDwAAAA==.Kelste:BAAANQAECggICwAAAA==.',
Ki='Killaclowns:BAAANQADCgUIEwAAAA==.Kimiko:BAAANQADCgQIBAAAAA==.Kioki:BAAANQADCgEIAQAAAA==.',
Kl='Klitess:BAAANQADCgIIAgAAAA==.',
Ko='Koffcmorbius:BAAANQADCgUIEAAAAA==.Kostian:BAAANQADCgUICQABNQAECgQICQABAAAAAA==.',
Kr='Kraken:BAABNQAECoEeAAIFAAkKmh1gAgAvAwAFAAkKmh1gAgAvAwAAAA==.',
Ku='Kubb:BAAANQAECgQICAAAAA==.',
Kw='Kweh:BAABNQAECoEjAAIUAAkKbR7XBAATAwAUAAkKbR7XBAATAwAAAA==.',
['Kê']='Kêlsen:BAAANQAECgEIAQAAAA==.',
La='Laero:BAAANQADCgYICwABNQAECgQICAABAAAAAA==.Larrissa:BAAANQADCgUIEAAAAA==.Laurlynn:BAAANQADCgYICwAAAA==.',
Le='Lenwe:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Lettuceprey:BAAANQAECgIIAgAAAA==.',
Li='Lierise:BAAANQADCgcIDgAAAA==.Lilindra:BAABNQAECoEaAAQCAAYK0xPuUgAXAQACAAUKqQ7uUgAXAQARAAUKIxUPeAARAQAGAAEKwAqiwQArAAAAAA==.Lillymay:BAAANQAECgEIAQAAAA==.Lilspazz:BAAANQADCgQIBAAAAA==.',
Ll='Lluiz:BAAANQADCgYICgAAAA==.',
Lo='Lockdeath:BAAANQADCgcIDAAAAA==.Logoruk:BAAANQADCgQIBAAAAA==.Loxia:BAAANQAECgIIAgAAAA==.',
Lu='Lucille:BAAANQADCgYIBgAAAA==.Luckett:BAAANQADCgMJAwAAAA==.Lui:BAAANQAECgIIAgAAAA==.Lumi:BAAANQAECgQIBAAAAA==.',
Ma='Maavarra:BAAANQAECgUIBwAAAA==.Madischa:BAAANQADCgYIBgAAAA==.Madshaggy:BAABNQAECoEYAAILAAYKch4jGwDrAQALAAYKch4jGwDrAQAAAA==.Magikern:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.Mahallomi:BAAANQADCgQIBAABNQAECgUIDgABAAAAAA==.Maldreth:BAAANQADCgYIBgAAAA==.Maxlin:BAAANQAECgYICAAAAA==.',
Me='Mehänemäntä:BAAANQADCggIEgAAAA==.Melarii:BAAANQADCgQIBwAAAA==.Merixa:BAAANQAECgQIBAAAAA==.',
Mi='Misstreater:BAAANQAECgEIAQAAAA==.',
Mo='Momentomori:BAAANQAECgYIDAAAAA==.Monbeau:BAABNQAECoEaAAIVAAkKKRViegByAgAVAAkKKRViegByAgAAAA==.Monocerotis:BAAANQAECgcIEwAAAA==.Moosebear:BAAANQADCgYIBgAAAA==.Morishima:BAABNQAECoEsAAMMAAkKQRwiEADfAgAMAAkKChwiEADfAgAWAAcKbRkBGQAAAgAAAA==.',
Mu='Multipàss:BAAANQADCgQIBQAAAA==.',
My='Mydarling:BAACNQAFFIEIAAMPAAUK/BPvEgDxAAAPAAMK6AzvEgDxAAAXAAMKbgeHGQCiAAA1AAQKgSYAAxcACQplGc9dAFQCABcACQplGc9dAFQCAA8ABQrrDeGcACIBAAAA.Mymoon:BAAANQAECgUICwAAAA==.Myris:BAABNQAECoEWAAIRAAgKwhvOLABeAgARAAgKwhvOLABeAgAAAA==.',
['Mî']='Mîsgüïdëð:BAAANQADCggIGgAAAA==.',
Na='Naturalchi:BAAANQAECgcIEwAAAA==.',
Ne='Nefilion:BAAANQAECgEIAQAAAA==.Nefy:BAAANQADCgMIAwAAAA==.Nezin:BAAANQADCgMJAwAAAA==.',
Ni='Niselo:BAAANQADCgUIBQAAAA==.',
No='Nohzul:BAACNQAFFIEIAAITAAQKTxdlDQBYAQATAAQKTxdlDQBYAQA1AAQKgRcAAhMACQqiIVsUADwDABMACQqiIVsUADwDAAAA.Nomik:BAAANQAECgIIAgAAAA==.Nonah:BAAANQADCgYIBwAAAA==.',
Nu='Nullspace:BAAANQAECggIDQAAAA==.',
['Ní']='Níght:BAAANQAECgEIAQAAAA==.',
Or='Orgresh:BAAANQADCggICAAAAA==.Orym:BAAANQAECgQIBwAAAA==.',
Pa='Palacia:BAAANQAECgUIDgAAAA==.Pallythetank:BAAANQAECgUIDgAAAA==.Pappabeary:BAAANQADCgIJAwAAAA==.',
Pe='Peerow:BAAANQADCgUIEQAAAA==.Petrichorica:BAAANQADCgcICgAAAA==.',
Pi='Pintobeans:BAAANQAECgcIEQAAAA==.',
Pr='Primeatheist:BAAANQAECgYICAAAAA==.',
Pu='Puuhceew:BAAANQAECgYIEAAAAA==.',
Ra='Rainbrews:BAAANQAECgEIAQAAAA==.Rainera:BAABNQAECoEcAAIDAAcKgyL6AgC+AgADAAcKgyL6AgC+AgABNQAECgkJKgAYAM4mAA==.Ramanas:BAAANQAECgEIAQAAAA==.Ramrod:BAAANQAECgUJBwAAAA==.Ramstank:BAAANQAECgEIAgAAAA==.Rattles:BAAANQAECgIIAwAAAA==.',
Re='Redgicide:BAAANQAECgYIDwABNQAECgkJKAAIAMQWAA==.Resurgencê:BAAANQAECgQICQAAAA==.',
Ri='Riordan:BAAANQAECgUIDwAAAA==.',
Ro='Rojeton:BAAANQADCgIIAgAAAA==.Rothema:BAAANQAECgQIBwAAAA==.Routh:BAAANQADCgEIAQAAAA==.',
Ru='Rubee:BAAANQADCgMIAwAAAA==.',
Rw='Rwlmaster:BAABNQAECoEaAAIGAAcKoBZ2PADwAQAGAAcKoBZ2PADwAQAAAA==.',
Sa='Sandwiches:BAAANQAECgEIAQAAAA==.',
Sc='Scerra:BAAANQAECgcIEgAAAA==.Scridders:BAAANQAECgcIDgAAAA==.Scridderz:BAAANQAECgEIAQAAAA==.Scriddle:BAAANQAECgQIBAAAAA==.',
Se='Secre:BAAANQADCgQJBAAAAA==.Sellandre:BAAANQADCgYIBgABNQAECgcIDwABAAAAAA==.Seru:BAAANQAECgEIAQAAAA==.',
Sh='Shamarha:BAAANQAECgUICwAAAA==.Shamonbo:BAAANQADCgUIBQABNQAECgkJGgAVACkVAA==.Sharriavolf:BAABNQAECoEcAAMEAAcKZx5WgQC2AQAEAAUKth5WgQC2AQAFAAIKox32RACnAAAAAA==.Shreder:BAAANQADCgIIAgAAAA==.Shuma:BAAANQADCgUIBgAAAA==.',
Si='Simichaelton:BAACNQAFFIEEAAMZAAIKrQu1DgBLAAAZAAEKKxC1DgBLAAAVAAEKLwcgUgBKAAA1AAQKgSsAAxkACQq2F8kWACEBABUACArnEpehAB8CABkABAp+HMkWACEBAAAA.Sinahi:BAAANQAECgEIAQAAAA==.Sinpal:BAAANQAECgcIDAAAAA==.Sinthea:BAAANQAECggIAQAAAA==.',
Sn='Sneakysoul:BAABNQAECoEWAAIMAAkKpRsXEgDLAgAMAAkKpRsXEgDLAgAAAA==.',
So='Solyn:BAAANQAECgUIDwAAAA==.Sonic:BAAANQADCgUIBQAAAA==.',
Sp='Spagooti:BAAANQAECgQICAAAAA==.Spanxya:BAAANQADCgQIBAAAAA==.Spartaaxd:BAAANQAECgcIEwAAAA==.',
St='Stabbard:BAAANQADCgQIBAAAAA==.Stagerrind:BAAANQADCgMIAwAAAA==.Steiner:BAAANQADCgMIAwAAAA==.Stejamarha:BAAANQADCgQIBAAAAA==.',
Su='Sugarseer:BAABNQAECoEWAAISAAgKWRcERQAiAgASAAgKWRcERQAiAgAAAA==.Suka:BAAANQADCgYIGAAAAA==.Suzi:BAAANQAECgYICgAAAA==.',
Sw='Swiftleaf:BAAANQADCggICAAAAA==.',
Sy='Syevoid:BAAANQADCgIIAwAAAA==.Sylentcurse:BAAANQAECgEIAQABNQAECgYIDQABAAAAAA==.Sylentwolvez:BAAANQAECgIIAgAAAA==.Syleta:BAAANQADCgEIAQABNQAECgYIGgACANMTAA==.Sylvarus:BAAANQADCgQIBAAAAA==.',
Ta='Tabraxis:BAAANQADCgEJAQAAAA==.Tagalorc:BAAANQAECgUIEAAAAA==.Takamaki:BAAANQADCgUIDQAAAA==.Tanksbacon:BAAANQAECgUIBQAAAA==.',
Te='Teana:BAAANQAECgcIEAAAAA==.Tempestas:BAAANQADCgUIBgAAAA==.',
Th='Thelegendáry:BAABNQAECoEdAAISAAgK6Bn6OQBPAgASAAgK6Bn6OQBPAgAAAA==.Themigrant:BAAANQABCgMIAwAAAA==.Thorgrimm:BAAANQADCgYIBgAAAA==.Thraine:BAAANQAECgUIBwAAAA==.Threedog:BAAANQADCgIIAgAAAA==.',
Ti='Tione:BAAANQAECgUICwAAAA==.',
To='Toadvoker:BAABNQAECoEaAAMaAAgKBxedFgA2AgAaAAgKBxedFgA2AgAbAAEKxwCqJAARAAAAAA==.Topao:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Totembish:BAAANQAECgYICgAAAA==.',
Tr='Trisstan:BAAANQAECgQICQAAAA==.Trollthrall:BAAANQADCggICAAAAA==.',
Ty='Tyster:BAABNQAECoEbAAIXAAkKbBp7VABvAgAXAAkKbBp7VABvAgAAAA==.',
['Tï']='Tïghtgrïp:BAAANQAECgUIDgAAAA==.',
['Tø']='Tørmented:BAAANQADCgUIBQAAAA==.',
Un='Undol:BAAANQADCgUIDgABNQAECgQICAABAAAAAA==.',
Ve='Velobeef:BAAANQADCgEIAQAAAA==.Veloth:BAACNQAFFIEOAAMZAAYKsRD/AABSAQAZAAQKABT/AABSAQAVAAIKEwpvPwCWAAA1AAQKgTMAAxkACQonJQABAIkDABkACQooJAABAIkDABUACQqJH6g4AAkDAAAA.Verminus:BAAANQAECgcIEQAAAA==.',
Vi='Viggle:BAAANQADCgUICAABNQAECgQICQABAAAAAA==.Viho:BAABNQAECoEcAAIXAAcKHhNcnACzAQAXAAcKHhNcnACzAQAAAA==.Vilekin:BAAANQADCgYIEAAAAA==.Vithaxa:BAAANQAECgIIAwAAAA==.',
Vo='Voidra:BAAANQAECgEIAQAAAA==.',
Vy='Vyinson:BAAANQAECgQIBAABNQAECgUIDQABAAAAAA==.',
Wa='Warloque:BAAANQADCgMJAwAAAA==.',
We='Weechuup:BAAANQAECgMIAwAAAA==.',
Wi='Wifeotusk:BAAANQAECgQIBAAAAA==.Wiggle:BAAANQADCgYICwAAAA==.Willmar:BAAANQAECgQICAAAAA==.Windrun:BAAANQAECgIIAwAAAA==.',
Wo='Wolf:BAABNQAECoEXAAIcAAkKoBHyEwDfAQAcAAkKoBHyEwDfAQAAAA==.Woodtique:BAAANQADCgUIEgAAAA==.',
Wu='Wulthan:BAAANQADCgUJBQAAAA==.',
Xa='Xandercruise:BAAANQAECgEIAQAAAA==.',
Xu='Xuchilbara:BAAANQAECgUIEQAAAA==.',
Ya='Yamato:BAAANQAECgUIBwAAAA==.',
Za='Zaledron:BAAANQAECgYIBgAAAA==.',
Zb='Zbelladonna:BAAANQADCggIEgABNQAECgkJMwACACkiAA==.',
Ze='Zezera:BAAANQAECgEIAQAAAA==.',
Zh='Zhades:BAABNQAECoEzAAMCAAkKKSJgBgBrAwACAAkKKSJgBgBrAwARAAkKxBLqUACmAQAAAA==.Zhort:BAAANQADCgQICAAAAA==.',
Zo='Zodgul:BAAANQADCggICAAAAA==.',
Zu='Zultan:BAABNQAECoEgAAIEAAgK0gw+dwDSAQAEAAgK0gw+dwDSAQAAAA==.',
Zy='Zynblasted:BAAANQADCgQIBAAAAA==.Zynhunter:BAAANQADCgUIBwAAAA==.',
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
