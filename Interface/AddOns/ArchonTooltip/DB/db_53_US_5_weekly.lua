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

local lookup = {'Unknown-Unknown','Priest-Holy','Priest-Discipline','DemonHunter-Vengeance','Mage-Arcane','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Paladin-Protection','Warrior-Arms','Shaman-Restoration','Evoker-Devastation','Druid-Balance','Shaman-Elemental','Monk-Brewmaster','Paladin-Holy','Warlock-Demonology','Rogue-Assassination','Warlock-Destruction','Priest-Shadow','Rogue-Outlaw','Druid-Feral','Warrior-Protection','Evoker-Preservation','DemonHunter-Devourer','Warlock-Affliction','DeathKnight-Blood','DeathKnight-Unholy','Monk-Mistweaver','Rogue-Subtlety','Hunter-Survival','DeathKnight-Frost','Warrior-Fury','Druid-Restoration','Monk-Windwalker','Evoker-Augmentation','Druid-Guardian','Shaman-Enhancement',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Accost:BAAANQADCgcIDQAAAA==.Acronica:BAAANQAECgUIDQAAAA==.',
Ad='Addilynn:BAAANQABCgEIAQAAAA==.',
Ak='Akassa:BAAANQADCgcICwAAAA==.Aknologia:BAAANQAECgQIBgABNQAECggIEQABAAAAAA==.',
Al='Alecto:BAAANQAECgYICAAAAA==.Allele:BAAANQAECgIIAgAAAA==.Allet:BAAANQADCgcIDwABNQAECgMIAwABAAAAAA==.',
Am='Amarah:BAABNQAECoEoAAICAAkKlRvpIADPAgACAAkKlRvpIADPAgAAAA==.Ameilie:BAABNQAECoEsAAMCAAkKox++HQDgAgACAAkKox++HQDgAgADAAQKiRcDDwAmAQAAAA==.',
An='Anapuwae:BAAANQAECgUIEQAAAA==.Animehero:BAABNQAECoEiAAIEAAgKwiAvBADhAgAEAAgKwiAvBADhAgAAAA==.',
Ar='Arcant:BAABNQAECoEaAAIFAAcK9hkqogAdAgAFAAcK9hkqogAdAgAAAA==.Ardicov:BAAANQADCgYICwAAAA==.Argadin:BAAANQAECgUIBgABNQAECgkJIgAGAB0jAA==.Arglock:BAAANQADCgcIBwABNQAECgkJIgAGAB0jAA==.Argrekh:BAABNQAECoEiAAMGAAkKHSPfBwCQAwAGAAkKHSPfBwCQAwAHAAEKQQ/JdgA5AAAAAA==.Argreks:BAAANQADCgEIAgABNQAECgkJIgAGAB0jAA==.Argrekt:BAAANQAECgIIAgABNQAECgkJIgAGAB0jAA==.Aridol:BAAANQADCgYIBgAAAA==.Arigön:BAAANQADCgIIAgAAAA==.Aronna:BAAANQADCgYICAAAAA==.Arosea:BAAANQADCgYIBgAAAA==.Arthaslk:BAABNQAECoE3AAMIAAkKISW9BADNAwAIAAkKISW9BADNAwAJAAIKBAkdVwBVAAABNQAECgkJPQAKAEIiAA==.Aryssol:BAAANQADCggIEAAAAA==.',
At='Ate:BAAANQAECgYIEgAAAA==.Atlette:BAAANQAECgMIAwAAAA==.Attman:BAABNQAECoEqAAILAAkKWiH2CwBMAwALAAkKWiH2CwBMAwAAAA==.',
Au='Auradawn:BAAANQADCgcIDwAAAA==.',
Ba='Badhands:BAAANQAECgIIAgAAAA==.Baeator:BAAANQAECgEIAQABNQAFFAcIFwAMAAEPAA==.Barneystins:BAAANQABCgEIAgABNQADCgQIBAABAAAAAA==.',
Be='Bearmane:BAABNQAECoEnAAINAAkKlSBUEAAyAwANAAkKlSBUEAAyAwAAAA==.Beastarsfan:BAABNQAECoEeAAIOAAkKaSLtCgCEAwAOAAkKaSLtCgCEAwAAAA==.Behmow:BAABNQAECoEkAAIKAAkKgSWfBQDDAwAKAAkKgSWfBQDDAwAAAA==.Belithel:BAAANQAECgQIBgABNQAECgcIEAABAAAAAA==.Bencreepin:BAAANQAECgMICQAAAA==.Bernoulli:BAABNQAECoEYAAIPAAgKYBOVDwDSAQAPAAgKYBOVDwDSAQAAAA==.',
Bi='Bigspitter:BAAANQADCgYIBgABNQAECgkJJQAFAIMkAA==.Bis:BAAANQADCgUJBQABNQAECgkJFgAFABcdAA==.',
Bl='Blessedxx:BAAANQAECgUIBgAAAA==.Bloodboo:BAAANQADCgQIBAAAAA==.Bloodyhpally:BAACNQAFFIEZAAIQAAcKShkPAgB2AgAQAAcKShkPAgB2AgA1AAQKgSEAAhAACQq1GMQjAMUCABAACQq1GMQjAMUCAAAA.',
Bo='Boopsnoopems:BAAANQAECgQICAAAAA==.Borderline:BAAANQAECgUIBQABNQAECgkJJwARAEQYAA==.',
Br='Bradcrit:BAAANQAECgEIAQAAAA==.',
Bu='Bubble:BAAANQAECgYIEgAAAA==.Burrfoot:BAAANQAECgIIAwAAAA==.Bustah:BAAANQAECgcIEgABNQAECgkJHAACAIgbAA==.',
Bw='Bwoodmorgan:BAAANQAECgYIDgAAAA==.',
Ca='Calene:BAACNQAFFIEKAAISAAYKJxAQAwD5AQASAAYKJxAQAwD5AQA1AAQKgTYAAhIACQrEInsHAEcDABIACQrEInsHAEcDAAAA.Candy:BAAANQAECgMIBQAAAA==.Cannedcorn:BAAANQAECgIIAgAAAA==.Caperusin:BAAANQAECgUICAAAAA==.Casare:BAAANQADCgYIFgAAAA==.Cayde:BAAANQADCgYJBgABNQAFFAUICgAHAKIOAA==.',
Ce='Celestinee:BAAANQAECgYIEQAAAA==.Celyda:BAAANQAECgQIBAAAAA==.Cenarian:BAAANQABCgUIBwAAAA==.',
Ch='Chabotloe:BAAANQAECgMIAwAAAA==.Chape:BAABNQAECoEdAAMQAAkKvhdrMwB7AgAQAAkKvhdrMwB7AgAIAAYKXBLbzABIAQAAAA==.Chochalinda:BAAANQAECgYIDgAAAA==.',
Ci='Cinderlee:BAAANQAECgQIBgAAAA==.',
Co='Colexn:BAAANQAECgcIEAAAAA==.Cong:BAACNQAFFIEFAAIKAAQK/gZ1GQAFAQAKAAQK/gZ1GQAFAQA1AAQKgRwAAgoACQr/GEJNAIcCAAoACQr/GEJNAIcCAAAA.Corg:BAAANQADCgYIBgAAAA==.Cornchipz:BAAANQAECggIEQAAAA==.',
Cr='Crapsack:BAAANQABCgEIAQAAAA==.Croski:BAAANQADCgEIAQAAAA==.Cryonidus:BAAANQAECgEIAQAAAA==.',
Cu='Curves:BAAANQAECgEIAQAAAA==.',
Cy='Cypressa:BAAANQADCgQIBAAAAA==.',
Da='Daangalanng:BAAANQAECgcIEAAAAA==.Daegra:BAABNQAECoEkAAISAAgK3R9BEADeAgASAAgK3R9BEADeAgAAAA==.Dankkush:BAAANQADCgQIBAAAAA==.Darkacedia:BAABNQAECoEqAAMRAAkKUxcWQAB2AgARAAkKUxcWQAB2AgATAAMKKwrpSgCTAAAAAA==.Darkzetta:BAAANQAECgIIAgABNQAFFAUICgAUANQNAA==.',
De='Deadlift:BAAANQAECgYIBgAAAA==.Dealosed:BAABNQAECoEZAAMSAAgKWhlWIQBOAgASAAgKORlWIQBOAgAVAAQKORO9EADyAAAAAA==.Deathawolf:BAAANQAECgEIAQAAAA==.Deathkilera:BAAANQADCgUIBwAAAA==.Defy:BAAANQADCgYIBgAAAA==.Delenn:BAABNQAECoEXAAIWAAgKERtRCwBEAgAWAAgKERtRCwBEAgAAAA==.Demonclawz:BAAANQAECgYIBgAAAA==.Demonnyaa:BAAANQADCgcIBwAAAA==.Derzy:BAAANQADCgIIAgAAAA==.Dewygirl:BAAANQADCgQIBwAAAA==.',
Dh='Dhuumystic:BAAANQADCgEIAQAAAA==.',
Di='Disastasmite:BAAANQADCgIIBAABNQAECgkJIAAVAGUcAA==.Dive:BAABNQAECoEWAAIFAAkKFx11UADQAgAFAAkKFx11UADQAgAAAA==.',
Do='Doogru:BAABNQAECoEfAAIXAAgKYhozDABHAgAXAAgKYhozDABHAgAAAA==.Doogtwo:BAAANQADCggIHAABNQAECggIHwAXAGIaAA==.Doryndoran:BAAANQAECgQIBQAAAA==.Dorynhashots:BAAANQADCgUIBQAAAA==.Dotproduct:BAAANQADCgEIAQABNQADCgIIAgABAAAAAA==.Dotsrock:BAAANQAECgYIDgAAAA==.Dovah:BAAANQADCgIIAgAAAA==.',
Dr='Dragoneggs:BAABNQAECoEhAAMMAAkKcxpLCwCcAgAMAAkKcxpLCwCcAgAYAAkK9Qk+HADpAQAAAA==.Dragonforce:BAAANQADCggIEgAAAA==.Drakonutz:BAAANQAECgYIDwAAAA==.Draxx:BAAANQAECggIBwAAAA==.Drañzer:BAAANQAECgEIAgAAAA==.Dreammachine:BAAANQAECgcIBwAAAA==.Drjoel:BAAANQADCgcIEQAAAA==.Drunkenutz:BAAANQAECgQIDAAAAA==.Dräx:BAAANQAECggIEAAAAA==.',
Dw='Dwallen:BAAANQADCgIIAgAAAA==.Dwightschrut:BAAANQADCgQIBAAAAA==.',
['Dä']='Dälf:BAAANQAECgIIAgABNQAFFAcICQAJAN8SAA==.',
Ea='Earthshocker:BAAANQAECgUICQAAAA==.',
El='Elenix:BAAANQAECgcIAQAAAA==.Elki:BAAANQADCgQIBgAAAA==.Elmesia:BAAANQAECgYIEQAAAA==.Eloris:BAABNQAECoEgAAIZAAgKQB21FgCTAgAZAAgKQB21FgCTAgAAAA==.Elpato:BAAANQADCgcIBwABNQAECgkJJQAFAIMkAA==.Elthyn:BAAANQAECgQIBQAAAA==.Elvar:BAAANQAECgEIAQAAAA==.',
Em='Emachine:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Emeraldrin:BAAANQADCgEIAQAAAA==.Emz:BAABNQAECoEnAAIVAAgKzB8HBADBAgAVAAgKzB8HBADBAgAAAA==.',
En='Eniar:BAAANQAECgMIBAAAAA==.',
Er='Erakk:BAAANQADCgEIAgAAAA==.Erianda:BAAANQABCgQIBAAAAA==.Eric:BAABNQAECoEbAAIKAAcKjRxebQAqAgAKAAcKjRxebQAqAgAAAA==.Eroninja:BAAANQAECgIIAwABNQAECgcIEAABAAAAAA==.Erín:BAAANQAECgQIDQAAAA==.',
Eu='Eurong:BAACNQAFFIEHAAINAAQKVAoiEgALAQANAAQKVAoiEgALAQA1AAQKgR8AAg0ACQr/GDolAIcCAA0ACQr/GDolAIcCAAAA.',
Ez='Ezynuff:BAAANQAECgUICwAAAA==.',
Fa='Fapple:BAAANQAECgQIBAABNQAECggIIgAYAGgiAA==.Fatesworn:BAAANQADCgcIBwAAAA==.Faïry:BAABNQAECoEdAAIGAAgK9iGWKADWAgAGAAgK9iGWKADWAgAAAA==.',
Fe='Feaughoeren:BAAANQAECgYIBgAAAA==.Felwyrm:BAABNQAECoEnAAIRAAkKRBgnPgB8AgARAAkKRBgnPgB8AgAAAA==.Feralshmeral:BAAANQABCgQIBAABNQAECgkJGgAGAFsiAA==.',
Fo='Foragh:BAAANQAECgUIBwABNQAECgcIGAAYAOUPAA==.Foxi:BAAANQADCggIEQABNQAECgcIEwABAAAAAA==.',
Fr='Frank:BAAANQAECgQIBgAAAA==.Freakbeast:BAAANQAECgYJEgABNQAFFAIIAgABAAAAAA==.Fries:BAEANQAECgcIBwABNQAECggIDAABAAAAAA==.',
Fu='Fullkidney:BAACNQAFFIEKAAISAAQKYx20BgByAQASAAQKYx20BgByAQA1AAQKgSAAAhIACQp+IgsGAF0DABIACQp+IgsGAF0DAAAA.Funch:BAABNQAECoEbAAIaAAgKcRI3BwAKAgAaAAgKcRI3BwAKAgAAAA==.',
Ga='Gaefaeryn:BAABNQAECoEgAAMUAAkKphYcFwB8AgAUAAkKphYcFwB8AgADAAEKmgEkLQAfAAAAAA==.Garonnaa:BAABNQAECoEXAAIbAAgKIBBOTQCgAQAbAAgKIBBOTQCgAQAAAA==.Garthel:BAAANQAECggIEgAAAA==.',
Ge='Genetiks:BAAANQADCgYIDAAAAA==.',
Gh='Ghari:BAABNQAECoEZAAIcAAYKKxPLZgBQAQAcAAYKKxPLZgBQAQAAAA==.',
Gi='Gingerlock:BAABNQAECoEYAAIRAAgKihrkRABnAgARAAgKihrkRABnAgAAAA==.Gingershaman:BAAANQADCgEIAQAAAA==.Giyuu:BAAANQADCgUIBQAAAA==.',
Gn='Gnoblin:BAAANQADCggIFgAAAA==.',
Gr='Greka:BAAANQAECgQICAAAAA==.Greylooms:BAAANQADCgcIBwAAAA==.Griplock:BAABNQAECoEfAAIbAAgKCQ1wUwCEAQAbAAgKCQ1wUwCEAQAAAA==.',
Gu='Gutz:BAAANQADCgcICQAAAA==.',
['Gö']='Gözër:BAAANQADCgMIAwABNQAECgYIDAABAAAAAA==.',
Ha='Happyfriend:BAAANQAECgEIAQABNQAECgkJJwARAEQYAA==.',
He='Healalle:BAAANQADCgYICwABNQAECgYIEQABAAAAAA==.Healhole:BAABNQAECoElAAMLAAkKdSCkEgAcAwALAAkKdSCkEgAcAwAOAAMKKxWt0QC/AAAAAA==.Heàl:BAAANQAECgQIBwAAAA==.',
Hi='Hidolo:BAAANQADCgYIDAAAAA==.',
Hu='Hunterishard:BAAANQAECgQIBAAAAA==.',
Hy='Hylaina:BAAANQADCgYJCgAAAA==.',
['Hô']='Hôlÿ:BAAANQADCggIDgAAAA==.',
Ia='Iamamonk:BAAANQADCgEIAQAAAA==.',
Ik='Ikerous:BAAANQADCgMIAwAAAA==.',
Il='Ilysa:BAAANQABCgQIBAAAAA==.',
Im='Imadwagon:BAAANQADCgcIAgAAAA==.Imcolorblind:BAAANQADCgIIAgAAAA==.Imhammered:BAAANQAECgYIDgAAAA==.',
Io='Ioun:BAAANQADCgMIAwAAAA==.Iounn:BAAANQADCgcIBwABNQAECggIIgAdAJkXAA==.',
Is='Isatku:BAAANQAECgEIAQAAAA==.',
It='Itiswhatitiz:BAABNQAECoEkAAIGAAgKrBv+MwCtAgAGAAgKrBv+MwCtAgAAAA==.Itsybityshiv:BAABNQAECoEkAAIeAAgKlBdUEgBMAgAeAAgKlBdUEgBMAgAAAA==.',
Ja='Jakarr:BAAANQADCgQIBAAAAA==.Jams:BAAANQADCgMIAwAAAA==.',
Je='Jeabuss:BAAANQADCgUIBQAAAA==.',
Jh='Jhani:BAAANQAECgQICAAAAA==.',
Ji='Jiu:BAABNQAECoEcAAICAAkKiBslHQDkAgACAAkKiBslHQDkAgAAAA==.',
Jo='Joethemage:BAABNQAECoEaAAIFAAgKiRywYwCjAgAFAAgKiRywYwCjAgAAAA==.Jormojo:BAAANQAECgMIAwAAAA==.',
Ju='Jungol:BAAANQADCgUICQAAAA==.',
Ka='Kamin:BAAANQAECgYIBgABNQAECgkJIgAFAEgdAA==.Katamaran:BAAANQAECgEIAQABNQAFFAUICgAUANQNAA==.Kaykaypally:BAABNQAECoEUAAIIAAcKQxFbpgCbAQAIAAcKQxFbpgCbAQAAAA==.',
Ke='Kellan:BAAANQADCggIFgAAAA==.',
Kh='Khybyr:BAAANQADCgMIAwAAAA==.',
Ki='Kidata:BAABNQAECoEiAAIdAAgKmRfKEgAjAgAdAAgKmRfKEgAjAgAAAA==.Kindaprepped:BAAANQADCgQIBAAAAA==.Kinji:BAAANQAECgcIEAAAAA==.Kinn:BAAANQADCggICAABNQAECggIGAAPAGATAA==.',
Ko='Konfu:BAAANQADCgcIEQAAAA==.Kormega:BAAANQAECgUIBQAAAA==.Korral:BAAANQADCggIDQAAAA==.',
Kr='Krispies:BAAANQAECgUIDQAAAA==.Kristysavage:BAABNQAECoEkAAMfAAkKESBoAQBPAwAfAAkKeR5oAQBPAwAGAAIK+RnwDAGcAAAAAA==.',
Ku='Kulaesca:BAACNQAFFIEIAAIRAAMKBRI7GgDvAAARAAMKBRI7GgDvAAA1AAQKgSYAAxEACQrFGEA+AHwCABEACQrFGEA+AHwCABMAAQrtAMaAAB4AAAAA.',
Ky='Kynar:BAACNQAFFIEaAAMgAAcKTR0TAQBCAgAgAAYKsx4TAQBCAgAbAAYKEQnaDABXAQA1AAQKgSQAAyAACQogJpoGAGcDACAACQogJpoGAGcDABsAAwofFTWKALQAAAAA.Kyua:BAAANQAECgEIAQAAAA==.',
La='Ladragona:BAAANQADCggICAAAAA==.Lambshot:BAAANQAECgcIEgAAAA==.Lambsy:BAACNQAFFIEdAAQKAAcKUxMPBQBVAgAKAAcK1hIPBQBVAgAhAAEK5AZwBABPAAAXAAEKEAz8BwA9AAA1AAQKgSUAAwoACQrdJJsXAFADAAoACQrZJJsXAFADACEAAwoCE/IdAK0AAAAA.Lanamama:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Lanana:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Le='Lerat:BAABNQAECoEgAAIMAAgKcR4DCgC3AgAMAAgKcR4DCgC3AgAAAA==.',
Li='Lightwarden:BAAANQADCgQIBAAAAA==.Lilyy:BAABNQAECoEhAAIFAAkKGBmvXACzAgAFAAkKGBmvXACzAgAAAA==.Lisanalgaib:BAABNQAECoEbAAIIAAgKNBafeQAJAgAIAAgKNBafeQAJAgAAAA==.Lizzimcguire:BAABNQAECoEsAAIMAAkK/iT3AADEAwAMAAkK/iT3AADEAwAAAA==.',
Lo='Lobobare:BAABNQAECoEfAAIiAAgK2x07FwBiAgAiAAgK2x07FwBiAgAAAA==.Loraen:BAAANQAECgUICQAAAA==.',
Lu='Lunarmon:BAAANQADCgUIBQAAAA==.Lunchable:BAAANQAECgUIEAAAAA==.',
Ma='Maevora:BAAANQAECgQICgAAAA==.Makaroni:BAAANQAECgUIBQAAAA==.Manticus:BAAANQADCgYICAAAAA==.Maomaoo:BAAANQAECgcIDwAAAA==.Marni:BAAANQAECgQICQABNQAECgYIEQABAAAAAA==.Marsrover:BAAANQAECgIIAgABNQAFFAcIHAAKAFkcAA==.Martel:BAAANQADCgQIBAAAAA==.Mashunit:BAAANQABCgIIAgAAAA==.Matroxx:BAACNQAFFIEMAAIjAAUKnRegBQCKAQAjAAUKnRegBQCKAQA1AAQKgSsAAiMACQo5JDoHAEgDACMACQo5JDoHAEgDAAAA.',
Me='Medinduceyuh:BAAANQADCgEIAQAAAA==.Meenoi:BAABNQAECoEXAAIcAAgKLxyiOwANAgAcAAgKLxyiOwANAgABNQAECgkJHAACAIgbAA==.Mellotots:BAAANQABCgIIBAAAAA==.Metatron:BAAANQADCgIIAgAAAA==.',
Mi='Miadas:BAAANQAECgMIAwABNQAECggIJgAWACQfAA==.Mimikyu:BAAANQABCgYIBgAAAA==.Minìwheats:BAAANQADCgMIAwAAAA==.',
Mo='Moardotsnow:BAABNQAECoEmAAMTAAkK9CKGFgCwAQARAAYKpiCrVQA0AgATAAQKQSWGFgCwAQAAAA==.Moby:BAAANQAECgIIBAAAAA==.Moistmender:BAAANQAECgMIAwAAAA==.Mortiana:BAAANQADCggICAAAAA==.',
Mu='Murridan:BAAANQAECggIEQAAAA==.',
My='Mykaela:BAAANQAECgEIAQAAAA==.',
['Më']='Mëow:BAAANQAECgMIBAAAAA==.',
Na='Namiyu:BAAANQADCgcIBwAAAA==.Narrath:BAAANQADCgMJAwAAAA==.Nayalaah:BAAANQAECgEIAQAAAA==.',
Ne='Nehpets:BAAANQADCgUIBQAAAA==.Nephelym:BAABNQAECoEfAAMCAAgKQA8iYQDLAQACAAgKQA8iYQDLAQADAAIKrAKEIABKAAAAAA==.Nerv:BAAANQADCgMIBQAAAA==.',
Ni='Nicolasmage:BAAANQABCgMIAwAAAA==.Nirina:BAAANQAECgQICAAAAA==.',
No='Nohtil:BAAANQADCgUIEQAAAA==.Notstephen:BAABNQAECoEXAAMCAAgKGQjDdACFAQACAAgKGQjDdACFAQAUAAMKKQ8UUgCZAAAAAA==.Nourishnutz:BAAANQADCgYIBgAAAA==.',
Nu='Nut:BAAANQAECgQIEAABNQAECgYIEgABAAAAAA==.',
Nw='Nwalliance:BAAANQAECgEIAQAAAA==.',
['Nö']='Nötprepared:BAAANQADCgYIEwABNQAECgUJBQABAAAAAA==.',
Oi='Oiflar:BAAANQAECgUIDwABNQAECggIIgAYAGgiAA==.',
Ol='Olangi:BAAANQAECgEIAQAAAA==.',
Om='Omnidh:BAAANQADCggJEAABNQAFFAMIBgAjAKcUAA==.Omnipotent:BAAANQADCggICAAAAA==.',
On='Onepavo:BAAANQAECgYIDwAAAA==.',
Oo='Oogie:BAAANQADCgYIBgAAAA==.Oogrikusk:BAAANQADCgIIAgAAAA==.Oottedenttoo:BAAANQADCgQIBAAAAA==.',
Op='Oppose:BAAANQAECgUICgAAAA==.',
Or='Orexion:BAABNQAECoEaAAIhAAcKrwlMEgBVAQAhAAcKrwlMEgBVAQAAAA==.Ormagöden:BAABNQAECoEjAAIgAAgK2g4gNgDCAQAgAAgK2g4gNgDCAQAAAA==.',
Ov='Overpower:BAAANQADCgYIBgAAAA==.',
Pa='Pagoda:BAAANQAECgQIBQAAAA==.Palladean:BAAANQAECgIIAwAAAA==.Palphen:BAAANQAECgcJDAABNQAECggIFwACABkIAA==.Panako:BAAANQAECgUICQAAAA==.Pastasauce:BAABNQAECoEdAAIIAAYKZAlz2QAuAQAIAAYKZAlz2QAuAQAAAA==.',
Pe='Pegero:BAAANQADCgYIDQAAAA==.Penelohpe:BAABNQAECoEiAAIFAAkKSB1WaACZAgAFAAkKSB1WaACZAgAAAA==.',
Ph='Phatt:BAAANQAECgMIAwAAAA==.Phoenixdrac:BAAANQADCggICQAAAA==.Phoon:BAECNQAFFIEFAAMRAAIKoRbcJACkAAARAAIKoRbcJACkAAATAAEKKRFrGQBQAAA1AAQKgSYAAxEACQq2IJsyAKQCABEABwoBI5syAKQCABMABApUHEEiAFMBAAAA.Phoondk:BAEANQAECgUICAABNQAFFAIIBQARAKEWAA==.',
Pi='Piggy:BAAANQAECgEIAQAAAA==.Pita:BAAANQABCgYIBgAAAA==.Pizzadriver:BAACNQAFFIEcAAMKAAcKWRyoAgCiAgAKAAcKWRyoAgCiAgAhAAEKWwovBABTAAA1AAQKgSMAAwoACQpvJVkZAEcDAAoACQpnJVkZAEcDACEAAQo9JjQjAHAAAAAA.',
Pl='Plaguefist:BAAANQADCgcIBwABNQADCggIEgABAAAAAA==.Plata:BAAANQAECgUICgAAAA==.',
Po='Poosicat:BAAANQABCgYIBgAAAA==.Poosycat:BAAANQADCgMIAQAAAA==.',
Pr='Praytroxx:BAAANQAECgQICAABNQAFFAUIDAAjAJ0XAA==.Premonitions:BAAANQAECgIIAgAAAA==.Premune:BAABNQAECoEsAAIQAAgKzhznJgC2AgAQAAgKzhznJgC2AgAAAA==.Prion:BAAANQAECggIEgAAAA==.',
Pu='Pucco:BAAANQADCgIIAgAAAA==.Putrav:BAAANQAECgYICAAAAA==.',
Py='Pyrena:BAAANQADCgEIAQAAAA==.Pyroclasm:BAAANQAECgUICgAAAA==.Pyrrha:BAAANQADCgMIAwAAAA==.',
Qu='Quigly:BAAANQADCgIIAgAAAA==.',
Ra='Ragingfluids:BAAANQAECgYIDwAAAA==.Rahdek:BAAANQADCgMIAwAAAA==.Raine:BAACNQAFFIEdAAILAAcKYxiUAgBcAgALAAcKYxiUAgBcAgA1AAQKgSIAAwsACQpNFdZEACMCAAsACQpNFdZEACMCAA4ABApaFL2/AOQAAAAA.Raistlin:BAAANQADCgEIAQAAAA==.Ralfio:BAABNQAECoEiAAMYAAgKaCKjCAALAwAYAAgKaCKjCAALAwAkAAEKFQ9AIAAzAAAAAA==.Rasq:BAAANQAECggIEwAAAA==.Rat:BAABNQAECoEXAAISAAkKeCKrBQBjAwASAAkKeCKrBQBjAwAAAA==.Rayaray:BAAANQADCgYIBgAAAA==.Raynith:BAABNQAECoEmAAQWAAgKJB9sDQAPAgANAAcKHxzrKgBeAgAWAAYK5hxsDQAPAgAlAAIKmhKbPgBxAAAAAA==.',
Rd='Rdyoshy:BAAANQADCgUIBQAAAA==.',
Re='Readycheck:BAABNQAECoEcAAMNAAgKAxGGRACzAQANAAcKZxGGRACzAQAlAAcKdwnIJQAhAQAAAA==.Reflex:BAAANQAECgIIAgAAAA==.Regirock:BAAANQABCgMIAwAAAA==.Rellek:BAAANQAECgIIAgAAAA==.Remulous:BAAANQAECgYICgAAAA==.Resist:BAAANQADCgYIBgAAAA==.Retallica:BAAANQAECgcICwAAAA==.Revali:BAACNQAFFIEKAAIHAAUKog6eCgBuAQAHAAUKog6eCgBuAQA1AAQKgTMAAwYACQrmIoMjAOsCAAYACQqvH4MjAOsCAAcACQoaHNUTAKwCAAAA.Revelaen:BAAANQAECgcIDwABNQAFFAUICgAHAKIOAA==.',
Ri='Rick:BAACNQAFFIEHAAIHAAMKChm9EQDrAAAHAAMKChm9EQDrAAA1AAQKgRoAAwcACQorIWwQANMCAAcACQq+IGwQANMCAAYABAriHUToAAABAAAA.',
Rm='Rmagep:BAAANQAECgUICwAAAA==.',
Ro='Roadhouse:BAAANQAECgMIAwAAAA==.Roman:BAAANQAECgYIDAABNQAECgkJMQAYAMAjAA==.Roshango:BAAANQADCgYIBgAAAA==.Rosinator:BAAANQAECggIAQAAAA==.Rotgus:BAAANQAECgEIAQAAAA==.Rouk:BAAANQAECgcICwABNQAECgkJFwAIAIImAA==.Rowgar:BAAANQAECgcIDAAAAA==.',
Ru='Rubenslik:BAABNQAECoEjAAIFAAgKnCJpQAD2AgAFAAgKnCJpQAD2AgAAAA==.',
Sa='Saelyn:BAAANQADCggIBgAAAA==.Saephora:BAAANQAECgYICgAAAA==.Saggypants:BAAANQAECgcIEQAAAA==.Sakurai:BAAANQAECgEIAQABNQAECgEIAgABAAAAAA==.Salamander:BAAANQAECgUJCgAAAA==.Salazzle:BAAANQADCgQIBAAAAA==.Sammel:BAAANQAECgUIEAAAAA==.Sanari:BAAANQADCgUIBwABNQAECgcIEAABAAAAAA==.Sandilla:BAAANQADCggICAABNQAECgkJHgAKAPkjAA==.Sangwine:BAAANQADCgYIBgAAAA==.Sapphica:BAAANQAECgEIAQAAAA==.Sathreina:BAABNQAECoEgAAIIAAgKIBa1agAvAgAIAAgKIBa1agAvAgAAAA==.',
Sc='Scaries:BAABNQAECoEZAAIPAAkKuBxHBgDOAgAPAAkKuBxHBgDOAgAAAA==.Scariesdwarf:BAAANQADCgYICgAAAA==.Scootko:BAABNQAECoEWAAIIAAcKbSCISACVAgAIAAcKbSCISACVAgAAAA==.Scuss:BAAANQADCggICAAAAA==.',
Se='Sego:BAAANQAECgEIAQAAAA==.Sekimaru:BAAANQAECgEIAgAAAA==.Senli:BAAANQAECgEIAQAAAA==.Severson:BAABNQAECoEbAAIHAAgKoAy5LQC4AQAHAAgKoAy5LQC4AQAAAA==.Sey:BAAANQADCgYIBgAAAA==.',
Sh='Shadowapoke:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Shadowisbad:BAABNQAECoEmAAIUAAgK6RvCFwBzAgAUAAgK6RvCFwBzAgAAAA==.Shadvoker:BAABNQAECoEiAAMYAAgKzx2SDADLAgAYAAgKzx2SDADLAgAMAAIK1BGHLwB2AAAAAA==.Shamaneggs:BAAANQAECgcICwAAAA==.Shamatroxx:BAABNQAECoEXAAImAAYKtBqlFAD1AQAmAAYKtBqlFAD1AQABNQAFFAUIDAAjAJ0XAA==.Shamberry:BAAANQAECgQIBQAAAA==.Shambles:BAAANQADCgYICQAAAA==.Shieldwalle:BAAANQAECgYIEQAAAA==.Shinobukocho:BAAANQADCgQJBAAAAA==.Shotigolova:BAAANQADCgcIDgAAAA==.',
Si='Sidesalad:BAAANQAECgEIAQAAAA==.Sidric:BAABNQAECoEZAAINAAgKrg0lQgDBAQANAAgKrg0lQgDBAQAAAA==.Silre:BAAANQAECgIIAgAAAA==.Sim:BAABNQAECoEeAAIKAAkK+SMjDwB+AwAKAAkK+SMjDwB+AwAAAA==.Singularité:BAAANQAECgcIBwABNQAFFAYICgASACcQAA==.Sipplex:BAAANQADCgQIBAABNQAECgEIAgABAAAAAA==.',
Sl='Slander:BAAANQAECgQJBAABNQAECgUJCgABAAAAAA==.Slanderous:BAAANQADCgEJAQABNQAECgUJCgABAAAAAA==.',
Sn='Snuudle:BAAANQAECgcIDwABNQAECgkJHAARADoYAA==.',
So='Solokills:BAAANQADCgMIAwABNQADCgYIDQABAAAAAA==.Sophia:BAAANQAECgcIEgAAAA==.Soundtrack:BAAANQADCgYICQABNQAECgIIAgABAAAAAA==.Soyshine:BAAANQADCgYIBgAAAA==.',
Sp='Spaceman:BAAANQAECgUIBQABNQAECgkJJwARAEQYAA==.',
Sq='Squab:BAABNQAECoEcAAINAAkKDx/xFAAJAwANAAkKDx/xFAAJAwAAAA==.Squanchy:BAAANQADCgYJCAAAAA==.',
St='Stabbywixx:BAAANQAECgIIAgAAAA==.Starwnd:BAABNQAECoEUAAIRAAcKjBc7agD3AQARAAcKjBc7agD3AQABNQAFFAUIDAAkAEARAA==.Sterìs:BAAANQAECgEIAQAAAA==.Stickman:BAAANQADCggICAABNQAECgkJJwARAEQYAA==.Stillcreepin:BAAANQADCggIFQAAAA==.Storienn:BAAANQAECgUIEAAAAA==.Stormzpaly:BAAANQAECgYIEQAAAA==.',
Su='Suküna:BAAANQADCggIFwAAAA==.Sunbur:BAAANQADCgYICgAAAA==.Sunglo:BAAANQAECgUIBwAAAA==.Surch:BAAANQADCgEIAQAAAA==.',
Sw='Swaption:BAABNQAECoEWAAILAAgKRh81KACiAgALAAgKRh81KACiAgAAAA==.Sweetie:BAAANQADCgEIAQAAAA==.',
Sy='Syrelia:BAABNQAECoElAAIFAAkKfhM0hQBbAgAFAAkKfhM0hQBbAgAAAA==.',
['Só']='Sónny:BAAANQABCgIIAgAAAA==.',
Ta='Tablescraps:BAAANQABCggICAABNQADCgIIAgABAAAAAA==.Tassarosea:BAAANQADCggIGAABNQAECgkJLAAMAP4kAA==.Tauloe:BAAANQAECgQIBQAAAA==.Tayna:BAAANQAECgQIBwAAAA==.',
Te='Tenderoni:BAAANQADCgEIAQAAAA==.',
Th='Thatsmyhorse:BAAANQADCgIIAgAAAA==.Thomosaurus:BAAANQADCggIDAAAAA==.Thraly:BAAANQADCgYIBwAAAA==.Thunk:BAAANQAECggIEQABNQAECgkJHgAKAPkjAA==.',
Ti='Timdawg:BAAANQAECgYICwABNQAFFAcIHAARAMwaAA==.Timmolate:BAACNQAFFIEcAAQRAAcKzBoLBAARAgARAAYKeBcLBAARAgATAAIKwRfiCACsAAAaAAEKCBdhCgBLAAA1AAQKgSMAAxMACQpZJCkKAEwCABEABwoGIIpIAFsCABMACAoBFykKAEwCAAAA.Tiramisubear:BAAANQAECggIBwAAAA==.Tircaps:BAAANQADCgUIBQAAAA==.',
To='Tomcruise:BAAANQAECgIIAgAAAA==.Tomotostein:BAABNQAECoEeAAIIAAkK1BlgVQBsAgAIAAkK1BlgVQBsAgAAAA==.Tornado:BAAANQABCgQICQABNQADCgQIBAABAAAAAA==.Tourniquet:BAAANQABCgQIBgAAAA==.',
Tr='Tristîtia:BAABNQAECoEWAAMUAAkK9RDaJADhAQAUAAgKwxHaJADhAQACAAIKCwmwzAB3AAAAAA==.Trulu:BAAANQADCgQIBQAAAA==.',
Ts='Tsukikyo:BAAANQADCgQIBAAAAA==.Tsuma:BAAANQABCgIIAgAAAA==.Tsume:BAAANQAECgMIBAAAAA==.',
Tt='Ttomas:BAAANQAECggIDgAAAA==.',
Ty='Tyrinn:BAAANQAECgUIBQAAAA==.Tyv:BAABNQAECoEhAAIFAAgKog7wtgDzAQAFAAgKog7wtgDzAQAAAA==.',
Uz='Uzì:BAAANQADCgIIAgAAAA==.',
Va='Vainatetosix:BAAANQAECgUJBQAAAA==.Vallodon:BAABNQAECoEhAAIFAAgKaSE9PAAAAwAFAAgKaSE9PAAAAwAAAA==.Vantablack:BAAANQABCgIIAgABNQADCgQIBAABAAAAAA==.Vanwolfy:BAAANQAECgcIDQAAAA==.Vaylorian:BAAANQAECgQIBwAAAA==.',
Ve='Velectran:BAAANQADCgUICgABNQAECgkJJQAFAH4TAA==.Velorian:BAAANQADCgMIAwAAAA==.Velveeta:BAAANQAECgMIAwAAAA==.Veragon:BAAANQADCgEIAQAAAA==.',
Vf='Vfacer:BAAANQADCgEIAQAAAA==.',
Vi='Vikav:BAAANQADCgIIAgAAAA==.Vikimg:BAAANQAECgcIDQAAAA==.',
Vo='Voodoomike:BAAANQAECgQIBAAAAA==.Vortash:BAAANQADCgUIBwAAAA==.',
Vy='Vynle:BAAANQAECgEIAQAAAA==.',
Wa='Warheimer:BAAANQAECgcIDwAAAA==.Warrgodx:BAABNQAECoE9AAMKAAkKQiKODwB7AwAKAAkKQiKODwB7AwAhAAEKygijLQA1AAAAAA==.',
Wh='Whoknows:BAAANQADCgIIAgAAAA==.',
Wo='Woogi:BAAANQADCgUIBQAAAA==.',
Wr='Wrongwookie:BAABNQAECoEmAAIOAAgKARp7OABtAgAOAAgKARp7OABtAgAAAA==.',
Ya='Yapper:BAAANQADCgMIAwAAAA==.',
Yo='Yolanda:BAAANQAECgIIAgAAAA==.Yoyohunty:BAAANQAECgYIBgAAAA==.',
Yt='Ytix:BAAANQAECgEIAQAAAA==.',
Yu='Yumekoo:BAAANQADCgIIAgAAAA==.',
Za='Zabada:BAAANQADCgcIGAAAAA==.Zandrea:BAAANQAECgQICgABNQAFFAUICgAUANQNAA==.Zariee:BAAANQABCgIIAwAAAA==.',
Ze='Zehz:BAABNQAECoEaAAIgAAkKyAFgewBzAAAgAAkKyAFgewBzAAAAAA==.Zemsen:BAABNQAECoEnAAIFAAkKIB47VwDAAgAFAAkKIB47VwDAAgAAAA==.Zentrea:BAAANQAECgEIAQABNQAFFAUICgAUANQNAA==.Zenyea:BAAANQAECgUIDAABNQAFFAUICgAUANQNAA==.Zetta:BAACNQAFFIEKAAIUAAUK1A2kBwBpAQAUAAUK1A2kBwBpAQA1AAQKgSAAAhQACQqJGdoSALUCABQACQqJGdoSALUCAAAA.',
Zo='Zome:BAABNQAECoEpAAMeAAkK+ROMDgB+AgAeAAkK+ROMDgB+AgASAAEKlAMTjAAwAAAAAA==.',
Zy='Zyndrael:BAAANQAECgYIEQAAAA==.',
['Èl']='Èlytz:BAAANQADCgYICQAAAA==.',
['Êl']='Êlytz:BAAANQADCggJCAAAAA==.',
['ßl']='ßlue:BAAANQAECgYICgAAAA==.',
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
