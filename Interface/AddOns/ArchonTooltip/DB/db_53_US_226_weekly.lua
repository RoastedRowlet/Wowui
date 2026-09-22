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

local lookup = {'Unknown-Unknown','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Paladin-Retribution','Monk-Windwalker','Mage-Arcane','Mage-Frost','Hunter-BeastMastery','Warrior-Fury','DemonHunter-Devourer','Monk-Brewmaster','Rogue-Subtlety','Shaman-Restoration','Hunter-Marksmanship','Rogue-Outlaw','Hunter-Survival','Shaman-Enhancement','Druid-Restoration','Druid-Balance','Warrior-Protection','Druid-Feral','Shaman-Elemental','Paladin-Holy','Warrior-Arms','Warlock-Destruction','Evoker-Devastation','Monk-Mistweaver','Paladin-Protection','Evoker-Preservation','Warlock-Demonology','Warlock-Affliction','DemonHunter-Havoc','Rogue-Assassination','Evoker-Augmentation',}
local provider = {region='US',realm='Turalyon',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Absorb:BAAANQAECgMIBQABNQAECgcIEAABAAAAAA==.',
Ac='Aconcerious:BAAANQAECgUJDwAAAA==.Actionbztrd:BAAANQAECgcIEQAAAA==.',
Ad='Adamancy:BAAANQAECgMIAwAAAA==.Addlee:BAABNQAECoEdAAQCAAkKFhKECwApAQADAAcKLRUnQQDhAQACAAYKXAmECwApAQAEAAEKFQhOTgBEAAAAAA==.Addler:BAAANQAECgEIAQAAAA==.Aduro:BAAANQAECgUJDAAAAA==.',
Ae='Aeleleroesh:BAAANQABCgIIAgABNQABCgQIBAABAAAAAA==.Aeolyte:BAAANQAECgUIDAAAAA==.Aeradeath:BAABNQAECoEeAAQFAAkKyCBeCAAkAwAFAAkKcB9eCAAkAwAGAAgKHhUzKAAlAgAHAAUKEyMxMADlAQAAAA==.Aeronir:BAABNQAECoEbAAIIAAgKMw6jYwDSAQAIAAgKMw6jYwDSAQAAAA==.',
Ah='Ahlis:BAAANQAECgEIBAAAAA==.',
Ai='Aidur:BAAANQADCgUIBQAAAA==.',
Ak='Akabaggins:BAAANQADCggIGQAAAA==.',
Al='Alacrys:BAAANQAECgQICgAAAA==.Aldyrían:BAAANQADCgQIBgAAAA==.Alear:BAAANQAECgYJCgAAAA==.Alessie:BAAANQAECgMJAwAAAA==.Alltreg:BAAANQAECgIIAwAAAA==.Alrir:BAAANQADCggIGQAAAA==.Alyrii:BAAANQADCgQIBAABNQAECgQIBwABAAAAAA==.',
Am='Ambrose:BAAANQADCgcIBwAAAA==.Amelyn:BAAANQAECgQIBQAAAA==.Amrén:BAAANQAECgYIEQAAAA==.',
An='Angriff:BAAANQAECgcJDwAAAA==.Angusmcrizle:BAAANQAECgUJCgAAAA==.Ankalagon:BAAANQAECgUJCQAAAA==.',
Ar='Aranjah:BAAANQADCgYIEQAAAA==.Ardius:BAABNQAECoEbAAIJAAkK+xp4DAC5AgAJAAkK+xp4DAC5AgAAAA==.Arenaria:BAAANQAECgQJBQAAAA==.Arishokk:BAAANQAECgUIDQAAAA==.Arkmagi:BAAANQADCgUJBQABNQAECgcIEwABAAAAAA==.Arks:BAABNQAECoEgAAMKAAkK/xskQADLAgAKAAkKBRskQADLAgALAAEKkiEVKgBHAAAAAA==.Arkthugal:BAAANQAECgcIEwAAAA==.Arktwogal:BAAANQADCgEIAQABNQAECgcIEwABAAAAAA==.Arteezer:BAAANQADCgcIBwABNQAECgkJIAAEACMWAA==.Artemiye:BAAANQAECgYICgAAAA==.Artikblaz:BAAANQADCggIFwAAAA==.Arun:BAAANQADCgYIBgAAAA==.Arés:BAAANQAECgQIBgAAAA==.',
As='Ashieldu:BAAANQAECgIIAgAAAA==.Ashkikur:BAAANQADCgYIBgAAAA==.Askanni:BAAANQAECgUJCwAAAA==.Astharot:BAAANQAECgQIEAAAAA==.Astralain:BAAANQAECgYJCgAAAA==.Astrozen:BAAANQADCgUIBQAAAA==.Asture:BAAANQADCgUIBQAAAA==.',
At='Atulmoji:BAAANQAECgEIAQAAAA==.',
Au='Augdra:BAAANQADCggIFwAAAA==.Auriauna:BAAANQAECgQJBwAAAA==.',
Av='Avadagryth:BAAANQAECgcIDQAAAA==.Avanyani:BAAANQAECgEIAQAAAA==.Avidowned:BAAANQAECgUJBQAAAA==.',
Ay='Ayllo:BAAANQAECgEJAQABNQAECgMIAwABAAAAAA==.',
Ba='Baalis:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Bacalhau:BAAANQAECgQJBQABNQAECgUIDgABAAAAAA==.Baelgoroth:BAAANQAECgYJEAAAAA==.Barachiel:BAAANQAECgYIDwAAAA==.Basheaba:BAABNQAECoEVAAIMAAgKXB+VIwCqAgAMAAgKXB+VIwCqAgAAAA==.Batrous:BAAANQADCgYJBgAAAA==.Battlerbrian:BAAANQABCgMIAwAAAA==.',
Be='Belandra:BAAANQAECgYJEQAAAA==.Belegond:BAAANQADCgcIBwAAAA==.Belishario:BAAANQAECgYIEgAAAA==.Belladawna:BAABNQAECoEbAAIKAAgKSg02kQDsAQAKAAgKSg02kQDsAQAAAA==.Bellatrex:BAAANQADCgEIAQAAAA==.Beredeath:BAAANQADCgcIBwABNQAECgEIAgABAAAAAA==.Bereid:BAAANQADCggIDgABNQAECgEIAgABAAAAAA==.Berejitsu:BAAANQADCgQIBQABNQAECgEIAgABAAAAAA==.Beârback:BAEANQAECggJCwAAAA==.',
Bi='Bigchops:BAAANQAECgQJBwAAAA==.Bigfuzzy:BAAANQADCggIGwAAAA==.Bigtime:BAAANQADCgYJCAAAAA==.Bigwillie:BAAANQAECgQIDAAAAA==.',
Bl='Blazerbrew:BAAANQAECgUICwAAAA==.Blezaa:BAAANQAECgUJDAAAAA==.Blinknleap:BAABNQAECoEdAAINAAgK7RuDAwCfAgANAAgK7RuDAwCfAgAAAA==.Blooddrakken:BAAANQADCggIGAABNQAECgEIAQABAAAAAA==.Blooddruid:BAAANQABCgIIAgABNQAECgEIAQABAAAAAA==.Bloodoxel:BAAANQADCgcJDQAAAA==.',
Bn='Bn:BAAANQAECgIIAgAAAA==.',
Bo='Boring:BAAANQAECgcJEgAAAA==.Boxlunch:BAAANQADCgYIBgABNQAECgkJGQAOAIAfAA==.Boyana:BAAANQADCgcICwAAAA==.',
Br='Brandybuck:BAAANQAECgIIAgAAAA==.Brucelééroy:BAAANQAECgEJAQAAAA==.Bruski:BAAANQABCgEIAQAAAA==.Bruskii:BAAANQAECgUJDwAAAA==.',
Bu='Bulsharess:BAAANQADCgQIBAAAAA==.Bulshari:BAAANQADCgUIBQAAAA==.Bunns:BAAANQADCgcIDQAAAA==.Burningrash:BAAANQADCgYIDwAAAA==.Butternugget:BAAANQAECgUJBQAAAA==.Buuffy:BAAANQAECgQJBAAAAA==.',
By='Byleana:BAAANQADCggIDgABNQAECggIIQAHACodAA==.Byléana:BAABNQAECoEhAAIHAAgKKh0CGwB/AgAHAAgKKh0CGwB/AgAAAA==.Bytem:BAAANQAECgYICwAAAA==.',
Ca='Caelyn:BAAANQADCgQIBAAAAA==.Caewyn:BAAANQADCggJFQAAAA==.Calysta:BAAANQAECgQJBgAAAA==.Candalen:BAAANQABCgYIBgAAAA==.Carleys:BAAANQAECgYJCAAAAA==.Cassara:BAAANQAECgQJBQAAAA==.Cathella:BAAANQADCgYJCQAAAA==.',
Ce='Ceberus:BAAANQADCgUIBQAAAA==.Celek:BAAANQAECggICAAAAA==.Celekai:BAAANQAECgQIDAABNQAECggICAABAAAAAA==.Celi:BAAANQAECgYJDgAAAA==.Celébrin:BAAANQABCgIIAgAAAA==.Cerandan:BAAANQABCgQIBAAAAA==.Cerbadin:BAAANQAECgEIAQABNQAECgYJDQABAAAAAA==.Cerbyhunt:BAAANQAECgYJDQAAAA==.Cerbymage:BAAANQADCgIIAgABNQAECgYJDQABAAAAAA==.Cerbywar:BAAANQADCgcIBwABNQAECgYJDQABAAAAAA==.',
Ch='Cheeana:BAAANQAECgQICAAAAA==.Cherlindrea:BAAANQAECgUICQABNQAECggJGgAPAEkXAA==.Chhive:BAAANQAECgUICQAAAA==.Chickenstrip:BAAANQADCgQIBwABNQAECgEIAQABAAAAAA==.Chopchop:BAAANQADCgYICwAAAA==.Chrysus:BAAANQAECgUJBQAAAA==.',
Ci='Cidal:BAAANQAECgQJBQAAAA==.Cindii:BAAANQADCgcICwAAAA==.',
Cl='Clada:BAAANQAECgQIDQABNQAECgQIBgABAAAAAA==.Clancy:BAAANQAECgEIAQAAAA==.Cleric:BAAANQAECgEIAQAAAA==.Clifmantooth:BAAANQAECgUJBQAAAA==.',
Co='Colada:BAAANQABCggICwAAAA==.Coldkiller:BAAANQAECgIIAgAAAA==.Coneau:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Couprenarde:BAAANQADCgMIAwABNQAECgcIFQABAAAAAA==.Courpsie:BAAANQAECgcJEwAAAA==.Courtvoke:BAAANQADCgEIAQABNQAECgcJEgABAAAAAA==.',
Cr='Crager:BAAANQAECgQJBQAAAA==.Crazyjamu:BAAANQADCgYIBwAAAA==.Creamygees:BAAANQAECgcIEwAAAA==.Creaturé:BAAANQADCgYJEQAAAA==.Criaharn:BAAANQAECgYIBgAAAA==.Cripp:BAAANQAECgIJAgAAAA==.Crybeardin:BAAANQAECgYICAABNQAECggIFwAIAPEgAA==.Cryohunter:BAAANQAECgQJCAAAAA==.',
Ct='Ctair:BAAANQAECgUIDgAAAA==.',
Cu='Cuckcommando:BAAANQADCgIIAgABNQAFFAMICQAPAKcOAA==.',
Cy='Cybersorc:BAAANQAECgEIAQAAAA==.Cybrhexx:BAEANQADCgcIBgABNQAECgYIEQABAAAAAA==.Cyrce:BAAANQADCgYIBgAAAA==.Cyrs:BAAANQAECgQIBQAAAA==.Cysvarion:BAAANQAECgIJAgAAAA==.',
['Có']='Ców:BAAANQAECgIIAgABNQAECgYIEgABAAAAAA==.',
['Cø']='Cønø:BAAANQAECgIIAgAAAA==.',
Da='Daddi:BAAANQAECgYJEAAAAA==.Dairs:BAAANQAECgEIAQAAAA==.Dajjflajj:BAAANQAECgQIBAAAAA==.Dalitha:BAAANQAECgIJAgABNQAECgcIFQABAAAAAA==.Daltan:BAAANQAECgUICAAAAA==.Dalynar:BAAANQADCgQIBAAAAA==.Damukovu:BAAANQAECgEIAQAAAA==.Danayro:BAAANQAECgYJEQAAAA==.Dandron:BAAANQAECgYICQAAAA==.Dankmeme:BAAANQAECgQIBgAAAA==.Darc:BAAANQADCgUJCAAAAA==.Darksath:BAAANQADCgMIAgAAAA==.Darkvag:BAABNQAECoEdAAMLAAkKWx6XBwDmAQAKAAcKHho/eQApAgALAAYKhBuXBwDmAQAAAA==.Davalos:BAAANQAECgUICAAAAA==.Davepark:BAAANQADCgUIBQAAAA==.Davos:BAAANQADCgcJDQAAAA==.Daygos:BAABNQAECoEdAAIMAAkKYh9eEQAYAwAMAAkKYh9eEQAYAwAAAA==.Daêmon:BAAANQAECgIIAgAAAA==.',
De='Deadsparks:BAABNQAECoEiAAIGAAgKbSNTCwAyAwAGAAgKbSNTCwAyAwAAAA==.Deathosso:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Deftech:BAABNQAECoEaAAIQAAkKMiTRAADPAwAQAAkKMiTRAADPAwAAAA==.Demonic:BAAANQAECgQIBQAAAA==.Demonrocket:BAAANQAECgMJBQAAAA==.Derisive:BAAANQADCgcIBwABNQAECgYJEAABAAAAAA==.Devilslayery:BAAANQAECgQJCAAAAA==.',
Dh='Dharien:BAABNQAECoEXAAIIAAgK8SC+IwDXAgAIAAgK8SC+IwDXAgAAAA==.',
Di='Diamondbob:BAAANQADCgEIAQAAAA==.Digbicktus:BAAANQAECgIIAgAAAA==.Direheart:BAAANQAECgQJBQAAAA==.',
Do='Dommothop:BAACNQAFFIEQAAIQAAcKcyQfAAD1AgAQAAcKcyQfAAD1AgA1AAQKgSwAAhAACQrqJhYAABEEABAACQrqJhYAABEEAAAA.Dorp:BAAANQAECgYIBwAAAA==.Dovahbruh:BAAANQABCgYIBgAAAA==.',
Dr='Dragdon:BAAANQAECgQIBAABNQAECgQIBgABAAAAAA==.Dragosangue:BAAANQAECgEIAQAAAA==.Dragundeez:BAAANQAECgIIAwABNQAECgkJMQARAIIiAA==.Drakebeard:BAAANQAECgcIDwAAAA==.Drayus:BAAANQAECgYJDAAAAA==.Driitz:BAAANQAECgcJEwAAAA==.',
Du='Duvoh:BAAANQAECgUJEAAAAA==.',
Dw='Dweezilla:BAAANQAECgMJBQAAAA==.',
Ea='Easimode:BAAANQADCgYIBgAAAA==.Eatswutsdead:BAAANQADCgYIBgAAAA==.',
Ec='Echarrial:BAAANQADCgYIDwAAAA==.Eclipsweaver:BAAANQABCgIJAgAAAA==.',
Ed='Eddias:BAAANQADCggIDwAAAA==.Edge:BAAANQAECgYJDwAAAA==.',
Ek='Eklypsis:BAAANQADCggIDwAAAA==.',
El='Elang:BAAANQAECgQJDAAAAA==.Elange:BAAANQADCgYIBgAAAA==.Elazuria:BAAANQAECgIIAgAAAA==.Elementrix:BAAANQAECgMIBAAAAA==.Elgrandè:BAAANQADCgQIBAAAAA==.Elmafudd:BAAANQAECgIJAgABNQAECgcIFQABAAAAAA==.Elsadieorc:BAAANQADCgcIDwAAAA==.Eluss:BAAANQADCgUIBQAAAA==.Elvay:BAAANQAECggJDwAAAA==.Elyos:BAAANQADCgcJEwAAAA==.Elzar:BAAANQAECgMJBQAAAA==.',
Em='Emeraldflame:BAAANQADCgMIAwAAAA==.Emodk:BAAANQAECgMIAwABNQAFFAcIGAASABQhAA==.',
En='Entarri:BAAANQAECgYJCgAAAA==.Entivala:BAAANQADCgYIBgAAAA==.Envoi:BAAANQADCgcIDQAAAA==.',
Eq='Equitem:BAAANQAECgcJEAAAAA==.',
Er='Eridanos:BAAANQADCgYIEQAAAA==.',
Es='Escanör:BAAANQAECgQIBAABNQAECgYJBgABAAAAAA==.Eshel:BAABNQAECoEaAAITAAgKtAbFCQCYAQATAAgKtAbFCQCYAQAAAA==.Eshmel:BAAANQAECgQJBAAAAA==.Essek:BAAANQAECgUJDQAAAA==.',
Ev='Everfrost:BAABNQAECoEfAAMKAAkKxh8YKAAaAwAKAAkKxh8YKAAaAwALAAUKdBNNEAAqAQAAAA==.Evidicus:BAABNQAECoEWAAINAAgKxhoiBAB9AgANAAgKxhoiBAB9AgAAAA==.Evilscarnage:BAABNQAECoEZAAIUAAkKQRhDAgC8AgAUAAkKQRhDAgC8AgAAAA==.Evilstotem:BAABNQAECoEeAAIVAAgK/hn6CACTAgAVAAgK/hn6CACTAgAAAA==.Evu:BAABNQAECoEYAAIHAAgKMiKkDAAUAwAHAAgKMiKkDAAUAwAAAA==.',
Ex='Exkath:BAABNQAECoEgAAMFAAkKaCVXAwCMAwAFAAkKYSRXAwCMAwAGAAUKXSTkKQAZAgAAAA==.',
Ez='Ezlyn:BAAANQAECgIIAgAAAA==.Ezrael:BAAANQADCgcIBwAAAA==.',
Fa='Faedrela:BAAANQAECgUJDAAAAA==.Falito:BAAANQAECgYJDgAAAA==.Farben:BAAANQAECgcIEAAAAA==.Fatabbot:BAAANQAECgEIAgAAAA==.',
Fe='Felines:BAAANQADCgcIDgAAAA==.Felixfenton:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Fellbane:BAAANQADCgYICgAAAA==.Feohh:BAAANQAECgQJBQAAAA==.',
Fi='Fiddlesticks:BAABNQAECoEZAAIJAAgKvhkDEgBYAgAJAAgKvhkDEgBYAgAAAA==.Findale:BAABNQAECoEYAAIWAAkKbBl7CwC0AgAWAAkKbBl7CwC0AgAAAA==.',
Fj='Fjalar:BAAANQAECggICwAAAA==.',
Fk='Fkxstvebee:BAAANQAECgEJAQABNQAECggIGgAIAGATAA==.',
Fl='Flajj:BAAANQAECgYIDwAAAA==.Flamezephyr:BAABNQAECoEZAAMKAAYKzCK5fAAgAgAKAAYKOx+5fAAgAgALAAEKWCFfJABfAAAAAA==.Flufbuns:BAAANQADCggIFAAAAA==.',
Fo='Foxnews:BAAANQAECgUJCwAAAA==.',
Fr='Frackingheal:BAAANQABCgQIBAAAAA==.Fredfazbear:BAABNQAECoElAAIXAAkKWh90DgAiAwAXAAkKWh90DgAiAwAAAA==.Frostystrips:BAAANQAECgEIAQAAAA==.Frozat:BAAANQADCgQIBgAAAA==.Frumdaheart:BAAANQADCgUIBQABNQAECgcIDwABAAAAAA==.',
Fu='Furiza:BAAANQADCgYIBgAAAA==.Furybztrd:BAAANQADCgcIBwAAAA==.',
Ga='Gagno:BAAANQADCgIIAgAAAA==.Gagnot:BAAANQADCgMIAwAAAA==.Galadriál:BAAANQADCgUJBgAAAA==.Garnimal:BAAANQAECgUJCQAAAA==.',
Ge='Georgigeo:BAAANQAECgYIEAAAAA==.',
Gh='Ghazkill:BAAANQABCgEIAQAAAA==.Ghostbrue:BAAANQAECgMJAwAAAA==.',
Gl='Glacious:BAAANQAECgIIAgAAAA==.Glizygobrice:BAAANQABCgIIAwAAAA==.',
Go='Gong:BAAANQADCgYJBgAAAA==.Goo:BAAANQADCgYIBgAAAA==.Goodbeer:BAAANQAECgUIDAAAAA==.Gouraud:BAAANQAECgIIBAAAAA==.',
Gr='Graeclaw:BAAANQAECgUJCgAAAA==.Grayson:BAABNQAECoEfAAMNAAkKNyK2AACPAwANAAkKNyK2AACPAwAYAAIKdBahIwB3AAAAAA==.Greenclaw:BAABNQAECoEaAAIXAAgKUBLfKgAPAgAXAAgKUBLfKgAPAgAAAA==.Gregoryus:BAAANQADCgUIDwAAAA==.Grosmortfif:BAAANQADCgYIBgABNQAECgYJDgABAAAAAA==.Gruber:BAAANQADCgcIBwABNQAECggIIwAZALIiAA==.',
Gu='Gultak:BAAANQAECgIJAwAAAA==.',
['Gô']='Gôósè:BAAANQAECgYIEQAAAA==.',
Ha='Hadron:BAAANQAECgUICgABNQAECggIGwAPACcgAA==.Hairsweater:BAAANQAECgUJCgAAAA==.Hakirai:BAAANQAECgUJDQAAAA==.Halje:BAAANQADCggICAAAAA==.Halodin:BAAANQAECgEIAgAAAA==.Harambecast:BAAANQADCggJDwABNQAECgYJBgABAAAAAA==.',
He='Heimdall:BAAANQAECgYICwAAAA==.Hermóðr:BAAANQAECgcICQABNQAECgkJIAAKAP8bAA==.Herrick:BAAANQADCgYIBgAAAA==.Hexan:BAAANQAECgUJDwAAAA==.Hexun:BAAANQABCgIIAgAAAA==.',
Hi='Hibred:BAAANQADCgcIBwAAAA==.Hirumaredx:BAAANQAECgUJCgAAAA==.',
Ho='Hobbsies:BAAANQAECgUJCgAAAA==.Hobkins:BAABNQAECoEeAAIaAAgKSxvNJQCJAgAaAAgKSxvNJQCJAgAAAA==.Holcon:BAAANQAECgIIBAAAAA==.Holiussy:BAAANQADCggIDQABNQAECgkJMQARAIIiAA==.Hollypops:BAAANQAECgMIBQAAAA==.Holybeau:BAABNQAECoEhAAIbAAgKtR7GGADJAgAbAAgKtR7GGADJAgAAAA==.Holybo:BAAANQADCggIBwABNQAECggIHgABAAAAAQ==.Holyhex:BAAANQABCgQIBQAAAA==.Holywars:BAAANQAECgUIBQAAAA==.Holywdundead:BAAANQAECgMIBgAAAA==.',
Hu='Hula:BAAANQAECgMIAwAAAA==.',
Hy='Hypercat:BAAANQAECgYIEAAAAA==.Hyriel:BAAANQAECgEIAQAAAA==.',
['Hú']='Húnts:BAAANQAECgQJCAAAAA==.',
Ia='Iambbq:BAAANQAECgcIEwAAAA==.',
Ib='Ibuprofen:BAAANQAECgIJAgAAAA==.',
Ic='Iceblades:BAAANQADCgMIAwAAAA==.Icyclo:BAAANQADCgUICQAAAA==.',
Id='Idioterroors:BAAANQADCgIJAgAAAA==.',
Ig='Igraine:BAAANQAECgUJBwAAAA==.',
Il='Illidarios:BAAANQAECgMIBAABNQAECgQIBwABAAAAAA==.Ilostmybible:BAAANQAECgIIAwAAAA==.',
Im='Imakeupuddin:BAABNQAECoEkAAIcAAkKJiTiBwCcAwAcAAkKJiTiBwCcAwAAAA==.',
In='Indydevteam:BAAANQAECgIIBQAAAA==.Inffected:BAAANQAECgUJBQAAAA==.Inflames:BAAANQAECgQJBQABNQABCgEIAQABAAAAAA==.Inglëwood:BAAANQADCgYIFAAAAA==.',
Is='Isasabotage:BAAANQAECgIJBAAAAA==.Isult:BAAANQAECgIJAwAAAA==.',
Iv='Iv:BAAANQAECgMIBAAAAA==.',
Ix='Ixthyr:BAABNQAECoEbAAIcAAkKvR9+GAAlAwAcAAkKvR9+GAAlAwABNQAECgkJIAAFACwhAA==.',
Ja='Jaenaa:BAAANQAECgYIDQAAAA==.Jahrobi:BAABNQAECoEaAAIYAAgK0yQPAgBZAwAYAAgK0yQPAgBZAwAAAA==.Jakqua:BAAANQABCgIIAgABNQAECgcIDgABAAAAAA==.Jaselyn:BAABNQAECoEWAAMRAAgKOSB0EgDyAgARAAgKOSB0EgDyAgAaAAUKcw5FeQApAQAAAA==.Jaskryt:BAAANQAECgEIAQABNQAECggJGAAdAJANAA==.Jaslyn:BAAANQADCgMIBQAAAA==.Jaxin:BAAANQADCgIIAgAAAA==.Jaxsen:BAAANQADCggIFAAAAA==.',
Je='Jelibean:BAAANQADCggICAAAAA==.Jensei:BAABNQAECoEaAAIPAAgKSRegCQAWAgAPAAgKSRegCQAWAgAAAA==.',
Jh='Jheina:BAABNQAECoEaAAIeAAcKAQZtGQBTAQAeAAcKAQZtGQBTAQAAAA==.Jheirazlynn:BAAANQABCggIBgABNQAECgcIGgAeAAEGAA==.',
Ji='Jimmyvrr:BAAANQAECgUIDwAAAA==.Jinnô:BAABNQAECoEjAAIfAAkKrx2BBAAjAwAfAAkKrx2BBAAjAwAAAA==.Jizzelda:BAAANQADCgcIEAAAAA==.',
Jo='Joqi:BAAANQADCggIBwAAAA==.Jorazak:BAAANQADCgcJBwAAAA==.',
Ju='Jubzie:BAAANQAECgQICAAAAA==.Jubzy:BAAANQAECgcIDwAAAA==.Judgment:BAAANQAECgEIAQAAAA==.Justwin:BAAANQAECgUICQAAAA==.',
['Jå']='Jåckx:BAAANQADCgQICAAAAA==.',
Ka='Kaarnu:BAAANQAECgUJDAAAAA==.Kageman:BAAANQAECgQJBgAAAA==.Kakon:BAAANQAECgUJCAAAAA==.Kamikrazi:BAAANQADCgEIAQAAAA==.Kapuna:BAAANQAECgUJBwAAAA==.Karaglaz:BAAANQAECgYIDAAAAA==.Karalea:BAABNQAECoEfAAMKAAgKiCLDMAD8AgAKAAgKsCHDMAD8AgALAAEKGyWNJABeAAAAAA==.Katalene:BAAANQADCgUIBQABNQAECgcIFQABAAAAAA==.Kayani:BAAANQADCgUJBQAAAA==.Kazaganthis:BAAANQAECgcJBwAAAA==.Kazstorius:BAAANQAECgUJDgAAAA==.',
Ke='Kellbell:BAAANQAECgIJAwAAAA==.Kertug:BAAANQAECgQICAAAAA==.Keturonium:BAAANQAECgQICQAAAA==.Kevdk:BAAANQAECgMJBgAAAA==.',
Kh='Khary:BAAANQABCgYIBAAAAA==.Kharzaette:BAABNQAECoEZAAMKAAcKGRSItACbAQAKAAYKuhSItACbAQALAAEKUhDMKwBCAAAAAA==.Khristo:BAABNQAECoEYAAIgAAgKqR6/CAC0AgAgAAgKqR6/CAC0AgAAAA==.',
Ki='Kiing:BAAANQAECgYIEgAAAA==.Kikwi:BAAANQAECgIIBAAAAA==.Kioshi:BAAANQAECgYJEQAAAA==.Kirayamató:BAAANQAECgcIDwAAAA==.Kitmeup:BAAANQADCgEIAgAAAA==.Kiyofu:BAAANQAECgYIDgAAAA==.',
Kn='Knew:BAAANQAECggJCwAAAA==.Knotagan:BAAANQAECgIIBAAAAA==.',
Ko='Kobebryant:BAAANQAECgcIBwAAAA==.Koriol:BAAANQAECgEJAQAAAA==.Korkron:BAABNQAECoExAAMRAAkKgiJnEQD8AgARAAkKgiJnEQD8AgAaAAIKxBDDswCHAAAAAA==.Kovian:BAAANQADCgIIAgAAAA==.Kozmikboom:BAAANQAECgEIAQAAAA==.',
Kr='Krackster:BAAANQADCgMJAwABNQADCgQIBAABAAAAAA==.Krakow:BAAANQABCgYICAAAAA==.Krezan:BAAANQADCgcIEgAAAA==.Krix:BAAANQAECgQJBAABNQADCgYJBgABAAAAAA==.Krolo:BAAANQADCgYIDAABNQAECgYJDgABAAAAAA==.',
Ku='Kutkala:BAAANQADCgEJAQAAAA==.',
Ky='Kyndrine:BAAANQADCgMIAwABNQADCggIGQABAAAAAA==.Kyrja:BAAANQAECgUICAAAAA==.Kytti:BAAANQAECgMIAwAAAA==.',
La='Laani:BAAANQADCgcIBwABNQAECggIFgAHAAcYAA==.Ladorin:BAAANQADCgYICwAAAA==.Lahallia:BAABNQAECoEbAAIDAAgKfhbKMAAzAgADAAgKfhbKMAAzAgAAAA==.Laiellarien:BAAANQADCgUJBwABNQAECgcIFQABAAAAAA==.Lamarqt:BAAANQADCggICAAAAA==.Landrea:BAAANQADCggIAgAAAA==.Lany:BAAANQADCgEIAQAAAA==.Laran:BAAANQAECgYJDQAAAA==.Laupouette:BAAANQAECgUIBwABNQAECgkJHQAhACofAA==.Laurissandra:BAAANQAECgIIAgAAAA==.Lavalley:BAAANQADCgYIBgAAAA==.Lazypanda:BAAANQADCgYJCgAAAA==.',
Le='Lerzian:BAAANQADCggJCAAAAA==.Lexicage:BAAANQAECgUJDgAAAA==.',
Li='Lidd:BAAANQAECgUJDwAAAA==.Lightiuz:BAAANQAECgUJEgAAAA==.Lightless:BAAANQABCgYIBgAAAA==.Lightmeat:BAAANQABCggICgAAAA==.Lightstorme:BAAANQABCggIEQABNQAECgQIBAABAAAAAA==.Lilshadoww:BAAANQAECgUIAgAAAA==.Livandletdie:BAAANQAECgIIAwAAAA==.Lividchaos:BAAANQABCgMIAwAAAA==.',
Ll='Llalow:BAAANQADCggICAAAAA==.Llalowdh:BAAANQAECgYIEgAAAA==.',
Lo='Lockewynn:BAAANQAECgcIEQAAAA==.Lockjawsh:BAABNQAECoEhAAMdAAgKZB0MFQCtAQAiAAcKRx3RNABLAgAdAAYKExYMFQCtAQAAAA==.Lokuma:BAAANQAECgYJEAAAAA==.Lorelae:BAAANQADCgcIBwAAAA==.Lorre:BAAANQADCgQIBgAAAA==.Lot:BAAANQADCggICAAAAA==.Louni:BAABNQAECoEhAAIEAAkKvSK9BABzAwAEAAkKvSK9BABzAwAAAA==.',
Lu='Ludo:BAAANQADCgUIDAAAAA==.Lunch:BAAANQADCgQIBAAAAA==.Lunchbreak:BAABNQAECoEZAAIOAAkKgB9oBgBSAwAOAAkKgB9oBgBSAwAAAA==.Lunchpunch:BAAANQAECgUIBQABNQAECgkJGQAOAIAfAA==.Lunchtime:BAAANQAECgYICQABNQAECgkJGQAOAIAfAA==.Luot:BAAANQADCgcJCQAAAA==.',
Ma='Machine:BAAANQADCgcICwABNQAECgQIBQABAAAAAA==.Magias:BAAANQADCgUJCgAAAA==.Maglea:BAAANQADCgUJBwAAAA==.Majexs:BAABNQAECoEhAAIIAAgKsR4rKwCwAgAIAAgKsR4rKwCwAgAAAA==.Malady:BAAANQADCggIDQAAAA==.Malfûrion:BAAANQABCgMJAwAAAA==.Malignancy:BAAANQAECgcIEAAAAA==.Manalhau:BAAANQAECgUIDgAAAA==.Mandragoran:BAABNQAECoEiAAQcAAkKAxhtPgBtAgAcAAkKthdtPgBtAgAYAAcKkxNHDwCfAQANAAEKiAH1JwAVAAAAAA==.Manohar:BAAANQADCgMIAwAAAA==.Manuster:BAAANQAECgUJBgAAAA==.Maradön:BAABNQAECoEbAAIHAAgKah14FgCoAgAHAAgKah14FgCoAgAAAA==.Margarida:BAAANQAECgUIDQAAAA==.Margaru:BAAANQADCgQIBgAAAA==.Maruknar:BAAANQADCgcJCwAAAA==.Mavd:BAAANQAECgUICgAAAA==.Mavex:BAAANQAECgYJBgABNQAFFAMJCAAjAO8TAA==.Maximmus:BAAANQAECgYIDAAAAA==.Mayæl:BAAANQADCgcIEQAAAA==.Mazerrackham:BAAANQAECgYJDQAAAA==.',
Me='Meesooholyy:BAAANQAECgIIAgAAAA==.Meina:BAAANQAECgIJBAAAAA==.Mellow:BAAANQADCgcIBwABNQAECgUJDQABAAAAAA==.Melynia:BAAANQAECgIJBAAAAA==.Mephala:BAAANQAECgcIDwAAAA==.Metapig:BAAANQAECgYIDAAAAA==.Mezasu:BAAANQAECgcJDAAAAA==.',
Mi='Michaelj:BAAANQAECgQIBAAAAA==.Mikedawson:BAABNQAECoEbAAIjAAkKfRtwAQD6AgAjAAkKfRtwAQD6AgAAAA==.Mikya:BAAANQAECgYIDwAAAA==.Milkot:BAAANQAECggIBwAAAA==.Milkys:BAAANQAECgQICAABNQAECgQIDgABAAAAAA==.Mistian:BAAANQAECgcIEQAAAA==.Mistpet:BAAANQADCgUIBQABNQAECggIGwAXAKkgAA==.Mistrbfkx:BAABNQAECoEaAAQIAAgKYBPubAC2AQAIAAcKSxHubAC2AQAbAAcKNgxzXQB/AQAgAAEKtxZvTAAtAAAAAA==.',
Mo='Moai:BAAANQADCgEIAQAAAA==.Moderñdruið:BAAANQAECgUIDgAAAA==.Mojodjin:BAAANQAECgYJCQAAAA==.Molewithwing:BAAANQAECgMIAwAAAA==.Molocko:BAAANQAECgMIAwAAAA==.Monkahkiin:BAAANQAECgEIAQAAAA==.Moomoomo:BAABNQAECoEhAAMMAAkKqR4SGgDdAgAMAAcKXiUSGgDdAgASAAYKTRCcKQB3AQAAAA==.Moonrstrudel:BAABNQAECoEcAAIZAAgKiBwfBQCoAgAZAAgKiBwfBQCoAgAAAA==.Moonsaka:BAAANQAECgIIAgAAAA==.Mooseboi:BAAANQAECgYJDgAAAA==.Moothy:BAAANQAECgIIAgAAAA==.Morang:BAAANQAECgYJDgAAAA==.Mossbeard:BAAANQAECgIJAgAAAA==.Mossdormu:BAAANQADCgUJBwAAAA==.',
Mu='Mujeae:BAAANQAECgQIBQAAAA==.Munitions:BAAANQADCggIDwAAAA==.Murricah:BAAANQAECgcJEwAAAA==.Musique:BAAANQAECgQJBAAAAA==.',
My='Myrical:BAAANQADCgYIBgAAAA==.Myricism:BAAANQADCgMIBgABNQADCgYIBgABAAAAAA==.Myrihwana:BAABNQAECoEeAAIkAAgKJA0hJgDfAQAkAAgKJA0hJgDfAQAAAA==.Mythorne:BAAANQABCgYJBwAAAA==.',
['Mê']='Mêzcal:BAAANQAECgIIAwAAAA==.',
['Më']='Mërrick:BAAANQADCggICgAAAA==.',
Na='Nahp:BAAANQADCgcJDQAAAA==.Nahtinde:BAABNQAECoEWAAMlAAgK8RMKGAAwAgAlAAgK8RMKGAAwAgAQAAMK2wFmOQBzAAAAAA==.Naterade:BAAANQAFFAIIAgAAAA==.Nazrull:BAAANQAECgYJCgAAAA==.',
Ne='Necrofrost:BAAANQAECgEIAQAAAA==.Neobovine:BAAANQAECgQIBQAAAA==.Neoordained:BAAANQAECgEIAQAAAA==.Nesowras:BAAANQADCgYIBgABNQAECgcIEgABAAAAAA==.Nexlaht:BAAANQAECgYIEQAAAA==.',
Ni='Nicodemuss:BAAANQAECgMIAwAAAA==.Nightflare:BAAANQAECgUJCwAAAA==.',
No='Nodad:BAAANQADCgcJBwAAAA==.Nodramah:BAAANQAECggIAgAAAA==.Noeyescono:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Nokzanoh:BAAANQADCgIIAgABNQADCggJCAABAAAAAA==.Noraz:BAABNQAECoEjAAIZAAgKsiI5AwANAwAZAAgKsiI5AwANAwAAAA==.Normalsaline:BAAANQAECgMIAwAAAA==.Nosirrage:BAAANQAECgYIBgABNQAECgkJIwAOAP8hAA==.Noxoff:BAABNQAECoEgAAQFAAkKLCENCQAXAwAFAAkKrB8NCQAXAwAGAAgKzhtqIABgAgAHAAEKlBlqjwBIAAAAAA==.',
Nu='Nullan:BAAANQAECgMJBAAAAA==.Nullash:BAAANQADCgYIBgABNQAECgMJBAABAAAAAA==.Nuriel:BAAANQADCgcIBwAAAA==.',
['Nè']='Nèphelle:BAABNQAECoEkAAQDAAkKGx80EgDuAgADAAkKGx80EgDuAgACAAEKZhtyGABKAAAEAAIKXQRcTQBIAAAAAA==.',
['Në']='Nëmèsÿs:BAAANQADCggJDwAAAA==.',
Oa='Oakendale:BAAANQAECgcIEwAAAA==.Oaklei:BAAANQADCgcIEwAAAA==.Oakrageous:BAAANQAECgIIBAAAAA==.',
Ob='Obiione:BAAANQAECgEJAQAAAA==.Obionekenobi:BAAANQAECgIIAgAAAA==.',
Od='Oddball:BAAANQADCgcIBwAAAA==.Odinsson:BAAANQADCgUICAAAAA==.',
Ol='Olrun:BAAANQAECgIJBAAAAQ==.',
Or='Ordin:BAAANQADCgcIBwAAAA==.Orinek:BAAANQAECgcIDgAAAA==.Ororomunroe:BAAANQABCgQJBAAAAA==.Oruda:BAAANQADCgQIBAAAAA==.Orynnh:BAAANQADCgcIDgAAAA==.',
Os='Osogrande:BAAANQAECgYJCgAAAA==.Osso:BAAANQAECgMIAwAAAA==.',
Ow='Oway:BAAANQAECgEIAQAAAA==.Owy:BAAANQADCgUJCgAAAA==.',
Pa='Paean:BAAANQADCgYJBgAAAA==.Palajinn:BAABNQAECoEbAAMbAAkK0RtqEAAIAwAbAAkK0RtqEAAIAwAIAAMKhggo6gCDAAAAAA==.Pandaspanda:BAAANQAECgUJBQAAAA==.Passacaglia:BAAANQAECggIHgAAAQ==.Patryck:BAAANQAECgYIDQAAAA==.Payotee:BAAANQADCggIFQAAAA==.',
Pc='Pcokalypse:BAAANQAECgUJDwAAAA==.',
Pe='Peilli:BAAANQADCgcJDQAAAA==.Penderrin:BAAANQADCggIBwABNQAECggIIQAHACodAA==.Penemuel:BAAANQAECgUIDQAAAA==.Pepperfrost:BAAANQABCgIIAwAAAA==.Perkys:BAAANQABCgEIAQAAAA==.Perrinaybara:BAABNQAECoEfAAIJAAkKcR1/CAAGAwAJAAkKcR1/CAAGAwAAAA==.Petesteele:BAAANQAECgUJCwAAAA==.Petruccio:BAAANQAECgQIBgAAAA==.',
Ph='Phaet:BAAANQAECgYICwAAAA==.Phob:BAAANQAECgcIEgAAAA==.Phoreal:BAAANQAECgUICwAAAA==.Phuryberryz:BAAANQADCggJFAAAAA==.Phuryblight:BAAANQADCgYIDgAAAA==.Phurysand:BAAANQADCgUIBQAAAA==.Phurystorm:BAAANQAECgIJAwAAAA==.',
Pi='Pikasloot:BAABNQAECoEZAAMKAAgKJBd0YgBnAgAKAAgKJBd0YgBnAgALAAEK1wn2MAA2AAAAAA==.Pinechi:BAAANQADCgYIBgAAAA==.Pinestraw:BAAANQAECgYJDgAAAA==.Pinksy:BAAANQAECgYJDwAAAA==.Pipfanie:BAAANQADCgcJFgAAAA==.Pixelphobia:BAAANQAECgYIBgABNQAECgUIDAABAAAAAA==.',
Pl='Plaid:BAAANQAECgYIDAAAAA==.',
Pn='Pnakotus:BAAANQAECgUIEAABNQAECgcIDwABAAAAAA==.',
Po='Pokeey:BAAANQAECgIIBAAAAA==.Powskii:BAAANQAECgYJDgAAAA==.',
Pp='Ppsmash:BAABNQAFFIEJAAIPAAMKpw5HAwDQAAAPAAMKpw5HAwDQAAAAAA==.',
Pr='Prishe:BAAANQAECgEIAQAAAA==.Profits:BAAANQAECgUJBQAAAA==.Pronouns:BAAANQAECgcIDgAAAA==.Protege:BAAANQAECgUJCgAAAA==.',
Ps='Psy:BAAANQAECgIIBAAAAA==.Psybient:BAAANQAECgQIBAAAAA==.',
Pu='Purina:BAAANQADCgMIAwAAAA==.',
Pv='Pvp:BAAANQADCgUIBwAAAA==.',
['Pã']='Pãoduro:BAAANQADCgYIBwABNQAECgUIDgABAAAAAA==.',
['Pé']='Pérkis:BAAANQADCgcIBwAAAA==.',
Qu='Quacklord:BAAANQADCgQIBgAAAA==.',
['Qî']='Qîîz:BAAANQAECgcJEwAAAA==.',
Ra='Rakgul:BAAANQABCgMJAwAAAA==.Rambojohny:BAAANQAECggICwABNQAECgkJHwAKAMYfAA==.Rampagé:BAAANQADCgIIAgAAAA==.Ramzï:BAAANQAECgYJEAAAAA==.Randompriest:BAABNQAECoEbAAIDAAkKQBPOMQAtAgADAAkKQBPOMQAtAgAAAA==.Rangetomato:BAAANQAECgUIBQABNQAECgkJJQAIAJMeAA==.Rathernot:BAAANQAECgUIDgAAAA==.Ravenbella:BAAANQAECgQJBQAAAA==.Ravex:BAAANQADCgcIBwABNQAFFAMJCAAjAO8TAA==.Ravodin:BAAANQAECgYIBgABNQAFFAMJCAAjAO8TAA==.Ravoks:BAACNQAFFIEIAAQjAAMK7xOgAQCrAAAjAAIKkBOgAQCrAAAiAAEKrhTKIABVAAAdAAEKjQf1FABMAAA1AAQKgSMABCIACQqOIqAWAOECACIACApVIaAWAOECAB0ABAqCHwobAHkBACMAAwrlH1QNAAEBAAAA.Razalla:BAAANQAECgQICgAAAA==.Razatre:BAAANQADCgUJBQAAAA==.Razeill:BAAANQAECgEJAQAAAA==.Razellia:BAAANQADCgUICQAAAA==.',
Re='Redfiend:BAAANQAECgUICAAAAA==.Reika:BAABNQAECoEXAAMLAAcKoxi0BgAGAgALAAcKoxi0BgAGAgAKAAUKNwlJBwH+AAAAAA==.Requlier:BAAANQAECgcICwAAAA==.Revelationzz:BAABNQAECoEdAAMQAAgK2RY4DgBiAgAQAAgK2RY4DgBiAgAlAAIKYg+pUACBAAAAAA==.Rexkong:BAAANQAECgcJEwAAAA==.Reyus:BAAANQABCgQJBAABNQAECgYJDAABAAAAAA==.Rezc:BAAANQADCggJDwAAAA==.',
Rg='Rghtcousbtch:BAAANQAECgQJCAAAAA==.',
Ri='Riblets:BAAANQADCgUIBQAAAA==.Riki:BAAANQADCggIEgAAAA==.Ripetomato:BAABNQAECoElAAMIAAkKkx7cIQDgAgAIAAkKkx7cIQDgAgAbAAEKZhD8zAA/AAAAAA==.Ritualist:BAAANQADCgEJAQAAAA==.',
Ro='Rockzeeheart:BAAANQAECgQJBQAAAA==.',
Rt='Rtcmouse:BAAANQAECgYJEAAAAA==.',
Ru='Rukeshno:BAAANQAECgQICAAAAA==.Rumblemuffin:BAAANQAECggJCAAAAA==.',
['Ró']='Róckmybubble:BAAANQAECgcJEwAAAA==.',
Sa='Sacerdos:BAAANQAECgUICgAAAA==.Saijin:BAAANQAECgUJBQAAAA==.Salvatorre:BAAANQADCgQIBAAAAA==.Salysra:BAAANQAECgQIBwAAAA==.Samstein:BAAANQAECgYJDgAAAA==.Sanare:BAAANQAECgIIBAAAAA==.Sanchey:BAABNQAECoEXAAIEAAgK2BhIEgB8AgAEAAgK2BhIEgB8AgAAAA==.Sandalath:BAAANQABCgQJAgAAAA==.Sandara:BAAANQADCggIGQAAAA==.Sapz:BAAANQAECgcJEAAAAA==.Sarbrak:BAAANQADCgcJCwAAAA==.Sarka:BAAANQAECgIIAwAAAA==.Sarrh:BAAANQADCgUIBQAAAA==.Saryndra:BAAANQADCgQIBAABNQAECgYJBwABAAAAAA==.Satet:BAAANQAECgIJAgAAAA==.Savatree:BAAANQADCgYIBgAAAA==.Savvyshammy:BAAANQADCgYIBgAAAA==.Savïtar:BAAANQAECgYJDgAAAA==.',
Sc='Scarleriss:BAAANQADCgQIBwAAAA==.Scrandle:BAAANQAECgUICQAAAA==.Scythíx:BAAANQAECgEJAgABNQAECggIIQAbALUeAA==.',
Se='Sebile:BAABNQAECoEbAAImAAgKKwo9CACFAQAmAAgKKwo9CACFAQAAAA==.Selirri:BAAANQADCgUIBQAAAA==.Semishift:BAAANQAECgcJDwAAAA==.Sephroth:BAAANQAECgUJDQAAAA==.Seydin:BAAANQAECgYJDgAAAA==.Señorbear:BAAANQAECgEIAQAAAA==.',
Sh='Shaboink:BAAANQAECgYJBgAAAA==.Shabutie:BAABNQAECoEcAAMQAAgK1xZIFQABAgAQAAcKqxRIFQABAgAlAAUKtRZGLwBdAQAAAA==.Shadhahvar:BAAANQABCgcICgAAAA==.Shadowutf:BAAANQADCgYIBgAAAA==.Shadyboot:BAAANQAECgEIAQABNQAECggJGQARABAjAA==.Shaienne:BAAANQAECgYICgAAAA==.Shamtan:BAAANQADCgIIBAAAAA==.Shayná:BAAANQAECgcIEQAAAA==.Shayse:BAAANQAECgEIAQAAAA==.Shigar:BAAANQADCggICAAAAA==.Shigâr:BAAANQADCgYICgAAAA==.Shingaling:BAAANQAECgEIAQAAAA==.Shinzovoker:BAAANQAECggIEwAAAA==.Shockcore:BAAANQADCgcJDQAAAA==.Shoshlihauni:BAAANQADCgUIBAAAAA==.Shotz:BAAANQAECgEJAQABNQAECgcJEAABAAAAAA==.',
Si='Sidioüs:BAABNQAECoEZAAIRAAgKECOFDwAMAwARAAgKECOFDwAMAwAAAA==.Silvermoonto:BAAANQAECgQJBQAAAA==.Silvia:BAAANQAECgIIBAABNQAECggJGAAHADIiAA==.Sinister:BAAANQAECgEIAQAAAA==.Sinnan:BAAANQAECgQJCAAAAA==.Sintaro:BAEANQAECgYICAAAAA==.',
Sk='Skalina:BAAANQADCgEJAQAAAA==.Skidattles:BAABNQAECoEXAAISAAkKZw9NGABAAgASAAkKZw9NGABAAgAAAA==.Skullordx:BAAANQADCgQJBAAAAA==.',
Sl='Sliverblood:BAAANQADCgYIBgAAAA==.',
Sm='Smeckledorfd:BAAANQAECgQIDgAAAA==.',
Sn='Snelly:BAAANQAECgQIBAAAAA==.',
So='Sophie:BAAANQABCgYICAAAAA==.Soulzero:BAAANQAECgQJBgAAAA==.',
Sp='Spanksmoo:BAAANQAECgYJEwAAAA==.Spaxx:BAAANQAECgcIEAAAAA==.Spellstryke:BAAANQADCgUICAAAAA==.Spinnaz:BAAANQAECgYJDgAAAA==.',
St='Stalizzy:BAAANQAECgEJAQAAAA==.Stalizzyx:BAAANQAECgYJCgAAAA==.Stephani:BAAANQAECgYICAAAAA==.Stephia:BAACNQAFFIEJAAISAAQKvhCeCAA5AQASAAQKvhCeCAA5AQA1AAQKgTMAAxIACQrjIMMEAGkDABIACQrjIMMEAGkDAAwABAoUF4aoAA4BAAAA.Stevejubz:BAAANQADCgIIAgAAAA==.Stonestout:BAAANQAECgIIBAAAAA==.Storme:BAAANQAECgQIBAAAAA==.Styches:BAAANQADCgMIAwAAAA==.Stàple:BAAANQAECgQJCQAAAA==.',
Su='Suffrage:BAAANQAECgYJBwAAAA==.Suki:BAAANQADCgUIBQABNQAECgUICwABAAAAAA==.Sulveris:BAABNQAECoEdAAIWAAgKxiS3BQAnAwAWAAgKxiS3BQAnAwAAAA==.Sunnyshaman:BAABNQAECoEXAAIRAAcK1xXSTAC1AQARAAcK1xXSTAC1AQAAAA==.Sunstriker:BAAANQADCgQIBAAAAA==.Suzygreenbrg:BAAANQADCgMIAwAAAA==.',
Sy='Syleane:BAAANQABCgYICgAAAA==.Syque:BAAANQADCgYIBgAAAA==.',
['Sä']='Sämael:BAAANQADCggJDgABNQAECgYJDgABAAAAAA==.',
['Sì']='Sìnìster:BAABNQAECoEgAAIOAAkKzR5ECAAwAwAOAAkKzR5ECAAwAwAAAA==.',
Ta='Tamachi:BAAANQAECgIIAgAAAA==.Tanaxe:BAAANQADCgMJAwAAAA==.Tanelorñ:BAAANQADCgcJCwAAAA==.Tanksomes:BAABNQAECoEZAAIHAAgKIxf9IwA3AgAHAAgKIxf9IwA3AgAAAA==.Tareilimage:BAAANQAECgQIBAAAAA==.Taurenman:BAAANQAECgYICgAAAA==.',
Te='Tecom:BAAANQAECgQJBQAAAA==.Teddiebolt:BAAANQAECgMIAwABNQAFFAEJAQABAAAAAA==.Teddifer:BAAANQAFFAEJAQAAAA==.Temptus:BAAANQAECgYJEQAAAA==.Terrenarde:BAAANQAECgQJCAABNQAECgcIFQABAAAAAA==.',
Th='Thdrae:BAAANQAECggICAAAAA==.Thejondoepro:BAABNQAECoEaAAINAAgKxhOaBgAVAgANAAgKxhOaBgAVAgAAAA==.Thicklog:BAAANQAECgQJCAAAAA==.Thisylas:BAAANQABCgMIAwABNQAECgYJBwABAAAAAA==.Thorrina:BAAANQABCgIIAQAAAA==.Thsbursysrur:BAAANQAECgYJDgAAAA==.Thulsadoom:BAAANQADCgQIBQAAAA==.Thunderswift:BAABNQAECoEaAAISAAgKmBOiHAANAgASAAgKmBOiHAANAgAAAA==.Thæria:BAAANQAECgUJDQAAAA==.',
Ti='Tia:BAAANQAECgYIDwAAAA==.Tiltion:BAAANQAECgQJBQAAAA==.Tind:BAAANQABCgQIBwAAAA==.Tinggu:BAAANQADCggIGAAAAA==.Tinitus:BAAANQAECgcJEAAAAA==.Tish:BAAANQADCgYIEQAAAA==.Tizzona:BAACNQAFFIEGAAIJAAMKyRzjBAAeAQAJAAMKyRzjBAAeAQA1AAQKgSYAAgkACQqxJY4BAL8DAAkACQqxJY4BAL8DAAE1AAMKBwgHAAEAAAAA.',
Tl='Tlachtgae:BAAANQADCgIIAwAAAA==.',
To='Tobygodz:BAAANQAECgQIEAAAAA==.Tomatofest:BAAANQAECgMIBQAAAA==.Tomlong:BAAANQABCgUIBAAAAA==.Tookdk:BAAANQAECgcJEwAAAA==.Tookdrin:BAAANQAECgYIBwABNQAECgcJEwABAAAAAA==.Tooksamdi:BAAANQADCgcIBwABNQAECgcJEwABAAAAAA==.Toreto:BAAANQADCgMJAwAAAA==.Torvik:BAAANQADCgIIAgAAAA==.',
Tr='Treckken:BAAANQAECgYJDgAAAA==.Treemendous:BAAANQABCgIIAgAAAA==.Treepunch:BAAANQADCgYIDAAAAA==.',
Tu='Tuknar:BAAANQAECgUIDQAAAA==.Tulleren:BAAANQADCgcIIAAAAA==.',
Tv='Tvalin:BAAANQAECgQIBAABNQAECgUICAABAAAAAA==.',
Ty='Tynan:BAAANQAECgUJDgAAAA==.Typhön:BAAANQAECgMJBAAAAA==.',
Tz='Tzezae:BAAANQAECgUICgAAAA==.',
['Tï']='Tïlo:BAAANQAECgcJEgAAAA==.',
Uc='Ucy:BAAANQADCggJEAAAAA==.',
Ul='Ulfvaer:BAAANQABCgMIAwAAAA==.',
Um='Umbrafrost:BAAANQAECgUJCwAAAA==.',
Un='Unspeakable:BAAANQADCgUIBQAAAA==.Untot:BAABNQAECoEWAAMgAAgK+BUXEQAJAgAgAAgK+BUXEQAJAgAIAAIK4AHiPAEfAAAAAA==.',
Va='Vach:BAAANQAECgIIAgAAAA==.Vacui:BAAANQAECgUJBgAAAA==.Vaedoc:BAAANQADCgUIBQAAAA==.Valezriel:BAAANQAECgQJBwABNQAECgUICAABAAAAAA==.Valintine:BAAANQAECgIIAgAAAA==.Vallence:BAABNQAECoEbAAIKAAgKFiQ7IQAyAwAKAAgKFiQ7IQAyAwAAAA==.Valorem:BAAANQADCgEJAQAAAA==.Valorie:BAAANQAECgcICgAAAA==.Valrev:BAAANQADCgcIBwAAAA==.Vassaro:BAAANQAECgEIAQABNQAECgYIDQABAAAAAA==.',
Ve='Vermivora:BAAANQAECgIJBAAAAA==.Vettè:BAABNQAECoEXAAIbAAgKdRCMQADzAQAbAAgKdRCMQADzAQAAAA==.Vevoxypoo:BAAANQADCggJDwAAAA==.',
Vi='Villivia:BAABNQAECoEWAAIHAAgKBxjVIwA4AgAHAAgKBxjVIwA4AgAAAA==.Viracia:BAAANQAECggIBgAAAA==.Virtigo:BAAANQAECgIJAwAAAA==.Visari:BAAANQAECgIIBAAAAA==.Vitole:BAAANQADCgEIAQABNQAECgcIDwABAAAAAA==.',
Vo='Voidcollapse:BAAANQADCgUJBgAAAA==.Voidnut:BAAANQAECgIIAgAAAA==.Voss:BAAANQADCggICQAAAA==.',
['Vê']='Vêstïge:BAAANQAECgQIBQAAAA==.',
Wa='Watermyrain:BAABNQAECoEaAAMiAAgKSSP5DQAcAwAiAAgKkSL5DQAcAwAdAAIKIBxOPQCpAAAAAA==.',
We='Weeble:BAAANQADCgUICgAAAA==.Weebu:BAAANQAECgUJDQAAAA==.Welsley:BAAANQAECgUJDQAAAA==.',
Wh='Whispe:BAAANQAECgYIDwAAAA==.',
Wi='Wicate:BAAANQAECgYJCwAAAA==.Wildedge:BAAANQADCgYICgAAAA==.Wilder:BAABNQAECoEeAAIgAAkKiRQMDwAqAgAgAAkKiRQMDwAqAgAAAA==.Willendra:BAABNQAECoEbAAIXAAgKexxaGgCjAgAXAAgKexxaGgCjAgAAAA==.Wir:BAABNQAECoEeAAIIAAgKJh//KAC7AgAIAAgKJh//KAC7AgAAAA==.',
Wo='Wolfery:BAAANQAECgUJDwAAAA==.Wolowizard:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Wonderface:BAAANQADCgcIBwABNQAECgUIDgABAAAAAA==.Wonderfu:BAAANQAECgUICgAAAA==.Wookreformed:BAAANQAECgEIAQAAAA==.Wordrid:BAAANQADCgYIEgAAAA==.',
Wt='Wtfocks:BAAANQAECgQJCQAAAA==.',
Wu='Wuiigii:BAABNQAECoEXAAIgAAgK4BnJDQA/AgAgAAgK4BnJDQA/AgAAAA==.',
Xa='Xaena:BAAANQADCgcIDQAAAA==.Xanatis:BAAANQADCgYIBgABNQAECggIIQAHACodAA==.Xatus:BAAANQAECgMIBQAAAA==.',
Xe='Xendrik:BAAANQAECgYJDAAAAA==.Xenyl:BAAANQADCgcJDQAAAA==.',
Xi='Xiaolia:BAAANQAECgQJBAAAAA==.',
Ya='Yamihikari:BAAANQAECgUICAAAAA==.Yarela:BAAANQADCgYJDQAAAA==.',
Ye='Yedster:BAAANQAECgUIBQAAAA==.Yenara:BAABNQAECoEYAAIEAAcKdx0AFABhAgAEAAcKdx0AFABhAgAAAA==.Yesrav:BAAANQAECgIIAgAAAA==.',
Yi='Yihua:BAAANQAECgcIFQAAAQ==.Yinohn:BAAANQADCggJCAAAAA==.Yippee:BAAANQAECgQJBQABNQAECgQIBgABAAAAAA==.',
Yu='Yumba:BAAANQAECgIIAwAAAA==.',
['Yå']='Yång:BAAANQADCgYICAAAAA==.',
Za='Zaborg:BAABNQAECoEXAAMiAAgKywllbACAAQAiAAcKUQllbACAAQAdAAQKMQbmNwC+AAAAAA==.Zalerien:BAAANQADCgEIAQABNQAECgcIFQABAAAAAA==.Zandig:BAAANQAECgUJCgAAAA==.Zappyzapp:BAAANQADCgMIAwAAAA==.Zartman:BAAANQADCgUIBQAAAA==.Zathog:BAAANQAECgIIAgAAAA==.',
Ze='Zebin:BAAANQADCgUIBQAAAA==.Zeem:BAAANQAECgIIAwAAAA==.Zerthimon:BAAANQABCgIIAgAAAA==.',
Zh='Zharae:BAAANQAECgEIAgAAAA==.',
Zi='Ziaroe:BAAANQADCgEIAQAAAA==.Ziayn:BAAANQADCgQIBQAAAA==.',
Zo='Zoet:BAAANQAECgcJEgAAAA==.Zohân:BAAANQAECgIIAgAAAA==.',
Zu='Zulani:BAAANQAECgcJDwAAAA==.Zurana:BAAANQADCgYIBgABNQAECgQJBgABAAAAAA==.',
['Àl']='Àlik:BAABNQAECoEbAAMbAAgKaxM/NwAdAgAbAAgKaxM/NwAdAgAIAAcKcAwUhABzAQAAAA==.',
['Áa']='Áayla:BAAANQADCggICAAAAA==.',
['Çh']='Çhökèm:BAAANQAECggJEgABNQAECgkJIAAKAP8bAA==.',
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
