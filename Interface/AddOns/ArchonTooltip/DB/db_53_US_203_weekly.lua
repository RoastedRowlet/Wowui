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
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aanuanaela:BAABNQAECn8oAAIBAAkKzhEwAwCUAQABAAkKzhEwAwCUAQAAAA==.Aanubis:BAAANQAECgMIAwAAAA==.',
Ab='Absens:BAABNQAECn83AAICAAoKsw1/BQBkAQACAAoKsw1/BQBkAQAAAA==.Abumim:BAAANQAECgQIBAAAAA==.',
Ad='Adorian:BAAANQAECgQIBAABNQAECgoKMwADAO0gAA==.Adwillon:BAAANQAECgQIAwAAAA==.',
Af='Aforceofone:BAAANQAECgcIDQAAAA==.',
Ag='Aggretsuko:BAABNQAECn8uAAMEAAoKjxa0QAAaAgAEAAgKGhm0QAAaAgADAAkKHAvOTgB5AQAAAA==.',
Al='Aldonza:BAAANQADCgIIAgAAAA==.Alex:BAAANQAECgUIDgAAAA==.Alivanllan:BAAANQAECgQIBQAAAA==.Aluviel:BAACNQAFFH8KAAMFAAMKdhx9LgAdAQAFAAMKdhx9LgAdAQAGAAEKAQwdEwBIAAA1AAQKfxwAAwUACQo3JYsiAFIDAAUACQo3JYsiAFIDAAYAAQoNISUrAF8AAAE1AAUUCAgYAAcA0SQA.Alyslia:BAAANQADCgEIAQAAAA==.',
An='Anamuht:BAABNQAECn8zAAQIAAkKHxWZLgCwAQAIAAgKDxOZLgCwAQAJAAgKzQ2KeAA0AQAKAAMKEgcpHQB6AAABNQAECgoKOQALAHodAA==.Angeli:BAAANQAECgEIAQAAAA==.Annaday:BAABNQAECn8fAAIMAAgKPRCNOgAvAQAMAAgKPRCNOgAvAQAAAA==.Antiock:BAABNQAECn8zAAQDAAoK7SA8EQAFAwADAAoKEx08EQAFAwAMAAcKzyLrLwBSAgAEAAcKnxksQwAOAgAAAA==.Anyamonka:BAAANQAECgcIEgAAAA==.',
Ap='Appalachia:BAAANQADCgYJBgAAAA==.',
Ar='Ariea:BAAANQADCgEIAQAAAA==.Arraven:BAAANQADCggIBwAAAA==.Arrowmir:BAAANQADCgEIAQAAAA==.Artto:BAAANQADCgIIAwAAAA==.',
As='Ashbrínger:BAABNQAECn9EAAINAAoKsSNHFAD9AgANAAoKsSNHFAD9AgAAAA==.Association:BAAANQAECgEIAQABNQAECgkJKgAOAOwHAA==.',
At='Atua:BAAANQAECgIIAwAAAA==.',
Au='Aurah:BAAANQAECgEIAQAAAA==.',
Av='Averax:BAABNQAECn8wAAMPAAkKbCFrDwD5AgAPAAkKbCFrDwD5AgAQAAEKAAB3jQBBAAAAAA==.Avylbrew:BAAANQADCgcICgABNQAECgIIAgARAAAAAA==.',
Ay='Aylakaye:BAAANQADCggICQAAAA==.',
Az='Azzathoth:BAAANQADCggICAAAAA==.',
Ba='Babybilly:BAABNQAECn8lAAMLAAoKoh7dHwBFAgALAAkKzR7dHwBFAgASAAYKgR1hSAC+AQAAAA==.Babyshoes:BAAANQAECgQIBwAAAA==.Backpack:BAAANQAECgcIDQAAAA==.Bananawaffle:BAAANQADCgEIAQAAAA==.Bandan:BAABNQAECn8XAAIIAAkKwRo0GgCMAQAIAAkKwRo0GgCMAQAAAA==.Bato:BAAANQADCgUIDAAAAA==.',
Be='Beauvito:BAAANQADCgEIAQAAAA==.Beefjurkey:BAAANQAECgQICQAAAA==.Betch:BAAANQAECggIBQABNQAECggIDQARAAAAAA==.',
Bh='Bhalthazar:BAAANQADCgUICQABNQADCgYICAARAAAAAA==.',
Bi='Bier:BAAANQAECgQIBgAAAA==.Biggymcfinch:BAAANQADCgEIAQAAAA==.Bigrig:BAAANQAECgEIAQAAAA==.Bitterman:BAABNQAECn8qAAIOAAkK7AepqwB7AQAOAAkK7AepqwB7AQAAAA==.',
Bl='Blastin:BAAANQADCggIGQAAAA==.Blinkerfluid:BAAANQADCgEIAQAAAA==.Bloodveil:BAABNQAECn8UAAITAAcK2xj3EwA+AQATAAcK2xj3EwA+AQABNQAECgoKIwANAIgcAA==.Bluemonster:BAAANQADCgQIBAAAAA==.',
Bo='Bobviela:BAAANQAECgEIAQAAAA==.Bombsaway:BAAANQAECgEIAQABNQAECgEIAQARAAAAAA==.Boohoo:BAAANQADCgMIBAAAAA==.Bovinedivine:BAAANQADCgUIBgABNQAECggINQARAAAAAA==.',
Br='Braddock:BAAANQADCgEIAQAAAA==.Brandumb:BAAANQAECgYICgAAAA==.',
Ca='Callana:BAAANQAECgQICAAAAA==.Camedra:BAABNQAECn8vAAIUAAoKVyNzCQAuAwAUAAoKVyNzCQAuAwAAAA==.Carelessheal:BAAANQAECggICAAAAA==.Carthella:BAAANQADCgQJBAABNQAECgoKNgAVAFESAA==.Catamynyia:BAABNQAECn8aAAIWAAcKkQx1pwC2AQAWAAcKkQx1pwC2AQAAAA==.',
Cc='Cchaos:BAAANQAECgMJAwAAAA==.',
Ce='Celaborn:BAABNQAECn8pAAMXAAgKURygCgClAQAXAAYK9hygCgClAQAYAAgKdxdlYwCcAQAAAA==.Celice:BAAANQADCgEIAQABNQAECgkJPgAZAK0fAA==.',
Ch='Chaotiiks:BAAANQADCgEIAQAAAA==.Chimaira:BAAANQADCgQIBAAAAA==.Chucknoris:BAAANQADCgcJEQAAAA==.Chump:BAAANQADCgEIAQAAAA==.',
Cl='Claytonbigse:BAAANQADCgEIAQAAAA==.',
Co='Colossus:BAAANQAECgUIBwABNQAECgcIEQARAAAAAA==.Colossuss:BAAANQAECgcIEQAAAA==.Commodious:BAAANQADCgcICgAAAA==.Conduction:BAAANQAECgQIBQAAAA==.',
Cr='Crankadin:BAAANQAECggIAQABNQADCggIEwARAAAAAA==.Crispyquinn:BAAANQADCgUIBQAAAA==.Crispysham:BAABNQAECn8cAAILAAkKhg/ZZwDpAQALAAkKhg/ZZwDpAQAAAA==.Cruciö:BAAANQADCggIDQAAAA==.Crànk:BAAANQADCggIEwAAAA==.Cránk:BAAANQAECggJCAABNQADCggIEwARAAAAAA==.Crãnk:BAABNQAECn8WAAMaAAkKtQw9dQDwAAAbAAUKzAriZwATAQAaAAkK3gk9dQDwAAABNQADCggIEwARAAAAAA==.',
Cu='Cullyeskie:BAABNQAECn8bAAIWAAcK8wJd7QCXAAAWAAcK8wJd7QCXAAAAAA==.Curveball:BAAANQAECgMIAwABNQAECgkJKgAOAOwHAA==.',
Cy='Cyniar:BAABNQAECn8rAAIHAAkK5Az6LABhAQAHAAkK5Az6LABhAQAAAA==.',
Da='Dabrick:BAAANQADCgEIAQAAAA==.Dahnu:BAAANQADCgIIAgABNQAECgYIHAAJAKITAA==.Damerlin:BAAANQADCgIIAgAAAA==.Darios:BAAANQADCgUIBgABNQAECgoKSQAPAM8jAA==.Darkhuntress:BAAANQADCgYIBgAAAA==.Darkstär:BAABNQAECn8+AAMMAAoKRRkXKQB5AgAMAAoKRRkXKQB5AgADAAEKIQopngA1AAAAAA==.Darkun:BAAANQADCggICAABNQAECgoKNAAVAGYPAA==.',
De='Deacon:BAABNQAECn8vAAIcAAgKiwc5EADvAAAcAAgKiwc5EADvAAAAAA==.Deadzly:BAABNQAECn83AAQMAAkKoSNsEAApAwAMAAgKsiNsEAApAwADAAgKZhY6PADdAQAEAAgKYhC6VQC7AQAAAA==.Deathknights:BAAANQADCgMIAwAAAA==.Deeanne:BAAANQAECgUIBwAAAA==.Deepfriar:BAABNQAECn8+AAIJAAoKnCUXDwBNAwAJAAoKnCUXDwBNAwAAAA==.Deltoro:BAAANQADCgIIAgAAAA==.Demoniiks:BAAANQADCgEIAQAAAA==.Demonmore:BAAANQADCgEIAQAAAA==.Derailed:BAABNQAECn8cAAIDAAkKnwvcRgA9AQADAAkKnwvcRgA9AQAAAA==.Deshal:BAAANQAECgUIBgAAAA==.Dethwing:BAAANQAECgEIAQAAAA==.Dewsbelle:BAAANQAECgUICwAAAA==.',
Dh='Dha:BAAANQADCgcIDgABNQAECggIHwAdAKUaAA==.',
Di='Diablognomis:BAAANQADCgcIDwAAAA==.Dirtman:BAABNQAECn80AAILAAoKtRbwKQADAgALAAoKtRbwKQADAgAAAA==.Distillate:BAAANQAECgEIAwAAAA==.',
Dk='Dkrise:BAAANQADCgIIAgABNQAECgoKNAAVAGYPAA==.',
Do='Dolphina:BAAANQAECgEIAQAAAA==.Donny:BAAANQAECgUICAAAAA==.',
Dr='Dragonic:BAACNQAFFH8TAAMeAAYKoBqaBgCoAQAeAAYKoBqaBgCoAQAVAAIKxwN2DQBwAAA1AAQKfzAAAx4ACgozHKsGAMkCAB4ACgozHKsGAMkCABUAAgp3DigzAHYAAAAA.Dreathlu:BAAANQADCgUIBgAAAA==.Drewdog:BAABNQAECn8eAAIWAAcKIA/fuACSAQAWAAcKIA/fuACSAQAAAA==.',
Dt='Dtat:BAAANQAECgEIAQAAAA==.',
Du='Dubes:BAABNQAECn88AAIGAAkKtxv7BgCIAgAGAAkKtxv7BgCIAgAAAA==.Dunbartian:BAABNQAECn8xAAIdAAkKcBZbCwDSAQAdAAkKcBZbCwDSAQAAAA==.Duration:BAAANQADCgEIAQAAAA==.',
Ea='Easybreezin:BAAANQAECgcIDQAAAA==.',
Ei='Eirote:BAABNQAECn89AAIfAAoK9REaAgC4AQAfAAoK9REaAgC4AQAAAA==.',
El='Elarris:BAAANQAECgQIBAAAAA==.Eldari:BAAANQAECgUIDwAAAA==.Eledron:BAAANQAECgQIBAAAAA==.Elyssaena:BAAANQAECgYIDQAAAA==.',
Em='Emotionaldmg:BAAANQAECgUIBQABNQAECggIDQARAAAAAA==.',
En='Enzojr:BAAANQAECgMIBAAAAA==.',
Er='Eriath:BAABNQAECn9IAAIIAAoKhh1wDgAJAwAIAAoKhh1wDgAJAwAAAA==.',
Ev='Evè:BAAANQADCgEIAQAAAA==.',
Ex='Exalted:BAAANQAECgUIDAABNQAFFAYIEwAeAKAaAA==.',
Ey='Eye:BAABNQAECn8bAAMLAAoKphbgNACkAgALAAkKUxjgNACkAgASAAEKDQjt5gAvAAAAAA==.',
Fa='Faranth:BAABNQAECn89AAQVAAoKQRfPEQA3AgAVAAkKjRfPEQA3AgAgAAQKng25EACkAAAeAAEKoAmCNAA0AAAAAA==.',
Fe='Feld:BAAANQAECgcIDgAAAA==.Felynne:BAAANQAECggIAwAAAA==.Feo:BAABNQAECn8fAAIPAAcKNx10HgBdAgAPAAcKNx10HgBdAgAAAA==.Feru:BAAANQAECgUIBQAAAA==.Ferum:BAABNQAECn9CAAIUAAoKVyW4AgDDAwAUAAoKVyW4AgDDAwAAAA==.',
Fi='Fionnan:BAABNQAECn80AAIhAAkKGxMgGwByAQAhAAkKGxMgGwByAQABNQAECgoKPQASAAUMAA==.Fizwidget:BAAANQADCgEIAQAAAA==.',
Fo='Fortuna:BAAANQAECgEIAQABNQAECgEIAQARAAAAAA==.',
Fr='Freezia:BAAANQAECgYICgAAAA==.Frostigan:BAAANQAECgcIDAABNQAECgkJIAAiAEQPAA==.Fryeguy:BAAANQADCgQIBAAAAA==.',
Fu='Fudo:BAAANQAECgIIAQAAAA==.Fudoswrath:BAAANQAECgcIDQAAAA==.Funkysoup:BAAANQAECgUICwAAAA==.',
['Fò']='Fòrced:BAAANQADCgYIEAAAAA==.',
Ga='Gallium:BAAANQAECgIJAgAAAA==.',
Ge='Gehena:BAAANQAECgQIBAABNQAECgkJOwAWAPgjAQ==.Gemsareyum:BAAANQADCgIIAgABNQAFFAcIJAAWAMsgAA==.',
Gi='Girthquake:BAABNQAECn8XAAILAAcK5QyfpwBFAQALAAcK5QyfpwBFAQAAAA==.',
Gl='Glow:BAAANQADCggJCAAAAA==.',
Go='Goof:BAABNQAECn8vAAIiAAoKwAetYgBdAQAiAAoKwAetYgBdAQAAAA==.Goontaa:BAAANQAECgQIAQAAAA==.',
Gr='Griz:BAAANQAECggIDgAAAA==.Grizzly:BAAANQAECgEIAQABNQAECggIDgARAAAAAA==.Grossevache:BAAANQADCgIIBAAAAA==.',
Ha='Haddor:BAABNQAECn8lAAIjAAgKZhN7HQBNAQAjAAgKZhN7HQBNAQAAAA==.Halfheart:BAAANQAECgUICwAAAA==.Hankerin:BAAANQAECgEIAwAAAA==.Harborhate:BAAANQAECgcIAgAAAA==.Harmoni:BAAANQAECgMIBgAAAA==.Harpomage:BAAANQADCggIEwAAAA==.Haunter:BAABNQAECn8lAAQEAAoKFR5nOABEAgAEAAkKUCBnOABEAgADAAcKaxd4QwC2AQAMAAYKjQ9TWgCyAAAAAA==.',
He='Heimdallr:BAAANQADCggIEgAAAA==.Heisenborg:BAAANQAECgQIBAAAAA==.Helldin:BAAANQAECgEIAwAAAA==.',
Hi='Hidden:BAAANQADCgMIAwABNQAFFAYIEwAeAKAaAA==.Hilite:BAAANQAECgQICAAAAA==.Himothyjr:BAAANQADCgcICgAAAA==.',
Ho='Holific:BAABNQAECn87AAINAAoKPxTCcACuAQANAAoKPxTCcACuAQAAAA==.Holymommy:BAAANQAECgUIEAABNQAECgoKIwANAIgcAA==.Hoss:BAAANQAECggIDQAAAA==.Hotrodranger:BAABNQAECn87AAIWAAkKBSDXLwBVAgAWAAkKBSDXLwBVAgAAAA==.',
Hs='Hshyomouth:BAAANQADCgIIAgABNQAECgkJOwAWAAUgAA==.',
Hu='Hunters:BAAANQADCgYIBwAAAA==.Hut:BAACNQAFFH8XAAIHAAcKRxRXCAD+AQAHAAcKRxRXCAD+AQA1AAQKf1IAAgcACgpYJWkCAGEDAAcACgpYJWkCAGEDAAAA.',
Hy='Hypearione:BAAANQADCgEIAwAAAA==.',
Ia='Iambohike:BAAANQAECgIIAwAAAA==.',
Ic='Icycritties:BAABNQAECn8pAAQGAAkKog4SDQB9AQAGAAkKog4SDQB9AQAFAAcKnwYwxwDwAAAfAAEKPQOIDwAiAAAAAA==.',
Ih='Iheals:BAAANQADCgIIAgAAAA==.',
Im='Imjustadruid:BAAANQADCgMIBQAAAA==.Immortal:BAABNQAECn80AAIEAAkKHhBhJACMAQAEAAkKHhBhJACMAQAAAA==.',
In='Incarnated:BAABNQAECn8bAAMEAAoK3CFmDQBOAwAEAAoK3CFmDQBOAwADAAYKiRhHQABbAQAAAA==.',
Ir='Irís:BAAANQAECggIEgAAAA==.',
Is='Iskra:BAAANQADCgIIAgAAAA==.Ispithotfire:BAAANQADCgEIAQAAAA==.',
Iu='Iu:BAAANQAECggIEQAAAA==.',
Ja='Jackfash:BAAANQADCgMIBQAAAA==.Jadecross:BAAANQADCgIIAgAAAA==.Javan:BAAANQADCgIIAgAAAA==.',
Je='Jerryatric:BAABNQAECn8iAAINAAcKDQ1q5ABSAQANAAcKDQ1q5ABSAQAAAA==.',
Ji='Jiri:BAAANQADCgEIAQAAAA==.',
Jk='Jkmno:BAAANQADCgMIAwABNQADCgUIBQARAAAAAA==.',
Jo='Joeyrains:BAAANQADCgQIBAAAAA==.',
Ju='Justblaze:BAAANQAECgQIBAAAAA==.Justincasê:BAAANQADCgEIAgAAAA==.',
Ka='Kallikan:BAABNQAECn8sAAIhAAgK7hPwHgCnAQAhAAgK7hPwHgCnAQAAAA==.Kamidk:BAABNQAECn8YAAMMAAkKVCDVCADrAgAMAAkKVCDVCADrAgAEAAMK9RLDRADNAAAAAA==.Kamuri:BAAANQADCgUIBQAAAA==.Kasteen:BAAANQAECgEIAQAAAA==.Kastra:BAAANQADCgEIAQAAAA==.Katia:BAABNQAECn8WAAINAAUKfQZgMQHQAAANAAUKfQZgMQHQAAAAAA==.Kaøs:BAAANQAECgEIAgAAAA==.',
Kd='Kdoggparker:BAAANQABCgYICQAAAA==.',
Ke='Kelvox:BAAANQAECgQIBAAAAA==.Kementari:BAABNQAECn8mAAIHAAkK/gWjPgD9AAAHAAkK/gWjPgD9AAAAAA==.Kenzaki:BAABNQAECn8qAAINAAgKiBVRkwD9AQANAAgKiBVRkwD9AQAAAA==.',
Kh='Khaladin:BAAANQADCgYICAAAAA==.Khaosreborn:BAAANQADCgUIAQAAAA==.Khaotic:BAAANQAECgQIBAAAAA==.',
Ki='Kilaaz:BAABNQAECn8lAAINAAoKACJ3LACHAgANAAoKACJ3LACHAgAAAA==.Kilossus:BAAANQAECgQIBQAAAA==.Kirveka:BAAANQADCgEIAQAAAA==.',
Kl='Kliticaldk:BAAANQAECgIIBAAAAA==.Kliticalwar:BAABNQAECn8bAAIYAAoK7A9ZjgD4AQAYAAoK7A9ZjgD4AQAAAA==.Klothys:BAABNQAECn8lAAINAAoKAx3iXQB/AgANAAoKAx3iXQB/AgAAAA==.',
Kn='Knuts:BAAANQADCgMJAwABNQAECgYIBgARAAAAAA==.',
Ko='Koitsvo:BAAANQAECgIIAwAAAA==.Ková:BAAANQADCgUJDAAAAA==.',
Ku='Kuani:BAAANQAECgQIBAABNQAECgkJPgAZAK0fAA==.',
La='Labelle:BAAANQAECgEIAQAAAA==.Landre:BAAANQADCgQIBgAAAA==.Lassy:BAAANQADCgIJAgAAAA==.Lathray:BAABNQAECn8dAAMUAAgKPQsdLQA9AQAUAAgKPQsdLQA9AQAHAAEKAAApxQAdAAAAAA==.Lazerislong:BAAANQAECgEIAQAAAA==.Lazerous:BAAANQAECgMIAwAAAA==.',
Le='Lealoo:BAABNQAECn8rAAINAAkKrBPGkQABAgANAAkKrBPGkQABAgABNQAECgoKLwAQACYRAA==.Leftfield:BAAANQAECgIIAgABNQAECgkJKgAOAOwHAA==.Legolard:BAABNQAECn8fAAMdAAgKpRqMDwCEAQAdAAcKZh+MDwCEAQAYAAMKiwecMwFtAAAAAA==.Leleia:BAABNQAECn8YAAIIAAgKkQrBIwArAQAIAAgKkQrBIwArAQAAAA==.',
Lh='Lhera:BAABNQAECn8jAAMkAAkKkR1yDACpAgAkAAkKkR1yDACpAgASAAcKMRR/eACiAQABNQAECgoKMgAbAGEfAA==.',
Li='Liath:BAABNQAECn8cAAIJAAYKohOBegAuAQAJAAYKohOBegAuAQAAAA==.Lichtenberg:BAABNQAECn85AAMLAAoKeh3KMQCzAgALAAoKeh3KMQCzAgASAAUKxwjL1AC9AAAAAA==.Linddori:BAABNQAECn8UAAINAAYKjhAwDgEHAQANAAYKjhAwDgEHAQABNQAECgoKKgACAAQWAA==.Liori:BAAANQAECgEIAgAAAA==.Lirillia:BAABNQAECn8qAAQCAAoKBBY5CgBTAgACAAgKMxg5CgBTAgAOAAkK3wyvngDjAAAlAAEKAACoMAA0AAAAAA==.Lirillïa:BAAANQADCgYIDAABNQAECgoKKgACAAQWAA==.Lizzie:BAAANQADCgUIBQAAAA==.',
Lo='Locdon:BAAANQABCgIIAgABNQAECgUICAARAAAAAA==.Lodestone:BAAANQAECgQIBAAAAA==.Loena:BAABNQAECn8VAAMiAAoK7Ax3SgC3AQAiAAkK1At3SgC3AQANAAIKEwE8pwEAAAAAAA==.Lokk:BAAANQAECgIIAgABNQAECggIJAAWAOIaAA==.Loko:BAAANQAECgEIAQAAAA==.Lolowbeatz:BAAANQADCgUICwAAAA==.Lovelydread:BAAANQAECgEIAQAAAA==.',
Lu='Lunabug:BAAANQAECgIIAgAAAA==.Lupinos:BAAANQADCgIIAgAAAA==.',
Ly='Lyadra:BAABNQAECn8sAAIJAAkKIh6XNQAyAgAJAAkKIh6XNQAyAgAAAA==.Lyrissa:BAAANQADCgYIBgAAAA==.',
['Lõ']='Lõst:BAAANQAECgIIAwAAAA==.',
Ma='Mackito:BAABNQAFFH8OAAIWAAgKHgE8IwBjAAAWAAgKHgE8IwBjAAAAAA==.Madan:BAABNQAECn8bAAIEAAcK9wdcNgAXAQAEAAcK9wdcNgAXAQAAAA==.Magey:BAAANQADCgEIAQAAAA==.Mahoushojou:BAAANQAECgIIAgABNQAECgkJIAAiAEQPAA==.Malasminna:BAAANQAECgYIEgAAAA==.Malehorelock:BAAANQAECgEIAQABNQAECgEIAQARAAAAAA==.Malicioun:BAAANQADCgEIAQAAAA==.Malkariss:BAABNQAECn8lAAMGAAgK4xrYGwARAQAFAAYKNhv7zQDqAQAGAAUKBhfYGwARAQAAAA==.Mammadruid:BAABNQAECn8oAAIhAAcKcgyhLwDdAAAhAAcKcgyhLwDdAAAAAA==.Mauldis:BAABNQAECn8mAAMLAAgK4gU4dAD0AAALAAgK4gU4dAD0AAASAAUKtQI07QCRAAAAAA==.',
Me='Meryl:BAABNQAECn8wAAIiAAkKYxi2PAByAgAiAAkKYxi2PAByAgAAAA==.',
Mi='Miaka:BAABNQAECn84AAIlAAoK7RmgAwC4AgAlAAoK7RmgAwC4AgAAAA==.Minigoonta:BAAANQAECgEIAQAAAA==.Minth:BAAANQADCgcIDgABNQAECgkJIAAiAEQPAA==.Miraakle:BAAANQAECgQIBwABNQAECgkJIAAiAEQPAA==.Misfire:BAABNQAECn8zAAIWAAkKfBFweAAeAgAWAAkKfBFweAAeAgAAAA==.Mithra:BAAANQAECgQICQAAAA==.',
Mo='Moghroth:BAABNQAECn87AAMHAAkK6gyaLABkAQAHAAkKcgyaLABkAQAhAAIKjgkVYwArAAAAAA==.Molykote:BAAANQAECggIDAAAAA==.Monks:BAAANQADCgQIBAAAAA==.Monsterbabe:BAAANQAECgEIAgAAAA==.Moonfall:BAAANQADCgEIAQAAAA==.Moreleath:BAAANQADCgMIBAAAAA==.Morphias:BAAANQADCgQIBAAAAA==.Mowiewowie:BAAANQADCgEIAQAAAA==.',
Mu='Mugzypatron:BAAANQAECgEIAgAAAA==.Murdrmitts:BAABNQAECn8bAAIhAAcKmwsrKgBGAQAhAAcKmwsrKgBGAQAAAA==.',
['Mã']='Mãtador:BAACNQAFFH8HAAILAAUK1RPnEABdAQALAAUK1RPnEABdAQA1AAQKfyoAAwsACQoZIxAgAAsDAAsACQoZIxAgAAsDABIAAwo3EJv6AHUAAAAA.',
['Mä']='Mätadør:BAABNQAECn8UAAIIAAgKFxs2IgAjAgAIAAgKFxs2IgAjAgABNQAFFAUIBwALANUTAA==.',
Na='Nahryn:BAABNQAECn8mAAIUAAgKzhwZFwCJAgAUAAgKzhwZFwCJAgAAAA==.',
Ne='Nedina:BAAANQADCgUIBQAAAA==.Nerbert:BAAANQADCgYJBgABNQAECgoKNgAVAFESAA==.Neretsym:BAABNQAECn8zAAIWAAkKChBzZQCyAQAWAAkKChBzZQCyAQAAAA==.',
Ni='Nineva:BAABNQAECn8bAAIUAAcKeQbZPADbAAAUAAcKeQbZPADbAAAAAA==.',
No='Nobas:BAABNQAECn89AAIHAAoKWwpyLwBRAQAHAAoKWwpyLwBRAQAAAA==.Nonfiction:BAAANQAECgEIAQAAAA==.Nonoa:BAAANQAECgIIAwAAAA==.',
Oc='Octavien:BAAANQADCgIIAgAAAA==.',
Og='Ogr:BAAANQADCgMIAwAAAA==.',
On='Onlyfeet:BAABNQAECn8jAAINAAoKiBzuMwBnAgANAAoKiBzuMwBnAgAAAA==.',
Op='Oppgjør:BAAANQAECgEIAQAAAA==.',
Or='Oreeree:BAAANQAECgQIDwAAAA==.Ormr:BAABNQAECn82AAMVAAoKURKwCQCmAQAVAAoKURKwCQCmAQAgAAEKAABPIwA5AAAAAA==.',
Os='Osteo:BAABNQAECn8pAAMCAAkKLQajJwA7AQACAAcK2wSjJwA7AQAOAAkK7wVKmQDvAAAAAA==.Osteoprime:BAAANQADCgUJBQAAAA==.',
Ou='Ouron:BAABNQAECn8sAAMSAAoKiRbmPQBoAgASAAoKiRbmPQBoAgALAAEKAAD/AwEAAAAAAA==.Outofmana:BAAANQAECgQIDgAAAA==.',
Ov='Ovelia:BAAANQAECgUIBQAAAA==.',
Pa='Pagoda:BAAANQADCgYIBgAAAA==.Papashrimps:BAACNQAFFH8QAAMFAAUKKxTgKQA8AQAFAAQKKxTgKQA8AQAGAAEKAAC4FAAAAAA1AAQKfyYAAwUACgqHGISWAFMCAAUACgqXF4SWAFMCAAYAAQoxGmQ/AEYAAAAA.',
Pe='Penelopee:BAAANQAECgEIAgAAAA==.Percy:BAAANQADCggIGQAAAA==.',
Ph='Phatcow:BAAANQADCgEIAQAAAA==.',
Pl='Placeholder:BAABNQAECn87AAIjAAkKUSLzBwChAgAjAAkKUSLzBwChAgAAAA==.',
Po='Pojoevokest:BAABNQAECn8hAAIeAAgKzAkvHAAAAQAeAAgKzAkvHAAAAQAAAA==.Pontifex:BAABNQAECn8vAAIJAAoKDhUgSADfAQAJAAoKDhUgSADfAQAAAA==.Pontiféx:BAAANQADCgEIAQAAAA==.Portandmorph:BAABNQAECn8gAAIGAAkK0hGWCwAHAgAGAAkK0hGWCwAHAgAAAA==.',
Pr='Priests:BAAANQADCgQIBgAAAA==.Prone:BAABNQAECn89AAMSAAoKBQwTjwBjAQASAAkKOAkTjwBjAQALAAYKlwW7kgCtAAAAAA==.Protarada:BAAANQAECgcICQAAAA==.',
Qu='Quietmind:BAAANQAECggIEQAAAA==.Quinnifred:BAAANQAECgEIAQAAAA==.',
Ra='Raakotah:BAABNQAECn89AAIHAAoKHyWCCQDqAgAHAAoKHyWCCQDqAgAAAA==.Raasclaat:BAAANQADCgcIDQAAAA==.Raelo:BAABNQAECn86AAIkAAkK0w3qEQC2AQAkAAkK0w3qEQC2AQAAAA==.Rainbowflake:BAABNQAECn8VAAIWAAcK3wIbAgEBAQAWAAcK3wIbAgEBAQAAAA==.Raiseurmug:BAABNQAECn8tAAIcAAoKxBDTEADcAQAcAAoKxBDTEADcAQAAAA==.Rakash:BAAANQADCgcICAAAAA==.Rarg:BAABNQAECn8VAAMMAAgKlRnWSgDMAQAMAAgKlRnWSgDMAQAEAAEK6QLn8gAkAAAAAA==.Ravia:BAAANQAFFAEIAQAAAA==.Rayjr:BAAANQAECgYIBgAAAA==.',
Re='Rendysavage:BAAANQAECgYJBgAAAA==.Resco:BAAANQADCggIEwAAAA==.',
Ri='Riddle:BAABNQAECn8uAAISAAoKKQsOagBDAQASAAoKKQsOagBDAQAAAA==.Rimeouo:BAAANQAFFAEIAQAAAA==.Rize:BAABNQAECn8aAAIYAAgK/w++mgDaAQAYAAgK/w++mgDaAQABNQAECgoKNAAVAGYPAA==.Rizmthetizm:BAAANQADCgEIAQAAAA==.',
Ro='Roadlock:BAAANQADCgEIAQAAAA==.Rosenrott:BAABNQAECn87AAIWAAkK+CNZGADCAgAWAAkK+CNZGADCAgAAAA==.Rosepiercer:BAABNQAECn8rAAIWAAoK9SNACgAkAwAWAAoK9SNACgAkAwAAAA==.Rouz:BAABNQAECn8bAAIVAAcKhgn5EQDnAAAVAAcKhgn5EQDnAAAAAA==.',
Ru='Ruddybear:BAAANQADCgIJAgAAAA==.',
Ry='Ryoto:BAAANQAECgUICAAAAA==.',
Sa='Sadarasdeath:BAAANQAECgMIAwAAAA==.Samandean:BAABNQAECn8vAAIQAAoKJhEoHgDhAQAQAAoKJhEoHgDhAQAAAA==.Sarasvati:BAAANQAECgMIAwAAAA==.Sariia:BAAANQAECggIDwABNQAECgoKSQAPAM8jAA==.',
Se='Sellena:BAABNQAECn8kAAIkAAkK/xDdEADJAQAkAAkK/xDdEADJAQABNQAECgoKLwAQACYRAA==.Serrations:BAAANQAECgEIAQABNQAECgEIAQARAAAAAA==.',
Sh='Shakenn:BAAANQADCgEIAgAAAA==.Shandow:BAABNQAECn9MAAIGAAoKrCMfAQApAwAGAAoKrCMfAQApAwAAAA==.Shansoracle:BAABNQAECn8sAAMJAAoKWx/uDwAyAwAJAAoKWx/uDwAyAwAIAAEKaAP7ggAmAAABNQAECgoKTAAGAKwjAA==.Shed:BAAANQAECgUIBAABNQAFFAcIFwAHAEcUAA==.Sheislegend:BAAANQAECgEIAQAAAA==.Shelby:BAABNQAECn8rAAIJAAkKcByEQQBlAgAJAAkKcByEQQBlAgAAAA==.Shocked:BAAANQAECggIBAABNQAECggIDQARAAAAAA==.Shockolate:BAAANQAECgYIDgAAAA==.Shoog:BAAANQABCgMIAwAAAA==.Shrimpbottom:BAAANQAFFAEIAQAAAA==.',
Si='Siarn:BAAANQADCgMIBQAAAA==.Siccinok:BAABNQAECn84AAMFAAgKJR4MVQDrAQAFAAgKJR4MVQDrAQAGAAQKwx2kIADkAAAAAA==.Sindorian:BAAANQAECgEIAQAAAA==.Sixhundrdlbs:BAACNQAFFH8OAAIPAAQKUh2mBQD2AAAPAAQKUh2mBQD2AAA1AAQKf0AAAw8ACgreJLADAJ0DAA8ACgreJLADAJ0DABAAAQqYCpl4AC4AAAE1AAQKCgobAAQA3CEA.',
Sk='Skraps:BAAANQADCgEJAQAAAA==.',
Sl='Slimped:BAAANQADCgYICwAAAA==.',
Sn='Sneakybato:BAAANQAECgEIAQAAAA==.',
So='Sofie:BAAANQADCgQIBAABNQAECgoKOQALAHodAA==.Solarial:BAAANQAECgUIEQAAAA==.Solastra:BAABNQAECn8vAAIiAAgKuRbJQgDVAQAiAAgKuRbJQgDVAQAAAA==.Soramai:BAAANQAECgQICwAAAA==.Soth:BAABNQAECn89AAMEAAoKZBXKIACoAQAEAAoKZBXKIACoAQAMAAkK0BByVgCaAQAAAA==.',
Sp='Sparký:BAABNQAECn8nAAIOAAoK9iR1BABBAwAOAAoK9iR1BABBAwAAAA==.Spinnycrisp:BAAANQADCgYIBgAAAA==.',
St='Starlyvana:BAACNQAFFH8PAAMGAAUKTQs+AgDrAAAGAAQKTQs+AgDrAAAFAAIKlwf0RgAAAAA1AAQKfxkAAwYACgprFssHAG8CAAYACgprFssHAG8CAAUAAQrEGPAsAUwAAAAA.Staryxia:BAABNQAECn8XAAIDAAkKSh1KNgD/AQADAAkKSh1KNgD/AQAAAA==.Statiic:BAAANQADCgEIAQAAAA==.Steamdruid:BAAANQADCggIEAABNQAECgoKNwAQAHEYAA==.Steephany:BAAANQADCgMIBwAAAA==.Stonecross:BAABNQAECn8mAAIJAAkKDxuGOgB/AgAJAAkKDxuGOgB/AgAAAA==.Stoneldo:BAAANQADCgEIAQAAAA==.Stormbolt:BAABNQAECn8vAAIHAAoKnwtYTgCmAQAHAAoKnwtYTgCmAQAAAA==.Stormspirit:BAAANQADCggIIQAAAA==.Striggen:BAABNQAECn8WAAMNAAUKYxRC2QDqAAANAAUKLxRC2QDqAAAjAAMKuA5/VgCHAAAAAA==.',
Su='Sugarsham:BAABNQAECn8kAAILAAoKpAvJcgDIAQALAAoKpAvJcgDIAQAAAA==.Sulwen:BAACNQAFFH8YAAIHAAgK0SRnAQDwAgAHAAgK0SRnAQDwAgA1AAQKfzkAAgcACgryJjcAAJkDAAcACgryJjcAAJkDAAAA.Sumerset:BAABNQAECn8ZAAINAAkK8Qw0mgBXAQANAAkK8Qw0mgBXAQAAAA==.Sundave:BAAANQAECgEJAgAAAA==.Supaflytnt:BAABNQAECn8wAAITAAgKqxgNCgDzAQATAAgKqxgNCgDzAQAAAA==.Sustia:BAAANQAECgUICwAAAA==.',
Ta='Taera:BAABNQAECn8+AAIZAAkKrR86BgD3AgAZAAkKrR86BgD3AgAAAA==.Talavenn:BAABNQAECn8kAAIPAAkK0B2uEQDgAgAPAAkK0B2uEQDgAgAAAA==.Tanglock:BAAANQAECgYIEAAAAA==.Tarage:BAAANQAECgUIDAAAAA==.Tatumus:BAAANQADCgEIAQAAAA==.Taurîel:BAAANQADCgYIBwAAAA==.',
Te='Tectoniiks:BAAANQAECgcIBwAAAA==.Tedds:BAAANQAECgUJCAAAAA==.Teds:BAAANQADCgYICwAAAA==.Tempus:BAAANQAECgMJAwAAAA==.Teriko:BAABNQAECn8sAAIDAAoKihcVLQA3AgADAAoKihcVLQA3AgAAAA==.Teviro:BAAANQADCgIIAgABNQAECgoKMgAbAGEfAA==.',
Th='Thequixote:BAABNQAECn8bAAITAAYKaha/FQCfAQATAAYKaha/FQCfAQAAAA==.',
Ti='Tictok:BAAANQAECgEIAQAAAA==.Tinytotems:BAAANQADCgQIBAAAAA==.',
To='Toaderic:BAAANQAECgUIDwAAAA==.Toemama:BAAANQAECgIIAgABNQAECgoKIwANAIgcAA==.Tots:BAABNQAECn8/AAIhAAoKAh2iCQB4AgAhAAoKAh2iCQB4AgAAAA==.Toxictotes:BAAANQAECgEIAQAAAA==.',
Tr='Trazah:BAAANQADCgEIAQAAAA==.',
Ty='Tyraèl:BAABNQAECn8lAAIiAAoKGyMBCACJAwAiAAoKGyMBCACJAwAAAA==.Tyzy:BAACNQAFFH8UAAMUAAQK4iEHBQCUAQAUAAQK4iEHBQCUAQAHAAQK8COTCQAkAQA1AAQKfyoAAwcACgrvI/YNAFsDAAcACgrvI/YNAFsDABQACQowHZkXAIQCAAAA.',
Um='Umber:BAAANQADCggICAAAAA==.',
Va='Valenora:BAABNQAECn8uAAICAAoKWBgtAgAzAgACAAoKWBgtAgAzAgAAAA==.Valvitor:BAAANQADCgEIAQAAAA==.Varuz:BAABNQAECn8kAAIWAAgK4hpIQACqAgAWAAgK4hpIQACqAgAAAA==.Varyz:BAAANQADCgIIAgABNQAECggIJAAWAOIaAA==.',
Ve='Velanie:BAAANQAECgEIAQAAAA==.Veloon:BAABNQAECn8bAAIHAAkKIg7hQgDqAQAHAAkKIg7hQgDqAQAAAA==.Veloras:BAAANQAECggIDAAAAA==.Verinari:BAAANQAECgQICQAAAA==.',
Vi='Vipul:BAAANQADCgUIDQABNQADCgYIBwARAAAAAA==.Viridria:BAABNQAECn8gAAMiAAkKRA/pTQCpAQAiAAkKRA/pTQCpAQANAAIKZwnqgQEkAAAAAA==.Vityazi:BAABNQAECn8YAAINAAcKlAO6KAHcAAANAAcKlAO6KAHcAAAAAA==.',
Vl='Vlado:BAAANQAECgEIAgAAAA==.',
Vo='Volksworgeñ:BAAANQADCgEIAQAAAA==.Voodoobootie:BAAANQADCgEIAQAAAA==.',
Vy='Vy:BAAANQADCgUICQAAAA==.',
['Vè']='Vè:BAABNQAECn8pAAIhAAkKqxAbGgDWAQAhAAkKqxAbGgDWAQAAAA==.',
Wa='Warriors:BAABNQAECn9IAAIYAAoKDiMREQABAwAYAAoKDiMREQABAwAAAA==.Wartooth:BAABNQAECn8vAAMCAAgKOhUvKQAxAQAOAAgK/A0ObQBXAQACAAQKiBgvKQAxAQAAAA==.Wassergott:BAAANQAECgEIAQAAAA==.',
We='Webicus:BAABNQAECn8eAAQYAAgKKQn5xwBoAQAYAAcKFQr5xwBoAQAXAAMKfQZEJABVAAAdAAEKjQS1PwAnAAAAAA==.Weebster:BAAANQABCgQIBAAAAA==.Wendee:BAABNQAECn8tAAMJAAkKsAQvbwBSAQAJAAkKsAQvbwBSAQAIAAEKAABKlAATAAAAAA==.',
Wh='Whitefóx:BAAANQAECgcIEAABNQAECgoKTAAGAKwjAA==.Whitley:BAABNQAECn81AAMSAAkKiSHmLQCqAgASAAkKiSHmLQCqAgALAAcKkBThbgDTAQAAAA==.',
Wi='Wildspart:BAABNQAECn8VAAMmAAgKSxW5CAC9AQAmAAgKDBS5CAC9AQAWAAIKxhYeKwGaAAAAAA==.',
Wo='Wooden:BAABNQAECn8tAAIWAAkKIhmeQQAZAgAWAAkKIhmeQQAZAgAAAA==.',
Xa='Xaphy:BAABNQAECn8hAAMJAAkKOxwKKgBuAgAJAAkKOxwKKgBuAgAIAAkKvA30GwB3AQAAAA==.Xardots:BAABNQAECn8aAAICAAcKthN8EgDhAQACAAcKthN8EgDhAQABNQAECggINQARAAAAAA==.',
Xi='Xiareth:BAABNQAECn8qAAIeAAcKPhGwFgBJAQAeAAcKPhGwFgBJAQAAAA==.',
Xy='Xyleiah:BAAANQADCgYIBgABNQAECgoKPQAVAEEXAA==.',
['Xá']='Xároth:BAAANQAECggINQAAAQ==.',
Ya='Yaddi:BAAANQAECgIIBgAAAA==.Yargue:BAABNQAECn8tAAIIAAoKpBp7CgCPAgAIAAoKpBp7CgCPAgAAAA==.',
Ye='Yeeyee:BAAANQAECggIDQAAAA==.',
Yi='Yirï:BAAANQADCgEIAQAAAA==.',
Yo='Yorgue:BAAANQAECggIAwABNQAECgoKLQAIAKQaAA==.Youngjeezy:BAABNQAECn8ZAAMEAAYKmgNtWACCAAAEAAYKmgNtWACCAAADAAIKZQNsqgAeAAAAAA==.Yoursinpride:BAAANQAECggIDgAAAA==.',
Za='Zackor:BAAANQADCgUIDAAAAA==.',
Ze='Ze:BAAANQADCgYICwAAAA==.Zervann:BAAANQADCgYIBwAAAA==.',
Zi='Ziska:BAAANQADCgIIAgAAAA==.',
Zo='Zorithic:BAAANQAECgIJAwAAAA==.',
Zu='Zuldan:BAAANQADCgIIAgAAAA==.',
Zy='Zyde:BAAANQAECgUIBQABNQAECggIJAAWAOIaAA==.',
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
