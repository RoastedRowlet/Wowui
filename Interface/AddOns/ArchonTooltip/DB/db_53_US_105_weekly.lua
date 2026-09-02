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

local lookup = {'Unknown-Unknown','Paladin-Protection',}
local provider = {region='US',realm='Garrosh',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aadolin:BAAANQAECgEIAQAAAA==.',
Ac='Acamar:BAAANQADCgQIBAAAAA==.',
Ad='Adeleska:BAAANQADCgcIDgAAAA==.Aderina:BAAANQADCgIIAgAAAA==.Adessa:BAAANQAECgQIBQAAAA==.',
Ae='Aellibash:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.Aenivath:BAAANQADCgQIBAAAAA==.',
Ai='Aisatsana:BAAANQADCgQIBgAAAA==.',
Al='Alopex:BAAANQAECgIIAgAAAA==.',
Am='Amaellara:BAAANQAECgEIAQAAAA==.',
An='Anthathein:BAAANQADCgUICAAAAA==.',
Ao='Aoda:BAAANQADCgcIDQAAAA==.',
Aq='Aqualina:BAAANQADCgQIBAAAAA==.',
Ar='Archblade:BAAANQADCggIDAAAAA==.Armagnac:BAAANQAECgQIBQAAAA==.',
Au='Aufare:BAAANQAECgEIAQAAAA==.',
Av='Avarya:BAAANQAECgQIBQAAAA==.Averagesham:BAAANQAECgQIAwABNQAECggIDwABAAAAAA==.Averagevoker:BAAANQAECggIDwAAAA==.Averwine:BAAANQADCgYICAAAAA==.',
Ba='Bael:BAAANQADCgIIAwAAAA==.Baraxius:BAAANQABCgEIAQAAAA==.Bayleaf:BAAANQAECgQIBQABNQAECggIDwABAAAAAA==.',
Be='Bearykyns:BAAANQAECgEIAQAAAA==.Beastwarden:BAAANQAECgIIAgAAAA==.Beatrixkiddo:BAAANQADCgYIBgAAAA==.Beautyschool:BAAANQAECgYICgAAAA==.Bejay:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Bemused:BAAANQADCgYIDAAAAA==.Benpai:BAAANQAECgEIAQAAAA==.Besticle:BAAANQAECgYICQAAAA==.',
Bi='Bigcheddarz:BAAANQADCgMIAwAAAA==.Bilberry:BAAANQABCgIIAgAAAA==.Binkie:BAAANQADCgQIBgABNQADCgYICwABAAAAAA==.',
Bj='Bjaculator:BAAANQAECgQIBQAAAA==.',
Bl='Blep:BAAANQAECgEIAQAAAA==.Blueheal:BAAANQADCgQIBgAAAA==.Blueshiver:BAAANQADCgYIBwAAAA==.',
Bo='Bonesaw:BAAANQADCgIIAgAAAA==.Bowlinder:BAAANQAECgYICgAAAA==.Boyvine:BAAANQADCgcIDQAAAA==.',
Br='Braldar:BAAANQADCgUIBQAAAA==.Braxiss:BAAANQAECgQIBAAAAA==.Brilin:BAAANQAECgEIAQAAAA==.Brithio:BAAANQADCgMIAQAAAA==.Broguë:BAAANQADCgYICwAAAA==.Brokton:BAAANQADCgQIBAAAAA==.',
Bu='Bullshzitt:BAAANQADCggICAAAAA==.Busin:BAAANQADCgQIBAAAAA==.',
['Bî']='Bîllydakîd:BAAANQADCgYIBgAAAA==.',
Ca='Calabag:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Calabloom:BAAANQAECgQIBQAAAA==.Caland:BAAANQADCgIIAgAAAA==.Calibern:BAAANQADCgMIAwAAAA==.Calmm:BAAANQAECgMIAwABNQAECgUICAABAAAAAA==.Canthndice:BAAANQADCgcIDQAAAA==.Cavalina:BAAANQAECgQIBAAAAA==.Cavick:BAAANQADCggIDgAAAA==.Cawnor:BAAANQADCgYICwAAAA==.Caótica:BAAANQADCgEIAQAAAA==.',
Ce='Ceradwyn:BAAANQADCgIIAgAAAA==.',
Ch='Charön:BAAANQAECgcIDAAAAA==.Chentrocka:BAAANQAECgQICQAAAA==.Chillberto:BAAANQADCgcIDAAAAA==.Chiselin:BAAANQADCgYICAAAAA==.',
Co='Coalgrim:BAAANQAECgIIAwAAAA==.Cosmíc:BAAANQADCgYICwAAAA==.',
Cp='Cptbyakuya:BAAANQAECgcICAAAAA==.',
Cr='Craterbip:BAAANQADCgcICwAAAA==.',
Cu='Curoconcum:BAAANQADCgYIBwAAAA==.',
Cy='Cyrub:BAAANQADCgQIBgAAAA==.',
Da='Daedrian:BAAANQADCggIDgAAAA==.Dallena:BAAANQAECgMIAwAAAA==.Dankweaver:BAAANQAECgEIAQAAAA==.Darthxander:BAAANQADCgMIBQAAAA==.Daywrecker:BAAANQADCgcIDQAAAA==.Dayyman:BAAANQAECgQIBgAAAA==.Dazuk:BAAANQADCgYIBgAAAA==.',
De='Deathlysham:BAAANQADCgIIAgAAAA==.Deathshroom:BAAANQADCgQIBAAAAA==.Deathsun:BAAANQADCgcIDQAAAA==.Deform:BAAANQAECgQIBAAAAA==.Deianaera:BAAANQADCgQIBAAAAA==.Delldestus:BAAANQADCgMIAwAAAA==.Demonstix:BAAANQAECgEIAQAAAA==.Demv:BAAANQADCgIIAgAAAA==.Despairykyns:BAAANQADCgQIAwABNQAECgEIAQABAAAAAA==.Dethbringa:BAAANQAECgMIBAAAAA==.Dewfall:BAAANQAECgYIBgAAAA==.',
Dh='Dhuoth:BAAANQAECgMIAwAAAA==.',
Di='Diagoraz:BAAANQADCgUIBwAAAA==.Dialtone:BAAANQADCgQIBwAAAA==.Digoshadow:BAAANQAECgIIAgAAAA==.Ditdoo:BAAANQADCgQIBAAAAA==.',
Dk='Dkmetcàlf:BAAANQADCggICAAAAA==.',
Do='Dorkyspork:BAAANQAECgEIAQAAAA==.',
Dr='Dragonis:BAAANQADCggICAAAAA==.Dreamerzz:BAAANQADCgYIBwAAAA==.Drovac:BAAANQADCgYIBgAAAA==.Druidxd:BAAANQADCgQIBAAAAA==.Drworm:BAAANQADCgIIAgAAAA==.Drääko:BAAANQABCgIIAgAAAA==.',
Du='Dubbies:BAAANQADCgcIDQAAAA==.Durtluz:BAAANQADCgcICAAAAA==.Dustandblood:BAAANQADCgMIAgAAAA==.',
Dy='Dyrim:BAAANQADCgQIBgAAAA==.',
['Dæ']='Dæmonkawlr:BAAANQADCgQIBAAAAA==.',
['Dê']='Dêformjr:BAAANQAECgQIBgAAAA==.',
['Dë']='Dëformjr:BAAANQADCgYIBgAAAA==.',
['Dú']='Dúbletap:BAAANQADCgYIBgAAAA==.',
El='Elbrujo:BAAANQABCgIIAwAAAA==.Elenii:BAAANQAECgEIAgAAAA==.Eleynra:BAAANQADCgIIAgAAAA==.Elybear:BAAANQADCgUIBQAAAA==.Elychan:BAAANQADCgYIBgAAAA==.Elygance:BAAANQADCggICAAAAA==.Elÿ:BAAANQAECgQIBAAAAA==.',
Em='Emptyside:BAAANQADCgYICgAAAA==.',
En='Enchorxxi:BAAANQADCggICAAAAA==.Enetrenazara:BAAANQABCgEIAQAAAA==.Eniar:BAAANQADCgUIBQABNQADCgcIBwABAAAAAA==.Enlonger:BAAANQAECgQIBAAAAA==.',
Ep='Epicgooner:BAAANQAECgEIAQAAAA==.',
Er='Erahmm:BAAANQADCgYICwAAAA==.Ergaraskreia:BAAANQADCgIIAgAAAA==.Erielia:BAAANQADCgIIAgABNQADCgYICAABAAAAAA==.',
Es='Esmirelda:BAAANQADCgYIDAAAAA==.Essn:BAAANQAFFAEIAQAAAA==.',
Eu='Eulune:BAEANQADCgYIDwABNQAECgQIBAABAAAAAA==.',
Ev='Evelynna:BAAANQADCgUIBQAAAA==.',
Ex='Exsull:BAAANQADCgcIDQAAAA==.',
Fa='Falron:BAABNQAECoEhAAICAAgJMyJlAQATAwACAAgJMyJlAQATAwAAAA==.Fathlia:BAAANQAECgEIAQAAAA==.',
Fe='Fezzjin:BAAANQADCggIDgAAAA==.',
Fi='Filbrust:BAAANQADCgIIAgAAAA==.Fishtanked:BAAANQADCgQIBgAAAA==.Fitzofrage:BAAANQADCgEIAQAAAA==.',
Fl='Flashlights:BAAANQADCgYICQAAAA==.Fleshbiter:BAAANQADCgQIBQAAAA==.Flowingdeath:BAAANQADCgMIAwABNQADCgYIBgABAAAAAA==.Flowingrage:BAAANQADCgYIBgAAAA==.',
Fo='Foot:BAAANQAECgQIBAAAAA==.Forcefaith:BAAANQAECgEIAQAAAA==.',
Fr='Freduardo:BAAANQADCgUIBgAAAA==.Freva:BAAANQAECgEIAQAAAA==.Fruitpuddle:BAAANQABCgEIAQABNQAECgYIBwABAAAAAA==.Frøsty:BAAANQADCgEIAQAAAA==.',
Fu='Furryhugger:BAAANQADCgcIFAAAAA==.Furstab:BAAANQADCgQIBQAAAA==.',
Ga='Galepalm:BAAANQADCggIDgAAAA==.Gambriniss:BAAANQADCgYICwAAAA==.Gamea:BAAANQAECgQIBAAAAA==.Gazrosh:BAAANQADCgUICQABNQADCgYICwABAAAAAA==.',
Ge='Geladra:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.Gemmothy:BAAANQADCgMIBQAAAA==.',
Gi='Gibbychona:BAAANQAECgQIBQAAAA==.',
Gl='Glowshroom:BAAANQADCgEIAQABNQADCgQIBAABAAAAAA==.',
Go='Gonnagetproc:BAAANQADCggICAAAAA==.Gordoc:BAAANQADCgYICwAAAA==.',
Gr='Graff:BAAANQADCggIDgAAAA==.Gravie:BAAANQADCgIIAgAAAA==.Greggorie:BAAANQAECgEIAQAAAA==.Grennan:BAAANQADCgUIBQAAAA==.Grifflez:BAAANQADCgcIBwAAAA==.Grumpli:BAAANQADCgYIBgAAAA==.',
Gu='Guytheshower:BAAANQADCgYICgAAAA==.',
Gw='Gweilo:BAAANQADCgcIBwAAAA==.',
Ha='Habek:BAAANQADCgQIBAAAAA==.Hamadaver:BAAANQABCgQIBgAAAA==.Handofblood:BAAANQAECgMIAwAAAA==.Harderrock:BAAANQADCgEIAQABNQAECgYICAABAAAAAA==.Hardrockgirl:BAAANQAECgMIAwABNQAECgYICAABAAAAAA==.Harmonechi:BAAANQAECgIIAwAAAA==.',
He='Healdealer:BAAANQADCgQIBAAAAA==.Healmonbello:BAAANQAECgEIAQAAAA==.Healystix:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Hellzcrusade:BAAANQADCgYICwAAAA==.Henchi:BAAANQADCgIIAgABNQADCgUIBQABAAAAAA==.',
Hi='Higherheal:BAAANQADCgMIAwAAAA==.',
Ho='Hodesh:BAAANQADCgMIAwAAAA==.Holypuuss:BAAANQAECgUICAAAAA==.Honeybumms:BAAANQAECgIIAgAAAA==.Hoplitedruid:BAAANQAECgEIAQAAAA==.Houndoom:BAAANQADCgMIBAAAAA==.',
Ht='Htiál:BAAANQADCgIIAgAAAA==.Htiâl:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.',
Hu='Huntko:BAAANQADCggIDQAAAA==.',
Hy='Hyperthymia:BAAANQAECgMIBAAAAA==.Hyrakka:BAAANQADCgYIBgABNQADCgUIBQABAAAAAA==.',
Ic='Icystyx:BAAANQADCggIDgAAAA==.',
Il='Ilyamurometz:BAAANQAECgQIBAAAAA==.',
Im='Immorta:BAAANQAECgMIAwAAAA==.',
In='Indigokiya:BAAANQADCgYIDAAAAA==.Inodoro:BAAANQADCggICAAAAA==.',
Io='Iordgodplaya:BAAANQADCgcICwAAAA==.',
Ir='Iriclaw:BAAANQAFFAIIAgAAAA==.Ironpanda:BAAANQADCgEIAQAAAA==.',
Is='Isothymia:BAAANQADCgUIBQABNQAECgMIBAABAAAAAA==.',
It='Itsmepip:BAAANQADCgcICQAAAA==.',
Ja='Jacoby:BAAANQADCgEIAQABNQAECgcIDAABAAAAAA==.Jadefires:BAAANQADCgQIBAABNQADCgcICAABAAAAAA==.Jadelite:BAAANQADCgcICAAAAA==.Janddasham:BAAANQAECgIIAwAAAA==.Janddavoker:BAAANQAECgcIDQAAAA==.Jaxo:BAAANQAECgEIAQABNQAECgUIDQABAAAAAA==.',
Jh='Jherri:BAAANQADCgUICAAAAA==.',
Ji='Jimbeamer:BAAANQADCgYIDAAAAA==.',
Jk='Jkm:BAAANQADCgYIDAAAAA==.',
Jo='Joanexotic:BAAANQADCggICwAAAA==.Jojolion:BAAANQADCgYIDAAAAA==.',
Jr='Jrocmfka:BAAANQADCgYICQAAAA==.',
Jt='Jtama:BAAANQADCgUIBwAAAA==.',
Ka='Kage:BAAANQADCgQIBgAAAA==.Kaiderten:BAAANQADCgIIAgAAAA==.Kailo:BAAANQADCgYIDAAAAA==.Kal:BAAANQADCgQIBgAAAA==.Kalorondir:BAAANQABCgQIBAAAAA==.Kamila:BAAANQADCggIDAAAAA==.Kaorí:BAAANQADCgQIBAAAAA==.Karatekyns:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Kaselian:BAAANQADCgcICQAAAA==.Kattara:BAAANQAECgEIAQAAAA==.Kazuhla:BAAANQADCgcIBwAAAA==.',
Ke='Keiryn:BAAANQADCgYIBgAAAA==.Kenté:BAAANQADCgUIBQAAAA==.',
Kh='Khaotikpyre:BAAANQAECgcIDQAAAA==.',
Ki='Kiffypoo:BAAANQADCgcIDAAAAA==.Kil:BAAANQAECgQIBQAAAA==.Kinner:BAAANQADCgYICgAAAA==.Kisho:BAAANQADCgMIAwAAAA==.Kiyoshie:BAAANQAECgQIBQAAAA==.',
Kn='Kn:BAAANQADCgcIDAAAAA==.',
Ko='Kontroll:BAEANQADCgIIAwAAAA==.Kookee:BAAANQAECgcIDQAAAA==.Korice:BAAANQAECgEIAQAAAA==.',
Kr='Krypticgrip:BAAANQAECgQIBAABNQAECgcIDQABAAAAAA==.',
Ku='Kumaa:BAAANQADCgYICwAAAA==.',
Ky='Kyle:BAAANQADCgQIBwAAAA==.Kylidon:BAAANQADCgYIBgAAAA==.',
La='Lalaind:BAAANQADCgYICAAAAA==.Larissa:BAAANQADCgYICwAAAA==.Lathillea:BAAANQADCgcIDAAAAA==.Launchpad:BAAANQADCgQIBAAAAA==.Lazzirus:BAAANQAECgQIBAAAAA==.',
Le='Leedict:BAAANQAECgEIAQAAAA==.Leerøy:BAAANQADCgcIDQAAAA==.Leilani:BAAANQADCgUIBwAAAA==.Leinalei:BAAANQADCggICAABNQADCggICgABAAAAAA==.Lessii:BAEANQAECgYICAAAAA==.',
Li='Lidarcis:BAAANQAECgEIAQAAAA==.Liedora:BAAANQADCgUIBgAAAA==.Lightpraiser:BAAANQADCgcIDQAAAA==.Linra:BAAANQAECgIIAgAAAA==.Littlefatt:BAAANQAECgEIAQAAAA==.',
Lu='Lucishifts:BAAANQAECgIIAgAAAA==.Lucîan:BAAANQADCgYICwAAAA==.Lunamorr:BAAANQADCgYIBgAAAA==.',
Ly='Lyserra:BAAANQADCgEIAQAAAA==.',
Ma='Maddawggamin:BAAANQADCgQIBAAAAA==.Mafi:BAAANQADCgMIAwAAAA==.Magenos:BAAANQADCgYIBgAAAA==.Magicpants:BAAANQADCgYIBwAAAA==.Magobiga:BAAANQADCgYICAAAAA==.Mahrx:BAAANQAFFAEIAQAAAA==.Mawaru:BAAANQADCgcIBQAAAA==.Maxanadu:BAAANQADCgQIBQAAAA==.',
Me='Meatpipe:BAAANQAECgEIAQAAAA==.Medarela:BAAANQADCgYICwAAAA==.Meeke:BAAANQAFFAEIAQAAAA==.Mell:BAAANQAECgcICwABNQAECggICAABAAAAAA==.Melmin:BAAANQADCgUICQAAAA==.Mercyful:BAAANQADCggICQAAAA==.Meroman:BAAANQADCgQIBgAAAA==.Metamora:BAAANQADCggIDwAAAA==.Meuria:BAAANQADCgYICwAAAA==.',
Mi='Midgetlord:BAAANQAECgcIBwAAAA==.Miklos:BAAANQADCgQIBQAAAA==.',
Mo='Moneebagz:BAAANQADCggIDQAAAA==.Montblanc:BAAANQADCggICAAAAA==.Moonem:BAAANQAECgMIBQAAAA==.Mossacre:BAAANQAECgEIAgAAAA==.',
Mu='Mutilatør:BAAANQADCgYIBgAAAA==.',
['Mé']='Méta:BAAANQADCgIIAgABNQADCggIDwABAAAAAA==.',
Na='Nachopapa:BAAANQADCgQIBAAAAA==.Nalorspace:BAAANQADCgUIBQAAAA==.Naniwa:BAAANQAECgEIAQAAAA==.Narwail:BAAANQAECgEIAgAAAA==.Narweil:BAAANQADCgUIBQABNQAECgEIAgABAAAAAA==.Narwhall:BAAANQADCgYICwABNQAECgEIAgABAAAAAA==.Natanus:BAAANQADCgQIBgAAAA==.Nazaric:BAAANQAECgEIAQAAAA==.Nazgeul:BAAANQADCgUIBQAAAA==.',
Ne='Necrodik:BAAANQADCgQIBAAAAA==.Neladris:BAAANQADCgIIAgAAAA==.Nelagorn:BAAANQADCgEIAQAAAA==.Nemesís:BAAANQABCgMIAwAAAA==.Neohorn:BAAANQADCgYIDAAAAA==.Neomyk:BAAANQADCgYIBgAAAA==.Neoptolemus:BAAANQADCgQIBgAAAA==.Neoqled:BAAANQADCgIIAgAAAA==.Nerclopse:BAAANQAECgQICAAAAA==.Neverender:BAAANQADCgcIDQAAAA==.Nexian:BAAANQABCgIIAgAAAA==.',
Ni='Niaryci:BAAANQADCgYIDgAAAA==.',
No='Noritotem:BAAANQADCgcIDQAAAA==.Note:BAAANQADCgQIBAAAAA==.Novacainê:BAAANQADCgUIBQAAAA==.',
Ob='Obsidiansun:BAAANQAECgIIAwAAAA==.',
Oc='Octame:BAAANQADCgcIDAAAAA==.',
Op='Opalescence:BAAANQADCgQIBwAAAA==.Optional:BAAANQAECggICgAAAA==.',
Or='Orgargo:BAAANQABCgQIBAAAAA==.',
Os='Osley:BAAANQADCgMIAwAAAA==.',
Ou='Oule:BAEANQAECgQIBAAAAA==.',
Pa='Pallorx:BAAANQADCgQIBAAAAA==.Palpatiné:BAAANQADCgQIBAAAAA==.Pandasennin:BAAANQADCgQIBgAAAA==.Papachains:BAAANQADCgYIDAABNQAECggIAQABAAAAAA==.Papashootin:BAAANQAECggIAQAAAA==.Paperplate:BAAANQAECgMIBAAAAA==.Paradox:BAAANQAECgQIBAAAAA==.Pattyhealsu:BAAANQAECgcICgAAAA==.Pawlyn:BAAANQADCgEIAQAAAA==.',
Pe='Pelivarondo:BAAANQAECgQIBwAAAA==.Pelizandeth:BAAANQADCgYIDAABNQAECgQIBwABAAAAAA==.Pepegas:BAAANQADCgcIBwAAAA==.Pestillia:BAAANQADCggIDQAAAA==.',
Ph='Phoffynax:BAAANQADCgYICwAAAA==.Phundip:BAAANQADCgMIBgABNQADCgcICgABAAAAAA==.',
Pl='Playful:BAAANQADCggICQAAAA==.Plopopotamus:BAAANQAECgYIBAAAAA==.',
Po='Pookìe:BAAANQADCgMIAwAAAA==.Poorsol:BAAANQAECgEIAQAAAA==.',
Py='Pyranis:BAAANQABCgIIAgAAAA==.',
Qu='Quickbrown:BAAANQADCgMIBAAAAA==.',
Ra='Raikz:BAAANQAECgEIAQAAAA==.Raiyne:BAAANQADCggIDwAAAA==.Rats:BAAANQAECgYIDQAAAA==.',
Re='Rendis:BAAANQADCgIIAgAAAA==.Reno:BAAANQADCgcIEQAAAA==.Reurog:BAAANQADCgQICAAAAA==.',
Rh='Rhakudu:BAAANQADCgYIBgAAAA==.',
Ri='Rian:BAAANQAECgcIDAABNQAFFAEIAQABAAAAAA==.Ritalia:BAAANQAECgMIAwAAAA==.',
Rm='Rmnieech:BAAANQADCgUIDwAAAA==.',
Ro='Roadiee:BAAANQADCgQIBAAAAA==.Roadiex:BAAANQADCgIIAwAAAA==.Roadkyll:BAAANQADCgYICwAAAA==.Rosamoon:BAAANQADCgQIBAAAAA==.Rosilyn:BAAANQADCgcIBwAAAA==.',
Ru='Rurrick:BAAANQAECgEIAQAAAA==.',
Ry='Ryzee:BAAANQAECgIIAgAAAA==.',
['Rå']='Råinè:BAAANQADCgcIBwAAAA==.',
Sa='Sahmash:BAAANQADCgIIAgAAAA==.Salara:BAAANQADCgcIDQAAAA==.Salasong:BAAANQADCgQIBAAAAA==.Saltytoast:BAAANQAECgEIAQAAAA==.Samburai:BAAANQADCgQIBQAAAA==.Samuella:BAAANQAECgEIAQAAAA==.Sandrinea:BAAANQADCggIDQAAAA==.',
Sc='Scargiver:BAAANQADCgEIAQAAAA==.Scarllett:BAAANQADCgUIBQABNQADCgcIFAABAAAAAA==.Scrubmage:BAAANQADCgMIAwAAAA==.',
Se='Sedale:BAAANQADCgcIDAAAAA==.Seesdeline:BAAANQADCgUIAgABNQADCgQIBAABAAAAAA==.Seilene:BAAANQADCgQIBQABNQADCgcICQABAAAAAA==.Senddra:BAAANQABCgIIAgAAAA==.Seo:BAAANQADCggICAAAAA==.Seraf:BAAANQAECgYIBwAAAA==.Serafain:BAAANQADCggICAABNQAECgYIBwABAAAAAA==.',
Sh='Shadowerise:BAAANQADCgIIAgAAAA==.Shaforgold:BAAANQAECgIIAgAAAA==.Shalazard:BAAANQADCgcIDAAAAA==.Shamananana:BAAANQADCgYIBgAAAA==.Sharrina:BAAANQABCgEIAQAAAA==.Shibal:BAAANQADCgcIFwAAAA==.Shotorock:BAAANQADCgYIDAAAAA==.Shushumen:BAAANQAECgEIAQAAAA==.Shänk:BAAANQABCgQIBgAAAA==.',
Si='Sickburn:BAAANQADCgUIBAAAAA==.Sicknezz:BAAANQADCgYICwAAAA==.Sidewinder:BAAANQADCgEIAQABNQAECggICgABAAAAAA==.Siinyster:BAAANQADCgMIAwAAAA==.Sikmode:BAAANQADCgcICgAAAA==.Sildrusil:BAAANQADCgEIAQAAAA==.Sindari:BAAANQAECgEIAQAAAA==.Sinturio:BAAANQADCggIDQAAAA==.Sipsy:BAAANQADCgYIDAAAAA==.',
Sk='Skarg:BAAANQAECgEIAQAAAA==.Skyeashe:BAAANQADCgMIAwAAAA==.',
Sl='Sleezytease:BAAANQADCgcIBwAAAA==.Slimdusty:BAAANQADCgQIBAAAAA==.Slobbrknckr:BAAANQADCgcIBwABNQAECgUICAABAAAAAA==.Slowmo:BAAANQADCgYIBgAAAA==.',
Sm='Smittles:BAAANQADCgcIDAAAAA==.',
Sn='Sneakybob:BAAANQADCggICAAAAA==.Sneakystix:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
So='Sootclaw:BAAANQADCgYIBgAAAA==.Sophus:BAAANQADCggICAAAAA==.Soren:BAAANQADCgQIBAAAAA==.Sorenko:BAAANQADCgIIAgABNQADCgQIBAABAAAAAA==.',
Sp='Spagooter:BAAANQAECgQIBAAAAA==.Sparklepants:BAAANQAECgQIBAAAAA==.Speyesee:BAAANQADCggIDwAAAA==.Splashydank:BAAANQADCgUIBQAAAA==.',
St='Stabbydank:BAAANQADCgYIBgAAAA==.Stackss:BAAANQAECgEIAQAAAA==.Stonedninja:BAAANQADCgIIAQAAAA==.Stonemason:BAAANQADCgcIDQAAAA==.Strawberymik:BAAANQADCgEIAQAAAA==.',
Su='Submisive:BAAANQADCgcIDgAAAA==.Supe:BAAANQADCgYIDAAAAA==.',
Sw='Swagruid:BAAANQADCggIDgAAAA==.Swampslinger:BAAANQADCggIDgAAAA==.Swordlady:BAAANQADCgYIBgABNQAECgEIAgABAAAAAA==.',
Sy='Syntari:BAAANQADCgIIAgAAAA==.Synìk:BAAANQADCgUICgAAAA==.',
['Sö']='Söma:BAAANQAECgIIAgAAAA==.',
Ta='Taktixxloxx:BAAANQABCgMIAwAAAA==.Tankerbelle:BAAANQADCgEIAQAAAA==.Taymatt:BAAANQADCgYIDAAAAA==.Tazstinko:BAAANQAECgEIAQAAAA==.',
Te='Tectonic:BAAANQAECgYIDAAAAA==.Tejasgeek:BAAANQADCgYICQAAAA==.Tenleron:BAAANQABCgIIAgAAAA==.Tenntoes:BAAANQADCgYIBgAAAA==.',
Th='Theiceflare:BAAANQADCgMIAwAAAA==.Themuffinman:BAAANQADCgYICwAAAA==.Theworrirawr:BAAANQAECgQIBwAAAA==.Thur:BAAANQAECgEIAQAAAA==.',
Ti='Tiesci:BAAANQADCggICgAAAA==.Tinyclash:BAAANQADCgQIBAAAAA==.Tinypap:BAAANQADCggICQAAAA==.Tippe:BAAANQADCgcICAAAAA==.',
Tl='Tlálocx:BAAANQADCgYICQAAAA==.',
To='Toastedblade:BAAANQADCgMIAwAAAA==.Toldyousoul:BAAANQAECgEIAQAAAA==.Tonytots:BAAANQADCgYICQAAAA==.Tottemakk:BAAANQADCgEIAQAAAA==.Toughshots:BAAANQADCgEIAQAAAA==.Toxenima:BAAANQADCgcIDAAAAA==.Toxiciti:BAAANQADCgUIBQAAAA==.',
Tr='Tramlaw:BAAANQADCgIIAgAAAA==.Trashedara:BAAANQADCgUIBQAAAA==.Treebirth:BAAANQAECgUIBQAAAA==.Treyu:BAAANQADCgYIBgAAAA==.Triegh:BAAANQABCgQIBAAAAA==.Trunder:BAAANQADCggIDgAAAA==.',
Ts='Tsaindorcus:BAAANQAECgQIBgAAAA==.Tsunamyz:BAAANQADCgIIBQAAAA==.',
Tu='Tuskgwel:BAAANQADCgIIAQAAAA==.',
Ud='Uders:BAAANQADCggIDgAAAA==.',
Uh='Uhlvar:BAAANQAECgQIBAAAAA==.Uhm:BAAANQADCgYIBgAAAA==.',
Ui='Uil:BAEANQADCgQIBAABNQAECgQIBAABAAAAAA==.',
Ul='Ultramellow:BAAANQAECgEIAQAAAA==.',
Un='Unclesquid:BAAANQADCggIDAAAAA==.Unholydubzzy:BAAANQADCgEIAQAAAA==.',
Up='Upngo:BAAANQAECgEIAgAAAA==.',
Us='Uskthyr:BAAANQABCgMIAwAAAA==.',
Va='Vanakin:BAAANQAECgQIBAABNQAFFAEIAQABAAAAAA==.Vandredor:BAAANQAFFAEIAQAAAA==.Vastatio:BAAANQADCgEIAQAAAA==.Vasträ:BAAANQADCgQIBgAAAA==.',
Ve='Velicelia:BAAANQAECgMIAwAAAA==.Vesroth:BAAANQADCgcIDAAAAA==.',
Vi='Viborge:BAAANQADCgQIBQAAAA==.View:BAAANQAECgQIBAAAAA==.Vince:BAAANQADCgYICQAAAA==.Vissra:BAAANQADCgUIBQAAAA==.',
Vu='Vulpermon:BAAANQADCgMIBAAAAA==.',
['Vä']='Vääko:BAAANQADCgYICwAAAA==.',
['Ví']='Vínce:BAAANQADCgIIAgAAAA==.',
We='Weatherr:BAAANQAECggIBgAAAA==.Weki:BAAANQADCggIDAAAAA==.',
Wh='Whippoorwill:BAAANQAECgQIBQAAAA==.Whiskyslayer:BAAANQADCggIEAAAAA==.',
Wn='Wntlmd:BAAANQAECgEIAQAAAA==.',
Wo='Wolfnacht:BAAANQAECgEIAQAAAA==.',
Wu='Wukangmei:BAAANQADCgMIAwAAAA==.',
Xe='Xene:BAAANQAECgQIBQAAAA==.',
Xh='Xhade:BAAANQADCgIIAgABNQADCgcICAABAAAAAA==.',
Xr='Xriss:BAAANQADCgQIBAAAAA==.',
Ya='Yanedin:BAAANQAECgQIBAAAAA==.',
Yo='Younger:BAAANQAECgEIAQAAAA==.Youngerxx:BAAANQADCgYIBgAAAA==.',
Yu='Yukonícus:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.Yukonïcus:BAAANQAECgUICQAAAA==.Yuridemo:BAAANQAECgYICgAAAA==.',
['Yè']='Yènnefer:BAAANQADCgUIBQAAAA==.',
Za='Zaraydorine:BAAANQADCgUIBQAAAA==.',
Zb='Zbrickashaw:BAAANQADCgYIBgAAAA==.',
Ze='Zelrin:BAAANQAECggIDQAAAA==.Zenthalion:BAAANQAECgEIAQAAAA==.',
Zi='Zippee:BAAANQADCgQIBAAAAA==.',
Zo='Zoomhunt:BAAANQAECgMIAwABNQAECgcICAABAAAAAA==.Zoommage:BAAANQAECgcICAAAAA==.',
Zu='Zuluugargorg:BAAANQAECgIIAwAAAA==.',
Zy='Zyrun:BAAANQADCgQIBAAAAA==.',
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
