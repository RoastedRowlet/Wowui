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

local lookup = {'Mage-Frost','Priest-Holy','Priest-Shadow','Unknown-Unknown','Mage-Arcane','Druid-Restoration','Hunter-BeastMastery','Warrior-Protection','Hunter-Marksmanship','Druid-Guardian','Paladin-Protection','Paladin-Holy','Rogue-Assassination','Rogue-Subtlety','Druid-Balance','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Rogue-Outlaw','Paladin-Retribution','Monk-Mistweaver','Warrior-Arms','DeathKnight-Frost','DeathKnight-Blood','Warlock-Demonology','Monk-Windwalker','DemonHunter-Havoc','DemonHunter-Devourer','Warrior-Fury','DeathKnight-Unholy','Warlock-Affliction','Priest-Discipline','Warlock-Destruction','Hunter-Survival','DemonHunter-Vengeance','Monk-Brewmaster','Druid-Feral',}
local provider = {region='US',realm='EarthenRing',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abrothael:BAABNQAECn8eAAIBAAgK8xEyDQDcAQABAAgK8xEyDQDcAQAAAA==.',
Ac='Actanonverba:BAAANQAECgEIAQAAAA==.',
Ad='Adorèè:BAABNQAECn8aAAMCAAcKrQuJjQBpAQACAAcKrQuJjQBpAQADAAYKmQP1TgDTAAAAAA==.',
Ae='Aedelas:BAAANQADCgQIBAAAAA==.Aelinpeepo:BAAANQAECgEIAQABNQAECgMJAwAEAAAAAA==.Aestua:BAAANQADCgUICgAAAA==.Aetheros:BAACNQAFFH8KAAIFAAQKoBBvKQA3AQAFAAQKoBBvKQA3AQA1AAQKfzQAAgUACQpGHoc0ACEDAAUACQpGHoc0ACEDAAAA.',
Ag='Agarim:BAAANQADCgQICAAAAA==.',
Ai='Airlinna:BAABNQAECn8yAAIGAAkKyRkWFQCbAgAGAAkKyRkWFQCbAgAAAA==.Airoach:BAAANQAECgIIAgAAAA==.',
Ak='Akers:BAAANQADCggICwABNQAECggIHAAHAEMHAA==.',
Al='Alaraen:BAABNQAECn8aAAIIAAcKPRZPGQCZAQAIAAcKPRZPGQCZAQAAAA==.Alcremie:BAAANQAECgIIAwABNQAFFAYIEwAJAJMfAA==.Aleman:BAAANQADCgYIEAAAAA==.Aleve:BAAANQADCgIIAgAAAA==.Alexxandria:BAAANQADCggJCwAAAA==.Aleyah:BAAANQAECgUJBQAAAA==.Almarii:BAABNQAECn8ZAAMBAAYKwBNYIgDVAAAFAAYK9RI3DAF1AQABAAMK7RNYIgDVAAAAAA==.Alraune:BAABNQAECn8qAAIKAAkK9yITAwCKAwAKAAkK9yITAwCKAwAAAA==.Alynndra:BAAANQAECgUIEAAAAA==.Alyssazoe:BAAANQADCgIIBAAAAA==.',
Am='Ambler:BAAANQADCgcIFAAAAA==.',
An='Anarionhunts:BAAANQAECgcIDgAAAA==.Andius:BAAANQAECgEIAQAAAA==.Andoric:BAAANQABCgYICAAAAA==.Anirra:BAABNQAECn8WAAILAAYKPQlAQQDuAAALAAYKPQlAQQDuAAAAAA==.Annaraeliri:BAAANQADCggICwAAAA==.',
Ap='Apert:BAABNQAECn8gAAIMAAcKtyaJFwAbAwAMAAcKtyaJFwAbAwAAAA==.Apnea:BAAANQADCgIIAgAAAA==.Appa:BAAANQADCgUICQAAAA==.',
Ar='Ardenweald:BAABNQAECn8wAAMGAAkKwB3yDAD8AgAGAAkKwB3yDAD8AgAKAAcKFRHJJQBiAQAAAA==.Aretok:BAAANQADCgYIBgAAAA==.Armyokittens:BAAANQAECgEIAQAAAA==.Arroezze:BAAANQADCgYIBQAAAA==.Arthurin:BAAANQAECgQICgAAAA==.',
As='Ashaleth:BAAANQADCgUIBQAAAA==.Ashayo:BAAANQADCggIFAAAAA==.Asphodel:BAAANQAECgUIBQAAAA==.Astrana:BAABNQAECn8oAAIHAAgKUREUdAAlAgAHAAgKUREUdAAlAgAAAA==.',
At='Athelstan:BAAANQADCgcIBwAAAA==.',
Au='Augkward:BAAANQAECgUICAABNQAFFAYIEAACAJ4YAA==.Aureldor:BAAANQADCgMIAwAAAA==.Automatic:BAABNQAECn8lAAMNAAkKwh7RDQARAwANAAkKjh7RDQARAwAOAAMKWh3qOADrAAAAAA==.Autoshot:BAAANQADCgMIBAAAAA==.',
Av='Avorek:BAAANQADCgYICwAAAA==.Avorik:BAAANQAECgUIEQAAAA==.Avouric:BAAANQAECgQIBQAAAA==.Avourik:BAAANQAECgYIBwAAAA==.',
Az='Azaree:BAAANQAECgQJCgAAAA==.Azndak:BAAANQADCgcJBwAAAA==.',
Ba='Baelzabob:BAAANQAECgEIAQAAAA==.Bakaran:BAAANQADCgUJBQAAAA==.Barae:BAAANQAECgEIAQAAAA==.Barboosa:BAAANQAECgEIAQAAAA==.Barcmaul:BAAANQAECgUIDQAAAA==.Bathzalts:BAAANQADCgYIBQAAAA==.Baylel:BAAANQAECgUIEAAAAA==.',
Bb='Bbqmonk:BAAANQADCggICAABNQAECgYIEgAEAAAAAA==.Bbqpriest:BAAANQADCggICAAAAA==.',
Be='Bearbq:BAAANQAECgYIEgAAAA==.Belledolphin:BAAANQAECgcIDgAAAA==.Bellgold:BAAANQADCgYIBgABNQAECggIGgAHAC0IAA==.Berigo:BAABNQAECn8XAAMGAAgKmhBmKQDQAQAGAAgKmhBmKQDQAQAPAAEKAADFxQAaAAAAAA==.Betth:BAAANQADCgIIAgAAAA==.Bezvoker:BAABNQAECn8gAAQQAAgKnBQSGwAUAgAQAAgKnBQSGwAUAgARAAYK7xBnDwBGAQASAAMKPAkGMACVAAAAAA==.Beárwithme:BAAANQADCgQICAAAAA==.',
Bi='Birria:BAAANQADCgQICQABNQADCgYIGQAEAAAAAA==.',
Bj='Bjordrann:BAAANQADCgEIAQAAAA==.',
Bl='Blackhoofcow:BAAANQAECgUIDAAAAA==.Blackicewolf:BAABNQAECn8eAAITAAgKhCMKCwC+AgATAAgKhCMKCwC+AgAAAA==.Bleake:BAAANQADCgUIBQAAAA==.Bleunienn:BAAANQADCgYIBgAAAA==.Blueberrypie:BAAANQAECgUICAAAAA==.',
Bo='Bohah:BAAANQADCgYIBgAAAA==.Bonbarrion:BAEBNQAECn8yAAQUAAkKox08KQDZAgAUAAgKShw8KQDZAgAVAAYKYg5RnAA8AQATAAIK5RTiLACRAAAAAA==.Borbory:BAABNQAECn8gAAIVAAgKViCkIgDbAgAVAAgKViCkIgDbAgAAAA==.Boringhuman:BAAANQAECgYIEQAAAA==.Borlorín:BAAANQADCgYIBgAAAA==.Borogove:BAAANQADCgYIDAAAAA==.',
Br='Brasca:BAABNQAECn8hAAISAAcKwRmZEQA4AgASAAcKwRmZEQA4AgAAAA==.Brisketdk:BAAANQAECgIIAgABNQAECgYIEgAEAAAAAA==.Bruhmal:BAABNQAECn8aAAMPAAgKWR7hGgDwAgAPAAgKWR7hGgDwAgAGAAEKQhl7bABMAAAAAA==.Brunner:BAAANQADCgIIAgAAAA==.Brynndolin:BAABNQAECn8hAAMPAAcKyBJESwC0AQAPAAcKyBJESwC0AQAGAAMKVAwGYACAAAAAAA==.',
Bu='Burzolog:BAABNQAECn8rAAQOAAkKABPzFAA9AgAOAAkKnRLzFAA9AgAWAAUKfAphEgDeAAANAAEKTgtuogAwAAAAAA==.',
['Bä']='Bärk:BAABNQAECn9WAAMPAAkKdB++EQA3AwAPAAkKdB++EQA3AwAGAAQKcBN4RgD4AAAAAA==.',
['Bö']='Böldly:BAAANQAECgIIAgAAAA==.Börk:BAAANQAECgYIBgAAAA==.',
Ca='Calanash:BAAANQAECgUIBQABNQAECggIHAAXALcWAA==.Calazan:BAABNQAECn8cAAIXAAgKtxZmgAAjAgAXAAgKtxZmgAAjAgAAAA==.Calazil:BAAANQADCgQIBAABNQAECggIHAAXALcWAA==.Calethron:BAAANQADCgUICgAAAA==.Calladan:BAAANQAECgIIAgAAAA==.Calliel:BAAANQADCgcIBwAAAA==.Carlos:BAAANQADCgUIBgAAAA==.Cascious:BAAANQAECgEIAQABNQAFFAYIEwAGAB0PAA==.Casylla:BAAANQADCgMJAwAAAA==.Cazym:BAAANQADCggICAABNQAECggIBgAEAAAAAA==.',
Ce='Cedarjr:BAAANQAECgMIBAAAAA==.Cef:BAABNQAECn8aAAIYAAgKShrCEQBdAgAYAAgKShrCEQBdAgAAAA==.Ceftoration:BAAANQADCgQIBQABNQAECggIGgAYAEoaAA==.Celindre:BAAANQAECgQIBgAAAA==.',
Ch='Cherrybomb:BAAANQADCgIIAgAAAA==.Chewbie:BAAANQAECgIIAgAAAA==.Chickentendi:BAAANQADCgQIBAABNQAECgcIIQARALUWAA==.Choonjung:BAAANQAECggIBwAAAA==.Chronis:BAAANQAECgIIAwAAAA==.',
Ci='Ciphon:BAAANQAECgQIBgAAAA==.Cirok:BAAANQADCgcIEwAAAA==.Civic:BAAANQAECgYIEQAAAA==.',
Ck='Cklyde:BAACNQAFFH8KAAIMAAQKzRZSEABYAQAMAAQKzRZSEABYAQA1AAQKfy8AAgwACQoPIUMQAEkDAAwACQoPIUMQAEkDAAAA.',
Cl='Claiyre:BAAANQAECgYIEQAAAA==.Clewis:BAAANQABCgUICAAAAA==.Clubble:BAAANQAECgMJBAAAAA==.Clumperton:BAACNQAFFH8GAAIHAAMKoBVGFAAaAQAHAAMKoBVGFAAaAQA1AAQKfx0AAgcACQpgH/cuAN4CAAcACQpgH/cuAN4CAAAA.Clãsh:BAAANQAECgIIBAAAAA==.',
Co='Cochino:BAABNQAECn8YAAMHAAkKGiKdFABKAwAHAAkKGiKdFABKAwAJAAEKFxYDgABAAAAAAA==.Concentrate:BAAANQAECgcIHwAAAQ==.Connan:BAABNQAECn8aAAIZAAgKUyBsRAC5AgAZAAgKUyBsRAC5AgABNQAECgkJKwAVADYlAA==.Constant:BAAANQAECgQICAAAAA==.Corbesan:BAAANQAECgYIBgABNQAECggIGAAUAPIVAA==.Cordrann:BAAANQADCggIIgAAAA==.Coveness:BAAANQAECgEIAQAAAA==.Cowi:BAACNQAFFH8KAAIVAAQKahMkEABIAQAVAAQKahMkEABIAQA1AAQKfy0AAhUACQrzIZoNAFMDABUACQrzIZoNAFMDAAAA.',
Cr='Crasusakechi:BAAANQAECgUICwAAAA==.Crisisangel:BAAANQADCggIAgAAAA==.Crossnover:BAAANQAECgQIBAABNQAECgkJMwAHAA0aAA==.Cryomagus:BAABNQAECn8xAAMaAAkK7xd0LgApAgAaAAgKPhp0LgApAgAbAAkKdQ0ETQC/AQAAAA==.',
Cu='Cuqquiform:BAABNQAECn8nAAMGAAkKdiOdCwANAwAGAAgKgSOdCwANAwAPAAcKqhdhNwAuAgAAAA==.',
Cy='Cylesia:BAAANQAECgEIAQAAAA==.Cylthia:BAAANQAECgMIAwAAAA==.Cyrienna:BAAANQADCgYICQAAAA==.',
Da='Daemata:BAAANQAECgEIAgAAAA==.Dajinbo:BAAANQAECgQIBwAAAA==.Dalarium:BAAANQAECgEIAQAAAA==.Damarq:BAAANQABCgYIBgAAAA==.Damons:BAAANQAECgYICQABNQAECgkJKwAPAPkgAA==.Dankinia:BAAANQADCgUIEgAAAA==.Darchlo:BAAANQADCgEIAQAAAA==.Darkhammer:BAAANQAECggIEgAAAA==.Darkswift:BAACNQAFFH8KAAIXAAQKCR00DwBRAQAXAAQKCR00DwBRAQA1AAQKfzQAAhcACQr7ISkjADYDABcACQr7ISkjADYDAAAA.Darnadda:BAAANQAECgQICAAAAA==.Darowyn:BAABNQAECn8fAAIHAAgKdhOecgApAgAHAAgKdhOecgApAgAAAA==.Dashiell:BAAANQAECgcIDgABNQAECggIGAAUAPIVAA==.Dawnflare:BAAANQAECggICQABNQAECgkJHgAVAC0bAA==.',
De='Deafdog:BAAANQADCgcIBwAAAA==.Deathryder:BAAANQADCggICAAAAA==.Deaxus:BAAANQAECgQIDgABNQAECgkJNAAcAFsWAA==.Deb:BAABNQAECn8YAAIPAAYK0Rz+PwD4AQAPAAYK0Rz+PwD4AQAAAA==.Defacer:BAAANQABCgYIBgAAAA==.Defame:BAAANQADCgEIAgABNQAECggIIAAXACwOAA==.Delailia:BAAANQADCggIFgAAAA==.Delbelfine:BAACNQAFFH8KAAIMAAQK2woOFAAbAQAMAAQK2woOFAAbAQA1AAQKfygAAgwACQoNEx9PACwCAAwACQoNEx9PACwCAAAA.Delfar:BAAANQADCgUIBQAAAA==.Delimeats:BAAANQAECggICwAAAA==.Delisomethng:BAABNQAECn8WAAIUAAcKRAqKlABtAQAUAAcKRAqKlABtAQAAAA==.Dellechero:BAAANQAECggICwAAAA==.Demilich:BAAANQAECgUICwAAAA==.Demonra:BAAANQADCgMIAwAAAA==.Despaira:BAAANQAECgcIEwAAAA==.Dethyler:BAABNQAECn8gAAIWAAgKkBjnBgBUAgAWAAgKkBjnBgBUAgAAAA==.Devilwoman:BAAANQAECgYIDgAAAA==.Deylil:BAAANQADCgYIBgABNQAECgcIHgALAGMdAA==.Deyv:BAABNQAECn8gAAIXAAgKLA4stACwAQAXAAgKLA4stACwAQAAAA==.',
Di='Diancie:BAAANQAECgIIAgABNQAFFAYIEwAJAJMfAA==.Diddibeau:BAABNQAECn8ZAAIHAAYKoQoJxgBxAQAHAAYKoQoJxgBxAQAAAA==.Diddiblind:BAAANQADCgMIBgABNQAECgYIGQAHAKEKAA==.Diego:BAAANQADCgEIAQAAAA==.Divinezanon:BAAANQAFFAIIBAABNQAFFAYIFwAGAKMXAA==.',
Do='Dontyagnomie:BAABNQAECn8aAAIYAAYKKCBRFgATAgAYAAYKKCBRFgATAgAAAA==.Doobu:BAAANQADCgcIHQAAAA==.Dooganitis:BAAANQAECgYIDwAAAA==.Dorne:BAAANQADCggIDwAAAA==.Doruk:BAAANQAECgQIBAAAAA==.',
Dr='Drayden:BAAANQABCggIDAAAAA==.Dreamsoul:BAAANQABCgQIBQAAAA==.Drfeelgreat:BAAANQADCgIIAwAAAA==.',
Du='Duckie:BAAANQAECgEIAQABNQAECgMJAwAEAAAAAA==.Dullahstrasz:BAAANQADCgYIBgAAAA==.Dusksorrow:BAAANQADCgUIBQAAAA==.',
Dz='Dzud:BAAANQADCgUIBQAAAA==.',
Ed='Edovard:BAAANQAECgIIBAAAAA==.',
Ee='Ee:BAAANQAECgUICgAAAA==.Eeragon:BAAANQAECgMIAwAAAA==.',
Ef='Efitzherbert:BAAANQAECgUICgAAAA==.',
El='Elentari:BAAANQABCgUIBQAAAA==.Elfshadow:BAAANQABCgQIAwAAAA==.Eliyon:BAAANQAECgUIDQAAAA==.Ellarinya:BAAANQADCgYICwAAAA==.Ellemir:BAAANQAECgEIAQAAAA==.Elshifty:BAAANQADCgcIBwABNQAECggIAQAEAAAAAA==.Eltanari:BAAANQAECgIIBAAAAA==.Eluera:BAAANQAECggIDgAAAA==.Elyn:BAAANQAECgcIEQABNQAFFAQICgAbADEIAA==.Elynthil:BAACNQAFFH8KAAIbAAQKMQg8FwDrAAAbAAQKMQg8FwDrAAA1AAQKfxwAAhsACQqKF2UzAD4CABsACQqKF2UzAD4CAAAA.',
Em='Emet:BAAANQADCgIIAgAAAA==.Emilie:BAAANQAECgQIBwAAAA==.Emunny:BAABNQAECn8hAAIZAAcKOg8LsQCdAQAZAAcKOg8LsQCdAQAAAA==.',
En='Endest:BAABNQAECn8gAAIQAAgKYRodEwB5AgAQAAgKYRodEwB5AgAAAA==.Enezalle:BAABNQAECn8gAAICAAgK9g/YcgC/AQACAAgK9g/YcgC/AQAAAA==.',
Eo='Eointhas:BAABNQAECn8hAAIZAAcKbgWr2gAxAQAZAAcKbgWr2gAxAQAAAA==.',
Ep='Ephimonk:BAABNQAECn8fAAMdAAgKZRaXIQAZAgAdAAgKZRaXIQAZAgAYAAUKCBghJgBDAQAAAA==.',
Er='Erenyeagar:BAAANQADCgYIDAAAAA==.Ernson:BAAANQADCgYIDgAAAA==.',
Eu='Euronymous:BAAANQAECgYIEwAAAA==.',
Ev='Evilandy:BAAANQAECgUIDQAAAA==.',
Fa='Faeleda:BAAANQADCgEIAQAAAA==.Fandrall:BAAANQADCgQIBgAAAA==.Faunni:BAAANQAECgUIBQAAAA==.',
Fb='Fblthp:BAAANQAECgUICwAAAA==.',
Fe='Felblood:BAAANQAECgEIAQAAAA==.Ferndolyn:BAAANQADCgMIAwAAAA==.Fezduin:BAAANQADCgIIAgAAAA==.',
Fi='Finnagetit:BAABNQAECn8cAAIbAAgKdBVxQQD1AQAbAAgKdBVxQQD1AQAAAA==.',
Fl='Flagonslayer:BAAANQAECgIJAgAAAA==.Flaimefu:BAAANQAECgIIBAAAAA==.Flaimelock:BAAANQADCgYIBgAAAA==.Floopt:BAAANQAECgQIBAAAAA==.Floorlicker:BAAANQADCgYIBgAAAA==.Flopsie:BAABNQAECn8gAAIHAAgKzhhBaABBAgAHAAgKzhhBaABBAgAAAA==.Fluffystorm:BAAANQAECgEIAQAAAA==.',
Fo='Forzod:BAAANQAECgEIAQAAAA==.Forzzie:BAAANQADCgYICQAAAA==.Foxheals:BAAANQADCgcIBwAAAA==.Foxymagic:BAAANQAECgYIEQAAAA==.',
Fr='Frabjous:BAABNQAECn8hAAIbAAcKMh3wMgBAAgAbAAcKMh3wMgBAAgAAAA==.Freenk:BAAANQADCgcIEQAAAA==.Freezerburn:BAACNQAFFH8HAAMBAAQKGAw0CgBsAAAFAAMKWRDkOQDYAAABAAIKlQM0CgBsAAA1AAQKfzIAAwUACQpsGYWVAFQCAAUACApCGYWVAFQCAAEAAgprGg8wAHsAAAAA.Frogstomper:BAAANQADCgEIAQAAAA==.',
Fu='Furn:BAABNQAECn8hAAIVAAcKxCFOMACeAgAVAAcKxCFOMACeAgAAAA==.Furryaz:BAAANQAECgQIDQAAAA==.Further:BAACNQAFFH8KAAIZAAQKECCDFACBAQAZAAQKECCDFACBAQA1AAQKfzIAAhkACQpaJV4HALcDABkACQpaJV4HALcDAAAA.',
Fy='Fyrrek:BAAANQADCgYIDQAAAA==.',
Ga='Galadrien:BAAANQADCgYIBgAAAA==.Galavenat:BAABNQAECn8gAAIHAAgKDBf2TwB9AgAHAAgKDBf2TwB9AgAAAA==.Galroy:BAAANQADCgEIAQAAAA==.Galstan:BAAANQADCgUIDAAAAA==.Garbohydrate:BAAANQADCgEIAQAAAA==.Garbolicious:BAAANQAECgEIAQAAAA==.Garbothicc:BAAANQAECgUIEwAAAA==.Garyh:BAACNQAFFH8bAAIZAAcK9SVDAgDQAgAZAAcK9SVDAgDQAgA1AAQKfzAAAhkACQruJssDANoDABkACQruJssDANoDAAAA.Garyhreturns:BAAANQAECgUIBgABNQAFFAcIGwAZAPUlAA==.',
Ge='Geldeinmonch:BAAANQADCgYIBwABNQAECgYIHQAeAJ4JAA==.Geldfuralle:BAAANQADCgIIAgABNQAECgYIHQAeAJ4JAA==.Geldklerk:BAAANQADCgYIFwABNQAECgYIHQAeAJ4JAA==.Geldverdamnt:BAABNQAECn8dAAMeAAYKngkzWAAiAQAeAAYKngkzWAAiAQAfAAYKhQTEUADTAAAAAA==.Gerasham:BAAANQADCgcIBwAAAA==.',
Gh='Ghost:BAAANQABCgQIBgAAAA==.Ghuramonk:BAAANQADCggICgAAAA==.',
Gi='Giacomo:BAAANQAECgIIAgAAAA==.Gil:BAAANQAECgUIBwAAAA==.Gildina:BAAANQAECgUICwAAAA==.Ginggy:BAABNQAECn8eAAIXAAkKyxmLZgBkAgAXAAkKyxmLZgBkAgABNQAFFAYIEwAGAB0PAA==.Girafficz:BAACNQAFFH8HAAIPAAMK2iH3FAAWAQAPAAMK2iH3FAAWAQA1AAQKfyEAAg8ACQqeJa0HAJIDAA8ACQqeJa0HAJIDAAE1AAUUCAgpABkAtSAA.',
Go='Gobb:BAAANQAECgUIBQAAAA==.Golodiso:BAAANQAECggIBgAAAA==.Gori:BAABNQAECn8rAAMIAAkKJCCdBAA4AwAIAAkKJCCdBAA4AwAgAAMK0As6JACNAAAAAA==.Gorin:BAAANQADCggIDAABNQAECggIGAAUAPIVAA==.',
Gr='Graelle:BAAANQADCgYIBgAAAA==.Gralle:BAAANQAECgUICwAAAA==.Graug:BAAANQAECgQICAABNQAECgUIEwAEAAAAAA==.Gravehart:BAAANQADCggIEAABNQAECgcIFwAhACgiAA==.Gravelbeard:BAAANQADCgIIBAAAAA==.Greatos:BAAANQABCgQIBAAAAA==.Gregory:BAABNQAECn8kAAIFAAkK2hR2jwBgAgAFAAkK2hR2jwBgAgABNQAECgUIEwAEAAAAAA==.Greyantheril:BAABNQAECn8gAAIeAAgKmgh+RgCNAQAeAAgKmgh+RgCNAQAAAA==.Greyji:BAABNQAECn8pAAIHAAkKexB+YgBOAgAHAAkKexB+YgBOAgAAAA==.Grumb:BAACNQAFFH8FAAIUAAMKQww/HADZAAAUAAMKQww/HADZAAA1AAQKfzMAAhQACQpLHJ4pANgCABQACQpLHJ4pANgCAAAA.Grypht:BAAANQADCgEIAQAAAA==.',
Gu='Guenara:BAAANQAECgYIEgAAAQ==.Guillimon:BAAANQADCgQIBAABNQAECgkJKQADALgPAA==.Gustytail:BAAANQAECgUIEwAAAA==.',
Ha='Haardrada:BAABNQAECn8fAAIbAAgKUCL5EQAbAwAbAAgKUCL5EQAbAwABNQAFFAcIGwAZAPUlAA==.Habit:BAABNQAECn8qAAIHAAkKVxcxRgCXAgAHAAkKVxcxRgCXAgAAAA==.Hadrianna:BAAANQAECgcIEQAAAA==.Halanir:BAAANQADCgIIAgAAAA==.Hanzul:BAABNQAECn8gAAMXAAgK5iKLKAAiAwAXAAgK5iKLKAAiAwALAAQKMyNxLwBfAQAAAA==.Hapless:BAABNQAECn8cAAIBAAYKDAr6GgAXAQABAAYKDAr6GgAXAQAAAA==.Hashanir:BAAANQADCgEIAQAAAA==.Hashat:BAAANQADCgIIAgAAAA==.Hawkfoot:BAAANQAECgQICgAAAA==.',
He='Hearthbreakr:BAAANQAECgQIBwABNQAFFAQICAAVAGkIAA==.Hellanie:BAAANQADCgQIBwAAAA==.Hellbore:BAABNQAECn8dAAIKAAcK+BhiFgD9AQAKAAcK+BhiFgD9AQAAAA==.Hellchi:BAABNQAECn8fAAIdAAgKbwyZLwCWAQAdAAgKbwyZLwCWAQAAAA==.Hellinasel:BAAANQAECgUIEwAAAA==.Hemmy:BAABNQAECn8yAAIMAAkKzyYgAAAIBAAMAAkKzyYgAAAIBAAAAA==.Hermer:BAAANQADCgMIAwAAAA==.Heysham:BAAANQAECgUJCQAAAA==.Hezzakan:BAAANQAECgUICwAAAA==.',
Ho='Holycef:BAAANQAECgUIDQABNQAECggIGgAYAEoaAA==.Holychild:BAAANQADCgYICgAAAA==.Holykow:BAABNQAECn8YAAIMAAcKfg4FhQCIAQAMAAcKfg4FhQCIAQAAAA==.Hotspur:BAABNQAECn8hAAQgAAcKBg1dEwBnAQAgAAcKSAtdEwBnAQAIAAQKPwzMKwDUAAAZAAEKQQP7WwEmAAAAAA==.Howlua:BAAANQADCgQJBAAAAA==.',
Hu='Huevomuerto:BAAANQAECgQICQAAAA==.Huevonyque:BAABNQAECn85AAIZAAkKfCCcHgA8AwAZAAkKfCCcHgA8AwAAAA==.Hungryhippo:BAAANQADCggICQAAAA==.Huntsthewind:BAAANQADCgUIDQAAAA==.Huulgrim:BAABNQAECn8gAAIhAAgKuBjDPAAqAgAhAAgKuBjDPAAqAgABNQABCgMIAwAEAAAAAA==.',
Hy='Hydaelyn:BAAANQADCgQIBAAAAA==.Hyejinx:BAAANQAECgUIBwAAAA==.',
Ic='Iceclaw:BAAANQADCgQIBAABNQADCgYIFAAEAAAAAA==.Icona:BAAANQADCgQIBAAAAA==.',
Ih='Ihiannan:BAAANQADCggILQABNQAECgcIIQAgAAYNAA==.',
Ii='Iiarian:BAABNQAECn8fAAIPAAcK5RATTwCfAQAPAAcK5RATTwCfAQAAAA==.',
Il='Ilivarra:BAAANQAECgQIBAAAAA==.Illisong:BAAANQAECgUIBQAAAA==.Illukana:BAABNQAECn8wAAICAAkKYCASFwAaAwACAAkKYCASFwAaAwABNQAFFAYIFAAXAFMZAA==.',
In='Infoxy:BAABNQAECn8XAAIXAAcK4gtI1wBmAQAXAAcK4gtI1wBmAQAAAA==.Inthra:BAAANQAECgUICAAAAA==.Intricacy:BAAANQAECgIIAgABNQAFFAUIDgAMAAQRAA==.',
Ir='Irimas:BAAANQADCggJFwAAAA==.',
Is='Isopope:BAAANQAECggIDQAAAA==.Isthian:BAABNQAECn8aAAIiAAcKKBExCgDVAQAiAAcKKBExCgDVAQAAAA==.',
It='Itako:BAAANQAECgEIAQAAAA==.Itoldhimso:BAAANQAECgMIBgAAAA==.',
Iv='Ivaldi:BAAANQADCgQIBwAAAA==.',
Ix='Ix:BAAANQADCgIIAgAAAA==.',
Ja='Jadelark:BAABNQAECn8gAAIGAAgK+RE9JwDjAQAGAAgK+RE9JwDjAQAAAA==.Jaeren:BAAANQABCggIIAAAAA==.Jambani:BAAANQAECgEIAQAAAA==.Javèrt:BAABNQAECn8qAAIbAAgKpBeMOgAYAgAbAAgKpBeMOgAYAgAAAA==.Jaxina:BAAANQAECgUIBwABNQAECggIGwAcAH4XAA==.Jaxordamus:BAABNQAECn8bAAIcAAgKfhefZQAmAgAcAAgKfhefZQAmAgAAAA==.',
Je='Jekle:BAAANQADCgQIBwAAAA==.Jema:BAAANQAECgUIDgAAAA==.Jenilea:BAABNQAECn8hAAIcAAcK0AZUuQBWAQAcAAcK0AZUuQBWAQAAAA==.Jessaril:BAABNQAECn8aAAILAAcK9xnbIgDHAQALAAcK9xnbIgDHAQAAAA==.Jessbgood:BAAANQABCgIIAgAAAA==.',
Ji='Jimboree:BAABNQAECn8oAAIUAAkK9B0vJADzAgAUAAkK9B0vJADzAgAAAA==.Jinsu:BAAANQAECgEIAgAAAA==.Jinzeem:BAAANQADCggIJQABNQAECgUICwAEAAAAAA==.Jiujitsunut:BAAANQADCgIIBAAAAA==.',
Jo='Jordend:BAAANQAECgMICAAAAA==.Joseppii:BAAANQAECgQIEgAAAA==.',
Jp='Jpxfrd:BAAANQADCgQIBAABNQADCgYIGQAEAAAAAA==.',
Ju='Jungyuul:BAAANQAECgUIDAAAAA==.Junkhar:BAAANQABCgEIAQAAAA==.Junpimaeus:BAAANQAECgUICwAAAA==.',
Jy='Jynnx:BAAANQADCgEIAQAAAA==.',
['Jâ']='Jâzzy:BAABNQAECn8cAAMMAAcKgiSrIgDfAgAMAAcKgiSrIgDfAgAXAAQK+Q8AAAAAAAAAAA==.Jâzzý:BAAANQADCggIEgABNQAECgcIHAAMAIIkAA==.',
Ka='Kaajira:BAAANQADCgEIAQAAAA==.Kaandew:BAAANQAECgUICwAAAA==.Kailann:BAAANQAECgUICAAAAA==.Kanji:BAAANQAECgIIAgAAAA==.Kaorin:BAAANQAECgEIAwAAAA==.Karesta:BAAANQAECgEIAQAAAA==.Kaylith:BAAANQAECgIIBAAAAA==.Kayra:BAAANQADCggIDgAAAA==.',
Ke='Kegelsmash:BAAANQAECgQIBAABNQAECgkJKAAKAKolAA==.Kelanansi:BAAANQAECgIIBAAAAA==.Kelanis:BAAANQADCgYIBgAAAA==.Kelel:BAABNQAECn8aAAMCAAgKzxR/XQAFAgACAAgKzxR/XQAFAgAjAAEK/wwlKwAtAAAAAA==.Kelessa:BAAANQADCgUICgAAAA==.Kessia:BAAANQADCggIHQAAAA==.Kessía:BAAANQADCgQIBAAAAA==.',
Kh='Khalistra:BAABNQAECn8bAAISAAgKzQ9yFQDyAQASAAgKzQ9yFQDyAQAAAA==.',
Ki='Kiroblade:BAAANQAECgUIBQABNQAECggIMQAHAOceAA==.Kiropaly:BAAANQAECgQIBAABNQAECggIMQAHAOceAA==.Kirotard:BAABNQAECn8xAAIHAAgK5x7ZPgCsAgAHAAgK5x7ZPgCsAgAAAA==.Kisldarin:BAAANQADCgUJBQAAAA==.Kithedrael:BAAANQAECgQIBQAAAA==.',
Kl='Klouded:BAAANQAECgYIBgAAAA==.',
Kn='Knuts:BAAANQADCgYICwABNQAECgkJKgAHALAlAA==.',
Ko='Koa:BAAANQAECgYICQAAAA==.Kojakk:BAABNQAECn8bAAIhAAcKlxzSPwAbAgAhAAcKlxzSPwAbAgAAAA==.Kordac:BAABNQAECn8gAAIVAAgKJBeWVgALAgAVAAgKJBeWVgALAgAAAA==.Korigan:BAAANQAECgcIDgAAAA==.Korvova:BAAANQADCgEIAQAAAA==.',
Kt='Kth:BAAANQABCggICwAAAA==.',
Ku='Kulluast:BAAANQADCgIIAgAAAA==.Kunamashiro:BAAANQAECgYIDgAAAA==.Kutisbayag:BAAANQAECgIIAgAAAA==.',
Ky='Kylê:BAAANQAECgEIAQAAAA==.Kymetra:BAAANQAECgUIDwAAAA==.Kyttin:BAAANQAECgEIAQAAAA==.',
['Kä']='Kära:BAAANQAECgQICAABNQAECgkJKwAVADYlAA==.',
['Kÿ']='Kÿthe:BAAANQABCgYICwAAAA==.',
La='Ladeeda:BAAANQADCgQIBwAAAA==.Laevi:BAAANQAECgUICwAAAA==.Lalena:BAAANQAECgYIEAAAAA==.Lawanda:BAAANQADCgEIAQABNQAECgUIEAAEAAAAAA==.',
Le='Leonineone:BAACNQAFFH8KAAIDAAQKUg+XCwAtAQADAAQKUg+XCwAtAQA1AAQKfzMAAgMACQonIuwHAFsDAAMACQonIuwHAFsDAAAA.Ler:BAAANQADCgYIBgABNQADCggIHQAEAAAAAA==.',
Li='Lichplease:BAABNQAECn8wAAIaAAkK5yRFBQCKAwAaAAkK5yRFBQCKAwAAAA==.Light:BAAANQAECggIEAAAAA==.Lightlady:BAAANQAECgUICwAAAA==.Lightridge:BAAANQABCgUICQAAAA==.Lightweight:BAAANQAECgUIDQAAAA==.Lillythorne:BAAANQAECgcIEgAAAA==.Limewire:BAABNQAFFH8HAAIbAAQKMhvHDgBiAQAbAAQKMhvHDgBiAQAAAA==.Lindsay:BAAANQAECgUIAwABNQAECgYIFgAUAIwSAA==.Linthil:BAAANQAECgEIAQAAAA==.Litehlzonly:BAAANQAECgUIDQAAAA==.Literalcow:BAAANQABCgUJBQAAAA==.Livebeef:BAAANQADCgUIDwAAAA==.Liverando:BAAANQAECgQIBAAAAA==.',
Lm='Lmaolock:BAAANQADCgEIAQAAAA==.',
Lo='Lohvadner:BAAANQADCggIGAAAAA==.Lothlum:BAABNQAECn8YAAMUAAgK8hWYbwDNAQAUAAcKsBaYbwDNAQAVAAUKZxCcpwAfAQAAAA==.',
Lu='Lunacie:BAAANQADCgYICgAAAA==.Lunalia:BAAANQAECgEIAwAAAA==.Lupen:BAAANQAECgQIBgAAAA==.Luxurria:BAAANQADCgYICQAAAA==.',
Ly='Lynlin:BAAANQAECgUICQAAAA==.Lynwalker:BAAANQAECgYIDgAAAA==.',
Ma='Madison:BAAANQADCgEIAQAAAA==.Magesef:BAABNQAECn8dAAIFAAcKEgOsPQEiAQAFAAcKEgOsPQEiAQAAAA==.Magnusrn:BAAANQADCgYIFAAAAA==.Mairead:BAAANQAECgEIAQABNQAECgUICAAEAAAAAA==.Makinmemoist:BAAANQAECgIIAgAAAA==.Malandras:BAAANQADCgEIAQAAAA==.Malandrius:BAAANQADCggIIgAAAA==.Malehei:BAAANQADCgMIAwAAAA==.Malemental:BAAANQADCggICAAAAA==.Malignities:BAABNQAECn8hAAIeAAgKzxBmOgDdAQAeAAgKzxBmOgDdAQAAAA==.Malthruin:BAAANQAECgUICQABNQAECgkJNAAcAFsWAA==.Manajamba:BAABNQAECn8fAAITAAgKhRaNEABfAgATAAgKhRaNEABfAgAAAA==.Manamidget:BAAANQADCgUICQAAAA==.Mancubus:BAABNQAECn8xAAIXAAgKSR5QRADEAgAXAAgKSR5QRADEAgAAAA==.Marosenth:BAAANQADCggIEwAAAA==.Marqadin:BAAANQAECgEIAQAAAA==.Marvinacus:BAAANQABCggIFQAAAA==.Mattyy:BAAANQAECgMIBQABNQAECgcIFwAPADYTAA==.Maxidorf:BAAANQADCggIDgAAAA==.',
Me='Meleeno:BAAANQADCgIIBAAAAA==.Mercymainbtw:BAAANQAECgQIBgAAAA==.Mergatroid:BAAANQADCgYIBgAAAA==.Metatron:BAAANQAECggIBAAAAA==.Meush:BAACNQAFFH8UAAIXAAYKUxnzBQD0AQAXAAYKUxnzBQD0AQA1AAQKfzQAAhcACQrKIjAtABADABcACQrKIjAtABADAAAA.Mewkow:BAAANQADCggIMAAAAA==.Mewsa:BAABNQAECn8hAAMBAAcKIA8aEACjAQABAAcKIA8aEACjAQAFAAMKzwELpgFtAAAAAA==.',
Mi='Micha:BAAANQADCgcIDAAAAA==.Midgee:BAAANQAECgIIBAAAAA==.Minidorf:BAAANQAECgUIBwAAAA==.Minimigraine:BAAANQAECgQIBgAAAA==.Miniroar:BAAANQADCgMIAwAAAA==.Ministorm:BAAANQAECgEIAQABNQAECgcIFwAhACgiAA==.Mintmazzo:BAAANQADCgEIAQAAAA==.Miphisto:BAAANQAECgEIAQAAAA==.Mirandee:BAAANQAECgMIBgAAAA==.Misary:BAACNQAFFH8GAAMaAAMK7AaaGAB1AAAaAAIK7AaaGAB1AAAbAAEKAACyPgAUAAA1AAQKfzIABBoACQqwHYITAO0CABoACQqwHYITAO0CABsAAQoAAPjOACwAACEAAQrWB+zrACcAAAAA.Mishrani:BAAANQADCggIFgAAAA==.Mite:BAAANQADCggICgAAAA==.',
Mo='Moa:BAAANQAECgEIAQAAAA==.Mokatines:BAAANQADCgQIBAAAAA==.Molding:BAABNQAECn8gAAIFAAcKVhTf3ADLAQAFAAcKVhTf3ADLAQAAAA==.Mollusk:BAAANQADCgYIEQAAAA==.Monis:BAABNQAECn8tAAIZAAkKLAuPjwDxAQAZAAkKLAuPjwDxAQAAAA==.Montessarah:BAAANQADCgcIGgAAAA==.Moonstôrm:BAAANQADCgYJBgAAAA==.Mootalica:BAAANQADCgQICAAAAA==.Mordraug:BAAANQAECgUICAAAAA==.Morinoe:BAABNQAECn8aAAMCAAYKrBzNagDZAQACAAYKrBzNagDZAQADAAEKAABtegAxAAAAAA==.Mornwalker:BAABNQAECn8fAAIMAAgKdCNyFAAuAwAMAAgKdCNyFAAuAwAAAA==.',
Mu='Mudelf:BAAANQADCgYIDAAAAA==.Mumra:BAABNQAECn8ZAAQMAAgKdhltYAD0AQAMAAcK4xdtYAD0AQALAAUKVRp0LgBmAQAXAAMKQQhKRAGrAAABNQAECgkJJwAGAHYjAA==.',
My='Mysticc:BAAANQADCggIGgAAAA==.Myxii:BAAANQAECgIIAgABNQAECgYIEgAEAAAAAA==.',
['Mà']='Màdrigal:BAAANQAECgEIAQAAAA==.',
['Mí']='Míckey:BAABNQAECn8YAAITAAcKDRQmGQDNAQATAAcKDRQmGQDNAQAAAA==.',
['Mÿ']='Mÿthunn:BAABNQAECn8aAAIHAAcKuwzxpQC1AQAHAAcKuwzxpQC1AQAAAA==.',
Na='Nadia:BAAANQADCgcIBwAAAA==.Nagratz:BAABNQAECn8dAAMkAAgKhRbtDwD9AQAkAAcKLhTtDwD9AQAcAAcK2hDljADBAQAAAA==.Naichingeru:BAAANQAECgEIAQAAAA==.Nalu:BAAANQAECgEIAgAAAA==.Napalmo:BAAANQADCgYICwAAAA==.Naterra:BAABNQAECn8eAAMVAAkKLRtRJgDJAgAVAAkKLRtRJgDJAgAUAAQKpwSf7QC0AAAAAA==.Nazzgul:BAAANQABCgEIAQAAAA==.',
Ne='Necessities:BAAANQAECgYIEwAAAA==.Necrill:BAABNQAECn8YAAQcAAcKywiXsgBlAQAcAAcKmwiXsgBlAQAkAAMKDgW1UQCJAAAiAAEK9QJFNQAiAAAAAA==.Neirwind:BAAANQADCggIEAAAAA==.Neyasha:BAAANQADCgEIAQAAAA==.',
Ni='Nichiwa:BAAANQAECgQICQAAAA==.Niladros:BAAANQADCgcICwAAAA==.Nirazend:BAAANQADCgYIEAAAAA==.Nisaam:BAAANQADCgUIDwAAAA==.Niteterror:BAAANQAECgUIBwAAAA==.',
Nl='Nloc:BAAANQADCgYIDAAAAA==.Nlok:BAAANQAECgEIAQAAAA==.',
No='Noadelgazo:BAAANQAECggICAAAAA==.Nolmac:BAAANQAECgUICwAAAA==.Nomesacan:BAAANQAECggIDAAAAA==.Nosleep:BAAANQAECgEIAQAAAA==.Novelia:BAAANQADCgIIAgAAAA==.',
Nu='Nuglife:BAAANQADCgYICwAAAA==.',
['Nà']='Nàtureuscary:BAAANQAECgQIDQAAAA==.',
Ob='Obtusepanda:BAABNQAECn8hAAIOAAgKWA7mGwDzAQAOAAgKWA7mGwDzAQAAAA==.',
Oc='Ocupocorrer:BAAANQAFFAEIAQAAAA==.',
Of='Offthechaeni:BAAANQAECgIIBAAAAA==.',
Og='Ograndoe:BAABNQAECn8tAAILAAkKDBwZEACaAgALAAkKDBwZEACaAgAAAA==.',
Oh='Ohanzee:BAAANQADCgcIEwAAAA==.Ohku:BAAANQAECgQIBwAAAA==.Ohok:BAAANQAECgUIEAAAAA==.',
Oi='Oisin:BAAANQAECgYICwAAAA==.',
Ol='Olomin:BAAANQAECgUIEAAAAA==.',
Om='Omathra:BAABNQAECn80AAIcAAkKWxYrSQB0AgAcAAkKWxYrSQB0AgAAAA==.',
On='Onikai:BAAANQAECgQIAgAAAA==.Onruk:BAAANQAECgcIDwAAAA==.',
Op='Ophina:BAABNQAECn8cAAIHAAgKQwf/tACVAQAHAAgKQwf/tACVAQAAAA==.',
Or='Oreo:BAAANQAECgQICAAAAA==.Orgish:BAAANQAECgIIAgABNQAECgcIFwAPADYTAA==.Orieda:BAAANQADCgUIBQAAAA==.Orihime:BAAANQADCgYIBgAAAA==.',
Os='Osage:BAABNQAECn8vAAIZAAkKbSQZDACVAwAZAAkKbSQZDACVAwAAAA==.',
Ox='Oxidising:BAABNQAECn8qAAIUAAkKXhSVQgBoAgAUAAkKXhSVQgBoAgAAAA==.',
Oz='Ozborne:BAAANQAECgQIEAAAAA==.',
Pa='Padrone:BAAANQADCgcIGQAAAA==.Paladullahan:BAABNQAECn8bAAIMAAcKfyVYHwDxAgAMAAcKfyVYHwDxAgAAAA==.Pandthrall:BAAANQAECgUICAAAAA==.Pawthos:BAAANQADCgcIEAAAAA==.',
Pe='Pennonteller:BAAANQADCgQIBQAAAA==.Pennydredful:BAAANQABCgYIBwAAAA==.Perplnuggetz:BAAANQAECgEIAQABNQAECgIIBQAEAAAAAA==.Petríchor:BAAANQADCgEIAQABNQAECgUIEAAEAAAAAA==.Pewpewmcgraw:BAABNQAECn8lAAIHAAgKmx1nSACRAgAHAAgKmx1nSACRAgAAAA==.',
Ph='Phobu:BAAANQAECgYIDgAAAA==.',
Pl='Plaguehart:BAABNQAECn8XAAIhAAcKKCJ3JwCbAgAhAAcKKCJ3JwCbAgAAAA==.Plagueniss:BAABNQAECn8qAAIIAAkKPybHAADYAwAIAAkKPybHAADYAwAAAA==.',
Po='Pompina:BAAANQADCgUICAAAAA==.Pompino:BAAANQABCgQIBAAAAA==.Ponairi:BAAANQADCgYIDAABNQAECgYIFgAUAIwSAA==.',
Pr='Primè:BAAANQADCgYIBgAAAA==.Primø:BAABNQAECn8UAAIbAAYKlA95cAAwAQAbAAYKlA95cAAwAQAAAA==.',
Ps='Psychó:BAABNQAECn8jAAIhAAkKvh4mEwAeAwAhAAkKvh4mEwAeAwAAAA==.',
Pu='Puerile:BAAANQAECgQIBQAAAA==.Pugfoo:BAAANQADCgYIBgAAAA==.Purplêlotus:BAACNQAFFH8FAAIHAAIKFgOCKwB7AAAHAAIKFgOCKwB7AAA1AAQKf0UAAgcACQqUHk4kAAQDAAcACQqUHk4kAAQDAAAA.Purrl:BAAANQAECgEIAgAAAA==.',
Py='Pyana:BAAANQADCgcIDQAAAA==.',
['Pö']='Pöppy:BAABNQAECn8YAAMHAAkK8QnYwgB4AQAHAAgKgAnYwgB4AQAlAAQKKQd3DgC5AAAAAA==.',
Qs='Qserie:BAAANQAECgEIAgAAAA==.',
Qu='Quesadilla:BAAANQADCggICQAAAA==.',
Ra='Rabid:BAAANQADCgYIDAABNQAFFAQICgAJAEwSAA==.Racelon:BAAANQAECgcIEgAAAA==.Raganark:BAAANQADCgYIBgAAAA==.Raidgriefer:BAABNQAECn8hAAIeAAcKdSOXHgChAgAeAAcKdSOXHgChAgAAAA==.Raistlín:BAAANQAECgYICQAAAA==.Rakwell:BAAANQAECgYIEwAAAA==.Raloth:BAAANQAECgIIAgAAAA==.Ramadin:BAAANQADCgIIAgABNQAFFAQICgAJAEwSAA==.Ramil:BAABNQAECn8gAAIVAAgKECPPFgAZAwAVAAgKECPPFgAZAwAAAA==.Ramorash:BAAANQAECgEIAgAAAA==.Randomeena:BAAANQADCgYIBgAAAA==.Raptorbait:BAAANQADCgYIFAAAAA==.Ratirs:BAAANQAFFAEIAQAAAA==.',
Re='Reannis:BAAANQADCgYIDQAAAA==.Reanukeeves:BAAANQADCgYIEwAAAA==.Redvoid:BAAANQAECgQJCAABNQAFFAUIEAAJAEogAA==.Rekane:BAAANQAECgQIDQAAAA==.Relyste:BAAANQADCggIDgAAAA==.Renala:BAABNQAECn8uAAIYAAkKSBcVEAB5AgAYAAkKSBcVEAB5AgAAAA==.Reteril:BAABNQAECn8uAAIHAAkKDiJoEABhAwAHAAkKDiJoEABhAwAAAA==.Retribution:BAAANQADCgcIBwAAAA==.Reyis:BAABNQAECn8hAAMCAAcK4BXHawDWAQACAAcK4BXHawDWAQADAAMKBRZzVAC3AAAAAA==.Reyvinite:BAABNQAECn8bAAIXAAgK2BIQoADcAQAXAAgK2BIQoADcAQAAAA==.',
Rh='Rhodaria:BAAANQAECgIIBAAAAA==.',
Ri='Ricepicks:BAABNQAECn80AAINAAgKeAjgRACuAQANAAgKeAjgRACuAQABNQADCgYIBgAEAAAAAA==.Rilaka:BAAANQADCggIJAAAAA==.Rintaladin:BAAANQADCgQIBwABNQAECgUIEQAEAAAAAA==.Rissu:BAACNQAFFH8IAAMOAAQKywaTCwD+AAAOAAQKpASTCwD+AAANAAEKuwYmIQBDAAA1AAQKfy0AAw0ACQr6HOoUANECAA0ACQr6HOoUANECAA4ACAoVGcwRAGMCAAAA.Risuu:BAAANQAFFAEIAQAAAA==.',
Ro='Roasted:BAABNQAECn8cAAMRAAcKiwm2DwBAAQARAAcKiwm2DwBAAQASAAQKoARfLgCnAAAAAA==.Roka:BAAANQABCgMIBAAAAA==.Ronathan:BAABNQAECn8WAAMUAAYKjBLDiQCIAQAUAAYKjBLDiQCIAQAVAAEKXwvNJAElAAAAAA==.Roper:BAABNQAECn8pAAMDAAkKuA9bIwAVAgADAAkKuA9bIwAVAgACAAcKBQ47iwBwAQAAAA==.Ropervoker:BAAANQAECgEIAQAAAA==.Roshen:BAAANQADCggIHwAAAA==.Rosselyne:BAAANQAECgMIAwABNQAECggIDwAEAAAAAA==.Rouzou:BAABNQAECn8gAAMcAAgKLxn+TgBkAgAcAAcKrRj+TgBkAgAkAAEKvRuTZwBSAAAAAA==.',
Rr='Rrun:BAAANQAECgYICwAAAA==.',
Ru='Rukia:BAABNQAECn86AAMDAAkK0iLiBQB4AwADAAkK0iLiBQB4AwACAAUK1hRBmABHAQAAAA==.Rumgold:BAABNQAECn8aAAIHAAgKLQgJmwDNAQAHAAgKLQgJmwDNAQAAAA==.Rustins:BAAANQADCgYIEAAAAA==.',
Ry='Rynhart:BAAANQAECgEIAQABNQAECgcIFwAhACgiAA==.Ryoushen:BAAANQADCggIFAAAAA==.',
['Rá']='Rád:BAAANQABCgcIBwAAAA==.',
Sa='Sabele:BAAANQADCgEIAQABNQAECgMIAwAEAAAAAA==.Sadie:BAAANQADCgcIFgAAAA==.Saintmichael:BAAANQADCgUICgAAAA==.Sapphism:BAACNQAFFH8TAAMJAAYKkx9dBgDrAQAJAAYKNRxdBgDrAQAHAAEKhiBQLgBhAAA1AAQKfzEAAwkACQoLJv4DAJYDAAkACQoLJv4DAJYDACUAAgoFHo0OALQAAAAA.Sarai:BAAANQABCgYIDwAAAA==.Sarbev:BAABNQAECn8rAAQSAAkKJxTXDQCAAgASAAkKJxTXDQCAAgARAAIKAQ5gHwBfAAAQAAEKzwS4UAApAAAAAA==.Saskwatch:BAACNQAFFH8TAAIGAAYKHQ8FBQDLAQAGAAYKHQ8FBQDLAQA1AAQKfzgAAgYACQqgH/kIADIDAAYACQqgH/kIADIDAAAA.Savat:BAAANQAECgUIEAABNQAECgcIGAAcAMsIAA==.Sayoko:BAABNQAECn8rAAIVAAkKNiWWAQDOAwAVAAkKNiWWAQDOAwAAAA==.Sayris:BAABNQAECn8rAAMHAAkKVQ2GgwABAgAHAAgKhQ6GgwABAgAJAAMK8AXiZgCLAAAAAA==.',
Sc='Scarymonster:BAAANQAECgMIAwAAAA==.Sckratchxx:BAABNQAECn8ZAAIfAAcKOx6oHgBYAgAfAAcKOx6oHgBYAgAAAA==.Scoochacho:BAABNQAECn8rAAIFAAgK7yEnMwAkAwAFAAgK7yEnMwAkAwAAAA==.',
Se='Senhunter:BAABNQAECn8YAAIHAAcKzh5iXwBWAgAHAAcKzh5iXwBWAgAAAA==.Senmaster:BAAANQAECgUIBQABNQAECgcIGAAHAM4eAA==.Sentrollock:BAAANQABCgIIAgABNQAECgcIGAAHAM4eAA==.Seradiin:BAAANQADCgEIAQAAAA==.Sereknight:BAAANQADCgQIBAAAAA==.',
Sh='Shakers:BAABNQAECn8vAAIHAAkK5CFPFwA8AwAHAAkK5CFPFwA8AwAAAA==.Shaleron:BAAANQADCgcICgAAAA==.Shamarq:BAAANQADCggIKgAAAA==.Shamtastyc:BAAANQAECgEIAQABNQAECggIGwAbAD4QAA==.Shapewalker:BAABNQAECn8yAAMmAAkKnRxJBQDbAgAmAAkKnRxJBQDbAgAeAAEKAACMigBEAAAAAA==.Shayla:BAAANQAECgUIBQAAAA==.Shaylina:BAABNQAECn8cAAMMAAgKDxbWVgARAgAMAAgKDxbWVgARAgAXAAEKcRcKhwFIAAAAAA==.Shaylune:BAAANQAECgUIAwABNQAECggIHAAMAA8WAA==.Sheba:BAAANQABCgEIAQAAAA==.Shendhi:BAAANQAECgMIBgAAAA==.Sheoby:BAAANQABCgMJBAAAAA==.Shiftcen:BAAANQAECgQIBgAAAA==.Shintazhi:BAABNQAECn8WAAIGAAYKOxgqLgClAQAGAAYKOxgqLgClAQAAAA==.Shirkan:BAABNQAECn8sAAIgAAgKXSGeBADqAgAgAAgKXSGeBADqAgAAAA==.Shojobeat:BAAANQAECgQIBAAAAA==.Shootypizza:BAAANQAECgcIEQABNQAFFAYIDwAOAGATAA==.Shreddedbeef:BAAANQAECgcIDgAAAA==.Shwartz:BAAANQADCgQIBAAAAA==.',
Si='Sigillaria:BAAANQAECgYIDAAAAA==.Simplicity:BAABNQAECn8nAAIMAAkKsBqAIwDbAgAMAAkKsBqAIwDbAgAAAA==.Sindrii:BAAANQAECgMIAwAAAA==.Sinhoi:BAAANQADCgUIBQABNQAECgMIAwAEAAAAAA==.Sinku:BAAANQAECgMICQAAAA==.Sinza:BAAANQAECgEIAQABNQAECgMICQAEAAAAAA==.Sixp:BAAANQAECgUIBQABNQAFFAQICAAVAGkIAA==.',
Sk='Skadooshh:BAABNQAECn8XAAIQAAcKjx8dEgCJAgAQAAcKjx8dEgCJAgABNQAECgkJKwAVADYlAA==.Skarray:BAEBNQAECn8gAAInAAgKzgzwEwChAQAnAAgKzgzwEwChAQAAAA==.',
Sl='Slyraxis:BAAANQAECgcIEwAAAA==.',
So='Soleirra:BAAANQADCgEIAQABNQADCggICAAEAAAAAA==.Sonas:BAAANQAECgYIDAAAAA==.Soohainao:BAAANQADCgcIDwABNQAFFAQICAAVAGkIAA==.Sorador:BAAANQADCgQICwAAAA==.',
Sp='Spargelfürze:BAAANQADCgIIBAAAAA==.Sparia:BAAANQAECgQIBAAAAA==.Spellgibson:BAABNQAECn8lAAIFAAkKAxyEOQAVAwAFAAkKAxyEOQAVAwAAAA==.Spiara:BAAANQABCgQIBAAAAA==.Spiraa:BAAANQADCggICAAAAA==.Spyroh:BAABNQAECn8hAAMRAAcKtRZDCwCrAQASAAcKnRX6GAC3AQARAAcKqhNDCwCrAQAAAA==.',
Sq='Squirrél:BAAANQADCgUIBQAAAA==.',
St='Starshine:BAAANQADCgYIBgAAAA==.Steakfrites:BAAANQADCgMIAwAAAA==.Stealthgoat:BAAANQADCgQIBAABNQADCgUICgAEAAAAAA==.Stiches:BAAANQAECgYIDAAAAA==.Stinkyfeets:BAAANQABCgEJAQAAAA==.Stoogle:BAAANQAFFAEIAQAAAA==.Stormbrook:BAABNQAECn8aAAIUAAcKyhypRwBUAgAUAAcKyhypRwBUAgAAAA==.Stoutlager:BAAANQADCgYIBgAAAA==.Stubbytotems:BAAANQAECgEIAQABNQAECgYIEgAEAAAAAA==.Stumpnose:BAAANQAECgcIDgAAAA==.Sturmdorf:BAAANQAECgUICwAAAA==.',
Su='Suhli:BAAANQADCgYIGQAAAA==.Sulfrick:BAAANQAECgEIAQAAAA==.Summannuz:BAAANQADCgIIAgAAAA==.',
Sv='Svurg:BAAANQAECgUIBwAAAA==.',
Sw='Sweetchi:BAABNQAECn8eAAIdAAcKqxF+KwC7AQAdAAcKqxF+KwC7AQAAAA==.',
Sy='Sybria:BAAANQAECgUICwABNQAECgYIEQAEAAAAAA==.Sykko:BAAANQAECgcIEAAAAA==.Sylea:BAAANQAECgIIAgAAAA==.Sylverhunter:BAAANQABCgcICwABNQAECgUICwAEAAAAAA==.Symet:BAAANQAECgIIAwAAAA==.',
['Så']='Såturn:BAAANQAECgMIBAAAAA==.',
['Së']='Sëthos:BAAANQADCgQIBQAAAA==.',
Ta='Takaria:BAAANQAECgYICAABNQAECgYIDAAEAAAAAA==.Tal:BAEANQAECgcIDAAAAA==.Tankdium:BAABNQAECn8cAAIKAAgKHxS4GADgAQAKAAgKHxS4GADgAQAAAA==.Tapcon:BAABNQAECn8ZAAIHAAYKoRDYrgCiAQAHAAYKoRDYrgCiAQAAAA==.Tape:BAAANQAECgEIAQAAAA==.Tarlas:BAABNQAECn8ZAAIMAAcK0wnYlABeAQAMAAcK0wnYlABeAQAAAA==.Tator:BAAANQADCggICAABNQAECgIIAgAEAAAAAA==.Tayllore:BAABNQAECn8fAAIBAAcK+QgnFwBAAQABAAcK+QgnFwBAAQAAAA==.',
Te='Tearsheet:BAAANQAECgEIAQABNQAECgcIIQAgAAYNAA==.Terah:BAAANQAECgUIDgABNQAFFAQICAAPADMYAA==.Terendelev:BAABNQAECn8dAAIQAAkKTRKUGQAmAgAQAAkKTRKUGQAmAgAAAA==.Terrador:BAABNQAECn8fAAIIAAgKARXREgD1AQAIAAgKARXREgD1AQAAAA==.Terramortua:BAABNQAECn8nAAIhAAkKpyUpAwDCAwAhAAkKpyUpAwDCAwABNQAFFAQICAAPADMYAA==.Terraviridis:BAABNQAFFH8IAAIPAAQKMxiAEQBNAQAPAAQKMxiAEQBNAQAAAA==.',
Th='Thalassairi:BAAANQADCgMIAwABNQAECgYIFgAUAIwSAA==.Thaugtless:BAAANQADCgYJDAABNQAECgcIIQARALUWAA==.Thelonius:BAAANQAECgYICQAAAA==.Therocksays:BAABNQAECn8bAAIfAAcKoRCXMwChAQAfAAcKoRCXMwChAQAAAA==.Thindead:BAAANQADCgIIAgABNQAECgkJMwAcAIEcAA==.Thinloc:BAABNQAECn8zAAQcAAkKgRxEQwCFAgAcAAkK4RdEQwCFAgAkAAQKIR/tKAAyAQAiAAIKVBCzHQCMAAAAAA==.Thinpal:BAAANQAECgMIBAABNQAECgkJMwAcAIEcAA==.Thissa:BAAANQAECgQIBAAAAA==.Thragge:BAEANQAECgcIEQAAAA==.Thronjak:BAABNQAECn8eAAIhAAcKyiCjLQB5AgAhAAcKyiCjLQB5AgAAAA==.Thunderfury:BAAANQAECgUIEgAAAA==.',
Ti='Tidepod:BAAANQADCggIEAAAAA==.Tidêpod:BAAANQADCgYIBgAAAA==.Tienlong:BAAANQABCggIFAAAAA==.Tiernagie:BAAANQAECggICAAAAA==.Tipride:BAACNQAFFH8IAAMVAAQKaQijGgDAAAAVAAMK6wmjGgDAAAAUAAIKyQrkIwCaAAA1AAQKfzUAAxQACQoBHRxDAGYCABQABwpaHhxDAGYCABUACQo2FOtYAAMCAAAA.Tiradis:BAAANQADCgMIAwAAAA==.Tiralie:BAAANQAECgYIEwAAAA==.Tiryl:BAAANQAECgIIAwAAAA==.',
Tn='Tnama:BAAANQADCgIIAgAAAA==.',
To='Togashi:BAAANQAECgUIDgAAAA==.Tolipes:BAAANQADCgYIBgAAAA==.Toogodly:BAAANQADCgcIDQAAAA==.Torent:BAAANQAECgIIBAAAAA==.Toshinori:BAAANQAECgIIAgABNQAECgMIAwAEAAAAAA==.Totemdáddy:BAAANQAECgQICwAAAA==.Tovëlo:BAAANQAECgYICwAAAA==.',
Tr='Treelight:BAAANQADCgEIAQAAAA==.Trehugga:BAAANQADCgcIBwAAAA==.Treldend:BAAANQADCgEIAQAAAA==.Trinogra:BAACNQAFFH8KAAIJAAQKTBIMEQAnAQAJAAQKTBIMEQAnAQA1AAQKfywAAwkACQpyH1IOAPsCAAkACQpyH1IOAPsCAAcAAQoAAE1NAUAAAAAA.Trunks:BAABNQAECn8ZAAIXAAcKoxQKsgC1AQAXAAcKoxQKsgC1AQAAAA==.Trystern:BAAANQAECgQIDgABNQAECgYIEQAEAAAAAA==.',
Tu='Turmeric:BAAANQAECgEIAwABNQAECgIIAgAEAAAAAA==.Turqos:BAAANQADCgYIDAAAAA==.',
['Tä']='Tänya:BAABNQAECn8dAAIHAAcKDgdhwgB4AQAHAAcKDgdhwgB4AQAAAA==.',
Uh='Uhno:BAAANQADCggICAAAAA==.Uhoh:BAAANQADCgUIBQAAAA==.',
Ul='Ultar:BAABNQAECn8zAAIXAAkKJiKCFwBlAwAXAAkKJiKCFwBlAwAAAA==.Ultodeesavag:BAAANQAECgUIEwAAAA==.Ultradeath:BAAANQADCggICAAAAA==.',
Un='Undeadshaman:BAAANQAECgIIBAAAAA==.Unholyjinksy:BAAANQAECgQIBwAAAA==.Unvdi:BAAANQAECgEIAQAAAA==.',
Va='Vaderrage:BAABNQAECn8hAAMgAAkKtCNXAQCRAwAgAAkKtCNXAQCRAwAZAAIKiBLmHgGVAAAAAA==.Vaehei:BAAANQABCgcICgAAAA==.Vaeronica:BAAANQADCggICwAAAA==.Valeyria:BAAANQAECgUIBQAAAA==.Valiyntha:BAAANQAECgUICwABNQAECgYIDgAEAAAAAA==.Valri:BAAANQAECgEIAgAAAA==.Vancasper:BAAANQAECgUIDAAAAA==.Vanishmancha:BAAANQAECgEIAQAAAA==.Varl:BAACNQAFFH8FAAIFAAMK0RbWNgDlAAAFAAMK0RbWNgDlAAA1AAQKfxkAAgUACQqqIEQrADkDAAUACQqqIEQrADkDAAE1AAUUBAgFACIAdxAA.Varlock:BAACNQAFFH8FAAQiAAQKdxA9BQCSAAAiAAIKCQQ9BQCSAAAcAAEKbh9FOgBXAAAkAAEK7w0PHQBNAAA1AAQKfy4ABBwACQozIhQjAPUCABwACAqcIRQjAPUCACIABgoMH6YHAB0CACQABAoTF94uAA4BAAAA.Varthlokkur:BAAANQADCgQIBAAAAA==.Vasill:BAAANQAECgcICwAAAA==.',
Ve='Velari:BAABNQAECn8hAAMiAAcKkxAGCwC+AQAiAAcKURAGCwC+AQAkAAcK1gb2IQBgAQAAAA==.Velmathris:BAAANQAECgUICAAAAA==.Venarien:BAAANQADCgQIBAAAAA==.Ventnor:BAAANQADCgIIAgAAAA==.Veydh:BAABNQAECn8lAAImAAgK1yLgAwAWAwAmAAgK1yLgAwAWAwAAAA==.Veymina:BAAANQADCgYJEgABNQAECggIJQAmANciAA==.',
Vi='Viinnee:BAAANQAECgYIDQAAAA==.Vilehart:BAAANQADCgMIAgABNQAECgcIFwAhACgiAA==.Vilya:BAAANQAECgEIAQAAAA==.Vincentlight:BAAANQAECgEIAwAAAA==.Vixess:BAACNQAFFH8KAAICAAQK9xQ+FgBBAQACAAQK9xQ+FgBBAQA1AAQKfzEAAgIACQpKIXsPAEgDAAIACQpKIXsPAEgDAAAA.',
Vo='Voidpriest:BAAANQADCggICAAAAA==.Voidweaver:BAAANQADCgUICQAAAA==.Volddawn:BAAANQADCgQIBAAAAA==.Volteer:BAABNQAECn8vAAISAAkK4Q9iEgAoAgASAAkK4Q9iEgAoAgAAAA==.',
Vu='Vudor:BAAANQAECgEIAQAAAA==.',
Vy='Vyara:BAAANQADCgIIAgABNQAECggIGQAXAKMUAA==.Vynddradoria:BAABNQAECn80AAQiAAkKGhoNAwDVAgAiAAkKGhoNAwDVAgAkAAIKDQtcXwBlAAAcAAEKiga+QAExAAAAAA==.Vyndh:BAABNQAECn8ZAAQfAAgKuiNxEQDfAgAfAAgKoSNxEQDfAgAmAAUKAiFCEACpAQAeAAEKAwiRlAAvAAAAAA==.Vynlock:BAACNQAFFH8KAAMkAAQKyCPJBADNAAAcAAMKYiSbFgBEAQAkAAIK/yLJBADNAAA1AAQKfxwABBwACQqZJs4AAPYDABwACQqZJs4AAPYDACIAAgofD4geAIMAACQAAQr8JTdbAG4AAAAA.Vynstaya:BAAANQAECgEIAQAAAA==.',
Wa='Wagmitzzixx:BAAANQADCgcIBwAAAA==.Walkerbowe:BAAANQAECgUICgAAAA==.Walt:BAAANQAECgUIEAAAAA==.Wanderin:BAABNQAECn8XAAICAAcKmRGDfACgAQACAAcKmRGDfACgAQAAAA==.Wanderit:BAAANQAECgEIAQAAAA==.Waterbutcold:BAABNQAECn8aAAIBAAcKSw+REQCJAQABAAcKSw+REQCJAQAAAA==.Waysmomtwo:BAAANQADCgYIBgAAAA==.',
We='Webby:BAAANQAECggIEQABNQAECggIGQAXAKMUAA==.',
Wh='Whiskerses:BAABNQAECn8YAAIbAAkKwxvRJgCFAgAbAAkKwxvRJgCFAgAAAA==.Whithers:BAAANQAECgIIBAAAAA==.',
Wi='Wilmer:BAAANQAECgQJBAAAAA==.Wilyy:BAAANQAECgYIDgABNQAECgkJMAARAMkZAA==.Winterchild:BAAANQADCgIIAgAAAA==.',
Wo='Woodsylver:BAAANQAECgUICwAAAA==.Wookiee:BAAANQADCgUIEgAAAA==.Worski:BAAANQAECgMICAAAAA==.',
Wr='Wrathalthiel:BAAANQAECgIIBQAAAA==.Wratherael:BAAANQADCggIDQABNQAECgIIBQAEAAAAAA==.Wraîth:BAABNQAECn8nAAIeAAkKoQ0JNQABAgAeAAkKoQ0JNQABAgAAAA==.',
Wy='Wynilla:BAAANQAECgUICwAAAA==.',
Xa='Xanamage:BAAANQADCgUICgAAAA==.Xanathar:BAAANQAECgQICQAAAA==.Xaphoris:BAAANQAECgEIAgABNQAECgYIEQAEAAAAAA==.Xayleficent:BAAANQADCggICQAAAA==.Xaylia:BAABNQAECn8hAAIVAAcKviXKHQDzAgAVAAcKviXKHQDzAgAAAA==.',
Xe='Xerhunt:BAAANQAECgYIEQAAAA==.Xerial:BAAANQAECgUIBgABNQAECgYIEQAEAAAAAA==.',
Xi='Xilorith:BAAANQAECggIDwAAAA==.',
Xo='Xolotin:BAAANQADCgMIAwAAAA==.',
Ya='Yadris:BAAANQADCgEIAQABNQAECgYIEQAEAAAAAA==.Yassi:BAABNQAECn8gAAIoAAgKpgs1FQClAQAoAAgKpgs1FQClAQAAAA==.',
Ye='Yelignar:BAAANQADCgUIBQAAAA==.',
Yi='Yimmy:BAAANQAECgYICAAAAA==.',
Yn='Ynarii:BAAANQADCgQIBQAAAA==.Ynkdh:BAAANQAECgEIAQABNQAECggIHwANAOEjAA==.',
Yo='Yoonhee:BAAANQAECggIDwAAAA==.',
Yu='Yura:BAAANQADCgQIBwAAAA==.Yurtrus:BAAANQAECgQIBgAAAA==.',
Za='Zaghary:BAABNQAECn8aAAImAAgK4AwgEwB3AQAmAAgK4AwgEwB3AQAAAA==.Zaphor:BAAANQADCgQIBAABNQAECgYIEQAEAAAAAA==.Zarik:BAAANQADCgUICAAAAA==.Zathog:BAAANQAECggICAAAAA==.',
Ze='Zebjati:BAABNQAECn8fAAIDAAgKswlcMQCUAQADAAgKswlcMQCUAQAAAA==.',
Zh='Zhend:BAAANQAECgYIEwAAAA==.',
Zo='Zoot:BAAANQADCgUIDQAAAA==.',
Zu='Zunch:BAAANQAECgUIDAAAAQ==.',
['Àz']='Àzazel:BAABNQAECn8dAAMeAAcKRxDVRACZAQAeAAcKRxDVRACZAQAmAAMKMQKPKgBbAAAAAA==.',
['Är']='Ärk:BAABNQAECn8eAAIbAAcKiRpOPwD/AQAbAAcKiRpOPwD/AQAAAA==.Ärmistice:BAAANQAECgcIEAAAAA==.',
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
