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

local lookup = {'Unknown-Unknown','Hunter-Marksmanship','Priest-Holy','Druid-Restoration','Warrior-Arms','Druid-Balance','Paladin-Retribution',}
local provider = {region='US',realm='EarthenRing',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abrothael:BAAANQADCggIFwAAAA==.',
Ad='Adorèè:BAAANQAECgEIAQAAAA==.',
Ae='Aedelas:BAAANQADCgQIBAAAAA==.Aestua:BAAANQADCgMIBQAAAA==.Aetheros:BAAANQAECgcIDAAAAA==.',
Ag='Agarim:BAAANQADCgQIBAAAAA==.',
Ai='Airlinna:BAAANQAECgcICwAAAA==.Airoach:BAAANQADCggIEwAAAA==.',
Ak='Akers:BAAANQADCggICwABNQAECgEIAQABAAAAAA==.',
Al='Alaraen:BAAANQAECgMIAgAAAA==.Alcremie:BAAANQAECgIIAgABNQAFFAUIBwACAFYSAA==.Aleman:BAAANQADCgYICgAAAA==.Aleve:BAAANQADCgIIAgAAAA==.Alexxandria:BAAANQADCggICAAAAA==.Aleyah:BAAANQADCggIFgAAAA==.Almarii:BAAANQAECgIIAgAAAA==.Alraune:BAAANQAECgUIBQAAAA==.Alynndra:BAAANQAECgIIAgAAAA==.Alyssazoe:BAAANQADCgIIBAAAAA==.',
An='Anarionhunts:BAAANQAECgIIAgAAAA==.Andius:BAAANQADCgYIDQAAAA==.Andoric:BAAANQABCgYICAAAAA==.Anirra:BAAANQAECgIIAgAAAA==.',
Ap='Apert:BAAANQAECgIIAgAAAA==.Apnea:BAAANQADCgIIAgAAAA==.',
Ar='Ardenweald:BAAANQAECgYICwAAAA==.Armyokittens:BAAANQADCgYIDgAAAA==.Arroezze:BAAANQADCgYIBQAAAA==.Arthurin:BAAANQAECgEIAQAAAA==.',
As='Ashaleth:BAAANQADCgUIBQAAAA==.Ashayo:BAAANQADCgYICQAAAA==.Astrana:BAAANQAECgQIBQAAAA==.',
At='Athelstan:BAAANQADCgcIBwAAAA==.',
Au='Augkward:BAAANQADCgYIBQABNQAECgkJGAADAIsaAA==.Aureldor:BAAANQADCgMIAwAAAA==.Automatic:BAAANQAECgYICwAAAA==.Autoshot:BAAANQADCgMIBAAAAA==.',
Av='Avorik:BAAANQADCggICQAAAA==.',
Az='Azaree:BAAANQAECgIIAgAAAA==.Azndak:BAAANQADCgcIBwAAAA==.',
Ba='Baelzabob:BAAANQADCgUICwAAAA==.Bakaran:BAAANQADCgUIBQAAAA==.Barae:BAAANQADCgYIDQAAAA==.Barboosa:BAAANQADCgcIBwAAAA==.Barcmaul:BAAANQADCgcIEQAAAA==.Bathzalts:BAAANQADCgYIBQAAAA==.Baylel:BAAANQAECgIIAgAAAA==.',
Be='Belledolphin:BAAANQAECgUIBQAAAA==.Bellgold:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Berigo:BAAANQAECgUICQAAAA==.Bertoxulous:BAAANQADCgUIBQAAAA==.Bezvoker:BAAANQAECgIIAwAAAA==.Beárwithme:BAAANQADCgQICAAAAA==.',
Bi='Birria:BAAANQADCgQIBAAAAA==.',
Bj='Bjordrann:BAAANQADCgEIAQAAAA==.',
Bl='Blackicewolf:BAAANQAECgcIDAAAAA==.Bleake:BAAANQADCgUIBQAAAA==.Bleunienn:BAAANQABCgQIBgAAAA==.Blueberrypie:BAAANQAECgMIAwAAAA==.',
Bo='Bonbarrion:BAEANQAECgYICwAAAA==.Borbory:BAAANQAECgEIAQAAAA==.Boringhuman:BAAANQADCgcICgAAAA==.Borogove:BAAANQADCgYIBgAAAA==.',
Br='Brasca:BAAANQAECgIIAgAAAA==.Brisketdk:BAAANQADCggIDAAAAA==.Bruhmal:BAAANQAECgEIAQAAAA==.Brunner:BAAANQADCgEIAQAAAA==.Brynndolin:BAAANQAECgIIAgAAAA==.',
Bu='Burzolog:BAAANQAECgYICgAAAA==.',
['Bä']='Bärk:BAAANQAECgYIEAAAAA==.',
Ca='Calanash:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Calazan:BAAANQAECgQIBAAAAA==.Cascious:BAAANQADCgcIBwABNQAECgkJFwAEAEIUAA==.',
Ce='Cedarjr:BAAANQADCgcIDwAAAA==.Cef:BAAANQAECgEIAQAAAA==.Celindre:BAAANQADCgQIBQAAAA==.',
Ch='Chewbie:BAAANQAECgEIAQAAAA==.',
Ci='Ciphon:BAAANQADCgUICwAAAA==.Cirok:BAAANQADCgcIDQAAAA==.Civic:BAAANQADCggICQAAAA==.',
Ck='Cklyde:BAAANQAECgcIDAAAAA==.',
Cl='Claiyre:BAAANQADCgcICgAAAA==.Clewis:BAAANQABCgUICAAAAA==.Clubble:BAAANQAECgEIAQAAAA==.Clumperton:BAAANQAECgcIDQAAAA==.Clãsh:BAAANQAECgIIAgAAAA==.',
Co='Cochino:BAAANQADCgYIBgAAAA==.Concentrate:BAAANQAECgQIBQAAAQ==.Connan:BAAANQADCgUIBwABNQAECgQIBwABAAAAAA==.Constant:BAAANQADCgIIAgAAAA==.Corbesan:BAAANQADCgcIBwABNQADCggIDAABAAAAAA==.Cordrann:BAAANQADCgYICwAAAA==.Coveness:BAAANQADCgEIAQAAAA==.Cowi:BAAANQAECggICQAAAA==.',
Cr='Crasusakechi:BAAANQADCgUIBQAAAA==.Cryomagus:BAAANQAECgcICwAAAA==.',
Cu='Cuqquiform:BAAANQAECgQIDAABNQAECgUICQABAAAAAA==.',
Cy='Cylesia:BAAANQADCgcICwAAAA==.Cylthia:BAAANQADCgIIAgAAAA==.',
Da='Daemata:BAAANQAECgEIAQAAAA==.Dajinbo:BAAANQADCgcIDQAAAA==.Darchlo:BAAANQADCgEIAQAAAA==.Darkhammer:BAAANQADCgYIBgAAAA==.Darkswift:BAAANQAECgcIDAAAAA==.Darnadda:BAAANQADCgcIDgAAAA==.Darowyn:BAAANQAECgEIAQAAAA==.Dashiell:BAAANQADCgQIBwABNQADCggIDAABAAAAAA==.Dawnflare:BAAANQADCgcIDQABNQAECgMIAwABAAAAAA==.',
De='Deaxus:BAAANQAECgMIAwABNQAECgYICgABAAAAAA==.Deb:BAAANQAECgIIAgAAAA==.Delbelfine:BAAANQAECgcIDAAAAA==.Delfar:BAAANQADCgUIBQAAAA==.Delisomethng:BAAANQAECgMIAwAAAA==.Dellechero:BAAANQADCgYIDAAAAA==.Demilich:BAAANQADCgIIAgAAAA==.Demonra:BAAANQADCgMIAwAAAA==.Dethyler:BAAANQAECgEIAQAAAA==.Devilwoman:BAAANQAECgEIAgAAAA==.Deyv:BAAANQAECgEIAQAAAA==.',
Di='Diancie:BAAANQAECgIIAgABNQAFFAUIBwACAFYSAA==.Diddibeau:BAAANQAECgIIAgAAAA==.Diddiblind:BAAANQADCgMIBgABNQAECgIIAgABAAAAAA==.Diego:BAAANQADCgEIAQAAAA==.Divinezanon:BAAANQAFFAEIAQABNQAECggICAABAAAAAA==.',
Do='Doobu:BAAANQADCgYICwAAAA==.Dooganitis:BAAANQAECgEIAQAAAA==.Doruk:BAAANQADCgcICQAAAA==.',
Dr='Dreamsoul:BAAANQABCgQIBAAAAA==.Drfeelgreat:BAAANQADCgIIAwAAAA==.',
Du='Dullahstrasz:BAAANQADCgYIBgAAAA==.Dusksorrow:BAAANQADCgUIBQAAAA==.',
Dz='Dzud:BAAANQABCgIIAgAAAA==.',
Ed='Edovard:BAAANQADCgYIDAAAAA==.',
Ee='Ee:BAAANQADCgcIDAAAAA==.Eeragon:BAAANQADCgUICQAAAA==.',
El='Elentari:BAAANQABCgMIAwAAAA==.Elfshadow:BAAANQABCgQIAwAAAA==.Eliyon:BAAANQADCgcIEQAAAA==.Ellarinya:BAAANQADCgMIBQAAAA==.Ellemir:BAAANQADCgYIDQAAAA==.Eltanari:BAAANQADCgYIDAAAAA==.Eluera:BAAANQADCgcICAAAAA==.Elyn:BAAANQAECgcICgAAAA==.',
Em='Emet:BAAANQABCgIIAgAAAA==.Emunny:BAAANQAECgIIAgAAAA==.',
En='Endest:BAAANQAECgEIAQAAAA==.Enezalle:BAAANQAECgEIAQAAAA==.',
Eo='Eointhas:BAAANQAECgIIAgAAAA==.',
Ep='Ephimonk:BAAANQAECgEIAQAAAA==.',
Er='Ernson:BAAANQADCgMIBAAAAA==.',
Eu='Euronymous:BAAANQAECgEIAQAAAA==.',
Ev='Evilandy:BAAANQAECgIIAgAAAA==.',
Fa='Faeleda:BAAANQADCgEIAQAAAA==.Fandrall:BAAANQADCgIIAwAAAA==.',
Fb='Fblthp:BAAANQAECgMIAgAAAA==.',
Fe='Felblood:BAAANQADCgYIDAAAAA==.Fezduin:BAAANQADCgIIAgAAAA==.',
Fi='Finnagetit:BAAANQAECgEIAQAAAA==.',
Fl='Flagonslayer:BAAANQADCggIDgAAAA==.Flaimefu:BAAANQADCgYIEAAAAA==.Floorlicker:BAAANQADCgYIBgAAAA==.Flopsie:BAAANQAECgMIAgAAAA==.Fluffystorm:BAAANQADCgYIDQAAAA==.',
Fo='Forzod:BAAANQADCgYICAAAAA==.Forzzie:BAAANQADCgUIBAAAAA==.Foxymagic:BAAANQADCgcICgAAAA==.',
Fr='Frabjous:BAAANQAECgIIAgAAAA==.Freenk:BAAANQADCgcIDQAAAA==.Freezerburn:BAAANQAECgcIDAAAAA==.',
Fu='Furn:BAAANQAECgIIAgAAAA==.Furryaz:BAAANQADCgIIAgAAAA==.Further:BAAANQAECgcIDAAAAA==.',
Fy='Fyrrek:BAAANQADCgYICgAAAA==.',
Ga='Galadrien:BAAANQADCgYIBgAAAA==.Galavenat:BAAANQAECgEIAQAAAA==.Garbohydrate:BAAANQADCgEIAQAAAA==.Garbolicious:BAAANQADCgEIAQAAAA==.Garbothicc:BAAANQAECgIIAgAAAA==.Garyh:BAACNQAFFIEHAAIFAAUJAxqYAQDaAQAFAAUJAxqYAQDaAQA1AAQKgRsAAgUACQnzJZgBANgDAAUACQnzJZgBANgDAAAA.Garyhreturns:BAAANQAECgUIBgABNQAFFAUIBwAFAAMaAA==.',
Ge='Geldeinmonch:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Geldverdamnt:BAAANQAECgEIAQAAAA==.',
Gh='Ghost:BAAANQABCgQIBgAAAA==.Ghuramonk:BAAANQADCggICgAAAA==.',
Gi='Giacomo:BAAANQADCgUIBgAAAA==.Gil:BAAANQAECgIIAgAAAA==.Gildina:BAAANQADCgYIDgAAAA==.Ginggy:BAAANQAECgQIBQABNQAECgkJFwAEAEIUAA==.Girafficz:BAABNQAECoEaAAIGAAkJ2iTBAADZAwAGAAkJ2iTBAADZAwABNQAFFAYICwAFAHMkAA==.',
Go='Gori:BAAANQAECgIIAgAAAA==.Gorin:BAAANQADCggIDAAAAA==.',
Gr='Graelle:BAAANQADCgYIBgAAAA==.Gralle:BAAANQAECgQIBAAAAA==.Graug:BAAANQADCgQIBAABNQADCgMIAwABAAAAAA==.Gravelbeard:BAAANQADCgIIBAAAAA==.Gregory:BAAANQAFFAEIAQABNQADCgMIAwABAAAAAA==.Greyantheril:BAAANQAECgEIAQAAAA==.Greyji:BAAANQAECgcIDAAAAA==.Grumb:BAAANQAECgcIDAAAAA==.',
Gu='Guenara:BAAANQADCggIFQAAAQ==.Guillimon:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Gustytail:BAAANQAECgEIAQAAAA==.',
Ha='Haardrada:BAAANQADCggIFgABNQAFFAUIBwAFAAMaAA==.Habit:BAAANQAECgQIBAAAAA==.Hadrianna:BAAANQAECgIIAgAAAA==.Halanir:BAAANQADCgIIAgAAAA==.Hanzul:BAAANQAECgEIAQAAAA==.Hapless:BAAANQADCgcIDwAAAA==.Hashanir:BAAANQADCgEIAQAAAA==.Hashat:BAAANQADCgIIAgAAAA==.Hawkfoot:BAAANQADCgcIBwAAAA==.',
He='Hearthbreakr:BAAANQAECgIIAgABNQAECgcIDAABAAAAAA==.Hellanie:BAAANQADCgQIBwAAAA==.Hellbore:BAAANQAECgMIAwAAAA==.Hellchi:BAAANQADCggIFQAAAA==.Hellinasel:BAAANQADCgMIAwAAAA==.Hemmy:BAAANQAECgYIDgAAAA==.Hermer:BAAANQADCgMIAwAAAA==.Heysham:BAAANQAECgEIAQAAAA==.Hezzakan:BAAANQADCgYIDgAAAA==.',
Ho='Holykow:BAAANQADCggIEAABNQAECgEIAQABAAAAAA==.Hotspur:BAAANQAECgIIAgAAAA==.',
Hu='Huevomuerto:BAAANQADCgQICAAAAA==.Huevonyque:BAAANQAFFAEIAQAAAA==.Huulgrim:BAAANQAECgEIAQABNQABCgMIAwABAAAAAA==.',
Hy='Hyejinx:BAAANQAECgIIAgAAAA==.',
Ic='Icona:BAAANQADCgQIBAAAAA==.',
Ih='Ihiannan:BAAANQADCgYIDQABNQAECgIIAgABAAAAAA==.',
Ii='Iiarian:BAAANQAECgIIAgAAAA==.',
Il='Illukana:BAAANQAECgUICAABNQAECgkJHQAHADUhAA==.',
In='Infoxy:BAAANQADCgYICQAAAA==.Inthra:BAAANQAECgEIAQAAAA==.',
Ir='Irimas:BAAANQADCggIDwAAAA==.',
Is='Isopope:BAAANQABCgYIBgAAAA==.Isthian:BAAANQAECgEIAQAAAA==.',
It='Itako:BAAANQADCgUIDAAAAA==.Itoldhimso:BAAANQADCgcICgAAAA==.',
Iv='Ivaldi:BAAANQADCgQIBQAAAA==.',
Ja='Jadelark:BAAANQAECgIIAgAAAA==.Javèrt:BAAANQAECgcICwAAAA==.Jaxina:BAAANQADCgIIAgABNQAECgUIBwABAAAAAA==.Jaxordamus:BAAANQAECgUIBwAAAA==.',
Je='Jema:BAAANQADCggIFAAAAA==.Jenilea:BAAANQAECgIIAgAAAA==.Jessaril:BAAANQADCggIDQAAAA==.Jessbgood:BAAANQABCgIIAgAAAA==.',
Ji='Jimboree:BAAANQAECgYICQAAAA==.Jinsu:BAAANQADCgYIDQAAAA==.Jinzeem:BAAANQADCgYIDgAAAA==.Jiujitsunut:BAAANQADCgIIBAAAAA==.',
Jo='Jordend:BAAANQAECgEIAgAAAA==.Joseppii:BAAANQAECgIIAgAAAA==.',
Jp='Jpxfrd:BAAANQABCgMIAwABNQADCgQIBAABAAAAAA==.',
Ju='Jungyuul:BAAANQADCggIDgAAAA==.',
Jy='Jynnx:BAAANQADCgEIAQAAAA==.',
['Jâ']='Jâzzy:BAAANQAECgEIAQAAAA==.',
Ka='Kaajira:BAAANQADCgEIAQAAAA==.Kaandew:BAAANQADCgYIDgAAAA==.Kailann:BAAANQADCgYIBgAAAA==.Karesta:BAAANQADCgMIAwAAAA==.Kaylith:BAAANQADCgYICwAAAA==.Kayra:BAAANQADCgIIAgAAAA==.',
Ke='Kegelsmash:BAAANQADCgMIAwABNQAECgYICgABAAAAAA==.Kelanansi:BAAANQADCgYIDQAAAA==.Kelanis:BAAANQADCgYIBgAAAA==.Kelel:BAAANQAECgQICAAAAA==.Kessia:BAAANQADCgcIDAAAAA==.Kessía:BAAANQADCgQIBAAAAA==.',
Kh='Khalistra:BAAANQAECgEIAQAAAA==.',
Ki='Kiropaly:BAAANQADCgYIDgABNQAECgUIBQABAAAAAA==.Kirotard:BAAANQAECgUIBQAAAA==.Kithedrael:BAAANQADCgUICAAAAA==.',
Kl='Klouded:BAAANQAECgMIAwAAAA==.',
Kn='Knuts:BAAANQADCgYICwABNQAECgUICQABAAAAAA==.',
Ko='Koa:BAAANQADCggIDgAAAA==.Kojakk:BAAANQAECgIIAgAAAA==.Kordac:BAAANQAECgEIAQAAAA==.Korigan:BAAANQAECgIIAgAAAA==.Korvova:BAAANQADCgEIAQAAAA==.',
Kt='Kth:BAAANQABCgIIAgAAAA==.',
Ku='Kunamashiro:BAAANQAECgEIAQAAAA==.',
Ky='Kylê:BAAANQAECgEIAQAAAA==.Kymetra:BAAANQADCggIFQAAAA==.Kyttin:BAAANQADCgYIDQAAAA==.',
['Kä']='Kära:BAAANQADCgUIBQABNQAECgQIBwABAAAAAA==.',
['Kÿ']='Kÿthe:BAAANQABCgQIBQAAAA==.',
La='Ladeeda:BAAANQADCgQIBwAAAA==.Laevi:BAAANQADCgYIDQAAAA==.Lalena:BAAANQADCggIDAAAAA==.Lawanda:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.',
Le='Leonineone:BAAANQAECgcIDAAAAA==.Ler:BAAANQADCgYIBgABNQADCgcIDAABAAAAAA==.',
Li='Lichplease:BAAANQAECggIEQAAAA==.Lightlady:BAAANQADCgYIDgAAAA==.Lightridge:BAAANQABCgMIBQAAAA==.Lillythorne:BAAANQAECgEIAQAAAA==.Litehlzonly:BAAANQADCggIDgAAAA==.Livebeef:BAAANQADCgUICwAAAA==.',
Lm='Lmaolock:BAAANQADCgEIAQAAAA==.',
Lo='Lohvadner:BAAANQADCgYICgAAAA==.Lothlum:BAAANQADCgYIDAABNQADCggIDAABAAAAAA==.',
Lu='Lunacie:BAAANQADCgMIBAAAAA==.Lupen:BAAANQAECgIIAgAAAA==.Luxurria:BAAANQADCgYICQAAAA==.',
Ma='Magesef:BAAANQAECgEIAQAAAA==.Magnusrn:BAAANQADCgMIBQAAAA==.Makinmemoist:BAAANQADCggIDAAAAA==.Malandrius:BAAANQADCgUICwAAAA==.Malignities:BAAANQAECgQIBQAAAA==.Malthruin:BAAANQADCggIFAABNQAECgYICgABAAAAAA==.Manajamba:BAAANQADCggIFQAAAA==.Mancubus:BAAANQAECgQICAAAAA==.Marosenth:BAAANQADCggICAAAAA==.Marqadin:BAAANQADCgIIBAAAAA==.Maxidorf:BAAANQADCgYIBgAAAA==.',
Me='Meleeno:BAAANQADCgIIBAAAAA==.Meush:BAABNQAECoEdAAIHAAkJNSFSBwBMAwAHAAkJNSFSBwBMAwAAAA==.Mewkow:BAAANQADCgYIEQAAAA==.Mewsa:BAAANQAECgIIAgAAAA==.',
Mi='Micha:BAAANQADCgcIBwAAAA==.Midgee:BAAANQADCgYICwAAAA==.Minimigraine:BAAANQAECgIIAgAAAA==.Miphisto:BAAANQADCgYICgAAAA==.Mirandee:BAAANQADCgYIDAAAAA==.Mishrani:BAAANQADCgYIDgAAAA==.Mite:BAAANQADCggICgAAAA==.',
Mo='Moa:BAAANQADCgYICwAAAA==.Molding:BAAANQADCgcIBwAAAA==.Mollusk:BAAANQADCgEIAgAAAA==.Monis:BAAANQAECgYICwAAAA==.Montessarah:BAAANQADCgUICQAAAA==.Moonstôrm:BAAANQADCgYIBgAAAA==.Mordraug:BAAANQADCgYIBgAAAA==.Morinoe:BAAANQAECgIIAgAAAA==.Mornwalker:BAAANQAECgEIAQAAAA==.',
Mu='Mudelf:BAAANQADCgYIBgAAAA==.Mumra:BAAANQAECgUICQAAAA==.',
My='Mysticc:BAAANQADCgYICgAAAA==.Myxii:BAAANQADCggIDAAAAA==.',
['Mà']='Màdrigal:BAAANQADCgYIDgAAAA==.',
['Mí']='Míckey:BAAANQAECgEIAQAAAA==.',
['Mÿ']='Mÿthunn:BAAANQADCggIDgAAAA==.',
Na='Nadia:BAAANQADCgcIBwAAAA==.Nagratz:BAAANQAECgEIAQAAAA==.Naichingeru:BAAANQADCgYIDQAAAA==.Napalmo:BAAANQADCgEIAQAAAA==.Naterra:BAAANQAECgMIAwAAAA==.',
Ne='Necessities:BAAANQADCggIFQAAAA==.Necrill:BAAANQAECgQIBAAAAA==.Neirwind:BAAANQADCgYICAAAAA==.',
Ni='Nichiwa:BAAANQADCgYIDQAAAA==.Nirazend:BAAANQADCgEIAQAAAA==.Nisaam:BAAANQADCgMIAwAAAA==.Niteterror:BAAANQAECgIIAgAAAA==.',
Nl='Nloc:BAAANQADCgYICAAAAA==.',
No='Nolmac:BAAANQADCgYICwAAAA==.Nomesacan:BAAANQADCgQIBAAAAA==.Nosleep:BAAANQADCgYIDQAAAA==.Novelia:BAAANQADCgIIAgAAAA==.',
Nu='Nuglife:BAAANQADCgYICwAAAA==.',
['Nà']='Nàtureuscary:BAAANQAECgQIBAAAAA==.',
Ob='Obtusepanda:BAAANQAECgIIAgAAAA==.',
Oc='Ocupocorrer:BAAANQADCgYIBgAAAA==.',
Of='Offthechaeni:BAAANQADCgUIBQAAAA==.',
Og='Ograndoe:BAAANQAECgYICQAAAA==.',
Oh='Ohanzee:BAAANQADCgQIBwAAAA==.Ohku:BAAANQADCggIFAAAAA==.Ohok:BAAANQAECgQIBQAAAA==.',
Oi='Oisin:BAAANQADCgYIDgAAAA==.',
Om='Omathra:BAAANQAECgYICgAAAA==.',
On='Onikai:BAAANQAECgIIAgAAAA==.Onruk:BAAANQADCgYIBgAAAA==.',
Op='Ophina:BAAANQAECgEIAQAAAA==.',
Or='Orieda:BAAANQADCgUIBAAAAA==.',
Os='Osage:BAAANQAECgQIBAAAAA==.',
Ox='Oxidising:BAAANQAECgQIBwAAAA==.',
Pa='Padrone:BAAANQADCgQICAAAAA==.Paladullahan:BAAANQAECgMIAgAAAA==.Pawthos:BAAANQADCgQIBwAAAA==.',
Pe='Pennonteller:BAAANQADCgIIBAAAAA==.Pennydredful:BAAANQABCgYIBwAAAA==.Perplnuggetz:BAAANQAECgEIAQAAAA==.Pewpewmcgraw:BAAANQAECgIIAgAAAA==.',
Pl='Plaguehart:BAAANQADCggICQAAAA==.Plagueniss:BAAANQAECgcIDAAAAA==.',
Po='Pompino:BAAANQABCgQIBAAAAA==.',
Pr='Primø:BAAANQAECgIIAgAAAA==.',
Ps='Psychó:BAAANQAECggIAwAAAA==.Psylänce:BAAANQAECgUICAAAAA==.',
Pu='Puerile:BAAANQADCgYICwAAAA==.Purplêlotus:BAAANQAECgYIDgAAAA==.Purrl:BAAANQADCgcIDAAAAA==.',
Py='Pyana:BAAANQADCgcIDQAAAA==.',
Qs='Qserie:BAAANQADCgYICwAAAA==.',
Ra='Rabid:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Racelon:BAAANQAECgcICwAAAA==.Raidgriefer:BAAANQAECgcICgAAAA==.Raistlín:BAAANQADCgYICgAAAA==.Rakwell:BAAANQADCggIFQAAAA==.Ramadin:BAAANQADCgEIAQABNQAECgcIDAABAAAAAA==.Ramil:BAAANQAECgEIAQAAAA==.Ramorash:BAAANQADCgYICQAAAA==.Randomeena:BAAANQADCgYIBgAAAA==.Raptorbait:BAAANQADCgEIAQAAAA==.',
Re='Reannis:BAAANQADCgMIAwAAAA==.Redvoid:BAAANQAECgQIBAABNQAECggIFgACABkjAA==.Rekane:BAAANQAECgEIAQAAAA==.Relyste:BAAANQADCggIDgAAAA==.Renala:BAAANQAECgcICgAAAA==.Reteril:BAAANQAECgYICQAAAA==.Reyis:BAAANQAECgMIAgAAAA==.Reyvinite:BAAANQADCggIDwAAAA==.',
Rh='Rhodaria:BAAANQADCgYIEAAAAA==.',
Ri='Ricepicks:BAAANQAECgQIBAABNQADCgYIBgABAAAAAA==.Rilaka:BAAANQADCgYIDgAAAA==.Rintaladin:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Rissu:BAAANQAECgYICwAAAA==.Risuu:BAAANQAECgIIAgAAAA==.',
Ro='Roasted:BAAANQAECgEIAQAAAA==.Roka:BAAANQABCgIIAgAAAA==.Ronathan:BAAANQAECgIIAgAAAA==.Roper:BAAANQAECgQIBgAAAA==.Roshen:BAAANQADCgYIEAAAAA==.Rosselyne:BAAANQADCgYIBgABNQAECgUIBwABAAAAAA==.Rouzou:BAAANQAECgEIAQAAAA==.',
Rr='Rrun:BAAANQAECgMIAwAAAA==.',
Ru='Rukia:BAAANQAECgYIEQAAAA==.Rumgold:BAAANQAECgEIAQAAAA==.Rustins:BAAANQADCgQIBAAAAA==.',
Sa='Sabele:BAAANQADCgEIAQABNQADCgUIBQABAAAAAA==.Sadie:BAAANQADCgUICQAAAA==.Saintmichael:BAAANQADCgUICgAAAA==.Sapphism:BAACNQAFFIEHAAICAAUJVhLOAQCkAQACAAUJVhLOAQCkAQA1AAQKgRwAAgIACQlhJFYBALMDAAIACQlhJFYBALMDAAAA.Sarai:BAAANQABCgMIBAAAAA==.Sarbev:BAAANQAECgYICwAAAA==.Saskwatch:BAABNQAECoEXAAIEAAkJQhQ/CQBYAgAEAAkJQhQ/CQBYAgAAAA==.Savat:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.Sayoko:BAAANQAECgQIBwAAAA==.Sayris:BAAANQAECgUIBwAAAA==.',
Sc='Sckratchxx:BAAANQAECgEIAQAAAA==.Scoochacho:BAAANQAECgMIBAAAAA==.',
Se='Selaria:BAAANQADCgcICgAAAA==.Senhunter:BAAANQAECgMIAwAAAA==.Senmaster:BAAANQADCgUICQABNQAECgMIAwABAAAAAA==.Sentrollock:BAAANQABCgIIAgABNQAECgMIAwABAAAAAA==.Seradiin:BAAANQADCgEIAQAAAA==.Sereknight:BAAANQADCgQIBAAAAA==.',
Sh='Shakers:BAAANQAECgcIDAAAAA==.Shaleron:BAAANQADCgQIBgAAAA==.Shamarq:BAAANQADCgYIDQAAAA==.Shamtastyc:BAAANQADCgUIBQABNQADCggIFgABAAAAAA==.Shapewalker:BAAANQAECgYICwAAAA==.Shaylina:BAAANQAECgMIBAAAAA==.Shaylune:BAAANQADCgUIBQABNQAECgMIBAABAAAAAA==.Sheba:BAAANQABCgEIAQAAAA==.Shendhi:BAAANQABCgQIBAAAAA==.Sheoby:BAAANQABCgMIBAAAAA==.Shiftcen:BAAANQAECgEIAQAAAA==.Shintazhi:BAAANQAECgIIAgAAAA==.Shirkan:BAAANQAECgYICwAAAA==.Shreddedbeef:BAAANQAECgQIBAAAAA==.Shwartz:BAAANQADCgQIBAAAAA==.',
Si='Simplicity:BAAANQADCgYIDQAAAA==.Sindrii:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.Sinhoi:BAAANQADCgUIBQAAAA==.Sinku:BAAANQADCgYICwAAAA==.',
Sk='Skarray:BAEANQAECgEIAQAAAA==.',
Sl='Slyraxis:BAAANQAECgEIAQAAAA==.',
So='Soleirra:BAAANQADCgEIAQABNQADCggICAABAAAAAA==.Sonas:BAAANQADCgEIAQAAAA==.Soohainao:BAAANQADCgcICgABNQAECgcIDAABAAAAAA==.Sorador:BAAANQADCgQIBwAAAA==.',
Sp='Spargelfürze:BAAANQADCgIIBAAAAA==.Spellgibson:BAAANQAECgMIAwAAAA==.Spiara:BAAANQABCgQIBAAAAA==.Spiraa:BAAANQADCggICAAAAA==.Spyroh:BAAANQAECgIIAgAAAA==.',
St='Stoogle:BAAANQAECggIEAAAAA==.Stormbrook:BAAANQAECgMIAgAAAA==.Sturmdorf:BAAANQADCgUICQAAAA==.',
Su='Suhli:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.Sulfrick:BAAANQADCgYIDQAAAA==.Summannuz:BAAANQADCgIIAgAAAA==.',
Sv='Svurg:BAAANQADCgcIEgAAAA==.',
Sw='Sweetchi:BAAANQAECgEIAQAAAA==.',
Sy='Sybria:BAAANQADCgcICgABNQADCgcICgABAAAAAA==.Sykko:BAAANQAECgIIAgAAAA==.Sylea:BAAANQAECgIIAgAAAA==.Sylverhunter:BAAANQABCgQIBAABNQADCgcIDwABAAAAAA==.Symet:BAAANQADCgYICQAAAA==.',
['Så']='Såturn:BAAANQADCgcIDwAAAA==.',
Ta='Takaria:BAAANQAECgIIAgAAAA==.Takaris:BAAANQADCgcIBwAAAA==.Tal:BAEANQAECgIIAgAAAA==.Tankdium:BAAANQAECgEIAQAAAA==.Tapcon:BAAANQADCgYIEAAAAA==.Tarlas:BAAANQAECgEIAQAAAA==.Tayllore:BAAANQAECgIIAgAAAA==.',
Te='Tearsheet:BAAANQADCgQIBwABNQAECgIIAgABAAAAAA==.Terah:BAAANQADCgUICQABNQAECgcIDAABAAAAAA==.Terendelev:BAAANQAECgcICwAAAA==.Terramortua:BAAANQAECgcIDAAAAA==.',
Th='Thalassairi:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Thaugtless:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Thelonius:BAAANQAECgIIAgAAAA==.Therocksays:BAAANQAECgIIAgAAAA==.Thindead:BAAANQADCgIIAgABNQAECgQICQABAAAAAA==.Thinloc:BAAANQAECgQICQAAAA==.Thinpal:BAAANQADCgIIAgABNQAECgQICQABAAAAAA==.Thragge:BAEANQAECgEIAQAAAA==.Thronjak:BAAANQAECgIIAgAAAA==.Thunderfury:BAAANQADCggIFgAAAA==.',
Ti='Tidepod:BAAANQADCggIEAAAAA==.Tipride:BAAANQAECgcIDAAAAA==.Tiralie:BAAANQADCggIEwAAAA==.Tiryl:BAAANQADCgYICQAAAA==.',
Tn='Tnama:BAAANQADCgIIAgAAAA==.',
To='Togashi:BAAANQAECgEIAQAAAA==.Tolipes:BAAANQADCgYIBgAAAA==.Toogodly:BAAANQADCgcIDQAAAA==.Torent:BAAANQADCgYIEAAAAA==.Toshinori:BAAANQADCgIIAgAAAA==.Totemdáddy:BAAANQAECgEIAwAAAA==.Tovëlo:BAAANQADCgYIBgAAAA==.',
Tr='Treelight:BAAANQADCgEIAQAAAA==.Trehugga:BAAANQADCgcIBwAAAA==.Trinogra:BAAANQAECgcIDAAAAA==.Trunks:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.Trystern:BAAANQAECgIIAgAAAA==.',
Tu='Turmeric:BAAANQADCgYICgABNQADCggIEwABAAAAAA==.',
['Tä']='Tänya:BAAANQAECgMIAgAAAA==.',
Ul='Ultar:BAAANQAECgcIDAAAAA==.Ultodeesavag:BAAANQAECgIIAgAAAA==.Ultradeath:BAAANQADCggICAAAAA==.',
Un='Undeadshaman:BAAANQAECgEIAgAAAA==.Unvdi:BAAANQADCgYIDAAAAA==.',
Va='Vaderrage:BAAANQADCggICAABNQAECgYICAABAAAAAA==.Valeyria:BAAANQADCggIFQAAAA==.Valiyntha:BAAANQADCgYIDQAAAA==.Vancasper:BAAANQADCgQIBAAAAA==.Varlock:BAAANQAECgcIDAAAAA==.Vasill:BAAANQAECgEIAQAAAA==.',
Ve='Velari:BAAANQAECgIIAgAAAA==.Velmathris:BAAANQAECgIIAgAAAA==.Ventnor:BAAANQADCgIIAgAAAA==.Veydh:BAAANQAECgMIAwAAAA==.Veymina:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.',
Vi='Viinnee:BAAANQAECgIIAgAAAA==.Vincentlight:BAAANQADCgYIDwAAAA==.Vixess:BAAANQAECgcICwAAAA==.',
Vo='Voidpriest:BAAANQADCggICAAAAA==.Voidweaver:BAAANQADCgUICQAAAA==.Volteer:BAAANQAECgUIBgAAAA==.',
Vy='Vyara:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Vynddradoria:BAAANQAECgYICwAAAA==.Vyndh:BAAANQAECgcIDAAAAA==.',
Wa='Walkerbowe:BAAANQADCgUIBQAAAA==.Walt:BAAANQAECgMIAgAAAA==.Wanderin:BAAANQADCggIDAAAAA==.Waterbutcold:BAAANQAECgEIAQAAAA==.Waysmomtwo:BAAANQADCgYIBgAAAA==.',
We='Webby:BAAANQAECgMIAwAAAA==.',
Wh='Whiskerses:BAAANQAECgUIBAAAAA==.Whithers:BAAANQADCgUIDQAAAA==.',
Wi='Wilmer:BAAANQADCggIDQAAAA==.Wilyy:BAAANQAECgQIBAABNQAECgcIDwABAAAAAA==.Windowhelle:BAAANQADCgcICQAAAA==.Winterchild:BAAANQADCgIIAgAAAA==.',
Wo='Woodsylver:BAAANQADCgcIDwAAAA==.Worski:BAAANQADCgUICQAAAA==.',
Wr='Wrathalthiel:BAAANQADCgYIEQABNQAECgEIAQABAAAAAA==.Wratherael:BAAANQADCggIDQABNQAECgEIAQABAAAAAA==.Wraîth:BAAANQAECgQICAAAAA==.',
Wy='Wynilla:BAAANQADCgYIDgAAAA==.',
Xa='Xanathar:BAAANQAECgIIAgAAAA==.Xaphoris:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Xayleficent:BAAANQADCgYIBgAAAA==.Xaylia:BAAANQAECgIIAgAAAA==.',
Xo='Xolotin:BAAANQADCgMIAwAAAA==.',
Ya='Yassi:BAAANQAECgEIAQAAAA==.',
Yn='Ynarii:BAAANQADCgEIAQAAAA==.Ynkdh:BAAANQAECgEIAQAAAA==.',
Yo='Yoonhee:BAAANQAECgUIBwAAAA==.',
Yu='Yura:BAAANQADCgIIAgAAAA==.',
Za='Zaghary:BAAANQADCgcIGQAAAA==.Zarik:BAAANQADCgIIAwAAAA==.',
Ze='Zebjati:BAAANQAECgEIAQAAAA==.',
Zh='Zhend:BAAANQAECgEIAQAAAA==.',
Zu='Zunch:BAAANQADCgcIEAAAAQ==.',
['Àz']='Àzazel:BAAANQAECgMIAwAAAA==.',
['Är']='Ärk:BAAANQAECgEIAQAAAA==.Ärmistice:BAAANQAECgQIBgAAAA==.',
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
