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

local lookup = {'Unknown-Unknown','Priest-Holy','DemonHunter-Vengeance','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Paladin-Protection','Warrior-Arms','Shaman-Restoration','Evoker-Devastation','Druid-Balance','Mage-Arcane','Paladin-Holy','DeathKnight-Unholy','Rogue-Assassination','Warlock-Demonology','Warlock-Destruction','Rogue-Outlaw','Druid-Feral','Warlock-Affliction','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','DeathKnight-Frost','Warrior-Fury','Warrior-Protection','Druid-Restoration','Monk-Windwalker','Shaman-Elemental','Evoker-Augmentation','Rogue-Subtlety',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Accost:BAAANQADCgcIDQAAAA==.Acronica:BAAANQAECgMJAwAAAA==.',
Ad='Addilynn:BAAANQABCgEIAQAAAA==.',
Ak='Akassa:BAAANQADCgcICwAAAA==.Aknologia:BAAANQAECgQIBgABNQAECgcJDgABAAAAAA==.',
Al='Alecto:BAAANQAECgEIAgAAAA==.Allele:BAAANQADCggIEgAAAA==.Allet:BAAANQADCgUJBQABNQADCgYIDAABAAAAAA==.',
Am='Amarah:BAABNQAECoEcAAICAAgKKRtDIQCHAgACAAgKKRtDIQCHAgAAAA==.Ameilie:BAABNQAECoEaAAICAAgKhx8/HwCTAgACAAgKhx8/HwCTAgAAAA==.',
An='Anapuwae:BAAANQAECgUIEQAAAA==.Animehero:BAABNQAECoEbAAIDAAgKMSBwAgDwAgADAAgKMSBwAgDwAgAAAA==.',
Ar='Arcant:BAAANQAECgUJCwAAAA==.Ardicov:BAAANQADCgQIBQAAAA==.Argadin:BAAANQAECgIIAgABNQAECgkJFwAEANYXAA==.Argrekh:BAABNQAECoEXAAMEAAkK1hdxKQCPAgAEAAkK1hdxKQCPAgAFAAEKQQ8WVwBAAAAAAA==.Argreks:BAAANQADCgEIAQABNQAECgkJFwAEANYXAA==.Argrekt:BAAANQAECgIIAgABNQAECgkJFwAEANYXAA==.Aridol:BAAANQADCgYIBgAAAA==.Arigön:BAAANQADCgEIAQAAAA==.Aronna:BAAANQADCgYIBwAAAA==.Arosea:BAAANQADCgYIBgAAAA==.Arthaslk:BAABNQAECoEkAAMGAAkKBh8GFQAxAwAGAAkKBh8GFQAxAwAHAAIKBAkdQABbAAABNQAECggILQAIAOEcAA==.Aryssol:BAAANQADCggIDgAAAA==.',
At='Ate:BAAANQAECgUJDgAAAA==.Attman:BAABNQAECoEaAAIJAAgKDSCBGQC+AgAJAAgKDSCBGQC+AgAAAA==.',
Au='Auradawn:BAAANQADCgcIDwAAAA==.',
Ba='Baeator:BAAANQAECgEIAQABNQAFFAYIDQAKAMgIAA==.Balho:BAAANQABCgEIAgAAAA==.Barneystins:BAAANQABCgEIAgABNQADCgQIBAABAAAAAA==.',
Be='Bearmane:BAABNQAECoEbAAILAAgKqSAJFADjAgALAAgKqSAJFADjAgAAAA==.Beastarsfan:BAAANQAECgUICwAAAA==.Behmow:BAABNQAECoEZAAIIAAkK4iSDBgCpAwAIAAkK4iSDBgCpAwAAAA==.Belithel:BAAANQAECgQIBgABNQAECgYIDAABAAAAAA==.Bencreepin:BAAANQAECgIIBQAAAA==.Bernoulli:BAAANQAECgYIDwAAAA==.',
Bi='Bigspitter:BAAANQADCgYIBgABNQAECgYIEgABAAAAAA==.Bis:BAAANQADCgUJBQABNQAECgkJFgAMABkdAA==.',
Bl='Blessedxx:BAAANQAECgEIAQAAAA==.Bloodboo:BAAANQADCgQIBAAAAA==.Bloodyhpally:BAACNQAFFIEMAAINAAYKoBReAgAKAgANAAYKoBReAgAKAgA1AAQKgRwAAg0ACQq1GHAWANkCAA0ACQq1GHAWANkCAAAA.',
Bo='Boopsnoopems:BAAANQAECgEIAQAAAA==.',
Br='Bradcrit:BAAANQAECgEIAQAAAA==.',
Bu='Bubble:BAAANQAECgQIDAAAAA==.Burrfoot:BAAANQAECgIIAwAAAA==.Bustah:BAAANQAECgcIEAABNQAECggIFwAOAC8cAA==.',
Bw='Bwoodmorgan:BAAANQAECgUICgAAAA==.',
Ca='Calene:BAABNQAECoEqAAIPAAkK8yAeBgAuAwAPAAkK8yAeBgAuAwAAAA==.Cannedcorn:BAAANQAECgIIAgAAAA==.Caperusin:BAAANQAECgQIBAAAAA==.Casare:BAAANQADCgYIFAAAAA==.Cayde:BAAANQADCgYJBgABNQAECgkJKAAEAPEeAA==.',
Ce='Celestinee:BAAANQAECgYIBgAAAA==.Cenarian:BAAANQABCgQIBwAAAA==.',
Ch='Chape:BAABNQAECoEdAAMNAAkKvhdQIQCRAgANAAkKvhdQIQCRAgAGAAYKXBJDigBjAQAAAA==.Chochalinda:BAAANQAECgQIBQAAAA==.',
Ci='Cinderlee:BAAANQAECgEJAQAAAA==.',
Co='Colexn:BAAANQAECgcIDwAAAA==.Cong:BAACNQAFFIEFAAIIAAQK/gYJDgAMAQAIAAQK/gYJDgAMAQA1AAQKgRcAAggACQpBFyI0AJcCAAgACQpBFyI0AJcCAAAA.Corg:BAAANQADCgYIBgAAAA==.Cornchipz:BAAANQAECgcJDgAAAA==.',
Cr='Crapsack:BAAANQABCgEIAQAAAA==.Croski:BAAANQADCgEIAQAAAA==.Cryonidus:BAAANQAECgEIAQAAAA==.',
Cu='Curves:BAAANQAECgEIAQAAAA==.',
Da='Daangalanng:BAAANQAECgQICwAAAA==.Daegra:BAAANQAECggJEgAAAA==.Dankkush:BAAANQADCgQIBAAAAA==.Darkacedia:BAABNQAECoEbAAMQAAgKIhegRQAHAgAQAAcKNhigRQAHAgARAAMKKwrbPwCfAAAAAA==.',
De='Dealosed:BAABNQAECoEZAAMPAAgKWhl7EQB7AgAPAAgKORl7EQB7AgASAAQKORPMDQAEAQAAAA==.Deathawolf:BAAANQAECgEIAQAAAA==.Deathkilera:BAAANQADCgUIBwAAAA==.Defy:BAAANQADCgYIBgAAAA==.Delenn:BAABNQAECoEXAAITAAgKERvLBgBgAgATAAgKERvLBgBgAgAAAA==.Demonnyaa:BAAANQADCgcIBwAAAA==.Derzy:BAAANQADCgIIAgAAAA==.Dewygirl:BAAANQADCgQIBwAAAA==.',
Di='Disastastab:BAABNQAECoEWAAMSAAgKRBzGAwChAgASAAgKRBzGAwChAgAPAAcKDBTUIADVAQAAAA==.Dive:BAABNQAECoEWAAIMAAkKGR0GLgAFAwAMAAkKGR0GLgAFAwAAAA==.',
Do='Doogru:BAAANQAECgUJEAAAAA==.Doogtwo:BAAANQADCggIFgABNQAECgUJEAABAAAAAA==.Doryndoran:BAAANQAECgQIBQAAAA==.Dorynhashots:BAAANQADCgUIBQAAAA==.Dotproduct:BAAANQADCgEIAQABNQADCgIIAgABAAAAAA==.Dotsrock:BAAANQAECgIIAgAAAA==.Dovah:BAAANQADCgIIAgAAAA==.',
Dr='Dragoneggs:BAAANQAECggIEgAAAA==.Dragonforce:BAAANQADCggIEgAAAA==.Drakonutz:BAAANQAECgQIBwAAAA==.Draxx:BAAANQAECggIBwAAAA==.Drañzer:BAAANQAECgEIAQAAAA==.Dreammachine:BAAANQADCgQIBwAAAA==.Drjoel:BAAANQADCgcIEQAAAA==.Drunkenutz:BAAANQAECgQICQAAAA==.Dräx:BAAANQAECggJDQAAAA==.',
Dw='Dwallen:BAAANQADCgIIAgAAAA==.Dwightschrut:BAAANQADCgQIBAAAAA==.',
['Dä']='Dälf:BAAANQAECgIIAgABNQAFFAcIBwAHAFoRAA==.',
Ea='Earthshocker:BAAANQAECgMIBAAAAA==.',
El='Elenix:BAAANQAECgcIAQAAAA==.Elmesia:BAAANQAECgMJBgAAAA==.Eloris:BAAANQAECgcIEgAAAA==.Elpato:BAAANQADCgcIBwABNQAECgYIEgABAAAAAA==.Elthyn:BAAANQAECgEJAQAAAA==.Elvar:BAAANQADCgUIBQAAAA==.',
Em='Emachine:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Emeraldrin:BAAANQADCgEIAQAAAA==.Emz:BAABNQAECoEZAAISAAgKUR5nAwC4AgASAAgKUR5nAwC4AgAAAA==.',
En='Eniar:BAAANQAECgEIAQAAAA==.',
Er='Erakk:BAAANQADCgEIAgAAAA==.Erianda:BAAANQABCgQIBAAAAA==.Eric:BAABNQAECoEXAAIIAAcKvxreWAAKAgAIAAcKvxreWAAKAgAAAA==.Eroninja:BAAANQAECgIJAgABNQAECgYIDAABAAAAAA==.Erín:BAAANQAECgQJBQAAAA==.',
Eu='Eurong:BAABNQAECoEaAAILAAkKsBYiHwB2AgALAAkKsBYiHwB2AgAAAA==.',
Ez='Ezynuff:BAAANQAECgMIBgAAAA==.',
Fa='Fapple:BAAANQADCgQIBAABNQAECgcIEwABAAAAAA==.Fatesworn:BAAANQADCgcIBwAAAA==.Faïry:BAABNQAECoEYAAIEAAgKGyCwHgDDAgAEAAgKGyCwHgDDAgAAAA==.',
Fe='Felwyrm:BAABNQAECoEhAAIQAAkK9BWEKgB3AgAQAAkK9BWEKgB3AgAAAA==.',
Fo='Foragh:BAAANQAECgUIBgAAAA==.Foxi:BAAANQADCggIEQABNQAECgQICQABAAAAAA==.',
Fr='Freakbeast:BAAANQAECgYJEgABNQAFFAIIAgABAAAAAA==.Fries:BAEANQAECgcJBwABNQAECggJBwABAAAAAA==.',
Fu='Fullkidney:BAAANQAFFAIJAwAAAA==.Funch:BAABNQAECoEXAAIUAAgKcRI2BAAvAgAUAAgKcRI2BAAvAgAAAA==.',
Ga='Gaefaeryn:BAABNQAECoEXAAMVAAcKnRVMGwD6AQAVAAcKnRVMGwD6AQAWAAEKmgFkIQAhAAAAAA==.Garonnaa:BAAANQAECgcIDwAAAA==.Garthel:BAAANQAECgIIAgAAAA==.',
Ge='Genetiks:BAAANQADCgYIDAAAAA==.',
Gh='Ghari:BAAANQAECgYIEAAAAA==.',
Gi='Gingerlock:BAAANQAECgYICwAAAA==.Giyuu:BAAANQADCgUIBQAAAA==.',
Gn='Gnoblin:BAAANQADCggJFAAAAA==.',
Gr='Greka:BAAANQAECgEIAQAAAA==.Greylooms:BAAANQADCgcIBwAAAA==.Griplock:BAAANQAECgUIDQAAAA==.',
['Gö']='Gözër:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Ha='Happyfriend:BAAANQAECgEIAQABNQAECgkJIQAQAPQVAA==.',
He='Healalle:BAAANQADCgYICwABNQAECgQICQABAAAAAA==.Healhole:BAAANQAECgYIEQAAAA==.Heàl:BAAANQAECgIIBAAAAA==.',
Hi='Hidolo:BAAANQADCgYIDAAAAA==.',
Hu='Hunterishard:BAAANQAECgQIBAAAAA==.',
Hy='Hylaina:BAAANQADCgYJCgAAAA==.',
['Hô']='Hôlÿ:BAAANQADCggIDgAAAA==.',
Ia='Iamamonk:BAAANQADCgEIAQAAAA==.',
Ik='Ikerous:BAAANQADCgMIAwAAAA==.',
Im='Imadwagon:BAAANQADCgcIAgAAAA==.Imcolorblind:BAAANQADCgIIAgAAAA==.Imhammered:BAAANQAECgYIDgAAAA==.',
Io='Iounn:BAAANQADCgcIBwABNQAECgYIEQABAAAAAA==.',
It='Itiswhatitiz:BAABNQAECoEVAAIEAAcKshm8QgAuAgAEAAcKshm8QgAuAgAAAA==.Itsybityshiv:BAAANQAECgcIEwAAAA==.',
Ja='Jakarr:BAAANQADCgQIBAAAAA==.',
Jh='Jhani:BAAANQAECgIJAgAAAA==.',
Ji='Jiu:BAAANQAECggIDgABNQAECggIFwAOAC8cAA==.',
Jo='Joethemage:BAAANQAECgUJCwAAAA==.',
Ju='Jungol:BAAANQADCgUICQAAAA==.',
Ka='Kamin:BAAANQAECgYIBgABNQAECgkJIgAMAEgdAA==.Katamaran:BAAANQABCgEIAQABNQAECgkJGAAVALcWAA==.Kaykaypally:BAAANQAECgYIDQAAAA==.',
Ke='Kellan:BAAANQADCggICAAAAA==.',
Kh='Khybyr:BAAANQADCgMIAwAAAA==.',
Ki='Kidata:BAAANQAECgYIEQAAAA==.Kinji:BAAANQAECgQIBAABNQAECgYIDAABAAAAAA==.',
Ko='Konfu:BAAANQADCgcIEQAAAA==.Korral:BAAANQADCggIDQAAAA==.',
Kr='Krispies:BAAANQAECgUICAAAAA==.Kristysavage:BAAANQAECgcIEQAAAA==.',
Ku='Kulaesca:BAABNQAECoEgAAMQAAkKaBciIgCgAgAQAAkKaBciIgCgAgARAAEK7QDDcAAhAAAAAA==.',
Ky='Kynar:BAACNQAFFIEPAAMXAAYKUxJcBgBuAQAXAAYKEQlcBgBuAQAYAAQKiBFwBAAgAQA1AAQKgR8AAxgACQriJdwDAIADABgACQriJdwDAIADABcAAwofFRZtALsAAAAA.Kyua:BAAANQADCggJCAAAAA==.',
La='Ladragona:BAAANQADCggICAAAAA==.Lambshot:BAAANQAECgYICQAAAA==.Lambsy:BAACNQAFFIERAAQIAAYKRBFgBAD1AQAIAAYKKxBgBAD1AQAZAAEK5AZ7AgBRAAAaAAEKEAzcBABDAAA1AAQKgSAAAwgACQoLJKARAFADAAgACQoHJKARAFADABkAAwoCE5oVALcAAAAA.Lanamama:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Lanana:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Le='Lerat:BAAANQAECgYJDgAAAA==.',
Li='Lightwarden:BAAANQADCgQIBAAAAA==.Lilyy:BAABNQAECoEZAAIMAAgKlhigVACOAgAMAAgKlhigVACOAgAAAA==.Lisanalgaib:BAABNQAECoEbAAIGAAgKNBbXSAAwAgAGAAgKNBbXSAAwAgAAAA==.Lizzimcguire:BAABNQAECoEfAAIKAAgKwyGHBQAJAwAKAAgKwyGHBQAJAwAAAA==.',
Lo='Lobobare:BAABNQAECoEfAAIbAAgK2x2FDgCAAgAbAAgK2x2FDgCAAgAAAA==.Loraen:BAAANQAECgQJBAAAAA==.',
Lu='Lunarmon:BAAANQADCgUIBQAAAA==.Lunchable:BAAANQAECgQJCgAAAA==.',
Ma='Maevora:BAAANQAECgQIBQAAAA==.Makaroni:BAAANQADCgUIBwAAAA==.Manticus:BAAANQADCgYICAAAAA==.Marni:BAAANQAECgEIAQAAAA==.Marsrover:BAAANQAECgIIAgABNQAFFAYIDwAIAGMaAA==.Martel:BAAANQADCgQIBAAAAA==.Matroxx:BAABNQAECoEjAAIcAAkKliIjBQBQAwAcAAkKliIjBQBQAwAAAA==.',
Me='Meenoi:BAABNQAECoEXAAIOAAgKLxzzGwCHAgAOAAgKLxzzGwCHAgAAAA==.Mellotots:BAAANQABCgIIBAAAAA==.Metatron:BAAANQADCgIIAgAAAA==.',
Mi='Miadas:BAAANQAECgMIAwABNQAECggIGgATAJUdAA==.Mimikyu:BAAANQABCgYIBgAAAA==.',
Mo='Moardotsnow:BAAANQAECgYIEgAAAA==.Moby:BAAANQAECgEJAgAAAA==.Moistmender:BAAANQADCgYIDAAAAA==.Mortiana:BAAANQADCggICAAAAA==.',
Mu='Murridan:BAAANQAECgUJBgAAAA==.',
My='Mykaela:BAAANQAECgEJAQAAAA==.',
['Më']='Mëow:BAAANQAECgIIAgAAAA==.',
Na='Narrath:BAAANQADCgMJAwAAAA==.Nayalaah:BAAANQAECgEJAQAAAA==.',
Ne='Nehpets:BAAANQADCgUIBQAAAA==.Nephelym:BAAANQAECgcJDgAAAA==.Nerv:BAAANQADCgMIBQAAAA==.',
Ni='Nicolasmage:BAAANQABCgMIAwAAAA==.Nirina:BAAANQAECgEIAQAAAA==.',
No='Nohtil:BAAANQADCgUIDAAAAA==.Notstephen:BAAANQAECgYJBgABNQAECgcJDAABAAAAAA==.Nourishnutz:BAAANQADCgYIBgAAAA==.',
Nu='Nut:BAAANQAECgQIDAABNQAECgUJDgABAAAAAA==.',
Nw='Nwalliance:BAAANQAECgEIAQAAAA==.',
['Nö']='Nötprepared:BAAANQADCgUJDgABNQAECgUJBQABAAAAAA==.',
Oi='Oiflar:BAAANQAECgUIDgABNQAECgcIEwABAAAAAA==.',
Ol='Olangi:BAAANQAECgEIAQAAAA==.',
Om='Omnidh:BAAANQADCggJEAABNQAECgkJGgAcAE0kAA==.Omnipotent:BAAANQADCggICAAAAA==.',
On='Onepavo:BAAANQAECgYJBwAAAA==.',
Oo='Oogie:BAAANQADCgYIBgAAAA==.Oogrikusk:BAAANQADCgIIAgAAAA==.',
Op='Oppose:BAAANQAECgQICAAAAA==.',
Or='Orexion:BAAANQAECgYIDQAAAA==.Ormagöden:BAAANQAECgYIEQAAAA==.',
Ov='Overpower:BAAANQADCgYIBgAAAA==.',
Pa='Palladean:BAAANQAECgIIAwAAAA==.Palphen:BAAANQAECgcJDAAAAA==.Panako:BAAANQAECgQJBAAAAA==.Pastasauce:BAAANQAECgYIEQAAAA==.',
Pe='Pegero:BAAANQADCgYIDQABNQAECggIDgABAAAAAA==.Penelohpe:BAABNQAECoEiAAIMAAkKSB0jPgDRAgAMAAkKSB0jPgDRAgAAAA==.',
Ph='Phatt:BAAANQADCgYIBgAAAA==.Phoenixdrac:BAAANQADCggICQAAAA==.Phoon:BAEBNQAECoEaAAMQAAkKbSDgIQChAgAQAAcKySLgIQChAgARAAQK+BohIQBEAQAAAA==.Phoondk:BAEANQAECgUICAABNQAECgkJGgAQAG0gAA==.',
Pi='Piggy:BAAANQAECgEIAQAAAA==.Pita:BAAANQABCgYIBgAAAA==.Pizzadriver:BAACNQAFFIEPAAIIAAYKYxrhAgAuAgAIAAYKYxrhAgAuAgA1AAQKgR4AAwgACQoAJZEPAF4DAAgACQoAJZEPAF4DABkAAQrVIzUcAF4AAAAA.',
Pl='Plaguefist:BAAANQADCgcIBwABNQADCggIEgABAAAAAA==.Plata:BAAANQAECgUJBQAAAA==.',
Po='Poosicat:BAAANQABCgYIBgAAAA==.Poosycat:BAAANQABCgYICAAAAA==.',
Pr='Praytroxx:BAAANQAECgIIBAABNQAECgkJIwAcAJYiAA==.Premonitions:BAAANQAECgIIAgAAAA==.Premune:BAABNQAECoEbAAINAAgKnBe6KQBgAgANAAgKnBe6KQBgAgAAAA==.Prion:BAAANQAECgUIBQAAAA==.',
Pu='Pucco:BAAANQADCgIIAgAAAA==.Putrav:BAAANQAECgEIAQAAAA==.',
Py='Pyrena:BAAANQADCgEIAQAAAA==.Pyroclasm:BAAANQAECgUICgAAAA==.',
Qu='Quigly:BAAANQADCgIIAgAAAA==.',
Ra='Ragingfluids:BAAANQAECgQIBAAAAA==.Rahdek:BAAANQADCgMIAwAAAA==.Raine:BAACNQAFFIERAAIJAAYKaBGjAgDzAQAJAAYKaBGjAgDzAQA1AAQKgSAAAwkACQrDFO8uAD8CAAkACQrDFO8uAD8CAB0ABApaFKuMAPgAAAAA.Raistlin:BAAANQADCgEIAQAAAA==.Ralfio:BAAANQAECgcIEwAAAA==.Rasq:BAAANQAECgQJBAAAAA==.Rat:BAAANQAECggIEwAAAA==.Raynith:BAABNQAECoEaAAMTAAgKlR2fCAAcAgATAAYK5hyfCAAcAgALAAcKQBatLQD5AQAAAA==.',
Rd='Rdyoshy:BAAANQADCgUIBQAAAA==.',
Re='Readycheck:BAAANQAECgUICQAAAA==.Reflex:BAAANQAECgIIAgAAAA==.Regirock:BAAANQABCgMIBAAAAA==.Rellek:BAAANQAECgIIAgAAAA==.Remulous:BAAANQAECgMIBAAAAA==.Retallica:BAAANQAECgQIBQAAAA==.Revali:BAABNQAECoEoAAMEAAkK8R5XIQC1AgAEAAkKnBxXIQC1AgAFAAkKBRf9EQCQAgAAAA==.Revelaen:BAAANQAECgIIAwABNQAECgkJKAAEAPEeAA==.',
Ri='Rick:BAABNQAECoEWAAMFAAkKlx8jCwDxAgAFAAkKKh8jCwDxAgAEAAQK4h1lpgASAQAAAA==.',
Rm='Rmagep:BAAANQAECgUICwAAAA==.',
Ro='Roadhouse:BAAANQADCgQIBQAAAA==.Roshango:BAAANQADCgYIBgAAAA==.Rosinator:BAAANQAECggIAQAAAA==.Rouk:BAAANQAECgQIBAABNQAFFAIIAgABAAAAAA==.Rowgar:BAAANQAECgQIBAAAAA==.',
Ru='Rubenslik:BAAANQAECgYIEAAAAA==.',
['Rá']='Ráts:BAAANQAECgYJBQAAAA==.',
Sa='Saelyn:BAAANQADCggIBgAAAA==.Saephora:BAAANQAECgYIBgAAAA==.Saggypants:BAAANQAECgYICgAAAA==.Sakurai:BAAANQAECgEIAQABNQAECggIGAAMAPcOAA==.Salamander:BAAANQAECgUJCgAAAA==.Sammel:BAAANQAECgUIEAAAAA==.Sanari:BAAANQADCgUIBwABNQAECgYIDAABAAAAAA==.Sangwine:BAAANQADCgYIBgAAAA==.Sapphica:BAAANQADCgYJCQAAAA==.Sathreina:BAABNQAECoEZAAIGAAgKrhIQUgAOAgAGAAgKrhIQUgAOAgAAAA==.',
Sc='Scaries:BAAANQAECgcIDwAAAA==.Scootko:BAAANQAFFAIIAgAAAA==.Scuss:BAAANQADCggICAAAAA==.',
Se='Sego:BAAANQADCgYJGQAAAA==.Severson:BAAANQAECgcJEAAAAA==.Sey:BAAANQADCgYIBgAAAA==.',
Sh='Shadowapoke:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Shadowisbad:BAABNQAECoEYAAIVAAgKURpEEQCMAgAVAAgKURpEEQCMAgAAAA==.Shadvoker:BAAANQAECgcIEgAAAA==.Shamaneggs:BAAANQAECgEJAQAAAA==.Shamatroxx:BAAANQAECgYIEQABNQAECgkJIwAcAJYiAA==.Shamberry:BAAANQADCgcICQAAAA==.Shambles:BAAANQADCgYICQAAAA==.Shieldwalle:BAAANQAECgQICQAAAA==.Shinobukocho:BAAANQADCgQJBAAAAA==.Shotigolova:BAAANQADCgEIAQAAAA==.',
Si='Sidesalad:BAAANQADCgQIBwAAAA==.Sidric:BAAANQAECgUJDAAAAA==.Silre:BAAANQADCggIEwAAAA==.Sim:BAAANQAECgcJEwAAAA==.Sipplex:BAAANQADCgQIBAAAAA==.',
Sl='Slander:BAAANQAECgQJBAABNQAECgUJCgABAAAAAA==.Slanderous:BAAANQADCgEJAQABNQAECgUJCgABAAAAAA==.',
Sn='Snuudle:BAAANQAECgcIDwABNQAECgkJHAAQADkYAA==.',
So='Solokills:BAAANQADCgMIAwABNQAECggIDgABAAAAAA==.Sophia:BAAANQAECgcIEAAAAA==.Soundtrack:BAAANQADCgYICQABNQAECgIIAgABAAAAAA==.Soyshine:BAAANQADCgYIBgAAAA==.',
Sq='Squab:BAABNQAECoEYAAILAAgKBSABFADkAgALAAgKBSABFADkAgAAAA==.Squanchy:BAAANQADCgYJCAAAAA==.',
St='Stabbywixx:BAAANQAECgIIAgAAAA==.Starwnd:BAABNQAECoEUAAIQAAcKjBfqPgAhAgAQAAcKjBfqPgAhAgABNQAFFAUJCAAeAPkIAA==.Sterìs:BAAANQAECgEIAQAAAA==.Stickman:BAAANQADCggICAABNQAECgkJIQAQAPQVAA==.Stillcreepin:BAAANQADCgcJEgAAAA==.Storienn:BAAANQAECgUICgAAAA==.Stormzpaly:BAAANQAECgYICwAAAA==.',
Su='Suküna:BAAANQADCggIFwAAAA==.Sunbur:BAAANQADCgYICgAAAA==.Sunglo:BAAANQAECgIIAgAAAA==.Surch:BAAANQADCgEIAQAAAA==.',
Sw='Swaption:BAAANQAECgcJEAAAAA==.Sweetie:BAAANQADCgEIAQAAAA==.',
Sy='Syrelia:BAABNQAECoEYAAIMAAgKVRAwhQAKAgAMAAgKVRAwhQAKAgAAAA==.',
['Só']='Sónny:BAAANQABCgIIAgAAAA==.',
Ta='Tablescraps:BAAANQABCggICAABNQADCgIIAgABAAAAAA==.Tassarosea:BAAANQADCggIGAABNQAECggJHwAKAMMhAA==.Tauloe:BAAANQAECgEJAQAAAA==.Tayna:BAAANQABCgMJBAAAAA==.',
Te='Tenderoni:BAAANQADCgEIAQAAAA==.',
Th='Thatsmyhorse:BAAANQADCgIIAgAAAA==.Thomosaurus:BAAANQADCggIDAAAAA==.Thraly:BAAANQADCgYIBwAAAA==.Thunk:BAAANQAECgQIBgABNQAECgcJEwABAAAAAA==.',
Ti='Timdawg:BAAANQAECgUICAABNQAFFAUIDwAQAEEaAA==.Timmolate:BAACNQAFFIEPAAQQAAUKQRpPBgBbAQAQAAQKWRZPBgBbAQARAAIKwReMBgC1AAAUAAEKJBLCBgBQAAA1AAQKgR4AAxEACQrvI9EHAGgCABEACAoBF9EHAGgCABAABwp9HzIzAFECAAAA.',
To='Tomcruise:BAAANQAECgIIAgAAAA==.Tomotostein:BAABNQAECoEYAAIGAAgK2hgfRABDAgAGAAgK2hgfRABDAgAAAA==.Tornado:BAAANQABCgQICQAAAA==.',
Tr='Tristîtia:BAAANQAECgcJCwAAAA==.',
Ts='Tsuma:BAAANQABCgIIAgAAAA==.Tsume:BAAANQADCggJCAAAAA==.',
Tt='Ttomas:BAAANQAECgcICwAAAA==.',
Ty='Tyrinn:BAAANQADCgUJBQAAAA==.Tyv:BAAANQAECgYJDwAAAA==.',
Uz='Uzì:BAAANQADCgIIAgAAAA==.',
Va='Vainatetosix:BAAANQAECgUJBQAAAA==.Vallodon:BAAANQAECgYIDgAAAA==.Vantablack:BAAANQABCgIJAgABNQABCgQICQABAAAAAA==.Vanwolfy:BAAANQAECgYJCwAAAA==.Vaylorian:BAAANQAECgEJAQAAAA==.',
Ve='Velectran:BAAANQADCgUICgABNQAECggIGAAMAFUQAA==.Velorian:BAAANQADCgMIAwAAAA==.Velveeta:BAAANQAECgEIAgAAAA==.',
Vf='Vfacer:BAAANQADCgEIAQAAAA==.',
Vi='Vikav:BAAANQADCgIIAgAAAA==.Vikimg:BAAANQAECgEIAQAAAA==.',
Vo='Voodoomike:BAAANQAECgQJBAAAAA==.Vortash:BAAANQADCgUIBwAAAA==.',
Vy='Vynle:BAAANQAECgEIAQAAAA==.',
Wa='Warheimer:BAAANQAECgYICQAAAA==.Warrgodx:BAABNQAECoEtAAMIAAgK4RzpMgCdAgAIAAgK4RzpMgCdAgAZAAEKygjwIQA3AAAAAA==.',
Wh='Whoknows:BAAANQADCgIIAgAAAA==.',
Wo='Woogi:BAAANQADCgUIBQAAAA==.',
Wr='Wrongwookie:BAABNQAECoEYAAIdAAgKsBXXMwA0AgAdAAgKsBXXMwA0AgAAAA==.',
Ya='Yapper:BAAANQADCgMIAwAAAA==.',
Yo='Yolanda:BAAANQAECgIIAgAAAA==.Yoyohunty:BAAANQADCgYJBgAAAA==.',
Za='Zabada:BAAANQADCgcIDQAAAA==.Zandrea:BAAANQAECgQIBAABNQAECgkJGAAVALcWAA==.Zariee:BAAANQABCgIJAwAAAA==.',
Ze='Zehz:BAAANQAECggICAAAAA==.Zemsen:BAABNQAECoEnAAIMAAkKIB7SLwD/AgAMAAkKIB7SLwD/AgAAAA==.Zentrea:BAAANQAECgEIAQABNQAECgkJGAAVALcWAA==.Zenyea:BAAANQAECgIJBQABNQAECgkJGAAVALcWAA==.Zetta:BAABNQAECoEYAAIVAAkKtxYLEACeAgAVAAkKtxYLEACeAgAAAA==.',
Zo='Zome:BAABNQAECoEeAAMfAAgK5RCJEgAkAgAfAAgK5RCJEgAkAgAPAAEKlAODYQAzAAAAAA==.',
Zy='Zyndrael:BAAANQAECgUIBQAAAA==.',
['Èl']='Èlytz:BAAANQADCgYICQAAAA==.',
['Êl']='Êlytz:BAAANQADCggJCAAAAA==.',
['ßl']='ßlue:BAAANQAECgQJBAAAAA==.',
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
