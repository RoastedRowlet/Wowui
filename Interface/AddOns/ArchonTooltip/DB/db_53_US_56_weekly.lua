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
local provider = {region='US',realm='Daggerspine',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aamara:BAAANQAECgEIAgAAAA==.',
Ad='Adhpally:BAAANQADCgIIAgAAAA==.',
Ae='Aefarshammy:BAAANQAECgQIBAAAAA==.Aerithorn:BAAANQAECgMIBQAAAA==.',
Ah='Ahleya:BAAANQAECgIIAgAAAA==.Ahlonaa:BAAANQADCgYIBgAAAA==.',
Ai='Airundies:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Ak='Akoris:BAAANQADCgMIAwABNQAECgMIAwABAAAAAA==.Akorys:BAAANQAECgMIAwAAAA==.',
Al='Albyno:BAAANQAECgUICQAAAA==.',
Am='Amara:BAAANQADCgMIBAAAAA==.Ameadynnie:BAAANQABCgIIAgAAAA==.',
An='Anchint:BAAANQADCgYICAAAAA==.Anuurg:BAAANQADCgIIAgAAAA==.Anwir:BAAANQAECgIIAgAAAA==.',
Aq='Aquua:BAAANQADCggIDwAAAA==.',
Ar='Arcticdps:BAAANQAECgQIBAAAAA==.Ariell:BAAANQAECgQIBQAAAA==.Ariestar:BAAANQADCgMIAgAAAA==.Ariiel:BAAANQADCggICQABNQAECgQIBQABAAAAAA==.Arthimas:BAAANQADCgYICQAAAA==.Arthurdent:BAAANQAECgMIBQAAAA==.',
As='Ascendance:BAAANQADCgYICAAAAA==.Ashelash:BAAANQADCgUICgAAAA==.Asidize:BAAANQADCgYICAAAAA==.Aslor:BAAANQAECgEIAQAAAA==.Aspenoa:BAAANQADCggICAAAAA==.',
At='Athaisce:BAAANQAECgQIBQAAAA==.Athalia:BAAANQAECgQIBQAAAA==.Atlaswolfe:BAAANQADCgYICAAAAA==.',
Au='Aug:BAAANQADCgYIBgAAAA==.',
Av='Avex:BAAANQADCggIDgAAAA==.',
Ax='Axemage:BAAANQAECgQIBQAAAA==.Axeom:BAAANQAECgQIBwAAAA==.',
Az='Azzith:BAAANQADCgcIBwAAAA==.',
Ba='Bajaladin:BAAANQAECgIIAgAAAA==.Barometer:BAAANQAECgEIAQAAAA==.Baylee:BAAANQAECgIIAgAAAA==.',
Be='Bearvul:BAAANQABCgEIAQAAAA==.Belbroon:BAAANQADCgQIBAAAAA==.Benjohnbo:BAAANQABCgEIAQAAAA==.Benwins:BAAANQADCggIDgAAAA==.Bergamö:BAAANQADCgcICQAAAA==.Bernecessity:BAAANQADCgYIBgAAAA==.',
Bi='Biffedit:BAAANQADCgcIBwAAAA==.Biscuitbabe:BAAANQADCggIDwAAAA==.Bisholoyd:BAAANQADCgUICQAAAA==.',
Bl='Blackgold:BAAANQADCgQIBAAAAA==.Blakely:BAAANQABCgQIBAAAAA==.Blastoise:BAAANQAECgQIBAAAAA==.',
Bo='Boostia:BAAANQADCgEIAQAAAA==.Borthos:BAAANQADCggICAAAAA==.Bowsback:BAAANQADCgYICgAAAA==.',
Br='Brandoe:BAAANQADCgYIBgAAAA==.Breece:BAAANQADCgQIBAAAAA==.Brickinkeys:BAAANQADCgYIBgABNQAECgEIAgABAAAAAA==.Brightmare:BAAANQADCgUIBQAAAA==.Brynnix:BAAANQADCgEIAQAAAA==.',
['Bà']='Bàne:BAAANQADCgYIBgAAAA==.',
Ca='Caimie:BAAANQADCgYICwAAAA==.Calfionn:BAAANQADCgIIAgAAAA==.Candez:BAAANQADCgUIBQAAAA==.Canroth:BAAANQADCggIDAAAAA==.Cassiaan:BAAANQADCgQIBAAAAA==.Caylavibes:BAAANQAECgQIBQAAAA==.',
Ch='Cherry:BAAANQADCggICAAAAA==.Chironn:BAAANQAECgEIAQAAAA==.Chull:BAAANQADCgIIAgAAAA==.Chumbo:BAAANQADCgcIDAAAAA==.',
Ci='Cinderburn:BAAANQADCgUIBQAAAA==.Cinderkai:BAAANQADCgEIAQAAAA==.',
Cl='Clayshaper:BAAANQADCgIIAgAAAA==.Clohhe:BAAANQADCgYIDQAAAA==.Clwnshoenrgy:BAAANQADCgYIBgAAAA==.',
Co='Combust:BAAANQADCgEIAQAAAA==.Coowmoo:BAAANQADCgYICAAAAA==.Cosmochopper:BAAANQAECgEIAQABNQADCgcICAABAAAAAA==.Cosmoshotter:BAAANQADCgcICAAAAA==.',
Cr='Cremebrule:BAAANQADCgQIBgAAAA==.Critnyspears:BAAANQADCgUIBQAAAA==.Crushleaf:BAAANQADCgMIAwAAAA==.',
Cy='Cyndra:BAAANQADCgIIAgAAAA==.',
Da='Dagdenth:BAAANQADCgEIAQAAAA==.Dallthyrian:BAAANQADCgYIBgABNQADCgcIDQABAAAAAA==.Dalthyriian:BAAANQADCgcIDQAAAA==.Dalthyrrian:BAAANQADCgIIAgABNQADCgcIDQABAAAAAA==.Dalthyyrian:BAAANQADCgQIBQABNQADCgcIDQABAAAAAA==.Damii:BAAANQADCgEIAQAAAA==.Darjen:BAAANQADCgQICAAAAA==.Daysmonk:BAAANQADCgYIBgAAAA==.',
Dc='Dcash:BAAANQADCgIIAgAAAA==.',
De='Deathfang:BAAANQADCgQIBQAAAA==.Deathlyy:BAAANQAECgEIAQAAAA==.Deathmatch:BAAANQAECgEIAQAAAA==.Deathstone:BAAANQADCgUIBgABNQAECgYIDAABAAAAAA==.Deathtress:BAAANQADCggIEAAAAA==.Debbydowner:BAAANQAECgIIAgAAAA==.Decado:BAAANQAECgIIAgAAAA==.Deemwins:BAAANQADCgYIBwAAAA==.Deezenuts:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Demonroo:BAAANQADCgEIAQAAAA==.Denimdan:BAEANQAECgIIAwAAAA==.Denwere:BAAANQADCgMIAwAAAA==.',
Dh='Dhawk:BAAANQADCgcIDAAAAA==.Dhelilha:BAAANQABCgEIAQAAAA==.',
Dk='Dkalliru:BAAANQADCggIDwAAAA==.',
Do='Docdolittle:BAAANQAECgQIBAAAAA==.Docfreez:BAAANQAECgQIBQAAAA==.Docragosa:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Doraemee:BAAANQADCgYICgAAAA==.',
Dr='Drbaconbrgr:BAAANQADCggICAABNQAECgMIBAABAAAAAA==.Drbaobuns:BAAANQADCgYICgABNQAECgMIBAABAAAAAA==.Drgatorwine:BAAANQADCgUIBQABNQAECgMIBAABAAAAAA==.Drkimchirice:BAAANQAECgQIBQABNQAECgMIBAABAAAAAA==.Drmacncheese:BAAANQADCggIDQABNQAECgMIBAABAAAAAA==.Drpumpkinpie:BAAANQADCgcIDQABNQAECgMIBAABAAAAAA==.Drshephardpi:BAAANQADCggICgABNQAECgMIBAABAAAAAA==.Druiddres:BAAANQADCgYIDAAAAA==.Druidussy:BAAANQADCggICAAAAA==.Drwontonsoup:BAAANQAECgMIBAAAAA==.',
Du='Dummythicc:BAAANQADCgQIBAAAAA==.',
Ei='Eighteen:BAAANQAECgEIAQAAAA==.',
Ek='Eksi:BAAANQADCgcIBwAAAA==.',
El='Elethe:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Elzaine:BAAANQAECgIIAgAAAA==.',
Em='Embedded:BAAANQADCgYICAAAAA==.Empress:BAAANQADCgYIDAAAAA==.',
En='Endear:BAAANQADCggIBgAAAA==.Energyz:BAAANQADCgMIAwABNQAECgIIBAABAAAAAA==.Entrophi:BAAANQADCgMIAwAAAA==.',
Er='Erisnyx:BAAANQADCgIIAgAAAA==.',
Es='Esterelore:BAAANQADCgYIBgAAAA==.Estix:BAAANQAECgEIAQABNQAECgIIBAABAAAAAA==.',
Ex='Excruciator:BAAANQAECgEIAQAAAA==.',
Fa='Falloutz:BAAANQADCgUICgAAAA==.Farahcanle:BAAANQAECgEIAgAAAA==.',
Fe='Felystia:BAAANQADCgYIIAAAAA==.Feorblarir:BAAANQADCgcICwAAAA==.Fernmister:BAAANQAECgEIAQAAAA==.',
Fi='Filledegel:BAAANQAECgEIAQAAAA==.Finowscath:BAAANQADCgYIBgAAAA==.Firequencher:BAAANQAECgIIAgAAAA==.Fistacuffs:BAAANQADCgEIAQAAAA==.Fistdoc:BAAANQAECgEIAQAAAA==.Fistícuffs:BAAANQADCgUIDQAAAA==.Fizzroll:BAAANQADCgQIBwAAAA==.',
Fl='Flais:BAAANQADCgQICAAAAA==.Fleetwoodmac:BAAANQADCgYIBgAAAA==.',
Fo='Foxfel:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.',
Fr='Friendlypal:BAAANQAECgEIAQAAAA==.Friendofbear:BAAANQAECgUICQAAAA==.',
Fu='Furryfeet:BAAANQADCgcIBwAAAA==.Fuzywuzzy:BAAANQADCgcIDAAAAA==.Fuzzykuntz:BAAANQAECgIIAgAAAA==.',
Fy='Fynsdood:BAAANQADCgcIDAAAAA==.',
Ga='Gabelock:BAAANQAECgYICgAAAA==.Gala:BAAANQADCgcICQAAAA==.Gasback:BAAANQADCgYIBgAAAA==.',
Gh='Gherkins:BAAANQADCgQIBAAAAA==.Ghostreveri:BAAANQADCggIDAAAAA==.',
Gi='Gigah:BAAANQADCgcIDAAAAA==.Gingercool:BAAANQADCgUIBQAAAA==.',
Gl='Glitsch:BAAANQADCgQIBAAAAA==.Glorpnotl:BAAANQADCgYIBgAAAA==.Gloziwitz:BAAANQADCggICAAAAA==.Glutebruiser:BAAANQADCgMIAwABNQADCgMIBQABAAAAAA==.',
Gn='Gnomedguerre:BAAANQADCgYIBgAAAA==.',
Go='Gooseshift:BAAANQADCgMIAgAAAA==.Gouchh:BAAANQAECgEIAQAAAA==.',
Gr='Gravithel:BAAANQADCgUIBgAAAA==.Grayseer:BAAANQAECgQIBAAAAA==.Grimtree:BAAANQAECgEIAQAAAA==.Grumpstraza:BAAANQADCgYIBgAAAA==.Grumpydemon:BAAANQAECgMIAwAAAA==.',
Ha='Halfskul:BAAANQAECgcIDgAAAA==.Hashah:BAAANQAECgIIAgAAAA==.Hatefel:BAAANQADCgEIAQABNQADCgYICwABAAAAAA==.',
He='Healsgobrr:BAAANQADCgUIBQABNQAECgYIBwABAAAAAA==.Helenfeller:BAAANQADCgEIAwAAAA==.Helgard:BAAANQADCgQIBAAAAA==.Hesha:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Hexlexxia:BAAANQADCgcIBwABNQAECgEIAgABAAAAAA==.Heyyboyy:BAAANQAECgEIAQAAAA==.',
Ho='Holyyaii:BAAANQADCgEIAgAAAA==.Holz:BAAANQADCgQIBQAAAA==.',
Hu='Hugoman:BAAANQADCgUIBgABNQAECgIIAwABAAAAAA==.Huni:BAAANQAECgQIBAAAAA==.',
Hy='Hystaric:BAAANQADCgUIBgAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgEIAQAAAA==.',
Ib='Ibun:BAAANQADCgMIAwAAAA==.',
Ic='Icentheveins:BAAANQAECgQIBwAAAA==.',
Ig='Igneus:BAAANQAECgQIBAAAAA==.Igriz:BAAANQADCgcICQAAAA==.',
Ii='Iillil:BAAANQAECgQIBQAAAA==.',
Il='Ilvinabox:BAAANQADCgQIBAAAAA==.',
Im='Immamoonchix:BAAANQADCgEIAQAAAA==.Imtheworst:BAAANQADCgIIAgAAAA==.Imzaiahx:BAAANQADCgEIAQAAAA==.',
Ir='Irodina:BAAANQADCgUICgAAAA==.',
It='Itsjeff:BAAANQADCgUICAAAAA==.',
Iz='Izyel:BAAANQADCgEIAQAAAA==.',
Ja='Jaeyk:BAAANQADCggIDwAAAA==.Jambonjay:BAAANQAECgEIAQAAAA==.Jarnirdimli:BAAANQABCgQIBwAAAA==.',
Jc='Jckjck:BAAANQADCgIIAgAAAA==.Jckjckjck:BAAANQADCgUIBQAAAA==.',
Je='Jermagedupri:BAAANQAECggIEAAAAA==.Jessupy:BAAANQADCggICAAAAA==.',
Jo='Johkneesinz:BAAANQADCgYIBgAAAA==.',
Ju='Junkbot:BAAANQADCgYICgAAAA==.Justiz:BAAANQADCgYIBgAAAA==.',
Ka='Kalrendion:BAAANQADCgEIAQABNQADCgcIDAABAAAAAA==.Karaillyonna:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Karasu:BAAANQADCgQIBQAAAA==.Karicxis:BAAANQADCgQIBAAAAA==.Kasher:BAAANQADCgMIBQAAAA==.Kayho:BAAANQADCgcIDQAAAA==.',
Ke='Kelltrax:BAAANQADCgcICAAAAA==.Kelsier:BAAANQAECgMIBAAAAA==.Kesk:BAAANQADCgMIAwAAAA==.',
Kh='Khaster:BAAANQABCgEIAQAAAA==.Khendra:BAAANQADCgYIBwAAAA==.',
Ki='Killachefd:BAAANQAECgEIAQAAAA==.Killamanjoro:BAAANQAECgUICAAAAA==.Kimchiwar:BAAANQADCgcIBwAAAA==.Kirasha:BAAANQADCgUICQAAAA==.Kitak:BAAANQADCgcIDAAAAA==.Kitchenbound:BAAANQADCggIDgAAAA==.Kittychan:BAAANQAECgIIAwAAAA==.',
Kl='Klaacus:BAAANQAECgQIBwAAAA==.',
Ko='Koudelka:BAAANQAECgIIAgAAAA==.',
Kr='Kralok:BAAANQADCgYIBgAAAA==.Krazm:BAAANQADCgMIAwAAAA==.Kriticál:BAAANQAECgIIAgAAAA==.Krustyg:BAAANQADCgYIBgAAAA==.',
Ku='Kuurun:BAEANQADCgcIBwABNQAECgYICwABAAAAAA==.',
La='Lakshmi:BAAANQADCgcIDAABNQAECgEIAgABAAAAAA==.Larndorn:BAAANQADCgMIAwAAAA==.',
Le='Lelou:BAAANQAECgcIDQAAAA==.Lewsky:BAAANQAECgEIAQABNQAECgcIDAABAAAAAA==.',
Li='Lilathiaa:BAAANQADCgYIBgAAAA==.Limpairrow:BAAANQADCggIDgAAAA==.Linddria:BAAANQADCggIDQAAAA==.Liondori:BAAANQADCgYIBgAAAA==.Lipspire:BAAANQABCgQIBAAAAA==.Lissarael:BAAANQADCgcIBwAAAA==.',
Lm='Lmj:BAAANQAECgEIAQAAAA==.',
Lo='Lockbox:BAAANQAECgQIBQAAAA==.Loomin:BAAANQAECgcICwAAAA==.',
Lu='Lucatia:BAAANQAECgIIAgAAAA==.Lumièrevide:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Lunastitch:BAAANQADCgEIAQAAAA==.Lunna:BAAANQADCgMIAwAAAA==.',
['Lä']='Lädyæk:BAAANQAECgIIAgAAAA==.',
Ma='Maekyss:BAAANQADCgQIBAAAAA==.Magezu:BAAANQAECgEIAQAAAA==.Magixstraza:BAAANQAECgQIBQAAAA==.Mahmba:BAAANQAECgQIBAAAAA==.Malzel:BAAANQADCgcIDAAAAA==.Mamasan:BAAANQADCgcIDAAAAA==.Maphra:BAAANQADCgMIAwAAAA==.Marvindent:BAAANQADCgYIBgAAAA==.',
Me='Mechabull:BAAANQABCgIIAgAAAA==.Meleemeal:BAAANQADCgYIBgAAAA==.Menoheal:BAAANQADCgMIAwAAAA==.Merope:BAAANQADCgUIBQAAAA==.Mertence:BAAANQADCgYICgAAAA==.Mexicanbrick:BAAANQADCgEIAQAAAA==.',
Mh='Mheow:BAAANQADCgYICgAAAA==.',
Mi='Mikuu:BAAANQADCgUICgAAAA==.Mistical:BAAANQADCggICAAAAA==.Mitufu:BAAANQADCgQIBQAAAA==.',
Mo='Morganya:BAAANQAECgQIBQAAAA==.Morgul:BAAANQADCgcIBwAAAA==.Morrtis:BAAANQADCgYIDQAAAA==.',
Ms='Mseow:BAAANQADCgUICAAAAA==.',
Mu='Mudbutbrooks:BAAANQAECgIIAgAAAA==.Muller:BAAANQAECgEIAQAAAA==.',
My='Mynnu:BAAANQADCgcIFQAAAA==.Mynthara:BAAANQADCggIAgAAAA==.',
Ne='Neildasstysn:BAAANQAECgMIAwAAAA==.Nemezyz:BAAANQADCgQIBAAAAA==.Nephey:BAAANQADCgMIAwAAAA==.Neveya:BAAANQADCgMIAwAAAA==.',
Ni='Nickeld:BAAANQAECgEIAQAAAA==.Nickhy:BAAANQADCgYICQAAAA==.Nietherme:BAAANQADCgcIDQAAAA==.',
No='Noblefiend:BAAANQADCgQIBAAAAA==.Norinithedra:BAAANQADCgMIAwAAAA==.',
Ny='Nyagosa:BAAANQADCggICQAAAA==.Nyalore:BAAANQAECgIIAgAAAA==.',
Oh='Ohnjaxx:BAAANQAECgEIAQAAAA==.',
Or='Oraedia:BAAANQADCggIEwAAAA==.Oralen:BAAANQAECgYICQAAAA==.Orilitha:BAAANQADCgYIDAAAAA==.',
Oy='Oyabun:BAAANQADCgYIBgAAAA==.',
Pa='Pairodeez:BAAANQADCgMIAQAAAA==.Pandussi:BAAANQAECgQIBAAAAA==.Paneer:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Paninus:BAAANQAECgEIAQAAAA==.',
Pe='Pebbletoe:BAAANQADCgUIBQAAAA==.Perfectplex:BAAANQABCgQIBAAAAA==.Peruano:BAAANQAECgQIBAAAAA==.Petforheals:BAAANQAECgIIAgAAAA==.',
Ph='Phyett:BAAANQADCgEIAQABNQADCgMIBwABAAAAAA==.',
Pi='Pietastegood:BAAANQAECgQIBAAAAA==.Pikaboom:BAAANQADCgYIBgAAAA==.',
Po='Pocahöntas:BAAANQADCgQIBAAAAA==.Pocketrocket:BAAANQADCgUIBQAAAA==.Ponce:BAAANQAECgUIBwAAAA==.Poordemon:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Pr='Provolonie:BAAANQADCggIDAAAAA==.Pròntò:BAAANQADCgQIBAAAAA==.Prõntõ:BAAANQADCgEIAQABNQADCgMIBAABAAAAAA==.Prøntø:BAAANQAECgIIAgAAAA==.',
Pu='Puffthemagic:BAAANQADCgYICQABNQAECgQIBAABAAAAAA==.Punchbugman:BAAANQADCggIDAAAAA==.Puritos:BAAANQABCgQIBQAAAA==.',
Py='Pyrista:BAAANQADCgcIDAAAAA==.',
Qo='Qortethpally:BAAANQADCgQIBAAAAA==.',
Qu='Quinte:BAEANQABCgQIBAAAAA==.',
Ra='Radetoo:BAAANQADCggICQAAAA==.Raendarth:BAAANQADCgcICAAAAA==.Rageth:BAAANQADCgcIDQAAAA==.Rakalaag:BAEANQADCgUIBQAAAA==.Rakath:BAAANQADCgQICAAAAA==.Ramidus:BAAANQADCgQICAAAAA==.Ranciid:BAAANQADCgIIAwAAAA==.Rasmis:BAAANQAECgUIBQAAAA==.',
Re='Reck:BAAANQAECgQIBAAAAA==.Rektify:BAAANQADCgEIAQAAAA==.Reunach:BAAANQADCggIDAAAAA==.',
Rh='Rhahirn:BAAANQADCgEIAQAAAA==.Rhialto:BAAANQADCgIIAgAAAA==.',
Ri='Riptiide:BAAANQADCgcIBwABNQADCggICwABAAAAAA==.Rivendra:BAAANQADCgcIBwAAAA==.',
Ro='Rockabye:BAAANQADCggIDAAAAA==.Rosannas:BAAANQADCgUIAgABNQAECgQIBQABAAAAAA==.Rosi:BAAANQADCggICAAAAA==.',
Ru='Rudeknees:BAAANQAECgYICwAAAA==.Ruibash:BAEANQAECgYICwAAAA==.Runebladé:BAAANQADCgUIBQAAAA==.',
Ry='Ryuu:BAAANQADCggIDAAAAA==.',
Sa='Saikoumaster:BAAANQADCgcICQAAAA==.Savaged:BAAANQADCgcIDAABNQAECgQIBQABAAAAAA==.Savajed:BAAANQAECgQIBQAAAA==.',
Sc='Scarletmatch:BAAANQAECgIIAgAAAA==.',
Se='Searcomic:BAAANQADCggIDgAAAA==.Seldav:BAAANQAECgYIBwAAAA==.Selessa:BAAANQADCgYIBgAAAA==.Selm:BAAANQAECgEIAQAAAA==.',
Sh='Shadedluster:BAAANQADCgQIBAAAAA==.Shaleka:BAAANQADCgMIAwAAAA==.Shameless:BAAANQADCggIDwAAAA==.Shamwów:BAAANQAECgUIBgAAAA==.Sharco:BAAANQAECgQIBgAAAA==.Sharkbites:BAAANQADCgQIBAAAAA==.Shawarmafury:BAAANQAECgYICgAAAA==.Shirun:BAAANQADCgMIBwAAAA==.Shockadinn:BAAANQAECgMIBgAAAA==.Shooshmael:BAAANQADCggIDgAAAA==.Shékinah:BAAANQAECgQIBAAAAA==.',
Si='Silirazzle:BAAANQADCgMIAwAAAA==.Sinsister:BAAANQADCgYIBgAAAA==.Sinthein:BAAANQADCgYIDAABNQAECgIIAgABAAAAAA==.',
Sk='Skyle:BAAANQADCgQIBAAAAA==.Skypanties:BAAANQAECgEIAQAAAA==.',
Sl='Sleepingsun:BAAANQADCggICAAAAA==.Sloppyspikes:BAAANQAECgIIAgAAAA==.',
Sm='Smakm:BAAANQADCgEIAQAAAA==.Smidgenn:BAAANQADCgYICwAAAA==.Smokyblast:BAAANQADCggIDwAAAA==.Smolden:BAAANQABCgEIAQAAAA==.',
Sn='Snailtrails:BAAANQADCgYICwAAAA==.Snowball:BAAANQAECgQICAAAAA==.',
So='Sonbrandt:BAAANQADCgcIDQAAAA==.Soulforge:BAAANQADCgQIBAAAAA==.Soulread:BAAANQAECgIIAgAAAA==.',
Sp='Sparowprince:BAAANQAECgYIDAAAAA==.Speccurious:BAAANQADCgYIBwAAAA==.Spectraleye:BAAANQADCggICgAAAA==.Sproocherlou:BAAANQADCggIDgAAAA==.Sprour:BAAANQAECgEIAQAAAA==.',
St='Stankbolt:BAAANQADCgMIBQAAAA==.Steezya:BAAANQAECgEIAQAAAA==.Stormykitty:BAAANQAECgQIBAAAAA==.Strongwoman:BAAANQADCgQIBQAAAA==.Sturtza:BAAANQAECgUIBwAAAA==.',
Su='Subarashi:BAAANQADCgYIBgAAAA==.Sukmybigtoe:BAAANQADCgIIAQAAAA==.Suun:BAAANQADCggIDAAAAA==.',
Sw='Swampassuti:BAAANQAECgEIAQAAAA==.Swoley:BAAANQAECgEIAQAAAA==.',
Sy='Syrina:BAAANQADCgEIAQAAAA==.',
Ta='Taelandas:BAAANQADCgEIAQAAAA==.Tagobeets:BAAANQADCggICAAAAA==.Taleiya:BAAANQADCgYIFQAAAA==.Tanisatharae:BAAANQADCgYIDAAAAA==.Tarahse:BAAANQADCgIIAgABNQADCgYICQABAAAAAA==.Taron:BAAANQADCgcICAAAAA==.Tart:BAAANQAECgQIBQABNQAECgYICgABAAAAAA==.',
Te='Tedjones:BAAANQADCgUIBgAAAA==.',
Th='Thehumanatee:BAAANQAECgEIAQAAAA==.Theunholyone:BAAANQADCgcIDQAAAA==.Thilidan:BAAANQADCgEIAQAAAA==.Thingytoo:BAAANQADCgUIBwAAAA==.Thiqq:BAAANQADCggICAAAAA==.Throbinggimp:BAAANQADCgEIAQAAAA==.Thyphlo:BAAANQADCgcIBwAAAA==.',
Ti='Tiltedup:BAAANQAECgQIBgAAAA==.Tinesa:BAAANQADCgQIBQAAAA==.Titaintium:BAAANQAECgQIBAAAAA==.',
To='Toshi:BAAANQADCgIIAgAAAA==.',
Tr='Trustmei:BAAANQADCggIBAAAAA==.Trystin:BAAANQAECgIIAgAAAA==.',
Tu='Tullyy:BAAANQADCgMIAgAAAA==.Tums:BAAANQAECgMIAwAAAA==.',
Tw='Twirls:BAAANQAECgEIAQAAAA==.Twistoffate:BAAANQADCgQICAAAAA==.',
Ty='Tyerant:BAAANQADCgEIAQAAAA==.Tylenill:BAAANQADCgQIBAAAAA==.',
Ug='Uglygoat:BAAANQADCgEIAQAAAA==.',
Um='Umbrasanctus:BAAANQADCgUIBgAAAA==.',
Ur='Urtle:BAAANQADCgcIDAAAAA==.',
Us='Uselece:BAAANQAECgIIAgAAAA==.',
Va='Valgorr:BAAANQADCgYIBgAAAA==.Valvalon:BAAANQADCgYICwAAAA==.',
Ve='Veelaria:BAAANQADCggIDgAAAA==.Vet:BAAANQAECgQIBAAAAA==.',
Vh='Vhelithiana:BAAANQADCgMIBQAAAA==.',
Vi='Vicalaus:BAAANQADCggICwABNQAECgQIBwABAAAAAA==.View:BAAANQAECgIIAgAAAA==.Vikcy:BAAANQADCgYICwAAAA==.Vilified:BAAANQADCgQIBwAAAA==.Vitros:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.',
Vo='Voidbren:BAAANQADCgEIAQABNQADCgcIDAABAAAAAA==.Voidwitch:BAAANQADCgYICwAAAA==.Volstagg:BAAANQADCgMIAwAAAA==.',
Vy='Vyndenus:BAAANQADCgYIBgAAAA==.',
Wa='Warriorluv:BAAANQADCgEIAQAAAA==.',
We='Webbfury:BAAANQADCgcIDAAAAA==.Wespoo:BAAANQAECgMIBQAAAA==.',
Wi='Wigpetval:BAAANQAECgMIAwAAAA==.Wiidge:BAAANQADCgcIDQAAAA==.Wildside:BAAANQADCgUIBwAAAA==.Willregret:BAAANQADCggICAAAAA==.',
Wo='Wocky:BAAANQADCgcICAAAAA==.Worldender:BAAANQADCgQICAAAAA==.',
Xa='Xantry:BAAANQAECgcIDAAAAA==.',
Xy='Xymm:BAAANQADCgEIAQAAAA==.',
Ye='Yeastybush:BAAANQAECgMIAwAAAA==.',
Ys='Yseeraa:BAAANQADCgcICwAAAA==.',
Za='Zalatoes:BAAANQADCggIDgAAAA==.',
Zi='Zilphah:BAAANQADCgIIAgAAAA==.Zimmerwitch:BAAANQADCgYIBgAAAA==.Zimms:BAAANQADCggIEAAAAA==.',
Zo='Zoeyredbird:BAAANQADCgcIDAAAAA==.',
['Ña']='Ñazary:BAAANQABCgIIAgAAAA==.',
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
