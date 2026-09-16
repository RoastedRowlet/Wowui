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

local lookup = {'Unknown-Unknown','Druid-Restoration','DemonHunter-Devourer','Paladin-Retribution','Paladin-Holy','DemonHunter-Vengeance','Mage-Arcane','Mage-Frost','DeathKnight-Frost','DeathKnight-Unholy',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abberleigh:BAAANQADCgUIDAAAAA==.Abron:BAAANQADCgMIAwAAAA==.',
Ae='Aerostotle:BAAANQABCgQIBQAAAA==.',
Ag='Aganoth:BAAANQAECgcIEAAAAA==.',
Al='Alaraa:BAAANQADCgUIBwABNQAECgQIDgABAAAAAA==.Algonq:BAAANQADCgUICwABNQADCggIFgABAAAAAA==.Alkamaz:BAAANQAECgQIBgAAAA==.Alstar:BAAANQAECgYIDQAAAA==.Alynis:BAAANQADCgQIBAAAAA==.',
Am='Amathus:BAAANQAECgYIDgAAAA==.',
An='Andarial:BAAANQADCggIDwAAAA==.Andreth:BAAANQADCgUIDAAAAA==.Anoxyn:BAAANQADCgYIBgAAAA==.Anthe:BAAANQADCgQICQAAAA==.',
Ar='Arcanmaggy:BAAANQADCgYIDgABNQAECgYIEQABAAAAAA==.Arcee:BAAANQADCgQIBgAAAA==.Ares:BAAANQADCgQIBAABNQADCgMIAwABAAAAAA==.Aryxi:BAAANQADCgUIBQABNQADCgMIAwABAAAAAA==.',
As='Asiägo:BAAANQABCgcICAAAAA==.',
Ba='Baelhal:BAAANQAECgYIDAAAAA==.',
Be='Bearypotter:BAAANQADCgUIBQAAAA==.Benedin:BAAANQADCgcIDAABNQAECgUICgABAAAAAA==.',
Bi='Bigtex:BAAANQADCggIFwAAAA==.Biped:BAAANQAECgIIAwAAAA==.',
Bl='Blackdeath:BAAANQAECgQIBAAAAA==.',
Bo='Bofadees:BAAANQADCggIFAAAAA==.Boloevo:BAAANQADCgUIBQAAAA==.Bolopal:BAAANQADCgcIDAAAAA==.Boomstique:BAAANQADCggIFgAAAA==.Boondocka:BAAANQAECgcIEQAAAA==.',
Br='Brewco:BAABNQAECoEdAAICAAkJByPDAACyAwACAAkJByPDAACyAwAAAA==.Brissennissa:BAAANQAECgcIEQAAAA==.Brokkr:BAAANQADCgYICwAAAA==.Bronar:BAAANQADCgMIAwAAAA==.Brutalís:BAAANQAECgIIAwAAAA==.',
Bt='Btrain:BAAANQADCggIDgAAAA==.',
Bu='Bubblebae:BAAANQADCgYIBwABNQADCggIDQABAAAAAA==.',
['Bó']='Bóunty:BAAANQAECgQIBAAAAA==.',
Ce='Cenobité:BAAANQADCggIFQAAAA==.',
Ch='Chialing:BAAANQADCggIDAAAAA==.Chichi:BAAANQADCggICAAAAA==.Chuckfinley:BAAANQADCgYIDwAAAA==.',
Ci='Cirax:BAAANQADCgcIFQAAAA==.',
Cl='Classic:BAAANQADCgIIAgABNQADCggIFgABAAAAAA==.Clenton:BAAANQAECgYICgAAAA==.',
Co='Cosplay:BAAANQADCggIDgABNQAECgYIDAABAAAAAA==.',
Cr='Crichton:BAABNQAECoEZAAIDAAkJah3pCAARAwADAAkJah3pCAARAwAAAA==.Crowford:BAAANQAECgMIBAAAAA==.',
Cy='Cyris:BAAANQADCgQIBgABNQADCggIGAABAAAAAA==.',
['Cá']='Cástle:BAAANQAECgQIBwAAAA==.',
Da='Daevahna:BAAANQADCgUIBQAAAA==.Dak:BAAANQAECgUICgAAAA==.Dakstorm:BAAANQADCgYICgABNQAECgUICgABAAAAAA==.Darkmiza:BAAANQAECgYIEQAAAA==.',
De='Deadmangalad:BAAANQADCgUICgAAAA==.Deedees:BAAANQAECgQIBAAAAA==.Demonhandler:BAAANQADCgQIBAAAAA==.Deo:BAAANQAECgYIDAAAAA==.',
Di='Diioo:BAAANQAECgMIBQAAAA==.Dirtnåp:BAAANQADCgUICQAAAA==.',
Dr='Dragontoast:BAAANQADCgUIDAAAAA==.Druidïan:BAAANQADCgYIDwAAAA==.',
Dy='Dynwor:BAAANQADCggICgAAAA==.',
Ea='Easme:BAAANQAECgQIBQAAAA==.',
El='Elaric:BAAANQADCggICAAAAA==.',
En='Engi:BAAANQAECgQIBgAAAA==.Enhuna:BAAANQADCgIIAgAAAA==.',
Es='Escaper:BAAANQAECgIIBAAAAA==.',
Ex='Extrema:BAAANQADCgUIDAAAAA==.',
Fh='Fhait:BAAANQADCgUIEQABNQADCggIFgABAAAAAA==.',
Fi='Fionab:BAAANQADCgIIAgAAAA==.',
Fo='Foxfu:BAAANQADCgYICwAAAA==.',
Ga='Galadan:BAAANQADCggIEgABNQADCgUICgABAAAAAA==.Garrekton:BAAANQAECgUICgAAAA==.Gaskelmarg:BAAANQADCgQIBgAAAA==.',
Ge='Gellane:BAAANQAECgMIAwAAAA==.',
Gh='Ghozt:BAAANQADCgUICgABNQAECgQIBwABAAAAAA==.',
Gl='Glory:BAAANQAECgYIDgAAAA==.',
Go='Goldtusk:BAAANQAECgIIBAAAAA==.',
Gr='Graveyard:BAAANQADCgcICwABNQAECgQIBwABAAAAAA==.Grundler:BAAANQADCgYICQAAAA==.Gryphone:BAAANQADCggIEAAAAA==.',
Ha='Hakmud:BAAANQADCgQIBAAAAA==.Harandee:BAAANQADCgUIBQAAAA==.Haufa:BAAANQADCgUICAAAAA==.',
He='Hettokal:BAAANQADCgQIBAAAAA==.Heximal:BAAANQADCgQIBwABNQAECgcIEQABAAAAAA==.',
Ho='Hondojoe:BAAANQAECgUIBQAAAA==.Honeydrake:BAAANQAECgIIAwAAAA==.Hopewell:BAAANQADCggIFgAAAA==.',
Hu='Hugnsnuggle:BAAANQADCggIFgAAAA==.Huhu:BAAANQAECgYICAAAAA==.Humilitas:BAAANQADCgUICQAAAA==.',
Ib='Ibn:BAAANQAECgIIAwAAAA==.',
Il='Illadus:BAAANQADCgYICwAAAA==.Illidab:BAAANQAECgcIEgAAAA==.',
Ir='Irielle:BAAANQADCgUIDAAAAA==.',
Iv='Ivylyn:BAAANQADCgIIAgAAAA==.',
Ix='Ixiyá:BAAANQAECgcIDwAAAA==.Ixií:BAAANQADCgYIBgAAAA==.Ixì:BAAANQADCgEIAQAAAA==.',
Ja='Jakbenimble:BAAANQADCgcIDQAAAA==.Jakeyprogue:BAAANQAECgIIAgAAAA==.Jakota:BAAANQADCgQIBAAAAA==.Jakskeleton:BAAANQAECgEIAQAAAA==.',
Je='Jethroy:BAAANQADCgQIBAAAAA==.',
Jo='Joerollin:BAAANQADCgEIAQABNQAECgUIBQABAAAAAA==.',
Ju='Judax:BAAANQAECgQICgAAAA==.Justagirl:BAAANQADCggIFQABNQADCggIFgABAAAAAA==.Juti:BAAANQADCgUIBQAAAA==.Juvu:BAAANQADCgQIBAAAAA==.',
Ka='Kadooka:BAAANQAECgQIBwAAAA==.Kahlyn:BAAANQADCgQIBAAAAA==.Kai:BAAANQAECgYICgAAAA==.Kallan:BAAANQADCgQIBAABNQADCggIFgABAAAAAA==.Kaléanor:BAAANQAECgEIAgAAAA==.Karen:BAAANQADCgIIAgAAAA==.Katabell:BAAANQADCggIFgAAAA==.Katira:BAAANQADCgUICQAAAA==.',
Ke='Keeganw:BAAANQAECgMIAwAAAA==.Keelay:BAAANQAECgcIDwAAAA==.Kelste:BAAANQAECggIBwAAAA==.',
Ki='Killaclowns:BAAANQADCgQIBgAAAA==.Kimiko:BAAANQADCgQIBAAAAA==.',
Ko='Koffcmorbius:BAAANQADCgQICAAAAA==.Kostian:BAAANQADCgUICQABNQADCggIFgABAAAAAA==.',
Kr='Kraken:BAAANQAECgUIBwAAAA==.',
Ku='Kubb:BAAANQADCggIGAAAAA==.',
Kw='Kweh:BAAANQAECgcIEgAAAA==.',
['Kê']='Kêlsen:BAAANQADCgYIDwAAAA==.',
La='Larrissa:BAAANQADCgQICAAAAA==.',
Le='Lenwe:BAAANQADCgQIBgABNQADCgYIFgABAAAAAA==.Lettuceprey:BAAANQADCggIEAAAAA==.',
Li='Lierise:BAAANQADCgcIDgAAAA==.Lilindra:BAAANQAECgQIDgAAAA==.Lillymay:BAAANQAECgEIAQAAAA==.Lilspazz:BAAANQADCgQIBAAAAA==.',
Ll='Lluiz:BAAANQADCgYIBQAAAA==.',
Lo='Lockdeath:BAAANQADCgEIAQAAAA==.Logoruk:BAAANQADCgQIBAAAAA==.Loxia:BAAANQADCggICAAAAA==.',
Lu='Lucille:BAAANQADCgYIBgAAAA==.Luckett:BAAANQADCgMIAwAAAA==.Lumi:BAAANQADCgIIAgAAAA==.',
Ma='Maavarra:BAAANQADCggIFQAAAA==.Madshaggy:BAAANQAECgQIBQAAAA==.Mahallomi:BAAANQADCgQIBAABNQAECgIIBAABAAAAAA==.Maxlin:BAAANQADCgUIDQAAAA==.',
Me='Mehänemäntä:BAAANQADCgUICgAAAA==.Melarii:BAAANQADCgMIAwAAAA==.Merixa:BAAANQADCgQIDgAAAA==.',
Mi='Misstreater:BAAANQAECgEIAQAAAA==.',
Mo='Momentomori:BAAANQADCgYIBgAAAA==.Monbeau:BAAANQAECgYIDwAAAA==.Monocerotis:BAAANQAECgUIBQAAAA==.Moosebear:BAAANQADCgYIBgAAAA==.Morishima:BAAANQAECgYIDwAAAA==.',
Mu='Multipàss:BAAANQADCgQIBQAAAA==.',
My='Mydarling:BAABNQAECoEYAAMEAAkJ2xTBMgA7AgAEAAkJ2xTBMgA7AgAFAAEJ2w3qtQA0AAAAAA==.Mymoon:BAAANQAECgMIBAAAAA==.Myris:BAAANQAECgUIBgAAAA==.',
['Mî']='Mîsgüïdëð:BAAANQADCggIEAAAAA==.',
Na='Naturalchi:BAAANQAECgIIAgAAAA==.',
Ne='Nefilion:BAAANQAECgEIAQAAAA==.Nezin:BAAANQADCgMIAwAAAA==.',
No='Nohzul:BAAANQAFFAEIAQAAAA==.Nomik:BAAANQADCgYIFgAAAA==.Nonah:BAAANQADCgUIBQAAAA==.',
Nu='Nullspace:BAAANQAECgYICwAAAA==.',
Or='Orgresh:BAAANQADCggICAAAAA==.',
Pa='Palacia:BAAANQAECgMIBAAAAA==.Pallythetank:BAAANQAECgMIAwAAAA==.Pappabeary:BAAANQADCgIIAgAAAA==.',
Pe='Peerow:BAAANQADCgUIBwAAAA==.Petrichorica:BAAANQADCgcICgAAAA==.',
Pi='Pintobeans:BAAANQAECgUICAAAAA==.',
Pr='Primeatheist:BAAANQAECgQIBgAAAA==.',
Pu='Puuhceew:BAAANQAECgQIBwAAAA==.',
Ra='Rainbrews:BAAANQAECgEIAQAAAA==.Rainera:BAAANQAECgQICAABNQAECggIGgAGAMEmAA==.Ramanas:BAAANQADCggICAAAAA==.Ramrod:BAAANQAECgIIAgAAAA==.Rattles:BAAANQADCgEIAQAAAA==.',
Re='Redgicide:BAAANQAECgQIBQABNQAECgcIEQABAAAAAA==.Resurgencê:BAAANQADCggIFgAAAA==.',
Ri='Riordan:BAAANQAECgEIAQAAAA==.',
Ro='Rojeton:BAAANQADCgIIAgAAAA==.Rothema:BAAANQADCgcIEgAAAA==.Routh:BAAANQADCgEIAQAAAA==.',
Ru='Rubee:BAAANQADCgMIAwAAAA==.',
Rw='Rwlmaster:BAAANQAECgQIBgAAAA==.',
Sa='Sandwiches:BAAANQADCgUIDAAAAA==.',
Sc='Scerra:BAAANQAECgQIBgAAAA==.Scridders:BAAANQAECgEIAQAAAA==.Scriddle:BAAANQADCgYIBgAAAA==.',
Se='Sellandre:BAAANQADCgYIBgABNQADCggIDQABAAAAAA==.Seru:BAAANQADCgUIDAAAAA==.',
Sh='Shamarha:BAAANQAECgEIAQAAAA==.Shamonbo:BAAANQADCgUIBQABNQAECgYIDwABAAAAAA==.Sharriavolf:BAAANQAECgYICwAAAA==.Shreder:BAAANQADCgIIAgAAAA==.Shuma:BAAANQADCgUIBQAAAA==.',
Si='Simichaelton:BAAANQAECgcIEwABNQAECggIEgABAAAAAA==.Sinpal:BAAANQAECgcICwAAAA==.',
Sn='Sneakysoul:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.',
So='Solyn:BAAANQADCgcIBwAAAA==.Sonic:BAAANQADCgUIBQAAAA==.',
Sp='Spagooti:BAAANQAECgMIBAAAAA==.Spanxya:BAAANQADCgQIBAAAAA==.Spartaaxd:BAAANQAECgQIBgAAAA==.',
St='Stabbard:BAAANQADCgQIBAAAAA==.Stagerrind:BAAANQADCgMIAwAAAA==.',
Su='Sugarseer:BAAANQAECgYIDAAAAA==.Suka:BAAANQADCgQICAAAAA==.Suzi:BAAANQAECgIIAgAAAA==.',
Sw='Swiftleaf:BAAANQADCggICAAAAA==.',
Sy='Syevoid:BAAANQADCgIIAgAAAA==.Sylentcurse:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Sylentwolvez:BAAANQADCgUIBwAAAA==.Syleta:BAAANQADCgEIAQABNQAECgQIDgABAAAAAA==.Sylvarus:BAAANQADCgQIBAAAAA==.',
Ta='Tabraxis:BAAANQADCgEIAQAAAA==.Tagalorc:BAAANQAECgMIAwAAAA==.Takamaki:BAAANQADCgUIBwAAAA==.Tanksbacon:BAAANQADCgcIEwAAAA==.',
Te='Teana:BAAANQAECgQICAAAAA==.Tempestas:BAAANQADCgIIBAAAAA==.',
Th='Thelegendáry:BAAANQAECgYIBwABNQAECgcIBwABAAAAAA==.Thraine:BAAANQADCgIIAgAAAA==.Threedog:BAAANQADCgIIAgAAAA==.',
Ti='Tione:BAAANQADCggIHQAAAA==.',
To='Toadvoker:BAAANQAECgYIDAAAAA==.Totembish:BAAANQAECgIIAgAAAA==.',
Tr='Trisstan:BAAANQADCgcICgAAAA==.',
Ty='Tyster:BAAANQAECgcIDQAAAA==.',
['Tï']='Tïghtgrïp:BAAANQAECgMIAwAAAA==.',
['Tø']='Tørmented:BAAANQADCgUIBQAAAA==.',
Un='Undol:BAAANQADCgUICQABNQADCggIGAABAAAAAA==.',
Ve='Veloth:BAABNQAECoEgAAMHAAkJtB/0HgAaAwAHAAkJkx30HgAaAwAIAAUJiCCaBwClAQAAAA==.Verminus:BAAANQAECgQIBAAAAA==.',
Vi='Viho:BAAANQAECgQIBgAAAA==.',
Vy='Vyinson:BAAANQADCgMIBAABNQAECgIIBAABAAAAAA==.',
We='Weechuup:BAAANQADCgUICAAAAA==.',
Wi='Willmar:BAAANQAECgEIAQAAAA==.Window:BAAANQADCggICAABNQAECgQIBwABAAAAAA==.Windrun:BAAANQADCgYIDAAAAA==.',
Wo='Wolf:BAAANQAECgYIDgAAAA==.Woodtique:BAAANQADCgQICAAAAA==.',
Xa='Xandercruise:BAAANQAECgEIAQAAAA==.',
Xu='Xuchilbara:BAAANQAECgEIAQAAAA==.',
Ya='Yamato:BAAANQADCggIDAAAAA==.',
Zb='Zbelladonna:BAAANQADCggIEgABNQAECgkJGAAJAOgbAA==.',
Ze='Zezera:BAAANQADCgUIDAAAAA==.',
Zh='Zhades:BAABNQAECoEYAAMJAAkJ6BvOCgCsAgAJAAgJ6xvOCgCsAgAKAAkJxBLCJgAEAgAAAA==.Zhort:BAAANQADCgIIAgAAAA==.',
Zu='Zultan:BAAANQAECgQIBwAAAA==.',
Zy='Zynblasted:BAAANQADCgQIBAAAAA==.',
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
