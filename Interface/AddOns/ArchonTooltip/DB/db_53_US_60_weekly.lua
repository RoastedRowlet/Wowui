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

local lookup = {'Hunter-Marksmanship','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Blood','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Affliction','Warlock-Destruction','Warrior-Arms','Paladin-Protection','DemonHunter-Devourer','Paladin-Holy','Mage-Arcane','Mage-Frost','DemonHunter-Havoc','Priest-Shadow',}
local provider = {region='US',realm='Darkspear',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abssorath:BAAANQADCgYIBgAAAA==.',
Ae='Aerouant:BAAANQAECgcIEAAAAA==.',
Ai='Aidix:BAAANQADCggIFQAAAA==.',
Al='Alaliix:BAAANQADCgEIAQAAAA==.Alcyone:BAAANQAECgUICgAAAA==.Allophone:BAAANQADCgIIAgAAAA==.Almightyhunt:BAAANQADCgMIAwAAAA==.Altimys:BAAANQADCgIIAgAAAA==.',
An='Antakata:BAAANQADCgcIBwAAAA==.Antapathy:BAAANQAECgUICgAAAA==.Anthross:BAAANQAECgEIAgAAAA==.',
Ap='Apollovon:BAAANQAECgcIDwAAAA==.Applebees:BAAANQAECgEIAQAAAA==.',
Ar='Arcanenug:BAAANQADCgQIBAAAAA==.Arcbnonez:BAAANQADCggIDQAAAA==.Armiggy:BAAANQAECgUICwAAAA==.Aro:BAABNQAECoEZAAMBAAkJMyQ6EgBiAgABAAcJUyA6EgBiAgACAAYJLSGYNgAfAgAAAA==.Arrowraen:BAAANQAECgUICAAAAA==.',
As='Asd:BAAANQADCgQIBAAAAA==.Asecond:BAAANQADCgMIAwAAAA==.',
Au='Audomere:BAAANQAECgQICAAAAA==.Auurwarr:BAAANQADCgUIBQAAAA==.',
Av='Avawrath:BAAANQAECgcIBwAAAA==.Avraellia:BAAANQADCgYIBQAAAA==.',
Az='Azkaellon:BAAANQADCgQIBAABNQAECgcIDwADAAAAAA==.',
Ba='Bagool:BAAANQADCgYIBgAAAA==.Bailey:BAAANQADCgIIAgABNQAECgIIAwADAAAAAA==.Ballstench:BAAANQADCgIIAgAAAA==.Barbåtos:BAAANQADCggIEQAAAA==.Bathory:BAAANQADCgYIBgAAAA==.',
Be='Bearboi:BAAANQAECgUIDAABNQADCgUIBQADAAAAAA==.Bearbomblolz:BAAANQADCgMIBAABNQADCggIGgADAAAAAA==.Bearmanakin:BAAANQADCgYICQAAAA==.Bearypotter:BAAANQADCgMIAwAAAA==.Beastly:BAAANQAECgIIAgABNQAECgIIAwADAAAAAA==.Beastmandes:BAAANQADCggIFAAAAA==.Bejeezus:BAAANQAECgUICgAAAA==.Bel:BAAANQABCgYIDAAAAA==.Bellion:BAAANQAECgYICgAAAA==.Berijar:BAAANQADCgYIBgABNQAECgIIAgADAAAAAA==.Bewslee:BAAANQADCgYICgAAAA==.Bexx:BAAANQADCggIFwAAAA==.',
Bi='Biblehumping:BAAANQAECgYIDwAAAA==.Bietk:BAAANQADCgQIBwABNQAECgUIBQADAAAAAA==.Bigbonks:BAAANQAECgQIBAAAAA==.Bigoldpumper:BAAANQAECgEIAQAAAA==.',
Bl='Blackplague:BAAANQADCgQIBQAAAA==.Bleaknight:BAAANQADCgUIBQAAAA==.Blãezer:BAAANQADCggIEAAAAA==.',
Br='Brewtoe:BAAANQAECgQIBAAAAA==.Brisketz:BAAANQADCgUIAQAAAA==.Bruneau:BAAANQABCgUIBQAAAA==.',
Bs='Bshoutbot:BAAANQADCgUIBQABNQAFFAQIBAADAAAAAA==.',
Bu='Bubblemehard:BAAANQAECgQIBAAAAA==.',
By='Byahnbreath:BAAANQADCgQIBAAAAA==.',
Ca='Cannabinoide:BAAANQAECgIIAgAAAA==.Cannatonic:BAAANQAECgEIAQAAAA==.Castielx:BAAANQAECgYICwAAAA==.Catnips:BAAANQADCgIIAgABNQAECgYIDwADAAAAAA==.',
Ce='Celestraza:BAAANQADCggICAAAAA==.Celirra:BAAANQAECgUICgAAAA==.Cennerus:BAAANQADCgIIAwAAAA==.',
Ch='Chaosreign:BAAANQADCggICwAAAA==.Cheekybaby:BAAANQAECgEIAgAAAA==.Cherrypoplol:BAAANQADCgUIDAAAAA==.Chocopaati:BAAANQAECgUIBwAAAA==.Chokma:BAAANQAECgYIBwAAAA==.Chunkyfists:BAAANQADCgMIAwAAAA==.Chëeks:BAAANQADCgUIBQAAAA==.Chìefponbury:BAAANQADCggIFQAAAA==.',
Ci='Cinnaa:BAAANQAECgUICQAAAA==.',
Cl='Clawwz:BAAANQAECgEIAQAAAA==.Cleisthenes:BAAANQAECgEIAQAAAA==.Clors:BAAANQAECgQIBAAAAA==.',
Co='Conflux:BAAANQADCggIFAAAAA==.',
Cr='Crazegideon:BAAANQABCgIIAgAAAA==.Crazespawnz:BAAANQABCgIIAgAAAA==.Cruelbeam:BAAANQADCgQIBAAAAA==.',
Cu='Curzondax:BAAANQAECggIBgAAAA==.',
Cy='Cyberfairy:BAAANQADCgQIBAAAAA==.Cyphinx:BAAANQAECgUIBQAAAA==.',
['Câ']='Câraxes:BAAANQADCgUIBAAAAA==.',
['Cä']='Cät:BAAANQAECgEIAQAAAA==.',
Da='Dahelzforyou:BAAANQADCgEIAQAAAA==.Dalìnar:BAAANQAECgIIAgAAAA==.Damadafacker:BAAANQAECgUIBgAAAA==.Darkclôud:BAAANQADCgYIDAAAAA==.Darklia:BAAANQAECgEIAQAAAA==.Darthjae:BAABNQAECoEjAAMEAAYJkhc5MQCfAQAEAAYJkhc5MQCfAQAFAAEJcAWjWAAhAAAAAA==.Darthmikkey:BAAANQADCgYIBgAAAA==.Darthrakk:BAAANQAECgUICgAAAA==.Davina:BAAANQADCgcIBwABNQAECgYIBwADAAAAAA==.Daïn:BAAANQAECgYICgAAAA==.',
De='Deadestmoonb:BAAANQABCgYIDgAAAA==.Deathalimon:BAABNQAECoEUAAMEAAcJ+A1FOQBwAQAEAAcJxwtFOQBwAQAGAAQJPg0HWADkAAAAAA==.Degion:BAAANQADCgEIAQAAAA==.Deltonn:BAAANQADCgUIBQAAAA==.Demonarian:BAAANQAECgQIBAABNQAECgcIFAAEAPgNAA==.Denerrollin:BAAANQADCgIIAgAAAA==.Depthcharge:BAAANQAECgQIBQAAAA==.Deroc:BAAANQAECgEIAgAAAA==.Deáthtáxi:BAAANQADCgYICgAAAA==.',
Di='Dinfarmer:BAAANQADCgUIBgAAAA==.Dirtycheese:BAAANQAECgUICgAAAA==.',
Dj='Djgha:BAAANQADCgYIBgAAAA==.',
Dm='Dmptrukdonna:BAAANQADCgEIAQAAAA==.',
Do='Dogfärts:BAAANQADCgQICAAAAA==.Dorunter:BAAANQAECgUICwAAAA==.',
Dr='Dragonbnonez:BAAANQADCggIBwAAAA==.Dragonforge:BAAANQADCgYIDQAAAA==.Drakujin:BAAANQADCgMIBAAAAA==.Drdoitall:BAAANQADCggICgAAAA==.Dreadnpain:BAAANQADCgEIAQAAAA==.Dreynick:BAAANQADCgQIBAAAAA==.Dripfarming:BAAANQAECgMIAwABNQAFFAQIBwAGAKsZAA==.Drnastea:BAAANQADCgYIBgAAAA==.Drstorm:BAAANQADCgYICwAAAA==.',
Ed='Edaladalrian:BAAANQADCgUIBQAAAA==.',
El='Ella:BAAANQADCgIIAgAAAA==.',
En='Enhydra:BAAANQADCggICwAAAA==.Enough:BAAANQADCgcIDAAAAA==.',
Eq='Eqv:BAABNQAECoEWAAMHAAkJSiNwAQDAAgAHAAcJkSNwAQDAAgAIAAIJUCIMMQDKAAAAAA==.',
Er='Ericolson:BAAANQAECgQICAAAAA==.Erze:BAAANQADCggIFAAAAA==.Erôman:BAAANQADCgQIBAAAAA==.',
Ev='Evé:BAAANQADCggIEAABNQAECgcIDQADAAAAAA==.',
Ez='Ezzartkal:BAAANQADCgUIBQAAAA==.',
Fa='Farmerdragon:BAAANQADCggIDgAAAA==.Favabean:BAAANQADCgUIBQABNQAECgYIIwAEAJIXAA==.',
Fe='Feathring:BAAANQADCgYIBgABNQAECgUICgADAAAAAA==.Fengshui:BAAANQADCggIEwAAAA==.Fertra:BAAANQADCgYIBgAAAA==.',
Fh='Fhedrah:BAAANQADCgEIAgAAAA==.',
Fi='Fiz:BAAANQADCgYIBgAAAA==.',
Fl='Fleepo:BAAANQAECgIIAgABNQAECggICAADAAAAAA==.Fleshnbones:BAAANQADCgEIAQAAAA==.Flourie:BAAANQAECgUICgAAAA==.Flyhawk:BAAANQADCgUIDAAAAA==.',
Fo='Foorsaken:BAAANQADCgQIBAAAAA==.',
Fu='Funkadelfic:BAAANQAECgQIBgAAAA==.',
['Fé']='Fénrír:BAAANQADCgcIBwABNQAECgQIBQADAAAAAA==.',
['Fò']='Fòxxy:BAAANQAECgEIAQAAAA==.',
Ga='Galadri:BAAANQAECgYIEAABNQAECgcICAADAAAAAA==.Garu:BAAANQADCgIIAgAAAA==.',
Ge='Geared:BAAANQAECgcIDwAAAA==.Geartryx:BAAANQADCggIDQAAAA==.',
Gh='Ghoshshadow:BAAANQADCgYIDAAAAA==.Ghostinz:BAAANQADCgYICAAAAA==.',
Gi='Gimpripper:BAAANQADCggIEgAAAA==.Giztron:BAAANQADCgYIDgAAAA==.',
Gl='Glitterp:BAAANQADCgQIBAABNQAECggIGAAEAGgZAA==.Globalcold:BAAANQAECgUIDgAAAA==.Globb:BAABNQAECoEjAAIJAAgJchPxSAAQAgAJAAgJchPxSAAQAgAAAA==.Globius:BAAANQAECgUIBwAAAA==.Gloriouscole:BAAANQAECgMIBQAAAA==.Glower:BAAANQADCgEIAQAAAA==.',
Go='Gonkz:BAAANQAECgEIAQAAAA==.',
Gr='Greekorc:BAAANQABCgQIBQAAAA==.Greenyheals:BAAANQADCgUIBQAAAA==.Gromol:BAAANQADCggIFQAAAA==.Grumby:BAAANQADCggICAAAAA==.',
Gu='Guifu:BAAANQADCgIIAgAAAA==.',
Gw='Gwendolÿn:BAAANQADCgEIAQABNQADCgQIBAADAAAAAA==.',
['Gê']='Gêralt:BAAANQADCgQIBAAAAA==.',
Ha='Hacknhaf:BAAANQADCgYIDAAAAA==.Hakubar:BAAANQADCgYIBwAAAA==.Hatebrêêd:BAAANQADCgEIAQAAAA==.',
He='Healman:BAAANQADCgUIDAAAAA==.Healsatute:BAAANQADCgMIAwAAAA==.Healylady:BAAANQADCgIIAgAAAA==.Hellyas:BAAANQABCgQIBAAAAA==.Herbs:BAAANQADCgUIBQAAAA==.Herenorthere:BAAANQAECgUIEgABNQAECgkJGAAIAFcWAA==.Hermippe:BAAANQADCgYIBgAAAA==.Hexstraits:BAAANQAFFAEIAQAAAA==.',
Hi='Hia:BAABNQAECoEbAAIEAAkJVxyaDQDjAgAEAAkJVxyaDQDjAgAAAA==.Hitlist:BAAANQADCgUIBQAAAA==.',
Ho='Holyfits:BAAANQADCgEIAQAAAA==.Hondacervix:BAAANQAECgYIBgAAAA==.Hondaimpala:BAAANQAECgQIBgABNQAECgYIIwAEAJIXAA==.Howardyou:BAAANQADCgEIAgAAAA==.',
Hu='Huhdean:BAAANQAECgUICgAAAA==.Hulxamus:BAAANQAECgYICwAAAA==.Hunterz:BAAANQAECgQIBwAAAA==.',
['Hé']='Héåthcliff:BAABNQAECoEeAAIKAAgJQCJoBAAFAwAKAAgJQCJoBAAFAwAAAA==.',
Ic='Icyblaze:BAAANQAECgQICAAAAA==.',
Il='Illumi:BAAANQADCgQIBwABNQAECgUICQADAAAAAA==.',
Im='Immigrant:BAAANQADCggICAAAAA==.',
In='Indominus:BAAANQADCgIIAgAAAA==.',
Ir='Ires:BAAANQADCgUIBQAAAA==.',
It='Itheusvalles:BAAANQADCggIEgAAAA==.Itsjerry:BAAANQADCgYICQAAAA==.',
Iw='Iwillcrushyo:BAAANQAECgEIAQAAAA==.',
Ja='Jainalynn:BAAANQADCgUIEQAAAA==.Jalenbrunson:BAAANQADCgEIAQAAAA==.Jazira:BAAANQAECgQIBAAAAA==.',
Jd='Jdarkside:BAAANQADCggIEwAAAA==.',
Je='Jeremmiah:BAAANQADCgYIEAAAAA==.',
Jh='Jhacobo:BAAANQAECgQIBwAAAA==.',
Jo='Jojupobu:BAAANQADCggICAAAAA==.Jorkinit:BAAANQAECgUICQAAAA==.',
Jr='Jragon:BAAANQAECgUICgAAAA==.',
Ju='Juicedh:BAAANQADCgUIBQAAAA==.Juicy:BAAANQAECgcIEAAAAA==.Junipur:BAAANQAECgMIBAAAAA==.',
Jx='Jxxy:BAAANQAFFAEIAQAAAA==.',
['Jú']='Júnjúnwälä:BAAANQAECgQIBgAAAA==.',
Ka='Kandance:BAAANQADCgQIBgAAAA==.Karlmagnus:BAAANQADCgcIBwAAAA==.',
Ke='Keempus:BAAANQAECggICAAAAA==.Kelvintwo:BAAANQADCgQIAgAAAA==.',
Ki='Kimbopable:BAAANQADCgUICgABNQAECgYIIwAEAJIXAA==.Kittyÿ:BAAANQAECgYICgAAAA==.',
Ko='Kozan:BAAANQADCgQIBAAAAA==.',
Kr='Krystall:BAAANQAECgUICQAAAA==.',
Ku='Kuarahy:BAAANQAECgcIEAAAAA==.Kunfugrip:BAAANQAECgcIDQAAAA==.Kurizmuh:BAAANQADCgUIBwAAAA==.',
['Kà']='Kàl:BAAANQADCgYIBgABNQAECgEIDAADAAAAAA==.',
['Kã']='Kãl:BAAANQADCgYIBgABNQAECgEIDAADAAAAAA==.',
La='Lanthos:BAABNQAECoEXAAILAAgJAxw+DQDFAgALAAgJAxw+DQDFAgAAAA==.Larthal:BAAANQADCggIEAAAAA==.Latinpapi:BAAANQAECgcIDAAAAA==.',
Le='Leemiez:BAAANQADCgUIBQAAAA==.Leyära:BAAANQADCgMIAwAAAA==.',
Li='Lilina:BAAANQAECgQIBAAAAA==.',
Lm='Lmn:BAAANQADCgUIBwAAAA==.',
Lo='Lonweh:BAAANQAECgEIAQAAAA==.Lousmage:BAAANQADCgUIBQAAAA==.Loza:BAAANQADCgQIBgABNQAECgIIAgADAAAAAA==.',
Lu='Lucith:BAAANQAECgUICgAAAA==.Luckie:BAAANQABCgMIAwABNQAECgkJFgAMAGIdAA==.Lulafairy:BAAANQADCgYICQAAAA==.Lumador:BAAANQAECgQIBAABNQAECgYIEQADAAAAAA==.Lunatick:BAAANQAECggIBQAAAA==.Lunawa:BAABNQAECoEfAAMNAAkJiSS1BQCwAwANAAkJiSS1BQCwAwAOAAMJtRHRFACvAAAAAA==.Lustbót:BAAANQAECggICAAAAA==.',
Ly='Lynnai:BAAANQADCgYIEQAAAA==.Lynxmi:BAAANQADCgEIAQAAAA==.Lyse:BAABNQAECoEXAAIPAAkJhCXfAADiAwAPAAkJhCXfAADiAwAAAA==.',
['Lê']='Lêvak:BAAANQADCgIIAgAAAA==.',
['Lô']='Lôuku:BAAANQAECgUICwAAAA==.',
Ma='Maahn:BAAANQADCgUIBQAAAA==.Macalob:BAAANQAECgQIBgAAAA==.Madallar:BAAANQAECgIIAgAAAA==.Magdagni:BAAANQADCggIEwAAAA==.Mageji:BAABNQAECoEdAAINAAgJ6iLXHAAlAwANAAgJ6iLXHAAlAwABNQADCgYIBgADAAAAAA==.Magepies:BAAANQAECgQIBgABNQAECgQIBAADAAAAAA==.Mallgoth:BAAANQAECgQIDwAAAA==.Manohar:BAAANQAECgUICAAAAA==.Mardtard:BAAANQAECgQIBAABNQAECgUIBgADAAAAAA==.Marximilian:BAAANQADCgYICgAAAA==.',
Mc='Mcflurryz:BAAANQADCgUIBQAAAA==.Mcgrubert:BAAANQAECgIIAgABNQAECggIEwADAAAAAA==.',
Me='Mechachad:BAAANQAECgMIAwAAAA==.Medlock:BAAANQADCgMIAwAAAA==.Medmasters:BAAANQABCgIIAgAAAA==.Megamango:BAAANQADCggICAABNQAECgkJGwAOAEwjAA==.Merdune:BAAANQADCgEIAQAAAA==.Metaloclypse:BAAANQADCgcICgAAAA==.Mezaryn:BAAANQADCgYIEAABNQAECggICAADAAAAAA==.Mezzoo:BAAANQAECggICAAAAA==.',
Mi='Midger:BAAANQADCgQIBAAAAA==.Millic:BAAANQAECgQIBwAAAA==.Millish:BAAANQADCgQIBAAAAA==.Minax:BAAANQAECgMIBAAAAA==.Missionsena:BAAANQAECgEIAQAAAA==.',
Mo='Moozx:BAAANQAECgEIAQAAAA==.Morgannâ:BAAANQADCgYIBwAAAA==.Mosfeat:BAAANQADCggICAABNQAECggIBQADAAAAAA==.',
Mu='Muckdile:BAAANQAECgQIBAAAAA==.Muckstab:BAAANQAFFAEIAQAAAA==.Mux:BAAANQADCggIDQAAAA==.',
Na='Narayeda:BAAANQAECgMIAwAAAA==.Nasuadia:BAAANQADCggIFAABNQAECgUIDQADAAAAAA==.',
Ne='Nekkash:BAAANQAECgQIBAAAAA==.Neredir:BAAANQADCgYIBgAAAA==.Netoraresan:BAAANQAECggIAQAAAA==.',
No='Norros:BAAANQADCgcIDAAAAA==.Novacaine:BAAANQADCgcIBwAAAA==.',
Nu='Nuvi:BAAANQAECgMIAwAAAA==.Nuvostaph:BAAANQADCgYICgAAAA==.',
Od='Odecias:BAAANQADCgUICQAAAA==.',
Og='Ogbrew:BAAANQADCgcIEAAAAA==.',
Or='Orezn:BAAANQAECgQICgAAAA==.',
Pa='Pabby:BAAANQABCgIIBAAAAA==.Painting:BAAANQADCgUIBQABNQAECgIIAgADAAAAAA==.Pallypusher:BAAANQADCgQICAAAAA==.Papiace:BAAANQAECgQIBAAAAA==.Pato:BAAANQAECgcIEgAAAA==.',
Ph='Phatnips:BAAANQAECgUICgAAAA==.',
Pi='Pigeon:BAAANQADCgUIBgAAAA==.',
Pn='Pnuts:BAABNQAECoEZAAIQAAgJ9BkyDgCOAgAQAAgJ9BkyDgCOAgAAAA==.',
Po='Popedragon:BAAANQAECgEIAgAAAA==.Poshh:BAAANQADCgQIBAAAAA==.',
Pr='Pres:BAAANQADCgIIAgAAAA==.Prisonmike:BAAANQAECgEIAQABNQAECgQIBQADAAAAAA==.Prophets:BAAANQADCgIIAgAAAA==.Pryome:BAAANQAECgQICAABNQAECgcIFAAEAPgNAA==.',
Pu='Puddiñ:BAAANQADCgMIAwAAAA==.Puffindaboof:BAAANQADCgUIBwAAAA==.Punkz:BAAANQADCgYICAABNQAECgcICAADAAAAAA==.Punpal:BAAANQADCgYIBgAAAA==.Pushmaa:BAAANQAECgUIBQAAAA==.',
Py='Pytorch:BAABNQAECoEiAAINAAYJRRvscAD0AQANAAYJRRvscAD0AQAAAA==.',
['Pó']='Póphero:BAAANQADCgcICgAAAA==.',
Qu='Queelex:BAAANQAECgcICAAAAA==.Quigzz:BAAANQAECggIEAAAAA==.Quinnie:BAAANQADCggIEAAAAA==.',
Ra='Raganarok:BAAANQADCggIGgAAAA==.Rahja:BAAANQAECgIIAgAAAA==.Ranch:BAAANQADCgUIBQAAAA==.',
Re='Realtrendy:BAAANQADCggICAABNQAECgQICAADAAAAAA==.Redranse:BAAANQADCgQIBAAAAA==.Restomania:BAAANQADCgMIAwAAAA==.',
Ro='Robinsonic:BAAANQAECgMIAwAAAA==.Rokenn:BAAANQADCggICAAAAA==.Rosabetsy:BAAANQADCgIIAgAAAA==.',
Ru='Rukiè:BAAANQAECgIIAgAAAA==.',
['Rô']='Rôbert:BAAANQAECgEIAQAAAA==.',
Sa='Saberyn:BAAANQADCggIEwAAAA==.Saenya:BAAANQAECgYIEAAAAA==.Sassynova:BAAANQADCgYICQAAAA==.',
Sc='Schvitz:BAAANQAECgMIAwAAAA==.Scopeftis:BAAANQAECgQICAAAAA==.',
Se='Seano:BAAANQAECgMIAwAAAA==.Seberology:BAABNQAECoEiAAIMAAkJ9w0lJwA4AgAMAAkJ9w0lJwA4AgAAAA==.Segagamecube:BAAANQADCgIIAgAAAA==.Sepatown:BAAANQADCggICAAAAA==.Sephi:BAAANQADCgQIBAAAAA==.',
Sh='Shaco:BAAANQAECgMIAwAAAA==.Shamanpizza:BAAANQADCgMIAwAAAA==.Shamjam:BAAANQAECgMIBQABNQAECgcIDQADAAAAAA==.Shamownage:BAAANQAECgMIBQABNQAECgcIFAAEAPgNAA==.Shankyews:BAAANQADCgIIAgAAAA==.Shepling:BAAANQAFFAIIAgAAAA==.Shifterella:BAAANQAECgEIAQAAAA==.Shifu:BAAANQAECggICAAAAA==.Shivàh:BAABNQAECoEYAAIFAAkJRiJxBQApAwAFAAkJRiJxBQApAwAAAA==.Shneezleberg:BAAANQAECgUICQAAAA==.',
Si='Sildormi:BAAANQAECgEIAQAAAA==.Sithrage:BAAANQADCgQIBAAAAA==.Sizzlinghots:BAAANQADCggIFQAAAA==.',
Sk='Skateboardp:BAAANQADCgYIBgAAAA==.Sko:BAAANQAECgcIDQAAAA==.',
Sn='Snackdad:BAAANQADCgMIBAAAAA==.Sneakymoomoo:BAAANQADCgYIBgABNQAECgYIDwADAAAAAA==.Snowyrain:BAAANQADCgIIAgABNQADCgYIBwADAAAAAA==.',
So='Solanum:BAAANQADCgQIBAAAAA==.Solkar:BAAANQADCgYICgAAAA==.Solo:BAAANQAECgYIDQAAAA==.Soupsandwich:BAAANQAECgMIBAAAAA==.Sourless:BAAANQAECgEIAQAAAA==.',
St='Stankazz:BAAANQABCgQIBAAAAA==.Stankytotems:BAAANQADCgcIEQAAAA==.Stinkcheese:BAAANQAECgEIAQAAAA==.',
Su='Sunarii:BAAANQADCggIEQAAAA==.Sunroof:BAAANQADCgMIBgAAAA==.',
Sw='Swagalito:BAAANQADCgUIBgAAAA==.',
Sy='Sydry:BAAANQADCggICAAAAA==.',
['Sà']='Sàviorself:BAAANQADCggIEwAAAA==.',
Ta='Taelian:BAAANQADCgYICQAAAA==.Talanath:BAAANQADCggIFwAAAA==.Taldor:BAAANQABCgMIAwAAAA==.Tanarran:BAAANQADCgUIBQAAAA==.Tatooth:BAAANQADCgQIBAAAAA==.Tazoo:BAAANQAECgIIAgAAAA==.',
Te='Teamfluffer:BAAANQADCgUICQAAAA==.Tee:BAAANQADCgcIDQAAAA==.Telps:BAAANQADCgIIAgAAAA==.Teranosouth:BAAANQABCgMIAwAAAA==.',
Th='Thabeast:BAAANQAECgEIAQAAAA==.Thadeouss:BAAANQAECgcIDQAAAA==.Tharon:BAAANQAECgMIBQAAAA==.Thebigboom:BAAANQAECgcIEgAAAA==.Thecarter:BAAANQAECgIIAgAAAA==.Thoomahawk:BAAANQADCgIIAgAAAA==.',
Ti='Tichalock:BAAANQADCgIIAgABNQAECgEIAQADAAAAAA==.Tigerchimon:BAAANQADCgUIBQAAAA==.Tinglem:BAAANQADCgYICwAAAA==.',
To='Tobiramaa:BAAANQABCgQIBAAAAA==.Toeclipper:BAAANQADCgYIBgAAAA==.Tolivold:BAAANQAECgQICAAAAA==.Tomeoz:BAAANQAECgEIAQAAAA==.Toxicsocks:BAAANQAECgEIAQAAAA==.',
Tr='Trapscallion:BAAANQADCgcIBwAAAA==.Trashcaster:BAAANQADCgcIDAAAAA==.Treeknight:BAAANQAECgUICQAAAA==.Treelimbs:BAAANQADCggIDgAAAA==.Tridity:BAAANQAECgYICgAAAA==.Trollolollz:BAAANQAECgIIAwAAAA==.',
Ts='Tsuuna:BAAANQAECgQICAAAAA==.',
Tu='Turtleqt:BAAANQABCgEIAQAAAA==.',
Ty='Tylanar:BAAANQADCgYIBgABNQADCgcIDAADAAAAAA==.Tylandon:BAAANQADCggICAAAAA==.',
['Tê']='Tênaciousv:BAAANQAECgEIAQAAAA==.',
['Të']='Tëhzoo:BAAANQABCgIIAgAAAA==.',
['Tì']='Tìnnitus:BAAANQABCgMIBAAAAA==.',
Ug='Uglyboyryan:BAAANQADCgIIAgAAAA==.',
Un='Unavaluable:BAAANQADCggICAAAAA==.Ungodlyy:BAAANQADCgUIDAAAAA==.Untöuchable:BAAANQAECgYICwAAAA==.',
Ur='Urskrog:BAAANQADCggIEwAAAA==.',
Ve='Verdtual:BAAANQADCgMIAwAAAA==.Veredelyse:BAAANQAECgYIDQAAAA==.Verxl:BAAANQAECgEIAgAAAA==.',
Vo='Voidnyou:BAAANQADCgQICAAAAA==.Volumes:BAAANQAECgUIBwAAAA==.Volund:BAAANQAECgQIBwAAAA==.',
Vy='Vynsong:BAAANQAECgMIBAAAAA==.Vyz:BAAANQADCgQIBAABNQAECgQIBAADAAAAAA==.',
Wa='Warwalkerz:BAAANQADCggIFQAAAA==.Watermalorne:BAAANQAECgMIAwAAAA==.',
We='Weemies:BAAANQAECgUIBgAAAA==.Wetmonk:BAAANQAECgcICwAAAA==.',
Wh='Whoyerdaddy:BAAANQADCgUIBgAAAA==.Whywhybecuz:BAAANQADCgQIBAAAAA==.',
Wi='Wickedal:BAAANQADCgIIAgAAAA==.Winkss:BAAANQAECgcIDQAAAA==.Winndfurry:BAAANQADCgMIAwAAAA==.Winnototem:BAAANQAECgUICgAAAA==.Wisakedjak:BAAANQADCggIGwAAAA==.Wix:BAAANQADCgcIBwAAAA==.',
Wo='Wong:BAAANQAECgEIAQAAAA==.',
Wu='Wutpuddle:BAAANQADCggIAQAAAA==.',
Xi='Xiaoshui:BAAANQADCgYIBgAAAA==.',
Xu='Xugos:BAAANQAECgUIBwAAAA==.',
Yo='Yochill:BAAANQAECgIIAwAAAA==.Yooper:BAAANQADCgcIBgAAAA==.Yota:BAAANQAECgEIAQAAAA==.',
Yr='Yrgg:BAAANQAECgIIAgAAAA==.',
Yu='Yuna:BAAANQABCgYICwAAAA==.',
Za='Zadanthra:BAAANQADCggIGgAAAA==.Zapadin:BAAANQAECgMIAwAAAA==.Zaphodè:BAAANQADCggIDgAAAA==.',
Ze='Zephian:BAAANQADCgYICgAAAA==.Zephsham:BAAANQADCgYIDAAAAA==.Zerokool:BAAANQABCgMIAwAAAA==.',
Zi='Zimone:BAAANQADCgMIAwAAAA==.',
Zo='Zoerik:BAAANQAECgYICgAAAA==.Zotoperen:BAAANQAECgUICgAAAA==.',
Zy='Zylergy:BAAANQAECgUIBgAAAA==.',
['Àv']='Àvicant:BAAANQAECgUIBQABNQAECgkJGQACAAUkAA==.',
['Än']='Ändo:BAAANQAECgQIBgAAAA==.',
['Äy']='Äy:BAAANQABCgEIAQAAAA==.',
['Çy']='Çyrin:BAAANQAECgUICgAAAA==.',
['Çø']='Çørpsë:BAAANQABCgIIAgAAAA==.',
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
