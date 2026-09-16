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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Hunter-BeastMastery','Druid-Guardian','Paladin-Holy','Priest-Holy','Priest-Shadow','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','Mage-Arcane','Priest-Discipline','Paladin-Retribution','Monk-Windwalker','Shaman-Enhancement','DemonHunter-Devourer','Rogue-Subtlety','Evoker-Augmentation','Evoker-Devastation','Warrior-Arms','Druid-Balance','Hunter-Survival','Hunter-Marksmanship',}
local provider = {region='US',realm='Elune',name='US',type='weekly',zone=53,date='2026-09-15',data={Ae='Aelaya:BAAANQADCgQIBAAAAA==.Aeshen:BAAANQAECgUICAAAAA==.Aevea:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.',
Ai='Aib:BAAANQAECgIIAgAAAA==.Aifertim:BAAANQADCgQIBAABNQAECgkJFwACADQcAA==.',
Ak='Akashah:BAAANQAECgYIDwAAAA==.Akeno:BAAANQAECgEIAQAAAA==.',
Al='Alarick:BAAANQAECgIIAgAAAA==.Alatha:BAAANQADCgQIBAABNQAECgUICwABAAAAAA==.Alathasedai:BAAANQAECgUICwAAAA==.Alathea:BAAANQAECggIEwAAAA==.Aledis:BAAANQAECgcIEgAAAA==.Allanøn:BAAANQADCgYIEAAAAA==.',
Am='Amalith:BAAANQADCgcIEwAAAA==.Amirial:BAAANQADCggIDAAAAA==.Amowrath:BAAANQAECgMIBQAAAA==.Amyasia:BAAANQAECgQIBwABNQAECgYIBgABAAAAAA==.',
An='Anghúro:BAAANQADCgYICQABNQADCgcIFAABAAAAAA==.Angélica:BAAANQAECgYIDAAAAA==.Animethighs:BAAANQADCgcIDAAAAA==.Ankoou:BAAANQABCgQIBQAAAA==.',
Aq='Aquaskies:BAAANQAECgYICgAAAA==.',
Ar='Arawynn:BAAANQAECgQICAAAAA==.Archnessa:BAAANQAECgEIAQAAAA==.Ariock:BAAANQAECgQIBAAAAA==.Arknight:BAAANQAECgQICQAAAA==.Artémís:BAAANQAECgEIAQAAAA==.',
As='Astreae:BAAANQAECgQIBwAAAA==.',
At='Atamus:BAAANQADCggIEwAAAA==.',
Av='Avanah:BAAANQADCgYIBgAAAA==.Avi:BAAANQAECgYIBgABNQAECgcIDwABAAAAAA==.',
Ay='Aya:BAAANQAECgQICQAAAA==.Ayekillu:BAAANQAECgQIBAAAAA==.Ayiasofia:BAAANQAECgYIDAAAAA==.Ayla:BAAANQAECgMIBQAAAA==.Aylan:BAAANQAECgIIBAAAAA==.Ayumfox:BAAANQAECgcICAAAAA==.Ayumm:BAAANQADCggICAAAAA==.',
Az='Azapal:BAAANQAECgYIDQAAAA==.Azuros:BAAANQADCgUICAABNQAECgYICwABAAAAAA==.',
Ba='Babyjezuz:BAAANQAECgQICAAAAA==.Badger:BAAANQAECgYIDgAAAA==.Balloon:BAAANQADCggIFAAAAA==.Bandâid:BAAANQADCgUIBwABNQAECgcICwABAAAAAA==.Barathiel:BAABNQAECoEfAAIDAAgJFRXcKgBSAgADAAgJFRXcKgBSAgAAAA==.Barlow:BAAANQAECgEIAQAAAA==.Baryll:BAAANQAECgMIBAAAAA==.Batasu:BAAANQAECgUICQAAAA==.Baulde:BAAANQAECgcIDwAAAA==.',
Be='Beerbroth:BAAANQAECgYIBgAAAA==.',
Bi='Biefcake:BAAANQAECgYIDwAAAA==.Bigmoo:BAABNQAECoEaAAIEAAgJghuFBACKAgAEAAgJghuFBACKAgAAAA==.Bigoldotties:BAAANQAECgEIAQAAAA==.',
Bk='Bk:BAAANQAECgIIAwAAAA==.',
Bl='Blackparade:BAAANQAECgMIAwAAAA==.Blaydun:BAAANQAECgIIAgAAAA==.Blewboar:BAAANQAECgUIBwAAAA==.Bllass:BAAANQADCgUIDwAAAA==.Blueberrie:BAAANQAECgYIDQAAAA==.Blyzard:BAAANQADCgQIBgAAAA==.',
Bo='Boiledfrogz:BAAANQAECgcICwAAAA==.Boned:BAAANQAECggIEAAAAA==.Boopboops:BAAANQAECgUICAAAAA==.Bosleigor:BAAANQADCgYIBgAAAA==.',
Br='Bravehearthx:BAAANQAECgQIBQAAAA==.Bringerdk:BAAANQAFFAEIAQAAAA==.Brogend:BAAANQAECgQIBAABNQAECgYIDgABAAAAAA==.Bronco:BAAANQAECgQICQAAAA==.Brume:BAAANQADCgYIBgAAAA==.Brünhïnnä:BAAANQADCgQIBQAAAA==.',
Bu='Bubblntendre:BAAANQAECgYIEQAAAA==.',
Ca='Caféconron:BAAANQAECgQIBAAAAA==.Caitsidhe:BAAANQAECgQICQAAAA==.Calinda:BAAANQADCgYICgABNQAECgMIBgABAAAAAA==.Cannute:BAAANQAECgMIBgAAAA==.Canuckdruid:BAAANQADCgcICgAAAA==.Canuckranger:BAAANQAECgQIBAAAAA==.Captnubcakes:BAAANQAECgMIBAAAAA==.Carebear:BAABNQAECoEbAAIFAAkJCRscDwDtAgAFAAkJCRscDwDtAgAAAA==.Castallia:BAAANQAECgcIDwAAAA==.Catrathena:BAAANQADCggIEgAAAA==.',
Ce='Celeborn:BAAANQADCgYIBgAAAA==.Celta:BAAANQADCgQIBAAAAA==.',
Ch='Chaelis:BAAANQAECgYIDwAAAA==.Chalado:BAAANQADCgMIBAAAAA==.Chamanita:BAAANQAECgMIBAAAAA==.Charizzard:BAAANQADCgcIBwAAAA==.Cheweh:BAAANQAECgYIBgAAAA==.Chilléd:BAAANQAECgYIBgAAAA==.Chisato:BAAANQADCggICAABNQAECgIIAwABAAAAAA==.Chwamzrogue:BAAANQADCgIIAgAAAA==.',
Ci='Cisticola:BAAANQAECgYICQAAAA==.Citii:BAAANQADCgQIBAAAAA==.',
Cl='Clair:BAABNQAECoEZAAIGAAkJsxWsHgBUAgAGAAkJsxWsHgBUAgAAAA==.Clova:BAAANQAECgUIDAAAAA==.',
Co='Combusty:BAAANQADCgEIAgAAAA==.Cornholyoh:BAABNQAECoEfAAIHAAkJxBNoDQCfAgAHAAkJxBNoDQCfAgAAAA==.Counsel:BAAANQAECgIIAgAAAA==.',
Cr='Cremefraiche:BAAANQAECgMIAQAAAA==.Crillex:BAAANQADCgMIAwABNQAECgIIBAABAAAAAA==.Critkiller:BAAANQAECgEIAQAAAA==.Crulzilla:BAAANQAECgEIAQAAAA==.',
Cu='Cuero:BAAANQADCgUIBQAAAA==.Cupcakemeow:BAAANQAECgcIEAAAAA==.Curas:BAAANQAECgIIBAAAAA==.Curzøn:BAABNQAECoEfAAIIAAcJZyZsAQD/AgAIAAcJZyZsAQD/AgAAAA==.',
Cw='Cw:BAAANQAECgQICQAAAA==.Cwd:BAAANQADCgYIBwAAAA==.Cwds:BAAANQADCgcIEwABNQADCgYIBwABAAAAAA==.Cwoodz:BAAANQADCggIDAABNQADCgYIBwABAAAAAA==.',
Da='Dabubblez:BAAANQADCgEIAQAAAA==.Daedengerek:BAAANQAECgQICAAAAA==.Daggers:BAAANQADCgQIBAAAAA==.Daigz:BAAANQADCgYICgAAAA==.Danerrin:BAABNQAECoEdAAMJAAkJwiMUCgAqAwAJAAgJeSMUCgAqAwAKAAUJ9x/1HgCHAQAAAA==.Dangersaur:BAAANQAECgQIBAAAAA==.Danielsan:BAAANQABCgYIBwAAAA==.Danigos:BAAANQAFFAYIDwAAAQ==.Darkcrushr:BAAANQADCgYICQAAAA==.Daryss:BAAANQADCgcIDAAAAA==.Daspirn:BAAANQADCgYICgAAAA==.Dawnshott:BAAANQADCggIDwAAAA==.',
De='Deand:BAAANQABCgQIBAAAAA==.Deathadder:BAAANQAECgcIDwAAAA==.Deathhounds:BAAANQADCgcIBwAAAA==.Deller:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.Demiphant:BAAANQAECgIIBAAAAA==.Dennirn:BAAANQADCggICAABNQAECgkJHQAJAMIjAA==.',
Di='Diesalot:BAAANQAECgMIAwAAAA==.Divinedragon:BAAANQAECgIIAgAAAA==.',
Dr='Dracthar:BAAANQADCgcIFQAAAA==.Draczeal:BAAANQAECgEIAQAAAA==.Dragonlee:BAAANQADCgEIAQAAAA==.Dragovade:BAAANQAECgQICQAAAA==.Dreadlocke:BAAANQAECgQIBQAAAA==.Dreidels:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.Drunkciggie:BAAANQAECgMIAwAAAA==.Drunky:BAAANQAECgEIAQAAAA==.Drysua:BAAANQAECgcIEgAAAA==.',
Du='Duffageddon:BAAANQADCgcIBwAAAA==.Duskmender:BAAANQAECgcIEAAAAA==.Duzick:BAAANQADCgUICAAAAA==.',
Dz='Dzmage:BAAANQAECgEIAQAAAA==.Dzwarlock:BAAANQAECgUIDgAAAA==.',
['Dë']='Dëëds:BAAANQADCgUICAAAAA==.',
Ec='Ecklyn:BAAANQADCgIIAgABNQAECgUICQABAAAAAA==.',
Eg='Egino:BAAANQADCgcIEAAAAA==.',
El='Elarisiel:BAAANQADCggICAAAAA==.Elaynne:BAAANQAECgQIDQAAAA==.Eldrith:BAAANQADCgIIAgABNQAECgUICQABAAAAAA==.Eledis:BAAANQAECgIIBAAAAA==.Elemender:BAAANQAECgMIBgABNQAECgcIEAABAAAAAA==.Elementrix:BAAANQAECggIAQAAAA==.Elieth:BAAANQADCgUICQABNQADCggIDAABAAAAAA==.Eliteelf:BAAANQAECgQIBQAAAA==.Ellenora:BAAANQADCgYIBgAAAA==.Ellmer:BAAANQAECgYIDwAAAA==.Elnir:BAAANQADCgUIBQAAAA==.Elopeppe:BAAANQAECgEIAQAAAA==.Elorro:BAAANQAECgEIAQABNQAECgkJHwAHAMQTAA==.Eltaizari:BAAANQAECgIIAgAAAA==.Elthiør:BAAANQAECgYICwAAAA==.Elumiel:BAAANQAECgMIAwAAAA==.Elunedorei:BAAANQADCgcICgAAAA==.Elunelol:BAAANQAFFAIIAgABNQAFFAQICQALABEWAA==.Elwesingollo:BAAANQADCgYICwAAAA==.',
En='Enilia:BAAANQAECgcIEgAAAA==.Enrgizernelf:BAAANQADCgcIEwAAAA==.',
Eo='Eo:BAAANQADCggICAAAAA==.',
Er='Erathena:BAAANQADCgYIBgAAAA==.Eriya:BAAANQAECgIIBAAAAA==.',
Es='Esmeray:BAAANQADCgIIAgABNQAECgcIEAABAAAAAA==.Estalea:BAAANQADCgIIAgAAAA==.Estideeslol:BAAANQAECgIIAgAAAA==.',
Ey='Eyllis:BAAANQAECgYICgAAAA==.',
Ez='Ezareth:BAAANQADCgUIBQAAAA==.',
Fa='Faded:BAAANQAECgIIAQAAAA==.Faedark:BAAANQADCgMIAgAAAA==.Farastraza:BAAANQADCgIIAgAAAA==.',
Fe='Feralscar:BAAANQADCgQIBAAAAA==.Ferangdh:BAAANQAECgQIBwABNQAECgYIBgABAAAAAA==.Fevion:BAAANQAECgIIAgAAAA==.Fevius:BAAANQAECgIIAwABNQAECgIIAgABAAAAAA==.',
Fh='Fhantomgrave:BAAANQAECgQICAAAAA==.',
Fi='Finduilas:BAAANQAECgYIDwAAAA==.Firepower:BAAANQAECgUICgAAAA==.Firepriest:BAAANQAECgQICAAAAA==.Firesdruid:BAAANQADCgUICAABNQAECgQICAABAAAAAA==.Fistu:BAAANQADCgQIBAAAAA==.',
Fl='Flagon:BAAANQADCgUIBQABNQADCgcICgABAAAAAA==.Flappyjacks:BAAANQAECgQIBQAAAA==.Flappystraza:BAAANQAECgIIAgAAAA==.Fleabane:BAAANQABCgIIAgAAAA==.Flickka:BAAANQAECgIIAgAAAA==.',
Fo='Fourteen:BAAANQAECgMIAwAAAA==.Fourus:BAAANQADCggIEQAAAA==.',
Fr='Freakaleake:BAAANQAECgEIAQAAAA==.Freeport:BAABNQAECoEYAAIMAAkJqiPxCgCIAwAMAAkJqiPxCgCIAwAAAA==.Freezerburn:BAAANQADCgYIDAABNQAECgQIBQABAAAAAA==.Frostmender:BAAANQADCggICAABNQAECgcIEAABAAAAAA==.Frostypillz:BAAANQABCgEIAQAAAA==.Frtouches:BAAANQAECgIIAgAAAA==.',
Fu='Funnymuffin:BAAANQAECgYIDgAAAA==.Furyia:BAAANQADCggIHQAAAA==.Furyk:BAAANQAECgQIBAAAAA==.Fuzzleprime:BAAANQAECgQICQAAAA==.Fuzzy:BAAANQADCgUIBQAAAA==.',
Ga='Gaebora:BAAANQADCggIEQAAAA==.Gahmull:BAAANQADCgYICgAAAA==.Galleae:BAAANQAECgQICQAAAA==.Garmart:BAAANQAECgcICwAAAA==.Gauza:BAAANQAECgEIAQAAAA==.',
Gh='Ghouldann:BAAANQAECgQIBQAAAA==.',
Gi='Gionathir:BAAANQAECgEIAQAAAA==.',
Gl='Glagglag:BAAANQAECgcIDgAAAA==.',
Go='Goldeen:BAAANQAECgQICQAAAA==.Gorothraex:BAAANQADCgcIEwAAAA==.',
Gr='Graxion:BAAANQAECgQIBgAAAA==.Greggiiee:BAAANQAECgIIAgAAAA==.Grimmaw:BAAANQAECgQIBAAAAA==.Grindelwald:BAAANQADCggIEAAAAA==.',
Gu='Guacamelee:BAAANQAECgEIAQAAAA==.',
Gw='Gwuak:BAAANQADCgYIEQAAAA==.Gwynorra:BAAANQAECgMIAwAAAA==.',
Ha='Habibi:BAAANQAECgQICAAAAA==.Haralda:BAAANQAECgYIBQAAAA==.Harshblue:BAAANQAECgYIDwAAAA==.Hatt:BAAANQAECgYIBwAAAA==.Hatts:BAAANQADCgUICQAAAA==.Hawtnhordy:BAAANQADCgMIAwAAAA==.',
He='Healeydan:BAABNQAECoEdAAQGAAkJqCQ5AgCTAwAGAAkJjiQ5AgCTAwANAAcJPCCQAgCGAgAHAAIJ4gsKPABqAAAAAA==.Heddh:BAAANQAECgYICgABNQAECgUICwABAAAAAA==.Heddruid:BAAANQAECgUICwAAAA==.Heiligfeuer:BAAANQADCgcIFAAAAA==.Hentaya:BAAANQADCgYIDwABNQABCgIIAgABAAAAAA==.Heythanksman:BAAANQADCgYIBgAAAA==.Heyzuse:BAAANQAECgEIAQAAAA==.',
Hi='Hippay:BAAANQAECgEIAQAAAA==.',
Ho='Hoid:BAAANQAECgEIAQAAAA==.Holynihalus:BAABNQAECoEcAAIGAAkJ8xvqEADBAgAGAAkJ8xvqEADBAgAAAA==.Holypowerr:BAAANQAECgEIAQABNQAECgkJFwACADQcAA==.Holyspoons:BAABNQAECoEZAAIOAAkJ/xQ3LABeAgAOAAkJ/xQ3LABeAgAAAA==.Homar:BAAANQAECgIIAgAAAA==.Hoopa:BAABNQAFFIELAAIPAAUJ4haDAQDPAQAPAAUJ4haDAQDPAQAAAA==.Hordemender:BAAANQADCgYIBwABNQAECgcIEAABAAAAAA==.Houndwar:BAAANQADCgYIDAAAAA==.',
Hu='Huggs:BAAANQAECgYICgAAAA==.Hunterama:BAAANQADCgUIBQAAAA==.Huntli:BAAANQAECgMIBAAAAA==.Huntrix:BAAANQAECgIIAgAAAA==.Huricaine:BAAANQAECgEIAQAAAA==.',
['Hé']='Hécate:BAAANQAECgcIEAAAAA==.',
Ic='Icecreamcake:BAACNQAFFIEKAAIGAAYJvgNFAwCyAQAGAAYJvgNFAwCyAQA1AAQKgR0AAgYACQnTGDkXAIsCAAYACQnTGDkXAIsCAAAA.Icyy:BAAANQAECgMIBAAAAA==.',
Id='Idontpaint:BAAANQADCgUIBQABNQABCgQIBAABAAAAAA==.',
Il='Ilithya:BAAANQAECgEIAgAAAA==.Illidansdad:BAAANQAECgIIAgAAAA==.',
Io='Ioana:BAAANQAECgEIAQAAAA==.',
Ip='Iphei:BAAANQAECgQIBAAAAA==.',
Ir='Irulanni:BAAANQAECgcIDwAAAA==.',
Is='Ishanaxade:BAAANQAECgQICQAAAA==.',
Iv='Iva:BAAANQAECgcIDwAAAA==.Ivanov:BAAANQADCgUIBQAAAA==.',
Iz='Izzie:BAAANQADCgcIBwAAAA==.',
Ja='Jackybrennan:BAAANQADCgcIBwABNQAECgUIBwABAAAAAA==.Jagershaii:BAAANQADCgcIEwAAAA==.Jaketm:BAAANQADCgQIBAAAAA==.Jalaven:BAAANQAECgQIBwAAAA==.Jano:BAAANQADCgEIAQAAAA==.Jas:BAAANQADCggIFQAAAA==.',
Je='Jecka:BAAANQAECgQIBwAAAA==.Jentle:BAAANQAECgYICgAAAA==.Jessicka:BAAANQAECgIIAgAAAA==.Jesûs:BAAANQADCgUIBQAAAA==.',
Ji='Jibbywibby:BAAANQADCgIIBAABNQAECgcIFwAQAFQhAA==.Jibreel:BAAANQAECgEIAQAAAA==.Jinyla:BAAANQADCgQIBQAAAA==.Jinzho:BAAANQAECgQIBAAAAA==.Jiynila:BAAANQADCgcIEgAAAA==.',
Jo='Johey:BAAANQAECgYIDAABNQABCgUIBQABAAAAAA==.',
Ju='Juanchoxch:BAAANQAECgEIAQAAAA==.Justinian:BAAANQABCgMIAQAAAA==.Juvenate:BAAANQAECgQICQAAAA==.Juyani:BAAANQAECgEIAgAAAA==.',
Ka='Kailyn:BAAANQADCgIIAgAAAA==.Kaiyah:BAAANQADCgcIEwAAAA==.Kanab:BAAANQAECgEIAQABNQAECgcICwABAAAAAA==.Kayllea:BAAANQADCgYIFwABNQADCggIHwABAAAAAA==.Kaytara:BAAANQAECgQICQAAAA==.',
Ke='Keharn:BAAANQADCgYIEQAAAA==.Kellen:BAACNQAFFIEGAAIGAAQJ3R58BAB7AQAGAAQJ3R58BAB7AQA1AAQKgSAAAgYACQl7JNsHACkDAAYACQl7JNsHACkDAAAA.Keloros:BAAANQADCgYICwAAAA==.Kenós:BAAANQAECgUICAAAAA==.Kettock:BAAANQADCgcIFgAAAA==.Kevzorg:BAAANQABCgMIAwAAAA==.',
Ki='Kierk:BAAANQADCgUIBAAAAA==.Kilj:BAAANQAECgQICQAAAA==.Kinuran:BAAANQAECgcIDwAAAA==.Kitherry:BAAANQAECgMIBAAAAA==.',
Kn='Knifeprty:BAAANQAECgEIAQAAAA==.',
Ko='Kowdrak:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Kowmann:BAAANQABCgcIBwABNQAECgMIAwABAAAAAA==.',
Kr='Kreapen:BAAANQAECgIIAgAAAA==.Krisdk:BAABNQAECoEgAAIJAAkJ+SGtBwBQAwAJAAkJ+SGtBwBQAwAAAA==.Krisevoker:BAAANQAECgUIBQABNQAECgkJIAAJAPkhAA==.',
Ku='Kurenäi:BAAANQAECgQIBQAAAA==.Kurzul:BAAANQADCgMIAwAAAA==.',
Kw='Kwerin:BAAANQAECgEIAQAAAA==.',
['Kí']='Kírî:BAABNQAECoEgAAILAAkJ2hmGCQCiAgALAAkJ2hmGCQCiAgAAAA==.',
['Kö']='Körialstrasz:BAAANQAECgQIBQABNQAECgUIBQABAAAAAA==.',
La='Lacus:BAAANQAECgcIDwAAAA==.Larat:BAAANQADCgYIDwAAAA==.Laufeyson:BAAANQADCgQIBAAAAA==.Layara:BAAANQADCgUIBQAAAA==.Layil:BAAANQAECgEIAQAAAA==.Lazanya:BAAANQAECgQIBgAAAA==.',
Le='Legolamb:BAAANQAECgQIBQAAAA==.Leviasaint:BAAANQAECgYIDwAAAA==.',
Lh='Lhadnire:BAAANQADCgYIBgABNQAECgcICwABAAAAAA==.',
Li='Lifeinsuranc:BAAANQADCgUICQAAAA==.Lightstim:BAAANQADCgIIAgAAAA==.Lilito:BAAANQAECgQIBQAAAA==.Limewire:BAAANQAECgYICQAAAA==.',
Lo='Lodtuspuch:BAAANQABCgEIAQAAAA==.Lofie:BAAANQAECgYICQAAAA==.Lonesnipa:BAAANQADCgUICAAAAA==.Looseyjoosey:BAAANQAECgQIBgAAAA==.Louiswu:BAAANQAECgUIBwAAAA==.',
Lu='Luciferias:BAAANQAECgYIDwAAAA==.Luckyzounds:BAAANQABCgEIAQAAAA==.Lunariya:BAAANQAECgMIAwAAAA==.',
Ly='Lyz:BAAANQAECgEIAQAAAA==.',
Ma='Madreezov:BAAANQAECgEIAQAAAA==.Madreezus:BAAANQAECgYICgAAAA==.Magdalayna:BAAANQADCggICAABNQADCggICAABAAAAAA==.Malfron:BAAANQADCgEIAQAAAA==.Mangodemon:BAABNQAECoEWAAIRAAkJ9iB7BQBXAwARAAkJ9iB7BQBXAwAAAA==.Mangopally:BAAANQAECgEIAgABNQAECgkJFgARAPYgAA==.Mantheon:BAAANQAECgEIAQAAAA==.Marvel:BAAANQAECggIEwAAAA==.Matak:BAAANQADCgcIBwAAAA==.Maybedos:BAAANQADCgYIDAAAAA==.Mayuki:BAABNQAECoEaAAIEAAgJ6CSEAQBfAwAEAAgJ6CSEAQBfAwAAAA==.',
Me='Melmard:BAAANQABCgMIBAAAAA==.Meowfurion:BAAANQADCgIIAgAAAA==.Mezzocleeze:BAAANQAECgQIBAABNQAECgQICAABAAAAAA==.',
Mi='Miquella:BAAANQADCggICAABNQAECgUIBQABAAAAAA==.Mirrari:BAAANQAECgEIAQAAAA==.Misschill:BAAANQADCgMIAwAAAA==.Missdumpling:BAAANQADCgIIAgAAAA==.',
Mo='Mogin:BAABNQAECoEXAAICAAkJNBxzDAACAwACAAkJNBxzDAACAwAAAA==.Molten:BAAANQAECgEIAQAAAA==.Morganite:BAAANQADCgMIAwAAAA==.Moronica:BAAANQADCggIEAAAAA==.',
Mu='Muehpera:BAAANQAECgUICAAAAA==.Muya:BAAANQADCgYIBgAAAA==.',
My='Myrabeth:BAAANQADCgYICAAAAA==.',
Na='Nadion:BAAANQADCgQICwAAAA==.Naldon:BAAANQADCgUICQAAAA==.Naraine:BAAANQADCgYICAAAAA==.Nayhture:BAAANQADCgEIAQAAAA==.',
Ne='Nefka:BAAANQADCgYIBgAAAA==.Nefkhet:BAAANQADCgUICAAAAA==.Nephtyys:BAAANQAECgQIBwAAAA==.Nerfbat:BAAANQAECgIIAgAAAA==.Nes:BAAANQAECgEIAQAAAA==.',
Ni='Niavy:BAAANQAECgQIBAAAAA==.Nightgecko:BAAANQAECgcIDwAAAA==.Nightshaded:BAAANQABCgYICAAAAA==.Nihavoker:BAAANQADCgUIBQAAAA==.Nineteen:BAAANQAFFAEIAQABNQAECgMIAwABAAAAAA==.Nisroth:BAAANQAECgMIAwAAAA==.Nitro:BAAANQAECgUIBQAAAA==.Niávy:BAAANQAECgIIAgAAAA==.',
Nm='Nmandragoran:BAAANQAECgEIAQAAAA==.',
No='Noedos:BAAANQAECgMIAwAAAA==.Nofoxgivn:BAAANQAECgEIAQAAAA==.Nogdem:BAAANQAECgMIAwAAAA==.Novaprime:BAAANQAECgIIBAAAAA==.Noyy:BAAANQADCgUIBAABNQADCgYIBgABAAAAAA==.',
Ob='Obeevoker:BAAANQAECgMIBAAAAA==.',
Oc='Ocala:BAAANQADCgMIAwAAAA==.',
Og='Ogryn:BAAANQADCgMIAwAAAA==.',
Om='Omgsogoth:BAAANQABCgEIAQAAAA==.',
Or='Orziver:BAAANQABCgIIAgAAAA==.',
Os='Ostï:BAAANQADCgYIBgABNQAECgcIDgABAAAAAA==.',
Ot='Otosan:BAABNQAECoEXAAICAAcJzBinKAAkAgACAAcJzBinKAAkAgAAAA==.',
Pa='Palshi:BAAANQADCgMIAwABNQAECgIIAwABAAAAAA==.Pandariock:BAAANQAECgMIBAAAAA==.Parfait:BAAANQADCgYIBgAAAA==.Pawsatyou:BAAANQAECgQIBAAAAA==.',
Pe='Peachiekeen:BAAANQADCgcIEwAAAA==.Peekãboo:BAABNQAECoEgAAISAAkJ8xyCBAAeAwASAAkJ8xyCBAAeAwAAAA==.Peewheewoo:BAAANQADCgYIDwAAAA==.Peliossa:BAAANQADCgYIBgAAAA==.Pelzy:BAAANQAECgQIBQAAAA==.Pepae:BAAANQAECgcIEAAAAA==.',
Ph='Pholia:BAAANQADCgcIGAAAAA==.',
Pi='Pieni:BAAANQADCgYIDwAAAA==.Pinkrose:BAAANQADCggIEgAAAA==.Pizza:BAAANQAECgIIAwAAAA==.',
Pl='Platomatrixx:BAAANQADCgYICwAAAA==.',
Po='Pollyanna:BAAANQADCggICwAAAA==.Poony:BAAANQAECgYIEAABNQAECgkJGwAMAJQiAA==.',
Pr='Proximus:BAAANQAECgEIAQABNQAECgYIDAABAAAAAA==.',
Ps='Psyop:BAAANQAECggIDwAAAA==.',
Pu='Punnyname:BAAANQAECgUICgAAAA==.Purrsian:BAAANQAECgQIBAAAAA==.',
Qb='Qberks:BAAANQAECgcIDAAAAA==.',
Qu='Quaddh:BAAANQADCggIDAAAAA==.Quellif:BAAANQABCgYICAAAAA==.Quincee:BAAANQADCggICgAAAA==.',
Ra='Raenin:BAAANQAECgIIAwAAAA==.Ragingdraem:BAAANQAECgYIDQAAAA==.Raidei:BAAANQAECgUICwAAAA==.Rainoffur:BAAANQAECgQIBQAAAA==.Rakeripwait:BAAANQADCgUIBQAAAA==.Raoulqc:BAAANQADCgcIBwAAAA==.Ratatosk:BAAANQAECgEIAgAAAA==.Rathan:BAAANQAECgQICQAAAA==.Ravenanarchy:BAAANQAECgcIDwAAAA==.Rawheadrexx:BAAANQABCgIIAgAAAA==.',
Re='Redpawedfox:BAAANQAECgQICQAAAA==.Rekviem:BAAANQAECgIIBAAAAQ==.Remyz:BAAANQADCgUIBQAAAA==.Revie:BAAANQADCgQIBAABNQAECgkJGAAMAKojAA==.',
Ri='Rielexia:BAAANQABCgYIBgAAAA==.Rikola:BAAANQADCgcIBgAAAA==.Rizzen:BAAANQADCggIDgAAAA==.',
Ro='Roderika:BAAANQAECgEIAQAAAA==.Rogmar:BAAANQABCgIIAgAAAA==.Royalnewb:BAABNQAECoEeAAMIAAgJuxxRAwBgAgAIAAgJbBxRAwBgAgAMAAgJ/Q+bZwAQAgAAAA==.Royston:BAAANQAECgQICQAAAA==.',
Ru='Rucereal:BAAANQAECgQIBwAAAA==.Rufous:BAAANQAECgQICAAAAA==.',
Rw='Rwaga:BAAANQAECgIIAgAAAA==.',
Ry='Ryliea:BAAANQADCgMIAwAAAA==.Rynsidious:BAAANQAECgYIDwAAAA==.',
['Rã']='Rãin:BAAANQAECgMIAwABNQAECgUIDAABAAAAAA==.',
['Rì']='Rìkú:BAAANQADCgUIBQAAAA==.',
Sa='Sabelle:BAAANQADCggIGgAAAA==.Sableanne:BAAANQABCgYICwAAAA==.Sabîne:BAAANQAECgQICQAAAA==.Saeton:BAAANQAECgcIDwAAAA==.Sahlaris:BAAANQAECgMIAwAAAA==.Salno:BAAANQADCgQIBAAAAA==.Samsonite:BAABNQAECoEWAAIDAAgJohcUIgB+AgADAAgJohcUIgB+AgAAAA==.Sanji:BAAANQADCgIIAgAAAA==.Sargerik:BAEANQABCgIIAgAAAA==.Sariths:BAAANQABCggIDAAAAA==.Savreen:BAAANQADCgYIBgAAAA==.',
Sc='Scrubpal:BAAANQADCggIFAAAAA==.',
Se='Sekhmet:BAAANQADCgMIAwAAAA==.Sekstrasza:BAAANQADCgMIAwAAAA==.Sens:BAAANQADCgcICgAAAA==.Serrik:BAAANQAECggIBQAAAA==.Sersilkyhair:BAAANQAECgQICAAAAA==.',
Sh='Shamanoid:BAAANQADCgYICwABNQAECgQIBQABAAAAAA==.Shasta:BAAANQAECgQICQAAAA==.Shortmark:BAAANQADCggIDgAAAA==.Shozwar:BAAANQAECgYIDQAAAA==.',
Si='Siik:BAAANQAECgcICwAAAA==.Silaena:BAAANQAECgIIAgAAAA==.Silverlocke:BAAANQAECgQICAAAAA==.Sindaris:BAAANQADCgMIAwABNQAECgYICgABAAAAAA==.',
Sj='Sj:BAAANQADCgQIBAAAAA==.',
Sk='Skillcrusade:BAAANQADCggIDwAAAA==.Skillscales:BAABNQAECoEgAAMTAAkJsCCCAQAlAwATAAkJFB+CAQAlAwAUAAgJiyFWBgDSAgAAAA==.Skyfallen:BAAANQAECgIIAgAAAA==.',
Sl='Sleepydk:BAAANQAECgYICQAAAA==.Slopysecondz:BAAANQAECgEIAQABNQAECgQICAABAAAAAA==.Slovik:BAAANQAECgEIAgAAAA==.Slowbro:BAAANQADCgYIDwAAAA==.',
Sm='Smok:BAAANQAECgIIAgAAAA==.',
Sn='Snafflo:BAAANQADCgIIAgAAAA==.Snekhet:BAAANQAECgQICQAAAA==.',
So='Softscars:BAAANQAECgIIAwAAAA==.Solanea:BAAANQAECgIIAwAAAA==.Solaura:BAAANQAECgEIAQAAAA==.Solo:BAAANQADCgMIAwABNQAECgUIDwABAAAAAA==.Sorcero:BAAANQAECgIIAgAAAA==.Sorcforce:BAAANQADCgUIBQAAAA==.Soultelage:BAAANQADCgcIEwAAAA==.Sourwine:BAAANQADCgYICQAAAA==.',
Sp='Spaceman:BAABNQAECoElAAIVAAkJdyVAAgDbAwAVAAkJdyVAAgDbAwAAAA==.Spire:BAAANQADCggIKAAAAA==.Sporkeh:BAAANQADCgMIAwAAAA==.Spritemonk:BAAANQAECgQICgABNQAECgUICQABAAAAAA==.Spritepally:BAAANQAECgUICQAAAA==.',
St='Stellara:BAAANQADCgQIBwAAAA==.Stiffmcgee:BAAANQAECgIIAgAAAA==.Stormdancer:BAABNQAECoEYAAIQAAcJuhklCQBLAgAQAAcJuhklCQBLAgAAAA==.Stormpage:BAAANQAECgIIAwAAAA==.Strangiatie:BAAANQADCgEIAQAAAA==.Strych:BAAANQAECgQIBAABNQAECggIFwASAMYdAA==.Stumpyfoot:BAAANQAECgYICQAAAA==.Stygi:BAAANQAECgEIAQAAAA==.Stárling:BAAANQAECgYIDgAAAA==.Stãrs:BAABNQAECoEgAAMWAAkJ5iHmBwBcAwAWAAkJ5iHmBwBcAwALAAEJ3gb+QQAsAAAAAA==.',
Su='Suki:BAAANQADCggICwAAAA==.Surfacing:BAAANQAECgcIEAAAAA==.',
Sy='Syntharia:BAAANQAECgYIDgAAAA==.',
Ta='Taffigosa:BAAANQAECgQIBgAAAA==.Taffy:BAAANQADCgMIAwAAAA==.Tanthel:BAAANQAECgMIBgAAAA==.Taursain:BAAANQADCgYIBwAAAA==.',
Tb='Tbh:BAAANQAECgEIAQAAAA==.',
Te='Terranteal:BAAANQAECgMIAwAAAA==.Terraquis:BAAANQAECgIIAgAAAA==.Terravolta:BAAANQAECgcIDgAAAA==.Testarossa:BAAANQAECgYICQAAAA==.',
Th='Themage:BAAANQADCgQIBAABNQAECgIIBAABAAAAAA==.Therealvenat:BAAANQAECgQICQAAAA==.Thiccbiddies:BAAANQAECgMICAAAAA==.Thort:BAAANQADCgQIBAAAAA==.Thunderwings:BAAANQAECgEIAQAAAA==.',
Ti='Tigan:BAAANQAECgQIBgAAAA==.Tigra:BAAANQAECgYIDQAAAA==.Timelord:BAAANQAECgUIBwAAAA==.Timeweaver:BAAANQAECgcIDwAAAA==.Tirione:BAAANQAECgIIBQAAAA==.Tirogue:BAAANQADCgUIBgAAAA==.',
To='Toastshark:BAAANQAECgYICQAAAA==.Toranaar:BAAANQADCggIDgAAAA==.Torpal:BAAANQADCgUICAABNQAECgQICQABAAAAAA==.Totorö:BAAANQAECgUIDAAAAA==.Tova:BAAANQADCgcIDgAAAA==.',
Tr='Traiturner:BAAANQAECgQICAAAAA==.Trayfu:BAAANQADCggIGgAAAA==.Trice:BAAANQAECgQIDAAAAA==.Trillion:BAAANQAECgQICQAAAA==.Trostani:BAAANQAECgYIBQAAAA==.Truc:BAAANQADCgMIAwAAAA==.Trusker:BAAANQAECgQIBgAAAA==.',
Ts='Tsaavas:BAAANQAECgMIBgAAAA==.Tsereya:BAAANQADCgYIBgAAAA==.Tsugumomo:BAAANQADCggICAAAAA==.',
Tu='Tullandil:BAAANQABCgQIAgAAAA==.',
Tw='Twitty:BAAANQAECgMIBAABNQAECgkJGwAFAAkbAA==.',
Ty='Tyloestus:BAAANQAECgEIAQAAAA==.Tyragni:BAAANQAECgEIAQAAAA==.Tyravana:BAAANQADCgYIBgAAAA==.Tystriel:BAAANQAECgMIBAAAAA==.',
['Tí']='Tíamat:BAAANQAECgIIAgAAAA==.',
Ul='Ulasar:BAAANQADCgcIFAAAAA==.',
Un='Unmilkable:BAAANQADCgUIBQAAAA==.Untarot:BAAANQADCgIIAgAAAA==.',
Va='Valdanyr:BAEANQAECgEIAQAAAA==.Vallenar:BAAANQAECgEIAQAAAA==.Valliant:BAAANQAECgIIAgAAAA==.Valnullis:BAAANQADCgUIBwAAAA==.Valorfist:BAAANQADCgQIBAAAAA==.Valídus:BAAANQADCgYICgAAAA==.Vampteabag:BAAANQADCggIDQAAAA==.Vanden:BAAANQAECgMIBAABNQAECgYIBgABAAAAAA==.Varsi:BAABNQAECoEcAAQDAAkJGR8+EAD2AgADAAgJXSI+EAD2AgAXAAEJUwqwCwA4AAAYAAEJ9QRPTAA4AAAAAA==.',
Ve='Veetor:BAAANQAECgMIBgAAAA==.Velash:BAAANQAECgMIBgAAAA==.Vendorin:BAAANQAECgEIAQAAAA==.Verratanikto:BAAANQAECgYIBQAAAA==.Verwínd:BAAANQAECgUIBgAAAA==.',
Vi='Virusgt:BAAANQADCgcIBwAAAA==.Vitner:BAAANQAECgcICgABNQAECggICAABAAAAAA==.',
Vo='Voidbeam:BAAANQAECgEIAQAAAA==.Voidsta:BAAANQADCgIIAgAAAA==.Volgur:BAAANQADCggIHwAAAA==.Volker:BAAANQAECgQICQAAAA==.',
We='Wenotknow:BAAANQAECgYIEQAAAA==.',
Wi='Wife:BAAANQAECgUIDwAAAA==.Wildraubtier:BAAANQADCgIIAgAAAA==.',
Wo='Wormsloe:BAAANQADCgYIBgAAAA==.',
Xa='Xaida:BAAANQAECgQICQAAAA==.Xaldania:BAAANQADCgMIBgAAAA==.',
Xc='Xcaps:BAAANQADCgcIBwAAAA==.',
Xu='Xuing:BAAANQAECgcIDgAAAA==.Xuingg:BAAANQADCgYIBgABNQAECgcIDgABAAAAAA==.',
Ya='Yarp:BAAANQADCgUIBQAAAA==.Yarro:BAAANQAECgYIDQAAAA==.',
Ye='Yesdaddy:BAAANQADCgcIGQAAAA==.',
Yo='Yorozu:BAAANQAECgQIBQAAAA==.Young:BAAANQADCgQICAABNQAECgcICwABAAAAAA==.Youngblud:BAAANQAECgcICwAAAA==.Youngplasma:BAAANQADCgYIEQABNQAECgcICwABAAAAAA==.Yourhealor:BAAANQADCgYIBgAAAA==.',
Yu='Yuairi:BAAANQAECgQIBQAAAA==.Yugi:BAAANQAECgYICgAAAA==.',
Za='Zaela:BAAANQADCgQIBAAAAA==.Zahira:BAAANQAECgQICQAAAA==.Zax:BAAANQAECgIIAgAAAA==.',
Ze='Zenatra:BAAANQADCgYICwAAAA==.Zeroximo:BAAANQAECgYIDwAAAA==.',
Zi='Zieren:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Zipline:BAAANQAECgUICQAAAA==.Zirathiel:BAAANQADCgYICAABNQADCggIDAABAAAAAA==.',
Zo='Zofie:BAAANQADCgYIBgAAAA==.Zogz:BAAANQAECgUIBgAAAA==.Zombiexcat:BAAANQADCgEIAQAAAA==.Zorakiel:BAAANQAECgUICgAAAA==.',
Zw='Zwiebelle:BAAANQAECgQICQAAAA==.',
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
