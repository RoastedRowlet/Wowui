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

local lookup = {'Warrior-Protection','Hunter-BeastMastery','Rogue-Assassination','Shaman-Elemental','Mage-Frost','Mage-Arcane','Hunter-Marksmanship','Rogue-Subtlety','Shaman-Restoration','Unknown-Unknown','Paladin-Holy','Priest-Shadow','Priest-Holy','Paladin-Retribution','Warrior-Arms','DemonHunter-Havoc','Warrior-Fury','Druid-Guardian','Druid-Restoration','Monk-Mistweaver','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Outlaw','Paladin-Protection','Druid-Balance','Warlock-Demonology','Evoker-Devastation','Monk-Windwalker','Mage-Fire','DeathKnight-Frost','Evoker-Preservation','Evoker-Augmentation','Warlock-Destruction','DemonHunter-Vengeance','Shaman-Enhancement','Warlock-Affliction','DemonHunter-Devourer','Priest-Discipline','Monk-Brewmaster','Druid-Feral',}
local provider = {region='US',realm='Korgath',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abbygrace:BAAANQAECgUIBgAAAA==.Abcdemon:BAAANQAECgIIAwABNQAFFAUICgABAGURAA==.',
Ad='Adar:BAABNQAECoEWAAICAAcKMBfGdgD0AQACAAcKMBfGdgD0AQAAAA==.',
Ae='Aegeis:BAAANQAECgEIAQABNQAECggIHgADADgVAA==.Aelaryn:BAAANQAECgYICQAAAA==.Aeonffx:BAAANQAECgIIAgAAAA==.',
Af='Afterearth:BAACNQAFFIEQAAIEAAUKsSIvBgDtAQAEAAUKsSIvBgDtAQA1AAQKgSMAAgQACQoWJf4IAJQDAAQACQoWJf4IAJQDAAAA.',
Ag='Aggrobeast:BAAANQAECgcIEAAAAA==.Agoný:BAAANQADCgQIBAAAAA==.',
Ai='Ailie:BAABNQAECoEbAAMFAAgKcR0WCAA2AgAFAAgKcR0WCAA2AgAGAAMKrw4YewGXAAAAAA==.',
Ak='Akadey:BAAANQADCgYICAAAAA==.',
Al='Aliì:BAAANQAECgcIEwABNQAFFAQIBwAHAIQNAA==.Allise:BAAANQAECgYICQAAAA==.Allnightlong:BAAANQAECgQJBAABNQAECggIIAAIADYWAA==.Allnightløng:BAABNQAECoEgAAMIAAgKNhb5EQBQAgAIAAgKNhb5EQBQAgADAAIKpQuweAB0AAAAAA==.Alphonos:BAAANQADCgMIAwAAAA==.Alverez:BAABNQAECoFJAAIJAAkKaSGYDABIAwAJAAkKaSGYDABIAwAAAA==.',
Am='Amorilas:BAAANQAECgYIEQAAAA==.Amunera:BAAANQADCgYIEAABNQAECgEIAQAKAAAAAA==.Amàrok:BAAANQADCgUICgABNQAECgIIAgAKAAAAAA==.',
An='Anaqt:BAAANQAECgEIAQAAAA==.Andersan:BAABNQAECoEvAAILAAgKwBJ4VAD8AQALAAgKwBJ4VAD8AQAAAA==.Anetharion:BAAANQAECgEIAQAAAA==.Animalchange:BAAANQAECgQIEQAAAA==.Anklelock:BAAANQADCgUIBAAAAA==.',
Ap='Apeth:BAAANQADCgEIAQAAAA==.Applepi:BAABNQAECoEYAAIMAAgKKBeeHAA7AgAMAAgKKBeeHAA7AgAAAA==.Aproditee:BAAANQADCgMIBAAAAA==.',
Ar='Areayl:BAABNQAECoEdAAINAAkKgBfCNABzAgANAAkKgBfCNABzAgAAAA==.Arinn:BAACNQAFFIEHAAMHAAQKhA2DEQDvAAAHAAQKRAiDEQDvAAACAAIKMA92HACpAAA1AAQKgSEAAwcACQpVHsIfADMCAAcACAoJGsIfADMCAAIABwrZGKGOALsBAAAA.',
As='Ashtkal:BAABNQAECoEiAAMLAAkKOCHNDABUAwALAAkKOCHNDABUAwAOAAIKzg94PAF7AAAAAA==.Ashtoes:BAABNQAECoEcAAICAAgKbxI0XgAxAgACAAgKbxI0XgAxAgAAAA==.Astralbubble:BAABNQAECoEdAAILAAkKdxwqHADuAgALAAkKdxwqHADuAgAAAA==.',
At='Athená:BAAANQADCggIDAAAAA==.',
Au='August:BAAANQADCggIEAAAAA==.Auratic:BAAANQAECgEIAgAAAA==.Automation:BAAANQAECgYICAABNQAFFAQICQAGAGEXAA==.',
Av='Avalea:BAAANQADCgUIBwAAAA==.Avaleir:BAAANQAECgIIAwAAAA==.',
Ay='Ayahuascå:BAABNQAECoEiAAMEAAkKwAAZEAE4AAAEAAkKwAAZEAE4AAAJAAIKBQBcIgEBAAAAAA==.Ayyvlaad:BAAANQAECgcIEwAAAA==.',
Az='Azerlite:BAAANQAECgYICAABNQAECgkJLgAEAMwdAA==.Azkota:BAABNQAECoEeAAIJAAgK4RaXSgAMAgAJAAgK4RaXSgAMAgAAAA==.Azulwall:BAAANQAECgUICgAAAA==.Azureros:BAABNQAECoEiAAICAAgKAxvfQgB9AgACAAgKAxvfQgB9AgAAAA==.',
Ba='Bandaayd:BAAANQAECgEIAQAAAA==.Bargaug:BAAANQADCgYJBgABNQAECgkJIQAPAJQeAA==.Bathasar:BAAANQAECgYICgAAAA==.Bathpally:BAAANQAECgUIEgAAAA==.',
Be='Beandh:BAAANQADCggIEAABNQAFFAYIEAAQAIAQAA==.Beanygene:BAAANQAECgUIBQAAAA==.Bearwithme:BAAANQADCgYIBgAAAA==.Beastfury:BAABNQAECoEaAAIHAAgKlhyqFwCEAgAHAAgKlhyqFwCEAgAAAA==.Beefyclap:BAABNQAECoEUAAIRAAQK8yGoDwCLAQARAAQK8yGoDwCLAQAAAA==.Begal:BAABNQAFFIEHAAMMAAQKewOJDQDHAAAMAAMKggSJDQDHAAANAAEKNwazLABLAAAAAA==.Beha:BAAANQADCgEIAQAAAA==.Beleria:BAAANQADCgMIAwAAAA==.Bellaidd:BAABNQAECoEVAAISAAgKgw56HQBvAQASAAgKgw56HQBvAQAAAA==.Bellore:BAAANQAECgMIBAAAAA==.Benafflict:BAAANQAECggIAgAAAA==.Benedîct:BAAANQAECgYIEAAAAA==.Bewblywoobly:BAAANQAECgUIEwAAAA==.Bezvoker:BAAANQADCgUIBQAAAA==.Beástboy:BAABNQAECoEdAAITAAgKECEXDADvAgATAAgKECEXDADvAgAAAA==.',
Bi='Biekdafreak:BAAANQAECgYICgAAAA==.Bigbackmoto:BAAANQADCgMIAwAAAA==.Bigblade:BAAANQADCgIIAwAAAA==.Bigbuffalo:BAAANQADCggIDAAAAA==.Bigdaddoo:BAAANQADCgUIBQAAAA==.Biggbob:BAAANQAECgEIAQAAAA==.Biggisign:BAABNQAECoEYAAIUAAgKPwu7HgByAQAUAAgKPwu7HgByAQAAAA==.Bina:BAAANQADCggICAAAAA==.Binddy:BAAANQADCgIIAgAAAA==.Bingberries:BAAANQADCgQIBQAAAA==.Bitemenow:BAAANQAECgUICAAAAA==.Bitsobacon:BAABNQAECoEeAAMJAAkKOgiVbgCQAQAJAAkKOgiVbgCQAQAEAAYKuAMvvADrAAAAAA==.Bizzó:BAAANQAECgEIAQAAAA==.',
Bl='Bladeboy:BAAANQABCgIIAgAAAA==.Blamblam:BAAANQAECgYIBgAAAA==.Blambus:BAAANQAECgEIAQAAAA==.Blambussi:BAAANQADCgcIEgAAAA==.Blckbeard:BAAANQADCgIIAgAAAA==.Blitzball:BAAANQAECgEIAQAAAA==.Blooddragoon:BAABNQAECoEZAAIOAAgKIh/vQQCpAgAOAAgKIh/vQQCpAgAAAA==.Bloodycrow:BAAANQABCgMIAwAAAA==.Bluestas:BAAANQABCgIIAgAAAA==.',
Bo='Bohica:BAABNQAECoEfAAIVAAkKNRXyOAAbAgAVAAkKNRXyOAAbAgAAAA==.Bombadil:BAAANQAECgQIBgAAAA==.Bomberdeath:BAABNQAECoEaAAMVAAcKYx6DNwAjAgAVAAcKYx6DNwAjAgAWAAEK4QCe0wAXAAAAAA==.Bomberpally:BAAANQADCgMIAwAAAA==.Bongrip:BAAANQAECggICwAAAA==.Boochstorm:BAAANQADCggIDAAAAA==.Boogiee:BAAANQAECgYIDQABNQAECggIIAAQADcMAA==.Boons:BAAANQAECgMIBQABNQAECggIKAAXAHEjAA==.Boosh:BAAANQADCgYICAAAAA==.Boostednub:BAAANQABCgYIDAAAAA==.',
Br='Bradington:BAAANQAECgcIEwAAAA==.Brezel:BAAANQADCgYIBgAAAA==.Briko:BAAANQABCgEIAQABNQAECgEIAQAKAAAAAA==.Brond:BAAANQABCgIIAgAAAA==.Brontide:BAAANQAECgYIEAAAAA==.Browley:BAAANQAECgcIBwAAAA==.Bruengar:BAABNQAECoElAAMOAAgKARyUVABvAgAOAAgKARyUVABvAgAYAAEKWBpPWgBKAAAAAA==.Bruniik:BAABNQAECoEbAAMNAAgKRx4aIQDOAgANAAgKRx4aIQDOAgAMAAEKQwl7dgAmAAAAAA==.',
Bu='Bubblehêarth:BAAANQAECgQICAAAAA==.Budapest:BAABNQAECoEfAAILAAkKnBftJgC1AgALAAkKnBftJgC1AgAAAA==.Buddyolpal:BAAANQAECgYIDQAAAA==.Bumbleh:BAAANQAECgQICAAAAA==.Bumibe:BAAANQADCgcIBwAAAA==.Bungulator:BAABNQAECoEuAAIEAAkKzB3FHgD3AgAEAAkKzB3FHgD3AgAAAA==.Buné:BAABNQAECoEoAAIXAAgKcSNoAgAjAwAXAAgKcSNoAgAjAwAAAA==.Butkus:BAAANQAECgEIAQABNQAECgQICwAKAAAAAA==.',
Ca='Caad:BAAANQAECgUIDQAAAA==.Caddk:BAAANQAECgEIAQAAAA==.Cador:BAAANQAECgYIEgAAAA==.Cadwarr:BAAANQADCgYIBgAAAA==.Cak:BAAANQAECgUIBQABNQAECgYICQAKAAAAAA==.Cam:BAAANQAECgMIBQAAAQ==.Camazotz:BAAANQADCgMIAgAAAA==.Cannibubz:BAAANQAECgQICgAAAA==.Cannilol:BAAANQAECgMIAwAAAA==.Cannimal:BAACNQAFFIEIAAIZAAQKhhHwDwAxAQAZAAQKhhHwDwAxAQA1AAQKgR4AAhkACQqCHyUWAP8CABkACQqCHyUWAP8CAAAA.Cannish:BAAANQAECgEIAQAAAA==.Cataylst:BAAANQAECgIIAwABNQAECgQIBAAKAAAAAA==.Catwilliams:BAABNQAECoEmAAITAAkKTiA0BgBNAwATAAkKTiA0BgBNAwAAAA==.',
Ce='Celestas:BAAANQADCgIIAgAAAA==.',
Ch='Cheeze:BAAANQADCgcICwAAAA==.Chiliwop:BAABNQAECoEiAAIaAAgK0xudOgCIAgAaAAgK0xudOgCIAgAAAA==.Chippydk:BAAANQAECggICAAAAA==.Chippyh:BAABNQAECoEpAAMCAAgK0CAPJwDcAgACAAgK0CAPJwDcAgAHAAIKVQ/fZwBnAAAAAA==.Chloei:BAAANQAFFAEIAQAAAA==.Chulkma:BAAANQABCgEIAQAAAA==.Chwonk:BAAANQAECgYIDwAAAA==.',
Ci='Cik:BAAANQABCgQIBAAAAA==.Circê:BAAANQAECgEIBAAAAA==.Cirin:BAAANQAECgMIBgAAAA==.',
Cl='Cleaved:BAAANQAECgYIDAAAAA==.Cleppy:BAAANQAECgUIBQAAAA==.Clevoker:BAABNQAECoEoAAIbAAkK9SPfAQCXAwAbAAkK9SPfAQCXAwAAAA==.Cloacussy:BAAANQADCgYIBgAAAA==.Cloudystorm:BAAANQAECgYICAABNQAFFAUIEAAOAK4gAA==.Clusion:BAABNQAFFIEGAAIcAAMKIBIJCgDbAAAcAAMKIBIJCgDbAAAAAA==.',
Co='Codex:BAABNQAECoEeAAIGAAgKDBpNegByAgAGAAgKDBpNegByAgAAAA==.Cole:BAAANQADCggIDAAAAA==.Conanb:BAAANQADCggICAAAAA==.Conductor:BAABNQAECoEvAAIdAAkKph6XAAA9AwAdAAkKph6XAAA9AwAAAA==.Convergent:BAABNQAECoEgAAMWAAkK8Bq2HQCqAgAWAAgKBR22HQCqAgAVAAEKRwoAAAAAAAAAAA==.Coosh:BAACNQAFFIEQAAIGAAUK9CAkDwDZAQAGAAUK9CAkDwDZAQA1AAQKgScAAgYACQpYI+kSAIEDAAYACQpYI+kSAIEDAAAA.Cornydog:BAAANQADCgIIBQAAAA==.Cornydogy:BAAANQADCgEIAQAAAA==.Corov:BAAANQAECgQIBQAAAA==.Corovv:BAAANQABCgUIBwAAAA==.Courigon:BAAANQAECgEIAQAAAA==.Cowish:BAAANQAECgMIAwAAAA==.',
Cp='Cptamerica:BAABNQAECoEcAAILAAkKux3dFAAbAwALAAkKux3dFAAbAwAAAA==.',
Cr='Craigolas:BAAANQAECgYIEAAAAA==.Crippler:BAAANQAECgYICwAAAA==.Cromewell:BAAANQADCggIDQAAAA==.Crossbow:BAAANQADCgMIBwAAAA==.Crosscut:BAAANQAECgEIAQAAAA==.Cruelty:BAAANQAECgMIAwAAAA==.Cröw:BAAANQABCgUIBgABNQABCgYICAAKAAAAAA==.',
Cu='Cummins:BAABNQAECoEmAAITAAkKax8VDQDhAgATAAkKax8VDQDhAgAAAA==.Cupcake:BAAANQAECgQIBAAAAA==.Currents:BAAANQADCggICAAAAA==.',
Cy='Cymaig:BAAANQADCgYICQAAAA==.',
Da='Dadstealer:BAAANQAECgUIDgAAAA==.Daemonwing:BAAANQADCgcICgAAAA==.Dagrundel:BAABNQAECoEbAAIWAAgKVBRsOgD6AQAWAAgKVBRsOgD6AQAAAA==.Dalinarix:BAAANQAECgYIDQAAAA==.Dangens:BAAANQAECgcIDQAAAA==.Dankpope:BAAANQAECgIIAgAAAA==.Darkballs:BAAANQAECgcIBwAAAA==.Dasbink:BAAANQADCgYIBgAAAA==.Davrin:BAABNQAECoEoAAQOAAgKhB/XOwC/AgAOAAgKhB/XOwC/AgAYAAYKaBaFLABOAQALAAMKCAk63ACZAAAAAA==.',
De='Deathbyarow:BAAANQAECgUIDwAAAA==.Deathhammer:BAABNQAECoEWAAIWAAcK5wbJagAkAQAWAAcK5wbJagAkAQAAAA==.Deathjrak:BAABNQAECoEgAAMWAAkKtBxZMQAtAgAWAAcKMh5ZMQAtAgAVAAYK5Bk5RgDZAQAAAA==.Deesixxfour:BAAANQADCgUIBQABNQAECgkJIQAPAOYjAA==.Degates:BAAANQAECgIIAgAAAA==.Deldor:BAAANQABCggICAAAAA==.Demonia:BAAANQAECgQIBgAAAA==.Demonicshoes:BAAANQAECgUICwAAAA==.Dethwing:BAABNQAECoEiAAQeAAgKthEgPgCQAQAeAAcKMxAgPgCQAQAVAAYKig99awBAAQAWAAEKhwyTvwAtAAAAAA==.Devaña:BAABNQAECoEYAAICAAgKtB6uKwDKAgACAAgKtB6uKwDKAgAAAA==.',
Di='Dianora:BAAANQADCgcIBwAAAA==.Diclonius:BAAANQAECgYIEQAAAA==.Dieclonius:BAAANQADCgQIBgAAAA==.Dikosmoney:BAAANQAECgIIAgAAAA==.Dildas:BAAANQADCgcIDAAAAA==.Dirtystaff:BAAANQAECgUIDAAAAA==.Dirtzmage:BAABNQAECoEXAAIGAAYKYBg92ACwAQAGAAYKYBg92ACwAQAAAA==.Dirtzz:BAAANQADCgQIBAAAAA==.Dizzledh:BAAANQAECgYIEgAAAA==.Dizzranger:BAAANQAECgUIBQAAAA==.Dizzsteel:BAAANQAECgEIAgABNQAECgUIBQAKAAAAAA==.',
Dj='Djkhaledd:BAABNQAECoEbAAIEAAkKQR/wGAAdAwAEAAkKQR/wGAAdAwAAAA==.',
Dk='Dkpowah:BAAANQAECgUIBAAAAA==.',
Do='Doobins:BAAANQAECgYIEAAAAA==.Dookiboy:BAAANQAECgQIBgABNQAECgkJKgAHAAUcAA==.Doomedstar:BAAANQADCgEIAQABNQAECgkJLwAdAKYeAA==.Dooy:BAAANQAECgUIDwAAAA==.Douii:BAAANQADCggICAAAAA==.',
Dr='Draco:BAAANQABCgQICAAAAA==.Draconir:BAAANQABCgYICAAAAA==.Dragao:BAAANQADCgYIBgAAAA==.Draggen:BAABNQAECoEUAAIbAAYKFx6eFQDQAQAbAAYKFx6eFQDQAQAAAA==.Dragimal:BAAANQAECgUICgAAAA==.Dragonn:BAAANQAECgQICAAAAA==.Dragonoied:BAAANQADCgMIAwAAAA==.Dragonxlord:BAAANQAECgUICQAAAA==.Dragosia:BAABNQAECoE8AAQfAAkKqBNuFABUAgAfAAkKqBNuFABUAgAgAAMKqxgbEwDSAAAbAAEKXgaoOQAxAAAAAA==.Drakojangens:BAABNQAECoEcAAIfAAgKayAsCgDyAgAfAAgKayAsCgDyAgAAAA==.Drakthar:BAAANQADCggIFgAAAA==.Dranoric:BAAANQADCggIDAABNQAECgkJIQAPAA8ZAA==.Dreebus:BAAANQADCgYIBgABNQAECggIKAAWAK0LAA==.Drev:BAAANQADCgYICwAAAA==.Drlawyerphd:BAABNQAECoEcAAIIAAcKYBm1FwAPAgAIAAcKYBm1FwAPAgAAAA==.Droving:BAAANQADCgUIBQAAAA==.Druidijrak:BAAANQADCgYIBwAAAA==.Druini:BAAANQABCgYICAAAAA==.Druz:BAAANQAECgYIDAAAAA==.',
Ds='Dsixfoour:BAAANQAECgEJAQABNQAECgkJIQAPAOYjAA==.Dsixxfour:BAABNQAECoEhAAIPAAkK5iNwGQBHAwAPAAkK5iNwGQBHAwAAAA==.',
Du='Dumdumdugan:BAAANQABCgQIBgABNQADCggICAAKAAAAAA==.Duncedivh:BAAANQADCggIGQAAAA==.Dunzjan:BAABNQAECoEfAAMhAAgKPRwhGACiAQAhAAUKuhwhGACiAQAaAAMKbRtC3QDiAAAAAA==.Durrinn:BAAANQADCgcIBwABNQAECggIJAAFAGoWAA==.',
Dy='Dysmai:BAAANQADCgYICwAAAA==.',
['Dé']='Déathwolf:BAABNQAECoElAAIVAAgK7AywVQCSAQAVAAgK7AywVQCSAQAAAA==.',
['Dø']='Døminic:BAAANQAECgUICQAAAA==.',
Ea='Earthlore:BAAANQABCgQIBwAAAA==.Eatsammich:BAAANQADCggIEQAAAA==.',
Eg='Eggsbenedïct:BAABNQAECoEWAAIHAAkK3RBRJQABAgAHAAkK3RBRJQABAgAAAA==.Egol:BAABNQAECoEkAAMTAAkKzyTaBgBBAwATAAgK8yTaBgBBAwAZAAEK+B6fkgBYAAAAAA==.',
El='Eldonra:BAAANQADCgYIBgABNQAFFAYIEAAPAGwRAA==.Elidrine:BAAANQAECgQIBAAAAA==.Elmerfuddz:BAABNQAECoEgAAMCAAgKuQ6IaQAUAgACAAgKuQ6IaQAUAgAHAAYKegLTTADPAAAAAA==.Elyrayldin:BAAANQAECgYIEAAAAA==.',
En='Enazenoth:BAACNQAFFIEHAAIbAAQKoBT8BQAvAQAbAAQKoBT8BQAvAQA1AAQKgRgAAhsACQoUIooGAAsDABsACQoUIooGAAsDAAAA.Endymíon:BAAANQAECggICAABNQAFFAQICAAiAIYFAA==.Enryu:BAAANQAECggIDwAAAA==.Envburnz:BAAANQAECgUICwAAAA==.',
Er='Erooka:BAABNQAECoElAAIGAAkKAh6nNwAMAwAGAAkKAh6nNwAMAwAAAA==.',
Es='Esio:BAABNQAECoEgAAIPAAgKNhV6egAGAgAPAAgKNhV6egAGAgAAAA==.',
Ev='Evileyes:BAAANQADCgUIBQABNQADCggJCAAKAAAAAA==.',
Ey='Eyri:BAABNQAECoEoAAIGAAgKdxP3oAAgAgAGAAgKdxP3oAAgAgAAAA==.',
Ez='Ezzie:BAAANQAECgYIEQAAAA==.',
Fa='Falsodew:BAABNQAECoEaAAIJAAkKPhjCRAAjAgAJAAkKPhjCRAAjAgAAAA==.',
Fe='Felicity:BAABNQAECoEdAAIQAAcK7QYwSwA8AQAQAAcK7QYwSwA8AQAAAA==.Femme:BAAANQAECgUIBgAAAA==.Femmever:BAAANQAECgEIAQAAAA==.Feonix:BAABNQAECoEoAAIGAAkKyCGpFAB6AwAGAAkKyCGpFAB6AwAAAA==.Ferenus:BAAANQABCggICgAAAA==.Fewsha:BAACNQAFFIEYAAIEAAcKWR6wAQCRAgAEAAcKWR6wAQCRAgA1AAQKgSYAAgQACQrxJFkLAIADAAQACQrxJFkLAIADAAAA.',
Fi='Fidellia:BAAANQAECgYIEgAAAA==.Findie:BAAANQAECgUICQAAAA==.',
Fl='Fleshoflìght:BAAANQADCgIIAgAAAA==.',
Fo='Foofoolala:BAAANQADCgYIFAAAAA==.Fookadk:BAAANQADCggJGQAAAA==.Fookapalli:BAAANQABCgYICgAAAA==.Forttoo:BAAANQADCgEIAQAAAA==.Fourthwing:BAAANQADCgQIBAAAAA==.',
Fr='Frawstbyte:BAABNQAECoEiAAIGAAkKHhlBagCVAgAGAAkKHhlBagCVAgAAAA==.Fredbearr:BAAANQADCgMIAwAAAA==.Freeholed:BAABNQAECoEgAAIVAAkKNB3GHgC0AgAVAAkKNB3GHgC0AgAAAA==.Fridgefister:BAABNQAECoEXAAMcAAcKWw9+NQAyAQAcAAYKPAx+NQAyAQAUAAEKmgRASgAmAAAAAA==.Frodie:BAABNQAECoEZAAMFAAkKGwpuEQBnAQAGAAkK9gjSuQDtAQAFAAgK0AduEQBnAQAAAA==.',
Fu='Fumina:BAAANQAECgUICwAAAA==.',
Ga='Gaea:BAABNQAECoEeAAICAAgKtxmkQgB+AgACAAgKtxmkQgB+AgAAAA==.Gallanon:BAAANQAECgEIAQAAAA==.Gallshot:BAAANQADCgUIDQAAAA==.Galuciene:BAAANQADCgEIAQAAAA==.Gamergirl:BAAANQABCgcIBwAAAA==.Gangrêl:BAAANQADCgYIDAABNQAECgEIAQAKAAAAAA==.Garithor:BAAANQAECgMIAwAAAA==.',
Gb='Gbang:BAAANQAECgIIAwAAAA==.',
Ge='Gekidoryu:BAAANQADCgQIBAABNQAECgYIBgAKAAAAAA==.Gerebert:BAAANQAECgYIDwAAAA==.Getajobubum:BAABNQAECoEhAAIEAAgKyBn3PABZAgAEAAgKyBn3PABZAgAAAA==.',
Gh='Ghalizor:BAAANQADCgYIBgABNQAECgYICQAKAAAAAA==.Ghostdance:BAACNQAFFIESAAIGAAYKPxv/BwAjAgAGAAYKPxv/BwAjAgA1AAQKgSYAAgYACQpzJYQNAJkDAAYACQpzJYQNAJkDAAAA.Ghoulia:BAAANQAECgIIAgAAAA==.',
Gi='Giggz:BAAANQAECgYIDQAAAA==.Gilgalight:BAAANQAECgYICwAAAA==.Gingerpala:BAAANQADCgQJBwAAAA==.Giuttrix:BAAANQAECgYIDwAAAA==.',
Gl='Glacie:BAAANQAECgEIAgAAAA==.Gleams:BAAANQAECgQIDAAAAA==.Gloriousdead:BAAANQADCgYIBgAAAA==.Glowing:BAAANQAECgcIEQAAAA==.',
Go='Gokukakarot:BAAANQAECgUIDwAAAA==.Goldann:BAAANQABCgcIEQAAAA==.Goldeneyes:BAAANQADCgMIAwAAAA==.Goldlore:BAAANQAECgQIBwAAAA==.Gonger:BAAANQAECgUIDgAAAA==.Goopdk:BAAANQAECgQJCQABNQAECgYICwAKAAAAAA==.Gosiâ:BAAANQAECgUIDQABNQAECgkJPAAfAKgTAA==.Gothikia:BAAANQAECgYIEAAAAA==.',
Gr='Gremhunt:BAAANQAECgIIAgAAAA==.Grondel:BAAANQAECgcICQAAAA==.Gruhan:BAAANQAECgcIBwAAAA==.Grummish:BAAANQADCgQIBAAAAA==.Grumpybear:BAAANQADCgcIDwAAAA==.',
Gu='Guiltea:BAAANQADCgEIAQAAAA==.Gundham:BAAANQAECgUICwAAAA==.Gunko:BAAANQAECgQIBwAAAA==.Gunstrong:BAAANQAECgQJBgAAAA==.',
['Gõ']='Gõsia:BAAANQAECgQIBgAAAA==.',
['Gø']='Gøtt:BAAANQADCgIIAgAAAA==.',
Ha='Haagendots:BAAANQAECgYIEQAAAA==.Hadokens:BAAANQAECgEIAQAAAA==.Hairofwar:BAABNQAECoElAAIBAAgKBSGjBQD2AgABAAgKBSGjBQD2AgAAAA==.Haleynicole:BAAANQAECgYIEQAAAA==.Happydaug:BAAANQADCgcICwABNQAFFAMICQAcAOESAA==.Happydawg:BAACNQAFFIEJAAIcAAMK4RIwCgDWAAAcAAMK4RIwCgDWAAA1AAQKgSgAAhwACQoWJAgEAIkDABwACQoWJAgEAIkDAAAA.Hasted:BAACNQAFFIEJAAIGAAQKYRexHQBZAQAGAAQKYRexHQBZAQA1AAQKgSEAAgYACQrpIlcfAFMDAAYACQrpIlcfAFMDAAAA.Hawktar:BAABNQAECoEeAAIHAAkKtRihGQBxAgAHAAkKtRihGQBxAgAAAA==.',
He='Healimus:BAABNQAECoEfAAILAAgKmg3RYgDLAQALAAgKmg3RYgDLAQAAAA==.Healmates:BAAANQAECgYICQAAAA==.Helix:BAABNQAECoEpAAIJAAkKUx6xGwDkAgAJAAkKUx6xGwDkAgAAAA==.Hennybull:BAAANQADCgIIAgAAAA==.Henný:BAAANQADCgQIBAAAAA==.Hesperos:BAAANQADCggIEQAAAA==.',
Ho='Ho:BAAANQAECgcIBwAAAA==.Hoffzz:BAAANQAECgQICQAAAA==.Holee:BAAANQADCgYICwAAAA==.Holybaby:BAAANQAECgYIEwAAAA==.Holybrute:BAAANQAECgIIAwABNQAECgkJIwAaACYaAA==.Holybunger:BAAANQAECgYICQAAAA==.Holycannoli:BAAANQADCgIIAgABNQADCgQIBwAKAAAAAA==.Holyscheisse:BAAANQAECggIAwABNQAECgkJIgAEAMAAAA==.Holysheetz:BAAANQABCgQIBAAAAA==.Horde:BAAANQADCgcICwAAAA==.',
Hu='Hueycheeks:BAABNQAECoEjAAIjAAkKeBx9CADgAgAjAAkKeBx9CADgAgAAAA==.Humantelope:BAAANQAECgYICwAAAA==.Huntstatus:BAABNQAECoEiAAICAAgKAxTFgQDaAQACAAgKAxTFgQDaAQAAAA==.Huxium:BAABNQAECoEcAAICAAcKDRVseADwAQACAAcKDRVseADwAQAAAA==.',
Hw='Hwangdoyoung:BAAANQABCgEIAQABNQADCgEJAQAKAAAAAA==.',
Hy='Hymnpossible:BAABNQAECoEcAAINAAgK7hgvPwBJAgANAAgK7hgvPwBJAgAAAA==.',
Ic='Icecreamdveg:BAAANQADCggICQAAAA==.Icetongue:BAABNQAECoEiAAIFAAgKgxyJBQCPAgAFAAgKgxyJBQCPAgAAAA==.',
If='Iflingpoo:BAABNQAECoEwAAIWAAkKzxzVGgDAAgAWAAkKzxzVGgDAAgAAAA==.Ifusêekamy:BAAANQAECgUIDAAAAA==.',
Ij='Ijrakwarrior:BAAANQAECgIIAgAAAA==.',
Il='Illidussy:BAAANQADCgcIBwABNQAECgEIAQAKAAAAAA==.Illregularxx:BAAANQAECgIIBAAAAA==.',
Im='Imposteroak:BAAANQAECgIIAgAAAA==.Impulse:BAABNQAECoEYAAILAAcKHyCHMwB7AgALAAcKHyCHMwB7AgAAAA==.',
In='Indelebi:BAAANQABCgQIBgAAAA==.Inorgeing:BAAANQAECgMIBAAAAA==.Intrúder:BAAANQADCgEIAQAAAA==.',
Ir='Irdaman:BAAANQAECgEIAQABNQAECgkJHwANADgXAA==.Irmengaud:BAAANQAECgYIEAAAAA==.Ironbrowd:BAAANQAECgEIAQAAAA==.Ironpup:BAABNQAECoEbAAQaAAgKDRaXcwDdAQAaAAgKug6XcwDdAQAhAAMKwRvBMAD5AAAkAAMKaRF7FADWAAAAAA==.Ironscales:BAAANQAECgQIAQABNQAFFAgIAgAKAAAAAA==.',
Ja='Jabbyjr:BAABNQAECoEmAAMRAAgKsRGNCwDlAQARAAgKsRGNCwDlAQAPAAEKTQ0KNAE1AAAAAA==.Jabum:BAAANQAECgcICgAAAA==.Jaio:BAAANQAECgcIEQAAAA==.Jajakuna:BAAANQAECgYIDwAAAA==.Jangens:BAAANQAFFAEIAQABNQAECggIHAAfAGsgAA==.Jarofsomethi:BAAANQAECgYIDwAAAA==.Jaruni:BAABNQAECoEkAAIYAAgKXR7WDgCKAgAYAAgKXR7WDgCKAgAAAA==.Jaynine:BAABNQAECoEpAAMMAAkKgxqXGABqAgAMAAgKQBuXGABqAgANAAkKKg/pTgAOAgAAAA==.Jazerfunk:BAAANQADCgEIAQAAAA==.',
Je='Jeffvyrt:BAAANQAECgYIDQAAAA==.Jeksulee:BAAANQABCggIEAAAAA==.',
Ji='Jibbs:BAAANQAECgcICwAAAA==.',
Jo='Jodimaw:BAAANQAECgEIAQAAAA==.Johncleve:BAAANQADCgUIBwAAAA==.Jorian:BAAANQAECgQIBAAAAA==.Joridiezs:BAAANQAECgUICgAAAA==.Joshness:BAAANQADCgMIAwAAAA==.',
Ju='Juanrambo:BAAANQAECgUIDQAAAA==.Juicyjohnson:BAAANQADCgMIBQABNQAECgkJIAAOAD8lAA==.Jumblo:BAAANQAECgYIEQAAAA==.Jupileo:BAABNQAECoEfAAIFAAgKPwpbEAB4AQAFAAgKPwpbEAB4AQAAAA==.Jurassichots:BAAANQADCggIDwAAAA==.',
['Jé']='Jésus:BAAANQAECgYICwAAAA==.',
Ka='Kaalista:BAAANQAECgEJAwABNQAECggIEwAKAAAAAA==.Kaiiju:BAAANQADCggICAAAAA==.Kailee:BAACNQAFFIEWAAIcAAcKQx9UAQCHAgAcAAcKQx9UAQCHAgA1AAQKgSgAAhwACQoPJggDAJ4DABwACQoPJggDAJ4DAAE1AAQKAwgEAAoAAAAA.Kaito:BAAANQAECgEIAQAAAA==.Kakaboy:BAAANQAECgQIBAABNQAECgkJKgAHAAUcAA==.Kaolis:BAAANQADCggICQAAAA==.Kariba:BAABNQAECoEjAAIMAAkKaSKaBgBeAwAMAAkKaSKaBgBeAwABNQAFFAQICAAVAMAXAA==.Karmablood:BAAANQAECggIAwAAAA==.Karmana:BAAANQAECggIEAAAAA==.Katael:BAAANQADCgYICwAAAA==.Kavel:BAABNQAECoEeAAMGAAkKyBlvcwCBAgAGAAkKAhhvcwCBAgAdAAEKiBE2CgBFAAAAAA==.Kaylie:BAAANQAECgMIBAAAAA==.Kayti:BAAANQAECgUIDwAAAA==.',
Ke='Kelfiona:BAAANQAECgIIAgAAAA==.Keraboo:BAABNQAECoEaAAIIAAcKhx8nDwB3AgAIAAcKhx8nDwB3AgAAAA==.Kerie:BAABNQAECoEYAAILAAcK2CFxKQCqAgALAAcK2CFxKQCqAgAAAA==.Kesleya:BAAANQADCgUIBgAAAA==.Ketamyne:BAAANQADCggIFgAAAA==.Keynin:BAAANQADCgUIBQAAAA==.',
Kh='Khalu:BAAANQADCgEIAQAAAA==.',
Ki='Kiandron:BAAANQADCgYIDgAAAA==.Killerqtlol:BAAANQADCggIJgABNQAECgkJJAAJAFcbAA==.Kimbostab:BAAANQADCgMIBAAAAA==.',
Kn='Knockbak:BAAANQAECgYICwAAAA==.',
Ko='Kohko:BAAANQADCgYIBgAAAA==.Kolossus:BAAANQADCgQIBAAAAA==.Kozinirus:BAAANQAECgYIEAAAAA==.',
Kq='Kqmav:BAABNQAECoEUAAIHAAcKmwuoNAB9AQAHAAcKmwuoNAB9AQAAAA==.',
Kr='Kromewell:BAAANQAECgQIBAAAAA==.Kromwell:BAAANQAECggICQAAAA==.Kruwll:BAAANQAECgQICAAAAA==.Krít:BAAANQAECgUICQABNQADCgQIBAAKAAAAAA==.',
Ku='Kukulcan:BAAANQADCgUIBQAAAA==.Kumolock:BAABNQAECoEeAAQkAAgKPhpwBwACAgAkAAYKUxxwBwACAgAaAAUK2hBhswA5AQAhAAEKIhJpbQA8AAAAAA==.Kuntissimo:BAAANQAECgQIBgABNQAECggIGgAHAJYcAA==.Kuongsun:BAAANQADCggIEgAAAA==.',
['Kú']='Kúrama:BAAANQABCgYICAAAAA==.',
La='Ladeehunter:BAABNQAECoEZAAICAAgKrRmaRAB4AgACAAgKrRmaRAB4AgAAAA==.Lambsbreath:BAAANQADCggIFwAAAA==.Lanto:BAAANQADCgUICAABNQABCgIIAgAKAAAAAA==.Laprofessora:BAAANQADCggICQAAAA==.Laquince:BAAANQAECgYIDwAAAA==.Lasagnazaddy:BAAANQADCgYICwAAAA==.Laurafel:BAAANQAECgYICwAAAA==.',
Le='Leetlee:BAAANQADCgMIAwAAAA==.Lelouché:BAAANQABCgIIAgABNQABCgYICAAKAAAAAA==.Lertglochen:BAAANQAECgMICwAAAA==.Lexistarr:BAEANQAECgQIBQABNQAECgYIEQAKAAAAAA==.',
Li='Lickmelow:BAAANQADCgUIAQAAAA==.Lightbunz:BAAANQADCgQJBAAAAA==.Lightcast:BAAANQAECgIIAgABNQAFFAUIDQATAMYWAA==.Lightra:BAAANQAECgUIDgAAAA==.Limeywater:BAABNQAECoEiAAIUAAgKyxjJEgAjAgAUAAgKyxjJEgAjAgAAAA==.Lindramech:BAAANQADCgYIBgAAAA==.Liquedz:BAAANQADCgYIBgABNQAECgQICQAKAAAAAA==.Litherous:BAAANQAECgcIDgAAAA==.Litzdh:BAABNQAECoEWAAIQAAcK0hQgNwDDAQAQAAcK0hQgNwDDAQAAAA==.',
Ll='Llazereth:BAABNQAECoEoAAIWAAgKrQttVwBzAQAWAAgKrQttVwBzAQAAAA==.Llordvalar:BAAANQADCgIJAgAAAA==.',
Lo='Lockimar:BAEBNQAECoEZAAQaAAgK/AvQgwCvAQAaAAgK/AvQgwCvAQAhAAQK0wWBPwC6AAAkAAEKVA8KLQAyAAAAAA==.Lockuru:BAABNQAECoEmAAMhAAkKrh2NHACBAQAaAAcKfhzHUQA/AgAhAAYKNQ+NHACBAQAAAA==.Lonestàr:BAABNQAECoEXAAIFAAcKdheVCgDrAQAFAAcKdheVCgDrAQAAAA==.Lowiqslowirl:BAAANQABCgIIAgAAAA==.',
Lu='Lucian:BAAANQADCgMIAwAAAA==.Lucidy:BAAANQAECggIDgAAAA==.Lumberjacked:BAAANQAECgQIBwABNQAECgkJGQAXAM0hAA==.Luna:BAAANQADCgYIDQABNQAECggIHwAaAB0eAA==.Luspriest:BAAANQADCgQIBAAAAA==.Lusuffer:BAABNQAECoEnAAIWAAkKfiAEDgAvAwAWAAkKfiAEDgAvAwAAAA==.Lusufferr:BAAANQAECgQIBAABNQAECgkJJwAWAH4gAA==.Lutra:BAABNQAECoEiAAIUAAgKvxTdFQDvAQAUAAgKvxTdFQDvAQAAAA==.',
Ly='Lyx:BAAANQAECgUICgAAAA==.',
Ma='Madseason:BAAANQAECgEIAgAAAA==.Magerpwn:BAAANQADCgUIBQAAAA==.Magictats:BAAANQAECgQIBAABNQAECgYIDQAKAAAAAA==.Magusarcanus:BAAANQAECgQICgAAAA==.Makrio:BAAANQABCgUIBwAAAA==.Malachî:BAAANQAECgIIBAAAAA==.Malitan:BAABNQAECoEuAAIOAAkK+BqxSgCOAgAOAAkK+BqxSgCOAgAAAA==.Mamif:BAAANQAECgYIEQAAAA==.Manfrony:BAAANQADCggICAABNQAECggIHgACALcZAA==.Mannasto:BAAANQADCgYIBgAAAA==.Manuelek:BAAANQAECgEIAQAAAA==.Markatron:BAABNQAECoEbAAMaAAkKEBU7ZQAGAgAaAAgK6BQ7ZQAGAgAhAAEKUhZeagBBAAAAAA==.Mattiekay:BAABNQAECoEfAAMVAAgKhho2OAAfAgAVAAgKhho2OAAfAgAWAAUKSgR7jgCnAAAAAA==.Maxx:BAAANQAECgYJBgAAAA==.Mayberocks:BAAANQAECggIBwABNQAFFAYIEAAgACodAA==.Mañajuana:BAABNQAECoEiAAMSAAgKhxdzEAAaAgASAAgKQhdzEAAaAgAZAAYKohDTXAA1AQAAAA==.',
Mc='Mclaud:BAAANQADCgYIBgAAAA==.',
Me='Meatrocket:BAAANQADCgYIBgABNQAECgkJKAAbAPUjAA==.Meefalo:BAABNQAECoEeAAQaAAgKOBkweQDNAQAaAAYK5xsweQDNAQAhAAIKKxG/VAB2AAAkAAEKRA9aKgA5AAAAAA==.Meganfox:BAAANQAECgcIDQAAAA==.Meggfox:BAAANQADCgQIBAAAAA==.Meghanics:BAAANQAECgYIEQAAAA==.Meileen:BAAANQADCgEIAQAAAA==.Mendwyn:BAAANQABCgUJBQAAAA==.Menethol:BAAANQADCgUIBQABNQAECggIPAAGAHAcAA==.Mercymage:BAAANQAECgMIAwAAAA==.Merie:BAAANQADCgUIBQABNQAECggIGQACAK0ZAA==.Merlinswrath:BAAANQADCgYJBAAAAA==.Merril:BAAANQADCgIIAgABNQAFFAQICAAfAP0SAA==.Merza:BAAANQADCggJDAABNQAFFAMIBwAlABgXAA==.Merzinator:BAACNQAFFIEHAAIlAAMKGBcGCgD+AAAlAAMKGBcGCgD+AAA1AAQKgSkAAyUACQqYIB0JADoDACUACQqYIB0JADoDABAAAgr+C4Z4AFgAAAAA.',
Mi='Mickle:BAAANQAECgYIDwAAAA==.Midev:BAAANQAECgQIBAAAAA==.Midgrad:BAAANQADCggIDgABNQAECgkJHQAZAKINAA==.Mikelowry:BAAANQAECgcIEQAAAA==.Minimum:BAAANQAECgQIBAABNQAECgUIBQAKAAAAAA==.Misae:BAAANQADCgMIAwAAAA==.Mischeveous:BAABNQAECoEWAAIOAAgKwAZS1AA4AQAOAAgKwAZS1AA4AQAAAA==.Missu:BAAANQADCgEJAQAAAA==.Mithrandir:BAABNQAECoEkAAMFAAgKahYJIQDBAAAGAAYKyxZM4wCcAQAFAAMKgBQJIQDBAAAAAA==.',
Mj='Mjiltanke:BAAANQAECgYIEwAAAA==.',
Mo='Moistcarry:BAAANQADCgUIBQAAAA==.Mokniahiah:BAABNQAECoEYAAIJAAgK6htXMQB1AgAJAAgK6htXMQB1AgAAAA==.Moksha:BAAANQADCgMIAwABNQAECgQICwAKAAAAAA==.Monkmates:BAAANQAECgEIAQAAAA==.Moodoon:BAAANQAECgYIDAAAAA==.Moohammadali:BAAANQADCgYJBgAAAA==.Mooseyfate:BAAANQAECgcICwAAAA==.Moraxy:BAAANQAECgYIEgAAAA==.Moromagus:BAABNQAECoErAAIGAAkKCRcEeQB1AgAGAAkKCRcEeQB1AgAAAA==.Mortis:BAAANQAECgcICwAAAA==.Motaro:BAAANQAECgEIAQAAAA==.Motorboats:BAAANQAECgEIAQAAAA==.',
Ms='Mschief:BAAANQADCgQIBAAAAA==.',
Mu='Mualpractice:BAAANQADCgQIBQAAAA==.Murasaki:BAAANQAECgMIBAABNQAECgYICQAKAAAAAA==.Murdok:BAAANQAFFAEIAQAAAA==.Murray:BAAANQAFFAEIAQABNQAFFAYIFQAWAIgMAA==.Mutknodeprac:BAAANQAECgYIEQAAAA==.',
Mx='Mxsery:BAAANQAECgcICQAAAA==.Mxz:BAAANQADCgcIBwABNQAECgkJLgAEAMwdAA==.',
My='Myræl:BAAANQAECgcICwAAAA==.Mystíle:BAACNQAFFIEKAAIVAAQK3x/7CQBKAQAVAAQK3x/7CQBKAQA1AAQKgS8AAhUACQpJJpgEAKEDABUACQpJJpgEAKEDAAAA.Mythrix:BAAANQABCgIIAgABNQADCgcIEQAKAAAAAA==.Mythrixx:BAAANQADCgcIEQAAAA==.',
['Mà']='Màjíque:BAABNQAECoEWAAIEAAcKRgJ+vgDmAAAEAAcKRgJ+vgDmAAAAAA==.',
['Mé']='Méadow:BAAANQAECgIIAgAAAA==.',
['Mô']='Môto:BAAANQADCgcIBwAAAA==.',
['Mö']='Mötley:BAAANQADCggIDQABNQAECgEIAgAKAAAAAA==.',
Na='Nabesan:BAAANQADCgIIAgAAAA==.Naked:BAAANQADCggIBAAAAA==.Nalera:BAAANQAECggIBwAAAA==.Nanoboostme:BAAANQADCggIGAAAAA==.Narhi:BAAANQAECgQICwAAAA==.Nasminthe:BAAANQAECgEIAQAAAA==.Nature:BAAANQADCgUIBQAAAA==.Naughtya:BAAANQAECgQIEAAAAA==.Nay:BAAANQAECgMIAgAAAA==.Nazem:BAAANQAECgUIDwAAAA==.',
Ne='Neikoh:BAAANQAECgQIBQAAAA==.Nekoro:BAABNQAECoEjAAQaAAkKJhrKJgDRAgAaAAkKJhrKJgDRAgAkAAIK4QnOHwBiAAAhAAEKCAU0cQA4AAAAAA==.Nelfsquantch:BAAANQAECgUIDQAAAA==.Nemesis:BAAANQADCggICAAAAA==.Neourth:BAAANQADCgQIBAAAAA==.Nevadawolf:BAAANQAECgYIEQAAAA==.',
Ni='Nightreaver:BAAANQAECgQICQAAAA==.Nightshiftér:BAAANQAECgEIAgAAAA==.Nimbex:BAAANQADCgQIBAAAAA==.Ninetailsfox:BAABNQAECoEhAAIGAAgKaBTqnwAiAgAGAAgKaBTqnwAiAgABNQAECgkJKgAHAAUcAA==.Nion:BAABNQAECoEeAAMNAAgKMwZ5ewBuAQANAAgKMwZ5ewBuAQAMAAEKSAPyfQAfAAAAAA==.Nippy:BAAANQADCggIFgABNQAECgUICgAKAAAAAA==.',
No='Nolo:BAAANQADCgQIBQAAAA==.Northzen:BAABNQAECoEeAAIcAAkKWBxTFACQAgAcAAkKWBxTFACQAgAAAA==.Notaorc:BAAANQADCgUIBQAAAA==.Notmyconcern:BAAANQAECgEIAQAAAA==.Novaflux:BAABNQAECoEeAAIGAAgKwiCNUQDNAgAGAAgKwiCNUQDNAgAAAA==.Noxxicc:BAAANQAECgYIDwABNQAECggIMQAJAFMeAA==.',
Ny='Nyghtterror:BAAANQAECgEIAQAAAA==.Nyreeh:BAAANQAECgUIDAAAAA==.Nyrsa:BAAANQADCgYICwABNQAECgUIDAAKAAAAAA==.Nytearcher:BAABNQAECoEbAAICAAcKqx13SwBkAgACAAcKqx13SwBkAgAAAA==.Nyxa:BAAANQAECgYIDgAAAA==.',
['Ná']='Nálera:BAAANQADCggIDgAAAA==.',
['Nü']='Nüguns:BAAANQAECgUICAAAAA==.',
Ok='Okamifist:BAAANQADCgYIBgAAAA==.Oklyra:BAAANQABCgYICgAAAA==.',
Om='Omnia:BAABNQAECoEiAAMJAAkKFxG0TwD5AQAJAAkKFxG0TwD5AQAEAAcKeQbvkwBCAQABNQADCggICAAKAAAAAA==.Omrath:BAAANQADCgYIBgABNQABCgIIAgAKAAAAAA==.',
On='Onlyshams:BAAANQAECgQIBAAAAA==.',
Oo='Oogiee:BAABNQAECoEgAAIQAAgKNwyIOAC5AQAQAAgKNwyIOAC5AQAAAA==.',
Or='Orcmonk:BAAANQADCggIFQAAAA==.Orega:BAAANQADCgQIBAAAAA==.Orthoganal:BAAANQAECgcIDwAAAA==.',
Os='Oschun:BAABNQAECoEoAAIOAAkKNhyrQgCnAgAOAAkKNhyrQgCnAgAAAA==.',
Pa='Palacandia:BAAANQADCgYIBQAAAA==.Palanar:BAABNQAECoEoAAQVAAkKySRtDwAnAwAVAAgKYiVtDwAnAwAeAAQKASHtRwBVAQAWAAEKACKJpQBjAAAAAA==.Palle:BAABNQAECoEbAAIOAAkKIh1cPgC1AgAOAAkKIh1cPgC1AgAAAA==.Pallyboi:BAAANQAECgUICwAAAA==.Paluru:BAAANQAECgEIAQABNQAECgkJJgAhAK4dAA==.Panosh:BAAANQADCgUIBQAAAA==.Pantricelog:BAAANQADCggICAABNQAECggIJwATAEQYAA==.Parthlore:BAAANQABCgcIEQAAAA==.',
Pc='Pchef:BAAANQAECgQIBgAAAA==.',
Pe='Pelayo:BAAANQAECgQICwAAAA==.Peperoninips:BAAANQAECgUIDAAAAA==.Petricia:BAABNQAECoEnAAITAAgKRBjHGwAtAgATAAgKRBjHGwAtAgAAAA==.',
Pf='Pfeffer:BAAANQAECgYIEQAAAA==.',
Ph='Phaithful:BAACNQAFFIESAAMMAAUK7RUJCABcAQAMAAQKYBkJCABcAQAmAAEKpAgaAwBRAAA1AAQKgSgAAwwACQpLId0MAAYDAAwACQpLId0MAAYDACYABgogDm8NAEcBAAAA.Pharaoh:BAAANQADCgQIBwAAAA==.Phazerman:BAABNQAECoEfAAMmAAgK3gotCgCUAQAmAAgK3gotCgCUAQAMAAIKnRivUwCQAAAAAA==.Phocus:BAAANQAFFAEIAgABNQAFFAUIEgAMAO0VAA==.Phury:BAAANQAECgcIEgABNQAFFAUIEgAMAO0VAA==.',
Pi='Pikapikapika:BAABNQAECoEhAAIEAAgKORlmPgBSAgAEAAgKORlmPgBSAgAAAA==.',
Pl='Planthoofem:BAAANQAECgIIAgAAAA==.Playpride:BAABNQAECoEWAAICAAcKshSmdAD5AQACAAcKshSmdAD5AQAAAA==.',
Po='Poboy:BAAANQAECgcIEQAAAA==.Pocket:BAAANQAECgQICQABNQAECggIHwAaAB0eAA==.Pokepokepoke:BAABNQAECoEWAAIDAAgKKhrUGQCGAgADAAgKKhrUGQCGAgAAAA==.Poppop:BAAANQAECgYIEwAAAA==.Poriand:BAAANQAECgQJBQAAAA==.Portzul:BAAANQAECgEIAQAAAA==.',
Pr='Prawns:BAAANQADCgUIBQAAAA==.Preeze:BAAANQAECggICAAAAA==.Priesttea:BAAANQAECgQIBgAAAA==.Procology:BAAANQAECgEIAQAAAA==.',
Ps='Pseudogrim:BAABNQAECoEYAAIGAAgKvRPAowAaAgAGAAgKvRPAowAaAgAAAA==.Psspspss:BAAANQAECgQIBwAAAA==.',
Pu='Pugno:BAAANQADCggICAAAAA==.Pugnosano:BAAANQADCgQIBAABNQADCggICAAKAAAAAA==.Pussnboots:BAAANQAECgQIEAAAAA==.',
['Pö']='Pöppop:BAAANQAECgEIAQABNQAECgYIEwAKAAAAAA==.',
Qq='Qq:BAAANQAECggIBgAAAA==.',
Ra='Raefe:BAAANQAECgcIEQAAAA==.Raffaj:BAAANQAECgYIEQAAAA==.Raidedww:BAAANQADCgUIBQAAAA==.Raihnese:BAEANQAECgYICgAAAA==.Ramenveg:BAABNQAECoEWAAIcAAcKVQ40MABgAQAcAAcKVQ40MABgAQAAAA==.Rancora:BAABNQAECoEYAAITAAkK0wjRJwCxAQATAAkK0wjRJwCxAQAAAA==.Ravnsifu:BAAANQADCggIDQAAAA==.',
Re='Reapersbless:BAAANQAECgEIAgABNQAECgEIAgAKAAAAAA==.Reapersbount:BAAANQAECgEIAgAAAA==.Reapersele:BAAANQADCgMIAwABNQAECgEIAgAKAAAAAA==.Redbuffpls:BAACNQAFFIELAAIOAAYKfxmVAwAUAgAOAAYKfxmVAwAUAgA1AAQKgSsAAg4ACQr1JY0KAJ4DAA4ACQr1JY0KAJ4DAAAA.Redbul:BAAANQAECgcIEwAAAA==.Redbullz:BAAANQADCgUIBQAAAA==.Reddrock:BAAANQADCggIDwAAAA==.Redstörm:BAAANQADCgcIBwAAAA==.Reffusul:BAAANQADCgMIAwABNQAECgkJJwAWAH4gAA==.Reflexadín:BAAANQADCgcIBwAAAA==.Reilanna:BAAANQAECgcIBwAAAA==.Reklesshealz:BAAANQADCgQIBAAAAA==.Reptilia:BAABNQAECoEnAAIZAAkKXxw5FwD1AgAZAAkKXxw5FwD1AgAAAA==.Rewef:BAAANQAECgQIBQABNQAFFAcIGAAEAFkeAA==.Rex:BAABNQAECoEhAAIGAAkKJSLTHQBYAwAGAAkKJSLTHQBYAwAAAA==.',
Rh='Rhune:BAAANQADCgIIAgAAAA==.',
Ri='Rickylicky:BAAANQADCgIIAgAAAA==.Riffz:BAABNQAECoEoAAMDAAkKkRysFgChAgADAAgKLR2sFgChAgAIAAgKDBIJGAAMAgAAAA==.Rig:BAAANQAECgQIBAAAAA==.Rinzsha:BAABNQAECoEXAAIEAAcKaRdxVgDzAQAEAAcKaRdxVgDzAQAAAA==.Rishka:BAAANQADCgUIBQAAAA==.Riv:BAAANQADCggICAABNQAECgkJHQAZAKINAA==.Rivien:BAABNQAECoEdAAMZAAkKog2kQQDFAQAZAAkKegukQQDFAQASAAMKihT4OACZAAAAAA==.',
Ro='Roostersauce:BAAANQADCgYIBgAAAA==.Rosare:BAAANQADCgEIAQAAAA==.',
Ru='Ruhkouri:BAAANQAECgUIDAAAAA==.Rulez:BAAANQADCgQIBAAAAA==.Rumix:BAAANQADCgMIAwAAAA==.Rustibox:BAACNQAFFIEUAAMaAAcKShXjBQDmAQAaAAYKNhLjBQDmAQAhAAIKfRseBwC1AAA1AAQKgTsAAxoACQoFJWsEAKgDABoACQqhJGsEAKgDACEABAqzFBgnADMBAAAA.',
Sa='Saltdeeduck:BAAANQADCgYICgAAAA==.Samardev:BAAANQADCgYIBgABNQAFFAQICAAfAP0SAA==.Sammichomg:BAABNQAECoEdAAIOAAcKqiE6WgBeAgAOAAcKqiE6WgBeAgAAAA==.Sammyfuego:BAAANQAECgYIEQAAAA==.Sarutko:BAAANQAECgUICAAAAA==.Sazaimes:BAAANQABCgUIBQAAAA==.',
Sc='Scalestas:BAABNQAECoEkAAIbAAgKNxwTDACMAgAbAAgKNxwTDACMAgAAAA==.Scoobies:BAAANQAECgQIBgABNQAFFAEIAQAKAAAAAA==.',
Se='Searing:BAACNQAFFIEGAAIYAAMK2Q+SBwC5AAAYAAMK2Q+SBwC5AAA1AAQKgSAAAxgACQq1GpATAEYCABgACQq1GpATAEYCAA4AAwo3Hcr1APkAAAAA.Segfaulted:BAAANQAECggIDQAAAA==.Seleane:BAABNQAECoEmAAMJAAgK/RR3UgDvAQAJAAgK/RR3UgDvAQAEAAIKBRCd7AB6AAAAAA==.Sellvanya:BAAANQADCgYICQAAAA==.Senyor:BAAANQAECgEIAQABNQAECgQICQAKAAAAAA==.Seraphia:BAAANQADCgQIBAAAAA==.Serrick:BAAANQADCgUIBQABNQAECgkJIQAPAJQeAA==.Sethcure:BAAANQAECgUIBwAAAA==.Sethlore:BAAANQABCggIFAAAAA==.',
Sh='Shaadas:BAABNQAECoElAAINAAgKSxyWNQBwAgANAAgKSxyWNQBwAgAAAA==.Shabazz:BAAANQAECgQICAABNQAECgQICwAKAAAAAA==.Shacklestorm:BAAANQAECgUIBwAAAA==.Shadeau:BAAANQAECgUIDAAAAA==.Shamackerd:BAAANQAECgcICQAAAA==.Shampoo:BAAANQABCgUIBAAAAA==.Shamyy:BAAANQADCgYIBgAAAA==.Shandriss:BAAANQAECgIIAwAAAA==.Shawlen:BAAANQABCgIIAgAAAA==.Sheve:BAAANQADCgQJBAAAAA==.Shmimon:BAAANQAECgcIEAAAAA==.Shockapal:BAAANQAECgUICQAAAA==.Shockvalue:BAAANQAECgEJAQAAAA==.Shortfist:BAAANQAECgIIAgAAAA==.Shrimon:BAAANQADCgIIAgAAAA==.Shrimps:BAABNQAECoEWAAIEAAkKQhoOLACqAgAEAAkKQhoOLACqAgAAAA==.Shâokahn:BAAANQADCgcIEwAAAA==.',
Si='Sicell:BAAANQAECgcIBwAAAA==.Sidewinder:BAAANQAECgYIDgAAAA==.Sillybear:BAAANQAECgIIAwAAAA==.Siong:BAABNQAECoEbAAInAAgKxAbxFgBQAQAnAAgKxAbxFgBQAQAAAA==.Sitch:BAAANQADCgQJBQAAAA==.',
Sk='Skeletorz:BAAANQADCgYIDAAAAA==.Skunknmidget:BAAANQADCggIDgAAAA==.Skyvestris:BAAANQAECgcIEAAAAA==.',
Sl='Slamueladams:BAAANQADCgMIAwAAAA==.Slayberto:BAABNQAECoEiAAInAAgKpxU5DQAIAgAnAAgKpxU5DQAIAgAAAA==.Sleepbringer:BAAANQAECgEIAQAAAA==.Sloppysecond:BAAANQADCgQIBAAAAA==.',
Sm='Smellmygas:BAABNQAECoEjAAINAAYKPRL8eAB2AQANAAYKPRL8eAB2AQAAAA==.Smerge:BAAANQABCgEIAQAAAA==.Smoko:BAABNQAECoEfAAIJAAgK7RibPABEAgAJAAgK7RibPABEAgAAAA==.',
Sn='Sneaky:BAABNQAECoEmAAINAAkKCSAyDgA+AwANAAkKCSAyDgA+AwABNQAECgkJMgASALwmAA==.Sneakyr:BAABNQAECoEyAAISAAkKvCY9AAAIBAASAAkKvCY9AAAIBAAAAA==.Snoodle:BAAANQAECgEIAQAAAA==.Snypar:BAABNQAECoEkAAITAAgKDxQSIAD+AQATAAgKDxQSIAD+AQAAAA==.Snôva:BAABNQAECoEXAAIUAAcKvRbzFgDdAQAUAAcKvRbzFgDdAQAAAA==.',
So='Soaraga:BAAANQABCgQIBAAAAA==.Sodosopa:BAAANQADCgYIBgAAAA==.Solaire:BAAANQAECgYIEQAAAA==.Sole:BAAANQADCgcIBwABNQAECgUJCgAKAAAAAA==.Soleim:BAAANQAECgUJCgAAAA==.Somavanna:BAABNQAECoEWAAMTAAcKlxq9GwAtAgATAAcKlxq9GwAtAgAZAAEK/QxDqAAmAAAAAA==.Sophara:BAAANQAECgUIBwAAAA==.Sorbet:BAABNQAECoEpAAIFAAkKSCV8AADBAwAFAAkKSCV8AADBAwAAAA==.Soulgrinder:BAAANQAECgcIDQAAAA==.',
Sp='Sparden:BAAANQADCggIDQAAAA==.Sparhawk:BAABNQAECoEoAAIOAAkKXSOwDACQAwAOAAkKXSOwDACQAwAAAA==.Sparklebolts:BAAANQADCgQIBAAAAA==.Speedwagon:BAAANQAECgUICwABNQAECgYIDAAKAAAAAA==.Spicyprayers:BAAANQADCgEIAQAAAA==.Spicytotems:BAABNQAECoEhAAIEAAgK+xWZRAA3AgAEAAgK+xWZRAA3AgAAAA==.Spidercowsd:BAAANQADCgIIAgAAAA==.Spippy:BAAANQAECgQIBAAAAA==.Spitzer:BAAANQADCgEIAQAAAA==.Splõõsh:BAABNQAECoExAAMJAAgKUx4mLQCJAgAJAAgKUx4mLQCJAgAEAAQK7xdopAAcAQAAAA==.Spooky:BAAANQADCggIIwABNQAFFAUIEgADAIciAA==.Spro:BAAANQAECgQIBAABNQAECgkJJwAQAAIiAA==.Sprogue:BAABNQAECoEmAAQDAAkK0x+hCgAcAwADAAkK0x+hCgAcAwAXAAYKwBGmDABvAQAIAAEK1Q1KSgA5AAABNQAECgkJJwAQAAIiAA==.Spronatty:BAAANQADCgIIAgAAAA==.Sprosport:BAAANQAECgUIDQABNQAECgkJJwAQAAIiAA==.Sprø:BAAANQAECgEIAQABNQAECgkJJwAQAAIiAA==.Spurlock:BAAANQAECgQIBgAAAA==.Spyrogos:BAAANQAECgYIEQAAAA==.',
Sq='Squidbits:BAAANQAECgQIEAAAAA==.Sqwuanchigos:BAAANQADCggICAAAAA==.',
St='Stabsandhugs:BAAANQADCgQIBAAAAA==.Starclaw:BAABNQAECoEhAAIoAAkKOCT3AQCTAwAoAAkKOCT3AQCTAwAAAA==.Stasis:BAABNQAECoEcAAQLAAcKpwtemgApAQALAAYKJwlemgApAQAOAAYKtgb47gAFAQAYAAMKbg6JSQCbAAAAAA==.Statixx:BAAANQADCgYIBgAAAA==.Stel:BAAANQAECgEIAQAAAA==.Stroonzy:BAAANQAECgUICAAAAA==.Stumbly:BAAANQAECgMIAwAAAA==.Styrmir:BAAANQADCgMIAwAAAA==.',
Su='Sugarteets:BAABNQAECoEYAAIOAAcKdhQmnACzAQAOAAcKdhQmnACzAQAAAA==.Sujung:BAAANQADCgIJAwAAAA==.Sukmymeat:BAAANQADCgcIBAAAAA==.Sukubis:BAAANQADCgUIBQAAAA==.Supadope:BAAANQAECgQIDgAAAA==.Superpaladin:BAAANQAECgQIBwABNQAECgYIEQAKAAAAAA==.',
Sy='Sydner:BAAANQAECgcIEAAAAA==.Synergize:BAAANQADCgMIAwAAAA==.Sythila:BAACNQAFFIEQAAIQAAYKgBBQBQDYAQAQAAYKgBBQBQDYAQA1AAQKgSQAAxAACQr7HoYcAJACABAACQrSHYYcAJACACUABgo+GLoxAI8BAAAA.',
['Sé']='Séamus:BAAANQADCgYIBgAAAA==.',
['Sü']='Süblime:BAAANQAECggICAAAAA==.',
Ta='Tachichan:BAAANQADCgUIBQAAAA==.Tacx:BAAANQAECgEIAQAAAA==.Tadertod:BAAANQAECggIDwAAAA==.Talleth:BAABNQAECoFXAAIbAAkK4CG2AgB4AwAbAAkK4CG2AgB4AwAAAA==.Tallìsh:BAAANQADCgYICgABNQAECgYIEAAKAAAAAA==.Talorion:BAABNQAECoEdAAIPAAgKEBGsgwDuAQAPAAgKEBGsgwDuAQAAAA==.Tandrisell:BAAANQAECgEIAQAAAA==.Tarkyn:BAAANQADCggICAAAAA==.Tassyn:BAABNQAECoEmAAMDAAkKiBaYLgDzAQADAAcKjBWYLgDzAQAIAAcKXxKnHADbAQAAAA==.Tattianna:BAAANQAECgYIEQAAAA==.Tazenezoth:BAACNQAFFIEIAAIfAAQK/RIwCwBAAQAfAAQK/RIwCwBAAQA1AAQKgS0AAh8ACQq+HjwKAPECAB8ACQq+HjwKAPECAAAA.',
Te='Tehmachine:BAABNQAECoEZAAINAAkKAhxHIgDIAgANAAkKAhxHIgDIAgAAAA==.Terpene:BAAANQAECgEIAQAAAA==.Terry:BAABNQAECoEWAAIGAAcKQBYCugDsAQAGAAcKQBYCugDsAQAAAA==.',
Th='Thanyros:BAABNQAECoElAAIWAAgKCSQFDgAvAwAWAAgKCSQFDgAvAwAAAA==.Thanywar:BAABNQAECoEiAAIPAAkKtCLxDgB/AwAPAAkKtCLxDgB/AwAAAA==.Thebrowner:BAAANQAECgIIAgABNQAECgYIDwAKAAAAAA==.Thejuice:BAAANQAECgEIAQAAAA==.Thetrashman:BAAANQAECgYIDwAAAA==.Thoian:BAABNQAECoEcAAMRAAkK3BvsAwDkAgARAAkK3BvsAwDkAgABAAYKRg+NHwAnAQAAAA==.Thork:BAAANQADCgYIBgAAAA==.Thrindy:BAAANQAECgYIBwAAAA==.Thugnificint:BAABNQAECoEqAAMHAAkKBRxZHgBBAgAHAAkKyxVZHgBBAgACAAQKNhnGwwBGAQAAAA==.Thåwn:BAAANQAECgYICAAAAA==.Thèokoles:BAACNQAFFIEFAAIPAAMKhQYdJQCYAAAPAAMKhQYdJQCYAAA1AAQKgScABA8ACQoGFg5bAF4CAA8ACQoGFg5bAF4CAAEABgorCyshABUBABEAAQqmC1AtADYAAAAA.',
Ti='Tiblock:BAABNQAECoExAAIhAAkKQxNkCgBHAgAhAAkKQxNkCgBHAgAAAA==.Tidalsage:BAAANQAECgcIEwAAAA==.Tilolas:BAAANQAECgIIAwAAAA==.Timeskip:BAAANQAECgYIEAAAAA==.Timfinnigut:BAABNQAECoElAAIVAAgKmCPOEQATAwAVAAgKmCPOEQATAwAAAA==.Tinkiewinkie:BAAANQADCggICAAAAA==.Tinx:BAAANQAECgYIDQAAAA==.Tinylego:BAAANQADCggIGwAAAA==.Tinytiran:BAAANQAECgYIEAAAAA==.',
To='Tonktotem:BAEANQADCgEIAQABNQAECggIGQAaAK8XAA==.Toptearcryer:BAABNQAECoEiAAIPAAgK/hlmYABOAgAPAAgK/hlmYABOAgAAAA==.Tortilla:BAAANQAECgYIDAAAAA==.Toryn:BAAANQADCgYICgABNQADCggICAAKAAAAAA==.',
Tr='Trailwalker:BAAANQAECgcIEgAAAA==.Trashypally:BAAANQAECgEIAgAAAA==.Trecks:BAAANQADCggIHAAAAA==.Treelonmüsk:BAAANQAECgYIDAAAAA==.Treesumm:BAAANQAECgYIEgAAAA==.Trickyrickyy:BAAANQAECgUICgAAAA==.Triptix:BAAANQADCggIEQAAAA==.Truthbringer:BAAANQADCgQIBAAAAA==.Trynitie:BAAANQAECgYIEAAAAA==.',
Tu='Turlane:BAABNQAECoEcAAIOAAgKeAvlqQCTAQAOAAgKeAvlqQCTAQAAAA==.',
Tw='Twinkslayer:BAAANQADCgYIDgABNQAECgkJHAAaAPgbAA==.Twinkugly:BAAANQABCgcIDwAAAA==.',
Ty='Tyberia:BAAANQAECgUICgAAAA==.Tychó:BAABNQAECoEWAAIPAAgKMhtcWQBiAgAPAAgKMhtcWQBiAgAAAA==.Tyeret:BAABNQAECoEZAAMOAAkKqRaUbQAnAgAOAAkKEBWUbQAnAgAYAAEKgCXPUQBsAAAAAA==.Tyet:BAAANQAECgYIBAABNQAECgkJGQAOAKkWAA==.',
['Tø']='Tørvald:BAAANQAECgQIEgAAAA==.',
Uc='Uccisore:BAAANQADCgcIEwAAAA==.',
Un='Unbeliever:BAAANQABCgYICgAAAA==.',
Us='Uslurper:BAABNQAECoErAAQOAAkK8xsARwCaAgAOAAkKdhsARwCaAgAYAAkKzBLaGwDjAQALAAEKPAf3BQE1AAAAAA==.',
Va='Vaalak:BAAANQAECgEIAQAAAA==.Valrosh:BAAANQAECgIIAwAAAA==.Varenar:BAABNQAECoEiAAIlAAgKcRhpHgBBAgAlAAgKcRhpHgBBAgAAAA==.Varpuff:BAAANQADCgYIBgABNQAECgkJGwAaABAVAA==.',
Ve='Vearn:BAAANQADCgMIAwABNQADCggIEAAKAAAAAA==.Velkorn:BAAANQADCgYIBwAAAA==.Vellamo:BAAANQADCgMIBQAAAA==.Vengeful:BAAANQADCggJGwAAAA==.Venuveus:BAAANQAECgYIEwAAAA==.Verdan:BAABNQAECoEgAAIoAAgKVBoaCQCIAgAoAAgKVBoaCQCIAgAAAA==.',
Vi='Viperion:BAAANQADCgMIAwAAAA==.Virlomi:BAACNQAFFIEKAAITAAQKbxNdBwBVAQATAAQKbxNdBwBVAQA1AAQKgTEAAhMACQq5IbcHADMDABMACQq5IbcHADMDAAAA.Viyya:BAAANQADCgYIBgAAAA==.',
Vl='Vlix:BAAANQADCgMIAwAAAA==.',
Vo='Vowz:BAAANQADCgYICgAAAA==.',
Vu='Vurttotems:BAAANQAECgQIBAABNQAECgYIDQAKAAAAAA==.',
Vy='Vynx:BAAANQAECgYIEQAAAA==.Vyrogash:BAAANQADCgMIAwAAAA==.Vysceral:BAAANQADCgUIBQAAAA==.Vythica:BAAANQAECggIEwAAAA==.',
Wa='Wakoguyc:BAAANQAECgQIBwAAAA==.Wargodd:BAAANQAECggIBQABNQAECgkJGQAOAKkWAA==.',
We='Weierstraß:BAABNQAECoElAAICAAgKhxR/XgAxAgACAAgKhxR/XgAxAgAAAA==.Welari:BAABNQAECoEiAAIOAAgKOyGyOwC/AgAOAAgKOyGyOwC/AgAAAA==.Weskerx:BAAANQAECgcIDgAAAA==.',
Wh='Whindd:BAAANQAECgEIAQAAAA==.Whurstresort:BAABNQAECoEgAAIlAAgKKyHBDQD7AgAlAAgKKyHBDQD7AgAAAA==.Whurstrong:BAAANQADCgEIAQABNQAECggIIAAlACshAA==.Whurstyx:BAAANQAECgUIBQAAAA==.',
Wi='Wickedsoul:BAAANQADCggICAAAAA==.Widowmaker:BAAANQAECgQIBwAAAA==.Wif:BAAANQAECgMIBAAAAA==.Wingmancole:BAAANQADCgQIBAAAAA==.Withers:BAAANQADCgYIBgABNQAECgkJIQAPAJQeAA==.',
Wo='Wondrball:BAABNQAECoEfAAMgAAgKHhARDgA6AQAbAAYKfQ4DHgBUAQAgAAYK9g0RDgA6AQAAAA==.Wonode:BAAANQAECgIIAgAAAA==.Worgen:BAAANQAECgcIEgAAAA==.Worthless:BAAANQAECgMIAwAAAA==.',
Xa='Xago:BAAANQADCgUJBQAAAA==.Xalvelora:BAAANQADCgYICQAAAA==.Xanderia:BAAANQAECgYIEgAAAA==.Xandil:BAAANQADCggICAAAAA==.Xanius:BAAANQADCgMIAwAAAA==.',
Xe='Xeralath:BAABNQAECoEgAAIaAAgKwAc+mAB5AQAaAAgKwAc+mAB5AQAAAA==.',
Xv='Xvibe:BAAANQAECgUIDAAAAA==.',
Xy='Xyphira:BAAANQAECgQICAAAAA==.',
['Xý']='Xý:BAAANQADCgcIHwAAAA==.',
Ya='Yaboo:BAAANQAECgEIAQAAAA==.Yaen:BAAANQADCgcIDAAAAA==.',
Ye='Yehvenâh:BAABNQAECoEbAAIPAAcK4x7eWABkAgAPAAcK4x7eWABkAgAAAA==.Yeska:BAAANQADCgQIBAAAAA==.',
Yo='Yootle:BAABNQAECoEgAAITAAgK/xkEFgBwAgATAAgK/xkEFgBwAgAAAA==.Youngcheese:BAAANQADCgcIBwAAAA==.Yourgothgf:BAEBNQAECoEZAAMaAAgKrxcGUABEAgAaAAgKrxcGUABEAgAhAAEKhRYlaABEAAAAAA==.Yovanna:BAAANQADCgYIBAABNQAECggICAAKAAAAAA==.',
Yu='Yummyx:BAAANQAECgEIAQAAAA==.',
Za='Zallo:BAABNQAECoEeAAISAAgKzyO2BAAzAwASAAgKzyO2BAAzAwAAAA==.Zaloria:BAAANQAECgQIBwAAAA==.Zaqws:BAAANQADCggIDAAAAA==.Zarth:BAAANQADCgIIAgAAAA==.Zava:BAAANQAECgQIEgAAAA==.Zaxon:BAAANQADCggIDAABNQADCggICAAKAAAAAA==.',
Ze='Zeelos:BAABNQAECoEUAAICAAgKuBSKXwAuAgACAAgKuBSKXwAuAgAAAA==.Zembu:BAAANQADCgQIBAAAAA==.Zephhyr:BAABNQAECoEhAAIPAAkKlB6IJAAXAwAPAAkKlB6IJAAXAwAAAA==.Zephyr:BAAANQAECgYICgAAAA==.Zeñor:BAAANQAECgQICQAAAA==.',
Zh='Zharek:BAAANQADCggIFgAAAA==.Zhax:BAAANQABCgMIAwAAAA==.',
Zi='Zireael:BAABNQAECoEeAAIiAAgK7B8+BADfAgAiAAgK7B8+BADfAgAAAA==.',
Zo='Zornox:BAAANQADCgYIEQAAAA==.',
['Óp']='Óprawïndfury:BAAANQAECgYIDAAAAA==.',
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
