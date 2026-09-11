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

local lookup = {'Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Rogue-Assassination','Warrior-Arms','DemonHunter-Havoc','DemonHunter-Devourer','Mage-Arcane','DeathKnight-Unholy','Paladin-Holy','DeathKnight-Blood','Priest-Shadow','Priest-Holy','Priest-Discipline','Hunter-Marksmanship','Hunter-Survival','Shaman-Restoration','Hunter-BeastMastery',}
local provider = {region='US',realm="Dath'Remar",name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aaronius:BAAANQADCgYIBwAAAA==.',
Ab='Abduhl:BAAANQABCgEIAQAAAA==.',
Ad='Ade:BAAANQAECgEIAQAAAA==.Adezardre:BAAANQADCggIEQAAAA==.Admetriell:BAAANQAECgIIAgABNQAECgYICQABAAAAAA==.Advosary:BAAANQADCgcIDwAAAA==.',
Ai='Aigmokthar:BAAANQAECgQICQAAAA==.',
Ak='Akiriah:BAAANQADCggICAAAAA==.Akirial:BAAANQABCgIIAgAAAA==.Aklo:BAAANQADCgcIEwAAAA==.',
Al='Alamysia:BAAANQADCgYICwAAAA==.Albertfist:BAAANQADCgMIAwAAAA==.Aletech:BAAANQAECgMIAwAAAA==.Ali:BAAANQAECgEIAQAAAA==.Aliesá:BAAANQADCgcIDwAAAA==.Alilea:BAAANQADCgQIBAAAAA==.Alimagus:BAAANQADCggIDwABNQAECgcIEwABAAAAAA==.Alisandrah:BAABNQAECoEXAAMCAAkJAR5hBgBzAgACAAcJwR5hBgBzAgADAAcJNhuGFQBUAgAAAA==.Alison:BAAANQADCgYIDAAAAA==.Allakeer:BAABNQAECoESAAIEAAgJLyAvAwAOAwAEAAgJLyAvAwAOAwAAAA==.Altarios:BAAANQADCggIFAAAAA==.Alyyix:BAAANQADCgUIDwAAAA==.',
Am='Amber:BAAANQADCggIFQAAAA==.Ambertastic:BAAANQADCgcIEQABNQADCggIFQABAAAAAA==.Amilandris:BAAANQAECgUIEAAAAA==.',
An='Analalea:BAAANQADCgUICQAAAA==.Analdrainal:BAAANQAECgQIBgAAAA==.Annaris:BAAANQADCgYICAAAAA==.',
Ap='Apophani:BAAANQADCgcIDwAAAA==.Appolo:BAAANQAECgIIBAAAAA==.',
Ar='Arcanegasm:BAAANQAECgYICwAAAA==.Archii:BAAANQADCgcIBwABNQAECgQIBwABAAAAAA==.Archslayer:BAAANQAECgEIAQAAAA==.Aresdeekx:BAAANQADCggICAAAAA==.Arneus:BAAANQADCgcIDAAAAA==.Arnir:BAAANQAECgEIAQAAAA==.Arriving:BAAANQAECgQIBgAAAA==.Artaq:BAAANQADCgcIDgAAAA==.Artoriöus:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Arvanon:BAAANQAECgIIBAAAAA==.',
As='Ashanar:BAAANQADCggIHQAAAA==.Asharla:BAAANQADCgYIEQAAAA==.Ashbringa:BAAANQAECgEIAQAAAA==.Ashhman:BAAANQADCgYIBgAAAA==.Ashhunt:BAAANQAECgYICwAAAA==.Ashmend:BAAANQADCgcIEAAAAA==.Asorrow:BAAANQAECgQICAABNQAECggICgABAAAAAA==.Assatur:BAAANQADCgYIBgAAAA==.Astarna:BAAANQAECgEIAQAAAA==.Asteríx:BAAANQADCgQICAAAAA==.',
At='Atiatal:BAAANQABCgIIAgAAAA==.Atlasursidae:BAAANQAECgMIBgAAAA==.Atoniah:BAAANQADCggIDgAAAA==.',
Au='Auraz:BAAANQAECgYIBwAAAA==.',
Av='Avelinna:BAAANQAECgEIAQAAAA==.',
Aw='Awan:BAAANQADCgYIBgAAAA==.',
Az='Aztrayel:BAAANQADCgcIEgAAAA==.',
Ba='Baalial:BAAANQADCgcIFAAAAA==.Baboya:BAAANQAECggIAQAAAA==.Baelgrim:BAAANQADCgcIEQAAAA==.Baly:BAAANQADCgYIDAABNQAECgYICwABAAAAAA==.Bangbangbro:BAAANQAECgEIAQAAAA==.Barium:BAAANQADCgEIAQAAAA==.',
Be='Belfrostbolt:BAAANQADCgcIEAAAAA==.Bentt:BAAANQABCgQIBAAAAA==.Bettÿ:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Bi='Bigjawden:BAAANQADCgcIDwAAAA==.Billbee:BAAANQADCgcIDAAAAA==.Bimbohaggins:BAAANQAECgMIAwABNQAECgQIBwABAAAAAA==.Bimbò:BAAANQAECgEIAQAAAA==.Binchicken:BAAANQAECgMIAwAAAA==.Bingler:BAAANQABCgMIAwAAAA==.',
Bj='Bjornhammerz:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Bjornshockz:BAAANQAECgQIBAAAAA==.',
Bl='Blaz:BAAANQAECgQICgAAAA==.Blockz:BAAANQADCggIDwAAAA==.Bloodboi:BAAANQADCgcIDgAAAA==.Bloodyeddy:BAAANQAECgEIAQAAAA==.Bluecups:BAAANQADCggIEwAAAA==.Bluey:BAAANQADCgYICwAAAA==.',
Bo='Bobbyboom:BAAANQAECgMIAwAAAA==.Bonedecays:BAAANQADCgMIBAAAAA==.Bontoad:BAAANQADCggIFwAAAA==.',
Br='Brewaresx:BAAANQAECgYIBgAAAA==.Broxaschor:BAAANQABCgMIAQAAAA==.Brutus:BAAANQAECgUIBgAAAA==.',
Bu='Bubbleduck:BAAANQADCgIIAgAAAA==.Buggzz:BAAANQAECgYIDAAAAA==.',
Bz='Bzlthazyr:BAAANQAECgcIDAAAAA==.',
Ca='Cahtbl:BAAANQADCgcICgAAAA==.Callin:BAAANQADCgcIEAAAAA==.Calyx:BAAANQADCgYICQAAAA==.Casay:BAAANQAECgEIAQAAAA==.Casbot:BAAANQAECgYICQAAAA==.Cashmere:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Castalight:BAAANQADCgYICwAAAA==.Castlebravo:BAAANQADCgYIBgAAAA==.',
Ch='Charlee:BAAANQADCgUICwAAAA==.Chirran:BAAANQAECgQIDAAAAA==.Chxdzilla:BAABNQAECoEXAAIFAAkJsg9EKABQAgAFAAkJsg9EKABQAgAAAA==.',
Ci='Cinnamõn:BAAANQABCgQIBQAAAA==.',
Co='Corldrin:BAAANQAECgEIAQAAAA==.Coronis:BAAANQAECgEIAQAAAA==.Corriana:BAAANQADCgcIEQABNQAECgEIAQABAAAAAA==.Corwin:BAAANQADCgUIDwAAAA==.',
Cr='Crazee:BAAANQAECgcIEQAAAA==.Cruz:BAAANQAECgQICgAAAA==.Crystalflame:BAAANQAECgMIAwAAAA==.Crìsp:BAAANQADCgYICwABNQADCggICwABAAAAAA==.',
Ct='Ctshammy:BAAANQAECgMIBAAAAA==.',
Cu='Cultistt:BAAANQAECgYICgAAAA==.Cursedyou:BAAANQADCggIEwAAAA==.Curserot:BAAANQAECgEIAQAAAA==.Cuteselenes:BAAANQADCgIIAgAAAA==.',
Cy='Cynal:BAAANQAECgUIBwAAAA==.',
Da='Daddyy:BAAANQADCggICAABNQAECgcIEQABAAAAAA==.Dammo:BAAANQADCgcIDwAAAA==.Dantallion:BAAANQADCgUICAABNQADCgcIBwABAAAAAA==.Darkholme:BAAANQAECgEIAQAAAA==.Darkk:BAAANQADCgEIAQAAAA==.Darthdraik:BAAANQADCggIDgAAAA==.',
Dc='Dcver:BAAANQAECgUIEAAAAA==.',
Dd='Ddraigfach:BAAANQABCgMIAwAAAA==.',
De='Deademeat:BAAANQADCgMIAwAAAA==.Deadlynewbz:BAAANQAECgcIDwAAAA==.Deathboom:BAAANQADCgUIBQABNQAECgcIDQABAAAAAA==.Deathbyshoe:BAAANQADCggIGwAAAA==.Deathivy:BAAANQADCgcIDgAAAA==.Deathjam:BAAANQAECgEIAQAAAA==.Deathmore:BAAANQAECgEIAQAAAA==.Deathshrine:BAAANQADCggIDQAAAA==.Decypha:BAAANQAECgUIBgAAAA==.Deidius:BAAANQADCgUIBQAAAA==.Deiwos:BAAANQAECgIIAgAAAA==.Delichtable:BAAANQADCgcIEQABNQADCggIFQABAAAAAA==.Deltora:BAAANQAECgEIAQAAAA==.Demodog:BAAANQAECgQIBwAAAA==.Demonicnight:BAAANQAECgQIBQAAAA==.Derryth:BAAANQAECgIIAgAAAA==.Devpro:BAAANQAECgMIBAAAAA==.Dexillo:BAABNQAECoEYAAMGAAkJ0hPfDAA/AgAGAAkJhhPfDAA/AgAHAAgJ8A4CFwAEAgAAAA==.',
Dh='Dhaveira:BAAANQAECgQIBwAAAA==.',
Di='Divinegirly:BAAANQAECgEIAQAAAA==.',
Do='Dodgeanaxe:BAABNQAECoEgAAIFAAgJ5BDANAAHAgAFAAgJ5BDANAAHAgAAAA==.Dojoe:BAAANQAECgIIBgABNQAECgUICgABAAAAAA==.Dorá:BAAANQADCgUIBQAAAA==.',
Dr='Dracnock:BAAANQAECgQIBgAAAA==.Drinian:BAAANQADCggICgAAAA==.',
Du='Ducker:BAAANQAECggIEwAAAA==.Dustangel:BAAANQADCggICAAAAA==.',
Dy='Dylexd:BAAANQAECgEIAQAAAA==.',
Ea='Eatmybolts:BAAANQAECgYIBgAAAA==.',
Ec='Eccentricity:BAAANQAECgEIAQAAAA==.',
El='Eldarion:BAAANQADCgQIBAAAAA==.Electricmon:BAAANQAECgUICgABNQAECggIIAAFAOQQAA==.Elementi:BAAANQADCgIIAgAAAA==.Eliasidris:BAAANQAECgEIAQAAAA==.Elmaco:BAAANQAECgMIAwAAAA==.Elphkilla:BAAANQADCggICAAAAA==.Elroth:BAAANQADCgYICgAAAA==.Elseapi:BAAANQADCggIHQAAAA==.Elyssae:BAAANQAECgUIBwAAAA==.',
En='Endarios:BAAANQADCgYIBwAAAA==.Endsplit:BAAANQAECgEIAQAAAA==.',
Er='Erzalockhart:BAAANQADCgYIBgAAAA==.',
Es='Esmaralda:BAAANQADCgUIBwAAAA==.',
Ev='Everleaf:BAAANQADCgQIBgAAAA==.Eviion:BAAANQAECgQIBAAAAA==.',
Ez='Ezoth:BAAANQADCgIIAgAAAA==.',
Fa='Fallendivine:BAAANQAECgUIBwAAAA==.',
Fe='Feetenjoyer:BAAANQADCgMIAwAAAA==.Feipo:BAABNQAECoERAAIIAAgJDBZPOwBMAgAIAAgJDBZPOwBMAgAAAA==.Fensmage:BAAANQADCggIDwAAAA==.Feralbuffkty:BAABNQAECoEXAAIJAAkJYR0KCAAkAwAJAAkJYR0KCAAkAwAAAA==.Fere:BAAANQAECgUICAAAAA==.Feurekt:BAAANQAECgUIDQAAAA==.',
Fi='Finitaur:BAAANQADCgQIBwAAAA==.',
Fl='Flashinlight:BAAANQAECgEIAQAAAA==.Flashstép:BAAANQAECgMIAwAAAA==.Flipside:BAAANQAECgEIAgAAAA==.',
Fo='Fomor:BAAANQAECgIIAgAAAA==.Forbs:BAAANQADCgMIAwAAAA==.Foreignerr:BAAANQAECgcIEwAAAA==.',
Fr='Franziscka:BAAANQADCgYICwAAAA==.',
Fu='Furbold:BAAANQAECgYIBwAAAA==.',
['Fí']='Fíredup:BAAANQADCggIFAABNQAECgQIBAABAAAAAA==.',
Ga='Galeira:BAAANQAECgIIAgAAAA==.Gallene:BAABNQAECoEsAAIFAAgJsyQYCABrAwAFAAgJsyQYCABrAwAAAA==.Gandallf:BAAANQADCgQIBQABNQAECgEIAQABAAAAAA==.Garakarak:BAAANQADCggICAAAAA==.Garthinian:BAAANQADCgYICQAAAA==.Garthpally:BAAANQADCgUIBQAAAA==.',
Ge='Genimaculata:BAAANQAECgUIBgAAAA==.Gerothos:BAAANQADCgQIBAAAAA==.',
Gh='Ghislaine:BAAANQADCgQIBQAAAA==.Ghöst:BAAANQADCgYIBgAAAA==.',
Gl='Gladios:BAAANQADCgEIAQAAAA==.Glarry:BAAANQADCggICAABNQAECgkJGgAKAC8eAA==.Glidelicator:BAAANQAECgUIBwAAAA==.',
Go='Goodasnew:BAAANQADCggIFAAAAA==.Gortopia:BAAANQADCgYICwAAAA==.Gosublood:BAAANQAECgQIBgAAAA==.Gosupriest:BAAANQAECgIIAgABNQAECgQIBgABAAAAAA==.',
Gr='Graggy:BAABNQAECoEaAAIKAAkJLx50BABPAwAKAAkJLx50BABPAwAAAA==.Grapejelly:BAAANQAECgQICAAAAA==.Grashk:BAAANQAECgEIAQAAAA==.Grimbel:BAAANQAECgEIAQAAAA==.',
['Gø']='Gødspeed:BAAANQABCgQIBwAAAA==.',
Ha='Hadeshunt:BAAANQAECgEIAQAAAA==.Hadessham:BAAANQADCgYIBgAAAA==.Halzarius:BAAANQAECgEIAQAAAA==.Handyshammy:BAAANQAECgEIAQABNQAECgUIDQABAAAAAA==.Handywar:BAAANQAECgUIDQAAAA==.Hans:BAAANQADCggIGwAAAA==.Harleybear:BAAANQADCgUIDQAAAA==.',
Ho='Holyknox:BAAANQADCggIDwABNQAECgYIBwABAAAAAA==.Holymender:BAAANQADCggICQAAAA==.',
Hu='Hulkamania:BAAANQADCgMIAwAAAA==.Humble:BAAANQAECgQIBAAAAA==.',
Hy='Hydromender:BAAANQAECgQIBQAAAA==.Hyperactiv:BAAANQADCgYIBgABNQADCgcIDgABAAAAAA==.',
['Hø']='Høpeless:BAAANQAECgQIBgAAAA==.',
Ic='Icycookiex:BAAANQADCggIDgABNQAECgMIBAABAAAAAA==.Icymilkyx:BAAANQAECgMIBAAAAA==.',
Ig='Igneel:BAAANQADCgYIDAAAAA==.',
Il='Illigniteyou:BAAANQAECgQIDAAAAA==.',
In='Inosolan:BAAANQAECgEIAQAAAA==.Inurfacevegi:BAAANQADCgYICAABNQAECgEIAQABAAAAAA==.',
Io='Iozt:BAAANQAFFAEIAQAAAA==.',
Ir='Irritable:BAAANQAECgEIAQAAAA==.Irvina:BAAANQAECgUICwAAAA==.Irvinebrown:BAAANQADCgIIBAABNQAECgUICwABAAAAAA==.Irvinia:BAAANQADCggIHAABNQAECgUICwABAAAAAA==.',
Is='Iskarius:BAAANQAECgIIAgAAAA==.Istenn:BAAANQAECgEIAQAAAA==.',
It='Ithyl:BAAANQADCgcIEgAAAA==.Itzshammy:BAAANQAECgUIBwAAAA==.',
Iv='Ivanoviaa:BAAANQADCgMIAwAAAA==.',
Ja='Jackdaw:BAAANQABCgIIAgAAAA==.Janinda:BAAANQAECgYIDQAAAA==.Jastina:BAAANQAECgEIAQAAAA==.Jaszz:BAAANQAECgQIBgAAAA==.',
Jb='Jb:BAAANQADCggICwAAAA==.',
Je='Jelly:BAAANQADCgcIDAAAAA==.Jengil:BAAANQAECgQIBAAAAA==.Jengol:BAAANQABCgIIAgAAAA==.Jesto:BAAANQAECgUIEAAAAA==.',
Jh='Jhonn:BAAANQADCggIFAAAAA==.',
Jo='Jodiefroster:BAAANQAECgEIAQAAAA==.Joeseppe:BAAANQAECgUICgAAAA==.Joshst:BAAANQADCgYIDwAAAA==.Josta:BAAANQADCgQIBAABNQAECgUIEAABAAAAAA==.Josto:BAAANQADCgcIEQABNQAECgUIEAABAAAAAA==.Jovyll:BAAANQAECgEIAQAAAA==.Joyboyluffy:BAAANQADCgUIBQAAAA==.',
Ju='Jurodice:BAAANQAECgYICQAAAA==.',
['Jå']='Jårko:BAAANQADCgYICQAAAA==.',
Ka='Kaelinth:BAAANQADCgYIBgAAAA==.Kaelyth:BAAANQADCggIHQAAAA==.Kamakazie:BAAANQADCgYIBgAAAA==.Karmerre:BAAANQADCgcICQAAAA==.Karramerre:BAAANQADCgUIBQABNQADCgcICQABAAAAAA==.Kaydeebug:BAAANQAECgQIBwAAAA==.Kayna:BAAANQAECgUICgAAAA==.',
Ke='Kellanis:BAAANQAECgMIBAAAAA==.Kelugar:BAAANQADCgIIAgAAAA==.Kerenarye:BAAANQAECgcIDQAAAA==.',
Kh='Khaladore:BAAANQAECgMIAwAAAA==.Kharazhan:BAAANQAECgEIAQAAAA==.',
Ki='Kiilbill:BAAANQADCgcICwABNQAECgQIBAABAAAAAA==.Killshotbob:BAAANQADCgcICwAAAA==.Kinkyheaven:BAAANQAECgQIBAAAAA==.Kinnigit:BAAANQAECgYICQAAAA==.Kinstalz:BAAANQAECgIIAgAAAA==.Kiotia:BAAANQADCgYICAAAAA==.Kipp:BAAANQAECgEIAQAAAA==.Kiril:BAAANQADCgUIBQAAAA==.Kirky:BAAANQADCgQIBQAAAA==.Kithraah:BAAANQAECgcIEQAAAA==.Kithrah:BAAANQADCggIDAABNQAECgcIEQABAAAAAA==.',
Kn='Knifeparty:BAAANQADCgcIDQAAAA==.',
Ko='Kolugar:BAAANQAECgcIDQAAAA==.Konkar:BAAANQAECgQICAAAAA==.',
Kr='Kradon:BAAANQAECgEIAQAAAA==.Kruphix:BAAANQAECgIIAgAAAA==.Krysania:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.',
Ku='Kudreanne:BAAANQADCgUIDwAAAA==.Kuri:BAAANQADCggICAAAAA==.',
La='Laiceeshay:BAAANQAECgQIBAAAAA==.Lars:BAAANQAECgQIBgAAAA==.Larxe:BAAANQADCggIEAAAAA==.',
Le='Legendaïry:BAAANQADCgQIBQAAAA==.Letmedie:BAAANQAECgEIAQAAAA==.Lexillo:BAAANQAECgQIBQAAAA==.',
Li='Liaravara:BAAANQAECgEIAQAAAA==.Lightmender:BAAANQADCgQIBAAAAA==.Lilldemon:BAAANQADCgcIDgAAAA==.Lizzo:BAAANQAECgIIAgAAAA==.',
Lo='Lorieyxo:BAAANQADCgcIEgAAAA==.Lorrim:BAAANQADCgcIFQAAAA==.Louron:BAAANQABCgEIAQAAAA==.',
Lu='Luena:BAAANQADCgMIAwAAAA==.Lunabi:BAAANQAECgEIAQABNQAECgcIBwABAAAAAA==.Luxdae:BAAANQADCgEIAQAAAA==.',
Ly='Lyrannia:BAAANQAECgMIBQAAAA==.Lyth:BAAANQAECgQIBgAAAA==.',
['Lá']='Láiken:BAAANQADCgYIEQAAAA==.',
Ma='Madmoxxie:BAAANQADCgUIBQAAAA==.Mageapayne:BAAANQADCgYIBgAAAA==.Magetom:BAAANQAECgEIAQAAAA==.Maghan:BAAANQADCgQICAAAAA==.Magicus:BAAANQADCgcIBwAAAA==.Magikaze:BAAANQAECgEIAQAAAA==.Mahgo:BAAANQAECgQIBAAAAA==.Maikara:BAAANQADCgcIBwAAAA==.Malfalcator:BAAANQADCgMIAwAAAA==.Marieh:BAAANQADCgYIBgAAAA==.Martha:BAAANQABCgYIBwAAAA==.Masscarnage:BAAANQAECgMICAAAAA==.Maywina:BAAANQAECgIIBAABNQAECgUIEAABAAAAAA==.Mazhun:BAAANQAECgEIAQAAAA==.',
Me='Meaculpa:BAAANQAECgIIBAAAAA==.Mediqua:BAAANQADCgQIAQAAAA==.Megaflame:BAAANQADCgUIDAAAAA==.Mekkii:BAAANQADCgIIAgABNQAECgcIDQABAAAAAA==.Mekky:BAAANQAECgcIDQAAAA==.Melonheadx:BAAANQADCgIIAgAAAA==.Meltharion:BAAANQADCgcIDgAAAA==.Mercerful:BAAANQADCgMIAwAAAA==.Methex:BAAANQAECgUIBgAAAA==.Metzger:BAAANQADCgQIBwAAAA==.',
Mi='Mingi:BAAANQADCgEIAQABNQAECgYICQABAAAAAA==.Minigore:BAAANQAECgQIBgAAAA==.Mirya:BAAANQADCgcIEgAAAA==.Mishamigo:BAAANQAECgEIAQAAAA==.Missharmony:BAAANQAECgEIAQAAAA==.Misstickles:BAAANQAECgEIAQAAAA==.',
Mo='Moistpawjob:BAAANQAECggIEgAAAA==.Moistpole:BAAANQADCgYIBwAAAA==.Mojostormale:BAAANQADCgEIAQAAAA==.Monanarr:BAAANQADCgEIAgABNQADCgcIFQABAAAAAA==.Monmonk:BAAANQADCgcIFQAAAA==.Moograin:BAAANQABCgQIBAAAAA==.Moonalisa:BAAANQADCgYIDgAAAA==.Moondropz:BAAANQADCgYIBgAAAA==.Moonsblood:BAAANQAECgEIAQAAAA==.Moontara:BAAANQAECgMICAAAAA==.Moopsy:BAAANQADCgcIGwAAAA==.Mops:BAAANQADCggIHwAAAA==.',
Mu='Muldoom:BAAANQABCgQIAgAAAA==.Mur:BAAANQAECgEIAQAAAA==.',
My='Mycotoxin:BAAANQADCggIFAAAAA==.Myrrdan:BAAANQAECgEIAQAAAA==.Mysst:BAAANQADCggIHQAAAA==.Mysteerie:BAAANQAECgEIAQAAAA==.Mythlogic:BAAANQAECgEIAQAAAA==.Mythsham:BAAANQADCgUIDQAAAA==.',
['Má']='Mángo:BAAANQAECgYICgAAAA==.',
['Mù']='Mùshu:BAAANQADCgQIBAAAAA==.',
Na='Nardaran:BAAANQAECgQIBAAAAA==.Natsumi:BAAANQADCgQIBAABNQAECgcIDAABAAAAAA==.',
Ne='Needcoffee:BAAANQADCgYIDQAAAA==.Neemixa:BAAANQADCgYIDwAAAA==.Neonh:BAAANQADCgcIDwAAAA==.',
Ni='Nightwissh:BAAANQADCggIHQAAAA==.Nitestar:BAAANQADCgUICwAAAA==.Nitevoker:BAAANQAECgMIBAAAAA==.',
No='Nordvoker:BAAANQAECgQIBgAAAA==.Nospheratu:BAABNQAECoEcAAIIAAUJNxxxcwCGAQAIAAUJNxxxcwCGAQABNQADCgYIBgABAAAAAA==.',
Nu='Nubu:BAAANQADCgUIBwAAAA==.',
Ny='Nycepala:BAAANQADCgcIDwAAAA==.Nylaith:BAAANQADCgUIBQAAAA==.Nyni:BAABNQAECoEXAAILAAkJRROwEgBUAgALAAkJRROwEgBUAgAAAA==.Nythshade:BAAANQADCgYIBgAAAA==.',
['Nü']='Nümnüts:BAAANQAECgEIAQAAAA==.',
Of='Offworlder:BAAANQADCgcIDAAAAA==.',
On='Onlyhoofs:BAEANQAECgYIDAAAAA==.',
Oo='Oofm:BAAANQAECgQIDAAAAA==.Oospider:BAAANQADCgQIEAAAAA==.',
Op='Ophearia:BAAANQADCgYIDQAAAA==.Optimiss:BAAANQADCgYIDQAAAA==.',
Or='Orcboy:BAAANQAECgUIBQAAAA==.Orken:BAAANQADCgEIAQAAAA==.Orthanu:BAAANQADCgUIBQAAAA==.',
Pa='Paieth:BAAANQAECgMIBAAAAA==.Paladerp:BAAANQAECgQIBwAAAA==.Palaresx:BAAANQAECgIIAgAAAA==.Pallyshunter:BAAANQAECgMIBQAAAA==.Panchamp:BAAANQADCgcIDgAAAA==.Pandamourne:BAAANQADCgcICQAAAA==.Pandori:BAAANQAECgUIBgAAAA==.Parchmentham:BAAANQAECgcICgAAAA==.Paryniux:BAAANQAECgEIAQAAAA==.Patience:BAAANQADCgMIAwAAAA==.',
Pi='Pinchiy:BAAANQADCgQIBAAAAA==.Pinkpanthir:BAAANQAECgMIBAAAAA==.',
Pj='Pjay:BAAANQADCgcIBwAAAA==.',
Pl='Plisky:BAAANQADCgcICQAAAA==.',
Po='Pollywaffle:BAAANQADCgQIBAAAAA==.Portals:BAAANQADCggICAAAAA==.Poùnd:BAAANQADCgYIDAABNQAECgQIBAABAAAAAA==.',
Pr='Praiseme:BAAANQADCgYIDgAAAA==.Predz:BAAANQAECgEIAQAAAA==.Prepaired:BAAANQADCggICAABNQAECgkJJwACAOweAA==.',
Ps='Psyreq:BAAANQAECgQIBAAAAA==.',
Pu='Punkey:BAAANQAECgMIAwAAAA==.',
Qu='Quartquartma:BAAANQAECgEIAQAAAA==.',
Ra='Raedia:BAAANQADCgMIAwAAAA==.Rahll:BAAANQABCgQICAAAAA==.Ravachiar:BAAANQAECgIIAwABNQAECgQIBAABAAAAAA==.Ravenathas:BAAANQADCgUIEgABNQADCgcICwABAAAAAA==.Ravenimus:BAAANQADCgcICwAAAA==.Ravic:BAAANQADCgYIBgAAAA==.Razeld:BAAANQADCgcIDwAAAA==.Razhun:BAAANQADCggIHQAAAA==.Razia:BAAANQAECgEIAQAAAA==.Razzax:BAAANQADCgUIBQAAAA==.Razzmata:BAAANQAECgMIAwAAAA==.',
Re='Reckendorf:BAAANQAECgEIAgAAAA==.Redefine:BAAANQADCgQIBAAAAA==.Reflet:BAAANQADCggIFgAAAA==.Rell:BAAANQAECgYIBwAAAA==.Rentress:BAAANQADCgUIDwAAAA==.Restik:BAAANQADCggIEwAAAA==.Revyre:BAAANQADCgIIAgAAAA==.Rexxnaar:BAAANQADCgMIBAAAAA==.Rexy:BAAANQAECgQIBAAAAA==.',
Rh='Rhiotannis:BAAANQAECgQIBAAAAA==.Rhombus:BAAANQADCgYIBgAAAA==.Rhots:BAAANQAECgUIBQAAAA==.',
Ri='Ricketyrekt:BAAANQADCgcIBwAAAA==.Rimara:BAAANQAECgEIAQAAAA==.Rishari:BAAANQADCgcICQAAAA==.',
Ro='Rocadin:BAAANQADCggIDwAAAA==.Rocmon:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.Rorisala:BAAANQADCgYICwAAAA==.Rottlee:BAAANQADCgcICAAAAA==.Rowshamboe:BAAANQADCgUIDwAAAA==.Rozabella:BAAANQAECgUIBgAAAA==.',
Ru='Rune:BAAANQAECgIIAgABNQAECgYIDgABAAAAAA==.',
['Rê']='Rêdylive:BAAANQADCggIFAAAAA==.',
Sa='Saelska:BAAANQAECgEIAQAAAA==.Sahven:BAAANQADCgYICQAAAA==.Sakuraharu:BAAANQAECgIIAgAAAA==.Sakuraharune:BAAANQADCgYIBQAAAA==.Sakuraharuno:BAAANQAECgUICAAAAA==.Sakuura:BAAANQADCggIAwAAAA==.Sarang:BAAANQAECgQIBgAAAA==.Sassystrasza:BAAANQADCgQIBAAAAA==.Savagepaw:BAAANQAECgYIBgAAAA==.',
Sc='Scarbz:BAAANQAECgEIAQAAAA==.',
Se='Selennys:BAAANQADCgUICAAAAA==.Selest:BAAANQADCgcIBwAAAA==.',
Sh='Shadowkain:BAAANQAECgEIAQAAAA==.Shadøws:BAAANQAECgUIBgAAAA==.Shagz:BAAANQADCgQIDAAAAA==.Shallios:BAAANQADCgYIEAAAAA==.Shamajov:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Shamankiing:BAAANQABCgIIAwAAAA==.Shamannigans:BAAANQADCggICAAAAA==.Shammyhagar:BAAANQADCgcIBwAAAA==.Shamnow:BAAANQADCgEIAQAAAA==.Shaytan:BAAANQADCggIHQAAAA==.Sheogorath:BAAANQAECgYICgAAAA==.Shocksocks:BAAANQAECgEIAQAAAA==.Shoujian:BAAANQADCgcIDQAAAA==.',
Si='Sianien:BAAANQADCgcIEgAAAA==.Sickology:BAAANQAECgYICgAAAA==.Siinatra:BAAANQAECgcIDQAAAA==.Siinatrah:BAAANQAECgcICwABNQAECgcIDQABAAAAAA==.Silverstarr:BAAANQADCgIIAgAAAA==.Siohban:BAAANQAECgEIAQAAAA==.Sionel:BAAANQADCgUIBQAAAA==.Siphirahah:BAAANQAECgEIAQAAAA==.',
Sk='Skürge:BAAANQAECgEIAQAAAA==.',
Sl='Slapntits:BAAANQABCgYIDAAAAA==.Slimreaper:BAAANQAECgEIAQAAAA==.Slothination:BAAANQAECgYIBgABNQAECgkJFwAJAGEdAA==.Slurrydots:BAAANQAECgcIDgAAAA==.',
Sn='Snaglvr:BAAANQADCgIIAgAAAA==.Snowtownz:BAAANQAECgcIDwAAAA==.Snörichäun:BAAANQADCgcIDgAAAA==.',
So='Sokraxx:BAAANQAECgcIDwAAAA==.Sonozap:BAAANQAECgQIBgAAAA==.Sonyc:BAAANQADCgQIBAAAAA==.Soothlocked:BAAANQADCgcICgAAAA==.Soraflash:BAAANQADCggICAAAAA==.Soulreaperau:BAAANQAECgEIAQAAAA==.',
Sp='Spearzy:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Spicedgoat:BAAANQADCgYIEAAAAA==.Spinandwin:BAAANQAECgIIAgAAAA==.Springroll:BAAANQAECgQICAAAAA==.',
Sq='Squishikayla:BAAANQADCgEIAQAAAA==.Squishyman:BAAANQAECgYICQAAAA==.',
Sr='Sram:BAAANQAECgcIDQAAAA==.Srbenda:BAAANQADCgUIBgAAAA==.',
Ss='Sstormmy:BAAANQAECgQIBwAAAA==.',
St='Stabit:BAAANQADCggIDAAAAA==.Starless:BAAANQAECgMIBAAAAA==.Starmyst:BAAANQADCgYIBgAAAA==.Steelbull:BAAANQAECgQIBAAAAA==.Steelmyth:BAAANQAECgQIBAAAAA==.Strìder:BAAANQAECgEIAQAAAA==.Strîder:BAAANQAECgEIAgAAAA==.',
Su='Summerskye:BAAANQAECgQIBAAAAA==.',
Sy='Sy:BAAANQAECgMIBwABNQAECgcIDAABAAAAAA==.Sycamore:BAAANQADCgMIAwAAAA==.Sydor:BAAANQADCggIEgAAAA==.Sylennia:BAAANQADCggIHQAAAA==.Sylvatrix:BAAANQAECgQIBAAAAA==.Symbiont:BAAANQADCgYICwAAAA==.',
Sz='Szarni:BAAANQADCggIGAAAAA==.',
Ta='Tabitrisao:BAAANQAECgEIAQAAAA==.Tamarin:BAAANQABCgIIAgAAAA==.Taridalas:BAAANQADCgYIBgABNQADCgYICwABAAAAAA==.Taucetid:BAAANQADCggIFAAAAA==.Tazington:BAAANQAECgQIBAAAAA==.Tazuki:BAAANQABCgIIAgAAAA==.',
Te='Tehsharp:BAAANQAECgYICQAAAA==.Tehwarrior:BAAANQABCgUIBQAAAA==.Telraena:BAAANQADCggIFQAAAA==.Terokkar:BAAANQADCggIHQAAAA==.Tesalach:BAAANQADCgUIBQAAAA==.Teul:BAAANQAECgUIBQABNQAECgcIDAABAAAAAA==.',
Th='Thalorian:BAAANQADCgUICgAAAA==.Thananerion:BAAANQADCgMIAwAAAA==.Thealiaa:BAAANQADCgIIAgAAAA==.Thiea:BAAANQAECgUIBgAAAA==.Thorel:BAAANQADCgYIBwABNQAECgQIBAABAAAAAA==.Thorsake:BAAANQAECgYICgAAAA==.Thromgorr:BAAANQAECgQIBwAAAA==.Thundercant:BAAANQAECgcIBwABNQAECgkJGQAMAIkcAA==.Thunderpog:BAABNQAECoEZAAQMAAkJiRzKBwDdAgAMAAgJTR3KBwDdAgANAAYJaBfLLgCDAQAOAAQJNhyGBwBDAQAAAA==.',
Ti='Tillicity:BAAANQAECgYICwAAAA==.Tilzabeth:BAAANQADCgQICgABNQAECgYICwABAAAAAA==.Timewarp:BAAANQADCggIBQAAAA==.Tinhu:BAAANQADCgYIBgAAAA==.Tinypi:BAAANQAECgEIAQAAAA==.',
To='Tomahawk:BAAANQADCgEIAQAAAA==.Toosuss:BAAANQADCgYICgAAAA==.Topshot:BAAANQAECgIIAwAAAA==.Torags:BAAANQADCgQIBAAAAA==.',
Tr='Trazendeath:BAAANQADCgMIAwAAAA==.Treesome:BAAANQAECgIIAgAAAA==.Treesource:BAAANQADCgEIAQAAAA==.Trigaa:BAAANQADCggIDAAAAA==.Trojans:BAAANQABCgIIAQAAAA==.',
Ts='Tsaiko:BAAANQADCgcIEQAAAA==.',
Tw='Twirls:BAAANQAECgQIBAAAAA==.Twirlshair:BAAANQADCgUIBQAAAA==.',
Ty='Tynzel:BAAANQADCgcIDAAAAA==.Tyvaria:BAAANQADCgUIBwAAAA==.',
['Tà']='Tàkhisis:BAAANQADCgcICgAAAA==.',
Ul='Ullbenxt:BAAANQAECgIIAgAAAA==.',
Um='Umf:BAAANQADCggICQABNQAECgcICgABAAAAAA==.',
Un='Underwhelmed:BAAANQADCgYICQAAAA==.Unitofglory:BAAANQADCgIIAgABNQAECgQIBwABAAAAAA==.Unitoflife:BAAANQAECgQIBwAAAA==.Unitofshapes:BAAANQAECgMIBAABNQAECgQIBwABAAAAAA==.',
Va='Valanar:BAAANQADCgMIAwAAAA==.Valdormu:BAAANQAECgMIBAAAAA==.Vanador:BAAANQAECgEIAQAAAA==.Vanarel:BAAANQADCgYIDgAAAA==.Vanel:BAAANQADCgYIBgAAAA==.Vannbeef:BAAANQAECgEIAQAAAA==.Varthlight:BAAANQAECgEIAQAAAA==.',
Ve='Veinytotem:BAAANQADCgUIBQAAAA==.Veloran:BAABNQAECoEhAAMPAAgJIg+MFQDmAQAPAAgJIg+MFQDmAQAQAAIJ5AucBwBrAAAAAA==.Venomsspawn:BAAANQAECgMIBAAAAA==.Vexahlia:BAAANQADCgEIAQAAAA==.Veyrathor:BAAANQADCgIIAgAAAA==.',
Vi='Vio:BAACNQAFFIEGAAIRAAUJeBUbAQDGAQARAAUJeBUbAQDGAQA1AAQKgRkAAhEACQmtIioDAGsDABEACQmtIioDAGsDAAAA.Virtues:BAAANQADCgMIAwAAAA==.Virtus:BAAANQADCgYIBwAAAA==.Viserys:BAAANQADCggIFAAAAA==.',
Vu='Vuruul:BAAANQADCgYIBgAAAA==.',
Vy='Vypërz:BAAANQAECgYICgAAAA==.Vyral:BAAANQAECgQIBwAAAA==.',
Wa='Wabssevo:BAAANQAECgQIBAABNQAECgYIDAABAAAAAA==.Wabssjnr:BAAANQAECgYIDAAAAA==.Wararesx:BAAANQADCgUIBwABNQAECgYIBgABAAAAAA==.Warizard:BAAANQAECgQIBAAAAA==.Wattanuhbii:BAAANQADCgQIBAAAAA==.Wayzpala:BAAANQADCgYICQAAAA==.',
We='Weyoun:BAAANQAECgEIAQAAAA==.',
Wh='Wheetie:BAAANQAECgMIAwAAAA==.',
Wi='Williwaw:BAAANQADCgQIBwAAAA==.Winterstormm:BAAANQAECgEIAQAAAA==.',
Wn='Wno:BAAANQADCgcIBwAAAA==.',
Wo='Wobbuffet:BAAANQAECgcIDwAAAA==.Wolfen:BAAANQADCgcIDgAAAA==.',
Wy='Wyrnn:BAAANQAECgUIBwAAAA==.',
Xa='Xaniran:BAAANQADCgYICAAAAA==.',
Xe='Xelbino:BAAANQADCgEIAQAAAA==.',
Xi='Xiaobi:BAAANQAECgcIBwAAAA==.Xintar:BAAANQADCggIEAAAAA==.Xiomana:BAAANQAECgEIAQAAAA==.Xion:BAAANQAECgYICQAAAA==.',
Xy='Xyluna:BAAANQADCgYIBgABNQAECgYIDgABAAAAAA==.',
Ye='Yebanned:BAAANQADCggICAABNQAECgkJHwASAEkiAA==.Yellowajah:BAAANQAECgQIBQABNQAECgcIEQABAAAAAA==.',
Yi='Yify:BAAANQADCgUIBQABNQADCgcICwABAAAAAA==.',
Yn='Yneva:BAAANQAECgEIAgAAAA==.',
Yw='Ywrensire:BAAANQADCgQIBAAAAA==.',
Za='Zaabra:BAAANQADCgcICAAAAA==.Zaion:BAAANQAECgEIAQAAAA==.',
Ze='Zealis:BAAANQAECgEIAgAAAA==.Zebby:BAAANQADCggICAAAAA==.Zedar:BAAANQAECgEIAQABNQAECgUIEAABAAAAAA==.',
Zh='Zhi:BAAANQAECgEIAQAAAA==.',
Zi='Zilin:BAAANQAECgEIAQAAAA==.',
Zo='Zolce:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.',
Zu='Zuularok:BAAANQADCgUIBQAAAA==.',
Zy='Zybaxos:BAAANQAECgYICgAAAA==.',
Zz='Zzro:BAAANQADCgYICAAAAA==.',
['Ãr']='Ãrçâñîst:BAAANQADCgYIBgAAAA==.',
['År']='Årchon:BAAANQAECgEIAQAAAA==.Årtix:BAAANQADCgYIBgABNQADCgYICgABAAAAAA==.',
['Îs']='Îssy:BAAANQAECgIIAgAAAA==.',
['Ôr']='Ôrkásh:BAAANQADCgcIDgAAAA==.',
['Öm']='Ömegoss:BAAANQADCgcIGwAAAA==.',
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
