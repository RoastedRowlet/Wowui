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

local lookup = {'Unknown-Unknown','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Priest-Holy','Mage-Arcane','Paladin-Retribution','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Shaman-Elemental','Hunter-BeastMastery','DeathKnight-Unholy','Warrior-Arms','Warrior-Protection','Rogue-Subtlety','Rogue-Assassination','Shaman-Enhancement','Priest-Discipline','Paladin-Holy','Mage-Frost','Druid-Balance','Druid-Restoration','Druid-Feral','Druid-Guardian','DeathKnight-Blood','Paladin-Protection','Priest-Shadow','Hunter-Marksmanship','Shaman-Restoration','DemonHunter-Vengeance','Rogue-Outlaw','DemonHunter-Devourer','Warrior-Fury','Hunter-Survival',}
local provider = {region='US',realm='Kargath',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaryn:BAAANQADCggICAABNQAECgUICwABAAAAAA==.',
Ab='Abracadabruh:BAAANQAECgcIEgAAAA==.Absynthia:BAAANQAECgUIDgAAAA==.',
Ac='Academe:BAAANQADCgYICQAAAA==.Accalon:BAAANQADCgYIBgAAAA==.',
Ad='Adérai:BAAANQAECgYICAAAAA==.',
Ae='Aellopus:BAAANQAECgUICwAAAA==.Aero:BAAANQAECgUICwAAAA==.',
Ag='Agròm:BAAANQADCgQIBAABNQADCgcICwABAAAAAA==.',
Ak='Akata:BAAANQADCgQIBQAAAA==.Akku:BAAANQADCgYIBwAAAA==.',
Al='Alanwake:BAABNQAECoEfAAQCAAgKERrADQBOAgACAAgKUxfADQBOAgADAAUKSxiUCwBMAQAEAAMKGQNrOwBpAAAAAA==.Aldourolf:BAAANQABCgQIBAAAAA==.Alomeo:BAEANQADCgYJCwAAAA==.Alphasmash:BAAANQAECgIIAgAAAA==.',
Am='Amiliane:BAAANQAECgQICQAAAA==.Amilmean:BAAANQAECgEJAQAAAA==.Amoradine:BAAANQAECgIIAgAAAA==.Amz:BAAANQAECgIIAgAAAA==.',
An='Anadrien:BAAANQAECgYIDwAAAA==.Ancelagon:BAAANQADCgYIBwAAAA==.Andrae:BAAANQADCgYIHQAAAA==.Angrimia:BAAANQAECgUICwAAAA==.Annussa:BAAANQAECgEIAQAAAA==.Antal:BAAANQADCgcIBwAAAA==.',
Ar='Arboria:BAAANQAECggIAgAAAA==.Arcadya:BAAANQADCgcIBwAAAA==.Archielgh:BAAANQADCgUIBQAAAA==.Ardbeg:BAAANQABCgYIDAAAAA==.Arduin:BAAANQAECgUICwAAAA==.Aremethea:BAAANQAECgQICAAAAA==.Aronk:BAAANQADCggIHAABNQAECgQICgABAAAAAA==.Arore:BAAANQADCgMJBQABNQAECgQICgABAAAAAA==.Aroreck:BAAANQADCgQIBAABNQAECgQICgABAAAAAA==.Arorepriest:BAAANQADCgcIBwABNQAECgQICgABAAAAAA==.Articulaté:BAABNQAECoEWAAIFAAgK8SB9FQD4AgAFAAgK8SB9FQD4AgAAAA==.Arîel:BAAANQADCggICAAAAA==.',
As='Asbjorn:BAAANQAECgMIAwAAAA==.',
At='Attack:BAAANQADCgQIBQABNQAECgkJKwAGAOwhAA==.',
Av='Avestara:BAAANQAECgUICwAAAA==.',
Ay='Ayohec:BAAANQAECggICAAAAA==.',
Az='Azoril:BAABNQAECoEWAAIHAAgKbxKkdgDfAQAHAAgKbxKkdgDfAQAAAA==.Azùla:BAAANQAECgQIBgAAAA==.',
['Aí']='Aídeen:BAAANQAECgQICAAAAA==.',
Ba='Babs:BAAANQADCgEJAQAAAA==.Badmooddude:BAAANQAECgMIBAAAAA==.Baelnorn:BAAANQAECgYIEQAAAA==.Bains:BAAANQADCgcIBwAAAA==.Barrex:BAAANQAECgIIAwAAAA==.Basken:BAAANQAECgYIDwAAAA==.Batôsai:BAAANQAECgEIAQAAAA==.',
Be='Beardiso:BAAANQAECgYICwAAAA==.Beastcleave:BAAANQAECgQIBAAAAA==.Beelz:BAAANQAECgUICwAAAA==.Bekens:BAAANQAECgYIBgAAAA==.Belaraariaae:BAAANQADCggIDQABNQAECgcJFgAIAEUgAA==.Benipal:BAABNQAECoEuAAIHAAkKoBxxLgDRAgAHAAkKoBxxLgDRAgAAAA==.Bernardboggs:BAAANQAECgYIEgAAAA==.',
Bh='Bheefknight:BAAANQAECgcIEgAAAA==.Bheeftotemz:BAAANQADCgUICQAAAA==.',
Bi='Bierbro:BAAANQAECgcIEgAAAA==.Bigsofty:BAAANQAECgIIAwAAAA==.Billiam:BAAANQAECgEIAQAAAA==.Billié:BAABNQAECoEbAAMJAAcKSBrFTQAkAgAJAAcKSBrFTQAkAgAKAAEKehtxXgBRAAABNQAECggIJAALAMAgAA==.',
Bl='Blightheaded:BAAANQADCgYIBgAAAA==.Blumir:BAAANQAECgcICwAAAA==.',
Bo='Bogatyri:BAAANQADCgIIAgAAAA==.Bomgan:BAAANQAECgUICgAAAA==.Bonchonn:BAABNQAECoEiAAIMAAkKICTWBgCOAwAMAAkKICTWBgCOAwAAAA==.Bonkula:BAAANQAECgQIBQAAAA==.Bops:BAAANQADCggIDQAAAA==.Borque:BAAANQAECgYIEQAAAA==.Bosenmorimei:BAAANQADCgIIAgAAAA==.',
Br='Brae:BAAANQAECgMJBAAAAA==.Brazonk:BAAANQAECgMIBQAAAA==.Brewzco:BAABNQAECoEdAAIIAAcK0SDTBgCXAgAIAAcK0SDTBgCXAgAAAA==.Bricifergoat:BAAANQAECgMIAwABNQAECgkJHAANAP8kAA==.Briciferkong:BAABNQAECoEcAAINAAkK/yQ8BwBtAwANAAkK/yQ8BwBtAwAAAA==.Brickedup:BAAANQAECgEIAQAAAA==.Brightblayde:BAAANQAECgUIDgAAAA==.',
Bu='Buanto:BAAANQADCggIGgAAAA==.Bubblegumm:BAAANQADCgUJBQAAAA==.Bubbletea:BAAANQAECgQICQABNQADCgUJBQABAAAAAA==.Butterball:BAABNQAECoEZAAMOAAkKDhmSUgBRAgAOAAgKNRuSUgBRAgAPAAIKPQdcLgBUAAAAAA==.Butterknight:BAAANQAECgYIBgAAAA==.',
Ca='Candlelock:BAAANQAECgIIAwAAAA==.Candlewic:BAAANQADCggIFwAAAA==.Cathal:BAAANQABCgYICgAAAA==.Cattroll:BAAANQAECgQIBQABNQAECgUJDAABAAAAAA==.',
Ce='Celithila:BAAANQAECgQICAAAAA==.Celithvia:BAAANQAECgMIBAAAAA==.Cervantés:BAABNQAECoEbAAMQAAcKHxn1KQBAAQAQAAQKqRj1KQBAAQARAAMKvBliTAD6AAAAAA==.',
Ch='Chaosknight:BAAANQAECgUICAAAAA==.Charginatyou:BAAANQADCggIDwABNQAECggIIwASAJcSAA==.Charla:BAAANQADCgUIBwABNQAECggIHAAMAAIUAA==.Chelsea:BAAANQADCggICgAAAA==.Chise:BAABNQAECoEXAAITAAgKEhvoAgCnAgATAAgKEhvoAgCnAgAAAA==.Chiza:BAAANQADCgUIBwAAAA==.Chob:BAAANQADCgcICwAAAA==.',
Cl='Clarry:BAAANQADCgYIDAAAAA==.Clyde:BAAANQAECgEIAQAAAA==.Clydk:BAAANQAECgIIAwAAAA==.',
Co='Coachbeard:BAABNQAECoEYAAIUAAgK+hSgQgAaAgAUAAgK+hSgQgAaAgAAAA==.Colzaratha:BAAANQAECgQICwAAAA==.Conrow:BAAANQADCgQIBAAAAA==.Coorsbanquet:BAAANQAECgcIDwAAAA==.Corian:BAAANQADCgQIBAAAAA==.Corndog:BAABNQAECoEgAAMGAAkK6xhTewBPAgAGAAgKXBdTewBPAgAVAAIK3hwvIQCjAAAAAA==.Corpsereth:BAAANQADCggICAAAAA==.Cozzworth:BAAANQADCgEIAQAAAA==.',
Cr='Cronchybacon:BAAANQADCgcIBwAAAA==.',
Cu='Cudguzzler:BAAANQAECgIIAgAAAA==.Cursegoesmoo:BAAANQAECgYICQAAAA==.Cursehoots:BAABNQAECoElAAIWAAkKzCKFCgBhAwAWAAkKzCKFCgBhAwAAAA==.',
Cy='Cyntheria:BAABNQAECoEYAAIHAAgKFhv9RgBzAgAHAAgKFhv9RgBzAgAAAA==.',
Da='Daddybeàr:BAABNQAECoEjAAUXAAkKVR+vBwAdAwAXAAkKVR+vBwAdAwAYAAQKXxb/GQDvAAAZAAIK6RWFMACGAAAWAAEKdhGJjQA+AAAAAA==.Daendron:BAAANQAECgYIBgAAAA==.Darksaxon:BAAANQAECgUICAAAAA==.Darorek:BAAANQAECgQICgAAAA==.',
De='Deathnethal:BAAANQADCgYIBgAAAA==.Deathweaver:BAABNQAECoEhAAMRAAkK9CS5AADeAwARAAkK9CS5AADeAwAQAAgKDiMzBgAMAwAAAA==.Debumanko:BAAANQADCggIDgAAAA==.Decima:BAAANQADCgcIEAAAAA==.Deeneye:BAAANQADCgYIEAABNQAECgEIAgABAAAAAA==.Delerai:BAAANQAECgEIAQAAAA==.Dellgado:BAAANQAECgIIAgAAAA==.Deme:BAAANQAECgUIBgAAAA==.Demonbains:BAAANQAECgEIAQAAAA==.Demonica:BAAANQAECgQIBwAAAA==.Demonscythe:BAAANQADCgcIEQAAAA==.Dendrax:BAAANQAECgYIDgAAAA==.Dented:BAAANQABCgQIBAAAAA==.Deviance:BAAANQAECgIIAwAAAA==.Dezwar:BAAANQADCgEIAQABNQAFFAUIDQAVAH8hAA==.',
Di='Dissonance:BAAANQADCgUIBQAAAA==.',
Dj='Djanga:BAAANQADCgYIBgABNQAECgUIDAABAAAAAA==.Djdazzle:BAAANQADCgYIBwAAAA==.',
Do='Dogbearcat:BAAANQADCgQIBAABNQAFFAMIAwABAAAAAA==.Dorito:BAAANQAFFAEIAQAAAA==.',
Dr='Dragooned:BAACNQAFFIEHAAIVAAUKjBNlAACfAQAVAAUKjBNlAACfAQA1AAQKgR8AAhUACQrPJfIAAIYDABUACQrPJfIAAIYDAAAA.Drahhrak:BAAANQADCgQIBwAAAA==.Drango:BAAANQAECgUJBwAAAA==.Draugdae:BAAANQAECgQICAAAAA==.Draxtor:BAAANQADCgQJBAAAAA==.Drinksomuch:BAAANQAECgUICwAAAA==.Drizzlin:BAAANQADCgYIBgAAAA==.Drleche:BAAANQADCgEIAQAAAA==.Drob:BAEANQAECgYIDQAAAA==.Drocket:BAEANQAECgUICwAAAA==.Drome:BAAANQADCgcIDwABNQAECgQICQABAAAAAA==.Drukhi:BAAANQAECgYIEQAAAA==.',
Du='Dudetotems:BAAANQAECgcIDgAAAA==.Dungrough:BAAANQAECgUIBQAAAA==.Durtkal:BAABNQAECoEXAAMJAAgKGhMMaADPAQAJAAcK6hEMaADPAQAKAAEKahv3XgBQAAAAAA==.',
Dy='Dyonn:BAAANQAECgQICAAAAA==.',
Ea='Earnhardt:BAAANQAECgIIAgAAAA==.',
Ef='Efarel:BAABNQAECoEaAAIOAAcKDRRRfgDLAQAOAAcKDRRRfgDLAQAAAA==.Efdis:BAAANQADCgIIAgAAAA==.',
Ei='Eienarinna:BAAANQADCgYIBgAAAA==.Eilana:BAABNQAECoEbAAMaAAkKiBipHwCAAgAaAAkKiBipHwCAAgANAAcKTAZxZgANAQABNQAFFAMIAwABAAAAAA==.Eilària:BAAANQADCgQIBwAAAA==.',
El='Elsa:BAAANQAECgYIEgAAAA==.',
Em='Emma:BAAANQADCggJDgAAAA==.',
En='Eneco:BAABNQAECoEfAAIFAAkKPiE3CwBEAwAFAAkKPiE3CwBEAwAAAA==.Enserath:BAAANQADCgYICwAAAA==.',
Eu='Eurythmics:BAAANQAECgUICgAAAA==.',
Ev='Evonahh:BAAANQADCgQIBAAAAA==.',
Ex='Exelion:BAAANQAECgYIEgAAAA==.Explogan:BAAANQAECgEIAQAAAA==.',
Ez='Ezanah:BAAANQADCgIIBAAAAA==.Ezrack:BAAANQADCgYICAABNQAECgIIAgABAAAAAA==.',
Fa='Faaith:BAAANQADCgcIFwAAAA==.Fahooquazaad:BAAANQADCggIIgAAAA==.Fancie:BAAANQADCgUIBQABNQAECgYIDwABAAAAAA==.Fancy:BAAANQAECgcIEwAAAA==.',
Fe='Feetlesmcdee:BAAANQAECgQICAAAAA==.Felfáádaern:BAAANQADCgEJAQAAAA==.Felporch:BAAANQAECgIIAwAAAA==.',
Fi='Fitzy:BAABNQAECoEUAAMbAAUK7BrOJwBEAQAbAAQKth3OJwBEAQAUAAIKhQPY3gBWAAAAAA==.',
Fl='Flowermound:BAAANQAECgIIAgAAAA==.',
Fo='Fourqto:BAAANQAECgUICgAAAA==.Fox:BAACNQAFFIEJAAIFAAUK1xk7BwDQAQAFAAUK1xk7BwDQAQA1AAQKgSAAAgUACQryIogOACgDAAUACQryIogOACgDAAAA.',
Fr='Freya:BAAANQADCgUIBQAAAA==.',
Fu='Fujikujaku:BAAANQAECgUICwAAAA==.Fulmetal:BAAANQAECgYIEAAAAA==.Funji:BAAANQAECgUIDAAAAA==.Funkalicious:BAAANQAECgYIDgAAAA==.',
['Fé']='Félo:BAAANQAECgYIDgAAAA==.',
Ga='Gaila:BAABNQAECoEkAAMLAAgKwCASIADXAgALAAgKQx8SIADXAgASAAYKPSGZEAAYAgAAAA==.Garathor:BAAANQABCgQIBQAAAA==.Garrosh:BAAANQABCgMIAwAAAA==.Garthoneeye:BAAANQADCgcIFQAAAA==.Gazreyna:BAAANQAECgMIBAAAAA==.',
Ge='Genryusai:BAAANQAECgQIBAAAAA==.Genós:BAAANQAECgYIEgAAAA==.Gerardo:BAAANQAECgQICAAAAA==.',
Gi='Gigarawr:BAAANQAECgIIAwABNQAECgYJCQABAAAAAA==.Ginnee:BAAANQAECgUICgAAAA==.',
Gl='Glakattack:BAABNQAECoEdAAIGAAcKSQk13AB9AQAGAAcKSQk13AB9AQAAAA==.Glein:BAABNQAECoEXAAIHAAgKpyKlJgD0AgAHAAgKpyKlJgD0AgAAAA==.Gleivoker:BAAANQAECgMJAwABNQAECggIFwAHAKciAA==.',
Gn='Gnomeisbis:BAAANQADCggICAAAAA==.',
Go='Gongfu:BAAANQADCgEIAQAAAA==.Gooeyquiver:BAAANQADCgMIBQAAAA==.',
Gr='Graestoke:BAAANQAECgIIBAABNQAECgkJGwAcAAwfAA==.Granthar:BAAANQADCgUIBQAAAA==.Greasermorty:BAAANQADCgMIAwAAAA==.Grimixtalis:BAAANQADCgcIBwAAAA==.Growls:BAAANQAECgYIEQAAAA==.Grundlegnome:BAAANQAECgcIDQABNQAECgkJLQARAOsgAA==.',
Gu='Gurri:BAAANQAECgUIBwAAAA==.',
['Gõ']='Gõldenchild:BAAANQAECgIIAgAAAA==.',
Ha='Habenero:BAAANQAECgEJAQAAAA==.Hairypitts:BAAANQAECgUIDQAAAA==.Happychaos:BAAANQAECgQIBAAAAA==.Haraniantha:BAABNQAECoEWAAIIAAcKRSDFCQBBAgAIAAcKRSDFCQBBAgAAAA==.Hatean:BAAANQAECgIIAgAAAA==.Hathor:BAAANQAECgQICwAAAA==.Hazzbek:BAAANQADCgcIDwAAAA==.',
He='Heiboss:BAAANQAECgIIAgABNQAECggIGAAaAFQkAA==.Heibub:BAAANQAECgEIAQABNQAECggIGAAaAFQkAA==.Heiranir:BAAANQAECgUIDAABNQAECggIGAAaAFQkAA==.Heiretic:BAAANQAECgUICQABNQAECggIGAAaAFQkAA==.Heithyr:BAAANQADCgMIBAABNQAECggIGAAaAFQkAA==.Helos:BAAANQADCgcICgAAAA==.Hemit:BAAANQAECgQIBAABNQAECgkJGwAcAAwfAA==.',
Hi='Hikikomori:BAAANQAECgEIAQABNQAECgcIMAAaAKAkAA==.Hildegarde:BAAANQAECgYIEgAAAA==.Himura:BAAANQAECggICAAAAA==.Hinomiko:BAAANQAECgUIBwAAAA==.',
Ho='Holycowch:BAAANQADCgEIAQAAAA==.Hootiedixon:BAAANQADCgIIAgAAAA==.Hotdog:BAAANQAECgUIBQABNQAECgkJIAAGAOsYAA==.',
Hu='Huran:BAABNQAECoEYAAIaAAgKVCSoCgBBAwAaAAgKVCSoCgBBAwAAAA==.',
Hx='Hx:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.',
Ia='Iatemydad:BAAANQAECgYIDgAAAA==.',
Ic='Icéehawt:BAEANQAECgQIBwABNQADCgUIBQABAAAAAA==.',
Ig='Ignignokt:BAEBNQAECoEaAAMMAAgKOSUbFQAcAwAMAAgKOSUbFQAcAwAdAAMKURRTRwC9AAAAAA==.',
Im='Imagine:BAABNQAECoEXAAIeAAgKmCMYEAAbAwAeAAgKmCMYEAAbAwAAAA==.',
In='Inarush:BAABNQAECoEZAAIfAAcKCwo/EQA2AQAfAAcKCwo/EQA2AQAAAA==.',
Ir='Ironshield:BAAANQADCggJCAABNQAECgkJIwALAG0YAA==.',
Iw='Iwishiknew:BAAANQAECgUIDQAAAA==.',
Iz='Iztras:BAAANQADCgEIAQAAAA==.',
Ja='Jabbtrak:BAAANQAECgYIEgAAAA==.Jabttrak:BAAANQAECgMIAwAAAA==.Jacklowry:BAAANQAECgUICgAAAA==.Jakiepoobear:BAABNQAECoEeAAIdAAgKxhfpGgBGAgAdAAgKxhfpGgBGAgAAAA==.Jalador:BAAANQADCggICAAAAA==.Jambie:BAAANQAECgcIEAAAAA==.',
Je='Jedery:BAAANQAECgUICAAAAA==.',
Ji='Jivepepper:BAAANQADCggIDwAAAA==.',
Jo='Jolynn:BAAANQAECgcIBwAAAA==.Joroldess:BAAANQAECgYIEgAAAA==.Joyo:BAAANQADCgUIDAAAAA==.',
Ju='Juzam:BAAANQADCgYIDQAAAA==.',
Ka='Kahghär:BAAANQAECgUICgABNQAFFAUIDgAgAA4WAA==.Kahlly:BAAANQAECgQICgAAAA==.Kahndumb:BAAANQAECgIIAgAAAA==.Kaida:BAAANQAECgMIBAAAAA==.Kaio:BAAANQAECgYICwAAAA==.Kalahan:BAAANQAECgIIAwAAAA==.Kaotut:BAAANQADCgQIAwAAAA==.Kardrion:BAAANQAECgEJAQAAAA==.Karigyn:BAAANQAECgUICwAAAA==.Kaskaa:BAAANQADCggIDAAAAA==.Katelina:BAAANQAECgQICQAAAA==.Katren:BAAANQADCgMIAwAAAA==.Katrienne:BAAANQAECgUICwAAAA==.Katrya:BAAANQABCgQIBAABNQAECgUICwABAAAAAA==.Kaylid:BAAANQAECgYICwAAAA==.Kazzoth:BAAANQAECgYIEQAAAA==.',
Ke='Keilen:BAAANQADCgQIAwAAAA==.Keiyo:BAAANQADCggIFgAAAA==.Ketsuana:BAAANQADCgcIBwABNQAECgQIDAABAAAAAA==.Ketsukusai:BAAANQADCggJDwAAAA==.',
Kh='Khally:BAAANQADCgcIBwAAAA==.',
Ki='Kilen:BAAANQABCgUICQAAAA==.Kilimanjaro:BAAANQADCgcIDwAAAA==.Killjôy:BAAANQADCgIIAgAAAA==.Kimjongboom:BAABNQAECoEdAAIWAAkKbCRGCAB5AwAWAAkKbCRGCAB5AwAAAA==.',
Kl='Klax:BAAANQADCgcJDAAAAA==.Klondor:BAAANQAECgMIAwAAAA==.Klz:BAAANQADCggJDQAAAA==.Klzx:BAAANQAECgQIBwAAAA==.',
Ko='Komo:BAABNQAECoEeAAMJAAkKRiEQDQA/AwAJAAkKRiEQDQA/AwAKAAEKySFtWQBhAAAAAA==.Konokusotare:BAAANQAECgQIBQAAAA==.Korbi:BAAANQADCgYICgABNQAECgYIEQABAAAAAA==.Korbs:BAAANQAECgcIEgAAAA==.Kortek:BAAANQADCgUIBQAAAA==.Korvold:BAABNQAECoEYAAIOAAcKehkGYQAiAgAOAAcKehkGYQAiAgAAAA==.',
Kr='Krak:BAAANQABCgYICAAAAA==.Kralkor:BAAANQADCgQIAwAAAA==.Kreckon:BAAANQAECgIIAgAAAA==.Kronn:BAAANQAECgUICgABNQAECgYIDQABAAAAAA==.',
Ks='Kschnell:BAAANQADCgQIBQABNQAECgkJKwAGAOwhAA==.',
Ku='Kukulkan:BAAANQAECgQIDQAAAA==.Kuulan:BAAANQAECgYIEgAAAA==.',
Ky='Kythra:BAAANQAECgEIAQAAAA==.',
La='Lanstin:BAAANQADCgUIBgAAAA==.',
Le='Leafpool:BAAANQADCgYIBgAAAA==.Leancuisine:BAAANQAECgEIAQAAAA==.Leetlebug:BAAANQADCgcIBwAAAA==.Leofull:BAAANQAECgMIBQAAAA==.Lettÿ:BAAANQAECgQICAAAAA==.Lexapro:BAAANQAECgEJAQAAAA==.',
Li='Lickemraw:BAAANQADCgQIBAAAAA==.Lightzwrath:BAAANQAECgYICwAAAA==.Lilithphage:BAAANQAECgIIAgAAAA==.Lilstorm:BAAANQADCgMIAwAAAA==.Littlenewt:BAAANQADCgYIBgAAAA==.',
Lo='Lockbealady:BAAANQADCgYIBgAAAA==.Lorebeard:BAAANQAECgEIAQAAAA==.Loreix:BAAANQAECgUICQAAAA==.Loreous:BAAANQADCgUIBQABNQAECgYIDQABAAAAAA==.',
Lu='Luther:BAAANQADCgQIBQABNQAECgYIEgABAAAAAA==.Luvinez:BAAANQADCggIEAAAAA==.Luvinz:BAAANQAECgQICAAAAA==.Luxuria:BAAANQAECgQJBAAAAA==.',
Ly='Lycanhunter:BAAANQAECgQICAAAAA==.Lycansham:BAAANQAECgEIAQAAAA==.Lyse:BAEANQAECgIIAgAAAA==.',
Ma='Maarc:BAAANQAECgMIBQAAAA==.Machantu:BAAANQADCggIDgAAAA==.Madfurion:BAAANQAECgQICAAAAA==.Magebot:BAAANQAECgUIEgAAAA==.Maggotbag:BAAANQADCgYICgAAAA==.Magicmandan:BAAANQADCgUIBQAAAA==.Magikstik:BAAANQAECgUJCAAAAA==.Mahgrim:BAAANQADCgMIAwAAAA==.Majestic:BAABNQAECoErAAIGAAkK7CHmHABQAwAGAAkK7CHmHABQAwAAAA==.Maliná:BAAANQADCgEIAQABNQADCgYIHQABAAAAAA==.Malvenue:BAAANQADCgMIBAAAAA==.Marchesa:BAAANQADCgcIBwAAAA==.Markdashaman:BAAANQADCgIIAgAAAA==.Mauwy:BAABNQAECoEYAAMLAAgKnRTYTQDwAQALAAcKaBbYTQDwAQAeAAMKLwanxgCGAAAAAA==.',
Mc='Mcbullseye:BAAANQAECgUIBQAAAA==.',
Me='Megarah:BAAANQADCgYJFgAAAA==.Mepkaelpto:BAAANQADCgYIBgAAAA==.Meretrix:BAAANQAECgUICgAAAA==.Mersadie:BAAANQAECgUIDAAAAA==.Metanya:BAAANQAECgQIBAAAAA==.Mew:BAAANQAECgQIBQAAAA==.',
Mi='Miateh:BAAANQADCggIGgAAAA==.Mimicme:BAABNQAECoEYAAIMAAgKCCC1IgDUAgAMAAgKCCC1IgDUAgAAAA==.Mirajanê:BAAANQAECgMIBAAAAA==.Mitchell:BAAANQAECgUICgAAAA==.Miwah:BAAANQAECgQIDAAAAA==.Mizzheals:BAAANQAECgUIEQAAAA==.',
Mo='Mogarr:BAAANQADCgcICwAAAA==.Monkhei:BAAANQADCgEIAQABNQAECggIGAAaAFQkAA==.Moocifer:BAABNQAECoEbAAIHAAgKRhEtegDVAQAHAAgKRhEtegDVAQAAAA==.Mooglewing:BAAANQAECgIIAwAAAA==.Moomoobrncow:BAAANQAECgMIAwAAAA==.Mooriahdairy:BAAANQAECgQIBAAAAA==.Moorrigån:BAAANQADCgIIAgAAAA==.Mordicanta:BAAANQAECgUIDAAAAA==.Morgannon:BAAANQADCgUIBQAAAA==.Morphies:BAAANQADCgEIAQAAAA==.',
Mu='Muerr:BAABNQAECoEXAAIMAAgKxiLAFQAYAwAMAAgKxiLAFQAYAwAAAA==.Muerrizond:BAAANQADCgcIDQABNQAECggIFwAMAMYiAA==.Muggel:BAAANQADCggIFQAAAA==.Mumraa:BAAANQAECgIIAgAAAA==.Mushroohead:BAAANQAECgQICwAAAA==.',
My='Mysterbyrnes:BAAANQADCgYIBwAAAA==.Myykiel:BAAANQAECgUICAAAAA==.',
Na='Naina:BAAANQAECgQICAAAAA==.Najaja:BAAANQAECgMIBAAAAA==.Namii:BAAANQAECgUICAAAAA==.Narsum:BAAANQADCgYIBgAAAA==.Natacha:BAAANQAECgEIAgAAAA==.Navadurga:BAAANQAECggIDgAAAA==.',
Ne='Necro:BAABNQAECoEwAAIaAAcKoCQmEwDpAgAaAAcKoCQmEwDpAgAAAA==.Nedrali:BAAANQADCgcIBwABNQAECggIGAALAJ0UAA==.Nedrina:BAAANQADCgcIBwABNQAECggIGAALAJ0UAA==.Netrath:BAAANQAECgIIAgAAAA==.',
Ni='Nidom:BAAANQAECgIIAgAAAA==.Nighammer:BAAANQAECgQIBgAAAA==.Nimeesha:BAAANQADCgMJAwAAAA==.Ninmah:BAAANQADCggIEAAAAA==.Nirø:BAAANQAECgIIAwAAAA==.',
No='Nooki:BAAANQAECgYIDQAAAA==.Notgretuh:BAAANQAECgcIDgAAAA==.',
Ny='Nyrikah:BAAANQADCgcIFwAAAA==.',
Ob='Obidiah:BAAANQAECgUICwAAAA==.',
Od='Oddearth:BAAANQAECgEIAQAAAA==.',
Om='Omegablivet:BAAANQADCgMJAwAAAA==.',
Or='Orah:BAAANQADCgQIBQAAAA==.',
Pa='Palagem:BAAANQAECgQICgAAAA==.Palidingo:BAAANQADCgEIAQAAAA==.Palinyes:BAAANQAECgUICgAAAA==.Pandabutz:BAAANQAECgUIBwAAAA==.Pandahands:BAAANQADCgIIAgAAAA==.Panduh:BAAANQAECgUICAAAAA==.Pandussy:BAAANQAECgcIBwAAAA==.Papabill:BAABNQAECoEgAAIHAAcKaAe8sgBGAQAHAAcKaAe8sgBGAQAAAA==.Papaharny:BAAANQAECgYIDwABNQAECgcIIAAHAGgHAA==.Paragorn:BAAANQAECgMIBgAAAA==.Pattee:BAAANQAECgMIBgAAAA==.',
Pe='Pech:BAAANQAECgEIAgABNQAECgYJCQABAAAAAA==.Pechay:BAAANQADCgIJBAABNQAECgYJCQABAAAAAA==.Peenidin:BAAANQAECgYIEQAAAA==.Peepo:BAABNQAECoEtAAIRAAkK6yAEBQBdAwARAAkK6yAEBQBdAwAAAA==.Pemerd:BAAANQAECgUIDwAAAA==.',
Ph='Phoze:BAAANQAECgQICQAAAA==.Phozzack:BAAANQADCgcIDgAAAA==.Phyai:BAAANQAECgQICgAAAA==.',
Pl='Pliny:BAABNQAECoEjAAILAAkKbRhSLgCDAgALAAkKbRhSLgCDAgAAAA==.',
Pn='Pnutt:BAAANQAECgEIAQAAAA==.',
Po='Pocahauntas:BAAANQAECgIIAgAAAA==.Porphyriia:BAAANQADCggICAAAAA==.',
Pr='Priestglein:BAAANQADCgUIBQABNQAECggIFwAHAKciAA==.Promethyus:BAAANQADCgcIDQAAAA==.Promidan:BAAANQAECgQIBgABNQADCggIDAABAAAAAA==.Prymus:BAABNQAECoEaAAIbAAgKYB+vCgCxAgAbAAgKYB+vCgCxAgAAAA==.Pryxi:BAAANQAECgUIEAAAAA==.',
Pu='Punkalicious:BAAANQAECgUIBwAAAA==.',
Py='Pyrogar:BAAANQADCgYIBgAAAA==.Pythius:BAAANQAECgQIBgAAAA==.',
['Pó']='Pótatò:BAAANQAECgIIAgAAAA==.',
Qu='Quetip:BAAANQADCgMIAwAAAA==.Quiksylver:BAABNQAECoEZAAMUAAcKwRkgQgAcAgAUAAcKwRkgQgAcAgAHAAMKRhAfAwGlAAAAAA==.',
Ra='Rakael:BAAANQADCgcIBwAAAA==.Ratshot:BAABNQAECoErAAIMAAkKhBreGwD1AgAMAAkKhBreGwD1AgABNQAECgkJMgAhAP4iAA==.Rawty:BAAANQADCgUICQAAAA==.',
Re='Red:BAAANQAECgYIDwAAAA==.Relgul:BAAANQADCgYICwAAAA==.Rellster:BAABNQAECoEdAAMOAAgKehLGaQAIAgAOAAgKehLGaQAIAgAiAAEKFAtlKAAzAAAAAA==.Renix:BAAANQADCgUIBQAAAA==.Rennyo:BAAANQAECgYIEQAAAA==.Resonance:BAAANQADCggJFwAAAA==.Rexion:BAAANQAECgQICQAAAA==.',
Ri='Rigg:BAAANQADCggICgAAAA==.Riggsy:BAAANQAECgUICwABNQADCggICgABAAAAAA==.Riggzbuffs:BAAANQADCgYICwABNQADCggICgABAAAAAA==.Rivenp:BAAANQADCgYIEgAAAA==.',
Ro='Rocknroll:BAABNQAECoEVAAIMAAcKDRcFYAADAgAMAAcKDRcFYAADAgAAAA==.Rokbiter:BAAANQAECgIIAgAAAA==.Roll:BAAANQAFFAMIAwAAAA==.Rothound:BAAANQAECgQIBgAAAA==.Rozgrez:BAAANQAECgUICwAAAA==.',
Ru='Runefflck:BAAANQAECgcIEwAAAA==.Russbus:BAABNQAECoEbAAIHAAkK4xjVVgA/AgAHAAkK4xjVVgA/AgAAAA==.',
Ry='Rynari:BAAANQADCgUIBQABNQAECgcIGQANAI8OAA==.Rynmorelle:BAABNQAECoEZAAINAAcKjw44TAB9AQANAAcKjw44TAB9AQAAAA==.',
['Ré']='Réven:BAAANQAECgYIEgAAAA==.',
['Rí']='Rínoah:BAAANQADCgUICAAAAA==.',
['Rô']='Rôckbôttôm:BAAANQAECgUJBQAAAA==.',
Sa='Sakura:BAAANQAECgcIEwAAAA==.Sane:BAAANQAECgcIEQAAAA==.Saoiirse:BAAANQAECgMIBAAAAA==.',
Se='Searshaa:BAAANQADCgcIBwAAAA==.Seershaa:BAAANQADCgYIBgAAAA==.Seriux:BAAANQADCgUIBQAAAA==.Sevencharlie:BAAANQAECgMIAwAAAA==.',
Sh='Shadowfate:BAAANQAECgcIDgAAAA==.Shadê:BAAANQADCgYIBgAAAA==.Shamanyou:BAAANQADCgEIAQAAAA==.Shamiqua:BAAANQAECgUICAAAAA==.Shamutty:BAAANQADCgQIBAABNQAECgkJGwAcAAwfAA==.Shentao:BAAANQAECgYIEAAAAA==.Shinjô:BAAANQAECgcIBwAAAA==.Shirikao:BAAANQADCgYIBgAAAA==.Shiroishi:BAAANQAECgQIBwAAAA==.Shivaray:BAAANQAECgQJBAAAAA==.Shocklesner:BAAANQAECgUICAAAAA==.Shomade:BAAANQADCgQIBwAAAA==.Shouganai:BAAANQAECgIIAwAAAA==.Shupaz:BAAANQAECgIIAwAAAA==.',
Si='Sifu:BAAANQAECgUIBQAAAA==.Silverlight:BAAANQAECgUICAAAAA==.Simp:BAAANQADCgQIBAAAAA==.Sinaar:BAAANQADCgQIBAAAAA==.Sindena:BAAANQAECgQIBAAAAA==.',
Sk='Skyemage:BAAANQADCggIFAAAAA==.',
Sl='Sloked:BAAANQAECgYIDQAAAA==.Slokep:BAAANQADCgQIBAAAAA==.Slokes:BAAANQADCgIIAgAAAA==.Slotz:BAAANQAECgUICwAAAA==.',
Sm='Smitepanda:BAAANQADCgcICAAAAA==.',
Sn='Sneeze:BAAANQADCgcIFQAAAA==.Snekashifty:BAAANQAECgMIAwAAAA==.Snowsham:BAAANQADCgUJBQAAAA==.',
So='Sonarr:BAAANQAECgMIAwAAAA==.Sozzle:BAAANQADCgUIBQABNQAECgkJKwAGAOwhAA==.',
Sp='Spark:BAAANQAECgQIBQAAAA==.Spicymeat:BAAANQAECgcJEgABNQAECgkJKwAGAOwhAA==.Sputty:BAABNQAECoEbAAIcAAkKDB/iCgAOAwAcAAkKDB/iCgAOAwAAAA==.',
Sq='Squanto:BAAANQAECgYICAABNQAECgkJKwAGAOwhAA==.',
St='Stalken:BAAANQADCgYJCwAAAA==.Stesha:BAAANQAECgUIDwAAAA==.Stonedfrog:BAAANQADCgcIFwAAAA==.Stïtches:BAAANQAECgUICQAAAA==.Stönk:BAAANQAECgMIBAAAAA==.',
Su='Sugarlumps:BAAANQADCgEIAQAAAA==.Superdaman:BAAANQADCgEIAQAAAA==.',
Sw='Swaggles:BAAANQAECgUICgAAAA==.',
Sy='Sygon:BAAANQAECgUIDAAAAA==.Sylm:BAAANQAECgQIBAABNQAECgkJLQALABghAA==.Symbr:BAAANQAECgYICQAAAA==.Synglace:BAAANQAECgEIAQAAAA==.Syntherizena:BAAANQADCgcIBwAAAA==.',
Ta='Tacitus:BAAANQAECgUICwAAAA==.Tairrad:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.Takara:BAAANQADCgUIBQAAAA==.Takeru:BAAANQAECgUIDQAAAA==.Talasmar:BAAANQADCgMIAwAAAA==.Taliessin:BAAANQADCgUJBgAAAA==.Talistian:BAAANQADCgIIAgAAAA==.Tarirn:BAAANQADCgYICwAAAA==.Tauntsinpvp:BAAANQAECgQIBQAAAA==.Taylia:BAAANQADCgYJBgABNQAECggIFwATABIbAA==.Tazwomann:BAAANQADCgIIAgAAAA==.',
Te='Teaqo:BAAANQADCgUIBQABNQAECgcIGQAZAGYZAA==.Telinda:BAAANQABCgIIAgAAAA==.Tempestrasza:BAAANQADCgcICwAAAA==.Tendonitis:BAAANQABCgQIBAAAAA==.Teppe:BAAANQAECgYICgAAAA==.Terial:BAAANQAECgQICAAAAA==.Terranovian:BAAANQAECgIIAgAAAA==.',
Th='Thajeebus:BAAANQAECgQIEQAAAA==.Thebigstein:BAAANQAECggIDgAAAA==.Thecapt:BAABNQAECoEeAAIiAAgK1hIHCAAYAgAiAAgK1hIHCAAYAgAAAA==.Theôdöræ:BAAANQAECgIIAwAAAA==.',
Ti='Tiaoma:BAAANQADCggIDgAAAA==.Tinylock:BAAANQADCgUICQAAAA==.Tinymich:BAAANQADCgUIBwABNQAECgYIEQABAAAAAA==.',
Tj='Tjhookèr:BAAANQAECgEIAQAAAA==.',
To='Toetoms:BAAANQAECgMIAwAAAA==.Toletheus:BAABNQAECoEXAAIZAAgKwCTrAgBVAwAZAAgKwCTrAgBVAwAAAA==.Tomin:BAAANQADCgIIAgAAAA==.Toreshii:BAAANQADCgUICQAAAA==.Totemique:BAAANQAECgQIBAABNQAECgYIEQABAAAAAA==.Totumfknpole:BAAANQADCgMIAwAAAA==.',
Tr='Trashkantz:BAAANQAECgQICAABNQAFFAYIEQAGAD4jAA==.Treeperson:BAAANQAECgUICwAAAA==.Trickyric:BAAANQAECgYIEgAAAA==.Trinak:BAAANQADCgQICAAAAA==.Trowel:BAAANQAECgQIBAABNQAECgkJGwAcAAwfAA==.',
Ts='Tsuyoimono:BAAANQAECgQIBgABNQAECgUIBwABAAAAAA==.',
Tu='Turtleclap:BAAANQAECgMIAwAAAA==.',
Tw='Twistandgrip:BAABNQAECoEfAAINAAgKPRFuPQDFAQANAAgKPRFuPQDFAQAAAA==.',
Ty='Tydroin:BAAANQADCgUIBQAAAA==.Tyinthor:BAAANQAECgMIBgAAAA==.Tytoalba:BAAANQAECgcIDgAAAA==.',
Un='Unholylean:BAAANQAECgIIAgAAAA==.',
Ur='Uratsukasama:BAAANQAECgQIBQAAAA==.Urza:BAAANQAECgcICgAAAA==.',
Va='Vacaite:BAAANQADCgcIBwAAAA==.Vagiant:BAABNQAECoEbAAIYAAgKaRRlCgAnAgAYAAgKaRRlCgAnAgAAAA==.Vangers:BAAANQABCgMIAwAAAA==.Vangie:BAAANQADCggIEAAAAA==.Vangnaw:BAAANQADCggICAAAAA==.Vanya:BAAANQAECgUIBgAAAA==.Vasso:BAAANQADCgYJFgAAAA==.Vayln:BAAANQAECgcIDQAAAA==.',
Ve='Veildreya:BAAANQABCgQIBAAAAA==.Veinygamer:BAABNQAECoEdAAIOAAgKPR0PVABMAgAOAAgKPR0PVABMAgAAAA==.Veldian:BAAANQAECgYIEAAAAA==.Velveen:BAAANQAECgYIEQAAAA==.Vexahalia:BAABNQAECoEaAAQMAAgKRxNkYAACAgAMAAgKRxNkYAACAgAdAAUK5wTqSQCwAAAjAAIKzwsaDQB3AAAAAA==.',
Vi='Vicarious:BAAANQAECgcICgAAAA==.Viciouslump:BAAANQADCggICAAAAA==.Vilebloom:BAEANQAECgMIAwAAAA==.Vilewyrm:BAEANQADCgcIEgABNQAECgMIAwABAAAAAA==.Violetblade:BAAANQADCgQIBAAAAA==.Viridius:BAAANQAECgEIAgAAAA==.',
Vo='Voidmulan:BAEANQADCgUIBQAAAA==.Voluga:BAAANQAECgEIAgAAAA==.',
Vr='Vraak:BAAANQADCggIHAAAAA==.',
Wa='Wagguslight:BAAANQAECgQICAAAAA==.',
We='Werstshot:BAAANQADCggIEwAAAA==.',
Wh='Whateverdude:BAAANQAECgUICwAAAA==.',
Wi='Wicketlock:BAAANQAECgQIBAAAAA==.Wiickett:BAABNQAECoEdAAMCAAkKEA1KFADGAQACAAgKXg1KFADGAQAEAAUK2AI0MgC/AAAAAA==.Wildesel:BAAANQAECgQIAwAAAA==.Willaá:BAAANQAECgYIDwAAAA==.Wilson:BAAANQAECgYIEgAAAA==.Wizzpeaver:BAAANQADCgcIBwAAAA==.',
Wo='Wonderwizard:BAAANQADCgIIAgAAAA==.',
Wr='Wrathhoof:BAAANQAECgQIBQABNQAECgYICwABAAAAAA==.',
Xy='Xylias:BAAANQAECgQIBgAAAA==.',
['Xá']='Xánada:BAAANQADCggIDQABNQAECgEIAQABAAAAAA==.',
Yo='Yorril:BAAANQADCgUIBQAAAA==.',
Yu='Yucca:BAAANQAECgUIEQAAAA==.Yuda:BAAANQAECgQIBgABNQAECgkJHwAFAD4hAA==.Yukiteru:BAAANQAECgEIAQAAAA==.Yurito:BAAANQADCgYIBgAAAA==.',
Za='Zabrina:BAAANQADCgYIBgABNQAECgUIDwABAAAAAA==.Zachie:BAAANQAECgYIBgAAAA==.Zakutin:BAAANQAECgIIAwAAAA==.Zappybains:BAAANQAECgUICwAAAA==.Zarakii:BAAANQAECgIIAgAAAA==.',
Ze='Zekken:BAAANQADCgMIAwAAAA==.Zelaira:BAAANQADCgMIAwABNQAECgcIGQANAI8OAA==.',
Zi='Zigzagga:BAAANQADCgQIBAAAAA==.',
Zo='Zoinks:BAAANQADCgQIBQAAAA==.Zorandar:BAAANQAECgEIAQAAAA==.',
Zu='Zupaz:BAAANQADCgQIBAABNQAECgIIAwABAAAAAA==.',
Zy='Zylluz:BAAANQAECgYIEgAAAA==.',
['Äs']='Ästen:BAAANQAECgQIBQAAAA==.',
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
