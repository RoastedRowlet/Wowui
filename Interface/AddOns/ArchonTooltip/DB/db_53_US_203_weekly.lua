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

local lookup = {'Unknown-Unknown','Druid-Balance','Evoker-Preservation','Mage-Arcane','Mage-Frost',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aanuanaela:BAAANQAECgUIBwAAAA==.',
Ab='Absens:BAAANQAECgUICQAAAA==.',
Ad='Adorian:BAAANQAECgQIBAABNQAECgYIDgABAAAAAA==.Adwillon:BAAANQAECgIIAgAAAA==.',
Af='Aforceofone:BAAANQADCgYIBgAAAA==.',
Ag='Aggretsuko:BAAANQAECgUIBQAAAA==.',
Al='Alex:BAAANQAECgMIAwAAAA==.Aluviel:BAAANQAFFAEIAQABNQAFFAUICgACAJojAA==.Alyslia:BAAANQABCggIEAAAAA==.',
An='Anamuht:BAAANQAECgQIBwABNQAECgUICwABAAAAAA==.Annaday:BAAANQAECgEIAQAAAA==.Antiock:BAAANQAECgYIDgAAAA==.Anyamonka:BAAANQAECgIIAgAAAA==.',
As='Ashbrínger:BAAANQAECgYICwAAAA==.',
At='Atua:BAAANQADCgQIBQAAAA==.',
Av='Averax:BAAANQAECgQIBgAAAA==.Avylbrew:BAAANQADCgUICAAAAA==.',
Ay='Aylakaye:BAAANQADCgEIAQAAAA==.',
Az='Azzathoth:BAAANQADCggICAAAAA==.',
Ba='Babybilly:BAAANQAECgUIDAAAAA==.Backpack:BAAANQADCgUIBQAAAA==.Bananawaffle:BAAANQADCgEIAQAAAA==.Bandan:BAAANQAECgQICAAAAA==.Bato:BAAANQADCgUIDAAAAA==.',
Be='Beefjurkey:BAAANQAECgQICQAAAA==.',
Bi='Bier:BAAANQADCgQIBAAAAA==.Bigrig:BAAANQADCgcIDgAAAA==.Bitterman:BAAANQAECgQIBwAAAA==.',
Bo='Boohoo:BAAANQABCgIIBAAAAA==.Bovinedivine:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.',
Br='Brandumb:BAAANQAECgYICgAAAA==.',
Ca='Callana:BAAANQAECgQICAAAAA==.Camedra:BAAANQAECgQICAAAAA==.Carthella:BAAANQADCgQIBAABNQAECgUIDQABAAAAAA==.Catamynyia:BAAANQADCggIFgAAAA==.',
Cc='Cchaos:BAAANQAECgMIAwAAAA==.',
Ce='Celaborn:BAAANQAECgQIBQAAAA==.',
Ch='Chucknoris:BAAANQADCgYIEQAAAA==.',
Cr='Crankadin:BAAANQAECggIAQABNQADCggIEQABAAAAAA==.Crispysham:BAAANQAECgUICQAAAA==.Cruciö:BAAANQADCggIDAAAAA==.Crànk:BAAANQADCggIEQAAAA==.Cránk:BAAANQADCggICAABNQADCggIEQABAAAAAA==.',
Cu='Cullyeskie:BAAANQAECgEIAQAAAA==.Curveball:BAAANQAECgMIAwABNQAECgQIBwABAAAAAA==.',
Cy='Cyniar:BAAANQAECgQIBwAAAA==.',
Da='Darkstär:BAAANQAECgUICwAAAA==.',
De='Deacon:BAAANQAECgQIBgAAAA==.Deadzly:BAAANQAECgcIEwAAAA==.Deathknights:BAAANQADCgMIAwAAAA==.Deeanne:BAAANQADCgUIDAAAAA==.Deepfriar:BAAANQAECgUICwAAAA==.Demoniiks:BAAANQABCgQIBAAAAA==.Derailed:BAAANQAECgUIBQAAAA==.Dethwing:BAAANQABCgIIBAAAAA==.Dewsbelle:BAAANQADCggIFAAAAA==.',
Di='Diablognomis:BAAANQADCgcIDwAAAA==.Dirtman:BAAANQAECgUICQAAAA==.Distillate:BAAANQADCgYIEgAAAA==.',
Dk='Dkrise:BAAANQADCgIIAgABNQAECgcIEwABAAAAAA==.',
Do='Dolphina:BAAANQADCgYIBwAAAA==.Donny:BAAANQAECgUICAAAAA==.',
Dr='Dragonic:BAABNQAECoEcAAIDAAkJ1hjtCgCFAgADAAkJ1hjtCgCFAgAAAA==.Drewdog:BAAANQAECgEIAgAAAA==.',
Du='Dubes:BAAANQAECgUICwAAAA==.Dunbartian:BAAANQAECgIIAgAAAA==.',
Ei='Eirote:BAAANQAECgUICwAAAA==.',
El='Elarris:BAAANQADCgYIBgAAAA==.Eldari:BAAANQAECgQICAAAAA==.Eledron:BAAANQADCggIEQAAAA==.Elyssaena:BAAANQADCggICAAAAA==.',
Em='Emotionaldmg:BAAANQAECgUIBQABNQAECggIAwABAAAAAA==.',
En='Enzojr:BAAANQAECgMIBAAAAA==.',
Er='Eriath:BAAANQAECgYIDgAAAA==.',
Ex='Exalted:BAAANQAECgIIBAABNQAECgkJHAADANYYAA==.',
Ey='Eye:BAAANQAECgUIBgAAAA==.',
Fa='Faranth:BAAANQAECgUICwAAAA==.',
Fe='Felynne:BAAANQADCgYICQAAAA==.Feo:BAAANQAECgEIAQAAAA==.Ferum:BAAANQAECgYIEQAAAA==.',
Fi='Fionnan:BAAANQAECgQIBwABNQAECgUICwABAAAAAA==.Fizwidget:BAAANQADCgEIAQAAAA==.',
Fr='Freezia:BAAANQADCggIFQAAAA==.Fryeguy:BAAANQADCgQIBAAAAA==.',
Fu='Fudo:BAAANQAECgEIAQAAAA==.Fudoswrath:BAAANQADCgMIAwAAAA==.Funkysoup:BAAANQAECgUICwAAAA==.',
['Fò']='Fòrced:BAAANQADCgUIBQAAAA==.',
Ga='Gallium:BAAANQADCgcIBgAAAA==.',
Ge='Gehena:BAAANQAECgQIBAABNQAECgQICAABAAAAAQ==.',
Gi='Girthquake:BAAANQAECgMIAwAAAA==.',
Gl='Glow:BAAANQADCggICAAAAA==.',
Go='Goof:BAAANQAECgUICQAAAA==.',
Gr='Griz:BAAANQAECgYIBgAAAA==.Grossevache:BAAANQADCgIIBAAAAA==.',
Ha='Haddor:BAAANQAECgEIAQAAAA==.Halfheart:BAAANQAECgQIBgAAAA==.Hankerin:BAAANQADCgUIBgAAAA==.Harpomage:BAAANQADCgcIEwAAAA==.Haunter:BAAANQAECgUICQAAAA==.',
He='Heimdallr:BAAANQADCggIEAAAAA==.Heisenborg:BAAANQAECgQIBAAAAA==.Helldin:BAAANQAECgEIAQAAAA==.',
Hi='Hilite:BAAANQAECgQICAAAAA==.Himothyjr:BAAANQADCgMIAwAAAA==.',
Ho='Holific:BAAANQAECgUICQAAAA==.Hotrodranger:BAAANQAECgQIBgAAAA==.',
Hu='Hunters:BAAANQADCgYIBgAAAA==.Hut:BAABNQAECoEeAAICAAkJPCO7BQB+AwACAAkJPCO7BQB+AwAAAA==.',
Hy='Hypearione:BAAANQABCgEIAQAAAA==.',
Ia='Iambohike:BAAANQADCgQIBQAAAA==.',
Ic='Icycritties:BAAANQADCgIIAgAAAA==.',
Ih='Iheals:BAAANQADCgIIAgAAAA==.',
Im='Immortal:BAAANQAECgQIBwAAAA==.',
Is='Iskra:BAAANQADCgIIAgAAAA==.Ispithotfire:BAAANQABCgQIBgAAAA==.',
Iu='Iu:BAAANQAECgIIAQABNQAECggIEwABAAAAAA==.',
Ja='Jadecross:BAAANQADCgIIAgAAAA==.Javan:BAAANQADCgIIAgAAAA==.',
Je='Jerryatric:BAAANQAECgMIBAAAAA==.',
Ji='Jiri:BAAANQABCgYIDAAAAA==.',
Jk='Jkmno:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.',
Jo='Joeyrains:BAAANQADCgQIBAAAAA==.',
Ju='Justblaze:BAAANQAECgQIBAAAAA==.Justincasê:BAAANQABCgMIAwAAAA==.',
Ka='Kallikan:BAAANQAECgQIBgAAAA==.Kamidk:BAAANQADCgQIBAABNQAECgQICgABAAAAAA==.Kamuri:BAAANQADCgEIAQAAAA==.Kasteen:BAAANQADCgcIFgAAAA==.Katia:BAAANQADCgYIEQAAAA==.Kaøs:BAAANQAECgEIAgAAAA==.',
Kd='Kdoggparker:BAAANQABCgYICQAAAA==.',
Ke='Kementari:BAAANQAECgIIAgAAAA==.Kenzaki:BAAANQAECgYIDwAAAA==.',
Kh='Khaladin:BAAANQADCgYICAAAAA==.Khaosreborn:BAAANQADCgUIAQAAAA==.Khaotic:BAAANQADCgIIAgAAAA==.',
Ki='Kilaaz:BAAANQAECgUICAAAAA==.Kirveka:BAAANQABCgQIBAAAAA==.',
Kl='Kliticaldk:BAAANQADCgUIBQAAAA==.Kliticalwar:BAAANQAECgUIBQAAAA==.Klothys:BAAANQAECgMIAwAAAA==.',
Ko='Ková:BAAANQADCgUICwAAAA==.',
Ku='Kuani:BAAANQADCgcICQABNQAECgQICAABAAAAAA==.',
La='Landre:BAAANQADCgQIBgAAAA==.Lathray:BAAANQAECgEIAQAAAA==.Lazerous:BAAANQADCgIIAgAAAA==.',
Le='Lealoo:BAAANQAECgUIBgAAAA==.Legolard:BAAANQAECgMIBAAAAA==.Leleia:BAAANQADCggIGgAAAA==.',
Lh='Lhera:BAAANQAECgQIBwABNQAECgYIDAABAAAAAA==.',
Li='Liath:BAAANQAECgEIAQAAAA==.Lichtenberg:BAAANQAECgUICwAAAA==.Linddori:BAAANQAECgQIBAABNQAECgQIBAABAAAAAA==.Liori:BAAANQADCgYICgAAAA==.Lirillia:BAAANQAECgQIBAAAAA==.Lirillïa:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Lo='Locdon:BAAANQABCgIIAgABNQAECgUICAABAAAAAA==.Lodestone:BAAANQADCgIIAgAAAA==.Lokk:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.Lovelydread:BAAANQAECgEIAQAAAA==.',
Lu='Lunabug:BAAANQAECgIIAgAAAA==.Lupinos:BAAANQADCgIIAQAAAA==.',
Ly='Lyadra:BAAANQAECgQIBwAAAA==.',
Ma='Mackito:BAAANQADCggIDgAAAA==.Madan:BAAANQADCggIGQAAAA==.Mahoushojou:BAAANQAECgIIAgAAAA==.Malasminna:BAAANQADCgcIFgAAAA==.Malehorelock:BAAANQAECgEIAQAAAA==.Malicioun:BAAANQABCgYICgAAAA==.Malkariss:BAAANQAECgQIBgAAAA==.Mammadruid:BAAANQADCgcIHgAAAA==.Mauldis:BAAANQAECgQIBgAAAA==.',
Me='Meryl:BAAANQAECgYIDgAAAA==.',
Mi='Miaka:BAAANQAECgUICgAAAA==.Minth:BAAANQADCgcIDQAAAA==.Misfire:BAAANQAECgQIBwAAAA==.',
Mo='Moghroth:BAAANQAECgQIBgAAAA==.Molykote:BAAANQADCgYICwAAAA==.Monks:BAAANQADCgQIBAAAAA==.Monsterbabe:BAAANQADCgQIBQAAAA==.Moreleath:BAAANQADCgMIBAAAAA==.',
Mu='Mugzypatron:BAAANQADCgcIBwAAAA==.Murdrmitts:BAAANQAECgEIAQAAAA==.',
['Mã']='Mãtador:BAAANQAECgcIBwABNQAECgcIEgABAAAAAA==.',
['Mä']='Mätadør:BAAANQAECgcIEgAAAA==.',
Na='Nahryn:BAAANQAECgQIBgAAAA==.',
Ne='Nedina:BAAANQADCgUIBQAAAA==.Nerbert:BAAANQADCgYIBgABNQAECgUIDQABAAAAAA==.Neretsym:BAAANQAECgQIBwAAAA==.',
Ni='Nineva:BAAANQAECgEIAQAAAA==.',
No='Nobas:BAAANQAECgUICwAAAA==.Nonoa:BAAANQADCgQIBQAAAA==.',
Oc='Octavien:BAAANQADCgIIAgAAAA==.',
Og='Ogr:BAAANQADCgMIAwAAAA==.',
On='Onlyfeet:BAAANQADCgYICgAAAA==.',
Op='Oppgjør:BAAANQAECgEIAQAAAA==.',
Or='Oreeree:BAAANQAECgIIAgAAAA==.Ormr:BAAANQAECgUIDQAAAA==.',
Os='Osteo:BAAANQAECgMIAwAAAA==.Osteoprime:BAAANQADCgUIBQAAAA==.',
Ou='Ouron:BAAANQAECgMIBAAAAA==.Outofmana:BAAANQADCgQIBAAAAA==.',
Pa='Pagoda:BAAANQADCgYIBgAAAA==.Papashrimps:BAABNQAECoEZAAIEAAgJwxZ0VQBJAgAEAAgJwxZ0VQBJAgAAAA==.',
Pe='Penelopee:BAAANQADCgYIBgAAAA==.Percy:BAAANQADCgYIBgAAAA==.',
Ph='Phatcow:BAAANQADCgEIAQAAAA==.',
Pl='Placeholder:BAAANQAECgQIBgAAAA==.',
Po='Pojoevokest:BAAANQADCggIHQAAAA==.Pontifex:BAAANQAECgUICQAAAA==.Portandmorph:BAAANQAECgMIBAAAAA==.',
Pr='Priests:BAAANQADCgQIBgAAAA==.Prone:BAAANQAECgUICwAAAA==.Protarada:BAAANQADCgEIAQAAAA==.',
Qu='Quietmind:BAAANQAECgIIAgAAAA==.Quinnifred:BAAANQADCgYIEwAAAA==.',
Ra='Raakotah:BAAANQAECgcIEgAAAA==.Raasclaat:BAAANQADCgUIBgAAAA==.Raelo:BAAANQAECgQIBgAAAA==.Rainbowflake:BAAANQAECgIIAgAAAA==.Raiseurmug:BAAANQAECgUICwAAAA==.Rakash:BAAANQADCgcIBwAAAA==.Rarg:BAAANQAECgcIEgAAAA==.Ravia:BAAANQAECgEIAQAAAA==.',
Re='Rendysavage:BAAANQADCgEIAQAAAA==.Resco:BAAANQADCggIEgAAAA==.',
Ri='Riddle:BAAANQAECgUICQAAAA==.Rize:BAAANQAECgMIAwABNQAECgcIEwABAAAAAA==.',
Ro='Rosenrott:BAAANQAECgQICAAAAA==.Rosepiercer:BAAANQADCggIFQAAAA==.Rouz:BAAANQAECgQIBgAAAA==.',
Ry='Ryoto:BAAANQAECgIIAgAAAA==.',
Sa='Samandean:BAAANQADCggIFQABNQAECgUIBgABAAAAAA==.',
Se='Sellena:BAAANQAECgEIAQABNQAECgUIBgABAAAAAA==.',
Sh='Shakenn:BAAANQADCgEIAQAAAA==.Shandow:BAABNQAECoEdAAIFAAgJSSAsAgC5AgAFAAgJSSAsAgC5AgAAAA==.Shansoracle:BAAANQAECgMIBwABNQAECggIHQAFAEkgAA==.Shed:BAAANQAECgQIBAABNQAECgkJHgACADwjAA==.Sheislegend:BAAANQADCgYIEQAAAA==.Shelby:BAAANQAECgQICAAAAA==.Shocked:BAAANQAECggIAwAAAA==.',
Si='Siccinok:BAAANQAECgUICQAAAA==.Sindorian:BAAANQADCgUIEwABNQAECgEIAQABAAAAAA==.Sixhundrdlbs:BAAANQAECggIEQABNQABCgIIBAABAAAAAA==.',
Sl='Slimped:BAAANQADCgYICwAAAA==.',
Sn='Sneakybato:BAAANQADCgUIBQAAAA==.',
So='Sofie:BAAANQADCgQIBAABNQAECgUICwABAAAAAA==.Solarial:BAAANQADCgYIEQAAAA==.Solastra:BAAANQAECgQIBgAAAA==.Soramai:BAAANQADCgcICgAAAA==.Soth:BAAANQAECgUICwAAAA==.',
St='Starlyvana:BAAANQAECgcIBwAAAA==.Staryxia:BAAANQAECgcIEQAAAA==.Steamdruid:BAAANQADCggICQABNQAECgUICwABAAAAAA==.Steephany:BAAANQADCgMIBAAAAA==.Stonecross:BAAANQAECgQIBQAAAA==.Stormbolt:BAAANQAECgQIBwAAAA==.Stormspirit:BAAANQADCggIEwAAAA==.Striggen:BAAANQADCgYIEQAAAA==.',
Su='Sugarsham:BAAANQAECgMIBgAAAA==.Sulwen:BAACNQAFFIEKAAICAAUJmiN9AQAfAgACAAUJmiN9AQAfAgA1AAQKgR0AAgIACQmUJrUAAOwDAAIACQmUJrUAAOwDAAAA.Sumerset:BAAANQAECgMIAwAAAA==.Sundave:BAAANQAECgEIAgAAAA==.Supaflytnt:BAAANQAECgMIAwAAAA==.Sustia:BAAANQADCggIEAAAAA==.',
Ta='Taera:BAAANQAECgQICAAAAA==.Talavenn:BAAANQAECgUICQAAAA==.Tarage:BAAANQADCggIDQAAAA==.Taurîel:BAAANQADCgYIBgAAAA==.',
Te='Tectoniiks:BAAANQADCggIDwAAAA==.Tedds:BAAANQAECgQIBwAAAA==.Teds:BAAANQADCgYICwAAAA==.Tempus:BAAANQAECgMIAwAAAA==.Teriko:BAAANQAECgQICAAAAA==.Teviro:BAAANQADCgEIAQABNQAECgYIDAABAAAAAA==.',
Th='Thequixote:BAAANQAECgEIAQAAAA==.',
To='Toaderic:BAAANQAECgQICAAAAA==.Tots:BAAANQAECgYIDgAAAA==.Toxictotes:BAAANQADCgEIAQAAAA==.',
Ty='Tyraèl:BAAANQAECgcIDgAAAA==.Tyzy:BAAANQAECgcIEQAAAA==.',
Va='Valenora:BAAANQAECgQIBAAAAA==.Valvitor:BAAANQADCgEIAQAAAA==.Varuz:BAAANQAECgUICQAAAA==.Varyz:BAAANQADCgIIAgABNQAECgUICQABAAAAAA==.',
Ve='Velanie:BAAANQAECgEIAQAAAA==.Veloon:BAAANQAECgMIBQAAAA==.Verinari:BAAANQADCgUIDgAAAA==.',
Vi='Vipul:BAAANQADCgUIDQAAAA==.Viridria:BAAANQADCgQIBAABNQADCgcIDQABAAAAAA==.Vityazi:BAAANQADCggIHAAAAA==.',
Vl='Vlado:BAAANQADCgIIAgAAAA==.',
Vo='Voodoobootie:BAAANQABCgYIBgAAAA==.',
['Vè']='Vè:BAAANQAECgIIAgAAAA==.',
Wa='Warriors:BAAANQAECgYIDgAAAA==.Wartooth:BAAANQAECgQIBgAAAA==.Wassergott:BAAANQADCgYIBgAAAA==.',
We='Webicus:BAAANQAECgEIAQAAAA==.Wendee:BAAANQADCggIFQAAAA==.',
Wh='Whitley:BAAANQAECgUIBgAAAA==.',
Wi='Wildspart:BAAANQAECgEIAQAAAA==.',
Wo='Wooden:BAAANQAECgQIBgAAAA==.',
Xa='Xaphy:BAAANQAECgEIAQAAAA==.Xardots:BAAANQAECgQICAABNQAECgQIBgABAAAAAA==.',
Xi='Xiareth:BAAANQAECgQIBgAAAA==.',
['Xá']='Xároth:BAAANQAECgQIBgAAAQ==.',
Yi='Yirï:BAAANQABCgIIBAAAAA==.',
Yo='Youngjeezy:BAAANQADCggICQAAAA==.Yoursinpride:BAAANQAECggIDgAAAA==.',
Za='Zackor:BAAANQADCgUIDAAAAA==.',
Ze='Ze:BAAANQADCgQIBAAAAA==.Zervann:BAAANQADCgYIBgAAAA==.',
Zi='Ziska:BAAANQADCgIIAgAAAA==.',
Zo='Zorithic:BAAANQAECgEIAQAAAA==.',
Zy='Zyde:BAAANQADCgMIAwABNQAECgUICQABAAAAAA==.',
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
