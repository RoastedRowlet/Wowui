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

local lookup = {'Warlock-Demonology','Warrior-Protection','Paladin-Retribution','Priest-Holy','Priest-Discipline','Priest-Shadow','Mage-Arcane','Unknown-Unknown','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Druid-Feral','Evoker-Devastation','Druid-Restoration','Paladin-Protection','Evoker-Preservation','Monk-Windwalker','Monk-Brewmaster','Mage-Frost','Warrior-Arms','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Holy','Shaman-Elemental','Hunter-BeastMastery','Shaman-Enhancement','Shaman-Restoration','Monk-Mistweaver','Hunter-Survival','Warrior-Fury','Druid-Balance','Warlock-Destruction','Rogue-Subtlety','Hunter-Marksmanship','Rogue-Outlaw','Druid-Guardian','Evoker-Augmentation','DemonHunter-Vengeance','Warlock-Affliction','Mage-Fire','Rogue-Assassination',}
local provider = {region='US',realm='Turalyon',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Absorb:BAAANQAECgMIBQABNQAECgkJHgABAIEcAA==.',
Ac='Aconcerious:BAABNQAECoEfAAICAAgKSA/nFgCPAQACAAgKSA/nFgCPAQAAAA==.Actionbztrd:BAABNQAECoEeAAIDAAgKyCJDIAArAwADAAgKyCJDIAArAwAAAA==.',
Ad='Adamancy:BAAANQAECgUICQAAAA==.Addlee:BAABNQAECoEpAAQEAAkKhhcpMQCDAgAEAAkKhhcpMQCDAgAFAAYKXAmQDwAaAQAGAAEKFQjDaQA6AAAAAA==.Addler:BAAANQAECggIBAAAAA==.Aduro:BAABNQAECoEZAAIHAAgK/RuEdwB5AgAHAAgK/RuEdwB5AgAAAA==.',
Ae='Aeleleroesh:BAAANQABCgIIAgABNQABCgQIBAAIAAAAAA==.Aeolyte:BAABNQAECoEYAAIGAAgKpgovLACcAQAGAAgKpgovLACcAQAAAA==.Aeradeath:BAABNQAECoEuAAQJAAkKuiETEQDnAgAJAAkKfB8TEQDnAgAKAAkKghuLIgCcAgALAAUKEyPtQwDMAQAAAA==.Aeronir:BAABNQAECoEqAAIDAAgKDw8QkwDJAQADAAgKDw8QkwDJAQAAAA==.',
Ah='Ahlis:BAAANQAECgUICgAAAA==.',
Ai='Aidur:BAAANQADCgcIDAAAAA==.',
Ak='Akabaggins:BAAANQAECgIIAgAAAA==.Akuul:BAAANQAECgEIAQABNQAECgkJNAAMAPQiAA==.',
Al='Alacrys:BAAANQAECgQIDQAAAA==.Aldyrían:BAAANQADCggIFgAAAA==.Alear:BAABNQAECoEWAAINAAYKbBS6GgCAAQANAAYKbBS6GgCAAQAAAA==.Alessie:BAAANQAECgQIBAAAAA==.Alltreg:BAAANQAECgQICQAAAA==.Alrir:BAAANQAECgIIAgAAAA==.Alunamura:BAAANQABCgYIBgAAAA==.Alyrii:BAAANQADCgQIBAABNQAECgQIBwAIAAAAAA==.',
Am='Ambrose:BAAANQADCgcIBwAAAA==.Amelyn:BAAANQAECgQIBQAAAA==.Amrén:BAABNQAECoEbAAIOAAgKHAamMwBJAQAOAAgKHAamMwBJAQAAAA==.',
An='Anessara:BAAANQADCggICAABNQAECgIIAgAIAAAAAA==.Angriff:BAAANQAECgcIEwAAAA==.Angusmcrizle:BAABNQAECoEZAAIPAAcKvhJbJQCHAQAPAAcKvhJbJQCHAQAAAA==.Ankalagon:BAABNQAECoEaAAMNAAcK0Aj/HQBUAQANAAcK0Aj/HQBUAQAQAAUKbgWFNADQAAAAAA==.Antilogy:BAAANQADCgIIAgABNQAECgYIDQAIAAAAAA==.Antrum:BAAANQADCgEIAQAAAA==.',
Ar='Aranjah:BAAANQAECgIIAgAAAA==.Ardius:BAABNQAECoEpAAMRAAkKyR3+DwDJAgARAAkKcB3+DwDJAgASAAUKnxg1FQBvAQAAAA==.Arenaria:BAAANQAECgUIDwAAAA==.Arishokk:BAAANQAECgYIEwAAAA==.Arkmagi:BAAANQADCgUJBQABNQAFFAMIBgAKAOIRAA==.Arks:BAABNQAECoEtAAMHAAkK9hyVYQCoAgAHAAkK/BuVYQCoAgATAAIK4xzgKQCCAAAAAA==.Arkthugal:BAACNQAFFIEGAAIKAAMK4hGuDgDvAAAKAAMK4hGuDgDvAAA1AAQKgSsAAgoACQqtIzsKAFgDAAoACQqtIzsKAFgDAAAA.Arktwogal:BAAANQADCgEIAQABNQAFFAMIBgAKAOIRAA==.Arteezer:BAAANQADCgcIBwABNQAFFAUICgAGANEKAA==.Artemiye:BAAANQAECgYICgAAAA==.Artikblaz:BAAANQAECgYIDQAAAA==.Arun:BAAANQADCgYIBgAAAA==.Arés:BAAANQAECgQIBgAAAA==.',
As='Ashieldu:BAAANQAECgUICQAAAA==.Ashkikur:BAAANQADCgYIBgAAAA==.Askanni:BAABNQAECoEXAAIUAAgKsgUJvwBMAQAUAAgKsgUJvwBMAQAAAA==.Astharot:BAABNQAECoEZAAMVAAUKzxilTAAzAQAVAAQKpxulTAAzAQAWAAUK2Q92PwAfAQAAAA==.Astralain:BAAANQAECgYIEAAAAA==.Astrozen:BAAANQADCgUIBQAAAA==.Asture:BAAANQADCgUIBQAAAA==.',
At='Atulmoji:BAAANQAECgEIAQAAAA==.',
Au='Augdra:BAAANQAECgIIAgAAAA==.Aurelion:BAAANQAECgEIAQAAAA==.Auriauna:BAAANQAECgUIEQAAAA==.Auroralai:BAAANQAECgQIBAAAAA==.',
Av='Avadagryth:BAABNQAECoEdAAIXAAkKXRx5GgD5AgAXAAkKXRx5GgD5AgAAAA==.Avanyani:BAAANQAECgQICQAAAA==.Avidowned:BAAANQAECgYIEQAAAA==.Avus:BAAANQAECgQICAABNQAECggIHAAYAM0fAA==.',
Ay='Ayllo:BAAANQAECgEJAQABNQAECgUIBwAIAAAAAA==.',
Ba='Baalis:BAAANQADCgYICAABNQAECgUICwAIAAAAAA==.Bacalhau:BAAANQAECgcICwAAAA==.Baelgoroth:BAABNQAECoEbAAIDAAgKXBmZYwBDAgADAAgKXBmZYwBDAgAAAA==.Baphomelle:BAAANQAECgYIBgAAAA==.Barachiel:BAABNQAECoEhAAIPAAkKBx7HCAD2AgAPAAkKBx7HCAD2AgAAAA==.Basheaba:BAABNQAECoEmAAIZAAkK+SByDABpAwAZAAkK+SByDABpAwAAAA==.Batrous:BAAANQADCgcIDAAAAA==.Battlerbrian:BAAANQAECgQIBAAAAA==.',
Be='Belandra:BAABNQAECoEkAAITAAgK0xJ6CgDuAQATAAgK0xJ6CgDuAQAAAA==.Belegond:BAAANQADCgcIBwAAAA==.Belishario:BAABNQAECoEdAAMaAAgKFx08DQCAAgAaAAcKeyA8DQCAAgAbAAEKVhJP/gA7AAAAAA==.Belladawna:BAABNQAECoEqAAIHAAgKaRQnoAAhAgAHAAgKaRQnoAAhAgAAAA==.Bellatrex:BAAANQADCgEIAQAAAA==.Beredeath:BAAANQADCgcIBwABNQAECgIIAgAIAAAAAA==.Bereid:BAAANQAECgIIAgAAAA==.Berejitsu:BAAANQADCgQIBQABNQAECgIIAgAIAAAAAA==.Besk:BAAANQADCggICQAAAA==.Beârback:BAEANQAECggIEQAAAA==.',
Bi='Bigchops:BAAANQAECgQJBwAAAA==.Bigfuzzy:BAAANQAECgIIAgAAAA==.Bigtime:BAAANQADCgYJCAAAAA==.Bigwillie:BAAANQAECgQIDQAAAA==.',
Bl='Blazerbrew:BAABNQAECoEWAAMRAAkKOBghHAAtAgARAAgKLRchHAAtAgAcAAYKLAeWKwDlAAAAAA==.Blezaa:BAABNQAECoEZAAMdAAgKpxH8BgDoAQAdAAcKYhL8BgDoAQAZAAUKWg2hygA4AQAAAA==.Blinknleap:BAABNQAECoEjAAIeAAkKWx2NAwD5AgAeAAkKWx2NAwD5AgAAAA==.Blinkyflakes:BAAANQADCgEIAQAAAA==.Blooddrakken:BAAANQAECgQIBwABNQAECgQICQAIAAAAAA==.Blooddruid:BAAANQADCgYICwABNQAECgQICQAIAAAAAA==.Bloodoxel:BAAANQAECgEIAQAAAA==.',
Bn='Bn:BAAANQAECgIIAgAAAA==.',
Bo='Boring:BAABNQAECoEdAAIUAAkK/Rt0LgDwAgAUAAkK/Rt0LgDwAgAAAA==.Boxlunch:BAAANQADCgYIBgABNQAECgkJLAAWAJEiAA==.Boyana:BAAANQADCgcICwAAAA==.',
Br='Brandybuck:BAAANQAECgQIBwAAAA==.Brewliever:BAAANQAECgUIBQABNQAECgkJHgABAIEcAA==.Brucelééroy:BAAANQAECgIIAwAAAA==.Bruski:BAAANQABCgEIAQAAAA==.Bruskii:BAABNQAECoEfAAIfAAcKwR2cMAA3AgAfAAcKwR2cMAA3AgAAAA==.',
Bu='Bulsharess:BAAANQADCgQIBAAAAA==.Bulshari:BAAANQADCgUIBQAAAA==.Bunns:BAAANQADCgcIDQAAAA==.Burningrash:BAAANQADCgYIDwAAAA==.Butmunky:BAAANQAECgEIAQABNQAFFAQICwAHABoTAA==.Butternugget:BAAANQAECgUIBQAAAA==.Buuffy:BAAANQAECgQICwAAAA==.',
By='Byleana:BAAANQADCggIFgABNQAECgkJLgALAE4hAA==.Byléana:BAABNQAECoEuAAMLAAkKTiEjDgAtAwALAAkKTiEjDgAtAwAKAAMKoB6fewADAQAAAA==.Bytem:BAABNQAECoEbAAIfAAkK0SDkCwBdAwAfAAkK0SDkCwBdAwAAAA==.Byuru:BAAANQADCgYIBgABNQAECgcIDgAIAAAAAA==.',
Ca='Caelyn:BAAANQADCgYICgAAAA==.Caewyn:BAAANQADCggJFQAAAA==.Calysta:BAAANQAECgYIEQAAAA==.Candalen:BAAANQABCgYIBgAAAA==.Carleys:BAAANQAECgYICAAAAA==.Cassara:BAAANQAECgUICAAAAA==.Cathella:BAAANQADCgYICQAAAA==.',
Ce='Ceberus:BAAANQADCgUIBQAAAA==.Celek:BAAANQAECggICAAAAA==.Celekai:BAABNQAECoEaAAIHAAcKmhwIowAbAgAHAAcKmhwIowAbAgABNQAECggICAAIAAAAAA==.Celi:BAABNQAECoEaAAIOAAYKwAxqNgA0AQAOAAYKwAxqNgA0AQAAAA==.Celébrin:BAAANQABCgIIAgAAAA==.Cerandan:BAAANQABCgQIBAAAAA==.Cerbadin:BAAANQAECgEIAQABNQAECggIHAAZAPceAA==.Cerbydrood:BAAANQADCgYIBgABNQAECggIHAAZAPceAA==.Cerbyhunt:BAABNQAECoEcAAIZAAgK9x7cLADGAgAZAAgK9x7cLADGAgAAAA==.Cerbymage:BAAANQADCgIIAgABNQAECggIHAAZAPceAA==.Cerbywar:BAAANQADCgcIBwABNQAECggIHAAZAPceAA==.',
Ch='Cheeana:BAAANQAECgQICAAAAA==.Cherlindrea:BAAANQAECgYIEwABNQAECgkJHwASALwXAA==.Chhive:BAAANQAECgUICQAAAA==.Chickenstrip:BAAANQADCgYIDQABNQAECgQIBAAIAAAAAA==.Chopchop:BAAANQADCggIDwAAAA==.Chrysus:BAAANQAECgYIBgAAAA==.',
Ci='Cidal:BAAANQAECgUIDwAAAA==.Cindii:BAAANQADCgcICwAAAA==.',
Cl='Clada:BAAANQAECgQIDQABNQAECgQIBgAIAAAAAA==.Clancy:BAAANQAECgEIAQAAAA==.Cleric:BAAANQAECgEIAQAAAA==.Clifmantooth:BAAANQAECgcIEAAAAA==.',
Co='Colada:BAAANQABCggIDgAAAA==.Coldkiller:BAAANQAECgIIAgAAAA==.Coldphusion:BAAANQABCgQIBAAAAA==.Coneau:BAAANQADCgIIAgABNQAECgYICAAIAAAAAA==.Couprenarde:BAAANQADCgMIAwABNQAECggIHQAIAAAAAA==.Courpsie:BAABNQAECoEeAAIeAAgK8Q5HDADTAQAeAAgK8Q5HDADTAQAAAA==.Courtvoke:BAAANQAECgEIAQABNQAECgkJHQAUAP0bAA==.',
Cr='Crager:BAAANQAECgUIDwAAAA==.Crazyjamu:BAAANQAECgIIAgAAAA==.Creamygees:BAABNQAECoElAAIDAAgKYB/jOADKAgADAAgKYB/jOADKAgAAAA==.Creaturé:BAAANQADCggIHQAAAA==.Criaharn:BAAANQAECgYIBgAAAA==.Cripp:BAAANQAECgUICwAAAA==.Crybeardin:BAAANQAECgYICAABNQAECgkJHwADAMUiAA==.Cryohunter:BAAANQAECgQJCAAAAA==.',
Ct='Ctair:BAABNQAECoEdAAIcAAgKpA+MGwCdAQAcAAgKpA+MGwCdAQAAAA==.',
Cu='Cuckcommando:BAAANQADCgIIAgABNQAFFAQIDQASAI8UAA==.',
Cy='Cyberhexia:BAAANQAECggICAAAAA==.Cybersorc:BAAANQAECggIDgAAAA==.Cyrce:BAAANQADCgYIBgAAAA==.Cyrs:BAAANQAECgUIDgAAAA==.Cysvarion:BAAANQAECgQIBgAAAA==.',
['Có']='Ców:BAAANQAECgIIAgABNQAECggIHQAaABcdAA==.',
['Cø']='Cønø:BAAANQAECgYICAAAAA==.',
Da='Daddi:BAABNQAECoEbAAIHAAgKbg9QtAD4AQAHAAgKbg9QtAD4AQAAAA==.Dairs:BAAANQAECgEIAQAAAA==.Dajjflajj:BAAANQAECgYIDwAAAA==.Dakdubustr:BAAANQADCgYICwAAAA==.Dalitha:BAAANQAECgIIAgABNQAECggIHQAIAAAAAA==.Daltan:BAAANQAECgUICgABNQAECgcIGAABABIbAA==.Dalthero:BAAANQADCgQIBAABNQAECgcIGAABABIbAA==.Dalynar:BAAANQADCgQIBAAAAA==.Damukovu:BAAANQAECgQIBQAAAA==.Danayro:BAABNQAECoEhAAIgAAgKOw/AEADrAQAgAAgKOw/AEADrAQAAAA==.Dandron:BAAANQAECgYICQAAAA==.Dankmeme:BAAANQAECgQIBgABNQAECggIEwAIAAAAAA==.Darc:BAAANQADCggIDwAAAA==.Darksath:BAAANQADCgMIAgAAAA==.Darkvag:BAABNQAECoEjAAMTAAkKwSK1BwBCAgATAAcKfx61BwBCAgAHAAcKGR6cmQAvAgAAAA==.Dav:BAAANQAECgcIBwAAAA==.Davalos:BAAANQAECgUICAAAAA==.Davepark:BAAANQADCgUIBQAAAA==.Davos:BAAANQAECgEIAQAAAA==.Daygos:BAABNQAECoElAAIZAAkKNSKcEwA5AwAZAAkKNSKcEwA5AwAAAA==.Daêmon:BAAANQAECgUIBwAAAA==.',
De='Deadsparks:BAABNQAECoEtAAIKAAkKHiQoCABvAwAKAAkKHiQoCABvAwAAAA==.Deathosso:BAAANQAECgUICAAAAA==.Deathveta:BAAANQAECgMIAwAAAA==.Deftech:BAABNQAECoEmAAIhAAkK5CSaAADjAwAhAAkK5CSaAADjAwAAAA==.Demonic:BAAANQAECgUIDwAAAA==.Demonmommy:BAAANQAECgYIBgABNQAECgcIDgAIAAAAAA==.Demonrocket:BAAANQAECgUIDwAAAA==.Denkou:BAAANQADCgIIAgABNQADCgYIDAAIAAAAAA==.Derisive:BAAANQAECgUIBAABNQAECggIHQAJAHYkAA==.Destris:BAAANQADCgYIBwAAAA==.Devac:BAAANQADCgYIBgABNQAECggIHQAbALYWAA==.Device:BAAANQAECgIIAgAAAA==.Devilslayery:BAABNQAECoEXAAQKAAcKBgtyZQBVAQAKAAcKBgtyZQBVAQALAAQK1gZQlgCRAAAJAAEKYgMXoQAhAAAAAA==.',
Dh='Dharien:BAABNQAECoEfAAIDAAkKxSJnGgBFAwADAAkKxSJnGgBFAwAAAA==.',
Di='Diamondbob:BAAANQADCgEIAQAAAA==.Dias:BAAANQADCgIIAgAAAA==.Digbicktus:BAAANQAECgIIAgAAAA==.Dilandria:BAAANQADCgEIAQAAAA==.Direheart:BAAANQAECgUIDwAAAA==.Discountable:BAAANQADCgYIBgABNQAECggIHQACABsbAA==.',
Do='Dommothop:BAACNQAFFIEVAAIhAAcKcyRTAADQAgAhAAcKcyRTAADQAgA1AAQKgS0AAiEACQrqJlUAAPgDACEACQrqJlUAAPgDAAAA.Dorp:BAAANQAECgYICgAAAA==.Dovahbruh:BAAANQABCgYIBgAAAA==.',
Dr='Dragdon:BAAANQAECgQIBAABNQAECggIEwAIAAAAAA==.Dragosangue:BAAANQAECgQICQAAAA==.Dragundeez:BAAANQAECgIIAwABNQAECgkJPAAbAO0iAA==.Drakebeard:BAABNQAECoEcAAIRAAkKrR71CgAOAwARAAkKrR71CgAOAwAAAA==.Drakenjosh:BAAANQAECgUIBQABNQAECgkJKgABAP8dAA==.Drayus:BAABNQAECoEcAAMYAAgKzR9FIgDhAgAYAAgKzR9FIgDhAgAbAAIKrwRA+QBFAAAAAA==.Driitz:BAABNQAECoElAAIZAAgKMxh8SgBnAgAZAAgKMxh8SgBnAgAAAA==.',
Du='Duvoh:BAABNQAECoEeAAIXAAYKiBoaZQDDAQAXAAYKiBoaZQDDAQAAAA==.',
Dw='Dweezilla:BAAANQAECgMIBgAAAA==.Dweezneez:BAAANQADCgYIBwAAAA==.',
['Dè']='Dèathmarch:BAAANQADCgcIDAAAAA==.',
Ea='Easimode:BAAANQADCgYIBgAAAA==.Eatswutsdead:BAAANQADCgYIBgAAAA==.',
Ec='Echarrial:BAAANQAECgIIAgAAAA==.Eclipsweaver:BAAANQABCgIIAgAAAA==.',
Ed='Eddias:BAAANQADCggIDwAAAA==.Edge:BAABNQAECoEgAAIVAAgKrh16GgCjAgAVAAgKrh16GgCjAgAAAA==.',
Ek='Eklypsis:BAAANQADCggIDwAAAA==.',
El='Elang:BAAANQAECgYIEwAAAA==.Elange:BAAANQADCgYIEgAAAA==.Elazuria:BAAANQAECgIIAgAAAA==.Elementrix:BAAANQAECgYIDwAAAA==.Elgrandè:BAAANQADCgQIBAAAAA==.Elmafudd:BAAANQAECgIIAgABNQAECggIHQAIAAAAAA==.Elsadieorc:BAAANQADCgcIDwAAAA==.Eluss:BAAANQADCgUIBQAAAA==.Elvay:BAAANQAECggIEQAAAA==.Elyos:BAAANQADCgcIFAAAAA==.Elzar:BAAANQAECgUIDwAAAA==.',
Em='Emeraldflame:BAAANQADCgMIAwAAAA==.Emodk:BAAANQAECgYIBgABNQAFFAgIKAAiAHshAA==.',
En='Enlytnin:BAAANQAECgEIAQAAAA==.Entarri:BAABNQAECoEbAAICAAgKFhe4DgATAgACAAgKFhe4DgATAgAAAA==.Entivala:BAAANQADCgYIBgAAAA==.Envoi:BAAANQADCggIEQAAAA==.',
Ep='Eplodin:BAAANQAECgYIBgAAAA==.',
Eq='Equitem:BAABNQAECoEcAAILAAkKuBakMAAxAgALAAkKuBakMAAxAgABNQAECgkJJQAPAKIhAA==.',
Er='Eridanos:BAAANQADCggIFAAAAA==.',
Es='Escanör:BAAANQAECgQIBAABNQAECgcIDgAIAAAAAA==.Eshel:BAABNQAECoEiAAIjAAgKDQcCDACDAQAjAAgKDQcCDACDAQAAAA==.Eshmel:BAAANQAECgQJBAAAAA==.Essek:BAABNQAECoEdAAILAAcKMRp5NgAQAgALAAcKMRp5NgAQAgAAAA==.',
Ev='Everfrost:BAACNQAFFIELAAMHAAQKGhO1KgDzAAAHAAMKABO1KgDzAAATAAEKZhOXDQBOAAA1AAQKgSQAAwcACQrkHxVAAPcCAAcACQrkHxVAAPcCABMABQp0EwIZAAgBAAAA.Evidicus:BAABNQAECoElAAIeAAgKKxwhBgCGAgAeAAgKKxwhBgCGAgAAAA==.Evilscarnage:BAACNQAFFIEFAAMZAAIK+wswLQBQAAAZAAEK8w0wLQBQAAAdAAEKBAo7AgBLAAA1AAQKgRwAAh0ACQrCGL8DAJ4CAB0ACQrCGL8DAJ4CAAAA.Evilstotem:BAABNQAECoEhAAIaAAkKkhjrCgCuAgAaAAkKkhjrCgCuAgAAAA==.Evu:BAABNQAECoEjAAILAAkKpSFvCgBUAwALAAkKpSFvCgBUAwAAAA==.',
Ex='Exkath:BAACNQAFFIEGAAMJAAMK5hsjCAAgAQAJAAMK5hsjCAAgAQAKAAEK5BfvHABHAAA1AAQKgSgAAwkACQodJugCAKoDAAkACQoRJugCAKoDAAoABQpdJDlJAMsBAAAA.',
Ez='Ezlyn:BAAANQAECgUICQAAAA==.Ezrael:BAAANQADCgcIBwAAAA==.',
Fa='Faedrela:BAABNQAECoEYAAIZAAYKvgezvABVAQAZAAYKvgezvABVAQAAAA==.Falito:BAABNQAECoEfAAQGAAcKWxCWMgBmAQAGAAYK1w6WMgBmAQAEAAYKhxDafgBiAQAFAAEK5QKGKgApAAAAAA==.Farben:BAABNQAECoEYAAIOAAkKOhkREgChAgAOAAkKOhkREgChAgAAAA==.Fatabbot:BAAANQAECgEIAgABNQAECgIIAgAIAAAAAA==.',
Fe='Felines:BAAANQAECgIIAgAAAA==.Felinesx:BAAANQADCgYIBgAAAA==.Felixfenton:BAAANQADCgcIBwABNQAECgYICAAIAAAAAA==.Fellbane:BAAANQADCgYICgAAAA==.Feohh:BAAANQAECgUIDwAAAA==.',
Fi='Fiddlesticks:BAABNQAECoEqAAIRAAkKSxvXDwDLAgARAAkKSxvXDwDLAgAAAA==.Findale:BAABNQAECoEmAAIOAAkKCx5CCgAJAwAOAAkKCx5CCgAJAwAAAA==.',
Fj='Fjalar:BAAANQAECggICwAAAA==.',
Fk='Fkxstvebee:BAAANQAECggIDgABNQAECgkJIwAXAIUQAA==.',
Fl='Flajj:BAABNQAECoEjAAIHAAkKnBufVADGAgAHAAkKnBufVADGAgAAAA==.Flamezephyr:BAABNQAECoElAAMTAAcKESVOFgAnAQAHAAYKhSAWlQA5AgATAAMK0CFOFgAnAQAAAA==.Flufbuns:BAAANQADCggIFAAAAA==.Flurryflirt:BAAANQADCgIIAgAAAA==.',
Fo='Foxnews:BAAANQAECgYIEQAAAA==.',
Fr='Frackingheal:BAAANQABCgQIBAAAAA==.Fredfazbear:BAACNQAFFIEIAAIfAAQKjBC9EAAkAQAfAAQKjBC9EAAkAQA1AAQKgTMAAh8ACQq2ILQQAC8DAB8ACQq2ILQQAC8DAAAA.Frostystrips:BAAANQAECgQIBAAAAA==.Frozat:BAAANQADCgQIBgAAAA==.Frumdaheart:BAAANQADCgUIBQABNQAECgcIGwAZAMkVAA==.',
Fu='Furballs:BAAANQAECgEIAQABNQAFFAQICwAHABoTAA==.Furiza:BAAANQADCgYIBgAAAA==.Furybztrd:BAAANQAECgIIAgAAAA==.Fuzzybuzzy:BAAANQABCgMIAwAAAA==.',
Ga='Gagno:BAAANQADCgIIAgAAAA==.Gagnot:BAAANQAECgcIBwAAAA==.Galadriál:BAAANQADCggIFAAAAA==.Galisa:BAAANQABCgIIAgAAAA==.Garnimal:BAABNQAECoEXAAIUAAcK4xlNfAACAgAUAAcK4xlNfAACAgAAAA==.',
Ge='Georgigeo:BAABNQAECoEmAAIZAAkKhCPfCQB+AwAZAAkKhCPfCQB+AwAAAA==.',
Gh='Ghazkill:BAAANQABCgEIAQAAAA==.Ghostbrue:BAAANQAECgUIDQAAAA==.',
Gi='Gimmedin:BAAANQADCgYIBgAAAA==.',
Gl='Glacious:BAAANQAECgIIAgAAAA==.Glizygobrice:BAAANQADCgIIAgAAAA==.',
Go='Gong:BAAANQADCgYJBgAAAA==.Goo:BAAANQADCgYIBgAAAA==.Goodbeer:BAABNQAECoEeAAIZAAcK6hkIXwAvAgAZAAcK6hkIXwAvAgAAAA==.Goodimppimp:BAAANQADCgUIBQAAAA==.Goodpizza:BAAANQADCgYIBgAAAA==.Gouraud:BAAANQAECgQICAAAAA==.',
Gr='Graeclaw:BAABNQAECoEYAAIOAAcKlxAHLACIAQAOAAcKlxAHLACIAQAAAA==.Grayson:BAABNQAECoEwAAMeAAkKaiO9AACxAwAeAAkKaiO9AACxAwACAAIKdBb9MABzAAAAAA==.Greenclaw:BAABNQAECoErAAIfAAkKexKGLwA/AgAfAAkKexKGLwA/AgAAAA==.Greengiant:BAAANQADCgYIBgAAAA==.Gregoryus:BAAANQADCgUIDwAAAA==.Grogg:BAAANQADCgMIBAAAAA==.Grosmortfif:BAAANQADCgYIBgABNQAECggIHQACABsbAA==.Gruber:BAAANQADCgcIBwABNQAECgkJNAAMAPQiAA==.',
Gu='Gultak:BAAANQAECgIJAwAAAA==.',
['Gô']='Gôósè:BAABNQAECoEfAAIOAAgKShK/IQDsAQAOAAgKShK/IQDsAQAAAA==.',
Ha='Hadron:BAABNQAECoEZAAMkAAcKURqVEAAXAgAkAAcKURqVEAAXAgAfAAEKoQCYugAPAAABNQAECggIGwASACcgAA==.Hairsweater:BAAANQAECgYIEQAAAA==.Hakirai:BAABNQAECoEZAAIZAAcKJhfRaQAUAgAZAAcKJhfRaQAUAgAAAA==.Halje:BAAANQAECgQIAwAAAA==.Halodin:BAAANQAECgMIBgAAAA==.Harambecast:BAAANQAECgQIBAABNQAECgcIDgAIAAAAAA==.Hastaqt:BAAANQAECgEIAQABNQAECgYICwAIAAAAAA==.Hazex:BAAANQADCgEIAQAAAA==.',
He='Heimdall:BAABNQAECoEdAAIJAAgKEBsiHQB6AgAJAAgKEBsiHQB6AgAAAA==.Hekus:BAEANQADCggICAABNQAECgkJHAADAA0VAA==.Helboy:BAAANQADCgUIBQAAAA==.Hermóðr:BAABNQAECoEXAAQlAAgKchtICQDDAQAlAAcKMxxICQDDAQANAAYKzQ8bIAA3AQAQAAIKLghtQAByAAABNQAECgkJLQAHAPYcAA==.Herrick:BAAANQADCgYICwAAAA==.Hexan:BAABNQAECoEZAAMbAAgK3x8vOABXAgAbAAcK4h4vOABXAgAYAAMKUwdI4wCTAAAAAA==.Hexun:BAAANQABCgIIAgAAAA==.',
Hi='Hibred:BAAANQAECgEIAQABNQAECgQICQAIAAAAAA==.Hirumaredx:BAABNQAECoEZAAIFAAcKfBtSBQA8AgAFAAcKfBtSBQA8AgAAAA==.',
Ho='Hobbsies:BAAANQAECgUJCgAAAA==.Hobie:BAAANQADCgIIAgAAAA==.Hobkins:BAABNQAECoEmAAIYAAkKdRyJJADUAgAYAAkKdRyJJADUAgAAAA==.Holcon:BAAANQAECgQICgAAAA==.Holiussy:BAAANQAECgUIBQABNQAECgkJPAAbAO0iAA==.Hollypops:BAAANQAECgcIEQAAAA==.Holybeau:BAABNQAECoEpAAIXAAkKKRxcHADtAgAXAAkKKRxcHADtAgAAAA==.Holybo:BAAANQADCggIBwABNQAFFAIIAwAIAAAAAQ==.Holyboh:BAAANQADCgYIBgAAAA==.Holyhex:BAAANQABCgQIBQAAAA==.Holywars:BAAANQAECgUIBQAAAA==.Holywdundead:BAAANQAECgMIBgAAAA==.',
Hu='Hula:BAAANQAECgMIAwAAAA==.',
Hy='Hypercat:BAABNQAECoEXAAIHAAgKMBt6fQBrAgAHAAgKMBt6fQBrAgAAAA==.Hyriel:BAAANQAECgMIBQAAAA==.',
['Hú']='Húnts:BAAANQAECgQJCAAAAA==.',
Ia='Iambbq:BAABNQAECoEnAAMHAAkK8ByOXQCxAgAHAAkKqRmOXQCxAgATAAIKkx6OIwCwAAAAAA==.',
Ib='Ibuprofen:BAAANQAECgIIAwAAAA==.',
Ic='Iceblades:BAAANQADCgMIAwAAAA==.Icyclo:BAAANQADCgYICgAAAA==.',
Id='Idioterroors:BAAANQAECgEIAQAAAA==.',
Ig='Igraine:BAAANQAECgUIDwAAAA==.',
Il='Illidarios:BAAANQAECgMIBAABNQAECgQIBwAIAAAAAA==.Illinax:BAAANQAECgYIBgAAAA==.Ilostmybible:BAAANQAECgQICAAAAA==.',
Im='Imakeupuddin:BAABNQAECoEkAAIUAAkKJiT8EwBiAwAUAAkKJiT8EwBiAwAAAA==.',
In='Indydevteam:BAAANQAECgUICgAAAA==.Inffected:BAAANQAECgUJBQAAAA==.Inflames:BAAANQAECgUICgABNQABCgEIAQAIAAAAAA==.Inglëwood:BAAANQADCgYIFAAAAA==.',
Is='Isasabotage:BAAANQAECgIJBAAAAA==.Isult:BAAANQAECgQIBwAAAA==.',
Iv='Iv:BAAANQAECgcIEQAAAA==.',
Ix='Ixthyr:BAABNQAECoEfAAIUAAkKsSCdJgAPAwAUAAkKsSCdJgAPAwABNQAFFAUICAAJACkWAA==.',
Ja='Jackd:BAAANQADCgUIBQAAAA==.Jaenaa:BAAANQAECgYIDQAAAA==.Jahrobi:BAABNQAECoErAAICAAkKByUgAQC9AwACAAkKByUgAQC9AwAAAA==.Jakqua:BAAANQABCgIIAgABNQAECgkJHQAJAEwTAA==.Jaselyn:BAABNQAECoEeAAMbAAkKiiF+CQBhAwAbAAkKiiF+CQBhAwAYAAUKcw7mpgAXAQAAAA==.Jaskryt:BAAANQAECgUIBwABNQAECgkJHwAgAJcNAA==.Jaslyn:BAAANQADCgMIBQAAAA==.Jaxin:BAAANQADCgIIAgAAAA==.Jaxsen:BAAANQADCggIFAAAAA==.',
Je='Jelibean:BAAANQADCggICAAAAA==.Jenofeve:BAAANQAECgIIAgAAAA==.Jensei:BAABNQAECoEfAAISAAkKvBc2CwA9AgASAAkKvBc2CwA9AgAAAA==.',
Jh='Jheina:BAABNQAECoEpAAINAAgKdQicGQCRAQANAAgKdQicGQCRAQAAAA==.Jheirazlynn:BAAANQABCggIBgABNQAECggIKQANAHUIAA==.',
Ji='Jimmyvrr:BAABNQAECoEZAAMiAAgKiQMZRgD2AAAZAAYKvQPo6wD5AAAiAAgKLQIZRgD2AAAAAA==.Jinnô:BAABNQAECoEsAAIcAAkKayBdBQAyAwAcAAkKayBdBQAyAwAAAA==.Jizzelda:BAAANQADCgcIEAAAAA==.',
Jo='Joqi:BAAANQADCggIBwAAAA==.Jorazak:BAAANQADCgcIDgAAAA==.',
Ju='Jubzie:BAAANQAECgQIDQAAAA==.Jubzug:BAABNQAECoElAAIUAAkKkSCTGQBGAwAUAAkKkSCTGQBGAwAAAA==.Judgment:BAAANQAECggICQAAAA==.Justwin:BAABNQAECoEbAAQEAAkKXCNtFwACAwAEAAgK5iBtFwACAwAFAAUK5yF8BwDmAQAGAAEKVg4WcQAtAAAAAA==.',
['Jå']='Jåckx:BAAANQADCgUICQAAAA==.',
Ka='Kaarnu:BAABNQAECoEcAAIbAAcKnRuySQAQAgAbAAcKnRuySQAQAgAAAA==.Kageman:BAAANQAECgUIEAAAAA==.Kainese:BAAANQADCgEIAQAAAA==.Kakon:BAABNQAECoEWAAIZAAcKmhGKggDXAQAZAAcKmhGKggDXAQAAAA==.Kamikrazi:BAAANQADCgEIAQAAAA==.Kapuna:BAAANQAECgUICQAAAA==.Karaglaz:BAAANQAECgcIEwAAAA==.Karalea:BAABNQAECoEnAAMHAAkKyyDqNQAQAwAHAAkKCyDqNQAQAwATAAEKGyXKMwBVAAAAAA==.Katalene:BAAANQADCgUIBgABNQAECggIHQAIAAAAAA==.Kayani:BAAANQAECgEIAQAAAA==.Kazaganthis:BAABNQAECoEWAAIeAAgK4RRlCQAaAgAeAAgK4RRlCQAaAgAAAA==.Kazstorius:BAABNQAECoEZAAMKAAcKsQeAcgAmAQAKAAcKFAeAcgAmAQALAAQKUgYJlQCUAAAAAA==.',
Ke='Kellbell:BAAANQAECgQIBwAAAA==.Kertug:BAABNQAECoEXAAMeAAcKLwo9GgDcAAAUAAcKRgixtQBnAQAeAAUKnwg9GgDcAAAAAA==.Keturonium:BAAANQAECgYIEAAAAA==.Kevdk:BAAANQAECgYICwAAAA==.',
Kh='Khary:BAAANQABCgYIBAAAAA==.Kharzaette:BAABNQAECoEqAAMHAAkKghQclgA3AgAHAAgK7BQclgA3AgATAAEKLxGwOgBAAAAAAA==.Khristo:BAABNQAECoEiAAMPAAkKsCB/BwASAwAPAAkKsCB/BwASAwAXAAEK2QxIAAFAAAAAAA==.',
Ki='Kiing:BAABNQAECoElAAMXAAgKfiKZFQAXAwAXAAgKfiKZFQAXAwADAAgKWSACOgDFAgAAAA==.Kikwi:BAAANQAECgMIBgAAAA==.Kioshi:BAABNQAECoEhAAIXAAgKHAzFjgBHAQAXAAgKHAzFjgBHAQAAAA==.Kirayamató:BAABNQAECoEeAAIhAAgKrxrMDgB7AgAhAAgKrxrMDgB7AgAAAA==.Kitmeup:BAAANQADCgEIAgAAAA==.Kiyofu:BAABNQAECoEaAAIBAAYKaw5jngBrAQABAAYKaw5jngBrAQAAAA==.',
Kn='Knew:BAAANQAECggICwABNQAFFAEIAQAIAAAAAA==.Knotagan:BAAANQAECgQICgAAAA==.',
Ko='Kobebryant:BAAANQAECgcIDQAAAA==.Koriol:BAAANQAECgQICAAAAA==.Korkron:BAABNQAECoE8AAMbAAkK7SLTCQBfAwAbAAkK7SLTCQBfAwAYAAIKxBBL6wB9AAAAAA==.Korrin:BAAANQAECgUIBQABNQABCgEIAQAIAAAAAA==.Kovian:BAAANQADCgIIAgAAAA==.Kozmikboom:BAAANQAECgIIAwAAAA==.',
Kr='Krackster:BAAANQADCgMJAwABNQADCgQIBAAIAAAAAA==.Krakow:BAAANQABCgYICAAAAA==.Krezan:BAAANQADCgcIFAAAAA==.Krix:BAAANQAECgcIEgABNQADCgYJBgAIAAAAAA==.Krolo:BAAANQADCgYIDAABNQAECggIHQAbALYWAA==.',
Ku='Kutkala:BAAANQADCgEIAQAAAA==.',
Ky='Kyndrine:BAAANQADCgMIAwABNQAECgIIAgAIAAAAAA==.Kyrja:BAABNQAECoEYAAIJAAgKqxCgNADMAQAJAAgKqxCgNADMAQAAAA==.Kyrst:BAAANQADCgEIAQAAAA==.Kytti:BAAANQAECgUICwAAAA==.',
La='Laani:BAAANQADCgcIBwABNQAECggIJAALAL8ZAA==.Ladorin:BAAANQAECgYIBgAAAA==.Lahallia:BAABNQAECoEqAAIEAAgKch1dJwCvAgAEAAgKch1dJwCvAgAAAA==.Laiellarien:BAAANQAECgUIBQABNQAECggIHQAIAAAAAA==.Lamarqt:BAAANQADCggICAAAAA==.Landrea:BAAANQADCggIAgAAAA==.Lany:BAAANQADCgEIAQAAAA==.Laran:BAABNQAECoEXAAIKAAgKSxFWTgCyAQAKAAgKSxFWTgCyAQAAAA==.Laupouette:BAAANQAECgcIEQABNQAFFAUIDAAQAA8TAA==.Laurissandra:BAAANQAECgQICAAAAA==.Lavalley:BAAANQAECgYIBgAAAA==.Lazypanda:BAAANQADCggIEgAAAA==.',
Le='Lerzian:BAAANQAECgEIAQABNQAECggIGgALABccAA==.Lexicage:BAAANQAECgUIEgAAAA==.',
Li='Lidd:BAABNQAECoEXAAMZAAYKEhtghwDMAQAZAAYKhBpghwDMAQAiAAUKWg1FRQD8AAAAAA==.Lightiuz:BAABNQAECoEhAAMXAAYKxRrkXwDUAQAXAAYKxRrkXwDUAQADAAEKTwu4fgEvAAAAAA==.Lightless:BAAANQABCgYIBgAAAA==.Lightmeat:BAAANQABCggICgAAAA==.Lightric:BAAANQADCgcIBwAAAA==.Lightstorme:BAAANQABCggIEgABNQAECgQIBAAIAAAAAA==.Lilshadoww:BAAANQAECgUIAgAAAA==.Livandletdie:BAAANQAECgQICQAAAA==.Lividchaos:BAAANQABCgMIAwAAAA==.Livyane:BAAANQADCgYIBQAAAA==.',
Ll='Llalow:BAAANQADCggICAAAAA==.Llalowdh:BAABNQAECoElAAMWAAgK9iH8DAAFAwAWAAgK9iH8DAAFAwAmAAIKkAulJQBYAAAAAA==.',
Lo='Lockewynn:BAABNQAECoEgAAIjAAkKhRlBBAC4AgAjAAkKhRlBBAC4AgAAAA==.Lockjawsh:BAABNQAECoEqAAMBAAkK/x07NgCXAgABAAgKNx47NgCXAgAgAAYKZRc1GACiAQAAAA==.Lokuma:BAABNQAECoEZAAQFAAgKlx8rCADPAQAEAAcKlRy6SAAlAgAFAAUKzSArCADPAQAGAAIKbBKtVQCEAAAAAA==.Lorelae:BAAANQAECgEIAQAAAA==.Lorre:BAAANQADCgQIBgAAAA==.Lot:BAAANQADCggICAAAAA==.Louni:BAABNQAECoEtAAIGAAkKtCO+BAB+AwAGAAkKtCO+BAB+AwAAAA==.Louu:BAAANQADCgYIBgABNQAECgYICAAIAAAAAA==.',
Lu='Ludo:BAAANQADCgUIDAAAAA==.Lunch:BAAANQADCgQIBAAAAA==.Lunchbreak:BAABNQAECoEsAAIWAAkKkSJqBACHAwAWAAkKkSJqBACHAwAAAA==.Lunchpunch:BAAANQAECgYICgABNQAECgkJLAAWAJEiAA==.Lunchtime:BAAANQAECgYICwABNQAECgkJLAAWAJEiAA==.Luot:BAAANQAECgEIAQAAAA==.',
Ma='Machine:BAAANQADCgcICwABNQAECgUIDwAIAAAAAA==.Magias:BAAANQADCgYIEAAAAA==.Maglea:BAAANQAECgEIAQAAAA==.Majexs:BAABNQAECoEwAAIDAAkKECP1EwBlAwADAAkKECP1EwBlAwAAAA==.Malady:BAAANQAECgQIBQAAAA==.Malfûrion:BAAANQABCgMJAwAAAA==.Malignancy:BAABNQAECoEeAAIBAAkKgRwnMgClAgABAAkKgRwnMgClAgAAAA==.Manalhau:BAAANQAECgUIDgABNQAECgcICwAIAAAAAA==.Mandragoran:BAABNQAECoEvAAQUAAkKRBpkTQCHAgAUAAkK9xlkTQCHAgACAAcKkxP0FwB/AQAeAAEKiAFkNQAUAAAAAA==.Manohar:BAAANQAECgIIAgAAAA==.Manuster:BAAANQAECgUICwAAAA==.Maradön:BAABNQAECoEqAAILAAgKgh7EHgCjAgALAAgKgh7EHgCjAgAAAA==.Margarida:BAAANQAECgcIDwAAAA==.Margaru:BAAANQADCgQIBgAAAA==.Maruknar:BAAANQAECgEIAQAAAA==.Mavd:BAAANQAECgUIEwAAAA==.Mavele:BAAANQAECgYICgAAAA==.Mavex:BAAANQAECgcIDQABNQAFFAYIEwAgAKUUAA==.Maximmus:BAABNQAECoEfAAIaAAkKMSB2BABEAwAaAAkKMSB2BABEAwAAAA==.Mayæl:BAAANQADCgcIEQAAAA==.Mazerrackham:BAABNQAECoEcAAIHAAgKsBP7oAAgAgAHAAgKsBP7oAAgAgAAAA==.',
Mb='Mbappé:BAAANQADCgEIAQAAAA==.',
Me='Meesooholyy:BAAANQAECgYICAAAAA==.Meespresso:BAAANQAECgIIAgAAAA==.Meina:BAAANQAECgIIBAAAAA==.Mellow:BAAANQADCgcIBwABNQAECgcIHQALADEaAA==.Melynia:BAAANQAECgIJBAAAAA==.Mephala:BAABNQAECoEXAAIZAAcKNCSRKADWAgAZAAcKNCSRKADWAgAAAA==.Metapig:BAAANQAECgcIDQAAAA==.Mezasu:BAAANQAECgcJDAAAAA==.',
Mi='Michaelj:BAAANQAECgQIBAAAAA==.Mikedawson:BAABNQAECoEkAAInAAkKnh6OAQAeAwAnAAkKnh6OAQAeAwAAAA==.Mikya:BAABNQAECoEfAAIoAAgKRRT5AQAyAgAoAAgKRRT5AQAyAgAAAA==.Milkot:BAAANQAECggIBwAAAA==.Milkys:BAAANQAECggIEgAAAA==.Mistian:BAAANQAECgcIEQAAAA==.Mistpet:BAAANQADCgUIBQABNQAECgkJJwAfAJUgAA==.Mistrbfkx:BAABNQAECoEjAAQXAAkKhRDTRgAsAgAXAAkKhRDTRgAsAgADAAcKSxF8qACWAQAPAAEKtxYPaAAoAAAAAA==.Mitsukuni:BAAANQADCgEIAQAAAA==.',
Mo='Moai:BAAANQADCgEIAQAAAA==.Moderñdruið:BAABNQAECoEsAAIOAAgKtiH1CQANAwAOAAgKtiH1CQANAwAAAA==.Mojodjin:BAAANQAECgcICgAAAA==.Molewithwing:BAAANQAECgMIAwAAAA==.Molocko:BAAANQAECgQIBAAAAA==.Monkahkiin:BAAANQAECgEIAQAAAA==.Moomoomo:BAABNQAECoEzAAMZAAkKTiUyCACNAwAZAAgKYiYyCACNAwAiAAYKbxO4NQB0AQAAAA==.Moonlyt:BAAANQADCgQIBAAAAA==.Moonrstrudel:BAABNQAECoErAAIMAAkK1B6FBAAgAwAMAAkK1B6FBAAgAwAAAA==.Moonsaka:BAAANQAECgQICAAAAA==.Mooseboi:BAABNQAECoEdAAMCAAgKGxsAEgDYAQAUAAgKbxDHhADrAQACAAUKmSAAEgDYAQAAAA==.Moothy:BAAANQAECgQICAAAAA==.Morang:BAABNQAECoEcAAIkAAgKlRHPFwCuAQAkAAgKlRHPFwCuAQAAAA==.Morechaos:BAAANQAECgUIBwAAAA==.Mossbeard:BAAANQAECgIJAgAAAA==.Mossdormu:BAAANQADCgUJBwAAAA==.',
Mu='Mujeae:BAAANQAECgQIBQAAAA==.Munitions:BAAANQADCggIDwAAAA==.Murricah:BAABNQAECoEmAAILAAgK+hoyKABkAgALAAgK+hoyKABkAgAAAA==.Musique:BAAANQAECgQIBwAAAA==.',
My='Myrical:BAAANQADCgYIDAAAAA==.Myricism:BAAANQADCgUICwABNQADCgYIDAAIAAAAAA==.Myrihwana:BAABNQAECoEnAAIVAAkKUBKiJwA3AgAVAAkKUBKiJwA3AgAAAA==.Mythorne:BAAANQABCgYICAAAAA==.',
['Må']='Mångling:BAAANQADCgMIAwAAAA==.',
['Mê']='Mêzcal:BAAANQAECgQICQAAAA==.',
['Më']='Mërrick:BAAANQADCggICgAAAA==.',
Na='Nahp:BAAANQAECgEIAQAAAA==.Nahtinde:BAABNQAECoEWAAMpAAgK8RMGKwAKAgApAAgK8RMGKwAKAgAhAAMK2wFnQwBsAAAAAA==.Naterade:BAACNQAFFIEMAAQKAAUKiAnYDAARAQAKAAQKkQnYDAARAQAJAAIKlgE1FABqAAALAAEKYwmmMQAkAAA1AAQKgRoAAwoACQp1FxMvAFECAAoACQp1FxMvAFECAAkAAgooDnN/AGgAAAAA.Nazrull:BAABNQAECoEaAAILAAgKFxyPIgCIAgALAAgKFxyPIgCIAgAAAA==.',
Ne='Necrofrost:BAAANQAECgEIAQAAAA==.Neobovine:BAAANQAECgQIBQAAAA==.Neoordained:BAAANQAECgUICgAAAA==.Nesowras:BAAANQADCgYIDAABNQAECggIHQAEACYbAA==.Nexlaht:BAABNQAECoEeAAMbAAkKmyIMDABLAwAbAAkKmyIMDABLAwAYAAEK+w8qDQE8AAAAAA==.',
Ni='Nicodemuss:BAAANQAECgMIAwAAAA==.Nightflare:BAABNQAECoEaAAIWAAcKaAtVMgCLAQAWAAcKaAtVMgCLAQAAAA==.Nim:BAAANQADCgcICAABNQAECgkJJQAHAJkdAA==.',
No='Nodad:BAAANQAECgEIAQAAAA==.Nodramah:BAAANQAECggIAwAAAA==.Noeyescono:BAAANQAECgIIAgABNQAECgYICAAIAAAAAA==.Nokzanoh:BAAANQAECgcIDgAAAA==.Noraz:BAABNQAECoE0AAIMAAkK9CI5AgCFAwAMAAkK9CI5AgCFAwAAAA==.Normalsaline:BAAANQAECgMIAwAAAA==.Nosirrage:BAABNQAECoEYAAIUAAgKtx7pRwCZAgAUAAgKtx7pRwCZAgABNQAFFAMIBwAVAN8UAA==.Noxoff:BAACNQAFFIEIAAMJAAUKKRY6CQAGAQAJAAMKSho6CQAGAQALAAIK+A/6HwBrAAA1AAQKgSUABAkACQpNIY8TANACAAkACQrNH48TANACAAoACApyHWY8AAkCAAsAAQqUGeOxAEYAAAAA.',
Nu='Nullah:BAAANQADCgUIBQABNQAECgQIBQAIAAAAAA==.Nullan:BAAANQAECgQIBQAAAA==.Nullash:BAAANQADCgYIBgABNQAECgQIBQAIAAAAAA==.Numb:BAAANQADCgUIBQABNQAECgkJJQAHAJkdAA==.Nurarihyon:BAAANQAECgEIAQAAAA==.Nuriel:BAAANQADCgcIBwAAAA==.',
['Nè']='Nèphelle:BAABNQAECoEyAAQEAAkK0iCaGwDsAgAEAAkK0iCaGwDsAgAFAAIK3hReGgB5AAAGAAIKXQQGZwBAAAAAAA==.',
['Në']='Nëmèsÿs:BAAANQAECgMIAwAAAA==.',
Oa='Oakendale:BAABNQAECoEhAAMbAAkKZiSxBACUAwAbAAkKZiSxBACUAwAYAAMKcw9F6wB9AAAAAA==.Oaklei:BAAANQAECgQIBAAAAA==.Oakrageous:BAAANQAECgQICgAAAA==.',
Ob='Obiione:BAAANQAECgQICQAAAA==.Obionekenobi:BAAANQAECgIIAgAAAA==.',
Od='Oddball:BAAANQADCgcIBwAAAA==.Odinsson:BAAANQADCgUICAAAAA==.',
Ol='Olrun:BAAANQAECgQICgAAAQ==.',
Or='Ordin:BAAANQADCgcIBwAAAA==.Orinek:BAABNQAECoEYAAMOAAkKYR2ZCwD2AgAOAAkKYR2ZCwD2AgAMAAEKtgcqNgA2AAAAAA==.Ororomunroe:BAAANQABCgQJBAAAAA==.Oruda:BAAANQADCgYIDwAAAA==.Orynnh:BAAANQADCgcIDgAAAA==.',
Os='Osogrande:BAABNQAECoEbAAQnAAgK4BR+CgCjAQAnAAYKEhZ+CgCjAQABAAUKgw2PugApAQAgAAEK2QbJbwA5AAAAAA==.Osso:BAAANQAECgMIAwABNQAECgUICAAIAAAAAA==.',
Ow='Oway:BAAANQAECgUIBgAAAA==.Owy:BAAANQADCgcIDQAAAA==.',
Pa='Paean:BAAANQAECgQIBAAAAA==.Palajinn:BAACNQAFFIEFAAIXAAIKAxX2GQCaAAAXAAIKAxX2GQCaAAA1AAQKgSsAAxcACQpGHXQWABEDABcACQpGHXQWABEDAAMAAwqGCP09AXkAAAAA.Pandaspanda:BAAANQAECgUJBQAAAA==.Parousia:BAAANQADCgQIBAABNQAECgUIDwAIAAAAAA==.Passacaglia:BAAANQAFFAIIAwAAAQ==.Patryck:BAABNQAECoEeAAMYAAkKvBnBKQC3AgAYAAkKvBnBKQC3AgAbAAEKcATJBwEtAAAAAA==.Payotee:BAAANQAECgUICQAAAA==.',
Pc='Pcokalypse:BAABNQAECoEfAAMHAAgKdg2dwgDbAQAHAAgKewydwgDbAQATAAMKFArdJwCQAAAAAA==.',
Pe='Peilli:BAAANQADCgcIDQAAAA==.Penderrin:BAAANQADCggIDwABNQAECgkJLgALAE4hAA==.Penemuel:BAAANQAECgYIEgAAAA==.Pepperfrost:BAAANQABCgIIAwAAAA==.Perkys:BAAANQABCgEIAQAAAA==.Perrinaybara:BAABNQAECoEtAAMRAAkKrB9JDAD7AgARAAkKrB9JDAD7AgASAAMK6xQJIAC9AAABNQAFFAIIBAATAK0LAA==.Petesteele:BAABNQAECoEZAAIGAAcKvg1XLwCAAQAGAAcKvg1XLwCAAQAAAA==.Petruccio:BAAANQAECgUIEAAAAA==.',
Ph='Phaet:BAABNQAECoEbAAIfAAgKJhftMAA1AgAfAAgKJhftMAA1AgAAAA==.Phob:BAABNQAECoEdAAIEAAgKJhuePABTAgAEAAgKJhuePABTAgAAAA==.Phoreal:BAABNQAECoEbAAIEAAcKwCWqGAD8AgAEAAcKwCWqGAD8AgAAAA==.Phuryberryz:BAAANQAECgYIBgAAAA==.Phuryblight:BAAANQADCgYIDgAAAA==.Phurystorm:BAAANQAECgQICgAAAA==.Phurysung:BAAANQADCgUIBQAAAA==.',
Pi='Pikasloot:BAABNQAECoEoAAMHAAgK8RkRdwB5AgAHAAgK8RkRdwB5AgATAAEK1wmKRQAsAAAAAA==.Pinechi:BAAANQADCgYIBgAAAA==.Pinestorm:BAAANQADCgEIAQABNQAECggIHQADAHoPAA==.Pinestraw:BAABNQAECoEdAAMDAAgKeg8ckQDOAQADAAgKeg8ckQDOAQAXAAYK+wzHiwBPAQAAAA==.Pinewilt:BAAANQADCgUIBQAAAA==.Pinksy:BAABNQAECoEZAAIWAAgKpBosGgBsAgAWAAgKpBosGgBsAgAAAA==.Pipfanie:BAAANQADCgcIIAAAAA==.Pixelphobia:BAAANQAECgYIBgABNQAECgkJIgAcACMbAA==.',
Pl='Plaid:BAABNQAECoEbAAIYAAkK5xnjKgCwAgAYAAkK5xnjKgCwAgAAAA==.',
Pn='Pnakotus:BAABNQAECoEbAAIZAAcKyRWWewDoAQAZAAcKyRWWewDoAQAAAA==.',
Po='Pokeey:BAAANQAECgIIBAAAAA==.Powskii:BAAANQAECgYJDgAAAA==.',
Pp='Ppsmash:BAABNQAFFIENAAISAAQKjxROBAAnAQASAAQKjxROBAAnAQAAAA==.',
Pr='Priestofcake:BAAANQAECggICAAAAA==.Prishe:BAAANQAECgEIAQAAAA==.Profits:BAAANQAECgYIDwAAAA==.Pronouns:BAAANQAECgcIEgAAAA==.Protege:BAABNQAECoEZAAILAAcKcBEIUgCLAQALAAcKcBEIUgCLAQAAAA==.',
Ps='Psy:BAAANQAECgQICgAAAA==.Psybient:BAAANQAECgUIDQAAAA==.',
Pu='Purina:BAAANQADCgMIAwAAAA==.',
Pv='Pvp:BAAANQADCgUIDAAAAA==.',
Py='Pyraxion:BAAANQADCggICAAAAA==.',
['Pã']='Pãoduro:BAAANQADCgYIBwABNQAECgcICwAIAAAAAA==.',
['Pé']='Pérkis:BAAANQADCgcIBwAAAA==.',
Qu='Quacklord:BAAANQADCgQIBgAAAA==.',
['Qî']='Qîîz:BAABNQAECoEiAAMKAAkKyhTYPAAHAgAKAAkKyhTYPAAHAgALAAEK4BHfvAAwAAAAAA==.',
Ra='Racklock:BAAANQADCgYIBgABNQAECggIHAAHALATAA==.Rakgul:BAAANQABCgQIBAAAAA==.Rambojohny:BAAANQAECggIEQABNQAFFAQICwAHABoTAA==.Rampagé:BAAANQADCgQICQAAAA==.Ramzï:BAABNQAECoEdAAMJAAgKdiRzDAAbAwAJAAgKdiRzDAAbAwAKAAcKmx/DPgD+AQAAAA==.Randompriest:BAABNQAECoEfAAIEAAkKWBSsTAAWAgAEAAkKWBSsTAAWAgAAAA==.Rangetomato:BAAANQAECgUIBQABNQAFFAQICAADAPkLAA==.Rathernot:BAABNQAECoEdAAMQAAgKdwwHJQB1AQAQAAcK/wwHJQB1AQAlAAIKQwOaHABVAAAAAA==.Ravenbella:BAAANQAECgUICgAAAA==.Ravex:BAAANQADCgcIBwABNQAFFAYIEwAgAKUUAA==.Ravodin:BAAANQAECgcIDQABNQAFFAYIEwAgAKUUAA==.Ravoks:BAACNQAFFIETAAQgAAYKpRQ8BgC7AAABAAQKxw8XEgA8AQAgAAIKVh08BgC7AAAnAAIKkBOZAwChAAA1AAQKgSoABAEACQqcI54hAOYCAAEACAqEIp4hAOYCACAABAocICMeAHUBACcAAwrlHyITAO0AAAAA.Razalla:BAAANQAECgQICgAAAA==.Razatre:BAAANQADCgYICwAAAA==.Razeill:BAAANQAECgEJAQAAAA==.Razellia:BAAANQADCgUICQAAAA==.',
Re='Redcyclone:BAAANQAECgYIBgAAAA==.Redfiend:BAAANQAECgUICAAAAA==.Redhawt:BAAANQAECgIIAgABNQAECgQIBAAIAAAAAA==.Reika:BAABNQAECoEXAAMTAAcKoxj3CwDHAQATAAcKoxj3CwDHAQAHAAUKNwmtTAHsAAAAAA==.Requlier:BAAANQAECggIDAAAAA==.Rev:BAAANQAECgUIBQAAAA==.Revelationzz:BAABNQAECoEuAAMhAAkKyhgNDwB4AgAhAAgKWxkNDwB4AgApAAMK7hFbaAC/AAAAAA==.Rexkong:BAABNQAECoElAAIZAAgKHgyIeQDtAQAZAAgKHgyIeQDtAQAAAA==.Reyus:BAAANQAECgUIBQABNQAECggIHAAYAM0fAA==.Rezc:BAAANQAECgMIAwAAAA==.',
Rg='Rghtcousbtch:BAAANQAECgQICAAAAA==.',
Ri='Riblets:BAAANQADCgUIBQAAAA==.Riki:BAAANQADCggIEgAAAA==.Ripetomato:BAACNQAFFIEIAAIDAAQK+QuFDgAnAQADAAQK+QuFDgAnAQA1AAQKgTQAAwMACQq+IbQdADYDAAMACQq+IbQdADYDABcAAQoWF8H9AEUAAAAA.Ritualist:BAAANQADCgEJAQAAAA==.',
Ro='Rockzeeheart:BAAANQAECgUIDwAAAA==.',
Rt='Rtcmouse:BAABNQAECoEeAAIPAAgK4gkJLABRAQAPAAgK4gkJLABRAQAAAA==.',
Ru='Rukeshno:BAAANQAECgQICAAAAA==.Rumblemuffin:BAAANQAECggJCAAAAA==.',
Ry='Rylo:BAAANQADCgIIAgAAAA==.',
['Ró']='Róckmybubble:BAABNQAECoEcAAIDAAgKEQlnuAB0AQADAAgKEQlnuAB0AQAAAA==.',
Sa='Sacerdos:BAAANQAECgUIDgAAAA==.Sacredhammer:BAAANQAECggIAQAAAA==.Saijin:BAAANQAECgYIEgAAAA==.Salvatorre:BAAANQADCgQIBAAAAA==.Salysra:BAAANQAECgQIBwAAAA==.Samstein:BAABNQAECoEaAAMpAAYKZBTQZADPAAAhAAMK6RNdOADRAAApAAMK3hTQZADPAAAAAA==.Sanare:BAAANQAECgIIBAAAAA==.Sanchey:BAABNQAECoEgAAIGAAkK8hvAEADSAgAGAAkK8hvAEADSAgAAAA==.Sandalath:BAAANQABCgQJAgAAAA==.Sandara:BAAANQADCggIHwAAAA==.Sangrenard:BAAANQADCgYIBwABNQAECggIHQAIAAAAAA==.Sapz:BAABNQAECoEcAAMpAAkKDCD/CQAlAwApAAkK5B//CQAlAwAhAAQKNx8XLABGAQAAAA==.Sarbrak:BAAANQAECgEIAQAAAA==.Sarka:BAAANQAECgQICQAAAA==.Sarrh:BAAANQADCgUIBQAAAA==.Saryndra:BAAANQADCgQIBAABNQAECgcIDgAIAAAAAA==.Satet:BAAANQAECgQICAAAAA==.Satrenservis:BAAANQADCggIDwABNQAECggIJAALAL8ZAA==.Savatree:BAAANQADCggIFAAAAA==.Savvyshammy:BAAANQADCgYICwAAAA==.Savïtar:BAABNQAECoEaAAQiAAYKpxs4UwCxAAAZAAQKFxs3ygA5AQAiAAMKMRU4UwCxAAAdAAEKKCJCDwBeAAAAAA==.',
Sc='Scarleriss:BAAANQADCgQIBwAAAA==.Scolt:BAAANQAECgUICgAAAA==.Scrandle:BAAANQAECgYIEAAAAA==.Scythíx:BAAANQAECggICwABNQAECgkJKQAXACkcAA==.',
Se='Sebile:BAABNQAECoEqAAIlAAgKPwwECwCMAQAlAAgKPwwECwCMAQAAAA==.Selirri:BAAANQADCgUIBQAAAA==.Semishift:BAABNQAECoEcAAMMAAgK2h6KCQB5AgAMAAcKuB2KCQB5AgAOAAgKBRuJFwBeAgAAAA==.Sephroth:BAABNQAECoEeAAIDAAcK3Q71swB+AQADAAcK3Q71swB+AQAAAA==.Seydin:BAABNQAECoEaAAIPAAYKvxbiJgB6AQAPAAYKvxbiJgB6AQAAAA==.Señorbear:BAAANQAECgEIAQAAAA==.',
Sh='Shaboink:BAAANQAECgcIDgAAAA==.Shabutie:BAABNQAECoErAAMhAAkK2BdaGAAIAgAhAAcKUBdaGAAIAgApAAYKaBZAQACHAQAAAA==.Shadhahvar:BAAANQABCgcICwAAAA==.Shadowutf:BAAANQADCgYIBwAAAA==.Shadyboot:BAAANQAECgUIBQABNQAECgkJKAAbAOohAA==.Shaienne:BAABNQAECoEaAAIiAAgKBBZSIAAuAgAiAAgKBBZSIAAuAgAAAA==.Shamtan:BAAANQADCggIFAAAAA==.Shayná:BAABNQAECoEeAAIZAAgKhSCIJADnAgAZAAgKhSCIJADnAgAAAA==.Shayse:BAAANQAECgMIAwAAAA==.Shigar:BAAANQADCggICAAAAA==.Shigâr:BAAANQADCgYICgAAAA==.Shinedown:BAAANQADCgcIBQABNQAECgUIDwAIAAAAAA==.Shingaling:BAAANQAECgUIBgAAAA==.Shinzovoker:BAABNQAECoEgAAIQAAkK0xp6DADMAgAQAAkK0xp6DADMAgAAAA==.Shockcore:BAAANQAECgEIAQAAAA==.Shoshlihauni:BAAANQAECgEIAQAAAA==.Shotz:BAAANQAECgIIAwABNQAECgkJHAApAAwgAA==.',
Si='Sidioüs:BAABNQAECoEoAAIbAAkK6iHBDgA4AwAbAAkK6iHBDgA4AwAAAA==.Silverlight:BAAANQAECgEIAQABNQAECgYICgAIAAAAAA==.Silvermann:BAAANQADCgUIBwAAAA==.Silvermoonto:BAAANQAECgQIBQAAAA==.Silvia:BAAANQAECgIIBAABNQAECgkJIwALAKUhAA==.Sinister:BAAANQAECgIIAgAAAA==.Sinnan:BAABNQAECoEUAAIKAAYKcx+DOAAeAgAKAAYKcx+DOAAeAgAAAA==.Sintaro:BAEANQAECgYIDQAAAA==.',
Sk='Skalina:BAAANQADCgcICAAAAA==.Skarejudge:BAAANQAECgQIBAABNQAECggIEwAIAAAAAA==.Skidattles:BAACNQAFFIEFAAIiAAIKlxFsFwCUAAAiAAIKlxFsFwCUAAA1AAQKgSMAAiIACQopGPoTAKsCACIACQopGPoTAKsCAAAA.Skullkandy:BAAANQAECgEIAQAAAA==.Skullordx:BAAANQADCgQIBAAAAA==.',
Sl='Sliverblood:BAAANQADCgYIBgAAAA==.',
Sm='Smeckledorfd:BAABNQAECoEcAAIfAAcKdRl3NwAIAgAfAAcKdRl3NwAIAgABNQAECggIEgAIAAAAAA==.',
Sn='Snelly:BAAANQAECgQIBAAAAA==.',
So='Sophie:BAAANQADCgQIBAAAAA==.Soulzero:BAAANQAECgUICwAAAA==.',
Sp='Spanksmoo:BAABNQAECoEjAAILAAgKviM9DQA2AwALAAgKviM9DQA2AwAAAA==.Spaxx:BAABNQAECoEgAAIUAAgKRQ6higDbAQAUAAgKRQ6higDbAQAAAA==.Spellstryke:BAAANQADCgYIDgAAAA==.Spinnaz:BAABNQAECoEZAAIPAAgKMxVUHgDKAQAPAAgKMxVUHgDKAQAAAA==.',
St='Stalizzy:BAAANQAECgEIAwAAAA==.Stalizzyx:BAAANQAECggIEQAAAA==.Stephani:BAAANQAECgYICAAAAA==.Stephia:BAACNQAFFIEQAAIiAAUK7RNiDQA7AQAiAAUK7RNiDQA7AQA1AAQKgT0AAyIACQpSJGADAJ0DACIACQpSJGADAJ0DABkABAoUF8nnAAEBAAAA.Stevejubz:BAAANQADCgIIAgAAAA==.Stonestout:BAAANQAECgQICgAAAA==.Storme:BAAANQAECgQIBAAAAA==.Styches:BAAANQADCgMIAwAAAA==.Stàple:BAAANQAECgYIDwAAAA==.',
Su='Suffrage:BAAANQAECgcIDgAAAA==.Suki:BAAANQADCggIGwABNQAECgcIGwAEAMAlAA==.Sulveris:BAABNQAECoEuAAIOAAkKbSPnBQBSAwAOAAkKbSPnBQBSAwAAAA==.Sunnyshaman:BAABNQAECoEYAAIbAAcKWBdSYgC4AQAbAAcKWBdSYgC4AQAAAA==.Sunstriker:BAAANQADCgQIBAAAAA==.Suzygreenbrg:BAAANQADCgMIAwAAAA==.',
Sw='Swolfzy:BAAANQAECgQIBQAAAA==.Swolfzzi:BAAANQAECgEIAQAAAA==.',
Sy='Syleane:BAAANQABCgYICgAAAA==.Syque:BAAANQADCgYIBgAAAA==.',
['Sä']='Sämael:BAAANQADCggJDgABNQAECgYIGgApAGQUAA==.',
['Së']='Sëråph:BAAANQADCgUIBwAAAA==.',
['Sì']='Sìnìster:BAABNQAECoEgAAIWAAkKzR7+DQD4AgAWAAkKzR7+DQD4AgAAAA==.',
Ta='Taakeshi:BAAANQAECgcICgAAAA==.Takumii:BAAANQADCggIDgAAAA==.Tamachi:BAAANQAECgMIBAAAAA==.Tanaxe:BAAANQAECgEIAQAAAA==.Tanelorñ:BAAANQAECgEIAQAAAA==.Tanksomes:BAABNQAECoEqAAILAAkK3h1IEwD8AgALAAkK3h1IEwD8AgAAAA==.Tareilaman:BAAANQADCgcIBwAAAA==.Tareilimage:BAAANQAECgUICQAAAA==.Tauntted:BAAANQAECgEIAQAAAA==.Taurenman:BAAANQAECgcIEgAAAA==.',
Te='Tecom:BAAANQAECgUIDwAAAA==.Teddiebolt:BAAANQAECgMIAwABNQAFFAIIBQABAJ0jAA==.Teddifer:BAACNQAFFIEFAAIBAAIKnSMZHwDQAAABAAIKnSMZHwDQAAA1AAQKgRgAAgEACQpOIHQaAAcDAAEACQpOIHQaAAcDAAAA.Temptus:BAABNQAECoElAAIfAAgKlxo3KQBrAgAfAAgKlxo3KQBrAgAAAA==.Terrenarde:BAAANQAECgQICAABNQAECggIHQAIAAAAAA==.',
Th='Thdrae:BAAANQAECggICAAAAA==.Thejondoepro:BAABNQAECoErAAIeAAkKvBcYBgCIAgAeAAkKvBcYBgCIAgAAAA==.Thesniperino:BAAANQAECgEIAQAAAA==.Thicklog:BAAANQAECgYIEwAAAA==.Thisylas:BAAANQABCgMIAwABNQAECgcIDgAIAAAAAA==.Thorrina:BAAANQABCgIIAQAAAA==.Thsbursysrur:BAABNQAECoEaAAIkAAYKAQwEKAAPAQAkAAYKAQwEKAAPAQAAAA==.Thulsadoom:BAAANQADCgQIBQAAAA==.Thunderswift:BAABNQAECoErAAIiAAkKJBgTGAB/AgAiAAkKJBgTGAB/AgAAAA==.Thæria:BAABNQAECoEeAAMVAAcKxQxGQwBwAQAVAAcK+ApGQwBwAQAmAAUKxQkwHADDAAAAAA==.',
Ti='Tia:BAABNQAECoEZAAIbAAgKURCGaQCgAQAbAAgKURCGaQCgAQAAAA==.Tiller:BAAANQADCgYIBgABNQAECgkJKQAYAEQiAA==.Tiltion:BAAANQAECgUIDwAAAA==.Tind:BAAANQAECgYIBwAAAA==.Tinggu:BAAANQAECgUIBwAAAA==.Tinitus:BAABNQAECoEYAAMaAAgKgRCbEgAcAgAaAAgKgRCbEgAcAgAYAAEKkASDIgEsAAAAAA==.Tish:BAAANQAECgIIAgAAAA==.Tizzona:BAACNQAFFIEPAAIRAAYKlyBaAgA7AgARAAYKlyBaAgA7AgA1AAQKgSwAAhEACQrZJeQCAKIDABEACQrZJeQCAKIDAAE1AAMKBwgHAAgAAAAA.',
Tl='Tlachtgae:BAAANQADCgIIAwAAAA==.',
To='Tobygodz:BAAANQAECgQIEQAAAA==.Tomatofest:BAAANQAECgUIDgAAAA==.Tomlong:BAAANQADCgQIBAAAAA==.Tookdk:BAABNQAECoEbAAILAAkKTB4gFgDmAgALAAkKTB4gFgDmAgAAAA==.Tookdrin:BAAANQAECgYIEQABNQAECgkJGwALAEweAA==.Tooksamdi:BAAANQADCgcIBwABNQAECgkJGwALAEweAA==.Toreto:BAAANQADCgMJAwAAAA==.Torvik:BAAANQADCgIIAgAAAA==.',
Tr='Treckken:BAABNQAECoEdAAIbAAgKthZrUAD3AQAbAAgKthZrUAD3AQAAAA==.Treemendous:BAAANQABCgIIAgAAAA==.Treepunch:BAAANQADCgYIDAAAAA==.Trystán:BAAANQADCgUICAAAAA==.',
Tu='Tuknar:BAABNQAECoEaAAQaAAgKxhfEGwBxAQAaAAQKrh7EGwBxAQAbAAUKHBjQfwBfAQAYAAIKBQyv9gBkAAAAAA==.Tulleren:BAAANQAECgEIAgAAAA==.',
Tv='Tvalin:BAAANQAECgYICgABNQAECgcIGAABABIbAA==.',
Ty='Tynan:BAABNQAECoEdAAQnAAgKPBQjBgAvAgAnAAgKPBQjBgAvAgAgAAIKxwuNWQBqAAABAAEK/QdWLgErAAAAAA==.Typhön:BAAANQAECgMIBAAAAA==.',
Tz='Tzezae:BAABNQAECoEZAAIkAAcKogzyIgA5AQAkAAcKogzyIgA5AQAAAA==.',
['Tï']='Tïlo:BAABNQAECoEeAAIDAAgKmRRIcQAeAgADAAgKmRRIcQAeAgAAAA==.',
Uc='Ucy:BAAANQAECgEIAQAAAA==.',
Ul='Ulfvaer:BAAANQADCgYIBgAAAA==.',
Um='Umbrafrost:BAAANQAECgUIDwAAAA==.',
Un='Unspeakable:BAAANQADCgUIBQAAAA==.Untot:BAABNQAECoElAAMPAAkKoiF7BABbAwAPAAkKoiF7BABbAwADAAIK4AFhnQEdAAAAAA==.',
Va='Vach:BAAANQAECgIIAgAAAA==.Vacui:BAAANQAECgUIBgAAAA==.Vaedoc:BAAANQADCgUIBQAAAA==.Valadhiel:BAAANQAECgUIBQAAAA==.Valezriel:BAABNQAECoEYAAIBAAcKEhuVUABDAgABAAcKEhuVUABDAgAAAA==.Valintine:BAAANQAECgUICQAAAA==.Vallence:BAABNQAECoEqAAIHAAgKXySvMgAZAwAHAAgKXySvMgAZAwAAAA==.Valorem:BAAANQADCgEJAQAAAA==.Valorie:BAAANQAFFAIIAwAAAA==.Valrev:BAAANQADCgcIBwAAAA==.Vassaro:BAAANQAECgcIDAAAAA==.',
Ve='Vermivora:BAAANQAECgIIBAAAAA==.Vettè:BAABNQAECoEfAAIXAAkKbhGcRQAxAgAXAAkKbhGcRQAxAgAAAA==.Vevoxypoo:BAAANQADCggIDwAAAA==.',
Vi='Vida:BAAANQAECgEIAQAAAA==.Villivia:BAABNQAECoEkAAILAAgKvxlYLQBEAgALAAgKvxlYLQBEAgAAAA==.Viracia:BAAANQAECggIBgAAAA==.Virtigo:BAAANQAECgQIBwAAAA==.Visari:BAAANQAECgQICgAAAA==.Vitole:BAAANQADCgEIAQABNQAECgcIGwAZAMkVAA==.',
Vo='Voidcollapse:BAAANQADCgUJBgAAAA==.Voidnut:BAAANQAECgIIAgAAAA==.Voss:BAAANQADCggICQAAAA==.',
['Vè']='Vèndetta:BAAANQAECgYICQAAAA==.',
['Vê']='Vêstïge:BAAANQAECgQICgAAAA==.',
Wa='Wareid:BAAANQADCgUIBgABNQAECgIIAgAIAAAAAA==.Waterfalls:BAAANQADCgYIBgAAAA==.Watermyrain:BAABNQAECoEqAAQBAAkKCCRNBQCbAwABAAkK+CNNBQCbAwAgAAMKpCQ8JQBAAQAnAAEKZQmpJwA/AAAAAA==.',
We='Weeble:BAAANQAECgEIAQAAAA==.Weebu:BAABNQAECoEdAAIYAAcKuRoBTgASAgAYAAcKuRoBTgASAgAAAA==.Wehaia:BAAANQADCgYIDAAAAA==.Welsley:BAABNQAECoEdAAIYAAgK1w5yYQDNAQAYAAgK1w5yYQDNAQAAAA==.',
Wh='Whispe:BAABNQAECoEfAAIkAAgKvwlmIABRAQAkAAgKvwlmIABRAQAAAA==.Whíte:BAAANQADCgQIBAAAAA==.',
Wi='Wicate:BAABNQAECoEcAAIDAAgK4Qj6rgCJAQADAAgK4Qj6rgCJAQAAAA==.Wildedge:BAAANQADCgYIFgAAAA==.Wilder:BAABNQAECoErAAIPAAkKohviDQCZAgAPAAkKohviDQCZAgAAAA==.Willendra:BAABNQAECoEpAAIfAAgKbR3NIACpAgAfAAgKbR3NIACpAgAAAA==.Wir:BAABNQAECoEnAAIDAAgKvCElNQDXAgADAAgKvCElNQDXAgAAAA==.',
Wo='Wolfery:BAABNQAECoEfAAISAAgKTgWzGAAzAQASAAgKTgWzGAAzAQAAAA==.Wolflust:BAAANQADCgUIBQAAAA==.Wolowizard:BAAANQADCgYIBgABNQAECgYICAAIAAAAAA==.Wonderface:BAAANQADCgcIBwABNQAECggIHQAQAHcMAA==.Wonderfu:BAAANQAECgYIEAAAAA==.Woodhorn:BAAANQAECgcIBwAAAA==.Wookreformed:BAAANQAECgEIAQAAAA==.Wordrid:BAAANQADCggIHQAAAA==.',
Wt='Wtfocks:BAABNQAECoEUAAIFAAYKQhT+CgB/AQAFAAYKQhT+CgB/AQAAAA==.',
Wu='Wuiigii:BAABNQAECoEXAAIPAAgK4BkVGwDsAQAPAAgK4BkVGwDsAQAAAA==.Wurzel:BAAANQADCggICAAAAA==.',
Xa='Xaena:BAAANQADCgcIGgAAAA==.Xanatis:BAAANQADCggIDgABNQAECgkJLgALAE4hAA==.Xanavi:BAAANQAECgEIAQAAAA==.Xatus:BAAANQAECgYIEQAAAA==.',
Xe='Xendrik:BAABNQAECoEZAAMdAAgKSw9+BwDOAQAdAAcKhQ9+BwDOAQAiAAYK+AnSPgAsAQAAAA==.Xenyl:BAAANQAECgEIAQAAAA==.',
Xi='Xiaolia:BAAANQAECgcIDgAAAA==.',
Ya='Yamihikari:BAABNQAECoEXAAIKAAcKuBCQWQCDAQAKAAcKuBCQWQCDAQAAAA==.Yarela:BAAANQADCgYJDQAAAA==.',
Ye='Yedster:BAAANQAECgUIBQAAAA==.Yenara:BAABNQAECoEdAAIGAAkKqhv6EgC0AgAGAAkKqhv6EgC0AgAAAA==.Yesrav:BAAANQAECgIIAgAAAA==.',
Yi='Yihua:BAAANQAECggIHQAAAQ==.Yinohn:BAAANQAECgYICQABNQAECgkJJQAPAKIhAA==.Yippee:BAAANQAECggIEwAAAA==.',
Yu='Yumba:BAAANQAECgQICQAAAA==.',
['Yå']='Yång:BAAANQADCgYICAAAAA==.',
Za='Zaborg:BAABNQAECoEjAAMBAAgKSRBAawD1AQABAAgKSRBAawD1AQAgAAQKMQb3QAC1AAAAAA==.Zalduras:BAAANQADCgcIDQAAAA==.Zalerien:BAAANQADCgEIAQABNQAECggIHQAIAAAAAA==.Zandig:BAABNQAECoEaAAMBAAcKSSCQQAB1AgABAAcKpR+QQAB1AgAgAAEKARwNZABPAAAAAA==.Zappyzapp:BAAANQAECgQIBAAAAA==.Zaricht:BAAANQADCgIIAgAAAA==.Zartman:BAAANQADCgUIBQAAAA==.Zathog:BAAANQAECgYICAAAAA==.',
Ze='Zebin:BAAANQADCgUIBQAAAA==.Zeem:BAAANQAECgQICQAAAA==.Zerthimon:BAAANQABCgIIAgAAAA==.',
Zh='Zharae:BAAANQAECgQICQAAAA==.',
Zi='Ziaroe:BAAANQADCgEIAQAAAA==.Ziayn:BAAANQADCgQIBQAAAA==.',
Zo='Zoet:BAABNQAECoEdAAIDAAkKDBYPXQBWAgADAAkKDBYPXQBWAgAAAA==.Zohân:BAAANQAECgIIAgAAAA==.',
Zu='Zulani:BAABNQAECoEaAAIZAAgK3CHoHgAAAwAZAAgK3CHoHgAAAwAAAA==.Zurana:BAAANQADCgYIBgABNQAECgYIDQAIAAAAAA==.',
Zy='Zythen:BAAANQADCgUIBQAAAA==.',
['Àl']='Àlik:BAABNQAECoEkAAMXAAgKSxhIPABWAgAXAAgKSxhIPABWAgADAAcKcAw2xQBYAQAAAA==.',
['Áa']='Áayla:BAAANQADCggICAAAAA==.',
['Çh']='Çhökèm:BAABNQAECoEYAAMWAAkKAxqkHgA+AgAWAAgKvxukHgA+AgAVAAEKKgwGggA2AAABNQAECgkJLQAHAPYcAA==.',
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
