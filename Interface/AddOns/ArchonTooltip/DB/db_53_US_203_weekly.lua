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

local lookup = {'Rogue-Outlaw','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Unholy','Mage-Arcane','Mage-Frost','Druid-Balance','Priest-Shadow','Priest-Holy','Priest-Discipline','Shaman-Elemental','DeathKnight-Blood','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','Unknown-Unknown','Shaman-Restoration','Warlock-Demonology','Druid-Restoration','Evoker-Devastation','Warrior-Arms','Warrior-Fury','Monk-Mistweaver','Monk-Brewmaster','Warrior-Protection','Evoker-Preservation','Hunter-BeastMastery','Mage-Fire','Evoker-Augmentation','Druid-Guardian','Paladin-Holy','Shaman-Enhancement','Rogue-Assassination','Warlock-Affliction','Paladin-Protection','Druid-Feral',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aanuanaela:BAABNQAECn8gAAIBAAkKNhHvCAAGAgABAAkKNhHvCAAGAgAAAA==.Aanubis:BAAANQADCgUIBQAAAA==.',
Ab='Absens:BAABNQAECn8qAAICAAoKoAwxAgBPAQACAAoKoAwxAgBPAQAAAA==.Abumim:BAAANQAECgQIBAAAAA==.',
Ad='Adorian:BAAANQAECgQIBAABNQAECgoKMgADAO0gAA==.Adwillon:BAAANQAECgIIAgAAAA==.',
Af='Aforceofone:BAAANQAECgUICgAAAA==.',
Ag='Aggretsuko:BAABNQAECn8nAAMEAAoKuRW0QAAaAgAEAAgK6hi0QAAaAgADAAkKOQnOTgB5AQAAAA==.',
Al='Aldonza:BAAANQADCgIIAgAAAA==.Alex:BAAANQAECgQIDAAAAA==.Alivanllan:BAAANQAECgQIBAAAAA==.Aluviel:BAACNQAFFH8KAAMFAAMKdhx9LgAdAQAFAAMKdhx9LgAdAQAGAAEKAQwdEwBIAAA1AAQKfxUAAgUACQrqJIsiAFIDAAUACQrqJIsiAFIDAAE1AAUUBwgWAAcAAiYA.Alyslia:BAAANQABCggIGQAAAA==.',
An='Anamuht:BAABNQAECn8sAAQIAAgKDxaZLgCwAQAIAAcK5hOZLgCwAQAJAAcK4Qs3UwDRAAAKAAMKEgcpHQB6AAABNQAECgkJMQALAPwdAA==.Angeli:BAAANQAECgEIAQAAAA==.Annaday:BAAANQAECgYIEAAAAA==.Antiock:BAABNQAECn8yAAQDAAoK7SA8EQAFAwADAAoKEx08EQAFAwAMAAcKzyLrLwBSAgAEAAcKnxksQwAOAgAAAA==.Anyamonka:BAAANQAECgcIEQAAAA==.',
Ap='Appalachia:BAAANQADCgYJBgAAAA==.',
Ar='Ariea:BAAANQADCgEIAQAAAA==.Arraven:BAAANQADCggIBwAAAA==.Arrowmir:BAAANQABCgYJCAAAAA==.Artto:BAAANQADCgIIAgAAAA==.',
As='Ashbrínger:BAABNQAECn8xAAINAAoKtCHDGABhAwANAAoKtCHDGABhAwAAAA==.',
At='Atua:BAAANQAECgEIAgAAAA==.',
Av='Averax:BAABNQAECn8kAAMOAAgKxSBCAwAFAgAOAAgKxSBCAwAFAgAPAAEKAAB3jQBBAAAAAA==.Avylbrew:BAAANQADCgcICgABNQAECgIIAgAQAAAAAA==.',
Ay='Aylakaye:BAAANQADCggICQAAAA==.',
Az='Azzathoth:BAAANQADCggICAAAAA==.',
Ba='Babybilly:BAABNQAECn8aAAMLAAgKfBmVXAAMAgALAAcKJhuVXAAMAgARAAUKzB6zFwCaAQAAAA==.Babyshoes:BAAANQAECgQIBwAAAA==.Backpack:BAAANQAECgYICQAAAA==.Bananawaffle:BAAANQADCgEIAQAAAA==.Bandan:BAAANQAECgYIDAAAAA==.Bato:BAAANQADCgUIDAAAAA==.',
Be='Beauvito:BAAANQADCgEIAQAAAA==.Beefjurkey:BAAANQAECgQICQAAAA==.Betch:BAAANQAECggIBQABNQAECggIDAAQAAAAAA==.',
Bh='Bhalthazar:BAAANQADCgUICQABNQADCgYICAAQAAAAAA==.',
Bi='Bier:BAAANQAECgQIBgAAAA==.Bigrig:BAAANQAECgEIAQAAAA==.Bitterman:BAABNQAECn8lAAISAAgKTgipqwB7AQASAAgKTgipqwB7AQAAAA==.',
Bl='Blastin:BAAANQADCggIGAAAAA==.Bloodveil:BAAANQAECgQIBgABNQAECggIEQAQAAAAAA==.Bluemonster:BAAANQADCgQIBAAAAA==.',
Bo='Boohoo:BAAANQADCgMIAwAAAA==.Bovinedivine:BAAANQADCgUIBQABNQAECggIIgAQAAAAAA==.',
Br='Brandumb:BAAANQAECgYICgAAAA==.',
Ca='Callana:BAAANQAECgQICAAAAA==.Camedra:BAABNQAECn8jAAITAAkKciNzCQAuAwATAAkKciNzCQAuAwAAAA==.Carelessheal:BAAANQAECggICAAAAA==.Carthella:BAAANQADCgQJBAABNQAECgoKMgAUAFESAA==.Catamynyia:BAAANQAECgYIEAAAAA==.',
Cc='Cchaos:BAAANQAECgMJAwAAAA==.',
Ce='Celaborn:BAABNQAECn8bAAMVAAgK2hDLRgATAQAVAAgK2hDLRgATAQAWAAEKOA3nMwAzAAAAAA==.Celice:BAAANQABCgcIBwABNQAECgkJLQAXAA4bAA==.',
Ch='Chimaira:BAAANQADCgQIBAAAAA==.Chucknoris:BAAANQADCgcJEQAAAA==.Chump:BAAANQADCgEIAQAAAA==.',
Cl='Claytonbigse:BAAANQABCgIIAgAAAA==.',
Co='Colossuss:BAAANQAECgIIAgAAAA==.Conduction:BAAANQADCgcICwAAAA==.',
Cr='Crankadin:BAAANQAECggIAQABNQADCggIEQAQAAAAAA==.Crispyquinn:BAAANQADCgUIBQAAAA==.Crispysham:BAABNQAECn8bAAILAAgKExHZZwDpAQALAAgKExHZZwDpAQAAAA==.Cruciö:BAAANQADCggIDAAAAA==.Crànk:BAAANQADCggIEQAAAA==.Cránk:BAAANQAECggJCAABNQADCggIEQAQAAAAAA==.Crãnk:BAAANQAECggIDgABNQADCggIEQAQAAAAAA==.',
Cu='Cullyeskie:BAAANQAECgUIDwAAAA==.Curveball:BAAANQAECgMIAwABNQAECggIJQASAE4IAA==.',
Cy='Cyniar:BAABNQAECn8jAAIHAAgKNQs5FQAyAQAHAAgKNQs5FQAyAQAAAA==.',
Da='Dabrick:BAAANQADCgEIAQAAAA==.Dahnu:BAAANQADCgIIAgABNQAECgYIFQAJADERAA==.Damerlin:BAAANQADCgIIAgAAAA==.Darkhuntress:BAAANQADCgYIBgAAAA==.Darkstär:BAABNQAECn8xAAIMAAkKvBgXKQB5AgAMAAkKvBgXKQB5AgAAAA==.Darkun:BAAANQADCggICAABNQAECgoKMwAUAH0OAA==.',
De='Deacon:BAABNQAECn8kAAIYAAgKyQalBwDqAAAYAAgKyQalBwDqAAAAAA==.Deadzly:BAABNQAECn83AAQMAAkKoSNsEAApAwAMAAgKsiNsEAApAwADAAgKZhY6PADdAQAEAAgKYhC6VQC7AQAAAA==.Deathknights:BAAANQADCgMIAwAAAA==.Deeanne:BAAANQAECgQIBAAAAA==.Deepfriar:BAABNQAECn8yAAIJAAkK4iVWCABiAgAJAAkK4iVWCABiAgAAAA==.Deltoro:BAAANQADCgIIAgAAAA==.Demoniiks:BAAANQABCgcICQAAAA==.Derailed:BAABNQAECn8WAAIDAAgKCwt9MQDWAAADAAgKCwt9MQDWAAAAAA==.Dethwing:BAAANQADCgQICAAAAA==.Dewsbelle:BAAANQAECgQICAAAAA==.',
Dh='Dha:BAAANQADCgcIBwABNQAECgYIFgAZADYfAA==.',
Di='Diablognomis:BAAANQADCgcIDwAAAA==.Dirtman:BAABNQAECn8iAAILAAgKwRc7EACTAQALAAgKwRc7EACTAQAAAA==.Distillate:BAAANQADCgYIHAAAAA==.',
Dk='Dkrise:BAAANQADCgIIAgABNQAECgoKMwAUAH0OAA==.',
Do='Dolphina:BAAANQAECgEIAQAAAA==.Donny:BAAANQAECgUICAAAAA==.',
Dr='Dragonic:BAACNQAFFH8OAAMaAAUKLxYNCgCMAQAaAAUKLxYNCgCMAQAUAAIKxwN2DQBwAAA1AAQKfyUAAxoACgpgF04UAGoCABoACgpgF04UAGoCABQAAgp3DigzAHYAAAAA.Dreathlu:BAAANQADCgUIBQAAAA==.Drewdog:BAABNQAECn8bAAIbAAcKIA/fuACSAQAbAAcKIA/fuACSAQAAAA==.',
Du='Dubes:BAABNQAECn8xAAIGAAkKIBv7BgCIAgAGAAkKIBv7BgCIAgAAAA==.Dunbartian:BAABNQAECn8hAAIZAAkKShOeBACLAQAZAAkKShOeBACLAQAAAA==.Duration:BAAANQABCgUIBwAAAA==.',
Ea='Easybreezin:BAAANQADCggICAAAAA==.',
Ei='Eirote:BAABNQAECn8xAAIcAAkKzg+3AgAGAgAcAAkKzg+3AgAGAgAAAA==.',
El='Elarris:BAAANQADCgYIBgAAAA==.Eldari:BAAANQAECgUIDwAAAA==.Eledron:BAAANQAECgQIBAAAAA==.Elyssaena:BAAANQAECgYICAAAAA==.',
Em='Emotionaldmg:BAAANQAECgUIBQABNQAECggIDAAQAAAAAA==.',
En='Enzojr:BAAANQAECgMIBAAAAA==.',
Er='Eriath:BAABNQAECn87AAIIAAoKUByjAQBnAgAIAAoKUByjAQBnAgAAAA==.',
Ev='Evè:BAAANQABCgEIAQAAAA==.',
Ex='Exalted:BAAANQAECgQIBwABNQAFFAUIDgAaAC8WAA==.',
Ey='Eye:BAABNQAECn8bAAMLAAoKphbgNACkAgALAAkKUxjgNACkAgARAAEKDQj3lwA2AAAAAA==.',
Fa='Faranth:BAABNQAECn8xAAMUAAkKBBfAAwBsAQAUAAkKBBfAAwBsAQAdAAIKLwrOIABRAAAAAA==.',
Fe='Feld:BAAANQAECgQIBAAAAA==.Felynne:BAAANQAECggIAwAAAA==.Feo:BAABNQAECn8XAAIOAAcKNx10HgBdAgAOAAcKNx10HgBdAgAAAA==.Feru:BAAANQAECgUIBQAAAA==.Ferum:BAABNQAECn8wAAITAAoKCyV6AAC/AwATAAoKCyV6AAC/AwAAAA==.',
Fi='Fionnan:BAABNQAECn8sAAIeAAgKexI1DQAvAQAeAAgKexI1DQAvAQABNQAECgkJMQARAPgMAA==.Fizwidget:BAAANQADCgEIAQAAAA==.',
Fr='Freezia:BAAANQAECgYICgAAAA==.Frostigan:BAAANQAECgcIDAABNQAECgcIEgAQAAAAAA==.Fryeguy:BAAANQADCgQIBAAAAA==.',
Fu='Fudo:BAAANQAECgEIAQAAAA==.Fudoswrath:BAAANQAECgQIBgAAAA==.Funkysoup:BAAANQAECgUICwAAAA==.',
['Fò']='Fòrced:BAAANQADCgYIEAAAAA==.',
Ga='Gallium:BAAANQAECgIJAgAAAA==.',
Ge='Gehena:BAAANQAECgQIBAABNQAECgkJKgAbAFQeAQ==.Gemsareyum:BAAANQADCgIIAgABNQAFFAUIIAAbAL8gAA==.',
Gi='Girthquake:BAABNQAECn8WAAILAAYKkw2fpwBFAQALAAYKkw2fpwBFAQAAAA==.',
Gl='Glow:BAAANQADCggJCAAAAA==.',
Go='Goof:BAABNQAECn8iAAIfAAoKdwX1gwCPAQAfAAoKdwX1gwCPAQAAAA==.Goontaa:BAAANQAECgQIAQAAAA==.',
Gr='Griz:BAAANQAECgYIBgAAAA==.Grossevache:BAAANQADCgIIBAAAAA==.',
Ha='Haddor:BAAANQAECgYIEwAAAA==.Halfheart:BAAANQAECgUICwAAAA==.Hankerin:BAAANQADCgcIDgAAAA==.Harborhate:BAAANQAECgcIAgAAAA==.Harpomage:BAAANQADCggIEwAAAA==.Haunter:BAABNQAECn8fAAQEAAgKwx9nOABEAgAEAAgKwx9nOABEAgADAAcKaxd4QwC2AQAMAAUK7Q2+hADqAAAAAA==.',
He='Heimdallr:BAAANQADCggIEAAAAA==.Heisenborg:BAAANQAECgQIBAAAAA==.Helldin:BAAANQAECgEIAQAAAA==.',
Hi='Hidden:BAAANQADCgMIAwABNQAFFAUIDgAaAC8WAA==.Hilite:BAAANQAECgQICAAAAA==.Himothyjr:BAAANQADCgcICgAAAA==.',
Ho='Holific:BAABNQAECn8vAAINAAkKFBMHVAAdAQANAAkKFBMHVAAdAQAAAA==.Holymommy:BAAANQAECgIIBAABNQAECggIEQAQAAAAAA==.Hoss:BAAANQAECggIDAAAAA==.Hotrodranger:BAABNQAECn8qAAIbAAkKYRmBDQAGAgAbAAkKYRmBDQAGAgAAAA==.',
Hs='Hshyomouth:BAAANQADCgIIAgABNQAECgkJKgAbAGEZAA==.',
Hu='Hunters:BAAANQADCgYIBgAAAA==.Hut:BAACNQAFFH8WAAIHAAcKRxRXCAD+AQAHAAcKRxRXCAD+AQA1AAQKfzwAAgcACgqfJJMAAD8DAAcACgqfJJMAAD8DAAAA.',
Hy='Hypearione:BAAANQABCgEIAQAAAA==.',
Ia='Iambohike:BAAANQAECgEIAgAAAA==.',
Ic='Icycritties:BAABNQAECn8ZAAQGAAkKzw2VAwCJAQAGAAkKzw2VAwCJAQAFAAEKsgLl3wEkAAAcAAEKPQOIDwAiAAAAAA==.',
Ih='Iheals:BAAANQADCgIIAgAAAA==.',
Im='Imjustadruid:BAAANQADCgIIAgAAAA==.Immortal:BAABNQAECn8sAAIEAAgKdxCfEABXAQAEAAgKdxCfEABXAQAAAA==.',
In='Incarnated:BAABNQAECn8ZAAMEAAoKiiBmDQBOAwAEAAkKoiFmDQBOAwADAAYKiRg+DgCTAQAAAA==.',
Ir='Irís:BAAANQAECggIBwAAAA==.',
Is='Iskra:BAAANQADCgIIAgAAAA==.Ispithotfire:BAAANQABCgQIBgAAAA==.',
Iu='Iu:BAAANQAECggIEQAAAA==.',
Ja='Jackfash:BAAANQADCgMIBQAAAA==.Jadecross:BAAANQADCgIIAgAAAA==.Javan:BAAANQADCgIIAgAAAA==.',
Je='Jerryatric:BAABNQAECn8cAAINAAYKfg5q5ABSAQANAAYKfg5q5ABSAQAAAA==.',
Ji='Jiri:BAAANQABCgcIDwAAAA==.',
Jk='Jkmno:BAAANQADCgMIAwABNQADCgUIBQAQAAAAAA==.',
Jo='Joeyrains:BAAANQADCgQIBAAAAA==.',
Ju='Justblaze:BAAANQAECgQIBAAAAA==.Justincasê:BAAANQABCgMIBQAAAA==.',
Ka='Kallikan:BAABNQAECn8iAAIeAAgKPBOtDQApAQAeAAgKPBOtDQApAQAAAA==.Kamidk:BAAANQAECgYIDAABNQAECggIEQAQAAAAAA==.Kamuri:BAAANQADCgUIBQAAAA==.Kasteen:BAAANQAECgEIAQAAAA==.Katia:BAAANQAECgUIDQAAAA==.Kaøs:BAAANQAECgEIAgAAAA==.',
Kd='Kdoggparker:BAAANQABCgYICQAAAA==.',
Ke='Kelvox:BAAANQAECgQIBAAAAA==.Kementari:BAABNQAECn8YAAIHAAYKxgY0MwCQAAAHAAYKxgY0MwCQAAAAAA==.Kenzaki:BAABNQAECn8qAAINAAgKiBVRkwD9AQANAAgKiBVRkwD9AQAAAA==.',
Kh='Khaladin:BAAANQADCgYICAAAAA==.Khaosreborn:BAAANQADCgUIAQAAAA==.Khaotic:BAAANQADCggICgAAAA==.',
Ki='Kilaaz:BAABNQAECn8VAAINAAoK6hhjJACSAQANAAoK6hhjJACSAQAAAA==.Kirveka:BAAANQABCgQIBAAAAA==.',
Kl='Kliticaldk:BAAANQAECgIIBAAAAA==.Kliticalwar:BAABNQAECn8bAAIVAAoK7A+FSgAKAQAVAAoK7A+FSgAKAQAAAA==.Klothys:BAABNQAECn8eAAINAAkK0xriXQB/AgANAAkK0xriXQB/AgAAAA==.',
Kn='Knuts:BAAANQADCgMJAwABNQAECgYIBgAQAAAAAA==.',
Ko='Ková:BAAANQADCgUJCwAAAA==.',
Ku='Kuani:BAAANQAECgQIBAABNQAECgkJLQAXAA4bAA==.',
La='Landre:BAAANQADCgQIBgAAAA==.Lassy:BAAANQADCgIJAgAAAA==.Lathray:BAAANQAECgUIDgAAAA==.Lazerous:BAAANQADCggICgAAAA==.',
Le='Lealoo:BAABNQAECn8kAAINAAgK7BPGkQABAgANAAgK7BPGkQABAgAAAA==.Legolard:BAABNQAECn8WAAMZAAYKNh90EQAPAgAZAAYKNh90EQAPAgAVAAIKNwycMwFtAAAAAA==.Leleia:BAABNQAECn8WAAIIAAcKJwsFEAASAQAIAAcKJwsFEAASAQAAAA==.',
Lh='Lhera:BAABNQAECn8gAAMgAAgKsx9yDACpAgAgAAgKsx9yDACpAgARAAcKMRR/eACiAQABNQAECgoKKgAhAMUcAA==.',
Li='Liath:BAABNQAECn8VAAIJAAYKMREbOQAeAQAJAAYKMREbOQAeAQAAAA==.Lichtenberg:BAABNQAECn8xAAMLAAkK/B37EQCHAQALAAkK/B37EQCHAQARAAUKxwjL1AC9AAAAAA==.Linddori:BAAANQAECgUIDwABNQAECggIIgACADMYAA==.Liori:BAAANQADCggIHwAAAA==.Lirillia:BAABNQAECn8iAAQCAAgKMxg5CgBTAgACAAgKMxg5CgBTAgASAAYKjQm20AAoAQAiAAEKAACoMAA0AAAAAA==.Lirillïa:BAAANQADCgYICwABNQAECggIIgACADMYAA==.Lizzie:BAAANQADCgUIBQAAAA==.',
Lo='Locdon:BAAANQABCgIIAgABNQAECgUICAAQAAAAAA==.Lodestone:BAAANQADCggICgAAAA==.Loena:BAAANQAECgYICAAAAA==.Lokk:BAAANQAECgEIAQABNQAECggIJAAbAOIaAA==.Loko:BAAANQAECgEIAQAAAA==.Lolowbeatz:BAAANQADCgIIAgAAAA==.Lovelydread:BAAANQAECgEIAQAAAA==.',
Lu='Lunabug:BAAANQAECgIIAgAAAA==.Lupinos:BAAANQADCgIIAQAAAA==.',
Ly='Lyadra:BAABNQAECn8kAAIJAAgKmh/9DAAZAgAJAAgKmh/9DAAZAgAAAA==.Lyrissa:BAAANQADCgYIBgAAAA==.',
['Lõ']='Lõst:BAAANQAECgIIAwAAAA==.',
Ma='Mackito:BAABNQAFFH8OAAIbAAgKHgFIEwBmAAAbAAgKHgFIEwBmAAAAAA==.Madan:BAABNQAECn8UAAIEAAYKuAYPKgC7AAAEAAYKuAYPKgC7AAAAAA==.Mahoushojou:BAAANQAECgIIAgABNQAECgcIEgAQAAAAAA==.Malasminna:BAAANQAECgYIEgAAAA==.Malehorelock:BAAANQAECgEIAQAAAA==.Malicioun:BAAANQABCggIDgAAAA==.Malkariss:BAABNQAECn8eAAMFAAgK4xpSSQApAQAFAAYKNhtSSQApAQAGAAQKORnYGwARAQAAAA==.Mammadruid:BAABNQAECn8bAAIeAAYKeAufMgALAQAeAAYKeAufMgALAQAAAA==.Mauldis:BAABNQAECn8fAAMLAAgKMAX6pQBIAQALAAgKMAX6pQBIAQARAAUKtQJjdQBoAAAAAA==.',
Me='Meryl:BAABNQAECn8wAAIfAAkKYxi2PAByAgAfAAkKYxi2PAByAgAAAA==.',
Mi='Miaka:BAABNQAECn8vAAIiAAkKRhqgAwC4AgAiAAkKRhqgAwC4AgAAAA==.Minth:BAAANQADCgcIDQABNQAECgcIEgAQAAAAAA==.Miraakle:BAAANQAECgQIBwABNQAECgcIEgAQAAAAAA==.Misfire:BAABNQAECn8sAAIbAAgKTRJQKQB1AQAbAAgKTRJQKQB1AQAAAA==.Mithra:BAAANQAECgQICQAAAA==.',
Mo='Moghroth:BAABNQAECn8qAAMHAAkKagoNEABZAQAHAAkKagoNEABZAQAeAAEK1wQOZQAqAAAAAA==.Molykote:BAAANQAECggIDAAAAA==.Monks:BAAANQADCgQIBAAAAA==.Monsterbabe:BAAANQADCgUICgAAAA==.Moreleath:BAAANQADCgMIBAAAAA==.Morphias:BAAANQADCgQIBAAAAA==.Mowiewowie:BAAANQABCgIIAgAAAA==.',
Mu='Mugzypatron:BAAANQADCggIIwAAAA==.Murdrmitts:BAAANQAECgYIEAAAAA==.',
['Mã']='Mãtador:BAACNQAFFH8GAAILAAQK5BbnEABdAQALAAQK5BbnEABdAQA1AAQKfyIAAwsACQrLIBAgAAsDAAsACQrLIBAgAAsDABEAAwo3EJv6AHUAAAAA.',
['Mä']='Mätadør:BAABNQAECn8UAAIIAAgKFxs2IgAjAgAIAAgKFxs2IgAjAgABNQAFFAQIBgALAOQWAA==.',
Na='Nahryn:BAABNQAECn8fAAITAAgKzhzSBQD5AQATAAgKzhzSBQD5AQAAAA==.',
Ne='Nedina:BAAANQADCgUIBQAAAA==.Nerbert:BAAANQADCgYJBgABNQAECgoKMgAUAFESAA==.Neretsym:BAABNQAECn8rAAIbAAgKdhDoJQCCAQAbAAgKdhDoJQCCAQAAAA==.',
Ni='Nineva:BAAANQAECgYIEAAAAA==.',
No='Nobas:BAABNQAECn8xAAIHAAkKXQj6IwDXAAAHAAkKXQj6IwDXAAAAAA==.Nonoa:BAAANQAECgEIAgAAAA==.',
Oc='Octavien:BAAANQADCgIIAgAAAA==.',
Og='Ogr:BAAANQADCgMIAwAAAA==.',
On='Onlyfeet:BAAANQAECggIEQAAAA==.',
Op='Oppgjør:BAAANQAECgEIAQAAAA==.',
Or='Oreeree:BAAANQAECgMIBAAAAA==.Ormr:BAABNQAECn8yAAMUAAoKURKuAgCeAQAUAAoKURKuAgCeAQAdAAEKAABPIwA5AAAAAA==.',
Os='Osteo:BAABNQAECn8mAAMCAAcKTwajJwA7AQACAAcK2wSjJwA7AQASAAcK+QXYYwC7AAAAAA==.Osteoprime:BAAANQADCgUJBQAAAA==.',
Ou='Ouron:BAABNQAECn8kAAIRAAoKiBXmPQBoAgARAAoKiBXmPQBoAgAAAA==.Outofmana:BAAANQAECgQIDQAAAA==.',
Ov='Ovelia:BAAANQAECgUIBAAAAA==.',
Pa='Pagoda:BAAANQADCgYJBgAAAA==.Papashrimps:BAACNQAFFH8PAAIFAAQKKxSfDwDiAAAFAAQKKxSfDwDiAAA1AAQKfyUAAwUACgqHGISWAFMCAAUACgqXF4SWAFMCAAYAAQoxGmQ/AEYAAAAA.',
Pe='Penelopee:BAAANQADCggIHgAAAA==.Percy:BAAANQADCggIGQAAAA==.',
Ph='Phatcow:BAAANQADCgEIAQAAAA==.',
Pl='Placeholder:BAABNQAECn8qAAIjAAkKoB+BAQB4AgAjAAkKoB+BAQB4AgAAAA==.',
Po='Pojoevokest:BAABNQAECn8WAAIaAAgKhAlzKwBPAQAaAAgKhAlzKwBPAQAAAA==.Pontifex:BAABNQAECn8pAAIJAAgKqxfIGQCnAQAJAAgKqxfIGQCnAQAAAA==.Portandmorph:BAABNQAECn8ZAAIGAAgK6xOWCwAHAgAGAAgK6xOWCwAHAgAAAA==.Powerbottm:BAAANQAECgYIDAAAAA==.',
Pr='Priests:BAAANQADCgQIBgAAAA==.Prone:BAABNQAECn8xAAMRAAkK+Ay2SQDOAAARAAgK7wm2SQDOAAALAAMKlQPOGgFaAAAAAA==.Protarada:BAAANQAECgEIAQAAAA==.',
Qu='Quietmind:BAAANQAECgcIDwAAAA==.',
Ra='Raakotah:BAABNQAECn8vAAIHAAoKOCL4DQBbAwAHAAoKOCL4DQBbAwAAAA==.Raasclaat:BAAANQADCgcIDQAAAA==.Raelo:BAABNQAECn8pAAIgAAkKXgxkBADDAQAgAAkKXgxkBADDAQAAAA==.Rainbowflake:BAABNQAECn8VAAIbAAcK3wIbAgEBAQAbAAcK3wIbAgEBAQAAAA==.Raiseurmug:BAABNQAECn8kAAIYAAkKkBHTEADcAQAYAAkKkBHTEADcAQAAAA==.Rakash:BAAANQADCgcIBwAAAA==.Rarg:BAABNQAECn8VAAMMAAgKlRnWSgDMAQAMAAgKlRnWSgDMAQAEAAEK6QLn8gAkAAAAAA==.Ravia:BAAANQAFFAEIAQAAAA==.',
Re='Rendysavage:BAAANQAECgYJBgAAAA==.Resco:BAAANQADCggIEgAAAA==.',
Ri='Riddle:BAABNQAECn8cAAIRAAkKHwuShwB3AQARAAkKHwuShwB3AQAAAA==.Rimeouo:BAAANQAECgYIBQAAAA==.Rize:BAABNQAECn8YAAIVAAgK/w++mgDaAQAVAAgK/w++mgDaAQABNQAECgoKMwAUAH0OAA==.Rizmthetizm:BAAANQADCgEIAQAAAA==.',
Ro='Rosenrott:BAABNQAECn8qAAIbAAkKVB77BgBZAgAbAAkKVB77BgBZAgAAAA==.Rosepiercer:BAABNQAECn8XAAIbAAgKrx2bVABzAgAbAAgKrx2bVABzAgAAAA==.Rouz:BAABNQAECn8bAAIUAAcKhglVBwAEAQAUAAcKhglVBwAEAQAAAA==.',
Ru='Ruddybear:BAAANQADCgIJAgAAAA==.',
Ry='Ryoto:BAAANQAECgUICAAAAA==.',
Sa='Sadarasdeath:BAAANQADCgUICQAAAA==.Samandean:BAABNQAECn8eAAIPAAgKPA57JADhAAAPAAgKPA57JADhAAABNQAECggIJAANAOwTAA==.Sarasvati:BAAANQAECgMIAwAAAA==.Sariia:BAAANQADCgMIAQABNQAECgoKOgAOAJAeAA==.',
Se='Sellena:BAAANQAECgUIEAABNQAECggIJAANAOwTAA==.',
Sh='Shakenn:BAAANQADCgEIAQAAAA==.Shandow:BAABNQAECn86AAIGAAoK5Rx2AwAPAwAGAAoK5Rx2AwAPAwAAAA==.Shansoracle:BAABNQAECn8ZAAMJAAoKohnvAwDtAgAJAAoKohnvAwDtAgAIAAEKaAP7ggAmAAABNQAECgoKOgAGAOUcAA==.Shed:BAAANQAECgQIBAABNQAFFAcIFgAHAEcUAA==.Sheislegend:BAAANQADCggIFgAAAA==.Shelby:BAABNQAECn8gAAIJAAcK3R+EQQBlAgAJAAcK3R+EQQBlAgAAAA==.Shocked:BAAANQAECggIAwABNQAECggIDAAQAAAAAA==.Shockolate:BAAANQADCggICAAAAA==.',
Si='Siarn:BAAANQADCgMIBQAAAA==.Siccinok:BAABNQAECn8rAAMFAAgKBhsyKAB3AQAFAAgKJhkyKAB3AQAGAAQKwx2kIADkAAAAAA==.Sixhundrdlbs:BAACNQAFFH8NAAIOAAQKUh1+AgALAQAOAAQKUh1+AgALAQA1AAQKfzMAAw4ACgp/I7ADAJ0DAA4ACgp/I7ADAJ0DAA8AAQqYChdSADMAAAE1AAQKCgoZAAQAiiAA.',
Sk='Skraps:BAAANQADCgEJAQAAAA==.',
Sl='Slimped:BAAANQADCgYICwAAAA==.',
Sn='Sneakybato:BAAANQADCggIFwAAAA==.',
So='Sofie:BAAANQADCgQIBAABNQAECgkJMQALAPwdAA==.Solarial:BAAANQAECgUIEAAAAA==.Solastra:BAABNQAECn8kAAIfAAgK0RWgDQDyAQAfAAgK0RWgDQDyAQAAAA==.Soramai:BAAANQAECgMIAwAAAA==.Soth:BAABNQAECn8xAAMEAAkKqxQRSgDtAQAEAAkKqxQRSgDtAQAMAAgKxhFyVgCaAQAAAA==.',
Sp='Sparký:BAABNQAECn8XAAISAAoKaSFIBQBoAgASAAoKaSFIBQBoAgAAAA==.Spinnycrisp:BAAANQADCgYIBgAAAA==.',
St='Starlyvana:BAACNQAFFH8OAAMGAAQKLw5vAQDNAAAGAAMKLw5vAQDNAAAFAAIKlwdOLAAAAAA1AAQKfxcAAgYACgpDFcsHAG8CAAYACgpDFcsHAG8CAAAA.Staryxia:BAABNQAECn8XAAIDAAkKSh1KNgD/AQADAAkKSh1KNgD/AQAAAA==.Statiic:BAAANQABCgIIBQAAAA==.Steamdruid:BAAANQADCggIDwABNQAECgoKJQAOAAATAA==.Steephany:BAAANQADCgMIBwAAAA==.Stonecross:BAABNQAECn8eAAIJAAkKDxv4GgCgAQAJAAkKDxv4GgCgAQAAAA==.Stormbolt:BAABNQAECn8mAAIHAAkK3gpYTgCmAQAHAAkK3gpYTgCmAQAAAA==.Stormspirit:BAAANQADCggIHQAAAA==.Striggen:BAAANQAECgUIDQAAAA==.',
Su='Sugarsham:BAABNQAECn8gAAILAAkKlAvJcgDIAQALAAkKlAvJcgDIAQAAAA==.Sulwen:BAACNQAFFH8WAAIHAAcKAiZnAQDwAgAHAAcKAiZnAQDwAgA1AAQKfyYAAgcACgpiJs0EALMDAAcACgpiJs0EALMDAAAA.Sumerset:BAAANQAECgcIEgAAAA==.Sundave:BAAANQAECgEJAgAAAA==.Supaflytnt:BAABNQAECn8iAAIkAAcKiBQ9BACLAQAkAAcKiBQ9BACLAQAAAA==.Sustia:BAAANQAECgQICAAAAA==.',
Ta='Taera:BAABNQAECn8tAAIXAAkKDhupAQCTAgAXAAkKDhupAQCTAgAAAA==.Talavenn:BAABNQAECn8kAAIOAAkK0B2uEQDgAgAOAAkK0B2uEQDgAgAAAA==.Tanglock:BAAANQAECgMIAwAAAA==.Tarage:BAAANQAECgQICQAAAA==.Taurîel:BAAANQADCgYIBgAAAA==.',
Te='Tectoniiks:BAAANQAECgcIBwAAAA==.Tedds:BAAANQAECgUJCAAAAA==.Teds:BAAANQADCgYICwAAAA==.Tempus:BAAANQAECgMJAwAAAA==.Teriko:BAABNQAECn8lAAIDAAgKFRsVLQA3AgADAAgKFRsVLQA3AgAAAA==.Teviro:BAAANQADCgIIAgABNQAECgoKKgAhAMUcAA==.',
Th='Thequixote:BAABNQAECn8TAAIkAAYKehW/FQCfAQAkAAYKehW/FQCfAQAAAA==.',
Ti='Tictok:BAAANQADCgYICgAAAA==.',
To='Toaderic:BAAANQAECgUIDwAAAA==.Tots:BAABNQAECn8yAAIeAAoKdhw3AQCoAgAeAAoKdhw3AQCoAgAAAA==.Toxictotes:BAAANQADCgYICQAAAA==.',
Tr='Trazah:BAAANQADCgEIAQAAAA==.',
Ty='Tyraèl:BAABNQAECn8kAAIfAAoKGyMBCACJAwAfAAoKGyMBCACJAwAAAA==.Tyzy:BAACNQAFFH8MAAMHAAQK8CPMAwBFAQAHAAQK8CPMAwBFAQATAAIKHCMLDgDJAAA1AAQKfycAAwcACgrMI/YNAFsDAAcACgrMI/YNAFsDABMACAo0HJkXAIQCAAAA.',
Um='Umber:BAAANQADCggICAAAAA==.',
Va='Valenora:BAABNQAECn8iAAICAAkKkhUDBgCwAgACAAkKkhUDBgCwAgAAAA==.Valvitor:BAAANQADCgEIAQAAAA==.Varuz:BAABNQAECn8kAAIbAAgK4hphHQCiAQAbAAgK4hphHQCiAQAAAA==.Varyz:BAAANQADCgIIAgABNQAECggIJAAbAOIaAA==.',
Ve='Velanie:BAAANQAECgEIAQAAAA==.Veloon:BAABNQAECn8bAAIHAAkKIg7hQgDqAQAHAAkKIg7hQgDqAQAAAA==.Verinari:BAAANQAECgQICQAAAA==.',
Vi='Vipul:BAAANQADCgUIDQABNQADCgYIBwAQAAAAAA==.Viridria:BAAANQAECgcIEgAAAA==.Vityazi:BAAANQAECgYIDQAAAA==.',
Vl='Vlado:BAAANQADCgUIBgAAAA==.',
Vo='Voodoobootie:BAAANQABCgcJBwAAAA==.',
Vy='Vy:BAAANQADCgUICQAAAA==.',
['Vè']='Vè:BAABNQAECn8nAAIeAAkKqxAbGgDWAQAeAAkKqxAbGgDWAQAAAA==.',
Wa='Warriors:BAABNQAECn87AAIVAAoKZCJhAQAyAwAVAAoKZCJhAQAyAwAAAA==.Wartooth:BAABNQAECn8kAAMSAAgKNBWCIQBoAQASAAgKlg2CIQBoAQACAAQKiBgvKQAxAQAAAA==.Wassergott:BAAANQAECgEIAQAAAA==.',
We='Webicus:BAAANQAECgYIEAAAAA==.Wendee:BAABNQAECn8eAAMJAAgKggTuSQDpAAAJAAgKggTuSQDpAAAIAAEKAABKlAATAAAAAA==.',
Wh='Whitley:BAABNQAECn8qAAMRAAkKiSG6DAD+AQARAAkKiSG6DAD+AQALAAcKfRThbgDTAQAAAA==.',
Wi='Wildspart:BAAANQAECgYIDAAAAA==.',
Wo='Wooden:BAABNQAECn8hAAIbAAgKzBrBFgDBAQAbAAgKzBrBFgDBAQAAAA==.',
Xa='Xaphy:BAABNQAECn8XAAMIAAkKOg8gDwAbAQAIAAcKNg0gDwAbAQAJAAUKRhaobgCJAAAAAA==.Xardots:BAABNQAECn8aAAICAAcKthN8EgDhAQACAAcKthN8EgDhAQABNQAECggIIgAQAAAAAA==.',
Xi='Xiareth:BAABNQAECn8fAAIaAAcKPhFfBgBrAQAaAAcKPhFfBgBrAQAAAA==.',
Xy='Xyleiah:BAAANQADCgYIBgABNQAECgkJMQAUAAQXAA==.',
['Xá']='Xároth:BAAANQAECggIIgAAAQ==.',
Ya='Yargue:BAABNQAECn8YAAIIAAkKHg9gEAAOAQAIAAkKHg9gEAAOAQAAAA==.',
Ye='Yeeyee:BAAANQAECggIDAAAAA==.',
Yi='Yirï:BAAANQABCgQIBgAAAA==.',
Yo='Youngjeezy:BAAANQAECgUICgAAAA==.Yoursinpride:BAAANQAECggIDgAAAA==.',
Za='Zackor:BAAANQADCgUIDAAAAA==.',
Ze='Ze:BAAANQADCgYICgAAAA==.Zervann:BAAANQADCgYIBgAAAA==.',
Zi='Ziska:BAAANQADCgIIAgAAAA==.',
Zo='Zorithic:BAAANQAECgIJAwAAAA==.',
Zu='Zuldan:BAAANQADCgIIAgAAAA==.',
Zy='Zyde:BAAANQAECgIIAQABNQAECggIJAAbAOIaAA==.',
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
