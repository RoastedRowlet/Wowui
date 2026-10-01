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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','Hunter-Marksmanship','Shaman-Elemental','Shaman-Enhancement','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Shadow','Paladin-Protection','Shaman-Restoration','Monk-Windwalker','DeathKnight-Frost','DeathKnight-Unholy','Monk-Brewmaster','DeathKnight-Blood','Warlock-Demonology','Mage-Arcane','Mage-Frost','Priest-Discipline','Priest-Holy','DemonHunter-Vengeance','Druid-Balance','Warrior-Arms','Warrior-Fury','Paladin-Holy','Mage-Fire','Warlock-Affliction','Warlock-Destruction','Rogue-Subtlety','Rogue-Outlaw','Druid-Feral','Rogue-Assassination',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abysseus:BAAANQADCgcIDwAAAA==.',
Ad='Admired:BAAANQADCgQIBQAAAA==.',
Ae='Aerdrie:BAAANQABCgMIAwAAAA==.Aevelin:BAAANQAECgcJDQAAAA==.',
Aj='Ajagar:BAAANQADCgcIIQABNQAECgYIDwABAAAAAA==.',
Al='Alamora:BAAANQADCggIHgAAAA==.Alastair:BAAANQAECggIAgAAAA==.Alathena:BAAANQAECgMIAwAAAA==.Alexandrya:BAABNQAECoEYAAICAAgK7Q3mXgAFAgACAAgK7Q3mXgAFAgAAAA==.Alickdh:BAAANQADCgIIAgAAAA==.Almostpanda:BAAANQADCgUIBQABNQAECggIHAADAEEOAA==.Altery:BAAANQAECgEIAQAAAA==.',
Am='Ampharos:BAAANQABCgYIBgAAAA==.Amsahunter:BAAANQADCggICAABNQAECgQIBwABAAAAAA==.Amsroeb:BAAANQAECgQIBwAAAA==.',
An='Anelavenger:BAACNQAFFIEHAAIEAAMKehYzBAD3AAAEAAMKehYzBAD3AAA1AAQKgTQAAwQACQo4IgQBAIkDAAQACQo4IgQBAIkDAAUABgpiDH4dADcBAAAA.Annain:BAAANQADCgYJCgAAAA==.',
Ar='Arathor:BAAANQADCggIEQAAAA==.Ardent:BAAANQAECgQICAAAAA==.Ardor:BAAANQADCgYICgABNQAECgQICAABAAAAAA==.Arent:BAABNQAECoEeAAIGAAgKVhOIGwAGAgAGAAgKVhOIGwAGAgAAAA==.Arkanna:BAAANQADCgYIBgAAAA==.',
As='Asharia:BAAANQAECgQJBAAAAA==.Ashla:BAAANQADCgIIAgAAAA==.Assateague:BAAANQADCggIIQAAAA==.Astelossa:BAAANQADCgcIEQAAAA==.',
['Aë']='Aëro:BAAANQADCgYICQAAAA==.',
Ba='Bananapistol:BAAANQABCgIIBAAAAA==.Barracksbuny:BAAANQAECgIIAwABNQAECgUIBQABAAAAAA==.Barrathfrogy:BAAANQADCgMIBQAAAA==.',
Be='Bebheishel:BAAANQADCgMIBQAAAA==.Beefcake:BAAANQADCgYJFQABNQADCgcJBwABAAAAAA==.Beserol:BAAANQADCgYIBwAAAA==.',
Bi='Biest:BAAANQAECggIBQAAAA==.Biggs:BAAANQADCggICQABNQAECgMIBgABAAAAAA==.Billy:BAAANQAECgcIDQAAAA==.Bilywitchdoc:BAAANQAECgEIAQABNQAECggIGgAHAG8cAA==.Bionicle:BAAANQADCgQIBAAAAA==.Biscuít:BAAANQAECgUJCwAAAA==.',
Bk='Bk:BAAANQADCgcICwABNQAECggIFgAIAGcWAA==.',
Bl='Blasuoff:BAAANQADCgYIBgAAAA==.Bloodeagle:BAAANQADCggJCAAAAA==.Bloodyfate:BAAANQADCgYIBgAAAA==.Bluechalk:BAAANQAECgYICgABNQAFFAcIEAAJALocAA==.',
Bo='Boomslap:BAAANQAECggICAAAAA==.Borzoi:BAABNQAECoEjAAIKAAcKnSLXMwC7AgAKAAcKnSLXMwC7AgAAAA==.',
Br='Brawne:BAAANQADCgUIBQAAAA==.',
Bu='Buzzdruu:BAAANQAECggIEAAAAA==.',
['Bø']='Bønës:BAAANQADCgQIBAAAAA==.',
Ca='Caaniss:BAAANQABCgQIBAAAAA==.Caduceus:BAAANQADCgUIBQAAAA==.Caesus:BAAANQADCgcICwAAAA==.Cagedancer:BAAANQADCgUICQAAAA==.Callio:BAABNQAECoEcAAICAAgKoQrZZwDsAQACAAgKoQrZZwDsAQAAAA==.Caritta:BAABNQAECoEUAAMLAAcKKxU1MQB1AQALAAYKRxE1MQB1AQAMAAMKqxacUgDTAAAAAA==.Cathillex:BAAANQAECgQIBgAAAA==.Caycay:BAACNQAFFIEKAAIMAAUKCBRGBQCkAQAMAAUKCBRGBQCkAQA1AAQKgS0AAgwACQrDJOACALoDAAwACQrDJOACALoDAAAA.',
Ce='Celestian:BAAANQAECggIBgAAAA==.',
Ch='Chillbros:BAABNQAECoEaAAMIAAkKjyMHGAAQAwAIAAgK8SMHGAAQAwAJAAgKwRtlDgBFAgAAAA==.Churd:BAABNQAECoEeAAINAAgKnxFTHgAAAgANAAgKnxFTHgAAAgAAAA==.Chypnotic:BAAANQAECggIEgAAAA==.Chypotle:BAAANQADCgYJBgAAAA==.Chypster:BAAANQADCgYIBgAAAA==.',
Cl='Cleft:BAAANQAECgYIDgAAAA==.Clowwnshoes:BAAANQAECgQICgAAAA==.',
Co='Coalystra:BAABNQAECoEeAAILAAgKxhuhEwCgAgALAAgKxhuhEwCgAgAAAA==.Cocopuffs:BAAANQAECgQICgAAAA==.Colostrom:BAABNQAECoEeAAIOAAgKzCNKBQAxAwAOAAgKzCNKBQAxAwAAAA==.Coramage:BAAANQAECgIJAwAAAA==.Corliss:BAAANQAECgEIAQAAAA==.Cornholeo:BAAANQABCgIIBAAAAA==.Corruptdata:BAAANQAECgcIEAABNQAFFAQICAAKAGkMAA==.',
Cp='Cplusmc:BAAANQADCgMIAwAAAA==.',
Da='Darkbeast:BAAANQAECgYJDwAAAA==.Darthorc:BAAANQADCgcJBwAAAA==.Daten:BAABNQAECoEaAAIKAAgKCAnJmwB9AQAKAAgKCAnJmwB9AQAAAA==.Dazshauran:BAAANQADCgUICwAAAA==.',
De='Deadzexcs:BAAANQAECgIIAwAAAA==.Decayed:BAAANQAECgUIBQAAAA==.Deladoria:BAAANQAECgYICgAAAA==.',
Di='Diagonalli:BAAANQAECgQIBwAAAA==.Dirk:BAAANQADCgUIBQABNQAECgQICQABAAAAAA==.Dirkdìggler:BAAANQADCgUIBwAAAA==.Divirian:BAAANQAECgIIAgAAAA==.',
Dj='Djdaemon:BAAANQADCgQIDAAAAA==.Djdrakshadow:BAAANQADCgUIDAAAAA==.Djdruidshadw:BAAANQADCgYIEAAAAA==.Djpaly:BAAANQADCgUIDgAAAA==.Djpriest:BAAANQADCgYIFQAAAA==.Djshadow:BAAANQADCgYIEwAAAA==.Djshadowar:BAAANQADCgYIFgAAAA==.Djshadowhunt:BAAANQADCgUIDgAAAA==.Djshadowlock:BAAANQADCgQIDQAAAA==.Djshadowlok:BAAANQADCgYIEgAAAA==.Djshadowrog:BAAANQADCgYIFwAAAA==.Djshadruid:BAAANQADCgYIBwAAAA==.Djshamy:BAAANQADCgYIEAAAAA==.Djshaolin:BAAANQADCgcIFwAAAA==.Djzhadow:BAAANQADCgQICwAAAA==.Djzhadruid:BAAANQADCgQIBgAAAA==.',
Dk='Dkshadow:BAAANQADCgcIEQAAAA==.',
Do='Doofuss:BAAANQABCgIIAgAAAA==.',
Dr='Dragonchalk:BAAANQADCgYIBgABNQAFFAcIEAAJALocAA==.Drakhadir:BAAANQADCgMIAwAAAA==.Drakmon:BAAANQADCgUIBQAAAA==.Draktând:BAAANQAECgYIDgAAAA==.Dreve:BAAANQABCgIIBAAAAA==.Driftier:BAAANQADCggICAAAAA==.Drogon:BAAANQADCgQIBAABNQAECgkJIQAPAH0hAA==.Drunkenpanda:BAABNQAECoEcAAMDAAgKQQ4YFwC0AQADAAgKQQ4YFwC0AQAQAAEKLAHOXwAXAAAAAA==.',
Du='Duneshadow:BAAANQADCgUICQAAAA==.',
Ec='Echö:BAEBNQAECoEbAAIMAAgKTgvJMgC1AQAMAAgKTgvJMgC1AQAAAA==.',
Ei='Eirø:BAAANQADCgQIBAABNQAECgkJJwAHACUbAA==.',
El='Elaine:BAAANQADCgUJBgAAAA==.Elberon:BAAANQAECgIIAgAAAA==.Elöhim:BAAANQAECggIBgAAAA==.',
Ep='Epic:BAAANQADCgYICQAAAA==.',
Eq='Eqo:BAAANQADCgQIBAAAAA==.',
Er='Erebosa:BAAANQABCgQIBAAAAA==.',
Fa='Fatherchill:BAABNQAECoEbAAIOAAcK0hYLHQCoAQAOAAcK0hYLHQCoAQAAAA==.Fathermoses:BAAANQADCgMIAwAAAA==.',
Fi='Fitco:BAAANQAECgQIBQAAAA==.',
Fl='Flokii:BAAANQADCgEIAQAAAA==.',
Fr='Frantecks:BAAANQAECgYIBgAAAA==.Freela:BAEANQADCgUIBQABNQAECgQIBwABAAAAAA==.Frost:BAAANQAECgIJAgABNQAFFAUICQARAAAMAA==.Frostmon:BAABNQAECoEiAAISAAkKDCBWEgDyAgASAAkKDCBWEgDyAgAAAA==.Frostyaf:BAAANQADCgIIAgAAAA==.',
Fu='Furbee:BAAANQAECggIBgAAAA==.',
Ga='Galeandra:BAAANQAECgEIAQAAAA==.Gambas:BAAANQADCgIIAgAAAA==.Garim:BAAANQAECgYIEAAAAA==.Gaztingo:BAAANQAECgYIDwAAAA==.',
Gh='Ghostbanri:BAAANQABCgUIBQAAAA==.',
Gi='Gildor:BAAANQADCggIDQAAAA==.Girthshock:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.',
Gn='Gnar:BAAANQADCgcICAAAAA==.',
Go='Gobi:BAAANQAECgYIDAAAAA==.Gowtherpunch:BAABNQAECoEfAAITAAgK0Am7EgBzAQATAAgK0Am7EgBzAQAAAA==.',
Gr='Gravewynd:BAAANQADCggIDwAAAA==.Grimsy:BAAANQAECgYICwAAAA==.Gruxxiron:BAAANQAECgQIBgABNQAECggIFwAUAEQVAA==.',
Gu='Gulnn:BAAANQAECgcIEAAAAA==.Gumby:BAAANQABCgQIBAAAAA==.',
Ha='Haelena:BAAANQADCgcIIwAAAA==.Hage:BAAANQADCggIAQAAAA==.Harmossy:BAAANQAECgUJDgAAAA==.',
He='Heartsfang:BAAANQADCgMIBAAAAA==.Heriotza:BAAANQAECgYIDwAAAA==.',
Ho='Hogmaine:BAAANQADCgQIBAAAAA==.Holypaladin:BAABNQAECoEgAAIVAAcKRBp/WwD3AQAVAAcKRBp/WwD3AQAAAA==.',
Hu='Hunttress:BAAANQADCgYIBgAAAA==.',
Ii='Iimit:BAAANQAECgQICgABNQAECgYIEQABAAAAAA==.',
Il='Illidead:BAACNQAFFIEOAAIWAAUK6B40CwDZAQAWAAUK6B40CwDZAQA1AAQKgSUAAxYACQpUJb8dAE0DABYACApgJb8dAE0DABcAAQr6JJEuAFAAAAAA.Illooj:BAABNQAECoEgAAMYAAkKmSbaAABWAwAZAAgKeiWfCABdAwAYAAgKviXaAABWAwAAAA==.',
In='Indexes:BAAANQADCggIJgAAAA==.Inspiration:BAAANQADCgQICwAAAA==.',
Is='Ist:BAABNQAECoEeAAIaAAgKhxKBCgDRAQAaAAgKhxKBCgDRAQAAAA==.',
It='Itskamertime:BAAANQAECgEJAQABNQAECggIIgAbAAwdAA==.',
Iv='Ivgorod:BAAANQAECgQIBgAAAA==.',
Ja='Jabbadahut:BAAANQAECgMIBgAAAA==.Jarhead:BAAANQAECgQIBQAAAA==.Jaybas:BAAANQABCgIIAgAAAA==.Jazilyne:BAAANQADCgMIAwAAAA==.Jaziriel:BAAANQADCgYIBgAAAA==.',
Jo='Joleya:BAAANQADCgYICwAAAA==.',
Ju='Justcalmdown:BAAANQAECgUIBQABNQAECgIIAgABAAAAAA==.Justyra:BAAANQAECgQICAABNQAECggIGwALADMbAA==.',
Ka='Kalder:BAAANQADCgIJAgABNQAECgUIBwABAAAAAA==.Kalloo:BAAANQAECgYIBgABNQAECgkJIAAYAJkmAA==.Kambative:BAABNQAECoEiAAMbAAgKDB2CKABTAgAbAAcKfh6CKABTAgAGAAMKTBnLOQDmAAAAAA==.Kambustable:BAAANQADCggICwABNQAECggIIgAbAAwdAA==.Kammunion:BAAANQAECgUIBQABNQAECggIIgAbAAwdAA==.Kamphiyer:BAAANQADCgMIBAABNQAECggIIgAbAAwdAA==.Kanan:BAAANQADCgcICgAAAA==.Kandosii:BAAANQABCgIIAgAAAA==.Kantheal:BAAANQAECgQIBwAAAA==.',
Ki='Kiagas:BAABNQAECoEWAAMcAAkKBA5icQDxAQAcAAkKxQxicQDxAQAdAAYKKwvcEQAwAQABNQADCgIIAgABAAAAAA==.Kimbrawly:BAAANQADCgYIBgAAAA==.',
Kr='Kravex:BAAANQAECgUIDwAAAA==.Kreynar:BAAANQAECgQJBAABNQAECgUIDwABAAAAAA==.',
Ku='Kukoc:BAAANQAECgcIEQAAAA==.',
Ky='Kylana:BAAANQADCgUIBQABNQAECgUIDgABAAAAAA==.Kyriel:BAABNQAECoEaAAIPAAgKsRedPAAkAgAPAAgKsRedPAAkAgAAAA==.',
['Ké']='Kélly:BAAANQAECggICAAAAA==.',
La='Laayna:BAAANQAECgIIBAAAAA==.Lanta:BAAANQAECgYIDwAAAA==.Larayvia:BAABNQAECoEZAAICAAgKxwYufAC2AQACAAgKxwYufAC2AQAAAA==.',
Le='Leesala:BAAANQAECgYIEgAAAA==.Leiman:BAAANQAECgMIBgAAAA==.',
Lg='Lg:BAAANQAECgcIEQABNQAECgIIAgABAAAAAA==.',
Li='Lic:BAAANQAECgQIBwAAAA==.Lilbitty:BAAANQADCgEIAQAAAA==.Lilililil:BAABNQAECoEWAAIIAAgKZxa9PwArAgAIAAgKZxa9PwArAgAAAA==.Lillabet:BAAANQADCgQICgAAAA==.Limpydk:BAAANQADCgUIBQABNQAECgcIEAABAAAAAA==.Limpylock:BAAANQAECgYIDQABNQAECgcIEAABAAAAAA==.Limpypal:BAAANQAECgcIEAAAAA==.Lispeth:BAAANQAECgEIAQAAAA==.',
Lo='Longtrang:BAAANQADCgMIAwAAAA==.',
Lu='Luckyleaf:BAAANQADCgYIBgAAAA==.Lunaaris:BAAANQAECgcIBwAAAA==.Lunastre:BAAANQABCgYICgAAAA==.',
Ma='Macallan:BAAANQADCgMIAwAAAA==.Magifur:BAABNQAECoEcAAIWAAgKnxLkmwAEAgAWAAgKnxLkmwAEAgAAAA==.Magnakilro:BAAANQAECgUIDAAAAA==.Magnomar:BAAANQADCgcIDQAAAA==.Maisy:BAAANQADCgUJBwAAAA==.Maleficus:BAAANQADCggIJQAAAA==.Mamoswine:BAAANQABCgcICgAAAA==.Mareki:BAAANQADCggIDQAAAA==.Markdfordeth:BAAANQADCgcIBwAAAA==.Mattyfu:BAAANQAECgYIDQAAAA==.Maxrogue:BAAANQADCgUIBQABNQAECgYIEAABAAAAAA==.Mazikeen:BAAANQAECgQICQAAAA==.',
Me='Meatsupreme:BAABNQAECoEcAAIKAAgKFxR+bwD0AQAKAAgKFxR+bwD0AQAAAA==.Meepin:BAABNQAECoEhAAQeAAkKLh4yOwA5AgAeAAcKgR0yOwA5AgAKAAgK6BKtdADlAQAOAAMKLwycQwCLAAAAAA==.Merdoc:BAAANQADCgYJCAAAAA==.Mesopunchy:BAAANQADCggIHAAAAA==.Mesopyro:BAAANQADCgMIBgABNQADCggIHAABAAAAAA==.',
Mi='Microchyp:BAAANQADCgEIAQAAAA==.Milemarker:BAAANQAECgcIDAAAAA==.Misstwizted:BAAANQAECgYIDAAAAA==.',
Mo='Mohinu:BAAANQADCgYICwAAAA==.Mojodaemon:BAAANQADCgUIBQAAAA==.Moocowmoo:BAAANQADCggIDgABNQAECggIIAAVAEQaAA==.Moondevil:BAAANQADCgQICAAAAA==.Morta:BAEANQAECgQIBwAAAA==.Mortkavaliro:BAAANQADCgYIBgABNQAECgYIDwABAAAAAA==.',
Mu='Mugzy:BAAANQAECggIAgAAAA==.Muted:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
['Mö']='Mörph:BAAANQAECgMIAwABNQAECgkJHAAeAEobAA==.',
Na='Nanérs:BAAANQAECgUIBgABNQAFFAQICAAbAAAVAA==.Narrodus:BAAANQAECgIIAgAAAA==.Nasht:BAAANQADCggICQAAAA==.Nataku:BAAANQAECgUICQAAAA==.',
Ne='Neelix:BAAANQADCgYJDgAAAA==.Neoth:BAAANQABCgQJBgAAAA==.Nezzick:BAABNQAECoEeAAMIAAgKsRhqMAB3AgAIAAgKsRhqMAB3AgAPAAgKYAjbcwBYAQAAAA==.',
Ni='Nightreaper:BAAANQADCggIIgAAAA==.Nightsinger:BAAANQABCgIIAgAAAA==.Nimbus:BAACNQAFFIEOAAIIAAYKQRntAgAhAgAIAAYKQRntAgAhAgA1AAQKgXYAAggACQoPJqMBAOUDAAgACQoPJqMBAOUDAAAA.',
No='Nomns:BAAANQADCgYIBgABNQAECgUIDQABAAAAAA==.Normel:BAAANQAECgEIAQAAAA==.Noz:BAAANQAECgIIBAABNQAECggIGwAKAJweAA==.',
Nr='Nrvous:BAAANQADCgIIAgAAAA==.',
Nu='Numbers:BAAANQAECgUIBwAAAA==.',
Ny='Nytesage:BAACNQAFFIEHAAIfAAQKyR4bAAChAQAfAAQKyR4bAAChAQA1AAQKgSIAAh8ACQpWJg4AAOsDAB8ACQpWJg4AAOsDAAAA.',
['Nä']='Näners:BAAANQAECgIIAQABNQAFFAQICAAbAAAVAA==.',
['Në']='Nëvërmind:BAAANQAECgYIEgAAAA==.',
['Nì']='Nìghtcat:BAAANQADCggIDgAAAA==.',
Or='Orgrom:BAAANQAECggICAAAAA==.',
Oz='Ozgar:BAAANQAECgIIBQAAAA==.Ozo:BAAANQADCgIIAgAAAA==.',
Pa='Painavolian:BAABNQAECoEoAAIWAAkKKx+4JQAyAwAWAAkKKx+4JQAyAwAAAA==.Palcris:BAAANQADCgcIBwAAAA==.Paxren:BAAANQABCgIIAgAAAA==.',
Pe='Peeches:BAAANQAECgUIBQAAAA==.',
Ph='Pheayre:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Phoenixdówn:BAAANQAECgUICAAAAA==.Phoosa:BAAANQADCgEIAQAAAA==.',
Pi='Pingpong:BAABNQAECoEbAAIQAAgKmhgNFgBRAgAQAAgKmhgNFgBRAgAAAA==.Pisspadpanda:BAABNQAECoEeAAMVAAgKchu6PABeAgAVAAgK2Bq6PABeAgAgAAMKSRp5EQDiAAAAAA==.',
Pl='Plungsnipes:BAAANQADCgcIDgABNQAECggICAABAAAAAA==.',
Po='Poggies:BAACNQAFFIEJAAIWAAUKXiBnCgDkAQAWAAUKXiBnCgDkAQA1AAQKgRcAAxYACQpXJPUaAFcDABYACQqDI/UaAFcDAB8ACAruIO4AAMcCAAAA.Potatodh:BAAANQAECgEIAgAAAA==.Potatolock:BAAANQADCgcIDAAAAA==.',
Pr='Praynes:BAABNQAECoEbAAIZAAgKmRvzMABiAgAZAAgKmRvzMABiAgAAAA==.',
Pu='Puppet:BAAANQADCgEIAQAAAA==.',
Py='Pylanora:BAAANQADCgMIAwAAAA==.',
Qu='Quinnx:BAAANQADCgMJAQAAAA==.',
Ra='Rach:BAAANQAECgcIDwAAAA==.Rael:BAAANQADCgIJAgAAAA==.Raethellon:BAAANQADCgYIBgAAAA==.Ranoe:BAAANQAECgIIAwABNQAECgYIEQABAAAAAA==.Rathalos:BAAANQABCgIIAgAAAA==.Raxity:BAAANQAECgQIBgAAAA==.Razji:BAABNQAECoEaAAMHAAgKbxy1GABfAgAHAAcK4Ry1GABfAgACAAQKfx2PtwAoAQAAAA==.',
Re='Redmg:BAAANQADCgUICAABNQAECgMIAwABAAAAAA==.',
Ri='Riete:BAAANQAECgQICgAAAA==.',
Ro='Rochallie:BAAANQAECgEIAQAAAA==.Rockii:BAAANQADCgYIBgAAAA==.Rocknwolf:BAAANQAECgEIAQAAAA==.Rokd:BAABNQAECoEeAAIOAAgKqyHVBwDyAgAOAAgKqyHVBwDyAgAAAA==.Roscoelock:BAABNQAECoEVAAMhAAYKUxiIHAB6AQAhAAUK0hqIHAB6AQAVAAQKzwo4vQDuAAAAAA==.',
Ru='Ruibaron:BAAANQADCgcIHgAAAA==.',
['Rà']='Ràidèn:BAAANQADCgcIBwABNQAECggIIwAPAFogAA==.',
['Rá']='Ráyne:BAAANQAECgEIAQAAAA==.',
Sa='Sadeel:BAABNQAECoEeAAIgAAgKmRJ5BQAmAgAgAAgKmRJ5BQAmAgAAAA==.Sadewolf:BAABNQAECoEYAAILAAgK5SGHDAD7AgALAAgK5SGHDAD7AgAAAA==.Salvadore:BAAANQADCggICAAAAA==.Samentoni:BAABNQAECoEcAAIeAAgKYBfDOQA/AgAeAAgKYBfDOQA/AgAAAA==.Samgal:BAAANQAECgQIBQAAAA==.Sampsyn:BAAANQABCgYICgAAAA==.Sasha:BAAANQAECgMIBgAAAA==.Satyra:BAABNQAECoEbAAILAAgKMxsuFgCBAgALAAgKMxsuFgCBAgAAAA==.Saurphang:BAABNQAECoEnAAISAAkKsSEFDAAzAwASAAkKsSEFDAAzAwAAAA==.',
Sc='Scamanes:BAAANQAECgUIBwAAAA==.',
Se='Semperfi:BAAANQABCgYICQAAAA==.Severis:BAAANQADCgEIAQAAAA==.',
Sh='Shadora:BAAANQAECgUIBwAAAA==.Shadowwizard:BAABNQAECoEwAAIhAAgKlwpNFQC3AQAhAAgKlwpNFQC3AQAAAA==.Shadybrat:BAAANQADCggIFwABNQAECggIGAACAO0NAA==.Shaladin:BAAANQAECgQICAAAAA==.Shidan:BAABNQAECoEjAAIPAAgKWiC7GwDNAgAPAAgKWiC7GwDNAgAAAA==.Shockaho:BAAANQAECgQIBwAAAA==.Shockchalk:BAACNQAFFIEQAAIJAAcKuhwiAACzAgAJAAcKuhwiAACzAgA1AAQKgSsAAgkACQqSJiQAAAIEAAkACQqSJiQAAAIEAAAA.Shocknorris:BAAANQAECgIIBAABNQAECgQIBQABAAAAAA==.Shrooclaw:BAAANQADCgIIAgAAAA==.Shulk:BAAANQAECgYIEgAAAA==.',
Si='Sibbiah:BAEANQAECgMIBQAAAQ==.Silanre:BAAANQAECgEIAgAAAA==.',
Sk='Skaðï:BAABNQAECoEnAAMHAAkKJRsDEwCgAgAHAAkKGRsDEwCgAgACAAIKIg2MAAFmAAAAAA==.',
Sl='Slizzard:BAAANQADCgIIAgABNQAECgkJLAASAN4dAA==.',
Sp='Spadesrage:BAAANQAECgIIBQAAAA==.Spash:BAAANQADCgQIBAAAAA==.Spicyycurryy:BAABNQAECoEbAAIcAAgK0BhmXgArAgAcAAgK0BhmXgArAgAAAA==.',
St='Strahm:BAAANQAECgYIEAAAAA==.Strehm:BAAANQADCgYIDAABNQAECgYIEAABAAAAAA==.Stryhm:BAAANQADCgQIBwABNQAECgYIEAABAAAAAA==.',
Su='Sulfass:BAAANQABCgIIAgAAAA==.Surai:BAAANQAECgYIDwABNQAFFAMIBQAiAMoMAA==.',
Sy='Sylryn:BAAANQADCgQIBAAAAA==.Sylvexa:BAAANQADCggIDAAAAA==.Symple:BAAANQADCggIFAAAAA==.Syns:BAAANQADCgcIBwAAAA==.Synz:BAAANQADCgcJEgAAAA==.Syssare:BAAANQAECgYIDQAAAA==.',
Ta='Tacpally:BAAANQADCgYIEAAAAA==.Talamor:BAAANQADCgMJAwAAAA==.Talasam:BAAANQADCgQIBAAAAA==.Tandsonnara:BAAANQAECggIAQAAAA==.Tastetickle:BAABNQAECoEeAAIWAAgK7hgvcQBnAgAWAAgK7hgvcQBnAgAAAA==.Tazdrin:BAABNQAECoEeAAIjAAgKgxD0BwD7AQAjAAgKgxD0BwD7AQAAAA==.',
Te='Telidrus:BAABNQAECoEhAAQXAAkKKCHQCAD8AQAWAAgKMB79bABxAgAXAAYKeyLQCAD8AQAfAAIK6A4FBwB9AAAAAA==.Teneturadvys:BAAANQADCgQIBAABNQAECgYIBwABAAAAAA==.Terrax:BAAANQADCgQIBAAAAA==.',
Th='Thicc:BAAANQABCgQIBAAAAA==.Thicchunter:BAABNQAECoEbAAIHAAgKaSBMDgDZAgAHAAgKaSBMDgDZAgAAAA==.Thiccmage:BAAANQAECgYICQAAAA==.Thiccwiggy:BAAANQADCgMIAwABNQAECgYIDQABAAAAAA==.Thunderbug:BAAANQADCggICAAAAA==.',
To='Topaze:BAABNQAECoEcAAMeAAkKSht4GgDhAgAeAAkKSht4GgDhAgAOAAEKZQ/CWwApAAAAAA==.Totemmonster:BAAANQABCgIIAgAAAA==.',
Tr='Trancendantx:BAAANQADCgcIBwAAAA==.Tripx:BAACNQAFFIEIAAIKAAQKaQxYCgAxAQAKAAQKaQxYCgAxAQA1AAQKgR8AAgoACQoKG0o/AI4CAAoACQoKG0o/AI4CAAAA.Tripxed:BAABNQAECoEeAAMbAAgK3xjLJgBhAgAbAAgK3xjLJgBhAgAkAAEKWgqGKwA7AAABNQAFFAQICAAKAGkMAA==.Trishan:BAAANQAECgQIBQAAAA==.Trolk:BAAANQADCgUIBwAAAA==.Tronko:BAAANQAECgUICAAAAA==.Truthjustice:BAAANQADCggJDwAAAA==.',
Tu='Turntsnaco:BAABNQAECoErAAMiAAkK7xoCDwBqAgAiAAcKXx4CDwBqAgAlAAYKaxHUQQA2AQAAAA==.Turyon:BAAANQADCgEIAQAAAA==.',
Tw='Twiztedfaith:BAAANQADCgYIBgAAAA==.',
Ul='Ulhume:BAAANQADCgEJAQABNQAECgUIDwABAAAAAA==.',
Un='Unafhaen:BAAANQADCgQIBAAAAA==.Unaverse:BAAANQADCgYIBgAAAA==.',
Ur='Urp:BAAANQAECgEIAQAAAA==.',
Us='Usmc:BAAANQADCgYIBgAAAA==.Usmccpl:BAAANQADCgYICQAAAA==.',
Va='Valengarde:BAAANQAECgcJDQAAAA==.Valentin:BAAANQABCgIIAgAAAA==.Valhalia:BAAANQABCgIIAgAAAA==.Vanderneuker:BAAANQAECgIIAwABNQAECgkJLAASAN4dAA==.Vangoon:BAEANQAECgYIEAAAAA==.Vanmonk:BAAANQAECgIIAQAAAA==.Vann:BAAANQADCgQIBwAAAA==.Vannix:BAABNQAECoEeAAINAAgKPCMOCgAcAwANAAgKPCMOCgAcAwAAAA==.',
Ve='Velkanos:BAAANQADCgQIBAAAAA==.Velkhaz:BAAANQABCgYIBgAAAA==.Vereena:BAAANQAECgQIBgAAAA==.Vesstar:BAAANQABCggIEAAAAA==.',
Vi='Virmethir:BAAANQAECgQIBwAAAA==.',
Vo='Voltaren:BAAANQAECgIJAgAAAA==.',
Wh='Whtmg:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Wi='Wiwi:BAABNQAECoEsAAMSAAkK3h3nNQDxAQASAAgKfRnnNQDxAQARAAYK+RwsLQDRAQAAAA==.',
Wo='Woopie:BAAANQAECgEIAQAAAA==.',
Wu='Wukøng:BAAANQABCgIIAgAAAA==.',
Xa='Xake:BAAANQAECgUICgAAAA==.Xares:BAAANQAECgYIEQAAAA==.',
Xe='Xenp:BAABNQAECoEhAAMOAAgKOhbWFQD9AQAOAAgKOhbWFQD9AQAKAAIKcAnPKQFdAAAAAA==.',
Xi='Xiovemm:BAAANQADCgcJBQAAAA==.',
Xu='Xuri:BAAANQAECgYIDwAAAA==.',
Yd='Ydriel:BAAANQADCgUIBwAAAA==.',
['Yö']='Yöurfired:BAAANQADCgQICAAAAA==.',
Za='Zake:BAABNQAECoEcAAICAAkKohhxLACqAgACAAkKohhxLACqAgAAAA==.Zalileina:BAAANQADCgMJAgAAAA==.Zantanna:BAAANQADCgYJEAAAAA==.Zappythile:BAAANQAECgUIDgAAAA==.Zayiro:BAAANQADCgYIDAAAAA==.',
Ze='Zealdavir:BAAANQABCgIIAgAAAA==.',
Zi='Zigzagoon:BAAANQABCgYIBgAAAA==.',
Zo='Zoz:BAAANQADCggIIAAAAA==.',
Zu='Zulfrik:BAABNQAECoEYAAMWAAgK2hOnmQAIAgAWAAgKshCnmQAIAgAXAAIKEh1cJQB/AAAAAA==.',
Zy='Zyzy:BAAANQAECgYICQABNQAFFAYIFQANABUeAA==.',
['Äh']='Ählis:BAAANQAECgIIAgAAAA==.',
['ße']='ßeef:BAAANQAECgUICQAAAA==.',
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
