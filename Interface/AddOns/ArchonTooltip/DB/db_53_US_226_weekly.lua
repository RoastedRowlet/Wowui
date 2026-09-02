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

local lookup = {'Unknown-Unknown','Hunter-Marksmanship','Hunter-BeastMastery',}
local provider = {region='US',realm='Turalyon',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Absorb:BAAANQAECgMIBQAAAA==.',
Ac='Aconcerious:BAAANQAECgEIAQAAAA==.Actionbztrd:BAAANQAECgEIAQAAAA==.',
Ad='Addlee:BAAANQAECgQIBgAAAA==.Aduro:BAAANQADCggIDgAAAA==.',
Ae='Aeleleroesh:BAAANQABCgIIAgABNQABCgQIBAABAAAAAA==.Aeolyte:BAAANQADCggIDgAAAA==.Aeradeath:BAAANQAECgQIBgAAAA==.Aeronir:BAAANQAECgQIBQAAAA==.',
Ak='Akabaggins:BAAANQADCgQIBwAAAA==.',
Al='Alacrys:BAAANQADCgUIBQAAAA==.Aldyrían:BAAANQADCgQIBgAAAA==.Alltreg:BAAANQADCgcIDQAAAA==.Alrir:BAAANQADCgQIBwAAAA==.',
Am='Amelyn:BAAANQAECgEIAQAAAA==.Amrén:BAAANQAECgUIBQAAAA==.',
An='Angriff:BAAANQAECgEIAQAAAA==.Angusmcrizle:BAAANQADCgcIDAAAAA==.Ankalagon:BAAANQADCggIDwAAAA==.',
Ar='Aranjah:BAAANQADCgQIBwAAAA==.Ardius:BAAANQAECgEIAQAAAA==.Arenaria:BAAANQADCgYICgAAAA==.Arishokk:BAAANQADCggIDwAAAA==.Arks:BAAANQAECgQIBwAAAA==.Arkthugal:BAAANQAECgEIAQAAAA==.Arktwogal:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Arteezer:BAAANQADCgcIBwABNQAECgYICgABAAAAAA==.Artemiye:BAAANQADCgQIBgAAAA==.Artikblaz:BAAANQADCgQIBwAAAA==.Arun:BAAANQADCgMIAwAAAA==.Arés:BAAANQADCgUIBQAAAA==.',
As='Ashieldu:BAAANQADCgYICwAAAA==.Askanni:BAAANQADCggICgAAAA==.Astharot:BAAANQAECgIIAgAAAA==.Astralain:BAAANQADCgYIDAAAAA==.',
Au='Augdra:BAAANQADCgQIBQAAAA==.Auriauna:BAAANQADCgUICQAAAA==.',
Av='Avadagryth:BAAANQAECgQIBgAAAA==.Avanyani:BAAANQADCgUIBQAAAA==.',
Ay='Ayllo:BAAANQADCgUIBgAAAA==.',
Ba='Baelgoroth:BAAANQAECgEIAQAAAA==.Barachiel:BAAANQADCggIDgAAAA==.Basheaba:BAAANQAECgIIAgAAAA==.Bayale:BAAANQADCgcIDAAAAA==.',
Be='Belandra:BAAANQAECgEIAQAAAA==.Belishario:BAAANQAECgEIAQAAAA==.Belladawna:BAAANQAECgQIBQAAAA==.Benjals:BAAANQAECgMIAwAAAA==.Bereid:BAAANQADCgYIDAAAAA==.Berejitsu:BAAANQADCgQIBQABNQADCgYIDAABAAAAAA==.',
Bi='Bigchops:BAAANQADCgcIBwAAAA==.',
Bl='Blazerbrew:BAAANQAECgUICAAAAA==.Blezaa:BAAANQADCggIDwAAAA==.Blinknleap:BAAANQAECgUIBgAAAA==.Blooddrakken:BAAANQADCgYICgAAAA==.Bloodoxel:BAAANQADCgQIBgAAAA==.',
Bo='Boring:BAAANQAECgMIBAAAAA==.Boxlunch:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Boyana:BAAANQADCgcICwAAAA==.',
Br='Brandybuck:BAAANQADCgYIDAAAAA==.Brucelééroy:BAAANQADCgUIBQAAAA==.Bruskii:BAAANQAECgEIAQAAAA==.',
Bu='Bunns:BAAANQADCgUIBgAAAA==.Burningrash:BAAANQADCgUICQAAAA==.',
By='Byleana:BAAANQADCgYIBgABNQAECgYICAABAAAAAA==.Byléana:BAAANQAECgYICAAAAA==.Bytem:BAAANQADCggIEgAAAA==.',
Ca='Caewyn:BAAANQADCgQIBwAAAA==.Calysta:BAAANQADCgYICAAAAA==.Carleys:BAAANQABCgIIAgAAAA==.Cassara:BAAANQADCgcICwAAAA==.Cathella:BAAANQADCgMIBgAAAA==.',
Ce='Celekai:BAAANQADCgcIDAAAAA==.Celi:BAAANQADCggIDgAAAA==.Cerandan:BAAANQABCgQIBAAAAA==.Cerbadin:BAAANQAECgEIAQAAAA==.Cerbyhunt:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Cerbywar:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Ch='Cheeana:BAAANQADCgcIBwAAAA==.Cherlindrea:BAAANQADCgcIDAABNQAECgQIBQABAAAAAA==.Chickenstrip:BAAANQADCgQIBwAAAA==.Chopchop:BAAANQADCgQIBQAAAA==.Chrysus:BAAANQADCgYIBgAAAA==.',
Ci='Cidal:BAAANQADCgYICgAAAA==.Cindii:BAAANQADCgQIBAAAAA==.',
Cl='Clada:BAAANQAECgIIAgAAAA==.Clancy:BAAANQAECgEIAQAAAA==.Clifmantooth:BAAANQADCgQIBAAAAA==.',
Co='Couprenarde:BAAANQADCgMIAwABNQAECgQIBAABAAAAAA==.Courpsie:BAAANQAECgEIAQAAAA==.',
Cr='Crager:BAAANQADCgYICgAAAA==.Creamygees:BAAANQAECgQIBQAAAA==.Criaharn:BAAANQADCggICAAAAA==.Cripp:BAAANQAECgIIAgAAAA==.Crybeardin:BAAANQAECgYICAAAAA==.Cryohunter:BAAANQADCggIDgAAAA==.',
Ct='Ctair:BAAANQADCggIDgAAAA==.',
Cu='Cuckcommando:BAAANQADCgIIAgABNQAECggIDgABAAAAAA==.',
Cy='Cyberhex:BAEANQAECgMIAwAAAA==.Cybersorc:BAAANQADCgYICQAAAA==.Cyrs:BAAANQADCgEIAQAAAA==.Cysvarion:BAAANQADCgYICgAAAA==.',
['Có']='Ców:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Da='Daddi:BAAANQADCggICAAAAA==.Dairs:BAAANQADCgYICwAAAA==.Dalitha:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Damukovu:BAAANQADCgcICQAAAA==.Danayro:BAAANQAECgEIAQAAAA==.Dandron:BAAANQADCgYIBgAAAA==.Dankmeme:BAAANQAECgIIAgAAAA==.Darc:BAAANQADCgMIAwAAAA==.Darkvag:BAAANQAECgUIBwAAAA==.Davalos:BAAANQAECgEIAQAAAA==.Davos:BAAANQADCgQIBgAAAA==.Daygos:BAAANQAECggIAwAAAA==.Daêmon:BAAANQADCgYIBgAAAA==.',
De='Deadsparks:BAAANQAECgYICQAAAA==.Deftech:BAAANQAECgYIBgAAAA==.Demonic:BAAANQADCgYICgAAAA==.Demonrocket:BAAANQADCggIDgAAAA==.Derisive:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Devilslayery:BAAANQADCgcIBwAAAA==.',
Di='Diamondbob:BAAANQADCgEIAQAAAA==.',
Do='Dommothop:BAAANQAFFAMIAwAAAA==.Dorp:BAAANQAECgEIAQAAAA==.',
Dr='Dragosangue:BAAANQADCgUICQABNQADCgYICgABAAAAAA==.Drakebeard:BAAANQAECgQIBQAAAA==.Drayus:BAAANQAECgIIAgAAAA==.Driitz:BAAANQAECgEIAQAAAA==.',
Du='Duvoh:BAAANQAECgIIAgAAAA==.',
Dw='Dweezilla:BAAANQADCgEIAQAAAA==.',
Ea='Easimode:BAAANQABCgIIAwAAAA==.',
Ec='Echarrial:BAAANQADCgMIBQAAAA==.',
Ed='Eddias:BAAANQADCgcIBwAAAA==.Edge:BAAANQAECgMIAwAAAA==.',
Ek='Eklypsis:BAAANQADCgcIBwAAAA==.',
El='Elang:BAAANQADCgcIBwAAAA==.Elementrix:BAAANQADCgYICAAAAA==.Elsadieorc:BAAANQADCgYIBwAAAA==.Elyos:BAAANQADCgYIDAAAAA==.Elzar:BAAANQADCgcIDQAAAA==.',
Em='Emeraldflame:BAAANQABCgQIBAAAAA==.',
En='Entarri:BAAANQADCggIDgAAAA==.',
Es='Escanör:BAAANQADCggIDQAAAA==.Eshel:BAAANQAECgQIBQAAAA==.Eshmel:BAAANQADCggIDQAAAA==.Essek:BAAANQADCggIDwAAAA==.',
Ev='Everfrost:BAAANQAECgYICgAAAA==.Evidicus:BAAANQAECgEIAQAAAA==.Evilscarnage:BAAANQAECgQIBQAAAA==.Evilstotem:BAAANQAECgUIBgAAAA==.Evu:BAAANQAECgQIBgAAAA==.',
Ex='Exkath:BAAANQAECgYICAAAAA==.',
Ez='Ezlyn:BAAANQADCgYICwAAAA==.Ezrael:BAAANQADCgcIBwAAAA==.',
Fa='Faedrela:BAAANQADCggIDQAAAA==.Falito:BAAANQADCggIDgAAAA==.Farben:BAAANQAECgEIAQAAAA==.',
Fe='Felines:BAAANQADCgEIAQAAAA==.Fellbane:BAAANQADCgYICgAAAA==.Feohh:BAAANQADCgYICgAAAA==.',
Fi='Fiddlesticks:BAAANQAECgQIBQAAAA==.Findale:BAAANQAECgMIBAAAAA==.',
Fj='Fjalar:BAAANQAECgIIAgAAAA==.',
Fl='Flajj:BAAANQAECgEIAQAAAA==.Flamezephyr:BAAANQAECgQICAAAAA==.Flufbuns:BAAANQADCgYIDwAAAA==.',
Fo='Foxnews:BAAANQAECgIIAgAAAA==.',
Fr='Frackingheal:BAAANQABCgEIAQAAAA==.Fredfazbear:BAAANQAECgYICwAAAA==.Frozat:BAAANQADCgQIBgAAAA==.',
Fu='Furybztrd:BAAANQADCgcIBwAAAA==.',
Ga='Gagno:BAAANQADCgIIAgAAAA==.Garnimal:BAAANQADCgcIDAAAAA==.',
Ge='Georgigeo:BAAANQAECgIIAgAAAA==.',
Gh='Ghostbrue:BAAANQADCgYICwAAAA==.',
Gl='Glacious:BAAANQADCgIIAgAAAA==.',
Go='Gong:BAAANQADCgYIBgAAAA==.Goo:BAAANQADCgYIBgAAAA==.Goodbeer:BAAANQAECgEIAQAAAA==.Gouraud:BAAANQADCgcIDQAAAA==.',
Gr='Graeclaw:BAAANQADCgcIDAAAAA==.Grayson:BAAANQAECgUIBgAAAA==.Greenclaw:BAAANQAECgQIBQAAAA==.Gregoryus:BAAANQADCgUICgAAAA==.Grosmortfif:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Gruber:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.',
['Gô']='Gôósè:BAAANQAECgIIAgAAAA==.',
Ha='Hadron:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.Hairsweater:BAAANQADCgcICgAAAA==.Hakirai:BAAANQADCggIDwAAAA==.Halodin:BAAANQADCgUIBwAAAA==.Harambecast:BAAANQADCggICAABNQADCggIDQABAAAAAA==.',
He='Hexan:BAAANQAECgEIAQAAAA==.',
Hi='Hirumaredx:BAAANQADCgcIDAAAAA==.',
Ho='Hobkins:BAAANQAECgUIBgAAAA==.Holcon:BAAANQADCgcIDAAAAA==.Hollypops:BAAANQADCgcIDQAAAA==.Holybeau:BAAANQAECgYICAAAAA==.Holybo:BAAANQABCgEIAQABNQAECgYIBwABAAAAAQ==.Holywars:BAAANQADCgcIDAAAAA==.Holywdundead:BAAANQADCggIDwAAAA==.',
Hu='Hula:BAAANQADCgYIDAAAAA==.',
Hy='Hypercat:BAAANQAECgIIAgAAAA==.Hyriel:BAAANQADCgUIBwAAAA==.',
['Hú']='Húnts:BAAANQAECgQIBAAAAA==.',
Ia='Iambbq:BAAANQAECgQIBAAAAA==.',
Ic='Iceblades:BAAANQADCgMIAwAAAA==.Icyclo:BAAANQADCgQIBgAAAA==.',
Ig='Igraine:BAAANQADCgYICAAAAA==.',
Il='Illidarios:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Ilostmybible:BAAANQADCgYIDAAAAA==.',
Im='Imakeupuddin:BAAANQAECgcICwAAAA==.',
In='Indydevteam:BAAANQAECgEIAQAAAA==.Inffected:BAAANQADCgMIBAAAAA==.Inflames:BAAANQADCgYIBgAAAA==.Inglëwood:BAAANQADCgYIDgAAAA==.',
Is='Isasabotage:BAAANQAECgIIAgAAAA==.Isult:BAAANQADCgYICgAAAA==.',
Iv='Iv:BAAANQADCggICAAAAA==.',
Ix='Ixthyr:BAAANQAECgUIBgABNQAECgYICgABAAAAAA==.',
Ja='Jaenaa:BAAANQAECgIIAgAAAA==.Jahrobi:BAAANQAECgQIBQAAAA==.Jaselyn:BAAANQAECgUIBgAAAA==.Jaskryt:BAAANQADCgQIBAABNQAECgQIBwABAAAAAA==.Jaslyn:BAAANQADCgMIBQAAAA==.Jaxsen:BAAANQADCgYIDAAAAA==.',
Je='Jelibean:BAAANQADCggICAAAAA==.Jensei:BAAANQAECgQIBQAAAA==.',
Jh='Jheina:BAAANQAECgMIAwAAAA==.',
Ji='Jimmyvrr:BAAANQAECgQIBQAAAA==.Jinnô:BAAANQAECgYICAAAAA==.Jizzelda:BAAANQADCgcIEAAAAA==.',
Ju='Jubzie:BAAANQADCgcIBwAAAA==.Jubzy:BAAANQADCgcIBwAAAA==.Justwin:BAAANQAECgEIAgAAAA==.',
['Jå']='Jåckx:BAAANQADCgQIBAAAAA==.',
Ka='Kaarnu:BAAANQADCggIDwAAAA==.Kageman:BAAANQADCggIDgAAAA==.Kakon:BAAANQADCgcICQAAAA==.Kapuna:BAAANQADCgYICAAAAA==.Karaglaz:BAAANQADCggIEAAAAA==.Karalea:BAAANQAECgYICAAAAA==.Kazaganthis:BAAANQADCgcIDQAAAA==.',
Ke='Kellbell:BAAANQADCgcIBwAAAA==.Kertug:BAAANQADCggICAAAAA==.Keturonium:BAAANQADCgQIBAAAAA==.Kevdk:BAAANQAECgEIAQAAAA==.',
Kh='Khary:BAAANQABCgIIAgAAAA==.Kharzaette:BAAANQAECgQIBQAAAA==.Khristo:BAAANQAECgYIBwAAAA==.',
Ki='Kiing:BAAANQAECgIIAgAAAA==.Kikwi:BAAANQAECgEIAQAAAA==.Kioshi:BAAANQAECgEIAQAAAA==.Kitmeup:BAAANQADCgEIAgAAAA==.Kiyofu:BAAANQADCggIDgAAAA==.',
Kn='Knew:BAAANQAECggIBQAAAA==.Knotagan:BAAANQADCgcICAAAAA==.',
Ko='Korkron:BAAANQAECgcIEwAAAA==.Kovian:BAAANQADCgIIAgAAAA==.Kozmikboom:BAAANQADCgcIBwAAAA==.',
Kr='Krackster:BAAANQADCgEIAQABNQADCgQIBAABAAAAAA==.Krakow:BAAANQABCgQIAQAAAA==.Krix:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Krolo:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Ku='Kutkala:BAAANQADCgEIAQAAAA==.',
Ky='Kyrja:BAAANQADCggIDgAAAA==.Kytti:BAAANQADCgQIBgAAAA==.',
La='Ladorin:BAAANQADCgYICwAAAA==.Lahallia:BAAANQAECgQIBQAAAA==.Laiellarien:BAAANQADCgQIBQABNQAECgQIBAABAAAAAA==.Lany:BAAANQADCgEIAQAAAA==.Laran:BAAANQAECgEIAQAAAA==.Laupouette:BAAANQAECgEIAQAAAA==.Laurissandra:BAAANQADCgEIAQAAAA==.Lazypanda:BAAANQABCgIIAgAAAA==.',
Le='Lexicage:BAAANQADCgcIBwAAAA==.',
Li='Lidd:BAAANQAECgEIAQAAAA==.Lightiuz:BAAANQAECgQIBgAAAA==.Lilshadoww:BAAANQAECgQIAQAAAA==.Livandletdie:BAAANQADCgcIDQAAAA==.',
Ll='Llalowdh:BAAANQAECgIIAgAAAA==.',
Lo='Lockewynn:BAAANQAECgIIAgAAAA==.Lockjawsh:BAAANQAECgYICAAAAA==.Lokuma:BAAANQAECgEIAQAAAA==.Lorre:BAAANQADCgQIBgAAAA==.Louni:BAAANQAECgMIBgAAAA==.',
Lu='Ludo:BAAANQADCgQIBwAAAA==.Lunchbreak:BAAANQAECgIIAgAAAA==.Lunchpunch:BAAANQADCgcICgABNQAECgIIAgABAAAAAA==.Luot:BAAANQADCgIIAgAAAA==.',
Ma='Magias:BAAANQADCgMIBQAAAA==.Maglea:BAAANQADCgIIAgAAAA==.Majexs:BAAANQAECgUIBwAAAA==.Malady:BAAANQADCgUIBQAAAA==.Malfûrion:BAAANQABCgMIAwAAAA==.Malignancy:BAAANQADCgYIBgABNQAECgMIBQABAAAAAA==.Manalhau:BAAANQAECgQIBwAAAA==.Mandragoran:BAAANQAECgYICAAAAA==.Manohar:BAAANQADCgMIAwAAAA==.Manuster:BAAANQADCgIIAgAAAA==.Maradön:BAAANQAECgQIBQAAAA==.Margarida:BAAANQAECgEIAQAAAA==.Margaru:BAAANQADCgQIBgAAAA==.Maruknar:BAAANQADCgQIBAAAAA==.Mavd:BAAANQAECgEIAQAAAA==.Mavex:BAAANQADCggICAABNQAECggIDgABAAAAAA==.Maximmus:BAAANQAECgQIBgAAAA==.Mayæl:BAAANQADCgYICgAAAA==.Mazerrackham:BAAANQAECgEIAQAAAA==.',
Me='Meina:BAAANQADCgcICAAAAA==.Melynia:BAAANQADCgYICQAAAA==.Mephala:BAAANQADCggIDgAAAA==.Metapig:BAAANQAECgIIBAAAAA==.Mezasu:BAAANQADCgcIBwAAAA==.',
Mi='Mikedawson:BAAANQAECgYIBwAAAA==.Mikya:BAAANQADCggIDgAAAA==.Milkot:BAAANQAECgcIAgAAAA==.Milkys:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Mistian:BAAANQAECgQIBAAAAA==.Mistpet:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Mistrbfkx:BAAANQAECgQIBQAAAA==.',
Mo='Moai:BAAANQADCgEIAQAAAA==.Moderñdruið:BAAANQADCggIIAAAAA==.Mojodjin:BAAANQADCgIIAgAAAA==.Molewithwing:BAAANQAECgMIAwAAAA==.Monkahkiin:BAAANQADCgQIBAAAAA==.Moomoomo:BAAANQAECgcICQAAAA==.Moonrstrudel:BAAANQAECgQIBgAAAA==.Moonsaka:BAAANQADCgcIDQAAAA==.Mooseboi:BAAANQAECgEIAQAAAA==.Moothy:BAAANQADCgcIDQAAAA==.Morang:BAAANQAECgEIAQAAAA==.Mossdormu:BAAANQADCgUIBwAAAA==.',
Mu='Munitions:BAAANQADCgcIBwAAAA==.Murricah:BAAANQAECgEIAQAAAA==.Musique:BAAANQADCggICgAAAA==.',
My='Myrihwana:BAAANQAECgYIBwAAAA==.',
Na='Nahp:BAAANQADCgQIBgAAAA==.Nahtinde:BAAANQAECgcICgAAAA==.Naterade:BAAANQAECgcIDAAAAA==.Nazrull:BAAANQADCggIDgAAAA==.',
Ne='Neobovine:BAAANQAECgEIAQAAAA==.Nexlaht:BAAANQAECgUIBgAAAA==.',
Ni='Nicodemuss:BAAANQADCgUIBQAAAA==.Nightflare:BAAANQADCgMIAwAAAA==.',
No='Noeyescono:BAAANQADCgMIAwAAAA==.Noraz:BAAANQAECgQIBQAAAA==.Normalsaline:BAAANQADCgQIBQAAAA==.Noxoff:BAAANQAECgYICgAAAA==.',
Nu='Nullan:BAAANQADCgQIBwAAAA==.',
['Nè']='Nèphelle:BAAANQAECgQIBQAAAA==.',
['Në']='Nëmèsÿs:BAAANQADCgYICgAAAA==.',
Oa='Oakendale:BAAANQAECgUIBQAAAA==.Oaklei:BAAANQADCgUIBQAAAA==.Oakrageous:BAAANQADCgcIDQAAAA==.',
Ob='Obiione:BAAANQADCgcICAAAAA==.Obionekenobi:BAAANQAECgIIAgAAAA==.',
Od='Odinsson:BAAANQADCgQIBAAAAA==.',
Ol='Olrun:BAAANQADCgcIDQAAAQ==.',
Or='Orinek:BAAANQAECgYIBwAAAA==.Oruda:BAAANQADCgQIBAAAAA==.Orynnh:BAAANQADCgYICAAAAA==.',
Os='Osogrande:BAAANQADCggIDgAAAA==.Osso:BAAANQADCgQIBgAAAA==.',
Ow='Oway:BAAANQADCgQIBAAAAA==.Owy:BAAANQADCgEIAQAAAA==.',
Pa='Palajinn:BAAANQAECgIIAgAAAA==.Pandaspanda:BAAANQADCgUIBQAAAA==.Passacaglia:BAAANQAECgYIBwAAAQ==.Patryck:BAAANQAECgEIAQAAAA==.',
Pc='Pcokalypse:BAAANQAECgEIAQAAAA==.',
Pe='Peilli:BAAANQADCgcIBwAAAA==.Penemuel:BAAANQAECgEIAQAAAA==.Perkys:BAAANQABCgEIAQAAAA==.Perrinaybara:BAAANQAECgQIBQABNQAECgUIBgABAAAAAA==.Petesteele:BAAANQAECgEIAQAAAA==.Petruccio:BAAANQADCggIDgAAAA==.',
Ph='Phaet:BAAANQAECgEIAQAAAA==.Phob:BAAANQAECgQIBQAAAA==.Phoreal:BAAANQADCggIEAAAAA==.Phuryberryz:BAAANQADCgIIBAAAAA==.Phuryblight:BAAANQADCgQIBAAAAA==.Phurystorm:BAAANQADCgcIBwAAAA==.',
Pi='Pikasloot:BAAANQAECgQIBQAAAA==.Pinestraw:BAAANQAECgEIAQAAAA==.Pinksy:BAAANQADCggIDwAAAA==.Pipfanie:BAAANQADCgMIBQAAAA==.Pixelphobia:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.',
Pl='Plaid:BAAANQAECgEIAQAAAA==.',
Pn='Pnakotus:BAAANQAECgEIAQABNQAECgYICAABAAAAAA==.',
Po='Pokeey:BAAANQADCgcIDQAAAA==.Powskii:BAAANQADCggIDgAAAA==.',
Pp='Ppsmash:BAAANQAECggIDgAAAA==.',
Pr='Pronouns:BAAANQADCgcICwAAAA==.Protege:BAAANQADCgcIDAAAAA==.',
Ps='Psy:BAAANQADCgcIDQAAAA==.',
Pv='Pvp:BAAANQADCgQIBQAAAA==.',
['Pã']='Pãoduro:BAAANQADCgYIBwABNQAECgQIBwABAAAAAA==.',
['Pé']='Pérkis:BAAANQADCgcIBwAAAA==.',
Qu='Quacklord:BAAANQADCgQIBgAAAA==.',
['Qî']='Qîîz:BAAANQAECgMIAwAAAA==.',
Ra='Rambojohny:BAAANQAECgYIBgABNQAECgYICgABAAAAAA==.Ramzï:BAAANQAECgIIAgAAAA==.Randompriest:BAAANQAECgQIBgAAAA==.Rathernot:BAAANQADCggIDgAAAA==.Ravenbella:BAAANQADCgYICgAAAA==.Ravoks:BAAANQAECggIDgAAAA==.Razalla:BAAANQAECgEIAQAAAA==.Razellia:BAAANQADCgMIAwAAAA==.',
Re='Redfiend:BAAANQADCgIIAgAAAA==.Reika:BAAANQAECgQIBAAAAA==.Requlier:BAAANQAECgIIAgAAAA==.Revelationzz:BAAANQAECgQIBgAAAA==.Rexkong:BAAANQAECgEIAQAAAA==.',
Ri='Riki:BAAANQADCgcICgAAAA==.Ripetomato:BAAANQAECgYICwAAAA==.',
Ro='Rockzeeheart:BAAANQADCgYIBgAAAA==.',
Rt='Rtcmouse:BAAANQAECgEIAQAAAA==.',
Ru='Rukeshno:BAAANQAECgEIAQAAAA==.',
['Ró']='Róckmybubble:BAAANQAECgEIAQAAAA==.',
Sa='Saijin:BAAANQADCggICAAAAA==.Salysra:BAAANQAECgEIAQAAAA==.Samstein:BAAANQADCggIDQAAAA==.Sanare:BAAANQAECgIIAgAAAA==.Sandara:BAAANQADCgQIBwAAAA==.Sapz:BAAANQAECgQIBAAAAA==.Sarbrak:BAAANQADCgIIBAAAAA==.Sarka:BAAANQADCgcIDQAAAA==.Sarrh:BAAANQADCgUIBQAAAA==.Saryndra:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Satet:BAAANQADCgYICQAAAA==.Savïtar:BAAANQADCggIDgAAAA==.',
Sc='Scrandle:BAAANQADCggIDgAAAA==.',
Se='Sebile:BAAANQAECgQIBQAAAA==.Semishift:BAAANQAECgEIAQAAAA==.Sephroth:BAAANQADCggIDwAAAA==.Seydin:BAAANQADCggIDgAAAA==.Señorbear:BAAANQAECgEIAQAAAA==.',
Sh='Shaboink:BAAANQADCgEIAQABNQADCggIDQABAAAAAA==.Shabutie:BAAANQAECgQIBgAAAA==.Shadhahvar:BAAANQABCgQIBgAAAA==.Shadyboot:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.Shaienne:BAAANQAECgEIAQAAAA==.Shamtan:BAAANQADCgIIBAAAAA==.Shayná:BAAANQAECgEIAQAAAA==.Shigâr:BAAANQADCgYIBAAAAA==.Shingaling:BAAANQADCgUIBwAAAA==.Shinzovoker:BAAANQAECgIIAgAAAA==.Shockcore:BAAANQADCgQIBgAAAA==.Shoshlihauni:BAAANQADCgUIBAAAAA==.',
Si='Sidioüs:BAAANQAECgQIBQAAAA==.Silvermoonto:BAAANQADCgQIBAAAAA==.Silvia:BAAANQADCgYICQABNQAECgQIBgABAAAAAA==.Sinnan:BAAANQADCggIDgAAAA==.Sintaro:BAEANQAECgIIAgAAAA==.',
Sk='Skidattles:BAAANQAECgYIBwAAAA==.Skullordx:BAAANQADCgQIBAAAAA==.',
Sm='Smeckledorfd:BAAANQAECgIIAgAAAA==.',
Sn='Snelly:BAAANQADCggIDQAAAA==.',
So='Soulzero:BAAANQADCgYICQAAAA==.',
Sp='Spanksmoo:BAAANQAECgIIAgAAAA==.Spaxx:BAAANQADCgcIBwAAAA==.Spinnaz:BAAANQAECgEIAQAAAA==.',
St='Stalizzyx:BAAANQAECgMIBAAAAA==.Stephani:BAAANQAECgIIAgAAAA==.Stephia:BAABNQAECoEWAAMCAAgJkRsjBwCZAgACAAgJkRsjBwCZAgADAAQJFBf+KQBPAQAAAA==.Stàple:BAAANQADCgcIDAAAAA==.',
Su='Suffrage:BAAANQAECgEIAQAAAA==.Sulveris:BAAANQAECgQIBQAAAA==.Sunnyshaman:BAAANQAECgQIBwAAAA==.Sunstriker:BAAANQADCgEIAQAAAA==.Suzygreenbrg:BAAANQADCgMIAwAAAA==.',
Sy='Syleane:BAAANQABCgQIBAAAAA==.',
['Sä']='Sämael:BAAANQADCgYIBgABNQADCggIDQABAAAAAA==.',
['Sì']='Sìnìster:BAAANQAECgYIBwAAAA==.',
Ta='Tanelorñ:BAAANQADCgQIBAAAAA==.Tanksomes:BAAANQAECgQIBAAAAA==.Tareilimage:BAAANQADCggICAAAAA==.Taurenman:BAAANQADCggICAAAAA==.',
Te='Teddiebolt:BAAANQAECgMIAwAAAA==.Temptus:BAAANQAECgIIAgAAAA==.Terrenarde:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
Th='Thdrae:BAAANQAECggICAAAAA==.Thejondoepro:BAAANQAECgQIBQAAAA==.Thicklog:BAAANQADCgcIDAAAAA==.Thorrina:BAAANQABCgIIAQAAAA==.Thsbursysrur:BAAANQADCggIDgAAAA==.Thulsadoom:BAAANQADCgEIAQAAAA==.Thunderswift:BAAANQAECgQIBQAAAA==.Thæria:BAAANQADCggIDwAAAA==.',
Ti='Tia:BAAANQAECgEIAQAAAA==.Tiltion:BAAANQADCgYICgAAAA==.Tinggu:BAAANQABCgMIAwAAAA==.Tinitus:BAAANQAECgEIAQAAAA==.Tish:BAAANQADCgQIBwAAAA==.Tizzona:BAAANQAECgcIDAABNQADCgcIBwABAAAAAA==.',
Tl='Tlachtgae:BAAANQADCgIIAgAAAA==.',
To='Tobygodz:BAAANQAECgQIBAAAAA==.Tomatofest:BAAANQADCgYIDAAAAA==.Tookdk:BAAANQAECgQIBQAAAA==.Tookdrin:BAAANQADCgYICgABNQAECgQIBQABAAAAAA==.Tooksamdi:BAAANQADCgcIBwAAAA==.Torvik:BAAANQADCgIIAgAAAA==.',
Tr='Treckken:BAAANQAECgEIAQAAAA==.',
Tu='Tuknar:BAAANQAECgEIAQAAAA==.Tulleren:BAAANQADCgYIBgAAAA==.',
Ty='Tynan:BAAANQADCggIDgAAAA==.Typhön:BAAANQAECgIIAgAAAA==.',
Tz='Tzezae:BAAANQADCgYICwAAAA==.',
['Tï']='Tïlo:BAAANQAECgMIAwAAAA==.',
Uc='Ucy:BAAANQADCgMIBAAAAA==.',
Um='Umbrafrost:BAAANQADCgcIDQAAAA==.',
Un='Unspeakable:BAAANQADCgUIBQAAAA==.Untot:BAAANQAECgYIBgAAAA==.',
Va='Vach:BAAANQADCgcICwAAAA==.Vaedoc:BAAANQADCgUIBQAAAA==.Valintine:BAAANQADCgYICQAAAA==.Vallence:BAAANQAECgQIBQAAAA==.Valrev:BAAANQADCgcIBwAAAA==.Vassaro:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.',
Ve='Vettè:BAAANQAECgYIBwAAAA==.Vevoxypoo:BAAANQADCggIDwAAAA==.',
Vi='Virtigo:BAAANQADCgcIBwAAAA==.Visari:BAAANQADCgcIDQAAAA==.Vitole:BAAANQADCgEIAQABNQAECgYICAABAAAAAA==.',
Vo='Voidnut:BAAANQABCgQIBAAAAA==.',
['Vê']='Vêstïge:BAAANQADCgcICgAAAA==.',
Wa='Watermyrain:BAAANQAECgQIBQAAAA==.',
We='Weebu:BAAANQADCggIEQAAAA==.Welsley:BAAANQAECgEIAQAAAA==.',
Wh='Whatdahelly:BAAANQADCgYIBgAAAA==.Whispe:BAAANQADCggIDgAAAA==.',
Wi='Wicate:BAAANQAECgEIAQAAAA==.Wilder:BAAANQAECgMIBgAAAA==.Willendra:BAAANQAECgQIBQAAAA==.Wir:BAAANQAECgQIBgAAAA==.',
Wo='Wolfery:BAAANQAECgEIAQAAAA==.Wonderfu:BAAANQADCggIDgAAAA==.',
Wt='Wtfocks:BAAANQADCgYIDAAAAA==.',
Wu='Wuiigii:BAAANQAECgUIBwAAAA==.',
Xa='Xatus:BAAANQADCggIDgAAAA==.',
Xe='Xendrik:BAAANQADCgcIDQAAAA==.Xenyl:BAAANQADCgQIBgAAAA==.',
Xi='Xiaolia:BAAANQADCgYIDAAAAA==.',
Ya='Yamihikari:BAAANQADCgcIDQAAAA==.Yarela:BAAANQADCgMIAwAAAA==.',
Ye='Yedster:BAAANQADCgcIBwAAAA==.Yenara:BAAANQAECgQIBQAAAA==.Yesrav:BAAANQADCgYIBgAAAA==.',
Yi='Yihua:BAAANQAECgQIBAAAAQ==.',
Yu='Yumba:BAAANQADCgcIDQAAAA==.',
['Yå']='Yång:BAAANQADCgYIBwAAAA==.',
Za='Zaborg:BAAANQADCggIEAAAAA==.Zalerien:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.Zandig:BAAANQADCgcIDAAAAA==.Zappyzapp:BAAANQADCgMIAwAAAA==.Zathog:BAAANQADCgcICgAAAA==.',
Ze='Zebin:BAAANQADCgUIBQAAAA==.Zeem:BAAANQADCgcICAAAAA==.',
Zh='Zharae:BAAANQADCgUIBQAAAA==.',
Zi='Ziaroe:BAAANQADCgEIAQAAAA==.Ziayn:BAAANQADCgMIAwAAAA==.',
Zo='Zoet:BAAANQAECgEIAQAAAA==.Zohân:BAAANQADCgYIBwAAAA==.',
Zu='Zulani:BAAANQAECgIIAgAAAA==.',
['Àl']='Àlik:BAAANQAECgQIBAAAAA==.',
['Áa']='Áayla:BAAANQABCgQIBAAAAA==.',
['Çh']='Çhökèm:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.',
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
