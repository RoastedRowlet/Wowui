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

local lookup = {'Unknown-Unknown','Priest-Holy','DemonHunter-Vengeance','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Paladin-Protection','Warrior-Arms','Shaman-Restoration','Evoker-Devastation','Druid-Balance','Mage-Arcane','Paladin-Holy','Warlock-Demonology','Rogue-Assassination','Warlock-Destruction','Rogue-Outlaw','Druid-Feral','Warrior-Protection','Evoker-Preservation','DemonHunter-Devourer','Warlock-Affliction','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Elemental','Monk-Mistweaver','Rogue-Subtlety','Hunter-Survival','DeathKnight-Frost','Warrior-Fury','Druid-Restoration','Monk-Windwalker','Evoker-Augmentation','Shaman-Enhancement',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Accost:BAAANQADCgcIDQAAAA==.Acronica:BAAANQAECgUICAAAAA==.',
Ad='Addilynn:BAAANQABCgEIAQAAAA==.',
Ak='Akassa:BAAANQADCgcICwAAAA==.Aknologia:BAAANQAECgQIBgABNQAECggIEAABAAAAAA==.',
Al='Alecto:BAAANQAECgEIAgAAAA==.Allele:BAAANQADCggIEgAAAA==.Allet:BAAANQADCgUICAABNQAECgMIAwABAAAAAA==.',
Am='Amarah:BAABNQAECoEiAAICAAgKJhxmJwCRAgACAAgKJhxmJwCRAgAAAA==.Ameilie:BAABNQAECoEkAAICAAkKLh9LGQDgAgACAAkKLh9LGQDgAgAAAA==.',
An='Anapuwae:BAAANQAECgUIEQAAAA==.Animehero:BAABNQAECoEiAAIDAAgKwiAYAwD0AgADAAgKwiAYAwD0AgAAAA==.',
Ar='Arcant:BAAANQAECgYIEAAAAA==.Ardicov:BAAANQADCgQIBQAAAA==.Argadin:BAAANQAECgUIBgABNQAECgkJHgAEAC0gAA==.Arglock:BAAANQADCgcIBwABNQAECgkJHgAEAC0gAA==.Argrekh:BAABNQAECoEeAAMEAAkKLSAQDABcAwAEAAkKLSAQDABcAwAFAAEKQQ9YaAA7AAAAAA==.Argreks:BAAANQADCgEIAgABNQAECgkJHgAEAC0gAA==.Argrekt:BAAANQAECgIIAgABNQAECgkJHgAEAC0gAA==.Aridol:BAAANQADCgYIBgAAAA==.Arigön:BAAANQADCgIIAgAAAA==.Aronna:BAAANQADCgYICAAAAA==.Arosea:BAAANQADCgYIBgAAAA==.Arthaslk:BAABNQAECoEtAAMGAAkK3yN7DgB3AwAGAAkK3yN7DgB3AwAHAAIKBAl1TABWAAABNQAECgkJNgAIAG4gAA==.Aryssol:BAAANQADCggIEAAAAA==.',
At='Ate:BAAANQAECgYIEgAAAA==.Atlette:BAAANQAECgMIAwAAAA==.Attman:BAABNQAECoEgAAIJAAkK+R+VEAAXAwAJAAkK+R+VEAAXAwAAAA==.',
Au='Auradawn:BAAANQADCgcIDwAAAA==.',
Ba='Badhands:BAAANQAECgIIAgAAAA==.Baeator:BAAANQAECgEIAQABNQAFFAcIEwAKAO0LAA==.Barneystins:BAAANQABCgEIAgABNQADCgQIBAABAAAAAA==.',
Be='Bearmane:BAABNQAECoEjAAILAAkKhR4LEQAeAwALAAkKhR4LEQAeAwAAAA==.Beastarsfan:BAAANQAECgcIEgAAAA==.Behmow:BAABNQAECoEeAAIIAAkKeyW6BgCvAwAIAAkKeyW6BgCvAwAAAA==.Belithel:BAAANQAECgQIBgABNQAECgcIEwABAAAAAA==.Bencreepin:BAAANQAECgIIBgAAAA==.Bernoulli:BAAANQAECgYIDwAAAA==.',
Bi='Bigspitter:BAAANQADCgYIBgABNQAECggIHAAMAIcjAA==.Bis:BAAANQADCgUJBQABNQAECgkJFgAMABcdAA==.',
Bl='Blessedxx:BAAANQAECgUIBgAAAA==.Bloodboo:BAAANQADCgQIBAAAAA==.Bloodyhpally:BAACNQAFFIETAAINAAcKqBPVAQBYAgANAAcKqBPVAQBYAgA1AAQKgR8AAg0ACQq1GEodAM8CAA0ACQq1GEodAM8CAAAA.',
Bo='Boopsnoopems:BAAANQAECgMIBAAAAA==.Borderline:BAAANQAECgUIBQABNQAECgkJJgAOAEQYAA==.',
Br='Bradcrit:BAAANQAECgEIAQAAAA==.',
Bu='Bubble:BAAANQAECgYIEgAAAA==.Burrfoot:BAAANQAECgIIAwAAAA==.Bustah:BAAANQAECgcIEAABNQAECgkJFgACAKkXAA==.',
Bw='Bwoodmorgan:BAAANQAECgYICwAAAA==.',
Ca='Calene:BAACNQAFFIEHAAIPAAUKKBCLAwCfAQAPAAUKKBCLAwCfAQA1AAQKgTMAAg8ACQrEIp8EAGUDAA8ACQrEIp8EAGUDAAAA.Candy:BAAANQAECgMIAwAAAA==.Cannedcorn:BAAANQAECgIIAgAAAA==.Caperusin:BAAANQAECgUICAAAAA==.Casare:BAAANQADCgYIFgAAAA==.Cayde:BAAANQADCgYJBgABNQAFFAMIBwAFAPsQAA==.',
Ce='Celestinee:BAAANQAECgYICwAAAA==.Celyda:BAAANQADCggICAAAAA==.Cenarian:BAAANQABCgUIBwAAAA==.',
Ch='Chabotloe:BAAANQAECgMIAwAAAA==.Chape:BAABNQAECoEdAAMNAAkKvhemKgCFAgANAAkKvhemKgCFAgAGAAYKXBJErgBQAQAAAA==.Chochalinda:BAAANQAECgQICAAAAA==.',
Ci='Cinderlee:BAAANQAECgEIAgAAAA==.',
Co='Colexn:BAAANQAECgcIDwAAAA==.Cong:BAACNQAFFIEFAAIIAAQK/gbrEwAHAQAIAAQK/gbrEwAHAQA1AAQKgRgAAggACQoLGCtEAIICAAgACQoLGCtEAIICAAAA.Corg:BAAANQADCgYIBgAAAA==.Cornchipz:BAAANQAECggIEAAAAA==.',
Cr='Crapsack:BAAANQABCgEIAQAAAA==.Croski:BAAANQADCgEIAQAAAA==.Cryonidus:BAAANQAECgEIAQAAAA==.',
Cu='Curves:BAAANQAECgEIAQAAAA==.',
Cy='Cypressa:BAAANQADCgQIBAAAAA==.',
Da='Daangalanng:BAAANQAECgUIDAAAAA==.Daegra:BAABNQAECoEcAAIPAAgKGh1LDwDIAgAPAAgKGh1LDwDIAgAAAA==.Dankkush:BAAANQADCgQIBAAAAA==.Darkacedia:BAABNQAECoEkAAMOAAkKwxXfOQBpAgAOAAkKwxXfOQBpAgAQAAMKKwpFRgCYAAAAAA==.',
De='Deadlift:BAAANQADCgEIAQAAAA==.Dealosed:BAABNQAECoEZAAMPAAgKWhlUGQBgAgAPAAgKORlUGQBgAgARAAQKORN3DwD3AAAAAA==.Deathawolf:BAAANQAECgEIAQAAAA==.Deathkilera:BAAANQADCgUIBwAAAA==.Defy:BAAANQADCgYIBgAAAA==.Delenn:BAABNQAECoEXAAISAAgKERsqCQBMAgASAAgKERsqCQBMAgAAAA==.Demonclawz:BAAANQADCgQIBAAAAA==.Demonnyaa:BAAANQADCgcIBwAAAA==.Derzy:BAAANQADCgIIAgAAAA==.Dewygirl:BAAANQADCgQIBwAAAA==.',
Dh='Dhuumystic:BAAANQADCgEIAQAAAA==.',
Di='Disastasmite:BAAANQADCgIIBAABNQAECgkJHgARAP4bAA==.Disastastab:BAABNQAECoEeAAMRAAkK/hsTBACpAgARAAgKzBwTBACpAgAPAAgKPBT3IwAFAgAAAA==.Dive:BAABNQAECoEWAAIMAAkKFx2HPgDoAgAMAAkKFx2HPgDoAgAAAA==.',
Do='Doogru:BAABNQAECoEYAAITAAcKwBmlDQD9AQATAAcKwBmlDQD9AQAAAA==.Doogtwo:BAAANQADCggIHAABNQAECgcIGAATAMAZAA==.Doryndoran:BAAANQAECgQIBQAAAA==.Dorynhashots:BAAANQADCgUIBQAAAA==.Dotproduct:BAAANQADCgEIAQABNQADCgIIAgABAAAAAA==.Dotsrock:BAAANQAECgUICAAAAA==.Dovah:BAAANQADCgIIAgAAAA==.',
Dr='Dragoneggs:BAABNQAECoEbAAMKAAkKcxp0CQCzAgAKAAkKcxp0CQCzAgAUAAgKqwcsHwCbAQAAAA==.Dragonforce:BAAANQADCggIEgAAAA==.Drakonutz:BAAANQAECgYIDQAAAA==.Draxx:BAAANQAECggIBwAAAA==.Drañzer:BAAANQAECgEIAgAAAA==.Dreammachine:BAAANQADCgQIBwAAAA==.Drjoel:BAAANQADCgcIEQAAAA==.Drunkenutz:BAAANQAECgQICgAAAA==.Dräx:BAAANQAECggIDgAAAA==.',
Dw='Dwallen:BAAANQADCgIIAgAAAA==.Dwightschrut:BAAANQADCgQIBAAAAA==.',
['Dä']='Dälf:BAAANQAECgIIAgABNQAFFAcICQAHAN8SAA==.',
Ea='Earthshocker:BAAANQAECgQIBgAAAA==.',
El='Elenix:BAAANQAECgcIAQAAAA==.Elki:BAAANQADCgQIBAAAAA==.Elmesia:BAAANQAECgUICwAAAA==.Eloris:BAABNQAECoEbAAIVAAgKQB2GEwChAgAVAAgKQB2GEwChAgAAAA==.Elpato:BAAANQADCgcIBwABNQAECggIHAAMAIcjAA==.Elthyn:BAAANQAECgEJAQAAAA==.Elvar:BAAANQAECgEIAQAAAA==.',
Em='Emachine:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Emeraldrin:BAAANQADCgEIAQAAAA==.Emz:BAABNQAECoEjAAIRAAgKfh4UBACpAgARAAgKfh4UBACpAgAAAA==.',
En='Eniar:BAAANQAECgMIBAAAAA==.',
Er='Erakk:BAAANQADCgEIAgAAAA==.Erianda:BAAANQABCgQIBAAAAA==.Eric:BAABNQAECoEbAAIIAAcKjRyrWgA2AgAIAAcKjRyrWgA2AgAAAA==.Eroninja:BAAANQAECgIIAwABNQAECgcIEwABAAAAAA==.Erín:BAAANQAECgQICQAAAA==.',
Eu='Eurong:BAACNQAFFIEHAAILAAQKVAqlDgAPAQALAAQKVAqlDgAPAQA1AAQKgR0AAgsACQr/GIwfAJsCAAsACQr/GIwfAJsCAAAA.',
Ez='Ezynuff:BAAANQAECgUICAAAAA==.',
Fa='Fapple:BAAANQAECgQIBAABNQAECggIGwAUANghAA==.Fatesworn:BAAANQADCgcIBwAAAA==.Faïry:BAABNQAECoEdAAIEAAgK9iH7HADvAgAEAAgK9iH7HADvAgAAAA==.',
Fe='Felwyrm:BAABNQAECoEmAAIOAAkKRBi6LwCPAgAOAAkKRBi6LwCPAgAAAA==.',
Fo='Foragh:BAAANQAECgUIBwAAAA==.Foxi:BAAANQADCggIEQABNQAECgYIDAABAAAAAA==.',
Fr='Frank:BAAANQAECgQIBAAAAA==.Freakbeast:BAAANQAECgYJEgABNQAFFAIIAgABAAAAAA==.Fries:BAEANQAECgcIBwABNQAECggICwABAAAAAA==.',
Fu='Fullkidney:BAACNQAFFIEHAAIPAAQKZxt8BABuAQAPAAQKZxt8BABuAQA1AAQKgR0AAg8ACQpRIhgEAHEDAA8ACQpRIhgEAHEDAAAA.Funch:BAABNQAECoEZAAIWAAgKcRK8BQAcAgAWAAgKcRK8BQAcAgAAAA==.',
Ga='Gaefaeryn:BAABNQAECoEbAAMXAAkK7BN8FgBkAgAXAAkK7BN8FgBkAgAYAAEKmgHFJwAhAAAAAA==.Garonnaa:BAABNQAECoEXAAIZAAgKIBCRQwCqAQAZAAgKIBCRQwCqAQAAAA==.Garthel:BAAANQAECgQIBgAAAA==.',
Ge='Genetiks:BAAANQADCgYIDAAAAA==.',
Gh='Ghari:BAABNQAECoEWAAIaAAYKKxOfUgBgAQAaAAYKKxOfUgBgAQAAAA==.',
Gi='Gingerlock:BAAANQAECgcIEgAAAA==.Giyuu:BAAANQADCgUIBQAAAA==.',
Gn='Gnoblin:BAAANQADCggIFgAAAA==.',
Gr='Greka:BAAANQAECgMIBAAAAA==.Greylooms:BAAANQADCgcIBwAAAA==.Griplock:BAAANQAECgYIEwAAAA==.',
['Gö']='Gözër:BAAANQADCgMIAwABNQAECgUIBgABAAAAAA==.',
Ha='Happyfriend:BAAANQAECgEIAQABNQAECgkJJgAOAEQYAA==.',
He='Healalle:BAAANQADCgYICwABNQAECgYIDgABAAAAAA==.Healhole:BAABNQAECoEcAAMJAAgKpSAsHADKAgAJAAgKpSAsHADKAgAbAAMKKxUWuQDHAAAAAA==.Heàl:BAAANQAECgQIBwAAAA==.',
Hi='Hidolo:BAAANQADCgYIDAAAAA==.',
Hu='Hunterishard:BAAANQAECgQIBAAAAA==.',
Hy='Hylaina:BAAANQADCgYJCgAAAA==.',
['Hô']='Hôlÿ:BAAANQADCggIDgAAAA==.',
Ia='Iamamonk:BAAANQADCgEIAQAAAA==.',
Ik='Ikerous:BAAANQADCgMIAwAAAA==.',
Im='Imadwagon:BAAANQADCgcIAgAAAA==.Imcolorblind:BAAANQADCgIIAgAAAA==.Imhammered:BAAANQAECgYIDgAAAA==.',
Io='Ioun:BAAANQADCgMIAwAAAA==.Iounn:BAAANQADCgcIBwABNQAECggIGwAcAGgVAA==.',
Is='Isatku:BAAANQAECgEIAQAAAA==.',
It='Itiswhatitiz:BAABNQAECoEcAAIEAAgK6hnpPABtAgAEAAgK6hnpPABtAgAAAA==.Itsybityshiv:BAABNQAECoEdAAIdAAgKphaiEQBFAgAdAAgKphaiEQBFAgAAAA==.',
Ja='Jakarr:BAAANQADCgQIBAAAAA==.Jams:BAAANQADCgMIAwAAAA==.',
Je='Jeabuss:BAAANQADCgUIBQAAAA==.',
Jh='Jhani:BAAANQAECgQIBgAAAA==.',
Ji='Jiu:BAABNQAECoEWAAICAAkKqRfyHgC+AgACAAkKqRfyHgC+AgAAAA==.',
Jo='Joethemage:BAAANQAECgYIEQAAAA==.',
Ju='Jungol:BAAANQADCgUICQAAAA==.',
Ka='Kamin:BAAANQAECgYIBgABNQAECgkJIgAMAEgdAA==.Katamaran:BAAANQAECgEIAQABNQAFFAQIBgAXAIEJAA==.Kaykaypally:BAAANQAECgYIEwAAAA==.',
Ke='Kellan:BAAANQADCggIDwAAAA==.',
Kh='Khybyr:BAAANQADCgMIAwAAAA==.',
Ki='Kidata:BAABNQAECoEbAAIcAAgKaBUGEgALAgAcAAgKaBUGEgALAgAAAA==.Kindaprepped:BAAANQADCgQIBAAAAA==.Kinji:BAAANQAECgUICQABNQAECgcIEwABAAAAAA==.Kinn:BAAANQADCggICAABNQAECgYIDwABAAAAAA==.',
Ko='Konfu:BAAANQADCgcIEQAAAA==.Kormega:BAAANQADCgIIAgAAAA==.Korral:BAAANQADCggIDQAAAA==.',
Kr='Krispies:BAAANQAECgUIDAAAAA==.Kristysavage:BAABNQAECoEbAAMeAAgKOh9nAgDlAgAeAAgKXB5nAgDlAgAEAAEKjxTJBwFRAAAAAA==.',
Ku='Kulaesca:BAACNQAFFIEFAAIOAAIKJgvzIgCUAAAOAAIKJgvzIgCUAAA1AAQKgSMAAw4ACQpoF6AyAIQCAA4ACQpoF6AyAIQCABAAAQrtANx5AB8AAAAA.',
Ky='Kynar:BAACNQAFFIEVAAMfAAcKxxqbAQDtAQAfAAUK3x+bAQDtAQAZAAYKEQnBCQBkAQA1AAQKgSIAAx8ACQoHJjUFAG4DAB8ACQoHJjUFAG4DABkAAwofFZZ9ALYAAAAA.Kyua:BAAANQAECgEIAQAAAA==.',
La='Ladragona:BAAANQADCggICAAAAA==.Lambshot:BAAANQAECgYIDQAAAA==.Lambsy:BAACNQAFFIEXAAQIAAcKvRKeAwBTAgAIAAcKQRKeAwBTAgAgAAEK5AZhAwBRAAATAAEKEAxZBgA/AAA1AAQKgSMAAwgACQpVJN8SAFkDAAgACQpRJN8SAFkDACAAAwoCE8cZALIAAAAA.Lanamama:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Lanana:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Le='Lerat:BAABNQAECoEYAAIKAAgKShwQCwCLAgAKAAgKShwQCwCLAgAAAA==.',
Li='Lightwarden:BAAANQADCgQIBAAAAA==.Lilyy:BAABNQAECoEfAAIMAAkKPBhcTgC+AgAMAAkKPBhcTgC+AgAAAA==.Lisanalgaib:BAABNQAECoEbAAIGAAgKNBblYQAcAgAGAAgKNBblYQAcAgAAAA==.Lizzimcguire:BAABNQAECoEpAAIKAAkKlCT7AAC8AwAKAAkKlCT7AAC8AwAAAA==.',
Lo='Lobobare:BAABNQAECoEfAAIhAAgK2x0SEwBxAgAhAAgK2x0SEwBxAgAAAA==.Loraen:BAAANQAECgQIBwAAAA==.',
Lu='Lunarmon:BAAANQADCgUIBQAAAA==.Lunchable:BAAANQAECgUIDgAAAA==.Luscid:BAAANQAECgEIAQAAAA==.',
Ma='Maevora:BAAANQAECgQICQAAAA==.Makaroni:BAAANQADCgUIBwAAAA==.Manticus:BAAANQADCgYICAAAAA==.Maomaoo:BAAANQAECgcICgAAAA==.Marni:BAAANQAECgQIBQABNQAECgUICgABAAAAAA==.Marsrover:BAAANQAECgIIAgABNQAFFAcIFgAIAJUbAA==.Martel:BAAANQADCgQIBAAAAA==.Mashunit:BAAANQABCgIIAgAAAA==.Matroxx:BAACNQAFFIEHAAIiAAMKgRWiBwDvAAAiAAMKgRWiBwDvAAA1AAQKgSgAAiIACQr1I7cFAFYDACIACQr1I7cFAFYDAAAA.',
Me='Meenoi:BAABNQAECoEXAAIaAAgKLxyMKgA3AgAaAAgKLxyMKgA3AgABNQAECgkJFgACAKkXAA==.Mellotots:BAAANQABCgIIBAAAAA==.Metatron:BAAANQADCgIIAgAAAA==.',
Mi='Miadas:BAAANQAECgMIAwABNQAECggIIAASAMkeAA==.Mimikyu:BAAANQABCgYIBgAAAA==.Minìwheats:BAAANQADCgEIAQAAAA==.',
Mo='Moardotsnow:BAABNQAECoEdAAMQAAgKBiQHFgCvAQAOAAUKByKtYADmAQAQAAQKBSUHFgCvAQAAAA==.Moby:BAAANQAECgIIBAAAAA==.Moistmender:BAAANQAECgMIAwAAAA==.Mortiana:BAAANQADCggICAAAAA==.',
Mu='Murridan:BAAANQAECggIDgAAAA==.',
My='Mykaela:BAAANQAECgEIAQAAAA==.',
['Më']='Mëow:BAAANQAECgIIAgAAAA==.',
Na='Namiyu:BAAANQADCgcIBwAAAA==.Narrath:BAAANQADCgMJAwAAAA==.Nayalaah:BAAANQAECgEIAQAAAA==.',
Ne='Nehpets:BAAANQADCgUIBQAAAA==.Nephelym:BAABNQAECoEXAAMCAAgKdgoOYACcAQACAAgKdgoOYACcAQAYAAIKrAKVHABNAAAAAA==.Nerv:BAAANQADCgMIBQAAAA==.',
Ni='Nicolasmage:BAAANQABCgMIAwAAAA==.Nirina:BAAANQAECgMIBAAAAA==.',
No='Nohtil:BAAANQADCgUIDAAAAA==.Notstephen:BAAANQAECgcIDQAAAA==.Nourishnutz:BAAANQADCgYIBgAAAA==.',
Nu='Nut:BAAANQAECgQIDAABNQAECgYIEgABAAAAAA==.',
Nw='Nwalliance:BAAANQAECgEIAQAAAA==.',
['Nö']='Nötprepared:BAAANQADCgYIEwABNQAECgUJBQABAAAAAA==.',
Oi='Oiflar:BAAANQAECgUIDgABNQAECggIGwAUANghAA==.',
Ol='Olangi:BAAANQAECgEIAQAAAA==.',
Om='Omnidh:BAAANQADCggJEAABNQAECgkJHAAiAE0kAA==.Omnipotent:BAAANQADCggICAAAAA==.',
On='Onepavo:BAAANQAECgYIDAAAAA==.',
Oo='Oogie:BAAANQADCgYIBgAAAA==.Oogrikusk:BAAANQADCgIIAgAAAA==.Oottedenttoo:BAAANQADCgQIBAAAAA==.',
Op='Oppose:BAAANQAECgUICQAAAA==.',
Or='Orexion:BAAANQAECgYIEQAAAA==.Ormagöden:BAABNQAECoEcAAIfAAgK9A0gLwDDAQAfAAgK9A0gLwDDAQAAAA==.',
Ov='Overpower:BAAANQADCgYIBgAAAA==.',
Pa='Pagoda:BAAANQAECgEIAQAAAA==.Palladean:BAAANQAECgIIAwAAAA==.Palphen:BAAANQAECgcJDAABNQAECgcIDQABAAAAAA==.Panako:BAAANQAECgUICQAAAA==.Pastasauce:BAABNQAECoEXAAIGAAYKVAk/vgAtAQAGAAYKVAk/vgAtAQAAAA==.',
Pe='Pegero:BAAANQADCgYIDQABNQAFFAIIAgABAAAAAA==.Penelohpe:BAABNQAECoEiAAIMAAkKSB1RVACvAgAMAAkKSB1RVACvAgAAAA==.',
Ph='Phatt:BAAANQAECgMIAwAAAA==.Phoenixdrac:BAAANQADCggICQAAAA==.Phoon:BAEBNQAECoEjAAMOAAkKkSDcJgCzAgAOAAcK0iLcJgCzAgAQAAQKVBxjIABZAQAAAA==.Phoondk:BAEANQAECgUICAABNQAECgkJIwAOAJEgAA==.',
Pi='Piggy:BAAANQAECgEIAQAAAA==.Pita:BAAANQABCgYIBgAAAA==.Pizzadriver:BAACNQAFFIEWAAIIAAcKlRtDAgCMAgAIAAcKlRtDAgCMAgA1AAQKgSEAAwgACQpNJZkTAFQDAAgACQpFJZkTAFQDACAAAQo9JoweAHEAAAAA.',
Pl='Plaguefist:BAAANQADCgcIBwABNQADCggIEgABAAAAAA==.Plata:BAAANQAECgUIBwAAAA==.',
Po='Poosicat:BAAANQABCgYIBgAAAA==.Poosycat:BAAANQADCgMIAQAAAA==.',
Pr='Praytroxx:BAAANQAECgQICAABNQAFFAMIBwAiAIEVAA==.Premonitions:BAAANQAECgIIAgAAAA==.Premune:BAABNQAECoEiAAINAAgKMBwnIQC5AgANAAgKMBwnIQC5AgAAAA==.Prion:BAAANQAECggIDQAAAA==.',
Pu='Pucco:BAAANQADCgIIAgAAAA==.Putrav:BAAANQAECgYIBwAAAA==.',
Py='Pyrena:BAAANQADCgEIAQAAAA==.Pyroclasm:BAAANQAECgUICgAAAA==.',
Qu='Quigly:BAAANQADCgIIAgAAAA==.',
Ra='Ragingfluids:BAAANQAECgUICQAAAA==.Rahdek:BAAANQADCgMIAwAAAA==.Raine:BAACNQAFFIEXAAIJAAYKgRbMAwD8AQAJAAYKgRbMAwD8AQA1AAQKgSAAAwkACQrDFPQ9AB4CAAkACQrDFPQ9AB4CABsABApaFI6oAOwAAAAA.Raistlin:BAAANQADCgEIAQAAAA==.Ralfio:BAABNQAECoEbAAMUAAgK2CFYCAAAAwAUAAgK2CFYCAAAAwAjAAEKFQ9VHAA0AAAAAA==.Rasq:BAAANQAECgYICwAAAA==.Rat:BAABNQAECoEXAAIPAAkKeCKnAwB6AwAPAAkKeCKnAwB6AwAAAA==.Rayaray:BAAANQADCgYIBgAAAA==.Raynith:BAABNQAECoEgAAMSAAgKyR79CgAWAgALAAcKzRhqLwAeAgASAAYK5hz9CgAWAgAAAA==.',
Rd='Rdyoshy:BAAANQADCgUIBQAAAA==.',
Re='Readycheck:BAAANQAECgYIEAAAAA==.Reflex:BAAANQAECgIIAgAAAA==.Regirock:BAAANQABCgMIAwAAAA==.Rellek:BAAANQAECgIIAgAAAA==.Remulous:BAAANQAECgMIBAAAAA==.Resist:BAAANQADCgYIBgAAAA==.Retallica:BAAANQAECgYIBwAAAA==.Revali:BAACNQAFFIEHAAIFAAMK+xAyDwDmAAAFAAMK+xAyDwDmAAA1AAQKgTAAAwQACQpuIoAYAAgDAAQACQqvH4AYAAgDAAUACQqAG7USAKQCAAAA.Revelaen:BAAANQAECgQICAABNQAFFAMIBwAFAPsQAA==.',
Ri='Rick:BAABNQAECoEYAAMFAAkKKyGHDADwAgAFAAkKviCHDADwAgAEAAQK4h16ygABAQAAAA==.',
Rm='Rmagep:BAAANQAECgUICwAAAA==.',
Ro='Roadhouse:BAAANQAECgMIAwAAAA==.Roman:BAAANQAECgYICAABNQAECgkJJwAUAMAjAA==.Roshango:BAAANQADCgYIBgAAAA==.Rosinator:BAAANQAECggIAQAAAA==.Rotgus:BAAANQAECgEIAQAAAA==.Rouk:BAAANQAECgcICwABNQAFFAIIAgABAAAAAA==.Rowgar:BAAANQAECgcICwAAAA==.',
Ru='Rubenslik:BAABNQAECoEbAAIMAAgK8yDTPwDlAgAMAAgK8yDTPwDlAgAAAA==.',
Sa='Saelyn:BAAANQADCggIBgAAAA==.Saephora:BAAANQAECgYICAAAAA==.Saggypants:BAAANQAECgcIEQAAAA==.Sakurai:BAAANQAECgEIAQABNQAECgEIAgABAAAAAA==.Salamander:BAAANQAECgUJCgAAAA==.Salazzle:BAAANQADCgQIBAAAAA==.Sammel:BAAANQAECgUIEAAAAA==.Sanari:BAAANQADCgUIBwABNQAECgcIEwABAAAAAA==.Sandilla:BAAANQADCggICAABNQAECggIGAAIAMIjAA==.Sangwine:BAAANQADCgYIBgAAAA==.Sapphica:BAAANQADCgYICgAAAA==.Sathreina:BAABNQAECoEdAAIGAAgKeRV5XAAtAgAGAAgKeRV5XAAtAgAAAA==.',
Sc='Scaries:BAAANQAECgcIEgAAAA==.Scootko:BAAANQAFFAIIAgAAAA==.Scuss:BAAANQADCggICAAAAA==.',
Se='Sego:BAAANQADCggIIQAAAA==.Sekimaru:BAAANQAECgEIAgAAAA==.Severson:BAABNQAECoEbAAIFAAgKoAyGJwDDAQAFAAgKoAyGJwDDAQAAAA==.Sey:BAAANQADCgYIBgAAAA==.',
Sh='Shadowapoke:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Shadowisbad:BAABNQAECoEfAAIXAAgKehvMFAB6AgAXAAgKehvMFAB6AgAAAA==.Shadvoker:BAABNQAECoEbAAMUAAgKMB0BCwDQAgAUAAgKMB0BCwDQAgAKAAIK1BFXKwB5AAAAAA==.Shamaneggs:BAAANQAECgcICAAAAA==.Shamatroxx:BAABNQAECoEWAAIkAAYKqBqjEQAAAgAkAAYKqBqjEQAAAgABNQAFFAMIBwAiAIEVAA==.Shamberry:BAAANQAECgEIAQAAAA==.Shambles:BAAANQADCgYICQAAAA==.Shieldwalle:BAAANQAECgYIDgAAAA==.Shinobukocho:BAAANQADCgQJBAAAAA==.Shotigolova:BAAANQADCgYIBwAAAA==.',
Si='Sidesalad:BAAANQAECgEIAQAAAA==.Sidric:BAAANQAECgYIDQAAAA==.Silre:BAAANQAECgEIAQAAAA==.Sim:BAABNQAECoEYAAIIAAgKwiPnHgAaAwAIAAgKwiPnHgAaAwAAAA==.Sipplex:BAAANQADCgQIBAAAAA==.',
Sl='Slander:BAAANQAECgQJBAABNQAECgUJCgABAAAAAA==.Slanderous:BAAANQADCgEJAQABNQAECgUJCgABAAAAAA==.',
Sn='Snuudle:BAAANQAECgcIDwABNQAECgkJHAAOADkYAA==.',
So='Solokills:BAAANQADCgMIAwABNQAFFAIIAgABAAAAAA==.Sophia:BAAANQAECgcIEgAAAA==.Soundtrack:BAAANQADCgYICQABNQAECgIIAgABAAAAAA==.Soyshine:BAAANQADCgYIBgAAAA==.',
Sq='Squab:BAABNQAECoEcAAILAAkKCx8jEQAdAwALAAkKCx8jEQAdAwAAAA==.Squanchy:BAAANQADCgYJCAAAAA==.',
St='Stabbywixx:BAAANQAECgIIAgAAAA==.Starwnd:BAABNQAECoEUAAIOAAcKjBfNVAAMAgAOAAcKjBfNVAAMAgABNQAFFAUICAAjAPkIAA==.Sterìs:BAAANQAECgEIAQAAAA==.Stickman:BAAANQADCggICAABNQAECgkJJgAOAEQYAA==.Stillcreepin:BAAANQADCggIFQAAAA==.Storienn:BAAANQAECgUIDwAAAA==.Stormzpaly:BAAANQAECgYIEQAAAA==.',
Su='Suküna:BAAANQADCggIFwAAAA==.Sunbur:BAAANQADCgYICgAAAA==.Sunglo:BAAANQAECgIIAgAAAA==.Surch:BAAANQADCgEIAQAAAA==.',
Sw='Swaption:BAAANQAECgcIEwAAAA==.Sweetie:BAAANQADCgEIAQAAAA==.',
Sy='Syrelia:BAABNQAECoEfAAIMAAkK8xAYgABEAgAMAAkK8xAYgABEAgAAAA==.',
['Só']='Sónny:BAAANQABCgIIAgAAAA==.',
Ta='Tablescraps:BAAANQABCggICAABNQADCgIIAgABAAAAAA==.Tassarosea:BAAANQADCggIGAABNQAECgkJKQAKAJQkAA==.Tauloe:BAAANQAECgEJAQAAAA==.Tayna:BAAANQAECgMIAwAAAA==.',
Te='Tenderoni:BAAANQADCgEIAQAAAA==.',
Th='Thatsmyhorse:BAAANQADCgIIAgAAAA==.Thomosaurus:BAAANQADCggIDAAAAA==.Thraly:BAAANQADCgYIBwAAAA==.Thunk:BAAANQAECggIDgABNQAECggIGAAIAMIjAA==.',
Ti='Timdawg:BAAANQAECgUICQABNQAFFAcIFgAOAKgYAA==.Timmolate:BAACNQAFFIEWAAQOAAcKqBipAgAVAgAOAAYK+RSpAgAVAgAQAAIKwRfuBwCyAAAWAAEKCBcCCABQAAA1AAQKgSEAAxAACQoYJO4IAFwCABAACAoBF+4IAFwCAA4ABwqyH6dBAE0CAAAA.',
To='Tomcruise:BAAANQAECgIIAgAAAA==.Tomotostein:BAABNQAECoEbAAIGAAkKmhfqSwBiAgAGAAkKmhfqSwBiAgAAAA==.Tornado:BAAANQABCgQICQABNQADCgQIBAABAAAAAA==.Tourniquet:BAAANQABCgQIBgAAAA==.',
Tr='Tristîtia:BAAANQAECgcIDgAAAA==.',
Ts='Tsukikyo:BAAANQADCgQIBAAAAA==.Tsuma:BAAANQABCgIIAgAAAA==.Tsume:BAAANQAECgEIAQAAAA==.',
Tt='Ttomas:BAAANQAECggIDgAAAA==.',
Ty='Tyrinn:BAAANQADCggICQAAAA==.Tyv:BAABNQAECoEZAAIMAAcK1A2RxQCpAQAMAAcK1A2RxQCpAQAAAA==.',
Uz='Uzì:BAAANQADCgIIAgAAAA==.',
Va='Vainatetosix:BAAANQAECgUJBQAAAA==.Vallodon:BAABNQAECoEZAAIMAAgKfCAMOAD7AgAMAAgKfCAMOAD7AgAAAA==.Vantablack:BAAANQABCgIIAgABNQADCgQIBAABAAAAAA==.Vanwolfy:BAAANQAECgcIDAAAAA==.Vaylorian:BAAANQAECgIIAwAAAA==.',
Ve='Velectran:BAAANQADCgUICgABNQAECgkJHwAMAPMQAA==.Velorian:BAAANQADCgMIAwAAAA==.Velveeta:BAAANQAECgEIAwAAAA==.Veragon:BAAANQADCgEIAQAAAA==.',
Vf='Vfacer:BAAANQADCgEIAQAAAA==.',
Vi='Vikav:BAAANQADCgIIAgAAAA==.Vikimg:BAAANQAECgYIBgAAAA==.',
Vo='Voodoomike:BAAANQAECgQJBAAAAA==.Vortash:BAAANQADCgUIBwAAAA==.',
Vy='Vynle:BAAANQAECgEIAQAAAA==.',
Wa='Warheimer:BAAANQAECgcIDQAAAA==.Warrgodx:BAABNQAECoE2AAMIAAkKbiAuEwBXAwAIAAkKbiAuEwBXAwAgAAEKygh9JwA2AAAAAA==.',
Wh='Whoknows:BAAANQADCgIIAgAAAA==.',
Wo='Woogi:BAAANQADCgUIBQAAAA==.',
Wr='Wrongwookie:BAABNQAECoEfAAIbAAgKjRiVNABhAgAbAAgKjRiVNABhAgAAAA==.',
Ya='Yapper:BAAANQADCgMIAwAAAA==.',
Yo='Yolanda:BAAANQAECgIIAgAAAA==.Yoyohunty:BAAANQAECgEIAQAAAA==.',
Yt='Ytix:BAAANQAECgEIAQAAAA==.',
Yu='Yumekoo:BAAANQADCgIIAgAAAA==.',
Za='Zabada:BAAANQADCgcIFAAAAA==.Zandrea:BAAANQAECgQIBgABNQAFFAQIBgAXAIEJAA==.Zariee:BAAANQABCgIIAwAAAA==.',
Ze='Zehz:BAABNQAECoEaAAIfAAkKyAHLbAB2AAAfAAkKyAHLbAB2AAAAAA==.Zemsen:BAABNQAECoEnAAIMAAkKIB4bRADaAgAMAAkKIB4bRADaAgAAAA==.Zentrea:BAAANQAECgEIAQABNQAFFAQIBgAXAIEJAA==.Zenyea:BAAANQAECgMICAABNQAFFAQIBgAXAIEJAA==.Zetta:BAACNQAFFIEGAAIXAAQKgQlwCAAWAQAXAAQKgQlwCAAWAQA1AAQKgRsAAhcACQrfFwgTAJICABcACQrfFwgTAJICAAAA.',
Zo='Zome:BAABNQAECoElAAMdAAkKeBLfDgBsAgAdAAkKeBLfDgBsAgAPAAEKlAOFdwAyAAAAAA==.',
Zy='Zyndrael:BAAANQAECgUICgAAAA==.',
['Èl']='Èlytz:BAAANQADCgYICQAAAA==.',
['Êl']='Êlytz:BAAANQADCggJCAAAAA==.',
['ßl']='ßlue:BAAANQAECgYICQAAAA==.',
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
