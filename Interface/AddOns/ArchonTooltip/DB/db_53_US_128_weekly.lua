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

local lookup = {'Unknown-Unknown','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Mage-Arcane','Monk-Brewmaster','Paladin-Retribution','Shaman-Elemental','Hunter-BeastMastery','DeathKnight-Unholy','Warrior-Arms','Warrior-Protection','Rogue-Subtlety','Rogue-Assassination','Shaman-Enhancement','Paladin-Holy','Mage-Frost','Druid-Balance','Druid-Restoration','Druid-Feral','Druid-Guardian','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Hunter-Marksmanship','Rogue-Outlaw','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','Warrior-Fury',}
local provider = {region='US',realm='Kargath',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abracadabruh:BAAANQAECgYICwAAAA==.Absynthia:BAAANQAECgUICQAAAA==.',
Ac='Academe:BAAANQADCgYICQAAAA==.Accalon:BAAANQADCgYIBgAAAA==.',
Ad='Adérai:BAAANQAECgYICAAAAA==.',
Ae='Aellopus:BAAANQAECgIIBgAAAA==.Aero:BAAANQAECgQIBgAAAA==.',
Ag='Agròm:BAAANQADCgQIBAABNQADCgcICwABAAAAAA==.',
Ak='Akata:BAAANQADCgQIBQAAAA==.Akku:BAAANQADCgYIBwAAAA==.',
Al='Alanwake:BAABNQAECoEXAAQCAAgK1xaIDQA1AgACAAgKWhOIDQA1AgADAAMKWhdXDwC6AAAEAAMKGQP6MwBqAAAAAA==.Aldourolf:BAAANQABCgQIBAAAAA==.Alomeo:BAEANQADCgYJCwAAAA==.Alphasmash:BAAANQAECgIJAgAAAA==.',
Am='Amiliane:BAAANQAECgMIBQAAAA==.Amilmean:BAAANQAECgEJAQAAAA==.Amoradine:BAAANQADCgcIDAAAAA==.Amz:BAAANQAECgEIAQAAAA==.',
An='Anadrien:BAAANQAECgQICQAAAA==.Ancelagon:BAAANQADCgYIBwAAAA==.Andrae:BAAANQADCgUIFwAAAA==.Angrimia:BAAANQAECgQIBgAAAA==.Annussa:BAAANQAECgEIAQAAAA==.',
Ar='Arboria:BAAANQAECgcIAgAAAA==.Ardbeg:BAAANQABCgYICgAAAA==.Arduin:BAAANQAECgUICAAAAA==.Aremethea:BAAANQAECgMJBAAAAA==.Aronk:BAAANQADCggIHAABNQAECgMIBgABAAAAAA==.Arore:BAAANQADCgMJBQABNQAECgMIBgABAAAAAA==.Aroreck:BAAANQADCgQIBAABNQAECgMIBgABAAAAAA==.Articulaté:BAAANQAECgcIDgAAAA==.',
As='Asbjorn:BAAANQADCggIGAAAAA==.',
At='Attack:BAAANQADCgQJBAABNQAECgkJJQAFABchAA==.',
Av='Avestara:BAAANQAECgQIBgAAAA==.',
Ay='Ayohec:BAAANQADCgQIBAAAAA==.',
Az='Azoril:BAAANQAECgYIEQAAAA==.Azùla:BAAANQAECgIIAgAAAA==.',
['Aí']='Aídeen:BAAANQAECgQICAAAAA==.',
Ba='Babs:BAAANQADCgEJAQAAAA==.Badmooddude:BAAANQAECgEJAQAAAA==.Baelnorn:BAAANQAECgYIEAAAAA==.Bains:BAAANQADCgcIBwAAAA==.Barrex:BAAANQAECgEIAQAAAA==.Basken:BAAANQAECgUJCQAAAA==.Batôsai:BAAANQAECgEIAQAAAA==.',
Be='Beardiso:BAAANQAECgYIBgAAAA==.Beastcleave:BAAANQADCggICAAAAA==.Beelz:BAAANQAECgUJBgAAAA==.Bekens:BAAANQADCgQIAwAAAA==.Belaraariaae:BAAANQADCggIDQABNQAECgcJFgAGAEUgAA==.Benipal:BAABNQAECoElAAIHAAkKTBwgJgDKAgAHAAkKTBwgJgDKAgAAAA==.Bernardboggs:BAAANQAECgUIDAAAAA==.',
Bh='Bheefknight:BAAANQAECgYJDgAAAA==.Bheeftotemz:BAAANQADCgUICQAAAA==.',
Bi='Bierbro:BAAANQAECgcIEgAAAA==.Bigsofty:BAAANQAECgIIAgAAAA==.Billiam:BAAANQADCggICAAAAA==.Billié:BAAANQAECgYIEQABNQAECggJHAAIAOkdAA==.',
Bl='Blightheaded:BAAANQADCgYIBgAAAA==.Blumir:BAAANQAECgcJCQAAAA==.',
Bo='Bomgan:BAAANQAECgQIBQAAAA==.Bonchonn:BAABNQAECoEcAAIJAAkKwyNHBgCFAwAJAAkKwyNHBgCFAwAAAA==.Bonkula:BAAANQAECgEJAQAAAA==.Bops:BAAANQADCggIDQAAAA==.Borque:BAAANQAECgUJCwAAAA==.Bosenmorimei:BAAANQADCgIIAgAAAA==.',
Br='Brae:BAAANQAECgMJBAAAAA==.Brazonk:BAAANQAECgEJAgAAAA==.Brewzco:BAABNQAECoEWAAIGAAcKPB+KBgB9AgAGAAcKPB+KBgB9AgAAAA==.Briciferkong:BAABNQAECoEZAAIKAAkK9yR0BACdAwAKAAkK9yR0BACdAwAAAA==.Brickedup:BAAANQAECgEIAQAAAA==.Brightblayde:BAAANQAECgQICQAAAA==.',
Bu='Buanto:BAAANQADCggJFwAAAA==.Bubblegumm:BAAANQADCgUJBQAAAA==.Bubbletea:BAAANQAECgMIBQABNQADCgUJBQABAAAAAA==.Butterball:BAABNQAECoEWAAMLAAgKBhmoUQAlAgALAAcKehuoUQAlAgAMAAIKPQeSJgBYAAAAAA==.',
Ca='Candlelock:BAAANQAECgEIAQAAAA==.Candlewic:BAAANQADCggJEgAAAA==.Cathal:BAAANQABCgYICAAAAA==.Cattroll:BAAANQAECgEJAgABNQAECgUJDAABAAAAAA==.',
Ce='Celithila:BAAANQAECgMIBQAAAA==.Celithvia:BAAANQAECgEJAgAAAA==.Cervantés:BAABNQAECoEUAAMNAAcKQhe+JwAxAQANAAQKtRa+JwAxAQAOAAMK/xd3PgDxAAAAAA==.',
Ch='Chaosknight:BAAANQAECgMIAwAAAA==.Charginatyou:BAAANQADCggIDwABNQAECggIHQAPAMgQAA==.Charla:BAAANQADCgUIBwABNQADCgYJBgABAAAAAA==.Chelsea:BAAANQADCgIIAgAAAA==.Chise:BAAANQAECgYJDwAAAA==.Chiza:BAAANQADCgMIAwAAAA==.Chob:BAAANQADCgcICwAAAA==.',
Cl='Clarry:BAAANQADCgYIDAAAAA==.Clyde:BAAANQAECgEIAQAAAA==.Clydk:BAAANQAECgEJAQAAAA==.',
Co='Coachbeard:BAABNQAECoEYAAIQAAgK+hTlNQAjAgAQAAgK+hTlNQAjAgAAAA==.Colzaratha:BAAANQAECgQICwAAAA==.Coorsbanquet:BAAANQAECgUJCQAAAA==.Corian:BAAANQADCgQIBAAAAA==.Corndog:BAABNQAECoEXAAMFAAkKIBficABAAgAFAAgKWBXicABAAgARAAIK3hw6HACdAAAAAA==.Corpsereth:BAAANQADCggICAAAAA==.Cozzworth:BAAANQADCgEIAQAAAA==.',
Cu='Cudguzzler:BAAANQAECgIIAgAAAA==.Cursegoesmoo:BAAANQAECgUIBwAAAA==.Cursehoots:BAABNQAECoEdAAISAAkK2yHdCABiAwASAAkK2yHdCABiAwAAAA==.',
Cy='Cyntheria:BAAANQAECgYJDwAAAA==.',
Da='Daddybeàr:BAABNQAECoEdAAUTAAkKbBrvCQDPAgATAAkKbBrvCQDPAgAUAAQKXxaGFAD6AAAVAAIK3hLLJwB0AAASAAEKdhEcfQA/AAAAAA==.Daendron:BAAANQAECgYIBgAAAA==.Darksaxon:BAAANQAECgMIAwAAAA==.Darorek:BAAANQAECgMIBgAAAA==.',
De='Deathnethal:BAAANQADCgYIBgAAAA==.Deathweaver:BAABNQAECoEYAAMNAAkKPB/VBAAmAwANAAgKDiPVBAAmAwAOAAIKohACVQBnAAAAAA==.Debumanko:BAAANQADCggIDgAAAA==.Decima:BAAANQADCgUICQAAAA==.Deeneye:BAAANQADCgUICgABNQAECgEJAgABAAAAAA==.Delerai:BAAANQADCggICAAAAA==.Dellgado:BAAANQABCgMIBQAAAA==.Deme:BAAANQAECgQJBQAAAA==.Demonbains:BAAANQAECgEIAQAAAA==.Demonica:BAAANQAECgMIAwAAAA==.Demonscythe:BAAANQADCgcIEQAAAA==.Dendrax:BAAANQAECgQICAAAAA==.Dented:BAAANQABCgQIBAAAAA==.Deviance:BAAANQAECgEJAQAAAA==.Dezwar:BAAANQADCgEIAQABNQAFFAUJCAARAFogAA==.',
Di='Dissonance:BAAANQADCgUJBQAAAA==.',
Dj='Djanga:BAAANQADCgYIBgABNQAECgQJBwABAAAAAA==.Djdazzle:BAAANQADCgYIBwAAAA==.',
Do='Dogbearcat:BAAANQADCgQIBAABNQAFFAIIAgABAAAAAA==.Dorito:BAAANQAFFAEIAQAAAA==.',
Dr='Dragooned:BAABNQAECoEcAAIRAAkKmSWHAACgAwARAAkKmSWHAACgAwAAAA==.Drahhrak:BAAANQADCgQJBAAAAA==.Drango:BAAANQAECgUJBwAAAA==.Draugdae:BAAANQAECgMIBAAAAA==.Draxtor:BAAANQADCgQJBAAAAA==.Drinksomuch:BAAANQAECgQJBgAAAA==.Drizzlin:BAAANQADCgYIBgAAAA==.Drleche:BAAANQADCgEIAQAAAA==.Drob:BAEANQAECgUJCAAAAA==.Drocket:BAEANQAECgUJBgAAAA==.Drome:BAAANQADCgcJCAABNQAECgMIBQABAAAAAA==.Drukhi:BAAANQAECgYIDwAAAA==.',
Du='Dudetotems:BAAANQAECgQIBwAAAA==.Dungrough:BAAANQADCgcIDQAAAA==.Durtkal:BAAANQAECgUJDQAAAA==.',
Dy='Dyonn:BAAANQAECgMJBAAAAA==.',
Ef='Efarel:BAAANQAECgYJEgAAAA==.Efdis:BAAANQADCgIIAgAAAA==.',
Ei='Eienarinna:BAAANQADCgYIBgAAAA==.Eilana:BAAANQAFFAIIAgAAAA==.Eilària:BAAANQADCgMIAwAAAA==.',
El='Elsa:BAAANQAECgYIEAAAAA==.',
Em='Emma:BAAANQADCggJDgAAAA==.',
En='Eneco:BAAANQAECggIEwAAAA==.Enserath:BAAANQADCgYICwAAAA==.',
Eu='Eurythmics:BAAANQAECgQIBQAAAA==.',
Ev='Evonahh:BAAANQADCgQIBAAAAA==.',
Ex='Exelion:BAAANQAECgYIEAAAAA==.Explogan:BAAANQAECgEIAQAAAA==.',
Ez='Ezanah:BAAANQADCgIIAgAAAA==.Ezrack:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
Fa='Faaith:BAAANQADCgcIFwAAAA==.Fahooquazaad:BAAANQADCgcIGgAAAA==.Fancie:BAAANQADCgEIAQABNQAECgYIDwABAAAAAA==.Fancy:BAAANQAECgYJDAAAAA==.',
Fe='Feetlesmcdee:BAAANQAECgMIBQAAAA==.Felfáádaern:BAAANQADCgEJAQAAAA==.Felporch:BAAANQAECgEJAQAAAA==.',
Fi='Fitzy:BAAANQAECgYIDwAAAA==.',
Fl='Flowermound:BAAANQADCgcJHQAAAA==.',
Fo='Fourqto:BAAANQAECgQIBQAAAA==.Fox:BAABNQAECoEdAAIWAAkKoSLJCgAwAwAWAAkKoSLJCgAwAwAAAA==.',
Fr='Freya:BAAANQADCgUIBQAAAA==.',
Fu='Fujikujaku:BAAANQAECgUJBgAAAA==.Fulmetal:BAAANQAECgYIDgAAAA==.Funji:BAAANQAECgQJBwAAAA==.Funkalicious:BAAANQAECgYIDQAAAA==.',
['Fé']='Félo:BAAANQAECgQICAAAAA==.',
Ga='Gaila:BAABNQAECoEcAAMIAAgK6R3DHgC4AgAIAAgK7xvDHgC4AgAPAAYKPSH7DAAtAgAAAA==.Garathor:BAAANQABCgQIBQAAAA==.Garrosh:BAAANQABCgMIAwAAAA==.Garthoneeye:BAAANQADCgYJFAAAAA==.Gazreyna:BAAANQAECgEIAgAAAA==.',
Ge='Genós:BAAANQAECgYIEAAAAA==.Gerardo:BAAANQAECgMJBAAAAA==.',
Gi='Gigarawr:BAAANQAECgEIAQABNQAECgYJCQABAAAAAA==.Ginnee:BAAANQAECgQJBQAAAA==.',
Gl='Glakattack:BAABNQAECoEYAAIFAAcK4Ah5vgCFAQAFAAcK4Ah5vgCFAQAAAA==.Glein:BAAANQAECgYJDQAAAA==.Gleivoker:BAAANQAECgMJAwABNQAECgYJDQABAAAAAA==.',
Gn='Gnomeisbis:BAAANQADCggICAAAAA==.',
Go='Gongfu:BAAANQADCgEIAQAAAA==.Gooeyquiver:BAAANQADCgMIBQAAAA==.',
Gr='Graestoke:BAAANQAECgIJAgABNQAECgkJGAAXAMgcAA==.Granthar:BAAANQADCgUIBQAAAA==.Greasermorty:BAAANQADCgMIAwAAAA==.Growls:BAAANQAECgUJCwAAAA==.Grundlegnome:BAAANQAECgcIDQABNQAECggIHAAOANUfAA==.',
Gu='Gurri:BAAANQAECgIIAgAAAA==.',
['Gõ']='Gõldenchild:BAAANQADCgcIGwAAAA==.',
Ha='Habenero:BAAANQAECgEJAQAAAA==.Hairypitts:BAAANQAECgUJCAAAAA==.Happychaos:BAAANQAECgQIBAAAAA==.Haraniantha:BAABNQAECoEWAAIGAAcKRSCjBwBYAgAGAAcKRSCjBwBYAgAAAA==.Hatean:BAAANQADCggIGAAAAA==.Hathor:BAAANQAECgQIBwAAAA==.Hazzbek:BAAANQADCgcIDwAAAA==.',
He='Heiboss:BAAANQAECgIIAgABNQAECgYIDwABAAAAAA==.Heibub:BAAANQADCgYICgABNQAECgYIDwABAAAAAA==.Heiranir:BAAANQAECgUICAABNQAECgYIDwABAAAAAA==.Heiretic:BAAANQAECgUICQABNQAECgYIDwABAAAAAA==.Heithyr:BAAANQADCgMJBAABNQAECgYIDwABAAAAAA==.Helos:BAAANQADCgcICgAAAA==.Hemit:BAAANQADCgUIBQABNQAECgkJGAAXAMgcAA==.',
Hi='Hikikomori:BAAANQAECgEIAQABNQAECgcIIgAYAGAjAA==.Hildegarde:BAAANQAECgUIDAAAAA==.Hinomiko:BAAANQAECgIIAgAAAA==.',
Ho='Holycowch:BAAANQADCgEIAQAAAA==.Hootiedixon:BAAANQADCgIIAgAAAA==.Hotdog:BAAANQAECgUIBQABNQAECgkJFwAFACAXAA==.',
Hu='Huran:BAAANQAECgYIDwAAAA==.',
Hx='Hx:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Ia='Iatemydad:BAAANQAECgUJCgAAAA==.',
Ic='Icéehawt:BAEANQAECgMIBgABNQADCgUIBQABAAAAAA==.',
Ig='Ignignokt:BAEBNQAECoEWAAIJAAgKOSVODQA6AwAJAAgKOSVODQA6AwAAAA==.',
Im='Imagine:BAAANQAECgYIDQAAAA==.',
In='Inarush:BAAANQAECgYJDwAAAA==.',
Ir='Ironshield:BAAANQADCggJCAABNQAECggIGQAIAEIYAA==.',
Iw='Iwishiknew:BAAANQAECgUICAAAAA==.',
Iz='Iztras:BAAANQADCgEIAQAAAA==.',
Ja='Jabbtrak:BAAANQAECgUJDAAAAA==.Jabttrak:BAAANQAECgEIAQAAAA==.Jacklowry:BAAANQAECgQJBQAAAA==.Jakiepoobear:BAABNQAECoEXAAIZAAgKpxNUHAARAgAZAAgKpxNUHAARAgAAAA==.Jalador:BAAANQADCggICAAAAA==.Jambie:BAAANQAECgYIDAAAAA==.',
Je='Jedery:BAAANQAECgMIAwAAAA==.',
Ji='Jivepepper:BAAANQADCggIDwAAAA==.',
Jo='Joroldess:BAAANQAECgYIEAAAAA==.Joyo:BAAANQADCgUIDAAAAA==.',
Ju='Juzam:BAAANQADCgIIAgAAAA==.',
Ka='Kahghär:BAAANQAECgQICQABNQAFFAUJCgAaAA4WAA==.Kahlly:BAAANQAECgMIBgAAAA==.Kahndumb:BAAANQAECgIIAgAAAA==.Kaida:BAAANQAECgMIBAAAAA==.Kaio:BAAANQAECgUICQAAAA==.Kalahan:BAAANQAECgEJAQAAAA==.Kaotut:BAAANQADCgQIAwAAAA==.Kardrion:BAAANQAECgEJAQAAAA==.Karigyn:BAAANQAECgQIBgAAAA==.Kaskaa:BAAANQADCggIDAAAAA==.Katelina:BAAANQAECgMJBQAAAA==.Katren:BAAANQADCgMIAwAAAA==.Katrienne:BAAANQAECgQIBgAAAA==.Katrya:BAAANQABCgQIBAABNQAECgQIBgABAAAAAA==.Kaylid:BAAANQAECgUJCQAAAA==.Kazzoth:BAAANQAECgYIDwAAAA==.',
Ke='Keilen:BAAANQADCgQIAwAAAA==.Keiyo:BAAANQADCggJEQAAAA==.Ketsuana:BAAANQADCgcIBwABNQAECgQJCwABAAAAAA==.Ketsukusai:BAAANQADCggJDwAAAA==.',
Ki='Kilen:BAAANQABCgUICQAAAA==.Kilimanjaro:BAAANQADCgcIDwAAAA==.Killjôy:BAAANQADCgIIAgAAAA==.Kimjongboom:BAABNQAECoEcAAISAAkKbCQ7BgCHAwASAAkKbCQ7BgCHAwAAAA==.',
Kl='Klax:BAAANQADCgcJDAAAAA==.Klondor:BAAANQAECgMIAwAAAA==.Klz:BAAANQADCggJDQAAAA==.Klzx:BAAANQAECgIIAwAAAA==.',
Ko='Komo:BAABNQAECoEcAAMbAAkKRiGYBwBZAwAbAAkKRiGYBwBZAwAcAAEKySGXUwBhAAAAAA==.Konokusotare:BAAANQAECgQIBQAAAA==.Korbi:BAAANQADCgYICgABNQAECgUJCwABAAAAAA==.Korbs:BAAANQAECgYJCwAAAA==.Kortek:BAAANQADCgUIBQAAAA==.Korvold:BAAANQAECgYJDwAAAA==.',
Kr='Krak:BAAANQABCgYICAAAAA==.Kralkor:BAAANQADCgQIAwAAAA==.Kreckon:BAAANQADCggIGgAAAA==.Kronn:BAAANQAECgUICgABNQAECgYIBgABAAAAAA==.',
Ks='Kschnell:BAAANQADCgQIBQABNQAECgkJJQAFABchAA==.',
Ku='Kukulkan:BAAANQAECgQICQAAAA==.Kuulan:BAAANQAECgYIEAAAAA==.',
Ky='Kythra:BAAANQAECgEIAQAAAA==.',
La='Lanstin:BAAANQADCgUIBgAAAA==.',
Le='Leafpool:BAAANQADCgYIBgAAAA==.Leancuisine:BAAANQADCgYIEQAAAA==.Leofull:BAAANQAECgIJAwAAAA==.Lettÿ:BAAANQAECgMJBAAAAA==.Lexapro:BAAANQAECgEJAQAAAA==.',
Li='Lickemraw:BAAANQADCgQIBAAAAA==.Lightzwrath:BAAANQAECgUJBQABNQAECgYIEAABAAAAAA==.Lilithphage:BAAANQADCgcJBwAAAA==.Lilstorm:BAAANQADCgMIAwAAAA==.Littlenewt:BAAANQADCgYIBgAAAA==.',
Lo='Lockbealady:BAAANQADCgYIBgAAAA==.Lorebeard:BAAANQADCgMJAwAAAA==.Loreix:BAAANQAECgQJBAAAAA==.Loreous:BAAANQADCgUIBQABNQAECgYIBgABAAAAAA==.',
Lu='Luther:BAAANQADCgQIBQABNQAECgUIDAABAAAAAA==.Luvinez:BAAANQADCggICAAAAA==.Luvinz:BAAANQAECgMJBAAAAA==.Luxuria:BAAANQAECgQJBAAAAA==.',
Ly='Lycanhunter:BAAANQAECgMIBAAAAA==.Lycansham:BAAANQAECgEIAQAAAA==.Lyse:BAEANQAECgIJAgAAAA==.',
Ma='Maarc:BAAANQAECgIJAgAAAA==.Machantu:BAAANQADCggIDgAAAA==.Madfurion:BAAANQAECgMIBAAAAA==.Magebot:BAAANQAECgUJDQAAAA==.Maggotbag:BAAANQADCgYICgAAAA==.Magikstik:BAAANQAECgUJCAAAAA==.Mahgrim:BAAANQADCgMIAwAAAA==.Majestic:BAABNQAECoElAAIFAAkKFyGFIAA1AwAFAAkKFyGFIAA1AwAAAA==.Malvenue:BAAANQADCgMIBAAAAA==.Markdashaman:BAAANQADCgIIAgAAAA==.Mauwy:BAAANQAECgYJDwAAAA==.',
Mc='Mcbullseye:BAAANQAECgUIBQAAAA==.',
Me='Megarah:BAAANQADCgYJFgAAAA==.Mepkaelpto:BAAANQADCgYJBgAAAA==.Meretrix:BAAANQAECgUJBQAAAA==.Mersadie:BAAANQAECgQJBwAAAA==.Metanya:BAAANQAECgMIAwAAAA==.Mew:BAAANQAECgIJAgAAAA==.',
Mi='Miateh:BAAANQADCggIGgAAAA==.Mimicme:BAAANQAECgYJEAAAAA==.Mirajanê:BAAANQAECgIJAgAAAA==.Mitchell:BAAANQAECgUICgAAAA==.Miwah:BAAANQAECgQJCwAAAA==.Mizzheals:BAAANQAECgUIDQAAAA==.',
Mo='Mogarr:BAAANQADCgcICwAAAA==.Monkhei:BAAANQADCgEIAQABNQAECgYIDwABAAAAAA==.Moocifer:BAAANQAECgYIEQAAAA==.Mooglewing:BAAANQAECgEIAQAAAA==.Moomoobrncow:BAAANQAECgMIAwAAAA==.Mooriahdairy:BAAANQADCggICAAAAA==.Moorrigån:BAAANQADCgIIAgAAAA==.Mordicanta:BAAANQAECgQJBwAAAA==.Morgannon:BAAANQADCgUIBQAAAA==.Morphies:BAAANQADCgEIAQAAAA==.',
Mu='Muerr:BAAANQAECgYJDgAAAA==.Muerrizond:BAAANQADCgcIBwABNQAECgYJDgABAAAAAA==.Muggel:BAAANQADCgYIDQAAAA==.Mumraa:BAAANQADCgYJEgAAAA==.Mushroohead:BAAANQAECgQICwAAAA==.',
My='Myykiel:BAAANQAECgMIAwAAAA==.',
Na='Naina:BAAANQAECgMIBAAAAA==.Najaja:BAAANQAECgMJBAAAAA==.Namii:BAAANQAECgUIBwAAAA==.Narsum:BAAANQADCgYIBgAAAA==.Natacha:BAAANQAECgEIAQAAAA==.Navadurga:BAAANQAECgMIBgAAAA==.',
Ne='Necro:BAABNQAECoEiAAIYAAcKYCNSEgDSAgAYAAcKYCNSEgDSAgAAAA==.Nedrali:BAAANQADCgcIBwABNQAECgYJDwABAAAAAA==.Nedrina:BAAANQADCgcIBwABNQAECgYJDwABAAAAAA==.Netrath:BAAANQAECgIIAgAAAA==.',
Ni='Nidom:BAAANQAECgIIAgAAAA==.Nighammer:BAAANQAECgQIBgAAAA==.Nimeesha:BAAANQADCgMJAwAAAA==.Ninmah:BAAANQADCggJCAAAAA==.Nirø:BAAANQAECgIIAwAAAA==.',
No='Nooki:BAAANQAECgYIBgAAAA==.Notgretuh:BAAANQAECgcIDQAAAA==.',
Ny='Nyrikah:BAAANQADCgcJEAAAAA==.',
Ob='Obidiah:BAAANQAECgQIBgAAAA==.',
Od='Oddearth:BAAANQAECgEIAQAAAA==.',
Om='Omegablivet:BAAANQADCgMJAwAAAA==.',
Or='Orah:BAAANQADCgEIAQAAAA==.',
Pa='Palagem:BAAANQAECgQJBwAAAA==.Palidingo:BAAANQADCgEIAQAAAA==.Palinyes:BAAANQAECgMIBAAAAA==.Pandabutz:BAAANQAECgQIBgAAAA==.Pandahands:BAAANQADCgIIAgAAAA==.Panduh:BAAANQAECgMJAwAAAA==.Pandussy:BAAANQAECgcIBwAAAA==.Papabill:BAABNQAECoEZAAIHAAcK3QYPlABJAQAHAAcK3QYPlABJAQAAAA==.Papaharny:BAAANQAECgYICgABNQAECgcIGQAHAN0GAA==.Paragorn:BAAANQAECgMIBQAAAA==.Pattee:BAAANQAECgMIAwAAAA==.',
Pe='Pech:BAAANQAECgEIAgABNQAECgYJCQABAAAAAA==.Pechay:BAAANQADCgIJBAABNQAECgYJCQABAAAAAA==.Peenidin:BAAANQAECgYIDwAAAA==.Peepo:BAABNQAECoEcAAIOAAgK1R+ZCgDhAgAOAAgK1R+ZCgDhAgAAAA==.Pemerd:BAAANQAECgQJCwAAAA==.',
Ph='Phoze:BAAANQAECgMIBQAAAA==.Phozzack:BAAANQADCgcJBwAAAA==.Phyai:BAAANQAECgQJBgAAAA==.',
Pl='Pliny:BAABNQAECoEZAAIIAAgKQhgWLwBPAgAIAAgKQhgWLwBPAgAAAA==.',
Pn='Pnutt:BAAANQAECgEIAQAAAA==.',
Po='Porphyriia:BAAANQADCggICAAAAA==.',
Pr='Priestglein:BAAANQADCgUIBQABNQAECgYJDQABAAAAAA==.Promethyus:BAAANQADCgcIDQAAAA==.Promidan:BAAANQAECgIIAgABNQADCggICAABAAAAAA==.Prymus:BAAANQAECgYJDQAAAA==.Pryxi:BAAANQAECgUJCwAAAA==.',
Pu='Punkalicious:BAAANQAECgQIBQAAAA==.',
Py='Pyrogar:BAAANQADCgYIBgAAAA==.Pythius:BAAANQAECgQIBgAAAA==.',
['Pó']='Pótatò:BAAANQADCgMIAwAAAA==.',
Qu='Quetip:BAAANQADCgMIAwAAAA==.Quiksylver:BAAANQAECgYIDgAAAA==.',
Ra='Ratshot:BAABNQAECoEfAAIJAAcKzRkqOgBNAgAJAAcKzRkqOgBNAgABNQAECgkJKQAdAJYgAA==.Rawty:BAAANQADCgUICQAAAA==.',
Re='Red:BAAANQAECgUICQAAAA==.Relgul:BAAANQADCgYICwAAAA==.Rellster:BAAANQAECgcIEwAAAA==.Rennyo:BAAANQAECgUJCwAAAA==.Resonance:BAAANQADCggJFwAAAA==.Rexion:BAAANQAECgMIBQAAAA==.',
Ri='Rigg:BAAANQADCggICgAAAA==.Riggsy:BAAANQAECgQIBgABNQADCggICgABAAAAAA==.Riggzbuffs:BAAANQADCgYICwABNQADCggICgABAAAAAA==.Rivenp:BAAANQADCgYIEAAAAA==.',
Ro='Rocknroll:BAAANQAECgYJDgAAAA==.Rokbiter:BAAANQAECgIIAgAAAA==.Roll:BAAANQADCgYICgABNQAFFAIIAgABAAAAAA==.Rothound:BAAANQAECgIIAgAAAA==.Rozgrez:BAAANQAECgQJBgAAAA==.',
Ru='Runefflck:BAAANQAECgYJDAAAAA==.Russbus:BAABNQAECoEZAAIHAAkKqhhGQABRAgAHAAkKqhhGQABRAgAAAA==.',
Ry='Rynari:BAAANQADCgUIBQABNQAECgYIFwAKAMYPAA==.Rynmorelle:BAABNQAECoEXAAIKAAYKxg/NQwCBAQAKAAYKxg/NQwCBAQAAAA==.',
['Ré']='Réven:BAAANQAECgYIEAAAAA==.',
['Rí']='Rínoah:BAAANQADCgQIBAAAAA==.',
['Rô']='Rôckbôttôm:BAAANQAECgUJBQAAAA==.',
Sa='Sakura:BAAANQAECgYJDAAAAA==.Sane:BAAANQAECgcICgAAAA==.Saoiirse:BAAANQAECgIIAwAAAA==.',
Se='Seershaa:BAAANQADCgYIBgAAAA==.Seriux:BAAANQADCgUIBQAAAA==.Sevencharlie:BAAANQADCggIHwAAAA==.',
Sh='Shadowfate:BAAANQAECgcIBQAAAA==.Shadê:BAAANQADCgEIAQAAAA==.Shamanyou:BAAANQADCgEIAQAAAA==.Shamiqua:BAAANQAECgMIAwAAAA==.Shamutty:BAAANQADCgQIBAABNQAECgkJGAAXAMgcAA==.Shentao:BAAANQAECgYIDgAAAA==.Shirikao:BAAANQADCgYIBgAAAA==.Shiroishi:BAAANQAECgIJAwAAAA==.Shivaray:BAAANQAECgQJBAAAAA==.Shocklesner:BAAANQAECgMIAwAAAA==.Shomade:BAAANQADCgQIBwAAAA==.Shouganai:BAAANQAECgEIAQAAAA==.Shupaz:BAAANQAECgIJAwAAAA==.',
Si='Sifu:BAAANQADCgcJCAAAAA==.Silverlight:BAAANQAECgQJBwAAAA==.Simira:BAAANQADCgQIBAABNQAECgYJDwABAAAAAA==.Simp:BAAANQADCgQIBAAAAA==.Sinaar:BAAANQADCgQIBAAAAA==.Sindena:BAAANQAECgQIBAAAAA==.',
Sk='Skillcommand:BAAANQADCgUIBQAAAA==.Skyemage:BAAANQADCggIFAAAAA==.',
Sl='Sloked:BAAANQAECgUIDAAAAA==.Slokes:BAAANQADCgIIAgAAAA==.Slotz:BAAANQAECgQIBgAAAA==.',
Sm='Smitepanda:BAAANQADCgcICAAAAA==.',
Sn='Sneeze:BAAANQADCgcJFAAAAA==.Snekashifty:BAAANQAECgEIAQAAAA==.Snowsham:BAAANQADCgUJBQAAAA==.',
So='Sonarr:BAAANQAECgMJAwAAAA==.',
Sp='Spark:BAAANQAECgEIAQAAAA==.Spicymeat:BAAANQAECgcJEgABNQAECgkJJQAFABchAA==.Sputty:BAABNQAECoEYAAIXAAkKyBzcCQAOAwAXAAkKyBzcCQAOAwAAAA==.',
Sq='Squanto:BAAANQAECgIIAgABNQAECgkJJQAFABchAA==.',
St='Stalken:BAAANQADCgYJCwAAAA==.Stesha:BAAANQAECgUJCgAAAA==.Stonedfrog:BAAANQADCgcIEAAAAA==.Stïtches:BAAANQAECgQJBAAAAA==.Stönk:BAAANQAECgEJAgAAAA==.',
Su='Sugarlumps:BAAANQADCgEIAQAAAA==.Superdaman:BAAANQADCgEIAQAAAA==.',
Sw='Swaggles:BAAANQAECgMJBQAAAA==.',
Sy='Sygon:BAAANQAECgQJBwAAAA==.Sylm:BAAANQAECgQIBAAAAA==.Symbr:BAAANQAECgUICAAAAA==.Synglace:BAAANQAECgEIAQAAAA==.Syntherizena:BAAANQADCgcIBwAAAA==.',
Ta='Tacitus:BAAANQAECgUJBgAAAA==.Tairrad:BAAANQADCgUIBQABNQAECgIJAgABAAAAAA==.Takeru:BAAANQAECgUICQAAAA==.Talasmar:BAAANQADCgMIAwAAAA==.Taliessin:BAAANQADCgUJBgAAAA==.Talistian:BAAANQADCgIIAgAAAA==.Tarirn:BAAANQADCgYICwAAAA==.Tauntsinpvp:BAAANQAECgEJAQAAAA==.Taylia:BAAANQADCgYJBgABNQAECgYJDwABAAAAAA==.Tazwomann:BAAANQADCgIIAgAAAA==.',
Te='Teaqo:BAAANQADCgQIBAABNQAECgYIDgABAAAAAA==.Telinda:BAAANQABCgIIAgAAAA==.Tempestrasza:BAAANQADCgcICwAAAA==.Tendonitis:BAAANQABCgQIBAAAAA==.Teppe:BAAANQAECgQIBAAAAA==.Terial:BAAANQAECgQICAAAAA==.Terranovian:BAAANQAECgIIAgAAAA==.',
Th='Thajeebus:BAAANQAECgQIDAAAAA==.Thebigstein:BAAANQAECgcIDQAAAA==.Thecapt:BAABNQAECoEXAAIeAAgKMw+KBwDzAQAeAAgKMw+KBwDzAQAAAA==.Theôdöræ:BAAANQAECgEIAQAAAA==.',
Ti='Tiaoma:BAAANQADCggIDgAAAA==.Tinylock:BAAANQADCgUICQAAAA==.Tinymich:BAAANQADCgUIBwABNQAECgUJCwABAAAAAA==.',
Tj='Tjhookèr:BAAANQADCgEJAgAAAA==.',
To='Toetoms:BAAANQADCgIIAgAAAA==.Toletheus:BAAANQAECgYIDQAAAA==.Tomin:BAAANQADCgIIAgAAAA==.Toreshii:BAAANQADCgUICQAAAA==.Totemique:BAAANQADCgQIBAABNQAECgUJCwABAAAAAA==.',
Tr='Trashkantz:BAAANQAECgQIBgABNQAFFAUJDQAFADojAA==.Treeperson:BAAANQAECgUJBgAAAA==.Trickyric:BAAANQAECgYIDwAAAA==.Trinak:BAAANQADCgQICAAAAA==.',
Ts='Tsuyoimono:BAAANQAECgEJAgABNQAECgIIAgABAAAAAA==.',
Tu='Turtleclap:BAAANQADCgUIBQAAAA==.',
Tw='Twistandgrip:BAAANQAECgYIEwAAAA==.',
Ty='Tyinthor:BAAANQAECgMIBgAAAA==.Tytoalba:BAAANQAECgcIBwAAAA==.',
Un='Unholylean:BAAANQADCggIDgAAAA==.',
Ur='Uratsukasama:BAAANQAECgEJAQAAAA==.Urza:BAAANQAECgcIAQAAAA==.',
Va='Vacaite:BAAANQADCgcIBwAAAA==.Vagiant:BAAANQAECggIEQAAAA==.Vangers:BAAANQABCgMIAwAAAA==.Vangie:BAAANQADCgcICAAAAA==.Vanya:BAAANQAECgEJAQAAAA==.Vasso:BAAANQADCgYJFgAAAA==.Vayln:BAAANQAECgcIDQAAAA==.',
Ve='Veildreya:BAAANQABCgQIBAAAAA==.Veinygamer:BAABNQAECoEcAAILAAgKxRxDRwBLAgALAAgKxRxDRwBLAgAAAA==.Veldian:BAAANQAECgYIEAAAAA==.Velveen:BAAANQAECgUJCwAAAA==.Vexahalia:BAAANQAECggJEgAAAA==.',
Vi='Vicarious:BAAANQAECgMIAwABNQAECggJHgAKAHwiAA==.Viciouslump:BAAANQADCggICAAAAA==.Vilebloom:BAEANQAECgMIAwAAAA==.Vilewyrm:BAEANQADCgcIEgABNQAECgMIAwABAAAAAA==.Violetblade:BAAANQADCgQIBAAAAA==.Viridius:BAAANQAECgEIAQAAAA==.',
Vo='Voidmulan:BAEANQADCgUIBQAAAA==.Voluga:BAAANQAECgEIAQAAAA==.',
Vr='Vraak:BAAANQADCggIFAAAAA==.',
Wa='Wagguslight:BAAANQAECgQIBAAAAA==.',
We='Werstshot:BAAANQADCggIEwAAAA==.',
Wh='Whateverdude:BAAANQAECgQIBQAAAA==.',
Wi='Wicketlock:BAAANQADCgcIBwAAAA==.Wiickett:BAABNQAECoEaAAMCAAgKIQ1iEQDhAQACAAgKIQ1iEQDhAQAEAAQKFQK8MQCGAAAAAA==.Wildesel:BAAANQADCggIEAAAAA==.Willaá:BAAANQAECgYIDwAAAA==.Wilson:BAAANQAECgUIDAAAAA==.Wizzpeaver:BAAANQADCgcIBwAAAA==.',
Wo='Wonderwizard:BAAANQADCgIIAgAAAA==.',
Wr='Wrathhoof:BAAANQAECgQIBQABNQAECgYIEAABAAAAAA==.',
Xy='Xylias:BAAANQAECgIIAgAAAA==.',
['Xá']='Xánada:BAAANQADCggIDQABNQAECgEIAQABAAAAAA==.',
Yo='Yorril:BAAANQADCgUIBQAAAA==.',
Yu='Yucca:BAAANQAECgUJDAAAAA==.Yuda:BAAANQAECgQIBAABNQAECggIEwABAAAAAA==.Yukiteru:BAAANQAECgEIAQAAAA==.Yurito:BAAANQADCgYIBgAAAA==.',
Za='Zachie:BAAANQADCgUIBQAAAA==.Zakutin:BAAANQAECgEJAQAAAA==.Zappybains:BAAANQAECgQJBgAAAA==.Zarakii:BAAANQADCgcIHQAAAA==.',
Ze='Zekken:BAAANQADCgMIAwAAAA==.Zelaira:BAAANQADCgMIAwABNQAECgYIFwAKAMYPAA==.',
Zi='Zigzagga:BAAANQADCgQIBAAAAA==.',
Zo='Zoinks:BAAANQADCgQIBQAAAA==.Zorandar:BAAANQADCgQIBQAAAA==.',
Zu='Zupaz:BAAANQADCgQIBAABNQAECgIJAwABAAAAAA==.',
Zy='Zylluz:BAAANQAECgYIEAAAAA==.',
['Äs']='Ästen:BAAANQAECgEJAQAAAA==.',
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
