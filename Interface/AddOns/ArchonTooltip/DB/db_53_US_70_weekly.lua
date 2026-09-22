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

local lookup = {'Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Paladin-Retribution','Unknown-Unknown','Shaman-Restoration','Hunter-Marksmanship','Mage-Arcane','Warlock-Demonology','Paladin-Holy','Rogue-Assassination','Druid-Balance','Druid-Restoration','Priest-Holy','Hunter-Survival','Warrior-Fury','Warrior-Arms','Priest-Shadow','Shaman-Elemental','Paladin-Protection',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Acemage:BAAANQAECgIJBAABNQAFFAUJCgABANsYAA==.',
Ae='Aegon:BAABNQAECoEbAAQCAAgKVSBCDwAEAwACAAgKVSBCDwAEAwADAAYKJQcQXAADAQAEAAEKEAfXbQA0AAAAAA==.Aelivalor:BAAANQADCggIFAAAAA==.Aendoran:BAAANQADCggICwAAAA==.Aeon:BAAANQADCgYIBgAAAA==.Aesthelyan:BAAANQAECgUICAAAAA==.',
Ah='Ahdonis:BAAANQAECgQIBQAAAA==.Ahnerfays:BAAANQADCgMIAwABNQAECggJGgAFALMfAA==.',
Ai='Aiara:BAAANQAECgEIAQAAAA==.Aiarra:BAAANQAECgUIDQAAAA==.Aindriana:BAAANQAECgQICQAAAA==.Aitra:BAAANQAECgEJAQAAAA==.',
Aj='Ajx:BAAANQADCgcJCgABNQAECgIIAgAGAAAAAA==.',
Ak='Akame:BAAANQADCggJDAAAAA==.Akashajade:BAAANQAECgQJBwAAAA==.Akzeriyuth:BAAANQADCgEIAQABNQAECgcIDwAGAAAAAA==.',
Al='Alerothon:BAABNQAECoEdAAIFAAgKqA/9YgDVAQAFAAgKqA/9YgDVAQAAAA==.Alestiana:BAAANQAECgYJEwAAAA==.Alevora:BAAANQADCgIIAgAAAA==.Aluminum:BAAANQADCgQJBAAAAA==.Alycya:BAAANQABCgYIBwAAAA==.',
Am='Amephyst:BAAANQAECgUJCQAAAA==.Amnadores:BAAANQAECgQICAABNQAECgcJEwAGAAAAAA==.',
An='Annati:BAABNQAECoEcAAIHAAkKlyJACABTAwAHAAkKlyJACABTAwAAAA==.Antarres:BAAANQAECgQIBAAAAA==.',
Ao='Aoba:BAAANQAECgYIDwAAAA==.',
Ap='Apila:BAAANQADCgEJAQABNQAECgUICAAGAAAAAQ==.Apox:BAAANQADCgEIAQAAAA==.',
Ar='Arathria:BAAANQADCgUIBQABNQAECgcIEQAGAAAAAA==.Areaman:BAAANQADCgMIAwABNQAECgEJAQAGAAAAAA==.Armagedon:BAAANQADCgUIBQAAAA==.Arovon:BAAANQADCgEJAQAAAA==.Artemisomega:BAAANQADCgEIAgABNQAECgUIBwAGAAAAAA==.Artemisshade:BAAANQAECgUIBwAAAA==.Arthillius:BAAANQADCgcJEgAAAA==.',
As='Astro:BAAANQADCggIEAAAAA==.',
Av='Aviana:BAAANQAECgQIBgAAAA==.',
Ay='Aylá:BAAANQADCgQICAAAAA==.',
Ba='Baldrr:BAAANQADCgUIBQAAAA==.',
Be='Beefypal:BAAANQADCggJCAAAAA==.Beerntotems:BAAANQADCgQJBQAAAA==.Beldar:BAAANQAECgYJEgAAAA==.Bellaliel:BAAANQADCgYIBgAAAA==.',
Bi='Bigmacker:BAAANQADCgIJAgAAAA==.Bip:BAAANQAECgcJDwAAAA==.',
Bl='Blakely:BAAANQADCgQIBAAAAA==.Blitzy:BAAANQAECgYIEgAAAA==.',
Bo='Bobbette:BAAANQAECgEJAQABNQAECgcIEwAGAAAAAA==.Bonejovi:BAAANQADCgYJBgAAAA==.',
Br='Brenick:BAAANQAECgEIAQAAAA==.Bringer:BAAANQADCgYIDAAAAA==.Bristlegonad:BAAANQADCgEIAQAAAA==.Broseph:BAAANQABCgIIAgAAAA==.Bråyden:BAAANQADCgcIEQAAAA==.',
Bu='Bubbléoseven:BAAANQADCgYIBgAAAA==.Bullgrim:BAAANQADCggIDwAAAA==.Burnie:BAAANQAECgEJAQAAAA==.',
['Bò']='Bònkers:BAAANQAECgIIAwAAAA==.',
Ca='Camilah:BAAANQAECgUJCwAAAA==.Capa:BAAANQAECgcIDwAAAA==.Carcine:BAAANQADCgUIBQAAAA==.Carion:BAAANQAECgcIDAAAAA==.',
Ce='Celestiné:BAAANQADCgcJBwAAAA==.Cemeteri:BAAANQADCgYJCAAAAA==.',
Ch='Chaingun:BAAANQAECgIIAgAAAA==.Chelseac:BAAANQAECgQJBQABNQAECgUIBgAGAAAAAA==.Chilblain:BAAANQAECgYJDwAAAA==.Chilchizedek:BAAANQADCgUICQAAAA==.Chobii:BAABNQAECoEZAAIIAAkKRRA1GQA2AgAIAAkKRRA1GQA2AgAAAA==.',
Ci='Cibochevski:BAAANQADCgYJCAABNQAECgEJAQAGAAAAAA==.Ciratorynth:BAAANQAECgYIEAAAAA==.Circumschism:BAAANQADCgUICQAAAA==.Citrus:BAABNQAECoEhAAIHAAkKKiIOBgBwAwAHAAkKKiIOBgBwAwAAAA==.',
Cl='Clearlovec:BAAANQAECgQJAwABNQAECgUIBgAGAAAAAA==.Closetfurry:BAAANQAECgEJAwAAAA==.',
Co='Condor:BAAANQADCggJEwAAAA==.Corrinne:BAAANQAECgMJBAAAAA==.Cosmicmage:BAAANQADCgUIBQAAAA==.',
Cr='Critmypänts:BAAANQAECgEIAQAAAA==.',
Cz='Czernobog:BAAANQADCggJCAAAAA==.',
Da='Daeshan:BAAANQAECgYJDwAAAA==.Dahealamon:BAAANQAECgUIBQAAAA==.Daldolarette:BAAANQAECgcJEwAAAA==.Daradevil:BAAANQADCgcJBwAAAA==.Daralicte:BAAANQADCgUIBQABNQADCgcJBwAGAAAAAA==.Daralune:BAAANQAECgMIAwAAAA==.Darkenrahll:BAAANQADCgIIAgAAAA==.Darner:BAAANQAECgYJDwAAAA==.Dasecondone:BAAANQAECgEJAQAAAA==.Dathirdone:BAAANQADCgYJBgAAAA==.Dawg:BAAANQAECgMJBAAAAA==.',
De='Deadlytankz:BAAANQADCgIIAgAAAA==.Deadval:BAAANQADCgMIAwAAAA==.Demonicfyre:BAABNQAECoEXAAIJAAkKFBp/RwC0AgAJAAkKFBp/RwC0AgAAAA==.Deslarion:BAAANQADCgYIBwAAAA==.Destros:BAAANQAECgIIAgAAAA==.',
Di='Disdain:BAAANQADCggIDgABNQAFFAUIDgAKAG4cAA==.',
Do='Donchapper:BAAANQADCgcJBwAAAA==.Doomsteel:BAAANQADCgQIBAABNQADCgQJBAAGAAAAAA==.',
Dr='Drauger:BAAANQADCgUIBQAAAA==.Drucyllå:BAAANQADCgIIAgAAAA==.Druidson:BAAANQABCgQIBAAAAA==.Drusti:BAAANQADCggICAAAAA==.Dryageribeye:BAAANQAECgcIEgAAAA==.Drzip:BAAANQADCggIFgAAAA==.Drzippy:BAAANQAECgIIAgAAAA==.',
Du='Duskthrasher:BAAANQAECgIJAgAAAA==.Duyii:BAAANQADCgYJBgABNQAECgUICAAGAAAAAQ==.',
Dw='Dwarpheus:BAAANQADCgMIAwAAAA==.',
Dy='Dyanthus:BAAANQAECgcJEQAAAA==.',
['Dà']='Dàrktress:BAAANQAECgEJAgAAAA==.',
Ea='Easterneon:BAAANQAECgUIBgAAAA==.',
Ec='Ech:BAAANQAECgYJDwAAAA==.',
Ei='Eiraveta:BAAANQAECgUIDgAAAA==.',
El='Elemental:BAAANQAECgIIAgAAAA==.Elendirs:BAAANQABCgYIDQAAAA==.Ellois:BAAANQAECgYICQAAAA==.Elronnd:BAAANQADCggIDwAAAA==.',
Ep='Epicnoname:BAAANQAECgcIEQAAAA==.',
Er='Erëdor:BAAANQAECgEIAQAAAA==.',
Es='Esmerèlda:BAAANQADCggJDQAAAA==.Estherwing:BAAANQADCgMIAwAAAA==.',
Ev='Evershine:BAAANQAECgEIAQAAAA==.',
Fa='Fairlight:BAAANQAECgYJDwAAAA==.',
Fe='Feannesse:BAAANQAECgEJAQAAAA==.',
Fi='Firebolt:BAAANQAECgQJCQAAAA==.Fitts:BAAANQAECgUJBQABNQAECggIHAALAOEfAA==.',
Fo='Foe:BAAANQADCgcIBwABNQAECgkJHQAMAHYVAA==.',
Fr='Frags:BAAANQADCgYIBgAAAA==.Fricorith:BAAANQAECgEJAQAAAA==.Frostytoot:BAAANQADCgcICgAAAA==.',
Fu='Fuuz:BAAANQAECgYJBgAAAA==.',
['Fë']='Fëhirthane:BAAANQADCgYICwABNQAECgIJAgAGAAAAAA==.',
['Fù']='Fùzz:BAAANQAECgYJDgAAAA==.',
Ga='Garekk:BAAANQADCggIDwAAAA==.',
Gi='Gilgamésh:BAABNQAECoEsAAMEAAkKiCFyBABxAwAEAAkKiCFyBABxAwACAAgKVxWlLgD4AQAAAA==.Gilmore:BAAANQADCgEIAQAAAA==.',
Gl='Glenix:BAAANQADCgIIAgAAAA==.',
Go='Golldehammer:BAAANQADCgYJCAAAAA==.Goneville:BAAANQADCgYIBgAAAA==.',
Gr='Grizzabella:BAAANQADCggIDwAAAA==.',
Gt='Gtx:BAAANQAECgQJAgAAAA==.',
Gu='Guias:BAAANQADCgEIAQAAAA==.Gutworthy:BAAANQADCgcJCwAAAA==.',
Ha='Hairykrishna:BAAANQAECgEIAQAAAA==.Haldevarik:BAAANQADCgYJCAAAAA==.Hallzofhell:BAAANQAECgUICQAAAA==.Hammerjane:BAAANQAECgEJAQAAAA==.Hamur:BAAANQAECgQJCAAAAA==.Hariyaki:BAAANQAECgEJAQAAAA==.',
He='Heavywinner:BAABNQAECoEcAAMNAAgKrhmCHgB8AgANAAgKrhmCHgB8AgAOAAQKWAlxNgC+AAAAAA==.Hecûba:BAAANQABCgQICAAAAA==.Hedoniist:BAABNQAECoEUAAIPAAcKpyKAFwDGAgAPAAcKpyKAFwDGAgAAAA==.Hellslayer:BAAANQAECgIJAwAAAA==.Hellwalker:BAAANQADCggJDwAAAA==.',
Hu='Hubbabubbá:BAAANQADCgcIBwAAAA==.Hughmann:BAAANQAECgEJAQAAAA==.',
['Hâ']='Hârlot:BAAANQAECgEJAQAAAA==.',
['Hè']='Hèathen:BAAANQADCgYJCAAAAA==.',
In='Ingenii:BAAANQAECgQJBAABNQAECgcIDwAGAAAAAA==.',
Is='Ishaa:BAAANQADCgIIAgAAAA==.Isllwyn:BAAANQADCgMIAwAAAA==.Isummonyou:BAAANQAFFAIJBAAAAA==.',
Ja='Jadeth:BAAANQAECgEIAQAAAA==.Jaestra:BAAANQADCgMIAwABNQAECgEJAQAGAAAAAA==.Jaidah:BAAANQADCgcIFgAAAA==.Jaith:BAAANQADCgQJBAAAAA==.Jamaicann:BAAANQADCgYIBgABNQAECgQICAAGAAAAAA==.Jansôlo:BAABNQAECoEXAAMBAAgKQCIfEQAaAwABAAgKQCIfEQAaAwAIAAMKGRVZPQDBAAAAAA==.Jaratri:BAABNQAECoEiAAIQAAgKPBjtAgCGAgAQAAgKPBjtAgCGAgAAAA==.',
Je='Jeka:BAAANQADCgQIBwAAAA==.Jenton:BAAANQAECgUJBgAAAA==.',
Ka='Kaerovia:BAAANQAECgYJEgAAAA==.Kaisen:BAAANQADCgUICwAAAA==.Kalsidious:BAAANQADCgEIAQAAAA==.Kamthesham:BAAANQAECgcICwAAAA==.Kanchome:BAAANQADCgYIBgAAAA==.Kaneki:BAAANQAECgMIAgAAAA==.Karenmode:BAAANQADCgQJBAAAAA==.Karg:BAAANQAECgUJBwAAAA==.Karmai:BAAANQAECgYJEQAAAA==.Kathine:BAAANQADCggIFwAAAA==.Kayliey:BAAANQADCggJCAAAAA==.',
Ke='Keaa:BAAANQABCgQIBAAAAA==.Kelvala:BAABNQAECoEXAAMRAAgKdSRHBgAiAgASAAgKPx4nMwCcAgARAAUK9SRHBgAiAgAAAA==.Kelwynd:BAAANQADCggIJQAAAA==.Keä:BAAANQAECgQJBAAAAA==.',
Kh='Khasaziel:BAAANQADCgcIBwAAAA==.',
Ki='Kirean:BAAANQAECgYJDwAAAA==.',
Ko='Kobesama:BAAANQAECgYJDgAAAA==.Kodask:BAAANQADCgYICwAAAA==.Kodera:BAAANQAECgYJEgAAAA==.Konata:BAAANQADCggIDwABNQAECgYIDwAGAAAAAA==.Korbenzoo:BAAANQADCgMIBAABNQAECgUICAAGAAAAAQ==.Korigan:BAAANQADCgEIAQAAAA==.',
Kr='Kryssie:BAAANQAECgYIEgAAAA==.',
Ku='Kuroku:BAAANQADCgUIBQAAAA==.',
Kw='Kwaili:BAAANQAECgYJDAAAAA==.',
La='Lanaya:BAAANQAECgMJBAAAAA==.Laserheadten:BAABNQAECoEbAAITAAgK9BvBDgCzAgATAAgK9BvBDgCzAgAAAA==.Lawrensce:BAAANQAECgIJAwAAAA==.',
Le='Lencho:BAAANQAECgIJAgAAAA==.Lenchodude:BAAANQADCgUJCQAAAA==.Lenian:BAAANQAECgEJAQAAAA==.Leâfs:BAAANQADCgYJEQAAAA==.',
Li='Lirrael:BAAANQADCgEIAQAAAA==.Litesout:BAAANQAECgMJAwAAAA==.',
Lo='Loghyn:BAAANQAECgIIAgAAAA==.Loreck:BAAANQADCggIFwAAAA==.Lorlea:BAAANQADCgMIAwABNQADCgQJBAAGAAAAAA==.Lourom:BAAANQAECgUJBgAAAA==.',
Lu='Lunarcateyes:BAAANQADCgYIBgAAAA==.Lunariel:BAAANQAECgIIAgAAAA==.',
Ly='Lyraae:BAAANQAECgUIDgAAAA==.',
Ma='Mackas:BAAANQADCgYICAAAAA==.Magicbeer:BAAANQADCgYJDQAAAA==.Maidenofhate:BAABNQAECoEcAAIBAAgKqhYFMwBnAgABAAgKqhYFMwBnAgAAAA==.Maiganoss:BAAANQADCggIHAAAAA==.Makeloa:BAAANQADCgUIBgAAAA==.Mardon:BAAANQABCgQICQABNQABCgYIDQAGAAAAAA==.Maxxwell:BAAANQABCgIJAgAAAA==.',
Me='Megid:BAAANQAECgUIDgAAAA==.Mestopheles:BAAANQAECgYJCgAAAA==.Mezsiah:BAAANQAECgEIAQABNQAECgUICwAGAAAAAA==.',
Mi='Midianite:BAAANQADCgMIAwAAAA==.Mimiru:BAAANQADCgYIBgAAAA==.Minié:BAAANQAECgMJAwAAAA==.Mizblumkin:BAAANQADCgcIDQAAAA==.',
Mo='Monkies:BAAANQADCgcJBwAAAA==.Montey:BAAANQADCgMIAwAAAA==.Moonnshine:BAAANQAECgYJEgAAAA==.Moonrend:BAAANQADCgEJAQAAAA==.',
Mu='Murgrot:BAAANQADCgQIBAAAAA==.',
My='Mylittlepwni:BAAANQADCgYJEQAAAA==.',
['Mä']='Mälcharion:BAAANQADCgcJBwAAAA==.',
Na='Nainel:BAAANQADCgMIAwABNQAECgEJAQAGAAAAAA==.Nakros:BAAANQAECgUJBgAAAA==.Nathelezet:BAAANQADCgQJBAABNQAECgEJAQAGAAAAAA==.',
Ne='Nemonas:BAAANQADCggIHAAAAA==.Nerik:BAAANQADCgUJBgAAAA==.Nerissa:BAEANQAECggICAAAAA==.Netallia:BAAANQABCgcIDQAAAA==.',
Ng='Ngyue:BAAANQADCgYJJAAAAA==.',
Ni='Niala:BAAANQADCgUJBQAAAA==.Nianna:BAAANQAECgUIDgAAAA==.Nickto:BAAANQAECgIJAgAAAA==.Nightshayed:BAAANQADCgYJCAAAAA==.',
Nu='Nubin:BAAANQADCgYICAAAAA==.Numbed:BAAANQADCggICAAAAA==.',
Ny='Nytwalker:BAAANQAECgMIAwAAAA==.Nyårlåthôtêp:BAAANQAECgEJAQAAAA==.',
Og='Ogbruced:BAAANQADCgYIBQABNQAECgIJAgAGAAAAAA==.',
Op='Opalla:BAAANQADCggIHAAAAA==.',
Or='Orceo:BAAANQADCggIGQAAAA==.Orcrest:BAAANQADCgcJEQAAAA==.Ororo:BAABNQAECoEaAAIUAAgKnxKiOQAWAgAUAAgKnxKiOQAWAgAAAA==.',
Pa='Palal:BAAANQADCgcIBwABNQAECgMIBAAGAAAAAA==.Paryah:BAAANQAECgEJAQAAAA==.',
Ph='Phanceester:BAAANQADCgYIDwAAAA==.Phindra:BAAANQADCgUJBgAAAA==.Phréek:BAAANQAECgYJDAAAAA==.',
Pl='Plants:BAAANQADCgMIAwAAAA==.Plethknight:BAAANQAECgUIDAABNQAFFAMICgAVAEQIAA==.',
Po='Poetea:BAAANQADCgEIAQAAAA==.',
Pr='Praze:BAAANQADCgcJEgAAAA==.',
Pu='Puogh:BAAANQABCgIIAgAAAA==.Puoh:BAAANQABCgYIBwAAAA==.Pustülio:BAAANQADCggICAAAAA==.',
Pw='Pwough:BAAANQABCggJCgAAAA==.',
Ra='Raha:BAAANQADCgYIBgAAAA==.Rahis:BAAANQAECgYJEgAAAA==.Raiu:BAAANQAECgEJAQAAAA==.Ramsis:BAAANQAECgcIEwAAAA==.Randir:BAAANQAECgcIEwAAAA==.Ranir:BAAANQADCgcJDAAAAA==.Rath:BAAANQAECgUIDwAAAA==.',
Re='Rebarka:BAAANQAECgEIAQAAAA==.Rebrewke:BAAANQAECgMIBAAAAA==.Remedivhs:BAAANQADCgEJAQABNQAECgUICAAGAAAAAQ==.Rettbull:BAAANQADCgMIAwAAAA==.Revy:BAAANQAECgQJBAAAAA==.',
Rh='Rhiannonage:BAAANQAECgQJBAAAAA==.Rhyli:BAAANQADCgMIAwAAAA==.',
Ro='Robinhoodx:BAAANQAECgYJDwAAAA==.Roenabur:BAAANQADCgYJCAAAAA==.Romok:BAAANQADCgcJEgAAAA==.',
Ru='Rubysunday:BAAANQADCggIGQAAAA==.',
Ry='Rykarranger:BAAANQADCgQIBAAAAA==.',
['Rì']='Rìseandemìse:BAAANQABCgEIAQAAAA==.',
Sa='Sacrìfice:BAAANQAECgUJDAAAAA==.Samoot:BAAANQAECgUICwAAAA==.Sarreus:BAAANQADCgMJBwABNQAECgUICAAGAAAAAQ==.',
Se='Sepharim:BAAANQADCgQIBwAAAA==.',
Sh='Shael:BAAANQAECgEJAQAAAA==.Shamanstein:BAEANQADCggJDwAAAA==.Shammbo:BAAANQAECgIJAwABNQAECgUJCAAGAAAAAA==.Sharty:BAAANQAECgQICwAAAA==.Sheriruth:BAAANQADCggICAABNQAECgcIDwAGAAAAAA==.Shortigen:BAAANQADCgcJEQAAAA==.Shrilynda:BAAANQADCgUIBwAAAA==.Shupala:BAAANQAECgIIBAAAAA==.',
Si='Sicnus:BAAANQADCgYICAAAAA==.Silveryl:BAAANQADCggJCAABNQADCggIHAAGAAAAAA==.Sinadin:BAAANQAECgYJEgAAAA==.',
Sk='Skolmaster:BAAANQAECgQIBAAAAA==.Skootter:BAAANQADCgYJBwAAAA==.Skyfury:BAAANQAECgEJAgABNQAECgQJCQAGAAAAAA==.',
Sm='Smarky:BAAANQAECggIAQAAAA==.Smâlls:BAEANQAECgIJAgAAAA==.',
Sn='Snugz:BAAANQADCggICAAAAA==.',
So='Sourdiesel:BAAANQADCgcIEwAAAA==.Southsound:BAAANQAECgQIDAABNQAECgUIBgAGAAAAAA==.',
Sp='Spewak:BAAANQADCgQIBAABNQABCgEIAQAGAAAAAA==.',
St='Stallos:BAAANQADCgQIBAAAAA==.Stark:BAAANQADCggJDAAAAA==.Starmie:BAAANQADCgcIBwAAAA==.Steakknife:BAAANQAECgcJDAAAAA==.Stormoon:BAAANQAECgMJBwAAAA==.Sturma:BAAANQAECgMIBwAAAA==.',
Su='Superrad:BAAANQADCgcIFQAAAA==.',
Sw='Swayla:BAAANQADCgUIBwAAAA==.Sweatyhog:BAAANQADCggJGAAAAA==.',
Sy='Sybil:BAAANQADCggJEAAAAA==.',
['Sà']='Sàlvage:BAAANQADCggICAAAAA==.',
['Sí']='Sínner:BAAANQADCgIIAgAAAA==.',
Ta='Tahfyn:BAAANQAECgEJAQAAAA==.Tahtiania:BAAANQADCgYIDwAAAA==.Tamarin:BAAANQADCgEIAQAAAA==.Tasdarazen:BAAANQADCgYJDAAAAA==.Tazedtilblue:BAAANQADCgYIDwAAAA==.',
Te='Ted:BAAANQAECggIAgAAAA==.Teo:BAAANQAECgUIDgAAAA==.Teyamat:BAAANQAECgUICQABNQABCgQIBwAGAAAAAA==.',
Th='Thalumind:BAAANQADCgQIBAAAAA==.Thelock:BAABNQAECoEXAAMHAAgKHR1tHwCXAgAHAAgKHR1tHwCXAgAUAAIKsBBetwB8AAAAAA==.Thetree:BAABNQAECoEnAAMOAAkKrRujCQDVAgAOAAkKrRujCQDVAgANAAcKEhztJQA6AgAAAA==.Thien:BAAANQADCgUIBQAAAA==.Thoinus:BAAANQAECgEJAQABNQAECgUJDgAGAAAAAA==.Thoughtcrime:BAAANQADCggIDQAAAA==.Thundertaco:BAAANQADCggICAAAAA==.Thundertwig:BAAANQAECgUJCwAAAA==.',
Ti='Timoris:BAAANQAECgIIAgABNQAECgcIDwAGAAAAAA==.',
To='Tobiume:BAAANQADCgUJCQABNQAECgcJEwAGAAAAAA==.Tofulhundun:BAAANQAECgEIAQAAAA==.Toggo:BAAANQADCgQIBQAAAA==.Tommytwotusk:BAAANQAECgIJAgAAAA==.',
Tr='Trenon:BAAANQADCgYICAAAAA==.Triannah:BAAANQAECgIIBAAAAA==.Trildjr:BAAANQAECgEJAQAAAA==.',
Tu='Tuchmi:BAAANQADCgYIBgAAAA==.Tuldag:BAAANQAECgYJDgAAAA==.',
Ty='Tyronda:BAAANQADCgcJCgAAAA==.Tyrse:BAAANQAECgIJAgAAAA==.',
Tz='Tzerina:BAAANQAECgIJAgAAAA==.',
['Tâ']='Tânkyû:BAAANQADCgUIBQAAAA==.',
['Tï']='Tïmbits:BAAANQAECgIJAgAAAA==.',
Ut='Uthadravis:BAAANQAECgUICAAAAQ==.',
Va='Vaelwyn:BAAANQADCggJCAAAAA==.Valegion:BAAANQADCgMJAwAAAA==.Valerina:BAAANQADCgQJBAAAAA==.Valford:BAAANQAECgQIBwAAAA==.Validan:BAAANQADCgYICAAAAA==.Valkriss:BAAANQADCgMIAwAAAA==.Vallyrie:BAABNQAECoEZAAICAAcK1xM7NADWAQACAAcK1xM7NADWAQAAAA==.Valssharess:BAAANQAECgIJAgAAAA==.Valth:BAAANQADCgcJEgAAAA==.Valzen:BAAANQADCgEIAQAAAA==.Vanae:BAAANQADCgUJBQAAAA==.Vaporgriffin:BAAANQAECgEJAQAAAA==.Varthric:BAAANQADCgMIAwAAAA==.',
Ve='Velendez:BAAANQADCgcJDgAAAA==.Veleria:BAABNQAECoEVAAILAAcKVhm/OAAWAgALAAcKVhm/OAAWAgAAAA==.Vellysonna:BAAANQAECgEIAQAAAA==.Ventessa:BAAANQADCgYIBgAAAA==.Versatina:BAAANQADCgcJEAAAAA==.',
Vi='Victra:BAAANQAECgIIAgAAAA==.Viirnald:BAEANQADCgYIBgAAAA==.Vikingbeast:BAAANQABCgUJBgAAAA==.Viko:BAAANQAECgIIAgAAAA==.Vinaya:BAAANQADCgcJEgAAAA==.Vindicta:BAAANQAECgEIAQABNQADCgEIAQAGAAAAAA==.',
Vo='Volthemar:BAAANQAECgcIEQAAAA==.Voodoopunch:BAAANQABCgUIBwAAAA==.',
Vy='Vynll:BAAANQADCgIJAgAAAA==.',
Wa='Warrpath:BAAANQADCgEIAQAAAA==.Watsuki:BAAANQADCgYJCAABNQAECgEJAQAGAAAAAA==.',
We='Weoo:BAAANQADCgcJCAAAAA==.Werrick:BAAANQAECgUJCwAAAA==.',
Wh='Whitespot:BAAANQADCgcJEwAAAA==.',
Wi='Wisegurl:BAAANQAECgUIBwAAAA==.',
Wo='Woodpecker:BAAANQAECgYJDwAAAA==.',
Wr='Wreckreation:BAAANQAECgIIBAAAAA==.',
Wy='Wylecsham:BAAANQADCgUJBQAAAA==.Wylectra:BAAANQAECgYJDwAAAA==.',
Xe='Xethos:BAAANQADCgQIBAAAAA==.',
Ya='Yanikå:BAAANQADCgQICAAAAA==.',
Ye='Yeira:BAAANQAECgYIEAAAAA==.Yerdedmatey:BAAANQAECgEIAQAAAA==.',
Yo='Yourdemon:BAAANQAECgIIAgAAAA==.',
Za='Zagasham:BAAANQAECgYIDwAAAA==.Zahvaria:BAAANQAECgEJAQAAAA==.Zalson:BAAANQABCgYJBgAAAA==.Zamari:BAAANQADCgMIAwABNQAECgEJAQAGAAAAAA==.Zaphiell:BAAANQAECgQICAAAAA==.',
Ze='Zeid:BAAANQAECgcJDQAAAA==.Zev:BAAANQADCgcJEQAAAA==.',
Zi='Zillz:BAAANQADCgYIDAAAAA==.Zinderalanot:BAAANQAECgQICQABNQAECgUICAAGAAAAAQ==.',
Zl='Zlightnin:BAAANQADCgQIBAAAAA==.',
Zo='Zoeystorm:BAAANQAECgQJDgAAAA==.',
Zu='Zuldrak:BAAANQAECgcIEAAAAA==.',
Zy='Zykie:BAAANQADCgcIBwAAAA==.',
['Ìn']='Ìnferior:BAAANQADCgYIBgAAAA==.',
['Ðè']='Ðèáth:BAAANQADCgYIBgAAAA==.',
['Öm']='Ömenjr:BAAANQAECgcJEwAAAA==.',
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
