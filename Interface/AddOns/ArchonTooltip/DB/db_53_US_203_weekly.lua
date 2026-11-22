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

local lookup = {'Rogue-Outlaw','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Unholy','Mage-Arcane','Mage-Frost','Druid-Balance','Priest-Shadow','Priest-Holy','Priest-Discipline','Shaman-Elemental','DeathKnight-Blood','Monk-Windwalker','Monk-Mistweaver','Paladin-Retribution','Warlock-Demonology','DemonHunter-Devourer','DemonHunter-Havoc','Unknown-Unknown','Shaman-Restoration','Druid-Feral','Druid-Restoration','Evoker-Devastation','Hunter-BeastMastery','Warrior-Fury','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','Monk-Brewmaster','Warrior-Protection','Evoker-Preservation','Hunter-Marksmanship','Mage-Fire','Evoker-Augmentation','Druid-Guardian','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Warlock-Affliction','Hunter-Survival',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aanuanaela:BAABNQAECn8uAAIBAAoKKROxAgD1AQABAAoKKROxAgD1AQAAAA==.Aanubis:BAAANQAECgUICAAAAA==.',
Ab='Absens:BAABNQAECn89AAICAAoKORAUBgCIAQACAAoKORAUBgCIAQAAAA==.Abumim:BAAANQAECgUICAAAAA==.',
Ad='Adorian:BAAANQAECgQIBAABNQAECgoKNwADAIkhAA==.Adwillon:BAAANQAECgQIAwAAAA==.',
Af='Aforceofone:BAAANQAECgcIDAAAAA==.',
Ag='Aggretsuko:BAABNQAECn8uAAMEAAoKjxa0QAAaAgAEAAgKGhm0QAAaAgADAAkKHAvOTgB5AQAAAA==.',
Ak='Akiraa:BAAANQAECgQIBAAAAA==.',
Al='Aldonza:BAAANQADCgIIAgAAAA==.Alex:BAAANQAECgUIDgAAAA==.Alivanllan:BAAANQAECgQIBQAAAA==.Aluviel:BAACNQAFFH8KAAMFAAMKdhx9LgAdAQAFAAMKdhx9LgAdAQAGAAEKAQwdEwBIAAA1AAQKfxwAAwUACQo3JYsiAFIDAAUACQo3JYsiAFIDAAYAAQoNIQ00AFsAAAE1AAUUCQkaAAcABSQA.Alyslia:BAAANQABCggIGQAAAA==.',
An='Anamuht:BAABNQAECn82AAQIAAoK+BWZLgCwAQAIAAgKDxOZLgCwAQAJAAkK7g5IdQB7AQAKAAMKEgcpHQB6AAABNQAECgoKSwALABghAA==.Angeli:BAAANQAECgEIAQAAAA==.Annaday:BAABNQAECn8hAAIMAAoKWxBQMACMAQAMAAoKWxBQMACMAQAAAA==.Antiock:BAABNQAECn83AAQDAAoKiSE8EQAFAwADAAoKrx08EQAFAwAMAAcKzyLrLwBSAgAEAAcKnxksQwAOAgAAAA==.Anyaesthesia:BAAANQAECgMIAwAAAA==.Anyamonka:BAABNQAECn8WAAMNAAoK+RBZKgDKAQANAAoK+RBZKgDKAQAOAAIKkAhlRgBRAAAAAA==.',
Ap='Appalachia:BAAANQADCgYIBgAAAA==.',
Ar='Ariea:BAAANQADCgEIAQAAAA==.Arraven:BAAANQADCggIBwAAAA==.Arrowmir:BAAANQABCgYJCAAAAA==.Artto:BAAANQADCgIIAgAAAA==.',
As='Ashbrínger:BAABNQAECn9EAAIPAAoKsSPDGABhAwAPAAoKsSPDGABhAwAAAA==.Association:BAAANQAECgEIAQABNQAECgoKMwAQAEUOAA==.',
At='Atua:BAAANQAECgEIAgAAAA==.',
Av='Averax:BAABNQAECn8/AAMRAAoKuR9sDACLAgARAAoKuR9sDACLAgASAAEKAAB3jQBBAAAAAA==.Avylbrew:BAAANQADCgcICgABNQAECgIIAgATAAAAAA==.',
Ay='Aylakaye:BAAANQADCggICQAAAA==.',
Az='Azzathoth:BAAANQADCggICAAAAA==.',
Ba='Babybilly:BAABNQAECn8mAAMLAAoKoh79KAA9AgALAAkKzR79KAA9AgAUAAYKWR5EVQC+AQAAAA==.Babyshoes:BAAANQAECgQIBwAAAA==.Backpack:BAAANQAECgcIDAAAAA==.Bananawaffle:BAAANQADCgEIAQAAAA==.Bandan:BAABNQAECn8XAAIIAAkKwRquJQACAgAIAAkKwRquJQACAgAAAA==.Bato:BAAANQADCgUIDAAAAA==.',
Be='Beauvito:BAAANQADCgEIAQAAAA==.Beefjurkey:BAAANQAECgQICQAAAA==.',
Bh='Bhalthazar:BAAANQADCgUICQABNQADCgYICAATAAAAAA==.',
Bi='Bier:BAAANQAECgQIBgAAAA==.Bigrig:BAAANQAECgEIAQAAAA==.Bitterman:BAABNQAECn8zAAIQAAoKRQ5TYgCvAQAQAAoKRQ5TYgCvAQAAAA==.',
Bl='Blastin:BAAANQADCggIGAAAAA==.Bloodveil:BAABNQAECn8VAAIVAAcK9Ro7GABVAQAVAAcK9Ro7GABVAQABNQAECgoKJQAPAOkcAA==.Bluemonster:BAAANQADCgQIBAAAAA==.',
Bo='Boohoo:BAAANQADCgMIAwAAAA==.Bovinedivine:BAAANQADCgUIBQABNQAECggIPgATAAAAAA==.',
Br='Brandumb:BAAANQAECgYICgAAAA==.',
Ca='Callana:BAAANQAECgQICAAAAA==.Camedra:BAABNQAECn9BAAIWAAoKdiRuBACuAwAWAAoKdiRuBACuAwAAAA==.Carelessheal:BAAANQAECggICAAAAA==.Carthella:BAAANQADCgQJBAABNQAECgoKNgAXAFESAA==.Catamynyia:BAABNQAECn8cAAIYAAkKsgt1pwC2AQAYAAkKsgt1pwC2AQAAAA==.',
Cc='Cchaos:BAAANQAECgMJAwAAAA==.',
Ce='Celaborn:BAABNQAECn8uAAMZAAkKDBuSDgCWAQAaAAkK4xZBYwDWAQAZAAYK9hySDgCWAQAAAA==.Celice:BAAANQABCgcIBwABNQAECgoKSQAOACsgAA==.',
Ch='Chimaira:BAAANQADCgQIBAAAAA==.Chucknoris:BAAANQADCgcJEQAAAA==.Chump:BAAANQADCgEIAQAAAA==.',
Cl='Claytonbigse:BAAANQABCgIIAgAAAA==.',
Co='Colossus:BAAANQAECgYIDwABNQAECgkJGgAEACIWAA==.Colossuss:BAABNQAECn8aAAIEAAkKIhbHHQD0AQAEAAkKIhbHHQD0AQAAAA==.Commodious:BAAANQADCgcICgAAAA==.Conduction:BAAANQAECgQIBAAAAA==.',
Cr='Crankadin:BAAANQAECggIAQABNQADCggIEQATAAAAAA==.Crispyquinn:BAAANQADCgUIBQAAAA==.Crispysham:BAABNQAECn8cAAILAAkKhg/ZZwDpAQALAAkKhg/ZZwDpAQAAAA==.Cruciö:BAAANQADCggIDAAAAA==.Crànk:BAAANQADCggIEQAAAA==.Cránk:BAAANQAECggJCAABNQADCggIEQATAAAAAA==.Crãnk:BAABNQAECn8bAAMbAAkKgw0MiwAGAQAcAAUKzAriZwATAQAbAAkKqwoMiwAGAQABNQADCggIEQATAAAAAA==.',
Cu='Cullyeskie:BAABNQAECn8dAAIYAAkK4QKzBQGnAAAYAAkK4QKzBQGnAAAAAA==.Curveball:BAAANQAECgMIAwABNQAECgoKMwAQAEUOAA==.',
Cy='Cyniar:BAABNQAECn86AAIHAAoKAQ4DMgB6AQAHAAoKAQ4DMgB6AQAAAA==.',
Da='Dabrick:BAAANQADCgEIAQAAAA==.Dahnu:BAAANQADCgIIAgABNQAECggIJAAJANoTAA==.Damerlin:BAAANQADCgIIAgAAAA==.Darios:BAAANQADCgUIBgABNQAECggIDwATAAAAAA==.Darkhuntress:BAAANQADCgYIBgAAAA==.Darkstär:BAABNQAECn9QAAMMAAoKGx7qDgCuAgAMAAoKGx7qDgCuAgADAAIKIQp/tAA1AAAAAA==.Darkun:BAAANQADCggICAABNQAECgoKNAAXAGYPAA==.',
De='Deacon:BAABNQAECn83AAIdAAoKsAeEDgA/AQAdAAoKsAeEDgA/AQAAAA==.Deadsinsloth:BAAANQAECggICAAAAA==.Deadzly:BAABNQAECn83AAQMAAkKoSNsEAApAwAMAAgKsiNsEAApAwADAAgKZhY6PADdAQAEAAgKYhC6VQC7AQAAAA==.Deathknights:BAAANQADCgMIAwAAAA==.Decay:BAAANQAECgQIBAABNQAECggIDgATAAAAAA==.Deeanne:BAAANQAECgUIBwAAAA==.Deepfriar:BAABNQAECn9QAAMJAAoKnCWHCQCfAwAJAAoKnCWHCQCfAwAIAAUK2Ae4OgDKAAAAAA==.Deltoro:BAAANQADCgIIAgAAAA==.Demoniiks:BAAANQABCgcICQAAAA==.Derailed:BAABNQAECn8cAAIDAAkKnwsSVwA5AQADAAkKnwsSVwA5AQAAAA==.Deshal:BAAANQAECgYIDwAAAA==.Dethwing:BAAANQADCgQICAAAAA==.Dewsbelle:BAAANQAECgUICwAAAA==.',
Dh='Dha:BAAANQADCgcIDQABNQAECggIHwAeAKUaAA==.',
Di='Diablognomis:BAAANQADCgcIDwAAAA==.Dirtman:BAABNQAECn80AAILAAoKtRYINgD9AQALAAoKtRYINgD9AQAAAA==.Distillate:BAAANQADCgYIHAAAAA==.',
Dk='Dkrise:BAAANQADCgIIAgABNQAECgoKNAAXAGYPAA==.',
Do='Dolphina:BAAANQAECgEIAQAAAA==.Donny:BAAANQAECgUICAAAAA==.',
Dr='Dragonic:BAACNQAFFH8TAAMfAAYKoBojCQClAQAfAAYKoBojCQClAQAXAAIKxwN2DQBwAAA1AAQKfzAAAx8ACgozHHEIAMYCAB8ACgozHHEIAMYCABcAAgp3DigzAHYAAAAA.Dreathlu:BAAANQADCgUIBgAAAA==.Drewdog:BAABNQAECn8eAAIYAAcKIA/fuACSAQAYAAcKIA/fuACSAQAAAA==.',
Du='Dubes:BAABNQAECn9OAAIGAAoKxBv7BgCIAgAGAAoKxBv7BgCIAgAAAA==.Dunbartian:BAABNQAECn8xAAIeAAkKcBY5DwDEAQAeAAkKcBY5DwDEAQAAAA==.Duration:BAAANQABCgUIBwAAAA==.',
Ea='Easybreezin:BAABNQAECn8ZAAIgAAkKPwfUHgB+AQAgAAkKPwfUHgB+AQAAAA==.',
Ei='Eirote:BAABNQAECn9PAAIhAAoKoRd+AQBTAgAhAAoKoRd+AQBTAgAAAA==.',
El='Elarisiel:BAAANQAECgQIBAABNQAECgoKMgACALEWAA==.Elarris:BAAANQAECgQIBAAAAA==.Eldari:BAAANQAECgUIDwAAAA==.Eledron:BAAANQAECgQIBAAAAA==.Elyssaena:BAAANQAECgcIEQAAAA==.',
Em='Emotionaldmg:BAAANQAECgUIBQABNQAECggIDAATAAAAAA==.',
En='Enzojr:BAAANQAECgMIBAAAAA==.',
Er='Eriath:BAABNQAECn9IAAIIAAoKhh1wDgAJAwAIAAoKhh1wDgAJAwAAAA==.',
Ev='Evè:BAAANQABCgEIAQAAAA==.',
Ex='Exalted:BAAANQAECgUICwABNQAFFAYIEwAfAKAaAA==.',
Ey='Eye:BAABNQAECn8bAAMLAAoKphbgNACkAgALAAkKUxjgNACkAgAUAAEKDQiP/QAvAAAAAA==.',
Fa='Faranth:BAABNQAECn9PAAQXAAoK+BioBQBgAgAXAAoK+BioBQBgAgAiAAQKng0DFACgAAAfAAEKoAmuOwAyAAAAAA==.',
Fe='Feld:BAABNQAECn8WAAIYAAoK6wNqzQAXAQAYAAoK6wNqzQAXAQAAAA==.Felynne:BAAANQAECggIAwAAAA==.Feo:BAABNQAECn8hAAIRAAkKfBp0HgBdAgARAAkKfBp0HgBdAgAAAA==.Feru:BAAANQAECgUIBQAAAA==.Ferum:BAABNQAECn9QAAIWAAoKuSXhAgDgAwAWAAoKuSXhAgDgAwAAAA==.',
Fi='Fionnan:BAABNQAECn83AAIjAAoK4BEpIACCAQAjAAoK4BEpIACCAQABNQAECgoKTwAUAFAJAA==.Fizwidget:BAAANQADCgEIAQAAAA==.',
Fr='Freezia:BAAANQAECgYICgAAAA==.Frostigan:BAAANQAECgcIDAABNQAECgkJIQAkAKQPAA==.Fryeguy:BAAANQADCgQIBAAAAA==.',
Fu='Fudo:BAAANQAECgIIAQAAAA==.Fudoswrath:BAAANQAECggIDQAAAA==.Funkysoup:BAAANQAECgUICwAAAA==.',
['Fò']='Fòrced:BAAANQADCgYIEAAAAA==.',
Ga='Gallium:BAAANQAECgMIAgAAAA==.',
Ge='Gehena:BAAANQAECgQIBAABNQAECgoKRgAYACUkAQ==.Gemsareyum:BAAANQADCgIIAgABNQAFFAcIJAAYAMsgAA==.',
Gi='Girthquake:BAABNQAECn8cAAILAAgKXw1mhgABAQALAAgKXw1mhgABAQAAAA==.',
Gl='Glow:BAAANQADCggJCAAAAA==.',
Go='Goof:BAABNQAECn81AAIkAAoKQwj1gwCPAQAkAAoKQwj1gwCPAQAAAA==.Goontaa:BAAANQAECgQIAQAAAA==.',
Gr='Griz:BAAANQAECggIDgAAAA==.Grizzly:BAAANQAECgYIBwABNQAECggIDgATAAAAAA==.Grossevache:BAAANQADCgIIBAAAAA==.',
Ha='Haddor:BAABNQAECn82AAIlAAoKzhFRGAC1AQAlAAoKzhFRGAC1AQAAAA==.Halfheart:BAAANQAECgUICwAAAA==.Hankerin:BAAANQAECgEIAQAAAA==.Harborhate:BAAANQAECggIAgAAAA==.Harmoni:BAAANQAECgIIBQAAAA==.Harpomage:BAAANQADCggIEwAAAA==.Haunter:BAABNQAECn8lAAQEAAoKFR5nOABEAgAEAAkKUCBnOABEAgADAAcKaxd4QwC2AQAMAAYKjQ/AZwCsAAAAAA==.',
He='Heimdallr:BAAANQADCggIEAAAAA==.Heisenborg:BAAANQAECgQIBAAAAA==.Helldin:BAAANQAECgEIAQAAAA==.Henryrollinz:BAAANQADCgcIBwAAAA==.',
Hi='Hidden:BAAANQAECgEIAQABNQAFFAYIEwAfAKAaAA==.Hilite:BAAANQAECgQICAAAAA==.Himothyjr:BAAANQADCgcICgAAAA==.',
Ho='Holific:BAABNQAECn9NAAIPAAoKnhi5RABcAgAPAAoKnhi5RABcAgAAAA==.Holymommy:BAAANQAECgYIEQABNQAECgoKJQAPAOkcAA==.Hoss:BAAANQAECggIDQAAAA==.Hotrodranger:BAABNQAECn9AAAIYAAkKBSD5RgBDAgAYAAkKBSD5RgBDAgAAAA==.',
Hs='Hshyomouth:BAAANQADCgIIAgABNQAECgkJQAAYAAUgAA==.',
Hu='Hunters:BAAANQADCgYIBgAAAA==.Hut:BAACNQAFFH8ZAAIHAAgKBxZXCAD+AQAHAAgKBxZXCAD+AQA1AAQKf1oAAgcACgqSJZkCAGcDAAcACgqSJZkCAGcDAAAA.',
Hy='Hypearione:BAAANQABCgEIAQAAAA==.',
Ia='Iambohike:BAAANQAECgIIAgAAAA==.',
Ic='Icycritties:BAABNQAECn80AAQGAAoKSg6SDQC/AQAGAAoKSg6SDQC/AQAFAAcKnwZ+3gDwAAAhAAEKPQOIDwAiAAAAAA==.',
Ih='Iheals:BAAANQADCgIIAgAAAA==.',
Im='Imjustadruid:BAAANQADCgIIAgAAAA==.Immortal:BAABNQAECn83AAIEAAoKQxNsHwDlAQAEAAoKQxNsHwDlAQAAAA==.',
In='Incarnated:BAABNQAECn8bAAMEAAoK3CFmDQBOAwAEAAoK3CFmDQBOAwADAAYKiRjAUABTAQAAAA==.',
Ir='Irís:BAAANQAECggIEwAAAA==.',
Is='Iskra:BAAANQADCgIIAgAAAA==.Ispithotfire:BAAANQABCgQIBgAAAA==.',
Iu='Iu:BAAANQAECggIEQAAAA==.',
Ja='Jackfash:BAAANQADCgMIBQAAAA==.Jadecross:BAAANQADCgIIAgAAAA==.Jailbaitt:BAAANQAECgQIBAAAAA==.Javan:BAAANQADCgIIAgAAAA==.',
Je='Jerryatric:BAABNQAECn8jAAIPAAcKDQ1q5ABSAQAPAAcKDQ1q5ABSAQAAAA==.',
Ji='Jiri:BAAANQABCgcIDwAAAA==.',
Jk='Jkmno:BAAANQADCgMIAwABNQADCgUIBQATAAAAAA==.',
Jo='Joeyrains:BAAANQADCgQIBAAAAA==.',
Ju='Justblaze:BAAANQAECgQIBAAAAA==.Justincasê:BAAANQADCgIIAgAAAA==.',
Ka='Kallikan:BAABNQAECn8zAAIjAAgKdhQ0IwBpAQAjAAgKdhQ0IwBpAQAAAA==.Kamidk:BAABNQAECn8YAAMMAAkKVCAvCwDeAgAMAAkKVCAvCwDeAgAEAAMK9RKBTgDKAAAAAA==.Kamuri:BAAANQAECgMIAwAAAA==.Kasteen:BAAANQAECgEIAQAAAA==.Katia:BAABNQAECn8WAAIPAAUKfQZgMQHQAAAPAAUKfQZgMQHQAAAAAA==.Kaøs:BAAANQAECgEIAgAAAA==.',
Kd='Kdoggparker:BAAANQABCgYICQAAAA==.',
Ke='Kelvox:BAAANQAECgQIBAAAAA==.Kementari:BAABNQAECn8nAAIHAAkK/gWySQD7AAAHAAkK/gWySQD7AAAAAA==.Kenzaki:BAABNQAECn8qAAIPAAgKiBVRkwD9AQAPAAgKiBVRkwD9AQAAAA==.',
Kh='Khaladin:BAAANQADCgYICAAAAA==.Khaosreborn:BAAANQADCgUIAQAAAA==.Khaotic:BAAANQAECgQIBAAAAA==.',
Ki='Kilaaz:BAABNQAECn8oAAIPAAoKHCL6NgCJAgAPAAoKHCL6NgCJAgAAAA==.Kilossus:BAAANQAECgUICQAAAA==.Kirveka:BAAANQABCgQIBAAAAA==.',
Kl='Kliticaldk:BAAANQAECgIIBAAAAA==.Kliticalwar:BAABNQAECn8bAAIaAAoK7A9ZjgD4AQAaAAoK7A9ZjgD4AQAAAA==.Klothys:BAABNQAECn8lAAIPAAoKAx3iXQB/AgAPAAoKAx3iXQB/AgAAAA==.',
Kn='Knuts:BAAANQADCgMJAwABNQAECgYICQATAAAAAA==.',
Ko='Koitsvo:BAAANQAECgUICgAAAA==.Ková:BAAANQADCgUJCwAAAA==.',
Ku='Kuani:BAAANQAECgQIBAABNQAECgoKSQAOACsgAA==.',
La='Landre:BAAANQADCgQIBgAAAA==.Lassy:BAAANQADCgIJAgAAAA==.Lathray:BAABNQAECn8eAAMWAAkK6ApvMQBlAQAWAAkK6ApvMQBlAQAHAAEKAAApxQAdAAAAAA==.Lazerislong:BAAANQAECgEIAQAAAA==.Lazerous:BAAANQAECgMIAwAAAA==.Lazur:BAAANQAECgMIAwAAAA==.',
Le='Lealoo:BAABNQAECn8tAAIPAAoKWBPGkQABAgAPAAoKWBPGkQABAgABNQAECgoKOQASAOMTAA==.Leftfield:BAAANQAECgIIAgABNQAECgoKMwAQAEUOAA==.Legolard:BAABNQAECn8fAAMeAAgKpRp0EQAPAgAeAAcKZh90EQAPAgAaAAMKiwecMwFtAAAAAA==.Leleia:BAABNQAECn8cAAIIAAkKVwpGJQBaAQAIAAkKVwpGJQBaAQAAAA==.',
Lh='Lhera:BAABNQAECn8mAAMmAAoKvR9yDACpAgAmAAoKvR9yDACpAgAUAAcKMRR/eACiAQABNQAECgoKMgAcAGEfAA==.',
Li='Liath:BAABNQAECn8kAAIJAAgK2hP6XgDEAQAJAAgK2hP6XgDEAQAAAA==.Lichtenberg:BAABNQAECn9LAAMLAAoKGCE6DgD8AgALAAoKGCE6DgD8AgAUAAUKxwjL1AC9AAAAAA==.Linddori:BAABNQAECn8ZAAIPAAoKdAxYugBdAQAPAAoKdAxYugBdAQABNQAECgoKMgACALEWAA==.Lirillia:BAABNQAECn8yAAQCAAoKsRY5CgBTAgACAAkKnRc5CgBTAgAQAAkK3wy6swDsAAAnAAEKAACoMAA0AAAAAA==.Lizzie:BAAANQADCgUIBQAAAA==.',
Lo='Locdon:BAAANQABCgIIAgABNQAECgUICAATAAAAAA==.Lodestone:BAAANQAECgQIBwAAAA==.Loena:BAABNQAECn8XAAMkAAoK7AxtXQCjAQAkAAkK1AttXQCjAQAPAAIKEwFy1gEAAAAAAA==.Lokk:BAAANQAECgIIAgABNQAECggIJAAYAOIaAA==.Loko:BAAANQAECgEIAQAAAA==.Lolowbeatz:BAAANQADCgUICwAAAA==.Lovelydread:BAAANQAECgEIAQAAAA==.',
Lu='Lunabug:BAAANQAECgIIAgAAAA==.Lupinos:BAAANQADCgIIAQAAAA==.',
Ly='Lyadra:BAABNQAECn8vAAIJAAoKWx4EMwB1AgAJAAoKWx4EMwB1AgAAAA==.Lyrissa:BAAANQADCgYIBgAAAA==.',
['Lõ']='Lõst:BAAANQAECgIIAwAAAA==.',
Ma='Mackito:BAABNQAFFH8QAAIYAAkK6wGUJgCEAAAYAAkK6wGUJgCEAAAAAA==.Madan:BAABNQAECn8jAAIEAAkKiggvNwA/AQAEAAkKiggvNwA/AQAAAA==.Mahoushojou:BAAANQAECgIIAgABNQAECgkJIQAkAKQPAA==.Malasminna:BAAANQAECgYIEgAAAA==.Malehorelock:BAAANQAECgEIAQAAAA==.Malicioun:BAAANQABCggIFgAAAA==.Malkariss:BAABNQAECn8zAAMFAAoKCBcBagDfAQAFAAkKthYBagDfAQAGAAUKBhfYGwARAQAAAA==.Mammadruid:BAABNQAECn8wAAIjAAkKuwzaKwAuAQAjAAkKuwzaKwAuAQAAAA==.Mauldis:BAABNQAECn8tAAMLAAgKhAYBggAMAQALAAgKhAYBggAMAQAUAAUKtQI07QCRAAAAAA==.',
Me='Meryl:BAABNQAECn8wAAIkAAkKYxi2PAByAgAkAAkKYxi2PAByAgAAAA==.',
Mi='Miaka:BAABNQAECn9EAAInAAoKRRqgAwC4AgAnAAoKRRqgAwC4AgAAAA==.Minigoonta:BAAANQAECgcIBwAAAA==.Minth:BAAANQADCgcIDQABNQAECgkJIQAkAKQPAA==.Miraakle:BAAANQAECgQIBwABNQAECgkJIQAkAKQPAA==.Misfire:BAABNQAECn82AAIYAAoKoBBweAAeAgAYAAoKoBBweAAeAgAAAA==.Mithra:BAAANQAECgQICQAAAA==.',
Mo='Moghroth:BAABNQAECn9GAAMHAAoK/gyJLwCKAQAHAAoKzguJLwCKAQAjAAMKtwoCXwBVAAAAAA==.Molykote:BAAANQAECggIDAAAAA==.Monks:BAAANQADCgQIBAAAAA==.Monsterbabe:BAAANQADCgUICgAAAA==.Moreleath:BAAANQADCgMIBAAAAA==.Morphias:BAAANQADCgQIBAAAAA==.Mowiewowie:BAAANQABCgIIAgAAAA==.',
Mu='Mugzypatron:BAAANQADCggIIwAAAA==.Murdrmitts:BAABNQAECn8bAAIjAAcKmwsrKgBGAQAjAAcKmwsrKgBGAQAAAA==.',
['Mâ']='Mâsterdon:BAAANQAECgcIBwAAAA==.',
['Mã']='Mãtador:BAACNQAFFH8IAAILAAYKwxXnEABdAQALAAYKwxXnEABdAQA1AAQKfy0AAwsACQpmIxAgAAsDAAsACQpmIxAgAAsDABQAAwo3EJv6AHUAAAAA.',
['Mä']='Mätadør:BAABNQAECn8UAAIIAAgKFxs2IgAjAgAIAAgKFxs2IgAjAgABNQAFFAYICAALAMMVAA==.',
['Mì']='Mìasma:BAAANQAECgIIAgAAAA==.',
Na='Nahryn:BAABNQAECn80AAIWAAoK2BlkFgBsAgAWAAoK2BlkFgBsAgAAAA==.',
Ne='Nedina:BAAANQADCgUIBQAAAA==.Nerbert:BAAANQADCgYJBgABNQAECgoKNgAXAFESAA==.Neretsym:BAABNQAECn82AAIYAAoKfA+OaQDwAQAYAAoKfA+OaQDwAQAAAA==.',
Ni='Nineva:BAABNQAECn8cAAIWAAgKYQaYQQACAQAWAAgKYQaYQQACAQAAAA==.',
No='Nobas:BAABNQAECn9PAAIHAAoKeAz6KwCiAQAHAAoKeAz6KwCiAQAAAA==.Nonoa:BAAANQAECgEIAgAAAA==.',
Oc='Octavien:BAAANQADCgIIAgAAAA==.',
Og='Ogr:BAAANQADCgMIAwAAAA==.',
On='Onlyfeet:BAABNQAECn8lAAIPAAoK6RzTPwBrAgAPAAoK6RzTPwBrAgAAAA==.',
Op='Oppgjør:BAAANQAECgEIAQAAAA==.',
Or='Oreeree:BAAANQAECgQIDgAAAA==.Ormr:BAABNQAECn82AAMXAAoKURIPEQBEAgAXAAoKURIPEQBEAgAiAAEKAABPIwA5AAAAAA==.',
Os='Osteo:BAABNQAECn8tAAMCAAkKRQajJwA7AQAQAAkKCAbMxQA/AQACAAcK2wSjJwA7AQAAAA==.Osteoprime:BAAANQADCgUJBQAAAA==.',
Ou='Ouron:BAABNQAECn8uAAMUAAoKzBbmPQBoAgAUAAoKzBbmPQBoAgALAAEKAADZIwEAAAAAAA==.Outofmana:BAAANQAECgQIDQAAAA==.',
Ov='Ovelia:BAAANQAECgYIBQAAAA==.',
Pa='Pagoda:BAAANQADCgYIBgAAAA==.Papashrimps:BAACNQAFFH8QAAMFAAUKKxTgKQA8AQAFAAQKKxTgKQA8AQAGAAEKAAB7GQAAAAA1AAQKfyYAAwUACgqHGISWAFMCAAUACgqXF4SWAFMCAAYAAQoxGmQ/AEYAAAAA.',
Pe='Percy:BAAANQADCggIGQAAAA==.',
Ph='Phatcow:BAAANQADCgEIAQAAAA==.',
Pl='Placeholder:BAABNQAECn9HAAMlAAoKpyN9AwA3AwAlAAoKpyN9AwA3AwAPAAEKZQ4ZiwE9AAAAAA==.',
Po='Pojoevokest:BAABNQAECn8nAAIfAAgKUgr1HwAOAQAfAAgKUgr1HwAOAQAAAA==.Pontifex:BAABNQAECn8vAAIJAAoKDhUKWQAXAgAJAAoKDhUKWQAXAgAAAA==.Portandmorph:BAABNQAECn8jAAIGAAoK8xOWCwAHAgAGAAoK8xOWCwAHAgAAAA==.',
Pr='Praxx:BAAANQAECggICAABNQAECgoKNgAXAFESAA==.Priests:BAAANQADCgQIBgAAAA==.Prone:BAABNQAECn9PAAMUAAoKUAlJbABvAQAUAAoKUAlJbABvAQALAAYKFQallADgAAAAAA==.Protarada:BAAANQAECgcICwAAAA==.',
Qu='Quietmind:BAABNQAECn8VAAIPAAoKwwU6/wAhAQAPAAoKwwU6/wAhAQAAAA==.',
Ra='Raakotah:BAABNQAECn9CAAIHAAoKJiX8CgDwAgAHAAoKJiX8CgDwAgAAAA==.Raasclaat:BAAANQADCgcIDQAAAA==.Raelo:BAABNQAECn9EAAImAAoKxw90EAAOAgAmAAoKxw90EAAOAgAAAA==.Rainbowflake:BAABNQAECn8VAAIYAAcK3wIbAgEBAQAYAAcK3wIbAgEBAQAAAA==.Raiseurmug:BAABNQAECn8/AAIdAAoKERECCwCMAQAdAAoKERECCwCMAQAAAA==.Rakash:BAAANQADCgcIBwAAAA==.Rarg:BAABNQAECn8VAAMMAAgKlRnWSgDMAQAMAAgKlRnWSgDMAQAEAAEK6QLn8gAkAAAAAA==.Ravia:BAAANQAFFAEIAQAAAA==.Rayjr:BAAANQAECggIDgAAAA==.',
Re='Rendysavage:BAAANQAECgYJBgAAAA==.Resco:BAAANQADCggIEgAAAA==.',
Ri='Riddle:BAABNQAECn8xAAIUAAoKZguShwB3AQAUAAoKZguShwB3AQAAAA==.Rimeouo:BAAANQAFFAEIAQAAAA==.Rize:BAABNQAECn8aAAIaAAgK/w++mgDaAQAaAAgK/w++mgDaAQABNQAECgoKNAAXAGYPAA==.Rizmthetizm:BAAANQADCgEIAQAAAA==.',
Ro='Rosenrott:BAABNQAECn9GAAIYAAoKJSQTCwA0AwAYAAoKJSQTCwA0AwAAAA==.Rosepiercer:BAABNQAECn83AAIYAAoKMiT/CwAtAwAYAAoKMiT/CwAtAwAAAA==.Rouz:BAABNQAECn8bAAIXAAcKhgkXFQDkAAAXAAcKhgkXFQDkAAAAAA==.',
Ru='Ruddybear:BAAANQADCgIJAgAAAA==.',
Ry='Ryoto:BAAANQAECgUICAAAAA==.',
Sa='Sadarasdeath:BAAANQAECgUIDAAAAA==.Samandean:BAABNQAECn85AAISAAoK4xMrIAAJAgASAAoK4xMrIAAJAgAAAA==.Sarasvati:BAAANQAECgMIAwAAAA==.Sariia:BAAANQAECggIDwAAAA==.',
Se='Sellena:BAABNQAECn81AAImAAoK2BgsCgB7AgAmAAoK2BgsCgB7AgABNQAECgoKOQASAOMTAA==.',
Sh='Shakenn:BAAANQADCgEIAQAAAA==.Shandow:BAABNQAECn9YAAIGAAoKFyXdAABZAwAGAAoKFyXdAABZAwAAAA==.Shansoracle:BAABNQAECn82AAMJAAoKeCAEDQB4AwAJAAoKeCAEDQB4AwAIAAEKaAP7ggAmAAABNQAECgoKWAAGABclAA==.Shed:BAAANQAECgQIBAABNQAFFAgIGQAHAAcWAA==.Sheislegend:BAAANQADCggIFgAAAA==.Shelby:BAABNQAECn82AAIJAAoKmB5sPABJAgAJAAoKmB5sPABJAgAAAA==.Shocked:BAAANQAECggIAwABNQAECggIDAATAAAAAA==.Shockolate:BAABNQAECn8WAAILAAoKdgeqXQBuAQALAAoKdgeqXQBuAQAAAA==.Shoog:BAAANQADCgUIBQAAAA==.Shrimpbottom:BAAANQAFFAIIAgAAAA==.',
Si='Siarn:BAAANQADCgMIBQAAAA==.Siccinok:BAABNQAECn9DAAMFAAoKpBvnNgBpAgAFAAoKpBvnNgBpAgAGAAQKwx2kIADkAAAAAA==.Sink:BAAANQAECgQIBAAAAA==.Sixhundrdlbs:BAACNQAFFH8OAAIRAAQKUh2aBwDpAAARAAQKUh2aBwDpAAA1AAQKf0AAAxEACgreJLADAJ0DABEACgreJLADAJ0DABIAAQqYCrOIAC4AAAE1AAQKCgobAAQA3CEA.',
Sk='Skraps:BAAANQADCgEJAQAAAA==.',
Sl='Slimped:BAAANQADCgYICwAAAA==.',
Sn='Sneakybato:BAAANQADCggIFwAAAA==.',
So='Sofie:BAAANQADCgQIBAABNQAECgoKSwALABghAA==.Solarial:BAAANQAECgUIEQAAAA==.Solastra:BAABNQAECn89AAIkAAoK0xMVMwBSAgAkAAoK0xMVMwBSAgAAAA==.Soramai:BAAANQAECgQIBwAAAA==.Soth:BAABNQAECn9GAAMEAAoK0xbVGgAPAgAEAAoK0xbVGgAPAgAMAAkK0BByVgCaAQAAAA==.',
Sp='Sparký:BAABNQAECn8nAAIQAAoK9iSgBwAxAwAQAAoK9iSgBwAxAwAAAA==.Spinnycrisp:BAAANQADCgYIBgAAAA==.',
St='Starlyvana:BAACNQAFFH8QAAMGAAYKhQ5gAQA8AQAGAAUKhQ5gAQA8AQAFAAIKlwcuUgAAAAA1AAQKfxoAAwYACgprFssHAG8CAAYACgprFssHAG8CAAUAAQrEGKxFAUkAAAAA.Staryxia:BAABNQAECn8XAAIDAAkKSh1KNgD/AQADAAkKSh1KNgD/AQAAAA==.Statiic:BAAANQABCgIIBQAAAA==.Steamdruid:BAAANQADCggIDwABNQAECgoKTQASAH8eAA==.Steephany:BAAANQADCgMIBwAAAA==.Stonecross:BAABNQAECn8mAAIJAAkKDxuGOgB/AgAJAAkKDxuGOgB/AgAAAA==.Stoneldo:BAAANQAECgUIBQAAAA==.Stormbolt:BAABNQAECn9BAAIHAAoKQw2LKwClAQAHAAoKQw2LKwClAQAAAA==.Stormspirit:BAAANQADCggIHQAAAA==.Striggen:BAABNQAECn8WAAMPAAUKYxT7BQEVAQAPAAUKLxT7BQEVAQAlAAMKuA5/VgCHAAAAAA==.',
Su='Sugarsham:BAABNQAECn8kAAILAAoKpAvJcgDIAQALAAoKpAvJcgDIAQAAAA==.Sulwen:BAACNQAFFH8aAAIHAAkKBSRnAQDwAgAHAAkKBSRnAQDwAgA1AAQKfzkAAgcACgryJlgAAJcDAAcACgryJlgAAJcDAAAA.Sumerset:BAABNQAECn8cAAIPAAoKjA+0iQC4AQAPAAoKjA+0iQC4AQAAAA==.Sundave:BAAANQAECgEJAgAAAA==.Supaflytnt:BAABNQAECn82AAIVAAkKBhvLCABfAgAVAAkKBhvLCABfAgAAAA==.Sustia:BAAANQAECgUICwAAAA==.',
Ta='Taera:BAABNQAECn9JAAIOAAoKKyDgAwCFAwAOAAoKKyDgAwCFAwAAAA==.Talavenn:BAABNQAECn8kAAIRAAkK0B2uEQDgAgARAAkK0B2uEQDgAgAAAA==.Tanglock:BAABNQAECn8ZAAMQAAgKLgoLiwBHAQAQAAgKLgoLiwBHAQAnAAMKgARiJgBRAAAAAA==.Tarage:BAAANQAECgUIDAAAAA==.Taurîel:BAAANQADCgYIBgAAAA==.',
Te='Tectoniiks:BAAANQAECgcIBwAAAA==.Tedds:BAAANQAECgUICAAAAA==.Teds:BAAANQADCgYICwAAAA==.Tempus:BAAANQAECgMJAwAAAA==.Teriko:BAABNQAECn8vAAIDAAoKYxgVLQA3AgADAAoKYxgVLQA3AgAAAA==.Teviro:BAAANQADCgIIAgABNQAECgoKMgAcAGEfAA==.',
Th='Thequixote:BAABNQAECn8iAAIVAAcKbxa5EwCQAQAVAAcKbxa5EwCQAQAAAA==.',
Ti='Tictok:BAAANQADCgYICgAAAA==.Tinytotems:BAAANQADCgQIBAAAAA==.',
To='Toaderic:BAAANQAECgUIDwAAAA==.Toemama:BAAANQAECgEIAgABNQAECgoKJQAPAOkcAA==.Tots:BAACNQAFFH8FAAIjAAQKjwq9BQCfAAAjAAQKjwq9BQCfAAA1AAQKf0QAAiMACgqKHc4LAHwCACMACgqKHc4LAHwCAAAA.Toxictotes:BAAANQADCgYICQAAAA==.',
Tr='Trazah:BAAANQADCgEIAQAAAA==.',
Ty='Tyraèl:BAABNQAECn8lAAIkAAoKGyMBCACJAwAkAAoKGyMBCACJAwAAAA==.Tyzy:BAACNQAFFH8WAAMWAAQK4iEEBwCFAQAWAAQK4iEEBwCFAQAHAAQK8CO+DgATAQA1AAQKfysAAwcACgrvI/YNAFsDAAcACgrvI/YNAFsDABYACQowHZkXAIQCAAAA.',
Um='Umber:BAAANQADCggICAAAAA==.',
Va='Valenora:BAABNQAECn9BAAMCAAoKvRvvAQCEAgACAAoKvRvvAQCEAgAQAAEKDwryFgE3AAAAAA==.Valvitor:BAAANQADCgEIAQAAAA==.Varuz:BAABNQAECn8kAAIYAAgK4hpIQACqAgAYAAgK4hpIQACqAgAAAA==.Varyz:BAAANQADCgIIAgABNQAECggIJAAYAOIaAA==.',
Ve='Velanie:BAAANQAECgEIAQAAAA==.Veloon:BAABNQAECn8bAAIHAAkKIg7hQgDqAQAHAAkKIg7hQgDqAQAAAA==.Veloras:BAAANQAECggICgAAAA==.Verinari:BAAANQAECgYIDAAAAA==.',
Vi='Vipul:BAAANQADCgUIDQABNQADCgYIBwATAAAAAA==.Viridria:BAABNQAECn8hAAMkAAkKpA90XwCcAQAkAAkKpA90XwCcAQAPAAIKZwm6rwEkAAAAAA==.Vityazi:BAABNQAECn8eAAIPAAkKYQSKGQHDAAAPAAkKYQSKGQHDAAAAAA==.',
Vo='Voodoobootie:BAAANQABCgcJBwAAAA==.',
Vy='Vy:BAAANQADCgUICQAAAA==.',
['Vè']='Vè:BAABNQAECn8pAAIjAAkKqxAbGgDWAQAjAAkKqxAbGgDWAQAAAA==.',
Wa='Warriors:BAABNQAECn9IAAIaAAoKDiNqFwBbAwAaAAoKDiNqFwBbAwAAAA==.Wartooth:BAABNQAECn86AAMQAAoKfhVhUgDdAQAQAAoKHA9hUgDdAQACAAUKxhgvKQAxAQAAAA==.Wassergott:BAAANQAECgEIAQAAAA==.',
We='Webicus:BAABNQAECn8gAAQaAAoKqAlRsQAXAQAaAAkKYwpRsQAXAQAZAAMKfQYoLQBUAAAeAAEKjQSNSgAnAAAAAA==.Weebster:BAAANQAECgMIAwAAAA==.Wendee:BAABNQAECn83AAMJAAoKkAWHcwCAAQAJAAoKkAWHcwCAAQAIAAMKHAheVQBXAAAAAA==.',
Wh='Whitefóx:BAABNQAECn8gAAQlAAoKvwwlHgB+AQAlAAoKvwwlHgB+AQAPAAcKzQLHMwGfAAAkAAEKlQNyBwElAAABNQAECgoKWAAGABclAA==.Whitley:BAABNQAECn8+AAMUAAoKryCzEwAaAwAUAAoKryCzEwAaAwALAAcKkBThbgDTAQAAAA==.',
Wi='Wildspart:BAABNQAECn8YAAMoAAoKIBfbBgDEAQAoAAoKMBbbBgDEAQAYAAIKxhYeKwGaAAAAAA==.',
Wo='Wooden:BAABNQAECn85AAIYAAoKWBjtPwBWAgAYAAoKWBjtPwBWAgAAAA==.',
Xa='Xaphy:BAABNQAECn8sAAMJAAoKSxodOQBYAgAJAAkKOxwdOQBYAgAIAAoKEQ8GGQDZAQAAAA==.Xardots:BAABNQAECn8aAAICAAcKthN8EgDhAQACAAcKthN8EgDhAQABNQAECggIPgATAAAAAA==.',
Xi='Xiareth:BAABNQAECn80AAIfAAoKsA0wFAC1AQAfAAoKsA0wFAC1AQAAAA==.',
Xy='Xyleiah:BAAANQADCgYIBgABNQAECgoKTwAXAPgYAA==.',
['Xá']='Xároth:BAAANQAECggIPgAAAQ==.',
Ya='Yaddi:BAAANQAECgQIAwAAAA==.Yargue:BAABNQAECn9EAAIIAAoKyx2ACQDJAgAIAAoKyx2ACQDJAgAAAA==.',
Ye='Yeeyee:BAAANQAECggIDAAAAA==.',
Yi='Yirï:BAAANQABCgQIBgAAAA==.',
Yo='Yorgue:BAAANQAECggIAgABNQAECgoKRAAIAMsdAA==.Youngjeezy:BAABNQAECn8gAAMEAAYKOQY+YwCAAAAEAAYKOQY+YwCAAAADAAIKZQNPwgAdAAAAAA==.Yoursinpride:BAAANQAECggIDgAAAA==.',
Za='Zackor:BAAANQADCgUIDAAAAA==.',
Ze='Ze:BAAANQADCgYICgAAAA==.Zervann:BAAANQADCgYIBgAAAA==.',
Zi='Ziska:BAAANQADCgIIAgAAAA==.',
Zo='Zorithic:BAAANQAECgIJAwAAAA==.',
Zy='Zyde:BAAANQAECgUIBAABNQAECggIJAAYAOIaAA==.',
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
