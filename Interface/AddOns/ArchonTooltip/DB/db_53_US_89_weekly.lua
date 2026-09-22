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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Elemental','Hunter-Marksmanship','Paladin-Protection','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Mage-Arcane','Mage-Frost','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','Paladin-Holy','Druid-Balance','Mage-Fire','Warlock-Affliction','Warlock-Destruction','Shaman-Restoration','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abysseus:BAAANQADCgcIDwAAAA==.',
Ad='Admired:BAAANQADCgQIBAAAAA==.',
Ae='Aerdrie:BAAANQABCgMIAwAAAA==.Aevelin:BAAANQAECgcJDQAAAA==.',
Aj='Ajagar:BAAANQADCgcJGgAAAA==.',
Al='Alamora:BAAANQADCgcJFgAAAA==.Alastair:BAAANQAECggIAgAAAA==.Alathena:BAAANQAECgMIAwAAAA==.Alexandrya:BAAANQAECgYJEQAAAA==.Alickdh:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Almostpanda:BAAANQADCgUIBQABNQAECgcIEAABAAAAAA==.Altery:BAAANQADCgIJAgAAAA==.',
Am='Ampharos:BAAANQABCgYIBgAAAA==.Amsahunter:BAAANQADCggICAABNQAECgIJAwABAAAAAA==.Amsroeb:BAAANQAECgIJAwAAAA==.',
An='Anelavenger:BAACNQAFFIEFAAICAAMKrhPWAgABAQACAAMKrhPWAgABAQA1AAQKgSsAAwIACQpjIfsAAH4DAAIACQpjIfsAAH4DAAMABgpiDAMaAEsBAAAA.Annain:BAAANQADCgYJCgAAAA==.',
Ar='Arathor:BAAANQADCgUJCQAAAA==.Ardent:BAAANQAECgQIBAAAAA==.Ardor:BAAANQADCgYICgABNQAECgQIBAABAAAAAA==.Arent:BAAANQAECgcJEwAAAA==.Arkanna:BAAANQADCgYIBgAAAA==.Artemislives:BAAANQADCggJDgAAAA==.',
As='Asharia:BAAANQAECgQJBAAAAA==.Ashla:BAAANQADCgIIAgAAAA==.Assateague:BAAANQADCgcJGQAAAA==.Astelossa:BAAANQADCgcJEAAAAA==.',
['Aë']='Aëro:BAAANQADCgYICQAAAA==.',
Ba='Bananapistol:BAAANQABCgIIBAAAAA==.Barracksbuny:BAAANQAECgEJAgABNQAECgQIBAABAAAAAA==.Barrathfrogy:BAAANQADCgMIBQAAAA==.',
Be='Bebheishel:BAAANQADCgMIBQAAAA==.Beefcake:BAAANQADCgYJFQABNQADCgcJBwABAAAAAA==.Beserol:BAAANQADCgYIBwAAAA==.',
Bi='Biest:BAAANQAECgQIBAAAAA==.Biggs:BAAANQADCggICQABNQAECgMIBQABAAAAAA==.Billy:BAAANQAECgcICwAAAA==.Bionicle:BAAANQADCgQIBAAAAA==.Biscuít:BAAANQAECgUJCwAAAA==.',
Bk='Bk:BAAANQADCgcIBwABNQAECgcJDwABAAAAAA==.',
Bl='Blasuoff:BAAANQADCgYIBgAAAA==.Bloodeagle:BAAANQADCggJCAAAAA==.Bloodyfate:BAAANQADCgYIBgAAAA==.Bluechalk:BAAANQAECgYIBgABNQAFFAYJCwAEAP0bAA==.',
Bo='Boomslap:BAAANQAECggJBgAAAA==.Booty:BAAANQADCgcJCAAAAA==.Borzoi:BAABNQAECoEVAAIFAAYKGiEQRwA3AgAFAAYKGiEQRwA3AgAAAA==.',
Br='Brawne:BAAANQADCgUIBQAAAA==.',
Bu='Buzzdruu:BAAANQAECgYICwAAAA==.',
['Bø']='Bønës:BAAANQADCgQIBAAAAA==.',
Ca='Caaniss:BAAANQABCgQIBAAAAA==.Caduceus:BAAANQADCgUIBQAAAA==.Caesus:BAAANQADCgcICwAAAA==.Cagedancer:BAAANQADCgUICQAAAA==.Callio:BAAANQAECgYIEAAAAA==.Caritta:BAABNQAECoEUAAMGAAcKKxXEKwCIAQAGAAYKRxHEKwCIAQAHAAMKqxZ5QwDlAAAAAA==.Cathillex:BAAANQAECgEJAgAAAA==.Caycay:BAACNQAFFIEFAAIHAAMK2xJ5BwD1AAAHAAMK2xJ5BwD1AAA1AAQKgSMAAgcACQoPJAIEAJEDAAcACQoPJAIEAJEDAAAA.',
Ce='Celestian:BAAANQAECggIBgAAAA==.',
Ch='Chillbros:BAABNQAECoEaAAMIAAkKjyONEQAlAwAIAAgK8SONEQAlAwAEAAgKwRtICwBZAgAAAA==.Churd:BAAANQAFFAEJAQAAAA==.Chypnotic:BAAANQAECgcIDAAAAA==.Chypotle:BAAANQADCgYJBgAAAA==.Chypster:BAAANQADCgYIBgAAAA==.',
Cl='Cleft:BAAANQAECgQJCAAAAA==.Clowwnshoes:BAAANQAECgQIBgAAAA==.',
Co='Coalystra:BAAANQAECgYIEgAAAA==.Cocopuffs:BAAANQAECgMJBgAAAA==.Colostrom:BAAANQAECgYIEgAAAA==.Coramage:BAAANQAECgIJAwAAAA==.Corliss:BAAANQAECgEIAQAAAA==.Cornholeo:BAAANQABCgIJBAAAAA==.Corruptdata:BAAANQAECgYJCwABNQAECgkJGQAFAAobAA==.',
Cp='Cplusmc:BAAANQADCgMIAwAAAA==.',
Da='Darkbeast:BAAANQAECgYJDwAAAA==.Darthorc:BAAANQADCgcJBwAAAA==.Daten:BAABNQAECoEaAAIFAAgKCAkfegCQAQAFAAgKCAkfegCQAQAAAA==.Dazshauran:BAAANQADCgMIBgAAAA==.',
De='Deadzexcs:BAAANQAECgIIAgAAAA==.Decayed:BAAANQAECgQIBAAAAA==.Deladoria:BAAANQAECgUICQAAAA==.',
Di='Diagonalli:BAAANQAECgIJAwAAAA==.Dirkdìggler:BAAANQADCgUIBwAAAA==.Divirian:BAAANQADCgEIAQAAAA==.',
Dj='Djdaemon:BAAANQADCgQJCAAAAA==.Djdrakshadow:BAAANQADCgQJCQAAAA==.Djdruidshadw:BAAANQADCgYIDAAAAA==.Djpaly:BAAANQADCgUJCwAAAA==.Djpriest:BAAANQADCgYJEQAAAA==.Djshadow:BAAANQADCgYJDgAAAA==.Djshadowar:BAAANQADCgYIEgAAAA==.Djshadowhunt:BAAANQADCgUJDgAAAA==.Djshadowlock:BAAANQADCgQJCgAAAA==.Djshadowlok:BAAANQADCgYJDgAAAA==.Djshadowrog:BAAANQADCgYIEwAAAA==.Djshadruid:BAAANQADCgYIAgAAAA==.Djshamy:BAAANQADCgYJDAAAAA==.Djshaolin:BAAANQADCgYIEAAAAA==.Djzhadow:BAAANQADCgQICwAAAA==.Djzhadruid:BAAANQADCgMIAwAAAA==.',
Dk='Dkshadow:BAAANQADCgUJDAAAAA==.',
Do='Doofuss:BAAANQABCgIJAgAAAA==.',
Dr='Drakmon:BAAANQADCgUIBQAAAA==.Draktând:BAAANQAECgUJCgAAAA==.Dreve:BAAANQABCgIIBAAAAA==.Driftier:BAAANQADCggICAAAAA==.Drunkenpanda:BAAANQAECgcIEAAAAA==.',
Du='Duneshadow:BAAANQADCgUICQAAAA==.',
Ec='Echö:BAEANQAECgYIEgAAAA==.',
Ei='Eirø:BAAANQADCgQIBAABNQAECgkJIgAJAHcZAA==.',
El='Elaine:BAAANQADCgUJBgAAAA==.Elberon:BAAANQAECgIIAgAAAA==.Elöhim:BAAANQAECggIBgAAAA==.',
Ep='Epic:BAAANQADCgYICQAAAA==.',
Er='Erebosa:BAAANQABCgQIBAAAAA==.',
Fa='Fatherchill:BAABNQAECoEWAAIKAAcKyhRFFwCvAQAKAAcKyhRFFwCvAQAAAA==.Fathermoses:BAAANQADCgMIAwAAAA==.',
Fi='Fitco:BAAANQAECgQIBQAAAA==.',
Fl='Flokii:BAAANQADCgEIAQAAAA==.',
Fr='Frantecks:BAAANQAECgYIBgAAAA==.Freela:BAEANQADCgUJBQABNQAECgMIAwABAAAAAA==.Frost:BAAANQAECgIJAgABNQAECgkJFgALAHUgAA==.Frostmon:BAABNQAECoEdAAIMAAkKXh/5CgA3AwAMAAkKXh/5CgA3AwAAAA==.Frostyaf:BAAANQADCgIIAgAAAA==.',
Fu='Furbee:BAAANQAECggIBgAAAA==.',
Ga='Galeandra:BAAANQADCgYICwAAAA==.Garim:BAAANQAECgUICgAAAA==.Gaztingo:BAAANQAECgYICQAAAA==.',
Gh='Ghostbanri:BAAANQABCgUIBQAAAA==.',
Gi='Gildor:BAAANQADCggJDQAAAA==.Girthshock:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.',
Gn='Gnar:BAAANQADCgcICAAAAA==.',
Go='Gobi:BAAANQAECgQIBgAAAA==.Gowtherpunch:BAAANQAECgYIEgAAAA==.',
Gr='Gravewynd:BAAANQADCggIDwAAAA==.Grimsy:BAAANQAECgYICwAAAA==.Gruxxiron:BAAANQAECgQIBgABNQAECgcJDQABAAAAAA==.',
Gu='Gulnn:BAAANQAECgcIDwAAAA==.Gumby:BAAANQABCgQIBAAAAA==.',
Ha='Haelena:BAAANQADCgcJHAAAAA==.Harmossy:BAAANQAECgUJDgAAAA==.',
He='Heartsfang:BAAANQADCgMIBAAAAA==.Heriotza:BAAANQAECgUJDgAAAA==.',
Ho='Holypaladin:BAABNQAECoEaAAINAAcKthjITQDoAQANAAcKthjITQDoAQAAAA==.',
Hu='Hunttress:BAAANQADCgYJBgAAAA==.',
Ii='Iimit:BAAANQAECgQICgABNQAECgUJDwABAAAAAA==.',
Il='Illidead:BAACNQAFFIEKAAIOAAUKkRhXCADQAQAOAAUKkRhXCADQAQA1AAQKgR0AAw4ACQpgJD4sAAwDAA4ACApNJD4sAAwDAA8AAQr6JAYmAFcAAAAA.Illooj:BAABNQAECoEdAAMQAAkKkyamAABeAwARAAgKdCUyBgBlAwAQAAgKviWmAABeAwAAAA==.',
In='Indexes:BAAANQADCgcJHgAAAA==.Inspiration:BAAANQADCgQICwAAAA==.',
Is='Ist:BAAANQAECgcJEwAAAA==.',
It='Itskamertime:BAAANQAECgEJAQABNQAECgYIEwABAAAAAA==.',
Iv='Ivgorod:BAAANQAECgIJAgAAAA==.',
Ja='Jabbadahut:BAAANQAECgMIBQAAAA==.Jarhead:BAAANQAECgQJBQAAAA==.Jaybas:BAAANQABCgIIAgAAAA==.Jazilyne:BAAANQADCgMIAwAAAA==.',
Jo='Joleya:BAAANQADCgUIBQAAAA==.',
Ju='Justcalmdown:BAAANQAECgUIBQABNQAECgIIAgABAAAAAA==.Justyra:BAAANQAECgQICAABNQAECgcJEQABAAAAAA==.',
Ka='Kalder:BAAANQADCgIJAgABNQAECgUJBwABAAAAAA==.Kalloo:BAAANQADCggICAABNQAECgkJHQAQAJMmAA==.Kambative:BAAANQAECgYIEwAAAA==.Kambustable:BAAANQADCggICwABNQAECgYIEwABAAAAAA==.Kamphiyer:BAAANQADCgMIBAABNQAECgYIEwABAAAAAA==.Kandosii:BAAANQABCgIIAgAAAA==.Kantheal:BAAANQAECgIIAwAAAA==.',
Ki='Kiagas:BAAANQAECgcJEgABNQADCgIIAgABAAAAAA==.Kimbrawly:BAAANQADCgYIBgAAAA==.',
Kr='Kravex:BAAANQAECgQICgAAAA==.Kreynar:BAAANQAECgQJBAABNQAECgQICgABAAAAAA==.',
Ku='Kukoc:BAAANQAECgYJCgABNQAECggJFwARAHQfAA==.',
Ky='Kyriel:BAAANQAECgcJEQAAAA==.',
La='Laayna:BAAANQAECgIIAwAAAA==.Lanta:BAAANQAECgUICQAAAA==.Larayvia:BAABNQAECoEXAAISAAgKwgbqYQDIAQASAAgKwgbqYQDIAQAAAA==.',
Le='Leesala:BAAANQAECgYIEgAAAA==.Leiman:BAAANQAECgMJAwAAAA==.',
Lg='Lg:BAAANQAECgYICgABNQAECgIIAgABAAAAAA==.',
Li='Lic:BAAANQAECgQJBwAAAA==.Lilililil:BAAANQAECgcJDwAAAA==.Lillabet:BAAANQADCgQICgAAAA==.Limpydk:BAAANQADCgUIBQABNQAECgcIEAABAAAAAA==.Limpylock:BAAANQAECgYIDQABNQAECgcIEAABAAAAAA==.Limpypal:BAAANQAECgcIEAAAAA==.',
Lo='Longtrang:BAAANQADCgMIAwAAAA==.',
Lu='Lunastre:BAAANQABCgYJCQAAAA==.',
Ma='Macallan:BAAANQABCgQJCAAAAA==.Magifur:BAABNQAECoEcAAIOAAgKnxJhfgAcAgAOAAgKnxJhfgAcAgAAAA==.Magnakilro:BAAANQAECgQIBwAAAA==.Magnomar:BAAANQADCgcIDQAAAA==.Maisy:BAAANQADCgUJBwAAAA==.Maleficus:BAAANQADCgcJHQAAAA==.Mamoswine:BAAANQABCgcICgAAAA==.Mareki:BAAANQADCggIDQAAAA==.Markdfordeth:BAAANQADCgcIBwAAAA==.Mattyfu:BAAANQAECgYIDQAAAA==.Maxrogue:BAAANQADCgUIBQABNQAECgUICgABAAAAAA==.Mazikeen:BAAANQAECgMIBQAAAA==.',
Me='Meatsupreme:BAAANQAFFAEJAQAAAA==.Meepin:BAABNQAECoEeAAMTAAgKax4eLwBDAgATAAcKgR0eLwBDAgAFAAgK6BKuWAD3AQAAAA==.Merdoc:BAAANQADCgYJCAAAAA==.Mesopunchy:BAAANQADCgcJFAAAAA==.Mesopyro:BAAANQADCgMIBgABNQADCgcJFAABAAAAAA==.',
Mi='Microchyp:BAAANQADCgEIAQAAAA==.Milemarker:BAAANQAECgcJCwAAAA==.Misstwizted:BAAANQAECgUJBgAAAA==.',
Mo='Mohinu:BAAANQADCgYJBgAAAA==.Mojodaemon:BAAANQADCgUIBQAAAA==.Moocowmoo:BAAANQADCggIDgABNQAECggIGgANALYYAA==.Moondevil:BAAANQADCgQIBwAAAA==.Morta:BAEANQAECgMIAwAAAA==.Mortkavaliro:BAAANQADCgYIBgAAAA==.',
Mu='Mugzy:BAAANQAECggIBQAAAA==.Muted:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
['Mö']='Mörph:BAAANQAECgMIAwABNQAECgkJHAATAEobAA==.',
Na='Nanérs:BAAANQAECgUIBgABNQAECgkJHwAUAKkeAA==.Narrodus:BAAANQAECgIJAgAAAA==.Nasht:BAAANQADCggICQAAAA==.Nataku:BAAANQAECgQJBAAAAA==.',
Ne='Neelix:BAAANQADCgYJDgAAAA==.Neoth:BAAANQABCgQJBgAAAA==.Nezzick:BAAANQAECgcJEwAAAA==.',
Ni='Nightreaper:BAAANQADCggJGwAAAA==.Nimbus:BAACNQAFFIEIAAIIAAUKthOsBACdAQAIAAUKthOsBACdAQA1AAQKgV0AAggACQqqJOAEAK0DAAgACQqqJOAEAK0DAAAA.',
No='Nomns:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.Normel:BAAANQAECgEIAQAAAA==.Noz:BAAANQAECgIIBAABNQAECggJGwAFAJweAA==.',
Nr='Nrvous:BAAANQADCgIIAgAAAA==.',
Nu='Numbers:BAAANQAECgUJBQAAAA==.',
Ny='Nytesage:BAABNQAECoEfAAIVAAkKISYMAADtAwAVAAkKISYMAADtAwAAAA==.',
['Nä']='Näners:BAAANQAECgIIAQABNQAECgkJHwAUAKkeAA==.',
['Në']='Nëvërmind:BAAANQAECgUJDAAAAA==.',
['Nì']='Nìghtcat:BAAANQADCggJDgAAAA==.',
Oz='Ozgar:BAAANQAECgIJBQAAAA==.Ozo:BAAANQADCgIIAgAAAA==.',
Pa='Painavolian:BAABNQAECoEfAAIOAAkKQR47LAAMAwAOAAkKQR47LAAMAwAAAA==.Palcris:BAAANQADCgcIBwAAAA==.Paxren:BAAANQABCgIIAgAAAA==.',
Ph='Phoenixdówn:BAAANQAECgIIAwAAAA==.Phoosa:BAAANQADCgEIAQAAAA==.',
Pi='Pingpong:BAAANQAECgYIEAAAAA==.Pisspadpanda:BAABNQAECoEXAAMNAAgKFhu8LwBgAgANAAgKfRq8LwBgAgAWAAMKSRpCDgDnAAAAAA==.',
Pl='Plungsnipes:BAAANQADCgcIBwABNQAECggJBgABAAAAAA==.',
Po='Poggies:BAAANQAFFAMIBAAAAA==.Potatodh:BAAANQAECgEIAgAAAA==.Potatolock:BAAANQADCgcJDAAAAA==.',
Pr='Praynes:BAAANQAECgYIEgAAAA==.',
Pu='Puppet:BAAANQADCgEIAQAAAA==.',
Py='Pylanora:BAAANQADCgMIAwAAAA==.',
Qu='Quinnx:BAAANQADCgMJAQAAAA==.',
Ra='Rach:BAAANQAECgcJCAAAAA==.Rael:BAAANQADCgIJAgAAAA==.Ranoe:BAAANQAECgIIAwABNQAECgUJDwABAAAAAA==.Rathalos:BAAANQABCgIIAgAAAA==.Raxity:BAAANQAECgQJBAAAAA==.Razji:BAAANQAECgcIEgAAAA==.',
Re='Redmg:BAAANQADCgMIAwABNQAECgMIAwABAAAAAA==.',
Ri='Riete:BAAANQAECgMIBgAAAA==.',
Ro='Rochallie:BAAANQADCgMIAwAAAA==.Rockii:BAAANQADCgYIBgAAAA==.Rocknwolf:BAAANQADCggIGwAAAA==.Rokd:BAAANQAECgcIEwAAAA==.Roscoelock:BAABNQAECoEVAAMXAAYKUxjpGQCDAQAXAAUK0hrpGQCDAQANAAQKzwoynwDzAAAAAA==.',
Ru='Ruibaron:BAAANQADCgcIFwAAAA==.',
['Rà']='Ràidèn:BAAANQADCgcIBwABNQAECggJGwAYAFccAA==.',
['Rá']='Ráyne:BAAANQADCgYIEgAAAA==.',
Sa='Sadeel:BAAANQAECgYIEgAAAA==.Sadewolf:BAAANQAFFAEJAQAAAA==.Salvadore:BAAANQADCggICAAAAA==.Samentoni:BAAANQAFFAEIAQAAAA==.Samgal:BAAANQAECgEJAQAAAA==.Sampsyn:BAAANQABCgYICgAAAA==.Sasha:BAAANQAECgMJAwAAAA==.Satyra:BAAANQAECgcJEQAAAA==.Saurphang:BAABNQAECoEiAAIMAAkKwB9cCwAyAwAMAAkKwB9cCwAyAwAAAA==.',
Sc='Scamanes:BAAANQAECgIIAgAAAA==.',
Se='Severis:BAAANQADCgEIAQAAAA==.',
Sh='Shadora:BAAANQAECgQJBAAAAA==.Shadowwizard:BAABNQAECoEgAAIXAAgK0gTjGwBxAQAXAAgK0gTjGwBxAQAAAA==.Shadybrat:BAAANQADCgcIDQABNQAECgYJEQABAAAAAA==.Shaladin:BAAANQAECgQICAAAAA==.Shidan:BAABNQAECoEbAAIYAAgKVxxgHgCeAgAYAAgKVxxgHgCeAgAAAA==.Shockaho:BAAANQAECgQIBwAAAA==.Shockchalk:BAACNQAFFIELAAIEAAYK/Rs+AABaAgAEAAYK/Rs+AABaAgA1AAQKgSgAAgQACQq7JTUAAPYDAAQACQq7JTUAAPYDAAAA.Shocknorris:BAAANQAECgIIBAABNQAECgQIBQABAAAAAA==.Shrooclaw:BAAANQADCgIIAgAAAA==.Shulk:BAAANQAECgYJDAAAAA==.',
Si='Sibbiah:BAEANQAECgEJAgAAAQ==.Silanre:BAAANQAECgEJAQAAAA==.',
Sk='Skaðï:BAABNQAECoEiAAMJAAkKdxlFEQCaAgAJAAkKdxlFEQCaAgASAAIKugkF4gBWAAAAAA==.',
Sl='Slizzard:BAAANQADCgIIAgABNQAECgkJKAAMAAwbAA==.',
Sp='Spadesrage:BAAANQAECgIIAwAAAA==.Spicyycurryy:BAAANQAECgYIEQAAAA==.',
St='Strahm:BAAANQAECgUICgAAAA==.Strehm:BAAANQADCgYIDAABNQAECgUICgABAAAAAA==.Stryhm:BAAANQADCgQIBwABNQAECgUICgABAAAAAA==.',
Su='Sulfass:BAAANQABCgIIAgAAAA==.Surai:BAAANQAECgUICQABNQAECgkJIAAZAFwgAA==.',
Sy='Sylryn:BAAANQADCgQIBAAAAA==.Sylvexa:BAAANQADCggICAAAAA==.Symple:BAAANQADCggJFAAAAA==.Synz:BAAANQADCgcJEgAAAA==.Syssare:BAAANQAECgYICAAAAA==.',
Ta='Tacpally:BAAANQADCgYICwAAAA==.Talamor:BAAANQADCgMJAwAAAA==.Talasam:BAAANQADCgQIBAAAAA==.Tandsonnara:BAAANQAECggIAQAAAA==.Tastetickle:BAAANQAECgYIEgAAAA==.Tazdrin:BAAANQAECgYIEgAAAA==.',
Te='Telidrus:BAABNQAECoEhAAQPAAkKKCFCBgAWAgAOAAgKMB5EUwCSAgAPAAYKeyJCBgAWAgAVAAIK6A7gBQCDAAAAAA==.Teneturadvys:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.',
Th='Thicc:BAAANQABCgQIBAAAAA==.Thicchunter:BAAANQAECgYIEgAAAA==.Thiccmage:BAAANQAECgQIBAAAAA==.Thiccwiggy:BAAANQADCgMIAwABNQAECgYIDQABAAAAAA==.Thunderbug:BAAANQADCggICAAAAA==.',
To='Topaze:BAABNQAECoEcAAMTAAkKShvcEwDtAgATAAkKShvcEwDtAgAKAAEKZQ+oTAAtAAAAAA==.Totemmonster:BAAANQABCgIIAgAAAA==.',
Tr='Trancendantx:BAAANQADCgcIBwAAAA==.Tripx:BAABNQAECoEZAAIFAAkKChuqKwCuAgAFAAkKChuqKwCuAgAAAA==.Tripxed:BAAANQAECgcJEwABNQAECgkJGQAFAAobAA==.Trishan:BAAANQAECgQJBAAAAA==.Trolk:BAAANQADCgUIBwAAAA==.Tronko:BAAANQAECgMIBQAAAA==.Truthjustice:BAAANQADCggJDwAAAA==.',
Tu='Turntsnaco:BAABNQAECoEjAAMZAAkKZBcKFAARAgAZAAYKuh0KFAARAgAaAAYKaxHWMgBCAQAAAA==.Turyon:BAAANQADCgEIAQAAAA==.',
Tw='Twiztedfaith:BAAANQADCgYIBgAAAA==.',
Ul='Ulhume:BAAANQADCgEJAQABNQAECgQICgABAAAAAA==.',
Un='Unafhaen:BAAANQADCgQIBAAAAA==.Unaverse:BAAANQADCgYIBgAAAA==.',
Ur='Urp:BAAANQADCgMIAwAAAA==.',
Us='Usmc:BAAANQADCgYIBgAAAA==.Usmccpl:BAAANQADCgYICQAAAA==.',
Va='Valengarde:BAAANQAECgcJDQAAAA==.Valentin:BAAANQABCgIIAgAAAA==.Valhalia:BAAANQABCgIIAgAAAA==.Vanderneuker:BAAANQAECgIIAgABNQAECgkJKAAMAAwbAA==.Vangoon:BAAANQAECgUICgAAAA==.Vanmonk:BAAANQAECgIIAQAAAA==.Vann:BAAANQADCgQIBwAAAA==.Vannix:BAAANQAECgYIEgAAAA==.',
Ve='Velkanos:BAAANQADCgQIBAAAAA==.Velkhaz:BAAANQABCgYIBgAAAA==.Vereena:BAAANQAECgQIBgAAAA==.Vesstar:BAAANQABCgYJCAAAAA==.',
Vi='Virmethir:BAAANQAECgMJAwAAAA==.',
Vo='Voltaren:BAAANQAECgIJAgAAAA==.',
Wh='Whtmg:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Wi='Wiwi:BAABNQAECoEoAAMMAAkKDBsvKQAeAgAMAAgKhhcvKQAeAgALAAYKXhtGIwDcAQAAAA==.',
Wo='Woopie:BAAANQAECgEIAQAAAA==.',
Wu='Wukøng:BAAANQABCgIIAgAAAA==.',
Xa='Xake:BAAANQAECgQIBQAAAA==.Xares:BAAANQAECgUJDwAAAA==.',
Xe='Xenp:BAAANQAECgcIEgAAAA==.',
Xi='Xiovemm:BAAANQADCgcJBQAAAA==.',
Xu='Xuri:BAAANQAECgYICQAAAA==.',
Yd='Ydriel:BAAANQADCgUIBwAAAA==.',
['Yö']='Yöurfired:BAAANQADCgQICAAAAA==.',
Za='Zake:BAABNQAECoEVAAISAAkK4RcwIgCxAgASAAkK4RcwIgCxAgAAAA==.Zalileina:BAAANQADCgMJAgAAAA==.Zantanna:BAAANQADCgYJEAAAAA==.Zappythile:BAAANQAECgUJCQAAAA==.Zayiro:BAAANQADCgYIDAAAAA==.',
Ze='Zealdavir:BAAANQABCgIIAgAAAA==.',
Zi='Zigzagoon:BAAANQABCgYIBgAAAA==.',
Zo='Zoz:BAAANQADCgcJGAAAAA==.',
Zu='Zulfrik:BAAANQAECgcJEAAAAA==.',
Zy='Zyzy:BAAANQAECgYICQABNQAFFAUIDwAbAE8eAA==.',
['Äh']='Ählis:BAAANQADCgYIBgAAAA==.',
['ße']='ßeef:BAAANQAECgQJBAAAAA==.',
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
