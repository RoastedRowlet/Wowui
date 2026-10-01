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

local lookup = {'Unknown-Unknown','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','Hunter-BeastMastery','Druid-Restoration','DemonHunter-Devourer','Paladin-Protection','Paladin-Holy','DemonHunter-Havoc','Shaman-Restoration','Shaman-Elemental','Druid-Feral','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Paladin-Retribution','DemonHunter-Vengeance','Mage-Frost','Evoker-Preservation','Evoker-Augmentation','Druid-Guardian','DeathKnight-Frost','DeathKnight-Unholy',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abberleigh:BAAANQADCggIGAAAAA==.Abron:BAAANQADCgMIAwAAAA==.',
Ad='Adelerock:BAAANQADCgYIBgAAAA==.',
Ae='Aerostotle:BAAANQADCgYIBgAAAA==.',
Ag='Aganoth:BAAANQAECgcJEAAAAA==.',
Al='Alaraa:BAAANQADCgUIBwABNQAECgQIEAABAAAAAA==.Algonq:BAAANQADCgYIFgABNQAECgMIBQABAAAAAA==.Alkamaz:BAAANQAECgYIDQAAAA==.Alstar:BAAANQAECgcJDgAAAA==.Alynis:BAAANQADCgQIBAAAAA==.',
Am='Amathus:BAABNQAECoEjAAQCAAgK9xP8BAA6AgACAAgK0xP8BAA6AgADAAYKIg/OlwBGAQAEAAEKUwalcgAuAAAAAA==.',
An='Andarial:BAAANQAECgEIAQAAAA==.Andreth:BAAANQADCggIGAAAAA==.Anoxyn:BAAANQADCgYIBgAAAA==.Anthe:BAAANQADCgUIEAAAAA==.',
Ar='Arcanmaggy:BAAANQADCgcIEAABNQAECggIHQADABgQAA==.Arcee:BAAANQADCgQIBgAAAA==.Ares:BAAANQAECgMIBQABNQADCgMJAwABAAAAAA==.Aryxi:BAAANQADCgUJBQABNQADCgMJAwABAAAAAA==.',
As='Asiägo:BAAANQABCgcJCgAAAA==.',
Ba='Baelhal:BAABNQAECoEdAAIFAAgK/xAMQgCyAQAFAAgK/xAMQgCyAQAAAA==.',
Be='Bearypotter:BAAANQADCgUIBQAAAA==.Benedin:BAAANQADCgcJDAABNQAECgcIEgABAAAAAA==.',
Bi='Bigtex:BAAANQAECgMIBQAAAA==.Biped:BAAANQAECgUIDAAAAA==.Bishul:BAAANQADCgEIAQAAAA==.',
Bl='Blackdeath:BAAANQAECgQIBQAAAA==.',
Bo='Bofadees:BAAANQADCggIFAAAAA==.Boloevo:BAAANQADCgUIBQAAAA==.Bolopal:BAAANQADCgcIDAAAAA==.Boomstique:BAAANQAECgMIBQAAAA==.Boondocka:BAABNQAECoEnAAIGAAkKxBZKLgCiAgAGAAkKxBZKLgCiAgAAAA==.',
Br='Brewco:BAABNQAECoEnAAIHAAkKdCRvAQCyAwAHAAkKdCRvAQCyAwAAAA==.Brissennissa:BAABNQAECoEgAAIIAAkKWRtsEADIAgAIAAkKWRtsEADIAgAAAA==.Brokkr:BAAANQADCggIEwAAAA==.Bronar:BAAANQADCgMIAwAAAA==.Brutalís:BAAANQAECgUICwAAAA==.Brèwtality:BAAANQADCgMIAwAAAA==.',
Bt='Btrain:BAAANQAECgIIAgAAAA==.',
Bu='Bubblebae:BAAANQADCggIDwABNQAECgQIBAABAAAAAA==.',
['Bó']='Bóunty:BAAANQAECgUIDgAAAA==.',
Ce='Cenobité:BAAANQAECgMIBQAAAA==.',
Ch='Chialing:BAAANQAECgUIBwAAAA==.Chichi:BAAANQAECggICAAAAA==.Chickenhead:BAAANQAECgEIAQAAAA==.Chip:BAAANQADCgUICgAAAA==.Chuckfinley:BAAANQAECgEIAQAAAA==.',
Ci='Cirax:BAAANQAECgMIBAAAAA==.',
Cl='Classic:BAAANQADCgUIBwABNQAECgMIBQABAAAAAA==.Cleetess:BAAANQADCgQIBAAAAA==.Clenton:BAABNQAECoEXAAIJAAcKZQvzJwBDAQAJAAcKZQvzJwBDAQAAAA==.',
Co='Cosplay:BAAANQAECgYIBgABNQAECggIEAABAAAAAA==.',
Cr='Crichton:BAABNQAECoEmAAIIAAkKBh+3DAD5AgAIAAkKBh+3DAD5AgAAAA==.Crowford:BAAANQAECgMIBgAAAA==.',
Cy='Cyris:BAAANQADCgUICwABNQAECgMIBQABAAAAAA==.',
['Cá']='Cástle:BAAANQAECgQIBwAAAA==.',
Da='Daevahna:BAAANQADCgYICwAAAA==.Dak:BAABNQAECoEaAAIJAAcKIRvKFQD9AQAJAAcKIRvKFQD9AQAAAA==.Dakstorm:BAAANQAECgUIBQABNQAECgcIGgAJACEbAA==.Darkmiza:BAABNQAECoEdAAIDAAgKGBAAYgDiAQADAAgKGBAAYgDiAQAAAA==.',
De='Deadmangalad:BAAANQADCgYIEAAAAA==.Deedees:BAAANQAECgQJBgAAAA==.Demonhandler:BAAANQADCgUICQAAAA==.Demonikk:BAAANQADCggIAQAAAA==.Deo:BAAANQAECgYIDAABNQAECggIEAABAAAAAA==.Depression:BAAANQAECggIBAAAAA==.',
Di='Diioo:BAAANQAECgMIBQAAAA==.Dirtnåp:BAAANQADCgYIDwAAAA==.Diskbänk:BAAANQADCgUIBQAAAA==.',
Dr='Dragontoast:BAAANQADCggIGAAAAA==.Druidïan:BAAANQAECgMIAwAAAA==.',
Dy='Dynwor:BAAANQADCggICgAAAA==.',
Ea='Easme:BAAANQAECgUJCQAAAA==.',
El='Elaric:BAAANQAECgEIAQAAAA==.',
En='Engi:BAAANQAECgYIEQAAAA==.Enhuna:BAAANQADCgIIAgAAAA==.',
Es='Escaper:BAAANQAECgYIDwAAAA==.',
Ex='Extrema:BAAANQADCggIGAAAAA==.',
Fh='Fhait:BAAANQADCgYIGgABNQAECgMIBQABAAAAAA==.',
Fi='Fionab:BAAANQADCgIIAgAAAA==.',
Fo='Foxfu:BAAANQADCgYICwAAAA==.',
Fu='Fujika:BAAANQADCgQIBAAAAA==.',
Ga='Galadan:BAAANQAECgMIBQABNQADCgYIEAABAAAAAA==.Garrekton:BAAANQAECgcIEgAAAA==.Gaskelmarg:BAAANQADCgUIDgAAAA==.',
Ge='Gellane:BAAANQAECgMIAwAAAA==.',
Gh='Ghozt:BAAANQADCgUICgABNQAECgQIBwABAAAAAA==.',
Gl='Glory:BAABNQAECoEcAAIKAAcKFB10NQBSAgAKAAcKFB10NQBSAgAAAA==.',
Go='Goldtusk:BAAANQAECgUIDQAAAA==.',
Gr='Graveyard:BAAANQADCgcICwABNQAECgQIBwABAAAAAA==.Grundler:BAAANQADCgYICQAAAA==.Gryphone:BAAANQADCggIEAAAAA==.',
Ha='Hakmud:BAAANQADCgYICgAAAA==.Harandee:BAAANQADCgYICwAAAA==.Hasmus:BAAANQADCgUIBQAAAA==.Haufa:BAAANQAECgIIAwAAAA==.',
He='Headstrong:BAAANQADCgcIBwAAAA==.Hettokal:BAAANQADCgQIBAAAAA==.Heximal:BAAANQADCgQIBwABNQAECgkJJwAGAMQWAA==.',
Ho='Hondojoe:BAAANQAECgcIEQAAAA==.Honeydrake:BAAANQAECgQICQAAAA==.Hopewell:BAAANQAECgMIBQAAAA==.',
Hu='Hugnsnuggle:BAAANQAECgMIBQABNQAECgMIBQABAAAAAA==.Huhu:BAAANQAECgcICgAAAA==.Humilitas:BAAANQADCgUICQAAAA==.',
Ib='Ibn:BAAANQAECgUIDAAAAA==.',
Il='Illadus:BAAANQADCgYICwAAAA==.Illidab:BAABNQAECoEcAAILAAgK/BxlGQCKAgALAAgK/BxlGQCKAgAAAA==.',
In='Infectus:BAAANQAECggICAAAAA==.',
Ir='Irielle:BAAANQADCgUIEwAAAA==.',
Iv='Ivylyn:BAAANQAECgUIBQAAAA==.',
Ix='Ixiyá:BAABNQAECoEYAAIMAAkKjSNNAgCxAwAMAAkKjSNNAgCxAwAAAA==.Ixií:BAAANQADCgYIBgAAAA==.Ixì:BAAANQADCgEIAQAAAA==.',
Ja='Jakbenimble:BAAANQADCgcIDQAAAA==.Jakeyprogue:BAAANQAECgIIBAAAAA==.Jakota:BAAANQADCgUIDAAAAA==.Jakskeleton:BAAANQAECgMIBgAAAA==.',
Je='Jethroy:BAAANQADCgQIBAAAAA==.',
Jo='Joerollin:BAAANQADCggICQABNQAECgcIEQABAAAAAA==.',
Ju='Judax:BAABNQAECoEcAAINAAgK8g5AXQC4AQANAAgK8g5AXQC4AQAAAA==.Justagirl:BAAANQAECgMIBQAAAA==.Juti:BAAANQADCgUIDQAAAA==.Juvu:BAAANQADCgQIBAAAAA==.',
Ka='Kadooka:BAAANQAECgYIDwAAAA==.Kahlyn:BAAANQADCgQIBAAAAA==.Kai:BAAANQAECgYIEAAAAA==.Kaldaran:BAAANQADCgcIBwABNQAECgUICAABAAAAAA==.Kallan:BAAANQADCgQJBAABNQAECgMIBQABAAAAAA==.Kaléanor:BAAANQAECgUICAAAAA==.Karen:BAAANQADCgIIAgAAAA==.Katabell:BAAANQAECgMIBQAAAA==.Katira:BAAANQADCgUIDgAAAA==.',
Ke='Keeganw:BAAANQAECgUICAAAAA==.Keelay:BAAANQAECgcIDwAAAA==.Kelste:BAAANQAECggICgAAAA==.',
Ki='Killaclowns:BAAANQADCgUIDgAAAA==.Kimiko:BAAANQADCgQIBAAAAA==.',
Kl='Klitess:BAAANQADCgIJAgAAAA==.',
Ko='Koffcmorbius:BAAANQADCgUIEAAAAA==.Kostian:BAAANQADCgUICQABNQAECgMIBQABAAAAAA==.',
Kr='Kraken:BAAANQAECggIEgAAAA==.',
Ku='Kubb:BAAANQAECgMIBQAAAA==.',
Kw='Kweh:BAABNQAECoEgAAIOAAkKwR1DBAAEAwAOAAkKwR1DBAAEAwAAAA==.',
['Kê']='Kêlsen:BAAANQAECgEIAQAAAA==.',
La='Laero:BAAANQADCgYIBgABNQAECgMIBQABAAAAAA==.Larrissa:BAAANQADCgUIEAAAAA==.Laurlynn:BAAANQADCgYIBgAAAA==.',
Le='Lenwe:BAAANQAECgEIAQAAAA==.Lettuceprey:BAAANQAECgIIAgAAAA==.',
Li='Lierise:BAAANQADCgcIDgAAAA==.Lilindra:BAAANQAECgQIEAAAAA==.Lillymay:BAAANQAECgEIAQAAAA==.Lilspazz:BAAANQADCgQIBAAAAA==.',
Ll='Lluiz:BAAANQADCgYJCAAAAA==.',
Lo='Lockdeath:BAAANQADCgcIDAAAAA==.Logoruk:BAAANQADCgQIBAAAAA==.Loxia:BAAANQAECgEIAQAAAA==.',
Lu='Lucille:BAAANQADCgYIBgAAAA==.Luckett:BAAANQADCgMJAwAAAA==.Lui:BAAANQAECgIIAgAAAA==.Lumi:BAAANQADCggICgAAAA==.',
Ma='Maavarra:BAAANQAECgIIAgAAAA==.Madshaggy:BAAANQAECgUIDwAAAA==.Magikern:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.Mahallomi:BAAANQADCgQIBAABNQAECgUIDgABAAAAAA==.Maldreth:BAAANQADCgYIBgAAAA==.Maxlin:BAAANQAECgYIBgAAAA==.',
Me='Mehänemäntä:BAAANQADCggIEgAAAA==.Melarii:BAAANQADCgQIBwAAAA==.Merixa:BAAANQAECgEIAQAAAA==.',
Mi='Misstreater:BAAANQAECgEIAQAAAA==.',
Mo='Momentomori:BAAANQAECgYIDAAAAA==.Monbeau:BAABNQAECoEXAAIPAAcKrhYBoQD4AQAPAAcKrhYBoQD4AQAAAA==.Monocerotis:BAAANQAECgcIDAAAAA==.Moosebear:BAAANQADCgYIBgAAAA==.Morishima:BAABNQAECoEjAAMQAAkKtxvjDADnAgAQAAkK+BrjDADnAgARAAcKbRkuFgANAgAAAA==.',
Mu='Multipàss:BAAANQADCgQIBQAAAA==.',
My='Mydarling:BAABNQAECoEhAAMSAAkKNhgJUQBRAgASAAkKNhgJUQBRAgAKAAQKMQ8rogDsAAAAAA==.Mymoon:BAAANQAECgUIBwAAAA==.Myris:BAAANQAECgYIEAAAAA==.',
['Mî']='Mîsgüïdëð:BAAANQADCggIGgAAAA==.',
Na='Naturalchi:BAAANQAECgYIDQAAAA==.',
Ne='Nefilion:BAAANQAECgEIAQAAAA==.Nezin:BAAANQADCgMJAwAAAA==.',
No='Nohzul:BAABNQAFFIEFAAINAAMKFxmsDgAGAQANAAMKFxmsDgAGAQAAAA==.Nomik:BAAANQADCgYIFgABNQAECgEIAQABAAAAAA==.Nonah:BAAANQADCgYIBwAAAA==.',
Nu='Nullspace:BAAANQAECgcIDAAAAA==.',
['Ní']='Níght:BAAANQAECgEIAQAAAA==.',
Or='Orgresh:BAAANQADCggICAAAAA==.Orym:BAAANQAECgMIAwAAAA==.',
Pa='Palacia:BAAANQAECgUICQAAAA==.Pallythetank:BAAANQAECgUICgAAAA==.Pappabeary:BAAANQADCgIJAwAAAA==.',
Pe='Peerow:BAAANQADCgUIDgAAAA==.Petrichorica:BAAANQADCgcICgAAAA==.',
Pi='Pintobeans:BAAANQAECgUJDQAAAA==.',
Pr='Primeatheist:BAAANQAECgYICAAAAA==.',
Pu='Puuhceew:BAAANQAECgYICwAAAA==.',
Ra='Rainbrews:BAAANQAECgEIAQAAAA==.Rainera:BAAANQAECgYIEwABNQAECgkJJwATAM4mAA==.Ramanas:BAAANQADCggJDgAAAA==.Ramrod:BAAANQAECgUJBwAAAA==.Rattles:BAAANQAECgIIAQAAAA==.',
Re='Redgicide:BAAANQAECgYIDwABNQAECgkJJwAGAMQWAA==.Resurgencê:BAAANQAECgMIBQAAAA==.',
Ri='Riordan:BAAANQAECgUICgAAAA==.',
Ro='Rojeton:BAAANQADCgIIAgAAAA==.Rothema:BAAANQAECgMIAwAAAA==.Routh:BAAANQADCgEIAQAAAA==.',
Ru='Rubee:BAAANQADCgMIAwAAAA==.',
Rw='Rwlmaster:BAAANQAECgYIEQAAAA==.',
Sa='Sandwiches:BAAANQADCggIFAAAAA==.',
Sc='Scerra:BAAANQAECgYIEQAAAA==.Scridders:BAAANQAECgUIBwAAAA==.Scridderz:BAAANQAECgEIAQAAAA==.Scriddle:BAAANQAECgQIBAAAAA==.',
Se='Secre:BAAANQADCgQJBAAAAA==.Sellandre:BAAANQADCgYIBgABNQAECgcIDwABAAAAAA==.Seru:BAAANQADCggIGAAAAA==.',
Sh='Shamarha:BAAANQAECgUIBgAAAA==.Shamonbo:BAAANQADCgUIBQABNQAECgcIFwAPAK4WAA==.Sharriavolf:BAAANQAECgYIEwAAAA==.Shreder:BAAANQADCgIIAgAAAA==.Shuma:BAAANQADCgUJBgAAAA==.',
Si='Simichaelton:BAABNQAECoEmAAMUAAkKKRb2EgA2AQAPAAgKKBFMnQAAAgAUAAQKfhz2EgA2AQAAAA==.Sinahi:BAAANQADCgYJBgAAAA==.Sinpal:BAAANQAECgcIDAAAAA==.',
Sn='Sneakysoul:BAAANQAECggIEAAAAA==.',
So='Solyn:BAAANQAECgUICgAAAA==.Sonic:BAAANQADCgUIBQAAAA==.',
Sp='Spagooti:BAAANQAECgQICAAAAA==.Spanxya:BAAANQADCgQIBAAAAA==.Spartaaxd:BAAANQAECgYIEgAAAA==.',
St='Stabbard:BAAANQADCgQIBAAAAA==.Stagerrind:BAAANQADCgMIAwAAAA==.Stejamarha:BAAANQADCgQIBAAAAA==.',
Su='Sugarseer:BAABNQAECoEWAAIMAAgKWReGOgAtAgAMAAgKWReGOgAtAgAAAA==.Suka:BAAANQADCgYIEwAAAA==.Suzi:BAAANQAECgIIBQAAAA==.',
Sw='Swiftleaf:BAAANQADCggICAAAAA==.',
Sy='Syevoid:BAAANQADCgIIAwAAAA==.Sylentcurse:BAAANQAECgEIAQABNQAECgUICwABAAAAAA==.Sylentwolvez:BAAANQAECgIIAgAAAA==.Syleta:BAAANQADCgEIAQABNQAECgQIEAABAAAAAA==.Sylvarus:BAAANQADCgQIBAAAAA==.',
Ta='Tabraxis:BAAANQADCgEJAQAAAA==.Tagalorc:BAAANQAECgQICwAAAA==.Takamaki:BAAANQADCgUICgAAAA==.Tanksbacon:BAAANQAECgUIBQAAAA==.',
Te='Teana:BAAANQAECgcIEAAAAA==.Tempestas:BAAANQADCgUIBQAAAA==.',
Th='Thelegendáry:BAABNQAECoEXAAIMAAgKLRfVPQAfAgAMAAgKLRfVPQAfAgAAAA==.Thorgrimm:BAAANQADCgYIBgAAAA==.Thraine:BAAANQAECgUIBQAAAA==.Threedog:BAAANQADCgIIAgAAAA==.',
Ti='Tione:BAAANQAECgQIBgAAAA==.',
To='Toadvoker:BAABNQAECoEYAAMVAAgKEhaCFAA4AgAVAAgKEhaCFAA4AgAWAAEKxwCEIAARAAAAAA==.Totembish:BAAANQAECgQIBQAAAA==.',
Tr='Trisstan:BAAANQAECgMIBQAAAA==.',
Ty='Tyster:BAABNQAECoEYAAISAAgK2RumUQBPAgASAAgK2RumUQBPAgAAAA==.',
['Tï']='Tïghtgrïp:BAAANQAECgQIBwAAAA==.',
['Tø']='Tørmented:BAAANQADCgUIBQAAAA==.',
Un='Undol:BAAANQADCgUIDgABNQAECgMIBQABAAAAAA==.',
Ve='Velobeef:BAAANQADCgEIAQAAAA==.Veloth:BAACNQAFFIEIAAMUAAMKlxPOAwCrAAAUAAIKqRjOAwCrAAAPAAEKcgmGSQBEAAA1AAQKgTAAAxQACQoJJOMAAIwDABQACQoKI+MAAIwDAA8ACQqJH5ArAB8DAAAA.Verminus:BAAANQAECgYICgAAAA==.',
Vi='Viggle:BAAANQADCgUICAABNQAECgMIBQABAAAAAA==.Viho:BAAANQAECgYIEQAAAA==.Vilekin:BAAANQADCgYIDAAAAA==.Vithaxa:BAAANQADCggIDQAAAA==.',
Vo='Voidra:BAAANQAECgEIAQAAAA==.',
Vy='Vyinson:BAAANQADCgMIBAABNQAECgUIDQABAAAAAA==.',
Wa='Warloque:BAAANQADCgMJAwAAAA==.',
We='Weechuup:BAAANQADCgUICAAAAA==.',
Wi='Wiggle:BAAANQADCgYIBgAAAA==.Willmar:BAAANQAECgMIBAAAAA==.Window:BAAANQADCggICAABNQAECgQIBwABAAAAAA==.Windrun:BAAANQAECgEIAQAAAA==.',
Wo='Wolf:BAABNQAECoEVAAIXAAgKeBH7EgCsAQAXAAgKeBH7EgCsAQAAAA==.Woodtique:BAAANQADCgUIDQAAAA==.',
Wu='Wulthan:BAAANQADCgUJBQAAAA==.',
Xa='Xandercruise:BAAANQAECgEIAQAAAA==.',
Xu='Xuchilbara:BAAANQAECgQIBwAAAA==.',
Ya='Yamato:BAAANQAECgUIBQAAAA==.',
Zb='Zbelladonna:BAAANQADCggIEgABNQAECgkJKgAYACQhAA==.',
Ze='Zezera:BAAANQADCggIGAAAAA==.',
Zh='Zhades:BAABNQAECoEqAAMYAAkKJCEkCQAvAwAYAAkK1yAkCQAvAwAZAAkKxBJ5QAC1AQAAAA==.Zhort:BAAANQADCgQICAAAAA==.',
Zu='Zultan:BAABNQAECoEYAAIDAAgKEAo9cAC2AQADAAgKEAo9cAC2AQAAAA==.',
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
