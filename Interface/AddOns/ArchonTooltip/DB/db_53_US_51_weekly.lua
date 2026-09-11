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

local lookup = {'Druid-Balance','Unknown-Unknown','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='Cenarius',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aalen:BAAANQAECgcIEAAAAA==.',
Ab='Aby:BAAANQAECgEIAQAAAA==.',
Ac='Achooah:BAABNQAECoEXAAIBAAgJYCKmCQAIAwABAAgJYCKmCQAIAwAAAA==.Acturus:BAAANQADCggIFQAAAA==.',
Ad='Adekeh:BAAANQABCgIIAgAAAA==.',
Ae='Aela:BAAANQAECgYIBgAAAA==.Aenie:BAAANQADCggICgAAAA==.Aerose:BAAANQADCgYIEQAAAA==.Aethelia:BAAANQADCgMIBgAAAA==.',
Ak='Aki:BAAANQADCgcIEgAAAA==.Akie:BAAANQADCgYIBgABNQADCgcIEgACAAAAAA==.',
Al='Aladrelis:BAAANQADCggICAABNQAECgEIAQACAAAAAA==.Alarana:BAAANQADCgYIBgAAAA==.Allizana:BAAANQADCgUIBQABNQAECgcICgACAAAAAA==.Alumeena:BAAANQADCggIDQAAAA==.',
Am='Amelei:BAAANQAECgcIBwAAAA==.Amorlordros:BAAANQADCgYIBAAAAA==.Amylynn:BAAANQAECgEIAQAAAA==.Amyquivers:BAAANQADCgcIEQAAAA==.',
An='Andarieal:BAAANQAECgIIAgAAAA==.Androlas:BAAANQADCgQIBAAAAA==.Ankhling:BAAANQAECgQICAAAAA==.Annahlia:BAAANQADCgQIBAAAAA==.Annoying:BAAANQAECgEIAQAAAA==.Anyafire:BAAANQADCgUICgAAAA==.',
Ap='Appian:BAAANQADCgYIEwAAAA==.',
Ar='Aralye:BAAANQADCggICwAAAA==.Armsop:BAAANQADCgQICAAAAA==.Armîda:BAAANQAECgIIAgAAAA==.Arnika:BAAANQAECgMIAwAAAA==.Arvalyn:BAAANQAECgMIAwAAAA==.',
As='Ashlien:BAAANQADCgQIBAAAAA==.Astralvoid:BAAANQAECgMIBAAAAA==.Asuya:BAAANQADCgYIBgAAAA==.',
At='Atalune:BAAANQADCgYIBgAAAA==.Athaesia:BAAANQADCgIIAgAAAA==.',
Au='Aus:BAAANQADCgYICAABNQAECgQICQACAAAAAA==.',
Av='Avakai:BAAANQADCgQIBQAAAA==.Avawar:BAAANQABCgIIAgAAAA==.',
Ax='Axazon:BAAANQAECgQICQAAAA==.Axellered:BAAANQADCgEIAQAAAA==.',
Ba='Bartholoméw:BAAANQAECgcIDgAAAA==.Bascus:BAAANQADCggIEAAAAA==.Bassuu:BAAANQAECgQIBAAAAA==.',
Be='Beefdaddy:BAAANQAECgYICAAAAA==.Beendayho:BAAANQADCgMIAwAAAA==.Beerrun:BAAANQADCgEIAQAAAA==.Belfør:BAAANQAECgMIBAAAAA==.Bellius:BAAANQAECgMIAwAAAA==.Bennissia:BAAANQADCgYICwAAAA==.Betula:BAAANQADCgQICgAAAA==.',
Bi='Bigolbert:BAAANQADCgQIBQAAAA==.Bipolaire:BAAANQADCgMIAwAAAA==.',
Bl='Blazefury:BAAANQAECgQIBAAAAA==.Blueyez:BAAANQADCgMIAwAAAA==.',
Bo='Bobsalami:BAAANQADCgMIBgAAAA==.Boragarsh:BAAANQAECgQIBAAAAA==.Bowlyne:BAAANQAECgUICgAAAA==.Boyz:BAAANQADCggIDgAAAA==.',
Br='Brannflake:BAAANQADCgYIBwABNQAECgYICAACAAAAAA==.Brewkong:BAEANQADCgYIBgAAAA==.Bruhsabi:BAAANQADCggIDAAAAA==.Brumsta:BAAANQAECgQICAAAAA==.Brutalious:BAAANQADCgYICgAAAA==.Bruutii:BAAANQAECgcIDwAAAA==.',
Bu='Bubbleandrun:BAAANQAECgMIAwAAAA==.Buckcherry:BAAANQADCggIFQAAAA==.Bulvaan:BAAANQAECgIIAwAAAA==.',
['Bì']='Bìtterbabe:BAAANQADCgYIBgAAAA==.',
Ca='Caell:BAAANQAECgIIAgAAAA==.Calair:BAAANQADCgIIAgAAAQ==.Calandia:BAAANQADCggIFQAAAA==.Cannoneer:BAAANQAECgQIBAABNQAECgcIEgACAAAAAA==.Cannonia:BAAANQAECgcIEgAAAA==.Cantdance:BAAANQADCgIIBAAAAA==.Cantora:BAAANQAECgEIAQAAAA==.Castolo:BAAANQABCgYICQAAAA==.Catrunner:BAAANQADCgMIAwAAAA==.Cayvie:BAAANQADCggIFAAAAA==.',
Ce='Cedroes:BAAANQAECgUIDQAAAA==.Celandine:BAAANQADCggIFQAAAA==.Cerenus:BAAANQAECgQIBAAAAA==.',
Ch='Chaoswolf:BAAANQADCgcICgAAAA==.Cheapthrills:BAAANQADCgYIBgAAAA==.Chickfilafry:BAAANQAECgMIAwAAAA==.Chickfilagal:BAAANQABCgIIAgAAAA==.Chipadip:BAAANQAECgcIEAAAAA==.Chiqasaurus:BAAANQAECgEIAQAAAA==.',
Ci='Cindoria:BAAANQADCggIDgAAAA==.Cinzia:BAAANQADCggICAAAAA==.',
Cl='Clockblocked:BAAANQAECgMIBQAAAA==.Clolarion:BAAANQADCggIEQAAAA==.',
Co='Coltyn:BAAANQAECgIIAgAAAA==.Contrakt:BAAANQAECgMIBAAAAA==.',
Cr='Crackiechan:BAAANQAECgIIAgAAAA==.Crashcash:BAAANQADCgQIBgAAAA==.Croatan:BAAANQADCgIIAgAAAA==.',
Cu='Curiel:BAAANQADCggIDAAAAA==.Cutters:BAAANQADCgUIBwAAAA==.',
Cv='Cviper:BAAANQAECgcIDwAAAA==.',
Cy='Cyanos:BAAANQADCgYICwAAAA==.Cymbre:BAAANQADCggIDgAAAA==.',
Da='Dad:BAAANQAECgEIAQAAAA==.Dae:BAAANQAECgMIBAAAAA==.Dallinarr:BAAANQADCgUIBQAAAA==.Darifire:BAAANQADCgQIBAAAAA==.Darkhrt:BAAANQAECgEIAQAAAA==.Darkson:BAAANQADCgYIBgAAAA==.Dazedxar:BAAANQAECgEIAQAAAA==.',
De='Deadtotem:BAAANQAECgEIAQAAAA==.Deathdeath:BAAANQAECgIIAgAAAA==.Deathwavez:BAAANQAECgYICAAAAA==.Degaen:BAAANQADCgEIAQAAAA==.Delirium:BAAANQADCggIEgAAAA==.Dennis:BAAANQAECgcIEAAAAA==.Deosil:BAAANQADCgYIBgAAAA==.Departéd:BAEBNQAECoEdAAMDAAkJMyGPAAB2AwADAAkJMyGPAAB2AwAEAAEJHh4QLABZAAAAAA==.Deplete:BAAANQADCgIIAgABNQAECgIIAgACAAAAAA==.Derasia:BAAANQADCgMIAwAAAA==.Deyvia:BAAANQADCgEIAQAAAA==.',
Di='Dianasia:BAAANQADCgUIBQAAAA==.Dinothunder:BAAANQAECgcIBwAAAA==.Dippindots:BAAANQADCgYIDAABNQAECgYICAACAAAAAA==.Dirf:BAAANQADCggICgAAAA==.Discobear:BAAANQAFFAEIAQAAAA==.',
Do='Docent:BAAANQADCgEIAQAAAA==.Doomui:BAAANQAECgEIAQAAAA==.Dorflundgren:BAAANQADCgYIBgAAAA==.Doruh:BAAANQAECgEIAQAAAA==.Dotdragon:BAAANQADCgEIAQAAAA==.',
Dr='Draegon:BAAANQADCgUIBgABNQADCggIFQACAAAAAA==.Draenorious:BAAANQADCggIFQAAAA==.Dragonix:BAAANQAECgQIBAAAAA==.Drakonetta:BAAANQADCgUICQAAAA==.',
Du='Dudris:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.Dumbasmus:BAAANQAECgEIAQAAAA==.',
['Dä']='Däkk:BAAANQADCggICAAAAA==.',
['Dé']='Déathgoddess:BAAANQADCggIEwAAAA==.',
Ea='Eavie:BAAANQADCgcIDgAAAA==.',
Ed='Ediah:BAAANQADCgYIEQAAAA==.Edibleundies:BAAANQADCgMIBQABNQADCgQIBAACAAAAAA==.',
Ee='Eeveé:BAAANQADCgIIAgAAAA==.',
El='Electronaut:BAEANQADCggIDQAAAA==.Elee:BAAANQADCgYICAAAAA==.Elestrae:BAAANQADCgUIBQAAAA==.Eljefe:BAAANQADCgEIAQAAAA==.Elleria:BAAANQADCgUIBgAAAA==.',
Em='Emeraldstar:BAAANQADCgIIAgAAAA==.',
En='Envelion:BAAANQAECgIIBAAAAA==.',
Er='Erand:BAAANQAECgQIBAAAAA==.',
Es='Esvanka:BAAANQAECgYICAAAAA==.',
Et='Ethuul:BAAANQABCgIIAgAAAA==.',
Eu='Euterpe:BAAANQAECgIIAwAAAA==.',
Ex='Exoddus:BAAANQADCggIEgAAAA==.',
Fa='Fae:BAAANQADCgYIBgAAAA==.Faein:BAAANQADCgQIBAAAAA==.Faelynatlyf:BAAANQAECgUIBQAAAA==.Falamoto:BAAANQADCggIDwAAAA==.Fallen:BAAANQADCgYICwAAAA==.Fangskin:BAAANQAECgIIBQAAAA==.',
Fe='Feltoast:BAAANQADCgEIAQABNQADCggIDAACAAAAAA==.Feyn:BAAANQAECgQIBAAAAA==.',
Fh='Fhaeos:BAAANQADCgQIBgAAAA==.',
Fi='Fiode:BAAANQAECgMIAwAAAA==.',
Fj='Fjall:BAAANQAECgIIAgAAAA==.',
Fl='Flipsmage:BAAANQADCgYIBgAAAA==.',
Fo='Foomanpan:BAAANQADCggICAAAAA==.',
Fr='Fresh:BAAANQADCgcIDQAAAA==.Frieren:BAAANQAECgIIAgAAAA==.Frostea:BAAANQAECgIIAwAAAA==.Fruitloops:BAAANQADCgUIBQABNQAECgYICAACAAAAAA==.',
Fu='Fuzybear:BAAANQADCgYIBwABNQADCgcIDAACAAAAAA==.',
Fy='Fyo:BAAANQAECgcIEAAAAA==.Fyorin:BAAANQAECgEIAQAAAA==.',
['Fä']='Fäyëth:BAAANQADCggIDAABNQAECgQIBAACAAAAAA==.',
Ga='Gamerkun:BAAANQAECgQIBAAAAA==.Gankz:BAAANQAECgIIAwAAAA==.Gargon:BAAANQAECgQIBAAAAA==.Gatchagooner:BAAANQAECgMIBQAAAA==.Gautham:BAAANQADCgIIAgAAAA==.',
Gi='Gihum:BAAANQADCgMIBgAAAA==.Ginjjow:BAAANQADCgUIBQAAAA==.Girthquakè:BAAANQAECgMIBQAAAA==.',
Gl='Glaurung:BAAANQADCgUIBgAAAA==.Glue:BAAANQAECgcIDwAAAA==.',
Gn='Gnomestomper:BAAANQAECgMIBAAAAA==.',
Go='Goldenlotus:BAAANQAECgcIEAAAAA==.Golder:BAAANQAECgcIDQAAAA==.Goldlight:BAAANQADCgYIDwAAAA==.Goodshammy:BAAANQADCggICQAAAA==.Goreyok:BAAANQADCgQIBAAAAA==.Gorgoneion:BAEANQAECgQIBgABNQAECgcIEAACAAAAAA==.Gortess:BAEANQAECgcIEAAAAA==.',
Gr='Graatch:BAAANQADCgMIBQAAAA==.Greentotems:BAAANQADCggIHQAAAA==.Greyferret:BAAANQADCgIIAgAAAA==.Grifin:BAAANQADCgIIAgAAAA==.Grimåldus:BAAANQABCgMIAwAAAA==.Gryfalia:BAAANQAECgIIAgAAAA==.',
Gu='Guinevera:BAAANQADCgMIBgAAAA==.',
['Gó']='Góat:BAAANQAECgYIDAAAAA==.',
Ha='Haavok:BAAANQAECgUICAAAAQ==.Hadoken:BAAANQAECgIIAgAAAA==.Haist:BAAANQADCggIDAAAAA==.Halenia:BAAANQADCgcIDAAAAA==.Halftoon:BAAANQADCgEIAQAAAA==.Halyte:BAAANQAECgEIAQAAAA==.Hamoonraza:BAAANQAECgIIAgAAAA==.Handwelor:BAAANQADCgUICAAAAA==.Haneel:BAAANQADCgMIBAAAAA==.Hanske:BAAANQADCgcIEQAAAA==.Happyfeet:BAAANQAECgQIBQAAAA==.Harak:BAAANQAECgEIAQAAAA==.Harf:BAAANQADCgUIDgAAAA==.Hatestar:BAAANQAECgEIAQAAAA==.Hauthen:BAAANQAECgIIAgAAAA==.Havoc:BAAANQAECgIIAgAAAA==.',
He='Heliokine:BAAANQADCggIDgAAAA==.Heys:BAAANQADCgEIAQAAAA==.',
Hi='Himi:BAAANQAECgcIDQAAAA==.Hindenburg:BAAANQADCgYIDQAAAA==.',
Ho='Hobemian:BAAANQADCgcIDQAAAA==.Holyfíre:BAAANQADCgUIBQAAAA==.Holynenaea:BAAANQAECgYIBwAAAA==.Holypally:BAAANQAECgIIAgAAAA==.Holyram:BAAANQADCggIDgAAAA==.Hoodsman:BAAANQAECgYICgAAAA==.Hound:BAAANQAECgcIDQAAAA==.',
Hu='Hushh:BAAANQADCgYICAAAAA==.',
['Há']='Háze:BAAANQADCggIDgAAAA==.',
['Hâ']='Hâldor:BAAANQADCgYIBgAAAA==.',
Ib='Ibop:BAAANQADCggICAABNQAECgQIBAACAAAAAA==.',
Ic='Icewall:BAAANQADCgQIBAAAAA==.',
Ih='Ihzfrsfld:BAAANQADCgQIBwAAAA==.',
Il='Ilexia:BAAANQADCgYICwAAAA==.Illavoida:BAAANQABCgUIBQAAAA==.Illidansboss:BAAANQAECgMIAwAAAA==.Illidiet:BAAANQADCgcICwAAAA==.',
In='Infierna:BAAANQAECgMICAAAAA==.',
Ir='Ironfistxrio:BAAANQADCggIFQAAAA==.Ironscale:BAAANQADCgcIBwAAAA==.',
Is='Isath:BAAANQAECgEIAQAAAA==.',
Iw='Iwillpeeonu:BAAANQAECgQICQAAAA==.',
Ix='Ixix:BAAANQAECgMIBAAAAA==.',
Ja='Jackysan:BAAANQADCgQIBAABNQAECgQIBAACAAAAAA==.Jalani:BAAANQAECgEIAQAAAA==.Jaq:BAAANQADCgYIBgABNQAECgcIDQACAAAAAA==.Jatee:BAAANQADCgYIBgAAAA==.Java:BAAANQAECgIIAgAAAA==.',
Jd='Jdsc:BAAANQADCgMIAwAAAA==.',
Je='Jeffrotull:BAAANQAECgEIAQAAAA==.Jentoo:BAAANQAECgMIAwAAAA==.Jerg:BAAANQAECgIIAgAAAA==.Jerode:BAAANQADCggICQAAAA==.Jetpackcat:BAAANQAECgcIDQAAAA==.Jexzyn:BAAANQADCggIEQAAAA==.',
Ji='Jizza:BAAANQAECgEIAQAAAA==.',
Jo='Joe:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Joepiden:BAAANQAECgQIBwABNQAECgYICAACAAAAAA==.Jond:BAAANQAECgcIDAAAAA==.',
Jr='Jrôxs:BAAANQAECgEIAQAAAA==.',
Ju='Jubilee:BAAANQAECgUIBwAAAA==.Jubnon:BAAANQAECgIIAwAAAA==.',
Ka='Kadeth:BAAANQADCgcIEgAAAA==.Kahawse:BAAANQADCggICAAAAA==.Kamer:BAAANQAECgQIBAAAAA==.Kamm:BAAANQADCgQIBAAAAA==.Kanekii:BAAANQADCgMIAwAAAA==.Kaptalon:BAAANQAECgQICgAAAA==.Katarina:BAAANQAECgcIDwAAAA==.Kathu:BAAANQAECgEIAgAAAA==.Kawaii:BAAANQAECgIIBAAAAA==.Kazanot:BAAANQADCgYICQABNQAECgEIAQACAAAAAA==.Kazenazza:BAAANQADCgcIEwAAAA==.',
Ke='Kelarie:BAAANQADCgIIAgAAAA==.Keltaryn:BAAANQAECgIIAgAAAA==.Kephzax:BAAANQAECgcIDgAAAA==.Kerapac:BAAANQAECgcIDwAAAA==.Kezinik:BAAANQAFFAIIAwAAAA==.Kezursine:BAAANQAECgMIAwAAAA==.',
Ki='Kireek:BAAANQAECgQICAAAAA==.Kitas:BAAANQADCgcIDAAAAA==.Kizuna:BAAANQADCgEIAQAAAA==.',
Kl='Klegain:BAAANQADCggICAAAAA==.',
Kn='Knockknocks:BAAANQADCgIIAgAAAA==.',
Ko='Koujii:BAAANQAECgcIDwAAAA==.',
Kr='Kristyana:BAAANQAECgEIAQAAAA==.',
Ks='Ksenja:BAAANQAECgEIAQAAAA==.',
Ku='Kuum:BAAANQADCgUIBQAAAA==.',
Kw='Kwaichngcain:BAAANQADCgMIAwAAAA==.',
Ky='Kyfujú:BAAANQADCgEIAQAAAA==.Kylgard:BAAANQADCgUIBAAAAA==.Kyliara:BAAANQABCgQIBwAAAA==.Kylire:BAAANQABCgQIBAAAAA==.Kylithra:BAAANQABCgMIBQAAAA==.Kylmara:BAAANQADCgQIBgAAAA==.Kylneldth:BAAANQABCgQIBQAAAA==.Kylorend:BAAANQAECgYICAAAAA==.Kylsoonmar:BAAANQABCgQIBgAAAA==.Kysindra:BAAANQAECgcIBwAAAA==.Kyutir:BAAANQADCgYICQAAAA==.Kyuu:BAAANQAECgEIAQAAAA==.Kyygo:BAAANQAECgQIBAAAAA==.',
['Ká']='Kámm:BAAANQAECgMIAwAAAA==.',
['Kè']='Kètåsét:BAAANQADCgQICwAAAA==.',
La='Ladyneasa:BAAANQAECgMIAwAAAA==.Lainn:BAAANQADCgMIAgAAAA==.Lambofgoad:BAAANQAECgYIBgAAAA==.Lamennais:BAAANQADCggIEgAAAA==.Lapsene:BAAANQADCggICgAAAA==.Lasagna:BAAANQADCgUICAABNQAECgYICAACAAAAAA==.Lavendae:BAAANQAECgEIAQAAAA==.Laxus:BAAANQAECgcIEAAAAA==.',
Le='Leahpali:BAAANQADCgIIAgAAAA==.Lesath:BAAANQAECgUIBQAAAA==.Lesca:BAAANQADCgYIBgABNQAECgcIEAACAAAAAA==.Leshalles:BAAANQAECgUIBwAAAA==.Leviathayne:BAAANQADCgEIAgAAAA==.',
Li='Liazel:BAAANQAECgcIDwAAAA==.Lilrage:BAAANQADCgUIBQAAAA==.Lilsquishy:BAAANQADCgYIDQAAAA==.Limen:BAAANQADCggIFAAAAA==.Lissael:BAAANQADCggIDgAAAA==.',
Lo='Loaruun:BAAANQAECgYICAAAAA==.Loopi:BAAANQAECgIIAgAAAA==.',
Lu='Lunatick:BAAANQAECgcIDwAAAA==.',
Ly='Lyriele:BAAANQADCgYIBgAAAA==.',
['Lü']='Lünar:BAAANQADCgUICAAAAA==.',
Ma='Maegumi:BAAANQAECgQIBAAAAA==.Maeliá:BAAANQABCgIIAgAAAA==.Magdalin:BAAANQADCgYICwABNQAECgIIAgACAAAAAA==.Magdalyne:BAAANQAECgIIAgAAAA==.Magedudee:BAAANQAECgcIDwAAAA==.Magespec:BAAANQAECgEIAQAAAA==.Maghom:BAAANQADCgQICwAAAA==.Malestrom:BAAANQADCggIFQAAAA==.Malfei:BAAANQADCgcICgAAAA==.Manate:BAAANQAECgcIDQAAAA==.Manawavez:BAAANQADCgYIBgAAAA==.Mancakesyrup:BAAANQAECgQIBAAAAA==.Mandori:BAAANQAECgIIAgAAAA==.Manusbane:BAAANQADCggICQAAAA==.Marceh:BAAANQADCgcIEwAAAA==.Marineoracle:BAEANQAECgIIAgAAAA==.Marter:BAAANQADCgMIBAAAAA==.Martypriest:BAAANQAECgUICgAAAA==.Mashal:BAAANQAECgMIAwAAAA==.Mavraan:BAAANQADCgMIAwAAAA==.Mayse:BAAANQADCgYIFQAAAA==.',
Me='Me:BAAANQAECgMIBQAAAA==.Meatsac:BAAANQAECgYICAAAAA==.Mellennah:BAAANQAECgMIBAAAAA==.',
Mi='Micromenace:BAAANQADCgQIBAAAAA==.Mikdra:BAAANQADCgQIBAAAAA==.Milkshake:BAAANQABCgIIAgABNQADCgUICgACAAAAAA==.Missanthropy:BAAANQADCgQIBAAAAA==.Misspelling:BAAANQADCgcIBwAAAA==.',
Mo='Mohpnya:BAAANQADCgEIAQAAAA==.Mongsok:BAAANQAECgYIDgAAAA==.Monkmonkmonk:BAAANQADCggIFQABNQAECgIIAgACAAAAAA==.Moonshíne:BAAANQAECgEIAQAAAA==.Moy:BAAANQAECgUICAAAAA==.Moÿ:BAAANQAECgUIBQAAAA==.',
Mu='Mumple:BAAANQAECgIIAgAAAA==.Murlok:BAAANQAECgIIAgAAAA==.',
My='Mynöghra:BAAANQADCgYIBgABNQADCgYICgACAAAAAA==.Myshak:BAAANQAECgEIAQAAAA==.Mysticsoul:BAAANQAECgcIEAAAAA==.',
['Mè']='Mègàmägë:BAAANQADCgQIBAAAAA==.',
Na='Nadizel:BAAANQADCgcIEAAAAA==.Naglfer:BAAANQADCgEIAQAAAA==.Narzud:BAAANQADCgIIAgAAAA==.Nazmyr:BAAANQAECgMIBQAAAA==.',
Ne='Necrofeelyea:BAAANQADCgYICAAAAA==.Neotron:BAAANQADCgYIDAAAAA==.',
Ni='Nickelbritt:BAAANQAECgIIAgAAAA==.Niish:BAAANQADCggIFAAAAA==.',
No='Noani:BAAANQAECgYICgAAAA==.Notsu:BAAANQADCgcICgAAAA==.Novidius:BAAANQAECgQIBAAAAA==.',
Nu='Numkins:BAAANQAECgQIBAAAAA==.',
['Ní']='Níghts:BAAANQAECgIIAgAAAA==.',
Oe='Oephelia:BAAANQAECgMIAwAAAA==.',
Oj='Ojaru:BAAANQAECgEIAQAAAA==.',
Ol='Olliver:BAAANQADCgMIAwAAAA==.',
On='Onlyhams:BAAANQAECgcIDwAAAA==.',
Or='Oras:BAAANQADCgcIEQAAAA==.Orayleina:BAAANQADCgYIDQAAAA==.',
Ot='Othelli:BAAANQADCgUIBQAAAA==.',
Pa='Packafist:BAAANQAECgEIAQAAAA==.Palm:BAAANQADCgIIAgAAAA==.Palpalpal:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.Paulywag:BAAANQADCgYIDAAAAA==.Paulywog:BAAANQADCgUIBQAAAA==.Pawsed:BAAANQAECgMIAwAAAA==.',
Pe='Perleana:BAAANQAECgMIBAAAAA==.Perra:BAAANQAECgUIBQAAAA==.Petergriffon:BAAANQADCgcIDAAAAA==.',
Ph='Philmikehawk:BAAANQAECggIEAAAAA==.',
Pi='Picklestack:BAAANQAECgQIBAAAAA==.Pikatin:BAAANQADCgYIBgAAAA==.',
Pl='Platemage:BAAANQAECgQIBQAAAA==.',
Ps='Psyk:BAAANQAECgQIBQAAAA==.',
Pu='Puding:BAAANQAECgMIAwAAAA==.',
Pw='Pwnykeg:BAAANQADCggIEgAAAA==.',
Py='Pyixi:BAAANQADCgUICQAAAA==.',
['Pà']='Pàulywog:BAAANQAECgQIBQAAAA==.',
['Pá']='Páppajohn:BAAANQADCggIFAAAAA==.',
Qb='Qb:BAAANQAECgcIDQAAAA==.',
Qu='Quelenna:BAAANQADCggIEgAAAA==.Questorwar:BAAANQADCgcIDAAAAA==.Quintus:BAAANQADCgcICgAAAA==.',
Ra='Ragmer:BAAANQAECgQIBAAAAA==.Ragnariuss:BAAANQAECgQIBAAAAA==.Raira:BAAANQADCgcIEgAAAA==.Ravenfeld:BAAANQADCggICwAAAA==.',
Re='Redbeauty:BAAANQADCgUIBgAAAA==.Redvail:BAAANQADCgYIFQAAAA==.Refuting:BAAANQADCgYICAABNQAECgMIAwACAAAAAA==.Reivida:BAAANQAECgEIAgAAAA==.Remyxz:BAAANQADCgYICQAAAA==.Renlaut:BAAANQADCgYICwAAAA==.Reported:BAAANQADCgQIBAABNQAECgYIDgACAAAAAA==.Reprisal:BAAANQAECgYIDgAAAA==.',
Rh='Rhapsady:BAAANQADCgQIBAAAAA==.',
Ri='Riffraff:BAAANQADCggIFQAAAA==.Rioz:BAAANQADCgUIBQAAAA==.Ripbozo:BAAANQAECgQIBgAAAA==.',
Ro='Rocknocker:BAAANQAECgUICQAAAA==.Rogueelf:BAAANQADCgYIDAAAAA==.Rokkmar:BAAANQADCgIIAwAAAA==.Rookie:BAAANQAECgcIDwAAAA==.Roxene:BAAANQADCggIEwAAAA==.',
Ru='Rukaza:BAAANQAECgYICwAAAA==.',
['Rè']='Rènara:BAAANQADCgMIAwAAAA==.',
Sa='Saelyraria:BAAANQADCgcIEgAAAA==.Safijiva:BAAANQAECgMIBQAAAA==.Saintrawrs:BAAANQADCgIIAQAAAA==.Saiti:BAAANQAECgcIDwAAAA==.Sanleras:BAAANQAECgQIBAAAAA==.Sanovia:BAAANQADCgYICwAAAA==.Sarao:BAAANQAECgQIBAAAAA==.',
Sc='Schutzengel:BAAANQADCgcIBwAAAA==.Scoondk:BAAANQADCgcICwAAAA==.Scuttlebug:BAAANQAECgUIBQAAAA==.Scynthyace:BAAANQAECgcIDwAAAA==.',
Se='Selystina:BAAANQADCgYIBgAAAA==.Sensistar:BAAANQAECgMIBAAAAA==.Sephen:BAAANQADCggIFgAAAA==.Septemberr:BAAANQADCgYICwAAAA==.Sermac:BAAANQADCgYIDAAAAA==.',
Sh='Shadowfacs:BAAANQADCgMIBAAAAA==.Shadowvail:BAAANQADCgIIAgAAAA==.Shakama:BAAANQADCgYIEAAAAA==.Shallowhale:BAAANQADCgUIBQAAAA==.Shallzappy:BAAANQAECgYICAAAAA==.Shamander:BAAANQADCgIIAgAAAA==.Shammyfox:BAAANQADCgYIDQAAAA==.Shamuraijack:BAAANQADCgYIDAABNQAECgYICAACAAAAAA==.Sharlock:BAAANQABCgYIBgAAAA==.Sheepngone:BAAANQADCgcIBwAAAA==.Shihow:BAAANQABCgIIAgAAAA==.Shooth:BAAANQAECgcICAAAAA==.Shortangry:BAAANQADCggICAAAAA==.Shrubs:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
Si='Sickminded:BAAANQAECgUIBwAAAA==.Sikes:BAAANQADCgYIDAAAAA==.Sikés:BAAANQAECgEIAQAAAA==.Silvain:BAAANQAECgUIBwAAAA==.Sinkhole:BAAANQADCggICAAAAA==.',
Sk='Skittzo:BAAANQADCgYICgAAAA==.',
Sl='Slashstar:BAAANQADCggICQAAAA==.Slinky:BAAANQADCgcIBwAAAA==.',
Sm='Smexyandikno:BAAANQAECgcIDAAAAA==.',
Sn='Snokums:BAAANQADCggIEgAAAA==.Snozzberry:BAAANQADCggICgAAAA==.Snykes:BAAANQADCgUIDQAAAA==.',
So='Soulsplash:BAAANQADCgUIBQAAAA==.',
Sp='Spence:BAAANQAECgcIDQAAAA==.',
St='Stankonia:BAAANQADCgMIBQAAAA==.Stanlitwochi:BAAANQAECgUICAAAAA==.Sticky:BAAANQAECgQIBAAAAA==.Stormkitty:BAAANQAECgEIAQAAAA==.Stout:BAAANQAECgQIBQAAAA==.Stuntyron:BAAANQAECgMIAwAAAA==.Stícky:BAAANQADCgQIBAABNQADCgYICgACAAAAAA==.',
Su='Sums:BAAANQAECgcIDQAAAA==.Sunser:BAAANQAECgYICwAAAA==.Superdruid:BAAANQADCggIDgAAAA==.Supremus:BAAANQADCggICAAAAA==.',
Sv='Svetlanka:BAAANQAECgEIAQAAAA==.',
Sy='Sylrêith:BAAANQADCgYIFQAAAA==.Sylyndra:BAAANQAECgIIAwAAAA==.Syralvia:BAAANQADCggICAAAAA==.',
['Sø']='Søulz:BAAANQADCgUIBwAAAA==.',
Ta='Tabaleina:BAAANQADCgMIAgAAAA==.Taeghana:BAAANQADCggIFAAAAA==.Taltosh:BAAANQADCgcICgAAAA==.Tardishunter:BAAANQADCggIFQAAAA==.Tartarrus:BAAANQAECgYIBwAAAA==.Taterthots:BAAANQADCgYIBgAAAA==.Taulmäril:BAAANQAECgEIAQAAAA==.',
Te='Tearsofpain:BAAANQADCgMIBgAAAA==.Tearsofrain:BAAANQADCgMIBAAAAA==.Tearsofsolan:BAAANQADCgIIAgAAAA==.Teddista:BAAANQABCgIIAwAAAA==.Tellen:BAEANQAECgUIBQAAAA==.',
Th='Tharkeves:BAAANQADCgUIBQAAAA==.That:BAAANQADCggIDgAAAA==.Thequae:BAAANQADCggICgAAAA==.Therin:BAAANQADCggIBgAAAA==.This:BAAANQADCgYIBgAAAA==.Thostin:BAAANQADCgUIBQAAAA==.Thotlety:BAAANQAECgEIAQAAAA==.Thrèsh:BAAANQAECgcIDgAAAA==.Thymara:BAAANQAECgUIBQAAAA==.',
Ti='Tiamot:BAAANQADCgcIEQAAAA==.Ticksndots:BAAANQAECgIIAwAAAA==.Tirinas:BAAANQADCgIIAgAAAA==.',
To='Toastragosa:BAAANQADCggIDAAAAA==.Tobais:BAAANQAECgQIBAAAAA==.Tombstone:BAAANQAECgIIAgAAAA==.',
Tr='Trigzy:BAAANQADCgUIBgAAAA==.Triqqy:BAAANQADCggICAAAAA==.Troikka:BAAANQAECgIIAgAAAA==.Tropicana:BAAANQADCgMIAwAAAA==.Truinnean:BAAANQAECgQIBQAAAA==.',
Tu='Tuarang:BAAANQADCggIDgAAAA==.Turokuruvar:BAAANQADCggIDwAAAA==.',
Tw='Twinevil:BAAANQADCgUICgAAAA==.',
Ty='Tynker:BAAANQADCggIDgAAAA==.Tyravelle:BAAANQADCggIDgAAAA==.',
['Tú']='Túg:BAAANQADCggICgABNQAECgQICAACAAAAAA==.',
Un='Undousedrice:BAAANQAECgUIBgAAAA==.Unleashes:BAAANQAECgMIAwAAAA==.',
Uz='Uzu:BAAANQADCgMIBQAAAA==.',
Va='Vaelwyn:BAAANQADCgYIBgAAAA==.Validar:BAAANQADCgcIDwAAAA==.Valërie:BAAANQADCggIDQAAAA==.Vanarian:BAAANQAECgcIDwAAAA==.Varaza:BAAANQADCgIIAgAAAA==.',
Ve='Velaania:BAAANQAECgIIAgAAAA==.Veleno:BAAANQADCgUIBQAAAA==.Venóm:BAAANQADCgEIAQABNQADCgUIBQACAAAAAA==.Vertaí:BAAANQADCggIEwAAAA==.Veter:BAAANQAECgMIBgAAAA==.Vexxon:BAAANQAECggIBwAAAA==.',
Vi='Vibrotron:BAAANQAECgMIBAAAAA==.Vicinia:BAAANQADCgMIAwAAAA==.Victraa:BAAANQADCgYIBgAAAA==.',
Vo='Voidpera:BAAANQAECgEIAQAAAA==.',
Vu='Vulpics:BAAANQAECgUICAAAAA==.',
['Vè']='Vèrten:BAAANQADCgYIBgAAAA==.',
Wa='Warexx:BAAANQADCgcIEQAAAA==.Wasupnow:BAAANQAECgIIAgAAAA==.',
We='Weetchdoctah:BAAANQAECgQIBAAAAA==.Wenadin:BAAANQADCggIFAAAAA==.Wetwibution:BAAANQAECgcIDwAAAA==.',
Wh='Whimpy:BAAANQADCgcIDQAAAA==.Whovias:BAAANQADCgUICQABNQADCgYIEwACAAAAAA==.',
Wi='William:BAAANQADCggIFAAAAA==.',
Wr='Wrathawk:BAAANQADCgYIBwAAAA==.',
Xh='Xhii:BAAANQAECgcIEAAAAA==.',
Xi='Xingxong:BAAANQADCgUIBQAAAA==.',
Xu='Xuann:BAAANQAECgMIAwAAAA==.',
Xy='Xykaz:BAAANQAECgcIDwAAAA==.',
Ya='Yanakiria:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.',
Ye='Yendi:BAAANQAECgQIBAAAAA==.',
Yn='Yngvar:BAAANQAECgYICwAAAA==.',
Yo='Yokira:BAAANQABCgQIBgAAAA==.You:BAAANQADCgcICwAAAA==.',
Yr='Yrrmad:BAAANQABCgEIAQAAAA==.',
Za='Zarknoth:BAAANQAECgcIDQAAAA==.',
Ze='Zelmancha:BAAANQAECgUIBgAAAA==.Zenkichi:BAAANQADCgUICAAAAA==.Zephyyra:BAAANQADCgcICgAAAA==.Zethriel:BAAANQADCggIFAAAAA==.Zevorra:BAAANQADCgUIBQABNQADCgYIFQACAAAAAA==.',
Zh='Zhealan:BAAANQADCgYICQAAAA==.',
Zi='Zibreezie:BAAANQADCgQIBgAAAA==.Zilmage:BAAANQAECgQIBgAAAA==.Zinathyr:BAAANQAECgcIEAAAAA==.',
Zo='Zorrita:BAAANQADCgMIBgAAAA==.',
Zu='Zulrahk:BAAANQADCgYIBgAAAA==.',
Zy='Zycie:BAAANQAECgQIBAAAAA==.',
Zz='Zzuul:BAAANQAECgQIBAAAAA==.',
['Zý']='Zýe:BAAANQADCggIEQAAAA==.',
['Æx']='Æxil:BAAANQADCgMIBgAAAA==.',
['Él']='Éleanor:BAAANQAECgMIBgAAAA==.',
['Öh']='Öhai:BAAANQAECgEIAQAAAA==.',
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
