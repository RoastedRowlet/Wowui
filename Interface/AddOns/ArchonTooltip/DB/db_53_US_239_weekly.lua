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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','DeathKnight-Frost','DeathKnight-Blood','Mage-Arcane','Shaman-Elemental','Druid-Restoration','Druid-Balance','Druid-Guardian','Druid-Feral','Priest-Holy','Priest-Shadow','Warrior-Arms','Hunter-BeastMastery','Monk-Windwalker','Shaman-Restoration','Shaman-Enhancement','Mage-Frost','Warlock-Destruction','Warlock-Demonology','Paladin-Holy',}
local provider = {region='US',realm='Windrunner',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Accea:BAAANQADCgEIAQAAAA==.Acehobo:BAAANQADCgUIBQAAAA==.Acetaminofun:BAAANQAECgQIBwAAAA==.Actionjaxson:BAAANQAECgQICAAAAA==.',
Ad='Adeathknight:BAAANQABCgIIAgAAAA==.Ademis:BAAANQAECgEIAQAAAA==.Admore:BAAANQAECgMIAwAAAA==.',
Ae='Aeriith:BAAANQAECgcIDAAAAA==.Aethmourne:BAAANQADCgMIAwAAAA==.',
Ag='Agameden:BAAANQAECgIIAgAAAA==.Agogg:BAAANQADCgcIDAAAAA==.Agronak:BAAANQABCgIIAgAAAA==.',
Ah='Ahsina:BAAANQABCgUIBQAAAA==.',
Ai='Aintnosecret:BAAANQAECgMIAwAAAA==.Aishi:BAAANQAECgQIBgAAAA==.',
Ak='Akaya:BAAANQAECgEIAgABNQAECgYIDAABAAAAAA==.Akitsuki:BAAANQADCgUIBQAAAA==.',
Al='Algy:BAAANQADCgIIAgAAAA==.Alillara:BAAANQADCgIIAgAAAA==.Alivron:BAAANQAECgYICgAAAA==.Alkoren:BAAANQAECgEIAQABNQAECgYIDgABAAAAAA==.Alkorin:BAAANQAECgYIDgAAAA==.Allestra:BAABNQAECoEZAAICAAgJxBs1DwCnAgACAAgJxBs1DwCnAgAAAA==.',
Am='Amaranthine:BAAANQADCgYIBgAAAA==.Amoxil:BAAANQADCggIGgAAAA==.',
An='Anasztaizia:BAEANQAECgEIAQAAAA==.Andorin:BAAANQAECgcIEAAAAA==.Angelclaw:BAAANQAECgUIDgAAAA==.Anorah:BAAANQAECgEIAQAAAA==.Anunitu:BAAANQAECgUICAAAAA==.',
Ao='Aoibheann:BAAANQAECgMIAwAAAA==.',
Ar='Arath:BAAANQAECgcIEgAAAA==.Arcath:BAAANQAECgUICwAAAA==.Arcona:BAAANQADCgcIGQAAAA==.Aristus:BAAANQADCgYIBgAAAA==.Arthuel:BAAANQADCgIIAgAAAA==.',
As='Asar:BAAANQAECgEIAQAAAA==.Ashlanni:BAAANQADCgIIAwAAAA==.Asiaminor:BAAANQADCgMIBQAAAA==.Astora:BAAANQADCgcIBwAAAA==.',
At='Athuzad:BAAANQAECgUICwAAAA==.',
Au='Auroraalysia:BAAANQADCgYICwAAAA==.Auroran:BAAANQAECgUICgAAAA==.Autumnmoon:BAAANQAECgQIBgAAAA==.',
Av='Aviendah:BAAANQADCgYIBgAAAA==.Avrilenv:BAAANQAECgEIAQAAAA==.',
Ay='Ayeroh:BAAANQADCgcIFgAAAA==.',
Az='Azenet:BAAANQADCgYIBgAAAA==.',
Ba='Bakasaura:BAAANQADCgYICwABNQAECgQICgABAAAAAA==.Balorous:BAAANQAECgQIBgAAAA==.Bansheelen:BAAANQAECgYICwAAAA==.Banthis:BAAANQAECgYICwAAAA==.Barkcamon:BAAANQAECgYIDAAAAA==.Barmaak:BAAANQAECgEIAQAAAA==.Barrand:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Barthelo:BAAANQAECgQICAAAAA==.Bassandi:BAAANQADCgEIAQABNQAECgUICgABAAAAAA==.Baxdock:BAAANQAECgEIAQAAAA==.Baxideath:BAAANQAECgMIAwAAAA==.',
Be='Beefcâke:BAAANQADCgYIBgAAAA==.Bekahroo:BAAANQADCgYIEAABNQADCggIFQABAAAAAA==.Bekahsama:BAAANQADCggIFQAAAA==.Belcron:BAAANQADCgYICwAAAA==.Beld:BAAANQADCgYIBgAAAA==.Beldaran:BAAANQAECgEIAQAAAA==.Belladawna:BAAANQAECgQICAAAAA==.Belldândy:BAAANQADCggIDQAAAA==.Bernal:BAAANQADCgcIGQAAAA==.',
Bh='Bhature:BAAANQADCgMIAwAAAA==.',
Bi='Bigmapletree:BAAANQAECgIIBAAAAA==.Bigëmu:BAAANQADCgYIFAAAAA==.Billyidols:BAAANQADCgEIAQAAAA==.Bingbangpów:BAAANQAECgIIAgAAAA==.',
Bl='Blackblader:BAAANQADCgcIDwAAAA==.Blarus:BAAANQADCgIIAgAAAA==.Bluecat:BAAANQADCgIIAgAAAA==.Blueplanet:BAAANQAECgQICgAAAA==.',
Bo='Boarggon:BAAANQADCgEIAQABNQAECgQICQABAAAAAA==.Boherwin:BAAANQAECgQIBgAAAA==.Borealus:BAAANQAECgQIBQAAAA==.',
Br='Bratakwar:BAAANQADCggICAAAAA==.Bris:BAAANQAECgUICAAAAA==.Bruby:BAAANQAECgQIBQAAAA==.Bruceleelad:BAAANQADCgYIBgAAAA==.Brugamen:BAAANQAECgUICgABNQAECgUICgABAAAAAA==.Brugg:BAAANQAECgUICgAAAA==.Brynnu:BAAANQADCgIIAgAAAA==.Brád:BAAANQAECgMIAwAAAA==.',
Bu='Bunnylajoya:BAAANQADCgYICwAAAA==.Burgerz:BAAANQADCggIGwAAAA==.Busblaster:BAAANQAECgUICgAAAA==.',
['Bä']='Bäldur:BAAANQAECgEIAQAAAA==.',
Ca='Calestel:BAAANQADCgIIAgAAAA==.Careßear:BAAANQADCggICAAAAA==.Carielle:BAAANQADCgcIDAAAAA==.Carodd:BAABNQAECoEhAAIDAAkJbRydBgALAwADAAkJbRydBgALAwAAAA==.',
Ce='Cedaver:BAAANQAECgQIBwAAAA==.Ceez:BAAANQADCgYIBwAAAA==.Celtigar:BAAANQADCggIGgAAAA==.',
Ch='Chaan:BAAANQAECgEIAQAAAA==.Chaddicus:BAAANQADCggIFAAAAA==.Chainna:BAAANQADCggIEAAAAA==.Chanlin:BAABNQAECoEWAAIEAAgJxx8FDwDPAgAEAAgJxx8FDwDPAgAAAA==.Chateau:BAAANQADCggICAAAAA==.Chauda:BAAANQADCgcICwABNQAECgYIDAABAAAAAA==.Chazbot:BAAANQADCgYIBgAAAA==.Chereth:BAAANQADCgcIGQAAAA==.Cheshire:BAAANQAECgYIDQAAAA==.Chestystab:BAAANQADCggIEgAAAA==.Chezpuff:BAAANQADCgEIAQAAAA==.Chill:BAAANQAECgMIBgAAAA==.Chlorin:BAAANQAECgYICgAAAA==.Chocolate:BAABNQAECoEXAAIFAAkJFh01KwDkAgAFAAkJFh01KwDkAgAAAA==.',
Cl='Cloudcrasher:BAAANQADCgYICgAAAA==.Cloudsayer:BAAANQAECgIIAgAAAA==.Cloudspeaker:BAAANQAECgUICgAAAA==.',
Co='Coldfrostshk:BAAANQADCgUICgAAAA==.Coldslayer:BAAANQAECgQIBwAAAA==.Coldsteeldx:BAAANQADCgUIBQAAAA==.Copy:BAAANQAECgEIAgAAAA==.Corpha:BAAANQADCgUIBQABNQAECggIGAAGAKQeAA==.Cozbysuite:BAAANQADCgIIAgAAAA==.',
Cr='Crackzap:BAAANQAECgEIAQAAAA==.Crazyrd:BAAANQAECgQIBgAAAA==.Crotgustus:BAAANQADCgMIBQAAAA==.Crumblebump:BAAANQADCgcIEwAAAA==.Crummbly:BAAANQADCgYIDwAAAA==.',
Cy='Cyndelle:BAAANQADCgYIFgAAAA==.Cyntaria:BAAANQADCgcIFgAAAA==.Cyriz:BAAANQAECgIIAgAAAA==.',
Da='Dagarim:BAAANQAECgEIAQAAAA==.Daienne:BAAANQAECgIIAgAAAA==.Danamor:BAAANQAECgUICAAAAA==.Dandanx:BAAANQADCgUICgABNQAECgQIBwABAAAAAA==.Daplug:BAAANQADCggIEAAAAA==.Darkbrand:BAAANQAECgYICAAAAA==.Darkladÿ:BAAANQADCgMIAwAAAA==.Darnel:BAAANQAECgQICAAAAA==.Darnogden:BAAANQADCgUIBQAAAA==.Darnokk:BAAANQADCgcIGQAAAA==.',
De='Deathbreaker:BAAANQADCgIIAgAAAA==.Deathbyfel:BAAANQADCgcIDAABNQAECgMIBQABAAAAAA==.Deathbyshock:BAAANQAECgMIBQAAAA==.Deathrollins:BAAANQADCggIGQAAAA==.Delaror:BAAANQADCgYIBgAAAA==.Denadin:BAAANQAECgEIAgAAAA==.Denari:BAAANQABCgEIAQAAAA==.Dennygrips:BAAANQADCggIDQAAAA==.Dennyshreds:BAAANQAECgQIBwAAAA==.Denrukhan:BAABNQAECoEaAAMHAAkJOyGLBAAdAwAHAAkJOyGLBAAdAwAIAAEJDh0AAAAAAAAAAA==.Deschain:BAAANQADCgUIEgAAAA==.Dew:BAAANQAECgcIDgAAAA==.',
Di='Diin:BAAANQAECgMIAwAAAA==.',
Dk='Dklord:BAAANQAECgEIAQAAAA==.',
Do='Donappletino:BAAANQADCgYIBgAAAA==.Donkedixlol:BAAANQADCgcICwAAAA==.Doobzers:BAAANQADCgMIAwABNQAECgYIDQABAAAAAA==.Doxtorbrujo:BAAANQADCggICAABNQAECgUIDAABAAAAAA==.Doxtorele:BAAANQADCgQIBAABNQAECgUIDAABAAAAAA==.Doxtorprote:BAAANQAECgUIDAAAAA==.Doxtorunholy:BAAANQAECgIIAgABNQAECgUIDAABAAAAAA==.',
Dr='Dredd:BAAANQADCgUIBQAAAA==.Drunk:BAAANQAECgYIDwAAAA==.',
Du='Duckpally:BAAANQABCgYIBgAAAA==.',
Dw='Dwarfussy:BAAANQAECgUIBgAAAA==.',
Ea='Earthernheal:BAAANQADCgcIEwAAAA==.',
Ec='Eckshin:BAAANQADCggICAAAAA==.',
Ed='Edroffert:BAAANQADCgQIBAAAAA==.',
Eh='Ehonte:BAAANQAECgUICwAAAA==.',
Ei='Eidolonn:BAAANQADCgUICgAAAA==.',
Ek='Ekkaia:BAAANQAECgUICQAAAA==.',
El='Eleminohpee:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.Elfypriestly:BAAANQADCgUIBwAAAA==.Elsell:BAAANQAECgEIAQAAAA==.Elwasp:BAAANQADCgcICwAAAA==.',
En='Encana:BAAANQAECgYIDQAAAA==.Ender:BAAANQADCgYIFgAAAA==.',
Ep='Epiales:BAAANQADCgUIBQAAAA==.',
Er='Ericgb:BAABNQAECoEeAAMJAAgJ+BFYCADqAQAJAAgJ+BFYCADqAQAKAAEJPANpHQAxAAAAAA==.Eronara:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.Errzza:BAAANQADCgcIGQAAAA==.Erzsébet:BAAANQAECgEIAwAAAA==.',
Es='Esha:BAAANQADCgUICQAAAA==.',
Et='Etsupriest:BAAANQAECgcIEAAAAA==.',
Eu='Eula:BAAANQADCgUIBQAAAA==.',
Ev='Evelynn:BAAANQAECgQIBAAAAA==.Evoked:BAAANQAECgQIBAAAAA==.',
Ex='Exanimus:BAAANQADCgUICAAAAA==.Exign:BAAANQADCgIIAgAAAA==.Exqui:BAAANQAECgUICQAAAA==.',
Ez='Ezral:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
['Eí']='Eíko:BAAANQAECggIDwAAAA==.',
Fa='Faeruh:BAAANQADCggICQAAAA==.Fafnar:BAAANQADCgcIDAABNQAECgQICAABAAAAAA==.Fafnie:BAAANQAECgQIBQAAAA==.',
Fe='Felath:BAAANQAECgQIBwAAAA==.Feldspar:BAAANQAECgQIBAAAAA==.',
Fi='Fil:BAAANQAECgQIBwAAAA==.Fishswife:BAAANQAECgEIAQAAAA==.Fissal:BAAANQADCgcIBwAAAA==.Fistoflurry:BAAANQADCgIIAgABNQAECgQICQABAAAAAA==.',
Fl='Flameviper:BAAANQADCgcIFgAAAA==.Flompy:BAAANQADCgIIAgAAAA==.',
Fo='Foofighter:BAAANQADCgIIAgAAAA==.Footoo:BAAANQADCgcIGAAAAA==.Foxybrie:BAAANQABCgIIAgAAAA==.',
Fr='Franksuba:BAAANQADCgMIBQAAAA==.Friedchimkin:BAAANQADCggICAAAAA==.Frort:BAAANQADCgMIAwAAAA==.',
Fu='Fuknord:BAAANQADCgYIBwAAAA==.Fulva:BAAANQADCgcIBgAAAA==.',
Fy='Fyneep:BAAANQAECgQIBwAAAA==.Fynne:BAABNQAECoEWAAILAAcJyhbONADKAQALAAcJyhbONADKAQAAAA==.',
Ga='Gaiusmohiam:BAAANQABCgQIBAAAAA==.Galdademon:BAAANQADCggIDAAAAA==.Galiophobia:BAAANQADCgYICwAAAA==.Galm:BAAANQADCgUIBQAAAA==.Garrethul:BAAANQAECgMIBgAAAA==.Gawleywood:BAAANQADCgcIGQAAAA==.',
Ge='Gellidus:BAAANQAECgUICQAAAA==.Genhooves:BAEANQADCgYICwABNQAECgcIEQABAAAAAA==.Gensisd:BAAANQAECgQICAAAAA==.Gentleshadow:BAAANQAECgMIAwAAAA==.Gerulf:BAAANQABCgQIBAAAAA==.',
Gh='Ghosteagle:BAAANQADCgQIBAAAAA==.Ghostvoid:BAAANQABCgYICgAAAA==.',
Gn='Gnomejodas:BAAANQADCgYIBwAAAA==.',
Go='Gobfather:BAAANQADCgcIDAAAAA==.Goodfaith:BAAANQADCggIGgAAAA==.Goofy:BAAANQAFFAMIBAABNQAECgEIAQABAAAAAA==.',
Gr='Grimlocke:BAAANQAECgIIAgAAAA==.Grimsolo:BAAANQADCggIGAABNQAECgIIAgABAAAAAA==.Gromit:BAAANQAECgcIEAAAAA==.',
Gu='Gubber:BAAANQADCgIIAQAAAA==.',
Gw='Gwyndolin:BAAANQADCgcIDQAAAA==.Gwynne:BAAANQAECgEIAQAAAA==.',
Ha='Halanad:BAAANQAECgEIAQAAAA==.Halfmoons:BAAANQAECgQICwAAAA==.Halfsumo:BAAANQAECgMIAwAAAA==.Halobender:BAAANQADCggIEAAAAA==.Harrol:BAAANQAECgQICQABNQAECgQIBAABAAAAAA==.Hassindiir:BAAANQAECgYIDAAAAA==.Hawgelf:BAAANQAECgIIAgAAAA==.Hawmahcide:BAAANQADCgYIBgAAAA==.Hayles:BAAANQADCgYIEQAAAA==.',
He='Helathra:BAAANQAECgMIAwAAAA==.Hermonk:BAAANQAECgQICAABNQAECgkJGgAEAAgbAA==.',
Hi='Hiiru:BAAANQADCgcIBwABNQAECgYIDgABAAAAAA==.Hishunter:BAAANQAECgYICAABNQAECgkJIwAIAMUeAA==.',
Hu='Huntarr:BAAANQAECgEIAQAAAA==.Hunterdamon:BAAANQAECgUICQAAAA==.',
Hy='Hycinna:BAAANQADCgYICwAAAQ==.Hydrazashen:BAAANQADCgcIDAAAAA==.',
['Hà']='Hàou:BAAANQADCgYIBgAAAA==.',
Ia='Iamafish:BAAANQAECgQIBwAAAA==.',
Ig='Igotyou:BAAANQAECgQIBgAAAA==.',
In='Insidae:BAAANQAECgYICQAAAA==.',
Ir='Ironpunch:BAAANQADCggICQAAAA==.',
Is='Ismirea:BAAANQADCggIDQAAAA==.Isoldella:BAAANQADCgYIBgAAAA==.',
Ja='Jalencarter:BAAANQAECgUICQAAAA==.Jamirprote:BAAANQAECgEIAQAAAA==.Jantasir:BAAANQAECgMIAwAAAA==.Javalyn:BAAANQADCgcIDwAAAA==.',
Ji='Jinda:BAAANQADCgUIDwAAAA==.Jirachi:BAAANQAECgYIBgABNQAFFAUICwAMANgHAA==.Jiu:BAAANQAECgMIAwAAAA==.',
Jo='Jobergas:BAAANQADCgcIFAAAAA==.Jobi:BAAANQAECgMIBAAAAA==.Johallas:BAAANQAECgUICQAAAA==.',
Ju='Judzia:BAAANQAECgMIAwAAAA==.Juf:BAAANQAECgUIBwAAAA==.Jumpingbear:BAABNQAECoEhAAIKAAkJ6iDSAQA9AwAKAAkJ6iDSAQA9AwAAAA==.Justdeadfred:BAAANQADCggICAAAAA==.',
Ka='Kagar:BAAANQADCgMIAwAAAA==.Kaho:BAAANQAECgUICQAAAA==.Kainazzo:BAAANQADCgYIFAAAAA==.Kaladorn:BAAANQADCgcIAgAAAA==.Kaladïn:BAAANQADCgUIBQABNQAECgIIAwABAAAAAA==.Kalda:BAAANQAECgYIEQAAAA==.Kalikali:BAAANQABCgIIAgABNQAECgEIAgABAAAAAA==.Kallisto:BAAANQAECgIIAgAAAA==.Kamiarashi:BAAANQADCgIIAgAAAA==.Kattizzi:BAAANQADCgMIAwAAAA==.Kazuhiro:BAABNQAECoEcAAINAAkJayQZAwDMAwANAAkJayQZAwDMAwAAAA==.',
Ke='Keadath:BAAANQADCggIBwAAAA==.Keagan:BAAANQAECgEIAQAAAA==.Kehzai:BAAANQAECgEIAQAAAA==.Kelric:BAAANQADCgUIBQAAAA==.Kenpomaster:BAAANQADCgcIGgAAAA==.Keyalastus:BAAANQADCgQIBAAAAA==.',
Kh='Khaluha:BAAANQADCgcIEgAAAA==.Khaymaan:BAAANQADCggIDwAAAA==.',
Ki='Kilmeawden:BAAANQAECgMIBwAAAA==.',
Kr='Krisha:BAAANQAECgYIDAAAAA==.Krisphobos:BAAANQAECgMIAwAAAA==.',
Ku='Kubael:BAAANQAECgEIAQAAAA==.Kulgutbuster:BAAANQAECgQICAAAAA==.Kungpow:BAAANQAECgIIAgAAAA==.Kupdor:BAAANQAECgMIAwAAAA==.Kuromatsu:BAAANQAECgQIBgAAAA==.',
['Kÿ']='Kÿt:BAAANQAECgUICQAAAA==.',
La='Lantank:BAAANQABCgIIAgAAAA==.Larceny:BAAANQAECgEIAgAAAA==.Larfleeze:BAAANQADCgYIBgAAAA==.Layliah:BAABNQAECoEfAAIIAAkJrCIHCABbAwAIAAkJrCIHCABbAwAAAA==.',
Le='Leiania:BAAANQADCgUIBQABNQAECgcIEgABAAAAAA==.Lewis:BAAANQADCggICAAAAA==.',
Li='Lild:BAAANQADCgYICQAAAA==.Liqudblu:BAAANQADCgYICQAAAA==.Lishan:BAAANQAECgQIBAAAAA==.Liszandera:BAAANQAECgQIAgAAAA==.Literein:BAAANQAECgMIBQAAAA==.Lizora:BAAANQAECgYIBgAAAA==.',
Lo='Lokisan:BAAANQADCgMIAwAAAA==.Lorenei:BAAANQAECgQIBQAAAA==.Los:BAAANQADCgcIDQAAAA==.',
Lt='Ltwhisker:BAAANQAECgIIAwAAAA==.',
Lu='Lucìd:BAAANQADCgYIBgAAAA==.Lucïd:BAAANQAECgQIBgAAAA==.Lunhzae:BAAANQADCgUIBQAAAA==.Lustallo:BAAANQADCgQIBAAAAA==.',
Ly='Lynxx:BAAANQADCgcIEwAAAA==.',
Ma='Macharth:BAAANQAECgMIBQAAAA==.Mack:BAAANQAECgEIAQAAAA==.Mad:BAAANQAECgUICAAAAA==.Madchickenz:BAAANQAECgQIBwAAAA==.Magicwithin:BAAANQAECgQICAAAAQ==.Magut:BAAANQADCgUICAAAAA==.Maira:BAAANQADCgYIFgAAAA==.Maitias:BAAANQADCgUIBQABNQABCgQIBAABAAAAAA==.Majim:BAAANQADCggIEgAAAA==.Malevolens:BAAANQADCgcIFQAAAA==.Mannyfingers:BAAANQADCgUIBQAAAA==.Marche:BAAANQAECgUICQAAAA==.Marianacross:BAAANQAECgEIAQAAAA==.Marsel:BAAANQADCgYIBgAAAA==.Masokist:BAAANQADCgYIBgAAAA==.Mavdk:BAAANQADCggIDgABNQAECgQICAABAAAAAA==.Mavrar:BAAANQAECgQICAAAAA==.',
Mc='Mcflurrey:BAAANQAECgEIAgAAAA==.',
Me='Mechamana:BAAANQADCgYIBgABNQADCgYIBwABAAAAAA==.Melodrama:BAAANQADCgIIAgAAAA==.Meowrian:BAAANQADCgUIAgAAAA==.Mephïsto:BAAANQAECgEIAQAAAA==.Mereoleona:BAAANQAECgcIEQAAAA==.Messdupllama:BAABNQAECoEXAAIOAAgJfybgAwCUAwAOAAgJfybgAwCUAwAAAA==.Metamorfasis:BAAANQAECgQIBgAAAA==.',
Mi='Micos:BAAANQADCggICAAAAA==.Microburst:BAAANQAECgQIBQAAAA==.Microcharge:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.Miischief:BAAANQADCgYIEgAAAA==.Milkman:BAAANQADCggIFAAAAA==.Misslynn:BAAANQAECgQIBAAAAA==.Missmoodý:BAAANQADCggIGAAAAA==.Missqwerty:BAAANQAECgEIAQAAAA==.Mizari:BAAANQABCgEIAQAAAA==.',
Mo='Moltenbeast:BAAANQAECgUIAwABNQAECggIBgABAAAAAA==.Mongargiss:BAAANQAECgEIAQAAAA==.Montaro:BAAANQADCgcIGQAAAA==.Morbidi:BAAANQADCgcIDgAAAA==.Mortharos:BAAANQAECgMIBQAAAA==.',
Mu='Mudkip:BAACNQAFFIELAAIMAAUJ2Ac9AgCFAQAMAAUJ2Ac9AgCFAQA1AAQKgSIAAgwACQmYIJoEAGQDAAwACQmYIJoEAGQDAAAA.Munnsta:BAAANQAECgQIBgAAAA==.',
My='Mylanara:BAAANQAECgUICQAAAA==.Mysticah:BAAANQADCgcIFgAAAA==.Mythalagos:BAAANQADCgEIAQAAAA==.Mythblast:BAAANQAECgEIAgAAAA==.Myvrth:BAAANQAECgEIAQAAAA==.',
['Mä']='Märs:BAABNQAECoEjAAIIAAkJxR63CgA0AwAIAAkJxR63CgA0AwAAAA==.',
Na='Naelu:BAAANQADCgMIAwAAAA==.Nanr:BAAANQAECgUICQAAAA==.Nathi:BAAANQAECgEIAQAAAA==.Navori:BAABNQAECoEVAAIPAAgJuxcWEQAjAgAPAAgJuxcWEQAjAgAAAA==.Nazeraz:BAAANQAECgIIAwAAAA==.',
Ne='Necrokinesis:BAAANQAECgEIAQAAAA==.Nerve:BAAANQAECgYIDAAAAA==.Nesiryn:BAAANQADCgYICgAAAA==.Neth:BAAANQAECgMIBAAAAA==.Neuroshots:BAAANQAECgIIAgAAAA==.Newkers:BAAANQADCgUICQAAAA==.',
Ni='Nightknight:BAAANQADCgQIBwAAAA==.Nightràven:BAAANQAECgUICwAAAA==.Nimrodd:BAAANQAECgEIAQAAAA==.',
No='Nobby:BAAANQADCgUICgAAAA==.Noogan:BAAANQADCgYIBgAAAA==.Nosferatü:BAAANQADCgUIBQAAAA==.Nothotdog:BAAANQADCgIIAgAAAA==.Novacat:BAABNQAECoEZAAIHAAcJeCHeCQCaAgAHAAcJeCHeCQCaAgAAAA==.Novangel:BAAANQADCgYIBgAAAA==.November:BAAANQAECgMIAwAAAA==.Nox:BAAANQADCggIDAAAAA==.',
Nu='Nubriss:BAAANQAECgIIAgAAAA==.Nudetayne:BAAANQADCgQIBAAAAA==.Nuitsguard:BAABNQAECoEXAAQQAAgJuxXaLAALAgAQAAgJuxXaLAALAgARAAUJhgxcEgBUAQAGAAEJWw19uwAyAAAAAA==.Nunnaly:BAAANQADCggICAAAAA==.',
Ny='Nyaboron:BAAANQAECgUICAAAAA==.',
['Nè']='Nèaner:BAAANQAECgYIDAAAAA==.',
Og='Oggden:BAAANQAECgEIAgAAAA==.Ogrebane:BAAANQAECgQICAAAAA==.',
Oi='Oiheg:BAAANQAECgUICQAAAA==.',
Pa='Pajamasniper:BAAANQAECgQICAAAAA==.',
Pe='Peach:BAAANQAECgQICAAAAA==.',
Ph='Photos:BAAANQAECgQIBgAAAA==.',
Pi='Pigums:BAAANQAECgUIBwAAAA==.',
Pl='Pluug:BAAANQAECgIIAgAAAA==.',
Po='Poleo:BAAANQADCggICAAAAA==.',
Pr='Prayer:BAAANQAECgUICQABNQADCgcIBwABAAAAAA==.Prîde:BAAANQADCgYIBwAAAA==.',
Ps='Psycopath:BAAANQAECgYICwAAAA==.Psygn:BAAANQADCgUIBQABNQAECgQICAABAAAAAA==.Psyloc:BAAANQADCgcIBwABNQAECgQICAABAAAAAA==.',
Pt='Ptra:BAAANQAECgQIBwABNQAECgcIEgABAAAAAA==.',
Pu='Puddingfarts:BAAANQADCgcIBwAAAA==.Pumpy:BAABNQAECoEZAAIGAAkJUyH8BwBsAwAGAAkJUyH8BwBsAwAAAA==.',
Py='Pywacket:BAAANQAECgEIAgAAAA==.',
['Pã']='Pãlàdoom:BAAANQADCgMIBgABNQAECgUICwABAAAAAA==.',
Qu='Quendwings:BAEANQAECgUIBQABNQAECgkJJQAHAJogAA==.',
Ra='Rabern:BAAANQADCgIIAgAAAA==.Rainsky:BAAANQAECgEIAQAAAA==.Rasmatazz:BAAANQADCgIIAgAAAA==.Rayleighh:BAAANQAECgYIEAAAAA==.',
Re='Redemptio:BAAANQAECgQIBAAAAA==.',
Ri='Rikaza:BAAANQADCgcIBgAAAA==.Ristraza:BAAANQADCgIIAgABNQAECgIIBQABAAAAAA==.',
Ro='Roguewølf:BAAANQADCgQIBgAAAA==.Roono:BAAANQADCgcICgAAAA==.Rosalidia:BAAANQAECgIIAwAAAA==.Rosephane:BAAANQADCgUIBQAAAA==.Rossco:BAAANQAECgEIAQAAAA==.Rozzluz:BAAANQAECgYICwAAAA==.',
Ru='Rutira:BAAANQAECgYIDAAAAA==.',
Ry='Ryân:BAAANQADCgMIAwAAAA==.',
Sa='Sabbat:BAAANQADCgUIBQAAAA==.Sapphiwrath:BAAANQADCgYIDgAAAA==.',
Sc='Scuuzemee:BAAANQADCgEIAQAAAA==.',
Se='Seacow:BAAANQADCggIDgAAAA==.Searilus:BAAANQADCgcIGAAAAA==.Seethed:BAAANQADCgUICgAAAA==.Selyana:BAAANQADCggICAAAAA==.Seylena:BAAANQADCgcIEQABNQAECgQICAABAAAAAA==.',
Sh='Shadowcrit:BAAANQAECgMIAwAAAA==.Shamamma:BAAANQADCgIIAgAAAA==.Shammallamma:BAAANQABCgQIBgAAAA==.Shamæn:BAAANQADCgcIDgAAAA==.Shaphyr:BAAANQAECgMIAwABNQAECgQIBwABAAAAAA==.Sharphammer:BAAANQADCgUICAAAAA==.Shieldon:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.Shikamarú:BAAANQADCgEIAQAAAA==.Shinhealer:BAAANQAECgEIAQAAAA==.Shiroa:BAAANQADCgUIBQABNQAECgEIAwABAAAAAA==.Shootsahlot:BAAANQADCgYIEQAAAA==.',
Si='Sidapa:BAAANQADCgYICgAAAA==.Silvernleaf:BAAANQADCgYIFgAAAA==.Sinai:BAAANQAECgQIBAAAAA==.Sindir:BAAANQADCgUIBQABNQAECgkJGgAHADshAA==.Siyx:BAAANQADCgYIBgAAAA==.',
Sk='Skept:BAAANQAECgUIBwAAAA==.',
Sl='Sleêp:BAAANQAECgEIAQAAAA==.Slosh:BAAANQAECgUICgAAAA==.',
Sm='Smellyandfat:BAEBNQAECoElAAMHAAkJmiAjAgBuAwAHAAkJmiAjAgBuAwAIAAgJOB5PEwDDAgAAAA==.Smerffy:BAAANQAECgQICAAAAA==.Smites:BAAANQADCgUICgABNQAECgQICAABAAAAAA==.',
So='Somehobo:BAAANQADCgIIAgAAAA==.Sonny:BAAANQAECgQIDAAAAA==.Sorshalynne:BAAANQADCgcIFQAAAA==.Soulhorror:BAAANQAECgUICQAAAA==.',
Sp='Spiritfire:BAAANQAECgEIAgAAAA==.Spitefury:BAAANQAECgMIBAABNQAECgYIDAABAAAAAA==.Spriggs:BAEANQAECgcIEQAAAA==.',
St='Starrfighter:BAAANQADCggICAABNQAECggIFwAQALsVAA==.Stepfather:BAAANQADCgIIAgAAAA==.Stepmother:BAAANQADCgIIAgAAAA==.Stillblade:BAAANQADCgIIAgABNQADCgYIBwABAAAAAA==.Stonedread:BAAANQADCgYICwAAAA==.Stormfodder:BAAANQABCgQIBAAAAA==.Stronker:BAAANQADCggICgAAAA==.',
Su='Sungmi:BAAANQAECgUICgAAAA==.Sunntzu:BAAANQAECgQICQAAAA==.',
Sw='Swindlle:BAAANQAECgMIAwAAAA==.',
Sy='Syber:BAAANQAECgcIDwAAAA==.Sympathy:BAAANQADCggIDQAAAA==.Symphonica:BAAANQAECgQICAAAAA==.Syreithis:BAAANQAECgEIAQAAAA==.',
['Sí']='Síd:BAAANQAECgYIDAAAAA==.',
Ta='Tacofighter:BAAANQAECgQIBgAAAA==.Taerielle:BAABNQAECoEcAAISAAgJrBx9AgCeAgASAAgJrBx9AgCeAgAAAA==.Tageren:BAAANQADCgYICgAAAA==.Taldim:BAAANQADCgUIBQABNQAECgQICAABAAAAAA==.Taliah:BAAANQADCgcIBwAAAA==.Tarhos:BAAANQABCgIIBgAAAA==.Tarò:BAABNQAECoEhAAILAAkJDAsVMADnAQALAAkJDAsVMADnAQAAAA==.Taychi:BAAANQAECgIIAgABNQAECggIFgACAAgQAA==.',
Te='Teacupps:BAABNQAECoEXAAMTAAkJhh1qDgDqAQAUAAcJfhoGMAAYAgATAAcJHhZqDgDqAQAAAA==.Teegan:BAAANQAECgQIBAAAAA==.Tekloa:BAAANQADCgUIBQAAAA==.Telvissra:BAAANQAECgcIEgAAAA==.Temporary:BAAANQADCgYIBgAAAA==.Teoritta:BAAANQAECgYIDwAAAA==.Terrisher:BAAANQAECgQICAAAAA==.',
Th='Thaljadrak:BAAANQADCgQIBwAAAA==.Thermopalea:BAAANQADCgUICgAAAA==.Thetamoon:BAAANQAECgQICAAAAA==.Thorald:BAAANQAECgIIAwAAAA==.Thorggon:BAAANQAECgQICQAAAA==.Thornbeast:BAAANQAECgEIAgAAAA==.Thuato:BAAANQADCgQICAAAAA==.Thundermayne:BAAANQADCggIDwAAAA==.Thád:BAAANQAECgMIAwAAAA==.',
Ti='Tiranoc:BAAANQADCgUIBQABNQAECgQICAABAAAAAA==.',
To='Tojara:BAAANQADCgcIBwAAAA==.Toxique:BAAANQADCgcIFgAAAA==.',
Tr='Travelocitee:BAAANQAECgIIAgAAAA==.Triskalyn:BAAANQAECgEIAQAAAA==.Trojanhorse:BAAANQADCggIIAAAAA==.Trokosan:BAAANQADCgUIBgAAAA==.Trustissues:BAAANQADCggIFgAAAA==.Try:BAACNQAFFIEKAAIRAAYJuxwcAABXAgARAAYJuxwcAABXAgA1AAQKgR0AAhEACQl9JnkAANEDABEACQl9JnkAANEDAAAA.Trybu:BAABNQAECoEfAAIFAAgJshrQOgCmAgAFAAgJshrQOgCmAgAAAA==.Tryiss:BAAANQADCggIFQAAAA==.',
Tt='Ttryss:BAAANQADCgUIBQAAAA==.',
Tu='Tubslumpkin:BAAANQAECgIIAgAAAA==.Tuketu:BAAANQAECgYIDQAAAA==.Turtlelord:BAAANQAECgYICwAAAA==.',
Ty='Tylarion:BAAANQAECgQIBAAAAA==.Tylendal:BAAANQAECgYIDgAAAA==.Tylenulz:BAAANQAECgQIBAAAAA==.Tylheras:BAAANQAECgcICwAAAA==.Tyliera:BAAANQADCgcICAAAAA==.Tylren:BAAANQAECgMIAwAAAA==.',
['Tà']='Tànya:BAAANQAECgMIAwAAAA==.',
Un='Unfàthømable:BAAANQADCggICAABNQAECgUICwABAAAAAA==.',
Ut='Uthercito:BAAANQADCggICQAAAA==.',
Va='Vallarath:BAAANQAECgEIAQAAAA==.Valtaran:BAAANQADCggIGgAAAA==.Valtarr:BAAANQAECgQICAAAAA==.Vampirism:BAAANQAECgUICAAAAA==.Vasira:BAAANQADCgcIFAAAAA==.Vaulthunter:BAAANQADCgcIEgAAAA==.',
Ve='Vecna:BAAANQADCgMIBQAAAA==.Veina:BAAANQAECgUIBQAAAA==.Veloril:BAAANQADCgcIDAAAAA==.Vethena:BAAANQADCgIIAgAAAA==.Vezahk:BAAANQADCgEIAQAAAA==.',
Vi='Vidu:BAAANQAECgQICAAAAA==.Vikas:BAAANQADCgYIBgAAAA==.Vivitrix:BAAANQADCggIGQAAAA==.Viví:BAAANQAECgQICwAAAA==.',
Vl='Vlm:BAAANQAECgMIAwAAAA==.',
Vo='Voidbreaker:BAAANQAECgYIBwABNQAECgYIEQABAAAAAA==.Vordis:BAAANQAECgQIBQAAAA==.Voxis:BAAANQADCggICQAAAA==.',
Vv='Vv:BAAANQAECgMIAwAAAA==.',
Vy='Vyrstal:BAAANQADCggICAABNQAECgYIDAABAAAAAA==.',
Wa='Wardan:BAAANQADCgUIBgAAAA==.',
We='Weavile:BAAANQADCgUIBQABNQAFFAUICwAMANgHAA==.Wef:BAAANQADCggIFgAAAA==.Weirdtotem:BAABNQAECoEYAAMGAAgJpB5nFQDQAgAGAAgJpB5nFQDQAgAQAAYJyx0/LgAEAgAAAA==.Westylad:BAAANQAECgYICgAAAA==.Wetrat:BAAANQAECgUIBQABNQAECgkJGQAGAFMhAA==.',
Wh='Whatthefunk:BAAANQADCgUIBgAAAA==.',
Wi='Winterfox:BAAANQADCgYICQAAAA==.Winters:BAAANQADCgMIAwAAAA==.',
Wr='Wrystal:BAAANQAECgYIDAAAAA==.',
Xe='Xernes:BAAANQADCgQIBAAAAA==.',
Xu='Xujian:BAAANQADCgcIFQAAAA==.',
Ya='Yakiki:BAAANQADCgcIBwABNQAECgkJJAAMAFolAA==.',
Za='Zaelenia:BAAANQAECgEIAgAAAA==.Zalen:BAAANQAECgUICQAAAA==.Zappylad:BAAANQAECgMIAwAAAA==.',
Ze='Zenamani:BAAANQAECgQIBAAAAA==.Zenetha:BAAANQAECgIIAwAAAA==.Zephyres:BAAANQAECggIDwABNQAECgkJHAANAGskAA==.Zerokool:BAAANQABCgYIBgABNQAECgIIAgABAAAAAA==.Zevarya:BAAANQAECgEIAQAAAA==.',
Zo='Zonksmoose:BAAANQADCgYIBgAAAA==.Zonkspaladin:BAABNQAECoEWAAIVAAgJZxmOHAB+AgAVAAgJZxmOHAB+AgAAAA==.Zornac:BAAANQADCgcIDQAAAA==.',
Zp='Zpyder:BAAANQAECgIIAgAAAA==.',
Zy='Zynskie:BAAANQAECgQICQAAAA==.Zyraa:BAAANQADCgIIAQAAAA==.',
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
