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
local provider = {region='US',realm='BurningLegion',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aalfie:BAAANQADCgYICwABNQAECgQIBAABAAAAAA==.',
Ad='Aderren:BAAANQAECgIIAgAAAA==.',
Ae='Aeir:BAAANQAECgQIBAAAAA==.Aether:BAAANQADCgcIBwAAAA==.Aevella:BAAANQAECggICgAAAA==.',
Ag='Agarn:BAAANQADCggIDgABNQADCggIDgABAAAAAA==.Aghanaar:BAAANQADCgYIBgAAAA==.Agidan:BAAANQAECgMIBAAAAA==.Aguthus:BAAANQADCgYIBgAAAA==.',
Ak='Akaibara:BAAANQADCgUIBgAAAA==.',
Al='Alizar:BAAANQAECgYICgAAAA==.Alleriá:BAAANQAECgMIAwAAAA==.Almaholzhert:BAAANQADCggIDgAAAA==.Alor:BAAANQAECgQIBAAAAA==.Alundareth:BAAANQADCggICAAAAA==.Alysanne:BAAANQADCgIIAgAAAA==.',
Am='Amelie:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.',
An='Angryart:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Anniellusion:BAAANQAECgIIAgAAAA==.Anthreax:BAAANQADCgUIBQAAAA==.',
Ap='Applepie:BAAANQADCgQIBAAAAA==.',
Ar='Armous:BAAANQADCgYICwAAAA==.Arms:BAAANQAECgYICgAAAA==.Arrano:BAAANQAECgEIAQAAAA==.',
As='Astrada:BAAANQADCgYICAAAAA==.',
Ay='Ayangat:BAAANQAECgcIDQAAAA==.Aycekween:BAAANQADCggICwAAAA==.',
Az='Azusa:BAAANQAECgQIBQAAAA==.Azzulaa:BAAANQADCgYICwAAAA==.',
Ba='Baconarrow:BAAANQADCggICAAAAA==.Baggedmilk:BAAANQADCgUICAAAAA==.',
Be='Belgarrion:BAAANQADCgYIAQAAAA==.Belladonna:BAAANQAECgYICwABNQAFFAMIAwABAAAAAA==.Bezirk:BAAANQAECgUIBgAAAA==.',
Bh='Bhaal:BAAANQAECgQIBAAAAA==.',
Bi='Bigboyfriend:BAAANQADCggICAAAAA==.Bighunters:BAAANQAECgEIAQAAAA==.Bigitaly:BAAANQADCgcICAAAAA==.',
Bj='Bjardle:BAAANQAECgMIAwAAAA==.',
Bl='Blast:BAAANQAECgIIAgAAAA==.Bleedlife:BAAANQAECgIIAgAAAA==.Blindguard:BAAANQAECgcIDAAAAA==.Blinksoncd:BAAANQAECgYIBwAAAA==.Bloodrainer:BAAANQAECgQIBAAAAA==.Blutzappel:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.',
Bo='Boot:BAAANQAECgIIAgAAAA==.Bootkin:BAAANQAECgMIBAAAAA==.Borgorn:BAAANQAECgMIAwAAAA==.Bownes:BAAANQAECgMIAwAAAA==.',
Br='Brewbott:BAAANQAECgUIBgAAAA==.Brickp:BAAANQAECgMIBAAAAA==.Brimscythe:BAAANQADCgYIBgAAAA==.',
Bu='Bulinlok:BAAANQADCgMIAwAAAA==.Buluc:BAAANQAECgMIAwAAAA==.Buroode:BAAANQAECgEIAQAAAA==.Busselton:BAAANQAECgcIDQAAAA==.',
Bv='Bvngly:BAAANQAECgcICgAAAA==.',
Ca='Callister:BAAANQADCggIEwAAAA==.Campanda:BAAANQADCgYIBgAAAA==.Carble:BAAANQADCggICAAAAA==.Cashgrabber:BAAANQADCgIIAgAAAA==.',
Ch='Champthyr:BAAANQAECgYICQAAAA==.',
Cl='Claudia:BAAANQADCgIIAgAAAA==.Clouds:BAAANQADCgYIBgAAAA==.',
Co='Coachkreeton:BAAANQAECgQIBwAAAA==.Cologa:BAAANQADCggIDgAAAA==.Confess:BAAANQAECgIIAgAAAA==.Coola:BAAANQADCggIDQAAAA==.Coollá:BAAANQADCgUIBQABNQADCggIDQABAAAAAA==.Coot:BAAANQAECgEIAgAAAA==.Copmage:BAAANQAECgQIBQAAAA==.Cosines:BAAANQAECgQIBAAAAA==.Cowsrule:BAAANQAECgMIAwAAAA==.',
Cr='Crestfallen:BAAANQADCgEIAgAAAA==.Cryokaren:BAAANQADCgQIBQAAAA==.',
Da='Daarfsad:BAAANQADCgYIBgAAAA==.Daeio:BAAANQADCgMIAwAAAA==.Darkaunnas:BAAANQAECgEIAQAAAA==.Darth:BAAANQAECgEIAQAAAA==.',
De='Deified:BAAANQADCgIIAgAAAA==.Deldor:BAAANQADCgYICQAAAA==.Deli:BAAANQADCggIDQAAAA==.Demonetizer:BAAANQAECgcIDAAAAA==.Demonicart:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Demyxx:BAAANQAECgEIAgAAAA==.Denniecrane:BAEANQAECgYICQAAAA==.',
Dh='Dhjochann:BAAANQAECgIIAgAAAA==.',
Di='Dirtywork:BAAANQAECgEIAQAAAA==.',
Do='Dominic:BAAANQADCgMIAwAAAA==.Donttrustme:BAAANQADCgYICwAAAA==.',
Dr='Drae:BAAANQADCgYICgAAAA==.Dragunass:BAAANQADCgQIAwAAAA==.Drama:BAAANQABCgMIAgAAAA==.Drayu:BAAANQADCgYIDAAAAA==.',
Du='Duggin:BAAANQAECgQIBAAAAA==.',
Ei='Eilesa:BAAANQADCgcIDQAAAA==.',
El='Eldarin:BAAANQADCggIDgAAAA==.Eliardis:BAAANQADCgcIDgAAAA==.',
En='Enigmazz:BAAANQADCggIDwAAAA==.',
Ep='Epictitus:BAAANQADCgQIBAAAAA==.',
Es='Escaflowne:BAAANQAECgcIDQAAAA==.',
Et='Ethaee:BAAANQADCgUIBgAAAA==.',
Eu='Eurydices:BAAANQADCgYIBgAAAA==.',
Ev='Evangelión:BAAANQADCgUICgAAAA==.',
Ex='Exit:BAAANQADCggIDgAAAA==.',
Ey='Eyks:BAAANQADCggICgAAAA==.',
Fa='Faelithndrel:BAAANQAECgQIBQAAAA==.Farmette:BAAANQADCgYIBgAAAA==.',
Fe='Felbeard:BAAANQAFFAMIAwAAAA==.Feleâ:BAAANQADCgUIBwAAAA==.Ferreday:BAAANQADCggIDgAAAA==.',
Fi='Fingoflin:BAAANQADCgYIBgAAAA==.Firemystic:BAAANQADCgQIBAAAAA==.',
Fl='Fleakertwo:BAAANQAECgcIDQAAAA==.Floopzii:BAAANQAECgMIAwAAAA==.Flói:BAAANQADCgYICAAAAA==.',
Fr='Friedrib:BAAANQAECgcIDAAAAA==.',
Fu='Fulldipey:BAAANQAECgEIAQAAAA==.Furrythot:BAAANQAECgcIDQAAAA==.',
Ga='Galise:BAAANQADCgYIBgAAAA==.Galynnia:BAAANQADCgYIBgAAAA==.Gangstafrost:BAAANQADCgMIBQAAAA==.',
Gd='Gduff:BAAANQAECgEIAQAAAA==.',
Ge='Genaveive:BAAANQAECgYICQAAAA==.',
Gg='Ggodetan:BAAANQADCgYIBgAAAA==.',
Gi='Gigglespit:BAAANQADCgcICQAAAA==.Gildeath:BAAANQAECgYIBgAAAA==.Gimmix:BAAANQAECgQIBQAAAA==.',
Gl='Glindora:BAAANQADCgYICAAAAA==.',
Go='Gobbylynn:BAAANQAECgYICwABNQAECggICgABAAAAAA==.Gooptoob:BAAANQADCgcIBwAAAA==.',
Gu='Guaplord:BAAANQADCgMIAwAAAA==.',
Ha='Hagran:BAAANQADCgMIAwAAAA==.Haint:BAAANQAECgMIAwAAAA==.Halzak:BAAANQADCgcICAAAAA==.Hawdazz:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.',
He='Hegotthedrip:BAAANQAECggIDAAAAA==.Helios:BAAANQAECgQIBAAAAA==.Hellaquin:BAAANQAECgcIDQAAAA==.Hellomotojr:BAAANQAECgEIAQAAAA==.',
Hi='Hijackx:BAAANQAECgQIBQAAAQ==.Hinotama:BAAANQADCgYIBgAAAA==.',
Ho='Holycoward:BAAANQADCgYIDAAAAA==.Holynova:BAAANQADCggIDgAAAA==.Holysuave:BAAANQADCggICgAAAA==.Horu:BAAANQADCgcIDAAAAA==.',
Hy='Hyhu:BAAANQAECgQIBQAAAA==.Hymlok:BAAANQAECgMIAwAAAA==.Hyperion:BAAANQAECgUIBQAAAA==.Hyuga:BAAANQADCgcIDQAAAA==.',
Ic='Iccarium:BAAANQAECgMIAwAAAA==.Icexjh:BAAANQADCggIDgAAAA==.',
Ig='Ignatowski:BAAANQADCgUIBQAAAA==.Igorongon:BAAANQAECgQIBQAAAA==.',
Ik='Ikhawe:BAAANQADCgIIAgAAAA==.',
In='Inebrious:BAAANQADCgYICwAAAA==.',
Io='Ionna:BAAANQADCgUIBQABNQADCggIDgABAAAAAA==.',
Ir='Ironmann:BAAANQAECgQIBAAAAA==.',
It='Itsmäam:BAAANQAECgEIAQAAAA==.',
Ja='Jabamental:BAAANQAECgYIDAAAAA==.Jaded:BAAANQADCgYICgAAAA==.Jadefonda:BAAANQADCgcICwAAAA==.Jamx:BAAANQAECgQIBAABNQAECgcIDgABAAAAAA==.Jamy:BAAANQAECgcIDgAAAA==.Jandria:BAAANQAECgIIAgAAAA==.Janos:BAAANQAECgQIBQAAAA==.Jashin:BAAANQAECgQIBQAAAA==.Jawbreaker:BAAANQADCgQIBQAAAA==.Jaycifer:BAAANQAECgYIDAAAAA==.',
Je='Jerm:BAAANQADCgQIBAAAAA==.Jerzyp:BAAANQADCgEIAQAAAA==.Jessia:BAAANQAECgMIAwAAAA==.',
Jo='Joobi:BAAANQAECgEIAQAAAA==.Jorrethoi:BAAANQADCgYICwAAAA==.',
Ju='Jurble:BAAANQAECgQIBQAAAA==.Juurou:BAAANQADCgYICQAAAA==.',
['Jä']='Jäydedfäith:BAAANQADCgUIBgAAAA==.',
Ka='Kabbu:BAAANQADCggIDgAAAA==.Kaimed:BAAANQAECgYIBwAAAA==.Kamton:BAAANQADCgUIBQAAAA==.Kardrig:BAAANQADCgcIDAAAAA==.Katwoman:BAAANQAECgQIBAAAAA==.Kaylana:BAAANQADCgUICAAAAA==.',
Kd='Kdzee:BAAANQADCggIDgAAAA==.',
Kh='Khalezzi:BAAANQAECgQIBAAAAA==.Khonos:BAAANQAECgMIAQAAAA==.',
Ki='Killercold:BAAANQADCgUIBQAAAA==.Kimoora:BAAANQADCgQIBQAAAA==.Kirarawr:BAAANQABCgIIAgAAAA==.Kisstrosity:BAAANQAECggIDwAAAA==.',
Kl='Kloosterhuis:BAAANQAECgMIAwAAAA==.',
Ko='Kodoseeker:BAAANQAECgQIBAAAAA==.Kovos:BAAANQADCgEIAQAAAA==.',
Kr='Krean:BAAANQADCgcICwAAAA==.Krisali:BAAANQADCgIIAgAAAA==.',
Ku='Kunardh:BAAANQADCgUICQABNQAECgQIBQABAAAAAA==.Kunarr:BAAANQAECgQIBQAAAA==.',
Ky='Kylerichards:BAAANQADCgYIBgAAAA==.Kyohunt:BAAANQAECgQIBQAAAA==.Kyoshock:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.',
La='Ladonda:BAAANQADCgUIBQAAAA==.Lanius:BAAANQABCgIIAgAAAA==.Lanyx:BAAANQADCgUIBgAAAA==.Lareina:BAAANQAECgcIDQAAAA==.Larinara:BAAANQADCgEIAQAAAA==.',
Le='Lemonhope:BAAANQAECgIIAwAAAA==.',
Li='Linchknight:BAAANQADCgcIDQAAAA==.Livola:BAAANQAECgIIAgAAAA==.',
Lo='Locknik:BAAANQADCgQICQAAAA==.Lokkahn:BAAANQADCgcIDQAAAA==.',
Lu='Lunarsol:BAAANQAECgQIBAAAAA==.',
Ly='Lyanna:BAAANQADCgcICQABNQAECgQIBQABAAAAAA==.',
['Lä']='Lätêx:BAAANQAECgcICwAAAA==.',
Ma='Magicmeatxxl:BAAANQAECgUIBQABNQAECgUIBQABAAAAAA==.Magusgobrr:BAAANQAECgQIBQAAAA==.Mahawker:BAAANQADCgIIAgAAAA==.Mahfaty:BAAANQADCgYIBgAAAA==.Malüs:BAAANQADCgUIBQAAAA==.Marideous:BAAANQADCgUIBQAAAA==.Mark:BAAANQAECgEIAQABNQAECgUICAABAAAAAA==.Marth:BAAANQADCggIDgAAAA==.Mashem:BAAANQAECgUICAAAAA==.Mathias:BAAANQADCgUIBQAAAA==.Mattpriest:BAAANQAECgcIDQAAAA==.Maxverclappn:BAAANQADCgcIBwAAAA==.Maxvertrappn:BAAANQAECgEIAQAAAA==.',
Mc='Mcsloppy:BAAANQADCgYIBgAAAA==.',
Me='Meshkuhrib:BAAANQADCgUIBQABNQAECgcIDAABAAAAAA==.Methir:BAAANQADCgUICQAAAA==.',
Mi='Mightythor:BAAANQADCgYIBgAAAA==.Milkedmoose:BAAANQAECgMIAwAAAA==.Milkers:BAAANQAECgcICgAAAA==.Minimoose:BAAANQADCggIDgAAAA==.Misclick:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.',
Mo='Moona:BAAANQAECgEIAQAAAA==.Moonberry:BAAANQAECgYICAAAAA==.Moonlock:BAAANQADCgUIBgAAAA==.Motomotoo:BAAANQADCgYIBgAAAA==.',
Mu='Muffinfeliz:BAAANQADCgQIBAABNQADCgUIBgABAAAAAA==.',
My='Mythundreran:BAAANQADCgcICgAAAA==.',
Na='Namdari:BAAANQADCggIDgAAAA==.Nazzan:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.',
Ni='Nightmàre:BAAANQAECgEIAQAAAA==.Nightstride:BAAANQADCgMIAQAAAA==.Nirra:BAAANQADCgcICwAAAA==.',
No='Novapal:BAAANQAECgIIAgAAAA==.Novura:BAAANQADCgYIBgAAAA==.',
Oc='Ochnauq:BAAANQAECgQIBQABNQAECgYIDAABAAAAAA==.',
Om='Omarid:BAAANQADCgIIBAAAAA==.Omfgpie:BAAANQAECgMIAwAAAA==.',
Oo='Ooiskan:BAAANQADCgIIAgAAAA==.',
Or='Orcall:BAAANQAECgUIBgAAAA==.',
Ov='Overcharged:BAAANQADCgQIBAAAAA==.',
Ow='Owencaddell:BAAANQADCgUIBQAAAA==.',
Pa='Pada:BAAANQAECgEIAQAAAA==.Pakku:BAAANQAECgcIDQAAAA==.Paladaine:BAAANQADCgUIBQAAAA==.Pallix:BAAANQAECgQIBQABNQAECgYIDAABAAAAAA==.Palpacino:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Palytivecare:BAAANQADCgIIAwAAAA==.Papajaja:BAAANQAECgIIAgAAAA==.Paramôre:BAAANQAECgMIAwABNQAECgcICwABAAAAAA==.',
Pe='Peace:BAAANQAECgUICAAAAA==.Pegmianis:BAAANQADCgcIDQAAAA==.',
Ph='Phigon:BAAANQADCggIDgAAAA==.',
Pi='Pixelbaddy:BAAANQADCgYIBgAAAA==.',
Pl='Plumbus:BAAANQADCgUIBQAAAA==.',
Po='Polygrip:BAAANQADCgYICwAAAA==.Popechaz:BAAANQADCgYIDAAAAA==.',
Ps='Psychonaut:BAAANQAECgUIBQAAAA==.',
Pu='Pure:BAAANQAECgYIBwAAAA==.',
Py='Pyrine:BAAANQADCgYIBgAAAA==.',
Qu='Quancho:BAAANQAECgYIDAAAAA==.',
Qw='Qwade:BAAANQAECgEIAQAAAA==.',
Ra='Ragran:BAAANQADCgUIBQAAAA==.Rakaman:BAAANQADCggICwAAAA==.Ramza:BAAANQAECggIDwAAAA==.Ranbou:BAAANQAECgYIDAAAAA==.Randor:BAAANQABCgQIBgAAAA==.Ratatasquer:BAAANQADCggIDgAAAA==.Rattleballs:BAAANQADCggIEAABNQAECgIIAwABAAAAAA==.',
Re='Reegss:BAAANQADCgEIAQAAAA==.Regsia:BAAANQADCgYICgAAAA==.Repens:BAAANQADCggIDgAAAA==.Retbeanznrce:BAAANQADCgIIAgAAAA==.Retful:BAAANQADCgUIBQABNQAECgcIDAABAAAAAA==.Revo:BAAANQADCgYIBgABNQAECgcICQABAAAAAA==.',
Rh='Rhaid:BAAANQAECgMIAwAAAA==.Rhordrick:BAAANQAECgIIAgAAAA==.',
Ri='Rizzgrizzly:BAAANQADCgIIAgAAAA==.Rizzurrect:BAAANQADCgIIAgAAAA==.',
Rn='Rng:BAAANQADCgIIAgAAAA==.',
Ro='Roquefort:BAAANQADCgUIBgAAAA==.Roscoedshamn:BAAANQADCgYICQAAAA==.Rowdi:BAAANQADCgYIBgAAAA==.',
Ru='Rukarm:BAAANQADCgUIDgAAAA==.Runawaynow:BAAANQAFFAIIAgAAAA==.Runelife:BAAANQADCgYIBwABNQAECgIIAgABAAAAAA==.',
Sa='Saelaissamlt:BAAANQADCgQIBAAAAA==.Samdeathfoot:BAAANQADCgYICwAAAA==.Sartok:BAAANQADCgUICgAAAA==.',
Se='Seyuri:BAAANQAECgQIBQAAAA==.Seán:BAAANQADCggIDgAAAA==.',
Sh='Shadowar:BAAANQADCgcIDQAAAA==.Shadowbell:BAAANQAECgMIAwAAAA==.Shadowgale:BAAANQADCgcIDQAAAA==.Shantari:BAAANQADCgEIAQAAAA==.Shayrpd:BAAANQADCggICAAAAA==.Shøckybalboa:BAAANQAECgMIBAAAAA==.',
Si='Sinnshifts:BAAANQADCgYIDAAAAA==.',
Sk='Skhorn:BAAANQAECgMIAwAAAA==.Skuûub:BAAANQADCgUIBQAAAA==.',
Sl='Slãyer:BAAANQADCgYICwAAAA==.',
Sm='Smokedrib:BAAANQADCgMIAwABNQAECgcIDAABAAAAAA==.',
So='Sometymz:BAAANQAECgIIAwAAAA==.',
Sp='Spareathot:BAAANQAECgYICAAAAA==.Spirulina:BAAANQADCgIIAgAAAA==.Splashsplash:BAAANQADCgQIBQAAAA==.',
St='Staar:BAAANQAECgEIAQAAAA==.Starflames:BAAANQADCgQIBAAAAA==.Stellarèé:BAAANQAECgcIDQAAAA==.Strongdroid:BAAANQADCgMIAwAAAA==.Strángè:BAAANQAECgEIAQAAAA==.',
Su='Substrate:BAAANQADCgYIBgAAAA==.Sugarteets:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Suramo:BAAANQAECgQIBAAAAA==.',
Sv='Svaval:BAAANQAECgUIBwAAAA==.',
Sy='Syles:BAAANQADCgUIBgABNQADCggIDQABAAAAAA==.Syphon:BAAANQAECgQIBAAAAA==.',
Ta='Tamedurmom:BAAANQAECgIIAgAAAA==.Tarekk:BAAANQAECgIIAgAAAA==.Tarewreck:BAAANQADCgUIBQAAAA==.Tariqpapi:BAAANQAECgQIBQAAAA==.',
Te='Tehcountess:BAAANQAECgQIBQAAAA==.',
Th='Tharos:BAAANQADCgcIDQAAAA==.Thebeerwiz:BAAANQADCgQIBAAAAA==.Thecarebear:BAAANQAECgQIBAAAAA==.Thelianne:BAAANQADCgYICAAAAA==.Thelmina:BAAANQADCgQICAAAAA==.Thermidor:BAAANQADCggIDgAAAA==.Thorps:BAAANQAECgEIAgAAAA==.Thurstee:BAAANQAECgMIBAAAAA==.',
Ti='Tibian:BAAANQAECgQIBQAAAA==.Tigerpalm:BAAANQAECgEIAQAAAA==.Tilexer:BAAANQADCgMIAwAAAA==.Tinypreest:BAAANQADCgYIBgAAAA==.',
To='Totemlyfoxy:BAAANQADCgMIAwAAAA==.',
Tr='Treesdk:BAAANQAECgQIBQAAAA==.Trugs:BAAANQAECgEIAQAAAA==.',
Tu='Tuntunvergun:BAAANQAECgYICAAAAA==.',
Tw='Twelvetacos:BAAANQAECgUICAAAAA==.',
Ty='Tyralde:BAAANQAECgQIBgAAAA==.',
Ud='Udenlo:BAAANQADCgYIDAAAAA==.',
Um='Umbraheart:BAAANQADCgYIEAAAAA==.',
Un='Unsub:BAAANQADCgEIAQABNQAECgcICgABAAAAAA==.',
Us='Usui:BAAANQADCgEIAQAAAA==.',
Va='Valei:BAAANQADCggIDgAAAA==.Valvadime:BAAANQAECgEIAQAAAA==.',
Ve='Vecidus:BAAANQADCgYIBgAAAA==.Velassi:BAAANQAECgQIBAAAAA==.Velouriuum:BAAANQADCgQIBAAAAA==.Vetrandus:BAAANQADCgYIBgAAAA==.',
Vh='Vhioth:BAAANQADCgQIBgAAAA==.',
Vi='Vielli:BAAANQADCggIDgAAAA==.',
Vo='Volorren:BAAANQADCgcIDQAAAA==.Volzu:BAAANQAECgQIBAAAAA==.',
Wa='Walon:BAAANQADCgMIAwAAAA==.Wazerk:BAAANQADCgcIBwAAAA==.',
We='Weirdchampx:BAAANQAECgEIAQAAAA==.',
Wh='Whely:BAEANQAECgYIDAAAAA==.Whitegrlswag:BAAANQADCgQIAwAAAA==.',
Wi='Wilcoxx:BAAANQAECgYICwAAAA==.Wilcozz:BAAANQADCgQIBAABNQAECgYICwABAAAAAA==.Wipeout:BAAANQADCgYIDQAAAA==.Wirecutter:BAAANQADCgQIBAAAAA==.Wixjones:BAAANQADCgUIBQABNQAECgcIDgABAAAAAA==.Wizurd:BAAANQAECgQIBAAAAA==.',
Wo='Wolfcult:BAAANQAECgQIBAAAAA==.Wompstomper:BAAANQADCgEIAQAAAA==.',
Wr='Wrapwrap:BAAANQAECgMIAwAAAA==.Wratheon:BAAANQADCgEIAQAAAA==.',
['Wî']='Wîxx:BAAANQAECgUICAAAAA==.Wîxÿ:BAAANQAECgQIBQAAAA==.',
Yu='Yuseolha:BAAANQADCgcIBwAAAA==.',
Za='Zac:BAAANQADCggIDAABNQADCggIDwABAAAAAA==.Zacheeus:BAAANQAECgYICwAAAA==.Zaco:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.Zagran:BAAANQADCgIIAgAAAA==.Zak:BAAANQADCggIDwAAAA==.Zantidious:BAAANQADCgUIBwAAAA==.Zardragon:BAAANQAECgYIDAAAAA==.',
Ze='Zelenä:BAAANQAECgQIBAAAAA==.Zelethor:BAAANQAECgYIDAAAAA==.Zelithor:BAAANQAECgQIBQAAAA==.',
['Àr']='Àrcaneheart:BAAANQADCgUIBQAAAA==.',
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
