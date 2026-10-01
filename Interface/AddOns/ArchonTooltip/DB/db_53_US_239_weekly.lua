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

local lookup = {'Paladin-Retribution','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Protection','Warrior-Arms','DemonHunter-Devourer','Hunter-BeastMastery','Evoker-Devastation','DeathKnight-Blood','DeathKnight-Unholy','Unknown-Unknown','Monk-Mistweaver','Druid-Balance','Druid-Feral','Druid-Guardian','Druid-Restoration','Mage-Arcane','DeathKnight-Frost','Hunter-Marksmanship','Paladin-Protection','Monk-Windwalker','DemonHunter-Vengeance','Priest-Holy','Rogue-Assassination','Rogue-Subtlety','Shaman-Enhancement','Priest-Shadow','Mage-Frost','Warrior-Fury','Hunter-Survival','Paladin-Holy','DemonHunter-Havoc','Monk-Brewmaster',}
local provider = {region='US',realm='Windrunner',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Accea:BAAANQADCgEIAQAAAA==.Acehobo:BAAANQADCgUIBQAAAA==.Acetaminofun:BAAANQAECgQJCgAAAA==.Actionjaxson:BAABNQAECoEUAAIBAAcKDiJzOgCgAgABAAcKDiJzOgCgAgAAAA==.',
Ad='Adeathknight:BAAANQABCgIIAgAAAA==.Ademis:BAAANQAECgEIAgAAAA==.Admore:BAAANQAECgQICQAAAA==.',
Ae='Aeriith:BAABNQAECoEaAAMCAAkKNxZlOgAuAgACAAkKNxZlOgAuAgADAAYKUgzTgwBDAQAAAA==.Aethmourne:BAAANQADCgMIAwAAAA==.',
Ag='Agameden:BAAANQAECgQICQAAAA==.Agogg:BAAANQADCggIFAAAAA==.Agronak:BAAANQABCgIIAgAAAA==.',
Ah='Ahsina:BAAANQABCgUIBQAAAA==.',
Ai='Aintnosecret:BAAANQAECgUICAAAAA==.Aishi:BAAANQAECgQIDQAAAA==.',
Ak='Akaya:BAAANQAECgUICgABNQAECggIFwADAOwQAA==.Akitsuki:BAAANQADCgUIBQAAAA==.',
Al='Algy:BAAANQADCgIJAgAAAA==.Alillara:BAAANQADCgIIAgAAAA==.Alivron:BAABNQAECoEYAAQEAAcKEgw+CQCeAQAEAAcKogs+CQCeAQAFAAIK/QRl+QBTAAAGAAEKHwK0eAAjAAAAAA==.Alkoren:BAAANQAECgUICQABNQAECggIHQAHAE4cAA==.Alkorin:BAABNQAECoEdAAMHAAgKThy9CAB2AgAHAAgKThy9CAB2AgAIAAIKZgnq/gBuAAAAAA==.Allestra:BAABNQAECoEqAAIJAAkKdByTDAD7AgAJAAkKdByTDAD7AgAAAA==.',
Am='Amaranthine:BAAANQADCgYIBgAAAA==.Amoxil:BAAANQAECgQIBAAAAA==.',
An='Anasztaizia:BAEANQAECgEIAQAAAA==.Andorin:BAABNQAECoEfAAIKAAgK5xnsOgB0AgAKAAgK5xnsOgB0AgAAAA==.Andronicus:BAAANQADCgMIAwAAAA==.Andwin:BAAANQADCggJCAAAAA==.Anorah:BAAANQAECgEIAQAAAA==.Anunitu:BAABNQAECoEbAAICAAgKGhlWOQAyAgACAAgKGhlWOQAyAgAAAA==.',
Ao='Aoibheann:BAAANQAECgUICAAAAA==.',
Ar='Arath:BAABNQAECoEcAAILAAgKXBTwDwAeAgALAAgKXBTwDwAeAgAAAA==.Arcath:BAABNQAECoEcAAIMAAgKvBu8IAB4AgAMAAgKvBu8IAB4AgAAAA==.Arcona:BAAANQAECgMIBQAAAA==.Aristus:BAAANQADCggIEgAAAA==.Arthuel:BAAANQADCgMIAwAAAA==.',
As='Asar:BAAANQAECgEIAwAAAA==.Ashlanni:BAAANQADCgIIAwAAAA==.Asiaminor:BAAANQADCgMIBQAAAA==.Astora:BAAANQADCgcIBwAAAA==.',
At='Athuzad:BAABNQAECoEYAAINAAgK0R0hHgCQAgANAAgK0R0hHgCQAgAAAA==.',
Au='Auroraalysia:BAAANQADCgYICwAAAA==.Auroran:BAAANQAECgYIEAAAAA==.Autumnmoon:BAAANQAECgYIEgAAAA==.',
Av='Aviendah:BAAANQADCggIEgAAAA==.Avrilenv:BAAANQAECgEIAQAAAA==.',
Ay='Ayeroh:BAAANQAECgIIAgAAAA==.Aylara:BAAANQAECgQIBAAAAA==.',
Az='Azenet:BAAANQADCgYIBgAAAA==.Azkabras:BAAANQADCgMIAwABNQAECgcIEAAOAAAAAA==.',
Ba='Badoink:BAAANQADCggICAABNQAECggIFwAPAKkiAA==.Bakasaura:BAAANQADCgYICwABNQAECgYIFgAQAP0iAA==.Balorous:BAAANQAECgYIEgAAAA==.Bansheelen:BAABNQAECoEZAAQRAAcKSxWADQDSAQARAAcKchSADQDSAQASAAUKHxXIHAAvAQATAAIKkRS5SgCDAAAAAA==.Banthis:BAAANQAECgcJEgAAAA==.Barkcamon:BAABNQAECoEdAAIPAAgKWRCYFgC7AQAPAAgKWRCYFgC7AQAAAA==.Barmaak:BAAANQAECgEIAQAAAA==.Barrand:BAAANQADCggJCAABNQAECgUICwAOAAAAAA==.Barthelo:BAABNQAECoEUAAIMAAYK8SIVJQBaAgAMAAYK8SIVJQBaAgAAAA==.Bassandi:BAAANQADCgEIAQABNQAECggIHAAIANcOAA==.Baxdock:BAAANQAECgMJBAAAAA==.Baxideath:BAAANQAECgYIDwAAAA==.',
Be='Beastylad:BAAANQADCgYIBwAAAA==.Beefcâke:BAAANQADCgYIBgAAAA==.Bekahroo:BAAANQADCgYIGwABNQAECgQJBAAOAAAAAA==.Bekahsama:BAAANQAECgQJBAAAAA==.Belcron:BAAANQADCgYIFgAAAA==.Beld:BAAANQADCgYJBgAAAA==.Beldaran:BAAANQAECgEIAQAAAA==.Belladawna:BAABNQAECoEUAAMEAAYKHg3ICgB0AQAEAAYKHg3ICgB0AQAFAAEK3QJOEwEqAAAAAA==.Belldândy:BAAANQAECgEJAQAAAA==.Bernal:BAAANQAECgMIBQAAAA==.',
Bh='Bhature:BAAANQADCgMIAwAAAA==.',
Bi='Bigmapletree:BAAANQAECgYIDwAAAA==.Bigëmu:BAAANQADCgcIIQAAAA==.Billyidols:BAAANQADCgEIAQAAAA==.Bingbangpów:BAAANQAECgMIAgAAAA==.',
Bl='Blackblader:BAAANQAECgUIBQAAAA==.Blarus:BAAANQADCgIIAgAAAA==.Bluecat:BAAANQAECgcIDAAAAA==.Blueplanet:BAABNQAECoEWAAIQAAYK/SKPKgBEAgAQAAYK/SKPKgBEAgAAAA==.',
Bn='Bnoo:BAAANQADCgEIAQABNQAECgkJKwAUADQgAA==.',
Bo='Boarggon:BAAANQADCgEIAQABNQAECgkJGwAHAJ8iAA==.Boherwin:BAAANQAECgYIDQAAAA==.Bonnie:BAAANQAECgMIAwAAAA==.Borealus:BAAANQAECgYIEQAAAA==.',
Br='Bratakwar:BAAANQAECgEIAQAAAA==.Bris:BAAANQAECgcIEwAAAA==.Bruby:BAAANQAECgQIBQAAAA==.Bruceleelad:BAAANQADCgYIBgAAAA==.Brugamen:BAABNQAECoEcAAMIAAgK1w74fADPAQAIAAgK3g34fADPAQAHAAQKaA2EJQCvAAAAAA==.Brugg:BAABNQAECoEXAAIKAAgKjRkcNwCBAgAKAAgKjRkcNwCBAgABNQAECggIHAAIANcOAA==.Brynnu:BAAANQADCgIIAgAAAA==.Brád:BAAANQAECgYIDgAAAA==.',
Bu='Bunnylajoya:BAAANQADCgYICwAAAA==.Burgerz:BAAANQADCggJGwAAAA==.Busblaster:BAAANQAECgYIEAAAAA==.',
['Bä']='Bäldur:BAAANQAECgYIBwAAAA==.',
Ca='Calestel:BAAANQADCgIIAgAAAA==.Careßear:BAAANQAECgIIAQAAAA==.Carielle:BAAANQADCgcJEgAAAA==.Carodd:BAABNQAECoEoAAIVAAkKHSHmCgAWAwAVAAkKHSHmCgAWAwAAAA==.',
Ce='Cedaver:BAAANQAECgYIEwAAAA==.Ceez:BAAANQADCgYIBwABNQADCggIBQAOAAAAAA==.Cellphoneguy:BAAANQADCgMIAwAAAA==.Celtigar:BAAANQAECgEJAQAAAA==.',
Ch='Chaan:BAAANQAECgUIBwAAAA==.Chaddicus:BAAANQADCggJGwAAAA==.Chainna:BAAANQADCggIEAAAAA==.Chaliceia:BAAANQADCgEIAQAAAA==.Chanlin:BAABNQAECoEXAAIMAAkKmh5MFADdAgAMAAkKmh5MFADdAgAAAA==.Chateau:BAAANQAECgEIAQAAAA==.Chauda:BAAANQADCgcICwABNQAECggIFwADAOwQAA==.Chazbot:BAAANQAECgEIAQAAAA==.Chereth:BAAANQAECgMIBQAAAA==.Cheshire:BAABNQAECoEeAAIKAAgKpR3CLwCdAgAKAAgKpR3CLwCdAgAAAA==.Chestystab:BAAANQADCggIEgAAAA==.Chezpuff:BAAANQADCgEIAQAAAA==.Chill:BAAANQAECgYIEQAAAA==.Chlorin:BAABNQAECoEbAAIWAAgKRAZeLgCAAQAWAAgKRAZeLgCAAQAAAA==.Chocolate:BAACNQAFFIEHAAIUAAQK5RGWGABOAQAUAAQK5RGWGABOAQA1AAQKgR0AAhQACQq7IJ87APECABQACQq7IJ87APECAAAA.',
Cl='Cloudcrasher:BAAANQAECgMIAwAAAA==.Cloudsayer:BAAANQAECgQIBwAAAA==.Cloudspeaker:BAAANQAECgYIEAAAAA==.',
Co='Coldblades:BAAANQADCgYJBgAAAA==.Coldfrostshk:BAAANQADCgUICgAAAA==.Coldslayer:BAAANQAECgYIEAAAAA==.Coldsteeldx:BAAANQADCgUIBQAAAA==.Copy:BAAANQAECgQJBQAAAA==.Corpha:BAAANQADCgUJBQABNQAECgkJIgADAFgeAA==.Cozbysuite:BAAANQADCgIIAgAAAA==.',
Cr='Crackzap:BAAANQAECgEIAQAAAA==.Crazyrd:BAAANQAECgYIDwAAAA==.Crotgustus:BAAANQADCgMIBQAAAA==.Crudkicker:BAAANQADCgYIBgAAAA==.Crumblebump:BAAANQAECgMIBQAAAA==.Crummbly:BAAANQAECgEIAQAAAA==.',
Cy='Cyndelle:BAAANQADCggIJAAAAA==.Cyntaria:BAAANQAECgIIAgAAAA==.Cyriz:BAAANQAECgIIBgAAAA==.',
Da='Daedrea:BAAANQADCgYIBgAAAA==.Dagarim:BAAANQAECgEIAQAAAA==.Daienne:BAAANQAECgcIDgAAAA==.Danamor:BAABNQAECoEYAAIBAAgKrBQmawAAAgABAAgKrBQmawAAAgAAAA==.Dandanx:BAAANQADCggIGAABNQAECgYIEwAOAAAAAA==.Daplug:BAAANQAECgMIBgAAAA==.Dariann:BAAANQADCgYIBgAAAA==.Darkbrand:BAABNQAECoEZAAIJAAgKrgnrKgCrAQAJAAgKrgnrKgCrAQAAAA==.Darkdock:BAAANQADCgIIAgAAAA==.Darkladÿ:BAAANQADCgMIAwAAAA==.Darnel:BAABNQAECoEUAAIXAAYKvhJXJgBQAQAXAAYKvhJXJgBQAQAAAA==.Darnogden:BAAANQADCgUIBQAAAA==.Darnokk:BAAANQAECgMIBQAAAA==.',
De='Deathbreaker:BAAANQADCgYJCAAAAA==.Deathbyfel:BAAANQADCgcIDAABNQAECgUICwAOAAAAAA==.Deathbyshock:BAAANQAECgUICwAAAA==.Deathdan:BAAANQADCgEIAQAAAA==.Deathrollins:BAAANQAECgEJAQAAAA==.Deathylad:BAAANQADCgcIBwAAAA==.Delaror:BAAANQADCgYIBgAAAA==.Denadin:BAAANQAECgEIAgABNQAECgYIDwAOAAAAAA==.Denari:BAAANQABCgMIBQAAAA==.Dennygrips:BAAANQADCggIDQABNQAECgYIDwAOAAAAAA==.Dennyshotz:BAAANQADCggICAABNQAECgYIDwAOAAAAAA==.Dennyshreds:BAAANQAECgYIDwAAAA==.Dennytotem:BAAANQAECgQIBAABNQAECgYIDwAOAAAAAA==.Dennywarrior:BAAANQADCggICAABNQAECgYIDwAOAAAAAA==.Denrukhan:BAACNQAFFIEIAAITAAQKNR7pBABuAQATAAQKNR7pBABuAQA1AAQKgSAAAxMACQorIwMGAD4DABMACQorIwMGAD4DABAAAQoOHQAAAAAAAAAA.Deschain:BAAANQADCgcIGQAAAA==.Dew:BAABNQAECoElAAIDAAkKyxxZHADxAgADAAkKyxxZHADxAgAAAA==.',
Di='Diin:BAAANQAECgUICwAAAA==.',
Dk='Dklord:BAAANQAECgUICAAAAA==.',
Do='Donappletino:BAAANQAECgIIAgAAAA==.Donkedixlol:BAAANQADCgcICwAAAA==.Doobzers:BAAANQADCgMIAwABNQAECgYJDQAOAAAAAA==.Doxtorbrujo:BAAANQAECgcICwABNQAECggIHAAXAKEfAA==.Doxtorele:BAAANQAECgcICQABNQAECggIHAAXAKEfAA==.Doxtormonje:BAAANQAECgYIBgABNQAECggIHAAXAKEfAA==.Doxtorprote:BAABNQAECoEcAAIXAAgKoR9NCQDNAgAXAAgKoR9NCQDNAgAAAA==.Doxtorunholy:BAAANQAECgcICQABNQAECggIHAAXAKEfAA==.',
Dr='Draelgor:BAAANQADCgEJAQAAAA==.Dredd:BAAANQAECgEIAQAAAA==.Drunk:BAABNQAECoEaAAMPAAgK5g7RGACZAQAPAAgK5g7RGACZAQAYAAIK5Qq5SQBlAAAAAA==.',
Du='Duckpally:BAAANQABCgYIBgAAAA==.',
Dw='Dwarfussy:BAAANQAECgYICwAAAA==.Dwindle:BAAANQADCgUIBQABNQAECgUICwAOAAAAAA==.',
Ea='Earthernheal:BAAANQAECgMIBAAAAA==.',
Ec='Eckshin:BAAANQADCggIDgAAAA==.',
Ed='Edroffert:BAAANQADCgQIBAAAAA==.',
Eh='Ehonte:BAABNQAECoEbAAIIAAgKQBB1cwDrAQAIAAgKQBB1cwDrAQAAAA==.',
Ei='Eidolonn:BAAANQADCgcJEAAAAA==.',
Ek='Ekkaia:BAAANQAECgcIEAAAAA==.',
El='Eleminohpee:BAAANQADCgMIAwABNQAECgYIDgAOAAAAAA==.Elfypriestly:BAAANQADCgUIBwAAAA==.Elsell:BAAANQAECgEJAQAAAA==.Elwasp:BAAANQAECgEIAQAAAA==.',
Em='Emptypockets:BAAANQADCgUICQAAAA==.',
En='Encana:BAABNQAECoEeAAIZAAgKlRazCAALAgAZAAgKlRazCAALAgAAAA==.Ender:BAAANQADCggIJAAAAA==.',
Ep='Epiales:BAAANQADCgUIBQAAAA==.',
Er='Ericgb:BAABNQAECoEmAAMSAAgKmhOkEADSAQASAAgKmhOkEADSAQARAAEKPAMPMQApAAAAAA==.Eronara:BAAANQADCgIIAgABNQAECgUIDAAOAAAAAA==.Errzza:BAAANQAECgMIBQAAAA==.Erutreya:BAAANQADCgcICQAAAA==.Erzsébet:BAAANQAECgIJBQAAAA==.',
Es='Esha:BAAANQADCgYIFAAAAA==.',
Et='Etsubrew:BAAANQAECggIDwAAAA==.Etsupriest:BAAANQAECgcIEAAAAA==.',
Eu='Eula:BAAANQADCgYICwAAAA==.',
Ev='Evelynn:BAAANQAECgYIEAAAAA==.Evoked:BAAANQAECgUICwAAAA==.',
Ex='Exanimus:BAAANQADCgUJCAAAAA==.Exign:BAAANQADCgIJAgAAAA==.Exix:BAAANQAECgEIAQAAAA==.Exqui:BAABNQAECoEcAAMFAAgKZSCXGgDtAgAFAAgKZSCXGgDtAgAGAAEKkhfeZABBAAAAAA==.',
Ez='Ezral:BAAANQAECgEJAQABNQAECgEIAQAOAAAAAA==.',
['Eí']='Eíko:BAABNQAECoEcAAIaAAkK1BcSNQBQAgAaAAkK1BcSNQBQAgAAAA==.',
Fa='Faeruh:BAAANQADCggICQAAAA==.Fafnar:BAAANQADCgcIDAABNQAECgYIFAAKAOMXAA==.Fafnie:BAAANQAECgQIDQAAAA==.',
Fe='Felath:BAAANQAECgYIEAAAAA==.Feldspar:BAAANQAECgYIEAAAAA==.',
Fi='Fil:BAAANQAECgYIEgAAAA==.Fishswife:BAAANQAECgYICQAAAA==.Fissal:BAAANQADCgcIBwAAAA==.Fistoflurry:BAAANQADCgIIAgABNQAECgkJGwAHAJ8iAA==.',
Fl='Flameviper:BAAANQAECgIIAgAAAA==.Flompy:BAAANQADCgIIAgAAAA==.Floreil:BAAANQADCgUIBQAAAA==.',
Fo='Foofighter:BAAANQADCgIIAgAAAA==.Footoo:BAAANQAECgMIBQAAAA==.Foxybrie:BAAANQABCgIIAgAAAA==.',
Fr='Friedchimkin:BAAANQADCggIEQAAAA==.Frort:BAAANQADCgcIDwAAAA==.',
Fu='Fuknord:BAAANQADCgYIBwAAAA==.Fulva:BAAANQADCgcIBgAAAA==.',
Fy='Fyneep:BAAANQAECgYIEgAAAA==.Fynne:BAABNQAECoEgAAIaAAcKYBguUgDUAQAaAAcKYBguUgDUAQAAAA==.',
Ga='Gaiusmohiam:BAAANQABCgUIBQAAAA==.Galadriell:BAAANQADCgcIBwAAAA==.Galdademon:BAAANQAECgMJAwAAAA==.Galiophobia:BAAANQADCgYICwAAAA==.Galm:BAAANQADCggIEwAAAA==.Garrethul:BAAANQAECgMIBgAAAA==.Gawleywood:BAAANQAECgMIBQAAAA==.',
Ge='Gellidus:BAAANQAECgYIDwAAAA==.Genhooves:BAEANQADCgYJCwABNQAECgkJIQAUAFcaAA==.Gensisd:BAAANQAECgYIEwAAAA==.Gentledh:BAAANQAECgQIBAAAAA==.Gentleshadow:BAAANQAECgUICAAAAA==.Gerulf:BAAANQABCgQIBAAAAA==.',
Gh='Ghosteagle:BAAANQADCgQIBAAAAA==.Ghostvoid:BAAANQABCgYICgAAAA==.',
Gn='Gnomejodas:BAAANQADCggIFQAAAA==.',
Go='Gobfather:BAAANQADCgcIEgAAAA==.Goldcity:BAAANQAFFAIIAgAAAA==.Goodfaith:BAAANQAECgEJAQAAAA==.Goofy:BAACNQAFFIEPAAIIAAUK9xk3CgCnAQAIAAUK9xk3CgCnAQA1AAQKgRkAAggACQr3JC4PAHADAAgACQr3JC4PAHADAAE1AAQKAggEAA4AAAAA.Gotha:BAAANQADCgEIAQABNQAECgYIEwAOAAAAAA==.',
Gr='Grimlocke:BAAANQAECgUIBwAAAA==.Grimsolo:BAAANQADCggIGAABNQAECgUIBwAOAAAAAA==.Gromit:BAAANQAECgcIEgAAAA==.Grovecaller:BAAANQADCgUIBQABNQAECgYIEAAOAAAAAA==.',
Gu='Gubber:BAAANQADCgIIAQAAAA==.',
Gw='Gwyndolin:BAAANQAECgMIBQAAAA==.Gwynne:BAAANQAECgUJBgAAAA==.',
Ha='Halanad:BAAANQAECgEIAQAAAA==.Halfmoons:BAABNQAECoEYAAIaAAcKcB2mNgBJAgAaAAcKcB2mNgBJAgAAAA==.Halfsumo:BAAANQAECgUIDAAAAA==.Halobender:BAAANQAECgIIAgAAAA==.Harrol:BAAANQAECgQICQABNQAECgQIBAAOAAAAAA==.Hassindiir:BAABNQAECoEfAAISAAgKUAZEHgAhAQASAAgKUAZEHgAhAQAAAA==.Hawgelf:BAAANQAECgUICQAAAA==.Hawmahcide:BAAANQADCgcICwAAAA==.Hayles:BAAANQAECgMIBQAAAA==.',
He='Helathra:BAAANQAECgYIDwAAAA==.Helliona:BAAANQADCggICAAAAA==.Hermonk:BAAANQAECgQICAABNQAFFAQICAAMALsZAA==.',
Hi='Hiiru:BAAANQADCgcIBwABNQAECggIHQAHAE4cAA==.Hishunter:BAAANQAECgcIDgABNQAFFAQIBgAQANkaAA==.',
Ho='Hofin:BAAANQAECgYIBgAAAA==.',
Hu='Huntarr:BAAANQAECgcIDwAAAA==.Hunterdamon:BAABNQAECoEaAAMJAAgKJQscKADFAQAJAAgKuwkcKADFAQAZAAIK6w8oHwBlAAAAAA==.',
Hy='Hycinna:BAAANQADCgYICwAAAQ==.Hydrazashen:BAAANQAECgIIAgAAAA==.',
['Hà']='Hàou:BAAANQADCggIEgAAAA==.',
Ia='Iamafish:BAAANQAECgYIEgAAAA==.Iamgroott:BAAANQADCgMIAwAAAA==.',
Ic='Ichimaru:BAAANQAECgYIBgAAAA==.',
Ig='Igotyou:BAAANQAECgUIEAAAAA==.',
In='Insidae:BAABNQAECoEaAAMbAAgK7hfJGABkAgAbAAgK7hfJGABkAgAcAAEKowA7SwAVAAAAAA==.',
Ir='Ironpunch:BAAANQADCggICQAAAA==.',
Is='Ismirea:BAAANQAECgEJAQAAAA==.Isoldella:BAAANQADCgYIBgAAAA==.',
Iz='Izuna:BAAANQADCgUIBQAAAA==.',
Ja='Jalencarter:BAAANQAECgUICQAAAA==.Jamirprote:BAAANQAECgcIDQAAAA==.Jantasir:BAAANQAECgUICgAAAA==.Jasaryia:BAAANQADCgUIBQAAAA==.Javalyn:BAAANQAECgMIBQAAAA==.',
Ji='Jin:BAAANQAECggIDwABNQAFFAYIDAAdAB0eAA==.Jinda:BAAANQADCgYIGgAAAA==.Jirachi:BAAANQAECggIEAABNQAFFAUIEwAeAH8VAA==.Jiujitsu:BAAANQAECgYICQAAAA==.',
Jo='Jobergas:BAAANQAECgIIAgAAAA==.Jobi:BAAANQAECgMIBAAAAA==.Johallas:BAABNQAECoEcAAIfAAgKNRw2BACuAgAfAAgKNRw2BACuAgAAAA==.',
Ju='Judzia:BAAANQAECgMIAwAAAA==.Juf:BAABNQAECoEYAAMaAAgKSwv9WwCsAQAaAAgKSwv9WwCsAQAeAAEKDQMzcgAbAAAAAA==.Jufster:BAAANQADCggICwAAAA==.Jumpingbear:BAACNQAFFIEKAAIRAAUKeAvDAACSAQARAAUKeAvDAACSAQA1AAQKgSkAAxEACQoRIqcDACQDABEACQoRIqcDACQDABAAAgpyFnN6AIYAAAAA.Justdeadfred:BAAANQADCggICAAAAA==.',
Ka='Kagar:BAAANQADCgMIAwAAAA==.Kaho:BAAANQAECgUICQAAAA==.Kainazzo:BAAANQADCggIIQAAAA==.Kaladorn:BAAANQAECgIIAgAAAA==.Kaladïn:BAAANQADCgUIBQABNQAECgMIBgAOAAAAAA==.Kalda:BAAANQAECgYIEQABNQAECggIEgAOAAAAAA==.Kalikali:BAAANQADCgcIBwABNQAECgQIBgAOAAAAAA==.Kallisto:BAAANQAECgUICQAAAA==.Kamiarashi:BAAANQADCggICgAAAA==.Karabethe:BAEANQAECgIJAQAAAA==.Kattizzi:BAAANQADCgMIAwAAAA==.Kazuhiro:BAACNQAFFIENAAIIAAUKfB8+CADOAQAIAAUKfB8+CADOAQA1AAQKgScAAwgACQq3JR0FAMADAAgACQqdJR0FAMADAAcAAgr6JYshANkAAAAA.',
Ke='Keadath:BAAANQADCgcIBwAAAA==.Keagan:BAAANQAECgIIBQAAAA==.Kehzai:BAABNQAECoEZAAINAAYKgQ7dXQAyAQANAAYKgQ7dXQAyAQAAAA==.Kelric:BAAANQADCgUIBQAAAA==.Kenpomaster:BAAANQAECgEIAQAAAA==.Keyalastus:BAAANQADCgQIBAAAAA==.',
Kh='Khaluha:BAAANQAECgEJAQAAAA==.Khaymaan:BAAANQAECgUICAAAAA==.',
Ki='Killios:BAAANQAECgMIAwAAAA==.Kilmeawden:BAAANQAECgUIEQAAAA==.',
Ko='Kozal:BAAANQADCgcIBwAAAA==.',
Kr='Krionys:BAAANQADCgEIAQAAAA==.Krisha:BAABNQAECoEXAAIDAAgK7BD2TAD0AQADAAgK7BD2TAD0AQAAAA==.Krisphobos:BAAANQAECgUICwAAAA==.',
Ku='Kubael:BAAANQAECgEIAQAAAA==.Kuesham:BAAANQADCgUJBAABNQAECgEIAQAOAAAAAA==.Kulgutbuster:BAABNQAECoEbAAIKAAgKjRrOOAB7AgAKAAgKjRrOOAB7AgAAAA==.Kungpow:BAAANQAECgcIDgAAAA==.Kupdor:BAAANQAECgUIDAABNQAECgYIDgAOAAAAAA==.Kuromatsu:BAAANQAECgUIEAAAAA==.Kurtrus:BAAANQADCgQIBAAAAA==.',
['Kÿ']='Kÿt:BAAANQAECgYIEgAAAA==.',
La='Lacedon:BAAANQAECgYICgAAAA==.Lantank:BAAANQABCgIIAgAAAA==.Larceny:BAAANQAECgYICAAAAA==.Larfleeze:BAAANQADCgYIBgAAAA==.Layliah:BAACNQAFFIEJAAIQAAUKryCZBQDdAQAQAAUKryCZBQDdAQA1AAQKgSoAAhAACQpJJBUEAK8DABAACQpJJBUEAK8DAAAA.',
Le='Leiania:BAAANQADCgUIBQABNQAECgkJJQANAM0cAA==.Lewis:BAAANQADCggICAAAAA==.',
Li='Lild:BAAANQADCgYICQAAAA==.Lilgup:BAAANQAECgUIBQAAAA==.Linadrea:BAAANQADCgYIBgAAAA==.Linedaleiris:BAAANQADCgcJBwAAAA==.Liqudblu:BAAANQAECgQICQAAAA==.Liqudfury:BAAANQADCgYIBgAAAA==.Lishan:BAAANQAECgQIBAAAAA==.Liszandera:BAAANQAECgQIBQAAAA==.Literein:BAAANQAECgYIEAAAAA==.Lizora:BAAANQAECgYICgAAAA==.',
Lo='Lokisan:BAAANQADCgMIAwAAAA==.Lorenei:BAAANQAECgcIDAAAAA==.Los:BAAANQAECgMIBQAAAA==.',
Lt='Ltwhisker:BAAANQAECgYIDAAAAA==.',
Lu='Lucìd:BAAANQADCgcIDQAAAA==.Lucïd:BAAANQAECgYIDAAAAA==.Lunhzae:BAAANQADCgUIBQAAAA==.Lustallo:BAAANQADCgQIBAAAAA==.',
Ly='Lynxx:BAAANQAECgQIBQAAAA==.',
Ma='Macharth:BAAANQAECgUICQAAAA==.Mack:BAAANQAECgcJBgAAAA==.Mad:BAABNQAECoEXAAMPAAgKqSLoCgCiAgAPAAcKCiLoCgCiAgAYAAEKtwagVwAqAAAAAA==.Madchickenz:BAAANQAECgQIDQAAAA==.Magicwithin:BAAANQAECgYIFgAAAQ==.Magut:BAAANQADCgUICAAAAA==.Maira:BAAANQADCgYIFgAAAA==.Maitias:BAAANQADCgUIBQABNQADCgYIBgAOAAAAAA==.Majim:BAAANQAECgUICAAAAA==.Malevolens:BAAANQADCgcIHAAAAA==.Mannyfingers:BAAANQADCgUIBQAAAA==.Marche:BAABNQAECoEcAAIFAAgKvBJSVAAOAgAFAAgKvBJSVAAOAgAAAA==.Marianacross:BAAANQAECgUICQAAAA==.Marsel:BAAANQADCgYIBgAAAA==.Masokist:BAAANQADCgYIBgAAAA==.Mavdk:BAAANQADCggIDgABNQAECgQICAAOAAAAAA==.Mavrar:BAAANQAECgQICAAAAA==.',
Mc='Mcflurrey:BAAANQAECgQICgAAAA==.',
Me='Mechamana:BAAANQADCgYIBgABNQADCggIBQAOAAAAAA==.Meing:BAAANQAECgEIAQAAAA==.Melodrama:BAAANQADCgIIAgAAAA==.Meowrian:BAAANQAECgMIAwAAAA==.Mephïsto:BAAANQAECgEIAQAAAA==.Mereoleona:BAAANQAECgcIEwAAAA==.Messdupjuf:BAAANQADCggJCAABNQAECggIJgAKANkmAA==.Messdupllama:BAABNQAECoEmAAIKAAgK2SZmBQCfAwAKAAgK2SZmBQCfAwAAAA==.Metamorfasis:BAAANQAECgYIEQAAAA==.',
Mi='Micos:BAAANQAECgIIAgAAAA==.Microburst:BAAANQAECgYIDgAAAA==.Microcharge:BAAANQADCgUIBQABNQAECgYIDgAOAAAAAA==.Miischief:BAAANQAECgMIBQAAAA==.Milkman:BAAANQADCggIFAAAAA==.Misslynn:BAAANQAECgQJBQAAAA==.Missmoodý:BAAANQAECgEJAQAAAA==.Missqwerty:BAAANQAECgEIAQAAAA==.Mizari:BAAANQABCgEIAQAAAA==.',
Mo='Moltenbeast:BAAANQAECgYIBwABNQAECggIBgAOAAAAAA==.Mongargiss:BAAANQAECgMIBAAAAA==.Mongoth:BAAANQADCgcIDAAAAA==.Montaro:BAAANQAECgMIBQAAAA==.Morbidi:BAAANQAECgEIAQAAAA==.Moreithe:BAAANQADCggICAAAAA==.Mortharos:BAAANQAECgMIBQAAAA==.',
Mu='Mudkip:BAACNQAFFIETAAIeAAUKfxWtBACkAQAeAAUKfxWtBACkAQA1AAQKgTMAAh4ACQorJHMCAKkDAB4ACQorJHMCAKkDAAAA.Munnsta:BAAANQAECgYIEQAAAA==.Muskan:BAAANQADCggIDgAAAA==.',
My='Mylanara:BAABNQAECoEcAAIgAAgKUxmdBQBwAgAgAAgKUxmdBQBwAgAAAA==.Mysticah:BAAANQAECgMIAwAAAA==.Mythalagos:BAAANQADCgEIAQAAAA==.Mythblast:BAAANQAECgEJAgAAAA==.Myvrth:BAAANQAECgEIAQAAAA==.',
['Mä']='Märs:BAACNQAFFIEGAAIQAAQK2RqDCwBSAQAQAAQK2RqDCwBSAQA1AAQKgSYAAhAACQpBIUIQACUDABAACQpBIUIQACUDAAAA.',
Na='Naelu:BAAANQADCgMIAwAAAA==.Nanr:BAABNQAECoEcAAQQAAgKPg3tRwB6AQAQAAcKvAztRwB6AQATAAQKIxRMNgD/AAASAAMKIQqKMACGAAAAAA==.Nathi:BAAANQAECgEIAQAAAA==.Navori:BAACNQAFFIEGAAIYAAQKeAcoBwAJAQAYAAQKeAcoBwAJAQA1AAQKgRoAAhgACAofGz4YADICABgACAofGz4YADICAAAA.Nazeera:BAEANQADCggICAABNQAECgEIAQAOAAAAAA==.Nazeraz:BAAANQAECgUIDAAAAA==.',
Ne='Necrokinesis:BAAANQAECgEJAQAAAA==.Nerve:BAAANQAECgcIEAAAAA==.Nesiryn:BAAANQADCgYIEAAAAA==.Neth:BAAANQAECgYICwAAAA==.Neuroshots:BAAANQAECgIIBgAAAA==.Newkers:BAAANQADCgUICQAAAA==.',
Ni='Nightknight:BAAANQADCgQIBwAAAA==.Nightràven:BAABNQAECoEcAAMhAAgKLRSoBQAJAgAhAAcKmRSoBQAJAgAKAAUKtQuItwAoAQAAAA==.Nijitani:BAAANQADCgcIDQAAAA==.Nimrodd:BAAANQAECgQIBQAAAA==.',
No='Nobby:BAAANQADCgUICgAAAA==.Noogan:BAAANQADCgYIBgAAAA==.Nosferatü:BAAANQADCgUJBQAAAA==.Nothotdog:BAAANQADCgIIAgAAAA==.Novacat:BAABNQAECoElAAITAAkKOR9rBwAjAwATAAkKOR9rBwAjAwAAAA==.Novangel:BAAANQADCgYIBgAAAA==.November:BAAANQAECgUIDAAAAA==.Nox:BAAANQADCggIDAAAAA==.',
Nu='Nubriss:BAAANQAECgYIDQAAAA==.Nudetayne:BAAANQADCgQJBAAAAA==.Nuitsguard:BAABNQAECoEmAAQCAAkKxBvaHwC1AgACAAkKxBvaHwC1AgAdAAUKhgx+GwA4AQADAAIK+Qzq2QBtAAAAAA==.Nunnaly:BAAANQAECgYIBgAAAA==.',
Ny='Nyaboron:BAAANQAECgcIEwAAAA==.Nyv:BAAANQADCggICAABNQAECgQIBAAOAAAAAA==.',
['Nè']='Nèaner:BAABNQAECoEfAAIaAAgKgwijYQCWAQAaAAgKgwijYQCWAQAAAA==.',
Og='Oggden:BAAANQAECgUICwAAAA==.Ogrebane:BAAANQAECgYIDwAAAA==.',
Oi='Oiheg:BAABNQAECoEbAAIHAAgKEhyACAB9AgAHAAgKEhyACAB9AgAAAA==.',
Or='Oriha:BAAANQADCgYIBgAAAA==.',
Pa='Pajamasniper:BAAANQAECgQICAAAAA==.Pantheon:BAAANQAECgMIAwAAAA==.Parttimebear:BAAANQADCgEIAQABNQAECggIFgACAOYgAA==.',
Pe='Peach:BAABNQAECoEUAAIiAAYK8CT3KQCJAgAiAAYK8CT3KQCJAgAAAA==.Peppermint:BAAANQADCgcIBwAAAA==.Perlita:BAAANQADCgQJBAAAAA==.',
Ph='Phoephoe:BAAANQADCgMIAwABNQAECgUIDAAOAAAAAA==.Photos:BAAANQAECgYIEgAAAA==.',
Pi='Pigums:BAABNQAECoEWAAICAAgK5iDxFgDrAgACAAgK5iDxFgDrAgAAAA==.',
Pl='Plugbae:BAAANQADCgMIAwAAAA==.Pluug:BAAANQAECgcIDAAAAA==.',
Po='Poleo:BAAANQADCggICAAAAA==.',
Pr='Prayer:BAABNQAECoEaAAMBAAgKviVxEABqAwABAAgKviVxEABqAwAiAAEKtRV96wA5AAABNQADCgcIBwAOAAAAAA==.Prayered:BAAANQAECgQIBAABNQAECgUICwAOAAAAAA==.Prîde:BAAANQADCgYIBwAAAA==.',
Ps='Psycopath:BAAANQAECgYIEwAAAA==.Psygn:BAAANQADCgUIBQABNQAECgYIFAAMAPEiAA==.Psyloc:BAAANQADCggIFQABNQAECgYIFAAMAPEiAA==.',
Pt='Ptra:BAAANQAFFAIIAgAAAA==.',
Pu='Puddingfarts:BAAANQADCgcIBwAAAA==.Pumpy:BAACNQAFFIEIAAIDAAQKrhjmCQBdAQADAAQKrhjmCQBdAQA1AAQKgR8AAgMACQqhI8kMAGgDAAMACQqhI8kMAGgDAAAA.Purrfessör:BAAANQADCggIBAAAAA==.Purrpally:BAAANQADCgUICQAAAA==.',
Py='Pywacket:BAAANQAECgYICQAAAA==.',
['Pã']='Pãlàdoom:BAAANQADCgUIDgABNQAECggIHAAhAC0UAA==.',
Qa='Qadésh:BAAANQABCgQIBAABNQADCgUIBQAOAAAAAA==.',
Qu='Quendwings:BAEANQAECgUIBQABNQAFFAYIDQATALsVAA==.',
Ra='Rabern:BAAANQADCgIIAgAAAA==.Ragnaclio:BAAANQADCgIJAgAAAA==.Rainsky:BAAANQAECgIIAwAAAA==.Rasmatazz:BAAANQADCgcICQAAAA==.Rayleighh:BAAANQAECgYIEAAAAA==.',
Re='Redemptio:BAAANQAECgcIEwAAAA==.Relerin:BAAANQADCgIIAgAAAA==.Rexxcat:BAAANQAECgQIBAAAAA==.',
Ri='Rikaza:BAAANQADCgcIBgAAAA==.Ristraza:BAAANQADCgIIAgABNQAECgMJBwAOAAAAAA==.',
Ro='Roguewølf:BAAANQADCgQIBgAAAA==.Roono:BAAANQADCgcICgAAAA==.Rosalidia:BAAANQAECgQICQAAAA==.Rosephane:BAAANQADCgUIBQAAAA==.Ross:BAAANQAECgIIAgAAAA==.Rossco:BAAANQAECgEIAQABNQAECgIIAgAOAAAAAA==.Rozoe:BAAANQADCgEJAQAAAA==.Rozzluz:BAAANQAECgYICwAAAA==.',
Ru='Rutira:BAABNQAECoEfAAIjAAgKniOvCgAzAwAjAAgKniOvCgAzAwAAAA==.',
Ry='Ryân:BAAANQADCgMIAwAAAA==.',
['Rê']='Rêcklêss:BAAANQADCgEIAQABNQAECggIHAAhAC0UAA==.',
Sa='Sabbat:BAAANQADCgcJCwAAAA==.Salder:BAAANQADCgYJBgABNQADCggIFAAOAAAAAA==.Sapphiwrath:BAAANQADCgYIFAAAAA==.',
Sc='Scuuzemee:BAAANQAECgEIAQAAAA==.',
Se='Seacow:BAAANQAECgYJBgAAAA==.Searilus:BAAANQAECgMIBQAAAA==.Seethed:BAAANQADCgUJCgAAAA==.Selyana:BAAANQADCggJCAAAAA==.Seylena:BAAANQADCggIHwABNQAECgYIFAAPAB8NAA==.',
Sh='Shadowcrit:BAAANQAECgUICgAAAA==.Shamamma:BAAANQADCgUIBwAAAA==.Shammallamma:BAAANQABCgQIBgAAAA==.Shamæn:BAAANQAECgMIAwAAAA==.Shaphyr:BAAANQAECgQIBgABNQAECgQIDQAOAAAAAA==.Sharphammer:BAAANQADCggIEwAAAA==.Shieldon:BAAANQADCgUIBQABNQAECgUIEAAOAAAAAA==.Shikamarú:BAAANQADCgEIAQAAAA==.Shinhealer:BAAANQAECgEIAQAAAA==.Shiroa:BAAANQAECgIIAwABNQAECgIJBQAOAAAAAA==.Shlapp:BAAANQADCgUJBQAAAA==.Shootsahlot:BAAANQAECgMIAwAAAA==.',
Si='Sidapa:BAAANQADCgYICgAAAA==.Silvernleaf:BAAANQADCggIJAAAAA==.Sinai:BAAANQAECgYIDwAAAA==.Sindir:BAAANQADCgUIBQABNQAFFAQICAATADUeAA==.Sinner:BAAANQAECgUIBQABNQAECgYICAAOAAAAAA==.Siyx:BAAANQAECgMIBAAAAA==.',
Sk='Skept:BAAANQAECgcIEgAAAA==.',
Sl='Sleêp:BAAANQAECgQIBQAAAA==.Slosh:BAABNQAECoEcAAMCAAkKUCLCBwBpAwACAAkKUCLCBwBpAwADAAIKnwY53wBiAAAAAA==.',
Sm='Smellyandfat:BAECNQAFFIENAAMTAAYKuxXeAQAEAgATAAYKuxXeAQAEAgAQAAEKRAAkIgAVAAA1AAQKgTAAAxMACQoxJWMBALQDABMACQoxJWMBALQDABAACAo4HiQhAI4CAAAA.Smerffy:BAAANQAECgYIDgAAAA==.Smites:BAAANQADCgcJEAABNQAECgcIFAABAA4iAA==.',
So='Solise:BAAANQAECgcIDgAAAA==.Somehobo:BAAANQADCgIIAgAAAA==.Sonny:BAABNQAECoEaAAMfAAYKCBuODQCNAQAfAAUKpByODQCNAQAUAAUK+BGV9wBKAQAAAA==.Sorshalynne:BAAANQAECgIIAgAAAA==.Soulhorror:BAABNQAECoEXAAINAAgKDRiGLgAdAgANAAgKDRiGLgAdAgAAAA==.',
Sp='Spiritfire:BAAANQAECgQICgAAAA==.Spitefury:BAAANQAECgMIBgABNQAECggIHQAPAFkQAA==.Spriggs:BAEBNQAECoEhAAIUAAkKVxp5PQDrAgAUAAkKVxp5PQDrAgAAAA==.',
St='Starrfighter:BAAANQADCggICAABNQAECgkJJgACAMQbAA==.Stepfather:BAAANQADCgIIAgAAAA==.Stepmother:BAAANQADCgIIAgAAAA==.Stillblade:BAAANQADCggIBQAAAA==.Stonedread:BAAANQADCgYICwAAAA==.Stormfodder:BAAANQABCgQIBAAAAA==.Stronker:BAAANQADCggICgAAAA==.',
Su='Sungmi:BAAANQAECgYIEAAAAA==.Sunntzu:BAABNQAECoEXAAMkAAcKsBvDCgAmAgAkAAcKsBvDCgAmAgAYAAIKqA7tRwBwAAAAAA==.',
Sw='Swindlle:BAAANQAECgUICwAAAA==.',
Sy='Syber:BAABNQAECoEgAAMTAAgKgxwSDgC4AgATAAgKgxwSDgC4AgAQAAEKCQt7mQAmAAAAAA==.Syberfist:BAAANQABCgQIBAABNQAECggIIAATAIMcAA==.Syberstyx:BAAANQADCgQIBAABNQAECggIIAATAIMcAA==.Sympathy:BAAANQAECgQIBAAAAA==.Symphonica:BAAANQAECgYIEQAAAA==.Syreithis:BAAANQAECgUJBgAAAA==.',
['Sí']='Síd:BAABNQAECoEbAAMbAAgKTxUZHgA2AgAbAAgKTxUZHgA2AgAcAAUKvguCLQAcAQAAAA==.',
Ta='Tacofighter:BAAANQAECgYIEgAAAA==.Taerielle:BAABNQAECoEqAAIfAAkKJRuAAwDPAgAfAAkKJRuAAwDPAgAAAA==.Tageren:BAAANQADCgYIEAAAAA==.Taldim:BAAANQADCgUIBQABNQAECgYIFAAMAPEiAA==.Taliah:BAAANQADCgcJDQAAAA==.Tarhos:BAAANQABCgIIBgAAAA==.Tarò:BAABNQAECoEoAAIaAAkKmgsUUQDZAQAaAAkKmgsUUQDZAQAAAA==.Taychi:BAAANQAECgIIAgABNQAECggIFgAJAAgQAA==.',
Te='Teacupps:BAACNQAFFIEEAAMGAAMKkwouDAChAAAGAAIKdAsuDAChAAAFAAEK0Qh5LwBLAAA1AAQKgR8AAwYACQqqHfYRANYBAAUABwqsGpVXAAMCAAYABwoeFvYRANYBAAAA.Teegan:BAAANQAECgQIDQABNQAECgUIEwAOAAAAAA==.Tekloa:BAAANQADCgUIBQAAAA==.Telvissra:BAABNQAECoElAAINAAkKzRz1FgDLAgANAAkKzRz1FgDLAgAAAA==.Temporary:BAAANQAECgEIAQAAAA==.Teoritta:BAAANQAECgYIDwAAAA==.Terrisher:BAAANQAECgcIDwAAAA==.',
Th='Thaljadrak:BAAANQADCgQIBwAAAA==.Thermopalea:BAAANQADCgUICgAAAA==.Thetamoon:BAABNQAECoEUAAIKAAYK4xerdgDFAQAKAAYK4xerdgDFAQAAAA==.Thorald:BAAANQAECgUIDQAAAA==.Thordh:BAAANQAECgYIBgAAAA==.Thorggon:BAABNQAECoEbAAMHAAkKnyLcAQCDAwAHAAkKnyLcAQCDAwAIAAEKiBbqDAFIAAAAAA==.Thornbeast:BAAANQAECgQIBgAAAA==.Thuato:BAAANQADCgQICAAAAA==.Thundermayne:BAAANQAECgEJAQAAAA==.Thád:BAAANQAECgYIDgAAAA==.',
Ti='Tiranoc:BAAANQADCgcJCQABNQAECgYIEwAOAAAAAA==.',
To='Tojara:BAAANQADCgcIBwAAAA==.Toxique:BAAANQAECgIIAgAAAA==.',
Tr='Trappist:BAAANQADCgMIAwAAAA==.Travelocitee:BAAANQAECgYICgAAAA==.Triskalyn:BAAANQAECgEJAQAAAA==.Trojanhorse:BAAANQADCggIIAAAAA==.Trokosan:BAAANQAECgQJBAAAAA==.Trustissues:BAAANQADCggIFgAAAA==.Try:BAACNQAFFIEMAAIdAAYKHR6ZAAA5AgAdAAYKHR6ZAAA5AgA1AAQKgSMAAh0ACQp9JioBAK0DAB0ACQp9JioBAK0DAAAA.Trybu:BAABNQAECoErAAIUAAkKNCAhJAA3AwAUAAkKNCAhJAA3AwAAAA==.Tryiss:BAAANQAECgIJAgAAAA==.',
Tt='Ttryss:BAAANQADCgUIBQAAAA==.',
Tu='Tubslumpkin:BAAANQAECgIIAgAAAA==.Tuketu:BAABNQAECoEeAAIQAAgK0g3MOgDMAQAQAAgK0g3MOgDMAQAAAA==.Turtlelord:BAABNQAECoEdAAIFAAcK9BaMYQDjAQAFAAcK9BaMYQDjAQAAAA==.',
Ty='Tylarion:BAAANQAECgQIBAAAAA==.Tylendal:BAABNQAECoEaAAILAAgK7g1ZFADFAQALAAgK7g1ZFADFAQAAAA==.Tylenolz:BAAANQAECgQIBAAAAA==.Tylenulz:BAAANQAECgQIDAAAAA==.Tylheras:BAAANQAECgcIDAAAAA==.Tyliera:BAAANQADCgcICAAAAA==.Tylren:BAAANQAECgMIAwAAAA==.',
['Tà']='Tànya:BAAANQAECgUIDQAAAA==.',
Un='Undbaxi:BAAANQADCgQIBQAAAA==.Unfàthømable:BAAANQADCggICAABNQAECggIHAAhAC0UAA==.',
Ut='Uthercito:BAAANQADCggICQAAAA==.',
Va='Vallarath:BAAANQAECgYICwAAAA==.Valtaran:BAAANQAECgEIAQAAAA==.Valtarr:BAAANQAECgYIEwAAAA==.Vampirism:BAABNQAECoEXAAIMAAcKKBRBQgCxAQAMAAcKKBRBQgCxAQAAAA==.Vasira:BAAANQAECgIIAgAAAA==.Vaulthunter:BAAANQAECgQIBAAAAA==.',
Ve='Vecna:BAAANQADCgMIBQAAAA==.Veina:BAAANQAECgYICwAAAA==.Veloril:BAAANQADCggIFAAAAA==.Vespicey:BAAANQADCggICAAAAA==.Vethena:BAAANQAECgQIBQAAAA==.Vezahk:BAAANQADCgEIAQAAAA==.',
Vi='Vidu:BAABNQAECoEUAAMPAAYKHw0rIQAqAQAPAAYKHw0rIQAqAQAYAAUKrhEcMgAWAQAAAA==.Vikas:BAAANQADCgYIBgAAAA==.Vivitrix:BAAANQAECgEJAQAAAA==.Viví:BAAANQAECgUIEgAAAA==.',
Vl='Vlm:BAAANQAECgUICAAAAA==.',
Vo='Voidbreaker:BAAANQAECggIEgAAAA==.Vordis:BAAANQAECgQIBQABNQAECgYIBgAOAAAAAA==.Vordissia:BAAANQAECgYIBgAAAA==.Voxis:BAAANQAECgQIBAAAAA==.',
Vv='Vv:BAAANQAECgUIDAAAAA==.',
Vy='Vyrande:BAAANQADCggICAAAAA==.Vyrstal:BAAANQADCggICAABNQAECgcIGgAGAPwHAA==.',
Wa='Wardan:BAAANQAECgIIAgAAAA==.',
We='Weavile:BAAANQADCgUIBQABNQAFFAUIEwAeAH8VAA==.Wef:BAAANQADCggJHgAAAA==.Weirdtotem:BAABNQAECoEiAAMDAAkKWB7SHgDfAgADAAgKlyHSHgDfAgACAAcKZhyVOwApAgAAAA==.Westylad:BAABNQAECoEXAAMIAAcKFSCmRgB6AgAIAAcKFSCmRgB6AgAgAAUK8BpeDgB3AQAAAA==.Westyladd:BAAANQADCggICAAAAA==.Wetrat:BAAANQAECgUIBQABNQAFFAQICAADAK4YAA==.',
Wh='Whatthefunk:BAAANQADCgUICgAAAA==.',
Wi='Winterfox:BAAANQADCgYICQAAAA==.Winters:BAAANQADCgMIAwAAAA==.',
Wo='Woodybax:BAAANQAECgQIBAAAAA==.',
Wr='Wrystal:BAABNQAECoEaAAMGAAcK/AdnHwBhAQAGAAcK/AdnHwBhAQAFAAEKqQI/HgEaAAAAAA==.',
Xa='Xannaa:BAAANQADCgIJAgAAAA==.',
Xe='Xernes:BAAANQADCgQIBAAAAA==.',
Xu='Xujian:BAAANQAECgMIAwAAAA==.',
Ya='Yakiki:BAAANQADCgcIBwABNQAFFAQIBwAeAC8eAA==.',
Yu='Yuma:BAAANQAECgEIAQABNQAECgUIDQAOAAAAAA==.',
Za='Zaelenia:BAAANQAECgUICwAAAA==.Zaerel:BAAANQADCgMIAwAAAA==.Zalen:BAAANQAECgcIEAAAAA==.Zappylad:BAAANQAECgMIAwAAAA==.Zarelle:BAAANQAECgEIAQAAAA==.Zartoon:BAAANQADCgcIBwAAAA==.',
Ze='Zenamani:BAAANQAECgUJBQAAAA==.Zenetha:BAAANQAECgUIDAAAAA==.Zephyres:BAABNQAECoEcAAMQAAkKHyXVBACkAwAQAAkKHyXVBACkAwASAAYKrSS3CACCAgABNQAFFAUIDQAIAHwfAA==.Zerokool:BAAANQABCgYIBgABNQAECgcICQAOAAAAAA==.Zevarya:BAAANQAECgEIAQAAAA==.',
Zo='Zonksmoose:BAAANQADCgYICgAAAA==.Zonkspaladin:BAABNQAECoEkAAIiAAkK3hxgFgD6AgAiAAkK3hxgFgD6AgAAAA==.Zornac:BAAANQAECgIIAgAAAA==.',
Zp='Zpyder:BAAANQAECgUICQAAAA==.',
Zy='Zynskie:BAAANQAECgcIEQAAAA==.Zyraa:BAAANQADCgIIAQAAAA==.',
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
