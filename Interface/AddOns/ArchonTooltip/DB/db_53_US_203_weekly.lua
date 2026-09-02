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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aanuanaela:BAAANQADCggIDwAAAA==.',
Ab='Absens:BAAANQAECgEIAQAAAA==.',
Ad='Adwillon:BAAANQAECgEIAQAAAA==.',
Al='Alex:BAAANQAECgIIAgAAAA==.Alyslia:BAAANQABCgQIBgAAAA==.',
An='Anamuht:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.Annaday:BAAANQADCggIDgAAAA==.Antiock:BAAANQAECgQICAAAAA==.Anyamonka:BAAANQADCggIDQAAAA==.',
As='Ashbrínger:BAAANQAECgEIAQAAAA==.',
At='Atua:BAAANQADCgMIBAAAAA==.',
Av='Averax:BAAANQADCggIDQAAAA==.Avylbrew:BAAANQADCgQIBAAAAA==.',
Ay='Aylakaye:BAAANQADCgEIAQAAAA==.',
Az='Azzathoth:BAAANQADCggICAAAAA==.',
Ba='Babybilly:BAAANQAECgMIAwAAAA==.Backpack:BAAANQADCgUIBQAAAA==.Bananawaffle:BAAANQADCgEIAQAAAA==.Bandan:BAAANQADCggICAAAAA==.Bato:BAAANQADCgUIBwAAAA==.',
Be='Beefjurkey:BAAANQADCggIDQAAAA==.',
Bi='Bitterman:BAAANQADCggIDgAAAA==.',
Bo='Bohikeog:BAAANQADCgMIBAAAAA==.Bovinedivine:BAAANQADCgUIBQABNQADCggIDgABAAAAAA==.',
Br='Brandumb:BAAANQADCgEIAQAAAA==.',
Ca='Camedra:BAAANQAECgIIAgAAAA==.Catamynyia:BAAANQADCggIDgAAAA==.',
Cc='Cchaos:BAAANQADCgQIBAAAAA==.',
Ce='Celaborn:BAAANQADCgcIDQAAAA==.',
Ch='Chucknoris:BAAANQADCgMIBQAAAA==.',
Cr='Crankadin:BAAANQADCggICAABNQADCgcICQABAAAAAA==.Crispysham:BAAANQADCggICQAAAA==.Cruciö:BAAANQADCgQIBAAAAA==.Crànk:BAAANQADCgcICQAAAA==.',
Cu='Cullyeskie:BAAANQADCggICAAAAA==.Curveball:BAAANQADCgcICwABNQADCggIDgABAAAAAA==.',
Cy='Cyniar:BAAANQADCgcIDAAAAA==.',
Da='Darkstär:BAAANQAECgIIAgAAAA==.',
De='Deacon:BAAANQADCggIDQAAAA==.Deadzly:BAAANQAECgMIAwAAAA==.Deathknights:BAAANQADCgMIAwAAAA==.Deeanne:BAAANQADCgQIBwAAAA==.Deepfriar:BAAANQAECgIIAgAAAA==.Demoniiks:BAAANQABCgQIBAAAAA==.Derailed:BAAANQAECgIIAgAAAA==.Dewsbelle:BAAANQADCgQIBwAAAA==.',
Di='Diablognomis:BAAANQADCgUICAAAAA==.Dirtman:BAAANQADCgUIBQAAAA==.Distillate:BAAANQADCgYIDAAAAA==.',
Dk='Dkrise:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.',
Do='Dolphina:BAAANQADCgMIBAAAAA==.Donny:BAAANQAECgEIAQAAAA==.',
Dr='Dragonic:BAAANQAECgYICQAAAA==.Drewdog:BAAANQAECgEIAQAAAA==.',
Du='Dubes:BAAANQAECgIIAgAAAA==.Dunbartian:BAAANQADCgYICAAAAA==.',
Ei='Eirote:BAAANQAECgIIAgAAAA==.',
El='Eldari:BAAANQADCgcIDAAAAA==.Eledron:BAAANQADCgYICQAAAA==.',
En='Enzojr:BAAANQAECgEIAQAAAA==.',
Er='Eriath:BAAANQAECgMIAwAAAA==.',
Ex='Exalted:BAAANQAECgIIAgABNQAECgYICQABAAAAAA==.',
Ey='Eye:BAAANQAECgIIAgAAAA==.',
Fa='Faranth:BAAANQAECgIIAgAAAA==.',
Fe='Felynne:BAAANQADCgYIBwAAAA==.Feo:BAAANQADCggIDgAAAA==.Ferum:BAAANQAECgQIBQAAAA==.',
Fi='Fionnan:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.Fizwidget:BAAANQADCgEIAQAAAA==.',
Fr='Freezia:BAAANQADCgcIDQAAAA==.Fryeguy:BAAANQADCgQIBAAAAA==.',
Fu='Fudo:BAAANQADCggIDgAAAA==.Funkysoup:BAAANQAECgUICwAAAA==.',
Ga='Gallium:BAAANQADCgcIBgAAAA==.',
Gi='Girthquake:BAAANQADCgYICwAAAA==.',
Go='Goof:BAAANQAECgEIAQAAAA==.',
Gr='Griz:BAAANQADCgUIBQAAAA==.Grossevache:BAAANQADCgIIBAAAAA==.',
Ha='Haddor:BAAANQADCgYIDQAAAA==.Halfheart:BAAANQADCggIDgAAAA==.Hankerin:BAAANQADCgMIAwAAAA==.Harpomage:BAAANQADCgQIBgAAAA==.Haunter:BAAANQADCggICAAAAA==.',
He='Heimdallr:BAAANQADCgQIBAAAAA==.Heisenborg:BAAANQADCggIDgAAAA==.Helldin:BAAANQADCgUIBgAAAA==.',
Hi='Hilite:BAAANQADCgcIDAAAAA==.',
Ho='Holific:BAAANQADCgcIDQAAAA==.Hotrodranger:BAAANQADCggIDgAAAA==.',
Hu='Hut:BAAANQAECgcICwAAAA==.',
Ih='Iheals:BAAANQADCgIIAgAAAA==.',
Im='Immortal:BAAANQADCggIDgAAAA==.',
Is='Iskra:BAAANQADCgIIAgAAAA==.Ispithotfire:BAAANQABCgQIBgAAAA==.',
Ja='Jadecross:BAAANQADCgIIAgAAAA==.Javan:BAAANQADCgIIAgAAAA==.',
Je='Jerryatric:BAAANQADCgYICwAAAA==.',
Ju='Justblaze:BAAANQADCgIIAgAAAA==.',
Ka='Kallikan:BAAANQADCggIDQAAAA==.Kamuri:BAAANQADCgEIAQAAAA==.Kasteen:BAAANQADCgUICAAAAA==.Katia:BAAANQADCgUIBwAAAA==.',
Ke='Kenzaki:BAAANQAECgMIBAAAAA==.',
Kh='Khaladin:BAAANQADCgYICAAAAA==.Khaosreborn:BAAANQADCgUIAQAAAA==.Khaotic:BAAANQADCgIIAgAAAA==.',
Ki='Kilaaz:BAAANQAECgMIAwAAAA==.Kirveka:BAAANQABCgIIAgAAAA==.',
Kl='Kliticaldk:BAAANQADCgUIBQAAAA==.Kliticalwar:BAAANQADCgUIBAAAAA==.Klothys:BAAANQADCgYIBgAAAA==.',
Ko='Ková:BAAANQADCgUICgAAAA==.',
Ku='Kuani:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
La='Landre:BAAANQADCgQIBgAAAA==.Lathray:BAAANQADCggIDgAAAA==.Lazerous:BAAANQADCgIIAgAAAA==.',
Le='Lealoo:BAAANQADCggIDgABNQADCggIDwABAAAAAA==.Legolard:BAAANQADCgYIDAAAAA==.Leleia:BAAANQADCggICgAAAA==.',
Lh='Lhera:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.',
Li='Liath:BAAANQADCgUICAAAAA==.Lichtenberg:BAAANQAECgIIAgAAAA==.Linddori:BAAANQADCggIDgAAAA==.',
Lo='Lodestone:BAAANQADCgIIAgAAAA==.Lovelydread:BAAANQAECgEIAQAAAA==.',
Lu='Lunabug:BAAANQAECgIIAgAAAA==.Lupinos:BAAANQADCgIIAQAAAA==.',
Ly='Lyadra:BAAANQADCggIDgAAAA==.',
Ma='Madan:BAAANQADCgYICQAAAA==.Mahoushojou:BAAANQAECgIIAgAAAA==.Malasminna:BAAANQADCgUICAAAAA==.Malehorelock:BAAANQADCgQIBAABNQADCgUICgABAAAAAA==.Malkariss:BAAANQADCggIDQAAAA==.Mammadruid:BAAANQADCgYIDgAAAA==.Mauldis:BAAANQADCggIDQAAAA==.',
Me='Meryl:BAAANQAECgMIAwAAAA==.',
Mi='Miaka:BAAANQAECgIIAgAAAA==.Minth:BAAANQADCgYIBgAAAA==.Misfire:BAAANQADCggIDgAAAA==.',
Mo='Moghroth:BAAANQADCggIDgAAAA==.Molykote:BAAANQADCgUIBgAAAA==.Monks:BAAANQADCgQIBAAAAA==.Monsterbabe:BAAANQADCgEIAQAAAA==.Moreleath:BAAANQADCgEIAQAAAA==.',
Mu='Mugzypatron:BAAANQADCgcIBwAAAA==.Murdrmitts:BAAANQADCggICAAAAA==.',
['Mã']='Mãtador:BAAANQADCggICAABNQAECgcICwABAAAAAA==.',
['Mä']='Mätadør:BAAANQAECgcICwAAAA==.',
Na='Nahryn:BAAANQADCggIDQAAAA==.',
Ne='Neretsym:BAAANQADCggIDAAAAA==.',
Ni='Nineva:BAAANQADCgQIBAAAAA==.',
No='Nobas:BAAANQAECgIIAgAAAA==.Nonoa:BAAANQADCgMIBAAAAA==.',
Oc='Octavien:BAAANQADCgIIAgAAAA==.',
Og='Ogr:BAAANQADCgMIAwAAAA==.',
Op='Oppgjør:BAAANQADCgYIBwAAAA==.',
Or='Ormr:BAAANQAECgMIAwAAAA==.',
Os='Osteo:BAAANQADCggICwAAAA==.',
Ou='Ouron:BAAANQADCgYICQAAAA==.',
Pa='Papashrimps:BAAANQAECgUIBwAAAA==.',
Ph='Phatcow:BAAANQADCgEIAQAAAA==.',
Pl='Placeholder:BAAANQADCggIDAAAAA==.',
Po='Pojoevokest:BAAANQADCggIDQAAAA==.Pontifex:BAAANQADCggIDgAAAA==.Portandmorph:BAAANQADCggIDgAAAA==.',
Pr='Priests:BAAANQADCgQIBgAAAA==.Prone:BAAANQAECgIIAgAAAA==.',
Qu='Quietmind:BAAANQADCgQIBAAAAA==.Quinnifred:BAAANQADCgYICQAAAA==.',
Ra='Raakotah:BAAANQAECgQIBQAAAA==.Raasclaat:BAAANQADCgEIAQAAAA==.Raelo:BAAANQADCggIDgAAAA==.Raiseurmug:BAAANQAECgIIAgAAAA==.Rakash:BAAANQADCgcIBwAAAA==.Rarg:BAAANQAECgYICgAAAA==.',
Re='Resco:BAAANQADCggICAAAAA==.',
Ri='Riddle:BAAANQADCggIDgAAAA==.Rize:BAAANQADCgYIBwABNQAECgQIBgABAAAAAA==.',
Ro='Rosenrott:BAAANQAECgIIAgAAAA==.Rosepiercer:BAAANQADCgcIDQAAAA==.Rouz:BAAANQADCggIDQAAAA==.',
Sa='Samandean:BAAANQADCgcIDQABNQADCggIDwABAAAAAA==.',
Se='Sellena:BAAANQADCggIDwAAAA==.',
Sh='Shakenn:BAAANQADCgEIAQAAAA==.Shandow:BAAANQAECgYICwAAAA==.Shansoracle:BAAANQAECgMIAwABNQAECgYICwABAAAAAA==.Shed:BAAANQAECgQIBAABNQAECgcICwABAAAAAA==.Sheislegend:BAAANQADCgUIBwAAAA==.Shelby:BAAANQAECgIIAgAAAA==.',
Si='Siccinok:BAAANQADCgUICQAAAA==.Sindorian:BAAANQADCgUICgAAAA==.Sixhundrdlbs:BAAANQAECgMIBAABNQABCgIIAgABAAAAAA==.',
Sl='Slimped:BAAANQADCgYICwAAAA==.',
So='Sofie:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Solarial:BAAANQADCgUIBwAAAA==.Solastra:BAAANQADCggIDQAAAA==.Soramai:BAAANQADCgIIAwAAAA==.Soth:BAAANQAECgIIAgAAAA==.',
St='Staryxia:BAAANQAECgYICgAAAA==.Steephany:BAAANQADCgEIAQAAAA==.Stonecross:BAAANQADCggICAAAAA==.Stormbolt:BAAANQAECgIIAgAAAA==.Stormspirit:BAAANQADCgYICwAAAA==.Striggen:BAAANQADCgUIBwAAAA==.',
Su='Sugarsham:BAAANQADCggICAAAAA==.Sulwen:BAAANQAFFAEIAQAAAA==.Sumerset:BAAANQADCgYICwAAAA==.Sundave:BAAANQADCgYIDAAAAA==.Sustia:BAAANQADCgMIAwAAAA==.',
Ta='Taera:BAAANQAECgIIAgAAAA==.Talavenn:BAAANQADCggIDAAAAA==.Taurîel:BAAANQADCgYIBgAAAA==.',
Te='Tedds:BAAANQADCggICAAAAA==.Tempus:BAAANQADCgcIDQAAAA==.Teriko:BAAANQADCggIEAAAAA==.',
To='Toaderic:BAAANQADCgcIDAAAAA==.Tots:BAAANQAECgMIAwAAAA==.Toxictotes:BAAANQADCgEIAQAAAA==.',
Ty='Tyraèl:BAAANQAECgIIAgAAAA==.Tyzy:BAAANQAECgQIBAAAAA==.',
Va='Valenora:BAAANQADCggIDwAAAA==.Valvitor:BAAANQADCgEIAQAAAA==.Varuz:BAAANQADCggIDgAAAA==.',
Ve='Velanie:BAAANQADCgYIBwAAAA==.Veloon:BAAANQADCgYIDAAAAA==.Verinari:BAAANQADCgQIBwAAAA==.',
Vi='Vipul:BAAANQADCgUIDQAAAA==.Viridria:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Vityazi:BAAANQADCggIDgAAAA==.',
Vl='Vlado:BAAANQADCgIIAgAAAA==.',
['Vè']='Vè:BAAANQADCgUIBAAAAA==.',
Wa='Warriors:BAAANQAECgMIAwAAAA==.Wartooth:BAAANQADCggIDQAAAA==.Wassergott:BAAANQADCgEIAQAAAA==.',
We='Webicus:BAAANQADCggIDgAAAA==.Wendee:BAAANQADCgcIDQAAAA==.',
Wh='Whitley:BAAANQAECgIIAgAAAA==.',
Wi='Wildspart:BAAANQADCggICAAAAA==.',
Wo='Wooden:BAAANQADCgIIAgAAAA==.',
Xa='Xaphy:BAAANQADCggICAAAAA==.Xardots:BAAANQAECgEIAQABNQADCggIDgABAAAAAA==.',
Xi='Xiareth:BAAANQADCggIDQAAAA==.',
['Xá']='Xároth:BAAANQADCggIDgAAAQ==.',
Yo='Yoursinpride:BAAANQAECgYIBgAAAA==.',
Za='Zackor:BAAANQADCgQIBgAAAA==.',
Zi='Ziska:BAAANQADCgIIAgAAAA==.',
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
