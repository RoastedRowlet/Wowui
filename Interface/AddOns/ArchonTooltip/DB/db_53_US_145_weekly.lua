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

local lookup = {'Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Devourer','Shaman-Restoration','Priest-Holy','Priest-Shadow','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Warrior-Protection','Druid-Restoration','Druid-Balance','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Evoker-Devastation','DeathKnight-Blood','Shaman-Elemental','Warrior-Fury','Mage-Arcane','Evoker-Preservation','DemonHunter-Havoc','Paladin-Holy','DeathKnight-Unholy','Paladin-Retribution','Mage-Frost','Paladin-Protection','Shaman-Enhancement','Druid-Feral','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','Priest-Discipline','DeathKnight-Frost','Evoker-Augmentation','DemonHunter-Vengeance',}
local provider = {region='US',realm='Lothar',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aaliara:BAAANQAECgMIAwAAAA==.',
Ab='Absynthae:BAAANQADCgcIEgAAAA==.',
Ac='Ackreser:BAAANQAECgEIBAAAAA==.',
Ad='Adorath:BAAANQADCgUICAAAAA==.',
Ae='Aedal:BAAANQADCggICQAAAA==.Aelethia:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Aesirah:BAAANQADCggIEQAAAA==.Aeven:BAAANQADCgEIAQABNQAFFAMICwACALoeAA==.',
Ai='Aidan:BAACNQAFFH86AAMDAAkKECcCAAAdBAADAAkKECcCAAAdBAAEAAEKAACUCQBtAAA1AAQKfx4AAwMACQrFJjcHAFoDAAMACQrFJjcHAFoDAAQAAgqaJnchAM4AAAAA.Aidhan:BAABNQAECn8bAAIFAAkKtyObDgD/AgAFAAkKtyObDgD/AgABNQAFFAkJOgADABAnAA==.Aileron:BAACNQAFFH8NAAIGAAQK4RBFEgAmAQAGAAQK4RBFEgAmAQA1AAQKfykAAgYACQpCIqUZAAkDAAYACQpCIqUZAAkDAAAA.Airlin:BAAANQADCgYICgAAAA==.',
Ak='Akshana:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.',
Al='Alapally:BAAANQADCgEIAQAAAA==.Alarod:BAAANQAECgEIAQABNQAECgQICAABAAAAAA==.Alcore:BAAANQAECgQJBQAAAA==.Aldrigor:BAAANQAECgUICAAAAA==.Alett:BAAANQAECgUICgAAAA==.Alivathus:BAACNQAFFH8GAAIHAAMKKyFsGAAoAQAHAAMKKyFsGAAoAQA1AAQKfzMAAwcACQoWJUcDALgDAAcACQoWJUcDALgDAAgAAQp+Dm56ADEAAAAA.Alluu:BAAANQADCgUIBQAAAA==.Alonzie:BAAANQAECgYIBgAAAA==.Alsong:BAAANQADCgUIDAAAAA==.Alunaa:BAAANQAECgIIAwAAAA==.Alvart:BAAANQAECgQICQAAAA==.',
Am='Ambervoid:BAAANQAECgUJCgAAAA==.Amiko:BAAANQAECgYIEQAAAA==.',
An='Annaisa:BAAANQABCgUIBQABNQAFFAQICQAHACkIAA==.Ansigar:BAAANQADCgcIBwAAAA==.',
Ar='Arbark:BAABNQAECn8hAAQJAAkKsyQnAgAOAwAJAAgKbiUnAgAOAwAKAAgKNyOEOACnAgALAAQKLCBuIwBVAQAAAA==.Arcada:BAAANQADCgYIBgAAAA==.Archdemon:BAAANQADCgUIBQAAAA==.Archie:BAAANQADCgMIAwABNQAECgcIFQADABojAA==.Arcnfrost:BAAANQAECgYIEgAAAA==.Ardone:BAAANQABCgIIAgAAAA==.Arkadis:BAAANQAECgUIDgAAAA==.Armina:BAAANQAECgYIBgAAAA==.Arrothin:BAAANQABCggIHQAAAA==.',
As='Asdanoth:BAAANQADCggICwAAAA==.Ashenbrawl:BAABNQAECn8UAAMMAAgKchhcewAjAgAMAAgKchhcewAjAgANAAEKDBmXPgBDAAAAAA==.Ashenclaw:BAAANQAECgUICwAAAA==.Aspinks:BAAANQAECgIIAgABNQAECgkJMAAKALEOAA==.',
Au='Auxie:BAABNQAECn8VAAIDAAcKGiNGFACxAgADAAcKGiNGFACxAgAAAA==.',
Av='Availl:BAAANQADCgcIBwABNQAECgIIAwABAAAAAA==.Avatipup:BAAANQAECggIEQAAAA==.',
Aw='Aweinon:BAAANQADCgQIBAAAAA==.',
Ay='Aydan:BAAANQAECgMIBQABNQAFFAkJOgADABAnAA==.Aydin:BAACNQAFFH8QAAIMAAUKTybTCAAiAgAMAAUKTybTCAAiAgA1AAQKfx4AAgwACQpWJqsWAF0DAAwACQpWJqsWAF0DAAE1AAUUCQk6AAMAECcA.Aylan:BAAANQADCgMIAwAAAA==.',
Az='Azelous:BAAANQADCggICAABNQAFFAMICAAGAEUhAA==.Azumaa:BAAANQADCggIIwAAAA==.Azurath:BAAANQAECgUICwAAAA==.Azureth:BAAANQADCgEIAQAAAA==.',
Ba='Badonk:BAAANQADCgUIBQAAAA==.Bainironwind:BAAANQADCgUIBQAAAA==.Baiwushi:BAABNQAECn8kAAICAAgKMCB7CgDdAgACAAgKMCB7CgDdAgAAAA==.Ballock:BAAANQADCggICAAAAA==.Balázs:BAAANQAECgQJCAAAAA==.Barloc:BAAANQAECgEIAQAAAA==.',
Be='Becbec:BAAANQADCgcICwAAAA==.Beckyplease:BAAANQAECgEIAQAAAA==.Belaghal:BAAANQADCgUIBQAAAA==.Bestricer:BAAANQAECgIIAgABNQAFFAkJLgADAB0eAA==.',
Bi='Biggles:BAECNQAFFH8YAAMOAAYKMhNHBADkAQAOAAYKMhNHBADkAQAPAAEKPQtRJgBHAAA1AAQKfyUAAw8ACQpGExU6AB0CAA8ACQpGExU6AB0CAA4ACQobFp8iAA0CAAAA.Bighuntarizo:BAABNQAECn8YAAIQAAgKfhaoYABTAgAQAAgKfhaoYABTAgAAAA==.Bilagaana:BAAANQADCgQIBAABNQAECggIKAAEAEwaAA==.Billevilbill:BAABNQAECn8fAAMKAAgKixNjawAXAgAKAAgKixNjawAXAgALAAEKAAC5gAAqAAAAAA==.',
Bl='Blobney:BAACNQAFFH8cAAQKAAgKZiBNBAA1AgAKAAYK/iFNBAA1AgALAAIK7yMIBgDAAAAJAAEKFhXZBwBiAAA1AAQKfyYAAwsACQplJlgHAI8CAAoABwpcJoUmAOcCAAsABwpzI1gHAI8CAAAA.Bloodymouth:BAAANQAECgQIAwABNQAECgcIFQADABojAA==.Bluechip:BAABNQAECn8kAAIGAAgK7w7XdgCjAQAGAAgK7w7XdgCjAQAAAA==.Blueeagle:BAACNQAFFH8QAAMRAAUKSiDmBwDIAQARAAUKJh/mBwDIAQASAAEK8hxFAgBYAAA1AAQKfyoABBEACQpbJfsJADMDABEACQpKJPsJADMDABIAAwrhJXULADgBABAAAQrUJpk3AW0AAAAA.Bluespell:BAAANQAECgUICwABNQAFFAUIEAARAEogAA==.',
Bo='Boldalgaz:BAAANQAFFAIIAgAAAA==.Bolts:BAAANQAECgEIAQAAAA==.Borak:BAAANQADCgQIBAABNQAFFAMICAAGAEUhAA==.',
Br='Braezlor:BAAANQAECgUIBQAAAA==.Brendel:BAAANQAECgEIBAAAAA==.Brewdarymor:BAAANQAECggIDQABNQAFFAQIBgATABkMAA==.Broaahhaha:BAAANQAECgEIBAAAAA==.Brumduhr:BAAANQADCgYIBgAAAA==.',
Bu='Bulletsponge:BAAANQADCgEIAQABNQAECgUICgABAAAAAA==.Butterflyy:BAACNQAFFH8GAAIQAAIKewiGKQCOAAAQAAIKewiGKQCOAAA1AAQKfzAAAhAACQpeFgg9ALECABAACQpeFgg9ALECAAAA.Butternutt:BAAANQADCgIIAgAAAA==.',
Ca='Caelena:BAAANQAECgYIEQAAAA==.',
Ce='Celestial:BAABNQAECn8uAAMLAAkKhRQ3BwCTAgALAAkKhRQ3BwCTAgAJAAIKCRNFHwB7AAAAAA==.',
Ch='Chaskah:BAAANQAECgEIAQAAAA==.Chilltest:BAAANQAECgQIBwAAAA==.Chronobacon:BAAANQADCgYICgABNQAFFAQIBgATABkMAA==.Chupacabra:BAAANQAECgQICQAAAA==.Chuyz:BAABNQAECn8hAAIQAAkKWhyVNADLAgAQAAkKWhyVNADLAgAAAA==.Chuyzz:BAABNQAECn8vAAIUAAgKKxmNLABjAgAUAAgKKxmNLABjAgAAAA==.',
Cl='Clawdene:BAAANQADCgQIBwAAAA==.Clickchi:BAAANQAECgIIAgAAAA==.Clikclikboom:BAAANQAECggIBgAAAA==.Cloudwarrior:BAAANQADCgEIAQABNQAFFAMIBwAVAK4ZAA==.',
Co='Cooties:BAAANQADCgUIBQABNQAECgEIAgABAAAAAA==.Cordeliaa:BAAANQADCggIFgAAAA==.Coven:BAAANQAECgIIBQAAAA==.',
Cr='Crunch:BAABNQAECn8yAAMWAAkKKyWQAADRAwAWAAkKKyWQAADRAwAMAAMKFhR/FQGqAAAAAA==.',
Cy='Cynderelle:BAAANQAECgIIBAAAAA==.Cynikka:BAABNQAECn8dAAIXAAgK7B3UcgCYAgAXAAgK7B3UcgCYAgAAAA==.Cynthor:BAABNQAECn8YAAIYAAgKew1mIgC0AQAYAAgKew1mIgC0AQAAAA==.',
Da='Dabz:BAAANQADCgYIBgAAAA==.Dadtothebone:BAAANQADCggIHAAAAA==.Daghahi:BAABNQAECn8oAAIEAAgKTBoiCwBZAgAEAAgKTBoiCwBZAgAAAA==.Daishanar:BAAANQAECgYIDgAAAA==.Dalethyr:BAAANQAECgQIBAAAAA==.Darkseid:BAAANQADCgQIBAAAAA==.Darren:BAAANQAECgUIBwAAAA==.Darthflame:BAAANQADCgUIBQABNQAECgkJLwAZACYXAA==.Datavi:BAAANQADCgYIDAAAAA==.David:BAAANQAECgEIBAABNQAECggIGgAaANgeAA==.Dawuffman:BAABNQAECn8cAAISAAgKYRA9BgA6AgASAAgKYRA9BgA6AgAAAA==.Daylia:BAAANQADCgYIBgAAAA==.',
De='Deathash:BAAANQAECgEIAQAAAA==.Deathdruid:BAABNQAECn8mAAMPAAkK5AwiOwAWAgAPAAkK5AwiOwAWAgAOAAIKRQXgawBOAAAAAA==.Deathfarm:BAAANQAECgYIEgAAAA==.Delaktrirr:BAAANQAECgEIAQABNQAECgQJCAABAAAAAA==.Deliverenc:BAAANQAECgQIBAAAAA==.Delmus:BAABNQAECn8jAAMLAAgKDxUxEQDuAQALAAcKVxQxEQDuAQAKAAgKWA1agwDZAQAAAA==.Delphinae:BAAANQAECgQIBwAAAA==.Demontwink:BAAANQADCggIFwAAAA==.Demount:BAAANQAECgQIBAAAAA==.Devera:BAABNQAECn8YAAIPAAkKxRK7OwATAgAPAAkKxRK7OwATAgABNQAECgkJGQAVAD8ZAA==.',
Di='Dillonator:BAAANQAECgIIAgAAAA==.Dinkylock:BAAANQADCggIDAAAAA==.Dirtykahuna:BAAANQAECgQIDQABNQAECgUIBQABAAAAAA==.Dirtylock:BAAANQAECgUIBQAAAA==.Dirtymagus:BAAANQADCgYIBgABNQAECgUIBQABAAAAAA==.Dirtypali:BAAANQADCgUIBQABNQAECgUIBQABAAAAAA==.Discosticks:BAAANQAECgEIAgAAAA==.Distress:BAAANQAECgEIAwAAAA==.',
Do='Dojoshaman:BAABNQAECn8bAAIVAAgKGSGQKADdAgAVAAgKGSGQKADdAgAAAA==.Doodman:BAAANQAECgYIDAAAAA==.Doubleshot:BAAANQAECgEIAQAAAA==.',
Dr='Dragondeez:BAAANQADCgUIBQABNQAECgkJJQAXAA0bAA==.Dreadrend:BAABNQAECn8UAAMUAAgKaBgbQQD2AQAUAAcKfxobQQD2AQAbAAEK2wu28QAjAAAAAA==.Dropsin:BAAANQADCggICAAAAA==.Drwn:BAAANQAECgUIEQAAAA==.',
Du='Duckroll:BAAANQAECgIIBQAAAA==.Dunkelzahn:BAAANQADCgUIBQAAAA==.Dustmaster:BAAANQABCgIIBgAAAA==.',
Dw='Dwelknarr:BAAANQAECgQIBwAAAA==.Dwlirious:BAABNQAECn8jAAIcAAgKkgpewgCRAQAcAAgKkgpewgCRAQAAAA==.',
Ea='Eadric:BAAANQAECgIIAgAAAA==.Earendur:BAAANQAECgIIAwAAAA==.Earthfury:BAAANQAECgQIBgABNQAECggIHQAcAFAYAA==.Eaven:BAAANQADCgIIAgABNQAFFAMICwACALoeAA==.',
Ed='Edalasar:BAAANQAECgEIAwAAAA==.Edallen:BAABNQAECn8eAAIQAAgK5BSTcAAuAgAQAAgK5BSTcAAuAgAAAA==.Edorbla:BAAANQABCggICAAAAA==.',
Ee='Eelyroc:BAAANQADCgMIAwAAAA==.',
Ei='Eilly:BAAANQAECgUIBwAAAA==.',
El='Elbrujo:BAAANQAECgcIEAAAAA==.Eleaanor:BAAANQADCgYIBgAAAA==.Elementals:BAAANQAECggJAQAAAA==.',
Em='Emaytete:BAAANQAECgUIDAAAAA==.Emayteteheww:BAAANQAECgMIBwAAAA==.Emaytetem:BAAANQADCgMIAwAAAA==.Emillyra:BAAANQAECgIIAgAAAA==.Empress:BAAANQAECgEIAQABNQAFFAYIEgAUANwkAA==.',
Ep='Ephemra:BAAANQADCggJBwAAAA==.',
Es='Esteban:BAAANQAECgUIDAAAAA==.',
Ev='Evisette:BAAANQADCgMIBQAAAA==.Evokethywikd:BAABNQAECn8WAAITAAkKTQzYFQDsAQATAAkKTQzYFQDsAQABNQAFFAIIAgABAAAAAA==.',
Fa='Fahx:BAAANQAECgIIAgAAAA==.Falwyn:BAAANQAECgIIBQAAAA==.Famidore:BAAANQADCgIIBAAAAA==.Faèlyn:BAAANQADCgUICQAAAA==.',
Fe='Felflamel:BAABNQAECn8vAAIZAAkKJhc1JgBnAgAZAAkKJhc1JgBnAgAAAA==.Feltest:BAAANQAECgcJDwAAAA==.Feralized:BAAANQAECgIIAwAAAA==.Ferdinan:BAABNQAECn8mAAIMAAkKTxQUawBMAgAMAAkKTxQUawBMAgAAAA==.Fernier:BAAANQADCgYIBgAAAA==.',
Fl='Flareon:BAAANQAECgEIAQABNQAFFAcIEAAGADkaAA==.Flashter:BAABNQAECn8eAAMMAAgKtRBwmgDWAQAMAAgKexBwmgDWAQANAAEKQxaHQAA6AAAAAA==.Flax:BAAANQADCgMIAwAAAA==.Fluffycuddle:BAAANQADCgUICQAAAA==.Fluffymage:BAAANQADCgIIAwABNQAFFAQIBgATABkMAA==.Flurryfarm:BAAANQADCggICAAAAA==.',
Fo='Forrealzies:BAAANQAECgUICQAAAA==.Fortunato:BAAANQADCgEIAQAAAA==.',
Fr='Frankhs:BAAANQAECgMIBQAAAA==.Frypach:BAAANQAECgQIBgABNQAECggIGgAaANgeAA==.',
Fu='Furchi:BAAANQADCgIIAgABNQAECggIHAASAGEQAA==.',
Ga='Galdrel:BAAANQAECgQIEQAAAA==.Gallince:BAACNQAFFH8QAAIcAAYKdCShAgBjAgAcAAYKdCShAgBjAgA1AAQKfyMAAhwACQoJJkIQAIcDABwACQoJJkIQAIcDAAAA.Garbich:BAAANQADCgEIAgABNQAECgUIBQABAAAAAA==.Gary:BAABNQAECn8eAAIGAAgKWh5TKADBAgAGAAgKWh5TKADBAgAAAA==.',
Ge='Gerhart:BAAANQAECgQIBwAAAA==.',
Gh='Ghostsham:BAACNQAFFH8dAAIVAAgKSBunAAABAwAVAAgKSBunAAABAwA1AAQKfygAAxUACQreJt8BAOgDABUACQreJt8BAOgDAAYAAwoJA+T0AHsAAAAA.Ghðst:BAABNQAFFH8KAAIPAAcKfxQwBABrAgAPAAcKfxQwBABrAgABNQAFFAgIHQAVAEgbAA==.',
Gi='Gilgamet:BAAANQADCgEIAQAAAA==.Gizmito:BAAANQADCgQIBQAAAA==.',
Gl='Glizzyman:BAABNQAECn8ZAAIMAAkKWhHKgwAOAgAMAAkKWhHKgwAOAgAAAA==.',
Gn='Gnarfarm:BAAANQAECgQIBwAAAA==.',
Go='Go:BAAANQADCgYJBgABNQAECgYIBwABAAAAAA==.Gobsborne:BAAANQAECgEIAQABNQAECgkJLQAdAMYeAA==.Goldoran:BAAANQADCgIIAgAAAA==.Gonette:BAAANQADCgYIBgABNQAECgkJJgAeAHsfAA==.Goniff:BAABNQAECn8mAAIeAAkKex9MCAAYAwAeAAkKex9MCAAYAwAAAA==.Goransk:BAAANQAECgEIBAAAAA==.Gorsk:BAAANQADCgYIBgABNQAECgEIBAABAAAAAA==.',
Gr='Gracelious:BAABNQAECn8qAAIcAAgK8BkjdwA6AgAcAAgK8BkjdwA6AgAAAA==.Graebeard:BAAANQADCggIGwAAAA==.Graehame:BAAANQADCgYIDAAAAA==.Greyshadow:BAAANQADCgUIBQAAAA==.Grubber:BAAANQADCgYIDAABNQAECgUICQABAAAAAA==.Grüb:BAAANQAECgUICQAAAA==.',
Gu='Guitar:BAAANQAECgQICAAAAA==.Guntran:BAACNQAFFH8GAAIcAAIKzxMEIgCUAAAcAAIKzxMEIgCUAAA1AAQKfy8AAhwACQrJHgEoACQDABwACQrJHgEoACQDAAAA.Gurkha:BAAANQADCgYIBwAAAA==.Gurthock:BAAANQAECgYICgAAAA==.',
Gw='Gwenixx:BAAANQAECgIIAwAAAA==.',
Ha='Hackers:BAAANQADCgMIAwAAAA==.Halios:BAAANQAECgIIAgAAAA==.Haunter:BAAANQAECgIIAgAAAA==.',
He='Headhuntin:BAABNQAECn8fAAIQAAgK7BGIYgBOAgAQAAgK7BGIYgBOAgAAAA==.Heatfang:BAAANQADCgcICQAAAA==.Hellifiknow:BAAANQADCgQIBAABNQAECgUICgABAAAAAA==.Hellione:BAABNQAECn8YAAIbAAgKAQtWWgCjAQAbAAgKAQtWWgCjAQAAAA==.Hellmaree:BAAANQADCgEIAQAAAA==.Helltest:BAAANQAECgEIAQAAAA==.',
Hi='Hiruzèn:BAAANQAECgQICwAAAA==.',
Ho='Holyspurb:BAAANQADCgYIBgAAAA==.Holywater:BAABNQAECn8lAAIIAAgKCBTqIwAPAgAIAAgKCBTqIwAPAgAAAA==.Honkinhammer:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Hotdogman:BAACNQAFFH8gAAIRAAgKGiWYAAAsAwARAAgKGiWYAAAsAwA1AAQKfyEAAhEACQqZJmcCALwDABEACQqZJmcCALwDAAE1AAQKCAgOAAEAAAAA.Hotdumpling:BAAANQAECgYIDwAAAA==.Hozo:BAAANQADCgcIBwAAAA==.',
Hu='Huegarak:BAAANQAECgQIBgAAAA==.Hunterdwarf:BAAANQABCgYIBAAAAA==.',
Hy='Hyle:BAABNQAECn8XAAINAAcKBw2kHgBaAQANAAcKBw2kHgBaAQAAAA==.',
Il='Illidaddy:BAAANQAECgUICgABNQAECgkJJQAXAA0bAA==.Illuminator:BAAANQAECgIIAwAAAA==.',
In='Inspectadeck:BAACNQAFFH8WAAMKAAYKHw0rFQBRAQAKAAUKeQsrFQBRAQALAAEKEhJiGwBPAAA1AAQKfzkAAwoACQooH38yALsCAAoACQqiHn8yALsCAAsABApjFmwsABwBAAAA.',
Ir='Irsh:BAAANQADCggICAAAAA==.',
Is='Istariel:BAAANQAECgIIAgABNQAFFAgIHQAVAEgbAA==.',
It='Ithoron:BAABNQAECn8qAAIUAAgKzhlKMgBEAgAUAAgKzhlKMgBEAgAAAA==.',
Iv='Ivoree:BAAANQAECgUICAAAAA==.',
Ja='Jaytov:BAAANQABCgQIBAAAAA==.Jazu:BAABNQAECn8bAAIXAAgKXBrgdwCOAgAXAAgKXBrgdwCOAgAAAA==.',
Je='Jerks:BAABNQAECn8sAAMfAAgKwxTdEwAnAgAfAAgKwxTdEwAnAgAGAAMKzQ5B9AB9AAAAAA==.',
Jo='Jost:BAAANQADCgMIAwABNQAECgUIBgABAAAAAA==.Joval:BAAANQAECgIIAwAAAA==.Jozeph:BAAANQAECgcIEQAAAA==.',
Ju='Jusalilguy:BAAANQAECgEIAQAAAA==.',
['Jà']='Jàmie:BAAANQAECgYIBgAAAA==.',
Ka='Kaalar:BAABNQAECn8oAAIQAAgKhh77PACxAgAQAAgKhh77PACxAgAAAA==.Kaesandra:BAAANQADCgYIBgAAAA==.Kaestirael:BAAANQAECgEIAQAAAA==.Kakarrot:BAAANQAECgIJAgAAAA==.Kalichnakov:BAAANQADCgYIBgAAAA==.Kalicreborn:BAAANQABCggICgAAAA==.Kamoura:BAABNQAECn8nAAIdAAgKeRkiCABgAgAdAAgKeRkiCABgAgAAAA==.Kapeta:BAAANQAECgUIEwAAAA==.Karmen:BAACNQAFFH8bAAIYAAYKkxwABQAYAgAYAAYKkxwABQAYAgA1AAQKfyUAAhgACQoKJGwDAIEDABgACQoKJGwDAIEDAAAA.Karnatron:BAAANQAECgQIBwAAAA==.Karnvoid:BAAANQADCggIDwABNQAECgQIBwABAAAAAA==.Katalain:BAAANQADCggICQABNQAFFAMICQAOAO0VAA==.Kayleave:BAAANQADCgYIBgAAAA==.Kazz:BAAANQADCggIDwABNQAECgkJMQAgACYiAA==.',
Ke='Keattz:BAACNQAFFH8rAAIMAAkKyB5YAACYAwAMAAkKyB5YAACYAwA1AAQKfy8AAgwACQqsJgQFAMwDAAwACQqsJgQFAMwDAAE1AAQKCQkuACEAsCQA.Keattzxd:BAABNQAECn8uAAMhAAkKsCQuAwClAwAhAAkKsCQuAwClAwAiAAMKFQ9NQQCoAAAAAA==.Keedill:BAABNQAECn8lAAMJAAgKPxjtCQDcAQAJAAcKnxPtCQDcAQAKAAcKiBlqjwC7AQAAAA==.Keelinnea:BAAANQAECgEIAQAAAA==.Keelu:BAAANQADCgEIAQAAAA==.Keggerz:BAAANQADCgcIDAAAAA==.Kennagi:BAAANQAECgQICQAAAA==.Kenshunterl:BAAANQAECgQICQAAAA==.',
Kh='Khanzen:BAAANQAECgQIBgAAAA==.Khathgar:BAABNQAECn8ZAAIhAAcKfAywRgClAQAhAAcKfAywRgClAQABNQAECgkJLQAgAF8ZAA==.Khovastis:BAACNQAFFH8YAAMPAAYKfRyoCQDaAQAPAAUK0yCoCQDaAQAgAAEKeA84BABfAAA1AAQKfyUABA8ACQoAGlAyAE4CAA8ACAqsG1AyAE4CACMAAwr5EwxAALMAACAAAgr2D2syAHkAAAAA.',
Ki='Kianll:BAAANQAECggICAAAAA==.Kitchntabls:BAACNQAFFH8ZAAIZAAYK1yBBBAAmAgAZAAYK1yBBBAAmAgA1AAQKfyUAAxkACQpKJpwEAKgDABkACQpKJpwEAKgDAAUAAwriETBZAJcAAAAA.',
Kj='Kjirou:BAABNQAECn8gAAIIAAgKaB4hFADCAgAIAAgKaB4hFADCAgAAAA==.',
Ko='Koenji:BAACNQAFFH8XAAIfAAYK3hdpAQALAgAfAAYK3hdpAQALAgA1AAQKfyIAAh8ACQpmI3YGAB0DAB8ACQpmI3YGAB0DAAAA.Korenn:BAAANQAECgUICQAAAA==.Korgrim:BAAANQAECgEIAwAAAA==.',
Ky='Kymal:BAAANQAECgEIAgAAAA==.Kynana:BAAANQAECgYIDgABNQAECgkJFgAVALUUAA==.Kyndel:BAAANQADCgQIBwAAAA==.Kyndrah:BAABNQAECn8bAAQHAAgKhxAxbQDSAQAHAAgKRhAxbQDSAQAIAAgK3gpjMACcAQAkAAMKaQSnHgBoAAABNQADCgQIBwABAAAAAA==.',
['Kä']='Käne:BAABNQAECn8eAAIbAAgKVwxNXQCWAQAbAAgKVwxNXQCWAQAAAA==.',
['Kì']='Kìn:BAAANQADCgIIAgABNQAECgkJGwAPABUNAA==.',
['Kí']='Kín:BAAANQADCgEIAQABNQAECgkJGwAPABUNAA==.',
La='Lableue:BAAANQAECgEIAgAAAA==.Landuchi:BAAANQAECgYICwAAAA==.Lavacask:BAAANQADCggJHgAAAA==.',
Le='Lehvy:BAAANQADCggICAABNQAFFAMIBwAHAFIGAA==.Leodk:BAACNQAFFH8LAAMlAAUK6x07CQBQAQAlAAQK6x07CQBQAQAbAAEKAADbHgBPAAA1AAQKfyoAAyUACQoZJWkKAEUDACUACQoZJWkKAEUDABsABgpeH3NbAJ4BAAE1AAUUBQoLACUA6x0A.Lerann:BAAANQADCgQIBAABNQAECgkJKgAMAJgkAA==.Levey:BAACNQAFFH8HAAIHAAMKUgYCIgDKAAAHAAMKUgYCIgDKAAA1AAQKf0MAAgcACQpFH4MYABIDAAcACQpFH4MYABIDAAAA.Lewdcifer:BAAANQAECgQIBwAAAA==.',
Li='Lick:BAAANQAECgMIAwABNQAECgYIBwABAAAAAA==.Lict:BAACNQAFFH8MAAIaAAQKUw7XEgAuAQAaAAQKUw7XEgAuAQA1AAQKfx4AAhoACQqzGZYqALsCABoACQqzGZYqALsCAAE1AAQKBggHAAEAAAAA.Liekki:BAAANQAECgIIAgABNQAECgQIBwABAAAAAA==.Lillea:BAAANQAECgYIEwAAAA==.Linada:BAAANQAECgEIAgAAAA==.Listurfiend:BAAANQADCgIIAgAAAA==.Liteseraph:BAAANQAECgQICAAAAA==.',
Lo='Loktalaan:BAACNQAFFH8UAAIfAAYKvBccAQAtAgAfAAYKvBccAQAtAgA1AAQKfzEAAh8ACQpsIUkFADcDAB8ACQpsIUkFADcDAAAA.Lothlorian:BAAANQADCgEIAQAAAA==.',
Lu='Luan:BAAANQAECgQIBAAAAA==.Lucien:BAACNQAFFH8JAAIOAAMK7RUGDADyAAAOAAMK7RUGDADyAAA1AAQKfzEAAg4ACQraHFYPAN0CAA4ACQraHFYPAN0CAAAA.Lute:BAABNQAECn8aAAMVAAgKsiMzHgATAwAVAAgKsiMzHgATAwAGAAEKyA09KQEiAAAAAA==.',
Ly='Lyfeguard:BAABNQAECn8dAAIHAAgKuBAbYwDzAQAHAAgKuBAbYwDzAQAAAA==.',
Ma='Machoke:BAAANQADCgYIDQAAAA==.Maelyfleuve:BAAANQADCggICAAAAA==.Mahito:BAABNQAECn8xAAIgAAkKJiJEAwBtAwAgAAkKJiJEAwBtAwAAAA==.Maiha:BAABNQAECn8WAAIVAAkKtRT6XgABAgAVAAkKtRT6XgABAgAAAA==.Malenia:BAACNQAFFH8RAAMKAAUKtw0IGgAqAQAKAAQKUA8IGgAqAQALAAIKFgk/EQCQAAA1AAQKfyYABAsACQpsHlseAHsBAAoACAp3FuJxAAcCAAsABQoqH1seAHsBAAkABAraD70VAOoAAAAA.Malume:BAAANQADCgYICAAAAA==.Malyon:BAAANQADCgEIAQAAAA==.Malístra:BAAANQADCggICgAAAA==.Manaless:BAAANQAECgEIAQABNQAFFAUKCwAlAOsdAA==.Marderer:BAABNQAECn8hAAIhAAgKkA++NQD9AQAhAAgKkA++NQD9AQAAAA==.Masakari:BAABNQAECn8oAAIQAAgKEBTlZwBCAgAQAAgKEBTlZwBCAgAAAA==.Materia:BAAANQAECgUIBgAAAA==.Mathmagician:BAABNQAECn8lAAIXAAkKDRu+YAC9AgAXAAkKDRu+YAC9AgAAAA==.Maulfarm:BAACNQAFFH8KAAMgAAYKdQ08AQCgAQAgAAUKdQ08AQCgAQAPAAEKAACjLAAkAAA1AAQKfyEAAiAACQqsIHUFACEDACAACQqsIHUFACEDAAAA.Mazz:BAAANQABCgYIBgABNQAECgEIAQABAAAAAA==.Mazzlock:BAAANQAECgEIAQAAAA==.',
Mc='Mclovn:BAAANQADCgEIAQAAAA==.',
Me='Megameow:BAABNQAECn8tAAMgAAkKXxmCBwDkAgAgAAkKXxmCBwDkAgAOAAQKLA30TADVAAAAAA==.Mercuria:BAAANQADCgMIAwAAAA==.Messmer:BAAANQAECgYICQAAAA==.Metaclass:BAAANQAECgIIAwAAAA==.',
Mi='Mirâ:BAAANQADCgcICQAAAA==.Mitrixx:BAABNQAECn8dAAIfAAcKFxgXFAAjAgAfAAcKFxgXFAAjAgAAAA==.Miztie:BAAANQADCgQIBAAAAA==.',
Mo='Mobius:BAAANQAECgEIAQAAAA==.Mokuo:BAAANQAECgcICQAAAA==.Moonthorn:BAAANQAECgUIEgAAAA==.Morrow:BAAANQADCgEIAQAAAA==.Mort:BAAANQAECgQIBwAAAA==.Moxou:BAAANQAECgIIAgABNQAFFAcIFwAGAGwdAA==.Moxxou:BAACNQAFFH8XAAIGAAcKbB1yAgB6AgAGAAcKbB1yAgB6AgA1AAQKfycAAgYACQpUJRkFAJ4DAAYACQpUJRkFAJ4DAAAA.Moyi:BAAANQAECgEIAQAAAA==.',
Mu='Mulch:BAABNQAECn8zAAIOAAkKiw5LKADZAQAOAAkKiw5LKADZAQAAAA==.',
My='Mybelle:BAAANQADCgIIAgAAAA==.Mysticle:BAAANQADCggIGQAAAA==.Mythaltis:BAABNQAECn8kAAIZAAcKvCIDHgCmAgAZAAcKvCIDHgCmAgAAAA==.',
Na='Naedori:BAAANQADCgYICAABNQAECgcIDQABAAAAAA==.Naizhruk:BAAANQADCgEIAQAAAA==.Nall:BAAANQADCgIIBAAAAA==.Naoh:BAAANQADCgQJBAAAAA==.Narache:BAAANQADCgYIBwAAAA==.Naturerend:BAAANQADCgYICgAAAA==.Nau:BAAANQADCgQIBAAAAA==.Naul:BAACNQAFFH8GAAMTAAQKQwuvCQDKAAATAAMKfQ6vCQDKAAAmAAEKlgG5DABBAAA1AAQKfyAAAyYACQqZFqINAG8BABMACAqlDwsYAMYBACYABQoOGKINAG8BAAAA.Naull:BAAANQAECgEIAgAAAA==.Naysayer:BAAANQADCgQIBQAAAA==.Naúl:BAAANQADCgUIBQAAAA==.',
Ne='Necrokai:BAABNQAECn8ZAAIOAAkKnCDECAA2AwAOAAkKnCDECAA2AwAAAA==.Necroscourge:BAABNQAECn8eAAIUAAgKABuyLgBWAgAUAAgKABuyLgBWAgABNQAECgkJGQAOAJwgAA==.Neighter:BAAANQAECgYIEAAAAA==.Nerevar:BAAANQAECgIIAwAAAA==.Netal:BAAANQAECgQJCgAAAA==.Nevergoback:BAAANQADCgcICwABNQAECggIKAAUAMYPAA==.',
Ni='Ninejuanjuan:BAABNQAECn8pAAIaAAgKgBb/RgBIAgAaAAgKgBb/RgBIAgAAAA==.Nishikienrai:BAAANQAECggICwAAAA==.',
No='Nochit:BAACNQAFFH8XAAIPAAcK7yWRAQDcAgAPAAcK7yWRAQDcAgA1AAQKfysAAg8ACQrfJs8CANADAA8ACQrfJs8CANADAAAA.Noctula:BAABNQAECn8dAAQJAAkK4xtXAwDFAgAJAAkK4xtXAwDFAgAKAAQKPQ+j8wDeAAALAAIKqQL3agBJAAABNQAECgkJGQAOAJwgAA==.Norbiee:BAAANQAECgYIDgAAAA==.Nored:BAAANQAECgQIBwAAAA==.Norne:BAABNQAECn8tAAIZAAgKdxv7IgB/AgAZAAgKdxv7IgB/AgAAAA==.Nowfaleena:BAAANQAECgMIBQAAAA==.Nozok:BAAANQAECgIIAwAAAA==.',
Ny='Nymphira:BAAANQAECgUIBQAAAA==.Nytkiller:BAAANQAECgQIBQAAAA==.Nyzul:BAAANQAECgIIBQABNQAECggIIwALAA8VAA==.',
['Në']='Nëv:BAAANQADCgIIAgAAAA==.',
Oa='Oatie:BAAANQADCgUIAwAAAA==.',
Oc='Oceanic:BAAANQAECgUIDgAAAA==.',
Od='Odlinn:BAABNQAECn8YAAMHAAgKKw4pcQDFAQAHAAgKKw4pcQDFAQAkAAEKKwHAMgAYAAABNQAECgkJMwAOAIsOAA==.',
On='Onlyhorns:BAAANQAECgYICgABNQAECgkJKAAfAI8lAA==.',
Oo='Oogs:BAAANQAECgEIAQAAAA==.',
Op='Opalia:BAAANQAECgUIDwAAAA==.Opallea:BAAANQAECgIIBQABNQAECgIIBQABAAAAAA==.Oppa:BAAANQADCgEIAQABNQAECgIIBQABAAAAAA==.',
Or='Orch:BAAANQAECgcIHQAAAQ==.',
Ov='Overclocked:BAABNQAECn8wAAIKAAkKsQ7fcgAEAgAKAAkKsQ7fcgAEAgAAAA==.',
Pa='Paddington:BAABNQAECn8jAAIjAAgKYAzdIgB6AQAjAAgKYAzdIgB6AQAAAA==.Pahbi:BAAANQAECgIIAwAAAA==.Palempi:BAAANQADCggIDwAAAA==.Papadawn:BAAANQAECgEIAQAAAA==.Paratus:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.',
Pe='Pendojight:BAAANQAECgQIBAAAAA==.Pendojo:BAAANQAFFAIIAgAAAA==.Pendomage:BAAANQAECggIDwAAAA==.',
Ph='Phobius:BAAANQAECgIIAgAAAA==.',
Pi='Pip:BAABNQAECn8ZAAMVAAkKPxkpVwAbAgAVAAgK/hgpVwAbAgAGAAIKDwOGAgFdAAAAAA==.Pipium:BAABNQAECn8YAAIJAAkKTiPFBQBbAgAJAAkKTiPFBQBbAgABNQAECgkJGQAVAD8ZAA==.Pixsin:BAAANQAECgUICgABNQAECgkJOQAKAI8ZAA==.',
Po='Pookiehandz:BAABNQAECn8oAAIUAAgKxg9XWACPAQAUAAgKxg9XWACPAQAAAA==.Porpul:BAAANQAECgIIAgAAAA==.Powery:BAAANQAECgcIEAAAAA==.',
Pr='Project:BAAANQAECgQICwAAAA==.Prophet:BAAANQADCgcIBwAAAA==.',
Pu='Publicbussy:BAAANQADCgcIFQAAAA==.Purples:BAAANQAECgYJCgAAAA==.Purpul:BAAANQAECgQIBAABNQAECgYJCgABAAAAAA==.',
Py='Pyrivia:BAAANQAECgUIBQABNQAECgkJFgAVALUUAA==.',
Qa='Qawxz:BAAANQADCgUIBQAAAA==.',
Qu='Quicktail:BAAANQAECgQIBQABNQAECgkJLQAdAMYeAA==.',
Ra='Raikan:BAABNQAECn8qAAMMAAkKmCSOBQDHAwAMAAkKbiSOBQDHAwANAAcKFCQJBwDtAgAAAA==.Rainwater:BAAANQADCgEIAQAAAA==.Raisins:BAAANQADCggICAABNQAFFAYIFgAHALYbAA==.Raisyns:BAACNQAFFH8WAAIHAAYKthuDBgAoAgAHAAYKthuDBgAoAgA1AAQKfyUAAwcACQqGI8QQAD8DAAcACQqGI8QQAD8DACQAAQqQHGElAEAAAAAA.Rammic:BAAANQADCgIIAgAAAA==.Randstohl:BAAANQADCggIDgAAAA==.Ratakhan:BAAANQADCgUICAAAAA==.Raulothim:BAAANQAECgcIDwAAAA==.',
Re='Rebell:BAABNQAECn8XAAIcAAgKBw6mxQCKAQAcAAgKBw6mxQCKAQABNQAECgkJFgAVALUUAA==.Reelorn:BAAANQADCgYIBgAAAA==.Reny:BAAANQAECgIIAwAAAA==.Repentance:BAAANQADCgEIAQABNQADCgYIBwABAAAAAA==.Retribussy:BAABNQAECn8fAAIcAAgKbyLvNQD0AgAcAAgKbyLvNQD0AgAAAA==.',
Ri='Ribbed:BAAANQAECgMIAwABNQAECgYIBwABAAAAAA==.Ricemachinex:BAABNQAECn8dAAMKAAkKyBZifwDjAQAKAAcK0BJifwDjAQALAAMK5RYyNwDjAAABNQAFFAkJLgADAB0eAA==.Ricemachnedk:BAAANQAECggIDwABNQAFFAkJLgADAB0eAA==.Riko:BAAANQAECgUIBQABNQAECgkJMQAgACYiAA==.',
Ro='Rocthar:BAABNQAECn8mAAIaAAgK0Q1VcADEAQAaAAgK0Q1VcADEAQAAAA==.Roguelite:BAAANQADCgEIAQABNQAFFAUKCwAlAOsdAA==.Romarus:BAAANQAECgYIEwAAAA==.Romeoposter:BAABNQAECn8UAAMiAAcKUAyNMQAsAQAiAAUKLw6NMQAsAQAhAAMK6AhThQCSAAAAAA==.',
Ru='Rukarazyll:BAAANQAECgQICwAAAA==.Rumble:BAAANQAECgQICAAAAA==.Rutherford:BAAANQADCgQIBAAAAA==.Ruush:BAAANQAECgUIDQAAAA==.',
Ry='Rypach:BAABNQAECn8aAAMaAAgK2B7nJQDQAgAaAAgK2B7nJQDQAgAcAAQKuxm27QA6AQAAAA==.Ryunohige:BAAANQADCggICAAAAA==.',
['Rú']='Rúúsh:BAAANQAECgQIBgAAAA==.',
Sa='Safeword:BAAANQAECgQIDgAAAA==.Saihua:BAAANQADCgYIBgAAAA==.Saintjohn:BAAANQAECgcIDgAAAA==.Saintjon:BAAANQAECggIEgAAAA==.Saintjonn:BAABNQAECn8jAAMlAAkKvgxjRgCfAQAlAAcKbxFjRgCfAQAbAAcKiQjRiQD3AAAAAA==.Saintrob:BAAANQADCgMJAwAAAA==.Salamando:BAEANQAFFAEIAQABNQAFFAQIDgAMACshAA==.Sarthdidius:BAABNQAECn8pAAIZAAgKgQpARQCWAQAZAAgKgQpARQCWAQAAAA==.Sassparilluh:BAAANQAECgIIAwAAAA==.Savalla:BAAANQADCgYIBgAAAA==.',
Sc='Scarletflamè:BAAANQADCgcIBwAAAA==.Schadenfreud:BAAANQAECgQIBQAAAA==.Scholoman:BAAANQADCggIDgAAAA==.Scratchbelly:BAAANQADCggIDQAAAA==.Scumdog:BAAANQADCgYIBgAAAA==.',
Se='Senpai:BAACNQAFFH8WAAMXAAYKsRaaEADtAQAXAAYKsRaaEADtAQAdAAEK/xExEQBMAAA1AAQKfyQAAxcACQreIf1BAAADABcACQreIf1BAAADAB0AAQoAAMY/AEMAAAAA.Seoli:BAAANQAECgEIAQAAAA==.Serenya:BAAANQADCgYIBgAAAA==.',
Sh='Shalanthra:BAAANQAECgQICwAAAA==.Shamallow:BAAANQADCgQIBAAAAA==.Shamanette:BAAANQADCggICAABNQAECgIIBQABAAAAAA==.Shammunition:BAABNQAECn8oAAIfAAkKjyXsAADAAwAfAAkKjyXsAADAAwAAAA==.Shamussy:BAAANQAECgUIEQAAAA==.Shartner:BAAANQADCgMIAwAAAA==.Shartz:BAAANQAECgYIEwAAAA==.Shaysa:BAEBNQAECn8XAAMCAAgKaRGDIgBsAQACAAcKkA6DIgBsAQADAAUKpQYcTADDAAAAAA==.Sheraa:BAAANQAECgcIEgAAAA==.Shinigamisan:BAABNQAECn8YAAIdAAkK9g9YDADzAQAdAAkK9g9YDADzAQAAAA==.Shynox:BAABNQAECn8cAAMaAAgKYR6MRABRAgAaAAcKdB2MRABRAgAcAAcKaBa5mADtAQAAAA==.Shümp:BAAANQAECgIIAgAAAA==.',
Si='Sinnerchrono:BAAANQADCggIBwAAAA==.Sinnwoo:BAAANQABCgQIBgAAAA==.Sitharco:BAAANQAECgMICgAAAA==.',
Sk='Skimmilk:BAAANQAECggIEQABNQAFFAQIDAANANkdAA==.',
Sl='Sladex:BAAANQAECgIIAgAAAA==.Sleeptoken:BAAANQADCgEIAQAAAA==.',
Sm='Smorc:BAAANQAECgcIEwAAAA==.',
Sn='Snackwitch:BAAANQAECgMIBAAAAA==.Sneaki:BAAANQAECgYIDQABNQAECgcIFQADABojAA==.',
So='Soarseas:BAAANQADCgYIBgAAAA==.Sommin:BAAANQADCgYICgAAAA==.Songy:BAAANQADCgUICQAAAA==.Sorakah:BAAANQAECgMIBAAAAA==.Soulviper:BAABNQAECn82AAMGAAkK0Bg/SQA6AgAGAAkK0Bg/SQA6AgAVAAYKhwqTnQBYAQAAAA==.',
Sp='Spankmyflank:BAAANQAECgIIBQAAAA==.Spurb:BAAANQAECggIAQAAAA==.Spurblock:BAAANQADCgYJBgAAAA==.',
Sq='Squaleon:BAAANQADCgQIBAAAAA==.',
St='Stabbyfinch:BAAANQAECgQICQAAAA==.Steatfox:BAAANQADCgUIBQAAAA==.Steplok:BAAANQAECgQIBAAAAA==.Stonestriker:BAAANQAECgQIBQAAAA==.Stooben:BAABNQAECn8fAAIMAAkKmRbkcwA2AgAMAAkKmRbkcwA2AgAAAA==.Stoobenh:BAAANQAECgQIBQAAAA==.Sturge:BAAANQAECgMIBAAAAA==.',
Su='Supahsayajin:BAAANQAECgcIEQABNQAFFAIIAgABAAAAAA==.',
Sw='Sweetbee:BAABNQAECn8YAAIQAAcKgA3VqgCrAQAQAAcKgA3VqgCrAQAAAA==.Sweetpotato:BAAANQAECgUIBQAAAA==.Sweetvaldine:BAAANQADCgcIDAAAAA==.Swole:BAAANQAECgQIBQAAAA==.',
Sy='Syanalody:BAAANQAECgIIAwAAAA==.Sylarz:BAABNQAECn8cAAMlAAkKchtvFQDdAgAlAAkKchtvFQDdAgAUAAIKRAaCuQBRAAABNQAFFAQIBgATABkMAA==.Sylenn:BAAANQAECgIIAwAAAA==.Sylveon:BAAANQAECgIIAgAAAA==.Syn:BAABNQAECn8lAAMJAAgKlCFCBACcAgAJAAcKlCFCBACcAgAKAAIK+hLkFgGTAAAAAA==.Synchro:BAAANQAECgEIAQAAAA==.',
Ta='Tactics:BAAANQADCgQIBAAAAA==.Talanna:BAAANQADCgcICgAAAA==.Tanstaafl:BAABNQAECn8sAAIQAAgKLh6MKwDqAgAQAAgKLh6MKwDqAgAAAA==.Taralom:BAAANQAECgQICQAAAA==.Taz:BAECNQAFFH8FAAInAAIKXiGXAwC+AAAnAAIKXiGXAwC+AAA1AAQKfy4AAycACQoNJqkAAM8DACcACQoNJqkAAM8DABkAAQo9ASGmAAUAAAAA.',
Te='Telmo:BAABNQAECn8YAAIHAAkKEQ8lXAAJAgAHAAkKEQ8lXAAJAgAAAA==.Tenebrix:BAAANQAECgUIBgAAAA==.Tenevoy:BAABNQAECn8ZAAMIAAkKyhqCFQCwAgAIAAgKfx2CFQCwAgAHAAkKLQ4yXAAJAgABNQAFFAgIHQAVAEgbAA==.',
Th='Thadex:BAABNQAECn8dAAMMAAkKvR9iTwCYAgAMAAgKvR9iTwCYAgAWAAEKAACOLgBEAAAAAA==.Thebigfreeze:BAAANQABCgMIAQAAAA==.Thedood:BAAANQADCgYIBgAAAA==.Thedruidguy:BAAANQADCgQIBAAAAA==.Theldrid:BAACNQAFFH8IAAIbAAMKlhXMEQDrAAAbAAMKlhXMEQDrAAA1AAQKfzUAAhsACQq4I+IOAD8DABsACQq4I+IOAD8DAAAA.Thepallyguy:BAAANQAECgQIBAABNQAECgcIHgAHALsfAA==.Theprepared:BAAANQAECgEIAQAAAA==.Thepriestguy:BAABNQAECn8eAAIHAAcKux/HQABkAgAHAAcKux/HQABkAgAAAA==.Theralethia:BAAANQAECgQIBAAAAA==.Therian:BAAANQADCgIIBQAAAA==.Theshamanguy:BAAANQAECgMIBAABNQAECgcIHgAHALsfAA==.Thorseas:BAABNQAECn8lAAISAAgKhiHvAgDyAgASAAgKhiHvAgDyAgAAAA==.Thunderkill:BAAANQADCgYICwAAAA==.',
Ti='Tirissa:BAAANQADCggICgAAAA==.',
To='Tooyew:BAAANQAECgcIDQABNQAFFAYIGgAMABsdAA==.Tooyoo:BAACNQAFFH8aAAMMAAYKGx2/CAAjAgAMAAYKGx2/CAAjAgAWAAEKAACyBQBLAAA1AAQKfxsAAgwACQqiInEkACQDAAwACQqiInEkACQDAAAA.Torpedotaka:BAAANQAECgMIBAAAAA==.',
Tp='Tpala:BAAANQAECgQICgAAAA==.',
Tr='Triggerfarm:BAABNQAECn8dAAMQAAkKpSNiBgCrAwAQAAkKpSNiBgCrAwARAAIK0g93awB7AAAAAA==.Tristis:BAAANQADCgYICgAAAA==.',
Tu='Turthunt:BAACNQAFFH8TAAIRAAcKYhRaBAAqAgARAAcKYhRaBAAqAgA1AAQKfyQAAxEACQp4JL8aAHwCABEABwqfJL8aAHwCABAABgp8I2q2AJIBAAAA.Turtrik:BAAANQAECgIIAgABNQAFFAcIEwARAGIUAA==.',
Tw='Twinns:BAAANQADCggIDQAAAA==.Twoyoo:BAAANQAECgcIDAABNQAFFAYIGgAMABsdAA==.',
Ty='Tyesham:BAAANQADCgYICQABNQAECgQICAABAAAAAA==.Tyice:BAAANQAECgQICAAAAA==.',
Um='Umbriä:BAAANQADCgYICAABNQAECgUIBQABAAAAAA==.',
Un='Uninclined:BAAANQADCgUIBQAAAA==.',
Ur='Urak:BAAANQADCgYIBgAAAA==.',
Va='Valaidpriest:BAABNQAECn8hAAMIAAkKqR1yCwAsAwAIAAkKqR1yCwAsAwAHAAgKVxnFZQDqAQAAAA==.Valdahn:BAAANQADCgIIAgAAAA==.Valoth:BAAANQADCgUICAAAAA==.Vanelura:BAAANQAECgIIAgAAAA==.Vaporeon:BAACNQAFFH8QAAIGAAcKORpkAwBYAgAGAAcKORpkAwBYAgA1AAQKfzAAAgYACQrAJVkBANMDAAYACQrAJVkBANMDAAAA.',
Ve='Velorth:BAAANQAECgUIDgAAAA==.',
Vo='Volatileone:BAAANQAECgEIAQAAAA==.',
Vr='Vrahmageddon:BAAANQAECgUIDwAAAA==.',
Vy='Vynlorin:BAACNQAFFH8OAAIUAAUKpQRPFQAFAQAUAAUKpQRPFQAFAQA1AAQKfyQAAhQACQrcFO89AAcCABQACQrcFO89AAcCAAAA.',
Wa='Wahcked:BAAANQAECgMIAwAAAA==.Wahstella:BAACNQAFFH8hAAMXAAcK2hL7CAAyAgAXAAcKRg77CAAyAgAdAAIKxhPwBgCjAAA1AAQKfy8AAxcACQrXJIYwACsDABcACQofJIYwACsDAB0AAgq0I7wqAKAAAAAA.Waraight:BAACNQAFFH8SAAIUAAUKOhqdCwCXAQAUAAUKOhqdCwCXAQA1AAQKfxwAAhQACQqOI8sLAFMDABQACQqOI8sLAFMDAAAA.Wardrarth:BAABNQAECn8bAAQeAAcKqhVeIwDDAQAeAAcKvRJeIwDDAQAcAAMKwxOvOQG8AAAaAAIKKhSG+ACHAAAAAA==.Warlockhomes:BAAANQADCgUIBQAAAA==.Waterdroplet:BAAANQADCgcICgAAAA==.',
Wh='Whitelady:BAAANQAECggICQAAAA==.Whodofthunk:BAAANQAECgUICgAAAA==.Whodovoodoo:BAAANQADCgMIAwAAAA==.',
Wi='Wighttrash:BAAANQAECgQIBwABNQAECgkJJQAOAOwfAA==.Wilferth:BAAANQAECgYIEgAAAA==.Willøw:BAAANQAECgcICAAAAA==.Wirl:BAAANQADCggICAAAAA==.',
Wo='Woozi:BAACNQAFFH8UAAIGAAYK8xF/CADGAQAGAAYK8xF/CADGAQA1AAQKfyAAAgYACQqrGC8/AGECAAYACQqrGC8/AGECAAAA.',
Wr='Wrinklz:BAACNQAFFH8GAAIXAAIKOA19SQCSAAAXAAIKOA19SQCSAAA1AAQKfzEAAxcACQriF5lSANsCABcACQriF5lSANsCAB0AAwqDCy0wAHsAAAAA.Wrlymoonbat:BAAANQADCgQIBwAAAA==.',
Wu='Wuggles:BAAANQAECgIIAgAAAA==.Wulvirine:BAAANQAECggIAQAAAA==.',
Xa='Xavierson:BAAANQAECgQIDAAAAA==.',
Xe='Xelot:BAAANQAECgEIAQAAAA==.',
Xi='Xiaoxiao:BAAANQAECgQIBAAAAA==.Xilone:BAAANQADCgUICQAAAA==.',
Xq='Xquisid:BAABNQAECn8VAAIKAAkKMQ8HbwAOAgAKAAkKMQ8HbwAOAgAAAA==.',
Ya='Yangchengfu:BAAANQAECgQICAAAAA==.Yanjee:BAAANQAECgEIAQAAAA==.',
Yi='Yi:BAAANQAECgYIBwAAAA==.',
Yn='Ynoga:BAAANQAECggICAAAAA==.',
Yo='Yootoo:BAAANQAECgYICwABNQAFFAYIGgAMABsdAA==.Youkai:BAAANQADCgYIBgAAAA==.',
Za='Zaaga:BAABNQAECn8aAAIKAAgKsA7EgADgAQAKAAgKsA7EgADgAQAAAA==.Zaeth:BAAANQADCgYJBgAAAA==.Zamon:BAAANQADCgYICwAAAA==.Zamyk:BAAANQAECgEIAQAAAA==.Zanthara:BAAANQADCgIIAgAAAA==.Zaqor:BAAANQABCgIIAgAAAA==.Zarf:BAABNQAECn8jAAISAAkKWxJHBQBtAgASAAkKWxJHBQBtAgAAAA==.Zariq:BAAANQADCgUIBQAAAA==.Zayra:BAAANQADCggIEwAAAA==.',
Ze='Zeld:BAABNQAECn8WAAIQAAkKGRToVQBuAgAQAAkKGRToVQBuAgAAAA==.Zelgius:BAABNQAECn8zAAMlAAkKVCZTAQDfAwAlAAkKQSZTAQDfAwAbAAcKTCUlGgDuAgAAAA==.Zenfel:BAABNQAECn8eAAILAAgKXBFvDwAEAgALAAgKXBFvDwAEAgAAAA==.Zenga:BAAANQABCgYIBgAAAA==.Zephalor:BAABNQAECn8dAAIcAAgKUBiOdgA8AgAcAAgKUBiOdgA8AgAAAA==.Zeroyz:BAAANQAECgEIAwAAAA==.',
Zh='Zhulee:BAABNQAECn8aAAMDAAkKPBZ+HABSAgADAAkKPBZ+HABSAgACAAQKnxZgKgAXAQAAAA==.',
Zi='Zikaja:BAAANQAECgYIBgABNQAFFAUIDgAUAKUEAA==.Zir:BAAANQAECgUICgAAAA==.',
Zo='Zoark:BAAANQAECgIIAgAAAA==.Zorak:BAAANQADCgIIAgAAAA==.Zorgap:BAAANQAECggIDwAAAA==.Zorgaw:BAAANQAECggICgAAAA==.',
Zu='Zuggwithin:BAABNQAECn8aAAIQAAcKUxZEiQD1AQAQAAcKUxZEiQD1AQAAAA==.Zuldope:BAAANQAECgUIDAAAAA==.',
Zy='Zygo:BAAANQAECgEIAQAAAA==.Zynestra:BAAANQADCgMIAwAAAA==.Zyprexen:BAAANQADCgYIDgAAAA==.Zyprexius:BAABNQAECn8pAAMcAAgK2RvvaQBbAgAcAAgK2RvvaQBbAgAaAAQKUBOyuQAFAQAAAA==.',
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
