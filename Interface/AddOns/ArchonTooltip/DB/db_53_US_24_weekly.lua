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
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=53,date='2026-09-08',data={Ad='Addy:BAAANQAECgMIBAAAAA==.Adelethe:BAAANQADCgYIBgAAAA==.',
Ae='Aestian:BAAANQADCggIEQAAAA==.',
Ah='Ahhotep:BAAANQADCgEIAQAAAA==.',
Ai='Ailysely:BAAANQADCgUICQAAAA==.Aispere:BAAANQADCgEIAQABNQADCgQICgABAAAAAA==.',
Al='Alerzhulan:BAAANQAECgIIAgAAAA==.Alfurn:BAAANQADCgIIAgAAAA==.Aliveknightt:BAAANQADCggICAAAAA==.Alorely:BAAANQAECgIIAgAAAA==.',
Am='Amanara:BAAANQADCgcICwAAAA==.Amoonia:BAAANQADCgUIBQAAAA==.',
An='Anciientpaw:BAAANQAECgYICwAAAA==.Andrasomnius:BAAANQADCgcIBwAAAA==.Angbar:BAAANQADCggIFgAAAA==.Anguirus:BAAANQAECgMIBAAAAA==.Anuksunàmun:BAAANQADCgYIDAAAAA==.',
Aq='Aqulenas:BAAANQAECgEIAQAAAA==.',
Ar='Arakhan:BAAANQADCgIIAgAAAA==.Arcadian:BAAANQAECgUICwAAAA==.Arceeprime:BAAANQADCgEIAgAAAA==.Arextheelder:BAAANQAECgEIAQAAAA==.Argentum:BAAANQADCggICAABNQAECgMIBAABAAAAAA==.Armorscales:BAAANQAECgcIEQAAAA==.Arntraz:BAAANQADCgYIBgAAAA==.Arrabbiato:BAAANQADCgQIBAAAAA==.Arronaxx:BAAANQADCgYIBgAAAA==.Arçadia:BAAANQAECgIIAgAAAA==.',
As='Ashtori:BAAANQABCgQIBgAAAA==.Astayoni:BAAANQADCgUICwAAAA==.Asterfleur:BAAANQADCgYIBwABNQAECgEIAQABAAAAAA==.Astrine:BAAANQAECgcIBwAAAA==.',
At='Ataraxya:BAAANQADCggIEAAAAA==.',
Au='Auberon:BAAANQAECgYICgAAAA==.Aufta:BAAANQAECgEIAQAAAA==.Aumer:BAAANQABCgYIBQAAAA==.',
Az='Azi:BAAANQAFFAEIAQAAAA==.Azurite:BAAANQADCgYIDwAAAA==.',
Ba='Backpedal:BAAANQADCgcIDAAAAA==.Badankhadonk:BAAANQAECgcIDQAAAA==.Bakkutteh:BAAANQABCgIIBAAAAA==.Balen:BAAANQADCggIDgAAAA==.Bandersin:BAAANQADCgUIBQAAAA==.Bansheex:BAAANQADCgQIBAAAAA==.',
Be='Beefmuffinz:BAAANQAECgcIBwAAAA==.Beethozart:BAAANQADCgUICAAAAA==.Belcebu:BAAANQABCgQIBgAAAA==.Belholy:BAAANQADCggIEwAAAA==.Bellafleur:BAAANQABCgYICAABNQAECgEIAQABAAAAAA==.Bendeekay:BAAANQAECgcIDQAAAA==.Bethgibbons:BAAANQADCgQIBQAAAA==.',
Bg='Bgpocalypse:BAAANQADCgYIBgAAAA==.',
Bl='Blackblood:BAAANQAECgIIAgAAAA==.Bloodache:BAAANQAECgIIAgAAAA==.Blux:BAAANQADCgYIBgAAAA==.',
Bo='Boil:BAAANQAECgEIAQAAAA==.Bonemarrow:BAAANQAECgIIAgAAAA==.',
Br='Brakeable:BAAANQADCgIIBAAAAA==.Braké:BAAANQAECgIIAgAAAA==.Brewskies:BAAANQAECgQIBQAAAA==.Brightstar:BAAANQADCgUIBQAAAA==.Brionthicc:BAAANQAECgIIAgABNQAFFAEIAQABAAAAAA==.Brownington:BAAANQAECgYIBwAAAA==.Bruhilda:BAAANQAECgEIAQAAAA==.Brìonik:BAAANQAFFAEIAQAAAA==.',
Bu='Bubbleroundi:BAAANQAECgUICAAAAA==.Bubudder:BAAANQAECgQIBwAAAA==.Buffstuff:BAAANQAECgQIBQAAAA==.',
Ca='Caeviro:BAAANQAECgQIBQAAAA==.Canadaishere:BAAANQADCgEIAQAAAA==.Cantheartitz:BAAANQAECgMIBAAAAA==.Catdav:BAAANQADCgcIEAAAAA==.',
Ch='Charbol:BAAANQADCgMIAwAAAA==.Chelraani:BAAANQADCggIDgAAAA==.Chess:BAAANQADCggICgAAAA==.Chiichard:BAAANQADCgIIAgAAAA==.Chunkamonk:BAAANQADCgQIBAAAAA==.',
Ci='Cigar:BAAANQADCgUICQABNQAECgUICgABAAAAAA==.',
Cl='Clazzicola:BAAANQAECgcIDwAAAA==.',
Co='Cowdeer:BAAANQAECgIIAgAAAA==.',
Cp='Cptncrush:BAAANQAECgIIAgAAAA==.',
Cr='Creamsickle:BAAANQABCgIIBAAAAA==.',
Cu='Cupcakes:BAAANQADCgYIBgAAAA==.Cutethulu:BAAANQAECgQIBAAAAA==.',
Cy='Cyther:BAAANQAFFAEIAQAAAA==.',
Da='Dadbodftw:BAAANQADCggIEgAAAA==.Daddylight:BAAANQADCgcIEQAAAA==.Dakk:BAAANQADCggICAAAAA==.Darkdottie:BAAANQAECgIIAgAAAA==.Darkenstormy:BAAANQADCgcIEgAAAA==.Darkmage:BAAANQABCgYIBgAAAA==.Dayday:BAAANQADCggIEAAAAA==.',
De='Deadlight:BAAANQAECgYICQAAAA==.Deadtofall:BAAANQADCgYICgAAAA==.Deathshikzs:BAAANQAECgYIEQAAAA==.Decix:BAAANQAECgIIAgABNQAFFAEIAQABAAAAAA==.Deity:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Demonllxll:BAAANQAECgQIBQAAAA==.Desolation:BAAANQAECgQIBQAAAA==.Despia:BAAANQADCggIEgAAAA==.Devastacia:BAAANQADCggICAAAAA==.',
Di='Dicot:BAAANQADCggIEgAAAA==.Diety:BAAANQAECgMIAwAAAA==.Dimension:BAAANQAECgEIAQAAAA==.Disconnect:BAAANQABCgUIBwAAAA==.',
Dj='Djpallyd:BAAANQAECgYIBwAAAA==.',
Do='Doughy:BAAANQADCggICAAAAA==.',
Dr='Dragonu:BAAANQAECggIDgAAAA==.Draktyr:BAAANQAFFAEIAQAAAA==.Droody:BAAANQABCgIIAgAAAA==.',
El='Ellalais:BAAANQAECgIIAgAAAA==.Ellismom:BAAANQAECgQIBQAAAA==.',
En='End:BAAANQAECgIIAgAAAA==.',
Er='Ereithelda:BAAANQAECgcIEgAAAA==.Ericka:BAAANQADCgEIAQAAAA==.Erina:BAAANQABCgYICQAAAA==.Erowid:BAAANQADCggICwABNQAECggIDgABAAAAAA==.Errutu:BAAANQAECgQIBQAAAA==.',
Ev='Evox:BAAANQADCgcIEgAAAA==.',
Fa='Fann:BAAANQAECgIIAgAAAA==.Fauna:BAAANQADCggICAAAAA==.',
Fe='Feathiir:BAAANQADCgEIAQAAAA==.Fewz:BAAANQAECgcIEQAAAA==.',
Fl='Flakflap:BAAANQADCggICAABNQAECgcIEQABAAAAAA==.Flakov:BAAANQADCggIDgABNQAECgcIEQABAAAAAA==.Flaktop:BAAANQAECgcIEQAAAA==.Flatplate:BAAANQADCgUIBQAAAA==.Fler:BAAANQAECgEIAQAAAA==.',
Fo='Forbacon:BAAANQAECgMIAwAAAA==.Force:BAAANQAECgIIAgAAAA==.Fouris:BAAANQADCgcICgAAAA==.',
Fr='Fridgie:BAAANQAFFAEIAQAAAA==.Friggenmage:BAAANQAECgYICgAAAA==.Frostbitte:BAAANQADCgEIAQAAAA==.Frozenruby:BAAANQABCgYICwAAAA==.Frozenturtle:BAAANQADCgcIEQAAAA==.',
Ft='Ftwiamtank:BAAANQAECgEIAQAAAA==.',
Ga='Garcutt:BAAANQAECgcIEQAAAA==.',
Ge='Geddan:BAAANQADCgQIBgAAAA==.Genericpal:BAAANQAECgYICgAAAA==.',
Gi='Ginrai:BAAANQADCgUIBQAAAA==.',
Gl='Gladstone:BAAANQAECgIIAgAAAA==.',
Gn='Gnawbear:BAEANQAECgMIBQAAAA==.',
Go='Goatassassin:BAAANQADCgUIBQABNQAECgMIBAABAAAAAA==.Goatshifter:BAAANQAECgMIBAAAAA==.',
Gr='Grayeyes:BAAANQADCgMIAwAAAA==.Greenngoblin:BAAANQAECgEIAQAAAA==.Grämps:BAAANQADCgYIBgAAAA==.',
Gu='Guino:BAAANQADCgYICwAAAA==.',
Gw='Gwenelly:BAAANQADCgYICQAAAA==.',
Ha='Hamnqueso:BAAANQADCgYICgAAAA==.Hardeesdelux:BAAANQADCgUICQABNQADCgYIEgABAAAAAA==.Hazis:BAAANQAECgcIEQAAAA==.',
Hi='Hinala:BAAANQAECgUICQAAAA==.',
Ho='Holy:BAAANQADCggIFgABNQAECgcIEQABAAAAAA==.Holydad:BAAANQADCgcIBwAAAA==.Honeybutter:BAAANQAECgcIBQAAAA==.Hordebreaker:BAAANQABCgIIAgAAAA==.',
Hu='Huesitos:BAAANQAECgMIBQAAAA==.Huntzilla:BAAANQADCgYIBgAAAA==.Huukend:BAAANQAECgIIAwAAAA==.',
In='Innominot:BAAANQADCgUIBQAAAA==.',
Ja='Jadaveon:BAAANQADCggIFgAAAA==.Jalene:BAAANQADCgYIBwAAAA==.',
Je='Jettadari:BAAANQAECgYICgABNQAFFAEIAQABAAAAAA==.Jettadin:BAAANQAFFAEIAQAAAA==.',
Jw='Jwalker:BAAANQADCgQIBQAAAA==.',
['Jë']='Jëks:BAAANQAFFAEIAQAAAA==.',
Ka='Kakozaps:BAAANQAFFAEIAQAAAA==.Kallar:BAAANQADCggIFAABNQAECgIIAgABAAAAAA==.Kayeera:BAAANQADCgUICwAAAA==.Kaylrandi:BAAANQADCgIIBQAAAA==.Kayna:BAAANQADCgEIAQAAAA==.',
Ke='Kearza:BAAANQADCgYICgAAAA==.Keiyona:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Kennethv:BAAANQADCgcIEgAAAA==.Keny:BAAANQAECgUIBgAAAA==.Kero:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Kev:BAAANQAECgQIBAAAAA==.',
Kh='Khibanee:BAAANQADCgcIEQAAAA==.Khiell:BAAANQAECgcIDAAAAA==.Khrominius:BAAANQAECgIIAgAAAA==.',
Ki='Kinigit:BAAANQADCggIEAABNQAECgcIEQABAAAAAA==.Kirïtö:BAAANQADCgMIAwAAAA==.Kitaradin:BAAANQAECgQIBQAAAA==.',
Kn='Knghtmre:BAAANQAECgYIDQAAAA==.',
Ko='Konpalitaa:BAAANQADCgUIBQAAAA==.',
Ku='Kuranaa:BAAANQADCgQICgAAAA==.Kurulak:BAAANQAECgQIBQAAAA==.',
Ky='Kymru:BAAANQADCgYICQAAAA==.',
La='Lacerveza:BAAANQAECgEIAQAAAA==.',
Le='Leriope:BAAANQAECgQIBQAAAA==.',
Li='Lichfiend:BAAANQADCgYICgAAAA==.Lihpfu:BAAANQAECgQIBAABNQAECgYIDAABAAAAAA==.Lilem:BAAANQADCgIIAgAAAA==.',
Lj='Lj:BAAANQAECgQIBQAAAA==.',
Lu='Luxure:BAAANQAECgEIAQAAAA==.',
Ma='Maegan:BAAANQADCgcIEwAAAA==.Mager:BAAANQAECgEIAQAAAA==.Mageshyte:BAAANQAECgcIEAAAAA==.Magolock:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Magus:BAAANQADCggICAAAAA==.Maidrim:BAAANQAFFAEIAQAAAA==.Mamajumbo:BAAANQADCggIFgAAAA==.Mana:BAAANQAECgcIEQAAAA==.Marellias:BAAANQAECgYIBgABNQAECggIDwABAAAAAA==.Marikel:BAAANQADCgYICAAAAA==.Maruka:BAAANQAECgQIBAAAAA==.',
Me='Meletha:BAAANQADCggICAAAAA==.',
Mi='Michaelken:BAAANQAECgEIAQAAAA==.Midari:BAAANQADCgEIAQAAAA==.Mierin:BAAANQADCgUIBQAAAA==.Migrains:BAAANQAECgQIBQAAAA==.Milkmesloppy:BAAANQADCgYIBgABNQAECgcIEQABAAAAAA==.Miskaabin:BAAANQADCggIEwAAAA==.Missdemon:BAAANQADCggICAAAAA==.',
Mo='Mojogreens:BAAANQADCgUIBQAAAA==.Monsart:BAAANQABCgYIBwAAAA==.Moonie:BAAANQADCgYIBgAAAA==.Moralizdormi:BAAANQAECgQIBQAAAA==.',
Mp='Mpd:BAAANQAECgEIAQAAAA==.',
My='Mylendria:BAAANQABCgYIBwAAAA==.Mystique:BAAANQAECgEIAQAAAA==.',
['Mí']='Míerín:BAAANQAECgcIEQAAAA==.',
Na='Naama:BAAANQADCgEIAQAAAA==.Natzu:BAAANQAECgEIAQAAAA==.Naushan:BAAANQADCgIIAgAAAA==.Nazari:BAAANQAECgcIEQAAAA==.',
Ne='Necronu:BAAANQADCggICAABNQAECggIDgABAAAAAA==.',
No='Nogusta:BAAANQAFFAEIAQAAAA==.Notdecix:BAAANQAFFAEIAQAAAA==.',
Nu='Nuggets:BAAANQADCgYICwAAAA==.',
Ob='Obyss:BAAANQADCgQIBAAAAA==.',
On='Onlyshams:BAAANQAECgYIBwAAAA==.',
Oo='Oorggtejedor:BAAANQADCgUIBQAAAA==.',
Or='Orondo:BAAANQADCgYIEQAAAA==.',
Ou='Oumura:BAAANQADCggIDwAAAA==.',
Pa='Patharok:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.Pathator:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Patheros:BAAANQABCgUIBQABNQAECgQIBQABAAAAAA==.Paxmansigh:BAAANQADCgYIFAAAAA==.',
Ph='Phantöm:BAAANQAECgYICgAAAA==.',
Pl='Placcid:BAAANQAECgIIAwAAAA==.Planknstein:BAAANQADCgUICwAAAA==.Plantoor:BAAANQAECgUIBQAAAA==.',
Po='Pockett:BAAANQADCgQIBAAAAA==.Ponarp:BAAANQAECgIIAgAAAA==.Porkchop:BAAANQAECgQIBQAAAA==.',
Pr='Prismclaw:BAAANQAECgQIBQAAAA==.Processing:BAAANQAFFAEIAQAAAA==.',
Pu='Puddleheal:BAAANQADCgYIEgAAAA==.Puffdamagic:BAAANQAECgUICQAAAA==.',
Pw='Pwnstarz:BAAANQADCgYICwAAAA==.',
Py='Pyous:BAAANQADCgUICgAAAA==.',
Qp='Qplus:BAAANQAECgIIAgAAAA==.',
Qu='Quaenie:BAAANQAECgIIAgAAAA==.Quintin:BAAANQADCgUICAAAAA==.',
Ra='Ragetotem:BAAANQADCgIIAgAAAA==.Ragewarg:BAAANQAECgEIAQAAAA==.Raginsteel:BAAANQADCgYICwAAAA==.Ralvarr:BAAANQADCgQIBAAAAA==.Rayleigh:BAAANQADCgcIEgABNQADCgMIAwABAAAAAA==.',
Re='Redchord:BAAANQAECgEIAQAAAA==.Regidør:BAAANQAECgcIDAAAAA==.Relik:BAAANQAECgIIAgAAAA==.',
Ri='Rilliccine:BAAANQADCgYIBgAAAA==.Rilliguine:BAAANQADCgQIBAAAAA==.Rillinetti:BAAANQAECgEIAQAAAA==.Rillini:BAAANQAECgIIAgAAAA==.Rilliti:BAAANQADCgUIBQAAAA==.Risky:BAAANQABCgQIBAABNQADCgYIDAABAAAAAA==.',
Ro='Robotnik:BAAANQAECgIIAQAAAA==.Rogu:BAAANQADCgYICwAAAA==.Rondon:BAAANQADCggIEgAAAA==.Rookdh:BAAANQAFFAEIAQAAAA==.Rosey:BAAANQAECgIIAgAAAA==.Royale:BAAANQAECgIIAgAAAA==.',
Ru='Rudyeightbal:BAAANQADCgYIBgAAAA==.Rum:BAAANQADCggIDAAAAA==.Rustedbarrel:BAAANQAECgUIBwAAAA==.',
Sa='Saelyres:BAAANQADCgcIEQAAAA==.Sagesse:BAAANQADCggICAAAAA==.Samifleur:BAAANQAECgEIAQAAAA==.Sammy:BAAANQAECgIIAgAAAA==.Santaclaaws:BAAANQAECggIEwAAAA==.Santapal:BAAANQAECgUIDgABNQAECggIEwABAAAAAA==.Saphotic:BAAANQAECgcICwABNQAFFAEIAQABAAAAAA==.Sayvil:BAAANQAECgIIAgAAAQ==.',
Se='Semmers:BAAANQAECgIIAgAAAA==.Sensational:BAAANQAECgIIAgAAAA==.Septiria:BAAANQADCgYIBgAAAA==.Sergio:BAAANQADCgQIBAAAAA==.Seyren:BAAANQADCgQIBAAAAA==.',
Sh='Shalash:BAAANQADCgYIBgABNQAECggIDQABAAAAAA==.Shamadeano:BAAANQADCgcIDwAAAA==.Shamanshikz:BAAANQAECgEIAQAAAA==.Shamiska:BAAANQADCgcICwAAAA==.Shampooh:BAAANQADCgYIDAAAAA==.Shamrockk:BAAANQADCggICAAAAA==.Shaokhan:BAAANQAECgUIBQAAAA==.Sharpcukuee:BAAANQADCggIEQAAAA==.Shian:BAAANQADCggIDAAAAA==.Shieldee:BAAANQAECgMIAwAAAA==.Shikzzs:BAAANQAECgQICAAAAA==.Shockeei:BAAANQAECggIDgAAAA==.Shortdon:BAAANQADCgEIAQAAAA==.Shortebus:BAAANQADCgYIBgAAAA==.',
Si='Sighh:BAAANQADCgEIAQAAAA==.Sijth:BAAANQAECgUIDQAAAA==.Silvereyes:BAAANQABCgUIBAAAAA==.Silverwar:BAAANQAECgIIAgAAAA==.Simmune:BAEANQAFFAEIAQAAAA==.Sixior:BAAANQAECgIIAgAAAA==.Sixpath:BAAANQADCgQIAgAAAA==.Sixs:BAAANQADCggICAAAAA==.',
Sk='Skepti:BAAANQAECgIIAgAAAA==.Skreep:BAAANQADCgMIAwAAAA==.',
Sl='Slybiscuit:BAAANQAECgEIAQAAAA==.',
Sm='Smeeta:BAAANQAECgUIBwAAAA==.',
Sn='Sneakerbaby:BAAANQABCgQIBgAAAA==.',
So='Soram:BAAANQADCgYIBgAAAA==.Sourdevil:BAAANQABCgIIBAAAAA==.Soùl:BAAANQADCggIFgAAAA==.',
Sp='Spike:BAAANQADCgcICgAAAA==.',
St='Starlara:BAAANQABCgIIAgAAAA==.Stazz:BAAANQAECgQIBQAAAA==.Steelerayne:BAAANQADCgcIEgAAAA==.Stonecrab:BAAANQAECgMIBAAAAA==.Stormcontrol:BAAANQAECgMIAwAAAA==.Stormii:BAAANQADCgUIBQAAAA==.Stormtotem:BAAANQADCgUIBQAAAA==.Strangerdk:BAAANQAECgEIAQAAAA==.Styless:BAAANQABCgYIBwAAAA==.',
Sw='Swagboyxx:BAAANQADCgQIBAAAAA==.Swishersweet:BAAANQAECgUICQAAAA==.Swordfish:BAAANQADCgUICAAAAA==.',
Sy='Sybrooke:BAAANQADCgUICwAAAA==.Syrinne:BAAANQADCgEIAQAAAA==.',
Ta='Tabrieus:BAAANQAECgQIBQAAAA==.Taegia:BAAANQADCgUIBQABNQAECgcIEgABAAAAAA==.Talanth:BAAANQAECgEIAQAAAA==.Talbott:BAAANQADCgEIAQAAAA==.Tarrisx:BAAANQADCgEIAQABNQAECgUIBwABAAAAAA==.Tayon:BAAANQADCgcICAAAAA==.Tayvin:BAAANQADCgEIAQAAAA==.',
Te='Termana:BAAANQAFFAEIAQAAAA==.',
Th='Thatsmypurse:BAAANQADCggICAAAAA==.Theodoró:BAAANQAECgIIAQAAAA==.Thug:BAAANQADCgcIFQAAAA==.',
Ti='Tiferet:BAAANQAECgIIAgAAAA==.Tigiw:BAAANQADCgYICgAAAA==.Tinysunshine:BAAANQAECgEIAQAAAA==.Tinyt:BAAANQADCgMIAwAAAA==.Titonatty:BAAANQABCgIIBAAAAA==.',
To='Tolenkar:BAAANQAECgIIAgAAAA==.Tomato:BAAANQAFFAEIAQAAAA==.Torfelori:BAAANQADCggICAAAAA==.Torvalar:BAAANQAECgQIBQAAAA==.Tove:BAAANQAECgEIAQAAAA==.',
Tr='Trûth:BAAANQAECggIBwAAAA==.',
Tu='Turdyl:BAAANQAECgYICAAAAA==.',
Ty='Tyfelsion:BAAANQAECgEIAQAAAA==.Tyrelline:BAAANQAECgIIAgAAAA==.',
['Tá']='Tárris:BAAANQADCgcIBwABNQAECgUIBwABAAAAAA==.',
['Tô']='Tôx:BAAANQAECgYICQAAAA==.',
Un='Unheardjp:BAAANQADCgMIBQAAAA==.',
Ur='Ursus:BAAANQAECgIIAgAAAA==.',
Va='Vaerix:BAAANQAECgEIAQAAAA==.Valydrin:BAAANQAECgQIBQAAAA==.',
Ve='Vexadrine:BAAANQAFFAEIAQAAAA==.',
Vy='Vysis:BAAANQAECggIEQAAAA==.',
We='Weebdestroya:BAAANQADCgIIAgAAAA==.',
Wh='Whisperfål:BAAANQADCgIIAgAAAA==.',
Wi='Wickèr:BAAANQAECgIIBAAAAA==.Wieldblade:BAAANQAECgQIBgAAAA==.',
Wu='Wunderbar:BAAANQADCggIEgAAAA==.',
Wy='Wyldfire:BAAANQAECgcIEQAAAA==.',
Xa='Xanith:BAAANQADCgYIBgAAAA==.',
Yi='Yia:BAAANQAECgIIAgAAAA==.Yilnara:BAAANQADCggIDwAAAA==.',
Ys='Ysa:BAAANQAECgUIBwAAAA==.',
Za='Zarich:BAAANQAECgMIBAAAAA==.',
Ze='Zekkun:BAAANQADCggICAAAAA==.',
Zo='Zoga:BAEANQADCgUIBQABNQAECgIIAgABAAAAAA==.Zogah:BAEANQADCgQIBAABNQAECgIIAgABAAAAAA==.Zoganian:BAEANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Zu='Zullthornp:BAAANQADCgQIBAAAAA==.',
['Æb']='Æbony:BAAANQABCgIIAgAAAA==.',
['Év']='Évélýn:BAAANQADCgUIBQAAAA==.',
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
