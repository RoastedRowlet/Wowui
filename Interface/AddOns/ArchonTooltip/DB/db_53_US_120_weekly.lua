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

local lookup = {'Unknown-Unknown','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Druid-Restoration','DemonHunter-Devourer','Paladin-Holy','DemonHunter-Havoc','Druid-Feral','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Paladin-Retribution','DemonHunter-Vengeance','Mage-Frost','DeathKnight-Frost','DeathKnight-Unholy',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abberleigh:BAAANQADCgcJEAAAAA==.Abron:BAAANQADCgMIAwAAAA==.',
Ae='Aerostotle:BAAANQABCgQJBQAAAA==.',
Ag='Aganoth:BAAANQAECgcJEAAAAA==.',
Al='Alaraa:BAAANQADCgUIBwABNQAECgQIDgABAAAAAA==.Algonq:BAAANQADCgUIEAABNQAECgIJAgABAAAAAA==.Alkamaz:BAAANQAECgQJBwAAAA==.Alstar:BAAANQAECgcJDgAAAA==.Alynis:BAAANQADCgQIBAAAAA==.',
Am='Amathus:BAABNQAECoEaAAQCAAgKCRHrBQDeAQACAAcKuw/rBQDeAQADAAYKSw4ofQBMAQAEAAEKUwY+awAuAAAAAA==.',
An='Andarial:BAAANQAECgEIAQAAAA==.Andreth:BAAANQADCgcJEAAAAA==.Anoxyn:BAAANQADCgYIBgAAAA==.Anthe:BAAANQADCgUIDgAAAA==.',
Ar='Arcanmaggy:BAAANQADCgYJDgABNQAECggJGwADABgQAA==.Arcee:BAAANQADCgQIBgAAAA==.Ares:BAAANQAECgIJAgABNQADCgMJAwABAAAAAA==.Aryxi:BAAANQADCgUJBQABNQADCgMJAwABAAAAAA==.',
As='Asiägo:BAAANQABCgcJCgAAAA==.',
Ba='Baelhal:BAAANQAECgYJEgAAAA==.',
Be='Bearypotter:BAAANQADCgUIBQAAAA==.Benedin:BAAANQADCgcJDAABNQAECgcIEQABAAAAAA==.',
Bi='Bigtex:BAAANQAECgIJAgAAAA==.Biped:BAAANQAECgQIBwAAAA==.',
Bl='Blackdeath:BAAANQAECgQIBAAAAA==.',
Bo='Bofadees:BAAANQADCggIFAAAAA==.Boloevo:BAAANQADCgUIBQAAAA==.Bolopal:BAAANQADCgcIDAAAAA==.Boomstique:BAAANQAECgIJAgAAAA==.Boondocka:BAABNQAECoEfAAIFAAgKQxdQNABjAgAFAAgKQxdQNABjAgAAAA==.',
Br='Brewco:BAABNQAECoEiAAIGAAkK8iMzAQCuAwAGAAkK8iMzAQCuAwAAAA==.Brissennissa:BAABNQAECoEcAAIHAAgKLhuxEgCSAgAHAAgKLhuxEgCSAgAAAA==.Brokkr:BAAANQADCgYICwAAAA==.Bronar:BAAANQADCgMIAwAAAA==.Brutalís:BAAANQAECgMIBgAAAA==.',
Bt='Btrain:BAAANQADCggIDgAAAA==.',
Bu='Bubblebae:BAAANQADCgYIBwABNQAECgQIBAABAAAAAA==.',
['Bó']='Bóunty:BAAANQAECgUICQAAAA==.',
Ce='Cenobité:BAAANQAECgIJAgAAAA==.',
Ch='Chialing:BAAANQAECgIIAgAAAA==.Chichi:BAAANQAECggJCAAAAA==.Chip:BAAANQADCgUIBQAAAA==.Chuckfinley:BAAANQADCggJEQAAAA==.',
Ci='Cirax:BAAANQAECgEIAQAAAA==.',
Cl='Classic:BAAANQADCgUIBwABNQAECgIJAgABAAAAAA==.Clenton:BAAANQAECgYJEAAAAA==.',
Co='Cosplay:BAAANQADCggIFgABNQAECggJCAABAAAAAA==.',
Cr='Crichton:BAABNQAECoEgAAIHAAkKMB5LCwD9AgAHAAkKMB5LCwD9AgAAAA==.Crowford:BAAANQAECgMIBAAAAA==.',
Cy='Cyris:BAAANQADCgQJBgABNQAECgIJAgABAAAAAA==.',
['Cá']='Cástle:BAAANQAECgQIBwAAAA==.',
Da='Daevahna:BAAANQADCgYICwAAAA==.Dak:BAAANQAECgYIEAAAAA==.Dakstorm:BAAANQADCgYICgABNQAECgYIEAABAAAAAA==.Darkmiza:BAABNQAECoEbAAIDAAgKGBAKSwDzAQADAAgKGBAKSwDzAQAAAA==.',
De='Deadmangalad:BAAANQADCgUJCgAAAA==.Deedees:BAAANQAECgQJBgAAAA==.Demonhandler:BAAANQADCgQIBAAAAA==.Demonikk:BAAANQADCggIAQAAAA==.Deo:BAAANQAECgYIDAABNQAECggJCAABAAAAAA==.Depression:BAAANQAECggJBAAAAA==.',
Di='Diioo:BAAANQAECgMIBQAAAA==.Dirtnåp:BAAANQADCgYJCQAAAA==.Diskbänk:BAAANQADCgUIBQAAAA==.',
Dr='Dragontoast:BAAANQADCgcJEAAAAA==.Druidïan:BAAANQADCggIEwAAAA==.',
Dy='Dynwor:BAAANQADCggICgAAAA==.',
Ea='Easme:BAAANQAECgUJCQAAAA==.',
El='Elaric:BAAANQAECgEIAQAAAA==.',
En='Engi:BAAANQAECgUICwAAAA==.Enhuna:BAAANQADCgIIAgAAAA==.',
Es='Escaper:BAAANQAECgUJCQAAAA==.',
Ex='Extrema:BAAANQADCgcJEAAAAA==.',
Fh='Fhait:BAAANQADCgUJFAABNQAECgIJAgABAAAAAA==.',
Fi='Fionab:BAAANQADCgIIAgAAAA==.',
Fo='Foxfu:BAAANQADCgYICwAAAA==.',
Fu='Fujika:BAAANQADCgQIBAAAAA==.',
Ga='Galadan:BAAANQAECgIIAgABNQADCgUJCgABAAAAAA==.Garrekton:BAAANQAECgcIEQAAAA==.Gaskelmarg:BAAANQADCgQJCQAAAA==.',
Ge='Gellane:BAAANQAECgMIAwAAAA==.',
Gh='Ghozt:BAAANQADCgUICgABNQAECgQIBwABAAAAAA==.',
Gl='Glory:BAABNQAECoEWAAIIAAcKFB1KKgBdAgAIAAcKFB1KKgBdAgAAAA==.',
Go='Goldtusk:BAAANQAECgUJCQAAAA==.',
Gr='Graveyard:BAAANQADCgcICwABNQAECgQIBwABAAAAAA==.Grundler:BAAANQADCgYICQAAAA==.Gryphone:BAAANQADCggIEAAAAA==.',
Ha='Hakmud:BAAANQADCgQJBAAAAA==.Harandee:BAAANQADCgUIBQAAAA==.Haufa:BAAANQAECgEJAQAAAA==.',
He='Hettokal:BAAANQADCgQIBAAAAA==.Heximal:BAAANQADCgQIBwABNQAECggIHwAFAEMXAA==.',
Ho='Hondojoe:BAAANQAECgYJCgAAAA==.Honeydrake:BAAANQAECgMIBQAAAA==.Hopewell:BAAANQAECgIJAgAAAA==.',
Hu='Hugnsnuggle:BAAANQAECgIJAgABNQAECgIJAgABAAAAAA==.Huhu:BAAANQAECgYICQAAAA==.Humilitas:BAAANQADCgUICQAAAA==.',
Ib='Ibn:BAAANQAECgQIBwAAAA==.',
Il='Illadus:BAAANQADCgYICwAAAA==.Illidab:BAABNQAECoEZAAIJAAgKghmOFwB0AgAJAAgKghmOFwB0AgAAAA==.',
In='Infectus:BAAANQAECggJCAAAAA==.',
Ir='Irielle:BAAANQADCgUJDgAAAA==.',
Iv='Ivylyn:BAAANQADCgYIBgAAAA==.',
Ix='Ixiyá:BAAANQAECgcIEQAAAA==.Ixií:BAAANQADCgYIBgAAAA==.Ixì:BAAANQADCgEIAQAAAA==.',
Ja='Jakbenimble:BAAANQADCgcIDQAAAA==.Jakeyprogue:BAAANQAECgIIBAAAAA==.Jakota:BAAANQADCgQJBwAAAA==.Jakskeleton:BAAANQAECgMIBAAAAA==.',
Je='Jethroy:BAAANQADCgQIBAAAAA==.',
Jo='Joerollin:BAAANQADCggICQABNQAECgYJCgABAAAAAA==.',
Ju='Judax:BAAANQAECgYIEAAAAA==.Justagirl:BAAANQAECgIJAgAAAA==.Juti:BAAANQADCgUJCAAAAA==.Juvu:BAAANQADCgQIBAAAAA==.',
Ka='Kadooka:BAAANQAECgQICQAAAA==.Kahlyn:BAAANQADCgQIBAAAAA==.Kai:BAAANQAECgYICgAAAA==.Kallan:BAAANQADCgQJBAABNQAECgIJAgABAAAAAA==.Kaléanor:BAAANQAECgEIAwAAAA==.Karen:BAAANQADCgIIAgAAAA==.Katabell:BAAANQAECgIJAgAAAA==.Katira:BAAANQADCgUIDgAAAA==.',
Ke='Keeganw:BAAANQAECgMIAwAAAA==.Keelay:BAAANQAECgcIDwAAAA==.Kelste:BAAANQAECggJCQAAAA==.',
Ki='Killaclowns:BAAANQADCgQJCQAAAA==.Kimiko:BAAANQADCgQIBAAAAA==.',
Kl='Klitess:BAAANQADCgIJAgAAAA==.',
Ko='Koffcmorbius:BAAANQADCgQJCwAAAA==.Kostian:BAAANQADCgUICQABNQAECgIJAgABAAAAAA==.',
Kr='Kraken:BAAANQAECgcIDAAAAA==.',
Ku='Kubb:BAAANQAECgIJAgAAAA==.',
Kw='Kweh:BAABNQAECoEcAAIKAAgKKx55BADJAgAKAAgKKx55BADJAgAAAA==.',
['Kê']='Kêlsen:BAAANQAECgEJAQAAAA==.',
La='Larrissa:BAAANQADCgQJCwAAAA==.',
Le='Lenwe:BAAANQAECgEJAQAAAA==.Lettuceprey:BAAANQADCggJGAAAAA==.',
Li='Lierise:BAAANQADCgcIDgAAAA==.Lilindra:BAAANQAECgQIDgAAAA==.Lillymay:BAAANQAECgEIAQAAAA==.Lilspazz:BAAANQADCgQIBAAAAA==.',
Ll='Lluiz:BAAANQADCgYJCAAAAA==.',
Lo='Lockdeath:BAAANQADCgQJBQAAAA==.Logoruk:BAAANQADCgQIBAAAAA==.Loxia:BAAANQAECgEIAQAAAA==.',
Lu='Lucille:BAAANQADCgYIBgAAAA==.Luckett:BAAANQADCgMJAwAAAA==.Lumi:BAAANQADCgIIAgAAAA==.',
Ma='Maavarra:BAAANQADCggJHQAAAA==.Madshaggy:BAAANQAECgUICgAAAA==.Mahallomi:BAAANQADCgQIBAABNQAECgUICQABAAAAAA==.Maxlin:BAAANQADCgUJEgAAAA==.',
Me='Mehänemäntä:BAAANQADCgUICgAAAA==.Melarii:BAAANQADCgQIBwAAAA==.Merixa:BAAANQADCgQJDgAAAA==.',
Mi='Misstreater:BAAANQAECgEJAQAAAA==.',
Mo='Momentomori:BAAANQAECgYJBgAAAA==.Monbeau:BAABNQAECoEWAAILAAcKgBX6kADtAQALAAcKgBX6kADtAQAAAA==.Monocerotis:BAAANQAECgUIBwAAAA==.Moosebear:BAAANQADCgYIBgAAAA==.Morishima:BAABNQAECoEaAAMMAAkKcxjGEgAhAgAMAAcKbRnGEgAhAgANAAMKDxSSQwDSAAAAAA==.',
Mu='Multipàss:BAAANQADCgQIBQAAAA==.',
My='Mydarling:BAABNQAECoEdAAMOAAkK0Bb5RgA3AgAOAAkK0Bb5RgA3AgAIAAQKMQ9hjADxAAAAAA==.Mymoon:BAAANQAECgQJBQAAAA==.Myris:BAAANQAECgUICgAAAA==.',
['Mî']='Mîsgüïdëð:BAAANQADCggJFgAAAA==.',
Na='Naturalchi:BAAANQAECgUJBwAAAA==.',
Ne='Nefilion:BAAANQAECgEIAQAAAA==.Nezin:BAAANQADCgMJAwAAAA==.',
No='Nohzul:BAAANQAFFAEIAgAAAA==.Nomik:BAAANQADCgYIFgABNQAECgEJAQABAAAAAA==.Nonah:BAAANQADCgYIBwAAAA==.',
Nu='Nullspace:BAAANQAECgcIDAAAAA==.',
Or='Orgresh:BAAANQADCggICAAAAA==.',
Pa='Palacia:BAAANQAECgUICQAAAA==.Pallythetank:BAAANQAECgMIBQAAAA==.Pappabeary:BAAANQADCgIJAwAAAA==.',
Pe='Peerow:BAAANQADCgUJCQAAAA==.Petrichorica:BAAANQADCgcICgAAAA==.',
Pi='Pintobeans:BAAANQAECgUJDQAAAA==.',
Pr='Primeatheist:BAAANQAECgUJBwAAAA==.',
Pu='Puuhceew:BAAANQAECgQICQAAAA==.',
Ra='Rainbrews:BAAANQAECgEIAQAAAA==.Rainera:BAAANQAECgUIDQABNQAECgkJIwAPAK0mAA==.Ramanas:BAAANQADCggJDgAAAA==.Ramrod:BAAANQAECgUJBwAAAA==.Rattles:BAAANQADCgEIAQAAAA==.',
Re='Redgicide:BAAANQAECgYIDAABNQAECggIHwAFAEMXAA==.Resurgencê:BAAANQAECgIJAgAAAA==.',
Ri='Riordan:BAAANQAECgQIBQAAAA==.',
Ro='Rojeton:BAAANQADCgIIAgAAAA==.Rothema:BAAANQAECgIJAgAAAA==.Routh:BAAANQADCgEIAQAAAA==.',
Ru='Rubee:BAAANQADCgMIAwAAAA==.',
Rw='Rwlmaster:BAAANQAECgUICwAAAA==.',
Sa='Sandwiches:BAAANQADCgUIDAAAAA==.',
Sc='Scerra:BAAANQAECgUJCwAAAA==.Scridders:BAAANQAECgEIAgAAAA==.Scriddle:BAAANQAECgQIBAAAAA==.',
Se='Secre:BAAANQADCgQJBAAAAA==.Sellandre:BAAANQADCgYIBgABNQAECgcJCAABAAAAAA==.Seru:BAAANQADCgcJEAAAAA==.',
Sh='Shamarha:BAAANQAECgUIBgAAAA==.Shamonbo:BAAANQADCgUIBQABNQAECgcJFgALAIAVAA==.Sharriavolf:BAAANQAECgYJEAAAAA==.Shreder:BAAANQADCgIIAgAAAA==.Shuma:BAAANQADCgUJBgAAAA==.',
Si='Simichaelton:BAABNQAECoEgAAMQAAkKKRaiDgBGAQALAAgKKBEufwAaAgAQAAQKfhyiDgBGAQAAAA==.Sinahi:BAAANQADCgYJBgAAAA==.Sinpal:BAAANQAECgcIDAAAAA==.',
Sn='Sneakysoul:BAAANQAECggJCAAAAA==.',
So='Solyn:BAAANQAECgUIBQAAAA==.Sonic:BAAANQADCgUIBQAAAA==.',
Sp='Spagooti:BAAANQAECgQICAAAAA==.Spanxya:BAAANQADCgQIBAAAAA==.Spartaaxd:BAAANQAECgYJDAAAAA==.',
St='Stabbard:BAAANQADCgQIBAAAAA==.Stagerrind:BAAANQADCgMIAwAAAA==.Stejamarha:BAAANQADCgQIBAAAAA==.',
Su='Sugarseer:BAAANQAECgYIDQAAAA==.Suka:BAAANQADCgUIDQAAAA==.Suzi:BAAANQAECgIJAwAAAA==.',
Sw='Swiftleaf:BAAANQADCggICAAAAA==.',
Sy='Syevoid:BAAANQADCgIIAgAAAA==.Sylentcurse:BAAANQAECgEJAQABNQAECgMIBgABAAAAAA==.Sylentwolvez:BAAANQADCgUJCwAAAA==.Syleta:BAAANQADCgEIAQABNQAECgQIDgABAAAAAA==.Sylvarus:BAAANQADCgQIBAAAAA==.',
Ta='Tabraxis:BAAANQADCgEJAQAAAA==.Tagalorc:BAAANQAECgQIBwAAAA==.Takamaki:BAAANQADCgUJCQAAAA==.Tanksbacon:BAAANQADCgcIEwAAAA==.',
Te='Teana:BAAANQAECgQICQAAAA==.Tempestas:BAAANQADCgUJBQAAAA==.',
Th='Thelegendáry:BAAANQAECgcIEQAAAA==.Thorgrimm:BAAANQADCgYIBgAAAA==.Thraine:BAAANQADCggJCgAAAA==.Threedog:BAAANQADCgIIAgAAAA==.',
Ti='Tione:BAAANQAECgIIAgAAAA==.',
To='Toadvoker:BAAANQAECgcIEwAAAA==.Totembish:BAAANQAECgIIAgAAAA==.',
Tr='Trisstan:BAAANQAECgIJAgAAAA==.',
Ty='Tyster:BAABNQAECoEWAAIOAAgK2Rt/OwBlAgAOAAgK2Rt/OwBlAgAAAA==.',
['Tï']='Tïghtgrïp:BAAANQAECgMIAwAAAA==.',
['Tø']='Tørmented:BAAANQADCgUIBQAAAA==.',
Un='Undol:BAAANQADCgUIDgABNQAECgIJAgABAAAAAA==.',
Ve='Veloth:BAABNQAECoEpAAMQAAkKByOlAACQAwAQAAkKQyKlAACQAwALAAkKkx0cMQD7AgAAAA==.Verminus:BAAANQAECgUJCQAAAA==.',
Vi='Viggle:BAAANQADCgMJAwABNQAECgIJAgABAAAAAA==.Viho:BAAANQAECgUJCwAAAA==.Vilekin:BAAANQADCgYIBgAAAA==.Vithaxa:BAAANQADCgYIBgAAAA==.',
Vo='Voidra:BAAANQAECgEIAQAAAA==.',
Vy='Vyinson:BAAANQADCgMIBAABNQAECgUJCQABAAAAAA==.',
Wa='Warloque:BAAANQADCgMJAwAAAA==.',
We='Weechuup:BAAANQADCgUICAAAAA==.',
Wi='Willmar:BAAANQAECgMIBAAAAA==.Window:BAAANQADCggICAABNQAECgQIBwABAAAAAA==.Windrun:BAAANQADCgcJDQAAAA==.',
Wo='Wolf:BAAANQAECgYJEwAAAA==.Woodtique:BAAANQADCgQJCAAAAA==.',
Wu='Wulthan:BAAANQADCgUJBQAAAA==.',
Xa='Xandercruise:BAAANQAECgEIAQAAAA==.',
Xu='Xuchilbara:BAAANQAECgIJAwAAAA==.',
Ya='Yamato:BAAANQADCgkJFAAAAA==.',
Zb='Zbelladonna:BAAANQADCggIEgABNQAECgkJIQARAGIgAA==.',
Ze='Zezera:BAAANQADCgcJEAAAAA==.',
Zh='Zhades:BAABNQAECoEhAAMRAAkKYiByCAAjAwARAAkK8B9yCAAjAwASAAkKxBIjLwD2AQAAAA==.Zhort:BAAANQADCgQJBQAAAA==.',
Zu='Zultan:BAAANQAECgYIDQAAAA==.',
Zy='Zynblasted:BAAANQADCgQIBAAAAA==.Zynhunter:BAAANQADCgIJAgAAAA==.',
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
