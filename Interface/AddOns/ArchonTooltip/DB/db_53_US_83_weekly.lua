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
local provider = {region='US',realm='EarthenRing',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abrothael:BAAANQADCggIDwAAAA==.',
Ad='Adorèè:BAAANQADCgcIBwAAAA==.',
Ae='Aedelas:BAAANQADCgQIBAAAAA==.Aestua:BAAANQADCgEIAgAAAA==.Aetheros:BAAANQAECgQIBQAAAA==.',
Ag='Agarim:BAAANQADCgQIBAAAAA==.',
Ai='Airlinna:BAAANQAECgQIBQAAAA==.Airoach:BAAANQADCgYICwAAAA==.',
Ak='Akers:BAAANQADCggICwAAAA==.',
Al='Alaraen:BAAANQADCgcIDQAAAA==.Alcremie:BAAANQAECgIIAgABNQAFFAIIAgABAAAAAA==.Aleman:BAAANQADCgIIAgAAAA==.Aleyah:BAAANQADCgcIDgAAAA==.Almarii:BAAANQABCgIIAgAAAA==.Alraune:BAAANQADCggIDAAAAA==.Alynndra:BAAANQADCgYIBgAAAA==.Alyssazoe:BAAANQADCgIIAgAAAA==.',
An='Anarionhunts:BAAANQADCgcIDAAAAA==.Andius:BAAANQADCgQIBwAAAA==.Anirra:BAAANQADCgcIDQAAAA==.',
Ap='Apert:BAAANQADCggIDgAAAA==.',
Ar='Ardenweald:BAAANQAECgMIBQAAAA==.Armyokittens:BAAANQADCgUICAAAAA==.Arroezze:BAAANQADCgYIBQAAAA==.Arthurin:BAAANQAECgEIAQAAAA==.',
As='Ashayo:BAAANQADCgMIAwAAAA==.Astrana:BAAANQAECgEIAQAAAA==.',
Au='Augkward:BAAANQADCgYIBQABNQAFFAEIAQABAAAAAA==.Aureldor:BAAANQADCgMIAwAAAA==.Automatic:BAAANQAECgQIBQAAAA==.Autoshot:BAAANQADCgMIAwAAAA==.',
Av='Avorik:BAAANQADCggICAAAAA==.',
Az='Azaree:BAAANQADCgcIDQAAAA==.Azndak:BAAANQADCgcIBwAAAA==.',
Ba='Baelzabob:BAAANQADCgMIBgAAAA==.Bakaran:BAAANQADCgUIBQAAAA==.Barae:BAAANQADCgUICAAAAA==.Barcmaul:BAAANQADCgYICgAAAA==.Bathzalts:BAAANQADCgYIBQAAAA==.Baylel:BAAANQADCgcIDQAAAA==.',
Be='Belledolphin:BAAANQAECgUIBQAAAA==.Bellgold:BAAANQADCgEIAQABNQADCggIDAABAAAAAA==.Berigo:BAAANQAECgQIBAAAAA==.Bezvoker:BAAANQAECgEIAQAAAA==.',
Bj='Bjordrann:BAAANQADCgEIAQAAAA==.',
Bl='Blackicewolf:BAAANQAECgQIBQAAAA==.Bleake:BAAANQADCgUIBQAAAA==.Bleunienn:BAAANQABCgIIBAAAAA==.Blueberrypie:BAAANQADCggIDQAAAA==.',
Bo='Bonbarrion:BAEANQAECgQIBQAAAA==.Borbory:BAAANQADCggIDgAAAA==.Boringhuman:BAAANQADCgUICAAAAA==.',
Br='Brasca:BAAANQADCggIDgAAAA==.Brisketdk:BAAANQADCggIBAAAAA==.Bruhmal:BAAANQADCggIDgAAAA==.Brunner:BAAANQADCgEIAQAAAA==.Brynndolin:BAAANQADCggIDgAAAA==.',
Bu='Burzolog:BAAANQAECgMIBAAAAA==.',
['Bä']='Bärk:BAAANQAECgQIBAAAAA==.',
Ca='Calazan:BAAANQADCggIDgAAAA==.Cascious:BAAANQADCgcIBwABNQAECgcIDAABAAAAAA==.',
Ce='Cedarjr:BAAANQADCgUICAAAAA==.Cef:BAAANQADCgcICwAAAA==.Celindre:BAAANQADCgQIBQAAAA==.',
Ch='Chewbie:BAAANQAECgEIAQAAAA==.',
Ci='Ciphon:BAAANQADCgUIBgAAAA==.Cirok:BAAANQADCgcIDQAAAA==.Civic:BAAANQADCgQIAQAAAA==.',
Ck='Cklyde:BAAANQAECgQIBQAAAA==.',
Cl='Claiyre:BAAANQADCgUICAAAAA==.Clewis:BAAANQABCgMIBAAAAA==.Clubble:BAAANQADCgcIDQAAAA==.Clumperton:BAAANQAECgUIBgAAAA==.Clãsh:BAAANQADCgYICwAAAA==.',
Co='Cochino:BAAANQADCgYIBgAAAA==.Concentrate:BAAANQAECgEIAQAAAQ==.Connan:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.Constant:BAAANQADCgIIAgAAAA==.Corbesan:BAAANQADCgcIBwAAAA==.Cordrann:BAAANQADCgUIBQAAAA==.Coveness:BAAANQADCgEIAQAAAA==.Cowi:BAAANQAECgEIAgAAAA==.',
Cr='Crasusakechi:BAAANQADCgMIAwAAAA==.Cryomagus:BAAANQAECgQIBQAAAA==.',
Cu='Cuqquiform:BAAANQAECgQICAAAAA==.',
Cy='Cylesia:BAAANQADCgYICgAAAA==.Cylthia:BAAANQADCgIIAgAAAA==.',
Da='Daemata:BAAANQADCggICAAAAA==.Dajinbo:BAAANQADCgQIBgAAAA==.Darchlo:BAAANQADCgEIAQAAAA==.Darkhammer:BAAANQADCgYIBgAAAA==.Darkswift:BAAANQAECgQIBQAAAA==.Darnadda:BAAANQADCgUIBwAAAA==.Darowyn:BAAANQADCggIDgAAAA==.Dashiell:BAAANQADCgQIBwABNQADCgcIBwABAAAAAA==.Dawnflare:BAAANQADCgcIBwABNQADCggIDQABAAAAAA==.',
De='Deaxus:BAAANQADCgUICgABNQAECgQIBAABAAAAAA==.Deb:BAAANQADCgcICAAAAA==.Delbelfine:BAAANQAECgQIBQAAAA==.Delfar:BAAANQADCgUIBQAAAA==.Delisomethng:BAAANQADCgcIDAAAAA==.Dellechero:BAAANQADCgYIBgAAAA==.Demilich:BAAANQADCgIIAgAAAA==.Despaira:BAAANQADCgcIDAAAAA==.Dethyler:BAAANQADCggIDgAAAA==.Devilwoman:BAAANQAECgEIAQAAAA==.',
Di='Diancie:BAAANQAECgIIAgABNQAFFAIIAgABAAAAAA==.Diddibeau:BAAANQADCgQIBwAAAA==.Diddiblind:BAAANQADCgMIBgABNQADCgQIBwABAAAAAA==.Diego:BAAANQADCgEIAQAAAA==.Divinezanon:BAAANQAECgcICgABNQADCggICAABAAAAAA==.',
Do='Dontyagnomie:BAAANQADCgYICgAAAA==.Doobu:BAAANQADCgUIBgAAAA==.Dooganitis:BAAANQADCgcIDQAAAA==.Doruk:BAAANQADCgIIAgAAAA==.',
Dr='Dreamsoul:BAAANQABCgQIBAAAAA==.',
Du='Dusksorrow:BAAANQADCgUIBQAAAA==.',
Ed='Edovard:BAAANQADCgQIBgAAAA==.',
Ee='Ee:BAAANQADCgUIBQAAAA==.Eeragon:BAAANQADCgUICQAAAA==.',
El='Eliyon:BAAANQADCgYICgAAAA==.Ellarinya:BAAANQADCgEIAgAAAA==.Ellemir:BAAANQADCgQIBwAAAA==.Eltanari:BAAANQADCgUICgAAAA==.Eluera:BAAANQADCgQIAgAAAA==.Elyn:BAAANQAECgMIAwAAAA==.',
Em='Emunny:BAAANQADCggIDgAAAA==.',
En='Endest:BAAANQADCggIDgAAAA==.Enezalle:BAAANQADCggIDgAAAA==.',
Eo='Eointhas:BAAANQADCggIDgAAAA==.',
Ep='Ephimonk:BAAANQADCggICAAAAA==.',
Er='Ernson:BAAANQADCgEIAQAAAA==.',
Ev='Evilandy:BAAANQADCggICAAAAA==.',
Fa='Faeleda:BAAANQADCgEIAQAAAA==.',
Fb='Fblthp:BAAANQADCgcIDQAAAA==.',
Fe='Felblood:BAAANQADCgYICAAAAA==.Fezduin:BAAANQADCgIIAgAAAA==.',
Fi='Finnagetit:BAAANQADCggICAAAAA==.',
Fl='Flagonslayer:BAAANQADCgYICwAAAA==.Flaimefu:BAAANQADCgUICgAAAA==.Flopsie:BAAANQADCgYIBgAAAA==.Fluffystorm:BAAANQADCgQIBwAAAA==.',
Fo='Forzod:BAAANQADCgYICAAAAA==.Foxymagic:BAAANQADCgUICAAAAA==.',
Fr='Frabjous:BAAANQADCggIDgAAAA==.Freenk:BAAANQADCgcICQAAAA==.Freezerburn:BAAANQAECgQIBQAAAA==.',
Fu='Furn:BAAANQADCggIDgAAAA==.Furryaz:BAAANQADCgIIAgAAAA==.Further:BAAANQAECgQIBQAAAA==.',
Fy='Fyrrek:BAAANQADCgYIBgAAAA==.',
Ga='Galadrien:BAAANQADCgYIBgAAAA==.Galavenat:BAAANQADCggIDQAAAA==.Garbohydrate:BAAANQADCgEIAQAAAA==.Garbothicc:BAAANQADCgQIBQAAAA==.Garyh:BAAANQAFFAIIAgAAAA==.Garyhreturns:BAAANQAECgUIBgABNQAFFAIIAgABAAAAAA==.',
Gh='Ghuramonk:BAAANQADCgIIAgAAAA==.',
Gi='Giacomo:BAAANQADCgIIAgAAAA==.Gil:BAAANQADCgEIAQAAAA==.Gildina:BAAANQADCgUICAAAAA==.Ginggy:BAAANQAECgEIAQABNQAECgcIDAABAAAAAA==.Girafficz:BAAANQAFFAEIAQABNQAFFAQIBAABAAAAAA==.',
Go='Gori:BAAANQADCggIDgAAAA==.Gorin:BAAANQADCgQIBAABNQADCgcIBwABAAAAAA==.',
Gr='Gralle:BAAANQAECgEIAQAAAA==.Graug:BAAANQADCgQIBAABNQADCgIIAgABAAAAAA==.Gravelbeard:BAAANQADCgIIAgAAAA==.Gregory:BAAANQAECgEIAQABNQADCgIIAgABAAAAAA==.Greyantheril:BAAANQADCggICAAAAA==.Greyji:BAAANQAECgQIBQAAAA==.Grumb:BAAANQAECgQIBQAAAA==.',
Gu='Guenara:BAAANQADCgcIDQAAAQ==.Gustytail:BAAANQADCggIDgAAAA==.',
Ha='Haardrada:BAAANQADCggIDgABNQAFFAIIAgABAAAAAA==.Habit:BAAANQAECgIIAgAAAA==.Hadrianna:BAAANQADCgcIDAAAAA==.Halanir:BAAANQADCgIIAgAAAA==.Hanzul:BAAANQADCggIDgAAAA==.Hapless:BAAANQADCgUIBQAAAA==.Hashanir:BAAANQADCgEIAQAAAA==.Hashat:BAAANQADCgIIAgAAAA==.',
He='Hearthbreakr:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.Hellanie:BAAANQADCgQIBwAAAA==.Hellbore:BAAANQADCggIDQAAAA==.Hellchi:BAAANQADCggIDQAAAA==.Hellinasel:BAAANQADCgIIAgAAAA==.Hemmy:BAAANQAECgUICAAAAA==.Hermer:BAAANQADCgEIAQAAAA==.Heysham:BAAANQADCgcIBwAAAA==.Hezzakan:BAAANQADCgUICAAAAA==.',
Ho='Holykow:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.Hotspur:BAAANQADCggIDgAAAA==.',
Hu='Huevomuerto:BAAANQADCgQICAAAAA==.Huevonyque:BAAANQAECgQICAAAAA==.Huulgrim:BAAANQADCggIDgABNQABCgMIAwABAAAAAA==.',
Hy='Hyejinx:BAAANQAECgIIAgAAAA==.',
Ih='Ihiannan:BAAANQADCgQIBwABNQADCggIDgABAAAAAA==.',
Ii='Iiarian:BAAANQADCggIDgAAAA==.',
Il='Illukana:BAAANQAECgMIAwABNQAECgcICwABAAAAAA==.',
In='Infoxy:BAAANQADCgYICQAAAA==.Inthra:BAAANQAECgEIAQAAAA==.',
Ir='Irimas:BAAANQADCggICAAAAA==.',
Is='Isthian:BAAANQADCgcIDAAAAA==.',
It='Itako:BAAANQADCgQIBwAAAA==.Itoldhimso:BAAANQADCgYIBwAAAA==.',
Iv='Ivaldi:BAAANQADCgMIAwAAAA==.',
Ja='Jadelark:BAAANQADCgcIDQAAAA==.Javèrt:BAAANQAECgQIBQAAAA==.Jaxina:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Jaxordamus:BAAANQAECgQIBAAAAA==.',
Je='Jema:BAAANQADCgcIDAAAAA==.Jenilea:BAAANQADCggIDgAAAA==.Jessaril:BAAANQADCggIDQAAAA==.Jessbgood:BAAANQABCgIIAgAAAA==.',
Ji='Jimboree:BAAANQAECgMIAwAAAA==.Jinsu:BAAANQADCgQIBwAAAA==.Jinzeem:BAAANQADCgUICAAAAA==.Jiujitsunut:BAAANQADCgIIAgAAAA==.',
Jo='Jordend:BAAANQADCggICgAAAA==.Joseppii:BAAANQADCgYICgAAAA==.',
Ju='Jungyuul:BAAANQADCggICAAAAA==.',
Jy='Jynnx:BAAANQADCgEIAQAAAA==.',
['Jâ']='Jâzzy:BAAANQADCgcIDQAAAA==.',
Ka='Kaajira:BAAANQADCgEIAQAAAA==.Kaandew:BAAANQADCgUICAAAAA==.Kailann:BAAANQADCgYIBgAAAA==.Karesta:BAAANQADCgMIAwAAAA==.Kaylith:BAAANQADCgUIBQAAAA==.Kayra:BAAANQADCgIIAgAAAA==.',
Ke='Kegelsmash:BAAANQADCgMIAwABNQAECgUIBgABAAAAAA==.Kelanansi:BAAANQADCgUIBwAAAA==.Kelel:BAAANQAECgMIBAAAAA==.Kessia:BAAANQADCgUIBQAAAA==.Kessía:BAAANQADCgQIBAAAAA==.',
Kh='Khalistra:BAAANQADCggIDgAAAA==.',
Ki='Kiropaly:BAAANQADCgQIBQABNQAECgEIAQABAAAAAA==.Kirotard:BAAANQAECgEIAQAAAA==.Kithedrael:BAAANQADCgUIAwAAAA==.',
Kl='Klouded:BAAANQADCggIFAAAAA==.',
Kn='Knuts:BAAANQADCgYICwABNQAECgQIBAABAAAAAA==.',
Ko='Koa:BAAANQADCgMIBgAAAA==.Kojakk:BAAANQADCggIDgAAAA==.Kordac:BAAANQADCggIDgAAAA==.Korigan:BAAANQADCgUIBQAAAA==.Korvova:BAAANQADCgEIAQAAAA==.',
Kt='Kth:BAAANQABCgIIAgAAAA==.',
Ku='Kunamashiro:BAAANQADCgcIBwAAAA==.',
Ky='Kyttin:BAAANQADCgQIBwAAAA==.',
La='Ladeeda:BAAANQADCgQIBwAAAA==.Laevi:BAAANQADCgYIBwAAAA==.Lalena:BAAANQADCggIBAAAAA==.',
Le='Leonineone:BAAANQAECgQIBQAAAA==.',
Li='Lichplease:BAAANQAECgYICgAAAA==.Lightlady:BAAANQADCgUICAAAAA==.Lillythorne:BAAANQADCggIDQAAAA==.Litehlzonly:BAAANQADCgYIBgAAAA==.Livebeef:BAAANQADCgUICAAAAA==.',
Lo='Lohvadner:BAAANQADCgYIBgAAAA==.Lothlum:BAAANQADCgYIDAABNQADCgcIBwABAAAAAA==.',
Lu='Lunacie:BAAANQADCgEIAQAAAA==.Lunalia:BAAANQADCgYICQAAAA==.Lupen:BAAANQADCgcIBwAAAA==.Luxurria:BAAANQADCgYICQAAAA==.',
Ma='Magesef:BAAANQADCgcIBwAAAA==.Magnusrn:BAAANQADCgEIAgAAAA==.Makinmemoist:BAAANQADCgQIBAAAAA==.Malandrius:BAAANQADCgQIBgAAAA==.Malignities:BAAANQAECgEIAQAAAA==.Malthruin:BAAANQADCgcIDAABNQAECgQIBAABAAAAAA==.Manajamba:BAAANQADCgcIDQAAAA==.Mancubus:BAAANQAECgQIBAAAAA==.Marqadin:BAAANQADCgIIAgAAAA==.',
Me='Meleeno:BAAANQADCgIIAgAAAA==.Meush:BAAANQAECgcICwAAAA==.Mewkow:BAAANQADCgYICwAAAA==.',
Mi='Midgee:BAAANQADCgUIBQAAAA==.Miphisto:BAAANQADCgQIBgAAAA==.Mirandee:BAAANQADCgQIBgAAAA==.Mishrani:BAAANQADCgUICAAAAA==.Mite:BAAANQADCgIIAgAAAA==.',
Mo='Moa:BAAANQADCgUIBQAAAA==.Mollusk:BAAANQADCgEIAgAAAA==.Monis:BAAANQAECgQIBQAAAA==.Montessarah:BAAANQADCgUIBQAAAA==.Moonstôrm:BAAANQADCgYIBgAAAA==.Mordraug:BAAANQADCgYIBgAAAA==.Morinoe:BAAANQADCgcIDQAAAA==.Mornwalker:BAAANQADCgcIDQAAAA==.',
Mu='Mumra:BAAANQAECgQIBAABNQAECgQICAABAAAAAA==.',
My='Mysticc:BAAANQADCgQIBgAAAA==.Myxii:BAAANQADCggIBAAAAA==.',
['Mà']='Màdrigal:BAAANQADCgUICAAAAA==.',
['Mí']='Míckey:BAAANQADCggIDgAAAA==.',
['Mÿ']='Mÿthunn:BAAANQADCggIDgAAAA==.',
Na='Nagratz:BAAANQADCggIDgAAAA==.Naichingeru:BAAANQADCgQIBwAAAA==.Napalmo:BAAANQADCgEIAQAAAA==.Naterra:BAAANQADCggIDQAAAA==.',
Ne='Necessities:BAAANQADCgcIDQAAAA==.Necrill:BAAANQADCggIDgABNQADCggIDgABAAAAAA==.Neirwind:BAAANQADCgYICAAAAA==.',
Ni='Nichiwa:BAAANQADCgUIBwAAAA==.Niladros:BAAANQADCgYIBgAAAA==.Nirazend:BAAANQADCgEIAQAAAA==.',
Nl='Nloc:BAAANQADCgYICAAAAA==.',
No='Nolmac:BAAANQADCgUIBQAAAA==.Nomesacan:BAAANQADCgQIBAAAAA==.Nosleep:BAAANQADCgQIBwAAAA==.',
Nu='Nuglife:BAAANQADCgYICQAAAA==.',
['Nà']='Nàtureuscary:BAAANQADCgUIBQAAAA==.',
Ob='Obtusepanda:BAAANQADCggIDwAAAA==.',
Oc='Ocupocorrer:BAAANQADCgYIBgAAAA==.',
Of='Offthechaeni:BAAANQADCgUIBQAAAA==.',
Og='Ograndoe:BAAANQAECgMIAwAAAA==.',
Oh='Ohanzee:BAAANQADCgIIAwAAAA==.Ohku:BAAANQADCgcIDAAAAA==.Ohok:BAAANQAECgMIAwAAAA==.',
Oi='Oisin:BAAANQADCgUICAAAAA==.',
Om='Omathra:BAAANQAECgQIBAAAAA==.',
On='Onikai:BAAANQADCgcIBwAAAA==.Onruk:BAAANQADCgYIBgAAAA==.',
Op='Ophina:BAAANQABCgIIAgABNQADCggICwABAAAAAA==.',
Os='Osage:BAAANQADCgYIBgAAAA==.',
Ox='Oxidising:BAAANQAECgIIAwAAAA==.',
Pa='Padrone:BAAANQADCgMIBAAAAA==.Paladullahan:BAAANQADCgcIDQAAAA==.Pawthos:BAAANQADCgIIAwAAAA==.',
Pe='Pennonteller:BAAANQADCgIIAgAAAA==.Pennydredful:BAAANQABCgEIAQAAAA==.Pewpewmcgraw:BAAANQADCggIDgAAAA==.',
Pl='Plaguehart:BAAANQADCggIAQAAAA==.Plagueniss:BAAANQAECgQIBQAAAA==.',
Pr='Primø:BAAANQADCgcICAAAAA==.',
Ps='Psylänce:BAAANQAECgQIBAAAAA==.',
Pu='Puerile:BAAANQADCgYICQAAAA==.Purplêlotus:BAAANQAECgQIBQAAAA==.Purrl:BAAANQADCgUIBQAAAA==.',
Py='Pyana:BAAANQADCgcIDQAAAA==.',
Qs='Qserie:BAAANQADCgQIBwAAAA==.',
Ra='Racelon:BAAANQAECgQIBAAAAA==.Raidgriefer:BAAANQAECgUIBAAAAA==.Raistlín:BAAANQADCgUICQAAAA==.Rakwell:BAAANQADCgcIDQAAAA==.Ramadin:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.Ramil:BAAANQADCggIDgAAAA==.Ramorash:BAAANQADCgYICQAAAA==.Raptorbait:BAAANQADCgEIAQAAAA==.',
Re='Rekane:BAAANQADCgUICQAAAA==.Relyste:BAAANQADCggIDgAAAA==.Renala:BAAANQAECgQIBAAAAA==.Reteril:BAAANQAECgQIBAAAAA==.Reyis:BAAANQADCgcICwAAAA==.Reyvinite:BAAANQADCgcIBwAAAA==.',
Rh='Rhodaria:BAAANQADCgUICgAAAA==.',
Ri='Rilaka:BAAANQADCgUICAAAAA==.Rintaladin:BAAANQADCgMIAwABNQADCgcICgABAAAAAA==.Rissu:BAAANQAECgQIBQAAAA==.Risuu:BAAANQADCgYIBgAAAA==.',
Ro='Roasted:BAAANQADCgcIDQAAAA==.Ronathan:BAAANQADCgcICgAAAA==.Roper:BAAANQAECgIIAgAAAA==.Roshen:BAAANQADCgUICAAAAA==.Rouzou:BAAANQADCggIDgAAAA==.',
Rr='Rrun:BAAANQADCgIIAgAAAA==.',
Ru='Rukia:BAAANQAECgYICwAAAA==.Rumgold:BAAANQADCggIDAAAAA==.',
Sa='Sabele:BAAANQADCgEIAQABNQADCgMIAwABAAAAAA==.Sadie:BAAANQADCgQIBAAAAA==.Saintmichael:BAAANQADCgUICgAAAA==.Sapphism:BAAANQAFFAIIAgAAAA==.Sarbev:BAAANQAECgQIBQAAAA==.Saskwatch:BAAANQAECgcIDAAAAA==.Savat:BAAANQADCggIDgAAAA==.Sayoko:BAAANQAECgIIAwAAAA==.Sayris:BAAANQAECgIIAgAAAA==.',
Sc='Sckratchxx:BAAANQADCgYIBgAAAA==.Scoochacho:BAAANQAECgEIAQAAAA==.',
Se='Selaria:BAAANQADCgcICgAAAA==.Senhunter:BAAANQADCgYIBgAAAA==.Senmaster:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Seradiin:BAAANQADCgEIAQAAAA==.',
Sh='Shakers:BAAANQAECgQIBQAAAA==.Shaleron:BAAANQADCgQIBgAAAA==.Shamarq:BAAANQADCgQIBwAAAA==.Shapewalker:BAAANQAECgQIBQAAAA==.Shaylina:BAAANQAECgIIAgAAAA==.Shaylune:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Shiftcen:BAAANQADCgUIBQAAAA==.Shintazhi:BAAANQADCgcIDQAAAA==.Shirkan:BAAANQAECgQIBQAAAA==.Shreddedbeef:BAAANQADCgcIDgAAAA==.',
Si='Simplicity:BAAANQADCgYIBgAAAA==.Sindrii:BAAANQADCgMIAwAAAA==.Sinku:BAAANQADCgYICQAAAA==.',
Sk='Skarray:BAEANQADCggIDgAAAA==.',
Sl='Slyraxis:BAAANQADCggIDgAAAA==.',
So='Soohainao:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.Sorador:BAAANQADCgMIAwAAAA==.',
Sp='Spargelfürze:BAAANQADCgIIAgAAAA==.Spellgibson:BAAANQADCgcIBwAAAA==.Spiraa:BAAANQADCggICAAAAA==.Spyroh:BAAANQADCgcIDQAAAA==.',
St='Stoogle:BAAANQAECggIDgAAAA==.Stormbrook:BAAANQADCgcIDQAAAA==.Sturmdorf:BAAANQADCgQIBAAAAA==.',
Su='Suhli:BAAANQADCgQIBAAAAA==.Sulfrick:BAAANQADCgQIBwAAAA==.',
Sv='Svurg:BAAANQADCgcICwAAAA==.',
Sw='Sweetchi:BAAANQADCgcIDQAAAA==.',
Sy='Sybria:BAAANQADCgUICAAAAA==.Sykko:BAAANQADCgQIBgAAAA==.Sylea:BAAANQADCgYIBgAAAA==.Symet:BAAANQADCgYIBgAAAA==.',
['Så']='Såturn:BAAANQADCgUICAAAAA==.',
Ta='Takaris:BAAANQADCgcIBwAAAA==.Tal:BAEANQADCggIDgAAAA==.Tankdium:BAAANQADCggIDgAAAA==.Tapcon:BAAANQADCgYICgAAAA==.Tayllore:BAAANQADCggIDgAAAA==.',
Te='Tearsheet:BAAANQADCgQIBwABNQADCggIDgABAAAAAA==.Terah:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.Terendelev:BAAANQAECgQIBQAAAA==.Terramortua:BAAANQAECgQIBQAAAA==.',
Th='Thalassairi:BAAANQADCgMIAwABNQADCgcICgABAAAAAA==.Thelonius:BAAANQADCgcIBwAAAA==.Therocksays:BAAANQADCgcIDQAAAA==.Thindead:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.Thinloc:BAAANQAECgQIBQAAAA==.Thinpal:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.Thragge:BAEANQADCgcIDQAAAA==.Thronjak:BAAANQADCgcICAAAAA==.Thunderfury:BAAANQADCggIDgAAAA==.',
Ti='Tidepod:BAAANQADCggICAAAAA==.Tipride:BAAANQAECgQIBQAAAA==.Tiralie:BAAANQADCgYICwAAAA==.Tiryl:BAAANQADCgYICQAAAA==.',
Tn='Tnama:BAAANQADCgIIAgAAAA==.',
To='Togashi:BAAANQADCggIDQAAAA==.Tolipes:BAAANQADCgYIBgAAAA==.Toogodly:BAAANQADCgcIDQAAAA==.Torent:BAAANQADCgUICgAAAA==.Toshinori:BAAANQADCgIIAgAAAA==.Totemdáddy:BAAANQAECgEIAQAAAA==.Tovëlo:BAAANQADCgYIBgAAAA==.',
Tr='Treelight:BAAANQADCgEIAQAAAA==.Trehugga:BAAANQADCgcIBwAAAA==.Trinogra:BAAANQAECgQIBQAAAA==.Trunks:BAAANQADCgcICwABNQADCggIAQABAAAAAA==.Trystern:BAAANQADCgcIDQAAAA==.',
Tu='Turmeric:BAAANQADCgQIBAABNQADCgYICwABAAAAAA==.',
['Tä']='Tänya:BAAANQADCgcICwAAAA==.',
Ul='Ultar:BAAANQAECgUIBQAAAA==.Ultodeesavag:BAAANQADCgcIDQAAAA==.Ultradeath:BAAANQADCggICAAAAA==.',
Un='Undeadshaman:BAAANQAECgEIAgAAAA==.Unvdi:BAAANQADCgQIBgAAAA==.',
Va='Valeyria:BAAANQADCgcIDQAAAA==.Valiyntha:BAAANQADCgYIBwABNQADCggICAABAAAAAA==.Vancasper:BAAANQADCgQIBAAAAA==.Varlock:BAAANQAECgQIBQAAAA==.Vasill:BAAANQADCgYICwAAAA==.',
Ve='Velari:BAAANQADCggIDgAAAA==.Velmathris:BAAANQADCggICAAAAA==.Veydh:BAAANQADCggIDgAAAA==.',
Vi='Viinnee:BAAANQADCggIDQAAAA==.Vincentlight:BAAANQADCgUICQAAAA==.Vixess:BAAANQAECgQIBAAAAA==.',
Vo='Voidpriest:BAAANQADCggICAAAAA==.Voidweaver:BAAANQADCgUICQAAAA==.Volteer:BAAANQAECgEIAQAAAA==.',
Vy='Vyara:BAAANQADCgIIAgABNQADCggIAQABAAAAAA==.Vynddradoria:BAAANQAECgQIBQAAAA==.Vyndh:BAAANQAECgQIBQAAAA==.',
Wa='Walkerbowe:BAAANQADCgQIBAAAAA==.Walt:BAAANQADCgcIBwAAAA==.Wanderin:BAAANQADCggIBAAAAA==.Waterbutcold:BAAANQADCgcIDQAAAA==.',
We='Webby:BAAANQADCggIAQAAAA==.',
Wh='Whiskerses:BAAANQADCggIDgAAAA==.Whithers:BAAANQADCgUICQAAAA==.',
Wi='Wilmer:BAAANQADCggICAAAAA==.Wilyy:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.',
Wo='Woodsylver:BAAANQADCgUICAAAAA==.Worski:BAAANQADCgQIBgAAAA==.',
Wr='Wrathalthiel:BAAANQADCgYICwABNQADCggIDQABAAAAAA==.Wratherael:BAAANQADCggIDQAAAA==.Wraîth:BAAANQAECgQIBAAAAA==.',
Wy='Wynilla:BAAANQADCgUICAAAAA==.',
Xa='Xanathar:BAAANQADCgcIDAAAAA==.Xaylia:BAAANQADCgcIDQAAAA==.',
Xo='Xolotin:BAAANQADCgMIAwAAAA==.',
Ya='Yassi:BAAANQADCggIDgAAAA==.',
Yn='Ynarii:BAAANQADCgEIAQAAAA==.Ynkdh:BAAANQAECgEIAQAAAA==.',
Yo='Yoonhee:BAAANQAECgIIAgAAAA==.',
Za='Zaghary:BAAANQADCgcIEgAAAA==.Zarik:BAAANQADCgIIAwAAAA==.',
Ze='Zebjati:BAAANQADCggIDgAAAA==.',
Zh='Zhend:BAAANQADCgcIDQAAAA==.',
Zu='Zunch:BAAANQADCgUICQAAAQ==.',
['Àz']='Àzazel:BAAANQADCgUIBQAAAA==.',
['Är']='Ärk:BAAANQADCgcIDQAAAA==.Ärmistice:BAAANQAECgIIAgAAAA==.',
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
