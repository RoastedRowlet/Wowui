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

local lookup = {'DemonHunter-Devourer','Unknown-Unknown','Priest-Holy','Hunter-BeastMastery','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Priest-Shadow','Hunter-Survival','Mage-Arcane','Paladin-Retribution','Mage-Frost','Monk-Brewmaster','Warrior-Arms','Monk-Windwalker',}
local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aassvik:BAAANQAECgMIAwAAAA==.',
Ab='Absolute:BAABNQAECoEYAAIBAAkJxCE2BAB0AwABAAkJxCE2BAB0AwAAAA==.',
Ac='Achelin:BAAANQADCgUIBQAAAA==.Achieved:BAAANQAFFAIIAgAAAA==.Achievsome:BAAANQAECggIEAAAAA==.',
Ad='Adorabull:BAAANQADCgQIBQAAAA==.',
Ae='Aethalas:BAAANQABCgIIAgAAAA==.',
Ag='Agrajag:BAAANQADCgUIBQABNQAECgcIEAACAAAAAA==.',
Ah='Ahnruun:BAAANQAECgQIBQAAAA==.',
Ai='Aiona:BAAANQADCgQIBAAAAA==.',
Ak='Akagrats:BAAANQADCgEIAQAAAA==.',
Al='Alessandro:BAAANQAECgMIAwAAAA==.Aliengrey:BAAANQADCgcICQAAAA==.Alonsusfaol:BAAANQAECgQICAAAAA==.Alrsta:BAAANQADCgIIAQAAAA==.Alunarteil:BAAANQADCgEIAQAAAA==.',
Am='Amane:BAAANQAECgcIEwAAAA==.Ammaydie:BAAANQADCgIIAgAAAA==.Amytenchi:BAAANQABCgcICgAAAA==.',
An='Anger:BAAANQADCggICAAAAA==.Annya:BAAANQAECgUICgAAAA==.',
Ar='Archdragon:BAAANQADCgMIAwABNQAECgYICwACAAAAAA==.Aristae:BAAANQABCgIIAgABNQADCgcIGQACAAAAAA==.Arkanis:BAAANQAECgUICgAAAA==.Armament:BAAANQAECgQICQAAAA==.Arthus:BAAANQADCggICAAAAA==.',
As='Ashleymarion:BAAANQADCgIIAgAAAA==.',
Au='Aurafiora:BAAANQAECgcIDwAAAA==.Aurius:BAAANQAECgEIAQAAAA==.',
Av='Avalancha:BAAANQAECgUICAAAAA==.Avinoch:BAAANQADCggIFwAAAA==.',
Ax='Axon:BAAANQAECgcICwAAAA==.',
Ay='Aynhillbeads:BAAANQAECgEIAQAAAA==.',
Az='Azekor:BAAANQADCggIEQAAAA==.Azenroth:BAAANQAECgEIAQAAAA==.Azureth:BAAANQAECgUICQAAAA==.',
Ba='Babykay:BAAANQADCgUICAABNQAECgUICwACAAAAAA==.Bakimono:BAAANQADCgQIBAAAAA==.Banehellborn:BAAANQAECggICwAAAA==.Barnicas:BAAANQADCgYICQAAAA==.Bartholomäus:BAAANQADCgUICwAAAA==.',
Be='Beezlebumon:BAAANQAECggIDQAAAA==.Bellcross:BAAANQADCgUIBQAAAA==.Bewater:BAAANQAECgYIDQAAAA==.',
Bl='Blóðugrgríma:BAAANQAECgEIAQAAAA==.',
Bo='Bobabear:BAAANQAECgEIAQAAAA==.Bonersimpsun:BAAANQAECgMIBgAAAA==.Boombastic:BAAANQADCgYIBwAAAA==.Boomchicken:BAAANQADCgMIAwAAAA==.Boomclap:BAAANQAECgcIEwAAAA==.',
Bp='Bpbreezy:BAABNQAECoEYAAIDAAkJAh3VCwD3AgADAAkJAh3VCwD3AgAAAA==.',
Br='Bracknor:BAAANQAECgcIDQAAAA==.Braknight:BAAANQADCgYIBgAAAA==.Brandonb:BAAANQAECgcIEgAAAA==.Brandonw:BAAANQAECgQIBAAAAA==.Bredock:BAAANQADCgYIBgABNQAECgkJGAAEAPIdAA==.Brotem:BAAANQAECgEIAgAAAA==.Brutalisto:BAAANQADCggIDAAAAA==.Brynnbramble:BAAANQADCgcIDgAAAA==.',
By='Bysokar:BAAANQAECgYIDQAAAA==.',
Ca='Cainfortea:BAAANQADCgYIEgAAAA==.Cakel:BAAANQADCgcIBwAAAA==.Calipal:BAAANQADCggIFQAAAA==.Calipriest:BAAANQADCgQIAgAAAA==.Catalinasham:BAABNQAFFIEGAAIFAAQJ7hPqAwBfAQAFAAQJ7hPqAwBfAQABNQAFFAQJBgAFAO4TAA==.Catalïna:BAAANQADCgcIBwABNQAFFAQJBgAFAO4TAA==.Cazadore:BAAANQADCggIDwAAAA==.',
Ce='Celebrimbjor:BAAANQAECgEIAQAAAA==.Cerberusbone:BAAANQAECgUICQAAAA==.',
Ch='Challengerz:BAAANQADCgYICAAAAA==.Charliehorse:BAAANQADCgQIBAAAAA==.Chopper:BAAANQAECgQIBAAAAA==.',
Ci='Cinderlily:BAAANQADCggIFgAAAA==.',
Co='Conflagrate:BAAANQAECgcIDQAAAA==.Connery:BAAANQADCgUIDQAAAA==.Cornpopp:BAAANQABCggIFQAAAA==.',
Cp='Cptcrushingb:BAAANQADCgYICAAAAA==.',
Cr='Crax:BAAANQADCgMIBAAAAA==.Crithappens:BAAANQADCggIGgAAAA==.Criturrpants:BAAANQADCgYIFwAAAA==.Crouch:BAAANQAECgIIAgAAAA==.',
Cy='Cynnå:BAAANQAECgIIAwAAAA==.Cynthea:BAAANQADCgMIAwAAAA==.Cyp:BAAANQAECgcIDwAAAA==.',
Da='Dababycar:BAAANQAECgIIAgAAAA==.Dabbyduck:BAABNQAECoEeAAMGAAkJsBnZDQDzAgAGAAkJsBnZDQDzAgAHAAcJehFjEQDGAQAAAA==.Dambalah:BAAANQADCgYIBgAAAA==.Danifru:BAAANQAECgIIAgAAAA==.Darren:BAAANQABCgcICgAAAA==.',
De='Deadincide:BAEANQAECgIIBAAAAA==.Deadstasheo:BAAANQAECgcIEwAAAA==.Deathblight:BAAANQADCgYIBAAAAA==.Decree:BAAANQAECgEIAQAAAA==.Deezmonz:BAAANQADCggIEAABNQAECgcIEAACAAAAAA==.Delik:BAAANQAECgUICAAAAA==.Demonarch:BAAANQADCgYICgAAAA==.Demonlordmeh:BAAANQADCgUICQAAAA==.Deneol:BAAANQAECgQICAAAAA==.Destrogen:BAAANQAECgEIAgAAAA==.Desìre:BAAANQAECgUIBwAAAA==.Deäthgär:BAAANQADCgMIAwABNQAECgQIBAACAAAAAA==.',
Di='Diabolic:BAAANQADCggICAAAAA==.Dirty:BAAANQADCggIGQAAAA==.',
Dk='Dksura:BAAANQAECgQIBAAAAA==.',
Do='Doomknight:BAAANQADCgYIBgAAAA==.Doomshield:BAAANQAECgEIAQAAAA==.Doomshroud:BAAANQABCgUIBQABNQAECgEIAQACAAAAAA==.',
Dr='Dracodeez:BAAANQAECgEIAQAAAA==.Driretlan:BAAANQADCgYIBwAAAA==.Druss:BAAANQAECgYIDAAAAA==.',
Du='Durunk:BAAANQADCgEIAQAAAA==.',
Dz='Dzimps:BAAANQABCgQIBAAAAA==.',
['Dì']='Dìesèl:BAAANQAECgQIBAAAAA==.',
Ei='Eileen:BAAANQABCgIIBAAAAA==.',
Em='Emilianaluz:BAAANQADCgYIDwAAAA==.',
En='Endeavor:BAAANQADCggIFAAAAA==.',
Eq='Equâs:BAAANQADCgcIDAAAAA==.',
Er='Eradion:BAAANQADCggIDQAAAA==.Eredarlord:BAAANQAECgQIBQAAAA==.Erelm:BAAANQAECgMIBAAAAA==.Erisson:BAAANQAECgMIBgAAAA==.Errorèdivina:BAAANQAECgEIAQAAAA==.',
Es='Eszran:BAAANQADCgcIEQAAAA==.',
Eu='Euthanized:BAAANQAECgEIAQAAAA==.',
Fa='Fasani:BAAANQABCgcICQAAAA==.',
Fe='Fennar:BAAANQAECgEIAwAAAA==.Ferosha:BAAANQAECgcIDwAAAA==.Fexxyr:BAAANQADCgYIDAABNQAECgkJFgAIALUVAA==.',
Fi='Fiadh:BAAANQABCgQIBAAAAA==.Firm:BAAANQADCgMIBQAAAA==.Firstfear:BAAANQADCgYICwAAAA==.Fisch:BAAANQAECgEIAQAAAA==.',
Fl='Flemtok:BAAANQAECggIAQAAAA==.Flidd:BAAANQAECgEIAQAAAA==.Flipingtiska:BAAANQAECgEIAQAAAA==.Floisa:BAAANQADCgQIBAAAAA==.Flynae:BAAANQAECgUIBQAAAA==.',
Fo='Fontingaul:BAAANQADCgcIBwAAAA==.',
Fr='Fragtastic:BAAANQAECgYIDwAAAA==.Frearyne:BAAANQAECgYICwAAAA==.Frinu:BAAANQAECgIIAgABNQABCgIIAgACAAAAAA==.Frogs:BAAANQADCggIFwAAAA==.Frostyshadow:BAAANQAECgUIEAAAAA==.',
Fs='Fstingnemo:BAAANQAECgcIEQAAAA==.',
Fy='Fyxxie:BAABNQAECoEWAAIIAAkJtRUmDgCPAgAIAAkJtRUmDgCPAgAAAA==.',
Ga='Gaucho:BAAANQABCgIIAgAAAA==.',
Ge='Genvissa:BAAANQAECgcIEAAAAA==.',
Gi='Gialiana:BAAANQAECgUICAAAAA==.',
Go='Goobby:BAAANQADCgcIDAAAAA==.',
Gr='Grassfed:BAAANQAECgcIEwAAAA==.Greenymeany:BAAANQAECgQICwAAAA==.Grully:BAAANQAECgYIEAAAAA==.',
Gw='Gwumpy:BAAANQAECgEIAQAAAA==.',
Ha='Haggard:BAAANQAECgUICAAAAA==.Hailsbelle:BAAANQADCggIFQAAAA==.Hashtag:BAAANQADCgUICwAAAA==.',
Hb='Hbic:BAAANQADCggIDAAAAA==.',
He='Healyboar:BAAANQADCgUIBQAAAA==.Heartstabber:BAAANQAECgQIBgAAAA==.Hellbane:BAAANQADCgYIBgAAAA==.',
Ho='Holyling:BAAANQADCgYIBgAAAA==.Hondurasman:BAAANQADCgEIAQAAAA==.Honkhonk:BAAANQADCggIFwAAAA==.',
Hr='Hraktar:BAAANQADCgEIAQAAAA==.',
Ic='Icwiener:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.',
Ie='Ievil:BAAANQAECgIIAwAAAA==.',
Ik='Ikasha:BAAANQADCggICAAAAA==.',
Im='Imjustpika:BAABNQAECoEWAAIJAAkJCxfiAQCoAgAJAAkJCxfiAQCoAgAAAA==.',
In='Inawee:BAAANQAECgcIEgAAAA==.Inferniö:BAABNQAECoEZAAIKAAkJXSLRFgBCAwAKAAkJXSLRFgBCAwAAAA==.Inkurushio:BAAANQAECgIIAwAAAA==.',
Io='Iolanie:BAAANQADCggICAAAAA==.',
Is='Ismat:BAAANQAECgcIEgAAAA==.',
Ja='Jaeza:BAAANQADCggIDwABNQAECgYICgACAAAAAA==.Jarshh:BAAANQAECgEIAQAAAA==.',
Jo='Johnefive:BAAANQAECgcIEAAAAA==.Jorrick:BAAANQAECgEIAQAAAA==.',
Ju='Judge:BAAANQAECgQIBAABNQAECgcIDwACAAAAAA==.Juura:BAAANQADCggICAAAAA==.',
Ka='Kalukaynas:BAAANQAECgIIAgAAAA==.Karrog:BAAANQABCgQIBAAAAA==.Kassian:BAAANQABCgIIAgAAAA==.Kaveros:BAAANQAECgEIAQAAAA==.',
Ke='Kelaan:BAAANQAECgQIBgAAAA==.Kelimao:BAAANQAECgEIAQAAAA==.Kendrà:BAAANQADCgIIAgAAAA==.Kevron:BAAANQAECgEIAQAAAA==.',
Ki='Kiimagi:BAAANQADCgEIAQAAAA==.Killingame:BAAANQABCgEIAQAAAA==.Kiritos:BAAANQADCggIHAAAAA==.Kiserys:BAAANQAECgQICQAAAA==.',
Ko='Koharu:BAAANQABCgcICgAAAA==.Kollia:BAAANQADCgEIAgAAAA==.Korena:BAAANQADCgUIBwAAAA==.Kostard:BAAANQAECgEIAQAAAA==.',
Kr='Krysto:BAAANQAECgUICAAAAA==.',
Ku='Kurlabji:BAAANQADCgUIBQAAAA==.',
Le='Lenin:BAAANQAECgQIBQAAAA==.',
Li='Lightmasta:BAAANQADCgYIBgAAAA==.Liily:BAAANQADCggIDAAAAA==.Likdiso:BAAANQADCgcIBwAAAA==.Lilydari:BAAANQADCgEIAQAAAA==.Lizzmo:BAAANQABCgQIBAAAAA==.',
Lo='Lookforlight:BAABNQAECoEZAAILAAgJSh4SIgCZAgALAAgJSh4SIgCZAgAAAA==.Lorenth:BAAANQAECgEIAQAAAA==.',
Lu='Lucid:BAAANQADCggIGAAAAA==.Luckyjade:BAAANQAECgIIAgAAAA==.',
['Lì']='Lìte:BAAANQAECgMIAwAAAA==.',
Ma='Mabi:BAAANQADCgUIBQAAAA==.Macarthur:BAAANQAECgUICwAAAA==.Madcowburger:BAAANQADCgYICwAAAA==.Mageyoulookk:BAAANQADCgIIAgAAAA==.Maizuko:BAAANQADCgUIBQABNQAECgcIEgACAAAAAA==.Malagu:BAAANQAECgIIAwABNQAECgUIEAACAAAAAA==.Malidros:BAAANQADCgcIEgAAAA==.Malign:BAAANQAECgEIAQABNQAECgkJGAABAMQhAA==.Manogawd:BAAANQADCgEIAQAAAA==.Marhault:BAAANQAECgcIEgAAAA==.Masitaka:BAAANQAECgcIEgAAAA==.Matt:BAAANQABCgQIBQAAAA==.Maxicat:BAAANQADCggIDAAAAA==.Maximus:BAAANQAECgMIAwAAAA==.Mazah:BAAANQAECgcIEgAAAA==.Mazlo:BAABNQAECoEXAAMMAAgJqhuSAgCXAgAMAAgJqhuSAgCXAgAKAAIJ6wC3LwE9AAAAAA==.',
Me='Meleebrain:BAAANQABCgEIAQABNQAECgcIEAACAAAAAA==.Mellethir:BAAANQAECgUICwAAAA==.Mex:BAAANQADCggIDAAAAA==.',
Mi='Minipimp:BAAANQABCggIEwAAAA==.Missoxx:BAAANQAECgQIBAAAAA==.Mistbringer:BAAANQADCggIFQAAAA==.',
Mo='Moarhots:BAAANQADCgIIAgAAAA==.Mofoasso:BAAANQAECgQIBgAAAA==.Moglayn:BAAANQAECgcIEQAAAA==.Monkazz:BAAANQADCgQIBAAAAA==.Monkorith:BAEBNQAECoEYAAINAAkJ1hZoBQBzAgANAAkJ1hZoBQBzAgAAAA==.Mortis:BAAANQADCgIIAgAAAA==.',
Mu='Mullett:BAAANQADCgMIAwABNQAECgUICwACAAAAAA==.',
My='Myspace:BAAANQADCgYIBgAAAA==.Mystogaan:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãdmåx:BAAANQABCgQIBAABNQABCgYIBgACAAAAAA==.',
['Mø']='Mørbid:BAAANQADCggICAAAAA==.',
Na='Nakiki:BAAANQADCgcIEwAAAA==.Nastyiam:BAAANQAECgQIBwAAAA==.',
Ne='Nerfornothin:BAAANQAECgMIAwAAAA==.Nethflap:BAAANQAECgYIDwAAAA==.Nezhi:BAAANQADCgIIAgAAAA==.',
Ni='Nialin:BAAANQADCgcIDAAAAA==.Nifru:BAAANQADCgMIAwAAAA==.Niik:BAABNQAECoEXAAIFAAkJ7hVxFQCrAgAFAAkJ7hVxFQCrAgAAAA==.',
No='Norgahl:BAAANQADCgMIBAAAAA==.Nosferato:BAAANQADCgEIAQAAAA==.',
Nu='Nutmilker:BAAANQAECgYIEAAAAA==.',
Ny='Nyxnight:BAAANQADCgEIAQAAAA==.',
Ob='Obi:BAAANQAECgEIAQAAAA==.',
Om='Omacron:BAAANQADCgEIAQAAAA==.',
Or='Oriion:BAAANQADCgMIBQAAAA==.Orthae:BAAANQADCgMIAwABNQAECgYICgACAAAAAA==.',
Ou='Outstanding:BAAANQADCgYIDAABNQAECgMIAwACAAAAAA==.',
Pa='Pandoosevelt:BAAANQADCgMIAwAAAA==.',
Pe='Pepis:BAAANQADCggICAAAAA==.',
Ph='Phemera:BAAANQADCgMIAwAAAA==.Philidan:BAAANQAECgIIAgAAAA==.Phyrra:BAAANQADCgEIAQAAAA==.',
Pi='Picklerickz:BAAANQADCgEIAQAAAA==.Pikagosa:BAAANQABCgEIAQABNQAECgkJFgAJAAsXAA==.Pilgor:BAAANQAECgQIBgAAAA==.',
Po='Polkovnik:BAABNQAECoEfAAIOAAkJqhqrIADSAgAOAAkJqhqrIADSAgAAAA==.Powderjinx:BAAANQADCgIIAgAAAA==.',
Pr='Pravaat:BAAANQAECgIIAgAAAA==.Prayvus:BAAANQADCgIIAgAAAA==.Preroll:BAAANQADCgEIAQAAAA==.Prisonsoul:BAAANQADCgYIBgAAAA==.',
Py='Pylon:BAAANQADCgUICAAAAA==.',
Qu='Qubit:BAEANQAECgEIAQABNQAECgIIBAACAAAAAA==.',
Ra='Rast:BAAANQAECgIIAgAAAA==.Rastabout:BAAANQADCggICwABNQAECgUICwACAAAAAA==.Ravel:BAAANQAECgEIAQAAAA==.',
Re='Reahla:BAAANQADCgcIBwAAAA==.Reclaim:BAAANQAECgUICwAAAA==.Reios:BAAANQAECgUICAAAAA==.',
Rh='Rhaego:BAAANQAECgUIBQAAAA==.Rhaz:BAAANQAECgMIAwAAAA==.Rhikre:BAAANQADCgUIBQAAAA==.Rhoup:BAAANQADCgcIBgABNQAECgQICAACAAAAAA==.',
Ri='Rickyspanish:BAAANQAECgUICwAAAA==.Rifter:BAAANQADCgYIEAAAAA==.Rikkibobbi:BAAANQADCgMIAwABNQADCgYIBgACAAAAAA==.Ripnmaim:BAEANQADCgYIBgABNQAECgIIBAACAAAAAA==.Rivensong:BAAANQADCggICAAAAA==.',
Ro='Rontastico:BAAANQADCgIIAgAAAA==.Roupert:BAAANQAECgQICAAAAA==.',
Ru='Rubyouraw:BAAANQADCggIHQAAAA==.Ruffneck:BAAANQAECgQIBgAAAA==.Russk:BAAANQADCgcICQAAAA==.',
['Rû']='Rûsko:BAAANQADCgYICgAAAA==.',
Sa='Saelaan:BAAANQAECgEIAgABNQAECgQIBgACAAAAAA==.Sailfu:BAABNQAECoEeAAIPAAkJACR8AQC0AwAPAAkJACR8AQC0AwABNQAECgkJGAABAMQhAA==.Saiyurie:BAAANQABCgIIAgAAAA==.Salami:BAAANQADCgcIDgAAAA==.Samo:BAAANQAECgMIAwAAAA==.Sandarr:BAAANQADCggIFQAAAA==.Sanguinne:BAAANQADCggIFQAAAA==.Santhus:BAAANQADCggIGwAAAA==.Saretae:BAAANQADCgcIDQAAAA==.Sargemarge:BAAANQAECgcIEQAAAA==.',
Sc='Sci:BAAANQAECgQIDwAAAA==.',
Se='Selener:BAAANQADCggIFQAAAA==.Serrata:BAAANQADCgUICAAAAA==.Seymorweiner:BAAANQADCgQIBQAAAA==.',
Sh='Shamski:BAAANQADCgYIBQABNQAECgIIAwACAAAAAA==.Shamydavisjr:BAAANQABCgYIBgAAAA==.',
Si='Silther:BAAANQAECgEIAQAAAA==.',
Sk='Skarath:BAAANQAECgEIAQAAAA==.',
Sl='Slavka:BAAANQADCgMIBQAAAA==.',
Sm='Smaalls:BAAANQADCgIIAgAAAA==.Smote:BAAANQADCggICAAAAA==.',
Sn='Snâppy:BAAANQAECgMIAwAAAA==.',
So='Soloron:BAAANQAECgMIAwAAAA==.Sorrowsöng:BAAANQAECgEIAQAAAA==.Southvik:BAAANQADCgcIBwABNQAECgMIAwACAAAAAA==.',
Sp='Spamlock:BAAANQAECgMIAwABNQAECgkJGAADAAIdAA==.Sparrhawk:BAAANQADCgcIDAAAAA==.Spiced:BAAANQAECgcICwAAAA==.Spirithaeler:BAAANQABCgIIAgAAAA==.Spood:BAAANQAECgMIAwAAAA==.',
St='Stabulóus:BAAANQADCggIAQAAAA==.Starskream:BAAANQABCgQIBAAAAA==.Steelarrow:BAAANQADCgUIBQAAAA==.Steliokontos:BAAANQABCgIIAgAAAA==.Stickes:BAAANQADCggICAAAAA==.Stingella:BAAANQADCgMIAwAAAA==.Stormclaw:BAAANQADCgYIBgABNQAECgcIEAACAAAAAA==.Stormfall:BAAANQADCgYIEQAAAA==.Streea:BAAANQABCgYICgABNQAECgYICgACAAAAAA==.Sttriker:BAAANQAECgMIAwAAAA==.Styx:BAAANQABCgQIBAABNQADCgIIAgACAAAAAA==.',
Sy='Synsairis:BAAANQAECgEIAQAAAA==.',
Ta='Talenelat:BAAANQADCggIDwAAAA==.Talonknight:BAAANQAECgMIAwAAAA==.Tau:BAAANQABCgYIBgAAAA==.Tauria:BAAANQABCggIDgAAAA==.Taurrows:BAAANQABCgYICAAAAA==.Tavaran:BAAANQABCgIIAgAAAA==.Tavinz:BAAANQADCgYIFAAAAA==.',
Th='Thaendofyou:BAAANQAECgMIAwAAAA==.Thalonis:BAAANQABCgYIBgAAAA==.Theladyheir:BAAANQADCgQIBAAAAA==.Thelas:BAAANQADCgQIBAABNQADCgcIDAACAAAAAA==.Therise:BAAANQADCggIEgABNQAECgcIEgACAAAAAA==.Thetank:BAAANQAECgcIDQAAAA==.Thoroughbred:BAAANQADCgYICwAAAA==.Throwdini:BAAANQAECgUIBwAAAA==.Thunder:BAAANQABCgIIAgABNQABCgQIBAACAAAAAA==.',
Ti='Timotthy:BAAANQAECgQIBAAAAA==.Tixxle:BAAANQADCggICwAAAA==.',
To='Totemaka:BAAANQADCgUIBQAAAA==.Touchmé:BAAANQADCgQIBAAAAA==.Tousle:BAAANQAECgUIBQABNQAECgcIDQACAAAAAA==.',
Tr='Treateak:BAAANQADCgYIBgAAAA==.Treb:BAAANQADCggICAAAAA==.Trotsky:BAAANQAECgcIDAAAAA==.Trögdor:BAAANQADCgUIBQAAAA==.',
Tu='Tulanis:BAAANQAECgcIEgAAAA==.Turbotax:BAAANQADCgEIAQAAAA==.',
Ty='Tyfa:BAAANQADCggIEQAAAA==.Tyriem:BAAANQAECgUICAAAAA==.Tyssanton:BAAANQAECgQIBwAAAA==.',
Tz='Tziganin:BAAANQAECgEIAQAAAA==.',
Ug='Uggork:BAAANQADCgQIBwABNQAECgIIAgACAAAAAA==.',
Un='Unholybussy:BAAANQADCggIFgAAAA==.',
Ut='Utaadh:BAAANQAECgQICQAAAA==.',
Va='Vael:BAAANQAECgIIAgABNQAECgcIEQACAAAAAA==.Vaelhorn:BAAANQADCgYICwABNQAECgMIBAACAAAAAA==.Vallerin:BAAANQAECgQIBAAAAA==.',
Ve='Velaar:BAAANQAECgIIAgABNQAECgcIEQACAAAAAA==.',
Vi='Vicenti:BAAANQADCgYIEQAAAA==.',
Vo='Vodnar:BAABNQAECoEYAAIEAAkJ8h3NEwDZAgAEAAkJ8h3NEwDZAgAAAA==.',
Vu='Vulnixia:BAAANQAECgUIBwAAAA==.',
Wa='Wagwan:BAAANQAECgEIAQAAAA==.Walls:BAAANQADCgcIGQAAAA==.Waste:BAAANQAECgEIAQAAAA==.Wawel:BAAANQAECgYICwAAAA==.Wazwaz:BAAANQAECgEIAQABNQAECgQIDwACAAAAAA==.',
Wi='Wildbill:BAAANQAECgIIAwAAAA==.Willîe:BAAANQADCgYIBgAAAA==.Wingsofsteel:BAAANQABCgQIBAAAAA==.',
Wo='Wolnir:BAAANQADCgQIBAAAAA==.Wowiezonk:BAAANQABCgIIAgAAAA==.',
Xe='Xerethis:BAAANQADCgcIDAAAAA==.',
Xs='Xshirroz:BAAANQADCggICAAAAA==.',
Yn='Yn:BAAANQABCgQIBgAAAA==.',
Yo='Yogí:BAAANQAECgYIDQAAAA==.Yokos:BAAANQADCgMIAwAAAA==.',
Yu='Yunkali:BAAANQADCgcIBwAAAA==.',
Za='Zahneel:BAAANQAECgEIAQAAAA==.Zarallia:BAAANQAECgQIBQAAAA==.Zaratul:BAABNQAECoEaAAILAAgJ6iDSGwDDAgALAAgJ6iDSGwDDAgAAAA==.Zarisong:BAAANQADCggIEwAAAA==.',
Zh='Zhawaricus:BAAANQAECgQIBgAAAA==.Zhuri:BAAANQABCgUICQAAAA==.',
Zo='Zoburg:BAAANQADCgYIBgABNQAECgMIAwACAAAAAA==.',
Zp='Zpig:BAAANQAECggICAAAAA==.',
Zu='Zugssico:BAAANQADCgYIBgAAAA==.',
Zy='Zyrian:BAAANQADCgUIBQAAAA==.',
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
