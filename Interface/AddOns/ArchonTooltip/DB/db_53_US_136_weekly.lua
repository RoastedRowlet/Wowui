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

local lookup = {'Warrior-Protection','Rogue-Assassination','Shaman-Elemental','Mage-Frost','Mage-Arcane','Hunter-Marksmanship','Rogue-Subtlety','Shaman-Restoration','Unknown-Unknown','Paladin-Holy','Priest-Holy','Hunter-BeastMastery','Paladin-Retribution','Warrior-Arms','DemonHunter-Havoc','Priest-Shadow','Druid-Guardian','DeathKnight-Unholy','Rogue-Outlaw','Druid-Balance','Druid-Restoration','Warlock-Demonology','Evoker-Devastation','Mage-Fire','DeathKnight-Blood','Paladin-Protection','DeathKnight-Frost','Evoker-Preservation','Evoker-Augmentation','Warlock-Destruction','DemonHunter-Vengeance','Monk-Windwalker','Shaman-Enhancement','Warrior-Fury','Warlock-Affliction','Monk-Mistweaver','DemonHunter-Devourer','Priest-Discipline','Monk-Brewmaster','Druid-Feral',}
local provider = {region='US',realm='Korgath',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abbygrace:BAAANQAECgUIBgAAAA==.Abcdemon:BAAANQAECgIIAgABNQAFFAQICQABAPsRAA==.',
Ad='Adar:BAAANQAECgUIDgAAAA==.',
Ae='Aegeis:BAAANQAECgEIAQABNQAECggIFgACAPoTAA==.Aelaryn:BAAANQAECgYICQAAAA==.Aeonffx:BAAANQAECgIIAgAAAA==.',
Af='Afterearth:BAACNQAFFIEMAAIDAAUKfyANBQDYAQADAAUKfyANBQDYAQA1AAQKgSAAAgMACQrTJDUIAJQDAAMACQrTJDUIAJQDAAAA.',
Ag='Aggrobeast:BAAANQAECgYIDgAAAA==.Agoný:BAAANQADCgQIBAAAAA==.',
Ai='Ailie:BAABNQAECoEZAAMEAAgKNx16BgBPAgAEAAgKNx16BgBPAgAFAAMKrw4kXAGaAAAAAA==.',
Ak='Akadey:BAAANQADCgYICAAAAA==.',
Al='Aliì:BAAANQAECgcIEwABNQAECgkJHgAGAFYdAA==.Allise:BAAANQAECgMIBAAAAA==.Allnightlong:BAAANQAECgQJBAABNQAECggIGQAHAG0RAA==.Allnightløng:BAABNQAECoEZAAIHAAgKbRFqFQAWAgAHAAgKbRFqFQAWAgAAAA==.Alphonos:BAAANQADCgMJAwAAAA==.Alverez:BAABNQAECoE2AAIIAAkKuiDUCwBAAwAIAAkKuiDUCwBAAwAAAA==.',
Am='Amorilas:BAAANQAECgYIEQAAAA==.Amunera:BAAANQADCgYIEAABNQAECgEIAQAJAAAAAA==.Amàrok:BAAANQADCgUICgABNQADCggIGwAJAAAAAA==.',
An='Andersan:BAABNQAECoErAAIKAAgKwBLTRwAFAgAKAAgKwBLTRwAFAgAAAA==.Anetharion:BAAANQAECgEIAQAAAA==.Animalchange:BAAANQAECgQIEQAAAA==.Anklelock:BAAANQADCgQIBAAAAA==.',
Ap='Apeth:BAAANQADCgEIAQAAAA==.Applepi:BAAANQAECgcIEQAAAA==.Aproditee:BAAANQADCgMIBAAAAA==.',
Ar='Areayl:BAABNQAECoEXAAILAAgKYRh0OgA4AgALAAgKYRh0OgA4AgAAAA==.Arinn:BAABNQAECoEeAAMGAAkKVh2cHwAVAgAGAAgKmxecHwAVAgAMAAcK2RiydgDFAQAAAA==.',
As='Ashtkal:BAABNQAECoEfAAMKAAkK2CCUCgBWAwAKAAkK2CCUCgBWAwANAAEKPRRWPwE9AAAAAA==.Ashtoes:BAABNQAECoEWAAIMAAgKFRGDUgApAgAMAAgKFRGDUgApAgAAAA==.Astralbubble:BAABNQAECoEdAAIKAAkKdxyrFgD4AgAKAAkKdxyrFgD4AgAAAA==.',
Au='August:BAAANQADCggIEAAAAA==.Auratic:BAAANQADCgcIBwAAAA==.Automation:BAAANQAECgIIAgABNQAECgkJHgAFAOkiAA==.',
Av='Avalea:BAAANQADCgUIBwAAAA==.Avaleir:BAAANQAECgEIAQAAAA==.',
Ay='Ayahuascå:BAABNQAECoEZAAIDAAkKvQDz9AA6AAADAAkKvQDz9AA6AAAAAA==.Ayyvlaad:BAAANQAECgUIDAAAAA==.',
Az='Azerlite:BAAANQAECgIIAgABNQAECgkJKwADAMwdAA==.Azkota:BAABNQAECoEXAAIIAAcKwRdITQDeAQAIAAcKwRdITQDeAQAAAA==.Azulwall:BAAANQAECgUICQAAAA==.Azureros:BAABNQAECoEbAAIMAAgKyBpYNQCIAgAMAAgKyBpYNQCIAgAAAA==.',
Ba='Bandaayd:BAAANQAECgEIAQAAAA==.Bargaug:BAAANQADCgYJBgABNQAECggIGwAOANEfAA==.Bathasar:BAAANQAECgUJCAAAAA==.Bathpally:BAAANQAECgUIEAAAAA==.',
Be='Beandh:BAAANQADCggIEAABNQAFFAUICwAPAOYJAA==.Beanygene:BAAANQAECgUIBQAAAA==.Bearwithme:BAAANQADCgYIBgAAAA==.Beastfury:BAABNQAECoEYAAIGAAgKjhz0EwCVAgAGAAgKjhz0EwCVAgAAAA==.Beefyclap:BAAANQAECgQIEAAAAA==.Begal:BAABNQAFFIEHAAMQAAQKewPvCgDSAAAQAAMKggTvCgDSAAALAAEKNwbrJgBLAAAAAA==.Beha:BAAANQADCgEIAQAAAA==.Beleria:BAAANQADCgMIAwAAAA==.Bellaidd:BAABNQAECoEVAAIRAAgKgw73FgB1AQARAAgKgw73FgB1AQAAAA==.Bellore:BAAANQADCgQIBAAAAA==.Benedîct:BAAANQAECgYIBgAAAA==.Bewblywoobly:BAAANQAECgUIEwAAAA==.Bezvoker:BAAANQADCgUIBQAAAA==.Beástboy:BAAANQAECgcIEwAAAA==.',
Bi='Biekdafreak:BAAANQAECgYIBgAAAA==.Bigbackmoto:BAAANQADCgMIAwAAAA==.Bigblade:BAAANQADCgIIAwAAAA==.Bigbuffalo:BAAANQADCgYJCQAAAA==.Bigdaddoo:BAAANQADCgUIBQAAAA==.Biggbob:BAAANQADCgYIBgAAAA==.Biggisign:BAAANQAECgcIEAAAAA==.Bina:BAAANQADCggICAAAAA==.Bingberries:BAAANQADCgQIBQAAAA==.Bitemenow:BAAANQAECgUIBwAAAA==.Bitsobacon:BAAANQAECgcIDwAAAA==.Bizzó:BAAANQAECgEIAQAAAA==.',
Bl='Bladeboy:BAAANQABCgIIAgAAAA==.Blamblam:BAAANQAECgYIBgAAAA==.Blambussi:BAAANQADCgcIEgAAAA==.Blckbeard:BAAANQADCgIIAgAAAA==.Blitzball:BAAANQAECgEIAQAAAA==.Blooddragoon:BAAANQAECgYIDwAAAA==.Bloodycrow:BAAANQABCgMIAwAAAA==.Bluestas:BAAANQABCgIIAgAAAA==.',
Bo='Bohica:BAABNQAECoEbAAISAAgKqBTlMwD8AQASAAgKqBTlMwD8AQAAAA==.Bombadil:BAAANQAECgQIBgAAAA==.Bomberdeath:BAAANQAECgYIEAAAAA==.Bomberpally:BAAANQADCgMIAwAAAA==.Bongrip:BAAANQAECggIBQAAAA==.Boochstorm:BAAANQADCggIDAAAAA==.Boogiee:BAAANQAECgQIBwABNQAECggIGgAPAA8KAA==.Boons:BAAANQAECgMIBQABNQAECggIIQATAC0jAA==.Boosh:BAAANQADCgYICAAAAA==.Boostednub:BAAANQABCgYIDAAAAA==.',
Br='Bradington:BAAANQAECgUIDAAAAA==.Brezel:BAAANQADCgYIBgAAAA==.Briko:BAAANQABCgEIAQABNQAECgEIAQAJAAAAAA==.Brond:BAAANQABCgIIAgAAAA==.Brontide:BAAANQAECgYIEAAAAA==.Browley:BAAANQAECgcIBwAAAA==.Bruengar:BAABNQAECoEeAAINAAgKzRpeSwBkAgANAAgKzRpeSwBkAgAAAA==.Bruniik:BAAANQAECgcIEAAAAA==.',
Bu='Bubblehêarth:BAAANQAECgQICAAAAA==.Budapest:BAABNQAECoEcAAIKAAkKnBffHwDAAgAKAAkKnBffHwDAAgAAAA==.Buddyolpal:BAAANQAECgYIDQAAAA==.Bumbleh:BAAANQAECgQICAAAAA==.Bumibe:BAAANQADCgcIBwAAAA==.Bungulator:BAABNQAECoErAAIDAAkKzB1fGAANAwADAAkKzB1fGAANAwAAAA==.Buné:BAABNQAECoEhAAITAAgKLSM0AgAhAwATAAgKLSM0AgAhAwAAAA==.Butkus:BAAANQAECgEIAQABNQAECgQICAAJAAAAAA==.',
Ca='Caad:BAAANQAECgUICAAAAA==.Caddk:BAAANQAECgEIAQAAAA==.Cador:BAAANQAECgUIDAAAAA==.Cadwarr:BAAANQADCgYIBgAAAA==.Cak:BAAANQADCgUICgABNQAECgUICAAJAAAAAA==.Cam:BAAANQAECgMIBQAAAQ==.Camazotz:BAAANQADCgMIAgAAAA==.Cannibubz:BAAANQAECgMIBgAAAA==.Cannimal:BAABNQAECoEcAAIUAAkKHB9oEwAHAwAUAAkKHB9oEwAHAwAAAA==.Cannish:BAAANQAECgEIAQAAAA==.Cataylst:BAAANQAECgIIAwAAAA==.Catwilliams:BAABNQAECoEjAAIVAAkKTiCRBABeAwAVAAkKTiCRBABeAwAAAA==.',
Ce='Celestas:BAAANQADCgIIAgAAAA==.',
Ch='Cheeze:BAAANQADCgcICwAAAA==.Chiliwop:BAABNQAECoEcAAIWAAgK4xpzMACMAgAWAAgK4xpzMACMAgAAAA==.Chippydk:BAAANQAECggICAAAAA==.Chippyh:BAABNQAECoEfAAMMAAcKwh+rPQBqAgAMAAcKwh+rPQBqAgAGAAIKVQ/oWwBnAAAAAA==.Chippym:BAAANQADCgQIBAAAAA==.Chloei:BAAANQAFFAEIAQAAAA==.Chulkma:BAAANQABCgEIAQAAAA==.Chwonk:BAAANQAECgUICQAAAA==.',
Ci='Cik:BAAANQABCgQIBAAAAA==.Circê:BAAANQAECgEIBAAAAA==.Cirin:BAAANQAECgMIBAAAAA==.',
Cl='Cleaved:BAAANQAECgUIBgAAAA==.Cleppy:BAAANQAECgUIBQAAAA==.Clevoker:BAABNQAECoEiAAIXAAkKWiKfAgByAwAXAAkKWiKfAgByAwAAAA==.Cloacussy:BAAANQADCgYIBgAAAA==.Cloudystorm:BAAANQAECgQIBQABNQAFFAUICwANAJkfAA==.Clusion:BAAANQAFFAIIAgAAAA==.',
Co='Codex:BAABNQAECoEXAAIFAAcKhhlumwAFAgAFAAcKhhlumwAFAgAAAA==.Cole:BAAANQADCggIDAAAAA==.Conanb:BAAANQADCggICAAAAA==.Conductor:BAABNQAECoEnAAIYAAgKSh+6AAABAwAYAAgKSh+6AAABAwAAAA==.Convergent:BAABNQAECoEaAAMZAAkK3RPGMgADAgAZAAgKEBXGMgADAgASAAEKRwoAAAAAAAAAAA==.Coosh:BAACNQAFFIEMAAIFAAUKJxyLDADJAQAFAAUKJxyLDADJAQA1AAQKgSQAAgUACQqkItsTAHQDAAUACQqkItsTAHQDAAAA.Cornydog:BAAANQADCgEIAQAAAA==.Corov:BAAANQAECgQIBQAAAA==.Courigon:BAAANQAECgEIAQAAAA==.Cowish:BAAANQAECgMIAwAAAA==.',
Cp='Cptamerica:BAABNQAECoEaAAIKAAkKux0+EAAmAwAKAAkKux0+EAAmAwAAAA==.',
Cr='Craigolas:BAAANQAECgUICgAAAA==.Crippler:BAAANQAECgYICwAAAA==.Cromewell:BAAANQADCgQIBQAAAA==.Crossbow:BAAANQADCgMIBwAAAA==.Crosscut:BAAANQAECgEIAQAAAA==.Cruelty:BAAANQAECgMIAwAAAA==.Cröw:BAAANQABCgMIAwABNQABCgYICAAJAAAAAA==.',
Cu='Cummins:BAABNQAECoEkAAIVAAkKax81CgDwAgAVAAkKax81CgDwAgAAAA==.Currents:BAAANQADCggICAAAAA==.',
Cy='Cymaig:BAAANQADCgIIAgAAAA==.',
Da='Dadstealer:BAAANQAECgQICQAAAA==.Daemonwing:BAAANQADCgcICgAAAA==.Dagrundel:BAAANQAECgcIEAAAAA==.Dalinarix:BAAANQAECgYICQAAAA==.Dangens:BAAANQAECgUIBQAAAA==.Dankpope:BAAANQAECgIIAgAAAA==.Darkballs:BAAANQAECgIIAgABNQAECgQIBgAJAAAAAA==.Dasbink:BAAANQADCgYIBgAAAA==.Davrin:BAABNQAECoEhAAQNAAgKSR9XMADJAgANAAgKSR9XMADJAgAaAAYKaBZ/JABhAQAKAAMKCAkexgCbAAAAAA==.',
De='Deathbyarow:BAAANQAECgUIDwAAAA==.Deathhammer:BAAANQAECgYIDwAAAA==.Deathjrak:BAABNQAECoEaAAIZAAcKMh64KQA7AgAZAAcKMh64KQA7AgAAAA==.Deesixxfour:BAAANQADCgUIBQABNQAECgkJHgAOAOYjAA==.Degates:BAAANQAECgIIAgAAAA==.Deldor:BAAANQABCggICAAAAA==.Demonia:BAAANQAECgQIBgAAAA==.Demonicshoes:BAAANQAECgUICAAAAA==.Dethwing:BAABNQAECoEcAAMbAAgKmxGoPQBfAQAbAAYKshCoPQBfAQASAAYKig9WVwBNAQAAAA==.Devaña:BAAANQAECgcIEAAAAA==.',
Di='Diclonius:BAAANQAECgYIDQAAAA==.Dieclonius:BAAANQADCgMIAwAAAA==.Dildas:BAAANQADCgYIBgAAAA==.Dirtystaff:BAAANQAECgQIBwAAAA==.Dirtzmage:BAAANQAECgUIEAAAAA==.Dirtzz:BAAANQADCgQIBAAAAA==.Dizzledh:BAAANQAECgYIDQAAAA==.Dizzranger:BAAANQAECgUIBQAAAA==.Dizzsteel:BAAANQAECgEIAQABNQAECgUIBQAJAAAAAA==.',
Dj='Djkhaledd:BAABNQAECoEWAAIDAAgK0B+AHgDiAgADAAgK0B+AHgDiAgAAAA==.',
Do='Doobins:BAAANQAECgUICgAAAA==.Dookiboy:BAAANQADCggJDgABNQAECgkJHQAGAOIZAA==.Doomedstar:BAAANQADCgEIAQABNQAECggIJwAYAEofAA==.Dooy:BAAANQAECgUICgAAAA==.Douii:BAAANQADCggICAAAAA==.',
Dr='Draco:BAAANQABCgQICAAAAA==.Draconir:BAAANQABCgYICAAAAA==.Dragao:BAAANQADCgYIBgAAAA==.Draggen:BAABNQAECoEUAAIXAAYKFx7/EgDeAQAXAAYKFx7/EgDeAQAAAA==.Dragimal:BAAANQAECgQICAAAAA==.Dragonn:BAAANQAECgQICAAAAA==.Dragonoied:BAAANQADCgMIAwAAAA==.Dragonxlord:BAAANQAECgUICAAAAA==.Dragosia:BAABNQAECoE1AAQcAAkKBA/7FgATAgAcAAkKBA/7FgATAgAdAAIKTRHMFwBlAAAXAAEKXgbqNAAxAAAAAA==.Drakojangens:BAABNQAECoEZAAIcAAgKPR5NCwDLAgAcAAgKPR5NCwDLAgAAAA==.Drakthar:BAAANQADCggIFAAAAA==.Dranoric:BAAANQADCggIDAABNQAECgkJHQAOAOsXAA==.Dreebus:BAAANQADCgYIBgABNQAECggIIQAZAJMLAA==.Drev:BAAANQADCgYICwAAAA==.Drlawyerphd:BAABNQAECoEaAAIHAAcKGxgGFgAPAgAHAAcKGxgGFgAPAgAAAA==.Druidijrak:BAAANQADCgIIAgAAAA==.Druini:BAAANQABCgYICAAAAA==.Druz:BAAANQAECgYIDAAAAA==.',
Ds='Dsixfoour:BAAANQAECgEJAQABNQAECgkJHgAOAOYjAA==.Dsixxfour:BAABNQAECoEeAAIOAAkK5iMqEgBdAwAOAAkK5iMqEgBdAwAAAA==.',
Du='Dumdumdugan:BAAANQABCgQIBgABNQADCggICAAJAAAAAA==.Duncedivh:BAAANQADCggIGAAAAA==.Dunzjan:BAABNQAECoEYAAMeAAcKUxxZIABZAQAeAAQKAB1ZIABZAQAWAAMKbRvnwADnAAAAAA==.Durrinn:BAAANQADCgcIBwABNQAECggIHQAEAFgWAA==.',
Dy='Dysmai:BAAANQADCgYICwAAAA==.',
['Dé']='Déathwolf:BAABNQAECoEeAAISAAgKjgsSSQCMAQASAAgKjgsSSQCMAQAAAA==.',
['Dø']='Døminic:BAAANQAECgQIBAAAAA==.',
Ea='Eatsammich:BAAANQADCggIEQAAAA==.',
Eg='Eggsbenedïct:BAABNQAECoEWAAIGAAkK3RAYIAAQAgAGAAkK3RAYIAAQAgAAAA==.Egol:BAABNQAECoEeAAMVAAkKIyPgBgAtAwAVAAgKESPgBgAtAwAUAAEKHBmajQA+AAAAAA==.',
El='Eldonra:BAAANQADCgYIBgABNQAFFAUICwAOAGoQAA==.Elidrine:BAAANQAECgQIBAAAAA==.Elmerfuddz:BAABNQAECoEYAAMMAAgK4AhVbwDYAQAMAAgK4AhVbwDYAQAGAAYKegJoQwDUAAAAAA==.Elyrayldin:BAAANQAECgUICgAAAA==.',
En='Enazenoth:BAABNQAECoEYAAIXAAkKFCL5BAAlAwAXAAkKFCL5BAAlAwAAAA==.Endymíon:BAAANQAECggICAABNQAECgkJJAAfAOUOAA==.Enryu:BAAANQAECgcIDQAAAA==.Envburnz:BAAANQAECgQJBAAAAA==.',
Er='Erooka:BAABNQAECoEiAAIFAAgKLR/QRQDVAgAFAAgKLR/QRQDVAgAAAA==.',
Es='Esio:BAABNQAECoEcAAIOAAgKfRE9fADRAQAOAAgKfRE9fADRAQAAAA==.',
Ev='Evileyes:BAAANQADCgUIBQABNQADCggJCAAJAAAAAA==.',
Ey='Eyri:BAABNQAECoEhAAIFAAgKGRA7mgAHAgAFAAgKGRA7mgAHAgAAAA==.',
Ez='Ezzie:BAAANQAECgYIDQAAAA==.',
Fa='Falsodew:BAABNQAECoEaAAIIAAkKPhhwOAA2AgAIAAkKPhhwOAA2AgAAAA==.',
Fe='Felicity:BAAANQAECgYIEwAAAA==.Femme:BAAANQAECgIJAgAAAA==.Femmever:BAAANQAECgEIAQAAAA==.Feonix:BAABNQAECoEiAAIFAAkKPx01NQACAwAFAAkKPx01NQACAwAAAA==.Ferenus:BAAANQABCggICgAAAA==.Fewsha:BAACNQAFFIEYAAIDAAcKWR7+AACeAgADAAcKWR7+AACeAgA1AAQKgSMAAgMACQrnJN0IAI4DAAMACQrnJN0IAI4DAAAA.',
Fi='Fidellia:BAAANQAECgUIDAAAAA==.Findie:BAAANQAECgUICQAAAA==.',
Fl='Fleshoflìght:BAAANQADCgIJAgAAAA==.',
Fo='Foofoolala:BAAANQADCgYIFAAAAA==.Fookadk:BAAANQADCggJGQAAAA==.Fookapalli:BAAANQABCgYICgAAAA==.Forttoo:BAAANQADCgEIAQAAAA==.Fourthwing:BAAANQADCgQIBAAAAA==.',
Fr='Frawstbyte:BAABNQAECoEiAAIFAAkKHhkfVgCqAgAFAAkKHhkfVgCqAgAAAA==.Fredbearr:BAAANQADCgMIAwAAAA==.Freeholed:BAABNQAECoEdAAISAAkK6RyTFwDFAgASAAkK6RyTFwDFAgAAAA==.Fridgefister:BAAANQAECgcIDwAAAA==.Frodie:BAAANQAECggIDwAAAA==.',
Fu='Fumina:BAAANQAECgUIBgAAAA==.',
['Fæ']='Fælmyhæl:BAAANQADCgQIBAAAAA==.',
Ga='Gaea:BAABNQAECoEXAAIMAAcK9RnzUAAuAgAMAAcK9RnzUAAuAgAAAA==.Gallanon:BAAANQADCgcIDwAAAA==.Gallshot:BAAANQADCgUIDQAAAA==.Galuciene:BAAANQABCgIIAgAAAA==.Gamergirl:BAAANQABCgcIBwAAAA==.Gangrêl:BAAANQADCgYIDAABNQAECgEIAQAJAAAAAA==.Garithor:BAAANQADCgYICwAAAA==.',
Gb='Gbang:BAAANQAECgIIAwAAAA==.',
Ge='Gekidoryu:BAAANQADCgQIBAABNQAECgYIBgAJAAAAAA==.Gerebert:BAAANQAECgYIDwAAAA==.Getajobubum:BAABNQAECoEaAAIDAAgKMxSCRAAWAgADAAgKMxSCRAAWAgAAAA==.',
Gh='Ghalizor:BAAANQADCgYIBgABNQAECgUICAAJAAAAAA==.Ghostdance:BAACNQAFFIEMAAIFAAUKFB+lCwDUAQAFAAUKFB+lCwDUAQA1AAQKgSMAAgUACQoKJYcLAJ0DAAUACQoKJYcLAJ0DAAAA.Ghoulia:BAAANQADCggIIgAAAA==.',
Gi='Giggz:BAAANQAECgYIDAAAAA==.Gilgapally:BAAANQAECgUIBQAAAA==.Gingerpala:BAAANQADCgQJBwAAAA==.Giuttrix:BAAANQAECgUICQAAAA==.',
Gl='Glacie:BAAANQAECgEIAgAAAA==.Gleams:BAAANQAECgQICwAAAA==.Gloriousdead:BAAANQADCgYIBgAAAA==.Glowing:BAAANQAECgUICgAAAA==.',
Go='Gokukakarot:BAAANQAECgQICgAAAA==.Goldeneyes:BAAANQADCgMIAwAAAA==.Goldlore:BAAANQAECgQIBgAAAA==.Gonger:BAAANQAECgUICQAAAA==.Goopdk:BAAANQAECgQJCQABNQAECgYIBgAJAAAAAA==.Gosiâ:BAAANQAECgUICQABNQAECgkJNQAcAAQPAA==.Gothikia:BAAANQAECgUICgAAAA==.',
Gr='Gremhunt:BAAANQAECgIIAgAAAA==.Grondel:BAAANQAECgYICAAAAA==.Grummish:BAAANQADCgQIBAAAAA==.Grumpybear:BAAANQADCgcIDwAAAA==.',
Gu='Gundham:BAAANQAECgQIBgAAAA==.Gunko:BAAANQAECgQIBwAAAA==.Gunstrong:BAAANQAECgQJBgAAAA==.',
['Gõ']='Gõsia:BAAANQAECgQIBAAAAA==.',
['Gø']='Gøtt:BAAANQADCgIIAgAAAA==.',
Ha='Haagendots:BAAANQAECgYIDQAAAA==.Hadokens:BAAANQAECgEIAQAAAA==.Hairofwar:BAABNQAECoEeAAIBAAgKnh+PBQDaAgABAAgKnh+PBQDaAgAAAA==.Haleynicole:BAAANQAECgYIDQAAAA==.Happydaug:BAAANQADCgcICwABNQAFFAMIBgAgAOESAA==.Happydawg:BAACNQAFFIEGAAIgAAMK4RL8BwDkAAAgAAMK4RL8BwDkAAA1AAQKgSUAAiAACQoWJL0CAJ0DACAACQoWJL0CAJ0DAAAA.Hasted:BAABNQAECoEeAAIFAAkK6SIFGwBXAwAFAAkK6SIFGwBXAwAAAA==.Hawktar:BAABNQAECoEYAAIGAAgKThg0HQAuAgAGAAgKThg0HQAuAgAAAA==.',
He='Healimus:BAABNQAECoEeAAIKAAgKGQ2IVgDOAQAKAAgKGQ2IVgDOAQAAAA==.Healmates:BAAANQAECgYICQAAAA==.Helix:BAABNQAECoElAAIIAAkKiR0xGgDXAgAIAAkKiR0xGgDXAgAAAA==.Hennybull:BAAANQADCgIIAgAAAA==.Henný:BAAANQADCgQIBAAAAA==.Hesperos:BAAANQADCggIEQAAAA==.',
Ho='Ho:BAAANQAECgcIBwAAAA==.Hoffzz:BAAANQAECgQIBQAAAA==.Holee:BAAANQADCgYICwAAAA==.Holybaby:BAAANQAECgYIEwAAAA==.Holybrute:BAAANQAECgIIAwABNQAECggIHAAWAIEbAA==.Holybunger:BAAANQAECgUICAAAAA==.Holycannoli:BAAANQADCgIIAgABNQADCgQIBAAJAAAAAA==.Holyscheisse:BAAANQAECggIAwABNQAECgkJGQADAL0AAA==.Holysheetz:BAAANQABCgQIBAAAAA==.Horde:BAAANQADCgcICwAAAA==.',
Hu='Hueycheeks:BAABNQAECoEgAAIhAAkK3xtMBwDiAgAhAAkK3xtMBwDiAgAAAA==.Humantelope:BAAANQAECgYIBgAAAA==.Huntstatus:BAABNQAECoEiAAIMAAgKAxRbagDlAQAMAAgKAxRbagDlAQAAAA==.Huxium:BAABNQAECoEaAAIMAAcKDRWcYwD4AQAMAAcKDRWcYwD4AQAAAA==.',
Hw='Hwangdoyoung:BAAANQABCgEIAQABNQADCgEJAQAJAAAAAA==.',
Hy='Hymnpossible:BAAANQAECgYIEQAAAA==.',
Ic='Icecreamdveg:BAAANQADCggICQAAAA==.Icetongue:BAABNQAECoEbAAIEAAgK9Bv2BACMAgAEAAgK9Bv2BACMAgAAAA==.',
If='Iflingpoo:BAABNQAECoEnAAIZAAkKqRuaGQCwAgAZAAkKqRuaGQCwAgAAAA==.Ifusêekamy:BAAANQAECgQIBwAAAA==.',
Ij='Ijrakwarrior:BAAANQAECgIIAgAAAA==.',
Il='Illidussy:BAAANQADCgcIBwABNQAECgEIAQAJAAAAAA==.Illregularxx:BAAANQAECgIIBAAAAA==.',
Im='Impulse:BAABNQAECoEYAAIKAAcKHyA3KwCCAgAKAAcKHyA3KwCCAgAAAA==.',
In='Indelebi:BAAANQABCgQIBgAAAA==.Inorgeing:BAAANQAECgMIBAAAAA==.Intrúder:BAAANQADCgEIAQAAAA==.',
Ir='Irdaman:BAAANQAECgEIAQAAAA==.Irmengaud:BAAANQAECgUICgAAAA==.Ironbrowd:BAAANQAECgEIAQAAAA==.Ironpup:BAAANQAECgcIEgAAAA==.Ironscales:BAAANQAECgQIAQAAAA==.',
Ja='Jabbyjr:BAABNQAECoEkAAMiAAgKsRGCCQDvAQAiAAgKsRGCCQDvAQAOAAEKTQ3fGAE1AAAAAA==.Jabum:BAAANQAECgcICgAAAA==.Jaio:BAAANQAECgYICgAAAA==.Jajakuna:BAAANQAECgQICQAAAA==.Jangens:BAAANQAFFAEIAQABNQAECggIGQAcAD0eAA==.Jarofsomethi:BAAANQAECgYIDQAAAA==.Jaruni:BAABNQAECoEeAAIaAAgKXR4xCwCmAgAaAAgKXR4xCwCmAgAAAA==.Jaynine:BAABNQAECoEiAAMQAAkK7hkzFQB1AgAQAAgKERszFQB1AgALAAkKAA1bRQAJAgAAAA==.Jazerfunk:BAAANQADCgEIAQAAAA==.',
Je='Jeffvyrt:BAAANQAECgYIDQAAAA==.Jeksulee:BAAANQABCggIEAAAAA==.',
Ji='Jibbs:BAAANQAECgYIBgAAAA==.',
Jo='Jodimaw:BAAANQADCggICAAAAA==.Johncleve:BAAANQADCgIIAgAAAA==.Jorian:BAAANQADCgIIAgABNQAECgIIAwAJAAAAAA==.Joridiezs:BAAANQAECgUICQAAAA==.Joshness:BAAANQADCgMIAwAAAA==.',
Ju='Juanrambo:BAAANQAECgQJCAAAAA==.Juicyjohnson:BAAANQADCgMIBQABNQAECggIGgANAD0kAA==.Jumblo:BAAANQAECgYIDQAAAA==.Jupileo:BAABNQAECoEYAAIEAAgKNQruDACaAQAEAAgKNQruDACaAQAAAA==.Jurassichots:BAAANQADCggIDwAAAA==.',
['Jé']='Jésus:BAAANQAECgUIBQAAAA==.',
Ka='Kaalista:BAAANQAECgEJAwABNQAECggIEwAJAAAAAA==.Kailee:BAACNQAFFIERAAIgAAYK8iHRAQBCAgAgAAYK8iHRAQBCAgA1AAQKgSUAAiAACQqdJVcDAI0DACAACQqdJVcDAI0DAAE1AAQKAwgDAAkAAAAA.Kaito:BAAANQAECgEIAQAAAA==.Kakaboy:BAAANQAECgQIBAABNQAECgkJHQAGAOIZAA==.Kaolis:BAAANQADCggICQAAAA==.Kariba:BAABNQAECoEfAAIQAAkK8SBzBgBWAwAQAAkK8SBzBgBWAwABNQAFFAMIBQAZAGQKAA==.Karmana:BAAANQAECggIEAAAAA==.Katael:BAAANQADCgYICwAAAA==.Kavel:BAABNQAECoEbAAMFAAkKrxd1bgBuAgAFAAkK6RV1bgBuAgAYAAEKiBGdCABLAAAAAA==.Kaylie:BAAANQAECgMIAwAAAA==.Kayti:BAAANQAECgUICgAAAA==.',
Ke='Kelfiona:BAAANQADCggIIwAAAA==.Keraboo:BAAANQAECgYIEAAAAA==.Kerie:BAAANQAECgYIDwAAAA==.Kesleya:BAAANQADCgUIBgAAAA==.Ketamyne:BAAANQADCggIFgAAAA==.Keynin:BAAANQADCgUIBQAAAA==.',
Kh='Khalu:BAAANQADCgEIAQAAAA==.',
Ki='Kiandron:BAAANQADCgYIDgAAAA==.Killerqtlol:BAAANQADCggIHgABNQAECggIHwAIAMIZAA==.Kimbostab:BAAANQADCgMIBAAAAA==.',
Kn='Knockbak:BAAANQAECgYICwAAAA==.',
Ko='Kohko:BAAANQADCgYIBgAAAA==.Kozinirus:BAAANQAECgUICgAAAA==.',
Kq='Kqmav:BAAANQAECgcIEgAAAA==.',
Kr='Kromewell:BAAANQAECgEIAQAAAA==.Kromwell:BAAANQAECgcIBwAAAA==.Kruwll:BAAANQAECgQIBAAAAA==.Krít:BAAANQAECgQIBAABNQADCgQIBAAJAAAAAA==.',
Ku='Kumolock:BAABNQAECoEXAAQjAAcKPxsmBwDmAQAjAAYKDhsmBwDmAQAWAAQKKhIRuAD5AAAeAAEKIhI5aAA8AAAAAA==.Kuntissimo:BAAANQAECgQIBAABNQAECggIGAAGAI4cAA==.Kuongsun:BAAANQADCggIEgAAAA==.',
['Kú']='Kúrama:BAAANQABCgYICAAAAA==.',
La='Ladeehunter:BAAANQAECgcIEgAAAA==.Lambsbreath:BAAANQADCggIFwAAAA==.Lanto:BAAANQADCgUICAABNQABCgIIAgAJAAAAAA==.Laprofessora:BAAANQADCggICAAAAA==.Laquince:BAAANQAECgUIDgAAAA==.Lasagnazaddy:BAAANQADCgYICwAAAA==.Laurafel:BAAANQAECgYICgAAAA==.',
Le='Leetlee:BAAANQADCgMIAwAAAA==.Lelouché:BAAANQABCgIIAgABNQABCgYICAAJAAAAAA==.Lertglochen:BAAANQAECgMICgAAAA==.Lexistarr:BAEANQAECgQIBQABNQAECgUICQAJAAAAAA==.',
Li='Lickmelow:BAAANQADCgEIAQAAAA==.Lightbunz:BAAANQADCgQJBAAAAA==.Lightcast:BAAANQAECgIIAgABNQAFFAUICgAVAOIQAA==.Lightra:BAAANQAECgUICgAAAA==.Limeywater:BAABNQAECoEbAAIkAAgKyxjPDwA1AgAkAAgKyxjPDwA1AgAAAA==.Lindramech:BAAANQADCgYIBgAAAA==.Liquedz:BAAANQADCgYIBgAAAA==.Litherous:BAAANQAECgcIDQAAAA==.Litzdh:BAAANQAECgYIDwAAAA==.',
Ll='Llazereth:BAABNQAECoEhAAIZAAgKkwuATgB2AQAZAAgKkwuATgB2AQAAAA==.Llordvalar:BAAANQADCgIJAgAAAA==.',
Lo='Lockimar:BAEBNQAECoEXAAQWAAgK/AuRbwC4AQAWAAgK/AuRbwC4AQAeAAQK0wXEOgDCAAAjAAEKVA8FKAA0AAAAAA==.Lockuru:BAABNQAECoEgAAMeAAkKlxymHQBxAQAWAAcK7hveRgA8AgAeAAYKOw6mHQBxAQAAAA==.Lonestàr:BAAANQAECgUIDgAAAA==.Lowiqslowirl:BAAANQABCgIIAgAAAA==.',
Lu='Lucian:BAAANQADCgMIAwAAAA==.Lucidy:BAAANQAECgYIBwAAAA==.Lumberjacked:BAAANQAECgQIBgABNQAECgkJGAATAMAhAA==.Luna:BAAANQADCgYJDQABNQAECggIGQAWAAgcAA==.Luspriest:BAAANQADCgQIBAAAAA==.Lusuffer:BAABNQAECoEfAAIZAAgKzCH7EQD1AgAZAAgKzCH7EQD1AgAAAA==.Lusufferr:BAAANQAECgQIBAABNQAECggIHwAZAMwhAA==.Lutra:BAABNQAECoEgAAIkAAgKhBS8EgD+AQAkAAgKhBS8EgD+AQAAAA==.',
Ly='Lyx:BAAANQAECgUICgAAAA==.',
Ma='Madseason:BAAANQAECgEIAQAAAA==.Magerpwn:BAAANQADCgUIBQAAAA==.Magusarcanus:BAAANQAECgEIAQAAAA==.Makrio:BAAANQABCgUIBwAAAA==.Malachî:BAAANQAECgIIAgAAAA==.Malitan:BAABNQAECoEmAAINAAkK3xaZUwBJAgANAAkK3xaZUwBJAgAAAA==.Mamif:BAAANQAECgYIDQAAAA==.Manfrony:BAAANQADCggICAABNQAECgcIFwAMAPUZAA==.Mannasto:BAAANQADCgYIBgAAAA==.Manuelek:BAAANQAECgEIAQAAAA==.Markatron:BAAANQAFFAEIAQAAAA==.Mattiekay:BAABNQAECoEdAAMSAAgKuhkqKwAyAgASAAgKuhkqKwAyAgAZAAUKSgQ/gQCrAAAAAA==.Maxx:BAAANQAECgYJBgAAAA==.Mayberocks:BAAANQAECggIBwABNQAFFAYIDgAdACodAA==.Mañajuana:BAABNQAECoEgAAMRAAgKEhegDQAQAgARAAgKTRagDQAQAgAUAAYKohD6UgA9AQAAAA==.',
Mc='Mclaud:BAAANQADCgYIBgAAAA==.',
Me='Meatrocket:BAAANQADCgYIBgABNQAECgkJIgAXAFoiAA==.Meefalo:BAAANQAECgYIEwAAAA==.Meganfox:BAAANQAECgcIDQAAAA==.Meggfox:BAAANQADCgQIBAAAAA==.Meghanics:BAAANQAECgYIDAAAAA==.Meileen:BAAANQADCgEIAQAAAA==.Mendwyn:BAAANQABCgUJBQAAAA==.Menethol:BAAANQADCgUIBQABNQAECggIMwAFAJsaAA==.Mercymage:BAAANQAECgMIAwAAAA==.Merie:BAAANQADCgUJBQABNQAECgcIEgAJAAAAAA==.Merlinswrath:BAAANQADCgYJBAAAAA==.Merril:BAAANQADCgIIAgABNQAECgkJJQAcAL4eAA==.Merza:BAAANQADCggJDAABNQAFFAMIBQAlAO0WAA==.Merzinator:BAACNQAFFIEFAAIlAAMK7RZwCAD9AAAlAAMK7RZwCAD9AAA1AAQKgSYAAyUACQrnH5gIADUDACUACQrnH5gIADUDAA8AAgr+C21pAFsAAAAA.',
Mi='Mickle:BAAANQAECgYICgAAAA==.Midgrad:BAAANQADCggIDgABNQAECgYIEgAJAAAAAA==.Mikelowry:BAAANQAECgcIEQAAAA==.Minimum:BAAANQAECgQIBAABNQAECgUIBQAJAAAAAA==.Misae:BAAANQADCgMIAwAAAA==.Mischeveous:BAAANQAECgUIDwAAAA==.Missu:BAAANQADCgEJAQAAAA==.Mithrandir:BAABNQAECoEdAAMEAAgKWBYIHADLAAAFAAYKtBZDzQCaAQAEAAMKgBQIHADLAAAAAA==.',
Mj='Mjiltanke:BAAANQAECgUIDQAAAA==.',
Mo='Moistcarry:BAAANQADCgUIBQAAAA==.Mokniahiah:BAAANQAECgcIEgAAAA==.Monkmates:BAAANQAECgEIAQAAAA==.Moodoon:BAAANQAECgYICAAAAA==.Moohammadali:BAAANQADCgYJBgAAAA==.Mooseyfate:BAAANQAECgYICgAAAA==.Moraxy:BAAANQAECgUIDAAAAA==.Moromagus:BAABNQAECoEnAAIFAAkKqhYNawB2AgAFAAkKqhYNawB2AgAAAA==.Mortis:BAAANQAECgYICgAAAA==.Motaro:BAAANQADCggICAAAAA==.Motorboats:BAAANQADCggIFgAAAA==.',
Mu='Mualpractice:BAAANQADCgQIBQAAAA==.Murasaki:BAAANQAECgMIBAABNQAECgMIBAAJAAAAAA==.Murdok:BAAANQAECggIDQAAAA==.Murray:BAAANQAECgcIDQABNQAFFAUIDwAZAIAMAA==.Mutknodeprac:BAAANQAECgYIDQAAAA==.',
Mx='Mxsery:BAAANQAECgYICAAAAA==.Mxz:BAAANQADCgcIBwABNQAECgkJKwADAMwdAA==.',
My='Myræl:BAAANQAECgcICwAAAA==.Mystíle:BAACNQAFFIEHAAISAAQK3x9wBQBkAQASAAQK3x9wBQBkAQA1AAQKgSwAAhIACQr2JaYCALkDABIACQr2JaYCALkDAAAA.Mythrix:BAAANQABCgIIAgABNQADCgcIEQAJAAAAAA==.Mythrixx:BAAANQADCgcIEQAAAA==.',
['Mà']='Màjíque:BAAANQAECgYIDwAAAA==.',
['Mé']='Méadow:BAAANQADCggIGwAAAA==.',
['Mö']='Mötley:BAAANQADCggIDQABNQAECgEIAQAJAAAAAA==.',
Na='Nabesan:BAAANQADCgIIAgAAAA==.Naked:BAAANQADCggIBAAAAA==.Nalera:BAAANQAECggIBwAAAA==.Nanoboostme:BAAANQADCggIEAAAAA==.Narhi:BAAANQAECgQIBwAAAA==.Nasminthe:BAAANQAECgEIAQAAAA==.Nature:BAAANQADCgUIBQAAAA==.Naughtya:BAAANQAECgQIDAAAAA==.Nay:BAAANQAECgMIAgAAAA==.Nazem:BAAANQAECgUICgAAAA==.',
Ne='Neikoh:BAAANQAECgEIAQAAAA==.Nekoro:BAABNQAECoEcAAQWAAcKgRvyRwA4AgAWAAcKgRvyRwA4AgAjAAIK4QmOGwBnAAAeAAEKCAVfagA5AAAAAA==.Nelfsquantch:BAAANQAECgQICAAAAA==.Nevadawolf:BAAANQAECgUICwAAAA==.',
Ni='Nightreaver:BAAANQAECgQIBQAAAA==.Nightshiftér:BAAANQAECgEJAgAAAA==.Nimbex:BAAANQADCgQIBAAAAA==.Ninetailsfox:BAABNQAECoEaAAIFAAgK/BBKswDQAQAFAAgK/BBKswDQAQABNQAECgkJHQAGAOIZAA==.Nion:BAABNQAECoEXAAMLAAcKJwYseQA/AQALAAcKJwYseQA/AQAQAAEKSAPvbwAfAAAAAA==.Nippy:BAAANQADCggIEgABNQAECgUICQAJAAAAAA==.',
No='Nolo:BAAANQADCgQIBQAAAA==.Northzen:BAABNQAECoEaAAIgAAgKihzTFgBFAgAgAAgKihzTFgBFAgAAAA==.Notaorc:BAAANQADCgUIBQAAAA==.Notmyconcern:BAAANQAECgEIAQAAAA==.Novaflux:BAABNQAECoEbAAIFAAgKwiDqRQDVAgAFAAgKwiDqRQDVAgAAAA==.Noxxicc:BAAANQAECgUIDAABNQAECggILgAIAFMeAA==.',
Ny='Nyghtterror:BAAANQAECgEIAQAAAA==.Nyreeh:BAAANQAECgQIBwAAAA==.Nyrsa:BAAANQADCgUIBQABNQAECgQIBwAJAAAAAA==.Nytearcher:BAABNQAECoEVAAIMAAcKhxzgQQBcAgAMAAcKhxzgQQBcAgAAAA==.Nyxa:BAAANQAECgUICAAAAA==.',
['Ná']='Nálera:BAAANQADCggIDgAAAA==.',
['Nü']='Nüguns:BAAANQAECgMIAwAAAA==.',
Ok='Okamifist:BAAANQADCgYIBgAAAA==.Oklyra:BAAANQABCgYICgAAAA==.',
Om='Omnia:BAABNQAECoEaAAMIAAgKjBLfTwDUAQAIAAgKjBLfTwDUAQADAAcK7QV3iQA1AQABNQADCggICAAJAAAAAA==.Omrath:BAAANQADCgYIBgABNQABCgIIAgAJAAAAAA==.',
On='Onlyshams:BAAANQAECgQIBAAAAA==.',
Oo='Oogiee:BAABNQAECoEaAAIPAAgKDwoCNACrAQAPAAgKDwoCNACrAQAAAA==.',
Or='Orcmonk:BAAANQADCggIFQAAAA==.Orthoganal:BAAANQAECgcICAAAAA==.',
Os='Oschun:BAABNQAECoEkAAINAAgKmhyNSABuAgANAAgKmhyNSABuAgAAAA==.',
Pa='Palacandia:BAAANQADCgYIBQAAAA==.Palanar:BAABNQAECoEiAAMSAAkKvySgCwA4AwASAAgKViWgCwA4AwAbAAQKASHYPABlAQAAAA==.Palle:BAAANQAECgcIEQAAAA==.Pallyboi:BAAANQAECgUICwAAAA==.Paluru:BAAANQAECgEIAQABNQAECgkJIAAeAJccAA==.Panosh:BAAANQADCgUIBQAAAA==.Pantricelog:BAAANQADCggICAABNQAECggIIAAVAEQYAA==.',
Pc='Pchef:BAAANQAECgQIBgAAAA==.',
Pe='Pelayo:BAAANQAECgQIBwABNQAECgQICAAJAAAAAA==.Peperoninips:BAAANQAECgQICAAAAA==.Petricia:BAABNQAECoEgAAIVAAgKRBjzFgA+AgAVAAgKRBjzFgA+AgAAAA==.',
Pf='Pfeffer:BAAANQAECgUICwAAAA==.',
Ph='Phaithful:BAACNQAFFIENAAMQAAUKchRxBgBcAQAQAAQKhhdxBgBcAQAmAAEKpAjAAgBRAAA1AAQKgSUAAxAACQriHxIMAPsCABAACQriHxIMAPsCACYABgogDrsLAE4BAAAA.Pharaoh:BAAANQADCgQIBAAAAA==.Phazerman:BAABNQAECoEZAAMmAAgKtwkGCQCXAQAmAAgKtwkGCQCXAQAQAAEKoBmNWABKAAAAAA==.Phocus:BAAANQAFFAEIAQABNQAFFAUIDQAQAHIUAA==.Phury:BAAANQAECgcIDAABNQAFFAUIDQAQAHIUAA==.',
Pi='Pikapikapika:BAABNQAECoEaAAIDAAgKLxWPPAA6AgADAAgKLxWPPAA6AgAAAA==.',
Pl='Planthoofem:BAAANQAECgIIAgAAAA==.Playpride:BAAANQAECgYIDwAAAA==.',
Po='Poboy:BAAANQAECgYICgAAAA==.Pocket:BAAANQAECgQIBQABNQAECggIGQAWAAgcAA==.Pokepokepoke:BAAANQAECgYIDwAAAA==.Poppop:BAAANQAECgYIDwAAAA==.Poriand:BAAANQAECgQJBQAAAA==.Portzul:BAAANQAECgEIAQAAAA==.',
Pr='Priesttea:BAAANQAECgEIAgAAAA==.Procology:BAAANQAECgEIAQAAAA==.',
Ps='Pseudogrim:BAABNQAECoEYAAIFAAgKvRNOjgAiAgAFAAgKvRNOjgAiAgAAAA==.Psspspss:BAAANQAECgQIBgAAAA==.',
Pu='Pugno:BAAANQADCggICAAAAA==.Pugnosano:BAAANQADCgQIBAABNQADCggICAAJAAAAAA==.Pussnboots:BAAANQAECgQIDAAAAA==.',
['Pö']='Pöppop:BAAANQAECgEIAQABNQAECgYIDwAJAAAAAA==.',
Qq='Qq:BAAANQAECggIBgAAAA==.',
Ra='Raefe:BAAANQAECgYIDgAAAA==.Raffaj:BAAANQAECgYIDQAAAA==.Raidedww:BAAANQADCgUIBQAAAA==.Raihnese:BAEANQAECgUJCQAAAA==.Ramenveg:BAAANQAECgUIDgAAAA==.Rancora:BAABNQAECoEYAAIVAAkK0wgfIQDEAQAVAAkK0wgfIQDEAQAAAA==.Ravnsifu:BAAANQADCggIDQAAAA==.',
Re='Reapersbless:BAAANQAECgEIAgABNQAECgEIAgAJAAAAAA==.Reapersbount:BAAANQAECgEIAgAAAA==.Reapersele:BAAANQADCgMIAwABNQAECgEIAgAJAAAAAA==.Redbuffpls:BAACNQAFFIEJAAINAAUKUxnrBAC9AQANAAUKUxnrBAC9AQA1AAQKgSkAAg0ACQrkJRsHAK8DAA0ACQrkJRsHAK8DAAAA.Redbul:BAAANQAECgcIEwAAAA==.Redbullz:BAAANQADCgUIBQAAAA==.Reddrock:BAAANQADCggIDwAAAA==.Redstörm:BAAANQADCgcIBwAAAA==.Reffusul:BAAANQADCgMIAwABNQAECggIHwAZAMwhAA==.Reflexadín:BAAANQADCgcIBwAAAA==.Reilanna:BAAANQAECgcIBwAAAA==.Reptilia:BAABNQAECoEhAAIUAAkKxBhFGwC/AgAUAAkKxBhFGwC/AgAAAA==.Rewef:BAAANQAECgQIBQABNQAFFAcIGAADAFkeAA==.Rex:BAABNQAECoEeAAIFAAkKBSKuGwBUAwAFAAkKBSKuGwBUAwAAAA==.',
Rh='Rhune:BAAANQADCgIIAgAAAA==.',
Ri='Rickylicky:BAAANQADCgIIAgAAAA==.Riffz:BAABNQAECoEiAAMCAAkKLBzUEQCqAgACAAgKvBzUEQCqAgAHAAgKDBJYFQAWAgAAAA==.Rig:BAAANQAECgQIBAAAAA==.Rinzsha:BAAANQAECgYIDwAAAA==.Rishka:BAAANQADCgUIBQAAAA==.Riv:BAAANQADCggICAABNQAECgYIEgAJAAAAAA==.Rivien:BAAANQAECgYIEgAAAA==.',
Ro='Roostersauce:BAAANQADCgYIBgAAAA==.Rosare:BAAANQADCgEIAQAAAA==.',
Ru='Ruhkouri:BAAANQAECgQIBwAAAA==.Rulez:BAAANQADCgQIBAAAAA==.Rustibox:BAACNQAFFIETAAMWAAcKShWJAwDzAQAWAAYKNhKJAwDzAQAeAAIKfRtCBQDBAAA1AAQKgTIAAxYACQr5JPsDAJ0DABYACQo0JPsDAJ0DAB4ABAqzFLskADgBAAAA.',
Sa='Saltdeeduck:BAAANQADCgQJBgAAAA==.Samardev:BAAANQADCgYIBgABNQAECgkJJQAcAL4eAA==.Sammichomg:BAABNQAECoEaAAINAAcKqiEDRgB3AgANAAcKqiEDRgB3AgAAAA==.Sammyfuego:BAAANQAECgYIDQAAAA==.Sarutko:BAAANQAECgUICAAAAA==.Sazaimes:BAAANQABCgUIBQAAAA==.',
Sc='Scalestas:BAABNQAECoEdAAIXAAgKhxtQCwCEAgAXAAgKhxtQCwCEAgAAAA==.Scoobies:BAAANQAECgQIBgABNQAFFAEIAQAJAAAAAA==.',
Se='Searing:BAABNQAECoEgAAMaAAkKtRrXDgBjAgAaAAkKtRrXDgBjAgANAAMKNx3ZzwAHAQAAAA==.Segfaulted:BAAANQAECgcIDAAAAA==.Seleane:BAABNQAECoEeAAMIAAgK/RT6RQD8AQAIAAgK/RT6RQD8AQADAAIKgQom2QBuAAAAAA==.Sellvanya:BAAANQADCgYICQAAAA==.Senyor:BAAANQAECgEIAQABNQAECgQICQAJAAAAAA==.Seraphia:BAAANQADCgQIBAAAAA==.Sethcure:BAAANQAECgIIAgAAAA==.',
Sh='Shaadas:BAABNQAECoEiAAILAAgKgRsYLAB5AgALAAgKgRsYLAB5AgAAAA==.Shabazz:BAAANQAECgQICAAAAA==.Shacklestorm:BAAANQAECgIIAwAAAA==.Shadeau:BAAANQAECgUICQAAAA==.Shamackerd:BAAANQAECgYICAAAAA==.Shampoo:BAAANQABCgUIBAAAAA==.Shandriss:BAAANQAECgIIAwAAAA==.Shawlen:BAAANQABCgIIAgAAAA==.Sheve:BAAANQADCgQJBAAAAA==.Shmimon:BAAANQAECgYIDgAAAA==.Shockapal:BAAANQAECgUICQAAAA==.Shockvalue:BAAANQAECgEJAQAAAA==.Shrimon:BAAANQADCgIIAgAAAA==.Shrimps:BAAANQAECggIDQAAAA==.Shâokahn:BAAANQADCgcIDAAAAA==.',
Si='Sicell:BAAANQAECgYIBgAAAA==.Sidewinder:BAAANQAECgYICgAAAA==.Sillybear:BAAANQAECgIIAwAAAA==.Siong:BAAANQAECgcIEQAAAA==.Sitch:BAAANQADCgQJBQAAAA==.',
Sk='Skeletorz:BAAANQADCgYIDAAAAA==.Skunknmidget:BAAANQADCggIDgAAAA==.Skyvestris:BAAANQAECgcICgAAAA==.',
Sl='Slamueladams:BAAANQADCgMIAwAAAA==.Slayberto:BAABNQAECoEbAAInAAgKjxKqDQDZAQAnAAgKjxKqDQDZAQAAAA==.Sleepbringer:BAAANQAECgEIAQAAAA==.Sloppysecond:BAAANQADCgQIBAAAAA==.',
Sm='Smellmygas:BAAANQAECgQIEgAAAA==.Smoko:BAABNQAECoEYAAIIAAcKwhtfPQAhAgAIAAcKwhtfPQAhAgAAAA==.',
Sn='Sneaky:BAABNQAECoEkAAILAAkKCSB2CgBMAwALAAkKCSB2CgBMAwABNQAECgkJLAARALYmAA==.Sneakyr:BAABNQAECoEsAAIRAAkKtiYuAAAIBAARAAkKtiYuAAAIBAAAAA==.Snoodle:BAAANQADCgYJBgAAAA==.Snypar:BAABNQAECoEdAAIVAAgKFRLeHAD1AQAVAAgKFRLeHAD1AQAAAA==.Snôva:BAAANQAECgYIDwAAAA==.',
So='Soaraga:BAAANQABCgQIBAAAAA==.Sodosopa:BAAANQADCgYIBgAAAA==.Solaire:BAAANQAECgUICwAAAA==.Sole:BAAANQADCgcIBwABNQAECgUJCgAJAAAAAA==.Soleim:BAAANQAECgUJCgAAAA==.Somavanna:BAAANQAECgYIDwAAAA==.Sophara:BAAANQAECgUIBwAAAA==.Sorbet:BAABNQAECoEgAAIEAAkKASS9AACbAwAEAAkKASS9AACbAwAAAA==.Soulgrinder:BAAANQAECgYICwAAAA==.',
Sp='Sparden:BAAANQADCggICgAAAA==.Sparhawk:BAABNQAECoEiAAINAAkKPCAlGgAzAwANAAkKPCAlGgAzAwAAAA==.Sparklebolts:BAAANQADCgQIBAAAAA==.Speedwagon:BAAANQAECgUICwABNQAECgYIDAAJAAAAAA==.Spicytotems:BAABNQAECoEZAAIDAAcKgRVxUADmAQADAAcKgRVxUADmAQAAAA==.Spidercowsd:BAAANQADCgIJAgAAAA==.Spippy:BAAANQAECgQIBAAAAA==.Spitzer:BAAANQADCgEIAQAAAA==.Splõõsh:BAABNQAECoEuAAMIAAgKUx6xJACZAgAIAAgKUx6xJACZAgADAAQKaRdJjwAmAQAAAA==.Spooky:BAAANQADCggIGwABNQAFFAUIDgACAIYfAA==.Spro:BAAANQAECgQIBAABNQAECgkJIQAPAAIiAA==.Sprogue:BAABNQAECoEjAAQCAAkK0x8+BwAzAwACAAkK0x8+BwAzAwATAAYKAxAuDABlAQAHAAEK1Q2rRAA9AAABNQAECgkJIQAPAAIiAA==.Spronatty:BAAANQADCgIIAgAAAA==.Sprosport:BAAANQAECgUIDQABNQAECgkJIQAPAAIiAA==.Sprø:BAAANQAECgEIAQABNQAECgkJIQAPAAIiAA==.Spurlock:BAAANQAECgIIAgAAAA==.Spyrogos:BAAANQAECgUICwAAAA==.',
Sq='Squidbits:BAAANQAECgQIDAAAAA==.Sqwuanchigos:BAAANQADCggICAAAAA==.',
St='Stabsandhugs:BAAANQADCgQIBAAAAA==.Starclaw:BAABNQAECoEfAAIoAAkK7SNvAQCaAwAoAAkK7SNvAQCaAwAAAA==.Stasis:BAABNQAECoEaAAQKAAcKpwsMiAAwAQAKAAYKJwkMiAAwAQANAAYKtgbWzQALAQAaAAEK3QgYWAAxAAAAAA==.Statixx:BAAANQADCgYIBgAAAA==.Stel:BAAANQAECgEIAQAAAA==.Stroonzy:BAAANQAECgUIBwAAAA==.Stumbly:BAAANQAECgEIAQAAAA==.Styrmir:BAAANQADCgMIAwAAAA==.',
Su='Sugarteets:BAAANQAECgYIDwAAAA==.Sujung:BAAANQADCgIJAwAAAA==.Sukubis:BAAANQADCgUIBQAAAA==.Supadope:BAAANQAECgQICgAAAA==.Superpaladin:BAAANQAECgQIBgABNQAECgUICgAJAAAAAA==.',
Sy='Sydner:BAAANQAECgYIDgAAAA==.Synergize:BAAANQADCgMIAwAAAA==.Sythila:BAACNQAFFIELAAIPAAUK5gnzBgByAQAPAAUK5gnzBgByAQA1AAQKgSIAAw8ACQqtHicXAJ8CAA8ACQqEHScXAJ8CACUABgo+GMssAJsBAAAA.',
['Sé']='Séamus:BAAANQADCgYIBgAAAA==.',
['Sü']='Süblime:BAAANQAECggIBwAAAA==.',
Ta='Tachichan:BAAANQADCgUIBQAAAA==.Tacx:BAAANQAECgEIAQAAAA==.Tadertod:BAAANQAECggIDwAAAA==.Talleth:BAABNQAECoFOAAIXAAkKpCF9AgB2AwAXAAkKpCF9AgB2AwAAAA==.Tallìsh:BAAANQADCgYICgABNQAECgYIBgAJAAAAAA==.Talorion:BAAANQAECgcIEwAAAA==.Tandrisell:BAAANQAECgEIAQAAAA==.Tarkyn:BAAANQADCggICAAAAA==.Tassyn:BAABNQAECoEgAAMHAAgKwBPNGQDmAQAHAAcKXxLNGQDmAQACAAIKBxJgYwCDAAAAAA==.Tattianna:BAAANQAECgYIDQAAAA==.Tazenezoth:BAABNQAECoElAAIcAAkKvh46CgDfAgAcAAkKvh46CgDfAgAAAA==.',
Te='Tehmachine:BAAANQAECgYIEgAAAA==.Terpene:BAAANQAECgEIAQAAAA==.Terry:BAAANQAECgYIDwAAAA==.',
Th='Thanyros:BAABNQAECoEdAAIZAAgKbyPJDQAeAwAZAAgKbyPJDQAeAwAAAA==.Thanywar:BAABNQAECoEfAAIOAAkKVCIADQB+AwAOAAkKVCIADQB+AwAAAA==.Thebrowner:BAAANQAECgIIAgABNQAECgUIDQAJAAAAAA==.Thejuice:BAAANQAECgEIAQAAAA==.Thetrashman:BAAANQAECgUIDQAAAA==.Thoian:BAAANQAECgcIEgAAAA==.Thork:BAAANQADCgYIBgAAAA==.Thrindy:BAAANQAECgYIBwAAAA==.Thugnificint:BAABNQAECoEdAAMGAAkK4hnRGgBHAgAGAAkKLhXRGgBHAgAMAAIKDxZZ8wCMAAAAAA==.Thåwn:BAAANQAECgYICAAAAA==.Thèokoles:BAABNQAECoEjAAQOAAgK6xa6XQAtAgAOAAgK6xa6XQAtAgABAAYKKws2HAAZAQAiAAEKpguuJwA2AAAAAA==.',
Ti='Tiblock:BAABNQAECoEpAAIeAAkKlhJsCQBSAgAeAAkKlhJsCQBSAgAAAA==.Tidalsage:BAAANQAECgcIEQAAAA==.Tilolas:BAAANQAECgIIAwAAAA==.Timeskip:BAAANQAECgUICgAAAA==.Timfinnigut:BAABNQAECoEeAAISAAgKUSIUDwATAwASAAgKUSIUDwATAwAAAA==.Tinkiewinkie:BAAANQADCggICAAAAA==.Tinx:BAAANQAECgYIDQAAAA==.Tinylego:BAAANQADCggIGwAAAA==.Tinytiran:BAAANQAECgYIEAABNQAECggIHAAKAJ0aAA==.',
To='Tonktotem:BAEANQADCgEIAQABNQAECgYIEQAJAAAAAA==.Toptearcryer:BAABNQAECoEbAAIOAAgKPRczZAAZAgAOAAgKPRczZAAZAgAAAA==.Tortilla:BAAANQAECgYIDAAAAA==.Toryn:BAAANQADCgYICgABNQADCggICAAJAAAAAA==.',
Tr='Trailwalker:BAAANQAECgcIDAAAAA==.Trashypally:BAAANQAECgEIAgAAAA==.Trecks:BAAANQADCggIHAAAAA==.Treelonmüsk:BAAANQAECgUIBgAAAA==.Treesumm:BAAANQAECgYIDAAAAA==.Trickyrickyy:BAAANQAECgUICgAAAA==.Triptix:BAAANQADCggIEQAAAA==.Truthbringer:BAAANQADCgQIBAAAAA==.Trynitie:BAAANQAECgUICgAAAA==.',
Tu='Turlane:BAABNQAECoEUAAINAAcKOgblxwAXAQANAAcKOgblxwAXAQAAAA==.',
Tw='Twinkslayer:BAAANQADCgYIDgABNQAECgkJGAAWANcbAA==.Twinkugly:BAAANQABCgcIDwAAAA==.',
Ty='Tyberia:BAAANQAECgUICAAAAA==.Tychó:BAABNQAECoEWAAIOAAgKMht+RgB6AgAOAAgKMht+RgB6AgAAAA==.Tyeret:BAABNQAECoEXAAINAAkKfBToVgA+AgANAAkKfBToVgA+AgAAAA==.Tyet:BAAANQAECgYIBAABNQAECgkJFwANAHwUAA==.',
['Tø']='Tørvald:BAAANQAECgQICgAAAA==.',
Uc='Uccisore:BAAANQADCgcIDQAAAA==.',
Un='Unbeliever:BAAANQABCgYICgAAAA==.',
Us='Uslurper:BAABNQAECoEoAAQNAAkKiBtjNwCtAgANAAkKURtjNwCtAgAaAAkKhhIpFgD5AQAKAAEKPAcl7QA2AAAAAA==.',
Va='Vaalak:BAAANQAECgEIAQAAAA==.Valrosh:BAAANQAECgEIAQAAAA==.Varenar:BAABNQAECoEgAAIlAAgK6hduGwBEAgAlAAgK6hduGwBEAgAAAA==.Varpuff:BAAANQADCgYIBgABNQAFFAEIAQAJAAAAAA==.',
Ve='Vearn:BAAANQADCgMIAwABNQADCggIEAAJAAAAAA==.Velkorn:BAAANQADCgYIBwAAAA==.Vellamo:BAAANQADCgMIBQAAAA==.Vengeful:BAAANQADCggJGwAAAA==.Venuveus:BAAANQAECgYIDwAAAA==.Verdan:BAABNQAECoEZAAIoAAgKOhn5BwB2AgAoAAgKOhn5BwB2AgAAAA==.',
Vi='Viperion:BAAANQADCgMIAwAAAA==.Virlomi:BAACNQAFFIEHAAIVAAQKOxGRBQBQAQAVAAQKOxGRBQBQAQA1AAQKgS4AAhUACQqPIRAGAD0DABUACQqPIRAGAD0DAAAA.Viyya:BAAANQADCgYIBgAAAA==.',
Vl='Vlix:BAAANQADCgMIAwAAAA==.',
Vo='Vowz:BAAANQADCgYICgAAAA==.',
Vy='Vynx:BAAANQAECgYIDQAAAA==.Vyrogash:BAAANQADCgMIAwAAAA==.Vythica:BAAANQAECggIEwAAAA==.',
Wa='Wakoguyc:BAAANQAECgQIBwAAAA==.Warcaige:BAAANQAFFAEIAQABNQAFFAcIGAAbABcVAA==.Wargodd:BAAANQAECggIBQABNQAECgkJFwANAHwUAA==.',
We='Weierstraß:BAABNQAECoEeAAIMAAgK8hP/TQA3AgAMAAgK8hP/TQA3AgAAAA==.Welari:BAABNQAECoEgAAINAAgKRCDvMgC+AgANAAgKRCDvMgC+AgAAAA==.Weskerx:BAAANQAECgUIBwAAAA==.',
Wh='Whindd:BAAANQAECgEIAQAAAA==.Whurstresort:BAABNQAECoEZAAIlAAgKpR35EgCoAgAlAAgKpR35EgCoAgAAAA==.Whurstrong:BAAANQADCgEIAQABNQAECggIGQAlAKUdAA==.Whurstyx:BAAANQAECgUIBQAAAA==.',
Wi='Wickedsoul:BAAANQADCggICAAAAA==.Widowmaker:BAAANQAECgIIAwAAAA==.Wif:BAAANQAECgMIBAAAAA==.Wingmancole:BAAANQADCgQIBAAAAA==.Withers:BAAANQADCgYIBgABNQAECggIGwAOANEfAA==.',
Wo='Wondrball:BAABNQAECoEXAAMdAAgKaw3PDgD3AAAXAAYK8A0yHABLAQAdAAUK3grPDgD3AAAAAA==.Worgen:BAAANQAECgcIEQAAAA==.Worthless:BAAANQADCggICAAAAA==.',
Xa='Xago:BAAANQADCgUJBQAAAA==.Xalvelora:BAAANQADCgYICQAAAA==.Xanderia:BAAANQAECgUIDAAAAA==.Xandil:BAAANQADCggICAAAAA==.Xanius:BAAANQADCgMIAwAAAA==.',
Xe='Xeralath:BAABNQAECoEeAAIWAAgKbQfShQB2AQAWAAgKbQfShQB2AQAAAA==.',
Xv='Xvibe:BAAANQAECgQIBwAAAA==.',
Xy='Xyphira:BAAANQAECgMIBAAAAA==.',
['Xý']='Xý:BAAANQADCgYIGQAAAA==.',
Ya='Yaboo:BAAANQAECgEIAQAAAA==.Yaen:BAAANQADCgcIDAAAAA==.',
Ye='Yehvenâh:BAAANQAECgYIEQAAAA==.Yeska:BAAANQADCgQIBAAAAA==.',
Yo='Yootle:BAABNQAECoEZAAIVAAgKxRRvGwAHAgAVAAgKxRRvGwAHAgAAAA==.Youngcheese:BAAANQADCgcIBwAAAA==.Yourgothgf:BAEANQAECgYIEQAAAA==.Yovanna:BAAANQADCgYIBAABNQAECggIAwAJAAAAAA==.',
Yu='Yummyx:BAAANQAECgEIAQAAAA==.',
Za='Zallo:BAABNQAECoEXAAIRAAcKDyQjBgDTAgARAAcKDyQjBgDTAgAAAA==.Zaloria:BAAANQAECgQIBgAAAA==.Zaqws:BAAANQADCggIDAAAAA==.Zarth:BAAANQADCgIIAgAAAA==.Zava:BAAANQAECgQIEQAAAA==.Zaxon:BAAANQADCggIDAABNQADCggICAAJAAAAAA==.',
Ze='Zeelos:BAAANQAECggIDQAAAA==.Zembu:BAAANQADCgQIBAAAAA==.Zephhyr:BAABNQAECoEbAAIOAAgK0R9AKwDiAgAOAAgK0R9AKwDiAgAAAA==.Zephyr:BAAANQAECgQIBQAAAA==.Zeñor:BAAANQAECgQICQAAAA==.',
Zh='Zharek:BAAANQADCgUICgAAAA==.Zhax:BAAANQABCgMIAwAAAA==.',
Zi='Zireael:BAABNQAECoEXAAIfAAcKax/OBQB1AgAfAAcKax/OBQB1AgAAAA==.',
Zo='Zornox:BAAANQADCgYIEQAAAA==.',
['Óp']='Óprawïndfury:BAAANQAECgUICwAAAA==.',
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
