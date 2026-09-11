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

local lookup = {'Unknown-Unknown','Warrior-Arms','Mage-Arcane','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination',}
local provider = {region='US',realm='Medivh',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abashai:BAAANQAECgMIBAAAAA==.',
Ae='Aellyria:BAAANQADCgEIAQAAAA==.Aerrikon:BAAANQAECgEIAQABNQAECgIIBQABAAAAAA==.',
Ak='Akaili:BAAANQAECgIIAgAAAA==.',
Al='Alexiya:BAAANQAECgEIAgAAAA==.Allacari:BAAANQAECgIIAgAAAA==.Alodir:BAAANQADCgYICgABNQAECgIIAgABAAAAAA==.Alstadin:BAAANQADCgIIAgAAAA==.Alucardd:BAAANQADCgcIDQAAAA==.',
Am='Amanda:BAAANQAECgQIBAAAAA==.Amonamarth:BAAANQADCgcIBwAAAA==.',
An='Anabelleigh:BAAANQABCgUICAAAAA==.Andrise:BAAANQAECgEIAwAAAA==.Annathesia:BAAANQADCgEIAQAAAA==.Antibear:BAAANQAECgEIAQAAAA==.',
Ap='Apol:BAAANQAECgIIAgAAAA==.',
Ar='Arachne:BAAANQAECgQIBQAAAA==.Arakar:BAAANQAECgQIBgAAAA==.Aralynne:BAAANQAECgEIAQAAAA==.Arch:BAAANQADCgcIEQAAAA==.Ardori:BAAANQADCggIFwAAAA==.Arlïnn:BAAANQAECgQIBgABNQAECgYICgABAAAAAA==.Armorya:BAAANQAECgcIDQAAAA==.Armyofone:BAAANQADCggIEgAAAA==.Artaius:BAAANQAECgUIBQAAAA==.',
As='Ashaw:BAAANQADCgYIBgAAAA==.Astariel:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Astarog:BAAANQAECgEIAQAAAA==.',
At='Atafloosy:BAEANQAECgEIAQAAAA==.Athelf:BAAANQAECgcIDgAAAA==.',
Au='Aubriell:BAAANQADCgcIDQAAAA==.',
Ay='Ayrnerdam:BAAANQADCgYIEAAAAA==.',
Ba='Babelfish:BAAANQADCggIFgAAAA==.Bagleflinger:BAAANQAECgQIBgAAAA==.Baldr:BAAANQAECgQIBAAAAA==.Batarang:BAAANQAECgQIBQAAAA==.',
Be='Bealzulbub:BAAANQABCgMIAwAAAA==.Bearbarian:BAAANQAECgQIBQAAAA==.Beastkael:BAAANQADCggIDgAAAA==.Beg:BAAANQAECgYIBgAAAA==.Belfalas:BAAANQABCgIIAgAAAA==.Berghain:BAAANQADCgQIBQAAAA==.Berick:BAAANQAECgEIAgAAAA==.Betzalel:BAAANQAECgEIAgAAAA==.Beytryx:BAAANQADCgYIBgAAAA==.',
Bl='Bladeoftruth:BAAANQAECgYICgAAAA==.Blitzwing:BAAANQADCgcICQAAAA==.Bloodyaggro:BAAANQADCgcIDQAAAA==.',
Bo='Bonnabelle:BAAANQAECgUICgAAAA==.Bos:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.',
Br='Brewnelle:BAAANQADCggIDgABNQAECgYICgABAAAAAA==.Bruid:BAAANQAECgYICgAAAA==.Bruneigin:BAAANQADCgYIEAAAAA==.',
Ca='Calzone:BAAANQADCgYIBgAAAA==.Cambria:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Cardian:BAAANQADCgcIDQAAAA==.Caridin:BAAANQADCgYIEgAAAA==.Carmey:BAAANQAECgIIAgAAAA==.Carrin:BAAANQAECgYIEAAAAA==.Catalyia:BAAANQAECgQIBgAAAA==.Catris:BAAANQADCgcIEQAAAA==.Catset:BAAANQADCggICAAAAA==.',
Ch='Charlton:BAAANQAECgEIAgABNQAECgUICQABAAAAAA==.Chazzo:BAAANQAECgYICgAAAA==.Chazzy:BAAANQADCgcIBwAAAA==.Chila:BAAANQADCgYIEAAAAA==.',
Co='Commy:BAAANQADCggIEAAAAA==.Concorde:BAAANQADCgcIDgAAAA==.Copiousconns:BAAANQAECgQIBgAAAA==.Corlock:BAAANQADCgYIDAAAAA==.',
Cr='Craitos:BAAANQABCgMIBQAAAA==.Crimsonfury:BAAANQADCggIEAAAAA==.',
Cu='Cubos:BAAANQAECgEIAQAAAA==.Cutlash:BAAANQADCgcIEAAAAA==.',
Cy='Cynaea:BAAANQABCgQIBgABNQAECgUICQABAAAAAA==.',
Da='Daemona:BAAANQAECgIIAgAAAA==.Daieniceis:BAAANQADCggIDAAAAA==.Dalkurn:BAAANQAECggIEwAAAA==.',
De='Decayy:BAAANQAECggIEwAAAA==.Deceptakahn:BAAANQAECgMIBAAAAA==.Derailedbeef:BAABNQAECoENAAICAAgJJw7+OwDgAQACAAgJJw7+OwDgAQAAAA==.Deydoralia:BAAANQAECgcIDQAAAA==.',
Di='Diabeetus:BAAANQADCgQICAAAAA==.',
Dn='Dnme:BAAANQAECgQIBAAAAA==.',
Do='Doneldus:BAAANQADCgYIDQAAAA==.Dool:BAAANQADCgYIBwAAAA==.Dorfdragon:BAAANQAECgQIBgAAAA==.Dorfe:BAAANQAECgQIBwAAAA==.',
Dr='Drakthur:BAAANQADCgQIBAAAAA==.Draximus:BAAANQADCgUIBQAAAA==.Drewgarymore:BAAANQAECgIIAwAAAA==.',
Du='Dukker:BAAANQABCgIIAgAAAA==.Durandall:BAAANQAFFAIIAgAAAA==.Durleap:BAAANQADCgcIDQAAAA==.Durthmaul:BAAANQADCgYIBgAAAA==.',
Dw='Dwarflock:BAAANQADCggICAAAAA==.',
Dy='Dylpickl:BAAANQAECgUIBQAAAA==.',
Ef='Eft:BAAANQABCgQIBAAAAA==.',
El='Elow:BAAANQABCgUIBQAAAA==.',
Er='Erazminash:BAAANQAECgIIAwAAAA==.',
Es='Esdeáth:BAAANQADCgIIAgAAAA==.Esmae:BAAANQADCgcIDQAAAA==.Ess:BAAANQADCgcIEQAAAA==.',
Ev='Evalina:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Evvie:BAAANQADCgYIEAAAAA==.',
Ex='Executiepie:BAAANQADCggICAAAAA==.',
Fa='Fabulosoo:BAAANQAECgQIBgAAAA==.Fantarius:BAAANQAECgcIDgAAAA==.Fatdono:BAAANQADCggICAAAAA==.',
Fi='Fibbs:BAAANQAECgEIAgAAAA==.Fikti:BAAANQAECgUIBwAAAA==.Firocios:BAAANQAECgIIAgAAAA==.',
Fl='Flaminia:BAAANQADCgUICQAAAA==.',
Fo='Foxybeans:BAAANQADCgQIBwAAAA==.',
Fr='Fran:BAAANQADCgcIFAABNQAECgIIAgABAAAAAA==.Frieda:BAAANQABCgIIAgAAAA==.Frink:BAAANQADCgcIDgAAAA==.Frostyfella:BAABNQAECoEQAAIDAAgJyBtEKACoAgADAAgJyBtEKACoAgABNQABCgIIAgABAAAAAA==.',
Fu='Furman:BAAANQADCgMIAwAAAA==.',
Ga='Garypotter:BAAANQAECgEIAgAAAA==.Gazooks:BAAANQABCgQIBAAAAA==.',
Ge='Gelantria:BAAANQADCgcIBwAAAA==.',
Gl='Gleave:BAAANQAECgIIAgAAAA==.',
Gr='Greystoke:BAAANQADCgQIBAAAAA==.Greyvee:BAAANQAECgIIAgAAAA==.Grindelbald:BAAANQAECgUICgAAAA==.',
Gt='Gtfofupá:BAAANQADCgYIEAAAAA==.',
Gu='Gushee:BAAANQAECgQICAAAAA==.',
Gw='Gwenn:BAAANQADCgYIEgAAAA==.',
Ha='Hadez:BAAANQADCgcICwAAAA==.Haegan:BAAANQABCgYIBwAAAA==.Hagioszoe:BAAANQAECgQIBQAAAA==.Hairypoóter:BAAANQADCgUICQAAAA==.Hanamari:BAAANQAECggIEwAAAA==.Hanoe:BAAANQABCgEIAQAAAA==.Harakrron:BAAANQADCgUIBQAAAA==.Harleyquìnn:BAAANQADCgUICQAAAA==.Harydresden:BAAANQAECgIIAgAAAA==.Hawkesmage:BAAANQADCgMIAwAAAA==.Hawkslayer:BAAANQADCgcIDQAAAA==.',
He='Hedgelord:BAAANQAECggIEAAAAA==.',
Hi='Hisky:BAAANQAECgIIAgAAAA==.',
Ho='Hobe:BAAANQAECgQIBwAAAA==.Holytruck:BAAANQADCgEIAQAAAA==.Hoodmagik:BAAANQABCgYIBwABNQAECgYICQABAAAAAA==.Hornadus:BAAANQADCgMIAwAAAA==.Hornride:BAAANQADCgMIAwAAAA==.',
Hu='Humoresque:BAAANQADCgcIEQAAAA==.Huntaredead:BAAANQAECgQIBAABNQAECgcIDwABAAAAAA==.',
Ic='Icyblades:BAAANQADCggIFwAAAA==.',
Il='Ilidania:BAAANQADCgYIBgAAAA==.Ilyna:BAAANQAECgEIAgAAAA==.',
Im='Immortalnut:BAAANQAECgQIBQAAAA==.',
In='Inori:BAAANQADCgcIBwAAAA==.Interrupted:BAAANQAECgIIAgAAAA==.',
It='Itscell:BAAANQADCgEIAQAAAA==.',
Ja='Jaedis:BAAANQADCgYIEAAAAA==.Jaktar:BAAANQAECgQICAAAAA==.Jane:BAAANQADCgMIAgAAAA==.Janet:BAAANQAECgUICgAAAA==.Jani:BAAANQADCgQIBAABNQAECgUICgABAAAAAA==.Janiina:BAAANQADCgQIBwAAAA==.',
Je='Jezak:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
Jo='Jol:BAAANQABCgQIBAAAAA==.Jone:BAAANQADCgcIDQAAAA==.Joobs:BAAANQAECgEIAQAAAA==.Joosh:BAAANQADCggIFQAAAA==.',
Js='Jslice:BAABNQAECoEVAAICAAkJPR28EQD8AgACAAkJPR28EQD8AgAAAA==.',
Ju='Juda:BAAANQADCgYIBgAAAA==.Jurucil:BAAANQADCgQIBAAAAA==.',
Ka='Kaelys:BAAANQAECgEIAQAAAA==.Kahliea:BAAANQADCgcIEQAAAA==.Kaidance:BAAANQADCgcIDAAAAA==.Kaisaze:BAAANQADCgcICQAAAA==.Kapachka:BAAANQADCgYIDQAAAA==.Karbide:BAAANQADCgQIBQAAAA==.Kardisa:BAAANQABCgIIAgAAAA==.Kateri:BAAANQADCgYIEAAAAA==.Katmarie:BAAANQADCgQIAwAAAA==.Kazothor:BAAANQADCgcIEQAAAA==.',
Ke='Keria:BAABNQAECoEYAAIEAAkJhCMMAgCFAwAEAAkJhCMMAgCFAwAAAA==.Keyz:BAAANQAECgEIAQAAAA==.',
Ki='Kiretsu:BAAANQAECgYICwAAAA==.',
Ko='Kovus:BAAANQADCgYIEAAAAA==.',
Kr='Krelien:BAAANQADCgYICgAAAA==.Krispee:BAAANQADCgYIDgAAAA==.Kristanya:BAAANQAECgQIBgAAAA==.',
Ku='Kulaidmage:BAAANQAECgIIAwAAAA==.Kurtcowbain:BAAANQAECgMIAwAAAA==.',
Ky='Kynetik:BAAANQAECggICAAAAA==.Kyttin:BAAANQADCgcIBwAAAA==.',
La='Ladamirea:BAAANQAECgQIBgAAAA==.Lamashtu:BAAANQAECgEIAgAAAA==.Lashar:BAAANQADCgYIBgAAAA==.',
Le='Leiman:BAAANQABCgQIBQAAAA==.',
Li='Lilifa:BAAANQAECgQIBgAAAA==.Lilillidari:BAAANQAECgYICAABNQAECgkJGAAFAAwjAA==.Lillirann:BAAANQAECgEIAQAAAA==.Lilmontaro:BAABNQAECoEYAAMFAAkJDCN3AwAVAwAFAAkJ1h93AwAVAwAGAAgJUB7PDADUAgAAAA==.Lilunholy:BAAANQAECgUIBQABNQAECgkJGAAFAAwjAA==.Lirianna:BAAANQADCgMIAwAAAA==.Littany:BAAANQAECgUIBQAAAA==.Livane:BAAANQAECgMIBQAAAA==.',
Lo='Lowground:BAAANQADCgIIAgAAAA==.',
Lu='Lucïna:BAAANQAECgQIBgAAAA==.Ludk:BAAANQAECgQIBgAAAA==.Luk:BAAANQAECgQIBAABNQADCggIEgABAAAAAA==.Lumiela:BAAANQAECgEIAQAAAA==.Lunacy:BAAANQADCgYICgAAAA==.Lunì:BAAANQABCgMIAwAAAA==.',
['Ló']='Lóner:BAAANQADCgcIEQAAAA==.',
Ma='Macbayne:BAAANQADCgEIAQAAAA==.Maebe:BAAANQAECgQIBQAAAA==.Mageblaster:BAAANQADCgYICgAAAA==.Maggnut:BAAANQAECgQIBwAAAA==.Magicg:BAAANQAECgcIDwAAAA==.Magordito:BAAANQAECgQIBQAAAA==.Mairek:BAAANQAECgcIDgAAAA==.Maleigoron:BAAANQAECgQIBQAAAA==.Malkuri:BAAANQAECgIIAgABNQAECgUIBQABAAAAAA==.Malorysera:BAAANQAECgQIBAABNQAECgYICwABAAAAAA==.Matsuma:BAAANQADCgMIAwAAAA==.',
Mc='Mcbasketball:BAAANQAECgIIAgAAAA==.',
Me='Mechaljaxon:BAAANQADCggIDgAAAA==.Menirva:BAAANQAECgUIBQAAAA==.Merv:BAAANQAECgEIAQAAAA==.Metapal:BAAANQAECgcIEgABNQAECggICAABAAAAAA==.Metasham:BAAANQAECgcIEgABNQAECggICAABAAAAAA==.',
Mi='Miiaa:BAAANQAECgEIAQAAAA==.Mijoy:BAAANQADCggIDgAAAA==.Milane:BAAANQADCgUICQAAAA==.',
Mo='Moirasha:BAAANQAECgEIAQAAAA==.Monran:BAAANQAECgEIAQAAAA==.Moonwood:BAAANQADCgYIBgAAAA==.Moosand:BAAANQAECgIIAgAAAA==.Morphingtime:BAAANQAECgQIBgAAAA==.Mortivus:BAAANQADCgYIEAAAAA==.',
Mu='Muggs:BAAANQABCgQIBAAAAA==.Mulvane:BAAANQADCgYIEAAAAA==.Mustachio:BAAANQAECgEIAQAAAA==.',
Mw='Mwc:BAABNQAFFIEGAAMHAAUJ7xOeAQB5AQAHAAQJIRCeAQB5AQAIAAEJKCO8AgBpAAAAAA==.',
Mz='Mziao:BAAANQADCgYIBgAAAA==.',
Ne='Neall:BAAANQADCgYICgAAAA==.',
Ni='Nightbird:BAAANQADCggICQAAAA==.',
No='Nonna:BAAANQAECgQIBgAAAA==.Noslrac:BAAANQADCgYIEAAAAA==.Notbysight:BAAANQADCgYIBgAAAA==.Notorious:BAAANQAECgcICwAAAQ==.',
Ny='Nyxjr:BAAANQADCgIIAgAAAA==.',
Ob='Oblast:BAAANQAECgcIEAAAAA==.',
Od='Odb:BAAANQADCgQIBAAAAA==.Odirtyblasta:BAAANQADCgIIAgAAAA==.',
Ol='Olmanjankins:BAAANQAECgIIAgAAAA==.',
On='Onlyslams:BAAANQAECgcIBwAAAA==.',
Oo='Ooze:BAAANQADCgMIAwAAAA==.',
Or='Orter:BAAANQAECgIIBQAAAA==.',
Ot='Ottan:BAAANQADCgYICwAAAA==.',
Ov='Overkill:BAAANQADCggIFAAAAA==.',
Pa='Pandorasfox:BAAANQABCgQIBAAAAA==.Papsfear:BAAANQAECgQIBQAAAA==.Parceh:BAAANQAECgQIBgAAAA==.',
Ph='Phydaux:BAAANQADCgcICwAAAA==.',
Pi='Pinkponyclub:BAAANQADCggICAAAAA==.Pizzaman:BAAANQAECgEIAQAAAA==.',
Pr='Pringle:BAAANQADCgYIEgAAAA==.Prosciutto:BAAANQAECgQIBAAAAA==.Proxima:BAAANQADCgUIBgAAAA==.',
Pt='Ptoughneigh:BAAANQAECgQIBAAAAA==.',
Pu='Puckish:BAAANQAECggIEgAAAA==.Punn:BAAANQAECgUIBQABNQAECgcIDwABAAAAAA==.Punnisher:BAAANQAECgcIDwAAAA==.Pureflow:BAAANQAECgEIAQAAAA==.',
['Pä']='Päiñ:BAAANQADCgUIBQAAAA==.',
Qu='Quackers:BAAANQADCgcIDwAAAA==.',
Ra='Raelianna:BAAANQADCgUICgABNQAECgUICAABAAAAAA==.Raewyna:BAAANQADCgYICwAAAA==.Raine:BAAANQAECgQIBQAAAA==.Rainjar:BAAANQADCggIEAAAAA==.Ranron:BAAANQADCgQIBAAAAA==.Raphael:BAAANQAECgEIAQAAAA==.Rasik:BAAANQAECgQIBgAAAA==.Ravenblood:BAAANQADCggIDQAAAA==.Rayel:BAAANQAECgEIAQAAAA==.Raylyn:BAAANQADCgEIAQAAAA==.',
Rh='Rhadamancus:BAAANQAECgEIAQAAAA==.Rhani:BAAANQADCgcIDAAAAA==.Rheanon:BAAANQADCgQIBQAAAA==.Rhome:BAAANQAECgYIDAAAAA==.Rhox:BAAANQADCggICwAAAA==.',
Ri='Rialu:BAAANQAECgUIBwAAAA==.Ribald:BAAANQAECgQIBAAAAA==.Rickgrimes:BAAANQAECgcICwAAAA==.',
Ro='Roid:BAAANQAECggIEgAAAA==.Rotcorpse:BAAANQAECgEIAQAAAA==.',
Ru='Ruddam:BAAANQADCgcIDQAAAA==.',
['Rä']='Räveñz:BAAANQAECgEIAgAAAA==.',
Sa='Saintabes:BAAANQAECgcIDQAAAA==.Sakurah:BAAANQAECgEIAQAAAA==.Sandara:BAAANQADCgMIAwAAAA==.Sanrinn:BAAANQADCgUIBQAAAA==.Sarahboom:BAAANQAECgcIDAAAAA==.Sargarach:BAAANQADCgEIAQAAAA==.',
Sc='Scapegoat:BAEANQAECgQIBgAAAQ==.Scraime:BAAANQADCgcIBwAAAA==.',
Se='Seekýefirst:BAAANQADCgcIBwAAAA==.Seethe:BAAANQADCgYIBgAAAA==.Seilah:BAAANQAECgQIBQAAAA==.Seliah:BAAANQAECgQIBgAAAA==.',
Sh='Shadowglade:BAAANQAECgQIBgAAAA==.Shalltear:BAAANQADCgcIDwAAAA==.Shamizzle:BAAANQAECgQIBQAAAA==.Shammydavis:BAAANQAECgIIAgAAAA==.Shaølinstørm:BAAANQADCgMIAwAAAA==.Shiftybud:BAAANQADCgQIBwAAAA==.Shinobi:BAAANQADCggICAAAAA==.Shrapnel:BAAANQAECgIIAgAAAA==.Shàmwôw:BAAANQADCgYIBAAAAA==.Shàytan:BAAANQAECgEIAgAAAA==.',
Si='Sinistral:BAAANQAECgIIAgAAAA==.',
Sl='Slise:BAAANQADCgIIAwAAAA==.',
Sm='Smithers:BAAANQAECgQIBgAAAA==.',
Sn='Snappycakes:BAAANQAECgEIAQAAAA==.Sneakybunny:BAAANQAECgQIBgAAAA==.',
So='Sorabjr:BAAANQADCgcIDQAAAA==.Sorin:BAAANQADCgYIBgABNQAECgYICgABAAAAAA==.Soulbreaker:BAAANQAECgQIBgAAAA==.Southy:BAAANQAECgEIAgAAAA==.',
Sp='Sparxs:BAAANQADCgMIAwAAAA==.',
St='Starblunder:BAAANQADCgUICgAAAA==.Stormdeth:BAAANQADCgMIAwAAAA==.Stormmystic:BAAANQAECgIIAgAAAA==.Stylemonk:BAAANQAFFAIIAgAAAA==.',
Su='Sulfalloway:BAAANQADCgIIAgAAAA==.Sumawfulot:BAAANQADCggIFgAAAA==.Sunsparrow:BAAANQAECgIIAgAAAA==.',
Sy='Syraelia:BAAANQABCgEIAQAAAA==.Syvarris:BAAANQAECgYICQAAAA==.',
Ta='Tamesßond:BAAANQADCgYICAAAAA==.Tandaiff:BAAANQADCgYIBgAAAA==.Tankajahari:BAAANQAECgQIBAAAAA==.Tanksnotanks:BAAANQADCgYIDAAAAA==.Tanleron:BAAANQADCgMIAwAAAA==.Tarayn:BAAANQAECgQIBgAAAA==.',
Te='Teagan:BAAANQADCgYIDQAAAA==.Tenac:BAAANQADCggIDgAAAA==.Teoritta:BAEANQAECgQIBgAAAA==.',
Th='Thalimus:BAAANQADCgQIBAAAAA==.Thelle:BAAANQAECgUIBQABNQAECgkJGAAEAIQjAA==.Thewhitelion:BAAANQADCgcIDQAAAA==.',
Ti='Tigg:BAABNQAECoEVAAMFAAkJnh2cBQC4AgAFAAkJ4BycBQC4AgAGAAEJSCP6YgBNAAAAAA==.Tikifiki:BAAANQAECgIIAgAAAA==.',
To='Tokin:BAAANQADCgYIBgAAAA==.Toochill:BAAANQADCgEIAQAAAA==.Toshidot:BAAANQAECggIDQAAAA==.Totemtila:BAAANQAECgEIAQABNQAECgYICQABAAAAAA==.',
Tr='Translucent:BAAANQAECgUIBwAAAA==.Trazatra:BAAANQAECgUICQAAAA==.Truckah:BAAANQADCggICwAAAA==.Trueguidance:BAAANQAECgYIBgAAAA==.Tràvdog:BAAANQAECgEIAgAAAA==.',
Tu='Tunalongarms:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Tuonadari:BAAANQADCgMIAwAAAA==.Tuonai:BAAANQAECgIIAgAAAA==.Tusknus:BAAANQADCggIDgAAAA==.',
Ty='Tylordis:BAAANQADCgYICgAAAA==.',
['Tý']='Týr:BAAANQABCgIIBAAAAA==.',
Us='Usodead:BAAANQADCgQIBAAAAA==.Usosquishy:BAAANQAECgUIDAAAAA==.',
Va='Vader:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Valkuridk:BAABNQAECoEXAAMFAAkJVCaMAADEAwAFAAkJXSSMAADEAwAGAAgJKiZABQBaAwAAAA==.Vandy:BAAANQAECgYICwAAAA==.',
Ve='Vedo:BAAANQAECgcIEAAAAA==.Vedora:BAAANQADCggIFgAAAA==.Velf:BAAANQADCgEIAQAAAA==.Veradis:BAAANQADCgYIEgAAAA==.Vestiege:BAAANQABCgYIBwAAAA==.',
Vi='Vinland:BAAANQADCgYIDAAAAA==.Vinsmokesanj:BAAANQADCgQIBAAAAA==.Virulent:BAAANQAECgEIAQAAAA==.Vissarion:BAAANQADCgYIEgAAAA==.',
Vl='Vladak:BAAANQAECgIIAgAAAA==.',
Vo='Voc:BAAANQAECgYICgAAAA==.Voz:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Vu='Vulkin:BAAANQAECgIIAgAAAA==.',
Vv='Vv:BAAANQAECgQIBgAAAA==.',
Vy='Vyridiondk:BAAANQADCgQIBAAAAA==.Vyx:BAAANQADCgcIBwAAAA==.',
Wa='Waggi:BAAANQADCgYIBgABNQADCgYIEgABAAAAAA==.Waymán:BAAANQADCgQIBAAAAA==.',
We='Weebjones:BAAANQADCgQIBAAAAA==.Weelilcurse:BAAANQABCgMIAgAAAA==.',
Wu='Wumply:BAAANQAECggIDwAAAA==.',
['Wä']='Wäyman:BAAANQAECgQIBgAAAA==.',
Xa='Xaranthia:BAAANQAECgQIBAAAAA==.',
Xm='Xmcdizzle:BAAANQAECgEIAQAAAA==.',
Xy='Xylarra:BAAANQAECgQIBgAAAA==.',
Ya='Yautja:BAAANQAECgUIBQAAAA==.Yazule:BAAANQADCggIEAAAAA==.',
Yo='Yodawg:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Yoruba:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Za='Zamali:BAAANQAECgEIAgAAAA==.Zantris:BAAANQADCgUIBwABNQADCgYIEgABAAAAAA==.Zartella:BAAANQAECgQIBAAAAA==.Zaxon:BAAANQADCgYIDAAAAA==.',
Ze='Zendraza:BAAANQAECgIIAgAAAA==.Zephyrion:BAAANQAECgcIEQAAAA==.Zepplin:BAAANQAECgIIAgAAAA==.Zetro:BAAANQAECgQIBQAAAA==.',
Zr='Zreydyn:BAAANQADCgYIBgAAAA==.',
Zu='Zuma:BAAANQADCggICAAAAA==.Zuraxxus:BAAANQABCgMIAwAAAA==.',
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
