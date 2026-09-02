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
local provider = {region='US',realm='Windrunner',name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Actionjaxson:BAAANQAECgEIAQAAAA==.',
Ad='Adeathknight:BAAANQABCgIIAgAAAA==.Admore:BAAANQADCgcIDQAAAA==.',
Ae='Aeriith:BAAANQAECgQIBQAAAA==.Aethmourne:BAAANQADCgMIAwAAAA==.',
Ag='Agameden:BAAANQADCgcIDQAAAA==.Agogg:BAAANQADCgUIBQAAAA==.',
Ah='Ahsina:BAAANQABCgQIBAAAAA==.',
Ai='Aintnosecret:BAAANQADCgYIDAAAAA==.Aishi:BAAANQADCgcICwAAAA==.',
Ak='Akaya:BAAANQADCggIDgABNQAECgMIAwABAAAAAA==.Akitsuki:BAAANQADCgUIBQAAAA==.',
Al='Algy:BAAANQADCgIIAgAAAA==.Alillara:BAAANQADCgIIAgAAAA==.Alivron:BAAANQADCggICAAAAA==.Alkoren:BAAANQADCggIDgABNQAECgMIAwABAAAAAA==.Alkorin:BAAANQAECgMIAwAAAA==.Allestra:BAAANQAECgUIBwAAAA==.',
Am='Amoxil:BAAANQADCgcIDQAAAA==.',
An='Anasztaizia:BAAANQADCgcIDQAAAA==.Andorin:BAAANQAECgMIAwAAAA==.Angelclaw:BAAANQAECgIIAgAAAA==.Anorah:BAAANQADCgcIDQAAAA==.Anunitu:BAAANQADCggIDgAAAA==.',
Ao='Aoibheann:BAAANQADCgcIDQAAAA==.',
Ar='Arath:BAAANQAECgQIBAAAAA==.Arcath:BAAANQAECgIIAgAAAA==.Arcona:BAAANQADCgYICwAAAA==.Arthuel:BAAANQADCgIIAgAAAA==.',
As='Asar:BAAANQADCgEIAQAAAA==.Ashlanni:BAAANQADCgIIAwAAAA==.Asiaminor:BAAANQADCgMIBQAAAA==.Astora:BAAANQADCgcIBwAAAA==.',
At='Athuzad:BAAANQAECgIIAgAAAA==.',
Au='Auroraalysia:BAAANQADCgUIBQAAAA==.Auroran:BAAANQAECgEIAQAAAA==.Autumnmoon:BAAANQAECgEIAQAAAA==.',
Ay='Ayeroh:BAAANQADCgYICAAAAA==.',
Az='Azenet:BAAANQADCgYIBgAAAA==.',
Ba='Bakasaura:BAAANQADCgUICgAAAA==.Balorous:BAAANQADCgcIDQAAAA==.Bansheelen:BAAANQAECgUIBQAAAA==.Banthis:BAAANQAECgEIAQAAAA==.Barkcamon:BAAANQADCgUIBQABNQAECgMIBAABAAAAAA==.Barmaak:BAAANQAECgEIAQAAAA==.Barthelo:BAAANQAECgEIAQAAAA==.Baxdock:BAAANQADCgMIBAAAAA==.Baxideath:BAAANQADCgUICAAAAA==.',
Be='Bekahroo:BAAANQADCgQIBQABNQADCgYIBgABAAAAAA==.Bekahsama:BAAANQADCgYIBgAAAA==.Belcron:BAAANQADCgQIBQAAAA==.Beldaran:BAAANQADCgcIDQAAAA==.Belladawna:BAAANQAECgEIAQAAAA==.Belldândy:BAAANQADCgQIBAAAAA==.Bernal:BAAANQADCgYICwAAAA==.',
Bh='Bhature:BAAANQADCgMIAwAAAA==.',
Bi='Bigmapletree:BAAANQADCgYICwAAAA==.Bigëmu:BAAANQADCgUICQAAAA==.Billyidols:BAAANQADCgEIAQAAAA==.Bingbangpów:BAAANQADCgQIBAAAAA==.',
Bl='Blackblader:BAAANQADCgEIAQAAAA==.Blarus:BAAANQADCgIIAgAAAA==.Blueplanet:BAAANQAECgMIAwAAAA==.',
Bo='Boherwin:BAAANQAECgEIAQAAAA==.',
Br='Bratakwar:BAAANQABCgQIBAAAAA==.Bris:BAAANQAECgEIAQAAAA==.Bruby:BAAANQAECgEIAQAAAA==.Brugamen:BAAANQAECgIIAgAAAA==.Brugg:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Brád:BAAANQADCgYIDAAAAA==.',
Bu='Bunnylajoya:BAAANQADCgYICwAAAA==.Burgerz:BAAANQADCgcIDQAAAA==.Busblaster:BAAANQAECgEIAQAAAA==.',
['Bä']='Bäldur:BAAANQADCgUIBQAAAA==.',
Ca='Calestel:BAAANQADCgIIAgAAAA==.Careßear:BAAANQADCgEIAQAAAA==.Carielle:BAAANQADCgUIBQAAAA==.Carodd:BAAANQAECgcIDQAAAA==.',
Ce='Cedaver:BAAANQAECgEIAQAAAA==.Ceez:BAAANQADCgYIBwAAAA==.Celtigar:BAAANQADCgYICwAAAA==.',
Ch='Chaan:BAAANQADCggIDgAAAA==.Chaddicus:BAAANQADCgYICwAAAA==.Chanlin:BAAANQAECgUICAAAAA==.Chauda:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Chereth:BAAANQADCgYICwAAAA==.Cheshire:BAAANQAECgMIAwAAAA==.Chestystab:BAAANQADCgUICgAAAA==.Chill:BAAANQAECgEIAQAAAA==.Chlorin:BAAANQAECgEIAQAAAA==.Chocolate:BAAANQAECgcIDQAAAA==.',
Cl='Cloudcrasher:BAAANQADCgUIBQAAAA==.Cloudsayer:BAAANQADCgYIBgAAAA==.Cloudspeaker:BAAANQAECgEIAQAAAA==.',
Co='Coldfrostshk:BAAANQADCgUICgAAAA==.Coldslayer:BAAANQAECgEIAQAAAA==.Copy:BAAANQAECgEIAQAAAA==.',
Cr='Crazyrd:BAAANQADCggIDAAAAA==.Crotgustus:BAAANQADCgMIBQAAAA==.Crumblebump:BAAANQADCgYICwAAAA==.Crummbly:BAAANQADCgUICQAAAA==.',
Cy='Cyndelle:BAAANQADCgYICgAAAA==.Cyntaria:BAAANQADCgYICAAAAA==.Cyriz:BAAANQADCgcIBwAAAA==.',
Da='Daienne:BAAANQADCgcIDQAAAA==.Dandanx:BAAANQADCgUICgABNQAECgEIAQABAAAAAA==.Daplug:BAAANQADCggICAAAAA==.Darkbrand:BAAANQAECgEIAQAAAA==.Darnel:BAAANQAECgEIAQAAAA==.Darnokk:BAAANQADCgYICwAAAA==.',
De='Deathbyfel:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Deathbyshock:BAAANQAECgEIAQAAAA==.Deathrollins:BAAANQADCgYICgAAAA==.Delaror:BAAANQADCgYIBgAAAA==.Denadin:BAAANQADCgQIBAAAAA==.Denari:BAAANQABCgEIAQAAAA==.Dennyshreds:BAAANQADCggIDgAAAA==.Denrukhan:BAAANQAECgcIDQAAAA==.Deschain:BAAANQADCgQICAAAAA==.Dew:BAAANQAECgEIAQAAAA==.',
Di='Diin:BAAANQADCgYICwAAAA==.',
Dk='Dklord:BAAANQADCgYICwAAAA==.',
Do='Donkedixlol:BAAANQADCgcICwAAAA==.Doxtorele:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Doxtorprote:BAAANQAECgIIAgAAAA==.',
Dr='Dredd:BAAANQADCgUIBQAAAA==.Drunk:BAAANQAECgQIBAAAAA==.',
Ea='Earthernheal:BAAANQADCgUIBQAAAA==.',
Eh='Ehonte:BAAANQAECgIIAgAAAA==.',
Ei='Eidolonn:BAAANQADCgUICgAAAA==.',
Ek='Ekkaia:BAAANQAECgEIAQAAAA==.',
El='Elfypriestly:BAAANQADCgUIBwAAAA==.Elsell:BAAANQAECgEIAQAAAA==.',
En='Encana:BAAANQAECgMIAwAAAA==.Ender:BAAANQADCgYICgAAAA==.',
Ep='Epiales:BAAANQADCgUIBQAAAA==.',
Er='Ericgb:BAAANQAECgcIEQAAAA==.Eronara:BAAANQADCgIIAgABNQADCgcIDwABAAAAAA==.Errzza:BAAANQADCgYICwAAAA==.Erzsébet:BAAANQAECgEIAgAAAA==.',
Es='Esha:BAAANQADCgUIBQAAAA==.',
Et='Etsupriest:BAAANQAECgQIBAAAAA==.',
Ev='Evelynn:BAAANQADCgQIBgAAAA==.',
Ex='Exanimus:BAAANQADCgUICAAAAA==.Exign:BAAANQADCgIIAgAAAA==.Exqui:BAAANQAECgEIAQAAAA==.',
Ez='Ezral:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
['Eí']='Eíko:BAAANQADCgcIBwAAAA==.',
Fa='Faeruh:BAAANQADCgUIBQAAAA==.Fafnar:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Fafnie:BAAANQADCgYIDAAAAA==.',
Fe='Felath:BAAANQADCggIDgAAAA==.Feldspar:BAAANQADCgcIDQAAAA==.',
Fi='Fil:BAAANQADCggIDgAAAA==.Fishswife:BAAANQADCgYICQAAAA==.Fissal:BAAANQADCgcIBwAAAA==.Fistoflurry:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Fl='Flameviper:BAAANQADCgYICAAAAA==.',
Fo='Foofighter:BAAANQADCgIIAgAAAA==.Footoo:BAAANQADCgYICgAAAA==.',
Fr='Franksuba:BAAANQADCgIIAgAAAA==.',
Fu='Fuknord:BAAANQADCgEIAQAAAA==.',
Fy='Fyneep:BAAANQAECgEIAQAAAA==.Fynne:BAAANQAECgQIBwAAAA==.',
Ga='Galdademon:BAAANQADCgYICgAAAA==.Galiophobia:BAAANQADCgUIBQAAAA==.Galm:BAAANQADCgUIBQAAAA==.Garrethul:BAAANQAECgEIAQAAAA==.Gawleywood:BAAANQADCgYICwAAAA==.',
Ge='Gellidus:BAAANQAECgEIAQAAAA==.Genhooves:BAAANQADCgYICwABNQAECgQIBAABAAAAAA==.Gensisd:BAAANQAECgEIAQAAAA==.',
Gh='Ghosteagle:BAAANQADCgQIBAAAAA==.',
Gn='Gnomejodas:BAAANQADCgYIBgAAAA==.',
Go='Gobfather:BAAANQADCgYICwAAAA==.Goodfaith:BAAANQADCgYICwAAAA==.Goofy:BAAANQAECgcICQABNQADCggIEAABAAAAAA==.',
Gr='Grimlocke:BAAANQADCgIIAgABNQADCgYICQABAAAAAA==.Grimsolo:BAAANQADCgYICQAAAA==.Gromit:BAAANQAECgQIBAAAAA==.',
Gu='Gubber:BAAANQADCgIIAQAAAA==.',
Gw='Gwynne:BAAANQADCggIDQAAAA==.',
Ha='Halanad:BAAANQADCgcIDQAAAA==.Halfmoons:BAAANQAECgIIAgAAAA==.Halfsumo:BAAANQADCgYIDAAAAA==.Harrol:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Hassindiir:BAAANQAECgEIAQAAAA==.Hawgelf:BAAANQADCgQIBAAAAA==.Hayles:BAAANQADCgQIBgAAAA==.',
He='Hermonk:BAAANQAECgIIBAABNQAFFAEIAQABAAAAAA==.',
Hi='Hishunter:BAAANQAECgYIBgABNQAECgcIDgABAAAAAA==.',
Hu='Hunterdamon:BAAANQAECgEIAQAAAA==.',
Hy='Hycinna:BAAANQADCgUIBQAAAQ==.',
Ia='Iamafish:BAAANQADCggIDgAAAA==.',
Ig='Igotyou:BAAANQADCgcICAAAAA==.',
In='Insidae:BAAANQAECgMIAwAAAA==.',
Ir='Ironpunch:BAAANQADCggICAAAAA==.',
Is='Ismirea:BAAANQADCgUIBQAAAA==.Isoldella:BAAANQADCgUIBQAAAA==.',
Ja='Jalencarter:BAAANQAECgUIBgAAAA==.Jamirprote:BAAANQADCgIIAgAAAA==.Jantasir:BAAANQADCgUICAAAAA==.Javalyn:BAAANQADCgYIBwAAAA==.',
Ji='Jinda:BAAANQADCgMIBgAAAA==.Jirachi:BAAANQADCgEIAQABNQAFFAIIAwABAAAAAA==.Jiu:BAAANQADCgQIBAAAAA==.',
Jo='Jobergas:BAAANQADCgYIBgAAAA==.Jobi:BAAANQADCgIIAgAAAA==.Johallas:BAAANQAECgEIAQAAAA==.',
Ju='Juf:BAAANQADCgYICwAAAA==.Jumpingbear:BAAANQAECgcIDQAAAA==.',
Ka='Kagar:BAAANQADCgMIAwAAAA==.Kaho:BAAANQAECgIIBAAAAA==.Kainazzo:BAAANQADCgUICAAAAA==.Kalda:BAAANQAECgQIBgAAAA==.Kalikali:BAAANQABCgIIAgABNQAECgEIAQABAAAAAA==.Kallisto:BAAANQADCgcIDQAAAA==.Kazuhiro:BAAANQAECggICwAAAA==.',
Ke='Keagan:BAAANQADCgcICgAAAA==.Kehzai:BAAANQAECgEIAQAAAA==.Kelric:BAAANQADCgUIBQAAAA==.Kenpomaster:BAAANQADCgYICwAAAA==.Keyalastus:BAAANQADCgQIBAAAAA==.',
Kh='Khaluha:BAAANQADCgYICwAAAA==.Khaymaan:BAAANQADCgYICAAAAA==.',
Ki='Kilmeawden:BAAANQADCgYIBgAAAA==.',
Kr='Krisha:BAAANQAECgMIAwAAAA==.Krisphobos:BAAANQADCgYICwAAAA==.',
Ku='Kubael:BAAANQAECgEIAQAAAA==.Kulgutbuster:BAAANQAECgEIAQAAAA==.Kungpow:BAAANQADCggIEgAAAA==.Kuromatsu:BAAANQAECgEIAQAAAA==.',
['Kÿ']='Kÿt:BAAANQADCggIEAAAAA==.',
La='Larceny:BAAANQADCggIDgAAAA==.',
Le='Leiania:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Lewis:BAAANQADCggICAAAAA==.',
Li='Lild:BAAANQADCgMIAwAAAA==.Lishan:BAAANQAECgQIBAAAAA==.Liszandera:BAAANQADCggICgAAAA==.Literein:BAAANQADCgYIDAAAAA==.Lizora:BAAANQADCggIEwAAAA==.',
Lo='Lokisan:BAAANQADCgMIAwAAAA==.Lorenei:BAAANQADCgcIDQAAAA==.Los:BAAANQADCgUIBQAAAA==.',
Lt='Ltwhisker:BAAANQADCgcICwAAAA==.',
Lu='Lucïd:BAAANQADCggIDgAAAA==.Lunhzae:BAAANQADCgUIBQAAAA==.Lustallo:BAAANQADCgQIBAAAAA==.',
Ly='Lynxx:BAAANQADCgcIDAAAAA==.',
Ma='Macharth:BAAANQAECgEIAQAAAA==.Mack:BAAANQADCggIDQAAAA==.Mad:BAAANQAECgEIAQAAAA==.Madchickenz:BAAANQAECgEIAQAAAA==.Magicwithin:BAAANQAECgEIAQAAAQ==.Maira:BAAANQADCgYICgAAAA==.Majim:BAAANQADCgYICgAAAA==.Malevolens:BAAANQADCgUIBwAAAA==.Marche:BAAANQAECgEIAQAAAA==.Mavdk:BAAANQADCggIDgAAAA==.',
Mc='Mcflurrey:BAAANQAECgEIAQAAAA==.',
Me='Mechamana:BAAANQADCgYIBgABNQADCgYIBwABAAAAAA==.Melodrama:BAAANQADCgIIAgAAAA==.Mephïsto:BAAANQADCgYICwAAAA==.Mereoleona:BAAANQAECgQIBAAAAA==.Messdupllama:BAAANQAECgYIBgAAAA==.Metamorfasis:BAAANQADCgcICgAAAA==.',
Mi='Micos:BAAANQADCgYIBgAAAA==.Microburst:BAAANQAECgEIAQAAAA==.Microcharge:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Miischief:BAAANQADCgUIBwAAAA==.Milkman:BAAANQADCggIFAAAAA==.Misslynn:BAAANQADCgMIAwAAAA==.Missmoodý:BAAANQADCgYICQAAAA==.Missqwerty:BAAANQADCggIBQAAAA==.',
Mo='Moltenbeast:BAAANQADCgYIDQAAAA==.Mongargiss:BAAANQADCgYICQAAAA==.Montaro:BAAANQADCgYICwAAAA==.Morbidi:BAAANQADCgUIBwAAAA==.Mortharos:BAAANQAECgMIBQAAAA==.',
Mu='Mudkip:BAAANQAFFAIIAwAAAA==.Munnsta:BAAANQAECgEIAQAAAA==.',
My='Mylanara:BAAANQAECgEIAQAAAA==.Mysticah:BAAANQADCgYICAAAAA==.Mythalagos:BAAANQADCgEIAQAAAA==.Mythblast:BAAANQADCgEIAgAAAA==.',
['Mä']='Märs:BAAANQAECgcIDgAAAA==.',
Na='Naelu:BAAANQADCgMIAwAAAA==.Nanr:BAAANQAECgEIAQAAAA==.Nathi:BAAANQADCgcIDQAAAA==.Navori:BAEANQAECgcIDQAAAA==.Nazeraz:BAAANQADCgcIDAAAAA==.',
Ne='Nerve:BAAANQAECgEIAQAAAA==.Neth:BAAANQAECgIIAgAAAA==.Neuroshots:BAAANQADCgcIBwAAAA==.Newkers:BAAANQADCgUICQAAAA==.',
Ni='Nightknight:BAAANQADCgMIAwAAAA==.Nightràven:BAAANQAECgIIAgAAAA==.Nimrodd:BAAANQADCggIDAAAAA==.',
No='Nobby:BAAANQADCgUIBQAAAA==.Noogan:BAAANQADCgYIBgAAAA==.Nosferatü:BAAANQADCgUIBQAAAA==.Nothotdog:BAAANQADCgIIAgAAAA==.Novacat:BAAANQAECgUICQAAAA==.Novangel:BAAANQADCgYIBgAAAA==.November:BAAANQADCgcIDQAAAA==.Nox:BAAANQADCggIBgAAAA==.',
Nu='Nubriss:BAAANQADCgcIDAAAAA==.Nuitsguard:BAAANQAECgUIBgAAAA==.',
Ny='Nyaboron:BAAANQAECgIIAgAAAA==.',
['Nè']='Nèaner:BAAANQAECgEIAQAAAA==.',
Og='Oggden:BAAANQADCgcIDAAAAA==.Ogrebane:BAAANQAECgEIAQAAAA==.',
Oi='Oiheg:BAAANQAECgEIAQAAAA==.',
Pa='Pajamasniper:BAAANQAECgEIAQAAAA==.',
Pe='Peach:BAAANQAECgEIAQAAAA==.',
Ph='Photos:BAAANQAECgEIAQAAAA==.',
Pl='Pluug:BAAANQAECgEIAQAAAA==.',
Pr='Prayer:BAAANQAECgEIAQAAAA==.Prîde:BAAANQADCgEIAQAAAA==.',
Ps='Psycopath:BAAANQAECgEIAgAAAA==.Psygn:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Pt='Ptra:BAAANQABCgMIAwABNQAECgQIBQABAAAAAA==.',
Pu='Pumpy:BAAANQAECgcIDQAAAA==.',
Py='Pywacket:BAAANQAECgEIAQAAAA==.',
['Pã']='Pãlàdoom:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Qu='Quendwings:BAEANQAECgUIBQABNQAECggICwABAAAAAA==.',
Ra='Rayleighh:BAAANQAECgMIBQAAAA==.',
Ri='Rikaza:BAAANQADCgYIBgAAAA==.Ristraza:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.',
Ro='Roguewølf:BAAANQADCgQIBgAAAA==.Roono:BAAANQADCgUIAQAAAA==.Rossco:BAAANQADCgYIBwAAAA==.Rozzluz:BAAANQADCggICAAAAA==.',
Ru='Rutira:BAAANQAECgEIAQAAAA==.',
Ry='Ryân:BAAANQADCgMIAwAAAA==.',
Sa='Sabbat:BAAANQADCgUIBQAAAA==.Sapphiwrath:BAAANQADCgYIDAAAAA==.',
Se='Seacow:BAAANQADCgYIBgAAAA==.Searilus:BAAANQADCgYICwAAAA==.Seethed:BAAANQADCgUIBQAAAA==.Seylena:BAAANQADCgUICgABNQAECgEIAQABAAAAAA==.',
Sh='Shammallamma:BAAANQABCgQIBgAAAA==.Shamæn:BAAANQADCgYIBgAAAA==.Shaphyr:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Sharphammer:BAAANQADCgIIAwAAAA==.Shieldon:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Shootsahlot:BAAANQADCgQIBgAAAA==.',
Si='Sidapa:BAAANQADCgYICgAAAA==.Silvernleaf:BAAANQADCgYICgAAAA==.Sindir:BAAANQADCgQIBAABNQAECgcIDQABAAAAAA==.',
Sk='Skept:BAAANQADCggIEAAAAA==.',
Sl='Sleêp:BAAANQADCgcIDQAAAA==.Slosh:BAAANQAECgQIBQAAAA==.',
Sm='Smellyandfat:BAEANQAECggICwAAAA==.Smerffy:BAAANQAECgEIAQAAAA==.Smites:BAAANQADCgUICAABNQAECgEIAQABAAAAAA==.',
So='Somehobo:BAAANQADCgIIAgAAAA==.Sonny:BAAANQAECgIIAgAAAA==.Sorshalynne:BAAANQADCgUIBwAAAA==.Soulhorror:BAAANQAECgEIAQAAAA==.',
Sp='Spiritfire:BAAANQAECgEIAQAAAA==.Spitefury:BAAANQAECgMIBAAAAA==.Spriggs:BAAANQAECgQIBAAAAA==.',
St='Stepfather:BAAANQADCgIIAgAAAA==.Stepmother:BAAANQADCgIIAgAAAA==.Stonedread:BAAANQADCgUIBQAAAA==.Stronker:BAAANQADCggICgAAAA==.',
Su='Sungmi:BAAANQAECgEIAQAAAA==.Sunntzu:BAAANQAECgEIAQAAAA==.',
Sw='Swindlle:BAAANQADCgYICwAAAA==.',
Sy='Syber:BAAANQAECgIIAwAAAA==.Sylvaynetta:BAAANQAECgUIBwAAAA==.Sympathy:BAAANQADCgUIBQAAAA==.Symphonica:BAAANQAECgIIAQAAAA==.Syreithis:BAAANQADCggIDQAAAA==.',
['Sí']='Síd:BAAANQAECgUIBgAAAA==.',
['Sî']='Sîccness:BAAANQAECgEIAQAAAA==.',
Ta='Tacofighter:BAAANQADCgcICQAAAA==.Taerielle:BAAANQAECgUIDAAAAA==.Taldim:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Tarò:BAAANQAECgcIDQAAAA==.Taychi:BAAANQAECgIIAgABNQAECgYIBgABAAAAAA==.',
Te='Teacupps:BAAANQAECgcICwAAAA==.Teegan:BAAANQADCgcICgABNQAECgIIAgABAAAAAA==.Telvissra:BAAANQAECgQIBAAAAA==.Teoritta:BAAANQAECgMIBAAAAA==.Terrisher:BAAANQAECgEIAQAAAA==.',
Th='Thermopalea:BAAANQADCgUIBQAAAA==.Thetamoon:BAAANQAECgEIAQAAAA==.Thorald:BAAANQADCgcICwAAAA==.Thorggon:BAAANQAECgMIAwAAAA==.Thornbeast:BAAANQAECgEIAQAAAA==.Thuato:BAAANQADCgQICAAAAA==.Thundermayne:BAAANQADCgYIBgAAAA==.Thád:BAAANQADCgYIDAAAAA==.',
Ti='Tiranoc:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
To='Toxique:BAAANQADCgYICAAAAA==.',
Tr='Travelocitee:BAAANQADCggICAAAAA==.Triskalyn:BAAANQADCgcIAQAAAA==.Trojanhorse:BAAANQADCgcIHAAAAA==.Trokosan:BAAANQADCgUIBgAAAA==.Trustissues:BAAANQADCggIEAAAAA==.Try:BAAANQAFFAIIAwAAAA==.Trybu:BAAANQAECgQIBwAAAA==.Tryiss:BAAANQADCgYICgAAAA==.',
Tt='Ttryss:BAAANQADCgUIBQAAAA==.',
Tu='Tubslumpkin:BAAANQADCgQIBQAAAA==.Tuketu:BAAANQAECgMIAwAAAA==.Turtlelord:BAAANQADCggIBwAAAA==.',
Ty='Tylarion:BAAANQADCgYIBwAAAA==.Tylendal:BAAANQAECgMIBAAAAA==.Tylenulz:BAAANQADCgQIBQAAAA==.Tyliera:BAAANQADCgcICAAAAA==.Tylren:BAAANQADCgUIBQAAAA==.',
['Tà']='Tànya:BAAANQADCgYICwAAAA==.',
Ut='Uthercito:BAAANQADCggICQAAAA==.',
Va='Vallarath:BAAANQADCggIDQAAAA==.Valtaran:BAAANQADCgYICwAAAA==.Valtarr:BAAANQAECgEIAQAAAA==.Vampirism:BAAANQADCggIDwAAAA==.Vasira:BAAANQADCgYIBgAAAA==.Vaulthunter:BAAANQADCgUICQAAAA==.',
Ve='Vecna:BAAANQADCgIIAgAAAA==.Veloril:BAAANQADCgUIBQAAAA==.Vethena:BAAANQADCgIIAgAAAA==.Vezahk:BAAANQADCgEIAQAAAA==.',
Vi='Vidu:BAAANQAECgEIAQAAAA==.Vikas:BAAANQADCgYIBgAAAA==.Vivitrix:BAAANQADCgYICgAAAA==.Viví:BAAANQAECgMIBAAAAA==.',
Vo='Vordis:BAAANQAECgEIAQAAAA==.',
Vv='Vv:BAAANQADCgcIDQAAAA==.',
Vy='Vyrstal:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.',
Wa='Wardan:BAAANQADCgEIAQAAAA==.',
We='Weavile:BAAANQADCgUIBQABNQAFFAIIAwABAAAAAA==.Wef:BAAANQADCgYICwAAAA==.Weirdtotem:BAAANQAFFAIIAgAAAA==.Westylad:BAAANQADCgYICQAAAA==.Wetrat:BAAANQAECgUIBQABNQAECgcIDQABAAAAAA==.',
Wh='Whatthefunk:BAAANQADCgUIBQAAAA==.',
Wi='Winters:BAAANQADCgMIAwAAAA==.',
Wr='Wrystal:BAAANQAECgIIAgAAAA==.',
Xe='Xernes:BAAANQADCgQIBAAAAA==.',
Xu='Xujian:BAAANQADCgYICwAAAA==.',
Ya='Yakiki:BAAANQADCgcIBwABNQAECgcICgABAAAAAA==.',
Za='Zaelenia:BAAANQADCgcIDAAAAA==.Zalen:BAAANQAECgEIAQAAAA==.Zappylad:BAAANQADCggICAAAAA==.',
Ze='Zenamani:BAAANQADCgYICgAAAA==.Zenetha:BAAANQADCgcIDwAAAA==.Zephyres:BAAANQAECgEIAQABNQAECggICwABAAAAAA==.Zevarya:BAAANQADCgYICgAAAA==.',
Zo='Zonksmoose:BAAANQADCgYIBgAAAA==.Zonkspaladin:BAAANQAECgUIBwAAAA==.Zornac:BAAANQADCgYIBgAAAA==.',
Zp='Zpyder:BAAANQADCgYIDAAAAA==.',
Zy='Zynskie:BAAANQAECgMIBAAAAA==.Zyraa:BAAANQADCgIIAQAAAA==.',
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
