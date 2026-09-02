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
local provider = {region='US',realm='Kargath',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abracadabruh:BAAANQAECgEIAQAAAA==.Absynthia:BAAANQADCgcIDQAAAA==.',
Ac='Academe:BAAANQADCgYICQAAAA==.',
Ad='Adérai:BAAANQAECgUIBwAAAA==.',
Ae='Aellopus:BAAANQADCgYIBgAAAA==.Aero:BAAANQADCggIDgAAAA==.',
Ag='Agròm:BAAANQADCgQIBAABNQADCgcICwABAAAAAA==.',
Ak='Akata:BAAANQADCgQIBQAAAA==.Akku:BAAANQADCgYIBwAAAA==.',
Al='Alanwake:BAAANQAECgEIAgAAAA==.',
Am='Amiliane:BAAANQADCggIDgAAAA==.Amoradine:BAAANQADCgYICwAAAA==.Amz:BAAANQADCgYIBwAAAA==.',
An='Anadrien:BAAANQADCgcIDQAAAA==.Ancelagon:BAAANQADCgYIBgAAAA==.Andrae:BAAANQADCgUICgAAAA==.Angrimia:BAAANQADCggIDgAAAA==.Annussa:BAAANQADCggIDAAAAA==.',
Ar='Arboria:BAAANQAECgYIAQAAAA==.Ardbeg:BAAANQABCgMIAwAAAA==.Arduin:BAAANQADCgcIDAAAAA==.Aremethea:BAAANQADCgYICwAAAA==.Aronk:BAAANQADCggIDgAAAA==.Arore:BAAANQADCgMIBAABNQADCggIDgABAAAAAA==.Aroreck:BAAANQADCgQIBAABNQADCggIDgABAAAAAA==.',
As='Asbjorn:BAAANQADCgQIBAAAAA==.',
At='Attack:BAAANQADCgIIAgABNQAECgYICAABAAAAAA==.',
Av='Avestara:BAAANQADCggIDgAAAA==.',
Az='Azoril:BAAANQAECgEIAQAAAA==.Azùla:BAAANQADCgYICQAAAA==.',
['Aí']='Aídeen:BAAANQADCggIDwAAAA==.',
Ba='Babs:BAAANQADCgEIAQAAAA==.Baelnorn:BAAANQAECgEIAQAAAA==.Basken:BAAANQADCgEIAQAAAA==.Batôsai:BAAANQADCgYICgAAAA==.',
Be='Beelz:BAAANQADCgYIBgAAAA==.Belaraariaae:BAAANQADCggICAABNQAECgYICAABAAAAAA==.Benipal:BAAANQAECgYICgAAAA==.Bernardboggs:BAAANQADCgcIDAAAAA==.',
Bh='Bheefknight:BAAANQAECgEIAQAAAA==.',
Bi='Bierbro:BAAANQAECgEIAQAAAA==.Billié:BAAANQAECgIIAgABNQAECgUICAABAAAAAA==.',
Bl='Blumir:BAAANQADCgQIBgAAAA==.',
Bo='Bomgan:BAAANQADCggIDgAAAA==.Bonchonn:BAAANQAECgYIBwAAAA==.Bonkula:BAAANQADCgQIBAAAAA==.Bops:BAAANQADCgUIBQAAAA==.Borque:BAAANQADCgcIDQAAAA==.Bosenmorimei:BAAANQADCgIIAgAAAA==.',
Br='Brae:BAAANQADCgQIBAAAAA==.Brazonk:BAAANQADCggIDgAAAA==.Brewzco:BAAANQAECgQIBAAAAA==.Briciferkong:BAAANQAECgcIDQAAAA==.Brickedup:BAAANQADCggIEAAAAA==.Brightblayde:BAAANQADCggIDgAAAA==.',
Bu='Buanto:BAAANQADCgUICQAAAA==.Bubblegumm:BAAANQADCgQIBAAAAA==.Bubbletea:BAAANQADCgcIDQABNQADCgQIBAABAAAAAA==.Butterball:BAAANQAECgQIBQAAAA==.',
Ca='Candlelock:BAAANQADCgQIBQAAAA==.Candlewic:BAAANQADCgYICgAAAA==.Cathal:BAAANQABCgIIAgAAAA==.Cattroll:BAAANQADCggIDgAAAA==.',
Ce='Celithila:BAAANQADCggIDgAAAA==.Celithvia:BAAANQADCggIDwAAAA==.Cervantés:BAAANQAECgQIBAAAAA==.',
Ch='Chaosknight:BAAANQADCgcIDQAAAA==.Charginatyou:BAAANQADCggIDwABNQAECgQICAABAAAAAA==.Chelsea:BAAANQADCgIIAgAAAA==.Chise:BAAANQAECgEIAQAAAA==.Chob:BAAANQADCgcICwAAAA==.',
Cl='Clarry:BAAANQADCgYIBgAAAA==.Clyde:BAAANQAECgEIAQAAAA==.Clydk:BAAANQADCgcIBwAAAA==.',
Co='Coachbeard:BAAANQAECgIIAwAAAA==.Colzaratha:BAAANQAECgIIAgAAAA==.Corndog:BAAANQAECgQIBAAAAA==.Cozzworth:BAAANQADCgEIAQAAAA==.',
Cu='Cudguzzler:BAAANQAECgIIAgAAAA==.Cursegoesmoo:BAAANQADCgEIAQAAAA==.Cursehoots:BAAANQAECgQIBQAAAA==.',
Cy='Cyntheria:BAAANQAECgEIAQAAAA==.',
Da='Daddybeàr:BAAANQAECgYIBwAAAA==.Daendron:BAAANQAECgIIAgAAAA==.Darksaxon:BAAANQADCgcIBwAAAA==.',
De='Deathnethal:BAAANQADCgYIBgAAAA==.Deathweaver:BAAANQAECgQIBAAAAA==.Deeneye:BAAANQADCgUICgAAAA==.Dellgado:BAAANQABCgMIBQAAAA==.Demonica:BAAANQADCgcIDQAAAA==.Demonscythe:BAAANQADCgUIBQAAAA==.Dendrax:BAAANQADCgYIBgAAAA==.Dented:BAAANQABCgQIBAAAAA==.Deviance:BAAANQADCgcIDAAAAA==.Dezwar:BAAANQADCgEIAQABNQAECggICwABAAAAAA==.',
Di='Dissonance:BAAANQADCgQIBAAAAA==.',
Dj='Djanga:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.Djdazzle:BAAANQADCgYIBwAAAA==.',
Do='Dorito:BAAANQADCgUIBQAAAA==.',
Dr='Dragooned:BAAANQAECgcICwAAAA==.Drango:BAAANQADCgMIAwAAAA==.Draugdae:BAAANQADCggIDgAAAA==.Drinksomuch:BAAANQADCgcIDQAAAA==.Drizzlin:BAAANQADCgYIBgAAAA==.Drob:BAEANQADCgYICwAAAA==.Drocket:BAEANQADCgYIBgAAAA==.Drome:BAAANQADCgEIAQABNQADCggIDgABAAAAAA==.Drukhi:BAAANQAECgEIAQAAAA==.',
Du='Dudetotems:BAAANQADCgcIBwAAAA==.Dungrough:BAAANQADCgcIDQAAAA==.Durtkal:BAAANQADCggIDgAAAA==.',
Dy='Dyonn:BAAANQADCgYICwAAAA==.',
Ef='Efarel:BAAANQAECgIIAgAAAA==.',
Ei='Eilana:BAAANQADCgcIDAAAAA==.',
El='Elsa:BAAANQAECgEIAQAAAA==.',
En='Eneco:BAAANQADCgQIBAAAAA==.Enserath:BAAANQADCgUIBgAAAA==.',
Eu='Eurythmics:BAAANQADCgMIAwAAAA==.',
Ex='Exelion:BAAANQAECgEIAQAAAA==.',
Ez='Ezrack:BAAANQADCgIIAgAAAA==.',
Fa='Faaith:BAAANQADCgMIAwAAAA==.Fahooquazaad:BAAANQADCgQIBwAAAA==.Fancy:BAAANQAECgEIAQAAAA==.',
Fe='Feetlesmcdee:BAAANQADCggICwAAAA==.',
Fi='Fitzy:BAAANQAECgQIBgAAAA==.',
Fl='Flowermound:BAAANQADCgUICQAAAA==.',
Fo='Fourqto:BAAANQADCgcICQAAAA==.Fox:BAAANQAECgcIDAAAAA==.',
Fr='Freya:BAAANQADCgUIBQAAAA==.',
Fu='Fujikujaku:BAAANQADCgYIBgAAAA==.Fulmetal:BAAANQAECgEIAQAAAA==.Funji:BAAANQADCgcIBwAAAA==.Funkalicious:BAAANQAECgMIAwAAAA==.',
['Fé']='Félo:BAAANQADCgcIDQAAAA==.',
Ga='Gaila:BAAANQAECgUICAAAAA==.Garathor:BAAANQABCgIIAwAAAA==.Garrosh:BAAANQABCgMIAwAAAA==.Garthoneeye:BAAANQADCgMIBAAAAA==.Gazreyna:BAAANQADCggIEAAAAA==.',
Ge='Genós:BAAANQAECgEIAQAAAA==.Gerardo:BAAANQADCgYICwAAAA==.',
Gi='Gigarawr:BAAANQAECgEIAQABNQAECgEIAgABAAAAAA==.Ginnee:BAAANQADCgUIBQAAAA==.',
Gl='Glakattack:BAAANQAECgQIBQAAAA==.Glein:BAAANQADCggIDgAAAA==.',
Go='Gooeyquiver:BAAANQADCgMIBQAAAA==.',
Gr='Graestoke:BAAANQADCgYICwABNQAECgQIBQABAAAAAA==.Greasermorty:BAAANQADCgMIAwAAAA==.Growls:BAAANQADCgcIDQAAAA==.Grundlegnome:BAAANQAECgQIBgAAAA==.',
Gu='Gurri:BAAANQADCgYICwAAAA==.',
['Gõ']='Gõldenchild:BAAANQADCgUICAAAAA==.',
Ha='Habenero:BAAANQADCgUICQAAAA==.Hairypitts:BAAANQADCgcIBwAAAA==.Happychaos:BAAANQADCgQIBAAAAA==.Haraniantha:BAAANQAECgYICAAAAA==.Hatean:BAAANQADCgYICQAAAA==.Hathor:BAAANQADCgYICAAAAA==.Hazzbek:BAAANQADCgYICQAAAA==.',
He='Heiboss:BAAANQADCggIDAABNQAECgEIAQABAAAAAA==.Heibub:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Heiranir:BAAANQADCggIDQABNQAECgEIAQABAAAAAA==.Heiretic:BAAANQADCggICgABNQAECgEIAQABAAAAAA==.',
Hi='Hikikomori:BAAANQADCggIDwABNQAECgQIBAABAAAAAA==.Hildegarde:BAAANQADCgcIDAAAAA==.Hinomiko:BAAANQADCgYIDAAAAA==.',
Ho='Holycowch:BAAANQADCgEIAQAAAA==.',
Hu='Huran:BAAANQAECgEIAQAAAA==.',
Ia='Iatemydad:BAAANQAECgMIBAAAAA==.',
Ic='Icéehawt:BAEANQADCgYICwABNQADCgUIBQABAAAAAA==.',
Ig='Ignignokt:BAEANQAECgQIBAAAAA==.',
Im='Imagine:BAAANQADCggIDgAAAA==.',
In='Inarush:BAAANQADCggIDwAAAA==.',
Iw='Iwishiknew:BAAANQADCgYIBAAAAA==.',
Iz='Iztras:BAAANQADCgEIAQAAAA==.',
Ja='Jabbtrak:BAAANQADCggIDgAAAA==.Jacklowry:BAAANQADCggIDgAAAA==.Jakiepoobear:BAAANQAECgQIBAAAAA==.Jambie:BAAANQADCgYICgAAAA==.',
Je='Jedery:BAAANQADCgcIDQAAAA==.',
Jo='Joroldess:BAAANQAECgEIAQAAAA==.Joyo:BAAANQADCgQIBAAAAA==.',
Ju='Juzam:BAAANQADCgIIAgAAAA==.',
Ka='Kahghär:BAAANQADCgMIAwABNQAECgcICwABAAAAAA==.Kahlly:BAAANQADCggIDgAAAA==.Kahndumb:BAAANQADCggIDAAAAA==.Kaida:BAAANQADCgQIBAAAAA==.Kaio:BAAANQADCgMIAwAAAA==.Kalahan:BAAANQADCgcIBwAAAA==.Kardrion:BAAANQADCgMIAwAAAA==.Karigyn:BAAANQADCggICAAAAA==.Katren:BAAANQADCgMIAwAAAA==.Katrienne:BAAANQADCggIDgAAAA==.Katrya:BAAANQABCgQIBAABNQADCggIDgABAAAAAA==.Kaylid:BAAANQADCgYIDAAAAA==.Kazzoth:BAAANQAECgEIAQAAAA==.',
Ke='Ketsuana:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Ki='Kilen:BAAANQABCgQIBAAAAA==.Kilimanjaro:BAAANQADCgIIAgAAAA==.Killjôy:BAAANQADCgIIAgAAAA==.Kimjongboom:BAAANQAECgYICAAAAA==.',
Kl='Klax:BAAANQADCgYICwAAAA==.Klondor:BAAANQADCggIDgAAAA==.Klz:BAAANQADCgQIBQAAAA==.Klzx:BAAANQADCggIDgAAAA==.',
Ko='Komo:BAAANQAECgcICwAAAA==.Konokusotare:BAAANQAECgEIAQAAAA==.Korbs:BAAANQADCggIDwAAAA==.Kortek:BAAANQADCgUIBQAAAA==.Korvold:BAAANQAECgEIAQAAAA==.',
Kr='Kreckon:BAAANQADCgUICAAAAA==.Kronn:BAAANQAECgEIAQAAAA==.Krypt:BAAANQADCgIIAgAAAA==.',
Ks='Kschnell:BAAANQADCgQIBQABNQAECgYICAABAAAAAA==.',
Ku='Kukulkan:BAAANQADCgcIBwAAAA==.Kuulan:BAAANQAECgEIAQAAAA==.',
La='Lanstin:BAAANQADCgEIAQAAAA==.',
Le='Leancuisine:BAAANQADCgYICQAAAA==.Leofull:BAAANQADCggICgAAAA==.Lettÿ:BAAANQADCgYICwAAAA==.',
Li='Lickemraw:BAAANQADCgQIBAAAAA==.Lilstorm:BAAANQADCgMIAwAAAA==.',
Lo='Loreix:BAAANQADCggIDAAAAA==.Loreous:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Lu='Luvinz:BAAANQADCgYICgAAAA==.Luxuria:BAAANQADCgYICwAAAA==.',
Ly='Lycanhunter:BAAANQADCgYIBgAAAA==.Lycansham:BAAANQADCgMIAwAAAA==.Lyse:BAEANQADCgYICgAAAA==.',
Ma='Maarc:BAAANQADCgYICQAAAA==.Madfurion:BAAANQADCgUIBwABNQADCgYIDgABAAAAAA==.Magebot:BAAANQAECgEIAQAAAA==.Maggotbag:BAAANQADCgQIBAAAAA==.Magikstik:BAAANQADCgYIBgAAAA==.Majestic:BAAANQAECgYICAAAAA==.Malvenue:BAAANQADCgMIBAAAAA==.Markdashaman:BAAANQADCgIIAgAAAA==.Mauwy:BAAANQAECgEIAQAAAA==.',
Mc='Mcbullseye:BAAANQADCgcICgAAAA==.',
Me='Megarah:BAAANQADCgUIBQAAAA==.Mepkaelpto:BAAANQADCgYIBgAAAA==.Meretrix:BAAANQADCgYIBgAAAA==.Mersadie:BAAANQADCgcIBwAAAA==.Metanya:BAAANQADCgQICAAAAA==.Mew:BAAANQADCgEIAQAAAA==.',
Mi='Miateh:BAAANQADCgYICwAAAA==.Mimicme:BAAANQAECgEIAQAAAA==.Mitchell:BAAANQADCgYIBgAAAA==.Miwah:BAAANQAECgEIAQAAAA==.Mizzheals:BAAANQAECgEIAQAAAA==.',
Mo='Mogarr:BAAANQADCgcICwAAAA==.Moocifer:BAAANQAECgIIAgAAAA==.Mooglewing:BAAANQADCgYICwAAAA==.Moomoobrncow:BAAANQADCggIDQAAAA==.Moorrigån:BAAANQADCgIIAgAAAA==.Mordicanta:BAAANQADCgcIDQAAAA==.Morgannon:BAAANQADCgUIBQAAAA==.Morphies:BAAANQADCgEIAQAAAA==.',
Mu='Muerr:BAAANQAECgEIAQAAAA==.Muggel:BAAANQADCgUIBwAAAA==.Mumraa:BAAANQADCgIIAgAAAA==.Mushroohead:BAAANQADCggIHAAAAA==.',
My='Myykiel:BAAANQADCgcICQAAAA==.',
Na='Naina:BAAANQADCggIDgAAAA==.Najaja:BAAANQADCgQIBAAAAA==.Narsum:BAAANQADCgYIBgAAAA==.Natacha:BAAANQADCgYICwAAAA==.Navadurga:BAAANQADCgEIAQAAAA==.',
Ne='Necro:BAAANQAECgQIBAAAAA==.Nedrina:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Ni='Nidom:BAAANQAECgIIAgAAAA==.Nighammer:BAAANQAECgEIAQAAAA==.Nirø:BAAANQADCgcIBwAAAA==.',
No='Nooki:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Noreye:BAAANQADCgUIBAAAAA==.Notgretuh:BAAANQAECgYIBwAAAA==.',
Ny='Nyrikah:BAAANQADCgQIBQAAAA==.',
Ob='Obidiah:BAAANQADCgcIDAAAAA==.',
Od='Oddearth:BAAANQAECgEIAQAAAA==.',
Om='Omegablivet:BAAANQABCgQIBgAAAA==.',
Pa='Palagem:BAAANQADCgYICwAAAA==.Palidingo:BAAANQADCgEIAQAAAA==.Palinyes:BAAANQADCgUIBQAAAA==.Pandabutz:BAAANQADCggIDQAAAA==.Panduh:BAAANQADCgYICwAAAA==.Papabill:BAAANQAECgEIAQAAAA==.Papaharny:BAAANQADCgcICAABNQAECgEIAQABAAAAAA==.Paragorn:BAAANQADCgcIDAAAAA==.Pattee:BAAANQADCgcIDQAAAA==.',
Pe='Pech:BAAANQAECgEIAgAAAA==.Pechay:BAAANQADCgIIAgABNQAECgEIAgABAAAAAA==.Peenidin:BAAANQAECgEIAQAAAA==.Pemerd:BAAANQAECgEIAQAAAA==.',
Ph='Phoze:BAAANQADCgYIBgAAAA==.Phyai:BAAANQADCgYICQAAAA==.',
Pl='Pliny:BAAANQAECgQIBAAAAA==.',
Pn='Pnutt:BAAANQADCgQIBAAAAA==.',
Po='Porphyriia:BAAANQADCggICAAAAA==.',
Pr='Priestglein:BAAANQADCgUIBQABNQADCggIDgABAAAAAA==.Promethyus:BAAANQADCgcIDQAAAA==.Promidan:BAAANQADCgQIBAABNQAECgYICwABAAAAAA==.Prymus:BAAANQADCggIDgAAAA==.Pryxi:BAAANQADCgcIDQAAAA==.',
Pu='Punkalicious:BAAANQABCgQIBAAAAA==.',
Py='Pythius:BAAANQADCggIDgAAAA==.',
Qu='Quetip:BAAANQADCgMIAwAAAA==.Quiksylver:BAAANQAECgEIAQAAAA==.',
Ra='Ratshot:BAAANQADCgQIBAABNQAECgYIDQABAAAAAA==.Rawty:BAAANQADCgMIBAAAAA==.',
Re='Red:BAAANQADCgcICgAAAA==.Relgul:BAAANQABCgEIAQAAAA==.Rellster:BAAANQAECgIIAgAAAA==.Rennyo:BAAANQADCgcIDQAAAA==.Resonance:BAAANQADCggICAAAAA==.Rexion:BAAANQADCggIDgAAAA==.',
Ri='Riggsy:BAAANQADCgUIBQABNQABCgQIBAABAAAAAA==.Riggzbuffs:BAAANQADCgYICwABNQABCgQIBAABAAAAAA==.Rivenp:BAAANQADCgYIDAAAAA==.',
Ro='Rocknroll:BAAANQAECgMIAwAAAA==.Rokbiter:BAAANQADCgYIBgAAAA==.Roll:BAAANQADCgYIBgABNQADCgcIDAABAAAAAA==.Rothound:BAAANQADCgYIBgAAAA==.Rozgrez:BAAANQADCgcIDQAAAA==.',
Ru='Runefflck:BAAANQABCgQIBgAAAA==.Russbus:BAAANQAECgYIBwAAAA==.',
Ry='Rynmorelle:BAAANQAECgEIAQAAAA==.',
['Ré']='Réven:BAAANQAECgEIAQAAAA==.',
Sa='Sane:BAAANQADCggIDQAAAA==.Saoiirse:BAAANQADCgYICQAAAA==.',
Se='Sevencharlie:BAAANQADCgYICQAAAA==.',
Sh='Shadowfate:BAAANQADCgQIBAAAAA==.Shamanyou:BAAANQADCgEIAQAAAA==.Shamiqua:BAAANQADCgYIDAAAAA==.Shentao:BAAANQADCggICgAAAA==.Shiroishi:BAAANQADCggIDgAAAA==.Shocklesner:BAAANQADCgcICwAAAA==.Shouganai:BAAANQADCgYICwAAAA==.',
Si='Sifu:BAAANQADCgYIBgAAAA==.Silverlight:BAAANQADCgYICQAAAA==.Simp:BAAANQADCgQIBAAAAA==.Sinaar:BAAANQADCgQIBAAAAA==.',
Sk='Skillcommand:BAAANQADCgUIBQAAAA==.Skyemage:BAAANQADCgQIBAAAAA==.',
Sl='Sloked:BAAANQADCggICAAAAA==.Slotz:BAAANQADCggIDgAAAA==.',
Sm='Smitepanda:BAAANQADCgcIBwAAAA==.',
Sn='Sneeze:BAAANQADCgUIBQAAAA==.',
Sp='Spicymeat:BAAANQAECgMIAwABNQAECgYICAABAAAAAA==.Sputty:BAAANQAECgQIBQAAAA==.',
St='Stesha:BAAANQAECgEIAQAAAA==.Stonedfrog:BAAANQADCgQIBQAAAA==.Stïtches:BAAANQADCgUICQAAAA==.Stönk:BAAANQADCggIDgAAAA==.',
Su='Sugarlumps:BAAANQADCgEIAQAAAA==.Superdaman:BAAANQADCgEIAQAAAA==.',
Sw='Swaggles:BAAANQADCggIDgAAAA==.',
Sy='Sygon:BAAANQADCgcIDQAAAA==.Sylm:BAAANQAECgQIBAABNQAECggIDgABAAAAAA==.Symbr:BAAANQADCgcICwAAAA==.',
Ta='Tacitus:BAAANQADCgYIBgAAAA==.Tairrad:BAAANQADCgQIBAABNQADCgcIDQABAAAAAA==.Takeru:BAAANQADCgcICwAAAA==.Talasmar:BAAANQADCgMIAwAAAA==.Taliessin:BAAANQADCgQIBQAAAA==.Talistian:BAAANQADCgIIAgAAAA==.Tarirn:BAAANQADCgUIBQAAAA==.',
Te='Tempestrasza:BAAANQADCgQIBAAAAA==.Teppe:BAAANQADCgcICgAAAA==.',
Th='Thajeebus:BAAANQAECgEIAQAAAA==.Thecapt:BAAANQAECgQIBAAAAA==.Theôdöræ:BAAANQAECgEIAQAAAA==.',
Ti='Tiaoma:BAAANQADCgYIBgAAAA==.Tinylock:BAAANQADCgQIBAAAAA==.',
To='Toletheus:BAAANQADCggIDgAAAA==.Tomin:BAAANQADCgIIAgAAAA==.Toreshii:BAAANQADCgQIBAAAAA==.',
Tr='Treeperson:BAAANQADCgYIBgAAAA==.Trickyric:BAAANQAECgEIAQAAAA==.',
Ts='Tsuyoimono:BAAANQADCgUICQABNQADCgYIDAABAAAAAA==.',
Tu='Turtleclap:BAAANQADCgUIBQAAAA==.',
Tw='Twistandgrip:BAAANQAECgIIAgAAAA==.',
Ur='Uratsukasama:BAAANQADCgYIBwAAAA==.Urza:BAAANQADCgQIBgAAAA==.',
Va='Vagiant:BAAANQAECgEIAQAAAA==.Vanya:BAAANQADCgcIDQAAAA==.Vasso:BAAANQADCgUIBQAAAA==.Vayln:BAAANQAECgUIBQAAAA==.',
Ve='Veinygamer:BAAANQAECgcIDQAAAA==.Veldian:BAAANQAECgEIAQAAAA==.Velveen:BAAANQADCgcIDQAAAA==.Vexahalia:BAAANQAECgQIBAAAAA==.',
Vi='Vilewyrm:BAEANQADCgcIDQAAAA==.Viridius:BAAANQADCgQIBAAAAA==.',
Vo='Voidmulan:BAEANQADCgUIBQAAAA==.',
Vr='Vraak:BAAANQADCgUIBgAAAA==.',
Wa='Wagguslight:BAAANQADCggIDgAAAA==.',
We='Werstshot:BAAANQADCgYICwAAAA==.',
Wh='Whateverdude:BAAANQADCggICAAAAA==.',
Wi='Wiickett:BAAANQAECgQIBQAAAA==.Willaá:BAAANQADCggIDgAAAA==.Wilson:BAAANQADCgcIDAAAAA==.',
Wr='Wrathhoof:BAAANQADCggIDgABNQAECgEIAQABAAAAAA==.',
Yo='Yorril:BAAANQADCgUIBQAAAA==.',
Yu='Yucca:BAAANQADCgcIDQAAAA==.Yukiteru:BAAANQADCgcIDAAAAA==.Yurito:BAAANQADCgYIBgAAAA==.',
Za='Zachie:BAAANQABCgQIBAAAAA==.Zakutin:BAAANQADCgcIDAAAAA==.Zappybains:BAAANQADCgcIDQAAAA==.Zarakii:BAAANQADCgUICQAAAA==.',
Ze='Zekken:BAAANQADCgMIAwAAAA==.Zelaira:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Zi='Zigzagga:BAAANQADCgQIBAAAAA==.',
Zo='Zoinks:BAAANQADCgEIAQAAAA==.',
Zy='Zylluz:BAAANQAECgEIAQAAAA==.',
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
