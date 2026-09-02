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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship',}
local provider = {region='US',realm='Nagrand',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abysalwombie:BAAANQADCgYICgAAAA==.',
Ac='Academic:BAAANQADCgYICAAAAA==.Acherron:BAAANQAECgQIBgAAAA==.Acilia:BAAANQADCgUIBQAAAA==.',
Ad='Adenachi:BAAANQADCgYICgAAAA==.Adenalock:BAAANQAECgEIAQAAAA==.Adialetha:BAAANQADCgYIDAAAAA==.',
Ae='Aelinhunter:BAAANQADCgUIBQABNQADCgYICAABAAAAAA==.Aerwyn:BAAANQABCgEIAQAAAA==.',
Ag='Agiel:BAAANQADCgcIBwAAAA==.',
Ah='Ahxiongzz:BAAANQAECgYICAAAAA==.',
Ai='Aimaradin:BAAANQADCgMIAwAAAA==.Aiolia:BAAANQAECgIIAgAAAA==.',
Ak='Akakai:BAAANQAECgIIAgAAAA==.',
Al='Alblaireo:BAAANQADCgcIDQAAAA==.Alexantros:BAAANQAECgQIBQAAAA==.Allewyn:BAAANQADCgcIDQAAAA==.Althena:BAAANQADCgEIAQAAAA==.Altheous:BAAANQADCgcIDQAAAA==.Alunamus:BAAANQAECgQIBAAAAA==.Alvanâ:BAAANQAECgEIAQAAAA==.',
Am='Amandelthul:BAAANQADCggIDwAAAA==.Amarizara:BAAANQADCgcIDAAAAA==.Ambioracle:BAAANQAECgQICAAAAA==.Amullugh:BAAANQADCgcICQAAAA==.',
An='Angelfeet:BAAANQABCgQIBAAAAA==.Ankarna:BAAANQAECgQIBAAAAA==.Antarie:BAAANQAECgQIBAAAAA==.Anumbra:BAAANQADCggIDwAAAA==.',
Ap='Apollyoin:BAAANQAECgYICQAAAA==.Apophiis:BAAANQADCggICAAAAA==.Aprilkat:BAAANQAECgIIAgAAAA==.',
Ar='Arcenwrit:BAAANQAECgQIBQAAAA==.Archonyx:BAAANQAECgEIAgAAAA==.Aredhele:BAAANQAECgIIAgAAAA==.Arlanaria:BAAANQADCgcIDQAAAA==.Arundal:BAAANQAECgcIDQAAAA==.',
As='Asamara:BAAANQADCgUICwAAAA==.Ashwathama:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Astaril:BAAANQAECgEIAQAAAA==.Asttrixe:BAAANQADCgIIAgAAAA==.',
Au='Auri:BAAANQAECgQIBQAAAA==.Auriana:BAAANQADCgYIEAAAAQ==.Aurithel:BAAANQADCgQICgABNQADCgYIEAABAAAAAQ==.',
Av='Avelaara:BAAANQADCgcICgAAAA==.Avren:BAAANQADCgEIAQAAAA==.',
Aw='Awakia:BAAANQADCgIIAgAAAA==.Awooweewaa:BAEANQAECgIIAgAAAA==.',
Az='Azarix:BAAANQADCggIDwAAAA==.Azdaja:BAAANQADCgQICgABNQAECgQIBQABAAAAAA==.Azinosuke:BAAANQAECgMIAwAAAA==.Azriathi:BAAANQADCgYIBgAAAA==.Azrilia:BAAANQADCggICAAAAA==.Azstrixe:BAAANQADCgYIBgAAAA==.',
Ba='Baconbaby:BAAANQAECgIIAgAAAA==.Balbimlin:BAAANQAECgIIAgAAAA==.Baneblades:BAAANQADCgYICAAAAA==.Banggoes:BAAANQADCggIEAAAAA==.Banonir:BAAANQAECgQIBQAAAA==.Batuman:BAAANQADCggICAAAAA==.Baynz:BAAANQAECgYICQAAAA==.',
Be='Beckdormu:BAAANQADCggIEAAAAA==.Bekstar:BAAANQAECgQIBgAAAA==.Belnakor:BAAANQAECgQIBAAAAA==.Bewinator:BAAANQAECgcIDAAAAA==.',
Bi='Bigjoe:BAAANQAECgEIAQAAAA==.Bigs:BAAANQADCgcIBwAAAA==.Billy:BAAANQAECgYICAAAAA==.Binnie:BAAANQAFFAIIAgAAAA==.Bixwar:BAAANQAECgEIAQAAAA==.',
Bl='Blackwing:BAAANQADCgQIBAAAAA==.Blatsphemare:BAAANQADCgcIDAAAAA==.',
Bo='Bobhots:BAAANQADCgYICwAAAA==.Bongfury:BAAANQAECgEIAQAAAA==.Boomerite:BAAANQADCgcIDAAAAA==.Boomshaka:BAAANQAECgQIBAAAAA==.Boostwunk:BAAANQADCggICgAAAA==.Bosswamdi:BAAANQAECgUICQAAAA==.Bouch:BAAANQAECgQIBQAAAA==.Boujee:BAAANQAECgEIAQAAAA==.',
Br='Brakenjan:BAAANQADCgEIAQAAAA==.Break:BAAANQADCgMIAwAAAA==.Brewzleé:BAAANQADCgQIBAAAAA==.Brickfield:BAAANQADCgUIBQAAAA==.Brillybril:BAAANQAECgEIAQAAAA==.Browngirl:BAAANQADCggIDgAAAA==.Brownonion:BAAANQAECgEIAQAAAA==.Broxstar:BAAANQADCggICAAAAA==.Brutalpala:BAAANQADCgIIAgAAAA==.Brutalshammy:BAAANQAECgQIBAAAAA==.',
Bu='Buffalot:BAAANQADCgQICAAAAA==.Bundaburg:BAAANQADCggIDwAAAA==.Busting:BAAANQADCgcIDQAAAA==.',
Ca='Caean:BAAANQADCgYICwAAAA==.Caelthus:BAAANQADCgEIAQAAAA==.Captplanetz:BAAANQAECgcICwAAAA==.Cargrim:BAAANQAECgEIAQAAAA==.Carnacki:BAAANQADCgYIBgAAAA==.Catmoncorgi:BAAANQAECgcIDAABNQAFFAIIAgABAAAAAA==.Caywen:BAAANQADCggICgAAAA==.',
Ce='Celaxus:BAAANQAECgEIAQAAAA==.Celish:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Cerrast:BAAANQAECgMIBgAAAA==.',
Ch='Chaosdots:BAAANQADCgYIBgAAAA==.Charben:BAAANQADCgQIBgAAAA==.Chickade:BAAANQADCgQIBAAAAA==.Chickekk:BAAANQAECgcIDAAAAA==.Chips:BAAANQAFFAIIAgAAAA==.Chowder:BAAANQADCggICQAAAA==.',
Cj='Cjhunter:BAAANQAECgMIAwAAAA==.Cjshammy:BAAANQAECgMIAwAAAA==.',
Ck='Ckc:BAAANQAECgQIBAAAAA==.',
Cl='Cliege:BAAANQADCgYIBwAAAA==.Cloutermage:BAAANQAECgUIBQAAAA==.Clr:BAAANQADCgYIEAAAAA==.',
Co='Coldrethreth:BAAANQADCgUICQAAAA==.Conystus:BAAANQADCgQIBAAAAA==.Corpsemere:BAAANQADCgMIAwAAAA==.Cowoflife:BAAANQAECgQICgAAAA==.',
Cr='Crazee:BAAANQADCgYICwAAAA==.Crimdal:BAAANQAECgYIBgAAAA==.Crunchadin:BAAANQADCgcIDQAAAA==.',
Cx='Cxzza:BAAANQAECgEIAQAAAA==.',
Da='Dahdahdahw:BAAANQABCgIIAgAAAA==.Dalston:BAAANQADCgcIDQAAAA==.Damarah:BAAANQAFFAIIAgAAAA==.Dannerus:BAAANQADCgUIBwAAAA==.Danotia:BAAANQADCgUIBwAAAA==.Danthalian:BAAANQADCgUICgAAAA==.Darianus:BAAANQADCgYIDwAAAA==.Darkerella:BAAANQADCgQIBwABNQADCgcIDgABAAAAAA==.Darkrose:BAAANQAECgYICQAAAA==.Darthcutie:BAAANQADCgYIBgAAAA==.Daspp:BAAANQADCgIIAgAAAA==.Dato:BAAANQAECgEIAQAAAA==.Davebutblue:BAAANQADCgUIBQAAAA==.',
De='Deadcalm:BAAANQADCgIIAgAAAA==.Deathdealers:BAAANQADCggICAAAAA==.Deathlen:BAAANQADCgQIBAABNQAECgcIDQABAAAAAA==.Deathlyclown:BAAANQAECgQIBAAAAA==.Deathlypach:BAAANQADCggIDgAAAA==.Deathnerrisa:BAAANQADCgYIBgABNQADCggIDgABAAAAAA==.Deathrange:BAAANQAECgUICgAAAA==.Decawraith:BAAANQAECgYICAAAAA==.Decitar:BAAANQADCggIDAABNQAECgcICwABAAAAAA==.Dekïngrekt:BAAANQAECgEIAQAAAA==.Desura:BAAANQAECgEIAQAAAA==.Dex:BAAANQAECgEIAQAAAA==.Deysona:BAAANQADCgMIAwABNQAECgYICAABAAAAAA==.Deãthnchaos:BAAANQADCgQIBAAAAA==.',
Di='Dileyna:BAAANQADCgUICQAAAA==.Dirtbike:BAAANQAECgEIAQAAAA==.Discretion:BAAANQADCgUIBgAAAA==.Dismàl:BAAANQAECgUIBQAAAA==.Divinarius:BAAANQADCgEIAQAAAA==.Dizzyfrizz:BAAANQADCgQIBAAAAA==.Dizzygrizz:BAAANQADCgQIBQAAAA==.',
Dj='Djabooty:BAAANQADCgYICQAAAA==.Djarin:BAAANQADCgYICAABNQADCgcICgABAAAAAA==.',
Dk='Dkarth:BAAANQADCgYIBgAAAA==.Dkinaböx:BAAANQAECgEIAQAAAA==.',
Do='Doktor:BAAANQADCgUIBQAAAA==.Donnlock:BAAANQAECgEIAQAAAA==.Doob:BAAANQAECgYICQAAAA==.Dovatomt:BAAANQADCggICAAAAA==.',
Dr='Dragonsaint:BAAANQAECgEIAQAAAA==.Draik:BAAANQADCgMIAwAAAA==.Dranoth:BAAANQADCgMIBAAAAA==.Dreadzie:BAAANQADCggIEAAAAA==.Dreadzz:BAAANQADCgcIBwABNQADCggIEAABAAAAAA==.Dreary:BAAANQADCgYICwAAAA==.Drogodoth:BAAANQADCgYICgAAAA==.Droopsy:BAAANQADCgIIAgAAAA==.Dryhemp:BAAANQAECgMIAwAAAA==.Dryx:BAAANQADCgYIBgAAAA==.',
Du='Dunghai:BAAANQADCgYIBgAAAA==.',
['Dé']='Déaxta:BAAANQADCgcIDQAAAA==.',
Ea='Eastty:BAAANQAECgYICQAAAA==.Eatrootnleaf:BAAANQADCgIIBAAAAA==.',
Ed='Edrooney:BAAANQAECgIIAgAAAA==.',
Eg='Eggyokegamer:BAAANQAECgEIAgAAAA==.',
Ei='Eisenschutz:BAAANQADCgIIBAAAAA==.',
El='Eldodo:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.Eldr:BAAANQAECgEIAQAAAA==.Eletyre:BAAANQAECgUICgAAAA==.Elliann:BAAANQADCggIDgAAAA==.Elwìngs:BAAANQAECgEIAQAAAA==.',
Em='Emchi:BAAANQAECgcIDAABNQAFFAIIAwABAAAAAA==.Emeli:BAAANQADCgYIBgAAAA==.',
En='Enderosi:BAAANQAECgIIAgAAAA==.Englshmuffn:BAAANQAECgQIBAAAAA==.Enigmazole:BAAANQADCgUICgABNQAFFAIIAgABAAAAAA==.',
Er='Erereas:BAAANQAECgEIAgAAAA==.Eryndor:BAAANQABCgQIBQAAAA==.',
Es='Esaul:BAAANQADCgYIBgAAAA==.Eshaybruh:BAAANQADCgMIBAAAAA==.',
Ev='Everdream:BAAANQAECgEIAQAAAA==.',
Ex='Exovenator:BAAANQAFFAIIAgAAAA==.',
Ez='Ezoth:BAAANQADCgEIAQAAAA==.',
Fa='Faithguard:BAAANQADCgYIBgAAAA==.Faizoo:BAAANQADCgUIBQAAAA==.Faizzah:BAAANQADCgcIBwAAAA==.Falassion:BAAANQADCgYICgAAAA==.Faloria:BAAANQADCgQIBAABNQADCgcICQABAAAAAA==.Fandraynna:BAAANQADCgMIBAAAAA==.Faranir:BAAANQAECgEIAgAAAA==.Fawni:BAAANQAECgMIBQAAAA==.Fazzadru:BAAANQADCgQIBwAAAA==.',
Fe='Fergasmo:BAAANQAECgIIAgAAAA==.Ferny:BAAANQADCgYIBgAAAA==.Ferragus:BAAANQADCgcIDQAAAA==.',
Fi='Finalsigma:BAAANQAECgIIAgAAAA==.Finlan:BAAANQADCggICgAAAA==.Fistsofchaos:BAAANQADCgYIBgAAAA==.',
Fl='Flickascale:BAAANQADCgYICwAAAA==.Flossytop:BAAANQADCgYICAAAAA==.Flutterhoof:BAAANQADCgUIBwABNQADCgcIDgABAAAAAA==.Flybubye:BAAANQADCgUICAAAAA==.Flykickednan:BAAANQAECgEIAQAAAA==.',
Fo='Formsfriend:BAAANQAECgQIDAAAAA==.Foxxglove:BAAANQAECgIIBAAAAA==.',
Fr='Freakytouch:BAAANQAECgEIAQAAAA==.Friesnaioli:BAAANQADCgIIAgAAAA==.Friya:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.Frostmore:BAAANQADCgQIBgAAAA==.Frostyveins:BAAANQADCggIDgAAAA==.',
Fu='Furbý:BAAANQAECgEIAQAAAA==.',
Fy='Fythir:BAAANQADCgMIAwAAAA==.',
Ga='Gaberiel:BAAANQADCgcIDQAAAA==.Galaron:BAAANQADCgQICQAAAA==.Gavo:BAAANQADCgcIDQAAAA==.',
Ge='Gentayangan:BAAANQADCgQIBAABNQAECgEIAgABAAAAAA==.',
Gh='Ghillian:BAAANQADCgEIAQAAAA==.',
Gi='Gilfit:BAAANQADCgUIBQAAAA==.Gilgámesh:BAAANQAECgcIDAAAAA==.Gilreis:BAAANQADCgYIBgAAAA==.Gimpmama:BAAANQAECgYICQAAAA==.',
Go='Goldeer:BAAANQADCgQIBAAAAA==.Gorwrath:BAAANQAECgQICAAAAA==.Gotrek:BAAANQADCgYIEAAAAA==.',
Gr='Greybalgruf:BAAANQAECgEIAQAAAA==.Grimakh:BAAANQADCgcIDQAAAA==.Gruesome:BAAANQADCgYICwABNQADCgEIAQABAAAAAA==.Gruesomely:BAAANQADCgEIAQAAAA==.Grânite:BAAANQADCgUIBQAAAA==.',
Gy='Gypse:BAAANQAECgQIBQAAAA==.Gypsi:BAAANQADCgQICgAAAA==.',
['Gõ']='Gõdly:BAAANQADCgEIAQAAAA==.',
Ha='Hadouken:BAAANQAECgQIBAAAAA==.Halleydinde:BAAANQADCggICQAAAA==.Hargol:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Hasunstraza:BAAANQADCgUICAAAAA==.Hayhatchie:BAAANQAECgEIAQAAAA==.Hazel:BAAANQADCggICQAAAA==.Hazèful:BAAANQADCggIEAAAAA==.',
He='Heirophant:BAAANQADCgcIDAAAAA==.Hellisha:BAAANQADCgYIBgAAAA==.Henwee:BAAANQADCgYIEAAAAA==.Herborial:BAAANQADCgcICgAAAA==.Hex:BAAANQADCggICQAAAA==.Hexxage:BAAANQADCgcIBwAAAA==.Hezekïel:BAAANQADCgMIAwAAAA==.',
Hi='Hilfy:BAAANQAECgEIAgAAAA==.Hixl:BAAANQAECgEIAQAAAQ==.',
Ho='Holyfoxclaws:BAAANQADCgcIDgAAAA==.Hongtoufa:BAAANQADCgQICgAAAA==.Hopskipjump:BAAANQAECgQIBAAAAA==.Hoshiyomi:BAAANQAECgEIAQAAAA==.Hotpink:BAAANQADCgIIAgABNQADCgcIEwABAAAAAA==.Hotpocket:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Hotshöt:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
['Hé']='Hétzu:BAAANQADCgIIAgAAAA==.',
Ic='Icyberry:BAAANQAECgIIAgAAAA==.',
If='If:BAAANQAECgQIBAAAAA==.',
Ik='Iklehannican:BAAANQADCgUIBQAAAA==.Ikneb:BAAANQADCgcICQAAAA==.',
Im='Imohsdk:BAAANQAECgQIBAAAAA==.Impmama:BAAANQAECgYICQAAAA==.',
In='Inariarse:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Insomniac:BAAANQADCgMIAwAAAA==.',
Ir='Ireneroev:BAAANQAECgQIBAAAAA==.Ireneropr:BAAANQADCgYICwABNQAECgQIBAABAAAAAA==.Irrelevance:BAAANQAECgQIBQAAAA==.',
Is='Isenpal:BAEANQADCggIDwAAAA==.',
It='Ithleron:BAAANQADCggIDwAAAA==.Itsriv:BAAANQAECgMIBgAAAA==.',
['Iç']='Içy:BAAANQAECgQIBgAAAA==.',
Ja='Jackpawt:BAAANQADCgIIBAAAAA==.Jainaproudmo:BAAANQAECgcIDAAAAA==.Jallopeno:BAAANQAECgEIAQAAAA==.Jastar:BAAANQAECgIIAQAAAA==.Jawatko:BAAANQADCgYICgAAAA==.Jayzin:BAAANQAECgYICQAAAA==.Jazzyfizzle:BAAANQADCgcIDQAAAA==.',
Jb='Jboomy:BAAANQADCgcICQABNQAECgcIBwABAAAAAA==.',
Je='Jenniku:BAAANQADCgIIAgAAAA==.',
Ji='Jimmyrecard:BAAANQADCgQIBwAAAA==.Jimscautery:BAAANQAECgEIAQAAAA==.Jimshealing:BAAANQADCgYIBwAAAA==.',
Jl='Jlãb:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.',
Jo='Joestjoe:BAAANQADCggIDAAAAA==.Jonesysz:BAAANQAECgEIAgAAAA==.Joofheart:BAAANQADCgYIBgAAAA==.Jorick:BAAANQAECgQIBgAAAA==.Jormungand:BAAANQADCggIDgAAAA==.Jormunter:BAAANQADCgYICwAAAA==.',
Ju='Judzia:BAAANQADCgYICgAAAA==.Juggérnaut:BAAANQAECgIIAgAAAA==.Juguan:BAAANQADCgQIBAAAAA==.Justclick:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Ka='Kadôs:BAAANQAECgMIBAAAAA==.Kaggon:BAAANQADCgUIBgABNQAECgQIBQABAAAAAA==.Kaigha:BAAANQABCgQIAwAAAA==.Kainendh:BAAANQAFFAIIAgAAAA==.Kaizen:BAAANQADCgYIEAAAAA==.Kamiikazee:BAAANQAECgcIDQAAAA==.Karlise:BAAANQADCgEIAQAAAA==.Katheriina:BAAANQADCgcIDgAAAA==.Kattarinna:BAAANQADCgcICgAAAA==.Kattiiee:BAAANQAECgIIAgAAAA==.Katyia:BAAANQADCgMIAwAAAA==.Kayubi:BAAANQADCgIIAwAAAA==.Kazer:BAAANQAECgIIAgAAAA==.Kazutaka:BAAANQAECgIIAgAAAA==.Kazx:BAAANQADCggIBwAAAA==.Kaìtlyn:BAAANQAECgMIBQAAAA==.',
Ke='Kehlaina:BAAANQADCggIDAAAAA==.Kesh:BAAANQADCgMIAwAAAA==.',
Kh='Khaal:BAAANQAECgYIBgAAAA==.Khanethus:BAAANQADCggIDAAAAA==.Kharli:BAAANQADCgYICgAAAA==.',
Ki='Kidstuff:BAAANQAECgEIAQAAAA==.Kijin:BAAANQADCggIDwAAAA==.Kikashi:BAAANQADCgIIAgAAAA==.Kinko:BAAANQADCgUIDAAAAA==.Kiped:BAAANQAECgEIAQAAAA==.Kirlen:BAAANQAECgcIDAAAAA==.Kisschasey:BAAANQADCgYIBgAAAA==.',
Kl='Kleb:BAAANQADCggIDgAAAA==.',
Kn='Kny:BAAANQADCgYIDAAAAA==.',
Kr='Kruzt:BAAANQAECgEIAQAAAA==.',
Ky='Kyrièl:BAAANQADCgcIDQAAAA==.',
La='Laihoxi:BAAANQADCggIDAAAAA==.Lalwenya:BAAANQAECgEIAQAAAA==.Lantanis:BAAANQAECgEIAQAAAA==.',
Le='Lebronion:BAAANQADCgUIBQAAAA==.Levares:BAAANQADCggIDwAAAA==.',
Li='Lieken:BAAANQAECgMIBgAAAA==.Linestanas:BAAANQAECgEIAgAAAA==.Lirrah:BAAANQADCgYIBgAAAA==.',
Lo='Lorkel:BAAANQADCgcIBwAAAA==.Lottiee:BAAANQADCgYICgAAAA==.',
Lu='Lucero:BAAANQADCggICgAAAA==.Luminel:BAAANQAECgcIDAAAAA==.Lunaleri:BAAANQADCggIDgAAAA==.Lunguci:BAAANQADCggIDgAAAA==.',
['Lë']='Lëndis:BAAANQADCgYIDQAAAA==.',
['Lì']='Lìfebinder:BAAANQADCgcICgAAAA==.',
Ma='Madgettie:BAAANQAECgQIBQAAAA==.Madross:BAAANQADCgcIDQAAAA==.Maevis:BAAANQADCgYICwAAAA==.Magadin:BAAANQAFFAIIAgAAAA==.Magiclock:BAAANQADCgcIDgAAAA==.Magictuxedo:BAAANQADCggICAAAAA==.Magicwaffles:BAAANQADCgQIBQAAAA==.Magnayah:BAAANQADCgcIDQAAAA==.Magretta:BAAANQADCgYICAAAAA==.Mainblitz:BAAANQADCgcIBwAAAA==.Maladria:BAAANQAECgEIAQABNQAECgYICAABAAAAAA==.Malastraza:BAAANQAECgEIAQAAAA==.Mandamar:BAAANQAECgcIDQAAAA==.Mariio:BAAANQADCgYIDQAAAA==.Mashd:BAAANQADCggIDgAAAA==.Matt:BAAANQADCgYICQAAAA==.Matthias:BAAANQADCgcIDQAAAA==.Mattiblood:BAAANQADCgYIBgAAAA==.Mavv:BAAANQAECgEIAQAAAA==.Maxiless:BAAANQADCggIEAAAAA==.Maxpowaah:BAAANQADCgYICAAAAA==.Maxumas:BAAANQAECgEIAQAAAA==.',
Mc='Mcflurry:BAAANQADCggICQAAAA==.',
Me='Megapet:BAAANQADCgcIDgAAAA==.Melancholy:BAAANQAECgEIAQAAAA==.Melliena:BAAANQAECgMIBgAAAA==.Metajücy:BAAANQADCgMIBQAAAA==.',
Mi='Milkyway:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Miloiced:BAAANQADCggIDgAAAA==.Mimosa:BAAANQADCggICAAAAA==.Minae:BAEANQAECgQIBAABNQAECgcICQABAAAAAA==.Mistjester:BAAANQAECgEIAQAAAA==.Mistyc:BAAANQAECgUICwAAAA==.Mistycbicdig:BAAANQAECgMIBQABNQAECgUICwABAAAAAA==.Mitsue:BAEANQAECgcICQAAAA==.',
Mj='Mjay:BAAANQADCggIEAAAAA==.',
Mo='Moffmatiks:BAAANQADCgcIDQAAAA==.Momspriest:BAAANQADCgcIDQAAAA==.Monika:BAAANQADCgQICAAAAA==.Moonstorm:BAAANQADCgcIDQAAAA==.Moophus:BAAANQADCgQIBAABNQADCgcIDQABAAAAAA==.Moraykings:BAAANQAECgYICgAAAA==.Morbthegreat:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Morbzz:BAAANQAECgEIAQAAAA==.Morgoloth:BAAANQADCgYIBgAAAA==.',
Mu='Muggles:BAAANQADCggICAAAAA==.Munabuunii:BAAANQAECgcICwAAAA==.Munch:BAAANQADCgcIDQAAAA==.Musclethighs:BAAANQADCggICwABNQADCggIDgABAAAAAA==.',
My='Mybâd:BAAANQADCggICAAAAA==.Myehv:BAAANQADCgcICgAAAA==.Mylowe:BAAANQADCggIEAAAAA==.Myneckmyback:BAAANQADCggICAAAAA==.Mysticshadow:BAAANQAECgYIDAAAAA==.Mystimonk:BAAANQADCgUIBQABNQAECgYIDAABAAAAAA==.Mystèrion:BAAANQADCgEIAQAAAA==.',
['Mô']='Môth:BAAANQAECgEIAgAAAA==.',
Na='Naacho:BAAANQAECgcICwAAAA==.Naachoh:BAAANQADCgIIAgABNQAECgcICwABAAAAAA==.Nachomage:BAAANQADCgYIBgABNQAECgcICwABAAAAAA==.Nadyae:BAAANQADCggIDgAAAA==.Nas:BAAANQAECgQIBQAAAA==.Nasayuki:BAAANQAECgEIAQAAAA==.Nasmilk:BAAANQADCgYIDAAAAA==.',
Ne='Nehdrake:BAAANQADCggICQAAAA==.Nelth:BAAANQADCgYIDAAAAA==.Nerancis:BAAANQADCgQIBAAAAA==.Nerastrasza:BAAANQADCgYIEAAAAA==.Nerrisa:BAAANQADCggIDgAAAA==.Nety:BAAANQAFFAIIAgAAAA==.Nexx:BAAANQADCgQICAABNQADCgYIEAABAAAAAA==.Neytiriee:BAAANQADCgQIBQAAAA==.Nezihs:BAAANQADCggIDwAAAA==.',
Ni='Niftybeasty:BAAANQADCgYIDQAAAA==.Nightmarexx:BAAANQAECgIIAwAAAA==.Nightwish:BAAANQADCgQIBAAAAA==.Nihilus:BAAANQAECgQIBQAAAA==.Nihlus:BAAANQADCgcIDAAAAA==.Nish:BAAANQADCgcIDgAAAA==.',
No='Noblepark:BAAANQAECgQICAAAAA==.Noirpalm:BAAANQADCggIDwAAAA==.Nonothing:BAAANQADCgYIBgAAAA==.Noona:BAAANQADCgcIDAAAAA==.Norwyck:BAAANQADCgYICwAAAA==.Notjuzzie:BAAANQAECgIIAgAAAA==.Notvie:BAAANQADCgYIBgABNQADCgYICwABAAAAAA==.',
Nu='Nudtharion:BAAANQADCgYIEAAAAA==.',
Ob='Obbi:BAAANQAECgEIAgAAAA==.Obesewikaman:BAAANQADCggIDgAAAA==.',
Ol='Olyhornz:BAAANQAECgUIBQAAAA==.',
Om='Omatikayar:BAAANQAECgQIBAAAAA==.Omegacub:BAAANQADCgUIDQAAAA==.',
On='Onejobmoon:BAAANQADCgQIBAAAAA==.Oneo:BAAANQAECgcIDAAAAA==.',
Oo='Oomma:BAAANQAECgYICQAAAA==.',
Or='Oralock:BAAANQADCgcICwAAAA==.Orczilla:BAAANQAECgIIBAAAAA==.',
Os='Osirris:BAAANQADCggICAAAAA==.',
Pa='Pahnicious:BAAANQADCgUIBwAAAA==.Palalord:BAAANQADCgYIBgAAAA==.Paliotank:BAAANQADCgcIDQAAAA==.Pallyperson:BAAANQAECgEIAQAAAA==.Pallytato:BAAANQAECgQICAAAAA==.Parallaxian:BAAANQAECgEIAgAAAA==.Pariroa:BAAANQADCgUIBQAAAA==.',
Pe='Pedros:BAAANQAECgQIBgAAAA==.Peggbundy:BAAANQAECgIIAgAAAA==.Pentahealixx:BAAANQADCggIDwAAAA==.Peon:BAAANQADCgcIDgAAAA==.Perisauce:BAAANQADCgYICgAAAA==.Pew:BAAANQAECgUIBQAAAA==.',
Ph='Phaidor:BAAANQADCgUIBQAAAA==.Phenomblack:BAAANQAECgIIAgAAAA==.Phil:BAAANQADCggIDgAAAA==.',
Pi='Pinkadin:BAAANQADCgcIEwAAAA==.',
Pl='Plastique:BAAANQADCgcIDQAAAA==.Plopperjr:BAAANQAECgYICQAAAA==.',
Po='Pokemonster:BAAANQADCggIEAABNQAECgcIDAABAAAAAA==.Ponendus:BAAANQADCgYICwAAAA==.Popalot:BAAANQADCgYICwAAAA==.Potatoshoes:BAAANQAECgcICwAAAA==.',
Pr='Prepared:BAAANQAECgQICAAAAA==.Priestlydots:BAAANQAECgEIAQAAAA==.Priestlåd:BAAANQADCgUIBwAAAA==.',
Pu='Puddiin:BAAANQADCgQICAAAAA==.',
Py='Py:BAAANQADCggIDgAAAA==.Pyrothermia:BAAANQAECgYIBgAAAA==.Pyzrlil:BAAANQAECgEIAQAAAA==.',
['Pé']='Pérsephóne:BAAANQAECgUIBQAAAA==.',
['Qü']='Qüelaag:BAAANQADCgIIAgABNQAECgYICQABAAAAAA==.',
Ra='Raeleth:BAAANQAECgEIAQAAAA==.Rageissues:BAAANQAECgQIBQAAAA==.Rainiar:BAAANQAECgcIBwAAAA==.Rambutan:BAAANQADCgcIBwAAAA==.Rascalanger:BAAANQADCgcIDQAAAA==.Rastaloth:BAAANQAECgIIAgAAAA==.Raurr:BAAANQADCgEIAQAAAA==.Ravýn:BAAANQAECgEIAQAAAA==.Raybans:BAAANQADCgIIAgAAAA==.',
Re='Reedy:BAAANQAECgYICwAAAA==.Reililim:BAAANQADCgIIAgAAAA==.Reladria:BAAANQAECgYICAAAAA==.Renren:BAAANQADCgcIDgAAAA==.Renrenboomy:BAAANQADCgcIBwAAAA==.Rentheous:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.Restopig:BAAANQAECgEIAQAAAA==.Retage:BAAANQAECgMIBQAAAA==.Retbro:BAAANQADCgUIBQAAAA==.Revii:BAAANQAECgEIAQAAAA==.',
Rh='Rhinock:BAAANQADCgUIBQAAAA==.Rhinoh:BAAANQADCgcIDQAAAA==.Rhyfelpod:BAAANQAECgUIBgAAAA==.Rhymenocerus:BAAANQADCgQIBAAAAA==.',
Ri='Riftera:BAAANQADCgYICwABNQAECgcIDQABAAAAAA==.Ringostaarr:BAAANQADCgYIBgAAAA==.Rinkleesak:BAAANQADCgMIBgABNQAECgUICwABAAAAAA==.Ripiggy:BAAANQADCggICAAAAA==.Ripto:BAAANQADCgIIAgAAAA==.Rivi:BAAANQADCgcICwABNQAECgMIBgABAAAAAA==.',
Ro='Roeilai:BAAANQADCgMIBAAAAA==.Rogbert:BAAANQAECgQIBAAAAA==.Roidboss:BAAANQADCggIDwAAAA==.Rokarn:BAAANQAECgQICAAAAA==.',
Rr='Rr:BAAANQAECgQICAAAAA==.',
Ry='Rysan:BAAANQADCggICQABNQAECgEIAQABAAAAAA==.',
Sa='Saani:BAAANQADCggIDgAAAA==.Saber:BAAANQAECgIIAgAAAA==.Sabré:BAAANQADCggICAAAAA==.Sadoderé:BAAANQADCggIDgAAAA==.Saelor:BAAANQAFFAEIAQAAAA==.Saennia:BAAANQAECgEIAQAAAA==.Saetan:BAAANQADCgQIBAAAAA==.Sagje:BAAANQADCggIDgAAAA==.Sagé:BAAANQADCggIDgAAAA==.Salestra:BAAANQADCgIIAgAAAA==.Saloondoors:BAAANQAECgQIBQAAAA==.Sameara:BAAANQADCgYIDAAAAA==.Samila:BAAANQADCggIDgAAAA==.Sandioncrack:BAAANQAECgEIAgAAAA==.Sareila:BAAANQADCgcIDQAAAA==.Savaris:BAAANQADCgYIEAAAAA==.Savis:BAAANQAECgUIBwAAAA==.',
Sc='Scatho:BAAANQADCgYIBgAAAA==.',
Se='Seakay:BAAANQADCgYIBgAAAA==.Seladang:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Selenabowmez:BAAANQAECgIIAgAAAA==.Serdeath:BAAANQADCgMIAwAAAA==.Servellan:BAAANQADCgIIAgAAAA==.',
Sf='Sfetti:BAAANQAECgUIBgAAAA==.',
Sh='Shabar:BAAANQAECgYICQAAAA==.Shadowarrior:BAAANQADCgYIBgAAAA==.Shadowevil:BAAANQADCgcIDQAAAA==.Shadowmoonn:BAAANQADCgMIAwAAAA==.Shaimara:BAAANQAECgcICwAAAA==.Shaimu:BAAANQADCgcIAgAAAA==.Shamayonaise:BAAANQAECgQIBQAAAA==.Shamosh:BAAANQADCggICgAAAA==.Sharrowsham:BAAANQADCggICAAAAA==.Sherkizk:BAAANQAECgEIAQAAAA==.Shiomi:BAAANQAECgQIBAAAAA==.Shivhappens:BAAANQADCgYICwAAAA==.Shockolat:BAAANQADCgYIBgAAAA==.Shopintrolli:BAAANQADCgYIDgAAAA==.Shottigrippa:BAAANQADCgUIBQAAAA==.',
Si='Sible:BAAANQADCgQICgAAAA==.Siilver:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Sikla:BAAANQADCggICAAAAA==.Silverbreeze:BAAANQAECgEIAQAAAA==.Simadin:BAAANQAECgEIAQAAAA==.Singletarget:BAAANQAECgQIBAAAAA==.',
Sk='Sk:BAAANQADCgcIDQAAAA==.Skaðizie:BAAANQADCgYIDgAAAA==.Skrunkly:BAAANQAECgEIAQAAAA==.Skullflare:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Skyrun:BAAANQADCgQIBwAAAA==.Skyíerxy:BAAANQAECgIIAgAAAA==.',
Sl='Slatefox:BAAANQAECgEIAQAAAA==.',
Sm='Smoothy:BAAANQAECgcICwAAAA==.',
Sn='Sniffington:BAAANQAECgIIAgAAAA==.Snotshöt:BAAANQAECgEIAQAAAA==.',
So='Sockadin:BAAANQADCgMIAwAAAA==.Sockhuntr:BAAANQADCgQIBAAAAA==.Solargeist:BAAANQADCgcIBwAAAA==.Sonoka:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Sooffy:BAAANQAECgQIBgAAAA==.Sor:BAAANQADCggIAQAAAA==.Soryu:BAAANQADCgIIAgAAAA==.',
Sp='Sparvo:BAAANQAECgEIAQAAAA==.Spawñ:BAAANQADCggIDgAAAA==.Spellwave:BAAANQADCggIEAAAAA==.Spiicy:BAAANQADCgMIAwABNQADCgMIAwABAAAAAA==.Splashzonë:BAAANQAECgEIAQAAAA==.Spootless:BAAANQADCggIDwAAAA==.Sprouters:BAAANQADCgEIAQAAAA==.Sprouties:BAAANQAECgUICgAAAA==.',
St='Stav:BAAANQADCggIDgABNQAECgcIDAABAAAAAA==.Stealthybaz:BAAANQADCggIDwAAAA==.Stickward:BAAANQADCgYICgAAAA==.Stoen:BAAANQAECgcIDAAAAA==.Stonetalent:BAAANQABCgQIBAAAAA==.Stormclaw:BAAANQAECgIIAgAAAA==.Streetjezus:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Strogganoff:BAAANQAECgEIAQAAAA==.Stòrmy:BAAANQADCgYIBgAAAA==.',
Su='Sulakin:BAAANQADCgYICwAAAA==.Sumatru:BAAANQAECgQIBQAAAA==.Sustained:BAAANQADCgYIBgAAAA==.Suwee:BAAANQAECgEIAQAAAA==.Suweetcheeks:BAAANQADCggIDwABNQAECgEIAQABAAAAAA==.Suzuchan:BAAANQAECgIIAgAAAA==.',
Sw='Swagrid:BAAANQAECgEIAQAAAA==.',
Sx='Sxix:BAAANQAECgEIAQAAAA==.',
Sy='Sygrogiàn:BAABNQAECoENAAMCAAgJTQdQKwBGAQACAAYJPgdQKwBGAQADAAQJpAR0HwCbAAAAAA==.Sylrune:BAAANQADCggIDgAAAA==.Syrenaria:BAAANQADCgUICgAAAA==.',
Ta='Taelthas:BAAANQADCggICgAAAA==.Tagazog:BAAANQADCgYIBgAAAA==.Tahlana:BAAANQADCgQIBwAAAA==.Takabuka:BAAANQADCgUIBQAAAA==.Takkumampu:BAAANQADCggICAAAAA==.Taladañ:BAAANQABCgQIBAAAAA==.Talanthae:BAAANQADCgIIAgAAAA==.Taserface:BAAANQAECgUIBgAAAA==.Tathagor:BAAANQADCgYIEAAAAA==.',
Te='Teachernote:BAAANQADCgUIBQAAAA==.Teaora:BAAANQADCgYIDgAAAA==.Tefli:BAAANQAECgIIAgAAAA==.Tenuki:BAAANQAECgIIAgAAAA==.',
Th='Theboo:BAAANQADCgYIBgABNQADCggICgABAAAAAA==.Thefaveazn:BAAANQADCgYICgAAAA==.Theimppimp:BAAANQABCgQIBAAAAA==.Thelayl:BAAANQAECgEIAgAAAA==.Themaladan:BAAANQADCgYICwABNQAECgEIAgABAAAAAA==.Theodoros:BAAANQADCgYIEAABNQAECgQIBQABAAAAAA==.Theolethros:BAAANQAECgQIBQAAAA==.Thewizeone:BAAANQADCggICAAAAA==.Thomö:BAAANQADCggICAAAAA==.Thorarchmage:BAAANQAECgEIAQAAAA==.Thorickto:BAAANQADCgcIDQAAAA==.Thorr:BAAANQAECgIIAgABNQAECgcIDAABAAAAAA==.Thorsky:BAAANQADCgUIBQAAAA==.Throatslit:BAAANQADCgMIAwAAAA==.Thunderfists:BAAANQADCgUIBQAAAA==.',
Ti='Tiberium:BAAANQAECgEIAQAAAA==.Tin:BAAANQAECgQIBQABNQADCgUIBQABAAAAAA==.Tipsyclick:BAAANQAECgQIBAAAAA==.Tirraz:BAAANQADCgYIBgAAAA==.Tirti:BAAANQADCgcIDQABNQAECgYICAABAAAAAA==.',
To='Tod:BAAANQADCgYIDAAAAA==.Toodlez:BAAANQAECgIIAgAAAA==.Toughmoecha:BAAANQAECgYICQAAAA==.',
Tr='Trenpanda:BAAANQADCggIDAAAAA==.Trinelle:BAAANQAECgEIAQAAAA==.Trorr:BAAANQADCgQIBAAAAA==.',
Ts='Tszyu:BAAANQADCgYICgAAAA==.',
Tt='Tthor:BAAANQAECgcIDAAAAA==.',
Tu='Tumbawumba:BAAANQADCggICQAAAA==.Turango:BAAANQADCgQICgABNQADCgYIEAABAAAAAA==.Turkandar:BAAANQADCgcIDQAAAA==.Turkinater:BAAANQADCgQICAAAAA==.',
Tw='Twidgey:BAAANQAECgIIAgAAAA==.',
Ty='Tydrocast:BAAANQADCgUIBQAAAA==.Tylamoriel:BAAANQADCgIIAgAAAA==.Typhouge:BAAANQADCgUIBQAAAA==.Tyrandewhis:BAAANQAECgQIBAABNQAECgcIDAABAAAAAA==.Tythramor:BAAANQAECgIIAgAAAA==.',
['Tó']='Tóomi:BAAANQAECgYICAAAAA==.',
Ul='Ulfvaar:BAAANQADCgcIBQAAAA==.',
Um='Umairah:BAAANQAECgUIBgAAAA==.Umbrageist:BAAANQABCgIIAgAAAA==.',
Un='Unbearable:BAAANQADCgYICgAAAA==.Unholyjlab:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Unmilkable:BAAANQAECgEIAQAAAA==.',
Ur='Urglefloggah:BAAANQADCgUIBwAAAA==.',
Uy='Uyko:BAAANQADCggIDwAAAA==.',
Va='Vabos:BAAANQADCgYIBgAAAA==.Vachan:BAAANQABCgQIBAAAAA==.Vaedor:BAAANQADCgYICgABNQADCggIDgABAAAAAA==.Vagiant:BAAANQAECgQIBgAAAA==.Vakahna:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Vako:BAAANQADCgUIBQAAAA==.Valea:BAAANQADCgYIDAAAAA==.Valenya:BAAANQAECgEIAgAAAA==.Valestraee:BAAANQADCgcIDAAAAA==.Valinys:BAAANQABCgIIAgAAAA==.Valkyrja:BAAANQADCgYICQAAAA==.Vandarkholme:BAAANQADCgYIBgAAAA==.Varantus:BAAANQADCgcIDQAAAA==.Varenda:BAAANQADCggIDgAAAA==.Varrior:BAAANQAFFAIIAgAAAA==.Vassallo:BAAANQAECgMIAwAAAA==.Vatcharin:BAAANQAECgEIAQAAAA==.',
Ve='Velvetdreams:BAAANQADCgMIBgAAAA==.Vengefilth:BAAANQAECgUIBgAAAA==.Veralei:BAAANQAECgEIAQAAAA==.Verrior:BAAANQAFFAIIAgAAAA==.Veshale:BAAANQADCgIIAgAAAA==.Vesherok:BAAANQADCgYIBgAAAA==.Veylira:BAAANQADCgcICAAAAA==.',
Vi='Vic:BAAANQADCggIDgAAAA==.Viebae:BAAANQADCgEIAQABNQADCgYICwABAAAAAA==.Viebai:BAAANQAECgMIAwABNQADCgYICwABAAAAAA==.Viehi:BAAANQADCgYICwAAAA==.Viekay:BAAANQADCgUIBgABNQADCgYICwABAAAAAA==.Vienir:BAAANQADCgIIAgABNQADCgYICwABAAAAAA==.Vieno:BAAANQADCgcICgABNQADCgYICwABAAAAAA==.Vietoo:BAAANQADCgYIBwABNQADCgYICwABAAAAAA==.Vigilante:BAAANQAECgEIAQAAAA==.Vitalizes:BAAANQAECgQIBQAAAA==.',
Vo='Voidbunny:BAAANQABCgIIAgAAAA==.Voidmaple:BAAANQADCgYIDAAAAA==.Voidnerissa:BAAANQADCgcIBwABNQADCggIDgABAAAAAA==.Volatilehugs:BAAANQADCggICAAAAA==.',
Vu='Vulpeera:BAAANQABCgIIAQAAAA==.',
Vy='Vyndrolar:BAAANQADCgcIDAAAAA==.',
Wa='Wallpuncher:BAAANQADCgUIBwAAAA==.Warbsy:BAAANQADCgQIBQAAAA==.Warimoh:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Warlocknon:BAAANQADCgcIDAAAAA==.Warriorscott:BAAANQADCgcIDQAAAA==.Warstine:BAAANQAECgYICQAAAA==.Wasahk:BAAANQAECgEIAQAAAA==.Watchar:BAAANQAECgQIBQAAAA==.',
We='Wessa:BAAANQADCgcIBwAAAA==.Wetfur:BAAANQADCgYICQAAAA==.',
Wh='Whiskcy:BAAANQADCgYIDgAAAA==.',
Wi='Wifii:BAAANQADCgcICQAAAA==.Wilkie:BAAANQADCgcIDQAAAA==.Wilnikyastuf:BAAANQADCgcIDQAAAA==.Window:BAAANQADCgYIBwABNQADCggIDgABAAAAAA==.Winnygolds:BAAANQABCgMIBgAAAA==.',
Wo='Worgana:BAAANQAECgYICAAAAA==.Wotenhearg:BAAANQADCgUICAAAAA==.',
Wu='Wuffiandesu:BAAANQADCgUIBQAAAA==.',
Wy='Wyrdevoke:BAAANQAECgYICgAAAA==.',
['Wí']='Wíld:BAAANQADCgYIBgABNQAECgcIDQABAAAAAA==.',
['Wî']='Wîld:BAAANQAECgcIDQAAAA==.',
Xa='Xamchi:BAAANQADCgYIBgAAAA==.Xamhorns:BAAANQADCgcIBwAAAA==.Xandov:BAAANQAECgEIAQAAAA==.Xaner:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Xathrian:BAAANQADCgUIBQAAAA==.',
Xe='Xeropally:BAAANQADCggICAAAAA==.Xevrion:BAAANQAECgYICgAAAA==.',
Xi='Xifer:BAAANQAECgMIAwAAAA==.',
Xo='Xolialumbra:BAAANQAECgEIAQAAAA==.',
Xs='Xsurani:BAAANQAECgEIAQAAAA==.',
Ya='Yaimakmak:BAAANQADCgYIBgAAAA==.Yamargi:BAAANQADCggIDwAAAA==.',
Ye='Yeahbuggzy:BAAANQADCgUIBQAAAA==.',
Yh='Yhazzmine:BAAANQAECgEIAQAAAA==.',
Yo='Yohda:BAAANQAECgIIAgAAAA==.Yomumma:BAAANQAECgEIAQAAAA==.',
Ys='Ysabbell:BAAANQADCgYICwAAAA==.Ysone:BAAANQADCggIDgAAAA==.',
Za='Zaarkann:BAAANQADCgQIBgAAAA==.Zailen:BAAANQADCggIDwAAAA==.Zappymcblam:BAAANQAECgEIAQAAAA==.Zarba:BAAANQADCgcIDQAAAA==.Zariallyn:BAAANQADCggIDwAAAA==.',
Ze='Zebba:BAAANQAECgQIBAAAAA==.Zenky:BAAANQADCgQIBAAAAA==.Zephaeryn:BAAANQADCggIBAAAAA==.Zeykoyu:BAAANQADCggIDwAAAA==.',
Zi='Zigbiy:BAAANQADCgMIAwAAAA==.',
Zn='Znemde:BAAANQADCgYIBwAAAA==.',
Zo='Zollmalath:BAAANQADCgIIAgAAAA==.',
Zu='Zuczuc:BAAANQABCgIIAgAAAA==.Zumwalt:BAAANQAECgcICwAAAA==.Zunther:BAAANQADCgcIDQAAAA==.',
['Zú']='Zúës:BAAANQAECgEIAQABNQAECgUIBQABAAAAAA==.',
['Ðr']='Ðryks:BAAANQADCgYIBgAAAA==.',
['Ðu']='Ðurakwir:BAAANQADCgMIAwAAAA==.',
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
