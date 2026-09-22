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

local lookup = {'Unknown-Unknown','Druid-Balance','DeathKnight-Blood','DeathKnight-Frost','DeathKnight-Unholy','Evoker-Devastation','Evoker-Preservation','Priest-Shadow','Paladin-Retribution','Paladin-Holy','Mage-Arcane','Mage-Frost','DemonHunter-Devourer','Druid-Guardian','Druid-Restoration','Warrior-Arms',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aanuanaela:BAAANQAECgUJDAAAAA==.',
Ab='Absens:BAAANQAECgYJDwAAAA==.Abumim:BAAANQADCggICAAAAA==.',
Ad='Adorian:BAAANQAECgQIBAABNQAECgcIEgABAAAAAA==.Adwillon:BAAANQAECgIIAgAAAA==.',
Af='Aforceofone:BAAANQADCggJCAAAAA==.',
Ag='Aggretsuko:BAAANQAECgcJDAAAAA==.',
Al='Aldonza:BAAANQADCgIJAgAAAA==.Alex:BAAANQAECgQJBQAAAA==.Aluviel:BAAANQAFFAEIAQABNQAFFAYIDgACABQlAA==.Alyslia:BAAANQABCggIFQAAAA==.',
An='Anamuht:BAAANQAECgUJDAABNQAECgYIEQABAAAAAA==.Annaday:BAAANQAECgEJAQAAAA==.Antiock:BAAANQAECgcIEgAAAA==.Anyamonka:BAAANQAECgQIBgAAAA==.',
Ap='Appalachia:BAAANQADCgYJBgAAAA==.',
Ar='Arrowmir:BAAANQABCgYJCAAAAA==.',
As='Ashbrínger:BAAANQAECgYIEQAAAA==.',
At='Atua:BAAANQADCgQJBQAAAA==.',
Av='Averax:BAAANQAECgQICgAAAA==.Avylbrew:BAAANQADCgUJCAABNQAECgIIAgABAAAAAA==.',
Ay='Aylakaye:BAAANQADCgcICAAAAA==.',
Az='Azzathoth:BAAANQADCggICAAAAA==.',
Ba='Babybilly:BAAANQAECgUIDwAAAA==.Backpack:BAAANQAECgMJAwAAAA==.Bananawaffle:BAAANQADCgEIAQAAAA==.Bandan:BAAANQAECgQICAAAAA==.Bato:BAAANQADCgUIDAAAAA==.',
Be='Beefjurkey:BAAANQAECgQICQAAAA==.',
Bh='Bhalthazar:BAAANQADCgQIBAABNQADCgYICAABAAAAAA==.',
Bi='Bier:BAAANQADCgYJBgAAAA==.Bigrig:BAAANQADCgcJEgAAAA==.Bitterman:BAAANQAECgUJDAAAAA==.',
Bo='Boohoo:BAAANQABCgIIBAAAAA==.Bovinedivine:BAAANQADCgUJBQABNQAECgQICgABAAAAAA==.',
Br='Brandumb:BAAANQAECgYICgAAAA==.',
Ca='Callana:BAAANQAECgQICAAAAA==.Camedra:BAAANQAECgUICQAAAA==.Carthella:BAAANQADCgQJBAABNQAECgYJEwABAAAAAA==.Catamynyia:BAAANQADCggJHwAAAA==.',
Cc='Cchaos:BAAANQAECgMJAwAAAA==.',
Ce='Celaborn:BAAANQAECgUICAAAAA==.',
Ch='Chimaira:BAAANQADCgMIAwAAAA==.Chucknoris:BAAANQADCgcJEQAAAA==.',
Cl='Claytonbigse:BAAANQABCgIJAgAAAA==.',
Cr='Crankadin:BAAANQAECggIAQABNQADCggIEQABAAAAAA==.Crispyquinn:BAAANQADCgUIBQAAAA==.Crispysham:BAAANQAECgYIDwAAAA==.Cruciö:BAAANQADCggIDAAAAA==.Crànk:BAAANQADCggIEQAAAA==.Cránk:BAAANQAECggJCAABNQADCggIEQABAAAAAA==.',
Cu='Cullyeskie:BAAANQAECgEIAQAAAA==.Curveball:BAAANQAECgMIAwABNQAECgUJDAABAAAAAA==.',
Cy='Cyniar:BAAANQAECgUJDAAAAA==.',
Da='Dahnu:BAAANQADCgIJAgABNQAECgEJAQABAAAAAA==.Darkhuntress:BAAANQADCgYIBgAAAA==.Darkstär:BAAANQAECgYIEQAAAA==.',
De='Deacon:BAAANQAECgQICgAAAA==.Deadzly:BAABNQAECoEhAAQDAAgKEBx+IgBCAgADAAcKMx5+IgBCAgAEAAcK6BKNJQDIAQAFAAYKLwM+YwDnAAAAAA==.Deathknights:BAAANQADCgMIAwAAAA==.Deeanne:BAAANQADCgUIDAAAAA==.Deepfriar:BAAANQAECgYIEQAAAA==.Demoniiks:BAAANQABCgcICQAAAA==.Derailed:BAAANQAECgYICQAAAA==.Dethwing:BAAANQADCgQIBAAAAA==.Dewsbelle:BAAANQADCggIFAAAAA==.',
Di='Diablognomis:BAAANQADCgcIDwAAAA==.Dirtman:BAAANQAECgYIDwAAAA==.Distillate:BAAANQADCgYIFgAAAA==.',
Dk='Dkrise:BAAANQADCgIIAgABNQAECggJHgAGAIENAA==.',
Do='Dolphina:BAAANQADCgYIBwAAAA==.Donny:BAAANQAECgUICAAAAA==.',
Dr='Dragonic:BAABNQAECoEeAAMHAAkK1hhxDgBzAgAHAAkK1hhxDgBzAgAGAAIKdw7uJQCJAAAAAA==.Drewdog:BAAANQAECgIJBQAAAA==.',
Du='Dubes:BAAANQAECgYIEQAAAA==.Dunbartian:BAAANQAECgIJBAAAAA==.',
Ei='Eirote:BAAANQAECgYIEQAAAA==.',
El='Elarris:BAAANQADCgYIBgAAAA==.Eldari:BAAANQAECgQICAAAAA==.Eledron:BAAANQADCggJGQAAAA==.Elyssaena:BAAANQADCggJDwAAAA==.',
Em='Emotionaldmg:BAAANQAECgUIBQABNQAECggIAwABAAAAAA==.',
En='Enzojr:BAAANQAECgMIBAAAAA==.',
Er='Eriath:BAABNQAECoEZAAIIAAgKNxU9FgA/AgAIAAgKNxU9FgA/AgAAAA==.',
Ex='Exalted:BAAANQAECgIIBAABNQAECgkJHgAHANYYAA==.',
Ey='Eye:BAAANQAECgUIBwAAAA==.',
Fa='Faranth:BAAANQAECgYIEQAAAA==.',
Fe='Felynne:BAAANQAECgMJAwAAAA==.Feo:BAAANQAECgEIAQAAAA==.Ferum:BAAANQAECgYIEQAAAA==.',
Fi='Fionnan:BAAANQAECgUJDAABNQAECgYIEQABAAAAAA==.Fizwidget:BAAANQADCgEIAQAAAA==.',
Fr='Freezia:BAAANQADCggIFQAAAA==.Frostigan:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Fryeguy:BAAANQADCgQIBAAAAA==.',
Fu='Fudo:BAAANQAECgEIAQAAAA==.Fudoswrath:BAAANQADCgYJCQAAAA==.Funkysoup:BAAANQAECgUICwAAAA==.',
['Fò']='Fòrced:BAAANQADCgYJCwAAAA==.',
Ga='Gallium:BAAANQAECgIJAgAAAA==.',
Ge='Gehena:BAAANQAECgQIBAABNQAECgQIDAABAAAAAQ==.',
Gi='Girthquake:BAAANQAECgQJBwAAAA==.',
Gl='Glow:BAAANQADCggJCAAAAA==.',
Go='Goof:BAAANQAECgYJDwAAAA==.',
Gr='Griz:BAAANQAECgYIBgAAAA==.Grossevache:BAAANQADCgIIBAAAAA==.',
Ha='Haddor:BAAANQAECgEJAQAAAA==.Halfheart:BAAANQAECgUICwAAAA==.Hankerin:BAAANQADCgUIBgAAAA==.Harpomage:BAAANQADCggJEwAAAA==.Haunter:BAAANQAECgUJCQAAAA==.',
He='Heimdallr:BAAANQADCggJEAAAAA==.Heisenborg:BAAANQAECgQIBAAAAA==.Helldin:BAAANQAECgEIAQAAAA==.',
Hi='Hilite:BAAANQAECgQICAAAAA==.Himothyjr:BAAANQADCgcICgAAAA==.',
Ho='Holific:BAAANQAECgYIDwAAAA==.Hotrodranger:BAAANQAECgQICgAAAA==.',
Hu='Hunters:BAAANQADCgYIBgAAAA==.Hut:BAACNQAFFIEJAAICAAUK7RWdBQClAQACAAUK7RWdBQClAQA1AAQKgSQAAgIACQqQI8IHAHIDAAIACQqQI8IHAHIDAAAA.',
Hy='Hypearione:BAAANQABCgEIAQAAAA==.',
Ia='Iambohike:BAAANQADCgUICgAAAA==.',
Ic='Icycritties:BAAANQADCgIJAgAAAA==.',
Ih='Iheals:BAAANQADCgIIAgAAAA==.',
Im='Imjustadruid:BAAANQADCgIIAgAAAA==.Immortal:BAAANQAECgUJDAAAAA==.',
Is='Iskra:BAAANQADCgIIAgAAAA==.Ispithotfire:BAAANQABCgQIBgAAAA==.',
Iu='Iu:BAAANQAECggJCQAAAA==.',
Ja='Jadecross:BAAANQADCgIIAgAAAA==.Javan:BAAANQADCgIIAgAAAA==.',
Je='Jerryatric:BAAANQAECgMIBwAAAA==.',
Ji='Jiri:BAAANQABCgYJDQAAAA==.',
Jk='Jkmno:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.',
Jo='Joeyrains:BAAANQADCgQIBAAAAA==.',
Ju='Justblaze:BAAANQAECgQIBAAAAA==.Justincasê:BAAANQABCgMJBQAAAA==.',
Ka='Kallikan:BAAANQAECgQICgAAAA==.Kamidk:BAAANQAECgQIBAAAAA==.Kamuri:BAAANQADCgUJBQAAAA==.Kasteen:BAAANQADCgcJGgAAAA==.Katia:BAAANQAECgEIAQAAAA==.Kaøs:BAAANQAECgEIAgAAAA==.',
Kd='Kdoggparker:BAAANQABCgYJCQAAAA==.',
Ke='Kementari:BAAANQAECgIIBAAAAA==.Kenzaki:BAABNQAECoEaAAIJAAgKKg+VZgDJAQAJAAgKKg+VZgDJAQAAAA==.',
Kh='Khaladin:BAAANQADCgYICAAAAA==.Khaosreborn:BAAANQADCgUIAQAAAA==.Khaotic:BAAANQADCgcICQAAAA==.',
Ki='Kilaaz:BAAANQAECgYJDQAAAA==.Kirveka:BAAANQABCgQIBAAAAA==.',
Kl='Kliticaldk:BAAANQADCgUIBQAAAA==.Kliticalwar:BAAANQAECgUIBQAAAA==.Klothys:BAAANQAECgUICAAAAA==.',
Kn='Knuts:BAAANQADCgMJAwABNQAECgYIBgABAAAAAA==.',
Ko='Ková:BAAANQADCgUJCwAAAA==.',
Ku='Kuani:BAAANQADCgcICQABNQAECgQIDAABAAAAAA==.',
La='Landre:BAAANQADCgQIBgAAAA==.Lassy:BAAANQADCgIJAgAAAA==.Lathray:BAAANQAECgEIAQAAAA==.Lazerous:BAAANQADCgcICQAAAA==.',
Le='Lealoo:BAAANQAECgYJDAAAAA==.Legolard:BAAANQAECgMIBwAAAA==.Leleia:BAAANQAECgEJAQAAAA==.',
Lh='Lhera:BAAANQAECgUIDAABNQAECgcJEwABAAAAAA==.',
Li='Liath:BAAANQAECgEJAQAAAA==.Lichtenberg:BAAANQAECgYIEQAAAA==.Linddori:BAAANQAECgQIBAABNQAECgUJCQABAAAAAA==.Liori:BAAANQADCgYIDgAAAA==.Lirillia:BAAANQAECgUJCQAAAA==.Lirillïa:BAAANQADCgYIBgABNQAECgUJCQABAAAAAA==.Lizzie:BAAANQADCgUIBQAAAA==.',
Lo='Locdon:BAAANQABCgIIAgABNQAECgUICAABAAAAAA==.Lodestone:BAAANQADCgcICQAAAA==.Loena:BAAANQADCgMIAwAAAA==.Lokk:BAAANQAECgEIAQABNQAECgYJDwABAAAAAA==.Loko:BAAANQADCggICAAAAA==.Lovelydread:BAAANQAECgEIAQAAAA==.',
Lu='Lunabug:BAAANQAECgIIAgAAAA==.Lupinos:BAAANQADCgIIAQAAAA==.',
Ly='Lyadra:BAAANQAECgUJDAAAAA==.Lyrissa:BAAANQADCgYIBgAAAA==.',
Ma='Mackito:BAAANQADCggJDgAAAA==.Madan:BAAANQADCggJIAAAAA==.Mahoushojou:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.Malasminna:BAAANQADCgcIFgAAAA==.Malehorelock:BAAANQAECgEIAQAAAA==.Malicioun:BAAANQABCggICgAAAA==.Malkariss:BAAANQAECgQICgAAAA==.Mammadruid:BAAANQAECgIJAgAAAA==.Mauldis:BAAANQAECgQICgAAAA==.',
Me='Meryl:BAABNQAECoEZAAIKAAgKzRehLgBGAgAKAAgKzRehLgBGAgAAAA==.',
Mi='Miaka:BAAANQAECgUIDwAAAA==.Minth:BAAANQADCgcIDQABNQAECgMIAwABAAAAAA==.Misfire:BAAANQAECgUJDAAAAA==.',
Mo='Moghroth:BAAANQAECgQICgAAAA==.Molykote:BAAANQADCgcIDwAAAA==.Monks:BAAANQADCgQIBAAAAA==.Monsterbabe:BAAANQADCgQIBQAAAA==.Moreleath:BAAANQADCgMIBAAAAA==.',
Mu='Mugzypatron:BAAANQADCgcIDQAAAA==.Murdrmitts:BAAANQAECgEJAQAAAA==.',
['Mã']='Mãtador:BAAANQAECggIDwAAAA==.',
['Mä']='Mätadør:BAAANQAECgcIEgABNQAECggIDwABAAAAAA==.',
Na='Nahryn:BAAANQAECgQICgAAAA==.',
Ne='Nedina:BAAANQADCgUIBQAAAA==.Nerbert:BAAANQADCgYJBgABNQAECgYJEwABAAAAAA==.Neretsym:BAAANQAECgUJDAAAAA==.',
Ni='Nineva:BAAANQAECgEJAQAAAA==.',
No='Nobas:BAAANQAECgYIEQAAAA==.Nonoa:BAAANQADCgQJBQAAAA==.',
Oc='Octavien:BAAANQADCgIIAgAAAA==.',
Og='Ogr:BAAANQADCgMIAwAAAA==.',
On='Onlyfeet:BAAANQAECgQIBAAAAA==.',
Op='Oppgjør:BAAANQAECgEIAQAAAA==.',
Or='Oreeree:BAAANQAECgIJAgAAAA==.Ormr:BAAANQAECgYJEwAAAA==.',
Os='Osteo:BAAANQAECgQIBwAAAA==.Osteoprime:BAAANQADCgUJBQAAAA==.',
Ou='Ouron:BAAANQAECgQIBwAAAA==.Outofmana:BAAANQAECgEIAQAAAA==.',
Pa='Pagoda:BAAANQADCgYJBgAAAA==.Papashrimps:BAABNQAECoEdAAMLAAkKNReHXgByAgALAAkKJBWHXgByAgAMAAEKMRq+JgBTAAAAAA==.',
Pe='Penelopee:BAAANQADCgYICgAAAA==.Percy:BAAANQADCgYJCQAAAA==.',
Ph='Phatcow:BAAANQADCgEIAQAAAA==.',
Pl='Placeholder:BAAANQAECgQICgAAAA==.',
Po='Pojoevokest:BAAANQAECgQIBAAAAA==.Pontifex:BAAANQAECgYJDwAAAA==.Portandmorph:BAAANQAECgUJCQAAAA==.Powerbottm:BAAANQAECgQIBgAAAA==.',
Pr='Priests:BAAANQADCgQIBgAAAA==.Prone:BAAANQAECgYIEQAAAA==.Protarada:BAAANQADCgEIAQAAAA==.',
Qu='Quietmind:BAAANQAECgUIBwAAAA==.Quinnifred:BAAANQADCgcIGgAAAA==.',
Ra='Raakotah:BAABNQAECoEdAAICAAkK1R29DQAqAwACAAkK1R29DQAqAwAAAA==.Raasclaat:BAAANQADCgUIBgAAAA==.Raelo:BAAANQAECgQICgAAAA==.Rainbowflake:BAAANQAECgUIBwAAAA==.Raiseurmug:BAAANQAECgYIEQAAAA==.Rakash:BAAANQADCgcIBwAAAA==.Rarg:BAABNQAECoEVAAMDAAgKWBcPLQD4AQADAAgKWBcPLQD4AQAFAAEK6QI5mwAsAAAAAA==.Ravia:BAAANQAECgEIAQAAAA==.',
Re='Rendysavage:BAAANQAECgYJBgAAAA==.Resco:BAAANQADCggIEgAAAA==.',
Ri='Riddle:BAAANQAECgYJDwAAAA==.Rize:BAAANQAECgUJCAABNQAECggJHgAGAIENAA==.',
Ro='Rosenrott:BAAANQAECgQIDAAAAA==.Rosepiercer:BAAANQAECgMIAwAAAA==.Rouz:BAAANQAECgQICgAAAA==.',
Ru='Ruddybear:BAAANQADCgIJAgAAAA==.',
Ry='Ryoto:BAAANQAECgUIBwAAAA==.',
Sa='Samandean:BAAANQAECgMIAwABNQAECgYJDAABAAAAAA==.',
Se='Sellena:BAAANQAECgEJAQABNQAECgYJDAABAAAAAA==.',
Sh='Shakenn:BAAANQADCgEIAQAAAA==.Shandow:BAABNQAECoEiAAIMAAgKSSB/AwCbAgAMAAgKSSB/AwCbAgAAAA==.Shansoracle:BAAANQAECgMIBwABNQAECggIIgAMAEkgAA==.Shed:BAAANQAECgQIBAABNQAFFAUICQACAO0VAA==.Sheislegend:BAAANQADCgYIEQAAAA==.Shelby:BAAANQAECgQIDAAAAA==.Shocked:BAAANQAECggIAwAAAA==.',
Si='Siccinok:BAAANQAECgUIEAAAAA==.Sindorian:BAAANQADCgcIGgABNQAECgEIAQABAAAAAA==.Sixhundrdlbs:BAABNQAECoEbAAINAAkKHCGlBAB2AwANAAkKHCGlBAB2AwABNQABCgIIBAABAAAAAA==.',
Sk='Skraps:BAAANQADCgEJAQAAAA==.',
Sl='Slimped:BAAANQADCgYICwAAAA==.',
Sn='Sneakybato:BAAANQADCgYJCwAAAA==.',
So='Sofie:BAAANQADCgQIBAABNQAECgYIEQABAAAAAA==.Solarial:BAAANQAECgEIAQAAAA==.Solastra:BAAANQAECgQICgAAAA==.Soramai:BAAANQADCgcICgAAAA==.Soth:BAAANQAECgYIEQAAAA==.',
St='Starlyvana:BAAANQAFFAEIAQAAAA==.Staryxia:BAAANQAECgcIEQAAAA==.Statiic:BAAANQABCgIIBQAAAA==.Steamdruid:BAAANQADCggICQABNQAECgUIDgABAAAAAA==.Steephany:BAAANQADCgMIBAAAAA==.Stonecross:BAAANQAECgUJCgAAAA==.Stormbolt:BAAANQAECgUIDAAAAA==.Stormspirit:BAAANQADCggIGwAAAA==.Striggen:BAAANQAECgEIAQAAAA==.',
Su='Sugarsham:BAAANQAECgMIBgAAAA==.Sulwen:BAACNQAFFIEOAAICAAYKFCUVAQCPAgACAAYKFCUVAQCPAgA1AAQKgR0AAgIACQqUJnYBANkDAAIACQqUJnYBANkDAAAA.Sumerset:BAAANQAECgMIAwAAAA==.Sundave:BAAANQAECgEJAgAAAA==.Supaflytnt:BAAANQAECgUJCAAAAA==.Sustia:BAAANQADCggIEAAAAA==.',
Ta='Taera:BAAANQAECgQIDAAAAA==.Talavenn:BAAANQAECgYJCwAAAA==.Tarage:BAAANQADCggIDQAAAA==.Taurîel:BAAANQADCgYIBgAAAA==.',
Te='Tectoniiks:BAAANQAECgYIBgAAAA==.Tedds:BAAANQAECgUJCAAAAA==.Teds:BAAANQADCgYICwAAAA==.Tempus:BAAANQAECgMJAwAAAA==.Teriko:BAAANQAECgYJDgAAAA==.Teviro:BAAANQADCgEIAQABNQAECgcJEwABAAAAAA==.',
Th='Thequixote:BAAANQAECgEJAQAAAA==.',
Ti='Tictok:BAAANQADCgYIBgAAAA==.',
To='Toaderic:BAAANQAECgQICAAAAA==.Tots:BAABNQAECoEZAAIOAAgKaxoTBwBxAgAOAAgKaxoTBwBxAgAAAA==.Toxictotes:BAAANQADCgEIAQAAAA==.',
Ty='Tyraèl:BAABNQAECoEWAAIKAAkK8iHQBQB5AwAKAAkK8iHQBQB5AwAAAA==.Tyzy:BAABNQAECoEcAAMCAAkKJCShBQCPAwACAAkKJCShBQCPAwAPAAcKbBXGFwD2AQAAAA==.',
Va='Valenora:BAAANQAECgUJCQAAAA==.Valvitor:BAAANQADCgEIAQAAAA==.Varuz:BAAANQAECgYJDwAAAA==.Varyz:BAAANQADCgIIAgABNQAECgYJDwABAAAAAA==.',
Ve='Velanie:BAAANQAECgEIAQAAAA==.Veloon:BAAANQAECggIDQAAAA==.Verinari:BAAANQADCgUIDgAAAA==.',
Vi='Vipul:BAAANQADCgUIDQABNQADCgYIBwABAAAAAA==.Viridria:BAAANQAECgMIAwAAAA==.Vityazi:BAAANQADCggJJQAAAA==.',
Vl='Vlado:BAAANQADCgQIBQAAAA==.',
Vo='Voodoobootie:BAAANQABCgcJBwAAAA==.',
Vy='Vy:BAAANQADCgQIBAAAAA==.',
['Vè']='Vè:BAAANQAECgcICQAAAA==.',
Wa='Warriors:BAABNQAECoEZAAIQAAgKRCFEJQDdAgAQAAgKRCFEJQDdAgAAAA==.Wartooth:BAAANQAECgQICgAAAA==.Wassergott:BAAANQADCgYIBgAAAA==.',
We='Webicus:BAAANQAECgEJAQAAAA==.Wendee:BAAANQAECgMIAwAAAA==.',
Wh='Whitley:BAAANQAECgYIDAAAAA==.',
Wi='Wildspart:BAAANQAECgEIAQAAAA==.',
Wo='Wooden:BAAANQAECgQICgAAAA==.',
Xa='Xaphy:BAAANQAECgIIAgAAAA==.Xardots:BAAANQAECgQICAABNQAECgQICgABAAAAAA==.',
Xi='Xiareth:BAAANQAECgQJBgAAAA==.',
Xy='Xyleiah:BAAANQADCgYIBgABNQAECgYIEQABAAAAAA==.',
['Xá']='Xároth:BAAANQAECgQICgAAAQ==.',
Ya='Yargue:BAAANQAECgEIAQAAAA==.',
Yi='Yirï:BAAANQABCgIIBAAAAA==.',
Yo='Youngjeezy:BAAANQAECgEJAQAAAA==.Yoursinpride:BAAANQAECggIDgAAAA==.',
Za='Zackor:BAAANQADCgUIDAAAAA==.',
Ze='Ze:BAAANQADCgYICgAAAA==.Zervann:BAAANQADCgYIBgAAAA==.',
Zi='Ziska:BAAANQADCgIIAgAAAA==.',
Zo='Zorithic:BAAANQAECgIJAwAAAA==.',
Zy='Zyde:BAAANQADCgMJAwABNQAECgYJDwABAAAAAA==.',
['Zæ']='Zælys:BAAANQAECgEIAQAAAA==.',
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
