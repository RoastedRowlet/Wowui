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

local lookup = {'Warlock-Destruction','DeathKnight-Blood','Druid-Balance','Shaman-Elemental','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Retribution','Unknown-Unknown','Evoker-Devastation','Priest-Holy','Evoker-Preservation','Mage-Frost','Mage-Fire','Priest-Shadow','Evoker-Augmentation','Shaman-Restoration','Hunter-BeastMastery','Paladin-Holy','Rogue-Assassination','Warlock-Affliction','Mage-Arcane','Monk-Brewmaster','Warrior-Arms','DemonHunter-Devourer','Druid-Guardian','Druid-Restoration',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aanuanaela:BAAANQAECgUJDAAAAA==.',
Ab='Absens:BAABNQAECoEXAAIBAAcKqgmMHgBpAQABAAcKqgmMHgBpAQAAAA==.Abumim:BAAANQADCggICAAAAA==.',
Ad='Adorian:BAAANQAECgQIBAABNQAECggIGwACAIIhAA==.Adwillon:BAAANQAECgIIAgAAAA==.',
Af='Aforceofone:BAAANQAECgQIBAAAAA==.',
Ag='Aggretsuko:BAAANQAECgcIEwAAAA==.',
Al='Aldonza:BAAANQADCgIIAgAAAA==.Alex:BAAANQAECgQIBgAAAA==.Aluviel:BAAANQAFFAIIAwABNQAFFAcIFAADAAAmAA==.Alyslia:BAAANQABCggIFQAAAA==.',
An='Anamuht:BAAANQAECgYIEgABNQAECggIGwAEAIYcAA==.Annaday:BAAANQAECgMIBAAAAA==.Antiock:BAABNQAECoEbAAQCAAgKgiGJIQByAgACAAcKTyGJIQByAgAFAAgKvRgbHQBWAgAGAAIKQBCckgBzAAAAAA==.Anyamonka:BAAANQAECgUIBwAAAA==.',
Ap='Appalachia:BAAANQADCgYJBgAAAA==.',
Ar='Ariea:BAAANQADCgEIAQAAAA==.Arrowmir:BAAANQABCgYJCAAAAA==.Artto:BAAANQADCgIIAgAAAA==.',
As='Ashbrínger:BAABNQAECoEcAAIHAAgKYyNMHAAnAwAHAAgKYyNMHAAnAwAAAA==.',
At='Atua:BAAANQADCgQJBQAAAA==.',
Av='Averax:BAAANQAECgUIDwAAAA==.Avylbrew:BAAANQADCgUJCAABNQAECgIIAgAIAAAAAA==.',
Ay='Aylakaye:BAAANQADCgcICAAAAA==.',
Az='Azzathoth:BAAANQADCggICAAAAA==.',
Ba='Babybilly:BAAANQAECgUIEwAAAA==.Babyshoes:BAAANQAECgQIBAAAAA==.Backpack:BAAANQAECgMJAwAAAA==.Bananawaffle:BAAANQADCgEIAQAAAA==.Bandan:BAAANQAECgUICQAAAA==.Bato:BAAANQADCgUIDAAAAA==.',
Be='Beefjurkey:BAAANQAECgQICQAAAA==.',
Bh='Bhalthazar:BAAANQADCgQIBAABNQADCgYICAAIAAAAAA==.',
Bi='Bier:BAAANQADCgYJBgAAAA==.Bigrig:BAAANQAECgEIAQAAAA==.Bitterman:BAAANQAECgYIEgAAAA==.',
Bl='Blastin:BAAANQADCggICAAAAA==.',
Bo='Boohoo:BAAANQADCgMIAwAAAA==.Bovinedivine:BAAANQADCgUJBQABNQAECgUIDwAIAAAAAA==.',
Br='Brandumb:BAAANQAECgYICgAAAA==.',
Ca='Callana:BAAANQAECgQICAAAAA==.Camedra:BAAANQAECgcIEAAAAA==.Carthella:BAAANQADCgQJBAABNQAECggIHwAJAM0SAA==.Catamynyia:BAAANQAECgMIAwAAAA==.',
Cc='Cchaos:BAAANQAECgMJAwAAAA==.',
Ce='Celaborn:BAAANQAECgUIDQAAAA==.',
Ch='Chimaira:BAAANQADCgMIAwAAAA==.Chucknoris:BAAANQADCgcJEQAAAA==.',
Cl='Claytonbigse:BAAANQABCgIJAgAAAA==.',
Cr='Crankadin:BAAANQAECggIAQABNQADCggIEQAIAAAAAA==.Crispyquinn:BAAANQADCgUIBQAAAA==.Crispysham:BAAANQAECgYIDwAAAA==.Cruciö:BAAANQADCggIDAAAAA==.Crànk:BAAANQADCggIEQAAAA==.Cránk:BAAANQAECggJCAABNQADCggIEQAIAAAAAA==.Crãnk:BAAANQAECggICAABNQADCggIEQAIAAAAAA==.',
Cu='Cullyeskie:BAAANQAECgMIBAAAAA==.Curveball:BAAANQAECgMIAwABNQAECgYIEgAIAAAAAA==.',
Cy='Cyniar:BAAANQAECgUIEQAAAA==.',
Da='Dahnu:BAAANQADCgIIAgABNQAECgQIBQAIAAAAAA==.Damerlin:BAAANQADCgIIAgAAAA==.Darkhuntress:BAAANQADCgYIBgAAAA==.Darkstär:BAABNQAECoEbAAICAAgKwRqTIgBrAgACAAgKwRqTIgBrAgAAAA==.Darkun:BAAANQADCggICAABNQAECggIJgAJAP0PAA==.',
De='Deacon:BAAANQAECgUIDwAAAA==.Deadzly:BAABNQAECoErAAQCAAkKrh7QHwB/AgACAAcKqCDQHwB/AgAFAAgKFxU+OwBwAQAGAAYKLwOzegDDAAAAAA==.Deathknights:BAAANQADCgMIAwAAAA==.Deeanne:BAAANQADCgUIDQAAAA==.Deepfriar:BAABNQAECoEcAAIKAAgK6CLVDQAuAwAKAAgK6CLVDQAuAwAAAA==.Demoniiks:BAAANQABCgcICQAAAA==.Derailed:BAAANQAECgYIDwAAAA==.Dethwing:BAAANQADCgQICAAAAA==.Dewsbelle:BAAANQADCggIFQAAAA==.',
Di='Diablognomis:BAAANQADCgcIDwAAAA==.Dirtman:BAABNQAECoEYAAIEAAcKuRc2SgD/AQAEAAcKuRc2SgD/AQAAAA==.Distillate:BAAANQADCgYIFwAAAA==.',
Dk='Dkrise:BAAANQADCgIIAgABNQAECggIJgAJAP0PAA==.',
Do='Dolphina:BAAANQADCgYIBwAAAA==.Donny:BAAANQAECgUICAAAAA==.',
Dr='Dragonic:BAACNQAFFIEGAAILAAMK2w6zCwDyAAALAAMK2w6zCwDyAAA1AAQKgSAAAwsACQrWGDMRAGkCAAsACQrWGDMRAGkCAAkAAgp3DuIqAH8AAAAA.Drewdog:BAAANQAECggIDgAAAA==.',
Du='Dubes:BAABNQAECoEbAAIMAAgKixsJBQCJAgAMAAgKixsJBQCJAgAAAA==.Dunbartian:BAAANQAECgUICQAAAA==.',
Ei='Eirote:BAABNQAECoEbAAINAAgK0Q4qAgD+AQANAAgK0Q4qAgD+AQAAAA==.',
El='Elarris:BAAANQADCgYIBgAAAA==.Eldari:BAAANQAECgUIDQAAAA==.Eledron:BAAANQAECgQIBAAAAA==.Elyssaena:BAAANQADCggIFwAAAA==.',
Em='Emotionaldmg:BAAANQAECgUIBQABNQAECggICAAIAAAAAA==.',
En='Enzojr:BAAANQAECgMIBAAAAA==.',
Er='Eriath:BAABNQAECoEhAAIOAAgKIRynEQClAgAOAAgKIRynEQClAgAAAA==.',
Ex='Exalted:BAAANQAECgIIBAABNQAFFAMIBgALANsOAA==.',
Ey='Eye:BAAANQAECgcIDgAAAA==.',
Fa='Faranth:BAABNQAECoEbAAMJAAgKcBTPEAALAgAJAAgKcBTPEAALAgAPAAIKLwoOGQBUAAAAAA==.',
Fe='Felynne:BAAANQAECgMIAwAAAA==.Feo:BAAANQAECgMIBAAAAA==.Feru:BAAANQAECgUIBQAAAA==.Ferum:BAAANQAECgcIEwAAAA==.',
Fi='Fionnan:BAAANQAECgYIEgABNQAECggIGwAQAOUKAA==.Fizwidget:BAAANQADCgEIAQAAAA==.',
Fr='Freezia:BAAANQAECgUIBQAAAA==.Frostigan:BAAANQADCgQIBAABNQAECgQIBwAIAAAAAA==.Fryeguy:BAAANQADCgQIBAAAAA==.',
Fu='Fudo:BAAANQAECgEIAQAAAA==.Fudoswrath:BAAANQADCgYJCQAAAA==.Funkysoup:BAAANQAECgUICwAAAA==.',
['Fò']='Fòrced:BAAANQADCgYIEAAAAA==.',
Ga='Gallium:BAAANQAECgIJAgAAAA==.',
Ge='Gehena:BAAANQAECgQIBAABNQAECgUIEQAIAAAAAQ==.Gemsareyum:BAAANQADCgIIAgABNQAECgkJSgARAI4lAA==.',
Gi='Girthquake:BAAANQAECgUIDAAAAA==.',
Gl='Glow:BAAANQADCggJCAAAAA==.',
Go='Goof:BAABNQAECoEXAAISAAcKVwWBgwA8AQASAAcKVwWBgwA8AQAAAA==.',
Gr='Griz:BAAANQAECgYIBgAAAA==.Grossevache:BAAANQADCgIIBAAAAA==.',
Ha='Haddor:BAAANQAECgIIAwAAAA==.Halfheart:BAAANQAECgUICwAAAA==.Hankerin:BAAANQADCgYIBwAAAA==.Harborhate:BAAANQAECgIIAgAAAA==.Harpomage:BAAANQADCggJEwAAAA==.Haunter:BAAANQAECgYIDwAAAA==.',
He='Heimdallr:BAAANQADCggJEAAAAA==.Heisenborg:BAAANQAECgQIBAAAAA==.Helldin:BAAANQAECgEIAQAAAA==.',
Hi='Hilite:BAAANQAECgQICAAAAA==.Himothyjr:BAAANQADCgcICgAAAA==.',
Ho='Holific:BAABNQAECoEZAAIHAAgK1xA/dwDeAQAHAAgK1xA/dwDeAQAAAA==.Hoss:BAAANQAECggIAQAAAA==.Hotrodranger:BAAANQAECgUIDwAAAA==.',
Hs='Hshyomouth:BAAANQADCgIIAgABNQAECgUIDwAIAAAAAA==.',
Hu='Hunters:BAAANQADCgYIBgAAAA==.Hut:BAACNQAFFIEOAAIDAAUKphvpBgC5AQADAAUKphvpBgC5AQA1AAQKgSoAAgMACQoYJIQHAIIDAAMACQoYJIQHAIIDAAAA.',
Hy='Hypearione:BAAANQABCgEIAQAAAA==.',
Ia='Iambohike:BAAANQADCgUICgAAAA==.',
Ic='Icycritties:BAAANQAECgEIAQAAAA==.',
Ih='Iheals:BAAANQADCgIIAgAAAA==.',
Im='Imjustadruid:BAAANQADCgIIAgAAAA==.Immortal:BAAANQAECgYIEgAAAA==.',
In='Incarnated:BAAANQAECggIBgAAAA==.',
Is='Iskra:BAAANQADCgIIAgAAAA==.Ispithotfire:BAAANQABCgQIBgAAAA==.',
Iu='Iu:BAAANQAECggIEQAAAA==.',
Ja='Jadecross:BAAANQADCgIIAgAAAA==.Javan:BAAANQADCgIIAgAAAA==.',
Je='Jerryatric:BAAANQAECgQICgAAAA==.',
Ji='Jiri:BAAANQABCgYJDQAAAA==.',
Jk='Jkmno:BAAANQADCgMIAwABNQADCgUIBQAIAAAAAA==.',
Jo='Joeyrains:BAAANQADCgQIBAAAAA==.',
Ju='Justblaze:BAAANQAECgQIBAAAAA==.Justincasê:BAAANQABCgMJBQAAAA==.',
Ka='Kallikan:BAAANQAECgUIDwAAAA==.Kamidk:BAAANQAECgQIBAAAAA==.Kamuri:BAAANQADCgUJBQAAAA==.Kasteen:BAAANQAECgEIAQAAAA==.Katia:BAAANQAECgQIBQAAAA==.Kaøs:BAAANQAECgEIAgAAAA==.',
Kd='Kdoggparker:BAAANQABCgYJCQAAAA==.',
Ke='Kementari:BAAANQAECgIIBAAAAA==.Kenzaki:BAABNQAECoEiAAIHAAgK+BJ/awD/AQAHAAgK+BJ/awD/AQAAAA==.',
Kh='Khaladin:BAAANQADCgYICAAAAA==.Khaosreborn:BAAANQADCgUIAQAAAA==.Khaotic:BAAANQADCgcICQAAAA==.',
Ki='Kilaaz:BAAANQAECgYIDgAAAA==.Kirveka:BAAANQABCgQIBAAAAA==.',
Kl='Kliticaldk:BAAANQADCgUIBQAAAA==.Kliticalwar:BAAANQAECgcICgAAAA==.Klothys:BAAANQAECgYIDgAAAA==.',
Kn='Knuts:BAAANQADCgMJAwABNQAECgYIBgAIAAAAAA==.',
Ko='Ková:BAAANQADCgUJCwAAAA==.',
Ku='Kuani:BAAANQAECgQIBAABNQAECgUIEQAIAAAAAA==.',
La='Landre:BAAANQADCgQIBgAAAA==.Lassy:BAAANQADCgIJAgAAAA==.Lathray:BAAANQAECgMIBAAAAA==.Lazerous:BAAANQADCgcICQAAAA==.',
Le='Lealoo:BAAANQAECgYIEgAAAA==.Legolard:BAAANQAECgMICAAAAA==.Leleia:BAAANQAECgYIBgAAAA==.',
Lh='Lhera:BAAANQAECgYIEgABNQAECggIGAATAGYcAA==.',
Li='Liath:BAAANQAECgQIBQAAAA==.Lichtenberg:BAABNQAECoEbAAMEAAgKhhyLKQCdAgAEAAgKhhyLKQCdAgAQAAUKxwirqwDAAAAAAA==.Linddori:BAAANQAECgQIBAABNQAECgYIDwAIAAAAAA==.Liori:BAAANQADCggIFQAAAA==.Lirillia:BAAANQAECgYIDwAAAA==.Lirillïa:BAAANQADCgYICwABNQAECgYIDwAIAAAAAA==.Lizzie:BAAANQADCgUIBQAAAA==.',
Lo='Locdon:BAAANQABCgIIAgABNQAECgUICAAIAAAAAA==.Lodestone:BAAANQADCgcICQAAAA==.Loena:BAAANQADCgUIBwAAAA==.Lokk:BAAANQAECgEIAQABNQAECgYIEQAIAAAAAA==.Loko:BAAANQAECgEIAQAAAA==.Lovelydread:BAAANQAECgEIAQAAAA==.',
Lu='Lunabug:BAAANQAECgIIAgAAAA==.Lupinos:BAAANQADCgIIAQAAAA==.',
Ly='Lyadra:BAAANQAECgYIEgAAAA==.Lyrissa:BAAANQADCgYIBgAAAA==.',
Ma='Mackito:BAAANQAECgEIAQAAAA==.Madan:BAAANQAECgQIBAAAAA==.Mahoushojou:BAAANQAECgIIAgABNQAECgQIBwAIAAAAAA==.Malasminna:BAAANQAECgQIBAAAAA==.Malehorelock:BAAANQAECgEIAQAAAA==.Malicioun:BAAANQABCggICgAAAA==.Malkariss:BAAANQAECgUIDwAAAA==.Mammadruid:BAAANQAECgUIBwAAAA==.Mauldis:BAAANQAECgQICgAAAA==.',
Me='Meryl:BAABNQAECoEhAAISAAgKCBiIOgA8AgASAAgKCBiIOgA8AgAAAA==.',
Mi='Miaka:BAABNQAECoEZAAIUAAgKSxWqBABIAgAUAAgKSxWqBABIAgAAAA==.Minth:BAAANQADCgcIDQABNQAECgQIBwAIAAAAAA==.Misfire:BAAANQAECgYIEgAAAA==.Mithra:BAAANQADCgEIAQAAAA==.',
Mo='Moghroth:BAAANQAECgUIDwAAAA==.Molykote:BAAANQAECgQIBAAAAA==.Monks:BAAANQADCgQIBAAAAA==.Monsterbabe:BAAANQADCgQIBQAAAA==.Moreleath:BAAANQADCgMIBAAAAA==.Mowiewowie:BAAANQABCgIIAgAAAA==.',
Mu='Mugzypatron:BAAANQADCgcIEwAAAA==.Murdrmitts:BAAANQAECgMIBAAAAA==.',
['Mã']='Mãtador:BAABNQAECoEWAAIEAAgKcyL0FQAfAwAEAAgKcyL0FQAfAwAAAA==.',
['Mä']='Mätadør:BAAANQAECgcIEgABNQAECggIFgAEAHMiAA==.',
Na='Nahryn:BAAANQAECgUIDwAAAA==.',
Ne='Nedina:BAAANQADCgUIBQAAAA==.Nerbert:BAAANQADCgYJBgABNQAECggIHwAJAM0SAA==.Neretsym:BAAANQAECgYIEQAAAA==.',
Ni='Nineva:BAAANQAECgMIBAAAAA==.',
No='Nobas:BAABNQAECoEbAAIDAAgKdAZcSgBsAQADAAgKdAZcSgBsAQAAAA==.Nonoa:BAAANQADCgQJBQAAAA==.',
Oc='Octavien:BAAANQADCgIIAgAAAA==.',
Og='Ogr:BAAANQADCgMIAwAAAA==.',
On='Onlyfeet:BAAANQAECgQIBAAAAA==.',
Op='Oppgjør:BAAANQAECgEIAQAAAA==.',
Or='Oreeree:BAAANQAECgIJAgAAAA==.Ormr:BAABNQAECoEfAAIJAAgKzRI8EQADAgAJAAgKzRI8EQADAgAAAA==.',
Os='Osteo:BAAANQAECgYIDQAAAA==.Osteoprime:BAAANQADCgUJBQAAAA==.',
Ou='Ouron:BAAANQAECgcIDQAAAA==.Outofmana:BAAANQAECgIIAwAAAA==.',
Pa='Pagoda:BAAANQADCgYJBgAAAA==.Papashrimps:BAABNQAECoEhAAMVAAkK2Rd5awB1AgAVAAkKlhZ5awB1AgAMAAEKMRrBLgBQAAAAAA==.',
Pe='Penelopee:BAAANQADCgcIEQAAAA==.Percy:BAAANQADCggIEQAAAA==.',
Ph='Phatcow:BAAANQADCgEIAQAAAA==.',
Pl='Placeholder:BAAANQAECgUIDwAAAA==.',
Po='Pojoevokest:BAAANQAECgUICQAAAA==.Pontifex:BAABNQAECoEXAAIKAAcKRBVyVgDDAQAKAAcKRBVyVgDDAQAAAA==.Portandmorph:BAAANQAECgUIDgAAAA==.Powerbottm:BAAANQAECgQIBgAAAA==.',
Pr='Priests:BAAANQADCgQIBgAAAA==.Prone:BAABNQAECoEbAAMQAAgK5QoVgQAyAQAQAAcK/QgVgQAyAQAEAAEKTgIPCgErAAAAAA==.Protarada:BAAANQADCgEIAQAAAA==.',
Qu='Quietmind:BAAANQAECgYICwAAAA==.Quinnifred:BAAANQADCgcIHAAAAA==.',
Ra='Raakotah:BAABNQAECoElAAIDAAkK5R8GDABQAwADAAkK5R8GDABQAwAAAA==.Raasclaat:BAAANQADCgcIDQAAAA==.Raelo:BAAANQAECgQIDgAAAA==.Rainbowflake:BAAANQAECgYIEwAAAA==.Raiseurmug:BAABNQAECoEbAAIWAAgK9QuREQCJAQAWAAgK9QuREQCJAQAAAA==.Rakash:BAAANQADCgcIBwAAAA==.Rarg:BAABNQAECoEVAAMCAAgKWBeeOADkAQACAAgKWBeeOADkAQAGAAEK6QInvgAkAAAAAA==.Ravia:BAAANQAECgEIAQAAAA==.',
Re='Rendysavage:BAAANQAECgYJBgAAAA==.Resco:BAAANQADCggIEgAAAA==.',
Ri='Riddle:BAABNQAECoEWAAIQAAcKag1rdABWAQAQAAcKag1rdABWAQAAAA==.Rize:BAABNQAECoEPAAIXAAYKcg5NpQBZAQAXAAYKcg5NpQBZAQABNQAECggIJgAJAP0PAA==.Rizmthetizm:BAAANQADCgEIAQAAAA==.',
Ro='Rosenrott:BAAANQAECgUIEQAAAA==.Rosepiercer:BAAANQAECgUICAAAAA==.Rouz:BAAANQAECgUIDwAAAA==.',
Ru='Ruddybear:BAAANQADCgIJAgAAAA==.',
Ry='Ryoto:BAAANQAECgUIBwAAAA==.',
Sa='Samandean:BAAANQAECgUICAABNQAECgYIEgAIAAAAAA==.',
Se='Sellena:BAAANQAECgIIAwABNQAECgYIEgAIAAAAAA==.',
Sh='Shakenn:BAAANQADCgEIAQAAAA==.Shandow:BAABNQAECoEkAAIMAAkKPR+zAwDFAgAMAAkKPR+zAwDFAgAAAA==.Shansoracle:BAAANQAECgMIBwABNQAECgkJJAAMAD0fAA==.Shed:BAAANQAECgQIBAABNQAFFAUIDgADAKYbAA==.Sheislegend:BAAANQADCgcIEgAAAA==.Shelby:BAAANQAECgUIDQAAAA==.Shocked:BAAANQAECggIAwABNQAECggICAAIAAAAAA==.',
Si='Siccinok:BAABNQAECoEbAAMMAAYKBBmYFwD4AAAVAAYK4RTIxQCpAQAMAAQKDhiYFwD4AAAAAA==.Sindorian:BAAANQADCgcIIQABNQAECgEIAQAIAAAAAA==.Sixhundrdlbs:BAABNQAECoEhAAIYAAkK0CNZAwCVAwAYAAkK0CNZAwCVAwABNQAECggIBgAIAAAAAA==.',
Sk='Skraps:BAAANQADCgEJAQAAAA==.',
Sl='Slimped:BAAANQADCgYICwAAAA==.',
Sn='Sneakybato:BAAANQADCgcIEgAAAA==.',
So='Sofie:BAAANQADCgQIBAABNQAECggIGwAEAIYcAA==.Solarial:BAAANQAECgQIBQAAAA==.Solastra:BAAANQAECgUIDwAAAA==.Soramai:BAAANQAECgEIAQAAAA==.Soth:BAABNQAECoEbAAIGAAgKwxOkOgDVAQAGAAgKwxOkOgDVAQAAAA==.',
Sp='Sparký:BAAANQAECgEIAQAAAA==.',
St='Starlyvana:BAAANQAFFAMIBAAAAA==.Staryxia:BAAANQAECgcIEQAAAA==.Statiic:BAAANQABCgIIBQAAAA==.Steamdruid:BAAANQADCggICQABNQAECgUIDwAIAAAAAA==.Steephany:BAAANQADCgMIBAAAAA==.Stonecross:BAAANQAECgUJCgAAAA==.Stormbolt:BAAANQAECgYIEgAAAA==.Stormspirit:BAAANQADCggIGwAAAA==.Striggen:BAAANQAECgQIBQAAAA==.',
Su='Sugarsham:BAAANQAECgYIDAAAAA==.Sulwen:BAACNQAFFIEUAAIDAAcKACZoAAANAwADAAcKACZoAAANAwA1AAQKgSIAAgMACQqUJjgCAM4DAAMACQqUJjgCAM4DAAAA.Sumerset:BAAANQAECgQIBAAAAA==.Sundave:BAAANQAECgEJAgAAAA==.Supaflytnt:BAAANQAECgYIDgAAAA==.Sustia:BAAANQADCggIEQAAAA==.',
Ta='Taera:BAAANQAECgUIEQAAAA==.Talavenn:BAAANQAECgcIEgAAAA==.Tarage:BAAANQADCggIDgAAAA==.Taurîel:BAAANQADCgYIBgAAAA==.',
Te='Tectoniiks:BAAANQAECgcIBwAAAA==.Tedds:BAAANQAECgUJCAAAAA==.Teds:BAAANQADCgYICwAAAA==.Tempus:BAAANQAECgMJAwAAAA==.Teriko:BAABNQAECoEYAAIFAAcKfxmhKwDdAQAFAAcKfxmhKwDdAQAAAA==.Teviro:BAAANQADCgEIAQABNQAECggIGAATAGYcAA==.',
Th='Thequixote:BAAANQAECgQIBQAAAA==.',
Ti='Tictok:BAAANQADCgYIBgAAAA==.',
To='Toaderic:BAAANQAECgUIDQAAAA==.Tots:BAABNQAECoEhAAIZAAgKexwICACWAgAZAAgKexwICACWAgAAAA==.Toxictotes:BAAANQADCgEIAQAAAA==.',
Tr='Trazah:BAAANQADCgEIAQAAAA==.',
Ty='Tyraèl:BAABNQAECoEeAAISAAkKwiJ8BQCNAwASAAkKwiJ8BQCNAwAAAA==.Tyzy:BAABNQAECoEfAAMDAAkKJCSXCAB2AwADAAkKJCSXCAB2AwAaAAgK4xoJEACcAgAAAA==.',
Va='Valenora:BAAANQAECgUIDgAAAA==.Valvitor:BAAANQADCgEIAQAAAA==.Varuz:BAAANQAECgYIEQAAAA==.Varyz:BAAANQADCgIIAgABNQAECgYIEQAIAAAAAA==.',
Ve='Velanie:BAAANQAECgEIAQAAAA==.Veloon:BAABNQAECoEbAAIDAAkKVRHyMgAEAgADAAkKVRHyMgAEAgAAAA==.Verinari:BAAANQADCgUIDgAAAA==.',
Vi='Vipul:BAAANQADCgUIDQABNQADCgYIBwAIAAAAAA==.Viridria:BAAANQAECgQIBwAAAA==.Vityazi:BAAANQAECgMIAwAAAA==.',
Vl='Vlado:BAAANQADCgQIBQAAAA==.',
Vo='Voodoobootie:BAAANQABCgcJBwAAAA==.',
Vy='Vy:BAAANQADCgUICQAAAA==.',
['Vè']='Vè:BAAANQAECgcIDwAAAA==.',
Wa='Warriors:BAABNQAECoEhAAIXAAgKLyIMKADwAgAXAAgKLyIMKADwAgAAAA==.Wartooth:BAAANQAECgUIDwAAAA==.Wassergott:BAAANQADCgcIBwAAAA==.',
We='Webicus:BAAANQAECgMIBAAAAA==.Wendee:BAAANQAECgUICAAAAA==.',
Wh='Whitley:BAAANQAECgYIEgAAAA==.',
Wi='Wildspart:BAAANQAECgIIAgAAAA==.',
Wo='Wooden:BAAANQAECgQIDgAAAA==.',
Xa='Xaphy:BAAANQAECgQIBgAAAA==.Xardots:BAAANQAECgYIDgABNQAECgUIDwAIAAAAAA==.',
Xi='Xiareth:BAAANQAECgUICwAAAA==.',
Xy='Xyleiah:BAAANQADCgYIBgABNQAECggIGwAJAHAUAA==.',
['Xá']='Xároth:BAAANQAECgUIDwAAAQ==.',
Ya='Yargue:BAAANQAECgIIAgAAAA==.',
Ye='Yeeyee:BAAANQAECggICAAAAA==.',
Yi='Yirï:BAAANQABCgIIBAAAAA==.',
Yo='Youngjeezy:BAAANQAECgIIBAAAAA==.Yoursinpride:BAAANQAECggIDgAAAA==.',
Za='Zackor:BAAANQADCgUIDAAAAA==.',
Ze='Ze:BAAANQADCgYICgAAAA==.Zervann:BAAANQADCgYIBgAAAA==.',
Zi='Ziska:BAAANQADCgIIAgAAAA==.',
Zo='Zorithic:BAAANQAECgIJAwAAAA==.',
Zy='Zyde:BAAANQAECgEIAQABNQAECgYIEQAIAAAAAA==.',
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
