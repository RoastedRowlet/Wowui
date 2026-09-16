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

local lookup = {'Unknown-Unknown','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','DeathKnight-Blood','DeathKnight-Unholy','Mage-Frost','Mage-Arcane','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Acelord:BAAANQAECgMIBAAAAA==.',
Ad='Adariom:BAAANQADCgYIBgAAAA==.Adilma:BAAANQADCgQIBgAAAA==.Adriannos:BAAANQAECgEIAQAAAA==.',
Ae='Aerosharpz:BAAANQADCgYIBgAAAA==.',
Ag='Aghatta:BAAANQADCgUIBQAAAA==.',
Ak='Akiji:BAAANQADCggICQAAAA==.',
Al='Ald:BAAANQADCgYIBgAAAA==.Alexextreme:BAAANQAECgIIAgAAAA==.Algea:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Algrixx:BAAANQAECgIIAwAAAA==.Aliaksandr:BAAANQADCgUIDAAAAA==.',
An='Angelloz:BAAANQADCgYICwAAAA==.Anggos:BAAANQADCgMIAwAAAA==.Annedin:BAAANQABCgIIAgAAAA==.Annia:BAAANQADCgEIAQAAAA==.Anyid:BAAANQADCgIIAgAAAA==.Anysoul:BAAANQADCgEIAQABNQADCgIIAgABAAAAAA==.Anystorm:BAAANQADCgEIAQABNQADCgIIAgABAAAAAA==.',
Ap='Apökalÿpsïs:BAAANQAECgUIDAAAAA==.',
As='Asaff:BAAANQADCgMIBQAAAA==.',
At='Atonos:BAAANQABCggIDAAAAA==.',
Az='Azadium:BAAANQADCgEIAQAAAA==.Azul:BAAANQAECgMIBAAAAA==.Azzalyn:BAAANQADCgQIBQAAAA==.',
['Aë']='Aëma:BAAANQAECgQIBAAAAA==.',
Ba='Balragouldur:BAAANQADCgUIBgAAAA==.Barkbouncer:BAAANQADCggICAAAAA==.',
Be='Beatriz:BAAANQADCgYICAAAAA==.Beelgarath:BAAANQADCgEIAQAAAA==.Belowlight:BAAANQADCgYIBgAAAA==.Benícia:BAAANQABCgMIAwAAAA==.',
Bl='Blackfear:BAAANQADCggICAABNQAECgQICgABAAAAAA==.Blackteriaa:BAAANQAECgIIBAAAAA==.Blastoize:BAAANQADCgYIBwAAAA==.Bloodh:BAAANQAECgIIBAAAAA==.Bluforged:BAEANQAECgUICwAAAA==.',
Bo='Boamort:BAAANQAECgMIAwAAAA==.Boruck:BAAANQABCgEIAQAAAA==.',
Br='Braeon:BAAANQADCgYIDwAAAA==.Bridda:BAAANQADCgMIAwAAAA==.Brinkst:BAAANQAECgEIAQAAAA==.',
Bw='Bwozaghar:BAAANQADCgIIAgAAAA==.',
['Bø']='Bøamorte:BAAANQADCgEIAQAAAA==.',
Ca='Canaduh:BAAANQADCgUIBQAAAA==.Casuall:BAAANQADCggIEAAAAA==.Catalango:BAAANQADCgQIBQAAAA==.Catapinha:BAAANQAECgEIAQAAAA==.Catapó:BAAANQADCgMIAwAAAA==.',
Cl='Climps:BAAANQAECgQICQAAAA==.',
Co='Corollaxei:BAAANQADCgIIAgAAAA==.Corvean:BAAANQADCgUIBQAAAA==.',
Cr='Creuzapriest:BAAANQAECgIIAgAAAA==.Cruzade:BAAANQAECgQIBwABNQAECgQICgABAAAAAA==.Cröwllëy:BAAANQAECgIIAwAAAA==.',
Cu='Cubatao:BAAANQAECgEIAQAAAA==.Curatio:BAAANQADCggICQAAAA==.',
Da='Dahaka:BAAANQAECgIIAgAAAA==.Dakshayani:BAAANQAECgQIBAAAAA==.Dallion:BAAANQADCgUIDAAAAA==.Dardano:BAAANQABCggIDgAAAA==.Darkfuntz:BAAANQAECgYICgAAAA==.Darksiderxd:BAAANQADCgEIAQAAAA==.',
De='Deadvi:BAAANQAECgUICQAAAA==.Degenerative:BAAANQAECggIDgAAAA==.Derothey:BAAANQAECgQICgAAAA==.Devendeer:BAAANQABCgIIAgABNQAECgQIBAABAAAAAA==.',
Di='Dioniisio:BAAANQABCgQIBAAAAA==.',
Dk='Dkabeza:BAAANQADCgcIBwAAAA==.',
Dn='Dngkakuzo:BAAANQAECgMIBQAAAA==.',
Do='Doomsman:BAAANQADCgcICgAAAA==.',
Dr='Dracomamante:BAAANQAECgYIEgAAAA==.Draconoide:BAAANQAECgQIBgAAAA==.Dracón:BAAANQABCgEIAgAAAA==.Dragnnyr:BAAANQADCggICAAAAA==.Dragondrukc:BAAANQAECgQICQAAAA==.Dreykar:BAAANQAECgIIAwAAAA==.Druidaezeki:BAAANQADCgUIBwAAAA==.',
Du='Duquetjb:BAAANQADCgYICAAAAA==.',
['Dä']='Dähäkä:BAAANQAECgQIBAAAAA==.',
Ed='Edven:BAAANQAECgQICQAAAA==.',
Ei='Eilin:BAAANQADCgYICAAAAA==.',
El='Elbruxão:BAAANQAECgUIBQAAAA==.Eldarië:BAAANQABCgYICwAAAA==.Elementais:BAAANQAECgQICAAAAA==.Ellanor:BAAANQAECgQICQAAAA==.Ellocopere:BAAANQAECgMIAwAAAA==.Eltão:BAAANQADCgQIBQAAAA==.',
En='Envie:BAAANQAECgcIEgAAAA==.',
Er='Erickya:BAAANQAECgMIBAAAAA==.Ervadocè:BAAANQADCgYIDAAAAA==.Ervelino:BAAANQAECgQICAAAAA==.',
Es='Eskaris:BAAANQADCgQIBAAAAA==.Espectrudo:BAAANQADCgIIAgAAAA==.',
Ev='Evely:BAAANQAECgMIAwAAAA==.',
Fa='Falstro:BAAANQADCgYIBgAAAA==.',
Fi='Firexo:BAAANQADCgEIAQAAAA==.',
Fl='Flemma:BAAANQAECgQIBAAAAA==.Flexer:BAAANQAECgEIAQAAAA==.',
Fo='Fonderus:BAAANQADCgMIBAAAAA==.Foxyroxy:BAAANQADCgIIAgAAAA==.',
Fr='Friodokrl:BAAANQAECgYICwAAAA==.Frostmalt:BAAANQABCgQIBAAAAA==.',
Fu='Fubukiofhell:BAAANQAECgcIEwAAAA==.',
Ga='Gafgar:BAAANQADCgYIDAAAAA==.Gafowi:BAAANQAECgQIBAAAAA==.Galduin:BAAANQAECgYICAAAAA==.Garrincha:BAAANQADCgYIBwABNQAECgQIBQABAAAAAA==.Gaunterodim:BAAANQAECgEIAQAAAA==.',
Ge='Gever:BAAANQADCgUIBQAAAA==.',
Gh='Ghopo:BAAANQADCgYICgAAAA==.',
Gi='Giradus:BAAANQADCgUIBQAAAA==.',
Gl='Glorcckk:BAAANQADCgUIBgAAAA==.',
Gr='Grimblade:BAAANQADCgEIAQAAAA==.Grommhell:BAAANQAECgQICAAAAA==.Grím:BAAANQAECgEIAQAAAA==.',
Gu='Gudangara:BAAANQAECgEIAQAAAA==.Gugans:BAAANQADCgcICgAAAA==.Guzinbrs:BAAANQADCgcIBwAAAA==.',
Ha='Haakaí:BAAANQAECgEIAgAAAA==.Haandir:BAAANQAECgMIAwAAAA==.Hadassä:BAAANQABCgEIAgAAAA==.Harany:BAAANQADCgcICwABNQAECgEIAwABAAAAAA==.',
He='Herablack:BAAANQADCgUICQAAAA==.',
Hi='Himikonee:BAAANQAECgQICAAAAA==.',
Ho='Horstmeyer:BAAANQADCgIIAgAAAA==.',
Ib='Ib:BAAANQABCggIDQAAAA==.',
Ig='Igthil:BAAANQADCgUIBgAAAA==.',
Ik='Ikiam:BAAANQAECgYIDQAAAA==.Iksivokilirt:BAAANQADCgIIAgAAAA==.Ikslawok:BAAANQADCggIDwAAAA==.',
Il='Ileria:BAAANQADCggICgAAAA==.Illusionarc:BAAANQAECgQIBwABNQAECggIEgABAAAAAA==.',
Im='Imnotbryan:BAAANQADCgUIBQAAAA==.',
In='Incognita:BAAANQAECgUICQAAAA==.',
Ir='Iramm:BAAANQAECgIIAgAAAA==.Irion:BAAANQAECgEIAQAAAA==.',
Is='Iscalio:BAAANQAECgQIBQAAAA==.',
It='Itatchii:BAAANQADCggIFwAAAA==.',
Iu='Iuuh:BAAANQAECgYICgAAAA==.',
Ja='Jackdawnsong:BAAANQADCgQICAAAAA==.Jahuun:BAAANQAECgQICQAAAA==.',
Je='Jefflich:BAAANQAECgEIAQAAAA==.Jefãoo:BAAANQAECgQIBgAAAA==.',
Jj='Jjokerr:BAAANQADCgEIAQAAAA==.',
Ju='Jubard:BAAANQADCggIDAAAAA==.Justimonk:BAAANQADCgEIAQAAAA==.',
Ka='Kaelyrah:BAAANQADCgQIBAAAAA==.Kardibito:BAAANQADCgYIDAAAAA==.Karmysh:BAAANQADCgUICgAAAA==.Kazuopala:BAAANQAECgEIAQAAAA==.',
Kh='Khoj:BAAANQAECgQIBwAAAA==.Kholckk:BAAANQADCgUICgAAAA==.',
Ki='Killerdek:BAAANQADCgEIAQAAAA==.Killersall:BAAANQAECgUICAAAAA==.',
Kl='Kluzlocak:BAAANQADCggICQAAAA==.',
Ko='Kore:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.',
Ku='Kutirenzo:BAAANQADCgcIDwAAAA==.',
Ky='Kysed:BAAANQADCgMIAwAAAA==.',
La='Lafiel:BAAANQADCgcIEQAAAA==.Lahllis:BAAANQAECgIIAgAAAA==.Lanmo:BAAANQAECgYICgAAAA==.Laurea:BAAANQAECgcIEAAAAA==.',
Le='Ledor:BAAANQADCgYIBwAAAA==.Lendarion:BAAANQAECgQICQAAAA==.Leopvazi:BAAANQADCgIIAgAAAA==.Leozadock:BAAANQAECgQIBAAAAA==.',
Li='Lichtbaum:BAAANQAECgUICgAAAA==.Liifecomm:BAAANQAECgYIDQAAAA==.Lipaodrk:BAABNQAECoEkAAICAAkJIhlXEQDYAgACAAkJIhlXEQDYAgAAAA==.',
Lk='Lkazaktoch:BAAANQADCgQIBQAAAA==.',
Lo='Lordpain:BAAANQAECgYICgAAAA==.Lortherti:BAAANQADCgQIBgAAAA==.Louisenacioo:BAAANQAECgEIAQAAAA==.',
Lu='Luccablack:BAAANQADCgYIBwAAAA==.Luccagelido:BAAANQADCgUIBQAAAA==.Luidar:BAAANQAECgQIAwAAAA==.Lukaslions:BAAANQAECgUIBgAAAA==.Luphoe:BAAANQAECgEIAgAAAA==.',
Ma='Madushi:BAAANQAECgMIBAAAAA==.Madzerø:BAAANQAECgQIBAAAAA==.Magatas:BAAANQADCgQIBAAAAA==.Maguul:BAAANQADCgYIEwAAAA==.Malandrvs:BAAANQAECgYIDQAAAA==.Maldiçoadora:BAAANQAECgcIDgAAAA==.Mangudah:BAAANQADCggIGAABNQAECgMIBAABAAAAAA==.Mannaton:BAAANQAECgMIBAAAAA==.Manzagon:BAAANQADCggIFwABNQAECgMIBAABAAAAAA==.Marcijo:BAAANQABCgIIAgAAAA==.Maruh:BAAANQAECgUIBwAAAA==.Marúh:BAABNQAECoEbAAMDAAkJ1x37BwA4AwADAAkJ1x37BwA4AwAEAAIJ9wdmpABZAAAAAA==.Mayarabr:BAAANQABCgYICQAAAA==.Maølayking:BAABNQAECoEmAAMFAAkJ/SX6AADhAwAFAAkJ/SX6AADhAwAGAAIJwQuEawCAAAAAAA==.',
Mc='Mclovingo:BAAANQADCgUIBAAAAA==.',
Me='Mendingu:BAAANQAECgUICQAAAA==.Mercenarybr:BAAANQAECgUIBwAAAA==.',
Mi='Mikasaackerr:BAAANQAECgQIBQAAAA==.Milone:BAAANQADCgMIAwAAAA==.Mindlocker:BAAANQADCgQIBgAAAA==.Miranda:BAAANQADCggICAABNQAECgcIEAABAAAAAA==.Mistwarden:BAAANQADCgYICAAAAA==.',
Mm='Mmenov:BAAANQADCgMIAwAAAA==.Mmenovw:BAAANQADCgEIAQAAAA==.',
Mo='Molior:BAAANQADCgMIAgAAAA==.Momongadk:BAAANQAECgQICAAAAA==.Monkeydking:BAAANQAECgQIBAAAAA==.Monozoio:BAAANQADCgMIAwAAAA==.Moonluter:BAAANQADCgUIBwAAAA==.Morinami:BAAANQABCgQIBAAAAA==.Moriyama:BAAANQADCgcIEQAAAA==.Morphizs:BAAANQAECgIIAwABNQAECgMIBAABAAAAAA==.Morphoss:BAAANQADCgUICAABNQAECgMIBAABAAAAAA==.Mortesan:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.',
My='Mystian:BAAANQADCgYIBwAAAA==.',
['Må']='Måximus:BAAANQAECgMIBAAAAA==.',
Na='Naeryndam:BAAANQADCgYIEQAAAA==.Naturezo:BAAANQAECgEIAwAAAA==.',
Ne='Necrograves:BAAANQADCgUIBwAAAA==.Nedy:BAAANQADCgMIAwAAAA==.Negblack:BAAANQADCgUIBQAAAA==.Netherbane:BAAANQAECgEIAgAAAA==.Nezkur:BAAANQADCgMIBAAAAA==.Neürose:BAAANQADCgUIBgAAAA==.',
Ni='Ninfador:BAAANQADCgUIBQAAAA==.',
Oa='Oakshlar:BAAANQAECgEIAQAAAA==.Oalxorozco:BAAANQADCgIIAgAAAA==.',
Os='Osmotios:BAAANQAECgEIAQAAAA==.',
Ot='Otton:BAAANQADCggIGQAAAA==.',
Pa='Paidesanto:BAAANQAECgQIBQAAAA==.Paladinokun:BAAANQAECgEIAQAAAA==.Palamino:BAAANQADCgMIAwAAAA==.Pandadruid:BAAANQADCgYIBgAAAA==.Pantanegro:BAAANQADCgQIBAAAAA==.',
Pe='Pedrö:BAAANQAECgQICQAAAA==.Peçanhaa:BAAANQADCgQIBAAAAA==.',
Pl='Playsson:BAAANQAECgQICwAAAA==.',
Pq='Pqchoras:BAAANQAECgQIBAAAAA==.',
Pr='Pravios:BAAANQAECgIIAwAAAA==.',
Pu='Puherito:BAAANQADCgYIBgAAAA==.Purifc:BAAANQADCgEIAQAAAA==.',
Ra='Ravenblak:BAAANQADCgQIBAAAAA==.',
Re='Reigeladinho:BAAANQADCgcICAAAAA==.',
Ro='Robadoom:BAAANQABCgQIBAAAAA==.Rowane:BAAANQADCgQIBAAAAA==.',
Ru='Ruanna:BAAANQADCgEIAQAAAA==.Runak:BAAANQADCgcIGQAAAA==.',
Sa='Saanemi:BAAANQADCgIIAgAAAA==.Safiralc:BAAANQADCgEIAQAAAA==.Salaciel:BAAANQADCgcIDQAAAA==.Sardron:BAAANQADCgMIAwAAAA==.Saydrom:BAAANQADCgYIBgAAAA==.Sayur:BAAANQADCgcIDgAAAA==.',
Se='Sepp:BAAANQADCgIIAgAAAA==.',
Sh='Shaladrasil:BAAANQADCgEIAgAAAA==.Shieldhonor:BAAANQADCgYIEAAAAA==.Shisuui:BAAANQADCggIDwAAAA==.',
Si='Silvanna:BAAANQAECgEIAgAAAA==.Silvao:BAAANQADCgEIAgAAAA==.Sinkra:BAAANQADCgEIAQAAAA==.Sion:BAAANQADCgIIAgAAAA==.Sirgonzo:BAAANQAECgEIAQAAAA==.',
So='Sonofroar:BAAANQAECgQIBAAAAA==.Soray:BAAANQAECgIIAgAAAA==.Sorim:BAAANQADCggIGQAAAA==.',
St='Staffkiller:BAAANQAECgEIAQAAAA==.Strygah:BAAANQAECgIIAgAAAA==.Stx:BAAANQADCgYICwAAAA==.',
Su='Sushhi:BAAANQADCgEIAQAAAA==.',
Sw='Swam:BAAANQAECgMIBAABNQAECgYICgABAAAAAA==.',
Ta='Taillys:BAAANQADCgcICAAAAA==.Talanis:BAAANQADCggICAABNQAECgcIEAABAAAAAA==.Tamuriano:BAAANQADCgEIAQAAAA==.Tarez:BAAANQAECgEIAgAAAA==.Tarfonir:BAAANQAECgIIBAAAAA==.',
Te='Ted:BAAANQADCggIEAAAAA==.',
Th='Thejokker:BAAANQADCgcICAAAAA==.Themooster:BAAANQAECgQICgAAAA==.Thepickles:BAAANQADCgMIAwAAAA==.Thepunk:BAAANQAECgIIAgAAAA==.Thormento:BAAANQAECgYICAAAAA==.Throosh:BAAANQADCgQIBAAAAA==.Thundertroll:BAAANQADCgEIAQAAAA==.',
Ti='Tiriricao:BAAANQADCgQIBAAAAA==.Titanicos:BAAANQAECgEIAgAAAA==.Tiãocarneiro:BAAANQADCgIIAgAAAA==.',
To='Tobbiy:BAAANQAECgYIDQAAAA==.',
Tr='Trévor:BAAANQAECgEIAQAAAA==.',
Tu='Tubaras:BAAANQADCgEIAQAAAA==.Tututzz:BAAANQADCgMIAwAAAA==.',
['Tÿ']='Tÿriøn:BAAANQADCgYICwAAAA==.',
Va='Valmila:BAAANQAECgQIBAAAAA==.Vandlesh:BAAANQADCgIIAgAAAA==.',
Ve='Velkharun:BAAANQAECgQICgAAAA==.',
Vh='Vhaeraun:BAAANQADCgEIAQAAAA==.',
Vi='Viseryss:BAAANQADCgIIAgAAAA==.Vivifirex:BAAANQADCgEIAQAAAA==.',
Vu='Vunks:BAAANQAECgMIAwAAAA==.',
['Vò']='Vòxs:BAAANQAECgEIAQAAAA==.',
Wa='Wako:BAAANQAECgQIDQAAAA==.Warlôck:BAAANQADCgYICwAAAA==.Watdafoxsay:BAAANQADCggIFwAAAA==.',
Wh='Whitersoul:BAABNQAECoEnAAMHAAcJQR8bAwBvAgAHAAcJQR8bAwBvAgAIAAMJHASEEQGJAAAAAA==.',
Wi='Wiitchkiing:BAAANQADCggIDAAAAA==.Wiserys:BAABNQAECoEZAAQJAAkJ8hifKAA/AgAJAAgJSxafKAA/AgAKAAQJaxDMCAAoAQALAAMJeg6ZNAC4AAAAAA==.',
Wm='Wmarcão:BAAANQAECgEIAQAAAA==.',
Wo='Wolfnwar:BAAANQAECgYICgAAAA==.',
Xe='Xenomorpho:BAAANQADCgEIAQAAAA==.Xexnetw:BAAANQAECgIIAgAAAA==.Xexnew:BAAANQAECgcIDgAAAA==.',
Xm='Xmari:BAAANQAECgQIDQAAAA==.',
Xn='Xnyx:BAAANQADCgEIAQAAAA==.',
Xo='Xots:BAAANQADCgIIAgAAAA==.',
Xt='Xtremetanke:BAAANQAECgEIAQAAAA==.',
Xx='Xxcantsidex:BAAANQAECgUIBgAAAA==.',
Ya='Yangyung:BAAANQADCggIDAAAAA==.Yannadcg:BAAANQAECgUIBgAAAA==.',
Yc='Ycantsideyx:BAAANQADCgYICgAAAA==.',
Ym='Ymperor:BAAANQADCgQIBAAAAA==.',
Yo='Yorickundyer:BAAANQADCgYICQAAAA==.Yorshka:BAAANQADCgYIBgAAAA==.',
Yr='Yrelistrasza:BAAANQAECgUICQAAAA==.',
Za='Zarolho:BAAANQADCgUIBgAAAA==.',
Ze='Zerdrax:BAAANQAECgIIAgAAAA==.',
Zi='Ziikiipala:BAAANQADCgIIAgAAAA==.',
['Ál']='Álucard:BAAANQAECgQIBQAAAA==.',
['Éy']='Éyga:BAAANQADCgUIDAAAAA==.',
['Ðw']='Ðwons:BAAANQADCgEIAQAAAA==.',
['Ök']='Ökamì:BAAANQADCgIIAgAAAA==.',
['Öx']='Öx:BAAANQAECgYIBgAAAA==.',
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
