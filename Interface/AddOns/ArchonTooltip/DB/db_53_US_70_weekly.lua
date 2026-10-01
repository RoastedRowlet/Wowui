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

local lookup = {'Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Paladin-Retribution','Unknown-Unknown','Shaman-Restoration','Warlock-Demonology','Paladin-Protection','Hunter-Survival','Warlock-Destruction','Mage-Frost','Hunter-Marksmanship','Evoker-Devastation','Monk-Windwalker','Paladin-Holy','Mage-Arcane','Warrior-Arms','Priest-Holy','Rogue-Assassination','Druid-Balance','Druid-Restoration','Rogue-Outlaw','DemonHunter-Havoc','Warrior-Fury','Evoker-Augmentation','Priest-Shadow','Shaman-Elemental','Warrior-Protection',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Acemage:BAAANQAECgUICQABNQAFFAUIDwABADEcAA==.',
Ae='Aegon:BAABNQAECoEbAAQCAAgKVSCrGQCzAgACAAgKVSCrGQCzAgADAAYKJQdVawD7AAAEAAEKEAeShAAyAAAAAA==.Aelivalor:BAAANQADCggIFAAAAA==.Aendoran:BAAANQADCggICwAAAA==.Aeon:BAAANQADCgYIBgAAAA==.Aesthelyan:BAAANQAECgUIDQAAAA==.',
Ah='Ahdonis:BAAANQAECgQIBQAAAA==.Ahnerfays:BAAANQAECgQIBgABNQAECggIIgAFALMfAA==.',
Ai='Aiara:BAAANQAECgEIAQAAAA==.Aiarra:BAAANQAECgYIEwAAAA==.Aindriana:BAAANQAECgUIDgAAAA==.Aitra:BAAANQAECgQIBQAAAA==.',
Aj='Ajx:BAAANQAECgIIAgABNQAECgQIBAAGAAAAAA==.',
Ak='Akame:BAAANQADCggIEgAAAA==.Akashajade:BAAANQAECgUIDAAAAA==.Akzeriyuth:BAAANQADCgEIAQABNQAECggIEAAGAAAAAA==.',
Al='Alerothon:BAABNQAECoElAAIFAAgKqBOxZwAKAgAFAAgKqBOxZwAKAgAAAA==.Alestiana:BAABNQAECoEhAAIHAAgKRBg3OQAzAgAHAAgKRBg3OQAzAgAAAA==.Alevora:BAAANQADCgIIAgAAAA==.Aluminum:BAAANQADCgQJBAAAAA==.Alycya:BAAANQABCgYIBwAAAA==.',
Am='Amephyst:BAAANQAECgYIDwAAAA==.Amnadores:BAAANQAECgQIDAABNQAECgkJHQAIAAIUAA==.',
An='Annati:BAACNQAFFIEHAAIHAAMKVRe4DQACAQAHAAMKVRe4DQACAQA1AAQKgR4AAgcACQqXIkgMADwDAAcACQqXIkgMADwDAAAA.Antarres:BAAANQAECgcICwAAAA==.',
Ao='Aoba:BAABNQAECoEZAAIJAAcK/BlXFwDpAQAJAAcK/BlXFwDpAQAAAA==.',
Ap='Apila:BAAANQADCgEIAgABNQAECgUIDgAGAAAAAQ==.Apox:BAAANQADCgEIAQAAAA==.',
Ar='Arathria:BAAANQADCgUIBQABNQAECgkJGQAEAIIaAA==.Areaman:BAAANQADCgMIAwABNQAECgIIAwAGAAAAAA==.Aridam:BAAANQADCgcIBwAAAA==.Armagedon:BAAANQADCgUIBQAAAA==.Arovon:BAAANQADCgcICAAAAA==.Artemisomega:BAAANQADCgEIAgABNQAECgUIDAAGAAAAAA==.Artemisshade:BAAANQAECgUIDAAAAA==.Arthillius:BAAANQADCgcIGQAAAA==.',
As='Astro:BAAANQADCggIEAAAAA==.',
Av='Aviana:BAAANQAECgQICgAAAA==.',
Ay='Aylá:BAAANQADCgQICAAAAA==.',
Ba='Baldrr:BAAANQADCgUIBQAAAA==.',
Be='Beefypal:BAAANQAECgQIBAAAAA==.Beerntotems:BAAANQADCgQJBQAAAA==.Beldar:BAABNQAECoEZAAIKAAcK/wnlBgC9AQAKAAcK/wnlBgC9AQAAAA==.Bellaliel:BAAANQADCgYIBgAAAA==.Bevil:BAAANQADCgYIBgAAAA==.',
Bi='Bigmacker:BAAANQADCgIIAgAAAA==.Bip:BAABNQAECoEZAAMIAAkKsQ89YQDkAQAIAAgKBA89YQDkAQALAAIKnhE7TwB8AAAAAA==.',
Bl='Blakely:BAAANQADCgYICgAAAA==.Blitzy:BAAANQAECgcIEwAAAA==.',
Bo='Bobbette:BAAANQAECgUIBgABNQAECggIFQAHAGsbAA==.Bonejovi:BAAANQAECgEIAQAAAA==.',
Br='Brenick:BAAANQAECgIIAwAAAA==.Bringer:BAAANQADCgYIDAAAAA==.Bristlegonad:BAAANQADCgEIAQAAAA==.Broseph:BAAANQABCgIIAgAAAA==.Bråyden:BAAANQADCgcIEQAAAA==.',
Bu='Bubbléoseven:BAAANQADCgYIBgAAAA==.Bullgrim:BAAANQADCggIDwAAAA==.Burnie:BAAANQAECgIIAwAAAA==.',
['Bò']='Bònkers:BAAANQAECgIIAwAAAA==.',
Ca='Camilah:BAAANQAECgcIEAAAAA==.Capa:BAAANQAECggIEAAAAA==.Carcine:BAAANQADCgUIBQAAAA==.Carion:BAAANQAECgcIEwAAAA==.',
Ce='Celestiné:BAAANQAECgQIBAAAAA==.Cemeteri:BAAANQADCgcIDAAAAA==.',
Ch='Chaingun:BAAANQAECgUIBQAAAA==.Chelseac:BAAANQAECgQICQABNQAECgcICAAGAAAAAA==.Chilblain:BAABNQAECoEZAAIMAAcKYgomDwBvAQAMAAcKYgomDwBvAQAAAA==.Chilchizedek:BAAANQADCgYIDwAAAA==.Chobii:BAABNQAECoEgAAINAAkK0RPXGQBTAgANAAkK0RPXGQBTAgAAAA==.',
Ci='Cibochevski:BAAANQADCgcIDAABNQAECgIIAwAGAAAAAA==.Ciratorynth:BAABNQAECoEaAAIOAAgK6hSqDwAjAgAOAAgK6hSqDwAjAgAAAA==.Circumschism:BAAANQADCgYIDwAAAA==.Citrus:BAABNQAECoEjAAIHAAkKKiI1CQBYAwAHAAkKKiI1CQBYAwAAAA==.',
Cl='Clearlove:BAAANQADCggICAABNQAECgcICAAGAAAAAA==.Clearlovec:BAAANQAECgcICAAAAA==.Closetfurry:BAAANQAECgMICAAAAA==.',
Co='Condor:BAAANQAECgQIBAAAAA==.Corrinne:BAAANQAECgcICwAAAA==.Cosmicmage:BAAANQADCgUIBQAAAA==.',
Cr='Critmypänts:BAAANQAECgEIAQAAAA==.',
Cz='Czernobog:BAAANQAECgQIBAAAAA==.',
Da='Daeshan:BAABNQAECoEZAAIPAAcKIRWHIQDCAQAPAAcKIRWHIQDCAQAAAA==.Dahealamon:BAAANQAECgUIBwAAAA==.Daldolarette:BAABNQAECoEdAAIQAAkKbRcvIwCuAgAQAAkKbRcvIwCuAgAAAA==.Daradevil:BAAANQADCgcJBwAAAA==.Daralicte:BAAANQADCgUIBQABNQADCgcJBwAGAAAAAA==.Daralune:BAAANQAECgMIAwAAAA==.Darkenrahll:BAAANQADCgIIAgAAAA==.Darner:BAABNQAECoEZAAMFAAcK+xdpcADxAQAFAAcK+xdpcADxAQAJAAEKxwTJYwAfAAAAAA==.Dasecondone:BAAANQAECgQIBQAAAA==.Dathirdone:BAAANQADCgcIDAAAAA==.Dawg:BAAANQAECgMIBQAAAA==.',
De='Deadlytankz:BAAANQADCgIIAgAAAA==.Deadval:BAAANQADCgMIAwAAAA==.Demonicfyre:BAEBNQAECoEbAAIRAAkKvxwMRgDVAgARAAkKvxwMRgDVAgAAAA==.Demonstein:BAEANQAECgUIBQABNQAFFAUIDAAFAM8YAA==.Deslarion:BAAANQADCgYICwAAAA==.Destros:BAAANQAECgQIBgAAAA==.',
Di='Disdain:BAAANQAECgYIBgABNQAFFAYIFAAIAKAcAA==.',
Do='Donchap:BAAANQAECggIBgAAAA==.Donchapper:BAAANQADCgcJBwAAAA==.Doomsteel:BAAANQADCgQIBAABNQADCgQJBAAGAAAAAA==.',
Dr='Drauger:BAAANQADCgUIBQAAAA==.Drucyllå:BAAANQADCgIIAgAAAA==.Druidson:BAAANQABCgQIBAAAAA==.Drusti:BAAANQADCggICAAAAA==.Dryageribeye:BAABNQAECoEYAAMCAAkKFBvyMgACAgACAAcKGRvyMgACAgAEAAYKzRcNMQC1AQAAAA==.Drzip:BAAANQADCggIFgAAAA==.Drzippy:BAAANQAECgMIBQAAAA==.',
Du='Duane:BAAANQAECgQIBAAAAA==.Duskthrasher:BAAANQAECgQIBgAAAA==.Duyii:BAAANQADCgYIBgABNQAECgUIDgAGAAAAAQ==.',
Dw='Dwarpheus:BAAANQADCgMIAwAAAA==.',
Dy='Dyanthus:BAABNQAECoEcAAIBAAgKGROHTwAyAgABAAgKGROHTwAyAgAAAA==.',
['Dà']='Dàrktress:BAAANQAECgIIBAAAAA==.',
Ea='Easterneon:BAAANQAECgUIBwABNQAECgcICAAGAAAAAA==.',
Ec='Ech:BAABNQAECoEZAAISAAcKfBWWfgDLAQASAAcKfBWWfgDLAQAAAA==.',
Ei='Eiraveta:BAABNQAECoEUAAITAAYKJQ1CdgBKAQATAAYKJQ1CdgBKAQAAAA==.',
El='Elemental:BAAANQAECgMIBQAAAA==.Elendirs:BAAANQABCgYIEQABNQABCgcIDgAGAAAAAA==.Ellois:BAAANQAECgYICQAAAA==.Elronnd:BAAANQADCggIDwAAAA==.',
Ep='Epicnoname:BAABNQAECoEZAAIEAAkKghpNFwCKAgAEAAkKghpNFwCKAgAAAA==.',
Er='Erëdor:BAAANQAECgEIAQAAAA==.',
Es='Esmerèlda:BAAANQAECgQIBAAAAA==.Estherwing:BAAANQADCgMIAwAAAA==.',
Ev='Evershine:BAAANQAECgYIBAAAAA==.',
Fa='Fairlight:BAABNQAECoEZAAIDAAcKbBjLNwDoAQADAAcKbBjLNwDoAQAAAA==.',
Fe='Feannesse:BAAANQAECgIIAgAAAA==.',
Fi='Firebolt:BAAANQAECgQIDQAAAA==.Fitts:BAAANQAECgUIBgABNQAECgkJJAAQAAUfAA==.',
Fo='Foe:BAAANQADCgcIBwABNQAECgkJHQAUAHYVAA==.',
Fr='Frags:BAAANQADCgYIBgAAAA==.Fricorith:BAAANQAECgQIBQAAAA==.Frostytoot:BAAANQADCgcICgAAAA==.',
Fu='Fuuz:BAAANQAECgYICwAAAA==.',
['Fë']='Fëhirthane:BAAANQADCgYICwABNQAECgUIBwAGAAAAAA==.',
['Fù']='Fùzz:BAAANQAECgcIDwAAAA==.',
Ga='Garekk:BAAANQAECgYIBgAAAA==.',
Gi='Gilgamésh:BAABNQAECoE4AAMEAAkKAiMQBACHAwAEAAkKAiMQBACHAwACAAgKQBbkQQCuAQAAAA==.Gilmore:BAAANQADCgEIAQAAAA==.',
Gl='Glenix:BAAANQADCggICgAAAA==.',
Go='Golldehammer:BAAANQADCgcIDAAAAA==.Goneville:BAAANQAECggICAAAAA==.',
Gr='Gretorix:BAAANQADCgcIBwAAAA==.Grizzabella:BAAANQAECgYIBgAAAA==.',
Gt='Gtx:BAAANQAECgQIBgAAAA==.',
Gu='Guias:BAAANQADCgEIAQAAAA==.Gutworthy:BAAANQAECgIIAgAAAA==.',
Ha='Hairykrishna:BAAANQAECgEIAQAAAA==.Haldevarik:BAAANQADCgYJCAAAAA==.Hallzofhell:BAAANQAECgUIDgAAAA==.Hallzy:BAAANQADCgYIBgAAAA==.Hammerjane:BAAANQAECgIIAwAAAA==.Hamur:BAAANQAECgUIDQAAAA==.Hariyaki:BAAANQAECgIIAwAAAA==.Havebandaids:BAAANQABCgYICAAAAA==.',
He='Heavywinner:BAABNQAECoElAAMVAAkK0hpGFwDjAgAVAAkK0hpGFwDjAgAWAAQKWAliQQC3AAAAAA==.Hecûba:BAAANQABCgQICAAAAA==.Hedoniist:BAABNQAECoEWAAITAAcK7COWHwC6AgATAAcK7COWHwC6AgAAAA==.Hellsfury:BAAANQADCgYIBwAAAA==.Hellslayer:BAAANQAECgUICAAAAA==.Hellwalker:BAAANQADCggIFQAAAA==.',
Hu='Hubbabubbá:BAAANQADCgcIBwAAAA==.Hughmann:BAAANQAECgIIAwAAAA==.',
['Hâ']='Hârlot:BAAANQAECgIIAwAAAA==.',
['Hè']='Hèathen:BAAANQADCgcIDAAAAA==.',
In='Ingenii:BAAANQAECgQIBAABNQAECggIEAAGAAAAAA==.',
Is='Ishaa:BAAANQADCgIIAgAAAA==.Isllwyn:BAAANQADCgMIAwAAAA==.Isummonyou:BAACNQAFFIEJAAIIAAUKjBTRBwCNAQAIAAUKjBTRBwCNAQA1AAQKgRYAAggACQpIGXEqAKQCAAgACQpIGXEqAKQCAAAA.',
Ja='Jace:BAAANQABCgYICAAAAA==.Jadeth:BAAANQAECgEIAQAAAA==.Jaestra:BAAANQADCgMIAwABNQAECgIIAwAGAAAAAA==.Jaidah:BAAANQADCggIHAAAAA==.Jaith:BAAANQAECgEIAQAAAA==.Jamaicann:BAAANQADCgYIBgABNQAECgQICAAGAAAAAA==.Jansôlo:BAABNQAECoEXAAMBAAgKQCKtGwD2AgABAAgKQCKtGwD2AgANAAMKGRUKSgCvAAAAAA==.Jaratri:BAABNQAECoErAAIKAAkKeBkfAgD7AgAKAAkKeBkfAgD7AgAAAA==.',
Je='Jeka:BAAANQADCgUIDAAAAA==.Jenton:BAAANQAECgUICwAAAA==.',
Ka='Kaerovia:BAABNQAECoEaAAIQAAgKvxALUADmAQAQAAgKvxALUADmAQAAAA==.Kaisen:BAAANQADCgUICwAAAA==.Kalsidious:BAAANQADCgEIAQAAAA==.Kamthesham:BAAANQAECggIDAAAAA==.Kanchome:BAAANQADCgYIBgAAAA==.Kaneki:BAAANQAECgUIBgAAAA==.Karg:BAAANQAECgYIDQAAAA==.Karmai:BAABNQAECoEbAAIXAAcKnSCXBACNAgAXAAcKnSCXBACNAgAAAA==.Kastigor:BAAANQADCgMIAwABNQAECggIIAAYAN0XAA==.Kathine:BAAANQAECgMIAwAAAA==.Kayliey:BAAANQAECgQIBAAAAA==.',
Ke='Keaa:BAAANQABCgQIBAAAAA==.Kelvala:BAABNQAECoEfAAMSAAkKvCPmGQAzAwASAAkKzyHmGQAzAwAZAAUK9SRMCAATAgAAAA==.Kelwynd:BAAANQAECgQIAgAAAA==.Keä:BAAANQAECgYICgAAAA==.',
Kh='Khasaziel:BAAANQADCgcIBwAAAA==.',
Ki='Kirean:BAABNQAECoEZAAIJAAcKphToIACBAQAJAAcKphToIACBAQAAAA==.',
Ko='Kobesama:BAAANQAECgYIEgAAAA==.Kodask:BAAANQADCgYICwAAAA==.Kodera:BAABNQAECoEYAAMaAAcKshHTCACkAQAaAAcKshHTCACkAQAOAAIKWgb9LQBfAAAAAA==.Konata:BAAANQADCggIDwABNQAECgcIGQAJAPwZAA==.Korbenzoo:BAAANQADCgMIBAABNQAECgUIDgAGAAAAAQ==.Korigan:BAAANQADCgEIAQAAAA==.',
Kr='Krom:BAAANQADCggICAABNQAECggIEQAGAAAAAA==.Kryssie:BAABNQAECoEaAAIBAAgKNRRkTAA8AgABAAgKNRRkTAA8AgAAAA==.',
Ku='Kuroku:BAAANQADCgUIBQAAAA==.',
Kw='Kwaili:BAAANQAECgYIEgAAAA==.',
La='Lanaya:BAAANQAECgUICQAAAA==.Laserheadten:BAABNQAECoEfAAIbAAkKbRriDwDCAgAbAAkKbRriDwDCAgAAAA==.Laudna:BAAANQADCgcIBwABNQAECgQIBQAGAAAAAA==.Lawrensce:BAAANQAECgQIBwAAAA==.',
Le='Lencho:BAAANQAECgIIBAAAAA==.Lenchodude:BAAANQAECgIIAgAAAA==.Lenian:BAAANQAECgIIAwAAAA==.Leâfs:BAAANQAECgQIBQAAAA==.',
Li='Lirrael:BAAANQADCgEIAQAAAA==.Litesout:BAAANQAECgMIAwAAAA==.',
Lo='Loghyn:BAAANQAECgIIAgAAAA==.Loreck:BAAANQAECgMIAwAAAA==.Lorlea:BAAANQADCgMIAwABNQADCgQJBAAGAAAAAA==.Lourom:BAAANQAECgUJBgAAAA==.',
Lu='Lunarcateyes:BAAANQADCgYIBgAAAA==.Lunariel:BAAANQAECgQIBAAAAA==.',
Ly='Lyraae:BAABNQAECoEUAAIHAAYKvhI5dQBUAQAHAAYKvhI5dQBUAQAAAA==.',
Ma='Mackas:BAAANQADCgYICAAAAA==.Magicbeer:BAAANQADCgYIDQAAAA==.Maidenofhate:BAABNQAECoElAAIBAAkKAhkNJgDFAgABAAkKAhkNJgDFAgAAAA==.Maiganoss:BAAANQAECgQIAgAAAA==.Makeloa:BAAANQADCgUICQAAAA==.Mardon:BAAANQABCgYICwABNQABCgcIDgAGAAAAAA==.Marsiel:BAAANQADCgcIDgAAAA==.Maxxwell:BAAANQAECgUIBgAAAA==.',
Mc='Mcpunch:BAAANQADCgMIAwAAAA==.',
Me='Megid:BAABNQAECoEUAAIJAAYKlR3oFgDvAQAJAAYKlR3oFgDvAQAAAA==.Mestopheles:BAAANQAECgcIEAABNQAECggICQAGAAAAAA==.Mezsiah:BAAANQAECgIIAwABNQAECgcIGwAVAP0EAA==.',
Mi='Midianite:BAAANQADCgMIAwAAAA==.Mimiru:BAAANQADCgYIBgAAAA==.Minié:BAAANQAECgMIBAAAAA==.Mizblumkin:BAAANQAECgMIAwAAAA==.',
Mo='Monkies:BAAANQADCggIDQAAAA==.Montey:BAAANQADCgMIAwAAAA==.Moonnshine:BAABNQAECoEaAAMVAAgKIAVhUgBBAQAVAAgKIAVhUgBBAQAWAAYKXwJSQAC8AAAAAA==.Moonrend:BAAANQADCgQIBQAAAA==.Moonzire:BAAANQADCgYIBgAAAA==.',
Mu='Murgrot:BAAANQADCgQIBAAAAA==.',
My='Mylittlepwni:BAAANQADCgcIGAAAAA==.',
['Mä']='Mälcharion:BAAANQADCgcJBwAAAA==.',
Na='Nainel:BAAANQADCgMIAwABNQAECgIIAwAGAAAAAA==.Nakros:BAAANQAECgUJBgAAAA==.Nathelezet:BAAANQADCgQJBAABNQAECgIIAwAGAAAAAA==.',
Ne='Neloria:BAAANQADCgEIAQAAAA==.Nemonas:BAAANQADCggIHAAAAA==.Nerik:BAAANQADCgYICAAAAA==.Nerissa:BAEANQAECggICAAAAA==.Netallia:BAAANQABCgcIEAAAAA==.',
Ng='Ngyue:BAAANQADCgYJJAAAAA==.',
Ni='Niala:BAAANQADCgUIBQAAAA==.Nianna:BAABNQAECoEUAAIBAAYK+xf4dgDEAQABAAYK+xf4dgDEAQAAAA==.Nickto:BAAANQAECgIIAwAAAA==.Nightshayed:BAAANQADCgcIDAAAAA==.',
Nu='Nubin:BAAANQAECgEIAQAAAA==.Numbed:BAAANQADCggICAAAAA==.',
Ny='Nytwalker:BAAANQAECgMIAwAAAA==.Nyårlåthôtêp:BAAANQAECgEJAQAAAA==.',
Og='Ogbruced:BAAANQADCgYIBQABNQAECgUIBwAGAAAAAA==.',
Op='Opalla:BAAANQADCggIHAAAAA==.',
Or='Orceo:BAAANQADCggIGQAAAA==.Orcrest:BAAANQADCgcIGAAAAA==.Ororo:BAABNQAECoEiAAIcAAgKbhdvNwBSAgAcAAgKbhdvNwBSAgAAAA==.',
Pa='Palal:BAAANQADCgcIBwABNQAECgQIBQAGAAAAAA==.Paryah:BAAANQAECgIIAwAAAA==.Pauken:BAAANQAECgUIBQABNQAECggIEAAGAAAAAA==.',
Ph='Phanceester:BAAANQADCgcIFAAAAA==.Phindra:BAAANQADCgYIBwAAAA==.Phréek:BAABNQAECoEWAAMQAAgK7xoLKQCOAgAQAAgK7xoLKQCOAgAFAAEKBRdQOwFBAAAAAA==.',
Pl='Plants:BAAANQAECgMIAwAAAA==.Plethknight:BAAANQAECgUIDAABNQAFFAQIEgAJABELAA==.',
Po='Poetea:BAAANQADCgEIAQAAAA==.',
Pr='Praze:BAAANQADCgcIGQAAAA==.',
Pu='Puogh:BAAANQABCgIIAgAAAA==.Puoh:BAAANQABCgYIBwAAAA==.Pustülio:BAAANQADCggICAAAAA==.',
Pw='Pwough:BAAANQABCggJCgAAAA==.',
Ra='Raeztharion:BAAANQADCgYIBgAAAA==.Raha:BAAANQADCgYIBgAAAA==.Rahis:BAABNQAECoEaAAMBAAgKpBIMSwBAAgABAAgKpBIMSwBAAgANAAEKeANdbwAyAAAAAA==.Raiu:BAAANQAECgIIAwAAAA==.Ramsis:BAABNQAECoEVAAIHAAgKaxsYLwBjAgAHAAgKaxsYLwBjAgAAAA==.Randir:BAABNQAECoEdAAIbAAkKrhT8FAB4AgAbAAkKrhT8FAB4AgAAAA==.Ranir:BAAANQADCgcIEwAAAA==.Rath:BAAANQAECgUIDwAAAA==.',
Re='Rebarka:BAAANQAECgEIAQAAAA==.Rebrewke:BAAANQAECgMIBAAAAA==.Remedivhs:BAAANQADCgEJAQABNQAECgUIDgAGAAAAAQ==.Rettbull:BAAANQADCgMIAwAAAA==.Revy:BAAANQAECgQIBAAAAA==.',
Rh='Rhiannonage:BAAANQAECgQICQAAAA==.Rhyli:BAAANQADCgMIAwAAAA==.',
Ro='Robinhoodx:BAABNQAECoEYAAIBAAcKhByyUgApAgABAAcKhByyUgApAgAAAA==.Roenabur:BAAANQADCgcIDAAAAA==.Romok:BAAANQADCgcIGAAAAA==.',
Ru='Rubysunday:BAAANQADCggIGQAAAA==.',
Ry='Rykarranger:BAAANQADCgQIBAAAAA==.',
['Rì']='Rìseandemìse:BAAANQABCgEIAQAAAA==.',
Sa='Sacrìfice:BAAANQAECgUIEAAAAA==.Samoot:BAABNQAECoEbAAIVAAcK/QSZVgAqAQAVAAcK/QSZVgAqAQAAAA==.Sarreus:BAAANQADCgQICwABNQAECgUIDgAGAAAAAQ==.',
Se='Sepharim:BAAANQADCgQIBwAAAA==.',
Sh='Shael:BAAANQAECgIIAwAAAA==.Shamanstein:BAEANQADCggJDwABNQAFFAUIDAAFAM8YAA==.Shammbo:BAAANQAECgIIAwABNQAECgcIDwAGAAAAAA==.Sharty:BAAANQAECggICwAAAA==.Sheriruth:BAAANQADCggICAABNQAECggIEAAGAAAAAA==.Shortigen:BAAANQADCgcIGAAAAA==.Shrilynda:BAAANQADCgUIBwAAAA==.Shupala:BAAANQAECgIIBAAAAA==.',
Si='Sicnus:BAAANQADCgcICQAAAA==.Sinadin:BAABNQAECoEcAAIFAAcKThEHkwCTAQAFAAcKThEHkwCTAQAAAA==.',
Sk='Skiltroth:BAAANQADCgYIBgABNQAECggIFwATALkIAA==.Skolmaster:BAAANQAECgQIBAAAAA==.Skootter:BAAANQADCgYJBwAAAA==.Skyfury:BAAANQAECgQIBgABNQAECgQIDQAGAAAAAA==.',
Sm='Smarky:BAAANQAECggIAgAAAA==.Smâlls:BAEANQAECgQIBgAAAA==.',
Sn='Sneekiemage:BAAANQADCggICAAAAA==.Snugz:BAAANQADCggICAAAAA==.',
So='Sourdiesel:BAAANQADCggIGwAAAA==.Southsound:BAAANQAECgQIEAABNQAECgcICAAGAAAAAA==.',
Sp='Spewak:BAAANQADCgQIBAABNQADCgYIBgAGAAAAAA==.',
St='Stallos:BAAANQADCgQIBAAAAA==.Stark:BAAANQADCggJDAAAAA==.Starmie:BAAANQADCgcIBwAAAA==.Steakknife:BAAANQAECgcJDAAAAA==.Stormoon:BAAANQAECgUIDAAAAA==.Sturma:BAAANQAECgQICQAAAA==.',
Su='Superrad:BAAANQADCgcIFQAAAA==.',
Sw='Swayla:BAAANQADCgUIBwAAAA==.Sweatyhog:BAAANQADCggIHAAAAA==.',
Sy='Sybil:BAAANQAECgQIBAAAAA==.',
['Sà']='Sàlvage:BAAANQADCggICAAAAA==.',
['Sí']='Sínner:BAAANQADCgIIAgAAAA==.Síràmõõn:BAAANQADCgUIBQAAAA==.',
Ta='Tahfyn:BAAANQAECgIIAwAAAA==.Tahtiania:BAAANQADCgYIFQAAAA==.Tamarin:BAAANQADCgEIAQAAAA==.Tasdarazen:BAAANQADCgYIDAAAAA==.Tazedtilblue:BAAANQADCgYIDwAAAA==.',
Te='Ted:BAAANQAECggIAgAAAA==.Telysse:BAAANQAECgYIBgAAAA==.Teo:BAABNQAECoEUAAIBAAYKGQ4ekwB8AQABAAYKGQ4ekwB8AQAAAA==.Teyamat:BAAANQAECgUICQABNQAECgYIBgAGAAAAAA==.',
Th='Thalumind:BAAANQADCgYICgAAAA==.Thelock:BAABNQAECoEfAAMHAAkKnRqoHgC8AgAHAAkKnRqoHgC8AgAcAAMKbBA3wAC0AAAAAA==.Thetree:BAABNQAECoEnAAMWAAkKrRsxDQDEAgAWAAkKrRsxDQDEAgAVAAcKEhyULgAlAgAAAA==.Thien:BAAANQADCgUIBQAAAA==.Thoinus:BAAANQAECgEJAQABNQAECggIFwATALkIAA==.Thoughtcrime:BAAANQADCggIEQAAAA==.Thundertaco:BAAANQADCggICAAAAA==.Thundertwig:BAAANQAECgYIEQAAAA==.',
Ti='Timoris:BAAANQAECgIIAgABNQAECggIEAAGAAAAAA==.',
To='Tobiume:BAAANQAECgIIAgABNQAECgkJHQAIAAIUAA==.Tofulhundun:BAAANQAECgEIAQAAAA==.Toggo:BAAANQADCgQIBQAAAA==.Tommytwotusk:BAAANQAECgUIBwAAAA==.',
Tr='Traladin:BAAANQAECgEIAQAAAA==.Trenon:BAAANQAECgEIAQAAAA==.Triannah:BAAANQAECgIIBgAAAA==.Trildjr:BAAANQAECgIIAwAAAA==.',
Tu='Tuchmi:BAAANQADCgYIBgAAAA==.Tuldag:BAABNQAECoEaAAIcAAgKLwTrgQBJAQAcAAgKLwTrgQBJAQAAAA==.',
Ty='Tyronda:BAAANQADCgcIEwAAAA==.Tyrse:BAAANQAECgQIBQAAAA==.',
Tz='Tzerina:BAAANQAECgIIBAAAAA==.',
['Tâ']='Tânkyû:BAAANQADCgUIBQAAAA==.',
['Tï']='Tïmbits:BAAANQAECgIIAgAAAA==.',
Ut='Uthadravis:BAAANQAECgUIDQABNQAECgUIDgAGAAAAAQ==.',
Va='Vaelwyn:BAAANQADCggIDgAAAA==.Valegion:BAAANQADCgMJAwAAAA==.Valerina:BAAANQADCgQJBAAAAA==.Valford:BAAANQAECgUIDAAAAA==.Validan:BAAANQAECgEIAQAAAA==.Valkriss:BAAANQADCgMIAwAAAA==.Vallyrie:BAABNQAECoEgAAMCAAgKOhP8RwCQAQACAAcK1xP8RwCQAQADAAcKUg8aTACCAQAAAA==.Valssharess:BAAANQAECgQIBgAAAA==.Valth:BAAANQADCgcIGQAAAA==.Valzen:BAAANQADCgEIAQAAAA==.Vanae:BAAANQADCgUJBQAAAA==.Vanargandr:BAAANQADCgMIAwABNQADCgYIBgAGAAAAAA==.Vaporgriffin:BAAANQAECgQIBQAAAA==.Vaporhunt:BAAANQADCgIIAgAAAA==.Varthric:BAAANQADCgMIAwAAAA==.',
Ve='Velendez:BAAANQADCgcIFQAAAA==.Veleria:BAABNQAECoEbAAMQAAgKqBhhNQBTAgAQAAgKqBhhNQBTAgAJAAUKPBQULAAiAQAAAA==.Vellysonna:BAAANQAECgEIAQAAAA==.Ventessa:BAAANQADCgYICgAAAA==.Versatina:BAAANQADCgcIFwAAAA==.',
Vi='Victra:BAAANQAECgUIBwAAAA==.Viirnald:BAEANQADCgcIDQAAAA==.Vikingbeast:BAAANQABCgUJBgAAAA==.Viko:BAAANQAECgQIBAAAAA==.Vinaya:BAAANQADCgcIGQAAAA==.Vindicta:BAAANQAECgEIAQABNQADCgEIAQAGAAAAAA==.',
Vo='Volthemar:BAABNQAECoEbAAMSAAgKBiHBNAC7AgASAAgKLh7BNAC7AgAdAAQK1hxGGgAyAQAAAA==.Voodoopunch:BAAANQABCgUIBwAAAA==.',
Vy='Vynll:BAAANQADCgIJAgAAAA==.',
Wa='Warrpath:BAAANQADCgEIAQAAAA==.Watsuki:BAAANQADCgcIDAABNQAECgIIAwAGAAAAAA==.',
We='Weoo:BAAANQAECgEIAQAAAA==.Werrick:BAAANQAECgYIEQAAAA==.',
Wh='Whitespot:BAAANQADCgcIFAAAAA==.',
Wi='Wilson:BAAANQADCgQIBAABNQAECgIIAwAGAAAAAA==.Wisegurl:BAAANQAECgUICAAAAA==.',
Wo='Woodpecker:BAABNQAECoEWAAIVAAcKGQ8RRACSAQAVAAcKGQ8RRACSAQAAAA==.',
Wr='Wreckreation:BAAANQAECgIIBgAAAA==.',
Wy='Wylecsham:BAAANQADCgUJBQAAAA==.Wylectra:BAABNQAECoEZAAITAAcKHQ1VagB1AQATAAcKHQ1VagB1AQAAAA==.',
Xe='Xethos:BAAANQADCgQIBAAAAA==.',
Ya='Yanikå:BAAANQADCgQICAAAAA==.',
Ye='Yeira:BAABNQAECoEbAAMBAAgKLg0iYgD8AQABAAgKLg0iYgD8AQANAAEKWgCbfAAPAAAAAA==.Yerdedmatey:BAAANQAECgEIAQAAAA==.',
Yo='Yourdemon:BAAANQAECgIIAgAAAA==.',
Za='Zagasham:BAABNQAECoEaAAIHAAgKJxq6MgBRAgAHAAgKJxq6MgBRAgAAAA==.Zahvaria:BAAANQAECgEIAgAAAA==.Zalson:BAAANQABCgYJBgAAAA==.Zamari:BAAANQADCgMIAwABNQAECgEIAgAGAAAAAA==.Zaphiell:BAAANQAECgcIEAAAAA==.',
Ze='Zeid:BAAANQAECggIEwAAAA==.Zev:BAAANQADCgcIGAAAAA==.',
Zi='Zillz:BAAANQADCgYIDAAAAA==.Zinderalanot:BAAANQAECgUIDgAAAQ==.',
Zl='Zlightnin:BAAANQADCgUICAAAAA==.',
Zo='Zoeystorm:BAAANQAECgQIDgAAAA==.Zoeythunder:BAAANQABCgYICwAAAA==.',
Zu='Zuldrak:BAAANQAECgcIEQAAAA==.',
Zy='Zykie:BAAANQADCgcIBwAAAA==.',
['Ìn']='Ìnferior:BAAANQADCgYIBgAAAA==.',
['Ðè']='Ðèáth:BAAANQADCgYIBgAAAA==.',
['Öm']='Ömenjr:BAABNQAECoEbAAQBAAgKhRfFPQBqAgABAAgKhRfFPQBqAgANAAEK6AWicAAxAAAKAAEKKwXOEAAoAAAAAA==.',
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
