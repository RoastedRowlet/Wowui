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

local lookup = {'Warlock-Demonology','Paladin-Protection','Warrior-Fury','Warrior-Arms','Paladin-Retribution','Paladin-Holy','Evoker-Augmentation','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Monk-Mistweaver','DemonHunter-Devourer','Druid-Guardian','Monk-Brewmaster','Unknown-Unknown','Druid-Restoration','Monk-Windwalker','Priest-Discipline','Hunter-BeastMastery','Shaman-Elemental','Warrior-Protection','Warlock-Destruction','Druid-Balance','DemonHunter-Havoc','DeathKnight-Blood','Shaman-Restoration','Hunter-Survival','Hunter-Marksmanship','Evoker-Preservation','Rogue-Outlaw','Mage-Arcane','Priest-Shadow','Rogue-Subtlety','Druid-Feral','Evoker-Devastation','Warlock-Affliction','Shaman-Enhancement','Rogue-Assassination',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aava:BAAALgADCgEJAQAAAA==.',
Ab='Abattoire:BAAALgADCgYJBgAAAA==.',
Ad='Adivion:BAAALgAECgkJCwAAAA==.Adrenelian:BAABLgAECn8cAAIBAAgJEwkfXgBGAQABAAgJEwkfXgBGAQAAAA==.',
Ah='Ahgro:BAAALgAECgMJAwAAAA==.',
Ak='Akroma:BAABLgAECn8eAAICAAYJ3xuhEQCuAQACAAYJ3xuhEQCuAQAAAA==.',
Al='Alecwar:BAACLgAFFH8GAAIDAAQJCRLOEwAwAQADAAQJCRLOEwAwAQAuAAQKfzAAAgMACAlyH20PADcCAAMACAlyH20PADcCAAAA.Allyon:BAAALgAECgYJBgAAAA==.Altezio:BAACLgAFFH8GAAIEAAIJ6h1DFwCjAAAEAAIJ6h1DFwCjAAAuAAQKfzEAAgQACQkhINUBAPQCAAQACQkhINUBAPQCAAAA.',
Am='Amorial:BAAALgAECgYJCQAAAA==.',
An='Andransonis:BAAALgADCgUJBQAAAA==.Ankarna:BAAALgAECgEJAQAAAA==.Anklespanker:BAAALgAECgYJAgAAAA==.Annegwish:BAABLgAECn8oAAMFAAkJ5ws+VACDAQAFAAkJ5ws+VACDAQAGAAcJpwnzRABkAQAAAA==.Anonymous:BAAALgAECgQJBAAAAA==.Antashaman:BAAALgAECgUJCQAAAA==.',
Ap='Apah:BAAALgADCgEJAQAAAA==.Apokalypsis:BAAALgADCgUJCgAAAA==.',
Ar='Archodreki:BAABLgAECn8kAAIHAAkJ6xONEwD1AQAHAAkJ6xONEwD1AQAAAA==.Ardithan:BAABLgAECn8eAAIIAAkJuCDjJADfAgAIAAkJuCDjJADfAgAAAA==.Argah:BAAALgADCgMJAwAAAA==.Arilm:BAAALgADCgMJAwAAAA==.Arthuur:BAABLgAECn8zAAIJAAkJ1CJVBwAIAwAJAAkJ1CJVBwAIAwAAAA==.Arynthyan:BAABLgAECn8ZAAIKAAkJEBnIEABeAgAKAAkJEBnIEABeAgAAAA==.Arystrasza:BAAALgADCgUJBQABLgAECgkJHwALAIsgAA==.Aryzhuque:BAABLgAECn8fAAILAAkJiyA3BAArAwALAAkJiyA3BAArAwAAAA==.Arzen:BAAALgAECgIJAgAAAA==.',
As='Ashana:BAAALgADCgYJBgAAAA==.Ashmandious:BAAALgAECgcJEAAAAA==.Asparavoid:BAABLgAECn8kAAIMAAkJ1x/BCABDAwAMAAkJ1x/BCABDAwAAAA==.Aspyn:BAAALgAECgEJAgAAAA==.Assandros:BAABLgAECn8fAAINAAkJ4SRNAADEAwANAAkJ4SRNAADEAwAAAA==.',
At='Ataraxia:BAAALgADCgEJAQAAAA==.Athleta:BAEALgAECggJCAABLgAFFAcJHAAOAFIZAA==.',
Au='Aurilian:BAAALgADCgQJBAAAAA==.',
Av='Average:BAAALgADCgkJKgAAAA==.',
Ay='Ayku:BAAALgAECgEJAQAAAA==.',
Az='Azrox:BAAALgADCgUJBQAAAA==.Azurien:BAAALgAECgMJAwAAAA==.',
Ba='Baboo:BAAALgAECgEJAQAAAA==.Bad:BAAALgAECgIJAwAAAA==.Bajablastois:BAAALgAECgEJAQABLgAECgkJEgAPAAAAAA==.Baldbud:BAAALgADCgQJBAABLgAECgcJEAAPAAAAAA==.Balgrim:BAAALgADCgQJBwAAAA==.Banthum:BAABLgAECn8uAAIQAAgJ+xO3KADGAQAQAAgJ+xO3KADGAQAAAA==.',
Be='Bearbayt:BAAALgAECgUJBgAAAA==.Bearlough:BAAALgAECgYJCgAAAA==.Beerhelmet:BAABLgAECn8aAAMRAAYJmBY8KwCEAQARAAYJmBY8KwCEAQALAAYJtQOxSAC2AAAAAA==.Bertarious:BAAALgADCgcJEQAAAA==.Beryl:BAABLgAECn8cAAMSAAgJqA0uIQBmAQASAAgJBQkuIQBmAQAKAAYJAQ3HPwA6AQAAAA==.',
Bi='Biggyword:BAABLgAECn8jAAMSAAgJtSFwBQDrAgASAAgJoCFwBQDrAgAKAAMJEyEySgAQAQAAAA==.',
Bl='Bleddyn:BAAALgADCgYJBgAAAA==.Blorbusdorp:BAAALgAECgcJEgAAAA==.',
Bo='Bobsgirl:BAABLgAECn8VAAITAAkJUg+sIwAwAgATAAkJUg+sIwAwAgAAAA==.Bolord:BAAALgAECgUJBQAAAA==.Boodrios:BAABLgAECn8oAAIUAAgJhQt9LQAzAQAUAAgJhQt9LQAzAQAAAA==.',
Br='Braleanna:BAAALgAECgEJAgAAAA==.Brewmaster:BAAALgADCgIJAgABLgAECggJIgASAGkiAA==.Bruke:BAABLgAECn8VAAIVAAkJMxyqCACVAgAVAAkJMxyqCACVAgAAAA==.',
Bu='Buffsyou:BAAALgAECgYJEQAAAA==.Bugge:BAABLgAECn8YAAIQAAgJGxs8FQBXAgAQAAgJGxs8FQBXAgAAAA==.Bulldozzer:BAAALgADCgYJBwAAAA==.Bus:BAABLgAFFH8WAAINAAkJsSEFAABNAwANAAkJsSEFAABNAwAAAA==.',
Ca='Catastrophe:BAABLgAECn8gAAIWAAgJXA2NCwA4AQAWAAgJXA2NCwA4AQAAAA==.',
Cb='Cbat:BAABLgAECn8qAAINAAgJ+B3tBQBJAgANAAgJ+B3tBQBJAgAAAA==.',
Cd='Cdicepalta:BAAALgAECgYJCAABLgAFFAIJAwAPAAAAAA==.',
Ce='Celes:BAAALgAECgYJEwAAAA==.',
Ch='Chapulín:BAAALgAFFAEJAQABLgAECggJJAAVAJ4XAA==.',
Ci='Cindér:BAAALgAECgEJAgAAAA==.Cinimist:BAABLgAECn8VAAIXAAkJNhGGGQClAQAXAAkJNhGGGQClAQAAAA==.',
Co='Coinlock:BAAALgAECgYJDwAAAA==.Coinslot:BAAALgAECgMJBAABLgAECgYJDwAPAAAAAA==.Compact:BAAALgAECgEJAQABLgAECggJIgASAGkiAA==.Concubine:BAABLgAECn8eAAIYAAcJ1w0KLABoAQAYAAcJ1w0KLABoAQAAAA==.Confettii:BAAALgAECgMJAwABLgAECgYJFgATACEiAA==.Conän:BAAALgADCgMJAwAAAA==.Cordie:BAAALgADCgcJDQAAAA==.Cowdrogo:BAAALgAECgUJCwAAAA==.',
Cr='Crippled:BAAALgADCgEJAQAAAA==.Crosis:BAAALgADCgcJBwAAAA==.Cryhard:BAAALgAECgcJAwAAAA==.',
Cu='Cuchulainn:BAAALgADCgIJAgAAAA==.Curses:BAAALgADCgEJAQAAAA==.',
Da='Dagal:BAAALgAFFAIJAwAAAA==.Daiju:BAAALgAECgEJAQABLgAECgYJEwAPAAAAAA==.Dalaran:BAABLgAECn8dAAIRAAgJRBhSFADGAQARAAgJRBhSFADGAQAAAA==.Daliron:BAAALgAECgEJAQAAAA==.Dalus:BAAALgADCgIJAgAAAA==.Danea:BAAALgAECgUJCwAAAA==.Dankzìlla:BAABLgAECn8cAAIZAAkJrRw4CwBiAgAZAAkJrRw4CwBiAgAAAA==.Darach:BAAALgAECgEJAQAAAA==.Dawny:BAABLgAECn8jAAMaAAkJJxmAIQAWAgAaAAkJJxmAIQAWAgAUAAUJ4BgJQQBFAQAAAA==.',
De='Dealain:BAAALgAECgUJBQAAAA==.Deathtrash:BAAALgADCgQJBAAAAA==.Decaran:BAABLgAECn8cAAIIAAkJ0hlhLADBAgAIAAkJ0hlhLADBAgAAAA==.Dectodraco:BAAALgADCgIJAgAAAA==.Dedpool:BAAALgAECgYJDgAAAA==.Deftinwolf:BAAALgAECgMJAwAAAA==.Delinara:BAABLgAECn8WAAIbAAcJ3w8wHABvAQAbAAcJ3w8wHABvAQAAAA==.Dethndk:BAAALgAECgYJBgAAAA==.',
Do='Doorjob:BAABLgAECn8fAAIYAAkJCx+cCADZAgAYAAkJCx+cCADZAgAAAA==.',
Dr='Drakemage:BAAALgAECgkJBAAAAA==.Dreadravens:BAAALgADCgUJBQAAAA==.Dreamily:BAABLgAECn8ZAAIXAAkJUhHAHQASAgAXAAkJUhHAHQASAgAAAA==.Driamn:BAAALgADCggJEAAAAA==.',
Dy='Dydy:BAAALgAECgEJAgAAAA==.',
Ea='Eame:BAABLgAECn8hAAIDAAkJjg1OJQB9AQADAAkJjg1OJQB9AQAAAA==.',
Eh='Ehnder:BAAALgADCgEJAQAAAA==.',
El='Elandron:BAAALgAECgIJAgAAAA==.Elenyia:BAABLgAECn8eAAIGAAYJXhqXIgClAQAGAAYJXhqXIgClAQAAAA==.Elfredo:BAAALgADCgEJAQAAAA==.Elia:BAABLgAECn8fAAMTAAkJlh23CwDkAgATAAkJlh23CwDkAgAcAAYJYgcCVAD7AAAAAA==.Elisandre:BAAALgAECgYJBgAAAA==.Ellexis:BAAALgAECgIJAQABLgAECggJLAATAFEiAA==.Elmo:BAABLgAECn8pAAMJAAkJ5iB+IQA8AgAJAAkJ5iB+IQA8AgAZAAEJrxzfPABNAAAAAA==.Elzä:BAABLgAECn8sAAITAAgJUSLgEACCAgATAAgJUSLgEACCAgAAAA==.',
Em='Emaria:BAAALgAECgYJDAAAAA==.Emergencii:BAAALgADCgIJAgABLgAECgYJFgATACEiAA==.',
En='Ennead:BAABLgAECn8oAAMWAAgJzA8GCwBAAQAWAAcJaxEGCwBAAQABAAgJKghKZwAxAQAAAA==.Entranced:BAABLgAECn8qAAIYAAgJTiO1BQCVAgAYAAgJTiO1BQCVAgAAAA==.Entropius:BAABLgAECn8tAAIJAAgJEBkFPADLAQAJAAgJEBkFPADLAQAAAA==.',
Er='Eranica:BAAALgADCgEJAQAAAA==.Ereinion:BAABLgAECn8bAAIDAAcJaRWJNQDSAQADAAcJaRWJNQDSAQAAAA==.Erkromerr:BAAALgAECgEJAgAAAA==.',
Ey='Eyb:BAAALgADCgcJDQAAAA==.',
Ez='Ezayle:BAABLgAECn8YAAIFAAkJsQjNYwC6AQAFAAkJsQjNYwC6AQAAAA==.Ezsolator:BAAALgAECgQJBAAAAA==.',
['Eï']='Eïs:BAABLgAECn8tAAIdAAkJFg/CDAC8AQAdAAkJFg/CDAC8AQAAAA==.',
Fe='Fearsmage:BAAALgAECgIJAgAAAA==.Fenris:BAAALgADCgYJCAAAAA==.',
Fo='Fonzie:BAABLgAECn8eAAIUAAkJGhWpGwA1AgAUAAkJGhWpGwA1AgAAAA==.Foregotten:BAACLgAFFH8GAAIXAAMJnQ+DHgDXAAAXAAMJnQ+DHgDXAAAuAAQKfyMAAhcACAn/HAsVAGkCABcACAn/HAsVAGkCAAAA.',
Fr='Fragile:BAAALgAFFAEJAQAAAA==.Freezee:BAAALgADCgkJEQAAAA==.Frostietute:BAABLgAECn8ZAAIIAAgJDxwMLwAaAgAIAAgJDxwMLwAaAgAAAA==.',
Fu='Fudd:BAAALgADCgQJBwAAAA==.',
Ga='Galen:BAAALgADCgEJAwAAAA==.Galsin:BAAALgAECgYJDwABLgAFFAIJAwAPAAAAAA==.Gamboa:BAAALgAECgYJEwAAAA==.Gandulfgray:BAAALgADCgMJAwAAAA==.Gauche:BAABLgAECn8rAAMRAAgJPSFtCAB4AgARAAgJPSFtCAB4AgALAAYJORqmOQDxAAAAAA==.Gazreiale:BAABLgAECn8eAAIeAAkJ0RPQAwD2AQAeAAkJ0RPQAwD2AQAAAA==.',
Gi='Giddie:BAABLgAECn8pAAMaAAkJ8BKiMACVAQAaAAkJ8BKiMACVAQAUAAYJnQ7iVADyAAAAAA==.Giddygos:BAAALgADCgIJAgAAAA==.Girthquake:BAAALgAECgUJEAAAAA==.',
Go='Goldylocks:BAAALgADCgcJBwAAAA==.',
Gr='Grass:BAABLgAECn8bAAIfAAcJPBMKCAB6AQAfAAcJPBMKCAB6AQAAAA==.Grimtree:BAAALgAECgIJAgAAAA==.Gromnash:BAAALgADCgcJDQABLgAFFAYJFwATAAsiAA==.',
Gu='Guldanica:BAAALgADCggJFgAAAA==.',
Gw='Gwaine:BAABLgAECn8WAAIVAAcJzRczEgB1AQAVAAcJzRczEgB1AQAAAA==.Gwyndolín:BAAALgAFFAEJAgAAAA==.',
Gy='Gyaatso:BAAALgADCgEJAQAAAA==.',
Ha='Halima:BAAALgADCgUJBQAAAA==.',
He='Helgrund:BAAALgADCgcJBwAAAA==.Hellfyrê:BAAALgAECgEJAgAAAA==.Heritikyl:BAABLgAECn8pAAIQAAkJDSOmBwADAwAQAAkJDSOmBwADAwAAAA==.Heritikyldin:BAAALgAECggJDAAAAA==.',
Hi='Hibou:BAAALgADCgEJAQAAAA==.Hiim:BAABLgAECn8UAAIXAAgJvRC9KAC5AQAXAAgJvRC9KAC5AQAAAA==.',
Ho='Holycast:BAAALgAECgQJBAAAAA==.Holyhero:BAABLgAECn8eAAMgAAkJuR7zCQDkAgAgAAkJuR7zCQDkAgAKAAEJcQeFgQAwAAAAAA==.',
Hu='Huntréss:BAAALgADCgUJBQAAAA==.',
Ic='Iceehot:BAAALgAECgEJAQAAAA==.',
Ig='Ignasio:BAAALgADCgYJBgAAAA==.',
Il='Ilikepepsi:BAAALgADCgMJAwAAAA==.',
Im='Imposturr:BAAALgADCgkJEQAAAA==.',
In='Insanitii:BAAALgADCgYJDQABLgAECgYJFgATACEiAA==.',
Ip='Iportyou:BAAALgAECgYJEAAAAA==.',
Ja='Jabjo:BAABLgAECn8kAAIGAAgJFSChDgBiAgAGAAgJFSChDgBiAgAAAA==.Jaira:BAAALgAECgcJDQAAAA==.Janorune:BAAALgADCgMJAwAAAA==.Jastinasta:BAAALgADCgMJAwAAAA==.',
Je='Jeudeu:BAAALgADCgYJCwAAAA==.',
Ka='Kabira:BAAALgAECgEJAwAAAA==.Kaimed:BAAALgAECgEJAwAAAA==.Kaji:BAAALgADCgYJCQAAAA==.Katalia:BAAALgAECgEJAQABLgAECgYJFQATAPMWAA==.Katyparry:BAAALgAECgQJBAAAAA==.',
Ke='Keign:BAAALgAECgEJAgAAAA==.Keljeon:BAAALgAECgEJAQAAAA==.',
Ki='Kigorr:BAAALgAECgMJAwAAAA==.Kinnick:BAAALgAECgYJDwAAAA==.Kinoloy:BAAALgADCgEJAQAAAA==.',
Ko='Konidus:BAAALgAECgQJBQAAAA==.Korna:BAAALgAECgEJAwAAAA==.',
Kr='Kronosdh:BAAALgADCgQJBAABLgAECggJJAAFAPMhAA==.Kronosmonk:BAAALgAECgYJDwABLgAECggJJAAFAPMhAA==.Kronoswarr:BAAALgAECgYJDwAAAA==.',
Ku='Kunaee:BAAALgAECgUJDAAAAA==.Kuzcó:BAAALgAECgYJCwAAAA==.Kuzume:BAAALgADCgcJCAABLgAECgYJFQATAPMWAA==.',
Ky='Kyrius:BAABLgAECn8jAAIaAAgJXhcvHgAEAgAaAAgJXhcvHgAEAgAAAA==.',
La='Lausia:BAABLgAECn8uAAIIAAgJnxbyPADkAQAIAAgJnxbyPADkAQABLgAECgkJIQADAI4NAA==.',
Ld='Ldyrose:BAAALgAECgQJDAAAAA==.',
Le='Legomaaggro:BAAALgAECgYJEgAAAA==.Lewtiefroopz:BAABLgAECn8gAAITAAcJuxvhPACXAQATAAcJuxvhPACXAQAAAA==.',
Li='Lilaria:BAAALgAECgQJCgABLgAFFAIJAwAPAAAAAA==.Lilblade:BAAALgAECgQJBQAAAA==.Liquidrichrd:BAAALgADCgkJCQAAAA==.Liquors:BAAALgADCggJCAAAAA==.',
Lo='Logana:BAAALgAECgYJBgAAAA==.Loxiteria:BAABLgAECn8cAAIhAAkJlRHxEwB2AgAhAAkJlRHxEwB2AgAAAA==.',
Lu='Luciang:BAAALgADCgQJBAAAAA==.Lunarkitsune:BAABLgAECn8ZAAITAAYJMgXhhgDMAAATAAYJMgXhhgDMAAAAAA==.Lusande:BAAALgADCgYJCQAAAA==.',
Ly='Lyzardwyzard:BAAALgADCgYJCQAAAA==.',
['Lì']='Lìlìth:BAABLgAECn8kAAIMAAgJRBhkLgDEAQAMAAgJRBhkLgDEAQAAAA==.',
Ma='Maantra:BAAALgADCgUJBgAAAA==.Macabre:BAAALgADCgkJCgAAAA==.Magiclmao:BAAALgAECgQJBQAAAA==.Magnificò:BAABLgAECn8uAAIZAAgJUAtDHQAWAQAZAAgJUAtDHQAWAQAAAA==.Makani:BAABLgAECn8eAAINAAYJgQlsJwCWAAANAAYJgQlsJwCWAAAAAA==.Malarix:BAAALgAECgQJBAABLgAECgYJDQAPAAAAAA==.Malory:BAABLgAECn8tAAIVAAkJuyRHAwAnAwAVAAkJuyRHAwAnAwAAAA==.Malzahär:BAACLgAFFH8YAAMWAAUJwxuRAgBTAQAWAAQJwxuRAgBTAQABAAQJIxExUADeAAAuAAQKfyYAAxYACQk7I9UDAKwCABYABwn6JNUDAKwCAAEABwmbIZcPAJsCAAAA.',
Me='Merp:BAAALgAECgcJBwAAAA==.Messi:BAACLgAFFH8PAAIaAAQJiw/zIQAEAQAaAAQJiw/zIQAEAQAuAAQKf0EAAhoACQn1IE4DAEUDABoACQn1IE4DAEUDAAAA.',
Mi='Mielk:BAAALgADCgEJAQAAAA==.Milkan:BAAALgAECgIJAgAAAA==.Minara:BAAALgAECgEJAgAAAA==.Miniraven:BAAALgAECgIJAgAAAA==.Minniedonut:BAAALgAECgEJAQAAAA==.',
Mu='Muffintop:BAABLgAECn8cAAIJAAgJkh72IwAuAgAJAAgJkh72IwAuAgAAAA==.Muki:BAABLgAECn8cAAIRAAgJBQyAJAA6AQARAAgJBQyAJAA6AQAAAA==.',
My='Mystikal:BAAALgADCgYJBgABLgAECggJKwAZAIwUAA==.Mythrondrir:BAAALgADCgYJBgAAAA==.Mythälus:BAAALgAECggJCAAAAA==.',
Na='Nanabanana:BAAALgADCgIJAgAAAA==.Nashumaya:BAABLgAECn8aAAIaAAYJMwP7bQCgAAAaAAYJMwP7bQCgAAAAAA==.Nathansbb:BAABLgAECn8yAAIFAAkJRSZ6AQBsAwAFAAkJRSZ6AQBsAwAAAA==.',
Ne='Neosnÿper:BAABLgAECn8rAAMQAAgJ4R2dDQCsAgAQAAgJ4R2dDQCsAgAiAAYJXAuqGAA4AQAAAA==.',
Ni='Nielic:BAAALgAECgYJEQAAAA==.Nimbus:BAACLgAFFH8TAAIHAAQJuxZ8FwA2AQAHAAQJuxZ8FwA2AQAuAAQKfz8AAwcACQlSJIgCADEDAAcACQlSJIgCADEDACMAAgnKETM2AGQAAAEuAAUUCAkWAAcATBYA.Nitrin:BAAALgADCgYJBgAAAA==.',
No='Norrahh:BAAALgAECgUJEQAAAA==.Noteeth:BAAALgAECgcJEAAAAA==.Nozzle:BAAALgAECgEJAQAAAA==.',
Ny='Nyclon:BAAALgAECgYJDAAAAA==.Nyru:BAAALgADCgYJCgAAAA==.',
['Ní']='Níto:BAAALgAECgEJAQAAAA==.',
Or='Ori:BAAALgAECgYJAgAAAA==.Oriimis:BAABLgAECn8RAAIMAAgJZxvlKADeAQAMAAgJZxvlKADeAQAAAA==.Orion:BAABLgAECn8vAAIIAAkJkQgNWgCOAQAIAAkJkQgNWgCOAQAAAA==.',
Pa='Palanar:BAAALgADCgYJBgAAAA==.',
Pe='Penelopè:BAABLgAECn8WAAIOAAgJkx4AEwB6AgAOAAgJkx4AEwB6AgABLgAECggJJAAVAJ4XAA==.Penelópe:BAAALgADCgcJBwABLgAECggJJAAVAJ4XAA==.Penný:BAABLgAECn8kAAIVAAgJnherEgDfAQAVAAgJnherEgDfAQAAAA==.Peondashaman:BAAALgAECggJEAAAAA==.Pepino:BAAALgAECgYJEQAAAA==.',
Pf='Pflanlock:BAAALgAECgEJAQAAAA==.',
Ph='Phinx:BAABLgAECn8eAAIJAAkJ+gjhYQDOAQAJAAkJ+gjhYQDOAQAAAA==.Phocheux:BAAALgAECgYJEwAAAA==.Phulgoth:BAAALgAECgQJBAAAAA==.',
Pi='Picklericks:BAAALgADCgMJBQAAAA==.Pierogi:BAABLgAECn8hAAIUAAgJPhvjFADvAQAUAAgJPhvjFADvAQAAAA==.',
Po='Pockit:BAAALgAECgEJAgAAAA==.Poetrii:BAABLgAECn8WAAITAAYJISK+LwDLAQATAAYJISK+LwDLAQAAAA==.Pomchow:BAAALgADCgQJBAAAAA==.Pomickyal:BAABLgAECn8uAAIBAAgJawsLWABWAQABAAgJawsLWABWAQAAAA==.Pomymoth:BAAALgADCgYJBgAAAA==.Ponn:BAABLgAECn8iAAMSAAgJaSKODwBFAgASAAgJaSKODwBFAgAgAAUJKBRcMwD4AAAAAA==.Ponyo:BAAALgAECgYJBgABLgAECggJJAAVAJ4XAA==.Poonswatter:BAAALgAECgYJEAAAAA==.Portails:BAAALgADCgMJAwAAAA==.',
Ps='Psychstorm:BAAALgAECgIJBQAAAA==.',
Qu='Quantumleaf:BAAALgADCgcJBwAAAA==.Quendeia:BAACLgAFFH8JAAILAAYJCxMACgC7AQALAAYJCxMACgC7AQAuAAQKfyAABAsACAl/HxwTADQCAAsABwkzIxwTADQCAA4ABgkiA2pfAMQAABEAAQl5BGCGACoAAAAA.',
Ra='Raeline:BAAALgADCgcJDgABLgADCgcJGgAPAAAAAA==.Ragnärok:BAABLgAECn8YAAMaAAkJORBdNACyAQAaAAkJORBdNACyAQAUAAQJ8RRRWADkAAAAAA==.Rats:BAAALgADCgcJDAAAAA==.',
Re='Recursion:BAACLgAFFH8GAAMkAAMJigcTBADbAAAkAAMJigcTBADbAAAWAAEJtQFmHQA3AAAuAAQKfygABCQACAnuEu0IAGsBACQABwkwFe0IAGsBABYABwkCELsrABEBAAEABAlZCCPTALQAAAAA.Reverii:BAAALgAECgIJAgABLgAECgYJFgATACEiAA==.Rexisias:BAACLgAFFH8NAAITAAQJZxuTFQBVAQATAAQJZxuTFQBVAQAuAAQKfysAAhMACQlZJNUEABADABMACQlZJNUEABADAAAA.Reígn:BAABLgAECn8rAAIZAAgJjBRdEgCSAQAZAAgJjBRdEgCSAQAAAA==.',
Ri='Riaglais:BAAALgAECgUJCwAAAA==.Rinahfire:BAAALgAECgkJEQAAAA==.',
Rj='Rj:BAABLgAECn8aAAIJAAYJZhmcdAAxAQAJAAYJZhmcdAAxAQAAAA==.',
Ro='Rocky:BAAALgAECgQJBAABLgAECgYJGgARAJgWAA==.Roomfourdy:BAAALgADCgEJAQAAAA==.Roughbbq:BAAALgAECgYJDAABLgAECgYJDgAPAAAAAA==.Roundtwo:BAAALgADCgkJEgAAAA==.Roxi:BAAALgAECgYJCwAAAA==.',
Rt='Rtpopham:BAAALgAECgQJBAAAAA==.',
Ru='Rumblebumble:BAAALgAECgUJBQAAAA==.',
Sa='Saedri:BAAALgADCgEJAQAAAA==.Saikus:BAAALgAECgYJDQAAAA==.Saloman:BAAALgADCgMJBQABLgAECgYJDwAPAAAAAA==.Sanguinus:BAAALgADCgkJCQAAAA==.Saphrin:BAABLgAECn8oAAIYAAgJsRifDQDoAQAYAAgJsRifDQDoAQAAAA==.Saphya:BAAALgAECgQJBAAAAA==.Sarapho:BAABLgAECn8VAAITAAYJ8xbbVwBhAQATAAYJ8xbbVwBhAQAAAA==.Satoru:BAAALgADCgMJAwAAAA==.',
Sc='Scubasteve:BAAALgADCgcJCQAAAA==.Scurus:BAAALgAECgYJDAAAAA==.',
Se='Selynis:BAAALgADCgUJBQAAAA==.Selynne:BAABLgAECn8fAAIFAAkJBBs4GwDGAgAFAAkJBBs4GwDGAgAAAA==.Servingcvnt:BAAALgADCgYJDAAAAA==.',
Sh='Shadowfern:BAAALgADCgEJAgABLgAECgYJFQATAPMWAA==.Shadowmnk:BAAALgAECgEJAQAAAA==.Shadows:BAAALgAECgIJAwAAAA==.Shamanizeds:BAAALgAECgQJCAAAAA==.Shameas:BAAALgAECgQJBAAAAA==.Shammeltoe:BAABLgAECn8aAAIaAAYJpBsFJgDSAQAaAAYJpBsFJgDSAQAAAA==.Sheezee:BAAALgAECgcJCAAAAA==.Shenn:BAAALgADCgkJEgAAAA==.Shifted:BAAALgADCgYJBgABLgAECggJKwAZAIwUAA==.Shotgirl:BAAALgADCgEJAQAAAA==.',
Si='Siello:BAAALgAECgQJBwAAAA==.Sillynda:BAAALgAECgQJBAAAAA==.Silversnipe:BAAALgAECgcJDQAAAA==.Sindorei:BAABLgAECn8mAAITAAkJVw8FLgDTAQATAAkJVw8FLgDTAQAAAA==.',
Sj='Sj:BAABLgAECn8XAAIGAAcJfyFREQCIAgAGAAcJfyFREQCIAgABLgAFFAgJGAAIAHgjAA==.',
Sk='Skye:BAAALgADCgkJEQABLgAFFAMJBgAXAJ0PAA==.',
Sl='Slagathore:BAABLgAECn8vAAIBAAkJuhHiMADVAQABAAkJuhHiMADVAQAAAA==.Slagathorne:BAAALgADCgYJBgABLgAECgkJLwABALoRAA==.Slegolas:BAABLgAECn8nAAQcAAkJpyM1CAAbAwAcAAgJ0CM1CAAbAwATAAUJWCIzQwCAAQAbAAEJ6hvVQQBQAAAAAA==.Slicindomes:BAAALgADCgMJAwAAAA==.Slizepal:BAAALgADCgQJBAAAAA==.',
Sm='Smashe:BAAALgAECgQJBQAAAA==.',
So='Soggy:BAAALgADCgMJAwAAAA==.Solazreiale:BAAALgAECgUJCgAAAA==.Somers:BAABLgAECn8eAAIDAAgJPhCMJACCAQADAAgJPhCMJACCAQAAAA==.',
Sp='Spellbind:BAABLgAECn8aAAIIAAYJRRz8XACHAQAIAAYJRRz8XACHAQAAAA==.Spudnasty:BAAALgADCgcJBwAAAA==.',
St='Starstorms:BAABLgAECn8pAAIQAAgJzhPcJQDZAQAQAAgJzhPcJQDZAQAAAA==.',
Su='Summatime:BAABLgAECn8WAAIUAAgJgBY+NACHAQAUAAgJgBY+NACHAQAAAA==.',
Sw='Swiftiez:BAAALgADCgMJAwAAAA==.',
Sy='Syara:BAAALgAECggJCAAAAA==.',
['Sö']='Sölair:BAAALgAECgYJBwAAAA==.',
Ta='Taie:BAABLgAECn8WAAIlAAYJQgpPFQDqAAAlAAYJQgpPFQDqAAAAAA==.',
Te='Terkerjobs:BAAALgADCgEJAQAAAA==.Teshala:BAAALgAECgUJEQAAAA==.Tetanei:BAAALgAECgUJBgAAAA==.',
Th='Thalandra:BAAALgAECgUJCgAAAA==.Theft:BAAALgADCgUJBQAAAA==.Theory:BAAALgAFFAIJAwAAAA==.Therapii:BAAALgAECgUJDQABLgAECgYJFgATACEiAA==.Thoraden:BAAALgADCgEJAQAAAA==.Thorgrimal:BAAALgAECgIJAgAAAA==.Thorizan:BAAALgADCgEJAQAAAA==.Thryx:BAAALgAECgQJBwAAAA==.',
Ti='Tifalockhàrt:BAACLgAFFH8JAAIGAAMJsgbdJACrAAAGAAMJsgbdJACrAAAuAAQKfykABAYACQmPCCpBAHMBAAYACAkaCCpBAHMBAAIABQmZD68aAO0AAAUAAQltBqNLASkAAAAA.Timewarped:BAABLgAECn8qAAIIAAkJbBAYUACpAQAIAAkJbBAYUACpAQAAAA==.Tiriòn:BAAALgAFFAIJBAAAAA==.Titlefight:BAAALgADCgUJBQAAAA==.',
To='Torvii:BAAALgADCgMJAwAAAA==.Tossitgood:BAAALgADCgEJAQAAAA==.Totetum:BAAALgAECgEJAQAAAA==.',
Tr='Trapsin:BAACLgAFFH8JAAIIAAMJwBqgTAATAQAIAAMJwBqgTAATAQAuAAQKfzAAAggACAkqI84UAKUCAAgACAkqI84UAKUCAAAA.Trashstyle:BAAALgADCgIJAgAAAA==.Treeage:BAAALgAECgEJAQAAAA==.Treebreath:BAAALgAECgEJAQAAAA==.Treegerhappy:BAABLgAECn8mAAMTAAkJBRZcJQAmAgATAAkJBRZcJQAmAgAcAAUJsgRdZQCqAAAAAA==.Trilldevour:BAAALgAECgcJBQAAAA==.Trubbs:BAAALgADCgMJBAAAAA==.Truffle:BAABLgAECn8tAAMBAAgJMRslMQDUAQABAAcJoholMQDUAQAWAAMJ/h1eGQCgAAAAAA==.Tryniti:BAAALgAECgEJAQAAAA==.',
Tw='Twyson:BAAALgADCgMJAwAAAA==.',
Un='Uny:BAAALgAECgQJBAABLgAECgkJIQADAI4NAA==.',
Us='Usdaprime:BAAALgAECgEJAQAAAA==.',
Va='Valanya:BAAALgADCgYJBgAAAA==.Valeandriox:BAAALgAECgYJBgABLgAECggJHQARAKYcAA==.Valkarie:BAABLgAECn8kAAMHAAgJgRJMIACFAQAHAAgJgRJMIACFAQAjAAEJgwmHQgAqAAAAAA==.Valtroist:BAAALgADCgkJFAABLgAECgUJEAAPAAAAAA==.Valzyn:BAABLgAECn8dAAIRAAgJphyCDgARAgARAAgJphyCDgARAgAAAA==.Vancleave:BAAALgADCgYJBgABLgADCgcJDQAPAAAAAA==.Vayla:BAAALgAECgUJCAABLgAECgcJFgAVAM0XAA==.',
Ve='Versacex:BAAALgADCgEJAQAAAA==.',
Vi='Vic:BAAALgAECgEJAQAAAA==.Vivix:BAABLgAECn8fAAIKAAkJkReCDwBrAgAKAAkJkReCDwBrAgAAAA==.',
Vo='Voidelfmage:BAAALgAECgEJAQABLgAECgkJMgAFAEUmAA==.',
Wa='Wapoxi:BAABLgAECn8jAAMBAAkJNBqJMQBGAgABAAgJpBqJMQBGAgAWAAQJQRbKKwAQAQAAAA==.Warisfluffy:BAABLgAECn8pAAIMAAgJGgnFYQATAQAMAAgJGgnFYQATAQAAAA==.Warwìck:BAAALgADCgMJAwAAAA==.Wayoftheurr:BAAALgADCgMJAwAAAA==.',
Wh='Wheatswall:BAAALgADCgMJAgAAAA==.',
Wi='Windhamer:BAAALgAECgMJAwAAAA==.Wiseman:BAAALgADCgYJDgAAAA==.',
Wo='Wokman:BAACLgAFFH8RAAIOAAQJ1AoMHwAAAQAOAAQJ1AoMHwAAAQAuAAQKfyQAAxEACQnxFDQvAG0BABEABgkFGTQvAG0BAA4ACQnqDpw3AG0BAAAA.Wolfso:BAAALgAECgMJAwAAAA==.Woodoo:BAABLgAECn8oAAINAAkJvx9kAwCmAgANAAkJvx9kAwCmAgAAAA==.Worldboss:BAABLgAECn8lAAICAAcJzB9nBwASAgACAAcJzB9nBwASAgAAAA==.Worldhorn:BAABLgAECn8WAAMjAAgJQg8XDgDlAAAHAAcJYQxcNgD/AAAjAAUJAQ8XDgDlAAAAAA==.',
Wr='Wradalin:BAABLgAECn8uAAIJAAgJUhb1PADIAQAJAAgJUhb1PADIAQAAAA==.Wraithstorm:BAAALgADCgkJHQAAAA==.',
['Wó']='Wólverìne:BAAALgADCgcJBwAAAA==.',
Ya='Yaga:BAAALgADCgYJBgABLgADCggJCQAPAAAAAA==.',
Yr='Yric:BAABLgAECn8ZAAIMAAgJSiCSEwBlAgAMAAgJSiCSEwBlAgAAAA==.',
Yu='Yugito:BAAALgAECgQJBgAAAA==.',
Za='Zariane:BAAALgADCgcJGgAAAA==.Zarila:BAAALgAECgUJDAAAAA==.Zartain:BAABLgAECn8uAAImAAgJgxEoBwCfAQAmAAgJgxEoBwCfAQAAAA==.Zataana:BAAALgADCgMJAwAAAA==.Zazreiale:BAAALgAECgEJAgAAAA==.',
Ze='Zelfei:BAAALgADCgUJBQAAAA==.Zennamite:BAABLgAECn8uAAIUAAgJ8RhZFgDgAQAUAAgJ8RhZFgDgAQAAAA==.',
Zi='Zipzaps:BAABLgAECn8XAAIIAAYJIBXGoQCUAQAIAAYJIBXGoQCUAQAAAA==.',
['Ñu']='Ñuiña:BAAALgADCgMJBAAAAA==.',
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
