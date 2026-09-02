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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='Hellscream',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aarix:BAAANQAECgEIAQAAAA==.',
Ac='Achmed:BAAANQADCgQIBwAAAA==.',
Ad='Addÿ:BAAANQADCgYICgAAAA==.',
Ae='Aelasong:BAAANQAECgYICAABNQADCgUIBQABAAAAAA==.Aelinessa:BAAANQADCgcIDQAAAA==.',
Af='Afflíctd:BAAANQADCgcICAAAAA==.',
Al='Aldrîch:BAAANQAECgEIAQAAAA==.Allyra:BAAANQAECgQIAwAAAA==.Allzora:BAAANQADCgcIDAAAAA==.Alorarose:BAAANQAECgEIAQAAAA==.',
Am='Amberness:BAAANQAECgQIBQAAAA==.Ametrius:BAAANQADCgYICAAAAA==.Ampd:BAAANQADCgYIBgAAAA==.',
An='Anastassia:BAAANQAECgIIAgAAAA==.Anuke:BAAANQADCgYIBwAAAA==.',
Ar='Arestoz:BAAANQAECgIIAgAAAA==.Arkhmonk:BAAANQAECgQIBAAAAA==.Armonos:BAAANQADCgcICAAAAA==.Arrowhoof:BAEANQADCgYICwAAAA==.Arthurian:BAAANQADCgEIAQAAAA==.',
As='Ash:BAAANQADCgYICgAAAA==.Ashiri:BAAANQABCgIIBAAAAA==.Ashmage:BAAANQADCgcIDQAAAA==.Asterisk:BAAANQAECgIIAgAAAA==.',
At='Attilathepun:BAAANQADCggICAAAAA==.',
Au='Auriêl:BAAANQADCgUICAAAAA==.',
Ax='Axxium:BAAANQAECgUIBwAAAA==.',
Az='Azastra:BAAANQADCgcIDQAAAA==.',
['Añ']='Aña:BAAANQADCgcIDAAAAA==.',
Ba='Babymonstter:BAAANQADCgEIAQAAAA==.Baelzharon:BAAANQADCgUIBQAAAA==.Baericade:BAAANQADCgMIAwAAAA==.Bagelpanda:BAAANQADCgQIBQAAAA==.Balgrim:BAAANQAECgQIBAAAAA==.Bandicoot:BAAANQADCgUICAAAAA==.Basalt:BAAANQADCgMIAwAAAA==.Bastenwode:BAAANQADCgUICQAAAA==.',
Bb='Bbye:BAAANQADCggIDQAAAA==.',
Be='Bebynoob:BAAANQADCgYICwAAAA==.Becký:BAAANQADCgYICgAAAA==.Beroan:BAAANQADCgMIAwAAAA==.',
Bi='Bigcøøkie:BAAANQADCgUICgAAAA==.Bigolcrities:BAAANQADCgYICgAAAA==.Bigshaft:BAAANQADCgUIBQAAAA==.Bigwannabe:BAAANQADCgcICwAAAA==.',
Bl='Bloodbunny:BAAANQADCgUICQAAAA==.',
Bo='Bootscoots:BAAANQAECgIIAgAAAA==.Bornite:BAAANQADCgUIBQAAAA==.',
Br='Brickaton:BAAANQADCgcIDAAAAA==.Brocknor:BAAANQAECgEIAQAAAA==.Broodling:BAAANQABCgEIAQAAAA==.',
Bu='Butterdtoast:BAEANQADCgcIDAAAAA==.',
Bw='Bwansamdi:BAAANQADCgQICAAAAA==.',
Ca='Cabbresoa:BAAANQADCgcICwAAAA==.Caboose:BAAANQADCggIDwAAAA==.Cadbvucolta:BAAANQADCgMIAwAAAA==.Caledor:BAAANQAECggIBAAAAA==.Calindrel:BAAANQAECgIIAgAAAA==.Caliriya:BAAANQADCggIDgAAAA==.Candren:BAAANQAECgEIAQAAAA==.Caraway:BAAANQADCgYICwAAAA==.',
Ce='Celaela:BAAANQAECggIAgAAAA==.Celant:BAAANQADCgQIBAAAAA==.Celson:BAAANQADCgQICAAAAA==.Celticlore:BAAANQADCgMIAwAAAA==.Cerrvantes:BAAANQADCgcICQAAAA==.',
Ch='Chernaboz:BAAANQAECgIIAgAAAA==.Chevelot:BAAANQADCgQIBgAAAA==.Chibbo:BAAANQAECgQIBAAAAA==.Chiblet:BAAANQADCggICAAAAA==.Chioma:BAAANQADCgcIDAABNQAECgEIAQABAAAAAA==.',
Ci='Ci:BAAANQADCgMIBgAAAA==.',
Cl='Cloudsinger:BAAANQADCgYIDAAAAA==.',
Co='Columbo:BAAANQADCgUIBQAAAA==.Combustdeez:BAAANQAECgQIBAAAAA==.Convrge:BAAANQADCgYIBgAAAA==.Corenthos:BAAANQAECgIIAgAAAA==.Corên:BAAANQADCgQIBAAAAA==.',
Cr='Crazymoron:BAAANQAECgEIAQAAAA==.Creepndeath:BAAANQADCgIIAgAAAA==.Creselia:BAAANQADCgcIBwAAAA==.Crowley:BAAANQADCgUIBQAAAA==.Crum:BAAANQADCgYIBgAAAA==.Crumdumpster:BAAANQADCgYICAABNQADCgYIBgABAAAAAA==.Crèmefraîche:BAAANQAECgIIAgAAAA==.',
Cu='Cuddlerz:BAAANQAECgIIBAAAAA==.',
Cy='Cypherrellik:BAAANQADCggICgAAAA==.',
Da='Dagthunderer:BAAANQADCgQIBAAAAA==.Dakkenrahl:BAAANQADCgQIBAAAAA==.Dalistra:BAAANQADCgYIBgABNQAECgQIAwABAAAAAA==.Dangly:BAAANQAECgIIAwAAAA==.Dar:BAAANQADCgUICQAAAA==.Darkflame:BAAANQAECgEIAQAAAA==.Darksidedbro:BAAANQADCgUIBQAAAA==.Dayve:BAAANQAECgEIAQAAAA==.',
Dc='Dcpt:BAAANQADCgQIBQAAAA==.',
De='Deadgeinside:BAAANQADCgQIBAAAAA==.Deadgnome:BAAANQADCgQIBAABNQADCggICAABAAAAAA==.Deathgimbo:BAAANQADCggICAAAAA==.Deathstomper:BAAANQAECgUIBgAAAA==.Demondono:BAAANQAECgEIAQAAAA==.Devomo:BAAANQADCgcICAAAAA==.Deyedora:BAAANQADCgcIDQAAAA==.Dezax:BAAANQAECgIIAgAAAA==.',
Di='Diaboli:BAAANQADCgQIBAAAAA==.Dinohunter:BAAANQAECgEIAQAAAA==.',
Dj='Djdiddles:BAAANQADCggICgAAAA==.',
Do='Dorimane:BAAANQADCggICgAAAQ==.Dorlock:BAAANQAECgEIAQAAAA==.',
Dr='Drdukesilver:BAAANQADCgQIBAAAAA==.Dreadpanda:BAAANQAECgQIBAAAAA==.Dredwarrior:BAAANQADCgEIAQAAAA==.Drprodigy:BAAANQAECgUIBQAAAA==.',
Dy='Dybuck:BAAANQABCgIIAgAAAA==.Dyrcyn:BAAANQADCggIDgAAAA==.',
['Dà']='Dànger:BAAANQADCggICAAAAA==.',
Ei='Eidur:BAAANQAECgEIAQAAAA==.Eightohfive:BAAANQADCgQIBAAAAA==.',
Ek='Ekøh:BAAANQADCgQICAAAAA==.',
El='Elemefayoh:BAAANQAECgEIAQAAAA==.Elementlo:BAAANQAECgQIBAABNQABCgIIAgABAAAAAA==.Elsafromtemu:BAAANQAECgMIAwAAAA==.Elspeth:BAAANQAECgEIAQAAAA==.',
Em='Emagonasooth:BAAANQAECgQIBwAAAA==.Emerey:BAAANQADCgQIBwAAAA==.',
En='Endknightt:BAAANQADCggIDgAAAA==.Enflamee:BAAANQADCgUIBQAAAA==.Enma:BAAANQADCgMIBAAAAA==.',
Ep='Ephriia:BAAANQADCgEIAQAAAA==.',
Er='Erikprince:BAAANQAECgEIAQAAAA==.Erso:BAAANQADCgMIBQAAAA==.',
Et='Eternalpaín:BAAANQAECgUICAAAAA==.',
Ev='Evagria:BAAANQADCgYIBgAAAA==.',
Fa='Fal:BAAANQADCgIIAgAAAA==.Falcyon:BAAANQADCgIIAgAAAA==.Falroot:BAAANQAECgEIAQAAAA==.',
Fe='Feliché:BAAANQADCgYIDAABNQAECgQIBAABAAAAAA==.Fevirin:BAAANQADCgYIBgAAAA==.',
Fi='Firefawkes:BAAANQADCgcIBwAAAA==.Fistbump:BAAANQADCgYIDAAAAA==.',
Fl='Fletchling:BAAANQADCggIDgAAAA==.Flizrak:BAAANQADCggIEAABNQAECggIDgABAAAAAA==.',
Fr='Freefallen:BAAANQADCgMIAwAAAA==.Frostclot:BAAANQAECgcICwAAAA==.Frostsalad:BAAANQADCgYIBgAAAA==.',
Fu='Fulta:BAAANQAECgIIAgAAAA==.',
['Fø']='Føxhound:BAAANQADCgUIBQAAAA==.',
Ga='Garadin:BAAANQADCgcIDAAAAA==.Garwa:BAAANQAECgQIBAAAAA==.',
Ge='Geniver:BAAANQADCgUICQAAAA==.Gerla:BAAANQADCggIDgAAAA==.',
Gi='Gigas:BAAANQADCggIDQAAAA==.Gilgameshh:BAAANQAECgEIAQAAAA==.Girthbrooks:BAAANQAECgEIAQAAAA==.',
Go='Gomory:BAAANQADCgUICQAAAA==.Gondark:BAAANQADCgIIAgAAAA==.Gorpse:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Gr='Gretchen:BAAANQAECgIIAgABNQAECgYIBwABAAAAAA==.Greywolf:BAAANQAECgQIBAAAAA==.',
Ha='Harrow:BAAANQADCgcIDAAAAA==.Haxx:BAAANQAECgEIAQAAAA==.',
He='Hearge:BAAANQAECgMIAwAAAA==.Hellhawk:BAAANQADCgMIAwAAAA==.Hevydevy:BAAANQADCgMIBAABNQADCgYICwABAAAAAA==.Hexhain:BAAANQAECgEIAQAAAA==.',
Ho='Hockay:BAAANQAECgQIBQAAAA==.Holygun:BAAANQAECgQIBAAAAA==.Holyshiets:BAAANQADCgUIBQAAAA==.Holyshiza:BAAANQADCgcIDQAAAA==.Holystan:BAAANQADCgIIAwAAAA==.Hondoe:BAAANQAECgIIAgAAAA==.',
Ht='Htownhots:BAAANQADCgYIBgABNQADCgYIBwABAAAAAA==.Htownshaman:BAAANQADCgYIBwAAAA==.',
Hu='Humblepotato:BAAANQADCgEIAQAAAA==.Huntfromhell:BAAANQAECgEIAQAAAA==.',
Ic='Iceagaint:BAAANQADCgQIBQAAAA==.',
Id='Idonttank:BAAANQADCgYIBgAAAA==.',
Il='Illio:BAAANQADCgUICQAAAA==.',
Im='Imarea:BAAANQADCggIDgAAAA==.Impirious:BAAANQAECgIIAgAAAA==.Imptard:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Imyx:BAAANQADCgcIDQAAAA==.',
In='Infel:BAAANQAECgIIAgAAAA==.Inkkish:BAAANQADCggIDgAAAA==.Innovates:BAAANQAECgMIAwAAAA==.Intervene:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.Invictus:BAAANQAECgIIAgAAAA==.',
Ja='Jackjr:BAAANQADCgMIAwAAAA==.Jadea:BAAANQADCgUIBQAAAA==.Jamesy:BAAANQADCgQIBAABNQAECgcICwABAAAAAA==.Jandoar:BAAANQADCgcIDAAAAA==.Jarlen:BAAANQADCgEIAQAAAA==.Jaylea:BAAANQAECgQIBAAAAA==.Jaynee:BAAANQABCgEIAQAAAA==.',
Je='Jegallidin:BAAANQADCgEIAQAAAA==.Jetpilot:BAAANQADCgcIDAAAAA==.',
Ji='Jiq:BAAANQADCgYICAAAAA==.',
Jo='Johli:BAAANQADCggICAAAAA==.',
Ka='Kabilos:BAAANQADCgYICAAAAA==.Kalesmora:BAAANQAECgEIAQAAAA==.Kamikaze:BAAANQADCgcICQAAAA==.Karlov:BAAANQAECgIIAgAAAA==.Karthis:BAAANQADCgQIBAAAAA==.',
Kh='Khrom:BAAANQADCgIIAgAAAA==.Khytoem:BAAANQADCggIDQAAAA==.',
Ki='Killduran:BAAANQAECgEIAQAAAA==.Kimaga:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Kirasha:BAAANQADCgUIBAAAAA==.Kitom:BAAANQAECgEIAQAAAA==.Kiwia:BAAANQAECgEIAQAAAA==.',
Ko='Kolaniber:BAAANQABCgEIAQAAAA==.Korkrum:BAAANQADCgQIBAABNQADCgUIAQABAAAAAA==.',
Kr='Kracked:BAAANQADCgMIAgAAAA==.Krank:BAAANQADCgUIBwAAAA==.Krellyroll:BAAANQADCggIDgAAAA==.Krumm:BAAANQAECgIIAgAAAA==.',
Ku='Kuhne:BAAANQADCgQIBwAAAA==.Kungfudrew:BAAANQADCggICAAAAA==.',
Ky='Kyber:BAAANQADCggIDAAAAA==.Kyther:BAAANQAECgMIAwAAAA==.',
['Kñ']='Kñightboat:BAAANQADCgcIDQAAAA==.',
La='Ladeiene:BAAANQADCgcIDAAAAA==.Laelynd:BAAANQADCgUICQAAAA==.Laeritides:BAAANQADCgMIAwAAAA==.Lateralas:BAAANQADCgQIBQAAAA==.',
Le='Leothedog:BAAANQADCgcICAAAAA==.Lethas:BAAANQADCgMIAwAAAA==.Leukheimsia:BAAANQADCgEIAQAAAA==.',
Li='Liere:BAAANQADCgMIBAAAAA==.Lightrising:BAAANQADCgcIBgAAAA==.Lilenalol:BAAANQADCgEIAQAAAA==.Lilfiorella:BAAANQADCgMIAwAAAA==.Lilmonstrman:BAAANQAECgQIBAAAAA==.Limbbiscuit:BAAANQAECgIIAgAAAA==.Listmonk:BAAANQAECgEIAQAAAA==.',
Lo='Lonjick:BAAANQADCgIIAgAAAA==.Lots:BAAANQADCgYICwAAAA==.Loyalty:BAAANQAECgEIAQAAAA==.',
Lu='Lul:BAAANQAECgYICgAAAA==.Luminar:BAAANQADCgMIAwAAAA==.',
['Lð']='Lðvergirl:BAAANQAECgEIAQAAAA==.',
Ma='Madcow:BAAANQADCgUICAAAAA==.Maelk:BAAANQADCgEIAQABNQADCgUIAQABAAAAAA==.Magistella:BAAANQADCgUICQAAAA==.Maisrii:BAEANQADCgUICwAAAA==.Maivz:BAAANQAECgEIAQAAAA==.Malignantt:BAAANQAECgEIAQAAAA==.Mapletoast:BAAANQADCgUIBAAAAA==.Marthren:BAAANQADCgUICQAAAA==.Marzyna:BAAANQABCgQIBAABNQADCgUIBwABAAAAAA==.Maurphious:BAAANQADCgQIBAAAAA==.',
Me='Melbee:BAAANQADCgcICwAAAA==.Melodrama:BAAANQADCggIDgAAAA==.Metri:BAAANQABCgIIAgAAAA==.',
Mi='Michaeljrdan:BAAANQADCgQIBAAAAA==.Milkee:BAAANQADCgEIAQAAAA==.Mirgaree:BAAANQADCggIDgAAAA==.',
Mo='Monty:BAAANQADCgQIBwAAAA==.Moodswingz:BAAANQADCgIIAwAAAA==.',
Mu='Muffinz:BAAANQADCggICAAAAA==.Multipass:BAAANQABCgEIAQAAAA==.',
My='Myau:BAAANQADCggIDgAAAA==.Mylou:BAAANQADCgcICwAAAA==.Mynia:BAAANQAECgIIAgAAAA==.',
Na='Nano:BAAANQADCggIDgAAAA==.Nazdreg:BAAANQAECgMIAwAAAA==.',
Ne='Neotoldir:BAAANQAECgEIAQAAAA==.Nerfdisc:BAAANQADCgYIBwAAAA==.Nevershocked:BAAANQADCggIDwAAAA==.',
No='Noblewrack:BAAANQADCgEIAQAAAA==.Northik:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Nosredna:BAAANQADCgEIAQAAAA==.Nosrednàx:BAAANQADCgUIBQAAAA==.Novata:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Nu='Nuzz:BAAANQAECgcIDQAAAA==.',
Ny='Nydav:BAAANQAECgIIAgAAAA==.',
Ob='Obalma:BAAANQAECgMIAwAAAA==.',
Od='Odwalla:BAAANQAECgMIAwAAAA==.',
Ol='Olmec:BAAANQAECgEIAQAAAA==.',
On='Onlydesert:BAAANQAECgIIAgAAAA==.Onranui:BAAANQADCgEIAQAAAA==.',
Op='Optiks:BAAANQADCgcIDAAAAA==.',
Or='Orksauce:BAAANQAECgQICAAAAA==.Orphella:BAAANQAECgEIAQAAAA==.',
Os='Osares:BAAANQADCgUIBQAAAA==.',
Ow='Owils:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Pa='Pallytree:BAAANQADCgcIDQAAAA==.',
Pe='Percepcions:BAAANQADCgUIBQAAAA==.Percksmash:BAAANQADCgcICgAAAA==.Perkyl:BAAANQADCgYICwAAAA==.',
Ph='Phage:BAAANQADCggICAAAAA==.Photophobia:BAAANQAECgcICgAAAA==.',
Pi='Piezo:BAAANQADCgQIBAAAAA==.Pikevarr:BAAANQADCgYICAAAAA==.',
Pk='Pkrage:BAAANQAECgYIBgAAAA==.',
Pl='Plazlie:BAAANQAECgMIBAAAAA==.Ploppstein:BAEANQAECgIIAgAAAA==.',
Po='Polyethylene:BAAANQAECgEIAQAAAA==.',
Pu='Punkpikachu:BAAANQADCgQIBQAAAA==.',
Qk='Qkoira:BAAANQAECgIIAgAAAA==.',
Qu='Quanlain:BAAANQADCgIIAgAAAA==.Quillathe:BAAANQADCggIDQAAAA==.',
Ra='Raagh:BAAANQAECgQIBAAAAA==.Rancore:BAAANQADCggIDgAAAA==.Rashdar:BAAANQAECgQIBAAAAA==.Rattpacck:BAAANQADCgEIAQAAAA==.Rattpack:BAAANQADCgcICgAAAA==.',
Re='Regilz:BAAANQADCgMIAwAAAA==.',
Rh='Rhys:BAAANQADCgMIAwAAAA==.',
Ri='Ribeyye:BAAANQADCgcIDQAAAA==.Rider:BAAANQAECgEIAQAAAA==.Rilde:BAAANQADCgQIBwAAAA==.Rinjiabri:BAAANQADCgQIBwAAAA==.',
Ro='Robrøy:BAAANQADCggIEAAAAA==.Rokmage:BAAANQADCgYICAAAAA==.Roku:BAAANQAECgEIAQABNQAECggIDwABAAAAAA==.Roseclaw:BAEANQADCgUIBQABNQADCgcICwABAAAAAA==.Roseclawed:BAEANQADCgcICwAAAA==.Roxso:BAAANQAECggIDgAAAA==.',
Ru='Rukaiz:BAAANQAECgEIAQAAAA==.',
['Rë']='Rëdmagma:BAAANQAECgQICgAAAA==.',
['Rò']='Ròbroy:BAAANQADCggICAAAAA==.',
['Ró']='Rónan:BAAANQADCgEIAQAAAA==.',
['Rû']='Rûsh:BAAANQADCgYICAAAAA==.',
Sa='Sacrelicious:BAAANQADCgcIDQAAAA==.Sagewynn:BAAANQADCgYIDAAAAA==.Salfroc:BAAANQAECgIIAgAAAA==.Samhain:BAAANQAECgIIAgAAAA==.Sanasianana:BAAANQADCgUIBQABNQAECgcICwABAAAAAA==.Saplo:BAAANQADCgMIAwAAAA==.Sarif:BAAANQADCgcICwAAAA==.',
Sc='Schwarzenman:BAAANQADCgEIAQAAAA==.',
Se='Segio:BAAANQAECgEIAQAAAA==.Selcia:BAAANQADCgYICAAAAA==.Seïya:BAAANQADCgYIBgAAAA==.',
Sh='Shango:BAAANQADCgUIBQAAAA==.Sharavia:BAAANQADCggICAAAAA==.Shasu:BAAANQADCgEIAQAAAA==.Shaundi:BAAANQADCgQIBwAAAA==.Shocktuah:BAAANQAECgIIAgAAAA==.Shonúff:BAAANQAECgEIAQAAAA==.Shotaru:BAAANQADCgUIBQAAAA==.Shotpace:BAAANQADCgYIBwAAAA==.Showerhandle:BAAANQADCgMIAwAAAA==.Shui:BAAANQADCgcICgAAAA==.Shädöw:BAAANQADCgIIAgAAAA==.',
Si='Silmeria:BAAANQADCgcIDAAAAA==.Sinful:BAAANQAECgQIBQAAAA==.',
Sk='Skalagrim:BAAANQADCgcIBwAAAA==.Skeptyk:BAAANQAECgEIAQAAAA==.Sko:BAEANQAECgQIBAABNQADCgUIBQABAAAAAA==.Skol:BAAANQAECgEIAgAAAA==.Skolivia:BAEANQADCgUIBQAAAA==.',
Sm='Smiley:BAAANQADCgIIAgAAAA==.Smokeydabear:BAAANQADCgEIAQAAAA==.Smug:BAAANQAECgQIBAAAAA==.',
Sn='Sniffledoo:BAAANQADCgYIBgAAAA==.Snuwuf:BAAANQADCgQIBAAAAA==.',
So='Sockz:BAAANQADCggICAAAAA==.Sourfangs:BAAANQAECgQIBgAAAA==.Soxx:BAAANQADCgQIBQABNQAECgEIAQABAAAAAA==.',
Sp='Spicypeño:BAAANQAECgYIDAABNQAFFAMIBAABAAAAAA==.Spicý:BAAANQAECgQIBgAAAA==.Splack:BAAANQAECgUIBQAAAA==.Splithoofe:BAEANQADCgEIAQABNQADCgYICwABAAAAAA==.Sprawl:BAAANQADCgcICAAAAA==.Sprawlher:BAAANQADCgcIDAABNQADCgcICAABAAAAAA==.',
Sq='Squrrlydan:BAAANQADCgYIBgAAAA==.',
St='Staint:BAAANQADCgcIBwABNQADCggICAABAAAAAA==.Starnights:BAAANQADCgcICwAAAA==.Statman:BAAANQADCgMIAwAAAA==.Steelbubble:BAAANQAECgMIBAAAAA==.Stella:BAAANQADCgYIBgAAAA==.Stengah:BAAANQAECgIIAgAAAA==.Strela:BAAANQAECgUIBQAAAQ==.',
Su='Suraki:BAAANQAECgEIAQAAAA==.',
Sw='Swtblsphmy:BAAANQADCggIDwAAAA==.',
['Sä']='Säber:BAAANQADCgcIBwAAAA==.',
['Sè']='Sèd:BAAANQAECgQIBQAAAA==.',
Ta='Tahrin:BAAANQADCgYIBgAAAA==.Talamon:BAAANQAECgEIAQAAAA==.Tandruid:BAAANQAECgQIBAAAAA==.Tarasis:BAAANQADCgEIAQAAAA==.Tashi:BAAANQADCggIDwAAAA==.Taurenamos:BAAANQAECgEIAQAAAA==.Taynam:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.',
Te='Tempëst:BAAANQADCgEIAQAAAA==.Tenchu:BAAANQADCgYIBgAAAA==.Tendra:BAAANQADCgMIAwAAAA==.Tenseven:BAAANQAECgEIAQAAAA==.',
Th='Thalorain:BAAANQADCgUIAQAAAA==.Thark:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Thatdruid:BAAANQABCgMIAwAAAA==.Throwd:BAAANQAECgIIAgAAAA==.Thundah:BAAANQAECgEIAQAAAA==.Thurk:BAAANQAECgQIBAAAAA==.',
Ti='Tideshunter:BAAANQAECgYICAAAAA==.Tinytony:BAAANQAECgQIBAAAAA==.Tinyweakling:BAAANQABCgQIBgABNQADCggIDgABAAAAAA==.',
To='Toranis:BAAANQADCgQIBwAAAA==.Torrents:BAAANQAECgIIAgAAAA==.',
Tr='Trinytee:BAAANQADCgYIDAAAAA==.Trippytotem:BAAANQAECgMIAwAAAA==.',
Ty='Tyriäel:BAAANQAECgQIBAAAAA==.',
Ug='Ugolino:BAAANQADCgEIAQAAAA==.',
Ul='Ulther:BAAANQADCgYICAAAAA==.',
Va='Vacare:BAAANQADCgYICAAAAA==.Valistar:BAAANQADCgQICAAAAA==.Valkoienne:BAAANQADCgEIAQAAAA==.Varnashar:BAAANQADCgYIBgAAAA==.Vavictus:BAAANQADCgYICAAAAA==.',
Ve='Vedronorael:BAAANQADCgYIBgAAAA==.Veinos:BAAANQADCggIAwAAAA==.Velora:BAAANQADCgQIBAAAAA==.Vengrath:BAAANQAECgIIAgAAAA==.Verderben:BAAANQADCgYICwAAAA==.Verind:BAAANQAECgcICwAAAA==.',
Vo='Voideater:BAAANQADCgEIAQAAAA==.Voron:BAAANQAECgMIBAAAAA==.',
Vu='Vulperra:BAAANQAECgIIAgAAAA==.',
Wa='Waq:BAAANQADCggIEAAAAA==.Waterwhip:BAAANQAECgQIBQAAAA==.',
We='Wemeo:BAAANQADCgYIBgAAAA==.Westfall:BAAANQAECgIIBAAAAA==.',
Wi='Willrun:BAAANQADCgYICgAAAA==.Wipeit:BAAANQADCgIIAgAAAA==.',
Wo='Wolfbayne:BAAANQADCgcICgAAAA==.Wompeal:BAAANQADCggIDgAAAA==.Wonkwonk:BAAANQADCgcICQAAAA==.Worth:BAAANQAECgQIBAAAAA==.',
Wr='Wrukolas:BAAANQAECgEIAQAAAA==.',
Wy='Wystan:BAAANQAECgIIAgAAAA==.',
['Wè']='Wès:BAAANQADCgEIAQAAAA==.',
['Wé']='Wés:BAAANQAECgIIAgAAAA==.',
Xa='Xanthe:BAAANQADCggIDgAAAA==.Xavin:BAAANQADCgIIAgAAAA==.',
Xe='Xentow:BAAANQAECgEIAQAAAA==.',
Ya='Yamling:BAAANQADCgMIAwAAAA==.Yayaka:BAAANQADCgcIBwAAAA==.',
Yi='Yizdano:BAAANQAFFAIIAgAAAA==.',
Yu='Yukiina:BAAANQADCgIIAgAAAA==.Yungbean:BAAANQADCgYIBgAAAA==.',
['Yû']='Yûm:BAAANQADCggICAAAAA==.',
Za='Zaccheus:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Zambora:BAAANQADCgcICgAAAA==.',
Ze='Zeebra:BAAANQADCgYICwAAAA==.Zeesaw:BAAANQADCggIDgAAAA==.Zenden:BAAANQADCgUICQAAAA==.Zeretrix:BAAANQAECgQIBAAAAA==.Zerospace:BAAANQAECgIIAgAAAA==.',
Zl='Zlutar:BAAANQADCgUICgAAAA==.',
Zy='Zynos:BAAANQAECgIIAgAAAA==.Zynothrian:BAAANQADCgMIAwAAAA==.',
['Ça']='Çalindrel:BAAANQADCgUIBQAAAA==.',
['Üb']='Überhealz:BAAANQAECgQIBAAAAA==.',
['ßö']='ßöw:BAAANQAECgIIAgAAAA==.',
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
