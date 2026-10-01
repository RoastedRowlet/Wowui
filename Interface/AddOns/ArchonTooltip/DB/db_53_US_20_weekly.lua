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

local lookup = {'Shaman-Elemental','Druid-Balance','Unknown-Unknown','Priest-Holy','Rogue-Assassination','Hunter-BeastMastery','Paladin-Retribution','Paladin-Holy','Mage-Arcane','Mage-Frost','Druid-Guardian','Shaman-Restoration','Warrior-Arms','Warlock-Demonology','DeathKnight-Blood','Monk-Brewmaster','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Subtlety','DemonHunter-Vengeance','DemonHunter-Devourer','Warrior-Fury','Shaman-Enhancement','DemonHunter-Havoc','Monk-Mistweaver','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Evoker-Devastation','Monk-Windwalker','Mage-Fire','Druid-Feral','Warrior-Protection','Druid-Restoration','Priest-Discipline',}
local provider = {region='US',realm='Arthas',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abacas:BAACNQAFFIEIAAIBAAUKeBxWBQDQAQABAAUKeBxWBQDQAQA1AAQKgSQAAgEACQrSIrkLAHEDAAEACQrSIrkLAHEDAAAA.Abraanu:BAABNQAECoEZAAICAAgKhx8SHAC4AgACAAgKhx8SHAC4AgAAAA==.Abrohms:BAAANQAECgYIEwAAAA==.',
Ae='Aeily:BAEANQAECgMJAwAAAA==.Aethaeist:BAAANQAECgIJAQAAAA==.',
Ag='Agiel:BAAANQAECgcIDQAAAA==.',
Ah='Ahzula:BAAANQAECgEJAQABNQAECgcIEAADAAAAAA==.',
Ai='Aiger:BAAANQADCgUIBQAAAA==.Ais:BAABNQAECoEkAAIEAAgKzSOFCwBCAwAEAAgKzSOFCwBCAwAAAA==.Aitsu:BAACNQAFFIEIAAIFAAUK7xUDAwC4AQAFAAUK7xUDAwC4AQA1AAQKgSQAAgUACQpIJMcDAHcDAAUACQpIJMcDAHcDAAAA.Aivy:BAABNQAECoEhAAIGAAgKaCNdEAA7AwAGAAgKaCNdEAA7AwAAAA==.',
Aj='Ajm:BAAANQABCgEIAQAAAA==.',
Ak='Akkula:BAAANQADCggIFAAAAA==.Akutagawa:BAAANQADCgcJBwABNQAFFAUIDAAHAAolAA==.',
Al='Alaeris:BAAANQADCgcIBwAAAA==.Alexdare:BAABNQAECoEbAAIIAAcKkhqDQgAaAgAIAAcKkhqDQgAaAgAAAA==.Alfadelle:BAAANQAECgYIDgABNQAECgkJIwAJALAkAA==.Alicarrdd:BAAANQAECgQIBgAAAA==.Aling:BAAANQAECgEIAQABNQAECggIGAAFAE4hAA==.Allbeefpatty:BAAANQAECgYIEwAAAA==.Almostbald:BAACNQAFFIEJAAIJAAQKZBtyFgBjAQAJAAQKZBtyFgBjAQA1AAQKgScAAwkACQojI8wfAEYDAAkACQojI8wfAEYDAAoAAQolIrUrAF0AAAAA.Alneeshi:BAABNQAECoEfAAMCAAgKMx/SGgDDAgACAAgKeR7SGgDDAgALAAIKghgqLwCRAAAAAA==.Alybella:BAAANQAECgQIBQAAAA==.',
Am='Amoriandis:BAAANQADCgMJAwABNQAECgUIBQADAAAAAA==.',
An='Ancstrlbower:BAAANQADCgcJEwAAAA==.Anetra:BAAANQADCgcJDQAAAA==.Angharad:BAAANQADCgcICwABNQAECggIIAAMAFYkAA==.Anot:BAABNQAECoEeAAINAAkK9SH7EABlAwANAAkK9SH7EABlAwAAAA==.Anothai:BAAANQADCgYICQAAAA==.Anton:BAAANQADCggIDgABNQAECggIGAAFAE4hAA==.Anutterone:BAAANQAECgQIBAAAAA==.Anzat:BAAANQAECgIIAgAAAA==.',
Ap='Apsaroke:BAAANQADCgYICwAAAA==.',
Aq='Aqi:BAABNQAECoEaAAIEAAcK7B16PwAjAgAEAAcK7B16PwAjAgAAAA==.',
Ar='Aralle:BAAANQAECgQIBwAAAA==.Aranea:BAAANQAECgIIAgAAAA==.Arclaw:BAAANQADCgYJBgAAAA==.Arin:BAABNQAECoEXAAIOAAgK7R2/KACrAgAOAAgK7R2/KACrAgABNQAECgcIEAADAAAAAA==.Arkadu:BAAANQADCgEJAQAAAA==.Arkys:BAAANQADCgUJBQAAAA==.Arman:BAAANQADCgYIBgAAAA==.Armistice:BAAANQAECgEIAQAAAA==.Arrowyn:BAAANQAECgcIDAAAAA==.Arröwyn:BAAANQABCgMIAwAAAA==.',
As='Ashenis:BAAANQABCggICAAAAA==.Asphalt:BAAANQAECgYIDAAAAA==.Astrà:BAAANQADCgEJAQAAAA==.',
At='Attidk:BAABNQAECoEfAAIPAAgK/RXuLgAaAgAPAAgK/RXuLgAaAgAAAA==.',
Au='Augful:BAABNQAECoEaAAIQAAkKDAsEEACmAQAQAAkKDAsEEACmAQAAAA==.Auspicious:BAABNQAECoEvAAMEAAkKmR1NDwAjAwAEAAkKmR1NDwAjAwARAAgKHBkFGABPAgAAAA==.Autýmn:BAAANQADCgcIDAABNQAECgYIDQADAAAAAA==.',
Av='Avadin:BAABNQAFFIEGAAMSAAQKwhCrBwAlAQASAAQKfQ2rBwAlAQATAAIK3AyRDwCHAAABNQAECgcIEwADAAAAAA==.Avadinde:BAAANQAECgcIEwAAAA==.Avadingue:BAAANQADCgYIBgABNQAECgcIEwADAAAAAA==.Avadragon:BAAANQAECgEIAgABNQAECgcIEwADAAAAAA==.Avarogue:BAAANQAECgIIAgABNQAECgcIEwADAAAAAA==.Aversa:BAAANQADCgEIAQABNQAECgcIEAADAAAAAA==.Avvallae:BAAANQAECgQICAABNQAECgkJHAAFACUdAA==.',
Ay='Aylla:BAAANQAECgQICQAAAA==.Ayrios:BAAANQADCgEIAQABNQAECgYIEAADAAAAAA==.Ayrious:BAABNQAECoEfAAIUAAgKNhHeFQARAgAUAAgKNhHeFQARAgAAAA==.',
['Aé']='Aéthric:BAAANQADCgUIBQAAAA==.',
Ba='Baalim:BAAANQAECgYJBgAAAA==.Backather:BAAANQADCgcJEwAAAA==.Backshocks:BAAANQADCgQIBAAAAA==.Bagger:BAAANQABCggIFgAAAA==.Bahalanagang:BAAANQADCggIBAAAAA==.Bahrasmyou:BAAANQAECgYIBgAAAA==.Bakkoutou:BAACNQAFFIEIAAIVAAUKLBqmAACeAQAVAAUKLBqmAACeAQA1AAQKgSQAAhUACQrHIoYBAGYDABUACQrHIoYBAGYDAAAA.Baldelomar:BAAANQADCgEIAQAAAA==.Baltic:BAAANQAECgEIAgABNQAECggIIAANAB8jAA==.Bambäm:BAAANQADCgYIBgABNQAECgQIBAADAAAAAA==.Bangers:BAAANQAECgMIBAAAAA==.Basix:BAAANQADCgUJDwAAAA==.Bastock:BAAANQAECgcIDAAAAA==.',
Be='Beanbins:BAAANQAECgEIAQAAAA==.Beannzz:BAAANQAECgIIAgAAAA==.Beanzmachine:BAAANQAECgEIAQAAAA==.Bearstout:BAAANQAECgUIBQAAAA==.Beeans:BAAANQADCgEIAQAAAA==.Beestmaster:BAABNQAECoEfAAIGAAgKcx91IgDVAgAGAAgKcx91IgDVAgAAAA==.Belavik:BAABNQAECoEoAAISAAkK7x2LEwDoAgASAAkK7x2LEwDoAgAAAA==.Bello:BAAANQADCgEJAQAAAA==.Beornna:BAAANQADCgUICAAAAA==.Beowelf:BAACNQAFFIEHAAIWAAQKshE8BgBiAQAWAAQKshE8BgBiAQA1AAQKgSgAAhYACQrtHYUKABgDABYACQrtHYUKABgDAAAA.Beowulfsson:BAAANQAECgQIBwAAAA==.Bertabeef:BAAANQADCggIHQAAAA==.Betrayar:BAAANQADCgYICQAAAA==.Bezzert:BAAANQADCgYIBgAAAA==.',
Bh='Bheap:BAAANQAFFAEIAQAAAA==.Bheapbheap:BAAANQADCggIFwAAAA==.',
Bi='Bigchungo:BAAANQADCgUICAAAAA==.Bigcook:BAAANQADCgYIBgAAAA==.Bigpaindk:BAAANQAECgUIDAAAAA==.Bigpaindru:BAAANQAECgMIAwAAAA==.Bigpainpal:BAAANQADCgMIAwAAAA==.Bigshloppy:BAAANQAECgQIBwAAAA==.Billysblade:BAABNQAECoEfAAMXAAgKmh8GCgDhAQANAAcKFx3VYgAdAgAXAAUKHiEGCgDhAQAAAA==.Birtbirt:BAAANQABCggICQAAAA==.',
Bk='Bkers:BAAANQADCgYIBgAAAA==.',
Bl='Blebipty:BAABNQAECoEiAAIYAAkKshWCCQCrAgAYAAkKshWCCQCrAgAAAA==.Blessyoho:BAAANQADCgYICwAAAA==.Blitzbuster:BAAANQAECgUIDgAAAA==.Blitzy:BAAANQADCgYIBgABNQAECgUIDgADAAAAAA==.Blladee:BAAANQAECgcIDQAAAA==.Bloodjesser:BAAANQAECgEIAQAAAA==.Bloodrender:BAAANQABCgYICAAAAA==.Bluehorn:BAAANQADCgYIBgAAAA==.Bluekoolaid:BAAANQADCgQIBAAAAA==.Blumpkings:BAAANQADCgQJBwAAAA==.',
Bo='Boingus:BAAANQADCgYIBgAAAA==.Bornshadow:BAAANQADCggIBQAAAA==.',
Br='Brockly:BAABNQAECoEYAAIMAAgKlyTODwAdAwAMAAgKlyTODwAdAwAAAA==.Brolly:BAAANQAECgEIAQAAAA==.Brooski:BAAANQADCgQIBwAAAA==.Brotorious:BAABNQAECoEbAAMZAAgK2BMyLQDgAQAWAAgKERBKJADpAQAZAAcK0BUyLQDgAQAAAA==.',
Bu='Bubllz:BAAANQAECgYIBgAAAA==.Budgetroll:BAAANQADCgQIBAAAAA==.Bulluptuous:BAABNQAECoEhAAINAAgKLhyJQACPAgANAAgKLhyJQACPAgAAAA==.Bun:BAAANQABCgUIBAAAAA==.Burkmon:BAAANQAECgYIDgAAAA==.Burret:BAAANQAECgUIDgAAAA==.Butseven:BAAANQAECgYICQAAAA==.Butterbubble:BAAANQAECgQIDAAAAA==.',
['Bó']='Bótat:BAABNQAECoEfAAIaAAgKfg0zGQCUAQAaAAgKfg0zGQCUAQAAAA==.',
Ca='Cadiron:BAAANQAECgIIAgAAAA==.Caedance:BAAANQADCgYICgABNQAECggIIAAMAFYkAA==.Cahrver:BAAANQADCgcIBwAAAA==.Caldergrim:BAAANQADCgQIBAAAAA==.Calumen:BAAANQAECgYIEQAAAA==.Calypzo:BAAANQAECgQICgAAAA==.Camazótz:BAAANQABCgIJAgAAAA==.Cardiacattck:BAAANQADCgEIAQAAAA==.Carnages:BAAANQADCgQIBAABNQAECgUIDQADAAAAAA==.Carvo:BAAANQADCgEJAQAAAA==.Caserius:BAAANQADCggIDAAAAA==.Casusbelli:BAAANQABCgIIAgAAAA==.Catta:BAAANQADCgMIBAABNQAECgQIBwADAAAAAA==.Catynca:BAAANQAECgUIEgABNQAECggIIAAMAFYkAA==.',
Ce='Celieril:BAAANQAECgQIBwAAAA==.Cerilio:BAAANQAECgcIDQAAAA==.',
Ch='Changqing:BAAANQAECgIIAgABNQAECggIGAAGAGghAA==.Chaparrín:BAAANQAECgQIBAAAAA==.Checoburger:BAAANQAECgQICQAAAA==.Cheiel:BAABNQAECoEWAAISAAkK5hDDNgDsAQASAAkK5hDDNgDsAQAAAA==.Chendruid:BAAANQADCgQIBAAAAA==.Chillheart:BAAANQADCgYIBgAAAA==.Chitoes:BAAANQADCgcIBwAAAA==.Chylan:BAAANQADCgUIBQAAAA==.',
Ci='Cimarex:BAAANQAECgYIBgABNQAECggIGAANAFIZAA==.Cincolobos:BAAANQAECgUICAAAAA==.Cinnaminsaph:BAAANQAECgIIAgAAAA==.',
Cl='Clipp:BAAANQAECgIIAgAAAA==.Cloraform:BAAANQADCgYIEgAAAA==.Clytemnestra:BAAANQADCgQIBAAAAA==.',
Co='Conduit:BAAANQAECgcIDQAAAA==.Conri:BAAANQAECgUIBQAAAA==.Coradk:BAAANQADCggICAABNQAFFAYIEgAHABYSAA==.Cowmooz:BAAANQAECgcIEAAAAA==.',
Cr='Critaurus:BAABNQAECoElAAIHAAkKaRIeYgAbAgAHAAkKaRIeYgAbAgAAAA==.Cronics:BAAANQADCgUJBQABNQAECgQIBAADAAAAAA==.Cronstione:BAABNQAECoEgAAMNAAkKaiOOCQCXAwANAAkKaiOOCQCXAwAXAAEKySAOIQBcAAAAAA==.Crossblessar:BAAANQADCgUIBQAAAA==.Crushinater:BAABNQAECoEdAAQOAAcKEBvYQQBMAgAOAAcKEBvYQQBMAgAbAAIKxhVcSwCHAAAcAAEKYh7eIABIAAABNQAECggIFwAIAA8WAA==.',
Ct='Ctrlaltdel:BAAANQADCggICgAAAA==.',
Cz='Czrp:BAAANQAECgMIBAAAAA==.',
['Cô']='Côrack:BAACNQAFFIESAAIHAAYKFhKAAwDsAQAHAAYKFhKAAwDsAQA1AAQKgScAAgcACQrEIVcdACIDAAcACQrEIVcdACIDAAAA.',
Da='Dad:BAAANQAECgcIBwAAAA==.Daddytank:BAAANQADCgUIBQAAAA==.Daedríc:BAAANQAECgYJDAAAAA==.Daeemon:BAAANQADCgcIBwABNQAECggIHwAUADYRAA==.Dagaa:BAAANQADCgYIEQAAAA==.Dagdeath:BAAANQAECgQICQAAAA==.Dagmarre:BAAANQADCgcIBwAAAA==.Dagothseth:BAAANQAECgEIBQAAAA==.Dagothsett:BAAANQADCgQIBwAAAA==.Daktz:BAAANQADCgYIBgAAAA==.Danelle:BAAANQADCggIEgAAAA==.Dankest:BAAANQAECgMICQAAAA==.Darfòrce:BAAANQAECgIIAwABNQAFFAcIGQAdAK8fAA==.Darison:BAAANQAECgcIEwAAAA==.Darkobey:BAAANQADCgEIAQAAAA==.Darreck:BAACNQAFFIEGAAMdAAQKPBnbDgDrAAAdAAMK3RbbDgDrAAAGAAEKWSCdHwBiAAA1AAQKgRoAAx0ACQrwIcATAJcCAB0ACAqJIcATAJcCAAYABArDImqyADMBAAAA.Darthmommy:BAAANQADCgYICgAAAA==.Darvus:BAAANQADCgEIAQAAAA==.Darwïn:BAAANQAECgEIAQAAAA==.Datonax:BAAANQAECgYIEAAAAA==.Davinity:BAABNQAECoEUAAIEAAYKzwqyewA2AQAEAAYKzwqyewA2AQAAAA==.Dayfire:BAAANQAECgQIBwAAAA==.',
Dd='Ddrizztt:BAAANQAECgYIEwAAAA==.',
De='Deadskill:BAABNQAECoEzAAISAAgKBh41IQB5AgASAAgKBh41IQB5AgAAAA==.Deathburrito:BAAANQADCgIIAgAAAA==.Deathloky:BAAANQAECgIIBQAAAA==.Decca:BAAANQAECgQIDAAAAA==.Deeroy:BAABNQAECoEYAAIGAAgKaCE8IADfAgAGAAgKaCE8IADfAgAAAA==.Dehmonia:BAAANQADCgYIBgABNQAECgcIGQAHAOAeAA==.Dela:BAAANQAECgUIDQAAAA==.Delandèr:BAAANQADCgYICAABNQAECgUIDQADAAAAAA==.Delerino:BAAANQAECgEIAQABNQAECgUIDQADAAAAAA==.Demincy:BAABNQAECoEYAAIOAAgK3hrXOgBlAgAOAAgK3hrXOgBlAgAAAA==.Demonbruff:BAAANQAECgcIEQAAAA==.Demonflex:BAAANQAECgYIEAAAAA==.Deoxys:BAAANQAECgMIAwAAAA==.Deset:BAAANQAECgcIEAAAAA==.Desprainer:BAAANQAECgQJBAAAAA==.Desse:BAAANQADCgUJCQAAAA==.Dew:BAAANQABCgcICwAAAA==.Deydoria:BAAANQADCgIIAgAAAA==.',
Dg='Dgt:BAAANQAECgIIAgAAAA==.',
Dh='Dhalthron:BAAANQADCggIDwAAAA==.',
Di='Dingùs:BAAANQAECggIDAAAAA==.Dirkadeux:BAABNQAECoEcAAIGAAgKgh83IgDWAgAGAAgKgh83IgDWAgAAAA==.Dirtyjay:BAAANQADCgEIAQAAAA==.Dirtyúndys:BAAANQAECgcIEgAAAA==.Discoliquid:BAAANQABCgEIAQAAAA==.Divinatrix:BAAANQADCgYJBwAAAA==.Divinecakes:BAABNQAECoEbAAIIAAgK0RNbQQAfAgAIAAgK0RNbQQAfAgAAAA==.Divineskillz:BAAANQAECgEIAQAAAA==.',
Do='Docmanhattan:BAAANQAECgQICwAAAA==.Doesnttank:BAAANQADCgYIEAAAAA==.Dogmatrix:BAABNQAECoEaAAIBAAkK+BT7MAB0AgABAAkK+BT7MAB0AgAAAA==.Donsapo:BAAANQADCgYIBgABNQAECgMIBAADAAAAAA==.Doomshock:BAAANQADCgEIAQAAAA==.Dotcom:BAAANQAECgEIAQAAAA==.Doughmaker:BAACNQAFFIEJAAIEAAUK6RB5CQCqAQAEAAUK6RB5CQCqAQA1AAQKgSQAAgQACQqrGqAoAIsCAAQACQqrGqAoAIsCAAAA.Douru:BAAANQABCgMIAwAAAA==.',
Dr='Dracpo:BAAANQAECgEIAQAAAA==.Dragonskillz:BAAANQADCgUIBQAAAA==.Draktar:BAAANQAECgIIAwAAAA==.Dreambender:BAAANQADCggICAAAAA==.Dreamdecoom:BAAANQAECgUICgAAAA==.Dreamdekoop:BAACNQAFFIEHAAMPAAQKQw1YFAClAAAPAAMKFAtYFAClAAATAAIKhg0ZEACAAAA1AAQKgRoAAhMACQrDHhEbAGkCABMACQrDHhEbAGkCAAAA.Drededknight:BAAANQADCggICQAAAA==.Dreignos:BAABNQAECoEYAAMeAAgK0hRoBgAQAgAeAAgK0hRoBgAQAgAfAAEK3QHKRQAmAAAAAA==.Drillbit:BAAANQADCgEIAQAAAA==.Drizztski:BAAANQADCgYIDAABNQAECgYIEwADAAAAAA==.Drocalla:BAAANQAECgEIAQAAAA==.Drozghul:BAAANQADCgYIEwAAAA==.',
Du='Durnhelm:BAAANQADCgYIBgABNQAECgkJGgABAPgUAA==.Durto:BAAANQADCggIDAABNQADCgQIBAADAAAAAA==.Dushawee:BAACNQAFFIEFAAMMAAIKdh9uEgC6AAAMAAIKdh9uEgC6AAABAAEKiwIRJgA8AAA1AAQKgTAAAwwACQpWHs0mAI0CAAwACApYHc0mAI0CAAEABQpcGthwAHkBAAAA.',
['Dá']='Dárk:BAAANQADCgUIBQAAAA==.',
['Dä']='Dävös:BAAANQAECgUIDwAAAA==.',
Ea='Earthwitch:BAAANQADCgcIDQABNQAECgkJKQAEANkWAA==.',
Eg='Egg:BAABNQAECoEXAAIRAAkKcxtsDQDnAgARAAkKcxtsDQDnAgABNQAFFAUICwAbAJ4hAA==.',
Ei='Eightysìx:BAAANQADCgEIAQABNQAECgUIBwADAAAAAA==.',
Ek='Ekalbs:BAABNQAECoEbAAIRAAgKVRuHEwCKAgARAAgKVRuHEwCKAgAAAA==.',
El='Eliniia:BAAANQAECgEIAQAAAA==.Ellayri:BAABNQAECoEjAAISAAgKKhOSOQDbAQASAAgKKhOSOQDbAQAAAA==.Elldis:BAABNQAECoEVAAIXAAgK9R12BACfAgAXAAgK9R12BACfAgAAAA==.Elleanor:BAAANQAECgMIBgAAAA==.Elonor:BAAANQADCgUIAwAAAA==.Eltanin:BAAANQAECgQIBAAAAA==.',
En='Endling:BAAANQADCgcIBwAAAA==.Endoblades:BAAANQAECgcICwAAAA==.Endobleeds:BAAANQAECgIIAgABNQAECgcICwADAAAAAA==.Endocrits:BAAANQADCggIDgABNQAECgcICwADAAAAAA==.Endodaddy:BAAANQAECgMIBQABNQAECgcICwADAAAAAA==.Endostars:BAAANQAECgUIDQABNQAECgcICwADAAAAAA==.Energykyouka:BAAANQAECgQJBQABNQAECgQJBQADAAAAAA==.Enferi:BAABNQAECoEZAAIgAAgKHCMoBgAaAwAgAAgKHCMoBgAaAwAAAA==.Enforcers:BAAANQAECgUICQAAAA==.',
Eq='Equinoxdk:BAAANQAFFAIIAgAAAA==.',
Es='Essent:BAAANQAECgUIDQABNQAECggIGgAQAHIZAA==.Esthera:BAAANQADCgYJBgAAAA==.',
Ev='Evochiken:BAECNQAFFIEKAAIfAAUKuQySBwCAAQAfAAUKuQySBwCAAQA1AAQKgSwABB8ACQovHAIGADADAB8ACQovHAIGADADACEABApzC3clAMYAAB4AAQonCrIbADgAAAAA.Evokemode:BAABNQAECoEdAAIfAAgKjCWSBABSAwAfAAgKjCWSBABSAwAAAA==.',
Ex='Exorcism:BAAANQAECgYIDQAAAA==.Exotic:BAAANQAECggIEAAAAA==.Explosivoh:BAAANQAECgMIBQAAAA==.Exumm:BAAANQAECgYIEwAAAA==.',
Ey='Eyeforagge:BAAANQADCgMIAwAAAA==.',
Fa='Fakelashes:BAAANQABCgQIBQAAAA==.Fanatheodord:BAAANQADCgcIBwAAAA==.Farstriderr:BAAANQADCggIMAAAAA==.Fataleclipse:BAAANQAECgUIDQAAAA==.Fatmir:BAAANQAECgMIBAAAAA==.',
Fe='Feigndps:BAAANQAECgQIBAAAAA==.Feldrak:BAABNQAECoEfAAMfAAkK3w9kFgAcAgAfAAkK3w9kFgAcAgAhAAIKAwRpLwBRAAAAAA==.Feldriu:BAAANQADCgcJDQAAAA==.Felzel:BAAANQAECgcIEAAAAA==.Ferrovax:BAAANQAECgQIBAAAAA==.',
Fi='Figai:BAAANQAECgcIEwAAAA==.Finebyme:BAAANQAECgEIAQAAAA==.Firebear:BAAANQAECgYIDAAAAA==.',
Fl='Flanknspank:BAACNQAFFIERAAIgAAYKQhjOAQDXAQAgAAYKQhjOAQDXAQA1AAQKgSoAAyAACQoxI3EDAGcDACAACQoxI3EDAGcDAAcAAgq+DoAaAXcAAAAA.',
Fo='Formulated:BAAANQABCgQIBAAAAA==.Fotmreroller:BAAANQAECgYIDwAAAA==.Fourtwenty:BAABNQAECoEcAAMiAAgK4xf6GgAQAgAiAAcKQBn6GgAQAgAQAAYKUwz8FgAlAQAAAA==.Foxyladeh:BAAANQADCgMIAwAAAA==.Foxylady:BAAANQADCgIIAgAAAA==.',
Fr='Frazledazzle:BAAANQADCgYIBgAAAA==.Frostytongue:BAAANQADCgUIBgAAAA==.Fruitbasket:BAAANQAECgYIBgAAAA==.Frôstíe:BAAANQAECgQICAAAAA==.',
Ga='Galadriella:BAAANQAECgYIDQAAAA==.Garglius:BAAANQAECggIAwAAAA==.',
Ge='Gekidos:BAAANQAECgEIAQAAAA==.Gekiretsu:BAAANQAECgEIAQAAAA==.Geodon:BAAANQAECgEJAQAAAA==.Geoffry:BAABNQAECoEZAAISAAgKQh6xHwCEAgASAAgKQh6xHwCEAgAAAA==.Gerbil:BAABNQAECoEdAAMNAAgKLhe5YQAgAgANAAgKLhe5YQAgAgAXAAEKBhYgIwBMAAAAAA==.',
Gh='Ghidora:BAAANQADCgEIAQAAAA==.Ghostmonkey:BAAANQADCgEIAQAAAA==.',
Gi='Giaoman:BAABNQAECoEWAAINAAkKpR8DJgD6AgANAAkKpR8DJgD6AgAAAA==.Gilgalock:BAAANQADCgMIBAABNQAECgkJIgANAOAeAA==.Gilwood:BAACNQAFFIEJAAIdAAUK8BL3BwB/AQAdAAUK8BL3BwB/AQA1AAQKgSQAAx0ACQp2HZ8cADUCAB0ACArvG58cADUCAAYABAo+HcCvADkBAAAA.Gingyr:BAAANQAECgYIDQAAAA==.Girthywand:BAAANQAECgQIDQABNQAECgcIFQACAPQTAA==.',
Gl='Glacialgimp:BAAANQAECgQIBwAAAA==.Gloinn:BAABNQAECoEkAAMJAAkKwB+QRADZAgAJAAkKwB+QRADZAgAKAAEKOCDhMwBCAAAAAA==.',
Gn='Gnomelyfans:BAABNQAECoElAAIRAAgKeBnlFwBQAgARAAgKeBnlFwBQAgAAAA==.Gnomorerage:BAAANQAECgIIAgABNQAECggIJQARAHgZAA==.',
Go='Golfire:BAACNQAFFIELAAMZAAUKNhQcBgCNAQAZAAUKnBAcBgCNAQAWAAMKrg02CQDnAAA1AAQKgS8AAxYACQphI8MLAAYDABYACQoJH8MLAAYDABkABgpFIXAkACoCAAAA.Gooberlol:BAAANQAECggIEQABNQAECggIFQAOANkcAA==.Gorbashe:BAAANQADCgEJAQABNQAECgkJJQAHAGkSAA==.Gorbie:BAACNQAFFIEIAAIWAAQKuQ4JBwA9AQAWAAQKuQ4JBwA9AQA1AAQKgSgAAhYACQptGWYUAJYCABYACQptGWYUAJYCAAE1AAQKBggNAAMAAAAA.Gorestus:BAABNQAECoEVAAIUAAcKlhU/GAD3AQAUAAcKlhU/GAD3AQAAAA==.Gorlockholms:BAABNQAECoEbAAIOAAkKFRQTNgB3AgAOAAkKFRQTNgB3AgAAAA==.Gorthex:BAAANQAECgcIDQAAAA==.Gozziz:BAAANQAECgUICgAAAA==.',
Gr='Graitlok:BAABNQAECoEdAAINAAcKkRz3XwAmAgANAAcKkRz3XwAmAgAAAA==.Grawd:BAAANQAECgYIEgAAAA==.Graysòn:BAAANQAECgMIAwAAAA==.Grilledchis:BAAANQAECgcIDQAAAA==.Grimdwagon:BAAANQAECgQICQAAAA==.Griseldas:BAAANQAECgQIBwABNQAECggIFwAIAA8WAA==.Griswald:BAAANQAECgYIDgAAAA==.Grotgrot:BAAANQAECgEIAQAAAA==.Grumpygranpa:BAABNQAECoEYAAMcAAQKgCJYCQCcAQAcAAQKgCJYCQCcAQAOAAEK7gclBgE2AAAAAA==.Grypser:BAAANQAECgEIAQAAAA==.',
Gu='Guesswholoky:BAAANQAECgEIAQAAAA==.Guldán:BAAANQADCggIDQAAAA==.Gulmatt:BAABNQAECoEmAAIbAAgKkSJsAgAmAwAbAAgKkSJsAgAmAwAAAA==.Gunslug:BAAANQAECgYIBgAAAA==.',
['Gí']='Gílgamore:BAABNQAECoEiAAMNAAkK4B5UNwCxAgANAAkKEhxUNwCxAgAXAAIK2yRlFwDVAAAAAA==.',
Ha='Haguda:BAAANQAECgEIAQAAAA==.Hakaska:BAABNQAECoEfAAIQAAgKPBLhDQDTAQAQAAgKPBLhDQDTAQAAAA==.Hakkinen:BAAANQAECgcICQAAAA==.Hakâi:BAAANQADCgYIBgAAAA==.Hankock:BAAANQADCggICAABNQAECggIDwADAAAAAA==.Hanswolo:BAAANQAECgUICAAAAA==.Haramboned:BAAANQADCggIDgAAAA==.Harharof:BAAANQADCgIIAgAAAA==.Haron:BAAANQAECggICAAAAA==.Hatebreeder:BAAANQAECgIIAgABNQAECgQIAgADAAAAAA==.Hatise:BAAANQADCgQIBAAAAA==.Hawktuàh:BAAANQADCgUIBgAAAA==.',
He='Heirofdeath:BAAANQABCgYICQAAAA==.Heliotoro:BAAANQADCgUICgAAAA==.Hellebore:BAAANQADCgcIDgAAAA==.',
Hi='Hierba:BAAANQAECgcIDgAAAA==.Highlock:BAAANQAECggIDwAAAA==.Hilde:BAAANQADCgUIDAAAAA==.',
Ho='Holigoat:BAAANQAECgIJAgAAAA==.Holycowbaby:BAAANQAECgEIAQABNQAECgQICwADAAAAAA==.Holysam:BAAANQADCgUIBQAAAA==.Holyshhmon:BAAANQAECgEIAQABNQAECgQIBAADAAAAAA==.Holystriker:BAAANQADCggICQAAAA==.Holywitch:BAABNQAECoEpAAMEAAkK2RbsLgBsAgAEAAkK2RbsLgBsAgARAAEKcADydgALAAAAAA==.Honnycorns:BAAANQAECgYICQAAAA==.Hoojah:BAAANQADCggIDQAAAA==.Hordack:BAAANQADCgQIBAAAAA==.Hormandacek:BAAANQAECgUJBQAAAA==.Hornguy:BAAANQAECgYIEAAAAA==.Hornstar:BAAANQAECgUICAAAAA==.Houndoom:BAABNQAECoEgAAMOAAkKdiLTFQAGAwAOAAgKtSLTFQAGAwAbAAIKDxTwSgCIAAAAAA==.',
Hr='Hrulot:BAAANQADCgYIBgAAAA==.',
Hs='Hsr:BAABNQAECoEfAAIHAAgKQCBSKADsAgAHAAgKQCBSKADsAgAAAA==.',
Hu='Huataurga:BAABNQAECoEcAAMGAAgKvxNOUgAqAgAGAAgKvxNOUgAqAgAdAAEKlwF0egAdAAAAAA==.Huff:BAABNQAECoEbAAIdAAkKZx5DDQDnAgAdAAkKZx5DDQDnAgABNQAFFAIICAAMADMmAA==.Hugetoke:BAAANQAECgIIAgAAAA==.Huktwo:BAAANQAECgUIDQAAAA==.Hunternin:BAAANQAECgIIAwABNQAECgIJBAADAAAAAA==.Huron:BAAANQAECgQICAAAAA==.Huskarl:BAAANQAECgIIAgAAAA==.Hussypriest:BAAANQAECgcIEgAAAA==.',
Hy='Hyzerflip:BAAANQAECgMIBAAAAA==.',
['Hà']='Hàchi:BAACNQAFFIEQAAICAAYKAiE2AgB0AgACAAYKAiE2AgB0AgA1AAQKgSoAAgIACQo8JqoBANoDAAIACQo8JqoBANoDAAAA.',
['Hä']='Hännibal:BAAANQADCgIIAgAAAA==.',
Ib='Ibsgodx:BAAANQADCgQIBAAAAA==.',
Id='Idiotfurry:BAABNQAECoEfAAISAAgKFSACGgCwAgASAAgKFSACGgCwAgAAAA==.',
Ig='Igotatiara:BAAANQADCgYIBgAAAA==.',
Il='Iliad:BAAANQADCggIEAAAAA==.Illidanheart:BAAANQABCgQIBgAAAA==.Illumináti:BAAANQADCgYIBgAAAA==.Ilmagnifico:BAABNQAECoEaAAIiAAkK3wrMIgCzAQAiAAkK3wrMIgCzAQAAAA==.',
Im='Imolegreg:BAABNQAECoEaAAIPAAkK/hoiGAC8AgAPAAkK/hoiGAC8AgAAAA==.Imperatris:BAAANQAECgEIAQAAAA==.Imvaernarhro:BAAANQADCgMIAwAAAA==.',
In='Inkubator:BAAANQAFFAIIBQAAAQ==.Inkyy:BAAANQADCgYIBgAAAA==.',
Ir='Irøns:BAAANQADCggIEAAAAA==.',
It='Itemlevel:BAAANQADCgUIBgAAAA==.',
Iy='Iyamwarlock:BAAANQADCgYIBgAAAA==.Iyanden:BAAANQAECgQICQAAAA==.',
Ja='Jabrogoz:BAAANQADCgMIAQAAAA==.Jahaerys:BAAANQADCgEJAQAAAA==.Jalahl:BAAANQADCgcIBwABNQAFFAYIEAAeAHYdAA==.Jastinos:BAAANQAECgQIBAAAAA==.',
Je='Jentrazka:BAAANQADCgIIAgABNQAECgUIDgADAAAAAA==.Jezahbel:BAAANQAECgQICgAAAA==.',
Ji='Jitteryjoe:BAABNQAECoEVAAIBAAcKtAuBbQCDAQABAAcKtAuBbQCDAQAAAA==.',
Jo='Joseko:BAABNQAECoEdAAICAAkK1BgmHwCfAgACAAkK1BgmHwCfAgAAAA==.',
Ju='Juggsr:BAABNQAECoEaAAIJAAcKbRv/gQA/AgAJAAcKbRv/gQA/AgAAAA==.Justbower:BAAANQAECgUIBQAAAA==.',
Ka='Kaeyle:BAAANQADCgcIDgABNQAFFAYIDQAYAN0RAA==.Kamico:BAAANQADCgUICQAAAA==.Kansoika:BAAANQADCgcIBwAAAA==.Kaptainpiss:BAAANQAECgQIBAAAAA==.Karakitana:BAAANQADCgYIBQABNQAECgkJHAAFACUdAA==.Kasualtrash:BAAANQAECgYIBgAAAA==.Katfury:BAABNQAECoEaAAIBAAgKSwpoXgC0AQABAAgKSwpoXgC0AQAAAA==.Kattallina:BAAANQADCgcJBwAAAA==.Kattmini:BAACNQAFFIEOAAMOAAYKzRIjBwCYAQAOAAUKxxMjBwCYAQAbAAIKwQqaDACeAAA1AAQKgSwAAw4ACQroIiIVAAoDAA4ACArvIiIVAAoDABsABwpLF9kOAPsBAAAA.Katto:BAAANQAECgQIBwAAAA==.',
Ke='Keffká:BAAANQADCggIEgAAAA==.Kelebrimbor:BAAANQAECgEIAQAAAA==.Kennycrvkok:BAAANQAECgEIAQAAAA==.Keyalidas:BAAANQADCgEIAQAAAA==.Keylime:BAAANQAECgQIBAAAAA==.',
Kh='Khane:BAAANQAECgIIAgAAAA==.Kharras:BAAANQADCggICgAAAA==.Khyran:BAAANQAECgMIAwABNQAECgQIBgADAAAAAA==.',
Ki='Killabattle:BAAANQADCgcIBwAAAA==.Kilyna:BAABNQAECoEeAAIOAAgKWBa0OQBpAgAOAAgKWBa0OQBpAgAAAA==.Kirbÿ:BAAANQAECgcIEgAAAA==.Kisha:BAAANQADCgYIBgAAAA==.',
Ko='Kodeezy:BAAANQADCggICAABNQAFFAUICAAHANwNAA==.Kodita:BAACNQAFFIEIAAIHAAUK3A37BgCEAQAHAAUK3A37BgCEAQA1AAQKgScAAgcACQqjH/0gAA8DAAcACQqjH/0gAA8DAAAA.Koldcuz:BAAANQADCgcIBwAAAA==.',
Kr='Krakair:BAAANQAECgUICgAAAA==.Krhon:BAAANQAECgQJBgAAAA==.Kryptic:BAAANQAECgcIEQAAAA==.',
Ky='Kylea:BAAANQAECgUICQAAAA==.Kyntaro:BAAANQADCgcICQAAAA==.Kyouka:BAAANQAECgQICAABNQAECgkJIQAOAGsgAA==.Kysira:BAABNQAECoEUAAIMAAYKHwTKmgDsAAAMAAYKHwTKmgDsAAAAAA==.',
La='Lailai:BAAANQAECgYIDwABNQAECggIDAADAAAAAA==.Lalax:BAAANQABCgQIBAAAAA==.Lalechuga:BAABNQAECoEXAAIJAAgKOB+WRwDQAgAJAAgKOB+WRwDQAgAAAA==.Lanerian:BAAANQAECgUIBQAAAA==.',
Ld='Ldytncty:BAAANQADCgUJBQAAAA==.',
Le='Leadah:BAAANQADCgUIBQAAAA==.Ledge:BAAANQAECgEIAQABNQAECgQIAgADAAAAAA==.Ledgebear:BAAANQAECgQIAgAAAA==.Leerwandler:BAAANQAECgQICAAAAA==.Lehunt:BAABNQAECoElAAIdAAkKOBubDwDIAgAdAAkKOBubDwDIAgAAAA==.Leiyong:BAAANQAECgEIAQAAAA==.Lerkenstein:BAAANQAECgUIBQAAAA==.Letmedoitpls:BAAANQABCgMIBQAAAA==.Levant:BAAANQADCgMIAwAAAA==.Levigosa:BAAANQADCgYIDAAAAA==.Lexadin:BAAANQABCgIIAgAAAA==.Leylanie:BAAANQAECggIBgAAAA==.',
Li='Liadarel:BAAANQADCgMIAwAAAA==.Liael:BAAANQADCgQIBAAAAA==.Lightlobster:BAAANQAECgQICAABNQAECgkJKQAYANwfAA==.Lightwalker:BAAANQAECgEIAQABNQAECgQIBgADAAAAAA==.Lilpuffz:BAAANQAECgYIEgAAAA==.Lisaleri:BAAANQADCgYIBwAAAA==.Litehouse:BAAANQADCgYIBgABNQAECgEJAQADAAAAAA==.Liteorheavy:BAAANQADCgIIAgAAAA==.Livewires:BAAANQADCgcICQABNQAECgcIEwADAAAAAA==.',
Ll='Llandshark:BAAANQAECgcIDwAAAA==.Lleyla:BAABNQAECoEgAAMMAAgKViQoDAA9AwAMAAgKViQoDAA9AwABAAIKoQma3ABnAAAAAA==.',
Lo='Loavoltage:BAAANQADCgUIBQAAAA==.Lockjaw:BAAANQAECgIIAwABNQAECgMIBAADAAAAAA==.Lockyboi:BAAANQAECgQIBAABNQAECgcIEAADAAAAAA==.Locomoko:BAAANQADCggJCAAAAA==.Lohre:BAAANQADCgIIAgAAAA==.Lojik:BAAANQADCggIBQAAAA==.Long:BAAANQAECgQIDwAAAA==.Lonoh:BAAANQAECgQIBQABNQAECgQIBgADAAAAAA==.Lookimapanda:BAAANQAECgQICAAAAA==.Lorakmahktar:BAAANQAECgYIEAAAAA==.Lottie:BAAANQAECgYIEAAAAA==.',
Lu='Luarhea:BAAANQAECgYIEAAAAA==.Luccina:BAAANQAECgcIEAAAAA==.Lucîd:BAAANQAECgUIDwABNQAECgcIEAADAAAAAA==.Luminarie:BAACNQAFFIEJAAIIAAUKKhkRBgC3AQAIAAUKKhkRBgC3AQA1AAQKgSQAAggACQrTIpkGAH8DAAgACQrTIpkGAH8DAAAA.Lunitari:BAABNQAECoEjAAIJAAkKsCQ4CgCjAwAJAAkKsCQ4CgCjAwAAAA==.Luvalot:BAAANQAECgMIBAAAAA==.',
Lx='Lxbeowulfxl:BAAANQADCgcJCgAAAA==.',
Ly='Lyraiel:BAABNQAECoEbAAMJAAgKdAXn9gBLAQAJAAgKdAXn9gBLAQAjAAMKOwG7BwBgAAAAAA==.Lysaera:BAAANQAECgQIBAAAAA==.',
['Lü']='Lücíd:BAAANQADCggICAABNQAECgcIEAADAAAAAA==.',
Ma='Mackantosh:BAAANQAECgYIDQAAAA==.Mackpyre:BAAANQAECgQIBgABNQAECgYIDQADAAAAAA==.Macuahùitl:BAAANQAECgEIAQAAAA==.Madness:BAAANQABCggICQAAAA==.Magelha:BAAANQADCgYIBgAAAA==.Magmalash:BAAANQADCgEIAQAAAA==.Mago:BAAANQADCgUIBQABNQAECgkJKAAZAH8kAA==.Magoroxx:BAAANQAECgcIEgAAAA==.Mahots:BAAANQAECgUIBQAAAA==.Maiyathicc:BAAANQAECgQICQAAAA==.Makagalvan:BAACNQAFFIEJAAINAAUKUAlADgBhAQANAAUKUAlADgBhAQA1AAQKgSQAAg0ACQqJGERLAGoCAA0ACQqJGERLAGoCAAAA.Malakes:BAABNQAECoEVAAIOAAgK2RwHIwDEAgAOAAgK2RwHIwDEAgAAAA==.Malthael:BAABNQAECoEYAAINAAkK7iNUHgAdAwANAAkK7iNUHgAdAwABNQAFFAUIDAAHAAolAA==.Malzahar:BAAANQADCgcIBwAAAA==.Mambas:BAAANQADCgMIAwAAAA==.Manamgmtllc:BAAANQADCgYIBgAAAA==.Mantu:BAAANQAECggICAAAAA==.Maplepriest:BAAANQADCgYIBgAAAA==.Markyle:BAEANQADCgYIBgABNQAECgUICwADAAAAAA==.Martien:BAAANQAECgcIDwAAAA==.Massteraria:BAAANQADCggIDwAAAA==.Masstercard:BAABNQAECoEfAAIiAAkKFh9rCQASAwAiAAkKFh9rCQASAwAAAA==.Maxeras:BAAANQAECgMIBgAAAA==.Maximus:BAAANQAECgUJDwAAAA==.Maya:BAABNQAFFIENAAIJAAYK/hivBQAnAgAJAAYK/hivBQAnAgAAAA==.Mayoi:BAAANQADCgYIDAAAAA==.Mazo:BAABNQAECoEoAAMZAAkKfyRCBQCHAwAZAAkKRCRCBQCHAwAWAAQKPBsFNwBBAQAAAA==.',
Mb='Mbuku:BAAANQAECgYIBgAAAA==.',
Mc='Mcroguez:BAACNQAFFIEHAAIUAAYKZRW0AQAqAgAUAAYKZRW0AQAqAgA1AAQKgSAAAxQACApXHtwNAHwCABQABwqOINwNAHwCAAUABAoIErBJAAkBAAAA.',
Me='Meeche:BAAANQAECgQIBQAAAA==.Melfpally:BAAANQAECgYICAAAAA==.Menagerie:BAABNQAECoEhAAMOAAkKayDtDQA5AwAOAAkKayDtDQA5AwAbAAEKCBGMaAA8AAAAAA==.Metche:BAAANQAECgYIDgAAAA==.Mezzy:BAAANQADCggIEAAAAA==.',
Mi='Midhealz:BAAANQADCgYIBgAAAA==.Mightythighs:BAAANQAECgYIEgAAAA==.Mihd:BAAANQAECgYIEAAAAA==.Miisch:BAAANQAECgQICQAAAA==.Milkyy:BAAANQAECgYJDgAAAA==.Millamaxwell:BAAANQADCgcICwABNQAFFAUICQAhAL0OAA==.Minimus:BAABNQAECoEbAAIMAAcKYiVVFgDvAgAMAAcKYiVVFgDvAgAAAA==.Miraeth:BAAANQAECgQIBgAAAA==.Misknocker:BAAANQAECgYIDAAAAA==.',
Mo='Moistivall:BAAANQAECgEIAQAAAA==.Moisturize:BAAANQABCgUIBAAAAA==.Momô:BAAANQAECgQIAwABNQAECgMJBwADAAAAAA==.Monkred:BAAANQAECgcIEwAAAA==.Monte:BAAANQAECgUIBQAAAA==.Moobees:BAAANQAECgQICQAAAA==.Moogasmic:BAAANQADCgIIAgAAAA==.Mooge:BAEANQADCgYICwABNQAECgUICwADAAAAAA==.Mooiester:BAAANQAECgYIBgAAAA==.Moomage:BAAANQAECgYIBgAAAA==.Moomanchuu:BAAANQADCgMIAwAAAA==.Moomins:BAAANQAECgUICAABNQAECgkJIwAJALAkAA==.Mootche:BAAANQAECgQIBAAAAA==.Mortuous:BAAANQAECgIIBgAAAA==.Mosthated:BAAANQAECgIIAgAAAA==.',
Ms='Mstrfreekill:BAABNQAECoEaAAMkAAgKASDmBADpAgAkAAgKyx/mBADpAgALAAMKERreJADjAAAAAA==.',
Mu='Mubu:BAAANQAECgQIBQAAAA==.Mudpriest:BAABNQAECoEfAAIEAAgKmSMmFAAAAwAEAAgKmSMmFAAAAwAAAA==.Muffdiiva:BAAANQAECgYIEAAAAA==.Muffinmán:BAAANQAECgEJAQAAAA==.Mulletman:BAABNQAECoEcAAIOAAgKJBjUQwBGAgAOAAgKJBjUQwBGAgAAAA==.Murphlord:BAAANQAECgUJBQAAAA==.Musky:BAABNQAECoEkAAINAAgK0x6mMADMAgANAAgK0x6mMADMAgAAAA==.Muskydk:BAAANQADCgYJBgABNQAECggIJAANANMeAA==.Muskydruid:BAABNQAECoEVAAIkAAgKFx+EBAD4AgAkAAgKFx+EBAD4AgABNQAECggIJAANANMeAA==.Muskyshnoze:BAAANQADCgQJBQABNQAECggIJAANANMeAA==.',
My='Mystogån:BAAANQADCggIDwAAAA==.Mystrix:BAABNQAECoEWAAIMAAgKzRt0MABdAgAMAAgKzRt0MABdAgAAAA==.Mytthdk:BAAANQAECgEIAQAAAA==.Myzary:BAAANQAECgIIAgAAAA==.',
['Mè']='Mèggz:BAAANQADCgIIAwAAAA==.',
['Më']='Mërcy:BAAANQAECgUICwAAAA==.',
['Mí']='Míghty:BAAANQABCgIIAgAAAA==.Míthrandír:BAABNQAECoE1AAIJAAkKriDSHwBGAwAJAAkKriDSHwBGAwAAAA==.',
['Mô']='Mômo:BAAANQAECgMJBwAAAA==.',
['Mû']='Mûfâsâ:BAAANQADCggJDgAAAA==.',
Na='Nardhaa:BAAANQAECgcIFQAAAQ==.Narkiel:BAAANQADCgEJAQAAAA==.Narrius:BAABNQAECoEZAAMYAAgKnByaDgBAAgAYAAcKYRmaDgBAAgABAAYKxhqNXAC6AQAAAA==.Nathzandalar:BAAANQAECgMIAwAAAA==.Natraps:BAAANQAECgUICgAAAA==.',
Ne='Neartonoir:BAAANQABCgcJDAAAAA==.Nesmage:BAAANQAECgQIBgAAAA==.Nesmie:BAABNQAECoEXAAIYAAYK+BpAEQAJAgAYAAYK+BpAEQAJAgAAAA==.',
Ni='Nijek:BAAANQAECgcIEQAAAA==.Nimchip:BAACNQAFFIEMAAMNAAUKKRO8CwCOAQANAAUKKRO8CwCOAQAlAAEKFgM5BwAwAAA1AAQKgT4AAg0ACQqQIdchAA0DAA0ACQqQIdchAA0DAAAA.',
Nl='Nlrvana:BAAANQADCgEJAQAAAA==.',
No='Nokkakkash:BAAANQADCggICAAAAA==.Notheysus:BAAANQADCgcIBwAAAA==.Notmyforte:BAAANQAECgYIEAAAAA==.',
Nu='Nudillos:BAAANQADCgcIBwAAAA==.Nudnarb:BAAANQADCgQIBAAAAA==.Nurflocks:BAAANQADCgYIBgAAAA==.',
Ny='Nyankobrq:BAAANQAECgQJBQAAAA==.Nyxtheabyss:BAAANQADCgQIBAAAAA==.',
['Ná']='Náthe:BAAANQAECgQIBwAAAA==.',
Oa='Oakzz:BAEANQAECgYIBgABNQAECgkJIQAhAKIbAA==.',
Ob='Obalnhabdea:BAAANQAECgMIAwAAAA==.Oblvn:BAAANQAECgQIBAAAAA==.',
Od='Odhran:BAAANQAECgcICgAAAA==.',
Oh='Ohda:BAAANQAECgUIDQAAAA==.Ohgodbees:BAAANQAECgYICgAAAA==.',
Oi='Oisn:BAAANQAECgQIBgABNQAECggIGgAQAHIZAA==.',
Ol='Oldlove:BAAANQAECgEIAQABNQAECggIDwADAAAAAA==.',
On='Onís:BAABNQAECoEaAAIQAAgKchnTCQBAAgAQAAgKchnTCQBAAgAAAA==.',
Op='Opspartan:BAAANQABCgYICwAAAA==.',
Or='Orastal:BAAANQAECgUIBQABNQAECgcICgADAAAAAA==.Oravoker:BAAANQAECgYIEgABNQAECgcICgADAAAAAA==.Orcishz:BAAANQADCgQIBwAAAA==.Oreweyna:BAAANQABCgIIBAAAAA==.Orion:BAAANQADCgcIDAAAAA==.',
Os='Osawa:BAAANQAECgYIBgAAAA==.Osk:BAAANQAECggICAAAAA==.Ostidevache:BAAANQADCgYICQAAAA==.',
Oy='Oyobi:BAAANQADCgEIAQAAAA==.',
Oz='Ozshock:BAAANQAECgYIEgAAAA==.',
Pa='Paffdk:BAAANQAECgUIDQAAAA==.Paiyn:BAAANQADCgcIBwAAAA==.Palamix:BAAANQAECgIJBAAAAA==.Palladone:BAAANQAECgYIEAAAAA==.Palthron:BAAANQAECgYIEwAAAA==.Palychick:BAAANQAECgcIEQAAAA==.Pampersxl:BAABNQAECoEdAAMGAAgKWx5tKAC7AgAGAAgKWx5tKAC7AgAdAAUKag2bPgD1AAAAAA==.Pandatheis:BAAANQADCgUIBQAAAA==.Pandatotem:BAAANQADCgYICgABNQAECggIHAAaAEEOAA==.Pangoro:BAACNQAFFIEQAAIWAAYKcBowAgAsAgAWAAYKcBowAgAsAgA1AAQKgSsAAhYACQqnIygEAIYDABYACQqnIygEAIYDAAAA.Paragondk:BAABNQAECoEXAAMTAAkKCh7oDAD8AgATAAkKCh7oDAD8AgASAAEKqgYougAoAAAAAA==.Paragonlock:BAAANQAECgYIEQABNQAECgkJFwATAAoeAA==.Paramedic:BAABNQAFFIEMAAIHAAUKCiUFAgAqAgAHAAUKCiUFAgAqAgAAAA==.Parser:BAAANQADCgMIAwAAAA==.',
Pe='Pelikanesis:BAAANQAECgUICAAAAA==.Pelolindo:BAAANQADCggICAAAAA==.Penance:BAAANQAECgMIBAAAAA==.Pestus:BAAANQAECgMIAwAAAA==.Peteqc:BAAANQADCgUIBQAAAA==.Petshunt:BAAANQAECggICgABNQADCggICQADAAAAAA==.',
Ph='Phageborn:BAACNQAFFIEKAAIPAAUKDx+fBQDJAQAPAAUKDx+fBQDJAQA1AAQKgSIAAg8ACAoeJDMQAAYDAA8ACAoeJDMQAAYDAAAA.Phiavel:BAAANQADCgYIFQAAAA==.Philmahuders:BAAANQADCgIIAgAAAA==.Phoop:BAAANQAECgEIAQAAAA==.',
Pi='Pik:BAAANQAECgYIEgAAAA==.Pillowpants:BAAANQAECgUIBwAAAA==.Pineappleish:BAAANQAECggIEgAAAA==.Pinkcross:BAAANQAECgYICQABNQAFFAcIAQADAAAAAA==.Pinkfuzi:BAAANQAECgQIBwAAAA==.',
Po='Pocketlockit:BAAANQAECgYJCwABNQAECgkJGgAPAP4aAA==.Poisonousx:BAAANQAECgEIAgAAAA==.Poka:BAAANQAECgUIDQAAAA==.Poluna:BAAANQAECgUIDQAAAA==.Polynium:BAAANQADCgcIBwAAAA==.Pookei:BAAANQADCggIDwAAAA==.Poprocket:BAAANQADCggIEgABNQAECggIGAAFAE4hAA==.Popsiclegirl:BAAANQADCgUIBwAAAA==.Porkkchopp:BAABNQAECoEdAAIMAAgKYhxyJwCKAgAMAAgKYhxyJwCKAgAAAA==.',
Pr='Prayermonger:BAAANQAFFAUIBwAAAQ==.Prialise:BAAANQAECgMJAwAAAA==.Priesticle:BAAANQAECgQICAABNQAFFAEIAQADAAAAAA==.Promptoa:BAAANQAECgYIBgAAAA==.Protendo:BAAANQADCggIEAAAAA==.Provider:BAAANQAECgUIBwAAAA==.',
Ps='Psyke:BAAANQADCgUIBQAAAA==.',
Pu='Pufftreez:BAABNQAECoEXAAMbAAgKkg32MgDjAAAOAAcKGA86fACSAQAbAAUKOQX2MgDjAAAAAA==.Purplatath:BAAANQADCgYICAAAAA==.Purpledrink:BAABNQAECoEbAAMJAAgK8x5UnQAAAgAJAAYKxB9UnQAAAgAKAAIKgBwIIQCkAAAAAA==.Purplette:BAAANQADCggICwAAAA==.Purplizor:BAAANQAECgMIBAAAAA==.',
Pw='Pwincessmeow:BAAANQADCgYIFwAAAA==.',
Py='Pynki:BAAANQADCggICwAAAA==.Pyroxion:BAAANQAECgUICgAAAA==.Pyrìz:BAABNQAECoEeAAMJAAcK+iT3OQD1AgAJAAcK+iT3OQD1AgAKAAMKRBvfHQC+AAAAAA==.',
Qi='Qiill:BAAANQADCggJEAAAAA==.',
Qu='Quadratic:BAAANQAECgIIAgAAAA==.Quikzmagez:BAAANQADCgYIBgAAAA==.Quikzpriest:BAAANQADCgYJBQAAAA==.',
Qw='Qweefur:BAAANQAECgUIBQAAAA==.',
Ra='Rabidwombat:BAACNQAFFIEIAAIMAAIKMyYrEADeAAAMAAIKMyYrEADeAAA1AAQKgSsAAgwACQrRJM0CAKkDAAwACQrRJM0CAKkDAAAA.Racoto:BAAANQAECgMIBQAAAA==.Ragingwagyu:BAAANQAECgEIAQAAAA==.Ragrega:BAAANQADCgIIAgAAAA==.Rainey:BAAANQADCgIJAgAAAA==.Rainie:BAAANQADCgcICAABNQAECgkJHwAEAPISAA==.Ralokian:BAACNQAFFIEQAAMeAAYKdh0qAQA3AgAeAAYKlhwqAQA3AgAhAAUKbxueAgCyAQA1AAQKgSkAAyEACQorJW4BAKUDACEACQrBJG4BAKUDAB4ACAoIJVoCABcDAAAA.Rangoo:BAAANQADCgUIBQAAAA==.Raphaelle:BAABNQAECoEZAAIUAAcK2AU7JgBnAQAUAAcK2AU7JgBnAQAAAA==.Ravelled:BAAANQAECgUIDgAAAA==.Ravencláw:BAAANQADCgYICwAAAA==.Ravenmane:BAABNQAECoEiAAIHAAgKFR/1MQDDAgAHAAgKFR/1MQDDAgAAAA==.Rawdaug:BAAANQAECgUIBQAAAA==.Razziz:BAAANQAECgUIEAAAAA==.Raín:BAAANQAECgIIAgAAAA==.',
Re='Regolas:BAAANQAECgQIBAAAAA==.Rejuvie:BAAANQAECgcIDwAAAA==.Relazrasum:BAAANQAECgEJAQAAAA==.Relzzad:BAABNQAECoEYAAMFAAgKTiGyCQAPAwAFAAgKTiGyCQAPAwAUAAIKBA8TPQCBAAAAAA==.Renalyne:BAAANQADCgEIAQAAAA==.Rentámonk:BAAANQADCgEIAQAAAA==.Rentápally:BAAANQAECgQICAAAAA==.Retch:BAAANQADCgEJAQAAAA==.Revelätion:BAAANQAECgEIAQAAAA==.Rexxaar:BAAANQAECgUIDQAAAA==.',
Ri='Riata:BAABNQAECoEbAAINAAkK7xD5XwAlAgANAAkK7xD5XwAlAgAAAA==.Ricericebaby:BAAANQAECgYICQAAAA==.Rikaya:BAAANQAECgcIEQAAAA==.Riot:BAAANQADCgUICwABNQAECgYIBgADAAAAAA==.',
Ro='Robertcheeto:BAACNQAFFIEJAAMCAAUKBBrqEADiAAACAAMK+xHqEADiAAAmAAMKQgeuCADVAAA1AAQKgSQAAyYACQrkG6MQAJMCACYACQrkG6MQAJMCAAIAAwpLHcpdAAUBAAAA.Robthegreat:BAAANQADCgMIAwAAAA==.Rogchamita:BAABNQAECoEjAAMMAAkKDRvoGgDSAgAMAAkKDRvoGgDSAgABAAIK1xH80QCAAAAAAA==.Ronalde:BAAANQAECgcIEQAAAA==.Rondall:BAAANQAECgcIEAAAAA==.Rousera:BAABNQAECoEcAAIFAAkKJR1hDADtAgAFAAkKJR1hDADtAgAAAA==.Roxxaan:BAAANQAECgUICQAAAA==.Royvn:BAAANQAECgUJDAAAAA==.',
Ru='Rubicon:BAAANQADCgcICQAAAA==.Ruffels:BAAANQAECgEIAQAAAA==.Rukiakuchki:BAAANQADCgMJAwAAAA==.Runtzz:BAAANQADCgcICwAAAA==.',
Ry='Ryushinizi:BAAANQADCgIIAgABNQAECgUIDQADAAAAAA==.',
Sa='Saberana:BAAANQADCgcJEAAAAA==.Sadllama:BAABNQAECoEdAAIPAAgKDiQVCwA8AwAPAAgKDiQVCwA8AwAAAA==.Saintcow:BAAANQADCgYIBgAAAA==.Saintl:BAACNQAFFIEJAAIdAAUK/g2xCABuAQAdAAUK/g2xCABuAQA1AAQKgSQAAh0ACQq9F1IaAE0CAB0ACQq9F1IaAE0CAAAA.Saloriel:BAAANQADCggJCwAAAA==.Sammwow:BAABNQAECoEaAAMBAAgK+g2UWQDFAQABAAgK+g2UWQDFAQAMAAQK/w6gmwDpAAAAAA==.Sammyl:BAAANQABCggIEAAAAA==.Sanalin:BAAANQADCgIIAgABNQADCgcIBwADAAAAAA==.Sanlerøs:BAAANQAECgYIDgAAAA==.Sarandots:BAAANQADCgEIAQABNQAECgkJHgAmACcLAA==.Saranfarmer:BAABNQAECoEeAAImAAkKJwtiIADNAQAmAAkKJwtiIADNAQAAAA==.Sarantakos:BAAANQADCgYICgABNQAECgkJHgAmACcLAA==.Sarviez:BAAANQADCgcIBwAAAA==.Sass:BAAANQADCggICAABNQAECggIIQACAKsaAA==.',
Sc='Schwetyß:BAAANQADCgYIBgAAAA==.Scolio:BAAANQAECgYIDgAAAA==.Scourgeguy:BAAANQAECggIEAAAAA==.',
Se='Separation:BAAANQADCgUIBgAAAA==.Serpentos:BAAANQADCggICAAAAA==.Severance:BAAANQAECgUICQABNQAECggIFwAJADgfAA==.Severances:BAAANQAECgEIAQAAAA==.Seves:BAAANQADCgcJDAAAAA==.',
Sh='Shaddough:BAAANQABCgIIAgAAAA==.Shadosham:BAAANQAECgYIDQAAAA==.Shadowcakes:BAAANQAECgQICAAAAA==.Shadowsmith:BAABNQAECoEiAAMbAAkKMx45GgCNAQAOAAYKmh5/YwDdAQAbAAYK0hM5GgCNAQAAAA==.Shaggyveins:BAAANQAECgEIAQAAAA==.Shamanella:BAAANQADCggICAAAAA==.Shamooky:BAEANQAECgUICwAAAA==.Shanke:BAAANQAECgYIEAAAAA==.Shaynke:BAAANQAECgUIBwAAAA==.Shieldbane:BAAANQADCggICAAAAA==.Shizzkin:BAAANQADCgcIBwAAAA==.Shmotz:BAAANQABCgIIAgAAAA==.Shockrender:BAAANQAECgQIBgAAAA==.Shocktoke:BAAANQAECgQIBwAAAA==.Shockzone:BAAANQAECgYIDQAAAA==.Shootymcgun:BAAANQAECgUIBgAAAA==.Shots:BAACNQAFFIEIAAINAAUKFwltDgBeAQANAAUKFwltDgBeAQA1AAQKgSQAAg0ACQrlEUZiAB4CAA0ACQrlEUZiAB4CAAAA.Shotsonshots:BAAANQADCggIDQAAAA==.Shoulders:BAAANQAECgYJBgAAAA==.',
Si='Siado:BAAANQAECgEIAgAAAA==.Sidesandwich:BAAANQAECgcIEgAAAA==.Silvanass:BAAANQAECgIIAgAAAA==.Sin:BAAANQAECgIIAgABNQAFFAcIGQAhAO8lAA==.Sinthetic:BAAANQAECgQJCAAAAA==.Siqi:BAAANQADCgEIAQAAAA==.',
Sk='Skills:BAAANQADCggIDAAAAA==.Skillzhunter:BAAANQADCgcIBwAAAA==.Skornn:BAAANQAECgQIBAABNQAECgQIBAADAAAAAA==.Skyfangret:BAAANQADCggIEgAAAA==.Skysweep:BAAANQADCgYIBQABNQAECgcIEAADAAAAAA==.',
Sl='Slag:BAAANQAECgEIAQABNQAECgUIBQADAAAAAA==.Slappypaws:BAAANQADCgYIBgABNQADCgYJBgADAAAAAA==.Slayerlilith:BAAANQADCgIIAgAAAA==.Slickxoxo:BAAANQAECgEIAQAAAA==.Slizaro:BAABNQAECoEfAAIGAAcKPRtoSQBFAgAGAAcKPRtoSQBFAgAAAA==.Sloponmyknob:BAAANQAECgMIAwABNQAECgQIBwADAAAAAA==.',
Sm='Smashendash:BAAANQAECgQIBwAAAA==.Smolslaps:BAAANQAECgYIDAABNQADCgYJBgADAAAAAA==.Smoothiebowl:BAAANQADCgcIBwAAAA==.',
Sn='Snakeyess:BAAANQAECgEIAQAAAA==.Snappypuppy:BAAANQADCgIIAgABNQADCgYJBgADAAAAAA==.',
So='Sockemm:BAAANQAECggIEgAAAA==.Solarmidnite:BAAANQADCgYIBgAAAA==.Solastus:BAAANQADCgEJAQAAAA==.Sollaria:BAAANQABCggICwAAAA==.Somma:BAAANQADCggIDgAAAA==.Sorchanna:BAAANQADCggIFwAAAA==.Soulamander:BAABNQAFFIEUAAIfAAcKRwivAwALAgAfAAcKRwivAwALAgAAAA==.Souza:BAAANQAECgUIDQAAAA==.Soül:BAABNQAECoEeAAMaAAkKChGIEQAVAgAaAAkKChGIEQAVAgAiAAIKJgfmTABSAAAAAA==.',
Sp='Spikeyboy:BAAANQADCgYIBgAAAA==.Spinal:BAABNQAECoEYAAIOAAcKKRXzYgDfAQAOAAcKKRXzYgDfAQAAAA==.Spiritfinger:BAAANQAECgUIDAABNQAECggIGgASAKIhAA==.',
Sq='Sqrood:BAABNQAECoEfAAIJAAgKeRGRmgAGAgAJAAgKeRGRmgAGAgAAAA==.Squâll:BAAANQAECgEIAQAAAA==.',
Sr='Srdlosrayoz:BAAANQAECggIEAAAAA==.',
St='Stativa:BAAANQADCgYIBgAAAA==.Stellaris:BAAANQAECgYIEQAAAA==.Stephenie:BAAANQAECggIEwAAAA==.Stevesmiff:BAAANQAECgIIAgAAAA==.Sting:BAAANQAECgYIEAAAAA==.Stoofy:BAAANQADCgQIBAABNQAFFAYIEQAgAEIYAA==.Stormbreakur:BAAANQADCggIGgAAAA==.Stormsage:BAAANQADCgYIBgAAAA==.Stormskillz:BAAANQADCgYIBgAAAA==.Strapperjack:BAAANQADCgUIBQAAAA==.',
Su='Sugarhammer:BAAANQADCgEIAQAAAA==.Sunarri:BAAANQAECgYICwAAAA==.Sunbourne:BAAANQAECgYIEAAAAA==.Suradin:BAABNQAECoEZAAMgAAgKVw1JKABBAQAHAAgKXwtflgCKAQAgAAcKKwxJKABBAQAAAA==.Surdaddy:BAAANQAECgUIDgAAAA==.Surín:BAAANQADCgcIBwAAAA==.',
Sy='Syrathia:BAAANQAECgMJBgAAAA==.',
['Sî']='Sîcarius:BAAANQADCgcIDgAAAA==.',
['Só']='Sóulglów:BAAANQADCgUIBQAAAA==.',
['Sú']='Súcellus:BAAANQADCgYIBgAAAA==.Súrë:BAACNQAFFIEQAAIfAAYKwRpQAwAdAgAfAAYKwRpQAwAdAgA1AAQKgSwAAh8ACQqIIksEAFkDAB8ACQqIIksEAFkDAAAA.',
Ta='Tahtics:BAABNQAECoEaAAIHAAgKPSS2FwBAAwAHAAgKPSS2FwBAAwAAAA==.Talmahua:BAAANQADCgYIBgAAAA==.Tangolay:BAAANQADCgIIAgABNQAECgYIEAADAAAAAA==.Tatyl:BAABNQAECoEiAAMOAAgKEyFcMQCIAgAOAAcKRCFcMQCIAgAbAAQKZxgxKgAVAQAAAA==.Tazana:BAAANQAECgEIAgAAAA==.',
Te='Tehsirus:BAAANQAECgcIEwAAAA==.Temoro:BAAANQADCgYIBgABNQADCggICAADAAAAAA==.Tempestaurus:BAAANQAFFAEIAgAAAA==.Tenkok:BAAANQAECgYIDQAAAA==.Tewpok:BAABNQAECoEiAAQcAAgK7w9uBwDdAQAcAAcKnQ9uBwDdAQAbAAMK2QmaQwChAAAOAAMKogV/6wB6AAAAAA==.',
Th='Thalisan:BAAANQAECgQICgAAAA==.Thatdruid:BAAANQADCgcICAAAAA==.Thatmage:BAABNQAECoEYAAMEAAgKyBFrSwDwAQAEAAgKyBFrSwDwAQARAAMKdAiuTACDAAAAAA==.Thebeanzz:BAAANQAECgYICwAAAA==.Theirashes:BAAANQADCgMIAwABNQAECgkJIAAkALQjAA==.Themoistest:BAAANQAECgcIEQAAAA==.Theothehero:BAABNQAECoEmAAIOAAkK1B6LFwD8AgAOAAkK1B6LFwD8AgAAAA==.Thewogfather:BAAANQAECgUIDAAAAA==.Thirdhank:BAAANQADCgYIBgAAAA==.Thoar:BAACNQAFFIENAAIYAAYK3RHEAAAPAgAYAAYK3RHEAAAPAgA1AAQKgSoAAhgACQr3IsYCAGcDABgACQr3IsYCAGcDAAAA.Thormoon:BAABNQAECoEaAAImAAgKEyV5BgA1AwAmAAgKEyV5BgA1AwAAAA==.Thraller:BAAANQADCgYIBgABNQAECgcIGQAOAIcZAA==.',
Ti='Tiahdoe:BAAANQADCggIEwAAAA==.Tiariel:BAABNQAFFIEQAAIPAAYKeQ/1BwCMAQAPAAYKeQ/1BwCMAQAAAA==.Tiriq:BAAANQAECgQIBQAAAA==.',
To='Tolnar:BAABNQAECoEgAAMFAAgKKBgvNgCBAQAFAAUKBhkvNgCBAQAUAAUK9hOfJgBjAQAAAA==.Tolnter:BAAANQADCgYIDAAAAA==.Toodle:BAAANQAECggIDwAAAA==.Torgrun:BAAANQAECgYIEgAAAA==.Torniak:BAAANQAECgQIBwAAAA==.Torpor:BAAANQADCggIDQAAAA==.',
Tr='Traplock:BAAANQAECgMIAgABNQAECggIGAAGAGghAA==.Trapple:BAAANQAECgIIAgAAAA==.Trillian:BAAANQADCggICAAAAA==.Trixia:BAABNQAECoEgAAIfAAkKUherDAC0AgAfAAkKUherDAC0AgAAAA==.Troudeseve:BAAANQADCgcIDQAAAA==.',
Tu='Tusenpai:BAAANQAECgMIAgAAAA==.',
Tw='Twiggyy:BAABNQAECoEcAAINAAgKVCNTIQAPAwANAAgKVCNTIQAPAwAAAA==.Twizzlestix:BAAANQADCgMIAwAAAA==.',
Ty='Tyburr:BAAANQAECggIBwAAAA==.',
Tz='Tzye:BAAANQADCgQIBQAAAA==.',
['Tâ']='Tângo:BAAANQAECgYIEAAAAA==.',
Uj='Ujellypalz:BAAANQAECgQIBQAAAA==.Ujio:BAAANQADCgYIBgABNQAECgkJHwAdAKEjAA==.',
Um='Umbráe:BAACNQAFFIEJAAIPAAUK0xQQCQByAQAPAAUK0xQQCQByAQA1AAQKgSQAAg8ACQqhHekYALUCAA8ACQqhHekYALUCAAAA.Umoonar:BAAANQADCgYICwAAAA==.',
Un='Unctekay:BAAANQABCgIJAgAAAA==.',
Ur='Urotherdaddy:BAAANQADCgQIBAABNQAECgEIAQADAAAAAA==.Ursainsanis:BAAANQAECgcIEwAAAA==.Urukhaí:BAAANQAECgEIAQAAAA==.',
Va='Vainless:BAAANQADCgIIAgAAAA==.Vakkar:BAAANQABCggICAAAAA==.Valediction:BAAANQADCggICwAAAA==.Valhalla:BAAANQAECgUIDQAAAA==.Vallynn:BAAANQADCgQIBAAAAA==.Vandle:BAABNQAECoEiAAMUAAkKbhVTGQDrAQAUAAcKuxFTGQDrAQAFAAUK7Bd2NwB5AQAAAA==.Vanoranda:BAAANQADCgIIAgABNQAECgcIEgADAAAAAA==.Variena:BAAANQADCgcIBgAAAA==.Varikk:BAAANQAECgYICwAAAA==.Varknight:BAAANQAECgQIBAABNQAECgYIBwADAAAAAA==.Varmage:BAAANQAECgQIBAABNQAECgYIBwADAAAAAA==.Varmmy:BAAANQAECgYIBwAAAA==.Varrair:BAAANQAECgQIBQABNQAECgYIBwADAAAAAA==.Vashezzo:BAACNQAFFIETAAIMAAcKaRrcAACiAgAMAAcKaRrcAACiAgA1AAQKgSQAAgwACQpKI5sGAHUDAAwACQpKI5sGAHUDAAAA.',
Ve='Velein:BAAANQADCgYJCQAAAA==.Vellyssa:BAABNQAECoEVAAIcAAYKSQ5QCgB/AQAcAAYKSQ5QCgB/AQAAAA==.Verdolaga:BAAANQADCgYIBgAAAA==.Vexys:BAAANQADCgUIBQAAAA==.Veyllor:BAAANQAECgQIBQAAAA==.',
Vi='Villainous:BAABNQAECoEdAAMGAAkKJR/mFgARAwAGAAgKxyHmFgARAwAdAAIKwQmVXABlAAAAAA==.Vindorian:BAAANQADCggICAAAAA==.Vitreshilla:BAAANQAECgQICAABNQAECggIGAAbAPUaAA==.Vixenz:BAAANQAECgcIDQAAAA==.',
Vo='Volteer:BAACNQAFFIEJAAIhAAUKvQ6qAwB8AQAhAAUKvQ6qAwB8AQA1AAQKgSQAAiEACQr5GI4LAH8CACEACQr5GI4LAH8CAAAA.Voxian:BAAANQADCgYICwAAAA==.',
Vr='Vriest:BAAANQAECgUJBQABNQAECgYIBwADAAAAAA==.',
Vy='Vyecodin:BAAANQADCgYIBgAAAA==.Vyr:BAECNQAFFIEOAAIRAAUKGhx2AwDQAQARAAUKGhx2AwDQAQA1AAQKgSgAAhEACQoSI+UEAHIDABEACQoSI+UEAHIDAAAA.',
['Vä']='Väryn:BAABNQAECoEYAAIIAAgKrR5nHADUAgAIAAgKrR5nHADUAgAAAA==.',
Wa='Wannabrownie:BAAANQADCgUIAwAAAA==.Wardrian:BAAANQAECgUICQAAAA==.Warriorzors:BAAANQADCgUIBQAAAA==.Wavyfist:BAAANQADCgQIBAABNQAFFAQIBwAEADoLAA==.Way:BAAANQAECgYIDgAAAA==.Wayshort:BAAANQADCggIFgABNQAECggIGAAFAE4hAA==.Waystrong:BAAANQAECgYICQABNQAECggIGAAFAE4hAA==.',
We='Wellith:BAABNQAECoEhAAMEAAkKbB+KGADlAgAEAAkKbB+KGADlAgAnAAEKnwYeJQAsAAAAAA==.Westìn:BAAANQADCgYIBwAAAA==.',
Wi='Wikdtwstr:BAABNQAECoEZAAMGAAkKVxlILQCmAgAGAAkK1xhILQCmAgAdAAQKJBrLQgDYAAAAAA==.Wildcard:BAAANQAECgQICAAAAA==.Wilder:BAAANQAECgcIEwAAAA==.',
Wo='Wolfir:BAAANQAECgMJAwAAAA==.',
Wt='Wtfchickenz:BAABNQAECoEVAAICAAcK9BNLOwDJAQACAAcK9BNLOwDJAQAAAA==.',
Wu='Wuntch:BAAANQADCgIIAgABNQADCgMIAwADAAAAAA==.',
['Wã']='Wãngs:BAAANQAECgUIEQABNQAECgYIDgADAAAAAA==.',
Xa='Xaev:BAAANQAECgUIDgAAAA==.Xaevis:BAAANQADCgcIBwABNQAECgUIDgADAAAAAA==.Xarathiel:BAAANQAECgQIBAABNQAECggIGAAFAPIRAA==.',
Xc='Xchenn:BAAANQADCgMIAwAAAA==.',
Xe='Xecution:BAABNQAECoEXAAMlAAgKsBCiGABIAQAlAAYKFRKiGABIAQANAAMKGwpu6ACoAAAAAA==.Xenthor:BAAANQADCgYJBgAAAA==.Xeseparg:BAEANQAECggICwABNQAECggIDwADAAAAAA==.Xevorian:BAAANQAECgUIDgAAAA==.',
Xi='Xiexieping:BAABNQAFFIERAAMYAAYKriJIAAB8AgAYAAYKriJIAAB8AgABAAEK9wLLJQA+AAAAAA==.',
Xy='Xyris:BAAANQADCgUIBQABNQAECgUIDgADAAAAAA==.',
Ye='Yedranna:BAAANQAECgEIAQAAAA==.',
Yo='Yoloswagcrew:BAABNQAECoEiAAIHAAgKTRf+VQBBAgAHAAgKTRf+VQBBAgAAAA==.Yooksham:BAAANQAFFAIIAgAAAA==.',
Ys='Yslena:BAAANQAECgEIAQAAAA==.Yssa:BAAANQADCggIGAABNQAECggIGAAFAE4hAA==.',
Yu='Yuebing:BAACNQAFFIEJAAMCAAUKnQUpDABDAQACAAUKQAUpDABDAQALAAEKwgTPBgAzAAA1AAQKgSQAAgIACQosFNwpAEkCAAIACQosFNwpAEkCAAAA.Yumin:BAAANQADCgUIBQAAAA==.Yurmagesty:BAAANQAECgYIDwAAAA==.',
['Yà']='Yàkana:BAAANQAECgMIBAAAAA==.',
Za='Zaddia:BAAANQADCgYIBwABNQAECgYIDgADAAAAAA==.Zaeta:BAAANQAECgYIEAAAAA==.Zaetini:BAAANQAECgQIBQABNQAECgYIEAADAAAAAA==.Zamforia:BAAANQAECgYIEgAAAA==.Zandadead:BAAANQADCgQIBAABNQAECgQICwADAAAAAA==.Zarellia:BAAANQAECgQIBwAAAA==.',
Ze='Zeeleez:BAAANQADCgYIBgAAAA==.Zephyrr:BAAANQADCggIFgABNQAECgUIDgADAAAAAA==.Zerathrot:BAAANQADCgMIAwAAAA==.Zevaran:BAAANQADCgIIAgABNQAFFAYICwAGAEYbAA==.Zexeria:BAABNQAECoEXAAMIAAgKDxYyNABYAgAIAAgKDxYyNABYAgAHAAIKEhfBDQGQAAAAAA==.',
Zi='Zingara:BAAANQADCgEIAQAAAA==.',
Zo='Zootz:BAAANQADCgYICAAAAA==.Zorororonoa:BAAANQAECggICwAAAA==.Zorrghen:BAAANQADCgYIEQABNQAECgYJEgADAAAAAA==.Zounap:BAAANQAECgYIEwAAAA==.Zoyaa:BAAANQAECgYIDgAAAA==.',
Zu='Zultra:BAAANQADCgcICAAAAA==.',
['Zë']='Zëd:BAAANQAECgIIAwAAAA==.',
['Ïs']='Ïshtãr:BAABNQAECoEYAAIWAAgKuBQyHQAxAgAWAAgKuBQyHQAxAgAAAA==.',
['Ða']='Ðash:BAAANQAECgEIAQAAAA==.',
['Üt']='Üthér:BAABNQAECoEYAAIHAAcKshTnfQDLAQAHAAcKshTnfQDLAQAAAA==.',
['ßö']='ßößßy:BAAANQADCgQIBAAAAA==.',
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
