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

local lookup = {'Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Mage-Arcane','Mage-Frost','Priest-Shadow','Monk-Brewmaster','Rogue-Subtlety','Shaman-Restoration','Hunter-Marksmanship','Druid-Balance','Warrior-Fury','Warrior-Protection','Paladin-Holy','Warrior-Arms','Monk-Mistweaver','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Paladin-Retribution','Warlock-Affliction','Hunter-BeastMastery','DemonHunter-Havoc','Rogue-Assassination','Priest-Holy','Priest-Discipline','DemonHunter-Devourer','Monk-Windwalker','Paladin-Protection',}
local provider = {region='US',realm='Turalyon',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Absorb:BAAANQAECgMIBQABNQAECgYICwABAAAAAA==.',
Ac='Aconcerious:BAAANQAECgUICgAAAA==.Actionbztrd:BAAANQAECgUICgAAAA==.',
Ad='Addlee:BAAANQAFFAEIAQAAAA==.Addler:BAAANQADCggICQAAAA==.Aduro:BAAANQAECgQIBwAAAA==.',
Ae='Aeleleroesh:BAAANQABCgIIAgABNQABCgQIBAABAAAAAA==.Aeolyte:BAAANQAECgUIBwAAAA==.Aeradeath:BAABNQAECoEWAAQCAAgJuSGZIAA1AgACAAgJHhWZIAA1AgADAAcJ0RrmFQD2AQAEAAUJEyOwJAD1AQAAAA==.Aeronir:BAAANQAECgcIEQAAAA==.',
Ah='Ahlis:BAAANQAECgEIAQAAAA==.',
Ak='Akabaggins:BAAANQADCggIFAAAAA==.',
Al='Alacrys:BAAANQAECgQIBAAAAA==.Aldyrían:BAAANQADCgQIBgAAAA==.Alear:BAAANQAECgQIBAAAAA==.Alessie:BAAANQAECgMIAwAAAA==.Alltreg:BAAANQAECgEIAQAAAA==.Alrir:BAAANQADCggIFAAAAA==.Alyrii:BAAANQADCgQIBAABNQAECgQIBwABAAAAAA==.',
Am='Ambrose:BAAANQADCgcIBwAAAA==.Amelyn:BAAANQAECgQIBQAAAA==.Amrén:BAAANQAECgYIEQAAAA==.',
An='Angriff:BAAANQAECgUICAAAAA==.Angusmcrizle:BAAANQAECgQIBQAAAA==.Ankalagon:BAAANQAECgQIBAAAAA==.',
Ar='Aranjah:BAAANQADCgYIDAAAAA==.Ardius:BAAANQAECggIEAAAAA==.Arenaria:BAAANQAECgEIAQAAAA==.Arishokk:BAAANQAECgQICAAAAA==.Arks:BAABNQAECoEXAAMFAAkJvxhsPQCcAgAFAAkJrxdsPQCcAgAGAAEJkiGjIABNAAAAAA==.Arkthugal:BAAANQAECgYIDAAAAA==.Arktwogal:BAAANQADCgEIAQABNQAECgYIDAABAAAAAA==.Arteezer:BAAANQADCgcIBwABNQAECgkJHQAHAGsVAA==.Artemiye:BAAANQAECgMIBAAAAA==.Artikblaz:BAAANQADCggIEgAAAA==.Arun:BAAANQADCgYIBgAAAA==.Arés:BAAANQAECgQIBgAAAA==.',
As='Ashieldu:BAAANQADCggIGgAAAA==.Ashkikur:BAAANQADCgYIBgAAAA==.Askanni:BAAANQAECgQIBgAAAA==.Astharot:BAAANQAECgQICwAAAA==.Astralain:BAAANQAECgQIBAAAAA==.Astrozen:BAAANQADCgUIBQAAAA==.Asture:BAAANQADCgUIBQAAAA==.',
At='Atulmoji:BAAANQAECgEIAQAAAA==.',
Au='Augdra:BAAANQADCggIEgAAAA==.Auriauna:BAAANQAECgMIAwAAAA==.',
Av='Avadagryth:BAAANQAECgQIBgAAAA==.Avanyani:BAAANQADCggIEwAAAA==.Avidowned:BAAANQADCggIBwAAAA==.',
Ay='Ayllo:BAAANQAECgEIAQAAAA==.',
Ba='Bacalhau:BAAANQAECgEIAQABNQAECgQIDQABAAAAAA==.Baelgoroth:BAAANQAECgUICgAAAA==.Barachiel:BAAANQAECgUICQAAAA==.Basheaba:BAAANQAECgcIEwAAAA==.Batrous:BAAANQADCgYIBgAAAA==.Battlerbrian:BAAANQABCgMIAwAAAA==.Bayale:BAAANQAECgIIAgAAAA==.',
Be='Belandra:BAAANQAECgYICwAAAA==.Belegond:BAAANQADCgcIBwAAAA==.Belishario:BAAANQAECgYIDAAAAA==.Belladawna:BAAANQAECgYIEQAAAA==.Bellatrex:BAAANQADCgEIAQAAAA==.Bereid:BAAANQADCggIDgABNQAECgEIAgABAAAAAA==.Berejitsu:BAAANQADCgQIBQABNQAECgEIAgABAAAAAA==.Beârback:BAEANQAECggIBQAAAA==.',
Bi='Bigchops:BAAANQAECgMIAwAAAA==.Bigfuzzy:BAAANQADCggIFQAAAA==.Bigtime:BAAANQADCgYIBgAAAA==.Bigwillie:BAAANQAECgQICwAAAA==.',
Bl='Blazerbrew:BAAANQAECgUICwAAAA==.Blezaa:BAAANQAECgUIBwAAAA==.Blinknleap:BAAANQAECgcIEgAAAA==.Blooddrakken:BAAANQADCggIFwAAAA==.Bloodoxel:BAAANQADCgQIBgAAAA==.',
Bn='Bn:BAAANQAECgIIAgAAAA==.',
Bo='Boring:BAAANQAECgcIDwAAAA==.Boxlunch:BAAANQADCgYIBgABNQAECgcIDgABAAAAAA==.Boyana:BAAANQADCgcICwAAAA==.',
Br='Brandybuck:BAAANQADCgcIEgAAAA==.Brucelééroy:BAAANQAECgEIAQAAAA==.Bruski:BAAANQABCgEIAQAAAA==.Bruskii:BAAANQAECgUICgAAAA==.',
Bu='Bulsharess:BAAANQADCgQIBAAAAA==.Bulshari:BAAANQADCgUIBQAAAA==.Bunns:BAAANQADCgcIDQAAAA==.Burningrash:BAAANQADCgYIDwAAAA==.Butternugget:BAAANQAECgQIBAAAAA==.Buuffy:BAAANQAECgIIAgAAAA==.',
By='Byleana:BAAANQADCggIDgABNQAECggIGQAEAPobAA==.Byléana:BAABNQAECoEZAAIEAAgJ+htmFwBuAgAEAAgJ+htmFwBuAgAAAA==.Bytem:BAAANQAECgQIBAAAAA==.',
Ca='Caewyn:BAAANQADCggIFAAAAA==.Calysta:BAAANQAECgIIAgAAAA==.Candalen:BAAANQABCgYIBgAAAA==.Carleys:BAAANQAECgYICAAAAA==.Cassara:BAAANQAECgEIAQAAAA==.Cathella:BAAANQADCgYICQAAAA==.',
Ce='Ceberus:BAAANQADCgUIBQAAAA==.Celek:BAAANQAECggICAAAAA==.Celekai:BAAANQAECgQICAABNQAECggICAABAAAAAA==.Celi:BAAANQAECgQICAAAAA==.Celébrin:BAAANQABCgIIAgAAAA==.Cerandan:BAAANQABCgQIBAAAAA==.Cerbadin:BAAANQAECgEIAQABNQAECgUIBwABAAAAAA==.Cerbyhunt:BAAANQAECgUIBwAAAA==.Cerbymage:BAAANQADCgIIAgABNQAECgUIBwABAAAAAA==.Cerbywar:BAAANQADCgcIBwABNQAECgUIBwABAAAAAA==.',
Ch='Cheeana:BAAANQAECgQIBAAAAA==.Cherlindrea:BAAANQAECgMIBAABNQAECgcIEAABAAAAAA==.Chhive:BAAANQAECgQIBAAAAA==.Chickenstrip:BAAANQADCgQIBwAAAA==.Chopchop:BAAANQADCgYICwAAAA==.Chrysus:BAAANQADCgYIBgAAAA==.',
Ci='Cidal:BAAANQAECgEIAQAAAA==.Cindii:BAAANQADCgcICwAAAA==.',
Cl='Clada:BAAANQAECgQICwAAAA==.Clancy:BAAANQAECgEIAQAAAA==.Cleric:BAAANQAECgEIAQAAAA==.Clifmantooth:BAAANQADCggIDAAAAA==.',
Co='Coldkiller:BAAANQADCggICAAAAA==.Coneau:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Couprenarde:BAAANQADCgMIAwABNQAECgcIEAABAAAAAA==.Courpsie:BAAANQAECgYIDAAAAA==.Courtvoke:BAAANQADCgEIAQABNQAECgcIDwABAAAAAA==.',
Cr='Crager:BAAANQAECgEIAQAAAA==.Creamygees:BAAANQAECgcIDAAAAA==.Creaturé:BAAANQADCgYICwAAAA==.Criaharn:BAAANQAECgUIBQAAAA==.Cripp:BAAANQAECgIIAgAAAA==.Crybeardin:BAAANQAECgYICAABNQAECgcIDQABAAAAAA==.Cryohunter:BAAANQAECgQICAAAAA==.',
Ct='Ctair:BAAANQAECgUICQAAAA==.',
Cu='Cuckcommando:BAAANQADCgIIAgABNQAFFAMIBgAIAKAOAA==.',
Cy='Cybersorc:BAAANQADCggIFQAAAA==.Cybrhexx:BAEANQADCgcIBgABNQAECgYIDwABAAAAAA==.Cyrce:BAAANQADCgYIBgAAAA==.Cyrs:BAAANQAECgQIBAAAAA==.Cysvarion:BAAANQADCggIEgAAAA==.',
['Có']='Ców:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.',
['Cø']='Cønø:BAAANQAECgIIAgAAAA==.',
Da='Daddi:BAAANQAECgYICwAAAA==.Dairs:BAAANQAECgEIAQAAAA==.Dalitha:BAAANQADCggICAABNQAECgcIEAABAAAAAA==.Daltan:BAAANQAECgMIAwABNQAECgMIAwABAAAAAA==.Damukovu:BAAANQAECgEIAQAAAA==.Danayro:BAAANQAECgYICwAAAA==.Dandron:BAAANQAECgYICQAAAA==.Dankmeme:BAAANQAECgQIBgAAAA==.Darc:BAAANQADCgMIAwAAAA==.Darksath:BAAANQADCgMIAgAAAA==.Darkvag:BAABNQAECoEYAAMGAAgJWSFsBQD0AQAGAAYJhBtsBQD0AQAFAAUJeh72hwC2AQAAAA==.Davalos:BAAANQAECgUICAAAAA==.Davepark:BAAANQADCgUIBQAAAA==.Davos:BAAANQADCgQIBgAAAA==.Daygos:BAAANQAECggIEQAAAA==.Daêmon:BAAANQADCggIFQAAAA==.',
De='Deadsparks:BAABNQAECoEbAAICAAgJViHyDQD0AgACAAgJViHyDQD0AgAAAA==.Deftech:BAABNQAECoEXAAIJAAkJ3SOkAADUAwAJAAkJ3SOkAADUAwAAAA==.Demonic:BAAANQAECgEIAQAAAA==.Demonrocket:BAAANQAECgIIAgAAAA==.Derisive:BAAANQADCgcIBwABNQAECgYICgABAAAAAA==.Devilslayery:BAAANQAECgQICAAAAA==.',
Dh='Dharien:BAAANQAECgcIDQAAAA==.',
Di='Diamondbob:BAAANQADCgEIAQAAAA==.Digbicktus:BAAANQAECgIIAgAAAA==.Direheart:BAAANQAECgEIAQAAAA==.',
Do='Dommothop:BAACNQAFFIEKAAIJAAcJOiIYAADmAgAJAAcJOiIYAADmAgA1AAQKgSMAAgkACQmhJiIAAAYEAAkACQmhJiIAAAYEAAAA.Dorp:BAAANQAECgYIBwAAAA==.Dovahbruh:BAAANQABCgYIBgAAAA==.',
Dr='Dragdon:BAAANQAECgQIBAABNQAECgQIBgABAAAAAA==.Dragosangue:BAAANQADCgcIFgABNQADCggIFwABAAAAAA==.Dragundeez:BAAANQAECgIIAwABNQAECgkJKAAKAJwgAA==.Drakebeard:BAAANQAECgcIDAAAAA==.Drayus:BAAANQAECgQIBgAAAA==.Driitz:BAAANQAECgYIDAAAAA==.',
Du='Duvoh:BAAANQAECgUICwAAAA==.',
Dw='Dweezilla:BAAANQAECgMIAwAAAA==.',
Ea='Easimode:BAAANQADCgYIBgAAAA==.Eatswutsdead:BAAANQADCgYIBgAAAA==.',
Ec='Echarrial:BAAANQADCgYICgAAAA==.Eclipsweaver:BAAANQABCgIIAgAAAA==.',
Ed='Eddias:BAAANQADCgcIBwAAAA==.Edge:BAAANQAECgUICQAAAA==.',
Ek='Eklypsis:BAAANQADCgcIBwAAAA==.',
El='Elang:BAAANQAECgQICAAAAA==.Elange:BAAANQADCgYIBgAAAA==.Elementrix:BAAANQAECgEIAQAAAA==.Elgrandè:BAAANQADCgQIBAAAAA==.Elmafudd:BAAANQAECgIIAgABNQAECgcIEAABAAAAAA==.Elsadieorc:BAAANQADCgcIDwAAAA==.Elvay:BAAANQAECggIDwAAAA==.Elyos:BAAANQADCgcIEwAAAA==.Elzar:BAAANQAECgIIAgAAAA==.',
Em='Emeraldflame:BAAANQADCgMIAwAAAA==.Emodk:BAAANQAECgMIAwABNQAFFAcIEgALAOcfAA==.',
En='Entarri:BAAANQAECgQIBAAAAA==.Entivala:BAAANQADCgYIBgAAAA==.Envoi:BAAANQADCgYIBgAAAA==.',
Eq='Equitem:BAAANQAECgcICQAAAA==.',
Er='Eridanos:BAAANQADCgYICwAAAA==.',
Es='Escanör:BAAANQAECgQIBAAAAA==.Eshel:BAAANQAECgYIEAAAAA==.Eshmel:BAAANQAECgQIBAAAAA==.Essek:BAAANQAECgQICAAAAA==.',
Ev='Everfrost:BAABNQAECoEdAAMFAAkJ7h1pIAATAwAFAAkJ7h1pIAATAwAGAAUJdBNcDAAtAQAAAA==.Evidicus:BAAANQAECgcIDQAAAA==.Evilscarnage:BAAANQAFFAEIAQAAAA==.Evilstotem:BAAANQAECgcIEwAAAA==.Evu:BAAANQAECgcIDgAAAA==.',
Ex='Exkath:BAABNQAECoEbAAIDAAkJYSSWAQCrAwADAAkJYSSWAQCrAwAAAA==.',
Ez='Ezlyn:BAAANQADCggIGgAAAA==.Ezrael:BAAANQADCgcIBwAAAA==.',
Fa='Faedrela:BAAANQAECgQIBwAAAA==.Falito:BAAANQAECgQICAAAAA==.Farben:BAAANQAECgYICQAAAA==.Fatabbot:BAAANQAECgEIAgAAAA==.',
Fe='Felines:BAAANQADCgYICQAAAA==.Felixfenton:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Fellbane:BAAANQADCgYICgAAAA==.Feohh:BAAANQAECgEIAQAAAA==.',
Fi='Fiddlesticks:BAAANQAECgYIEAAAAA==.Findale:BAAANQAECgYIDAAAAA==.',
Fj='Fjalar:BAAANQAECggICwAAAA==.',
Fk='Fkxstvebee:BAAANQABCgUIBQABNQAECgYIEAABAAAAAA==.',
Fl='Flajj:BAAANQAECgUICQAAAA==.Flamezephyr:BAAANQAECgQIEAAAAA==.Flufbuns:BAAANQADCggIFAAAAA==.',
Fo='Foxnews:BAAANQAECgUICwAAAA==.',
Fr='Frackingheal:BAAANQABCgQIBAAAAA==.Fredfazbear:BAABNQAECoEdAAIMAAkJFB7WCgAyAwAMAAkJFB7WCgAyAwAAAA==.Frostystrips:BAAANQADCgcIDAAAAA==.Frozat:BAAANQADCgQIBgAAAA==.Frumdaheart:BAAANQADCgUIBQABNQAECgcIDwABAAAAAA==.',
Fu='Furiza:BAAANQADCgYIBgAAAA==.Furybztrd:BAAANQADCgcIBwAAAA==.',
Ga='Gagno:BAAANQADCgIIAgAAAA==.Gagnot:BAAANQADCgMIAwAAAA==.Galadriál:BAAANQADCgQIBQAAAA==.Garnimal:BAAANQAECgQIBAAAAA==.',
Ge='Georgigeo:BAAANQAECgUICgAAAA==.',
Gh='Ghazkill:BAAANQABCgEIAQAAAA==.Ghostbrue:BAAANQADCggIGwAAAA==.',
Gl='Glacious:BAAANQAECgIIAgAAAA==.Glizygobrice:BAAANQABCgIIAwAAAA==.',
Go='Gong:BAAANQADCgYIBgAAAA==.Goo:BAAANQADCgYIBgAAAA==.Goodbeer:BAAANQAECgMIBwAAAA==.Gouraud:BAAANQAECgIIAgAAAA==.',
Gr='Graeclaw:BAAANQAECgQIBQAAAA==.Grayson:BAABNQAECoEWAAMNAAgJgiBxAQD9AgANAAgJgiBxAQD9AgAOAAIJdBZVHACCAAAAAA==.Greenclaw:BAAANQAECgYIEAAAAA==.Gregoryus:BAAANQADCgUIDwAAAA==.Grosmortfif:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.Gruber:BAAANQADCgcIBwABNQAECgcIEwABAAAAAA==.',
Gu='Gultak:BAAANQAECgEIAQAAAA==.',
['Gô']='Gôósè:BAAANQAECgUICwAAAA==.',
Ha='Hadron:BAAANQAECgQIBQABNQAECggIGAAIACYgAA==.Hairsweater:BAAANQAECgQIBQAAAA==.Hakirai:BAAANQAECgQICAAAAA==.Halje:BAAANQADCggICAAAAA==.Halodin:BAAANQAECgEIAQAAAA==.Harambecast:BAAANQADCggIDwABNQAECgQIBAABAAAAAA==.',
He='Heimdall:BAAANQAECgUIBQAAAA==.Hermóðr:BAAANQAECgIIAgABNQAECgkJFwAFAL8YAA==.Hexan:BAAANQAECgUICgAAAA==.Hexun:BAAANQABCgIIAgAAAA==.',
Hi='Hirumaredx:BAAANQAECgQIBQAAAA==.',
Ho='Hobbsies:BAAANQAECgUIBQAAAA==.Hobkins:BAAANQAECgcIEwAAAA==.Holcon:BAAANQAECgIIAgAAAA==.Holiussy:BAAANQADCgQIBAABNQAECgkJKAAKAJwgAA==.Hollypops:BAAANQAECgMIBQAAAA==.Holybeau:BAABNQAECoEZAAIPAAgJnB6sEQDUAgAPAAgJnB6sEQDUAgAAAA==.Holybo:BAAANQADCggIBwABNQAECggIFgABAAAAAQ==.Holyhex:BAAANQABCgQIBQAAAA==.Holywars:BAAANQAECgUIBQAAAA==.Holywdundead:BAAANQAECgMIBAAAAA==.',
Hu='Hula:BAAANQAECgMIAwAAAA==.',
Hy='Hypercat:BAAANQAECgYICgAAAA==.Hyriel:BAAANQADCgcIFAAAAA==.',
['Hú']='Húnts:BAAANQAECgQICAAAAA==.',
Ia='Iambbq:BAAANQAECgYIEAAAAA==.',
Ib='Ibuprofen:BAAANQADCgcICgAAAA==.',
Ic='Iceblades:BAAANQADCgMIAwAAAA==.Icyclo:BAAANQADCgQIBgAAAA==.',
Id='Idioterroors:BAAANQADCgIIAgAAAA==.',
Ig='Igraine:BAAANQAECgIIAgAAAA==.',
Il='Illidarios:BAAANQAECgMIBAABNQAECgQIBwABAAAAAA==.Ilostmybible:BAAANQAECgIIAgAAAA==.',
Im='Imakeupuddin:BAABNQAECoEcAAIQAAkJPiIwCQCFAwAQAAkJPiIwCQCFAwAAAA==.',
In='Indydevteam:BAAANQAECgIIBAAAAA==.Inffected:BAAANQAECgQIBAAAAA==.Inflames:BAAANQAECgEIAQABNQABCgEIAQABAAAAAA==.Inglëwood:BAAANQADCgYIFAAAAA==.',
Is='Isasabotage:BAAANQAECgIIBAAAAA==.Isult:BAAANQAECgIIAgAAAA==.',
Iv='Iv:BAAANQAECgMIAwAAAA==.',
Ix='Ixthyr:BAABNQAECoEZAAIQAAgJQCBuGwDzAgAQAAgJQCBuGwDzAgABNQAECgkJHAADAAAgAA==.',
Ja='Jaenaa:BAAANQAECgYIDQAAAA==.Jahrobi:BAAANQAECgYIEAAAAA==.Jakqua:BAAANQABCgIIAgABNQAECgYIDQABAAAAAA==.Jaselyn:BAAANQAECgcIDQAAAA==.Jaskryt:BAAANQADCgQIBAABNQAECgcIDwABAAAAAA==.Jaslyn:BAAANQADCgMIBQAAAA==.Jaxsen:BAAANQADCggIFAAAAA==.',
Je='Jelibean:BAAANQADCggICAAAAA==.Jensei:BAAANQAECgcIEAAAAA==.',
Jh='Jheina:BAAANQAECgYIEAAAAA==.Jheirazlynn:BAAANQABCggIBgABNQAECgYIEAABAAAAAA==.',
Ji='Jimmyvrr:BAAANQAECgUIDwAAAA==.Jinnô:BAABNQAECoEZAAIRAAgJeR7dBgCxAgARAAgJeR7dBgCxAgAAAA==.Jizzelda:BAAANQADCgcIEAAAAA==.',
Jo='Joqi:BAAANQADCggIBwAAAA==.',
Ju='Jubzie:BAAANQAECgQIBAAAAA==.Jubzy:BAAANQAECgYICAAAAA==.Judgment:BAAANQADCgYIBgAAAA==.Justwin:BAAANQAECgMIBgAAAA==.',
['Jå']='Jåckx:BAAANQADCgQIBAAAAA==.',
Ka='Kaarnu:BAAANQAECgQIBwAAAA==.Kageman:BAAANQAECgQIBAAAAA==.Kakon:BAAANQAECgIIAwAAAA==.Kamikrazi:BAAANQADCgEIAQAAAA==.Kapuna:BAAANQAECgEIAgAAAA==.Karaglaz:BAAANQAECgUICQAAAA==.Karalea:BAABNQAECoEXAAMFAAgJ2B99TgBhAgAFAAcJGB99TgBhAgAGAAEJGyXFHABjAAAAAA==.Katalene:BAAANQADCgUIBQABNQAECgcIEAABAAAAAA==.Kazaganthis:BAAANQADCgcIDQAAAA==.Kazstorius:BAAANQAECgUICQAAAA==.',
Ke='Kellbell:BAAANQAECgEIAQAAAA==.Kertug:BAAANQAECgMIBAAAAA==.Keturonium:BAAANQAECgQIBgAAAA==.Kevdk:BAAANQAECgMIBQAAAA==.',
Kh='Khary:BAAANQABCgYIBAAAAA==.Kharzaette:BAAANQAECgYIEAAAAA==.Khristo:BAAANQAECgcIDgAAAA==.',
Ki='Kiing:BAAANQAECgUIDAAAAA==.Kikwi:BAAANQAECgIIAgAAAA==.Kioshi:BAAANQAECgYICwAAAA==.Kirayamató:BAAANQAECgUICAAAAA==.Kitmeup:BAAANQADCgEIAgAAAA==.Kiyofu:BAAANQAECgQICAAAAA==.',
Kn='Knew:BAAANQAECggICwAAAA==.Knotagan:BAAANQAECgIIAgAAAA==.',
Ko='Koriol:BAAANQADCggICAAAAA==.Korkron:BAABNQAECoEoAAMKAAkJnCAlBgBUAwAKAAkJnCAlBgBUAwASAAEJTw7JqgBHAAAAAA==.Kovian:BAAANQADCgIIAgAAAA==.Kozmikboom:BAAANQAECgEIAQAAAA==.',
Kr='Krackster:BAAANQADCgMIAwABNQADCgQIBAABAAAAAA==.Krakow:BAAANQABCgYICAAAAA==.Krezan:BAAANQADCgcIDQAAAA==.Krix:BAAANQAECgQIBAABNQADCgYIBgABAAAAAA==.Krolo:BAAANQADCgYIDAABNQAECgUICAABAAAAAA==.',
Ku='Kutkala:BAAANQADCgEIAQAAAA==.',
Ky='Kyndrine:BAAANQADCgMIAwABNQADCggIFAABAAAAAA==.Kyrja:BAAANQAECgMIBAAAAA==.Kytti:BAAANQAECgIIAgAAAA==.',
La='Ladorin:BAAANQADCgYICwAAAA==.Lahallia:BAAANQAECgcIEQAAAA==.Laiellarien:BAAANQADCgUIBwABNQAECgcIEAABAAAAAA==.Lamarqt:BAAANQADCggICAAAAA==.Landrea:BAAANQADCggIAgAAAA==.Lany:BAAANQADCgEIAQAAAA==.Laran:BAAANQAECgUICAAAAA==.Laupouette:BAAANQAECgUIBwAAAA==.Laurissandra:BAAANQAECgIIAgAAAA==.Lavalley:BAAANQADCgYIBgAAAA==.Lazypanda:BAAANQADCgYICgAAAA==.',
Le='Lerzian:BAAANQADCggICAAAAA==.Lexicage:BAAANQAECgUICQAAAA==.',
Li='Lidd:BAAANQAECgUICgAAAA==.Lightiuz:BAAANQAECgUIDgAAAA==.Lightless:BAAANQABCgYIBgAAAA==.Lightmeat:BAAANQABCggICgAAAA==.Lilshadoww:BAAANQAECgUIAgAAAA==.Livandletdie:BAAANQAECgEIAQAAAA==.Lividchaos:BAAANQABCgMIAwAAAA==.',
Ll='Llalow:BAAANQADCggICAAAAA==.Llalowdh:BAAANQAECgUIDAAAAA==.',
Lo='Lockewynn:BAAANQAECgYIDQAAAA==.Lockjawsh:BAABNQAECoEZAAMTAAgJZhmDFACnAQAUAAYJERr3OwDeAQATAAYJWBWDFACnAQAAAA==.Lokuma:BAAANQAECgUICgAAAA==.Lorre:BAAANQADCgQIBgAAAA==.Lot:BAAANQADCggICAAAAA==.Louni:BAAANQAECggIEwAAAA==.',
Lu='Ludo:BAAANQADCgUIDAAAAA==.Lunchbreak:BAAANQAECgcIDgAAAA==.Lunchpunch:BAAANQAECgUIBQABNQAECgcIDgABAAAAAA==.Lunchtime:BAAANQAECgYICQAAAA==.Luot:BAAANQADCgIIAgAAAA==.',
Ma='Machine:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Magias:BAAANQADCgUICgAAAA==.Maglea:BAAANQADCgIIAgAAAA==.Majexs:BAABNQAECoEZAAIVAAgJwx3gHwCnAgAVAAgJwx3gHwCnAgAAAA==.Malady:BAAANQADCggIDQAAAA==.Malfûrion:BAAANQABCgMIAwAAAA==.Malignancy:BAAANQAECgYICwAAAA==.Manalhau:BAAANQAECgQIDQAAAA==.Mandragoran:BAABNQAECoEZAAQQAAgJxhdXPABGAgAQAAgJcBdXPABGAgAOAAcJkxPxCgC9AQANAAEJiAEZIQAVAAAAAA==.Manohar:BAAANQADCgMIAwAAAA==.Manuster:BAAANQAECgQIBAAAAA==.Maradön:BAAANQAECgcIEQAAAA==.Margarida:BAAANQAECgQICAAAAA==.Margaru:BAAANQADCgQIBgAAAA==.Maruknar:BAAANQADCgQIBAAAAA==.Mavd:BAAANQAECgQIBQAAAA==.Mavex:BAAANQADCggICAABNQAECgkJHgAUAI0hAA==.Maximmus:BAAANQAECgYIDAAAAA==.Mayæl:BAAANQADCggIEQAAAA==.Mazerrackham:BAAANQAECgQIBwAAAA==.',
Me='Meesooholyy:BAAANQAECgIIAgAAAA==.Meina:BAAANQAECgIIAgAAAA==.Mellow:BAAANQADCgcIBwABNQAECgQICAABAAAAAA==.Melynia:BAAANQAECgIIAgAAAA==.Mephala:BAAANQAECgUICQAAAA==.Metapig:BAAANQAECgQIBwAAAA==.Mezasu:BAAANQAECgYICwAAAA==.',
Mi='Michaelj:BAAANQAECgQIBAAAAA==.Mikedawson:BAABNQAECoEXAAIWAAgJHhqTAQCtAgAWAAgJHhqTAQCtAgAAAA==.Mikya:BAAANQAECgUICQAAAA==.Milkot:BAAANQAECggIBwAAAA==.Milkys:BAAANQAECgQIBAABNQAECgQICgABAAAAAA==.Mistian:BAAANQAECgYICgAAAA==.Mistpet:BAAANQADCgUIBQABNQADCggICwABAAAAAA==.Mistrbfkx:BAAANQAECgYIEAAAAA==.',
Mo='Moai:BAAANQADCgEIAQAAAA==.Moderñdruið:BAAANQAECgQICAAAAA==.Mojodjin:BAAANQAECgYIBwAAAA==.Molewithwing:BAAANQAECgMIAwAAAA==.Molocko:BAAANQAECgMIAwAAAA==.Monkahkiin:BAAANQADCgUIBQAAAA==.Moomoomo:BAABNQAECoEZAAMXAAkJ6xyeHACcAgAXAAcJICOeHACcAgALAAYJTRBUIQCLAQAAAA==.Moonrstrudel:BAAANQAECgcIEwAAAA==.Moonsaka:BAAANQAECgIIAgAAAA==.Mooseboi:BAAANQAECgUICAAAAA==.Moothy:BAAANQADCggIEwAAAA==.Morang:BAAANQAECgUICAAAAA==.Mossbeard:BAAANQAECgIIAgAAAA==.Mossdormu:BAAANQADCgUIBwAAAA==.',
Mu='Mujeae:BAAANQAECgQIBQAAAA==.Munitions:BAAANQADCgcIBwAAAA==.Murricah:BAAANQAECgYIDAAAAA==.Musique:BAAANQAECgQIBAAAAA==.',
My='Myrical:BAAANQADCgYIBgAAAA==.Myricism:BAAANQADCgMIBgABNQADCgYIBgABAAAAAA==.Myrihwana:BAABNQAECoEYAAIYAAgJIwzcHADhAQAYAAgJIwzcHADhAQAAAA==.Mythorne:BAAANQABCgYIBgAAAA==.',
['Mê']='Mêzcal:BAAANQAECgEIAQAAAA==.',
['Më']='Mërrick:BAAANQADCggICAAAAA==.',
Na='Nahp:BAAANQADCgQIBgAAAA==.Nahtinde:BAABNQAECoEWAAMZAAgJ8RMsDwBJAgAZAAgJ8RMsDwBJAgAJAAMJ2wEtMwB5AAAAAA==.Naterade:BAAANQAECggIEAAAAA==.Nazrull:BAAANQAECgQIBAAAAA==.',
Ne='Necrofrost:BAAANQAECgEIAQAAAA==.Neobovine:BAAANQAECgEIAQAAAA==.Nesowras:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.Nexlaht:BAAANQAECgYIDAAAAA==.',
Ni='Nicodemuss:BAAANQAECgMIAwAAAA==.Nightflare:BAAANQAECgQIBgAAAA==.',
No='Nodramah:BAAANQAECggIAgAAAA==.Noeyescono:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Noraz:BAAANQAECgcIEwAAAA==.Normalsaline:BAAANQAECgMIAwAAAA==.Noxoff:BAABNQAECoEcAAQDAAkJACDZCADVAgADAAgJHh/ZCADVAgACAAgJzhvEGAB9AgAEAAEJlBnaeABNAAAAAA==.',
Nu='Nullan:BAAANQAECgMIBAAAAA==.Nullash:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.Nuriel:BAAANQADCgcIBwAAAA==.',
['Nè']='Nèphelle:BAABNQAECoEZAAMaAAgJbyHMEQC6AgAaAAgJbyHMEQC6AgAbAAEJZhuAFQBKAAAAAA==.',
['Në']='Nëmèsÿs:BAAANQADCggIDwAAAA==.',
Oa='Oakendale:BAAANQAECgcIEQAAAA==.Oaklei:BAAANQADCgcIEwAAAA==.Oakrageous:BAAANQAECgIIAgAAAA==.',
Ob='Obiione:BAAANQADCggIGAAAAA==.Obionekenobi:BAAANQAECgIIAgAAAA==.',
Od='Oddball:BAAANQADCgcIBwAAAA==.Odinsson:BAAANQADCgUICAAAAA==.',
Ol='Olrun:BAAANQAECgIIAgAAAQ==.',
Or='Ordin:BAAANQADCgcIBwAAAA==.Orinek:BAAANQAECgYIBwAAAA==.Ororomunroe:BAAANQABCgIIAgAAAA==.Oruda:BAAANQADCgQIBAAAAA==.Orynnh:BAAANQADCgcIDgAAAA==.',
Os='Osogrande:BAAANQAECgQIBAAAAA==.Osso:BAAANQAECgIIAgAAAA==.',
Ow='Oway:BAAANQAECgEIAQAAAA==.Owy:BAAANQADCgUIBgAAAA==.',
Pa='Paean:BAAANQADCgYIBgAAAA==.Palajinn:BAAANQAFFAEIAQAAAA==.Pandaspanda:BAAANQAECgEIAQAAAA==.Passacaglia:BAAANQAECggIFgAAAQ==.Patryck:BAAANQAECgUICgAAAA==.Payotee:BAAANQADCgcIDQAAAA==.',
Pc='Pcokalypse:BAAANQAECgUICgAAAA==.',
Pe='Peilli:BAAANQADCgcIDQAAAA==.Penderrin:BAAANQADCggIBwABNQAECggIGQAEAPobAA==.Penemuel:BAAANQAECgUICAAAAA==.Pepperfrost:BAAANQABCgIIAwAAAA==.Perkys:BAAANQABCgEIAQAAAA==.Perrinaybara:BAAANQAECggIEgAAAA==.Petesteele:BAAANQAECgUIBgAAAA==.Petruccio:BAAANQAECgQIBgAAAA==.',
Ph='Phaet:BAAANQAECgQIBQAAAA==.Phob:BAAANQAECgYICwAAAA==.Phoreal:BAAANQAECgQIBgAAAA==.Phuryberryz:BAAANQADCggIDAAAAA==.Phuryblight:BAAANQADCgYIDgAAAA==.Phurysand:BAAANQADCgUIBQAAAA==.Phurystorm:BAAANQAECgEIAQAAAA==.',
Pi='Pikasloot:BAAANQAECgcIDwAAAA==.Pinechi:BAAANQADCgYIBgAAAA==.Pinestraw:BAAANQAECgUICAAAAA==.Pinksy:BAAANQAECgUICQAAAA==.Pipfanie:BAAANQADCgcIEAAAAA==.Pixelphobia:BAAANQAECgYIBgABNQAECgUIDAABAAAAAA==.',
Pl='Plaid:BAAANQAECgQIBgAAAA==.',
Pn='Pnakotus:BAAANQAECgUICwABNQAECgcIDwABAAAAAA==.',
Po='Pokeey:BAAANQAECgIIAgAAAA==.Powskii:BAAANQAECgQICAAAAA==.',
Pp='Ppsmash:BAABNQAFFIEGAAIIAAMJoA75AQDVAAAIAAMJoA75AQDVAAAAAA==.',
Pr='Pronouns:BAAANQAECgUICAAAAA==.Protege:BAAANQAECgQIBQAAAA==.',
Ps='Psy:BAAANQAECgIIAgAAAA==.Psybient:BAAANQADCgYIBgAAAA==.',
Pu='Purina:BAAANQADCgMIAwAAAA==.',
Pv='Pvp:BAAANQADCgUIBwAAAA==.',
['Pã']='Pãoduro:BAAANQADCgYIBwABNQAECgQIDQABAAAAAA==.',
['Pé']='Pérkis:BAAANQADCgcIBwAAAA==.',
Qu='Quacklord:BAAANQADCgQIBgAAAA==.',
['Qî']='Qîîz:BAAANQAECgcIDgAAAA==.',
Ra='Rakgul:BAAANQABCgIIAgAAAA==.Rambojohny:BAAANQAECggICwABNQAECgkJHQAFAO4dAA==.Rampagé:BAAANQADCgIIAgAAAA==.Ramzï:BAAANQAECgYICgAAAA==.Randompriest:BAAANQAECggIEwAAAA==.Rathernot:BAAANQAECgUICQAAAA==.Ravenbella:BAAANQAECgEIAQAAAA==.Ravex:BAAANQADCgcIBwABNQAECgkJHgAUAI0hAA==.Ravodin:BAAANQAECgYIBgABNQAECgkJHgAUAI0hAA==.Ravoks:BAABNQAECoEeAAQUAAkJjSFcDgDuAgAUAAgJnyBcDgDuAgATAAQJqh7nGQByAQAWAAMJ5R/lCQAIAQAAAA==.Razalla:BAAANQAECgQICgAAAA==.Razatre:BAAANQADCgUIBQAAAA==.Razeill:BAAANQADCgcIBwAAAA==.Razellia:BAAANQADCgUICQAAAA==.',
Re='Redfiend:BAAANQAECgMIAwAAAA==.Reika:BAAANQAECgYIDwAAAA==.Requlier:BAAANQAECgYICgAAAA==.Revelationzz:BAAANQAECgYIEgAAAA==.Rexkong:BAAANQAECgYIDAAAAA==.',
Rg='Rghtcousbtch:BAAANQAECgQIBAAAAA==.',
Ri='Riblets:BAAANQADCgUIBQAAAA==.Riki:BAAANQADCggIEgAAAA==.Ripetomato:BAABNQAECoEdAAIVAAkJOx6XFQD0AgAVAAkJOx6XFQD0AgAAAA==.',
Ro='Rockzeeheart:BAAANQAECgEIAQAAAA==.',
Rt='Rtcmouse:BAAANQAECgUICgAAAA==.',
Ru='Rukeshno:BAAANQAECgQICAAAAA==.',
['Ró']='Róckmybubble:BAAANQAECgYIDAAAAA==.',
Sa='Sacerdos:BAAANQAECgUIBQAAAA==.Saijin:BAAANQAECgQIBAAAAA==.Salvatorre:BAAANQADCgQIBAAAAA==.Salysra:BAAANQAECgQIBwAAAA==.Samstein:BAAANQAECgQICAAAAA==.Sanare:BAAANQAECgIIBAAAAA==.Sanchey:BAAANQAECgcIDQAAAA==.Sandalath:BAAANQABCgIIAgAAAA==.Sandara:BAAANQADCggIFAAAAA==.Sapz:BAAANQAECgYIDwAAAA==.Sarbrak:BAAANQADCgIIBAAAAA==.Sarka:BAAANQAECgEIAQAAAA==.Sarrh:BAAANQADCgUIBQAAAA==.Saryndra:BAAANQADCgQIBAABNQAECgUIBgABAAAAAA==.Satet:BAAANQADCggIEQAAAA==.Savvyshammy:BAAANQADCgYIBgAAAA==.Savïtar:BAAANQAECgQICAAAAA==.',
Sc='Scarleriss:BAAANQADCgQIBwAAAA==.Scrandle:BAAANQAECgQIBQAAAA==.Scythíx:BAAANQAECgEIAQABNQAECggIGQAPAJweAA==.',
Se='Sebile:BAAANQAECgcIEQAAAA==.Selirri:BAAANQADCgUIBQAAAA==.Semishift:BAAANQAECgYICAAAAA==.Sephroth:BAAANQAECgQICAAAAA==.Seydin:BAAANQAECgQICAAAAA==.Señorbear:BAAANQAECgEIAQAAAA==.',
Sh='Shaboink:BAAANQADCggICQABNQAECgQIBAABAAAAAA==.Shabutie:BAAANQAECgcIEwAAAA==.Shadowutf:BAAANQADCgYIBgAAAA==.Shadyboot:BAAANQADCgEIAQABNQAECgUIDwABAAAAAA==.Shaienne:BAAANQAECgQIBQAAAA==.Shamtan:BAAANQADCgIIBAAAAA==.Shayná:BAAANQAECgcICAAAAA==.Shayse:BAAANQABCgIIAgAAAA==.Shigar:BAAANQADCggICAAAAA==.Shigâr:BAAANQADCgYICgAAAA==.Shingaling:BAAANQADCggIFQAAAA==.Shinzovoker:BAAANQAECgUICwAAAA==.Shockcore:BAAANQADCgQIBgAAAA==.Shoshlihauni:BAAANQADCgUIBAAAAA==.',
Si='Sidioüs:BAAANQAECgUIDwAAAA==.Silvermoonto:BAAANQAECgEIAQAAAA==.Silvia:BAAANQAECgIIAgABNQAECgcIDgABAAAAAA==.Sinnan:BAAANQAECgQICAAAAA==.Sintaro:BAEANQAECgUIBwAAAA==.',
Sk='Skalina:BAAANQADCgEIAQAAAA==.Skidattles:BAAANQAECggIDgAAAA==.Skullordx:BAAANQADCgQIBAAAAA==.',
Sl='Sliverblood:BAAANQADCgYIBgAAAA==.',
Sm='Smeckledorfd:BAAANQAECgQICgAAAA==.',
Sn='Snelly:BAAANQAECgQIBAAAAA==.',
So='Sophie:BAAANQABCgYICAAAAA==.Soulzero:BAAANQAECgIIAgAAAA==.',
Sp='Spanksmoo:BAAANQAECgYIDQAAAA==.Spaxx:BAAANQAECgYIBwAAAA==.Spellstryke:BAAANQADCgYIBQAAAA==.Spinnaz:BAAANQAECgUICAAAAA==.',
St='Stalizzyx:BAAANQAECgYICAAAAA==.Stephani:BAAANQAECgYICAAAAA==.Stephia:BAACNQAFFIEFAAILAAMJ1A83CADjAAALAAMJ1A83CADjAAA1AAQKgSkAAwsACQmIHvwGACQDAAsACQmIHvwGACQDABcABAkUF4WBAB0BAAAA.Stevejubz:BAAANQADCgIIAgAAAA==.Styches:BAAANQADCgMIAwAAAA==.Stàple:BAAANQAECgQIBQAAAA==.',
Su='Suffrage:BAAANQAECgUIBgAAAA==.Sulveris:BAAANQAECgcIEgAAAA==.Sunnyshaman:BAAANQAECgYIDgAAAA==.Sunstriker:BAAANQADCgEIAQAAAA==.Suzygreenbrg:BAAANQADCgMIAwAAAA==.',
Sy='Syleane:BAAANQABCgYICgAAAA==.',
['Sä']='Sämael:BAAANQADCggIDgABNQAECgQICAABAAAAAA==.',
['Sì']='Sìnìster:BAABNQAECoEZAAIcAAkJbx0ACAAiAwAcAAkJbx0ACAAiAwAAAA==.',
Ta='Tamachi:BAAANQADCgcIBwAAAA==.Tanelorñ:BAAANQADCgQIBAAAAA==.Tanksomes:BAAANQAECgYIDwAAAA==.Tareilimage:BAAANQAECgQIBAAAAA==.Taurenman:BAAANQAECgQIBAAAAA==.',
Te='Tecom:BAAANQAECgEIAQAAAA==.Teddiebolt:BAAANQAECgMIAwABNQAECgcIDQABAAAAAA==.Teddifer:BAAANQAECgcIDQAAAA==.Temptus:BAAANQAECgUICwAAAA==.Terrenarde:BAAANQAECgMIBAABNQAECgcIEAABAAAAAA==.',
Th='Thdrae:BAAANQAECggICAAAAA==.Thejondoepro:BAAANQAECgYIEAAAAA==.Thicklog:BAAANQAECgMIBAAAAA==.Thisylas:BAAANQABCgMIAwABNQAECgUIBgABAAAAAA==.Thorrina:BAAANQABCgIIAQAAAA==.Thsbursysrur:BAAANQAECgQICAAAAA==.Thulsadoom:BAAANQADCgEIAQAAAA==.Thunderswift:BAAANQAECgYIEAAAAA==.Thæria:BAAANQAECgQICAAAAA==.',
Ti='Tia:BAAANQAECgUICQAAAA==.Tiltion:BAAANQAECgEIAQAAAA==.Tind:BAAANQABCgQIBwAAAA==.Tinggu:BAAANQADCggIEAAAAA==.Tinitus:BAAANQAECgYICgAAAA==.Tish:BAAANQADCgYIDAAAAA==.Tizzona:BAABNQAECoEiAAIdAAkJsSXnAADRAwAdAAkJsSXnAADRAwABNQADCgcIBwABAAAAAA==.',
Tl='Tlachtgae:BAAANQADCgIIAwAAAA==.',
To='Tobygodz:BAAANQAECgQIEAAAAA==.Tomatofest:BAAANQAECgEIAgAAAA==.Tookdk:BAAANQAECgcIEgAAAA==.Tookdrin:BAAANQAECgEIAQABNQAECgcIEgABAAAAAA==.Tooksamdi:BAAANQADCgcIBwABNQAECgcIEgABAAAAAA==.Toreto:BAAANQADCgMIAwAAAA==.Torvik:BAAANQADCgIIAgAAAA==.',
Tr='Treckken:BAAANQAECgUICAAAAA==.Treemendous:BAAANQABCgIIAgAAAA==.Treepunch:BAAANQADCgYIDAAAAA==.',
Tu='Tuknar:BAAANQAECgQICAAAAA==.Tulleren:BAAANQADCgcIEwAAAA==.',
Tv='Tvalin:BAAANQADCgcIDQABNQAECgMIAwABAAAAAA==.',
Ty='Tynan:BAAANQAECgUICQAAAA==.Typhön:BAAANQAECgMIBAAAAA==.',
Tz='Tzezae:BAAANQAECgQIBQAAAA==.',
['Tï']='Tïlo:BAAANQAECgYIDgAAAA==.',
Uc='Ucy:BAAANQADCgYIDgAAAA==.',
Ul='Ulfvaer:BAAANQABCgMIAwAAAA==.',
Um='Umbrafrost:BAAANQAECgQIBgAAAA==.',
Un='Unspeakable:BAAANQADCgUIBQAAAA==.Untot:BAAANQAECggIEgAAAA==.',
Va='Vach:BAAANQADCggIEwAAAA==.Vacui:BAAANQAECgEIAQABNQAECgQIBwABAAAAAA==.Vaedoc:BAAANQADCgUIBQAAAA==.Valezriel:BAAANQAECgMIAwAAAA==.Valintine:BAAANQADCggIGAAAAA==.Vallence:BAAANQAECgcIEQAAAA==.Valorem:BAAANQADCgEIAQAAAA==.Valorie:BAAANQAECgMIAwABNQAECgYICgABAAAAAA==.Valrev:BAAANQADCgcIBwAAAA==.Vassaro:BAAANQAECgEIAQABNQAECgYIDQABAAAAAA==.',
Ve='Vermivora:BAAANQAECgIIAgAAAA==.Vettè:BAABNQAECoEXAAIPAAgJdRANMAAEAgAPAAgJdRANMAAEAgAAAA==.Vevoxypoo:BAAANQADCggIDwAAAA==.',
Vi='Villivia:BAAANQAECgcIDQAAAA==.Viracia:BAAANQAECggIBgAAAA==.Virtigo:BAAANQAECgEIAQAAAA==.Visari:BAAANQAECgIIAgAAAA==.Vitole:BAAANQADCgEIAQABNQAECgcIDwABAAAAAA==.',
Vo='Voidcollapse:BAAANQADCgUIBgAAAA==.Voidnut:BAAANQAECgIIAgAAAA==.Voss:BAAANQADCggICQAAAA==.',
['Vê']='Vêstïge:BAAANQAECgQIBQAAAA==.',
Wa='Watermyrain:BAAANQAECgYIEAAAAA==.',
We='Weeble:BAAANQADCgUICAAAAA==.Weebu:BAAANQAECgQICAAAAA==.Welsley:BAAANQAECgUICAAAAA==.',
Wh='Whispe:BAAANQAECgUICQAAAA==.',
Wi='Wicate:BAAANQAECgQIBQAAAA==.Wildedge:BAAANQADCgYICgAAAA==.Wilder:BAAANQAECgcIEwAAAA==.Willendra:BAAANQAECgcIEQAAAA==.Wir:BAAANQAECgcIDwAAAA==.',
Wo='Wolfery:BAAANQAECgUICgAAAA==.Wolowizard:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Wonderface:BAAANQADCgcIBwABNQAECgUICQABAAAAAA==.Wonderfu:BAAANQAECgUIBQAAAA==.Wordrid:BAAANQADCgYIDAAAAA==.',
Wt='Wtfocks:BAAANQAECgQIBQAAAA==.',
Wu='Wuiigii:BAABNQAECoEWAAIeAAgJqhmWCQBYAgAeAAgJqhmWCQBYAgAAAA==.',
Xa='Xaena:BAAANQADCgcIDQAAAA==.Xatus:BAAANQAECgMIBQAAAA==.',
Xe='Xendrik:BAAANQAECgUIBgAAAA==.Xenyl:BAAANQADCgQIBgAAAA==.',
Xi='Xiaolia:BAAANQAECgQIBAAAAA==.',
Ya='Yamihikari:BAAANQAECgMIBAAAAA==.Yarela:BAAANQADCgUIBwAAAA==.',
Ye='Yedster:BAAANQAECgUIBQAAAA==.Yenara:BAAANQAECgYIDgAAAA==.Yesrav:BAAANQAECgIIAgAAAA==.',
Yi='Yihua:BAAANQAECgcIEAAAAQ==.Yinohn:BAAANQADCggICAAAAA==.',
Yu='Yumba:BAAANQAECgEIAQAAAA==.',
['Yå']='Yång:BAAANQADCgYICAAAAA==.',
Za='Zaborg:BAAANQAECgcIDAAAAA==.Zalerien:BAAANQADCgEIAQABNQAECgcIEAABAAAAAA==.Zandig:BAAANQAECgQIBQAAAA==.Zappyzapp:BAAANQADCgMIAwAAAA==.Zathog:BAAANQADCggIGQAAAA==.',
Ze='Zebin:BAAANQADCgUIBQAAAA==.Zeem:BAAANQAECgEIAQAAAA==.Zerthimon:BAAANQABCgIIAgAAAA==.',
Zh='Zharae:BAAANQAECgEIAgAAAA==.',
Zi='Ziaroe:BAAANQADCgEIAQAAAA==.Ziayn:BAAANQADCgQIBQAAAA==.',
Zo='Zoet:BAAANQAECgYICwAAAA==.Zohân:BAAANQAECgEIAQAAAA==.',
Zu='Zulani:BAAANQAECgUICAAAAA==.Zurana:BAAANQADCgYIBgABNQAECgEIAgABAAAAAA==.',
['Àl']='Àlik:BAAANQAECgcIEQAAAA==.',
['Áa']='Áayla:BAAANQADCgcIAQAAAA==.',
['Çh']='Çhökèm:BAAANQAECgcICwABNQAECgkJFwAFAL8YAA==.',
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
