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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Mage-Arcane','Hunter-BeastMastery','Hunter-Marksmanship',}
local provider = {region='US',realm='Daggerspine',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aamara:BAAANQAECgEIAwAAAA==.',
Ad='Adhpally:BAAANQADCgIIAgABNQAECggIEwABAAAAAA==.',
Ae='Aefarshammy:BAAANQAECgcICwAAAA==.Aerithorn:BAAANQAECgUICgAAAA==.',
Ah='Ahleya:BAAANQAECgIIAgAAAA==.Ahlonaa:BAAANQADCgYIBgAAAA==.',
Ai='Airundies:BAAANQADCgcIBwABNQAECgEIAgABAAAAAA==.',
Ak='Akoris:BAAANQADCgUIBgABNQAECgMIBAABAAAAAA==.Akorys:BAAANQAECgMIBAAAAA==.',
Al='Albyno:BAAANQAECggIEQAAAA==.',
Am='Amara:BAAANQADCgMIBwAAAA==.Ameadynnie:BAAANQABCgIIAgAAAA==.',
An='Anchint:BAAANQADCgYIDQAAAA==.Andromedia:BAAANQADCgYIBgABNQAECgEIAwABAAAAAA==.Anicarcia:BAAANQADCgQIBAAAAA==.Anuurg:BAAANQADCgIIAgAAAA==.Anwir:BAAANQAFFAEIAQAAAA==.',
Aq='Aquua:BAAANQAECgQIBAAAAA==.',
Ar='Arcticdps:BAAANQAECgUICQAAAA==.Ariell:BAAANQAECgYICwAAAA==.Ariestar:BAAANQADCggICgAAAA==.Ariiel:BAAANQADCggICQABNQAECgYICwABAAAAAA==.Arthimas:BAAANQADCgYICQAAAA==.Arthurdent:BAAANQAECgMIBQAAAA==.',
As='Ascendance:BAAANQADCggICgAAAA==.Ashelash:BAAANQADCgYIEAAAAA==.Asidize:BAAANQADCggICgAAAA==.Aslor:BAAANQAECgMIBAAAAA==.Aspenoa:BAAANQADCggICAAAAA==.',
At='Athaisce:BAAANQAECgQICQAAAA==.Athalia:BAAANQAECgcICwAAAA==.Atlaswolfe:BAAANQADCgYICAAAAA==.',
Au='Aug:BAAANQAECgIIAgAAAA==.',
Av='Avex:BAAANQAECgIIAgAAAA==.Avocadoze:BAAANQABCgIIAgAAAA==.',
Ax='Axemage:BAAANQAECgcIDQAAAA==.Axeom:BAAANQAECgQIDgAAAA==.',
Az='Azmodan:BAAANQAECgEIAQAAAA==.Azzith:BAAANQAECgIIAgAAAA==.',
Ba='Bajaladin:BAAANQAECgMIBAAAAA==.Barometer:BAAANQAECgEIAQAAAA==.Baylee:BAAANQAECgQICAAAAA==.',
Be='Bearaqobama:BAAANQADCgYIBgAAAA==.Bearvul:BAAANQABCgEIAQAAAA==.Beekerr:BAAANQADCgMIAwABNQAECgQIBwABAAAAAA==.Belbroon:BAAANQADCgQIBAAAAA==.Benjohnbo:BAAANQABCgEIAQAAAA==.Benwins:BAAANQAECgEIAQAAAA==.Bergamö:BAAANQADCgcICQABNQAECgIIAwABAAAAAA==.Bernecessity:BAAANQADCgcIDQAAAA==.',
Bi='Biffedit:BAAANQADCgcIBwAAAA==.Biscuitbabe:BAAANQAECgUIBQAAAA==.Bisholoyd:BAAANQADCggIEQAAAA==.',
Bl='Blackgold:BAAANQADCgQIBAAAAA==.Blakely:BAAANQABCgQIBAAAAA==.Blastoise:BAAANQAECgYICgAAAA==.Blizfishleg:BAAANQADCgUIBQAAAA==.Bllur:BAAANQADCgIIAgAAAA==.Bloodroots:BAAANQAECgMIAwAAAA==.',
Bo='Boostia:BAAANQADCgEIAQAAAA==.Borthos:BAAANQAECgMIAwAAAA==.Bowsback:BAAANQADCgYICwAAAA==.',
Br='Brandoe:BAAANQAECgQIBQAAAA==.Breece:BAAANQADCgQIBAAAAA==.Brickinkeys:BAAANQADCgYIBgABNQAECgEIAwABAAAAAA==.Brightmare:BAAANQADCgUIBQAAAA==.Brynnix:BAAANQADCgEIAQAAAA==.',
['Bà']='Bàne:BAAANQAECgQIBAAAAA==.',
Ca='Caadra:BAAANQADCgIIAgAAAA==.Caimie:BAAANQADCgYICwAAAA==.Calfionn:BAAANQADCgIIAgAAAA==.Candez:BAAANQADCgUIBQAAAA==.Canroth:BAAANQADCggIFAAAAA==.Cassiaan:BAAANQADCggIDgAAAA==.Caylavibes:BAAANQAECgYICwAAAA==.',
Ch='Chaviel:BAAANQADCgYIBgAAAA==.Cherry:BAAANQADCggICAAAAA==.Chironn:BAAANQAECgUIBwAAAA==.Chull:BAAANQADCgIIAgAAAA==.Chumbo:BAAANQADCggIFAAAAA==.',
Ci='Cinderburn:BAAANQADCgcIDAAAAA==.Cinderkai:BAAANQADCgEIAQAAAA==.',
Cl='Clayshaper:BAAANQADCgYIBwAAAA==.Clohhe:BAAANQADCggIGgAAAA==.Clwnshoenrgy:BAAANQADCgYIBgAAAA==.',
Co='Combust:BAAANQADCgEIAQAAAA==.Comfychair:BAAANQADCgUIBQAAAA==.Coowmoo:BAAANQADCgYIDgAAAA==.Cosmochopper:BAAANQAECgEIAQABNQADCggIEAABAAAAAA==.Cosmoshotter:BAAANQADCggIEAAAAA==.',
Cr='Craterstab:BAAANQADCgEIAQAAAA==.Cremebrule:BAAANQADCgYIDAAAAA==.Critnyspears:BAAANQAECgIIAgAAAA==.Crushleaf:BAAANQADCgMIAwAAAA==.',
Cy='Cyndra:BAAANQADCgIIAgAAAA==.',
Da='Dallthyrian:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Dalthyriian:BAAANQAECgIIAgAAAA==.Dalthyrrian:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Dalthyyrian:BAAANQADCgQIBQABNQAECgIIAgABAAAAAA==.Damii:BAAANQADCgEIAQAAAA==.Darjen:BAAANQADCgYIDgAAAA==.Daysfox:BAAANQADCgQIBAAAAA==.Daysmonk:BAAANQADCgYIBgAAAA==.',
Dc='Dcash:BAAANQADCgIIAgAAAA==.',
De='Deathfang:BAAANQADCgQIBQAAAA==.Deathlyy:BAAANQAECgUICwAAAA==.Deathmatch:BAAANQAECgEIAQAAAA==.Deathstone:BAAANQADCgUIBgABNQAECggIFwACABwdAA==.Deathtress:BAAANQADCggIGAAAAA==.Debbydowner:BAAANQAECgIIAgAAAA==.Decado:BAAANQAECgMIBAAAAA==.Deemwins:BAAANQADCgYIBwAAAA==.Deezenuts:BAAANQADCggIDgABNQAECgYICQABAAAAAA==.Dejevoid:BAAANQADCggICAAAAA==.Demonroo:BAAANQADCgEIAQAAAA==.Denimdan:BAEANQAECgUICgAAAA==.Denwere:BAAANQADCgMIAwAAAA==.Deww:BAAANQADCgYIBwAAAA==.',
Dh='Dhawk:BAAANQADCggIFAAAAA==.Dhelilha:BAAANQAECgMIBQAAAA==.',
Dk='Dkalliru:BAAANQAECgQIBAAAAA==.',
Do='Docdolittle:BAAANQAECgYICgAAAA==.Docfreez:BAAANQAECgYICwAAAA==.Docragosa:BAAANQAECgIIAwAAAA==.Doctafury:BAAANQAECgIIAgABNQAECgYICgABAAAAAA==.Doraemee:BAAANQAECgIIAgAAAA==.',
Dr='Drbaconbrgr:BAAANQADCggIEQABNQAECgMIBQABAAAAAA==.Drbaobuns:BAAANQADCgYICgABNQAECgMIBQABAAAAAA==.Drcarrotcake:BAAANQADCggICAABNQAECgMIBQABAAAAAA==.Drcheeseball:BAAANQADCgMIAwABNQAECgMIBQABAAAAAA==.Drgatorwine:BAAANQADCggIDQABNQAECgMIBQABAAAAAA==.Drkimchirice:BAAANQAECgYICwABNQAECgMIBQABAAAAAA==.Drmacncheese:BAAANQAECgIIAgABNQAECgMIBQABAAAAAA==.Drpumpkinpie:BAAANQADCggIFQABNQAECgMIBQABAAAAAA==.Drshephardpi:BAAANQADCggICgABNQAECgMIBQABAAAAAA==.Druiddres:BAAANQADCggIDgAAAA==.Druidussy:BAAANQADCggICAAAAA==.Drwontonsoup:BAAANQAECgMIBQAAAA==.',
Du='Dummythicc:BAAANQADCgQIBAAAAA==.',
['Dö']='Dööku:BAAANQADCgYIBgAAAA==.',
Ei='Eighteen:BAAANQAECgQIBQAAAA==.',
Ek='Eksi:BAAANQAECgQIBAAAAA==.',
El='Elethe:BAAANQAECgIIAgABNQAFFAEIAQABAAAAAA==.Elianx:BAAANQADCgMIAwAAAA==.Elzaine:BAAANQAECgMIBAAAAA==.',
Em='Embedded:BAAANQAECgIIAgAAAA==.Emearg:BAAANQABCgEIAQAAAA==.Emearq:BAAANQABCgQIBAAAAA==.Empress:BAAANQAECgMIAwAAAA==.',
En='Endear:BAAANQADCggIBgAAAA==.Energyz:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Entrophi:BAAANQADCgMIAwAAAA==.',
Er='Erisnyx:BAAANQADCgIIAgAAAA==.',
Es='Esterelore:BAAANQADCgYIBgAAAA==.Estix:BAAANQAECgEIAQAAAA==.',
Ex='Excruciator:BAAANQAECgIIAwAAAA==.Exhumedraven:BAAANQADCgMIAwAAAA==.',
Fa='Falloutz:BAAANQADCgYIEAAAAA==.Farahcanle:BAAANQAECgQIBwAAAA==.',
Fe='Felanish:BAAANQAECgEIAQAAAA==.Felystia:BAAANQAECgEIAgAAAA==.Feorblarir:BAAANQAECgEIAQAAAA==.Fernmister:BAAANQAECgIIAwAAAA==.',
Fi='Fieryfrost:BAAANQABCgQIBgABNQADCggIFAABAAAAAA==.Filledegel:BAAANQAECgQIBQAAAA==.Finowscath:BAAANQADCgYIDAAAAA==.Firequencher:BAAANQAECgQIBwAAAA==.Fistacuffs:BAAANQADCgcICAAAAA==.Fistdoc:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Fistícuffs:BAAANQADCgUIEwAAAA==.Fizzroll:BAAANQADCgYIDQAAAA==.',
Fl='Flais:BAAANQADCgYIDgAAAA==.Fleetwoodmac:BAAANQADCgYIBgAAAA==.',
Fo='Foxfel:BAAANQAECgIIAgABNQAECgcIDAABAAAAAA==.Foxybag:BAAANQADCgYIBgAAAA==.',
Fr='Friendlypal:BAAANQAECgQIBQAAAA==.Friendofbear:BAAANQAECgcIEAAAAA==.Fromabove:BAAANQADCgMIAwAAAA==.',
Fu='Furryfeet:BAAANQAECgEIAQAAAA==.Fuzywuzzy:BAAANQAECgQIBAAAAA==.Fuzzykuntz:BAAANQAECgMIBAAAAA==.',
Fy='Fynsdood:BAAANQADCggIFAAAAA==.',
Ga='Gabelock:BAAANQAFFAEIAQAAAA==.Gala:BAAANQAECgIIAgAAAA==.Gasback:BAAANQADCgYICgAAAA==.',
Gh='Gherkins:BAAANQADCgQIBAAAAA==.Ghostreveri:BAAANQAECgIIAgAAAA==.',
Gi='Gigah:BAAANQADCggIFAAAAA==.',
Gl='Glitsch:BAAANQADCgQIBAAAAA==.Glorpnotl:BAAANQADCgYIBgAAAA==.Gloziwitz:BAAANQAECgEIAQAAAA==.Glutebruiser:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Gn='Gnomedguerre:BAAANQADCgYIDQAAAA==.',
Go='Gooseshift:BAAANQADCgMIAwAAAA==.Gouchh:BAAANQAECgEIAQAAAA==.',
Gr='Gravithel:BAAANQADCgUICgAAAA==.Grayseer:BAAANQAECgYICAAAAA==.Grimtree:BAAANQAECgIIAwAAAA==.Grommel:BAAANQADCgEIAQAAAA==.Grumpstraza:BAAANQADCgYIBgAAAA==.Grumpydemon:BAAANQAECgYICQAAAA==.',
Gw='Gwong:BAAANQADCgcIBwAAAA==.',
Ha='Halfskul:BAAANQAECgcIDgAAAA==.Halotic:BAAANQADCgYIBgAAAA==.Hashah:BAAANQAECgQIBgAAAA==.Hatefel:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.',
He='Healsgobrr:BAAANQADCgYICwABNQAECgcIDgABAAAAAA==.Healyaass:BAAANQADCgUIBQAAAA==.Hecate:BAAANQADCgIIAgAAAA==.Helenfeller:BAAANQADCgEIBAAAAA==.Helgard:BAAANQADCgQIBAAAAA==.Hesha:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Hexlexxia:BAAANQADCggIDwABNQAECgEIAwABAAAAAA==.Heyyboyy:BAAANQAECgYIBwAAAA==.',
Ho='Holysock:BAAANQADCggICAAAAA==.Holyyaii:BAAANQADCgUIBgAAAA==.Holz:BAAANQADCgUICgAAAA==.',
Hu='Hugoman:BAAANQADCggIDgABNQAECgMIBQABAAAAAA==.Huni:BAAANQAECgcICwAAAA==.Huupa:BAAANQADCgYIBgAAAA==.',
Hy='Hystaric:BAAANQADCgYIDAAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgEIAQAAAA==.',
Ib='Ibun:BAAANQADCggICwAAAA==.',
Ic='Icentheveins:BAAANQAECgQICwAAAA==.',
Ig='Igneus:BAAANQAECggICwAAAA==.Igriz:BAAANQADCgcIDQAAAA==.',
Ii='Iillil:BAAANQAECgYICwAAAA==.',
Il='Ilvinabox:BAAANQADCgQIBAAAAA==.',
Im='Imakeuflased:BAAANQADCgIIAgAAAA==.Immamoonchix:BAAANQADCgUIBgAAAA==.Imtheworst:BAAANQADCgIIAgAAAA==.Imzaiahx:BAAANQADCgEIAQAAAA==.',
Ir='Irodina:BAAANQADCgUICgAAAA==.',
It='Itsjeff:BAAANQADCgcIDgAAAA==.',
Iz='Izyel:BAAANQADCgEIAQAAAA==.',
Ja='Jaeyk:BAAANQADCggIDwAAAA==.Jambonjay:BAAANQAECgQICAAAAA==.Jaywaz:BAAANQADCgMIAwAAAA==.',
Jc='Jckjck:BAAANQADCgIIAgAAAA==.Jckjckjck:BAAANQADCgUIBQAAAA==.',
Je='Jermagedupri:BAABNQAECoEdAAIDAAkJ6BymFQAWAwADAAkJ6BymFQAWAwAAAA==.Jessupy:BAAANQAECgEIAQAAAA==.Jezashi:BAAANQADCgUIBQAAAA==.',
Jo='Johkneesinz:BAAANQADCgYICwAAAA==.Joshuå:BAAANQAECgMIAwAAAA==.',
Ju='Julieteshade:BAAANQADCgMIBAAAAA==.Junkbot:BAAANQADCgYICgAAAA==.Justiz:BAAANQADCgYIBgAAAA==.',
['Jø']='Jøsh:BAAANQADCgQIBQAAAA==.',
Ka='Kalrendion:BAAANQADCgMIAwABNQADCgcIDAABAAAAAA==.Karaillyonna:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.Karasu:BAAANQADCgUICgAAAA==.Kasher:BAAANQADCgMIBQAAAA==.Kayho:BAAANQAECgUIBQAAAA==.',
Ke='Kelltrax:BAAANQADCgcIEgAAAA==.Kelsier:BAAANQAECgYICgAAAA==.Keruilin:BAAANQADCgQIAgAAAA==.Kesk:BAAANQADCgUICAAAAA==.',
Kh='Khaster:BAAANQABCgEIAQAAAA==.Khendra:BAAANQADCgYIBwAAAA==.',
Ki='Kiezo:BAAANQAECgEIAQAAAA==.Killachefd:BAAANQAECgMIAwAAAA==.Killamanjoro:BAAANQAECgcIDwAAAA==.Kimchiwar:BAAANQAECgIIAgAAAA==.Kirasha:BAAANQADCgcIDwAAAA==.Kitak:BAAANQADCgcIDAAAAA==.Kitchenbound:BAAANQAECgQIBAAAAA==.Kittychan:BAAANQAECgMIBQAAAA==.',
Kl='Klaacus:BAAANQAECgQICwABNQAECgUIBwABAAAAAA==.',
Ko='Kokk:BAAANQADCgUIBQAAAA==.Koudelka:BAAANQAECgMIAwAAAA==.',
Kr='Kralok:BAAANQADCgYICwAAAA==.Krazm:BAAANQADCgMIAwAAAA==.Kriticál:BAAANQAECgMIBAAAAA==.Krustyg:BAAANQADCgYIBgAAAA==.',
Ku='Kuurun:BAEANQADCgcIBwABNQAECggIFQACAFkcAA==.',
La='Lakshmi:BAAANQADCgcIDAABNQAECgEIAwABAAAAAA==.Laradin:BAAANQADCgIIAQAAAA==.Larasimus:BAAANQADCgIIAgAAAA==.Larndorn:BAAANQADCgMIAwAAAA==.Lavagrip:BAAANQAECgEIAQAAAA==.',
Le='Lelou:BAABNQAECoEYAAMEAAkJvCL1BABFAwAEAAgJcib1BABFAwAFAAIJaw5fLgCQAAAAAA==.Lewsky:BAAANQAECgEIAQABNQAECgkJFgACAOEfAA==.',
Li='Lilathiaa:BAAANQADCgYIDAAAAA==.Linddria:BAAANQAECgYICQAAAA==.Liondori:BAAANQADCgYIBgAAAA==.Lipspire:BAAANQABCgYIBgAAAA==.Lissarael:BAAANQADCggIDwAAAA==.',
Lm='Lmj:BAAANQAECgEIAgAAAA==.',
Lo='Lockbox:BAAANQAECgYICwAAAA==.Loomin:BAAANQAECgcIDwAAAA==.',
Lu='Lucatia:BAAANQAECgUIBwAAAA==.Luciaa:BAAANQADCgQIAgAAAA==.Lumièrevide:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.Lunastitch:BAAANQADCgEIAQAAAA==.Lunna:BAAANQADCgMIAwAAAA==.',
['Lä']='Lädyæk:BAAANQAECgIIAwAAAA==.',
Ma='Maekyss:BAAANQAECgEIAQAAAA==.Magezu:BAAANQAECgMIBAAAAA==.Magixstraza:BAAANQAECgUICgAAAA==.Magwilddued:BAAANQADCgQIBQAAAA==.Mahmba:BAAANQAECgUIBQAAAA==.Malzel:BAAANQADCggIFAAAAA==.Mamasan:BAAANQADCgcIDAAAAA==.Maphra:BAAANQADCgQIBAAAAA==.Marvindent:BAAANQADCgYIBgAAAA==.Mastatracka:BAAANQADCgMIAwAAAA==.',
Md='Mdeow:BAAANQADCgUIBQAAAA==.',
Me='Mechabull:BAAANQABCgIIAgAAAA==.Meladys:BAAANQADCgUIBQAAAA==.Meleemeal:BAAANQADCgYIBgAAAA==.Melorac:BAAANQADCgEIAQAAAA==.Menoheal:BAAANQADCgMIAwAAAA==.Merope:BAAANQADCgUIBQAAAA==.Mertence:BAAANQAECgEIAQAAAA==.Mexicanbrick:BAAANQADCgEIAQAAAA==.',
Mh='Mheow:BAAANQADCgYICgAAAA==.',
Mi='Miakoda:BAAANQADCgQIBAABNQADCgYIBwABAAAAAA==.Mikuu:BAAANQADCgUICgAAAA==.Minouetoile:BAAANQADCgYIBgAAAA==.Mistical:BAAANQAECgQIBAAAAA==.Mitufu:BAAANQADCgcICwAAAA==.',
Mo='Mogonn:BAAANQABCgEIAQAAAA==.Moonpiie:BAAANQADCgUIBQAAAA==.Morganya:BAAANQAECgcIDAAAAA==.Morgul:BAAANQADCggIDwAAAA==.Moriru:BAAANQADCgcIBwAAAA==.Morrtis:BAAANQADCgYIEwAAAA==.Morticas:BAAANQADCgUIBQAAAA==.',
Ms='Mseow:BAAANQADCgUIDAAAAA==.',
Mu='Mudbutbrooks:BAAANQAECgQIBgAAAA==.Muddbut:BAAANQADCgQIBAABNQAECgQICwABAAAAAA==.Muller:BAAANQAECgMIBAAAAA==.',
My='Mynnu:BAAANQAECgEIAgAAAA==.Mynthara:BAAANQADCggIAgAAAA==.',
Na='Nautprepared:BAAANQAECgQIBAAAAA==.',
Ne='Neildasstysn:BAAANQAECgYICQAAAA==.Nemezyz:BAAANQADCgQIBAAAAA==.Nephey:BAAANQADCgMIAwAAAA==.Neveya:BAAANQADCgQIBAAAAA==.',
Ni='Nickeld:BAAANQAECgMIAwAAAA==.Nickhy:BAAANQADCgcICgAAAA==.Nietherme:BAAANQAECgEIAQAAAA==.',
No='Noblefiend:BAAANQADCgQIBAAAAA==.Norinithedra:BAAANQADCgMIAwAAAA==.',
Ny='Nyagosa:BAAANQAECgUIBQAAAA==.Nyalore:BAAANQAECgMIBAAAAA==.',
Ob='Obiwinonly:BAAANQADCgIIAgAAAA==.',
Oh='Ohnjaxx:BAAANQAECgEIAQAAAA==.',
Or='Oraedia:BAAANQAECgcIBwAAAA==.Oralen:BAAANQAECgYIDwAAAA==.Orilitha:BAAANQADCgYIDAAAAA==.Orndaith:BAAANQAECgIIAgAAAA==.',
Ov='Overloader:BAAANQAECgMIAwABNQAECgQIBAABAAAAAA==.',
Ox='Oxkenpachixo:BAAANQADCgMIAwAAAA==.',
Oy='Oyabun:BAAANQADCgYIBgAAAA==.',
Pa='Pairodeez:BAAANQADCgMIAQAAAA==.Pallyaxe:BAAANQADCgUIBQABNQAECgcIDQABAAAAAA==.Pandawannabe:BAAANQADCgMIBwAAAA==.Pandussi:BAAANQAECgYIBgAAAA==.Paneer:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Paninus:BAAANQAECgEIAQAAAA==.',
Pe='Pebbletoe:BAAANQADCgUIBQAAAA==.Perfectplex:BAAANQABCgQIBAAAAA==.Peruano:BAAANQAECgQIBAAAAA==.Petforheals:BAAANQAECgIIAgAAAA==.',
Ph='Phyett:BAAANQADCgEIAQABNQADCgMIBwABAAAAAA==.',
Pi='Pietastegood:BAAANQAECgYICgAAAA==.Pikaboom:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Pintsizemage:BAAANQADCgUIBQABNQAECgIIAwABAAAAAA==.',
Po='Pocahöntas:BAAANQADCgQIBAAAAA==.Pocketrocket:BAAANQADCgUIBgAAAA==.Ponce:BAAANQAECgcIDgAAAA==.Poordemon:BAAANQADCgUIBQABNQAECgMIBQABAAAAAA==.Popehealz:BAAANQADCgYIBgAAAA==.',
Pr='Priestofholy:BAAANQADCgYIBwAAAA==.Provolonie:BAAANQADCggIDAAAAA==.Pròntò:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Prõntõ:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.Prøntø:BAAANQAECgQIBgAAAA==.',
Pu='Puffthemagic:BAAANQADCgYICQABNQAECgYICgABAAAAAA==.Punchbugman:BAAANQADCggIDAAAAA==.Puritos:BAAANQADCgcIBwAAAA==.',
Py='Pyrista:BAAANQADCggIFAAAAA==.',
Qo='Qortethpally:BAAANQADCgQIBAAAAA==.',
Qu='Quinte:BAEANQABCgQIBAAAAA==.',
Ra='Radetoo:BAAANQAECgIIAgAAAA==.Radilas:BAAANQABCgIIAgAAAA==.Radioatlarge:BAAANQADCgUIBQABNQAECgYICgABAAAAAA==.Raendarth:BAAANQADCggIDwAAAA==.Rageth:BAAANQAECgIIAgAAAA==.Rakalaag:BAEANQADCgUIBQAAAA==.Rakath:BAAANQADCgYIDgAAAA==.Ramidus:BAAANQAECgIIAgAAAA==.Ranciid:BAAANQADCgIIAwAAAA==.Rasmis:BAAANQAECgcIDAAAAA==.',
Re='Reck:BAAANQAECgYICgAAAA==.Rejuve:BAAANQADCgYIBgAAAA==.Rektify:BAAANQADCgEIAQAAAA==.Renwick:BAAANQADCggICAABNQAFFAEIAQABAAAAAA==.Reunach:BAAANQAECgEIAQAAAA==.',
Rh='Rhahirn:BAAANQADCgEIAQAAAA==.Rhialto:BAAANQADCgIIAgAAAA==.Rhyzand:BAAANQADCgIIAwAAAA==.',
Ri='Riasg:BAAANQADCgIIAgAAAA==.Rickilake:BAAANQADCgUICgAAAA==.Ricksanchez:BAAANQAECgEIAQAAAA==.Rinik:BAAANQAECgQIBQAAAA==.Riptiide:BAAANQADCgcIBwABNQADCggIDgABAAAAAA==.Rivendra:BAAANQADCgcIDgAAAA==.',
Ro='Rockabye:BAAANQAECgEIAQAAAA==.Rosannas:BAAANQADCgUIAgABNQAECgcICwABAAAAAA==.Rosi:BAAANQADCggICAAAAA==.Royallz:BAAANQADCggICAAAAA==.',
Ru='Rudeknees:BAAANQAFFAEIAQAAAA==.Ruibash:BAEBNQAECoEVAAICAAgJWRxyEwCvAgACAAgJWRxyEwCvAgAAAA==.Runebladé:BAAANQADCgYICgAAAA==.',
Ry='Ryuu:BAAANQADCggIDAAAAA==.',
Sa='Sacredknight:BAAANQADCgQIBAAAAA==.Saikoumaster:BAAANQADCggIEQAAAA==.Sakuraa:BAAANQAECgIIAgAAAA==.Sarajean:BAAANQADCgQIBAAAAA==.Savaged:BAAANQADCgcIDAABNQAECgUICwABAAAAAA==.Savajed:BAAANQAECgUICwAAAA==.',
Sc='Scallywagg:BAAANQADCgEIAQAAAA==.Scarletmatch:BAAANQAECgIIAgAAAA==.',
Se='Searcomic:BAAANQAECgQIBAAAAA==.Secondwall:BAAANQADCgMIAwAAAA==.Seldav:BAAANQAECgcIDgAAAA==.Selendas:BAAANQADCgEIAQAAAA==.Selessa:BAAANQADCggICgAAAA==.Selm:BAAANQAECgQIBQAAAA==.',
Sh='Shadedluster:BAAANQADCgQIBQAAAA==.Shaleka:BAAANQADCgUICAAAAA==.Shaluesta:BAAANQADCgcIBwAAAA==.Shamanism:BAAANQAECgEIAQAAAA==.Shameless:BAAANQAECgYIBgAAAA==.Shamwów:BAAANQAECgUICQAAAA==.Sharco:BAAANQAECgYIDAAAAA==.Sharkbites:BAAANQAECgIIAgAAAA==.Shawarmafury:BAAANQAECggIEgAAAA==.Shiirou:BAAANQADCgQIBAAAAA==.Shockadinn:BAAANQAECggIBgAAAA==.Shooshmael:BAAANQAECgQIBAAAAA==.Shékinah:BAAANQAECgcICwAAAA==.',
Si='Sidesteppin:BAAANQADCgQIBAAAAA==.Silirazzle:BAAANQADCgMIAwAAAA==.Sinsister:BAAANQAECgMIAwAAAA==.Sinthein:BAAANQAECgIIAgABNQAFFAEIAQABAAAAAA==.',
Sk='Skadgrip:BAAANQADCgUIBQABNQADCggIFAABAAAAAA==.Skorpekh:BAAANQAECgQIBAAAAA==.Skyle:BAAANQADCgQIBAAAAA==.Skypanties:BAAANQAECgEIAgAAAA==.',
Sl='Sleepingsun:BAAANQAECgQIBAAAAA==.Sloppyspikes:BAAANQAECgMIBAAAAA==.',
Sm='Smakm:BAAANQADCgEIAQAAAA==.Smidgenn:BAAANQADCgcIDAAAAA==.Smokyblast:BAAANQADCggIFgAAAA==.Smolden:BAAANQABCgEIAQAAAA==.',
Sn='Snailtrails:BAAANQADCgcIEAAAAA==.Snowball:BAAANQAECgQIDAAAAA==.',
So='Sohtan:BAAANQADCgMIAwAAAA==.Sonbrandt:BAAANQADCgcIDQAAAA==.Soulforge:BAAANQADCgQIBAAAAA==.Soulread:BAAANQAECgIIAgAAAA==.',
Sp='Sparowprince:BAABNQAECoEXAAICAAgJHB0bFgCVAgACAAgJHB0bFgCVAgAAAA==.Speccurious:BAAANQADCgYIBwAAAA==.Spectraleye:BAAANQAECgMIAwAAAA==.Sproocherlou:BAAANQAECggIAQAAAA==.Sprour:BAAANQAECgEIAgAAAA==.',
St='Stankbolt:BAAANQAECgEIAQAAAA==.Steezya:BAAANQAECgUIBQAAAA==.Stellarum:BAAANQAECgMIAgAAAA==.Stormykitty:BAAANQAECgYICgAAAA==.Striderdh:BAAANQABCgQIBAAAAA==.Strongwoman:BAAANQAECgEIAQAAAA==.Sturtza:BAAANQAECgcIDgAAAA==.',
Su='Subarashi:BAAANQADCgYIBgAAAA==.Sukmybigtoe:BAAANQADCgIIAQAAAA==.Suun:BAAANQAECgQIBgAAAA==.',
Sw='Swampassuti:BAAANQAECgEIAQAAAA==.Swoley:BAAANQAECgMIBAAAAA==.',
Sy='Sylphia:BAAANQADCgYIBgAAAA==.Syrina:BAAANQADCgQIBAAAAA==.',
Ta='Taelandas:BAAANQADCgQICQAAAA==.Tagobeets:BAAANQAECgQIBAAAAA==.Taleiya:BAAANQADCggIJAAAAA==.Talisaie:BAAANQADCgUIBQABNQAECggIDgABAAAAAA==.Tanisatharae:BAAANQADCgYIDgAAAA==.Tarahse:BAAANQADCgIIAgABNQADCgcIEAABAAAAAA==.Taron:BAAANQADCggIDwAAAA==.Tart:BAAANQAECgcIDAAAAA==.',
Te='Tedjones:BAAANQAECgIIAgAAAA==.Temupeggy:BAAANQADCgEIAQAAAA==.',
Th='Thehumanatee:BAAANQAECgQIBQAAAA==.Theunholyone:BAAANQADCgcIDQAAAA==.Thilidan:BAAANQADCgEIAQAAAA==.Thingytoo:BAAANQADCgUICwAAAA==.Thiqq:BAAANQADCggICAAAAA==.Threlindrier:BAAANQADCgQIBAAAAA==.Throbinggimp:BAAANQADCgcIBwAAAA==.Thyphlo:BAAANQAECgEIAQAAAA==.',
Ti='Tiltedup:BAAANQAECggIDgAAAA==.Tinesa:BAAANQADCgQIBQAAAA==.Tirich:BAAANQADCggICAABNQAFFAEIAQABAAAAAA==.Titaintium:BAAANQAECgQIBAAAAA==.',
To='Toshi:BAAANQAECgEIAQAAAA==.Totemtree:BAAANQADCgMIAwABNQAECgIIAwABAAAAAA==.',
Tr='Trustmei:BAAANQADCggIDAAAAA==.Trystin:BAAANQAECgIIAgAAAA==.',
Tu='Tullyy:BAAANQADCgMIAgAAAA==.Tums:BAAANQAECgQIBwAAAA==.',
Tw='Twirls:BAAANQAECgQIBQAAAA==.Twistoffate:BAAANQAECgEIAQAAAA==.',
Ty='Tyerant:BAAANQADCgMIAgAAAA==.Tylenill:BAAANQADCgQIBAAAAA==.',
Ug='Uglygoat:BAAANQADCgEIAQAAAA==.',
Um='Umbrasanctus:BAAANQADCgUIBgAAAA==.',
Ur='Urtle:BAAANQADCggIFAAAAA==.',
Us='Uselece:BAAANQAECgUIBwAAAA==.',
Ut='Uthadandewey:BAAANQADCgcIBwAAAA==.',
Va='Valgorr:BAAANQADCgYIDAAAAA==.Valvalon:BAAANQADCggIEgAAAA==.',
Ve='Veelaria:BAAANQAECgIIAgAAAA==.Vegetablue:BAAANQAECgEIAQAAAA==.Vet:BAAANQAECgQIBwAAAA==.',
Vh='Vhelithiana:BAAANQADCgUICgAAAA==.',
Vi='Viathun:BAAANQADCggICAABNQAECgUICwABAAAAAA==.Vicalaus:BAAANQAECgUIBwAAAA==.View:BAAANQAECgYICAAAAA==.Vikcy:BAAANQADCgYICwAAAA==.Vilified:BAAANQADCgQICwAAAA==.Vitros:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.',
Vo='Voidbren:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.Voidwitch:BAAANQAECgEIAQAAAA==.Volstagg:BAAANQADCgMIAwAAAA==.',
Vy='Vyndenus:BAAANQAECgQIAwAAAA==.',
Wa='Warriorluv:BAAANQADCgEIAQAAAA==.Warrwing:BAAANQADCgcIBwAAAA==.',
We='Webbfury:BAAANQADCggIFAAAAA==.Wespoo:BAAANQAECgQIBQAAAA==.',
Wi='Wiggles:BAAANQABCgEIAQAAAA==.Wigpetval:BAAANQAECgQICAAAAA==.Wiidge:BAAANQADCggIFQAAAA==.Wildside:BAAANQADCgUIBwAAAA==.Willregret:BAAANQAECgMIBQAAAA==.Winterbane:BAAANQADCggICAAAAA==.',
Wo='Wocky:BAAANQAECgMIAwAAAA==.Wolfchan:BAAANQABCgYICQAAAA==.Worldender:BAAANQAECgEIAQAAAA==.',
Xa='Xantry:BAABNQAECoEWAAICAAkJ4R9nBQBwAwACAAkJ4R9nBQBwAwAAAA==.',
Xy='Xymm:BAAANQADCgQIBQAAAA==.',
Ye='Yeastybush:BAAANQAECgUICAAAAA==.',
Ys='Yseeraa:BAAANQADCggIDAAAAA==.',
Za='Zalatoes:BAAANQADCggIFQAAAA==.Zarathea:BAAANQADCgYIBgABNQADCgYIBwABAAAAAA==.',
Zi='Zilphah:BAAANQADCgMIAwAAAA==.Zimmerwitch:BAAANQADCggIDgAAAA==.Zimms:BAAANQAECgQIBAAAAA==.',
Zo='Zoeyredbird:BAAANQADCggIFAAAAA==.',
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
