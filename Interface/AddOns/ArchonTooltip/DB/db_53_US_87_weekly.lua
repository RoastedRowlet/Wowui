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
local provider = {region='US',realm='Elune',name='US',type='weekly',zone=53,date='2026-09-01',data={Ai='Aib:BAAANQADCgYIDAAAAA==.',
Ak='Akashah:BAAANQAECgQIBQAAAA==.Akeno:BAAANQAECgEIAQAAAA==.',
Al='Alarick:BAAANQADCgYICgAAAA==.Alatha:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Alathasedai:BAAANQAECgIIAgAAAA==.Alathea:BAAANQAECgMIAwAAAA==.Aledis:BAAANQAECgQIBQAAAA==.Allanøn:BAAANQADCgUICgAAAA==.',
Am='Amalith:BAAANQADCgUIBwAAAA==.Amirial:BAAANQADCgQIBAAAAA==.Amowrath:BAAANQAECgIIAgAAAA==.Amyasia:BAAANQAECgIIAwAAAA==.',
An='Anghúro:BAAANQADCgYICQAAAA==.Angélica:BAAANQAECgUIBwAAAA==.Animethighs:BAAANQADCgIIAgAAAA==.',
Aq='Aquaskies:BAAANQAECgMIAwAAAA==.',
Ar='Arawynn:BAAANQADCgYIBgAAAA==.Archnessa:BAAANQADCggIEAAAAA==.Arissa:BAAANQADCgQIBAAAAA==.Arknight:BAAANQAECgEIAQAAAA==.',
As='Astreae:BAAANQAECgEIAQAAAA==.',
At='Atamus:BAAANQADCggIBgAAAA==.',
Av='Avi:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.',
Ay='Aya:BAAANQAECgEIAQAAAA==.Ayekillu:BAAANQADCggICwAAAA==.Ayiasofia:BAAANQAECgQIBAAAAA==.Ayla:BAAANQAECgIIAgAAAA==.Aylan:BAAANQADCggIDgAAAA==.',
Az='Azapal:BAAANQAECgIIAgAAAA==.',
Ba='Badger:BAAANQAECgIIAgAAAA==.Balloon:BAAANQADCgYICgAAAA==.Barathiel:BAAANQAECgcIDQAAAA==.Barlow:BAAANQADCgYIDAAAAA==.Baryll:BAAANQADCggIDgAAAA==.Batasu:BAAANQAECgMIAwAAAA==.Baulde:BAAANQAECgIIAgAAAA==.',
Bi='Biefcake:BAAANQAECgQIBAAAAA==.Bigmoo:BAAANQAECgYICAAAAA==.',
Bk='Bk:BAAANQAECgEIAQAAAA==.',
Bl='Blackparade:BAAANQADCgIIAgAAAA==.Blaydun:BAAANQADCgIIAgAAAA==.Blewboar:BAAANQAECgUIBQAAAA==.Bllass:BAAANQADCgMIAwAAAA==.Blueberrie:BAAANQAECgIIAgAAAA==.',
Bo='Boiledfrogz:BAAANQAECgIIAgAAAA==.Boned:BAAANQAECgIIAwAAAA==.Boopboops:BAAANQADCgYIBgAAAA==.',
Br='Bravehearthx:BAAANQADCgcIBwAAAA==.Bringerdk:BAAANQAFFAEIAQAAAA==.Bronco:BAAANQAECgEIAQAAAA==.Brünhïnnä:BAAANQADCgEIAQAAAA==.',
Bu='Bubblntendre:BAAANQAECgQIBQAAAA==.',
Ca='Caféconron:BAAANQADCgIIAgAAAA==.Caitsidhe:BAAANQAECgEIAQAAAA==.Cannute:BAAANQAECgIIAgAAAA==.Canuckdruid:BAAANQADCgMIAwAAAA==.Canuckranger:BAAANQADCgMIBAAAAA==.Captnubcakes:BAAANQADCggIDgAAAA==.Carebear:BAAANQAECgUIBwAAAA==.Castallia:BAAANQAECgIIAgAAAA==.Catrathena:BAAANQADCgQIBAAAAA==.',
Ch='Chaelis:BAAANQAECgQIBAAAAA==.Chalado:BAAANQADCgMIBAAAAA==.Chamanita:BAAANQADCggIDgAAAA==.Charizzard:BAAANQABCgEIAQAAAA==.Chilléd:BAAANQAECgYIBgAAAA==.Chisato:BAAANQADCggICAAAAA==.',
Ci='Cisticola:BAAANQAECgEIAQAAAA==.',
Cl='Clair:BAAANQAECgUICAAAAA==.Clova:BAAANQAECgMIAwAAAA==.',
Co='Combusty:BAAANQADCgEIAQAAAA==.Cornholyoh:BAAANQAECgcIDgAAAA==.Counsel:BAAANQADCggICgAAAA==.',
Cr='Cremefraiche:BAAANQAECgEIAQAAAA==.Crillex:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Critkiller:BAAANQADCgYIDAAAAA==.Crulzilla:BAAANQADCgYICwAAAA==.',
Cu='Cuero:BAAANQADCgQIBAAAAA==.Cupcakemeow:BAAANQAECgUIBgAAAA==.Curas:BAAANQADCgUICAAAAA==.Curzøn:BAAANQAECgUIDwAAAA==.',
Cw='Cw:BAAANQAECgQIBAAAAA==.Cwd:BAAANQADCgEIAQAAAA==.Cwds:BAAANQADCgcIDAABNQADCgEIAQABAAAAAA==.',
Da='Dabubblez:BAAANQADCgEIAQAAAA==.Daedengerek:BAAANQAECgQIBQAAAA==.Daggers:BAAANQADCgQIBAAAAA==.Daigz:BAAANQADCgQIBAAAAA==.Danerrin:BAAANQAECgYICgAAAA==.Dangersaur:BAAANQADCggIDQAAAA==.Danigos:BAAANQAFFAUIBgAAAQ==.Daryss:BAAANQADCgMIAwAAAA==.Daspirn:BAAANQADCgQIBAAAAA==.',
De='Deathadder:BAAANQAECgIIAgAAAA==.Deller:BAAANQADCgEIAQAAAA==.Demiphant:BAAANQAECgEIAQAAAA==.',
Di='Diesalot:BAAANQADCgcIDQAAAA==.Divinedragon:BAAANQADCgcIDAAAAA==.',
Dr='Dracthar:BAAANQADCgYICAAAAA==.Draczeal:BAAANQADCgYICgAAAA==.Dragonlee:BAAANQADCgEIAQAAAA==.Dragovade:BAAANQAECgEIAQAAAA==.Dreadlocke:BAAANQADCgcIDAAAAA==.Dreidels:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Drunkciggie:BAAANQADCgUIBQAAAA==.Drunky:BAAANQADCgYICgAAAA==.Drysua:BAAANQAECgQIBQAAAA==.',
Du='Duffageddon:BAAANQADCgcIBwAAAA==.Duskmender:BAAANQADCggICAABNQADCggIDAABAAAAAA==.Duzick:BAAANQADCgMIAwAAAA==.',
Dz='Dzmage:BAAANQADCgQICAAAAA==.Dzwarlock:BAAANQADCggIFQAAAA==.',
['Dë']='Dëëds:BAAANQADCgIIAwAAAA==.',
Ec='Ecklyn:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Eg='Egino:BAAANQADCgMIAwAAAA==.',
El='Elarisiel:BAAANQADCggICAAAAA==.Elaynne:BAAANQAECgQIBQAAAA==.Eldrith:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Eledis:BAAANQADCgcICwAAAA==.Elemender:BAAANQADCggIDAAAAA==.Elieth:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Eliteelf:BAAANQAECgEIAQAAAA==.Ellmer:BAAANQAECgQIBQAAAA==.Elnir:BAAANQADCgUIBQAAAA==.Elopeppe:BAAANQADCgYICgAAAA==.Elorro:BAAANQAECgEIAQABNQAECgcIDgABAAAAAA==.Eltaizari:BAAANQADCgcICwAAAA==.Elthiør:BAAANQAECgIIAwAAAA==.Elunedorei:BAAANQADCgQIBAAAAA==.Elwesingollo:BAAANQADCgEIAQAAAA==.',
En='Enilia:BAAANQAECgQIBAAAAA==.Enrgizernelf:BAAANQADCgYIDAAAAA==.',
Er='Erathena:BAAANQADCgYIBgAAAA==.Eriya:BAAANQADCggIDgAAAA==.',
Es='Esmeray:BAAANQADCgIIAgABNQADCggIDAABAAAAAA==.Estideeslol:BAAANQADCgYIDAAAAA==.',
Ey='Eyllis:BAAANQADCggICAAAAA==.',
Ez='Ezareth:BAAANQADCgUIBQAAAA==.',
Fa='Faded:BAAANQADCgYIBgAAAA==.Faedark:BAAANQADCgMIAgAAAA==.Farastraza:BAAANQABCgIIAgAAAA==.',
Fe='Feralscar:BAAANQADCgQIBAAAAA==.Ferangdh:BAAANQAECgIIAwAAAA==.Fevion:BAAANQADCgYICgAAAA==.Fevius:BAAANQADCgUIBQABNQADCgYICgABAAAAAA==.',
Fh='Fhantomgrave:BAAANQADCgYICgAAAA==.',
Fi='Finduilas:BAAANQAECgQIBQAAAA==.Firepower:BAAANQAECgEIAQAAAA==.Firepriest:BAAANQAECgEIAQAAAA==.Firesdruid:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Fl='Flappyjacks:BAAANQADCgYICgAAAA==.Flappystraza:BAAANQADCgIIAgAAAA==.Flickka:BAAANQADCgYICgAAAA==.',
Fo='Fourteen:BAAANQAECgMIAwAAAA==.Fourus:BAAANQADCggIBQAAAA==.',
Fr='Freakaleake:BAAANQADCgYIDAAAAA==.Freeport:BAAANQAECgcICgAAAA==.Freezerburn:BAAANQADCgUIBgABNQADCgcIDQABAAAAAA==.',
Fu='Funnymuffin:BAAANQAECgIIAgAAAA==.Furyia:BAAANQADCgcIDQAAAA==.Fuzzleprime:BAAANQAECgEIAQAAAA==.Fuzzy:BAAANQADCgUIBQAAAA==.',
Ga='Gaebora:BAAANQADCgUICAAAAA==.Gahmull:BAAANQADCgYICQAAAA==.Galleae:BAAANQAECgEIAQAAAA==.Garmart:BAAANQAECgQIBAAAAA==.Gauza:BAAANQADCgYICgAAAA==.',
Gh='Ghouldann:BAAANQAECgEIAQAAAA==.',
Gi='Gionathir:BAAANQADCggICQAAAA==.',
Gl='Glagglag:BAAANQAECgIIAgAAAA==.',
Go='Goldeen:BAAANQAECgEIAQAAAA==.Gorothraex:BAAANQADCgYIDAAAAA==.',
Gr='Graxion:BAAANQAECgIIAgAAAA==.Greggiiee:BAAANQADCgQIBAAAAA==.',
Gu='Guacamelee:BAAANQADCgYICwAAAA==.',
Gw='Gwuak:BAAANQADCgQIBQAAAA==.Gwynorra:BAAANQADCgYIDAAAAA==.',
Ha='Haralda:BAAANQAECgEIAQAAAA==.Harshblue:BAAANQAECgQIBQAAAA==.Hatt:BAAANQADCggIDgAAAA==.Hatts:BAAANQADCgUICQAAAA==.',
He='Healeydan:BAAANQAECgYICgAAAA==.Heddh:BAAANQADCggIEAABNQAECgIIAgABAAAAAA==.Heddruid:BAAANQAECgIIAgAAAA==.Heiligfeuer:BAAANQADCgYICAAAAA==.Hentaya:BAAANQADCgMIAwABNQABCgIIAgABAAAAAA==.Heyzuse:BAAANQADCgYICAAAAA==.',
Hi='Hippay:BAAANQADCgYIDAAAAA==.',
Ho='Holynihalus:BAAANQAECgcICwAAAA==.Holypowerr:BAAANQAECgEIAQABNQAECgYIBwABAAAAAA==.Holyspoons:BAAANQAECgYIBgAAAA==.Homar:BAAANQADCgYIDAAAAA==.Hoopa:BAAANQAFFAIIAgAAAA==.Houndwar:BAAANQADCgYIBgAAAA==.',
Hu='Huggs:BAAANQAECgQIBAAAAA==.Hunterama:BAAANQADCgUIBQAAAA==.Huntli:BAAANQADCggIDgAAAA==.Huntrix:BAAANQADCgcICwAAAA==.Huricaine:BAAANQADCgUIBQAAAA==.',
['Hé']='Hécate:BAAANQAECgMIAwAAAA==.',
Ic='Icecreamcake:BAAANQAFFAEIAQAAAA==.Icyy:BAAANQADCgYICwAAAA==.',
Id='Idontpaint:BAAANQADCgUIBQABNQABCgQIBAABAAAAAA==.',
Io='Ioana:BAAANQABCgIIAgAAAA==.',
Ip='Iphei:BAAANQADCggIDwAAAA==.',
Ir='Irulanni:BAAANQAECgIIAgAAAA==.',
Is='Ishanaxade:BAAANQAECgIIAgAAAA==.',
Iv='Iva:BAAANQAECgMIAwAAAA==.',
Iz='Izzie:BAAANQADCgcIBwAAAA==.',
Ja='Jagershaii:BAAANQADCgYIBgAAAA==.Jaketm:BAAANQADCgQIBAAAAA==.Jalaven:BAAANQADCgYICgAAAA==.Jas:BAAANQADCggIDQAAAA==.',
Je='Jecka:BAAANQADCgIIAgAAAA==.Jentle:BAAANQAECgQIBAAAAA==.Jessicka:BAAANQADCgYICAAAAA==.Jesûs:BAAANQADCgUIBQAAAA==.',
Ji='Jibbywibby:BAAANQADCgIIBAABNQAECgQICQABAAAAAA==.Jibreel:BAAANQADCggIDgAAAA==.Jinyla:BAAANQADCgQIBQAAAA==.Jiynila:BAAANQADCgYICwAAAA==.',
Jo='Johey:BAAANQAECgIIAgAAAA==.',
Ju='Juvenate:BAAANQAECgIIAgAAAA==.Juyani:BAAANQADCgYIEAAAAA==.',
Ka='Kailyn:BAAANQADCgIIAgAAAA==.Kaiyah:BAAANQADCgUIBwAAAA==.Kanab:BAAANQADCgYIBgABNQADCggIEAABAAAAAA==.Kayllea:BAAANQADCgYICwABNQADCgYIEAABAAAAAA==.Kaytara:BAAANQAECgIIAgAAAA==.',
Ke='Keharn:BAAANQADCgQIBQAAAA==.Kellen:BAAANQAECgcIDgAAAA==.Keloros:BAAANQADCgYICwAAAA==.Kenós:BAAANQAECgEIAQAAAA==.Kettock:BAAANQADCgUICQAAAA==.',
Ki='Kierk:BAAANQADCgUIBAAAAA==.Kilj:BAAANQAECgEIAQAAAA==.Kinuran:BAAANQAECgIIAgAAAA==.Kitherry:BAAANQADCggIDgAAAA==.',
Kn='Knifeprty:BAAANQAECgEIAQAAAA==.',
Ko='Kowdrak:BAAANQADCgcIBwAAAA==.',
Kr='Kreapen:BAAANQADCgYIDAAAAA==.Krisdk:BAAANQAECgcIDQAAAA==.Krisevoker:BAAANQADCgcIBwABNQAECgcIDQABAAAAAA==.',
Kt='Ktosh:BAAANQADCgQIBAAAAA==.',
Ku='Kurenäi:BAAANQADCggIDwAAAA==.',
Kw='Kwerin:BAAANQADCgYICgAAAA==.',
['Kí']='Kírî:BAAANQAECgcIDQAAAA==.',
La='Lacus:BAAANQAECgIIAgAAAA==.Larat:BAAANQADCgMIAwAAAA==.Layara:BAAANQADCgQIBAAAAA==.Layil:BAAANQADCgYIBgAAAA==.',
Le='Legolamb:BAAANQADCgcIBwAAAA==.Leviasaint:BAAANQAECgQIBQAAAA==.',
Lh='Lhadnire:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.',
Li='Lifeinsuranc:BAAANQADCgMIBAAAAA==.Lightstim:BAAANQADCgIIAgAAAA==.Lilito:BAAANQADCgYIBgAAAA==.Limewire:BAAANQAECgEIAQAAAA==.',
Lo='Lodtuspuch:BAAANQABCgEIAQAAAA==.Lofie:BAAANQAECgEIAQAAAA==.Lonesnipa:BAAANQADCgMIAwAAAA==.Looseyjoosey:BAAANQAECgEIAQAAAA==.Louiswu:BAAANQADCgYICwAAAA==.',
Lu='Luciferias:BAAANQAECgIIAwAAAA==.Luckyzounds:BAAANQABCgEIAQAAAA==.Lunariya:BAAANQADCgYICwAAAA==.',
Ly='Lyz:BAAANQADCgQIBAAAAA==.',
Ma='Madreezov:BAAANQADCgQIBgAAAA==.Madreezus:BAAANQAECgQIBAAAAA==.Mangodemon:BAAANQAECgYICgAAAA==.Mangopally:BAAANQAECgEIAgABNQAECgYICgABAAAAAA==.Mantheon:BAAANQADCgYIBgAAAA==.Marvel:BAAANQAECgMIAwAAAA==.Maybedos:BAAANQADCgYIBgAAAA==.Mayuki:BAAANQAECgUICQAAAA==.',
Me='Melmard:BAAANQABCgMIBAAAAA==.',
Mi='Miquella:BAAANQADCggICAABNQAECgMIAwABAAAAAA==.Mirrari:BAAANQADCgYICgAAAA==.Misschill:BAAANQADCgMIAwAAAA==.',
Mo='Mogin:BAAANQAECgYIBwAAAA==.Molten:BAAANQADCgYICgAAAA==.Morganite:BAAANQADCgMIAwAAAA==.',
Mu='Muehpera:BAAANQADCgYIBgAAAA==.',
My='Myrabeth:BAAANQADCgMIAwAAAA==.',
Na='Nadion:BAAANQADCgQIBwAAAA==.Naldon:BAAANQADCgMIAwAAAA==.Naraine:BAAANQADCgYICAAAAA==.',
Ne='Nefka:BAAANQADCgYIBgAAAA==.Nefkhet:BAAANQADCgMIAwAAAA==.Nephtyys:BAAANQAECgEIAQAAAA==.Nerfbat:BAAANQADCgYICgAAAA==.Nes:BAAANQADCgUIBQAAAA==.',
Ni='Nightgecko:BAAANQAECgIIAgAAAA==.Nineteen:BAAANQAFFAEIAQABNQAECgMIAwABAAAAAA==.Niávy:BAAANQADCgcIDAAAAA==.',
No='Noedos:BAAANQADCgIIAgAAAA==.Nofoxgivn:BAAANQAECgEIAQAAAA==.Nogdem:BAAANQADCggIDgAAAA==.Novaprime:BAAANQADCgYICgAAAA==.',
Ob='Obeevoker:BAAANQADCggIDgAAAA==.',
Oc='Ocala:BAAANQADCgMIAwAAAA==.',
Og='Ogryn:BAAANQADCgMIAwAAAA==.',
Ot='Otosan:BAAANQAECgQIBgAAAA==.',
Pa='Palshi:BAAANQADCgMIAwAAAA==.Pandariock:BAAANQADCgcIDAAAAA==.Parfait:BAAANQADCgYIBgAAAA==.Pawsatyou:BAAANQADCggIDwAAAA==.',
Pe='Peachiekeen:BAAANQADCgUIBwAAAA==.Peekãboo:BAAANQAECgcIDQAAAA==.Peewheewoo:BAAANQADCgMIAwAAAA==.Pelzy:BAAANQAECgMIAwAAAA==.Pepae:BAAANQAECgQIBQAAAA==.',
Ph='Pholia:BAAANQADCgcIDQAAAA==.',
Pi='Pieni:BAAANQADCgQIBAAAAA==.Pinkrose:BAAANQADCgYICgAAAA==.Pizza:BAAANQADCgcIBwAAAA==.',
Pl='Platomatrixx:BAAANQADCgYICAAAAA==.',
Po='Poony:BAAANQAECgUIBwABNQAECgcIDgABAAAAAA==.',
Pr='Proximus:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
Ps='Psyop:BAAANQAECgEIAQAAAA==.',
Pu='Punnyname:BAAANQAECgEIAQAAAA==.Purrsian:BAAANQADCgYIBgAAAA==.',
Qb='Qberks:BAAANQAECgIIAgAAAA==.',
Qu='Quaddh:BAAANQADCgQIBAAAAA==.Quincee:BAAANQADCgIIAgAAAA==.',
Ra='Raenin:BAAANQADCgcICQAAAA==.Ragingdraem:BAAANQAECgQIBQAAAA==.Raidei:BAAANQADCgcIDwAAAA==.Rainoffur:BAAANQADCgcIDQAAAA==.Rakeripwait:BAAANQADCgUIBQAAAA==.Ratatosk:BAAANQADCgcIDAAAAA==.Rathan:BAAANQAECgEIAQAAAA==.Ravenanarchy:BAAANQAECgIIAgAAAA==.',
Re='Redpawedfox:BAAANQAECgEIAQAAAA==.Rekviem:BAAANQAECgEIAgAAAQ==.Revie:BAAANQADCgQIBAABNQAECgcICgABAAAAAA==.',
Rh='Rhavaniel:BAAANQADCgYIBgAAAA==.',
Ro='Roderika:BAAANQADCgYICAAAAA==.Royalnewb:BAAANQAECgYIDAAAAA==.Royston:BAAANQAECgEIAQAAAA==.',
Ru='Rucereal:BAAANQADCgIIAgAAAA==.Rufous:BAAANQADCggIDwAAAA==.',
Rw='Rwaga:BAAANQADCgMIBAAAAA==.',
Ry='Rynsidious:BAAANQAECgQIBQAAAA==.',
['Rã']='Rãin:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.',
['Rì']='Rìkú:BAAANQADCgUIBQAAAA==.',
Sa='Sabelle:BAAANQADCgYICgAAAA==.Sableanne:BAAANQABCgQIBQAAAA==.Sabîne:BAAANQAECgIIAgAAAA==.Saeton:BAAANQAECgIIAgAAAA==.Sagar:BAAANQADCgYIBwAAAA==.Sahlaris:BAAANQADCggIDgAAAA==.Salno:BAAANQADCgMIAwAAAA==.Samsonite:BAAANQAECgUIBwAAAA==.Sanji:BAAANQADCgIIAgAAAA==.Sariths:BAAANQABCgQIBgAAAA==.',
Sc='Scrubpal:BAAANQADCgEIAQAAAA==.',
Se='Sekhet:BAAANQAECgEIAQAAAA==.Sekhmet:BAAANQADCgIIAgAAAA==.Sekstrasza:BAAANQADCgMIAwAAAA==.Sentineel:BAAANQAECgUIBgABNQAECgEIAQABAAAAAA==.Sersilkyhair:BAAANQAECgEIAQAAAA==.',
Sh='Shamanoid:BAAANQADCgYICwABNQADCgcIBwABAAAAAA==.Shasta:BAAANQAECgEIAQAAAA==.Shozwar:BAAANQAECgIIAgAAAA==.',
Si='Siik:BAAANQADCggIEAAAAA==.Silaena:BAAANQADCgYIDAAAAA==.Silverlocke:BAAANQADCgYIBgAAAA==.',
Sj='Sj:BAAANQADCgQIBAAAAA==.',
Sk='Skillcrusade:BAAANQADCgcIBwAAAA==.Skillscales:BAAANQAECgcIDQAAAA==.',
Sl='Sleepydk:BAAANQAECgEIAQAAAA==.Slovik:BAAANQAECgEIAgAAAA==.Slowbro:BAAANQADCgUICAAAAA==.',
Sm='Smok:BAAANQAECgIIAgAAAA==.',
So='Solanea:BAAANQADCgcIDAAAAA==.Solo:BAAANQADCgMIAwABNQAECgMIBQABAAAAAA==.Sorcero:BAAANQADCgYICgAAAA==.Soultelage:BAAANQADCgUIBgAAAA==.Sourwine:BAAANQADCgYICQAAAA==.',
Sp='Spaceman:BAAANQAECggIDwAAAA==.Spire:BAAANQADCggIGQAAAA==.Spritemonk:BAAANQAECgMIBQAAAA==.',
St='Stiffmcgee:BAAANQADCgcIDgAAAA==.Stormdancer:BAAANQAECgMIBQAAAA==.Stumpyfoot:BAAANQAECgEIAQAAAA==.Stygi:BAAANQADCgYICAAAAA==.Stárling:BAAANQAECgQIBAAAAA==.Stãrs:BAAANQAECgcIDQAAAA==.',
Su='Suki:BAAANQADCgMIAwAAAA==.Surfacing:BAAANQAECgQIBAAAAA==.',
Sy='Syntharia:BAAANQAECgIIAgAAAA==.',
Ta='Taffigosa:BAAANQAECgEIAQAAAA==.Taffy:BAAANQADCgMIAwAAAA==.Tanthel:BAAANQAECgEIAQAAAA==.Taursain:BAAANQADCgYIBwAAAA==.',
Tb='Tbh:BAAANQADCgEIAQAAAA==.',
Te='Terranteal:BAAANQADCggIDwAAAA==.Terravolta:BAAANQAECgIIAgAAAA==.Testarossa:BAAANQAECgEIAQAAAA==.',
Th='Themage:BAAANQADCgQIBAABNQADCggIDgABAAAAAA==.Therealvenat:BAAANQAECgIIAgAAAA==.Thiccbiddies:BAAANQAECgIIBAAAAA==.Thunderwings:BAAANQADCgYIBgAAAA==.',
Ti='Tigan:BAAANQADCggICwAAAA==.Tigra:BAAANQAECgEIAQAAAA==.Timelord:BAAANQAECgUIBgAAAA==.Timeweaver:BAAANQAECgIIAgAAAA==.Tirione:BAAANQAECgEIAQAAAA==.Tirogue:BAAANQADCgUIAgAAAA==.',
To='Toastshark:BAAANQAECgEIAQAAAA==.Toranaar:BAAANQADCggIDgAAAA==.Torpal:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Totorö:BAAANQAECgIIAgAAAA==.Tova:BAAANQADCgMIAwAAAA==.',
Tr='Traiturner:BAAANQADCgYIBgAAAA==.Trayfu:BAAANQADCgYICgAAAA==.Trice:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Trillion:BAAANQAECgEIAQAAAA==.Trostani:BAAANQAECgYIBQAAAA==.Truc:BAAANQADCgMIAwAAAA==.Trusker:BAAANQAECgIIAgAAAA==.',
Ts='Tsugumomo:BAAANQADCggICAAAAA==.',
Tu='Tullandil:BAAANQABCgQIAgAAAA==.',
Tw='Twitty:BAAANQADCgcIBwABNQAECgUIBwABAAAAAA==.',
Ty='Tyloestus:BAAANQADCggICAAAAA==.Tyragni:BAAANQAECgEIAQAAAA==.Tyravana:BAAANQADCgYIBgAAAA==.Tystriel:BAAANQADCgcIDQAAAA==.',
['Tí']='Tíamat:BAAANQADCggIDQAAAA==.',
Ul='Ulasar:BAAANQADCgUICAABNQADCgYICQABAAAAAA==.',
Va='Valdanyr:BAEANQADCgYICgAAAA==.Vallenar:BAAANQADCggIEwAAAA==.Valliant:BAAANQADCgQIBAAAAA==.Valnullis:BAAANQADCgUIBwAAAA==.Valorfist:BAAANQADCgQIBAAAAA==.Valídus:BAAANQADCgUICQAAAA==.Vampteabag:BAAANQADCggIDQAAAA==.Vanden:BAAANQAECgMIAwABNQAECgYIBgABAAAAAA==.Varsi:BAAANQAECgYICQAAAA==.',
Ve='Velash:BAAANQAECgEIAQAAAA==.Vendorin:BAAANQADCgYICgAAAA==.Verratanikto:BAAANQAECgEIAQAAAA==.Verwínd:BAAANQAECgEIAQAAAA==.',
Vi='Virusgt:BAAANQADCgcIBwAAAA==.Vitner:BAAANQAECgIIAgAAAA==.',
Vo='Voidsta:BAAANQADCgIIAgAAAA==.Volgur:BAAANQADCgYIEAAAAA==.Volker:BAAANQAECgEIAQAAAA==.',
We='Wenotknow:BAAANQAECgQIBQAAAA==.',
Wi='Wife:BAAANQAECgMIBQAAAA==.Wildraubtier:BAAANQADCgIIAgAAAA==.',
Wo='Wormsloe:BAAANQADCgYIBgAAAA==.',
Xa='Xaida:BAAANQAECgIIAgAAAA==.Xaldania:BAAANQADCgMIAwAAAA==.',
Xc='Xcaps:BAAANQADCgcIBwAAAA==.',
Xu='Xuing:BAAANQAECgEIAQAAAA==.Xuingg:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Ya='Yarro:BAAANQAECgEIAQAAAA==.',
Ye='Yesdaddy:BAAANQADCgcIDAAAAA==.',
Yo='Yorozu:BAAANQADCggIDwAAAA==.Young:BAAANQADCgQIBQABNQAECgQIBAABAAAAAA==.Youngblud:BAAANQAECgQIBAAAAA==.Youngplasma:BAAANQADCgQIBQABNQAECgQIBAABAAAAAA==.Yourhealor:BAAANQADCgYIBgAAAA==.',
Yu='Yuairi:BAAANQADCgQIBAAAAA==.Yugi:BAAANQAECgIIAgAAAA==.',
Za='Zahira:BAAANQAECgIIAgAAAA==.Zax:BAAANQADCgYICQAAAA==.',
Ze='Zenatra:BAAANQADCgYICwAAAA==.Zeroximo:BAAANQAECgIIAwAAAA==.',
Zi='Zipline:BAAANQADCggIDgAAAA==.Zirathiel:BAAANQADCgYIBgAAAA==.',
Zo='Zogz:BAAANQADCgEIAQAAAA==.Zombiexcat:BAAANQADCgEIAQAAAA==.Zorakiel:BAAANQAECgEIAQAAAA==.',
Zw='Zwiebelle:BAAANQAECgIIAgAAAA==.',
Zz='Zzyuniver:BAAANQADCggICAAAAA==.',
['ßl']='ßlight:BAAANQABCgEIAQAAAA==.',
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
