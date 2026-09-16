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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Druid-Restoration','DeathKnight-Blood','Warrior-Arms','Paladin-Holy','Priest-Holy','Mage-Arcane','Warlock-Demonology','DemonHunter-Havoc','Shaman-Elemental','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Warlock-Destruction','Monk-Windwalker','Priest-Shadow',}
local provider = {region='US',realm='Medivh',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abashai:BAAANQAECgMIBAAAAA==.',
Ae='Aellyria:BAAANQADCgEIAQAAAA==.Aerrikon:BAAANQAECgEIAQABNQAECgIIBgABAAAAAA==.',
Ak='Akaili:BAAANQAECgQIBgAAAA==.',
Al='Alexiya:BAAANQAECgQIBgAAAA==.Allacari:BAAANQAECgIIBAAAAA==.Allumer:BAAANQAECgEIAQAAAA==.Alodir:BAAANQADCgYICgABNQAECgQIBgABAAAAAA==.Alstadin:BAAANQADCgIIAgAAAA==.Alucardd:BAAANQADCgcIFAAAAA==.',
Am='Amanda:BAAANQAECgQIBwAAAA==.Amonamarth:BAAANQAECgIIAgAAAA==.',
An='Anabelleigh:BAAANQABCgcICgAAAA==.Andrise:BAAANQAECgQIBwAAAA==.Annathesia:BAAANQADCgEIAQAAAA==.Antibear:BAAANQAECgIIAwAAAA==.',
Ap='Apol:BAAANQAECgUIBwAAAA==.',
Ar='Arachne:BAAANQAECgUICgAAAA==.Arakar:BAAANQAECgYIDAAAAA==.Aralynne:BAAANQAECgEIAgAAAA==.Arch:BAAANQADCgcIEgAAAA==.Ardori:BAAANQADCggIFwAAAA==.Arlïnn:BAAANQAECgQIBgABNQAECgYICgABAAAAAA==.Armorya:BAABNQAECoEYAAICAAgJixm2NwAhAgACAAgJixm2NwAhAgAAAA==.Armyofone:BAAANQADCggIGgAAAA==.Artaius:BAAANQAECgUICgAAAA==.',
As='Ashaw:BAAANQADCgYIBgAAAA==.Astariel:BAAANQADCggICAABNQAECgIIAwABAAAAAA==.Astarog:BAAANQAECgIIAwAAAA==.',
At='Atafloosy:BAEANQAECgIIAwAAAA==.Athelf:BAAANQAECgcIDgAAAA==.',
Au='Aubriell:BAAANQADCgcIFAAAAA==.',
Ay='Ayrnerdam:BAAANQADCggIEgAAAA==.',
Ba='Babelfish:BAAANQAECgUIBQAAAA==.Bagleflinger:BAAANQAECgQICAAAAA==.Baldr:BAAANQAECgQIBQAAAA==.Batarang:BAAANQAECgQICQAAAA==.',
Be='Bealzulbub:BAAANQABCgMIAwAAAA==.Bearbarian:BAAANQAECgQICQAAAA==.Beastkael:BAAANQAECgMIAwAAAA==.Beg:BAAANQAECgcIDQAAAA==.Belfalas:BAAANQABCgQIBgAAAA==.Berghain:BAAANQADCgQIBQAAAA==.Berick:BAAANQAECgEIAgAAAA==.Betzalel:BAAANQAECgQIBgAAAA==.Beytryx:BAAANQAECgEIAQAAAA==.',
Bl='Bladeoftruth:BAAANQAECgcIEQAAAA==.Blitzwing:BAAANQADCggIDgAAAA==.Bloodyaggro:BAAANQADCgcIFAAAAA==.',
Bo='Bonnabelle:BAAANQAECgYIEQAAAA==.Boombawks:BAAANQADCgcICAAAAA==.Bos:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Bowtoahh:BAAANQABCgEIAQABNQAECgUICgABAAAAAA==.',
Br='Brewnelle:BAAANQADCggIDgABNQAECgYIEAABAAAAAA==.Bruid:BAAANQAECgYIEAAAAA==.Bruneigin:BAAANQADCgYIFgAAAA==.',
Ca='Calzone:BAAANQADCgYIBgAAAA==.Cambria:BAAANQADCgEIAQABNQAECgIIAwABAAAAAA==.Cardian:BAAANQADCgcIEwAAAA==.Caridin:BAAANQADCgYIEgAAAA==.Carmey:BAAANQAECgMIAwAAAA==.Carrin:BAABNQAECoEXAAICAAcJYBa7RADkAQACAAcJYBa7RADkAQAAAA==.Catalyia:BAAANQAECgQICgAAAA==.Catris:BAAANQADCgcIGAAAAA==.Catset:BAAANQAECgQIBAAAAA==.',
Ch='Charades:BAAANQADCgYIBgAAAA==.Charlton:BAAANQAECgEIAwABNQAECgUIDgABAAAAAA==.Chazzo:BAAANQAECgcIEQAAAA==.Chazzy:BAAANQADCgcIBwAAAA==.Chila:BAAANQADCgYIFgAAAA==.',
Co='Commy:BAAANQAECgUIBQAAAA==.Concorde:BAAANQAECgQIBAAAAA==.Copiousconns:BAAANQAECgQICgAAAA==.Corlock:BAAANQADCgYIDAAAAA==.',
Cr='Craitos:BAAANQABCgUICQAAAA==.Crimsonfury:BAAANQADCggIEAAAAA==.',
Cu='Cubos:BAAANQAECggICQAAAA==.Cutlash:BAAANQADCgcIFwAAAA==.',
Cy='Cynaea:BAAANQADCgQIBAABNQAECgUIDgABAAAAAA==.',
Da='Daemona:BAAANQAECgMIBQAAAA==.Daieniceis:BAAANQAECgIIAgAAAA==.Dalkurn:BAABNQAECoEfAAIDAAkJ6yOjAQCFAwADAAkJ6yOjAQCFAwAAAA==.',
De='Decayy:BAABNQAECoEfAAIEAAkJDyIjBwBIAwAEAAkJDyIjBwBIAwAAAA==.Deceptakahn:BAAANQAECgQICAAAAA==.Derailedbeef:BAABNQAECoEUAAIFAAgJLhTcPQA/AgAFAAgJLhTcPQA/AgAAAA==.Deydoralia:BAABNQAECoEXAAIGAAgJZh4WEwDIAgAGAAgJZh4WEwDIAgAAAA==.',
Di='Diabeetus:BAAANQADCgQICAAAAA==.',
Dn='Dnme:BAAANQAECgYICgAAAA==.',
Do='Doneldus:BAAANQADCgYIDQAAAA==.Dool:BAAANQADCgYIBwAAAA==.Dorfdragon:BAAANQAECgQICgAAAA==.Dorfe:BAAANQAECgUIDQAAAA==.',
Dr='Drakona:BAAANQABCgQICAAAAA==.Drakthur:BAAANQADCgQIBQAAAA==.Draximus:BAAANQADCgUIBQAAAA==.Drewgarymore:BAAANQAECgQIBwAAAA==.',
Du='Dukker:BAAANQABCgIIAgAAAA==.Durandall:BAABNQAECoEbAAICAAkJnRmZJQCDAgACAAkJnRmZJQCDAgAAAA==.Durleap:BAAANQADCgcIFAAAAA==.Durthmaul:BAAANQADCgYIBgAAAA==.',
Dw='Dwarflock:BAAANQAECgUIBQAAAA==.',
Dy='Dylpickl:BAAANQAFFAIIAgAAAA==.Dylán:BAAANQAECgQIBAAAAA==.',
Ef='Eft:BAAANQABCgQIBAAAAA==.',
El='Elliemae:BAAANQADCgYIBgAAAA==.Elow:BAAANQADCgIIAgAAAA==.',
Er='Erazminash:BAAANQAECgIIAwAAAA==.',
Es='Esdeáth:BAAANQADCgIIAgAAAA==.Esmae:BAAANQADCgcIFAAAAA==.Ess:BAAANQADCgcIGAAAAA==.',
Ev='Evalina:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Evvie:BAAANQADCgYIFgAAAA==.',
Ex='Executiepie:BAAANQADCggICAAAAA==.',
Fa='Fabulosoo:BAAANQAECgQICgAAAA==.Fantarius:BAABNQAECoEZAAIHAAgJWiERDwDVAgAHAAgJWiERDwDVAgAAAA==.Fatdono:BAAANQAECgUIBQAAAA==.',
Fi='Fibbs:BAAANQAECgQIBgAAAA==.Fikti:BAAANQAECgYIDQAAAA==.Firocios:BAAANQAECgIIBAAAAA==.',
Fl='Flaminia:BAAANQADCgUICQAAAA==.',
Fo='Foxybeans:BAAANQADCgYICgAAAA==.',
Fr='Fran:BAAANQAECgQIBAAAAA==.Frieda:BAAANQABCgIIAgAAAA==.Frink:BAAANQADCgcIFAAAAA==.Frostyfella:BAABNQAECoEYAAIIAAkJ0Bs+LgDYAgAIAAkJ0Bs+LgDYAgABNQABCgIIAgABAAAAAA==.',
Fu='Furman:BAAANQADCgMIAwAAAA==.',
['Fá']='Fáith:BAAANQADCggICAAAAA==.',
Ga='Garypotter:BAAANQAECgQIBgAAAA==.Gazooks:BAAANQADCgMIAwAAAA==.',
Ge='Gelantria:BAAANQADCgcIBwAAAA==.',
Gl='Gleave:BAAANQAECgUIBwAAAA==.',
Go='Goodbrew:BAAANQAECgEIAQAAAA==.',
Gr='Greystoke:BAAANQADCgQIBAAAAA==.Greyvee:BAAANQAECgIIAwAAAA==.Grindelbald:BAAANQAECgUICwAAAA==.',
Gt='Gtfofupá:BAAANQADCgcIEQAAAA==.',
Gu='Gushee:BAAANQAECgQIDAAAAA==.',
Gw='Gwenn:BAAANQADCgYIEgAAAA==.',
Gy='Gyes:BAAANQAECgEIAQAAAA==.',
Ha='Hadez:BAAANQADCgcICwAAAA==.Haegan:BAAANQABCgYIBwAAAA==.Hagioszoe:BAAANQAECgQIBQAAAA==.Hairypoóter:BAAANQADCgUICQAAAA==.Hanamari:BAAANQAECggIEwAAAA==.Hanoe:BAAANQABCgEIAQAAAA==.Harakrron:BAAANQADCgUICgAAAA==.Harleyquìnn:BAAANQADCgYIDwAAAA==.Harydresden:BAAANQAECgIIBAAAAA==.Hawkesmage:BAAANQADCgMIAwAAAA==.Hawkslayer:BAAANQADCgcIFAAAAA==.',
He='Hedgelord:BAAANQAECggIEwAAAA==.',
Hi='Hisky:BAAANQAECgQIBgAAAA==.',
Ho='Hobe:BAAANQAECgQICwAAAA==.Holytruck:BAAANQADCgEIAQAAAA==.Hoodmagik:BAAANQABCgYIBwABNQAECgYIBgABAAAAAA==.Hornadus:BAAANQADCgMIAwAAAA==.Hornride:BAAANQADCgMIAwAAAA==.',
Hu='Humoresque:BAAANQADCgcIGAAAAA==.Huntaredead:BAAANQAECgQIBAABNQAECggIGgAJAKUhAA==.',
Ic='Icyblades:BAAANQAECgQIBAAAAA==.',
Il='Ilidania:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Ilyna:BAAANQAECgQIBgAAAA==.',
Im='Immortalnut:BAAANQAECgUICgAAAA==.',
In='Inori:BAAANQADCgcIBwAAAA==.Interrupted:BAAANQAECgIIAgAAAA==.',
It='Itscell:BAAANQADCgEIAQAAAA==.',
Ja='Jaedis:BAAANQADCggIEgAAAA==.Jaktar:BAAANQAECgcIDwAAAA==.Jane:BAAANQADCgMIAgAAAA==.Janet:BAAANQAECgYIDAAAAA==.Jani:BAAANQADCgQIBAABNQAECgYIDAABAAAAAA==.Janiina:BAAANQADCgYIDQAAAA==.',
Je='Jezak:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.',
Jo='Jol:BAAANQABCgQIBAAAAA==.Jone:BAAANQADCgcIFAAAAA==.Joobs:BAAANQAECgIIAwAAAA==.Joosh:BAAANQAECgUIBQAAAA==.',
Js='Jslice:BAABNQAECoEVAAIFAAkJPR2cIADTAgAFAAkJPR2cIADTAgAAAA==.',
Ju='Juda:BAAANQADCgcIDQAAAA==.Jurucil:BAAANQADCgQIBAAAAA==.',
Ka='Kaelys:BAAANQAECgMIBAAAAA==.Kahliea:BAAANQADCgcIGAAAAA==.Kaidance:BAAANQADCgcIDAAAAA==.Kaisaze:BAAANQADCgcIEAAAAA==.Kapachka:BAAANQADCgYIEwAAAA==.Karbide:BAAANQADCgQIBQAAAA==.Kardisa:BAAANQABCgIIAgAAAA==.Kateri:BAAANQADCgYIFgAAAA==.Katmarie:BAAANQADCgQIAwAAAA==.Kazothor:BAAANQADCgcIGAAAAA==.',
Ke='Keria:BAACNQAFFIEHAAIKAAUJqxuHAQDXAQAKAAUJqxuHAQDXAQA1AAQKgSEAAgoACQkiJPwCAJQDAAoACQkiJPwCAJQDAAAA.Keyz:BAAANQAECgQIBQAAAA==.',
Ki='Kiretsu:BAAANQAECgcIEAAAAA==.',
Ko='Kovus:BAAANQADCgYIFgAAAA==.',
Kr='Kragami:BAAANQADCggICAAAAA==.Krelien:BAAANQAECgMIAwAAAA==.Krispee:BAAANQAECgUIBQAAAA==.Kristanya:BAAANQAECgQICQAAAA==.',
Ku='Kulaidmage:BAAANQAECgMIBgAAAA==.Kurtcowbain:BAAANQAECgQIBwAAAA==.',
Ky='Kynetik:BAAANQAECggICAABNQAECgkJHQALAEQWAA==.Kyttin:BAAANQADCggICAAAAA==.',
La='Ladamirea:BAAANQAECgYIDAAAAA==.Lamashtu:BAAANQAECgQIBgAAAA==.Lashar:BAAANQADCgYIBgAAAA==.',
Le='Leiman:BAAANQABCgQIBQAAAA==.Lexiê:BAAANQAECgQIBAAAAA==.',
Li='Lilifa:BAAANQAECgQICgAAAA==.Lilillidari:BAAANQAECgYIDgABNQAECgkJIgAMAKIlAA==.Lillirann:BAAANQAECgEIAQAAAA==.Lilmontaro:BAABNQAECoEiAAMMAAkJoiVEBQAuAwAMAAkJ7CFEBQAuAwANAAgJlSCrDwDeAgAAAA==.Lilunholy:BAAANQAECgYICAABNQAECgkJIgAMAKIlAA==.Lirianna:BAAANQADCgMIAwAAAA==.Littany:BAAANQAECgcIDAAAAA==.Livane:BAAANQAECgMIBQAAAA==.',
Lo='Loestus:BAAANQADCgQIBAAAAA==.Lowground:BAAANQADCgIIAgAAAA==.',
Lu='Lucïna:BAAANQAECgQIBgAAAA==.Ludk:BAAANQAECgQICQAAAA==.Luk:BAAANQAECgcIDAABNQADCggIGgABAAAAAA==.Lumiela:BAAANQAECgEIAQAAAA==.Lunacy:BAAANQADCgYICgAAAA==.Luni:BAAANQADCgMIBAAAAA==.Lunì:BAAANQABCgMIAwABNQADCgMIBAABAAAAAA==.',
['Ló']='Lóner:BAAANQAECgIIAgABNQAECgYICwABAAAAAA==.',
Ma='Macbayne:BAAANQADCgEIAQAAAA==.Maebe:BAAANQAECgQIBQAAAA==.Mageblaster:BAAANQADCgYICgAAAA==.Maggnut:BAAANQAECgYIDQAAAA==.Magicg:BAAANQAFFAEIAQAAAA==.Magordito:BAAANQAECgYICwAAAA==.Mairek:BAABNQAECoEZAAIIAAgJOBrNTgBgAgAIAAgJOBrNTgBgAgAAAA==.Maleigoron:BAAANQAECgYICwAAAA==.Malkuri:BAAANQAECgYICAAAAA==.Malorysera:BAAANQAECgcICwAAAA==.Matsuma:BAAANQADCgMIAwAAAA==.',
Mc='Mcbasketball:BAAANQAECgIIAgAAAA==.',
Me='Mechaljaxon:BAAANQAECgQIBAAAAA==.Menirva:BAAANQAECgUICgABNQAECgYICAABAAAAAA==.Merv:BAAANQAECgQIBQAAAA==.Metapal:BAAANQAECgcIEgABNQAECgkJHQALAEQWAA==.Metasham:BAABNQAECoEdAAILAAkJRBanGQCoAgALAAkJRBanGQCoAgAAAA==.',
Mi='Miiaa:BAAANQAECgUIBgAAAA==.Mijoy:BAAANQAECgQIBAAAAA==.Milane:BAAANQADCgYIDwAAAA==.',
Mo='Moirasha:BAAANQAECgIIAwAAAA==.Monran:BAAANQAECgEIAQAAAA==.Moonwood:BAAANQADCgYIBgAAAA==.Moosand:BAAANQAECgQIBgAAAA==.Morphingtime:BAAANQAECgQIBgAAAA==.Mortivus:BAAANQADCgYIFgAAAA==.',
Mu='Muggs:BAAANQADCggICAAAAA==.Mulvane:BAAANQADCgYIFgAAAA==.Mustachio:BAAANQAECgIIAwAAAA==.',
Mw='Mwc:BAACNQAFFIEMAAMOAAYJzhapAQDgAQAOAAUJ3hOpAQDgAQAPAAIJ6RdyAwC/AAA1AAQKgRYAAw4ACQkFJbMBAJADAA4ACQkFJbMBAJADAA8ABAl3FhYnAC0BAAAA.',
Mz='Mziao:BAAANQADCgcIDQAAAA==.',
Na='Nazureshal:BAAANQADCggICAABNQAECgUICAABAAAAAA==.',
Ne='Neall:BAAANQADCgYICgAAAA==.Ner:BAAANQADCgEIAQAAAA==.Nevets:BAAANQADCggICAAAAA==.',
Ni='Nightbird:BAAANQADCggIDwAAAA==.',
No='Nonna:BAAANQAECgQICQAAAA==.Noslrac:BAAANQADCgYIFAAAAA==.Notbysight:BAAANQADCgYIBgAAAA==.Notorious:BAAANQAECgcIEQAAAQ==.',
Ny='Nyxjr:BAAANQADCgIIAgAAAA==.',
Ob='Oblast:BAABNQAECoEbAAIIAAkJ4SKICQCSAwAIAAkJ4SKICQCSAwAAAA==.',
Od='Odb:BAAANQADCgQIBAAAAA==.Odirtyblasta:BAAANQADCgYIBgAAAA==.',
Ol='Olmanjankins:BAAANQAECgQIBgAAAA==.',
On='Onlyslams:BAAANQAFFAEIAQAAAA==.',
Oo='Ooze:BAAANQADCgMIAwAAAA==.',
Or='Orter:BAAANQAECgIIBgAAAA==.',
Ot='Ottan:BAAANQADCgYICwAAAA==.',
Ov='Overkill:BAAANQAECgMIAwAAAA==.',
Pa='Pandorasfox:BAAANQABCgQIBAAAAA==.Papsfear:BAAANQAECgUICgAAAA==.Parceh:BAAANQAECgQICQAAAA==.',
Ph='Phydaux:BAAANQADCgcIEgAAAA==.',
Pi='Pinkponyclub:BAAANQADCggICAAAAA==.Pizzaman:BAAANQAECgIIAwAAAA==.',
Pr='Pringle:BAAANQADCgYIEgABNQAECgQIBAABAAAAAA==.Prosciutto:BAAANQAECgQIBAAAAA==.Proxima:BAAANQADCggIDAAAAA==.',
Pt='Ptoughneigh:BAAANQAECgQIBAAAAA==.',
Pu='Puckish:BAABNQAECoEdAAMHAAkJ0wytMADjAQAHAAkJ0wytMADjAQAQAAEJvAF3HAAoAAAAAA==.Punn:BAAANQAECgcIDAABNQAECggIGgAJAKUhAA==.Punnisher:BAABNQAECoEaAAMJAAgJpSHHCgASAwAJAAgJpSHHCgASAwARAAEJvhsHUQBPAAAAAA==.Pureflow:BAAANQAECgIIAwAAAA==.',
['Pä']='Päiñ:BAAANQADCgUIBQAAAA==.',
Qu='Quackers:BAAANQADCgcIDwAAAA==.Quicks:BAAANQAECgcICwAAAA==.',
Ra='Raelianna:BAAANQADCggIEgABNQAECgYIEgABAAAAAA==.Raewyna:BAAANQAECgEIAQAAAA==.Raine:BAAANQAECgQIBQAAAA==.Rainjar:BAAANQADCggIGAAAAA==.Rancîd:BAAANQAECgQIBAAAAA==.Ranron:BAAANQADCgQIBgABNQAECgQIBAABAAAAAA==.Raphael:BAAANQAECgMIBAAAAA==.Rasik:BAAANQAECgQICQAAAA==.Ravenblood:BAAANQADCggIDQAAAA==.Rayel:BAAANQAECgIIAwAAAA==.Raylyn:BAAANQADCgEIAQAAAA==.',
Rh='Rhadamancus:BAAANQAECgIIAwAAAA==.Rhani:BAAANQAECgQIBAAAAA==.Rheanon:BAAANQADCgYICwAAAA==.Rhome:BAAANQAECgYIEgAAAA==.Rhox:BAAANQADCggIDwAAAA==.',
Ri='Rialu:BAAANQAECgYIDQAAAA==.Ribald:BAAANQAECgQIBAAAAA==.Rickgrimes:BAAANQAECgcIEAAAAA==.',
Ro='Roid:BAABNQAECoEeAAMGAAkJLw5QKAAxAgAGAAkJLw5QKAAxAgACAAIJawJ21gBHAAAAAA==.Rotcorpse:BAAANQAECgEIAQAAAA==.',
Ru='Ruddam:BAAANQADCgcIEwAAAA==.',
['Rä']='Räveñz:BAAANQAECgQIBgAAAA==.',
Sa='Saintabes:BAAANQAECgcIEAAAAA==.Sakurah:BAAANQAECgIIAwAAAA==.Sandara:BAAANQADCgMIAwAAAA==.Sanrinn:BAAANQADCgUIBQAAAA==.Sappy:BAAANQAECgEIAQAAAA==.Sarahboom:BAABNQAECoEWAAIIAAkJPQ2zVwBCAgAIAAkJPQ2zVwBCAgAAAA==.Sarahjupiter:BAAANQAECgQIBAABNQAECgkJFgAIAD0NAA==.Sargarach:BAAANQADCgEIAQAAAA==.',
Sc='Scapegoat:BAEANQAECgQICQAAAQ==.Scraime:BAAANQADCgcIBwAAAA==.',
Se='Seekýefirst:BAAANQADCgcIBwAAAA==.Seethe:BAAANQADCgYIBgAAAA==.Seilah:BAAANQAECgQIBQAAAA==.Seliah:BAAANQAECgQICgAAAA==.',
Sh='Shadowglade:BAAANQAECgQICQAAAA==.Shalltear:BAAANQADCgcIFQAAAA==.Shamizzle:BAAANQAECgQICAAAAA==.Shammydavis:BAAANQAECgIIBAAAAA==.Shaølinstørm:BAAANQADCgMIAwAAAA==.Shiftybud:BAAANQADCgQICwAAAA==.Shinobi:BAAANQAECgEIAQAAAA==.Shrapnel:BAAANQAECgIIBAAAAA==.Shàmwôw:BAAANQADCgYIBAAAAA==.Shàytan:BAAANQAECgQIBgAAAA==.',
Si='Sinistral:BAAANQAECgIIAgAAAA==.',
Sl='Slise:BAAANQADCgIIAwAAAA==.',
Sm='Smithers:BAAANQAECgQICQAAAA==.',
Sn='Snappycakes:BAAANQAECgEIAQAAAA==.Sneakybunny:BAAANQAECgQICQAAAA==.',
So='Solómon:BAAANQAECgEIAQAAAA==.Sorabjr:BAAANQADCgcIEwAAAA==.Sorin:BAAANQADCgYIBgABNQAECgYICgABAAAAAA==.Soulbreaker:BAAANQAECgQICgAAAA==.Southy:BAAANQAECgQIBgAAAA==.',
Sp='Sparxs:BAAANQADCgMIAwAAAA==.',
St='Starblunder:BAAANQADCgUICgAAAA==.Stormdeth:BAAANQADCgMIAwAAAA==.Stormmystic:BAAANQAECgIIAgAAAA==.Stylemonk:BAACNQAFFIEIAAISAAUJmRxDAQD2AQASAAUJmRxDAQD2AQA1AAQKgRwAAhIACAl4JnQCAI8DABIACAl4JnQCAI8DAAAA.',
Su='Sulfalloway:BAAANQADCgIIAgAAAA==.Sumawfulot:BAAANQAECgUIBQAAAA==.Sunsparrow:BAAANQAECgIIAgAAAA==.',
Sw='Swankdave:BAAANQADCgcIBwAAAA==.',
Sy='Syraelia:BAAANQABCgMIAwAAAA==.Syvarris:BAAANQAECgcIDwAAAA==.',
Ta='Tamesßond:BAAANQADCgcIDwAAAA==.Tandaiff:BAAANQADCgYIBgAAAA==.Tanksnotanks:BAAANQADCgYIEgAAAA==.Tanleron:BAAANQADCgMIAwAAAA==.Tarayn:BAAANQAECgQICgAAAA==.',
Te='Teagan:BAAANQADCgYIEwAAAA==.Tenac:BAAANQADCggIDgAAAA==.Teoritta:BAEANQAECgQICgAAAA==.Terllin:BAAANQADCgQIBAAAAA==.',
Th='Thalimus:BAAANQADCgYICgAAAA==.Thelle:BAAANQAECgYICwABNQAFFAUIBwAKAKsbAA==.Thewhitelion:BAAANQADCgcIFAAAAA==.',
Ti='Tigg:BAABNQAECoEeAAMMAAkJ3x9mBgAQAwAMAAkJSx9mBgAQAwANAAEJSCMmeABJAAAAAA==.Tikifiki:BAAANQAECgMIBQAAAA==.',
To='Tokin:BAAANQADCgYICgAAAA==.Toochill:BAAANQADCgEIAQAAAA==.Toshidot:BAABNQAECoEXAAIJAAkJ/B2CDAD/AgAJAAkJ/B2CDAD/AgAAAA==.Totemtila:BAAANQAECgEIAQABNQAECgYIDgABAAAAAA==.',
Tr='Translucent:BAAANQAECgUIDAAAAA==.Trazatra:BAAANQAECgUIDgAAAA==.Truckah:BAAANQAECgMIAwAAAA==.Tràvdog:BAAANQAECgQIBgAAAA==.',
Tu='Tunalongarms:BAAANQAECgIIAgAAAA==.Tuonadari:BAAANQADCgMIAwAAAA==.Tuonai:BAAANQAECgIIBAAAAA==.Tusknus:BAAANQAECgIIAgAAAA==.',
Ty='Tylordis:BAAANQADCgYICgAAAA==.',
['Tý']='Týr:BAAANQABCgcICQAAAA==.',
Us='Usodead:BAAANQADCgQIBAAAAA==.Usosquishy:BAAANQAECgcIEgAAAA==.',
Va='Vader:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.Valkuridk:BAABNQAECoEfAAMMAAkJkyZYAAD1AwAMAAkJgSZYAAD1AwANAAgJKibQCAA9AwAAAA==.Vandy:BAAANQAECgcIEgAAAA==.',
Ve='Vedo:BAAANQAECgcIEAAAAA==.Vedora:BAAANQAECgUIBQAAAA==.Velf:BAAANQADCgEIAQAAAA==.Veradis:BAAANQADCgYIEgAAAA==.Vestiege:BAAANQABCgYIBwAAAA==.',
Vi='Vinland:BAAANQADCgYIEgAAAA==.Vinsmokesanj:BAAANQADCgQIBAAAAA==.Virulent:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Vissarion:BAAANQADCgYIEgAAAA==.',
Vl='Vladak:BAAANQAECgUIBwAAAA==.',
Vo='Voc:BAAANQAECgcIEQAAAA==.Voz:BAAANQAECgIIAgAAAA==.',
Vu='Vulkin:BAAANQAECgIIAwAAAA==.',
Vv='Vv:BAAANQAECgYIDAAAAA==.',
Vy='Vyridiondk:BAAANQADCgcICwAAAA==.Vyx:BAAANQADCgcIDgAAAA==.',
Wa='Waggi:BAAANQAECgQIBAAAAA==.Waymán:BAAANQADCgYICQAAAA==.',
We='Weebjones:BAAANQADCgQIBAAAAA==.Weelilcurse:BAAANQADCggICAAAAA==.Wegberto:BAAANQADCggICAAAAA==.',
Wu='Wumply:BAABNQAECoEaAAITAAkJQRBcEABjAgATAAkJQRBcEABjAgAAAA==.',
['Wä']='Wäyman:BAAANQAECgQICQAAAA==.',
Xa='Xaranthia:BAAANQAECgYICgAAAA==.',
Xm='Xmcdizzle:BAAANQAECgIIAwAAAA==.',
Xy='Xylarra:BAAANQAECgQICQAAAA==.',
Ya='Yautja:BAAANQAECgUICgAAAA==.Yazule:BAAANQAECgUIBQAAAA==.',
Yo='Yodawg:BAAANQAECgMIBAABNQAECgcICQABAAAAAA==.Yoruba:BAAANQADCgMIAwABNQAECgIIAwABAAAAAA==.',
Za='Zairroth:BAAANQABCgYIBgAAAA==.Zamali:BAAANQAECgQIBgAAAA==.Zantris:BAAANQADCgUIBwABNQAECgQIBAABAAAAAA==.Zartella:BAAANQAECgQIBQABNQAECgYICwABAAAAAA==.Zaxon:BAAANQADCgYIDAAAAA==.',
Ze='Zendraza:BAAANQAECgQIBgAAAA==.Zephyrion:BAABNQAECoEdAAIEAAkJgRfZEgCgAgAEAAkJgRfZEgCgAgABNQABCgQIBAABAAAAAA==.Zepplin:BAAANQAECgQIBgAAAA==.Zerenity:BAAANQADCgQIBgAAAA==.Zetro:BAAANQAECgYICwAAAA==.',
Zr='Zreydyn:BAAANQADCgYICQAAAA==.',
Zu='Zuma:BAAANQAECgMIAwAAAA==.Zuraxxus:BAAANQABCgMIAwAAAA==.',
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
