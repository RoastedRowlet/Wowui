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
local provider = {region='US',realm='Azshara',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aaryyee:BAAANQADCgQIBgAAAA==.',
Ac='Aceforlife:BAAANQADCgUICgAAAA==.',
Ad='Adrox:BAAANQADCgMIAwAAAA==.',
Ae='Aelelelos:BAAANQADCgEIAQAAAA==.Aequus:BAAANQABCgQIAgAAAA==.Aevenyhm:BAAANQADCggIDQAAAA==.',
Ai='Aidoneus:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
Ak='Akismite:BAAANQADCgMIBQAAAA==.',
Al='Alemental:BAAANQADCgcIDAAAAA==.Allhallows:BAAANQADCgUICAAAAA==.Alqueria:BAAANQAECgIIAgAAAA==.',
An='Andanto:BAAANQADCgYICwAAAA==.Angeliz:BAAANQADCgQIBAAAAA==.Anneweaver:BAAANQAECgcICgAAAA==.Anorantha:BAAANQAECgEIAQAAAA==.',
Ap='Apicots:BAAANQADCggIDwAAAA==.Apipa:BAAANQAECgIIAgAAAA==.Apricot:BAAANQADCgUIBQABNQADCgcICAABAAAAAA==.Apzz:BAAANQADCgIIAgAAAA==.',
As='Ashalan:BAAANQADCgUICwAAAA==.Asherabinx:BAAANQABCgQICAAAAA==.Astesia:BAAANQADCgYIBgAAAA==.Astrraa:BAAANQADCgEIAQAAAA==.Asulo:BAAANQADCggIDwABNQAECgQIBAABAAAAAA==.',
At='Atrejha:BAAANQAECgQIBgAAAA==.',
Au='Aurä:BAAANQADCggIDQABNQAECgEIAQABAAAAAA==.',
Aw='Awesome:BAAANQAECgEIAQAAAA==.',
Az='Azgkrimpatul:BAAANQADCgYIBgAAAA==.Azrina:BAAANQADCggIDgAAAA==.',
Ba='Baidden:BAAANQADCgMIBQAAAA==.Baldwarrior:BAAANQAECgIIAgAAAA==.Bandidos:BAAANQADCgYIBQAAAA==.',
Be='Behealzabub:BAAANQADCgYICwAAAA==.Belmatride:BAAANQAECgEIAQAAAA==.Belpepper:BAAANQAECgYICAAAAA==.Bendelmonte:BAAANQABCgMIAwABNQADCgcIDAABAAAAAA==.',
Bi='Biggum:BAAANQADCgIIAgAAAA==.Bigmez:BAAANQADCgYICwAAAA==.Bigmoocowii:BAAANQADCgIIAgAAAA==.Bigswangindi:BAAANQADCggICwAAAA==.Bilipmonk:BAAANQAECgQIBQAAAA==.Bindinglight:BAAANQAECgcICgAAAA==.Birdofhermes:BAAANQADCgMIAwAAAA==.Biñx:BAAANQABCgMIBAAAAA==.',
Bl='Blarr:BAAANQADCgYIBgAAAA==.Blindehunter:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.Blindvoid:BAAANQADCgYICQABNQADCgIIAgABAAAAAA==.Bloodguard:BAAANQADCgYIBgAAAA==.Bluedabodeba:BAAANQADCgEIAQAAAA==.',
Bo='Boonkay:BAAANQADCgEIAQAAAA==.Boonkie:BAAANQADCgUICAAAAA==.Boonksdeath:BAAANQADCgIIAgAAAA==.Boonlock:BAAANQADCgIIAgAAAA==.Boxbeater:BAAANQADCgYIBgAAAA==.',
Br='Brisanna:BAAANQADCgYICwAAAA==.',
['Bà']='Bàwlz:BAAANQADCgcIDAAAAA==.',
['Bè']='Bèérsërk:BAAANQADCgEIAQAAAA==.',
Ca='Caelix:BAAANQADCgEIAQAAAA==.',
Ch='Chadder:BAAANQAECgEIAQAAAA==.Charliie:BAAANQAECgEIAQAAAA==.Chaunakoala:BAAANQADCgIIAgAAAA==.Cheesydemon:BAAANQADCgcICgAAAA==.Cherryfudge:BAAANQADCgQIBQAAAA==.Chipinwing:BAAANQADCggIDAAAAA==.',
Cl='Clockworks:BAAANQADCgMIAwAAAA==.Clouxdyskies:BAAANQADCgEIAQAAAA==.',
Co='Cocinegr:BAAANQAECgUIBAAAAA==.Coneja:BAAANQADCgUIBgAAAA==.',
Cr='Craiso:BAAANQAECgIIAgAAAA==.Crankinhawg:BAAANQAECgIIBAAAAA==.Crazbezzul:BAAANQADCgIIAgAAAA==.Creationz:BAAANQADCgYIBgABNQADCggIFAABAAAAAA==.Crisarrow:BAAANQADCgUICQAAAA==.',
Cu='Current:BAAANQADCgcIDAAAAA==.',
Cy='Cynesh:BAAANQAFFAMIAwAAAA==.',
Da='Dailybuilt:BAAANQADCgQICgAAAA==.Dangybangy:BAAANQADCggIDgAAAA==.Danjaianka:BAAANQADCgcIDAAAAA==.Darkkragmur:BAAANQADCggICwAAAA==.Darknest:BAAANQADCgQIBgAAAA==.Datbishkarma:BAAANQAECgEIAQAAAA==.',
Dd='Dding:BAAANQAECgQIBQAAAA==.',
De='Deathklok:BAAANQADCgUIBQAAAA==.Deathran:BAAANQAECgEIAQAAAA==.Deezgrips:BAAANQAECgIIAgAAAA==.Deffgwip:BAAANQADCgcIDAAAAA==.Delfine:BAAANQADCgQIAgAAAA==.Desimus:BAAANQADCgMIAwAAAA==.Despott:BAAANQAECgYIBwAAAA==.Dethfox:BAAANQADCgcIDAAAAA==.',
Di='Dioni:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Dirknasty:BAAANQADCgUICAAAAA==.',
Dk='Dkurther:BAAANQADCgEIAQAAAA==.',
Do='Doggybag:BAAANQADCgQIBAAAAA==.Doublehelix:BAAANQADCgIIAgAAAA==.',
Dr='Drackygacky:BAAANQADCgEIAQAAAA==.Drashar:BAAANQADCgUIBQAAAA==.Dravenm:BAAANQADCgYICwAAAA==.Draz:BAAANQADCggICgAAAA==.',
['Dè']='Dèmonic:BAAANQAECgQIBQAAAA==.',
['Dø']='Døric:BAAANQADCgcIDAAAAA==.',
['Dü']='Dürinn:BAAANQADCgIIAgAAAA==.',
Eh='Ehud:BAAANQAECgEIAQAAAA==.',
Ek='Ekô:BAAANQADCgYICwAAAA==.',
El='Elabrate:BAAANQADCgMIAwAAAA==.Elbori:BAAANQAECgYIBgAAAA==.Elfmas:BAAANQAECgMIAwAAAA==.',
Em='Emerhy:BAAANQADCgcICwAAAA==.',
Es='Escänor:BAAANQAECgEIAQAAAA==.Eshaia:BAAANQADCgEIAQAAAA==.',
Ex='Exlisum:BAAANQADCgQIBgAAAA==.',
Ey='Eylos:BAAANQADCgIIAgAAAA==.',
Fa='Faesmite:BAAANQADCgUIBQAAAA==.Faithflop:BAAANQADCgUIBwAAAA==.Fanorage:BAAANQADCgIIAgAAAA==.',
Fe='Ferocias:BAAANQAECgEIAQAAAA==.',
Fl='Flaffergan:BAAANQAECgIIAgAAAA==.Flexhack:BAAANQADCgUICgAAAA==.Flåsh:BAAANQADCgQIBAAAAA==.',
Fo='Focinnet:BAAANQADCgMIAwAAAA==.Forandra:BAAANQADCgUIBQAAAA==.Fortyacres:BAAANQADCgEIAQAAAA==.Four:BAAANQADCgMIAwAAAA==.Fourform:BAAANQADCgIIAgAAAA==.',
Fr='Frieren:BAAANQADCgcIBwAAAA==.',
Ga='Galithiri:BAAANQADCgEIAQABNQADCgMIBAABAAAAAA==.Ganthani:BAAANQADCgcICwAAAA==.Garzett:BAAANQAECgMIAwAAAA==.Gatortooth:BAAANQABCgIIBAAAAA==.',
Ge='Geigh:BAAANQADCgUIBQAAAA==.',
Gh='Ghouliana:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Gl='Glizyglober:BAAANQADCgMIAwABNQAECgcICgABAAAAAA==.Glizzyrizily:BAAANQADCgMIAwABNQAECgcICgABAAAAAA==.Glizzyys:BAAANQADCgMIAwABNQAECgcICgABAAAAAA==.Gllizzard:BAAANQADCgMIAwAAAA==.',
Go='Gordo:BAAANQAECgQIBAAAAA==.',
Gr='Gravtech:BAAANQADCggIDQAAAA==.Grhm:BAAANQADCggIDgAAAA==.Grim:BAAANQAFFAEIAQAAAA==.',
Gu='Gumsy:BAAANQABCgQIBgABNQADCggIDQABAAAAAA==.',
['Gø']='Gørë:BAAANQADCgQIBAAAAA==.',
Ha='Haddassah:BAAANQADCgIIAgAAAA==.Haramzadi:BAAANQADCgQIBQAAAA==.Haranue:BAAANQADCgYIBgAAAA==.Harryporter:BAAANQAECgEIAQAAAA==.Harukà:BAAANQADCgYIBgAAAA==.',
He='Healsdog:BAAANQADCgMIAwAAAA==.Hecâte:BAAANQABCgMIAwAAAA==.Helfon:BAAANQAECgMIBAAAAA==.Helganelf:BAAANQADCgIIAwAAAA==.Helices:BAAANQADCggIEgAAAA==.',
Hi='Highlordt:BAAANQAECgEIAQAAAA==.Highlordtron:BAAANQADCgQIBQAAAA==.Hinoxfine:BAAANQADCgMIBAAAAA==.',
Hk='Hkala:BAAANQADCggIDAAAAA==.',
Ho='Holybeast:BAAANQADCgIIAgAAAA==.Holycrab:BAAANQADCgIIAgAAAA==.Holyely:BAAANQADCgYICgAAAA==.Holyfae:BAAANQAECgYIBwAAAA==.Holyvoids:BAAANQADCgIIAgAAAA==.Hondodk:BAEANQAECgcICwABNQAECggIDgABAAAAAA==.Hoodlummon:BAAANQADCgUICQAAAA==.Hopesfall:BAAANQAECgEIAQAAAA==.Hozari:BAAANQAECgMIAwAAAA==.',
Ia='Ianil:BAAANQADCgUICgAAAA==.',
Ic='Iccyhot:BAAANQADCgMIAwABNQAECgcICgABAAAAAA==.',
Il='Ilirranna:BAAANQAECgEIAQAAAA==.',
In='Infi:BAAANQAFFAIIAwAAAA==.Initapoop:BAAANQADCgQIBAAAAA==.Inosukè:BAAANQAECgMIBAAAAA==.',
Io='Ioannis:BAAANQADCgUICAAAAA==.',
Is='Isos:BAAANQAECgEIAgAAAA==.Isus:BAAANQADCgYIBgABNQAECgEIAgABAAAAAA==.',
Iy='Iykyk:BAAANQADCgMIBQABNQADCggIEgABAAAAAA==.',
Ja='Jaded:BAAANQAECgQIBgAAAA==.Jakerbonk:BAAANQADCgEIAQAAAA==.Jakersai:BAAANQADCgcIDQAAAA==.Javyr:BAAANQADCgYICgAAAA==.',
Je='Jessicax:BAAANQAECgEIAQAAAA==.',
Jl='Jlnxy:BAAANQAECgQIAQAAAA==.',
Jo='Jonoa:BAAANQADCgUIBQAAAA==.',
Ka='Kagemika:BAAANQADCgcIBwABNQAECgQIBgABAAAAAA==.Kaiola:BAAANQADCgYIBgAAAA==.Kaizumie:BAAANQAECgIIAgAAAA==.Kanaa:BAAANQADCgIIAgAAAA==.Kanatre:BAAANQADCgEIAQAAAA==.',
Ke='Keeynai:BAAANQADCgQIBAAAAA==.Keldanis:BAAANQAECgMIBAAAAA==.Kelestrah:BAAANQADCgQIBAAAAA==.Kelterrager:BAAANQADCgMIAwAAAA==.Keony:BAAANQADCggIEgAAAA==.',
Ki='Kittyarly:BAAANQAECgIIAgAAAA==.',
Ko='Kodeck:BAAANQADCgUICQAAAA==.Kodokan:BAAANQADCgQIBwAAAA==.Koshima:BAAANQAECgMIAwAAAA==.Kozan:BAAANQADCgUICAAAAA==.',
Kr='Krimhit:BAAANQADCgQIBwAAAA==.',
Ku='Kudranne:BAAANQADCgMIBAAAAA==.Kugia:BAAANQAECgIIAgAAAA==.',
Ky='Kynndell:BAAANQADCgYICgAAAA==.Kyo:BAAANQADCgUICAAAAA==.',
La='Laments:BAAANQADCgUIBQAAAA==.Latir:BAAANQADCgUIBwAAAA==.',
Le='Leetheal:BAAANQAECgYICQAAAA==.Leethul:BAAANQAECgIIAgAAAA==.Lelethxx:BAAANQADCgcICwAAAA==.Lesanna:BAAANQAECgQIBAAAAA==.Leysmith:BAAANQAECgMIBAAAAA==.',
Li='Lifestream:BAAANQADCgYICwAAAA==.Lilheal:BAAANQADCgIIAgAAAA==.Lionël:BAAANQADCgYICwAAAA==.Lizbethe:BAAANQADCggIDgAAAA==.',
Lo='Lomrgreenol:BAAANQADCgQIBAAAAA==.',
Lu='Lumibell:BAAANQABCgQIBAAAAA==.',
Ma='Madamgypsy:BAAANQABCgIIAgAAAA==.Magaspy:BAAANQADCgYIBgAAAA==.Magerage:BAAANQAECgEIAQAAAA==.Magikiarly:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Mahoogany:BAAANQADCgYIDAAAAA==.Mamimage:BAAANQADCggICAABNQAECgUIBAABAAAAAA==.Marukka:BAAANQADCgQIBAABNQADCgUIBQABAAAAAA==.Matty:BAAANQADCgEIAQAAAA==.Mayiana:BAAANQADCgIIAgAAAA==.',
Me='Meadowlark:BAAANQAECgIIAgAAAA==.Mefistofeles:BAAANQADCgIIAwAAAA==.Mellie:BAAANQADCgEIAQAAAA==.Methypheni:BAAANQAECgEIAQAAAA==.',
Mi='Milfshotz:BAAANQADCgIIAgAAAA==.Mill:BAAANQADCgQICAAAAA==.Mirajanna:BAAANQAECgQIBAAAAA==.Missmouthoff:BAAANQADCggIDgAAAA==.Mitenâ:BAAANQADCgMIBAAAAA==.Mizzxgummy:BAAANQADCggICQAAAA==.',
Mo='Moogan:BAAANQADCgUICAAAAA==.Mookins:BAAANQAECgQIBAAAAA==.Moonfishing:BAAANQADCgMIAwAAAA==.Moonfly:BAAANQAECgUICQAAAA==.Morax:BAAANQADCgUICAAAAA==.Mourne:BAAANQAECgEIAQAAAA==.',
Ms='Mssmalvile:BAAANQADCgQIAQAAAA==.',
My='Myrrvain:BAAANQADCgMIBQAAAA==.',
Na='Nalaana:BAAANQAECgEIAgAAAA==.Nalariel:BAAANQAECgYICQAAAA==.Nalmagedan:BAAANQADCgQIBAAAAA==.Nandorr:BAAANQADCgEIAQAAAA==.Narec:BAAANQADCgUIBQAAAA==.Narfhound:BAAANQADCgMIAwAAAA==.',
Ne='Nearhammer:BAAANQABCgQIBgAAAA==.Nervouz:BAAANQAECgMIAwAAAA==.',
Ni='Nikis:BAAANQADCgQIBAAAAA==.',
No='Nobbs:BAAANQADCgIIAgAAAA==.Noonecaress:BAAANQADCgUIBQAAAA==.',
Nu='Nualaperafin:BAAANQAECgYICAAAAA==.',
Ny='Nyxkitsune:BAAANQADCgQIBQAAAA==.',
Oi='Oiyo:BAAANQABCgQIBQAAAA==.',
Ol='Olayro:BAAANQADCggIDgAAAA==.',
Oo='Ooptomss:BAAANQADCgMIBQAAAA==.',
Op='Openingshift:BAAANQABCgQIBAAAAA==.Ophelìa:BAAANQADCgcIBwAAAA==.',
Or='Orclee:BAAANQAECgUIBQAAAA==.',
Pa='Pacificadora:BAAANQAECgEIAQAAAA==.Palkavanka:BAAANQADCgYIBgAAAA==.',
Pe='Peeonfists:BAAANQADCgEIAQAAAA==.Persephie:BAAANQADCgUIBQABNQADCggIDQABAAAAAA==.',
Ph='Pharmacology:BAAANQADCgUIBQAAAA==.Phyberlamer:BAAANQADCgEIAQAAAA==.',
Pi='Pipha:BAAANQABCgIIAwAAAA==.Pitchblack:BAAANQADCgQIBAAAAA==.',
Po='Popa:BAAANQAECgQICAAAAA==.',
Pr='Prathe:BAAANQADCgcIDAAAAA==.Prayinfury:BAAANQADCgYIBgAAAA==.Premorry:BAAANQADCgQIBgAAAA==.Premory:BAAANQADCgMIBAAAAA==.Presagee:BAAANQADCgEIAQAAAA==.',
Ps='Psilocy:BAAANQADCggIDgAAAA==.',
Pu='Pulsate:BAAANQADCgYIDAAAAA==.Purpleduster:BAAANQADCgEIAQAAAA==.',
Qa='Qaucker:BAAANQADCgcIDgAAAA==.',
Qi='Qiz:BAAANQAECgEIAQAAAA==.',
Qw='Qwish:BAAANQADCgYIBgAAAA==.',
Ra='Rad:BAAANQADCgUICQABNQAECgEIAQABAAAAAA==.Radlock:BAAANQADCgUICQABNQAECgEIAQABAAAAAA==.Raiken:BAAANQADCgYICQAAAA==.Rasto:BAAANQADCggICgAAAA==.Raszto:BAAANQADCgIIAgABNQADCggICgABAAAAAA==.Rattlebat:BAAANQADCgMIAwAAAA==.',
Re='Redmark:BAAANQADCgUIBgAAAA==.Rendezook:BAAANQADCgMIAwAAAA==.',
Ri='Rincewind:BAAANQADCgMIBAAAAA==.Riohne:BAAANQADCgMIAwAAAA==.Rivexis:BAAANQADCgIIAgAAAA==.',
Ro='Roci:BAAANQADCgQIBAAAAA==.Roxus:BAAANQAECgMIBQAAAA==.',
Sa='Saegusa:BAAANQADCgYICAAAAA==.Saepius:BAAANQAECgIIAgAAAA==.Salestia:BAAANQADCgcIDAAAAA==.Sasive:BAAANQADCgYICwAAAA==.Sazoku:BAAANQADCgYIBgAAAA==.',
Sc='Schmall:BAAANQADCgYICQAAAA==.',
Se='Seniormage:BAAANQAECgEIAQAAAA==.Serveil:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.',
Sh='Shadesprint:BAAANQADCggIDQAAAA==.Shamamoomoo:BAAANQADCgYICAAAAA==.Shaowen:BAAANQADCgYIBgABNQADCgcIDAABAAAAAA==.Shaqeesha:BAAANQADCgUIBQAAAA==.Shenea:BAAANQADCgYICQAAAA==.Shestalker:BAAANQAECgYIBwAAAA==.Shiau:BAAANQADCggIDwAAAA==.Shý:BAAANQADCgEIAQAAAA==.',
Si='Silvaine:BAAANQADCgYICwAAAA==.Silverstorm:BAAANQAECgQIBgAAAA==.Sixii:BAAANQADCgYICQAAAA==.',
Sk='Skitzz:BAAANQADCgIIAgAAAQ==.',
Sl='Slackrm:BAAANQADCgMIBAAAAA==.Slashyr:BAAANQAECgQIBwAAAA==.',
Sn='Snipez:BAAANQADCgYIBwAAAA==.Snortymcgoop:BAAANQADCggIDgAAAA==.',
So='Solclipeus:BAAANQAECgIIAgAAAA==.Soldh:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Soupz:BAAANQADCgcIDAAAAA==.',
Sp='Sparadin:BAAANQADCgYICwAAAA==.Spartacûs:BAAANQADCgMIAwAAAA==.',
Sr='Sririacha:BAAANQABCgQIBAABNQADCggIDQABAAAAAA==.',
St='Stìtch:BAAANQAECgUICQAAAA==.Stítch:BAAANQADCgQIBAABNQAECgUICQABAAAAAA==.',
Su='Sukiafaunias:BAAANQAECgEIAQAAAA==.Suldån:BAAANQADCgUIBgAAAA==.Suoop:BAAANQADCgYICAAAAA==.',
Sw='Swiftshaman:BAAANQAECgEIAQAAAA==.',
Sy='Synvaria:BAAANQADCgYIBwAAAA==.Syraice:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.Syrare:BAAANQADCgYICQAAAA==.Syvenari:BAAANQADCgYIBgAAAA==.',
Ta='Taeril:BAAANQADCgQIBAAAAA==.Tamfam:BAAANQADCgQIBAAAAA==.Tanburn:BAAANQADCgYICwAAAA==.Tanduinex:BAAANQADCgQIBgAAAA==.Tankstabber:BAAANQADCgQIBQAAAA==.Tanplate:BAAANQADCgIIAgAAAA==.',
Tc='Tcmon:BAAANQAECgMIBAAAAA==.',
Te='Teaglizzy:BAAANQADCgEIAQABNQAECgcICgABAAAAAA==.Teehole:BAAANQAECgEIAQAAAA==.Telihill:BAAANQADCgQIBAAAAA==.Telsarra:BAAANQADCgMIAwAAAA==.',
Th='Thebigtuna:BAAANQAECgMIAwAAAA==.Theladydruid:BAAANQAECgIIAgAAAA==.Themeats:BAAANQADCgQIBAAAAA==.Thighsoffel:BAAANQADCgcIBwAAAA==.',
Ti='Tigerpa:BAAANQADCgEIAQAAAA==.Tinypally:BAAANQAECgEIAgAAAA==.Tinyraven:BAAANQAECgIIAgAAAA==.Tinythia:BAAANQADCgUIBQAAAA==.Tioklarus:BAAANQAECgUIBQAAAA==.Tiptip:BAAANQADCgYIDAAAAA==.',
To='Tofulady:BAAANQAECgcICwAAAA==.',
Tw='Twoone:BAAANQADCgEIAQAAAA==.',
Ty='Tyniarstus:BAAANQADCgYICAAAAA==.',
Ud='Udderfiasco:BAAANQABCgIIAgAAAA==.',
Un='Unhowly:BAAANQAECgcICAAAAA==.Unpoppable:BAAANQADCgcICgAAAA==.',
Va='Vakir:BAAANQAECgMIAwAAAA==.Valmortem:BAEANQADCgYICwAAAA==.Vapidos:BAAANQADCgUICAAAAA==.Varynix:BAAANQADCggIBwABNQAECgIIAgABAAAAAA==.Vatica:BAAANQADCgQIBAAAAA==.',
Ve='Velanoria:BAAANQADCggICwAAAA==.Veldorai:BAAANQADCgYICwAAAA==.Velrenya:BAAANQADCgQIBgAAAA==.Venvalzhar:BAAANQADCggIDgAAAA==.Veralidaine:BAAANQADCgMIAwAAAA==.Vestammeni:BAAANQAECgUIBQAAAA==.',
Vi='Vixsaurion:BAAANQADCgIIAgAAAA==.',
Vl='Vlamort:BAAANQADCgEIAQAAAA==.',
Vo='Voltx:BAAANQADCgMIAwAAAA==.Vow:BAAANQAECgEIAQAAAA==.',
Wc='Wckd:BAAANQAECgUIBgAAAA==.',
We='Weaksnow:BAAANQAECgQIBAABNQAECgUIBAABAAAAAA==.Weedvegeta:BAAANQADCggIDgAAAA==.',
Wh='Whirpy:BAAANQAECgIIAgAAAA==.Whitty:BAAANQADCgQIBAAAAA==.Whizkee:BAAANQADCggIDwAAAA==.',
Wi='Wingedlady:BAAANQADCgYICwAAAA==.Wingss:BAAANQAECgUICwAAAA==.',
Wu='Wushu:BAAANQADCgYIBgAAAA==.',
Xi='Xinei:BAAANQADCgQIAQAAAA==.',
Xn='Xneutron:BAAANQADCgcICgAAAA==.',
Xt='Xtravagent:BAAANQADCgIIAgAAAA==.',
Ya='Yaiie:BAAANQADCgcIDgAAAA==.',
Yo='Yonna:BAAANQAECgMIAwAAAA==.',
['Yü']='Yüto:BAAANQAECgMIAwAAAA==.',
Za='Zahäära:BAAANQADCgMIAwAAAA==.Zaldiz:BAAANQADCgEIAQAAAA==.Zarrtan:BAAANQABCgMIAwAAAA==.Zazprie:BAAANQADCgUIBgAAAA==.',
Zx='Zxeý:BAAANQADCgcICgAAAA==.',
['Äb']='Äbracadabruh:BAAANQAECgEIAQAAAA==.',
['Äl']='Älissia:BAAANQADCgQIBQAAAA==.',
['Ën']='Ëndo:BAAANQADCggIDQAAAA==.',
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
