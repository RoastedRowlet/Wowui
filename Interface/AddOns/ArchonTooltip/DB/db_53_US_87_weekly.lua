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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Priest-Shadow','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Monk-Windwalker','Priest-Holy','Druid-Restoration','Rogue-Subtlety','Mage-Arcane','Evoker-Devastation','Warrior-Arms','Druid-Balance',}
local provider = {region='US',realm='Elune',name='US',type='weekly',zone=53,date='2026-09-08',data={Ae='Aelaya:BAAANQADCgQIBAAAAA==.Aeshen:BAAANQAECgUICAAAAA==.Aevea:BAAANQADCgUIBQABNQADCgYIDAABAAAAAA==.',
Ai='Aib:BAAANQADCgcIEwAAAA==.Aifertim:BAAANQADCgQIBAABNQAECggIDwABAAAAAA==.',
Ak='Akashah:BAAANQAECgQICQAAAA==.Akeno:BAAANQAECgEIAQAAAA==.',
Al='Alarick:BAAANQADCgcIEQAAAA==.Alatha:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Alathasedai:BAAANQAECgQIBgAAAA==.Alathea:BAAANQAECgcICgAAAA==.Aledis:BAAANQAECgYICwAAAA==.Allanøn:BAAANQADCgYIEAAAAA==.',
Am='Amalith:BAAANQADCgYIDAAAAA==.Amirial:BAAANQADCgQIBAAAAA==.Amowrath:BAAANQAECgMIBQAAAA==.Amyasia:BAAANQAECgQIBwAAAA==.',
An='Anghúro:BAAANQADCgYICQAAAA==.Angélica:BAAANQAECgYIDAAAAA==.Animethighs:BAAANQADCgcIBwAAAA==.',
Aq='Aquaskies:BAAANQAECgQIBAAAAA==.',
Ar='Arawynn:BAAANQAECgQIBAAAAA==.Archnessa:BAAANQAECgEIAQAAAA==.Arknight:BAAANQAECgQIBQAAAA==.Artémís:BAAANQAECgEIAQAAAA==.',
As='Astreae:BAAANQAECgIIAwAAAA==.',
At='Atamus:BAAANQADCggIDAAAAA==.',
Av='Avi:BAAANQADCggIDgABNQAECgYICAABAAAAAA==.',
Ay='Aya:BAAANQAECgQIBQAAAA==.Ayekillu:BAAANQADCggICwAAAA==.Ayiasofia:BAAANQAECgUIBgAAAA==.Ayla:BAAANQAECgMIBQAAAA==.Aylan:BAAANQAECgIIAgAAAA==.Ayumfox:BAAANQADCggICQAAAA==.Ayumm:BAAANQADCggICAAAAA==.',
Az='Azapal:BAAANQAECgUIBwAAAA==.Azuros:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.',
Ba='Babyjezuz:BAAANQAECgQIBAAAAA==.Badger:BAAANQAECgYICAAAAA==.Balloon:BAAANQADCgYIDAAAAA==.Bandâid:BAAANQADCgQIBAABNQAECgcICgABAAAAAA==.Barathiel:BAABNQAECoEXAAICAAgJHhMTHgA7AgACAAgJHhMTHgA7AgAAAA==.Barlow:BAAANQADCgcIEwAAAA==.Baryll:BAAANQAECgMIAwAAAA==.Batasu:BAAANQAECgQIBwAAAA==.Baulde:BAAANQAECgYICAAAAA==.',
Bi='Biefcake:BAAANQAECgUICQAAAA==.Bigmoo:BAAANQAECgcIDwAAAA==.',
Bk='Bk:BAAANQAECgEIAQAAAA==.',
Bl='Blackparade:BAAANQADCgIIAgAAAA==.Blaydun:BAAANQAECgIIAgAAAA==.Blewboar:BAAANQAECgUIBwAAAA==.Bllass:BAAANQADCgUICgAAAA==.Blueberrie:BAAANQAECgYICAAAAA==.Blyzard:BAAANQADCgIIAgAAAA==.',
Bo='Boiledfrogz:BAAANQAECgMIBAAAAA==.Boned:BAAANQAECgQIBwAAAA==.Boopboops:BAAANQAECgMIAwAAAA==.Bosleigor:BAAANQADCgYIBgAAAA==.',
Br='Bravehearthx:BAAANQAECgEIAQAAAA==.Bringerdk:BAAANQAFFAEIAQAAAA==.Bronco:BAAANQAECgQIBQAAAA==.Brünhïnnä:BAAANQADCgQIBQAAAA==.',
Bu='Bubblntendre:BAAANQAECgYICwAAAA==.',
Ca='Caféconron:BAAANQADCgIIAgAAAA==.Caitsidhe:BAAANQAECgQIBQAAAA==.Calinda:BAAANQADCgYIBgABNQAECgIIAwABAAAAAA==.Cannute:BAAANQAECgMIBAAAAA==.Canuckdruid:BAAANQADCgMIAwAAAA==.Canuckranger:BAAANQADCgYICQAAAA==.Captnubcakes:BAAANQAECgMIAwAAAA==.Carebear:BAAANQAECgcIDgAAAA==.Castallia:BAAANQAECgYICAAAAA==.Catrathena:BAAANQADCgYICgAAAA==.',
Ce='Celeborn:BAAANQADCgYIBgAAAA==.',
Ch='Chaelis:BAAANQAECgUICQAAAA==.Chalado:BAAANQADCgMIBAAAAA==.Chamanita:BAAANQAECgMIAwAAAA==.Charizzard:BAAANQADCgcIBwAAAA==.Chilléd:BAAANQAECgYIBgAAAA==.Chisato:BAAANQADCggICAABNQAECgIIAwABAAAAAA==.',
Ci='Cisticola:BAAANQAECgQIBQAAAA==.',
Cl='Clair:BAAANQAECggIDgAAAA==.Clova:BAAANQAECgQIBwAAAA==.',
Co='Combusty:BAAANQADCgEIAgAAAA==.Cornholyoh:BAABNQAECoEZAAIDAAkJpQ/VCwBwAgADAAkJpQ/VCwBwAgAAAA==.Counsel:BAAANQADCggICgAAAA==.',
Cr='Cremefraiche:BAAANQAECgIIAQAAAA==.Crillex:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Critkiller:BAAANQADCgcIGQAAAA==.Crulzilla:BAAANQAECgEIAQAAAA==.',
Cu='Cuero:BAAANQADCgUIBQAAAA==.Cupcakemeow:BAAANQAECgYIDAAAAA==.Curas:BAAANQAECgEIAgAAAA==.Curzøn:BAABNQAECoEZAAIEAAcJZybMAAAPAwAEAAcJZybMAAAPAwAAAA==.',
Cw='Cw:BAAANQAECgQICAAAAA==.Cwd:BAAANQADCgYIBwAAAA==.Cwds:BAAANQADCgcIEwABNQADCgYIBwABAAAAAA==.Cwoodz:BAAANQADCgQIBAABNQADCgYIBwABAAAAAA==.',
Da='Dabubblez:BAAANQADCgEIAQAAAA==.Daedengerek:BAAANQAECgQICAAAAA==.Daggers:BAAANQADCgQIBAAAAA==.Daigz:BAAANQADCgYICgAAAA==.Danerrin:BAABNQAECoEUAAMFAAgJ9SPjCQADAwAFAAgJuCLjCQADAwAGAAQJ3h9mFQBDAQAAAA==.Dangersaur:BAAANQAECgQIBAAAAA==.Danigos:BAAANQAFFAUICwAAAQ==.Darkcrushr:BAAANQADCgYICQAAAA==.Daryss:BAAANQADCgUIBgAAAA==.Daspirn:BAAANQADCgYICgAAAA==.Dawnshott:BAAANQADCgcIBwAAAA==.',
De='Deand:BAAANQABCgQIBAAAAA==.Deathadder:BAAANQAECgYICAAAAA==.Deathhounds:BAAANQADCgcIBwAAAA==.Deller:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.Demiphant:BAAANQAECgIIAgAAAA==.Dennirn:BAAANQADCggICAABNQAECggIFAAFAPUjAA==.',
Di='Diesalot:BAAANQAECgIIAQAAAA==.Divinedragon:BAAANQADCgcIEwAAAA==.',
Dr='Dracthar:BAAANQADCgYIDgAAAA==.Draczeal:BAAANQADCggIEgAAAA==.Dragonlee:BAAANQADCgEIAQAAAA==.Dragovade:BAAANQAECgQIBQAAAA==.Dreadlocke:BAAANQAECgEIAQAAAA==.Dreidels:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Drunkciggie:BAAANQAECgIIAgAAAA==.Drunky:BAAANQADCggIEgAAAA==.Drysua:BAAANQAECgYICwAAAA==.',
Du='Duffageddon:BAAANQADCgcIBwAAAA==.Duskmender:BAAANQAECgcIBwAAAA==.Duzick:BAAANQADCgUICAAAAA==.',
Dz='Dzmage:BAAANQADCggIGAAAAA==.Dzwarlock:BAAANQAECgQIBAAAAA==.',
['Dë']='Dëëds:BAAANQADCgUICAAAAA==.',
Ec='Ecklyn:BAAANQADCgIIAgABNQAECgQIBwABAAAAAA==.',
Eg='Egino:BAAANQADCgcICgAAAA==.',
El='Elarisiel:BAAANQADCggICAAAAA==.Elaynne:BAAANQAECgQICQAAAA==.Eldrith:BAAANQADCgIIAgABNQAECgQIBwABAAAAAA==.Eledis:BAAANQAECgIIAgAAAA==.Elemender:BAAANQAECgMIBAABNQAECgcIBwABAAAAAA==.Elieth:BAAANQADCgUIBQABNQADCggIDAABAAAAAA==.Eliteelf:BAAANQAECgEIAQAAAA==.Ellmer:BAAANQAECgQICQAAAA==.Elnir:BAAANQADCgUIBQAAAA==.Elopeppe:BAAANQADCggIEgAAAA==.Elorro:BAAANQAECgEIAQABNQAECgkJGQADAKUPAA==.Eltaizari:BAAANQADCgcICwAAAA==.Elthiør:BAAANQAECgMIBQAAAA==.Elumiel:BAAANQADCgYIBQAAAA==.Elunedorei:BAAANQADCgcICgAAAA==.Elwesingollo:BAAANQADCgYIBwAAAA==.',
En='Enilia:BAAANQAECgcICwAAAA==.Enrgizernelf:BAAANQADCgcIEwAAAA==.',
Er='Erathena:BAAANQADCgYIBgAAAA==.Eriya:BAAANQAECgMIAgAAAA==.',
Es='Esmeray:BAAANQADCgIIAgABNQAECgcIBwABAAAAAA==.Estalea:BAAANQADCgIIAgAAAA==.Estideeslol:BAAANQADCgcIEwAAAA==.',
Ey='Eyllis:BAAANQAECgQIBAAAAA==.',
Ez='Ezareth:BAAANQADCgUIBQAAAA==.',
Fa='Faded:BAAANQAECgIIAQAAAA==.Faedark:BAAANQADCgMIAgAAAA==.Farastraza:BAAANQABCgQIBgAAAA==.',
Fe='Feralscar:BAAANQADCgQIBAAAAA==.Ferangdh:BAAANQAECgQIBwAAAA==.Fevion:BAAANQADCggIEgAAAA==.Fevius:BAAANQAECgIIAQABNQADCggIEgABAAAAAA==.',
Fh='Fhantomgrave:BAAANQAECgQIBAAAAA==.',
Fi='Finduilas:BAAANQAECgQICQAAAA==.Firepower:BAAANQAECgQIBQAAAA==.Firepriest:BAAANQAECgQIBQAAAA==.Firesdruid:BAAANQADCgUICAABNQAECgQIBQABAAAAAA==.Fistu:BAAANQADCgQIBAAAAA==.',
Fl='Flappyjacks:BAAANQAECgMIAwAAAA==.Flappystraza:BAAANQADCgYIDQAAAA==.Fleabane:BAAANQABCgIIAgAAAA==.Flickka:BAAANQADCggIEgAAAA==.',
Fo='Fourteen:BAAANQAECgMIAwAAAA==.Fourus:BAAANQADCggICwAAAA==.',
Fr='Freakaleake:BAAANQAECgEIAQAAAA==.Freeport:BAAANQAECggIEgAAAA==.Freezerburn:BAAANQADCgUIBgABNQAECgEIAQABAAAAAA==.Frostmender:BAAANQADCggICAABNQAECgcIBwABAAAAAA==.Frostypillz:BAAANQABCgEIAQAAAA==.Frtouches:BAAANQADCgQIBAAAAA==.',
Fu='Funnymuffin:BAAANQAECgUICAAAAA==.Furyia:BAAANQADCggIFQAAAA==.Fuzzleprime:BAAANQAECgQIBQAAAA==.Fuzzy:BAAANQADCgUIBQAAAA==.',
Ga='Gaebora:BAAANQADCgcIDgAAAA==.Gahmull:BAAANQADCgYICgAAAA==.Galleae:BAAANQAECgQIBQAAAA==.Garmart:BAAANQAECgQIBAAAAA==.Gauza:BAAANQADCggIEgAAAA==.',
Gh='Ghouldann:BAAANQAECgQIBQAAAA==.',
Gi='Gionathir:BAAANQAECgEIAQAAAA==.',
Gl='Glagglag:BAAANQAECgYICAAAAA==.',
Go='Goldeen:BAAANQAECgQIBQAAAA==.Gorothraex:BAAANQADCgcIEwAAAA==.',
Gr='Graxion:BAAANQAECgIIAgAAAA==.Greggiiee:BAAANQADCgQIBAAAAA==.Grimmaw:BAAANQAECgQIBAAAAA==.Grindelwald:BAAANQADCggICAAAAA==.',
Gu='Guacamelee:BAAANQADCgcIEgAAAA==.',
Gw='Gwuak:BAAANQADCgYICwAAAA==.Gwynorra:BAAANQAECgMIAwAAAA==.',
Ha='Habibi:BAAANQAECgMIBAAAAA==.Haralda:BAAANQAECgIIAQAAAA==.Harshblue:BAAANQAECgQICQAAAA==.Hatt:BAAANQAECgIIAQAAAA==.Hatts:BAAANQADCgUICQAAAA==.Hawtnhordy:BAAANQADCgMIAwAAAA==.',
He='Healeydan:BAAANQAECgcIEQAAAA==.Heddh:BAAANQAECgQIBAABNQAECgQIBgABAAAAAA==.Heddruid:BAAANQAECgQIBgAAAA==.Heiligfeuer:BAAANQADCgYIDQAAAA==.Hentaya:BAAANQADCgYICQABNQABCgIIAgABAAAAAA==.Heyzuse:BAAANQADCgcIDwAAAA==.',
Hi='Hippay:BAAANQADCgcIEwAAAA==.',
Ho='Hoid:BAAANQADCggICAAAAA==.Holynihalus:BAAANQAECgcIEgAAAA==.Holypowerr:BAAANQAECgEIAQABNQAECggIDwABAAAAAA==.Holyspoons:BAAANQAECgcIDQAAAA==.Homar:BAAANQADCgcIEQAAAA==.Hoopa:BAABNQAFFIEGAAIHAAQJ3xJmAQBbAQAHAAQJ3xJmAQBbAQAAAA==.Houndwar:BAAANQADCgYIDAAAAA==.',
Hu='Huggs:BAAANQAECgQIBAAAAA==.Hunterama:BAAANQADCgUIBQAAAA==.Huntli:BAAANQAECgMIAwAAAA==.Huntrix:BAAANQADCggIEQAAAA==.Huricaine:BAAANQADCgUICQAAAA==.',
['Hé']='Hécate:BAAANQAECgYICQAAAA==.',
Ic='Icecreamcake:BAABNQAECoEaAAIIAAkJ4BSBDgCVAgAIAAkJ4BSBDgCVAgAAAA==.Icyy:BAAANQAECgEIAQAAAA==.',
Id='Idontpaint:BAAANQADCgUIBQABNQABCgQIBAABAAAAAA==.',
Il='Ilithya:BAAANQAECgEIAgAAAA==.Illidansdad:BAAANQADCggICAAAAA==.',
Io='Ioana:BAAANQABCgIIAgAAAA==.',
Ip='Iphei:BAAANQAECgQIBAAAAA==.',
Ir='Irulanni:BAAANQAECgYICAAAAA==.',
Is='Ishanaxade:BAAANQAECgMIBQAAAA==.',
Iv='Iva:BAAANQAECgYICAAAAA==.Ivanov:BAAANQADCgUIBQAAAA==.',
Iz='Izzie:BAAANQADCgcIBwAAAA==.',
Ja='Jackybrennan:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Jagershaii:BAAANQADCgYIDAAAAA==.Jaketm:BAAANQADCgQIBAAAAA==.Jalaven:BAAANQAECgMIAwAAAA==.Jano:BAAANQADCgEIAQAAAA==.',
Je='Jecka:BAAANQAECgQIBAAAAA==.Jentle:BAAANQAECgYICgAAAA==.Jessicka:BAAANQADCgcICgAAAA==.Jesûs:BAAANQADCgUIBQAAAA==.',
Ji='Jibbywibby:BAAANQADCgIIBAABNQAECgYIEAABAAAAAA==.Jibreel:BAAANQAECgEIAQAAAA==.Jinyla:BAAANQADCgQIBQAAAA==.Jinzho:BAAANQADCggICAAAAA==.Jiynila:BAAANQADCgcIEgAAAA==.',
Jo='Johey:BAAANQAECgQIBgAAAA==.',
Ju='Justinian:BAAANQABCgIIAQAAAA==.Juvenate:BAAANQAECgMIBQAAAA==.Juyani:BAAANQAECgEIAQAAAA==.',
Ka='Kailyn:BAAANQADCgIIAgAAAA==.Kaiyah:BAAANQADCgYIDAAAAA==.Kanab:BAAANQADCggIDgABNQAECgQIBAABAAAAAA==.Kayllea:BAAANQADCgYIEQABNQADCgcIFwABAAAAAA==.Kaytara:BAAANQAECgMIBQAAAA==.',
Ke='Keharn:BAAANQADCgYICwAAAA==.Kellen:BAABNQAECoEZAAIIAAkJ/CPwAgBhAwAIAAkJ/CPwAgBhAwAAAA==.Keloros:BAAANQADCgYICwAAAA==.Kenós:BAAANQAECgQIBAAAAA==.Kettock:BAAANQADCgYIDwAAAA==.Kevzorg:BAAANQABCgMIAwAAAA==.',
Ki='Kierk:BAAANQADCgUIBAAAAA==.Kilj:BAAANQAECgQIBQAAAA==.Kinuran:BAAANQAECgYICAAAAA==.Kitherry:BAAANQAECgMIAwAAAA==.',
Kn='Knifeprty:BAAANQAECgEIAQAAAA==.',
Ko='Kowdrak:BAAANQAECgEIAQAAAA==.',
Kr='Kreapen:BAAANQADCgcIEwAAAA==.Krisdk:BAABNQAECoEXAAIFAAgJ2iBNDADcAgAFAAgJ2iBNDADcAgAAAA==.Krisevoker:BAAANQADCgcIBwABNQAECggIFwAFANogAA==.',
Kt='Ktosh:BAAANQADCgUICAAAAA==.',
Ku='Kurenäi:BAAANQAECgEIAQAAAA==.Kurzul:BAAANQADCgMIAwAAAA==.',
Kw='Kwerin:BAAANQADCgcIEAAAAA==.',
['Kí']='Kírî:BAABNQAECoEYAAIJAAkJ2hnCBQC4AgAJAAkJ2hnCBQC4AgAAAA==.',
['Kö']='Körialstrasz:BAAANQAECgQIBAABNQAECgUIBQABAAAAAA==.',
La='Lacus:BAAANQAECgYICAAAAA==.Larat:BAAANQADCgYICQAAAA==.Laufeyson:BAAANQADCgQIBAAAAA==.Layara:BAAANQADCgQIBAAAAA==.Layil:BAAANQADCgYIDAAAAA==.Lazanya:BAAANQAECgIIAgAAAA==.',
Le='Legolamb:BAAANQAECgIIAQAAAA==.Leviasaint:BAAANQAECgQICQAAAA==.',
Lh='Lhadnire:BAAANQADCgYIBgABNQAECgcICgABAAAAAA==.',
Li='Lifeinsuranc:BAAANQADCgUICQAAAA==.Lightstim:BAAANQADCgIIAgAAAA==.Lilito:BAAANQADCgYIBgAAAA==.Limewire:BAAANQAECgQIBQAAAA==.',
Lo='Lodtuspuch:BAAANQABCgEIAQAAAA==.Lofie:BAAANQAECgQIBQAAAA==.Lonesnipa:BAAANQADCgUICAAAAA==.Looseyjoosey:BAAANQAECgIIAgAAAA==.Louiswu:BAAANQAECgIIAgAAAA==.',
Lu='Luciferias:BAAANQAECgYICQAAAA==.Luckyzounds:BAAANQABCgEIAQAAAA==.Lunariya:BAAANQADCggIDgAAAA==.',
Ly='Lyz:BAAANQADCggIDAAAAA==.',
Ma='Madreezov:BAAANQAECgEIAQAAAA==.Madreezus:BAAANQAECgYICgAAAA==.Magdalayna:BAAANQADCggICAAAAA==.Mangodemon:BAAANQAECggIEgAAAA==.Mangopally:BAAANQAECgEIAgABNQAECggIEgABAAAAAA==.Mantheon:BAAANQAECgEIAQAAAA==.Marvel:BAAANQAECgcICgAAAA==.Maybedos:BAAANQADCgYIDAAAAA==.Mayuki:BAAANQAECgcIEAAAAA==.',
Me='Melmard:BAAANQABCgMIBAAAAA==.Meowfurion:BAAANQADCgIIAgAAAA==.',
Mi='Miquella:BAAANQADCggICAABNQAECgUIBQABAAAAAA==.Mirrari:BAAANQADCggIEgAAAA==.Misschill:BAAANQADCgMIAwAAAA==.',
Mo='Mogin:BAAANQAECggIDwAAAA==.Molten:BAAANQADCggIEgAAAA==.Morganite:BAAANQADCgMIAwAAAA==.Moronica:BAAANQADCgcICQAAAA==.',
Mu='Muehpera:BAAANQAECgQIBAAAAA==.Muya:BAAANQADCgYIBgAAAA==.',
My='Myrabeth:BAAANQADCgMIAwAAAA==.',
Na='Nadion:BAAANQADCgQICwAAAA==.Naldon:BAAANQADCgUICAAAAA==.Naraine:BAAANQADCgYICAAAAA==.Nayhture:BAAANQADCgEIAQAAAA==.',
Ne='Nefka:BAAANQADCgYIBgAAAA==.Nefkhet:BAAANQADCgUICAAAAA==.Nephtyys:BAAANQAECgMIAwAAAA==.Nerfbat:BAAANQADCgcIEQAAAA==.Nes:BAAANQADCgUIBQAAAA==.',
Ni='Nightgecko:BAAANQAECgYICAAAAA==.Nihavoker:BAAANQADCgUIBQAAAA==.Nineteen:BAAANQAFFAEIAQABNQAECgMIAwABAAAAAA==.Niávy:BAAANQAECgIIAgAAAA==.',
No='Noedos:BAAANQAECgMIAwAAAA==.Nofoxgivn:BAAANQAECgEIAQAAAA==.Nogdem:BAAANQAECgMIAwAAAA==.Novaprime:BAAANQAECgEIAgAAAA==.',
Ob='Obeevoker:BAAANQAECgMIAwAAAA==.',
Oc='Ocala:BAAANQADCgMIAwAAAA==.',
Og='Ogryn:BAAANQADCgMIAwAAAA==.',
Om='Omgsogoth:BAAANQABCgEIAQAAAA==.',
Ot='Otosan:BAAANQAECgUIEAAAAA==.',
Pa='Palshi:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Pandariock:BAAANQAECgEIAQAAAA==.Parfait:BAAANQADCgYIBgAAAA==.Pawsatyou:BAAANQAECgQIBAAAAA==.',
Pe='Peachiekeen:BAAANQADCgYIDAAAAA==.Peekãboo:BAABNQAECoEXAAIKAAgJ0BngCACJAgAKAAgJ0BngCACJAgAAAA==.Peewheewoo:BAAANQADCgYICQAAAA==.Pelzy:BAAANQAECgQIBQAAAA==.Pepae:BAAANQAECgUICQAAAA==.',
Ph='Pholia:BAAANQADCgcIEwAAAA==.',
Pi='Pieni:BAAANQADCgYICgAAAA==.Pinkrose:BAAANQADCggIEgAAAA==.Pizza:BAAANQAECgEIAQAAAA==.',
Pl='Platomatrixx:BAAANQADCgYICwAAAA==.',
Po='Pollyanna:BAAANQADCggICAAAAA==.Poony:BAAANQAECgYIDQABNQAECggIGAALAGwiAA==.',
Pr='Proximus:BAAANQAECgEIAQABNQAECgUIBgABAAAAAA==.',
Ps='Psyop:BAAANQAECgYIBwAAAA==.',
Pu='Punnyname:BAAANQAECgQIBQAAAA==.Purrsian:BAAANQADCgYIDAAAAA==.',
Qb='Qberks:BAAANQAECgcIBwAAAA==.',
Qu='Quaddh:BAAANQADCggIDAAAAA==.Quellif:BAAANQABCgIIBAAAAA==.Quincee:BAAANQADCggICgAAAA==.',
Ra='Raenin:BAAANQAECgEIAQAAAA==.Ragingdraem:BAAANQAECgQIBwAAAA==.Raidei:BAAANQAECgQIBAAAAA==.Rainoffur:BAAANQAECgEIAQAAAA==.Rakeripwait:BAAANQADCgUIBQAAAA==.Ratatosk:BAAANQAECgEIAQAAAA==.Rathan:BAAANQAECgQIBQAAAA==.Ravenanarchy:BAAANQAECgYICAAAAA==.Rawheadrexx:BAAANQABCgIIAgAAAA==.',
Re='Redpawedfox:BAAANQAECgQIBQAAAA==.Rekviem:BAAANQAECgIIBAAAAQ==.Revie:BAAANQADCgQIBAABNQAECggIEgABAAAAAA==.',
Rh='Rhavaniel:BAAANQADCggIDgAAAA==.',
Ri='Rizzen:BAAANQADCgYIBgAAAA==.',
Ro='Roderika:BAAANQADCgYIDwAAAA==.Rogmar:BAAANQABCgIIAgAAAA==.Royalnewb:BAAANQAECgcIEwAAAA==.Royston:BAAANQAECgQIBQAAAA==.',
Ru='Rucereal:BAAANQAECgQIBAAAAA==.Rufous:BAAANQAECgQIBAAAAA==.',
Rw='Rwaga:BAAANQADCgMIBAAAAA==.',
Ry='Ryliea:BAAANQADCgMIAwAAAA==.Rynsidious:BAAANQAECgQICQAAAA==.',
['Rã']='Rãin:BAAANQAECgMIAwABNQAECgQIBwABAAAAAA==.',
['Rì']='Rìkú:BAAANQADCgUIBQAAAA==.',
Sa='Sabelle:BAAANQADCggIEgAAAA==.Sableanne:BAAANQABCgYICwAAAA==.Sabîne:BAAANQAECgMIBQAAAA==.Saeton:BAAANQAECgYICAAAAA==.Sahlaris:BAAANQAECgMIAwAAAA==.Salno:BAAANQADCgMIAwAAAA==.Samsonite:BAAANQAECgYIDQAAAA==.Sanji:BAAANQADCgIIAgAAAA==.Sariths:BAAANQABCgYICgAAAA==.',
Sc='Scrubpal:BAAANQADCggIDQAAAA==.',
Se='Sekhet:BAAANQAECgQIBQAAAA==.Sekhmet:BAAANQADCgMIAwAAAA==.Sekstrasza:BAAANQADCgMIAwAAAA==.Sens:BAAANQADCgUIBQAAAA==.Serrik:BAAANQAECggIBQAAAA==.Sersilkyhair:BAAANQAECgMIBAAAAA==.',
Sh='Shamanoid:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.Shasta:BAAANQAECgQIBQAAAA==.Shortmark:BAAANQADCgYIBgAAAA==.Shozwar:BAAANQAECgUIBwAAAA==.',
Si='Siik:BAAANQAECgQIBAAAAA==.Silaena:BAAANQADCgcIEwAAAA==.Silverlocke:BAAANQAECgQIBAAAAA==.',
Sj='Sj:BAAANQADCgQIBAAAAA==.',
Sk='Skillcrusade:BAAANQADCgcIBwAAAA==.Skillscales:BAABNQAECoEXAAIMAAgJiyE2BAD+AgAMAAgJiyE2BAD+AgAAAA==.Skyfallen:BAAANQAECgIIAgAAAA==.',
Sl='Sleepydk:BAAANQAECgQIBQAAAA==.Slovik:BAAANQAECgEIAgAAAA==.Slowbro:BAAANQADCgYIDgAAAA==.',
Sm='Smok:BAAANQAECgIIAgAAAA==.',
So='Softscars:BAAANQAECgIIAwAAAA==.Solanea:BAAANQAECgEIAQAAAA==.Solo:BAAANQADCgMIAwABNQAECgQICgABAAAAAA==.Sorcero:BAAANQADCggIEgAAAA==.Sorcforce:BAAANQADCgUIBQAAAA==.Soultelage:BAAANQADCgcIDQAAAA==.Sourwine:BAAANQADCgYICQAAAA==.',
Sp='Spaceman:BAABNQAECoEdAAINAAkJYCXiAADtAwANAAkJYCXiAADtAwAAAA==.Spire:BAAANQADCggIHwAAAA==.Sporkeh:BAAANQADCgMIAwAAAA==.Spritemonk:BAAANQAECgQICQAAAA==.Spritepally:BAAANQAECgQIBAABNQAECgQICQABAAAAAA==.',
St='Stellara:BAAANQADCgQIBwAAAA==.Stiffmcgee:BAAANQADCgcIDgAAAA==.Stormdancer:BAAANQAECgUIDwAAAA==.Stormpage:BAAANQAECgIIAgAAAA==.Stumpyfoot:BAAANQAECgQIBQAAAA==.Stygi:BAAANQADCgYICAAAAA==.Stárling:BAAANQAECgQICAAAAA==.Stãrs:BAABNQAECoEXAAMOAAgJDB9hDgC7AgAOAAgJDB9hDgC7AgAJAAEJ3gayMQAxAAAAAA==.',
Su='Surfacing:BAAANQAECgYICQAAAA==.',
Sy='Syntharia:BAAANQAECgYICAAAAA==.',
Ta='Taffigosa:BAAANQAECgIIAgAAAA==.Taffy:BAAANQADCgMIAwAAAA==.Tanthel:BAAANQAECgIIAwAAAA==.Taursain:BAAANQADCgYIBwAAAA==.',
Te='Terranteal:BAAANQAECgMIAwAAAA==.Terraquis:BAAANQAECgIIAgAAAA==.Terravolta:BAAANQAECgYIBwAAAA==.Testarossa:BAAANQAECgQIBQAAAA==.',
Th='Themage:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Therealvenat:BAAANQAECgMIBQAAAA==.Thiccbiddies:BAAANQAECgQICAAAAA==.Thunderwings:BAAANQADCgcIDQAAAA==.',
Ti='Tigan:BAAANQAECgIIAgAAAA==.Tigra:BAAANQAECgYIBwAAAA==.Timelord:BAAANQAECgUIBwAAAA==.Timeweaver:BAAANQAECgYICAAAAA==.Tirione:BAAANQAECgIIAwAAAA==.Tirogue:BAAANQADCgUIBgAAAA==.',
To='Toastshark:BAAANQAECgQIBQAAAA==.Toranaar:BAAANQADCggIDgAAAA==.Torpal:BAAANQADCgUICAABNQAECgQIBQABAAAAAA==.Totorö:BAAANQAECgQIBwAAAA==.Tova:BAAANQADCgYICAAAAA==.',
Tr='Traiturner:BAAANQAECgQIBAAAAA==.Trayfu:BAAANQADCggIEgAAAA==.Trice:BAAANQAECgMIBAAAAA==.Trillion:BAAANQAECgQIBQAAAA==.Trostani:BAAANQAECgYIBQAAAA==.Truc:BAAANQADCgMIAwAAAA==.Trusker:BAAANQAECgIIAgAAAA==.',
Ts='Tsaavas:BAAANQAECgMIBAAAAA==.Tsereya:BAAANQADCgYIBgAAAA==.Tsugumomo:BAAANQADCggICAAAAA==.',
Tu='Tullandil:BAAANQABCgQIAgAAAA==.',
Tw='Twitty:BAAANQAECgMIAwABNQAECgcIDgABAAAAAA==.',
Ty='Tyloestus:BAAANQAECgEIAQAAAA==.Tyragni:BAAANQAECgEIAQAAAA==.Tyravana:BAAANQADCgYIBgAAAA==.Tystriel:BAAANQAECgIIAgAAAA==.',
['Tí']='Tíamat:BAAANQAECgEIAQAAAA==.',
Ul='Ulasar:BAAANQADCgUIDQABNQADCgYICQABAAAAAA==.',
Va='Valdanyr:BAEANQADCggIEgAAAA==.Vallenar:BAAANQADCggIGwAAAA==.Valliant:BAAANQADCggIDAAAAA==.Valnullis:BAAANQADCgUIBwAAAA==.Valorfist:BAAANQADCgQIBAAAAA==.Valídus:BAAANQADCgYICgAAAA==.Vampteabag:BAAANQADCggIDQAAAA==.Vanden:BAAANQAECgMIAwABNQAECgYIBgABAAAAAA==.Varsi:BAAANQAECgcIEAAAAA==.',
Ve='Veetor:BAAANQAECgMIBAAAAA==.Velash:BAAANQAECgIIAwAAAA==.Vendorin:BAAANQADCggIEgAAAA==.Verratanikto:BAAANQAECgQIBQAAAA==.Verwínd:BAAANQAECgUIBgAAAA==.',
Vi='Virusgt:BAAANQADCgcIBwAAAA==.Vitner:BAAANQAECgcICQAAAA==.',
Vo='Voidbeam:BAAANQAECgEIAQAAAA==.Voidsta:BAAANQADCgIIAgAAAA==.Volgur:BAAANQADCgcIFwAAAA==.Volker:BAAANQAECgQIBQAAAA==.',
We='Wenotknow:BAAANQAECgYICwAAAA==.',
Wi='Wife:BAAANQAECgQICgAAAA==.Wildraubtier:BAAANQADCgIIAgAAAA==.',
Wo='Wormsloe:BAAANQADCgYIBgAAAA==.',
Xa='Xaida:BAAANQAECgMIBQAAAA==.Xaldania:BAAANQADCgMIBgAAAA==.',
Xc='Xcaps:BAAANQADCgcIBwAAAA==.',
Xu='Xuing:BAAANQAECgYIBwAAAA==.Xuingg:BAAANQADCgYIBgABNQAECgYIBwABAAAAAA==.',
Ya='Yarp:BAAANQADCgUIBQAAAA==.Yarro:BAAANQAECgYIBwAAAA==.',
Ye='Yesdaddy:BAAANQADCgcIEwAAAA==.',
Yo='Yorozu:BAAANQAECgEIAQAAAA==.Young:BAAANQADCgQICAABNQAECgcICgABAAAAAA==.Youngblud:BAAANQAECgcICgAAAA==.Youngplasma:BAAANQADCgYICwABNQAECgcICgABAAAAAA==.Yourhealor:BAAANQADCgYIBgAAAA==.',
Yu='Yuairi:BAAANQADCgQIBAAAAA==.Yugi:BAAANQAECgMIBAAAAA==.',
Za='Zaela:BAAANQADCgQIBAAAAA==.Zahira:BAAANQAECgMIBQAAAA==.Zax:BAAANQADCggIEQAAAA==.',
Ze='Zenatra:BAAANQADCgYICwAAAA==.Zeroximo:BAAANQAECgYICQAAAA==.',
Zi='Zipline:BAAANQAECgQIBAAAAA==.Zirathiel:BAAANQADCgYICAABNQADCggIDAABAAAAAA==.',
Zo='Zogz:BAAANQADCgIIAwAAAA==.Zombiexcat:BAAANQADCgEIAQAAAA==.Zorakiel:BAAANQAECgQIBQAAAA==.',
Zw='Zwiebelle:BAAANQAECgMIBQAAAA==.',
Zz='Zzyuniver:BAAANQADCggICAAAAA==.',
['ßl']='ßlight:BAAANQADCgMIAwAAAA==.',
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
