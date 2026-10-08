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

local lookup = {'Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Devourer','Shaman-Restoration','Priest-Holy','Priest-Shadow','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Druid-Restoration','Druid-Balance','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Evoker-Devastation','DeathKnight-Blood','Shaman-Elemental','Warrior-Fury','Mage-Arcane','DemonHunter-Havoc','Paladin-Retribution','Warrior-Protection','Mage-Frost','Paladin-Protection','Shaman-Enhancement','Evoker-Preservation','Druid-Feral','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','Priest-Discipline','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Holy','Evoker-Augmentation','DemonHunter-Vengeance',}
local provider = {region='US',realm='Lothar',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aaliara:BAAANQAECgMIAwAAAA==.',
Ab='Absynthae:BAAANQADCgcIEgAAAA==.',
Ac='Ackreser:BAAANQAECgEIAwAAAA==.',
Ad='Adorath:BAAANQADCgUICAAAAA==.',
Ae='Aedal:BAAANQADCgcIBwAAAA==.Aelethia:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Aesirah:BAAANQADCggIDQAAAA==.Aeven:BAAANQADCgEIAQABNQAFFAMICQACAB0cAA==.',
Ai='Aidan:BAACNQAFFIEyAAMDAAkKCCcBAAAmBAADAAkKCCcBAAAmBAAEAAEKQiY3CABtAAA1AAQKgR4AAwMACQovJnsFAGoDAAMACQovJnsFAGoDAAQAAgqaJooeANEAAAAA.Aidhan:BAABNQAECoEbAAIFAAkKNiSPCgAlAwAFAAkKNiSPCgAlAwABNQAFFAkJMgADAAgnAA==.Aileron:BAACNQAFFIEKAAIGAAQKOQ7qDgAxAQAGAAQKOQ7qDgAxAQA1AAQKgSYAAgYACQpCIsQTABQDAAYACQpCIsQTABQDAAAA.Airlin:BAAANQADCgYICgAAAA==.',
Ak='Akshana:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Al='Alarod:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Alcore:BAAANQAECgQJBQAAAA==.Aldrigor:BAAANQAECgUIBwAAAA==.Alett:BAAANQAECgMIBQAAAA==.Alivathus:BAABNQAECoEvAAMHAAkK2SR2AgC6AwAHAAkK2SR2AgC6AwAIAAEKfg7kbQAyAAAAAA==.Alluu:BAAANQADCgUIBQAAAA==.Alonzie:BAAANQADCggICAAAAA==.Alsong:BAAANQADCgUIDAAAAA==.Alvart:BAAANQAECgQIBQAAAA==.',
Am='Ambervoid:BAAANQAECgUJCgAAAA==.Amiko:BAAANQAECgYICwAAAA==.',
An='Annaisa:BAAANQABCgUIBQABNQAFFAMIBgAHAMQIAA==.Ansigar:BAAANQADCgcIBwAAAA==.',
Ar='Arbark:BAABNQAECoEhAAQJAAkK+CSPAQAdAwAJAAgKjiWPAQAdAwAKAAgKmCM4LAC7AgALAAQKLCB7IQBaAQAAAA==.Arcada:BAAANQADCgYIBgAAAA==.Archdemon:BAAANQADCgUIBQAAAA==.Arcnfrost:BAAANQAECgQIDAAAAA==.Ardone:BAAANQABCgIIAgAAAA==.Arkadis:BAAANQAECgUIDgAAAA==.Armina:BAAANQAECgYIBgAAAA==.Arrothin:BAAANQABCggIGQAAAA==.',
As='Asdanoth:BAAANQADCggICwAAAA==.Ashenbrawl:BAAANQAECggIEgAAAA==.Ashenclaw:BAAANQAECgUICwAAAA==.Aspinks:BAAANQAECgIIAgABNQAECggIKAAKAEUMAA==.',
Au='Auxie:BAAANQAECgcIEgAAAA==.',
Av='Availl:BAAANQADCgcIBwABNQAECgIIAwABAAAAAA==.Avatipup:BAAANQAECgUICwAAAA==.',
Aw='Aweinon:BAAANQADCgQIBAAAAA==.',
Ay='Aydan:BAAANQAFFAEIAQABNQAFFAkJMgADAAgnAA==.Aydin:BAACNQAFFIEMAAIMAAUKJx6LCQDpAQAMAAUKJx6LCQDpAQA1AAQKgRwAAgwACQpvJFUZAEcDAAwACQpvJFUZAEcDAAE1AAUUCQkyAAMACCcA.Aylan:BAAANQADCgMIAwAAAA==.',
Az='Azelous:BAAANQADCggICAABNQAFFAMIBQAGAM0dAA==.Azumaa:BAAANQADCggIIwAAAA==.Azurath:BAAANQAECgMIBgAAAA==.Azureth:BAAANQADCgEIAQAAAA==.',
Ba='Bainironwind:BAAANQADCgUIBQAAAA==.Baiwushi:BAABNQAECoEdAAICAAgKxh3pCwCnAgACAAgKxh3pCwCnAgAAAA==.Ballock:BAAANQADCggICAAAAA==.Balázs:BAAANQAECgQJCAAAAA==.Barloc:BAAANQADCgUIBQAAAA==.',
Be='Becbec:BAAANQADCgcICwAAAA==.Beckyplease:BAAANQAECgEIAQAAAA==.Belaghal:BAAANQADCgUIBQAAAA==.Ben:BAAANQAECgQIBQABNQAECgUIEAABAAAAAA==.Bestricer:BAAANQAECgIIAgABNQAFFAgILAADAC0jAA==.',
Bi='Biggles:BAECNQAFFIETAAMNAAYKeBIsAwDyAQANAAYKeBIsAwDyAQAOAAEKPQsMIgBIAAA1AAQKgSMAAw0ACQobFlwdABwCAA0ACQobFlwdABwCAA4ACAq2E5k7AO0BAAAA.Bighuntarizo:BAABNQAECoEUAAIPAAcKrha/ZgAcAgAPAAcKrha/ZgAcAgAAAA==.Bilagaana:BAAANQADCgQIBAABNQAECggIIAAEAGwaAA==.Billevilbill:BAABNQAECoEXAAMKAAgKTBHGawDzAQAKAAgKTBHGawDzAQALAAEKzAUgewAqAAAAAA==.',
Bl='Blobney:BAACNQAFFIEaAAMKAAcKJSJRAgBIAgAKAAYKnSFRAgBIAgALAAIK7yPWBADGAAA1AAQKgSQAAwsACQpxJpYGAJgCAAoABwpuJqofAO8CAAsABwoWI5YGAJgCAAAA.Bloodymouth:BAAANQAECgMIAwABNQAECgcIEgABAAAAAA==.Bluechip:BAABNQAECoEcAAIGAAcK5Q9RdwB3AQAGAAcK5Q9RdwB3AQAAAA==.Blueeagle:BAACNQAFFIELAAMQAAQKHxtIDQA9AQAQAAQKRRpIDQA9AQARAAEK8hzRAQBdAAA1AAQKgSgABBAACQoeJcMJACkDABAACQpJJMMJACkDABEAAwrhJSIKAEIBAA8AAQrUJhEcAW8AAAAA.Bluespell:BAAANQAECgUICwABNQAFFAQICwAQAB8bAA==.',
Bo='Boldalgaz:BAAANQAECgcICAAAAA==.Bolts:BAAANQADCgcIGQAAAA==.Borak:BAAANQADCgQIBAABNQAFFAMIBQAGAM0dAA==.',
Br='Braezlor:BAAANQADCgcIBwAAAA==.Brendel:BAAANQAECgEIAwAAAA==.Brewdarymor:BAAANQAECgYICQABNQAFFAMIBQASABkMAA==.Broaahhaha:BAAANQAECgEIAwAAAA==.Brumduhr:BAAANQADCgYIBgAAAA==.',
Bu='Bulletsponge:BAAANQADCgEIAQABNQAECgMIBQABAAAAAA==.Butterflyy:BAABNQAECoEnAAIPAAgKNxVVUABWAgAPAAgKNxVVUABWAgAAAA==.Butternutt:BAAANQADCgIIAgAAAA==.',
Ca='Caelena:BAAANQAECgYIDgAAAA==.',
Ce='Celestial:BAABNQAECoEoAAMLAAgKshZqCQBYAgALAAgKshZqCQBYAgAJAAIK9hHSGwB9AAAAAA==.',
Ch='Chilltest:BAAANQAECgQIBwAAAA==.Chronobacon:BAAANQADCgYICgABNQAFFAMIBQASABkMAA==.Chupacabra:BAAANQAECgQIBQAAAA==.Chuyz:BAABNQAECoEbAAIPAAkKehkDNQCqAgAPAAkKehkDNQCqAgAAAA==.Chuyzz:BAABNQAECoEpAAITAAcKaxolNgASAgATAAcKaxolNgASAgAAAA==.',
Cl='Clawdene:BAAANQADCgQIBwAAAA==.Clickchi:BAAANQADCggIFwAAAA==.Cloudwarrior:BAAANQADCgEIAQABNQAECgkJJwAUAGweAA==.',
Co='Cooties:BAAANQADCgUIBQABNQAECgEIAgABAAAAAA==.Cordeliaa:BAAANQADCggIFgAAAA==.Coven:BAAANQAECgIIBQAAAA==.',
Cr='Crunch:BAABNQAECoEqAAMVAAkKTiTCAACwAwAVAAkKTiTCAACwAwAMAAMKvRJM/gCvAAAAAA==.',
Cy='Cynderelle:BAAANQADCgYIEAAAAA==.Cynikka:BAABNQAECoEaAAIWAAgKnB14XwCtAgAWAAgKnB14XwCtAgAAAA==.Cynthor:BAAANQAECgYIEgAAAA==.',
Da='Dadtothebone:BAAANQADCggIFAAAAA==.Daghahi:BAABNQAECoEgAAIEAAgKbBpkCgBRAgAEAAgKbBpkCgBRAgAAAA==.Daishanar:BAAANQAECgYIDgAAAA==.Dalethyr:BAAANQAECgQIBAAAAA==.Darkseid:BAAANQADCgQJBAAAAA==.Darren:BAAANQAECgUIBwAAAA==.Darthflame:BAAANQADCgUIBQABNQAECggIKQAXABoXAA==.Datavi:BAAANQADCgYIDAAAAA==.David:BAAANQAECgEIBAABNQAECgUIEAABAAAAAA==.Dawuffman:BAABNQAECoEZAAIRAAcKYhVwBgAHAgARAAcKYhVwBgAHAgAAAA==.Daylia:BAAANQADCgYIBgAAAA==.',
De='Deathash:BAAANQAECgEIAQAAAA==.Deathdruid:BAABNQAECoEdAAMOAAkK2wtJPQDiAQAOAAkK2wtJPQDiAQANAAIKRQVhXwBPAAAAAA==.Deathfarm:BAAANQAECgYIEAAAAA==.Delaktrirr:BAAANQAECgEIAQABNQAECgQJCAABAAAAAA==.Deliverenc:BAAANQAECgQIBAAAAA==.Delmus:BAABNQAECoEbAAMLAAgKcBISIABlAQAKAAcKzA4+iwCcAQALAAYKJw8SIABlAQAAAA==.Delphinae:BAAANQAECgQIBQAAAA==.Demontwink:BAAANQADCggIFwAAAA==.Demount:BAAANQADCgcICAAAAA==.Devera:BAABNQAECoEYAAIOAAkKpxSuNAAbAgAOAAkKpxSuNAAbAgABNQAECgkJGQAUAKIaAA==.',
Di='Dinkylock:BAAANQADCggIDAAAAA==.Dirtykahuna:BAAANQAECgQIDQAAAA==.Dirtylock:BAAANQADCgYIBgABNQAECgQIDQABAAAAAA==.Dirtymagus:BAAANQADCgYIBgABNQAECgQIDQABAAAAAA==.Dirtypali:BAAANQADCgUIBQABNQAECgQIDQABAAAAAA==.Discosticks:BAAANQAECgEIAQAAAA==.Distress:BAAANQAECgEIAgAAAA==.',
Do='Dojoshaman:BAABNQAECoEbAAIUAAgKsSH5HwDvAgAUAAgKsSH5HwDvAgAAAA==.Doodman:BAAANQAECgYIDAAAAA==.Doubleshot:BAAANQAECgEIAQAAAA==.',
Dr='Dragondeez:BAAANQADCgUIBQABNQAECggIHQAWAPUYAA==.Dreadrend:BAAANQAECggIEAAAAA==.Dropsin:BAAANQADCggICAAAAA==.Drwn:BAAANQAECgUIDwAAAA==.',
Du='Duckroll:BAAANQAECgEIAQAAAA==.Dustmaster:BAAANQABCgIIBgAAAA==.',
Dw='Dwelknarr:BAAANQAECgQIBQAAAA==.Dwlirious:BAABNQAECoEcAAIYAAgKqgWLzABIAQAYAAgKqgWLzABIAQAAAA==.',
Ea='Eadric:BAAANQAECgIIAgAAAA==.Earendur:BAAANQAECgEIAQAAAA==.Earthfury:BAAANQAECgQIBgABNQAECgcIEwABAAAAAA==.Eaven:BAAANQADCgIIAgABNQAFFAMICQACAB0cAA==.',
Ed='Edalasar:BAAANQAECgEIAgAAAA==.Edallen:BAABNQAECoEXAAIPAAcKwxThcwD7AQAPAAcKwxThcwD7AQAAAA==.',
Ee='Eelyroc:BAAANQADCgMIAwAAAA==.',
Ei='Eilly:BAAANQAECgUIBQAAAA==.',
El='Elbrujo:BAAANQAECgQJCgAAAA==.Eleaanor:BAAANQADCgYIBgAAAA==.Elementals:BAAANQAECggJAQAAAA==.',
Em='Emaytete:BAAANQAECgUICwAAAA==.Emayteteheww:BAAANQAECgMIBwAAAA==.Emaytetem:BAAANQADCgMIAwAAAA==.Emillyra:BAAANQAECgIIAgAAAA==.Empress:BAAANQAECgEIAQABNQAFFAYIEQATAH8iAA==.',
Ep='Ephemra:BAAANQADCggJBwAAAA==.',
Es='Esteban:BAAANQAECgQICAAAAA==.',
Ev='Evisette:BAAANQADCgMIBQAAAA==.Evokethywikd:BAABNQAECoEWAAISAAkK7wzCEwDyAQASAAkK7wzCEwDyAQABNQAECgcICAABAAAAAA==.',
Fa='Fahx:BAAANQAECgIIAgAAAA==.Falwyn:BAAANQAECgIIBQAAAA==.Famidore:BAAANQADCgIIBAAAAA==.Faèlyn:BAAANQADCgUICQAAAA==.',
Fe='Felflamel:BAABNQAECoEpAAIXAAgKGhciKQAsAgAXAAgKGhciKQAsAgAAAA==.Feltest:BAAANQAECgcJDwAAAA==.Feralized:BAAANQAECgIIAgAAAA==.Ferdinan:BAABNQAECoEkAAIMAAkK9hTdVwBnAgAMAAkK9hTdVwBnAgAAAA==.',
Fl='Flareon:BAAANQAECgEIAQABNQAFFAcIEAAGADkaAA==.Flashter:BAABNQAECoEbAAMMAAcKdxHUmQCyAQAMAAcKPRHUmQCyAQAZAAEKQxb6OAA7AAAAAA==.Flax:BAAANQADCgMIAwAAAA==.Fluffycuddle:BAAANQADCgUICQAAAA==.Fluffymage:BAAANQADCgIIAwABNQAFFAMIBQASABkMAA==.',
Fo='Forrealzies:BAAANQAECgQICAAAAA==.Fortunato:BAAANQADCgEIAQAAAA==.',
Fr='Frankhs:BAAANQAECgIJAgAAAA==.',
Fu='Furchi:BAAANQADCgIIAgABNQAECgcIGQARAGIVAA==.',
Ga='Galdrel:BAAANQAECgQIDQAAAA==.Gallince:BAACNQAFFIEQAAIYAAYKASSFAQB1AgAYAAYKASSFAQB1AgA1AAQKgSMAAhgACQozJhELAJsDABgACQozJhELAJsDAAAA.Garbich:BAAANQADCgEIAgABNQADCgcIBwABAAAAAA==.Gary:BAABNQAECoEXAAIGAAcKgB3JNgBdAgAGAAcKgB3JNgBdAgAAAA==.',
Ge='Gerhart:BAAANQAECgQIBQAAAA==.',
Gh='Ghostsham:BAACNQAFFIEdAAIUAAgKqRxLAAAPAwAUAAgKqRxLAAAPAwA1AAQKgSYAAxQACQq+JtIBAOYDABQACQq+JtIBAOYDAAYAAwoJA8HiAHYAAAAA.Ghðst:BAABNQAFFIEIAAIOAAYK2RWcBgD1AQAOAAYK2RWcBgD1AQABNQAFFAgIHQAUAKkcAA==.',
Gi='Gilgamet:BAAANQADCgEIAQAAAA==.Gizmito:BAAANQADCgQIBQAAAA==.',
Gl='Glizzyman:BAAANQAECgcIEwAAAA==.',
Gn='Gnarfarm:BAAANQAECgQIBwAAAA==.',
Go='Go:BAAANQADCgYJBgABNQAECgUIBgABAAAAAA==.Gobsborne:BAAANQAECgEIAQABNQAECggIJAAaADoeAA==.Goldoran:BAAANQADCgIIAgAAAA==.Gonette:BAAANQADCgYIBgABNQAECggIIAAbAFUgAA==.Goniff:BAABNQAECoEgAAIbAAgKVSA+CwDGAgAbAAgKVSA+CwDGAgAAAA==.Goransk:BAAANQAECgEIAwAAAA==.Gorsk:BAAANQADCgYIBgABNQAECgEIAwABAAAAAA==.',
Gr='Gracelious:BAABNQAECoEmAAIYAAcKDRwVcgAcAgAYAAcKDRwVcgAcAgAAAA==.Graebeard:BAAANQADCggIFgAAAA==.Graehame:BAAANQADCgYIDAAAAA==.Greyshadow:BAAANQADCgUIBQAAAA==.Grubber:BAAANQADCgYIDAABNQAECgUIBwABAAAAAA==.Grüb:BAAANQAECgUIBwAAAA==.',
Gu='Guitar:BAAANQAECgQICAAAAA==.Guntran:BAABNQAECoEmAAIYAAgKKh8xPQC5AgAYAAgKKh8xPQC5AgAAAA==.Gurkha:BAAANQADCgYIBwAAAA==.Gurthock:BAAANQAECgYICgAAAA==.',
Gw='Gwenixx:BAAANQAECgEIAQAAAA==.',
Ha='Halios:BAAANQADCgcIDQAAAA==.Haunter:BAAANQADCgYIBgAAAA==.',
He='Headhuntin:BAABNQAECoEZAAIPAAcKNRDphADSAQAPAAcKNRDphADSAQAAAA==.Heatfang:BAAANQADCgcICQAAAA==.Hellifiknow:BAAANQADCgQIBAABNQAECgMIBQABAAAAAA==.Hellione:BAAANQAECgcIEgAAAA==.Hellmaree:BAAANQADCgEIAQAAAA==.Helltest:BAAANQAECgEIAQAAAA==.',
Hi='Hiruzèn:BAAANQAECgQICwAAAA==.',
Ho='Holyspurb:BAAANQADCgYIBgAAAA==.Holywater:BAABNQAECoEeAAIIAAgKChMFIwDzAQAIAAgKChMFIwDzAQAAAA==.Honkinhammer:BAAANQADCgYJBgABNQAECgQIBAABAAAAAA==.Hotdogman:BAACNQAFFIEgAAIQAAgK5iRMAABIAwAQAAgK5iRMAABIAwA1AAQKgSEAAhAACQptJp4BAM4DABAACQptJp4BAM4DAAE1AAQKCAgMAAEAAAAA.Hotdumpling:BAAANQAECgYIDwAAAA==.Hozo:BAAANQADCgcIBwAAAA==.',
Hu='Huegarak:BAAANQAECgQJBgAAAA==.Hunterdwarf:BAAANQABCgYIBAAAAA==.',
Hy='Hyle:BAABNQAECoEXAAIZAAcKOg5YGgBjAQAZAAcKOg5YGgBjAQAAAA==.',
Il='Illidaddy:BAAANQAECgUIBQABNQAECggIHQAWAPUYAA==.Illuminator:BAAANQAECgEIAQAAAA==.',
In='Inspectadeck:BAACNQAFFIEQAAMKAAYK5wUREwAzAQAKAAUKPwUREwAzAQALAAEKLgneGwBMAAA1AAQKgTYAAwoACQqHHgglANgCAAoACQofHgglANgCAAsABApjFgwqAB8BAAAA.',
Ir='Irsh:BAAANQADCggICAAAAA==.',
Is='Istariel:BAAANQAECgIIAgABNQAFFAgIHQAUAKkcAA==.',
It='Ithoron:BAABNQAECoEmAAITAAgKBBjALwA3AgATAAgKBBjALwA3AgAAAA==.',
Iv='Ivoree:BAAANQAECgQIBAAAAA==.',
Ja='Jaytov:BAAANQABCgQIBAAAAA==.Jazu:BAAANQAECgYIEwAAAA==.',
Je='Jerks:BAABNQAECoEkAAMcAAgK6BKFEQAxAgAcAAgK6BKFEQAxAgAGAAIK8xGm7wBZAAAAAA==.',
Jo='Jost:BAAANQADCgMIAwABNQAECgUIBgABAAAAAA==.Joval:BAAANQAECgEIAQAAAA==.Jozeph:BAAANQAECgYIDgAAAA==.',
Ju='Jusalilguy:BAAANQAECgEIAQAAAA==.',
['Jà']='Jàmie:BAAANQAECgYIBgAAAA==.',
Ka='Kaalar:BAABNQAECoEkAAIPAAgKsB1MLwC9AgAPAAgKsB1MLwC9AgAAAA==.Kaestirael:BAAANQAECgEIAQAAAA==.Kakarrot:BAAANQAECgIJAgAAAA==.Kalichnakov:BAAANQADCgYIBgAAAA==.Kamoura:BAABNQAECoEfAAIaAAgKIhrDBgBjAgAaAAgKIhrDBgBjAgAAAA==.Kapeta:BAAANQAECgUIDgAAAA==.Karmen:BAACNQAFFIEVAAIdAAYKkxyxAwAlAgAdAAYKkxyxAwAlAgA1AAQKgSMAAh0ACQrwImADAHoDAB0ACQrwImADAHoDAAAA.Karnatron:BAAANQAECgQIBQAAAA==.Karnvoid:BAAANQADCggIDwABNQAECgQIBQABAAAAAA==.Katalain:BAAANQADCggICQABNQAFFAMIBgANAO0VAA==.Kayleave:BAAANQABCgEIAQAAAA==.Kazz:BAAANQADCggIDwABNQAECgkJKgAeADchAA==.',
Ke='Keattz:BAACNQAFFIEpAAIMAAgKeyNQAABaAwAMAAgKeyNQAABaAwA1AAQKgS4AAgwACQq4JhYDAOADAAwACQq4JhYDAOADAAE1AAQKCQktAB8ANSQA.Keattzxd:BAABNQAECoEtAAMfAAkKNST/AQC3AwAfAAkKNST/AQC3AwAgAAMKPQ8TPACxAAAAAA==.Keedill:BAABNQAECoEeAAMJAAgKKhVyCADhAQAJAAcKTxJyCADhAQAKAAcKmBQ3ewDHAQAAAA==.Keelinnea:BAAANQAECgEIAQAAAA==.Keelu:BAAANQADCgEIAQAAAA==.Keggerz:BAAANQADCgcIDAAAAA==.Kennagi:BAAANQAECgQICQAAAA==.Kenshunterl:BAAANQAECgQIBQAAAA==.',
Kh='Khanzen:BAAANQAECgQIBgAAAA==.Khathgar:BAABNQAECoEYAAIfAAcKDQ5AOQCvAQAfAAcKDQ5AOQCvAQABNQAECgkJKgAeAM4aAA==.Khovastis:BAACNQAFFIETAAMOAAYKJRs6CQC0AQAOAAUKex06CQC0AQAeAAEKeA94AwBhAAA1AAQKgSMABA4ACQqzGsMwADYCAA4ACAoLHMMwADYCACEAAwr5E2E0ALYAAB4AAgqSFlIqAHsAAAAA.',
Ki='Kianll:BAAANQAECggICAAAAA==.Kitchntabls:BAACNQAFFIEUAAIXAAYKSxxiAwAgAgAXAAYKSxxiAwAgAgA1AAQKgSMAAxcACQoPJjQDALcDABcACQoPJjQDALcDAAUAAwr/DwZQAJwAAAAA.',
Kj='Kjirou:BAABNQAECoEZAAIIAAcKRx4DGQBmAgAIAAcKRx4DGQBmAgAAAA==.',
Ko='Koenji:BAACNQAFFIESAAIcAAYKGhbyAAAgAgAcAAYKGhbyAAAgAgA1AAQKgSAAAhwACQoRIiMFADIDABwACQoRIiMFADIDAAAA.Korenn:BAAANQAECgQIBAAAAA==.Korgrim:BAAANQAECgEIAgAAAA==.',
Ky='Kymal:BAAANQAECgEIAgAAAA==.Kynana:BAAANQAECgQIBAABNQAECggIDwABAAAAAA==.Kyndel:BAAANQADCgQIBwAAAA==.Kyndrah:BAABNQAECoEbAAQHAAgKhxB6XQDYAQAHAAgKRhB6XQDYAQAIAAgKFg3kKgCnAQAiAAMKaQSxGgB2AAABNQADCgQIBwABAAAAAA==.',
['Kä']='Käne:BAABNQAECoEXAAIjAAcKMA2CXgBvAQAjAAcKMA2CXgBvAQAAAA==.',
['Kì']='Kìn:BAAANQADCgIIAgABNQAECgcIEwABAAAAAA==.',
['Kí']='Kín:BAAANQADCgEIAQABNQAECgcIEwABAAAAAA==.',
La='Lableue:BAAANQAECgEIAgAAAA==.Landuchi:BAAANQAECgYIBgAAAA==.Lavacask:BAAANQADCggJHgAAAA==.',
Le='Lehvy:BAAANQADCggICAABNQAFFAMIBQAHABAFAA==.Leodk:BAACNQAFFIEKAAMkAAQKUhyVCQD/AAAkAAMKLhyVCQD/AAAjAAEKvxxXGwBPAAA1AAQKgSUAAyQACQoLJUgKADUDACQACQoLJUgKADUDACMABgoUIL9RAKMBAAE1AAUUBAoKACQAUhwA.Lerann:BAAANQADCgQIBAABNQAECggIIAAMAOwlAA==.Levey:BAACNQAFFIEFAAIHAAMKEAWuGwDXAAAHAAMKEAWuGwDXAAA1AAQKgTkAAgcACQroHQwVABIDAAcACQroHQwVABIDAAAA.Lewdcifer:BAAANQAECgQIBwAAAA==.',
Li='Lick:BAAANQAECgMIAwABNQAECgUIBgABAAAAAA==.Lict:BAACNQAFFIEKAAIlAAQKUw7YDgA4AQAlAAQKUw7YDgA4AQA1AAQKgRoAAiUACQoBGBc0AHgCACUACQoBGBc0AHgCAAE1AAQKBQgGAAEAAAAA.Liekki:BAAANQADCgYIBwABNQAECgQIBQABAAAAAA==.Lillea:BAAANQAECgUIDQAAAA==.Linada:BAAANQAECgEIAgAAAA==.Listurfiend:BAAANQADCgIIAgAAAA==.Liteseraph:BAAANQAECgQICAAAAA==.',
Lo='Loktalaan:BAACNQAFFIEOAAIcAAYKXBAZAQAFAgAcAAYKXBAZAQAFAgA1AAQKgS4AAhwACQpEHdgEADkDABwACQpEHdgEADkDAAAA.Lothlorian:BAAANQADCgEIAQAAAA==.',
Lu='Luan:BAAANQAECgQIBAAAAA==.Lucien:BAACNQAFFIEGAAINAAMK7RVuCQACAQANAAMK7RVuCQACAQA1AAQKgSsAAg0ACQrAHFkNAN0CAA0ACQrAHFkNAN0CAAAA.Lute:BAABNQAECoEaAAMUAAgK/iPMFwAkAwAUAAgK/iPMFwAkAwAGAAEKyA2lEgEiAAAAAA==.',
Ly='Lyfeguard:BAABNQAECoEWAAIHAAcKsw9jagCpAQAHAAcKsw9jagCpAQAAAA==.',
Ma='Machoke:BAAANQADCgYIDQAAAA==.Mahito:BAABNQAECoEqAAIeAAkKNyH5AgBiAwAeAAkKNyH5AgBiAwAAAA==.Maiha:BAAANQAECgYICwABNQAECggIDwABAAAAAA==.Malenia:BAACNQAFFIEQAAMKAAUK0wx+EwAuAQAKAAQKzA1+EwAuAQALAAIKFgnnDgCVAAA1AAQKgSQABAsACQpDH8ccAH8BAAoACArRF6leABkCAAsABQoqH8ccAH8BAAkABAqUExcTAO4AAAAA.Malume:BAAANQADCgYICAAAAA==.Malyon:BAAANQADCgEIAQAAAA==.Malístra:BAAANQADCggICgAAAA==.Manaless:BAAANQAECgEIAQABNQAFFAQKCgAkAFIcAA==.Marderer:BAABNQAECoEZAAIfAAgKRQ5zMADmAQAfAAgKRQ5zMADmAQAAAA==.Masakari:BAABNQAECoEgAAIPAAgKbBM4WABBAgAPAAgKbBM4WABBAgAAAA==.Materia:BAAANQAECgQIBQAAAA==.Mathmagician:BAABNQAECoEdAAIWAAgK9RjLeAB2AgAWAAgK9RjLeAB2AgAAAA==.Maulfarm:BAACNQAFFIEJAAMeAAYK0g73AACjAQAeAAUKlBH3AACjAQAOAAEKCAFdJwAkAAA1AAQKgSAAAh4ACQqMID4EACwDAB4ACQqMID4EACwDAAAA.Mazz:BAAANQABCgYIBgABNQAECgEIAQABAAAAAA==.Mazzlock:BAAANQAECgEIAQAAAA==.',
Mc='Mclovn:BAAANQADCgEIAQAAAA==.',
Me='Megameow:BAABNQAECoEqAAMeAAkKzhowBgDkAgAeAAkKzhowBgDkAgANAAQKLA1rQwDaAAAAAA==.Mercuria:BAAANQADCgMIAwAAAA==.Messmer:BAAANQAECgYIBgAAAA==.Metaclass:BAAANQAECgIIAwAAAA==.',
Mi='Mirâ:BAAANQADCgcICQAAAA==.Mitrixx:BAABNQAECoEXAAIcAAcKgxWIEwAKAgAcAAcKgxWIEwAKAgAAAA==.Miztie:BAAANQADCgQIBAAAAA==.',
Mo='Mobius:BAAANQAECgEIAQAAAA==.Mokuo:BAAANQAECgYIBgAAAA==.Moonthorn:BAAANQAECgUIDQAAAA==.Morrow:BAAANQADCgEIAQAAAA==.Mort:BAAANQAECgMIAwAAAA==.Moxou:BAAANQAECgIIAgABNQAFFAcIFgAGAPcaAA==.Moxxou:BAACNQAFFIEWAAIGAAcK9xr+AQB1AgAGAAcK9xr+AQB1AgA1AAQKgSUAAgYACQpUJWwDAKUDAAYACQpUJWwDAKUDAAAA.Moyi:BAAANQAECgEJAQAAAA==.',
Mu='Mulch:BAABNQAECoEtAAINAAgKYg/tJgC5AQANAAgKYg/tJgC5AQAAAA==.',
My='Mybelle:BAAANQADCgIIAgAAAA==.Mysticle:BAAANQADCgcIFQAAAA==.Mythaltis:BAABNQAECoEeAAIXAAcKBCPjGACyAgAXAAcKBCPjGACyAgAAAA==.',
Na='Naedori:BAAANQADCgYICAABNQAECgYIBgABAAAAAA==.Naizhruk:BAAANQADCgEIAQAAAA==.Nall:BAAANQADCgIIBAAAAA==.Naoh:BAAANQADCgQJBAAAAA==.Narache:BAAANQADCgYIBwAAAA==.Naturerend:BAAANQADCgYJBgAAAA==.Nau:BAAANQADCgQIBAAAAA==.Naul:BAACNQAFFIEFAAISAAMKfQ5XCADXAAASAAMKfQ5XCADXAAA1AAQKgRgAAxIACQp+EqoVAM8BABIACAqIDqoVAM8BACYABApYFjgPAB8BAAAA.Naull:BAAANQAECgEIAgAAAA==.Naysayer:BAAANQADCgQIBQAAAA==.Naúl:BAAANQADCgUIBQAAAA==.',
Ne='Necrokai:BAABNQAECoEWAAINAAkKiR6XCQASAwANAAkKiR6XCQASAwAAAA==.Necroscourge:BAABNQAECoEXAAITAAcKehhaOgD7AQATAAcKehhaOgD7AQABNQAECgkJFgANAIkeAA==.Neighter:BAAANQAECgUICgAAAA==.Nerevar:BAAANQAECgEIAQAAAA==.Netal:BAAANQAECgQJCgAAAA==.Nevergoback:BAAANQADCgcICwABNQAECggIIQATAE4NAA==.',
Ni='Ninejuanjuan:BAABNQAECoEkAAIlAAgKBBXpPgBLAgAlAAgKBBXpPgBLAgAAAA==.Nishikienrai:BAAANQAECggIBgAAAA==.',
No='Nochit:BAACNQAFFIEVAAIOAAYK9iPBAgB+AgAOAAYK9iPBAgB+AgA1AAQKgSgAAg4ACQrXJuQBANkDAA4ACQrXJuQBANkDAAAA.Noctula:BAABNQAECoEVAAQJAAYKmxItDAB3AQAJAAYKmxItDAB3AQAKAAQKPA9D2gDoAAALAAIKqQK1ZQBLAAABNQAECgkJFgANAIkeAA==.Norbiee:BAAANQAECgYIDgAAAA==.Nored:BAAANQAECgQIBwAAAA==.Norne:BAABNQAECoEnAAIXAAgK6RneJwA2AgAXAAgK6RneJwA2AgAAAA==.Nowfaleena:BAAANQAECgMIBAAAAA==.Nozok:BAAANQAECgEIAQAAAA==.',
Ny='Nymphira:BAAANQAECgUIBQAAAA==.Nytkiller:BAAANQAECgEIAQAAAA==.Nyzul:BAAANQAECgIIBQABNQAECggIGwALAHASAA==.',
['Në']='Nëv:BAAANQADCgIIAgAAAA==.',
Oa='Oatie:BAAANQADCgUIAwAAAA==.',
Oc='Oceanic:BAAANQAECgUIDgAAAA==.',
Od='Odlinn:BAAANQAECgUIEgABNQAECggILQANAGIPAA==.',
On='Onlyhorns:BAAANQAECgYICgABNQAECgkJIAAcAEAkAA==.',
Oo='Oogs:BAAANQAECgEIAQAAAA==.',
Op='Opalia:BAAANQAECgUICgAAAA==.Opallea:BAAANQAECgIIBQABNQAECgIIBQABAAAAAA==.Oppa:BAAANQADCgEIAQABNQAECgIIBQABAAAAAA==.',
Or='Orch:BAAANQAECgYIFgAAAQ==.',
Ov='Overclocked:BAABNQAECoEoAAIKAAgKRQxrewDGAQAKAAgKRQxrewDGAQAAAA==.',
Pa='Paddington:BAABNQAECoEbAAIhAAgKxQtmHwBcAQAhAAgKxQtmHwBcAQAAAA==.Pahbi:BAAANQAECgEIAQAAAA==.Palempi:BAAANQADCggICgAAAA==.Papadawn:BAAANQAECgEIAQAAAA==.Paratus:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
Pe='Pendojo:BAAANQAECggIEAAAAA==.Pendomage:BAAANQAECgYIDQAAAA==.',
Ph='Phobius:BAAANQAECgIIAgAAAA==.',
Pi='Pip:BAABNQAECoEZAAMUAAkKoho0SQAlAgAUAAgKnho0SQAlAgAGAAIKDwOu7wBZAAAAAA==.Pipium:BAABNQAECoEYAAIJAAkK1SGrBABlAgAJAAkK1SGrBABlAgABNQAECgkJGQAUAKIaAA==.Pixsin:BAAANQAECgUIBQABNQAECgkJLwAKABcaAA==.',
Po='Pookiehandz:BAABNQAECoEhAAITAAgKTg3BVAB/AQATAAgKTg3BVAB/AQAAAA==.Porpul:BAAANQAECgIIAgAAAA==.Powery:BAAANQAECgcICgAAAA==.',
Pr='Project:BAAANQAECgQICgAAAA==.Prophet:BAAANQADCgcIBwAAAA==.',
Pu='Publicbussy:BAAANQADCgcIFQAAAA==.Purples:BAAANQAECgYJCgAAAA==.Purpul:BAAANQAECgQIBAABNQAECgYJCgABAAAAAA==.',
Qa='Qawxz:BAAANQADCgUIBQAAAA==.',
Qu='Quicktail:BAAANQAECgEIAQABNQAECggIJAAaADoeAA==.',
Ra='Raikan:BAABNQAECoEgAAIMAAgK7CUYDwB+AwAMAAgK7CUYDwB+AwAAAA==.Rainwater:BAAANQADCgEIAQAAAA==.Raisins:BAAANQADCggICAABNQAFFAYIEgAHAMwaAA==.Raisyns:BAACNQAFFIESAAIHAAYKzBqZBAA2AgAHAAYKzBqZBAA2AgA1AAQKgSMAAwcACQrtIhYOAD8DAAcACQrtIhYOAD8DACIAAQqQHMIhAEEAAAAA.Rammic:BAAANQADCgIIAgAAAA==.Randstohl:BAAANQADCggIDgAAAA==.Ratakhan:BAAANQADCgUICAAAAA==.Raulothim:BAAANQAECgYIDgAAAA==.',
Re='Rebell:BAAANQAECggIDwAAAA==.Reelorn:BAAANQADCgYIBgAAAA==.Reny:BAAANQAECgIIAwAAAA==.Repentance:BAAANQADCgEIAQABNQADCgYIBwABAAAAAA==.Retribussy:BAABNQAECoEeAAIYAAgKSCLrJgAPAwAYAAgKSCLrJgAPAwAAAA==.',
Ri='Ribbed:BAAANQAECgMIAwABNQAECgUIBgABAAAAAA==.Ricemachinex:BAABNQAECoEbAAMKAAkKOxb1cwDcAQAKAAcKPRP1cwDcAQALAAMK5RYlNADnAAABNQAFFAgILAADAC0jAA==.Ricemachnedk:BAAANQAECggIDwABNQAFFAgILAADAC0jAA==.Riko:BAAANQAECgUIBQABNQAECgkJKgAeADchAA==.',
Ro='Rocthar:BAABNQAECoEkAAIlAAgK0Q22YADRAQAlAAgK0Q22YADRAQAAAA==.Roguelite:BAAANQADCgEIAQABNQAFFAQKCgAkAFIcAA==.Romarus:BAAANQAECgYIDwAAAA==.Romeoposter:BAAANQAECgcIEAAAAA==.',
Ru='Rukarazyll:BAAANQAECgQIBwAAAA==.Rumble:BAAANQAECgQIBQAAAA==.Rutherford:BAAANQADCgQIBAAAAA==.Ruush:BAAANQAECgMIBQAAAA==.',
Ry='Rypach:BAAANQAECgUIEAAAAA==.Ryunohige:BAAANQADCggICAAAAA==.',
['Rú']='Rúúsh:BAAANQAECgQIBgAAAA==.',
Sa='Safeword:BAAANQAECgQICgAAAA==.Saihua:BAAANQADCgYIBgAAAA==.Saintjohn:BAAANQAECgcIDgAAAA==.Saintjon:BAAANQAECggIEAAAAA==.Saintjonn:BAABNQAECoEcAAMkAAgKrg2oSgBFAQAkAAYKRxGoSgBFAQAjAAcKyAt8fgD5AAAAAA==.Saintrob:BAAANQADCgMJAwAAAA==.Salamando:BAEANQAFFAEIAQABNQAFFAQIDQAMAAsdAA==.Sarthdidius:BAABNQAECoElAAIXAAgK7gk+PgCTAQAXAAgK7gk+PgCTAQAAAA==.Sassparilluh:BAAANQAECgEIAQAAAA==.Savalla:BAAANQADCgYIBgAAAA==.',
Sc='Scarletflamè:BAAANQADCgEIAQAAAA==.Schadenfreud:BAAANQAECgQIBQAAAA==.Scholoman:BAAANQADCggIDgAAAA==.Scratchbelly:BAAANQADCggIDQAAAA==.Scumdog:BAAANQADCgYIBgAAAA==.',
Se='Senpai:BAACNQAFFIEQAAIWAAYK8RKmDADzAQAWAAYK8RKmDADzAQA1AAQKgSIAAxYACQqaII05AAcDABYACQqaII05AAcDABoAAQrlH7U4AEUAAAAA.Seoli:BAAANQAECgEIAQAAAA==.Serenya:BAAANQADCgYIBgAAAA==.',
Sh='Shalanthra:BAAANQAECgQIBwAAAA==.Shamallow:BAAANQADCgQIBAAAAA==.Shammunition:BAABNQAECoEgAAIcAAkKQCSeAQCiAwAcAAkKQCSeAQCiAwAAAA==.Shamussy:BAAANQAECgUIDAAAAA==.Shartner:BAAANQADCgMJAwAAAA==.Shartz:BAAANQAECgUIDQAAAA==.Shaysa:BAEANQAECgYIEAAAAA==.Sheraa:BAAANQAECgYIDAAAAA==.Shinigamisan:BAAANQAECgcIEgAAAA==.Shynox:BAABNQAECoEWAAMlAAcKdB0kOwBbAgAlAAcKdB0kOwBbAgAYAAQK9A4dBQHeAAAAAA==.Shümp:BAAANQAECgIIAgAAAA==.',
Si='Sinnerchrono:BAAANQADCggIBwAAAA==.Sinnwoo:BAAANQABCgQIBgAAAA==.Sitharco:BAAANQAECgMICgAAAA==.',
Sk='Skimmilk:BAAANQADCgYIDQABNQAFFAMICAAZANkdAA==.',
Sl='Sladex:BAAANQAECgIIAgAAAA==.Sleeptoken:BAAANQADCgEIAQAAAA==.',
Sm='Smorc:BAAANQAECgcIEgAAAA==.',
Sn='Snackwitch:BAAANQAECgIIAgAAAA==.Sneaki:BAAANQAECgYIDAABNQAECgcIEgABAAAAAA==.',
So='Soarseas:BAAANQADCgYIBgAAAA==.Sommin:BAAANQADCgYICgAAAA==.Songy:BAAANQADCgUICQAAAA==.Sorakah:BAAANQAECgMIBAAAAA==.Soulviper:BAABNQAECoEwAAMGAAkK7xeLQAA0AgAGAAkK7xeLQAA0AgAUAAYKogsckABLAQAAAA==.',
Sp='Spankmyflank:BAAANQAECgIIBQAAAA==.Spurblock:BAAANQADCgYJBgAAAA==.',
Sq='Squaleon:BAAANQADCgQIBAAAAA==.',
St='Stabbyfinch:BAAANQAECgQIBQAAAA==.Steatfox:BAAANQADCgUIBQAAAA==.Steplok:BAAANQAECgQIBAAAAA==.Stonestriker:BAAANQAECgQIBQAAAA==.Stooben:BAABNQAECoEcAAIMAAgKURUwegAHAgAMAAgKURUwegAHAgAAAA==.Stoobenh:BAAANQAECgQIBAAAAA==.Sturge:BAAANQAECgEIAQAAAA==.',
Su='Supahsayajin:BAAANQAECgcIEAABNQAECgcICAABAAAAAA==.',
Sw='Sweetbee:BAAANQAECgYIEQAAAA==.Sweetpotato:BAAANQADCggICAAAAA==.Sweetvaldine:BAAANQADCgcIDAAAAA==.Swole:BAAANQAECgQIBQAAAA==.',
Sy='Syanalody:BAAANQAECgEIAQAAAA==.Sylarz:BAAANQAECgcIEgABNQAFFAMIBQASABkMAA==.Sylenn:BAAANQAECgEIAQAAAA==.Syn:BAABNQAECoEhAAMJAAgKCCFxAwCkAgAJAAcKSCFxAwCkAgAKAAIKIBne/QCXAAAAAA==.Synchro:BAAANQADCgQIBAAAAA==.',
Ta='Tactics:BAAANQADCgQIBAAAAA==.Talanna:BAAANQADCgYIBgAAAA==.Tanstaafl:BAABNQAECoEkAAIPAAgKsR/dJwDZAgAPAAgKsR/dJwDZAgAAAA==.Taralom:BAAANQAECgQIBQAAAA==.Taurenspurb:BAAANQADCgYIDAAAAA==.Taz:BAEBNQAECoErAAMnAAkK+iWCAADWAwAnAAkK+iWCAADWAwAXAAEKPQFKlAAFAAAAAA==.',
Te='Telmo:BAAANQAECgcIDQAAAA==.Tenebrix:BAAANQAECgUIBgAAAA==.Tenevoy:BAABNQAECoEZAAMIAAkKexu4EQDEAgAIAAgKmR24EQDEAgAHAAkKLQ75TQASAgABNQAFFAgIHQAUAKkcAA==.',
Th='Thadex:BAABNQAECoEaAAMMAAkKYx+OPwC0AgAMAAgKJyCOPwC0AgAVAAEKSBmRKQBEAAAAAA==.Thebigfreeze:BAAANQABCgMIAQAAAA==.Thedood:BAAANQADCgYIBgAAAA==.Thedruidguy:BAAANQADCgQIBAAAAA==.Theldrid:BAACNQAFFIEFAAIjAAMKlhXwDgDrAAAjAAMKlhXwDgDrAAA1AAQKgTEAAiMACQoSJDUMAEQDACMACQoSJDUMAEQDAAAA.Thepallyguy:BAAANQAECgQIBAABNQAECgYIEgABAAAAAA==.Theprepared:BAAANQAECgEIAQAAAA==.Thepriestguy:BAAANQAECgYIEgAAAA==.Theralethia:BAAANQAECgQIBAAAAA==.Therian:BAAANQADCgIJAwAAAA==.Theshamanguy:BAAANQAECgMIBAABNQAECgYIEgABAAAAAA==.Thorseas:BAABNQAECoEeAAIRAAcKwCGXAwCoAgARAAcKwCGXAwCoAgAAAA==.Thunderkill:BAAANQADCgYICwAAAA==.',
Ti='Tirissa:BAAANQADCggICgAAAA==.',
To='Tooyew:BAAANQAECgYIBgABNQAFFAYIFAAMANMXAA==.Tooyoo:BAACNQAFFIEUAAIMAAYK0xe7BgAkAgAMAAYK0xe7BgAkAgA1AAQKgRkAAgwACQqLIh8cADoDAAwACQqLIh8cADoDAAAA.Torpedotaka:BAAANQAECgMIBAAAAA==.',
Tp='Tpala:BAAANQAECgQICgAAAA==.',
Tr='Triggerfarm:BAABNQAECoEZAAMPAAkKOiTjBACyAwAPAAkKOiTjBACyAwAQAAEK0g8VdgA6AAAAAA==.Tristis:BAAANQADCgYICgAAAA==.',
Tu='Turthunt:BAACNQAFFIESAAIQAAcKlxgGAwBBAgAQAAcKlxgGAwBBAgA1AAQKgSIAAxAACQrLJMcWAI0CABAABwqKJMcWAI0CAA8ABgqRIvecAJoBAAAA.Turtrik:BAAANQAECgIIAgABNQAFFAcIEgAQAJcYAA==.',
Tw='Twinns:BAAANQADCgUIBQAAAA==.Twoyoo:BAAANQAECgYIBgABNQAFFAYIFAAMANMXAA==.',
Ty='Tyesham:BAAANQADCgYICQABNQAECgIIBAABAAAAAA==.Tyice:BAAANQAECgIIBAAAAA==.',
Um='Umbriä:BAAANQADCgYICAABNQAECgUIBQABAAAAAA==.',
Un='Uninclined:BAAANQADCgUIBQAAAA==.',
Ur='Urak:BAAANQADCgYIBgAAAA==.',
Va='Valaidpriest:BAABNQAECoEaAAMIAAkKeh0nEwCyAgAIAAgKqRwnEwCyAgAHAAgKVxnIVQD0AQAAAA==.Valdahn:BAAANQADCgIIAgAAAA==.Valoth:BAAANQADCgUICAAAAA==.Vanelura:BAAANQAECgIIAgAAAA==.Vaporeon:BAACNQAFFIEQAAIGAAcKORpPAgBoAgAGAAcKORpPAgBoAgA1AAQKgTAAAgYACQrAJdcAANcDAAYACQrAJdcAANcDAAAA.',
Ve='Velorth:BAAANQAECgUICQAAAA==.',
Vr='Vrahmageddon:BAAANQAECgUIDwAAAA==.',
Vy='Vynlorin:BAACNQAFFIENAAITAAQK9QRaFQDSAAATAAQK9QRaFQDSAAA1AAQKgSIAAhMACQrQFMU4AAMCABMACQrQFMU4AAMCAAAA.',
Wa='Wahcked:BAAANQADCggIDAAAAA==.Wahstella:BAACNQAFFIEgAAMWAAcK7xSpBQBBAgAWAAcKqhGpBQBBAgAaAAIKxhPQBACrAAA1AAQKgS8AAxYACQpfJGskAEIDABYACQrRI2skAEIDABoAAgq0I9MkAKcAAAAA.Waraight:BAACNQAFFIERAAITAAUKBxtYCQCZAQATAAUKBxtYCQCZAQA1AAQKgRwAAhMACQoaJNsIAGUDABMACQoaJNsIAGUDAAAA.Wardrarth:BAAANQAECgYIEwAAAA==.Warlockhomes:BAAANQADCgUIBQAAAA==.Waterdroplet:BAAANQADCgcICgAAAA==.',
Wh='Whitelady:BAAANQAECggICQAAAA==.Whodofthunk:BAAANQAECgMIBQAAAA==.',
Wi='Wighttrash:BAAANQAECgQIBwABNQAECgkJJQANAOwfAA==.Wilferth:BAAANQAECgYIEgAAAA==.Willøw:BAAANQAECgUIBgAAAA==.Wirl:BAAANQADCggICAAAAA==.',
Wo='Woozi:BAACNQAFFIEPAAIGAAUKZhCzCgCBAQAGAAUKZhCzCgCBAQA1AAQKgR4AAgYACQqrGEI0AGkCAAYACQqrGEI0AGkCAAAA.',
Wr='Wrinklz:BAABNQAECoEsAAMWAAkKNhnzSgDdAgAWAAkKNhnzSgDdAgAaAAMKrwjBKgB7AAAAAA==.Wrlymoonbat:BAAANQADCgQIBwAAAA==.',
Wu='Wuggles:BAAANQAECgIIAgAAAA==.',
Xa='Xavierson:BAAANQAECgQICAAAAA==.',
Xe='Xelot:BAAANQAECgEIAQAAAA==.',
Xi='Xiaoxiao:BAAANQAECgQIBAAAAA==.Xilone:BAAANQADCgUICQAAAA==.',
Xq='Xquisid:BAAANQAECgYIBgAAAA==.',
Ya='Yangchengfu:BAAANQAECgQICAAAAA==.',
Yi='Yi:BAAANQAECgUIBgAAAA==.',
Yn='Ynoga:BAAANQAECggICAAAAA==.',
Yo='Yootoo:BAAANQAFFAEIAQABNQAFFAYIFAAMANMXAA==.',
Za='Zaaga:BAAANQAECgYIDwAAAA==.Zaeth:BAAANQADCgYJBgAAAA==.Zamon:BAAANQADCgYICwAAAA==.Zamyk:BAAANQAECgEIAQAAAA==.Zanthara:BAAANQADCgIIAgAAAA==.Zaqor:BAAANQABCgIIAgAAAA==.Zarf:BAABNQAECoEjAAIRAAkK7BJNBAB/AgARAAkK7BJNBAB/AgAAAA==.Zariq:BAAANQADCgUIBQAAAA==.Zayra:BAAANQADCggIDQAAAA==.',
Ze='Zeld:BAAANQAECgcIEgAAAA==.Zelgius:BAABNQAECoEtAAMkAAgKUiYuBwBeAwAkAAgKOSYuBwBeAwAjAAcKeSUBFgDyAgAAAA==.Zenfel:BAABNQAECoEXAAILAAcKwxKNEwDLAQALAAcKwxKNEwDLAQAAAA==.Zephalor:BAAANQAECgcIEwAAAA==.Zeroyz:BAAANQAECgEIAgAAAA==.',
Zh='Zhulee:BAAANQAECgcIEgAAAA==.',
Zi='Zikaja:BAAANQAECgYIBgABNQAFFAQIDQATAPUEAA==.Zir:BAAANQAECgUICgAAAA==.',
Zo='Zoark:BAAANQAECgIIAgAAAA==.Zorak:BAAANQADCgIIAgAAAA==.Zorgap:BAAANQAECggIDwAAAA==.Zorgaw:BAAANQAECggICgAAAA==.',
Zu='Zuggwithin:BAABNQAECoEaAAIPAAcK2BWQcgD+AQAPAAcK2BWQcgD+AQAAAA==.Zuldope:BAAANQAECgUICAAAAA==.',
Zy='Zygo:BAAANQAECgEIAQAAAA==.Zynestra:BAAANQADCgMIAwAAAA==.Zyprexen:BAAANQADCgYIDgAAAA==.Zyprexius:BAABNQAECoElAAMYAAgK8RmDWQBhAgAYAAgK8RmDWQBhAgAlAAQKUBN3pgAKAQAAAA==.',
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
