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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Mage-Arcane','Warrior-Arms',}
local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aassvik:BAAANQADCggIEwAAAA==.',
Ab='Absolute:BAAANQAECggIEQAAAA==.',
Ac='Achieved:BAAANQAECgYICgAAAA==.Achievsome:BAAANQAECgcIDwAAAA==.',
Ad='Adorabull:BAAANQADCgEIAQAAAA==.',
Ag='Agrajag:BAAANQADCgUIBQABNQAECgQICQABAAAAAA==.',
Ah='Ahnruun:BAAANQAECgEIAQAAAA==.',
Ak='Akagrats:BAAANQADCgEIAQAAAA==.',
Al='Alessandro:BAAANQADCgYIDQAAAA==.Aliengrey:BAAANQADCgYIBgAAAA==.Alonsusfaol:BAAANQAECgMIBAAAAA==.Alrsta:BAAANQADCgIIAQAAAA==.',
Am='Amane:BAAANQAECgUIDAAAAA==.Ammaydie:BAAANQADCgIIAgAAAA==.Amytenchi:BAAANQABCgQIAwAAAA==.',
An='Annya:BAAANQAECgUIBgAAAA==.',
Ar='Archdragon:BAAANQADCgMIAwABNQAECgMIBQABAAAAAA==.Aristae:BAAANQABCgIIAgABNQADCgcIEgABAAAAAA==.Arkanis:BAAANQAECgQIBQAAAA==.Armament:BAAANQAECgQIBgAAAA==.',
As='Ashleymarion:BAAANQADCgIIAgAAAA==.',
Au='Aurafiora:BAAANQAECgYICAAAAA==.Aurius:BAAANQAECgEIAQAAAA==.',
Av='Avalancha:BAAANQAECgIIAgAAAA==.Avinoch:BAAANQADCgcIDwAAAA==.',
Ax='Axon:BAAANQAECgcICQAAAA==.',
Ay='Aynhillbeads:BAAANQADCggIFQAAAA==.',
Az='Azekor:BAAANQADCggIDgAAAA==.Azenroth:BAAANQADCggICQAAAA==.Azureth:BAAANQAECgQIBAAAAA==.',
Ba='Babykay:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.Bakimono:BAAANQADCgQIBAAAAA==.Banehellborn:BAAANQAECgEIAgAAAA==.Barnicas:BAAANQADCgYICQAAAA==.Bartholomäus:BAAANQADCgMIBgAAAA==.',
Be='Beezlebumon:BAAANQAECgQIBgAAAA==.Bewater:BAAANQAECgUICQAAAA==.',
Bl='Blóðugrgríma:BAAANQAECgEIAQAAAA==.',
Bo='Bobabear:BAAANQADCggIJgAAAA==.Bonersimpsun:BAAANQAECgMIAwAAAA==.Boombastic:BAAANQADCgYIBwAAAA==.Boomchicken:BAAANQABCgQIAwAAAA==.Boomclap:BAAANQAECgYIDAAAAA==.',
Bp='Bpbreezy:BAAANQAFFAEIAQAAAA==.',
Br='Bracknor:BAAANQAECgYIBgAAAA==.Braknight:BAAANQADCgYIBgAAAA==.Brandonb:BAAANQAECgYICwAAAA==.Brandonw:BAAANQADCgUICAAAAA==.Bredock:BAAANQADCgYIBgABNQAECgkJFQACAGoZAA==.Brotem:BAAANQAECgEIAQAAAA==.Brutalisto:BAAANQADCggICQAAAA==.Brynnbramble:BAAANQADCgYIBgAAAA==.',
By='Bysokar:BAAANQAECgYICQAAAA==.',
Ca='Cainfortea:BAAANQADCgUIDAAAAA==.Cakel:BAAANQADCgcIBwAAAA==.Calipal:BAAANQADCggIEAAAAA==.Calipriest:BAAANQADCgQIAgAAAA==.Catalinasham:BAABNQAFFIEGAAIDAAQJ7hO8AQBmAQADAAQJ7hO8AQBmAQABNQAFFAQJBgADAO4TAA==.Catalïna:BAAANQADCgcIBwABNQAFFAQJBgADAO4TAA==.Cazadore:BAAANQADCggIDwAAAA==.',
Ce='Celebrimbjor:BAAANQAECgEIAQAAAA==.Cerberusbone:BAAANQAECgQIBAAAAA==.',
Ch='Challengerz:BAAANQADCgYIBgAAAA==.Charliehorse:BAAANQADCgQIBAAAAA==.Chopper:BAAANQADCggIFwAAAA==.',
Ci='Cinderlily:BAAANQADCgcIDgAAAA==.',
Co='Conflagrate:BAAANQAECgcIDAAAAA==.Connery:BAAANQADCgUICQAAAA==.Cornpopp:BAAANQABCgYICAAAAA==.',
Cp='Cptcrushingb:BAAANQADCgYICAAAAA==.',
Cr='Crax:BAAANQADCgMIBAAAAA==.Crithappens:BAAANQADCggIEgAAAA==.Criturrpants:BAAANQADCgYICwAAAA==.Crouch:BAAANQAECgIIAgAAAA==.',
Cy='Cynnå:BAAANQAECgEIAQAAAA==.Cynthea:BAAANQADCgMIAwAAAA==.Cyp:BAAANQAECgYIDAAAAA==.',
Da='Dababycar:BAAANQADCggIDwAAAA==.Dabbyduck:BAAANQAECgcIEwAAAA==.Dambalah:BAAANQADCgYIBgAAAA==.Danifru:BAAANQAECgIIAgAAAA==.Darren:BAAANQABCgQIAwAAAA==.',
De='Deadincide:BAEANQAECgIIAgAAAA==.Deadstasheo:BAAANQAECgcIDAAAAA==.Deathblight:BAAANQADCgYIBAAAAA==.Decree:BAAANQADCgcIEgAAAA==.Deezmonz:BAAANQADCggICAABNQAECgQICQABAAAAAA==.Delik:BAAANQAECgIIAgAAAA==.Demonarch:BAAANQADCgYICgAAAA==.Demonlordmeh:BAAANQADCgUICQAAAA==.Deneol:BAAANQAECgMIBAAAAA==.Destrogen:BAAANQAECgEIAgAAAA==.Desìre:BAAANQAECgIIAgAAAA==.Deäthgär:BAAANQADCgMIAwABNQADCgcIEQABAAAAAA==.',
Di='Diabolic:BAAANQADCggICAAAAA==.Dirty:BAAANQADCgcIEQAAAA==.',
Dk='Dksura:BAAANQADCggIEQAAAA==.',
Do='Doomshield:BAAANQAECgEIAQAAAA==.Doomshroud:BAAANQABCgQIBAABNQAECgEIAQABAAAAAA==.',
Dr='Dracodeez:BAAANQADCggIFgAAAA==.Driretlan:BAAANQADCgYIBwAAAA==.Druss:BAAANQAECgUICAAAAA==.',
['Dì']='Dìesèl:BAAANQAECgIIAgAAAA==.',
Ei='Eileen:BAAANQABCgIIBAAAAA==.',
Em='Emilianaluz:BAAANQADCgYICgAAAA==.',
En='Endeavor:BAAANQADCgcIDAAAAA==.',
Eq='Equâs:BAAANQADCgYICwAAAA==.',
Er='Eradion:BAAANQADCgcICgAAAA==.Eredarlord:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Erelm:BAAANQAECgEIAQAAAA==.Erisson:BAAANQAECgIIBAAAAA==.Errorèdivina:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
Es='Eszran:BAAANQADCgYIDwAAAA==.',
Eu='Euthanized:BAAANQAECgEIAQAAAA==.',
Fa='Fasani:BAAANQABCgYICAAAAA==.',
Fe='Fennar:BAAANQAECgEIAgAAAA==.Ferosha:BAAANQAECgYICAAAAA==.Fexxyr:BAAANQADCgYIDAABNQAECggIEwABAAAAAA==.',
Fi='Fiadh:BAAANQABCgQIBAAAAA==.Firm:BAAANQADCgMIBQAAAA==.Firstfear:BAAANQADCgYIBgAAAA==.Fisch:BAAANQADCggIGAAAAA==.',
Fl='Flemtok:BAAANQAECggIAQAAAA==.Flidd:BAAANQADCggIFgAAAA==.Flipingtiska:BAAANQADCgEIAQAAAA==.Floisa:BAAANQADCgQIBAAAAA==.',
Fr='Fragtastic:BAAANQAECgYICQAAAA==.Frearyne:BAAANQAECgMIBQAAAA==.Frinu:BAAANQAECgIIAgABNQABCgIIAgABAAAAAA==.Frogs:BAAANQADCgcIDwAAAA==.Frostyshadow:BAAANQAECgQICwAAAA==.',
Fs='Fstingnemo:BAAANQAECgYICgAAAA==.',
Fy='Fyxxie:BAAANQAECggIEwAAAA==.',
Ga='Gaucho:BAAANQABCgIIAgAAAA==.',
Ge='Genvissa:BAAANQAECgYICgAAAA==.',
Gi='Gialiana:BAAANQAECgQIBQAAAA==.',
Go='Goobby:BAAANQADCgcIDAAAAA==.',
Gr='Grassfed:BAAANQAECgYIDAAAAA==.Greenymeany:BAAANQAECgQIBwAAAA==.Grully:BAAANQAECgYICgAAAA==.',
Gw='Gwumpy:BAAANQAECgEIAQAAAA==.',
Ha='Haggard:BAAANQAECgIIAgAAAA==.Hailsbelle:BAAANQADCggIFQAAAA==.Hashtag:BAAANQADCgMIBgAAAA==.',
Hb='Hbic:BAAANQADCggIDAAAAA==.',
He='Healyboar:BAAANQADCgUIBQAAAA==.Heartstabber:BAAANQAECgIIAgAAAA==.Hellbane:BAAANQADCgYIBgAAAA==.',
Ho='Holyling:BAAANQADCgYIBgAAAA==.Hondurasman:BAAANQADCgEIAQAAAA==.Honkhonk:BAAANQADCgcIDwAAAA==.',
Hr='Hraktar:BAAANQADCgEIAQAAAA==.',
Ie='Ievil:BAAANQAECgEIAQAAAA==.',
Ik='Ikasha:BAAANQADCggICAAAAA==.',
Im='Imjustpika:BAAANQAECggIEgAAAA==.',
In='Inawee:BAAANQAECgYICwAAAA==.Inferniö:BAABNQAECoEWAAIEAAkJXSLBCgBnAwAEAAkJXSLBCgBnAwAAAA==.Inkurushio:BAAANQAECgIIAwAAAA==.',
Io='Iolanie:BAAANQADCggICAAAAA==.',
Is='Ismat:BAAANQAECgYICwAAAA==.',
Ja='Jaeza:BAAANQADCgQIBwABNQAECgQIBQABAAAAAA==.Jarshh:BAAANQADCggIFgAAAA==.',
Jo='Johnefive:BAAANQAECgQICQAAAA==.Jorrick:BAAANQADCggIEwAAAA==.',
Ju='Juura:BAAANQABCgUIBQAAAA==.',
Ka='Kalukaynas:BAAANQADCgYIBwAAAA==.Kassian:BAAANQABCgIIAgAAAA==.',
Ke='Kelaan:BAAANQAECgIIAgAAAA==.Kelimao:BAAANQADCggICAAAAA==.Kendrà:BAAANQADCgIIAgAAAA==.Kevron:BAAANQAECgEIAQAAAA==.',
Ki='Killingame:BAAANQABCgEIAQAAAA==.Kiritos:BAAANQADCggIFgAAAA==.Kiserys:BAAANQAECgQIBQAAAA==.',
Ko='Koharu:BAAANQABCgQIBAAAAA==.Kollia:BAAANQADCgEIAgAAAA==.Korena:BAAANQADCgUIBwAAAA==.Kostard:BAAANQAECgEIAQAAAA==.',
Kr='Krysto:BAAANQAECgIIAgAAAA==.',
Le='Lenin:BAAANQAECgQIBQAAAA==.',
Li='Lightmasta:BAAANQADCgYIBgAAAA==.Liily:BAAANQADCggICAAAAA==.Likdiso:BAAANQADCgcIBwAAAA==.Lilydari:BAAANQADCgEIAQAAAA==.Lizzmo:BAAANQABCgQIBAAAAA==.',
Lo='Lookforlight:BAAANQAECgUICgAAAA==.Lorenth:BAAANQADCggIEgAAAA==.',
Lu='Lucid:BAAANQADCggIEAAAAA==.Luckyjade:BAAANQADCggIDgAAAA==.',
['Lì']='Lìte:BAAANQADCggIEwAAAA==.',
Ma='Mabi:BAAANQADCgUIBQAAAA==.Macarthur:BAAANQAECgQIBgAAAA==.Madcowburger:BAAANQADCgYICwAAAA==.Mageyoulookk:BAAANQADCgIIAgAAAA==.Malagu:BAAANQAECgIIAgABNQAECgQICwABAAAAAA==.Malidros:BAAANQADCgcIEgAAAA==.Malign:BAAANQAECgEIAQABNQAECggIEQABAAAAAA==.Marhault:BAAANQAECgYICwAAAA==.Masitaka:BAAANQAECgYICwAAAA==.Matt:BAAANQABCgQIBQAAAA==.Maxicat:BAAANQADCgYICgAAAA==.Maximus:BAAANQADCggIEwAAAA==.Mazah:BAAANQAECgYICwAAAA==.Mazlo:BAAANQAECgYIEAAAAA==.',
Me='Meleebrain:BAAANQABCgEIAQABNQAECgQICQABAAAAAA==.Mellethir:BAAANQAECgQIBgAAAA==.Mex:BAAANQADCggIDAAAAA==.',
Mi='Minipimp:BAAANQABCgYICwAAAA==.Missoxx:BAAANQADCgIIAgAAAA==.Mistbringer:BAAANQADCgcIDQAAAA==.',
Mo='Moarhots:BAAANQADCgIIAgAAAA==.Mofoasso:BAAANQAECgIIAgAAAA==.Moglayn:BAAANQAECgYICgAAAA==.Monkazz:BAAANQADCgQIBAAAAA==.Monkorith:BAEANQAECggIEwAAAA==.Mortis:BAAANQADCgIIAgAAAA==.',
Mu='Mullett:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.',
My='Myspace:BAAANQADCgYIBgAAAA==.Mystogaan:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãdmåx:BAAANQABCgQIBAAAAA==.',
['Mø']='Mørbid:BAAANQADCgYIBgAAAA==.',
Na='Nakiki:BAAANQADCgYIDAAAAA==.Nastyiam:BAAANQAECgQIBQAAAA==.',
Ne='Nerfornothin:BAAANQADCgcIDgAAAA==.Nethflap:BAAANQAECgUICQAAAA==.Nezhi:BAAANQADCgIIAgAAAA==.',
Ni='Nialin:BAAANQADCgcIBwAAAA==.Nifru:BAAANQADCgMIAwAAAA==.Niik:BAAANQAECggIDwAAAA==.',
No='Norgahl:BAAANQADCgMIBAAAAA==.Nosferato:BAAANQADCgEIAQAAAA==.',
Nu='Nutmilker:BAAANQAECgUICgAAAA==.',
Ny='Nyxnight:BAAANQADCgEIAQAAAA==.',
Ob='Obi:BAAANQADCgcIDQAAAA==.',
Om='Omacron:BAAANQADCgEIAQAAAA==.',
Or='Oriion:BAAANQADCgMIBQAAAA==.Orthae:BAAANQABCgQIBgABNQAECgQIBQABAAAAAA==.',
Ou='Outstanding:BAAANQADCgYIDAABNQADCggIEwABAAAAAA==.',
Pa='Pandoosevelt:BAAANQADCgQIAwAAAA==.',
Pe='Pepis:BAAANQADCggICAAAAA==.',
Ph='Phemera:BAAANQADCgMIAwAAAA==.Philidan:BAAANQADCgcIBwAAAA==.',
Pi='Pilgor:BAAANQAECgMIBAAAAA==.',
Po='Polkovnik:BAABNQAECoEYAAIFAAkJZRepGgCvAgAFAAkJZRepGgCvAgAAAA==.',
Pr='Pravaat:BAAANQAECgIIAgAAAA==.Prayvus:BAAANQADCgIIAgAAAA==.Preroll:BAAANQADCgIIAQAAAA==.Prisonsoul:BAAANQADCgYIBgAAAA==.',
Py='Pylon:BAAANQADCgUICAAAAA==.',
['Pæ']='Pæsta:BAAANQAECgYIBwAAAA==.',
Qu='Qubit:BAEANQADCgcIEwABNQAECgIIAgABAAAAAA==.',
Ra='Rast:BAAANQADCggIEwAAAA==.Rastabout:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.Ravel:BAAANQADCggIFgAAAA==.',
Re='Reahla:BAAANQADCgcIBwAAAA==.Reclaim:BAAANQAECgQIBgAAAA==.Reios:BAAANQAECgIIAgAAAA==.',
Rh='Rhaz:BAAANQADCggIFQAAAA==.Rhikre:BAAANQADCgUIBQAAAA==.Rhoup:BAAANQADCgcIBgABNQAECgQIBAABAAAAAA==.',
Ri='Rickyspanish:BAAANQAECgQIBgAAAA==.Rifter:BAAANQADCgYIDwAAAA==.Rikkibobbi:BAAANQADCgMIAwABNQADCgYIBgABAAAAAA==.Rivensong:BAAANQADCggICAAAAA==.',
Ro='Rontastico:BAAANQADCgEIAQAAAA==.Roupert:BAAANQAECgQIBAAAAA==.',
Ru='Rubyouraw:BAAANQADCggIFQAAAA==.Ruffneck:BAAANQAECgIIAgAAAA==.Russk:BAAANQADCgIIAgAAAA==.',
['Rû']='Rûsko:BAAANQADCgYICQAAAA==.',
Sa='Saelaan:BAAANQAECgEIAgABNQAECgIIAgABAAAAAA==.Sailfu:BAAANQAECggIEgABNQAECggIEQABAAAAAA==.Salami:BAAANQADCgcICwAAAA==.Samo:BAAANQADCggIEwAAAA==.Sandarr:BAAANQADCggIEgAAAA==.Sanguinne:BAAANQADCgYIDQAAAA==.Santhus:BAAANQADCgcIFAAAAA==.Saretae:BAAANQADCgcIBwAAAA==.Sargemarge:BAAANQAECgYICgAAAA==.',
Sc='Sci:BAAANQAECgQICgAAAA==.',
Se='Selener:BAAANQADCggIDQAAAA==.Serrata:BAAANQADCgMIAwAAAA==.Seymorweiner:BAAANQADCgMIAwAAAA==.',
Sh='Shamski:BAAANQADCgYIBQABNQAECgIIAwABAAAAAA==.',
Si='Silther:BAAANQADCggIFwAAAA==.',
Sl='Slavka:BAAANQADCgMIBAAAAA==.',
Sm='Smaalls:BAAANQADCgIIAgAAAA==.Smote:BAAANQADCgYIBgAAAA==.',
Sn='Snâppy:BAAANQADCggIEwAAAA==.',
So='Soloron:BAAANQADCggIFAAAAA==.Sorrowsöng:BAAANQADCggIFgAAAA==.',
Sp='Spamlock:BAAANQABCgYICgABNQAFFAEIAQABAAAAAA==.Sparrhawk:BAAANQADCgcIDAAAAA==.Spiced:BAAANQAECgcIBQAAAA==.Spirithaeler:BAAANQABCgIIAgAAAA==.',
St='Stabulóus:BAAANQADCggIAQAAAA==.Starskream:BAAANQABCgQIBAAAAA==.Steelarrow:BAAANQADCgUIBQAAAA==.Steliokontos:BAAANQABCgIIAgAAAA==.Stickes:BAAANQADCggICAAAAA==.Stormclaw:BAAANQADCgYIBgABNQAECgYICgABAAAAAA==.Stormfall:BAAANQADCgYICwAAAA==.Streea:BAAANQABCgYICgABNQAECgQIBQABAAAAAA==.Styx:BAAANQABCgQIBAABNQADCgIIAgABAAAAAA==.',
Sy='Synsairis:BAAANQADCggIFgAAAA==.',
Ta='Talenelat:BAAANQADCgYIBgAAAA==.Talonknight:BAAANQADCggIEwAAAA==.Tau:BAAANQABCgQIBAAAAA==.Tauria:BAAANQABCgQICAAAAA==.Taurrows:BAAANQABCgMIBAAAAA==.Tavinz:BAAANQADCgYIDgAAAA==.',
Th='Thaendofyou:BAAANQADCggICwAAAA==.Thalonis:BAAANQABCgQIBAAAAA==.Thelas:BAAANQADCgIIAgAAAA==.Therise:BAAANQADCggIEAABNQAECgYICwABAAAAAA==.Thetank:BAAANQAECgYIBgAAAA==.Thoroughbred:BAAANQADCgYIBgAAAA==.Throwdini:BAAANQAECgUIBwAAAA==.Thunder:BAAANQABCgIIAgABNQABCgQIBAABAAAAAA==.',
Ti='Tixxle:BAAANQADCgMIAwAAAA==.',
To='Totemaka:BAAANQADCgUIBQAAAA==.Touchmé:BAAANQADCgQIBAAAAA==.Tousle:BAAANQADCgUIBQABNQAECgcIDAABAAAAAA==.',
Tr='Treateak:BAAANQADCgYIBgAAAA==.Trotsky:BAAANQAECgIIBAAAAA==.Trögdor:BAAANQADCgUIBQAAAA==.',
Tu='Tulanis:BAAANQAECgYICwAAAA==.Turbotax:BAAANQADCgEIAQAAAA==.',
Ty='Tyfa:BAAANQADCggIDgAAAA==.Tyriem:BAAANQAECgMIAwAAAA==.Tyssanton:BAAANQAECgIIAgAAAA==.',
Tz='Tziganin:BAAANQADCggIFgAAAA==.',
Ug='Uggork:BAAANQADCgQIBwABNQADCgYIBwABAAAAAA==.',
Un='Unholybussy:BAAANQADCggIFgAAAA==.',
Ut='Utaadh:BAAANQAECgQIBQAAAA==.',
Va='Vaelhorn:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.Vallerin:BAAANQADCggIEAAAAA==.',
Ve='Velaar:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.',
Vi='Vicenti:BAAANQADCgYIEQAAAA==.',
Vo='Vodnar:BAABNQAECoEVAAICAAkJahk5DQDLAgACAAkJahk5DQDLAgAAAA==.',
Vu='Vulnixia:BAAANQAECgIIAgAAAA==.',
Wa='Walls:BAAANQADCgcIEgAAAA==.Waste:BAAANQADCggICAAAAA==.Wawel:BAAANQAECgUIBwAAAA==.Wazwaz:BAAANQAECgEIAQABNQAECgQICgABAAAAAA==.',
Wi='Wildbill:BAAANQAECgEIAQAAAA==.Willîe:BAAANQADCgYIBgAAAA==.Wingsofsteel:BAAANQABCgQIBAAAAA==.',
Wo='Wowiezonk:BAAANQABCgIIAgAAAA==.',
Xe='Xerethis:BAAANQADCgcIDAAAAA==.',
Yn='Yn:BAAANQABCgQIBgAAAA==.',
Yo='Yogí:BAAANQAECgQIBwAAAA==.Yokos:BAAANQADCgMIAwAAAA==.',
Yu='Yunkali:BAAANQADCgIIAgAAAA==.',
Za='Zahneel:BAAANQADCggIEgAAAA==.Zarallia:BAAANQAECgQIBQAAAA==.Zaratul:BAAANQAECgcIEAAAAA==.Zarisong:BAAANQADCggIDwAAAA==.',
Zh='Zhawaricus:BAAANQAECgEIAgAAAA==.',
Zu='Zugssico:BAAANQADCgYIBgAAAA==.',
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
