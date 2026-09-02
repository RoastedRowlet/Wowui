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

local lookup = {'Shaman-Restoration','Unknown-Unknown',}
local provider = {region='US',realm='Blackrock',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Absolve:BAAANQAECgcIBwAAAA==.',
Ad='Adamantium:BAAANQADCgQIBAABNQAECgkJFgABABchAA==.Adamantorc:BAABNQAECoEWAAIBAAkJFyH5AAB4AwABAAkJFyH5AAB4AwAAAA==.Adampal:BAAANQAECgIIAgABNQAECgkJFgABABchAA==.Adlez:BAAANQADCgYICQAAAA==.',
Ae='Aethylas:BAAANQADCgYICgAAAA==.',
Ai='Aizzen:BAAANQAECgQIBAAAAA==.',
Ak='Akadeyjr:BAAANQADCgQIBQAAAA==.Akaeus:BAAANQADCgQIBAAAAA==.',
Al='Albatross:BAAANQADCgYIDAAAAA==.Alienfreakdt:BAAANQAECgQIBAAAAA==.Allaon:BAAANQAECgQIBAAAAA==.Allerianna:BAAANQADCgIIAgAAAA==.Alyriel:BAAANQADCgUIBQAAAA==.Alysun:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.Alysyn:BAAANQAECgEIAQAAAA==.Alyys:BAAANQABCgIIAgABNQAECgEIAQACAAAAAA==.',
Am='Amathel:BAAANQAECgMIAwAAAA==.Amynda:BAAANQADCgQIBAAAAA==.',
An='Angelsfìst:BAAANQADCggIDgAAAA==.',
Ar='Arawein:BAAANQADCgQIBAAAAA==.Aremis:BAAANQAECgMIAwABNQAECgYICwACAAAAAA==.Argonius:BAAANQADCgUIBQAAAA==.Arkelly:BAAANQAECgEIAQAAAA==.Arutoria:BAAANQADCgYIBgAAAA==.',
As='Asche:BAAANQADCgYIBgAAAA==.Ashlie:BAAANQADCgEIAQAAAA==.Asirili:BAAANQADCggICAAAAA==.Asmoodeus:BAAANQAECgYICAAAAA==.',
Au='Auramaxxer:BAAANQADCggICAAAAA==.',
Av='Avazen:BAAANQADCgQIBgAAAA==.',
Ay='Ayrah:BAAANQADCgcICQAAAA==.',
Ba='Baelcoz:BAAANQAECgQIBQAAAA==.Baragan:BAAANQADCgYIBgAAAA==.',
Be='Bear:BAAANQADCgYICwAAAA==.Bearwurst:BAAANQADCgcIDAAAAA==.Beazle:BAAANQADCggIEgAAAA==.Beefchub:BAAANQAECgEIAQAAAA==.Beladora:BAAANQAECgIIAgAAAA==.Bellarke:BAAANQADCgYIBgAAAA==.Belldelphine:BAAANQAECggICgAAAA==.',
Bi='Bichyone:BAAANQADCggIDwAAAA==.Bigback:BAAANQAECgQIBAAAAA==.Bigmeattréat:BAAANQAECgEIAQAAAA==.Bilo:BAAANQAECgEIAQAAAA==.Bimpo:BAAANQADCgQIBQAAAA==.',
Bl='Blangtron:BAAANQAECgMIAwAAAA==.Blickyz:BAAANQAECgEIAQAAAA==.Bloodbortie:BAAANQADCggIDQAAAA==.Blödhgárm:BAAANQADCggICAABNQAECgEIAQACAAAAAA==.',
Bo='Boatsnack:BAAANQADCgQIBQAAAA==.Boderationx:BAAANQADCggIDgABNQAECgYICgACAAAAAA==.Bodyshots:BAAANQAECgEIAQAAAA==.Boing:BAAANQABCgEIAQABNQADCgUIBgACAAAAAA==.Bonethug:BAAANQADCgUIBQAAAA==.Boofoo:BAAANQADCgYIBgAAAA==.Boople:BAAANQADCgIIAgAAAA==.Borbleybim:BAAANQADCggICAAAAA==.Borella:BAAANQADCgEIAQABNQAFFAIIAgACAAAAAA==.Boscho:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.Boschoa:BAAANQAECgQIBAAAAA==.Bouncedh:BAAANQAECgEIAQABNQAECgcICgACAAAAAA==.Bowzarr:BAAANQADCgQIBAAAAA==.',
Br='Brayeda:BAAANQADCgcIDAAAAA==.Broccoliched:BAAANQADCgcIBwAAAA==.Brodacz:BAAANQADCgYIDAAAAA==.Brownii:BAAANQAECgMIAwAAAA==.',
Bu='Burntbunss:BAAANQADCgUIBQAAAA==.Burritortega:BAAANQADCggIEQAAAA==.',
['Bó']='Bóunce:BAAANQAECgcICgAAAA==.',
Ca='Cainos:BAAANQADCgEIAQAAAA==.Calandra:BAAANQADCggICAAAAA==.Cantgetme:BAAANQADCgYIBgAAAA==.Carditis:BAAANQAECgYICgAAAA==.Carditits:BAAANQADCgYIBgABNQAECgYICgACAAAAAA==.Catwilliams:BAAANQADCgYICAABNQAECgEIAQACAAAAAA==.',
Ce='Cev:BAAANQADCgYIBgABNQAECggIDgACAAAAAA==.Cevren:BAAANQAECggIDgAAAA==.',
Ch='Chaoselite:BAAANQAECgUICAAAAA==.Chuibacca:BAAANQADCggIDAAAAA==.',
Cl='Clops:BAAANQADCgMIAwAAAA==.',
Co='Cobrakilla:BAAANQAECgIIAgAAAA==.Cobrakiller:BAAANQADCgIIAgABNQAECgIIAgACAAAAAA==.Coldgrasp:BAAANQADCgcIBwAAAA==.Coochpooch:BAAANQADCgYIDAAAAA==.Corbun:BAAANQADCgQIBAAAAA==.Cosmicgate:BAAANQAECgUICQAAAA==.Cowlawladin:BAAANQADCgMIAwAAAA==.',
Cr='Crockett:BAAANQAECgYICQAAAA==.Croissantz:BAAANQAECgMIBgAAAA==.Crusha:BAAANQADCgMIAwAAAA==.Cryssis:BAAANQADCgYIBgAAAA==.',
Cu='Cubanmage:BAAANQAECgIIAgAAAA==.Cucucachoo:BAAANQADCgYICQAAAA==.',
Cy='Cyndi:BAAANQADCgUIBQAAAA==.Cynnabar:BAAANQADCgIIAgAAAA==.Cyrce:BAAANQADCgQIBAAAAA==.',
Da='Daanos:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.Daeltha:BAAANQAECgYICwAAAA==.Dafdafdaf:BAAANQADCgYIDAAAAA==.Daffenprime:BAAANQAECgYICgAAAA==.Dalux:BAAANQADCgUIBQAAAA==.Danastey:BAAANQADCgYIBgAAAA==.Daneglesack:BAAANQAECgEIAQAAAA==.Danosxd:BAAANQAECgQIBAAAAA==.Daragnos:BAAANQAECgYIBwAAAA==.Darkhært:BAAANQAECgIIAgAAAA==.Darkkai:BAAANQAECgQIBQAAAA==.Darthmuffin:BAAANQAECgUIBQAAAA==.Daryl:BAAANQAECgMIAwABNQAECgYIBgACAAAAAA==.Dasprime:BAAANQADCgYICgAAAA==.Dastòmper:BAAANQADCgUIBQABNQADCgcIBwACAAAAAA==.Dayven:BAAANQADCgEIAQAAAA==.',
De='Deadhitmann:BAAANQAECgEIAQAAAA==.Deathbringer:BAAANQAECgYIBQAAAA==.Deathãngel:BAAANQAECgEIAQAAAA==.Decall:BAEANQADCgYICwABNQADCggICgACAAAAAA==.Degraded:BAAANQADCggICwAAAA==.Ders:BAAANQADCggIDgAAAA==.Dessius:BAAANQADCgUIBQAAAA==.Dethstra:BAAANQADCgMIAwABNQADCgYIBgACAAAAAA==.Deüs:BAAANQAECgMIBAAAAA==.',
Di='Dionotus:BAAANQADCgYIBgAAAA==.Dirtgrub:BAAANQADCgYIBgAAAA==.Divert:BAAANQADCggICAAAAA==.',
Dk='Dkhaoz:BAAANQAECgYICQABNQADCgYIDAACAAAAAA==.Dkinabox:BAAANQADCggIAgABNQAECgEIAQACAAAAAA==.',
Do='Docturnal:BAAANQADCgMIAwAAAA==.Dolphina:BAAANQADCggICAAAAA==.Donuts:BAAANQADCgMIAwAAAA==.Doomsure:BAAANQADCgMIAwAAAA==.Doømhammer:BAAANQABCgIIAgAAAA==.',
Dr='Dracburton:BAAANQADCgEIAQAAAA==.Dracnaphobia:BAAANQADCgMIAwABNQADCggIEQACAAAAAA==.Dragynaegis:BAAANQADCgQIAwAAAA==.Dragynsoul:BAAANQADCgIIAgAAAA==.Dranok:BAAANQADCgYICwAAAA==.Dratnosfan:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.Dreamlike:BAAANQAECgcIDAAAAA==.Drezco:BAAANQADCgUIBwABNQAECggIDgACAAAAAA==.Drstormii:BAAANQAECgEIAQAAAA==.',
Du='Dukazra:BAAANQADCgYIDwAAAA==.Dunkndonuts:BAAANQADCggICAAAAA==.',
['Dé']='Déathy:BAAANQADCgQIBAABNQADCgYIBgACAAAAAA==.',
Ea='Earthencore:BAAANQAECgQIBAAAAA==.',
Ed='Edgyboy:BAAANQADCgYICwAAAA==.Edjelord:BAAANQADCgcICQAAAA==.',
Eg='Egirltank:BAAANQADCgcIDQABNQAECgQIBAACAAAAAA==.',
Ek='Ekó:BAAANQADCgUIBQAAAA==.Ekø:BAAANQADCgEIAwABNQADCgUIBQACAAAAAA==.',
El='Eldanath:BAAANQADCgYIBgAAAA==.Elnaa:BAAANQADCgUIBQAAAA==.Elteethree:BAAANQAECgYICgAAAA==.Elunepal:BAAANQADCggIDQAAAA==.Elys:BAAANQADCgcIEwAAAA==.',
Em='Emalynn:BAAANQADCgYIBgAAAA==.',
En='Enigmà:BAAANQAECgYIEgAAAA==.Enmanuel:BAAANQADCgcIDAAAAA==.',
Ep='Epyôn:BAAANQAECgUICAAAAA==.',
Er='Eriodara:BAAANQADCgIIAgAAAA==.',
Es='Escas:BAAANQAECgQIBAAAAA==.Escaz:BAAANQADCggICAAAAA==.Esrahaddon:BAAANQAECgMIAwAAAA==.',
Ev='Evanora:BAAANQADCgYICQAAAA==.Evillinx:BAAANQADCggICAAAAA==.Evilmaru:BAAANQADCggICAAAAA==.Evokelion:BAAANQADCgYICgABNQAECgYICwACAAAAAA==.',
Ex='Exploited:BAAANQABCgIIAgAAAA==.',
Fa='Factz:BAAANQADCgEIAQAAAA==.Faespalmn:BAAANQAECgYIBwAAAA==.Fauin:BAAANQADCgYIBgAAAA==.',
Fe='Fenthead:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.Fernandôge:BAAANQAECgQIBgAAAA==.',
Fi='Fidel:BAAANQAECgIIAgAAAA==.Fil:BAAANQAECgEIAQAAAA==.Fisac:BAAANQAECgcIDQAAAA==.Fishbubble:BAAANQABCgMIAwAAAA==.',
Fl='Fletchtern:BAAANQADCgEIAQABNQAECgIIAgACAAAAAA==.Flexlock:BAAANQADCgMIAwAAAA==.Flextime:BAAANQADCggIDwAAAA==.',
Fo='Folius:BAAANQAFFAIIAwAAAA==.',
Fr='Franzu:BAAANQAECgEIAQAAAA==.Freehits:BAAANQADCgEIAQAAAA==.Friggitte:BAAANQADCgYICAAAAA==.',
Fu='Full:BAAANQADCggIFAAAAA==.Furgoblin:BAAANQADCgUIBQABNQAECgIIAgACAAAAAA==.',
['Fâ']='Fâdêd:BAAANQADCggICAAAAA==.',
['Fë']='Fëanör:BAAANQAECgQIBAAAAA==.',
['Fø']='Førce:BAAANQADCgQIBgAAAA==.',
Ga='Gabi:BAAANQADCgYIBgAAAA==.Gacrüx:BAAANQADCgUICAAAAA==.Galadrìel:BAAANQAECgQICAAAAA==.Galadrìèl:BAAANQADCgUIBQAAAA==.Gambol:BAAANQADCgYIBgAAAA==.',
Gh='Ghorn:BAAANQADCggIDwAAAA==.',
Gl='Glareaforsor:BAAANQADCgIIAgAAAA==.Glimpse:BAAANQADCgYICAAAAA==.',
Go='Gochurass:BAAANQADCgYICQAAAA==.',
Gr='Grapthar:BAEANQADCggICgAAAA==.Greyarrow:BAAANQADCggIDgAAAA==.Greæd:BAAANQAECggIDwAAAA==.Grimgown:BAAANQAECgMIAgAAAA==.Grimreaper:BAAANQADCgcICQABNQADCggIDQACAAAAAA==.Grizzard:BAAANQADCggICAAAAA==.Gruckek:BAAANQAECgYICQAAAA==.',
Gu='Gulanis:BAAANQADCgYICgAAAA==.',
Gw='Gwendlyne:BAAANQADCgcIDQAAAA==.',
['Gó']='Góddess:BAAANQADCggICQAAAA==.',
Ha='Hag:BAAANQAECgQIBAABNQAECggICQACAAAAAA==.Halloffaith:BAAANQAECgcIDQAAAA==.Harissa:BAAANQADCgEIAQABNQADCgYIBgACAAAAAA==.Hawgneto:BAAANQADCgYIBgAAAA==.',
He='Hellig:BAAANQAECgQIBAAAAA==.Hellofriday:BAAANQADCgYIBgAAAA==.Hellíg:BAAANQADCgYIBgAAAA==.Hetzfury:BAAANQADCgEIAQAAAA==.Heyman:BAAANQADCgYICwAAAA==.',
Hi='Hideyerweed:BAAANQADCgQIBAABNQAECgUICAACAAAAAA==.Higi:BAAANQADCgYIBgAAAA==.',
Ho='Holistic:BAAANQAECgYICQAAAA==.Honeyblunt:BAAANQADCgIIAgAAAA==.Hotchocmilk:BAAANQAECgEIAQAAAA==.',
Hr='Hr:BAAANQADCgcIBwAAAA==.',
Hu='Huntaa:BAAANQAECgQIBQAAAA==.Hurají:BAAANQAECgcICwABNQAFFAEIAQACAAAAAA==.Huråji:BAAANQAFFAEIAQAAAA==.',
Il='Ilnookll:BAAANQADCgUIBgAAAA==.',
Im='Imblooms:BAAANQADCgEIAQAAAA==.Imbooms:BAAANQADCgYIBgAAAA==.Imryl:BAAANQAECgMIBQAAAA==.',
Ir='Ironpaws:BAAANQAECgIIAgAAAA==.Iryssoscaly:BAAANQADCgIIAgAAAA==.',
Is='Isa:BAAANQAECgYICgAAAA==.Isaa:BAAANQAECgUIBAABNQAECgYICgACAAAAAA==.',
It='Itamedruids:BAAANQADCggICAABNQAECgEIAQACAAAAAA==.',
Ja='Jackrackham:BAAANQAECgEIAQAAAA==.Jakuza:BAAANQADCgYIBgAAAA==.Jaydeep:BAAANQABCgIIAgAAAA==.',
Je='Jebydk:BAAANQADCggIEQABNQAECggIDQACAAAAAA==.Jebysham:BAAANQAECggIDQAAAA==.Jeffybubbles:BAAANQADCgYIBgAAAA==.Jeffytotems:BAAANQAECgIIAgAAAA==.Jelsy:BAAANQADCggIDgAAAA==.Jesly:BAAANQADCgUIBwABNQADCggIDgACAAAAAA==.Jessibella:BAAANQAFFAEIAQAAAA==.',
Ji='Jimmyhoofa:BAAANQABCgEIAQABNQADCgUIBgACAAAAAA==.',
Jo='Johnsteez:BAAANQADCgUIBwAAAA==.Jorndalf:BAAANQAECgQIBAAAAA==.',
Jt='Jt:BAAANQABCgIIAgAAAA==.',
Ju='Juggz:BAAANQADCgIIAwAAAA==.Justabutcher:BAAANQAECgMIAwAAAA==.',
Jw='Jwag:BAAANQADCgYIBwAAAA==.',
['Jê']='Jêcht:BAAANQAECgcICwAAAA==.',
Ka='Kafur:BAAANQADCggIDgAAAA==.Kaiido:BAAANQAECgEIAQABNQAECgYICgACAAAAAA==.Karmanda:BAAANQADCgYICwAAAA==.Kattel:BAAANQADCgYIBgAAAA==.',
Ke='Keither:BAAANQABCgIIAgABNQADCgUIBgACAAAAAA==.Kelendor:BAAANQAECgYICgAAAA==.Kellandil:BAAANQADCgMIBQAAAA==.Kenju:BAAANQAECgEIAQAAAA==.Kensie:BAAANQADCgcIBwAAAA==.',
Kh='Khlampz:BAAANQAECgQIBAAAAA==.Khlampzight:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.Khondor:BAAANQADCgIIAwAAAA==.',
Ki='Kiel:BAAANQAECgEIAQAAAA==.Kigen:BAAANQABCgIIAgAAAA==.Kikurface:BAAANQADCgUICQAAAA==.Kimjungun:BAAANQADCgEIAQAAAA==.Kiranax:BAAANQAECgcIDQAAAA==.',
Ko='Koinu:BAAANQAECgYICgAAAA==.Korbun:BAAANQADCgYIBgAAAA==.Kovskii:BAAANQADCgcIDAAAAA==.',
Kr='Krad:BAAANQADCggIEwAAAA==.Kriathura:BAAANQAECgQIBAAAAA==.',
Kw='Kwangpow:BAAANQAECgEIAQAAAA==.',
['Kà']='Kàkàshi:BAAANQAECgQIBgAAAA==.',
La='Lambbchopp:BAAANQADCgQIBQAAAA==.Lazyrage:BAAANQADCggIDgAAAA==.Lazyreaper:BAAANQADCgUIBwABNQADCggIDgACAAAAAA==.',
Le='Lebronto:BAAANQAECgUIBgAAAA==.Legsquats:BAAANQADCgQIBAAAAA==.Lessirs:BAAANQADCgcICQAAAA==.',
Li='Lichnaught:BAAANQADCgUIBwABNQADCggIDgACAAAAAA==.Lifetapped:BAAANQADCgcICQAAAA==.Lilfluffy:BAAANQADCgYIBgAAAA==.Liquid:BAAANQADCgYICQAAAA==.',
Ll='Llikdaor:BAAANQAECgEIAQAAAA==.',
Lo='Loaded:BAAANQAECgQIBAAAAA==.Loikk:BAAANQADCgMIAwAAAA==.Loodacrits:BAAANQAECgUIBwAAAA==.',
Lu='Lushylock:BAAANQADCgEIAQAAAA==.',
Ma='Macklin:BAAANQAECgEIAQAAAA==.Maddalynn:BAAANQAECgQIBAAAAA==.Maelstrox:BAAANQADCgUICgAAAA==.Magandadrake:BAAANQAECgYICQAAAA==.Magerita:BAAANQADCgMIAwAAAA==.Magharat:BAAANQADCgUICQABNQAECgYICQACAAAAAA==.Magicman:BAAANQADCgYIBgAAAA==.Malyss:BAAANQADCgYICQAAAA==.Mandelstam:BAAANQADCggIFQAAAA==.Mangkanor:BAAANQADCgMIBAAAAA==.Mangoloidman:BAAANQADCgIIAgABNQADCgIIAgACAAAAAA==.',
Mc='Mcsstab:BAAANQADCgYIBgAAAA==.',
Me='Meatballer:BAAANQADCgQIBAAAAA==.Meatballz:BAAANQAECgMIAwAAAA==.Mecalux:BAAANQADCgQIBAAAAA==.Meloco:BAAANQADCgYIBgAAAA==.Melody:BAAANQAECggIDwAAAA==.Menj:BAAANQADCgQIBgABNQAECgEIAQACAAAAAA==.Meowcheese:BAAANQADCgcIDQAAAA==.Meowmix:BAAANQADCgUIBQABNQADCgYIBgACAAAAAA==.Mesosphere:BAEANQADCgcIDAAAAA==.',
Mi='Midorii:BAAANQADCgcIBwAAAA==.Migpala:BAAANQADCgcIDQAAAA==.Miiniimaage:BAAANQADCgQIAgAAAA==.Milkmann:BAAANQABCgIIAgAAAA==.Milkymoos:BAAANQAECgEIAQAAAA==.Minar:BAAANQAECgQIBAABNQAECgQIBQACAAAAAA==.Minoic:BAAANQADCgYICwAAAA==.Mistchivus:BAAANQAECgQIBAAAAA==.',
Mo='Mobbster:BAAANQADCggIDwAAAA==.Mohnster:BAAANQADCgMIAwAAAA==.Moisttotems:BAAANQADCgEIAQAAAA==.Monipouch:BAAANQAECgMIBAAAAA==.Moondaisy:BAAANQADCgIIAgAAAA==.Moopocalypse:BAAANQADCgYICAAAAA==.Moosenukle:BAAANQADCgQIBAAAAA==.Morphaeus:BAAANQADCgUIBgAAAA==.Mortar:BAAANQAECgMIAwAAAA==.Mozrog:BAAANQAECgEIAQAAAA==.',
Mu='Muffblaster:BAAANQAECgUIBwAAAA==.Murphet:BAAANQADCggIEQAAAA==.',
My='Mythrix:BAAANQADCgYIBgABNQAECgcICAACAAAAAA==.',
['Mí']='Míra:BAAANQADCgcIDAAAAA==.',
['Mö']='Mönïca:BAAANQAECgEIAQAAAA==.',
Na='Nathenatra:BAAANQADCgQIBAABNQAECgYICgACAAAAAA==.',
Ne='Neeko:BAAANQAECgIIAgAAAA==.Neonmoose:BAAANQADCggICgAAAA==.Nezbrez:BAAANQADCgUIBwAAAA==.',
Nh='Nhthree:BAAANQAECgMIBAAAAA==.',
No='Nofsha:BAAANQADCgUIBQABNQADCggIDQACAAAAAA==.Noktyx:BAAANQABCgQIBgAAAA==.Nomoney:BAAANQAECgEIAQAAAA==.Norasong:BAAANQADCgcICQAAAA==.Nostick:BAAANQAECgUICAAAAA==.Novacrono:BAAANQAECgUIBwAAAA==.Noxioustoast:BAAANQADCgIIAgAAAA==.',
Nu='Nuke:BAAANQADCgYIFAAAAA==.',
['Nô']='Nôôk:BAAANQADCggIDAAAAA==.',
Op='Opta:BAAANQADCgYIBgAAAA==.',
Or='Orkhis:BAAANQAECgQIBAAAAA==.',
Ou='Outbrèak:BAAANQADCgcIDQAAAA==.',
Ow='Owo:BAAANQABCgIIAQABNQAECgEIAQACAAAAAA==.',
['Oá']='Oáklánd:BAAANQADCggIAgAAAA==.',
Pa='Pakuru:BAAANQAECgQIBAAAAA==.Pal:BAAANQAECgIIAgAAAA==.Palachin:BAAANQAECgQIBAAAAA==.Paladelion:BAAANQAECgQIBwABNQAECgYICwACAAAAAA==.Paleonebula:BAAANQADCgYIBgAAAA==.Pallyberry:BAAANQADCgYIBgAAAA==.Pangittroll:BAAANQAECgUIBQAAAA==.Papatotems:BAAANQADCgQIBAAAAA==.Papå:BAAANQADCgQIBAAAAA==.Pawtirra:BAAANQADCgIIAgAAAA==.',
Pe='Perfume:BAAANQADCgYIBgAAAA==.Petri:BAAANQAECgEIAQAAAA==.',
Pi='Pickwaton:BAAANQAECgMIAwAAAA==.Pipen:BAAANQAFFAIIAgAAAA==.',
Pl='Pld:BAAANQADCgcIBwAAAA==.',
Po='Potatatoes:BAAANQADCgUIBQAAAA==.Poxrot:BAAANQADCgQIBAABNQADCgcIDgACAAAAAA==.',
Pr='Praize:BAAANQAECgYICgAAAA==.Press:BAAANQAECggICQAAAA==.Prìde:BAAANQAECgQIBAABNQAECggIDwACAAAAAA==.',
Ps='Psykopathik:BAAANQADCgQIBAAAAA==.',
Pu='Puddl:BAAANQAECgcIDQAAAA==.Purrsephone:BAAANQADCgEIAQAAAA==.',
Qa='Qaa:BAAANQAECgEIAQAAAA==.',
Qh='Qhaoss:BAAANQADCgYIDAAAAA==.',
Qt='Qti:BAAANQADCgYIDAAAAA==.',
Qu='Quadnines:BAAANQADCggIDAAAAA==.Quelivia:BAAANQADCgEIAQABNQAECgMIBQACAAAAAA==.Ques:BAAANQADCgQIBAAAAA==.Quesly:BAAANQADCggIEQAAAA==.Quetzacoatl:BAAANQAECgMIAwAAAA==.',
Ra='Racophorus:BAAANQADCgUICQAAAA==.Raffe:BAAANQADCgcICgAAAA==.Rammsteen:BAAANQADCgYIBwAAAA==.Rarity:BAAANQAECgEIAgAAAA==.Ratarga:BAAANQAECgYICQAAAA==.Ravenaa:BAAANQAECgQIBQAAAA==.',
Re='Readycheck:BAAANQADCgEIAQAAAA==.Reallywanna:BAAANQADCgYIBgAAAA==.Reddragyn:BAAANQADCgYICAAAAA==.Reeves:BAAANQAECgEIAQAAAA==.Reggiez:BAAANQADCggIDQAAAA==.Reinbert:BAAANQADCgMIAwABNQADCgYIBgACAAAAAA==.Rektski:BAAANQAECgQIBQAAAA==.Renzer:BAAANQADCgcICQAAAA==.Reprosal:BAAANQADCgQIBQABNQADCgcIBwACAAAAAA==.Restasis:BAAANQADCgUIBwAAAA==.Retburn:BAAANQAECgQIBQAAAA==.Reveluv:BAAANQADCgcICAAAAA==.',
Ri='Rickehlol:BAAANQADCgYICgAAAA==.Righturn:BAAANQAECgIIAgAAAA==.Rikkeh:BAAANQADCgIIAgAAAA==.Rinaera:BAAANQADCggIDgAAAA==.',
Ro='Roahr:BAAANQADCgUIBAAAAA==.Rollinsmacks:BAAANQADCgIIAgAAAA==.Rollsforham:BAAANQADCggICAAAAA==.Rondali:BAAANQADCggICAAAAA==.Rotheris:BAAANQAECgIIAwAAAA==.Rottentreats:BAAANQADCgYICQAAAA==.Rottie:BAAANQAECgQIBwAAAA==.',
Rt='Rts:BAAANQAECgcIDAAAAA==.',
Ru='Rufio:BAAANQAECgYICgAAAA==.Rufiu:BAAANQAECgMIAwAAAA==.',
Ry='Ryogen:BAAANQAECgQIBgAAAA==.',
Sa='Saarahkin:BAAANQADCgUIBQAAAA==.Sablewhisper:BAAANQADCgYIBQABNQADCgYIBgACAAAAAA==.Sabryel:BAAANQAECgEIAQAAAA==.Saintvyn:BAAANQAECgUICAAAAA==.Salmonroll:BAAANQADCggIDgAAAA==.Salos:BAAANQADCgYIBgAAAA==.Sandarah:BAAANQAECgQIBgABNQAECggIDwACAAAAAA==.Sapling:BAAANQAECgMIAwAAAA==.Sathic:BAAANQAECgIIAgAAAA==.Satreser:BAAANQADCggICAAAAA==.',
Sc='Scallywrath:BAAANQADCgUIBQAAAA==.Scaretale:BAAANQADCgQIBgAAAA==.Scribbles:BAAANQAECgcICQAAAA==.Scribblesz:BAAANQADCgYIBgAAAA==.',
Se='Seanthepally:BAAANQAECgQIBAAAAA==.Seantheshamm:BAAANQAECgQIBAABNQAECgQIBAACAAAAAA==.Secihots:BAAANQAECgQIBgAAAA==.Seidhkona:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.Serialheal:BAAANQADCgYICgABNQAECgIIAgACAAAAAA==.',
Sh='Shadalune:BAAANQAECgUIBQAAAA==.Shamanelion:BAAANQAECgYICwAAAA==.Shazza:BAAANQADCgIIAgAAAA==.Shinso:BAAANQAECgYIBgAAAA==.Shiwang:BAAANQAECgQIBAAAAA==.Shockazuwu:BAAANQAECgQIBgAAAA==.Shocktagon:BAAANQADCgEIAQAAAA==.Shocktherapy:BAAANQAECgEIAQAAAA==.Shockér:BAAANQADCggICAAAAA==.Shuu:BAAANQAECgIIAgAAAA==.Shwoidlord:BAAANQAECgQIBAABNQAECgQIBgACAAAAAA==.Shwoop:BAAANQAECgQIBAABNQAECgQIBgACAAAAAA==.',
Si='Sigurrose:BAAANQAECgEIAQAAAA==.',
Sk='Skitzosvnff:BAAANQAECgUIBgAAAA==.',
Sm='Smokedh:BAAANQADCgYIDAABNQAECgUICAACAAAAAA==.Smokezug:BAAANQAECgUICAAAAA==.',
Sn='Snorter:BAAANQADCgUIBQAAAA==.Snowlock:BAAANQADCgYICgAAAA==.Snowrain:BAAANQAECgUICAAAAA==.',
So='Sotek:BAAANQABCgIIAgAAAA==.Soulster:BAAANQADCgEIAQAAAA==.Sourdeath:BAAANQADCggIDgAAAA==.',
Sp='Spinningbrew:BAAANQADCgYICwAAAA==.',
Ss='Ssnoosnoo:BAAANQADCgYICgAAAA==.',
St='Stanchion:BAAANQADCgQIBAAAAA==.Stinko:BAAANQAECgIIAQABNQAFFAEIAQACAAAAAA==.Stonecrusade:BAAANQADCgcIBwAAAA==.Stonedhokage:BAAANQAECgQIBQAAAA==.Stopthebleed:BAAANQADCgcIBwAAAA==.Sty:BAAANQAECggICwAAAA==.Ståb:BAAANQADCgYIBgABNQAECgYIEgACAAAAAA==.Stårr:BAAANQADCgYIBwAAAA==.',
Su='Suicideblond:BAAANQADCgcICAAAAA==.Supadrac:BAAANQAECgcICwAAAA==.Surfnturf:BAAANQAFFAEIAgAAAQ==.Surging:BAAANQAECgIIAgAAAA==.Suri:BAAANQAECgIIAgAAAA==.Surii:BAAANQAECgIIAgABNQAECgIIAgACAAAAAA==.',
Sw='Swaazz:BAAANQAECgEIAQAAAA==.Swerve:BAAANQAECgMIBAAAAA==.',
Sy='Sykocious:BAAANQAECgQIBQAAAA==.Sylleria:BAAANQADCgEIAQAAAA==.Syllia:BAAANQADCgEIAQABNQAECgcICgACAAAAAA==.Syphilia:BAAANQAECgYICAAAAA==.',
['Sè']='Sèanthewarr:BAAANQADCgUIBQABNQAECgQIBAACAAAAAA==.',
Ta='Tacocát:BAAANQADCgMIAwABNQAFFAIIAgACAAAAAA==.Tacosback:BAAANQADCgEIAQABNQAFFAIIAgACAAAAAA==.Tacosdk:BAAANQAFFAIIAgAAAA==.Tacoslop:BAAANQAECgcICAABNQAFFAIIAgACAAAAAA==.Tacosneak:BAAANQADCggIBwABNQAFFAIIAgACAAAAAA==.Talonarayan:BAAANQADCgUICQAAAA==.',
Te='Teebonez:BAAANQADCgQIBAAAAA==.Teesdays:BAAANQABCgQIBAAAAA==.Tewasha:BAAANQAECgYICQAAAA==.',
Th='Thalryn:BAAANQADCgMIAwAAAA==.Thedoofy:BAAANQADCgMIAwAAAA==.Threellamas:BAAANQAECgYIBwAAAA==.Thuringwethl:BAAANQADCgYICgAAAA==.',
Ti='Tidyswet:BAAANQADCgYIBgAAAA==.Tinydonny:BAAANQADCgQIBQAAAA==.',
To='Tonylildik:BAAANQADCgcICQABNQAECggIDQACAAAAAA==.Toopac:BAEANQAECgcICQAAAA==.Totö:BAAANQAECgUICgAAAA==.',
Tr='Tramana:BAAANQAECgQIBAAAAA==.Triggéred:BAAANQADCgQIBAAAAA==.Triig:BAAANQADCgQIBwAAAA==.Trollcopter:BAAANQADCgYIBgABNQADCggIEQACAAAAAA==.Trollwíthbow:BAAANQADCggIDQAAAA==.',
Tw='Tweedledumb:BAAANQADCgYIBgAAAA==.Twìnky:BAAANQAECgcICQAAAA==.',
Ul='Ulfric:BAAANQADCgIIAgAAAA==.',
Un='Unclepete:BAAANQADCgMIAwAAAA==.',
Va='Vacula:BAAANQADCggIDwAAAA==.Vaelyriana:BAAANQAECgQIBAAAAA==.Valreaux:BAAANQADCgIIAgAAAA==.Vandalism:BAAANQADCgYIDAAAAA==.Vanian:BAAANQADCgEIAQAAAA==.',
Vd='Vdyr:BAAANQADCgcIDAAAAA==.',
Ve='Vex:BAAANQABCgMIAwAAAA==.',
Vi='Vilgefortz:BAAANQAECgIIAgAAAA==.Vivelf:BAAANQADCggIAQAAAA==.',
Vo='Voidborn:BAAANQAECgMIAwAAAA==.Voidling:BAAANQADCgYIBgAAAA==.Voidturned:BAAANQADCgQIBAAAAA==.Vortexis:BAAANQADCggIGAAAAA==.',
Vu='Vulpurra:BAAANQADCggIDwAAAA==.Vurm:BAAANQAECgYIDQAAAA==.',
Vy='Vytamin:BAAANQADCggICQAAAA==.',
['Vâ']='Vâlinoth:BAAANQAECgUICAAAAA==.',
['Vó']='Vólkan:BAAANQADCgcIDQAAAA==.',
Wa='Walkinghealz:BAAANQADCgQIBQABNQADCggIEQACAAAAAA==.',
We='Wengo:BAAANQADCgIIBAAAAA==.',
Wi='Willywonkie:BAAANQADCgIIAgAAAA==.Windfrey:BAAANQAECgMIAwAAAA==.Winghollow:BAAANQADCgIIAgAAAA==.Wintershock:BAAANQAECgQIBAAAAA==.',
Wl='Wll:BAAANQAECgQIBgABNQAECgcICwACAAAAAA==.Wlx:BAAANQAECgcICwAAAA==.',
Wo='Wobs:BAAANQAECgYIBgAAAA==.Woopoles:BAAANQADCggIDgAAAA==.',
Wr='Wredgeek:BAAANQADCgYICAAAAA==.',
Wy='Wy:BAAANQADCgcIBwAAAA==.',
Xa='Xavierboí:BAAANQAECgQIBAAAAA==.',
Xi='Xileon:BAAANQAECgEIAQAAAA==.',
Ya='Yabishus:BAAANQADCgQIBAAAAA==.Yahboibangz:BAAANQADCggICAAAAA==.',
Ye='Yelacsa:BAAANQADCgYIBgABNQAECgQIBgACAAAAAA==.',
Yo='Yoshu:BAAANQAECgEIAQAAAA==.',
Yu='Yukyukyuk:BAAANQABCgQIBAAAAA==.',
Za='Zanthu:BAEANQADCgYIBgABNQAECgcICQACAAAAAA==.Zanu:BAAANQADCgYICwAAAA==.Zardon:BAAANQADCgYIBgABNQAECgYIDAACAAAAAA==.',
Ze='Zecar:BAAANQADCgQIBAAAAA==.Zengard:BAAANQADCgQIBAAAAA==.Zenkic:BAAANQADCgEIAQAAAA==.Zenlock:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.',
Zo='Zoralari:BAAANQAECgIIAgAAAA==.Zorke:BAAANQAECgIIAgAAAA==.',
['Ön']='Önonta:BAAANQADCgcICQAAAA==.Önotoes:BAAANQADCggIDwAAAA==.',
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
