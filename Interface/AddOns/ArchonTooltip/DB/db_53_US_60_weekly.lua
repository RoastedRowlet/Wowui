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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','DeathKnight-Blood','DeathKnight-Frost','DeathKnight-Unholy','Warrior-Arms','Mage-Arcane','Mage-Frost','Paladin-Holy',}
local provider = {region='US',realm='Darkspear',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abssorath:BAAANQADCgYIBgAAAA==.',
Ae='Aerouant:BAAANQAECgQICQAAAA==.',
Ai='Aidix:BAAANQADCggIDgAAAA==.',
Al='Alaliix:BAAANQADCgEIAQAAAA==.Alcyone:BAAANQAECgMIBQAAAA==.Allophone:BAAANQADCgIIAgAAAA==.Almightyhunt:BAAANQADCgMIAwAAAA==.Altimys:BAAANQADCgIIAgAAAA==.',
An='Antakata:BAAANQADCgcIBwAAAA==.Antapathy:BAAANQAECgMIBQAAAA==.Anthross:BAAANQAECgEIAQAAAA==.',
Ap='Apollovon:BAAANQAECgcICQAAAA==.Applebees:BAAANQAECgEIAQAAAA==.',
Ar='Arcanenug:BAAANQADCgQIBAAAAA==.Armiggy:BAAANQAECgQIBgAAAA==.Aro:BAABNQAECoEVAAMBAAkJMyREHwA0AgACAAcJUyBHDgBwAgABAAYJLSFEHwA0AgAAAA==.Arrowraen:BAAANQAECgIIAwAAAA==.',
As='Asd:BAAANQADCgQIBAAAAA==.Asecond:BAAANQADCgMIAwAAAA==.',
Au='Audomere:BAAANQAECgQIBAAAAA==.Auurwarr:BAAANQADCgIIAgAAAA==.',
Av='Avawrath:BAAANQAECgMIAgAAAA==.Avraellia:BAAANQADCgYIBQAAAA==.',
Az='Azkaellon:BAAANQADCgQIBAABNQAECgYIDAADAAAAAA==.',
Ba='Bagool:BAAANQADCgYIBgAAAA==.Bailey:BAAANQADCgIIAgABNQAECgIIAgADAAAAAA==.Ballstench:BAAANQADCgIIAgAAAA==.Barbåtos:BAAANQADCggICQAAAA==.Bathory:BAAANQADCgYIBgAAAA==.',
Be='Bearboi:BAAANQAECgQIBwABNQABCgEIAQADAAAAAA==.Bearbomblolz:BAAANQADCgMIBAABNQADCggIEgADAAAAAA==.Bearmanakin:BAAANQADCgYICQAAAA==.Bearypotter:BAAANQADCgMIAwAAAA==.Beastly:BAAANQADCgYIBgABNQAECgIIAwADAAAAAA==.Beastmandes:BAAANQADCggIDAAAAA==.Bejeezus:BAAANQAECgMIBQAAAA==.Bel:BAAANQABCgQICAAAAA==.Bellion:BAAANQAECgUIBQAAAA==.Bewslee:BAAANQADCgYICAAAAA==.Bexx:BAAANQADCggIEAAAAA==.',
Bi='Biblehumping:BAAANQAECgQICQAAAA==.Bietk:BAAANQADCgQIBwABNQAECgUIBwADAAAAAA==.Bigoldpumper:BAAANQAECgEIAQAAAA==.',
Bl='Blackplague:BAAANQADCgQIBQAAAA==.Bleaknight:BAAANQADCgUIBQAAAA==.Blãezer:BAAANQADCggIEAAAAA==.',
Br='Brewtoe:BAAANQADCgcIDAAAAA==.Brisketz:BAAANQADCgUIAQAAAA==.',
Bu='Bubblemehard:BAAANQADCgIIAgAAAA==.',
Ca='Cannabinoide:BAAANQAECgIIAgAAAA==.Cannatonic:BAAANQAECgEIAQAAAA==.Castielx:BAAANQAECgUIBQAAAA==.Catnips:BAAANQADCgIIAgABNQAECgQICQADAAAAAA==.',
Ce='Celirra:BAAANQAECgMIBQAAAA==.Cennerus:BAAANQADCgIIAwAAAA==.',
Ch='Chaosreign:BAAANQADCgMIAwAAAA==.Cheekybaby:BAAANQAECgEIAQAAAA==.Cherrypoplol:BAAANQADCgMIBAAAAA==.Chocopaati:BAAANQAECgMIAwAAAA==.Chokma:BAAANQAECgEIAQAAAA==.Chunkyfists:BAAANQADCgMIAwAAAA==.Chëeks:BAAANQADCgUIBQAAAA==.Chìefponbury:BAAANQADCggIDAAAAA==.',
Ci='Cinnaa:BAAANQAECgUICQAAAA==.',
Cl='Clawwz:BAAANQAECgEIAQAAAA==.Cleisthenes:BAAANQAECgEIAQAAAA==.Clors:BAAANQADCgUIBQAAAA==.',
Co='Conflux:BAAANQADCggICwAAAA==.',
Cu='Curzondax:BAAANQAECggIBAAAAA==.',
Cy='Cyberfairy:BAAANQADCgQIBAAAAA==.Cyphinx:BAAANQAECgUIBQAAAA==.',
['Câ']='Câraxes:BAAANQADCgUIBAAAAA==.',
['Cä']='Cät:BAAANQAECgEIAQAAAA==.',
Da='Dahelzforyou:BAAANQADCgEIAQAAAA==.Dalìnar:BAAANQADCggIDQAAAA==.Damadafacker:BAAANQAECgEIAQAAAA==.Darkclôud:BAAANQADCgYIDAAAAA==.Darklia:BAAANQADCgcIEwAAAA==.Darthjae:BAABNQAECoEXAAMEAAYJqxYyIwCqAQAEAAYJqxYyIwCqAQAFAAEJcAWGOAAhAAAAAA==.Darthmikkey:BAAANQADCgYIBgAAAA==.Darthrakk:BAAANQAECgQIBQAAAA==.Davina:BAAANQADCgYIBgABNQAECgUIBgADAAAAAA==.Daïn:BAAANQAECgIIBAAAAA==.',
De='Deadestmoonb:BAAANQABCgYIDAAAAA==.Deathalimon:BAAANQAECgUICgAAAA==.Degion:BAAANQADCgEIAQAAAA==.Deltonn:BAAANQADCgUIBQAAAA==.Demonarian:BAAANQAECgIIAgABNQAECgUICgADAAAAAA==.Denerrollin:BAAANQADCgIIAgAAAA==.Depthcharge:BAAANQAECgEIAQAAAA==.Deroc:BAAANQAECgEIAQAAAA==.Destuk:BAAANQADCgYICgAAAA==.',
Di='Dinfarmer:BAAANQADCgUIAgAAAA==.Dirtycheese:BAAANQAECgQIBwAAAA==.',
Dj='Djgha:BAAANQADCgYIBgAAAA==.',
Dm='Dmptrukdonna:BAAANQADCgEIAQAAAA==.',
Do='Dogfärts:BAAANQADCgQICAAAAA==.Dorunter:BAAANQAECgUIBgAAAA==.',
Dr='Dragonforge:BAAANQADCgYICwAAAA==.Drakujin:BAAANQADCgMIBAAAAA==.Drdoitall:BAAANQADCggICgAAAA==.Dreynick:BAAANQADCgQIBAAAAA==.Dripfarming:BAAANQAECgMIAwABNQAECgkJGQAGAIIjAA==.Drstorm:BAAANQADCgYICwAAAA==.',
Ed='Edaladalrian:BAAANQADCgUIBQAAAA==.',
El='Ella:BAAANQADCgIIAgAAAA==.',
En='Enhydra:BAAANQADCgUIBgAAAA==.Enough:BAAANQADCgcIDAAAAA==.',
Eq='Eqv:BAAANQAECgcIDgAAAA==.',
Er='Ericolson:BAAANQAECgMIAwAAAA==.Erze:BAAANQADCgcIDAAAAA==.Erôman:BAAANQADCgQIBAAAAA==.',
Ev='Evé:BAAANQADCggIEAABNQAECgYIBgADAAAAAA==.',
Ez='Ezzartkal:BAAANQADCgUIBQAAAA==.',
Fa='Farmerdragon:BAAANQADCgYIBgAAAA==.Favabean:BAAANQADCgUIBQABNQAECgYIFwAEAKsWAA==.',
Fe='Feathring:BAAANQADCgYIBgABNQAECgMIBQADAAAAAA==.Fengshui:BAAANQADCgYICwAAAA==.Fertra:BAAANQADCgYIBgAAAA==.',
Fh='Fhedrah:BAAANQADCgEIAgAAAA==.',
Fi='Fiz:BAAANQADCgYIBgAAAA==.',
Fl='Fleshnbones:BAAANQADCgEIAQAAAA==.Flourie:BAAANQAECgMIBQAAAA==.Flyhawk:BAAANQADCgUIBwAAAA==.',
Fo='Foorsaken:BAAANQADCgIIAgAAAA==.',
Fu='Funkadelfic:BAAANQAECgQIBQAAAA==.',
Ga='Galadri:BAAANQAECgYICwAAAA==.Garu:BAAANQADCgIIAgAAAA==.',
Ge='Geared:BAAANQAECgQICAAAAA==.Geartryx:BAAANQADCggIDQAAAA==.',
Gh='Ghoshshadow:BAAANQADCgYIBwAAAA==.Ghostinz:BAAANQADCgYIBgAAAA==.',
Gi='Gimpripper:BAAANQADCggIEgAAAA==.Giztron:BAAANQADCgYIDgAAAA==.',
Gl='Glitterp:BAAANQADCgQIBAABNQAECgcIDgADAAAAAA==.Globalcold:BAAANQAECgQICQAAAA==.Globb:BAABNQAECoEfAAIHAAgJchP7LwAhAgAHAAgJchP7LwAhAgAAAA==.Globius:BAAANQAECgIIAgAAAA==.Gloriouscole:BAAANQAECgMIBAAAAA==.Glower:BAAANQADCgEIAQAAAA==.',
Go='Gonkz:BAAANQADCggIDQAAAA==.Goonspree:BAAANQADCgEIAQAAAA==.',
Gr='Greekorc:BAAANQABCgQIBQAAAA==.Grimby:BAAANQADCggICAAAAA==.Gromol:BAAANQADCggIDgAAAA==.Grumby:BAAANQADCggICAAAAA==.',
Gu='Guifu:BAAANQADCgIIAgAAAA==.',
Gw='Gwendolÿn:BAAANQADCgEIAQAAAA==.',
['Gê']='Gêralt:BAAANQADCgQIBAAAAA==.',
Ha='Hacknhaf:BAAANQADCgYIDAAAAA==.Hakubar:BAAANQADCgQIBQAAAA==.Hatebrêêd:BAAANQADCgEIAQAAAA==.',
He='Healman:BAAANQADCgQIBwAAAA==.Healsatute:BAAANQADCgMIAwAAAA==.Herenorthere:BAAANQAECgUIDQABNQAECgcIDQADAAAAAA==.Hermippe:BAAANQADCgYIBgAAAA==.Hexstraits:BAAANQAECggIDwAAAA==.',
Hi='Hia:BAAANQAFFAEIAgAAAA==.Hitlist:BAAANQADCgUIBQAAAA==.',
Ho='Holyfits:BAAANQADCgEIAQAAAA==.Hondacervix:BAAANQADCgQIBAAAAA==.Hondaimpala:BAAANQAECgMIAwABNQAECgYIFwAEAKsWAA==.Howardyou:BAAANQADCgEIAgAAAA==.',
Hu='Huhdean:BAAANQAECgMIBQAAAA==.Hulxamus:BAAANQAECgYIBgAAAA==.Hunterz:BAAANQAECgMIAwAAAA==.',
['Hé']='Héåthcliff:BAAANQAECgcIEQAAAA==.',
Ic='Icyblaze:BAAANQAECgIIAgAAAA==.',
Il='Illumi:BAAANQADCgQIBwABNQAECgUICQADAAAAAA==.',
Im='Immigrant:BAAANQADCggICAAAAA==.',
In='Indominus:BAAANQADCgIIAgAAAA==.',
Ir='Ires:BAAANQADCgUIBQAAAA==.',
Is='Ishadow:BAAANQADCgYIBwAAAA==.',
It='Itheusvalles:BAAANQADCggIDQAAAA==.Itsjerry:BAAANQADCgYICQAAAA==.',
Iw='Iwillcrushyo:BAAANQAECgEIAQAAAA==.',
Ja='Jainalynn:BAAANQADCgUIDQAAAA==.Jalenbrunson:BAAANQADCgEIAQAAAA==.Jazira:BAAANQADCggIFgAAAA==.',
Jd='Jdarkside:BAAANQADCggIEwAAAA==.',
Je='Jeremmiah:BAAANQADCgYIDwAAAA==.',
Jh='Jhacobo:BAAANQAECgMIAwAAAA==.',
Jo='Jojupobu:BAAANQADCggICAAAAA==.Jorkinit:BAAANQAECgQIBAAAAA==.',
Jr='Jragon:BAAANQAECgMIBQAAAA==.',
Ju='Juicedh:BAAANQABCgEIAQAAAA==.Juicy:BAAANQAECgQICQAAAA==.Junipur:BAAANQAECgIIAgAAAA==.',
Jx='Jxxy:BAAANQAFFAEIAQAAAA==.',
['Jú']='Júnjúnwälä:BAAANQAECgIIAgAAAA==.',
Ka='Kandance:BAAANQADCgQIBgAAAA==.Karlmagnus:BAAANQADCgcIBwAAAA==.',
Ke='Keempus:BAAANQAECggICAAAAA==.Kelvintwo:BAAANQADCgQIAgAAAA==.',
Ki='Kimbopable:BAAANQADCgUICgABNQAECgYIFwAEAKsWAA==.Kittyÿ:BAAANQAECgUIBQAAAA==.',
Kr='Krystall:BAAANQAECgQIBAAAAA==.',
Ku='Kuarahy:BAAANQAECgcICAAAAA==.Kunfugrip:BAAANQAECgYIBgAAAA==.Kurizmuh:BAAANQADCgMIAwAAAA==.',
['Kà']='Kàl:BAAANQADCgYIBgABNQAECgEIBQADAAAAAA==.',
['Kã']='Kãl:BAAANQADCgYIBgABNQAECgEIBQADAAAAAA==.',
La='Lanthos:BAAANQAECgcIDQAAAA==.Larthal:BAAANQADCggIEAAAAA==.Latinpapi:BAAANQAECgQIBQAAAA==.',
Le='Leemiez:BAAANQADCgUIBQAAAA==.Leyära:BAAANQADCgMIAwAAAA==.',
Li='Lilina:BAAANQAECgQIBAAAAA==.',
Lm='Lmn:BAAANQADCgUIBwAAAA==.',
Lo='Loza:BAAANQADCgQIBAABNQADCggIFAADAAAAAA==.',
Lu='Lucith:BAAANQAECgMIBQAAAA==.Luckie:BAAANQABCgMIAwABNQAECggIEwADAAAAAA==.Lulafairy:BAAANQADCgcICQAAAA==.Lunawa:BAABNQAECoEaAAMIAAkJ8SFNBgCTAwAIAAkJ8SFNBgCTAwAJAAMJtRFUDgC6AAAAAA==.Lustbót:BAAANQAECggICAAAAA==.',
Ly='Lynnai:BAAANQADCgYIDAAAAA==.Lynxmi:BAAANQADCgEIAQAAAA==.Lyse:BAAANQAECggIDgAAAA==.',
['Lê']='Lêvak:BAAANQADCgIIAgAAAA==.',
['Lô']='Lôuku:BAAANQAECgQIBgAAAA==.',
Ma='Maahn:BAAANQADCgUIBQAAAA==.Macalob:BAAANQAECgEIAgAAAA==.Madallar:BAAANQADCggIEgAAAA==.Magdagni:BAAANQADCggIEgAAAA==.Mageji:BAAANQAECgcIEgABNQADCgYIBgADAAAAAA==.Magepies:BAAANQAECgQIBgAAAA==.Mallgoth:BAAANQAECgQIDwAAAA==.Manohar:BAAANQAECgQIBgAAAA==.Mardtard:BAAANQADCgEIAQABNQAECgQIBQADAAAAAA==.Marximilian:BAAANQADCgYIBgAAAA==.',
Mc='Mcflurryz:BAAANQADCgUIBQAAAA==.',
Me='Mechachad:BAAANQAECgMIAwAAAA==.Medlock:BAAANQADCgMIAwAAAA==.Merdune:BAAANQADCgEIAQAAAA==.Metaloclypse:BAAANQADCgYICAAAAA==.Mezaryn:BAAANQADCgYIEAABNQADCggICQADAAAAAA==.Mezzoo:BAAANQADCggICQAAAA==.',
Mi='Millic:BAAANQAECgMIAwAAAA==.Minax:BAAANQAECgMIBAAAAA==.Missionsena:BAAANQAECgEIAQAAAA==.',
Mo='Moozx:BAAANQADCgIIAgAAAA==.Morgannâ:BAAANQADCgYIBwAAAA==.',
Mu='Muckdile:BAAANQAECgQIBAAAAA==.Muckstab:BAAANQAFFAEIAQAAAA==.Mux:BAAANQADCggIDQAAAA==.',
Na='Narayeda:BAAANQADCgcIGQAAAA==.Nasuadia:BAAANQADCggIDgABNQAECgUICQADAAAAAA==.',
Ne='Nekkash:BAAANQADCgcIBwAAAA==.',
No='Norros:BAAANQADCgcIBgAAAA==.',
Nu='Nuvi:BAAANQADCgcIEQAAAA==.Nuvostaph:BAAANQADCgYICgAAAA==.',
Od='Odecias:BAAANQADCgUIBQAAAA==.',
Og='Ogbrew:BAAANQADCgYICQAAAA==.',
Or='Orezn:BAAANQAECgQIBgAAAA==.',
Pa='Pabby:BAAANQABCgIIBAAAAA==.Pallypusher:BAAANQADCgQIBAAAAA==.Papiace:BAAANQADCgYIBgAAAA==.Pato:BAAANQAECgYIDQAAAA==.',
Ph='Phatnips:BAAANQAECgMIBQAAAA==.',
Pi='Pigeon:BAAANQADCgUIBgAAAA==.',
Pn='Pnuts:BAAANQAECgcIEAAAAA==.',
Po='Popedragon:BAAANQAECgEIAQAAAA==.Poshh:BAAANQADCgQIBAAAAA==.',
Pr='Pres:BAAANQADCgIIAgAAAA==.Prisonmike:BAAANQADCgMIAwABNQAECgQIBQADAAAAAA==.Pryome:BAAANQAECgQIBAABNQAECgUICgADAAAAAA==.',
Pu='Puddiñ:BAAANQADCgMIAwAAAA==.Puffindaboof:BAAANQADCgUIBwAAAA==.Punkz:BAAANQADCgYICAABNQAECgYICwADAAAAAA==.Punpal:BAAANQABCgYIBgAAAA==.Pushmaa:BAAANQADCggICgAAAA==.',
Py='Pytorch:BAABNQAECoEVAAIIAAYJSxZCXgDIAQAIAAYJSxZCXgDIAQAAAA==.',
['Pó']='Póphero:BAAANQADCgMIAwAAAA==.',
Qu='Queelex:BAAANQAECgUIBQABNQAECgYICwADAAAAAA==.Quigzz:BAAANQAECgUICAAAAA==.Quinnie:BAAANQADCgQICAAAAA==.',
Ra='Raganarok:BAAANQADCggIEQAAAA==.Rahja:BAAANQADCggIDgAAAA==.Ranch:BAAANQADCgUIBQAAAA==.',
Re='Realtrendy:BAAANQADCggICAABNQAECgMIBAADAAAAAA==.Redranse:BAAANQADCgQIBAAAAA==.Reebs:BAAANQADCgYIBgAAAA==.Restomania:BAAANQADCgMIAwAAAA==.',
Ro='Rosabetsy:BAAANQADCgIIAgAAAA==.',
Ru='Rukiè:BAAANQAECgIIAgAAAA==.',
['Rô']='Rôbert:BAAANQADCgQIBwAAAA==.',
Sa='Saberyn:BAAANQADCggICwAAAA==.Saenya:BAAANQAECgUICgAAAA==.Sassynova:BAAANQADCgYICQAAAA==.',
Sc='Scopeftis:BAAANQAECgQIBAAAAA==.',
Se='Seberology:BAABNQAECoEaAAIKAAkJ9w1kGQBHAgAKAAkJ9w1kGQBHAgAAAA==.Segagamecube:BAAANQADCgIIAgAAAA==.Sepatown:BAAANQADCggICAAAAA==.Sephi:BAAANQADCgQIBAAAAA==.',
Sh='Shaco:BAAANQADCgEIAQAAAA==.Shamanpizza:BAAANQADCgMIAwAAAA==.Shamownage:BAAANQAECgMIBAABNQAECgUICgADAAAAAA==.Shankyews:BAAANQADCgIIAgAAAA==.Shepling:BAAANQAECgYIBgAAAA==.Shifu:BAAANQADCggICAAAAA==.Shivàh:BAAANQAFFAEIAQAAAA==.Shneezleberg:BAAANQAECgUIBwAAAA==.',
Si='Sildormi:BAAANQADCgYICQAAAA==.Sithrage:BAAANQADCgQIBAAAAA==.Sizzlinghots:BAAANQADCgcIDQAAAA==.',
Sk='Skateboardp:BAAANQADCgYIBgAAAA==.Sko:BAAANQAECgYIBgAAAA==.',
Sn='Snackdad:BAAANQADCgMIBAAAAA==.Sneakymoomoo:BAAANQADCgYIBgABNQAECgQICQADAAAAAA==.Snowyrain:BAAANQADCgIIAgABNQADCgYIBwADAAAAAA==.',
So='Solkar:BAAANQADCgYICgAAAA==.Solo:BAAANQAECgUIBwAAAA==.Soupsandwich:BAAANQAECgIIAwAAAA==.Sourless:BAAANQAECgEIAQAAAA==.',
St='Stankazz:BAAANQABCgQIBAAAAA==.Stankytotems:BAAANQADCgcIEQAAAA==.Stinkcheese:BAAANQAECgEIAQAAAA==.',
Su='Sunarii:BAAANQADCgYICAAAAA==.Sunroof:BAAANQADCgMIBgAAAA==.',
Sw='Swagalito:BAAANQADCgUIBgAAAA==.',
Sy='Sydry:BAAANQADCggICAAAAA==.',
['Sà']='Sàviorself:BAAANQADCgYIDQAAAA==.',
Ta='Talanath:BAAANQADCggIEgAAAA==.Taldor:BAAANQABCgMIAwAAAA==.Tanarran:BAAANQADCgUIBQAAAA==.Tazoo:BAAANQADCggIEwAAAA==.',
Te='Teamfluffer:BAAANQADCgUICQAAAA==.Tee:BAAANQADCgYICQAAAA==.Telps:BAAANQADCgIIAgAAAA==.Teranosouth:BAAANQABCgMIAwAAAA==.',
Th='Thabeast:BAAANQAECgEIAQAAAA==.Thadeouss:BAAANQAECgYIBgAAAA==.Tharon:BAAANQAECgIIAgAAAA==.Thebigboom:BAAANQAECgYICwAAAA==.Thecarter:BAAANQAECgIIAgAAAA==.Thoomahawk:BAAANQADCgIIAgAAAA==.',
Ti='Tichalock:BAAANQADCgEIAQABNQAECgEIAQADAAAAAA==.Tigerchimon:BAAANQADCgUIBQAAAA==.Tinglem:BAAANQADCgYICwAAAA==.',
To='Tolivold:BAAANQAECgQICAAAAA==.Tomeoz:BAAANQAECgEIAQAAAA==.Toxicsocks:BAAANQADCgMIAwAAAA==.',
Tr='Trapscallion:BAAANQADCgcIBwAAAA==.Trashcaster:BAAANQADCgcIDAAAAA==.Treeknight:BAAANQAECgIIBAAAAA==.Treelimbs:BAAANQADCggIDgAAAA==.Tridity:BAAANQAECgQIBAAAAA==.Trollolollz:BAAANQAECgEIAQAAAA==.',
Ts='Tsuuna:BAAANQAECgQIBgAAAA==.',
Tu='Turtleqt:BAAANQABCgEIAQAAAA==.',
Ty='Tylanar:BAAANQADCgYIBgABNQADCgcIBgADAAAAAA==.Tylandon:BAAANQADCggICAAAAA==.',
['Tê']='Tênaciousv:BAAANQADCggICgAAAA==.',
['Të']='Tëhzoo:BAAANQABCgIIAgAAAA==.',
['Tì']='Tìnnitus:BAAANQABCgMIBAAAAA==.',
Un='Unavaluable:BAAANQADCggICAAAAA==.Ungodlyy:BAAANQADCgUIDAAAAA==.Untöuchable:BAAANQAECgQIBQAAAA==.',
Ur='Urskrog:BAAANQADCggIEwAAAA==.',
Ve='Verdtual:BAAANQADCgMIAwAAAA==.Veredelyse:BAAANQAECgQIBwAAAA==.Verxl:BAAANQAECgEIAgAAAA==.',
Vo='Voidnyou:BAAANQADCgQICAAAAA==.Volumes:BAAANQAECgIIAgAAAA==.Volund:BAAANQAECgQIBwAAAA==.',
Vy='Vynsong:BAAANQAECgEIAQAAAA==.Vyz:BAAANQADCgQIBAABNQAECgQIBAADAAAAAA==.',
Wa='Warwalkerz:BAAANQADCggIDgAAAA==.',
We='Weemies:BAAANQAECgQIBQAAAA==.Wetmonk:BAAANQAECgQIBAAAAA==.',
Wh='Whoyerdaddy:BAAANQADCgUIBgAAAA==.',
Wi='Wickedal:BAAANQADCgIIAgAAAA==.Winkss:BAAANQAECgcIBwAAAA==.Winndfurry:BAAANQADCgMIAwAAAA==.Winnototem:BAAANQAECgMIBQAAAA==.Wisakedjak:BAAANQADCggIFAAAAA==.Wix:BAAANQADCgcIBwAAAA==.',
Wu='Wutpuddle:BAAANQADCggIAQAAAA==.',
Xi='Xiaoshui:BAAANQADCgYIBgAAAA==.',
Xu='Xugos:BAAANQAECgIIAgAAAA==.',
Yo='Yochill:BAAANQAECgIIAwAAAA==.Yooper:BAAANQADCgcIBgAAAA==.',
Yr='Yrgg:BAAANQADCgYICwAAAA==.',
Za='Zadanthra:BAAANQADCggIEgAAAA==.Zapadin:BAAANQADCgQIBAAAAA==.Zaphodè:BAAANQADCggIDgAAAA==.',
Ze='Zephian:BAAANQADCgUIBQAAAA==.Zephsham:BAAANQADCgYIBgAAAA==.',
Zi='Zimone:BAAANQADCgMIAwAAAA==.',
Zo='Zoerik:BAAANQAECgMIBQAAAA==.Zotoperen:BAAANQAECgMIBQAAAA==.',
Zy='Zylergy:BAAANQAECgIIAgAAAA==.',
['Än']='Ändo:BAAANQAECgIIAgAAAA==.',
['Çy']='Çyrin:BAAANQAECgQIBQAAAA==.',
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
