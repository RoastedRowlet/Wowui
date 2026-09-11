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

local lookup = {'Shaman-Restoration','Unknown-Unknown','Evoker-Devastation','DeathKnight-Unholy','DeathKnight-Blood','Druid-Restoration','DemonHunter-Devourer','Mage-Arcane','Mage-Frost','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','Priest-Holy','Priest-Discipline','Monk-Mistweaver','Shaman-Elemental','Shaman-Enhancement','DeathKnight-Frost','Paladin-Holy','Paladin-Retribution','Evoker-Preservation','DemonHunter-Havoc','Warrior-Arms',}
local provider = {region='US',realm='Blackrock',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Absolve:BAAANQAFFAEIAQAAAA==.',
Ad='Adamantium:BAAANQADCgQIBAABNQAECgkJHgABAIEiAA==.Adamantorc:BAABNQAECoEeAAIBAAkJgSIiAgCLAwABAAkJgSIiAgCLAwAAAA==.Adampal:BAAANQAECgIIAgABNQAECgkJHgABAIEiAA==.',
Ae='Aethylas:BAAANQADCggIDAAAAA==.',
Ai='Aizzen:BAAANQAECgUICQAAAA==.',
Ak='Akadeyjr:BAAANQADCggIDQAAAA==.Akaeus:BAAANQADCgcICwAAAA==.Akhouel:BAAANQADCgEIAQAAAA==.',
Al='Albatross:BAAANQADCggIFAAAAA==.Alfalfaflow:BAAANQADCggICAAAAA==.Alienfreakdt:BAAANQAECgYICgAAAA==.Allaon:BAAANQAECgUIBwAAAA==.Allerianna:BAAANQADCgIIAgAAAA==.Alyriel:BAAANQADCgUIBQABNQADCgYIBgACAAAAAA==.Alysun:BAAANQAECgQIBAAAAA==.Alysyn:BAAANQAECgEIAQABNQAECgQIBAACAAAAAA==.Alyys:BAAANQABCgIIAgABNQAECgQIBAACAAAAAA==.Alèxander:BAAANQADCgcICAAAAA==.',
Am='Amathel:BAAANQAECgQIBwAAAA==.Amynda:BAAANQADCgQIBAAAAA==.',
An='Angelsfìst:BAAANQAECgMIAwAAAA==.',
Ar='Arawein:BAAANQAECgEIAQAAAA==.Aremis:BAAANQAECgQIBwABNQAECgkJFQADALgVAA==.Argonius:BAAANQADCgUIBQAAAA==.Arkelly:BAAANQAECgMIBwAAAA==.Artemicion:BAAANQADCgIIAgABNQAECgMIBAACAAAAAA==.Arutoria:BAAANQADCggIDgAAAA==.',
As='Asche:BAAANQADCgYIBgAAAA==.Ashlie:BAAANQADCgEIAQAAAA==.Asirili:BAAANQAECgEIAQAAAA==.Asmoodeus:BAAANQAECgYICAAAAA==.',
Au='Auramaxxer:BAAANQADCggICAAAAA==.',
Av='Avazen:BAAANQADCgQIBwAAAA==.',
Ay='Ayrah:BAAANQAECgEIAQAAAA==.',
Ba='Badshammy:BAAANQAECgEIAgAAAA==.Baelcoz:BAAANQAECgQIBgAAAA==.Baragan:BAAANQADCgYIBgAAAA==.',
Be='Bear:BAAANQADCggIEwAAAA==.Bearwurst:BAAANQAECgEIAQAAAA==.Beazle:BAAANQAECgEIAQAAAA==.Beefchub:BAAANQAECgYIBwAAAA==.Beladora:BAAANQAECgYICAAAAA==.Bellarke:BAAANQADCgYIBgAAAA==.Belldelphine:BAAANQAECggIEAAAAA==.',
Bi='Bichyone:BAAANQADCggIDwAAAA==.Bigback:BAAANQAECgQICAAAAA==.Bigmeattréat:BAAANQAECgEIAQAAAA==.Bigpurr:BAAANQADCggICAABNQAFFAEIAQACAAAAAA==.Bilo:BAAANQAECgMIBAAAAA==.Bimpo:BAAANQADCgQIBQAAAA==.',
Bl='Blangtron:BAAANQAECgUICAAAAA==.Blickyz:BAAANQAECgMIBAAAAA==.Bloodbortie:BAAANQAECgIIAgAAAA==.Blödhgárm:BAAANQADCggICAABNQAECgQIBAACAAAAAA==.',
Bo='Boatsnack:BAAANQADCgYICwAAAA==.Boboko:BAAANQAECgQIBAAAAA==.Boderationx:BAAANQADCggIDwABNQAECggIEgACAAAAAA==.Bodyshots:BAAANQAECgEIAQAAAA==.Boing:BAAANQABCgEIAQABNQADCgYIDAACAAAAAA==.Bolgc:BAAANQADCgIIAgABNQADCggIAwACAAAAAA==.Bonethug:BAAANQADCgUIBQAAAA==.Boofoo:BAAANQAECgEIAQAAAA==.Boople:BAAANQADCgUIBwAAAA==.Borbleybim:BAAANQAECgMIAwAAAA==.Borella:BAAANQADCgEIAQABNQAFFAIIBAACAAAAAA==.Bortikus:BAAANQADCgUIBwAAAA==.Boscho:BAAANQAECgEIAQABNQAECgUICQACAAAAAA==.Boschoa:BAAANQAECgUICQAAAA==.Bouncedh:BAAANQAECgIIAgABNQAECgcIDQACAAAAAA==.Bowzarr:BAAANQADCgUICQAAAA==.',
Br='Brayeda:BAAANQADCgcIEwAAAA==.Breadpudn:BAAANQAECgIIAgAAAA==.Broccoliched:BAAANQADCgcIDgAAAA==.Brodacz:BAAANQADCgYIEgAAAA==.Brownii:BAAANQAECgMIAwAAAA==.',
Bu='Burntbunss:BAAANQADCgUICQAAAA==.Burritortega:BAAANQADCggIGAAAAA==.',
['Bé']='Bérserkblave:BAAANQADCggIEAAAAA==.',
['Bó']='Bóunce:BAAANQAECgcIDQAAAA==.',
Ca='Cainos:BAAANQADCgEIAQAAAA==.Calandra:BAAANQAECgQIBAAAAA==.Cantgetme:BAAANQADCgYICwAAAA==.Carditis:BAAANQAFFAEIAQAAAA==.Carditits:BAAANQADCgYIBgABNQAFFAEIAQACAAAAAA==.Catwilliams:BAAANQADCgYICAABNQAECgEIAQACAAAAAA==.',
Ce='Cev:BAAANQAECgYIBwABNQAECgkJGQAEANYjAA==.Cevren:BAABNQAECoEZAAMEAAkJ1iNmAgCkAwAEAAkJXSNmAgCkAwAFAAEJIxpOXwBIAAAAAA==.',
Ch='Chaoselite:BAAANQAECggIEAAAAA==.Chelia:BAAANQAECgEIAQAAAA==.Chuibacca:BAAANQAECgMIAwAAAA==.',
Cl='Clops:BAAANQADCgQIBwAAAA==.',
Co='Cobrakilla:BAAANQAECgIIAgAAAA==.Cobrakiller:BAAANQADCgIIAgABNQAECgIIAgACAAAAAA==.Coldgrasp:BAAANQADCgcIBwAAAA==.Coochpooch:BAAANQADCgYIDAAAAA==.Corbun:BAAANQADCgcICwAAAA==.Cosmicgate:BAAANQAECgYIDwAAAA==.Cowlawladin:BAAANQAECgIIAgAAAA==.',
Cr='Crockett:BAAANQAECgcIEAAAAA==.Croissantz:BAAANQAECgQICgAAAA==.Crusha:BAAANQADCgMIAwAAAA==.Cryssis:BAAANQADCgYIBgAAAA==.',
Cu='Cubanmage:BAAANQAECgMIBAAAAA==.Cucucachoo:BAAANQADCgcIDAAAAA==.',
Cy='Cyndi:BAAANQADCgUICgAAAA==.Cynnabar:BAAANQADCgIIAgAAAA==.Cyrce:BAAANQADCgQIBAAAAA==.',
Da='Daanos:BAAANQADCgYIBgABNQAECgUICQACAAAAAA==.Daeltha:BAABNQAECoEVAAIDAAkJuBWWBQDEAgADAAkJuBWWBQDEAgAAAA==.Dafdafdaf:BAAANQAECgQIBAAAAA==.Daffenprime:BAAANQAECgcIEQAAAA==.Dailong:BAAANQAECgIIAgAAAA==.Dalux:BAAANQADCgUIBgAAAA==.Danastey:BAAANQADCgYIBgAAAA==.Daneglesack:BAAANQAECgIIAwAAAA==.Danosxd:BAAANQAECgUICQAAAA==.Daragnos:BAAANQAECgcIDgAAAA==.Darkhært:BAAANQAECgQIBgAAAA==.Darkkai:BAAANQAECgQICQAAAA==.Darthmuffin:BAAANQAECgcIDAAAAA==.Daryl:BAAANQAECgYICQABNQAECggIDQACAAAAAA==.Dasprime:BAAANQADCgYICgAAAA==.Dastòmper:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Dayven:BAAANQADCgEIAQAAAA==.',
De='Deadhitmann:BAAANQAECgEIAQAAAA==.Deathbringer:BAAANQAECgYIBQAAAA==.Deathpenance:BAAANQADCgYIBgAAAA==.Deathãngel:BAAANQAECgQIBQAAAA==.Decall:BAEANQAECgMIAwAAAA==.Degraded:BAAANQAECggIAgAAAA==.Delenix:BAAANQADCgYIBgAAAA==.Ders:BAAANQADCggIDgAAAA==.Dessius:BAAANQADCgUIBQAAAA==.Dethstra:BAAANQADCgMIAwABNQADCgYIBgACAAAAAA==.Deüs:BAAANQAECgQIBwAAAA==.',
Di='Diffstyle:BAAANQAECggICAAAAA==.Dionotus:BAAANQADCgcIDQAAAA==.Dirtgrub:BAAANQAECgIIAgAAAA==.Divdan:BAAANQADCggICAAAAA==.Divert:BAAANQADCggICAAAAA==.',
Dk='Dkhaoz:BAAANQAECgcIDgABNQADCgYIDAACAAAAAA==.Dkinabox:BAAANQADCggIAgABNQAECgEIAQACAAAAAA==.',
Do='Docturnal:BAAANQADCgMIAwAAAA==.Dolphina:BAAANQAECgQIBAAAAA==.Donsaul:BAAANQADCggICgAAAA==.Donuts:BAAANQADCgMIAwAAAA==.Doomsure:BAAANQADCgMIAwAAAA==.Doryani:BAAANQAECgQIBAAAAA==.Doømhammer:BAAANQADCggICAAAAA==.',
Dr='Dracburton:BAAANQADCgEIAQAAAA==.Dracnaphobia:BAAANQADCgMIAwABNQAECgIIAgACAAAAAA==.Dragynsabor:BAAANQADCgQIBAAAAA==.Dragynsoul:BAAANQADCgYICAAAAA==.Dranok:BAAANQADCgYICwAAAA==.Dratnosfan:BAAANQADCgYICgABNQAECgUICQACAAAAAA==.Dreamlike:BAABNQAECoEVAAIGAAkJHB8DAgBGAwAGAAkJHB8DAgBGAwAAAA==.Drezco:BAAANQADCgUIBwABNQAECgkJGQAEANYjAA==.Droit:BAAANQAECgMIAgAAAA==.Drstormii:BAAANQAECgEIAQAAAA==.Drumelion:BAAANQAECgIIAgABNQAECgcIEgACAAAAAA==.',
Du='Dukazra:BAAANQADCgYIFQAAAA==.Dunkndonuts:BAAANQAECgQIBAAAAA==.',
['Dé']='Déathy:BAAANQADCgQIBAABNQADCgYIBgACAAAAAA==.',
Ea='Earthencore:BAAANQAECgQICQAAAA==.',
Ed='Edgyboy:BAAANQADCgcIEgAAAA==.Edjelord:BAAANQADCgcICQAAAA==.',
Eg='Egirltank:BAAANQADCgcIDQABNQAECgcICwACAAAAAA==.',
El='Elaxa:BAAANQADCggICAABNQAECgkJGAAHAMwhAA==.Eldanath:BAAANQADCgYIBgAAAA==.Elnaa:BAAANQADCgUIBQAAAA==.Elteethree:BAAANQAECgYIEAABNQAECgkJGQABAMYeAA==.Elunelock:BAAANQADCggICAAAAA==.Elunepal:BAAANQAECgIIAgAAAA==.Elys:BAAANQAECgEIAQAAAA==.',
Em='Emalynn:BAAANQADCgYIBgAAAA==.Emilyfrost:BAAANQADCgQIBAAAAA==.',
En='Enigmà:BAABNQAECoEcAAMIAAgJcBHKSAAUAgAIAAgJcBHKSAAUAgAJAAEJ4AHYIAAuAAAAAA==.Enmanuel:BAAANQAECgEIAwAAAA==.',
Ep='Epyôn:BAAANQAECggIEAAAAA==.',
Er='Eriodara:BAAANQADCgIIAgAAAA==.',
Es='Escas:BAAANQAECgUICQAAAA==.Escaz:BAAANQADCggICAAAAA==.Esrahaddon:BAAANQAECgUICAAAAA==.',
Ev='Evanora:BAAANQAECgQIBAAAAA==.Evillinx:BAAANQAECgEIAQAAAA==.Evilmaru:BAAANQAECgEIAQAAAA==.Evokelion:BAAANQAECgMIAwABNQAECgcIEgACAAAAAA==.',
Ew='Ewok:BAAANQADCgQIBAAAAA==.',
Ex='Exploited:BAAANQABCgQIBgAAAA==.',
Fa='Factz:BAAANQADCgEIAQAAAA==.Faespalmn:BAAANQAECgcIDgAAAA==.Fatalstab:BAAANQADCgYIBgAAAA==.Fauin:BAAANQADCgYIBgAAAA==.',
Fe='Fenthead:BAAANQADCgYIBgABNQAECgcICwACAAAAAA==.Fernandôge:BAAANQAECgQICgAAAA==.',
Fi='Fidel:BAAANQAECgYIBgAAAA==.Fil:BAAANQAECgYIBwAAAA==.Fisac:BAABNQAECoEYAAIKAAkJoRhhCgC8AgAKAAkJoRhhCgC8AgAAAA==.Fishbubble:BAAANQABCgQIBQAAAA==.',
Fl='Fletchtern:BAAANQADCgEIAQABNQAECgQIBgACAAAAAA==.Flexicute:BAAANQADCgcIBwAAAA==.Flexlock:BAAANQADCgMIAwAAAA==.Flextime:BAAANQAECgMIAwAAAA==.',
Fo='Folius:BAACNQAFFIEIAAMLAAUJ1hQUAQB3AQALAAQJPRkUAQB3AQAMAAEJOwMMCABUAAA1AAQKgRoAAwsACQlYJjUAAOgDAAsACQlYJjUAAOgDAAwAAwn7HbgkAPsAAAAA.Fortyourself:BAAANQADCggICAABNQAFFAEIAQACAAAAAA==.',
Fr='Franky:BAAANQAECgYIBgAAAA==.Franzu:BAAANQAECgUIBgAAAA==.Freehits:BAAANQADCgEIAQAAAA==.Freelaughs:BAAANQADCgQIBAAAAA==.Friggitte:BAAANQADCgYIDAAAAA==.Friholy:BAAANQAECgQIBAABNQAECgcIDQACAAAAAA==.Frostdragyn:BAAANQADCgYIBgAAAA==.Frosteviã:BAAANQADCgIIAgAAAA==.',
Fu='Full:BAAANQADCggIFAAAAA==.Furgoblin:BAAANQADCgYIBwABNQAECgQIBgACAAAAAA==.',
['Fâ']='Fâdêd:BAAANQADCggICAAAAA==.',
['Fë']='Fëanör:BAAANQAECgQICAAAAA==.',
['Fø']='Førce:BAAANQAECgEIAQAAAA==.',
Ga='Gabi:BAAANQADCgcIBwAAAA==.Gacrüx:BAAANQADCgcIDwAAAA==.Galadrìel:BAAANQAECgcIDwAAAA==.Galadrìèl:BAAANQADCggIDQAAAA==.Gambol:BAAANQADCgYIBgAAAA==.',
Gh='Ghorn:BAAANQAECgEIAQAAAA==.',
Gl='Glareaforsor:BAAANQADCgIIAgAAAA==.Glimpse:BAAANQAECgEIAQAAAA==.',
Go='Gochurass:BAAANQADCgYICQAAAA==.',
Gr='Grabbyhands:BAAANQADCgEIAQAAAA==.Grapthar:BAEANQADCggIDgABNQAECgMIAwACAAAAAA==.Grenth:BAAANQADCgMIAwAAAA==.Greyarrow:BAAANQAECgMIAwAAAA==.Greæd:BAABNQAECoEbAAMNAAkJEySbAgBqAwANAAkJEySbAgBqAwAOAAYJyx0WBQCtAQAAAA==.Grimgown:BAAANQAECgMIAwABNQAECgUIBQACAAAAAA==.Grimreaper:BAAANQADCggIEQAAAA==.Grizzard:BAAANQAECgEIAQAAAA==.Gruckek:BAAANQAECgcIEAAAAA==.',
Gu='Gulanis:BAAANQAECgEIAQAAAA==.',
Gw='Gwendlyne:BAAANQAECgEIAQAAAA==.',
['Gó']='Góddess:BAAANQADCggICQAAAA==.',
Ha='Hag:BAAANQAECgQIBAABNQAFFAIIAgACAAAAAA==.Hakarii:BAAANQADCgYIBQABNQAFFAEIAQACAAAAAA==.Halloffaith:BAAANQAECgcIDwAAAA==.Harissa:BAAANQADCgEIAQABNQADCgYIBgACAAAAAA==.Hawgneto:BAAANQADCggICQAAAA==.',
He='Hellig:BAAANQAECgUICQAAAA==.Hellofriday:BAAANQADCggICAAAAA==.Hellíg:BAAANQADCggIDgAAAA==.Hetzfury:BAAANQADCgEIAQAAAA==.Heyman:BAAANQADCgcIEgAAAA==.',
Hi='Hideyerweed:BAAANQADCgQIBAABNQAECgcIDQACAAAAAA==.Higi:BAAANQADCgYIBgAAAA==.',
Ho='Holistic:BAAANQAECggIEAAAAA==.Holyclanx:BAAANQADCgYIBgAAAA==.Holyzamboni:BAAANQAECgcIBwAAAA==.Honeyblunt:BAAANQADCgIIAgAAAA==.Hotchocmilk:BAAANQAECgMIBAAAAA==.',
Hr='Hr:BAAANQADCgcIBwAAAA==.',
Hu='Huntaa:BAAANQAECgYICwAAAA==.Hurají:BAAANQAFFAIIAgAAAA==.Huråji:BAABNQAECoEaAAIPAAkJCCGEAQBcAwAPAAkJCCGEAQBcAwABNQAFFAIIAgACAAAAAA==.',
Il='Ilnookll:BAAANQADCgUIBwAAAA==.',
Im='Imblooms:BAAANQADCgEIAQAAAA==.Imbooms:BAAANQADCgYIBgAAAA==.Imryl:BAAANQAECgYICQAAAA==.',
Io='Ionea:BAAANQADCgYIBgABNQAECgUICAACAAAAAA==.',
Ir='Ironpaws:BAAANQAECgQIBgAAAA==.Iryssoscaly:BAAANQADCgIIAgAAAA==.',
Is='Isa:BAAANQAECgYICgABNQAFFAEIAQACAAAAAA==.Isaa:BAAANQAFFAEIAQAAAA==.Istredd:BAAANQADCgIIAgAAAA==.',
It='Itamedruids:BAAANQADCggIDgABNQAECgEIAQACAAAAAA==.',
Ja='Jackrackham:BAAANQAECgMIBAAAAA==.Jakuza:BAAANQADCgYIBgABNQAECgMIAwACAAAAAA==.Jaydeep:BAAANQABCgIIAgAAAA==.',
Jd='Jdub:BAAANQAECgIIAgAAAA==.',
Je='Jebydk:BAAANQADCggIGQABNQAECgkJGAAQAFQcAA==.Jebysham:BAABNQAECoEYAAQQAAkJVBw8CgAOAwAQAAkJVBw8CgAOAwARAAEJmB0iFwBZAAABAAIJRAIdggBTAAAAAA==.Jeffybubbles:BAAANQADCgYICAAAAA==.Jeffytotems:BAAANQAECgUIBwAAAA==.Jelsy:BAAANQAECgMIAwAAAA==.Jesly:BAAANQADCgUIBwABNQAECgMIAwACAAAAAA==.Jessibella:BAABNQAECoEbAAINAAkJMhgzDACzAgANAAkJMhgzDACzAgAAAA==.',
Jh='Jhnstzy:BAAANQADCgYIBgAAAA==.',
Ji='Jimmyhoofa:BAAANQABCgEIAQABNQADCgYIDAACAAAAAA==.',
Jo='Johnsteez:BAAANQADCgcIDwAAAA==.Jorndalf:BAAANQAECgUICAAAAA==.',
Jt='Jt:BAAANQABCgIIAgAAAA==.',
Ju='Juggz:BAAANQAECgQIBAAAAA==.Justabutcher:BAAANQAECgQIBwAAAA==.',
Jw='Jwag:BAAANQADCgYIBwAAAA==.',
['Jê']='Jêcht:BAAANQAECggIEwAAAA==.',
Ka='Kafur:BAAANQAECgQIBAAAAA==.Kaiido:BAAANQAECgEIAgABNQAFFAEIAQACAAAAAA==.Karmanda:BAAANQADCgYICwAAAA==.Kattel:BAAANQADCggIDAAAAA==.',
Ke='Keither:BAAANQABCgIIAgABNQADCgYIDAACAAAAAA==.Kelendor:BAAANQAECgcIEQAAAA==.Kellandil:BAAANQADCgQICQAAAA==.Kenju:BAAANQAECgEIAQAAAA==.Kensie:BAAANQAECgUIBQAAAA==.',
Kh='Khlampz:BAAANQAECgQIBwABNQAECgUIBQACAAAAAA==.Khlampzight:BAAANQAECgUIBQAAAA==.Khlampzoker:BAAANQADCggICAABNQAECgUIBQACAAAAAA==.Khondor:BAAANQADCgIIAwAAAA==.',
Ki='Kigen:BAAANQAECgEIAQAAAA==.Kikurface:BAAANQADCgcIEAAAAA==.Kimjungun:BAAANQADCgEIAQAAAA==.Kiranax:BAABNQAECoEeAAQEAAkJJyJpAgCjAwAEAAkJJyJpAgCjAwAFAAMJVAdyUQCJAAASAAEJ1RIKMQA7AAAAAA==.Kittensune:BAAANQABCgIIAgAAAA==.',
Ko='Koinu:BAAANQAECgcIEQAAAA==.Kooriaisu:BAAANQADCgUIBQAAAA==.Korbun:BAAANQADCgYICAAAAA==.Kovskii:BAAANQADCggIFAAAAA==.',
Kr='Krad:BAAANQADCggIEwAAAA==.Kriathura:BAAANQAECgYICgAAAA==.',
Ku='Kukui:BAAANQABCgIIAgABNQAECgMIBAACAAAAAA==.',
Kw='Kwangpow:BAAANQAECgIIBAAAAA==.',
['Kà']='Kàkàshi:BAAANQAECgUICwAAAA==.',
La='Lambbchopp:BAAANQADCgQICQAAAA==.Lassitar:BAAANQADCgEIAQAAAA==.Lazyrage:BAAANQAECgQIBAAAAA==.Lazyreaper:BAAANQADCgUICwABNQAECgQIBAACAAAAAA==.',
Le='Lebronto:BAAANQAECgcIDQAAAA==.Legsquats:BAAANQADCgQIBAAAAA==.Lessirs:BAAANQADCgcIDwAAAA==.Lexatron:BAAANQABCgEIAQAAAA==.',
Li='Lichnaught:BAAANQADCgUIBwABNQAECgMIAwACAAAAAA==.Lifetapped:BAAANQADCgcIEAAAAA==.Lilfluffy:BAAANQAECgIIAgAAAA==.Liquid:BAAANQADCgcIEAAAAA==.',
Ll='Llikdaor:BAAANQAECgQIBQAAAA==.',
Lo='Loaded:BAAANQAECgUICAAAAA==.Loikk:BAAANQADCgMIAwAAAA==.Loodacrits:BAAANQAECgUIBwAAAA==.',
Lu='Lushylock:BAAANQADCgEIAQAAAA==.',
Ma='Macklin:BAAANQAECgEIAQAAAA==.Maddalynn:BAAANQAECgUICQAAAA==.Maelstrox:BAAANQADCgUIDQAAAA==.Magandadrake:BAAANQAECgcIEAAAAA==.Magerita:BAAANQADCgMIAwAAAA==.Magharat:BAAANQADCgYIDwABNQAECgcIDwACAAAAAA==.Magicman:BAAANQADCgYIBgAAAA==.Malacanthet:BAAANQADCggICAAAAA==.Mandelstam:BAAANQAECgIIAgAAAA==.Mangkanor:BAAANQADCgMIBAAAAA==.Mangoloidman:BAAANQADCgIIAgABNQADCgIIAgACAAAAAA==.Marsan:BAAANQABCgQIBgAAAA==.Marxen:BAAANQADCgQIBAAAAA==.',
Mc='Mcsstab:BAAANQADCgYIBgAAAA==.',
Me='Meatballer:BAAANQADCgQIBAAAAA==.Meatballz:BAAANQAECgUICAAAAA==.Mecalux:BAAANQADCgQIBAAAAA==.Meliodäs:BAAANQADCgYIBgABNQADCgYICQACAAAAAA==.Meloco:BAAANQAECgEIAQAAAA==.Melody:BAABNQAECoEaAAINAAkJAya9AAC5AwANAAkJAya9AAC5AwAAAA==.Menj:BAAANQADCgQIBgABNQAECgEIAQACAAAAAA==.Meno:BAAANQADCggICAAAAA==.Meowcheese:BAAANQAECgEIAQAAAA==.Meowmix:BAAANQADCgUIBQABNQADCgYIBgACAAAAAA==.Meridah:BAAANQADCgUIBQAAAA==.Mesosphere:BAEANQAECgEIAQAAAA==.',
Mi='Midorii:BAAANQADCgcIBwAAAA==.Migpala:BAAANQADCgcIEwAAAA==.Miiniimaage:BAAANQAECgIIAgAAAA==.Milkmann:BAAANQABCgIIAgAAAA==.Milkymoos:BAAANQAECgMIBAAAAA==.Minar:BAAANQAECgUICQABNQAECgcIDAACAAAAAA==.Minoic:BAAANQADCgYIDwAAAA==.Mistamiyagi:BAAANQAECgEIAQAAAA==.Mistchivus:BAAANQAECgQIBAAAAA==.Mistelion:BAAANQAECgMIAwABNQAECgcIEgACAAAAAA==.',
Mo='Mobbster:BAAANQADCggIFAAAAA==.Mohnster:BAAANQADCgMIBAAAAA==.Moisttotems:BAAANQADCgEIAQAAAA==.Monipouch:BAAANQAECgMIBQAAAA==.Moonchicken:BAAANQADCgQIBAAAAA==.Moondaisy:BAAANQADCgIIAgAAAA==.Moopocalypse:BAAANQAECgQIBAAAAA==.Moosenukle:BAAANQADCgQIBAAAAA==.Morphaeus:BAAANQADCgUICgAAAA==.Mortar:BAAANQAECgMIAwAAAA==.Mozrog:BAAANQAECgUIBgAAAA==.',
Mu='Muffblaster:BAAANQAECggIDwAAAA==.Murphet:BAAANQAECgIIAgAAAA==.',
My='Mythrix:BAAANQAECgIIAgABNQAFFAEIAQACAAAAAA==.',
['Mí']='Míra:BAAANQADCgcIDAAAAA==.',
['Mó']='Mónsoon:BAAANQABCgUIBQAAAA==.',
['Mö']='Mönïca:BAAANQAECgIIAgAAAA==.Mörrys:BAAANQAECgIIAgAAAA==.',
Na='Narrath:BAAANQABCgYICAAAAA==.Nathenatra:BAAANQADCgQIBAABNQAECgcIEQACAAAAAA==.',
Ne='Neeko:BAAANQAECgQIBgAAAA==.Neonmoose:BAAANQADCggIEAAAAA==.Nezbrez:BAAANQADCgUICgAAAA==.Nezzrad:BAAANQADCgMIAwAAAA==.',
Nh='Nhthree:BAAANQAECgQICAAAAA==.',
Ni='Niklaws:BAAANQAECgEIAQABNQAECgcIDQACAAAAAA==.',
No='Nofsha:BAAANQADCgUIBQABNQAECgIIAgACAAAAAA==.Noktyx:BAAANQABCgYIDAAAAA==.Nomoney:BAAANQAECgEIAgAAAA==.Norasong:BAAANQADCgcIEAAAAA==.Nostick:BAAANQAECgcIDwAAAA==.Novacrono:BAAANQAECgcIDgAAAA==.Noxioustoast:BAAANQADCgQIBgAAAA==.Nozdog:BAAANQADCgQIBAAAAA==.',
Nu='Nuke:BAAANQAECgQIDwAAAA==.',
['Nô']='Nôôk:BAAANQAECgEIAQAAAA==.',
Od='Odiare:BAAANQADCgUIBQAAAA==.',
Op='Opta:BAAANQADCgYIDAAAAA==.',
Or='Orkhis:BAAANQAECgUICQAAAA==.',
Ou='Outbrèak:BAAANQAECgMIAwAAAA==.',
Ow='Owo:BAAANQABCgQIBQABNQAECgMIBAACAAAAAA==.',
['Oá']='Oáklánd:BAAANQADCggIAgAAAA==.',
Pa='Pakuru:BAAANQAECgUICQAAAA==.Pal:BAAANQAECgIIAgAAAA==.Palachin:BAAANQAECgQIBgAAAA==.Paladelion:BAAANQAECgUIDAABNQAECgcIEgACAAAAAA==.Paleonebula:BAAANQADCgYIBgAAAA==.Pallmtree:BAAANQAECgIIAgABNQAECgUIBQACAAAAAA==.Pallyberry:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Pangittroll:BAAANQAECgUIBQAAAA==.Papatotems:BAAANQADCgQIBAAAAA==.Papå:BAAANQAECgEIAQAAAA==.Pawtirra:BAAANQADCgIIAgAAAA==.',
Pe='Perfume:BAAANQAECgEIAQAAAA==.Petri:BAAANQAECgQIBwAAAA==.',
Pi='Pickwaton:BAAANQAECgcICgAAAA==.Pipen:BAACNQAFFIEGAAITAAQJwwOlAgAqAQATAAQJwwOlAgAqAQA1AAQKgRkAAxMACQlUC4waAD4CABMACQlUC4waAD4CABQABwnqFBY0AMIBAAAA.Pixelglitter:BAAANQADCgYIBgAAAA==.',
Pl='Pld:BAAANQADCgcIBwAAAA==.',
Po='Potatatoes:BAAANQADCgUIBQAAAA==.Poxrot:BAAANQADCgQIBAABNQADCgcIDgACAAAAAA==.',
Pr='Praize:BAAANQAECgcIEQAAAA==.Press:BAAANQAFFAIIAgAAAA==.Prìde:BAAANQAECgQIBAABNQAECgkJGwANABMkAA==.',
Ps='Psykopathik:BAAANQAECgMIAwAAAA==.',
Pu='Puddl:BAABNQAECoEXAAMQAAgJMRsMEwCRAgAQAAgJMRsMEwCRAgABAAgJyxedGgA1AgAAAA==.Purrsephone:BAAANQADCgEIAQAAAA==.',
Py='Pyrocutie:BAAANQADCggICAABNQAECggIEAACAAAAAA==.',
Qa='Qaa:BAAANQAECgQIBgAAAA==.',
Qh='Qhaos:BAAANQADCgYIBgABNQADCgYIDAACAAAAAA==.Qhaoss:BAAANQADCgYIDAAAAA==.',
Qi='Qirl:BAAANQADCgMIAwAAAA==.',
Qt='Qti:BAAANQADCgYIEgAAAA==.',
Qu='Quadnines:BAAANQAECgMIAwAAAA==.Quelivia:BAAANQADCgEIAQABNQAECgYICQACAAAAAA==.Ques:BAAANQADCgYICgAAAA==.Quesly:BAAANQAECgIIAgAAAA==.Quetzacoatl:BAAANQAECgQIBwAAAA==.',
Ra='Rabbit:BAAANQAFFAIIAgAAAA==.Racophorus:BAAANQADCgcIEAAAAA==.Raffe:BAAANQAECgQIBAAAAA==.Rammsteen:BAAANQADCgYIDQAAAA==.Rarity:BAAANQAECgEIAwAAAA==.Ratarga:BAAANQAECgcIDwAAAA==.Rattroll:BAAANQADCgUIBQABNQAECgcIDwACAAAAAA==.Ravenaa:BAAANQAECgYICwAAAA==.',
Re='Readycheck:BAAANQADCgEIAQAAAA==.Reallywanna:BAAANQAECgEIAQAAAA==.Reddragyn:BAAANQAECgQIBAAAAA==.Reeves:BAAANQAECgEIAgAAAA==.Reggiez:BAAANQADCggIGAAAAA==.Reinbert:BAAANQADCgMIAwABNQADCgYIBgACAAAAAA==.Rektski:BAAANQAECgcIDAAAAA==.Remixi:BAAANQABCgUIBwAAAA==.Renzer:BAAANQADCgcIEAAAAA==.Reprosal:BAAANQAECgMIAwABNQAECgUIBQACAAAAAA==.Restasis:BAAANQADCgUIBwAAAA==.Retburn:BAAANQAECgYICwAAAA==.Reveluv:BAAANQADCggICgAAAA==.',
Ri='Rickehlol:BAAANQADCgYICgAAAA==.Righturn:BAAANQAECgQIBgAAAA==.Rikkeh:BAAANQADCgIIAgAAAA==.Rinaera:BAAANQAECgMIAwAAAA==.',
Ro='Roahr:BAAANQADCgUIBAAAAA==.Rollinsmacks:BAAANQADCgIIAgAAAA==.Rollsforham:BAAANQADCggIDgAAAA==.Rondali:BAAANQADCggICAAAAA==.Rotheris:BAAANQAECgUICgAAAA==.Rottentreats:BAAANQADCgYICQAAAA==.Rottie:BAAANQAECgcIEAAAAA==.',
Rt='Rts:BAABNQAECoEVAAIIAAkJ2x0QFwANAwAIAAkJ2x0QFwANAwAAAA==.',
Ru='Rufio:BAAANQAFFAEIAQAAAA==.Rufiu:BAAANQAECgQIBwAAAA==.Rufiz:BAAANQADCggICAAAAA==.',
Ry='Ryogen:BAAANQAECgYIDAAAAA==.',
['Ré']='Rén:BAAANQADCgYIBgAAAA==.',
Sa='Saarahkin:BAAANQADCgUIBQAAAA==.Sablewhisper:BAAANQAECgEIAQAAAA==.Sabryel:BAAANQAECgMIBwAAAA==.Saintvyn:BAAANQAECggIEAAAAA==.Salmonroll:BAAANQAECgMIAwAAAA==.Salos:BAAANQADCgYIBgAAAA==.Salvation:BAAANQADCgcIBwAAAA==.Samael:BAAANQADCgQIBAAAAA==.Sandarah:BAAANQAECggIDwABNQAECgkJGgANAAMmAA==.Sapling:BAAANQAECgQIBgAAAA==.Sathic:BAAANQAECgUIBwAAAA==.Satreser:BAAANQAECgMIAwAAAA==.',
Sc='Scallywrath:BAAANQADCgUIBQAAAA==.Scaretale:BAAANQADCgQIBgAAAA==.Scribbles:BAAANQAECggIEQAAAA==.Scribblesz:BAAANQADCgYIBgAAAA==.Scòtt:BAAANQADCgUIBQAAAA==.',
Se='Seanthepally:BAAANQAECgQIBAABNQAECgYICwACAAAAAA==.Seantheshamm:BAAANQAECgYICwAAAA==.Secihots:BAAANQAECgYIDQAAAA==.Seidhkona:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.Seishirou:BAAANQADCggICAABNQAECgUIBQACAAAAAA==.Serialheal:BAAANQADCgYIDgABNQAECgQIBgACAAAAAA==.Sevalynn:BAAANQADCggICAAAAA==.',
Sh='Shadalune:BAAANQAECggIEQAAAA==.Shamanelion:BAAANQAECgcIEgAAAA==.Shamnobi:BAAANQADCgQIBAAAAA==.Shazza:BAAANQADCgIIAgAAAA==.Shinso:BAAANQAECggIDQAAAA==.Shiwang:BAAANQAECgQIBAAAAA==.Shockazuwu:BAAANQAECgcIDQAAAA==.Shocktagon:BAAANQADCgEIAQAAAA==.Shocktherapy:BAAANQAECgEIAQAAAA==.Shockzilla:BAAANQAECgMIAwAAAA==.Shockér:BAAANQAECgIIAgAAAA==.Shodoroki:BAAANQAECgUIBQAAAA==.Shuu:BAAANQAECgQIBgAAAA==.Shwoidlord:BAAANQAECgQIBAABNQAECgcIDQACAAAAAA==.Shwoop:BAAANQAECgQIBAABNQAECgcIDQACAAAAAA==.',
Si='Sigurrose:BAAANQAECgIIBAAAAA==.',
Sk='Skitzosvnff:BAAANQAECgYIDAAAAA==.',
Sm='Smetrios:BAAANQADCggICAABNQAECgQIBAACAAAAAA==.Smokedh:BAAANQAECgQIBAABNQAECgcIDQACAAAAAA==.Smokezug:BAAANQAECgcIDQAAAA==.',
Sn='Snorter:BAAANQADCggIDQAAAA==.Snowfury:BAAANQADCgEIAQABNQAECgcIEQACAAAAAA==.Snowlock:BAAANQADCgYIEAAAAA==.Snowrain:BAAANQAECgcIDwAAAA==.',
So='Sotek:BAAANQABCgIIAgAAAA==.Soulster:BAAANQADCgEIAQAAAA==.Sourdeath:BAAANQAECgMIAwAAAA==.',
Sp='Spinningbrew:BAAANQADCgcIEgAAAA==.Spit:BAAANQAECgEIAQAAAA==.',
Ss='Ssnoosnoo:BAAANQADCggIEQAAAA==.',
St='Stanchion:BAAANQADCgUICAAAAA==.Steelmessiah:BAAANQADCgYIBgAAAA==.Stinko:BAAANQAECgIIAQABNQAECgkJGgAVABkhAA==.Stonecrusade:BAAANQAECgEIAQAAAA==.Stonedhokage:BAAANQAECgcIDAAAAA==.Stopthebleed:BAAANQADCggIDwAAAA==.Sturdy:BAAANQADCgYIBgAAAA==.Sty:BAABNQAECoEYAAMWAAkJjx6bBAAcAwAWAAkJYx6bBAAcAwAHAAgJjBlbEABmAgAAAA==.Ståb:BAAANQADCgYIBgABNQAECggIHAAIAHARAA==.Stårr:BAAANQADCgYIBwAAAA==.',
Su='Suffering:BAAANQADCgUIBQAAAA==.Suicideblond:BAAANQADCggIEAAAAA==.Supadrac:BAAANQAFFAEIAQAAAA==.Surfnturf:BAAANQAFFAIIBAAAAQ==.Surging:BAAANQAECgQIBwAAAA==.Suri:BAAANQAECgIIAgABNQAECgUIBwACAAAAAA==.Surii:BAAANQAECgUIBwAAAA==.',
Sw='Swaazz:BAAANQAECgMIBwAAAA==.Swerve:BAAANQAECgMIBAAAAA==.Swinybswipen:BAAANQAECgEIAQAAAA==.',
Sy='Sykocious:BAAANQAECgYICwAAAA==.Sylleria:BAAANQAECgEIAQAAAA==.Syllia:BAAANQAECgYIBQABNQAECgcIDQACAAAAAA==.Syngatesx:BAAANQADCggIAQAAAA==.Syphilia:BAAANQAECggIDgAAAA==.',
Sz='Szeto:BAAANQAECgMIAwABNQAFFAEIAQACAAAAAA==.',
['Sè']='Sèanthewarr:BAAANQADCgUIBQABNQAECgYICwACAAAAAA==.',
Ta='Tacocát:BAAANQAECgIIAgABNQAFFAIIBAACAAAAAA==.Tacosback:BAAANQADCgEIAQABNQAFFAIIBAACAAAAAA==.Tacosdk:BAAANQAFFAIIBAAAAA==.Tacoslop:BAAANQAECggIEAABNQAFFAIIBAACAAAAAA==.Tacosneak:BAAANQAECgIIAwABNQAFFAIIBAACAAAAAA==.Talonarayan:BAAANQADCgcIEAAAAA==.',
Te='Teebonez:BAAANQAECgQIBgAAAA==.Teesdays:BAAANQABCgQIBwAAAA==.Tewasha:BAAANQAECgcIEAAAAA==.',
Th='Thalryn:BAAANQADCgMIAwAAAA==.Thaylen:BAAANQADCgYIBQAAAA==.Thedoofy:BAAANQADCgQIBQAAAA==.Threellamas:BAAANQAECgYIDQAAAA==.Thuringwethl:BAAANQADCgYIEAAAAA==.',
Ti='Tidyswet:BAAANQADCgYIBgAAAA==.Tinydonny:BAAANQADCgQIBQAAAA==.',
To='Tonylildik:BAAANQAECgEIAQABNQAECgkJFwAIAK4ZAA==.Toolh:BAAANQADCgUIBQAAAA==.Toopac:BAEANQAECggIEQAAAA==.Totö:BAAANQAECgUIDQAAAA==.',
Tr='Tramana:BAAANQAECgUICQAAAA==.Trauk:BAAANQAECgIIAgAAAA==.Triggéred:BAAANQADCgQIBAAAAA==.Triig:BAAANQAECgIIAgAAAA==.Trollcopter:BAAANQAECgIIAgABNQAECgIIAgACAAAAAA==.Trollwíthbow:BAAANQADCggIFQAAAA==.',
Tu='Turr:BAAANQADCgYICwAAAA==.',
Tw='Tweedledumb:BAAANQAECgQIBAAAAA==.Twìnky:BAAANQAECggIEQAAAA==.',
Ul='Ulfric:BAAANQADCgIIAgAAAA==.',
Un='Unbreakkable:BAAANQADCggICAABNQAECgcIDgACAAAAAA==.Unclepete:BAAANQAECgUIBAAAAA==.Unstobubble:BAAANQABCgIIAgAAAA==.',
Ur='Urouge:BAAANQADCgYIBgABNQAFFAEIAQACAAAAAA==.',
Va='Vacula:BAAANQAECgMIAwAAAA==.Vaelyriana:BAAANQAECgQICAAAAA==.Valreaux:BAAANQAECgQIBAAAAA==.Vandalism:BAAANQADCgYIEgAAAA==.Vanian:BAAANQADCgEIAQAAAA==.',
Vd='Vdyr:BAAANQADCggIFAAAAA==.',
Ve='Vex:BAAANQABCgMIAwAAAA==.',
Vi='Vilgefortz:BAAANQAECgQIBgAAAA==.Vivelf:BAAANQADCggIAQAAAA==.',
Vo='Voidborn:BAAANQAECgQIBwAAAA==.Voidling:BAAANQAECgIIAgAAAA==.Voidturned:BAAANQADCgQIBAAAAA==.Vortexis:BAAANQAECgIIAgAAAA==.',
Vu='Vulpurra:BAAANQAECgEIAQAAAA==.Vurm:BAABNQAECoEYAAIXAAgJXx6IEwDtAgAXAAgJXx6IEwDtAgAAAA==.',
Vy='Vytamin:BAAANQAECgEIAQAAAA==.',
['Vâ']='Vâlinoth:BAAANQAECgYIDgAAAA==.',
['Vó']='Vólkan:BAAANQADCgcIFAAAAA==.',
Wa='Walkinghealz:BAAANQADCgQIBQABNQAECgIIAgACAAAAAA==.',
We='Wengo:BAAANQADCgIIBAAAAA==.',
Wh='Whistlejinky:BAAANQADCgQIBAAAAA==.',
Wi='Willywonkie:BAAANQADCgQIBgAAAA==.Windfrey:BAAANQAECgUIBwAAAA==.Windsong:BAAANQADCgUIBQAAAA==.Winghollow:BAAANQADCgIIAgAAAA==.Wintershock:BAAANQAECgcICgAAAA==.Wisk:BAAANQAECgMIAwAAAA==.',
Wl='Wll:BAAANQAECgQIBgABNQAECgcIEgACAAAAAA==.Wlx:BAAANQAECgcIEgAAAA==.',
Wo='Wobs:BAAANQAFFAEIAgAAAA==.Woopoles:BAAANQADCggIFAAAAA==.',
Wr='Wredgeek:BAAANQADCgYIDQAAAA==.',
Wy='Wy:BAAANQADCggIDwAAAA==.',
Xa='Xavierboí:BAAANQAECgQIBwAAAA==.',
Xi='Xileon:BAAANQAECgMIAwAAAA==.',
Ya='Yabishus:BAAANQAECgEIAQAAAA==.Yahboibangz:BAAANQAECgEIAQAAAA==.Yamajin:BAAANQADCgIIAgAAAA==.',
Yc='Ycetz:BAAANQADCgYIBgABNQAECgQIBgACAAAAAA==.',
Ye='Yelacsa:BAAANQADCgYIBgABNQAECgcIDQACAAAAAA==.',
Yo='Yoshu:BAAANQAECgQIBQAAAA==.',
Yu='Yukyukyuk:BAAANQABCgQIBAAAAA==.',
Za='Zanthu:BAEANQADCgYIBgABNQAECggIEQACAAAAAA==.Zanu:BAAANQADCgYICwAAAA==.Zardon:BAAANQADCgYIBgABNQAECgkJGAADAJMlAA==.',
Ze='Zecar:BAAANQADCgUIBQAAAA==.Zengard:BAAANQADCgQIBAAAAA==.Zenkic:BAAANQADCgEIAQAAAA==.Zenlock:BAAANQADCgYIBgABNQAECgQIBgACAAAAAA==.',
Zi='Zivá:BAAANQABCgYIBgAAAA==.',
Zo='Zoralari:BAAANQAECgUIBwAAAA==.Zorke:BAAANQAECgQIBQAAAA==.',
Zu='Zulnas:BAAANQAECgYIBgAAAA==.',
['Ön']='Önonta:BAAANQAECgIIAgAAAA==.Önotoes:BAAANQAECgMIAwAAAA==.',
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
