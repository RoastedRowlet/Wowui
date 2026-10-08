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

local lookup = {'Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','DemonHunter-Vengeance','Hunter-BeastMastery','Warrior-Arms','Mage-Arcane','Monk-Windwalker','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Druid-Balance','Warrior-Protection','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','Paladin-Retribution','Rogue-Assassination','DeathKnight-Blood','DeathKnight-Frost','Hunter-Survival','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Evoker-Preservation','Rogue-Outlaw','Paladin-Protection','DemonHunter-Devourer','Paladin-Holy','Mage-Frost','DemonHunter-Havoc','Priest-Discipline','Rogue-Subtlety','Warrior-Fury','Druid-Guardian','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Darkspear',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abssorath:BAAANQADCgYIBgAAAA==.',
Ae='Aerouant:BAABNQAECoElAAMBAAkKARfaBQBTAgABAAkKARfaBQBTAgACAAQKZBCBJQDvAAAAAA==.',
Ai='Aidix:BAAANQAECgEIAgAAAA==.Aimassist:BAAANQAECgQIBAAAAA==.',
Al='Alaliix:BAAANQADCgEIAQAAAA==.Alcyone:BAABNQAECoElAAIDAAkKTxq4DwC+AgADAAkKTxq4DwC+AgAAAA==.Alexstanna:BAAANQAECgEIAQAAAA==.Allophone:BAAANQADCgIIAgAAAA==.Almightyhunt:BAAANQADCgMIAwAAAA==.Altimys:BAAANQADCgIIAgAAAA==.',
An='Annarchy:BAAANQADCgQIBAAAAA==.Antakata:BAAANQADCgcIBwAAAA==.Antapathy:BAABNQAECoElAAIEAAkKzBQzCQApAgAEAAkKzBQzCQApAgAAAA==.Anthross:BAABNQAECoEYAAIFAAgK2w0LdwDzAQAFAAgK2w0LdwDzAQAAAA==.',
Ap='Apollovon:BAABNQAECoEbAAIGAAgKNiFGLgDxAgAGAAgKNiFGLgDxAgAAAA==.Applebees:BAAANQAECgEIAQAAAA==.',
Ar='Arcanenug:BAAANQADCgQJBAAAAA==.Arcbnonez:BAAANQAECgQIBQAAAA==.Arguxx:BAAANQAECgEIAQABNQAECgkJHwAHACISAA==.Armiggy:BAABNQAECoEjAAIIAAgKJBL5IwDYAQAIAAgKJBL5IwDYAQAAAA==.Aro:BAACNQAFFIERAAMJAAUKRCHbCwBXAQAJAAQKaSDbCwBXAQAFAAIK4hstGQC3AAA1AAQKgSIAAwkACQreJModAEYCAAkABwouIcodAEYCAAUABgotIal9AOMBAAAA.Arrowraen:BAABNQAECoEjAAIFAAkKyiN5BwCVAwAFAAkKyiN5BwCVAwAAAA==.Artoodetoo:BAAANQADCgQIBQAAAA==.',
As='Asavera:BAAANQAECgIIAgAAAA==.Asd:BAAANQADCgQIBAAAAA==.Asecond:BAAANQADCgYJBgAAAA==.Asträl:BAAANQAECgEIAwAAAA==.',
Au='Audomere:BAABNQAECoEbAAMKAAkKfQhjbACYAQAKAAkKfQhjbACYAQALAAIKlgEKDQE8AAAAAA==.Auurwarr:BAAANQAECgUIBQAAAA==.',
Av='Avawrath:BAAANQAECggIDAAAAA==.Avraellia:BAAANQADCgYIBQAAAA==.',
Az='Azkaellon:BAAANQADCgQIBAABNQAECggIHQAEALESAA==.',
Ba='Bagool:BAAANQADCgYIBgAAAA==.Bailey:BAAANQAECgEIAQABNQAECgIIAgAMAAAAAA==.Ballstench:BAAANQADCgIIAgAAAA==.Barbåtos:BAAANQADCggIFwAAAA==.Baskthyr:BAAANQADCgQIBAAAAA==.Bathory:BAAANQADCgYIBgAAAA==.',
Be='Bearboi:BAABNQAECoEXAAINAAgKWBdqMQAxAgANAAgKWBdqMQAxAgABNQADCgUIBQAMAAAAAA==.Bearbomblolz:BAAANQADCgQIBQABNQAECgQICQAMAAAAAA==.Bearmanakin:BAAANQADCgYICQAAAA==.Bearypotter:BAAANQAECgEIAQAAAA==.Beastbane:BAAANQAECggIAQAAAA==.Beastly:BAAANQAECgUICgAAAA==.Beastmandes:BAAANQADCggIFAAAAA==.Bejeezus:BAABNQAECoEmAAMOAAkK6hbsEQDZAQAGAAkKVRYyVwBpAgAOAAgKpBLsEQDZAQAAAA==.Bel:BAAANQABCgYIDAAAAA==.Bellion:BAABNQAECoExAAIPAAgK4hepOAAdAgAPAAgK4hepOAAdAgAAAA==.Berijar:BAAANQADCgYIBgABNQAECgIIAgAMAAAAAA==.Bewslee:BAAANQAECgEIAgAAAA==.Bexx:BAAANQADCggJGQAAAA==.',
Bi='Biblehumping:BAABNQAECoElAAMQAAgKYRk3PQBQAgAQAAgKYRk3PQBQAgARAAYKjgrYOgAoAQAAAA==.Bietk:BAAANQADCgQIBwABNQAECgcIDAAMAAAAAA==.Bigbonks:BAAANQAECgQIBwAAAA==.Bigdumb:BAAANQAECgEIAQAAAA==.Bigoldpumper:BAAANQAECgEIAQAAAA==.',
Bl='Blackplague:BAAANQADCgQIBQAAAA==.Bleaknight:BAAANQADCgUIBQAAAA==.Blessedbuns:BAAANQAECggIDQAAAA==.Blueshamoo:BAAANQAECgEJAQAAAA==.Blãezer:BAAANQAECgEIAQAAAA==.',
Bo='Bonex:BAAANQAECgEIAgAAAA==.Boomshroom:BAAANQAECgMIBQABNQAECgkJIwAIAIwbAA==.Bootsie:BAAANQADCggICAAAAA==.',
Br='Brewtoe:BAAANQAECgQIBAAAAA==.Brisketz:BAAANQADCgUIAQAAAA==.Bruneau:BAAANQAECgEIAQAAAA==.',
Bs='Bshoutbot:BAAANQADCgUIBQABNQAFFAcIEwAJAOgbAA==.',
Bu='Bubblemehard:BAABNQAECoEVAAISAAcKihZsiADjAQASAAcKihZsiADjAQAAAA==.',
By='Byahnbreath:BAAANQAFFAIIAgAAAA==.',
Ca='Cakeiko:BAAANQADCgMIAwAAAA==.Cannabinoide:BAAANQAECgIIAgAAAA==.Cannatonic:BAAANQAECgEIAQAAAA==.Casmiralda:BAAANQAECgEIAwAAAA==.Castielx:BAABNQAECoEZAAITAAcKnRJPMwDUAQATAAcKnRJPMwDUAQAAAA==.Catnips:BAAANQAECgQIBAABNQAECggIJQAQAGEZAA==.',
Ce='Celestraza:BAAANQADCggIFgAAAA==.Celirra:BAABNQAECoEkAAIPAAgKbyJtGQDaAgAPAAgKbyJtGQDaAgAAAA==.Cennerus:BAAANQADCgIIAwAAAA==.',
Ch='Chaosreign:BAAANQADCggICwAAAA==.Cheekybaby:BAABNQAECoEZAAIGAAgKUgqkmwCtAQAGAAgKUgqkmwCtAQAAAA==.Cherrypoplol:BAAANQADCgUIDAAAAA==.Chocopaati:BAAANQAECgYIEwAAAA==.Chokma:BAAANQAECgcIDgAAAA==.Chunkyfists:BAAANQADCgMIAwAAAA==.Chëeks:BAAANQADCgUIBQAAAA==.Chìefponbury:BAAANQAECgYIBwAAAA==.',
Ci='Cinnaa:BAAANQAECgUICgAAAA==.',
Cl='Clawdog:BAAANQADCgIIAgABNQAECgIIBAAMAAAAAQ==.Clawwz:BAAANQAECgEIAQAAAA==.Cleisthenes:BAAANQAECgEIAQAAAA==.Clors:BAABNQAECoEXAAIDAAcKRRyoGgA6AgADAAcKRRyoGgA6AgAAAA==.',
Co='Conflux:BAAANQADCggIFAAAAA==.',
Cr='Crawlah:BAAANQADCggICAAAAA==.Crazegideon:BAAANQAECgEIAQAAAA==.Crazespawnz:BAAANQAECgEIAQAAAA==.Cruelbeam:BAAANQADCgQIBAAAAA==.',
Cu='Curzondax:BAAANQAECggIEwAAAA==.',
Cy='Cyberfairy:BAAANQAECgEJAgAAAA==.Cyphinx:BAAANQAECgUIBQAAAA==.',
['Câ']='Câraxes:BAAANQAECgEIAQAAAA==.',
['Cä']='Cät:BAAANQAECgEIAQAAAA==.',
Da='Dahelzforyou:BAAANQADCgcICAAAAA==.Dalìnar:BAAANQAECgUIDAAAAA==.Damadafacker:BAAANQAECgcJDgAAAA==.Darkclôud:BAAANQAECgQIBAAAAA==.Darkkatriden:BAAANQADCgYIBgABNQAECgUIDAAMAAAAAA==.Darklia:BAAANQAECgUIDAAAAA==.Darthjae:BAABNQAECoE4AAMUAAcKMhkwRADLAQAUAAcKMhkwRADLAQAVAAEKcAWCogAfAAAAAA==.Darthmikkey:BAAANQADCgYIBgAAAA==.Darthrakk:BAABNQAECoEiAAIWAAgK9B3vAgDWAgAWAAgK9B3vAgDWAgAAAA==.Davina:BAAANQADCgcIBwABNQAFFAMIAwAMAAAAAA==.Daykwan:BAAANQAECggIDgAAAA==.Daïn:BAAANQAECgYIDQAAAA==.',
De='Deadestmoonb:BAAANQADCgIIBAAAAA==.Deathalimon:BAABNQAECoEnAAQPAAgKORoTSQDLAQAPAAcKgxUTSQDLAQAUAAcKthY7SAC4AQAVAAEKoAxDlwAvAAAAAA==.Deepdeath:BAABNQAECoEyAAIGAAgKziKVMADoAgAGAAgKziKVMADoAgAAAA==.Degion:BAAANQADCgEIAQAAAA==.Deltonn:BAAANQAECgEIAgAAAA==.Demonarian:BAAANQAECgYICQABNQAECggIJwAPADkaAA==.Demonpotato:BAAANQADCggJCAAAAA==.Denardath:BAAANQADCgUIBQAAAA==.Denerrollin:BAAANQADCgIIAgAAAA==.Depthcharge:BAAANQAECgYIDQAAAA==.Deroc:BAAANQAECgcIDwAAAA==.Desporato:BAAANQAECggIAQAAAA==.Deáthtáxi:BAAANQAECggICAAAAA==.',
Di='Dinfarmer:BAAANQADCgcIDAAAAA==.Dirtycheese:BAAANQAECgUIDQAAAA==.',
Dj='Djgha:BAAANQAECgIIBAAAAA==.',
Dm='Dmptrukdonna:BAAANQADCgEIAQAAAA==.',
Do='Dogfärts:BAAANQADCgcIFAAAAA==.Dorunter:BAABNQAECoEgAAMJAAcKeRT9LQC1AQAJAAcKDRP9LQC1AQAFAAEKsBlHJgFTAAAAAA==.Dottíe:BAAANQAECgUIBQAAAA==.Doubledosage:BAAANQAECgUIDQAAAA==.',
Dr='Dragonbnonez:BAAANQAECgUIBQAAAA==.Dragonforge:BAAANQADCgYIDQAAAA==.Drakujin:BAAANQADCgMIBQAAAA==.Drboomboom:BAAANQAECggICgAAAA==.Drdoitall:BAAANQAECgYIDAAAAA==.Dreadnpain:BAAANQADCgEIAQAAAA==.Dreynick:BAAANQADCgQIBAAAAA==.Dripfarming:BAAANQAECgMIBAABNQAFFAcIEgAVAF4fAA==.Drnastea:BAAANQADCgYIBgAAAA==.Drstorm:BAAANQADCgYICwAAAA==.',
Du='Duuid:BAAANQADCgQIBgAAAA==.',
Ed='Edaladalrian:BAAANQADCgUIBQAAAA==.',
El='Ella:BAAANQADCgIIAgAAAA==.Elysiá:BAAANQADCggICAAAAA==.',
En='Enhydra:BAAANQADCggICwAAAA==.Enough:BAAANQADCgcIDAAAAA==.',
Eq='Eqv:BAACNQAFFIEHAAQXAAQK2xIABACWAAAYAAIKDhTHCgCmAAAXAAIKqBEABACWAAAZAAEK6AGnPQA7AAA1AAQKgR4AAxcACQpFJNkCAMMCABcABwrUJNkCAMMCABgAAgpQIs89AMAAAAAA.',
Er='Ericolson:BAABNQAECoEaAAIGAAcKEBJAlgC8AQAGAAcKEBJAlgC8AQAAAA==.Erze:BAAANQAECgUIDAAAAA==.Erôman:BAAANQADCgQIBAAAAA==.',
Ev='Evilmcgyver:BAAANQAECgEIAgAAAA==.Evosolz:BAEANQAECgEIAgABNQAECgQICAAMAAAAAA==.Evé:BAAANQAECgMIBAABNQAECgkJIwAIAIwbAA==.',
Ez='Ezzartkal:BAAANQADCgUIBQAAAA==.',
Fa='Faeloria:BAAANQADCgMIAwAAAA==.Farmerdragon:BAAANQADCggIDgAAAA==.Favabean:BAAANQADCgUIBQABNQAECgcIOAAUADIZAA==.',
Fe='Feathring:BAAANQADCgYIBgABNQAECgkJIAAaAOYgAA==.Fefra:BAAANQADCgQIBAAAAA==.Felicious:BAAANQAECggICgAAAA==.Fengshui:BAAANQADCggIGwAAAA==.Feralco:BAAANQADCgYIBgAAAA==.Fertra:BAAANQAECgEIAQAAAA==.',
Fh='Fhedrah:BAAANQADCgEIAgAAAA==.',
Fi='Fixiation:BAAANQAECgEIAQAAAA==.Fiz:BAAANQADCgYIBgAAAA==.',
Fl='Flashdance:BAAANQADCgcIBwAAAA==.Fleepo:BAAANQAECgIIAwABNQAECggIDAAMAAAAAA==.Fleshnbones:BAAANQADCgEIAQAAAA==.Flourie:BAABNQAECoElAAMbAAkK/goyHQDbAQAbAAkK/goyHQDbAQACAAEK2wdcOgAvAAAAAA==.Flyhawk:BAAANQAECgEIAQAAAA==.Flöör:BAAANQADCgUJBQAAAA==.',
Fu='Fullmetal:BAAANQAECgEIAQAAAA==.Funkadelfic:BAAANQAECgUIBwAAAA==.',
['Fé']='Fénrír:BAAANQADCggIDwABNQAECgcIGgALAHUiAA==.',
['Fò']='Fòxxy:BAAANQAECgEJAQAAAA==.',
Ga='Galadri:BAABNQAECoEZAAMKAAgK/Bs5NQBkAgAKAAgK/Bs5NQBkAgALAAUKWhC+qwANAQAAAA==.Garu:BAAANQADCgIIAgAAAA==.',
Ge='Geared:BAAANQAECgcIEwAAAA==.Geartryx:BAAANQADCggIDQAAAA==.',
Gh='Ghoshshadow:BAAANQAECgEIAQAAAA==.Ghostinz:BAAANQAECgQIBAAAAA==.',
Gi='Gimpripper:BAAANQAECgEIAQAAAA==.Giztron:BAAANQADCgYIDgAAAA==.',
Gl='Glitterp:BAAANQADCgQIBAABNQAECggJIAAUANoZAA==.Globalcold:BAABNQAECoEbAAIGAAgK8BntXgBSAgAGAAgK8BntXgBSAgAAAA==.Globb:BAABNQAECoEwAAIGAAgKWRXSgAD2AQAGAAgKWRXSgAD2AQAAAA==.Globius:BAABNQAECoEhAAISAAkK5Bx6PQC4AgASAAkK5Bx6PQC4AgAAAA==.Gloriouscole:BAAANQAECgUIEgAAAA==.Glower:BAAANQADCgEIAQAAAA==.',
Go='Gooly:BAAANQADCgIIAgAAAA==.Goombit:BAAANQADCgEIAQAAAA==.Gospel:BAAANQAECgEIAgAAAA==.',
Gr='Greekorc:BAAANQABCgYJBwAAAA==.Greenyheals:BAAANQADCgUIBQAAAA==.Grimby:BAAANQAECgIIAgAAAA==.Grimdisney:BAAANQADCggIDgAAAA==.Gromol:BAAANQADCggJHQAAAA==.Grumby:BAAANQADCggICAAAAA==.',
Gu='Guifu:BAAANQADCgIIAgAAAA==.',
Gw='Gwendolÿn:BAAANQADCgYIBwAAAA==.',
['Gê']='Gêralt:BAAANQADCgQIBAAAAA==.',
Ha='Hacknhaf:BAAANQADCgYIDAAAAA==.Hakubar:BAAANQAECgQIBgAAAA==.Hareball:BAAANQAECgEIAQAAAA==.Hatebrêêd:BAAANQADCgQIBQAAAA==.',
He='Healman:BAAANQADCgcIGQAAAA==.Healsatute:BAAANQADCgMIAwAAAA==.Healylady:BAAANQADCgcIDAAAAA==.Heiden:BAAANQADCgYJBgAAAA==.Hel:BAAANQADCggIEwAAAA==.Hellyas:BAAANQAECgQICAAAAA==.Herbs:BAAANQADCgYICwABNQAECgkJKAAcAFUXAA==.Herenorthere:BAABNQAECoEjAAMRAAkKEBn9JgDMAQARAAYKOhz9JgDMAQAQAAUKcBeFegBxAQABNQAECgkJJwAYADMZAA==.Hermippe:BAAANQAECgMJAwAAAA==.Hexstraits:BAABNQAECoEiAAIUAAkKmSGoDQAyAwAUAAkKmSGoDQAyAwAAAA==.',
Hi='Hia:BAACNQAFFIEMAAIUAAUKGRSnDABaAQAUAAUKGRSnDABaAQA1AAQKgS0AAhQACQpFH2gOACsDABQACQpFH2gOACsDAAAA.Highriskbr:BAAANQAECggICAAAAA==.Hitlist:BAAANQADCgUJBQAAAA==.',
Ho='Holycow:BAAANQAECgEIAQAAAA==.Holyfits:BAAANQADCgEIAQAAAA==.Hondacervix:BAAANQAECgYIBwAAAA==.Hondaimpala:BAAANQAECgQIBwABNQAECgcIOAAUADIZAA==.Hoofmaster:BAAANQAECgEIAQAAAA==.Howardyou:BAAANQADCgEIAgAAAA==.',
Hu='Huffy:BAAANQADCgQIBAAAAA==.Huffyy:BAABNQAECoEcAAIGAAkKMRmkMwDdAgAGAAkKMRmkMwDdAgAAAA==.Huhdean:BAABNQAECoEhAAMVAAgK6SMwFADKAgAVAAcKxCMwFADKAgAPAAQKoR8OeAARAQAAAA==.Hulxamus:BAAANQAECgYICwAAAA==.Hunterramen:BAAANQADCgEJAQAAAA==.Hunterryan:BAAANQAECggIBQAAAA==.Hunterz:BAAANQAECgQJCQAAAA==.',
['Hé']='Héåthcliff:BAABNQAECoExAAMdAAkKDSNrAwB8AwAdAAkKDSNrAwB8AwASAAIKNxMnOAGDAAABNQAECgkJFgAUALQcAA==.',
Ic='Icyblaze:BAAANQAECggIEgAAAA==.',
Id='Idareu:BAAANQAECggIDgAAAA==.',
If='Ifstar:BAAANQAECgEIAQAAAA==.',
Il='Illumi:BAAANQADCgQIBwABNQAECgUICgAMAAAAAA==.',
Im='Immigrant:BAAANQADCggICAAAAA==.',
In='Indominus:BAAANQADCgIIAgAAAA==.',
Ir='Ires:BAAANQADCgUIBQAAAA==.',
Is='Ishadow:BAAANQAECgUIBgAAAA==.Issalis:BAAANQADCgYIBgAAAA==.',
It='Itheusvalles:BAAANQAECgEIAgAAAA==.Itsjerry:BAAANQADCgYICQAAAA==.',
Iw='Iwillcrushyo:BAAANQAECgEIAwAAAA==.',
Ja='Jaimerrek:BAAANQAECgMIAwAAAA==.Jainalynn:BAAANQADCgUIEgAAAA==.Jalenbrunson:BAAANQADCgEIAQAAAA==.Jazira:BAABNQAECoEaAAMDAAgK+QtYRgDKAAADAAYKZQZYRgDKAAANAAUK1AMlewC1AAAAAA==.',
Jd='Jdarkside:BAAANQAECgUICAAAAA==.',
Je='Jenzilus:BAAANQAECgcIAgAAAA==.Jeremmiah:BAAANQADCgcIEQAAAA==.',
Jh='Jhacobo:BAABNQAECoEhAAINAAgKgBmYKgBgAgANAAgKgBmYKgBgAgAAAA==.',
Jo='Jojupobu:BAAANQADCggICAAAAA==.Jorkinit:BAAANQAECgcIEwAAAA==.',
Jr='Jragon:BAABNQAECoEeAAIZAAcKnQnwmQB1AQAZAAcKnQnwmQB1AQAAAA==.',
Ju='Judis:BAAANQABCgYICwAAAA==.Juicedh:BAAANQADCgUIBQAAAA==.Juicy:BAABNQAECoEVAAIHAAkKtRrGYQCoAgAHAAkKtRrGYQCoAgAAAA==.Junipur:BAAANQAECgMICQAAAA==.',
Jx='Jxxy:BAACNQAFFIEJAAMFAAQKhRcREAAZAQAFAAMKbhoREAAZAQAJAAIK1g60GACMAAA1AAQKgRcAAwUACQpEH8q1AGQBAAUACApNIcq1AGQBAAkAAgpzGW5XAKEAAAE1AAUUBAoJAAUAhRcA.',
['Jú']='Júnjúnwälä:BAABNQAECoEcAAIDAAcKsCWWCwD2AgADAAcKsCWWCwD2AgAAAA==.',
Ka='Kalories:BAAANQAECgMIAwABNQAECgQIBAAMAAAAAA==.Kalvoid:BAAANQAECgQIBAAAAA==.Kandance:BAAANQAECgUICQABNQAFFAIIAgAMAAAAAA==.Karlmagnus:BAAANQAECgEIAQAAAA==.',
Ke='Kelvintwo:BAAANQADCgQIAwAAAA==.',
Ki='Kimbopable:BAAANQADCgUICgABNQAECgcIOAAUADIZAA==.Kittyÿ:BAAANQAECgYIDwAAAA==.',
Kn='Knurl:BAAANQADCgMIAwAAAA==.',
Ko='Korak:BAAANQADCgUIBQABNQADCgYIBgAMAAAAAA==.Korgh:BAAANQAECgEIAQAAAA==.Kosari:BAAANQADCgEIAQABNQADCgYIFgAMAAAAAA==.',
Kr='Krystall:BAABNQAECoEeAAIXAAgKOQ4ZCADsAQAXAAgKOQ4ZCADsAQAAAA==.',
Ku='Kuarahy:BAAANQAECgcIEAAAAA==.Kunfugrip:BAABNQAECoEjAAIIAAkKjBuZEADBAgAIAAkKjBuZEADBAgAAAA==.Kurizmuh:BAAANQADCgUIBwAAAA==.',
['Kà']='Kàl:BAAANQADCgYJBwABNQAECgQIBAAMAAAAAA==.',
['Kã']='Kãl:BAAANQADCgYIBgABNQAECgQIBAAMAAAAAA==.',
La='Lanthos:BAABNQAECoEtAAIeAAkKVRykDQD9AgAeAAkKVRykDQD9AgAAAA==.Lapulapu:BAAANQADCgYIBgAAAA==.Larthal:BAAANQAECgQIBAAAAA==.Latinpapi:BAABNQAECoEbAAISAAkKiRCCegAGAgASAAkKiRCCegAGAgAAAA==.',
Le='Leemiez:BAAANQADCgUIBQAAAA==.Leyära:BAAANQAECgIIBgAAAA==.',
Li='Lielys:BAAANQAECgEIAQAAAA==.Lilina:BAABNQAECoEZAAIEAAcKXRoMCgAQAgAEAAcKXRoMCgAQAgAAAA==.Liljaejae:BAAANQADCgEIAQAAAA==.',
Lm='Lmn:BAAANQADCgUIBwAAAA==.',
Lo='Lonweh:BAAANQAECgMICAAAAA==.Lousmage:BAAANQADCgUIBQAAAA==.Loza:BAAANQADCgUICwABNQAECgYIEAAMAAAAAA==.',
Lu='Lucith:BAABNQAECoElAAIVAAkKfB9eCgA0AwAVAAkKfB9eCgA0AwAAAA==.Luckie:BAAANQABCgQIBwABNQAFFAUIDgAfAA8RAA==.Lulafairy:BAAANQAECgEJAgAAAA==.Lumador:BAAANQAECgQICAABNQAECgcIHQARAIgXAA==.Lunatick:BAABNQAECoEXAAQVAAcKVQ/ARQBiAQAVAAcKbgvARQBiAQAPAAUKYgOOmACrAAAUAAIKghmvmQCHAAAAAA==.Lunawa:BAACNQAFFIEIAAIHAAUKAhkeEgC+AQAHAAUKAhkeEgC+AQA1AAQKgUAAAwcACQoyJpICAOQDAAcACQoyJpICAOQDACAAAwq1EQ0nAJcAAAAA.Lustbót:BAABNQAECoEbAAIHAAkKIAgDzQDHAQAHAAkKIAgDzQDHAQAAAA==.Luvnrdjr:BAAANQADCgYIBgAAAA==.',
Ly='Lynnai:BAAANQADCgYIFgAAAA==.Lynxmi:BAAANQADCgEIAQAAAA==.Lyse:BAACNQAFFIELAAIhAAUKwB6dBQDPAQAhAAUKwB6dBQDPAQA1AAQKgScAAiEACQq8Jd8DAKsDACEACQq8Jd8DAKsDAAAA.',
['Lê']='Lêvak:BAAANQADCgIIAgAAAA==.',
['Lí']='Líllith:BAAANQADCgYJBgAAAA==.',
['Lô']='Lôuku:BAABNQAECoEkAAIZAAgKFRmZPQB+AgAZAAgKFRmZPQB+AgAAAA==.',
Ma='Maahn:BAAANQADCgcICAAAAA==.Macalob:BAAANQAECgQICAAAAA==.Madallar:BAAANQAECgYIEwAAAA==.Magdagni:BAAANQAECgYIDgAAAA==.Mageji:BAACNQAFFIEJAAIHAAQK1yH+FwCQAQAHAAQK1yH+FwCQAQA1AAQKgTEAAgcACQpBIxgQAI4DAAcACQpBIxgQAI4DAAE1AAMKBggGAAwAAAAA.Magepies:BAAANQAECgQIBgABNQAECgQICQAMAAAAAA==.Magerella:BAAANQAECgEIAQAAAA==.Magicfurry:BAAANQAECgUICgABNQAECggIJQAQAGEZAA==.Malicelx:BAAANQAECgIIAgABNQAECgkJHwAHACISAA==.Mallgoth:BAABNQAECoEVAAIFAAYKDgYK3QAVAQAFAAYKDgYK3QAVAQAAAA==.Manohar:BAABNQAECoEhAAMKAAkKNRxHJQCxAgAKAAkKNRxHJQCxAgALAAcK1g7vbwCgAQAAAA==.Mardtard:BAAANQAECgcICgABNQAECgUICAAMAAAAAA==.Marximilian:BAAANQAECgMIAwAAAA==.',
Mc='Mcflurryz:BAAANQADCgUIBQAAAA==.Mcgrubert:BAAANQAECgIJAwAAAA==.',
Me='Mechachad:BAAANQAECgMIAwAAAA==.Medlock:BAAANQAECgEIAQAAAA==.Medmasters:BAAANQABCgIIAgAAAA==.Megamango:BAAANQADCggICAABNQAECgkJKAAgAL0kAA==.Mehiel:BAAANQAECgcIDAAAAA==.Meive:BAAANQADCgMIAwAAAA==.Merdune:BAAANQADCgEIAQAAAA==.Merkén:BAAANQADCgcIAwAAAA==.Metaloclypse:BAAANQADCgcIDgAAAA==.Meteas:BAAANQAECgQIBAAAAA==.Mezaryn:BAAANQAECggIDgABNQAECgkJIwADAMcHAA==.Mezgrim:BAAANQAECggIAgABNQAECgkJIwADAMcHAA==.Mezzoo:BAABNQAECoEjAAIDAAkKxwf5PgD2AAADAAkKxwf5PgD2AAAAAA==.',
Mi='Midger:BAAANQADCgQIBAAAAA==.Millic:BAABNQAECoEaAAMiAAcKDA/jCgCBAQAiAAcKDA/jCgCBAQARAAEKYQdvagA5AAAAAA==.Millish:BAAANQADCgQIBAAAAA==.Minax:BAAANQAECgMIBAAAAA==.Missionsena:BAAANQAECgEJAQAAAA==.Mitzrael:BAAANQADCgQIBQAAAA==.',
Mo='Moozx:BAAANQAECgEIAQAAAA==.Morgannâ:BAAANQAECgIIAgAAAA==.Mosfeat:BAAANQADCggICAABNQAECggIEQAMAAAAAA==.',
Mu='Muckdile:BAAANQAECgQIBQAAAA==.Muckstab:BAAANQAFFAEIAQAAAA==.Mux:BAAANQAECgEIAgAAAA==.',
Na='Narayeda:BAAANQAECgUIDQAAAA==.Nasuadia:BAAANQADCggIHQABNQAECgkJHgAVACYaAA==.',
Ne='Nekkash:BAAANQAECgQIBAAAAA==.Neredir:BAAANQADCgYIBgAAAA==.Netoraresan:BAAANQAECggIAQAAAA==.Neytiri:BAAANQABCgQJBQAAAA==.Nezelle:BAAANQAECgYIDQABNQAECgkJKAAcAFUXAA==.',
No='Nomaa:BAAANQADCgQIBAAAAA==.Noris:BAAANQAECggIBwAAAA==.Norros:BAAANQAECgIIBAAAAA==.Novacaine:BAAANQADCgcIBwAAAA==.',
Nu='Nuvi:BAAANQAECgQIDAAAAA==.Nuvostaph:BAAANQAECgcIDQAAAA==.',
Od='Oddithy:BAAANQAECgEIAQAAAA==.Odecias:BAAANQADCgUICQAAAA==.',
Og='Ogbrew:BAAANQADCgcIEAAAAA==.',
Oh='Ohiyaa:BAAANQADCgQIBAAAAA==.',
Or='Orcboken:BAAANQAECgMIBAAAAA==.Orezn:BAAANQAECgQIDAAAAA==.',
Pa='Pabby:BAAANQAECgEIAQAAAA==.Painting:BAAANQAECgEIAwABNQAECgYIEgAMAAAAAA==.Pallypusher:BAAANQADCgQJCAAAAA==.Papiace:BAAANQAECgYIEAABNQAECgkJNwAEAEEfAA==.Pato:BAABNQAECoEUAAMGAAgKch3NYwBEAgAGAAgKch3NYwBEAgAOAAEKBhjIOAA8AAAAAA==.',
Ph='Phatnips:BAABNQAECoEkAAMZAAgKBxGIaQD5AQAZAAgKBxGIaQD5AQAYAAEKxgNMfQAnAAAAAA==.',
Pi='Piesniper:BAAANQABCgIIAgABNQADCgYIDAAMAAAAAA==.Pigeon:BAAANQADCgUIBgAAAA==.',
Pn='Pnuts:BAACNQAFFIEIAAIRAAQKpww7CQA5AQARAAQKpww7CQA5AQA1AAQKgSwAAhEACQoJHYgOAPACABEACQoJHYgOAPACAAAA.',
Po='Popedragon:BAAANQAECgEIAwAAAA==.Poshh:BAAANQADCgQIBAAAAA==.',
Pr='Prayihealu:BAAANQADCgYIBwAAAA==.Pres:BAAANQADCgIIAgAAAA==.Prisonmike:BAAANQAECggIEwAAAA==.Promise:BAAANQAECggIBAAAAA==.Prophets:BAAANQAECgEIAQAAAA==.Prucifix:BAAANQAECgEIAQAAAA==.Pryome:BAABNQAECoEYAAIHAAgKGQsjwwDaAQAHAAgKGQsjwwDaAQABNQAECggIJwAPADkaAA==.',
Pu='Puddiñ:BAAANQADCgMIAwAAAA==.Puffindaboof:BAAANQAECgIIAgAAAA==.Punkz:BAAANQADCgYICAABNQAECggIGQAKAPwbAA==.Punpal:BAAANQADCgYIBgAAAA==.Pushmaa:BAAANQAECgYJCwAAAA==.',
Py='Pyromortis:BAAANQAECgYIEgABNQAECggIJQAQAGEZAA==.Pytorch:BAABNQAECoE8AAIHAAgKcByBbQCOAgAHAAgKcByBbQCOAgAAAA==.',
['Pó']='Póphero:BAAANQAECgEIAgAAAA==.',
Qu='Queelex:BAAANQAECgcIDQABNQAECggIGQAKAPwbAA==.Quigzz:BAABNQAECoEnAAIjAAkK8B6IBQAnAwAjAAkK8B6IBQAnAwAAAA==.Quinnie:BAAANQAECgUICQABNQAFFAIIAgAMAAAAAA==.',
Ra='Raganarok:BAAANQAECgEIAQAAAA==.Rahja:BAAANQAECgQIBgAAAA==.Ramss:BAAANQAECggICAAAAA==.Ranch:BAAANQADCgUIBQAAAA==.',
Re='Realtrendy:BAAANQADCggICAABNQAECggIHQAYAA8RAA==.Redranse:BAAANQADCgQIBAAAAA==.Reebs:BAAANQAECgIIAgAAAA==.Resa:BAAANQAECgEIAwAAAA==.Restomania:BAAANQADCgMIAwAAAA==.',
Ri='Ricasti:BAAANQAECgYICwAAAA==.',
Ro='Robinsonic:BAAANQAECgYIEAAAAA==.Rokenn:BAAANQAECgEIAgAAAA==.Rosabetsy:BAAANQADCgIIAgAAAA==.Rosetastoned:BAAANQADCgIJAgAAAA==.',
Ru='Rukiè:BAAANQAFFAEIAQAAAA==.Runmyrkr:BAAANQAECgYICwAAAA==.',
Ry='Ryanbank:BAAANQAECgEIAwAAAA==.',
['Rô']='Rôbert:BAAANQAECgEIBwAAAA==.',
Sa='Saberyn:BAAANQAECgYIBgAAAA==.Sacredsassy:BAAANQADCgQIBAAAAA==.Saenya:BAABNQAECoEYAAIRAAcKARcHJQDfAQARAAcKARcHJQDfAQAAAA==.Sageofwampa:BAAANQADCgEIAQAAAA==.Sassynova:BAAANQADCgYICQAAAA==.',
Sc='Schvitz:BAAANQAECgUIDgAAAA==.Scopeftis:BAABNQAECoEUAAIPAAgKax/+KAB0AgAPAAgKax/+KAB0AgAAAA==.Scroticus:BAAANQAECgEIAQABNQAECgcIAgAMAAAAAA==.',
Se='Seano:BAAANQAECgMIBQAAAA==.Seberology:BAABNQAECoEoAAIfAAkKEBIGPQBTAgAfAAkKEBIGPQBTAgAAAA==.Segagamecube:BAAANQADCgMIAwAAAA==.Sepatown:BAAANQADCggICAAAAA==.Sephi:BAAANQADCgQIBAAAAA==.Sergal:BAAANQADCggICAABNQAECgMICQAMAAAAAA==.',
Sh='Shaco:BAAANQAECgMIBAAAAA==.Shamanpizza:BAAANQADCgMIAwAAAA==.Shamjam:BAAANQAECgQICwABNQAECgkJHwAHACISAA==.Shamownage:BAABNQAECoEXAAMLAAgKWhIMbwCjAQALAAcKzBEMbwCjAQAKAAcKYg/RdwB1AQABNQAECggIJwAPADkaAA==.Shankyews:BAAANQADCgQJBAAAAA==.Sheev:BAAANQADCgEIAQAAAA==.Shepling:BAACNQAFFIEKAAIUAAUKYg47DwAuAQAUAAUKYg47DwAuAQA1AAQKgRQAAhQACAp5FbY8AO4BABQACAp5FbY8AO4BAAAA.Shifterella:BAAANQAECgMICAAAAA==.Shifu:BAABNQAECoEYAAMIAAkKRBzNFgBuAgAIAAcKGx7NFgBuAgAaAAcKlRWjEgCaAQAAAA==.Shivàh:BAACNQAFFIEPAAMPAAUKwxZBBgCbAQAPAAUKwxZBBgCbAQAVAAMKexJKCwDhAAA1AAQKgSAAAxUACQpMIkgXAKsCABUACQpGIkgXAKsCAA8AAwqkIUB3ABQBAAAA.Shneezleberg:BAABNQAECoEZAAMGAAkKOBjKQgCpAgAGAAkKOBjKQgCpAgAkAAQKGAtYHwCdAAAAAA==.',
Si='Sildormi:BAAANQAECgEIAgAAAA==.Sithrage:BAAANQADCgQIBAAAAA==.Sizzlinghots:BAAANQAECgYIDAAAAA==.',
Sk='Skateboardp:BAAANQADCgYIBgAAAA==.Skiddlywinks:BAAANQADCgYIDwABNQAECgQICQAMAAAAAA==.Sko:BAABNQAECoEfAAIGAAkKahlcRQChAgAGAAkKahlcRQChAgAAAA==.Skár:BAAANQADCggICwAAAA==.',
Sl='Sladak:BAAANQADCgMIBAAAAA==.',
Sn='Snackdad:BAAANQADCgMIBAAAAA==.Sneakyky:BAAANQADCgcIDAAAAA==.Sneakymoomoo:BAAANQADCgYJBgABNQAECggIJQAQAGEZAA==.Snowyrain:BAAANQAECgUIBgAAAA==.',
So='Sojourner:BAAANQAECgUICQAAAA==.Solanum:BAAANQADCgQIBAABNQADCgYIBwAMAAAAAA==.Solkar:BAAANQADCgcJCwAAAA==.Solo:BAABNQAECoEiAAISAAkK7hWlVABvAgASAAkK7hWlVABvAgAAAA==.Soupsandwich:BAAANQAECgMIBQAAAA==.Sourless:BAAANQAECgEIAQAAAA==.',
St='Stagg:BAABNQAECoEfAAIHAAkKIhLzjQBIAgAHAAkKIhLzjQBIAgAAAA==.Stankazz:BAAANQABCgQIBAAAAA==.Stankytotems:BAAANQAECgEIAQAAAA==.Stinkcheese:BAAANQAECgEIAQAAAA==.Stkk:BAAANQAECggICAAAAA==.Stonedkritz:BAAANQABCgMIAwAAAA==.',
Su='Sunarii:BAAANQAECgUIEAAAAA==.Sunroof:BAAANQADCgMIBgAAAA==.Superbroke:BAAANQAECgEIAQAAAA==.Superpoor:BAAANQAECgEIAwAAAA==.',
Sw='Swagalito:BAAANQADCgUIBgAAAA==.',
['Sà']='Sàviorself:BAAANQAECgIIAgAAAA==.',
['Sý']='Sýlvanàs:BAAANQADCgMIAwAAAA==.',
Ta='Taelian:BAAANQADCgYICQAAAA==.Talanath:BAABNQAECoEXAAIbAAgKVwUlJwBcAQAbAAgKVwUlJwBcAQAAAA==.Taldor:BAAANQAECgEIAQAAAA==.Tanarran:BAAANQADCgUIBQAAAA==.Tatooth:BAAANQADCgQIBAAAAA==.Tazoo:BAAANQAECgYIEQAAAA==.',
Te='Teamfluffer:BAAANQAECgEIAQAAAA==.Tee:BAAANQADCgcIDQAAAA==.Tehzew:BAAANQAECgEIAQAAAA==.Telps:BAAANQADCgIIAgAAAA==.Teranosouth:BAAANQAECgEIAQAAAA==.Teruulos:BAAANQAECgQIBAAAAA==.',
Th='Thabeast:BAAANQAECgEIAQAAAA==.Thadeouss:BAABNQAECoEiAAIQAAkKRRv6LgCMAgAQAAkKRRv6LgCMAgAAAA==.Tharon:BAABNQAECoEYAAIFAAgKwRYFUQBUAgAFAAgKwRYFUQBUAgAAAA==.Thebigboom:BAABNQAECoEqAAIlAAkKzxvWBwDRAgAlAAkKzxvWBwDRAgAAAA==.Thecarter:BAAANQAECgIIAgAAAA==.Thoomahawk:BAAANQADCgIIAgAAAA==.Threnody:BAAANQAECgYIEAAAAA==.',
Ti='Tichalock:BAAANQADCgIIAgABNQAECgEIAQAMAAAAAA==.Tichemort:BAAANQADCgcICwAAAA==.Tigerchimon:BAAANQADCgUIBQABNQAECggIJwAPADkaAA==.Tinglem:BAAANQADCgYICwAAAA==.',
To='Tobiramaa:BAAANQAECgEIAwAAAA==.Toeclipper:BAAANQADCgYIBgAAAA==.Tolivold:BAAANQAECgQICAAAAA==.Tomeoz:BAAANQAECgEIAQAAAA==.Toxicsocks:BAABNQAECoEgAAMmAAkK2hZNAQCYAgAmAAkK2hZNAQCYAgAHAAIKGQbGiwFuAAAAAA==.',
Tr='Trapscallion:BAAANQAECgQIDAAAAA==.Trashcaster:BAAANQADCgcIDAAAAA==.Treeknight:BAABNQAECoEfAAIPAAgKYBYoQAD2AQAPAAgKYBYoQAD2AQAAAA==.Treelimbs:BAAANQAECgUIBgAAAA==.Tridity:BAAANQAECgYIEQAAAA==.Trollolollz:BAAANQAECgIIBAAAAA==.',
Ts='Tsuuna:BAABNQAECoEhAAMGAAkKihpyOADMAgAGAAkKihpyOADMAgAOAAEKkhmRNgBKAAAAAA==.',
Tu='Turböman:BAAANQAECgEIAgAAAA==.Turtleqt:BAAANQABCgEIAQAAAA==.',
Ty='Tylanar:BAAANQADCgYIBgABNQAECgIIBAAMAAAAAA==.Tylandon:BAAANQAECgQIBQAAAA==.',
['Tê']='Tênaciousv:BAAANQAECgIJBAAAAA==.',
['Të']='Tëhzoo:BAAANQABCgIIAgAAAA==.',
['Tì']='Tìnnitus:BAAANQABCgMIBAAAAA==.',
Ug='Uglyboyryan:BAAANQAECgMIAwAAAA==.',
Un='Unavaluable:BAAANQADCggIDwAAAA==.Ungodlyy:BAAANQAECgQIBgAAAA==.Untöuchable:BAABNQAECoEmAAMSAAgKZh9fPAC8AgASAAgKZh9fPAC8AgAfAAEK4gE8GgEhAAAAAA==.',
Ur='Urskrog:BAAANQADCggIEwAAAA==.',
Ve='Velachlan:BAAANQAECgUIDQAAAA==.Verdtual:BAAANQADCgMIAwAAAA==.Veredelyse:BAABNQAECoEoAAQcAAkKVRf6BgA8AgAcAAgKgxj6BgA8AgAjAAQKCQkPNQDvAAATAAMK9RK8ZwDCAAAAAA==.Verxl:BAAANQAECgUIEQAAAA==.',
Vo='Voidnyou:BAAANQADCgQJCAAAAA==.Volumes:BAAANQAECgUICwAAAA==.Volund:BAABNQAECoEfAAInAAgKjAXWGACqAQAnAAgKjAXWGACqAQAAAA==.',
Vr='Vrixz:BAAANQAECgEIAQAAAA==.',
Vy='Vynsong:BAAANQAECgcIEQAAAA==.Vyz:BAAANQADCgQIBAABNQAECgQIBQAMAAAAAA==.',
Wa='Warwalkerz:BAAANQADCggIFgAAAA==.Watermalorne:BAAANQAECgMIAwAAAA==.',
We='Weemies:BAAANQAECgUIBwAAAA==.Wetmonk:BAAANQAECgcIDQAAAA==.',
Wh='Whoyerdaddy:BAAANQAECgEIAQAAAA==.Whywhybecuz:BAAANQADCgQIBAAAAA==.',
Wi='Wickedal:BAAANQADCgIIAgAAAA==.Winndfurry:BAAANQADCgMIAwAAAA==.Winnototem:BAABNQAECoElAAMKAAkK+BIWUAD4AQAKAAkK+BIWUAD4AQALAAEKDgrLFAE0AAAAAA==.Wisakedjak:BAAANQADCggIGwAAAA==.Wix:BAAANQAECgEIAgAAAA==.',
Wo='Wombatman:BAAANQAECgMIBAAAAA==.Wong:BAAANQAECgUIBgAAAA==.',
Wu='Wutpuddle:BAAANQADCggIAQAAAA==.',
Xi='Xiaoshui:BAAANQADCgYIBgAAAA==.',
Xu='Xugos:BAABNQAECoEYAAIZAAcKGh4NVAA4AgAZAAcKGh4NVAA4AgAAAA==.',
Ya='Yatagarasu:BAAANQAECggIAgAAAA==.',
Ye='Yenafer:BAAANQABCgYIBwAAAA==.',
Yo='Yochill:BAAANQAECgIIAgABNQAECgUICgAMAAAAAA==.Yolokin:BAAANQADCgcIDAAAAA==.Yooper:BAAANQAECgEIAQAAAA==.Yota:BAAANQAECgEIAQAAAA==.',
Yr='Yrgg:BAAANQAECgYIDQAAAA==.',
Yt='Ytgamezoned:BAAANQADCgQIBAAAAA==.',
Yu='Yuna:BAAANQAECgEIBAAAAA==.',
Za='Zadanthra:BAAANQAECgQICQAAAA==.Zapadin:BAABNQAECoEZAAISAAgKoBWXcgAbAgASAAgKoBWXcgAbAgAAAA==.Zaphodè:BAAANQAECgQIBAAAAA==.',
Ze='Zephian:BAAANQAECgMIBAAAAA==.Zephsham:BAAANQADCgYIDAAAAA==.Zerokool:BAAANQABCgMIAwAAAA==.',
Zi='Zimone:BAAANQADCgMIAwAAAA==.',
Zo='Zoerik:BAABNQAECoEgAAQiAAgKAAvkCQCcAQAiAAgKAAvkCQCcAQAQAAYK2wOmmwAHAQARAAUKEwXeSADPAAAAAA==.Zotoperen:BAABNQAECoEgAAMaAAkK5iBAAwBKAwAaAAkK5iBAAwBKAwAIAAMKPRDsSACnAAAAAA==.',
Zy='Zylergy:BAABNQAECoEUAAISAAcKXQu4vgBmAQASAAcKXQu4vgBmAQAAAA==.',
['Zì']='Zìfu:BAAANQADCgcIBgAAAA==.',
['Àv']='Àvicant:BAAANQAECgUJCAABNQAFFAQICAAFAPsbAA==.',
['Än']='Ändo:BAAANQAECgQICwAAAA==.',
['Äy']='Äy:BAAANQABCgEIAQAAAA==.',
['Çy']='Çyrin:BAABNQAECoEgAAMfAAgKtRG2VwDxAQAfAAgKtRG2VwDxAQASAAEK5QiJdQEzAAAAAA==.',
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
