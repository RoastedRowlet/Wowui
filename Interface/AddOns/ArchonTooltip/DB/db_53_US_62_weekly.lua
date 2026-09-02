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

local lookup = {'Unknown-Unknown','Warrior-Arms',}
local provider = {region='US',realm="Dath'Remar",name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aaronius:BAAANQADCgQIBAAAAA==.',
Ad='Ade:BAAANQAECgEIAQAAAA==.Adezardre:BAAANQADCgYICQAAAA==.Admetriell:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.Advosary:BAAANQADCgUICAAAAA==.',
Ai='Aigmokthar:BAAANQAECgQIBQAAAA==.',
Ak='Akiriah:BAAANQADCggICAAAAA==.Aklo:BAAANQADCgcIDQAAAA==.',
Al='Alamysia:BAAANQADCgYICwAAAA==.Albertfist:BAAANQADCgMIAwAAAA==.Aletech:BAAANQAECgMIAwAAAA==.Ali:BAAANQADCgYIDwAAAA==.Aliesá:BAAANQADCgUICAAAAA==.Alilea:BAAANQADCgQIBAAAAA==.Alimagus:BAAANQADCggICAABNQAECgcIDAABAAAAAA==.Alisandrah:BAAANQAECgcIDQAAAA==.Alison:BAAANQADCgQIBgAAAA==.Allakeer:BAAANQAECgYICAAAAA==.Altarios:BAAANQADCgYIDAAAAA==.Alyyix:BAAANQADCgQICgAAAA==.',
Am='Amber:BAAANQADCgcIDQAAAA==.Ambertastic:BAAANQADCgUICgABNQADCgcIDQABAAAAAA==.Amilandris:BAAANQAECgIIBgAAAA==.',
An='Analalea:BAAANQADCgUIBgAAAA==.Analdrainal:BAAANQAECgIIAgAAAA==.Annaris:BAAANQADCgIIAgAAAA==.',
Ap='Apophani:BAAANQADCgUICAAAAA==.Appolo:BAAANQADCgcIBwAAAA==.',
Ar='Arcanegasm:BAAANQAECgUIBQAAAA==.Archii:BAAANQADCgcIBwABNQAECgMIAwABAAAAAA==.Archslayer:BAAANQADCggIDQAAAA==.Arneus:BAAANQADCgcIBwAAAA==.Arnir:BAAANQADCgYIDwAAAA==.Arriving:BAAANQAECgIIAgAAAA==.Artaq:BAAANQADCgUICAAAAA==.Arvanon:BAAANQAECgEIAQAAAA==.',
As='Ashanar:BAAANQADCgcICAAAAA==.Asharla:BAAANQADCgYICwAAAA==.Ashbringa:BAAANQADCggIDQAAAA==.Ashhunt:BAAANQAECgQIBQAAAA==.Ashmend:BAAANQADCgYICQAAAA==.Asorrow:BAAANQAECgQICAAAAA==.Assatur:BAAANQADCgYIBgAAAA==.Astarna:BAAANQADCgYICwAAAA==.Asteríx:BAAANQADCgQICAAAAA==.',
At='Atlasursidae:BAAANQADCggICAAAAA==.Atoniah:BAAANQADCgYIBgAAAA==.',
Au='Auraz:BAAANQAECgEIAQAAAA==.',
Av='Avelinna:BAAANQADCgcIDQAAAA==.',
Az='Aztrayel:BAAANQADCgYICwAAAA==.',
Ba='Baalial:BAAANQADCgcIDAAAAA==.Baboya:BAAANQAECgYIAQAAAA==.Baelgrim:BAAANQADCgYICgAAAA==.Baly:BAAANQADCgYIDAABNQAECgUIBQABAAAAAA==.Bangbangbro:BAAANQADCgYIDwAAAA==.Barium:BAAANQADCgEIAQAAAA==.',
Be='Belfrostbolt:BAAANQADCgYICQAAAA==.Bentt:BAAANQABCgQIBAAAAA==.Bettÿ:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.',
Bi='Bigjawden:BAAANQADCgUICAAAAA==.Billbee:BAAANQADCgcIBwAAAA==.Bimbohaggins:BAAANQAECgMIAwABNQAECgQIBQABAAAAAA==.Bimbò:BAAANQADCgYIDwAAAA==.Binchicken:BAAANQADCgUICgAAAA==.Bingler:BAAANQABCgMIAwAAAA==.',
Bj='Bjornshockz:BAEANQADCggIDwAAAA==.',
Bl='Blaz:BAAANQAECgQIBgAAAA==.Blockz:BAAANQADCggICQAAAA==.Bloodboi:BAAANQADCgcIDQAAAA==.Bluecups:BAAANQADCgcICwAAAA==.',
Bo='Bonedecays:BAAANQADCgMIBAAAAA==.Bontoad:BAAANQADCggIDwAAAA==.',
Br='Brewaresx:BAAANQADCggICAAAAA==.Brutus:BAAANQAECgEIAQAAAA==.',
Bu='Bubbleduck:BAAANQADCgIIAgAAAA==.Buggzz:BAAANQAECgUIBgAAAA==.',
Bz='Bzlthazyr:BAAANQAECgUIBQAAAA==.',
Ca='Cahtbl:BAAANQADCgYICQAAAA==.Callin:BAAANQADCgUICQAAAA==.Calyx:BAAANQADCgYICQAAAA==.Casay:BAAANQADCggIDQAAAA==.Casbot:BAAANQAECgYICQAAAA==.Cashmere:BAAANQADCgUICAABNQAECgEIAQABAAAAAA==.Castalight:BAAANQADCgYICwAAAA==.',
Ch='Charlee:BAAANQADCgQIBgAAAA==.Chirran:BAAANQAECgIIBAAAAA==.Chxdzilla:BAAANQAECgcIDAAAAA==.',
Ci='Cinnamõn:BAAANQABCgMIAwAAAA==.',
Co='Corldrin:BAAANQADCgcICgAAAA==.Coronis:BAAANQADCggIDQAAAA==.Corriana:BAAANQADCgUICgABNQADCgcIDQABAAAAAA==.Corwin:BAAANQADCgQICgAAAA==.',
Cr='Crazee:BAAANQAECgYICgAAAA==.Cruz:BAAANQAECgQIBgAAAA==.Crystalflame:BAAANQADCgUIBwAAAA==.Crìsp:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.',
Ct='Ctshammy:BAAANQAECgEIAQAAAA==.',
Cu='Cultistt:BAAANQAECgQIBAAAAA==.Cursedyou:BAAANQADCgcICwAAAA==.Curserot:BAAANQADCggIDgAAAA==.',
Cy='Cynal:BAAANQAECgIIAgAAAA==.',
Da='Daddyy:BAAANQADCggICAABNQAECgYICgABAAAAAA==.Dammo:BAAANQADCgUICAAAAA==.Dantallion:BAAANQADCgUICAAAAA==.Darkholme:BAAANQADCgUIDwAAAA==.Darkk:BAAANQADCgEIAQAAAA==.Darthdraik:BAAANQADCgYIBgAAAA==.',
Dc='Dcver:BAAANQAECgIIBgAAAA==.',
De='Deademeat:BAAANQADCgMIAwAAAA==.Deadlynewbz:BAAANQAECgYICAAAAA==.Deathboom:BAAANQADCgUIBQABNQAECgYIBgABAAAAAA==.Deathbyshoe:BAAANQADCgYIBwAAAA==.Deathjam:BAAANQADCgcIDQAAAA==.Deathmore:BAAANQADCggIDQAAAA==.Deathshrine:BAAANQADCgUIBQAAAA==.Decypha:BAAANQAECgEIAQAAAA==.Deiwos:BAAANQAECgIIAgAAAA==.Delichtable:BAAANQADCgUICgABNQADCgcIDQABAAAAAA==.Demodog:BAAANQAECgQIBQAAAA==.Demonicnight:BAAANQAECgEIAQAAAA==.Denja:BAAANQADCggIBgAAAA==.Derryth:BAAANQADCggIEAAAAA==.Devpro:BAAANQAECgEIAQAAAA==.Dexillo:BAAANQAECgcIDQAAAA==.',
Dh='Dhaveira:BAAANQAECgMIAwAAAA==.',
Di='Divinegirly:BAAANQADCgYICwAAAA==.',
Do='Dodgeanaxe:BAABNQAECoEcAAICAAgJ0g5bGgAxAgACAAgJ0g5bGgAxAgAAAA==.Dojoe:BAAANQAECgIIBgAAAA==.',
Dr='Dracnock:BAAANQAECgIIAgAAAA==.Drinian:BAAANQADCgEIAQAAAA==.',
Du='Ducker:BAAANQAECgcICwAAAA==.',
Dy='Dylexd:BAAANQADCgIIAgAAAA==.',
Ec='Eccentricity:BAAANQADCgYIBwAAAA==.',
El='Elementi:BAAANQADCgIIAgAAAA==.Eliasidris:BAAANQADCgQIBAAAAA==.Elmaco:BAAANQAECgEIAQAAAA==.Elphkilla:BAAANQADCgYIBgAAAA==.Elroth:BAAANQADCgYIBwAAAA==.Elseapi:BAAANQADCgcICAAAAA==.Elyssae:BAAANQAECgIIAgAAAA==.',
En='Endarios:BAAANQADCgEIAQAAAA==.Endsplit:BAAANQADCgcIDAAAAA==.',
Er='Erzalockhart:BAAANQADCgUIBQAAAA==.',
Es='Esmaralda:BAAANQADCgIIAgAAAA==.',
Ev='Everleaf:BAAANQADCgQIBgAAAA==.Eviion:BAAANQADCgQIBQAAAA==.',
Fa='Fallendivine:BAAANQAECgIIAgAAAA==.',
Fe='Feetenjoyer:BAAANQADCgMIAwAAAA==.Feipo:BAAANQAECgYICQAAAA==.Fensmage:BAAANQADCggIDwAAAA==.Feralbuffkty:BAAANQAECgcIDAAAAA==.Fere:BAAANQAECgUICAAAAA==.Feurekt:BAAANQAECgQIBgAAAA==.',
Fi='Finitaur:BAAANQADCgQIBwAAAA==.',
Fl='Flashinlight:BAAANQADCggICwAAAA==.Flashstép:BAAANQADCgYIBgAAAA==.Flipside:BAAANQADCgYIDAAAAA==.',
Fo='Fomor:BAAANQADCggICAAAAA==.Forbs:BAAANQADCgMIAwAAAA==.Foreignerr:BAAANQAECgcIDAAAAA==.',
Fr='Franziscka:BAAANQADCgYICwAAAA==.',
Fu='Furbold:BAAANQAECgYIBgAAAA==.',
['Fí']='Fíredup:BAAANQADCggIDwABNQADCggIDwABAAAAAA==.',
Ga='Gallene:BAABNQAECoEcAAICAAgJ8R7kCgDoAgACAAgJ8R7kCgDoAgAAAA==.Garakarak:BAAANQADCggICAAAAA==.Garthinian:BAAANQADCgYICQAAAA==.Garthpally:BAAANQADCgMIAwAAAA==.',
Ge='Genimaculata:BAAANQAECgEIAQAAAA==.Gerothos:BAAANQADCgQIBAAAAA==.',
Gh='Ghislaine:BAAANQADCgQIBQAAAA==.',
Gl='Glarry:BAAANQADCggICAABNQAECggIDwABAAAAAA==.Glidelicator:BAAANQAECgMIAwAAAA==.',
Go='Goodasnew:BAAANQADCgYIDAAAAA==.Gortopia:BAAANQADCgUIBQAAAA==.Gosublood:BAAANQAECgIIAgAAAA==.Gosupriest:BAAANQADCgcIBwAAAA==.',
Gr='Graggy:BAAANQAECggIDwAAAA==.Grapejelly:BAAANQAECgMIBAAAAA==.Grashk:BAAANQADCgcIDAAAAA==.Grimbel:BAAANQADCgcIDAAAAA==.',
Ha='Hadeshunt:BAAANQADCgcIEAAAAA==.Halzarius:BAAANQADCgcIDQAAAA==.Handywar:BAAANQAECgQIBgAAAA==.Hans:BAAANQADCgYIBwAAAA==.Harleybear:BAAANQADCgQIBgAAAA==.',
Ho='Holymender:BAAANQADCgEIAQAAAA==.',
Hu='Hulkamania:BAAANQADCgMIAwAAAA==.Humble:BAAANQADCgcIDgAAAA==.',
Hy='Hydromender:BAAANQAECgEIAQAAAA==.',
['Hø']='Høpeless:BAAANQAECgIIAgAAAA==.',
Ic='Icycookiex:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Icymilkyx:BAAANQAECgIIAgAAAA==.',
Ig='Igneel:BAAANQADCgYIBgAAAA==.',
Il='Illigniteyou:BAAANQAECgIIBAAAAA==.',
In='Inosolan:BAAANQADCgcIDQAAAA==.Inurfacevegi:BAAANQADCgYICAABNQADCgcICwABAAAAAA==.',
Io='Iozt:BAAANQAFFAEIAQAAAA==.',
Ir='Irritable:BAAANQADCgEIAQAAAA==.Irvina:BAAANQAECgQIBAAAAA==.Irvinia:BAAANQADCggIEgABNQAECgQIBAABAAAAAA==.',
Is='Iskarius:BAAANQAECgEIAQAAAA==.Istenn:BAAANQAECgEIAQAAAA==.',
It='Ithyl:BAAANQADCgYICwAAAA==.Itzshammy:BAAANQAECgIIAgAAAA==.',
Iv='Ivanoviaa:BAAANQADCgMIAwAAAA==.',
Ja='Janinda:BAAANQAECgQIBgAAAA==.Jastina:BAAANQADCgcIDQAAAA==.Jaszz:BAAANQAECgIIAgAAAA==.',
Jb='Jb:BAAANQADCggIDwAAAA==.',
Je='Jelly:BAAANQADCgcIDAAAAA==.Jesto:BAAANQAECgIIBgAAAA==.',
Jh='Jhonn:BAAANQADCgYIDAAAAA==.',
Jo='Joeseppe:BAAANQADCgYIBgABNQAECgIIBgABAAAAAA==.Joshst:BAAANQADCgUICQAAAA==.Josta:BAAANQADCgQIBAABNQAECgIIBgABAAAAAA==.Josto:BAAANQADCgUICgABNQAECgIIBgABAAAAAA==.Jovyll:BAAANQADCgcIFwAAAA==.',
Ju='Jurodice:BAAANQAECgMIAwAAAA==.',
Ka='Kaelinth:BAAANQADCgYIBgAAAA==.Kaelyth:BAAANQADCgcICAAAAA==.Kamakazie:BAAANQADCgYIBgAAAA==.Karmerre:BAAANQADCgIIAgAAAA==.Kaydeebug:BAAANQAECgQIBAAAAA==.Kayna:BAAANQADCggIEAAAAA==.',
Ke='Kellanis:BAAANQAECgEIAQAAAA==.Kelugar:BAAANQADCgIIAgAAAA==.Kerenarye:BAAANQAECgYIBgAAAA==.',
Kh='Khaladore:BAAANQADCggIDgAAAA==.',
Ki='Kiilbill:BAAANQADCgcIBwABNQADCgYICgABAAAAAA==.Killshotbob:BAAANQADCgQIBAAAAA==.Kinkyheaven:BAAANQAECgQIBAAAAA==.Kinnigit:BAAANQAECgMIAwAAAA==.Kinstalz:BAAANQADCgIIAgAAAA==.Kiotia:BAAANQADCgIIAgAAAA==.Kipp:BAAANQADCgcICwAAAA==.Kiril:BAAANQADCgUIBQAAAA==.Kirky:BAAANQADCgQIBQAAAA==.Kithraah:BAAANQAECgYICgAAAA==.Kithrah:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.',
Kn='Knifeparty:BAAANQADCgcIDQAAAA==.',
Ko='Kolugar:BAAANQAECgUIBgAAAA==.Konkar:BAAANQAECgQIBQAAAA==.',
Kr='Kradon:BAAANQADCgcIDQAAAA==.Kruphix:BAAANQADCgYIBgAAAA==.Krysania:BAAANQADCgQIBAABNQADCggIDgABAAAAAA==.',
Ku='Kudreanne:BAAANQADCgQICgAAAA==.Kuri:BAAANQADCggICAAAAA==.',
La='Laiceeshay:BAAANQADCgYICwAAAA==.Lars:BAAANQAECgIIAgAAAA==.Larxe:BAAANQADCggIEAAAAA==.',
Le='Legendaïry:BAAANQADCgQIBQAAAA==.Letmedie:BAAANQADCggIDwAAAA==.Lexillo:BAAANQAECgQIBAAAAA==.',
Li='Liaravara:BAAANQADCgcICwAAAA==.Lightmender:BAAANQADCgQIBAAAAA==.Lilldemon:BAAANQADCgUICAAAAA==.Lizzo:BAAANQADCggIDgAAAA==.',
Lo='Lorieyxo:BAAANQADCgYICwAAAA==.Lorrim:BAAANQADCgYIDgAAAA==.Louron:BAAANQABCgEIAQAAAA==.',
Lu='Luena:BAAANQADCgcIBwAAAA==.Lunabi:BAAANQAECgEIAQABNQAECgYIBgABAAAAAA==.Luxdae:BAAANQADCgEIAQAAAA==.',
Ly='Lyrannia:BAAANQAECgEIAQAAAA==.Lyth:BAAANQAECgIIAgAAAA==.',
['Lá']='Láiken:BAAANQADCgYIDAAAAA==.',
Ma='Madmoxxie:BAAANQADCgUIBQAAAA==.Magetom:BAAANQAECgEIAQAAAA==.Maghan:BAAANQADCgQICAAAAA==.Magicus:BAAANQADCgUIBQAAAA==.Magikaze:BAAANQAECgEIAQAAAA==.Mahgo:BAAANQADCggIDgAAAA==.Maikara:BAAANQADCgYIBgAAAA==.Malfalcator:BAAANQADCgMIAwAAAA==.Marieh:BAAANQADCgUIBQAAAA==.Martha:BAAANQABCgQIBQAAAA==.Masscarnage:BAAANQAECgEIAgAAAA==.Maywina:BAAANQAECgIIAwABNQAECgIIBgABAAAAAA==.Mazhun:BAAANQADCggIDQAAAA==.',
Me='Meaculpa:BAAANQAECgEIAQAAAA==.Megaflame:BAAANQADCgMIBwAAAA==.Mekkii:BAAANQADCgIIAgABNQAECgYIBgABAAAAAA==.Mekky:BAAANQAECgYIBgAAAA==.Melonheadx:BAAANQADCgIIAgAAAA==.Meltharion:BAAANQADCgQICAAAAA==.Methex:BAAANQAECgEIAQAAAA==.Metzger:BAAANQADCgMIAwAAAA==.',
Mi='Mingi:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.Minigore:BAAANQAECgEIAgAAAA==.Mirya:BAAANQADCgYICwAAAA==.Mishamigo:BAAANQADCgcICQAAAA==.Missharmony:BAAANQADCgYICwAAAA==.Misstickles:BAAANQAECgEIAQAAAA==.',
Mo='Moistpawjob:BAAANQAECgYICgAAAA==.Mojostormale:BAAANQADCgEIAQAAAA==.Monanarr:BAAANQADCgEIAQABNQADCgcIBwABAAAAAA==.Monmonk:BAAANQADCgcIBwAAAA==.Moograin:BAAANQABCgQIBAAAAA==.Moonalisa:BAAANQADCgQICAAAAA==.Moondropz:BAAANQADCgUIBQAAAA==.Moonsblood:BAAANQADCgYICwAAAA==.Moontara:BAAANQAECgEIAgAAAA==.Moopsy:BAAANQADCgcIEwAAAA==.Mops:BAAANQADCgcIDAAAAA==.',
Mu='Mur:BAAANQADCgcIBwAAAA==.',
My='Mycotoxin:BAAANQADCgYIDAAAAA==.Mysst:BAAANQADCgcICAAAAA==.Mysteerie:BAAANQADCggIDQAAAA==.Mythlogic:BAAANQADCgcIDQAAAA==.Mythsham:BAAANQADCgQIBgAAAA==.',
['Má']='Mángo:BAAANQAECgQIBAAAAA==.',
['Mù']='Mùshu:BAAANQADCgQIBAAAAA==.',
Na='Nardaran:BAAANQADCgQIBAAAAA==.Natsumi:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.',
Ne='Needcoffee:BAAANQADCgUIBwAAAA==.Neemixa:BAAANQADCgUICQAAAA==.Neonh:BAAANQADCgUICAAAAA==.',
Ni='Nightwissh:BAAANQADCgcICAAAAA==.Nitestar:BAAANQADCgQIBgAAAA==.Nitevoker:BAAANQAECgIIAgAAAA==.',
No='Nordvoker:BAAANQAECgIIAgAAAA==.Nospheratu:BAAANQAECgQIDQABNQADCgYIBgABAAAAAA==.',
Nu='Nubu:BAAANQADCgIIAgAAAA==.',
Ny='Nycepala:BAAANQADCgUICAAAAA==.Nylaith:BAAANQADCgUIBQAAAA==.Nyni:BAAANQAECgcIDAAAAA==.Nythshade:BAAANQADCgYIBgAAAA==.',
['Nü']='Nümnüts:BAAANQADCgcIDAAAAA==.',
Of='Offworlder:BAAANQADCgUIBQAAAA==.',
On='Onlyhoofs:BAEANQAECgUIBgAAAA==.',
Oo='Oofm:BAAANQAECgEIAQAAAA==.Oospider:BAAANQADCgQIEAAAAA==.',
Op='Ophearia:BAAANQADCgUIBwAAAA==.Optimiss:BAAANQADCgQIBwAAAA==.',
Or='Orcboy:BAAANQADCggIEAAAAA==.Orken:BAAANQADCgEIAQAAAA==.Orthanu:BAAANQADCgUIBQAAAA==.',
Pa='Paieth:BAAANQAECgEIAQAAAA==.Paladerp:BAAANQAECgMIAwAAAA==.Pallyshunter:BAAANQAECgEIAQAAAA==.Panchamp:BAAANQADCgcIDgAAAA==.Pandamourne:BAAANQADCgcICQAAAA==.Pandori:BAAANQAECgEIAQAAAA==.Parchmentham:BAAANQAECgMIAwAAAA==.Paryniux:BAAANQAECgEIAQAAAA==.Patience:BAAANQADCgMIAwAAAA==.',
Pi='Pinchiy:BAAANQADCgQIBAAAAA==.Pinkpanthir:BAAANQAECgEIAQAAAA==.',
Pl='Plisky:BAAANQADCgIIAgAAAA==.',
Po='Pollywaffle:BAAANQADCgQIBAAAAA==.Poùnd:BAAANQADCgYIDAABNQADCggIDwABAAAAAA==.',
Pr='Praiseme:BAAANQADCgUICAAAAA==.Predz:BAAANQADCgYIDAAAAA==.',
Ps='Psyreq:BAAANQADCgcIDgAAAA==.',
Pu='Punkey:BAAANQADCgcIDwAAAA==.',
Qu='Quartquartma:BAAANQADCggIDQAAAA==.',
Ra='Raedia:BAAANQADCgMIAwAAAA==.Rahll:BAAANQABCgIIBAAAAA==.Ravachiar:BAAANQADCggIGAAAAA==.Ravenathas:BAAANQADCgUIDQAAAA==.Ravenimus:BAAANQADCgMIAwABNQADCgUIDQABAAAAAA==.Ravic:BAAANQADCgYIBgAAAA==.Razeld:BAAANQADCgUICAAAAA==.Razhun:BAAANQADCgcICAAAAA==.Razia:BAAANQADCgYIDAAAAA==.Razzmata:BAAANQAECgEIAQAAAA==.',
Re='Reckendorf:BAAANQADCgYIBgAAAA==.Reflet:BAAANQADCggIDgAAAA==.Rell:BAAANQAECgUIBgAAAA==.Rentress:BAAANQADCgQICgAAAA==.Restik:BAAANQADCgcICwAAAA==.Revyre:BAAANQADCgIIAgAAAA==.Rexxnaar:BAAANQADCgMIBAAAAA==.Rexy:BAAANQADCggIDwAAAA==.',
Rh='Rhiotannis:BAAANQADCggIDwAAAA==.Rhombus:BAAANQADCgYIBgAAAA==.Rhots:BAAANQAECgIIAgAAAA==.',
Ri='Ricketyrekt:BAAANQADCgcIBwAAAA==.Rimara:BAAANQADCgcIDQAAAA==.Rishari:BAAANQADCgIIAgAAAA==.',
Ro='Rocadin:BAAANQADCggIDwAAAA==.Rorisala:BAAANQADCgYICwAAAA==.Rottlee:BAAANQADCgEIAQAAAA==.Rowshamboe:BAAANQADCgQICgAAAA==.Rozabella:BAAANQAECgEIAQAAAA==.',
Ru='Rune:BAAANQAECgIIAgABNQAECgYICAABAAAAAA==.',
['Rê']='Rêdylive:BAAANQADCgYIDAAAAA==.',
Sa='Saelska:BAAANQAECgEIAQAAAA==.Sahven:BAAANQADCgEIAQAAAA==.Sakuraharu:BAAANQADCgcIDAAAAA==.Sakuraharuno:BAAANQAECgMIAwAAAA==.Sakuura:BAAANQADCgYIAQAAAA==.Sarang:BAAANQAECgMIAwAAAA==.Sassystrasza:BAAANQADCgQIBAAAAA==.Savagepaw:BAAANQADCggIEAAAAA==.',
Sc='Scarbz:BAAANQADCggIDgAAAA==.',
Se='Selennys:BAAANQADCgQIBwAAAA==.',
Sh='Shadowkain:BAAANQADCgYICwAAAA==.Shadøws:BAAANQAECgEIAQAAAA==.Shagz:BAAANQADCgQICgAAAA==.Shallios:BAAANQADCgYICwAAAA==.Shamankiing:BAAANQABCgIIAwAAAA==.Shamnow:BAAANQADCgEIAQAAAA==.Shaytan:BAAANQADCgcICAAAAA==.Sheogorath:BAAANQAECgQIBAAAAA==.Shocksocks:BAAANQADCggIDgAAAA==.Shoujian:BAAANQADCgcIDQAAAA==.',
Si='Sianien:BAAANQADCgYICwAAAA==.Sickology:BAAANQAECgQIBAAAAA==.Siinatra:BAAANQAECgcIBwAAAA==.Siinatrah:BAAANQAECgUIBwABNQAECgcIBwABAAAAAA==.Silverstarr:BAAANQADCgIIAgAAAA==.Siohban:BAAANQADCgYICwAAAA==.Siphirahah:BAAANQADCgYICwAAAA==.',
Sk='Skürge:BAAANQAECgEIAQAAAA==.',
Sl='Slapntits:BAAANQABCgIIBgAAAA==.Slimreaper:BAAANQAECgEIAQAAAA==.Slothination:BAAANQADCgYIDAABNQAECgcIDAABAAAAAA==.Slurrydots:BAAANQAECgQIBgAAAA==.',
Sn='Snaglvr:BAAANQADCgIIAgAAAA==.Snowtownz:BAAANQAECgYICAAAAA==.Snörichäun:BAAANQADCgcICAAAAA==.',
So='Sokraxx:BAAANQAECgYICAAAAA==.Sonozap:BAAANQAECgQIBAAAAA==.Sonyc:BAAANQADCgQIBAAAAA==.Soothlocked:BAAANQADCgYICQAAAA==.Soraflash:BAAANQADCggICAAAAA==.Soulreaperau:BAAANQAECgEIAQAAAA==.',
Sp='Spicedgoat:BAAANQADCgYICgAAAA==.Spinandwin:BAAANQADCggIDgAAAA==.Springroll:BAAANQAECgMIBAAAAA==.',
Sq='Squishyman:BAAANQAECgMIAwAAAA==.',
Sr='Sram:BAAANQAECgYIBgAAAA==.Srbenda:BAAANQADCgMIAwAAAA==.',
Ss='Sstormmy:BAAANQAECgMIAwAAAA==.',
St='Stabit:BAAANQADCgYICgAAAA==.Starless:BAAANQAECgEIAQAAAA==.Starmyst:BAAANQADCgYIBgAAAA==.Steelbull:BAAANQADCggIDwABNQADCggIGAABAAAAAA==.Steelmyth:BAAANQADCggIDgAAAA==.Strîder:BAAANQADCgYIEAAAAA==.',
Su='Summerskye:BAAANQADCggIDgAAAA==.',
Sy='Sy:BAAANQADCgcIDgABNQAECgUIBQABAAAAAA==.Sydor:BAAANQADCgYIDgAAAA==.Sylennia:BAAANQADCgcICAAAAA==.Sylvatrix:BAAANQADCggIDQAAAA==.Symbiont:BAAANQADCgQIBgAAAA==.',
Sz='Szarni:BAAANQADCgcICAAAAA==.',
Ta='Tabitrisao:BAAANQAECgEIAQAAAA==.Tamarin:BAAANQABCgIIAgAAAA==.Taucetid:BAAANQADCgYIDAAAAA==.Tazington:BAAANQADCggIDwAAAA==.Tazuki:BAAANQABCgIIAgAAAA==.',
Te='Tehsharp:BAAANQAECgMIAwAAAA==.Tehwarrior:BAAANQABCgIIAgAAAA==.Telraena:BAAANQADCgcIDQAAAA==.Terokkar:BAAANQADCgcICAAAAA==.Teul:BAAANQADCgcIDAABNQAECgQIBQABAAAAAA==.',
Th='Thalorian:BAAANQADCgUIBwAAAA==.Thananerion:BAAANQADCgMIAwAAAA==.Thealiaa:BAAANQADCgEIAQAAAA==.Thiea:BAAANQAECgEIAQAAAA==.Thorel:BAAANQADCgQIBAABNQADCgQIBQABAAAAAA==.Thorsake:BAAANQAECgQIBAAAAA==.Thromgorr:BAAANQAECgMIAwAAAA==.Thunderpog:BAAANQAECggIDgAAAA==.',
Ti='Tillicity:BAAANQAECgQIBQAAAA==.Tilzabeth:BAAANQADCgQICgABNQAECgQIBQABAAAAAA==.Tinhu:BAAANQADCgUIBQAAAA==.Tinypi:BAAANQADCggIDQAAAA==.',
To='Tomahawk:BAAANQADCgEIAQAAAA==.Toosuss:BAAANQADCgQIBAAAAA==.Topshot:BAAANQAECgEIAQAAAA==.Torags:BAAANQADCgQIBAAAAA==.',
Tr='Trazendeath:BAAANQADCgMIAwAAAA==.Treesome:BAAANQAECgEIAQAAAA==.Treesource:BAAANQADCgEIAQAAAA==.Trigaa:BAAANQADCgYICgAAAA==.',
Ts='Tsaiko:BAAANQADCgYICgAAAA==.',
Tw='Twirls:BAAANQADCggIDwAAAA==.',
Ty='Tynzel:BAAANQADCgMIBQAAAA==.Tyvaria:BAAANQADCgIIAgAAAA==.',
['Tà']='Tàkhisis:BAAANQADCgYICQAAAA==.',
Un='Underwhelmed:BAAANQADCgUICAAAAA==.Unitofglory:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Unitoflife:BAAANQAECgMIAwAAAA==.Unitofshapes:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.',
Va='Valanar:BAAANQADCgMIAwAAAA==.Valdormu:BAAANQAECgEIAQAAAA==.Vanador:BAAANQADCgUICQAAAA==.Vanarel:BAAANQADCgYICQAAAA==.Vannbeef:BAAANQADCgcIDQAAAA==.Varthlight:BAAANQADCgYICwAAAA==.',
Ve='Veinytotem:BAAANQADCgUIBQAAAA==.Veloran:BAAANQAECgYIDwAAAA==.Venomsspawn:BAAANQAECgEIAQAAAA==.Veyrathor:BAAANQADCgIIAgAAAA==.',
Vi='Vio:BAAANQAFFAEIAQAAAA==.Virtues:BAAANQADCgMIAwAAAA==.Viserys:BAAANQADCgYIDAAAAA==.',
Vy='Vypërz:BAAANQAECgQIBAAAAA==.Vyral:BAAANQAECgMIAwAAAA==.',
Wa='Wabssevo:BAAANQAECgQIBAABNQAECgYIDAABAAAAAA==.Wabssjnr:BAAANQAECgYIDAAAAA==.Warizard:BAAANQADCggIDwAAAA==.Wattanuhbii:BAAANQADCgQIBAAAAA==.Wayzpala:BAAANQADCgQIBAAAAA==.',
We='Weyoun:BAAANQADCgcIBwAAAA==.',
Wh='Wheetie:BAAANQADCggIDgAAAA==.',
Wi='Williwaw:BAAANQADCgQIBwAAAA==.Winterstormm:BAAANQADCgcIDAAAAA==.',
Wn='Wno:BAAANQADCgcIBwAAAA==.',
Wo='Wobbuffet:BAAANQAECgUICAAAAA==.',
Wy='Wyrnn:BAAANQAECgIIAgAAAA==.',
Xa='Xaniran:BAAANQADCgYICAAAAA==.',
Xe='Xelbino:BAAANQADCgEIAQAAAA==.',
Xi='Xiaobi:BAAANQAECgYIBgAAAA==.Xintar:BAAANQADCggIEAAAAA==.Xiomana:BAAANQADCgYICwAAAA==.Xion:BAAANQAECgMIAwAAAA==.',
Ye='Yebanned:BAAANQADCggICAAAAA==.Yellowajah:BAAANQADCgUIBwABNQAECgYICgABAAAAAA==.',
Yi='Yify:BAAANQABCgMIBAABNQADCgUIDQABAAAAAA==.',
Yn='Yneva:BAAANQAECgEIAQAAAA==.',
Yw='Ywrensire:BAAANQADCgQIBAAAAA==.',
Za='Zaabra:BAAANQADCgYICAAAAA==.Zaion:BAAANQADCgYIDwAAAA==.',
Ze='Zealis:BAAANQAECgEIAQAAAA==.Zedar:BAAANQADCgMIAwABNQAECgIIBgABAAAAAA==.',
Zh='Zhi:BAAANQADCgYICwAAAA==.',
Zi='Zilin:BAAANQADCgcIDAAAAA==.',
Zo='Zolce:BAAANQAECgIIAgAAAA==.',
Zu='Zuularok:BAAANQADCgUIBQAAAA==.',
Zy='Zybaxos:BAAANQAECgQIBAAAAA==.',
Zz='Zzro:BAAANQADCgQIBgAAAA==.',
['Ãr']='Ãrçâñîst:BAAANQADCgUIBQAAAA==.',
['År']='Årchon:BAAANQAECgEIAQAAAA==.Årtix:BAAANQADCgYIBgABNQADCgYIBwABAAAAAA==.',
['Îs']='Îssy:BAAANQADCgIIAgAAAA==.',
['Ôr']='Ôrkásh:BAAANQADCgcIDAAAAA==.',
['Öm']='Ömegoss:BAAANQADCgcIEwAAAA==.',
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
