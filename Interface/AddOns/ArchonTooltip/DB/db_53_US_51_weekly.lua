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
local provider = {region='US',realm='Cenarius',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aalen:BAAANQAECgYICQAAAA==.',
Ab='Aby:BAAANQADCgcIDAAAAA==.',
Ac='Achooah:BAAANQAECgcIDQAAAA==.Acturus:BAAANQADCgcIDQAAAA==.',
Ae='Aela:BAAANQADCgcIBwAAAA==.Aenie:BAAANQADCgMIAwAAAA==.Aerose:BAAANQADCgYICwAAAA==.Aethelia:BAAANQADCgMIAwAAAA==.',
Ak='Aki:BAAANQADCgYICwAAAA==.',
Al='Alumeena:BAAANQADCgYICwAAAA==.',
Am='Amylynn:BAAANQADCgYICgAAAA==.Amyquivers:BAAANQADCgYICgAAAA==.',
An='Andarieal:BAAANQADCgcIDQAAAA==.Ankhling:BAAANQAECgQIBAAAAA==.Annahlia:BAAANQADCgQIBAAAAA==.Anyafire:BAAANQADCgUICgAAAA==.',
Ap='Appian:BAAANQADCgYIBgAAAA==.',
Ar='Aralye:BAAANQADCgMIAwAAAA==.Armîda:BAAANQADCggIDwAAAA==.Arnika:BAAANQADCgYICwAAAA==.Arvalyn:BAAANQAECgEIAQAAAA==.',
As='Ashlien:BAAANQADCgQIBAAAAA==.Astralvoid:BAAANQADCgcIDQAAAA==.Asuya:BAAANQABCgIIAwAAAA==.',
At='Atalune:BAAANQADCgYIBgAAAA==.',
Au='Aus:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.',
Av='Avakai:BAAANQADCgEIAQAAAA==.',
Ax='Axazon:BAAANQAECgQIBQAAAA==.',
Ba='Bartholoméw:BAAANQAECgQIBwAAAA==.Bascus:BAAANQADCggIDgAAAA==.Bassuu:BAAANQADCgcIDQAAAA==.Battle:BAAANQABCgQIAQAAAA==.',
Be='Beefdaddy:BAAANQAECgIIAgAAAA==.Beendayho:BAAANQADCgMIAwAAAA==.Beerrun:BAAANQADCgEIAQAAAA==.Belfør:BAAANQADCgYIDAAAAA==.Bellius:BAAANQAECgMIAwAAAA==.Bennissia:BAAANQADCgYICwAAAA==.Betula:BAAANQADCgQIBwAAAA==.',
Bi='Bigolbert:BAAANQADCgQIBQAAAA==.Bipolaire:BAAANQADCgMIAwAAAA==.',
Bl='Blazefury:BAAANQADCgYIBgAAAA==.',
Bo='Bobsalami:BAAANQADCgMIAwAAAA==.Boragarsh:BAAANQADCggIDAAAAA==.Bowlyne:BAAANQAECgQIBQAAAA==.Boyz:BAAANQADCgYIDAAAAA==.',
Br='Brannflake:BAAANQADCgYIAwABNQAECgYIBgABAAAAAA==.Brewkong:BAEANQADCgYIBgAAAA==.Bruhsabi:BAAANQADCgYICgAAAA==.Brumsta:BAAANQAECgQIBAAAAA==.Brutalious:BAAANQADCgYIBwAAAA==.Bruutii:BAAANQAECgUICAAAAA==.',
Bu='Bubbleandrun:BAAANQAECgIIAgAAAA==.Buckcherry:BAAANQADCggIDgAAAA==.Bulvaan:BAAANQAECgEIAQAAAA==.',
['Bì']='Bìtterbabe:BAAANQADCgYIBgAAAA==.',
Ca='Caell:BAAANQADCgcIDAAAAA==.Calair:BAAANQADCgIIAgAAAQ==.Calandia:BAAANQADCggIDQAAAA==.Cannonia:BAAANQAECgQICQAAAA==.Cantdance:BAAANQADCgIIAgAAAA==.Catrunner:BAAANQADCgMIAwAAAA==.Cayvie:BAAANQADCgYIDAAAAA==.',
Ce='Cedroes:BAAANQAECgUIBgAAAA==.Celandine:BAAANQADCgcIDQAAAA==.Cerenus:BAAANQADCgcIDQAAAA==.',
Ch='Chaoswolf:BAAANQADCgMIAwAAAA==.Chickfilafry:BAAANQADCgcIDAAAAA==.Chipadip:BAAANQAECgYICQAAAA==.Chiqasaurus:BAAANQAECgEIAQAAAA==.',
Ci='Cindoria:BAAANQADCggIDAAAAA==.Cinzia:BAAANQADCggICAAAAA==.',
Cl='Clockblocked:BAAANQAECgIIAgAAAA==.Clolarion:BAAANQADCgcICwAAAA==.',
Co='Coltyn:BAAANQADCggIDwAAAA==.Contrakt:BAAANQADCgcIDQAAAA==.',
Cr='Crashcash:BAAANQADCgQIBAAAAA==.',
Cu='Curiel:BAAANQADCggIDAAAAA==.Cutters:BAAANQADCgMIBAAAAA==.',
Cv='Cviper:BAAANQAECgUICAAAAA==.',
Cy='Cyanos:BAAANQADCgYICwAAAA==.Cymbre:BAAANQADCgYIDAAAAA==.',
Da='Dad:BAAANQADCggIDQAAAA==.Dae:BAAANQADCgcIDQAAAA==.Dallinarr:BAAANQADCgUIBQAAAA==.Darkhrt:BAAANQADCgcIDAAAAA==.Dazedxar:BAAANQADCggICAAAAA==.',
De='Deadtotem:BAAANQADCgUICQAAAA==.Deathdeath:BAAANQAECgIIAgAAAA==.Deathwavez:BAAANQAECgQIBQAAAA==.Degaen:BAAANQADCgEIAQAAAA==.Delirium:BAAANQADCgYICwAAAA==.Dennis:BAAANQAECgYICQAAAA==.Deosil:BAAANQADCgUIBQAAAA==.Departéd:BAEANQAECggIDQAAAA==.Deplete:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Derasia:BAAANQADCgIIAgAAAA==.Deyvia:BAAANQADCgEIAQAAAA==.',
Di='Dinothunder:BAAANQADCgcIDgAAAA==.Dippindots:BAAANQADCgYIBgABNQAECgYIBgABAAAAAA==.Dirf:BAAANQADCgMIAwAAAA==.Discobear:BAAANQAECgcICgAAAA==.',
Do='Doomui:BAAANQADCgIIAgAAAA==.Doruh:BAAANQAECgEIAQAAAA==.Dotdragon:BAAANQADCgEIAQAAAA==.',
Dr='Draegon:BAAANQADCgEIAQABNQADCgcIDQABAAAAAA==.Draenorious:BAAANQADCgcIDQAAAA==.Dragonix:BAAANQADCgcIDQAAAA==.Drakonetta:BAAANQADCgUICQAAAA==.',
Du='Dudris:BAAANQADCgcIBwAAAA==.Dumbasmus:BAAANQADCgcIDAAAAA==.',
['Dä']='Däkk:BAAANQADCggICAAAAA==.',
['Dé']='Déathgoddess:BAAANQADCggICgAAAA==.',
Ea='Eavie:BAAANQADCgcIBwAAAA==.',
Ed='Ediah:BAAANQADCgYICwAAAA==.Edibleundies:BAAANQADCgMIBQAAAA==.',
Ee='Eeveé:BAAANQADCgIIAgAAAA==.',
El='Electronaut:BAEANQADCggIDQAAAA==.Elee:BAAANQADCgMIAwAAAA==.Eljefe:BAAANQADCgEIAQAAAA==.Elleria:BAAANQADCgUIBgAAAA==.',
Em='Emeraldstar:BAAANQADCgIIAgAAAA==.',
En='Envelion:BAAANQAECgIIAgAAAA==.',
Er='Erand:BAAANQADCgQIBAAAAA==.',
Es='Esvanka:BAAANQAECgQIBAAAAA==.',
Et='Ethuul:BAAANQABCgIIAgAAAA==.',
Eu='Euterpe:BAAANQAECgEIAQAAAA==.',
Ex='Exoddus:BAAANQADCgcICgAAAA==.',
Fa='Faein:BAAANQADCgQIBAAAAA==.Faelynatlyf:BAAANQADCggIDwAAAA==.Falamoto:BAAANQADCgYICQAAAA==.Fallen:BAAANQADCgYICwAAAA==.Fangskin:BAAANQAECgIIAwAAAA==.',
Fe='Feltoast:BAAANQADCgEIAQABNQADCgQIBQABAAAAAA==.Feyn:BAAANQADCgQIBAAAAA==.',
Fh='Fhaeos:BAAANQADCgQIBgAAAA==.',
Fi='Fiode:BAAANQADCgYICwAAAA==.',
Fj='Fjall:BAAANQADCgUIBQAAAA==.',
Fl='Flipsmage:BAAANQADCgUIBQAAAA==.',
Fo='Foomanpan:BAAANQADCggICAAAAA==.',
Fr='Fresh:BAAANQADCgcIDQAAAA==.Frieren:BAAANQADCggIDQAAAA==.Frostea:BAAANQADCgcIBwAAAA==.Fruitloops:BAAANQADCgQIAwABNQAECgYIBgABAAAAAA==.',
Fu='Fuzybear:BAAANQADCgEIAQABNQADCgYICwABAAAAAA==.',
Fy='Fyo:BAAANQAECgYICQAAAA==.',
['Fä']='Fäyëth:BAAANQADCggIDAAAAA==.',
Ga='Gankz:BAAANQAECgEIAQAAAA==.Gargon:BAAANQADCgcIDQAAAA==.Gatchagooner:BAAANQAECgMIAwAAAA==.Gautham:BAAANQADCgIIAgAAAA==.',
Gi='Gihum:BAAANQADCgMIAwAAAA==.Ginjjow:BAAANQADCgUIBQAAAA==.Girthquakè:BAAANQAECgIIAgAAAA==.',
Gl='Glaurung:BAAANQADCgUIBQAAAA==.Glue:BAAANQAECgUICAAAAA==.',
Gn='Gnomestomper:BAAANQADCgcIDQAAAA==.',
Go='Goldenlotus:BAAANQAECgUICQAAAA==.Golder:BAAANQAECgUIBgAAAA==.Goldlight:BAAANQADCgUICQAAAA==.Goreyok:BAAANQADCgQIBAAAAA==.Gorgoneion:BAEANQAECgIIAgABNQAECgYICQABAAAAAA==.Gortess:BAEANQAECgYICQAAAA==.',
Gr='Graatch:BAAANQADCgMIBQAAAA==.Greentotems:BAAANQADCgcIDQAAAA==.Greyferret:BAAANQADCgIIAgAAAA==.Grifin:BAAANQADCgIIAgAAAA==.Grimåldus:BAAANQABCgMIAwAAAA==.Gryfalia:BAAANQADCggIDgAAAA==.',
Gu='Guinevera:BAAANQADCgMIAwAAAA==.',
['Gó']='Góat:BAAANQAECgUIBgAAAA==.',
Ha='Haavok:BAAANQAECgMIAwAAAQ==.Hadoken:BAAANQADCggIEgAAAA==.Haist:BAAANQADCgMIBAAAAA==.Halenia:BAAANQADCgUIBgAAAA==.Halftoon:BAAANQADCgEIAQAAAA==.Halyte:BAAANQADCgcIDQAAAA==.Hamoonraza:BAAANQADCgcICgAAAA==.Handwelor:BAAANQADCgUICAAAAA==.Haneel:BAAANQADCgEIAQAAAA==.Hanske:BAAANQADCgUICgAAAA==.Happyfeet:BAAANQAECgEIAQAAAA==.Harak:BAAANQAECgEIAQAAAA==.Harf:BAAANQADCgUICgAAAA==.Hatestar:BAAANQADCgYICgAAAA==.Hauthen:BAAANQADCggIDwAAAA==.Havoc:BAAANQADCggIDwAAAA==.',
He='Heliokine:BAAANQADCgYIBgAAAA==.Heys:BAAANQADCgEIAQAAAA==.',
Hi='Himi:BAAANQAECgUIBgAAAA==.Hindenburg:BAAANQADCgUIBwAAAA==.',
Ho='Hobemian:BAAANQADCgYICgAAAA==.Holyfíre:BAAANQADCgUIBQAAAA==.Holynenaea:BAAANQADCgUIBgAAAA==.Holypally:BAAANQADCgMIAwAAAA==.Holyram:BAAANQADCgcIDQAAAA==.Hoodsman:BAAANQAECgQIBAAAAA==.Hound:BAAANQAECgQIBQAAAA==.',
Hu='Hushh:BAAANQADCgIIAgAAAA==.',
['Há']='Háze:BAAANQADCgYIDAAAAA==.',
Ia='Ianna:BAAANQADCgcICgAAAA==.',
Ic='Icewall:BAAANQADCgQIBAAAAA==.',
Ih='Ihzfrsfld:BAAANQADCgQIBQAAAA==.',
Il='Ilexia:BAAANQADCgUIBQAAAA==.Illidiet:BAAANQADCgUICQAAAA==.',
In='Infierna:BAAANQAECgEIAgAAAA==.',
Ir='Ironfistxrio:BAAANQADCgcIDQAAAA==.',
Is='Isath:BAAANQADCgcIDAAAAA==.',
Iw='Iwillpeeonu:BAAANQAECgQIBAAAAA==.',
Ix='Ixix:BAAANQADCgcIDQAAAA==.',
Ja='Jackysan:BAAANQADCgQIBAABNQADCggIFAABAAAAAA==.Jalani:BAAANQADCgMIAwAAAA==.Jaq:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Java:BAAANQAECgIIAgAAAA==.',
Je='Jeffrotull:BAAANQADCgcIDAAAAA==.Jentoo:BAAANQAECgIIAgAAAA==.Jerg:BAAANQADCgcIDQAAAA==.Jerode:BAAANQADCgIIAQAAAA==.Jetpackcat:BAAANQAECgUIBgAAAA==.Jexzyn:BAAANQADCgYICQAAAA==.',
Ji='Jizza:BAAANQADCgcIBwAAAA==.',
Jo='Joepiden:BAAANQAECgQIBAABNQAECgYIBgABAAAAAA==.Jond:BAAANQAECgUIBQAAAA==.',
Jr='Jrôxs:BAAANQADCgcICgAAAA==.',
Ju='Jubilee:BAAANQAECgIIAgAAAA==.Jubnon:BAAANQAECgEIAQAAAA==.',
Ka='Kadeth:BAAANQADCgYICwAAAA==.Kamer:BAAANQADCgYIBgAAAA==.Kaptalon:BAAANQAECgQIBAAAAA==.Katarina:BAAANQAECgYICAAAAA==.Kathu:BAAANQAECgEIAQAAAA==.Kawaii:BAAANQAECgIIBAAAAA==.Kazanot:BAAANQADCgYIBgAAAA==.Kazenazza:BAAANQADCgcIDAAAAA==.',
Ke='Kelarie:BAAANQADCgIIAgAAAA==.Keltaryn:BAAANQADCgEIAQAAAA==.Kephzax:BAAANQAECgYICQAAAA==.Kerapac:BAAANQAECgUICAAAAA==.Kezinik:BAAANQAFFAEIAQAAAA==.',
Ki='Kireek:BAAANQAECgMIBAAAAA==.Kitas:BAAANQADCgYICwAAAA==.Kizuna:BAAANQADCgEIAQAAAA==.',
Kn='Knockknocks:BAAANQADCgIIAgAAAA==.',
Ko='Koujii:BAAANQAECgUICAAAAA==.',
Ks='Ksenja:BAAANQADCgcIDAAAAA==.',
Kw='Kwaichngcain:BAAANQADCgMIAwAAAA==.',
Ky='Kyfujú:BAAANQABCgMIAwAAAA==.Kylmara:BAAANQADCgIIAgAAAA==.Kylorend:BAAANQAECgYIBgAAAA==.Kyutir:BAAANQADCgYICQAAAA==.Kyuu:BAAANQADCgcIDAAAAA==.Kyygo:BAAANQADCgYIBgAAAA==.',
['Ká']='Kámm:BAAANQADCgcICAAAAA==.',
['Kè']='Kètåsét:BAAANQADCgQICQAAAA==.',
La='Ladyneasa:BAAANQADCgcIDQAAAA==.Lainn:BAAANQADCgMIAgAAAA==.Lamennais:BAAANQADCgYICwAAAA==.Lapsene:BAAANQADCgMIAwAAAA==.Lasagna:BAAANQADCgUICAABNQAECgYIBgABAAAAAA==.Lavendae:BAAANQADCgcICAAAAA==.Laxus:BAAANQAECgYICQAAAA==.',
Le='Lesath:BAAANQADCgcIDgAAAA==.Lesca:BAAANQADCgUIBQABNQAECgYICQABAAAAAA==.Leshalles:BAAANQAECgIIAgAAAA==.',
Li='Liazel:BAAANQAECgYICAAAAA==.Lilrage:BAAANQADCgUIBQAAAA==.Lilsquishy:BAAANQADCgMIBwAAAA==.Limen:BAAANQADCgcIDAAAAA==.Lissael:BAAANQADCgYIDAAAAA==.',
Lo='Loaruun:BAAANQAECgIIAgAAAA==.Loopi:BAAANQADCggIDgAAAA==.',
Lu='Lunatick:BAAANQAECgUICAAAAA==.',
Ly='Lyriele:BAAANQADCgYIBgAAAA==.',
['Lü']='Lünar:BAAANQADCgUICAAAAA==.',
Ma='Maegumi:BAAANQADCgcIDQAAAA==.Maeliá:BAAANQABCgIIAgAAAA==.Magdalin:BAAANQADCgYICwABNQADCggIDgABAAAAAA==.Magdalyne:BAAANQADCggIDgAAAA==.Magedudee:BAAANQAECgUICAAAAA==.Magespec:BAAANQADCgQIBQAAAA==.Maghom:BAAANQADCgQIBwAAAA==.Malestrom:BAAANQADCgcIDQAAAA==.Malfei:BAAANQADCgMIAwAAAA==.Manate:BAAANQAECgUIBgAAAA==.Manawavez:BAAANQADCgYIBgAAAA==.Mancakesyrup:BAAANQADCggICAAAAA==.Mandori:BAAANQADCggIDgAAAA==.Manusbane:BAAANQADCgQIAQAAAA==.Marceh:BAAANQADCgcIDAAAAA==.Marineoracle:BAEANQADCgYICgAAAA==.Marter:BAAANQADCgMIBAAAAA==.Martypriest:BAAANQAECgQIBQAAAA==.Mashal:BAAANQADCgcIDQAAAA==.Mavraan:BAAANQADCgMIAwAAAA==.Mayse:BAAANQADCgYIDAAAAA==.',
Me='Me:BAAANQAECgMIAwAAAA==.Meatsac:BAAANQAECgIIAgAAAA==.Mellennah:BAAANQADCgcIDQAAAA==.',
Mi='Micromenace:BAAANQADCgQIBAAAAA==.Mikdra:BAAANQABCgQIBAAAAA==.Milkshake:BAAANQABCgIIAgABNQADCgUICgABAAAAAA==.Missanthropy:BAAANQADCgQIBAAAAA==.Misspelling:BAAANQADCgcIBwAAAA==.',
Mo='Mohpnya:BAAANQABCgIIAgAAAA==.Mongsok:BAAANQAECgYICAAAAA==.Monkmonkmonk:BAAANQADCggIDAABNQAECgIIAgABAAAAAA==.Moonshíne:BAAANQADCgcICQAAAA==.Moy:BAAANQAECgIIAwAAAA==.',
Mu='Mumple:BAAANQADCgcIDQAAAA==.Murlok:BAAANQADCgcIDAAAAA==.',
My='Myshak:BAAANQADCgcIDAAAAA==.Mysticsoul:BAAANQAECgYICQAAAA==.',
['Mè']='Mègàmägë:BAAANQADCgQIBAAAAA==.',
Na='Nadizel:BAAANQADCgUICQAAAA==.Narzud:BAAANQADCgIIAgAAAA==.Nazmyr:BAAANQAECgIIAgAAAA==.',
Ne='Necrofeelyea:BAAANQADCgIIAgAAAA==.Neotron:BAAANQADCgYICAAAAA==.',
Ni='Nickelbritt:BAAANQADCgcIDQAAAA==.Niish:BAAANQADCgYIDAAAAA==.',
No='Noani:BAAANQAECgQIBAAAAA==.Notsu:BAAANQADCgYICQAAAA==.Novidius:BAAANQADCgcIDQAAAA==.',
Nu='Numkins:BAAANQADCgQIBAABNQADCggIDAABAAAAAA==.',
['Ní']='Níghts:BAAANQADCgcIDQAAAA==.',
Oe='Oephelia:BAAANQADCggIDQAAAA==.',
Oj='Ojaru:BAAANQADCgYICwAAAA==.',
On='Onlyhams:BAAANQAECgcICgAAAA==.',
Or='Oras:BAAANQADCgYICgAAAA==.Orayleina:BAAANQADCgYIBgAAAA==.',
Pa='Packafist:BAAANQAECgEIAQAAAA==.Palm:BAAANQADCgIIAgAAAA==.Palpalpal:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Paulywag:BAAANQADCgQIBAAAAA==.Pawsed:BAAANQADCggICwAAAA==.',
Pe='Perleana:BAAANQADCgYIDAAAAA==.Perra:BAAANQADCggIDwAAAA==.Petergriffon:BAAANQADCgUIBQAAAA==.',
Ph='Philmikehawk:BAAANQAECggICQAAAA==.',
Pi='Picklestack:BAAANQADCgcIDQAAAA==.Pikatin:BAAANQADCgUIBQAAAA==.',
Pl='Platemage:BAAANQAECgEIAQAAAA==.',
Ps='Psyk:BAAANQAECgEIAQAAAA==.',
Pu='Puding:BAAANQADCgcIDQAAAA==.',
Pw='Pwnykeg:BAAANQADCgYICwAAAA==.',
Py='Pyixi:BAAANQADCgMIBAAAAA==.',
['Pà']='Pàulywog:BAAANQADCgUIBgAAAA==.',
['Pá']='Páppajohn:BAAANQADCgYIDAAAAA==.',
Qb='Qb:BAAANQAECgQIBgAAAA==.',
Qu='Quelenna:BAAANQADCgYICwAAAA==.Questorwar:BAAANQADCgcIDAAAAA==.Quintus:BAAANQADCgMIAwAAAA==.',
Ra='Ragmer:BAAANQADCgcIBwAAAA==.Ragnariuss:BAAANQADCgcIDQAAAA==.Raira:BAAANQADCgYICwAAAA==.Ravenfeld:BAAANQADCgUICAAAAA==.',
Re='Redbeauty:BAAANQADCgEIAQAAAA==.Redvail:BAAANQADCgYIDQAAAA==.Refuting:BAAANQADCgYICAAAAA==.Reivida:BAAANQAECgEIAQAAAA==.Remyxz:BAAANQADCgMIAwAAAA==.Renshaibob:BAAANQADCgUICgAAAA==.Reported:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Reprisal:BAAANQAECgQIBAAAAA==.',
Rh='Rhapsady:BAAANQADCgQIBAAAAA==.',
Ri='Riffraff:BAAANQADCgcIDQAAAA==.Ripbozo:BAAANQAECgMIAwAAAA==.',
Ro='Rocknocker:BAAANQAECgMIBAAAAA==.Rogueelf:BAAANQADCgQIBgAAAA==.Rokkmar:BAAANQADCgIIAwAAAA==.Rookie:BAAANQAECgUICAAAAA==.Roxene:BAAANQADCgYICwAAAA==.',
Ru='Rukaza:BAAANQAECgQIBQAAAA==.',
['Rè']='Rènara:BAAANQADCgMIAwAAAA==.',
Sa='Saelyraria:BAAANQADCgYICwAAAA==.Safijiva:BAAANQAECgIIAgAAAA==.Saintrawrs:BAAANQADCgIIAQAAAA==.Saiti:BAAANQAECgUICAAAAA==.Sanleras:BAAANQADCgcIDQAAAA==.Sanovia:BAAANQADCgQIBgAAAA==.Sarao:BAAANQADCggIDgAAAA==.',
Sc='Schutzengel:BAAANQADCgcIBwAAAA==.Scoondk:BAAANQADCgYIBgAAAA==.Scuttlebug:BAAANQADCggIDwAAAA==.Scynthyace:BAAANQAECgUICAAAAA==.',
Se='Sensistar:BAAANQADCgYICAAAAA==.Sephen:BAAANQADCggIDgAAAA==.Septemberr:BAAANQADCgUIBQAAAA==.Sermac:BAAANQADCgYIBgAAAA==.',
Sh='Shadowfacs:BAAANQADCgEIAQAAAA==.Shakama:BAAANQADCgYIBwAAAA==.Shallzappy:BAAANQAECgIIAgAAAA==.Shammyfox:BAAANQADCgQIBwAAAA==.Shamuraijack:BAAANQADCgYIDAABNQAECgYIBgABAAAAAA==.Sheepngone:BAAANQADCgcIBwAAAA==.Shihow:BAAANQABCgIIAgAAAA==.Shooth:BAAANQAECgEIAQAAAA==.Shrubs:BAAANQADCgcIDAABNQAECgIIAgABAAAAAA==.',
Si='Sickminded:BAAANQAECgIIAgAAAA==.Sikes:BAAANQADCgYIDAAAAA==.Silvain:BAAANQAECgIIAgAAAA==.Sinkhole:BAAANQADCggICAAAAA==.',
Sk='Skittzo:BAAANQADCgQIBAAAAA==.',
Sl='Slashstar:BAAANQADCggICQAAAA==.Slinky:BAAANQADCgEIAQAAAA==.',
Sm='Smexyandikno:BAAANQAECgUIBQAAAA==.',
Sn='Snokums:BAAANQADCgYICgAAAA==.Snozzberry:BAAANQADCgMIAwAAAA==.Snykes:BAAANQADCgMIBAAAAA==.',
Sp='Spence:BAAANQAECgUIBgAAAA==.',
St='Stankonia:BAAANQADCgMIAwAAAA==.Stanlitwochi:BAAANQAECgMIAwAAAA==.Sticky:BAAANQADCgcIDQAAAA==.Stormkitty:BAAANQADCgcIDAAAAA==.Stout:BAAANQAECgQIBQAAAA==.Stuntyron:BAAANQADCgcIDQAAAA==.Stícky:BAAANQADCgQIBAAAAA==.',
Su='Sums:BAAANQAECgUIBgAAAA==.Sunser:BAAANQAECgQIBAAAAA==.Superdruid:BAAANQADCggIDgAAAA==.Supremus:BAAANQADCgIIAQAAAA==.',
Sv='Svetlanka:BAAANQADCgcICwAAAA==.',
Sy='Sylrêith:BAAANQADCgYIDAAAAA==.Sylyndra:BAAANQAECgEIAQAAAA==.',
['Sø']='Søulz:BAAANQADCgIIAgAAAA==.',
Ta='Tabaleina:BAAANQADCgMIAgAAAA==.Taeghana:BAAANQADCgcIDAAAAA==.Taltosh:BAAANQADCgMIAwAAAA==.Tardishunter:BAAANQADCgcIDQAAAA==.Tartarrus:BAAANQAECgEIAQAAAA==.Taulmäril:BAAANQADCgcIDAAAAA==.',
Te='Tearsofpain:BAAANQADCgMIAwAAAA==.Tearsofrain:BAAANQADCgEIAQAAAA==.Tearsofsolan:BAAANQADCgIIAgAAAA==.Tellen:BAEANQADCggIDgAAAA==.',
Th='That:BAAANQADCggIDgAAAA==.Thequae:BAAANQADCgMIAwAAAA==.This:BAAANQADCgYIBgAAAA==.Thostin:BAAANQABCgEIAQAAAA==.Thotlety:BAAANQADCgcICwAAAA==.Thrèsh:BAAANQAECgUIBwAAAA==.Thymara:BAAANQADCggIDgAAAA==.',
Ti='Tiamot:BAAANQADCgUICgAAAA==.Ticksndots:BAAANQADCgcIDAAAAA==.',
To='Toastragosa:BAAANQADCgQIBQAAAA==.Tobais:BAAANQADCgcIDQAAAA==.Tombstone:BAAANQADCgcIDQAAAA==.',
Tr='Trigzy:BAAANQADCgUIBgAAAA==.Truinnean:BAAANQAECgEIAQAAAA==.',
Tu='Tuarang:BAAANQADCgYIDAAAAA==.Turokuruvar:BAAANQADCggIDwAAAA==.',
Tw='Twinevil:BAAANQADCgUICgAAAA==.',
Ty='Tynker:BAAANQADCgYIBgAAAA==.Tyravelle:BAAANQADCgYIDAAAAA==.',
['Tú']='Túg:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.',
Un='Undousedrice:BAAANQAECgUIBgAAAA==.Unleashes:BAAANQADCgYIBgABNQADCgYICAABAAAAAA==.',
Uz='Uzu:BAAANQADCgIIAgAAAA==.',
Va='Vaelwyn:BAAANQADCgYIBgAAAA==.Validar:BAAANQADCgYICAAAAA==.Valërie:BAAANQADCggIDAAAAA==.Vanarian:BAAANQAECgUICAAAAA==.',
Ve='Velaania:BAAANQADCgYIDAAAAA==.Veleno:BAAANQADCgUIBQAAAA==.Venóm:BAAANQADCgEIAQAAAA==.Vertaí:BAAANQADCgYICwAAAA==.Veter:BAAANQADCggICwABNQAECgEIAQABAAAAAA==.',
Vi='Vibrotron:BAAANQADCgcIDQAAAA==.Victraa:BAAANQADCgYIBgAAAA==.',
Vo='Voidpera:BAAANQADCgYIBgAAAA==.',
Vu='Vulpics:BAAANQAECgMIAwAAAA==.',
['Vè']='Vèrten:BAAANQADCgYIBgAAAA==.',
Wa='Warexx:BAAANQADCgYICgAAAA==.Wasupnow:BAAANQADCgcIFgAAAA==.',
We='Weetchdoctah:BAAANQADCgcIDAAAAA==.Wenadin:BAAANQADCgYIDAAAAA==.Wetwibution:BAAANQAECgUICAAAAA==.',
Wh='Whimpy:BAAANQADCgYIBgAAAA==.Whovias:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.',
Wi='William:BAAANQADCgYIDAAAAA==.',
Wr='Wrathawk:BAAANQADCgYIBwAAAA==.',
Xh='Xhii:BAAANQAECgYICQAAAA==.',
Xi='Xingxong:BAAANQADCgUIBQAAAA==.',
Xy='Xykaz:BAAANQAECgUICAAAAA==.',
Ya='Yanakiria:BAAANQADCggIDAAAAA==.',
Ye='Yendi:BAAANQADCgYIBgAAAA==.',
Yn='Yngvar:BAAANQAECgQIBQAAAA==.',
Yo='Yokira:BAAANQABCgQIBAAAAA==.You:BAAANQADCgYIBwAAAA==.',
Yr='Yrrmad:BAAANQABCgEIAQAAAA==.',
Za='Zarknoth:BAAANQAECgUIBgAAAA==.',
Ze='Zelmancha:BAAANQAECgEIAQAAAA==.Zenkichi:BAAANQADCgMIAwAAAA==.Zephyyra:BAAANQADCgMIAwAAAA==.Zethriel:BAAANQADCgYIDAAAAA==.',
Zh='Zhealan:BAAANQADCgYICQAAAA==.',
Zi='Zibreezie:BAAANQADCgQIBgAAAA==.Zilmage:BAAANQAECgEIAgAAAA==.Zinathyr:BAAANQAECgYICQAAAA==.',
Zo='Zorrita:BAAANQADCgMIAwAAAA==.',
Zy='Zycie:BAAANQADCgcIBwAAAA==.',
Zz='Zzuul:BAAANQADCgcIDQAAAA==.',
['Zý']='Zýe:BAAANQADCggICQAAAA==.',
['Æx']='Æxil:BAAANQADCgMIAwAAAA==.',
['Él']='Éleanor:BAAANQAECgIIAgAAAA==.',
['Öh']='Öhai:BAAANQADCgcIDQAAAA==.',
['ßr']='ßröádin:BAAANQADCgMIAwAAAA==.',
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
