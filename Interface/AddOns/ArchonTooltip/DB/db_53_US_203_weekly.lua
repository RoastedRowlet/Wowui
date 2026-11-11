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

local lookup = {'Rogue-Outlaw','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Unholy','Mage-Arcane','Mage-Frost','Druid-Balance','Priest-Shadow','Priest-Holy','Priest-Discipline','Shaman-Elemental','DeathKnight-Blood','Paladin-Retribution','Warlock-Demonology','DemonHunter-Devourer','DemonHunter-Havoc','Unknown-Unknown','Shaman-Restoration','Druid-Feral','Druid-Restoration','Evoker-Devastation','Hunter-BeastMastery','Warrior-Fury','Warrior-Arms','Monk-Mistweaver','Rogue-Subtlety','Rogue-Assassination','Monk-Brewmaster','Warrior-Protection','Evoker-Preservation','Mage-Fire','Evoker-Augmentation','Druid-Guardian','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Warlock-Affliction','Hunter-Survival',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aanuanaela:BAABNQAECn8rAAIBAAoKxhG7AgDdAQABAAoKxhG7AgDdAQAAAA==.Aanubis:BAAANQAECgQIBwAAAA==.',
Ab='Absens:BAABNQAECn89AAICAAoKORBiBQCMAQACAAoKORBiBQCMAQAAAA==.Abumim:BAAANQAECgUICAAAAA==.',
Ad='Adorian:BAAANQAECgQIBAABNQAECgoKNwADAIkhAA==.Adwillon:BAAANQAECgQIAwAAAA==.',
Af='Aforceofone:BAAANQAECgcIDAAAAA==.',
Ag='Aggretsuko:BAABNQAECn8uAAMEAAoKjxa0QAAaAgAEAAgKGhm0QAAaAgADAAkKHAvOTgB5AQAAAA==.',
Al='Aldonza:BAAANQADCgIIAgAAAA==.Alex:BAAANQAECgUIDgAAAA==.Alivanllan:BAAANQAECgQIBQAAAA==.Aluviel:BAACNQAFFH8KAAMFAAMKdhx9LgAdAQAFAAMKdhx9LgAdAQAGAAEKAQwdEwBIAAA1AAQKfxwAAwUACQo3JYsiAFIDAAUACQo3JYsiAFIDAAYAAQoNIVAwAFwAAAE1AAUUCAgYAAcA0SQA.Alyslia:BAAANQABCggIGQAAAA==.',
An='Anamuht:BAABNQAECn82AAQIAAoK+BWZLgCwAQAIAAgKDxOZLgCwAQAJAAkK7g7rawCBAQAKAAMKEgcpHQB6AAABNQAECgoKQgALAHMgAA==.Angeli:BAAANQAECgEIAQAAAA==.Annaday:BAABNQAECn8gAAIMAAkKpxC1NABnAQAMAAkKpxC1NABnAQAAAA==.Antiock:BAABNQAECn83AAQDAAoKiSE8EQAFAwADAAoKrx08EQAFAwAMAAcKzyLrLwBSAgAEAAcKnxksQwAOAgAAAA==.Anyamonka:BAAANQAECgcIEgAAAA==.',
Ap='Appalachia:BAAANQADCgYJBgAAAA==.',
Ar='Ariea:BAAANQADCgEIAQAAAA==.Arraven:BAAANQADCggIBwAAAA==.Arrowmir:BAAANQABCgYJCAAAAA==.Artto:BAAANQADCgIIAgAAAA==.',
As='Ashbrínger:BAABNQAECn9EAAINAAoKsSPDGABhAwANAAoKsSPDGABhAwAAAA==.Association:BAAANQAECgEIAQABNQAECgoKLQAOAA8JAA==.',
At='Atua:BAAANQAECgEIAgAAAA==.',
Av='Averax:BAABNQAECn84AAMPAAkKbCFrDwD5AgAPAAkKbCFrDwD5AgAQAAEKAAB3jQBBAAAAAA==.Avylbrew:BAAANQADCgcICgABNQAECgIIAgARAAAAAA==.',
Ay='Aylakaye:BAAANQADCggICQAAAA==.',
Az='Azzathoth:BAAANQADCggICAAAAA==.',
Ba='Babybilly:BAABNQAECn8mAAMLAAoKoh4YJQBAAgALAAkKzR4YJQBAAgASAAYKWR6dTQDEAQAAAA==.Babyshoes:BAAANQAECgQIBwAAAA==.Backpack:BAAANQAECgcIDAAAAA==.Bananawaffle:BAAANQADCgEIAQAAAA==.Bandan:BAABNQAECn8XAAIIAAkKwRrJHQCJAQAIAAkKwRrJHQCJAQAAAA==.Bato:BAAANQADCgUIDAAAAA==.',
Be='Beauvito:BAAANQADCgEIAQAAAA==.Beefjurkey:BAAANQAECgQICQAAAA==.Betch:BAAANQAECggIBQABNQAECggIDAARAAAAAA==.',
Bh='Bhalthazar:BAAANQADCgUICQABNQADCgYICAARAAAAAA==.',
Bi='Bier:BAAANQAECgQIBgAAAA==.Bigrig:BAAANQAECgEIAQAAAA==.Bitterman:BAABNQAECn8tAAIOAAoKDwmpqwB7AQAOAAoKDwmpqwB7AQAAAA==.',
Bl='Blastin:BAAANQADCggIGAAAAA==.Bloodveil:BAABNQAECn8VAAITAAcK9RpjFQBYAQATAAcK9RpjFQBYAQABNQAECgoKJAANAIgcAA==.Bluemonster:BAAANQADCgQIBAAAAA==.',
Bo='Boohoo:BAAANQADCgMIAwAAAA==.Bovinedivine:BAAANQADCgUIBQABNQAECggINgARAAAAAA==.',
Br='Brandumb:BAAANQAECgYICgAAAA==.',
Ca='Callana:BAAANQAECgQICAAAAA==.Camedra:BAABNQAECn84AAIUAAoKTSRVBACjAwAUAAoKTSRVBACjAwAAAA==.Carelessheal:BAAANQAECggICAAAAA==.Carthella:BAAANQADCgQJBAABNQAECgoKNgAVAFESAA==.Catamynyia:BAABNQAECn8bAAIWAAgKxgx1pwC2AQAWAAgKxgx1pwC2AQAAAA==.',
Cc='Cchaos:BAAANQAECgMJAwAAAA==.',
Ce='Celaborn:BAABNQAECn8sAAMXAAkKdhoFDQCbAQAYAAkKTRZOXQDTAQAXAAYK9hwFDQCbAQAAAA==.Celice:BAAANQABCgcIBwABNQAECgoKPwAZAL8eAA==.',
Ch='Chimaira:BAAANQADCgQIBAAAAA==.Chucknoris:BAAANQADCgcJEQAAAA==.Chump:BAAANQADCgEIAQAAAA==.',
Cl='Claytonbigse:BAAANQABCgIIAgAAAA==.',
Co='Colossus:BAAANQAECgYIDAABNQAECgkJFwAEAGgVAA==.Colossuss:BAABNQAECn8XAAIEAAkKaBVMHQDlAQAEAAkKaBVMHQDlAQAAAA==.Commodious:BAAANQADCgcICgAAAA==.Conduction:BAAANQAECgQIBAAAAA==.',
Cr='Crankadin:BAAANQAECggIAQABNQADCggIEQARAAAAAA==.Crispyquinn:BAAANQADCgUIBQAAAA==.Crispysham:BAABNQAECn8cAAILAAkKhg/ZZwDpAQALAAkKhg/ZZwDpAQAAAA==.Cruciö:BAAANQADCggIDAAAAA==.Crànk:BAAANQADCggIEQAAAA==.Cránk:BAAANQAECggJCAABNQADCggIEQARAAAAAA==.Crãnk:BAABNQAECn8bAAMaAAkKgw16fwAHAQAbAAUKzAriZwATAQAaAAkKqwp6fwAHAQABNQADCggIEQARAAAAAA==.',
Cu='Cullyeskie:BAABNQAECn8cAAIWAAgK/AJs+wChAAAWAAgK/AJs+wChAAAAAA==.Curveball:BAAANQAECgMIAwABNQAECgoKLQAOAA8JAA==.',
Cy='Cyniar:BAABNQAECn8xAAIHAAoKvAzSKQCbAQAHAAoKvAzSKQCbAQAAAA==.',
Da='Dabrick:BAAANQADCgEIAQAAAA==.Dahnu:BAAANQADCgIIAgABNQAECgcIIwAJALcVAA==.Damerlin:BAAANQADCgIIAgAAAA==.Darios:BAAANQADCgUIBgABNQAECggIDwARAAAAAA==.Darkhuntress:BAAANQADCgYIBgAAAA==.Darkstär:BAABNQAECn9HAAMMAAoKnBseFQBWAgAMAAoKnBseFQBWAgADAAEKIQqrqwA1AAAAAA==.Darkun:BAAANQADCggICAABNQAECgoKNAAVAGYPAA==.',
De='Deacon:BAABNQAECn8wAAIcAAgK4AfyEQDvAAAcAAgK4AfyEQDvAAAAAA==.Deadzly:BAABNQAECn83AAQMAAkKoSNsEAApAwAMAAgKsiNsEAApAwADAAgKZhY6PADdAQAEAAgKYhC6VQC7AQAAAA==.Deathknights:BAAANQADCgMIAwAAAA==.Deeanne:BAAANQAECgUIBwAAAA==.Deepfriar:BAABNQAECn9HAAMJAAoKnCUXDwBNAwAJAAoKnCUXDwBNAwAIAAUK2AfdNgDKAAAAAA==.Deltoro:BAAANQADCgIIAgAAAA==.Demoniiks:BAAANQABCgcICQAAAA==.Derailed:BAABNQAECn8cAAIDAAkKnws2UAA8AQADAAkKnws2UAA8AQAAAA==.Deshal:BAAANQAECgYIDQAAAA==.Dethwing:BAAANQADCgQICAAAAA==.Dewsbelle:BAAANQAECgUICwAAAA==.',
Dh='Dha:BAAANQADCgcIDQABNQAECggIHwAdAKUaAA==.',
Di='Diablognomis:BAAANQADCgcIDwAAAA==.Dirtman:BAABNQAECn80AAILAAoKtRYkMQD/AQALAAoKtRYkMQD/AQAAAA==.',
Dk='Dkrise:BAAANQADCgIIAgABNQAECgoKNAAVAGYPAA==.',
Do='Dolphina:BAAANQAECgEIAQAAAA==.Donny:BAAANQAECgUICAAAAA==.',
Dr='Dragonic:BAACNQAFFH8TAAMeAAYKoBr4BwCnAQAeAAYKoBr4BwCnAQAVAAIKxwN2DQBwAAA1AAQKfzAAAx4ACgozHLsHAMYCAB4ACgozHLsHAMYCABUAAgp3DigzAHYAAAAA.Dreathlu:BAAANQADCgUIBgAAAA==.Drewdog:BAABNQAECn8eAAIWAAcKIA/fuACSAQAWAAcKIA/fuACSAQAAAA==.',
Du='Dubes:BAABNQAECn9FAAIGAAoK3Br7BgCIAgAGAAoK3Br7BgCIAgAAAA==.Dunbartian:BAABNQAECn8xAAIdAAkKcBacDQDIAQAdAAkKcBacDQDIAQAAAA==.Duration:BAAANQABCgUIBwAAAA==.',
Ea='Easybreezin:BAAANQAECgcIDgAAAA==.',
Ei='Eirote:BAABNQAECn9GAAIfAAoKYxTFAQAaAgAfAAoKYxTFAQAaAgAAAA==.',
El='Elarisiel:BAAANQADCggIEwAAAA==.Elarris:BAAANQAECgQIBAAAAA==.Eldari:BAAANQAECgUIDwAAAA==.Eledron:BAAANQAECgQIBAAAAA==.Elyssaena:BAAANQAECgcIEAAAAA==.',
Em='Emotionaldmg:BAAANQAECgUIBQABNQAECggIDAARAAAAAA==.',
En='Enzojr:BAAANQAECgMIBAAAAA==.',
Er='Eriath:BAABNQAECn9IAAIIAAoKhh1wDgAJAwAIAAoKhh1wDgAJAwAAAA==.',
Ev='Evè:BAAANQABCgEIAQAAAA==.',
Ex='Exalted:BAAANQAECgUICwABNQAFFAYIEwAeAKAaAA==.',
Ey='Eye:BAABNQAECn8bAAMLAAoKphbgNACkAgALAAkKUxjgNACkAgASAAEKDQil9AAvAAAAAA==.',
Fa='Faranth:BAABNQAECn9GAAQVAAoKERjOBQBJAgAVAAoKERjOBQBJAgAgAAQKng2qEgCiAAAeAAEKoAn1OAAyAAAAAA==.',
Fe='Feld:BAAANQAECggIEQAAAA==.Felynne:BAAANQAECggIAwAAAA==.Feo:BAABNQAECn8gAAIPAAgKeBt0HgBdAgAPAAgKeBt0HgBdAgAAAA==.Feru:BAAANQAECgUIBQAAAA==.Ferum:BAABNQAECn9MAAIUAAoKVyXHAgDVAwAUAAoKVyXHAgDVAwAAAA==.',
Fi='Fionnan:BAABNQAECn83AAIhAAoK4BGmHACIAQAhAAoK4BGmHACIAQABNQAECgoKRgASAJsMAA==.Fizwidget:BAAANQADCgEIAQAAAA==.',
Fr='Freezia:BAAANQAECgYICgAAAA==.Frostigan:BAAANQAECgcIDAABNQAECgkJIQAiAKQPAA==.Fryeguy:BAAANQADCgQIBAAAAA==.',
Fu='Fudo:BAAANQAECgIIAQAAAA==.Fudoswrath:BAAANQAECgcIDAAAAA==.Funkysoup:BAAANQAECgUICwAAAA==.',
['Fò']='Fòrced:BAAANQADCgYIEAAAAA==.',
Ga='Gallium:BAAANQAECgIJAgAAAA==.',
Ge='Gehena:BAAANQAECgQIBAABNQAECgoKPAAWAHkjAQ==.Gemsareyum:BAAANQADCgIIAgABNQAFFAcIJAAWAMsgAA==.',
Gi='Girthquake:BAABNQAECn8cAAILAAgKXw0VfQABAQALAAgKXw0VfQABAQAAAA==.',
Gl='Glow:BAAANQADCggJCAAAAA==.',
Go='Goof:BAABNQAECn81AAIiAAoKQwipbQBYAQAiAAoKQwipbQBYAQAAAA==.Goontaa:BAAANQAECgQIAQAAAA==.',
Gr='Griz:BAAANQAECggIDQAAAA==.Grizzly:BAAANQAECgYIBgABNQAECggIDQARAAAAAA==.Grossevache:BAAANQADCgIIBAAAAA==.',
Ha='Haddor:BAABNQAECn8tAAIjAAkKzRK9GwB9AQAjAAkKzRK9GwB9AQAAAA==.Halfheart:BAAANQAECgUICwAAAA==.Hankerin:BAAANQAECgEIAQAAAA==.Harborhate:BAAANQAECgcIAgAAAA==.Harmoni:BAAANQAECgIIBQAAAA==.Harpomage:BAAANQADCggIEwAAAA==.Haunter:BAABNQAECn8lAAQEAAoKFR5nOABEAgAEAAkKUCBnOABEAgADAAcKaxd4QwC2AQAMAAYKjQ+GYgCvAAAAAA==.',
He='Heimdallr:BAAANQADCggIEAAAAA==.Heisenborg:BAAANQAECgQIBAAAAA==.Helldin:BAAANQAECgEIAQAAAA==.',
Hi='Hidden:BAAANQADCgMIAwABNQAFFAYIEwAeAKAaAA==.Hilite:BAAANQAECgQICAAAAA==.Himothyjr:BAAANQADCgcICgAAAA==.',
Ho='Holific:BAABNQAECn9EAAINAAoKVRUKVwAYAgANAAoKVRUKVwAYAgAAAA==.Holymommy:BAAANQAECgYIDgABNQAECgoKJAANAIgcAA==.Hoss:BAAANQAECggIDQAAAA==.Hotrodranger:BAABNQAECn8/AAIWAAkKBSBaPQBLAgAWAAkKBSBaPQBLAgAAAA==.',
Hs='Hshyomouth:BAAANQADCgIIAgABNQAECgkJPwAWAAUgAA==.',
Hu='Hunters:BAAANQADCgYIBgAAAA==.Hut:BAACNQAFFH8ZAAIHAAgKBxZXCAD+AQAHAAgKBxZXCAD+AQA1AAQKf1cAAgcACgqSJU8CAGkDAAcACgqSJU8CAGkDAAAA.',
Hy='Hypearione:BAAANQABCgEIAQAAAA==.',
Ia='Iambohike:BAAANQAECgEIAgAAAA==.',
Ic='Icycritties:BAABNQAECn8qAAQGAAoK3A1KDQClAQAGAAoK3A1KDQClAQAFAAcKnwZa1ADwAAAfAAEKPQOIDwAiAAAAAA==.',
Ih='Iheals:BAAANQADCgIIAgAAAA==.',
Im='Imjustadruid:BAAANQADCgMIAgAAAA==.Immortal:BAABNQAECn83AAIEAAoKQxMoHQDmAQAEAAoKQxMoHQDmAQAAAA==.',
In='Incarnated:BAABNQAECn8bAAMEAAoK3CFmDQBOAwAEAAoK3CFmDQBOAwADAAYKiRg+SgBXAQAAAA==.',
Ir='Irís:BAAANQAECggIEwAAAA==.',
Is='Iskra:BAAANQADCgIIAgAAAA==.Ispithotfire:BAAANQABCgQIBgAAAA==.',
Iu='Iu:BAAANQAECggIEQAAAA==.',
Ja='Jackfash:BAAANQADCgMIBQAAAA==.Jadecross:BAAANQADCgIIAgAAAA==.Jailbaitt:BAAANQAECgIIAgAAAA==.Javan:BAAANQADCgIIAgAAAA==.',
Je='Jerryatric:BAABNQAECn8iAAINAAcKDQ1q5ABSAQANAAcKDQ1q5ABSAQAAAA==.',
Ji='Jiri:BAAANQABCgcIDwAAAA==.',
Jk='Jkmno:BAAANQADCgMIAwABNQADCgUIBQARAAAAAA==.',
Jo='Joeyrains:BAAANQADCgQIBAAAAA==.',
Ju='Justblaze:BAAANQAECgQIBAAAAA==.Justincasê:BAAANQADCgIIAgAAAA==.',
Ka='Kallikan:BAABNQAECn8zAAIhAAgKdhSwHwBuAQAhAAgKdhSwHwBuAQAAAA==.Kamidk:BAABNQAECn8YAAMMAAkKVCBICgDjAgAMAAkKVCBICgDjAgAEAAMK9RLSSgDLAAAAAA==.Kamuri:BAAANQADCgUIBQAAAA==.Kasteen:BAAANQAECgEIAQAAAA==.Katia:BAABNQAECn8WAAINAAUKfQZgMQHQAAANAAUKfQZgMQHQAAAAAA==.Kaøs:BAAANQAECgEIAgAAAA==.',
Kd='Kdoggparker:BAAANQABCgYICQAAAA==.',
Ke='Kelvox:BAAANQAECgQIBAAAAA==.Kementari:BAABNQAECn8nAAIHAAkK/gVHRQD8AAAHAAkK/gVHRQD8AAAAAA==.Kenzaki:BAABNQAECn8qAAINAAgKiBVRkwD9AQANAAgKiBVRkwD9AQAAAA==.',
Kh='Khaladin:BAAANQADCgYICAAAAA==.Khaosreborn:BAAANQADCgUIAQAAAA==.Khaotic:BAAANQAECgQIBAAAAA==.',
Ki='Kilaaz:BAABNQAECn8oAAINAAoKHCJ2MACTAgANAAoKHCJ2MACTAgAAAA==.Kilossus:BAAANQAECgUICAAAAA==.Kirveka:BAAANQABCgQIBAAAAA==.',
Kl='Kliticaldk:BAAANQAECgIIBAAAAA==.Kliticalwar:BAABNQAECn8bAAIYAAoK7A9ZjgD4AQAYAAoK7A9ZjgD4AQAAAA==.Klothys:BAABNQAECn8lAAINAAoKAx3iXQB/AgANAAoKAx3iXQB/AgAAAA==.',
Kn='Knuts:BAAANQADCgMJAwABNQAECgYICQARAAAAAA==.',
Ko='Koitsvo:BAAANQAECgMIBQAAAA==.Ková:BAAANQADCgUJCwAAAA==.',
Ku='Kuani:BAAANQAECgQIBAABNQAECgoKPwAZAL8eAA==.',
La='Landre:BAAANQADCgQIBgAAAA==.Lassy:BAAANQADCgIJAgAAAA==.Lathray:BAABNQAECn8dAAMUAAgKPQuVMwA7AQAUAAgKPQuVMwA7AQAHAAEKAAApxQAdAAAAAA==.Lazerislong:BAAANQAECgEIAQAAAA==.Lazerous:BAAANQAECgMIAwAAAA==.',
Le='Lealoo:BAABNQAECn8sAAINAAoKWBPGkQABAgANAAoKWBPGkQABAgABNQAECgoKNwAQAOMTAA==.Leftfield:BAAANQAECgIIAgABNQAECgoKLQAOAA8JAA==.Legolard:BAABNQAECn8fAAMdAAgKpRp0EQAPAgAdAAcKZh90EQAPAgAYAAMKiwecMwFtAAAAAA==.Leleia:BAABNQAECn8bAAIIAAkKVwp4IgBaAQAIAAkKVwp4IgBaAQAAAA==.',
Lh='Lhera:BAABNQAECn8mAAMkAAoKvR9yDACpAgAkAAoKvR9yDACpAgASAAcKMRR/eACiAQABNQAECgoKMgAbAGEfAA==.',
Li='Liath:BAABNQAECn8jAAIJAAcKtxWWZACaAQAJAAcKtxWWZACaAQAAAA==.Lichtenberg:BAABNQAECn9CAAMLAAoKcyBTEQDXAgALAAoKcyBTEQDXAgASAAUKxwjL1AC9AAAAAA==.Linddori:BAABNQAECn8XAAINAAkKEQ3xyQAsAQANAAkKEQ3xyQAsAQABNQAECgoKLgACAAQWAA==.Lirillia:BAABNQAECn8uAAQCAAoKBBY5CgBTAgACAAgKMxg5CgBTAgAOAAkK3wxQqQDuAAAlAAEKAACoMAA0AAAAAA==.Lizzie:BAAANQADCgUIBQAAAA==.',
Lo='Locdon:BAAANQABCgIIAgABNQAECgUICAARAAAAAA==.Lodestone:BAAANQAECgQIBAAAAA==.Loena:BAABNQAECn8XAAMiAAoK7AyDVACwAQAiAAkK1AuDVACwAQANAAIKEwF7wwEAAAAAAA==.Lokk:BAAANQAECgIIAgABNQAECggIJAAWAOIaAA==.Loko:BAAANQAECgEIAQAAAA==.Lolowbeatz:BAAANQADCgUICwAAAA==.Lovelydread:BAAANQAECgEIAQAAAA==.',
Lu='Lunabug:BAAANQAECgIIAgAAAA==.Lupinos:BAAANQADCgIIAQAAAA==.',
Ly='Lyadra:BAABNQAECn8vAAIJAAoKWx6tLACAAgAJAAoKWx6tLACAAgAAAA==.Lyrissa:BAAANQADCgYIBgAAAA==.',
['Lõ']='Lõst:BAAANQAECgIIAwAAAA==.',
Ma='Mackito:BAABNQAFFH8QAAIWAAkK6wF5IwCEAAAWAAkK6wF5IwCEAAAAAA==.Madan:BAABNQAECn8hAAIEAAcK9weSOwAWAQAEAAcK9weSOwAWAQAAAA==.Mahoushojou:BAAANQAECgIIAgABNQAECgkJIQAiAKQPAA==.Malasminna:BAAANQAECgYIEgAAAA==.Malehorelock:BAAANQAECgEIAQAAAA==.Malicioun:BAAANQABCggIEwAAAA==.Malkariss:BAABNQAECn8sAAMGAAgK4xrYGwARAQAFAAYKNhsGjQB5AQAGAAUKBhfYGwARAQAAAA==.Mammadruid:BAABNQAECn8sAAIhAAcKngxONQDfAAAhAAcKngxONQDfAAAAAA==.Mauldis:BAABNQAECn8tAAMLAAgKhAbLeAAMAQALAAgKhAbLeAAMAQASAAUKtQI07QCRAAAAAA==.',
Me='Meryl:BAABNQAECn8wAAIiAAkKYxi2PAByAgAiAAkKYxi2PAByAgAAAA==.',
Mi='Miaka:BAABNQAECn87AAIlAAoK7RmgAwC4AgAlAAoK7RmgAwC4AgAAAA==.Minigoonta:BAAANQAECgcIBwAAAA==.Minth:BAAANQADCgcIDQABNQAECgkJIQAiAKQPAA==.Miraakle:BAAANQAECgQIBwABNQAECgkJIQAiAKQPAA==.Misfire:BAABNQAECn82AAIWAAoKoBBEawDRAQAWAAoKoBBEawDRAQAAAA==.Mithra:BAAANQAECgQICQAAAA==.',
Mo='Moghroth:BAABNQAECn88AAMHAAoK7gwOMgBhAQAHAAkKcgwOMgBhAQAhAAMKtwqCWQBVAAAAAA==.Molykote:BAAANQAECggIDAAAAA==.Monks:BAAANQADCgQIBAAAAA==.Monsterbabe:BAAANQADCgUICgAAAA==.Moreleath:BAAANQADCgMIBAAAAA==.Morphias:BAAANQADCgQIBAAAAA==.Mowiewowie:BAAANQABCgIIAgAAAA==.',
Mu='Murdrmitts:BAABNQAECn8bAAIhAAcKmwsrKgBGAQAhAAcKmwsrKgBGAQAAAA==.',
['Mâ']='Mâsterdon:BAAANQAECgQIBAAAAA==.',
['Mã']='Mãtador:BAACNQAFFH8HAAILAAUK1RPnEABdAQALAAUK1RPnEABdAQA1AAQKfy0AAwsACQpmIxAgAAsDAAsACQpmIxAgAAsDABIAAwo3EJv6AHUAAAAA.',
['Mä']='Mätadør:BAABNQAECn8UAAIIAAgKFxs2IgAjAgAIAAgKFxs2IgAjAgABNQAFFAUIBwALANUTAA==.',
['Mì']='Mìasma:BAAANQABCgQIBAAAAA==.',
Na='Nahryn:BAABNQAECn8tAAIUAAgKzhwZFwCJAgAUAAgKzhwZFwCJAgAAAA==.',
Ne='Nedina:BAAANQADCgUIBQAAAA==.Nerbert:BAAANQADCgYJBgABNQAECgoKNgAVAFESAA==.Neretsym:BAABNQAECn82AAIWAAoKfA+iXgDyAQAWAAoKfA+iXgDyAQAAAA==.',
Ni='Nineva:BAABNQAECn8cAAIUAAgKYQbhPAADAQAUAAgKYQbhPAADAQAAAA==.',
No='Nobas:BAABNQAECn9GAAIHAAoKngu7KgCUAQAHAAoKngu7KgCUAQAAAA==.Nonoa:BAAANQAECgEIAgAAAA==.',
Oc='Octavien:BAAANQADCgIIAgAAAA==.',
Og='Ogr:BAAANQADCgMIAwAAAA==.',
On='Onlyfeet:BAABNQAECn8kAAINAAoKiBzLPgBfAgANAAoKiBzLPgBfAgAAAA==.',
Op='Oppgjør:BAAANQAECgEIAQAAAA==.',
Or='Oreeree:BAAANQAECgQIDgAAAA==.Ormr:BAABNQAECn82AAMVAAoKURIPEQBEAgAVAAoKURIPEQBEAgAgAAEKAABPIwA5AAAAAA==.',
Os='Osteo:BAABNQAECn8sAAMCAAkKRQajJwA7AQACAAcK2wSjJwA7AQAOAAkKCAbdpAD4AAAAAA==.Osteoprime:BAAANQADCgUJBQAAAA==.',
Ou='Ouron:BAABNQAECn8uAAMSAAoKzBbmPQBoAgASAAoKzBbmPQBoAgALAAEKAABCFwEAAAAAAA==.Outofmana:BAAANQAECgQIDQAAAA==.',
Ov='Ovelia:BAAANQAECgUIBAAAAA==.',
Pa='Pagoda:BAAANQADCgYIBgAAAA==.Papashrimps:BAACNQAFFH8QAAMFAAUKKxTgKQA8AQAFAAQKKxTgKQA8AQAGAAEKAAB5FwAAAAA1AAQKfyYAAwUACgqHGISWAFMCAAUACgqXF4SWAFMCAAYAAQoxGmQ/AEYAAAAA.',
Pe='Percy:BAAANQADCggIGQAAAA==.',
Ph='Phatcow:BAAANQADCgEIAQAAAA==.',
Pl='Placeholder:BAABNQAECn89AAMjAAoKeiE1BgDpAgAjAAoKeiE1BgDpAgANAAEKZQ6deQE+AAAAAA==.',
Po='Pojoevokest:BAABNQAECn8nAAIeAAgKUgrZHQARAQAeAAgKUgrZHQARAQAAAA==.Pontifex:BAABNQAECn8vAAIJAAoKDhUKWQAXAgAJAAoKDhUKWQAXAgAAAA==.Portandmorph:BAABNQAECn8jAAIGAAoK8xOWCwAHAgAGAAoK8xOWCwAHAgAAAA==.',
Pr='Praxx:BAAANQAECggICAABNQAECgoKNgAVAFESAA==.Priests:BAAANQADCgQIBgAAAA==.Prone:BAABNQAECn9GAAMSAAoKmwwSdABAAQASAAkK3gkSdABAAQALAAYKFQa3igDgAAAAAA==.Protarada:BAAANQAECgcICwAAAA==.',
Qu='Quietmind:BAABNQAECn8VAAINAAoKwwU6/wAhAQANAAoKwwU6/wAhAQAAAA==.',
Ra='Raakotah:BAABNQAECn8+AAIHAAoKHyX4DQBbAwAHAAoKHyX4DQBbAwAAAA==.Raasclaat:BAAANQADCgcIDQAAAA==.Raelo:BAABNQAECn87AAIkAAoKpw3PEAD0AQAkAAoKpw3PEAD0AQAAAA==.Rainbowflake:BAABNQAECn8VAAIWAAcK3wIbAgEBAQAWAAcK3wIbAgEBAQAAAA==.Raiseurmug:BAABNQAECn82AAIcAAoKyRBXCwBuAQAcAAoKyRBXCwBuAQAAAA==.Rakash:BAAANQADCgcIBwAAAA==.Rarg:BAABNQAECn8VAAMMAAgKlRnWSgDMAQAMAAgKlRnWSgDMAQAEAAEK6QLn8gAkAAAAAA==.Ravia:BAAANQAFFAEIAQAAAA==.Rayjr:BAAANQAECgcIDQAAAA==.',
Re='Rendysavage:BAAANQAECgYJBgAAAA==.Resco:BAAANQADCggIEgAAAA==.',
Ri='Riddle:BAABNQAECn8xAAISAAoKZguShwB3AQASAAoKZguShwB3AQAAAA==.Rimeouo:BAAANQAFFAEIAQAAAA==.Rize:BAABNQAECn8aAAIYAAgK/w++mgDaAQAYAAgK/w++mgDaAQABNQAECgoKNAAVAGYPAA==.Rizmthetizm:BAAANQADCgEIAQAAAA==.',
Ro='Rosenrott:BAABNQAECn88AAIWAAoKeSMdDgAXAwAWAAoKeSMdDgAXAwAAAA==.Rosepiercer:BAABNQAECn80AAIWAAoKMiTHCQA2AwAWAAoKMiTHCQA2AwAAAA==.Rouz:BAABNQAECn8bAAIVAAcKhgnYEwDlAAAVAAcKhgnYEwDlAAAAAA==.',
Ru='Ruddybear:BAAANQADCgIJAgAAAA==.',
Ry='Ryoto:BAAANQAECgUICAAAAA==.',
Sa='Sadarasdeath:BAAANQAECgQIBwAAAA==.Samandean:BAABNQAECn83AAIQAAoK4xOFHQAMAgAQAAoK4xOFHQAMAgAAAA==.Sarasvati:BAAANQAECgMIAwAAAA==.Sariia:BAAANQAECggIDwAAAA==.',
Se='Sellena:BAABNQAECn8sAAIkAAkK1hOsEAD2AQAkAAkK1hOsEAD2AQABNQAECgoKNwAQAOMTAA==.',
Sh='Shakenn:BAAANQADCgEIAQAAAA==.Shandow:BAABNQAECn9TAAIGAAoKrCNkAQAoAwAGAAoKrCNkAQAoAwAAAA==.Shansoracle:BAABNQAECn8wAAMJAAoKWx8OFQAdAwAJAAoKWx8OFQAdAwAIAAEKaAP7ggAmAAABNQAECgoKUwAGAKwjAA==.Shed:BAAANQAECgUIBAABNQAFFAgIGQAHAAcWAA==.Sheislegend:BAAANQADCggIFgAAAA==.Shelby:BAABNQAECn8sAAIJAAoKFBuEQQBlAgAJAAoKFBuEQQBlAgAAAA==.Shocked:BAAANQAECggIAwABNQAECggIDAARAAAAAA==.Shockolate:BAAANQAECggIEQAAAA==.Shoog:BAAANQADCgUIBQAAAA==.Shrimpbottom:BAAANQAFFAIIAgAAAA==.',
Si='Siarn:BAAANQADCgMIBQAAAA==.Siccinok:BAABNQAECn88AAMFAAgKJR6QYwDfAQAFAAgKJR6QYwDfAQAGAAQKwx2kIADkAAAAAA==.Sixhundrdlbs:BAACNQAFFH8OAAIPAAQKUh3JBgDwAAAPAAQKUh3JBgDwAAA1AAQKf0AAAw8ACgreJLADAJ0DAA8ACgreJLADAJ0DABAAAQqYCiqCAC4AAAE1AAQKCgobAAQA3CEA.',
Sk='Skraps:BAAANQADCgEJAQAAAA==.',
Sl='Slimped:BAAANQADCgYICwAAAA==.',
Sn='Sneakybato:BAAANQADCggIFwAAAA==.',
So='Sofie:BAAANQADCgQIBAABNQAECgoKQgALAHMgAA==.Solarial:BAAANQAECgUIEQAAAA==.Solastra:BAABNQAECn82AAIiAAgKuRbWVQAYAgAiAAgKuRbWVQAYAgAAAA==.Soramai:BAAANQAECgQIBwAAAA==.Soth:BAABNQAECn9GAAMEAAoK0xbKGAAQAgAEAAoK0xbKGAAQAgAMAAkK0BByVgCaAQAAAA==.',
Sp='Sparký:BAABNQAECn8nAAIOAAoK9iQtBgA4AwAOAAoK9iQtBgA4AwAAAA==.Spinnycrisp:BAAANQADCgYIBgAAAA==.',
St='Starlyvana:BAACNQAFFH8QAAMGAAYKhQ4TAQA8AQAGAAUKhQ4TAQA8AQAFAAIKlwdbTQAAAAA1AAQKfxoAAwYACgprFssHAG8CAAYACgprFssHAG8CAAUAAQrEGLc7AUoAAAAA.Staryxia:BAABNQAECn8XAAIDAAkKSh1KNgD/AQADAAkKSh1KNgD/AQAAAA==.Statiic:BAAANQABCgIIBQAAAA==.Steamdruid:BAAANQADCggIDwABNQAECgoKRQAQANkcAA==.Steephany:BAAANQADCgMIBwAAAA==.Stonecross:BAABNQAECn8mAAIJAAkKDxuGOgB/AgAJAAkKDxuGOgB/AgAAAA==.Stoneldo:BAAANQAECgUIBQAAAA==.Stormbolt:BAABNQAECn84AAIHAAoKCAz7MABpAQAHAAoKCAz7MABpAQAAAA==.Stormspirit:BAAANQADCggIHQAAAA==.Striggen:BAABNQAECn8WAAMNAAUKYxTr8wDnAAANAAUKLxTr8wDnAAAjAAMKuA5/VgCHAAAAAA==.',
Su='Sugarsham:BAABNQAECn8kAAILAAoKpAvJcgDIAQALAAoKpAvJcgDIAQAAAA==.Sulwen:BAACNQAFFH8YAAIHAAgK0SRnAQDwAgAHAAgK0SRnAQDwAgA1AAQKfzkAAgcACgryJkoAAJgDAAcACgryJkoAAJgDAAAA.Sumerset:BAABNQAECn8cAAINAAoKjA9HfQC+AQANAAoKjA9HfQC+AQAAAA==.Sundave:BAAANQAECgEJAgAAAA==.Supaflytnt:BAABNQAECn82AAITAAkKBhukBwBlAgATAAkKBhukBwBlAgAAAA==.Sustia:BAAANQAECgUICwAAAA==.',
Ta='Taera:BAABNQAECn8/AAIZAAoKvx6aBQAxAwAZAAoKvx6aBQAxAwAAAA==.Talavenn:BAABNQAECn8kAAIPAAkK0B2uEQDgAgAPAAkK0B2uEQDgAgAAAA==.Tanglock:BAABNQAECn8WAAMOAAgKLgojgQBJAQAOAAgKLgojgQBJAQAlAAMKgAQcIwBTAAAAAA==.Tarage:BAAANQAECgUIDAAAAA==.Taurîel:BAAANQADCgYIBgAAAA==.',
Te='Tectoniiks:BAAANQAECgcIBwAAAA==.Tedds:BAAANQAECgUICAAAAA==.Teds:BAAANQADCgYICwAAAA==.Tempus:BAAANQAECgMJAwAAAA==.Teriko:BAABNQAECn8vAAIDAAoKYxgVLQA3AgADAAoKYxgVLQA3AgAAAA==.Teviro:BAAANQADCgIIAgABNQAECgoKMgAbAGEfAA==.',
Th='Thequixote:BAABNQAECn8iAAITAAcKbxZDEQCSAQATAAcKbxZDEQCSAQAAAA==.',
Ti='Tictok:BAAANQADCgYICgAAAA==.Tinytotems:BAAANQADCgQIBAAAAA==.',
To='Toaderic:BAAANQAECgUIDwAAAA==.Toemama:BAAANQAECgEIAgABNQAECgoKJAANAIgcAA==.Tots:BAABNQAECn9DAAIhAAoKih2pCgCBAgAhAAoKih2pCgCBAgAAAA==.Totss:BAAANQADCgYIBgAAAA==.Toxictotes:BAAANQADCgYICQAAAA==.',
Tr='Trazah:BAAANQADCgEIAQAAAA==.',
Ty='Tyraèl:BAABNQAECn8lAAIiAAoKGyMBCACJAwAiAAoKGyMBCACJAwAAAA==.Tyzy:BAACNQAFFH8WAAMUAAQK4iEYBgCJAQAUAAQK4iEYBgCJAQAHAAQK8CMiDAAcAQA1AAQKfysAAwcACgrvI/YNAFsDAAcACgrvI/YNAFsDABQACQowHZkXAIQCAAAA.',
Um='Umber:BAAANQADCggICAAAAA==.',
Va='Valenora:BAABNQAECn83AAMCAAoKFhv4AQBtAgACAAoKFhv4AQBtAgAOAAEKDwoSDQE4AAAAAA==.Valvitor:BAAANQADCgEIAQAAAA==.Varuz:BAABNQAECn8kAAIWAAgK4hpIQACqAgAWAAgK4hpIQACqAgAAAA==.Varyz:BAAANQADCgIIAgABNQAECggIJAAWAOIaAA==.',
Ve='Velanie:BAAANQAECgEIAQAAAA==.Veloon:BAABNQAECn8bAAIHAAkKIg7hQgDqAQAHAAkKIg7hQgDqAQAAAA==.Veloras:BAAANQAECggICgAAAA==.Verinari:BAAANQAECgQICQAAAA==.',
Vi='Vipul:BAAANQADCgUIDQABNQADCgYIBwARAAAAAA==.Viridria:BAABNQAECn8hAAMiAAkKpA8oWACjAQAiAAkKpA8oWACjAQANAAIKZwn2nQEkAAAAAA==.Vityazi:BAABNQAECn8ZAAINAAgKDgS6KAHcAAANAAgKDgS6KAHcAAAAAA==.',
Vo='Voodoobootie:BAAANQABCgcJBwAAAA==.',
Vy='Vy:BAAANQADCgUICQAAAA==.',
['Vè']='Vè:BAABNQAECn8pAAIhAAkKqxAbGgDWAQAhAAkKqxAbGgDWAQAAAA==.',
Wa='Warriors:BAABNQAECn9IAAIYAAoKDiNqFwBbAwAYAAoKDiNqFwBbAwAAAA==.Wartooth:BAABNQAECn8zAAMCAAgKiBUvKQAxAQAOAAgKSg6qdgBjAQACAAQKiBgvKQAxAQAAAA==.Wassergott:BAAANQAECgEIAQAAAA==.',
We='Webicus:BAABNQAECn8fAAQYAAkKbgn5xwBoAQAYAAgKPgr5xwBoAQAXAAMKfQZeKQBUAAAdAAEKjQQnRgAnAAAAAA==.Weebster:BAAANQABCgQIBAAAAA==.Wendee:BAABNQAECn81AAMJAAoKkAW0bAB/AQAJAAoKkAW0bAB/AQAIAAEKAABKlAATAAAAAA==.',
Wh='Whitefóx:BAABNQAECn8YAAQjAAkKFQmSLAD9AAAjAAgKdQmSLAD9AAANAAcKzQK1IwGhAAAiAAEKlQMv/gAlAAABNQAECgoKUwAGAKwjAA==.Whitley:BAABNQAECn8+AAMSAAoKryAoEQAhAwASAAoKryAoEQAhAwALAAcKkBThbgDTAQAAAA==.',
Wi='Wildspart:BAABNQAECn8WAAMmAAkKGxSECABVAQAmAAkKChOECABVAQAWAAIKxhYeKwGaAAAAAA==.',
Wo='Wooden:BAABNQAECn81AAIWAAkKfRl1TgAcAgAWAAkKfRl1TgAcAgAAAA==.',
Xa='Xaphy:BAABNQAECn8iAAMJAAoKQxq3MgBgAgAJAAkKOxy3MgBgAgAIAAoKPg1TGwClAQAAAA==.Xardots:BAABNQAECn8aAAICAAcKthN8EgDhAQACAAcKthN8EgDhAQABNQAECggINgARAAAAAA==.',
Xi='Xiareth:BAABNQAECn8xAAIeAAcKZBEXGQBNAQAeAAcKZBEXGQBNAQAAAA==.',
Xy='Xyleiah:BAAANQADCgYIBgABNQAECgoKRgAVABEYAA==.',
['Xá']='Xároth:BAAANQAECggINgAAAQ==.',
Ya='Yaddi:BAAANQAECgQIAwAAAA==.Yargue:BAABNQAECn84AAIIAAoKlBtFCwCYAgAIAAoKlBtFCwCYAgAAAA==.',
Ye='Yeeyee:BAAANQAECggIDAAAAA==.',
Yi='Yirï:BAAANQABCgQIBgAAAA==.',
Yo='Yorgue:BAAANQAECggIAgABNQAECgoKOAAIAJQbAA==.Youngjeezy:BAABNQAECn8aAAMEAAYKmgPrXgCBAAAEAAYKmgPrXgCBAAADAAIKZQOHuAAdAAAAAA==.Yoursinpride:BAAANQAECggIDgAAAA==.',
Za='Zackor:BAAANQADCgUIDAAAAA==.',
Ze='Ze:BAAANQADCgYICgAAAA==.Zervann:BAAANQADCgYIBgAAAA==.',
Zi='Ziska:BAAANQADCgIIAgAAAA==.',
Zo='Zorithic:BAAANQAECgIJAwAAAA==.',
Zy='Zyde:BAAANQAECgUIBAABNQAECggIJAAWAOIaAA==.',
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
