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

local lookup = {'Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Devourer','Shaman-Restoration','Priest-Holy','Priest-Shadow','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Druid-Restoration','Druid-Balance','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Evoker-Devastation','DeathKnight-Blood','Shaman-Elemental','Warrior-Fury','DemonHunter-Havoc','Mage-Arcane','Warrior-Protection','Paladin-Retribution','Paladin-Protection','Shaman-Enhancement','Mage-Frost','Evoker-Preservation','Druid-Feral','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','Priest-Discipline','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Holy','Evoker-Augmentation','DemonHunter-Vengeance',}
local provider = {region='US',realm='Lothar',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaliara:BAAANQAECgMIAwAAAA==.',
Ab='Absynthae:BAAANQADCgYICwAAAA==.',
Ac='Ackreser:BAAANQAECgEIAgAAAA==.',
Ad='Adorath:BAAANQADCgUICAAAAA==.',
Ae='Aelethia:BAAANQADCgEIAQABNQADCggIFQABAAAAAA==.Aesirah:BAAANQADCgUIBQAAAA==.Aeven:BAAANQADCgEIAQABNQAFFAMIBgACAPISAA==.',
Ai='Aidan:BAACNQAFFIErAAMDAAkKmSQCAAAbBAADAAkKmSQCAAAbBAAEAAEKQibRBgBuAAA1AAQKgR4AAwMACQovJskDAIMDAAMACQovJskDAIMDAAQAAgqaJgwbANYAAAAA.Aidhan:BAABNQAECoEbAAIFAAkKNiSLCAA2AwAFAAkKNiSLCAA2AwABNQAFFAkJKwADAJkkAA==.Aileron:BAACNQAFFIEGAAIGAAQKiQyZCwAxAQAGAAQKiQyZCwAxAQA1AAQKgSMAAgYACQpCIk4PACEDAAYACQpCIk4PACEDAAAA.Airlin:BAAANQADCgYICgAAAA==.',
Ak='Akshana:BAAANQAECgEIAQAAAA==.',
Al='Alcore:BAAANQAECgQJBQAAAA==.Aldrigor:BAAANQAECgIIAgAAAA==.Alett:BAAANQAECgIIAgAAAA==.Alivathus:BAABNQAECoErAAMHAAkKKiQXAwCmAwAHAAkKKiQXAwCmAwAIAAEKfg6CYAA1AAAAAA==.Alluu:BAAANQADCgUIBQAAAA==.Alsong:BAAANQADCgUIDAAAAA==.Alvart:BAAANQAECgIIAgAAAA==.',
Am='Ambervoid:BAAANQAECgUJCgAAAA==.Amiko:BAAANQAECgMIAwAAAA==.',
An='Annaisa:BAAANQABCgUIBQAAAA==.Ansigar:BAAANQADCgcIBwAAAA==.',
Ar='Arbark:BAABNQAECoEhAAQJAAkK+CQhAQAxAwAJAAgKjiUhAQAxAwAKAAgKmCOsHwDTAgALAAQKLCCHHwBgAQAAAA==.Arcada:BAAANQADCgYIBgAAAA==.Archdemon:BAAANQADCgUIBQAAAA==.Arcnfrost:BAAANQAECgQICQAAAA==.Ardone:BAAANQABCgIIAgAAAA==.Arkadis:BAAANQAECgUIDgAAAA==.Armina:BAAANQAECgYIBgAAAA==.Arrothin:BAAANQABCggIFgAAAA==.',
As='Asdanoth:BAAANQADCggICwAAAA==.Ashenbrawl:BAAANQAECggIEAAAAA==.Ashenclaw:BAAANQAECgUICwAAAA==.Aspinks:BAAANQAECgIIAgABNQAECggIIQAKAO8KAA==.',
Au='Auxie:BAAANQAECgcIDwAAAA==.',
Av='Availl:BAAANQADCgcIBwABNQAECgIIAwABAAAAAA==.Avatipup:BAAANQAECgQIBgAAAA==.',
Aw='Aweinon:BAAANQADCgQIBAAAAA==.',
Ay='Aydan:BAAANQAECgIIAgABNQAFFAkJKwADAJkkAA==.Aydin:BAACNQAFFIEIAAIMAAQKQxmrDwBJAQAMAAQKQxmrDwBJAQA1AAQKgRsAAgwACQpvJNUTAFMDAAwACQpvJNUTAFMDAAE1AAUUCQkrAAMAmSQA.Aylan:BAAANQADCgMIAwAAAA==.',
Az='Azelous:BAAANQADCggICAABNQAECgkJKQAGAHgiAA==.Azumaa:BAAANQADCggIIwAAAA==.Azurath:BAAANQAECgIIAwAAAA==.Azureth:BAAANQADCgEIAQAAAA==.',
Ba='Bainironwind:BAAANQADCgUIBQAAAA==.Baiwushi:BAAANQAECgcIEgAAAA==.Ballock:BAAANQADCggICAAAAA==.Balázs:BAAANQAECgQJCAAAAA==.Barloc:BAAANQADCgUIBQAAAA==.',
Be='Becbec:BAAANQADCgcICwAAAA==.Beckyplease:BAAANQADCgYIBgAAAA==.Belaghal:BAAANQADCgUIBQAAAA==.Ben:BAAANQAECgEIAQABNQAECgUIDAABAAAAAA==.Bestricer:BAAANQAECgIIAgABNQAFFAgIJQADAJ4gAA==.',
Bi='Biggles:BAECNQAFFIEOAAMNAAUKmxHTAwCgAQANAAUKmxHTAwCgAQAOAAEKPQumHQBIAAA1AAQKgSEAAw0ACQr5FDwZACECAA0ACQr5FDwZACECAA4ACAq2E6EzAP8BAAAA.Bighuntarizo:BAAANQAECgYIDQAAAA==.Billevilbill:BAAANQAECgYIDQAAAA==.',
Bl='Blobney:BAACNQAFFIEZAAMKAAcK/CFSAQBXAgAKAAYKbSFSAQBXAgALAAIK7yPLAwDOAAA1AAQKgSEAAwsACQoYJuYFAKMCAAoABwr8Jb0bAOcCAAsABwoWI+YFAKMCAAAA.Bloodymouth:BAAANQAECgIIAgABNQAECgcIDwABAAAAAA==.Bluechip:BAAANQAECgYIEwAAAA==.Blueeagle:BAACNQAFFIEHAAMPAAMKyBpmEgCnAAAPAAIKsxlmEgCnAAAQAAEK8hxrAQBeAAA1AAQKgSYABA8ACQoRJYcHAEEDAA8ACQo8JIcHAEEDABAAAwrhJQEJAEsBABEAAQrUJn38AHEAAAAA.Bluespell:BAAANQAECgMJBgABNQAFFAMIBwAPAMgaAA==.',
Bo='Boldalgaz:BAAANQAECgEIAQAAAA==.Bolts:BAAANQADCgYIEgAAAA==.Borak:BAAANQADCgQIBAABNQAECgkJKQAGAHgiAA==.',
Br='Braezlor:BAAANQADCgcIBwAAAA==.Brendel:BAAANQAECgEIAgAAAA==.Brewdarymor:BAAANQAECgYICQABNQAECgkJIAASAIAUAA==.Broaahhaha:BAAANQAECgEIAgAAAA==.Brumduhr:BAAANQADCgYIBgAAAA==.',
Bu='Bulletsponge:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Butterflyy:BAABNQAECoEhAAIRAAgKSxInUgAqAgARAAgKSxInUgAqAgAAAA==.Butternutt:BAAANQADCgIIAgAAAA==.',
Ca='Caelena:BAAANQAECgQICwAAAA==.',
Ce='Celestial:BAABNQAECoEgAAMLAAgKExOTDAAbAgALAAgKPxKTDAAbAgAJAAIK9hFoGACCAAAAAA==.',
Ch='Chilltest:BAAANQAECgQIBwAAAA==.Chronobacon:BAAANQADCgYICgABNQAECgkJIAASAIAUAA==.Chupacabra:BAAANQAECgEIAQAAAA==.Chuyz:BAABNQAECoEYAAIRAAkKNhgQMACcAgARAAkKNhgQMACcAgAAAA==.Chuyzz:BAABNQAECoEjAAITAAYKoxudPADOAQATAAYKoxudPADOAQAAAA==.',
Cl='Clawdene:BAAANQADCgQIBwAAAA==.Clickchi:BAAANQADCggIFwAAAA==.Cloudwarrior:BAAANQADCgEIAQABNQAECgkJIgAUAFgeAA==.',
Co='Cokediet:BAAANQAECgMIBwAAAA==.Cooties:BAAANQADCgUIBQABNQAECgEIAgABAAAAAA==.Cordeliaa:BAAANQADCggIFgAAAA==.Coven:BAAANQAECgIIAwAAAA==.',
Cr='Crunch:BAABNQAECoEmAAMVAAkK9COcAACvAwAVAAkK9COcAACvAwAMAAMKvRK85QCvAAAAAA==.',
Cy='Cynderelle:BAAANQADCgYIEAAAAA==.Cynikka:BAAANQAECgYIDwAAAA==.Cynthor:BAAANQAECgYIEgAAAA==.',
Da='Dadtothebone:BAAANQADCggIFAAAAA==.Daghahi:BAABNQAECoEYAAIEAAcKsxqNCwAPAgAEAAcKsxqNCwAPAgAAAA==.Daishanar:BAAANQAECgYIDgAAAA==.Dalethyr:BAAANQAECgQIBAAAAA==.Darkseid:BAAANQADCgQJBAAAAA==.Darren:BAAANQADCgQIBAAAAA==.Darthflame:BAAANQADCgUIBQABNQAECggIIAAWAEEUAA==.Datavi:BAAANQADCgYIBgAAAA==.David:BAAANQAECgEIAwABNQAECgUIDAABAAAAAA==.Dawuffman:BAAANQAECgYIEAAAAA==.Daylia:BAAANQADCgYIBgAAAA==.',
De='Deathash:BAAANQAECgEIAQAAAA==.Deathdruid:BAAANQAECgYIEAAAAA==.Deathfarm:BAAANQAECgUICwAAAA==.Delaktrirr:BAAANQAECgEIAQAAAA==.Deliverenc:BAAANQAECgQIBAAAAA==.Delmus:BAAANQAECgYIEAAAAA==.Delphinae:BAAANQAECgEIAQAAAA==.Demontwink:BAAANQADCggIFwAAAA==.Demount:BAAANQADCgcICAAAAA==.Devera:BAABNQAECoEYAAIOAAkKpxQ/LQAvAgAOAAkKpxQ/LQAvAgABNQAECgkJGQAUAKIaAA==.',
Di='Dinkylock:BAAANQADCggIDAAAAA==.Dirtykahuna:BAAANQAECgQICQAAAA==.Dirtymagus:BAAANQADCgYIBgABNQAECgQICQABAAAAAA==.Dirtypali:BAAANQADCgUIBQABNQAECgQICQABAAAAAA==.Discosticks:BAAANQAECgEIAQAAAA==.Distress:BAAANQAECgEIAQAAAA==.',
Do='Dojoshaman:BAABNQAECoEbAAIUAAgKsSHtGQACAwAUAAgKsSHtGQACAwAAAA==.Doodman:BAAANQAECgYIDAAAAA==.Doubleshot:BAAANQAECgEIAQAAAA==.',
Dr='Dragondeez:BAAANQADCgUIBQABNQAECggIGwAXAL8YAA==.Dreadrend:BAAANQAECggIDQAAAA==.Dropsin:BAAANQADCggICAAAAA==.Drwn:BAAANQAECgQICgAAAA==.',
Du='Duckroll:BAAANQAECgEIAQAAAA==.Dustmaster:BAAANQABCgIIBgAAAA==.',
Dw='Dwelknarr:BAAANQAECgEIAQAAAA==.Dwlirious:BAAANQAECgYIEgAAAA==.',
Ea='Eadric:BAAANQAECgIIAgAAAA==.Earendur:BAAANQADCggIJAAAAA==.Earthfury:BAAANQAECgQIBgABNQAECgYIDAABAAAAAA==.Eaven:BAAANQADCgIIAgABNQAFFAMIBgACAPISAA==.',
Ed='Edalasar:BAAANQAECgEIAQAAAA==.Edallen:BAAANQAECgYIEAAAAA==.',
Ee='Eelyroc:BAAANQADCgMIAwAAAA==.',
El='Elbrujo:BAAANQAECgQJCgAAAA==.Eleaanor:BAAANQADCgYIBgAAAA==.Elementals:BAAANQAECggJAQAAAA==.',
Em='Emaytete:BAAANQAECgUIBgAAAA==.Emayteteheww:BAAANQAECgMIBwAAAA==.Emaytetem:BAAANQADCgMIAwAAAA==.Emillyra:BAAANQADCggIFQAAAA==.Empress:BAAANQAECgEIAQABNQAFFAUIDQATAKgiAA==.',
Ep='Ephemra:BAAANQADCggJBwAAAA==.',
Es='Esteban:BAAANQAECgQIBQAAAA==.',
Ev='Evisette:BAAANQADCgIIAgAAAA==.Evokethywikd:BAABNQAECoEWAAISAAkK7wxnEQD/AQASAAkK7wxnEQD/AQABNQAECgEIAQABAAAAAA==.',
Fa='Fahx:BAAANQAECgIIAgAAAA==.Falwyn:BAAANQAECgIIAwAAAA==.Famidore:BAAANQADCgIIBAAAAA==.Faèlyn:BAAANQADCgUICQAAAA==.',
Fe='Felflamel:BAABNQAECoEgAAIWAAgKQRR4KQAAAgAWAAgKQRR4KQAAAgAAAA==.Feltest:BAAANQAECgcJDwAAAA==.Feralized:BAAANQADCgYIBwAAAA==.Ferdinan:BAABNQAECoEdAAIMAAkKXg7daQAIAgAMAAkKXg7daQAIAgAAAA==.',
Fl='Flareon:BAAANQAECgEIAQABNQAFFAcIDwAGAA8ZAA==.Flashter:BAABNQAECoEXAAMMAAcKbxHtiACsAQAMAAcKNRHtiACsAQAYAAEKQxYrMQA/AAAAAA==.Flax:BAAANQADCgMIAwAAAA==.Fluffycuddle:BAAANQADCgUICQAAAA==.Fluffymage:BAAANQADCgEIAQABNQAECgkJIAASAIAUAA==.',
Fo='Forrealzies:BAAANQAECgQIBAAAAA==.Fortunato:BAAANQADCgEIAQAAAA==.',
Fr='Frankhs:BAAANQAECgIJAgAAAA==.',
Fu='Furchi:BAAANQADCgIIAgABNQAECgYIEAABAAAAAA==.',
Ga='Galdrel:BAAANQAECgQICQAAAA==.Gallince:BAACNQAFFIEOAAIZAAYK5SPbAACBAgAZAAYK5SPbAACBAgA1AAQKgR4AAhkACQoSJh4IAKYDABkACQoSJh4IAKYDAAAA.Garbich:BAAANQADCgEIAgABNQADCgcIBwABAAAAAA==.Gary:BAAANQAECgYIEAAAAA==.',
Ge='Gerhart:BAAANQAECgEIAQAAAA==.',
Gh='Ghostsham:BAACNQAFFIEaAAIUAAcKBB6vAAC4AgAUAAcKBB6vAAC4AgA1AAQKgSUAAxQACQq1JXoCANYDABQACQq1JXoCANYDAAYAAwoJA27JAIAAAAAA.Ghðst:BAAANQAFFAMIAwABNQAFFAcIGgAUAAQeAA==.',
Gi='Gilgamet:BAAANQADCgEIAQAAAA==.Gizmito:BAAANQADCgQIBQAAAA==.',
Gl='Glizzyman:BAAANQAECgcIEQAAAA==.',
Gn='Gnarfarm:BAAANQAECgQIBwAAAA==.',
Go='Go:BAAANQADCgYJBgABNQAECgUIBgABAAAAAA==.Goldoran:BAAANQADCgIIAgAAAA==.Gonette:BAAANQADCgYIBgABNQAECgcIGAAaALogAA==.Goniff:BAABNQAECoEYAAIaAAcKuiCdDwBXAgAaAAcKuiCdDwBXAgAAAA==.Goransk:BAAANQAECgEIAgAAAA==.Gorsk:BAAANQADCgYIBgABNQAECgEIAgABAAAAAA==.',
Gr='Gracelious:BAABNQAECoEgAAIZAAcK9hu1XgAmAgAZAAcK9hu1XgAmAgAAAA==.Graebeard:BAAANQADCggIFQAAAA==.Graehame:BAAANQADCgYIDAAAAA==.Greyshadow:BAAANQADCgUIBQAAAA==.Grubber:BAAANQADCgYIBgABNQAECgUIBQABAAAAAA==.Grüb:BAAANQAECgUIBQAAAA==.',
Gu='Guitar:BAAANQAECgQIBAAAAA==.Guntran:BAABNQAECoEgAAIZAAgKSBxZRgB1AgAZAAgKSBxZRgB1AgAAAA==.Gurkha:BAAANQADCgYIBwAAAA==.Gurthock:BAAANQAECgYICgAAAA==.',
Gw='Gwenixx:BAAANQADCggIJQAAAA==.',
Ha='Halios:BAAANQADCgcIDQAAAA==.',
He='Headhuntin:BAAANQAECgYIDwAAAA==.Heatfang:BAAANQADCgcICQAAAA==.Hellifiknow:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Hellione:BAAANQAECgYIDwAAAA==.Hellmaree:BAAANQADCgEIAQAAAA==.Helltest:BAAANQAECgEIAQAAAA==.',
Hi='Hiruzèn:BAAANQAECgQIBwAAAA==.',
Ho='Holyspurb:BAAANQADCgYIBgAAAA==.Holywater:BAABNQAECoEXAAIIAAcKwQ6cKwB3AQAIAAcKwQ6cKwB3AQAAAA==.Honkinhammer:BAAANQADCgYJBgABNQAECgQIBAABAAAAAA==.Hotdogman:BAACNQAFFIEaAAIPAAgKfSE9AAA2AwAPAAgKfSE9AAA2AwA1AAQKgSEAAg8ACQptJu8AAN4DAA8ACQptJu8AAN4DAAE1AAQKAwgEAAEAAAAA.Hotdumpling:BAAANQAECgUIDgAAAA==.',
Hu='Hualing:BAAANQADCgQIBAAAAA==.Huegarak:BAAANQAECgQJBgAAAA==.',
Hy='Hyle:BAAANQAECgYIEAAAAA==.',
Il='Illidaddy:BAAANQADCgMIAwABNQAECggIGwAXAL8YAA==.Illuminator:BAAANQADCggIJQAAAA==.',
In='Inspectadeck:BAACNQAFFIEKAAMKAAUKOQR6FADsAAAKAAQKaAR6FADsAAALAAEKfQNRGQBNAAA1AAQKgTEAAwoACQqwHYIhAMsCAAoACQpIHYIhAMsCAAsABApjFjInACcBAAAA.',
Ir='Irsh:BAAANQADCggICAAAAA==.',
Is='Istariel:BAAANQAECgIIAgABNQAFFAcIGgAUAAQeAA==.',
It='Ithoron:BAABNQAECoEfAAITAAgKihUhMwABAgATAAgKihUhMwABAgAAAA==.',
Iv='Ivoree:BAAANQABCgEIAQAAAA==.',
Ja='Jaytov:BAAANQABCgQIBAAAAA==.Jazu:BAAANQAECgYIDQAAAA==.',
Je='Jerks:BAABNQAECoEcAAMbAAgKwxFcDwAxAgAbAAgKwxFcDwAxAgAGAAIK8xE12QBZAAAAAA==.',
Jo='Jost:BAAANQADCgMIAwABNQAECgUIBgABAAAAAA==.Joval:BAAANQADCggIJgAAAA==.Jozeph:BAAANQAECgYIDAAAAA==.',
['Jà']='Jàmie:BAAANQAECgYIBgAAAA==.',
Ka='Kaalar:BAABNQAECoEdAAIRAAgKoxqEPABuAgARAAgKoxqEPABuAgAAAA==.Kaestirael:BAAANQAECgEIAQAAAA==.Kakarrot:BAAANQAECgIJAgAAAA==.Kalichnakov:BAAANQADCgYIBgAAAA==.Kamoura:BAABNQAECoEXAAIcAAcKwBiBCAAHAgAcAAcKwBiBCAAHAgAAAA==.Kapeta:BAAANQAECgUICQAAAA==.Karmen:BAACNQAFFIEPAAIdAAUKRh/FBADeAQAdAAUKRh/FBADeAQA1AAQKgSEAAh0ACQrwIrsCAIMDAB0ACQrwIrsCAIMDAAAA.Karnatron:BAAANQAECgQIBAAAAA==.Karnvoid:BAAANQADCggJCAABNQAECgQIBAABAAAAAA==.Katalain:BAAANQADCggICQABNQAECgkJJgANAGocAA==.Kayleave:BAAANQABCgEIAQAAAA==.Kazz:BAAANQADCggICAABNQAECgkJIgAeAOUfAA==.',
Ke='Keattz:BAACNQAFFIEiAAIMAAgK4SFMAABCAwAMAAgK4SFMAABCAwA1AAQKgS0AAgwACQqwJsoBAOkDAAwACQqwJsoBAOkDAAE1AAQKCQklAB8AaiMA.Keattzxd:BAABNQAECoElAAMfAAkKaiNDAgCiAwAfAAkKaiNDAgCiAwAgAAMKPQ/bNwC2AAAAAA==.Keedill:BAABNQAECoEXAAMKAAgKEBQeZQDYAQAKAAcKmBQeZQDYAQAJAAIKpg/iGAB9AAAAAA==.Keelinnea:BAAANQAECgEIAQAAAA==.Keelu:BAAANQADCgEIAQAAAA==.Keggerz:BAAANQADCgcIDAAAAA==.Kennagi:BAAANQAECgQICQAAAA==.Kenshunterl:BAAANQAECgEIAQAAAA==.',
Kh='Khanzen:BAAANQAECgQIBgAAAA==.Khathgar:BAAANQAECgUIDgABNQAECgkJJwAeAM4aAA==.Khovastis:BAACNQAFFIENAAIOAAUKmRrgBwCjAQAOAAUKmRrgBwCjAQA1AAQKgSEABA4ACQrFGRorAEACAA4ACArzGhorAEACACEAAwr5E8wpALsAAB4AAgqSFiMjAH0AAAAA.',
Ki='Kianll:BAAANQAECggICAAAAA==.Kitchntabls:BAACNQAFFIEOAAIWAAUKPBrcBAC0AQAWAAUKPBrcBAC0AQA1AAQKgSEAAxYACQqlJeMCALkDABYACQqlJeMCALkDAAUAAwr/D51JAJ8AAAAA.',
Kj='Kjirou:BAAANQAECgYIEgAAAA==.',
Ko='Koenji:BAACNQAFFIENAAIbAAUK/RZCAQC6AQAbAAUK/RZCAQC6AQA1AAQKgR4AAhsACQqMIQQEAD8DABsACQqMIQQEAD8DAAAA.Korely:BAAANQADCggICAAAAA==.Korenn:BAAANQADCgQIBAAAAA==.Korgrim:BAAANQAECgEIAgAAAA==.',
Ky='Kymal:BAAANQAECgEIAQAAAA==.Kyndel:BAAANQADCgQIBwAAAA==.Kyndrah:BAABNQAECoEaAAQHAAgKhxDZTgDiAQAHAAgKRhDZTgDiAQAIAAgKFg32JAC2AQAiAAMKaQSTFwB5AAABNQADCgQIBwABAAAAAA==.',
['Kä']='Käne:BAAANQAECgYIEAAAAA==.',
['Kì']='Kìn:BAAANQADCgIIAgABNQAECgcIEgABAAAAAA==.',
['Kí']='Kín:BAAANQADCgEIAQABNQAECgcIEgABAAAAAA==.',
La='Lableue:BAAANQAECgEIAgAAAA==.Lavacask:BAAANQADCggJHgAAAA==.',
Le='Lehvy:BAAANQADCggICAABNQAECgkJKgAHAKwbAA==.Leodk:BAACNQAFFIEKAAMjAAQKUhw4BwALAQAjAAMKLhw4BwALAQAkAAEKvxxwEwBTAAA1AAQKgSIAAyMACQoLJd0GAFIDACMACQoLJd0GAFIDACQABApdHmhxAOIAAAE1AAUUBAoKACMAUhwA.Lerann:BAAANQADCgQIBAABNQAECggIGQAMAEYlAA==.Levey:BAABNQAECoEqAAIHAAkKrBssIQCyAgAHAAkKrBssIQCyAgAAAA==.Lewdcifer:BAAANQADCggIEAAAAA==.',
Li='Lick:BAAANQAECgMIAwABNQAECgUIBgABAAAAAA==.Lict:BAACNQAFFIEGAAIlAAMKHRAgDwDuAAAlAAMKHRAgDwDuAAA1AAQKgRoAAiUACQoBGNwqAIQCACUACQoBGNwqAIQCAAE1AAQKBQgGAAEAAAAA.Liekki:BAAANQADCgYIBwABNQAECgEIAQABAAAAAA==.Lillea:BAAANQAECgUICAAAAA==.Linada:BAAANQADCggIEgAAAA==.Listurfiend:BAAANQADCgIIAgAAAA==.Liteseraph:BAAANQAECgQIBAAAAA==.',
Lo='Loktalaan:BAACNQAFFIEIAAIbAAUKuQmRAQCQAQAbAAUKuQmRAQCQAQA1AAQKgSkAAhsACQqjGn8GAPkCABsACQqjGn8GAPkCAAAA.Lothlorian:BAAANQADCgEIAQAAAA==.',
Lu='Luan:BAAANQAECgQIBAAAAA==.Lucien:BAABNQAECoEmAAINAAkKahzJCgDoAgANAAkKahzJCgDoAgAAAA==.Lute:BAABNQAECoEZAAMUAAgK/iP1EgA2AwAUAAgK/iP1EgA2AwAGAAEKyA1W+gAiAAAAAA==.',
Ly='Lyfeguard:BAAANQAECgYIDwAAAA==.',
Ma='Machoke:BAAANQADCgYIDQAAAA==.Mahito:BAABNQAECoEiAAIeAAkK5R/wAgBLAwAeAAkK5R/wAgBLAwAAAA==.Maiha:BAAANQAECgYIBwABNQAECggICgABAAAAAA==.Malenia:BAACNQAFFIEMAAMKAAQKQguRFgDeAAAKAAMKIg2RFgDeAAALAAIKcAdiDQCZAAA1AAQKgSIABAsACQpDH+EaAIgBAAoACArRF4dMACgCAAsABQoqH+EaAIgBAAkAAgpKEdkbAGYAAAAA.Malume:BAAANQADCgYICAAAAA==.Malyon:BAAANQADCgEIAQAAAA==.Malístra:BAAANQADCggICgAAAA==.Manaless:BAAANQAECgEIAQABNQAFFAQKCgAjAFIcAA==.Marderer:BAABNQAECoEYAAIfAAcKAA+CLgC2AQAfAAcKAA+CLgC2AQAAAA==.Masakari:BAABNQAECoEYAAIRAAcKlgytewC4AQARAAcKlgytewC4AQAAAA==.Materia:BAAANQAECgIIAwAAAA==.Mathmagician:BAABNQAECoEbAAIXAAgKvxidZACFAgAXAAgKvxidZACFAgAAAA==.Maulfarm:BAACNQAFFIEHAAMeAAUKRxHsAABgAQAeAAQKVhXsAABgAQAOAAEKCAHwIQAkAAA1AAQKgR8AAh4ACQqMID0DADoDAB4ACQqMID0DADoDAAAA.Mazz:BAAANQABCgYIBgABNQAECgEIAQABAAAAAA==.Mazzlock:BAAANQAECgEIAQAAAA==.',
Mc='Mclovn:BAAANQADCgEIAQAAAA==.',
Me='Megameow:BAABNQAECoEnAAMeAAkKzhrbBADrAgAeAAkKzhrbBADrAgANAAQKLA2UOgDgAAAAAA==.Mercuria:BAAANQADCgMIAwAAAA==.Messmer:BAAANQADCggICQAAAA==.Metaclass:BAAANQAECgIIAwAAAA==.',
Mi='Mirâ:BAAANQADCgcIBwAAAA==.Mitrixx:BAAANQAECgcIEQAAAA==.Miztie:BAAANQADCgQIBAAAAA==.',
Mo='Mobius:BAAANQAECgEIAQAAAA==.Mokuo:BAAANQAECgUIBQAAAA==.Moonthorn:BAAANQAECgUICAAAAA==.Morrow:BAAANQADCgEIAQAAAA==.Mort:BAAANQADCggJIQAAAA==.Moxou:BAAANQAECgIIAgABNQAFFAYIEgAGABcYAA==.Moxxou:BAACNQAFFIESAAIGAAYKFxhcAwAJAgAGAAYKFxhcAwAJAgA1AAQKgSEAAgYACQpUJVICALADAAYACQpUJVICALADAAAA.Moyi:BAAANQAECgEJAQAAAA==.',
Mu='Mulch:BAABNQAECoEkAAINAAgK6Q2LIQC/AQANAAgK6Q2LIQC/AQAAAA==.',
My='Mybelle:BAAANQADCgIIAgAAAA==.Mysticle:BAAANQADCgcIEQAAAA==.Mythaltis:BAAANQAECgYIEwAAAA==.',
Na='Naedori:BAAANQADCgYICAABNQADCggIDAABAAAAAA==.Naizhruk:BAAANQADCgEIAQAAAA==.Nall:BAAANQADCgIIBAAAAA==.Naoh:BAAANQADCgQJBAAAAA==.Narache:BAAANQADCgYIBwAAAA==.Naturerend:BAAANQADCgYJBgAAAA==.Naul:BAACNQAFFIEFAAISAAMKfQ4HBwDcAAASAAMKfQ4HBwDcAAA1AAQKgRQAAxIACQoaDUsTANkBABIACAqIDksTANkBACYAAgpfAR4bADwAAAAA.Naull:BAAANQAECgEIAgAAAA==.Naysayer:BAAANQADCgEIAQAAAA==.Naúl:BAAANQADCgUIBQAAAA==.',
Ne='Necrokai:BAAANQAECgcIEQAAAA==.Necroscourge:BAAANQAECgYIEAABNQAECgcIEQABAAAAAA==.Neighter:BAAANQAECgQIBgAAAA==.Nerevar:BAAANQADCggIIwAAAA==.Netal:BAAANQAECgQJCgAAAA==.Nevergoback:BAAANQADCgcICwABNQAECgcIGgATALINAA==.',
Ni='Ninejuanjuan:BAABNQAECoEgAAIlAAgK9BStNABWAgAlAAgK9BStNABWAgAAAA==.Nishikienrai:BAAANQAECgEIAgAAAA==.',
No='Nochit:BAACNQAFFIEPAAIOAAYKpRzMAgBSAgAOAAYKpRzMAgBSAgA1AAQKgSUAAg4ACQrSJjgBAOMDAA4ACQrSJjgBAOMDAAAA.Noctula:BAAANQAECgQIEwABNQAECgcIEQABAAAAAA==.Norbiee:BAAANQAECgUIDAAAAA==.Nored:BAAANQAECgMIAwAAAA==.Norne:BAABNQAECoEgAAIWAAgKWhnxIQBAAgAWAAgKWhnxIQBAAgAAAA==.Nowfaleena:BAAANQAECgMIAwAAAA==.Nozok:BAAANQADCggICAAAAA==.',
Ny='Nymphira:BAAANQAECgUIBQAAAA==.Nytkiller:BAAANQAECgEIAQAAAA==.Nyzul:BAAANQAECgIIAwABNQAECgYIEAABAAAAAA==.',
['Në']='Nëv:BAAANQADCgIIAgAAAA==.',
Oa='Oatie:BAAANQADCgUIAwAAAA==.',
Oc='Oceanic:BAAANQAECgUICQAAAA==.',
Od='Odlinn:BAAANQAECgUIDQABNQAECggIJAANAOkNAA==.',
On='Onlyhorns:BAAANQAECgYICgABNQAECggIHgAbAMwjAA==.',
Oo='Oogs:BAAANQAECgEIAQAAAA==.',
Op='Opalia:BAAANQAECgQIBQAAAA==.Opallea:BAAANQAECgIIAwABNQAECgIIAwABAAAAAA==.',
Or='Orch:BAAANQAECgYIEAAAAQ==.',
Ov='Overclocked:BAABNQAECoEhAAIKAAgK7wppdACpAQAKAAgK7wppdACpAQAAAA==.',
Pa='Paddington:BAAANQAECgYIEQAAAA==.Pahbi:BAAANQADCggIHgAAAA==.Palempi:BAAANQADCggICgAAAA==.Paul:BAAANQAECgUIDAAAAA==.',
Pe='Pendojo:BAAANQAECgcIDQAAAA==.Pendomage:BAAANQAECgYIDQAAAA==.',
Ph='Phobius:BAAANQAECgIIAgAAAA==.',
Pi='Pip:BAABNQAECoEZAAMUAAkKohrUPAA5AgAUAAgKnhrUPAA5AgAGAAIKDwOc1QBiAAAAAA==.Pipium:BAABNQAECoEYAAIJAAkK1SGRAwB7AgAJAAkK1SGRAwB7AgABNQAECgkJGQAUAKIaAA==.Pixsin:BAEANQADCgQIBQABNQAECgkJJQAKAJUYAA==.',
Po='Pookiehandz:BAABNQAECoEaAAITAAcKsg1TVgBUAQATAAcKsg1TVgBUAQAAAA==.Porpul:BAAANQAECgIIAgAAAA==.Powery:BAAANQAECgYIBgAAAA==.',
Pr='Project:BAAANQAECgQIBQAAAA==.Prophet:BAAANQADCgcIBwAAAA==.',
Pu='Publicbussy:BAAANQADCgcIFQAAAA==.Purples:BAAANQAECgYJCgAAAA==.Purpul:BAAANQAECgQIBAABNQAECgYJCgABAAAAAA==.',
Qa='Qawxz:BAAANQADCgUIBQAAAA==.',
Qu='Quicktail:BAAANQAECgEIAQABNQAECggIHAAcANMdAA==.',
Ra='Raikan:BAABNQAECoEZAAIMAAgKRiVEDwBvAwAMAAgKRiVEDwBvAwAAAA==.Rainwater:BAAANQADCgEIAQAAAA==.Raisins:BAAANQADCggJCAABNQAFFAUIDQAHAJ0bAA==.Raisyns:BAACNQAFFIENAAIHAAUKnRvZBgDZAQAHAAUKnRvZBgDZAQA1AAQKgSEAAwcACQq3IqUKAEoDAAcACQq3IqUKAEoDACIAAQqQHBweAEIAAAAA.Rammic:BAAANQADCgIIAgAAAA==.Randstohl:BAAANQADCggIDgAAAA==.Ratakhan:BAAANQADCgUICAAAAA==.Raulothim:BAAANQAECgYIDgAAAA==.',
Re='Rebell:BAAANQAECggICgAAAA==.Reelorn:BAAANQADCgYIBgAAAA==.Reny:BAAANQAECgIIAwAAAA==.Repentance:BAAANQADCgEIAQABNQADCgYIBwABAAAAAA==.Retribussy:BAAANQAECgcIEwAAAA==.',
Ri='Ricemachinex:BAABNQAECoEbAAMKAAkKOxaoXwDpAQAKAAcKPROoXwDpAQALAAMK5Ra6MADvAAABNQAFFAgIJQADAJ4gAA==.Ricemachnedk:BAAANQAECgcIBwABNQAFFAgIJQADAJ4gAA==.Riko:BAAANQADCggICgABNQAECgkJIgAeAOUfAA==.',
Ro='Rocthar:BAABNQAECoEdAAIlAAgK0Q3nUgDbAQAlAAgK0Q3nUgDbAQAAAA==.Roguelite:BAAANQADCgEIAQABNQAFFAQKCgAjAFIcAA==.Romarus:BAAANQAECgQICQAAAA==.Romeoposter:BAAANQAECgUICgAAAA==.',
Ru='Rukarazyll:BAAANQAECgMIAwAAAA==.Rumble:BAAANQAECgEIAQAAAA==.Rutherford:BAAANQADCgQIBAAAAA==.Ruush:BAAANQAECgMIAwAAAA==.',
Ry='Ryunohige:BAAANQADCggICAAAAA==.',
['Rú']='Rúúsh:BAAANQAECgQIBgAAAA==.',
Sa='Safeword:BAAANQAECgQICAAAAA==.Saihua:BAAANQADCgYIBgAAAA==.Saintjohn:BAAANQAECgcIBwAAAA==.Saintjon:BAAANQAECggICAAAAA==.Saintjonn:BAABNQAECoEXAAMkAAgKYgoPaQACAQAkAAcKyAsPaQACAQAjAAIKMAnVfgA9AAAAAA==.Saintrob:BAAANQADCgMJAwAAAA==.Sarthdidius:BAABNQAECoEeAAIWAAgKdAkYNgCaAQAWAAgKdAkYNgCaAQAAAA==.Sassparilluh:BAAANQADCggIIAAAAA==.Savalla:BAAANQADCgYIBgAAAA==.',
Sc='Schadenfreud:BAAANQAECgQIBQAAAA==.Scholoman:BAAANQADCggIDgAAAA==.Scratchbelly:BAAANQADCggIDQAAAA==.Scumdog:BAAANQADCgYIBgAAAA==.',
Se='Senpai:BAACNQAFFIELAAIXAAUKCA9/EgCSAQAXAAUKCA9/EgCSAQA1AAQKgSAAAxcACQr3H+oxAAsDABcACQr3H+oxAAsDABwAAQrlHwUyAEcAAAAA.Seoli:BAAANQAECgEIAQAAAA==.Serenya:BAAANQADCgYIBgAAAA==.',
Sh='Shalanthra:BAAANQAECgMIAwAAAA==.Shamallow:BAAANQADCgQIBAAAAA==.Shammunition:BAABNQAECoEeAAIbAAgKzCMjBAA8AwAbAAgKzCMjBAA8AwAAAA==.Shartner:BAAANQADCgMJAwAAAA==.Shartz:BAAANQAECgUICAAAAA==.Shaysa:BAEANQAECgUICgAAAA==.Sheraa:BAAANQAECgMIBgAAAA==.Shinigamisan:BAAANQAECgcIEAAAAA==.Shynox:BAAANQAECgYIDwAAAA==.Shümp:BAAANQAECgIIAgAAAA==.',
Si='Sinnerchrono:BAAANQADCggIBwAAAA==.Sinnwoo:BAAANQABCgQIBgAAAA==.Sitharco:BAAANQAECgMICgAAAA==.',
Sl='Sladex:BAAANQAECgIJAgAAAA==.Sleeptoken:BAAANQADCgEIAQAAAA==.',
Sm='Smorc:BAAANQAECgcIDwAAAA==.',
Sn='Snackwitch:BAAANQADCggJGwABNQAECgEIAQABAAAAAA==.Sneaki:BAAANQAECgUICQABNQAECgcIDwABAAAAAA==.',
So='Soarseas:BAAANQADCgYIBgAAAA==.Sommin:BAAANQADCgYICgAAAA==.Sorakah:BAAANQAECgMIBAAAAA==.Soulviper:BAABNQAECoEoAAMGAAkKhhcINQBHAgAGAAkKhhcINQBHAgAUAAIK4Q3m0wB7AAAAAA==.',
Sp='Spankmyflank:BAAANQAECgIIAwAAAA==.Spurblock:BAAANQADCgYJBgAAAA==.',
Sq='Squaleon:BAAANQADCgQIBAAAAA==.',
St='Stabbyfinch:BAAANQAECgEIAQAAAA==.Steatfox:BAAANQADCgUIBQAAAA==.Steplok:BAAANQAECgQJBAAAAA==.Stonestriker:BAAANQAECgEIAQAAAA==.Stooben:BAABNQAECoEcAAIMAAgKURV2ZwAPAgAMAAgKURV2ZwAPAgAAAA==.Stoobenh:BAAANQADCgYIBgAAAA==.Sturge:BAAANQADCggIHwAAAA==.',
Su='Supahsayajin:BAAANQAECgcIEAABNQAECgEIAQABAAAAAA==.',
Sw='Sweetbee:BAAANQAECgUICwAAAA==.Sweetpotato:BAAANQADCggICAAAAA==.Sweetvaldine:BAAANQADCgcICgAAAA==.Swole:BAAANQAECgQIBQAAAA==.',
Sy='Syanalody:BAAANQADCggIJQAAAA==.Sylarz:BAAANQAECgUICgABNQAECgkJIAASAIAUAA==.Sylenn:BAAANQADCggIHgAAAA==.Syn:BAABNQAECoEaAAMJAAcKRiF1BABSAgAJAAYKmyF1BABSAgAKAAIKIBls3wCeAAAAAA==.Synchro:BAAANQADCgQIBAAAAA==.',
Ta='Tanstaafl:BAABNQAECoEcAAIRAAgKkh6qKAC6AgARAAgKkh6qKAC6AgAAAA==.Taralom:BAAANQAECgEIAQAAAA==.Taurenspurb:BAAANQADCgYIBgAAAA==.Taz:BAEBNQAECoEoAAMnAAkKwCVYAADgAwAnAAkKwCVYAADgAwAWAAEKPQHmgQAFAAAAAA==.',
Te='Telmo:BAAANQAECgcIDQAAAA==.Tenebrix:BAAANQAECgUIBgAAAA==.Tenevoy:BAAANQAECggIEAABNQAFFAcIGgAUAAQeAA==.',
Th='Thadex:BAABNQAECoEYAAMMAAgKBCBJRQB+AgAMAAcK+iBJRQB+AgAVAAEKSBk7JABFAAAAAA==.Thebigfreeze:BAAANQABCgMIAQAAAA==.Thedood:BAAANQADCgYIBgAAAA==.Thedruidguy:BAAANQADCgQIBAAAAA==.Theldrid:BAABNQAECoErAAIkAAkKvSPaBgByAwAkAAkKvSPaBgByAwAAAA==.Thepallyguy:BAAANQAECgQIBAABNQAECgUIDQABAAAAAA==.Theprepared:BAAANQADCgYICgAAAA==.Thepriestguy:BAAANQAECgUIDQAAAA==.Theralethia:BAAANQAECgQIBAAAAA==.Therian:BAAANQADCgIJAwAAAA==.Theshamanguy:BAAANQAECgMIAwABNQAECgUIDQABAAAAAA==.Thorseas:BAAANQAECgYIEwAAAA==.Thunderkill:BAAANQADCgYICwAAAA==.',
Ti='Tirissa:BAAANQADCgEIAgAAAA==.',
To='Tooyew:BAAANQAECgYIBgABNQAFFAUIDgAMAP0UAA==.Tooyoo:BAACNQAFFIEOAAIMAAUK/RQsCwCXAQAMAAUK/RQsCwCXAQA1AAQKgRcAAgwACQqLIr8VAEkDAAwACQqLIr8VAEkDAAAA.Torpedotaka:BAAANQAECgMIBAAAAA==.',
Tp='Tpala:BAAANQAECgQICgAAAA==.',
Tr='Triggerfarm:BAABNQAECoEVAAIRAAgK/CPSDQBOAwARAAgK/CPSDQBOAwAAAA==.Tristis:BAAANQADCgYICgAAAA==.',
Tu='Turthunt:BAACNQAFFIERAAIPAAcK+hcrAgBLAgAPAAcK+hcrAgBLAgA1AAQKgSAAAw8ACQqYJHkUAJACAA8ABwpJJHkUAJACABEABgqRIi6GAJ0BAAAA.Turtrik:BAAANQAECgIIAgABNQAFFAcIEQAPAPoXAA==.',
Tw='Twinns:BAAANQADCgUIBQAAAA==.Twoyoo:BAAANQADCgYIBgABNQAFFAUIDgAMAP0UAA==.',
Ty='Tyesham:BAAANQADCgYICQABNQAECgIIBAABAAAAAA==.Tyice:BAAANQAECgIIBAAAAA==.',
Um='Umbriä:BAAANQADCgYICAABNQAECgUIBQABAAAAAA==.',
Ur='Urak:BAAANQADCgYIBgAAAA==.',
Va='Valaidpriest:BAAANQAECgcIDgAAAA==.Valoth:BAAANQADCgUICAAAAA==.Vanelura:BAAANQAECgIIAgAAAA==.Vaporeon:BAACNQAFFIEPAAIGAAcKDxl1AQBzAgAGAAcKDxl1AQBzAgA1AAQKgS0AAgYACQpFJUsBAMcDAAYACQpFJUsBAMcDAAAA.',
Ve='Velorth:BAAANQAECgMIBgAAAA==.',
Vr='Vrahmageddon:BAAANQAECgUIDwAAAA==.',
Vy='Vynlorin:BAACNQAFFIENAAITAAQK9QSdEADbAAATAAQK9QSdEADbAAA1AAQKgSAAAhMACQrQFHcwAA8CABMACQrQFHcwAA8CAAAA.',
Wa='Wahcked:BAAANQADCggICAAAAA==.Wahstella:BAACNQAFFIEfAAMXAAcK7xRdAwBYAgAXAAcKqhFdAwBYAgAcAAIKxhMNAwC4AAA1AAQKgS8AAxcACQpfJK8aAFkDABcACQrRI68aAFkDABwAAgq0I4AfALAAAAAA.Waraight:BAACNQAFFIEQAAITAAUKahqGBwCXAQATAAUKahqGBwCXAQA1AAQKgRwAAhMACQoaJJsGAHcDABMACQoaJJsGAHcDAAAA.Wardrarth:BAAANQAECgYIDgAAAA==.Waterdroplet:BAAANQADCgcICgAAAA==.',
Wh='Whitelady:BAAANQAECggICQAAAA==.Whodofthunk:BAAANQAECgIIAgAAAA==.',
Wi='Wighttrash:BAAANQAECgQIBAABNQAECgkJHwANAN0aAA==.Wilferth:BAAANQAECgYIDgAAAA==.Willøw:BAAANQAECgUIBgAAAA==.Wirl:BAAANQADCggICAAAAA==.',
Wo='Woozi:BAACNQAFFIELAAIGAAUKTwxwCAB5AQAGAAUKTwxwCAB5AQA1AAQKgRsAAgYACQrBFkswAF0CAAYACQrBFkswAF0CAAAA.',
Wr='Wrinklz:BAABNQAECoEjAAMXAAkKHRXTXwCSAgAXAAkKHRXTXwCSAgAcAAMKrwgKJACLAAAAAA==.Wrlymoonbat:BAAANQADCgQIBwAAAA==.',
Wu='Wuggles:BAAANQAECgIIAgAAAA==.',
Xa='Xavierson:BAAANQAECgIIBAAAAA==.',
Xe='Xelot:BAAANQAECgEIAQAAAA==.',
Xi='Xilone:BAAANQADCgUICQAAAA==.',
Ya='Yangchengfu:BAAANQAECgQICAAAAA==.',
Yi='Yi:BAAANQAECgUIBgAAAA==.',
Yn='Ynoga:BAAANQAECggICAAAAA==.',
Yo='Yootoo:BAAANQADCgMIAwABNQAFFAUIDgAMAP0UAA==.',
Za='Zaaga:BAAANQAECgUICQAAAA==.Zaeth:BAAANQADCgYJBgAAAA==.Zamon:BAAANQADCgYICwAAAA==.Zamyk:BAAANQAECgEIAQAAAA==.Zaqor:BAAANQABCgIIAgAAAA==.Zarf:BAABNQAECoEbAAIQAAgKZRHwBAAzAgAQAAgKZRHwBAAzAgAAAA==.Zariq:BAAANQADCgUIBQAAAA==.Zayra:BAAANQADCggIDQAAAA==.',
Ze='Zeld:BAAANQAECgcIEAAAAA==.Zelgius:BAABNQAECoElAAMjAAgKKSZtBQBrAwAjAAgKKSZtBQBrAwAkAAUKuB34VwBKAQAAAA==.Zenfel:BAAANQAECgYIEAAAAA==.Zephalor:BAAANQAECgYIDAAAAA==.Zeroyz:BAAANQAECgEJAQAAAA==.',
Zh='Zhulee:BAAANQAECgcIEAAAAA==.',
Zi='Zikaja:BAAANQAECgYIBgABNQAFFAQIDQATAPUEAA==.Zir:BAAANQAECgUICgAAAA==.',
Zo='Zoark:BAAANQADCggIFgAAAA==.Zorgap:BAAANQAECggIDgAAAA==.Zorgaw:BAAANQAECggICgAAAA==.',
Zu='Zuggwithin:BAABNQAECoEaAAIRAAcK2BXBWwAOAgARAAcK2BXBWwAOAgAAAA==.Zuldope:BAAANQAECgQIBAAAAA==.',
Zy='Zygo:BAAANQAECgEIAQAAAA==.Zynestra:BAAANQADCgMIAwAAAA==.Zyprexen:BAAANQADCgYIDgAAAA==.Zyprexius:BAABNQAECoEeAAMZAAgKpxeuVQBCAgAZAAgKpxeuVQBCAgAlAAQKUBMNlAAPAQAAAA==.',
['Ða']='Ðadgar:BAAANQAECgUIBQAAAA==.',
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
