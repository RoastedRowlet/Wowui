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
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=53,date='2026-09-01',data={Ae='Aegon:BAAANQAECgQIBQAAAA==.Aelivalor:BAAANQADCggIDQAAAA==.Aendoran:BAAANQABCgIIAgAAAA==.Aesthelyan:BAAANQADCgYIDwAAAA==.',
Ah='Ahdonis:BAAANQADCgIIAgAAAA==.',
Ai='Aiarra:BAAANQADCggIEAAAAA==.Aindriana:BAAANQADCgYIDAAAAA==.',
Aj='Ajx:BAAANQADCgIIAQABNQADCgYIDAABAAAAAA==.',
Ak='Akashajade:BAAANQADCgcIBwAAAA==.Akzeriyuth:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.',
Al='Alerothon:BAAANQAECgQIBQAAAA==.Alestiana:BAAANQAECgEIAQAAAA==.Alevora:BAAANQADCgIIAgAAAA==.Alycya:BAAANQABCgIIAgAAAA==.',
Am='Amephyst:BAAANQADCggIDgAAAA==.Amnadores:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.',
An='Annati:BAAANQAECgYICgAAAA==.Antarres:BAAANQADCgYIBwAAAA==.',
Ap='Apila:BAAANQADCgEIAQABNQADCgcIBwABAAAAAQ==.',
Ar='Arathria:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.Armagedon:BAAANQADCgUIBQAAAA==.Artemisomega:BAAANQADCgEIAQABNQADCgcIDAABAAAAAA==.Artemisshade:BAAANQADCgcIDAAAAA==.Arthillius:BAAANQADCgQIBQAAAA==.',
Av='Aviana:BAAANQADCgYIBgAAAA==.',
Ay='Aylá:BAAANQADCgQICAAAAA==.',
Be='Beldar:BAAANQAECgIIAgAAAA==.',
Bi='Bip:BAAANQAECgMIAwAAAA==.',
Bl='Blitzy:BAAANQAECgIIAgAAAA==.',
Bo='Bobbette:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Br='Brenick:BAAANQADCgcICwAAAA==.Bringer:BAAANQADCgYIDAAAAA==.Bristlegonad:BAAANQADCgEIAQAAAA==.Bråyden:BAAANQADCgUICAAAAA==.',
Bu='Bullgrim:BAAANQADCgMIAwAAAA==.Burnie:BAAANQADCgYICgAAAA==.',
Ca='Camilah:BAAANQADCgcICwAAAA==.Capa:BAAANQAECgIIAgAAAA==.Carcine:BAAANQADCgUIBQAAAA==.Carion:BAAANQAECgQIBQAAAA==.',
Ce='Cemeteri:BAAANQADCgQIBAAAAA==.',
Ch='Chaingun:BAAANQADCgcIDAAAAA==.Chilblain:BAAANQADCggIDwAAAA==.Chobii:BAAANQAECgEIAQAAAA==.',
Ci='Cibochevski:BAAANQADCgQIBAABNQADCgYICgABAAAAAA==.Citrus:BAAANQAECgUIBwAAAA==.',
Cl='Closetfurry:BAAANQADCgYICwAAAA==.',
Cm='Cmerollin:BAAANQABCgIIAgAAAA==.',
Co='Condor:BAAANQADCgcIDAAAAA==.Corrinne:BAAANQADCgYICwAAAA==.',
Cr='Critmypänts:BAAANQADCgYICAAAAA==.',
Da='Daeshan:BAAANQADCggIDwAAAA==.Daldolarette:BAAANQAECgQIBQAAAA==.Daralune:BAAANQADCgYICQAAAA==.Darkenrahll:BAAANQADCgIIAgAAAA==.Darner:BAAANQAECgEIAQAAAA==.Dasecondone:BAAANQADCgUIBgAAAA==.',
De='Demonicfyre:BAAANQAECgQIBAAAAA==.Destros:BAAANQADCgQIBAAAAA==.',
Di='Disdain:BAAANQADCgYIBgABNQAFFAEIAQABAAAAAA==.',
Do='Doomsteel:BAAANQADCgQIBAAAAA==.',
Dr='Drucyllå:BAAANQADCgIIAgAAAA==.Dryageribeye:BAAANQAECgIIAgAAAA==.Drzippy:BAAANQADCgYICgAAAA==.',
Du='Duskthrasher:BAAANQADCggIDQAAAA==.Duyii:BAAANQADCgYIBgABNQADCgcIBwABAAAAAQ==.',
Dy='Dyanthus:BAAANQAECgQIBAAAAA==.',
['Dà']='Dàrktress:BAAANQADCgUIBQAAAA==.',
Ec='Ech:BAAANQADCggIDwAAAA==.',
Ei='Eiraveta:BAAANQADCggIEAAAAA==.',
El='Elemental:BAAANQADCgYICgAAAA==.Ellois:BAAANQADCgQIBAAAAA==.',
Ep='Epicnoname:BAAANQAECgQIBQAAAA==.',
Er='Erëdor:BAAANQADCgIIAgAAAA==.',
Fa='Fairlight:BAAANQADCggIDgAAAA==.',
Fe='Feannesse:BAAANQADCgYICgAAAA==.',
Fi='Firebolt:BAAANQAECgEIAgAAAA==.Fitts:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.',
Fr='Fricorith:BAAANQADCgcICQAAAA==.Frostytoot:BAAANQADCgUIBQAAAA==.',
['Fë']='Fëhirthane:BAAANQADCgYICwAAAA==.',
['Fù']='Fùzz:BAAANQAECgEIAQAAAA==.',
Ga='Garekk:BAAANQADCggIDwAAAA==.',
Gi='Gilgamésh:BAAANQAECgcICwAAAA==.',
Go='Golldehammer:BAAANQADCgQIBAAAAA==.Goneville:BAAANQADCgYIBgAAAA==.',
Gr='Grizzabella:BAAANQADCggIDwAAAA==.',
Gt='Gtx:BAAANQADCggIDQAAAA==.',
Gu='Guias:BAAANQADCgEIAQAAAA==.Gutworthy:BAAANQADCgUIBQAAAA==.',
Ha='Hairykrishna:BAAANQADCgYIDAAAAA==.Haldevarik:BAAANQADCgQIBAAAAA==.Hallzofhell:BAAANQADCgYICAAAAA==.Hammerjane:BAAANQADCgYICAAAAA==.Hamur:BAAANQADCgYICwAAAA==.Hariyaki:BAAANQADCgYICgAAAA==.',
He='Heavywinner:BAAANQAECgQIBQAAAA==.Hellslayer:BAAANQADCgYICwAAAA==.',
Hu='Hughmann:BAAANQADCgYICgAAAA==.',
['Hâ']='Hârlot:BAAANQADCgYICgAAAA==.',
['Hè']='Hèathen:BAAANQADCgQIBAAAAA==.',
Is='Ishaa:BAAANQADCgIIAgAAAA==.Isllwyn:BAAANQADCgMIAwAAAA==.Isummonyou:BAAANQAECgMIAwAAAA==.',
Ja='Jadeth:BAAANQADCgYICgAAAA==.Jaidah:BAAANQADCgQIBAAAAA==.Jansôlo:BAAANQAECgMIAwAAAA==.Jaratri:BAAANQAECgMIBQAAAA==.',
Je='Jenton:BAAANQADCgUIBQAAAA==.',
Ka='Kaerovia:BAAANQAECgIIAgAAAA==.Kaisen:BAAANQADCgQIBAAAAA==.Kamthesham:BAAANQAECgIIAgAAAA==.Kanchome:BAAANQADCgYIBgAAAA==.Kaneki:BAAANQADCgYIBgAAAA==.Karg:BAAANQADCggIDgAAAA==.Karmai:BAAANQAECgEIAQAAAA==.Kathine:BAAANQADCgUICAAAAA==.',
Ke='Kelvala:BAAANQAECgQIBQAAAA==.Kelwynd:BAAANQADCgcIDQAAAA==.',
Kh='Khasaziel:BAAANQADCgUIAQAAAA==.',
Ki='Kirean:BAAANQADCggIDwAAAA==.Kiuke:BAAANQADCgYIDAAAAA==.',
Ko='Kobesama:BAAANQADCgMIBQAAAA==.Kodask:BAAANQADCgYICwAAAA==.Kodera:BAAANQAECgEIAQAAAA==.Konata:BAAANQADCggIDwAAAA==.Korbenzoo:BAAANQADCgMIAwABNQADCgcIBwABAAAAAQ==.',
Kr='Kryssie:BAAANQAECgIIAgAAAA==.',
Ku='Kuroku:BAAANQADCgUIBQAAAA==.',
Kw='Kwaili:BAAANQADCgcIDAAAAA==.',
La='Lanaya:BAAANQADCgYICwAAAA==.Laserheadten:BAAANQAECgQIBQAAAA==.',
Le='Lencho:BAAANQADCgcICQAAAA==.Lenchodude:BAAANQADCgQIBAAAAA==.Lenian:BAAANQADCgYICgAAAA==.Leâfs:BAAANQADCgYICAAAAA==.',
Li='Litesout:BAAANQADCgYIBgAAAA==.',
Lo='Loreck:BAAANQADCgUICAAAAA==.Lorlea:BAAANQADCgMIAwAAAA==.',
Lu='Lunariel:BAAANQADCgYIDAAAAA==.',
Ly='Lyraae:BAAANQADCggIEAAAAA==.',
Ma='Mackas:BAAANQADCgIIAgAAAA==.Maidenofhate:BAAANQAECgQIBQAAAA==.Maiganoss:BAAANQADCgYIDAAAAA==.',
Me='Megid:BAAANQADCggIEAAAAA==.Mestopheles:BAAANQADCggIDQABNQAECgEIAQABAAAAAA==.',
Mi='Midianite:BAAANQADCgMIAwAAAA==.Mimiru:BAAANQADCgYIBgAAAA==.Minié:BAAANQADCgUIBQAAAA==.Mizblumkin:BAAANQADCgYIBgAAAA==.',
Mo='Moonnshine:BAAANQAECgIIAgAAAA==.',
My='Mylittlepwni:BAAANQADCgQIBQAAAA==.',
Na='Nakros:BAAANQADCgYICwAAAA==.',
Ne='Nemonas:BAAANQADCgYIDAAAAA==.Nerik:BAAANQADCgMIBAAAAA==.',
Ng='Ngyue:BAAANQADCgYIFAAAAA==.',
Ni='Nianna:BAAANQADCggIEAAAAA==.Nickto:BAAANQADCgYICAAAAA==.Nightshayed:BAAANQADCgQIBAAAAA==.',
Ny='Nytwalker:BAAANQADCgYICQAAAA==.Nyårlåthôtêp:BAAANQADCgMIAwAAAA==.',
Og='Ogbruced:BAAANQADCgYIBQABNQADCgYICwABAAAAAA==.',
Op='Opalla:BAAANQADCgYIDAAAAA==.',
Or='Orceo:BAAANQADCgYICwAAAA==.Orcrest:BAAANQADCgQIBAAAAA==.Ororo:BAAANQAECgMIBAAAAA==.',
Pa='Palal:BAAANQADCgcIBwABNQADCggICQABAAAAAA==.Paryah:BAAANQADCgYICgAAAA==.',
Ph='Phanceester:BAAANQADCgQIBQAAAA==.Phindra:BAAANQADCgUIBgAAAA==.Phréek:BAAANQAECgEIAQAAAA==.',
Pl='Plethknight:BAAANQAECgIIAgABNQAECgYICQABAAAAAA==.',
Pr='Praze:BAAANQADCgQIBQAAAA==.',
Ra='Raha:BAAANQADCgUIBQAAAA==.Rahis:BAAANQAECgIIAgAAAA==.Raiu:BAAANQADCgYICgAAAA==.Ramsis:BAAANQAECgEIAQAAAA==.Randir:BAAANQAECgIIAgAAAA==.Rath:BAAANQADCggIEAAAAA==.',
Re='Rebarka:BAAANQADCgQIBAAAAA==.Rebrewke:BAAANQADCgYICwAAAA==.',
Ro='Robinhoodx:BAAANQADCggIDwAAAA==.Roenabur:BAAANQADCgQIBAAAAA==.Romok:BAAANQADCgQIBQAAAA==.',
Ru='Rubysunday:BAAANQADCgYICwAAAA==.',
['Rì']='Rìseandemìse:BAAANQABCgEIAQAAAA==.',
Sa='Sacrìfice:BAAANQADCgQIBAAAAA==.Samoot:BAAANQADCgcIDQAAAA==.',
Se='Sepharim:BAAANQADCgIIAwAAAA==.',
Sh='Shael:BAAANQADCgYICgAAAA==.Shamanstein:BAEANQADCggIDwAAAA==.Sharty:BAAANQADCgcIDAAAAA==.Shortigen:BAAANQADCgQIBQAAAA==.Shrilynda:BAAANQADCgUIBwAAAA==.Shupala:BAAANQAECgIIAgAAAA==.',
Si='Sicnus:BAAANQADCgIIAgAAAA==.Siksmonthban:BAAANQADCggIEQAAAA==.Sinadin:BAAANQADCggIDwAAAA==.',
Sk='Skolmaster:BAAANQADCgcIDAAAAA==.Skootter:BAAANQADCgYIBwAAAA==.Skyfury:BAAANQADCgUICQABNQAECgEIAgABAAAAAA==.',
Sm='Smâlls:BAAANQADCgYIDAAAAA==.',
So='Soleil:BAAANQAECgIIAgAAAA==.Sourdiesel:BAAANQADCgQIBgAAAA==.Southsound:BAAANQADCggICAAAAA==.',
St='Stallos:BAAANQADCgQIBAAAAA==.Starmie:BAAANQADCgcIBwAAAA==.Steakknife:BAAANQADCgcIDQAAAA==.Sturma:BAAANQAECgEIAQAAAA==.',
Su='Superrad:BAAANQADCgYIDAAAAA==.',
Sw='Swayla:BAAANQADCgUIBwAAAA==.Sweatyhog:BAAANQADCgIIAgAAAA==.',
Sy='Sybil:BAAANQADCgYIBgAAAA==.',
Ta='Tahfyn:BAAANQADCgYICAAAAA==.Tahtiania:BAAANQADCgYICgAAAA==.Tazedtilblue:BAAANQADCgYICwAAAA==.',
Te='Ted:BAAANQAECgIIAgAAAA==.Teo:BAAANQADCggIEAAAAA==.Teyamat:BAAANQADCgcIDQABNQABCgQIBQABAAAAAA==.',
Th='Thelock:BAAANQAECgEIAgAAAA==.Thetree:BAAANQAECgcIDQAAAA==.Thien:BAAANQADCgUIBQAAAA==.Thoinus:BAAANQADCgYIBgAAAA==.Thundertwig:BAAANQADCggIDgAAAA==.',
Ti='Timoris:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.',
To='Tobiume:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Tofulhundun:BAAANQADCgcICAAAAA==.Toggo:BAAANQADCgQIBAAAAA==.Tommytwotusk:BAAANQADCgYICwAAAA==.',
Tr='Triannah:BAAANQADCgIIAgAAAA==.Trildjr:BAAANQADCgcIBwAAAA==.',
Tu='Tuchmi:BAAANQADCgYIBgAAAA==.Tuldag:BAAANQADCggIDgAAAA==.',
Ty='Tyrse:BAAANQADCgYICAAAAA==.',
Tz='Tzerina:BAAANQADCgYICgAAAA==.',
['Tâ']='Tânkyû:BAAANQADCgUIBQAAAA==.',
Ut='Uthadravis:BAAANQADCgcIBwAAAQ==.',
Va='Valford:BAAANQADCggICgAAAA==.Validan:BAAANQADCgMIAwAAAA==.Vallyrie:BAAANQAECgQIBQAAAA==.Valssharess:BAAANQADCgcIDQAAAA==.Valth:BAAANQADCgQIBQAAAA==.Vanae:BAAANQADCgMIAwAAAA==.Vaporgriffin:BAAANQADCgYIBgAAAA==.',
Ve='Velendez:BAAANQADCgEIAQAAAA==.Veleria:BAAANQAECgEIAQAAAA==.Vellysonna:BAAANQADCgYIBgAAAA==.Versatina:BAAANQADCgQIBQAAAA==.',
Vi='Victra:BAAANQADCgcICwAAAA==.Viko:BAAANQADCgcIBwAAAA==.Vinaya:BAAANQADCgQIBQAAAA==.',
Vo='Volthemar:BAAANQAECgQIBAAAAA==.',
Wa='Warrpath:BAAANQADCgEIAQAAAA==.Watsuki:BAAANQADCgQIBAABNQADCgYICgABAAAAAA==.',
We='Weoo:BAAANQADCgUIBQAAAA==.Werrick:BAAANQADCggIDgAAAA==.',
Wh='Whitespot:BAAANQADCgMIAwAAAA==.',
Wi='Wisegurl:BAAANQAECgEIAQAAAA==.',
Wo='Woodpecker:BAAANQADCggIDwAAAA==.',
Wr='Wreckreation:BAAANQADCgUIBwAAAA==.',
Wy='Wylecsham:BAAANQADCgUIBQAAAA==.Wylectra:BAAANQADCggIDwAAAA==.',
Xe='Xethos:BAAANQADCgQIBAAAAA==.',
Ye='Yeira:BAAANQAECgEIAQAAAA==.Yerdedmatey:BAAANQADCggICAAAAA==.',
Yo='Yourdemon:BAAANQADCgcICQAAAA==.',
Za='Zagasham:BAAANQADCggIDQAAAA==.Zahvaria:BAAANQADCgYICgAAAA==.Zaphiell:BAAANQADCggICAAAAA==.',
Ze='Zeid:BAAANQAECgIIAgAAAA==.Zev:BAAANQADCgQIBAAAAA==.',
Zi='Zillz:BAAANQADCgYIDAAAAA==.Zinderalanot:BAAANQADCgYIDAABNQADCgcIBwABAAAAAQ==.',
Zo='Zoeystorm:BAAANQAECgEIAQAAAA==.',
Zu='Zuldrak:BAAANQAECgQIBAAAAA==.',
Zy='Zykie:BAAANQADCgcIBwAAAA==.',
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
