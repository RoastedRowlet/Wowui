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
local provider = {region='US',realm='Trollbane',name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Acroin:BAAANQADCgQIBAAAAA==.',
Ad='Adorana:BAAANQADCgQIBAAAAA==.Adrunk:BAAANQAECgUIBQAAAA==.',
Ae='Aeloesh:BAAANQADCgIIAgAAAA==.Aelyra:BAAANQADCgYICAAAAA==.Aenatheon:BAAANQADCggIDQAAAA==.',
Ag='Aggrum:BAAANQADCgcIBwAAAA==.',
Ah='Ahexutroll:BAAANQADCgcIDQAAAA==.',
Ai='Aiur:BAAANQADCgYICgAAAA==.',
Ak='Akredfox:BAAANQADCgcIDAAAAA==.',
Al='Alexaviah:BAAANQADCgcICwAAAA==.Alicedelight:BAAANQAECgEIAQAAAA==.Alwaysburnt:BAAANQADCgUICQAAAA==.Alwayscooked:BAAANQADCgIIAgAAAA==.',
Am='Amabeast:BAAANQADCgUIBQAAAA==.Amisia:BAAANQADCgcIDAAAAA==.',
An='Anathas:BAAANQADCggIEAAAAA==.Angelfelis:BAAANQAECgUIBQAAAA==.Angriff:BAAANQADCgYIBgAAAA==.',
Ao='Aonaar:BAAANQADCgQIBQAAAA==.',
Ar='Archdemon:BAAANQAECgEIAQAAAA==.Arkroot:BAAANQADCggIDwAAAA==.',
As='Ashidpriest:BAEANQAECgQIBAAAAA==.Ashtoreth:BAAANQADCgYICwAAAA==.Assukun:BAAANQAECgMIAwAAAA==.Async:BAAANQAECgUIBQAAAA==.',
At='Ati:BAAANQADCgYIBgAAAA==.',
Au='Aurá:BAAANQADCgIIAgAAAA==.Autoattack:BAAANQADCgcIBwAAAA==.',
Ax='Axethegrippa:BAAANQAECgUIBgABNQAECgcIBwABAAAAAA==.Aximumeffort:BAAANQADCgYIBgABNQAECgcIBwABAAAAAA==.',
Ba='Badmac:BAAANQAECgQIBAAAAA==.Baelliman:BAAANQAECgIIAgAAAA==.Bakora:BAAANQADCggIDAAAAA==.Banishedfate:BAAANQADCgcIDAAAAA==.Banishedholy:BAAANQADCgEIAQABNQADCgcIDAABAAAAAA==.Baozi:BAAANQADCgUIBQABNQADCgcIDQABAAAAAA==.Barelyholy:BAAANQADCgcIDQAAAA==.Barf:BAAANQADCgEIAQABNQADCgcIDQABAAAAAA==.Barrendar:BAAANQADCgIIAgAAAA==.Bartholamew:BAAANQADCgQIBAAAAA==.',
Be='Bearballz:BAAANQADCgIIAgAAAA==.Berry:BAAANQAECgIIAgAAAA==.Besneakies:BAAANQAECgEIAQAAAA==.',
Bi='Bigdamfred:BAAANQADCgEIAQAAAA==.Binnford:BAAANQADCgQIBQAAAA==.',
Bl='Blackfang:BAAANQADCgUIBQABNQADCgcIBwABAAAAAA==.',
Bo='Bottombish:BAAANQADCggICAAAAA==.Boulderjaw:BAAANQADCgcICwAAAA==.Boxeybrown:BAAANQAECgQICQAAAA==.',
Br='Braised:BAAANQAECgEIAQAAAA==.Brbdeported:BAAANQADCgYICQAAAA==.Breakadakeys:BAAANQAECgMIBAAAAA==.Breccia:BAAANQADCgcIBwAAAA==.Brutanious:BAAANQADCgYICAAAAA==.',
Bu='Bubblebro:BAAANQAECgEIAQAAAA==.Buffwarrior:BAAANQAECgIIAwAAAA==.Bustamoon:BAAANQADCgIIAgAAAA==.Butterface:BAAANQADCgcIDAAAAA==.',
['Bà']='Bàckstabbath:BAAANQADCgMIAwAAAA==.',
Ca='Cammikins:BAEANQAECgQIBQAAAA==.Cantmilkem:BAAANQADCgIIAgAAAA==.Capellaz:BAAANQADCgcIDAAAAA==.Capriestson:BAAANQAECgEIAQAAAA==.Casandra:BAAANQAECgIIAQAAAA==.',
Ce='Celerynn:BAAANQADCgUIBQAAAA==.Centares:BAAANQADCgQIBAAAAA==.',
Ch='Charae:BAAANQAECgIIAgAAAA==.Charlutes:BAAANQADCgcIBwAAAA==.Chekzy:BAAANQADCgUIBQAAAA==.Chichii:BAAANQADCgYIBwAAAA==.Chilis:BAAANQADCgcIBwAAAA==.Chocolate:BAAANQADCgUICAAAAA==.Chudpath:BAAANQADCgcIDQABNQAECgQIBQABAAAAAA==.',
Cl='Cleome:BAAANQABCgEIAQAAAA==.',
Co='Coorsenjoyer:BAEANQAECgcIBwAAAA==.Copakid:BAAANQADCgcICgAAAA==.Cowlie:BAAANQAECgMIAwAAAA==.Coøkiewizard:BAAANQADCgEIAQAAAA==.',
Cr='Crippypal:BAAANQAECgEIAQABNQADCgIIAgABAAAAAA==.Crippyx:BAAANQADCgIIAgAAAA==.Cruelwar:BAAANQADCgcIBwAAAA==.',
Cu='Cuckcmder:BAAANQADCggIDQAAAA==.',
Da='Daffodil:BAAANQADCgEIAQAAAA==.Daggoth:BAAANQAECgEIAQAAAA==.Dalrak:BAAANQAECgQIBAAAAA==.Dandarth:BAAANQADCgMIAwAAAA==.Danemos:BAAANQADCgEIAQABNQADCgcIBwABAAAAAA==.Dante:BAAANQADCgcIBwABNQAECgMIAwABAAAAAA==.Darkendelf:BAAANQAECgEIAQAAAA==.Darkothy:BAAANQADCgYICwAAAA==.Datvoodoomon:BAAANQAECgQIBQAAAA==.Daïn:BAAANQADCggIDgAAAA==.',
Dc='Dcaý:BAAANQADCgIIAwABNQADCgYIBgABAAAAAA==.',
De='Deadjuggalo:BAAANQADCgQIBAAAAA==.Deadstep:BAAANQADCgcIBwAAAA==.Deleralia:BAAANQAECgQIBgAAAA==.Demontopher:BAAANQAECgcICgAAAA==.Deshaler:BAAANQADCgcIBwAAAA==.Devoidshield:BAAANQAECgIIAgAAAA==.',
Di='Dicon:BAAANQADCgYIBgAAAA==.Dieric:BAAANQADCgYICwAAAA==.Dividian:BAAANQAECgMIAwAAAA==.',
Do='Dorastrain:BAAANQAECgMIBAAAAA==.',
Dr='Dragonwyck:BAAANQADCgYIEQAAAA==.Draytheus:BAAANQADCgYIBQABNQADCgYICAABAAAAAA==.Dripping:BAAANQADCgYIBgAAAA==.',
Du='Duhdotsbruh:BAAANQADCgEIAQAAAA==.',
Ed='Edgarj:BAAANQADCgEIAQAAAA==.',
Ek='Eklipsch:BAAANQADCgIIAgAAAA==.',
El='Eld:BAAANQABCgMIAwAAAA==.Electabuzz:BAEANQADCgcIBwABNQAECgYICwABAAAAAA==.Electrocutey:BAAANQADCggIDQAAAA==.Elein:BAAANQADCgEIAQAAAA==.Eleman:BAAANQADCggIDAAAAA==.Elfclover:BAAANQAECgUIBgAAAA==.Elijahx:BAAANQAECgIIAgAAAA==.Elijay:BAAANQADCgcIBwAAAA==.Eljayye:BAAANQADCgQIBQAAAA==.',
Em='Emisha:BAAANQADCgIIAgAAAA==.Emmshunter:BAAANQADCggIBgAAAA==.',
Ep='Epicwarlock:BAAANQADCggICAAAAA==.Epona:BAAANQAECgQICAAAAA==.',
Er='Erzá:BAAANQAECgEIAQAAAA==.',
Et='Eterna:BAAANQADCggICAAAAA==.',
Ex='Exarchamus:BAAANQAECgMIBQAAAA==.',
Fa='Facemelt:BAAANQAECgEIAQAAAA==.Farfy:BAAANQAECgMIAwAAAA==.Fartsmagoo:BAAANQADCgYICwAAAA==.Faykan:BAAANQADCgcIEgAAAA==.',
Fe='Fedrameda:BAAANQADCgcICwAAAA==.Felix:BAAANQADCggIEAAAAA==.Fellender:BAAANQADCgUICQAAAA==.Fermented:BAAANQAECgIIAwAAAA==.',
Fi='Fizzle:BAAANQADCgQIBgAAAA==.',
Fl='Flintstones:BAAANQAECgEIAQAAAA==.Fluffykiitty:BAAANQADCgEIAQAAAA==.',
Fo='Fowlplay:BAAANQADCgQIBAAAAA==.Foxbox:BAAANQADCgYICgAAAA==.',
Fu='Fujee:BAAANQAECgEIAQAAAA==.Funkyt:BAAANQADCgcIDAAAAA==.',
['Fâ']='Fâlooga:BAAANQAECgEIAQAAAA==.',
Ga='Galadriael:BAAANQAECgQIBAAAAA==.Galtan:BAAANQADCgYICwAAAA==.Garrod:BAAANQADCggIDQAAAA==.Gattsu:BAAANQADCgcIDAAAAA==.',
Ge='Gennil:BAAANQAECgQIBQAAAA==.Gestella:BAAANQADCgYICwAAAA==.Gevo:BAAANQAECgMIAwAAAA==.',
Gl='Gloomblade:BAAANQAECgcIDQAAAA==.',
Gn='Gnomepimp:BAAANQADCgYIBgAAAA==.',
Gr='Grayscale:BAAANQADCgEIAQAAAA==.Greyseer:BAAANQADCgcIDAAAAA==.',
Gu='Guymontag:BAAANQAECgQICAAAAA==.',
Ha='Harbard:BAAANQAECgIIAgAAAA==.Hasselhøøf:BAAANQAECgEIAQAAAA==.Hawkeyeik:BAAANQADCggIDgAAAA==.Hawthorne:BAAANQADCggIDgAAAA==.Hayywaffle:BAAANQADCgQIBAAAAA==.',
He='Hellothere:BAAANQAECgIIAgAAAA==.Hellren:BAAANQADCgMIAwAAAA==.Helmet:BAAANQADCgQIBAAAAA==.',
Hi='Hikons:BAAANQAECgIIAwABNQAECgMIAwABAAAAAA==.Hinkle:BAAANQADCgQIBAABNQADCgYICQABAAAAAA==.',
Ho='Holysage:BAAANQADCgcIBwAAAA==.Holytoad:BAAANQADCgYIBgAAAA==.Hopsquash:BAAANQABCgIIAgAAAA==.Hopstop:BAAANQADCgcIDAAAAA==.',
Hu='Hughass:BAAANQADCgUIDAABNQAECgMIBQABAAAAAA==.Hugo:BAAANQADCgUIBQAAAA==.Huwglyndur:BAAANQADCgcIDAAAAA==.',
Hy='Hyperiunpala:BAAANQADCggIDQAAAA==.',
Id='Idispizhorde:BAAANQAECgIIAgAAAA==.',
Ig='Igris:BAAANQADCgcIDAAAAA==.',
Il='Illihottie:BAAANQADCgQIBAAAAA==.Illiora:BAAANQADCgYIBQABNQAECgQIBwABAAAAAA==.Illissia:BAAANQADCgMIAwAAAA==.',
Ir='Ironpreacher:BAAANQADCgYIBQAAAA==.Ironspite:BAAANQADCgYIBQAAAA==.',
Is='Ish:BAAANQAECgYICAAAAA==.Ishibad:BAAANQADCgcIBwABNQAECgYICAABAAAAAA==.Isolie:BAAANQADCgUIBQAAAA==.Isongard:BAAANQABCgIIAgAAAA==.',
It='Itsthesham:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.',
Iv='Ivok:BAAANQADCgUIBgAAAA==.',
Ja='Jatbez:BAAANQADCgIIAgAAAA==.Jaykay:BAAANQADCgMIAwAAAA==.Jazmìne:BAAANQADCgcICwAAAA==.',
Je='Jezuz:BAAANQADCggICAAAAA==.',
Ji='Jimmieslock:BAAANQAECgcIDQAAAA==.',
Jk='Jkils:BAAANQADCgQIBAAAAA==.',
Jo='Jonbaptist:BAAANQADCggIDwAAAA==.',
Jt='Jtrain:BAAANQADCggIDQAAAA==.',
Ju='Judwin:BAAANQADCggICQAAAA==.',
['Jä']='Jäzmine:BAAANQADCgIIAgAAAA==.',
['Jè']='Jèssicà:BAAANQAECgQIBAAAAA==.',
['Jô']='Jôseph:BAAANQADCgUIBgAAAA==.',
['Jö']='Jöe:BAAANQADCgIIAgAAAA==.',
Ka='Kaalin:BAAANQADCgIIAgAAAA==.Kabutosan:BAAANQADCgcIBwAAAA==.Kaleesi:BAAANQADCgUICQAAAA==.Kamots:BAAANQAECgIIAgAAAA==.Kareokee:BAAANQAECgIIAgAAAA==.Kargoroth:BAAANQAECgcICwAAAA==.Karral:BAAANQAECgQIBQAAAA==.Kazdormu:BAAANQAECgMIBAAAAA==.',
Ke='Kedira:BAAANQADCggIEAABNQAECgQICgABAAAAAA==.',
Kh='Khadriel:BAAANQAECgQIBQAAAA==.',
Ki='Kitani:BAAANQAECgUICQAAAA==.',
Kn='Knottybits:BAAANQADCgcIBwABNQADCgcIBwABAAAAAA==.',
Ko='Konsumer:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.Konân:BAAANQADCggIEAAAAA==.Korvakh:BAAANQADCgYIBgAAAA==.',
Kr='Kraduun:BAAANQADCgYIBgAAAA==.Krenniellin:BAAANQAECgEIAQAAAA==.Krys:BAAANQADCggIDwAAAA==.',
La='Lambadin:BAAANQADCgMIAwAAAA==.',
Le='Leizil:BAAANQAECgMIAwAAAA==.Lennox:BAAANQADCggIEAAAAA==.',
Lh='Lhuani:BAAANQAECgUIBwAAAA==.',
Li='Lightmyhole:BAAANQADCgEIAQABNQADCggIBgABAAAAAA==.Like:BAAANQADCgUIBQAAAA==.Lilyachty:BAAANQADCgUICgABNQAECgMIAwABAAAAAA==.Linshe:BAAANQAECgIIBAAAAA==.',
Ll='Llillianna:BAAANQADCgUIBQAAAA==.',
Lu='Lucarien:BAAANQAECgMIBQAAAA==.Lustyglory:BAAANQADCggICAAAAA==.',
Ma='Madeintyø:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Mageaga:BAAANQADCgQIBQAAAA==.Magnathul:BAAANQAECgQIBAAAAA==.Makeah:BAAANQAECgQIBAAAAA==.Makhamou:BAAANQADCggIDwAAAA==.Malinstur:BAAANQADCggIDgAAAA==.Marjorye:BAAANQADCgIIBAAAAA==.Marnaught:BAAANQADCgcIBwAAAA==.Mashed:BAAANQADCgUIBQAAAA==.Matts:BAAANQADCggIDwAAAA==.Mazaal:BAAANQAECgQIBQAAAA==.',
Mc='Mcshaft:BAAANQABCgQIBQAAAA==.',
Me='Mekeena:BAAANQADCgYIDAAAAA==.Melesandre:BAAANQADCgIIAgAAAA==.Mellinda:BAAANQADCgYICgAAAA==.Melzas:BAAANQADCgcIDAAAAA==.',
Mi='Midrok:BAAANQAECgQICAAAAA==.Missyennefer:BAAANQADCgYIDAAAAA==.',
Mo='Mobythicc:BAAANQADCgcICAABNQAECgcIBwABAAAAAA==.Mondai:BAAANQABCgQIBAAAAA==.Monkpowahh:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Montag:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.Moonboomfred:BAAANQADCgMIAwAAAA==.Moonshower:BAAANQADCggIDgAAAA==.Morgaenei:BAAANQABCgMIAwAAAA==.',
Mt='Mtastyck:BAAANQADCgYICAAAAA==.',
Mu='Mudsniffer:BAAANQAECgEIAQAAAA==.Multitool:BAEANQAECgMIAwAAAA==.Mundekk:BAAANQADCgcICAAAAA==.',
My='Myobûky:BAAANQADCgUIBQAAAA==.Mythgleam:BAAANQADCgEIAQAAAA==.Myththistle:BAAANQADCgEIAQAAAA==.',
['Má']='Mániac:BAAANQADCgUIBgAAAA==.',
Na='Nacks:BAAANQAECgUIBQAAAA==.Nacksd:BAAANQADCgEIAQABNQAECgUIBQABAAAAAA==.Nacksly:BAAANQAECgIIAgABNQAECgUIBQABAAAAAA==.Nacksp:BAAANQADCgUIBQABNQAECgUIBQABAAAAAA==.Naliön:BAAANQADCgUIBwAAAA==.Naotsugu:BAAANQADCgUIBQAAAA==.Nasarden:BAAANQAECgEIAQAAAA==.Nasir:BAAANQADCgUIBQAAAA==.Nastysage:BAAANQAECgEIAQAAAA==.Naxdh:BAAANQADCgEIAQABNQAECgUIBQABAAAAAA==.',
Ne='Nessië:BAAANQADCggIDwAAAA==.Nesthor:BAAANQADCgYIBgAAAA==.',
Ni='Nimibear:BAAANQAECgIIAgAAAA==.Nimidk:BAAANQAECgYICQAAAA==.Ninjahealer:BAAANQADCgcICgAAAA==.',
No='Nooffensë:BAEANQADCgcIDAAAAA==.',
Nu='Nutdevourer:BAAANQADCgcIFAAAAA==.',
['Né']='Néther:BAAANQADCgUIBQAAAA==.',
Oa='Oakelvin:BAAANQADCgUIBQAAAA==.',
Ob='Obnoxiousego:BAAANQAECgQIBAAAAA==.',
Od='Oddknee:BAAANQAECgYICAAAAA==.Odney:BAAANQADCgYIDAABNQAECgYICAABAAAAAA==.',
On='Onaria:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.',
Or='Oridox:BAAANQAECgEIAQAAAA==.Orumine:BAAANQAECgQIBQAAAA==.',
Pa='Papii:BAAANQAECgIIAgAAAA==.Paratussum:BAAANQADCgYIBgAAAA==.Parka:BAAANQADCggIDgAAAA==.',
Pb='Pbody:BAAANQADCgUIBQAAAA==.',
Pe='Perhorn:BAAANQADCgQIBAAAAA==.',
Po='Polunocnicá:BAAANQADCgYIDAAAAA==.Pooj:BAAANQADCggIDQAAAA==.',
Pr='Primetime:BAAANQADCgcIDgAAAA==.Prissila:BAAANQADCgYICQAAAA==.Prollimix:BAAANQADCgcIDQAAAA==.',
Ps='Psychoshorts:BAAANQADCgcIBQAAAA==.Psykick:BAAANQADCgEIAQAAAA==.',
Ra='Rachela:BAAANQADCgQIBAAAAA==.Ractiel:BAAANQADCgIIAwAAAA==.Raidhero:BAAANQADCgMIAwAAAA==.Rain:BAAANQADCggICAAAAA==.Raked:BAAANQAECgEIAQAAAA==.Ranfna:BAAANQADCgEIAQAAAA==.Rapidkiill:BAAANQADCgMIAwAAAA==.Raspberrytea:BAAANQABCgIIAwAAAA==.',
Re='Reebz:BAAANQADCgYIBQABNQAECgQIBQABAAAAAA==.Reflection:BAAANQAECgEIAQAAAA==.Rekcutnerd:BAAANQADCgYICAAAAA==.Reppa:BAAANQADCggICAAAAA==.Retiniris:BAAANQAECgQICAAAAA==.',
Rh='Rhonstaris:BAAANQADCgYICAAAAA==.',
Ri='Riceporridge:BAAANQADCgcIDQAAAA==.Riskofrain:BAAANQADCgYIBgAAAA==.Ritzcarltina:BAAANQADCgIIAgAAAA==.Ritzu:BAAANQADCggICAAAAA==.',
Ro='Roxyviper:BAAANQADCgQIBQAAAA==.Royalfox:BAAANQAECgEIAQAAAA==.',
Ru='Rubbish:BAAANQADCgYICgAAAA==.',
Sa='Saatari:BAAANQADCgUICQAAAA==.Saddeath:BAAANQADCgYIBgAAAA==.Saeylaura:BAAANQADCgYICwAAAA==.Saintchuck:BAAANQADCgUICAAAAA==.Salanaar:BAAANQAECgQIBQAAAA==.Salarix:BAAANQADCgYICgAAAA==.Sarja:BAAANQADCgYICwAAAA==.Sarras:BAAANQADCgEIAQAAAA==.Sasserfrass:BAAANQADCggIDwAAAA==.Sayy:BAAANQAECgMIAwAAAA==.',
Se='Seaotter:BAAANQAECgEIAQAAAA==.Senhonrue:BAAANQADCgYIBgAAAA==.Serabian:BAAANQADCgUIBQAAAA==.Seraz:BAAANQAECgUICQAAAA==.Serenitey:BAAANQADCgQIBQAAAA==.Serraglyndur:BAAANQADCgcIDAAAAA==.',
Sh='Shaderaina:BAAANQADCgMIAwAAAA==.Shambe:BAAANQADCgIIAgAAAA==.Sheabutters:BAAANQADCgYICQAAAA==.Shmorg:BAAANQAECgIIAgAAAA==.Shunaiman:BAAANQADCgcIDAAAAA==.Shàdowdànce:BAAANQADCgUIBQAAAA==.Shábam:BAAANQADCgQIBAAAAA==.',
Si='Sifferr:BAAANQADCgcICwAAAA==.Sijinn:BAAANQADCgUIBQAAAA==.',
Sk='Skotom:BAAANQADCgUIBQAAAA==.Skyjericho:BAAANQADCgYICAAAAA==.',
Sl='Slattpal:BAAANQAECgUICAAAAA==.Sleebyevoker:BAAANQAECgUIBgAAAA==.',
So='Solistome:BAAANQADCgQIBQAAAA==.Somarlar:BAAANQADCgMIAwAAAA==.Sopho:BAAANQADCgcIDAAAAA==.',
Sp='Specialtea:BAAANQADCgUIBwAAAA==.',
Sq='Squam:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.',
St='Stonebones:BAAANQADCgYIAQAAAA==.Strappy:BAAANQADCgcIBwAAAA==.Stwife:BAAANQAECgcIDQAAAA==.',
Su='Sufrucia:BAAANQADCggICAAAAA==.Sunday:BAAANQAECgQIBAAAAA==.Surâ:BAAANQAECgIIAgAAAA==.',
Sy='Symbol:BAAANQAECgMIAwABNQAECgIIAgABAAAAAA==.Sympissal:BAAANQADCggICwAAAA==.',
['Sò']='Sònya:BAAANQAECgMIAwAAAA==.',
Ta='Tagritalth:BAAANQABCgMIAwAAAA==.Taindnddra:BAAANQADCgEIAQABNQADCgQIBAABAAAAAA==.Talanas:BAAANQADCgUIBQAAAA==.Tanishalfelf:BAAANQAECgcIDQAAAA==.',
Th='Thalassikos:BAAANQADCgYICwAAAA==.Thatredhead:BAAANQADCgUIBAAAAA==.Thewraith:BAAANQAECgEIAQAAAA==.Thorcised:BAAANQAECgUIBgAAAA==.Thorin:BAAANQADCggIDQAAAA==.Thoryndir:BAAANQAECgQIBAAAAA==.Thrym:BAAANQADCgcIBwAAAA==.',
Ti='Tidalsong:BAAANQADCgUICAAAAA==.',
Tk='Tkenga:BAAANQADCgcIDAAAAA==.',
To='Tojarm:BAAANQADCgEIAQAAAA==.Tonicdeath:BAAANQADCgcIDQAAAA==.',
Tr='Tralzind:BAAANQADCgMIAwAAAA==.Truthsayer:BAAANQAECgEIAQAAAA==.',
Ts='Tsquared:BAAANQAECgMIAwAAAA==.',
Tu='Tukk:BAAANQADCgUIBQAAAA==.Tumnina:BAAANQADCgUIBQAAAA==.',
Tw='Twopuffs:BAAANQADCgYIBgAAAA==.',
Ty='Tyce:BAAANQAECgEIAQAAAA==.Tylannis:BAAANQAECgQIBQAAAA==.Tyranitar:BAEANQAECgYICwAAAA==.',
Ug='Ugacoop:BAAANQAECgQIBAAAAA==.',
Va='Vaelisara:BAAANQADCgcIDAAAAA==.',
Ve='Veldrys:BAAANQADCgUIBAABNQAECgEIAQABAAAAAA==.Veledaa:BAAANQADCgUIBQAAAA==.Verige:BAAANQADCgYIBgAAAA==.Vetis:BAAANQABCgEIAQAAAA==.',
Vi='Vicars:BAAANQADCgUIBQABNQADCgUIBQABAAAAAA==.Visionblast:BAAANQADCgEIAQAAAA==.Vixyn:BAAANQABCgQIBQAAAA==.',
Vo='Voidme:BAAANQADCgEIAQAAAA==.Vorellyn:BAAANQADCgYIBgAAAA==.',
['Và']='Vàlorie:BAAANQAECgYICAAAAA==.',
['Vè']='Vèlkhànà:BAAANQAECgEIAQAAAA==.',
Wa='Wangdaulf:BAAANQADCgQICAAAAA==.Wardoogy:BAAANQADCggICAAAAA==.Warglaíves:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.Warsmedic:BAAANQAECgEIAQAAAA==.',
Wh='Whumha:BAAANQADCgQIBAAAAA==.',
Wi='Williams:BAEANQADCgcIBwABNQAECgYICwABAAAAAA==.Winkel:BAAANQADCgQIBAAAAA==.',
Wo='Woopiing:BAEANQADCggIDQAAAA==.Woubbie:BAAANQABCgIIAwAAAA==.',
Wu='Wuhpow:BAAANQADCgIIAgAAAA==.Wunna:BAAANQAECgMIAwAAAA==.',
['Wá']='Wármonger:BAAANQADCgIIAgAAAA==.',
Xi='Xionz:BAAANQADCgcIDQAAAA==.',
Ya='Yakella:BAAANQADCggIEgAAAA==.',
Ye='Yelgrun:BAAANQADCgYICwAAAA==.Yellcat:BAAANQAECgYIBwAAAA==.',
Yh='Yhoda:BAAANQAECgQIBQAAAA==.',
Yo='Youseitgar:BAAANQADCgMIAwAAAA==.',
Yu='Yuisis:BAAANQADCggICAAAAA==.',
Za='Zabidu:BAAANQAECgQIBQAAAA==.Zappyketch:BAAANQAECgQIBgAAAA==.Zaraeiri:BAAANQADCgUIBQAAAA==.Zaraxaà:BAAANQADCgUIBQAAAA==.',
Ze='Zelenã:BAAANQADCgYICQAAAA==.Zelun:BAAANQADCgUIBQAAAA==.Zephon:BAAANQAECgEIAgAAAA==.',
Zo='Zombiemarj:BAAANQADCgYICwAAAA==.',
['Zé']='Zéd:BAAANQAECgMIAwAAAA==.',
['Æd']='Ædisgrace:BAAANQADCgYICgAAAA==.',
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
