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

local lookup = {'Unknown-Unknown','Warrior-Protection','DemonHunter-Devourer','Hunter-BeastMastery','Evoker-Devastation','DeathKnight-Frost','DeathKnight-Blood','Mage-Arcane','Shaman-Elemental','Druid-Restoration','Druid-Balance','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','Druid-Feral','Priest-Holy','Warrior-Arms','Shaman-Enhancement','Priest-Shadow','DeathKnight-Unholy','Shaman-Restoration','Rogue-Assassination','Rogue-Subtlety','Mage-Frost','Warlock-Destruction','Warlock-Demonology','Paladin-Holy',}
local provider = {region='US',realm='Windrunner',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Accea:BAAANQADCgEIAQAAAA==.Acehobo:BAAANQADCgUIBQAAAA==.Acetaminofun:BAAANQAECgQJCgAAAA==.Actionjaxson:BAAANQAECgYJDgAAAA==.',
Ad='Adeathknight:BAAANQABCgIIAgAAAA==.Ademis:BAAANQAECgEIAQAAAA==.Admore:BAAANQAECgQJBwAAAA==.',
Ae='Aeriith:BAAANQAECggIEwAAAA==.Aethmourne:BAAANQADCgMIAwAAAA==.',
Ag='Agameden:BAAANQAECgMJBQAAAA==.Agogg:BAAANQADCgcIDAAAAA==.Agronak:BAAANQABCgIIAgAAAA==.',
Ah='Ahsina:BAAANQABCgUIBQAAAA==.',
Ai='Aintnosecret:BAAANQAECgMIAwAAAA==.Aishi:BAAANQAECgQICgAAAA==.',
Ak='Akaya:BAAANQAECgQJBQABNQAECgcJEQABAAAAAA==.Akitsuki:BAAANQADCgUIBQAAAA==.',
Al='Algy:BAAANQADCgIJAgAAAA==.Alillara:BAAANQADCgIIAgAAAA==.Alivron:BAAANQAECgYJDwAAAA==.Alkoren:BAAANQAECgQJBAABNQAECggJGQACAE4cAA==.Alkorin:BAABNQAECoEZAAICAAgKThwIBgCXAgACAAgKThwIBgCXAgAAAA==.Allestra:BAABNQAECoEnAAIDAAkKFxy3CQAXAwADAAkKFxy3CQAXAwAAAA==.',
Am='Amaranthine:BAAANQADCgYIBgAAAA==.Amoxil:BAAANQADCggIIQAAAA==.',
An='Anasztaizia:BAEANQAECgEJAQAAAA==.Andorin:BAABNQAECoEZAAIEAAgKvBcAMQBvAgAEAAgKvBcAMQBvAgAAAA==.Andwin:BAAANQADCggJCAAAAA==.Anorah:BAAANQAECgEIAQAAAA==.Anunitu:BAAANQAECgYIDgAAAA==.',
Ao='Aoibheann:BAAANQAECgMIBgAAAA==.',
Ar='Arath:BAABNQAECoEYAAIFAAgKHxNWDgAkAgAFAAgKHxNWDgAkAgAAAA==.Arcath:BAAANQAECgYJEQAAAA==.Arcona:BAAANQAECgIJAgAAAA==.Aristus:BAAANQADCgYJCgAAAA==.Arthuel:BAAANQADCgIIAgAAAA==.',
As='Asar:BAAANQAECgEIAgAAAA==.Ashlanni:BAAANQADCgIIAwAAAA==.Asiaminor:BAAANQADCgMIBQAAAA==.Astora:BAAANQADCgcIBwAAAA==.',
At='Athuzad:BAAANQAECgYJDgAAAA==.',
Au='Auroraalysia:BAAANQADCgYICwAAAA==.Auroran:BAAANQAECgYIEAAAAA==.Autumnmoon:BAAANQAECgYJDAAAAA==.',
Av='Aviendah:BAAANQADCgYICgAAAA==.Avrilenv:BAAANQAECgEIAQAAAA==.',
Ay='Ayeroh:BAAANQADCgcIHQAAAA==.',
Az='Azenet:BAAANQADCgYIBgAAAA==.',
Ba='Badoink:BAAANQADCggJCAABNQAECgYIDgABAAAAAA==.Bakasaura:BAAANQADCgYICwABNQAECgYIEAABAAAAAA==.Balorous:BAAANQAECgYIDAAAAA==.Bansheelen:BAAANQAECgYIEAAAAA==.Banthis:BAAANQAECgcJEgAAAA==.Barkcamon:BAAANQAECgcIEwAAAA==.Barmaak:BAAANQAECgEIAQAAAA==.Barrand:BAAANQADCggJCAABNQAECgQJBgABAAAAAA==.Barthelo:BAAANQAECgYJDgAAAA==.Bassandi:BAAANQADCgEIAQABNQAECgYIEAABAAAAAA==.Baxdock:BAAANQAECgMJBAAAAA==.Baxideath:BAAANQAECgUICAAAAA==.',
Be='Beastylad:BAAANQADCgEJAQAAAA==.Beefcâke:BAAANQADCgYIBgAAAA==.Bekahroo:BAAANQADCgYJFQABNQAECgQJBAABAAAAAA==.Bekahsama:BAAANQAECgQJBAAAAA==.Belcron:BAAANQADCgYJEAAAAA==.Beld:BAAANQADCgYJBgAAAA==.Beldaran:BAAANQAECgEJAQAAAA==.Belladawna:BAAANQAECgYJDgAAAA==.Belldândy:BAAANQAECgEJAQAAAA==.Bernal:BAAANQAECgIJAgAAAA==.',
Bh='Bhature:BAAANQADCgMIAwAAAA==.',
Bi='Bigmapletree:BAAANQAECgUICQAAAA==.Bigëmu:BAAANQADCgYIGgAAAA==.Billyidols:BAAANQADCgEIAQAAAA==.Bingbangpów:BAAANQAECgIJAgAAAA==.',
Bl='Blackblader:BAAANQADCgcJFQAAAA==.Blarus:BAAANQADCgIIAgAAAA==.Bluecat:BAAANQAECgUIBQAAAA==.Blueplanet:BAAANQAECgYIEAAAAA==.',
Bo='Boarggon:BAAANQADCgEIAQABNQAECggIEQABAAAAAA==.Boherwin:BAAANQAECgYIDAAAAA==.Bonnie:BAAANQAECgMIAwAAAA==.Borealus:BAAANQAECgYICwAAAA==.',
Br='Bratakwar:BAAANQADCggICAAAAA==.Bris:BAAANQAECgUJDQAAAA==.Bruby:BAAANQAECgQJBQAAAA==.Bruceleelad:BAAANQADCgYIBgAAAA==.Brugamen:BAAANQAECgYJEAABNQAECgYIEAABAAAAAA==.Brugg:BAAANQAECgYIEAAAAA==.Brynnu:BAAANQADCgIIAgAAAA==.Brád:BAAANQAECgUICAAAAA==.',
Bu='Bunnylajoya:BAAANQADCgYICwAAAA==.Burgerz:BAAANQADCggJGwAAAA==.Busblaster:BAAANQAECgYIEAAAAA==.',
['Bä']='Bäldur:BAAANQAECgEIAQAAAA==.',
Ca='Calestel:BAAANQADCgIIAgAAAA==.Careßear:BAAANQAECgEIAQAAAA==.Carielle:BAAANQADCgcJEgAAAA==.Carodd:BAABNQAECoElAAIGAAkKrR9ICAAnAwAGAAkKrR9ICAAnAwAAAA==.',
Ce='Cedaver:BAAANQAECgYJDQAAAA==.Ceez:BAAANQADCgYIBwAAAA==.Celtigar:BAAANQAECgEJAQAAAA==.',
Ch='Chaan:BAAANQAECgEIAgAAAA==.Chaddicus:BAAANQADCggJGwAAAA==.Chainna:BAAANQADCggIEAAAAA==.Chanlin:BAABNQAECoEXAAIHAAkKmh4wDwD1AgAHAAkKmh4wDwD1AgAAAA==.Chateau:BAAANQAECgEIAQAAAA==.Chauda:BAAANQADCgcICwABNQAECgcJEQABAAAAAA==.Chazbot:BAAANQADCgYIBgAAAA==.Chereth:BAAANQAECgIJAgAAAA==.Cheshire:BAAANQAECgYIEwAAAA==.Chestystab:BAAANQADCggIEgAAAA==.Chezpuff:BAAANQADCgEIAQAAAA==.Chill:BAAANQAECgYIDAAAAA==.Chlorin:BAAANQAECgYJEAAAAA==.Chocolate:BAACNQAFFIEEAAIIAAMKDxWnFgAMAQAIAAMKDxWnFgAMAQA1AAQKgRoAAggACQooIBgvAAEDAAgACQooIBgvAAEDAAAA.',
Cl='Cloudcrasher:BAAANQADCgYICgAAAA==.Cloudsayer:BAAANQAECgIJAwAAAA==.Cloudspeaker:BAAANQAECgYIEAAAAA==.',
Co='Coldblades:BAAANQADCgYJBgAAAA==.Coldfrostshk:BAAANQADCgUICgAAAA==.Coldslayer:BAAANQAECgYJDQAAAA==.Coldsteeldx:BAAANQADCgUIBQAAAA==.Copy:BAAANQAECgQJBQAAAA==.Corpha:BAAANQADCgUJBQABNQAECgkJHgAJAE8eAA==.Cozbysuite:BAAANQADCgIJAgAAAA==.',
Cr='Crackzap:BAAANQAECgEIAQAAAA==.Crazyrd:BAAANQAECgUICQAAAA==.Crotgustus:BAAANQADCgMIBQAAAA==.Crumblebump:BAAANQAECgIJAgAAAA==.Crummbly:BAAANQADCgYIDwAAAA==.',
Cy='Cyndelle:BAAANQADCgYIHAAAAA==.Cyntaria:BAAANQADCgcJHQAAAA==.Cyriz:BAAANQAECgIJBAAAAA==.',
Da='Dagarim:BAAANQAECgEIAQAAAA==.Daienne:BAAANQAECgUIBwAAAA==.Danamor:BAAANQAECgUIDQAAAA==.Dandanx:BAAANQADCgcJEAABNQAECgYJDQABAAAAAA==.Daplug:BAAANQADCggIEAAAAA==.Dariann:BAAANQADCgYIBgAAAA==.Darkbrand:BAAANQAECgYIDgAAAA==.Darkladÿ:BAAANQADCgMIAwAAAA==.Darnel:BAAANQAECgYJDgAAAA==.Darnogden:BAAANQADCgUIBQAAAA==.Darnokk:BAAANQAECgIJAgAAAA==.',
De='Deathbreaker:BAAANQADCgYJCAAAAA==.Deathbyfel:BAAANQADCgcIDAABNQAECgUICgABAAAAAA==.Deathbyshock:BAAANQAECgUICgAAAA==.Deathrollins:BAAANQAECgEJAQAAAA==.Delaror:BAAANQADCgYIBgAAAA==.Denadin:BAAANQAECgEIAgAAAA==.Denari:BAAANQABCgMJAwAAAA==.Dennygrips:BAAANQADCggIDQAAAA==.Dennyshotz:BAAANQADCggICAAAAA==.Dennyshreds:BAAANQAECgQJCQAAAA==.Dennytotem:BAAANQADCgYIBwAAAA==.Denrukhan:BAACNQAFFIEFAAIKAAQKRBazAwBNAQAKAAQKRBazAwBNAQA1AAQKgRwAAwoACQpUIRIHAAcDAAoACQpUIRIHAAcDAAsAAQoOHQAAAAAAAAAA.Deschain:BAAANQADCgYJGAAAAA==.Dew:BAABNQAECoEbAAIJAAkKJBmpHQDAAgAJAAkKJBmpHQDAAgAAAA==.',
Di='Diin:BAAANQAECgQJBwAAAA==.',
Dk='Dklord:BAAANQAECgIJAwAAAA==.',
Do='Donappletino:BAAANQADCgYIBgAAAA==.Donkedixlol:BAAANQADCgcICwAAAA==.Doobzers:BAAANQADCgMIAwABNQAECgYJDQABAAAAAA==.Doxtorbrujo:BAAANQAECgUIBQABNQAECgcIEwABAAAAAA==.Doxtorele:BAAANQAECgIIAgABNQAECgcIEwABAAAAAA==.Doxtorprote:BAAANQAECgcIEwAAAA==.Doxtorunholy:BAAANQAECgIIAgABNQAECgcIEwABAAAAAA==.',
Dr='Draelgor:BAAANQADCgEJAQAAAA==.Dredd:BAAANQADCgcJDAAAAA==.Drunk:BAABNQAECoEYAAMMAAgK5g6OFACsAQAMAAgK5g6OFACsAQANAAIK5QqvPQBuAAAAAA==.',
Du='Duckpally:BAAANQABCgYIBgAAAA==.',
Dw='Dwarfussy:BAAANQAECgYICwAAAA==.',
Ea='Earthernheal:BAAANQAECgEJAQAAAA==.',
Ec='Eckshin:BAAANQADCggJCwAAAA==.',
Ed='Edroffert:BAAANQADCgQJBAAAAA==.',
Eh='Ehonte:BAAANQAECgYJEQAAAA==.',
Ei='Eidolonn:BAAANQADCgcJEAAAAA==.',
Ek='Ekkaia:BAAANQAECgYIDwAAAA==.',
El='Eleminohpee:BAAANQADCgMIAwABNQAECgYJCwABAAAAAA==.Elfypriestly:BAAANQADCgUIBwAAAA==.Elsell:BAAANQAECgEJAQAAAA==.Elwasp:BAAANQADCgcIEQAAAA==.',
Em='Emptypockets:BAAANQADCgQIBAAAAA==.',
En='Encana:BAAANQAECgYJEwAAAA==.Ender:BAAANQADCgYJHAAAAA==.',
Ep='Epiales:BAAANQADCgUIBQAAAA==.',
Er='Ericgb:BAABNQAECoEmAAMOAAgKmhPeCwDkAQAOAAgKmhPeCwDkAQAPAAEKPAO5JwApAAAAAA==.Eronara:BAAANQADCgIIAgABNQAECgUJCAABAAAAAA==.Errzza:BAAANQAECgIJAgAAAA==.Erutreya:BAAANQADCgcIBwAAAA==.Erzsébet:BAAANQAECgIJBQAAAA==.',
Es='Esha:BAAANQADCgYIDgAAAA==.',
Et='Etsubrew:BAAANQAECgcIBwAAAA==.Etsupriest:BAAANQAECgcIEAAAAA==.',
Eu='Eula:BAAANQADCgUIBQAAAA==.',
Ev='Evelynn:BAAANQAECgYICgAAAA==.Evoked:BAAANQAECgQJBgAAAA==.',
Ex='Exanimus:BAAANQADCgUJCAAAAA==.Exign:BAAANQADCgIJAgAAAA==.Exqui:BAAANQAECgYIDwAAAA==.',
Ez='Ezral:BAAANQAECgEJAQABNQAECgEIAQABAAAAAA==.',
['Eí']='Eíko:BAABNQAECoEYAAIQAAkKmRcHKABhAgAQAAkKmRcHKABhAgAAAA==.',
Fa='Faeruh:BAAANQADCggICQAAAA==.Fafnar:BAAANQADCgcIDAABNQAECgYJDgABAAAAAA==.Fafnie:BAAANQAECgQICQAAAA==.',
Fe='Felath:BAAANQAECgUICgAAAA==.Feldspar:BAAANQAECgYICgAAAA==.',
Fi='Fil:BAAANQAECgUIDAAAAA==.Fishswife:BAAANQAECgMIBAAAAA==.Fissal:BAAANQADCgcIBwAAAA==.Fistoflurry:BAAANQADCgIIAgABNQAECggIEQABAAAAAA==.',
Fl='Flameviper:BAAANQADCgcIHQAAAA==.Flompy:BAAANQADCgIIAgAAAA==.',
Fo='Foofighter:BAAANQADCgIIAgAAAA==.Footoo:BAAANQAECgIJAgAAAA==.Foxybrie:BAAANQABCgIIAgAAAA==.',
Fr='Franksuba:BAAANQADCgMIBQAAAA==.Friedchimkin:BAAANQADCggJDQAAAA==.Frort:BAAANQADCgYICQAAAA==.',
Fu='Fuknord:BAAANQADCgYIBwAAAA==.Fulva:BAAANQADCgcIBgAAAA==.',
Fy='Fyneep:BAAANQAECgUIDAAAAA==.Fynne:BAABNQAECoEcAAIQAAcKYBjJQADjAQAQAAcKYBjJQADjAQAAAA==.',
Ga='Gaiusmohiam:BAAANQABCgUIBQAAAA==.Galadriell:BAAANQADCgYJBgAAAA==.Galdademon:BAAANQAECgMJAwAAAA==.Galiophobia:BAAANQADCgYICwAAAA==.Galm:BAAANQADCgcJCwAAAA==.Garrethul:BAAANQAECgMIBgAAAA==.Gawleywood:BAAANQAECgIJAgAAAA==.',
Ge='Gellidus:BAAANQAECgYIDwAAAA==.Genhooves:BAEANQADCgYJCwABNQAECggIGQAIAFgXAA==.Gensisd:BAAANQAECgYIDgAAAA==.Gentledh:BAAANQADCgYIBgAAAA==.Gentleshadow:BAAANQAECgUICAAAAA==.Gerulf:BAAANQABCgQIBAAAAA==.',
Gh='Ghosteagle:BAAANQADCgQIBAAAAA==.Ghostvoid:BAAANQABCgYICgAAAA==.',
Gn='Gnomejodas:BAAANQADCgYIDQAAAA==.',
Go='Gobfather:BAAANQADCgcIDAAAAA==.Goodfaith:BAAANQAECgEJAQAAAA==.Goofy:BAACNQAFFIEKAAIRAAUK9xm0BgCtAQARAAUK9xm0BgCtAQA1AAQKgRcAAhEACQqGJO4LAHoDABEACQqGJO4LAHoDAAE1AAQKAggCAAEAAAAA.',
Gr='Grimlocke:BAAANQAECgUIBgAAAA==.Grimsolo:BAAANQADCggIGAABNQAECgUIBgABAAAAAA==.Gromit:BAAANQAECgcIEQAAAA==.',
Gu='Gubber:BAAANQADCgIIAQAAAA==.',
Gw='Gwyndolin:BAAANQAECgIJAgAAAA==.Gwynne:BAAANQAECgUJBgAAAA==.',
Ha='Halanad:BAAANQAECgEJAQAAAA==.Halfmoons:BAAANQAECgQIDgAAAA==.Halfsumo:BAAANQAECgQJBwAAAA==.Halobender:BAAANQADCggIGAAAAA==.Harrol:BAAANQAECgQICQABNQAECgQIBAABAAAAAA==.Hassindiir:BAAANQAECgcIEwAAAA==.Hawgelf:BAAANQAECgMJBAAAAA==.Hawmahcide:BAAANQADCgYJCAAAAA==.Hayles:BAAANQAECgIJAgAAAA==.',
He='Helathra:BAAANQAECgYICQAAAA==.Helliona:BAAANQADCggJCAAAAA==.Hermonk:BAAANQAECgQJCAABNQAECgkJIQAHADkdAA==.',
Hi='Hiiru:BAAANQADCgcIBwABNQAECggJGQACAE4cAA==.Hishunter:BAAANQAECgcIDgABNQAECgkJJQALAEogAA==.',
Ho='Hofin:BAAANQADCgQJBAAAAA==.',
Hu='Huntarr:BAAANQAECgYIBwAAAA==.Hunterdamon:BAAANQAECgYIDwAAAA==.',
Hy='Hycinna:BAAANQADCgYICwAAAQ==.Hydrazashen:BAAANQADCgcJDQAAAA==.',
['Hà']='Hàou:BAAANQADCgYICgAAAA==.',
Ia='Iamafish:BAAANQAECgUIDAAAAA==.',
Ic='Ichimaru:BAAANQADCgYJBgAAAA==.',
Ig='Igotyou:BAAANQAECgUICwAAAA==.',
In='Insidae:BAAANQAECgYJDwAAAA==.',
Ir='Ironpunch:BAAANQADCggICQAAAA==.',
Is='Ismirea:BAAANQAECgEJAQAAAA==.Isoldella:BAAANQADCgYIBgAAAA==.',
Ja='Jalencarter:BAAANQAECgUICQAAAA==.Jamirprote:BAAANQAECgUIBgAAAA==.Jantasir:BAAANQAECgMJBQAAAA==.Javalyn:BAAANQAECgIJAgAAAA==.',
Ji='Jin:BAAANQAECgcIBwABNQAFFAYICwASAB0eAA==.Jinda:BAAANQADCgUIFAAAAA==.Jirachi:BAAANQAECgcIDAABNQAFFAUIEAATAFIMAA==.Jiujitsu:BAAANQAECgYICQAAAA==.',
Jo='Jobergas:BAAANQADCgcIFAAAAA==.Jobi:BAAANQAECgMIBAAAAA==.Johallas:BAAANQAECgYIDwAAAA==.',
Ju='Judzia:BAAANQAECgMIAwAAAA==.Juf:BAAANQAECgYIDQAAAA==.Jufster:BAAANQADCggJCAAAAA==.Jumpingbear:BAABNQAECoEmAAMPAAkKFCHpAgAfAwAPAAkKFCHpAgAfAwALAAEKGBFbfwA5AAAAAA==.Justdeadfred:BAAANQADCggICAAAAA==.',
Ka='Kagar:BAAANQADCgMIAwAAAA==.Kaho:BAAANQAECgUICQAAAA==.Kainazzo:BAAANQADCggJHAAAAA==.Kaladorn:BAAANQADCgcJBQAAAA==.Kaladïn:BAAANQADCgUIBQABNQAECgIIBAABAAAAAA==.Kalda:BAAANQAECgYIEQAAAA==.Kalikali:BAAANQABCgIIAgABNQAECgEJAgABAAAAAA==.Kallisto:BAAANQAECgMJBAAAAA==.Kamiarashi:BAAANQADCggICgAAAA==.Karabethe:BAEANQAECgIJAQAAAA==.Kattizzi:BAAANQADCgMIAwAAAA==.Kazuhiro:BAACNQAFFIEIAAIRAAUKphvNBQDGAQARAAUKphvNBQDGAQA1AAQKgSUAAxEACQpyJXUDAMwDABEACQpYJXUDAMwDAAIAAgr6JZYbANwAAAAA.',
Ke='Keadath:BAAANQADCggIBwAAAA==.Keagan:BAAANQAECgIJAwAAAA==.Kehzai:BAAANQAECgUICwAAAA==.Kelric:BAAANQADCgUIBQAAAA==.Kenpomaster:BAAANQADCgcJHwAAAA==.Keyalastus:BAAANQADCgQIBAAAAA==.',
Kh='Khaluha:BAAANQAECgEJAQAAAA==.Khaymaan:BAAANQAECgQJBAAAAA==.',
Ki='Killios:BAAANQADCgUIAgAAAA==.Kilmeawden:BAAANQAECgUJDAAAAA==.',
Ko='Kozal:BAAANQABCgUIBQAAAA==.',
Kr='Krisha:BAAANQAECgcJEQAAAA==.Krisphobos:BAAANQAECgQJBgAAAA==.',
Ku='Kubael:BAAANQAECgEIAQAAAA==.Kuesham:BAAANQADCgUJBAABNQAECgEIAQABAAAAAA==.Kulgutbuster:BAAANQAECgYIDgAAAA==.Kungpow:BAAANQAECgUJBwAAAA==.Kupdor:BAAANQAECgQIBwAAAA==.Kuromatsu:BAAANQAECgUICwAAAA==.',
['Kÿ']='Kÿt:BAAANQAECgYJDwAAAA==.',
La='Lacedon:BAAANQAECgUIBQAAAA==.Lantank:BAAANQABCgIIAgAAAA==.Larceny:BAAANQAECgUIBwAAAA==.Larfleeze:BAAANQADCgYIBgAAAA==.Layliah:BAACNQAFFIEFAAILAAMKTiD6CQAqAQALAAMKTiD6CQAqAQA1AAQKgSMAAgsACQqII4sIAGcDAAsACQqII4sIAGcDAAAA.',
Le='Leiania:BAAANQADCgUIBQABNQAECgkJHQAUAGUYAA==.Lewis:BAAANQADCggICAAAAA==.',
Li='Lild:BAAANQADCgYICQAAAA==.Linedaleiris:BAAANQADCgcJBwAAAA==.Liqudblu:BAAANQAECgQIBAAAAA==.Lishan:BAAANQAECgQIBAAAAA==.Liszandera:BAAANQAECgQJBAAAAA==.Literein:BAAANQAECgUJCgAAAA==.Lizora:BAAANQAECgYICAAAAA==.',
Lo='Lokisan:BAAANQADCgMIAwAAAA==.Lorenei:BAAANQAECgYJBwAAAA==.Los:BAAANQAECgIJAgAAAA==.',
Lt='Ltwhisker:BAAANQAECgMIBgAAAA==.',
Lu='Lucìd:BAAANQADCgYIBgAAAA==.Lucïd:BAAANQAECgYICQAAAA==.Lunhzae:BAAANQADCgUIBQAAAA==.Lustallo:BAAANQADCgQIBAAAAA==.',
Ly='Lynxx:BAAANQAECgEIAQAAAA==.',
Ma='Macharth:BAAANQAECgMIBQAAAA==.Mack:BAAANQAECgcJBgAAAA==.Mad:BAAANQAECgYIDgAAAA==.Madchickenz:BAAANQAECgQICwAAAA==.Magicwithin:BAAANQAECgYIDgAAAQ==.Magut:BAAANQADCgUICAAAAA==.Maira:BAAANQADCgYIFgAAAA==.Maitias:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Majim:BAAANQAECgMIAwAAAA==.Malevolens:BAAANQADCgcIHAAAAA==.Mannyfingers:BAAANQADCgUIBQAAAA==.Marche:BAAANQAECgYIDwAAAA==.Marianacross:BAAANQAECgQJBAAAAA==.Marsel:BAAANQADCgYIBgAAAA==.Masokist:BAAANQADCgYIBgAAAA==.Mavdk:BAAANQADCggIDgABNQAECgQICAABAAAAAA==.Mavrar:BAAANQAECgQICAAAAA==.',
Mc='Mcflurrey:BAAANQAECgQIBgAAAA==.',
Me='Mechamana:BAAANQADCgYIBgABNQADCgYIBwABAAAAAA==.Meing:BAAANQAECgEIAQAAAA==.Melodrama:BAAANQADCgIIAgAAAA==.Meowrian:BAAANQADCgUJBQAAAA==.Mephïsto:BAAANQAECgEIAQAAAA==.Mereoleona:BAAANQAECgcIEQAAAA==.Messdupjuf:BAAANQADCggJCAABNQAECggIHQAEALgmAA==.Messdupllama:BAABNQAECoEdAAIEAAgKuCbwBACXAwAEAAgKuCbwBACXAwAAAA==.Metamorfasis:BAAANQAECgYIDAAAAA==.',
Mi='Micos:BAAANQADCggIDwAAAA==.Microburst:BAAANQAECgYJCwAAAA==.Microcharge:BAAANQADCgUIBQABNQAECgYJCwABAAAAAA==.Miischief:BAAANQAECgIJAgAAAA==.Milkman:BAAANQADCggIFAAAAA==.Misslynn:BAAANQAECgQJBQAAAA==.Missmoodý:BAAANQAECgEJAQAAAA==.Missqwerty:BAAANQAECgEIAQAAAA==.Mizari:BAAANQABCgEIAQAAAA==.',
Mo='Moltenbeast:BAAANQAECgUIAwABNQAECggIBgABAAAAAA==.Mongargiss:BAAANQAECgMIBAAAAA==.Mongoth:BAAANQADCgUIBQAAAA==.Montaro:BAAANQAECgIJAgAAAA==.Morbidi:BAAANQADCgcJFQAAAA==.Moreithe:BAAANQADCggICAAAAA==.Mortharos:BAAANQAECgMIBQAAAA==.',
Mu='Mudkip:BAACNQAFFIEQAAITAAUKUgy9AwCLAQATAAUKUgy9AwCLAQA1AAQKgS0AAhMACQpFIq8EAHQDABMACQpFIq8EAHQDAAAA.Munnsta:BAAANQAECgUJCwAAAA==.Muskan:BAAANQADCgYIBgAAAA==.',
My='Mylanara:BAAANQAECgYIDwAAAA==.Mysticah:BAAANQADCgcIHQAAAA==.Mythalagos:BAAANQADCgEIAQAAAA==.Mythblast:BAAANQAECgEJAgAAAA==.Myvrth:BAAANQAECgEIAQAAAA==.',
['Mä']='Märs:BAABNQAECoElAAILAAkKSiBIDQAxAwALAAkKSiBIDQAxAwAAAA==.',
Na='Naelu:BAAANQADCgMIAwAAAA==.Nanr:BAAANQAECgYIDwAAAA==.Nathi:BAAANQAECgEJAQAAAA==.Navori:BAACNQAFFIEFAAINAAQKoAUOBQAOAQANAAQKoAUOBQAOAQA1AAQKgRcAAg0ACApUGUMWABYCAA0ACApUGUMWABYCAAAA.Nazeraz:BAAANQAECgUJCAAAAA==.',
Ne='Necrokinesis:BAAANQAECgEJAQAAAA==.Nerve:BAAANQAECgcJEAAAAA==.Nesiryn:BAAANQADCgYICgAAAA==.Neth:BAAANQAECgYJCgAAAA==.Neuroshots:BAAANQAECgIJBAAAAA==.Newkers:BAAANQADCgUICQAAAA==.',
Ni='Nightknight:BAAANQADCgQIBwAAAA==.Nightràven:BAAANQAECgYJEQAAAA==.Nijitani:BAAANQADCgYJBgAAAA==.Nimrodd:BAAANQAECgQIBQAAAA==.',
No='Nobby:BAAANQADCgUICgAAAA==.Noogan:BAAANQADCgYIBgAAAA==.Nosferatü:BAAANQADCgUJBQAAAA==.Nothotdog:BAAANQADCgIIAgAAAA==.Novacat:BAABNQAECoEhAAIKAAgKnx/+CADiAgAKAAgKnx/+CADiAgAAAA==.Novangel:BAAANQADCgYIBgAAAA==.November:BAAANQAECgQJBwAAAA==.Nox:BAAANQADCggIDAAAAA==.',
Nu='Nubriss:BAAANQAECgYICAAAAA==.Nudetayne:BAAANQADCgQJBAAAAA==.Nuitsguard:BAABNQAECoEfAAQVAAgKVxYVPgD2AQAVAAgKVxYVPgD2AQASAAUKhgyQFwBEAQAJAAEKWw3/3wAxAAAAAA==.Nunnaly:BAAANQADCggJCAAAAA==.',
Ny='Nyaboron:BAAANQAECgUIDAAAAA==.Nyv:BAAANQADCggICAAAAA==.',
['Nè']='Nèaner:BAAANQAECgcIEwAAAA==.',
Og='Oggden:BAAANQAECgUJBwAAAA==.Ogrebane:BAAANQAECgUJCQAAAA==.',
Oi='Oiheg:BAAANQAECgYIDwAAAA==.',
Or='Oriha:BAAANQADCgYIBgAAAA==.',
Pa='Pajamasniper:BAAANQAECgQICAAAAA==.Pantheon:BAAANQADCggICAAAAA==.',
Pe='Peach:BAAANQAECgYIDgAAAA==.Perlita:BAAANQADCgQJBAAAAA==.',
Ph='Photos:BAAANQAECgYIDAAAAA==.',
Pi='Pigums:BAAANQAECgYIDQAAAA==.',
Pl='Pluug:BAAANQAECgUIBwAAAA==.',
Po='Poleo:BAAANQADCggICAAAAA==.',
Pr='Prayer:BAAANQAECgYIDwABNQADCgcIBwABAAAAAA==.Prîde:BAAANQADCgYIBwAAAA==.',
Ps='Psycopath:BAAANQAECgYJDwAAAA==.Psygn:BAAANQADCgUIBQABNQAECgYJDgABAAAAAA==.Psyloc:BAAANQADCgcJDQABNQAECgYJDgABAAAAAA==.',
Pt='Ptra:BAAANQAECgUIDAABNQAECggIGwALANsdAA==.',
Pu='Puddingfarts:BAAANQADCgcIBwAAAA==.Pumpy:BAACNQAFFIEFAAIJAAQKrhhYBgBjAQAJAAQKrhhYBgBjAQA1AAQKgRwAAgkACQphI4cJAHQDAAkACQphI4cJAHQDAAAA.',
Py='Pywacket:BAAANQAECgYJCAAAAA==.',
['Pã']='Pãlàdoom:BAAANQADCgUJCwABNQAECgYJEQABAAAAAA==.',
Qa='Qadésh:BAAANQABCgQIBAABNQADCgUIBQABAAAAAA==.',
Qu='Quendwings:BAEANQAECgUIBQABNQAFFAUJCAAKAEAZAA==.',
Ra='Rabern:BAAANQADCgIIAgAAAA==.Ragnaclio:BAAANQADCgIJAgAAAA==.Rainsky:BAAANQAECgIIAwAAAA==.Rasmatazz:BAAANQADCgIJAgAAAA==.Rayleighh:BAAANQAECgYIEAAAAA==.',
Re='Redemptio:BAAANQAECgUICQAAAA==.Rexxcat:BAAANQADCgYICQAAAA==.',
Ri='Rikaza:BAAANQADCgcIBgAAAA==.Ristraza:BAAANQADCgIIAgABNQAECgMJBwABAAAAAA==.',
Ro='Roguewølf:BAAANQADCgQIBgAAAA==.Roono:BAAANQADCgcICgAAAA==.Rosalidia:BAAANQAECgQICAAAAA==.Rosephane:BAAANQADCgUIBQAAAA==.Rossco:BAAANQAECgEIAQAAAA==.Rozoe:BAAANQADCgEJAQAAAA==.Rozzluz:BAAANQAECgYICwAAAA==.',
Ru='Rutira:BAAANQAECgcIEwAAAA==.',
Ry='Ryân:BAAANQADCgMIAwAAAA==.',
Sa='Sabbat:BAAANQADCgcJCwAAAA==.Salder:BAAANQADCgYJBgABNQADCgcIDAABAAAAAA==.Sapphiwrath:BAAANQADCgYJFAAAAA==.',
Sc='Scuuzemee:BAAANQAECgEJAQAAAA==.',
Se='Seacow:BAAANQAECgYJBgAAAA==.Searilus:BAAANQAECgIJAgAAAA==.Seethed:BAAANQADCgUJCgAAAA==.Selyana:BAAANQADCggJCAAAAA==.Seylena:BAAANQADCgcJFwABNQAECgYJDgABAAAAAA==.',
Sh='Shadowcrit:BAAANQAECgQIBQAAAA==.Shamamma:BAAANQADCgIJAgAAAA==.Shammallamma:BAAANQABCgQIBgAAAA==.Shamæn:BAAANQADCgcIFQAAAA==.Shaphyr:BAAANQAECgMJAwABNQAECgQICwABAAAAAA==.Sharphammer:BAAANQADCgUJCwAAAA==.Shieldon:BAAANQADCgUIBQABNQAECgUICwABAAAAAA==.Shikamarú:BAAANQADCgEIAQAAAA==.Shinhealer:BAAANQAECgEIAQAAAA==.Shiroa:BAAANQAECgEIAQABNQAECgIJBQABAAAAAA==.Shlapp:BAAANQADCgUJBQAAAA==.Shootsahlot:BAAANQADCgYIEwAAAA==.',
Si='Sidapa:BAAANQADCgYICgAAAA==.Silvernleaf:BAAANQADCgYIHAAAAA==.Sinai:BAAANQAECgUJCQAAAA==.Sindir:BAAANQADCgUIBQABNQAFFAQIBQAKAEQWAA==.Sinner:BAAANQADCggIBQABNQAECgUIBwABAAAAAA==.Siyx:BAAANQAECgIIAQAAAA==.',
Sk='Skept:BAAANQAECgcJDgAAAA==.',
Sl='Sleêp:BAAANQAECgEJAQAAAA==.Slosh:BAAANQAECggIEgAAAA==.',
Sm='Smellyandfat:BAECNQAFFIEIAAIKAAUKQBnUAQC+AQAKAAUKQBnUAQC+AQA1AAQKgSgAAwoACQogIlUDAGgDAAoACQogIlUDAGgDAAsACAo4HnsaAKICAAAA.Smerffy:BAAANQAECgQICAAAAA==.Smites:BAAANQADCgcJEAABNQAECgYJDgABAAAAAA==.',
So='Solise:BAAANQAECgcJBwAAAA==.Somehobo:BAAANQADCgIIAgAAAA==.Sonny:BAAANQAECgYIEwAAAA==.Sorshalynne:BAAANQADCgcIHAAAAA==.Soulhorror:BAAANQAECgYIDwAAAA==.',
Sp='Spiritfire:BAAANQAECgQIBgAAAA==.Spitefury:BAAANQAECgMIBAABNQAECgcIEwABAAAAAA==.Spriggs:BAEBNQAECoEZAAIIAAgKWBd5bABNAgAIAAgKWBd5bABNAgAAAA==.',
St='Starrfighter:BAAANQADCggICAABNQAECggIHwAVAFcWAA==.Stepfather:BAAANQADCgIIAgAAAA==.Stepmother:BAAANQADCgIIAgAAAA==.Stillblade:BAAANQADCgIIAgABNQADCgYIBwABAAAAAA==.Stonedread:BAAANQADCgYICwAAAA==.Stormfodder:BAAANQABCgQIBAAAAA==.Stronker:BAAANQADCggICgAAAA==.',
Su='Sungmi:BAAANQAECgYIEAAAAA==.Sunntzu:BAAANQAECgUIDgAAAA==.',
Sw='Swindlle:BAAANQAECgQJBwAAAA==.',
Sy='Syber:BAABNQAECoEZAAIKAAgKqhqBDgCBAgAKAAgKqhqBDgCBAgAAAA==.Sympathy:BAAANQADCggJDQAAAA==.Symphonica:BAAANQAECgQICwAAAA==.Syreithis:BAAANQAECgUJBgAAAA==.',
['Sí']='Síd:BAABNQAECoEUAAMWAAgKpxRbFQBNAgAWAAgKpxRbFQBNAgAXAAUKvgu8KAAkAQAAAA==.',
Ta='Tacofighter:BAAANQAECgUIDAAAAA==.Taerielle:BAABNQAECoEjAAIYAAgKrBzwAwCCAgAYAAgKrBzwAwCCAgAAAA==.Tageren:BAAANQADCgYICgAAAA==.Taldim:BAAANQADCgUIBQABNQAECgYJDgABAAAAAA==.Taliah:BAAANQADCgcJDQAAAA==.Tarhos:BAAANQABCgIIBgAAAA==.Tarò:BAABNQAECoElAAIQAAkKmgslQADmAQAQAAkKmgslQADmAQAAAA==.Taychi:BAAANQAECgIIAgABNQAECggJFgADAAgQAA==.',
Te='Teacupps:BAABNQAECoEaAAMZAAkKhh16EADcAQAaAAcKfhpASAD9AQAZAAcKHhZ6EADcAQAAAA==.Teegan:BAAANQAECgQJCQAAAA==.Tekloa:BAAANQADCgUJBQAAAA==.Telvissra:BAABNQAECoEdAAIUAAkKZRiQFgC3AgAUAAkKZRiQFgC3AgAAAA==.Temporary:BAAANQADCgYJBgAAAA==.Teoritta:BAAANQAECgYIDwAAAA==.Terrisher:BAAANQAECgYIDgAAAA==.',
Th='Thaljadrak:BAAANQADCgQIBwAAAA==.Thermopalea:BAAANQADCgUICgAAAA==.Thetamoon:BAAANQAECgYJDgAAAA==.Thorald:BAAANQAECgUICAAAAA==.Thordh:BAAANQADCgMIAwAAAA==.Thorggon:BAAANQAECggIEQAAAA==.Thornbeast:BAAANQAECgEJAgAAAA==.Thuato:BAAANQADCgQICAAAAA==.Thundermayne:BAAANQAECgEJAQAAAA==.Thád:BAAANQAECgUICAAAAA==.',
Ti='Tiranoc:BAAANQADCgcJCQABNQAECgYIDgABAAAAAA==.',
To='Tojara:BAAANQADCgcIBwAAAA==.Toxique:BAAANQADCgcIHQAAAA==.',
Tr='Travelocitee:BAAANQAECgQIBAAAAA==.Triskalyn:BAAANQAECgEJAQAAAA==.Trojanhorse:BAAANQADCggIIAAAAA==.Trokosan:BAAANQAECgQJBAAAAA==.Trustissues:BAAANQADCggIFgAAAA==.Try:BAACNQAFFIELAAISAAYKHR5IAABOAgASAAYKHR5IAABOAgA1AAQKgSEAAhIACQp9Jt4AALoDABIACQp9Jt4AALoDAAAA.Trybu:BAABNQAECoEkAAIIAAkK0R0tLAAMAwAIAAkK0R0tLAAMAwAAAA==.Tryiss:BAAANQAECgIJAgAAAA==.',
Tt='Ttryss:BAAANQADCgUIBQAAAA==.',
Tu='Tubslumpkin:BAAANQAECgIIAgAAAA==.Tuketu:BAAANQAECgYJEwAAAA==.Turtlelord:BAAANQAECgYJEgAAAA==.',
Ty='Tylarion:BAAANQAECgQIBAAAAA==.Tylendal:BAABNQAECoEZAAIFAAgK7g1NEQDjAQAFAAgK7g1NEQDjAQAAAA==.Tylenulz:BAAANQAECgQICAAAAA==.Tylheras:BAAANQAECgcJDAAAAA==.Tyliera:BAAANQADCgcICAAAAA==.Tylren:BAAANQAECgMIAwAAAA==.',
['Tà']='Tànya:BAAANQAECgUJCAAAAA==.',
Un='Unfàthømable:BAAANQADCggICAABNQAECgYJEQABAAAAAA==.',
Ut='Uthercito:BAAANQADCggICQAAAA==.',
Va='Vallarath:BAAANQAECgQIBQAAAA==.Valtaran:BAAANQAECgEJAQAAAA==.Valtarr:BAAANQAECgUIDQAAAA==.Vampirism:BAAANQAECgUIDQAAAA==.Vasira:BAAANQADCgcIGwAAAA==.Vaulthunter:BAAANQAECgQIBAAAAA==.',
Ve='Vecna:BAAANQADCgMIBQAAAA==.Veina:BAAANQAECgUJBQAAAA==.Veloril:BAAANQADCgcIDAAAAA==.Vethena:BAAANQAECgMJAwAAAA==.Vezahk:BAAANQADCgEIAQAAAA==.',
Vi='Vidu:BAAANQAECgYJDgAAAA==.Vikas:BAAANQADCgYIBgAAAA==.Vivitrix:BAAANQAECgEJAQAAAA==.Viví:BAAANQAECgQIDwAAAA==.',
Vl='Vlm:BAAANQAECgMIAwAAAA==.',
Vo='Voidbreaker:BAAANQAECgYJDAABNQAECgYIEQABAAAAAA==.Vordis:BAAANQAECgQIBQAAAA==.Vordissia:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.Voxis:BAAANQADCggICQAAAA==.',
Vv='Vv:BAAANQAECgQJBwAAAA==.',
Vy='Vyrstal:BAAANQADCggICAABNQAECgYIEgABAAAAAA==.',
Wa='Wardan:BAAANQADCgUICQAAAA==.',
We='Weavile:BAAANQADCgUIBQABNQAFFAUIEAATAFIMAA==.Wef:BAAANQADCggJHgAAAA==.Weirdtotem:BAABNQAECoEeAAMJAAkKTx7KFgD2AgAJAAgKjiHKFgD2AgAVAAcKZhzQLwA6AgAAAA==.Westylad:BAAANQAECgYJEAAAAA==.Wetrat:BAAANQAECgUIBQABNQAFFAQJBQAJAK4YAA==.',
Wh='Whatthefunk:BAAANQADCgUICgAAAA==.',
Wi='Winterfox:BAAANQADCgYICQAAAA==.Winters:BAAANQADCgMIAwAAAA==.',
Wr='Wrystal:BAAANQAECgYIEgAAAA==.',
Xa='Xannaa:BAAANQADCgIJAgAAAA==.',
Xe='Xernes:BAAANQADCgQIBAAAAA==.',
Xu='Xujian:BAAANQADCggJHAAAAA==.',
Ya='Yakiki:BAAANQADCgcIBwABNQAECgkJKgATALklAA==.',
Yu='Yuma:BAAANQABCgEIAgABNQAECgUJCAABAAAAAA==.',
Za='Zaelenia:BAAANQAECgUJBwAAAA==.Zalen:BAAANQAECgYIDwAAAA==.Zappylad:BAAANQAECgMIAwAAAA==.Zarelle:BAAANQAECgEIAQAAAA==.Zartoon:BAAANQADCgcIBwAAAA==.',
Ze='Zenamani:BAAANQAECgUJBQAAAA==.Zenetha:BAAANQAECgUJCAAAAA==.Zephyres:BAAANQAECggIEQABNQAFFAUICAARAKYbAA==.Zerokool:BAAANQABCgYIBgABNQAECgcICQABAAAAAA==.Zevarya:BAAANQAECgEIAQAAAA==.',
Zo='Zonksmoose:BAAANQADCgYICQAAAA==.Zonkspaladin:BAABNQAECoEhAAIbAAgKDB3JHQCnAgAbAAgKDB3JHQCnAgAAAA==.Zornac:BAAANQADCgcIDQAAAA==.',
Zp='Zpyder:BAAANQAECgIIBAAAAA==.',
Zy='Zynskie:BAAANQAECgcJEAAAAA==.Zyraa:BAAANQADCgIIAQAAAA==.',
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
