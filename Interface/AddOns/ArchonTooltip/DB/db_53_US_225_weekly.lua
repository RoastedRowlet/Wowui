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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Warlock-Affliction','Warrior-Arms','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Priest-Shadow','Warlock-Destruction','DeathKnight-Frost','Warrior-Protection','Mage-Arcane','Paladin-Retribution','Shaman-Restoration','Evoker-Preservation','DeathKnight-Unholy','Paladin-Holy',}
local provider = {region='US',realm='Trollbane',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Acroin:BAAANQADCgQIBAAAAA==.',
Ad='Adeliz:BAAANQAECgMIBQAAAA==.Adorana:BAAANQADCgQIBAAAAA==.Adrunk:BAAANQAECgcIEgAAAA==.',
Ae='Aeloesh:BAAANQADCgUICAAAAA==.Aelyra:BAAANQADCgYICAAAAA==.Aenatheon:BAAANQAECgMIAwAAAA==.',
Ag='Aggrum:BAAANQAECgMIAwAAAA==.',
Ah='Ahexutroll:BAAANQAECgQIBAAAAA==.',
Ai='Aiur:BAAANQADCggIGQAAAA==.',
Ak='Akredfox:BAAANQAECgQIBwAAAA==.',
Al='Alexaviah:BAAANQAECgQIBwAAAA==.Alicedelight:BAAANQAECgQIBwAAAA==.Alwaysburnt:BAAANQAECgIIAgAAAA==.Alwayscooked:BAAANQADCgIIAgAAAA==.Alwaysrolled:BAAANQABCgQIBAAAAA==.',
Am='Amabeast:BAAANQADCgUIBQAAAA==.Amanitin:BAAANQADCgQIBAAAAA==.Amisia:BAAANQADCggIGwAAAA==.',
An='Anathas:BAAANQAECgQICAAAAA==.Ancestor:BAAANQADCgEIAQAAAA==.Angelfelis:BAAANQAECgYIEQAAAA==.Angelgoblin:BAAANQADCgQIBQAAAA==.Angriff:BAAANQADCggIDgAAAA==.Angrybeavor:BAAANQAECgQIBQAAAA==.Anuke:BAAANQADCgcIBwAAAA==.',
Ao='Aonaar:BAAANQADCgYIEgAAAA==.',
Ar='Archdemon:BAAANQAECgcICwAAAA==.Arkroot:BAAANQADCggIDwAAAA==.Arlock:BAAANQADCggICAAAAA==.Arsy:BAAANQADCgYICwAAAA==.',
As='Ashidpriest:BAEANQAECgYIEAAAAA==.Ashtoreth:BAAANQAECgEIAQAAAA==.Assukun:BAAANQAECgYIDgAAAA==.Async:BAAANQAECgUIBQAAAA==.',
At='Ati:BAAANQADCgYIBgAAAA==.',
Au='Aurá:BAAANQADCgIIAgAAAA==.Autoattack:BAAANQADCgcIBwAAAA==.',
Ax='Axethegrippa:BAAANQAECgUICgABNQAFFAEIAQABAAAAAA==.Aximumeffort:BAAANQADCgYIBgABNQAFFAEIAQABAAAAAA==.',
Ba='Baddmojo:BAAANQADCgQIBAAAAA==.Badmac:BAAANQAECgYIEAAAAA==.Baelliman:BAAANQAECgcICgAAAA==.Baium:BAAANQAECgEIAgABNQAECgQIBwABAAAAAA==.Bakemono:BAAANQABCgYICwAAAA==.Bakora:BAAANQADCggIFAAAAA==.Banishedfate:BAAANQAECgQIBgAAAA==.Banishedform:BAAANQADCgYICgABNQAECgQIBgABAAAAAA==.Banishedholy:BAAANQADCgYIDAABNQAECgQIBgABAAAAAA==.Baozi:BAAANQAECgQIBQABNQAECgQIBwABAAAAAA==.Barelyholy:BAAANQAECgUIBwAAAA==.Barf:BAAANQADCgUIBQABNQAECgQIBwABAAAAAA==.Barrendar:BAAANQADCgIIAgAAAA==.Bartholamew:BAAANQADCgUIBwAAAA==.',
Be='Bearballz:BAAANQADCgIIAgAAAA==.Beardey:BAAANQADCgUIBQAAAA==.Berry:BAAANQAECgYIDgAAAA==.Besneakies:BAAANQAECgQIBwAAAA==.',
Bi='Bigdamfred:BAAANQADCgEIAQAAAA==.Binnford:BAAANQADCgYIEQAAAA==.',
Bl='Blackfang:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Blaqball:BAAANQADCgUIBQAAAA==.',
Bo='Bottombish:BAAANQADCggICAAAAA==.Boulderjaw:BAAANQAECgUICAAAAA==.Boxeybrown:BAAANQAECgUIEQAAAA==.',
Br='Braised:BAAANQAECgUICgAAAA==.Brbdeported:BAAANQAECgIIAgAAAA==.Breakadakeys:BAAANQAECgYIDwAAAA==.Breccia:BAAANQADCggIFwAAAA==.Brutanious:BAAANQADCgcIDwABNQAECgMIAwABAAAAAA==.',
Bu='Bubbalicous:BAAANQAECggIBgAAAA==.Bubblebro:BAAANQAECgQIBQAAAA==.Buffwarrior:BAAANQAECgUICQAAAA==.Bustamoon:BAAANQADCggIDQAAAA==.Butterface:BAAANQAECgEIAQAAAA==.',
['Bà']='Bàckstabbath:BAAANQADCgMIAwAAAA==.',
Ca='Caeruleus:BAAANQADCgcIBwAAAA==.Cammikins:BAEANQAECgcIEAAAAA==.Cantmilkem:BAAANQADCgIIAgAAAA==.Capellaz:BAAANQAECgQIBwAAAA==.Capriestson:BAAANQAECgUICgAAAA==.Casandra:BAAANQAECgUICAAAAA==.Cassiopeias:BAAANQADCgUIBQAAAA==.',
Ce='Celerynn:BAAANQADCgUICAAAAA==.Celestaura:BAAANQAECgMIAwAAAA==.Cenerald:BAAANQADCggICAAAAA==.Centares:BAAANQADCgYICAAAAA==.',
Ch='Charlutes:BAAANQADCggIFQAAAA==.Chekzy:BAAANQADCggIEwAAAA==.Chichii:BAAANQAECgMIBAAAAA==.Chilis:BAAANQADCgcIBwABNQAECgYICAABAAAAAA==.Chiyuki:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.Choasman:BAAANQADCgYICgAAAA==.Chocolate:BAAANQADCgUICAAAAA==.Chudpath:BAAANQAECgQIBwABNQAECgcIEgABAAAAAA==.',
Cl='Cleome:BAAANQABCgEIAQAAAA==.',
Co='Coorsenjoyer:BAEANQAFFAIIBAAAAA==.Copakid:BAAANQAECgMIBQAAAA==.Cowlie:BAAANQAECgYIDgAAAA==.Coøkiewizard:BAAANQADCgEIAQAAAA==.',
Cr='Crippy:BAAANQAECgQIBwABNQADCgIIAgABAAAAAA==.Crippypal:BAAANQAECgUIBwABNQADCgIIAgABAAAAAA==.Crippyx:BAAANQADCgIIAgAAAA==.Crowls:BAAANQADCgMIAwAAAA==.Cruelwar:BAAANQAECgYICgAAAA==.',
Cu='Cuckcmder:BAAANQAECgQIBAAAAA==.',
Da='Daffodil:BAAANQADCgEIAQAAAA==.Daggoth:BAAANQAECgcIDAAAAA==.Dalrak:BAAANQAECgYIEAAAAA==.Dandarth:BAAANQADCgMIAwAAAA==.Danemos:BAAANQADCgEIAQABNQAECgkJGQACAN0bAA==.Dante:BAAANQAECgQIBAABNQAECgUICQABAAAAAA==.Darkendelf:BAAANQAECgQIBQAAAA==.Darkothy:BAAANQAECgMIAwAAAA==.Darkvision:BAAANQAECgEIAQAAAA==.Dasdann:BAAANQADCgUIBQAAAA==.Datshammy:BAAANQADCgUIBQAAAA==.Datvoodoomon:BAAANQAECgcIEgAAAA==.Daïn:BAAANQAECgYIBgAAAA==.',
Dc='Dcaý:BAAANQADCgQIBQABNQAECgEIAQABAAAAAA==.',
De='Deadboii:BAAANQADCggICAAAAA==.Deadjuggalo:BAAANQADCgcIEAAAAA==.Deadlyfaith:BAAANQADCgYICAAAAA==.Deadstep:BAAANQAECgQIBAAAAA==.Deathzy:BAAANQADCgIIAgAAAA==.Deitzz:BAAANQADCgQIBAAAAA==.Deleralia:BAAANQAECgYIDAAAAA==.Demontopher:BAABNQAECoEcAAIDAAkJNiYGAAD/AwADAAkJNiYGAAD/AwAAAA==.Derodrayne:BAAANQADCgYIBwAAAA==.Deshaler:BAAANQADCgcIBwAAAA==.Devoidshield:BAAANQAECgIIAgAAAA==.',
Di='Dicon:BAAANQADCgYIBgAAAA==.Dieric:BAAANQAECgMIBAAAAA==.Dinkle:BAAANQADCgMIAwABNQAECgQIBAABAAAAAA==.Dividian:BAAANQAECgUICQAAAA==.',
Do='Dorastrain:BAAANQAECgYIDQAAAA==.',
Dr='Dracovoid:BAAANQADCgYIDAABNQAECgQIBQABAAAAAA==.Dragondees:BAAANQADCgQIBAAAAA==.Dragonwyck:BAAANQAECgQIBAAAAA==.Draytheus:BAAANQAECgMIAwAAAA==.Dripping:BAAANQAECgQICAAAAA==.Dromai:BAAANQADCgQIBAAAAA==.',
Du='Duhdotsbruh:BAAANQAECgQIBAAAAA==.Duugan:BAAANQADCgQIBAAAAA==.',
Ed='Edgarj:BAAANQADCgEIAQAAAA==.',
Ek='Eklipsch:BAAANQADCggIDwAAAA==.',
El='Eld:BAAANQABCgYIBwAAAA==.Electabuzz:BAEANQADCgcIBwABNQAECgkJHgAEAAocAA==.Electrocute:BAAANQADCgMIAwAAAA==.Electrocutey:BAAANQAECgQIBwAAAA==.Elein:BAAANQADCgEIAQAAAA==.Eleman:BAAANQADCggIDAAAAA==.Elfclover:BAAANQAECgYIEAAAAA==.Elijahx:BAAANQAECgYICwAAAA==.Elijay:BAAANQAECgUIBwAAAA==.Eljayye:BAAANQADCgYIEQAAAA==.',
Em='Emisha:BAAANQADCgIIAgAAAA==.Emmshunter:BAAANQAECgYIBgAAAA==.',
En='Envi:BAAANQAECgEIAQAAAA==.',
Ep='Epicdemise:BAAANQADCggICQAAAA==.Epicdemon:BAAANQADCgYIBwAAAA==.Epicwarlock:BAAANQADCggIDQAAAA==.Epona:BAAANQAECgUIEAAAAA==.',
Er='Erzá:BAAANQAECgQIBgAAAA==.',
Es='Espina:BAAANQADCgUIBQAAAA==.',
Et='Eterna:BAAANQAECgQIAwAAAA==.',
Ev='Eveilyn:BAAANQAECgMIAwAAAA==.Evileye:BAAANQADCgYIBgAAAA==.',
Ex='Exarchamus:BAAANQAECgUIEQAAAA==.',
Fa='Facemelt:BAAANQAECgYIDAAAAA==.Farfy:BAAANQAECgYIDgAAAA==.Fartsmagoo:BAAANQAECgQIBQAAAA==.Faykan:BAAANQAECgMIBAAAAA==.',
Fe='Fedrameda:BAAANQAECgUICgAAAA==.Felix:BAAANQAECgQIBwAAAA==.Fellender:BAAANQADCggIJwAAAA==.Fermented:BAAANQAECgYIDgAAAA==.',
Fi='Fizzle:BAAANQADCgQIBgAAAA==.',
Fl='Flintstones:BAAANQAECgcIEAAAAA==.Fluffykiitty:BAAANQADCgEIAQAAAA==.',
Fo='Fowlplay:BAAANQADCgYIEAAAAA==.Foxbox:BAAANQAECgEIAQAAAA==.',
Fr='Frostedhoof:BAAANQADCggICAABNQAECgkJGwAFAC4eAA==.',
Fu='Fujee:BAAANQAECgYICwAAAA==.Funkyt:BAAANQAECgMIBQAAAA==.Furrysona:BAAANQADCgcIBwABNQAECgcIEgABAAAAAA==.',
['Fâ']='Fâlooga:BAAANQAECgUICQAAAA==.',
Ga='Gaidine:BAAANQADCgMIAwAAAA==.Galadriael:BAAANQAECgYIDgAAAA==.Galtan:BAAANQADCggIGwAAAA==.Garrod:BAAANQAECgQIBAAAAA==.Gattsu:BAAANQAECgIIAgAAAA==.',
Ge='Gennil:BAAANQAECggIEgAAAA==.Gestella:BAAANQAECgQIBQAAAA==.Gevo:BAAANQAECgUICAAAAA==.',
Gi='Gineselle:BAAANQAECgEIAQAAAA==.Giveemhail:BAAANQADCgMIAwABNQAECgkJGAACAK8eAA==.',
Gl='Gloomblade:BAABNQAECoEaAAMGAAkJGx0aBQAMAwAGAAkJGx0aBQAMAwAHAAEJVAkHSQA8AAAAAA==.',
Gn='Gnomepimp:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Go='Gojìra:BAAANQAECgEIAgAAAA==.Goragaia:BAAANQAECgIIAwAAAA==.Gorbencleap:BAAANQABCgMIAwAAAA==.Gorion:BAAANQADCgQIBAAAAA==.',
Gr='Graypelt:BAAANQADCgUIBQAAAA==.Grayscale:BAAANQADCgYICgAAAA==.Greyseer:BAAANQAECgMIBQAAAA==.Grica:BAAANQADCgEIAQAAAA==.',
Gu='Guymontag:BAAANQAECgUIEQAAAA==.',
Ha='Halston:BAAANQADCgEIAQABNQAECgUICAABAAAAAA==.Hammergobrr:BAAANQABCgQIBAAAAA==.Harbard:BAAANQAECgYICwAAAA==.Hasselhøøf:BAAANQAECgYICwAAAA==.Hawkeyeik:BAAANQAECgMIAwAAAA==.Hawthorne:BAAANQAECgUICAAAAA==.Hayywaffle:BAAANQADCggIDAAAAA==.',
He='Hellothere:BAAANQAECgYICwAAAA==.Hellren:BAAANQADCgMIAwAAAA==.Helmet:BAAANQADCgQIBAAAAA==.',
Hi='Hikons:BAAANQAECgUIDAABNQAECgYIDQABAAAAAA==.Hinkle:BAAANQAECgQIBAAAAA==.',
Ho='Hobojoe:BAAANQAECgQIBAAAAA==.Holysage:BAAANQADCgcIBwAAAA==.Holytoad:BAAANQADCgYIBgAAAA==.Hopsquash:BAAANQADCgQIBAAAAA==.Hopstop:BAAANQAECgQIBwAAAA==.',
Hu='Hughass:BAAANQADCgYIEgABNQAECgMIBQABAAAAAA==.Hugo:BAAANQAECgQICwAAAA==.Hullr:BAAANQAECgQIBgAAAA==.Huwglyndur:BAAANQAECgQIBwAAAA==.',
Hy='Hyperiunpala:BAAANQAECgQIBAAAAA==.',
Ia='Iari:BAAANQADCggIDgAAAA==.',
Id='Idispizhorde:BAAANQAECgYIDQAAAA==.',
Ig='Igris:BAAANQAECgUIBwAAAA==.',
Il='Illihottie:BAAANQADCgQIBAAAAA==.Illiora:BAAANQADCgYIBQABNQAECggIIgAIADIYAA==.Illissia:BAAANQAECgEIAQAAAA==.',
Im='Imós:BAAANQADCgcICAAAAA==.',
Ir='Ironpreacher:BAAANQADCgYIDQAAAA==.Ironspite:BAAANQADCggIDQAAAA==.',
Is='Ish:BAABNQAECoEbAAIJAAkJHxsdCAAPAwAJAAkJHxsdCAAPAwAAAA==.Ishibad:BAAANQAECgEIAQABNQAECgkJGwAJAB8bAA==.Isolie:BAAANQAECgEIAQAAAA==.Isongard:BAAANQABCgIIAgAAAA==.',
It='Itsthesham:BAAANQAECgQIBQABNQAECgYIDQABAAAAAA==.',
Iv='Ivok:BAAANQADCgYIBwAAAA==.',
Iy='Iyooni:BAAANQABCgQIBAAAAA==.',
Ja='Jatbez:BAAANQADCgMIBQAAAA==.Jaykay:BAAANQADCgcICgAAAA==.Jazmìne:BAAANQADCggIGAAAAA==.',
Je='Jessa:BAAANQAECgUIBQAAAA==.Jezuz:BAAANQAECgUIBQAAAA==.',
Ji='Jimbadd:BAAANQAECgQIBAAAAA==.Jimmieslock:BAABNQAFFIEIAAQCAAUJgx0LAwBoAQACAAQJohoLAwBoAQADAAEJEiZHAQByAAAKAAEJHiCQCABkAAAAAA==.',
Jk='Jkils:BAAANQADCggIEQAAAA==.',
Jo='Jonbaptist:BAAANQAECgYIBgAAAA==.Jonile:BAAANQADCgEIAQAAAA==.Joyfulflame:BAAANQADCgMIAwABNQAECgQIBwABAAAAAA==.',
Jt='Jtrain:BAAANQAECgUICQAAAA==.',
Ju='Judwin:BAAANQAECgYICAAAAA==.',
['Jä']='Jäzmine:BAAANQADCgIIAgAAAA==.',
['Jè']='Jèssicà:BAAANQAECgcIEwAAAA==.',
['Jô']='Jôseph:BAAANQADCgUIBgAAAA==.',
['Jö']='Jöe:BAAANQADCgIIAgAAAA==.',
Ka='Kaalin:BAAANQADCgIIAgAAAA==.Kabutosan:BAAANQAECgEIAQABNQAECgkJGQACAN0bAA==.Kail:BAAANQADCgQIBAAAAA==.Kaleesi:BAAANQADCgcIEAAAAA==.Kamots:BAAANQAECgQIBgAAAA==.Kareokee:BAAANQAECgYIDQAAAA==.Kargoroth:BAABNQAECoEcAAIIAAkJYh3iEAD+AgAIAAkJYh3iEAD+AgAAAA==.Karnaga:BAAANQABCgYICQAAAA==.Karral:BAAANQAECgcIEQAAAA==.Katerzv:BAAANQADCgMIBAAAAA==.Kazdormu:BAAANQAECgcIEQAAAA==.',
Kc='Kchaos:BAAANQADCgcIBwAAAA==.',
Ke='Kedira:BAAANQADCggIEAABNQAECggILQALAKwjAA==.Keloth:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Keyztone:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.',
Kh='Khadriel:BAAANQAECgQICwAAAA==.',
Ki='Killinrapidy:BAAANQADCgUICQAAAA==.Kitani:BAABNQAECoEbAAIMAAgJvx6AAwDPAgAMAAgJvx6AAwDPAgAAAA==.',
Kn='Knottybits:BAAANQADCggIFQABNQADCggIFQABAAAAAA==.',
Ko='Konsumer:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Kontakt:BAAANQADCgcIDgAAAA==.Konân:BAAANQAECgQICAAAAA==.Kordim:BAAANQAECgQIBAABNQAECgUIEQABAAAAAA==.Korvakh:BAAANQAECgEIAQAAAA==.',
Kr='Kraduun:BAAANQAECgQIBgAAAA==.Krantly:BAAANQADCggICAAAAA==.Krenniellin:BAAANQAECgUICgAAAA==.Krys:BAAANQAECgYIBgAAAA==.',
La='Laev:BAEANQADCggICAABNQAECgYIEAABAAAAAA==.Lambadin:BAAANQADCgQIBAAAAA==.Lanaru:BAAANQADCgYIDAABNQAECgQIBgABAAAAAA==.Lavi:BAAANQADCgMIAwAAAA==.',
Le='Leizil:BAAANQAECgYIDgAAAA==.Lennox:BAAANQAECgQIBwAAAA==.Letara:BAAANQADCgYIBgAAAA==.Lextor:BAAANQADCgEIAQAAAA==.',
Lh='Lhuani:BAABNQAECoEaAAINAAkJxxilPQCbAgANAAkJxxilPQCbAgAAAA==.',
Li='Liaelina:BAEANQAECgMIAwAAAA==.Lightmyhole:BAAANQADCgEIAQABNQAECgYIBgABAAAAAA==.Like:BAAANQADCgUIBQAAAA==.Lilyachty:BAAANQADCgUICgABNQAECgcIEAABAAAAAA==.Linshe:BAAANQAECgUIDAAAAA==.Lizzie:BAAANQADCgUIBQAAAA==.',
Ll='Llillianna:BAAANQAECgQIBQAAAA==.',
Lo='Loosey:BAAANQABCgYIBgAAAA==.Lorm:BAAANQADCgEIAQAAAA==.',
Lu='Lucarien:BAAANQAECgMIBQAAAA==.Lustyglory:BAAANQADCggICAAAAA==.',
Ma='Macareios:BAAANQADCgUIBQAAAA==.Madeintyø:BAAANQADCgQIBAABNQAECgcIEAABAAAAAA==.Maelos:BAAANQAECgIIAgAAAA==.Mageaga:BAAANQADCgYICwAAAA==.Magnathul:BAAANQAECgcICgAAAA==.Magnumdruid:BAAANQADCgQIBAAAAA==.Makeah:BAAANQAECgcIEQAAAA==.Makhamou:BAAANQAECgYICwAAAA==.Malak:BAAANQAECgQICAAAAA==.Malinstur:BAAANQAECgYICwAAAA==.Marjorye:BAAANQAECgQIBwAAAA==.Marnaught:BAAANQADCggIFQAAAA==.Marzánna:BAAANQADCgQIBwABNQAECgQIBQABAAAAAA==.Mashed:BAAANQADCgYICwABNQADCgYICwABAAAAAA==.Matts:BAAANQAECgEIAgAAAA==.Maxxamus:BAAANQAECgEIAQAAAA==.Mazaal:BAAANQAECgcIEgAAAA==.',
Mc='Mcshaft:BAAANQABCgQIBQAAAA==.',
Me='Meatmuskett:BAAANQADCggICAAAAA==.Mekeena:BAAANQAECgQIBQAAAA==.Melesandre:BAAANQADCgYICgAAAA==.Melinee:BAAANQADCgIIAgAAAA==.Mellinda:BAAANQAECgEIAQAAAA==.Melzas:BAAANQAECgQIBgAAAA==.',
Mi='Midrok:BAAANQAECgUIEQAAAA==.Mikåh:BAAANQADCggICAAAAA==.Milkjugzz:BAAANQADCgQIBAAAAA==.Miselah:BAAANQADCgEIAQAAAA==.Missyennefer:BAAANQADCgcIEgAAAA==.',
Mo='Mobythicc:BAAANQADCgcICQABNQAFFAEIAQABAAAAAA==.Mondai:BAAANQABCgQIBAAAAA==.Monkpowahh:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Montag:BAAANQADCggIDgABNQAECgUIEQABAAAAAA==.Moonboomfred:BAAANQADCgMIAwAAAA==.Moonshower:BAAANQAECgUICAAAAA==.Mooranda:BAAANQABCggIDgAAAA==.Morgaenei:BAAANQABCgMIAwAAAA==.',
Mt='Mtastyck:BAAANQADCgYICAAAAA==.',
Mu='Mudsniffer:BAAANQAECgEIAQAAAA==.Multitool:BAEANQAECgYIDgAAAA==.Mundekk:BAAANQAECgQIBgAAAA==.',
My='Myobûky:BAAANQADCgUIBQAAAA==.Mystiecub:BAAANQABCgIIAQAAAA==.Mythgleam:BAAANQAECgEIAQAAAA==.Myththistle:BAAANQADCgEIAQAAAA==.',
['Má']='Mániac:BAAANQADCgYICwAAAA==.',
Na='Nack:BAAANQADCgcICQABNQAECggIEwABAAAAAA==.Nacks:BAAANQAECggIEwAAAA==.Nacksd:BAAANQADCgEIAQABNQAECggIEwABAAAAAA==.Nacksly:BAAANQAECgIIAgABNQAECggIEwABAAAAAA==.Nacksp:BAAANQADCgUIBQABNQAECggIEwABAAAAAA==.Naliön:BAAANQADCggIEwAAAA==.Naotsugu:BAAANQADCgYIDwAAAA==.Nargacuga:BAAANQAECgEIAQABNQAECgYIDAABAAAAAA==.Nasarden:BAAANQAECgMIBAAAAA==.Nasir:BAAANQADCggIEwAAAA==.Nastysage:BAAANQAECgQIBgAAAA==.Nastyxxnate:BAAANQADCgIIAwAAAA==.Naxdh:BAAANQADCgYICQABNQAECggIEwABAAAAAA==.',
Ne='Nechanion:BAAANQADCgUIBgAAAA==.Nessië:BAAANQAECgQIBQAAAA==.Nesthor:BAAANQADCgYIBgAAAA==.',
Ni='Nimibear:BAAANQAECgIIAgAAAA==.Nimidk:BAAANQAECgcIEwAAAA==.Ninjahealer:BAAANQAECgEIAQAAAA==.',
No='Noobtotem:BAAANQADCgYICwABNQAECgUIBwABAAAAAA==.Nooffensë:BAEANQADCgcIDAABNQAECgMIAwABAAAAAA==.',
Nu='Nugsmasher:BAAANQADCgYIBgAAAA==.Nutdevourer:BAAANQAECgYIDgAAAA==.',
['Né']='Néther:BAAANQADCgcICAAAAA==.',
Oa='Oakelvin:BAAANQAECgYIBwAAAA==.',
Ob='Obnoxiousego:BAAANQAECgcIDwAAAA==.',
Od='Odartherogue:BAAANQADCgUIBAAAAA==.Oddknee:BAABNQAECoEbAAIFAAkJLh66BwAVAwAFAAkJLh66BwAVAwAAAA==.Odney:BAAANQAECgQICAABNQAECgkJGwAFAC4eAA==.',
On='Onaria:BAAANQAECgQIBAABNQAECggIIgAIADIYAA==.',
Or='Oridox:BAAANQAECgYICwAAAA==.Orumine:BAABNQAECoEYAAIOAAkJGhzhGADaAgAOAAkJGhzhGADaAgAAAA==.',
Pa='Palcan:BAAANQADCgQICwAAAA==.Papii:BAAANQAECggIAgAAAA==.Paratussum:BAAANQADCgYIBgAAAA==.Parka:BAAANQAECggIEAAAAA==.Pattysmash:BAAANQAECgYICwABNQAECgkJGwAPAHkgAA==.',
Pb='Pbody:BAAANQAECgYICwAAAA==.',
Pe='Perhorn:BAAANQADCgQIBwAAAA==.',
Po='Pollywog:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Polunocnicá:BAAANQAECgQIBQAAAA==.Pooj:BAAANQADCggIFwAAAA==.',
Pr='Primehunter:BAAANQADCgQIBAAAAA==.Primetime:BAAANQAECgQICQAAAA==.Prissila:BAAANQADCgYIDwAAAA==.Prollimix:BAAANQAECgEIAgAAAA==.',
Ps='Psychoshorts:BAAANQAECgUICAAAAA==.Psykick:BAAANQADCgEIAQAAAA==.',
Py='Pyropoint:BAAANQAECgQIBAAAAA==.',
Ra='Rachela:BAAANQADCgYICgAAAA==.Ractiel:BAAANQADCgQICQAAAA==.Raidhero:BAAANQADCggIDQAAAA==.Rain:BAAANQAECgQIBAAAAA==.Raked:BAAANQAECgQICQAAAA==.Ranfna:BAAANQADCggICQAAAA==.Rapidkiill:BAAANQADCgMIAwAAAA==.Rapidly:BAAANQADCgUIBQAAAA==.Raspberrytea:BAAANQABCggICwAAAA==.Raviolio:BAAANQAECgMIAwABNQAECgMIBQABAAAAAA==.',
Re='Reebz:BAAANQADCgYIBwABNQAECgcIEwABAAAAAA==.Reflection:BAAANQAECgYIDAAAAA==.Rekcutnerd:BAAANQAECgEIAQAAAA==.Reppa:BAAANQADCggICAAAAA==.Retiniris:BAAANQAECgUIEQAAAA==.',
Rh='Rhonstaris:BAAANQAECgEIAQAAAA==.Rhylintras:BAAANQADCgQIBwABNQAECgQIBQABAAAAAA==.',
Ri='Riceporridge:BAAANQAECgQIBwAAAA==.Riptakeoff:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.Riskofrain:BAAANQAECgEIAQAAAA==.Ritzcarltina:BAAANQADCgIIAgAAAA==.Ritzu:BAAANQADCggICAABNQAECgQIBgABAAAAAA==.',
Ro='Rockemi:BAAANQABCgMIAwAAAA==.Roxyviper:BAAANQAECgQICQAAAA==.Royalfox:BAAANQAECgUICgAAAA==.',
Ru='Rubbish:BAAANQADCggIFgAAAA==.',
Sa='Saatari:BAAANQADCgUICQAAAA==.Saddeath:BAAANQADCgYIBgAAAA==.Saeylaura:BAAANQADCggIEwAAAA==.Saintchuck:BAAANQADCggIEQAAAA==.Sainted:BAAANQADCggICQAAAA==.Salanaar:BAAANQAECgcIEgAAAA==.Salarix:BAAANQAECgMIBAAAAA==.Sanarian:BAAANQADCgUIBQAAAA==.Sanctified:BAAANQAECggIBwAAAA==.Sarja:BAAANQAECgQIBwAAAA==.Sarras:BAAANQADCgYICgAAAA==.Sasserfrass:BAAANQAECgMIBQAAAA==.Savaant:BAAANQADCgIIAgAAAA==.Sayy:BAAANQAECgYICQAAAA==.',
Sc='Scaledrage:BAAANQADCgIIAgAAAA==.Schism:BAAANQAECgUIBQABNQADCggIFQABAAAAAA==.',
Se='Seaotter:BAAANQAECgUICgAAAA==.Senhonrue:BAAANQAECgEIAQAAAA==.Serabian:BAAANQADCgUIBQAAAA==.Seraz:BAABNQAECoEWAAIQAAkJ0BgoCQCtAgAQAAkJ0BgoCQCtAgAAAA==.Serenitey:BAAANQADCgYIEQAAAA==.Serraglyndur:BAAANQAECgQIBwAAAA==.',
Sh='Shaderaina:BAAANQADCggIEgAAAA==.Shadowgame:BAAANQADCgQIBAAAAA==.Shambe:BAAANQADCgIIAgAAAA==.Shamidzi:BAAANQADCgQIBAAAAA==.Sheabutters:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Shmorg:BAAANQAECgMIBQAAAA==.Shunaiman:BAAANQAECgQIBwAAAA==.Shàdowdànce:BAAANQADCgUIBwAAAA==.Shábam:BAAANQAECgEIAQAAAA==.',
Si='Sifferr:BAAANQAECgIIAwAAAA==.Sijinn:BAAANQADCgYIDAAAAA==.Silus:BAAANQAECgQIBAAAAA==.',
Sk='Skezes:BAAANQADCgYIBgAAAA==.Skotom:BAAANQADCgcIDAAAAA==.Skyjericho:BAAANQAECgEIAQAAAA==.',
Sl='Slattpal:BAAANQAECgcIEgAAAA==.Sleebyevoker:BAAANQAECgYIEgAAAA==.',
Sm='Smurghl:BAAANQADCgcIBwAAAA==.',
Sn='Snackysteak:BAAANQADCgYIBgAAAA==.',
So='Socinks:BAAANQADCgcIBwAAAA==.Solistome:BAAANQADCgYICwAAAA==.Somarlar:BAAANQADCgMIAwAAAA==.Sopho:BAAANQAECgQIBgAAAA==.Sophogue:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.',
Sp='Specialtea:BAAANQADCggIFgAAAA==.',
Sq='Squam:BAAANQADCgcIBwABNQAECgYIDgABAAAAAA==.',
St='Starzpapi:BAAANQABCgIIAgABNQAECgcIEAABAAAAAA==.Stonebones:BAAANQADCgcICAAAAA==.Strappy:BAAANQADCgcIBwAAAA==.Stwife:BAABNQAECoEbAAMRAAkJKhnuEgC5AgARAAkJaBjuEgC5AgALAAIJVA/tQwBoAAAAAA==.Störmë:BAAANQADCgUICQAAAA==.',
Su='Sufrucia:BAAANQAECgYICgAAAA==.Sunday:BAAANQAECgYIDgAAAA==.Sunhime:BAAANQAECgEIAQAAAA==.Surâ:BAAANQAECgYICwAAAA==.',
Sy='Symbol:BAAANQAECgcIDAABNQAECgYIDgABAAAAAA==.Sympissal:BAAANQADCggIEQAAAA==.',
['Sò']='Sònya:BAAANQAECgUIDAAAAA==.',
['Sÿ']='Sÿlvanas:BAAANQADCggICAAAAA==.',
Ta='Tabhunter:BAAANQADCgYIBgAAAA==.Tagritalth:BAAANQADCgYIBgABNQABCgMIAwABAAAAAA==.Taindnddra:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Talanas:BAAANQADCggIBQAAAA==.Tanishalfelf:BAABNQAECoEgAAMOAAkJ2SaKAAAABAAOAAkJ2SaKAAAABAASAAcJlRQ+MQD9AQAAAA==.Tankaman:BAAANQADCgQIBwABNQAECgIIAgABAAAAAA==.',
Te='Telliah:BAAANQABCgEIAQAAAA==.Tempestre:BAAANQADCgMIAwAAAA==.Terrorfury:BAAANQADCgUICQAAAA==.',
Th='Thalassikos:BAAANQAECgEIAQAAAA==.Thatredhead:BAAANQADCgQIBAAAAA==.Thegremlin:BAAANQAECgEIAQAAAA==.Thewraith:BAAANQAECgEIAQAAAA==.Thorcised:BAAANQAECgcIEQAAAA==.Thorin:BAAANQAECgQIBwAAAA==.Thorym:BAAANQADCgUIBQABNQAECgYIDgABAAAAAA==.Thoryndir:BAAANQAECgYIDgAAAA==.Thrym:BAAANQAECgYICgAAAA==.Thundernut:BAAANQADCggIEAAAAA==.',
Ti='Tidalsong:BAAANQADCggIFgAAAA==.Tirillian:BAAANQADCgUIBQAAAA==.Tirnoir:BAAANQADCgQIBgABNQAECgQIBAABAAAAAA==.',
Tk='Tkenga:BAAANQADCggIGgAAAA==.',
To='Tojarm:BAAANQADCgEIAQAAAA==.Tonicdeath:BAAANQAECgIIAgAAAA==.Torshana:BAAANQADCgEIAQAAAA==.Totemgobbler:BAAANQAECgEIAQAAAA==.Totemlyfine:BAAANQAECgIIAwAAAA==.',
Tr='Tralzind:BAAANQADCgMIAwAAAA==.Truthsayer:BAAANQAECgYICwAAAA==.',
Ts='Tsquared:BAAANQAECgYIDgAAAA==.Tsukasa:BAAANQAECgQIAwAAAA==.',
Tu='Tukk:BAAANQAECgQIBAAAAA==.Tumnina:BAAANQADCgYICwAAAA==.',
Tw='Twiinkletoes:BAAANQADCggIDAAAAA==.Twopuffs:BAAANQAECgQIBAAAAA==.',
Ty='Tyce:BAAANQAECgUIBwAAAA==.Tylannis:BAAANQAECgYIEQAAAA==.',
Ug='Ugacoop:BAAANQAECgcIEQAAAA==.',
Ut='Uthrick:BAAANQADCgYIBgAAAA==.',
Va='Vaelisara:BAAANQAECgQIBAAAAA==.',
Ve='Veldrys:BAAANQADCgcICwABNQAECgYICwABAAAAAA==.Veledaa:BAAANQADCgYIEAAAAA==.Venomnips:BAAANQADCgQIBAAAAA==.Verige:BAAANQAECgEIAQAAAA==.Vesperbough:BAAANQABCgIIAgAAAA==.Vetis:BAAANQADCggIDwAAAA==.',
Vi='Vicars:BAAANQADCgYICwABNQAECgQIBQABAAAAAA==.Vickos:BAAANQAECgYIBAAAAA==.Vilyawen:BAAANQABCgIIBAAAAA==.Virgil:BAAANQADCgUIBQABNQAECgUICQABAAAAAA==.Visionblast:BAAANQADCgEIAQAAAA==.Visionlink:BAAANQADCgEIAQAAAA==.Vixyn:BAAANQABCgYICQAAAA==.',
Vo='Voidme:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.Voidshift:BAAANQABCgMIAwAAAA==.Vorellyn:BAAANQADCgcIDQAAAA==.',
Vu='Vuuddon:BAAANQABCgIIAgAAAA==.',
['Và']='Vàlorie:BAAANQAECgYICgAAAA==.',
['Vè']='Vèlkhànà:BAAANQAECgYIDAAAAA==.',
Wa='Wangdaulf:BAAANQADCgQIDAAAAA==.Wardoogy:BAAANQADCggICAAAAA==.Warexios:BAAANQADCgYICgAAAA==.Warglaíves:BAAANQADCgYICwABNQAECgcIEAABAAAAAA==.Warradord:BAAANQADCgYIDAABNQAECgUIEQABAAAAAA==.Warsmedic:BAAANQAECgUICgAAAA==.',
We='Wevaren:BAAANQADCgEIAQAAAA==.',
Wh='Whumha:BAAANQADCgQIBAAAAA==.',
Wi='Wilbur:BAAANQADCgQIBAAAAA==.Williams:BAEANQAECggIDQABNQAECgkJHgAEAAocAA==.Williamsjr:BAEBNQAECoEeAAIEAAkJChz2FwAKAwAEAAkJChz2FwAKAwABNQAECgkJHgAEAAocAA==.Wilumi:BAAANQAECgEIAQAAAA==.Winkel:BAAANQADCgcICwAAAA==.',
Wo='Wolfyhuntres:BAAANQADCgQIBQAAAA==.Wolvesfor:BAAANQAECgIIAgAAAA==.Woopiing:BAAANQADCggIFQAAAA==.Woubbie:BAAANQABCgIIAwAAAA==.',
Wu='Wuhpow:BAAANQADCgIIAgAAAA==.Wunna:BAAANQAECgcIEAAAAA==.',
['Wá']='Wármonger:BAAANQADCgIIAgAAAA==.',
Xa='Xanístus:BAAANQAECgQIBAAAAA==.',
Xe='Xeppa:BAAANQAECgYICwAAAA==.',
Xi='Xionz:BAAANQAECgMIBQAAAA==.',
Ya='Yakella:BAAANQAECgMIBgAAAA==.',
Ye='Yelgrun:BAAANQADCgcIEwAAAA==.Yellcat:BAAANQAECgYIEAAAAA==.',
Yh='Yhoda:BAAANQAECgcIEgAAAA==.',
Yo='Yodä:BAAANQADCgUIBQAAAA==.Youseitgar:BAAANQAECggICQAAAA==.',
Yu='Yuisis:BAAANQAECgUIBQAAAA==.',
Za='Zabidu:BAAANQAECgcIEgAAAA==.Zappyketch:BAABNQAECoEYAAIIAAgJYBs0HQCIAgAIAAgJYBs0HQCIAgAAAA==.Zaraeiri:BAAANQADCgUIBQAAAA==.Zaraxaà:BAAANQADCgUICwABNQAECgcIEwABAAAAAA==.',
Ze='Zelenã:BAAANQAECgEIAgAAAA==.Zelun:BAAANQAECgcIDwAAAA==.Zephon:BAAANQAECgcIDwAAAA==.',
Zi='Ziggley:BAAANQADCgYIBgABNQAECgUIBwABAAAAAA==.',
Zo='Zombiemarj:BAAANQADCggIGwAAAA==.',
['Zé']='Zéd:BAAANQAECgQICwAAAA==.',
['Âx']='Âxel:BAAANQADCgUIBQABNQAECgYIEAABAAAAAA==.',
['Æd']='Ædisgrace:BAAANQAECgEIAgAAAA==.',
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
