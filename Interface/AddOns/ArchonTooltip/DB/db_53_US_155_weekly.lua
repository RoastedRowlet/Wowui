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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Priest-Holy','Druid-Restoration','Druid-Balance','DeathKnight-Blood','Warrior-Arms','Paladin-Holy','Mage-Arcane','Monk-Windwalker','Monk-Mistweaver','Warlock-Demonology','DemonHunter-Havoc','Shaman-Elemental','DeathKnight-Frost','DeathKnight-Unholy','Priest-Shadow','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Warlock-Destruction','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery',}
local provider = {region='US',realm='Medivh',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abashai:BAAANQAECgYICgAAAA==.',
Ae='Aellyria:BAAANQADCgEIAQAAAA==.Aerrikon:BAAANQAECgEJAQABNQAECgMJCQABAAAAAA==.',
Ak='Akaili:BAAANQAECgQIBgAAAA==.',
Al='Alexiya:BAAANQAECgUICgAAAA==.Allacari:BAAANQAECgUICQAAAA==.Allumer:BAAANQAECgEIAQAAAA==.Alodir:BAAANQADCgYICgABNQAECgQJBgABAAAAAA==.Alstadin:BAAANQADCgMJAwAAAA==.Alucardd:BAAANQADCggJGAAAAA==.',
Am='Amanda:BAAANQAECgUJDAAAAA==.Amonamarth:BAAANQAECgUIBwAAAA==.',
An='Anabelleigh:BAAANQABCggIDgAAAA==.Andrise:BAAANQAECgQICwAAAA==.Annathesia:BAAANQADCgEIAQAAAA==.Antibear:BAAANQAECgMJBgAAAA==.',
Ap='Apol:BAAANQAECgUJDAAAAA==.',
Ar='Arachne:BAAANQAECgcIEQAAAA==.Arakar:BAAANQAECgcJEwAAAA==.Aralynne:BAAANQAECgMJBQAAAA==.Arch:BAAANQADCggJGAAAAA==.Ardori:BAAANQAECgQIBAAAAA==.Arlïnn:BAAANQAECgQIBgABNQAECgcICwABAAAAAA==.Armorya:BAABNQAECoEdAAICAAkK6hiMOgBqAgACAAkK6hiMOgBqAgAAAA==.Armyofone:BAAANQADCggIIgAAAA==.Artaius:BAAANQAECgcIEAAAAA==.Arthuun:BAAANQAECggICAAAAA==.Artom:BAAANQADCgUJBQAAAA==.',
As='Ashaw:BAAANQADCgYIBgAAAA==.Astariel:BAAANQADCggICAABNQAECgUJCAABAAAAAA==.Astarog:BAAANQAECgUICAAAAA==.',
At='Atafloosy:BAEANQAECgMIBgAAAA==.Athelf:BAAANQAECgcIDgAAAA==.Attina:BAAANQABCgEIAQAAAA==.',
Au='Aubriell:BAAANQADCggJHAAAAA==.',
Ay='Ayrnerdam:BAAANQAECgQJBAAAAA==.',
Ba='Babelfish:BAAANQAECgYJCwAAAA==.Bagleflinger:BAAANQAECgQICAAAAA==.Baldr:BAAANQAECgQJBgAAAA==.Batarang:BAAANQAECgQIDQAAAA==.',
Be='Bealzulbub:BAAANQABCgQIBwAAAA==.Bearbarian:BAAANQAECgYJDwAAAA==.Beastkael:BAAANQAECgMIAwAAAA==.Beg:BAABNQAECoEXAAIDAAgKFRGbPwDpAQADAAgKFRGbPwDpAQAAAA==.Belfalas:BAAANQABCgQIBgAAAA==.Berghain:BAAANQADCgQJAgAAAA==.Berick:BAAANQAECgEIAgAAAA==.Betzalel:BAAANQAECgUICgAAAA==.Beytryx:BAAANQAECgIJAwAAAA==.',
Bl='Bladeoftruth:BAAANQAECgcIEQAAAA==.Blaize:BAAANQADCgMIAwAAAA==.Blitzwing:BAAANQADCggJEwAAAA==.Bloodyaggro:BAAANQADCggJHAAAAA==.',
Bo='Bonnabelle:BAABNQAECoEaAAIDAAgK/AMwZQBCAQADAAgK/AMwZQBCAQAAAA==.Boombawks:BAAANQAECgEIAQAAAA==.Bos:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Bowtoahh:BAAANQABCgEIAQABNQAECgYJEAABAAAAAA==.',
Br='Brewnelle:BAAANQADCggIDgABNQAECgcJFwAEANoaAA==.Briest:BAAANQAECgQIBAABNQAECgcJFwAEANoaAA==.Bruid:BAABNQAECoEXAAMEAAcK2hpJGwDHAQAEAAYKIhlJGwDHAQAFAAcKhRL3NADDAQAAAA==.Bruneigin:BAAANQADCggIGAAAAA==.',
Ca='Calzone:BAAANQADCgYIBgAAAA==.Cambria:BAAANQADCgEIAQABNQAECgIIAwABAAAAAA==.Cardian:BAAANQADCgcIEwAAAA==.Caridin:BAAANQADCgYIEgAAAA==.Carmey:BAAANQAECgMIAwAAAA==.Carrin:BAABNQAECoEmAAICAAcKmx7WNwB1AgACAAcKmx7WNwB1AgAAAA==.Catalyia:BAAANQAECgYIEAAAAA==.Catris:BAAANQADCggJHgAAAA==.Catset:BAAANQAECgYJCgAAAA==.',
Ce='Cecea:BAAANQABCggIEAAAAA==.',
Ch='Charades:BAAANQADCgYIDAAAAA==.Charlton:BAAANQAECgQIBwABNQAECgcIEAABAAAAAA==.Chazzo:BAAANQAECgcIEQAAAA==.Chazzy:BAAANQADCgcIBwAAAA==.Chila:BAAANQADCggIGAAAAA==.',
Co='Commy:BAAANQAECgYICwAAAA==.Concorde:BAAANQAECgQJCAAAAA==.Copiousconns:BAAANQAECgQIDgAAAA==.Corlock:BAAANQADCgYIDAAAAA==.',
Cr='Craitos:BAAANQABCgUJCQAAAA==.Cranjis:BAAANQADCggJCAAAAA==.Crimsonfury:BAAANQADCggIFQAAAA==.',
Cu='Cubos:BAAANQAECggIEQAAAA==.Cutlash:BAAANQADCggIGAAAAA==.Cutslash:BAAANQADCgUJBQABNQADCggIGAABAAAAAA==.',
Cy='Cynaea:BAAANQADCgQJBAABNQAECgcIEAABAAAAAA==.',
Da='Daemona:BAAANQAECgYICwAAAA==.Daieniceis:BAAANQAECgIIBAAAAA==.Dalkurn:BAACNQAFFIEGAAIEAAQK9BlWAwBjAQAEAAQK9BlWAwBjAQA1AAQKgSEAAgQACQrrI+gCAHQDAAQACQrrI+gCAHQDAAAA.',
De='Decayy:BAACNQAFFIEGAAIGAAQKRRjMBwBCAQAGAAQKRRjMBwBCAQA1AAQKgSEAAgYACQqxIvoJADcDAAYACQqxIvoJADcDAAAA.Deceptakahn:BAAANQAECgYJDgAAAA==.Derailedbeef:BAABNQAECoEbAAIHAAgKMxV0TgAxAgAHAAgKMxV0TgAxAgAAAA==.Deydoralia:BAABNQAECoEfAAIIAAgK7B4kGQDGAgAIAAgK7B4kGQDGAgAAAA==.',
Di='Diabeetus:BAAANQADCgQICAAAAA==.',
Dn='Dnme:BAAANQAECgcIEQAAAA==.',
Do='Doneldus:BAAANQADCgYIDQAAAA==.Dool:BAAANQADCgYICwAAAA==.Dorfdragon:BAAANQAECgQIDgAAAA==.Dorfe:BAAANQAECgYJEwAAAA==.',
Dr='Drakona:BAAANQABCgQICAAAAA==.Drakthur:BAAANQADCgUIBwAAAA==.Draximus:BAAANQADCgUIBQAAAA==.Drewgarymore:BAAANQAECgUIDAAAAA==.',
Du='Dukker:BAAANQABCgIJAgAAAA==.Durandall:BAABNQAECoEdAAICAAkK3hn/OwBjAgACAAkK3hn/OwBjAgAAAA==.Durleap:BAAANQADCggJHAAAAA==.Durthmaul:BAAANQADCgYJCwAAAA==.',
Dw='Dwarflock:BAAANQAECgYJCwAAAA==.',
Dy='Dylpickl:BAAANQAFFAIIAgAAAA==.Dylán:BAAANQAECgQIBAAAAA==.Dymàs:BAAANQAECgMIAwAAAA==.',
Ef='Eft:BAAANQABCgQIBAAAAA==.',
El='Elliemae:BAAANQADCgYIBgAAAA==.Elow:BAAANQADCgIIAgAAAA==.',
Er='Erazminash:BAAANQAECgMJBAAAAA==.',
Es='Esdeáth:BAAANQADCgIIAgAAAA==.Esmae:BAAANQADCggJHAAAAA==.Ess:BAAANQADCggJHgAAAA==.',
Ev='Evalina:BAAANQADCgQIBAABNQAECgIIBAABAAAAAA==.Evvie:BAAANQADCggIGAAAAA==.',
Ex='Executiepie:BAAANQADCggICAAAAA==.',
Fa='Fabulosoo:BAAANQAECgQIDgAAAA==.Fantarius:BAABNQAECoEgAAIDAAkKdx/gJwBiAgADAAkKdx/gJwBiAgAAAA==.Fatdono:BAAANQAECgYJCwAAAA==.',
Fi='Fibbs:BAAANQAECgQICgAAAA==.Fikti:BAAANQAECgYIEwAAAA==.Firetongue:BAAANQADCgUJBQAAAA==.Firocios:BAAANQAECgUICQAAAA==.',
Fl='Flaminia:BAAANQADCgUICQAAAA==.',
Fo='Fossilz:BAAANQADCggJCAAAAA==.Foxybeans:BAAANQADCgYICgAAAA==.',
Fr='Fran:BAAANQAECgUICQAAAA==.Frieda:BAAANQABCgIIAgAAAA==.Frink:BAAANQADCggJGgAAAA==.Frostyfella:BAABNQAECoEbAAIJAAkKix35OwDYAgAJAAkKix35OwDYAgABNQABCgIIAgABAAAAAA==.',
Fu='Furman:BAAANQADCgMIAwAAAA==.',
['Fá']='Fáith:BAAANQADCggIEAAAAA==.',
Ga='Garypotter:BAAANQAECgUICwAAAA==.Gazooks:BAAANQADCgMIAwAAAA==.',
Ge='Gelantria:BAAANQADCgcIBwAAAA==.',
Gi='Gillacs:BAAANQADCgMJAwAAAA==.',
Gl='Gleave:BAAANQAECgYIDQAAAA==.',
Go='Goodbrew:BAAANQAECgMJBAAAAA==.',
Gr='Greystoke:BAAANQADCgQIBAAAAA==.Greyvee:BAAANQAECgIJBAAAAA==.Grindelbald:BAAANQAECgcJEgAAAA==.',
Gt='Gtfofupá:BAAANQADCgcJGAAAAA==.',
Gu='Gushee:BAAANQAECgQIEAAAAA==.',
Gw='Gwenn:BAAANQADCgYIEgAAAA==.',
Gy='Gyes:BAAANQAECgIIAgAAAA==.',
Ha='Hadez:BAAANQADCgcICwAAAA==.Haegan:BAAANQABCgYIBwAAAA==.Hagioszoe:BAAANQAECgQJCAAAAA==.Hairypoóter:BAAANQADCgUICQAAAA==.Hanamari:BAABNQAECoEYAAMKAAkKEBaSEwA+AgAKAAkKEBaSEwA+AgALAAEK6wEnPgAdAAAAAA==.Hanoe:BAAANQABCgEIAQAAAA==.Harakrron:BAAANQADCgUICgAAAA==.Harleyquìnn:BAAANQADCgYIDwAAAA==.Harydresden:BAAANQAECgUICQAAAA==.Hawkesmage:BAAANQADCgMIAwAAAA==.Hawkslayer:BAAANQADCggJFwAAAA==.Hazule:BAAANQAECgIIAwABNQAECgYICwABAAAAAA==.',
He='Hedgelord:BAABNQAECoEbAAIFAAgKHh/XGACxAgAFAAgKHh/XGACxAgAAAA==.',
Hi='Hisky:BAAANQAECgQIBgAAAA==.',
Ho='Hobe:BAAANQAECgcIEgAAAA==.Holytruck:BAAANQADCgEIAQAAAA==.Hoodmagik:BAAANQABCgYIBwABNQAECggJDgABAAAAAA==.Hornadus:BAAANQADCgMIAwAAAA==.Hornride:BAAANQADCgMIAwAAAA==.',
Hu='Humoresque:BAAANQADCggJGQAAAA==.Huntaredead:BAAANQAECgQJBgABNQAECggIHgAMAIgiAA==.',
Ic='Icyblades:BAAANQAECgUJCQAAAA==.',
Il='Ilidania:BAAANQADCgYIBgABNQAECgIIBAABAAAAAA==.Ilyna:BAAANQAECgUICgAAAA==.',
Im='Immortalnut:BAAANQAECgYIEAAAAA==.',
In='Inori:BAAANQADCgcIBwAAAA==.Interrupted:BAAANQAECgIIAgAAAA==.',
It='Itscell:BAAANQADCgEIAQAAAA==.',
Ja='Jaedis:BAAANQAECgQJBAAAAA==.Jaktar:BAAANQAECgcIDwAAAA==.Jane:BAAANQADCgMIAgAAAA==.Janet:BAAANQAECgcIEwAAAA==.Jani:BAAANQADCgQIBAABNQAECgcIEwABAAAAAA==.Janiina:BAAANQADCgYIDQAAAA==.',
Je='Jezak:BAAANQADCgIIAgABNQAECgQJBgABAAAAAA==.',
Jo='Jol:BAAANQABCgQIBAAAAA==.Jone:BAAANQADCggJHAAAAA==.Joobs:BAAANQAECgUJCAAAAA==.Joosh:BAAANQAECgUIBQAAAA==.',
Js='Jslice:BAABNQAECoEXAAIHAAkKkB9RJwDSAgAHAAkKkB9RJwDSAgAAAA==.',
Ju='Juda:BAAANQAECgEJAQAAAA==.Jurant:BAAANQABCgQJAwAAAA==.Jurucil:BAAANQAECgEIAQAAAA==.',
Ka='Kaelys:BAAANQAECgQICAAAAA==.Kahliea:BAAANQADCggJHgAAAA==.Kaidance:BAAANQAECgEJAQAAAA==.Kaisaze:BAAANQADCggIGAAAAA==.Kapachka:BAAANQADCggIFQAAAA==.Karbide:BAAANQADCgQIBQAAAA==.Kardisa:BAAANQABCgIJAgAAAA==.Kateri:BAAANQADCgcJHQAAAA==.Katmarie:BAAANQAECgIJAgAAAA==.Kazothor:BAAANQADCggJHgAAAA==.',
Ke='Keria:BAACNQAFFIEMAAINAAYKUB9UAQA5AgANAAYKUB9UAQA5AgA1AAQKgSkAAg0ACQqJJS0BAN4DAA0ACQqJJS0BAN4DAAAA.Keyz:BAAANQAECgQIBQAAAA==.',
Ki='Kiretsu:BAAANQAECgcIEAAAAA==.',
Ko='Kovus:BAAANQADCggIGAAAAA==.',
Kr='Kragami:BAAANQADCggJEAAAAA==.Krelien:BAAANQAECgQIBwAAAA==.Krispee:BAAANQAECgUIBwAAAA==.Kristanya:BAAANQAECgUJDgAAAA==.',
Ku='Kulaidmage:BAAANQAECgUJCwAAAA==.Kurtcowbain:BAAANQAECgUJDAAAAA==.',
Ky='Kynetik:BAAANQAECggICAABNQAECgkJIQAOAOgWAA==.Kyttin:BAAANQADCggICAAAAA==.',
La='Ladamirea:BAAANQAECgcJEwAAAA==.Lamashtu:BAAANQAECgUICgAAAA==.Lashar:BAAANQADCgYIBgAAAA==.Layssar:BAAANQADCgUJBQAAAA==.',
Le='Leiman:BAAANQABCgQIBQAAAA==.Lenabug:BAAANQABCgIIAgAAAA==.Lexiê:BAAANQAECgQICAAAAA==.',
Li='Lilifa:BAAANQAECgQICgAAAA==.Lilillidari:BAABNQAECoEYAAINAAgKgBwYEgCyAgANAAgKgBwYEgCyAgABNQAFFAQJBwAPABYPAA==.Lillirann:BAAANQAECgEIAQAAAA==.Lilmontaro:BAACNQAFFIEHAAMPAAQKFg+1BQD6AAAPAAMK5hG1BQD6AAAGAAEKpwYOIwAgAAA1AAQKgSkAAw8ACQomJnkGAEgDAA8ACQq8InkGAEgDABAACAqkIKATANQCAAAA.Lilunholy:BAAANQAECgYICAABNQAFFAQJBwAPABYPAA==.Linali:BAAANQADCgcJBwAAAA==.Lirianna:BAAANQADCgMIAwAAAA==.Littany:BAAANQAECgcIEwAAAA==.Livane:BAAANQAECgMIBQAAAA==.',
Lo='Loestus:BAAANQADCgQIBAAAAA==.Lowground:BAAANQADCgIIAgAAAA==.',
Lu='Lucïna:BAAANQAECgQICgAAAA==.Ludk:BAAANQAECgUJDgAAAA==.Luk:BAAANQAECgcIEwABNQAECgYIBwABAAAAAA==.Lumiela:BAAANQAECgEJAQAAAA==.Luminah:BAAANQAECgIJAgAAAA==.Lunacy:BAAANQADCgYICgAAAA==.Luni:BAAANQADCgQIBgAAAA==.Lunì:BAAANQADCgQIBAABNQADCgQIBgABAAAAAA==.',
['Ló']='Lóner:BAAANQAECgUIBwABNQAECgYIEQABAAAAAA==.',
Ma='Macbayne:BAAANQADCgEIAQAAAA==.Maebe:BAAANQAECgQIBQAAAA==.Mageblaster:BAAANQADCgYICgAAAA==.Maggnut:BAABNQAECoEXAAIHAAgKhg82XwD1AQAHAAgKhg82XwD1AQAAAA==.Magicg:BAABNQAECoEWAAMRAAkKpBgvDQDOAgARAAkKpBgvDQDOAgADAAEKpgpMpwA+AAAAAA==.Magordito:BAAANQAECgYIEQAAAA==.Mairek:BAABNQAECoEiAAIJAAgK3B0STgChAgAJAAgK3B0STgChAgAAAA==.Maleigoron:BAAANQAECgcIEgAAAA==.Malkuri:BAAANQAECgYIDgABNQAECgcIEQABAAAAAA==.Malorysera:BAAANQAFFAIJAgAAAA==.Matsuma:BAAANQAECgEIAQAAAA==.',
Mc='Mcbasketball:BAAANQAECgIIAgAAAA==.',
Me='Mechaljaxon:BAAANQAECgUJCQAAAA==.Menirva:BAAANQAECgcIEQAAAA==.Merv:BAAANQAECgUIBgAAAA==.Metapal:BAAANQAECgcIEgABNQAECgkJIQAOAOgWAA==.Metasham:BAABNQAECoEhAAIOAAkK6BafJQCKAgAOAAkK6BafJQCKAgAAAA==.',
Mi='Miiaa:BAAANQAECgYJDAAAAA==.Mijoy:BAAANQAECgQIBAAAAA==.Milane:BAAANQADCgYJFAAAAA==.',
Mo='Moirasha:BAAANQAECgMJBgAAAA==.Monran:BAAANQAECgQIBQAAAA==.Moonwood:BAAANQADCgYIBgAAAA==.Moosand:BAAANQAECgQJBgAAAA==.Morphingtime:BAAANQAECgQICgAAAA==.Mortivus:BAAANQADCggIGAAAAA==.',
Mu='Muggs:BAAANQADCggJCAAAAA==.Mulvane:BAAANQADCggIGAAAAA==.Mustachio:BAAANQAECgMJBgAAAA==.',
Mw='Mwc:BAACNQAFFIEMAAMSAAYKzhbhAgDOAQASAAUK3hPhAgDOAQATAAIK6RcRBwCzAAA1AAQKgRYAAxIACQoFJa0CAHEDABIACQoFJa0CAHEDABMABAp3Fu43AB0BAAAA.',
Mz='Mziao:BAAANQADCggIFQAAAA==.',
Na='Nazureshal:BAAANQADCggICAABNQAECgUIDQABAAAAAA==.',
Ne='Neall:BAAANQAECgMJAwAAAA==.Ner:BAAANQADCgEIAQAAAA==.Nevets:BAAANQAECgEJAgAAAA==.',
Ni='Nightbird:BAAANQADCggIDwAAAA==.',
No='Nonna:BAAANQAECgUJDgAAAA==.Noslrac:BAAANQADCggIFgAAAA==.Notbysight:BAAANQADCgYIBgAAAA==.Notorious:BAAANQAECggIGgAAAQ==.',
Ny='Nyxjr:BAAANQADCgIJAgAAAA==.',
Ob='Oblast:BAABNQAECoEjAAIJAAkKXCNiDACSAwAJAAkKXCNiDACSAwAAAA==.',
Od='Odb:BAAANQADCgQIBAAAAA==.Odirtyblasta:BAAANQADCgYIBgAAAA==.',
Ol='Olmanjankins:BAAANQAECgQJCAAAAA==.',
On='Onlydks:BAAANQAECgcIBgABNQAFFAEIAQABAAAAAA==.Onlyslams:BAAANQAFFAEIAQAAAA==.',
Oo='Ooze:BAAANQADCgMIAwAAAA==.',
Or='Orter:BAAANQAECgMJCQAAAA==.',
Ot='Ottan:BAAANQADCgYICwAAAA==.',
Ov='Overkill:BAAANQAECgMIAwAAAA==.',
Pa='Pandorasfox:BAAANQADCgcIBwAAAA==.Papsfear:BAAANQAECgYJEAAAAA==.Parceh:BAAANQAECgUJDgAAAA==.',
Ph='Phydaux:BAAANQADCggIEwAAAA==.',
Pi='Pinkponyclub:BAAANQADCggICAAAAA==.Pizzaman:BAAANQAECgIIAwAAAA==.',
Pr='Pringle:BAAANQADCgYIEgABNQAECgQIBQABAAAAAA==.Prosciutto:BAAANQAECgQJBwAAAA==.Proxima:BAAANQADCggJEQAAAA==.',
Pt='Ptoughneigh:BAAANQAECgQIBAAAAA==.',
Pu='Puckish:BAABNQAECoEfAAMDAAkK0wxVQgDbAQADAAkK0wxVQgDbAQAUAAEKvAEGIQAkAAAAAA==.Punn:BAAANQAECgcIDAABNQAECggIHgAMAIgiAA==.Punnisher:BAABNQAECoEeAAMMAAgKiCKVDgAYAwAMAAgKiCKVDgAYAwAVAAEKvhv6WQBKAAAAAA==.Pureflow:BAAANQAECgMJBgAAAA==.',
['Pä']='Päiñ:BAAANQADCgUIBQAAAA==.',
Qu='Quackers:BAAANQAECgMJAwAAAA==.Quicks:BAAANQAECgcIEgAAAA==.',
Ra='Raelianna:BAAANQADCggJGgABNQAECgcIHgAJAH0lAA==.Raewyna:BAAANQAECgQIBQAAAA==.Raine:BAAANQAECgYJBwAAAA==.Rainingblood:BAAANQAECgIJAgAAAA==.Rainjar:BAAANQAECgIIAgAAAA==.Rancîd:BAAANQAECgYICwAAAA==.Ranron:BAAANQADCgQIBwABNQAECgYICwABAAAAAA==.Raphael:BAAANQAECgUICQAAAA==.Rasik:BAAANQAECgUJDgAAAA==.Rastafareye:BAAANQADCgYIBgAAAA==.Ravenblood:BAAANQADCggIDQAAAA==.Rayel:BAAANQAECgIJBQAAAA==.Raylyn:BAAANQADCgQIBQAAAA==.',
Rh='Rhadamancus:BAAANQAECgIIAwAAAA==.Rhani:BAAANQAECgQIBQAAAA==.Rheanon:BAAANQADCgYJEAAAAA==.Rhome:BAABNQAECoEcAAIDAAgKLSC7EgDqAgADAAgKLSC7EgDqAgAAAA==.Rhox:BAAANQADCggJEQAAAA==.',
Ri='Rialu:BAAANQAECgYJEwAAAA==.Ribald:BAAANQAECgQIBAAAAA==.Rickgrimes:BAABNQAECoEYAAMPAAgKPB4GFAB8AgAPAAgKKBoGFAB8AgAQAAcKSRwXKQAfAgAAAA==.',
Ro='Roid:BAABNQAECoEgAAMIAAkKLw56NgAgAgAIAAkKLw56NgAgAgACAAIKawI8CwFFAAAAAA==.Rotcorpse:BAAANQAECgcICAAAAA==.',
Ru='Ruddam:BAAANQADCggJGwAAAA==.',
['Rä']='Räveñz:BAAANQAECgUICgAAAA==.',
Sa='Saintabes:BAAANQAFFAIIAgAAAA==.Sakurah:BAAANQAECgMJBgAAAA==.Samelan:BAAANQABCggIEAAAAA==.Sandara:BAAANQADCgMIAwAAAA==.Sanicor:BAAANQADCggICAAAAA==.Sanrinn:BAAANQAECgEIAQAAAA==.Sappy:BAAANQAECgEIAQAAAA==.Sarahboom:BAABNQAECoEbAAIJAAkKqQ4mawBQAgAJAAkKqQ4mawBQAgAAAA==.Sarahjupiter:BAAANQAECgQIBAABNQAECgkJGwAJAKkOAA==.Sargarach:BAAANQADCgEIAQAAAA==.',
Sc='Scapegoat:BAEANQAECgQJDQAAAQ==.Scraime:BAAANQADCgcIBwAAAA==.',
Se='Seekýefirst:BAAANQADCgcIBwAAAA==.Seethe:BAAANQADCgYIBgAAAA==.Seilah:BAAANQAECgQJBQAAAA==.Seliah:BAAANQAECgQICgAAAA==.Seräph:BAAANQAECgEIAQAAAA==.',
Sh='Shadowglade:BAAANQAECgUJDgAAAA==.Shadowmourne:BAAANQABCgIIAgAAAA==.Shalltear:BAAANQADCggJGwAAAA==.Shamizzle:BAAANQAECgYJDgAAAA==.Shammydavis:BAAANQAECgUICQAAAA==.Shaølinstørm:BAAANQADCgMIAwAAAA==.Shiftybud:BAAANQADCgQICwAAAA==.Shinobi:BAAANQAECgEIAQAAAA==.Shocknorris:BAAANQADCgUIBQAAAA==.Shrapnel:BAAANQAECgUICQAAAA==.Shàmwôw:BAAANQADCgYIBAAAAA==.Shàytan:BAAANQAECgUICgAAAA==.',
Si='Sinistral:BAAANQAECgIIAgAAAA==.',
Sl='Slise:BAAANQADCgIIAwAAAA==.',
Sm='Smithers:BAAANQAECgQICQAAAA==.',
Sn='Snappycakes:BAAANQAECgEIAQAAAA==.Sneakybunny:BAAANQAECgUJDgAAAA==.',
So='Solómon:BAAANQAECgEIAQAAAA==.Sorabjr:BAAANQADCgcJEwAAAA==.Sorin:BAAANQADCgYIBgABNQAECgcICwABAAAAAA==.Soulbreaker:BAAANQAECgQIDgAAAA==.Southy:BAAANQAECgUICgAAAA==.',
Sp='Sparxs:BAAANQADCgMIAwAAAA==.Spookz:BAAANQADCgIJAgAAAA==.',
St='Starblunder:BAAANQADCgUICgAAAA==.Stormdeth:BAAANQADCgMIAwAAAA==.Stormmystic:BAAANQAECgIIAgAAAA==.Stormwild:BAAANQADCgUJBQABNQAECgIIAgABAAAAAA==.Stylemonk:BAACNQAFFIENAAIKAAUKBSOuAQAOAgAKAAUKBSOuAQAOAgA1AAQKgR4AAgoACAp4JnUDAH8DAAoACAp4JnUDAH8DAAAA.',
Su='Sulfalloway:BAAANQAECgMIAwAAAA==.Sumawfulot:BAAANQAECgYICwAAAA==.Sunsparrow:BAAANQAECgIIAgAAAA==.',
Sw='Swankdave:BAAANQADCgcIBwAAAA==.',
Sy='Syraelia:BAAANQADCggJCAAAAA==.Syvarris:BAABNQAECoEYAAQWAAgKExzeAgCMAgAWAAcKmh3eAgCMAgAXAAUKXwlDNAALAQAYAAEKZRHn5QBMAAAAAA==.',
Ta='Taeveren:BAAANQADCgIIAgAAAA==.Tamesßond:BAAANQADCggJFwAAAA==.Tandaiff:BAAANQADCgYIBgAAAA==.Tanguo:BAAANQADCgcIBwAAAA==.Tanksnotanks:BAAANQADCgYJFAAAAA==.Tanleron:BAAANQADCgMIAwAAAA==.Tarayn:BAAANQAECgQIDgAAAA==.',
Te='Teagan:BAAANQADCgYIEwAAAA==.Tenac:BAAANQADCggIDgAAAA==.Teoritta:BAEANQAECgQIDgAAAA==.Terllin:BAAANQADCgQIBAAAAA==.',
Th='Thalimus:BAAANQADCgYICgAAAA==.Thelle:BAAANQAECgYICwABNQAFFAYIDAANAFAfAA==.Thewhitelion:BAAANQADCggIHAAAAA==.',
Ti='Tigg:BAABNQAECoEgAAMPAAkKkCARCwD3AgAPAAkKKiARCwD3AgAQAAEKSCPeiABHAAAAAA==.Tikifiki:BAAANQAECgUJCgAAAA==.',
To='Tokin:BAAANQADCgYICgAAAA==.Toochill:BAAANQADCgEIAQAAAA==.Toodoo:BAAANQADCgIJAgABNQAECgYICwABAAAAAA==.Toshidot:BAABNQAECoEbAAIMAAkKqiA2DQAjAwAMAAkKqiA2DQAjAwAAAA==.Totemtila:BAAANQAECgEIAQABNQAECgcIFgAVAOcjAA==.',
Tr='Translucent:BAAANQAECgcIEwAAAA==.Trazatra:BAAANQAECgcIEAAAAA==.Truckah:BAAANQAECgQJBwAAAA==.Tràvdog:BAAANQAECgUICgAAAA==.',
Tu='Tunalongarms:BAAANQAECgIIBAAAAA==.Tuonadari:BAAANQADCgUJCAAAAA==.Tuonai:BAAANQAECgUICQAAAA==.Tusknus:BAAANQAECgIIAgAAAA==.',
Ty='Tylordis:BAAANQADCgYICgAAAA==.',
['Tý']='Týr:BAAANQABCgcICQAAAA==.',
Us='Usodead:BAAANQADCgQIBAAAAA==.Usosquishy:BAAANQAECgcIEgAAAA==.',
Va='Vader:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.Valkuridk:BAACNQAFFIEJAAIPAAUK1CHKAAD9AQAPAAUK1CHKAAD9AQA1AAQKgSIAAw8ACQqaJrkAAOkDAA8ACQqIJrkAAOkDABAACAoqJqQMACIDAAAA.Vandy:BAABNQAECoEcAAMDAAgKMReUMgApAgADAAgKExWUMgApAgAUAAQKqRaYDAAQAQAAAA==.',
Ve='Vedo:BAAANQAECgcIEgAAAA==.Vedora:BAAANQAECgYICwAAAA==.Velf:BAAANQADCgEIAQAAAA==.Veradis:BAAANQADCgYIEgAAAA==.Vestiege:BAAANQABCgYIBwAAAA==.',
Vi='Vinland:BAAANQADCgYJEgAAAA==.Vinsmokesanj:BAAANQADCgQIBAAAAA==.Virulent:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Vissarion:BAAANQADCgYIEgAAAA==.',
Vl='Vladak:BAAANQAECgUIDAAAAA==.',
Vo='Voc:BAAANQAECgcIEQAAAA==.Voz:BAAANQAECgIIAgAAAA==.',
Vu='Vulkin:BAAANQAECgIIAwAAAA==.',
Vv='Vv:BAAANQAECgcIEwAAAA==.',
Vy='Vyridiondk:BAAANQADCggJEwAAAA==.Vyx:BAAANQADCggIDwAAAA==.',
Wa='Waggi:BAAANQAECgQIBQAAAA==.Waymán:BAAANQADCgcIEAAAAA==.',
We='Weebjones:BAAANQADCgQIBAAAAA==.Weelilcurse:BAAANQADCggICAAAAA==.Wegberto:BAAANQADCggICAAAAA==.',
Wu='Wumply:BAABNQAECoEcAAIRAAkKVBDNFQBFAgARAAkKVBDNFQBFAgAAAA==.',
['Wà']='Wàyman:BAAANQADCgUIBwAAAA==.',
['Wä']='Wäyman:BAAANQAECgUJDgAAAA==.',
Xa='Xaranthia:BAAANQAECgYICgAAAA==.',
Xm='Xmcdizzle:BAAANQAECgMIBgAAAA==.',
Xy='Xylarra:BAAANQAECgUJDgAAAA==.',
Ya='Yautja:BAAANQAECgYJEAAAAA==.Yazule:BAAANQAECgYICwAAAA==.',
Yo='Yodawg:BAAANQAECgUICQABNQAECgcIEAABAAAAAA==.Yoruba:BAAANQADCgMIAwABNQAECgUICAABAAAAAA==.',
Za='Zairroth:BAAANQABCgYIBgAAAA==.Zamali:BAAANQAECgUICgAAAA==.Zantris:BAAANQADCgUIBwABNQAECgQIBQABAAAAAA==.Zartella:BAAANQAECgQIBQABNQAECgYJCwABAAAAAA==.Zaxon:BAAANQADCgcIDQAAAA==.',
Ze='Zendraza:BAAANQAECgUJCwAAAA==.Zephyrion:BAABNQAECoEhAAIGAAkKYxgvGQCPAgAGAAkKYxgvGQCPAgABNQAECgQIBAABAAAAAA==.Zepplin:BAAANQAECgUJCwAAAA==.Zerenity:BAAANQADCgcICgAAAA==.Zetro:BAAANQAECgYIEQAAAA==.',
Zr='Zreydyn:BAAANQADCgYIDgAAAA==.',
Zu='Zuma:BAAANQAECgUJCAAAAA==.Zuraxxus:BAAANQABCgMIAwAAAA==.',
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
