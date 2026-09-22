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

local lookup = {'Evoker-Augmentation','Evoker-Devastation','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','Unknown-Unknown','Priest-Holy','Priest-Shadow','DeathKnight-Blood','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Affliction','Warlock-Destruction','Monk-Windwalker','Paladin-Protection','DemonHunter-Devourer','Paladin-Holy','Mage-Arcane','Mage-Frost','DemonHunter-Havoc','Rogue-Outlaw','DemonHunter-Vengeance','Rogue-Subtlety','Paladin-Retribution','Druid-Guardian',}
local provider = {region='US',realm='Darkspear',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abssorath:BAAANQADCgYIBgAAAA==.',
Ae='Aerouant:BAABNQAECoEaAAMBAAgKzBaNBQALAgABAAgKzBaNBQALAgACAAEK5AzSLAA8AAAAAA==.',
Ai='Aidix:BAAANQADCggIFQAAAA==.',
Al='Alaliix:BAAANQADCgEIAQAAAA==.Alcyone:BAAANQAECgcJEQAAAA==.Allophone:BAAANQADCgIIAgAAAA==.Almightyhunt:BAAANQADCgMIAwAAAA==.Altimys:BAAANQADCgIIAgAAAA==.',
An='Antakata:BAAANQADCgcIBwAAAA==.Antapathy:BAAANQAECgcJEQAAAA==.Anthross:BAAANQAECgYICAAAAA==.',
Ap='Apollovon:BAABNQAECoEUAAIDAAcKXR8MOgB+AgADAAcKXR8MOgB+AgAAAA==.Applebees:BAAANQAECgEJAQAAAA==.',
Ar='Arcanenug:BAAANQADCgQJBAAAAA==.Arcbnonez:BAAANQADCggIFgAAAA==.Armiggy:BAAANQAECgYJEQAAAA==.Aro:BAACNQAFFIEIAAMEAAQKaSA2BgB7AQAEAAQKaSA2BgB7AQAFAAEKFhPHHQBQAAA1AAQKgRwAAwQACQozJAUXAE8CAAQABwpTIAUXAE8CAAUABgotIfhNAAgCAAAA.Arrowraen:BAAANQAECgcJDwAAAA==.',
As='Asd:BAAANQADCgQIBAAAAA==.Asecond:BAAANQADCgYJBgAAAA==.',
Au='Audomere:BAAANQAECgUJCwAAAA==.Auurwarr:BAAANQADCggJDQAAAA==.',
Av='Avawrath:BAAANQAECggIBwAAAA==.Avraellia:BAAANQADCgYIBQAAAA==.',
Az='Azkaellon:BAAANQADCgQIBAABNQAECgcIEAAGAAAAAA==.',
Ba='Bagool:BAAANQADCgYIBgAAAA==.Bailey:BAAANQADCgIIAgAAAA==.Ballstench:BAAANQADCgIIAgAAAA==.Barbåtos:BAAANQADCggIFgAAAA==.Baskthyr:BAAANQADCgQIBAAAAA==.Bathory:BAAANQADCgYIBgAAAA==.',
Be='Bearboi:BAAANQAECgUJDQABNQADCgUIBQAGAAAAAA==.Bearbomblolz:BAAANQADCgMIBAABNQAECgEIAQAGAAAAAA==.Bearmanakin:BAAANQADCgYICQAAAA==.Bearypotter:BAAANQADCgQJBgAAAA==.Beastbane:BAAANQAECggIAQAAAA==.Beastly:BAAANQAECgIJBAAAAA==.Beastmandes:BAAANQADCggIFAAAAA==.Bejeezus:BAAANQAECgcJEQAAAA==.Bel:BAAANQABCgYIDAAAAA==.Bellion:BAAANQAECgcIEgAAAA==.Berijar:BAAANQADCgYIBgABNQAECgIIAgAGAAAAAA==.Bewslee:BAAANQAECgEJAQAAAA==.Bexx:BAAANQADCggJGQAAAA==.',
Bi='Biblehumping:BAABNQAECoEZAAMHAAcKgRloRADSAQAHAAcKgRloRADSAQAIAAYKjgqUKgBLAQAAAA==.Bietk:BAAANQADCgQIBwABNQAECgYJDgAGAAAAAA==.Bigbonks:BAAANQAECgQIBgAAAA==.Bigoldpumper:BAAANQAECgEIAQAAAA==.',
Bl='Blackplague:BAAANQADCgQIBQAAAA==.Bleaknight:BAAANQADCgUIBQAAAA==.Blessedbuns:BAAANQAECggICAAAAA==.Blueshamoo:BAAANQAECgEJAQAAAA==.Blãezer:BAAANQADCggIEAAAAA==.',
Bo='Bonex:BAAANQAECgEJAQAAAA==.',
Br='Brewtoe:BAAANQAECgQIBAAAAA==.Brisketz:BAAANQADCgUIAQAAAA==.Bruneau:BAAANQABCgUIBQAAAA==.',
Bs='Bshoutbot:BAAANQADCgUIBQABNQAFFAYJCwAEADIVAA==.',
Bu='Bubblemehard:BAAANQAECgUJCQAAAA==.',
By='Byahnbreath:BAAANQAECgcIBwAAAA==.',
Ca='Cannabinoide:BAAANQAECgIIAgAAAA==.Cannatonic:BAAANQAECgEIAQAAAA==.Casmiralda:BAAANQABCgUJBQAAAA==.Castielx:BAAANQAECgcJEgAAAA==.Catnips:BAAANQADCgIJAgABNQAECgcJGQAHAIEZAA==.',
Ce='Celestraza:BAAANQADCggIEgAAAA==.Celirra:BAAANQAECgcJEQAAAA==.Cennerus:BAAANQADCgIIAwAAAA==.',
Ch='Chaosreign:BAAANQADCggICwAAAA==.Cheekybaby:BAAANQAECgYICAAAAA==.Cherrypoplol:BAAANQADCgUIDAAAAA==.Chocopaati:BAAANQAECgUJDAAAAA==.Chokma:BAAANQAECgYJBwAAAA==.Chunkyfists:BAAANQADCgMIAwAAAA==.Chëeks:BAAANQADCgUIBQAAAA==.Chìefponbury:BAAANQADCggIGgAAAA==.',
Ci='Cinnaa:BAAANQAECgUICQAAAA==.',
Cl='Clawdog:BAAANQADCgIIAgABNQADCgcIDAAGAAAAAQ==.Clawwz:BAAANQAECgEIAQAAAA==.Cleisthenes:BAAANQAECgEIAQAAAA==.Clors:BAAANQAECgYICgAAAA==.',
Co='Conflux:BAAANQADCggIFAAAAA==.',
Cr='Crazegideon:BAAANQABCgIIAgAAAA==.Crazespawnz:BAAANQABCgIIAgAAAA==.Cruelbeam:BAAANQADCgQIBAAAAA==.',
Cu='Curzondax:BAAANQAECggJCgAAAA==.',
Cy='Cyberfairy:BAAANQAECgEJAQAAAA==.Cyphinx:BAAANQAECgUIBQAAAA==.',
['Câ']='Câraxes:BAAANQADCgUIBAAAAA==.',
['Cä']='Cät:BAAANQAECgEIAQAAAA==.',
Da='Dahelzforyou:BAAANQADCgcJCAAAAA==.Dalìnar:BAAANQAECgQJBgAAAA==.Damadafacker:BAAANQAECgcJDQAAAA==.Darkclôud:BAAANQADCgYIDAAAAA==.Darklia:BAAANQAECgMJBAAAAA==.Darthjae:BAABNQAECoErAAMJAAcKMhnKLgDtAQAJAAcKMhnKLgDtAQAKAAEKcAUXeAAhAAAAAA==.Darthmikkey:BAAANQADCgYIBgAAAA==.Darthrakk:BAAANQAECgYJEAAAAA==.Davina:BAAANQADCgcJBwABNQAECgcICAAGAAAAAA==.Daykwan:BAAANQADCgIJAgAAAA==.Daïn:BAAANQAECgYICgAAAA==.',
De='Deadestmoonb:BAAANQADCgIJAgAAAA==.Deathalimon:BAABNQAECoEcAAMJAAcKrBQzOQCwAQAJAAcKWRMzOQCwAQALAAQKEQ4aYQDvAAAAAA==.Degion:BAAANQADCgEIAQAAAA==.Deltonn:BAAANQADCgUIBQAAAA==.Demonarian:BAAANQAECgUJBQABNQAECgcIHAAJAKwUAA==.Demonpotato:BAAANQADCggJCAAAAA==.Denerrollin:BAAANQADCgIIAgAAAA==.Depthcharge:BAAANQAECgQJCQAAAA==.Deroc:BAAANQAECgEJAgAAAA==.Deáthtáxi:BAAANQAECggICAAAAA==.',
Di='Dinfarmer:BAAANQADCgUIBgAAAA==.Dirtycheese:BAAANQAECgUJCwAAAA==.',
Dj='Djgha:BAAANQADCgYIBgAAAA==.',
Dm='Dmptrukdonna:BAAANQADCgEIAQAAAA==.',
Do='Dogfärts:BAAANQADCgUJDQAAAA==.Dorunter:BAAANQAECgUIEAAAAA==.Doubledosage:BAAANQAECgMJAwAAAA==.',
Dr='Dragonbnonez:BAAANQADCggJCgAAAA==.Dragonforge:BAAANQADCgYIDQAAAA==.Drakujin:BAAANQADCgMIBAAAAA==.Drboomboom:BAAANQADCgMIAwAAAA==.Drdoitall:BAAANQAECgUJBQAAAA==.Dreadnpain:BAAANQADCgEIAQAAAA==.Dreynick:BAAANQADCgQIBAAAAA==.Dripfarming:BAAANQAECgMIAwABNQAFFAUJCwALAMIbAA==.Drnastea:BAAANQADCgYIBgAAAA==.Drstorm:BAAANQADCgYICwAAAA==.',
Ed='Edaladalrian:BAAANQADCgUIBQAAAA==.',
El='Ella:BAAANQADCgIIAgAAAA==.Elysiá:BAAANQADCggICAAAAA==.',
En='Enhydra:BAAANQADCggICwAAAA==.Enough:BAAANQADCgcIDAAAAA==.',
Eq='Eqv:BAABNQAECoEaAAMMAAkKRSSwAQDkAgAMAAcK1CSwAQDkAgANAAIKUCI9NgDFAAAAAA==.',
Er='Ericolson:BAAANQAECgUIDQAAAA==.Erze:BAAANQADCggIFAAAAA==.Erôman:BAAANQADCgQIBAAAAA==.',
Ev='Evosolz:BAEANQADCgYJBgABNQAECgQJBgAGAAAAAA==.Evé:BAAANQADCggIEAABNQAECggJFwAOAO8VAA==.',
Ez='Ezzartkal:BAAANQADCgUIBQAAAA==.',
Fa='Farmerdragon:BAAANQADCggIDgAAAA==.Favabean:BAAANQADCgUIBQABNQAECgcIKwAJADIZAA==.',
Fe='Feathring:BAAANQADCgYIBgABNQAECgcJEQAGAAAAAA==.Fengshui:BAAANQADCggIGwAAAA==.Feralco:BAAANQADCgYIBgAAAA==.Fertra:BAAANQADCgYIBgAAAA==.',
Fh='Fhedrah:BAAANQADCgEIAgAAAA==.',
Fi='Fiz:BAAANQADCgYIBgAAAA==.',
Fl='Fleepo:BAAANQAECgIIAwABNQAECggICAAGAAAAAA==.Fleshnbones:BAAANQADCgEIAQAAAA==.Flourie:BAAANQAECgcJEQAAAA==.Flyhawk:BAAANQADCgUJEQAAAA==.Flöör:BAAANQADCgUJBQAAAA==.',
Fu='Funkadelfic:BAAANQAECgUJBwAAAA==.',
['Fé']='Fénrír:BAAANQADCggIDwABNQAECgUICgAGAAAAAA==.',
['Fò']='Fòxxy:BAAANQAECgEJAQAAAA==.',
Ga='Galadri:BAAANQAECgcIEQAAAA==.Garu:BAAANQADCgIIAgAAAA==.',
Ge='Geared:BAAANQAECgcIEAAAAA==.Geartryx:BAAANQADCggIDQAAAA==.',
Gh='Ghoshshadow:BAAANQADCgYIDAAAAA==.Ghostinz:BAAANQADCgcIDwAAAA==.',
Gi='Gimpripper:BAAANQADCggJEgAAAA==.Giztron:BAAANQADCgYIDgAAAA==.',
Gl='Glitterp:BAAANQADCgQIBAABNQAECggJIAAJANoZAA==.Globalcold:BAAANQAECgcJEgAAAA==.Globb:BAABNQAECoEpAAIDAAgKTBTMXwDyAQADAAgKTBTMXwDyAQAAAA==.Globius:BAAANQAECgcJDgAAAA==.Gloriouscole:BAAANQAECgMIBQAAAA==.Glower:BAAANQADCgEIAQAAAA==.',
Go='Gonkz:BAAANQAECgEJAgAAAA==.',
Gr='Greekorc:BAAANQABCgYJBwAAAA==.Greenyheals:BAAANQADCgUIBQAAAA==.Grimby:BAAANQAECgIJAQAAAA==.Grimdisney:BAAANQADCgYJBgAAAA==.Gromol:BAAANQADCggJHQAAAA==.Grumby:BAAANQADCggICAAAAA==.',
Gu='Guifu:BAAANQADCgIIAgAAAA==.',
Gw='Gwendolÿn:BAAANQADCgUIBgAAAA==.',
['Gê']='Gêralt:BAAANQADCgQIBAAAAA==.',
Ha='Hacknhaf:BAAANQADCgYIDAAAAA==.Hakubar:BAAANQAECgMJAwAAAA==.Hatebrêêd:BAAANQADCgQIBQAAAA==.',
He='Healman:BAAANQADCgYIEgAAAA==.Healsatute:BAAANQADCgMIAwAAAA==.Healylady:BAAANQADCgQIBQAAAA==.Heiden:BAAANQADCgYJBgAAAA==.Hel:BAAANQADCgUJBQAAAA==.Hellyas:BAAANQAECgQIBAAAAA==.Herbs:BAAANQADCgUIBQAAAA==.Herenorthere:BAABNQAECoEfAAMIAAgKyxehHADpAQAIAAYKdxuhHADpAQAHAAQKMBdMbAAlAQAAAA==.Hermippe:BAAANQAECgMJAwAAAA==.Hexstraits:BAABNQAECoEZAAIJAAkKEh+cCwAhAwAJAAkKEh+cCwAhAwAAAA==.',
Hi='Hia:BAACNQAFFIEHAAIJAAMKIw0vDQDFAAAJAAMKIw0vDQDFAAA1AAQKgSEAAgkACQprHXMQAOYCAAkACQprHXMQAOYCAAAA.Hitlist:BAAANQADCgUJBQAAAA==.',
Ho='Holyfits:BAAANQADCgEIAQAAAA==.Hondacervix:BAAANQAECgYIBgAAAA==.Hondaimpala:BAAANQAECgQIBgABNQAECgcIKwAJADIZAA==.Howardyou:BAAANQADCgEIAgAAAA==.',
Hu='Huffyy:BAAANQADCgQIBAAAAA==.Huhdean:BAAANQAECgcIEQAAAA==.Hulxamus:BAAANQAECgYJCgAAAA==.Hunterramen:BAAANQADCgEJAQAAAA==.Hunterz:BAAANQAECgQJCQAAAA==.',
['Hé']='Héåthcliff:BAABNQAECoEiAAIPAAkKZSHQAwBNAwAPAAkKZSHQAwBNAwAAAA==.',
Ic='Icyblaze:BAAANQAECgcIDwAAAA==.',
Il='Illumi:BAAANQADCgQIBwABNQAECgUICQAGAAAAAA==.',
Im='Immigrant:BAAANQADCggICAAAAA==.',
In='Indominus:BAAANQADCgIIAgAAAA==.',
Ir='Ires:BAAANQADCgUIBQAAAA==.',
Is='Ishadow:BAAANQAECgMJAwAAAA==.',
It='Itheusvalles:BAAANQADCggIEgAAAA==.Itsjerry:BAAANQADCgYICQAAAA==.',
Iw='Iwillcrushyo:BAAANQAECgEIAQAAAA==.',
Ja='Jainalynn:BAAANQADCgUIEQAAAA==.Jalenbrunson:BAAANQADCgEIAQAAAA==.Jazira:BAAANQAECgcJDQAAAA==.',
Jd='Jdarkside:BAAANQAECgEJAQAAAA==.',
Je='Jeremmiah:BAAANQADCgYIEAAAAA==.',
Jh='Jhacobo:BAAANQAECgcIDgAAAA==.',
Jo='Jojupobu:BAAANQADCggICAAAAA==.Jorkinit:BAAANQAECgcJEAAAAA==.',
Jr='Jragon:BAAANQAECgUJDwAAAA==.',
Ju='Judis:BAAANQABCgUIBQAAAA==.Juicedh:BAAANQADCgUIBQAAAA==.Juicy:BAAANQAECggJEgAAAA==.Junipur:BAAANQAECgMJBwAAAA==.',
Jx='Jxxy:BAAANQAFFAMIBAAAAA==.',
['Jú']='Júnjúnwälä:BAAANQAECgYJDAAAAA==.',
Ka='Kalories:BAAANQAECgMJAwAAAA==.Kalvoid:BAAANQADCgUJBQABNQAECgMJAwAGAAAAAA==.Kandance:BAAANQAECgUIBQAAAA==.Karlmagnus:BAAANQADCgcIBwAAAA==.',
Ke='Keempus:BAAANQAECggICAAAAA==.Kelvintwo:BAAANQADCgQIAgAAAA==.',
Ki='Kimbopable:BAAANQADCgUICgABNQAECgcIKwAJADIZAA==.Kittyÿ:BAAANQAECgYJCwAAAA==.',
Ko='Kozan:BAAANQADCgQIBAAAAA==.',
Kr='Krystall:BAAANQAECgYIDwAAAA==.',
Ku='Kuarahy:BAAANQAECgcIEAAAAA==.Kunfugrip:BAABNQAECoEXAAIOAAgK7xXQFAAtAgAOAAgK7xXQFAAtAgAAAA==.Kurizmuh:BAAANQADCgUIBwAAAA==.',
['Kà']='Kàl:BAAANQADCgYJBwABNQAECgMJAwAGAAAAAA==.',
['Kã']='Kãl:BAAANQADCgYIBgABNQAECgMJAwAGAAAAAA==.',
La='Lanthos:BAABNQAECoEfAAIQAAgKHh1TDgDRAgAQAAgKHh1TDgDRAgAAAA==.Larthal:BAAANQAECgIIAgAAAA==.Latinpapi:BAAANQAECgcJDwAAAA==.',
Le='Leemiez:BAAANQADCgUIBQAAAA==.Leyära:BAAANQAECgIJAgAAAA==.',
Li='Lilina:BAAANQAECgQJBwAAAA==.',
Lm='Lmn:BAAANQADCgUIBwAAAA==.',
Lo='Lonweh:BAAANQAECgIJAgAAAA==.Lousmage:BAAANQADCgUIBQAAAA==.Loza:BAAANQADCgQIBgABNQAECgMIBQAGAAAAAA==.',
Lu='Lucith:BAAANQAECgcJEQAAAA==.Luckie:BAAANQABCgQIBQABNQAECgkJGAARAGgeAA==.Lulafairy:BAAANQAECgEJAQAAAA==.Lumador:BAAANQAECgQIBQAAAA==.Lunatick:BAAANQAECggJCQAAAA==.Lunawa:BAABNQAECoEqAAMSAAkKFSVQBwCxAwASAAkKFSVQBwCxAwATAAMKtRGoGgCrAAAAAA==.Lustbót:BAAANQAECggICAAAAA==.',
Ly='Lynnai:BAAANQADCgYIEQAAAA==.Lynxmi:BAAANQADCgEIAQAAAA==.Lyse:BAABNQAECoEdAAIUAAkKhyXxAQDIAwAUAAkKhyXxAQDIAwAAAA==.',
['Lê']='Lêvak:BAAANQADCgIIAgAAAA==.',
['Lí']='Líllith:BAAANQADCgYJBgAAAA==.',
['Lô']='Lôuku:BAAANQAECgYJEQAAAA==.',
Ma='Maahn:BAAANQADCgUIBQAAAA==.Macalob:BAAANQAECgQIBgAAAA==.Madallar:BAAANQAECgQJBgAAAA==.Magdagni:BAAANQAECgQJBAAAAA==.Mageji:BAABNQAECoElAAISAAgKcyRSHQBCAwASAAgKcyRSHQBCAwABNQADCgYIBgAGAAAAAA==.Magepies:BAAANQAECgQIBgABNQAECgQICAAGAAAAAA==.Magicfurry:BAAANQADCgcJBwABNQAECgcJGQAHAIEZAA==.Mallgoth:BAABNQAECoEVAAIFAAYKDgYdnQAmAQAFAAYKDgYdnQAmAQAAAA==.Manohar:BAAANQAECgcJDwAAAA==.Mardtard:BAAANQAECgQIBAABNQAECgUIBgAGAAAAAA==.Marximilian:BAAANQAECgMIAwAAAA==.',
Mc='Mcflurryz:BAAANQADCgUIBQAAAA==.Mcgrubert:BAAANQAECgIJAgAAAA==.',
Me='Mechachad:BAAANQAECgMIAwAAAA==.Medlock:BAAANQADCgMJAwAAAA==.Medmasters:BAAANQABCgIIAgAAAA==.Megamango:BAAANQADCggICAABNQAECgkJIQATAL0kAA==.Merdune:BAAANQADCgEIAQAAAA==.Merkén:BAAANQADCgcIAQAAAA==.Metaloclypse:BAAANQADCgcJDQAAAA==.Mezzoo:BAAANQAECggJEAAAAA==.',
Mi='Midger:BAAANQADCgQIBAAAAA==.Millic:BAAANQAECgUIDAAAAA==.Millish:BAAANQADCgQIBAAAAA==.Minax:BAAANQAECgMIBAAAAA==.Missionsena:BAAANQAECgEJAQAAAA==.Mitzrael:BAAANQADCgIJAgAAAA==.',
Mo='Moozx:BAAANQAECgEIAQAAAA==.Morgannâ:BAAANQADCgYJCgAAAA==.Mosfeat:BAAANQADCggICAABNQAECggICwAGAAAAAA==.',
Mu='Muckdile:BAAANQAECgQIBAAAAA==.Muckstab:BAAANQAFFAEIAQAAAA==.Mux:BAAANQADCggIDQAAAA==.',
Na='Narayeda:BAAANQAECgMIAwAAAA==.Nasuadia:BAAANQADCggIFAABNQAECgcJEwAGAAAAAA==.',
Ne='Nekkash:BAAANQAECgQIBAAAAA==.Neredir:BAAANQADCgYIBgAAAA==.Netoraresan:BAAANQAECggIAQAAAA==.Neytiri:BAAANQABCgQJBQAAAA==.Nezelle:BAAANQAECgIIAgABNQAECggIFgAVAIMYAA==.',
No='Nomaa:BAAANQADCgQIBAAAAA==.Noris:BAAANQAECgEJAQAAAA==.Norros:BAAANQADCgcIDAAAAA==.Novacaine:BAAANQADCgcIBwAAAA==.',
Nu='Nuvi:BAAANQAECgQIBwAAAA==.Nuvostaph:BAAANQADCggJDAAAAA==.',
Od='Odecias:BAAANQADCgUICQAAAA==.',
Og='Ogbrew:BAAANQADCgcIEAAAAA==.',
Or='Orcboken:BAAANQAECgEJAQAAAA==.Orezn:BAAANQAECgQICgAAAA==.',
Pa='Pabby:BAAANQABCgIIBAAAAA==.Painting:BAAANQAECgEJAQABNQAECgQIBgAGAAAAAA==.Pallypusher:BAAANQADCgQJCAAAAA==.Papiace:BAAANQAECgQICAABNQAECggJJgAWADofAA==.Pato:BAAANQAECgcIEgAAAA==.',
Ph='Phatnips:BAAANQAECgcJEQAAAA==.',
Pi='Piesniper:BAAANQABCgIJAgABNQADCgYIDAAGAAAAAA==.Pigeon:BAAANQADCgUIBgAAAA==.',
Pn='Pnuts:BAABNQAECoEhAAIIAAkKdxkwDQDNAgAIAAkKdxkwDQDNAgAAAA==.',
Po='Popedragon:BAAANQAECgEIAgAAAA==.Poshh:BAAANQADCgQIBAAAAA==.',
Pr='Pres:BAAANQADCgIIAgAAAA==.Prisonmike:BAAANQAECgQIBQABNQAECgUJBgAGAAAAAA==.Promise:BAAANQADCgUJBQAAAA==.Prophets:BAAANQADCgMIBQAAAA==.Pryome:BAAANQAECgQJCwABNQAECgcIHAAJAKwUAA==.',
Pu='Puddiñ:BAAANQADCgMIAwAAAA==.Puffindaboof:BAAANQADCgUIBwAAAA==.Punkz:BAAANQADCgYICAABNQAECgcIEQAGAAAAAA==.Punpal:BAAANQADCgYIBgAAAA==.Pushmaa:BAAANQAECgYJCwAAAA==.',
Py='Pyromortis:BAAANQAECgQIBAABNQAECgcJGQAHAIEZAA==.Pytorch:BAABNQAECoEqAAISAAcKrRvTbwBDAgASAAcKrRvTbwBDAgAAAA==.',
['Pó']='Póphero:BAAANQADCggIEgAAAA==.',
Qu='Queelex:BAAANQAECgcIDAABNQAECgcIEQAGAAAAAA==.Quigzz:BAABNQAECoEaAAIXAAkKDxwSBwDqAgAXAAkKDxwSBwDqAgAAAA==.Quinnie:BAAANQAECgMIAwABNQAECgUIBQAGAAAAAA==.',
Ra='Raganarok:BAAANQADCggIHQAAAA==.Rahja:BAAANQAECgQIBgAAAA==.Ranch:BAAANQADCgUIBQAAAA==.',
Re='Realtrendy:BAAANQADCggICAABNQAECgYJDQAGAAAAAA==.Redranse:BAAANQADCgQIBAAAAA==.Reebs:BAAANQAECgIJAQAAAA==.Resa:BAAANQABCgIJAgAAAA==.Restomania:BAAANQADCgMIAwAAAA==.',
Ri='Ricasti:BAAANQADCgMJAwAAAA==.',
Ro='Robinsonic:BAAANQAECgMIBQAAAA==.Rokenn:BAAANQADCggJCAAAAA==.Rosabetsy:BAAANQADCgIIAgAAAA==.Rosetastoned:BAAANQADCgIJAgAAAA==.',
Ru='Rukiè:BAAANQAECgIIAwAAAA==.',
['Rô']='Rôbert:BAAANQAECgEIAgAAAA==.',
Sa='Saberyn:BAAANQADCggJGwAAAA==.Saenya:BAABNQAECoEYAAIIAAcKARcZGQAXAgAIAAcKARcZGQAXAgAAAA==.Sassynova:BAAANQADCgYICQAAAA==.',
Sc='Schvitz:BAAANQAECgMIBAAAAA==.Scopeftis:BAABNQAECoEQAAILAAcKbR+RGwCLAgALAAcKbR+RGwCLAgAAAA==.',
Se='Seano:BAAANQAECgMIAwAAAA==.Seberology:BAABNQAECoEoAAIRAAkKEBLjJwBrAgARAAkKEBLjJwBrAgAAAA==.Segagamecube:BAAANQADCgIIAgAAAA==.Sepatown:BAAANQADCggJCAAAAA==.Sephi:BAAANQADCgQIBAAAAA==.Sergal:BAAANQADCgIIAgABNQAECgMJBwAGAAAAAA==.',
Sh='Shaco:BAAANQAECgMIAwAAAA==.Shamanpizza:BAAANQADCgMIAwAAAA==.Shamjam:BAAANQAECgQICQABNQAECgcIEwAGAAAAAA==.Shamownage:BAAANQAECgQICAABNQAECgcIHAAJAKwUAA==.Shankyews:BAAANQADCgQJBAAAAA==.Sheev:BAAANQADCgEJAQAAAA==.Shepling:BAABNQAFFIEIAAIJAAUKYg75BwA9AQAJAAUKYg75BwA9AQAAAA==.Shifterella:BAAANQAECgIJAgAAAA==.Shifu:BAAANQAFFAEIAQAAAA==.Shivàh:BAACNQAFFIEGAAIKAAMKexLCBQD4AAAKAAMKexLCBQD4AAA1AAQKgRoAAgoACQpGIj0KAAQDAAoACQpGIj0KAAQDAAAA.Shneezleberg:BAAANQAECgcIEAAAAA==.',
Si='Sildormi:BAAANQAECgEIAQAAAA==.Sithrage:BAAANQADCgQIBAAAAA==.Sizzlinghots:BAAANQAECgEIAQAAAA==.',
Sk='Skateboardp:BAAANQADCgYIBgAAAA==.Sko:BAABNQAECoEXAAIDAAgKKRaxSQBCAgADAAgKKRaxSQBCAgAAAA==.',
Sl='Sladak:BAAANQADCgEIAQAAAA==.',
Sn='Snackdad:BAAANQADCgMIBAAAAA==.Sneakyky:BAAANQADCgEIAQAAAA==.Sneakymoomoo:BAAANQADCgYJBgABNQAECgcJGQAHAIEZAA==.Snowyrain:BAAANQADCgIIAgABNQADCggICAAGAAAAAA==.',
So='Solanum:BAAANQADCgQIBAABNQADCgUIBgAGAAAAAA==.Solkar:BAAANQADCgcJCwAAAA==.Solo:BAABNQAECoEWAAIYAAgKeRHqWwDsAQAYAAgKeRHqWwDsAQAAAA==.Soupsandwich:BAAANQAECgMIBAAAAA==.Sourless:BAAANQAECgEIAQAAAA==.',
St='Stagg:BAAANQAECgcIEwAAAA==.Stankazz:BAAANQABCgQIBAAAAA==.Stankytotems:BAAANQADCgcIEQAAAA==.Stinkcheese:BAAANQAECgEIAQAAAA==.Stonedkritz:BAAANQABCgMIAwAAAA==.',
Su='Sunarii:BAAANQAECgQIBgAAAA==.Sunroof:BAAANQADCgMIBgAAAA==.',
Sw='Swagalito:BAAANQADCgUIBgAAAA==.',
Sy='Sydry:BAAANQADCggICAAAAA==.',
['Sà']='Sàviorself:BAAANQADCggJFwAAAA==.',
Ta='Taelian:BAAANQADCgYICQAAAA==.Talanath:BAAANQAECgQJBwAAAA==.Taldor:BAAANQABCgMIAwAAAA==.Tanarran:BAAANQADCgUIBQAAAA==.Tatooth:BAAANQADCgQIBAAAAA==.Tazoo:BAAANQAECgIIAgAAAA==.',
Te='Teamfluffer:BAAANQADCgUICQAAAA==.Tee:BAAANQADCgcIDQAAAA==.Telps:BAAANQADCgIIAgAAAA==.Teranosouth:BAAANQABCgMIAwAAAA==.',
Th='Thabeast:BAAANQAECgEIAQAAAA==.Thadeouss:BAABNQAECoEXAAIHAAgKhR2rKABeAgAHAAgKhR2rKABeAgAAAA==.Tharon:BAAANQAECgYJCwAAAA==.Thebigboom:BAABNQAECoEeAAIZAAgKNRuIBgCAAgAZAAgKNRuIBgCAAgAAAA==.Thecarter:BAAANQAECgIIAgAAAA==.Thoomahawk:BAAANQADCgIIAgAAAA==.',
Ti='Tichalock:BAAANQADCgIIAgABNQAECgEIAQAGAAAAAA==.Tichemort:BAAANQADCgcICAAAAA==.Tigerchimon:BAAANQADCgUIBQAAAA==.Tinglem:BAAANQADCgYICwAAAA==.',
To='Tobiramaa:BAAANQABCgQJBAAAAA==.Toeclipper:BAAANQADCgYIBgAAAA==.Tolivold:BAAANQAECgQICAAAAA==.Tomeoz:BAAANQAECgEIAQAAAA==.Toxicsocks:BAAANQAECgYIBwAAAA==.',
Tr='Trapscallion:BAAANQAECgQIBAAAAA==.Trashcaster:BAAANQADCgcIDAAAAA==.Treeknight:BAAANQAECgYIDwAAAA==.Treelimbs:BAAANQAECgEJAQAAAA==.Tridity:BAAANQAECgYIDwAAAA==.Trollolollz:BAAANQAECgIIAwAAAA==.',
Ts='Tsuuna:BAAANQAECggIEAAAAA==.',
Tu='Turtleqt:BAAANQABCgEIAQAAAA==.',
Ty='Tylanar:BAAANQADCgYIBgABNQADCgcIDAAGAAAAAA==.Tylandon:BAAANQADCggICAAAAA==.',
['Tê']='Tênaciousv:BAAANQAECgIJAwAAAA==.',
['Të']='Tëhzoo:BAAANQABCgIIAgAAAA==.',
['Tì']='Tìnnitus:BAAANQABCgMIBAAAAA==.',
Ug='Uglyboyryan:BAAANQADCgIIAgAAAA==.',
Un='Unavaluable:BAAANQADCggJCQAAAA==.Ungodlyy:BAAANQADCgYJEAAAAA==.Untöuchable:BAAANQAECgcJEgAAAA==.',
Ur='Urskrog:BAAANQADCggIEwAAAA==.',
Ve='Velachlan:BAAANQAECgEJAQAAAA==.Verdtual:BAAANQADCgMIAwAAAA==.Veredelyse:BAABNQAECoEWAAIVAAgKgxjfBABpAgAVAAgKgxjfBABpAgAAAA==.Verxl:BAAANQAECgQIBgAAAA==.',
Vo='Voidnyou:BAAANQADCgQJCAAAAA==.Volumes:BAAANQAECgUIBwAAAA==.Volund:BAAANQAECgYIDQAAAA==.',
Vy='Vynsong:BAAANQAECgUICAAAAA==.Vyz:BAAANQADCgQIBAABNQAECgQIBAAGAAAAAA==.',
Wa='Warwalkerz:BAAANQADCggIFQAAAA==.Watermalorne:BAAANQAECgMIAwAAAA==.',
We='Weemies:BAAANQAECgUIBgAAAA==.Wetmonk:BAAANQAECgcJDAAAAA==.',
Wh='Whoyerdaddy:BAAANQADCgcJCQAAAA==.Whywhybecuz:BAAANQADCgQIBAAAAA==.',
Wi='Wickedal:BAAANQADCgIIAgAAAA==.Winndfurry:BAAANQADCgMIAwAAAA==.Winnototem:BAAANQAECgcJEQAAAA==.Wisakedjak:BAAANQADCggIGwAAAA==.Wix:BAAANQADCgcJBwAAAA==.',
Wo='Wombatman:BAAANQADCggICAAAAA==.Wong:BAAANQAECgUJBQAAAA==.',
Wu='Wutpuddle:BAAANQADCggIAQAAAA==.',
Xi='Xiaoshui:BAAANQADCgYIBgAAAA==.',
Xu='Xugos:BAAANQAECgUIDAAAAA==.',
Ya='Yatagarasu:BAAANQAECggIAgAAAA==.',
Yo='Yochill:BAAANQAECgIJAwABNQAECgIJBAAGAAAAAA==.Yooper:BAAANQADCgcIBgAAAA==.Yota:BAAANQAECgEIAQAAAA==.',
Yr='Yrgg:BAAANQAECgYICAAAAA==.',
Yu='Yuna:BAAANQABCgYJCwAAAA==.',
Za='Zadanthra:BAAANQAECgEIAQAAAA==.Zapadin:BAAANQAECgUJCAAAAA==.Zaphodè:BAAANQAECgQIBAAAAA==.',
Ze='Zephian:BAAANQAECgMIAwAAAA==.Zephsham:BAAANQADCgYIDAAAAA==.Zerokool:BAAANQABCgMIAwAAAA==.',
Zi='Zimone:BAAANQADCgMIAwAAAA==.',
Zo='Zoerik:BAAANQAECgcIEQAAAA==.Zotoperen:BAAANQAECgcJEQAAAA==.',
Zy='Zylergy:BAAANQAECgYIDAAAAA==.',
['Àv']='Àvicant:BAAANQAECgUJBwABNQAECgkJHAAFAIUkAA==.',
['Än']='Ändo:BAAANQAECgQJBgAAAA==.',
['Äy']='Äy:BAAANQABCgEIAQAAAA==.',
['Çy']='Çyrin:BAAANQAECgcJEQAAAA==.',
['Çø']='Çørpsë:BAAANQABCgIJAgAAAA==.',
['Ëu']='Ëuphoria:BAAANQADCgQIBAAAAA==.',
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
