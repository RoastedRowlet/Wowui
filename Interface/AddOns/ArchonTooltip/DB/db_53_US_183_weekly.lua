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

local lookup = {'Unknown-Unknown','DeathKnight-Unholy','Paladin-Retribution','Shaman-Restoration',}
local provider = {region='US',realm='Saurfang',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abbeyroad:BAAANQADCgMIAwAAAA==.',
Ad='Adnauseam:BAAANQAECgQICAAAAA==.',
Ae='Aedaenia:BAAANQADCgYIBgAAAA==.Aelyndara:BAAANQADCgQICAAAAA==.',
Ag='Agave:BAAANQADCgYIBgAAAA==.Aglerion:BAAANQADCgYIBgAAAA==.',
Ah='Ahlya:BAAANQAECgMIAwAAAA==.',
Ai='Aimei:BAAANQADCggIDgAAAA==.Aiphaton:BAAANQADCgcIDQAAAA==.',
Aj='Ajchmiel:BAAANQADCgQICAAAAA==.',
Ak='Akanea:BAAANQADCgIIAgAAAA==.Ake:BAAANQAECgQIBAAAAA==.Akàmè:BAAANQAECgIIAgAAAA==.',
Al='Aldavyr:BAAANQAECgUIBgAAAA==.Aldrick:BAAANQADCgUIBQAAAA==.Alienas:BAAANQADCgUIBQAAAA==.Alighieri:BAAANQADCggIDAAAAA==.Alinassa:BAAANQAECgIIAgAAAA==.Allacore:BAAANQADCgUIBgAAAA==.Alponyoman:BAAANQADCgMIAwAAAA==.',
Am='Amaizen:BAAANQADCgUIBgAAAA==.Ameilioli:BAAANQABCgIIAgAAAA==.Amorthian:BAAANQADCgcIBwAAAA==.',
An='Andrak:BAAANQADCgUIBQAAAA==.Angelock:BAAANQABCgEIAQAAAA==.Angertotem:BAAANQADCgcICQAAAA==.Angrboda:BAAANQADCgEIAQABNQADCggIDwABAAAAAA==.Angusmac:BAAANQADCgcIBwAAAA==.Anhailah:BAAANQAECgMIAwAAAA==.Animos:BAAANQAECgMIAwAAAA==.Annarah:BAAANQAECgIIAgAAAA==.Anthropocene:BAAANQADCgIIAgAAAA==.',
Ap='Appowulf:BAAANQAECgQIBgAAAA==.',
Aq='Aquamangue:BAAANQAECgQIBQAAAA==.',
Ar='Aragornne:BAAANQADCgYICAAAAA==.Arcanemage:BAAANQADCgYICAAAAA==.Archeuz:BAAANQADCgUICAAAAA==.Arkdan:BAAANQADCgMIAwAAAA==.Arnoon:BAAANQAECgQIBQAAAA==.Arogance:BAAANQAECgQIBAAAAA==.',
As='Ashreever:BAAANQADCgUIBQAAAA==.Asmodan:BAAANQAECgEIAQAAAA==.',
At='Attonrand:BAAANQADCggIDgAAAA==.',
Au='Ausarrow:BAAANQADCggIDgAAAA==.Ausdruid:BAAANQADCgQIBAAAAA==.',
Av='Avianori:BAAANQADCgUIBQAAAA==.Avie:BAAANQAFFAIIAwAAAA==.',
Ax='Axelfoley:BAAANQADCgIIAgAAAA==.',
Az='Azraezel:BAAANQAECgEIAQAAAQ==.Azzinot:BAAANQADCgUIBgAAAA==.',
['Aã']='Aãri:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.',
Ba='Babàyaga:BAAANQADCgQIBAABNQADCgcIBwABAAAAAA==.Barthom:BAAANQAECgQICgAAAA==.Baràk:BAAANQAECgQIDAAAAA==.',
Be='Bearzmage:BAAANQAECgMIAwAAAA==.Beatrix:BAAANQADCgYICAAAAA==.Bedebah:BAAANQAECgIIAgAAAA==.Beebeecee:BAAANQADCgIIAwAAAA==.Beerington:BAAANQAECgEIAQAAAA==.Behemoth:BAAANQADCgYICgAAAA==.Berknerkem:BAAANQADCggIDQAAAA==.Bewmz:BAAANQADCgcIBwAAAA==.',
Bi='Bigoltrollop:BAAANQADCggIDgAAAA==.Biscuitcapes:BAAANQADCgQICAAAAA==.',
Bl='Blinkinpark:BAAANQADCgYIBgAAAA==.Bllissterine:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Bllissticks:BAAANQAECgEIAQAAAA==.Bllisstrix:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Blxckbeef:BAAANQAECgQIDAAAAA==.',
Bo='Bombsquad:BAAANQAECgIIAgABNQAECgcICwABAAAAAA==.Bornewithit:BAAANQAECgQIDAAAAA==.Borttheblade:BAAANQAECgYICwAAAA==.',
Br='Brandyshot:BAAANQADCggIDgAAAA==.Brewtalîty:BAAANQADCgYIBgAAAA==.Briar:BAAANQADCgYIBgAAAA==.Brush:BAAANQAECgQIBAAAAA==.Bruvski:BAAANQAECgMIAgAAAA==.',
Bw='Bwthhybl:BAAANQADCgcIDQAAAA==.',
By='Bytes:BAAANQAECgEIAQAAAA==.',
['Bü']='Bünny:BAAANQAECgMIAwAAAA==.',
Ca='Cairnless:BAAANQADCggIDQAAAA==.Cakesrlife:BAAANQAECgQIBAAAAA==.Captcinder:BAAANQADCgMIAwAAAA==.Caselorc:BAAANQADCgUICgAAAA==.Cata:BAAANQADCgcIDAAAAA==.Catscythe:BAAANQADCggIDAAAAA==.Cauthon:BAAANQADCgcICQAAAA==.Cavemanwar:BAAANQADCgQIBAABNQAECgYICwABAAAAAA==.',
Ce='Celtic:BAAANQAFFAIIAgAAAA==.Ceredan:BAAANQADCgcIDAAAAA==.',
Ch='Challisa:BAAANQADCgEIAQAAAA==.Chaoskane:BAAANQADCgcIDQAAAA==.Charnaby:BAAANQAECgQIBAAAAA==.Cheeksmasher:BAAANQAECgEIAQAAAA==.Cheesesteaks:BAAANQADCgcIDwAAAA==.Chellê:BAAANQADCggIDgAAAA==.Chicknburgah:BAAANQAECgcIDQAAAA==.Chocorondo:BAAANQAECgQIBAAAAA==.Chokystafish:BAAANQADCgUIBQAAAA==.Chonkmagic:BAAANQADCggIDwAAAA==.Chovabub:BAAANQADCgUICgAAAA==.Chowhai:BAAANQADCgMIAwAAAA==.',
Ci='Circus:BAAANQAECgIIAgAAAA==.',
Co='Corte:BAAANQAECgQICgAAAA==.Coverghoul:BAABNQAECoEbAAICAAgJRBJVEAAuAgACAAgJRBJVEAAuAgABNQAECggJGwACAEQSAA==.',
Cr='Crazedorc:BAAANQAECgIIAgAAAA==.Creamymoot:BAAANQADCgYICgAAAA==.Croescrane:BAAANQAECgQIBAAAAA==.Crooked:BAAANQADCggIDgAAAA==.',
Cy='Cynthus:BAAANQAECgIIBgAAAA==.',
['Cé']='Cérberus:BAAANQADCggIDQAAAA==.',
Da='Damador:BAAANQAECgQIBAAAAA==.Damisia:BAAANQAECgEIAQAAAA==.Damuss:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Danirumi:BAAANQAECgEIAQAAAA==.Danithir:BAAANQADCgQIBQAAAA==.Danndk:BAAANQAECgQIBAAAAA==.Danndruid:BAAANQADCgEIAQAAAA==.Dannsham:BAAANQADCgIIAwAAAA==.Darkiller:BAAANQADCgEIAgAAAA==.Darksox:BAAANQADCgcIDQAAAA==.Daylisha:BAAANQAECgEIAQAAAA==.Dayn:BAAANQADCggIDwAAAA==.Dazzles:BAAANQAECgIIBAAAAA==.',
De='Deabloknight:BAAANQAECgEIAQAAAA==.Deablosrage:BAAANQAECgEIAQAAAA==.Deathraider:BAAANQAECgMIAwAAAA==.Ded:BAAANQAECgYIBgAAAA==.Demongasher:BAAANQADCgEIAQAAAA==.Demonmus:BAAANQADCgcIBwAAAA==.Demonpandaz:BAAANQAECgIIAgAAAA==.Dessa:BAAANQADCggIDQABNQAECgEIAQABAAAAAA==.Dessane:BAAANQAECgEIAQAAAA==.',
Di='Dijonmustard:BAAANQADCgcIDAAAAA==.Diora:BAAANQAECgIIAwAAAA==.',
Dk='Dkdence:BAAANQAECgQIBQAAAA==.',
Do='Donfandangle:BAAANQADCgQICAAAAA==.Donkeykongg:BAAANQAECgcICwAAAA==.Doofyspally:BAAANQADCgYIBgAAAA==.Doomadin:BAAANQAECgQIDAAAAA==.Dora:BAAANQADCgYICwAAAA==.Dovarkin:BAAANQAECgMIAwAAAA==.',
Dr='Drabsysham:BAAANQAECgcIDQAAAA==.Dracarsynimz:BAEANQAECgQICgAAAQ==.Draczr:BAAANQAECgQIBwAAAA==.Dragritt:BAAANQAECgEIAQABNQAECgcIDAABAAAAAA==.Dragritto:BAAANQAECgcIDAAAAA==.Dragsham:BAAANQADCgQIBAABNQAECgcIDAABAAAAAA==.Dragönshade:BAAANQAECgQICgAAAA==.Drakage:BAAANQADCgMIAwAAAA==.Drakana:BAAANQAECgEIAQAAAA==.Draykora:BAAANQAECgUIBQAAAA==.Drazzig:BAAANQADCgMIAwAAAA==.Dreambreaker:BAAANQADCgYICwAAAA==.Drewzus:BAAANQAECgEIAQAAAA==.Drexanoth:BAAANQADCgQIBAAAAA==.Drusindra:BAAANQADCgQICAAAAA==.',
Du='Dudeman:BAAANQADCgYIBgAAAA==.Durabull:BAAANQADCgEIAQAAAA==.',
Dw='Dwarfz:BAAANQAECgQIBwAAAA==.',
Ea='Earthbreaker:BAAANQAECgEIAgAAAA==.',
Ed='Edavv:BAAANQADCgQICAABNQAECgIIBAABAAAAAA==.Edmo:BAAANQAECgIIAgAAAA==.Edrandil:BAAANQAECgQIBQAAAA==.',
Ee='Eevula:BAAANQADCgEIAQAAAA==.',
Ei='Eiluaq:BAAANQADCggIGAAAAA==.Eirianna:BAAANQADCgQICAAAAA==.',
El='Elcrabbette:BAAANQADCgcIDgAAAA==.Elegant:BAAANQADCggIDQAAAA==.Elemelôn:BAAANQADCgcIDQABNQAECgQICgABAAAAAA==.Elundara:BAAANQAECgQIBQAAAA==.',
Eq='Eq:BAAANQADCgcIDAAAAA==.',
Es='Estardra:BAAANQADCggIDgAAAA==.',
Ev='Evelice:BAAANQAECgMIBAAAAA==.Evilnattie:BAAANQAECgQIBAAAAA==.',
Ex='Exajoule:BAAANQADCgUIBQABNQAECgQICgABAAAAAA==.Exiledpally:BAAANQADCgQIBAAAAA==.',
Fa='Faeryall:BAAANQAECgEIAgAAAA==.Fakeyoda:BAAANQAECgEIAQAAAA==.Falua:BAAANQAECgQIBAAAAA==.Faranight:BAAANQADCggIDQAAAA==.Fatherspark:BAAANQADCgEIAQAAAA==.',
Fb='Fba:BAAANQAECggIAwAAAA==.',
Fe='Fefeasa:BAAANQADCgQIBQAAAA==.Feistyfist:BAAANQADCggIDgAAAA==.Fenglei:BAAANQADCgcIDQABNQAECgcIDQABAAAAAA==.Fengliu:BAAANQAECgcIDQAAAA==.Fennik:BAAANQADCgIIAgAAAA==.Fenriz:BAAANQADCgYIDAAAAA==.',
Fi='Fieryroota:BAAANQAECgQICgAAAA==.Findewin:BAAANQADCggIDgAAAA==.Fiyerite:BAAANQAECgUIBgAAAA==.Fizzypal:BAAANQADCggIDgAAAA==.',
Fl='Flameeater:BAAANQAECgQIBAAAAA==.Flynnyzyzz:BAAANQAECgQIDAAAAA==.',
Fo='Folk:BAAANQABCgIIAgAAAA==.',
Fr='Franked:BAAANQADCgQIBAAAAA==.Frogster:BAAANQADCgMIAwAAAA==.Frogwash:BAAANQADCgMIAwABNQAECgUIBgABAAAAAA==.',
Fu='Furrylock:BAAANQAECgQICAAAAA==.',
Fy='Fyaha:BAAANQADCgQICAAAAA==.',
['Fú']='Fúzzlë:BAAANQADCggIDgAAAA==.',
Ga='Gadgetgeek:BAAANQADCgMIAwAAAA==.Galeidan:BAAANQADCggIDgAAAA==.Gameoftroll:BAAANQAECgQIBQAAAA==.Gamumush:BAAANQAECgQIBQAAAA==.Gamush:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Gargola:BAAANQADCgYIBgAAAA==.Garntek:BAAANQADCggIDgAAAA==.Garókk:BAAANQADCgYICgAAAA==.',
Ge='Geauxphreigh:BAAANQAECgEIAQAAAA==.',
Gh='Ghostbom:BAAANQADCgIIAgAAAA==.',
Gi='Giggels:BAAANQAECgQIBAAAAA==.Gilletté:BAAANQADCgYICwAAAA==.',
Gl='Glaiviture:BAAANQADCgcIDQAAAA==.',
Go='Goodgravy:BAAANQADCgMIAwAAAA==.Gorenrisao:BAAANQAECgEIAgABNQAECgMIBAABAAAAAA==.Gotsalt:BAAANQAECgQIBQAAAA==.Gotsdots:BAAANQAECgcIDQAAAA==.',
Gr='Greendoor:BAAANQAECgIIAgAAAA==.Gren:BAAANQADCgUIBgAAAA==.Growvert:BAAANQAECggIDgAAAA==.',
['Gé']='Gémini:BAAANQADCgIIAgAAAA==.',
['Gø']='Gødslapp:BAAANQAECgEIAQAAAA==.',
Ha='Hahwei:BAAANQADCgYICwAAAA==.Hailej:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Halianubran:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.Halliday:BAAANQAECgQIBgAAAA==.Harraktas:BAAANQAECgQIBAAAAA==.Harrowhark:BAAANQADCgYICgAAAA==.Harvestmoon:BAAANQADCgQIBAAAAA==.Haxxor:BAAANQADCgYICAAAAA==.',
He='Healiia:BAAANQAECgQIBQAAAA==.Hellsîng:BAAANQAECgUIBQABNQAECgcIDQABAAAAAA==.Hellà:BAAANQADCgUICAAAAA==.Helynna:BAAANQADCgUIBQAAAA==.Hendo:BAAANQADCggIDgAAAA==.Hepatitan:BAAANQADCgIIAgAAAA==.Hexecuted:BAAANQADCgcIDAAAAA==.Heyyaits:BAAANQAECgcICwAAAA==.',
Hi='Hikahi:BAAANQADCgUIBQAAAA==.',
Ho='Holdmyaggro:BAAANQAECgQICgAAAA==.Holdmyballz:BAAANQAECgEIAgAAAA==.Hollyballz:BAAANQADCgYIBgAAAA==.Holyberry:BAAANQAECgIIBgAAAA==.Holynovna:BAAANQADCgYICAAAAA==.Holè:BAAANQAECgQIBAAAAA==.Hotstreakqt:BAAANQADCgQICAAAAA==.Hotzug:BAAANQADCgIIAgAAAA==.Houyix:BAAANQADCgYIBgAAAA==.Howdowhodo:BAAANQADCgMIAwAAAA==.',
Hr='Hreeza:BAAANQADCgcIDAAAAA==.',
Hu='Huntssy:BAAANQAECgIIAgAAAA==.Huuag:BAAANQAECgEIAQAAAA==.',
Hy='Hypersleep:BAAANQADCggIDgAAAA==.',
['Hì']='Hìkàrì:BAAANQADCgMIAwAAAA==.',
['Hö']='Hötnhòrdey:BAAANQAECgEIAQAAAA==.',
['Hø']='Høstile:BAAANQADCgQICAAAAA==.',
Ii='Ii:BAAANQADCgcIBwAAAA==.Iisildur:BAAANQAECgIIBAAAAA==.',
Im='Imaginative:BAAANQAECgcICgAAAA==.Imcooked:BAAANQAECgcICwAAAA==.Imfiredupp:BAAANQAECggIAQAAAA==.Imladrisse:BAAANQADCgYICwAAAA==.',
In='Inkmouse:BAAANQAECgMIAwAAAA==.',
Ir='Irispearl:BAAANQADCgQICAAAAA==.Ironfistt:BAAANQAECgcICwAAAA==.',
Is='Isolde:BAAANQADCgYICQAAAA==.',
Iv='Ivar:BAAANQAECgQIBQAAAA==.',
Ja='Jacksmash:BAAANQADCgYIDgAAAA==.Jaideep:BAAANQADCgIIAgAAAA==.Jaminmyclam:BAAANQADCgcIDQAAAA==.Jamitydk:BAEANQAECgIIAgAAAA==.Jarnzarn:BAAANQADCggIEAAAAA==.Jarviltinn:BAAANQAECgMIBAAAAA==.',
Je='Jelia:BAAANQAECgQIBQAAAA==.Jelyah:BAAANQAECgMIAwABNQAECgQIBQABAAAAAA==.Jerô:BAAANQADCgYICAAAAA==.',
Jo='Jobbey:BAAANQAECgEIAQAAAA==.Jonkerstien:BAAANQAECgQIBAAAAA==.Jorgie:BAAANQADCgcIDQABNQADCggIDgABAAAAAA==.Joyous:BAAANQADCggIDgAAAA==.',
Ju='Juelz:BAAANQADCgIIAgAAAA==.Jumbosausage:BAAANQAECgIIAgAAAA==.Jungchi:BAAANQADCgcIDAAAAA==.Junior:BAAANQAECgMIAwAAAA==.',
Ka='Kahahn:BAAANQABCgIIAwAAAA==.Kakana:BAAANQADCgUIBwAAAA==.Kamui:BAAANQAECgMIBAAAAA==.Kanamè:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Kanfer:BAAANQADCgUIAwABNQADCgUIBQABAAAAAA==.Kariala:BAAANQAECgEIAQAAAA==.Katilaine:BAAANQADCgQICAAAAA==.Kayadrac:BAAANQAECgQIBQAAAA==.',
Ke='Keksiq:BAAANQAECgMIAwAAAA==.Keshae:BAAANQAECgQIBAAAAA==.',
Ki='Kidfork:BAAANQAECgEIAQAAAA==.Killasham:BAAANQADCgcIDQAAAA==.Killika:BAAANQADCgYIBQABNQAECgQIBAABAAAAAA==.Kinndred:BAAANQAECgMIBgAAAA==.Kintolina:BAAANQADCgIIAgAAAA==.Kiralia:BAAANQAECgQIDAAAAA==.Kirigolmer:BAAANQADCgcIDAAAAA==.',
Kn='Kngleonidas:BAAANQADCgYIBgAAAA==.',
Ko='Kokoy:BAAANQAECgQIBQAAAA==.',
Kr='Krackd:BAAANQADCggICQAAAA==.Kraelyk:BAAANQADCgMIBAAAAA==.Krazan:BAAANQAECgMIBgAAAA==.Krygore:BAAANQADCgcIDAAAAA==.',
Ku='Kunehoboy:BAAANQADCgYIBgAAAA==.Kungfufeet:BAAANQADCgQIBQAAAA==.Kurtcobang:BAAANQAECgUIBgAAAA==.Kushie:BAAANQAECgEIAQAAAA==.',
['Ká']='Kál:BAAANQAECgEIAQAAAA==.',
['Kø']='Kørndawg:BAAANQADCgYIDAAAAA==.',
La='Lagior:BAAANQAECgMIAwAAAA==.Laikaboss:BAAANQADCgQIBAAAAA==.Lasind:BAAANQADCgQICAAAAA==.Lawu:BAAANQAECgQIBQAAAA==.',
Le='Learrit:BAAANQAECgIIAgAAAA==.Lecorpse:BAAANQADCgYIBgAAAA==.Lendis:BAAANQADCgIIAgAAAA==.Leviathran:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.',
Li='Librawitch:BAAANQADCgMIAwAAAA==.Lifaène:BAAANQADCgYIDAAAAA==.Lightarcc:BAAANQADCgUICQAAAA==.Lightklobe:BAAANQADCggIDwAAAA==.Lihan:BAAANQADCgcIDAAAAA==.Lilcarabine:BAAANQADCgYIBgAAAA==.Lilindrena:BAAANQADCgUICQAAAA==.Lilmentyb:BAAANQADCggIEAAAAA==.Lilmis:BAAANQADCggIDgAAAA==.Liorawr:BAAANQADCgYICwAAAA==.Lipids:BAAANQADCgYICwAAAA==.Lissuin:BAAANQAECgEIAQAAAA==.',
Ll='Llandrei:BAAANQADCgYICwAAAA==.',
Lo='Locnár:BAAANQAECgIIAgAAAA==.Lollobionda:BAAANQAECgIIAgAAAA==.Loono:BAAANQADCgUICQAAAA==.Lorathiel:BAAANQADCgUIBQAAAA==.',
Lu='Luffytoe:BAAANQADCgMIAwABNQAECgcICwABAAAAAA==.Lulingqï:BAAANQADCgUIBQAAAA==.Lululapoon:BAAANQADCgMIAwAAAA==.Luminei:BAAANQAECgEIAQAAAA==.Lunakiss:BAAANQADCgYIBgAAAA==.Lutz:BAAANQADCggIDgAAAA==.',
Ly='Lynestra:BAAANQAECgYICwAAAA==.Lynmei:BAAANQADCgQICAAAAA==.Lyth:BAAANQADCgIIAgAAAA==.Lythor:BAAANQADCggIDwAAAA==.',
Ma='Mackyla:BAAANQAECgEIAQAAAA==.Macáronì:BAAANQADCgIIAgAAAA==.Mafdett:BAAANQADCgcIDAAAAA==.Mafilrion:BAAANQAECgQIBQAAAA==.Magicae:BAEANQAECgMIBQAAAA==.Magnestra:BAAANQADCgMIAwAAAA==.Mantova:BAAANQAECgEIAQAAAA==.Matt:BAAANQADCgUIBQAAAA==.Matthxw:BAAANQAECgIIAgAAAA==.Mayomonk:BAAANQADCgMIAwAAAA==.Mayzh:BAAANQADCggIDwAAAA==.',
Mc='Mcbain:BAAANQADCgcIDAAAAA==.',
Md='Mdma:BAAANQADCgYIBgAAAA==.',
Me='Melahna:BAAANQAECgMIAwAAAA==.Melwyn:BAAANQADCgcIDAAAAA==.',
Mg='Mgunit:BAAANQADCgYIDAAAAA==.',
Mi='Mikotö:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Milkyjoe:BAAANQAECgUIBwAAAA==.Milkysprayed:BAAANQAECgQIBQAAAA==.Mistajeeves:BAAANQADCgYIBgAAAA==.Mistweaved:BAAANQADCgQIBAAAAA==.Mithras:BAAANQADCgcICAAAAA==.Mithrasxox:BAAANQADCgEIAQABNQADCgcICAABAAAAAA==.',
Mo='Mochinator:BAAANQAECgIIAgAAAA==.Modigularna:BAAANQADCgIIAgAAAA==.Mojojojo:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Mollydooker:BAAANQAECgQICAAAAA==.Monkess:BAAANQADCgIIAgAAAA==.Monkeymagick:BAAANQADCggIDgAAAA==.Monklips:BAAANQAECgIIAgAAAA==.Morbidfetus:BAAANQADCgIIAgAAAA==.Mortassus:BAAANQADCgMIAwABNQADCggICAABAAAAAA==.Mortelunes:BAAANQADCgMIAwAAAA==.Mortira:BAAANQAECgEIAgAAAA==.Morzierz:BAAANQADCgcIDAAAAA==.Mottie:BAAANQADCgQIBAABNQADCgYICgABAAAAAA==.',
Mu='Muaddib:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.Mummadudu:BAAANQADCgUIBgAAAA==.Murkroz:BAAANQAECgQIBAAAAA==.',
My='Mycelia:BAAANQADCgQIBAAAAA==.Myrkvitill:BAAANQADCgUIBQABNQADCggIDwABAAAAAA==.Mystfyre:BAAANQADCgQICAAAAA==.',
['Më']='Mëphistò:BAAANQADCgcIDgAAAA==.',
['Mò']='Mòònshine:BAAANQADCggIDgABNQABCgEIAQABAAAAAA==.',
Na='Naeirm:BAAANQADCgQIBAAAAA==.Naissa:BAAANQADCgMIAwAAAA==.Namewaståken:BAAANQADCggIDAAAAA==.Nasdarath:BAAANQADCgYICAAAAA==.Nato:BAAANQAECgQIBAAAAA==.Naturefire:BAAANQABCgEIAQAAAA==.Navimie:BAEANQADCggIDQAAAA==.',
Ne='Neff:BAAANQADCgYIBgAAAA==.Negus:BAAANQAECgIIAgAAAA==.Nelphey:BAAANQAECgIIAgAAAA==.',
Nh='Nhael:BAAANQADCggIDwAAAA==.',
Ni='Nialdo:BAAANQAECgEIAQAAAA==.Nickwindfury:BAAANQAECgMIBAAAAA==.Nightfarer:BAAANQADCgcIDAABNQAECgEIAQABAAAAAA==.Nightshift:BAAANQADCgYIBgAAAA==.Nikko:BAAANQADCgMIAwAAAA==.Nikno:BAAANQADCgcICAAAAA==.Nips:BAAANQAECgUIBgAAAA==.Nipsymcgeé:BAAANQAECgEIAQAAAA==.Nitegorh:BAAANQADCgEIAQAAAA==.Nixea:BAAANQADCgQIBwAAAA==.',
No='Nogin:BAAANQADCgUIBQAAAA==.Nomby:BAAANQAECgUIBwAAAA==.Noobishly:BAAANQADCgYIBwAAAA==.Noperope:BAAANQADCgEIAQAAAA==.Norinari:BAAANQADCgYIBgAAAA==.Nostradamos:BAAANQADCgEIAQAAAA==.Noyou:BAAANQAECgEIAQAAAA==.',
['Nè']='Nèos:BAAANQAECgEIAQAAAA==.',
['Ní']='Níhilus:BAAANQADCgcIDAAAAA==.',
['Nÿ']='Nÿmber:BAAANQADCgcIDAAAAA==.',
Ob='Obamalives:BAAANQAECgQIBAAAAA==.Obsolve:BAAANQAECgEIAQAAAA==.',
Ol='Olddrekky:BAAANQAECgMIAwAAAA==.Oldegregg:BAAANQAECgIIAgAAAA==.Oldtimér:BAAANQADCgUIBwABNQADCgcIDgABAAAAAA==.',
On='Onikage:BAAANQAECgQIBQAAAA==.Onlyfrends:BAAANQADCggICQAAAA==.',
Or='Orb:BAAANQADCggICAAAAA==.Orobos:BAAANQAECggIBgAAAA==.',
Ot='Othentik:BAAANQAECgEIAQAAAA==.Otl:BAAANQAECgEIAQAAAA==.',
Ov='Overt:BAAANQAECgUICAABNQAECggIDgABAAAAAA==.',
Pa='Palaboodledo:BAAANQADCggIEAAAAA==.Palarsynimz:BAEANQADCggICAABNQAECgQICgABAAAAAA==.Pallyative:BAAANQADCgcIDQAAAA==.Palomar:BAAANQADCggIDwAAAA==.Pancake:BAAANQADCggIDgAAAA==.Para:BAAANQAECgMIBAAAAA==.Pavlovaa:BAAANQADCgcIDQAAAA==.',
Pe='Peepeedemon:BAAANQAECgQIBgAAAA==.Peleiades:BAAANQADCgcIDAAAAA==.Pewpews:BAAANQAECgIIAgAAAA==.',
Pi='Pirrin:BAAANQAECgEIAgAAAA==.',
Pk='Pks:BAAANQAFFAEIAQAAAA==.',
Pn='Pnau:BAAANQAECgIIAgAAAA==.',
Po='Pownrz:BAAANQAECgQIAwAAAA==.',
Pr='Privilege:BAAANQADCgYIDAAAAA==.',
Ps='Psycthyr:BAAANQADCgcICwAAAA==.',
Pu='Purrpleelff:BAAANQAECgEIAgAAAA==.',
['Pä']='Pändörä:BAAANQADCgIIAgABNQADCggIDAABAAAAAA==.',
Qa='Qasqiri:BAAANQADCgcIDQAAAA==.',
Qu='Quack:BAAANQADCggICAAAAA==.Queeshi:BAAANQADCgUIBgAAAA==.',
['Qà']='Qài:BAAANQADCgEIAQAAAA==.',
Ra='Rahj:BAAANQADCgYIBgAAAA==.Rainbowbash:BAAANQADCgMIBgAAAA==.Rainz:BAAANQAECgIIAgAAAA==.Rambro:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.Ranfin:BAAANQAECgQIBgAAAA==.Rare:BAAANQAECgIIAgAAAA==.Rarox:BAAANQADCgIIAgAAAA==.Ravinstep:BAAANQAECgYIBgAAAA==.Rawkalot:BAAANQADCgcIDQABNQAECgQIBAABAAAAAA==.Razs:BAAANQADCggICgAAAA==.Razzles:BAAANQADCgUIBQABNQAECgIIBAABAAAAAA==.',
Re='Redpal:BAABNQAECoEWAAIDAAgJaxziDQBAAgADAAgJaxziDQBAAgAAAA==.Reduvia:BAAANQADCggIDgAAAA==.Reekin:BAAANQAECgIIAgABNQABCgMIAgABAAAAAA==.Rendover:BAAANQADCgUICAAAAA==.',
Rh='Rheagz:BAAANQABCgQIAgAAAA==.',
Ri='Rielta:BAAANQADCggIDwAAAA==.Rightround:BAAANQADCgcIBwAAAA==.Rimrap:BAAANQADCgIIAgAAAA==.',
Ro='Robapaladin:BAAANQADCggICwAAAA==.Robbington:BAAANQADCgUICgAAAA==.Rocketts:BAAANQADCgQICAAAAA==.Rokket:BAAANQAECgEIAQAAAA==.',
Ru='Ruthia:BAAANQAECgIIAgAAAA==.Ruumn:BAAANQADCggIDQAAAA==.',
Ry='Rylaras:BAAANQADCgYICwAAAA==.Ryogen:BAAANQADCggIDgAAAA==.',
['Rê']='Rêvy:BAAANQADCgYIBgAAAA==.',
Sa='Sabretoothed:BAAANQADCgcIDAAAAA==.Saifere:BAAANQAECgIIAgAAAA==.Samanas:BAAANQAECgYICQABNQAECgYICgABAAAAAA==.Sambali:BAAANQADCgYICwAAAA==.Samgamgee:BAAANQADCgYICwAAAA==.Samonki:BAAANQAECgcIDQAAAA==.Samotem:BAAANQADCggICAABNQAECgcIDQABAAAAAA==.Sanctify:BAAANQAECgEIAQAAAA==.Santera:BAAANQADCggIDwAAAA==.Saridana:BAAANQADCgQIBgAAAA==.Satire:BAAANQADCggIDwAAAA==.Savriel:BAAANQAECgMIAwAAAA==.',
Sc='Schnoogans:BAAANQAECgUIBQAAAA==.Scottieboi:BAAANQAECgUIBgAAAA==.Scratchies:BAAANQAECgEIAQAAAA==.Screamdemons:BAAANQADCgYICAAAAA==.Scyadin:BAAANQADCgMIAwAAAA==.Scyler:BAAANQAFFAEIAQAAAA==.',
Se='Seffyre:BAAANQADCgYIBgAAAA==.Seilyre:BAAANQAECgQICAAAAA==.Sekuta:BAAANQAECgYICgAAAA==.Seltic:BAAANQADCggICQAAAA==.Senessara:BAAANQADCgcICwAAAA==.Senjougahara:BAAANQADCgQIBAAAAA==.Seregios:BAAANQAECgIIAgAAAA==.Sevrus:BAAANQADCggICwAAAA==.Seyn:BAAANQADCggIDwAAAA==.',
Sg='Sgtsquat:BAAANQAECgIIBAAAAA==.',
Sh='Shabria:BAAANQAECgEIAQAAAA==.Shadowthief:BAAANQAECgQIDAAAAA==.Shaetore:BAAANQAECgQIBQAAAA==.Shagbark:BAAANQADCggIDgAAAA==.Shambuu:BAAANQAECgMIBQAAAA==.Shammytammy:BAAANQADCgcIDQAAAA==.Sharmtor:BAAANQAECgQIBQAAAA==.Sharzam:BAAANQADCgMIAwAAAA==.Shauthra:BAAANQADCgUIBwAAAA==.Shazamza:BAAANQADCgUIBwAAAA==.Shazzles:BAAANQADCgUICgABNQAECgIIBAABAAAAAA==.Sheldelphine:BAAANQAECgEIAQAAAA==.Shellemental:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Shellstalker:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Shenhua:BAAANQAECgEIAQAAAA==.Sherber:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Shin:BAAANQAECgYIBgAAAA==.Shiné:BAAANQAECgEIAQAAAA==.Shoccymilk:BAAANQADCgYICgAAAA==.Shoop:BAAANQADCgIIAwAAAA==.Shyftzilla:BAAANQADCgIIAgAAAA==.Shåmanigans:BAAANQADCgcIBwAAAA==.',
Si='Siasham:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Sidis:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Sindrawrei:BAAANQADCgQIBAAAAA==.Sixxpal:BAAANQAECgMIBgAAAA==.',
Sk='Skanktank:BAAANQAECgUICQAAAA==.Skankvoker:BAAANQAECgEIAQABNQAECgUICQABAAAAAA==.Skarrovectis:BAAANQADCgEIAQAAAA==.Skathlok:BAAANQAECgMIAwAAAA==.Skest:BAAANQADCggIDwAAAA==.Skidstains:BAAANQADCgcIDQAAAA==.Skindeep:BAAANQADCggIDgAAAA==.Skragrott:BAAANQAECgUIBgAAAA==.Skullçrusher:BAAANQADCggIDgAAAA==.Skybomb:BAAANQADCgYIBgAAAA==.',
Sl='Slashycrisps:BAAANQADCggIEgAAAA==.Slobfather:BAAANQADCgIIAwAAAA==.',
Sm='Smacknzug:BAAANQADCgUIBQAAAA==.Smashmedaddy:BAAANQAECgMIBAAAAA==.',
Sn='Snapp:BAAANQADCggICAAAAA==.Sneaksham:BAAANQADCggICAAAAA==.Sneakswar:BAAANQAECgQICgAAAA==.Snowbind:BAAANQADCgYIBgAAAA==.',
So='Sofarogue:BAAANQAECgIIAgAAAA==.Solitiaire:BAAANQADCggICAAAAA==.Solvy:BAAANQAECgEIAQAAAA==.Sonara:BAAANQAECgMIAwAAAA==.Soondead:BAAANQAECgIIAwAAAA==.Soulmonk:BAAANQADCgIIAgAAAA==.',
Sp='Sparkies:BAAANQAECgQIBQAAAA==.Spieluhr:BAAANQADCgQIBAAAAA==.Spiritwhislr:BAAANQADCgYIBgAAAA==.',
St='Stabilitas:BAAANQAECgQIDAAAAA==.Starborne:BAAANQAECgQICgAAAA==.Sthöly:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Stockyx:BAAANQAECgYICgAAAA==.',
Su='Sudamon:BAAANQADCgEIAQAAAA==.Summoninc:BAAANQAECgQICgAAAA==.Sunila:BAAANQAECgQIBQAAAA==.Suntigerr:BAAANQAECgIIAgAAAA==.Superhanz:BAAANQADCgYIBgAAAA==.Suyasha:BAAANQAECgIIAgAAAA==.',
Sw='Swalala:BAAANQADCgIIAgAAAA==.Sweetmemeboy:BAAANQAECgEIAQAAAA==.Swipes:BAAANQADCgYIBgAAAA==.',
Sy='Sylvias:BAAANQADCggIDwAAAA==.Syreandrena:BAAANQAECgQICAAAAA==.Syvan:BAAANQADCgYIBgABNQAECgEIAgABAAAAAA==.',
['Sã']='Sãmael:BAAANQAECgQIDAAAAA==.',
['Sé']='Séhkmet:BAAANQADCgUIBQAAAA==.',
['Só']='Sól:BAAANQADCgIIAgAAAA==.',
Ta='Tabbandit:BAAANQADCgYICQAAAA==.Taffatups:BAAANQADCgUIBgAAAA==.Talena:BAAANQAECgMIAwABNQAECgUIBgABAAAAAA==.Talkingtree:BAAANQADCgcIBwAAAA==.Talorus:BAAANQAECgUIBgAAAA==.Tanwahhlock:BAAANQAECgUIBgAAAA==.Tarhata:BAAANQADCgMIBQAAAA==.Tarot:BAAANQADCggIDgAAAA==.Tatantaca:BAAANQAECgMIBgAAAA==.',
Te='Teknoman:BAAANQADCgYICQAAAA==.Tena:BAAANQADCgcIDQAAAA==.Teranzil:BAAANQAECgEIAQAAAA==.Terly:BAAANQADCggIDwAAAA==.Teär:BAAANQAECgYICgAAAA==.',
Th='Thalidomide:BAAANQAECgMIBgAAAA==.Thastir:BAAANQADCgUIBQAAAA==.Theavenger:BAAANQAECgEIAQAAAA==.Thedis:BAAANQADCgUIBgAAAA==.Thomus:BAAANQAECgEIAQAAAA==.Thormuss:BAAANQADCgUICQABNQAECgIIAgABAAAAAA==.Thundèrthigh:BAAANQADCgQIDAAAAA==.Thuxis:BAAANQAECgQIBQAAAA==.Thânãtös:BAAANQADCgYIBgAAAA==.',
Ti='Tishenya:BAAANQADCgUIBQAAAA==.',
To='Toezrmeanae:BAAANQADCgUICgAAAA==.Tokot:BAAANQAECgQICAAAAA==.Tombstone:BAAANQADCggIDgAAAA==.Tomsshaman:BAAANQADCggIEAAAAA==.Toniqjin:BAAANQAECgEIAQAAAA==.Toot:BAAANQADCgQIBAABNQAECgUIBgABAAAAAA==.Toowhiskay:BAAANQAECgQIDAAAAA==.Toridin:BAAANQADCgYIBgAAAA==.Tormentess:BAAANQAECgQICAAAAA==.',
Tr='Trinitylimit:BAAANQADCggIEAAAAA==.Tripletd:BAAANQADCgMIBgAAAA==.Trippy:BAAANQAECgEIAgAAAA==.Trixiest:BAAANQADCgYIEAAAAA==.',
Tu='Tulasham:BAAANQADCgIIAgABNQAECgUIBQABAAAAAA==.Tulathros:BAAANQAECgUIBQAAAA==.',
Tw='Twinkabell:BAAANQADCgEIAQAAAA==.',
Tx='Txci:BAAANQAECgEIAQAAAA==.',
Ty='Tylorän:BAAANQADCggICgAAAA==.',
Uc='Uchi:BAAANQAECgQIBQAAAA==.Uchuyagi:BAAANQAECgQIBQAAAA==.',
Un='Unc:BAAANQADCgcIDQAAAA==.',
Va='Valetudo:BAAANQADCggIDwAAAA==.Vance:BAAANQADCgYIBgAAAA==.Varayne:BAAANQADCgYIBgAAAA==.',
Ve='Veenus:BAAANQAECgEIAQAAAA==.Veladoris:BAAANQADCggIDwAAAA==.Velinoe:BAAANQADCggIDgAAAA==.Velkorvasa:BAAANQADCgQIBwAAAA==.Verdari:BAAANQADCggICQAAAA==.Verlene:BAAANQADCgYIBgAAAA==.',
Vi='Vindicatar:BAAANQAECgUIBgAAAA==.Vindicator:BAAANQADCggIDwAAAA==.Virek:BAAANQADCgYIDgAAAA==.Vivarna:BAAANQADCgIIAgAAAA==.',
Vo='Voidtree:BAAANQAECgYICgAAAA==.Voostab:BAAANQADCgMIAwAAAA==.Vortoxin:BAAANQADCggICAAAAA==.',
Vp='Vpallyonekey:BAAANQADCgcICgAAAA==.',
Vu='Vuvuzela:BAAANQADCgYIBgAAAA==.',
Vy='Vyeagra:BAAANQADCgcIBwABNQADCgcICwABAAAAAA==.',
['Ví']='Vírus:BAAANQADCgEIAQABNQADCgcIBwABAAAAAA==.',
Wa='Walshy:BAAANQAECgQICgAAAA==.Wantiwanti:BAAANQAECgQIBQAAAA==.Warrvx:BAAANQADCgQIBAAAAA==.Wartor:BAAANQADCgYICAAAAA==.Waxillium:BAAANQADCggIDwAAAA==.',
We='Well:BAAANQADCggIDgAAAA==.Werglerps:BAAANQAECgcICwAAAA==.',
Wh='Whytek:BAAANQADCgQIBwAAAA==.Whytelust:BAAANQADCgcIDQAAAA==.',
Wi='Windcier:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Windrider:BAAANQAECgIIAgAAAA==.Wirtle:BAAANQAECgUIBgAAAA==.Wisefrog:BAAANQADCgYIBgAAAA==.',
Wo='Worgdeeznuts:BAAANQADCgUIBQAAAA==.',
Wr='Wrathlon:BAAANQAECgIIAgAAAA==.',
Xa='Xandraevia:BAAANQADCgUICQAAAA==.Xannar:BAAANQAECgEIAQAAAA==.Xarmina:BAAANQAECgYICgAAAA==.',
Ye='Yetzira:BAAANQADCgEIAQAAAA==.',
Yo='Yodashaman:BAAANQAECgMIBgAAAA==.',
Yr='Yrbane:BAAANQADCgUIBgAAAA==.',
Za='Zaifer:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Zalayä:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Zaljan:BAABNQAFFIEHAAIEAAUJqBWlAAAEAQAEAAUJqBWlAAAEAQAAAA==.Zavul:BAAANQADCgYIDAAAAA==.',
Ze='Zeldonn:BAAANQABCgMIAwAAAA==.Zemu:BAAANQADCggICAAAAA==.Zendaiya:BAAANQADCgYIBgAAAA==.',
Zh='Zhànshi:BAAANQADCggIDwAAAA==.',
Zi='Zidiuz:BAAANQAECgEIAQAAAA==.Zippizap:BAAANQAECgIIAgAAAA==.',
['Âl']='Âlîse:BAAANQAECgEIAQAAAA==.',
['Äx']='Äxel:BAAANQADCgMIAgAAAA==.',
['Év']='Évelyn:BAAANQAECgYICQAAAA==.',
['Ðe']='Ðed:BAAANQAECgIIAgAAAA==.',
['Öz']='Öz:BAAANQADCgYIBgAAAA==.',
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
