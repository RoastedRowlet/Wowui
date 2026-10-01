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

local lookup = {'Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','DemonHunter-Vengeance','Warrior-Arms','Monk-Windwalker','Hunter-Marksmanship','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','Rogue-Assassination','DeathKnight-Blood','DeathKnight-Frost','Hunter-Survival','Warlock-Affliction','Warlock-Destruction','Monk-Brewmaster','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Rogue-Outlaw','Paladin-Protection','Druid-Balance','Warlock-Demonology','DemonHunter-Devourer','Paladin-Holy','Mage-Arcane','Mage-Frost','DemonHunter-Havoc','Rogue-Subtlety','Warrior-Fury','Druid-Guardian','Shaman-Enhancement','Priest-Discipline',}
local provider = {region='US',realm='Darkspear',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abssorath:BAAANQADCgYIBgAAAA==.',
Ae='Aerouant:BAABNQAECoEeAAMBAAkKiBZcBQBLAgABAAkKiBZcBQBLAgACAAEK5AyIMgA5AAAAAA==.',
Ai='Aidix:BAAANQADCggIFQAAAA==.Aimassist:BAAANQAECgQIBAAAAA==.',
Al='Alaliix:BAAANQADCgEIAQAAAA==.Alcyone:BAABNQAECoEcAAIDAAgKyxkBFABkAgADAAgKyxkBFABkAgAAAA==.Allophone:BAAANQADCgIIAgAAAA==.Almightyhunt:BAAANQADCgMIAwAAAA==.Altimys:BAAANQADCgIIAgAAAA==.',
An='Annarchy:BAAANQADCgQIBAAAAA==.Antakata:BAAANQADCgcIBwAAAA==.Antapathy:BAABNQAECoEcAAIEAAgKqBX3CAADAgAEAAgKqBX3CAADAgAAAA==.Anthross:BAAANQAECgYIDgAAAA==.',
Ap='Apollovon:BAABNQAECoEbAAIFAAgKNiEfIwAGAwAFAAgKNiEfIwAGAwAAAA==.Applebees:BAAANQAECgEIAQAAAA==.',
Ar='Arcanenug:BAAANQADCgQJBAAAAA==.Arcbnonez:BAAANQAECgQIBAAAAA==.Armiggy:BAABNQAECoEcAAIGAAgKNxGSIADNAQAGAAgKNxGSIADNAQAAAA==.Aro:BAACNQAFFIEMAAMHAAUKFiD2CABoAQAHAAQKaSD2CABoAQAIAAIK7xgaFACyAAA1AAQKgR8AAwcACQreJFoZAFgCAAcABwouIVoZAFgCAAgABgotIdxnAOwBAAAA.Arrowraen:BAABNQAECoEaAAIIAAgK9CQ8DABaAwAIAAgK9CQ8DABaAwAAAA==.',
As='Asd:BAAANQADCgQIBAAAAA==.Asecond:BAAANQADCgYJBgAAAA==.',
Au='Audomere:BAAANQAECgcIEQAAAA==.Auurwarr:BAAANQAECgUIBQAAAA==.',
Av='Avawrath:BAAANQAECggICQAAAA==.Avraellia:BAAANQADCgYIBQAAAA==.',
Az='Azkaellon:BAAANQADCgQIBAABNQAECggIGwAEADUSAA==.',
Ba='Bagool:BAAANQADCgYIBgAAAA==.Bailey:BAAANQADCgIIAgABNQAECgIIAgAJAAAAAA==.Ballstench:BAAANQADCgIIAgAAAA==.Barbåtos:BAAANQADCggIFwAAAA==.Baskthyr:BAAANQADCgQIBAAAAA==.Bathory:BAAANQADCgYIBgAAAA==.',
Be='Bearboi:BAAANQAECgUJDQABNQADCgUIBQAJAAAAAA==.Bearbomblolz:BAAANQADCgMIBAABNQAECgMIBAAJAAAAAA==.Bearmanakin:BAAANQADCgYICQAAAA==.Bearypotter:BAAANQADCgQICAAAAA==.Beastbane:BAAANQAECggIAQAAAA==.Beastly:BAAANQAECgIJBAAAAA==.Beastmandes:BAAANQADCggIFAAAAA==.Bejeezus:BAABNQAECoEdAAIFAAgKYRe1VwBAAgAFAAgKYRe1VwBAAgAAAA==.Bel:BAAANQABCgYIDAAAAA==.Bellion:BAABNQAECoElAAIKAAgK4hdeKQA+AgAKAAgK4hdeKQA+AgAAAA==.Berijar:BAAANQADCgYIBgABNQAECgIIAgAJAAAAAA==.Bewslee:BAAANQAECgEIAgAAAA==.Bexx:BAAANQADCggJGQAAAA==.',
Bi='Biblehumping:BAABNQAECoEeAAMLAAgKRRcaOABDAgALAAgKRRcaOABDAgAMAAYKjgrJMwAwAQAAAA==.Bietk:BAAANQADCgQIBwABNQAECgYIDwAJAAAAAA==.Bigbonks:BAAANQAECgQIBgAAAA==.Bigoldpumper:BAAANQAECgEIAQAAAA==.',
Bl='Blackplague:BAAANQADCgQIBQAAAA==.Bleaknight:BAAANQADCgUIBQAAAA==.Blessedbuns:BAAANQAECggICwAAAA==.Blueshamoo:BAAANQAECgEJAQAAAA==.Blãezer:BAAANQADCggIEAAAAA==.',
Bo='Bonex:BAAANQAECgEIAgAAAA==.Boomshroom:BAAANQADCgIIAgABNQAECgkJHwAGAKIaAA==.Bootsie:BAAANQADCggICAAAAA==.',
Br='Brewtoe:BAAANQAECgQIBAAAAA==.Brisketz:BAAANQADCgUIAQAAAA==.Bruneau:BAAANQABCgUIBQAAAA==.',
Bs='Bshoutbot:BAAANQADCgUIBQABNQAFFAYIEQAHAOQZAA==.',
Bu='Bubblemehard:BAAANQAECgYIDwAAAA==.',
By='Byahnbreath:BAAANQAECgcICQAAAA==.',
Ca='Cakeiko:BAAANQADCgMIAwAAAA==.Cannabinoide:BAAANQAECgIIAgAAAA==.Cannatonic:BAAANQAECgEIAQAAAA==.Casmiralda:BAAANQABCgUIBQAAAA==.Castielx:BAABNQAECoEZAAINAAcKnRKNKADiAQANAAcKnRKNKADiAQAAAA==.Catnips:BAAANQADCgIJAgABNQAECggIHgALAEUXAA==.',
Ce='Celestraza:BAAANQADCggIFgAAAA==.Celirra:BAABNQAECoEcAAIKAAgKASEmGgCvAgAKAAgKASEmGgCvAgAAAA==.Cennerus:BAAANQADCgIIAwAAAA==.',
Ch='Chaosreign:BAAANQADCggICwAAAA==.Cheekybaby:BAAANQAECgYIDgAAAA==.Cherrypoplol:BAAANQADCgUIDAAAAA==.Chocopaati:BAAANQAECgYIEgAAAA==.Chokma:BAAANQAECgYIBwAAAA==.Chunkyfists:BAAANQADCgMIAwAAAA==.Chëeks:BAAANQADCgUIBQAAAA==.Chìefponbury:BAAANQADCggIGgAAAA==.',
Ci='Cinnaa:BAAANQAECgUICQAAAA==.',
Cl='Clawdog:BAAANQADCgIIAgABNQAECgIIAgAJAAAAAQ==.Clawwz:BAAANQAECgEIAQAAAA==.Cleisthenes:BAAANQAECgEIAQAAAA==.Clors:BAAANQAECgYIDwAAAA==.',
Co='Conflux:BAAANQADCggIFAAAAA==.',
Cr='Crawlah:BAAANQADCggICAAAAA==.Crazegideon:BAAANQABCgIIAgAAAA==.Crazespawnz:BAAANQABCgIIAgAAAA==.Cruelbeam:BAAANQADCgQIBAAAAA==.',
Cu='Curzondax:BAAANQAECggIEQAAAA==.',
Cy='Cyberfairy:BAAANQAECgEJAQAAAA==.Cyphinx:BAAANQAECgUIBQAAAA==.',
['Câ']='Câraxes:BAAANQADCgUIBAAAAA==.',
['Cä']='Cät:BAAANQAECgEIAQAAAA==.',
Da='Dahelzforyou:BAAANQADCgcICAAAAA==.Dalìnar:BAAANQAECgQICQAAAA==.Damadafacker:BAAANQAECgcJDQAAAA==.Darkclôud:BAAANQAECgQIBAAAAA==.Darklia:BAAANQAECgQIBwAAAA==.Darthjae:BAABNQAECoEyAAMOAAcKMhmqOgDZAQAOAAcKMhmqOgDZAQAPAAEKcAUjjwAiAAAAAA==.Darthmikkey:BAAANQADCgYIBgAAAA==.Darthrakk:BAABNQAECoEbAAIQAAgK8hhvAwCRAgAQAAgK8hhvAwCRAgAAAA==.Davina:BAAANQADCgcJBwABNQAECgcICgAJAAAAAA==.Daykwan:BAAANQAECggICAAAAA==.Daïn:BAAANQAECgYICgAAAA==.',
De='Deadestmoonb:BAAANQADCgIJAgAAAA==.Deathalimon:BAABNQAECoEkAAQOAAgKZhdEPgDGAQAOAAcKthZEPgDGAQAKAAQKThHBbgDsAAAPAAEKoAzyhgAvAAAAAA==.Deepdeath:BAABNQAECoEyAAIFAAgKziJeJQD9AgAFAAgKziJeJQD9AgAAAA==.Degion:BAAANQADCgEIAQAAAA==.Deltonn:BAAANQADCgUIBQAAAA==.Demonarian:BAAANQAECgYICAABNQAECggIJAAOAGYXAA==.Demonpotato:BAAANQADCggJCAAAAA==.Denardath:BAAANQADCgEIAQAAAA==.Denerrollin:BAAANQADCgIIAgAAAA==.Depthcharge:BAAANQAECgQJCQAAAA==.Deroc:BAAANQAECgQIBgAAAA==.Deáthtáxi:BAAANQAECggICAAAAA==.',
Di='Dinfarmer:BAAANQADCgcIDAAAAA==.Dirtycheese:BAAANQAECgUICwAAAA==.',
Dj='Djgha:BAAANQAECgEIAQAAAA==.',
Dm='Dmptrukdonna:BAAANQADCgEIAQAAAA==.',
Do='Dogfärts:BAAANQADCgYIEwAAAA==.Dorunter:BAABNQAECoEaAAMHAAcKnxEIKgCqAQAHAAcK6hAIKgCqAQAIAAEKsRT3CAFPAAAAAA==.Dottíe:BAAANQADCgQIBAAAAA==.Doubledosage:BAAANQAECgUICQAAAA==.',
Dr='Dragonbnonez:BAAANQAECgQIBAAAAA==.Dragonforge:BAAANQADCgYIDQAAAA==.Drakujin:BAAANQADCgMIBQAAAA==.Drboomboom:BAAANQAECgIIAgAAAA==.Drdoitall:BAAANQAECgYICwAAAA==.Dreadnpain:BAAANQADCgEIAQAAAA==.Dreynick:BAAANQADCgQIBAAAAA==.Dripfarming:BAAANQAECgMIAwABNQAFFAYIEAAPABEeAA==.Drnastea:BAAANQADCgYIBgAAAA==.Drstorm:BAAANQADCgYICwAAAA==.',
Ed='Edaladalrian:BAAANQADCgUIBQAAAA==.',
El='Ella:BAAANQADCgIIAgAAAA==.Elysiá:BAAANQADCggICAAAAA==.',
En='Enhydra:BAAANQADCggICwAAAA==.Enough:BAAANQADCgcIDAAAAA==.',
Eq='Eqv:BAABNQAECoEcAAMRAAkKRSQtAgDUAgARAAcK1CQtAgDUAgASAAIKUCJrOgDDAAAAAA==.',
Er='Ericolson:BAAANQAECgUIEQAAAA==.Erze:BAAANQAECgQIBAAAAA==.Erôman:BAAANQADCgQIBAAAAA==.',
Ev='Evosolz:BAEANQADCggIDgABNQAECgQJBgAJAAAAAA==.Evé:BAAANQAECgMIAwABNQAECgkJHwAGAKIaAA==.',
Ez='Ezzartkal:BAAANQADCgUIBQAAAA==.',
Fa='Faeloria:BAAANQABCgcICwAAAA==.Farmerdragon:BAAANQADCggIDgAAAA==.Favabean:BAAANQADCgUIBQABNQAECgcIMgAOADIZAA==.',
Fe='Feathring:BAAANQADCgYIBgABNQAECggIHAATAEAhAA==.Fefra:BAAANQADCgQIBAAAAA==.Felicious:BAAANQAECgcICAAAAA==.Fengshui:BAAANQADCggIGwAAAA==.Feralco:BAAANQADCgYIBgAAAA==.Fertra:BAAANQADCgYIBgAAAA==.',
Fh='Fhedrah:BAAANQADCgEIAgAAAA==.',
Fi='Fiz:BAAANQADCgYIBgAAAA==.',
Fl='Flashdance:BAAANQADCgcIBwAAAA==.Fleepo:BAAANQAECgIIAwABNQAECggICgAJAAAAAA==.Fleshnbones:BAAANQADCgEIAQAAAA==.Flourie:BAABNQAECoEcAAMUAAgKxAuWHQCwAQAUAAgKxAuWHQCwAQACAAEK2weRNQAvAAAAAA==.Flyhawk:BAAANQADCgUJEQAAAA==.Flöör:BAAANQADCgUJBQAAAA==.',
Fu='Fullmetal:BAAANQABCgIIAgAAAA==.Funkadelfic:BAAANQAECgUIBwAAAA==.',
['Fé']='Fénrír:BAAANQADCggIDwABNQAECgYIEAAJAAAAAA==.',
['Fò']='Fòxxy:BAAANQAECgEJAQAAAA==.',
Ga='Galadri:BAABNQAECoEZAAMVAAgK/BulLABvAgAVAAgK/BulLABvAgAWAAUKWhCilQAXAQAAAA==.Garu:BAAANQADCgIIAgAAAA==.',
Ge='Geared:BAAANQAECgcIEAAAAA==.Geartryx:BAAANQADCggIDQAAAA==.',
Gh='Ghoshshadow:BAAANQADCgYIDAAAAA==.Ghostinz:BAAANQADCgcIDwAAAA==.',
Gi='Gimpripper:BAAANQADCggJEgAAAA==.Giztron:BAAANQADCgYIDgAAAA==.',
Gl='Glitterp:BAAANQADCgQIBAABNQAECggJIAAOANoZAA==.Globalcold:BAABNQAECoEYAAIFAAgK8BkGTQBkAgAFAAgK8BkGTQBkAgAAAA==.Globb:BAABNQAECoEtAAIFAAgKWRUebwD4AQAFAAgKWRUebwD4AQAAAA==.Globius:BAABNQAECoEYAAIXAAgKKR6mOwCbAgAXAAgKKR6mOwCbAgAAAA==.Gloriouscole:BAAANQAECgQICAAAAA==.Glower:BAAANQADCgEIAQAAAA==.',
Go='Gonkz:BAAANQAECgQIBgAAAA==.',
Gr='Greekorc:BAAANQABCgYJBwAAAA==.Greenyheals:BAAANQADCgUIBQAAAA==.Grimby:BAAANQAECgIIAQAAAA==.Grimdisney:BAAANQADCggIDgAAAA==.Gromol:BAAANQADCggJHQAAAA==.Grumby:BAAANQADCggICAAAAA==.',
Gu='Guifu:BAAANQADCgIIAgAAAA==.',
Gw='Gwendolÿn:BAAANQADCgUIBgAAAA==.',
['Gê']='Gêralt:BAAANQADCgQIBAAAAA==.',
Ha='Hacknhaf:BAAANQADCgYIDAAAAA==.Hakubar:BAAANQAECgMJAwAAAA==.Hatebrêêd:BAAANQADCgQIBQAAAA==.',
He='Healman:BAAANQADCgYIEgAAAA==.Healsatute:BAAANQADCgMIAwAAAA==.Healylady:BAAANQADCgcIDAAAAA==.Heiden:BAAANQADCgYJBgAAAA==.Hel:BAAANQADCgUIDgAAAA==.Hellyas:BAAANQAECgQIBAAAAA==.Herbs:BAAANQADCgUIBQABNQAECggIHAAYAIMYAA==.Herenorthere:BAABNQAECoEhAAMMAAgKixhZIwDIAQAMAAYKdxtZIwDIAQALAAQK8BnMewA1AQABNQAECgkJIwASAAYZAA==.Hermippe:BAAANQAECgMJAwAAAA==.Hexstraits:BAABNQAECoEdAAIOAAkKEh9mDwAOAwAOAAkKEh9mDwAOAwAAAA==.',
Hi='Hia:BAACNQAFFIELAAIOAAQKOhQTDAAvAQAOAAQKOhQTDAAvAQA1AAQKgSUAAg4ACQp5HYkUANsCAA4ACQp5HYkUANsCAAAA.Highriskbr:BAAANQAECggICAAAAA==.Hitlist:BAAANQADCgUJBQAAAA==.',
Ho='Holycow:BAAANQAECgEIAQAAAA==.Holyfits:BAAANQADCgEIAQAAAA==.Hondacervix:BAAANQAECgYIBgAAAA==.Hondaimpala:BAAANQAECgQIBgABNQAECgcIMgAOADIZAA==.Hoofmaster:BAAANQABCgIIAgAAAA==.Howardyou:BAAANQADCgEIAgAAAA==.',
Hu='Huffyy:BAAANQAECgQICAAAAA==.Huhdean:BAABNQAECoEaAAMPAAgK7iEnFwCLAgAPAAcKgCEnFwCLAgAKAAQKoR/EYAAlAQAAAA==.Hulxamus:BAAANQAECgYICgAAAA==.Hunterramen:BAAANQADCgEJAQAAAA==.Hunterz:BAAANQAECgQJCQAAAA==.',
['Hé']='Héåthcliff:BAABNQAECoEqAAMZAAkKTCI6BABOAwAZAAkKTCI6BABOAwAXAAEK3RDBOAFFAAAAAA==.',
Ic='Icyblaze:BAAANQAECggIEAAAAA==.',
Id='Idareu:BAAANQAECggIDgAAAA==.',
Il='Illumi:BAAANQADCgQIBwABNQAECgUICQAJAAAAAA==.',
Im='Immigrant:BAAANQADCggICAAAAA==.',
In='Indominus:BAAANQADCgIIAgAAAA==.',
Ir='Ires:BAAANQADCgUIBQAAAA==.',
Is='Ishadow:BAAANQAECgUIBgAAAA==.',
It='Itheusvalles:BAAANQADCggIEgAAAA==.Itsjerry:BAAANQADCgYICQAAAA==.',
Iw='Iwillcrushyo:BAAANQAECgEIAQAAAA==.',
Ja='Jainalynn:BAAANQADCgUIEgAAAA==.Jalenbrunson:BAAANQADCgEIAQAAAA==.Jazira:BAAANQAECgcIDwAAAA==.',
Jd='Jdarkside:BAAANQAECgIIAgAAAA==.',
Je='Jeremmiah:BAAANQADCgcIEQAAAA==.',
Jh='Jhacobo:BAABNQAECoEZAAIaAAgKKhcyKgBHAgAaAAgKKhcyKgBHAgAAAA==.',
Jo='Jojupobu:BAAANQADCggICAAAAA==.Jorkinit:BAAANQAECgcIEQAAAA==.',
Jr='Jragon:BAABNQAECoEYAAIbAAcKTwjkigBnAQAbAAcKTwjkigBnAQAAAA==.',
Ju='Judis:BAAANQABCgYICAAAAA==.Juicedh:BAAANQADCgUIBQAAAA==.Juicy:BAAANQAECggIEgAAAA==.Junipur:BAAANQAECgMICQAAAA==.',
Jx='Jxxy:BAABNQAFFIEIAAMIAAQKuxVdCwAcAQAIAAMKbhpdCwAcAQAHAAIKQgvNFACRAAABNQAFFAQKCAAIALsVAA==.',
['Jú']='Júnjúnwälä:BAAANQAECgYIEgAAAA==.',
Ka='Kalories:BAAANQAECgMJAwAAAA==.Kalvoid:BAAANQADCgUJBQABNQAECgMJAwAJAAAAAA==.Kandance:BAAANQAECgUIBQABNQAFFAIIAgAJAAAAAA==.Karlmagnus:BAAANQADCgcIBwAAAA==.',
Ke='Kelvintwo:BAAANQADCgQIAgAAAA==.',
Ki='Kimbopable:BAAANQADCgUICgABNQAECgcIMgAOADIZAA==.Kittyÿ:BAAANQAECgYICwAAAA==.',
Kn='Knurl:BAAANQADCgMIAwAAAA==.',
Ko='Korak:BAAANQADCgUIBQABNQADCgYIBgAJAAAAAA==.Korgh:BAAANQAECgEIAQAAAA==.Kozan:BAAANQADCgQIBAAAAA==.',
Kr='Krystall:BAABNQAECoEYAAIRAAgKqw3GBgD0AQARAAgKqw3GBgD0AQAAAA==.',
Ku='Kuarahy:BAAANQAECgcIEAAAAA==.Kunfugrip:BAABNQAECoEfAAIGAAkKohpNDwCzAgAGAAkKohpNDwCzAgAAAA==.Kurizmuh:BAAANQADCgUIBwAAAA==.',
['Kà']='Kàl:BAAANQADCgYJBwABNQAECgMJAwAJAAAAAA==.',
['Kã']='Kãl:BAAANQADCgYIBgABNQAECgMJAwAJAAAAAA==.',
La='Lanthos:BAABNQAECoEmAAIcAAkK+RrBDAD5AgAcAAkK+RrBDAD5AgAAAA==.Larthal:BAAANQAECgQIBAAAAA==.Latinpapi:BAABNQAECoEZAAIXAAkKiRBqYgAaAgAXAAkKiRBqYgAaAgAAAA==.',
Le='Leemiez:BAAANQADCgUIBQAAAA==.Leyära:BAAANQAECgIIAwAAAA==.',
Li='Lielys:BAAANQADCggICAABNQAECgMIBwAJAAAAAA==.Lilina:BAAANQAECgYIDQAAAA==.',
Lm='Lmn:BAAANQADCgUIBwAAAA==.',
Lo='Lonweh:BAAANQAECgIIAgAAAA==.Lousmage:BAAANQADCgUIBQAAAA==.Loza:BAAANQADCgQIBgABNQAECgUICgAJAAAAAA==.',
Lu='Lucith:BAABNQAECoEcAAIPAAgK6x8YEQDKAgAPAAgK6x8YEQDKAgAAAA==.Luckie:BAAANQABCgQIBwABNQAFFAUICQAdAM8LAA==.Lulafairy:BAAANQAECgEJAQAAAA==.Lumador:BAAANQAECgQIBQABNQAECgcIHQAMAIgXAA==.Lunatick:BAAANQAECggIDgAAAA==.Lunawa:BAACNQAFFIEIAAIeAAUKAhn4CwDQAQAeAAUKAhn4CwDQAQA1AAQKgTUAAx4ACQoJJhACAOQDAB4ACQoJJhACAOQDAB8AAwq1EXohAKAAAAAA.Lustbót:BAAANQAECggIEQAAAA==.Luvnrdjr:BAAANQADCgYIBgAAAA==.',
Ly='Lynnai:BAAANQADCgYIFgAAAA==.Lynxmi:BAAANQADCgEIAQAAAA==.Lyse:BAACNQAFFIEHAAIgAAQK+hi1BwBUAQAgAAQK+hi1BwBUAQA1AAQKgSMAAiAACQq8JckCALsDACAACQq8JckCALsDAAAA.',
['Lê']='Lêvak:BAAANQADCgIIAgAAAA==.',
['Lí']='Líllith:BAAANQADCgYJBgAAAA==.',
['Lô']='Lôuku:BAABNQAECoEcAAIbAAgKhBfWPABeAgAbAAgKhBfWPABeAgAAAA==.',
Ma='Maahn:BAAANQADCgcICAAAAA==.Macalob:BAAANQAECgQIBgAAAA==.Madallar:BAAANQAECgYIDAAAAA==.Magdagni:BAAANQAECgYICAAAAA==.Mageji:BAABNQAECoEtAAIeAAkKIiOnDQCSAwAeAAkKIiOnDQCSAwABNQADCgYIBgAJAAAAAA==.Magepies:BAAANQAECgQIBgABNQAECgQICAAJAAAAAA==.Magicfurry:BAAANQAECgUICgABNQAECggIHgALAEUXAA==.Malicelx:BAAANQAECgEIAQABNQAECggIGwAeAEIRAA==.Mallgoth:BAABNQAECoEVAAIIAAYKDgaSvgAZAQAIAAYKDgaSvgAZAQAAAA==.Manohar:BAABNQAECoEbAAMVAAgKgR4FKACHAgAVAAgKgR4FKACHAgAWAAIKzgwy3ABoAAAAAA==.Mardtard:BAAANQAECgQIBAABNQAECgUIBgAJAAAAAA==.Marximilian:BAAANQAECgMIAwAAAA==.',
Mc='Mcflurryz:BAAANQADCgUIBQAAAA==.Mcgrubert:BAAANQAECgIJAgABNQAECgkJJwAHADMeAA==.',
Me='Mechachad:BAAANQAECgMIAwAAAA==.Medlock:BAAANQADCgYICQAAAA==.Medmasters:BAAANQABCgIIAgAAAA==.Megamango:BAAANQADCggICAABNQAECgkJJQAfAL0kAA==.Mehiel:BAAANQAECgMIBQABNQAECgYIDwAJAAAAAA==.Merdune:BAAANQADCgEIAQAAAA==.Merkén:BAAANQADCgcIAwAAAA==.Metaloclypse:BAAANQADCgcIDgAAAA==.Mezaryn:BAAANQAECggICgABNQAECgkJGgADAB8FAA==.Mezzoo:BAABNQAECoEaAAIDAAkKHwXKPADTAAADAAkKHwXKPADTAAAAAA==.',
Mi='Midger:BAAANQADCgQIBAAAAA==.Millic:BAAANQAECgYIEgAAAA==.Millish:BAAANQADCgQIBAAAAA==.Minax:BAAANQAECgMIBAAAAA==.Missionsena:BAAANQAECgEJAQAAAA==.Mitzrael:BAAANQADCgIIAgAAAA==.',
Mo='Moozx:BAAANQAECgEIAQAAAA==.Morgannâ:BAAANQAECgIIAgAAAA==.Mosfeat:BAAANQADCggICAABNQAECggIDAAJAAAAAA==.',
Mu='Muckdile:BAAANQAECgQIBAAAAA==.Muckstab:BAAANQAFFAEIAQAAAA==.Mux:BAAANQADCggIDQAAAA==.',
Na='Narayeda:BAAANQAECgUICAAAAA==.Nasuadia:BAAANQADCggIGQABNQAECggIGAAPAD0VAA==.',
Ne='Nekkash:BAAANQAECgQIBAAAAA==.Neredir:BAAANQADCgYIBgAAAA==.Netoraresan:BAAANQAECggIAQAAAA==.Neytiri:BAAANQABCgQJBQAAAA==.Nezelle:BAAANQAECgUIBgABNQAECggIHAAYAIMYAA==.',
No='Nomaa:BAAANQADCgQIBAAAAA==.Noris:BAAANQAECgUIBgAAAA==.Norros:BAAANQAECgIIAgAAAA==.Novacaine:BAAANQADCgcIBwAAAA==.',
Nu='Nuvi:BAAANQAECgQICAAAAA==.Nuvostaph:BAAANQAECgMIAwAAAA==.',
Od='Odecias:BAAANQADCgUICQAAAA==.',
Og='Ogbrew:BAAANQADCgcIEAAAAA==.',
Or='Orcboken:BAAANQAECgMIBAAAAA==.Orezn:BAAANQAECgQICgAAAA==.',
Pa='Pabby:BAAANQABCgIIBAAAAA==.Painting:BAAANQAECgEIAQABNQAECgUICwAJAAAAAA==.Pallypusher:BAAANQADCgQJCAAAAA==.Papiace:BAAANQAECgUIDAABNQAECgkJLAAEABseAA==.Pato:BAAANQAECgcIEgAAAA==.',
Ph='Phatnips:BAABNQAECoEcAAMbAAgKnBCGWQD9AQAbAAgKnBCGWQD9AQASAAEKxgMCdwAnAAAAAA==.',
Pi='Pigeon:BAAANQADCgUIBgAAAA==.',
Pn='Pnuts:BAABNQAECoEkAAIMAAkKvRs2EAC9AgAMAAkKvRs2EAC9AgAAAA==.',
Po='Popedragon:BAAANQAECgEIAgAAAA==.Poshh:BAAANQADCgQIBAAAAA==.',
Pr='Prayihealu:BAAANQADCgYIBwAAAA==.Pres:BAAANQADCgIIAgAAAA==.Prisonmike:BAAANQAECgUICgAAAA==.Promise:BAAANQAECgQIBAAAAA==.Prophets:BAAANQADCgMIBQAAAA==.Pryome:BAAANQAECgcIEgABNQAECggIJAAOAGYXAA==.',
Pu='Puddiñ:BAAANQADCgMIAwAAAA==.Puffindaboof:BAAANQADCgUIBwAAAA==.Punkz:BAAANQADCgYICAABNQAECggIGQAVAPwbAA==.Punpal:BAAANQADCgYIBgAAAA==.Pushmaa:BAAANQAECgYJCwAAAA==.',
Py='Pyromortis:BAAANQAECgYICgABNQAECggIHgALAEUXAA==.Pytorch:BAABNQAECoEzAAIeAAgKmxraZgCAAgAeAAgKmxraZgCAAgAAAA==.',
['Pó']='Póphero:BAAANQADCggIEgAAAA==.',
Qu='Queelex:BAAANQAECgcIDAABNQAECggIGQAVAPwbAA==.Quigzz:BAABNQAECoEhAAIhAAkKohyiBwDrAgAhAAkKohyiBwDrAgAAAA==.Quinnie:BAAANQAECgMIAwABNQAFFAIIAgAJAAAAAA==.',
Ra='Raganarok:BAAANQADCggIHQAAAA==.Rahja:BAAANQAECgQIBgAAAA==.Ramss:BAAANQAECggICAAAAA==.Ranch:BAAANQADCgUIBQAAAA==.',
Re='Realtrendy:BAAANQADCggICAABNQAECggIFgASAI4QAA==.Redranse:BAAANQADCgQIBAAAAA==.Reebs:BAAANQAECgIIAQAAAA==.Resa:BAAANQAECgEIAQAAAA==.Restomania:BAAANQADCgMIAwAAAA==.',
Ri='Ricasti:BAAANQAECgYIBgAAAA==.',
Ro='Robinsonic:BAAANQAECgYICgAAAA==.Rokenn:BAAANQADCggJCAAAAA==.Rosabetsy:BAAANQADCgIIAgAAAA==.Rosetastoned:BAAANQADCgIJAgAAAA==.',
Ru='Rukiè:BAAANQAFFAEIAQAAAA==.Runmyrkr:BAAANQAECgYIBgAAAA==.',
['Rô']='Rôbert:BAAANQAECgEIAgAAAA==.',
Sa='Saberyn:BAAANQADCggIIwAAAA==.Saenya:BAABNQAECoEYAAIMAAcKARfdHwDvAQAMAAcKARfdHwDvAQAAAA==.Sassynova:BAAANQADCgYICQAAAA==.',
Sc='Schvitz:BAAANQAECgQICQAAAA==.Scopeftis:BAABNQAECoETAAIKAAgKjh6aHgCMAgAKAAgKjh6aHgCMAgAAAA==.',
Se='Seano:BAAANQAECgMIAwAAAA==.Seberology:BAABNQAECoEoAAIdAAkKEBJkMwBbAgAdAAkKEBJkMwBbAgAAAA==.Segagamecube:BAAANQADCgMIAwAAAA==.Sepatown:BAAANQADCggICAAAAA==.Sephi:BAAANQADCgQIBAAAAA==.Sergal:BAAANQADCggICAABNQAECgMICQAJAAAAAA==.',
Sh='Shaco:BAAANQAECgMIAwAAAA==.Shamanpizza:BAAANQADCgMIAwAAAA==.Shamjam:BAAANQAECgQICQABNQAECggIGwAeAEIRAA==.Shamownage:BAAANQAECgcIDwABNQAECggIJAAOAGYXAA==.Shankyews:BAAANQADCgQJBAAAAA==.Sheev:BAAANQADCgEIAQAAAA==.Shepling:BAABNQAFFIEKAAIOAAUKYg6lCwA5AQAOAAUKYg6lCwA5AQAAAA==.Shifterella:BAAANQAECgIIAgAAAA==.Shifu:BAAANQAFFAEIAgAAAA==.Shivàh:BAACNQAFFIEKAAMKAAQKGhUmBwAzAQAKAAQK3g8mBwAzAQAPAAMKexLKCADpAAA1AAQKgR0AAw8ACQpMIicRAMoCAA8ACQpGIicRAMoCAAoAAwqkIRRgACkBAAAA.Shneezleberg:BAABNQAECoETAAMFAAcKDhqJWgA3AgAFAAcKDhqJWgA3AgAiAAQKGAvzGgChAAAAAA==.',
Si='Sildormi:BAAANQAECgEIAQAAAA==.Sithrage:BAAANQADCgQIBAAAAA==.Sizzlinghots:BAAANQAECgIIAgAAAA==.',
Sk='Skateboardp:BAAANQADCgYIBgAAAA==.Sko:BAABNQAECoEfAAIFAAkKahlrNgC1AgAFAAkKahlrNgC1AgAAAA==.Skár:BAAANQADCgMIAwAAAA==.',
Sl='Sladak:BAAANQADCgIIAgAAAA==.',
Sn='Snackdad:BAAANQADCgMIBAAAAA==.Sneakyky:BAAANQADCgUIBgAAAA==.Sneakymoomoo:BAAANQADCgYJBgABNQAECggIHgALAEUXAA==.Snowyrain:BAAANQADCgIIBAABNQADCggIEAAJAAAAAA==.',
So='Sojourner:BAAANQAECgQIBAAAAA==.Solanum:BAAANQADCgQIBAABNQADCgUIBgAJAAAAAA==.Solkar:BAAANQADCgcJCwAAAA==.Solo:BAABNQAECoEbAAIXAAgKIhRrYwAXAgAXAAgKIhRrYwAXAgAAAA==.Soupsandwich:BAAANQAECgMIBAAAAA==.Sourless:BAAANQAECgEIAQAAAA==.',
St='Stagg:BAABNQAECoEbAAIeAAgKQhEDnQABAgAeAAgKQhEDnQABAgAAAA==.Stankazz:BAAANQABCgQIBAAAAA==.Stankytotems:BAAANQADCgcIEQAAAA==.Stinkcheese:BAAANQAECgEIAQAAAA==.Stonedkritz:BAAANQABCgMIAwAAAA==.',
Su='Sunarii:BAAANQAECgQIBwAAAA==.Sunroof:BAAANQADCgMIBgAAAA==.Superpoor:BAAANQABCgEIAQAAAA==.',
Sw='Swagalito:BAAANQADCgUIBgAAAA==.',
['Sà']='Sàviorself:BAAANQAECgEIAQAAAA==.',
Ta='Taelian:BAAANQADCgYICQAAAA==.Talanath:BAAANQAECgcIDgAAAA==.Taldor:BAAANQABCgMIAwAAAA==.Tanarran:BAAANQADCgUIBQAAAA==.Tatooth:BAAANQADCgQIBAAAAA==.Tazoo:BAAANQAECgUIBwAAAA==.',
Te='Teamfluffer:BAAANQADCgUICQAAAA==.Tee:BAAANQADCgcIDQAAAA==.Telps:BAAANQADCgIIAgAAAA==.Teranosouth:BAAANQABCgMIAwAAAA==.Teruulos:BAAANQAECgQIBAAAAA==.',
Th='Thabeast:BAAANQAECgEIAQAAAA==.Thadeouss:BAABNQAECoEeAAILAAgKhR1LNgBLAgALAAgKhR1LNgBLAgAAAA==.Tharon:BAAANQAECgcIEQAAAA==.Thebigboom:BAABNQAECoElAAIjAAgKlhznBwCaAgAjAAgKlhznBwCaAgAAAA==.Thecarter:BAAANQAECgIIAgAAAA==.Thoomahawk:BAAANQADCgIIAgAAAA==.',
Ti='Tichalock:BAAANQADCgIIAgABNQAECgEIAQAJAAAAAA==.Tichemort:BAAANQADCgcICwAAAA==.Tigerchimon:BAAANQADCgUIBQABNQAECggIJAAOAGYXAA==.Tinglem:BAAANQADCgYICwAAAA==.',
To='Tobiramaa:BAAANQABCgQIBAAAAA==.Toeclipper:BAAANQADCgYIBgAAAA==.Tolivold:BAAANQAECgQICAAAAA==.Tomeoz:BAAANQAECgEIAQAAAA==.Toxicsocks:BAAANQAECggIEQAAAA==.',
Tr='Trapscallion:BAAANQAECgQIBAAAAA==.Trashcaster:BAAANQADCgcIDAAAAA==.Treeknight:BAABNQAECoEbAAIKAAgKWRWYNQDzAQAKAAgKWRWYNQDzAQAAAA==.Treelimbs:BAAANQAECgEJAQAAAA==.Tridity:BAAANQAECgYIDwAAAA==.Trollolollz:BAAANQAECgIIAwAAAA==.',
Ts='Tsuuna:BAABNQAECoEbAAIFAAkKtxiCMwDAAgAFAAkKtxiCMwDAAgAAAA==.',
Tu='Turtleqt:BAAANQABCgEIAQAAAA==.',
Ty='Tylanar:BAAANQADCgYIBgABNQAECgIIAgAJAAAAAA==.Tylandon:BAAANQADCggICAAAAA==.',
['Tê']='Tênaciousv:BAAANQAECgIJAwAAAA==.',
['Të']='Tëhzoo:BAAANQABCgIIAgAAAA==.',
['Tì']='Tìnnitus:BAAANQABCgMIBAAAAA==.',
Ug='Uglyboyryan:BAAANQADCgIIAgAAAA==.',
Un='Unavaluable:BAAANQADCggIDwAAAA==.Ungodlyy:BAAANQAECgEIAQAAAA==.Untöuchable:BAABNQAECoEeAAMXAAgKOR8bMADKAgAXAAgKOR8bMADKAgAdAAEK4gF7AAEhAAAAAA==.',
Ur='Urskrog:BAAANQADCggIEwAAAA==.',
Ve='Velachlan:BAAANQAECgQIBQAAAA==.Verdtual:BAAANQADCgMIAwAAAA==.Veredelyse:BAABNQAECoEcAAIYAAgKgxggBgBKAgAYAAgKgxggBgBKAgAAAA==.Verxl:BAAANQAECgQICAAAAA==.',
Vo='Voidnyou:BAAANQADCgQJCAAAAA==.Volumes:BAAANQAECgUIBwAAAA==.Volund:BAABNQAECoEYAAIkAAgKzgRIFgClAQAkAAgKzgRIFgClAQAAAA==.',
Vy='Vynsong:BAAANQAECgYICQAAAA==.Vyz:BAAANQADCgQIBAABNQAECgQIBAAJAAAAAA==.',
Wa='Warwalkerz:BAAANQADCggIFgAAAA==.Watermalorne:BAAANQAECgMIAwAAAA==.',
We='Weemies:BAAANQAECgUIBgAAAA==.Wetmonk:BAAANQAECgcIDQAAAA==.',
Wh='Whoyerdaddy:BAAANQADCgcJCQAAAA==.Whywhybecuz:BAAANQADCgQIBAAAAA==.',
Wi='Wickedal:BAAANQADCgIIAgAAAA==.Winndfurry:BAAANQADCgMIAwAAAA==.Winnototem:BAABNQAECoEcAAMVAAgKbxL6VQC8AQAVAAgKbxL6VQC8AQAWAAEKDgpn9wA3AAAAAA==.Wisakedjak:BAAANQADCggIGwAAAA==.Wix:BAAANQADCgcIBwAAAA==.',
Wo='Wombatman:BAAANQAECgEIAgAAAA==.Wong:BAAANQAECgUIBgAAAA==.',
Wu='Wutpuddle:BAAANQADCggIAQAAAA==.',
Xi='Xiaoshui:BAAANQADCgYIBgAAAA==.',
Xu='Xugos:BAAANQAECgYIDgAAAA==.',
Ya='Yatagarasu:BAAANQAECggIAgAAAA==.',
Yo='Yochill:BAAANQAECgIIAgABNQAECgIJBAAJAAAAAA==.Yoinker:BAAANQADCgEIAQAAAA==.Yolokin:BAAANQADCgQIBAAAAA==.Yooper:BAAANQADCgcIBgAAAA==.Yota:BAAANQAECgEIAQAAAA==.',
Yr='Yrgg:BAAANQAECgYICAAAAA==.',
Yu='Yuna:BAAANQABCggIDQAAAA==.',
Za='Zadanthra:BAAANQAECgMIBAAAAA==.Zapadin:BAAANQAECgYIDgAAAA==.Zaphodè:BAAANQAECgQIBAAAAA==.',
Ze='Zephian:BAAANQAECgMIAwAAAA==.Zephsham:BAAANQADCgYIDAAAAA==.Zerokool:BAAANQABCgMIAwAAAA==.',
Zi='Zimone:BAAANQADCgMIAwAAAA==.',
Zo='Zoerik:BAABNQAECoEZAAMlAAgKAAt4CACoAQAlAAgKAAt4CACoAQAMAAUKEwUDQADWAAAAAA==.Zotoperen:BAABNQAECoEcAAITAAgKQCFZBAABAwATAAgKQCFZBAABAwAAAA==.',
Zy='Zylergy:BAAANQAECgYIEgAAAA==.',
['Zì']='Zìfu:BAAANQABCgQIBAAAAA==.',
['Àv']='Àvicant:BAAANQAECgUJBwABNQAFFAQICAAIAPsbAA==.',
['Än']='Ändo:BAAANQAECgQICAAAAA==.',
['Äy']='Äy:BAAANQABCgEIAQAAAA==.',
['Çy']='Çyrin:BAABNQAECoEZAAMdAAgK6hBwTADzAQAdAAgK6hBwTADzAQAXAAEK5QhgSAE2AAAAAA==.',
['Çø']='Çørpsë:BAAANQABCgIJAgAAAA==.',
['Ëu']='Ëuphoria:BAAANQADCgQIBAAAAA==.',
['Ün']='Üna:BAAANQADCggICAAAAA==.',
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
