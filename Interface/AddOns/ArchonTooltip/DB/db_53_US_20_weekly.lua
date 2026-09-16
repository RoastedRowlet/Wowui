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

local lookup = {'Shaman-Elemental','Rogue-Assassination','Unknown-Unknown','Mage-Arcane','Mage-Frost','Priest-Holy','Priest-Shadow','DemonHunter-Vengeance','DeathKnight-Unholy','DemonHunter-Devourer','Shaman-Enhancement','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Restoration','Warlock-Demonology','Evoker-Preservation','Evoker-Devastation','Paladin-Protection','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Havoc','Druid-Balance','Evoker-Augmentation','Warlock-Destruction','Paladin-Holy','Warrior-Arms','Rogue-Subtlety','DeathKnight-Blood','Priest-Discipline','Druid-Restoration','Warlock-Affliction','Druid-Feral','Monk-Mistweaver',}
local provider = {region='US',realm='Arthas',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abacas:BAABNQAECoEeAAIBAAkJViJYBQCTAwABAAkJViJYBQCTAwAAAA==.Abraanu:BAAANQAECgcIEQAAAA==.Abrohms:BAAANQAECgQIBwAAAA==.',
Ae='Aeily:BAAANQADCggIFAAAAA==.Aethaeist:BAAANQAECgIIAQAAAA==.',
Ag='Agiel:BAAANQADCgYIBwAAAA==.',
Ai='Aiger:BAAANQADCgUIBQAAAA==.Ais:BAAANQAECgcIEwAAAA==.Aitsu:BAABNQAECoEeAAICAAkJDyPuAQCIAwACAAkJDyPuAQCIAwAAAA==.Aivy:BAAANQAECgYIDwAAAA==.',
Ak='Akkula:BAAANQADCgUIDAAAAA==.Akutagawa:BAAANQADCgcIBwABNQAFFAMIAwADAAAAAA==.',
Al='Alexdare:BAAANQAECgUIEAAAAA==.Alfadelle:BAAANQAECgYICwABNQAECgkJFwAEADUiAA==.Alicarrdd:BAAANQAECgQIBgAAAA==.Aling:BAAANQADCgcIBwABNQAECgUICAADAAAAAA==.Allbeefpatty:BAAANQAECgQIBwAAAA==.Almostbald:BAACNQAFFIEFAAIEAAMJGB28CwAlAQAEAAMJGB28CwAlAQA1AAQKgR8AAwQACQnMIXgZADUDAAQACQnMIXgZADUDAAUAAQm8GzUgAE8AAAAA.Alneeshi:BAAANQAECgcIEQAAAA==.Alybella:BAAANQADCggIFAAAAA==.',
Am='Amoriandis:BAAANQADCgMIAwABNQADCggIIQADAAAAAA==.',
An='Ancstrlbower:BAAANQADCgcIEwAAAA==.Anetra:BAAANQADCgYICQAAAA==.Angharad:BAAANQADCgQIBAABNQAECgUIEgADAAAAAA==.Anot:BAAANQAECgcIDQAAAA==.Anothai:BAAANQADCgYICQAAAA==.Anton:BAAANQADCggIDgABNQAECgUICAADAAAAAA==.Anutterone:BAAANQAECgQIBAAAAA==.',
Ap='Apsaroke:BAAANQADCgYICwAAAA==.',
Aq='Aqi:BAAANQAECgcIDAAAAA==.',
Ar='Aralle:BAAANQAECgQIBAAAAA==.Aranea:BAAANQAECgIIAgAAAA==.Arclaw:BAAANQADCgEIAQAAAA==.Arin:BAAANQAECgUICgABNQAECgQIBAADAAAAAA==.Arkadu:BAAANQADCgEIAQAAAA==.Arkys:BAAANQADCgUIBQAAAA==.Arman:BAAANQADCgYIBgAAAA==.Armistice:BAAANQAECgEIAQAAAA==.Arrowyn:BAAANQAECgQIBAAAAA==.Arröwyn:BAAANQABCgIIAgAAAA==.',
As='Ashenis:BAAANQABCggICAAAAA==.Asphalt:BAAANQAECgUICAAAAA==.Astrà:BAAANQADCgEIAQAAAA==.',
At='Attidk:BAAANQAECgYIDwAAAA==.',
Au='Augful:BAAANQAECgYIEQAAAA==.Auspicious:BAABNQAECoEdAAMGAAkJmBeAGgByAgAGAAkJmBeAGgByAgAHAAYJWhaYGwCyAQAAAA==.Autýmn:BAAANQADCgUIBQABNQAECgUICwADAAAAAA==.',
Av='Avadin:BAAANQAFFAEIAQABNQAECgcIEwADAAAAAA==.Avadinde:BAAANQAECgcIEwAAAA==.Avadingue:BAAANQADCgYIBgABNQAECgcIEwADAAAAAA==.Avadragon:BAAANQAECgEIAgABNQAECgcIEwADAAAAAA==.Aversa:BAAANQADCgEIAQABNQAECgQICQADAAAAAA==.',
Ay='Aylla:BAAANQAECgMIBQAAAA==.Ayrios:BAAANQADCgEIAQABNQAECgYIEAADAAAAAA==.Ayrious:BAAANQAECgcIEQAAAA==.',
['Aé']='Aéthric:BAAANQADCgUICAAAAA==.',
Ba='Backather:BAAANQADCgcIDQAAAA==.Backshocks:BAAANQADCgQIBAAAAA==.Bahalanagang:BAAANQADCggIBAAAAA==.Bahrasmyou:BAAANQADCgYIBgAAAA==.Bakkoutou:BAABNQAECoEeAAIIAAkJGiK2AAB8AwAIAAkJGiK2AAB8AwAAAA==.Baldelomar:BAAANQADCgEIAQAAAA==.Baltic:BAAANQAECgEIAQABNQAECgYIDgADAAAAAA==.Bambäm:BAAANQADCgYIBgABNQAECgQIBAADAAAAAA==.Bangers:BAAANQAECgMIBAAAAA==.Basix:BAAANQADCgUICgAAAA==.Bastock:BAAANQAECgQIBAAAAA==.',
Be='Beanzmachine:BAAANQAECgEIAQAAAA==.Bearstout:BAAANQADCggIFAAAAA==.Beeans:BAAANQADCgEIAQAAAA==.Beestmaster:BAAANQAECgcIEAAAAA==.Belavik:BAABNQAECoEYAAIJAAkJkxf6EwCuAgAJAAkJkxf6EwCuAgAAAA==.Beowelf:BAABNQAECoEdAAIKAAkJrxl9CwDiAgAKAAkJrxl9CwDiAgAAAA==.Beowulfsson:BAAANQAECgQIBgAAAA==.Bertabeef:BAAANQADCggIHQAAAA==.Betrayar:BAAANQADCgYIBgAAAA==.Bezzert:BAAANQADCgYIBgAAAA==.',
Bh='Bheap:BAAANQAECgcIDwAAAA==.Bheapbheap:BAAANQADCggIFwAAAA==.',
Bi='Bigchungo:BAAANQADCgUICAAAAA==.Bigcook:BAAANQADCgYIBgAAAA==.Bigpaindk:BAAANQAECgIIAwAAAA==.Bigpaindru:BAAANQADCggIDgAAAA==.Bigpainpal:BAAANQADCgMIAwAAAA==.Bigshloppy:BAAANQAECgQIBgAAAA==.Billysblade:BAAANQAECgYIDwAAAA==.',
Bk='Bkers:BAAANQADCgYIBgAAAA==.',
Bl='Blebipty:BAABNQAECoEYAAILAAkJzhJmBgCqAgALAAkJzhJmBgCqAgAAAA==.Blessyoho:BAAANQADCgYICwAAAA==.Blitzbuster:BAAANQAECgMIBQAAAA==.Blitzy:BAAANQADCgYIBgABNQAECgMIBQADAAAAAA==.Blladee:BAAANQAECgQIBwAAAA==.Bloodjesser:BAAANQAECgEIAQAAAA==.Bloodrender:BAAANQABCgYICAAAAA==.Bluehorn:BAAANQADCgYIBgAAAA==.Bluekoolaid:BAAANQADCgQIBAAAAA==.Blumpkings:BAAANQADCgQIBwAAAA==.',
Bo='Boingus:BAAANQADCgYIBgAAAA==.Bornshadow:BAAANQABCgQIBAAAAA==.',
Br='Brockly:BAAANQAECgYIEAAAAA==.Brolly:BAAANQAECgEIAQAAAA==.Brooski:BAAANQADCgQIBwAAAA==.Brotorious:BAAANQAECgcIDQAAAA==.',
Bu='Bubllz:BAAANQADCgYIBgAAAA==.Budgetroll:BAAANQADCgQIBAAAAA==.Bulluptuous:BAAANQAECgYIEQAAAA==.Bun:BAAANQABCgUIBAAAAA==.Burkmon:BAAANQAECgIIAwAAAA==.Burret:BAAANQAECgQIBAAAAA==.Butseven:BAAANQAECgMIAwAAAA==.Butterbubble:BAAANQAECgQIBQAAAA==.',
['Bó']='Bótat:BAAANQAECgYIDwAAAA==.',
Ca='Cadiron:BAAANQADCgUICwAAAA==.Caedance:BAAANQADCgYICgABNQAECgUIEgADAAAAAA==.Caldergrim:BAAANQADCgQIBAAAAA==.Calumen:BAAANQAECgUICgAAAA==.Calypzo:BAAANQAECgQIBwAAAA==.Carnages:BAAANQADCgQIBAABNQAECgMIBAADAAAAAA==.Caserius:BAAANQADCggIDAAAAA==.Casusbelli:BAAANQABCgIIAgAAAA==.Catta:BAAANQADCgMIBAABNQADCgYIBgADAAAAAA==.Catynca:BAAANQAECgQICAABNQAECgUIEgADAAAAAA==.',
Ce='Celieril:BAAANQADCggIGAAAAA==.',
Ch='Changqing:BAAANQADCgUIBQABNQAECgUIDAADAAAAAA==.Chaparrín:BAAANQADCggICQAAAA==.Checoburger:BAAANQAECgIIAgAAAA==.Cheiel:BAAANQAECgcIDgAAAA==.Chendruid:BAAANQADCgQIBAAAAA==.Chillheart:BAAANQADCgYIBgAAAA==.Chitoes:BAAANQADCgcIBwAAAA==.Chylan:BAAANQADCgUIBQAAAA==.',
Ci='Cincolobos:BAAANQAECgQIBwAAAA==.Cinnaminsaph:BAAANQAECgIIAgAAAA==.',
Cl='Cloraform:BAAANQADCgUICQAAAA==.',
Co='Conduit:BAAANQAECgEIAQAAAA==.Conri:BAAANQADCggIGwAAAA==.Coradk:BAAANQADCggICAABNQAFFAQIBwAMAOQVAA==.Cowmooz:BAAANQAECgQIBAAAAA==.',
Cr='Critaurus:BAABNQAECoEXAAIMAAcJoBEXVgCgAQAMAAcJoBEXVgCgAQAAAA==.Cronics:BAAANQADCgUIBQABNQAECgQIBAADAAAAAA==.Cronstione:BAAANQAECgcIEAAAAA==.Crushinater:BAAANQAECgUIDAAAAA==.',
Ct='Ctrlaltdel:BAAANQADCggICgAAAA==.',
Cz='Czrp:BAAANQAECgMIBAAAAA==.',
['Cô']='Côrack:BAACNQAFFIEHAAIMAAQJ5BXoAgBdAQAMAAQJ5BXoAgBdAQA1AAQKgSEAAgwACQm8IaEKAFoDAAwACQm8IaEKAFoDAAAA.',
Da='Dad:BAAANQAECgcIBwAAAA==.Daddytank:BAAANQADCgUIBQAAAA==.Daedríc:BAAANQAECgYIBgAAAA==.Daeemon:BAAANQADCgcIBwABNQAECgcIEQADAAAAAA==.Dagaa:BAAANQADCgYIEQAAAA==.Dagdeath:BAAANQAECgQICAAAAA==.Dagmarre:BAAANQADCgcIBwAAAA==.Dagothseth:BAAANQAECgEIAgAAAA==.Dagothsett:BAAANQADCgQIBwAAAA==.Daktz:BAAANQADCgYIBgAAAA==.Danelle:BAAANQADCggIEgAAAA==.Dankest:BAAANQAECgEIAQAAAA==.Darfòrce:BAAANQAECgIIAwABNQAFFAYIDQANAHMbAA==.Darison:BAAANQAECgYIDAAAAA==.Darkobey:BAAANQADCgEIAQAAAA==.Darreck:BAABNQAECoEWAAMNAAkJ8CF0CwDUAgANAAgJiSF0CwDUAgAOAAQJwyKkbwBNAQAAAA==.Darthmommy:BAAANQADCgYICgAAAA==.Darvus:BAAANQADCgEIAQAAAA==.Darwïn:BAAANQAECgEIAQAAAA==.Datonax:BAAANQAECgYIEAAAAA==.Davinity:BAAANQAECgQICQAAAA==.Dayfire:BAAANQAECgMIAwAAAA==.',
Dd='Ddrizztt:BAAANQAECgQIBwAAAA==.',
De='Deadskill:BAABNQAECoEbAAIJAAcJ7xfKJwD7AQAJAAcJ7xfKJwD7AQAAAA==.Deathburrito:BAAANQADCgIIAgAAAA==.Deathloky:BAAANQAECgEIAgAAAA==.Decca:BAAANQAECgQIBwAAAA==.Deeroy:BAAANQAECgUIDAAAAA==.Dela:BAAANQAECgMIBQAAAA==.Delandèr:BAAANQADCgYICAABNQAECgMIBQADAAAAAA==.Delerino:BAAANQADCgQIBAABNQAECgMIBQADAAAAAA==.Demincy:BAAANQAECgUICAAAAA==.Demonbruff:BAAANQAECgYICQAAAA==.Demonflex:BAAANQAECgQIBwAAAA==.Deoxys:BAAANQAECgMIAwAAAA==.Deset:BAAANQAECgUICQAAAA==.Desprainer:BAAANQAECgQIBAAAAA==.Desse:BAAANQADCgUICQAAAA==.Dew:BAAANQABCgYICAAAAA==.Deydoria:BAAANQADCgIIAgAAAA==.',
Dg='Dgt:BAAANQAECgIIAgAAAA==.',
Dh='Dhalthron:BAAANQADCggICAAAAA==.',
Di='Dingùs:BAAANQAECgYICAAAAA==.Dirkadeux:BAAANQAECgYIDwAAAA==.Dirtyúndys:BAAANQAECgQIBQAAAA==.Discoliquid:BAAANQABCgEIAQAAAA==.Divinatrix:BAAANQADCgMIAwAAAA==.Divinecakes:BAAANQAECgUIDQAAAA==.Divineskillz:BAAANQAECgEIAQAAAA==.',
Do='Docmanhattan:BAAANQAECgMIBAAAAA==.Doesnttank:BAAANQADCgQICgAAAA==.Dogmatrix:BAAANQAECgcIDwAAAA==.Donsapo:BAAANQADCgYIBgABNQAECgMIBAADAAAAAA==.Doomshock:BAAANQADCgEIAQAAAA==.Dotcom:BAAANQAECgEIAQAAAA==.Doughmaker:BAABNQAECoEeAAIGAAkJGxWlJgAgAgAGAAkJGxWlJgAgAgAAAA==.Douru:BAAANQABCgMIAwAAAA==.',
Dr='Dracpo:BAAANQAECgEIAQAAAA==.Dragonskillz:BAAANQADCgUIBQAAAA==.Dreambender:BAAANQADCggICAAAAA==.Dreamdecoom:BAAANQAECgEIAQAAAA==.Dreamdekoop:BAAANQAFFAEIAgAAAA==.Drededknight:BAAANQADCgcIBwAAAA==.Dreignos:BAAANQAECgYIDwAAAA==.Drillbit:BAAANQADCgEIAQAAAA==.Drizztski:BAAANQADCgUIBgABNQAECgQIBwADAAAAAA==.Drocalla:BAAANQAECgEIAQAAAA==.Drozghul:BAAANQADCgUIDQAAAA==.',
Du='Durnhelm:BAAANQADCgYIBgABNQAECgcIDwADAAAAAA==.Durto:BAAANQADCggICAABNQADCgMIAwADAAAAAA==.Dushawee:BAABNQAECoEgAAMPAAkJvxzmFwCXAgAPAAgJjhvmFwCXAgABAAUJBRR1XwAwAQAAAA==.',
['Dá']='Dárk:BAAANQADCgUIBQAAAA==.',
['Dä']='Dävös:BAAANQAECgMIBQAAAA==.',
Ea='Earthwitch:BAAANQADCgcIDQABNQAECggIHAAGAPgTAA==.',
Eg='Egg:BAAANQAECggIDwABNQAECgkJFwAQALckAA==.',
Ek='Ekalbs:BAAANQAECgYIDAAAAA==.',
El='Eliniia:BAAANQAECgEIAQAAAA==.Ellayri:BAAANQAECgcIEQAAAA==.Elldis:BAAANQAECgQICAAAAA==.Elleanor:BAAANQAECgMIBgAAAA==.Eltanin:BAAANQADCggIFAAAAA==.',
En='Endoblades:BAAANQADCgYICQABNQAECgUIDQADAAAAAA==.Endocrits:BAAANQADCggIDgABNQAECgUIDQADAAAAAA==.Endodaddy:BAAANQAECgMIBQABNQAECgUIDQADAAAAAA==.Endostars:BAAANQAECgUIDQAAAA==.Energykyouka:BAAANQAECgQIBQABNQAECgQIBQADAAAAAA==.Enferi:BAAANQAECgUIDQAAAA==.Enforcers:BAAANQADCggIDgAAAA==.',
Eq='Equinoxdk:BAAANQAECgcICwAAAA==.',
Es='Essent:BAAANQAECgQIBwABNQAECgcICwADAAAAAA==.Esthera:BAAANQADCgYIBgAAAA==.',
Ev='Evochiken:BAEBNQAECoEdAAMRAAkJoRmXBgDuAgARAAkJoRmXBgDuAgASAAQJcwtzHADbAAAAAA==.Evokemode:BAAANQAECgcIEwAAAA==.',
Ex='Exorcism:BAAANQAECgQIBgAAAA==.Exotic:BAAANQAECggIEAAAAA==.Explosivoh:BAAANQAECgMIBQAAAA==.Exumm:BAAANQAECgQICAAAAA==.',
Ey='Eyeforagge:BAAANQADCgMIAwAAAA==.',
Fa='Fakelashes:BAAANQABCgQIBQAAAA==.Farstriderr:BAAANQADCgcIKQAAAA==.Fataleclipse:BAAANQAECgQIBgAAAA==.Fatmir:BAAANQAECgEIAQAAAA==.',
Fe='Feigndps:BAAANQADCgQIBAABNQAECgEIAQADAAAAAA==.Feku:BAAANQADCgMIAwAAAA==.Feldrak:BAAANQAECggIEwAAAA==.Feldriu:BAAANQADCgYICQAAAA==.',
Fi='Figai:BAAANQAECgQIBwAAAA==.Finebyme:BAAANQAECgEIAQAAAA==.Firebear:BAAANQAECgYIDAAAAA==.',
Fl='Flanknspank:BAACNQAFFIEIAAITAAQJ5RaOAQBWAQATAAQJ5RaOAQBWAQA1AAQKgR8AAhMACQmMIpcBAI8DABMACQmMIpcBAI8DAAAA.',
Fo='Formulated:BAAANQABCgQIBAAAAA==.Fotmreroller:BAAANQAECgQICAAAAA==.Fourtwenty:BAABNQAECoEVAAMUAAcJKg+hDwBEAQAUAAYJUwyhDwBEAQAVAAMJOw81KgDJAAAAAA==.Foxyladeh:BAAANQADCgMIAwAAAA==.Foxylady:BAAANQABCgMIBAAAAA==.',
Fr='Frostytongue:BAAANQADCgUIBgAAAA==.Frôstíe:BAAANQAECgEIAQAAAA==.',
Ga='Galadriella:BAAANQAECgEIAgAAAA==.Garglius:BAAANQAECggIAwAAAA==.',
Ge='Gekidos:BAAANQADCgYIBgAAAA==.Gekiretsu:BAAANQAECgEIAQAAAA==.Geodon:BAAANQADCggIEgAAAA==.Geoffry:BAAANQAECgYIDAAAAA==.Gerbil:BAAANQAECgUIDAAAAA==.',
Gh='Ghostmonkey:BAAANQADCgEIAQAAAA==.',
Gi='Giaoman:BAAANQAECgcIDgAAAA==.Gilgalock:BAAANQADCgIIAgABNQAECgcIEwADAAAAAA==.Gilwood:BAABNQAECoEeAAMNAAkJ+Bv0EwBJAgANAAgJQBr0EwBJAgAOAAQJPh2jawBZAQAAAA==.Gingyr:BAAANQAECgUICwAAAA==.Girthywand:BAAANQAECgQICgABNQAECgYICgADAAAAAA==.',
Gl='Glacialgimp:BAAANQAECgQIBQAAAA==.Gloinn:BAABNQAECoEeAAMEAAkJvxzTLQDaAgAEAAkJvxzTLQDaAgAFAAEJOCBKIwBEAAAAAA==.',
Gn='Gnomelyfans:BAAANQAECgcIEQAAAA==.Gnomorerage:BAAANQABCgQIBAABNQAECgcIEQADAAAAAA==.',
Go='Golfire:BAABNQAECoElAAMKAAkJuCEfCAAgAwAKAAkJVR4fCAAgAwAWAAYJ1h/EFABGAgAAAA==.Gooberlol:BAAANQAECgcICAABNQAECggICAADAAAAAA==.Gorbashe:BAAANQADCgEIAQABNQAECgcIFwAMAKARAA==.Gorbie:BAABNQAECoEgAAIKAAkJmRjmDgCrAgAKAAkJmRjmDgCrAgAAAA==.Gorestus:BAAANQAECgYIDAAAAA==.Gorlockholms:BAAANQAECgcIDgAAAA==.Gorthex:BAAANQAECgQIBAAAAA==.Gozziz:BAAANQAECgIIAgAAAA==.',
Gr='Graitlok:BAAANQAECgYIDgAAAA==.Grawd:BAAANQAECgQIBwAAAA==.Graysòn:BAAANQAECgMIAwAAAA==.Grilledchis:BAAANQAECgcIDQAAAA==.Grimdwagon:BAAANQAECgEIAQAAAA==.Griseldas:BAAANQAECgMIAwABNQAECgUIDAADAAAAAA==.Griswald:BAAANQAECgUIBgAAAA==.Grumpygranpa:BAAANQAECgQICAAAAA==.Grypser:BAAANQADCgQIBAAAAA==.',
Gu='Guesswholoky:BAAANQADCgYIDwAAAA==.Guldán:BAAANQADCgUIBQAAAA==.Gulmatt:BAAANQAECgQICgAAAA==.Gunslug:BAAANQADCgIIAgAAAA==.',
['Gí']='Gílgamore:BAAANQAECgcIEwAAAA==.',
Ha='Haguda:BAAANQAECgEIAQAAAA==.Hakaska:BAAANQAECgYIDwAAAA==.Hakkinen:BAAANQAECgcICAAAAA==.Hanswolo:BAAANQAECgEIAgAAAA==.Haramboned:BAAANQADCggIDgAAAA==.Harharof:BAAANQADCgIIAgAAAA==.Hatebreeder:BAAANQADCgYIBgABNQAECgIIAgADAAAAAA==.Hatise:BAAANQADCgQIBAAAAA==.Hawktuàh:BAAANQADCgUIBgAAAA==.',
He='Heliotoro:BAAANQADCgUICgAAAA==.Hellebore:BAAANQADCgcIBwAAAA==.',
Hi='Hierba:BAAANQAECgcIBwAAAA==.Highlock:BAAANQAECgYIBgAAAA==.Hilde:BAAANQADCgQIBAAAAA==.',
Ho='Holigoat:BAAANQADCgMIBAAAAA==.Holysam:BAAANQADCgUIBQAAAA==.Holyshhmon:BAAANQAECgEIAQAAAA==.Holystriker:BAAANQADCgYIBwAAAA==.Holywitch:BAABNQAECoEcAAIGAAgJ+BNuLQD2AQAGAAgJ+BNuLQD2AQAAAA==.Honnycorns:BAAANQAECgYICQAAAA==.Hoojah:BAAANQADCgIIAgAAAA==.Hormandacek:BAAANQAECgUIBQAAAA==.Hornguy:BAAANQAECgQIBQAAAA==.Houndoom:BAAANQAECggIEwAAAA==.',
Hr='Hrulot:BAAANQADCgYIBgAAAA==.',
Hs='Hsr:BAABNQAECoEXAAIMAAgJMxhALwBNAgAMAAgJMxhALwBNAgAAAA==.',
Hu='Huataurga:BAAANQAECgUIDwAAAA==.Huff:BAAANQAFFAEIAQABNQAECgkJHAAPAPwjAA==.Hugetoke:BAAANQADCgcIBwAAAA==.Huktwo:BAAANQAECgMIBQAAAA==.Hunternin:BAAANQAECgIIAgABNQAECgMIBgADAAAAAA==.Huron:BAAANQAECgQICAAAAA==.Huskarl:BAAANQADCggICAAAAA==.Hussypriest:BAAANQAECgQIBQAAAA==.',
Hy='Hyzerflip:BAAANQAECgIIAgAAAA==.',
['Hà']='Hàchi:BAACNQAFFIEFAAIXAAMJiyL1BQA5AQAXAAMJiyL1BQA5AQA1AAQKgR8AAhcACQnlJHUCALwDABcACQnlJHUCALwDAAAA.',
Ib='Ibsgodx:BAAANQADCgQIBAAAAA==.',
Id='Idiotfurry:BAAANQAECgYIDwAAAA==.',
Ig='Igotatiara:BAAANQADCgYICQAAAA==.',
Il='Illidanheart:BAAANQABCgIIAgAAAA==.Ilmagnifico:BAAANQAECgcIDgAAAA==.',
Im='Imolegreg:BAAANQAECgcICQAAAA==.Imperatris:BAAANQAECgEIAQAAAA==.Imvaernarhro:BAAANQADCgMIAwAAAA==.',
In='Inkubator:BAAANQAFFAEIAgAAAQ==.Inkyy:BAAANQADCgYIBgAAAA==.',
Ir='Irøns:BAAANQADCgYIDgAAAA==.',
It='Itemlevel:BAAANQADCgUIBgAAAA==.',
Iy='Iyamwarlock:BAAANQADCgYIBgAAAA==.Iyanden:BAAANQAECgIIAgAAAA==.',
Ja='Jabrogoz:BAAANQADCgMIAQAAAA==.Jalahl:BAAANQADCgcIBwABNQAFFAMIBQAYAAEgAA==.Jastinos:BAAANQAECgQIBAAAAA==.',
Je='Jentrazka:BAAANQADCgIIAgABNQAECgMIBQADAAAAAA==.Jezahbel:BAAANQAECgMIAwAAAA==.',
Ji='Jitteryjoe:BAAANQAECgQICQAAAA==.',
Jo='Jokich:BAAANQABCggIDgAAAA==.Joseko:BAAANQAECgYIDAAAAA==.',
Ju='Juggsr:BAAANQAECgYIDAAAAA==.Justbower:BAAANQADCgEIAQAAAA==.',
Ka='Kaeyle:BAAANQADCgcIDgABNQAECgkJHwALANsdAA==.Kamico:BAAANQADCgUICQAAAA==.Kansoika:BAAANQADCgcIBwAAAA==.Karakitana:BAAANQADCgYIBQABNQAECgYICgADAAAAAA==.Kasualtrash:BAAANQADCgQIBQAAAA==.Katfury:BAAANQAECgYICgAAAA==.Kattallina:BAAANQADCgcIBwAAAA==.Kattmini:BAABNQAECoEhAAMQAAkJ0R5oFwCpAgAQAAgJYR1oFwCpAgAZAAcJ/BR1DwDdAQAAAA==.Katto:BAAANQADCgYIBgAAAA==.',
Ke='Keffká:BAAANQADCggICgAAAA==.Kelebrimbor:BAAANQAECgEIAQAAAA==.Keyalidas:BAAANQADCgEIAQAAAA==.Keylime:BAAANQADCggIEAAAAA==.',
Kh='Khane:BAAANQADCggIDwAAAA==.Kharras:BAAANQADCggICgAAAA==.',
Ki='Killabattle:BAAANQADCgcIBwAAAA==.Kilyna:BAAANQAECgcIEQAAAA==.Kirbÿ:BAAANQAECgQIBQAAAA==.',
Ko='Kodeezy:BAAANQADCggICAABNQAECgkJIQAMABUdAA==.Kodita:BAABNQAECoEhAAIMAAkJFR2CDwAnAwAMAAkJFR2CDwAnAwAAAA==.',
Kr='Krakair:BAAANQAECgQIBQAAAA==.Krhon:BAAANQAECgQIBwAAAA==.Kryptic:BAAANQAECgQIBwAAAA==.',
Ky='Kylea:BAAANQAECgIIAwAAAA==.Kyntaro:BAAANQADCgcICQAAAA==.Kyouka:BAAANQADCgUIBQABNQAECgkJFQAQAIEaAA==.Kysira:BAAANQAECgQICQAAAA==.',
La='Lailai:BAAANQAECgUIDAABNQAECgYICAADAAAAAA==.Lalax:BAAANQABCgQIBAAAAA==.Lalechuga:BAAANQAECgUICgAAAA==.Lanerian:BAAANQADCggIIQAAAA==.',
Ld='Ldytncty:BAAANQADCgUIBQAAAA==.',
Le='Leadah:BAAANQADCgUIBQAAAA==.Ledge:BAAANQAECgEIAQABNQAECgIIAgADAAAAAA==.Ledgebear:BAAANQAECgIIAgAAAA==.Leerwandler:BAAANQAECgQICAAAAA==.Lehunt:BAABNQAECoEYAAINAAkJlRQ1DwCVAgANAAkJlRQ1DwCVAgAAAA==.Leiyong:BAAANQAECgEIAQAAAA==.Letmedoitpls:BAAANQABCgMIBQAAAA==.Levigosa:BAAANQADCgYIDAAAAA==.Lexadin:BAAANQABCgIIAgAAAA==.Leylanie:BAAANQAECggIBgAAAA==.',
Li='Liadarel:BAAANQADCgMIAwAAAA==.Liael:BAAANQADCgQIBAAAAA==.Lightlobster:BAAANQAECgQIBAABNQAECgkJHQALANAeAA==.Lilpuffz:BAAANQAECgUICQAAAA==.Lisaleri:BAAANQADCgYIBwAAAA==.Liteorheavy:BAAANQADCgIIAgAAAA==.Livewires:BAAANQADCgcICQABNQAECgUIBwADAAAAAA==.',
Ll='Llandshark:BAAANQAECgUICQAAAA==.Lleyla:BAAANQAECgUIEgAAAA==.',
Lo='Loavoltage:BAAANQADCgUIBQAAAA==.Lockjaw:BAAANQADCgQIBAABNQAECgIIAgADAAAAAA==.Lockyboi:BAAANQADCgUIBQABNQAECgUICQADAAAAAA==.Locomoko:BAAANQADCggICAAAAA==.Lohre:BAAANQADCgIIAgAAAA==.Lojik:BAAANQADCggIBQAAAA==.Long:BAAANQAECgQICgAAAA==.Lookimapanda:BAAANQADCgcICQAAAA==.Lorakmahktar:BAAANQAECgQIBAAAAA==.Lottie:BAAANQAECgYIBQAAAA==.',
Lu='Luarhea:BAAANQAECgQIBgAAAA==.Luccina:BAAANQAECgQICQAAAA==.Lucîd:BAAANQAECgQICAABNQAECgYIBgADAAAAAA==.Luminarie:BAABNQAECoEeAAIaAAkJIR+uBgBRAwAaAAkJIR+uBgBRAwAAAA==.Lunitari:BAABNQAECoEXAAIEAAkJNSLnDgBwAwAEAAkJNSLnDgBwAwAAAA==.Luvalot:BAAANQAECgIIAwAAAA==.',
Lx='Lxbeowulfxl:BAAANQADCgcICgAAAA==.',
Ly='Lyraiel:BAAANQAECgYIEgAAAA==.Lysaera:BAAANQAECgQIBAAAAA==.',
['Lü']='Lücíd:BAAANQADCggICAABNQAECgYIBgADAAAAAA==.',
Ma='Mackantosh:BAAANQAECgQIBAAAAA==.Mackpyre:BAAANQAECgMIAwABNQAECgQIBAADAAAAAA==.Madness:BAAANQABCggICQAAAA==.Magelha:BAAANQADCgYIBgAAAA==.Magmalash:BAAANQADCgEIAQAAAA==.Magoroxx:BAAANQAECgYICwAAAA==.Mahots:BAAANQAECgMIAwAAAA==.Maiyathicc:BAAANQAECgMIAwAAAA==.Makagalvan:BAABNQAECoEeAAIbAAkJCRcrKACnAgAbAAkJCRcrKACnAgAAAA==.Malakes:BAAANQAECggICAAAAA==.Malthael:BAABNQAECoEYAAIbAAkJ7iP1CgBzAwAbAAkJ7iP1CgBzAwABNQAFFAMIAwADAAAAAA==.Malzahar:BAAANQADCgcIBwAAAA==.Manamgmtllc:BAAANQADCgYIBgAAAA==.Mantu:BAAANQAECggIBwAAAA==.Maplepriest:BAAANQADCgYIBgAAAA==.Markyle:BAEANQADCgYIBgABNQAECgMIBQADAAAAAA==.Martien:BAAANQAECgMIBQAAAA==.Massteraria:BAAANQADCggIDwAAAA==.Masstercard:BAAANQAECggIEAAAAA==.Maxeras:BAAANQAECgEIAQAAAA==.Maximus:BAAANQAECgUICgAAAA==.Maya:BAAANQAFFAEIAQAAAA==.Mayoi:BAAANQADCgYIBgAAAA==.Mazo:BAABNQAECoEaAAMWAAkJsCNxAwCGAwAWAAkJsCNxAwCGAwAKAAQJDRezLwA0AQAAAA==.',
Mb='Mbuku:BAAANQADCgUIBQAAAA==.',
Mc='Mcroguez:BAABNQAECoEVAAMcAAgJ4BjsDgA/AgAcAAcJKxrsDgA/AgACAAQJORC+KQAWAQAAAA==.',
Me='Meeche:BAAANQAECgQIBQAAAA==.Menagerie:BAABNQAECoEVAAMQAAkJgRpUEQDUAgAQAAkJgRpUEQDUAgAZAAEJCBFNVgBCAAAAAA==.Metche:BAAANQAECgEIAQAAAA==.Mezzy:BAAANQADCgcIBwAAAA==.',
Mi='Mightythighs:BAAANQAECgYIDgAAAA==.Mihd:BAAANQAECgQIBwAAAA==.Miisch:BAAANQAECgQIBwAAAA==.Milkyy:BAAANQAECgYIDgAAAA==.Millamaxwell:BAAANQADCgcICwABNQAECgkJHgASAJAYAA==.Minimus:BAAANQAECgUICgAAAA==.Miraeth:BAAANQAECgEIAgAAAA==.Misknocker:BAAANQAECgMIAwAAAA==.',
Mo='Moistivall:BAAANQADCgUIBgAAAA==.Moisturize:BAAANQABCgUIBAAAAA==.Momô:BAAANQAECgIIAwABNQAECgMIBAADAAAAAA==.Monkred:BAAANQAECgUIBQAAAA==.Monte:BAAANQAECgUIBQAAAA==.Moobees:BAAANQAECgQICQAAAA==.Mooge:BAEANQADCgYICwABNQAECgMIBQADAAAAAA==.Mooiester:BAAANQADCgQIBAAAAA==.Moomanchuu:BAAANQADCgMIAwAAAA==.Moomins:BAAANQAECgMIBAABNQAECgkJFwAEADUiAA==.Mortuous:BAAANQAECgEIAgAAAA==.Mosthated:BAAANQAECgIIAgAAAA==.',
Ms='Mstrfreekill:BAAANQAECgYIDQAAAA==.',
Mu='Mubu:BAAANQAECgEIAQAAAA==.Mudpriest:BAAANQAECgYIDwAAAA==.Muffdiiva:BAAANQAECgQIBwAAAA==.Mulletman:BAAANQAECgUICwAAAA==.Musky:BAAANQAECgcIEQAAAA==.Muskydk:BAAANQADCgYIBgAAAA==.Muskydruid:BAAANQAECgcICQAAAA==.Muskyshnoze:BAAANQADCgQIBQAAAA==.',
My='Mystogån:BAAANQADCggIDwAAAA==.Mystrix:BAAANQAECgUICQAAAA==.Mytthdk:BAAANQADCgcIBwAAAA==.Myzary:BAAANQADCggIDgAAAA==.',
['Mè']='Mèggz:BAAANQADCgIIAwAAAA==.',
['Më']='Mërcy:BAAANQAECgEIAQAAAA==.',
['Mí']='Míthrandír:BAABNQAECoEiAAIEAAkJfB0HIAAVAwAEAAkJfB0HIAAVAwAAAA==.',
['Mô']='Mômo:BAAANQAECgMIBAAAAA==.',
['Mû']='Mûfâsâ:BAAANQADCggIDgAAAA==.',
Na='Nardhaa:BAAANQAECgYIDQAAAQ==.Narkiel:BAAANQADCgEIAQAAAA==.Narrius:BAAANQAECgYICQAAAA==.Nathzandalar:BAAANQADCgUIBQAAAA==.Natraps:BAAANQAECgMIBAAAAA==.',
Ne='Neartonoir:BAAANQABCgcICgAAAA==.Nesmage:BAAANQADCgMIAwAAAA==.Nesmie:BAAANQAECgYIDwAAAA==.',
Ni='Nijek:BAAANQAECgUICAAAAA==.Nimchip:BAABNQAECoE3AAIbAAkJMyGBEABDAwAbAAkJMyGBEABDAwAAAA==.',
Nl='Nlrvana:BAAANQADCgEIAQAAAA==.',
No='Nokkakkash:BAAANQADCggICAAAAA==.Notmyforte:BAAANQAECgQIBgAAAA==.',
Nu='Nudillos:BAAANQADCgcIBwAAAA==.Nudnarb:BAAANQADCgQIBAAAAA==.Nurflocks:BAAANQADCgYIBgAAAA==.',
Ny='Nyankobrq:BAAANQAECgQIBQAAAA==.Nyxtheabyss:BAAANQADCgQIBAAAAA==.',
['Ná']='Náthe:BAAANQAECgMIAwAAAA==.',
Oa='Oakzz:BAAANQAECgYIBgABNQAECgcIEQADAAAAAA==.',
Ob='Obalnhabdea:BAAANQADCggIFAAAAA==.Oblvn:BAAANQADCggIGAAAAA==.',
Oc='Ocêangrown:BAAANQADCggIBQAAAA==.',
Od='Odhran:BAAANQAECgcIBwAAAA==.',
Oh='Ohda:BAAANQAECgMIBAAAAA==.Ohgodbees:BAAANQAECgIIAwAAAA==.',
Oi='Oisn:BAAANQAECgIIAgABNQAECgcICwADAAAAAA==.',
On='Onepiece:BAAANQADCgYICQAAAA==.Onís:BAAANQAECgYIDAABNQAECgcICwADAAAAAA==.',
Op='Opspartan:BAAANQABCgYICQAAAA==.',
Or='Orastal:BAAANQADCgUIBgABNQAECgQIBwADAAAAAA==.Oravoker:BAAANQAECgQIBwAAAA==.Orcishz:BAAANQADCgQIBwAAAA==.Oreweyna:BAAANQABCgIIBAAAAA==.Orion:BAAANQADCgcIDAAAAA==.',
Os='Osawa:BAAANQADCgYICwABNQAECgUICwADAAAAAA==.Ostidevache:BAAANQADCgYICQAAAA==.',
Oy='Oyobi:BAAANQADCgEIAQAAAA==.',
Oz='Ozshock:BAAANQAECgUICwAAAA==.',
Pa='Paffdk:BAAANQAECgUIDQAAAA==.Paiyn:BAAANQADCgcIBwAAAA==.Palamix:BAAANQAECgIIAgABNQAECgMIBgADAAAAAA==.Palladone:BAAANQAECgQIBwAAAA==.Palthron:BAAANQAECgQICAAAAA==.Palychick:BAAANQAECgQIBgAAAA==.Pampersxl:BAAANQAECgYIDwAAAA==.Pandatheis:BAAANQADCgUIBQAAAA==.Pandatotem:BAAANQADCgYICgABNQAECgYICwADAAAAAA==.Pangoro:BAACNQAFFIEFAAIKAAMJ2BV3BAAOAQAKAAMJ2BV3BAAOAQA1AAQKgSAAAgoACQniIUcEAHIDAAoACQniIUcEAHIDAAAA.Paragondk:BAAANQAECgcICwAAAA==.Paragonlock:BAAANQAECgYIBwABNQAECgcICwADAAAAAA==.Paramedic:BAAANQAFFAMIAwAAAA==.Parser:BAAANQADCgMIAwAAAA==.',
Pe='Pelikanesis:BAAANQAECgMIBAAAAA==.Pelolindo:BAAANQADCggICAAAAA==.Penance:BAAANQAECgMIBAAAAA==.Pestus:BAAANQADCgYIEQAAAA==.Peteqc:BAAANQADCgUIBQAAAA==.Petshunt:BAAANQADCggIKwABNQADCggICQADAAAAAA==.',
Ph='Phageborn:BAABNQAECoEZAAIdAAgJyCMYCQAmAwAdAAgJyCMYCQAmAwAAAA==.Phiavel:BAAANQADCgYIDAAAAA==.Philmahuders:BAAANQADCgIIAgAAAA==.Phoop:BAAANQADCgcIDgAAAA==.',
Pi='Pik:BAAANQAECgQIBwAAAA==.Pillowpants:BAAANQAECgUIBwAAAA==.Pineappleish:BAAANQAECgcICgAAAA==.Pinkcross:BAAANQAECgMIBQABNQAFFAYIAQADAAAAAA==.Pinkfuzi:BAAANQADCgcIGAAAAA==.',
Po='Pocketlockit:BAAANQAECgQIBAABNQAECgcICQADAAAAAA==.Poisonousx:BAAANQAECgEIAQAAAA==.Poka:BAAANQAECgMIBQAAAA==.Poluna:BAAANQAECgIIBAAAAA==.Poprocket:BAAANQADCggICAABNQAECgUICAADAAAAAA==.Popsiclegirl:BAAANQADCgQIBAAAAA==.Porkkchopp:BAAANQAECgcIEQAAAA==.',
Pr='Prayermonger:BAAANQAFFAEIAQAAAQ==.Promptoa:BAAANQAECgYIBgAAAA==.Protendo:BAAANQADCggIEAAAAA==.Provider:BAAANQAECgEIAgAAAA==.',
Ps='Psyke:BAAANQADCgUIBQAAAA==.',
Pu='Pufftreez:BAAANQAECgcIEAAAAA==.Purplatath:BAAANQADCgYICAAAAA==.Purpledrink:BAAANQAECgUICwAAAA==.Purplette:BAAANQADCggICwAAAA==.Purplizor:BAAANQAECgIIAgAAAA==.',
Pw='Pwincessmeow:BAAANQADCgYIFwAAAA==.',
Py='Pynki:BAAANQADCggICwAAAA==.Pyroxion:BAAANQADCggIEwAAAA==.Pyrìz:BAAANQAECgMIBwAAAA==.',
Qi='Qiill:BAAANQADCggIDgAAAA==.',
Qu='Quadratic:BAAANQADCgUIBwAAAA==.Quikzmagez:BAAANQADCgYIBgAAAA==.Quikzpriest:BAAANQADCgYIBQAAAA==.',
Qw='Qweefur:BAAANQADCggIDgAAAA==.',
Ra='Rabidwombat:BAABNQAECoEcAAIPAAkJ/CMyAwCOAwAPAAkJ/CMyAwCOAwAAAA==.Racoto:BAAANQAECgIIAgAAAA==.Ragingwagyu:BAAANQADCggIDQAAAA==.Ragrega:BAAANQADCgIIAgABNQAECgYIDgADAAAAAA==.Rainey:BAAANQADCgIIAgAAAA==.Ralokian:BAACNQAFFIEFAAMYAAMJASBSAgC4AAAYAAIJNx5SAgC4AAASAAEJliPBBgBsAAA1AAQKgR4AAxgACQldJCQBAFEDABgACAkIJSQBAFEDABIABwkoHs4LADACAAAA.Rangoo:BAAANQADCgUIBQAAAA==.Raphaelle:BAAANQAECgQICQAAAA==.Ravelled:BAAANQAECgIIAwAAAA==.Ravencláw:BAAANQADCgYICwAAAA==.Ravenmane:BAAANQAECgcIDwAAAA==.Rawdaug:BAAANQAECgUIBQAAAA==.Razziz:BAAANQAECgUIBwAAAA==.Raín:BAAANQADCggIFAAAAA==.',
Re='Regolas:BAAANQADCggIHAAAAA==.Rejuvie:BAAANQAECgcIDwAAAA==.Relzzad:BAAANQAECgUICAAAAA==.Renalyne:BAAANQADCgEIAQABNQAECgkJIAAeAPMcAA==.Rentámonk:BAAANQADCgEIAQABNQAECgQICAADAAAAAA==.Rentápally:BAAANQAECgQICAAAAA==.Revelätion:BAAANQAECgEIAQAAAA==.Rexxaar:BAAANQAECgMIBAAAAA==.',
Ri='Riata:BAAANQAECgcIDgAAAA==.Ricericebaby:BAAANQAECgEIAQAAAA==.Rikaya:BAAANQAECgMIBAAAAA==.Riot:BAAANQADCgQIBAABNQAECgUICwADAAAAAA==.',
Ro='Robertcheeto:BAABNQAECoEeAAIfAAkJ5BuQCAC6AgAfAAkJ5BuQCAC6AgAAAA==.Rogchamita:BAAANQAECggIEwAAAA==.Ronalde:BAAANQAECgQIBQAAAA==.Rondall:BAAANQAECgUICQAAAA==.Rousera:BAAANQAECgYICgAAAA==.Roxxaan:BAAANQAECgMIBQAAAA==.Royvn:BAAANQAECgQICQAAAA==.',
Ru='Ruffels:BAAANQAECgEIAQAAAA==.Runtzz:BAAANQADCgMIAwAAAA==.',
Ry='Ryushinizi:BAAANQADCgIIAgABNQAECgMIBAADAAAAAA==.',
Sa='Saberana:BAAANQADCgYIDAAAAA==.Sadllama:BAAANQAECgYIDAAAAA==.Saintcow:BAAANQADCgYIBgAAAA==.Saintl:BAABNQAECoEeAAINAAkJERfpEAB3AgANAAkJERfpEAB3AgAAAA==.Saloriel:BAAANQADCggICAAAAA==.Sammwow:BAAANQAECgUICgAAAA==.Sammyl:BAAANQABCgcICwAAAA==.Sanalin:BAAANQADCgIIAgABNQADCgcIBwADAAAAAA==.Sanlerøs:BAAANQAECgIIAwAAAA==.Sarandots:BAAANQADCgEIAQABNQAECgcIEwADAAAAAA==.Saranfarmer:BAAANQAECgcIEwAAAA==.Sarantakos:BAAANQADCgYICgABNQAECgcIEwADAAAAAA==.Sarviez:BAAANQADCgcIBwAAAA==.Sass:BAAANQADCggICAABNQAECgcIDwADAAAAAA==.',
Sc='Schwetyß:BAAANQADCgYIBgAAAA==.Scolio:BAAANQAECgMIAwAAAA==.Scourgeguy:BAAANQAECgIIBQAAAA==.',
Se='Separation:BAAANQADCgUIBgAAAA==.Seves:BAAANQADCgcIDAAAAA==.',
Sh='Shadosham:BAAANQAECgQIBAAAAA==.Shadowcakes:BAAANQADCgYIBgAAAA==.Shadowsmith:BAABNQAECoEeAAMZAAkJ7RubFwCKAQAQAAYJ3hsQPwDRAQAZAAYJJBObFwCKAQAAAA==.Shamanella:BAAANQADCggICAAAAA==.Shamooky:BAEANQAECgMIBQAAAA==.Shanke:BAAANQAECgUICAAAAA==.Shieldbane:BAAANQADCggICAAAAA==.Shizzkin:BAAANQADCgcIBwAAAA==.Shmotz:BAAANQABCgIIAgAAAA==.Shocktoke:BAAANQAECgIIAwAAAA==.Shockzone:BAAANQAECgIIAgAAAA==.Shootymcgun:BAAANQAECgIIAgAAAA==.Shots:BAABNQAECoEeAAIbAAkJuRBJOwBKAgAbAAkJuRBJOwBKAgAAAA==.Shotsonshots:BAAANQADCggIDQAAAA==.Shoulders:BAAANQAECgUIBQAAAA==.',
Si='Siado:BAAANQAECgEIAgAAAA==.Sidesandwich:BAAANQAECgMIBAAAAA==.Sinthetic:BAAANQADCggIJwAAAA==.Siqi:BAAANQADCgEIAQAAAA==.',
Sk='Skills:BAAANQADCggICAAAAA==.Skornn:BAAANQAECgQIBAAAAA==.Skyfangret:BAAANQADCggIEgAAAA==.Skysweep:BAAANQADCgYICAABNQAECgQICQADAAAAAA==.',
Sl='Slag:BAAANQADCgcIEAABNQADCggIDgADAAAAAA==.Slappypaws:BAAANQADCgYIBgABNQADCgYIBgADAAAAAA==.Slayerlilith:BAAANQADCgIIAgAAAA==.Slickxoxo:BAAANQADCgcIBwAAAA==.Slizaro:BAAANQAECgcIEQAAAA==.Sloponmyknob:BAAANQAECgEIAQABNQAECgQIBgADAAAAAA==.',
Sm='Smashendash:BAAANQAECgQIBwAAAA==.Smolslaps:BAAANQAECgYIDAABNQADCgYIBgADAAAAAA==.',
Sn='Snakeyess:BAAANQADCggIDgAAAA==.Snappypuppy:BAAANQADCgIIAgABNQADCgYIBgADAAAAAA==.',
So='Sockemm:BAAANQAECgYICAAAAA==.Sollaria:BAAANQABCggICwAAAA==.Sorchanna:BAAANQADCgcIDgAAAA==.Soulamander:BAABNQAFFIEIAAIRAAQJowfZBAApAQARAAQJowfZBAApAQAAAA==.Souza:BAAANQAECgQICgAAAA==.Soül:BAAANQAECggIEAAAAA==.',
Sp='Spikeyboy:BAAANQADCgYIBgAAAA==.Spinal:BAAANQAECgUICQAAAA==.Spiritfinger:BAAANQAECgUIBwABNQAECggIDgADAAAAAA==.',
Sq='Sqrood:BAAANQAECgYIDgAAAA==.Squâll:BAAANQAECgEIAQAAAA==.',
Sr='Srdlosrayoz:BAAANQAECggICAAAAA==.',
St='Stativa:BAAANQADCgYIBgAAAA==.Stellaris:BAAANQAECgUICwAAAA==.Stevesmiff:BAAANQADCgUIBwAAAA==.Sting:BAAANQAECgQIBwAAAA==.Stoofy:BAAANQADCgQIBAABNQAFFAQICAATAOUWAA==.Stormbreakur:BAAANQADCggIFAAAAA==.Stormskillz:BAAANQADCgYIBgAAAA==.Strapperjack:BAAANQADCgUIBQAAAA==.',
Su='Sugarhammer:BAAANQADCgEIAQAAAA==.Sunarri:BAAANQADCggIFAAAAA==.Sunbourne:BAAANQAECgUICgAAAA==.Suradin:BAAANQAECgUICwAAAA==.Surdaddy:BAAANQAECgMIAwAAAA==.Surín:BAAANQADCgcIBwAAAA==.',
Sy='Syrathia:BAAANQAECgMIBgAAAA==.',
['Sî']='Sîcarius:BAAANQADCgcIDgAAAA==.',
['Sú']='Súcellus:BAAANQADCgYIBgAAAA==.Súrë:BAACNQAFFIEFAAIRAAMJWRNmBQAGAQARAAMJWRNmBQAGAQA1AAQKgSEAAhEACQmsIesCAFcDABEACQmsIesCAFcDAAAA.',
Ta='Tahtics:BAAANQAECgYICgAAAA==.Talmahua:BAAANQADCgUIBQAAAA==.Tangolay:BAAANQADCgIIAgABNQAECgUICQADAAAAAA==.Tatyl:BAAANQAECgcIEAAAAA==.Tazana:BAAANQAECgEIAQAAAA==.',
Te='Tehsirus:BAAANQAECgUIBgAAAA==.Temoro:BAAANQADCgYIBgABNQADCggICAADAAAAAA==.Tempestaurus:BAAANQAFFAEIAQAAAA==.Tenkok:BAAANQAECgQIBwAAAA==.Tewpok:BAABNQAECoEaAAQgAAgJowwlBQCsAQAgAAcJ2QslBQCsAQAZAAIJ3QyMRQB4AAAQAAIJzwcbqwBoAAAAAA==.',
Th='Thalisan:BAAANQAECgQIBgAAAA==.Thatmage:BAAANQAECgQIBwAAAA==.Theirashes:BAAANQADCgMIAwABNQAECgkJHAAhALMhAA==.Themoistest:BAAANQAECgQIBgAAAA==.Theothehero:BAABNQAECoEYAAIQAAgJrRlNJABYAgAQAAgJrRlNJABYAgAAAA==.Thewogfather:BAAANQAECgQIBQAAAA==.Thirdhank:BAAANQADCgYIBgAAAA==.Thoar:BAABNQAECoEfAAILAAkJ2x0kAwAnAwALAAkJ2x0kAwAnAwAAAA==.Thormoon:BAAANQAECgYICgAAAA==.Thraller:BAAANQADCgYIBgABNQAECgUICwADAAAAAA==.',
Ti='Tiahdoe:BAAANQADCggIEwAAAA==.Tiariel:BAAANQAFFAQIBAAAAA==.Tiriq:BAAANQAECgEIAQAAAA==.',
To='Tolnar:BAAANQAECgcIEgAAAA==.Tolnter:BAAANQADCgYIDAAAAA==.Tompo:BAEANQAECgYIAwAAAA==.Toodle:BAAANQAECgUICAAAAA==.Torgrun:BAAANQAECgQIBgAAAA==.Torniak:BAAANQAECgIIAwAAAA==.Torpor:BAAANQADCggIDQAAAA==.',
Tr='Traplock:BAAANQADCgQIBAABNQAECgUIDAADAAAAAA==.Trapple:BAAANQADCggICAABNQAECgUIDQADAAAAAA==.Trillian:BAAANQADCggICAAAAA==.Trixia:BAAANQAFFAEIAQAAAA==.Troudeseve:BAAANQADCgcIDQAAAA==.',
Tu='Tusenpai:BAAANQAECgEIAQAAAA==.',
Tw='Twiggyy:BAAANQAECggIDgAAAA==.',
Ty='Tyburr:BAAANQAECggIAQAAAA==.',
Tz='Tzye:BAAANQADCgQIBQAAAA==.',
['Tâ']='Tângo:BAAANQAECgUICQAAAA==.',
Uj='Ujellypalz:BAAANQAECgEIAQAAAA==.Ujio:BAAANQADCgYIBgABNQAECgQIBAADAAAAAA==.',
Um='Umbráe:BAABNQAECoEeAAIdAAkJwxwBDwDQAgAdAAkJwxwBDwDQAgAAAA==.Umoonar:BAAANQADCgYICwAAAA==.',
Un='Unctekay:BAAANQABCgIIAgAAAA==.',
Ur='Ursainsanis:BAAANQAECgUIBwAAAA==.Urukhaí:BAAANQADCgYIBgAAAA==.',
Va='Vainless:BAAANQADCgIIAgAAAA==.Valhalla:BAAANQAECgMIBQAAAA==.Vallynn:BAAANQADCgQIBAAAAA==.Vandle:BAAANQAECgcIEwAAAA==.Vanoranda:BAAANQADCgIIAgABNQAECgYICwADAAAAAA==.Variena:BAAANQADCgcIBgAAAA==.Varikk:BAAANQADCggIFAAAAA==.Varmage:BAAANQADCgYICwABNQAECgQIBAADAAAAAA==.Varmmy:BAAANQAECgQIBAAAAA==.Varrair:BAAANQADCggICAABNQAECgQIBAADAAAAAA==.Vashezzo:BAACNQAFFIEFAAIPAAMJTRS/BQALAQAPAAMJTRS/BQALAQA1AAQKgRkAAg8ACQkiIOMGAEgDAA8ACQkiIOMGAEgDAAE1AAUUBQgJACIAaxgA.',
Ve='Velein:BAAANQADCgYICQAAAA==.Vellyssa:BAAANQAECgUICgAAAA==.Verdolaga:BAAANQADCgYIBgAAAA==.Vexys:BAAANQADCgUIBQAAAA==.Veyllor:BAAANQAECgQIBQAAAA==.',
Vi='Villainous:BAAANQAECgYICgAAAA==.Vindorian:BAAANQADCggICAAAAA==.Vitreshilla:BAAANQAECgEIAQABNQAECgYICwADAAAAAA==.Vixenz:BAAANQAECgQIBgAAAA==.',
Vo='Volteer:BAABNQAECoEeAAISAAkJkBjwBgC+AgASAAkJkBjwBgC+AgAAAA==.Voxian:BAAANQADCgYICwAAAA==.',
Vr='Vriest:BAAANQAECgEIAQABNQAECgQIBAADAAAAAA==.',
Vy='Vyecodin:BAAANQADCgYIBgAAAA==.Vyr:BAEBNQAECoEhAAIHAAkJJSFFBABsAwAHAAkJJSFFBABsAwAAAA==.',
['Vä']='Väryn:BAAANQAECgUICAAAAA==.',
Wa='Wannabrownie:BAAANQADCgUIAwAAAA==.Wardrian:BAAANQAECgEIAgAAAA==.Warriorzors:BAAANQADCgUIBQAAAA==.Wavyfist:BAAANQADCgQIBAABNQAFFAEIAQADAAAAAA==.Way:BAAANQAECgQIBQAAAA==.Wayshort:BAAANQADCggICAABNQAECgUICAADAAAAAA==.Waystrong:BAAANQADCggICAABNQAECgUICAADAAAAAA==.',
We='Wellith:BAAANQAECgcIEwAAAA==.Westìn:BAAANQADCgEIAQAAAA==.',
Wi='Wikdtwstr:BAAANQAECgcIDgAAAA==.Wildcard:BAAANQAECgQIBQAAAA==.Wilder:BAAANQAECgUICgAAAA==.',
Wo='Wolfir:BAAANQADCggIEAAAAA==.',
Wt='Wtfchickenz:BAAANQAECgYICgAAAA==.',
Wu='Wuntch:BAAANQADCgIIAgABNQADCgMIAwADAAAAAA==.',
['Wã']='Wãngs:BAAANQAECgQICAABNQAECgUIBgADAAAAAA==.',
Xa='Xaev:BAAANQAECgMIBQAAAA==.Xarathiel:BAAANQAECgQIBAABNQAECgYICgADAAAAAA==.',
Xe='Xecution:BAAANQAECgYIDgAAAA==.Xenthor:BAAANQADCgUIBQAAAA==.Xeseparg:BAEANQAECggICAABNQAECggIAwADAAAAAA==.Xevorian:BAAANQAECgMIBQAAAA==.',
Xi='Xiexieping:BAABNQAFFIEGAAILAAQJ6h+NAACcAQALAAQJ6h+NAACcAQAAAA==.',
Xy='Xyris:BAAANQADCgUIBQABNQAECgMIBQADAAAAAA==.',
Ye='Yedranna:BAAANQAECgEIAQAAAA==.',
Yo='Yoloswagcrew:BAAANQAECgcIEQAAAA==.Yooksham:BAAANQAFFAIIAgAAAA==.',
Ys='Yslena:BAAANQABCgYICgAAAA==.Yssa:BAAANQADCggIDgABNQAECgUICAADAAAAAA==.',
Yu='Yuebing:BAABNQAECoEeAAIXAAkJORM2GwBsAgAXAAkJORM2GwBsAgAAAA==.Yumin:BAAANQADCgUIBQAAAA==.Yurmagesty:BAAANQAECgQIBwAAAA==.',
['Yà']='Yàkana:BAAANQADCggIDAAAAA==.',
Za='Zaddia:BAAANQADCgQIAQABNQAECgIIAwADAAAAAA==.Zaeta:BAAANQAECgQIBwAAAA==.Zaetini:BAAANQADCgYICwABNQAECgQIBwADAAAAAA==.Zamforia:BAAANQAECgUICwAAAA==.Zandadead:BAAANQADCgQIBAABNQAECgMIBAADAAAAAA==.Zarellia:BAAANQAECgMIAwAAAA==.',
Ze='Zeeleez:BAAANQABCgIIAgAAAA==.Zephyrr:BAAANQADCggIFgABNQAECgMIBQADAAAAAA==.Zerathrot:BAAANQADCgMIAwAAAA==.Zevaran:BAAANQADCgIIAgABNQAFFAUICQAOAHEaAA==.Zexeria:BAAANQAECgMIBQABNQAECgUIDAADAAAAAA==.',
Zi='Zingara:BAAANQADCgEIAQAAAA==.',
Zo='Zootz:BAAANQADCgYICAAAAA==.Zorororonoa:BAAANQAECggIBQAAAA==.Zorrghen:BAAANQADCgYIEQABNQAECgYIDwADAAAAAA==.Zounap:BAAANQAECgUICAAAAA==.Zoyaa:BAAANQAECgMIAwAAAA==.',
Zu='Zultra:BAAANQADCgcICAAAAA==.',
['Zë']='Zëd:BAAANQADCgcICQAAAA==.',
['Ïs']='Ïshtãr:BAAANQAECgUICAAAAA==.',
['Üt']='Üthér:BAAANQAECgYICwAAAA==.',
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
