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

local lookup = {'Unknown-Unknown','Hunter-Marksmanship','Paladin-Retribution',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Absofsteels:BAAANQAECgEIAQAAAA==.',
Ad='Adøra:BAAANQAECgYIBwAAAA==.',
Ag='Agumon:BAAANQADCgUICAAAAA==.',
Al='Alistair:BAAANQADCgUIBQAAAA==.Alluriel:BAAANQADCgQIBAAAAA==.Altharoth:BAAANQAECgQIBQAAAA==.',
Am='Amira:BAAANQADCgYICQABNQAECgYICQABAAAAAA==.Amormage:BAAANQADCgUICgAAAA==.Amphitrite:BAAANQADCgUIBQAAAA==.',
An='Anteiku:BAAANQAECgIIAwAAAA==.Anteikudeath:BAAANQADCgEIAQAAAA==.',
Ap='Applemoose:BAAANQADCgUIBwAAAA==.',
Ar='Arauial:BAAANQADCgUIBgAAAA==.Arcanis:BAAANQAECgEIAQAAAA==.Aribella:BAAANQAECgMIBAAAAA==.Arizann:BAAANQADCgYIDAAAAA==.Arobotev:BAAANQAECgEIAQAAAA==.',
As='Astaren:BAAANQADCgUICQAAAA==.',
At='Atiya:BAAANQAECgQIBwAAAA==.',
Az='Azaris:BAAANQADCgcIBwAAAA==.',
Ba='Baelrog:BAAANQADCgUICAAAAA==.Baiene:BAAANQADCgcIDQAAAA==.Baldheadelf:BAAANQADCgQIBAAAAA==.Bandalar:BAAANQAECgIIAgAAAA==.Banerino:BAAANQADCgIIAgAAAA==.Barnabust:BAAANQADCgMIAQAAAA==.',
Be='Beastums:BAAANQAECgEIAQAAAA==.',
Bl='Bleak:BAAANQADCgQIBAAAAA==.Blindmonk:BAAANQADCgMIAwAAAA==.Bloodmary:BAAANQADCggIDgAAAA==.Bloodor:BAAANQADCgEIAQAAAA==.Bloöm:BAAANQAECgUIBQAAAA==.',
Bm='Bmaazi:BAAANQADCgcIBwAAAA==.',
Bo='Bonerina:BAAANQAECgQIBAAAAA==.Boomadk:BAAANQAECgYIBwAAAA==.',
Br='Bradburn:BAAANQADCgYIBgAAAA==.Brasserz:BAAANQADCgUIBwAAAA==.Breezybone:BAAANQADCgcIDAAAAA==.Brice:BAAANQADCgUICQAAAA==.Briochebun:BAAANQADCggIDAAAAA==.',
Bw='Bwangifer:BAAANQADCggIDwAAAA==.',
['Bë']='Bëcky:BAAANQAECgcICwAAAA==.',
Ca='Caso:BAAANQADCgIIAgABNQADCgYIDgABAAAAAA==.',
Ce='Cellysia:BAAANQADCgcIDQAAAA==.Ceres:BAAANQAECgEIAQAAAA==.Cesara:BAAANQAECgQIBAAAAA==.',
Ch='Chal:BAAANQADCgIIAgAAAA==.Chaplin:BAAANQADCgUIBQABNQADCgUIBwABAAAAAA==.Chbribs:BAAANQADCgUICAAAAA==.Chiptewth:BAAANQABCgMIAwAAAA==.',
Co='Coldsteel:BAAANQADCgUICgAAAA==.Columbina:BAAANQAECgYIBwAAAA==.Corn:BAAANQADCgIIAgAAAA==.',
Cp='Cptredbeardd:BAAANQADCgUICAAAAA==.',
Cr='Crackmonger:BAAANQAECgYICgAAAA==.Crackundead:BAAANQAECgQIBQAAAA==.',
Cy='Cyphr:BAAANQAECgEIAQAAAA==.Cyrinx:BAAANQABCgEIAQAAAA==.',
Da='Daen:BAAANQADCggICAAAAA==.Dagravytrain:BAAANQAECgEIAQAAAA==.Dalend:BAAANQAECgIIAgAAAA==.Damerot:BAAANQADCgcICAAAAA==.Dangerous:BAAANQADCgYICgAAAA==.Dansharo:BAAANQADCgMIAwAAAA==.Darnnix:BAAANQADCgUIBQAAAA==.Darthrevin:BAAANQADCgYIBgAAAA==.',
De='Deadbeard:BAAANQAECgIIAgAAAA==.Deathbash:BAAANQADCgEIAQAAAA==.Deathrar:BAAANQADCgEIAQAAAA==.Debased:BAAANQADCgcIDgAAAA==.Demini:BAAANQADCgQIBAAAAA==.Demisê:BAAANQAECgQIBAAAAA==.Demonn:BAAANQADCgEIAQAAAA==.Desso:BAAANQADCgYICwAAAA==.',
Di='Dillinger:BAAANQADCgYICwAAAA==.Dingodgaf:BAAANQAECgEIAQAAAA==.',
Dj='Djinnjuicy:BAAANQAECgEIAQAAAA==.',
Do='Dorianmyth:BAAANQADCgcIDAAAAA==.',
Dr='Dragonshammy:BAAANQADCgMIAwAAAA==.Dreamclaw:BAAANQADCgYICQAAAA==.Drippindots:BAAANQAECgUIBQAAAA==.Driztette:BAAANQADCggIDAAAAA==.Drnewport:BAAANQADCgQIBAAAAA==.Drokash:BAAANQADCgYICQAAAA==.Drystine:BAAANQADCggIDgAAAA==.',
['Dí']='Dín:BAAANQAECgEIAQAAAA==.',
Eg='Eggs:BAAANQADCgEIAQAAAA==.',
Ei='Eillaura:BAAANQAECgQIBAAAAA==.',
El='Elipsis:BAAANQAECgYIBwAAAA==.Elm:BAAANQADCggIDgAAAA==.Elyenora:BAAANQAECgQIBQAAAA==.',
En='Enricco:BAAANQADCggICwAAAA==.',
Er='Ereko:BAAANQADCggIDwAAAA==.Erythorbic:BAAANQADCggIDwAAAA==.',
Es='Estralage:BAAANQADCgMIAwAAAA==.',
Ev='Evictor:BAAANQADCgIIAgABNQADCgYICgABAAAAAA==.',
Fa='Fanaticism:BAAANQADCgEIAQAAAA==.',
Fe='Feer:BAAANQADCgQICAAAAA==.Feldron:BAAANQADCggIEAAAAA==.',
Ff='Ffugme:BAAANQADCggIDgAAAA==.Ffugoff:BAAANQADCgYIBgAAAA==.Ffugtard:BAAANQADCgcIDQAAAA==.',
Fi='Finnian:BAAANQAECgEIAQAAAA==.Fio:BAAANQAECgMIAwAAAA==.',
Fl='Flowers:BAAANQADCggIDwAAAA==.Fläva:BAAANQADCgMIAwAAAA==.',
Fo='Foxhound:BAAANQADCgcIDQAAAA==.',
Fr='Frostypie:BAAANQADCggIEAAAAA==.',
['Fö']='Föx:BAAANQADCgYIBgAAAA==.',
Ga='Gaius:BAAANQADCgUICQAAAA==.Gawdcomplex:BAAANQAECgIIAgAAAA==.',
Ge='Gernaj:BAAANQADCgcICwAAAA==.',
Gh='Ghostfudge:BAAANQADCgcIDQAAAA==.',
Gi='Ginny:BAAANQADCgYIDAAAAA==.Ginsan:BAAANQADCgEIAQAAAA==.Ginthalos:BAAANQADCgQIBAAAAA==.',
Go='Golaru:BAAANQABCgIIAgAAAA==.',
Gr='Greygor:BAAANQAECgIIAgAAAA==.Grotok:BAAANQADCgYIBgAAAA==.',
Gu='Gumer:BAAANQADCgUIBwAAAA==.Guulen:BAAANQADCgIIAgAAAA==.',
Ha='Halygos:BAAANQADCgYIBwAAAA==.Hasklaufien:BAAANQADCgYICQAAAA==.',
Ia='Iahsotgievhu:BAAANQADCgUIBQAAAA==.',
Ig='Iggey:BAAANQADCgYICgAAAA==.',
Il='Ilandras:BAAANQAECgEIAQAAAA==.Illadus:BAAANQADCgcICgAAAA==.Illiviix:BAAANQADCgEIAQAAAA==.',
In='Indra:BAAANQADCgYIDQAAAA==.Intoxicated:BAAANQADCgYICwAAAA==.',
Ir='Iranna:BAAANQAECgcICgAAAA==.',
It='Itsredbelow:BAAANQADCgUIBQAAAA==.',
Ja='Jaggedace:BAAANQADCgcIDAAAAA==.Janaki:BAAANQADCgQIBAAAAA==.',
Je='Jellyfish:BAAANQADCgEIAQAAAA==.',
Ji='Jibbtotem:BAAANQADCgYIBwABNQADCggIEAABAAAAAA==.',
Jo='Jonnyquestt:BAAANQAECgMIAwAAAA==.',
Ju='Junrush:BAAANQAECgYICgAAAA==.Junshot:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.',
Ka='Katsuko:BAAANQADCggICAAAAA==.Kattnirra:BAAANQADCgYICgAAAA==.Katze:BAAANQADCggIGAAAAA==.',
Ke='Keepper:BAAANQAECgEIAQAAAA==.Kenj:BAAANQAECgcIDAABNQAECgEIAQABAAAAAA==.Kenjurr:BAAANQADCgQIBQABNQAECgEIAQABAAAAAA==.Kenslynn:BAAANQADCggICwAAAA==.',
Ki='Kiannor:BAAANQAECgEIAQAAAA==.Killahaseo:BAAANQAECgEIAQAAAA==.Killmoedee:BAAANQADCgYICQAAAA==.Kishibe:BAAANQADCgIIAgAAAA==.',
Kl='Klexios:BAAANQADCgUICQAAAA==.',
Ko='Koopa:BAAANQADCggIDQAAAA==.',
Kr='Kraulhoof:BAAANQADCgIIAgAAAA==.',
Ku='Kui:BAAANQAECgEIAQAAAA==.Kuyna:BAAANQADCgUICAAAAA==.',
La='Lailiia:BAAANQADCgQIBAAAAA==.Lavendarlace:BAAANQADCgYIDAAAAA==.Lazloo:BAAANQAECgEIAQAAAA==.',
Le='Leftÿ:BAAANQAECgQIBAAAAA==.Lexibelle:BAAANQADCgYIDAAAAA==.',
Li='Lightace:BAAANQADCgYICwAAAA==.Lightbunny:BAAANQAECggIAQAAAA==.Lincia:BAAANQADCgYIDAAAAA==.Linkkil:BAAANQADCgEIAQAAAA==.',
Lo='Loastotem:BAAANQADCgIIAgAAAA==.Lobos:BAAANQAECgIIAgAAAA==.Lostdraco:BAAANQADCgMIBAAAAA==.Lostdream:BAAANQADCgcICQAAAA==.Loun:BAAANQADCgYIDAAAAA==.',
Lu='Luvlycruelty:BAAANQADCgYIDAAAAA==.',
Ly='Lyn:BAEANQAECgIIAgAAAA==.',
Ma='Maazi:BAAANQADCgYIBgAAAA==.Mackenziiee:BAAANQAECgQIBAAAAA==.Madglowup:BAAANQAECgMIAwAAAA==.Magtaki:BAAANQADCgEIAQAAAA==.Mainline:BAAANQABCgIIAgAAAA==.Maizepriest:BAAANQAECgEIAQAAAA==.Maliaa:BAAANQADCgEIAQAAAA==.Malloryrose:BAAANQADCgcIBwAAAA==.Maxz:BAAANQADCgYIBgAAAA==.',
Me='Mellowblink:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Mellowlink:BAAANQAECgMIAwAAAA==.',
Mi='Migglet:BAAANQADCgEIAQAAAA==.Mimi:BAABNQAFFIEGAAICAAUJRBtCAADlAQACAAUJRBtCAADlAQAAAA==.Miramage:BAAANQADCgcIBwAAAA==.Mitcheoff:BAAANQADCgcIBwAAAA==.',
Mo='Monkerick:BAAANQADCgQIBwAAAA==.Morber:BAAANQADCgIIAgAAAA==.',
My='Mystáke:BAAANQAECgIIAgAAAA==.',
Na='Narbus:BAAANQADCgYIBgAAAA==.Naromancer:BAAANQAECgUIBQAAAA==.Nathadon:BAAANQADCgQIBAAAAA==.',
Ne='Nekhraros:BAAANQAECgMIAwAAAA==.Nezukô:BAAANQABCgEIAQAAAA==.',
Ni='Nikkisan:BAAANQADCgUICAAAAA==.',
No='Noixi:BAAANQADCgYICAAAAA==.Noras:BAAANQADCgYICgAAAA==.Nordicslayer:BAAANQADCgUIBQAAAA==.Notagnoblin:BAEANQAECgcICgAAAA==.Notrick:BAAANQADCgEIAQAAAA==.',
Nu='Nuffsaid:BAAANQADCgUIBQAAAA==.',
Og='Ogrelurd:BAAANQADCggIBwAAAA==.',
Op='Ophelia:BAAANQAECgEIAQAAAA==.',
Or='Orakwa:BAAANQADCggIDQAAAA==.',
Pa='Paladont:BAAANQADCgYIDgAAAA==.Pallinda:BAAANQAECgEIAQAAAA==.Palmogant:BAAANQAECgIIAgAAAA==.Pappyoblues:BAAANQAECgEIAQAAAA==.',
Pe='Pendulumlaw:BAAANQAECgYICwAAAA==.Pepe:BAAANQADCgEIAQAAAA==.',
Ph='Phinn:BAAANQADCggIDwAAAA==.Phoopanchu:BAAANQADCgYICAAAAA==.',
Pi='Pimikoh:BAAANQADCgYICAAAAA==.Pinkbuns:BAAANQADCgYIDAAAAA==.',
Pn='Pneuma:BAAANQADCgUIBQAAAA==.',
Po='Pollonius:BAAANQADCgQIBAAAAA==.Popsy:BAAANQADCggIDgAAAA==.',
Pr='Prenton:BAAANQADCggIDwAAAA==.Priestin:BAAANQABCgIIAQAAAA==.',
Ps='Psyduck:BAAANQAECgIIAgABNQAFFAUIBgADAJQiAA==.',
Pu='Punie:BAAANQADCgcICgAAAA==.',
Qe='Qeini:BAAANQADCggIDwAAAA==.',
Ra='Rafoff:BAAANQADCgUIBwAAAA==.Ragnarax:BAAANQADCgcIBwAAAA==.Rancoramble:BAAANQAECgIIAgAAAA==.Randis:BAAANQADCggIDwAAAA==.Raysonna:BAAANQADCgIIAgAAAA==.',
Re='Reticent:BAAANQADCgYIDAAAAA==.Reversewally:BAAANQAECgQICAAAAA==.Rexiis:BAAANQADCgcIDgAAAA==.Reyth:BAAANQADCgQIBwAAAA==.',
Rh='Rhuby:BAAANQADCggIDwAAAA==.',
Ri='Rimos:BAAANQADCgQIBAAAAA==.Rivening:BAAANQADCgUICAAAAA==.',
Rk='Rk:BAAANQADCgYICAAAAA==.',
Ro='Rochelle:BAAANQADCgYIBgAAAA==.Roeyth:BAAANQADCggICAAAAA==.Rokki:BAAANQADCgYIEgAAAA==.Roostor:BAAANQADCgQIBAAAAA==.Roundhouse:BAAANQAECgEIAQAAAA==.',
Ru='Rubmyoysters:BAAANQADCgEIAQAAAA==.Ruleti:BAAANQAECgQIBwAAAA==.Rumí:BAAANQADCgYICwAAAA==.',
Sa='Sabado:BAAANQADCgUIBQAAAA==.Safewerd:BAEANQADCgYICAAAAA==.Saitama:BAAANQADCgUICgAAAA==.Sangriel:BAAANQADCgUIBwAAAA==.Saralanna:BAAANQAECgEIAQAAAA==.Sarefina:BAAANQADCgYIBgAAAA==.Sathenazarke:BAAANQAECgQIBAABNQAECgcICgABAAAAAA==.',
Sc='Schism:BAAANQADCgQIBAAAAA==.',
Se='Seriousjakk:BAAANQADCgEIAQABNQADCgQIBwABAAAAAA==.',
Sh='Shan:BAAANQAECgUIBgAAAA==.Shavemybush:BAAANQADCgcIBwAAAA==.Shayy:BAAANQAECgIIAgAAAA==.Shigure:BAAANQADCgcIDgAAAA==.Sholin:BAAANQADCgUIBwAAAA==.Shomea:BAAANQADCgUICQAAAA==.',
Si='Sikotick:BAAANQADCggIDgAAAA==.Sikxrapture:BAAANQADCgYIBgAAAA==.Siliconista:BAAANQAECgYIBwAAAA==.',
Sk='Skitrit:BAAANQADCgQIBQABNQAECgQIBwABAAAAAA==.Skyjin:BAAANQADCgMIAwAAAA==.',
Sl='Slammurai:BAAANQADCgUIBQAAAA==.Slippinwater:BAAANQADCgcICQAAAA==.Sllew:BAAANQAECgIIAgAAAA==.',
Sm='Smoulder:BAAANQADCgEIAwAAAA==.',
Sn='Snigles:BAAANQADCgUIBwAAAA==.Snurp:BAAANQAECgMIAwAAAA==.',
So='Softnsquishy:BAAANQADCgcIDAAAAA==.Solmarrow:BAAANQAECgEIAQAAAA==.',
Sp='Spartos:BAAANQADCgUICQAAAA==.Speedy:BAAANQADCgYICQAAAA==.Speedyspeed:BAAANQADCgQIBQAAAA==.Sposi:BAEANQAECgEIAQAAAA==.',
Sr='Srimrithyu:BAAANQADCgYIEwAAAA==.',
Ss='Sselionn:BAAANQADCgYIDAAAAA==.',
St='Stomps:BAAANQADCgcIDQAAAA==.Stonezef:BAAANQADCgUIBwAAAA==.',
Su='Sungdihhwoo:BAAANQADCgQIBwAAAA==.Susann:BAAANQAECgQIBQAAAA==.',
Sy='Syravia:BAAANQAECgEIAQAAAA==.',
Ta='Tameka:BAAANQAECgEIAQAAAA==.Tardis:BAAANQADCggIBwAAAA==.Tatersdh:BAEANQADCgUIBQABNQAECgcICgABAAAAAA==.Tavinrayn:BAAANQADCgQIBgAAAA==.',
Te='Teksham:BAAANQADCgYIDAAAAA==.Telarin:BAAANQADCgYIBgAAAA==.',
Th='Thebigdawg:BAAANQADCgEIAQAAAA==.Theladyboy:BAAANQADCgYIDAAAAA==.Thomss:BAAANQAECgEIAgAAAA==.Thrumgar:BAAANQAECgEIAQAAAA==.',
Ti='Tigerliley:BAAANQADCgUIBQABNQADCggIDgABAAAAAA==.Tinneas:BAAANQADCgUIBwAAAA==.',
To='Tomás:BAAANQADCgUIBwAAAA==.Torstai:BAAANQADCgUICAAAAA==.Totemic:BAAANQADCgcIDAAAAA==.Toyun:BAAANQADCgMIAwAAAA==.',
Tr='Trap:BAAANQADCgQIBAAAAA==.',
Ty='Tyresious:BAAANQADCgIIAgAAAA==.',
Va='Valcerus:BAAANQADCgUICQAAAA==.Valedus:BAAANQAECgIIAgAAAA==.',
Ve='Vengeancedh:BAAANQADCgYICQAAAA==.Veylara:BAAANQADCgIIAgAAAA==.',
Vi='Vinno:BAAANQADCgMIBAAAAA==.',
Vo='Volcker:BAAANQADCggIDwAAAA==.Voltuk:BAAANQAECgEIAQAAAA==.',
Wa='Wariius:BAAANQADCgYIBgAAAA==.Warwarb:BAAANQADCgcICQABNQAECgMIAwABAAAAAA==.Waterliliy:BAAANQADCggIDgAAAA==.',
Wi='Windfurypie:BAAANQADCggICQAAAA==.',
Wo='Wolfbish:BAAANQADCgcIDQAAAA==.',
['Wý']='Wýler:BAAANQADCgIIAgAAAA==.',
Xa='Xacious:BAAANQADCgUICAAAAA==.',
Xh='Xhuri:BAAANQADCgYIBgAAAA==.',
['Xë']='Xëna:BAAANQADCgcIDQAAAA==.',
Yo='Yorllik:BAAANQADCgcIDwAAAA==.',
Yu='Yuzuha:BAAANQABCgIIAgAAAA==.',
Za='Zarulyn:BAAANQADCgYIBgAAAA==.',
Ze='Zendragon:BAAANQADCgUICQABNQAECgEIAQABAAAAAA==.',
Zh='Zhorvan:BAAANQADCgcICwABNQADCgcIDAABAAAAAA==.',
Zi='Zilstar:BAAANQADCgIIAgAAAA==.',
['Âr']='Ârtëmïs:BAAANQADCgcIDQAAAA==.',
['Åp']='Åpollo:BAAANQAECgYICQAAAA==.',
['Òm']='Òmgitsbwòng:BAAANQADCgYICQAAAA==.',
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
