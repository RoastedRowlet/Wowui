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

local lookup = {'Rogue-Outlaw','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Unholy','Mage-Arcane','Mage-Frost','Druid-Balance','Priest-Shadow','Priest-Holy','Priest-Discipline','Shaman-Elemental','DeathKnight-Blood','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','Unknown-Unknown','Shaman-Restoration','Warlock-Demonology','Druid-Restoration','Evoker-Devastation','Hunter-BeastMastery','Warrior-Arms','Warrior-Fury','Monk-Mistweaver','Monk-Brewmaster','Warrior-Protection','Evoker-Preservation','Mage-Fire','Evoker-Augmentation','Druid-Guardian','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Rogue-Assassination','Warlock-Affliction','Druid-Feral',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aanuanaela:BAABNQAECn8oAAIBAAkKzhGIAgCeAQABAAkKzhGIAgCeAQAAAA==.Aanubis:BAAANQADCgUIBQAAAA==.',
Ab='Absens:BAABNQAECn8xAAICAAoKPA05BABmAQACAAoKPA05BABmAQAAAA==.Abumim:BAAANQAECgQIBAAAAA==.',
Ad='Adorian:BAAANQAECgQIBAABNQAECgoKMwADAO0gAA==.Adwillon:BAAANQAECgQIAwAAAA==.',
Af='Aforceofone:BAAANQAECgcIDAAAAA==.',
Ag='Aggretsuko:BAABNQAECn8rAAMEAAoKuRW0QAAaAgAEAAgK6hi0QAAaAgADAAkKQAnOTgB5AQAAAA==.',
Al='Aldonza:BAAANQADCgIIAgAAAA==.Alex:BAAANQAECgUIDgAAAA==.Alivanllan:BAAANQAECgQIBQAAAA==.Aluviel:BAACNQAFFH8KAAMFAAMKdhx9LgAdAQAFAAMKdhx9LgAdAQAGAAEKAQwdEwBIAAA1AAQKfxoAAwUACQo3JYsiAFIDAAUACQo3JYsiAFIDAAYAAQoNIToiAGMAAAE1AAUUCAgYAAcA0SQA.Alyslia:BAAANQABCggIGQAAAA==.',
An='Anamuht:BAABNQAECn8vAAQIAAgKDxOZLgCwAQAIAAgKDxOZLgCwAQAJAAcK4Qu8jABwAQAKAAMKEgcpHQB6AAABNQAECgkJMwALAPwdAA==.Angeli:BAAANQAECgEIAQAAAA==.Annaday:BAABNQAECn8dAAIMAAgKtQ9TOQD+AAAMAAgKtQ9TOQD+AAAAAA==.Antiock:BAABNQAECn8zAAQDAAoK7SA8EQAFAwADAAoKEx08EQAFAwAMAAcKzyLrLwBSAgAEAAcKnxksQwAOAgAAAA==.Anyamonka:BAAANQAECgcIEgAAAA==.',
Ap='Appalachia:BAAANQADCgYJBgAAAA==.',
Ar='Ariea:BAAANQADCgEIAQAAAA==.Arraven:BAAANQADCggIBwAAAA==.Arrowmir:BAAANQABCgYJCAAAAA==.Artto:BAAANQADCgIIAgAAAA==.',
As='Ashbrínger:BAABNQAECn87AAINAAoKQiLDGABhAwANAAoKQiLDGABhAwAAAA==.',
At='Atua:BAAANQAECgEIAgAAAA==.',
Av='Averax:BAABNQAECn8pAAMOAAkK+yBrDwD5AgAOAAkK+yBrDwD5AgAPAAEKAAB3jQBBAAAAAA==.Avylbrew:BAAANQADCgcICgABNQAECgIIAgAQAAAAAA==.',
Ay='Aylakaye:BAAANQADCggICQAAAA==.',
Az='Azzathoth:BAAANQADCggICAAAAA==.',
Ba='Babybilly:BAABNQAECn8jAAMLAAoKJB7iFQBVAgALAAkKzR7iFQBVAgARAAYKgR2bNADMAQAAAA==.Babyshoes:BAAANQAECgQIBwAAAA==.Backpack:BAAANQAECgcIDAAAAA==.Bananawaffle:BAAANQADCgEIAQAAAA==.Bandan:BAAANQAECgcIEQAAAA==.Bato:BAAANQADCgUIDAAAAA==.',
Be='Beauvito:BAAANQADCgEIAQAAAA==.Beefjurkey:BAAANQAECgQICQAAAA==.Betch:BAAANQAECggIBQABNQAECggIDAAQAAAAAA==.',
Bh='Bhalthazar:BAAANQADCgUICQABNQADCgYICAAQAAAAAA==.',
Bi='Bier:BAAANQAECgQIBgAAAA==.Bigrig:BAAANQAECgEIAQAAAA==.Bitterman:BAABNQAECn8oAAISAAkK7AepqwB7AQASAAkK7AepqwB7AQAAAA==.',
Bl='Blastin:BAAANQADCggIGAAAAA==.Bloodveil:BAAANQAECgUICgABNQAECgoKHQANAHEcAA==.Bluemonster:BAAANQADCgQIBAAAAA==.',
Bo='Boohoo:BAAANQADCgMIAwAAAA==.Bovinedivine:BAAANQADCgUIBQABNQAECgcIKQAQAAAAAA==.',
Br='Brandumb:BAAANQAECgYICgAAAA==.',
Ca='Callana:BAAANQAECgQICAAAAA==.Camedra:BAABNQAECn8pAAITAAkKciNzCQAuAwATAAkKciNzCQAuAwAAAA==.Carelessheal:BAAANQAECggICAAAAA==.Carthella:BAAANQADCgQJBAABNQAECgoKNgAUAFESAA==.Catamynyia:BAABNQAECn8ZAAIVAAcKgwx1pwC2AQAVAAcKgwx1pwC2AQAAAA==.',
Cc='Cchaos:BAAANQAECgMJAwAAAA==.',
Ce='Celaborn:BAABNQAECn8mAAMWAAgKUhqsSwCiAQAWAAgKdxesSwCiAQAXAAQKmRznMwAzAAAAAA==.Celice:BAAANQABCgcIBwABNQAECgkJNgAYAJwfAA==.',
Ch='Chimaira:BAAANQADCgQIBAAAAA==.Chucknoris:BAAANQADCgcJEQAAAA==.Chump:BAAANQADCgEIAQAAAA==.',
Cl='Claytonbigse:BAAANQABCgIIAgAAAA==.',
Co='Colossus:BAAANQAECgEIAQABNQAECgYICQAQAAAAAA==.Colossuss:BAAANQAECgYICQAAAA==.Commodious:BAAANQADCgMIAwAAAA==.Conduction:BAAANQADCgcICwAAAA==.',
Cr='Crankadin:BAAANQAECggIAQABNQADCggIEQAQAAAAAA==.Crispyquinn:BAAANQADCgUIBQAAAA==.Crispysham:BAABNQAECn8cAAILAAkKhg/ZZwDpAQALAAkKhg/ZZwDpAQAAAA==.Cruciö:BAAANQADCggIDAAAAA==.Crànk:BAAANQADCggIEQAAAA==.Cránk:BAAANQAECggJCAABNQADCggIEQAQAAAAAA==.Crãnk:BAAANQAECggIDwABNQADCggIEQAQAAAAAA==.',
Cu='Cullyeskie:BAABNQAECn8aAAIVAAYKbQNw0gCOAAAVAAYKbQNw0gCOAAAAAA==.Curveball:BAAANQAECgMIAwABNQAECgkJKAASAOwHAA==.',
Cy='Cyniar:BAABNQAECn8nAAIHAAkKmgucJQBXAQAHAAkKmgucJQBXAQAAAA==.',
Da='Dabrick:BAAANQADCgEIAQAAAA==.Dahnu:BAAANQADCgIIAgABNQAECgYIGgAJADERAA==.Damerlin:BAAANQADCgIIAgAAAA==.Darkhuntress:BAAANQADCgYIBgAAAA==.Darkstär:BAABNQAECn84AAMMAAkKJhoXKQB5AgAMAAkKJhoXKQB5AgADAAEKIQoLigA1AAAAAA==.Darkun:BAAANQADCggICAABNQAECgoKNAAUAGYPAA==.',
De='Deacon:BAABNQAECn8oAAIZAAgKyQafDQDmAAAZAAgKyQafDQDmAAAAAA==.Deadzly:BAABNQAECn83AAQMAAkKoSNsEAApAwAMAAgKsiNsEAApAwADAAgKZhY6PADdAQAEAAgKYhC6VQC7AQAAAA==.Deathknights:BAAANQADCgMIAwAAAA==.Deeanne:BAAANQAECgUIBwAAAA==.Deepfriar:BAABNQAECn84AAIJAAkKBCYXDwBNAwAJAAkKBCYXDwBNAwAAAA==.Deltoro:BAAANQADCgIIAgAAAA==.Demoniiks:BAAANQABCgcICQAAAA==.Derailed:BAABNQAECn8cAAIDAAkKnwvbNQBFAQADAAkKnwvbNQBFAQAAAA==.Deshal:BAAANQAECgQIBAAAAA==.Dethwing:BAAANQADCgQICAAAAA==.Dewsbelle:BAAANQAECgUICwAAAA==.',
Dh='Dha:BAAANQADCgcIBwABNQAECgcIHQAaAGYfAA==.',
Di='Diablognomis:BAAANQADCgcIDwAAAA==.Dirtman:BAABNQAECn8uAAILAAoKtRZnHQAQAgALAAoKtRZnHQAQAgAAAA==.Distillate:BAAANQADCgYIHAAAAA==.',
Dk='Dkrise:BAAANQADCgIIAgABNQAECgoKNAAUAGYPAA==.',
Do='Dolphina:BAAANQAECgEIAQAAAA==.Donny:BAAANQAECgUICAAAAA==.',
Dr='Dragonic:BAACNQAFFH8TAAMbAAYKoBreBACpAQAbAAYKoBreBACpAQAUAAIKxwN2DQBwAAA1AAQKfy8AAxsACgozHJQEANICABsACgozHJQEANICABQAAgp3DigzAHYAAAAA.Dreathlu:BAAANQADCgUIBgAAAA==.Drewdog:BAABNQAECn8cAAIVAAcKIA/fuACSAQAVAAcKIA/fuACSAQAAAA==.',
Du='Dubes:BAABNQAECn83AAIGAAkKIBv7BgCIAgAGAAkKIBv7BgCIAgAAAA==.Dunbartian:BAABNQAECn8pAAIaAAkKWhRFCQC2AQAaAAkKWhRFCQC2AQAAAA==.Duration:BAAANQABCgUIBwAAAA==.',
Ea='Easybreezin:BAAANQAECgYIBgAAAA==.',
Ei='Eirote:BAABNQAECn83AAIcAAkKBRC3AgAGAgAcAAkKBRC3AgAGAgAAAA==.',
El='Elarris:BAAANQAECgQIBAAAAA==.Eldari:BAAANQAECgUIDwAAAA==.Eledron:BAAANQAECgQIBAAAAA==.Elyssaena:BAAANQAECgYICAAAAA==.',
Em='Emotionaldmg:BAAANQAECgUIBQABNQAECggIDAAQAAAAAA==.',
En='Enzojr:BAAANQAECgMIBAAAAA==.',
Er='Eriath:BAABNQAECn9EAAIIAAoKmBxwDgAJAwAIAAoKmBxwDgAJAwAAAA==.',
Ev='Evè:BAAANQABCgEIAQAAAA==.',
Ex='Exalted:BAAANQAECgQICgABNQAFFAYIEwAbAKAaAA==.',
Ey='Eye:BAABNQAECn8bAAMLAAoKphbgNACkAgALAAkKUxjgNACkAgARAAEKDQiaywAxAAAAAA==.',
Fa='Faranth:BAABNQAECn83AAMUAAkKDBdYCACEAQAUAAkKDBdYCACEAQAdAAIKLwrOIABRAAAAAA==.',
Fe='Feld:BAAANQAECgcICwAAAA==.Felynne:BAAANQAECggIAwAAAA==.Feo:BAABNQAECn8cAAIOAAcKNx10HgBdAgAOAAcKNx10HgBdAgAAAA==.Feru:BAAANQAECgUIBQAAAA==.Ferum:BAABNQAECn85AAITAAoKVyW4AQDJAwATAAoKVyW4AQDJAwAAAA==.',
Fi='Fionnan:BAABNQAECn8wAAIeAAkKghJHFwBWAQAeAAkKghJHFwBWAQABNQAECgkJNwARAPgMAA==.Fizwidget:BAAANQADCgEIAQAAAA==.',
Fr='Freezia:BAAANQAECgYICgAAAA==.Frostigan:BAAANQAECgcIDAABNQAECgkJHAAfAPYOAA==.Fryeguy:BAAANQADCgQIBAAAAA==.',
Fu='Fudo:BAAANQAECgEIAQAAAA==.Fudoswrath:BAAANQAECgYICwAAAA==.Funkysoup:BAAANQAECgUICwAAAA==.',
['Fò']='Fòrced:BAAANQADCgYIEAAAAA==.',
Ga='Gallium:BAAANQAECgIJAgAAAA==.',
Ge='Gehena:BAAANQAECgQIBAABNQAECgkJMwAVAEAjAQ==.Gemsareyum:BAAANQADCgIIAgABNQAFFAYIIgAVAGMhAA==.',
Gi='Girthquake:BAABNQAECn8XAAILAAcK5QyfpwBFAQALAAcK5QyfpwBFAQAAAA==.',
Gl='Glow:BAAANQADCggJCAAAAA==.',
Go='Goof:BAABNQAECn8pAAIfAAoK6gX1gwCPAQAfAAoK6gX1gwCPAQAAAA==.Goontaa:BAAANQAECgQIAQAAAA==.',
Gr='Griz:BAAANQAECggICwAAAA==.Grossevache:BAAANQADCgIIBAAAAA==.',
Ha='Haddor:BAABNQAECn8dAAIgAAgKHxGfGQAyAQAgAAgKHxGfGQAyAQAAAA==.Halfheart:BAAANQAECgUICwAAAA==.Hankerin:BAAANQAECgEIAQAAAA==.Harborhate:BAAANQAECgcIAgAAAA==.Harmoni:BAAANQAECgIIAwAAAA==.Harpomage:BAAANQADCggIEwAAAA==.Haunter:BAABNQAECn8hAAQEAAkKUCBnOABEAgAEAAkKUCBnOABEAgADAAcKaxd4QwC2AQAMAAUK7Q2+hADqAAAAAA==.',
He='Heimdallr:BAAANQADCggIEAAAAA==.Heisenborg:BAAANQAECgQIBAAAAA==.Helldin:BAAANQAECgEIAQAAAA==.',
Hi='Hidden:BAAANQADCgMIAwABNQAFFAYIEwAbAKAaAA==.Hilite:BAAANQAECgQICAAAAA==.Himothyjr:BAAANQADCgcICgAAAA==.',
Ho='Holific:BAABNQAECn81AAINAAkKMhMZkAAFAgANAAkKMhMZkAAFAgAAAA==.Holymommy:BAAANQAECgUICQABNQAECgoKHQANAHEcAA==.Hoss:BAAANQAECggIDQAAAA==.Hotrodranger:BAABNQAECn8zAAIVAAkKvB0JJQBPAgAVAAkKvB0JJQBPAgAAAA==.',
Hs='Hshyomouth:BAAANQADCgIIAgABNQAECgkJMwAVALwdAA==.',
Hu='Hunters:BAAANQADCgYIBgAAAA==.Hut:BAACNQAFFH8XAAIHAAcKRxRXCAD+AQAHAAcKRxRXCAD+AQA1AAQKf0cAAgcACgo4JUgBAG0DAAcACgo4JUgBAG0DAAAA.',
Hy='Hypearione:BAAANQABCgEIAQAAAA==.',
Ia='Iambohike:BAAANQAECgEIAgAAAA==.',
Ic='Icycritties:BAABNQAECn8iAAQGAAkKzw3fCQB0AQAGAAkKzw3fCQB0AQAFAAcKnwaJpgD6AAAcAAEKPQOIDwAiAAAAAA==.',
Ih='Iheals:BAAANQADCgIIAgAAAA==.',
Im='Imjustadruid:BAAANQADCgIIAgAAAA==.Immortal:BAABNQAECn8wAAIEAAkKEg8BHwB8AQAEAAkKEg8BHwB8AQAAAA==.',
In='Incarnated:BAABNQAECn8aAAMEAAoKiiBmDQBOAwAEAAkKoiFmDQBOAwADAAYKiRh+LgBuAQAAAA==.',
Ir='Irís:BAAANQAECggIDAAAAA==.',
Is='Iskra:BAAANQADCgIIAgAAAA==.Ispithotfire:BAAANQABCgQIBgAAAA==.',
Iu='Iu:BAAANQAECggIEQAAAA==.',
Ja='Jackfash:BAAANQADCgMIBQAAAA==.Jadecross:BAAANQADCgIIAgAAAA==.Javan:BAAANQADCgIIAgAAAA==.',
Je='Jerryatric:BAABNQAECn8iAAINAAcKDQ0SpAANAQANAAcKDQ0SpAANAQAAAA==.',
Ji='Jiri:BAAANQABCgcIDwAAAA==.',
Jk='Jkmno:BAAANQADCgMIAwABNQADCgUIBQAQAAAAAA==.',
Jo='Joeyrains:BAAANQADCgQIBAAAAA==.',
Ju='Justblaze:BAAANQAECgQIBAAAAA==.Justincasê:BAAANQABCgMIBQAAAA==.',
Ka='Kallikan:BAABNQAECn8lAAIeAAgKPBPwHgCnAQAeAAgKPBPwHgCnAQAAAA==.Kamidk:BAAANQAECgYIDwABNQAECggIEwAQAAAAAA==.Kamuri:BAAANQADCgUIBQAAAA==.Kasteen:BAAANQAECgEIAQAAAA==.Katia:BAAANQAECgUIEQAAAA==.Kaøs:BAAANQAECgEIAgAAAA==.',
Kd='Kdoggparker:BAAANQABCgYICQAAAA==.',
Ke='Kelvox:BAAANQAECgQIBAAAAA==.Kementari:BAABNQAECn8eAAIHAAcKCQYXRQCwAAAHAAcKCQYXRQCwAAAAAA==.Kenzaki:BAABNQAECn8qAAINAAgKiBVRkwD9AQANAAgKiBVRkwD9AQAAAA==.',
Kh='Khaladin:BAAANQADCgYICAAAAA==.Khaosreborn:BAAANQADCgUIAQAAAA==.Khaotic:BAAANQADCggICgAAAA==.',
Ki='Kilaaz:BAABNQAECn8eAAINAAoKACKPGwCnAgANAAoKACKPGwCnAgAAAA==.Kirveka:BAAANQABCgQIBAAAAA==.',
Kl='Kliticaldk:BAAANQAECgIIBAAAAA==.Kliticalwar:BAABNQAECn8bAAIWAAoK7A9ZjgD4AQAWAAoK7A9ZjgD4AQAAAA==.Klothys:BAABNQAECn8hAAINAAkKrRziXQB/AgANAAkKrRziXQB/AgAAAA==.',
Kn='Knuts:BAAANQADCgMJAwABNQAECgYIBgAQAAAAAA==.',
Ko='Koitsvo:BAAANQAECgMIAgAAAA==.Ková:BAAANQADCgUJCwAAAA==.',
Ku='Kuani:BAAANQAECgQIBAABNQAECgkJNgAYAJwfAA==.',
La='Landre:BAAANQADCgQIBgAAAA==.Lassy:BAAANQADCgIJAgAAAA==.Lathray:BAAANQAECgUIEwAAAA==.Lazerous:BAAANQADCggICgAAAA==.',
Le='Lealoo:BAABNQAECn8oAAINAAkKnRPGkQABAgANAAkKnRPGkQABAgABNQAECgoKKAAPANYPAA==.Leftfield:BAAANQAECgEIAQABNQAECgkJKAASAOwHAA==.Legolard:BAABNQAECn8dAAMaAAcKZh/nCgCTAQAaAAcKZh/nCgCTAQAWAAIKNwycMwFtAAAAAA==.Leleia:BAABNQAECn8WAAIIAAcKJwvPNQB1AQAIAAcKJwvPNQB1AQAAAA==.',
Lh='Lhera:BAABNQAECn8iAAMhAAgKsx9yDACpAgAhAAgKsx9yDACpAgARAAcKMRR/eACiAQABNQAECgoKMgAiAGEfAA==.',
Li='Liath:BAABNQAECn8aAAIJAAYKMRGUkQBhAQAJAAYKMRGUkQBhAQAAAA==.Lichtenberg:BAABNQAECn8zAAMLAAkK/B3KMQCzAgALAAkK/B3KMQCzAgARAAUKxwjL1AC9AAAAAA==.Linddori:BAAANQAECgYIDwABNQAECgkJJgACANcWAA==.Lirillia:BAABNQAECn8mAAQCAAkK1xY5CgBTAgACAAgKMxg5CgBTAgASAAcK6Aq20AAoAQAjAAEKAACoMAA0AAAAAA==.Lirillïa:BAAANQADCgYICwABNQAECgkJJgACANcWAA==.Lizzie:BAAANQADCgUIBQAAAA==.',
Lo='Locdon:BAAANQABCgIIAgABNQAECgUICAAQAAAAAA==.Lodestone:BAAANQADCggICgAAAA==.Loena:BAAANQAECggICwAAAA==.Lokk:BAAANQAECgIIAgABNQAECggIJAAVAOIaAA==.Loko:BAAANQAECgEIAQAAAA==.Lolowbeatz:BAAANQADCgUIBgAAAA==.Lovelydread:BAAANQAECgEIAQAAAA==.',
Lu='Lunabug:BAAANQAECgIIAgAAAA==.Lupinos:BAAANQADCgIIAQAAAA==.',
Ly='Lyadra:BAABNQAECn8oAAIJAAkKIh4BJQBBAgAJAAkKIh4BJQBBAgAAAA==.Lyrissa:BAAANQADCgYIBgAAAA==.',
['Lõ']='Lõst:BAAANQAECgIIAwAAAA==.',
Ma='Mackito:BAABNQAFFH8OAAIVAAgKHgFVHQBlAAAVAAgKHgFVHQBlAAAAAA==.Madan:BAABNQAECn8UAAIEAAYKuAZcQwCrAAAEAAYKuAZcQwCrAAAAAA==.Mahoushojou:BAAANQAECgIIAgABNQAECgkJHAAfAPYOAA==.Malasminna:BAAANQAECgYIEgAAAA==.Malehorelock:BAAANQAECgEIAQAAAA==.Malicioun:BAAANQABCggIDgAAAA==.Malkariss:BAABNQAECn8eAAMGAAgK4xrYGwARAQAFAAYKNhv7zQDqAQAGAAQKORnYGwARAQAAAA==.Mammadruid:BAABNQAECn8hAAIeAAcKOgtLJgDbAAAeAAcKOgtLJgDbAAAAAA==.Mauldis:BAABNQAECn8fAAMLAAgKMAX6pQBIAQALAAgKMAX6pQBIAQARAAUKtQI07QCRAAAAAA==.',
Me='Meryl:BAABNQAECn8wAAIfAAkKYxi2PAByAgAfAAkKYxi2PAByAgAAAA==.',
Mi='Miaka:BAABNQAECn8yAAIjAAkKRhqgAwC4AgAjAAkKRhqgAwC4AgAAAA==.Minth:BAAANQADCgcIDQABNQAECgkJHAAfAPYOAA==.Miraakle:BAAANQAECgQIBwABNQAECgkJHAAfAPYOAA==.Misfire:BAABNQAECn8wAAIVAAkKBhEtVQCdAQAVAAkKBhEtVQCdAQAAAA==.Mithra:BAAANQAECgQICQAAAA==.',
Mo='Moghroth:BAABNQAECn8zAAMHAAkKEwt+JQBYAQAHAAkKEwt+JQBYAQAeAAEK1wQOZQAqAAAAAA==.Molykote:BAAANQAECggIDAAAAA==.Monks:BAAANQADCgQIBAAAAA==.Monsterbabe:BAAANQADCgUICgAAAA==.Moreleath:BAAANQADCgMIBAAAAA==.Morphias:BAAANQADCgQIBAAAAA==.Mowiewowie:BAAANQABCgIIAgAAAA==.',
Mu='Mugzypatron:BAAANQADCggIIwAAAA==.Murdrmitts:BAABNQAECn8bAAIeAAcKmwsrKgBGAQAeAAcKmwsrKgBGAQAAAA==.',
['Mã']='Mãtador:BAACNQAFFH8GAAILAAQK5BbnEABdAQALAAQK5BbnEABdAQA1AAQKfycAAwsACQrLIBAgAAsDAAsACQrLIBAgAAsDABEAAwo3EJv6AHUAAAAA.',
['Mä']='Mätadør:BAABNQAECn8UAAIIAAgKFxs2IgAjAgAIAAgKFxs2IgAjAgABNQAFFAQIBgALAOQWAA==.',
Na='Nahryn:BAABNQAECn8fAAITAAgKzhwZFwCJAgATAAgKzhwZFwCJAgAAAA==.',
Ne='Nedina:BAAANQADCgUIBQAAAA==.Nerbert:BAAANQADCgYJBgABNQAECgoKNgAUAFESAA==.Neretsym:BAABNQAECn8vAAIVAAkK5Q55TgCxAQAVAAkK5Q55TgCxAQAAAA==.',
Ni='Nineva:BAABNQAECn8aAAITAAcKMQYyRQAFAQATAAcKMQYyRQAFAQAAAA==.',
No='Nobas:BAABNQAECn83AAIHAAkK1gkeLgAfAQAHAAkK1gkeLgAfAQAAAA==.Nonoa:BAAANQAECgEIAgAAAA==.',
Oc='Octavien:BAAANQADCgIIAgAAAA==.',
Og='Ogr:BAAANQADCgMIAwAAAA==.',
On='Onlyfeet:BAABNQAECn8dAAINAAoKcRwrJAB2AgANAAoKcRwrJAB2AgAAAA==.',
Op='Oppgjør:BAAANQAECgEIAQAAAA==.',
Or='Oreeree:BAAANQAECgQICgAAAA==.Ormr:BAABNQAECn82AAMUAAoKURIiBwCwAQAUAAoKURIiBwCwAQAdAAEKAABPIwA5AAAAAA==.',
Os='Osteo:BAABNQAECn8mAAMCAAcKTwajJwA7AQASAAcK+QXMxQA/AQACAAcK2wSjJwA7AQAAAA==.Osteoprime:BAAANQADCgUJBQAAAA==.',
Ou='Ouron:BAABNQAECn8oAAMRAAoK3hXmPQBoAgARAAoK3hXmPQBoAgALAAEKAACf4QAAAAAAAA==.Outofmana:BAAANQAECgQIDQAAAA==.',
Ov='Ovelia:BAAANQAECgUIBAAAAA==.',
Pa='Pagoda:BAAANQADCgYJBgAAAA==.Papashrimps:BAACNQAFFH8QAAMFAAUKKxQXGgDdAAAFAAQKKxQXGgDdAAAGAAEKAAB0EAAAAAA1AAQKfyYAAwUACgqHGISWAFMCAAUACgqXF4SWAFMCAAYAAQoxGmQ/AEYAAAAA.',
Pe='Percy:BAAANQADCggIGQAAAA==.',
Ph='Phatcow:BAAANQADCgEIAQAAAA==.',
Pl='Placeholder:BAABNQAECn8zAAIgAAkK3CAOBwBxAgAgAAkK3CAOBwBxAgAAAA==.',
Po='Pojoevokest:BAABNQAECn8aAAIbAAgKhAlzKwBPAQAbAAgKhAlzKwBPAQAAAA==.Pontifex:BAABNQAECn8rAAIJAAkK1RY4PwC4AQAJAAkK1RY4PwC4AQAAAA==.Portandmorph:BAABNQAECn8dAAIGAAkKhxGWCwAHAgAGAAkKhxGWCwAHAgAAAA==.Powerbottm:BAAANQAECgYIDwAAAA==.',
Pr='Priests:BAAANQADCgQIBgAAAA==.Prone:BAABNQAECn83AAMRAAkK+AwTjwBjAQARAAgK7wkTjwBjAQALAAQKFwSzqQBTAAAAAA==.Protarada:BAAANQAECgEIAQAAAA==.',
Qu='Quietmind:BAAANQAECggIEAAAAA==.',
Ra='Raakotah:BAABNQAECn80AAIHAAoK1iL4DQBbAwAHAAoK1iL4DQBbAwAAAA==.Raasclaat:BAAANQADCgcIDQAAAA==.Raelo:BAABNQAECn8yAAIhAAkKJA3sDQCxAQAhAAkKJA3sDQCxAQAAAA==.Rainbowflake:BAABNQAECn8VAAIVAAcK3wIbAgEBAQAVAAcK3wIbAgEBAQAAAA==.Raiseurmug:BAABNQAECn8qAAIZAAkK9xHTEADcAQAZAAkK9xHTEADcAQAAAA==.Rakash:BAAANQADCgcIBwAAAA==.Rarg:BAABNQAECn8VAAMMAAgKlRnWSgDMAQAMAAgKlRnWSgDMAQAEAAEK6QLn8gAkAAAAAA==.Ravia:BAAANQAFFAEIAQAAAA==.',
Re='Rendysavage:BAAANQAECgYJBgAAAA==.Resco:BAAANQADCggIEgAAAA==.',
Ri='Riddle:BAABNQAECn8lAAIRAAoKZQonXwAhAQARAAoKZQonXwAhAQAAAA==.Rimeouo:BAAANQAECgUICQAAAA==.Rize:BAABNQAECn8aAAIWAAgK/w++mgDaAQAWAAgK/w++mgDaAQABNQAECgoKNAAUAGYPAA==.Rizmthetizm:BAAANQADCgEIAQAAAA==.',
Ro='Rosenrott:BAABNQAECn8zAAIVAAkKQCMhFQCqAgAVAAkKQCMhFQCqAgAAAA==.Rosepiercer:BAABNQAECn8kAAIVAAoKzyAHCgAEAwAVAAoKzyAHCgAEAwAAAA==.Rouz:BAABNQAECn8bAAIUAAcKhglmDgDwAAAUAAcKhglmDgDwAAAAAA==.',
Ru='Ruddybear:BAAANQADCgIJAgAAAA==.',
Ry='Ryoto:BAAANQAECgUICAAAAA==.',
Sa='Sadarasdeath:BAAANQADCgUICQAAAA==.Samandean:BAABNQAECn8oAAIPAAoK1g+rFwDpAQAPAAoK1g+rFwDpAQAAAA==.Sarasvati:BAAANQAECgMIAwAAAA==.Sariia:BAAANQAECgUIBQABNQAECgoKQAAOAJAeAA==.',
Se='Sellena:BAABNQAECn8bAAIhAAkKvw+nDQC2AQAhAAkKvw+nDQC2AQABNQAECgoKKAAPANYPAA==.',
Sh='Shakenn:BAAANQADCgEIAQAAAA==.Shandow:BAABNQAECn9EAAIGAAoKrCPOAAAlAwAGAAoKrCPOAAAlAwAAAA==.Shansoracle:BAABNQAECn8kAAMJAAoKIx7WCgAyAwAJAAoKIx7WCgAyAwAIAAEKaAP7ggAmAAABNQAECgoKRAAGAKwjAA==.Shed:BAAANQAECgQIBAABNQAFFAcIFwAHAEcUAA==.Sheislegend:BAAANQADCggIFgAAAA==.Shelby:BAABNQAECn8jAAIJAAkKNRyEQQBlAgAJAAkKNRyEQQBlAgAAAA==.Shocked:BAAANQAECggIAwABNQAECggIDAAQAAAAAA==.Shockolate:BAAANQAECgQIBQAAAA==.',
Si='Siarn:BAAANQADCgMIBQAAAA==.Siccinok:BAABNQAECn8zAAMFAAgKhh1QRQDjAQAFAAgKhh1QRQDjAQAGAAQKwx2kIADkAAAAAA==.Sixhundrdlbs:BAACNQAFFH8OAAIOAAQKUh01BAABAQAOAAQKUh01BAABAQA1AAQKfzsAAw4ACgqyI7ADAJ0DAA4ACgqyI7ADAJ0DAA8AAQqYCjZqADMAAAE1AAQKCgoaAAQAiiAA.',
Sk='Skraps:BAAANQADCgEJAQAAAA==.',
Sl='Slimped:BAAANQADCgYICwAAAA==.',
Sn='Sneakybato:BAAANQADCggIFwAAAA==.',
So='Sofie:BAAANQADCgQIBAABNQAECgkJMwALAPwdAA==.Solarial:BAAANQAECgUIEQAAAA==.Solastra:BAABNQAECn8oAAIfAAgK0RUkMQDfAQAfAAgK0RUkMQDfAQAAAA==.Soramai:BAAANQAECgQIBQAAAA==.Soth:BAABNQAECn83AAMEAAkK5xSaIgBfAQAMAAgKxhFyVgCaAQAEAAkK5xSaIgBfAQAAAA==.',
Sp='Sparký:BAABNQAECn8kAAISAAoKeiRuAgBPAwASAAoKeiRuAgBPAwAAAA==.Spinnycrisp:BAAANQADCgYIBgAAAA==.',
St='Starlyvana:BAACNQAFFH8OAAMGAAQKLw7gAwDbAAAGAAMKLw7gAwDbAAAFAAIKlwdAPQAAAAA1AAQKfxgAAgYACgprFssHAG8CAAYACgprFssHAG8CAAAA.Staryxia:BAABNQAECn8XAAIDAAkKSh1KNgD/AQADAAkKSh1KNgD/AQAAAA==.Statiic:BAAANQABCgIIBQAAAA==.Steamdruid:BAAANQADCggIDwABNQAECgoKMAAPAM4UAA==.Steephany:BAAANQADCgMIBwAAAA==.Stonecross:BAABNQAECn8lAAIJAAkKDxtmJgA3AgAJAAkKDxtmJgA3AgAAAA==.Stormbolt:BAABNQAECn8pAAIHAAkKdgtYTgCmAQAHAAkKdgtYTgCmAQAAAA==.Stormspirit:BAAANQADCggIHQAAAA==.Striggen:BAAANQAECgUIEQAAAA==.',
Su='Sugarsham:BAABNQAECn8gAAILAAkKlAvJcgDIAQALAAkKlAvJcgDIAQAAAA==.Sulwen:BAACNQAFFH8YAAIHAAgK0SRnAQDwAgAHAAgK0SRnAQDwAgA1AAQKfzAAAgcACgrOJt4AAHoDAAcACgrOJt4AAHoDAAAA.Sumerset:BAABNQAECn8VAAINAAkK0AzUcgBuAQANAAkK0AzUcgBuAQAAAA==.Sundave:BAAANQAECgEJAgAAAA==.Supaflytnt:BAABNQAECn8pAAIkAAgKehUVCADRAQAkAAgKehUVCADRAQAAAA==.Sustia:BAAANQAECgUICwAAAA==.',
Ta='Taera:BAABNQAECn82AAIYAAkKnB9OBAAAAwAYAAkKnB9OBAAAAwAAAA==.Talavenn:BAABNQAECn8kAAIOAAkK0B2uEQDgAgAOAAkK0B2uEQDgAgAAAA==.Tanglock:BAAANQAECgUICQAAAA==.Tarage:BAAANQAECgUIDAAAAA==.Taurîel:BAAANQADCgYIBgAAAA==.',
Te='Tectoniiks:BAAANQAECgcIBwAAAA==.Tedds:BAAANQAECgUJCAAAAA==.Teds:BAAANQADCgYICwAAAA==.Tempus:BAAANQAECgMJAwAAAA==.Teriko:BAABNQAECn8qAAIDAAgKFRsVLQA3AgADAAgKFRsVLQA3AgAAAA==.Teviro:BAAANQADCgIIAgABNQAECgoKMgAiAGEfAA==.',
Th='Thequixote:BAABNQAECn8ZAAIkAAYKehVSEAAnAQAkAAYKehVSEAAnAQAAAA==.',
Ti='Tictok:BAAANQADCgYICgAAAA==.Tinytotems:BAAANQADCgQIBAAAAA==.',
To='Toaderic:BAAANQAECgUIDwAAAA==.Tots:BAABNQAECn87AAIeAAoKhBzSBgCAAgAeAAoKhBzSBgCAAgAAAA==.Toxictotes:BAAANQADCgYICQAAAA==.',
Tr='Trazah:BAAANQADCgEIAQAAAA==.',
Ty='Tyraèl:BAABNQAECn8lAAIfAAoKGyMBCACJAwAfAAoKGyMBCACJAwAAAA==.Tyzy:BAACNQAFFH8QAAMHAAQK8CPBBgAzAQAHAAQK8CPBBgAzAQATAAIK+COeCADOAAA1AAQKfykAAwcACgrMI/YNAFsDAAcACgrMI/YNAFsDABMACQowHZkXAIQCAAAA.',
Um='Umber:BAAANQADCggICAAAAA==.',
Va='Valenora:BAABNQAECn8nAAICAAkKtBcDBgCwAgACAAkKtBcDBgCwAgAAAA==.Valvitor:BAAANQADCgEIAQAAAA==.Varuz:BAABNQAECn8kAAIVAAgK4hpIQACqAgAVAAgK4hpIQACqAgAAAA==.Varyz:BAAANQADCgIIAgABNQAECggIJAAVAOIaAA==.',
Ve='Velanie:BAAANQAECgEIAQAAAA==.Veloon:BAABNQAECn8bAAIHAAkKIg7hQgDqAQAHAAkKIg7hQgDqAQAAAA==.Veloras:BAAANQAECgEIAgAAAA==.Verinari:BAAANQAECgQICQAAAA==.',
Vi='Vipul:BAAANQADCgUIDQABNQADCgYIBwAQAAAAAA==.Viridria:BAABNQAECn8cAAMfAAkK9g5wOwCsAQAfAAkK9g5wOwCsAQANAAIKZwlyUwEoAAAAAA==.Vityazi:BAABNQAECn8XAAINAAcKlAO6KAHcAAANAAcKlAO6KAHcAAAAAA==.',
Vo='Voodoobootie:BAAANQABCgcJBwAAAA==.',
Vy='Vy:BAAANQADCgUICQAAAA==.',
['Vè']='Vè:BAABNQAECn8oAAIeAAkKqxAbGgDWAQAeAAkKqxAbGgDWAQAAAA==.',
Wa='Warriors:BAABNQAECn9EAAIWAAoKaiLkDQD3AgAWAAoKaiLkDQD3AgAAAA==.Wartooth:BAABNQAECn8oAAMCAAgKNBUvKQAxAQASAAgKlg2WWwBRAQACAAQKiBgvKQAxAQAAAA==.Wassergott:BAAANQAECgEIAQAAAA==.',
We='Webicus:BAABNQAECn8cAAQWAAgKJgn5xwBoAQAWAAcKFQr5xwBoAQAXAAMKfQb4HABVAAAaAAEKeARGNQAnAAAAAA==.Wendee:BAABNQAECn8nAAMJAAkKcgS/XwA5AQAJAAkKcgS/XwA5AQAIAAEKAABKlAATAAAAAA==.',
Wh='Whitefóx:BAAANQAECgcIBwABNQAECgoKRAAGAKwjAA==.Whitley:BAABNQAECn8wAAMRAAkKiSHmLQCqAgARAAkKiSHmLQCqAgALAAcKfRThbgDTAQAAAA==.',
Wi='Wildspart:BAAANQAECgYIDgAAAA==.',
Wo='Wooden:BAABNQAECn8lAAIVAAgKzBpnTgCyAQAVAAgKzBpnTgCyAQAAAA==.',
Xa='Xaphy:BAABNQAECn8gAAMJAAkKOxyHGwCDAgAJAAkKOxyHGwCDAgAIAAkKqQxpFgBqAQAAAA==.Xardots:BAABNQAECn8aAAICAAcKthN8EgDhAQACAAcKthN8EgDhAQABNQAECgcIKQAQAAAAAA==.',
Xi='Xiareth:BAABNQAECn8jAAIbAAcKPhHUEQBNAQAbAAcKPhHUEQBNAQAAAA==.',
Xy='Xyleiah:BAAANQADCgYIBgABNQAECgkJNwAUAAwXAA==.',
['Xá']='Xároth:BAAANQAECgcIKQAAAQ==.',
Ya='Yaddi:BAAANQAECgIIAQAAAA==.Yargue:BAABNQAECn8iAAIIAAoKnBVwDAAbAgAIAAoKnBVwDAAbAgAAAA==.',
Ye='Yeeyee:BAAANQAECggIDAAAAA==.',
Yi='Yirï:BAAANQABCgQIBgAAAA==.',
Yo='Youngjeezy:BAAANQAECgQIDgAAAA==.Yoursinpride:BAAANQAECggIDgAAAA==.',
Za='Zackor:BAAANQADCgUIDAAAAA==.',
Ze='Ze:BAAANQADCgYICgAAAA==.Zervann:BAAANQADCgYIBgAAAA==.',
Zi='Ziska:BAAANQADCgIIAgAAAA==.',
Zo='Zorithic:BAAANQAECgIJAwAAAA==.',
Zu='Zuldan:BAAANQADCgIIAgAAAA==.',
Zy='Zyde:BAAANQAECgIIAQABNQAECggIJAAVAOIaAA==.',
['Zæ']='Zælys:BAAANQAECgEIAQAAAA==.',
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
