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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','Mage-Arcane','Druid-Restoration','Druid-Guardian','Druid-Feral','Druid-Balance','Priest-Shadow','Monk-Windwalker','Shaman-Elemental','Priest-Holy','Shaman-Enhancement',}
local provider = {region='US',realm='Windrunner',name='US',type='weekly',zone=53,date='2026-09-08',data={Ac='Accea:BAAANQADCgEIAQAAAA==.Acehobo:BAAANQADCgUIBQAAAA==.Acetaminofun:BAAANQAECgQIBQAAAA==.Actionjaxson:BAAANQAECgMIBAAAAA==.',
Ad='Adeathknight:BAAANQABCgIIAgAAAA==.Ademis:BAAANQADCgEIAQAAAA==.Admore:BAAANQADCggIFQAAAA==.',
Ae='Aeriith:BAAANQAECgUIBwAAAA==.Aethmourne:BAAANQADCgMIAwAAAA==.',
Ag='Agameden:BAAANQADCggIFQAAAA==.Agogg:BAAANQADCgUIBQAAAA==.',
Ah='Ahsina:BAAANQABCgQIBAAAAA==.',
Ai='Aintnosecret:BAAANQADCggIFAAAAA==.Aishi:BAAANQAECgQIBAAAAA==.',
Ak='Akaya:BAAANQAECgEIAQABNQAECgUICAABAAAAAA==.Akitsuki:BAAANQADCgUIBQAAAA==.',
Al='Algy:BAAANQADCgIIAgAAAA==.Alillara:BAAANQADCgIIAgAAAA==.Alivron:BAAANQAECgQIBAAAAA==.Alkoren:BAAANQADCggIFgABNQAECgUICAABAAAAAA==.Alkorin:BAAANQAECgUICAAAAA==.Allestra:BAAANQAECgcIDgAAAA==.',
Am='Amoxil:BAAANQADCggIFQAAAA==.',
An='Anasztaizia:BAEANQADCggIFQAAAA==.Andorin:BAAANQAECgYICQAAAA==.Angelclaw:BAAANQAECgUIBwAAAA==.Anunitu:BAAANQAECgMIAwAAAA==.',
Ao='Aoibheann:BAAANQADCggIEgAAAA==.',
Ar='Arath:BAAANQAECgcICwAAAA==.Arcath:BAAANQAECgQIBgAAAA==.Arcona:BAAANQADCgcIEgAAAA==.Arthuel:BAAANQADCgIIAgAAAA==.',
As='Asar:BAAANQADCgEIAQAAAA==.Ashlanni:BAAANQADCgIIAwAAAA==.Asiaminor:BAAANQADCgMIBQAAAA==.Astora:BAAANQADCgcIBwAAAA==.',
At='Athuzad:BAAANQAECgQIBgAAAA==.',
Au='Auroraalysia:BAAANQADCgYICwAAAA==.Auroran:BAAANQAECgQIBQAAAA==.Autumnmoon:BAAANQAECgEIAgAAAA==.',
Av='Avrilenv:BAAANQAECgEIAQAAAA==.',
Ay='Ayeroh:BAAANQADCgcIDwAAAA==.',
Az='Azenet:BAAANQADCgYIBgAAAA==.',
Ba='Bakasaura:BAAANQADCgUICgAAAA==.Balorous:BAAANQAECgIIAgAAAA==.Bansheelen:BAAANQAECgUIBQAAAA==.Banthis:BAAANQAECgQIBQAAAA==.Barkcamon:BAAANQAECgYIBgAAAA==.Barmaak:BAAANQAECgEIAQAAAA==.Barrand:BAAANQADCggICAAAAA==.Barthelo:BAAANQAECgMIBAAAAA==.Baxdock:BAAANQADCgYICAAAAA==.Baxideath:BAAANQADCggIEAAAAA==.',
Be='Bekahroo:BAAANQADCgUICgABNQADCgcIDQABAAAAAA==.Bekahsama:BAAANQADCgcIDQAAAA==.Belcron:BAAANQADCgUICgAAAA==.Beldaran:BAAANQADCggIFQAAAA==.Belladawna:BAAANQAECgMIBAAAAA==.Belldândy:BAAANQADCgcICwAAAA==.Bernal:BAAANQADCgcIEgAAAA==.',
Bh='Bhature:BAAANQADCgMIAwAAAA==.',
Bi='Bigmapletree:BAAANQAECgIIAgAAAA==.Bigëmu:BAAANQADCgYIDgAAAA==.Billyidols:BAAANQADCgEIAQAAAA==.Bingbangpów:BAAANQAECgIIAQAAAA==.',
Bl='Blackblader:BAAANQADCgcICAAAAA==.Blarus:BAAANQADCgIIAgAAAA==.Blueplanet:BAAANQAECgMIBgAAAA==.',
Bo='Boherwin:BAAANQAECgMIAwAAAA==.Borealus:BAAANQAECgEIAQAAAA==.',
Br='Bratakwar:BAAANQADCggICAAAAA==.Bris:BAAANQAECgMIBAAAAA==.Bruby:BAAANQAECgQIBQAAAA==.Bruceleelad:BAAANQADCgYIBgAAAA==.Brugamen:BAAANQAECgMIBQABNQAECgQIBQABAAAAAA==.Brugg:BAAANQAECgQIBQAAAA==.Brád:BAAANQADCggIFAAAAA==.',
Bu='Bunnylajoya:BAAANQADCgYICwAAAA==.Burgerz:BAAANQADCggIFQAAAA==.Busblaster:BAAANQAECgQIBQAAAA==.',
['Bä']='Bäldur:BAAANQAECgEIAQAAAA==.',
Ca='Calestel:BAAANQADCgIIAgAAAA==.Careßear:BAAANQADCgYIBgAAAA==.Carielle:BAAANQADCgUIBQAAAA==.Carodd:BAABNQAECoEYAAICAAkJrhkUBgCpAgACAAkJrhkUBgCpAgAAAA==.',
Ce='Cedaver:BAAANQAECgMIAwAAAA==.Ceez:BAAANQADCgYIBwAAAA==.Celtigar:BAAANQADCgcIEgAAAA==.',
Ch='Chaan:BAAANQADCggIFgAAAA==.Chaddicus:BAAANQADCgcIEgAAAA==.Chainna:BAAANQADCggICAAAAA==.Chanlin:BAAANQAECgYIDgAAAA==.Chateau:BAAANQADCggICAAAAA==.Chauda:BAAANQADCgQIBAABNQAECgUICAABAAAAAA==.Chazbot:BAAANQADCgYIBgAAAA==.Chereth:BAAANQADCgcIEgAAAA==.Cheshire:BAAANQAECgQIBwAAAA==.Chestystab:BAAANQADCggIEQAAAA==.Chezpuff:BAAANQADCgEIAQAAAA==.Chill:BAAANQAECgMIBAAAAA==.Chlorin:BAAANQAECgMIBAAAAA==.Chocolate:BAABNQAECoEWAAIDAAkJtxwXGAAHAwADAAkJtxwXGAAHAwAAAA==.',
Cl='Cloudcrasher:BAAANQADCgYICgAAAA==.Cloudsayer:BAAANQADCgYIDAAAAA==.Cloudspeaker:BAAANQAECgQIBQAAAA==.',
Co='Coldfrostshk:BAAANQADCgUICgAAAA==.Coldslayer:BAAANQAECgIIAwAAAA==.Copy:BAAANQAECgEIAQAAAA==.',
Cr='Crackzap:BAAANQAECgEIAQAAAA==.Crazyrd:BAAANQAECgIIAgAAAA==.Crotgustus:BAAANQADCgMIBQAAAA==.Crumblebump:BAAANQADCgcIEgAAAA==.Crummbly:BAAANQADCgYIDwAAAA==.',
Cy='Cyndelle:BAAANQADCgYIEAAAAA==.Cyntaria:BAAANQADCgcIDwAAAA==.Cyriz:BAAANQADCggIDwAAAA==.',
Da='Daienne:BAAANQAECgIIAgAAAA==.Danamor:BAAANQAECgMIAwAAAA==.Dandanx:BAAANQADCgUICgABNQAECgMIAwABAAAAAA==.Daplug:BAAANQADCggIEAAAAA==.Darkbrand:BAAANQAECgIIAgAAAA==.Darkladÿ:BAAANQADCgMIAwAAAA==.Darnel:BAAANQAECgMIBAAAAA==.Darnokk:BAAANQADCgcIEgAAAA==.',
De='Deathbyfel:BAAANQADCgUIBQABNQAECgEIAgABAAAAAA==.Deathbyshock:BAAANQAECgEIAgAAAA==.Deathrollins:BAAANQADCgcIEQAAAA==.Delaror:BAAANQADCgYIBgAAAA==.Denadin:BAAANQAECgEIAQAAAA==.Denari:BAAANQABCgEIAQAAAA==.Dennygrips:BAAANQADCgUIBQAAAA==.Dennyshreds:BAAANQAECgMIAwAAAA==.Denrukhan:BAABNQAECoEWAAIEAAkJQSDOAgAiAwAEAAkJQSDOAgAiAwAAAA==.Deschain:BAAANQADCgUIDQAAAA==.Dew:BAAANQAECgYIBwAAAA==.',
Di='Diin:BAAANQADCggIEwAAAA==.',
Dk='Dklord:BAAANQADCggIEwAAAA==.',
Do='Donappletino:BAAANQADCgYIBgAAAA==.Donkedixlol:BAAANQADCgcICwAAAA==.Doobzers:BAAANQADCgMIAwABNQAECgYICAABAAAAAA==.Doxtorele:BAAANQADCgIIAgABNQAECgMIBwABAAAAAA==.Doxtorprote:BAAANQAECgMIBwAAAA==.',
Dr='Dredd:BAAANQADCgUIBQAAAA==.Drunk:BAAANQAECgUICQAAAA==.',
Du='Duckpally:BAAANQABCgYIBgAAAA==.',
Dw='Dwarfussy:BAAANQAECgIIAwAAAA==.',
Ea='Earthernheal:BAAANQADCgcIDAAAAA==.',
Eh='Ehonte:BAAANQAECgQIBgAAAA==.',
Ei='Eidolonn:BAAANQADCgUICgAAAA==.',
Ek='Ekkaia:BAAANQAECgMIBAAAAA==.',
El='Elfypriestly:BAAANQADCgUIBwAAAA==.Elsell:BAAANQAECgEIAQAAAA==.Elwasp:BAAANQADCgYIBgAAAA==.',
En='Encana:BAAANQAECgQIBwAAAA==.Ender:BAAANQADCgYIEAAAAA==.',
Ep='Epiales:BAAANQADCgUIBQAAAA==.',
Er='Ericgb:BAABNQAECoEUAAMFAAcJ4BHZBgCqAQAFAAcJfRHZBgCqAQAGAAEJPAOTFAAxAAAAAA==.Eronara:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Errzza:BAAANQADCgcIEgAAAA==.Erzsébet:BAAANQAECgEIAgAAAA==.',
Es='Esha:BAAANQADCgUIBgAAAA==.',
Et='Etsupriest:BAAANQAECgUICQAAAA==.',
Eu='Eula:BAAANQADCgUIBQAAAA==.',
Ev='Evelynn:BAAANQADCgUICwAAAA==.Evoked:BAAANQABCgQIBAABNQADCggICAABAAAAAA==.',
Ex='Exanimus:BAAANQADCgUICAAAAA==.Exign:BAAANQADCgIIAgAAAA==.Exqui:BAAANQAECgMIBAAAAA==.',
Ez='Ezral:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
['Eí']='Eíko:BAAANQAECgcIBwAAAA==.',
Fa='Faeruh:BAAANQADCggICQAAAA==.Fafnar:BAAANQADCgUIBQABNQAECgMIBAABAAAAAA==.Fafnie:BAAANQAECgEIAQAAAA==.',
Fe='Felath:BAAANQAECgMIAwAAAA==.Feldspar:BAAANQADCggIFQAAAA==.',
Fi='Fil:BAAANQAECgMIAwAAAA==.Fishswife:BAAANQADCggIEQAAAA==.Fissal:BAAANQADCgcIBwAAAA==.Fistoflurry:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.',
Fl='Flameviper:BAAANQADCgcIDwAAAA==.',
Fo='Foofighter:BAAANQADCgIIAgAAAA==.Footoo:BAAANQADCgcIEQAAAA==.Foxybrie:BAAANQABCgIIAgAAAA==.',
Fr='Franksuba:BAAANQADCgMIBQAAAA==.',
Fu='Fuknord:BAAANQADCgYIBwAAAA==.Fulva:BAAANQADCgcIBgAAAA==.',
Fy='Fyneep:BAAANQAECgIIAwAAAA==.Fynne:BAAANQAECgYIDQAAAA==.',
Ga='Gaiusmohiam:BAAANQABCgQIBAAAAA==.Galdademon:BAAANQADCgcICwAAAA==.Galiophobia:BAAANQADCgYICwAAAA==.Galm:BAAANQADCgUIBQAAAA==.Garrethul:BAAANQAECgMIBAAAAA==.Gawleywood:BAAANQADCgcIEgAAAA==.',
Ge='Gellidus:BAAANQAECgMIBAAAAA==.Genhooves:BAEANQADCgYICwABNQAECgUICgABAAAAAA==.Gensisd:BAAANQAECgMIBAAAAA==.Gerulf:BAAANQABCgQIBAAAAA==.',
Gh='Ghosteagle:BAAANQADCgQIBAAAAA==.Ghostvoid:BAAANQABCgYICgAAAA==.',
Gn='Gnomejodas:BAAANQADCgYIBgAAAA==.',
Go='Gobfather:BAAANQADCgcIDAAAAA==.Goodfaith:BAAANQADCgcIEgAAAA==.Goofy:BAAANQAFFAEIAQABNQADCggIEAABAAAAAA==.',
Gr='Grimlocke:BAAANQAECgIIAgAAAA==.Grimsolo:BAAANQADCggIEQABNQAECgIIAgABAAAAAA==.Gromit:BAAANQAECgcICwAAAA==.',
Gu='Gubber:BAAANQADCgIIAQAAAA==.',
Gw='Gwyndolin:BAAANQADCgYIBgAAAA==.Gwynne:BAAANQADCggIFQAAAA==.',
Ha='Halanad:BAAANQADCggIFQAAAA==.Halfmoons:BAAANQAECgIIBAAAAA==.Halfsumo:BAAANQADCggIFAAAAA==.Halobender:BAAANQADCggICAAAAA==.Harrol:BAAANQAECgQIBgABNQAECgQIBAABAAAAAA==.Hassindiir:BAAANQAECgUIBgAAAA==.Hawgelf:BAAANQAECgIIAgAAAA==.Hawmahcide:BAAANQADCgYIBgAAAA==.Hayles:BAAANQADCgUICwAAAA==.',
He='Hermonk:BAAANQAECgQICAABNQAFFAEIAQABAAAAAA==.',
Hi='Hishunter:BAAANQAECgYICAABNQAECgkJGgAHAEkcAA==.',
Hu='Hunterdamon:BAAANQAECgMIBAAAAA==.',
Hy='Hycinna:BAAANQADCgYICwAAAQ==.Hydrazashen:BAAANQADCgYIBwAAAA==.',
Ia='Iamafish:BAAANQAECgMIAwAAAA==.',
Ig='Igotyou:BAAANQAECgIIAgAAAA==.',
In='Insidae:BAAANQAECgMIAwAAAA==.',
Ir='Ironpunch:BAAANQADCggICQAAAA==.',
Is='Ismirea:BAAANQADCgUIBQAAAA==.Isoldella:BAAANQADCgYIBgAAAA==.',
Ja='Jalencarter:BAAANQAECgUICQAAAA==.Jamirprote:BAAANQADCgIIAgAAAA==.Jantasir:BAAANQADCggIEAAAAA==.Javalyn:BAAANQADCgcIDgAAAA==.',
Ji='Jinda:BAAANQADCgQICgAAAA==.Jirachi:BAAANQADCgMIAwABNQAFFAMIBgAIAEYIAA==.Jiu:BAAANQAECgMIAwAAAA==.',
Jo='Jobergas:BAAANQADCgcIDQAAAA==.Jobi:BAAANQAECgIIAwAAAA==.Johallas:BAAANQAECgMIBAAAAA==.',
Ju='Judzia:BAAANQAECgMIAwAAAA==.Juf:BAAANQAECgIIAgAAAA==.Jumpingbear:BAABNQAECoEYAAIGAAkJpSAHAQBFAwAGAAkJpSAHAQBFAwAAAA==.Justdeadfred:BAAANQADCggICAAAAA==.',
Ka='Kagar:BAAANQADCgMIAwAAAA==.Kaho:BAAANQAECgUICQAAAA==.Kainazzo:BAAANQADCgYIDgAAAA==.Kaladïn:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Kalda:BAAANQAECgYIEQAAAA==.Kalikali:BAAANQABCgIIAgABNQAECgEIAgABAAAAAA==.Kallisto:BAAANQADCgcIEwAAAA==.Kattizzi:BAAANQADCgMIAwAAAA==.Kazuhiro:BAAANQAECggIEAAAAA==.',
Ke='Keagan:BAAANQADCggIEQAAAA==.Kehzai:BAAANQAECgEIAQAAAA==.Kelric:BAAANQADCgUIBQAAAA==.Kenpomaster:BAAANQADCgcIFQAAAA==.Keyalastus:BAAANQADCgQIBAAAAA==.',
Kh='Khaluha:BAAANQADCgcIEgAAAA==.Khaymaan:BAAANQADCgcIDwAAAA==.',
Ki='Kilmeawden:BAAANQAECgMIBAAAAA==.',
Kr='Krisha:BAAANQAECgUICAAAAA==.Krisphobos:BAAANQADCggIEwAAAA==.',
Ku='Kubael:BAAANQAECgEIAQAAAA==.Kulgutbuster:BAAANQAECgMIBAAAAA==.Kungpow:BAAANQAECgIIAgAAAA==.Kupdor:BAAANQADCggICAAAAA==.Kuromatsu:BAAANQAECgEIAgAAAA==.',
['Kÿ']='Kÿt:BAAANQAECgMIAwAAAA==.',
La='Lantank:BAAANQABCgIIAgAAAA==.Larceny:BAAANQAECgEIAQAAAA==.Larfleeze:BAAANQADCgYIBgAAAA==.',
Le='Leiania:BAAANQADCgUIBQABNQAECgcICwABAAAAAA==.Lewis:BAAANQADCggICAAAAA==.',
Li='Lild:BAAANQADCgYICQAAAA==.Liqudblu:BAAANQADCgMIAwAAAA==.Lishan:BAAANQAECgQIBAAAAA==.Liszandera:BAAANQADCggIEAAAAA==.Literein:BAAANQAECgIIAgAAAA==.Lizora:BAAANQAECgUIBQAAAA==.',
Lo='Lokisan:BAAANQADCgMIAwAAAA==.Lorenei:BAAANQAECgIIAgAAAA==.Los:BAAANQADCgYIBgAAAA==.',
Lt='Ltwhisker:BAAANQAECgEIAQAAAA==.',
Lu='Lucìd:BAAANQADCgYIBgAAAA==.Lucïd:BAAANQAECgIIAgAAAA==.Lunhzae:BAAANQADCgUIBQAAAA==.Lustallo:BAAANQADCgQIBAAAAA==.',
Ly='Lynxx:BAAANQADCgcIEwAAAA==.',
Ma='Macharth:BAAANQAECgEIAgAAAA==.Mack:BAAANQADCggIEgAAAA==.Mad:BAAANQAECgIIAwAAAA==.Madchickenz:BAAANQAECgQIBQAAAA==.Magicwithin:BAAANQAECgMIBAAAAQ==.Magut:BAAANQADCgMIAwAAAA==.Maira:BAAANQADCgYIEAAAAA==.Majim:BAAANQADCggIEgAAAA==.Malevolens:BAAANQADCgcIDgAAAA==.Mannyfingers:BAAANQADCgUIBQAAAA==.Marche:BAAANQAECgMIBAAAAA==.Marianacross:BAAANQADCgYIBgAAAA==.Marsel:BAAANQADCgYIBgAAAA==.Masokist:BAAANQADCgYIBgAAAA==.Mavdk:BAAANQADCggIDgABNQAECgQIBAABAAAAAA==.Mavrar:BAAANQAECgQIBAAAAA==.',
Mc='Mcflurrey:BAAANQAECgEIAgAAAA==.',
Me='Mechamana:BAAANQADCgYIBgABNQADCgYIBwABAAAAAA==.Melodrama:BAAANQADCgIIAgAAAA==.Meowrian:BAAANQADCgUIAgAAAA==.Mephïsto:BAAANQADCgYIDAAAAA==.Mereoleona:BAAANQAECgYICgAAAA==.Messdupllama:BAAANQAECgcIDwAAAA==.Metamorfasis:BAAANQAECgIIAgAAAA==.',
Mi='Micos:BAAANQADCggICAAAAA==.Microburst:BAAANQAECgEIAQAAAA==.Microcharge:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Miischief:BAAANQADCgUIDAAAAA==.Milkman:BAAANQADCggIFAAAAA==.Misslynn:BAAANQADCgcICgAAAA==.Missmoodý:BAAANQADCgcIEAAAAA==.Missqwerty:BAAANQAECgEIAQAAAA==.',
Mo='Moltenbeast:BAAANQADCgcIFAABNQAECgYIBgABAAAAAA==.Mongargiss:BAAANQADCggIEQAAAA==.Montaro:BAAANQADCgcIEgAAAA==.Morbidi:BAAANQADCgUIBwAAAA==.Mortharos:BAAANQAECgMIBQAAAA==.',
Mu='Mudkip:BAACNQAFFIEGAAIIAAMJRgjsAgDqAAAIAAMJRgjsAgDqAAA1AAQKgR8AAggACQn8Hm8EAEMDAAgACQn8Hm8EAEMDAAAA.Munnsta:BAAANQAECgEIAgAAAA==.',
My='Mylanara:BAAANQAECgMIBAAAAA==.Mysticah:BAAANQADCgcIDwAAAA==.Mythalagos:BAAANQADCgEIAQAAAA==.Mythblast:BAAANQAECgEIAQAAAA==.Myvrth:BAAANQADCgQIBAAAAA==.',
['Mä']='Märs:BAABNQAECoEaAAIHAAkJSRw8CgD9AgAHAAkJSRw8CgD9AgAAAA==.',
Na='Naelu:BAAANQADCgMIAwAAAA==.Nanr:BAAANQAECgMIBAAAAA==.Nathi:BAAANQADCggIFQAAAA==.Navori:BAABNQAECoEUAAIJAAgJuxeACwA+AgAJAAgJuxeACwA+AgAAAA==.Nazeraz:BAAANQAECgEIAQAAAA==.',
Ne='Nerve:BAAANQAECgUIBgAAAA==.Nesiryn:BAAANQADCgQIBAAAAA==.Neth:BAAANQAECgMIAwAAAA==.Neuroshots:BAAANQADCggIDwAAAA==.Newkers:BAAANQADCgUICQAAAA==.',
Ni='Nightknight:BAAANQADCgQIBwAAAA==.Nightràven:BAAANQAECgQIBgAAAA==.Nimrodd:BAAANQADCggIEwAAAA==.',
No='Nobby:BAAANQADCgUICgAAAA==.Noogan:BAAANQADCgYIBgAAAA==.Nosferatü:BAAANQADCgUIBQAAAA==.Nothotdog:BAAANQADCgIIAgAAAA==.Novacat:BAAANQAECgYIDwAAAA==.Novangel:BAAANQADCgYIBgAAAA==.November:BAAANQADCggIFQAAAA==.Nox:BAAANQADCggIBgAAAA==.',
Nu='Nubriss:BAAANQAECgIIAgAAAA==.Nudetayne:BAAANQADCgQIBAAAAA==.Nuitsguard:BAAANQAECgcIDQAAAA==.',
Ny='Nyaboron:BAAANQAECgMIBQAAAA==.',
['Nè']='Nèaner:BAAANQAECgUIBgAAAA==.',
Og='Oggden:BAAANQAECgEIAQAAAA==.Ogrebane:BAAANQAECgMIBAAAAA==.',
Oi='Oiheg:BAAANQAECgMIBAAAAA==.',
Pa='Pajamasniper:BAAANQAECgMIBAAAAA==.',
Pe='Peach:BAAANQAECgMIBAAAAA==.',
Ph='Photos:BAAANQAECgEIAgAAAA==.',
Pi='Pigums:BAAANQAECgIIAgAAAA==.',
Pl='Pluug:BAAANQAECgEIAQAAAA==.',
Pr='Prayer:BAAANQAECgMIBAABNQADCgcIBwABAAAAAA==.Prîde:BAAANQADCgYIBwAAAA==.',
Ps='Psycopath:BAAANQAECgUIBwAAAA==.Psygn:BAAANQADCgUIBQABNQAECgMIBAABAAAAAA==.',
Pt='Ptra:BAAANQAECgQIBAABNQAECgYICwABAAAAAA==.',
Pu='Pumpy:BAABNQAECoEWAAIKAAkJBiBUBQBpAwAKAAkJBiBUBQBpAwAAAA==.',
Py='Pywacket:BAAANQAECgEIAgAAAA==.',
['Pã']='Pãlàdoom:BAAANQADCgMIBgABNQAECgQIBgABAAAAAA==.',
Qu='Quendwings:BAEANQAECgUIBQABNQAECgkJHQAEAJogAA==.',
Ra='Rabern:BAAANQADCgIIAgAAAA==.Rainsky:BAAANQADCggICAAAAA==.Rayleighh:BAAANQAECgYICwAAAA==.',
Re='Redemptio:BAAANQAECgMIAwAAAA==.',
Ri='Rikaza:BAAANQADCgYIBgAAAA==.Ristraza:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.',
Ro='Roguewølf:BAAANQADCgQIBgAAAA==.Roono:BAAANQADCgcICgAAAA==.Rosalidia:BAAANQAECgIIAgAAAA==.Rossco:BAAANQAECgEIAQAAAA==.Rozzluz:BAAANQAECgUIBQAAAA==.',
Ru='Rutira:BAAANQAECgUIBgAAAA==.',
Ry='Ryân:BAAANQADCgMIAwAAAA==.',
Sa='Sabbat:BAAANQADCgUIBQAAAA==.Sapphiwrath:BAAANQADCgYIDAAAAA==.',
Se='Seacow:BAAANQADCggIDgAAAA==.Searilus:BAAANQADCgcIEgAAAA==.Seethed:BAAANQADCgUIBQAAAA==.Selyana:BAAANQADCggICAAAAA==.Seylena:BAAANQADCgUICgABNQAECgMIBAABAAAAAA==.',
Sh='Shammallamma:BAAANQABCgQIBgAAAA==.Shamæn:BAAANQADCgcIBwAAAA==.Shaphyr:BAAANQADCgUIBgABNQAECgQIBQABAAAAAA==.Sharphammer:BAAANQADCgMIBQAAAA==.Shieldon:BAAANQADCgUIBQABNQAECgEIAgABAAAAAA==.Shinhealer:BAAANQAECgEIAQAAAA==.Shootsahlot:BAAANQADCgYIDAAAAA==.',
Si='Sidapa:BAAANQADCgYICgAAAA==.Silvernleaf:BAAANQADCgYIEAAAAA==.Sinai:BAAANQADCggICAAAAA==.Sindir:BAAANQADCgUIBQABNQAECgkJFgAEAEEgAA==.Siyx:BAAANQADCgUIBgAAAA==.',
Sk='Skept:BAAANQAECgIIAgAAAA==.',
Sl='Sleêp:BAAANQADCggIFQAAAA==.Slosh:BAAANQAECgQIBgAAAA==.',
Sm='Smellyandfat:BAEBNQAECoEdAAMEAAkJmiAlAQB/AwAEAAkJmiAlAQB/AwAHAAcJqxkbGgATAgAAAA==.Smerffy:BAAANQAECgMIBAAAAA==.Smites:BAAANQADCgUICgABNQAECgMIBAABAAAAAA==.',
So='Somehobo:BAAANQADCgIIAgAAAA==.Sonny:BAAANQAECgMIBgAAAA==.Sorshalynne:BAAANQADCgcIDgAAAA==.Soulhorror:BAAANQAECgMIBAAAAA==.',
Sp='Spiritfire:BAAANQAECgEIAgAAAA==.Spitefury:BAAANQAECgMIBAABNQAECgYIBgABAAAAAA==.Spriggs:BAEANQAECgUICgAAAA==.',
St='Stepfather:BAAANQADCgIIAgAAAA==.Stepmother:BAAANQADCgIIAgAAAA==.Stonedread:BAAANQADCgYICwAAAA==.Stormfodder:BAAANQABCgQIBAAAAA==.Stronker:BAAANQADCggICgAAAA==.',
Su='Sungmi:BAAANQAECgQIBQAAAA==.Sunntzu:BAAANQAECgIIAwAAAA==.',
Sw='Swindlle:BAAANQADCggIEwAAAA==.',
Sy='Syber:BAAANQAECgUICAAAAA==.Sylvaynetta:BAAANQAECgYIDQAAAA==.Sympathy:BAAANQADCggIDQAAAA==.Symphonica:BAAANQAECgQIBQAAAA==.Syreithis:BAAANQADCggIFQAAAA==.',
['Sí']='Síd:BAAANQAECgUIBgAAAA==.',
Ta='Tacofighter:BAAANQAECgIIAgAAAA==.Taerielle:BAAANQAECgYIEgAAAA==.Tageren:BAAANQADCgQIBAAAAA==.Taldim:BAAANQADCgUIBQABNQAECgMIBAABAAAAAA==.Tarò:BAABNQAECoEYAAILAAkJEwbhIwDOAQALAAkJEwbhIwDOAQAAAA==.Taychi:BAAANQAECgIIAgABNQAECgcIDQABAAAAAA==.',
Te='Teacupps:BAAANQAECggIEgAAAA==.Teegan:BAAANQAECgQIBAAAAA==.Telvissra:BAAANQAECgcICwAAAA==.Teoritta:BAAANQAECgUICQAAAA==.Terrisher:BAAANQAECgMIBAAAAA==.',
Th='Thaljadrak:BAAANQADCgQIBwAAAA==.Thermopalea:BAAANQADCgUIBQAAAA==.Thetamoon:BAAANQAECgMIBAAAAA==.Thorald:BAAANQAECgEIAQAAAA==.Thorggon:BAAANQAECgQIBQAAAA==.Thornbeast:BAAANQAECgEIAgAAAA==.Thuato:BAAANQADCgQICAAAAA==.Thundermayne:BAAANQADCgcIBwAAAA==.Thád:BAAANQADCggIFAAAAA==.',
Ti='Tiranoc:BAAANQADCgUIBQABNQAECgMIBAABAAAAAA==.',
To='Tojara:BAAANQADCgcIBwAAAA==.Toxique:BAAANQADCgcIDwAAAA==.',
Tr='Travelocitee:BAAANQADCggIEAAAAA==.Triskalyn:BAAANQADCggICQAAAA==.Trojanhorse:BAAANQADCggIIAAAAA==.Trokosan:BAAANQADCgUIBgAAAA==.Trustissues:BAAANQADCggIFgAAAA==.Try:BAACNQAFFIEFAAIMAAMJQxljAAAvAQAMAAMJQxljAAAvAQA1AAQKgRkAAgwACQl9JjEAAOcDAAwACQl9JjEAAOcDAAAA.Trybu:BAAANQAECgcIEAAAAA==.Tryiss:BAAANQADCggIEgAAAA==.',
Tt='Ttryss:BAAANQADCgUIBQAAAA==.',
Tu='Tubslumpkin:BAAANQAECgIIAgAAAA==.Tuketu:BAAANQAECgQIBwAAAA==.Turtlelord:BAAANQAECgUIBQAAAA==.',
Ty='Tylarion:BAAANQADCgYICgAAAA==.Tylendal:BAAANQAECgQICAAAAA==.Tylenulz:BAAANQADCgQIBQAAAA==.Tylheras:BAAANQAECgUIBwAAAA==.Tyliera:BAAANQADCgcICAAAAA==.Tylren:BAAANQADCgUICAAAAA==.',
['Tà']='Tànya:BAAANQADCggIEwAAAA==.',
Ut='Uthercito:BAAANQADCggICQAAAA==.',
Va='Vallarath:BAAANQAECgEIAQAAAA==.Valtaran:BAAANQADCgcIEgAAAA==.Valtarr:BAAANQAECgMIBAAAAA==.Vampirism:BAAANQAECgMIAwAAAA==.Vasira:BAAANQADCgcIDQAAAA==.Vaulthunter:BAAANQADCgcIEQAAAA==.',
Ve='Vecna:BAAANQADCgMIBQAAAA==.Veloril:BAAANQADCgUIBQAAAA==.Vethena:BAAANQADCgIIAgAAAA==.Vezahk:BAAANQADCgEIAQAAAA==.',
Vi='Vidu:BAAANQAECgMIBAAAAA==.Vikas:BAAANQADCgYIBgAAAA==.Vivitrix:BAAANQADCgcIEQAAAA==.Viví:BAAANQAECgQICQAAAA==.',
Vl='Vlm:BAAANQADCgMIAwAAAA==.',
Vo='Voidbreaker:BAAANQAECgEIAgABNQAECgYIEQABAAAAAA==.Vordis:BAAANQAECgQIBQAAAA==.Voxis:BAAANQADCgYIBgAAAA==.',
Vv='Vv:BAAANQADCggIFQAAAA==.',
Vy='Vyrstal:BAAANQADCggICAABNQAECgQIBgABAAAAAA==.',
Wa='Wardan:BAAANQADCgUIBgAAAA==.',
We='Weavile:BAAANQADCgUIBQABNQAFFAMIBgAIAEYIAA==.Wef:BAAANQADCgYIEQAAAA==.Weirdtotem:BAAANQAFFAIIAgAAAA==.Westylad:BAAANQAECgYIBgAAAA==.Wetrat:BAAANQAECgUIBQABNQAECgkJFgAKAAYgAA==.',
Wh='Whatthefunk:BAAANQADCgUIBgAAAA==.',
Wi='Winterfox:BAAANQADCgMIAwAAAA==.Winters:BAAANQADCgMIAwAAAA==.',
Wr='Wrystal:BAAANQAECgQIBgAAAA==.',
Xe='Xernes:BAAANQADCgQIBAAAAA==.',
Xu='Xujian:BAAANQADCgcIDwAAAA==.',
Ya='Yakiki:BAAANQADCgcIBwABNQAECgkJGwAIAKAeAA==.',
Za='Zaelenia:BAAANQAECgEIAQAAAA==.Zalen:BAAANQAECgMIBAAAAA==.Zappylad:BAAANQAECgMIAwAAAA==.',
Ze='Zenamani:BAAANQADCgYICgAAAA==.Zenetha:BAAANQAECgEIAQAAAA==.Zephyres:BAAANQAECggICQABNQAECggIEAABAAAAAA==.Zerokool:BAAANQABCgYIBgABNQAECgIIAgABAAAAAA==.Zevarya:BAAANQADCgYICgAAAA==.',
Zo='Zonksmoose:BAAANQADCgYIBgAAAA==.Zonkspaladin:BAAANQAECgYIEgAAAA==.Zornac:BAAANQADCgYIBgAAAA==.',
Zp='Zpyder:BAAANQADCggIFAAAAA==.',
Zy='Zynskie:BAAANQAECgQICAAAAA==.Zyraa:BAAANQADCgIIAQAAAA==.',
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
