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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Retribution','Paladin-Holy',}
local provider = {region='US',realm='Trollbane',name='US',type='weekly',zone=53,date='2026-09-08',data={Ac='Acroin:BAAANQADCgQIBAAAAA==.',
Ad='Adeliz:BAAANQAECgIIAgAAAA==.Adorana:BAAANQADCgQIBAAAAA==.Adrunk:BAAANQAECgUICgAAAA==.',
Ae='Aeloesh:BAAANQADCgUIBwAAAA==.Aelyra:BAAANQADCgYICAAAAA==.Aenatheon:BAAANQADCggIFgAAAA==.',
Ag='Aggrum:BAAANQAECgIIAgAAAA==.',
Ah='Ahexutroll:BAAANQADCgcIDQAAAA==.',
Ai='Aiur:BAAANQADCgcIEQAAAA==.',
Ak='Akredfox:BAAANQAECgMIAwAAAA==.',
Al='Alexaviah:BAAANQAECgMIAwAAAA==.Alicedelight:BAAANQAECgIIAwAAAA==.Alwaysburnt:BAAANQADCgYIDwAAAA==.Alwayscooked:BAAANQADCgIIAgAAAA==.',
Am='Amabeast:BAAANQADCgUIBQAAAA==.Amisia:BAAANQADCgcIEwAAAA==.',
An='Anathas:BAAANQAECgQIBAAAAA==.Angelfelis:BAAANQAECgYICwAAAA==.Angelgoblin:BAAANQADCgEIAQAAAA==.Angriff:BAAANQADCggIDgAAAA==.Angrybeavor:BAAANQAECgEIAQAAAA==.Anuke:BAAANQADCgcIBwAAAA==.',
Ao='Aonaar:BAAANQADCgYIDAAAAA==.',
Ar='Archdemon:BAAANQAECgQIBQAAAA==.Arkroot:BAAANQADCggIDwAAAA==.Arlock:BAAANQADCggICAAAAA==.Arsy:BAAANQADCgUIBQABNQADCgYICwABAAAAAA==.',
As='Ashidpriest:BAEANQAECgYICgAAAA==.Ashtoreth:BAAANQADCggIFQAAAA==.Assukun:BAAANQAECgUICAAAAA==.Async:BAAANQAECgUIBQAAAA==.',
At='Ati:BAAANQADCgYIBgAAAA==.',
Au='Aurá:BAAANQADCgIIAgAAAA==.Autoattack:BAAANQADCgcIBwAAAA==.',
Ax='Axethegrippa:BAAANQAECgUIBgABNQAECggIEgABAAAAAA==.Aximumeffort:BAAANQADCgYIBgABNQAECggIEgABAAAAAA==.',
Ba='Baddmojo:BAAANQADCgQIBAAAAA==.Badmac:BAAANQAECgYICgAAAA==.Baelliman:BAAANQAECgIIAwAAAA==.Baium:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Bakora:BAAANQADCggIDwAAAA==.Banishedfate:BAAANQAECgMIAwAAAA==.Banishedform:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Banishedholy:BAAANQADCgYIBwABNQAECgMIAwABAAAAAA==.Baozi:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Barelyholy:BAAANQAECgIIAgAAAA==.Barf:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Barrendar:BAAANQADCgIIAgAAAA==.Bartholamew:BAAANQADCgUIBwAAAA==.',
Be='Bearballz:BAAANQADCgIIAgAAAA==.Berry:BAAANQAECgYICAAAAA==.Besneakies:BAAANQAECgMIAwAAAA==.',
Bi='Bigdamfred:BAAANQADCgEIAQAAAA==.Binnford:BAAANQADCgYICwAAAA==.',
Bl='Blackfang:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Blaqball:BAAANQADCgUIBQAAAA==.',
Bo='Bottombish:BAAANQADCggICAAAAA==.Boulderjaw:BAAANQAECgMIAwAAAA==.Boxeybrown:BAAANQAECgQIDAAAAA==.',
Br='Braised:BAAANQAECgQIBQAAAA==.Brbdeported:BAAANQADCgYIDgAAAA==.Breakadakeys:BAAANQAECgUICQAAAA==.Breccia:BAAANQADCggIDwAAAA==.Brutanious:BAAANQADCgYIDgABNQAECgMIAwABAAAAAA==.',
Bu='Bubblebro:BAAANQAECgEIAQAAAA==.Buffwarrior:BAAANQAECgMIBQAAAA==.Bustamoon:BAAANQADCgcICQAAAA==.Butterface:BAAANQADCgcIDAAAAA==.',
['Bà']='Bàckstabbath:BAAANQADCgMIAwAAAA==.',
Ca='Caeruleus:BAAANQADCgcIBwAAAA==.Cammikins:BAEANQAECgQICQAAAA==.Cantmilkem:BAAANQADCgIIAgAAAA==.Capellaz:BAAANQAECgMIAwAAAA==.Capriestson:BAAANQAECgQIBQAAAA==.Casandra:BAAANQAECgQIBQAAAA==.Cassiopeias:BAAANQADCgUIBQAAAA==.',
Ce='Celerynn:BAAANQADCgUICAAAAA==.Celestaura:BAAANQADCgYIBgAAAA==.Centares:BAAANQADCgUIBAAAAA==.',
Ch='Charlutes:BAAANQADCggIDwAAAA==.Chekzy:BAAANQADCgYICwAAAA==.Chichii:BAAANQAECgMIAwAAAA==.Chilis:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Choasman:BAAANQADCgQIBAAAAA==.Chocolate:BAAANQADCgUICAAAAA==.Chudpath:BAAANQAECgMIAwABNQAECgYICwABAAAAAA==.',
Cl='Cleome:BAAANQABCgEIAQAAAA==.',
Co='Coorsenjoyer:BAEANQAFFAIIAgAAAA==.Copakid:BAAANQAECgIIAgAAAA==.Cowlie:BAAANQAECgUICAAAAA==.Coøkiewizard:BAAANQADCgEIAQAAAA==.',
Cr='Crippy:BAAANQAECgMIAwABNQADCgIIAgABAAAAAA==.Crippypal:BAAANQAECgQIBQABNQADCgIIAgABAAAAAA==.Crippyx:BAAANQADCgIIAgAAAA==.Crowls:BAAANQADCgMIAwAAAA==.Cruelwar:BAAANQAECgQIBAAAAA==.',
Cu='Cuckcmder:BAAANQADCggIFQAAAA==.',
Da='Daffodil:BAAANQADCgEIAQAAAA==.Daggoth:BAAANQAECgQIBQAAAA==.Dalrak:BAAANQAECgYICgAAAA==.Dandarth:BAAANQADCgMIAwAAAA==.Danemos:BAAANQADCgEIAQABNQAFFAIIAgABAAAAAA==.Dante:BAAANQAECgQIBAAAAA==.Darkendelf:BAAANQAECgQIBQAAAA==.Darkothy:BAAANQADCggIEwAAAA==.Darkvision:BAAANQAECgEIAQAAAA==.Dasdann:BAAANQADCgUIBQAAAA==.Datshammy:BAAANQADCgUIBQAAAA==.Datvoodoomon:BAAANQAECgYICwAAAA==.Daïn:BAAANQADCggIEQAAAA==.',
Dc='Dcaý:BAAANQADCgIIAwABNQAECgEIAQABAAAAAA==.',
De='Deadjuggalo:BAAANQADCgcIDAAAAA==.Deadlyfaith:BAAANQADCgIIAgAAAA==.Deadstep:BAAANQADCggIDwAAAA==.Deathzy:BAAANQADCgIIAgAAAA==.Deleralia:BAAANQAECgQICgAAAA==.Demontopher:BAAANQAECggIEQAAAA==.Derodrayne:BAAANQADCgYIBgAAAA==.Deshaler:BAAANQADCgcIBwAAAA==.Devoidshield:BAAANQAECgIIAgAAAA==.',
Di='Dicon:BAAANQADCgYIBgAAAA==.Dieric:BAAANQADCggIEwAAAA==.Dinkle:BAAANQADCgMIAwABNQADCgcICwABAAAAAA==.Dividian:BAAANQAECgQIBAABNQAECgQIBAABAAAAAA==.',
Do='Dorastrain:BAAANQAECgMIBwAAAA==.',
Dr='Dracovoid:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Dragonwyck:BAAANQAECgMIAwAAAA==.Draytheus:BAAANQAECgMIAwAAAA==.Dripping:BAAANQAECgQIBAAAAA==.Dromai:BAAANQADCgQIBAAAAA==.',
Du='Duhdotsbruh:BAAANQADCgYIBwAAAA==.',
Ed='Edgarj:BAAANQADCgEIAQAAAA==.',
Ek='Eklipsch:BAAANQADCggICgAAAA==.',
El='Eld:BAAANQABCgYIBwAAAA==.Electabuzz:BAEANQADCgcIBwABNQAECgYIEgABAAAAAA==.Electrocutey:BAAANQAECgMIAwAAAA==.Elein:BAAANQADCgEIAQAAAA==.Eleman:BAAANQADCggIDAAAAA==.Elfclover:BAAANQAECgYIDAAAAA==.Elijahx:BAAANQAECgMIBQAAAA==.Elijay:BAAANQAECgIIAgAAAA==.Eljayye:BAAANQADCgYICwAAAA==.',
Em='Emisha:BAAANQADCgIIAgAAAA==.Emmshunter:BAAANQAECgIIAQAAAA==.',
Ep='Epicdemise:BAAANQADCgYIBgAAAA==.Epicdemon:BAAANQADCgYIBwAAAA==.Epicwarlock:BAAANQADCggIDQAAAA==.Epona:BAAANQAECgQICwAAAA==.',
Er='Erzá:BAAANQAECgIIAgAAAA==.',
Et='Eterna:BAAANQAECgMIAwAAAA==.',
Ev='Eveilyn:BAAANQADCgYIBgAAAA==.Evileye:BAAANQADCgYIBgAAAA==.',
Ex='Exarchamus:BAAANQAECgUICwAAAA==.',
Fa='Facemelt:BAAANQAECgUIBgAAAA==.Farfy:BAAANQAECgUICAAAAA==.Fartsmagoo:BAAANQAECgEIAQAAAA==.Faykan:BAAANQAECgEIAQAAAA==.',
Fe='Fedrameda:BAAANQAECgQIBAAAAA==.Felix:BAAANQAECgQIBAAAAA==.Fellender:BAAANQADCggIHAAAAA==.Fermented:BAAANQAECgUICAAAAA==.',
Fi='Fizzle:BAAANQADCgQIBgAAAA==.',
Fl='Flintstones:BAAANQAECgcICgAAAA==.Fluffykiitty:BAAANQADCgEIAQAAAA==.',
Fo='Fowlplay:BAAANQADCgYICgAAAA==.Foxbox:BAAANQADCgYIEAAAAA==.',
Fu='Fujee:BAAANQAECgQIBQAAAA==.Funkyt:BAAANQAECgIIAgAAAA==.Furrysona:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.',
['Fâ']='Fâlooga:BAAANQAECgMIBAAAAA==.',
Ga='Gaidine:BAAANQADCgMIAwAAAA==.Galadriael:BAAANQAECgQICAAAAA==.Galtan:BAAANQADCggIEwAAAA==.Garrod:BAAANQADCggIFQAAAA==.Gattsu:BAAANQADCggIFAAAAA==.',
Ge='Gennil:BAAANQAECgcICwAAAA==.Gestella:BAAANQAECgIIAgAAAA==.Gevo:BAAANQAECgMIAwAAAA==.',
Gl='Gloomblade:BAABNQAECoEXAAICAAkJpxu+AwAbAwACAAkJpxu+AwAbAwAAAA==.',
Gn='Gnomepimp:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Go='Gojìra:BAAANQAECgEIAQAAAA==.Goragaia:BAAANQADCggICAAAAA==.Gorbencleap:BAAANQABCgIIAgAAAA==.Gorion:BAAANQADCgQIBAAAAA==.',
Gr='Grayscale:BAAANQADCgQIBAAAAA==.Greyseer:BAAANQAECgEIAQAAAA==.Grica:BAAANQADCgEIAQAAAA==.',
Gu='Guymontag:BAAANQAECgQIDAAAAA==.',
Ha='Halston:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.Hammergobrr:BAAANQABCgQIBAAAAA==.Harbard:BAAANQAECgMIBQAAAA==.Hasselhøøf:BAAANQAECgQIBQAAAA==.Hawkeyeik:BAAANQADCggIFgAAAA==.Hawthorne:BAAANQAECgMIAwAAAA==.Hayywaffle:BAAANQADCggIDAAAAA==.',
He='Hellothere:BAAANQAECgMIBQAAAA==.Hellren:BAAANQADCgMIAwAAAA==.Helmet:BAAANQADCgQIBAAAAA==.',
Hi='Hikons:BAAANQAECgQIBwAAAA==.Hinkle:BAAANQADCgcICwAAAA==.',
Ho='Holysage:BAAANQADCgcIBwAAAA==.Holytoad:BAAANQADCgYIBgAAAA==.Hopsquash:BAAANQABCgIIBAAAAA==.Hopstop:BAAANQAECgMIAwAAAA==.',
Hu='Hughass:BAAANQADCgYIEgABNQAECgMIBQABAAAAAA==.Hugo:BAAANQAECgQIBgAAAA==.Hullr:BAAANQAECgQIBAAAAA==.Huwglyndur:BAAANQAECgMIAwAAAA==.',
Hy='Hyperiunpala:BAAANQADCggIFQAAAA==.',
Ia='Iari:BAAANQADCgYIBgAAAA==.',
Id='Idispizhorde:BAAANQAECgUIBwAAAA==.',
Ig='Igris:BAAANQAECgIIAgAAAA==.',
Il='Illihottie:BAAANQADCgQIBAAAAA==.Illiora:BAAANQADCgYIBQABNQAECgYIEQABAAAAAA==.Illissia:BAAANQADCgMIAwAAAA==.',
Im='Imós:BAAANQADCgEIAQAAAA==.',
Ir='Ironpreacher:BAAANQADCgUICAAAAA==.Ironspite:BAAANQADCggIDQAAAA==.',
Is='Ish:BAAANQAECgcIDwAAAA==.Ishibad:BAAANQAECgEIAQABNQAECgcIDwABAAAAAA==.Isolie:BAAANQAECgEIAQAAAA==.Isongard:BAAANQABCgIIAgAAAA==.',
It='Itsthesham:BAAANQAECgQIBAABNQAECgYICQABAAAAAA==.',
Iv='Ivok:BAAANQADCgUIBgAAAA==.',
Iy='Iyooni:BAAANQABCgQIAgAAAA==.',
Ja='Jatbez:BAAANQADCgIIAgAAAA==.Jaykay:BAAANQADCgcICgAAAA==.Jazmìne:BAAANQADCggIEwAAAA==.',
Je='Jessa:BAAANQADCggICAAAAA==.Jezuz:BAAANQADCggICAAAAA==.',
Ji='Jimbadd:BAAANQADCgIIAgAAAA==.Jimmieslock:BAAANQAFFAIIAgAAAA==.',
Jk='Jkils:BAAANQADCgUICQAAAA==.',
Jo='Jonbaptist:BAAANQADCggIFwAAAA==.Jonile:BAAANQADCgEIAQAAAA==.',
Jt='Jtrain:BAAANQAECgUIBQAAAA==.',
Ju='Judwin:BAAANQAECgIIAgAAAA==.',
['Jä']='Jäzmine:BAAANQADCgIIAgAAAA==.',
['Jè']='Jèssicà:BAAANQAECgYICgAAAA==.',
['Jô']='Jôseph:BAAANQADCgUIBgAAAA==.',
['Jö']='Jöe:BAAANQADCgIIAgAAAA==.',
Ka='Kaalin:BAAANQADCgIIAgAAAA==.Kabutosan:BAAANQADCggIDgABNQAFFAIIAgABAAAAAA==.Kaleesi:BAAANQADCgcIEAAAAA==.Kamots:BAAANQAECgMIBQAAAA==.Kareokee:BAAANQAECgUIBwAAAA==.Kargoroth:BAAANQAECggIEwAAAA==.Karnaga:BAAANQABCgYIBgAAAA==.Karral:BAAANQAECgUICgAAAA==.Katerzv:BAAANQADCgIIAgAAAA==.Kazdormu:BAAANQAECgYICgAAAA==.',
Ke='Kedira:BAAANQADCggIEAABNQAECggIHQADALIeAA==.',
Kh='Khadriel:BAAANQAECgQICQAAAA==.',
Ki='Killinrapidy:BAAANQADCgUIBQAAAA==.Kitani:BAAANQAECgcIEAAAAA==.',
Kn='Knottybits:BAAANQADCgcIDQABNQADCgcIDQABAAAAAA==.',
Ko='Konsumer:BAAANQADCgQIBAABNQADCggIDAABAAAAAA==.Kontakt:BAAANQADCgYIBwAAAA==.Konân:BAAANQAECgQIBAAAAA==.Kordim:BAAANQADCgYICwABNQAECgQIDAABAAAAAA==.Korvakh:BAAANQADCgYIBgAAAA==.',
Kr='Kraduun:BAAANQAECgMIAwAAAA==.Krantly:BAAANQADCgUIBQAAAA==.Krenniellin:BAAANQAECgQIBQAAAA==.Krys:BAAANQADCggIFwAAAA==.',
La='Laev:BAEANQADCggICAABNQAECgYICgABAAAAAA==.Lambadin:BAAANQADCgMIAwAAAA==.Lanaru:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Le='Leizil:BAAANQAECgUICAAAAA==.Lennox:BAAANQAECgQIBAAAAA==.Letara:BAAANQADCgYIBgAAAA==.Lextor:BAAANQADCgEIAQAAAA==.',
Lh='Lhuani:BAAANQAECgcIDgAAAA==.',
Li='Liaelina:BAEANQADCggICAAAAA==.Lightmyhole:BAAANQADCgEIAQABNQAECgIIAQABAAAAAA==.Like:BAAANQADCgUIBQAAAA==.Lilyachty:BAAANQADCgUICgABNQAECgYICQABAAAAAA==.Linshe:BAAANQAECgQIBwAAAA==.Lizzie:BAAANQADCgUIBQAAAA==.',
Ll='Llillianna:BAAANQAECgEIAQAAAA==.',
Lo='Lorm:BAAANQADCgEIAQAAAA==.',
Lu='Lucarien:BAAANQAECgMIBQAAAA==.Lustyglory:BAAANQADCggICAAAAA==.',
Ma='Macareios:BAAANQADCgUIBQAAAA==.Madeintyø:BAAANQADCgQIBAABNQAECgYICQABAAAAAA==.Maelos:BAAANQAECgIIAgAAAA==.Mageaga:BAAANQADCgYICwAAAA==.Magnathul:BAAANQAECgYIBgAAAA==.Magnumdruid:BAAANQADCgQIBAAAAA==.Makeah:BAAANQAECgYICgAAAA==.Makhamou:BAAANQAECgQIBAAAAA==.Malak:BAAANQAECgQIBAAAAA==.Malinstur:BAAANQAECgUIBQAAAA==.Marjorye:BAAANQADCgYICgAAAA==.Marnaught:BAAANQADCgcIDQAAAA==.Marzánna:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Mashed:BAAANQADCgYICwAAAA==.Matts:BAAANQAECgEIAQAAAA==.Maxxamus:BAAANQABCgIIAgAAAA==.Mazaal:BAAANQAECgYICwAAAA==.',
Mc='Mcshaft:BAAANQABCgQIBQAAAA==.',
Me='Meatmuskett:BAAANQADCggICAAAAA==.Mekeena:BAAANQAECgEIAQAAAA==.Melesandre:BAAANQADCgYICAAAAA==.Mellinda:BAAANQADCggIEgAAAA==.Melzas:BAAANQAECgIIAgAAAA==.',
Mi='Midrok:BAAANQAECgQIDAAAAA==.Miselah:BAAANQADCgEIAQAAAA==.Missyennefer:BAAANQADCgcIEgAAAA==.',
Mo='Mobythicc:BAAANQADCgcICQABNQAECggIEgABAAAAAA==.Mondai:BAAANQABCgQIBAAAAA==.Monkpowahh:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Montag:BAAANQADCgYIBgABNQAECgQIDAABAAAAAA==.Moonboomfred:BAAANQADCgMIAwAAAA==.Moonshower:BAAANQAECgMIAwAAAA==.Mooranda:BAAANQABCgYIBgAAAA==.Morgaenei:BAAANQABCgMIAwAAAA==.',
Mt='Mtastyck:BAAANQADCgYICAAAAA==.',
Mu='Mudsniffer:BAAANQAECgEIAQAAAA==.Multitool:BAEANQAECgUICAAAAA==.Mundekk:BAAANQAECgIIAgAAAA==.',
My='Myobûky:BAAANQADCgUIBQAAAA==.Mythgleam:BAAANQADCgEIAQAAAA==.Myththistle:BAAANQADCgEIAQAAAA==.',
['Má']='Mániac:BAAANQADCgYICwAAAA==.',
Na='Nack:BAAANQADCgcIBwABNQAECgcIDAABAAAAAA==.Nacks:BAAANQAECgcIDAAAAA==.Nacksd:BAAANQADCgEIAQABNQAECgcIDAABAAAAAA==.Nacksly:BAAANQAECgIIAgABNQAECgcIDAABAAAAAA==.Nacksp:BAAANQADCgUIBQABNQAECgcIDAABAAAAAA==.Naliön:BAAANQADCgcIDgAAAA==.Naotsugu:BAAANQADCgYICwAAAA==.Nasarden:BAAANQAECgMIBAAAAA==.Nasir:BAAANQADCgYICwAAAA==.Nastysage:BAAANQAECgEIAgAAAA==.Nastyxxnate:BAAANQADCgIIAgAAAA==.Naxdh:BAAANQADCgUIBgABNQAECgcIDAABAAAAAA==.',
Ne='Nechanion:BAAANQADCgQIBAAAAA==.Nessië:BAAANQAECgIIAgAAAA==.Nesthor:BAAANQADCgYIBgAAAA==.',
Ni='Nimibear:BAAANQAECgIIAgAAAA==.Nimidk:BAAANQAECgcIEAAAAA==.Ninjahealer:BAAANQAECgEIAQAAAA==.',
No='Noobtotem:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Nooffensë:BAEANQADCgcIDAABNQADCggICAABAAAAAA==.',
Nu='Nutdevourer:BAAANQAECgYICAAAAA==.',
['Né']='Néther:BAAANQADCgcICAAAAA==.',
Oa='Oakelvin:BAAANQAECgUIBQAAAA==.',
Ob='Obnoxiousego:BAAANQAECgQICAAAAA==.',
Od='Odartherogue:BAAANQADCgUIBAAAAA==.Oddknee:BAAANQAECgcIDwAAAA==.Odney:BAAANQAECgMIBAABNQAECgcIDwABAAAAAA==.',
On='Onaria:BAAANQADCggIDgABNQAECgYIEQABAAAAAA==.',
Or='Oridox:BAAANQAECgQIBQAAAA==.Orumine:BAAANQAECgcIDAAAAA==.',
Pa='Palcan:BAAANQADCgQIBAAAAA==.Papii:BAAANQAECgYIAgAAAA==.Paratussum:BAAANQADCgYIBgAAAA==.Parka:BAAANQAECggICgAAAA==.Pattysmash:BAAANQAECgQIBAABNQAECgcIEQABAAAAAA==.',
Pb='Pbody:BAAANQAECgUIBQAAAA==.',
Pe='Perhorn:BAAANQADCgQIBwAAAA==.',
Po='Pollywog:BAAANQADCgEIAQABNQADCgcIDAABAAAAAA==.Polunocnicá:BAAANQAECgEIAQAAAA==.Pooj:BAAANQADCggIFQAAAA==.',
Pr='Primetime:BAAANQAECgQIBQAAAA==.Prissila:BAAANQADCgYIDwAAAA==.Prollimix:BAAANQAECgEIAQAAAA==.',
Ps='Psychoshorts:BAAANQAECgMIAwAAAA==.Psykick:BAAANQADCgEIAQAAAA==.',
Py='Pyropoint:BAAANQADCggICAAAAA==.',
Ra='Rachela:BAAANQADCgYICgAAAA==.Ractiel:BAAANQADCgIIBQAAAA==.Raidhero:BAAANQADCggICgAAAA==.Rain:BAAANQADCggIEAAAAA==.Raked:BAAANQAECgQIBQAAAA==.Ranfna:BAAANQADCggICQAAAA==.Rapidkiill:BAAANQADCgMIAwAAAA==.Raspberrytea:BAAANQABCgYIBwAAAA==.Raviolio:BAAANQADCgcIBwABNQAECgMIBQABAAAAAA==.',
Re='Reebz:BAAANQADCgYIBQABNQAECgcIDAABAAAAAA==.Reflection:BAAANQAECgUIBgAAAA==.Rekcutnerd:BAAANQADCgYICAAAAA==.Reppa:BAAANQADCggICAAAAA==.Retiniris:BAAANQAECgQIDAAAAA==.',
Rh='Rhonstaris:BAAANQADCggIEAAAAA==.Rhylintras:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.',
Ri='Riceporridge:BAAANQAECgMIAwAAAA==.Riptakeoff:BAAANQADCgcIBwABNQAECgYICQABAAAAAA==.Riskofrain:BAAANQADCgYIBgAAAA==.Ritzcarltina:BAAANQADCgIIAgAAAA==.Ritzu:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.',
Ro='Roxyviper:BAAANQAECgEIAQAAAA==.Royalfox:BAAANQAECgQIBQAAAA==.',
Ru='Rubbish:BAAANQADCgcIEAAAAA==.',
Sa='Saatari:BAAANQADCgUICQAAAA==.Saddeath:BAAANQADCgYIBgAAAA==.Saeylaura:BAAANQADCggIEwAAAA==.Saintchuck:BAAANQADCgYICQAAAA==.Sainted:BAAANQADCgEIAQAAAA==.Salanaar:BAAANQAECgYICwAAAA==.Salarix:BAAANQAECgEIAQAAAA==.Sanarian:BAAANQADCgUIBQAAAA==.Sarja:BAAANQAECgMIAwAAAA==.Sarras:BAAANQADCgQIBAAAAA==.Sasserfrass:BAAANQAECgMIAwAAAA==.Sayy:BAAANQAECgUICAAAAA==.',
Sc='Schism:BAEANQADCgYICQABNQADCggIFQABAAAAAA==.',
Se='Seaotter:BAAANQAECgQIBQAAAA==.Senhonrue:BAAANQAECgEIAQAAAA==.Serabian:BAAANQADCgUIBQAAAA==.Seraz:BAAANQAECgcIEAAAAA==.Serenitey:BAAANQADCgYICwAAAA==.Serraglyndur:BAAANQAECgMIAwAAAA==.',
Sh='Shaderaina:BAAANQADCgcICgAAAA==.Shambe:BAAANQADCgIIAgAAAA==.Shamidzi:BAAANQADCgQIBAAAAA==.Sheabutters:BAAANQADCgYICQABNQADCgcICwABAAAAAA==.Shmorg:BAAANQAECgMIBQAAAA==.Shunaiman:BAAANQAECgMIAwAAAA==.Shàdowdànce:BAAANQADCgUIBwAAAA==.Shábam:BAAANQADCggIDAAAAA==.',
Si='Sifferr:BAAANQAECgEIAQAAAA==.Sijinn:BAAANQADCgYIBgAAAA==.Silus:BAAANQADCgUICAAAAA==.',
Sk='Skotom:BAAANQADCgUIBQAAAA==.Skyjericho:BAAANQADCgcIDwAAAA==.',
Sl='Slattpal:BAAANQAECgcIDwAAAA==.Sleebyevoker:BAAANQAECgYIDAAAAA==.',
Sn='Snackysteak:BAAANQADCgUIBQAAAA==.',
So='Solistome:BAAANQADCgYICwAAAA==.Somarlar:BAAANQADCgMIAwAAAA==.Sopho:BAAANQAECgMIAwAAAA==.Sophogue:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.',
Sp='Specialtea:BAAANQADCgcIDgAAAA==.',
Sq='Squam:BAAANQADCgcIBwABNQAECgYICAABAAAAAA==.',
St='Stonebones:BAAANQADCgcICAAAAA==.Strappy:BAAANQADCgcIBwAAAA==.Stwife:BAABNQAECoEXAAMEAAkJZhbzEQCNAgAEAAkJpBXzEQCNAgADAAIJVA/1JwB0AAAAAA==.Störmë:BAAANQADCgUIBQAAAA==.',
Su='Sufrucia:BAAANQAECgUIBQAAAA==.Sunday:BAAANQAECgQICAAAAA==.Surâ:BAAANQAECgMIBQAAAA==.',
Sy='Symbol:BAAANQAECgcICgABNQAECgYICAABAAAAAA==.Sympissal:BAAANQADCggIDAAAAA==.',
['Sò']='Sònya:BAAANQAECgUICAAAAA==.',
['Sÿ']='Sÿlvanas:BAAANQADCgIIAgABNQADCggIEgABAAAAAA==.',
Ta='Tagritalth:BAAANQABCgMIAwABNQABCgEIAQABAAAAAA==.Taindnddra:BAAANQADCgEIAQABNQADCggIDAABAAAAAA==.Talanas:BAAANQADCggIBQAAAA==.Tanishalfelf:BAABNQAECoEYAAMFAAkJaSQkBACNAwAFAAgJyyYkBACNAwAGAAcJlRT2IQAEAgAAAA==.Tankaman:BAAANQADCgQIBAABNQADCgcIFAABAAAAAA==.',
Te='Telliah:BAAANQABCgEIAQAAAA==.Terrorfury:BAAANQADCgUIBQAAAA==.',
Th='Thalassikos:BAAANQADCgcIEgAAAA==.Thatredhead:BAAANQADCgQIBAAAAA==.Thegremlin:BAAANQADCgYIBgAAAA==.Thewraith:BAAANQAECgEIAQAAAA==.Thorcised:BAAANQAECgYICwAAAA==.Thorin:BAAANQAECgMIAwAAAA==.Thorym:BAAANQADCgUIBQABNQAECgUICQABAAAAAA==.Thoryndir:BAAANQAECgUICQAAAA==.Thrym:BAAANQAECgQIBAAAAA==.Thundernut:BAAANQADCggICAAAAA==.',
Ti='Tidalsong:BAAANQADCgYIDgAAAA==.Tirillian:BAAANQADCgUIBQAAAA==.Tirnoir:BAAANQADCgIIAgABNQADCgUICAABAAAAAA==.',
Tk='Tkenga:BAAANQADCgcIEgAAAA==.',
To='Tojarm:BAAANQADCgEIAQAAAA==.Tonicdeath:BAAANQADCgcIFAAAAA==.Torshana:BAAANQADCgEIAQAAAA==.Totemgobbler:BAAANQAECgEIAQAAAA==.',
Tr='Tralzind:BAAANQADCgMIAwAAAA==.Truthsayer:BAAANQAECgQIBQAAAA==.',
Ts='Tsquared:BAAANQAECgUICAAAAA==.',
Tu='Tukk:BAAANQADCgUIBQAAAA==.Tumnina:BAAANQADCgUIBQAAAA==.',
Tw='Twiinkletoes:BAAANQADCgMIAwAAAA==.Twopuffs:BAAANQADCggIDgAAAA==.',
Ty='Tyce:BAAANQAECgIIAwAAAA==.Tylannis:BAAANQAECgYICwAAAA==.',
Ug='Ugacoop:BAAANQAECgYICgAAAA==.',
Ut='Uthrick:BAAANQADCgYIBgAAAA==.',
Va='Vaelisara:BAAANQADCgcIDAAAAA==.',
Ve='Veldrys:BAAANQADCgcICwABNQAECgQIBQABAAAAAA==.Veledaa:BAAANQADCgYICwAAAA==.Venomnips:BAAANQADCgQIBAAAAA==.Verige:BAAANQADCggIDgAAAA==.Vetis:BAAANQADCggICAAAAA==.',
Vi='Vicars:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.Vickos:BAAANQAECgYIAgAAAA==.Visionblast:BAAANQADCgEIAQAAAA==.Visionlink:BAAANQADCgEIAQAAAA==.Vixyn:BAAANQABCgYICQAAAA==.',
Vo='Voidme:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Vorellyn:BAAANQADCgYIBgAAAA==.',
['Và']='Vàlorie:BAAANQAECgYICgAAAA==.',
['Vè']='Vèlkhànà:BAAANQAECgUIBgAAAA==.',
Wa='Wangdaulf:BAAANQADCgQICAAAAA==.Wardoogy:BAAANQADCggICAAAAA==.Warexios:BAAANQADCgYIBgAAAA==.Warglaíves:BAAANQADCgYICwABNQAECgcICgABAAAAAA==.Warradord:BAAANQADCgYIBgABNQAECgQIDAABAAAAAA==.Warsmedic:BAAANQAECgQIBQAAAA==.',
We='Wevaren:BAAANQADCgEIAQAAAA==.',
Wh='Whumha:BAAANQADCgQIBAAAAA==.',
Wi='Williams:BAEANQAECgcIBQABNQAECgYIEgABAAAAAA==.Williamsjr:BAEANQAECgcIEgABNQAECgYIEgABAAAAAA==.Wilumi:BAAANQAECgEIAQAAAA==.Winkel:BAAANQADCgQIBAAAAA==.',
Wo='Wolfyhuntres:BAAANQADCgEIAQAAAA==.Woopiing:BAEANQADCggIFQAAAA==.Woubbie:BAAANQABCgIIAwAAAA==.',
Wu='Wuhpow:BAAANQADCgIIAgAAAA==.Wunna:BAAANQAECgYICQAAAA==.',
['Wá']='Wármonger:BAAANQADCgIIAgAAAA==.',
Xe='Xeppa:BAAANQAECgMIBQAAAA==.',
Xi='Xionz:BAAANQAECgIIAgAAAA==.',
Ya='Yakella:BAAANQAECgMIAwAAAA==.',
Ye='Yelgrun:BAAANQADCgYIDAAAAA==.Yellcat:BAAANQAECgYICgAAAA==.',
Yh='Yhoda:BAAANQAECgYICwAAAA==.',
Yo='Yodä:BAAANQADCgUIBQAAAA==.',
Yu='Yuisis:BAAANQADCggICAAAAA==.',
Za='Zabidu:BAAANQAECgYICwAAAA==.Zappyketch:BAAANQAECgcIDQAAAA==.Zaraeiri:BAAANQADCgUIBQAAAA==.Zaraxaà:BAAANQADCgUICQAAAA==.',
Ze='Zelenã:BAAANQAECgEIAQAAAA==.Zelun:BAAANQAECgYIBwAAAA==.Zephon:BAAANQAECgYICAAAAA==.',
Zo='Zombiemarj:BAAANQADCggIEwAAAA==.',
['Zé']='Zéd:BAAANQAECgQIBwAAAA==.',
['Âx']='Âxel:BAAANQADCgUIBQABNQAECgYICgABAAAAAA==.',
['Æd']='Ædisgrace:BAAANQADCggIEgAAAA==.',
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
