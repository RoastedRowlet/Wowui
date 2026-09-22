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

local lookup = {'Unknown-Unknown','Shaman-Elemental','Mage-Frost','Mage-Arcane','Hunter-Marksmanship','Shaman-Restoration','Paladin-Holy','Priest-Holy','Hunter-BeastMastery','Paladin-Retribution','DemonHunter-Havoc','Priest-Shadow','Druid-Guardian','Rogue-Outlaw','Druid-Balance','Druid-Restoration','Evoker-Devastation','Mage-Fire','Paladin-Protection','Warrior-Arms','Evoker-Preservation','Evoker-Augmentation','DeathKnight-Blood','Rogue-Subtlety','DeathKnight-Unholy','Monk-Windwalker','Warlock-Demonology','Shaman-Enhancement','Warrior-Fury','Warlock-Destruction','Warlock-Affliction','Monk-Mistweaver','DemonHunter-Devourer','DeathKnight-Frost','Priest-Discipline','Rogue-Assassination','Druid-Feral','Warrior-Protection',}
local provider = {region='US',realm='Korgath',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abbygrace:BAAANQAECgUIBgAAAA==.',
Ad='Adar:BAAANQAECgUICgAAAA==.',
Ae='Aegeis:BAAANQAECgEIAQABNQAECgYIDQABAAAAAA==.Aelaryn:BAAANQAECgIJAwAAAA==.Aeonffx:BAAANQAECgIIAgAAAA==.',
Af='Afterearth:BAACNQAFFIEHAAICAAUKFx8WAwDYAQACAAUKFx8WAwDYAQA1AAQKgR4AAgIACQrTJK0FAKMDAAIACQrTJK0FAKMDAAAA.',
Ag='Aggrobeast:BAAANQAECgUJCAAAAA==.Agoný:BAAANQADCgQIBAAAAA==.',
Ai='Ailie:BAABNQAECoEXAAMDAAgKNx2dBABeAgADAAgKNx2dBABeAgAEAAMKrw7+NgGeAAAAAA==.',
Ak='Akadey:BAAANQADCgYICAAAAA==.',
Al='Aliì:BAAANQAECgYJDAABNQAECgkJHAAFAFYdAA==.Allise:BAAANQAECgEJAgAAAA==.Allnightlong:BAAANQAECgQJBAABNQAECgcIEwABAAAAAA==.Allnightløng:BAAANQAECgcIEwAAAA==.Alphonos:BAAANQADCgMJAwAAAA==.Alverez:BAABNQAECoEqAAIGAAkKuiAYCABVAwAGAAkKuiAYCABVAwAAAA==.',
Am='Amorilas:BAAANQAECgYIEQAAAA==.Amunera:BAAANQADCgYIEAABNQAECgEIAQABAAAAAA==.Amàrok:BAAANQADCgUICgABNQADCggIFgABAAAAAA==.',
An='Andersan:BAABNQAECoEkAAIHAAgKYxJEPAAGAgAHAAgKYxJEPAAGAgAAAA==.Anetharion:BAAANQAECgEIAQAAAA==.Animalchange:BAAANQAECgQJDAAAAA==.',
Ap='Apeth:BAAANQADCgEIAQAAAA==.Applepi:BAAANQAECgUICgAAAA==.Aproditee:BAAANQADCgMIBAAAAA==.',
Ar='Areayl:BAABNQAECoEXAAIIAAgKYRgkLABLAgAIAAgKYRgkLABLAgAAAA==.Arinn:BAABNQAECoEcAAMFAAkKVh2rGQAwAgAFAAgKmxerGQAwAgAJAAcK2RhqXQDWAQAAAA==.',
As='Ashtkal:BAABNQAECoEcAAMHAAgKhCHbDwANAwAHAAgKhCHbDwANAwAKAAEKPRSmEAE/AAAAAA==.Ashtoes:BAAANQAECgcIDwAAAA==.Astralbubble:BAAANQAECgYJEAAAAA==.',
Au='August:BAAANQADCggIEAAAAA==.Auratic:BAAANQADCgcIBwAAAA==.Automation:BAAANQADCgcIDwABNQAECgkJHAAEAOkiAA==.',
Av='Avalea:BAAANQADCgUIBwAAAA==.',
Ay='Ayahuascå:BAAANQAECggIEAAAAA==.Ayyvlaad:BAAANQAECgUICgAAAA==.',
Az='Azerlite:BAAANQAECgIIAgABNQAECggJIgACAJQZAA==.Azkota:BAAANQAECgYJDgAAAA==.Azulwall:BAAANQAECgMIBAAAAA==.Azureros:BAAANQAECgcJEwAAAA==.',
Ba='Bandaayd:BAAANQAECgEIAQAAAA==.Bargaug:BAAANQADCgYJBgABNQAECgcIEwABAAAAAA==.Bathasar:BAAANQAECgUJCAAAAA==.Bathpally:BAAANQAECgUJCwAAAA==.',
Be='Beandh:BAAANQADCggIEAABNQAFFAUIBwALAFIEAA==.Beanygene:BAAANQAECgUIBQAAAA==.Beastfury:BAAANQAECgYIDgAAAA==.Beefyclap:BAAANQAECgQJDAAAAA==.Begal:BAABNQAFFIEHAAMMAAQKewMtCADhAAAMAAMKggQtCADhAAAIAAEKNwYxHQBOAAAAAA==.Beha:BAAANQADCgEIAQAAAA==.Beleria:BAAANQADCgMIAwAAAA==.Bellaidd:BAABNQAECoEVAAINAAgKgw7QEAB/AQANAAgKgw7QEAB/AQAAAA==.Bellore:BAAANQADCgQJBAAAAA==.Benedîct:BAAANQADCgIIAgAAAA==.Bewblywoobly:BAAANQAECgQICgAAAA==.Bezvoker:BAAANQADCgUIBQAAAA==.Beástboy:BAAANQAECgYJDAAAAA==.',
Bi='Biekdafreak:BAAANQAECgYJBgAAAA==.Bigbackmoto:BAAANQADCgMIAwAAAA==.Bigbuffalo:BAAANQADCgYJCQAAAA==.Bigdaddoo:BAAANQADCgUIBQAAAA==.Biggbob:BAAANQADCgYJBgAAAA==.Biggisign:BAAANQAECgQICQAAAA==.Bina:BAAANQADCggICAAAAA==.Bitemenow:BAAANQAECgMJAwAAAA==.Bitsobacon:BAAANQAECgUICAAAAA==.Bizzó:BAAANQAECgEJAQAAAA==.',
Bl='Bladeboy:BAAANQABCgIIAgAAAA==.Blamblam:BAAANQADCgQIBAAAAA==.Blambussi:BAAANQADCgcIEgAAAA==.Blitzball:BAAANQAECgEIAQAAAA==.Blooddragoon:BAAANQAECgQICQAAAA==.Bloodycrow:BAAANQABCgMIAwAAAA==.',
Bo='Bohica:BAAANQAECgcIEgAAAA==.Bombadil:BAAANQAECgQIBgAAAA==.Bomberdeath:BAAANQAECgUJCgAAAA==.Bongrip:BAAANQAECggIAwAAAA==.Boochstorm:BAAANQADCggIDAAAAA==.Boogiee:BAAANQAECgIJAgABNQAECgcIEwABAAAAAA==.Boons:BAAANQADCgIIAgABNQAECggIGQAOADIhAA==.Boosh:BAAANQADCgYICAAAAA==.Boostednub:BAAANQABCgYIDAAAAA==.',
Br='Bradington:BAAANQAECgQJBwAAAA==.Brezel:BAAANQADCgYIBgAAAA==.Briko:BAAANQABCgEIAQABNQAECgEIAwABAAAAAA==.Brond:BAAANQABCgIIAgAAAA==.Brontide:BAAANQAECgYJCwAAAA==.Bruengar:BAAANQAECgYIEgAAAA==.Bruniik:BAAANQAECgcICwAAAA==.',
Bu='Bubblehêarth:BAAANQAECgQICAAAAA==.Budapest:BAABNQAECoEaAAIHAAgKLhjMIwCBAgAHAAgKLhjMIwCBAgAAAA==.Buddyolpal:BAAANQAECgQIBwAAAA==.Bumbleh:BAAANQAECgQIBgAAAA==.Bumibe:BAAANQADCgcIBwAAAA==.Bungulator:BAABNQAECoEiAAICAAgKlBmgLABdAgACAAgKlBmgLABdAgAAAA==.Buné:BAABNQAECoEZAAIOAAgKMiGVAgDvAgAOAAgKMiGVAgDvAgAAAA==.Butkus:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Ca='Caad:BAAANQAECgMJAwAAAA==.Cador:BAAANQAECgQIBwAAAA==.Cadwarr:BAAANQADCgYIBgAAAA==.Cak:BAAANQADCgUIBwABNQAECgIIAwABAAAAAA==.Cam:BAAANQAECgMIBQAAAQ==.Camazotz:BAAANQADCgMIAgAAAA==.Cannibubz:BAAANQAECgMJBAAAAA==.Cannimal:BAABNQAECoEaAAIPAAkKpB5tDwAWAwAPAAkKpB5tDwAWAwAAAA==.Cataylst:BAAANQAECgEJAgAAAA==.Catwilliams:BAABNQAECoEZAAIQAAkKzRw6BwADAwAQAAkKzRw6BwADAwAAAA==.',
Ce='Celestas:BAAANQADCgIIAgAAAA==.',
Ch='Cheeze:BAAANQADCgcICwAAAA==.Chiliwop:BAAANQAECgYIEAAAAA==.Chippydk:BAAANQADCgYICAAAAA==.Chippyh:BAAANQAECgYJEgAAAA==.Chippym:BAAANQADCgQIBAAAAA==.Chloei:BAAANQAFFAEIAQAAAA==.Chwonk:BAAANQAECgUJCAAAAA==.',
Ci='Cik:BAAANQABCgQIBAAAAA==.Circê:BAAANQAECgEIAgAAAA==.Cirin:BAAANQAECgIIAgAAAA==.',
Cl='Cleaved:BAAANQAECgQIBAAAAA==.Clevoker:BAABNQAECoEeAAIRAAgKFiNkBAAsAwARAAgKFiNkBAAsAwAAAA==.Cloacussy:BAAANQADCgYIBgAAAA==.Cloudystorm:BAAANQAECgEIAQAAAA==.Clusion:BAAANQAFFAIIAgAAAA==.',
Co='Codex:BAAANQAECgYJDgAAAA==.Cole:BAAANQADCggIDAAAAA==.Conanb:BAAANQABCgIIAgAAAA==.Conductor:BAABNQAECoEgAAISAAgK4B6EAAAIAwASAAgK4B6EAAAIAwAAAA==.Convergent:BAAANQAECgcIEgAAAA==.Coosh:BAACNQAFFIEHAAIEAAUKbxPlCgCvAQAEAAUKbxPlCgCvAQA1AAQKgR4AAgQACQrcISkZAFMDAAQACQrcISkZAFMDAAAA.Corov:BAAANQAECgQIBQAAAA==.Courigon:BAAANQAECgEIAQAAAA==.Cowish:BAAANQADCgcICAAAAA==.',
Cp='Cptamerica:BAABNQAECoEYAAIHAAkKux3WCwAzAwAHAAkKux3WCwAzAwAAAA==.',
Cr='Craigolas:BAAANQAECgQIBQAAAA==.Crippler:BAAANQAECgUJBQAAAA==.Crossbow:BAAANQADCgMIBwAAAA==.Crosscut:BAAANQAECgEIAQAAAA==.Cruelty:BAAANQAECgMIAwAAAA==.Cröw:BAAANQABCgMIAwABNQABCgYICAABAAAAAA==.',
Cu='Cummins:BAABNQAECoEiAAIQAAkKax9GBwACAwAQAAkKax9GBwACAwAAAA==.Currents:BAAANQADCggICAAAAA==.',
Da='Dadstealer:BAAANQAECgQJBgAAAA==.Daemonwing:BAAANQADCgMIAwAAAA==.Dagrundel:BAAANQAECgUICgAAAA==.Dalinarix:BAAANQAECgIJAwAAAA==.Dankpope:BAAANQAECgIIAgAAAA==.Darkballs:BAAANQAECgEJAQABNQAECgQIBgABAAAAAA==.Dasbink:BAAANQADCgYJBgAAAA==.Davrin:BAABNQAECoEZAAQTAAgK7RqiGgCLAQAKAAYKIx2laQDAAQATAAYKaBaiGgCLAQAHAAMKCAnQrQCbAAAAAA==.',
De='Deathbyarow:BAAANQAECgUICgAAAA==.Deathhammer:BAAANQAECgQJCQAAAA==.Deathjrak:BAAANQAECgYJEwAAAA==.Deesixxfour:BAAANQADCgUIBQABNQAECggJGwAUACkkAA==.Degates:BAAANQAECgIIAgAAAA==.Demonia:BAAANQAECgQIBgAAAA==.Demonicshoes:BAAANQAECgMIAwAAAA==.Dethwing:BAAANQAECgYJEAAAAA==.Devaña:BAAANQAECgUICQAAAA==.',
Di='Diclonius:BAAANQAECgQIBwAAAA==.Dildas:BAAANQADCgYIBgAAAA==.Dirtystaff:BAAANQAECgMIAwAAAA==.Dirtzmage:BAAANQAECgUIDAAAAA==.Dirtzz:BAAANQADCgQIBAAAAA==.Dizzledh:BAAANQAECgQIBwAAAA==.Dizzranger:BAAANQAECgUIBQAAAA==.',
Dj='Djkhaledd:BAAANQAECgcJDQAAAA==.',
Do='Doobins:BAAANQAECgUJCAAAAA==.Dookiboy:BAAANQADCggJDgABNQAECggIEAABAAAAAA==.Doomedstar:BAAANQADCgEIAQABNQAECggIIAASAOAeAA==.Dooy:BAAANQAECgUJCAAAAA==.Douii:BAAANQADCggICAAAAA==.',
Dr='Draco:BAAANQABCgQICAAAAA==.Draconir:BAAANQABCgYICAAAAA==.Dragao:BAAANQADCgYIBgAAAA==.Draggen:BAABNQAECoEUAAIRAAYKFx5tEAD1AQARAAYKFx5tEAD1AQAAAA==.Dragimal:BAAANQAECgQIBQAAAA==.Dragonn:BAAANQAECgQICAAAAA==.Dragonoied:BAAANQADCgMIAwAAAA==.Dragonxlord:BAAANQAECgQIBAAAAA==.Dragosia:BAABNQAECoEoAAQVAAgK8QyyGADBAQAVAAgK8QyyGADBAQAWAAIKTRHJEwBqAAARAAEKXga4LgA0AAAAAA==.Drakojangens:BAAANQAFFAEJAQAAAA==.Drakthar:BAAANQADCggIFAAAAA==.Dranoric:BAAANQADCggIDAABNQAECggJGAAUAAcWAA==.Dreebus:BAAANQADCgYIBgABNQAECggIGQAXAAEKAA==.Drev:BAAANQADCgQIBQAAAA==.Drlawyerphd:BAABNQAECoEYAAIYAAcKGxjLEgAhAgAYAAcKGxjLEgAhAgAAAA==.Druz:BAAANQAECgQIBgAAAA==.',
Ds='Dsixfoour:BAAANQAECgEJAQABNQAECggJGwAUACkkAA==.Dsixxfour:BAABNQAECoEbAAIUAAgKKSROGgAaAwAUAAgKKSROGgAaAwAAAA==.',
Du='Duncedivh:BAAANQADCggIFgAAAA==.Dunzjan:BAAANQAECgYJDwAAAA==.Durrinn:BAAANQADCgcIBwABNQAECgcJEgABAAAAAA==.',
Dy='Dysmai:BAAANQADCgYICwAAAA==.',
['Dé']='Déathwolf:BAAANQAECgYIEgAAAA==.',
Ea='Eatsammich:BAAANQADCggIEQAAAA==.',
Eg='Eggsbenedïct:BAAANQAECgcJEQAAAA==.Egol:BAABNQAECoEbAAMQAAgKHSTzCQDPAgAQAAcKLCTzCQDPAgAPAAEKHBnTfABAAAAAAA==.',
El='Eldonra:BAAANQADCgYIBgABNQAFFAUIBwAUACIHAA==.Elidrine:BAAANQAECgQIBAAAAA==.Elmerfuddz:BAAANQAECgYJDgAAAA==.Elyrayldin:BAAANQAECgUJCAAAAA==.',
En='Enazenoth:BAABNQAECoEYAAIRAAkKFCJqAwBOAwARAAkKFCJqAwBOAwAAAA==.Enryu:BAAANQAECgcIDAAAAA==.Envburnz:BAAANQAECgQJBAAAAA==.',
Er='Erooka:BAABNQAECoEaAAIEAAgKBh8iOgDdAgAEAAgKBh8iOgDdAgAAAA==.',
Es='Esio:BAABNQAECoEXAAIUAAgKMhDoaADTAQAUAAgKMhDoaADTAQAAAA==.',
Ev='Evileyes:BAAANQADCgUIBQABNQADCggJCAABAAAAAA==.',
Ey='Eyri:BAABNQAECoEZAAIEAAgK0gxWkADuAQAEAAgK0gxWkADuAQAAAA==.',
Ez='Ezzie:BAAANQAECgQIBwAAAA==.',
Fa='Falsodew:BAABNQAECoEaAAIGAAkKPhhWKgBYAgAGAAkKPhhWKgBYAgAAAA==.',
Fe='Felicity:BAAANQAECgUJDQAAAA==.Femme:BAAANQAECgIJAgAAAA==.Femmever:BAAANQAECgEIAQAAAA==.Feonix:BAABNQAECoEeAAIEAAgKMyDcLwD/AgAEAAgKMyDcLwD/AgAAAA==.Ferenus:BAAANQABCggICgAAAA==.Fewsha:BAACNQAFFIERAAICAAYK2B46AQBAAgACAAYK2B46AQBAAgA1AAQKgSAAAgIACQrnJMYFAKIDAAIACQrnJMYFAKIDAAAA.',
Fi='Fidellia:BAAANQAECgUIBwAAAA==.Findie:BAAANQAECgUICQAAAA==.',
Fl='Fleshoflìght:BAAANQADCgIJAgAAAA==.',
Fo='Foofoolala:BAAANQADCgYJDgAAAA==.Fookadk:BAAANQADCggJGQAAAA==.Fookapalli:BAAANQABCgYICgAAAA==.Forttoo:BAAANQADCgEIAQAAAA==.Fourthwing:BAAANQADCgQIBAAAAA==.',
Fr='Frawstbyte:BAABNQAECoEeAAIEAAgKlho0WwB7AgAEAAgKlho0WwB7AgAAAA==.Fredbearr:BAAANQADCgMIAwAAAA==.Freeholed:BAABNQAECoEaAAIZAAgKUxvYGACiAgAZAAgKUxvYGACiAgAAAA==.Fridgefister:BAAANQAECgYJCgAAAA==.Frodie:BAAANQAECgcIDgAAAA==.',
Fu='Fumina:BAAANQAECgEIAQAAAA==.',
Ga='Gaea:BAAANQAECgYJDgAAAA==.Gallanon:BAAANQADCgcJDgAAAA==.Gallshot:BAAANQADCgUICgAAAA==.Gamergirl:BAAANQABCgcIBwAAAA==.Gangrêl:BAAANQADCgYIDAABNQAECgEIAQABAAAAAA==.Garithor:BAAANQADCgYICQAAAA==.',
Gb='Gbang:BAAANQAECgIIAwAAAA==.',
Ge='Gekidoryu:BAAANQADCgQIBAABNQAECgUIBQABAAAAAA==.Gerebert:BAAANQAECgQICQAAAA==.Getajobubum:BAAANQAECgcJEgAAAA==.',
Gh='Ghalizor:BAAANQADCgYIBgABNQAECgIIAwABAAAAAA==.Ghostdance:BAACNQAFFIEIAAIEAAUKLRuFCADOAQAEAAUKLRuFCADOAQA1AAQKgSAAAgQACQotJN0OAIMDAAQACQotJN0OAIMDAAAA.Ghoulia:BAAANQADCggJGgAAAA==.',
Gi='Giggz:BAAANQAECgQIBwAAAA==.Gingerpala:BAAANQADCgQJBwAAAA==.Giuttrix:BAAANQAECgQJBAAAAA==.',
Gl='Glacie:BAAANQAECgEIAgAAAA==.Gleams:BAAANQAECgQIBwAAAA==.Gloriousdead:BAAANQADCgYIBgAAAA==.Glowing:BAAANQAECgUIBQAAAA==.',
Go='Gokukakarot:BAAANQAECgIJAwAAAA==.Goldeneyes:BAAANQABCgIJAgAAAA==.Goldlore:BAAANQAECgMJBAAAAA==.Gonger:BAAANQAECgQIBAAAAA==.Goopdk:BAAANQAECgQJCQAAAA==.Gosiâ:BAAANQAECgMIBAABNQAECggIKAAVAPEMAA==.Gothikia:BAAANQAECgUJCAAAAA==.',
Gr='Gremhunt:BAAANQAECgIIAgAAAA==.Grondel:BAAANQAECgUIBwAAAA==.Grumpybear:BAAANQADCgcIDwAAAA==.',
Gu='Gundham:BAAANQAECgMIAwAAAA==.Gunko:BAAANQAECgQJBwAAAA==.Gunstrong:BAAANQAECgQJBgAAAA==.',
['Gõ']='Gõsia:BAAANQAECgQIBAAAAA==.',
['Gø']='Gøtt:BAAANQADCgIIAgAAAA==.',
Ha='Haagendots:BAAANQAECgQIBwAAAA==.Hadokens:BAAANQADCggJCAAAAA==.Hairofwar:BAAANQAECgYIEgAAAA==.Haleynicole:BAAANQAECgQIBwAAAA==.Happydaug:BAAANQADCgcICwABNQAECgkJHAAaAGMeAA==.Happydawg:BAABNQAECoEcAAIaAAkKYx4ICQD7AgAaAAkKYx4ICQD7AgAAAA==.Hasted:BAABNQAECoEcAAIEAAkK6SJ6EQB2AwAEAAkK6SJ6EQB2AwAAAA==.Hawktar:BAAANQAECgcJEwAAAA==.',
He='Healimus:BAAANQAECgcJEwAAAA==.Healmates:BAAANQAECgYICQAAAA==.Helix:BAABNQAECoEhAAIGAAkKiR2mEgDxAgAGAAkKiR2mEgDxAgAAAA==.Hennybull:BAAANQADCgIIAgAAAA==.Henný:BAAANQADCgQIBAAAAA==.Hesperos:BAAANQADCggIEQAAAA==.',
Ho='Ho:BAAANQAECgcIBwAAAA==.Hoffzz:BAAANQADCgIIAQAAAA==.Holee:BAAANQADCgYJBwAAAA==.Holybaby:BAAANQAECgYIEgAAAA==.Holybrute:BAAANQAECgIIAwABNQAECggJGQAbANYXAA==.Holybunger:BAAANQAECgIIAwAAAA==.Holyscheisse:BAAANQAECggIAwABNQAECggIEAABAAAAAA==.Holysheetz:BAAANQABCgQIBAAAAA==.Horde:BAAANQADCgcICwAAAA==.',
Hu='Hueycheeks:BAABNQAECoEdAAIcAAkKpBqaBQD3AgAcAAkKpBqaBQD3AgAAAA==.Humantelope:BAAANQABCgUICAABNQAECgQJCQABAAAAAA==.Huntstatus:BAABNQAECoEaAAIJAAgKGRFdfQB2AQAJAAgKGRFdfQB2AQAAAA==.Huxium:BAABNQAECoEYAAIJAAcKRBSVTgAGAgAJAAcKRBSVTgAGAgAAAA==.',
Hw='Hwangdoyoung:BAAANQABCgEIAQABNQADCgEJAQABAAAAAA==.',
Hy='Hymnpossible:BAAANQAECgYJCwAAAA==.',
Ic='Icecreamdveg:BAAANQABCgYJCAAAAA==.Icetongue:BAAANQAECgYJEQAAAA==.',
If='Iflingpoo:BAABNQAECoEZAAIXAAgKgxprIwA7AgAXAAgKgxprIwA7AgAAAA==.Ifusêekamy:BAAANQAECgMJAwAAAA==.',
Ij='Ijrakwarrior:BAAANQAECgIIAgAAAA==.',
Il='Illidussy:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Illregularxx:BAAANQAECgIIAgAAAA==.',
Im='Impulse:BAAANQAECgYIEQAAAA==.',
In='Indelebi:BAAANQABCgQIBgAAAA==.Inorgeing:BAAANQAECgMIBAAAAA==.Intrúder:BAAANQADCgEIAQAAAA==.',
Ir='Irdaman:BAAANQAECgEIAQABNQAECgYIEQABAAAAAA==.Irmengaud:BAAANQAECgQIBQAAAA==.Ironpup:BAAANQAECgYICwAAAA==.Ironscales:BAAANQAECgQIAQAAAA==.',
Ja='Jabbyjr:BAABNQAECoEeAAMdAAgK8RBXBwD7AQAdAAgK8RBXBwD7AQAUAAEKTQ18+AA3AAAAAA==.Jabum:BAAANQAECgcICgAAAA==.Jaio:BAAANQAECgQIBAAAAA==.Jajakuna:BAAANQAECgQIBQAAAA==.Jangens:BAAANQAFFAEIAQABNQAFFAEJAQABAAAAAA==.Jarofsomethi:BAAANQAECgUJCQAAAA==.Jaruni:BAAANQAECgYIEgAAAA==.Jaynine:BAABNQAECoEaAAMMAAgKyBiXFQBIAgAMAAcKaBqXFQBIAgAIAAMKXRe3fwDcAAAAAA==.',
Je='Jeffvyrt:BAAANQAECgQIBwAAAA==.Jeksulee:BAAANQABCggIEAAAAA==.',
Ji='Jibbs:BAAANQAECgUIBQAAAA==.',
Jo='Jodimaw:BAAANQADCggICAAAAA==.Jorian:BAAANQADCgIIAgABNQAECgEJAgABAAAAAA==.Joridiezs:BAAANQAECgMJBAAAAA==.Joshness:BAAANQADCgMIAwAAAA==.',
Ju='Juanrambo:BAAANQAECgQJCAAAAA==.Juicyjohnson:BAAANQADCgMIBQABNQAECgcIEQABAAAAAA==.Jumblo:BAAANQAECgQIBwAAAA==.Jupileo:BAAANQAECgYIDQAAAA==.Jurassichots:BAAANQADCggIDwAAAA==.',
Ka='Kaalista:BAAANQAECgEJAwABNQAECggIEwABAAAAAA==.Kailee:BAACNQAFFIEMAAIaAAUKRyFFAgDPAQAaAAUKRyFFAgDPAQA1AAQKgSIAAhoACQqEJe0BALEDABoACQqEJe0BALEDAAE1AAQKAQkBAAEAAAAA.Kaito:BAAANQAECgEIAQAAAA==.Kakaboy:BAAANQADCgMIAwABNQAECggIEAABAAAAAA==.Kaolis:BAAANQADCggICQAAAA==.Kariba:BAABNQAECoEYAAIMAAkKGR31BwAwAwAMAAkKGR31BwAwAwABNQAECgkJJQAZABUlAA==.Karmana:BAAANQAECggIDwAAAA==.Katael:BAAANQADCgYICwAAAA==.Kavel:BAABNQAECoEYAAMEAAkKsBU+XQB2AgAEAAkK6hM+XQB2AgASAAEKiBEgBwBOAAAAAA==.Kaylie:BAAANQAECgEJAQAAAA==.Kayti:BAAANQAECgUJCAAAAA==.',
Ke='Kelfiona:BAAANQADCggJHAAAAA==.Keraboo:BAAANQAECgUJCgAAAA==.Kerie:BAAANQAECgQICQAAAA==.Kesleya:BAAANQADCgQIBAAAAA==.Ketamyne:BAAANQADCggIFgAAAA==.Keynin:BAAANQADCgUIBQAAAA==.',
Kh='Khalu:BAAANQADCgEIAQAAAA==.',
Ki='Kiandron:BAAANQADCgYIDgAAAA==.Killerqtlol:BAAANQADCggIGAABNQAECggIGQAGAKUZAA==.Kimbostab:BAAANQADCgMIBAAAAA==.',
Kn='Knockbak:BAAANQAECgQJBQAAAA==.',
Ko='Kohko:BAAANQADCgYIBgAAAA==.Kozinirus:BAAANQAECgQIBQAAAA==.',
Kq='Kqmav:BAAANQAECgcJEAAAAA==.',
Kr='Kromewell:BAAANQAECgEIAQAAAA==.Kromwell:BAAANQADCgQIBQAAAA==.Kruwll:BAAANQAECgQIBAAAAA==.Krít:BAAANQAECgQIBAABNQADCgQIBAABAAAAAA==.',
Ku='Kumolock:BAAANQAECgYJDgAAAA==.Kuntissimo:BAAANQADCggICAABNQAECgYIDgABAAAAAA==.Kuongsun:BAAANQADCggIEgAAAA==.',
['Kú']='Kúrama:BAAANQABCgYICAAAAA==.',
La='Ladeehunter:BAAANQAECgUJCwAAAA==.Lambsbreath:BAAANQADCggIEAAAAA==.Lanto:BAAANQADCgUICAABNQABCgIIAgABAAAAAA==.Laprofessora:BAAANQADCggICAAAAA==.Laquince:BAAANQAECgQICQAAAA==.Lasagnazaddy:BAAANQADCgYICwAAAA==.Laurafel:BAAANQAECgQIBAAAAA==.',
Le='Leetlee:BAAANQADCgMIAwAAAA==.Lelouché:BAAANQABCgIIAgABNQABCgYICAABAAAAAA==.Lertglochen:BAAANQAECgMJCQAAAA==.Lexistarr:BAEANQAECgQIBQAAAA==.',
Li='Lickmelow:BAAANQADCgEIAQAAAA==.Lightbunz:BAAANQADCgQJBAAAAA==.Lightcast:BAAANQAECgIIAgABNQAECgkJGwAQADIfAA==.Lightra:BAAANQAECgIJBQAAAA==.Limeywater:BAAANQAECgcJEwAAAA==.Lindramech:BAAANQADCgYIBgAAAA==.Liquedz:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.Litherous:BAAANQAECgYIDAAAAA==.Litzdh:BAAANQAECgQJCQAAAA==.',
Ll='Llazereth:BAABNQAECoEZAAIXAAgKAQpJRgBtAQAXAAgKAQpJRgBtAQAAAA==.Llordvalar:BAAANQADCgIJAgAAAA==.',
Lo='Lockimar:BAEBNQAECoEVAAQbAAgKvAvvVwDEAQAbAAgKvAvvVwDEAQAeAAQK0wWBNgDEAAAfAAEKVA/OIgA1AAAAAA==.Lockuru:BAABNQAECoEcAAMeAAgKwR4HGwB5AQAbAAYKtB58QAAbAgAeAAYKOw4HGwB5AQAAAA==.Lonestàr:BAAANQAECgQJCQAAAA==.Lowiqslowirl:BAAANQABCgIIAgAAAA==.',
Lu='Lucidy:BAAANQAECgYIBwAAAA==.Lumberjacked:BAAANQAECgQIBQABNQAECgkJFgAOAIAhAA==.Luna:BAAANQADCgYJDQABNQAECggIFAAbACMaAA==.Luspriest:BAAANQADCgQIBAAAAA==.Lusuffer:BAABNQAECoEYAAIXAAgKSSBCEQDdAgAXAAgKSSBCEQDdAgAAAA==.Lusufferr:BAAANQADCgYIEgABNQAECggJGAAXAEkgAA==.Lutra:BAABNQAECoEZAAIgAAgKEhKEEAD1AQAgAAgKEhKEEAD1AQAAAA==.',
Ly='Lyx:BAAANQAECgUICgAAAA==.',
Ma='Magerpwn:BAAANQADCgUIBQAAAA==.Magusarcanus:BAAANQADCgYIBgAAAA==.Makrio:BAAANQABCgUJBwAAAA==.Malachî:BAAANQAECgIJAgAAAA==.Malitan:BAABNQAECoEgAAIKAAkKzRavPwBUAgAKAAkKzRavPwBUAgAAAA==.Mamif:BAAANQAECgQIBwAAAA==.Manfrony:BAAANQADCggICAABNQAECgYJDgABAAAAAA==.Mannasto:BAAANQADCgYIBgAAAA==.Manuelek:BAAANQAECgEIAQAAAA==.Markatron:BAAANQAECgYICwAAAA==.Mattiekay:BAAANQAECgcJEwAAAA==.Maxx:BAAANQAECgYJBgAAAA==.Mañajuana:BAABNQAECoEZAAMNAAgKOxaFCgAGAgANAAgKOxWFCgAGAgAPAAYKohA2RwBLAQAAAA==.',
Me='Meatrocket:BAAANQADCgYIBgABNQAECggJHgARABYjAA==.Meefalo:BAAANQAECgUIDQAAAA==.Meganfox:BAAANQAECgcJBwAAAA==.Meggfox:BAAANQADCgQIBAAAAA==.Meghanics:BAAANQAECgEIAQAAAA==.Meileen:BAAANQADCgEIAQAAAA==.Mendwyn:BAAANQABCgUJBQAAAA==.Menethol:BAAANQADCgUIBQABNQAECgcIKgAEAK0bAA==.Mercymage:BAAANQAECgMIAwAAAA==.Merie:BAAANQADCgUJBQABNQAECgUJCwABAAAAAA==.Merlinswrath:BAAANQADCgYJBAAAAA==.Merril:BAAANQABCgcICgABNQAECgkJIgAVAL4eAA==.Merza:BAAANQADCggJDAABNQAECgkJHQAhAC8cAA==.Merzinator:BAABNQAECoEdAAMhAAkKLxyHDQDcAgAhAAkKLxyHDQDcAgALAAIKdwEgYQA2AAAAAA==.',
Mi='Mickle:BAAANQAECgQJBAAAAA==.Midgrad:BAAANQADCggIDgABNQAECgUJDAABAAAAAA==.Mikelowry:BAAANQAECgYICgAAAA==.Minimum:BAAANQAECgQIBAABNQAECgUIBQABAAAAAA==.Mischeveous:BAAANQAECgUICwAAAA==.Missu:BAAANQADCgEJAQAAAA==.Mithrandir:BAAANQAECgcJEgAAAA==.',
Mj='Mjiltanke:BAAANQAECgUJCAAAAA==.',
Mo='Moistcarry:BAAANQADCgUIBQAAAA==.Mokniahiah:BAAANQAECgUIDAAAAA==.Monkmates:BAAANQAECgEIAQAAAA==.Moodoon:BAAANQAECgIIAgAAAA==.Moohammadali:BAAANQADCgYJBgAAAA==.Mooseyfate:BAAANQAECgUJCQAAAA==.Moraxy:BAAANQAECgUIBwAAAA==.Moromagus:BAABNQAECoEeAAIEAAgK/hX+cgA6AgAEAAgK/hX+cgA6AgAAAA==.Mortis:BAAANQAECgUJCQAAAA==.Motorboats:BAAANQADCgYIDgAAAA==.',
Mu='Mualpractice:BAAANQADCgQIBQAAAA==.Murdok:BAAANQAECgYIBwAAAA==.Murray:BAAANQAECgcIDQABNQAFFAUJCgAXAOEKAA==.Mutknodeprac:BAAANQAECgQIBwAAAA==.',
Mx='Mxsery:BAAANQAECgUIBwAAAA==.Mxz:BAAANQADCgcIBwABNQAECggJIgACAJQZAA==.',
My='Myræl:BAAANQAECgYJCQAAAA==.Mystíle:BAABNQAECoEjAAIZAAkKJCXFAgC+AwAZAAkKJCXFAgC+AwAAAA==.Mythrix:BAAANQABCgIIAgABNQADCgcIEQABAAAAAA==.Mythrixx:BAAANQADCgcIEQAAAA==.',
['Mà']='Màjíque:BAAANQAECgQJCQAAAA==.',
['Mé']='Méadow:BAAANQADCggIFgAAAA==.',
['Mö']='Mötley:BAAANQADCggICAAAAA==.',
Na='Nabesan:BAAANQADCgIIAgAAAA==.Naked:BAAANQADCggIBAAAAA==.Nalera:BAAANQAECggIBwAAAA==.Nanoboostme:BAAANQADCgYJBgAAAA==.Narhi:BAAANQAECgQIBwAAAA==.Nasminthe:BAAANQAECgEIAQAAAA==.Nature:BAAANQADCgUIBQAAAA==.Naughtya:BAAANQAECgQJCAAAAA==.Nazem:BAAANQAECgQIBQAAAA==.',
Ne='Nekoro:BAABNQAECoEZAAQbAAcK1hcYQgAVAgAbAAcK1hcYQgAVAgAfAAIK4Qn7FgBqAAAeAAEKCAULZAA5AAAAAA==.Nelfsquantch:BAAANQAECgQJBAAAAA==.Nevadawolf:BAAANQAECgQIBgAAAA==.',
Ni='Nightreaver:BAAANQAECgEJAQAAAA==.Nightshiftér:BAAANQAECgEJAgAAAA==.Nimbex:BAAANQADCgQIBAAAAA==.Ninetailsfox:BAAANQAECgcIEAABNQAECggIEAABAAAAAA==.Nion:BAAANQAECgYJDgAAAA==.Nippy:BAAANQADCggIDAABNQAECgUJBgABAAAAAA==.',
No='Nolo:BAAANQADCgQIBQAAAA==.Northzen:BAAANQAECgcIDwAAAA==.Notaorc:BAAANQADCgUIBQAAAA==.Notmyconcern:BAAANQADCgYJBgAAAA==.Novaflux:BAABNQAECoEbAAIEAAgKwiB4MwDzAgAEAAgKwiB4MwDzAgAAAA==.Noxxicc:BAAANQAECgQIBwABNQAECggJHgAGAHsfAA==.',
Ny='Nyghtterror:BAAANQAECgEIAQAAAA==.Nyreeh:BAAANQAECgMIAwAAAA==.Nytearcher:BAAANQAECgcJEQAAAA==.Nyxa:BAAANQAECgIIAwAAAA==.',
['Ná']='Nálera:BAAANQADCggIDgAAAA==.',
['Nü']='Nüguns:BAAANQAECgIJAgAAAA==.',
Ok='Okamifist:BAAANQADCgYIBgAAAA==.Oklyra:BAAANQABCgYICgAAAA==.',
Om='Omnia:BAABNQAECoEYAAMGAAgKEA/WSgC+AQAGAAgKEA/WSgC+AQACAAcK7QVocgA9AQABNQADCgEIAQABAAAAAA==.Omrath:BAAANQADCgUJBQABNQABCgIIAgABAAAAAA==.',
On='Onlyshams:BAAANQAECgQIBAAAAA==.',
Oo='Oogiee:BAAANQAECgcIEwAAAA==.',
Or='Orcmonk:BAAANQADCgcIDgAAAA==.Orthoganal:BAAANQAECgEIAQAAAA==.',
Os='Oschun:BAABNQAECoEdAAIKAAgK/BqGQgBJAgAKAAgK/BqGQgBJAgAAAA==.',
Pa='Palacandia:BAAANQADCgYIBQAAAA==.Palanar:BAABNQAECoEeAAMZAAgKOiNXFADNAgAZAAcKsCNXFADNAgAiAAQKASH9LQCDAQAAAA==.Palle:BAAANQAECgcJDQAAAA==.Pallyboi:BAAANQAECgQJCQAAAA==.Paluru:BAAANQAECgEIAQABNQAECggJHAAeAMEeAA==.Panosh:BAAANQADCgUIBQAAAA==.Pantricelog:BAAANQADCggICAABNQAECggJGAAQAEQYAA==.',
Pc='Pchef:BAAANQAECgQIBgAAAA==.',
Pe='Pelayo:BAAANQAECgMIAwABNQAECgQIBAABAAAAAA==.Peperoninips:BAAANQAECgIIBAAAAA==.Petricia:BAABNQAECoEYAAIQAAgKRBjOEQBMAgAQAAgKRBjOEQBMAgAAAA==.',
Pf='Pfeffer:BAAANQAECgUJBgAAAA==.',
Ph='Phaithful:BAACNQAFFIEIAAIMAAQKMxawBABcAQAMAAQKMxawBABcAQA1AAQKgR0AAwwACQqvHpAKAAEDAAwACQqvHpAKAAEDACMAAQoLCakcADUAAAAA.Phazerman:BAAANQAECgcIDwAAAA==.Phocus:BAAANQAECgcIDAABNQAFFAQICAAMADMWAA==.Phury:BAAANQAECgYIBgABNQAFFAQICAAMADMWAA==.',
Pi='Pikapikapika:BAAANQAECgYIDwAAAA==.',
Pl='Planthoofem:BAAANQAECgEIAQAAAA==.Playpride:BAAANQAECgQJCQAAAA==.',
Po='Poboy:BAAANQAECgYICgAAAA==.Pocket:BAAANQAECgQIBAABNQAECggIFAAbACMaAA==.Pokepokepoke:BAAANQAECgUICQAAAA==.Poppop:BAAANQAECgQJCQAAAA==.Poriand:BAAANQAECgQJBQAAAA==.Portzul:BAAANQAECgEIAQAAAA==.',
Pr='Priesttea:BAAANQAECgEIAQAAAA==.Procology:BAAANQABCgEJAQAAAA==.',
Ps='Pseudogrim:BAAANQAECgcJEwAAAA==.Psspspss:BAAANQAECgQIBQAAAA==.',
Pu='Pugnosano:BAAANQADCgQIBAAAAA==.Pussnboots:BAAANQAECgQJCAAAAA==.',
['Pö']='Pöppop:BAAANQADCgcIDAABNQAECgQJCQABAAAAAA==.',
Ra='Raefe:BAAANQAECgUJCAAAAA==.Raffaj:BAAANQAECgQIBwAAAA==.Raidedww:BAAANQADCgUIBQAAAA==.Raihnese:BAEANQAECgUJCQAAAA==.Ramenveg:BAAANQAECgQICQAAAA==.Rancora:BAAANQAECgcJEgAAAA==.Ravnsifu:BAAANQADCgUIBQAAAA==.Ravnwing:BAAANQADCggIFQAAAA==.',
Re='Reapersbless:BAAANQAECgEIAgABNQAECgEIAgABAAAAAA==.Reapersbount:BAAANQAECgEIAgAAAA==.Reapersele:BAAANQADCgMIAwABNQAECgEIAgABAAAAAA==.Redbuffpls:BAACNQAFFIEGAAIKAAMKkRfZCAD3AAAKAAMKkRfZCAD3AAA1AAQKgSQAAgoACQqqJZcEAMADAAoACQqqJZcEAMADAAAA.Redbul:BAAANQAECgcIDAAAAA==.Redbullz:BAAANQADCgUIBQAAAA==.Reddrock:BAAANQADCggIDwAAAA==.Redstörm:BAAANQADCgcIBwAAAA==.Reffusul:BAAANQADCgMIAwABNQAECggJGAAXAEkgAA==.Reflexadín:BAAANQADCgcIBwAAAA==.Reilanna:BAAANQAECgcIBwAAAA==.Reptilia:BAABNQAECoEdAAIPAAgKLBq8GwCVAgAPAAgKLBq8GwCVAgAAAA==.Rewef:BAAANQAECgMIAwABNQAFFAYJEQACANgeAA==.Rex:BAABNQAECoEbAAIEAAkKACHHFQBhAwAEAAkKACHHFQBhAwAAAA==.',
Rh='Rhune:BAAANQADCgIIAgAAAA==.',
Ri='Rickylicky:BAAANQADCgIIAgAAAA==.Riffz:BAABNQAECoEeAAMkAAgKWxxYEgBwAgAkAAcKBh1YEgBwAgAYAAgKDBIdEgAqAgAAAA==.Rig:BAAANQAECgQIBAAAAA==.Rinzsha:BAAANQAECgQJCQAAAA==.Rishka:BAAANQADCgUIBQAAAA==.Riv:BAAANQADCggICAABNQAECgUJDAABAAAAAA==.Rivien:BAAANQAECgUJDAAAAA==.',
Ro='Roostersauce:BAAANQADCgYIBgAAAA==.Rosare:BAAANQADCgEIAQAAAA==.',
Ru='Ruhkouri:BAAANQAECgMJAwAAAA==.Rulez:BAAANQADCgQIBAAAAA==.Rustibox:BAACNQAFFIEOAAMbAAYKpxHZAwCkAQAbAAUK/hHZAwCkAQAeAAIKlw/OCACqAAA1AAQKgSsAAxsACQr5JLMCAKgDABsACQo0JLMCAKgDAB4ABAqzFDQiADsBAAAA.',
Sa='Saltdeeduck:BAAANQADCgQJBgAAAA==.Samardev:BAAANQADCgYIBgABNQAECgkJIgAVAL4eAA==.Sammichomg:BAABNQAECoEWAAIKAAcKzx9MPQBeAgAKAAcKzx9MPQBeAgAAAA==.Sammyfuego:BAAANQAECgQIBwAAAA==.Sarutko:BAAANQAECgUIBwAAAA==.',
Sc='Scalestas:BAAANQAECgYIEgAAAA==.Scoobies:BAAANQAECgQIBAABNQAFFAEIAQABAAAAAA==.',
Se='Searing:BAABNQAECoEaAAITAAkKFRkECwB4AgATAAkKFRkECwB4AgAAAA==.Segfaulted:BAAANQAECgUJCgAAAA==.Seleane:BAAANQAECgYIEgAAAA==.Sellvanya:BAAANQADCgQIBAAAAA==.Senyor:BAAANQAECgEIAQABNQAECgQICQABAAAAAA==.Seraphia:BAAANQADCgQIBAAAAA==.Sethcure:BAAANQAECgIIAgAAAA==.',
Sh='Shaadas:BAABNQAECoEbAAIIAAgKLhtxJAB0AgAIAAgKLhtxJAB0AgAAAA==.Shabazz:BAAANQAECgQIBAAAAA==.Shacklestorm:BAAANQAECgEJAQAAAA==.Shadeau:BAAANQAECgQIBAAAAA==.Shamackerd:BAAANQAECgUIBwAAAA==.Shampoo:BAAANQABCgUIBAAAAA==.Shandriss:BAAANQAECgIIAwAAAA==.Shawlen:BAAANQABCgIJAgAAAA==.Sheve:BAAANQADCgQJBAAAAA==.Shmimon:BAAANQAECgUJCAAAAA==.Shockapal:BAAANQAECgUICQAAAA==.Shockvalue:BAAANQAECgEJAQAAAA==.Shrimon:BAAANQADCgIIAgAAAA==.Shrimps:BAAANQAECgQJCwAAAA==.Shâokahn:BAAANQADCgYIBgAAAA==.',
Si='Sicell:BAAANQAECgUJBQAAAA==.Sidewinder:BAAANQAECgMJBAAAAA==.Siong:BAAANQAECgcICgAAAA==.Sitch:BAAANQADCgQJBQAAAA==.',
Sk='Skeletorz:BAAANQADCgYIDAAAAA==.Skunknmidget:BAAANQADCggIDgAAAA==.Skyvestris:BAAANQAECgIIAwAAAA==.',
Sl='Slamueladams:BAAANQADCgMIAwAAAA==.Slayberto:BAAANQAECgcJEwAAAA==.Sleepbringer:BAAANQAECgEIAQAAAA==.Sloppysecond:BAAANQADCgQIBAAAAA==.',
Sm='Smellmygas:BAAANQAECgQIBwAAAA==.Smoko:BAAANQAECgYJEQAAAA==.',
Sn='Sneaky:BAABNQAECoEWAAIIAAgK8RJWNAAgAgAIAAgK8RJWNAAgAgABNQAECgkJJQANAEUmAA==.Sneakyr:BAABNQAECoElAAINAAkKRSYvAAAABAANAAkKRSYvAAAABAAAAA==.Snoodle:BAAANQADCgYJBgAAAA==.Snypar:BAAANQAECgYIEgAAAA==.Snôva:BAAANQAECgQJCQAAAA==.',
So='Soaraga:BAAANQABCgQIBAAAAA==.Sodosopa:BAAANQADCgYIBgAAAA==.Solaire:BAAANQAECgIIBgAAAA==.Sole:BAAANQADCgcIBwABNQAECgUJCgABAAAAAA==.Soleim:BAAANQAECgUJCgAAAA==.Somavanna:BAAANQAECgQICQAAAA==.Sophara:BAAANQAECgUIBwAAAA==.Sorbet:BAABNQAECoEcAAIDAAgK5SNdAQA9AwADAAgK5SNdAQA9AwAAAA==.Soulgrinder:BAAANQAECgUJBQAAAA==.',
Sp='Sparden:BAAANQADCggICAAAAA==.Sparhawk:BAABNQAECoEeAAIKAAgKbSL4FwAdAwAKAAgKbSL4FwAdAwAAAA==.Sparklebolts:BAAANQADCgQIBAAAAA==.Speedwagon:BAAANQAECgUICwABNQAECgYIBgABAAAAAA==.Spicytotems:BAAANQAECgUIDgAAAA==.Spidercowsd:BAAANQADCgIJAgAAAA==.Spippy:BAAANQAECgQIBAAAAA==.Spitzer:BAAANQADCgEIAQAAAA==.Splõõsh:BAABNQAECoEeAAMGAAgKex9pQQDoAQAGAAYKUR1pQQDoAQACAAMKnBeTkwDnAAAAAA==.Spooky:BAAANQADCggJEwABNQAFFAUJCgAkAGseAA==.Spro:BAAANQAECgQIBAABNQAECgkJGgAkAK8XAA==.Sprogue:BAABNQAECoEaAAQkAAkKrxe4EACGAgAkAAgKrxm4EACGAgAOAAYK6Q4LCwBnAQAYAAEK1Q30PgA9AAAAAA==.Spronatty:BAAANQADCgIIAgAAAA==.Sprosport:BAAANQAECgUICQABNQAECgkJGgAkAK8XAA==.Sprø:BAAANQAECgEIAQABNQAECgkJGgAkAK8XAA==.Spurlock:BAAANQADCggIFwAAAA==.Spyrogos:BAAANQAECgQIBgAAAA==.',
Sq='Squidbits:BAAANQAECgQICAAAAA==.Sqwuanchigos:BAAANQADCggICAAAAA==.',
St='Stabsandhugs:BAAANQADCgQIBAAAAA==.Starclaw:BAABNQAECoEcAAIlAAkKNSMXAQCfAwAlAAkKNSMXAQCfAwAAAA==.Stasis:BAABNQAECoEYAAQHAAcKdQsecwA5AQAHAAYK7QgecwA5AQAKAAYKtgaTqAAYAQATAAEK3QgUSgA0AAAAAA==.Statixx:BAAANQADCgYIBgAAAA==.Stel:BAAANQAECgEIAQAAAA==.Stroonzy:BAAANQAECgIJAgAAAA==.Styrmir:BAAANQABCgQIBAAAAA==.',
Su='Sugarteets:BAAANQAECgUJCQAAAA==.Sujung:BAAANQADCgIJAwAAAA==.Sukubis:BAAANQADCgUIBQAAAA==.Supadope:BAAANQAECgQIBgAAAA==.Superpaladin:BAAANQAECgQJBQABNQAECgUJCQABAAAAAA==.',
Sy='Sydner:BAAANQAECgUJCAAAAA==.Synergize:BAAANQADCgMIAwAAAA==.Sythila:BAACNQAFFIEHAAILAAUKUgQ/BgAtAQALAAUKUgQ/BgAtAQA1AAQKgSAAAwsACQqLHhASALMCAAsACQpiHRASALMCACEABgo+GKInAK4BAAAA.',
['Sé']='Séamus:BAAANQADCgYIBgAAAA==.',
['Sü']='Süblime:BAAANQAECggJBgAAAA==.',
Ta='Tachichan:BAAANQADCgUIBQAAAA==.Tadertod:BAAANQAECggIDwAAAA==.Talleth:BAABNQAECoE1AAIRAAkKxCCiAgBrAwARAAkKxCCiAgBrAwAAAA==.Tallìsh:BAAANQADCgYICgAAAA==.Talorion:BAAANQAECgcIDAAAAA==.Tandrisell:BAAANQAECgEIAQAAAA==.Tarkyn:BAAANQADCgEIAQAAAA==.Tassyn:BAABNQAECoEZAAMYAAcKjRE1HwCTAQAYAAYK5hA1HwCTAQAkAAIKDQ5yUQB9AAAAAA==.Tattianna:BAAANQAECgQIBwAAAA==.Tazenezoth:BAABNQAECoEiAAIVAAkKvh5SCADsAgAVAAkKvh5SCADsAgAAAA==.',
Te='Tehmachine:BAAANQAECgUIDwAAAA==.Terpene:BAAANQADCgYIBgAAAA==.Terry:BAAANQAECgQJCQAAAA==.',
Th='Thanyros:BAAANQAECgYIEQAAAA==.Thanywar:BAABNQAECoEXAAIUAAgK/R+vIgDrAgAUAAgK/R+vIgDrAgAAAA==.Thebrowner:BAAANQAECgIIAgABNQAECgQJBwABAAAAAA==.Thejuice:BAAANQADCggIDQAAAA==.Thetrashman:BAAANQAECgQJBwAAAA==.Thoian:BAAANQAECgYICwAAAA==.Thork:BAAANQADCgYIBgAAAA==.Thrindy:BAAANQAECgQIBQAAAA==.Thugnificint:BAAANQAECggIEAAAAA==.Thåwn:BAAANQAECgYICAAAAA==.Thèokoles:BAABNQAECoEfAAQUAAgK6xYtSQBEAgAUAAgK6xYtSQBEAgAmAAYKKws+FgAqAQAdAAEKpgsmIgA2AAAAAA==.',
Ti='Tiblock:BAABNQAECoEgAAIeAAgKig7wDgDuAQAeAAgKig7wDgDuAQAAAA==.Tidalsage:BAAANQAECgcIEQAAAA==.Tilolas:BAAANQADCgYIBgAAAA==.Timeskip:BAAANQAECgUJCAAAAA==.Timfinnigut:BAAANQAECgYIEgAAAA==.Tinkiewinkie:BAAANQADCggICAAAAA==.Tinx:BAAANQAECgUJBwAAAA==.Tinylego:BAAANQADCggIGwAAAA==.Tinytiran:BAAANQAECgYJDwABNQAECgcIEQABAAAAAA==.',
To='Tonktotem:BAEANQADCgEIAQABNQAECgYJCwABAAAAAA==.Toptearcryer:BAAANQAECgcIEQAAAA==.Tortilla:BAAANQAECgYIDAAAAA==.Toryn:BAAANQADCgYICgABNQADCgEIAQABAAAAAA==.',
Tr='Trailwalker:BAAANQAECgYICQAAAA==.Trashypally:BAAANQAECgEIAQAAAA==.Trecks:BAAANQADCggIGQAAAA==.Treelonmüsk:BAAANQAECgEIAQAAAA==.Treesumm:BAAANQAECgYICAAAAA==.Trickyrickyy:BAAANQAECgUICgAAAA==.Triptix:BAAANQADCggIEQAAAA==.Truthbringer:BAAANQADCgQIBAAAAA==.Trynitie:BAAANQAECgUJCAAAAA==.',
Tu='Turlane:BAAANQAECgYJDQAAAA==.',
Tw='Twinkslayer:BAAANQADCgYIDgABNQAECggIFwAbALwcAA==.Twinkugly:BAAANQABCgcIDwAAAA==.',
Ty='Tyberia:BAAANQAECgQIBwAAAA==.Tychó:BAAANQAECgcJDQAAAA==.Tyeret:BAAANQAECggJEQAAAA==.Tyet:BAAANQAECgYIBAABNQAECggJEQABAAAAAA==.',
['Tø']='Tørvald:BAAANQAECgQICAAAAA==.',
Uc='Uccisore:BAAANQADCgcIBwAAAA==.',
Un='Unbeliever:BAAANQABCgYJCgAAAA==.',
Us='Uslurper:BAABNQAECoEkAAMKAAkKNRrOKwCtAgAKAAkKfhnOKwCtAgATAAkKhhKIDgAzAgAAAA==.',
Va='Vaalak:BAAANQAECgEJAQAAAA==.Valrosh:BAAANQADCgMIAwAAAA==.Varenar:BAABNQAECoEZAAIhAAgK9hbdFwBUAgAhAAgK9hbdFwBUAgAAAA==.',
Ve='Vearn:BAAANQADCgMIAwABNQADCggIEAABAAAAAA==.Velkorn:BAAANQADCgYIBgAAAA==.Vellamo:BAAANQADCgMIBQAAAA==.Vengeful:BAAANQADCggJGwAAAA==.Venuveus:BAAANQAECgQICQAAAA==.Verdan:BAAANQAECgYIDgAAAA==.',
Vi='Virlomi:BAABNQAECoElAAIQAAkKRyCgBQApAwAQAAkKRyCgBQApAwAAAA==.Viyya:BAAANQADCgYIBgAAAA==.',
Vl='Vlix:BAAANQADCgMIAwAAAA==.',
Vo='Vowz:BAAANQADCgYICgAAAA==.',
Vy='Vynx:BAAANQAECgQIBwAAAA==.Vyrogash:BAAANQADCgMIAwAAAA==.Vythica:BAAANQAECggIEwAAAA==.',
Wa='Wakoguyc:BAAANQAECgQIBwAAAA==.Warcaige:BAAANQAFFAEIAQABNQAFFAYIEQAZANMSAA==.Wargodd:BAAANQAECggIBQABNQAECggJEQABAAAAAA==.',
We='Weierstraß:BAAANQAECgYIEgAAAA==.Welari:BAABNQAECoEZAAIKAAgKkR/AKAC8AgAKAAgKkR/AKAC8AgAAAA==.Weskerx:BAAANQAECgIJAgAAAA==.',
Wh='Whindd:BAAANQAECgEIAQAAAA==.Whurstresort:BAAANQAECgcIDgAAAA==.Whurstrong:BAAANQADCgEIAQABNQAECgcIDgABAAAAAA==.Whurstyx:BAAANQAECgUIBQAAAA==.',
Wi='Wickedsoul:BAAANQADCggICAAAAA==.Widowmaker:BAAANQAECgEJAgAAAA==.Wif:BAAANQAECgMIBAAAAA==.Wingmancole:BAAANQADCgQIBAAAAA==.Withers:BAAANQADCgYIBgABNQAECgcIEwABAAAAAA==.',
Wo='Wondrball:BAAANQAECgYIEgAAAA==.Worgen:BAAANQAECgcIEAAAAA==.',
Xa='Xago:BAAANQADCgUJBQAAAA==.Xalvelora:BAAANQADCgYICQAAAA==.Xanderia:BAAANQAECgUJCAAAAA==.Xandil:BAAANQADCggICAAAAA==.',
Xe='Xeralath:BAABNQAECoEXAAIbAAgKdAZjcgBsAQAbAAgKdAZjcgBsAQAAAA==.',
Xv='Xvibe:BAAANQAECgMJAwAAAA==.',
Xy='Xyphira:BAAANQAECgEIAQAAAA==.',
['Xý']='Xý:BAAANQADCgYIEwAAAA==.',
Ya='Yaboo:BAAANQAECgEIAQAAAA==.Yaen:BAAANQADCgcJDAAAAA==.',
Ye='Yehvenâh:BAAANQAECgYJCwAAAA==.Yeska:BAAANQADCgQJBAAAAA==.',
Yo='Yootle:BAAANQAECgUIDgAAAA==.Youngcheese:BAAANQADCgcIBwAAAA==.Yourgothgf:BAEANQAECgYJCwAAAA==.Yovanna:BAAANQADCgYIBAABNQAECggIAwABAAAAAA==.',
Yu='Yummyx:BAAANQAECgEIAQAAAA==.',
Za='Zallo:BAAANQAECgYJDgAAAA==.Zaloria:BAAANQAECgQIBAAAAA==.Zaqws:BAAANQADCggIDAAAAA==.Zarth:BAAANQADCgIIAgAAAA==.Zava:BAAANQAECgQJDwAAAA==.Zaxon:BAAANQADCgQIBAABNQADCgEIAQABAAAAAA==.',
Ze='Zeelos:BAAANQAECgcJDAAAAA==.Zembu:BAAANQADCgQIBAAAAA==.Zephhyr:BAAANQAECgcIEwAAAA==.Zephyr:BAAANQAECgQIBQAAAA==.Zeñor:BAAANQAECgQICQAAAA==.',
Zh='Zhax:BAAANQABCgMIAwAAAA==.',
Zi='Zireael:BAAANQAECgYJDgAAAA==.',
Zo='Zornox:BAAANQADCgYJEQAAAA==.',
['Óp']='Óprawïndfury:BAAANQAECgUJCQAAAA==.',
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
