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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Devourer','Shaman-Restoration','Unknown-Unknown','Priest-Holy','Priest-Shadow','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Druid-Restoration','Druid-Balance','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Evoker-Devastation','Shaman-Elemental','Warrior-Fury','DemonHunter-Havoc','DeathKnight-Blood','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Rogue-Assassination','Rogue-Subtlety','Druid-Feral','Shaman-Enhancement','Priest-Discipline','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Holy','Mage-Arcane','Mage-Frost','DemonHunter-Vengeance',}
local provider = {region='US',realm='Lothar',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaliara:BAAANQAECgMIAwAAAA==.',
Ab='Absynthae:BAAANQADCgQJBQAAAA==.',
Ac='Acalyn:BAAANQADCgUIBQAAAA==.Ackreser:BAAANQAECgEJAgAAAA==.',
Ad='Adorath:BAAANQADCgUICAAAAA==.',
Ae='Aeven:BAAANQADCgEIAQABNQAECgkJGwABADIgAA==.',
Ai='Aidan:BAACNQAFFIEjAAMCAAkKZyQBAAAmBAACAAkKZyQBAAAmBAADAAEKQiZIBQBwAAA1AAQKgR4AAwIACQovJlACAKMDAAIACQovJlACAKMDAAMAAgqaJn4XANoAAAAA.Aidhan:BAABNQAECoEaAAIEAAkKNiQuBgBXAwAEAAkKNiQuBgBXAwABNQAFFAkJIwACAGckAA==.Aileron:BAABNQAECoEgAAIFAAkKQiLOCgA3AwAFAAkKQiLOCgA3AwAAAA==.Airlin:BAAANQADCgYJCgAAAA==.',
Ak='Akshana:BAAANQADCgYIBgABNQADCggJGwAGAAAAAA==.',
Al='Alcore:BAAANQAECgQJBQAAAA==.Aldrigor:BAAANQAECgIIAgAAAA==.Alett:BAAANQADCggIFgAAAA==.Alivathus:BAABNQAECoEiAAMHAAkK3iPoAgCbAwAHAAkK3iPoAgCbAwAIAAEKfg7jUQA6AAAAAA==.Alluu:BAAANQADCgUIBQAAAA==.Alsong:BAAANQADCgUIDAAAAA==.Alvart:BAAANQADCggIFwAAAA==.',
Am='Ambervoid:BAAANQAECgUJCgAAAA==.Amiko:BAAANQAECgEJAQAAAA==.',
An='Annaisa:BAAANQABCgUIBQAAAA==.',
Ar='Arbark:BAABNQAECoEhAAQJAAkK+CTGAABJAwAJAAgKjiXGAABJAwAKAAgKmCMoFADxAgALAAQKLCDKHABoAQAAAA==.Arcada:BAAANQADCgYIBgAAAA==.Archdemon:BAAANQADCgUIBQAAAA==.Arcnfrost:BAAANQAECgQIBQAAAA==.Ardone:BAAANQABCgIIAgAAAA==.Arkadis:BAAANQAECgQJCQAAAA==.Armina:BAAANQAECgYIBgAAAA==.Arrothin:BAAANQABCggIFgAAAA==.',
As='Asdanoth:BAAANQADCggICwAAAA==.Ashenbrawl:BAAANQAECgcIDgAAAA==.Ashenclaw:BAAANQAECgQJBgAAAA==.Aspinks:BAAANQAECgIIAgABNQAECggJGQAKAIYJAA==.',
Au='Auxie:BAAANQAECgYICQAAAA==.',
Av='Availl:BAAANQADCgcIBwABNQAECgIIAwAGAAAAAA==.Avatipup:BAAANQAECgIIAgAAAA==.',
Aw='Aweinon:BAAANQADCgQIBAAAAA==.',
Ay='Aydin:BAACNQAFFIEIAAIMAAQKQxkKCgBdAQAMAAQKQxkKCgBdAQA1AAQKgRoAAgwACQpvJC8OAGgDAAwACQpvJC8OAGgDAAE1AAUUCQkjAAIAZyQA.Aylan:BAAANQADCgMIAwAAAA==.',
Az='Azelous:BAAANQADCggICAABNQAECgkJIAAFAI8eAA==.Azumaa:BAAANQADCggIIAAAAA==.Azurath:BAAANQAECgIIAgAAAA==.Azureth:BAAANQADCgEIAQAAAA==.',
Ba='Bainironwind:BAAANQADCgUIBQAAAA==.Baiwushi:BAAANQAECgYIDAAAAA==.Ballock:BAAANQADCggICAAAAA==.Balázs:BAAANQAECgQJCAAAAA==.',
Be='Becbec:BAAANQADCgYICgAAAA==.Beckyplease:BAAANQADCgYIBgAAAA==.Belaghal:BAAANQADCgUIBQAAAA==.Ben:BAAANQAECgEIAQABNQAECgQJBwAGAAAAAA==.Bestricer:BAAANQAECgIIAgABNQAFFAcIHQACACQZAA==.',
Bi='Biggles:BAECNQAFFIEJAAMNAAUK8At3BAAaAQANAAQKbgV3BAAaAQAOAAEKPQthFwBOAAA1AAQKgR4AAw4ACQq7E4cqABMCAA4ACAq2E4cqABMCAA0ACArbFZgYAOsBAAAA.Bighuntarizo:BAAANQAECgQJBwAAAA==.Billevilbill:BAAANQAECgUIBwAAAA==.',
Bl='Blobney:BAACNQAFFIESAAMKAAcKqx3hAgDHAQAKAAUKWx7hAgDHAQALAAIK8ht4BADAAAA1AAQKgR4AAwsACQoFJiMFAK4CAAoABwrjJcEVAOcCAAsABwoWIyMFAK4CAAAA.Bluechip:BAAANQAECgUJDQAAAA==.Blueeagle:BAABNQAECoEiAAQPAAkK/yT1BABlAwAPAAkKLyT1BABlAwAQAAIKGiW3CQDWAAARAAEK1CYx2QBzAAAAAA==.Bluespell:BAAANQAECgMJBgABNQAECgkJIgAPAP8kAA==.',
Bo='Bolts:BAAANQADCgYIEgAAAA==.Borak:BAAANQADCgQIBAABNQAECgkJIAAFAI8eAA==.',
Br='Braezlor:BAAANQADCgcIBwAAAA==.Brendel:BAAANQAECgEJAgAAAA==.Brewdarymor:BAAANQAECgQIBAABNQAECgkJHAASADUTAA==.Broaahhaha:BAAANQAECgEJAgAAAA==.',
Bu='Bulletsponge:BAAANQADCgEIAQABNQADCggIFQAGAAAAAA==.Butterflyy:BAABNQAECoEaAAIRAAgKSxIXPQBCAgARAAgKSxIXPQBCAgAAAA==.',
Ca='Caelena:BAAANQAECgQJCAAAAA==.',
Ce='Celestial:BAABNQAECoEYAAMLAAcKeRGdEwC6AQALAAcKhhCdEwC6AQAJAAIKwA03FQB6AAAAAA==.',
Ch='Chilltest:BAAANQAECgQIBwAAAA==.Chronobacon:BAAANQADCgYICgABNQAECgkJHAASADUTAA==.Chupacabra:BAAANQADCggJIQAAAA==.Chuyz:BAAANQAECggJEgAAAA==.Chuyzz:BAAANQAECgUJEAAAAA==.',
Cl='Clawdene:BAAANQADCgQIBwAAAA==.Clickchi:BAAANQADCggIEQAAAA==.Cloudwarrior:BAAANQADCgEIAQABNQAECgkJHgATAE8eAA==.',
Co='Cokediet:BAAANQAECgIIBAAAAA==.Cooties:BAAANQADCgUIBQABNQAECgEJAgAGAAAAAA==.Cordeliaa:BAAANQADCggIFgAAAA==.Coven:BAAANQAECgEJAQAAAA==.',
Cr='Crunch:BAABNQAECoEeAAMUAAgKZSLlAQANAwAUAAgKZSLlAQANAwAMAAMKvRJPxwC5AAAAAA==.',
Cy='Cynderelle:BAAANQADCgYIEAAAAA==.Cynikka:BAAANQAECgYIDgAAAA==.Cynthor:BAAANQAECgYJDAAAAA==.',
Da='Dadtothebone:BAAANQADCgcIDAAAAA==.Daghahi:BAAANQAECgUJDwAAAA==.Daishanar:BAAANQAECgUICAAAAA==.Dalethyr:BAAANQAECgQIBAAAAA==.Darkseid:BAAANQADCgQJBAAAAA==.Darthflame:BAAANQADCgUIBQABNQAECgcJGAAVAPkSAA==.David:BAAANQAECgEJAgABNQAECgQJBwAGAAAAAA==.Dawuffman:BAAANQAECgYJCgAAAA==.Daylia:BAAANQADCgYIBgAAAA==.',
De='Deathash:BAAANQAECgEIAQAAAA==.Deathdruid:BAAANQAECgUJCgAAAA==.Deathfarm:BAAANQAECgQIBwAAAA==.Deliverenc:BAAANQADCgYJBgAAAA==.Delmus:BAAANQAECgUICgAAAA==.Delphinae:BAAANQADCggJIQAAAA==.Demontwink:BAAANQADCggIFwAAAA==.Demount:BAAANQADCgYIBgAAAA==.Devera:BAABNQAECoEYAAIOAAkKpxRHJQBAAgAOAAkKpxRHJQBAAgABNQAECgkJGQATAKIaAA==.',
Di='Dinkylock:BAAANQADCggIDAAAAA==.Dirtykahuna:BAAANQAECgMJBQAAAA==.Dirtymagus:BAAANQABCgYIBgABNQAECgMJBQAGAAAAAA==.Discosticks:BAAANQAECgEJAQAAAA==.Distress:BAAANQAECgEIAQAAAA==.',
Do='Dojoshaman:BAABNQAECoEbAAITAAgKsSHUEgAYAwATAAgKsSHUEgAYAwAAAA==.Doodman:BAAANQAECgYICQAAAA==.Doubleshot:BAAANQADCgYJBgAAAA==.',
Dr='Dragondeez:BAAANQADCgUIBQABNQAECgcIEgAGAAAAAA==.Dreadrend:BAAANQAECgcJBgAAAA==.Dropsin:BAAANQADCggICAAAAA==.Drwn:BAAANQAECgQJBgAAAA==.',
Du='Duckroll:BAAANQAECgEIAQAAAA==.Dustmaster:BAAANQABCgIIBgAAAA==.',
Dw='Dwelknarr:BAAANQADCggJGQAAAA==.Dwlirious:BAAANQAECgQICAAAAA==.',
Ea='Eadric:BAAANQAECgIIAgAAAA==.Earendur:BAAANQADCggIHAAAAA==.Earthfury:BAAANQAECgQIBgABNQAECgYIBgAGAAAAAA==.Eaven:BAAANQADCgIIAgABNQAECgkJGwABADIgAA==.',
Ed='Edallen:BAAANQAECgUICgAAAA==.',
Ee='Eelyroc:BAAANQADCgMIAwAAAA==.',
El='Elbrujo:BAAANQAECgQJCgAAAA==.Elementals:BAAANQAECggJAQAAAA==.',
Em='Emaytete:BAAANQAECgMIAwAAAA==.Emayteteheww:BAAANQAECgMJBwAAAA==.Emaytetem:BAAANQADCgMIAwAAAA==.Emillyra:BAAANQADCggIEAAAAA==.Empress:BAAANQAECgEIAQABNQAFFAQJCAAWAOYeAA==.',
Ep='Ephemra:BAAANQADCggJBwAAAA==.',
Es='Esteban:BAAANQADCggIEwAAAA==.',
Ev='Evokethywikd:BAAANQAECggJDQABNQABCgIIAgAGAAAAAA==.',
Fa='Fahx:BAAANQADCgQIBAAAAA==.Falwyn:BAAANQAECgEJAQAAAA==.Famidore:BAAANQADCgIIBAAAAA==.Faèlyn:BAAANQADCgUICQAAAA==.',
Fe='Felflamel:BAABNQAECoEYAAIVAAcK+RKPKgC1AQAVAAcK+RKPKgC1AQAAAA==.Feltest:BAAANQAECgcJDwAAAA==.Feralized:BAAANQADCgUIBwAAAA==.Ferdinan:BAAANQAECggIEQAAAA==.',
Fl='Flareon:BAAANQAECgEIAQABNQAFFAYIDAAFAGQYAA==.Flashter:BAAANQAECgYJEAAAAA==.Flax:BAAANQADCgMIAwAAAA==.Fluffycuddle:BAAANQADCgUICQAAAA==.',
Fo='Forrealzies:BAAANQADCgYIDAAAAA==.Fortunato:BAAANQADCgEIAQAAAA==.',
Fr='Frankhs:BAAANQAECgIJAgAAAA==.',
Fu='Furchi:BAAANQADCgIIAgABNQAECgYJCgAGAAAAAA==.',
Ga='Galdrel:BAAANQAECgQICAAAAA==.Gallince:BAACNQAFFIEIAAIXAAQKJyBQBACIAQAXAAQKJyBQBACIAQA1AAQKgRoAAhcACQoSJg4RAE0DABcACQoSJg4RAE0DAAAA.Garbich:BAAANQADCgEIAgABNQADCgcIBwAGAAAAAA==.Gary:BAAANQAECgUICgAAAA==.',
Ge='Gerhart:BAAANQADCggJIQAAAA==.',
Gh='Ghostsham:BAACNQAFFIEXAAITAAYK9iAIAQBVAgATAAYK9iAIAQBVAgA1AAQKgSUAAxMACQq1JXoBAOQDABMACQq1JXoBAOQDAAUAAwoJA5avAIcAAAAA.Ghðst:BAAANQAECgcIEAABNQAFFAYIFwATAPYgAA==.',
Gi='Gilgamet:BAAANQADCgEIAQAAAA==.Gizmito:BAAANQADCgQIBQAAAA==.',
Gl='Glizzyman:BAAANQAECgYJEAAAAA==.',
Gn='Gnarfarm:BAAANQAECgQIBwAAAA==.',
Go='Go:BAAANQADCgYJBgABNQAECgQJBQAGAAAAAA==.Goldoran:BAAANQADCgIIAgAAAA==.Gonette:BAAANQADCgYIBgABNQAECgcIGAAYALogAA==.Goniff:BAABNQAECoEYAAIYAAcKuiA7CgCKAgAYAAcKuiA7CgCKAgAAAA==.Goransk:BAAANQAECgEJAgAAAA==.Gorsk:BAAANQADCgYIBgABNQAECgEJAgAGAAAAAA==.',
Gr='Gracelious:BAABNQAECoEaAAIXAAcK/BrRTQAdAgAXAAcK/BrRTQAdAgAAAA==.Graebeard:BAAANQADCgcIEgAAAA==.Graehame:BAAANQADCgQIBwAAAA==.Greyshadow:BAAANQADCgUIBQAAAA==.Grubber:BAAANQADCgYIBgABNQADCggIHAAGAAAAAA==.Grüb:BAAANQADCggIHAAAAA==.',
Gu='Guitar:BAAANQABCgUJBQAAAA==.Guntran:BAABNQAECoEZAAIXAAgKGxtxMgCNAgAXAAgKGxtxMgCNAgAAAA==.Gurkha:BAAANQADCgYIBwAAAA==.Gurthock:BAAANQAECgYICgAAAA==.',
Gw='Gwenixx:BAAANQADCggIHQAAAA==.',
Ha='Halios:BAAANQADCgYJBgAAAA==.',
He='Headhuntin:BAAANQAECgUJCQAAAA==.Heatfang:BAAANQADCgcICQAAAA==.Hellione:BAAANQAECgUJCQAAAA==.Hellmaree:BAAANQADCgEIAQAAAA==.Helltest:BAAANQAECgEIAQAAAA==.',
Ho='Holyspurb:BAAANQABCgIJAgAAAA==.Holywater:BAAANQAECgYJDwAAAA==.Honkinhammer:BAAANQADCgYJBgABNQAECgQIBAAGAAAAAA==.Hotdogman:BAACNQAFFIESAAIPAAYKjB2NAQBFAgAPAAYKjB2NAQBFAgA1AAQKgR8AAg8ACQpUJpoAAOoDAA8ACQpUJpoAAOoDAAE1AAQKAQgBAAYAAAAA.Hotdumpling:BAAANQAECgQJCQAAAA==.',
Hu='Huegarak:BAAANQAECgQJBgAAAA==.',
Hy='Hyle:BAAANQAECgUICgAAAA==.',
Il='Illidaddy:BAAANQADCgMIAwABNQAECgcIEgAGAAAAAA==.Illuminator:BAAANQADCggIHQAAAA==.',
In='Inspectadeck:BAACNQAFFIEFAAMKAAMK7gWlGgCRAAAKAAIKMQelGgCRAAALAAEKaQOAFABOAAA1AAQKgSkAAwoACQpFHMQaAMcCAAoACQpFHMQaAMcCAAsAAwqrEnY2AMQAAAAA.',
Is='Istariel:BAAANQAECgIIAgABNQAFFAYIFwATAPYgAA==.',
It='Ithoron:BAABNQAECoEXAAIWAAcKJhXRNQDDAQAWAAcKJhXRNQDDAQAAAA==.',
Iv='Ivoree:BAAANQABCgEJAQAAAA==.',
Ja='Jaytov:BAAANQABCgQIBAAAAA==.Jazu:BAAANQAECgUICwAAAA==.',
Je='Jerks:BAAANQAECgYJEQAAAA==.',
Jo='Jost:BAAANQADCgMIAwABNQAECgUIBgAGAAAAAA==.Joval:BAAANQADCggIHgAAAA==.Jozeph:BAAANQAECgUICwAAAA==.',
['Jà']='Jàmie:BAAANQAECgYIBgAAAA==.',
Ka='Kaalar:BAAANQAECgYIEgAAAA==.Kaestirael:BAAANQADCgcJCwAAAA==.Kakarrot:BAAANQAECgIJAgAAAA==.Kalichnakov:BAAANQADCgYIBgAAAA==.Kamoura:BAAANQAECgUIDgAAAA==.Kapeta:BAAANQAECgIJBAAAAA==.Karmen:BAACNQAFFIEKAAIZAAUKyxvQAwDFAQAZAAUKyxvQAwDFAQA1AAQKgR4AAhkACQrwIgcCAI0DABkACQrwIgcCAI0DAAAA.Karnatron:BAAANQAECgQIBAAAAA==.Karnvoid:BAAANQADCggJCAABNQAECgQIBAAGAAAAAA==.Katalain:BAAANQADCggICQABNQAECgkJIAANAN4YAA==.Kayleave:BAAANQABCgEIAQAAAA==.',
Ke='Keattz:BAACNQAFFIEaAAIMAAcKjh7ZAADCAgAMAAcKjh7ZAADCAgA1AAQKgSoAAgwACQqNJlMBAO8DAAwACQqNJlMBAO8DAAE1AAQKCQkdABoA+SAA.Keattzxd:BAABNQAECoEdAAMaAAkK+SAIAwB6AwAaAAkK+SAIAwB6AwAbAAMKPQ8IMwC3AAAAAA==.Keedill:BAAANQAECgYIDgAAAA==.Keelinnea:BAAANQAECgEIAQAAAA==.Keelu:BAAANQADCgEIAQAAAA==.Keggerz:BAAANQADCgcIDAAAAA==.Kennagi:BAAANQAECgQICQAAAA==.Kenshunterl:BAAANQADCggJIQAAAA==.',
Kh='Khanzen:BAAANQAECgIIAgAAAA==.Khathgar:BAAANQAECgQICQABNQAECgkJHwAcAHMaAA==.Khovastis:BAACNQAFFIEJAAIOAAUKxxdWBQCsAQAOAAUKxxdWBQCsAQA1AAQKgR4AAw4ACQq6GRMjAFQCAA4ACArzGhMjAFQCABwAAgqSFj8cAIIAAAAA.',
Ki='Kianll:BAAANQAECgEIAQAAAA==.Kitchntabls:BAACNQAFFIEKAAIVAAUKsRYDAwC5AQAVAAUKsRYDAwC5AQA1AAQKgR4AAxUACQqjJYcBANIDABUACQqjJYcBANIDAAQAAwr/D0dDAK4AAAAA.',
Kj='Kjirou:BAAANQAECgUIDAAAAA==.',
Ko='Koenji:BAACNQAFFIEKAAIdAAUKFRHaAAC8AQAdAAUKFRHaAAC8AQA1AAQKgRsAAh0ACQqMIdMCAFUDAB0ACQqMIdMCAFUDAAAA.Korely:BAAANQADCggICAAAAA==.Korgrim:BAAANQAECgEJAgAAAA==.',
Ky='Kymal:BAAANQAECgEIAQAAAA==.Kyndel:BAAANQADCgQIBwAAAA==.Kyndrah:BAABNQAECoEaAAQHAAgKhxBTPQD0AQAHAAgKRhBTPQD0AQAIAAgKFg3BHQDaAQAeAAMKaQTUEwB8AAABNQADCgQIBwAGAAAAAA==.',
['Kä']='Käne:BAAANQAECgUICgAAAA==.',
['Kì']='Kìn:BAAANQADCgIIAgABNQAECgYJEAAGAAAAAA==.',
['Kí']='Kín:BAAANQADCgEIAQABNQAECgYJEAAGAAAAAA==.',
La='Lableue:BAAANQAECgEJAgAAAA==.Lavacask:BAAANQADCggJHgAAAA==.',
Le='Lehvy:BAAANQADCggICAABNQAECgkJIgAHAK4aAA==.Leodk:BAACNQAFFIEGAAIfAAIK7x0ICACyAAAfAAIK7x0ICACyAAA1AAQKgR8AAx8ACQqnJGQEAHIDAB8ACQqnJGQEAHIDACAABApdHvlbAAYBAAE1AAUUAgoGAB8A7x0A.Lerann:BAAANQADCgQIBAABNQAECgYIEQAGAAAAAA==.Levey:BAABNQAECoEiAAIHAAkKrhpoGQC6AgAHAAkKrhpoGQC6AgAAAA==.Lewdcifer:BAAANQADCggICAAAAA==.',
Li='Lick:BAAANQAECgMIAwABNQAECgQJBQAGAAAAAA==.Lict:BAABNQAECoEZAAIhAAkKARisIQCPAgAhAAkKARisIQCPAgABNQAECgQJBQAGAAAAAA==.Liekki:BAAANQADCgYIBwABNQADCggJGQAGAAAAAA==.Lillea:BAAANQAECgIJAwAAAA==.Linada:BAAANQADCggJCAAAAA==.Listurfiend:BAAANQADCgIIAgAAAA==.',
Lo='Loktalaan:BAABNQAECoEhAAIdAAkKmhcmBwDCAgAdAAkKmhcmBwDCAgAAAA==.Lothlorian:BAAANQADCgEIAQAAAA==.',
Lu='Luan:BAAANQAECgQIBAAAAA==.Lucien:BAABNQAECoEgAAINAAkK3hh9DACjAgANAAkK3hh9DACjAgAAAA==.Lute:BAABNQAECoEYAAMTAAcKQCQwGQDiAgATAAcKQCQwGQDiAgAFAAEKyA2m4QAiAAAAAA==.',
Ly='Lyfeguard:BAAANQAECgUICQAAAA==.',
Ma='Machoke:BAAANQADCgYIDQAAAA==.Mahito:BAABNQAECoEbAAIcAAkKmRyxAwDzAgAcAAkKmRyxAwDzAgAAAA==.Maiha:BAAANQAECgQJBgABNQAECggIAgAGAAAAAA==.Malenia:BAACNQAFFIEIAAMLAAQKQwlnCgCeAAALAAIKcAdnCgCeAAAKAAIKFwuAGgCSAAA1AAQKgSAABAsACQpDH2kYAJABAAoACArRF285ADgCAAsABQoqH2kYAJABAAkAAgpKEWkXAGcAAAAA.Malume:BAAANQADCgYICAAAAA==.Malyon:BAAANQADCgEIAQAAAA==.Malístra:BAAANQADCggICgAAAA==.Manaless:BAAANQAECgEIAQABNQAFFAIKBgAfAO8dAA==.Marderer:BAAANQAECgUJDwAAAA==.Masakari:BAAANQAECgUJDwAAAA==.Materia:BAAANQAECgEJAQAAAA==.Mathmagician:BAAANQAECgcIEgAAAA==.Maulfarm:BAABNQAECoEeAAIcAAkKDiBmAgBBAwAcAAkKDiBmAgBBAwAAAA==.Mazz:BAAANQABCgYIBgABNQADCggJIAAGAAAAAA==.Mazzlock:BAAANQADCggJIAAAAA==.',
Mc='Mclovn:BAAANQADCgEIAQAAAA==.',
Me='Megameow:BAABNQAECoEfAAMcAAkKcxqKAwD5AgAcAAkKcxqKAwD5AgANAAQKEwtEMgDcAAAAAA==.Mercuria:BAAANQADCgMIAwAAAA==.Metaclass:BAAANQAECgIIAwAAAA==.',
Mi='Mirâ:BAAANQADCgcIBwAAAA==.Mitrixx:BAAANQAECgcICwAAAA==.Miztie:BAAANQADCgQIBAAAAA==.',
Mo='Mobius:BAAANQAECgEIAQAAAA==.Mokuo:BAAANQADCgUIBQAAAA==.Moonthorn:BAAANQAECgQJBwAAAA==.Morrow:BAAANQADCgEIAQAAAA==.Mort:BAAANQADCggJIQAAAA==.Moxou:BAAANQAECgEIAQABNQAFFAUJDAAFAHMXAA==.Moxxou:BAACNQAFFIEMAAIFAAUKcxdBBACtAQAFAAUKcxdBBACtAQA1AAQKgRwAAgUACQppI0oDAJ0DAAUACQppI0oDAJ0DAAAA.Moyi:BAAANQAECgEJAQAAAA==.',
Mu='Mulch:BAABNQAECoEcAAINAAgKcg0XGwDIAQANAAgKcg0XGwDIAQAAAA==.',
My='Mybelle:BAAANQADCgIIAgAAAA==.Mysticle:BAAANQADCgcJEAAAAA==.Mythaltis:BAAANQAECgUIDQAAAA==.',
Na='Naedori:BAAANQADCgYJBgABNQADCggIDAAGAAAAAA==.Naizhruk:BAAANQADCgEIAQAAAA==.Nall:BAAANQADCgIIBAAAAA==.Naoh:BAAANQADCgQJBAAAAA==.Narache:BAAANQADCgYIBwAAAA==.Naturerend:BAAANQADCgYJBgAAAA==.Naul:BAAANQAFFAMIAwAAAA==.Naull:BAAANQAECgEIAgAAAA==.Naysayer:BAAANQADCgEIAQAAAA==.Naúl:BAAANQADCgUIBQAAAA==.',
Ne='Necrokai:BAAANQAECgUJCgAAAA==.Necroscourge:BAAANQAECgUICgABNQAECgUJCgAGAAAAAA==.Neighter:BAAANQAECgIJAgAAAA==.Nerevar:BAAANQADCggIGwAAAA==.Netal:BAAANQAECgQJCgAAAA==.Nevergoback:BAAANQADCgcICwABNQAECgYJEQAGAAAAAA==.',
Ni='Ninejuanjuan:BAABNQAECoEcAAIhAAgKHxHZMwAsAgAhAAgKHxHZMwAsAgAAAA==.Nishikienrai:BAAANQAECgEIAQAAAA==.',
No='Nochit:BAACNQAFFIEJAAIOAAMK3SWqCABOAQAOAAMK3SWqCABOAQA1AAQKgSEAAg4ACQrRJiUBAOIDAA4ACQrRJiUBAOIDAAAA.Noctula:BAAANQAECgQJEAABNQAECgUJCgAGAAAAAA==.Norbiee:BAAANQAECgQICAAAAA==.Nored:BAAANQADCgQIBAAAAA==.Norne:BAABNQAECoEZAAIVAAgKExmIGQBeAgAVAAgKExmIGQBeAgAAAA==.Nowfaleena:BAAANQADCggICAAAAA==.',
Ny='Nytkiller:BAAANQAECgEIAQAAAA==.Nyzul:BAAANQAECgEIAQABNQAECgUICgAGAAAAAA==.',
['Në']='Nëv:BAAANQADCgIIAgAAAA==.',
Oa='Oatie:BAAANQADCgUIAwAAAA==.',
Oc='Oceanic:BAAANQAECgIJBAAAAA==.',
Od='Odlinn:BAAANQAECgUJDQABNQAECggIHAANAHINAA==.',
On='Onlyhorns:BAAANQAECgYICgABNQAECggJFwAdADUiAA==.',
Oo='Oogs:BAAANQAECgEIAQAAAA==.',
Op='Opalia:BAAANQAECgEIAQAAAA==.Opallea:BAAANQAECgEJAQABNQAECgEJAQAGAAAAAA==.',
Or='Orch:BAAANQAECgUICgAAAQ==.',
Ov='Overclocked:BAABNQAECoEZAAIKAAgKhgn0aACKAQAKAAgKhgn0aACKAQAAAA==.',
Pa='Paddington:BAAANQAECgUJCwAAAA==.Pahbi:BAAANQADCggIFgAAAA==.Palempi:BAAANQADCggJCAAAAA==.Paul:BAAANQAECgQJBwAAAA==.',
Pe='Pendojo:BAAANQAECgUIBgAAAA==.Pendomage:BAAANQAECgUICwAAAA==.',
Ph='Phobius:BAAANQAECgIIAgAAAA==.',
Pi='Pip:BAABNQAECoEZAAMTAAkKoho7LwBOAgATAAgKnho7LwBOAgAFAAIKDwOfvABiAAAAAA==.Pipium:BAABNQAECoEYAAIJAAkK1SGeAgCOAgAJAAkK1SGeAgCOAgABNQAECgkJGQATAKIaAA==.Pixsin:BAEANQADCgQIBQABNQAECggIHwAKACUZAA==.',
Po='Pookiehandz:BAAANQAECgYJEQAAAA==.Porpul:BAAANQAECgIIAgAAAA==.Powery:BAAANQADCggIEAAAAA==.',
Pr='Project:BAAANQAECgQIBAAAAA==.Prophet:BAAANQADCgcIBwAAAA==.',
Pu='Publicbussy:BAAANQADCgcJDgAAAA==.Purples:BAAANQAECgYJCgAAAA==.Purpul:BAAANQAECgQIBAABNQAECgYJCgAGAAAAAA==.',
Qa='Qawxz:BAAANQADCgUIBQAAAA==.',
Qu='Quicktail:BAAANQADCgIIAgABNQAECgYJEAAGAAAAAA==.',
Ra='Raikan:BAAANQAECgYIEQAAAA==.Rainwater:BAAANQADCgEIAQAAAA==.Raisins:BAAANQADCggJCAABNQAFFAUJCQAHALEaAA==.Raisyns:BAACNQAFFIEJAAIHAAUKsRpzBADbAQAHAAUKsRpzBADbAQA1AAQKgR4AAwcACQq3IiwHAFgDAAcACQq3IiwHAFgDAB4AAQqQHFMZAEIAAAAA.Rammic:BAAANQADCgIIAgAAAA==.Randstohl:BAAANQADCggIDgAAAA==.Ratakhan:BAAANQADCgUICAAAAA==.Raulothim:BAAANQAECgUICAAAAA==.',
Re='Rebell:BAAANQAECggIAgAAAA==.Reelorn:BAAANQADCgYIBgAAAA==.Reny:BAAANQAECgIIAwAAAA==.Repentance:BAAANQADCgEIAQABNQADCgYIBwAGAAAAAA==.Retribussy:BAAANQAECgYJDAAAAA==.',
Ri='Ricemachinex:BAABNQAECoEZAAMKAAkK+BUkTADuAQAKAAcK5xIkTADuAQALAAMK5RZoLAD3AAABNQAFFAcIHQACACQZAA==.Riko:BAAANQADCggICgABNQAECgkJGwAcAJkcAA==.',
Ro='Rocthar:BAAANQAECgYIEgAAAA==.Roguelite:BAAANQADCgEIAQABNQAFFAIKBgAfAO8dAA==.Romarus:BAAANQAECgQJBQAAAA==.Romeoposter:BAAANQAECgQJBgAAAA==.',
Ru='Rukarazyll:BAAANQADCggJHQAAAA==.Rumble:BAAANQADCgYICAAAAA==.Rutherford:BAAANQADCgQIBAAAAA==.',
Ry='Ryunohige:BAAANQADCggICAAAAA==.',
['Rú']='Rúúsh:BAAANQAECgQJBgAAAA==.',
Sa='Safeword:BAAANQAECgQJBAAAAA==.Saihua:BAAANQADCgYIBgAAAA==.Saintjohn:BAAANQAECgcIBwAAAA==.Saintjonn:BAAANQAECgcJDgAAAA==.Saintrob:BAAANQADCgMJAwAAAA==.Sarthdidius:BAAANQAECgYIEwAAAA==.Sassparilluh:BAAANQADCggIHgAAAA==.Savalla:BAAANQADCgYIBgAAAA==.',
Sc='Schadenfreud:BAAANQAECgQIBQAAAA==.Scholoman:BAAANQADCggIDgAAAA==.Scratchbelly:BAAANQADCgUIBQAAAA==.Scumdog:BAAANQADCgYJBgAAAA==.',
Se='Senpai:BAACNQAFFIEIAAIiAAUKCA9gCwCoAQAiAAUKCA9gCwCoAQA1AAQKgR0AAyIACQr3H8UjACkDACIACQr3H8UjACkDACMAAQrlHzUpAEoAAAAA.Seoli:BAAANQADCggIEAAAAA==.Serenya:BAAANQADCgYIBgAAAA==.',
Sh='Shalanthra:BAAANQADCggIFQAAAA==.Shamallow:BAAANQADCgQIBAAAAA==.Shammunition:BAABNQAECoEXAAIdAAgKNSLrBAAMAwAdAAgKNSLrBAAMAwAAAA==.Shartner:BAAANQADCgMJAwAAAA==.Shartz:BAAANQAECgIJAwAAAA==.Shaysa:BAEANQAECgUJBgAAAA==.Sheraa:BAAANQAECgIJAwAAAA==.Shinigamisan:BAAANQAECgYJDwAAAA==.Shynox:BAAANQAECgUICgAAAA==.Shümp:BAAANQADCgUIBQAAAA==.',
Si='Sinnerchrono:BAAANQADCggIBwAAAA==.Sinnwoo:BAAANQABCgQIBgAAAA==.Sitharco:BAAANQAECgMJBwAAAA==.',
Sl='Sladex:BAAANQAECgIJAgAAAA==.',
Sm='Smorc:BAAANQAECgcIDQAAAA==.',
Sn='Snackwitch:BAAANQADCggJGwAAAA==.Sneaki:BAAANQAECgUIBwABNQAECgYICQAGAAAAAA==.',
So='Soarseas:BAAANQADCgYIBgAAAA==.Sommin:BAAANQADCgYICgAAAA==.Sorakah:BAAANQAECgMIBAAAAA==.Soulviper:BAABNQAECoEiAAIFAAkKhhcHJgBwAgAFAAkKhhcHJgBwAgAAAA==.',
Sp='Spankmyflank:BAAANQAECgEJAQAAAA==.Spurblock:BAAANQADCgYJBgAAAA==.',
Sq='Squaleon:BAAANQADCgQIBAAAAA==.',
St='Stabbyfinch:BAAANQADCggJHAAAAA==.Steplok:BAAANQAECgQJBAAAAA==.Stonestriker:BAAANQADCggJIQAAAA==.Stooben:BAABNQAECoEZAAIMAAgKThPsVwAOAgAMAAgKThPsVwAOAgAAAA==.Stoobenh:BAAANQADCgYIBgAAAA==.Sturge:BAAANQADCggIFwAAAA==.',
Su='Supahsayajin:BAAANQAECgcIEAABNQABCgIIAgAGAAAAAA==.',
Sw='Sweetbee:BAAANQAECgQIBgAAAA==.Sweetvaldine:BAAANQADCgUIBQAAAA==.Swole:BAAANQAECgQIBQAAAA==.',
Sy='Syanalody:BAAANQADCggIHQAAAA==.Sylarz:BAAANQAECgQIBQABNQAECgkJHAASADUTAA==.Sylenn:BAAANQADCgcJFgAAAA==.Syn:BAAANQAECgYJEQAAAA==.Synchro:BAAANQADCgQIBAAAAA==.',
Ta='Tanstaafl:BAAANQAECgYJEQAAAA==.Taralom:BAAANQADCggJIQAAAA==.Taurenspurb:BAAANQADCgYIBgAAAA==.Taz:BAEBNQAECoEfAAMkAAkKvCH8AAB4AwAkAAgKzCX8AAB4AwAVAAEKPQFNbQAEAAAAAA==.',
Te='Telmo:BAAANQAECgYJBgAAAA==.Tenebrix:BAAANQAECgUIBgAAAA==.Tenevoy:BAAANQAECggJCAABNQAFFAYIFwATAPYgAA==.',
Th='Thadex:BAABNQAECoEWAAMMAAgK/B8HOQCCAgAMAAcK8SAHOQCCAgAUAAEKSBnoHgBGAAAAAA==.Thedood:BAAANQADCgYIBgAAAA==.Thedruidguy:BAAANQADCgQIBAAAAA==.Theldrid:BAABNQAECoEfAAIgAAgKviM8CwAzAwAgAAgKviM8CwAzAwAAAA==.Thepallyguy:BAAANQAECgMIAwABNQAECgQIBwAGAAAAAA==.Theprepared:BAAANQADCgQJBAAAAA==.Thepriestguy:BAAANQAECgQIBwAAAA==.Theralethia:BAAANQADCgcICAAAAA==.Therian:BAAANQADCgIJAwAAAA==.Theshamanguy:BAAANQADCggIEQABNQAECgQIBwAGAAAAAA==.Thorseas:BAAANQAECgUIDQAAAA==.Thunderkill:BAAANQADCgYICwAAAA==.',
Ti='Tirissa:BAAANQADCgEIAQAAAA==.',
To='Tooyew:BAAANQADCgcICAABNQAFFAUJCgAMALcPAA==.Tooyoo:BAABNQAFFIEKAAIMAAUKtw8+CACLAQAMAAUKtw8+CACLAQAAAA==.Torpedotaka:BAAANQAECgMIBAAAAA==.',
Tp='Tpala:BAAANQAECgQICgAAAA==.',
Tr='Triggerfarm:BAAANQAECgYJDQAAAA==.Tristis:BAAANQADCgYICgAAAA==.',
Tu='Turthunt:BAACNQAFFIEQAAIPAAYKOhozAgAQAgAPAAYKOhozAgAQAgA1AAQKgR4AAw8ACQqYJGoQAKYCAA8ABwpJJGoQAKYCABEABgqRIk1pALIBAAAA.Turtrik:BAAANQAECgIIAgABNQAFFAYIEAAPADoaAA==.',
Tw='Twinns:BAAANQADCgUJBQAAAA==.',
Ty='Tyesham:BAAANQADCgYICQABNQAECgEJAgAGAAAAAA==.Tyice:BAAANQAECgEJAgAAAA==.',
Um='Umbriä:BAAANQADCgIIAgABNQADCggIDgAGAAAAAA==.',
Ur='Urak:BAAANQADCgYIBgAAAA==.',
Va='Valaidpriest:BAAANQAECgUIBwAAAA==.Valoth:BAAANQADCgUICAAAAA==.Vanelura:BAAANQAECgIIAgAAAA==.Vaporeon:BAACNQAFFIEMAAIFAAYKZBjfAQAbAgAFAAYKZBjfAQAbAgA1AAQKgSkAAgUACQoyJSsBAMsDAAUACQoyJSsBAMsDAAAA.',
Ve='Velorth:BAAANQAECgIJAwAAAA==.',
Vr='Vrahmageddon:BAAANQAECgUICgAAAA==.',
Vy='Vynlorin:BAACNQAFFIEJAAIWAAQK9QTrCwDeAAAWAAQK9QTrCwDeAAA1AAQKgR4AAhYACQrQFDMnAB4CABYACQrQFDMnAB4CAAAA.',
Wa='Wahstella:BAACNQAFFIEYAAMiAAcKgRLxBQAAAgAiAAYKARHxBQAAAgAjAAIKkBOsAQC9AAA1AAQKgS0AAyIACQrcIkwcAEYDACIACQpNIkwcAEYDACMAAgq0I8QYAL4AAAAA.Waraight:BAACNQAFFIEQAAIWAAUKahrnBAChAQAWAAUKahrnBAChAQA1AAQKgRwAAhYACQoaJI4EAIoDABYACQoaJI4EAIoDAAAA.Wardrarth:BAAANQAECgYJCwAAAA==.Waterdroplet:BAAANQADCgcICgAAAA==.',
Wh='Whodofthunk:BAAANQADCggIFQAAAA==.',
Wi='Wighttrash:BAAANQAECgQIBAABNQAECgkJFwANABQYAA==.Wilferth:BAAANQAECgYICgAAAA==.Willøw:BAAANQAECgMJAwAAAA==.Wirl:BAAANQADCggICAAAAA==.',
Wo='Woozi:BAABNQAFFIEJAAIFAAUKTwyGBQCFAQAFAAUKTwyGBQCFAQAAAA==.',
Wr='Wrinklz:BAABNQAECoEeAAMiAAkK0BPFWwB6AgAiAAkK0BPFWwB6AgAjAAMKrwjyHQCNAAAAAA==.Wrlymoonbat:BAAANQADCgQIBwAAAA==.',
Wu='Wuggles:BAAANQAECgIIAgAAAA==.',
Xa='Xavierson:BAAANQAECgIIAgAAAA==.',
Xe='Xelot:BAAANQAECgEJAQAAAA==.',
Xi='Xilone:BAAANQADCgUICQAAAA==.',
Ya='Yangchengfu:BAAANQAECgQICAAAAA==.',
Yi='Yi:BAAANQAECgQJBQAAAA==.',
Za='Zaaga:BAAANQAECgUICQAAAA==.Zaeth:BAAANQADCgYJBgAAAA==.Zamon:BAAANQADCgYICwAAAA==.Zamyk:BAAANQADCgUJBQAAAA==.Zaqor:BAAANQABCgIIAgAAAA==.Zarf:BAAANQAECgcIEQAAAA==.Zariq:BAAANQADCgUIBQAAAA==.Zayra:BAAANQADCgUIBQAAAA==.',
Ze='Zeld:BAAANQAECgYJDwAAAA==.Zelgius:BAABNQAECoEdAAMfAAgKtiUJBQBlAwAfAAgKcCUJBQBlAwAgAAUKuB2nRAB9AQAAAA==.Zenfel:BAAANQAECgUICgAAAA==.Zephalor:BAAANQAECgYIBgAAAA==.Zeroyz:BAAANQAECgEJAQAAAA==.',
Zh='Zhulee:BAAANQAECgYJDwAAAA==.',
Zi='Zikaja:BAAANQAECgYIBgABNQAFFAQICQAWAPUEAA==.Zir:BAAANQAECgUICgAAAA==.',
Zo='Zoark:BAAANQADCggJEAAAAA==.Zorgap:BAAANQAECggIDQAAAA==.Zorgaw:BAAANQAECgIIAgAAAA==.',
Zu='Zuggwithin:BAAANQAECgYIEgAAAA==.Zuldope:BAAANQADCgQIBAAAAA==.',
Zy='Zygo:BAAANQAECgEIAQAAAA==.Zynestra:BAAANQABCgEIAQAAAA==.Zyprexen:BAAANQADCgYIDgAAAA==.Zyprexius:BAAANQAECgYIEwAAAA==.',
['Ða']='Ðadgar:BAAANQADCggIDgAAAA==.',
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
