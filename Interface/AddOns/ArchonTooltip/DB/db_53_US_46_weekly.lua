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

local lookup = {'Unknown-Unknown','Rogue-Outlaw','DemonHunter-Devourer','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Monk-Brewmaster','Shaman-Enhancement','Rogue-Subtlety','Hunter-BeastMastery','Monk-Windwalker','DemonHunter-Havoc','Paladin-Holy','DeathKnight-Frost','DeathKnight-Unholy','Mage-Arcane','Druid-Restoration','Evoker-Preservation','Druid-Guardian','Shaman-Restoration','Paladin-Retribution','Warrior-Arms','Priest-Holy','Priest-Discipline','Shaman-Elemental','DeathKnight-Blood','Hunter-Marksmanship','Druid-Balance','Warrior-Fury','Monk-Mistweaver','Paladin-Protection','Evoker-Devastation','Evoker-Augmentation','Rogue-Assassination','Mage-Frost','Hunter-Survival','Warrior-Protection',}
local provider = {region='US',realm='BurningBlade',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aatto:BAAANQADCgYICgABNQAECgUICAABAAAAAA==.',
Ac='Acertrick:BAACNQAFFIENAAICAAYJ1B4IAABXAgACAAYJ1B4IAABXAgA1AAQKgSMAAgIACQnDJQ4AAAMEAAIACQnDJQ4AAAMEAAAA.',
Ad='Adampriest:BAAANQAECgcICAAAAA==.Addh:BAABNQAECoEYAAIDAAgJTxoCEgB7AgADAAgJTxoCEgB7AgAAAA==.',
Ae='Aelwyd:BAABNQAECoEkAAQEAAkJbREdCQBCAgAEAAkJBg8dCQBCAgAFAAUJ+g57CAAxAQAGAAQJxQpJfwDxAAAAAA==.Aeoni:BAAANQADCggICAABNQAECgYIEAABAAAAAA==.Aeronis:BAAANQAECgQIBAAAAA==.Aery:BAAANQADCgUIBQABNQAECggIFwAHALUeAA==.Aessara:BAAANQAECgIIAgAAAA==.',
Ag='Aggron:BAABNQAECoEbAAIIAAkJJx9cAgBNAwAIAAkJJx9cAgBNAwAAAA==.',
Ai='Ailurun:BAAANQADCgEIAgAAAA==.',
Al='Alexassassin:BAABNQAECoEXAAIJAAkJqBrSBwDIAgAJAAkJqBrSBwDIAgAAAA==.Aloriannis:BAAANQAECgQICwAAAA==.Aluas:BAAANQADCggIEgAAAA==.Alurai:BAAANQADCgcIDQAAAA==.',
Am='Amaracepally:BAAANQAECgUICgAAAA==.Amethar:BAAANQAECgMIAwABNQAFFAUICQAIACcbAA==.Amowdrood:BAAANQADCgUIBgABNQAECgYIDgABAAAAAA==.Amowshamow:BAAANQAECgYIDgAAAA==.',
An='Anan:BAAANQAECgEIAgAAAA==.Anaria:BAAANQADCgQIBQAAAA==.Anatall:BAABNQAECoEXAAIKAAgJ1x1ZGQCxAgAKAAgJ1x1ZGQCxAgAAAA==.Andrin:BAAANQAECgUICQAAAA==.Andy:BAAANQADCgYIBgAAAA==.Aneira:BAAANQADCgUIBQAAAA==.Anitá:BAAANQADCgcIEAAAAA==.',
Ap='Applebees:BAAANQADCggICAAAAA==.',
Ar='Araragi:BAAANQAECgcIDAAAAA==.Archaon:BAAANQAECgcIDgAAAA==.Arei:BAABNQAECoEXAAIHAAgJtR5dBACrAgAHAAgJtR5dBACrAgAAAA==.Argosa:BAAANQAECgYIDwAAAA==.Ari:BAABNQAECoEYAAILAAgJ2CCwBwDuAgALAAgJ2CCwBwDuAgAAAA==.Arianagrande:BAAANQAECgIIAgAAAA==.Ariehh:BAAANQADCgcIBwABNQAECggIGAALANggAA==.Arihog:BAAANQAECgUICQAAAA==.Arioch:BAAANQAECgEIAQAAAA==.Arkilytê:BAACNQAFFIEJAAMDAAUJqhyrAgCQAQADAAQJxx+rAgCQAQAMAAEJNhCbCQBYAAA1AAQKgSIAAwMACQmZI44CAJ8DAAMACQkSI44CAJ8DAAwAAQl3JM9FAGYAAAAA.Aryä:BAAANQAECgEIAQAAAA==.',
As='Ascend:BAECNQAFFIEOAAINAAYJbA57AQD7AQANAAYJbA57AQD7AQA1AAQKgRsAAg0ACQkEHukJACcDAA0ACQkEHukJACcDAAAA.Ascendant:BAEANQAECggICAABNQAFFAYIDgANAGwOAA==.Astraeá:BAAANQAECgYICwAAAA==.',
Au='Auroch:BAAANQAECgcIDgAAAA==.Auxilary:BAABNQAECoEVAAMOAAcJdQysHgCKAQAOAAcJdQysHgCKAQAPAAIJAgkecQBqAAAAAA==.',
Av='Avalen:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Avarcis:BAAANQAECgYIDAAAAA==.Avasauras:BAAANQAECgEIAQAAAA==.Aveleni:BAABNQAECoEVAAIQAAcJYwxlhwC3AQAQAAcJYwxlhwC3AQAAAA==.Aveloree:BAAANQADCgYIFQAAAA==.',
Aw='Awakening:BAAANQABCgUIBgAAAA==.',
Az='Azelie:BAAANQAECgMIBQAAAA==.',
Ba='Baddragön:BAAANQADCgIIAgABNQAECggIFgARAMATAA==.Baery:BAAANQAECgQIBAABNQAECggIFwAHALUeAA==.Baidoom:BAAANQABCgQIBAAAAA==.Balcmeg:BAAANQAECgUIBgABNQAECgUIBgABAAAAAA==.Bandrui:BAAANQADCgYICwAAAA==.Banick:BAAANQAECgIIAgAAAA==.Bartszwar:BAAANQAECgYIEgAAAA==.',
Be='Bendie:BAAANQADCgcICAAAAA==.Beret:BAABNQAECoEXAAISAAgJsx1SCQCpAgASAAgJsx1SCQCpAgAAAA==.Bewmbat:BAAANQAECgUIBQABNQADCgEIAQABAAAAAQ==.',
Bg='Bgaraecen:BAAANQADCgQIBAAAAA==.',
Bi='Bigchimpn:BAAANQAECgIIAgAAAA==.Bimbo:BAAANQAECgMIBwAAAA==.Bindkickplz:BAAANQABCgQIBwAAAA==.Birdinii:BAAANQAECgcIDgAAAA==.Birstormrage:BAAANQAECgMIBQAAAA==.',
Bl='Blacksmoke:BAAANQADCgUIBAAAAA==.Blacktusk:BAAANQAECgQICgAAAA==.Bladestorm:BAAANQADCgYIDQAAAA==.Blargdruid:BAABNQAECoEjAAITAAkJ2xbVBAB7AgATAAkJ2xbVBAB7AgAAAA==.Blargwar:BAAANQADCgcICAABNQAECgkJIwATANsWAA==.Blessthat:BAEANQAECgIIAgAAAA==.Blindnada:BAAANQAECgEIAQABNQAECgcIEAABAAAAAA==.',
Bo='Bonkie:BAAANQADCggIGgABNQAECgMIBQABAAAAAA==.Boomkíll:BAAANQADCgIIAgABNQADCgcIDQABAAAAAA==.',
Br='Breaze:BAAANQAECgEIAQAAAA==.Brewdyne:BAAANQADCggICAABNQAECgcIEAABAAAAAA==.Brignis:BAAANQADCgUIBQAAAA==.Brizz:BAAANQAECgIIBAABNQAECggIFQAUANgaAA==.Brojojojojo:BAAANQAECgMIBgAAAA==.Broxas:BAAANQAECgEIAQAAAA==.Brøken:BAAANQAECggIDQAAAA==.',
Bu='Bubbleblade:BAAANQADCgEIAQAAAA==.Bubblesbro:BAABNQAECoEcAAIVAAkJqyXYAgDLAwAVAAkJqyXYAgDLAwAAAA==.Bubkiss:BAAANQADCgEIAQAAAQ==.Buffalo:BAABNQAECoEXAAIWAAgJaho2MAB9AgAWAAgJaho2MAB9AgAAAA==.Buffs:BAAANQADCgIIAgABNQAECgMIBgABAAAAAA==.Buffy:BAAANQAECgQIBAAAAA==.Bulbasaurz:BAAANQAECgQIBAAAAA==.Buldair:BAAANQAECgEIAgAAAA==.Bunsski:BAAANQAECgQIBgAAAA==.Burntbacon:BAAANQADCggICAABNQAECgYIEAABAAAAAA==.Burstygirl:BAABNQAECoEcAAIDAAkJmxdTDgC0AgADAAkJmxdTDgC0AgAAAA==.Buzzkill:BAAANQADCgMIAwAAAA==.',
Bw='Bwis:BAAANQAECgEIAQAAAA==.',
['Bø']='Bøkari:BAAANQAECgQICAAAAA==.',
Ca='Cakes:BAAANQADCgMIAwAAAA==.Callie:BAACNQAFFIEOAAIXAAYJAhaEAQAKAgAXAAYJAhaEAQAKAgA1AAQKgSMAAxcACQnJITEJABcDABcACQnJITEJABcDABgACAkVCPUGAJMBAAAA.Caloren:BAAANQADCgYICwABNQAECgQICAABAAAAAA==.Calypsoza:BAAANQADCggIDAAAAA==.Capitis:BAAANQAECgEIAQAAAA==.Catwink:BAAANQADCgYICAAAAA==.Caulkfu:BAAANQADCgQIBAABNQAECgYIDgABAAAAAA==.Caulkgoblinz:BAAANQADCgMIAwABNQAECgYIDgABAAAAAA==.',
Ce='Celaine:BAAANQADCgIIAgAAAA==.Celine:BAAANQAECgUIBwAAAA==.Ceol:BAAANQAECgUICAAAAA==.Cernath:BAAANQADCgYIBgABNQAECgcIDQABAAAAAA==.',
Ch='Chaddbrochil:BAAANQADCgYIBgAAAA==.Chaosblade:BAAANQAECgYICAAAAA==.Chilicheese:BAAANQADCgEIAQAAAA==.Chocobomb:BAABNQAECoEgAAMZAAkJZRFNJwA9AgAZAAkJZRFNJwA9AgAUAAYJxwHQdADoAAAAAA==.Chosen:BAAANQADCggIEAAAAA==.Chronarfs:BAAANQAECgUIBwAAAA==.',
Ci='Cicatrizesp:BAABNQAECoEVAAIIAAcJQg6ODADnAQAIAAcJQg6ODADnAQAAAA==.Cive:BAAANQAECgMIBgAAAA==.',
Cl='Clayberd:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
Co='Coldhearrted:BAABNQAECoEXAAMOAAkJEBZOFwDjAQAOAAgJvhROFwDjAQAPAAUJZBIsQgBSAQAAAA==.Copyleft:BAAANQADCgQIBAAAAA==.Cosmere:BAAANQAECgQIBAAAAA==.',
Cr='Cracku:BAAANQADCgYIBgAAAA==.Crookamow:BAAANQADCgIIAgABNQAECgYIDgABAAAAAA==.Cryt:BAAANQAECgQIBwAAAA==.',
Da='Dagather:BAAANQADCgcICwAAAA==.Danala:BAAANQADCgQIBAABNQAECgUIBQABAAAAAA==.Danendena:BAAANQAECgYIDAAAAA==.Danglars:BAAANQADCggICwABNQAECgYICwABAAAAAA==.Darkcorn:BAAANQAECgYIEgAAAA==.Darkdecayy:BAAANQADCgQIBQAAAA==.Darkshieldz:BAAANQAECgYIDgAAAA==.Darktiranus:BAAANQADCggICAAAAA==.David:BAAANQAECggIEAAAAA==.',
De='Deadkyle:BAAANQADCgQIBAAAAA==.Deadly:BAAANQADCgUIBQAAAA==.Deathcalls:BAAANQAECgEIAQAAAA==.Deathlywind:BAAANQAECgcICwAAAA==.Delphias:BAAANQAECgQIBAAAAA==.Destrorin:BAAANQAECgQIBAAAAA==.Dethlok:BAAANQADCgYIDQAAAA==.Deucedeuce:BAAANQADCgcIFgAAAA==.Devowizard:BAABNQAFFIETAAIQAAcJHBx1AACgAgAQAAcJHBx1AACgAgAAAA==.Dewshaman:BAAANQADCgIIAgAAAA==.',
Di='Dibib:BAACNQAFFIEOAAMGAAYJmA7iAQCeAQAGAAUJkw7iAQCeAQAEAAEJrw7HCgBaAAA1AAQKgSMAAwYACQlfI3UIACoDAAYACAn3InUIACoDAAQACAnkEtYJADQCAAAA.Dinglebery:BAAANQAECgYIEAAAAA==.Dirac:BAAANQAECgMIBAAAAA==.Dirtybirdz:BAAANQADCggIEAAAAA==.Discowalker:BAAANQAFFAEIAQAAAA==.Dislexy:BAAANQADCgQIBQAAAA==.',
Dk='Dkitty:BAAANQAECgYIDAAAAA==.Dkittykat:BAAANQADCgcIBwABNQAECgYIDAABAAAAAA==.Dkizzy:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.',
Do='Dogs:BAAANQADCgcIDQAAAA==.Donkeydonng:BAAANQAECgUIBQAAAA==.Doodlez:BAAANQAECgEIAQAAAA==.Dota:BAAANQAECgUIBgAAAA==.',
Dr='Dracke:BAAANQADCggICAAAAA==.Draga:BAAANQAECgYICgAAAA==.Dragondeezn:BAAANQADCgcICAAAAA==.Drekzul:BAAANQAECgQICAAAAA==.Drutara:BAAANQAECgYICgAAAA==.',
Du='Ducey:BAAANQAECgYIBwAAAA==.Ducksicker:BAAANQAECgUIBQAAAA==.Dumpsterbaby:BAAANQAECgQIBwAAAA==.Dumpsterfire:BAAANQADCggICAAAAA==.Durlklok:BAAANQADCgYICgAAAA==.',
['Dè']='Dèschain:BAAANQADCgUIDgAAAA==.',
['Dé']='Démonic:BAAANQADCgQIBAAAAA==.',
['Dó']='Dóth:BAAANQAECgcICQAAAA==.',
['Dø']='Dørf:BAAANQADCgUIBwAAAA==.',
Ef='Effinaye:BAAANQABCgYIBwAAAA==.',
Ei='Eightfingers:BAAANQAECgcIEgAAAA==.Eisenklopfer:BAAANQAECgIIAgAAAA==.',
Ek='Ekim:BAAANQAECgEIAQAAAA==.',
El='Elara:BAAANQAECgYIBgAAAA==.Elentiya:BAAANQADCgUIBwAAAA==.Elyaen:BAAANQAECgQICQAAAA==.',
Em='Emailed:BAECNQAFFIEJAAMUAAMJ6gZEBwDfAAAUAAMJ6gZEBwDfAAAZAAEJRQwuEgBKAAA1AAQKgR8AAxkACQkCHJIVAM4CABkACQkCHJIVAM4CABQAAwknF6l1AOUAAAAA.Emi:BAAANQAECgIIAgAAAA==.Emofemboy:BAAANQADCgYICwAAAA==.',
En='Envy:BAAANQAECgYICAAAAA==.',
Eo='Eore:BAAANQAECgUICAAAAA==.',
Er='Erequem:BAAANQADCgEIAQAAAA==.',
Eu='Eupatorus:BAAANQAECgEIAQAAAA==.',
Ew='Ewokhunter:BAABNQAECoEWAAIJAAkJniMbAQCwAwAJAAkJniMbAQCwAwAAAA==.',
Ex='Execuwute:BAAANQABCgYICAAAAA==.',
Fe='Felonee:BAAANQADCgcIEgAAAA==.Festermight:BAACNQAFFIEKAAQOAAMJVhcwBQClAAAPAAIJoBifBgCnAAAOAAIJIRYwBQClAAAaAAEJvBBXFAA0AAA1AAQKgSQAAw4ACQk3JSIBAMIDAA4ACQkoJSIBAMIDAA8ACQkTHz8RAMsCAAAA.',
Fi='Finnhunter:BAAANQADCgEIAQAAAA==.Firedur:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.Firenze:BAAANQAECgQIBAAAAA==.Fishpockets:BAAANQADCgEIAQAAAA==.',
Fl='Flosstradamu:BAAANQABCgMIAQAAAA==.',
Fr='Fredrock:BAAANQAECgYICwAAAA==.',
Fu='Fuzziewuzzie:BAAANQAECgMIAgAAAA==.',
['Fî']='Fîshy:BAAANQAFFAIIAwAAAA==.',
Ga='Gaibe:BAABNQAECoEcAAINAAkJjiWJAADiAwANAAkJjiWJAADiAwAAAA==.Gamba:BAAANQAECgcIEQAAAA==.Gambaj:BAAANQADCgYIBgAAAA==.Ganicuss:BAAANQAECgcIAQAAAA==.Garuum:BAAANQADCggICAABNQAECgUIBQABAAAAAA==.',
Gb='Gb:BAAANQADCgYIBgAAAA==.',
Ge='Genghiscaulk:BAAANQAECgYIDgAAAA==.Georgeknight:BAACNQAFFIEHAAQOAAMJcQ3xBACnAAAOAAIJxhLxBACnAAAPAAEJJB9UCQBbAAAaAAEJxgL7GQAeAAA1AAQKgSIAAw4ACQkpIBwIAOcCAA8ACQleHoQOAO0CAA4ACQnPGxwIAOcCAAAA.Gertrùde:BAAANQAECgUIBgAAAA==.Gerunash:BAAANQADCggICAABNQAFFAcIEwAJAPYLAA==.Gewnz:BAAANQAECgYIEAABNQADCgEIAQABAAAAAA==.',
Gi='Gildharts:BAAANQAECggIEQAAAA==.Gingergiant:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.Girl:BAAANQAECgUIBwAAAA==.',
Gl='Glowlimn:BAAANQAECgQIBAABNQAECgYICwABAAAAAA==.',
Go='Goblindur:BAAANQAECgQIBQAAAA==.',
Gr='Gradris:BAABNQAECoEVAAIVAAcJ2xbjTADDAQAVAAcJ2xbjTADDAQAAAA==.Greener:BAAANQAECgcIEgAAAA==.Griddy:BAAANQAECgMIBgAAAA==.Grimghar:BAAANQADCggIGQAAAA==.Grimhoof:BAAANQADCgcIBwABNQAECgQICwABAAAAAA==.Grimrael:BAAANQADCgQIBAABNQAECgQICwABAAAAAA==.Grimreapyr:BAAANQADCgUIBgABNQAECgQICwABAAAAAA==.Grimtar:BAAANQAECgYIDgABNQAECgQICwABAAAAAA==.Grimtariel:BAAANQAECgQICwAAAA==.Grimzilla:BAAANQAECgEIAQABNQAECgQICwABAAAAAA==.Grindkíng:BAAANQADCgQIBAAAAA==.Grippin:BAAANQAECgUIBwAAAA==.',
Gu='Guldar:BAAANQADCgYIBgAAAA==.Gunoil:BAAANQAECgQIBgAAAA==.',
['Gì']='Gìngerale:BAAANQADCggIGQAAAA==.',
Ha='Hamrshifts:BAAANQADCggIGQAAAA==.Hamrwitch:BAAANQADCgYIBgAAAA==.Harritapoter:BAAANQABCgYIBgAAAA==.Havartihavoc:BAAANQADCggIGAAAAA==.Hawtdots:BAAANQAECgIIAgABNQAECgQIBwABAAAAAA==.',
He='Healmeplx:BAAANQAECgQIBQAAAA==.Healsfadayz:BAAANQADCggICAAAAA==.Heiku:BAAANQAECgIIAgAAAA==.Hekaraa:BAAANQADCgcIFwAAAA==.Hellhammer:BAAANQADCgcIDAAAAA==.Herenya:BAAANQAECgEIAQAAAA==.',
Hi='Hiccup:BAAANQADCggIEAAAAA==.Hideyourtoes:BAAANQAECgYIDAABNQAECgkJIQAbAHojAQ==.Himnick:BAACNQAFFIETAAQFAAcJBxwzAAA7AQAFAAMJnhszAAA7AQAEAAMJRR/RAAAgAQAGAAMJABCNBwD4AAA1AAQKgSMABAQACQn5JPwEAKsCAAQABwnyIvwEAKsCAAYABwmsHtUhAGUCAAUABQmcIbQDAP4BAAAA.',
Ho='Holyslimes:BAAANQADCgMIAwAAAA==.Honoree:BAAANQAECgEIAQAAAA==.Honse:BAAANQAECgUIBQAAAA==.Hoodal:BAABNQAECoEYAAINAAkJkxgnFgCuAgANAAkJkxgnFgCuAgAAAA==.Hope:BAAANQAFFAIIAgAAAA==.',
Hu='Hugzug:BAAANQAECgMIAwAAAA==.Huntrez:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Hustlepuff:BAAANQADCgYIDQAAAA==.',
Hy='Hyllah:BAAANQAECgIIAgAAAA==.',
['Hè']='Hèrrinà:BAAANQAECgQIBgAAAA==.',
Ik='Ikissdudes:BAAANQAECgcIEgAAAA==.',
Il='Illuunni:BAAANQAECgQICQAAAA==.',
Im='Imbecile:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.Imblack:BAABNQAECoEaAAIcAAkJ7CAtCQBJAwAcAAkJ7CAtCQBJAwAAAA==.Improv:BAAANQADCggICQABNQAECgcIEgABAAAAAA==.',
Jc='Jclaw:BAAANQADCggIDgAAAA==.',
Je='Jeddak:BAAANQAECgQIBAAAAA==.Jennzen:BAAANQADCgcIEAAAAA==.Jesterawr:BAAANQADCgUIBQABNQADCgcIDAABAAAAAA==.',
Ji='Jinjin:BAAANQAECgcIEAAAAA==.',
Jl='Jlimremix:BAAANQAECgYICAAAAA==.',
Jo='Jouley:BAAANQAECgIIAgAAAA==.',
Ju='Justamage:BAAANQAECgQIBgAAAA==.Justsaiyan:BAAANQADCggIDgAAAA==.',
Jx='Jx:BAAANQAECggIFAAAAQ==.',
Jz='Jzimm:BAAANQAECgEIAQAAAA==.',
['Jå']='Jåcob:BAAANQADCggIBgABNQAECgEIAgABAAAAAA==.',
Ka='Kadane:BAAANQADCgYIBwAAAA==.Kaeori:BAACNQAFFIETAAIcAAcJnBeOAACDAgAcAAcJnBeOAACDAgA1AAQKgRwAAhwACQl3H1QPAPYCABwACQl3H1QPAPYCAAAA.Kaeorishock:BAAANQAECgYIBgABNQAFFAcIEwAcAJwXAA==.Kalïsta:BAAANQAECgIIAwAAAA==.Karlach:BAAANQADCgcIDQAAAA==.Karnesia:BAAANQABCgMIAwAAAA==.Karra:BAAANQAECgYIEAAAAA==.Kayliezra:BAAANQADCgYICwABNQADCgcIEAABAAAAAA==.Kayssa:BAAANQAECgcICAAAAA==.',
Ke='Keegan:BAABNQAECoEXAAMdAAgJaR9fBAAoAgAdAAYJ/SFfBAAoAgAWAAIJrhdptACUAAAAAA==.Keiragosa:BAAANQAECgMIBAAAAA==.Keita:BAAANQAECgcIDAAAAA==.Kelaran:BAAANQADCgEIAQAAAA==.Kellired:BAAANQADCgIIAgAAAA==.Kelsara:BAABNQAECoEeAAIQAAkJDyOGDAB+AwAQAAkJDyOGDAB+AwAAAA==.Keltan:BAAANQADCgQIBAAAAA==.',
Kh='Khaladyn:BAAANQADCgUIBQAAAA==.Khaladynie:BAAANQADCggIDAAAAA==.Khazjin:BAAANQADCgUIBQAAAA==.',
Ki='Kiko:BAAANQADCgcIEAAAAA==.Killersmallz:BAAANQAECgYIDQAAAA==.Killshott:BAAANQADCgYIBgAAAA==.Kindatipsy:BAAANQADCgYIEwAAAA==.Kirasti:BAAANQADCggIGQAAAA==.Kiriko:BAAANQADCggIDAAAAA==.Kirkadh:BAAANQAECgIIAgABNQAFFAcIEgARAKElAA==.Kirkap:BAAANQADCgUIBQABNQAFFAcIEgARAKElAA==.Kirkas:BAAANQAECgMIBAABNQAFFAcIEgARAKElAA==.Kisspr:BAAANQAECgQIBQAAAA==.Kisswar:BAAANQAECgYIBwAAAA==.Kitkatt:BAAANQADCggIDAAAAA==.Kittyen:BAAANQADCggICAAAAA==.',
Kl='Klet:BAAANQAECgYIDAAAAA==.',
Km='Kmage:BAAANQAECgIIAgAAAA==.',
Ko='Kogarasu:BAAANQADCggIGQAAAA==.Koramar:BAAANQAECgIIAgABNQAFFAcIEwAJAPYLAA==.',
Kr='Kragarsf:BAAANQADCgcIEAAAAA==.',
Ku='Kubernaughty:BAAANQADCgYIBgAAAA==.Kuulistin:BAAANQAECgQIBAAAAA==.',
Ky='Kyoppy:BAAANQAECgcIEwAAAA==.',
La='Labluegirl:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.Lacusclyne:BAAANQADCgEIAQAAAA==.Lavaßurst:BAAANQAECgEIAQAAAA==.',
Le='Leejohn:BAAANQADCgYIBgAAAA==.Legitasaurus:BAAANQADCggICAAAAA==.Legndairy:BAAANQAECgQIBgAAAA==.Legola:BAAANQADCgQIBQAAAA==.Lenala:BAAANQAFFAIIAgAAAA==.',
Li='Lightdeity:BAAANQADCgQIBgAAAA==.Lilbeefroni:BAAANQABCgEIAQAAAA==.Lilith:BAAANQAECgMIAwAAAA==.Lilythh:BAAANQADCgIIAgABNQADCgcIFwABAAAAAA==.Linessa:BAAANQAECgUIBAAAAA==.Littlelion:BAAANQAFFAEIAQAAAA==.Littlepigboy:BAAANQAECgEIAQAAAA==.Littleteapot:BAAANQAECgMIBgAAAA==.',
Lo='Lockjim:BAAANQADCgMIAwAAAA==.Lookatthisph:BAAANQADCgIIAgABNQADCgYICAABAAAAAA==.',
Lu='Lucentil:BAAANQADCgYICwABNQADCgcIEAABAAAAAA==.Lucie:BAAANQAECgQICAAAAA==.Lucigoosey:BAAANQAECgIIAgAAAA==.Luckycharms:BAAANQABCgQIBAAAAA==.Luminth:BAAANQAECggIDQAAAA==.',
Lv='Lv:BAAANQAECgQIBAAAAA==.',
Ly='Lyka:BAAANQAECgUIEQAAAA==.',
Ma='Madoria:BAAANQAECgQIBgAAAA==.Madorie:BAAANQAECgIIAgAAAA==.Magice:BAAANQAECgIIAgAAAA==.Magistus:BAACNQAFFIEOAAIeAAcJGA0pAABeAgAeAAcJGA0pAABeAgA1AAQKgR4AAx4ACQk3H8wBAHEDAB4ACQk3H8wBAHEDAAcAAQkOHSIbAFIAAAAA.Marmalady:BAECNQAFFIESAAISAAcJ8R14AACHAgASAAcJ8R14AACHAgA1AAQKgRwAAhIACQn+IwoCAHcDABIACQn+IwoCAHcDAAAA.Masa:BAACNQAFFIEOAAIRAAYJCR4+AAA1AgARAAYJCR4+AAA1AgA1AAQKgSMAAhEACQkuJGEBAJEDABEACQkuJGEBAJEDAAAA.Masq:BAAANQAECgMIBQAAAA==.Matamharicas:BAAANQAECgYICQAAAA==.Matt:BAAANQAECgMIBAAAAA==.Mauled:BAAANQAFFAMIAwABNQAFFAcIEAAfAJgQAA==.Maulnificent:BAAANQAECgIIAgABNQAFFAcIEAAfAJgQAA==.Maulo:BAABNQAFFIEQAAIfAAcJmBBoAAAjAgAfAAcJmBBoAAAjAgAAAA==.Maynaminty:BAAANQAECgUICgABNQAFFAMIBgAMAHMJAA==.',
Mc='Mclovin:BAAANQADCgUIBQAAAA==.',
Me='Medspriest:BAAANQADCgcIDQAAAA==.Megasoreass:BAAANQADCggICwAAAA==.Meliria:BAAANQAECgcIDwAAAA==.',
Mi='Microshanks:BAAANQADCggICQAAAA==.Midgert:BAACNQAFFIEHAAIQAAQJmglWCgBKAQAQAAQJmglWCgBKAQA1AAQKgSIAAhAACQmAIVQUAE8DABAACQmAIVQUAE8DAAAA.Mimint:BAAANQAECgIIAgABNQAFFAcIEwAbAPsjAA==.Misfortune:BAAANQADCgUIBQAAAA==.Mistfit:BAAANQADCgYICgAAAA==.Mitula:BAAANQABCgUIAwAAAA==.',
Mo='Moadebe:BAAANQAECgIIAgAAAA==.Moomoomeadow:BAAANQAECgIIAgAAAA==.Moorpheus:BAAANQADCgYIBgAAAA==.Moreshaman:BAAANQADCgEIAQABNQADCgEIAQABAAAAAA==.Morgianax:BAAANQAECgEIAQAAAA==.Morphsz:BAAANQAECgEIAQAAAA==.Morphunter:BAAANQAECgUIBwAAAA==.Mozerdozer:BAAANQADCgYIBgAAAA==.',
Mu='Muthabara:BAAANQADCggICAAAAA==.Muwu:BAAANQAECgcIEAAAAA==.',
My='Myfursona:BAAANQAECgQIBAAAAA==.Mysticpizza:BAAANQADCgEIAQAAAA==.Mystrali:BAAANQAECgUIBQAAAA==.Myztified:BAAANQADCgUIBQAAAA==.',
['Mã']='Mãyhem:BAAANQADCgIIAgABNQAECgEIAgABAAAAAA==.',
['Mä']='Mädrina:BAAANQADCggIDgAAAA==.',
Na='Naelyni:BAAANQAECgUIBQABNQADCggICAABAAAAAA==.Naloxone:BAAANQADCgEIAQAAAA==.Nathrezara:BAAANQABCgIIAgAAAA==.Nawtikal:BAAANQAECgIIAgAAAA==.',
Ne='Necrootter:BAAANQAECgYICQAAAA==.Negrumps:BAAANQADCgYIBgAAAA==.Nelune:BAAANQAECgYIBwAAAA==.Neoheals:BAAANQADCgcIBwAAAA==.Neotank:BAAANQADCgUIBQAAAA==.Netgehai:BAAANQADCgQIBAAAAA==.Neurosurgeon:BAAANQADCgEIAQAAAA==.Nezdh:BAACNQAFFIEOAAIMAAYJvh5nAABlAgAMAAYJvh5nAABlAgA1AAQKgR8AAwwACQmqJSwBANUDAAwACQmqJSwBANUDAAMABwmXHkYXADYCAAAA.',
Ni='Nizal:BAAANQAECgQIBAAAAA==.',
No='Nosimpin:BAAANQADCgcIDwAAAA==.Notbrianp:BAAANQADCgMIAwABNQAECgUICAABAAAAAA==.Notbrianpage:BAAANQAECgUICAAAAA==.Nox:BAAANQADCgcIDAAAAA==.',
Nu='Nutzferbuttz:BAAANQADCgMIBAABNQAECgUIDQABAAAAAA==.',
Ny='Nyllamage:BAABNQAECoEYAAIQAAkJix5OHwAYAwAQAAkJix5OHwAYAwAAAA==.',
Ob='Obdromeda:BAAANQAECgcIEQAAAA==.Oberron:BAAANQAECgYIDQABNQAECggIFwAKANcdAA==.',
Ok='Okixs:BAAANQAECgcIDgAAAA==.',
On='Onebaddruid:BAAANQAECgQICwAAAA==.Onebadwarr:BAAANQAECggIEAABNQAECgQICwABAAAAAA==.',
Oo='Oogabgooga:BAAANQAECgMIBQAAAA==.',
Os='Oscartheorc:BAAANQADCgEIAQAAAA==.Oshamma:BAAANQAECgQICAAAAA==.Ossoleil:BAAANQADCgYIBgABNQAECgMIBQABAAAAAA==.',
Ot='Otterfang:BAAANQAECgMIBgAAAA==.',
Oz='Ozatar:BAAANQAECgQIBAABNQAECgUICQABAAAAAA==.Ozcane:BAAANQADCgUIBQABNQAECgUICQABAAAAAA==.Ozen:BAAANQAECgMIAwABNQAECgUICQABAAAAAA==.Ozlayn:BAAANQADCgUIBQABNQAECgUICQABAAAAAA==.Ozpal:BAAANQAECgUICQAAAA==.Oztide:BAAANQAECgQIBAABNQAECgUICQABAAAAAA==.Oztington:BAAANQADCgEIAQAAAA==.',
Pa='Paegan:BAAANQADCgQIBAAAAA==.Paiku:BAAANQADCgYICgAAAA==.Palaky:BAAANQAECgMIBQAAAA==.Para:BAAANQAECgQICQAAAA==.',
Pe='Peahole:BAAANQADCgQIBAAAAA==.Peccavi:BAAANQADCgMIAwAAAA==.Pelusa:BAAANQAECgQIBwAAAA==.Penelopi:BAAANQAECgYICwAAAA==.Penguinia:BAAANQAECgEIAQAAAA==.Pensman:BAAANQABCgQIBAAAAA==.',
Pi='Pitukis:BAAANQADCgYIBgAAAA==.',
Pl='Plandalorian:BAAANQADCgYIEQAAAA==.Platectonics:BAAANQADCgUIBwAAAA==.Plexadin:BAAANQAECgEIAgAAAA==.',
Po='Ponch:BAAANQADCgQIBAAAAA==.Popmybubble:BAAANQAECgUIEAAAAA==.',
Pr='Prepotenté:BAAANQAECggIEwAAAA==.Priesta:BAABNQAECoEeAAIXAAkJUxtLEADHAgAXAAkJUxtLEADHAgAAAA==.Pronebone:BAAANQAECgYIDAAAAA==.',
Qu='Quomy:BAAANQAECgUIBwAAAA==.',
Ra='Rackblaster:BAAANQABCgMIAwAAAA==.Raei:BAABNQAECoEmAAIUAAkJXhTHGQCJAgAUAAkJXhTHGQCJAgAAAA==.Ragestrasz:BAAANQAECgMIBgAAAA==.Raladin:BAAANQAECgYIBwAAAA==.Ramchi:BAACNQAFFIETAAMbAAcJUSDwAAA1AgAbAAYJwh/wAAA1AgAKAAMJdCN0AgBOAQA1AAQKgRwAAxsACQkwJgkCAKQDABsACQlsJQkCAKQDAAoAAQnMJbG1AGUAAAAA.Ramhorn:BAAANQAECgIIAgAAAA==.Ramsaur:BAAANQAECgcIDQAAAA==.Ranniel:BAAANQADCgEIAQAAAA==.Rasalghul:BAAANQADCgUIBgAAAA==.Ratchetron:BAAANQABCgMIAwAAAA==.Raythe:BAAANQADCgIIAwAAAA==.Razorfists:BAAANQAECgcIDQABNQAFFAYIDgASADYLAA==.Razorscales:BAACNQAFFIEOAAQSAAYJNgsLBQAaAQASAAQJOgMLBQAaAQAgAAIJpAoFBgCOAAAhAAEJpwEWBABRAAA1AAQKgSQABBIACQkEFNUMAF8CABIACQkEFNUMAF8CACAABwmhHU8KAFcCACEAAQnVHa8RAE0AAAAA.',
Re='Reckon:BAAANQADCggIGAAAAA==.Reeleaf:BAABNQAECoEWAAIRAAgJwBOtDwAoAgARAAgJwBOtDwAoAgAAAA==.Remainn:BAAANQAECgEIAgAAAA==.Remlar:BAAANQAECgQIBQABNQAECgkJHAADAJsXAA==.Renske:BAAANQADCgUIBgAAAA==.',
Ri='Ride:BAAANQAECgEIAgAAAA==.Rizzard:BAAANQAECgMIAwAAAA==.',
Ro='Roriel:BAAANQAECgcIEAAAAA==.Rougarou:BAAANQAECgUIBwAAAA==.Rowdyronda:BAAANQABCgIIBAAAAA==.Roweana:BAAANQADCggIGQAAAA==.',
Ru='Rubmytotéms:BAAANQADCgUIBQABNQAECgUIEAABAAAAAA==.Rumblecat:BAAANQADCgYICwABNQAECgQIBgABAAAAAA==.',
Ry='Rylankneth:BAAANQADCgYIBgAAAA==.',
['Rî']='Rîce:BAAANQAECgMICQAAAA==.',
Sa='Sabelorn:BAAANQAECgYIDQAAAA==.Sacredfear:BAABNQAECoEaAAMGAAkJIB2dDgDsAgAGAAkJIB2dDgDsAgAEAAIJHA1WSABwAAAAAA==.Sacredshammy:BAAANQAECgYIEAABNQAECgkJGgAGACAdAA==.Sandayy:BAACNQAFFIEOAAMKAAYJJSGgAQCJAQAKAAQJtSCgAQCJAQAbAAQJwyAmBAB1AQA1AAQKgSIAAwoACQmFJVcQAPUCABsACAlVJKkGACsDAAoABwlTJlcQAPUCAAAA.Satsao:BAAANQABCgUIBAAAAA==.Sawario:BAAANQADCgMIAwAAAA==.',
Sc='Screwheals:BAAANQAECgIIAwABNQAECgYIEAABAAAAAA==.',
Se='Sellene:BAACNQAFFIESAAIRAAcJoSUDAADPAgARAAcJoSUDAADPAgA1AAQKgSMAAhEACQmzJAsDAE4DABEACQmzJAsDAE4DAAAA.Sellina:BAAANQAECgIIAgABNQAFFAcIEgARAKElAA==.Seneriya:BAAANQABCgIIAgAAAA==.Senorbang:BAAANQAECgQICAAAAA==.Sep:BAABNQAECoEVAAIUAAcJbRuYKwATAgAUAAcJbRuYKwATAgAAAA==.Serenashadow:BAAANQADCgUIBQAAAA==.',
Sh='Shadowflare:BAAANQADCgcIEwAAAA==.Shaggsalt:BAAANQAECggIAwAAAA==.Shalth:BAAANQABCgYIBgAAAA==.Shaolinhunk:BAAANQAECgcIDwAAAA==.Sharks:BAABNQAECoEXAAIaAAgJxRiPGgBPAgAaAAgJxRiPGgBPAgAAAA==.Shawshanks:BAAANQADCgEIAQABNQADCggICQABAAAAAA==.Shazzman:BAAANQADCggICwAAAA==.Shelandria:BAACNQAFFIETAAMJAAcJ9gsCAQAYAgAJAAYJGAwCAQAYAgAiAAMJ+wczAgASAQA1AAQKgSQAAyIACQksIMECAGQDACIACQknIMECAGQDAAkACQlvGsUGAOICAAAA.Shiroee:BAAANQABCggIBwABNQAECgYICQABAAAAAA==.Shoda:BAACNQAFFIELAAMKAAUJwhPNAwAUAQAbAAQJNQ1WBgAmAQAKAAMJqBnNAwAUAQA1AAQKgSMAAxsACQkwIwkQAIYCABsACAm+HQkQAIYCAAoABQmFJTk9AAMCAAAA.Shootrmcgávn:BAAANQAECgMIBgAAAA==.Shreker:BAABNQAECoEXAAIXAAgJxx5mHABkAgAXAAgJxx5mHABkAgAAAA==.',
Si='Sidchatic:BAAANQADCgEIAQAAAA==.Sidebo:BAAANQAECgEIAQAAAA==.Sinhunter:BAAANQAECgQIBQAAAA==.Sirn:BAAANQADCgYICgAAAA==.Sitonmytotem:BAAANQADCgIIAgABNQADCggICQABAAAAAA==.',
Sj='Sjp:BAAANQADCgIIAgABNQAECggIDwABAAAAAA==.',
Sk='Skeetoo:BAAANQAECggIEAAAAA==.Skeetwo:BAAANQADCggICAABNQAECggIEAABAAAAAA==.Skiera:BAAANQADCggICAABNQAECgYIEAABAAAAAA==.Skiplegs:BAAANQAECgcIDwAAAA==.Skorpeo:BAAANQADCggICQAAAA==.',
Sl='Slimes:BAAANQADCgIIAgAAAA==.Slimxx:BAAANQADCgYICgAAAA==.',
Sm='Smargendk:BAAANQADCgYIBwAAAA==.Smargenrog:BAACNQAFFIEJAAIIAAUJJxtZAADsAQAIAAUJJxtZAADsAQA1AAQKgR4AAggACQlRJbUAAL0DAAgACQlRJbUAAL0DAAAA.',
Sn='Snaven:BAAANQAECgEIAgAAAA==.Sneggs:BAAANQADCggIGQAAAA==.Snifellz:BAAANQAECgQIBAAAAA==.Snifflez:BAAANQAECgQICAABNQAECgQIBAABAAAAAA==.Snipermonkey:BAAANQAECgUIDAAAAA==.',
So='Soiled:BAAANQAECgEIAQAAAA==.Solidshaft:BAAANQAECgIIAgAAAA==.Solikar:BAAANQADCggICwAAAA==.Sopheia:BAAANQAECgQIBQAAAA==.Soul:BAABNQAECoEXAAIQAAgJXxybRgB7AgAQAAgJXxybRgB7AgAAAA==.',
Sp='Spek:BAABNQAECoEcAAMZAAkJMyLmEAD+AgAZAAgJ4yLmEAD+AgAUAAIJQg5KmgB2AAAAAA==.Split:BAAANQAECgYIDAAAAA==.Springonion:BAAANQAECggIEQABNQAFFAYIEAAUANgNAA==.',
Sq='Squidward:BAABNQAECoEeAAIDAAkJYSAeBwA0AwADAAkJYSAeBwA0AwAAAA==.',
St='Standardhors:BAAANQADCggICAABNQAECgYIEgABAAAAAA==.Steadchi:BAAANQAECgYIBgAAAA==.Steadyy:BAAANQABCgQIBAAAAA==.Steakburrito:BAAANQADCgcIEQAAAA==.Stedk:BAACNQAFFIEJAAIaAAYJTiG6AABKAgAaAAYJTiG6AABKAgA1AAQKgRsAAhoACQmVJukAAOMDABoACQmVJukAAOMDAAAA.Stepally:BAAANQAFFAQIBAAAAA==.Steven:BAAANQAECgYICgAAAA==.Strongshift:BAAANQAECgEIAQAAAA==.Stygwyggyr:BAAANQAECgYIDgAAAA==.',
Su='Suebird:BAAANQAECgQIBAABNQAECggIFwAXAMceAA==.Sugarzcoat:BAAANQAECgcIDAAAAA==.Sulphurous:BAAANQADCggIDwAAAA==.Supdudejr:BAAANQAECgUIDAAAAA==.Supernovi:BAAANQADCggICAAAAA==.',
Sw='Sweetstache:BAAANQABCgQIBgAAAA==.Swiftus:BAAANQADCgEIAQAAAA==.Swippin:BAAANQADCgQIBAABNQAECgUIBwABAAAAAA==.',
Sy='Sykomike:BAAANQAFFAEIAQAAAA==.Syler:BAABNQAECoEhAAIiAAkJFiIfAwBVAwAiAAkJFiIfAwBVAwAAAA==.Sylár:BAAANQADCggIHAAAAA==.Symbol:BAAANQABCgQIBAAAAA==.Syreal:BAAANQADCgYICAAAAA==.',
['Sä']='Säcred:BAAANQAECgMIBQABNQAECgkJGgAGACAdAA==.',
Ta='Tahlia:BAAANQAECgcIEwAAAA==.Talren:BAAANQAECgEIAQAAAA==.Talìa:BAAANQAECgQIBwAAAA==.Tannadà:BAAANQAECgcIEAAAAA==.Tasari:BAACNQAFFIEOAAIHAAYJ3SEaAABfAgAHAAYJ3SEaAABfAgA1AAQKgSIAAgcACQnHJVAAAOcDAAcACQnHJVAAAOcDAAAA.Taurenadin:BAAANQADCgIIAgAAAA==.Tayson:BAAANQABCgIIAwAAAA==.Tazzdingo:BAAANQABCgUIBQAAAA==.',
Te='Tekain:BAAANQAECgEIAQAAAA==.Tequilla:BAAANQADCgcIBwAAAA==.Terryn:BAAANQAECgEIAQAAAA==.Tesia:BAAANQADCgUICgAAAA==.',
Th='Thedeadlypug:BAAANQADCggICwAAAA==.Theeripper:BAAANQAECgQIBwAAAA==.Thrashwar:BAAANQAECgMIBAAAAA==.Thrustie:BAAANQAECgQIBwAAAA==.Thusios:BAAANQAECgMIBgAAAA==.',
Ti='Tiazz:BAAANQADCgUIBQAAAA==.Tichu:BAAANQAECgUIBQAAAA==.Tiekho:BAAANQADCgUIBQAAAA==.Tifelia:BAAANQADCgYICwAAAA==.Tigorain:BAAANQADCgcIBgAAAA==.Tizirk:BAAANQADCggIDAAAAA==.',
To='Toastybutter:BAAANQADCgYIDAAAAA==.Tonyz:BAAANQAECgcIBwAAAA==.Torrak:BAAANQAECgcIEQAAAA==.Torthie:BAACNQAFFIEOAAIQAAYJuRieAQBAAgAQAAYJuRieAQBAAgA1AAQKgSIAAxAACQnmIk4MAIADABAACQnmIk4MAIADACMAAQmmIT0dAF8AAAAA.Tothdk:BAAANQAFFAYIAQAAAA==.',
Tr='Trale:BAAANQADCgQIBAAAAA==.Treason:BAAANQADCgYIBwABNQADCggIGAABAAAAAA==.Treeage:BAAANQAECgIIAgAAAA==.Tripp:BAAANQAECgEIAQAAAA==.Troeg:BAAANQABCgUIAwAAAA==.Trollerella:BAAANQADCgQIBAABNQAECgkJHAADAJsXAA==.Trollzealot:BAAANQAECgMIAwAAAA==.Tronxx:BAAANQADCgQIBAAAAA==.Troxigar:BAAANQAECgUIBwAAAA==.',
Tu='Tullyspring:BAAANQADCgcICgAAAA==.Turkeysub:BAAANQADCggIDQAAAA==.',
Tv='Tverdydh:BAAANQAECgQIBAAAAA==.Tverdydk:BAAANQAECgMIBwAAAA==.',
Tw='Twertlekat:BAAANQAECgUICQAAAA==.Twinkiez:BAAANQAECgQIBAABNQAECgcIDAABAAAAAA==.Twistkun:BAAANQAECgMIAwAAAA==.',
Un='Unclehog:BAAANQAECgIIAwAAAA==.Unfixable:BAAANQAECgMIAwABNQAFFAQICQABAAAAAQ==.Unplayable:BAAANQAFFAQICQAAAQ==.Unusualhorse:BAAANQAECgYIEgAAAA==.',
Uu='Uunfar:BAABNQAECoEYAAIUAAgJjiWdBABtAwAUAAgJjiWdBABtAwAAAA==.',
Va='Valedia:BAAANQAECgUIBwAAAA==.Valn:BAAANQAECgQICAAAAA==.Valtross:BAAANQADCggIGAAAAA==.Vangough:BAAANQAECgcIEgAAAA==.Vayu:BAAANQADCgQIBAAAAA==.',
Ve='Velvetvixen:BAAANQAECgUICgAAAA==.',
Vi='Viper:BAABNQAECoEXAAMiAAgJARWPDwBDAgAiAAgJARWPDwBDAgAJAAMJMRPcKwDOAAAAAA==.',
Vl='Vlad:BAAANQAECgYICgAAAA==.',
Vo='Voreâu:BAAANQADCgEIAQAAAA==.Vosslar:BAAANQAECgQICQAAAA==.Vosslarr:BAAANQADCgMIAwAAAA==.',
Vv='Vvarden:BAAANQADCggIEgAAAA==.',
['Vî']='Vîper:BAAANQADCggIFAAAAA==.',
Wa='Waarrlockk:BAACNQAFFIEMAAMEAAUJfhmcAwC+AAAGAAMJeBfmBgAAAQAEAAIJhRycAwC+AAA1AAQKgSMAAwQACQkfJXUBAFIDAAQACQmcH3UBAFIDAAYABwksJOEPAOICAAAA.Walrusrider:BAAANQAECgUICgAAAA==.Wang:BAABNQAECoEaAAILAAkJBRoLCgCzAgALAAkJBRoLCgCzAgAAAA==.Warbird:BAAANQAECgUICgAAAA==.Warhmonger:BAAANQADCggICAAAAA==.Wassy:BAAANQAECgYICAAAAA==.Watharaim:BAAANQADCgUIBQABNQAECgUIEAABAAAAAA==.',
We='Wemgobyama:BAABNQAECoEhAAQbAAkJeiOqBgArAwAbAAgJpiOqBgArAwAKAAIJmiP4nwC7AAAkAAEJVgDeDAATAAAAAA==.',
Wh='Whispy:BAAANQABCgIIAgAAAA==.Whm:BAAANQAECgQIBAAAAA==.Whobe:BAAANQAECgcIEwAAAA==.',
Wi='Witherfang:BAAANQAECgMIBQAAAA==.Wizsera:BAAANQAECgIIAgABNQAECgcIGwAZAPYdAA==.Wizshock:BAABNQAECoEbAAIZAAcJ9h3HJABPAgAZAAcJ9h3HJABPAgAAAA==.',
Wn='Wnred:BAACNQAFFIEMAAMgAAUJ1BuFAQCFAQAgAAQJXyGFAQCFAQAhAAIJHgidAgClAAA1AAQKgSMAAyEACQmdJSoBAE4DACAACAl+JbsCAFYDACEACQk0ISoBAE4DAAAA.',
Wo='Wombly:BAAANQADCggIDAAAAA==.Womboree:BAAANQAECgYIDQAAAA==.Wonderful:BAAANQADCgcIAgAAAA==.Woobie:BAAANQADCgEIAQAAAA==.',
Xa='Xanarius:BAAANQAECgUIBQAAAA==.',
Ye='Yellowslice:BAAANQADCgIIAgAAAA==.Yeofp:BAAANQADCgUIBQAAAA==.',
Yk='Ykime:BAAANQADCgEIAQAAAA==.',
Yu='Yukarna:BAAANQAECgYIDAAAAA==.',
Za='Zaafkiel:BAABNQAECoEWAAQfAAcJlxVUGABTAQAfAAUJ9hZUGABTAQAVAAYJhApZegAsAQANAAQJqAQjgwDIAAAAAA==.Zabuza:BAAANQADCgUIBQAAAA==.Zanaroth:BAAANQADCggIGQAAAA==.Zandrissil:BAEANQADCgYIBgABNQAECgQICAABAAAAAA==.Zarafie:BAEANQADCgYIDAABNQAECgQICAABAAAAAA==.Zaraphym:BAEANQAECgQICAAAAA==.Zarazlow:BAEANQADCgQIBAABNQAECgQICAABAAAAAA==.Zarreh:BAAANQADCggIHQAAAA==.',
Ze='Zephyrine:BAAANQADCgQIBAAAAA==.',
Zh='Zhuzhu:BAAANQAECgYIDQAAAA==.',
Zi='Zigy:BAABNQAECoEYAAIlAAgJiiDmAgD1AgAlAAgJiiDmAgD1AgAAAA==.',
Zo='Zoeý:BAAANQADCgcIBwAAAA==.Zombie:BAAANQAECgQICQAAAA==.',
Zu='Zukko:BAAANQAECgIIAgAAAA==.Zulkaris:BAAANQADCggICAAAAA==.Zuroxxar:BAEANQAECgIIAgABNQAECgQICAABAAAAAA==.Zuwitsudh:BAAANQADCgQIBAAAAA==.',
Zy='Zynny:BAAANQAECgYIDAAAAA==.',
['Zë']='Zëll:BAAANQADCggIDwAAAA==.',
['Åa']='Åa:BAAANQAECgEIAgABNQAECggIFAABAAAAAA==.',
['Ðo']='Ðolo:BAAANQADCgQICAABNQAECgQIBwABAAAAAA==.',
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
