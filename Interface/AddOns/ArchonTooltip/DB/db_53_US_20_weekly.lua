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

local lookup = {'Shaman-Elemental','Druid-Balance','Unknown-Unknown','Priest-Holy','Rogue-Assassination','Hunter-BeastMastery','Paladin-Retribution','Mage-Arcane','Mage-Frost','Druid-Guardian','Shaman-Restoration','Warrior-Arms','DeathKnight-Blood','Priest-Shadow','Rogue-Subtlety','DemonHunter-Vengeance','DeathKnight-Unholy','DemonHunter-Devourer','Warrior-Fury','Shaman-Enhancement','Monk-Mistweaver','Hunter-Marksmanship','DeathKnight-Frost','Warlock-Destruction','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Paladin-Protection','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Havoc','Warlock-Demonology','Paladin-Holy','Druid-Restoration','Warlock-Affliction','Druid-Feral','Warrior-Protection',}
local provider = {region='US',realm='Arthas',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abacas:BAABNQAECoEhAAIBAAkKZSJ+CACAAwABAAkKZSJ+CACAAwAAAA==.Abraanu:BAABNQAECoEZAAICAAgKhx/3FQDOAgACAAgKhx/3FQDOAgAAAA==.Abrohms:BAAANQAECgYIDQAAAA==.',
Ae='Aeily:BAEANQAECgMJAwAAAA==.Aethaeist:BAAANQAECgIJAQAAAA==.',
Ag='Agiel:BAAANQAECgcJBwAAAA==.',
Ah='Ahzula:BAAANQAECgEJAQABNQAECgcJEAADAAAAAA==.',
Ai='Aiger:BAAANQADCgUIBQAAAA==.Ais:BAABNQAECoEeAAIEAAgKPiPZCABFAwAEAAgKPiPZCABFAwAAAA==.Aitsu:BAABNQAECoEhAAIFAAkKNCRFAgCRAwAFAAkKNCRFAgCRAwAAAA==.Aivy:BAABNQAECoEaAAIGAAgK5CL8DQA0AwAGAAgK5CL8DQA0AwAAAA==.',
Aj='Ajm:BAAANQABCgEIAQAAAA==.',
Ak='Akkula:BAAANQADCgUIDAAAAA==.Akutagawa:BAAANQADCgcJBwABNQAFFAQJBwAHAGAlAA==.',
Al='Alaeris:BAAANQADCgcIBwAAAA==.Alexdare:BAAANQAECgYIEQAAAA==.Alfadelle:BAAANQAECgYIDAABNQAECgkJIAAIADkkAA==.Alicarrdd:BAAANQAECgQIBgAAAA==.Aling:BAAANQADCgcICwABNQAECgUIDQADAAAAAA==.Allbeefpatty:BAAANQAECgQJDQAAAA==.Almostbald:BAACNQAFFIEJAAIIAAQKZBt5DgBzAQAIAAQKZBt5DgBzAQA1AAQKgScAAwgACQojIy0VAGQDAAgACQojIy0VAGQDAAkAAQolIrUjAGIAAAAA.Alneeshi:BAABNQAECoEcAAMCAAgK8B0+FwDCAgACAAgK8B0+FwDCAgAKAAEKpRA9MwAvAAAAAA==.Alybella:BAAANQAECgEIAQAAAA==.',
Am='Amidate:BAAANQABCgEIAQAAAA==.Amoriandis:BAAANQADCgMJAwABNQAECgMIAwADAAAAAA==.',
An='Ancstrlbower:BAAANQADCgcJEwAAAA==.Anetra:BAAANQADCgcJDQAAAA==.Angharad:BAAANQADCgcICwABNQAECggIGAALAAkjAA==.Anot:BAABNQAECoEWAAIMAAgKGSKmHAANAwAMAAgKGSKmHAANAwAAAA==.Anothai:BAAANQADCgYICQAAAA==.Anton:BAAANQADCggIDgABNQAECgUIDQADAAAAAA==.Anutterone:BAAANQAECgQIBAAAAA==.Anzat:BAAANQAECgEJAQAAAA==.',
Ap='Apsaroke:BAAANQADCgYICwAAAA==.',
Aq='Aqi:BAAANQAECgcIEwAAAA==.',
Ar='Aralle:BAAANQAECgQIBwAAAA==.Aranea:BAAANQAECgIIAgAAAA==.Arclaw:BAAANQADCgYJBgAAAA==.Arin:BAAANQAFFAIJAgABNQAECgQJCAADAAAAAA==.Arkadu:BAAANQADCgEJAQAAAA==.Arkys:BAAANQADCgUJBQAAAA==.Arman:BAAANQADCgYIBgAAAA==.Armistice:BAAANQAECgEJAQAAAA==.Arrowyn:BAAANQAECgcJCwAAAA==.Arröwyn:BAAANQABCgIIAgAAAA==.',
As='Ashenis:BAAANQABCggICAAAAA==.Asphalt:BAAANQAECgUICAAAAA==.Astrà:BAAANQADCgEJAQAAAA==.',
At='Attidk:BAABNQAECoEYAAINAAgKwRDgMwDPAQANAAgKwRDgMwDPAQAAAA==.',
Au='Augful:BAAANQAECgcIEwAAAA==.Auspicious:BAABNQAECoEmAAMOAAkKRRrZEQCCAgAOAAgKHBnZEQCCAgAEAAkKmBezKABeAgAAAA==.Autýmn:BAAANQADCgcIDAABNQAECgYIDAADAAAAAA==.',
Av='Avadin:BAAANQAFFAIIAgABNQAECgcIEwADAAAAAA==.Avadinde:BAAANQAECgcIEwAAAA==.Avadingue:BAAANQADCgYIBgABNQAECgcIEwADAAAAAA==.Avadragon:BAAANQAECgEIAgABNQAECgcIEwADAAAAAA==.Avarogue:BAAANQADCgIIAgABNQAECgcIEwADAAAAAA==.Aversa:BAAANQADCgEIAQABNQAECgcJEAADAAAAAA==.Avvallae:BAAANQAECgQJBAABNQAECggIEgADAAAAAA==.',
Ay='Aylla:BAAANQAECgQIBgAAAA==.Ayrios:BAAANQADCgEIAQABNQAECgYIEAADAAAAAA==.Ayrious:BAABNQAECoEYAAIPAAgKNhGGEgAkAgAPAAgKNhGGEgAkAgAAAA==.',
['Aé']='Aéthric:BAAANQADCgUIBQAAAA==.',
Ba='Baalim:BAAANQAECgYJBgAAAA==.Backather:BAAANQADCgcJEwAAAA==.Backshocks:BAAANQADCgQIBAAAAA==.Bagger:BAAANQABCggIEwAAAA==.Bahalanagang:BAAANQADCggJBAAAAA==.Bahrasmyou:BAAANQADCgYIBgAAAA==.Bakkoutou:BAABNQAECoEhAAIQAAkKGiIPAQBwAwAQAAkKGiIPAQBwAwAAAA==.Baldelomar:BAAANQADCgEIAQAAAA==.Baltic:BAAANQAECgEJAQABNQAECggJGAAMAN4hAA==.Bambäm:BAAANQADCgYIBgABNQAECgQIBAADAAAAAA==.Bangers:BAAANQAECgMIBAAAAA==.Basix:BAAANQADCgUJDwAAAA==.Bastock:BAAANQAECgcICwAAAA==.',
Be='Beannzz:BAAANQADCgEIAQAAAA==.Beanzmachine:BAAANQAECgEIAQAAAA==.Bearstout:BAAANQAECgMJAwAAAA==.Beeans:BAAANQADCgEIAQAAAA==.Beestmaster:BAABNQAECoEXAAIGAAcKUiDUKgCJAgAGAAcKUiDUKgCJAgAAAA==.Belavik:BAABNQAECoEgAAIRAAkKUBsxEQDvAgARAAkKUBsxEQDvAgAAAA==.Bello:BAAANQADCgEJAQAAAA==.Beornna:BAAANQADCgMIAwAAAA==.Beowelf:BAABNQAECoElAAISAAkK7RsyCgAQAwASAAkK7RsyCgAQAwAAAA==.Beowulfsson:BAAANQAECgQIBwAAAA==.Bertabeef:BAAANQADCggIHQAAAA==.Betrayar:BAAANQADCgYICQAAAA==.Bezzert:BAAANQADCgYIBgAAAA==.',
Bh='Bheap:BAAANQAECgcJDwAAAA==.Bheapbheap:BAAANQADCggIFwAAAA==.',
Bi='Bigchungo:BAAANQADCgUICAAAAA==.Bigcook:BAAANQADCgYIBgAAAA==.Bigpaindk:BAAANQAECgUICAAAAA==.Bigpainpal:BAAANQADCgMIAwAAAA==.Bigshloppy:BAAANQAECgQIBwAAAA==.Billysblade:BAABNQAECoEYAAMMAAgKvRz8VAAZAgAMAAcKSBz8VAAZAgATAAQKoBqLDgA3AQAAAA==.Birtbirt:BAAANQABCggICwAAAA==.',
Bk='Bkers:BAAANQADCgYIBgAAAA==.',
Bl='Blebipty:BAABNQAECoEcAAIUAAkKZhQGCACsAgAUAAkKZhQGCACsAgAAAA==.Blessyoho:BAAANQADCgYICwAAAA==.Blitzbuster:BAAANQAECgUICgAAAA==.Blitzy:BAAANQADCgYIBgABNQAECgUICgADAAAAAA==.Blladee:BAAANQAECgQJBwAAAA==.Bloodjesser:BAAANQAECgEIAQAAAA==.Bloodrender:BAAANQABCgYICQAAAA==.Bluehorn:BAAANQADCgYIBgAAAA==.Bluekoolaid:BAAANQADCgQIBAAAAA==.Blumpkings:BAAANQADCgQJBwAAAA==.',
Bo='Bocan:BAAANQAECgUIBQAAAA==.Boingus:BAAANQADCgYIBgAAAA==.Bornshadow:BAAANQADCgUIBQAAAA==.',
Br='Brockly:BAAANQAECgYJEwAAAA==.Brolly:BAAANQAECgEIAQAAAA==.Brooski:BAAANQADCgQIBwAAAA==.Brotorious:BAAANQAECgcIEgAAAA==.',
Bu='Bubllz:BAAANQADCgYJBgAAAA==.Budgetroll:BAAANQADCgQIBAAAAA==.Bulluptuous:BAABNQAECoEaAAIMAAgK4RgxRwBLAgAMAAgK4RgxRwBLAgAAAA==.Bun:BAAANQABCgUIBQAAAA==.Burkmon:BAAANQAECgUICAAAAA==.Burret:BAAANQAECgUICQAAAA==.Butseven:BAAANQAECgMIAwAAAA==.Butterbubble:BAAANQAECgQICAAAAA==.',
['Bó']='Bótat:BAABNQAECoEYAAIVAAgK4AtuFQCcAQAVAAgK4AtuFQCcAQAAAA==.',
Ca='Cadiron:BAAANQAECgIIAgAAAA==.Caedance:BAAANQADCgYICgABNQAECggIGAALAAkjAA==.Cahrver:BAAANQADCgcIBwAAAA==.Caldergrim:BAAANQADCgQIBAAAAA==.Calumen:BAAANQAECgYICwAAAA==.Calypzo:BAAANQAECgQICgAAAA==.Camazótz:BAAANQABCgIJAgAAAA==.Carnages:BAAANQADCgQIBAABNQAECgUICQADAAAAAA==.Carvo:BAAANQADCgEJAQAAAA==.Caserius:BAAANQADCggIDAAAAA==.Casusbelli:BAAANQABCgIIAgAAAA==.Catta:BAAANQADCgMIBAABNQAECgMIAwADAAAAAA==.Catynca:BAAANQAECgQIDAABNQAECggIGAALAAkjAA==.',
Ce='Celieril:BAAANQAECgMJAwAAAA==.Cerilio:BAAANQAECgQIBgAAAA==.',
Ch='Changqing:BAAANQADCgUIBQABNQAECgYIDQADAAAAAA==.Chaparrín:BAAANQADCggJCQAAAA==.Checoburger:BAAANQAECgMJBQAAAA==.Cheiel:BAAANQAECggIEQAAAA==.Chendruid:BAAANQADCgQIBAAAAA==.Chillheart:BAAANQADCgYIBgAAAA==.Chitoes:BAAANQADCgcIBwAAAA==.Chylan:BAAANQADCgUIBQAAAA==.',
Ci='Cincolobos:BAAANQAECgQIBwAAAA==.Cinnaminsaph:BAAANQAECgIIAgAAAA==.',
Cl='Clipp:BAAANQAECgIIAgAAAA==.Cloraform:BAAANQADCgUIDQAAAA==.',
Co='Conduit:BAAANQAECgUIBgAAAA==.Conri:BAAANQAECgMJAwAAAA==.Coradk:BAAANQADCggICAABNQAFFAYIDQAHAFMPAA==.Cowmooz:BAAANQAECgYJCgAAAA==.',
Cr='Critaurus:BAABNQAECoEbAAIHAAkKRRD6UwAIAgAHAAkKRRD6UwAIAgAAAA==.Cronics:BAAANQADCgUJBQABNQAECgQJBAADAAAAAA==.Cronstione:BAABNQAECoEZAAMMAAkKrCIICgCLAwAMAAkKjCIICgCLAwATAAEKySD0GwBgAAAAAA==.Crushinater:BAAANQAECgYJEgAAAA==.Crzlock:BAAANQAFFAEIAQABNQAECgYIDgADAAAAAA==.',
Ct='Ctrlaltdel:BAAANQADCggICgAAAA==.',
Cz='Czrp:BAAANQAECgMIBAAAAA==.',
['Cô']='Côrack:BAACNQAFFIENAAIHAAYKUw+bAgDQAQAHAAYKUw+bAgDQAQA1AAQKgSQAAgcACQq8IXATADwDAAcACQq8IXATADwDAAAA.',
Da='Dad:BAAANQAECgcIBwAAAA==.Daddytank:BAAANQADCgUIBQAAAA==.Daedríc:BAAANQAECgYJDAAAAA==.Daeemon:BAAANQADCgcIBwABNQAECggIGAAPADYRAA==.Dagaa:BAAANQADCgYIEQAAAA==.Dagdeath:BAAANQAECgQICAAAAA==.Dagmarre:BAAANQADCgcIBwAAAA==.Dagothseth:BAAANQAECgEIAwAAAA==.Dagothsett:BAAANQADCgQIBwAAAA==.Daktz:BAAANQADCgYIBgAAAA==.Danelle:BAAANQADCggIEgAAAA==.Dankest:BAAANQAECgEJAwAAAA==.Darfòrce:BAAANQAECgIIAwABNQAFFAcJEwAWACcfAA==.Darison:BAAANQAECgYIDAAAAA==.Darkobey:BAAANQADCgEIAQAAAA==.Darreck:BAABNQAECoEYAAMWAAkK8CGNDgC/AgAWAAgKiSGNDgC/AgAGAAQKwyL8kwA9AQAAAA==.Darthmommy:BAAANQADCgYICgAAAA==.Darvus:BAAANQADCgEIAQAAAA==.Darwïn:BAAANQAECgEIAQAAAA==.Datonax:BAAANQAECgYIEAAAAA==.Davinity:BAAANQAECgYJDwAAAA==.Dayfire:BAAANQAECgQIBAAAAA==.',
Dd='Ddrizztt:BAAANQAECgYJDQAAAA==.',
De='Deadskill:BAABNQAECoErAAIRAAgKaxq6HwBmAgARAAgKaxq6HwBmAgAAAA==.Deathburrito:BAAANQADCgIIAgAAAA==.Deathloky:BAAANQAECgEJAwAAAA==.Decca:BAAANQAECgQICgAAAA==.Deeroy:BAAANQAECgYIDQAAAA==.Dehmonia:BAAANQADCgYIBgABNQAECgYIEgADAAAAAA==.Dela:BAAANQAECgUICgAAAA==.Delandèr:BAAANQADCgYICAABNQAECgUICgADAAAAAA==.Delerino:BAAANQADCgQIBwABNQAECgUICgADAAAAAA==.Demincy:BAAANQAECgcIDwAAAA==.Demonbruff:BAAANQAECgYJDwAAAA==.Demonflex:BAAANQAECgQICgAAAA==.Deoxys:BAAANQAECgMJAwAAAA==.Deset:BAAANQAECgYIDwAAAA==.Desprainer:BAAANQAECgQJBAAAAA==.Desse:BAAANQADCgUJCQAAAA==.Dew:BAAANQABCgcJCQAAAA==.Deydoria:BAAANQADCgIIAgAAAA==.',
Dg='Dgt:BAAANQAECgIIAgAAAA==.',
Dh='Dhalthron:BAAANQADCggICAAAAA==.',
Di='Dingùs:BAAANQAECgYICAAAAA==.Dirkadeux:BAAANQAECgcJEwAAAA==.Dirtyjay:BAAANQADCgEIAQAAAA==.Dirtyúndys:BAAANQAECgcJDAAAAA==.Discoliquid:BAAANQABCgEIAgAAAA==.Divinatrix:BAAANQADCgYJBwAAAA==.Divinecakes:BAAANQAECgcJEgAAAA==.Divineskillz:BAAANQAECgEIAQAAAA==.',
Do='Docmanhattan:BAAANQAECgQIBwAAAA==.Doesnttank:BAAANQADCgQICgAAAA==.Dogmatrix:BAAANQAECgcIEwAAAA==.Donsapo:BAAANQADCgYIBgABNQAECgMIBAADAAAAAA==.Doomshock:BAAANQADCgEIAQAAAA==.Dotcom:BAAANQAECgEIAQAAAA==.Doughmaker:BAABNQAECoEhAAIEAAkKCBY5NAAhAgAEAAkKCBY5NAAhAgAAAA==.Douru:BAAANQABCgMIAwAAAA==.',
Dr='Dracpo:BAAANQAECgEIAQAAAA==.Dragonskillz:BAAANQADCgUIBQAAAA==.Dreambender:BAAANQADCggICAAAAA==.Dreamdecoom:BAAANQAECgQJBQAAAA==.Dreamdekoop:BAABNQAECoEXAAIXAAkKGB6yEQCaAgAXAAkKGB6yEQCaAgAAAA==.Drededknight:BAAANQADCgcIBwAAAA==.Dreignos:BAAANQAECgYIDwAAAA==.Drillbit:BAAANQADCgEIAQAAAA==.Drizztski:BAAANQADCgYJDAABNQAECgYJDQADAAAAAA==.Drocalla:BAAANQAECgEIAQAAAA==.Drozghul:BAAANQADCgYIEwAAAA==.',
Du='Durnhelm:BAAANQADCgYIBgABNQAECgcIEwADAAAAAA==.Durto:BAAANQADCggIDAABNQADCgMIAwADAAAAAA==.Dushawee:BAABNQAECoEoAAMLAAkKIR6dHQCjAgALAAgKHB2dHQCjAgABAAUKBRTXeQAoAQAAAA==.',
['Dá']='Dárk:BAAANQADCgUIBQAAAA==.',
['Dä']='Dävös:BAAANQAECgYICgAAAA==.',
Ea='Earthwitch:BAAANQADCgcIDQABNQAECgkJJQAEABoWAA==.',
Eg='Egg:BAAANQAECggIEAABNQAFFAQJBwAYAL4fAA==.',
Ek='Ekalbs:BAAANQAECgcIEwAAAA==.',
El='Eliniia:BAAANQAECgEIAQAAAA==.Ellayri:BAABNQAECoEcAAIRAAgK9RK5JwApAgARAAgK9RK5JwApAgAAAA==.Elldis:BAAANQAECgYIDgAAAA==.Elleanor:BAAANQAECgMIBgABNQAECgcIEAADAAAAAA==.Elonor:BAAANQADCgMJAwAAAA==.Eltanin:BAAANQAECgIJAgAAAA==.',
En='Endling:BAAANQADCgcIBwAAAA==.Endoblades:BAAANQAECgQIBAABNQAECgUIDQADAAAAAA==.Endobleeds:BAAANQAECgIIAgABNQAECgUIDQADAAAAAA==.Endocrits:BAAANQADCggIDgABNQAECgUIDQADAAAAAA==.Endodaddy:BAAANQAECgMIBQABNQAECgUIDQADAAAAAA==.Endostars:BAAANQAECgUIDQAAAA==.Energykyouka:BAAANQAECgQJBQABNQAECgQJBQADAAAAAA==.Enferi:BAAANQAECgYIDgAAAA==.Enforcers:BAAANQAECgQIBAAAAA==.',
Eq='Equinoxdk:BAAANQAECggJDQAAAA==.',
Es='Essent:BAAANQAECgQJCAABNQAECgcJEwADAAAAAA==.Esthera:BAAANQADCgYJBgAAAA==.',
Ev='Evochiken:BAECNQAFFIEHAAIZAAUKegtrBQCHAQAZAAUKegtrBQCHAQA1AAQKgSYABBkACQp4Gk8HAAADABkACQp4Gk8HAAADABoABApzCyAhANMAABsAAQonCkIXADwAAAAA.Evokemode:BAABNQAECoEdAAIZAAgKjCWHAwBdAwAZAAgKjCWHAwBdAwAAAA==.',
Ex='Exorcism:BAAANQAECgYIDAAAAA==.Exotic:BAAANQAECggIEAAAAA==.Explosivoh:BAAANQAECgMIBQAAAA==.Exumm:BAAANQAECgUIDQAAAA==.',
Ey='Eyeforagge:BAAANQADCgMIAwAAAA==.',
Fa='Fakelashes:BAAANQABCgQJBQAAAA==.Farstriderr:BAAANQADCgcJLAAAAA==.Fataleclipse:BAAANQAECgUJCwAAAA==.Fatmir:BAAANQAECgEIAQAAAA==.',
Fe='Feigndps:BAAANQADCgQIBAABNQAECgEIAQADAAAAAA==.Feknwack:BAAANQADCgMIAwAAAA==.Feldrak:BAABNQAECoEXAAMZAAkKagr1HACDAQAZAAkKagr1HACDAQAaAAIKMgN+KgBSAAAAAA==.Feldriu:BAAANQADCgcJDQAAAA==.Felzel:BAAANQAECgcJBwAAAA==.',
Fi='Figai:BAAANQAECgYJDAAAAA==.Finebyme:BAAANQAECgEIAQAAAA==.Firebear:BAAANQAECgYIDAAAAA==.',
Fl='Flanknspank:BAACNQAFFIENAAIcAAUKPBfdAQCbAQAcAAUKPBfdAQCbAQA1AAQKgSgAAxwACQogIxECAJMDABwACQogIxECAJMDAAcAAgq+DvntAHsAAAAA.',
Fo='Formulated:BAAANQABCgQIBQAAAA==.Fotmreroller:BAAANQAECgQICQAAAA==.Fourtwenty:BAABNQAECoEVAAMdAAcKKg+mEwAvAQAdAAYKUwymEwAvAQAeAAMKOw+1NAC9AAAAAA==.Foxyladeh:BAAANQADCgMIAwAAAA==.Foxylady:BAAANQABCgMIBAAAAA==.',
Fr='Frjosa:BAAANQABCgEIAQAAAA==.Frostytongue:BAAANQADCgUIBgAAAA==.Fruitbasket:BAAANQAECgYIBgAAAA==.Frôstíe:BAAANQAECgEIAgAAAA==.',
Ga='Galadriella:BAAANQAECgUJBwAAAA==.Garglius:BAAANQAECggIAwAAAA==.',
Ge='Gekidos:BAAANQADCgcJDQAAAA==.Gekiretsu:BAAANQAECgEIAQAAAA==.Geodon:BAAANQAECgEJAQAAAA==.Geoffry:BAAANQAECgYIDQAAAA==.Gerbil:BAAANQAECgcJEwAAAA==.',
Gh='Ghostmonkey:BAAANQADCgEIAQAAAA==.',
Gi='Giaoman:BAAANQAECggJEAAAAA==.Gilgalock:BAAANQADCgIIAgABNQAECgkJHwAMADkeAA==.Gilwood:BAABNQAECoEhAAMWAAkK+hwVFwBOAgAWAAgKYhsVFwBOAgAGAAQKPh3/jwBGAQAAAA==.Gingyr:BAAANQAECgYIDAAAAA==.Girthywand:BAAANQAECgQICgABNQAECgYIDgADAAAAAA==.',
Gl='Glacialgimp:BAAANQAECgQIBwAAAA==.Gloinn:BAABNQAECoEhAAMIAAkKYx9cNgDqAgAIAAkKYx9cNgDqAgAJAAEKOCDbKwBCAAAAAA==.',
Gn='Gnomelyfans:BAABNQAECoEdAAIOAAgKCBK0GQAQAgAOAAgKCBK0GQAQAgAAAA==.Gnomorerage:BAAANQAECgIIAgABNQAECggIHQAOAAgSAA==.',
Go='Golfire:BAACNQAFFIEGAAMSAAQKJBBEBwDvAAASAAMKrg1EBwDvAAAfAAIKaQ0ADACTAAA1AAQKgSgAAxIACQq4IuIJABUDABIACQrpHuIJABUDAB8ABgp4IPAcADkCAAAA.Gooberlol:BAAANQAECggIEAAAAA==.Gorbashe:BAAANQADCgEJAQABNQAECgkJGwAHAEUQAA==.Gorbie:BAABNQAECoElAAISAAkKbRk3EAC0AgASAAkKbRk3EAC0AgABNQAECgYIDQADAAAAAA==.Gorestus:BAAANQAECgcJEwAAAA==.Gorlockholms:BAAANQAECgcIEAAAAA==.Gorthex:BAAANQAECgYJCgAAAA==.Gozziz:BAAANQAECgMIBQAAAA==.',
Gr='Graitlok:BAABNQAECoEVAAIMAAcKGBu9UgAiAgAMAAcKGBu9UgAiAgAAAA==.Grawd:BAAANQAECgYJDQAAAA==.Graysòn:BAAANQAECgMIAwAAAA==.Grilledchis:BAAANQAECgcIDQAAAA==.Grimdwagon:BAAANQAECgQJBQAAAA==.Griseldas:BAAANQAECgMIAwABNQAECgYJEgADAAAAAA==.Griswald:BAAANQAECgUIBgAAAA==.Grumpygranpa:BAAANQAECgQJDwAAAA==.Grypser:BAAANQAECgEIAQAAAA==.',
Gu='Guesswholoky:BAAANQAECgEIAQAAAA==.Guldán:BAAANQADCgUIBQAAAA==.Gulmatt:BAABNQAECoEbAAIYAAgKASJZAgAfAwAYAAgKASJZAgAfAwAAAA==.Gunslug:BAAANQADCgIIAgAAAA==.',
['Gí']='Gílgamore:BAABNQAECoEfAAMMAAkKOR64KwC9AgAMAAkKaxu4KwC9AgATAAIK2yR5EwDbAAAAAA==.',
Ha='Haguda:BAAANQAECgEIAQAAAA==.Hakaska:BAABNQAECoEYAAIdAAgKoRHqCwDVAQAdAAgKoRHqCwDVAQAAAA==.Hakkinen:BAAANQAECgcICAAAAA==.Hanswolo:BAAANQAECgIJAwAAAA==.Haramboned:BAAANQADCggIDgAAAA==.Harharof:BAAANQADCgIIAgAAAA==.Hatebreeder:BAAANQADCgYIBgABNQAECgIIAgADAAAAAA==.Hatise:BAAANQADCgQIBAAAAA==.Hawktuàh:BAAANQADCgUIBgAAAA==.',
He='Heirofdeath:BAAANQABCgYICQAAAA==.Heliotoro:BAAANQADCgUICgAAAA==.Hellebore:BAAANQADCgcIBwAAAA==.',
Hi='Hierba:BAAANQAECgcIDgAAAA==.Highlock:BAAANQAECgcICwAAAA==.Hilde:BAAANQADCgUICQAAAA==.',
Ho='Holigoat:BAAANQAECgIJAgAAAA==.Holycowbaby:BAAANQADCgQJBAABNQAECgQIBwADAAAAAA==.Holysam:BAAANQADCgUIBQAAAA==.Holyshhmon:BAAANQAECgEIAQAAAA==.Holystriker:BAAANQADCgcICAAAAA==.Holywitch:BAABNQAECoElAAMEAAkKGhbDIwB4AgAEAAkKGhbDIwB4AgAOAAEKcADjZQALAAAAAA==.Honnycorns:BAAANQAECgYICQAAAA==.Hoojah:BAAANQADCgMIBQAAAA==.Hormandacek:BAAANQAECgUJBQAAAA==.Hornguy:BAAANQAECgUJCgAAAA==.Hornstar:BAAANQAECgQIBAAAAA==.Houndoom:BAABNQAECoEdAAMgAAkKUiLzDwANAwAgAAgKjiLzDwANAwAYAAIKDxQjRQCMAAAAAA==.',
Hr='Hrulot:BAAANQADCgYIBgAAAA==.',
Hs='Hsr:BAABNQAECoEYAAIHAAgKNxiuRwA0AgAHAAgKNxiuRwA0AgAAAA==.',
Hu='Huataurga:BAAANQAECgYIEAAAAA==.Huff:BAABNQAECoEZAAIWAAkKQRrYDwCtAgAWAAkKQRrYDwCtAgABNQAFFAIIBgALADMmAA==.Hugetoke:BAAANQAECgIIAgAAAA==.Huktwo:BAAANQAECgUICgAAAA==.Hunternin:BAAANQAECgIIAgABNQAECgIJBAADAAAAAA==.Huron:BAAANQAECgQICAAAAA==.Huskarl:BAAANQADCggICAAAAA==.Hussypriest:BAAANQAECgcIDAAAAA==.',
Hy='Hyzerflip:BAAANQAECgMIBAAAAA==.',
['Hà']='Hàchi:BAACNQAFFIEKAAICAAUK+x2yAwDnAQACAAUK+x2yAwDnAQA1AAQKgScAAgIACQq8JdgBAM8DAAIACQq8JdgBAM8DAAAA.',
['Hä']='Hännibal:BAAANQADCgIIAgAAAA==.',
Ib='Ibsgodx:BAAANQADCgQIBAAAAA==.',
Id='Idiotfurry:BAABNQAECoEYAAIRAAgKbxt3GwCMAgARAAgKbxt3GwCMAgAAAA==.',
Ig='Igotatiara:BAAANQADCgYIBgAAAA==.',
Il='Iliad:BAAANQADCggICAAAAA==.Illidanheart:BAAANQABCgIIAgAAAA==.Illumináti:BAAANQADCgQJBAAAAA==.Ilmagnifico:BAAANQAECgcIEQAAAA==.',
Im='Imolegreg:BAABNQAECoEXAAINAAgK4htsGACWAgANAAgK4htsGACWAgAAAA==.Imperatris:BAAANQAECgEIAQAAAA==.Imvaernarhro:BAAANQADCgMIAwAAAA==.',
In='Inkubator:BAAANQAFFAEIAwAAAQ==.Inkyy:BAAANQADCgYIBgAAAA==.',
Ir='Irøns:BAAANQADCgYJDgAAAA==.',
It='Itemlevel:BAAANQADCgUIBgAAAA==.',
Iy='Iyamwarlock:BAAANQADCgYIBgAAAA==.Iyanden:BAAANQAECgMIBQAAAA==.',
Ja='Jabrogoz:BAAANQADCgMIAQAAAA==.Jahaerys:BAAANQADCgEJAQAAAA==.Jalahl:BAAANQADCgcJBwABNQAFFAUJCgAaAMgcAA==.Jastinos:BAAANQAECgQIBAAAAA==.',
Je='Jentrazka:BAAANQADCgIIAgABNQAECgUICgADAAAAAA==.Jezahbel:BAAANQAECgMIBgAAAA==.',
Ji='Jitteryjoe:BAAANQAECgYJDwAAAA==.',
Jo='Jokich:BAAANQABCggIEQAAAA==.Joseko:BAAANQAECgcIEwAAAA==.',
Ju='Juggsr:BAAANQAECgcJEwAAAA==.Justbower:BAAANQAECgMJAwAAAA==.',
Ka='Kaeyle:BAAANQADCgcIDgABNQAFFAUJCQAUAJ4RAA==.Kamico:BAAANQADCgUICQAAAA==.Kansoika:BAAANQADCgcIBwAAAA==.Kaptainpiss:BAAANQADCgYJBgAAAA==.Karakitana:BAAANQADCgYIBQABNQAECggIEgADAAAAAA==.Kasualtrash:BAAANQADCgcJCQAAAA==.Katfury:BAAANQAECgcJEQAAAA==.Kattallina:BAAANQADCgcJBwAAAA==.Kattmini:BAACNQAFFIEIAAMgAAUKGQwGCQAqAQAgAAQK7QwGCQAqAQAYAAIKUwXLCgCZAAA1AAQKgSkAAyAACQqJIJ8WAOECACAACApEIJ8WAOECABgABwpLFy4NAAUCAAAA.Katto:BAAANQAECgMIAwAAAA==.',
Ke='Keffká:BAAANQADCggIDAAAAA==.Kelebrimbor:BAAANQAECgEIAQAAAA==.Keyalidas:BAAANQADCgEIAQAAAA==.Keylime:BAAANQAECgIIAgAAAA==.',
Kh='Khane:BAAANQADCggIDwAAAA==.Kharras:BAAANQADCggICgAAAA==.',
Ki='Killabattle:BAAANQADCgcIBwAAAA==.Kilyna:BAABNQAECoEUAAIgAAgKuw+iSgD1AQAgAAgKuw+iSgD1AQAAAA==.Kirbÿ:BAAANQAECgcJDAAAAA==.Kisha:BAAANQADCgYJBgAAAA==.',
Ko='Kodeezy:BAAANQADCggICAABNQAECgkJJAAHAJAdAA==.Kodita:BAABNQAECoEkAAIHAAkKkB3iGwADAwAHAAkKkB3iGwADAwAAAA==.',
Kr='Krakair:BAAANQAECgUICgAAAA==.Krhon:BAAANQAECgQJBgAAAA==.Kryptic:BAAANQAECgQJCgAAAA==.',
Ky='Kylea:BAAANQAECgUJCAAAAA==.Kyntaro:BAAANQADCgcICQAAAA==.Kyouka:BAAANQAECgQJBAABNQAECgkJHgAgAE8gAA==.Kysira:BAAANQAECgYJDwAAAA==.',
La='Lailai:BAAANQAECgUIDgABNQAECgYICAADAAAAAA==.Lalax:BAAANQABCgQIBQAAAA==.Lalechuga:BAAANQAECgYJEAAAAA==.Lanerian:BAAANQAECgMIAwAAAA==.',
Ld='Ldytncty:BAAANQADCgUJBQAAAA==.',
Le='Leadah:BAAANQADCgUIBQAAAA==.Ledge:BAAANQAECgEIAQABNQAECgIIAgADAAAAAA==.Ledgebear:BAAANQAECgIIAgAAAA==.Leerwandler:BAAANQAECgQICAAAAA==.Lehunt:BAABNQAECoEeAAIWAAkK2Bh+DgC/AgAWAAkK2Bh+DgC/AgAAAA==.Leiyong:BAAANQAECgEIAQAAAA==.Letmedoitpls:BAAANQABCgMIBQAAAA==.Levigosa:BAAANQADCgYIDAAAAA==.Lexadin:BAAANQABCgIIAgAAAA==.Leylanie:BAAANQAECggIBgAAAA==.',
Li='Liadarel:BAAANQADCgMIAwAAAA==.Liael:BAAANQADCgQIBAAAAA==.Lightlobster:BAAANQAECgQIBAABNQAECgkJJgAUANwfAA==.Lightwalker:BAAANQAECgEJAQABNQAECgQJBAADAAAAAA==.Lilpuffz:BAAANQAECgYJDQAAAA==.Lisaleri:BAAANQADCgYIBwAAAA==.Liteorheavy:BAAANQADCgIIAgAAAA==.Livewires:BAAANQADCgcICQABNQAECgUJDAADAAAAAA==.',
Ll='Llandshark:BAAANQAECgYIDgAAAA==.Lleyla:BAABNQAECoEYAAMLAAgKCSOwDQAcAwALAAgKCSOwDQAcAwABAAIKoQkTvgBqAAAAAA==.',
Lo='Loavoltage:BAAANQADCgUIBQAAAA==.Lockjaw:BAAANQAECgEIAQABNQAECgIIAgADAAAAAA==.Lockyboi:BAAANQADCgUIBQABNQAECgYIDwADAAAAAA==.Locomoko:BAAANQADCggJCAAAAA==.Lohre:BAAANQADCgIIAgAAAA==.Lojik:BAAANQADCggJBQAAAA==.Long:BAAANQAECgQJCwAAAA==.Lonoh:BAAANQAECgQJBAAAAA==.Lookimapanda:BAAANQAECgQIBAAAAA==.Lorakmahktar:BAAANQAECgYJCgAAAA==.Lottie:BAAANQAECgUJCgAAAA==.',
Lu='Luarhea:BAAANQAECgUJCgAAAA==.Luccina:BAAANQAECgcJEAAAAA==.Lucîd:BAAANQAECgUIDQABNQAECgcJCwADAAAAAA==.Luminarie:BAABNQAECoEhAAIhAAkKuSCXCQBKAwAhAAkKuSCXCQBKAwAAAA==.Lunitari:BAABNQAECoEgAAIIAAkKOSRhCQCjAwAIAAkKOSRhCQCjAwAAAA==.Luvalot:BAAANQAECgIIAwAAAA==.',
Lx='Lxbeowulfxl:BAAANQADCgcJCgAAAA==.',
Ly='Lyraiel:BAAANQAECgYIEwAAAA==.Lysaera:BAAANQAECgQIBAAAAA==.',
['Lü']='Lücíd:BAAANQADCggICAABNQAECgcJCwADAAAAAA==.',
Ma='Mackantosh:BAAANQAECgYICgAAAA==.Mackpyre:BAAANQAECgMIAwABNQAECgYICgADAAAAAA==.Madness:BAAANQABCggICQAAAA==.Magelha:BAAANQADCgYIBgAAAA==.Magmalash:BAAANQADCgEIAQAAAA==.Magoroxx:BAAANQAECgYICwAAAA==.Mahots:BAAANQAECgMIAwAAAA==.Maiyathicc:BAAANQAECgQJCQAAAA==.Makagalvan:BAABNQAECoEhAAIMAAkKiRhtOQCAAgAMAAkKiRhtOQCAAgAAAA==.Malakes:BAAANQAECggIDQABNQAECggIEAADAAAAAA==.Malthael:BAABNQAECoEYAAIMAAkK7iM2FAA/AwAMAAkK7iM2FAA/AwABNQAFFAQJBwAHAGAlAA==.Malzahar:BAAANQADCgcIBwAAAA==.Manamgmtllc:BAAANQADCgYIBgAAAA==.Mantu:BAAANQAECggJBwAAAA==.Maplepriest:BAAANQADCgYIBgAAAA==.Markyle:BAEANQADCgYIBgABNQAECgUICgADAAAAAA==.Martien:BAAANQAECgMJCAAAAA==.Massteraria:BAAANQADCggIDwAAAA==.Masstercard:BAABNQAECoEXAAIeAAkKfh2LCQDyAgAeAAkKfh2LCQDyAgAAAA==.Maxeras:BAAANQAECgMIBAAAAA==.Maximus:BAAANQAECgUJDwAAAA==.Maya:BAABNQAFFIEHAAIIAAUKPROnCgCyAQAIAAUKPROnCgCyAQAAAA==.Mayoi:BAAANQADCgYIDAAAAA==.Mazo:BAABNQAECoEgAAMfAAkKsCM8BgBgAwAfAAkKsCM8BgBgAwASAAQKDRc9NgAnAQAAAA==.',
Mb='Mbuku:BAAANQAECgYIBgAAAA==.',
Mc='Mcroguez:BAABNQAECoEdAAMPAAgKRh1dDACBAgAPAAcKMyBdDACBAgAFAAQKhBA1OgANAQAAAA==.',
Me='Meeche:BAAANQAECgQIBQAAAA==.Melfpally:BAAANQAECgUIBQAAAA==.Menagerie:BAABNQAECoEeAAMgAAkKTyDJBwBXAwAgAAkKTyDJBwBXAwAYAAEKCBFVXwBBAAAAAA==.Metche:BAAANQAECgUIBgAAAA==.Mezzy:BAAANQADCggJCQAAAA==.',
Mi='Mightythighs:BAAANQAECgYIDgAAAA==.Mihd:BAAANQAECgQICgAAAA==.Miisch:BAAANQAECgQICAAAAA==.Milkyy:BAAANQAECgYJDgAAAA==.Millamaxwell:BAAANQADCgcICwABNQAECgkJIQAaAPkYAA==.Minimus:BAAANQAECgYJEAAAAA==.Miraeth:BAAANQAECgEJAgAAAA==.Misknocker:BAAANQAECgMIBgAAAA==.',
Mo='Moistivall:BAAANQADCgYJCgAAAA==.Moisturize:BAAANQABCgUIBQAAAA==.Momô:BAAANQAECgIIAwABNQAECgMJBwADAAAAAA==.Monkred:BAAANQAECgcIDAAAAA==.Monte:BAAANQAECgUIBQAAAA==.Moobees:BAAANQAECgQICQAAAA==.Mooge:BAEANQADCgYICwABNQAECgUICgADAAAAAA==.Mooiester:BAAANQAECgIJAgAAAA==.Moomanchuu:BAAANQADCgMIAwAAAA==.Moomins:BAAANQAECgQJBgABNQAECgkJIAAIADkkAA==.Mortuous:BAAANQAECgIIBAAAAA==.Mosthated:BAAANQAECgIIAgAAAA==.',
Ms='Mstrfreekill:BAAANQAECgYJEwAAAA==.',
Mu='Mubu:BAAANQAECgQIBQAAAA==.Mudpriest:BAABNQAECoEYAAIEAAgK8iEcEgDuAgAEAAgK8iEcEgDuAgAAAA==.Muffdiiva:BAAANQAECgQICgAAAA==.Muffinmán:BAAANQAECgEJAQAAAA==.Mulletman:BAAANQAECgcIEgAAAA==.Murphlord:BAAANQAECgUJBQAAAA==.Musky:BAABNQAECoEcAAIMAAgKNRngQgBcAgAMAAgKNRngQgBcAgAAAA==.Muskydk:BAAANQADCgYJBgABNQAECggJHAAMADUZAA==.Muskydruid:BAAANQAECgcIEAABNQAECggJHAAMADUZAA==.Muskyshnoze:BAAANQADCgQJBQABNQAECggJHAAMADUZAA==.',
My='Mystogån:BAAANQADCggIDwAAAA==.Mystrix:BAAANQAECgcJDwAAAA==.Mytthdk:BAAANQADCgcJBwAAAA==.Myzary:BAAANQAECgEJAQAAAA==.',
['Mè']='Mèggz:BAAANQADCgIIAwAAAA==.',
['Më']='Mërcy:BAAANQAECgUIBgAAAA==.',
['Mí']='Míghty:BAAANQABCgIIAgAAAA==.Míthrandír:BAABNQAECoEpAAIIAAkK2x/dIAA0AwAIAAkK2x/dIAA0AwAAAA==.',
['Mô']='Mômo:BAAANQAECgMJBwAAAA==.',
['Mû']='Mûfâsâ:BAAANQADCggJDgAAAA==.',
Na='Nardhaa:BAAANQAECgcIEQAAAQ==.Narkiel:BAAANQADCgEJAQAAAA==.Narrius:BAAANQAECgcIEAAAAA==.Nathzandalar:BAAANQADCgUIBQAAAA==.Natraps:BAAANQAECgUIBwAAAA==.',
Ne='Neartonoir:BAAANQABCgcJDAAAAA==.Nesmage:BAAANQAECgQJBAAAAA==.Nesmie:BAAANQAECgYJEwAAAA==.',
Ni='Nijek:BAAANQAECgYIDAAAAA==.Nimchip:BAACNQAFFIEHAAIMAAQK+RHCCwA5AQAMAAQK+RHCCwA5AQA1AAQKgTwAAgwACQo1IUIaABoDAAwACQo1IUIaABoDAAAA.',
Nl='Nlrvana:BAAANQADCgEJAQAAAA==.',
No='Nokkakkash:BAAANQADCggICAAAAA==.Notheysus:BAAANQADCgcIBwAAAA==.Notmyforte:BAAANQAECgYIDAAAAA==.',
Nu='Nudillos:BAAANQADCgcIBwAAAA==.Nudnarb:BAAANQADCgQIBAAAAA==.Nurflocks:BAAANQADCgYIBgAAAA==.',
Ny='Nyankobrq:BAAANQAECgQJBQAAAA==.Nyxtheabyss:BAAANQADCgQIBAAAAA==.',
['Ná']='Náthe:BAAANQAECgMIAwAAAA==.',
Oa='Oakzz:BAEANQAECgYIBgABNQAECggIGAAaAKgbAA==.',
Ob='Obalnhabdea:BAAANQAECgIJAgAAAA==.Oblvn:BAAANQAECgIJAgAAAA==.',
Oc='Ocêangrown:BAAANQADCggIBQAAAA==.',
Od='Odhran:BAAANQAECgcICgAAAA==.',
Oh='Ohda:BAAANQAECgQJCAAAAA==.Ohgodbees:BAAANQAECgMIBAAAAA==.',
Oi='Oisn:BAAANQAECgQIBQABNQAECgcJEwADAAAAAA==.',
Ol='Oldlove:BAAANQAECgEIAQABNQAECgcICwADAAAAAA==.',
On='Onepiece:BAAANQADCgYJCgAAAA==.Onís:BAAANQAECgcJEwAAAA==.',
Op='Opspartan:BAAANQABCgYICgAAAA==.',
Or='Orastal:BAAANQADCgYJDAABNQAECgYIDgADAAAAAA==.Oravoker:BAAANQAECgYIDgAAAA==.Orcishz:BAAANQADCgQIBwAAAA==.Oreweyna:BAAANQABCgIIBAAAAA==.Orion:BAAANQADCgcIDAAAAA==.',
Os='Osawa:BAAANQADCgYIDwABNQAECgUJEAADAAAAAA==.Osk:BAAANQAECgcIBgAAAA==.Ostidevache:BAAANQADCgYICQAAAA==.',
Oy='Oyobi:BAAANQADCgEIAQAAAA==.',
Oz='Ozshock:BAAANQAECgYIDAAAAA==.',
Pa='Paffdk:BAAANQAECgUIDQAAAA==.Paiyn:BAAANQADCgcIBwAAAA==.Palamix:BAAANQAECgIJBAAAAA==.Palladone:BAAANQAECgQICgAAAA==.Palthron:BAAANQAECgUIDQAAAA==.Palychick:BAAANQAECgcIDQAAAA==.Pampersxl:BAABNQAECoEZAAMGAAgKDBztMQBrAgAGAAcKAh7tMQBrAgAWAAUKag2mNAAHAQAAAA==.Pandatheis:BAAANQADCgUIBQAAAA==.Pandatotem:BAAANQADCgYICgAAAA==.Pangoro:BAACNQAFFIEKAAISAAUKXhr0AgDLAQASAAUKXhr0AgDLAQA1AAQKgSgAAhIACQpzIxUDAJkDABIACQpzIxUDAJkDAAAA.Paragondk:BAAANQAFFAEIAQAAAA==.Paragonlock:BAAANQAECgYJDAABNQAFFAEIAQADAAAAAA==.Paramedic:BAABNQAFFIEHAAIHAAQKYCUQAwC7AQAHAAQKYCUQAwC7AQAAAA==.Parser:BAAANQADCgMIAwAAAA==.',
Pe='Pelikanesis:BAAANQAECgMIBAAAAA==.Pelolindo:BAAANQADCggICAAAAA==.Penance:BAAANQAECgMIBAAAAA==.Pestus:BAAANQADCgYJEQAAAA==.Peteqc:BAAANQADCgUIBQAAAA==.Petshunt:BAAANQAECggICAABNQADCggICQADAAAAAA==.',
Ph='Phageborn:BAACNQAFFIEFAAINAAMKQRyRCgD9AAANAAMKQRyRCgD9AAA1AAQKgR4AAg0ACAoeJCUMABoDAA0ACAoeJCUMABoDAAAA.Phiavel:BAAANQADCgYJEAAAAA==.Philmahuders:BAAANQADCgIIAgAAAA==.Phoop:BAAANQADCggIDwAAAA==.',
Pi='Pik:BAAANQAECgUIDAAAAA==.Pillowpants:BAAANQAECgUIBwAAAA==.Pineappleish:BAAANQAECgcICgAAAA==.Pinkcross:BAAANQAECgQJBwABNQAFFAYIAQADAAAAAA==.Pinkfuzi:BAAANQAECgMJAwAAAA==.',
Po='Pocketlockit:BAAANQAECgYJCwABNQAECggIFwANAOIbAA==.Poisonousx:BAAANQAECgEJAgAAAA==.Poka:BAAANQAECgUICgAAAA==.Poluna:BAAANQAECgQJCAAAAA==.Polynium:BAAANQADCgcJBwAAAA==.Pookei:BAAANQADCgcIBwAAAA==.Poprocket:BAAANQADCggIDgABNQAECgUIDQADAAAAAA==.Popsiclegirl:BAAANQADCgQJBAAAAA==.Porkkchopp:BAABNQAECoEWAAILAAgKFBhLLgBDAgALAAgKFBhLLgBDAgAAAA==.',
Pr='Prayermonger:BAAANQAFFAIJAwAAAQ==.Prialise:BAAANQAECgMJAwAAAA==.Priesticle:BAAANQAECgQICAABNQAFFAEIAQADAAAAAA==.Promptoa:BAAANQAECgYIBgAAAA==.Protendo:BAAANQADCggIEAAAAA==.Provider:BAAANQAECgIIAwAAAA==.',
Ps='Psyke:BAAANQADCgUJBQAAAA==.',
Pu='Pufftreez:BAABNQAECoEXAAMgAAgKkg1gYgChAQAgAAcKGA9gYgChAQAYAAUKOQXWLgDoAAAAAA==.Purplatath:BAAANQADCgYICAAAAA==.Purpledrink:BAAANQAECgYIEQAAAA==.Purplette:BAAANQADCggICwAAAA==.Purplizor:BAAANQAECgIIAgAAAA==.',
Pw='Pwincessmeow:BAAANQADCgYIFwAAAA==.',
Py='Pynki:BAAANQADCggICwAAAA==.Pyroxion:BAAANQAECgQJBQAAAA==.Pyrìz:BAAANQAECgUIDwAAAA==.',
Qi='Qiill:BAAANQADCggJEAAAAA==.',
Qu='Quadratic:BAAANQADCgUIBwAAAA==.Quikzmagez:BAAANQADCgYIBgAAAA==.Quikzpriest:BAAANQADCgYJBQAAAA==.',
Qw='Qweefur:BAAANQAECgMIAwAAAA==.',
Ra='Rabidwombat:BAACNQAFFIEGAAILAAIKMyY7CwDjAAALAAIKMyY7CwDjAAA1AAQKgSQAAgsACQrJJMwDAJQDAAsACQrJJMwDAJQDAAAA.Racoto:BAAANQAECgMIBQAAAA==.Ragingwagyu:BAAANQAECgEIAQAAAA==.Ragrega:BAAANQADCgIIAgABNQAECggIGAAhANAhAA==.Rainey:BAAANQADCgIJAgAAAA==.Rainie:BAAANQADCgcIBwAAAA==.Ralokian:BAACNQAFFIEKAAMaAAUKyByIAQDKAQAaAAUKbxuIAQDKAQAbAAIKNx66AwCuAAA1AAQKgSYAAxoACQorJYsBAJwDABoACQojJIsBAJwDABsACAoIJboBADcDAAAA.Rangoo:BAAANQADCgUIBQAAAA==.Raphaelle:BAAANQAECgUIDgAAAA==.Ravelled:BAAANQAECgUJCQAAAA==.Ravencláw:BAAANQADCgYICwAAAA==.Ravenmane:BAABNQAECoEYAAIHAAgK2hwxLgChAgAHAAgK2hwxLgChAgAAAA==.Rawdaug:BAAANQAECgUIBQAAAA==.Razziz:BAAANQAECgUICwAAAA==.Raín:BAAANQAECgIJAgAAAA==.',
Re='Regolas:BAAANQAECgIJAgAAAA==.Rejuvie:BAAANQAECgcIDwAAAA==.Relazrasum:BAAANQAECgEJAQAAAA==.Relzzad:BAAANQAECgUIDQAAAA==.Renalyne:BAAANQADCgEIAQABNQAFFAQJBwAEAOoMAA==.Rentámonk:BAAANQADCgEIAQABNQAECgQICAADAAAAAA==.Rentápally:BAAANQAECgQICAAAAA==.Retch:BAAANQADCgEJAQAAAA==.Revelätion:BAAANQAECgEIAQAAAA==.Rexxaar:BAAANQAECgUICQAAAA==.',
Ri='Riata:BAABNQAECoEWAAIMAAgKCw8rZwDZAQAMAAgKCw8rZwDZAQAAAA==.Ricericebaby:BAAANQAECgIJAwAAAA==.Rikaya:BAAANQAECgYJCgAAAA==.Riot:BAAANQADCgUJCQABNQAECgUJEAADAAAAAA==.',
Ro='Robertcheeto:BAABNQAECoEhAAIiAAkK5BuEDACiAgAiAAkK5BuEDACiAgAAAA==.Rogchamita:BAABNQAECoEbAAILAAkKdhpCFQDcAgALAAkKdhpCFQDcAgAAAA==.Ronalde:BAAANQAECgYICwAAAA==.Rondall:BAAANQAECgYIDwAAAA==.Rousera:BAAANQAECggIEgAAAA==.Roxxaan:BAAANQAECgUICQAAAA==.Royvn:BAAANQAECgUJDAAAAA==.',
Ru='Rubicon:BAAANQADCgIIAgAAAA==.Ruffels:BAAANQAECgEIAQAAAA==.Rukiakuchki:BAAANQADCgMJAwAAAA==.Runtzz:BAAANQADCgQIBAAAAA==.',
Ry='Ryushinizi:BAAANQADCgIIAgABNQAECgUICQADAAAAAA==.',
Sa='Saberana:BAAANQADCgcJEAAAAA==.Sadllama:BAAANQAECgYJEgAAAA==.Saintcow:BAAANQADCgYIBgAAAA==.Saintl:BAABNQAECoEhAAIWAAkKqRfzFABpAgAWAAkKqRfzFABpAgAAAA==.Saloriel:BAAANQADCggJCwAAAA==.Sammwow:BAAANQAECgcIEQAAAA==.Sammyl:BAAANQABCggIDwAAAA==.Sanalin:BAAANQADCgIIAgABNQADCgcJBwADAAAAAA==.Sanlerøs:BAAANQAECgYJCQAAAA==.Sarandots:BAAANQADCgEIAQABNQAECggIGAAiAJ0LAA==.Saranfarmer:BAABNQAECoEYAAIiAAgKnQtUHgChAQAiAAgKnQtUHgChAQAAAA==.Sarantakos:BAAANQADCgYICgABNQAECggIGAAiAJ0LAA==.Sarviez:BAAANQADCgcIBwAAAA==.Sass:BAAANQADCggICAABNQAECggJGQACAK4YAA==.',
Sc='Schwetyß:BAAANQADCgYIBgAAAA==.Scolio:BAAANQAECgUJCAAAAA==.Scourgeguy:BAAANQAECgUJCwAAAA==.',
Se='Separation:BAAANQADCgUIBgAAAA==.Severance:BAAANQAECgUIBQABNQAECgYJEAADAAAAAA==.Seves:BAAANQADCgcJDAAAAA==.',
Sh='Shadosham:BAAANQAECgQIBwAAAA==.Shadowcakes:BAAANQAECgQIBAAAAA==.Shadowsmith:BAABNQAECoEfAAMYAAkKYhzRFwCVAQAgAAYK3hv8WwC2AQAYAAYK1BPRFwCVAQAAAA==.Shaggyveins:BAAANQAECgEIAQAAAA==.Shamanella:BAAANQADCggICAAAAA==.Shamooky:BAEANQAECgUICgAAAA==.Shanke:BAAANQAECgUICwAAAA==.Shenanignism:BAAANQABCgEIAQAAAA==.Shieldbane:BAAANQADCggICAAAAA==.Shizzkin:BAAANQADCgcIBwAAAA==.Shmotz:BAAANQABCgIIAgAAAA==.Shockrender:BAAANQAECgIIAgABNQAECgQJBAADAAAAAA==.Shocktoke:BAAANQAECgIIAwAAAA==.Shockzone:BAAANQAECgUIBwAAAA==.Shootymcgun:BAAANQAECgQIBAAAAA==.Shots:BAABNQAECoEhAAIMAAkKtRH/TQAyAgAMAAkKtRH/TQAyAgAAAA==.Shotsonshots:BAAANQADCggIDQAAAA==.Shoulders:BAAANQAECgYJBgAAAA==.',
Si='Siado:BAAANQAECgEIAgAAAA==.Sidesandwich:BAAANQAECgcICwAAAA==.Sikkò:BAAANQABCgEIAQAAAA==.Sinthetic:BAAANQAECgQJCAAAAA==.Siqi:BAAANQADCgEIAQAAAA==.',
Sk='Skills:BAAANQADCggIDAAAAA==.Skillzhunter:BAAANQADCgcIBwAAAA==.Skornn:BAAANQAECgQIBAAAAA==.Skyfangret:BAAANQADCggIEgAAAA==.Skysweep:BAAANQADCgYIBQABNQAECgcJEAADAAAAAA==.',
Sl='Slag:BAAANQADCgcJEAABNQAECgMIAwADAAAAAA==.Slappypaws:BAAANQADCgYIBgABNQADCgYJBgADAAAAAA==.Slaptrix:BAAANQABCgEIAQAAAA==.Slayerlilith:BAAANQADCgIIAgAAAA==.Slickxoxo:BAAANQAECgEIAQAAAA==.Slizaro:BAABNQAECoEYAAIGAAcKhBnGQQAxAgAGAAcKhBnGQQAxAgAAAA==.Sloponmyknob:BAAANQAECgEIAQABNQAECgQIBwADAAAAAA==.',
Sm='Smashendash:BAAANQAECgQIBwAAAA==.Smolslaps:BAAANQAECgYIDAABNQADCgYJBgADAAAAAA==.Smoothiebowl:BAAANQADCgcIBwAAAA==.',
Sn='Snakeyess:BAAANQAECgEIAQAAAA==.Snappypuppy:BAAANQADCgIIAgABNQADCgYJBgADAAAAAA==.Sneakygaia:BAAANQABCgEIAgAAAA==.',
So='Sockemm:BAAANQAECgcIDQAAAA==.Solastus:BAAANQADCgEJAQAAAA==.Sollaria:BAAANQABCggICwAAAA==.Somma:BAAANQADCgcIBwAAAA==.Sorchanna:BAAANQADCgcJFAAAAA==.Soulamander:BAABNQAFFIEOAAIZAAYKYwjcAwDDAQAZAAYKYwjcAwDDAQAAAA==.Souza:BAAANQAECgUJDAAAAA==.Soül:BAABNQAECoEYAAMVAAkK0hAlDgAnAgAVAAkK0hAlDgAnAgAeAAIKJgc/QABbAAAAAA==.',
Sp='Spikeyboy:BAAANQADCgYIBgAAAA==.Spinal:BAAANQAECgYIDgAAAA==.Spiritfinger:BAAANQAECgUICwABNQAECggIFAARAPcbAA==.',
Sq='Sqrood:BAABNQAECoEYAAIIAAgKdRAxgQAVAgAIAAgKdRAxgQAVAgAAAA==.Squâll:BAAANQAECgEIAQAAAA==.',
Sr='Srdlosrayoz:BAAANQAECggICAAAAA==.',
St='Stativa:BAAANQADCgYIBgAAAA==.Stellaris:BAAANQAECgYIDAAAAA==.Stevesmiff:BAAANQADCgUIBwAAAA==.Sting:BAAANQAECgQJCgAAAA==.Stoofy:BAAANQADCgQIBAABNQAFFAUIDQAcADwXAA==.Stormbreakur:BAAANQADCggIGAAAAA==.Stormskillz:BAAANQADCgYIBgAAAA==.Strapperjack:BAAANQADCgUIBQAAAA==.',
Su='Sugarhammer:BAAANQADCgEIAQAAAA==.Sunarri:BAAANQAECgUJBQAAAA==.Sunbourne:BAAANQAECgUICgAAAA==.Suradin:BAAANQAECgcIDQAAAA==.Surdaddy:BAAANQAECgQICAAAAA==.Surín:BAAANQADCgcIBwAAAA==.',
Sy='Syrathia:BAAANQAECgMJBgAAAA==.',
['Sî']='Sîcarius:BAAANQADCgcIDgAAAA==.',
['Só']='Sóulglów:BAAANQADCgUIBQAAAA==.',
['Sú']='Súcellus:BAAANQADCgYIBgAAAA==.Súrë:BAACNQAFFIEKAAIZAAUKMRmpAwDLAQAZAAUKMRmpAwDLAQA1AAQKgSkAAhkACQqIIoIDAF0DABkACQqIIoIDAF0DAAAA.',
Ta='Tahtics:BAAANQAECgcIEQAAAA==.Talmahua:BAAANQADCgUJBQAAAA==.Tangolay:BAAANQADCgIIAgABNQAECgYICgADAAAAAA==.Tatyl:BAABNQAECoEbAAMgAAgKGSDBJwCEAgAgAAcKLiDBJwCEAgAYAAQKWRhhJwAWAQAAAA==.Tazana:BAAANQAECgEJAQAAAA==.',
Te='Tehsirus:BAAANQAECgYJDAAAAA==.Temoro:BAAANQADCgYIBgABNQADCggICAADAAAAAA==.Tempestaurus:BAAANQAFFAEJAgAAAA==.Tenkok:BAAANQAECgQICgAAAA==.Tewpok:BAABNQAECoEaAAQjAAgKowxgBwCiAQAjAAcK2QtgBwCiAQAYAAIK3Qx2TQBzAAAgAAIKzwee0ABoAAAAAA==.',
Th='Thalisan:BAAANQAECgQJBwAAAA==.Thatmage:BAAANQAECgYJDQAAAA==.Thebeanzz:BAAANQAECgYIBgAAAA==.Theirashes:BAAANQADCgMIAwABNQAECgkJIAAkALQjAA==.Themoistest:BAAANQAECgcJDQAAAA==.Theothehero:BAABNQAECoEgAAIgAAkKzx6cDQAfAwAgAAkKzx6cDQAfAwAAAA==.Thewogfather:BAAANQAECgQIBQAAAA==.Thirdhank:BAAANQADCgYIBgAAAA==.Thoar:BAACNQAFFIEJAAIUAAUKnhHhAAC4AQAUAAUKnhHhAAC4AQA1AAQKgScAAhQACQr3ItsBAH8DABQACQr3ItsBAH8DAAAA.Thormoon:BAAANQAECgcJEQAAAA==.Thraller:BAAANQADCgYIBgAAAA==.',
Ti='Tiahdoe:BAAANQADCggIEwAAAA==.Tiariel:BAABNQAFFIEKAAINAAYK4QknBgB0AQANAAYK4QknBgB0AQAAAA==.Tiriq:BAAANQAECgQIBQAAAA==.',
To='Tolnar:BAABNQAECoEdAAMFAAgKJhh8LAByAQAFAAUK2xZ8LAByAQAPAAUK9hNiIgBvAQAAAA==.Tolnter:BAAANQADCgYIDAAAAA==.Toodle:BAAANQAECggIDwAAAA==.Torgrun:BAAANQAECgYIDAAAAA==.Torniak:BAAANQAECgIJAwAAAA==.Torpor:BAAANQADCggIDQAAAA==.',
Tr='Traplock:BAAANQADCgQIBAABNQAECgYIDQADAAAAAA==.Trapple:BAAANQADCggICAABNQAECgUIDQADAAAAAA==.Tricia:BAAANQABCgEIAQAAAA==.Trillian:BAAANQADCggICAAAAA==.Trixia:BAABNQAECoEaAAIZAAkKXhT4DACMAgAZAAkKXhT4DACMAgAAAA==.Troudeseve:BAAANQADCgcIDQAAAA==.',
Tu='Tusenpai:BAAANQAECgIIAgAAAA==.',
Tw='Twiggyy:BAABNQAECoEVAAIMAAgKVCM5GQAgAwAMAAgKVCM5GQAgAwAAAA==.',
Ty='Tyburr:BAAANQAECggJBwAAAA==.',
Tz='Tzye:BAAANQADCgQIBQAAAA==.',
['Tâ']='Tângo:BAAANQAECgYICgAAAA==.',
Uj='Ujellypalz:BAAANQAECgIIAgAAAA==.Ujio:BAAANQADCgYIBgABNQAECgYJCgADAAAAAA==.',
Um='Umbráe:BAABNQAECoEhAAINAAkKoR0ZEwDLAgANAAkKoR0ZEwDLAgAAAA==.Umoonar:BAAANQADCgYICwAAAA==.',
Un='Unctekay:BAAANQABCgIJAwAAAA==.',
Ur='Ursainsanis:BAAANQAECgUJDAAAAA==.Urukhaí:BAAANQAECgEJAQAAAA==.',
Va='Vainless:BAAANQADCgIIAgAAAA==.Valhalla:BAAANQAECgUICgAAAA==.Vallynn:BAAANQADCgQIBAAAAA==.Vandle:BAABNQAECoEcAAMFAAgKShUQLQBtAQAPAAYKlRDaHQCiAQAFAAUKaBYQLQBtAQAAAA==.Vanoranda:BAAANQADCgIIAgABNQAECgYICwADAAAAAA==.Variena:BAAANQADCgcIBgAAAA==.Varikk:BAAANQAECgUJBQAAAA==.Varmage:BAAANQADCgYICwABNQAECgUJBQADAAAAAA==.Varmmy:BAAANQAECgQIBAABNQAECgUJBQADAAAAAA==.Varrair:BAAANQAECgEJAQABNQAECgUJBQADAAAAAA==.Vashezzo:BAACNQAFFIEMAAILAAcKsRLfAABwAgALAAcKsRLfAABwAgA1AAQKgSEAAgsACQpKIyoEAI0DAAsACQpKIyoEAI0DAAAA.',
Ve='Velein:BAAANQADCgYJCQAAAA==.Vellyssa:BAAANQAECgYJEAAAAA==.Verdolaga:BAAANQADCgYIBgAAAA==.Vexys:BAAANQADCgUIBQAAAA==.Veyllor:BAAANQAECgQIBQAAAA==.',
Vi='Villainous:BAAANQAECgcIEgAAAA==.Vindorian:BAAANQADCggICAAAAA==.Vitreshilla:BAAANQAECgMIBAABNQAECgYJEQADAAAAAA==.Vixenz:BAAANQAECgQJBgAAAA==.',
Vo='Volteer:BAABNQAECoEhAAIaAAkK+RjSCACrAgAaAAkK+RjSCACrAgAAAA==.Voxian:BAAANQADCgYICwAAAA==.',
Vr='Vriest:BAAANQAECgUJBQAAAA==.',
Vy='Vyecodin:BAAANQADCgYIBgAAAA==.Vyr:BAECNQAFFIEJAAIOAAQKvRPdBABWAQAOAAQKvRPdBABWAQA1AAQKgSUAAg4ACQq0IqMDAIoDAA4ACQq0IqMDAIoDAAAA.',
['Vä']='Väryn:BAAANQAECgcIDwAAAA==.',
Wa='Wannabrownie:BAAANQADCgUIAwAAAA==.Wardrian:BAAANQAECgQIBgAAAA==.Warriorzors:BAAANQADCgUIBQAAAA==.Wavyfist:BAAANQADCgQIBAABNQAFFAIJAwADAAAAAA==.Way:BAAANQAECgUJCgAAAA==.Wayshort:BAAANQADCggIDgABNQAECgUIDQADAAAAAA==.Waystrong:BAAANQAECgQIBAABNQAECgUIDQADAAAAAA==.',
We='Wellith:BAABNQAECoEbAAIEAAkKzh15FgDNAgAEAAkKzh15FgDNAgAAAA==.Westìn:BAAANQADCgYIBwAAAA==.',
Wi='Wikdtwstr:BAAANQAECggIEQAAAA==.Wildcard:BAAANQAECgQIBwAAAA==.Wilder:BAAANQAECgYIDAAAAA==.',
Wo='Wolfir:BAAANQAECgMJAwAAAA==.',
Wt='Wtfchickenz:BAAANQAECgYIDgAAAA==.',
Wu='Wuntch:BAAANQADCgIIAgABNQADCgMIAwADAAAAAA==.',
['Wã']='Wãngs:BAAANQAECgQJDAABNQAECgUIBgADAAAAAA==.',
Xa='Xaev:BAAANQAECgUICgAAAA==.Xarathiel:BAAANQAECgQIBAABNQAECgYIEAADAAAAAA==.',
Xe='Xecution:BAABNQAECoEVAAMlAAcKKxEYEwBaAQAlAAYKFRIYEwBaAQAMAAEKrQu89wA4AAAAAA==.Xenthor:BAAANQADCgYJBgAAAA==.Xeseparg:BAEANQAECggICgABNQAECggICAADAAAAAA==.Xevorian:BAAANQAECgUICgAAAA==.',
Xi='Xiexieping:BAABNQAFFIELAAIUAAYK8yAvAAByAgAUAAYK8yAvAAByAgAAAA==.',
Xy='Xyris:BAAANQADCgUIBQABNQAECgUICgADAAAAAA==.',
Ye='Yedranna:BAAANQAECgEIAQAAAA==.',
Yo='Yoloswagcrew:BAABNQAECoEbAAIHAAgKJhaDRQA9AgAHAAgKJhaDRQA9AgAAAA==.Yooksham:BAAANQAFFAIJAgAAAA==.',
Ys='Yslena:BAAANQABCgYJDwAAAA==.Yssa:BAAANQADCggIFQABNQAECgUIDQADAAAAAA==.',
Yu='Yuebing:BAABNQAECoEhAAICAAkKLBTUIQBeAgACAAkKLBTUIQBeAgAAAA==.Yumin:BAAANQADCgUIBQAAAA==.Yurmagesty:BAAANQAECgQICgAAAA==.',
['Yà']='Yàkana:BAAANQAECgEIAQAAAA==.',
Za='Zaddia:BAAANQADCgQIAQABNQAECgUICAADAAAAAA==.Zaeta:BAAANQAECgQICgAAAA==.Zaetini:BAAANQAECgEJAQABNQAECgQICgADAAAAAA==.Zamforia:BAAANQAECgYIDAAAAA==.Zandadead:BAAANQADCgQIBAABNQAECgQIBwADAAAAAA==.Zarellia:BAAANQAECgQIBwAAAA==.',
Ze='Zeeleez:BAAANQADCgYIBgAAAA==.Zephyrr:BAAANQADCggIFgABNQAECgUICgADAAAAAA==.Zerathrot:BAAANQADCgMIAwAAAA==.Zevaran:BAAANQADCgIIAgABNQAFFAUICQAGAHEaAA==.Zexeria:BAAANQAECgYICwABNQAECgYJEgADAAAAAA==.',
Zi='Zingara:BAAANQADCgEIAQAAAA==.',
Zo='Zootz:BAAANQADCgYICAAAAA==.Zorororonoa:BAAANQAECggIBQAAAA==.Zorrghen:BAAANQADCgYIEQABNQAECgYJEgADAAAAAA==.Zounap:BAAANQAECgUIDQAAAA==.Zoyaa:BAAANQAECgUJCAAAAA==.',
Zu='Zultra:BAAANQADCgcICAAAAA==.',
['Zë']='Zëd:BAAANQAECgEIAQAAAA==.',
['Ïs']='Ïshtãr:BAAANQAECgcIDwAAAA==.',
['Ða']='Ðash:BAAANQABCgQIAgAAAA==.',
['Üt']='Üthér:BAAANQAECgYJEQAAAA==.',
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
