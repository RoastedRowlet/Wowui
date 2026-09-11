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

local lookup = {'Unknown-Unknown','Druid-Balance',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aanuanaela:BAAANQAECgIIAgAAAA==.',
Ab='Absens:BAAANQAECgQIBQAAAA==.',
Ad='Adwillon:BAAANQAECgIIAgAAAA==.',
Af='Aforceofone:BAAANQADCgUIBQAAAA==.',
Ag='Aggretsuko:BAAANQADCggICAAAAA==.',
Al='Alex:BAAANQAECgMIAwAAAA==.Alyslia:BAAANQABCgQICgAAAA==.',
An='Anamuht:BAAANQAECgMIAwABNQAECgQIBgABAAAAAA==.Annaday:BAAANQADCggIFgAAAA==.Antiock:BAAANQAECgYIDgAAAA==.Anyamonka:BAAANQAECgIIAgAAAA==.',
As='Ashbrínger:BAAANQAECgQIBQAAAA==.',
At='Atua:BAAANQADCgQIBQAAAA==.',
Av='Averax:BAAANQAECgIIAgAAAA==.Avylbrew:BAAANQADCgUICAAAAA==.',
Ay='Aylakaye:BAAANQADCgEIAQAAAA==.',
Az='Azzathoth:BAAANQADCggICAAAAA==.',
Ba='Babybilly:BAAANQAECgUICAAAAA==.Backpack:BAAANQADCgUIBQAAAA==.Bananawaffle:BAAANQADCgEIAQAAAA==.Bandan:BAAANQAECgQIBAAAAA==.Bato:BAAANQADCgUIDAAAAA==.',
Be='Beefjurkey:BAAANQAECgQIBgAAAA==.',
Bi='Bier:BAAANQADCgQIBAAAAA==.Bigrig:BAAANQADCgcIBwAAAA==.Bitterman:BAAANQAECgMIAwAAAA==.',
Bo='Bohikeog:BAAANQADCgQIBQAAAA==.Boohoo:BAAANQABCgIIBAAAAA==.Bovinedivine:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Br='Brandumb:BAAANQAECgUIBwAAAA==.',
Ca='Callana:BAAANQAECgIIAwAAAA==.Camedra:BAAANQAECgQIBgAAAA==.Carthella:BAAANQADCgQIBAABNQAECgUICAABAAAAAA==.Catamynyia:BAAANQADCggIFgAAAA==.',
Cc='Cchaos:BAAANQADCgQIBwAAAA==.',
Ce='Celaborn:BAAANQAECgEIAQAAAA==.',
Ch='Chucknoris:BAAANQADCgYICwAAAA==.',
Cr='Crankadin:BAAANQADCggICAABNQADCggIEQABAAAAAA==.Crispysham:BAAANQAECgMIBAAAAA==.Cruciö:BAAANQADCggIDAAAAA==.Crànk:BAAANQADCggIEQAAAA==.',
Cu='Cullyeskie:BAAANQADCggIEAAAAA==.Curveball:BAAANQAECgMIAwABNQAECgMIAwABAAAAAA==.',
Cy='Cyniar:BAAANQAECgMIAwAAAA==.',
Da='Darkstär:BAAANQAECgQIBgAAAA==.',
De='Deacon:BAAANQAECgIIAgAAAA==.Deadzly:BAAANQAECgYIDQAAAA==.Deathknights:BAAANQADCgMIAwAAAA==.Deeanne:BAAANQADCgUIDAAAAA==.Deepfriar:BAAANQAECgQIBgAAAA==.Demoniiks:BAAANQABCgQIBAAAAA==.Derailed:BAAANQAECgIIAgAAAA==.Dethwing:BAAANQABCgIIBAAAAA==.Dewsbelle:BAAANQADCgUIDAAAAA==.',
Di='Diablognomis:BAAANQADCgcIDwAAAA==.Dirtman:BAAANQAECgQIBAAAAA==.Distillate:BAAANQADCgYIEgAAAA==.',
Dk='Dkrise:BAAANQADCgIIAgABNQAECgcIDAABAAAAAA==.',
Do='Dolphina:BAAANQADCgQIBQAAAA==.Donny:BAAANQAECgUIBgAAAA==.',
Dr='Dragonic:BAAANQAECgcIEAAAAA==.Drewdog:BAAANQAECgEIAQAAAA==.',
Du='Dubes:BAAANQAECgQIBgAAAA==.Dunbartian:BAAANQADCggIEAAAAA==.',
Ei='Eirote:BAAANQAECgQIBgAAAA==.',
El='Elarris:BAAANQADCgYIBgAAAA==.Eldari:BAAANQAECgQIBAAAAA==.Eledron:BAAANQADCgYICQAAAA==.Elyssaena:BAAANQADCggICAAAAA==.',
En='Enzojr:BAAANQAECgMIBAAAAA==.',
Er='Eriath:BAAANQAECgUICAAAAA==.',
Ex='Exalted:BAAANQAECgIIBAABNQAECgcIEAABAAAAAA==.',
Ey='Eye:BAAANQAECgMIAwAAAA==.',
Fa='Faranth:BAAANQAECgQIBgAAAA==.',
Fe='Felynne:BAAANQADCgYIBwAAAA==.Feo:BAAANQADCggIFgAAAA==.Ferum:BAAANQAECgYICwAAAA==.',
Fi='Fionnan:BAAANQAECgMIAwABNQAECgQIBgABAAAAAA==.Fizwidget:BAAANQADCgEIAQAAAA==.',
Fr='Freezia:BAAANQADCgcIDQAAAA==.Fryeguy:BAAANQADCgQIBAAAAA==.',
Fu='Fudo:BAAANQADCggIFgAAAA==.Funkysoup:BAAANQAECgUICwAAAA==.',
Ga='Gallium:BAAANQADCgcIBgAAAA==.',
Gi='Girthquake:BAAANQADCggIEwAAAA==.',
Gl='Glow:BAAANQADCggICAAAAA==.',
Go='Goof:BAAANQAECgQIBQAAAA==.',
Gr='Griz:BAAANQAECgQIBAAAAA==.Grossevache:BAAANQADCgIIBAAAAA==.',
Ha='Haddor:BAAANQADCggIFQAAAA==.Halfheart:BAAANQAECgQIBAAAAA==.Hankerin:BAAANQADCgMIAwAAAA==.Harpomage:BAAANQADCgYIDAAAAA==.Haunter:BAAANQAECgQIBAAAAA==.',
He='Heimdallr:BAAANQADCggIDAAAAA==.Heisenborg:BAAANQAECgQIBAAAAA==.Helldin:BAAANQADCgUIBgAAAA==.',
Hi='Hilite:BAAANQAECgQIBAAAAA==.',
Ho='Holific:BAAANQAECgQIBAAAAA==.Hotrodranger:BAAANQAECgIIAgAAAA==.',
Hu='Hunters:BAAANQADCgYIBgAAAA==.Hut:BAAANQAFFAIIAgAAAA==.',
Ic='Icycritties:BAAANQADCgIIAgAAAA==.',
Ih='Iheals:BAAANQADCgIIAgAAAA==.',
Im='Immortal:BAAANQAECgMIAwAAAA==.',
Is='Iskra:BAAANQADCgIIAgAAAA==.Ispithotfire:BAAANQABCgQIBgAAAA==.',
Ja='Jadecross:BAAANQADCgIIAgAAAA==.Javan:BAAANQADCgIIAgAAAA==.',
Je='Jerryatric:BAAANQAECgEIAQAAAA==.',
Ji='Jiri:BAAANQABCgYICwAAAA==.',
Jk='Jkmno:BAAANQADCgMIAwAAAA==.',
Jo='Joeyrains:BAAANQADCgQIBAAAAA==.',
Ju='Justblaze:BAAANQAECgEIAQAAAA==.',
Ka='Kallikan:BAAANQAECgIIAgAAAA==.Kamidk:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Kamuri:BAAANQADCgEIAQAAAA==.Kasteen:BAAANQADCgcIDwAAAA==.Katia:BAAANQADCgYIDQAAAA==.Kaøs:BAAANQADCgUIBQAAAA==.',
Ke='Kementari:BAAANQABCgYICQAAAA==.Kenzaki:BAAANQAECgUICQAAAA==.',
Kh='Khaladin:BAAANQADCgYICAAAAA==.Khaosreborn:BAAANQADCgUIAQAAAA==.Khaotic:BAAANQADCgIIAgAAAA==.',
Ki='Kilaaz:BAAANQAECgUICAAAAA==.Kirveka:BAAANQABCgQIBAAAAA==.',
Kl='Kliticaldk:BAAANQADCgUIBQAAAA==.Kliticalwar:BAAANQAECgIIAgAAAA==.Klothys:BAAANQADCgYIBgAAAA==.',
Ko='Ková:BAAANQADCgUICwAAAA==.',
Ku='Kuani:BAAANQADCgcICQABNQAECgIIBAABAAAAAA==.',
La='Landre:BAAANQADCgQIBgAAAA==.Lathray:BAAANQADCggIFgAAAA==.Lazerous:BAAANQADCgIIAgAAAA==.',
Le='Lealoo:BAAANQAECgEIAQAAAA==.Legolard:BAAANQAECgEIAQAAAA==.Leleia:BAAANQADCggIEgAAAA==.',
Lh='Lhera:BAAANQAECgMIAwABNQAECgQIBgABAAAAAA==.',
Li='Liath:BAAANQADCgcIDwAAAA==.Lichtenberg:BAAANQAECgQIBgAAAA==.Linddori:BAAANQAECgQIBAAAAA==.Liori:BAAANQADCgQIBAAAAA==.Lirillia:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Lirillïa:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Lo='Locdon:BAAANQABCgIIAgABNQAECgUIBgABAAAAAA==.Lodestone:BAAANQADCgIIAgAAAA==.Lovelydread:BAAANQAECgEIAQAAAA==.',
Lu='Lunabug:BAAANQAECgIIAgAAAA==.Lupinos:BAAANQADCgIIAQAAAA==.',
Ly='Lyadra:BAAANQAECgMIAwAAAA==.',
Ma='Mackito:BAAANQADCgYIBgAAAA==.Madan:BAAANQADCggIEQAAAA==.Mahoushojou:BAAANQAECgIIAgAAAA==.Malasminna:BAAANQADCgcIDwAAAA==.Malehorelock:BAAANQAECgEIAQAAAA==.Malicioun:BAAANQABCgUIBwAAAA==.Malkariss:BAAANQAECgIIAgAAAA==.Mammadruid:BAAANQADCgYIFQAAAA==.Mauldis:BAAANQAECgIIAgAAAA==.',
Me='Meryl:BAAANQAECgUICAAAAA==.',
Mi='Miaka:BAAANQAECgQIBQAAAA==.Minth:BAAANQADCgcIDQAAAA==.Misfire:BAAANQAECgMIAwAAAA==.',
Mo='Moghroth:BAAANQAECgIIAgAAAA==.Molykote:BAAANQADCgUIBgAAAA==.Monks:BAAANQADCgQIBAAAAA==.Monsterbabe:BAAANQADCgQIBQAAAA==.Moreleath:BAAANQADCgMIBAAAAA==.',
Mu='Mugzypatron:BAAANQADCgcIBwAAAA==.Murdrmitts:BAAANQADCggIEAAAAA==.',
['Mã']='Mãtador:BAAANQADCggIDwABNQAECgcIEgABAAAAAA==.',
['Mä']='Mätadør:BAAANQAECgcIEgAAAA==.',
Na='Nahryn:BAAANQAECgIIAgAAAA==.',
Ne='Neretsym:BAAANQAECgMIAwAAAA==.',
Ni='Nineva:BAAANQADCgQIBgAAAA==.',
No='Nobas:BAAANQAECgQIBgAAAA==.Nonoa:BAAANQADCgQIBQAAAA==.',
Oc='Octavien:BAAANQADCgIIAgAAAA==.',
Og='Ogr:BAAANQADCgMIAwAAAA==.',
On='Onlyfeet:BAAANQADCgUIBQAAAA==.',
Op='Oppgjør:BAAANQADCggIDwAAAA==.',
Or='Ormr:BAAANQAECgUICAAAAA==.',
Os='Osteo:BAAANQAECgEIAQAAAA==.Osteoprime:BAAANQADCgUIBQAAAA==.',
Ou='Ouron:BAAANQADCgYIDgAAAA==.',
Pa='Pagoda:BAAANQADCgYIBgAAAA==.Papashrimps:BAAANQAECgcIDgAAAA==.',
Pe='Penelopee:BAAANQADCgYIBgAAAA==.',
Ph='Phatcow:BAAANQADCgEIAQAAAA==.',
Pl='Placeholder:BAAANQAECgIIAgAAAA==.',
Po='Pojoevokest:BAAANQADCggIFQAAAA==.Pontifex:BAAANQAECgQIBAAAAA==.Portandmorph:BAAANQAECgMIAwAAAA==.',
Pr='Priests:BAAANQADCgQIBgAAAA==.Prone:BAAANQAECgQIBgAAAA==.Protarada:BAAANQADCgEIAQAAAA==.',
Qu='Quietmind:BAAANQADCggIDAAAAA==.Quinnifred:BAAANQADCgYIDgAAAA==.',
Ra='Raakotah:BAAANQAECgYICwAAAA==.Raasclaat:BAAANQADCgUIBgAAAA==.Raelo:BAAANQAECgIIAgAAAA==.Raiseurmug:BAAANQAECgQIBgAAAA==.Rakash:BAAANQADCgcIBwAAAA==.Rarg:BAAANQAECgcIEQAAAA==.Ravia:BAAANQAECgEIAQAAAA==.',
Re='Resco:BAAANQADCggIEgAAAA==.',
Ri='Riddle:BAAANQAECgQIBAAAAA==.Rize:BAAANQADCgYIBwABNQAECgcIDAABAAAAAA==.',
Ro='Rosenrott:BAAANQAECgIIBAAAAA==.Rosepiercer:BAAANQADCgcIDQAAAA==.Rouz:BAAANQAECgIIAgAAAA==.',
Sa='Samandean:BAAANQADCgcIDQABNQAECgEIAQABAAAAAA==.',
Se='Sellena:BAAANQADCggIFwABNQAECgEIAQABAAAAAA==.',
Sh='Shakenn:BAAANQADCgEIAQAAAA==.Shandow:BAAANQAECgcIEgAAAA==.Shansoracle:BAAANQAECgMIBwABNQAECgcIEgABAAAAAA==.Shed:BAAANQAECgQIBAABNQAFFAIIAgABAAAAAA==.Sheislegend:BAAANQADCgUIDAAAAA==.Shelby:BAAANQAECgIIBAAAAA==.',
Si='Siccinok:BAAANQAECgQIBAAAAA==.Sindorian:BAAANQADCgUIDwABNQAECgEIAQABAAAAAA==.Sixhundrdlbs:BAAANQAECgcICwABNQABCgIIAgABAAAAAA==.',
Sl='Slimped:BAAANQADCgYICwAAAA==.',
So='Sofie:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Solarial:BAAANQADCgYIDQAAAA==.Solastra:BAAANQAECgIIAgAAAA==.Soramai:BAAANQADCgcICgAAAA==.Soth:BAAANQAECgQIBgAAAA==.',
St='Starlyvana:BAAANQADCgQIBAAAAA==.Staryxia:BAAANQAECgcIEQAAAA==.Steephany:BAAANQADCgMIBAAAAA==.Stonecross:BAAANQAECgQIBQAAAA==.Stormbolt:BAAANQAECgQIBQAAAA==.Stormspirit:BAAANQADCgYICwAAAA==.Striggen:BAAANQADCgYIDQAAAA==.',
Su='Sugarsham:BAAANQAECgMIAwAAAA==.Sulwen:BAACNQAFFIEFAAICAAUJASOPAAAqAgACAAUJASOPAAAqAgA1AAQKgRoAAgIACQkmJs4AANgDAAIACQkmJs4AANgDAAAA.Sumerset:BAAANQAECgMIAwAAAA==.Sundave:BAAANQAECgEIAQAAAA==.Sustia:BAAANQADCgUICAAAAA==.',
Ta='Taera:BAAANQAECgIIBAAAAA==.Talavenn:BAAANQAECgQIBAAAAA==.Tarage:BAAANQADCgUIBQAAAA==.Taurîel:BAAANQADCgYIBgAAAA==.',
Te='Tectoniiks:BAAANQADCggICAAAAA==.Tedds:BAAANQAECgMIAwAAAA==.Teds:BAAANQADCgUIBQAAAA==.Tempus:BAAANQAECgEIAQAAAA==.Teriko:BAAANQAECgQIBAAAAA==.',
To='Toaderic:BAAANQAECgQIBAAAAA==.Tots:BAAANQAECgUICAAAAA==.Toxictotes:BAAANQADCgEIAQAAAA==.',
Ty='Tyraèl:BAAANQAECgYICAAAAA==.Tyzy:BAAANQAECgYICgAAAA==.',
Va='Valenora:BAAANQADCggIFwAAAA==.Valvitor:BAAANQADCgEIAQAAAA==.Varuz:BAAANQAECgQIBAAAAA==.',
Ve='Velanie:BAAANQADCggIDwAAAA==.Veloon:BAAANQAECgMIAwAAAA==.Verinari:BAAANQADCgUIDAAAAA==.',
Vi='Vipul:BAAANQADCgUIDQAAAA==.Viridria:BAAANQADCgQIBAABNQADCgcIDQABAAAAAA==.Vityazi:BAAANQADCggIFgAAAA==.',
Vl='Vlado:BAAANQADCgIIAgAAAA==.',
Vo='Voodoobootie:BAAANQABCgYIBgAAAA==.',
['Vè']='Vè:BAAANQADCgQIBAAAAA==.',
Wa='Warriors:BAAANQAECgUICAAAAA==.Wartooth:BAAANQAECgIIAgAAAA==.Wassergott:BAAANQADCgYIBgAAAA==.',
We='Webicus:BAAANQADCggIFgAAAA==.Wendee:BAAANQADCgcIDQAAAA==.',
Wh='Whitley:BAAANQAECgIIAwAAAA==.',
Wi='Wildspart:BAAANQADCggIDgAAAA==.',
Wo='Wooden:BAAANQAECgIIAgAAAA==.',
Xa='Xaphy:BAAANQADCggIEAAAAA==.Xardots:BAAANQAECgMIBAABNQAECgIIAgABAAAAAA==.',
Xi='Xiareth:BAAANQAECgIIAgAAAA==.',
['Xá']='Xároth:BAAANQAECgIIAgAAAQ==.',
Yi='Yirï:BAAANQABCgIIBAAAAA==.',
Yo='Youngjeezy:BAAANQABCgQIAwAAAA==.Yoursinpride:BAAANQAECggIDgAAAA==.',
Za='Zackor:BAAANQADCgUIDAAAAA==.',
Ze='Zervann:BAAANQADCgYIBgAAAA==.',
Zi='Ziska:BAAANQADCgIIAgAAAA==.',
Zo='Zorithic:BAAANQADCggIAQAAAA==.',
Zy='Zyde:BAAANQABCgIIAgABNQAECgQIBAABAAAAAA==.',
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
