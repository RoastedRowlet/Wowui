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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Monk-Mistweaver','DeathKnight-Unholy','Paladin-Holy','Evoker-Preservation','DemonHunter-Devourer','DemonHunter-Havoc','DeathKnight-Blood','DeathKnight-Frost','Priest-Holy','Priest-Shadow','Druid-Guardian',}
local provider = {region='US',realm='Azgalor',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aaradh:BAAANQAECgUICQAAAA==.Aaradk:BAAANQAECgQIBQABNQAECgUICQABAAAAAA==.Aarahunt:BAAANQADCgEIAQABNQAECgUICQABAAAAAA==.',
Ab='Abaddondk:BAAANQAECgYIAgAAAA==.Abnaruk:BAAANQAECgEIAQAAAA==.',
Ac='Acez:BAAANQAECggIEAAAAA==.',
Ad='Addilynn:BAAANQADCgEIAQAAAA==.Adoriah:BAAANQADCgYICwAAAA==.Adsaw:BAAANQAECgMIAwAAAA==.',
Ae='Aelania:BAAANQADCggICQAAAA==.Aelunara:BAAANQAECgQIBwAAAA==.Aemoz:BAAANQADCgMIAwAAAA==.',
Af='Aftershocks:BAAANQAECgEIAQAAAA==.',
Ag='Agh:BAAANQADCgcIDQAAAA==.',
Ai='Ailric:BAAANQAECgEIAQAAAA==.',
Al='Alarakian:BAAANQADCgUICQAAAA==.Alexei:BAAANQAECgEIAQAAAA==.Aliakin:BAAANQAECgMIBAAAAA==.Alistarburns:BAAANQAECgYICgAAAA==.Alkhan:BAAANQADCggIDgABNQAECgYIDAABAAAAAA==.Alteredbeest:BAAANQADCgQIBAAAAA==.Altos:BAAANQAECgcIDAAAAA==.Alyssachik:BAAANQADCgUIBQAAAA==.',
Am='Amarxd:BAAANQAECggIDwAAAA==.Amdabear:BAAANQADCgcIDAAAAA==.',
An='Angerclaw:BAAANQADCggIFgAAAA==.Ankaramessi:BAAANQADCgQIBQAAAA==.',
Ar='Arakisa:BAAANQADCgMIAwAAAA==.Arcanemagik:BAAANQADCggIFAAAAA==.Arcanmage:BAAANQAECgQICAAAAA==.Arcanofrosty:BAAANQADCgYIBQAAAA==.Aresascends:BAAANQADCgUIBQAAAA==.Arinthe:BAAANQADCgQIBAAAAA==.',
At='Atalmon:BAAANQAECgIIAgAAAA==.',
Au='Aurochi:BAAANQADCgMIAwAAAA==.',
Av='Avastin:BAAANQADCgUIBgAAAA==.',
Aw='Awni:BAAANQAECgQIBgAAAA==.',
Ba='Bacon:BAAANQAECgMIAwAAAA==.Badonkadonkk:BAAANQABCgIIAgAAAA==.Bahbahr:BAAANQAECgYIBgAAAA==.Baknow:BAAANQADCgEIAQAAAA==.Bangbangji:BAAANQAECgMIBAABNQAECgcIEAABAAAAAA==.Bantum:BAAANQADCggICAAAAA==.Bartholas:BAAANQAECgEIAQAAAA==.Bazzoo:BAAANQAECgEIAgAAAA==.',
Be='Beastmodex:BAAANQAECgUIBgAAAA==.Beastyboo:BAAANQAECgYICgAAAA==.Benzos:BAAANQAECggIDwAAAA==.Bequin:BAAANQAECgEIAQAAAA==.Berrd:BAAANQAECgMIBAAAAA==.Bewbbs:BAAANQADCgcIBwAAAA==.',
Bh='Bhangbhang:BAAANQAECgYICAAAAA==.',
Bi='Biggerbits:BAAANQAECgEIAQAAAA==.Bigkrayze:BAAANQADCgcIEQABNQAECgQIBgABAAAAAA==.Bigpullz:BAAANQABCgEIAQAAAA==.',
Bj='Bjordom:BAAANQADCgYIBgAAAA==.',
Bl='Bluerose:BAAANQADCgcIDAAAAA==.Blurry:BAAANQAECgIIAgAAAA==.',
Br='Bradyswife:BAAANQADCgYIDQAAAA==.Brisketboy:BAAANQADCgQIBAAAAA==.Bro:BAAANQADCgcIEQAAAA==.Bronthos:BAAANQADCggICAAAAA==.',
Bu='Buffbutton:BAAANQADCgcIEgABNQAECgQIBgABAAAAAA==.Buffstallion:BAAANQADCggICAAAAA==.',
['Bï']='Bïllï:BAAANQAECgYICgAAAA==.',
Ca='Caerisma:BAAANQAECgQIBAAAAQ==.Caravaggio:BAAANQADCgQIBQAAAA==.Catawba:BAAANQADCgMIAwAAAA==.',
Ce='Cellica:BAAANQAECgQIBQAAAA==.Cerywen:BAAANQADCgIIAgAAAA==.',
Ch='Chadwik:BAAANQADCgQIBwAAAA==.Charbzenberg:BAAANQAECgIIAgAAAA==.Charisma:BAAANQADCgYICQABNQAECgQIBAABAAAAAQ==.Chungae:BAAANQABCgEIAQAAAA==.',
Ci='Ciomara:BAAANQADCgUIBgAAAA==.',
Cl='Cloax:BAAANQAECgQIBwAAAA==.',
Co='Cobblepot:BAAANQABCgQIAgAAAA==.Coconut:BAAANQADCgIIAgABNQADCgcIDgABAAAAAA==.Coinbrew:BAAANQADCgQIBAAAAA==.Comardrac:BAAANQADCgQIBAAAAA==.Coned:BAAANQADCgEIAQAAAA==.Coobin:BAAANQADCgQIBAAAAA==.Coobins:BAAANQABCgIIAgAAAA==.',
Cr='Cranberrie:BAAANQADCggICAAAAA==.Crapo:BAAANQADCggIEgAAAA==.Cryhavok:BAAANQAECgUICQAAAA==.',
Cu='Cussack:BAAANQAECgYICwAAAA==.',
Da='Dabubble:BAAANQADCgIIAgAAAA==.Dadaji:BAAANQADCgQIAQABNQAECgcIEAABAAAAAA==.Daghar:BAAANQAECgIIAwAAAA==.Dalisaan:BAAANQADCgMIAwAAAA==.Dalé:BAAANQADCggICwAAAA==.Danastan:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Darkgol:BAAANQADCggIDgABNQAECgQIBgABAAAAAA==.Davioon:BAAANQAECgEIAgAAAA==.Dayrb:BAAANQADCgUIBQAAAA==.',
De='Deadtalini:BAAANQAECgcIEAAAAA==.Deah:BAAANQADCgYIBgAAAA==.Deckerdramon:BAAANQAECgQIBQAAAA==.Demomachin:BAAANQAECgQIBAAAAA==.Demyze:BAAANQADCggICAAAAA==.Deucalyon:BAAANQADCggIDgAAAA==.Devilchildd:BAAANQADCgMIAwAAAA==.Devours:BAABNQAECoEYAAICAAkJMBwEBwAXAwACAAkJMBwEBwAXAwAAAA==.',
Di='Divo:BAAANQADCgEIAgAAAA==.Diâblö:BAABNQAECoEWAAIDAAkJoCYLAAAJBAADAAkJoCYLAAAJBAAAAA==.',
Do='Donmegah:BAAANQADCgcIEQAAAA==.Dotmoo:BAAANQADCgEIAQAAAA==.',
Dr='Dragibbay:BAAANQADCgUIBQAAAA==.Dragoncito:BAAANQADCgMIAwAAAA==.Draki:BAAANQADCgYIEAAAAA==.Droodums:BAAANQAECgEIAQAAAA==.Druidmon:BAAANQADCgYIBgAAAA==.',
Du='Duggo:BAAANQAECgEIAQAAAA==.Dutanu:BAAANQAECgEIAQAAAA==.',
Ei='Eibhlean:BAAANQAECgMIAwABNQADCggIFQABAAAAAA==.Eirrin:BAAANQAECgMIAwABNQAECgQICgABAAAAAA==.',
El='Elariin:BAAANQADCggIEwAAAA==.Elendira:BAAANQADCgYIBgAAAA==.Elleredreaux:BAAANQAECgIIAgAAAA==.',
Em='Emongar:BAAANQABCgEIAQAAAA==.',
En='Endomorphism:BAAANQADCggIDgABNQAFFAEIAQABAAAAAA==.',
Es='Estradiol:BAAANQADCgYICwAAAA==.',
Ex='Exiza:BAAANQAECgMIAwAAAA==.',
Ez='Ezmelora:BAAANQAECgQIBAAAAA==.',
Fa='Fableshoot:BAAANQADCgQIBAAAAA==.Falconlaugh:BAAANQAECgEIAQAAAA==.Fantasie:BAAANQADCgcICwABNQAECgUIBgABAAAAAA==.Fatherclutch:BAAANQADCgQIBgABNQADCgYICAABAAAAAA==.Fauxpawz:BAAANQADCgYICwAAAA==.Fayia:BAAANQAECgYICQAAAA==.',
Fe='Felwoof:BAAANQAECgYIBgAAAA==.Fentacide:BAAANQADCgMIAwAAAA==.',
Fi='Firewraith:BAAANQADCgUIBQAAAA==.',
Fl='Flarllek:BAAANQADCgQICwAAAA==.Flexxed:BAAANQAECgcIDwAAAA==.',
Fr='Frakkinfrik:BAAANQABCgIIAgAAAA==.Frikkinfrak:BAAANQABCgIIAgAAAA==.Friskie:BAAANQADCgQIBAABNQAECgUIBgABAAAAAA==.Fry:BAAANQAFFAEIAQAAAA==.',
Fu='Fubardruid:BAAANQADCgcICQAAAA==.Fuguestate:BAAANQAECgUIBQAAAA==.Furystrike:BAAANQAECgcIBwABNQAECggIGAAEAGQfAA==.',
Ga='Galenaa:BAAANQADCgUIBwAAAA==.Ganondrow:BAAANQAECgUIBQAAAA==.',
Ge='Gemelo:BAAANQAECgEIAQAAAA==.Geromul:BAAANQADCgYICgAAAA==.Gerrexs:BAAANQADCgYIDAAAAA==.',
Gi='Gibayy:BAAANQAECgEIAQAAAA==.Gibsonex:BAAANQADCgcIEAAAAA==.Gilliamm:BAAANQAECgYIDAAAAA==.',
Gl='Gleste:BAAANQADCgQIBQAAAA==.',
Go='Golath:BAAANQAECgQIBgAAAA==.Gonguker:BAAANQADCgIIAgAAAA==.Gonthielhunt:BAAANQADCgcIEgAAAA==.Gothbutta:BAAANQADCgQICAAAAA==.',
Gr='Grado:BAAANQADCgIIAgAAAA==.Graydeon:BAAANQADCgcICAAAAA==.Gregorian:BAAANQAECgQIBQAAAA==.Gremliin:BAAANQAECgYIDgAAAA==.Grigo:BAAANQAECgIIBAAAAA==.Grymni:BAAANQADCgYIBgAAAA==.',
Ha='Hammerbell:BAAANQADCggICAAAAA==.Havideeznuts:BAAANQADCggICwAAAA==.',
He='Healmeharder:BAAANQADCgEIAQAAAA==.Healthcare:BAAANQADCggIEwAAAA==.',
Hi='Hierba:BAAANQADCgYIBgAAAA==.Hilltop:BAAANQABCgEIAQAAAA==.Hippo:BAAANQAECgUIBQAAAA==.',
Ho='Holdor:BAAANQADCgEIAQAAAA==.Holdors:BAAANQADCgQIBAAAAA==.Holier:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.Holyfae:BAAANQADCgMIAwAAAA==.Holynoodle:BAAANQAECgEIAQABNQAECgQICQABAAAAAA==.',
Hy='Hymnbral:BAAANQAECgQIBAAAAA==.',
Ic='Icebergx:BAAANQADCgIIAwAAAA==.',
Il='Iliohae:BAAANQAECgQICwAAAA==.Illyssa:BAAANQADCgIIAgAAAA==.',
Im='Imcooleddown:BAAANQAECgQIBQAAAA==.Imptricity:BAAANQADCgQIBAAAAA==.',
In='Intaria:BAAANQAECgYIDgAAAA==.',
Is='Isomorphism:BAAANQADCgYIBgAAAA==.',
It='Itchystraws:BAAANQADCgQIBAAAAA==.',
Ja='Jackbeef:BAAANQAECgYICwAAAA==.Jadedhooves:BAAANQAECgQIBAAAAA==.Jaggedlilhun:BAAANQAECgQIBgAAAA==.Jaggedshammy:BAAANQADCggICAABNQAECgQIBgABAAAAAA==.Jagruk:BAAANQADCgIIAgAAAA==.Jareyk:BAAANQAECgQIBQAAAA==.Jarladorin:BAAANQADCgUIAwAAAA==.Jaxodk:BAAANQAECgUIDQAAAA==.',
Jb='Jbrealone:BAAANQADCgMIAwAAAA==.',
Je='Jedai:BAABNQAECoEXAAIFAAkJjhpxCwDZAgAFAAkJjhpxCwDZAgAAAA==.Jerrysix:BAAANQAECgMIBgAAAA==.',
Ju='Judadiah:BAAANQADCgYIDQAAAA==.Judo:BAAANQAECgUICQAAAA==.Justbeginner:BAAANQADCggIEAAAAA==.',
Jy='Jyloti:BAAANQADCgYICwAAAA==.',
['Jà']='Jàxx:BAAANQADCggIDgAAAA==.',
['Jå']='Jåggy:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.',
Ka='Kalrock:BAAANQAECgUIBQAAAA==.Kalrotten:BAAANQADCgcICgABNQAECgUIBQABAAAAAA==.Kancisa:BAAANQADCgQIBAAAAA==.Karkit:BAAANQADCgMIAwAAAA==.Katkot:BAAANQAECgEIAQAAAA==.Kayro:BAAANQADCgUICAAAAA==.',
Kh='Khagolith:BAAANQAECgQIBAAAAA==.',
Ki='Kioria:BAAANQADCgcIDQAAAA==.Kirishino:BAAANQADCggIDgAAAA==.',
Kk='Kkodabear:BAAANQADCggIDwAAAA==.',
Ko='Kobiter:BAAANQAECgIIAgABNQAECgYICQABAAAAAA==.Kobito:BAAANQAECgYICQAAAA==.Korvas:BAAANQABCgMIAQAAAA==.Koup:BAAANQAFFAEIAQAAAA==.Koupe:BAAANQAECgMIAwABNQAFFAEIAQABAAAAAA==.',
Kr='Kranx:BAAANQADCgUIBQAAAA==.Krayzebeef:BAAANQAECgQIBgAAAA==.Kriss:BAAANQADCgYIDgAAAA==.',
Ku='Kungfudk:BAAANQADCgQIBAAAAA==.Kupe:BAAANQADCgUIBQABNQAFFAEIAQABAAAAAA==.',
Ky='Kyewanda:BAAANQADCggIEgAAAA==.Kyusakuu:BAAANQAECgYICAAAAA==.',
La='Laanu:BAAANQADCgcIBwABNQAECgQIBgABAAAAAA==.Lahey:BAAANQAECgYICgAAAA==.Lakes:BAAANQAECgQIBgAAAA==.Lanuna:BAAANQAECgMIAwAAAA==.Lathara:BAAANQADCgcIEQAAAA==.Lavs:BAAANQAECgIIAgAAAA==.Laxkeeper:BAAANQADCgUIBwAAAA==.',
Le='Legostepper:BAAANQADCgMIAwAAAA==.Leronis:BAAANQAECgYICgAAAA==.Lexiah:BAAANQADCggIEwAAAA==.',
Li='Lilicyhot:BAAANQADCgcIBwAAAA==.',
Lo='Loamathor:BAAANQADCgUIBQAAAA==.Lorilyn:BAAANQAECgIIAgAAAA==.Lorthag:BAAANQAECgMIBAAAAA==.Lovebuz:BAAANQADCgYIBgAAAA==.Loverone:BAAANQADCgIIAgAAAA==.Loyalty:BAAANQADCgQIBQAAAA==.',
Lu='Lucciola:BAAANQADCgQIBAAAAA==.Lulbah:BAAANQADCgcICQAAAA==.Lunareclips:BAAANQADCgIIAgAAAA==.Lunarus:BAAANQAECgEIAQAAAA==.',
['Lì']='Lìfe:BAAANQAECgQIBgAAAA==.',
['Ló']='Lónnìe:BAAANQAECgEIAQAAAA==.',
Ma='Maelona:BAAANQADCggIFgAAAA==.Magrumok:BAAANQAECgQIBQAAAA==.Magthars:BAAANQADCgUIBwAAAA==.Magtide:BAAANQAECgMIAwAAAA==.Malväryx:BAAANQADCgcIGAAAAA==.Manbearpig:BAAANQAECgcIEAAAAA==.Manman:BAAANQAECgIIAgAAAA==.Marshes:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.Masshooter:BAAANQADCgYICQAAAA==.Mazirek:BAAANQADCgMIAwAAAA==.',
Mc='Mctigly:BAAANQADCggIFQAAAA==.',
Me='Megadefi:BAAANQAECgEIAQAAAA==.Megol:BAAANQADCggICAAAAA==.Melirraei:BAAANQADCgYIDAAAAA==.Melith:BAAANQADCgYIBgAAAA==.Melkiel:BAAANQAECgYICQAAAA==.Mentalmidget:BAAANQAECgUIBwAAAA==.Mesa:BAABNQAECoEjAAIGAAgJyCSzAQBoAwAGAAgJyCSzAQBoAwAAAA==.Methaen:BAAANQADCgEIAQAAAA==.',
Mi='Miclovin:BAAANQAECgUICQAAAA==.Microplastic:BAAANQAECgQIBgAAAA==.Midsized:BAAANQADCgIIAgAAAA==.Mikexz:BAAANQADCgEIAQAAAA==.Mikoani:BAAANQAECgQIBgAAAA==.Mirumahn:BAAANQADCgUIBwAAAA==.Misocursed:BAAANQADCgYIDQAAAA==.Misoquick:BAAANQADCgcICgAAAA==.Missogyny:BAAANQAECgUICAAAAA==.Mithunzi:BAAANQAECgQIBAAAAA==.',
Mo='Moadeab:BAAANQADCgUIBwAAAA==.Mogando:BAAANQADCgIIAgABNQAECgYICgABAAAAAA==.Mogrodeath:BAAANQADCgYIBgAAAA==.Mogrogarg:BAAANQAECgQIBgAAAA==.Mogrosham:BAAANQADCgYIBgAAAA==.Momimilkers:BAAANQADCgcIDAABNQAECgcIEgABAAAAAA==.Mommasha:BAAANQADCgQIBAAAAA==.Monkky:BAAANQADCgYIBgAAAA==.Mordin:BAAANQADCgcICwAAAA==.Morenthia:BAAANQADCggICAAAAA==.Moribelar:BAAANQADCgYICwAAAA==.Mormonhunter:BAAANQAECgEIAQAAAA==.Morriffic:BAAANQADCggICgABNQAECgQIBQABAAAAAA==.Morventhas:BAAANQADCgIIAgAAAA==.Mosshead:BAAANQADCgYIBwAAAA==.Mousethyr:BAAANQAECgMIAwAAAA==.',
Mu='Muahah:BAAANQAECgEIAgAAAA==.Munric:BAAANQAECgQIBQAAAA==.',
My='Myboycleetus:BAAANQADCgYIDAAAAA==.Mylocky:BAAANQAECgEIAQAAAA==.Mynon:BAAANQADCgIIAgAAAA==.',
['Mä']='Mäze:BAAANQADCgYIBgAAAA==.',
Na='Nachothings:BAABNQAECoEYAAMHAAkJWxa4DAClAgAHAAkJWxa4DAClAgAIAAEJVhmFMgBQAAAAAA==.',
Ne='Necrokat:BAAANQADCgUIBQAAAA==.Nephelia:BAAANQADCgYIBgAAAA==.',
Ni='Nightmist:BAAANQADCgYIDAAAAA==.Nihility:BAAANQAECgcICgAAAA==.Nirgand:BAAANQADCgcIDQABNQAECgYICgABAAAAAA==.Nitak:BAAANQAECggICAAAAA==.',
No='Noodlestang:BAAANQAECgQICQAAAA==.Nool:BAAANQADCgcICwAAAA==.Norgand:BAAANQAECgYICgAAAA==.Nosleep:BAAANQAECgYICgAAAA==.Notdumb:BAAANQADCgQIBwAAAA==.',
Nu='Nullify:BAAANQADCgUICQAAAA==.',
Ny='Nydeath:BAAANQADCgUIBgAAAA==.Nyduss:BAAANQAECgIIAgAAAA==.Nymphs:BAAANQADCgEIAQAAAA==.Nyraxys:BAAANQAECgEIAQAAAA==.Nyxpal:BAAANQAECgIIAgAAAQ==.',
Ob='Obalo:BAAANQADCgcICQAAAA==.Obrlord:BAAANQADCgYIDQAAAA==.',
Oc='Ocopoko:BAAANQADCgcIBwAAAA==.',
On='Onibushi:BAAANQAECgYIBgAAAA==.',
Oo='Oof:BAAANQADCggIEgAAAA==.',
Op='Ophinias:BAAANQADCgcICAAAAA==.Optimize:BAAANQAECggICwAAAA==.',
Or='Orastal:BAAANQAECgIIAgABNQAECgQIBwABAAAAAA==.Ordonoir:BAAANQAECgIIAgAAAA==.Oroki:BAAANQADCggIAgAAAA==.',
Pa='Palledized:BAAANQADCgcIBwAAAA==.Paloadin:BAAANQADCgQIBAAAAA==.Pandadander:BAAANQADCgYIBgABNQADCgYIDAABAAAAAA==.Pandalo:BAAANQADCgUICQAAAA==.Pandalock:BAAANQADCgcIBwAAAA==.Parasiite:BAAANQAECgYICQAAAA==.',
Pe='Peepocute:BAAANQAECgEIAQAAAA==.',
Ph='Phadenstar:BAAANQADCgQICAAAAA==.Phylus:BAAANQADCggICAAAAA==.Physiowar:BAAANQAECgIIAgAAAA==.',
Pi='Pickledeath:BAAANQAECgQIBQAAAA==.Pizzapuff:BAAANQADCgYICwAAAA==.',
Pl='Plaguemachin:BAAANQADCgMIAwAAAA==.',
Po='Ponchoe:BAAANQADCgQIBQAAAA==.Poobahdrag:BAAANQAECgYIDwAAAA==.Poundpup:BAAANQADCgcIBwAAAA==.',
Pr='Prell:BAAANQADCgYIBgAAAA==.Preservation:BAAANQAECgEIAQAAAA==.',
Pu='Pugi:BAAANQADCgEIAQAAAA==.',
Qt='Qtyy:BAAANQAECgIIAgAAAA==.',
Ra='Raawwrr:BAAANQADCgIIAgAAAA==.Rabbi:BAAANQADCgIIAQAAAA==.Racken:BAAANQAECgIIAwAAAA==.Ragehound:BAAANQADCgEIAQAAAA==.Rainhealz:BAAANQADCgIIAgAAAA==.Ranzor:BAAANQAECgMIBAAAAA==.Rashis:BAAANQAECgMIAwAAAA==.Rattpack:BAAANQAECgEIAQAAAA==.Raveyn:BAAANQAECgIIAgAAAA==.',
Re='Redjak:BAAANQABCgQIBQAAAA==.Regino:BAAANQAECgMIBQAAAA==.Rekieuwu:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Rekita:BAAANQAECgQIBQAAAA==.Retispagheti:BAAANQADCggICAAAAA==.Retnuh:BAAANQAECgQIBAAAAA==.Revivified:BAAANQADCgcIBwAAAA==.',
Rh='Rhibbons:BAAANQADCgEIAQAAAA==.Rhyneaux:BAAANQADCgEIAQAAAA==.',
Ro='Roderika:BAAANQADCgcIDgABNQAECggIEAABAAAAAA==.Rogsicle:BAAANQAECggIEAAAAA==.Roldin:BAAANQAECgEIAQAAAA==.Rolockrad:BAAANQAECgIIAgAAAA==.Romanflak:BAAANQADCgYIBgAAAA==.Roostr:BAAANQAECgQIBAAAAA==.Rord:BAAANQAECgQIBQAAAA==.Royjacked:BAAANQADCgYICgAAAA==.',
Ru='Rubberr:BAAANQAECgEIAQAAAA==.Rubbershank:BAAANQAECgIIAwAAAA==.Rufío:BAAANQAECgMIAwAAAA==.Rumblebee:BAAANQADCgIIAgAAAA==.Runicstrike:BAABNQAECoEYAAQEAAcJZB/QJQDLAQAEAAUJqCDQJQDLAQAJAAQJLxrlNAApAQAKAAQJFBdMGQAJAQAAAA==.',
['Rø']='Røøm:BAAANQADCgYIBgAAAA==.',
Sa='Sagalia:BAAANQADCgIIAgABNQAECggICAABAAAAAA==.Sahra:BAAANQAECgQICQAAAA==.Saraphina:BAAANQADCgYICwAAAA==.Sauruman:BAAANQADCgEIAQAAAA==.',
Se='Sellandre:BAAANQADCggIDQAAAA==.Seronja:BAAANQAECgEIAQAAAA==.Serpompom:BAAANQADCgUIBQAAAA==.',
Sh='Shazzai:BAAANQADCgYIBgAAAA==.Sherfight:BAAANQAECgUIBgAAAA==.Shielddaddy:BAAANQAECgEIAQAAAA==.Shieldsftl:BAAANQADCgIIAgAAAA==.Shiftycent:BAAANQADCgcIBgAAAA==.Shnyaga:BAABNQAECoEiAAMLAAgJlSE0BgAUAwALAAgJlSE0BgAUAwAMAAIJqhgYKQCrAAAAAA==.Shunkd:BAAANQADCgUIBwAAAA==.',
Si='Silithaine:BAAANQADCgUIBQAAAA==.Simpsforimps:BAAANQAECgEIAQAAAA==.Sizurp:BAAANQABCgIIAgAAAA==.',
Sj='Sjardags:BAAANQADCgIIAgAAAA==.',
Sk='Skinwalk:BAAANQAECgEIAQAAAA==.Skrai:BAAANQADCggIGAAAAA==.',
Sl='Sleew:BAAANQAECgUICAAAAA==.Slippydippy:BAAANQAECgEIAQAAAA==.',
Sm='Smokintrees:BAAANQADCgMIAwAAAA==.',
Sn='Sneakylizard:BAAANQADCgYICwAAAA==.Snocaps:BAAANQADCgYIBgAAAA==.',
So='Soggypringle:BAAANQADCgMIBAAAAA==.Solnath:BAAANQAECgYICQAAAA==.',
Sp='Specsdraco:BAAANQAECgcIDAAAAA==.Spewpuke:BAAANQAECgUICAAAAA==.Spicytomato:BAAANQAECgMIAwAAAA==.Spirtforge:BAAANQADCgQIBAAAAA==.',
St='Staci:BAAANQAECgEIAQAAAA==.Starfree:BAAANQAECgYICgAAAA==.Starstorm:BAAANQADCgQIBAABNQAECgUICAABAAAAAA==.Stgermain:BAAANQAECgUICwAAAA==.Stormlotus:BAAANQADCgUIBwAAAA==.Stormsorrow:BAAANQADCgEIAQAAAA==.Strikeanywer:BAAANQADCgYICAAAAA==.',
Su='Superstoned:BAAANQADCgIIAgAAAA==.Surudk:BAAANQADCgYICAAAAA==.',
Sy='Sylrana:BAAANQADCgcICgAAAA==.Sylri:BAAANQADCgYIBgAAAA==.',
Ta='Taktikil:BAAANQADCgQICAAAAA==.Talrad:BAAANQAECgMIAwAAAA==.Tazerxface:BAAANQAECgYICwAAAA==.',
Te='Tealgos:BAAANQAECgQICAAAAA==.',
Th='Thaiddous:BAAANQAECgIIAgAAAA==.Thanx:BAAANQADCgUIBgAAAA==.Thebeefchief:BAABNQAECoEWAAINAAkJwyDJAAB3AwANAAkJwyDJAAB3AwAAAA==.Thebigmon:BAAANQAECgUIBwAAAA==.Thedabara:BAAANQADCgMIAwAAAA==.Thedon:BAAANQADCgUIBQAAAA==.Therealnmula:BAAANQADCgUICgAAAA==.Thewhite:BAAANQAECgUICQAAAA==.Thorxx:BAAANQADCgUIBQAAAA==.Thrudheals:BAAANQAECgQICAAAAA==.Thugnastie:BAAANQAECgMIBAAAAA==.',
Ti='Tika:BAAANQAECgEIAQAAAA==.',
To='Toastyshamy:BAAANQAECgEIAQAAAA==.Tofrenm:BAAANQADCggIFAAAAA==.Togashi:BAAANQAECgUICgAAAA==.Topacio:BAAANQADCgYIBgAAAA==.Topnacho:BAAANQADCgEIAQABNQAECgkJGAAHAFsWAA==.Torskeprime:BAAANQADCgEIAQAAAA==.Totalpyro:BAAANQADCgcIEgAAAA==.Totesschnook:BAAANQADCgMIAwAAAA==.',
Tr='Tricep:BAAANQABCgQIBQAAAA==.Tripallie:BAAANQADCgQIBgAAAA==.Trishian:BAAANQADCgMIBAAAAA==.Trunkmuffin:BAAANQADCgMIAQAAAA==.Truthless:BAEANQAECgYIBgAAAA==.',
Tu='Tuckermax:BAAANQADCgYICgAAAA==.Tunks:BAAANQAECgUIBQAAAA==.Tusk:BAAANQAECgQIBAAAAA==.',
Ug='Uglyashell:BAAANQADCgQIBgAAAA==.',
Un='Unit:BAAANQAECgcICwAAAA==.',
Uv='Uva:BAAANQADCggIFAAAAA==.',
Va='Valanui:BAAANQADCgIIAgAAAA==.Valendara:BAAANQAECgQIBQAAAA==.Valsorin:BAAANQADCggIFQAAAA==.Valtaea:BAAANQAECgYIDAAAAA==.',
Ve='Velanthos:BAAANQABCgIIAgAAAA==.',
Vi='Vishas:BAAANQADCgMIAwAAAA==.Vixol:BAAANQADCgQIBAAAAA==.',
Vo='Voidheals:BAAANQADCgEIAQABNQADCgcIEQABAAAAAA==.Volairne:BAAANQADCgQIBwAAAA==.Voreah:BAAANQAECgEIAQAAAA==.',
Wa='Wafflxs:BAAANQAECgcIEwAAAA==.Walkingheals:BAAANQADCgIIAwAAAA==.Wanpisu:BAAANQAECgQIBgAAAA==.',
We='Wellfookthat:BAAANQAECgYICgAAAA==.Weolf:BAAANQABCgIIAQAAAA==.',
Wh='Whiteshadows:BAAANQAECgEIAQAAAA==.Whyvala:BAAANQADCgYIDQABNQABCgIIBAABAAAAAA==.',
Wi='Wiisp:BAAANQAECgIIAgAAAA==.',
Wo='Wolnney:BAAANQAECgUICgAAAA==.Wowimhealing:BAAANQADCgcIEAAAAA==.',
['Wâ']='Wâarseer:BAAANQADCgMIBQAAAA==.',
Xa='Xalatoes:BAAANQAFFAEIAQAAAA==.Xanathar:BAAANQADCgYICAAAAA==.Xandertheone:BAAANQADCgUIBQAAAA==.',
Xi='Xiaoyu:BAAANQAECgcIDwAAAA==.Xiren:BAAANQABCgIIAgAAAA==.',
Xr='Xraiz:BAAANQADCggIDgAAAA==.',
Xy='Xyne:BAAANQADCgIIAgAAAA==.',
Ya='Yakiwhack:BAAANQADCgEIAQAAAA==.',
Yo='Yogonine:BAAANQAECggIEwAAAA==.Yourboyblue:BAAANQADCgYICgAAAA==.',
Yv='Yverrius:BAAANQADCgMIBgAAAA==.',
Za='Zanydruid:BAAANQADCgQICAAAAA==.Zanza:BAAANQADCgcIEQAAAA==.Zarione:BAAANQADCgYIBgAAAA==.',
Ze='Zearyth:BAAANQADCgcIDQAAAA==.Zemus:BAAANQADCggICAAAAA==.',
Zh='Zhamazu:BAAANQADCgMIAwAAAA==.Zhygår:BAAANQAECgEIAQAAAA==.',
Zi='Ziberia:BAAANQADCgIIAgAAAA==.',
Zo='Zodin:BAAANQADCgMIBQABNQADCggIFgABAAAAAA==.Zombiez:BAAANQAECgUICAAAAA==.Zoryn:BAAANQADCgYICQABNQABCgMIAwABAAAAAA==.',
['Él']='Élowen:BAAANQADCgYIBgAAAA==.',
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
