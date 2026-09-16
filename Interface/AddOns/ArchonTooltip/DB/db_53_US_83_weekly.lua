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

local lookup = {'Unknown-Unknown','Hunter-Marksmanship','Priest-Holy','Druid-Balance','Druid-Restoration','Paladin-Holy','Hunter-BeastMastery','Warrior-Arms','Shaman-Elemental','Paladin-Retribution','DeathKnight-Frost','Warrior-Protection','DeathKnight-Unholy','Shaman-Restoration','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction',}
local provider = {region='US',realm='EarthenRing',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abrothael:BAAANQAECgUIBQAAAA==.',
Ad='Adorèè:BAAANQAECgMIBAAAAA==.',
Ae='Aedelas:BAAANQADCgQIBAAAAA==.Aelucãrd:BAAANQADCggICAAAAA==.Aestua:BAAANQADCgQICQAAAA==.Aetheros:BAAANQAECgcIEwAAAA==.',
Ag='Agarim:BAAANQADCgQICAAAAA==.',
Ai='Airlinna:BAAANQAECgYIEAAAAA==.Airoach:BAAANQADCggIGgAAAA==.',
Ak='Akers:BAAANQADCggICwABNQAECgEIAgABAAAAAA==.',
Al='Alaraen:BAAANQAECgQIBgAAAA==.Alcremie:BAAANQAECgIIAwABNQAFFAYIDAACAAogAA==.Aleman:BAAANQADCgYIEAAAAA==.Aleve:BAAANQADCgIIAgAAAA==.Alexxandria:BAAANQADCggICwAAAA==.Aleyah:BAAANQADCggIFgAAAA==.Almarii:BAAANQAECgMIBQAAAA==.Alraune:BAAANQAECgYICwAAAA==.Alynndra:BAAANQAECgMIBQAAAA==.Alyssazoe:BAAANQADCgIIBAAAAA==.',
Am='Ambler:BAAANQADCgcIBgAAAA==.',
An='Anarionhunts:BAAANQAECgMIBQAAAA==.Andius:BAAANQADCgYIEwAAAA==.Andoric:BAAANQABCgYICAAAAA==.Anirra:BAAANQAECgMIBQAAAA==.Annaraeliri:BAAANQADCgMIAwAAAA==.',
Ap='Apert:BAAANQAECgQIBgAAAA==.Apnea:BAAANQADCgIIAgAAAA==.',
Ar='Ardenweald:BAAANQAECgYIEQAAAA==.Armyokittens:BAAANQADCgcIFAAAAA==.Arroezze:BAAANQADCgYIBQAAAA==.Arthurin:BAAANQAECgQIBAAAAA==.',
As='Ashaleth:BAAANQADCgUIBQAAAA==.Ashayo:BAAANQADCgYICQAAAA==.Astrana:BAAANQAECgUICgAAAA==.',
At='Athelstan:BAAANQADCgcIBwAAAA==.',
Au='Augkward:BAAANQADCgYIBgABNQAECgkJHAADAJodAA==.Aureldor:BAAANQADCgMIAwAAAA==.Automatic:BAAANQAECgcIEgAAAA==.Autoshot:BAAANQADCgMIBAAAAA==.',
Av='Avorik:BAAANQADCggIDgAAAA==.Avouric:BAAANQADCgUIBQAAAA==.',
Az='Azaree:BAAANQAECgQIBgAAAA==.Azndak:BAAANQADCgcIBwAAAA==.',
Ba='Baelzabob:BAAANQADCgYIEQAAAA==.Bakaran:BAAANQADCgUIBQAAAA==.Barae:BAAANQADCgYIEgAAAA==.Barboosa:BAAANQAECgEIAQAAAA==.Barcmaul:BAAANQADCggIGQAAAA==.Bathzalts:BAAANQADCgYIBQAAAA==.Baylel:BAAANQAECgMIBQAAAA==.',
Be='Belledolphin:BAAANQAECgUIBQAAAA==.Bellgold:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.Berigo:BAAANQAECgYIDAAAAA==.Bertoxulous:BAAANQADCgcIBQAAAA==.Bezvoker:BAAANQAECgIIAwAAAA==.Beárwithme:BAAANQADCgQICAAAAA==.',
Bi='Birria:BAAANQADCgQIBAAAAA==.',
Bj='Bjordrann:BAAANQADCgEIAQAAAA==.',
Bl='Blackhoofcow:BAAANQADCggICAAAAA==.Blackicewolf:BAAANQAECgcIEwAAAA==.Bleake:BAAANQADCgUIBQAAAA==.Bleunienn:BAAANQABCgYICAAAAA==.Blueberrypie:BAAANQAECgUICAAAAA==.',
Bo='Bonbarrion:BAEANQAECgYIEAAAAA==.Borbory:BAAANQAECgMIBAAAAA==.Boringhuman:BAAANQADCgcIEAAAAA==.Borlorín:BAAANQADCgYIBgAAAA==.Borogove:BAAANQADCgYIBgAAAA==.',
Br='Brasca:BAAANQAECgQIBgAAAA==.Brisketdk:BAAANQAECgIIAgAAAA==.Bruhmal:BAAANQAECgMIBAAAAA==.Brunner:BAAANQADCgEIAQAAAA==.Brynndolin:BAAANQAECgQIBgAAAA==.',
Bu='Burzolog:BAAANQAECgYIEAAAAA==.',
['Bä']='Bärk:BAABNQAECoEiAAIEAAgJURtcFwCWAgAEAAgJURtcFwCWAgAAAA==.',
Ca='Calanash:BAAANQADCgcIBwABNQAECgUICQABAAAAAA==.Calazan:BAAANQAECgUICQAAAA==.Cascious:BAAANQADCgcIBwABNQAECgkJIAAFAIUWAA==.Cazym:BAAANQADCggICAABNQAECggIBgABAAAAAA==.',
Ce='Cedarjr:BAAANQAECgMIAwAAAA==.Cef:BAAANQAECgMIBAAAAA==.Celindre:BAAANQADCgUIBwAAAA==.',
Ch='Cherrybomb:BAAANQADCgIIAgAAAA==.Chewbie:BAAANQAECgEIAQAAAA==.Chickentendi:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Chronis:BAAANQADCgYIBgAAAA==.',
Ci='Ciphon:BAAANQAECgIIAgAAAA==.Cirok:BAAANQADCgcIDQAAAA==.Civic:BAAANQADCggIDgAAAA==.',
Ck='Cklyde:BAABNQAECoEYAAIGAAkJiR8yBgBZAwAGAAkJiR8yBgBZAwAAAA==.',
Cl='Claiyre:BAAANQADCgcIDgABNQADCgcIDgABAAAAAA==.Clewis:BAAANQABCgUICAAAAA==.Clubble:BAAANQAECgMIBAAAAA==.Clumperton:BAABNQAECoEXAAIHAAgJ7hySFQDMAgAHAAgJ7hySFQDMAgAAAA==.Clãsh:BAAANQAECgIIBAAAAA==.',
Co='Cochino:BAAANQADCgYIBgAAAA==.Concentrate:BAAANQAECgQIBQAAAQ==.Connan:BAAANQAECgEIAQABNQAECgQICgABAAAAAA==.Constant:BAAANQADCggICgAAAA==.Corbesan:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Cordrann:BAAANQADCggIEwAAAA==.Coveness:BAAANQADCgIIAgAAAA==.Cowi:BAAANQAECggIEAAAAA==.',
Cr='Crasusakechi:BAAANQADCgYICQAAAA==.Crisisangel:BAAANQADCggIAgAAAA==.Cryomagus:BAAANQAECgYIEAAAAA==.',
Cu='Cuqquiform:BAAANQAECgUIEQAAAA==.',
Cy='Cylesia:BAAANQADCggIFAAAAA==.Cylthia:BAAANQADCgIIAgAAAA==.',
Da='Daemata:BAAANQAECgEIAgAAAA==.Dajinbo:BAAANQADCgcIEgAAAA==.Damons:BAAANQAECgMIAwABNQAFFAEIAQABAAAAAA==.Darchlo:BAAANQADCgEIAQAAAA==.Darkhammer:BAAANQAECgIIBAAAAA==.Darkswift:BAAANQAECgcIEwAAAA==.Darnadda:BAAANQADCgcIFQAAAA==.Darowyn:BAAANQAECgMIBAAAAA==.Dashiell:BAAANQADCgQIBwABNQAECgQIBAABAAAAAA==.Dawnflare:BAAANQADCgcIDQABNQAECgUICAABAAAAAA==.',
De='Deathryder:BAAANQADCggICAAAAA==.Deaxus:BAAANQAECgMIAwABNQAECgYIEAABAAAAAA==.Deb:BAAANQAECgMIBQAAAA==.Delailia:BAAANQADCgcIBgAAAA==.Delbelfine:BAAANQAECgcIEwAAAA==.Delfar:BAAANQADCgUIBQAAAA==.Delisomethng:BAAANQAECgQIBwAAAA==.Dellechero:BAAANQADCgYIDAAAAA==.Demilich:BAAANQADCgIIAgAAAA==.Demonra:BAAANQADCgMIAwAAAA==.Despaira:BAAANQAECgMIAwAAAA==.Dethyler:BAAANQAECgMIBAAAAA==.Devilwoman:BAAANQAECgMIBQAAAA==.Deyv:BAAANQAECgMIBAAAAA==.',
Di='Diancie:BAAANQAECgIIAgABNQAFFAYIDAACAAogAA==.Diddibeau:BAAANQAECgMIBQAAAA==.Diddiblind:BAAANQADCgMIBgABNQAECgMIBQABAAAAAA==.Diego:BAAANQADCgEIAQAAAA==.Divinezanon:BAAANQAFFAIIAwABNQAECggIEAABAAAAAA==.',
Do='Dontyagnomie:BAAANQAECgQIAwAAAA==.Doobu:BAAANQADCgcIEgAAAA==.Dooganitis:BAAANQAECgEIAQAAAA==.Dorne:BAAANQADCgcIBwAAAA==.Doruk:BAAANQAECgQIBAAAAA==.',
Dr='Dreamsoul:BAAANQABCgQIBAAAAA==.Drfeelgreat:BAAANQADCgIIAwAAAA==.',
Du='Dullahstrasz:BAAANQADCgYIBgAAAA==.Dusksorrow:BAAANQADCgUIBQAAAA==.',
Dz='Dzud:BAAANQABCgQIBAAAAA==.',
Ed='Edovard:BAAANQADCggIFAAAAA==.',
Ee='Ee:BAAANQADCgcIDAABNQADCggICAABAAAAAA==.Eeragon:BAAANQAECgMIAwAAAA==.',
El='Elentari:BAAANQABCgMIAwAAAA==.Elfshadow:BAAANQABCgQIAwAAAA==.Eliyon:BAAANQADCggIGQAAAA==.Ellarinya:BAAANQADCgMIBQAAAA==.Ellemir:BAAANQADCgYIEwAAAA==.Elshifty:BAAANQADCgcIBwABNQAECggIAQABAAAAAA==.Eltanari:BAAANQADCggIFAAAAA==.Eluera:BAAANQAECgQIBAAAAA==.Elyn:BAAANQAECgcIEQAAAA==.Elynthil:BAAANQADCgYIBgABNQAECgcIEQABAAAAAA==.',
Em='Emet:BAAANQABCgIIAgAAAA==.Emilie:BAAANQAECgEIAQAAAA==.Emunny:BAAANQAECgQIBgAAAA==.',
En='Endest:BAAANQAECgMIBAAAAA==.Enezalle:BAAANQAECgMIBAAAAA==.',
Eo='Eointhas:BAAANQAECgQIBgAAAA==.',
Ep='Ephimonk:BAAANQAECgMIBAAAAA==.',
Er='Erenyeagar:BAAANQADCgYIBgAAAA==.Ernson:BAAANQADCgQICAAAAA==.',
Eu='Euronymous:BAAANQAECgEIAQAAAA==.',
Ev='Evilandy:BAAANQAECgQIBQAAAA==.',
Fa='Faeleda:BAAANQADCgEIAQAAAA==.Fandrall:BAAANQADCgQIBgAAAA==.',
Fb='Fblthp:BAAANQAECgMIAgAAAA==.',
Fe='Felblood:BAAANQADCgYIEQAAAA==.Ferndolyn:BAAANQADCgMIAwAAAA==.Fezduin:BAAANQADCgIIAgAAAA==.',
Fi='Finnagetit:BAAANQAECgEIAgAAAA==.',
Fl='Flagonslayer:BAAANQAECgIIAgAAAA==.Flaimefu:BAAANQADCggIGAAAAA==.Floorlicker:BAAANQADCgYIBgAAAA==.Flopsie:BAAANQAECgUIBwAAAA==.Fluffystorm:BAAANQADCgYIEwAAAA==.',
Fo='Forzod:BAAANQADCgYICAAAAA==.Forzzie:BAAANQADCgYICQAAAA==.Foxheals:BAAANQADCgcIBwAAAA==.Foxymagic:BAAANQADCgcIDgAAAA==.',
Fr='Frabjous:BAAANQAECgQIBgAAAA==.Freenk:BAAANQADCgcIEQAAAA==.Freezerburn:BAAANQAECgcIEwAAAA==.',
Fu='Furn:BAAANQAECgQIBgAAAA==.Furryaz:BAAANQADCgIIAgAAAA==.Further:BAAANQAECgcIEwAAAA==.',
Fy='Fyrrek:BAAANQADCgYIDQAAAA==.',
Ga='Galadrien:BAAANQADCgYIBgAAAA==.Galavenat:BAAANQAECgMIBAAAAA==.Galroy:BAAANQADCgEIAQAAAA==.Galstan:BAAANQADCgQICAAAAA==.Garbohydrate:BAAANQADCgEIAQAAAA==.Garbolicious:BAAANQADCgIIAgAAAA==.Garbothicc:BAAANQAECgMIBQAAAA==.Garyh:BAACNQAFFIENAAIIAAYJ+x0kAQBqAgAIAAYJ+x0kAQBqAgA1AAQKgSQAAggACQnBJpcAAAAEAAgACQnBJpcAAAAEAAAA.Garyhreturns:BAAANQAECgUIBgABNQAFFAYIDQAIAPsdAA==.',
Ge='Geldeinmonch:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.Geldverdamnt:BAAANQAECgMIBAAAAA==.Gerasham:BAAANQADCgcIBwAAAA==.',
Gh='Ghost:BAAANQABCgQIBgAAAA==.Ghuramonk:BAAANQADCggICgAAAA==.',
Gi='Giacomo:BAAANQADCgYICgAAAA==.Gil:BAAANQAECgQIBAAAAA==.Gildina:BAAANQADCggIFgAAAA==.Ginggy:BAAANQAECgQICAABNQAECgkJIAAFAIUWAA==.Girafficz:BAABNQAECoEhAAIEAAkJ3CUQAQDgAwAEAAkJ3CUQAQDgAwABNQAFFAcIEgAIAKUkAA==.',
Go='Gori:BAAANQAECgQICgAAAA==.Gorin:BAAANQADCggIDAABNQAECgQIBAABAAAAAA==.',
Gr='Graelle:BAAANQADCgYIBgAAAA==.Gralle:BAAANQAECgQIBgAAAA==.Graug:BAAANQADCgQIBAABNQADCgUIBwABAAAAAA==.Gravelbeard:BAAANQADCgIIBAAAAA==.Gregory:BAAANQAFFAEIAQABNQADCgUIBwABAAAAAA==.Greyantheril:BAAANQAECgMIBAAAAA==.Greyji:BAAANQAECgcIDAAAAA==.Grumb:BAAANQAECgcIEwAAAA==.',
Gu='Guenara:BAAANQADCggIHQAAAQ==.Guillimon:BAAANQADCgQIBAABNQAECgYIDAABAAAAAA==.Gustytail:BAAANQAECgMIBAAAAA==.',
Ha='Haardrada:BAAANQAECgMIAwABNQAFFAYIDQAIAPsdAA==.Habit:BAAANQAECgYICgAAAA==.Hadrianna:BAAANQAECgMIBQAAAA==.Halanir:BAAANQADCgIIAgAAAA==.Hanzul:BAAANQAECgMIBAAAAA==.Hapless:BAAANQAECgQIBAAAAA==.Hashanir:BAAANQADCgEIAQAAAA==.Hashat:BAAANQADCgIIAgAAAA==.Hawkfoot:BAAANQADCgcIDAAAAA==.',
He='Hearthbreakr:BAAANQAECgIIAwABNQAECgkJGQAJAIQYAA==.Hellanie:BAAANQADCgQIBwAAAA==.Hellbore:BAAANQAECgUICAAAAA==.Hellchi:BAAANQAECgMIAwAAAA==.Hellinasel:BAAANQADCgUIBwAAAA==.Hemmy:BAAANQAECgYIDgAAAA==.Hermer:BAAANQADCgMIAwAAAA==.Heysham:BAAANQAECgMIBAAAAA==.Hezzakan:BAAANQADCggIFgAAAA==.',
Ho='Holykow:BAAANQAECgMIAwAAAA==.Hotspur:BAAANQAECgQIBgAAAA==.',
Hu='Huevomuerto:BAAANQADCgQICAAAAA==.Huevonyque:BAABNQAECoEZAAIIAAgJXhjXMwBsAgAIAAgJXhjXMwBsAgAAAA==.Huulgrim:BAAANQAECgMIBAABNQABCgMIAwABAAAAAA==.',
Hy='Hyejinx:BAAANQAECgUIBwAAAA==.',
Ic='Iceclaw:BAAANQADCgQIBAABNQADCgQICQABAAAAAA==.Icona:BAAANQADCgQIBAAAAA==.',
Ih='Ihiannan:BAAANQADCgYIEwABNQAECgQIBgABAAAAAA==.',
Ii='Iiarian:BAAANQAECgIIBAAAAA==.',
Il='Illisong:BAAANQADCgMIAwAAAA==.Illukana:BAAANQAECgcIDwABNQAECgkJJgAKANEhAA==.',
In='Infoxy:BAAANQAECgMIAwAAAA==.Inthra:BAAANQAECgIIAwAAAA==.',
Ir='Irimas:BAAANQADCggIFwAAAA==.',
Is='Isopope:BAAANQABCgYIBgAAAA==.Isthian:BAAANQAECgIIAwAAAA==.',
It='Itako:BAAANQADCgYIEgAAAA==.Itoldhimso:BAAANQADCggIDwAAAA==.',
Iv='Ivaldi:BAAANQADCgQIBQAAAA==.',
Ja='Jadelark:BAAANQAECgMIBQAAAA==.Javèrt:BAAANQAECgYIEAAAAA==.Jaxina:BAAANQADCgUIBwABNQAECgUIDAABAAAAAA==.Jaxordamus:BAAANQAECgUIDAAAAA==.',
Je='Jema:BAAANQAECgEIAQAAAA==.Jenilea:BAAANQAECgQIBgAAAA==.Jessaril:BAAANQAECgUIBQAAAA==.Jessbgood:BAAANQABCgIIAgAAAA==.',
Ji='Jimboree:BAAANQAECgcIEAAAAA==.Jinsu:BAAANQADCgYIFwAAAA==.Jinzeem:BAAANQADCggIFgAAAA==.Jiujitsunut:BAAANQADCgIIBAAAAA==.',
Jo='Jordend:BAAANQAECgEIAgAAAA==.Joseppii:BAAANQAECgQIBQAAAA==.',
Jp='Jpxfrd:BAAANQABCgUICAABNQADCgQIBAABAAAAAA==.',
Ju='Jungyuul:BAAANQAECgUIBQAAAA==.',
Jy='Jynnx:BAAANQADCgEIAQAAAA==.',
['Jâ']='Jâzzy:BAAANQAECgMIBAAAAA==.Jâzzý:BAAANQADCgMIAgABNQAECgMIBAABAAAAAA==.',
Ka='Kaajira:BAAANQADCgEIAQAAAA==.Kaandew:BAAANQADCggIFgAAAA==.Kailann:BAAANQAECgIIAgAAAA==.Kaorin:BAAANQADCgUIBQAAAA==.Karesta:BAAANQADCgQIBAAAAA==.Kaylith:BAAANQADCgcIEgAAAA==.Kayra:BAAANQADCgQIBgAAAA==.',
Ke='Kegelsmash:BAAANQADCgMIAwABNQAECgYIDwABAAAAAA==.Kelanansi:BAAANQADCgcIEwAAAA==.Kelanis:BAAANQADCgYIBgAAAA==.Kelel:BAAANQAECgYIDgAAAA==.Kessia:BAAANQADCggIFQAAAA==.Kessía:BAAANQADCgQIBAAAAA==.',
Kh='Khalistra:BAAANQAECgEIAQAAAA==.',
Ki='Kiroblade:BAAANQADCgUIBQABNQAECgYICwABAAAAAA==.Kiropaly:BAAANQADCgYIDgABNQAECgYICwABAAAAAA==.Kirotard:BAAANQAECgYICwAAAA==.Kisldarin:BAAANQADCgEIAQAAAA==.Kithedrael:BAAANQADCgYICQAAAA==.',
Kl='Klouded:BAAANQAECgUIBQAAAA==.',
Kn='Knuts:BAAANQADCgYICwABNQAECgYIDwABAAAAAA==.',
Ko='Koa:BAAANQAECgIIAgAAAA==.Kojakk:BAAANQAECgQIBgAAAA==.Kordac:BAAANQAECgMIBAAAAA==.Korigan:BAAANQAECgMIBQAAAA==.Korvova:BAAANQADCgEIAQAAAA==.',
Kt='Kth:BAAANQABCgMIBQAAAA==.',
Ku='Kunamashiro:BAAANQAECgEIAQAAAA==.',
Ky='Kylê:BAAANQAECgEIAQAAAA==.Kymetra:BAAANQAECgUIBQAAAA==.Kyttin:BAAANQADCgYIEwAAAA==.',
['Kä']='Kära:BAAANQADCggIDQABNQAECgQICgABAAAAAA==.',
['Kÿ']='Kÿthe:BAAANQABCgUIBwAAAA==.',
La='Ladeeda:BAAANQADCgQIBwAAAA==.Laevi:BAAANQADCgYIDQAAAA==.Lalena:BAAANQAECgIIAgAAAA==.Lawanda:BAAANQADCgEIAQABNQAECgMIBQABAAAAAA==.',
Le='Leonineone:BAAANQAECgcIEwAAAA==.Ler:BAAANQADCgYIBgABNQADCggIFQABAAAAAA==.',
Li='Lichplease:BAABNQAECoEZAAILAAgJwyMUBwD/AgALAAgJwyMUBwD/AgAAAA==.Lightlady:BAAANQADCggIFgAAAA==.Lightridge:BAAANQABCgUICQAAAA==.Lillythorne:BAAANQAECgEIAQAAAA==.Limewire:BAAANQAECgQIBAAAAA==.Litehlzonly:BAAANQAECgIIAgAAAA==.Literalcow:BAAANQABCgUIBQAAAA==.Livebeef:BAAANQADCgUIDwAAAA==.',
Lm='Lmaolock:BAAANQADCgEIAQAAAA==.',
Lo='Lohvadner:BAAANQADCgYIDwAAAA==.Lothlum:BAAANQAECgQIBAAAAA==.',
Lu='Lunacie:BAAANQADCgMIBAAAAA==.Lunalia:BAAANQAECgEIAQAAAA==.Lupen:BAAANQAECgQIBgAAAA==.Luxurria:BAAANQADCgYICQAAAA==.',
Ly='Lynlin:BAAANQAECgIIAgAAAA==.',
Ma='Magesef:BAAANQAECgMIBAAAAA==.Magnusrn:BAAANQADCgQICQAAAA==.Makinmemoist:BAAANQADCggIFAAAAA==.Malandras:BAAANQADCgEIAQAAAA==.Malandrius:BAAANQADCggIEwAAAA==.Malehei:BAAANQADCgMIAwAAAA==.Malignities:BAAANQAECgUICgAAAA==.Malthruin:BAAANQADCggIHAABNQAECgYIEAABAAAAAA==.Manajamba:BAAANQAECgMIAwAAAA==.Manamidget:BAAANQADCgUIBQAAAA==.Mancubus:BAAANQAECgUIDQAAAA==.Marosenth:BAAANQADCggIDAAAAA==.Marqadin:BAAANQADCgIIBAAAAA==.Maxidorf:BAAANQADCgYIBgAAAA==.',
Me='Meleeno:BAAANQADCgIIBAAAAA==.Meush:BAABNQAECoEmAAIKAAkJ0SEqCwBTAwAKAAkJ0SEqCwBTAwAAAA==.Mewkow:BAAANQADCgYIFgAAAA==.Mewsa:BAAANQAECgQIBgAAAA==.',
Mi='Micha:BAAANQADCgcIDAAAAA==.Midgee:BAAANQADCggIEwAAAA==.Minimigraine:BAAANQAECgQIBgAAAA==.Miniroar:BAAANQADCgMIAwAAAA==.Miphisto:BAAANQADCgYIEAAAAA==.Mirandee:BAAANQADCgcIEwAAAA==.Mishrani:BAAANQADCggIFgAAAA==.Mite:BAAANQADCggICgAAAA==.',
Mo='Moa:BAAANQADCgcIEQAAAA==.Molding:BAAANQAECgQIBgAAAA==.Mollusk:BAAANQADCgQIBgAAAA==.Monis:BAAANQAECgYICwAAAA==.Montessarah:BAAANQADCgcIEAAAAA==.Moonstôrm:BAAANQADCgYIBgAAAA==.Mordraug:BAAANQADCggIDgAAAA==.Morinoe:BAAANQAECgMIBQAAAA==.Mornwalker:BAAANQAECgMIBAAAAA==.',
Mu='Mudelf:BAAANQADCgYIDAAAAA==.Mumra:BAAANQAECgUICgABNQAECgUIEQABAAAAAA==.',
My='Mysticc:BAAANQADCgYIDwAAAA==.Myxii:BAAANQAECgIIAgAAAA==.',
['Mà']='Màdrigal:BAAANQADCgcIFAAAAA==.',
['Mí']='Míckey:BAAANQAECgMIBAAAAA==.',
['Mÿ']='Mÿthunn:BAAANQAECgIIAgAAAA==.',
Na='Nadia:BAAANQADCgcIBwAAAA==.Nagratz:BAAANQAECgMIBAAAAA==.Naichingeru:BAAANQADCgYIEwAAAA==.Nalu:BAAANQADCgYIBgAAAA==.Napalmo:BAAANQADCgQIBQAAAA==.Naterra:BAAANQAECgUICAAAAA==.',
Ne='Necessities:BAAANQADCggIHQAAAA==.Necrill:BAAANQAECgUICQAAAA==.Neirwind:BAAANQADCggIEAAAAA==.',
Ni='Nichiwa:BAAANQADCggIFQAAAA==.Niladros:BAAANQADCgcICwAAAA==.Nirazend:BAAANQADCgQIBQAAAA==.Nisaam:BAAANQADCgMIBgAAAA==.Niteterror:BAAANQAECgMIBQAAAA==.',
Nl='Nloc:BAAANQADCgYIDAAAAA==.',
No='Nolmac:BAAANQADCggIEwAAAA==.Nomesacan:BAAANQADCgQIBAAAAA==.Nosleep:BAAANQADCgYIEwAAAA==.Novelia:BAAANQADCgIIAgAAAA==.',
Nu='Nuglife:BAAANQADCgYICwAAAA==.',
['Nà']='Nàtureuscary:BAAANQAECgQIBQAAAA==.',
Ob='Obtusepanda:BAAANQAECgMIBQAAAA==.',
Oc='Ocupocorrer:BAAANQADCgYIBgAAAA==.',
Of='Offthechaeni:BAAANQADCgUIBQAAAA==.',
Og='Ograndoe:BAAANQAECgcIEAAAAA==.',
Oh='Ohanzee:BAAANQADCgYIDQAAAA==.Ohku:BAAANQADCggIGQAAAA==.Ohok:BAAANQAECgQIBQAAAA==.',
Oi='Oisin:BAAANQADCggIFgAAAA==.',
Om='Omathra:BAAANQAECgYIEAAAAA==.',
On='Onikai:BAAANQAECgIIAgAAAA==.Onruk:BAAANQAECgQIBAAAAA==.',
Op='Ophina:BAAANQAECgEIAgAAAA==.',
Or='Oreo:BAAANQADCggICAAAAA==.Orgish:BAAANQAECgIIAgAAAA==.Orieda:BAAANQADCgUIBQAAAA==.Orihime:BAAANQADCgYIBgAAAA==.',
Os='Osage:BAAANQAECgUICQAAAA==.',
Ox='Oxidising:BAAANQAECgYIDQAAAA==.',
Pa='Padrone:BAAANQADCgUIDQAAAA==.Paladullahan:BAAANQAECgQIBQAAAA==.Pawthos:BAAANQADCgYICgAAAA==.',
Pe='Pennonteller:BAAANQADCgIIBAAAAA==.Pennydredful:BAAANQABCgYIBwAAAA==.Perplnuggetz:BAAANQAECgEIAQAAAA==.Pewpewmcgraw:BAAANQAECgUIBwAAAA==.',
Pl='Plaguehart:BAAANQAECgIIAgAAAA==.Plagueniss:BAABNQAECoEZAAIMAAkJ+SLyAACfAwAMAAkJ+SLyAACfAwAAAA==.',
Po='Pompino:BAAANQABCgQIBAAAAA==.',
Pr='Primø:BAAANQAECgQIBgAAAA==.',
Ps='Psychó:BAAANQAECggICAAAAA==.Psylänce:BAAANQAECgYIDgAAAA==.',
Pu='Puerile:BAAANQADCggIDwAAAA==.Purplêlotus:BAABNQAECoEcAAIHAAcJihL5PQAAAgAHAAcJihL5PQAAAgAAAA==.Purrl:BAAANQADCggIFAAAAA==.',
Py='Pyana:BAAANQADCgcIDQAAAA==.',
['Pö']='Pöppy:BAAANQAECgQIAwAAAA==.',
Qs='Qserie:BAAANQADCgYIEQAAAA==.',
Ra='Rabid:BAAANQADCgYIDAABNQAECgcIEwABAAAAAA==.Racelon:BAAANQAECgcIEgAAAA==.Raidgriefer:BAAANQAECgcIDgAAAA==.Raistlín:BAAANQADCgcICwAAAA==.Rakwell:BAAANQADCggIHQAAAA==.Raloth:BAAANQABCgEIAQAAAA==.Ramadin:BAAANQADCgEIAQABNQAECgcIEwABAAAAAA==.Ramil:BAAANQAECgMIBAAAAA==.Ramorash:BAAANQADCgYICQAAAA==.Randomeena:BAAANQADCgYIBgAAAA==.Raptorbait:BAAANQADCgQIBQAAAA==.',
Re='Reannis:BAAANQADCgMIAwAAAA==.Redvoid:BAAANQAECgQICAABNQAECgkJHwACAJQkAA==.Rekane:BAAANQAECgEIAgAAAA==.Relyste:BAAANQADCggIDgAAAA==.Renala:BAAANQAECgYIDwAAAA==.Reteril:BAAANQAECgUIDgAAAA==.Reyis:BAAANQAECgQIBgAAAA==.Reyvinite:BAAANQAECgEIAQAAAA==.',
Rh='Rhodaria:BAAANQADCggIGAAAAA==.',
Ri='Ricepicks:BAAANQAECgYICgABNQADCgYIBgABAAAAAA==.Rilaka:BAAANQADCgcIFAAAAA==.Rintaladin:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Rissu:BAAANQAECgYIDQAAAA==.Risuu:BAAANQAECgcICQAAAA==.',
Ro='Roasted:BAAANQAECgMIBAAAAA==.Roka:BAAANQABCgIIAgAAAA==.Ronathan:BAAANQAECgMIBQAAAA==.Roper:BAAANQAECgYIDAAAAA==.Roshen:BAAANQADCgcIFwAAAA==.Rosselyne:BAAANQADCgYIBgABNQAECgYIDQABAAAAAA==.Rouzou:BAAANQAECgMIBAAAAA==.',
Rr='Rrun:BAAANQAECgUIBQAAAA==.',
Ru='Rukia:BAAANQAECgYIEQAAAA==.Rumgold:BAAANQAECgQIBAAAAA==.Rustins:BAAANQADCgYICgAAAA==.',
Ry='Rynhart:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.',
Sa='Sabele:BAAANQADCgEIAQABNQADCgYICQABAAAAAA==.Sadie:BAAANQADCgUIDgAAAA==.Saintmichael:BAAANQADCgUICgAAAA==.Sapphism:BAACNQAFFIEMAAMCAAYJCiDAAQDiAQACAAUJ8h/AAQDiAQAHAAEJhiBnDABvAAA1AAQKgSQAAgIACQnZJIEBALcDAAIACQnZJIEBALcDAAAA.Sarai:BAAANQABCgMIBAAAAA==.Sarbev:BAAANQAECgcIEgAAAA==.Saskwatch:BAABNQAECoEgAAIFAAkJhRZyCwB7AgAFAAkJhRZyCwB7AgAAAA==.Savat:BAAANQAECgQIBQABNQAECgUICQABAAAAAA==.Sayoko:BAAANQAECgQICgAAAA==.Sayris:BAAANQAECgUIDAAAAA==.',
Sc='Scarymonster:BAAANQADCgIIAgAAAA==.Sckratchxx:BAAANQAECgMIBAAAAA==.Scoochacho:BAAANQAECgQICAAAAA==.',
Se='Selaria:BAAANQADCgcICgAAAA==.Senhunter:BAAANQAECgMIBgAAAA==.Senmaster:BAAANQADCggIEQABNQAECgMIBgABAAAAAA==.Sentrollock:BAAANQABCgIIAgABNQAECgMIBgABAAAAAA==.Seradiin:BAAANQADCgEIAQAAAA==.Sereknight:BAAANQADCgQIBAAAAA==.',
Sh='Shakers:BAAANQAECgcIEwAAAA==.Shaleron:BAAANQADCgcICgAAAA==.Shamarq:BAAANQADCgYIEwAAAA==.Shamtastyc:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Shapewalker:BAAANQAECgYIEAAAAA==.Shayla:BAAANQADCgQIBAAAAA==.Shaylina:BAAANQAECgMIBwAAAA==.Shaylune:BAAANQADCgUIBQABNQAECgMIBwABAAAAAA==.Sheba:BAAANQABCgEIAQAAAA==.Shendhi:BAAANQABCgQIBAAAAA==.Sheoby:BAAANQABCgMIBAAAAA==.Shiftcen:BAAANQAECgEIAQAAAA==.Shintazhi:BAAANQAECgMIBQAAAA==.Shirkan:BAAANQAECgcIEgAAAA==.Shojobeat:BAAANQAECgQIBAAAAA==.Shreddedbeef:BAAANQAECgQIBAAAAA==.Shwartz:BAAANQADCgQIBAAAAA==.',
Si='Simplicity:BAAANQADCgYIGQAAAA==.Sindrii:BAAANQADCgYICQAAAA==.Sinhoi:BAAANQADCgUIBQABNQADCgYICQABAAAAAA==.Sinku:BAAANQADCggIDwAAAA==.Sinza:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.Sixp:BAAANQADCgMIBAABNQAECgkJGQAJAIQYAA==.',
Sk='Skadooshh:BAAANQADCgYIBgABNQAECgQICgABAAAAAA==.Skarray:BAEANQAECgMIBAAAAA==.',
Sl='Slyraxis:BAAANQAECgMIBAAAAA==.',
So='Soleirra:BAAANQADCgEIAQABNQADCggICAABAAAAAA==.Sonas:BAAANQADCgcIBwAAAA==.Soohainao:BAAANQADCgcIDwABNQAECgkJGQAJAIQYAA==.Sorador:BAAANQADCgQIBwAAAA==.',
Sp='Spargelfürze:BAAANQADCgIIBAAAAA==.Spellgibson:BAAANQAECgUICAAAAA==.Spiara:BAAANQABCgQIBAAAAA==.Spiraa:BAAANQADCggICAAAAA==.Spyroh:BAAANQAECgQIBgAAAA==.',
St='Stealthgoat:BAAANQABCgIIAgAAAA==.Stinkyfeets:BAAANQABCgEIAQAAAA==.Stoogle:BAAANQAECggIEgAAAA==.Stormbrook:BAAANQAECgQIBgAAAA==.Stoutlager:BAAANQADCgYIBgAAAA==.Sturmdorf:BAAANQADCggIEQAAAA==.',
Su='Suhli:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.Sulfrick:BAAANQADCgYIEwAAAA==.Summannuz:BAAANQADCgIIAgAAAA==.',
Sv='Svurg:BAAANQADCggIGgAAAA==.',
Sw='Sweetchi:BAAANQAECgMIBAAAAA==.',
Sy='Sybria:BAAANQADCgcIDgAAAA==.Sykko:BAAANQAECgIIAgAAAA==.Sylea:BAAANQAECgIIAgAAAA==.Sylverhunter:BAAANQABCgcICQABNQADCggIFwABAAAAAA==.Symet:BAAANQADCgYIDwAAAA==.',
['Så']='Såturn:BAAANQAECgMIAwAAAA==.',
Ta='Takaria:BAAANQAECgIIAgAAAA==.Takaris:BAAANQADCgcIBwAAAA==.Tal:BAEANQAECgIIAgAAAA==.Tankdium:BAAANQAECgEIAQAAAA==.Tapcon:BAAANQADCgYIFgAAAA==.Tape:BAAANQADCgcIBwAAAA==.Tarlas:BAAANQAECgQIBQAAAA==.Tayllore:BAAANQAECgQIBgAAAA==.',
Te='Tearsheet:BAAANQADCgYIDQABNQAECgQIBgABAAAAAA==.Terah:BAAANQAECgUIBgABNQAECgkJFwANAGMjAA==.Terendelev:BAAANQAECgYIEAAAAA==.Terrador:BAAANQAECgQIBAAAAA==.Terramortua:BAABNQAECoEXAAINAAkJYyMzBACVAwANAAkJYyMzBACVAwAAAA==.',
Th='Thalassairi:BAAANQADCgMIAwABNQAECgMIBQABAAAAAA==.Thaugtless:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.Thelonius:BAAANQAECgQIBgAAAA==.Therocksays:BAAANQAECgQIBgAAAA==.Thindead:BAAANQADCgIIAgABNQAECgYIDwABAAAAAA==.Thinloc:BAAANQAECgYIDwAAAA==.Thinpal:BAAANQADCgIIAgABNQAECgYIDwABAAAAAA==.Thragge:BAEANQAECgMIBAAAAA==.Thronjak:BAAANQAECgQIBgAAAA==.Thunderfury:BAAANQAECgMIAwAAAA==.',
Ti='Tidepod:BAAANQADCggIEAAAAA==.Tienlong:BAAANQABCgcIDQAAAA==.Tipride:BAABNQAECoEZAAMJAAkJhBh6KgAnAgAJAAcJwRp6KgAnAgAOAAkJrA17LQAIAgAAAA==.Tiradis:BAAANQADCgMIAwAAAA==.Tiralie:BAAANQAECgQIBAAAAA==.Tiryl:BAAANQADCggIEQAAAA==.',
Tn='Tnama:BAAANQADCgIIAgAAAA==.',
To='Togashi:BAAANQAECgQIBAAAAA==.Tolipes:BAAANQADCgYIBgAAAA==.Toogodly:BAAANQADCgcIDQAAAA==.Torent:BAAANQADCggIGAAAAA==.Toshinori:BAAANQADCgIIAgAAAA==.Totemdáddy:BAAANQAECgEIAwAAAA==.Tovëlo:BAAANQADCggIDgAAAA==.',
Tr='Treelight:BAAANQADCgEIAQAAAA==.Trehugga:BAAANQADCgcIBwAAAA==.Trinogra:BAAANQAECgcIEwAAAA==.Trunks:BAAANQAECgMIBQABNQAECgQIBwABAAAAAA==.Trystern:BAAANQAECgQIBgAAAA==.',
Tu='Turmeric:BAAANQADCggIEgABNQADCggIGgABAAAAAA==.',
['Tä']='Tänya:BAAANQAECgQIBgAAAA==.',
Uh='Uhoh:BAAANQADCgUIBQAAAA==.',
Ul='Ultar:BAAANQAECgcIEgAAAA==.Ultodeesavag:BAAANQAECgMIBQAAAA==.Ultradeath:BAAANQADCggICAAAAA==.',
Un='Undeadshaman:BAAANQAECgEIAgAAAA==.Unvdi:BAAANQADCggIFAAAAA==.',
Va='Vaderrage:BAAANQAECgYIBgAAAA==.Valeyria:BAAANQADCggIGwAAAA==.Valiyntha:BAAANQADCgYIDQABNQAECgQICAABAAAAAA==.Valri:BAAANQADCgQIBAAAAA==.Vancasper:BAAANQADCggIDAAAAA==.Varl:BAAANQADCgMIAwABNQAECgkJFwAPAM8fAA==.Varlock:BAABNQAECoEXAAQPAAkJzx+IGgCSAgAPAAcJFB+IGgCSAgAQAAQJCSDOBwBFAQARAAQJIRL6JQALAQAAAA==.Vasill:BAAANQAECgMIAwAAAA==.',
Ve='Velari:BAAANQAECgQIBgAAAA==.Velmathris:BAAANQAECgIIAgAAAA==.Ventnor:BAAANQADCgIIAgAAAA==.Veydh:BAAANQAECgQIBwAAAA==.Veymina:BAAANQADCgYIDAABNQAECgQIBwABAAAAAA==.',
Vi='Viinnee:BAAANQAECgQIBgAAAA==.Vilehart:BAAANQADCgMIAgABNQAECgIIAgABAAAAAA==.Vilya:BAAANQADCgYIBgAAAA==.Vincentlight:BAAANQADCggIFwAAAA==.Vixess:BAAANQAECgcIEgAAAA==.',
Vo='Voidpriest:BAAANQADCggICAAAAA==.Voidweaver:BAAANQADCgUICQAAAA==.Volteer:BAAANQAECgYIDgAAAA==.',
Vy='Vyara:BAAANQADCgIIAgABNQAECgQIBwABAAAAAA==.Vynddradoria:BAAANQAECgYIEAAAAA==.Vyndh:BAAANQAECgcIEwAAAA==.Vynlock:BAAANQAECgEIAQAAAA==.',
Wa='Walkerbowe:BAAANQADCggICwAAAA==.Walt:BAAANQAECgIIAwAAAA==.Wanderin:BAAANQAECgIIAgAAAA==.Waterbutcold:BAAANQAECgEIAQAAAA==.Waysmomtwo:BAAANQADCgYIBgAAAA==.',
We='Webby:BAAANQAECgQIBwAAAA==.',
Wh='Whiskerses:BAAANQAECgUICQAAAA==.Whithers:BAAANQADCggIFQAAAA==.',
Wi='Wilmer:BAAANQADCggIDQAAAA==.Wilyy:BAAANQAECgQIBAABNQAECgcIEwABAAAAAA==.Winterchild:BAAANQADCgIIAgAAAA==.',
Wo='Woodsylver:BAAANQADCggIFwAAAA==.Worski:BAAANQADCggIEQAAAA==.',
Wr='Wrathalthiel:BAAANQADCggIGQABNQAECgEIAQABAAAAAA==.Wratherael:BAAANQADCggIDQABNQAECgEIAQABAAAAAA==.Wraîth:BAAANQAECgUIDQAAAA==.',
Wy='Wynilla:BAAANQADCgYIFAAAAA==.',
Xa='Xanathar:BAAANQAECgMIBQAAAA==.Xaphoris:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.Xayleficent:BAAANQADCgYIBgAAAA==.Xaylia:BAAANQAECgQIBgAAAA==.',
Xo='Xolotin:BAAANQADCgMIAwAAAA==.',
Ya='Yassi:BAAANQAECgMIBAAAAA==.',
Ye='Yelignar:BAAANQADCgEIAQAAAA==.',
Yn='Ynarii:BAAANQADCgQIBQAAAA==.Ynkdh:BAAANQAECgEIAQABNQAECggIAwABAAAAAA==.',
Yo='Yoonhee:BAAANQAECgYIDQAAAA==.',
Yu='Yura:BAAANQADCgQIBQAAAA==.Yurtrus:BAAANQAECgIIAgAAAA==.',
Za='Zaghary:BAAANQAECgMIBgAAAA==.Zaphor:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Zarik:BAAANQADCgIIAwAAAA==.',
Ze='Zebjati:BAAANQAECgMIBAAAAA==.',
Zh='Zhend:BAAANQAECgMIBAAAAA==.',
Zu='Zunch:BAAANQADCggIGAAAAQ==.',
['Àz']='Àzazel:BAAANQAECgUICAAAAA==.',
['Är']='Ärk:BAAANQAECgMIBAAAAA==.Ärmistice:BAAANQAECgUICwAAAA==.',
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
