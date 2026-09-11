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

local lookup = {'Unknown-Unknown','Warrior-Arms','Shaman-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Retribution',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Absofsteels:BAAANQAECgEIAgAAAA==.',
Ac='Acaric:BAAANQAECgEIAQAAAA==.',
Ad='Adøra:BAAANQAECgcIDgAAAA==.',
Ag='Agumon:BAAANQADCgcIDwAAAA==.',
Al='Alistair:BAAANQADCgUIBQAAAA==.Alluriel:BAAANQADCgYICgAAAA==.Altharoth:BAAANQAECgcIDQAAAA==.',
Am='Amira:BAAANQADCgYIDwABNQAECgcIEAABAAAAAA==.Amormage:BAAANQADCgYIEAAAAA==.Amphitrite:BAAANQADCgUIBQAAAA==.',
An='Anteiku:BAAANQAECgIIBAAAAA==.Anteikudeath:BAAANQADCgEIAQAAAA==.',
Ap='Applemoose:BAAANQADCggIDgAAAA==.',
Ar='Arauial:BAAANQADCggIDQAAAA==.Arcanis:BAAANQAECgQIBAAAAA==.Aribella:BAAANQAECgMIBAAAAA==.Arizann:BAAANQADCggIFAAAAA==.Arobotev:BAAANQAECgQIBQAAAA==.',
As='Astaren:BAAANQADCgcIEAAAAA==.',
At='Atiya:BAAANQAECgYIDQAAAA==.',
Az='Azaris:BAAANQAECgMIAwAAAA==.',
Ba='Babykraze:BAAANQAECgQIBAAAAA==.Baelrog:BAAANQADCgcIDwAAAA==.Baiene:BAAANQADCgcIFAAAAA==.Baiken:BAAANQADCgYIBgAAAA==.Baldheadelf:BAAANQADCgQIBAAAAA==.Bandalar:BAAANQAECgUIBwAAAA==.Banerino:BAAANQADCgIIAgAAAA==.Barnabust:BAAANQADCgYIBwAAAA==.Bashems:BAAANQADCgQIBAAAAA==.',
Be='Beastums:BAAANQAECgQIBQAAAA==.',
Bi='Bigchungus:BAAANQADCgEIAQAAAA==.Bingbong:BAAANQADCgEIAQAAAA==.',
Bl='Bleak:BAAANQADCgQIBAAAAA==.Blindmonk:BAAANQAECgMIAwAAAA==.Bloodmary:BAAANQAECgEIAQAAAA==.Bloodor:BAAANQADCgEIAQAAAA==.Bloöm:BAAANQAECgYICwAAAA==.',
Bm='Bmaazi:BAAANQAECgEIAQAAAA==.',
Bo='Bonerina:BAAANQAECgQICQAAAA==.Boomadk:BAAANQAFFAEIAQAAAA==.',
Br='Bradburn:BAAANQADCgYIDAAAAA==.Brasserz:BAAANQADCgcIDQAAAA==.Breezybone:BAAANQADCgcIDAAAAA==.Brice:BAAANQADCgYICgAAAA==.Briochebun:BAAANQAECgIIAgAAAA==.',
Bw='Bwangifer:BAAANQAECgQIBAAAAA==.',
['Bë']='Bëcky:BAAANQAECgcIEgAAAA==.',
Ca='Caso:BAAANQADCgMIBAABNQAECgEIAQABAAAAAA==.',
Ce='Cellysia:BAAANQAECgMIAwAAAA==.Ceramyth:BAAANQADCgYIBgAAAA==.Ceres:BAAANQAECgQIBQAAAA==.Cesara:BAAANQAECgYICgAAAA==.',
Ch='Chal:BAAANQADCgYIBgAAAA==.Chaplin:BAAANQADCgUIBQABNQADCggIDgABAAAAAA==.Chbribs:BAAANQADCgcIDwAAAA==.Chiptewth:BAAANQABCgUIBQAAAA==.',
Co='Coldsteel:BAAANQADCggIEgAAAA==.Columbina:BAAANQAECgYIDQAAAA==.Corn:BAAANQADCgIIAgAAAA==.',
Cp='Cptredbeardd:BAAANQADCgUICAAAAA==.',
Cr='Crackmonger:BAABNQAECoEUAAICAAgJrBmAJgBbAgACAAgJrBmAJgBbAgAAAA==.Crackundead:BAAANQAECgYICwAAAA==.Crapdragon:BAAANQADCgEIAQAAAA==.',
Cy='Cyphr:BAAANQAECgQIBQAAAA==.Cyrinx:BAAANQADCgcIBwAAAA==.',
Da='Daen:BAAANQADCggICAAAAA==.Dagravytrain:BAAANQAECgMIAwAAAA==.Dalend:BAAANQAECgUIBwAAAA==.Damerot:BAAANQAECgQIAwAAAA==.Dangerous:BAAANQADCgYIDgAAAA==.Danpal:BAAANQADCgEIAQAAAA==.Dansharo:BAAANQADCgMIAwAAAA==.Darnnix:BAAANQAECgEIAQAAAA==.Darthrevin:BAAANQAECgMIAwAAAA==.Dawnsingers:BAAANQADCgQIBAAAAA==.',
De='Deadbeard:BAAANQAECgQIBgAAAA==.Deathbash:BAAANQADCgEIAQAAAA==.Deathdream:BAAANQADCgIIAgAAAA==.Deathrar:BAAANQADCgQIBAAAAA==.Deathviix:BAAANQADCgUIBQAAAA==.Debased:BAAANQAECgMIAwAAAA==.Demini:BAAANQADCgQICAAAAA==.Demisê:BAAANQAECgYICgAAAA==.Demonn:BAAANQADCgEIAQAAAA==.Desso:BAAANQADCgYIEQAAAA==.Detraz:BAAANQABCgEIAQAAAA==.',
Di='Dillinger:BAAANQADCgYIEQAAAA==.Dingodgaf:BAAANQAECgIIBAAAAA==.',
Dj='Djinnjuicy:BAAANQAECgQIBQAAAA==.',
Do='Dodo:BAAANQADCgUIBQAAAA==.Dorianmyth:BAAANQAECgEIAQAAAA==.',
Dr='Dragonshammy:BAAANQADCgMIAwAAAA==.Dreamclaw:BAAANQADCgYIEAAAAA==.Drippindots:BAAANQAECgYICwAAAA==.Driztette:BAAANQAECgIIAgAAAA==.Drnewport:BAAANQADCggIDAAAAA==.Drystine:BAAANQADCggIFgAAAA==.',
['Dí']='Dín:BAAANQAECgQIBQAAAA==.',
Ec='Ectharienne:BAAANQABCgMIAwAAAA==.',
Eg='Eggs:BAAANQADCgEIAQAAAA==.',
Ei='Eillaura:BAAANQAECgYICgAAAA==.',
El='Elipsis:BAAANQAECgcIDgAAAA==.Elm:BAAANQAECgEIAQAAAA==.Elyenora:BAAANQAECgQIBgAAAA==.',
En='Enricco:BAAANQADCggIDgAAAA==.',
Er='Ereko:BAAANQAECgIIAgAAAA==.Erythorbic:BAAANQAECgIIAgAAAA==.',
Es='Estralage:BAAANQADCgUIBgAAAA==.',
Ev='Evictor:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Fa='Fanaticism:BAAANQADCgMIAwAAAA==.Faranth:BAAANQADCgUIBQAAAA==.',
Fe='Feer:BAAANQADCgQICAAAAA==.Feldron:BAAANQAECgYIBgAAAA==.',
Ff='Ffugme:BAAANQAECgMIAwAAAA==.Ffugnutz:BAAANQADCgQIBAAAAA==.Ffugoff:BAAANQADCgYICgAAAA==.Ffugtard:BAAANQAECgEIAQAAAA==.Ffugyou:BAAANQADCgMIAwAAAA==.',
Fi='Finnian:BAAANQAECgQIBQAAAA==.Fio:BAAANQAECgYICQAAAA==.',
Fl='Flowers:BAAANQAECgEIAQAAAA==.Fläva:BAAANQADCgMIAwAAAA==.',
Fo='Foxhound:BAAANQAECgEIAQAAAA==.',
Fr='Frostypie:BAAANQADCggIEAAAAA==.',
['Fö']='Föx:BAAANQADCgYIBgAAAA==.',
Ga='Gaius:BAAANQADCgYIDwAAAA==.Gawdcomplex:BAAANQAECgQIBgAAAA==.',
Ge='Gernaj:BAAANQADCgcICwAAAA==.',
Gh='Ghostfrudge:BAAANQADCggICAAAAA==.Ghostfudge:BAAANQAECgEIAQAAAA==.',
Gi='Ginny:BAAANQADCggIFAAAAA==.Ginsan:BAAANQADCgEIAQAAAA==.Ginthalos:BAAANQADCgQIBAAAAA==.',
Go='Golaru:BAAANQABCgIIAgAAAA==.',
Gr='Greygor:BAAANQAECgIIAwAAAA==.Grotok:BAAANQADCggIDgAAAA==.',
Gu='Gumer:BAAANQADCggIDgAAAA==.Guulen:BAAANQADCgIIAgAAAA==.',
Ha='Halontier:BAAANQADCgUIBQAAAA==.Halygos:BAAANQADCgYIBwAAAA==.Hasklaufien:BAAANQADCgYICQAAAA==.',
Hi='Hinderberg:BAAANQADCgUIBQAAAA==.',
Ia='Iahsotgievhu:BAAANQADCgUIBQAAAA==.',
Ig='Iggey:BAAANQAECgIIAgAAAA==.',
Il='Ilandras:BAAANQAECgQIBQAAAA==.Illadus:BAAANQAECgEIAQAAAA==.Illiviix:BAAANQADCgUIBgAAAA==.',
In='Indra:BAAANQAECgUIBwAAAA==.Intoxicated:BAAANQADCgcIEgAAAA==.',
Ir='Iranna:BAAANQAFFAEIAQAAAA==.',
It='Itsredbelow:BAAANQADCgcICQAAAA==.',
Ja='Jaggedace:BAAANQADCgcIFAAAAA==.Janaki:BAAANQADCgYICQAAAA==.',
Je='Jellyfish:BAAANQADCgcICAAAAA==.',
Ji='Jibbtotem:BAAANQADCgYIDQABNQAECgEIAQABAAAAAA==.',
Jo='Joexotick:BAAANQABCgMIBQAAAA==.Jonnyquestt:BAAANQAECgUICAAAAA==.',
Ju='Junrush:BAAANQAECgYICgAAAA==.Junshot:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.',
Ka='Karaizula:BAAANQAECgIIAgAAAA==.Katsuko:BAAANQADCggICwAAAA==.Kattnirra:BAAANQADCgcIEQAAAA==.Katze:BAAANQAECgIIAwAAAA==.Kaylé:BAAANQADCgQIBQAAAA==.',
Ke='Keepper:BAAANQAECgEIAQAAAA==.Kenj:BAAANQAECgcIDQABNQAECgEIAQABAAAAAA==.Kenjurr:BAAANQAECgcIBwABNQAECgEIAQABAAAAAA==.Kenslynn:BAAANQAECgIIAgAAAA==.',
Ki='Kiannor:BAAANQAECgQIBQAAAA==.Killahaseo:BAAANQAECgQIBQAAAA==.Killmoedee:BAAANQAECgMIAwAAAA==.Kishibe:BAAANQADCgcICQAAAA==.Kiss:BAAANQAECgYIBgABNQAFFAUICQADAEsgAA==.',
Kl='Klexios:BAAANQADCgcIEAAAAA==.',
Ko='Koopa:BAAANQADCggIFAAAAA==.',
Kr='Kraulhoof:BAAANQADCgQIAwAAAA==.',
Ku='Kui:BAAANQAECgQIBQAAAA==.Kuyna:BAAANQADCgUICAAAAA==.',
['Kö']='Köz:BAAANQADCgQIBAAAAA==.',
La='Laetri:BAAANQAECgEIAQAAAA==.Lailiia:BAAANQADCgcICwAAAA==.Lavendarlace:BAAANQADCgYIDAAAAA==.Lazloo:BAAANQAECgEIAgAAAA==.Lazymidget:BAAANQAECggIBwAAAA==.',
Le='Leftÿ:BAAANQAECgcICwAAAA==.Lexibelle:BAAANQAECgEIAQAAAA==.',
Li='Lightace:BAAANQADCgYIEAAAAA==.Lightbunny:BAAANQAECggIBAAAAA==.Lincia:BAAANQADCggIFAAAAA==.Linkkil:BAAANQADCgEIAQAAAA==.Liv:BAAANQADCgMIAwABNQAECgQIBwABAAAAAA==.',
Lo='Loastotem:BAAANQADCgIIAgAAAA==.Lobos:BAAANQAECgQIBQAAAA==.Lorvinion:BAAANQADCgYIBgAAAA==.Lostdraco:BAAANQAECgQIBAAAAA==.Lostdream:BAAANQADCgcIDwAAAA==.Loun:BAAANQADCggIFAAAAA==.',
Lu='Luiss:BAAANQAECgEIAgAAAA==.Luminism:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Luvlycruelty:BAAANQADCggIFAAAAA==.',
Ly='Lyn:BAEANQAECgUIBwAAAA==.',
Ma='Maazi:BAAANQADCgYIBgAAAA==.Mackenziiee:BAAANQAECgYICgAAAA==.Madglowup:BAAANQAECgMIAwAAAA==.Magtaki:BAAANQADCgEIAQAAAA==.Mainline:BAAANQAECgMIAwAAAA==.Maizepriest:BAAANQAECgQIBQAAAA==.Maliaa:BAAANQADCgEIAQAAAA==.Malloryrose:BAAANQADCgcIBwAAAA==.Maxz:BAAANQADCgYIDAAAAA==.',
Me='Meerkat:BAAANQAECgQIBAAAAA==.Mellowblink:BAAANQAECgMIAwABNQAECgMIAwABAAAAAA==.',
Mi='Migglet:BAAANQADCgQIBQAAAA==.Mimi:BAACNQAFFIEMAAMEAAYJViPGAAD/AQAEAAUJwyHGAAD/AQAFAAIJLya5AQDaAAA1AAQKgRoAAwQACQkwJsEAANEDAAQACQkZJsEAANEDAAUAAgnjIiNxAL0AAAAA.Miramage:BAAANQADCgcIBwAAAA==.Mitcheoff:BAAANQADCgcIDgAAAA==.',
Mo='Monkerick:BAAANQADCgQIBwAAAA==.Morber:BAAANQADCgUIBgAAAA==.',
Mu='Murkoobi:BAAANQADCgYIBgAAAA==.',
My='Mystáke:BAAANQAECgUIBwAAAA==.',
Na='Narbus:BAAANQAECgMIAwAAAA==.Naromancer:BAAANQAECgUICAAAAA==.Nathadon:BAAANQADCgYICQAAAA==.Nautrium:BAAANQADCgIIAgAAAA==.',
Ne='Nekhraros:BAAANQAECgUICAAAAA==.Nergál:BAAANQADCgYIBQAAAA==.Neytvengy:BAAANQADCggICAAAAA==.Nezukô:BAAANQADCgQIBAAAAA==.',
Ni='Nikkisan:BAAANQADCgUICAAAAA==.Nixk:BAAANQADCgMIAwAAAA==.',
No='Noixi:BAAANQADCgYICQAAAA==.Noras:BAAANQAECgMIAwAAAA==.Nordicslayer:BAAANQADCgUIBQAAAA==.Notagnoblin:BAEANQAECggIEgAAAA==.Notrick:BAAANQADCgcICAAAAA==.',
Nu='Nuffsaid:BAAANQADCgUIBgAAAA==.',
Ny='Nyko:BAAANQADCgMIAwAAAA==.',
Og='Ogrelurd:BAAANQADCggIDAAAAA==.',
Op='Ophelia:BAAANQAECgQIBQAAAA==.',
Or='Orakwa:BAAANQAECgIIAgAAAA==.',
Pa='Pachez:BAAANQADCgcIBwAAAA==.Paladont:BAAANQAECgEIAQAAAA==.Pallinda:BAAANQAECgQIBAAAAA==.Palmogant:BAAANQAECgQIBgAAAA==.Pappyoblues:BAAANQAECgEIAQAAAA==.Patt:BAAANQADCgUIBQAAAA==.',
Pe='Pendulumlaw:BAAANQAECgcIEgAAAA==.Pepe:BAAANQADCgEIAQAAAA==.',
Ph='Phinn:BAAANQAECgIIAgAAAA==.Phoopanchu:BAAANQADCgYIDgAAAA==.',
Pi='Pimikoh:BAAANQADCgYICAAAAA==.Pinkbuns:BAAANQADCgYIEgAAAA==.',
Pn='Pneuma:BAAANQADCgcIDAAAAA==.',
Po='Pollonius:BAAANQADCgQIBAAAAA==.Popsy:BAAANQADCggIDwAAAA==.',
Pr='Prenton:BAAANQAECgIIAgAAAA==.Prepotente:BAAANQAECgMIAwAAAA==.Priestin:BAAANQABCgQIAwAAAA==.',
Ps='Psyduck:BAAANQAECgIIAgABNQAFFAYIDAAGAEggAA==.',
Pu='Punie:BAAANQAECgEIAQAAAA==.Puzzykat:BAAANQADCgYIBgAAAA==.',
Qe='Qeini:BAAANQAECgIIAgAAAA==.',
Ra='Rafoff:BAAANQADCgcIDgAAAA==.Ragnarax:BAAANQAECgMIAwAAAA==.Rancoramble:BAAANQAECgQIBgAAAA==.Randis:BAAANQAECgIIAgAAAA==.Raysonna:BAAANQADCgcICQAAAA==.',
Re='Reticent:BAAANQADCgcIEwAAAA==.Reversewally:BAAANQAECgUIDQAAAA==.Rexiis:BAAANQAECgMIAwAAAA==.Reyth:BAAANQADCgYIDQAAAA==.',
Rh='Rhuby:BAAANQAECgIIAgAAAA==.',
Ri='Rimos:BAAANQADCgYICgAAAA==.Rivening:BAAANQADCgcIDwAAAA==.',
Rk='Rk:BAAANQADCgYICAAAAA==.',
Ro='Rochelle:BAAANQADCgcIDQAAAA==.Roeyth:BAAANQADCggICAAAAA==.Rokki:BAAANQADCggIHQAAAA==.Roostor:BAAANQADCgYICAAAAA==.Roundhouse:BAAANQAECgQIBQAAAA==.',
Ru='Rubbmytotems:BAAANQAECgQIBAAAAA==.Rubicôn:BAAANQABCgYICAABNQAECggIEgABAAAAAA==.Rubmyoysters:BAAANQADCgEIAQAAAA==.Ruleti:BAAANQAECgQICQAAAA==.Rumí:BAAANQADCgcIEgAAAA==.',
Sa='Sabado:BAAANQADCgYICwAAAA==.Safewerd:BAEANQAECgIIAgAAAA==.Saitama:BAAANQADCgYIEAAAAA==.Sangriel:BAAANQADCggIDgAAAA==.Saraceleste:BAAANQADCgYIBgAAAA==.Saralanna:BAAANQAECgIIAwAAAA==.Sarefina:BAAANQADCggIDgAAAA==.Sathenazarke:BAAANQAECgUIBQABNQAFFAEIAQABAAAAAA==.',
Sc='Schism:BAAANQADCgQIBAAAAA==.',
Se='Seraphnite:BAAANQADCgIIAgAAAA==.Seriousjakk:BAAANQADCgEIAQABNQADCgQIBwABAAAAAA==.',
Sh='Shan:BAAANQAECgYIDAAAAA==.Shavemybush:BAAANQADCgcIBwAAAA==.Shayy:BAAANQAECgQIBgAAAA==.Shigure:BAAANQAECgEIAQAAAA==.Sholin:BAAANQADCggIDgAAAA==.Shomea:BAAANQADCgcIEAAAAA==.',
Si='Sikotick:BAAANQADCggIFQAAAA==.Sikxrapture:BAAANQADCgYIBgAAAA==.Siliconista:BAAANQAECgcIDgAAAA==.',
Sk='Skitrit:BAAANQADCgQIBQABNQAECgQICQABAAAAAA==.Skyjin:BAAANQADCgMIAwAAAA==.',
Sl='Slammurai:BAAANQADCgUIBQAAAA==.Slippinwater:BAAANQAECgIIAgAAAA==.Sllew:BAAANQAECgUIBwAAAA==.',
Sm='Smoulder:BAAANQADCgIIBAAAAA==.',
Sn='Snigles:BAAANQADCggIDgAAAA==.Snowlily:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.Snurp:BAAANQAECgQIBwAAAA==.',
So='Softnsquishy:BAAANQAECgEIAQAAAA==.Solmarrow:BAAANQAECgQIBQAAAA==.',
Sp='Spartos:BAAANQAECgIIAgAAAA==.Speedy:BAAANQADCgYIDAAAAA==.Speedyspeed:BAAANQADCgQIBQAAAA==.Sposi:BAEANQAECgQIBQAAAA==.',
Sr='Srimrithyu:BAAANQADCgYIEwAAAA==.',
Ss='Sselionn:BAAANQADCggIFAAAAA==.',
St='Stomps:BAAANQADCggIFQAAAA==.Stonezef:BAAANQADCggIDgAAAA==.',
Su='Suffocation:BAAANQADCgYIBwAAAA==.Sungdihhwoo:BAAANQADCgQIBwAAAA==.Susann:BAAANQAECgYICwAAAA==.',
Sy='Syravia:BAAANQAECgEIAQAAAA==.',
['Sò']='Sòlushan:BAAANQAECgEIAQABNQAECgcIDQABAAAAAA==.',
Ta='Tameka:BAAANQAECgQIBQAAAA==.Tardis:BAAANQAECgcIBgAAAA==.Tatersdh:BAEANQAECgQIBgABNQAECggIEgABAAAAAA==.Tavinrayn:BAAANQADCgQIBgAAAA==.',
Te='Tekesh:BAAANQADCgIIAgAAAA==.Teksham:BAAANQADCgYIEgAAAA==.Telarin:BAAANQADCggIDgAAAA==.Tezrian:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.',
Th='Thebigdawg:BAAANQADCgEIAQAAAA==.Theladyboy:BAAANQADCgcIDQAAAA==.Thomss:BAAANQAECgMIBQAAAA==.Throhk:BAAANQADCgQIBAAAAA==.Thrumgar:BAAANQAECgEIAgAAAA==.',
Ti='Tigerliley:BAAANQADCgUICgABNQAECgQIBQABAAAAAA==.Tinneas:BAAANQADCgYICAAAAA==.',
To='Tomás:BAAANQADCggIDgAAAA==.Torstai:BAAANQADCgcIDwAAAA==.Totemic:BAAANQADCggIEQAAAA==.Toyun:BAAANQADCgMIAwAAAA==.',
Tr='Trap:BAAANQADCgQIBAAAAA==.',
Ts='Tserendolgor:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.',
Ty='Tyresious:BAAANQADCgIIAgAAAA==.',
Ut='Utherrex:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Va='Vahaghn:BAAANQAECgYIBgAAAA==.Valcerus:BAAANQADCgcIEAAAAA==.Valedus:BAAANQAECgQIBgAAAA==.',
Ve='Veelete:BAAANQADCgQIBAABNQAECgcIDAABAAAAAA==.Vengeancedh:BAAANQADCgYIDwAAAA==.Veylara:BAAANQADCgIIAgAAAA==.',
Vi='Viix:BAAANQADCgIIAgAAAA==.Vinno:BAAANQADCgQIBQAAAA==.Virr:BAAANQADCgEIAQAAAA==.',
Vo='Volcker:BAAANQAECgIIAgAAAA==.Voltuk:BAAANQAECgQIBQAAAA==.',
Wa='Wariius:BAAANQADCggIDQAAAA==.Warwarb:BAAANQADCggIEAABNQAECgQIBwABAAAAAA==.Waterliliy:BAAANQAECgQIBQAAAA==.Wayhn:BAAANQABCgYIBgAAAA==.',
Wi='Windfurypie:BAAANQADCggICQAAAA==.',
Wo='Wolfbish:BAAANQAECgEIAQAAAA==.',
['Wý']='Wýler:BAAANQADCgIIAgABNQADCgYIBQABAAAAAA==.',
Xa='Xacious:BAAANQADCgcIDwAAAA==.',
Xh='Xhuri:BAAANQADCgYIBgAAAA==.',
['Xë']='Xëna:BAAANQAECgEIAQAAAA==.',
Yo='Yorllik:BAAANQADCgcIFAAAAA==.',
Yu='Yuzuha:BAAANQABCgIIAgAAAA==.',
Za='Zarulyn:BAAANQADCgYIBgAAAA==.',
Ze='Zendragon:BAAANQAECgQIBAABNQAECgQIBQABAAAAAA==.',
Zh='Zhorvan:BAAANQADCgcIEQABNQAECgEIAQABAAAAAA==.',
Zi='Zilstar:BAAANQADCggICgAAAA==.',
['Âr']='Ârtëmïs:BAAANQAECgIIAgAAAA==.',
['Åp']='Åpollo:BAAANQAECgcIEAAAAA==.',
['Òm']='Òmgitsbwòng:BAAANQAECgIIAgAAAA==.',
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
