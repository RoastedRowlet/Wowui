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

local lookup = {'Unknown-Unknown','Mage-Arcane','DeathKnight-Unholy','Priest-Holy','DemonHunter-Devourer','Warrior-Arms',}
local provider = {region='US',realm='Kargath',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abracadabruh:BAAANQAECgEIAQAAAA==.Absynthia:BAAANQADCgcIDQAAAA==.',
Ac='Academe:BAAANQADCgYICQAAAA==.',
Ad='Adérai:BAAANQAECgYICAAAAA==.',
Ae='Aellopus:BAAANQAECgIIAgAAAA==.Aero:BAAANQAECgIIAgAAAA==.',
Ag='Agròm:BAAANQADCgQIBAABNQADCgcICwABAAAAAA==.',
Ak='Akata:BAAANQADCgQIBQAAAA==.Akku:BAAANQADCgYIBwAAAA==.',
Al='Alanwake:BAAANQAECgYICAAAAA==.Aldourolf:BAAANQABCgQIBAAAAA==.',
Am='Amiliane:BAAANQAECgEIAQAAAA==.Amoradine:BAAANQADCgcIDAAAAA==.Amz:BAAANQADCgcIDgAAAA==.',
An='Anadrien:BAAANQAECgIIAgAAAA==.Ancelagon:BAAANQADCgYIBwAAAA==.Andrae:BAAANQADCgUIDwAAAA==.Angrimia:BAAANQAECgIIAgAAAA==.Annussa:BAAANQADCggIEgAAAA==.',
Ar='Arboria:BAAANQAECgYIAgAAAA==.Ardbeg:BAAANQABCgYIBwAAAA==.Arduin:BAAANQAECgEIAQAAAA==.Aremethea:BAAANQADCgcIEgAAAA==.Aronk:BAAANQADCggIFgABNQAECgEIAQABAAAAAA==.Arore:BAAANQADCgMIBAABNQAECgEIAQABAAAAAA==.Aroreck:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
As='Asbjorn:BAAANQADCgYICgAAAA==.',
At='Attack:BAAANQADCgQIBAABNQAECgkJEgACAGcdAA==.',
Av='Avestara:BAAANQAECgIIAgAAAA==.',
Ay='Ayohec:BAAANQADCgQIBAAAAA==.',
Az='Azoril:BAAANQAECgUIBgAAAA==.Azùla:BAAANQADCggIEQAAAA==.',
['Aí']='Aídeen:BAAANQAECgQIBAAAAA==.',
Ba='Babs:BAAANQADCgEIAQAAAA==.Baelnorn:BAAANQAECgQIBQAAAA==.Barrex:BAAANQADCgIIAgAAAA==.Basken:BAAANQAECgEIAQAAAA==.Batôsai:BAAANQAECgEIAQAAAA==.',
Be='Beelz:BAAANQAECgEIAQAAAA==.Belaraariaae:BAAANQADCggICAABNQAECgcIDwABAAAAAA==.Benipal:BAAANQAECgcIEgAAAA==.Bernardboggs:BAAANQAECgMIAwAAAA==.',
Bh='Bheefknight:BAAANQAECgMIAwAAAA==.Bheeftotemz:BAAANQADCgUIBQAAAA==.',
Bi='Bierbro:BAAANQAECgQIBQAAAA==.Billiam:BAAANQADCggICAAAAA==.Billié:BAAANQAECgQIBgABNQAECgUIDAABAAAAAA==.',
Bl='Blumir:BAAANQAECgEIAQAAAA==.',
Bo='Bomgan:BAAANQAECgEIAQAAAA==.Bonchonn:BAAANQAECgcIDgAAAA==.Bonkula:BAAANQADCgcICwAAAA==.Bops:BAAANQADCggIDQAAAA==.Borque:BAAANQAECgIIAgAAAA==.Bosenmorimei:BAAANQADCgIIAgAAAA==.',
Br='Brae:BAAANQADCgQIBAAAAA==.Brazonk:BAAANQAECgEIAQAAAA==.Brewzco:BAAANQAECgQICAAAAA==.Briciferkong:BAABNQAECoEXAAIDAAkJ9yRHAQDKAwADAAkJ9yRHAQDKAwAAAA==.Brickedup:BAAANQAECgEIAQAAAA==.Brightblayde:BAAANQAECgIIAgAAAA==.',
Bu='Buanto:BAAANQADCgYIDwAAAA==.Bubblegumm:BAAANQADCgQIBAAAAA==.Bubbletea:BAAANQAECgEIAQABNQADCgQIBAABAAAAAA==.Butterball:BAAANQAECgYIBwAAAA==.',
Ca='Candlelock:BAAANQADCgUIBgAAAA==.Candlewic:BAAANQADCgcIEQAAAA==.Cathal:BAAANQABCgYICAAAAA==.Cattroll:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Ce='Celithila:BAAANQADCggIFAAAAA==.Celithvia:BAAANQAECgEIAQAAAA==.Cervantés:BAAANQAECgQIBgAAAA==.',
Ch='Chaosknight:BAAANQADCgcIEgAAAA==.Charginatyou:BAAANQADCggIDwABNQAECgQIDgABAAAAAA==.Charla:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Chelsea:BAAANQADCgIIAgAAAA==.Chise:BAAANQAECgQIBQAAAA==.Chob:BAAANQADCgcICwAAAA==.',
Cl='Clarry:BAAANQADCgYIDAAAAA==.Clyde:BAAANQAECgEIAQAAAA==.Clydk:BAAANQADCgcICAAAAA==.',
Co='Coachbeard:BAAANQAECgYICAAAAA==.Colzaratha:BAAANQAECgQIBgAAAA==.Corndog:BAAANQAECgYICgAAAA==.Cozzworth:BAAANQADCgEIAQAAAA==.',
Cu='Cudguzzler:BAAANQAECgIIAgAAAA==.Cursegoesmoo:BAAANQADCgEIAQAAAA==.Cursehoots:BAAANQAECgYICwAAAA==.',
Cy='Cyntheria:BAAANQAECgQIBQAAAA==.',
Da='Daddybeàr:BAAANQAECgcIEAAAAA==.Daendron:BAAANQAECgIIAgAAAA==.Darksaxon:BAAANQADCgcIDAAAAA==.Darorek:BAAANQAECgEIAQAAAA==.',
De='Deathnethal:BAAANQADCgYIBgAAAA==.Deathweaver:BAAANQAECgYICgAAAA==.Deeneye:BAAANQADCgUICgABNQADCgcICAABAAAAAA==.Dellgado:BAAANQABCgMIBQAAAA==.Deme:BAAANQADCggICAAAAA==.Demonica:BAAANQAECgIIAgAAAA==.Demonscythe:BAAANQADCgUICgAAAA==.Dendrax:BAAANQADCggIDgAAAA==.Dented:BAAANQABCgQIBAAAAA==.Deviance:BAAANQADCgcIDQAAAA==.Dezwar:BAAANQADCgEIAQABNQAECgkJFQACAFIhAA==.',
Di='Dissonance:BAAANQADCgQIBAAAAA==.',
Dj='Djanga:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Djdazzle:BAAANQADCgYIBwAAAA==.',
Do='Dorito:BAAANQAFFAEIAQAAAA==.',
Dr='Dragooned:BAAANQAECggIEwAAAA==.Drango:BAAANQAECgIIAgAAAA==.Draugdae:BAAANQAECgEIAQAAAA==.Draxtor:BAAANQADCgMIAwAAAA==.Drinksomuch:BAAANQAECgEIAQAAAA==.Drizzlin:BAAANQADCgYIBgAAAA==.Drleche:BAAANQADCgEIAQAAAA==.Drob:BAEANQADCggIFwAAAA==.Drocket:BAEANQAECgEIAQAAAA==.Drome:BAAANQADCgEIAQABNQADCggIFgABAAAAAA==.Drukhi:BAAANQAECgQIBQAAAA==.',
Du='Dudetotems:BAAANQAECgMIAwAAAA==.Dungrough:BAAANQADCgcIDQAAAA==.Durtkal:BAAANQAECgMIAwAAAA==.',
Dy='Dyonn:BAAANQADCgcIEgAAAA==.',
Ef='Efarel:BAAANQAECgQIBgAAAA==.',
Ei='Eilana:BAAANQAECgIIAgAAAA==.Eilària:BAAANQADCgMIAwAAAA==.',
El='Elsa:BAAANQAECgQIBQAAAA==.',
En='Eneco:BAAANQAECgYIBgAAAA==.Enserath:BAAANQADCgYICwAAAA==.',
Eu='Eurythmics:BAAANQAECgEIAQAAAA==.',
Ev='Evonahh:BAAANQADCgQIBAAAAA==.',
Ex='Exelion:BAAANQAECgQIBQAAAA==.',
Ez='Ezrack:BAAANQADCgIIAgAAAA==.',
Fa='Faaith:BAAANQADCgUIDQAAAA==.Fahooquazaad:BAAANQADCgYIDQAAAA==.Fancy:BAAANQAECgUIBgAAAA==.',
Fe='Feetlesmcdee:BAAANQAECgEIAQAAAA==.',
Fi='Fitzy:BAAANQAECgQICgAAAA==.',
Fl='Flowermound:BAAANQADCgcIEAAAAA==.',
Fo='Fourqto:BAAANQAECgEIAQAAAA==.Fox:BAABNQAECoEWAAIEAAkJzyBQBAA+AwAEAAkJzyBQBAA+AwAAAA==.',
Fr='Freya:BAAANQADCgUIBQAAAA==.',
Fu='Fujikujaku:BAAANQAECgEIAQAAAA==.Fulmetal:BAAANQAECgMIBAAAAA==.Funji:BAAANQAECgEIAQAAAA==.Funkalicious:BAAANQAECgQIBgAAAA==.',
['Fé']='Félo:BAAANQADCggIGQAAAA==.',
Ga='Gaila:BAAANQAECgUIDAAAAA==.Garathor:BAAANQABCgIIAwAAAA==.Garrosh:BAAANQABCgMIAwAAAA==.Garthoneeye:BAAANQADCgUICQAAAA==.Gazreyna:BAAANQAECgEIAQAAAA==.',
Ge='Genryusai:BAAANQADCgIIAgAAAA==.Genós:BAAANQAECgQIBQAAAA==.Gerardo:BAAANQADCgcIDAAAAA==.',
Gi='Gigarawr:BAAANQAECgEIAQABNQAECgYIBgABAAAAAA==.Ginnee:BAAANQAECgEIAQAAAA==.',
Gl='Glakattack:BAAANQAECgUICgAAAA==.Glein:BAAANQAECgMIAwAAAA==.Gleivoker:BAAANQADCggICAABNQAECgMIAwABAAAAAA==.',
Go='Gongfu:BAAANQADCgEIAQAAAA==.Gooeyquiver:BAAANQADCgMIBQAAAA==.',
Gr='Graestoke:BAAANQADCgYIDwABNQAECgcIDAABAAAAAA==.Greasermorty:BAAANQADCgMIAwAAAA==.Growls:BAAANQAECgIIAgAAAA==.Grundlegnome:BAAANQAECggIDQAAAA==.',
Gu='Gurri:BAAANQADCgcIEgAAAA==.',
['Gõ']='Gõldenchild:BAAANQADCgYIDgAAAA==.',
Ha='Habenero:BAAANQADCgUIDgAAAA==.Hairypitts:BAAANQAECgEIAQAAAA==.Happychaos:BAAANQADCgcICwAAAA==.Haraniantha:BAAANQAECgcIDwAAAA==.Hatean:BAAANQADCgcIDwAAAA==.Hathor:BAAANQAECgEIAQAAAA==.Hazzbek:BAAANQADCgcIDQAAAA==.',
He='Heiboss:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.Heibub:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.Heiranir:BAAANQAECgMIAwABNQAECgQIBQABAAAAAA==.Heiretic:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.',
Hi='Hikikomori:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.Hildegarde:BAAANQAECgMIAwAAAA==.Hinomiko:BAAANQADCgcIEwAAAA==.',
Ho='Holycowch:BAAANQADCgEIAQAAAA==.',
Hu='Huran:BAAANQAECgQIBQAAAA==.',
Hx='Hx:BAAANQADCgMIAwABNQADCggICAABAAAAAA==.',
Ia='Iatemydad:BAAANQAECgMIBAAAAA==.',
Ic='Icéehawt:BAEANQADCgcIDAABNQADCgUIBQABAAAAAA==.',
Ig='Ignignokt:BAEANQAECgUICQAAAA==.',
Im='Imagine:BAAANQAECgMIAwAAAA==.',
In='Inarush:BAAANQAECgQIBAAAAA==.',
Iw='Iwishiknew:BAAANQADCggIDAAAAA==.',
Iz='Iztras:BAAANQADCgEIAQAAAA==.',
Ja='Jabbtrak:BAAANQAECgMIAwAAAA==.Jacklowry:BAAANQAECgEIAQAAAA==.Jakiepoobear:BAAANQAECgQICAAAAA==.Jambie:BAAANQAECgIIAgAAAA==.',
Je='Jedery:BAAANQADCgcIEgAAAA==.',
Ji='Jivepepper:BAAANQADCgcIBwAAAA==.',
Jo='Joroldess:BAAANQAECgQIBQAAAA==.Joyo:BAAANQADCgUICQAAAA==.',
Ju='Juzam:BAAANQADCgIIAgAAAA==.',
Ka='Kahghär:BAAANQAECgQIBAABNQAFFAMIAwABAAAAAA==.Kahlly:BAAANQAECgEIAQAAAA==.Kahndumb:BAAANQAECgIIAgAAAA==.Kaida:BAAANQADCgQIBAAAAA==.Kaio:BAAANQAECgQIBAAAAA==.Kalahan:BAAANQADCgcICAAAAA==.Kardrion:BAAANQADCgMIAwAAAA==.Karigyn:BAAANQAECgIIAgAAAA==.Kaskaa:BAAANQADCgQIBAAAAA==.Katelina:BAAANQADCgcIBwAAAA==.Katren:BAAANQADCgMIAwAAAA==.Katrienne:BAAANQAECgIIAgAAAA==.Katrya:BAAANQABCgQIBAABNQAECgIIAgABAAAAAA==.Kaylid:BAAANQADCggIFAAAAA==.Kazzoth:BAAANQAECgQIBAAAAA==.',
Ke='Keiyo:BAAANQADCgUIBQAAAA==.Ketsuana:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.Ketsukusai:BAAANQADCgUIBQAAAA==.',
Ki='Kilen:BAAANQABCgQICAAAAA==.Kilimanjaro:BAAANQADCgcICQAAAA==.Killjôy:BAAANQADCgIIAgAAAA==.Kimjongboom:BAAANQAECggIEAAAAA==.',
Kl='Klax:BAAANQADCgcIDAAAAA==.Klondor:BAAANQAECgIIAgAAAA==.Klz:BAAANQADCgQIBQAAAA==.Klzx:BAAANQAECgEIAQAAAA==.',
Ko='Komo:BAAANQAECggIEwAAAA==.Konokusotare:BAAANQAECgEIAQAAAA==.Korbi:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Korbs:BAAANQADCggIFwAAAA==.Kortek:BAAANQADCgUIBQAAAA==.Korvold:BAAANQAECgQIBQAAAA==.',
Kr='Krak:BAAANQABCgYICAAAAA==.Kreckon:BAAANQADCgUIDQAAAA==.Kronn:BAAANQAECgQIBQAAAA==.',
Ks='Kschnell:BAAANQADCgQIBQABNQAECgkJEgACAGcdAA==.',
Ku='Kukulkan:BAAANQAECgQIBAAAAA==.Kuulan:BAAANQAECgQIBQAAAA==.',
Ky='Kythra:BAAANQAECgEIAQAAAA==.',
La='Lanstin:BAAANQADCgUIBgAAAA==.',
Le='Leafpool:BAAANQADCgYIBgAAAA==.Leancuisine:BAAANQADCgYIEQAAAA==.Leofull:BAAANQAECgEIAQAAAA==.Lettÿ:BAAANQADCgcIEgAAAA==.Lexapro:BAAANQADCgYIBgAAAA==.',
Li='Lickemraw:BAAANQADCgQIBAAAAA==.Lilstorm:BAAANQADCgMIAwAAAA==.Littlenewt:BAAANQADCgYIBgAAAA==.',
Lo='Loreix:BAAANQADCggIEwAAAA==.Loreous:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.',
Lu='Luther:BAAANQADCgQIBQABNQAECgMIAwABAAAAAA==.Luvinz:BAAANQADCgcIEQAAAA==.Luxuria:BAAANQADCggIEwAAAA==.',
Ly='Lycanhunter:BAAANQADCgcIDAAAAA==.Lycansham:BAAANQADCgMIAwAAAA==.Lyse:BAEANQADCgcIEQAAAA==.',
Ma='Maarc:BAAANQADCggIEQAAAA==.Machantu:BAAANQADCgYIBgAAAA==.Madfurion:BAAANQADCgcIDgAAAA==.Magebot:BAAANQAECgMIBAAAAA==.Maggotbag:BAAANQADCgYICgAAAA==.Magikstik:BAAANQADCgYIDAAAAA==.Mahgrim:BAAANQADCgMIAwAAAA==.Majestic:BAABNQAECoESAAICAAkJZx2+GgD2AgACAAkJZx2+GgD2AgAAAA==.Malvenue:BAAANQADCgMIBAAAAA==.Markdashaman:BAAANQADCgIIAgAAAA==.Mauwy:BAAANQAECgQIBQAAAA==.',
Mc='Mcbullseye:BAAANQAECgEIAQAAAA==.',
Me='Megarah:BAAANQADCgYICwAAAA==.Mepkaelpto:BAAANQADCgYIBgAAAA==.Meretrix:BAAANQADCgcIDQAAAA==.Mersadie:BAAANQAECgEIAQAAAA==.Metanya:BAAANQADCgcIDwAAAA==.Mew:BAAANQADCgcICAAAAA==.',
Mi='Miateh:BAAANQADCgcIEgAAAA==.Mimicme:BAAANQAECgQIBQAAAA==.Mirajanê:BAAANQADCgYIBgAAAA==.Mitchell:BAAANQADCggIDgAAAA==.Miwah:BAAANQAECgQIBQAAAA==.Mizzheals:BAAANQAECgMIBAAAAA==.',
Mo='Mogarr:BAAANQADCgcICwAAAA==.Moocifer:BAAANQAECgQIBgAAAA==.Mooglewing:BAAANQADCgcIDgAAAA==.Moomoobrncow:BAAANQAECgIIAgAAAA==.Mooriahdairy:BAAANQADCggICAAAAA==.Moorrigån:BAAANQADCgIIAgAAAA==.Mordicanta:BAAANQAECgEIAQAAAA==.Morgannon:BAAANQADCgUIBQAAAA==.Morphies:BAAANQADCgEIAQAAAA==.',
Mu='Muerr:BAAANQAECgMIBAAAAA==.Muggel:BAAANQADCgUIDAAAAA==.Mumraa:BAAANQADCgUIBwAAAA==.Mushroohead:BAAANQAECgEIAQAAAA==.',
My='Myykiel:BAAANQADCgcIDgAAAA==.',
Na='Naina:BAAANQAECgEIAQAAAA==.Najaja:BAAANQADCgQIBAAAAA==.Namii:BAAANQADCggICAAAAA==.Narsum:BAAANQADCgYIBgAAAA==.Natacha:BAAANQADCgYIEQAAAA==.Navadurga:BAAANQADCggICQAAAA==.',
Ne='Necro:BAAANQAECgYICgAAAA==.Nedrina:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.Netrath:BAAANQADCgEIAQAAAA==.',
Ni='Nidom:BAAANQAECgIIAgAAAA==.Nighammer:BAAANQAECgIIAgAAAA==.Nirø:BAAANQAECgEIAQAAAA==.',
No='Nooki:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.Noreye:BAAANQADCgUIBAAAAA==.Notgretuh:BAAANQAECgcIDQAAAA==.',
Ny='Nyrikah:BAAANQADCgQIBQAAAA==.',
Ob='Obidiah:BAAANQAECgMIAwAAAA==.',
Od='Oddearth:BAAANQAECgEIAQAAAA==.',
Om='Omegablivet:BAAANQADCgMIAwAAAA==.',
Pa='Palagem:BAAANQADCggIEwAAAA==.Palidingo:BAAANQADCgEIAQAAAA==.Palinyes:BAAANQAECgEIAQAAAA==.Pandabutz:BAAANQAECgIIAgAAAA==.Panduh:BAAANQADCggIEwAAAA==.Papabill:BAAANQAECgMIBwAAAA==.Paragorn:BAAANQAECgEIAQAAAA==.Pattee:BAAANQADCgcIEgAAAA==.',
Pe='Pech:BAAANQAECgEIAgABNQAECgYIBgABAAAAAA==.Pechay:BAAANQADCgIIAgABNQAECgYIBgABAAAAAA==.Peenidin:BAAANQAECgQIBQAAAA==.Pemerd:BAAANQAECgIIAwAAAA==.',
Ph='Phoze:BAAANQAECgEIAQAAAA==.Phyai:BAAANQAECgIIAgAAAA==.',
Pl='Pliny:BAAANQAECgcICwAAAA==.',
Pn='Pnutt:BAAANQADCgQIBAAAAA==.',
Po='Porphyriia:BAAANQADCggICAAAAA==.',
Pr='Priestglein:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Promethyus:BAAANQADCgcIDQAAAA==.Promidan:BAAANQAECgIIAgABNQADCggICAABAAAAAA==.Prymus:BAAANQAECgIIAgAAAA==.Pryxi:BAAANQAECgIIAgAAAA==.',
Pu='Punkalicious:BAAANQADCggICAAAAA==.',
Py='Pythius:BAAANQAECgIIAgAAAA==.',
['Pó']='Pótatò:BAAANQADCgMIAwAAAA==.',
Qu='Quetip:BAAANQADCgMIAwAAAA==.Quiksylver:BAAANQAECgMIBAAAAA==.',
Ra='Ratshot:BAAANQAECgQIBAABNQAECggIFwAFAIYZAA==.Rawty:BAAANQADCgMIBAAAAA==.',
Re='Red:BAAANQAECgIIAgAAAA==.Relgul:BAAANQADCgYICAAAAA==.Rellster:BAAANQAECgQIBgAAAA==.Rennyo:BAAANQAECgIIAgAAAA==.Resonance:BAAANQADCggIEAAAAA==.Rexion:BAAANQADCggIFgAAAA==.',
Ri='Riggsy:BAAANQADCggIDQABNQABCgQIBAABAAAAAA==.Riggzbuffs:BAAANQADCgYICwABNQABCgQIBAABAAAAAA==.Rivenp:BAAANQADCgYIDAAAAA==.',
Ro='Rocknroll:BAAANQAECgQIBwAAAA==.Rokbiter:BAAANQAECgIIAgAAAA==.Roll:BAAANQADCgYICgABNQAECgIIAgABAAAAAA==.Rothound:BAAANQADCgYIBgAAAA==.Rozgrez:BAAANQAECgEIAQAAAA==.',
Ru='Runefflck:BAAANQABCgQIBgAAAA==.Russbus:BAAANQAECgcIDgAAAA==.',
Ry='Rynari:BAAANQADCgUIBQABNQAECgUIBgABAAAAAA==.Rynmorelle:BAAANQAECgUIBgAAAA==.',
['Ré']='Réven:BAAANQAECgQIBQAAAA==.',
Sa='Sakura:BAAANQADCgEIAQAAAA==.Sane:BAAANQAECgEIAQAAAA==.Saoiirse:BAAANQADCgYICQAAAA==.',
Se='Seriux:BAAANQADCgUIBQAAAA==.Sevencharlie:BAAANQADCgYIEQAAAA==.',
Sh='Shadowfate:BAAANQADCgQIBAAAAA==.Shamanyou:BAAANQADCgEIAQAAAA==.Shamiqua:BAAANQADCgYIDAAAAA==.Shentao:BAAANQAECgQIBAAAAA==.Shiroishi:BAAANQADCggIFgAAAA==.Shocklesner:BAAANQADCggIEwAAAA==.Shomade:BAAANQADCgMIAwAAAA==.Shouganai:BAAANQADCgcIDgAAAA==.',
Si='Sifu:BAAANQADCgYIBgAAAA==.Silverlight:BAAANQAECgIIAwAAAA==.Simp:BAAANQADCgQIBAAAAA==.Sinaar:BAAANQADCgQIBAAAAA==.Sindena:BAAANQAECgQIBAAAAA==.',
Sk='Skillcommand:BAAANQADCgUIBQAAAA==.Skyemage:BAAANQADCggIDAAAAA==.',
Sl='Sloked:BAAANQAECgMIAwAAAA==.Slokes:BAAANQADCgIIAgAAAA==.Slotz:BAAANQAECgIIAgAAAA==.',
Sm='Smitepanda:BAAANQADCgcICAAAAA==.',
Sn='Sneeze:BAAANQADCgYIBgAAAA==.',
Sp='Spark:BAAANQAECgEIAQAAAA==.Spicymeat:BAAANQAECgQIBwABNQAECgkJEgACAGcdAA==.Sputty:BAAANQAECgcIDAAAAA==.',
St='Stesha:BAAANQAECgEIAQAAAA==.Stonedfrog:BAAANQADCgQIBQAAAA==.Stïtches:BAAANQADCggIEQAAAA==.Stönk:BAAANQAECgEIAQAAAA==.',
Su='Sugarlumps:BAAANQADCgEIAQAAAA==.Superdaman:BAAANQADCgEIAQAAAA==.',
Sw='Swaggles:BAAANQAECgEIAQAAAA==.',
Sy='Sygon:BAAANQAECgEIAQAAAA==.Sylm:BAAANQAECgQIBAAAAA==.Symbr:BAAANQAECgEIAQAAAA==.',
Ta='Tacitus:BAAANQAECgEIAQAAAA==.Tairrad:BAAANQADCgQIBAABNQADCggIDwABAAAAAA==.Takeru:BAAANQAECgEIAQAAAA==.Talasmar:BAAANQADCgMIAwAAAA==.Taliessin:BAAANQADCgQIBQAAAA==.Talistian:BAAANQADCgIIAgAAAA==.Tarirn:BAAANQADCgYICwAAAA==.Tauntsinpvp:BAAANQADCgYIBgAAAA==.Taylia:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
Te='Telinda:BAAANQABCgIIAgAAAA==.Tempestrasza:BAAANQADCgQIBAAAAA==.Teppe:BAAANQADCggIEgAAAA==.',
Th='Thajeebus:BAAANQAECgQIBQAAAA==.Thecapt:BAAANQAECgYICgAAAA==.Theôdöræ:BAAANQAECgEIAQAAAA==.',
Ti='Tiaoma:BAAANQADCggIDgAAAA==.Tinylock:BAAANQADCgUICQAAAA==.Tinymich:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.',
Tj='Tjhookèr:BAAANQADCgEIAQAAAA==.',
To='Toletheus:BAAANQAECgMIAwAAAA==.Tomin:BAAANQADCgIIAgAAAA==.Toreshii:BAAANQADCgUICQAAAA==.',
Tr='Trashkantz:BAAANQAECgQIBAABNQAECgkJGQACAP8iAA==.Treeperson:BAAANQAECgEIAQAAAA==.Trickyric:BAAANQAECgQIBQAAAA==.',
Ts='Tsuyoimono:BAAANQADCgcIEAABNQADCgcIEwABAAAAAA==.',
Tu='Turtleclap:BAAANQADCgUIBQAAAA==.',
Tw='Twistandgrip:BAAANQAECgUIBwAAAA==.',
Ty='Tyinthor:BAAANQADCgYIBgAAAA==.',
Ur='Uratsukasama:BAAANQADCgcIDgAAAA==.Urza:BAAANQADCgQIBgAAAA==.',
Va='Vagiant:BAAANQAECgUIBgAAAA==.Vanya:BAAANQADCgcIEgAAAA==.Vasso:BAAANQADCgYICwAAAA==.Vayln:BAAANQAECggIDAAAAA==.',
Ve='Veildreya:BAAANQABCgQIBAAAAA==.Veinygamer:BAABNQAECoEWAAIGAAgJxRzJHQCXAgAGAAgJxRzJHQCXAgAAAA==.Veldian:BAAANQAECgQIBQAAAA==.Velveen:BAAANQAECgIIAgAAAA==.Vexahalia:BAAANQAECgYIBAAAAA==.',
Vi='Vilewyrm:BAEANQADCgcIEgAAAA==.Viridius:BAAANQADCgUICAAAAA==.',
Vo='Voidmulan:BAEANQADCgUIBQAAAA==.',
Vr='Vraak:BAAANQADCgUIBgAAAA==.',
Wa='Wagguslight:BAAANQADCggIFQAAAA==.',
We='Werstshot:BAAANQADCggIEwAAAA==.',
Wh='Whateverdude:BAAANQAECgEIAQAAAA==.',
Wi='Wicketlock:BAAANQADCgcIBwAAAA==.Wiickett:BAAANQAECgcIDAAAAA==.Willaá:BAAANQAECgQIBAAAAA==.Wilson:BAAANQAECgMIAwAAAA==.Wizzpeaver:BAAANQADCgcIBwAAAA==.',
Wr='Wrathhoof:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.',
Xy='Xylias:BAAANQADCggICAAAAA==.',
['Xá']='Xánada:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Yo='Yorril:BAAANQADCgUIBQAAAA==.',
Yu='Yucca:BAAANQAECgMIAwAAAA==.Yukiteru:BAAANQAECgEIAQAAAA==.Yurito:BAAANQADCgYIBgAAAA==.',
Za='Zachie:BAAANQABCgYIBgAAAA==.Zakutin:BAAANQADCgcIDAAAAA==.Zappybains:BAAANQAECgEIAQAAAA==.Zarakii:BAAANQADCgcIEAAAAA==.',
Ze='Zekken:BAAANQADCgMIAwAAAA==.Zelaira:BAAANQADCgMIAwABNQAECgUIBgABAAAAAA==.',
Zi='Zigzagga:BAAANQADCgQIBAAAAA==.',
Zo='Zoinks:BAAANQADCgEIAQAAAA==.',
Zu='Zupaz:BAAANQADCgQIBAAAAA==.',
Zy='Zylluz:BAAANQAECgQIBQAAAA==.',
['Äs']='Ästen:BAAANQADCgYIBgAAAA==.',
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
