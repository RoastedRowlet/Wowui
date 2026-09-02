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

local lookup = {'Unknown-Unknown','Paladin-Retribution',}
local provider = {region='US',realm='Bonechewer',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aandras:BAAANQADCgYIBgAAAA==.',
Ab='Abbey:BAAANQADCgYIBgAAAA==.Abhayah:BAAANQADCgYICAAAAA==.Absportls:BAAANQADCgcIBwAAAA==.',
Ac='Acelliste:BAAANQAECgMIAwAAAA==.',
Ad='Adventurerr:BAAANQADCgIIAgAAAA==.',
Af='Affgrezz:BAEANQADCgQIBAABNQADCggIDgABAAAAAA==.',
Ai='Aidlef:BAAANQADCggICAABNQAECgUIBQABAAAAAA==.Aikenbranwen:BAAANQADCgUICwAAAA==.',
Al='Alandor:BAAANQADCgUICgAAAA==.Allfire:BAAANQAECgUIBgAAAA==.Aluunix:BAAANQADCggIDgAAAA==.Alyse:BAAANQAECgQIBQAAAA==.Alyta:BAAANQADCgYIEQAAAA==.',
Am='Amayla:BAAANQADCgcIBwAAAA==.',
An='Anundir:BAAANQAECgEIAQAAAA==.',
Ao='Aondor:BAAANQAECgIIAgAAAA==.',
Ap='Applepi:BAAANQADCgEIAQAAAA==.',
Ar='Arcanical:BAAANQADCgUICgAAAA==.Arday:BAAANQAECgUIBQAAAA==.Aroromunroe:BAAANQADCgMIAwABNQADCggIDgABAAAAAA==.',
As='Ashblast:BAAANQADCgQIBAAAAA==.Ashira:BAAANQADCgcIDAABNQAECgQIBAABAAAAAA==.Astarouge:BAAANQAECgQIBAAAAA==.Astrasneaky:BAAANQAECgMIAwAAAA==.',
At='Atchafalaya:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.',
Av='Avatarstate:BAAANQADCgQIBAAAAA==.Avayl:BAAANQADCgIIAgAAAA==.',
Aw='Awrina:BAAANQADCgcIDQAAAA==.',
Az='Azylrog:BAAANQADCgQIBwAAAA==.',
Ba='Bakulu:BAAANQADCgYICwAAAA==.Bantoou:BAAANQADCgYICwAAAA==.Bathoryz:BAAANQAECgIIAwAAAA==.Battlescars:BAAANQADCgMIAwAAAA==.Bauhaus:BAAANQADCgIIAgAAAA==.Bauld:BAAANQADCgcICAAAAA==.',
Be='Beardybear:BAAANQAECgEIAQAAAA==.Bearicaide:BAAANQADCgYIBgAAAA==.Beautiful:BAAANQADCgYIBgAAAA==.Belldrak:BAAANQADCgUIBQAAAA==.Belldrin:BAAANQADCgQIBAAAAA==.Bepaulie:BAAANQADCgIIAgABNQADCggICAABAAAAAA==.',
Bi='Biglett:BAAANQAECgMIAwAAAA==.Bignagos:BAAANQADCgMIBAAAAA==.Bigthickheal:BAAANQADCgEIAQAAAA==.',
Bl='Blackk:BAAANQAECgQIBAAAAA==.Bladesong:BAAANQADCgQIBQAAAA==.Blorglock:BAAANQAECgYICAAAAA==.Blorgonw:BAAANQADCgYICwABNQAECgYICAABAAAAAA==.Blowaegis:BAAANQADCggIDgAAAA==.Blownoutshax:BAAANQADCgEIAQAAAA==.Blupenguiny:BAAANQAECgQIBAAAAA==.',
Bm='Bmfsleeps:BAAANQADCgUICAAAAA==.',
Bo='Boanz:BAAANQADCgUIBQAAAA==.Bobasaurus:BAAANQAECgQIBAAAAA==.Bombastik:BAAANQADCgYIBgAAAA==.Bountie:BAAANQADCggIEAAAAA==.Boyoyong:BAAANQADCgQIBAAAAA==.',
Br='Brandedsoul:BAAANQADCgIIAgAAAA==.Brewztler:BAAANQADCgMIBQAAAA==.Brightscale:BAAANQADCggIDgAAAA==.Broham:BAAANQAECgEIAQAAAA==.Bromeheal:BAAANQADCgIIAgAAAA==.Bronik:BAAANQADCgYICgAAAA==.',
Bu='Buffmage:BAAANQAECgQIBAAAAA==.Bullviper:BAAANQADCgYICQAAAA==.',
['Bè']='Bèrsèrk:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.',
['Bø']='Bønestørm:BAAANQAECgQIBQAAAA==.',
['Bù']='Bùndee:BAAANQADCgcICwAAAA==.',
Ca='Cabbâge:BAAANQADCgEIAQAAAA==.Caliex:BAAANQADCgYIBgAAAA==.Califax:BAAANQAECgQIBAAAAA==.Cannedbeans:BAAANQADCgMIAwAAAA==.Captantrips:BAAANQADCgQIBgAAAA==.Catazhanir:BAAANQADCgIIAgAAAA==.Catclown:BAAANQAECgIIAgAAAA==.Cazsandra:BAAANQAECgEIAQAAAA==.',
Cc='Ccs:BAAANQADCgQIBwAAAA==.',
Ch='Chamlio:BAAANQADCgMIBQAAAA==.Channis:BAAANQABCgQIBQAAAA==.Chenaccles:BAAANQADCgQIBAAAAA==.Chickenrally:BAAANQADCgEIAQAAAA==.Chinobear:BAAANQADCgYICgAAAA==.Chixilog:BAAANQADCgMIAwAAAA==.Chuchix:BAAANQAECgUICAAAAA==.Chuckler:BAAANQABCgQIAgAAAA==.',
Cl='Cladtu:BAAANQADCgcIBwAAAA==.Cleiah:BAAANQADCgUIBQAAAA==.Cloudfisto:BAAANQADCgYIBgAAAA==.',
Co='Colacolaz:BAAANQAECgcICwAAAA==.Colasham:BAAANQADCggICAABNQAECgcICwABAAAAAA==.Coldhands:BAAANQADCgEIAQABNQAECgIIAwABAAAAAA==.Colombiano:BAAANQADCgYIBwAAAA==.Coltoff:BAAANQAECgYICQAAAA==.Coprates:BAAANQADCgcICAAAAA==.Corgiquester:BAAANQADCgEIAQAAAA==.Corpserot:BAAANQADCgEIAQAAAA==.Corsin:BAAANQADCgQIBQAAAA==.Cowbustion:BAAANQAECgIIAwAAAA==.',
Cr='Cracken:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Crimsonrayne:BAAANQAECgEIAQAAAA==.Crusherlol:BAAANQADCgcIDAAAAA==.Crusherlul:BAAANQADCgQIBQABNQADCgcIDAABAAAAAA==.',
Da='Dannzig:BAAANQADCgEIAQAAAA==.Daragon:BAAANQADCgEIAQABNQAECgcIDAABAAAAAA==.Darkravèn:BAAANQAECgIIAgAAAA==.Darthkitsune:BAAANQADCgYICQAAAA==.Datbubblelol:BAAANQADCggICwAAAA==.Datchick:BAAANQADCgQIBwAAAA==.Dazbek:BAAANQAECgYIBwAAAA==.',
De='Deepdutch:BAAANQAECgEIAQAAAA==.Degeneffe:BAAANQADCgcIDQAAAA==.Demoreknight:BAAANQAECgQIBAAAAA==.Devilboy:BAAANQAECgQIBAAAAA==.',
Di='Dialuptacos:BAAANQABCgQIBAAAAA==.Diddycombs:BAAANQADCgYIBgAAAA==.Discbrown:BAAANQAECgYICwAAAA==.Discontent:BAAANQADCgIIAgAAAA==.',
Dj='Djblink:BAAANQADCgIIAgAAAA==.',
Dk='Dkgaming:BAAANQAECgEIAQAAAA==.',
Do='Dogeared:BAAANQAECgEIAQAAAA==.Domore:BAAANQADCggIDwAAAA==.Donson:BAAANQAECgQIBgAAAA==.Donsun:BAAANQADCgUIBQAAAA==.Doodlebobb:BAAANQADCgcIDQAAAA==.Doomlakalaka:BAAANQADCgUICgAAAA==.Doubleclap:BAAANQADCgQIBAAAAA==.',
Dp='Dpzofdoom:BAAANQADCgcIDQAAAA==.',
Dr='Dracthwnd:BAAANQAECgcIDQAAAA==.Dragbrown:BAAANQADCgYIBgAAAA==.Dragonsins:BAAANQAECgQIBQAAAA==.Drdiksmasher:BAAANQADCgUICQAAAA==.Drekka:BAAANQADCgEIAQAAAA==.Droptopp:BAAANQAECgQICAAAAA==.',
Du='Duckelf:BAAANQAECgQIBAAAAA==.Durrga:BAAANQAECgMIAwAAAA==.',
['Dã']='Dãftmõnk:BAAANQADCgYICgAAAA==.',
Eg='Egwenalmere:BAAANQADCgcIDAAAAA==.',
El='Elainia:BAAANQADCgUICAAAAA==.Elisaveta:BAAANQADCgMIAwAAAA==.Elliaa:BAAANQADCgQIBAAAAA==.Elodi:BAAANQADCgYIBgAAAA==.',
Em='Emanx:BAAANQABCgIIAgABNQADCggIDwABAAAAAA==.',
En='Enheduanna:BAAANQADCgUICAAAAA==.',
['Eì']='Eìrì:BAAANQADCgYICwAAAA==.',
['Eô']='Eôwyn:BAAANQADCgQIBwAAAA==.',
Fa='Faclion:BAAANQADCggIDgAAAA==.Faketurkey:BAAANQADCgcICAAAAA==.Fari:BAAANQADCgcICwAAAA==.Fatlootz:BAAANQAECgQIBQAAAA==.',
Fe='Feltyah:BAAANQADCgUICAAAAA==.',
Fi='Finnajuggyou:BAAANQAECgEIAQAAAA==.Finniker:BAAANQAECgIIAgAAAA==.Fiorina:BAAANQAECgIIAgAAAA==.Fishthicc:BAAANQADCgUICgAAAA==.',
Fl='Flashnikko:BAAANQADCgIIAgAAAA==.Flexkin:BAAANQAECgQIBAAAAA==.',
Fo='Foe:BAAANQAECgcICgAAAA==.Fornor:BAAANQAECgUIBwAAAA==.Foxfù:BAAANQADCgYICgAAAA==.Foxkníght:BAAANQAECgUIBwAAAA==.Foxxpachi:BAAANQADCgYICgAAAA==.',
Fr='Franký:BAAANQADCgUIBgAAAA==.Frogus:BAAANQAECgEIAQAAAA==.',
Fu='Fuule:BAAANQADCgcIDAAAAA==.Fuusei:BAAANQADCggIDgAAAA==.',
Fy='Fyrdrakon:BAAANQAECgIIAgAAAA==.',
Ga='Gabeitch:BAAANQADCgMIAwAAAA==.Galapagós:BAAANQADCgQIBwAAAA==.Galaxus:BAAANQAECgUICQAAAA==.Gammastorm:BAAANQAECgMIAwAAAA==.',
Gh='Ghall:BAAANQADCgIIAgAAAA==.Ghrell:BAEANQAECgIIAgAAAA==.',
Gi='Gickygackers:BAAANQADCgQICAAAAA==.Gigglepeak:BAAANQADCggIDQAAAA==.Girlhands:BAAANQADCgIIAgAAAA==.',
Gl='Glekimage:BAAANQAECgQIAwAAAA==.',
Go='Goatmylk:BAAANQADCgYIBwAAAA==.Gobblr:BAAANQADCgMIAwAAAA==.Gonuhreeuh:BAAANQADCgUIBQABNQAECgUICgABAAAAAA==.',
Gr='Grattick:BAAANQADCgYICwAAAA==.Greenlightt:BAAANQADCgMIBQAAAA==.Greenxll:BAAANQAECgQIBAAAAA==.Grezulock:BAEANQADCggIDgAAAA==.Griggles:BAAANQADCgMIAwAAAA==.Grizzbane:BAAANQADCgEIAQAAAA==.Grolk:BAAANQADCgUIBQAAAA==.',
Gu='Gumptruck:BAAANQAECgIIAgAAAA==.',
Gw='Gwenevere:BAAANQADCgMIAwAAAA==.',
Ha='Habibii:BAAANQADCgQIBAAAAA==.Hardendaire:BAAANQADCgMIAwAAAA==.Hashypally:BAAANQADCgEIAQAAAA==.Hathern:BAAANQADCgIIAgAAAA==.Hawkmees:BAAANQAECgIIAgAAAA==.Hazbretzul:BAAANQAECgQIBAAAAA==.',
He='Heelza:BAAANQADCgUIBQAAAA==.Hellskitchën:BAAANQADCgQIBAAAAA==.Help:BAAANQADCgIIAgAAAA==.Hephs:BAAANQADCgYIBwABNQADCggICAABAAAAAA==.Hermionejean:BAAANQADCgUIBQAAAA==.Hexuz:BAAANQAECgQIBAAAAA==.',
Hi='Hipster:BAAANQAECgIIAwABNQABCgIIAgABAAAAAA==.',
Ho='Holeekow:BAAANQADCgEIAgAAAA==.Hollymollie:BAAANQADCgQIBAAAAA==.Holypower:BAAANQADCgYICQAAAA==.Holythot:BAAANQAECgQIBQAAAA==.Hozrozlok:BAAANQAECgMIAwAAAA==.',
Hu='Hufgar:BAAANQADCgUIBwAAAA==.Huntdry:BAAANQADCgcIDAAAAA==.Hurkoh:BAAANQADCgcIDAAAAA==.Hushpuppié:BAAANQADCgMIAwAAAA==.',
Hy='Hypereon:BAAANQADCggIDwAAAA==.',
['Hé']='Héàthen:BAAANQADCgQIBAAAAA==.',
Ic='Icanthelpyou:BAAANQAECgEIAQAAAA==.Iceden:BAAANQADCgQIBAAAAA==.Icyweenor:BAAANQAECgEIAQAAAA==.',
Id='Idkdude:BAAANQAECgQIBAAAAA==.',
Ie='Ielarth:BAAANQADCgEIAQAAAA==.',
Il='Illadarina:BAAANQAECgIIAgAAAA==.',
In='Incetardis:BAAANQADCgQIBwAAAA==.',
Ir='Iradoria:BAAANQAECgQIBAAAAA==.',
Is='Isoldè:BAAANQABCgIIAgAAAA==.Istabu:BAAANQADCgYIBgAAAA==.',
It='Itachi:BAAANQAFFAIIAgAAAA==.Itamï:BAAANQAECgQIBAAAAA==.',
Ja='Jadawin:BAAANQAECgEIAQAAAA==.Jaketta:BAAANQADCgcIDAAAAA==.Jasnah:BAAANQAECgQIBAAAAA==.Jayrel:BAAANQAECgUIBwAAAA==.',
Je='Jerrik:BAAANQADCggIDgAAAA==.',
Ju='Juankkii:BAAANQADCgQIBAABNQADCgUIBgABAAAAAA==.Juggerbear:BAAANQADCgQICAAAAA==.Juls:BAAANQADCggIDgAAAA==.',
['Jä']='Jäger:BAAANQADCgcIBwAAAA==.',
Ka='Kagama:BAAANQADCgQIBwAAAA==.Kalatai:BAAANQAECgUIBAAAAA==.Kamisenshi:BAAANQADCgIIAgAAAA==.Karayna:BAAANQADCggICAAAAA==.Kauko:BAAANQADCggIDgAAAA==.',
Ke='Kezwik:BAAANQADCgcIDAAAAA==.',
Kh='Khaotick:BAAANQADCgMIBQAAAA==.Kheetz:BAAANQADCgcIBwAAAA==.',
Ki='Kilaaj:BAAANQADCgIIAgAAAA==.Killerbane:BAAANQADCgIIAgAAAA==.Kinthor:BAAANQABCgIIAgAAAA==.Kirrin:BAAANQAECgEIAQAAAA==.',
Kn='Kneecap:BAAANQADCggICAAAAA==.Kneepad:BAAANQADCgcIBwAAAA==.Knetikara:BAAANQAECgUIBgAAAA==.',
Ko='Kokokrantz:BAAANQADCgYICAAAAA==.Korthix:BAAANQADCgYIBgAAAA==.',
Kr='Kreiedril:BAAANQADCgQIBwAAAA==.Krispytoo:BAAANQAECgEIAQAAAA==.',
Ky='Kyokaii:BAAANQADCgMIAwAAAA==.',
La='Laarken:BAAANQADCggICQAAAA==.Lacedtotems:BAAANQAECgYICgAAAA==.Lagexe:BAAANQADCgcICQAAAA==.Lazlo:BAAANQAECgQIAwAAAA==.',
Le='Lenrela:BAAANQADCgYIBgAAAA==.Letena:BAAANQAECgQIBAAAAA==.Levyymage:BAAANQADCgQIBAAAAA==.',
Li='Licelia:BAAANQAECgQIBQAAAA==.Lilballohate:BAAANQADCgEIAQAAAA==.Liligayle:BAAANQADCgMIAwAAAA==.Linane:BAAANQAECgEIAQAAAA==.Lite:BAAANQADCggICQABNQAECgQIBAABAAAAAA==.Liveevil:BAAANQAECgcICAAAAA==.',
Lo='Loathsome:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.Lolmagician:BAAANQABCgIIAgABNQABCgQIBgABAAAAAA==.',
Lu='Lucifoor:BAAANQADCgMIBQAAAA==.Luftim:BAAANQAECgEIAQAAAA==.Lunoxx:BAAANQADCgUICAAAAA==.Lurang:BAAANQADCgcIBwAAAA==.',
Ma='Macdotnalds:BAAANQADCgMIAwAAAA==.Madetolock:BAAANQADCgMIBAAAAA==.Maerlyna:BAAANQABCgEIAQAAAA==.Magebrew:BAAANQADCgEIAQAAAA==.Mageycat:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Magicma:BAAANQAECgQIBAAAAA==.Makarov:BAAANQADCgEIAQAAAA==.Maliun:BAAANQADCgYIBgAAAA==.Malusdemon:BAAANQADCggIEQAAAA==.Mamasota:BAAANQADCgcIDQAAAA==.Marisol:BAAANQADCgMIAwAAAA==.Markfunk:BAAANQAECgYIBgAAAA==.Markiepoo:BAAANQADCgcIBwABNQAECgYIBgABAAAAAA==.Markyboom:BAAANQADCgIIAgABNQAECgYIBgABAAAAAA==.Markykong:BAAANQADCgIIAwABNQAECgYIBgABAAAAAA==.Mawmatz:BAAANQADCgEIAQAAAA==.',
Me='Meditations:BAAANQADCgEIAQAAAA==.Meleath:BAAANQADCgEIAQAAAA==.Melibeth:BAAANQABCgEIAQAAAA==.Metrakatanke:BAAANQADCgQIBAAAAA==.Mexiflip:BAAANQADCgMIAwAAAA==.',
Mi='Midoriya:BAAANQABCgIIAgAAAA==.Milgan:BAAANQAECgMIBAAAAA==.Minimochi:BAAANQAECgcIEgAAAA==.',
Mn='Mneme:BAAANQAECgcICwAAAA==.',
Mo='Monkeypiglet:BAAANQAECgYIBQAAAA==.Moogpal:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Moogul:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Morcarth:BAAANQADCggIDAAAAA==.Mortal:BAAANQADCgEIAQAAAA==.',
Mu='Mulks:BAAANQAECgUIBwAAAA==.Multiblox:BAAANQAECgQIBAAAAA==.Murgruuk:BAAANQADCggICAAAAA==.',
Na='Naam:BAAANQADCggICAAAAA==.Nadrin:BAAANQADCgUICgAAAA==.Naedora:BAAANQAECgEIAQAAAA==.Namixx:BAAANQAECgIIBQAAAA==.Naruwnd:BAAANQADCggICAABNQAECgcIDQABAAAAAA==.Nathaanis:BAAANQAECgYICgAAAA==.',
Ne='Necrodamus:BAAANQAECgEIAQAAAA==.Neopolitangs:BAAANQAECgIIAgAAAA==.Nezdispenser:BAAANQADCgQIBAAAAA==.',
Ni='Niduash:BAAANQADCgMIAwAAAA==.Nightchill:BAAANQADCggIDAAAAA==.Nimbletoes:BAAANQAECgQIBAAAAA==.Nirza:BAAANQADCgUIBwAAAA==.Niziel:BAAANQAECgQIBAAAAA==.',
No='Nofurrys:BAAANQADCgYIBgAAAA==.Nokorin:BAAANQADCgYIBwAAAA==.Nolo:BAAANQADCgUIBQABNQAECgYICAABAAAAAA==.Noros:BAAANQAECgYICAAAAA==.',
Nu='Nuggalicious:BAAANQADCgYIBgAAAA==.',
Om='Omenwar:BAAANQADCgUICQAAAA==.Omni:BAAANQADCggICwAAAA==.',
Or='Orelia:BAAANQADCgQIBAAAAA==.Ornarl:BAAANQAECgEIAQAAAA==.',
Ot='Ottawa:BAAANQADCgYIBgAAAA==.',
Pa='Packtastic:BAAANQAECgEIAQAAAA==.Padthang:BAAANQAECgEIAQAAAA==.Palazyn:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Parketor:BAAANQADCggICAAAAA==.',
Pe='Peachjars:BAAANQAECgQIBAAAAA==.Pelvis:BAAANQADCgQIBAAAAA==.Perixi:BAAANQADCgYICgAAAA==.Perpekto:BAAANQADCgUIBQAAAA==.',
Ph='Phedrah:BAAANQAECgEIAgAAAA==.',
Pi='Picklenator:BAAANQADCgYICwAAAA==.Pierreplays:BAAANQADCgUIBQAAAA==.Pillowhands:BAAANQADCgQIBAAAAA==.Pilto:BAAANQAECgEIAQAAAA==.Pingo:BAAANQADCgcIDQAAAA==.Pinkmj:BAAANQADCgMIBgAAAA==.Pitchief:BAAANQAECgEIAQAAAA==.',
Po='Polendina:BAAANQAECgQIBAAAAA==.Pooginator:BAAANQADCgYICAAAAA==.',
Pr='Primeork:BAAANQADCgUIBQAAAA==.',
Ps='Psammophile:BAAANQAECgQIBQAAAA==.Psymmer:BAAANQADCgIIAgABNQADCgYIEAABAAAAAA==.Psynnergy:BAAANQADCgYIEAAAAA==.Psytellar:BAAANQADCgEIAQABNQADCgYIEAABAAAAAA==.',
Pu='Puppyflower:BAAANQADCgUIBQAAAA==.Purplepally:BAAANQADCgEIAQAAAA==.Purpleshroom:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.Put:BAAANQADCgIIAwAAAA==.',
Py='Pyrat:BAAANQADCgcIDAAAAA==.Pyroangel:BAAANQADCgYICgAAAA==.Pyrotwopnto:BAAANQADCgYICQAAAA==.',
['Pí']='Píneapple:BAAANQAECgEIAQAAAA==.',
Qe='Qertinya:BAAANQADCgQIBQAAAA==.',
Qu='Quadman:BAAANQAECgUIBQAAAA==.Quinexorable:BAAANQAECgUIBwAAAA==.',
Ra='Ragedaddy:BAAANQAECgEIAQAAAA==.Rainndance:BAAANQADCgMIAwAAAA==.Raitan:BAAANQADCgQIBwAAAA==.Rallet:BAAANQADCgIIAgAAAA==.Ramrodveazy:BAAANQADCgcIGAAAAA==.Ranaklos:BAAANQADCgQIBAABNQADCgIIAgABAAAAAA==.Rancimus:BAAANQAECgQIBQAAAA==.Ranocthan:BAAANQAECgEIAQAAAA==.Rarcher:BAAANQAECgEIAQAAAA==.Rasmuz:BAAANQADCgIIAgAAAA==.Rauthar:BAAANQADCggICAAAAA==.Rayyven:BAAANQADCgQIBAAAAA==.Razorsharp:BAAANQAECgIIAgAAAA==.',
Re='Recon:BAAANQAECgYICQAAAA==.Reefermadnes:BAAANQAECgEIAgAAAA==.Reelsteel:BAAANQADCgIIAgAAAA==.Relnamah:BAAANQADCgQIBgAAAA==.Revdev:BAABNQAECoEUAAICAAgJFxQ+DQBLAgACAAgJFxQ+DQBLAgAAAA==.Revoke:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.Rezowulf:BAAANQADCgYICwAAAA==.',
Rh='Rhapsydee:BAAANQADCgUIBQAAAA==.Rhododendron:BAAANQADCgYIBgAAAA==.Rhoñin:BAAANQABCgEIAQAAAA==.Rhuney:BAAANQAECgEIAQAAAA==.Rhunie:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Rhyllii:BAAANQADCgcIDQAAAA==.',
Ri='Ripzug:BAAANQAECgQIAgAAAA==.',
Ro='Romenhoff:BAAANQAECgEIAQAAAA==.Rootbeer:BAAANQAECgEIAQAAAA==.Roshambu:BAAANQADCgQIBQAAAA==.',
Ru='Ruikiea:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.',
['Rà']='Ràggà:BAAANQADCgUIBgAAAA==.',
['Rí']='Rían:BAAANQADCgYICQAAAA==.',
Sa='Saelenei:BAAANQADCgIIAgABNQADCgYICQABAAAAAA==.Saevra:BAAANQADCgMIAwAAAA==.Sairadoka:BAAANQADCgcICAAAAA==.Samzori:BAAANQAECgEIAQAAAA==.Sanatizer:BAAANQAECgEIAQAAAA==.Sandret:BAAANQAECgEIAQAAAA==.Sarris:BAAANQADCggIDwAAAA==.Sathriel:BAAANQAECgIIBQAAAA==.Savagetotemz:BAAANQADCggIDQAAAA==.',
Sc='Scalelujah:BAAANQADCgUICAABNQAECgEIAQABAAAAAA==.Scottadin:BAAANQAECgQIBAAAAA==.',
Se='Secondenvoy:BAAANQADCggICQAAAA==.Seerawh:BAAANQAECgQIBAAAAA==.',
Sh='Shadownd:BAAANQAECgYICAABNQAECgcIDQABAAAAAA==.Shadowsloth:BAAANQABCgMIAwAAAA==.Shahli:BAAANQADCgIIAgAAAA==.Shakiro:BAAANQADCgMIAwABNQADCgYIBwABAAAAAA==.Shamergency:BAAANQADCgQIBQAAAA==.Shammyrock:BAAANQADCggIDgAAAA==.Shamtony:BAAANQABCgQIBgAAAA==.Shaylar:BAAANQADCgcICAAAAA==.Sherminator:BAAANQADCgIIAgABNQADCgYICwABAAAAAA==.Shiherlis:BAAANQADCgMIAwABNQADCgQIBAABAAAAAA==.Shmacken:BAAANQAECgIIAgAAAA==.Shockinglee:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Shosannaa:BAAANQADCgMIAwAAAA==.Shuriken:BAAANQAECgUIBwAAAA==.',
Si='Sikbubblez:BAAANQADCgYICAAAAA==.Sikshockz:BAAANQADCggICgAAAA==.Silverbow:BAAANQADCgQIBAAAAA==.Sindazia:BAAANQADCgYIBgAAAA==.Siopau:BAAANQADCgQIBAAAAA==.Sixunder:BAAANQADCgcIBwAAAA==.',
Sk='Skrinkles:BAAANQADCggIDgAAAA==.Skullwhisper:BAAANQAECgEIAQAAAA==.',
Sl='Slomar:BAAANQADCgUIBwAAAA==.Slowpallh:BAAANQADCgYICAAAAA==.Slowrog:BAAANQADCgUIAwABNQADCgYICAABAAAAAA==.Slowsh:BAAANQADCgUIBQABNQADCgYICAABAAAAAA==.',
Sm='Smoggely:BAAANQADCgcIDAAAAA==.Smoketotem:BAAANQADCgYICQAAAA==.',
Sn='Snowbreeze:BAAANQADCgcICAAAAA==.Snowfláme:BAAANQADCggIDwAAAA==.',
So='Solie:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Solki:BAAANQADCgIIAgAAAA==.Solrak:BAAANQADCgMIAwAAAA==.Soot:BAAANQAECgEIAQAAAA==.Soulcaller:BAAANQADCggICAAAAA==.Soulkrusher:BAAANQADCgYIBgAAAA==.',
Sp='Spadeii:BAAANQAECgQIBAAAAA==.Spagheddy:BAAANQADCgYIBgAAAA==.Spellzy:BAAANQAECgUICgAAAA==.Spicylatina:BAAANQADCgYIBgAAAA==.',
Ss='Sseoyoon:BAAANQADCgMIAwAAAA==.Ssnneezzyy:BAAANQADCgcIEQAAAA==.',
St='Starwnd:BAAANQAECgUIBQABNQAECgcIDQABAAAAAA==.Steadchi:BAAANQAECgQIBAAAAQ==.Stepbrodad:BAAANQADCgYICgAAAA==.Stolibear:BAAANQAECgIIAgAAAA==.Stolidh:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Stolidk:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Stoneycrusty:BAAANQAECgIIAwAAAA==.Straywalker:BAAANQADCgEIAQAAAA==.Stublimë:BAAANQADCgcIDAAAAA==.Studdie:BAAANQADCgMIAwAAAA==.',
Su='Succeeds:BAAANQADCgYICwAAAA==.Sungjinwooz:BAAANQAECgEIAQAAAA==.Suntitan:BAAANQADCgIIAgABNQADCgcIDQABAAAAAA==.Suuhdude:BAAANQADCgcICwAAAA==.',
Sw='Swd:BAAANQADCggIEAAAAA==.Swiffty:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Swudge:BAAANQADCgUIBgAAAA==.',
Sy='Syladeith:BAAANQAECgMIBAAAAA==.Sylbanas:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Syldrunk:BAAANQADCgcIBwAAAA==.',
['Sé']='Séii:BAAANQADCgYIBgAAAA==.',
Ta='Tabarnaka:BAAANQADCgYICgAAAA==.Tairnock:BAAANQADCggIDgAAAA==.Tanzee:BAAANQAECgUIBwAAAA==.Tarmesan:BAAANQAECgUIBwAAAA==.Tastytooth:BAAANQADCggICwAAAA==.Taytaytyrone:BAAANQADCgEIAQAAAA==.',
Te='Tegadin:BAAANQADCgMIBQAAAA==.Tensarion:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Tesse:BAAANQADCgMIAwAAAA==.',
Th='Thannos:BAAANQAECgQIBAAAAA==.Thanozul:BAAANQADCgcICQAAAA==.Thark:BAAANQADCggICAAAAA==.Thedùde:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Thelgrus:BAAANQADCgYICwAAAA==.Thorane:BAAANQADCgYIBgAAAA==.Thrashcan:BAAANQADCggIDwAAAA==.Threem:BAAANQADCgUIBQAAAA==.Threesteps:BAAANQADCgIIAgAAAA==.Throad:BAAANQADCgUIAQAAAA==.Throwbackhlz:BAAANQADCgUIBgAAAA==.Throwinshåde:BAAANQADCgMIAwAAAA==.Thudmuffin:BAAANQAECgQIBAABNQAECgMIAwABAAAAAA==.Thyrealest:BAAANQADCgEIAQAAAA==.',
Ti='Tides:BAAANQAECgMIAwAAAA==.Tinarii:BAAANQAECgUICQAAAA==.Tinyshadow:BAAANQADCgYICgAAAA==.Tinytit:BAAANQAECgEIAQAAAA==.Titpoosy:BAAANQADCgYIBgAAAA==.',
To='Tonystonk:BAAANQADCgUICgAAAA==.',
Tr='Tragha:BAAANQADCgIIAgAAAA==.Trayker:BAAANQADCgQIBAAAAA==.Traynisa:BAAANQADCgIIAwAAAA==.Treykor:BAAANQADCgQIBAAAAA==.Tria:BAAANQADCgUICQAAAA==.Trollsicle:BAAANQAECgMIAwAAAA==.Trotah:BAAANQADCgUIBQAAAA==.Tryzz:BAAANQAECgIIAgAAAA==.',
Tu='Tubhead:BAAANQADCgYICgAAAA==.Tunare:BAAANQADCgUICAAAAA==.Tusknflamer:BAAANQADCgUIBwAAAA==.',
Tw='Twylla:BAAANQAECgUIBgAAAA==.',
Ty='Tynak:BAAANQADCgQIBAAAAA==.',
Ug='Ugroto:BAAANQADCggIEAAAAA==.',
Uh='Uhrstaria:BAAANQADCggICAAAAA==.',
Un='Unclesnottyp:BAAANQADCgYIEAAAAA==.Unmortal:BAAANQADCggICAAAAA==.',
Ur='Uruker:BAAANQADCgIIAgAAAA==.',
Va='Valglacius:BAAANQADCgYICwAAAA==.Valkrin:BAAANQADCgYIBgAAAA==.Valonthir:BAAANQADCgQIBwAAAA==.Vancleave:BAAANQADCgUIBQAAAA==.Vaylethrayne:BAAANQABCgQIBQAAAA==.',
Ve='Verguetta:BAAANQADCgUIBgAAAA==.Verinsedai:BAAANQADCgcIDAAAAA==.Vesimer:BAAANQADCggICAAAAA==.',
Vi='Vicvondik:BAAANQADCgQIBAAAAA==.Vildri:BAAANQADCgcICAAAAA==.Violetknight:BAAANQADCgIIAgAAAA==.',
Vo='Voidrey:BAAANQAECgMIBAAAAA==.Voikullten:BAAANQADCgUIBQAAAA==.Vornash:BAAANQADCgUICAAAAA==.',
Vy='Vylent:BAAANQABCgQIBQAAAA==.',
Wa='Waddleweaver:BAAANQADCggICAAAAA==.Warkraz:BAAANQADCgIIAgAAAA==.Warrush:BAAANQADCggICgAAAA==.Watchmedps:BAAANQADCgQIBAAAAA==.',
Wi='Willpray:BAAANQAECgEIAQAAAA==.',
Wo='Wontondesire:BAAANQADCgcIDQAAAA==.',
Wu='Wulfdin:BAAANQADCggICAABNQADCgYICwABAAAAAA==.',
Xa='Xantry:BAEANQAECgEIAQAAAA==.',
Xb='Xbambs:BAAANQADCgQIBAAAAA==.',
Xe='Xerovladej:BAAANQADCgYICAAAAA==.',
Xo='Xoog:BAAANQADCgYICwAAAA==.',
Xw='Xwarrior:BAAANQAECgEIAQAAAA==.',
Ya='Yamata:BAAANQADCgQIBAAAAA==.',
Ye='Yetistorm:BAAANQADCgMIAwAAAA==.',
Yu='Yuee:BAAANQAECgMIAwAAAA==.',
Za='Zanarian:BAAANQADCgIIAgAAAA==.Zappinboi:BAAANQADCgYIBgABNQAFFAEIAQABAAAAAA==.Zatkiel:BAAANQADCgYIBgAAAA==.',
Ze='Zealot:BAAANQADCgYICQAAAA==.Zedar:BAAANQADCggIDwABNQADCggICwABAAAAAA==.Zeju:BAAANQADCgEIAQAAAA==.Zekinett:BAAANQADCgUIBQAAAA==.Zenolinwæ:BAAANQADCggIDgAAAA==.Zeohavoc:BAAANQADCgIIAgAAAA==.',
Zi='Zivanya:BAAANQADCgcIBwAAAA==.',
Zu='Zurprise:BAAANQADCgMIAwAAAA==.',
Zx='Zxz:BAAANQAECgIIAgAAAA==.',
Zy='Zyrgarran:BAAANQADCgUIBQAAAA==.',
['Zá']='Záraya:BAAANQAECgIIAwAAAA==.',
['Zú']='Zúpái:BAAANQADCgcIBwAAAA==.',
['Àz']='Àzæs:BAAANQADCgYICQAAAA==.',
['Ät']='Ätreo:BAAANQADCgMIAwAAAA==.',
['Æl']='Ælusive:BAAANQADCgcIBwAAAA==.',
['Ço']='Çondemned:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.',
['Ðr']='Ðräx:BAAANQADCggIDAAAAA==.',
['Óh']='Óhelgur:BAAANQADCgIIAgAAAA==.',
['Öh']='Öhgr:BAAANQADCggIDwAAAA==.',
['ßí']='ßíll:BAAANQADCgUIBQAAAA==.',
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
