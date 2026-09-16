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

local lookup = {'Unknown-Unknown','Warrior-Arms','Shaman-Restoration','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DeathKnight-Unholy','Evoker-Augmentation','Mage-Arcane','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Frost','Paladin-Holy','Shaman-Elemental','Shaman-Enhancement','Evoker-Devastation','DemonHunter-Havoc',}
local provider = {region='US',realm='Daggerspine',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aamara:BAAANQAECgEIBAAAAA==.',
Ab='Aboyton:BAAANQADCgUIBQABNQADCgUICAABAAAAAA==.',
Ad='Adhpally:BAAANQADCgIIAgABNQAECgkJGQACAHIeAA==.',
Ae='Aefarshammy:BAAANQAECgcIEwAAAA==.Aerithorn:BAAANQAECgYIEAAAAA==.',
Ah='Ahleya:BAAANQAECgQIBAAAAA==.Ahlonaa:BAAANQADCgYICwAAAA==.',
Ai='Airundies:BAAANQADCgcIBwABNQAECgQIBgABAAAAAA==.',
Ak='Akoris:BAAANQADCgUIBgABNQAECgMIBAABAAAAAA==.Akorys:BAAANQAECgMIBAAAAA==.',
Al='Albyno:BAAANQAFFAEIAQAAAA==.',
Am='Amara:BAAANQADCgQICwAAAA==.Ambitionz:BAAANQADCgEIAQAAAA==.Ameadynnie:BAAANQABCgIIAgAAAA==.',
An='Anchint:BAAANQAECgMIAwAAAA==.Ancksunamun:BAAANQADCgQIBAAAAA==.Andromedia:BAAANQADCgYIBgABNQAECgEIBAABAAAAAA==.Anicarcia:BAAANQADCgQIBAAAAA==.Anuurg:BAAANQADCgIIAgAAAA==.Anwir:BAAANQAFFAIIAwAAAA==.',
Aq='Aquua:BAAANQAECgYICgAAAA==.',
Ar='Arcticdps:BAAANQAECggIEQAAAA==.Ariell:BAAANQAECgYICwAAAA==.Ariestar:BAAANQAECgUIBQAAAA==.Ariiel:BAAANQADCggICQABNQAECgYICwABAAAAAA==.Arthimas:BAAANQADCgYICQAAAA==.Arthurdent:BAAANQAECgMIBQAAAA==.',
As='Ascendance:BAAANQADCggIDwAAAA==.Ashelash:BAAANQAECgIIAgAAAA==.Asidize:BAAANQADCggIEQAAAA==.Aslor:BAAANQAECgQIBwAAAA==.Aspenoa:BAAANQADCggICAAAAA==.',
At='Athalia:BAAANQAECggIEwAAAA==.Atlaswolfe:BAAANQADCgYIDAAAAA==.',
Au='Aug:BAAANQAECgMIAwAAAA==.',
Av='Avex:BAAANQAECgQIBgAAAA==.',
Ax='Axemage:BAAANQAECgcIEgAAAA==.Axeom:BAABNQAECoEcAAIDAAcJOxn5KQAcAgADAAcJOxn5KQAcAgAAAA==.Axeshammy:BAAANQADCggICAABNQAECgcIEgABAAAAAA==.',
Az='Azmodan:BAAANQAECgEIAQAAAA==.Azzith:BAAANQAECgMIBAAAAA==.',
Ba='Bajaladin:BAAANQAECgMIBQAAAA==.Barometer:BAAANQAECgUIBQAAAA==.Bast:BAAANQADCggIAwABNQAECgMIBAABAAAAAA==.Baxa:BAAANQADCgYIBgAAAA==.Baylee:BAAANQAECgQIDAAAAA==.',
Be='Bearaqobama:BAAANQADCgYIBgAAAA==.Bearlyalivee:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Bearvul:BAAANQABCgEIAQAAAA==.Beekerr:BAAANQADCgMIAwABNQAECgYIDQABAAAAAA==.Belbroon:BAAANQADCgQIBAAAAA==.Beliele:BAAANQADCgUIBQAAAA==.Benjohnbo:BAAANQABCgEIAQAAAA==.Benwins:BAAANQAECgEIAgAAAA==.Bergamö:BAAANQADCgcICQABNQAECgIIAwABAAAAAA==.Bernecessity:BAAANQADCggIFAAAAA==.',
Bh='Bho:BAAANQADCgUIBQAAAA==.',
Bi='Biffedit:BAAANQADCgcIBwAAAA==.Bis:BAAANQADCgEIAQAAAA==.Biscuitbabe:BAAANQAECgUICAAAAA==.Bisholoyd:BAAANQAECgIIAgAAAA==.',
Bl='Blackgold:BAAANQADCgQIBAAAAA==.Blastoise:BAAANQAECggIEAAAAA==.Blinktwice:BAAANQABCgYIBgAAAA==.Blizfishleg:BAAANQADCgUIBQAAAA==.Bllur:BAAANQADCgIIAgAAAA==.Bloodroots:BAAANQAECgMIBwAAAA==.Bluur:BAAANQADCgYIBgAAAA==.',
Bo='Boostia:BAAANQADCgEIAQAAAA==.Borthos:BAAANQAECgYICQAAAA==.Bowsback:BAAANQADCgYIDgAAAA==.',
Br='Brandoe:BAAANQAECgQIBQAAAA==.Breece:BAAANQADCgUIBQAAAA==.Brickinkeys:BAAANQADCgYIBgABNQAECgEIBAABAAAAAA==.Brightmare:BAAANQADCgYICwAAAA==.Brynnix:BAAANQADCgEIAQAAAA==.',
['Bà']='Bàne:BAAANQAECgQIBAAAAA==.',
Ca='Caadra:BAAANQADCgIIAgAAAA==.Caimie:BAAANQADCgYICwAAAA==.Calfionn:BAAANQADCgIIAgAAAA==.Candez:BAAANQADCgUIBQAAAA==.Canroth:BAAANQAECgIIAgAAAA==.Cassiaan:BAAANQADCggIDgAAAA==.Caylavibes:BAAANQAECgcIDQAAAA==.',
Ch='Chaviel:BAAANQAECgcIBwAAAA==.Cherry:BAAANQADCggICAAAAA==.Chironn:BAAANQAECgUICwAAAA==.Chull:BAAANQADCgIIAgAAAA==.Chumbo:BAAANQAECgMIAwAAAA==.',
Ci='Cinderburn:BAAANQADCgcIDAAAAA==.Cinderkai:BAAANQADCgEIAQAAAA==.',
Cl='Clayshaper:BAAANQADCgYIDAAAAA==.Clohhe:BAAANQAECgEIAQAAAA==.Clwnshoenrgy:BAAANQADCgYIBgAAAA==.',
Co='Combust:BAAANQADCgEIAQAAAA==.Comfychair:BAAANQADCgUIBQAAAA==.Conclaved:BAAANQADCgMIAwAAAA==.Coowmoo:BAAANQAECgMIAwAAAA==.Cosmochopper:BAAANQAECgEIAQABNQAECgQIAwABAAAAAA==.Cosmoshotter:BAAANQAECgQIAwAAAA==.',
Cr='Craterstab:BAAANQADCgEIAQAAAA==.Cremebrule:BAAANQADCggIEgAAAA==.Critnyspears:BAAANQAECgIIBAAAAA==.Crushleaf:BAAANQADCggICwAAAA==.',
Cy='Cyndra:BAAANQADCgIIAgAAAA==.',
Da='Dallthyrian:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Dalthyriian:BAAANQAECgIIAgAAAA==.Dalthyrrian:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Dalthyyrian:BAAANQAECgQIBAABNQAECgIIAgABAAAAAA==.Damii:BAAANQADCgEIAQAAAA==.Danfarm:BAAANQADCgEIAQAAAA==.Dargonbref:BAAANQADCgUIAQABNQAECgMIBQABAAAAAA==.Darjen:BAAANQADCgcIFQAAAA==.Darkjestêr:BAAANQADCgUIBQAAAA==.Daysfox:BAAANQAECgIIAgAAAA==.Daysmonk:BAAANQADCgYIBgAAAA==.',
Dc='Dcash:BAAANQADCgIIAgAAAA==.',
De='Deathfang:BAAANQADCgUICgAAAA==.Deathlyy:BAAANQAECgYIEQAAAA==.Deathmatch:BAAANQAECgEIAQAAAA==.Deathstone:BAAANQAECgEIAQABNQAECgkJIQAEAB8gAA==.Deathtress:BAAANQAECgMIAwAAAA==.Debbydowner:BAAANQAECgQIBgAAAA==.Decado:BAAANQAECgMIBAAAAA==.Deemwins:BAAANQADCgYIBwAAAA==.Deezenuts:BAAANQADCggIDgABNQAECgYICQABAAAAAA==.Dejevoid:BAAANQAECgMIAwAAAA==.Demonroo:BAAANQADCgEIAQAAAA==.Denimdan:BAEANQAECgUICgAAAA==.Denwere:BAAANQADCgMIAwAAAA==.Deww:BAAANQAECgYIBwAAAA==.',
Dh='Dhawk:BAAANQADCggIFAAAAA==.Dhelilha:BAAANQAECgQIDAAAAA==.',
Dk='Dkalliru:BAAANQAECgYICgAAAA==.',
Do='Docdolittle:BAAANQAECgcIEAAAAA==.Docfreez:BAAANQAECgYIDwAAAA==.Docragosa:BAAANQAECgMIBAABNQAECgQIBQABAAAAAA==.Doctafury:BAAANQAECgUIBwABNQAECgcIEAABAAAAAA==.Doctermoo:BAAANQADCgUIBQAAAA==.Doomhamer:BAAANQADCggICAABNQAECgYICQABAAAAAA==.Doraemee:BAAANQAECgIIAgAAAA==.',
Dr='Drbaconbrgr:BAAANQAECgUIBQABNQAECgMICAABAAAAAA==.Drbaobuns:BAAANQADCgYICgABNQAECgMICAABAAAAAA==.Drcarrotcake:BAAANQADCggIDgABNQAECgMICAABAAAAAA==.Drcheeseball:BAAANQADCgMIAwABNQAECgMICAABAAAAAA==.Drgatorwine:BAAANQAECgQIBAABNQAECgMICAABAAAAAA==.Drkimchirice:BAAANQAECgYIEQABNQAECgMICAABAAAAAA==.Drmacncheese:BAAANQAECgMIBQABNQAECgMICAABAAAAAA==.Drpumpkinpie:BAAANQAECgEIAQABNQAECgMICAABAAAAAA==.Drshephardpi:BAAANQADCggICgABNQAECgMICAABAAAAAA==.Druiddres:BAAANQAECgQIBAAAAA==.Druidussy:BAAANQADCggICAAAAA==.Drwontonsoup:BAAANQAECgMICAAAAA==.',
Du='Dummythicc:BAAANQADCgQIBAAAAA==.',
['Dö']='Dööku:BAAANQADCgYIBgAAAA==.',
Ei='Eighteen:BAAANQAECgYICwAAAA==.',
Ek='Eksi:BAAANQAECgYICgAAAA==.',
El='Elethe:BAAANQAECgIIAgABNQAFFAIIAwABAAAAAA==.Elianx:BAAANQADCgUIBgAAAA==.Elzaine:BAAANQAECgMIBAAAAA==.',
Em='Embedded:BAAANQAECgMIBQAAAA==.Emearg:BAAANQADCgYIBgAAAA==.Emearq:BAAANQABCggICgAAAA==.Empress:BAAANQAECgMIAwAAAA==.',
En='Endear:BAAANQADCggIBgAAAA==.Energyz:BAAANQADCgUIBwABNQAECgcIEAABAAAAAA==.Entrophi:BAAANQADCgMIAwAAAA==.',
Er='Erisnyx:BAAANQADCgIIAgAAAA==.',
Es='Esterelore:BAAANQADCgYIBgAAAA==.Estix:BAAANQAECgEIAQABNQAECgcIEAABAAAAAA==.',
Ex='Excruciator:BAAANQAECgUICAAAAA==.Exhumedraven:BAAANQADCgMIAwAAAA==.',
Fa='Falloutz:BAAANQADCgYIFgAAAA==.Farahcanle:BAAANQAECgcIDwAAAA==.Farrock:BAAANQAECgQIBAAAAA==.Fawxette:BAAANQADCggICAABNQAECggIEwABAAAAAA==.',
Fe='Felanish:BAAANQAECgEIAQAAAA==.Felystia:BAAANQAECgEIAgAAAA==.Feorblarir:BAAANQAECgEIAQAAAA==.Fernmister:BAAANQAECgIIAwAAAA==.',
Fi='Fieryfrost:BAAANQABCgQIBgABNQAECgEIAQABAAAAAA==.Filledegel:BAAANQAECgQICQAAAA==.Finowscath:BAAANQADCgYIDAAAAA==.Firequencher:BAAANQAECgYIDQAAAA==.Fistacuffs:BAAANQADCgcICAAAAA==.Fistdoc:BAAANQAECgQIBQAAAA==.Fistícuffs:BAAANQADCggIFgAAAA==.Fizzroll:BAAANQADCgYIEwAAAA==.Fié:BAAANQADCgYIBgABNQAECggIEwABAAAAAA==.',
Fl='Flais:BAAANQADCgcIFQAAAA==.Fleetwoodmac:BAAANQADCgYIBgAAAA==.',
Fo='Foxfel:BAAANQAECgUIDAABNQAECggIEwABAAAAAA==.Foxybag:BAAANQADCgYIBgAAAA==.',
Fr='Friendlypal:BAAANQAECgQIBQAAAA==.Friendofbear:BAAANQAECgcIEwAAAA==.Fromabove:BAAANQADCgMIAwAAAA==.',
Fu='Furryfeet:BAAANQAECgEIAQAAAA==.Fuzywuzzy:BAAANQAECgQIBwAAAA==.Fuzzykuntz:BAAANQAECgMIBAAAAA==.',
Fy='Fynsdood:BAAANQAECgEIAQAAAA==.',
Ga='Gabelock:BAABNQAECoEeAAQFAAkJMyIKDgDxAgAFAAgJSyIKDgDxAgAGAAQJLhmXIwAcAQAHAAEJ5hxgGQBDAAAAAA==.Gabemage:BAAANQAECgUIBQAAAA==.Gala:BAAANQAECgIIAgAAAA==.Gasback:BAAANQADCgYICwAAAA==.',
Gh='Gherkins:BAAANQADCgYICgAAAA==.Ghostreveri:BAAANQAECgUIBwAAAA==.',
Gi='Gigah:BAAANQAECgMIAwAAAA==.',
Gl='Glitsch:BAAANQADCgQIBAAAAA==.Glorpnotl:BAAANQADCgYIBgAAAA==.Gloziwitz:BAAANQAECgMIAwAAAA==.Glutebruiser:BAAANQADCgMIAwABNQAECgIIAwABAAAAAA==.',
Gn='Gnomedguerre:BAAANQADCgYIDQAAAA==.',
Go='Gooseshift:BAAANQAECgEIAQAAAA==.Gouchh:BAAANQAECgEIAQAAAA==.',
Gr='Gravithel:BAAANQADCgUIDAAAAA==.Grayseer:BAAANQAECgYIDgAAAA==.Grimtree:BAAANQAECgUICAAAAA==.Grindor:BAAANQADCgQIBAAAAA==.Grommel:BAAANQADCgQIBQAAAA==.Grumpstraza:BAAANQADCgcIDQAAAA==.Grumpydemon:BAAANQAECgcIEAAAAA==.',
Gw='Gwong:BAAANQADCgcIBwAAAA==.',
Ha='Halfskul:BAABNQAECoEYAAIIAAgJ4gyxLADZAQAIAAgJ4gyxLADZAQAAAA==.Halotic:BAAANQADCgYIBgAAAA==.Hashah:BAAANQAECgQICQAAAA==.Hatefel:BAAANQADCgEIAQABNQAECgEIAgABAAAAAA==.',
He='Healsgobrr:BAAANQADCgYICwABNQAECgkJGAAJAMUWAA==.Healyaass:BAAANQADCgUIBgAAAA==.Hecate:BAAANQADCgIIAgAAAA==.Helenfeller:BAAANQADCgEIBAAAAA==.Helgard:BAAANQADCgQIBAAAAA==.Hesha:BAAANQADCgQIBAABNQAECgQICQABAAAAAA==.Hexlexxia:BAAANQADCggIDwABNQAECgEIBAABAAAAAA==.Heyyboyy:BAAANQAECgYIBwAAAA==.',
Ho='Holyaefar:BAAANQADCgQIBAABNQAECgcIEwABAAAAAA==.Holysab:BAAANQAECgIIAgAAAA==.Holysock:BAAANQADCggICAAAAA==.Holyyaii:BAAANQAECgEIAQAAAA==.Holz:BAAANQADCgYIEAAAAA==.',
Hu='Hugoman:BAAANQADCggIFAABNQAECgMIBgABAAAAAA==.Huni:BAAANQAECgcIEgAAAA==.Huupa:BAAANQADCgYIBgAAAA==.',
Hy='Hystaric:BAAANQADCgYIDAAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgEIAQAAAA==.',
Ia='Iamyu:BAAANQAECgMIAQABNQAECgQIAwABAAAAAA==.',
Ib='Ibun:BAAANQAECgEIAQAAAA==.',
Ic='Icentheveins:BAAANQAECggIEwAAAA==.',
Ig='Igneus:BAAANQAFFAEIAQAAAA==.Igriz:BAAANQADCggIFQAAAA==.',
Ii='Iillil:BAAANQAECgcIDgAAAA==.',
Il='Ilvinabox:BAAANQADCgQIBAAAAA==.',
Im='Imakeuflased:BAAANQADCgIIAgAAAA==.Immamoonchix:BAAANQADCgUICwAAAA==.Imtheworst:BAAANQADCgIIAgAAAA==.Imzaiahx:BAAANQADCgEIAQAAAA==.',
Ir='Irodina:BAAANQADCgUICgAAAA==.',
It='Itsjeff:BAAANQAECgIIAgAAAA==.',
Iz='Izyel:BAAANQADCgEIAQAAAA==.',
Ja='Jaeyk:BAAANQADCggIFwAAAA==.Jambonjay:BAAANQAECgQIDAAAAA==.Jarnirdimli:BAAANQABCgQICgAAAA==.Jaywaz:BAAANQADCgMIAwAAAA==.',
Jc='Jckjck:BAAANQADCgIIAgAAAA==.Jckjckjck:BAAANQADCgUIBQAAAA==.',
Je='Jermagedupri:BAABNQAECoEmAAIKAAkJGyD0EwBRAwAKAAkJGyD0EwBRAwAAAA==.Jessupy:BAAANQAECgEIAQAAAA==.Jezashi:BAAANQADCgUIBQAAAA==.',
Jo='Johkneesinz:BAAANQADCgYICwAAAA==.Joshuå:BAAANQAECgQIBgAAAA==.',
Ju='Julieteshade:BAAANQADCgMIBAAAAA==.Junkbot:BAAANQADCgYICgAAAA==.Justiz:BAAANQADCgYIBgAAAA==.',
['Jø']='Jøsh:BAAANQADCgQIBQAAAA==.',
Ka='Kalrendion:BAAANQADCgMIAwABNQAECgMIAwABAAAAAA==.Karaillyonna:BAAANQADCgIIAgABNQAECgQICQABAAAAAA==.Karasu:BAAANQADCgYIEAAAAA==.Kasher:BAAANQADCgMIBQAAAA==.Kayho:BAAANQAECgUIBwAAAA==.',
Ke='Kelltrax:BAAANQAECgIIAgAAAA==.Kelsier:BAAANQAECgcIEQAAAA==.Keruilin:BAAANQADCgQIAgAAAA==.Kesk:BAAANQADCgUICAAAAA==.',
Kh='Khaster:BAAANQABCgEIAQAAAA==.Khela:BAAANQAECgEIAQAAAA==.Khendra:BAAANQADCgYIBwABNQADCggICAABAAAAAA==.',
Ki='Kiezo:BAAANQAECgQIBQAAAA==.Killachefd:BAAANQAECgMIAwAAAA==.Killamanjoro:BAABNQAECoEaAAICAAgJWxxlLgCHAgACAAgJWxxlLgCHAgAAAA==.Kimchiwar:BAAANQAECgMIAwAAAA==.Kirasha:BAAANQADCgYIFQAAAA==.Kitak:BAAANQAECgMIAwAAAA==.Kitchenbound:BAAANQAECgUICQAAAA==.Kittychan:BAAANQAECgMIBgAAAA==.',
Kl='Klaacus:BAAANQAECgYIEQAAAA==.Kloex:BAAANQABCgIIAgAAAA==.',
Ko='Kokk:BAAANQADCgUIBQAAAA==.Koudelka:BAAANQAECgQIBAAAAA==.',
Kr='Kralok:BAAANQADCgYICwAAAA==.Krazm:BAAANQADCgMIAwAAAA==.Kriticál:BAAANQAECggIDAAAAA==.Krustyg:BAAANQADCgcIDAAAAA==.Krustym:BAAANQADCgYIBgAAAA==.',
Ku='Kuurun:BAEANQADCgcIBwABNQAECggIGwAEAL4dAA==.',
La='Lakshmi:BAAANQAECgEIAQABNQAECgEIBAABAAAAAA==.Laradin:BAAANQADCgIIAQAAAA==.Larasimus:BAAANQADCgIIAgAAAA==.Larndorn:BAAANQADCgMIAwAAAA==.Lavagrip:BAAANQAECgQIBgAAAA==.',
Le='Lelou:BAABNQAECoEhAAMLAAkJtSPVCABHAwALAAgJiSbVCABHAwAMAAIJNBRbOQCTAAAAAA==.Lewsky:BAAANQAECgEIAwABNQAECgkJGAAEANciAA==.',
Li='Lilathiaa:BAAANQADCgYIDAAAAA==.Lilru:BAAANQAECgEIAQAAAA==.Linddria:BAAANQAECgYIDgAAAA==.Liondori:BAAANQADCgcIBgAAAA==.Lipspire:BAAANQABCggICAAAAA==.Lissarael:BAAANQAECgMIAwAAAA==.',
Lm='Lmj:BAAANQAECgIIBAAAAA==.',
Lo='Lockbox:BAAANQAECgYIDwAAAA==.Loomin:BAABNQAECoEYAAMKAAkJpBQ8PwCVAgAKAAkJpBQ8PwCVAgANAAQJkAbhFgCXAAAAAA==.',
Lu='Lucatia:BAAANQAECgUICwAAAA==.Luciaa:BAAANQADCgQIAgAAAA==.Lumièrevide:BAAANQADCgIIAgABNQAECgQICQABAAAAAA==.Lunastitch:BAAANQADCgEIAQAAAA==.Lunna:BAAANQADCgMIAwAAAA==.',
['Lä']='Lädyæk:BAAANQAECgIIAwAAAA==.',
Ma='Maekyss:BAAANQAECgMIBAAAAA==.Magezu:BAAANQAECgQICAAAAA==.Maggarak:BAAANQADCgIIAgAAAA==.Magixstraza:BAAANQAECgcIEQAAAA==.Magwilddued:BAAANQADCgQIBQAAAA==.Mahmba:BAAANQAECgUIBQAAAA==.Malzel:BAAANQAECgMIAwAAAA==.Mamasan:BAAANQADCgcIDAAAAA==.Maphra:BAAANQADCgQIBAAAAA==.Marvindent:BAAANQADCgYIBgAAAA==.Mastatracka:BAAANQADCgMIBQAAAA==.Mazethak:BAAANQADCgYIBgAAAA==.',
Md='Mdeow:BAAANQADCgUIBQAAAA==.',
Me='Mechabull:BAAANQABCgIIAgAAAA==.Meladys:BAAANQADCgUIBQAAAA==.Meleemeal:BAAANQADCgYIDAAAAA==.Melorac:BAAANQADCgEIAQAAAA==.Menoheal:BAAANQADCgMIAwAAAA==.Merope:BAAANQADCgUIBQAAAA==.Mertence:BAAANQAECgIIAwAAAA==.Mexicanbrick:BAAANQADCgEIAQAAAA==.',
Mh='Mheow:BAAANQAECgIIAgAAAA==.',
Mi='Miakoda:BAAANQADCgQIBAABNQADCgYIBwABAAAAAA==.Mikuu:BAAANQAECgIIAgAAAA==.Minouetoile:BAAANQADCgYIBgAAAA==.Mistdru:BAAANQADCgUIBQAAAA==.Mistical:BAAANQAECgYIBwAAAA==.Mitufu:BAAANQADCggIDQAAAA==.',
Mo='Mogonn:BAAANQABCgEIAQAAAA==.Moonpiie:BAAANQADCgUIBQAAAA==.Morganya:BAAANQAECggIEwAAAA==.Morgul:BAAANQAECgMIAwAAAA==.Moriru:BAAANQAECgMIAwAAAA==.Morrtis:BAAANQADCgYIEwAAAA==.Morticas:BAAANQADCgcIBwAAAA==.',
Ms='Mseow:BAAANQADCgUIDAAAAA==.',
Mu='Mudbutbrooks:BAAANQAECgQICQAAAA==.Muddbut:BAAANQADCgQIBAABNQAECggIEwABAAAAAA==.Muller:BAAANQAECgMIBQAAAA==.',
My='Mynnu:BAAANQAECgEIBAAAAA==.Mynthara:BAAANQADCggIAgAAAA==.',
Na='Nautprepared:BAAANQAECgQIBAAAAA==.',
Ne='Necrodancer:BAAANQAECggIAgAAAA==.Necrogore:BAAANQADCgcIBwAAAA==.Neildasstysn:BAAANQAECgYICQAAAA==.Nemezyz:BAAANQADCgQIBAAAAA==.Nephey:BAAANQADCgMIAwAAAA==.Neverdruid:BAAANQADCgEIAQAAAA==.Neveya:BAAANQADCgUICQAAAA==.Newtlid:BAAANQAECgQIBAAAAA==.',
Ni='Nickeld:BAAANQAECgYICQAAAA==.Nickhy:BAAANQADCggIEAAAAA==.Nietherme:BAAANQAECgQIBQAAAA==.Nietheryew:BAAANQADCgIIAgAAAA==.',
No='Noblefiend:BAAANQADCgQIBAAAAA==.Nolife:BAAANQADCgQIBAAAAA==.Norinithedra:BAAANQADCgMIAwAAAA==.',
Ny='Nyagosa:BAAANQAECgUIBQAAAA==.Nyalore:BAAANQAECgMIBAAAAA==.',
Ob='Obiwinonly:BAAANQADCgIIAgAAAA==.',
Oh='Ohnjaxx:BAAANQAECgEIAQAAAA==.',
Or='Oraedia:BAAANQAECggIDwAAAA==.Oralen:BAABNQAECoEcAAMOAAgJDB/aDQD6AgAOAAgJDB/aDQD6AgAEAAIJbQ+wwgBzAAAAAA==.Orilitha:BAAANQADCgYIDAAAAA==.Orlandris:BAAANQADCgQIBQAAAA==.Orndaith:BAAANQAECggICwAAAA==.',
Ov='Overloader:BAAANQAECgQIBgAAAA==.',
Ox='Oxkenpachixo:BAAANQADCgMIAwAAAA==.',
Oy='Oyabun:BAAANQADCgYIBgAAAA==.',
Pa='Pairodeez:BAAANQADCgMIAQAAAA==.Pallyaxe:BAAANQADCggICQABNQAECgcIEgABAAAAAA==.Pandawannabe:BAAANQADCgMIBwAAAA==.Pandussi:BAAANQAECgcIDQAAAA==.Paneer:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Paninus:BAAANQAECgEIAQAAAA==.Papawheelie:BAAANQADCgcIBwAAAA==.',
Pe='Pebbletoe:BAAANQADCgUIBQAAAA==.Perfectplex:BAAANQABCgUIBQAAAA==.Peruano:BAAANQAECgUICQAAAA==.Petforheals:BAAANQAECgQIBgAAAA==.',
Ph='Phyett:BAAANQADCgEIAQABNQADCgMIBwABAAAAAA==.',
Pi='Pietastegood:BAAANQAECgYIEAAAAA==.Pigbeniz:BAAANQABCgIIAgAAAA==.Pikaboom:BAAANQADCgYIBgABNQAECgcIBwABAAAAAA==.Pintsizemage:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.Pitchblack:BAAANQAECgQIAwAAAA==.',
Po='Pocahöntas:BAAANQADCgUIBQAAAA==.Pocketrocket:BAAANQADCgUIBgAAAA==.Ponce:BAAANQAECgcIEwAAAA==.Poordemon:BAAANQADCgUIBQABNQAECgUICgABAAAAAA==.Popehealz:BAAANQADCgYIBgAAAA==.',
Pr='Predatori:BAAANQADCgIIAgAAAA==.Priestofholy:BAAANQADCgYIDQAAAA==.Provolonie:BAAANQADCggIDAAAAA==.Proñto:BAAANQAECgEIAQABNQAECgYIDAABAAAAAA==.Pròntò:BAAANQADCgQIBAABNQAECgYIDAABAAAAAA==.Prõntõ:BAAANQADCgEIAQABNQAECgYIDAABAAAAAA==.Prøntø:BAAANQAECgYIDAAAAA==.',
Pu='Puffthemagic:BAAANQADCgYICQABNQAECggIEQABAAAAAA==.Punchbugman:BAAANQADCggIDAAAAA==.Puritos:BAAANQADCgcIBwAAAA==.Pustain:BAAANQABCgYIBgAAAA==.',
Py='Pymera:BAAANQAECgMIAwAAAA==.Pyrista:BAAANQAECgMIAwAAAA==.',
Qo='Qortethpally:BAAANQADCgQIBAAAAA==.',
Qu='Quinte:BAEANQABCgQIBAAAAA==.',
Ra='Radetoo:BAAANQAECgQIBgAAAA==.Radilas:BAAANQABCgIIAgAAAA==.Radioatlarge:BAAANQADCgUIBQABNQAECgYIEAABAAAAAA==.Raendarth:BAAANQAECgIIAgAAAA==.Rageth:BAAANQAECgQIBgAAAA==.Rakalaag:BAEANQADCgYICgAAAA==.Rakath:BAAANQADCgcIFQAAAA==.Ramidus:BAAANQAECgQIBgAAAA==.Ranciid:BAAANQADCgIIAwAAAA==.Rasmis:BAAANQAECgcIDQAAAA==.',
Re='Reck:BAAANQAECggIEQAAAA==.Rejuve:BAAANQADCgYIBgAAAA==.Rektify:BAAANQADCgEIAQAAAA==.Renwick:BAAANQAECgEIAQABNQAFFAIIAwABAAAAAA==.Restlece:BAAANQABCgEIAQAAAA==.Reunach:BAAANQAECgUIBgAAAA==.',
Rh='Rhahirn:BAAANQADCgEIAQAAAA==.Rhialto:BAAANQADCgIIAgAAAA==.Rhinopill:BAAANQADCggICAABNQAECggIEwABAAAAAA==.Rhyzand:BAAANQADCgIIAwAAAA==.',
Ri='Riasg:BAAANQADCgIIAgAAAA==.Rickilake:BAAANQADCggIEgAAAA==.Ricksanchez:BAAANQAECgIIAwAAAA==.Rinik:BAAANQAECgYICwAAAA==.Riptiide:BAAANQADCgcIBwABNQADCggIDgABAAAAAA==.Rivendra:BAAANQADCggIFQAAAA==.Riverpixie:BAAANQADCgQIBAAAAA==.',
Ro='Rockabye:BAAANQAECgYIDQAAAA==.Rosannas:BAAANQADCgUIAgABNQAECggIEwABAAAAAA==.Rosi:BAAANQADCggICAAAAA==.Royallz:BAAANQAECgIIAgAAAA==.',
Ru='Rudeknees:BAABNQAECoEfAAMPAAkJnRS8HQCEAgAPAAkJnRS8HQCEAgAQAAUJfAIZGQDBAAAAAA==.Ruibash:BAEBNQAECoEbAAIEAAgJvh1gIQCeAgAEAAgJvh1gIQCeAgAAAA==.Runebladé:BAAANQAECgQIBAAAAA==.',
Ry='Ryuu:BAAANQADCggIDAAAAA==.',
Sa='Sacredknight:BAAANQADCgQIBQAAAA==.Saikoumaster:BAAANQAECgEIAQAAAA==.Sakuraa:BAAANQAECgIIAgAAAA==.Sarajean:BAAANQADCgQIBAAAAA==.Savaged:BAAANQADCgcIDAABNQAECgUIEgABAAAAAA==.Savajed:BAAANQAECgUIEgAAAA==.',
Sc='Scallywagg:BAAANQADCggICQAAAA==.Scarletmatch:BAAANQAECgIIAgAAAA==.',
Se='Searcomic:BAAANQAECgUICAAAAA==.Secondwall:BAAANQADCgMIAwAAAA==.Seldav:BAABNQAECoEYAAMJAAkJxRbBAgCZAgAJAAkJxRbBAgCZAgARAAIJpQe6IgBxAAAAAA==.Selendas:BAAANQADCgQIBAAAAA==.Selessa:BAAANQADCggICgAAAA==.Selm:BAAANQAECgYICwAAAA==.',
Sh='Shadedluster:BAAANQADCgQIBQAAAA==.Shaleka:BAAANQADCgUICAAAAA==.Shaluesta:BAAANQADCgcIBwAAAA==.Shamanism:BAAANQAECgQIBAAAAA==.Shameless:BAAANQAECgYICgAAAA==.Shamwów:BAAANQAECgUIDAAAAA==.Sharco:BAABNQAECoEVAAINAAYJlR+GBAAhAgANAAYJlR+GBAAhAgAAAA==.Sharkbites:BAAANQAECgIIAgAAAA==.Shawarmafury:BAABNQAECoEdAAILAAkJvSYpAAALBAALAAkJvSYpAAALBAAAAA==.Shiirou:BAAANQADCgQIBAAAAA==.Shooshmael:BAAANQAECgUICQAAAA==.Shozo:BAAANQADCgQIBAABNQAECgYICwABAAAAAA==.Shékinah:BAAANQAECgcIEwAAAA==.',
Si='Sidesteppin:BAAANQADCgUICAAAAA==.Silirazzle:BAAANQADCgMIAwAAAA==.Sinsister:BAAANQAECgMIAwAAAA==.Sinthein:BAAANQAECgMIBQABNQAFFAIIAwABAAAAAA==.',
Sk='Skadgrip:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Skorpekh:BAAANQAECgQICAAAAA==.Skyle:BAAANQADCgQIBAAAAA==.Skypanties:BAAANQAECgQIBgAAAA==.',
Sl='Sleepingsun:BAAANQAECgUICQAAAA==.Sloppyspikes:BAAANQAECgMIBAAAAA==.',
Sm='Smakm:BAAANQADCgEIAQAAAA==.Smidgenn:BAAANQADCgcIDAAAAA==.Smokyblast:BAAANQAECgEIAQAAAA==.Smolden:BAAANQABCgEIAQAAAA==.',
Sn='Snailtrails:BAAANQADCgcIEAAAAA==.Sneakgooner:BAAANQADCgcIBwAAAA==.Snowball:BAABNQAECoEYAAIKAAYJAQNZ8gDZAAAKAAYJAQNZ8gDZAAAAAA==.',
So='Sohtan:BAAANQADCgQIBAAAAA==.Sonbrandt:BAAANQAECgIIAgAAAA==.Soulforge:BAAANQADCgQIBAAAAA==.Soulread:BAAANQAECgIIAgAAAA==.',
Sp='Sparowprince:BAABNQAECoEhAAIEAAkJHyAEEAAiAwAEAAkJHyAEEAAiAwAAAA==.Speccurious:BAAANQADCgYIBwAAAA==.Spectraleye:BAAANQAECgMIBAAAAA==.Sproocherlou:BAAANQAECggIDAAAAA==.Sprour:BAAANQAECgQIBgAAAA==.',
St='Stankbolt:BAAANQAECgIIAwAAAA==.Steezya:BAAANQAECgUICAAAAA==.Stegulos:BAAANQABCgEIAQABNQABCgIIAwABAAAAAA==.Stellarum:BAAANQAECgMIAwAAAA==.Stormykitty:BAAANQAECgYIDgAAAA==.Striderdh:BAAANQABCgYIBgAAAA==.Strongwoman:BAAANQAECgEIAQAAAA==.Sturtza:BAABNQAECoEaAAILAAkJNBo+EwDdAgALAAkJNBo+EwDdAgAAAA==.',
Su='Subarashi:BAAANQADCgYIBgAAAA==.Sukmybigtoe:BAAANQADCgIIAQAAAA==.Sunbear:BAAANQADCgYICAAAAA==.Suun:BAAANQAECgYIEAAAAA==.',
Sw='Swampassuti:BAAANQAECgEIAQAAAA==.Swoley:BAAANQAECgQICAAAAA==.',
Sy='Sylphia:BAAANQADCgYIBgAAAA==.Syrina:BAAANQADCgQIBAAAAA==.',
Ta='Taelandas:BAAANQADCgQIDQAAAA==.Tagobeets:BAAANQAECgUICQAAAA==.Tailyn:BAAANQADCgUIBQAAAA==.Taleiya:BAAANQAECgEIAgAAAA==.Talisaie:BAAANQAECgEIAQABNQAECgkJFwASAIQlAA==.Tanisatharae:BAAANQADCgYIDgABNQAECgMIAwABAAAAAA==.Tarahse:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.Taron:BAAANQAECgIIAgAAAA==.Tart:BAAANQAECgcIEQABNQAECgkJGgAKAIUeAA==.',
Te='Tedjones:BAAANQAECgQIBgAAAA==.Temupeggy:BAAANQADCgEIAQAAAA==.',
Tg='Tgbird:BAAANQADCgQIBAAAAA==.',
Th='Thegirth:BAAANQAECggICwAAAA==.Thehumanatee:BAAANQAECgQICQAAAA==.Theunholyone:BAAANQADCgcIDQAAAA==.Thilidan:BAAANQADCgEIAQAAAA==.Thingytoo:BAAANQADCgUICwAAAA==.Thiqq:BAAANQADCggICAAAAA==.Threlindrier:BAAANQADCgQIBAAAAA==.Throbinggimp:BAAANQADCggICAAAAA==.Thurien:BAAANQADCgYIBgAAAA==.Thyphlo:BAAANQAECgEIAgAAAA==.',
Ti='Tiltedup:BAAANQAECggIDwAAAA==.Tinesa:BAAANQADCgQIBQAAAA==.Tirich:BAAANQADCggICAABNQAFFAIIAwABAAAAAA==.Titaintium:BAAANQAECgQIBAABNQAECgQIBgABAAAAAA==.',
To='Toshi:BAAANQAECgQIBQAAAA==.Totemtree:BAAANQADCgMIAwABNQAECgUICAABAAAAAA==.',
Tr='Trustmei:BAAANQAECgQIAwAAAA==.Trystin:BAAANQAECgIIAgAAAA==.',
Tu='Tullydin:BAAANQAECgQICQAAAA==.Tullyy:BAAANQADCgMIAgAAAA==.Tums:BAAANQAECgYIDQAAAA==.',
Tw='Twirls:BAAANQAECgUICgAAAA==.Twistoffate:BAAANQAECgEIAgAAAA==.',
Ty='Tyerant:BAAANQADCgMIAgAAAA==.Tylenill:BAAANQADCgQIBAAAAA==.',
Ug='Uglygoat:BAAANQADCgEIAQAAAA==.',
Um='Umbrasanctus:BAAANQADCgUIBgAAAA==.',
Ur='Urtle:BAAANQADCggIFAAAAA==.',
Us='Uselece:BAAANQAECgcIDgAAAA==.',
Ut='Uthadandewey:BAAANQADCgcIBwAAAA==.',
Va='Valgorr:BAAANQAECgIIAQAAAA==.Valvalon:BAAANQAECgMIAwAAAA==.',
Ve='Veelaria:BAAANQAECgQIBgAAAA==.Vegetablue:BAAANQAECgEIAQAAAA==.Vet:BAAANQAECgQIBwAAAA==.',
Vh='Vhelithiana:BAAANQADCgYICwAAAA==.',
Vi='Viathun:BAAANQADCggICAABNQAECgUIEgABAAAAAA==.Vicalaus:BAAANQAECgUICwABNQAECgYIEQABAAAAAA==.View:BAAANQAECggIEAAAAA==.Vikcy:BAAANQADCgYICwAAAA==.Vilified:BAAANQADCgQICwAAAA==.Vitros:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.',
Vo='Voidbren:BAAANQADCgEIAQABNQAECgQIBwABAAAAAA==.Voidwitch:BAAANQAECgEIAgAAAA==.Volstagg:BAAANQADCgMIAwAAAA==.',
Vr='Vrakken:BAAANQADCggICAAAAA==.',
Vy='Vyndenus:BAAANQAECgcIDQAAAA==.',
Wa='Warriorluv:BAAANQADCgEIAQAAAA==.Warrwing:BAAANQADCgcIBwAAAA==.',
We='Webbfury:BAAANQADCggIFAAAAA==.Wespoo:BAAANQAECgQIBQAAAA==.Wetpug:BAAANQADCgUIBQAAAA==.',
Wh='Whupsmarse:BAAANQADCgYIBgAAAA==.',
Wi='Wifeyaggroed:BAAANQADCgIIAgAAAA==.Wiggles:BAAANQABCgEIAQAAAA==.Wiglock:BAAANQADCgQIBAAAAA==.Wigpetval:BAAANQAECgQIDAAAAA==.Wiidge:BAAANQAECgEIAQAAAA==.Wildside:BAAANQADCgUIBwAAAA==.Willregret:BAAANQAECgMIBQAAAA==.Winterbane:BAAANQAECgQIBAAAAA==.',
Wo='Wocky:BAAANQAECgQIBwAAAA==.Wolfchan:BAAANQABCgYICQAAAA==.Worldcrafter:BAAANQAECgMIAwAAAA==.Worldender:BAAANQAECgQIBQAAAA==.',
Wr='Wreckross:BAAANQABCgMIAwAAAA==.',
Xa='Xantry:BAABNQAECoEYAAIEAAkJ1yLyCABuAwAEAAkJ1yLyCABuAwAAAA==.',
Xm='Xmen:BAAANQAECggIAQAAAA==.',
Xy='Xymm:BAAANQADCgQIBQAAAA==.',
Ye='Yeastybush:BAAANQAECgYIDQAAAA==.',
Ys='Yseeraa:BAAANQAECgEIAQAAAA==.',
Za='Zalatoes:BAAANQADCggIFQAAAA==.Zarathea:BAAANQADCggICAAAAA==.',
Zi='Zilphah:BAAANQADCgMIAwAAAA==.Zimmerwitch:BAAANQADCggIDgAAAA==.Zimms:BAAANQAECgUIBwAAAA==.',
Zo='Zoeyredbird:BAAANQAECgMIAwAAAA==.Zongo:BAAANQADCgcIBwAAAA==.',
Zw='Zwhitty:BAAANQADCgcIBwAAAA==.',
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
