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

local lookup = {'Mage-Arcane','Unknown-Unknown','Priest-Holy','Priest-Discipline','DemonHunter-Vengeance','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Shaman-Restoration','Evoker-Devastation','Druid-Balance','Shaman-Elemental','Warrior-Arms','Monk-Brewmaster','Paladin-Holy','Rogue-Assassination','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Warlock-Destruction','Priest-Shadow','Rogue-Outlaw','Druid-Feral','Warrior-Protection','Warlock-Affliction','Evoker-Preservation','DemonHunter-Devourer','Monk-Windwalker','Monk-Mistweaver','Rogue-Subtlety','Hunter-Survival','Warrior-Fury','Mage-Frost','Druid-Restoration','DemonHunter-Havoc','Evoker-Augmentation','Druid-Guardian','Shaman-Enhancement',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Accost:BAAANQADCgcIDQAAAA==.Achendron:BAAANQADCgUIBQAAAA==.Acronica:BAAANQAECgUIEgAAAA==.',
Ad='Addilynn:BAAANQABCgEIAQAAAA==.',
Ak='Akassa:BAAANQADCgcICwAAAA==.Aknologia:BAAANQAECgQIBgABNQAECggIGQABAKwNAA==.',
Al='Alecto:BAAANQAECgYIDQAAAA==.Allele:BAAANQAECgIIAgAAAA==.Allet:BAAANQADCggIFwABNQAECgUICAACAAAAAA==.',
Am='Amarah:BAABNQAECn8tAAIDAAkKmBtcKQDBAgADAAkKmBtcKQDBAgAAAA==.Ameilie:BAABNQAECn82AAMDAAkKKiArHQD7AgADAAkKKiArHQD7AgAEAAYKRBixCQC2AQAAAA==.',
An='Anapuwae:BAAANQAECgUIEQAAAA==.Animehero:BAABNQAECn8iAAIFAAgKHCCIBQDRAgAFAAgKHCCIBQDRAgAAAA==.',
Ar='Arcant:BAABNQAECn8gAAIBAAcKdxv+sQAdAgABAAcKdxv+sQAdAgAAAA==.Ardicov:BAAANQADCgYICwAAAA==.Argadin:BAAANQAECgUIBgABNQAECgkJKQAGAJAjAA==.Arglock:BAAANQADCgcIBwABNQAECgkJKQAGAJAjAA==.Argrekh:BAABNQAECn8pAAMGAAkKkCOhCgCHAwAGAAkKkCOhCgCHAwAHAAEKQQ8chQA3AAAAAA==.Argreks:BAAANQADCgEIAgABNQAECgkJKQAGAJAjAA==.Argrekt:BAAANQAECgIIAgABNQAECgkJKQAGAJAjAA==.Aridol:BAAANQADCgYIBgAAAA==.Arigön:BAAANQADCgQIBAAAAA==.Aronna:BAAANQADCgYICAAAAA==.Arosea:BAAANQADCgYIBgAAAA==.Arthaslk:BAABNQAECn9EAAMIAAkKxCXZAgDnAwAIAAkKxCXZAgDnAwAJAAIKBAklYQBUAAAAAA==.Aryssol:BAAANQADCggIEAAAAA==.',
At='Ate:BAABNQAECn8YAAIKAAgKtAzyXAB7AQAKAAgKtAzyXAB7AQAAAA==.Atlette:BAAANQAECgMIAwAAAA==.Attman:BAACNQAFFH8HAAILAAMK9RVUFwDhAAALAAMK9RVUFwDhAAA1AAQKfy8AAgsACQpaIW0PAEYDAAsACQpaIW0PAEYDAAAA.',
Au='Auradawn:BAAANQADCgcIDwAAAA==.',
Ba='Backwater:BAAANQADCgcIBwABNQAECgUICAACAAAAAA==.Badhands:BAAANQAECgIIAgAAAA==.Baeator:BAAANQAECgEIAQABNQAFFAcIGAAMAO0PAA==.Barneystins:BAAANQABCgEIAgABNQADCgQIBAACAAAAAA==.',
Be='Bearmane:BAABNQAECn8pAAINAAkKAyJnDgBVAwANAAkKAyJnDgBVAwAAAA==.Beastarsfan:BAABNQAECn8hAAIOAAkKoiJZCwCLAwAOAAkKoiJZCwCLAwAAAA==.Behmow:BAABNQAECn8qAAIPAAkKmSaGBwC2AwAPAAkKmSaGBwC2AwAAAA==.Belithel:BAAANQAECgQIBgABNQAECggIGwAOADsZAA==.Bencreepin:BAAANQAECgUIDgAAAA==.Bernoulli:BAABNQAECn8fAAIQAAgKWxR/EADfAQAQAAgKWxR/EADfAQAAAA==.',
Bi='Bigspitter:BAAANQADCgYIBgABNQAECgkJLQABAHokAA==.Bis:BAAANQADCgUJBQABNQAECgkJFgABAD0cAA==.',
Bl='Blessedxx:BAAANQAECgUIBgAAAA==.Bloodboo:BAAANQADCgQIBAAAAA==.Bloodyhpally:BAACNQAFFH8aAAIRAAcKShkkAwBpAgARAAcKShkkAwBpAgA1AAQKfyQAAxEACQq1GOIqALoCABEACQq1GOIqALoCAAgAAgoXD1thAXsAAAAA.',
Bo='Boopsnoopems:BAAANQAECgQIDAAAAA==.Borderline:BAAANQAECgUIBQABNQAFFAMIAwACAAAAAA==.',
Br='Bradcrit:BAAANQAECgEIAQAAAA==.',
Bu='Bubble:BAAANQAECgYIEgAAAA==.Bulldoser:BAAANQADCgQIBAAAAA==.Burrfoot:BAAANQAECgIIAwAAAA==.Bustah:BAAANQAECgcIEgABNQAECgkJHAADAIgbAA==.',
Bw='Bwoodmorgan:BAAANQAECgYIDgAAAA==.',
Ca='Calene:BAACNQAFFH8KAAISAAYKDBLwBADkAQASAAYKDBLwBADkAQA1AAQKfzwAAhIACQp1IwUJAEYDABIACQp1IwUJAEYDAAAA.Candy:BAAANQAECgMIBQAAAA==.Cannedcorn:BAAANQAECgIIAgAAAA==.Caperusin:BAAANQAECgUICAAAAA==.Casare:BAAANQADCgYIFgAAAA==.Cayde:BAAANQADCgYJBgABNQAFFAUICgAHAGcNAA==.',
Ce='Celestinee:BAAANQAECgYIEgAAAA==.Celyda:BAAANQAECgUICAAAAA==.Cenarian:BAAANQABCgUIBwAAAA==.',
Ch='Chabotloe:BAAANQAECgMIAwAAAA==.Chape:BAABNQAECn8dAAMRAAkKvhdNPQBtAgARAAkKvhdNPQBtAgAIAAYK/BDY6wA+AQAAAA==.Chochalinda:BAAANQAECggIEwAAAA==.',
Ci='Cinderlee:BAAANQAECgQIBgAAAA==.',
Co='Colexn:BAABNQAECn8bAAMTAAcK7hhFOQDpAQATAAcK7hhFOQDpAQAUAAIKMhDEvwBnAAAAAA==.Cong:BAACNQAFFH8FAAIPAAQK3gi6HwD/AAAPAAQK3gi6HwD/AAA1AAQKfyQAAg8ACQoVHgwnABsDAA8ACQoVHgwnABsDAAAA.Corg:BAAANQADCgYIBgAAAA==.Cornchipz:BAABNQAECn8ZAAIBAAgKrA1CzQDpAQABAAgKrA1CzQDpAQAAAA==.',
Cr='Crapsack:BAAANQABCgEIAQAAAA==.Croski:BAAANQADCgEIAQAAAA==.Cryonidus:BAAANQAECgEIAQAAAA==.',
Cu='Curves:BAAANQAECgEIAQAAAA==.',
Cy='Cypressa:BAAANQADCgQIBAAAAA==.',
Da='Daangalanng:BAAANQAECggIEgAAAA==.Daegra:BAABNQAECn8nAAISAAkKCR5VDwADAwASAAkKCR5VDwADAwAAAA==.Dankkush:BAAANQADCgQIBAAAAA==.Darkacedia:BAABNQAECn8tAAMVAAkKihV2TABrAgAVAAkKihV2TABrAgAWAAMKKwoJTwCRAAAAAA==.Darkzetta:BAAANQAECgIIAgABNQAFFAUICwAXAIUOAA==.',
De='Deadlift:BAAANQAECgYIDAAAAA==.Deadlyhoof:BAAANQADCgUIBQAAAA==.Dealosed:BAABNQAECn8ZAAMSAAgKphkuKgA+AgASAAgKeRkuKgA+AgAYAAQKDhXTEQDsAAAAAA==.Deathawolf:BAAANQAECgEIAQAAAA==.Deathkilera:BAAANQADCgUIBwAAAA==.Defy:BAAANQADCgYIBgAAAA==.Delenn:BAABNQAECn8XAAIZAAgKZxqrDQA9AgAZAAgKZxqrDQA9AgAAAA==.Demonclawz:BAAANQAECgYIBgAAAA==.Demonnyaa:BAAANQADCgcIBwAAAA==.Derzy:BAAANQADCgIIAgAAAA==.Dewygirl:BAAANQADCgQIBwAAAA==.',
Dh='Dhuumystic:BAAANQADCgEIAQAAAA==.',
Di='Disastapyre:BAAANQAECgIIAgABNQAFFAIIBgAKAH0GAA==.Disastasmite:BAAANQADCgIIBAABNQAFFAIIBgAKAH0GAA==.Dive:BAABNQAECn8WAAIBAAkKPRzAYQC7AgABAAkKPRzAYQC7AgAAAA==.',
Do='Doogru:BAABNQAECn8nAAIaAAgKbxvXDABjAgAaAAgKbxvXDABjAgAAAA==.Doogtwo:BAAANQADCggIHAABNQAECggIJwAaAG8bAA==.Doryndoran:BAAANQAECgQIBQAAAA==.Dorynhashots:BAAANQADCgUIBQAAAA==.Dotproduct:BAAANQADCgEIAQABNQADCgIIAgACAAAAAA==.Dotsrock:BAABNQAECn8WAAMbAAgKOg7fCgDCAQAbAAcKpw/fCgDCAQAVAAUKXgTCBwG2AAAAAA==.Dovah:BAAANQADCgIIAgAAAA==.',
Dr='Dragoneggs:BAABNQAECn8hAAMMAAkKfhn1DACRAgAMAAkKfhn1DACRAgAcAAkK9Qk8HwDeAQAAAA==.Dragonforce:BAAANQADCggIEgAAAA==.Drakonutz:BAAANQAECgYIDwAAAA==.Draxx:BAAANQAECggICAAAAA==.Drañzer:BAAANQAECgEIAgAAAA==.Dreammachine:BAAANQAECgcIBwAAAA==.Drjoel:BAAANQADCgcIEQAAAA==.Drunkenutz:BAAANQAECgQIDAAAAA==.Dräx:BAAANQAECggIEAAAAA==.',
Dw='Dwallen:BAAANQADCgIIAgAAAA==.Dwightschrut:BAAANQADCgQIBAAAAA==.',
['Dä']='Dälf:BAAANQAECgIIAgABNQAFFAcICQAJABsVAA==.',
Ea='Earthshocker:BAAANQAECgYICwAAAA==.',
El='Elenix:BAAANQAECgcIAQAAAA==.Elki:BAAANQADCgQIBgAAAA==.Elmesia:BAAANQAECgYIEgAAAA==.Eloris:BAABNQAECn8lAAIdAAgK7RzlGwB0AgAdAAgK7RzlGwB0AgAAAA==.Elpato:BAAANQADCgcIBwABNQAECgkJLQABAHokAA==.Elthyn:BAAANQAECgQIBwAAAA==.Elvar:BAAANQAECgEIAQAAAA==.',
Em='Emachine:BAAANQADCggICAABNQAECgIIAgACAAAAAA==.Emeraldrin:BAAANQADCgEIAQAAAA==.Emz:BAABNQAECn8rAAIYAAgKIyD5AwDYAgAYAAgKIyD5AwDYAgAAAA==.',
En='Eniar:BAAANQAECgMIBgAAAA==.',
Er='Erakk:BAAANQADCgEIAgAAAA==.Erianda:BAAANQABCgQIBAAAAA==.Eric:BAABNQAECn8cAAIPAAcK5Rz2eAApAgAPAAcK5Rz2eAApAgAAAA==.Eroninja:BAAANQAECgIIAwABNQAECggIGwAOADsZAA==.Erín:BAAANQAECgQIEAAAAA==.',
Eu='Eurong:BAACNQAFFH8HAAINAAQKsxHKFQAGAQANAAQKsxHKFQAGAQA1AAQKfx8AAg0ACQpIGU4rAHwCAA0ACQpIGU4rAHwCAAAA.',
Ez='Ezynuff:BAAANQAECgUICwAAAA==.',
Fa='Fapple:BAAANQAECgQIBwABNQAECggIKQAcAOgiAA==.Fatesworn:BAAANQADCgcIBwAAAA==.Faïry:BAABNQAECn8jAAIGAAkK/SBbIAAUAwAGAAkK/SBbIAAUAwAAAA==.',
Fe='Feaughoeren:BAAANQAECgYIBgAAAA==.Felwyrm:BAABNQAECn8nAAIVAAkKgRckTwBkAgAVAAkKgRckTwBkAgABNQAFFAMIAwACAAAAAA==.Feralshmeral:BAAANQABCgQIBAABNQAECgkJHgAGABEiAA==.',
Fo='Foragh:BAAANQAECgYICAAAAA==.Foxi:BAAANQADCggIEQABNQAECgcIEwACAAAAAA==.',
Fr='Frank:BAAANQAECggIDgAAAA==.Freakbeast:BAAANQAECgYJEgABNQAECgkJGAAYAAIeAA==.Fries:BAEANQAECgcIBwABNQAECggIDQACAAAAAA==.',
Fu='Fullkidney:BAACNQAFFH8KAAISAAQKeB7KCQBgAQASAAQKeB7KCQBgAQA1AAQKfyAAAhIACQrbImkJAEIDABIACQrbImkJAEIDAAAA.Funch:BAABNQAECn8iAAIbAAkKsBIhBQB3AgAbAAkKsBIhBQB3AgAAAA==.',
Ga='Gaefaeryn:BAABNQAECn8hAAMXAAkK5BQ4GwBsAgAXAAkK5BQ4GwBsAgAEAAEKmgF4MQAfAAAAAA==.Garonnaa:BAABNQAECn8ZAAIKAAgKNw7MVACeAQAKAAgKNw7MVACeAQAAAA==.Garthel:BAABNQAECn8cAAIeAAkKTRH6IgALAgAeAAkKTRH6IgALAgAAAA==.',
Ge='Genetiks:BAAANQADCgYIDAAAAA==.',
Gh='Ghari:BAABNQAECn8eAAIUAAYKIRK7bwBSAQAUAAYKIRK7bwBSAQAAAA==.',
Gi='Gingerlock:BAABNQAECn8fAAIVAAkKkBmvNgCuAgAVAAkKkBmvNgCuAgAAAA==.Gingershaman:BAAANQADCgEIAQAAAA==.Giyuu:BAAANQADCgUIBQAAAA==.',
Gn='Gnoblin:BAAANQADCggIFgAAAA==.',
Gr='Greka:BAAANQAECgUIDQAAAA==.Greylooms:BAAANQADCgcIBwAAAA==.Griplock:BAABNQAECn8oAAMKAAkKwwxCWgCHAQAKAAgKdQxCWgCHAQATAAEKlQ4rqwAyAAAAAA==.',
Gu='Gutz:BAAANQADCgcIDQAAAA==.',
['Gö']='Gözër:BAAANQADCgMIAwABNQAECgYIDAACAAAAAA==.',
Ha='Happyfriend:BAAANQAECgEIAQABNQAFFAMIAwACAAAAAA==.Haruko:BAAANQADCggICAAAAA==.',
He='Healalle:BAAANQADCgYICwABNQAECgcIEgACAAAAAA==.Healhole:BAABNQAECn8tAAMLAAkKPyH3EgAxAwALAAkKPyH3EgAxAwAOAAMKbhH46gC6AAAAAA==.Heàl:BAAANQAECgcIDgAAAA==.',
Hi='Hidolo:BAAANQADCgYIDAAAAA==.',
Hu='Hunterishard:BAAANQAECgQIBAAAAA==.',
Hy='Hylaina:BAAANQADCgYJCgAAAA==.',
['Hô']='Hôlÿ:BAAANQADCggIDgAAAA==.',
Ia='Iamamonk:BAAANQADCgEIAQAAAA==.',
Ik='Ikerous:BAAANQADCgMIAwAAAA==.',
Il='Ilysa:BAAANQABCgQIBAAAAA==.',
Im='Imadwagon:BAAANQADCgcIAgAAAA==.Imcolorblind:BAAANQADCgIIAgAAAA==.Imhammered:BAAANQAECgYIDgAAAA==.',
Io='Ioun:BAAANQADCgMIAwAAAA==.Iounn:BAAANQADCgcIBwABNQAECggIIgAfAJkXAA==.',
Is='Isatku:BAAANQAECgEIAQAAAA==.',
It='Itiswhatitiz:BAABNQAECn8oAAIGAAgKHB1hOAC/AgAGAAgKHB1hOAC/AgAAAA==.Itsybityshiv:BAABNQAECn8rAAIgAAkKKhbNDgCKAgAgAAkKKhbNDgCKAgAAAA==.',
Ja='Jakarr:BAAANQADCgQIBAAAAA==.Jams:BAAANQAECgUIBQAAAA==.',
Je='Jeabuss:BAAANQADCgUIBQAAAA==.',
Jh='Jhani:BAAANQAECgUIDQAAAA==.',
Ji='Jiu:BAABNQAECn8cAAIDAAkKiBtrJQDTAgADAAkKiBtrJQDTAgAAAA==.',
Jo='Joethemage:BAABNQAECn8iAAIBAAkKyhsdQwD+AgABAAkKyhsdQwD+AgAAAA==.Jormojo:BAAANQAECgMIAwAAAA==.',
Ju='Jungol:BAAANQADCgUICQAAAA==.',
Ka='Kallip:BAAANQADCggICAAAAA==.Kamin:BAAANQAECgYIBgABNQAECgkJIgABAMgbAA==.Katamaran:BAAANQAECgMIAwABNQAFFAUICwAXAIUOAA==.Kaykaypally:BAABNQAECn8WAAIIAAcKnxB8uwCgAQAIAAcKnxB8uwCgAQAAAA==.',
Ke='Kellan:BAAANQADCggIFgAAAA==.',
Kh='Khybyr:BAAANQADCgMIAwAAAA==.',
Ki='Kidata:BAABNQAECn8iAAIfAAgKmRf+FQAXAgAfAAgKmRf+FQAXAgAAAA==.Kindaprepped:BAAANQADCgQIBAAAAA==.Kinji:BAABNQAECn8bAAIOAAgKOxnGRwBUAgAOAAgKOxnGRwBUAgAAAA==.Kinn:BAAANQADCggICAABNQAECggIHwAQAFsUAA==.',
Ko='Konfu:BAAANQADCgcIEQAAAA==.Kormega:BAAANQAECgUIBQAAAA==.Korral:BAAANQADCggIDQAAAA==.',
Kr='Krispies:BAAANQAECgUIDQAAAA==.Kristysavage:BAABNQAECn8uAAMhAAkKxCA3AQBuAwAhAAkKtx43AQBuAwAGAAIK+RvbJwGZAAAAAA==.',
Ku='Kulaesca:BAACNQAFFH8JAAIVAAMKBRKsIQDuAAAVAAMKBRKsIQDuAAA1AAQKfykAAxUACQoKGW9GAHwCABUACQoKGW9GAHwCABYAAQrtAC+HAB0AAAAA.',
Ky='Kynar:BAACNQAFFH8bAAMTAAcKZiFDAgAnAgATAAYKZiFDAgAnAgAKAAYKngd/EABIAQA1AAQKfycAAxMACQpaJvcJAEoDABMACQpaJvcJAEoDAAoAAwqHE6GVALAAAAAA.Kyua:BAAANQAECgEIAQAAAA==.',
La='Ladragona:BAAANQADCggICAAAAA==.Lambshot:BAABNQAECn8ZAAMGAAgKzRRLdAAlAgAGAAgK1RJLdAAlAgAHAAYKRBaNNgCWAQAAAA==.Lambsy:BAACNQAFFH8eAAQPAAcKQxfIBgBQAgAPAAcKQxfIBgBQAgAiAAEKAAD/BQBIAAAaAAEKAAB4CQA9AAA1AAQKfysAAw8ACQqYJFsQAHwDAA8ACQqTJFsQAHwDACIAAwoCE5YhAKgAAAAA.Lanamama:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.Lanana:BAAANQADCgMIAwABNQAECgIIAgACAAAAAA==.',
Le='Lerat:BAABNQAECn8nAAIMAAkKZBxLBwAMAwAMAAkKZBxLBwAMAwAAAA==.',
Li='Lightwarden:BAAANQADCgQIBAAAAA==.Lilyy:BAACNQAFFH8GAAMjAAIKuRKRBwCdAAAjAAIKuRKRBwCdAAABAAIKAArETACKAAA1AAQKfykAAyMACQpGHHcGAJcCAAEACQp8F+VwAJwCACMABwrqHXcGAJcCAAAA.Lisanalgaib:BAABNQAECn8bAAIIAAgKPBWHlAD2AQAIAAgKPBWHlAD2AQAAAA==.Lizzimcguire:BAACNQAFFH8FAAIMAAIKgCDzCQDBAAAMAAIKgCDzCQDBAAA1AAQKfy0AAgwACQpqJXUBALcDAAwACQpqJXUBALcDAAAA.',
Lo='Lobobare:BAABNQAECn8fAAIkAAgK2x3QGwBUAgAkAAgK2x3QGwBUAgAAAA==.Loraen:BAAANQAECgUIDQAAAA==.',
Lu='Lunarmon:BAAANQADCgUIBQAAAA==.Lunchable:BAABNQAECn8XAAMLAAgKeh3EUwAUAgALAAYKziDEUwAUAgAOAAYKzBXFfgCkAQAAAA==.',
Ma='Maevora:BAAANQAECgUIEQAAAA==.Makaroni:BAAANQAECgUIBQAAAA==.Manticus:BAAANQADCgYICAAAAA==.Maomaoo:BAAANQAECgcIEgAAAA==.Marni:BAAANQAECgYIDwABNQAECgkJGwAIAHcfAA==.Marsrover:BAAANQAECgIIAgABNQAFFAcIHQAPAHcfAA==.Martel:BAAANQADCgQIBAAAAA==.Mashunit:BAAANQABCgIIAgAAAA==.Matroxx:BAACNQAFFH8QAAIeAAUKAhvqBgCLAQAeAAUKAhvqBgCLAQA1AAQKfy4AAh4ACQorJQAHAF8DAB4ACQorJQAHAF8DAAAA.',
Me='Medinduceyuh:BAAANQADCgEIAQAAAA==.Meenoi:BAABNQAECn8XAAIUAAgKxBuBRAAEAgAUAAgKxBuBRAAEAgABNQAECgkJHAADAIgbAA==.Mellotots:BAAANQABCgIIBAAAAA==.Metatron:BAAANQADCgIIAgAAAA==.',
Mi='Miadas:BAAANQAECgMIAwABNQAECggIJwAZAMEeAA==.Mimikyu:BAAANQABCgYIBgAAAA==.Minìwheats:BAAANQADCgMIAwAAAA==.',
Mo='Moardotsnow:BAABNQAECn8pAAMWAAkKgCQDGACrAQAVAAYKGSRlVQBSAgAWAAQKCiUDGACrAQAAAA==.Moby:BAAANQAECgMIBQAAAA==.Moistmender:BAAANQAECgUICAAAAA==.Mortiana:BAAANQADCggICAAAAA==.',
Mu='Murridan:BAABNQAECn8aAAIlAAkKIRsjHAC1AgAlAAkKIRsjHAC1AgAAAA==.',
My='Mykaela:BAAANQAECgEIAQAAAA==.',
['Më']='Mëow:BAAANQAECgMIBAAAAA==.',
Na='Namiyu:BAAANQADCgcIBwAAAA==.Narrath:BAAANQADCgMJAwAAAA==.Nayalaah:BAAANQAECgEIAQAAAA==.',
Ne='Nehpets:BAAANQADCgUIBQAAAA==.Nephelym:BAABNQAECn8gAAMDAAgKQA/8cQDCAQADAAgKQA/8cQDCAQAEAAIKrAIjJABHAAAAAA==.Nerv:BAAANQADCgMIBQAAAA==.',
Ni='Nicolasmage:BAAANQABCgMIAwAAAA==.Nirina:BAAANQAECgQIDAAAAA==.',
No='Nohtil:BAAANQADCgUIEQAAAA==.Notstephen:BAABNQAECn8aAAMDAAkKDghVdAC7AQADAAkKDghVdAC7AQAXAAMKdhQ8VwCpAAAAAA==.Nourishnutz:BAAANQADCgYIBgAAAA==.',
Nu='Nukefury:BAAANQAECgYICQABNQAFFAIIBgAKAH0GAA==.Nut:BAAANQAECgQIEAABNQAECggIGAAKALQMAA==.',
Nw='Nwalliance:BAAANQAECgEIAQAAAA==.',
['Nö']='Nötprepared:BAAANQADCgYIEwABNQAECgUICQACAAAAAA==.',
Oi='Oiflar:BAAANQAECgUIDwABNQAECggIKQAcAOgiAA==.',
Ol='Olangi:BAAANQAECgEIAQAAAA==.',
Om='Omnidh:BAAANQADCggIEAABNQAFFAMICQAeAJAjAA==.Omnipotent:BAAANQAECgUIBQAAAA==.',
On='Onepavo:BAAANQAECgYIEgAAAA==.',
Oo='Oogie:BAAANQADCgYIBgAAAA==.Oogrikusk:BAAANQADCgMIAgAAAA==.Oottedenttoo:BAAANQADCgQIBAAAAA==.',
Op='Oppose:BAAANQAECgYICwAAAA==.',
Or='Orexion:BAABNQAECn8eAAIiAAgKlQoWEgCAAQAiAAgKlQoWEgCAAQAAAA==.Ormagöden:BAABNQAECn8jAAITAAgKJA5cQgC1AQATAAgKJA5cQgC1AQAAAA==.',
Ov='Overpower:BAAANQADCgYIBgAAAA==.',
Pa='Pagoda:BAAANQAECgUICgAAAA==.Palladean:BAAANQAECgIIAwAAAA==.Palphen:BAAANQAECgcJDAABNQAECgkJGgADAA4IAA==.Panako:BAAANQAECgUICQAAAA==.Pastasauce:BAABNQAECn8dAAIIAAYK3wlN+gAjAQAIAAYK3wlN+gAjAQAAAA==.',
Pe='Pegero:BAAANQADCgYIDQAAAA==.Penelohpe:BAABNQAECn8iAAIBAAkKyBvSegCIAgABAAkKyBvSegCIAgAAAA==.',
Ph='Phatt:BAAANQAECgMIAwAAAA==.Phoenixdrac:BAAANQADCggICQAAAA==.Phoon:BAECNQAFFH8JAAMVAAQKzxsqFQBRAQAVAAQKzxsqFQBRAQAWAAEKKRGCHABOAAA1AAQKfykAAxUACQpvI0A7AJ8CABUABwouI0A7AJ8CABYABAqiITkkAE8BAAAA.Phoondk:BAEANQAECgUICAABNQAFFAQICQAVAM8bAA==.',
Pi='Piggy:BAAANQAECgMIBAAAAA==.Pita:BAAANQABCgYIBgAAAA==.Pizzadriver:BAACNQAFFH8dAAMPAAcKdx/aAwCaAgAPAAcKdx/aAwCaAgAiAAEKAACsBQBLAAA1AAQKfygAAw8ACQrMJakZAFADAA8ACQrCJakZAFADACIAAQo9JlonAG4AAAAA.',
Pl='Plaguefist:BAAANQADCgcIBwABNQADCggIEgACAAAAAA==.Plata:BAAANQAECgUIDAAAAA==.',
Po='Poosicat:BAAANQABCgYIBgAAAA==.Poosycat:BAAANQADCgMIAQAAAA==.',
Pr='Praytroxx:BAAANQAECgQIDAABNQAFFAUIEAAeAAIbAA==.Premonitions:BAAANQAECgIIAgAAAA==.Premune:BAABNQAECn8uAAIRAAgKzhwNLgCsAgARAAgKzhwNLgCsAgAAAA==.Prion:BAABNQAECn8VAAQlAAkKJhSsLwAlAgAlAAkKPBKsLwAlAgAdAAEKlRQ5ZwBAAAAFAAEKOgu7MwAqAAAAAA==.',
Pu='Pucco:BAAANQADCgIIAgAAAA==.Putrav:BAAANQAECgYICAAAAA==.',
Py='Pyrena:BAAANQADCgEIAQAAAA==.Pyroclasm:BAAANQAECgUICgAAAA==.Pyrrha:BAAANQADCgMIAwAAAA==.',
Qu='Quigly:BAAANQADCgIIAgAAAA==.',
Ra='Ragingfluids:BAABNQAECn8bAAMiAAgKrhMrEgB+AQAPAAgK7xEkfQAeAgAiAAYKnBQrEgB+AQAAAA==.Rahdek:BAAANQADCgMIAwAAAA==.Raine:BAACNQAFFH8dAAILAAcKYxj1AwBCAgALAAcKYxj1AwBCAgA1AAQKfyIAAwsACQpNFTBRAB4CAAsACQpNFTBRAB4CAA4ABApeFurVAOMAAAAA.Raistlin:BAAANQADCgEIAQAAAA==.Ralfio:BAABNQAECn8pAAMcAAgK6CIGCQASAwAcAAgK6CIGCQASAwAmAAEKAAAdJAAzAAAAAA==.Rasq:BAAANQAECggIEwAAAA==.Rat:BAABNQAECn8XAAISAAkKNCF3CABNAwASAAkKNCF3CABNAwAAAA==.Rayaray:BAAANQADCgYIBgAAAA==.Raynith:BAABNQAECn8nAAQZAAgKwR5eEAACAgANAAcKRh7nLAByAgAZAAYKXhteEAACAgAnAAIK4hGdTABrAAAAAA==.Rayraye:BAAANQADCgIIAgAAAA==.',
Rd='Rdyoshy:BAAANQADCgUIBQAAAA==.',
Re='Readycheck:BAABNQAECn8kAAMNAAkK3Q8ANgA3AgANAAkKLA8ANgA3AgAnAAcKyQhILwAaAQAAAA==.Reflex:BAAANQAECgIIAgAAAA==.Regirock:BAAANQABCgMIAwAAAA==.Rellek:BAAANQAECgIIAgAAAA==.Remulous:BAAANQAECgYIDgAAAA==.Resist:BAAANQADCgYIBgAAAA==.Retallica:BAAANQAECgcIDwAAAA==.Revali:BAACNQAFFH8KAAIHAAUKZw1zDQBhAQAHAAUKZw1zDQBhAQA1AAQKfzYAAwYACQokIskwANgCAAYACQoBHskwANgCAAcACQocHfoXAJYCAAAA.Revelaen:BAAANQAECgcIDwABNQAFFAUICgAHAGcNAA==.',
Ri='Rick:BAACNQAFFH8KAAIHAAMKwxwVFAD5AAAHAAMKwxwVFAD5AAA1AAQKfxwAAwcACQr2IjoTAMYCAAcACQqwIjoTAMYCAAYABApOIIwAAf4AAAAA.',
Rm='Rmagep:BAAANQAECgUICwAAAA==.',
Ro='Roadhouse:BAAANQAECgQIBwAAAA==.Roman:BAAANQAECgYIDAABNQAECgkJNwAcAMAjAA==.Roshango:BAAANQADCgYIBgAAAA==.Rosinator:BAAANQAECggIAQAAAA==.Rotgus:BAAANQAECgEIAQAAAA==.Rouk:BAAANQAECgcIDQABNQAECgkJGAAIAIUmAA==.Rowgar:BAAANQAECgcIEwAAAA==.',
Ru='Rubenslik:BAABNQAECn8rAAIBAAkKliBrKgA7AwABAAkKliBrKgA7AwAAAA==.',
Sa='Saelyn:BAAANQADCggIBgAAAA==.Saephora:BAAANQAECgYIDgAAAA==.Saggypants:BAABNQAECn8XAAINAAkKRBVILwBjAgANAAkKRBVILwBjAgAAAA==.Sakurai:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.Salamander:BAAANQAECgUJCgAAAA==.Salazzle:BAAANQADCgQIBAAAAA==.Sammel:BAAANQAECgUIEAAAAA==.Sanari:BAAANQADCgUIBwABNQAECggIGwAOADsZAA==.Sandilla:BAAANQADCggICAABNQAECgkJIAAPAC4kAA==.Sangwine:BAAANQADCgYIBgAAAA==.Sapphica:BAAANQAECgEIAQAAAA==.Sathreina:BAABNQAECn8kAAIIAAkKERRYcgBGAgAIAAkKERRYcgBGAgAAAA==.',
Sc='Scaries:BAABNQAECn8cAAIQAAkKuhtBBwDJAgAQAAkKuhtBBwDJAgAAAA==.Scariesdwarf:BAAANQADCgYICgAAAA==.Scootko:BAABNQAECn8YAAIIAAcKSyXBQADQAgAIAAcKSyXBQADQAgAAAA==.Scuss:BAAANQADCggICAAAAA==.',
Se='Sefers:BAAANQADCgEIAQAAAA==.Sego:BAAANQAECgEIAQAAAA==.Sekimaru:BAAANQAECgIIAgAAAA==.Senli:BAAANQAECgEIAQAAAA==.Severson:BAABNQAECn8bAAIHAAgKXAzcMwCrAQAHAAgKXAzcMwCrAQAAAA==.Sey:BAAANQADCgYIBgAAAA==.',
Sh='Shadowapoke:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Shadowisbad:BAABNQAECn8mAAIXAAgK3BoEHABiAgAXAAgK3BoEHABiAgAAAA==.Shadvoker:BAABNQAECn8iAAMcAAgKzx2BDgC/AgAcAAgKzx2BDgC/AgAMAAIK1BFpMwBvAAAAAA==.Shamaneggs:BAAANQAECgcIEAAAAA==.Shamatroxx:BAABNQAECn8aAAIoAAcK6RzdEABZAgAoAAcK6RzdEABZAgABNQAFFAUIEAAeAAIbAA==.Shamberry:BAAANQAECggIDgAAAA==.Shambles:BAAANQADCgYICQAAAA==.Shieldwalle:BAAANQAECgcIEgAAAA==.Shinobukocho:BAAANQADCgQJBAAAAA==.Shotigolova:BAAANQADCgcIDgAAAA==.',
Si='Sidesalad:BAAANQAECgMIBAAAAA==.Sidric:BAABNQAECn8eAAINAAgKCA0dSgC6AQANAAgKCA0dSgC6AQAAAA==.Silre:BAAANQAECgUIBwAAAA==.Sim:BAABNQAECn8gAAIPAAkKLiQbFQBkAwAPAAkKLiQbFQBkAwAAAA==.Singularité:BAAANQAECggIDwABNQAFFAYICgASAAwSAA==.Sipplex:BAAANQADCgQIBAAAAA==.',
Sl='Slander:BAAANQAECgQJBAABNQAECgUJCgACAAAAAA==.Slanderous:BAAANQADCgEJAQABNQAECgUJCgACAAAAAA==.',
Sn='Snuudle:BAAANQAECgcIDwABNQAECgkJHAAVABwXAA==.',
So='Solokills:BAAANQADCgMIAwABNQADCgYIDQACAAAAAA==.Sophia:BAAANQAECgcIEgAAAA==.Soundtrack:BAAANQADCgYICQABNQAECgIIAgACAAAAAA==.Soyshine:BAAANQADCgYIBgAAAA==.',
Sp='Spaceman:BAAANQAFFAMIAwAAAA==.',
Sq='Squab:BAABNQAECn8cAAINAAkKaR53GQD6AgANAAkKaR53GQD6AgAAAA==.Squanchy:BAAANQADCgYJCAAAAA==.',
St='Stabbywixx:BAAANQAECgIIAgAAAA==.Starwnd:BAABNQAECn8UAAIVAAcKlhelgADgAQAVAAcKlhelgADgAQABNQAFFAUIDAAmANgQAA==.Sterìs:BAAANQAECgEIAQAAAA==.Stickman:BAAANQADCggICAABNQAFFAMIAwACAAAAAA==.Stillcreepin:BAAANQADCggIFQAAAA==.Storienn:BAAANQAECgYIEQAAAA==.Stormzpaly:BAAANQAECgYIEQAAAA==.',
Su='Suküna:BAAANQADCggIFwAAAA==.Sunbur:BAAANQADCgYICgAAAA==.Sunglo:BAAANQAECgUIBwAAAA==.Surch:BAAANQADCgEIAQAAAA==.',
Sw='Swaption:BAABNQAECn8cAAILAAgKGiJrGQAKAwALAAgKGiJrGQAKAwAAAA==.Sweetie:BAAANQADCgEIAQAAAA==.',
Sy='Syrelia:BAABNQAECn8sAAIBAAkK/hVthQBzAgABAAkK/hVthQBzAgAAAA==.',
['Só']='Sónny:BAAANQABCgIIAgAAAA==.',
Ta='Tablescraps:BAAANQABCggICAABNQADCgIIAgACAAAAAA==.Tassarosea:BAAANQADCggIIQABNQAFFAIIBQAMAIAgAA==.Tauloe:BAAANQAECgUICgAAAA==.Tayna:BAAANQAECgUIDAAAAA==.',
Te='Tenderoni:BAAANQADCgEIAQAAAA==.',
Th='Thatsmyhorse:BAAANQADCgIIAgAAAA==.Thatsograven:BAAANQADCgQIBAABNQADCgUIBQACAAAAAA==.Thomosaurus:BAAANQADCggIDAAAAA==.Thraly:BAAANQADCgYIBwAAAA==.Thunk:BAABNQAECn8VAAIOAAkKzSKBCwCKAwAOAAkKzSKBCwCKAwABNQAECgkJIAAPAC4kAA==.',
Ti='Timdawg:BAAANQAECgYIDgABNQAFFAcIHQAVAHQcAA==.Timmolate:BAACNQAFFH8dAAQVAAcKdBy+BgABAgAVAAYKoRq+BgABAgAWAAIKwRfKCgCmAAAbAAEKAADYDABLAAA1AAQKfycAAxYACQpQJPUKAEcCABUABwo+Hq5WAE4CABYACAoMGfUKAEcCAAAA.Tiramisubear:BAAANQAECggIBwAAAA==.Tircaps:BAAANQADCgUIBQAAAA==.',
To='Tomcruise:BAAANQAECgIIAgAAAA==.Tomotostein:BAABNQAECn8hAAIIAAkKTRipagBZAgAIAAkKTRipagBZAgAAAA==.Tornado:BAAANQABCgQICQABNQADCgQIBAACAAAAAA==.Tourniquet:BAAANQABCgQIBgAAAA==.',
Tr='Trilla:BAAANQADCgUIBQAAAA==.Tristîtia:BAABNQAECn8ZAAMXAAkK/A7LIwAQAgAXAAkK/A7LIwAQAgADAAIKCwnz4gB1AAAAAA==.Trulu:BAAANQADCgQIBQAAAA==.',
Ts='Tsukikyo:BAAANQADCgQIBAAAAA==.Tsuma:BAAANQABCgIIAgAAAA==.Tsume:BAAANQAECgQICAAAAA==.',
Tt='Ttomas:BAAANQAECggIEAAAAA==.',
Ty='Tyrinn:BAAANQAECgYICgAAAA==.Tyv:BAABNQAECn8pAAIBAAgKUg/MyADyAQABAAgKUg/MyADyAQAAAA==.',
Uz='Uzì:BAAANQADCgIIAgAAAA==.',
Va='Vainatetosix:BAAANQAECgUICQAAAA==.Vallodon:BAABNQAECn8hAAIBAAgKWiJ3TQDmAgABAAgKWiJ3TQDmAgAAAA==.Vantablack:BAAANQABCgIIAgABNQADCgQIBAACAAAAAA==.Vanwolfy:BAAANQAECggIEAAAAA==.Vaylorian:BAAANQAECgQICAAAAA==.',
Ve='Velectran:BAAANQADCgUICgABNQAECgkJLAABAP4VAA==.Velorian:BAAANQADCgMIAwAAAA==.Velveeta:BAAANQAECgMIAwAAAA==.Veragon:BAAANQADCgcIBwAAAA==.',
Vf='Vfacer:BAAANQADCgEIAQAAAA==.',
Vi='Vikimg:BAAANQAECgcIEAAAAA==.Violet:BAAANQADCgEIAQAAAA==.',
Vo='Voodoomike:BAAANQAECgQIBAAAAA==.Vortash:BAAANQADCgUIBwAAAA==.',
Vy='Vynle:BAAANQAECgEIAQAAAA==.',
Wa='Warheimer:BAABNQAECn8VAAMUAAgKtg6aXgCRAQAUAAgKtg6aXgCRAQAKAAQKVgYJoACUAAAAAA==.Warrgodx:BAABNQAECn9DAAMPAAkKnSKLDwCAAwAPAAkKnSKLDwCAAwAiAAEKygjwMgA0AAABNQAECgkJRAAIAMQlAA==.',
Wh='Whoknows:BAAANQADCgIIAgAAAA==.',
Wo='Woogi:BAAANQADCgUIBQAAAA==.',
Wr='Wrongwookie:BAABNQAECn8mAAIOAAgKLhkYRgBaAgAOAAgKLhkYRgBaAgAAAA==.',
Ya='Yapper:BAAANQADCgMIAwAAAA==.',
Yo='Yolanda:BAAANQAECgIIAgAAAA==.Yoyohunty:BAAANQAECgYIBwAAAA==.',
Yt='Ytix:BAAANQAECgEIAQAAAA==.',
Yu='Yumekoo:BAAANQADCgIIAgAAAA==.',
Za='Zabada:BAAANQAECgEIAQAAAA==.Zaldrea:BAAANQAECgMIAwABNQAFFAUICwAXAIUOAA==.Zandrea:BAAANQAECgYIDgABNQAFFAUICwAXAIUOAA==.Zariee:BAAANQABCgIIAwAAAA==.',
Ze='Zehz:BAABNQAECn8aAAITAAkKZAFpjwByAAATAAkKZAFpjwByAAAAAA==.Zemsen:BAABNQAECn8nAAIBAAkKoh0UawCoAgABAAkKoh0UawCoAgAAAA==.Zentrea:BAAANQAECgMIAwABNQAFFAUICwAXAIUOAA==.Zenyea:BAAANQAECgcIEgABNQAFFAUICwAXAIUOAA==.Zetta:BAACNQAFFH8LAAIXAAUKhQ7rCAB1AQAXAAUKhQ7rCAB1AQA1AAQKfyEAAhcACQqRGZEWAKQCABcACQqRGZEWAKQCAAAA.',
Zo='Zome:BAABNQAECn8rAAMgAAkKbRN4DwCBAgAgAAkKbRN4DwCBAgASAAEKlAN1ogAwAAAAAA==.',
Zy='Zyndrael:BAABNQAECn8bAAIIAAkKdx/hKwAWAwAIAAkKdx/hKwAWAwAAAA==.',
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
