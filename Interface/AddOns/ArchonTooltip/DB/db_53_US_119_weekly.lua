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

local lookup = {'Unknown-Unknown','Mage-Arcane','Warrior-Arms','Mage-Frost',}
local provider = {region='US',realm='Hellscream',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aarix:BAAANQAECgQIBQAAAA==.',
Ac='Achmed:BAAANQADCgYIDQAAAA==.',
Ad='Addÿ:BAAANQAECgMIAwAAAA==.',
Ae='Aelasong:BAAANQAECgcIDwABNQADCgUIBQABAAAAAA==.Aelinessa:BAAANQADCggIDwAAAA==.',
Af='Afflíctd:BAAANQADCgcICAAAAA==.',
Al='Aldrîch:BAAANQAECgEIAQAAAA==.Allyra:BAAANQAECgQICAAAAA==.Allzora:BAAANQADCggIFAAAAA==.Aloki:BAAANQADCggICAAAAA==.Alorarose:BAAANQAECgEIAQAAAA==.',
Am='Amberness:BAAANQAECgYICwAAAA==.Ametrius:BAAANQADCgYICAAAAA==.Ampd:BAAANQADCgYIDAAAAA==.',
An='Anastassia:BAAANQAECgYICAAAAA==.André:BAAANQAECggIDwAAAA==.Anuke:BAAANQADCgYICgAAAA==.',
Ar='Arestoz:BAAANQAECgIIAgAAAA==.Arkhmonk:BAAANQAECgUICQAAAA==.Armonos:BAAANQAECgEIAQAAAA==.Arrowhoof:BAEANQADCggIDQAAAA==.Arthurian:BAAANQADCgEIAQAAAA==.',
As='Ashiri:BAAANQABCgMIBQAAAA==.Ashmage:BAAANQADCgcIEwAAAA==.Asterisk:BAAANQAECgQIBgAAAA==.Astromo:BAAANQABCgMIAwAAAA==.Asya:BAAANQADCggICAAAAA==.',
At='Attilathepun:BAAANQADCggICAAAAA==.',
Au='Auriêl:BAAANQADCgUIDQAAAA==.',
Ax='Axxium:BAAANQAECgcIDgAAAA==.',
Az='Azastra:BAAANQADCggIFQAAAA==.',
['Añ']='Aña:BAAANQAECgQIBAAAAA==.',
Ba='Babymonstter:BAAANQADCgEIAQAAAA==.Baelzharon:BAAANQAECgEIAQAAAA==.Baericade:BAAANQADCgMIAwABNQADCgYIBgABAAAAAA==.Bagelpanda:BAAANQADCgYICwAAAA==.Balgrim:BAAANQAECgQICAAAAA==.Bandicoot:BAAANQADCgYIDQAAAA==.Basalt:BAAANQADCgYICQAAAA==.Bastenwode:BAAANQADCgYICgAAAA==.Bawce:BAAANQADCgcIBwAAAA==.',
Bb='Bbye:BAAANQADCggIDQAAAA==.',
Be='Beanboi:BAAANQADCgIIAgAAAA==.Bebynoob:BAAANQAECgEIAQAAAA==.Becký:BAAANQAECgQIBAAAAA==.Beroan:BAAANQADCgYICQAAAA==.',
Bi='Bigcøøkie:BAAANQADCgUICwAAAA==.Bigolcrities:BAAANQADCgYICgAAAA==.Bigshaft:BAAANQADCgYICgAAAA==.Bigwannabe:BAAANQAECgQIBAAAAA==.',
Bl='Blackmagma:BAAANQADCggICAABNQAECgQIDQABAAAAAA==.Bloodbunny:BAAANQADCgYICgAAAA==.',
Bo='Bootscoots:BAAANQAECgUIBwAAAA==.Bornite:BAAANQADCgUIBQAAAA==.Bowme:BAAANQADCgMIAwAAAA==.',
Br='Braedae:BAAANQADCggICAAAAA==.Brickaton:BAAANQADCgcIDwAAAA==.Brocknor:BAAANQAECgQIBQAAAA==.Broodling:BAAANQABCgEIAQAAAA==.',
Bu='Butterdtoast:BAEANQAECgEIAQAAAA==.',
Bw='Bwansamdi:BAAANQADCgQICAAAAA==.',
Ca='Cabbresoa:BAAANQADCgcIEQAAAA==.Caboose:BAAANQAECgIIAgAAAA==.Cadbvucolta:BAAANQADCgUIBgAAAA==.Caledor:BAAANQAECggIBAAAAA==.Calindrel:BAAANQAECgUIBQAAAA==.Caliriya:BAAANQADCggIFAAAAA==.Candren:BAAANQAECgEIAQAAAA==.Caraway:BAAANQADCggIEwAAAA==.',
Ce='Celaela:BAAANQAECggIAgAAAA==.Celant:BAAANQADCgQIBgAAAA==.Celson:BAAANQADCggIDQAAAA==.Celticlore:BAAANQADCgMIAwAAAA==.Cerrvantes:BAAANQADCgcIDQAAAA==.',
Ch='Chernaboz:BAAANQAECgQIBgAAAA==.Chevelot:BAAANQADCgQIBgAAAA==.Chibbo:BAAANQAECgQIBAAAAA==.Chiblet:BAAANQAECgUIBQAAAA==.Chioma:BAAANQADCgcIDAABNQAECgQIBQABAAAAAA==.',
Ci='Ci:BAAANQADCgMIBgAAAA==.',
Cl='Cledwyn:BAAANQADCgMIAwAAAA==.Cloudsinger:BAAANQADCgYIEgAAAA==.',
Co='Codysseuz:BAAANQADCgQIBAAAAA==.Columbo:BAAANQADCgUIBQAAAA==.Combustdeez:BAAANQAECgYICQAAAA==.Convrge:BAAANQADCgYIBwAAAA==.Corenthos:BAAANQAECgUIBwAAAA==.Corên:BAAANQADCgUICQAAAA==.',
Cr='Crashed:BAAANQABCgUIBgAAAA==.Crazymoron:BAAANQAECgQIBQAAAA==.Creepndeath:BAAANQADCgIIAgAAAA==.Creselia:BAAANQADCgcIDgAAAA==.Crowley:BAAANQADCgYICwAAAA==.Crum:BAAANQADCgYIBgAAAA==.Crumdumpster:BAAANQAECgEIAQABNQADCgYIBgABAAAAAA==.Crèmefraîche:BAAANQAECgIIAgAAAA==.',
Cu='Cuddlerz:BAAANQAECgIIBgAAAA==.',
Cy='Cypherrellik:BAAANQAECgIIAgAAAA==.',
Da='Dagthunderer:BAAANQAECgEIAQAAAA==.Dakkenrahl:BAAANQADCgUIBQAAAA==.Dalatras:BAAANQADCgUIBQABNQAECgQICAABAAAAAA==.Dalistra:BAAANQADCgYICAABNQAECgQICAABAAAAAA==.Damogdem:BAAANQADCgYIBgAAAA==.Dangly:BAAANQAECgcICgAAAA==.Dantes:BAAANQABCgMIAwAAAA==.Dar:BAAANQADCgUICQAAAA==.Darkflame:BAAANQAECgQIBQAAAA==.Darklûrker:BAAANQAECgIIAgAAAA==.Darksidedbro:BAAANQADCgUIBQAAAA==.Darkzelda:BAAANQADCggICAAAAA==.Dayve:BAAANQAECgQIBQAAAA==.',
Dc='Dcpt:BAAANQADCgYICwAAAA==.',
De='Deadgeinside:BAAANQADCgQIBAAAAA==.Deadgnome:BAAANQADCgQIBAABNQADCggIEAABAAAAAA==.Deathgimbo:BAAANQAECgUIBQAAAA==.Deathstomper:BAAANQAECgUIBwAAAA==.Demondono:BAAANQAECgQIBQAAAA==.Devomo:BAAANQAECgIIAgAAAA==.Deyedora:BAAANQADCggIDwAAAA==.Dezax:BAAANQAECgUIBwAAAA==.',
Di='Diaboli:BAAANQADCgQICAAAAA==.Dinohunter:BAAANQAECgYIBwAAAA==.',
Dj='Djdiddles:BAAANQADCggIEgAAAA==.',
Do='Dorimane:BAAANQAECgMIAwAAAQ==.Dorlock:BAAANQAECgQIBQAAAA==.',
Dr='Drais:BAAANQADCgIIBQABNQADCgQIBgABAAAAAA==.Drdukesilver:BAAANQADCgQIBAAAAA==.Dreadpanda:BAAANQAECgUICQAAAA==.Dredwarrior:BAAANQADCgEIAQAAAA==.Drprodigy:BAAANQAECgUICQAAAA==.',
Dy='Dybuck:BAAANQABCgYIBgAAAA==.Dyrcyn:BAAANQAECgMIAwAAAA==.',
['Dà']='Dànger:BAAANQAECggICAAAAA==.',
Ed='Edroh:BAAANQAECgEIAQAAAA==.',
Ei='Eidur:BAAANQAECgQIBQAAAA==.Eightohfive:BAAANQADCgUIBwAAAA==.',
Ek='Ekøh:BAAANQADCgQICAAAAA==.',
El='Elemefayoh:BAAANQAECgQIBQAAAA==.Elementlo:BAAANQAECgYICgABNQABCgIIAgABAAAAAA==.Elsafromtemu:BAAANQAECgQIBwAAAA==.Elspeth:BAAANQAECgQIBQAAAA==.',
Em='Emagonasooth:BAAANQAECgYIDQAAAA==.Emerey:BAAANQADCggIDAAAAA==.',
En='Endknightt:BAAANQADCggIDgAAAA==.Enflamee:BAAANQADCgUIBQAAAA==.Enma:BAAANQADCgMIBAAAAA==.',
Ep='Ephriia:BAAANQADCgYIBgAAAA==.',
Er='Erikprince:BAAANQAECgEIAgAAAA==.Erso:BAAANQADCgYICwAAAA==.',
Et='Eternalpaín:BAAANQAECgYIDgAAAA==.',
Ev='Evagria:BAAANQADCgYIBgAAAA==.',
Fa='Fal:BAAANQADCggICgAAAA==.Falcyon:BAAANQADCgIIAgAAAA==.Falroot:BAAANQAECgQIBQAAAA==.',
Fe='Feliché:BAAANQADCgYIDAABNQAECgYICgABAAAAAA==.Fevirin:BAAANQADCgYIBgAAAA==.',
Fi='Firefawkes:BAAANQADCgcIBwAAAA==.Fistbump:BAAANQAECgIIAwAAAA==.',
Fl='Fletchling:BAAANQAECgQIBAAAAA==.Flizrak:BAAANQADCggIEAABNQAECgkJGQACAH0cAA==.',
Fo='Footsteps:BAAANQADCgcIEQAAAA==.',
Fr='Freefallen:BAAANQADCgMIAwAAAA==.Frostclot:BAAANQAECggIEwAAAA==.Frostsalad:BAAANQAECgEIAQAAAA==.Frozoned:BAAANQAECgMIAwABNQAFFAEIAQABAAAAAA==.',
Fu='Fulta:BAAANQAECgQIBgAAAA==.',
['Fø']='Føxhound:BAAANQADCgUIBQAAAA==.',
Ga='Garadin:BAAANQAECgIIAgAAAA==.Garwa:BAAANQAECgUICQAAAA==.',
Ge='Geniver:BAAANQADCgYICgAAAA==.Gerla:BAAANQAECgMIAwAAAA==.',
Gi='Gigas:BAAANQAECgIIAgAAAA==.Gilgameshh:BAAANQAECgMIBAAAAA==.Girthbrooks:BAAANQAECgQIBQAAAA==.',
Go='Gomory:BAAANQADCgYICgAAAA==.Gondark:BAAANQADCgYICgAAAA==.Gorgrim:BAAANQAECgEIAQAAAA==.Gorpse:BAAANQADCgcIDAAAAA==.',
Gr='Gretchen:BAAANQAECgQIBAABNQAECgcIDgABAAAAAA==.Greyley:BAAANQADCgUIBQABNQABCgIIAgABAAAAAQ==.Greywolf:BAAANQAECgUICQAAAA==.',
Ha='Harrow:BAAANQADCggIEwAAAA==.Haxx:BAAANQAECgQIBQAAAA==.',
He='Hearge:BAAANQAECgYICQAAAA==.Hellhawk:BAAANQADCgYICQAAAA==.Hevydevy:BAAANQAECgIIAgAAAA==.Hexhain:BAAANQAECgQIBQAAAA==.',
Ho='Hockay:BAAANQAECgQICQAAAA==.Holygun:BAAANQAECgYIBwAAAA==.Holyshiets:BAAANQADCgUIBQAAAA==.Holyshiza:BAAANQAECgQIBAAAAA==.Holystan:BAAANQADCgIIAwAAAA==.Hondoe:BAAANQAECgQIBgAAAA==.',
Ht='Htownhots:BAAANQADCgYIBgABNQADCgYIDQABAAAAAA==.Htownshaman:BAAANQADCgYIDQAAAA==.',
Hu='Humblepotato:BAAANQADCgEIAgAAAA==.Huntfromhell:BAAANQAECgQIBQAAAA==.',
Ic='Iceagaint:BAAANQADCgQIBQAAAA==.',
Id='Idonttank:BAAANQADCgcICwAAAA==.',
Il='Illio:BAAANQADCggIEQAAAA==.',
Im='Imarea:BAAANQAECgEIAQAAAA==.Impirious:BAAANQAECgUIBwAAAA==.Imptard:BAAANQADCgIIAgABNQAECgUIBwABAAAAAA==.Imyx:BAAANQADCggIFQAAAA==.',
In='Infamuspikel:BAAANQAECgUIBQAAAA==.Infel:BAAANQAECgIIBAAAAA==.Inkkish:BAAANQAECgIIAgAAAA==.Innovates:BAAANQAECgcICgAAAA==.Intervene:BAAANQADCgYICwABNQAECgYIDgABAAAAAA==.Invictus:BAAANQAECgIIBAAAAA==.',
Ja='Jackjr:BAAANQADCgQIBgAAAA==.Jadea:BAAANQADCgUIBQAAAA==.Jalim:BAAANQADCgcIBwAAAA==.Jamesy:BAAANQADCgQIBAABNQAFFAEIAQABAAAAAA==.Jandoar:BAAANQADCggIFAAAAA==.Jarlen:BAAANQADCgEIAQAAAA==.Jaylea:BAAANQAECgUICQAAAA==.Jaynee:BAAANQABCgMIBAAAAA==.',
Je='Jegallidin:BAAANQADCgEIAQAAAA==.Jetpilot:BAAANQADCggIFAAAAA==.Jeypi:BAAANQADCgYIBgAAAA==.',
Ji='Jiq:BAAANQADCggIEAAAAA==.',
Jo='Johli:BAAANQADCggICAAAAA==.',
Ju='Junesong:BAAANQAECgQIBQAAAA==.',
Ka='Kabilos:BAAANQADCgYICAAAAA==.Kalesmora:BAAANQAECgQIBQAAAA==.Kamikaze:BAAANQADCggIEQAAAA==.Karlov:BAAANQAECgQIAwAAAA==.Karthis:BAAANQADCggIDAAAAA==.',
Ke='Keanah:BAAANQAECgQIBAAAAA==.',
Kh='Kheims:BAAANQADCggIBwAAAA==.Khrom:BAAANQADCgIIAgAAAA==.Khytoem:BAAANQADCggIEwAAAA==.',
Ki='Killduran:BAAANQAECgQIBQAAAA==.Kimaga:BAAANQADCgUICQABNQADCgcIDAABAAAAAA==.Kirasha:BAAANQADCgQIBAAAAA==.Kitom:BAAANQAECgIIAwAAAA==.Kiwia:BAAANQAECgIIAgAAAA==.',
Ko='Kolaniber:BAAANQABCgEIAQAAAA==.Korkrum:BAAANQADCgQIBAABNQADCgYICAABAAAAAA==.',
Kr='Kracked:BAAANQADCgMIAgAAAA==.Krank:BAAANQADCgUIDAAAAA==.Krellyroll:BAAANQADCggIDgABNQAECgEIAQABAAAAAA==.Krelthyr:BAAANQAECgEIAQAAAA==.Krumm:BAAANQAECgUIBwAAAA==.',
Ku='Kuhne:BAAANQADCgYIDQAAAA==.Kungfudrew:BAAANQADCggICAAAAA==.',
Ky='Kyber:BAAANQAECgIIAgAAAA==.Kyther:BAAANQAECgQIBwAAAA==.',
['Kñ']='Kñightboat:BAAANQADCggIFQAAAA==.',
La='Ladeiene:BAAANQADCggIFAAAAA==.Laelynd:BAAANQADCgYICgAAAA==.Laeritides:BAAANQADCgYICQAAAA==.Lastditch:BAAANQAECgMIAwAAAA==.Lateralas:BAAANQADCgYIDQAAAA==.',
Le='Leothedog:BAAANQAECgEIAQAAAA==.Lethas:BAAANQADCgMIAwAAAA==.Leukheimsia:BAAANQADCgUIBQABNQADCggIBwABAAAAAA==.',
Li='Liere:BAAANQADCgUICQAAAA==.Lightrising:BAAANQADCgcIBgAAAA==.Lilenalol:BAAANQADCgIIAgAAAA==.Lilfiorella:BAAANQADCgQIBAAAAA==.Lilmonstrman:BAAANQAECgUICQAAAA==.Liltree:BAAANQADCgUIBQAAAA==.Limbbiscuit:BAAANQAECgYIBwAAAA==.Listmonk:BAAANQAECgEIAQAAAA==.',
Ll='Llothae:BAAANQADCgYIBgAAAA==.',
Lo='Lonjick:BAAANQADCgIIAgAAAA==.Lots:BAAANQADCgYICwAAAA==.Loyalty:BAAANQAECgEIAgAAAA==.',
Lu='Lul:BAAANQAECgcIEQAAAA==.Luminar:BAAANQADCgUIBwAAAA==.Lunaaru:BAAANQADCgMIAwAAAA==.Luvrstriplet:BAAANQADCgYIBgAAAA==.',
['Lð']='Lðvergirl:BAAANQAECgMIAwAAAA==.',
Ma='Madcow:BAAANQADCggIEAAAAA==.Maelk:BAAANQADCgQIBQABNQADCgYICAABAAAAAA==.Magistella:BAAANQADCgUICwAAAA==.Maisrii:BAEANQADCgUICwAAAA==.Maivz:BAAANQAECgQIBQAAAA==.Malignantt:BAAANQAECgQIBQAAAA==.Mapletoast:BAAANQADCgQIBAAAAA==.Marthren:BAAANQADCgUICQAAAA==.Marzyna:BAAANQADCgEIAQABNQADCgUIDAABAAAAAA==.Maurphious:BAAANQADCgUICAAAAA==.',
Me='Melbee:BAAANQADCgcICwAAAA==.Melodrama:BAAANQAECgIIAgAAAA==.Metri:BAAANQABCgUIBwAAAA==.',
Mi='Michaeljrdan:BAAANQADCgQIBAAAAA==.Mikela:BAAANQAECgEIAQABNQAECgYICQABAAAAAA==.Milkee:BAAANQADCgEIAQAAAA==.Mirgaree:BAAANQAECgMIAwAAAA==.',
Mo='Monty:BAAANQADCgYIDQAAAA==.Moodswingz:BAAANQADCgIIAwAAAA==.',
Mu='Muffinz:BAAANQADCggIEAAAAA==.Multipass:BAAANQABCgEIAQAAAA==.',
My='Myau:BAAANQADCggIFgAAAA==.Mylou:BAAANQADCgcIEQAAAA==.Mynia:BAAANQAECgUIBwAAAA==.',
Na='Nano:BAAANQAECgMIAwAAAA==.Nazdreg:BAAANQAECgUICAAAAA==.',
Ne='Negan:BAAANQABCgUIBQAAAA==.Neotoldir:BAAANQAECgQIBQAAAA==.Nerfdisc:BAAANQADCgYIDQAAAA==.Nevershocked:BAAANQAECgQIBAAAAA==.',
Ni='Ninjaznpariz:BAAANQADCgQIBAAAAA==.',
No='Noblewrack:BAAANQADCgEIAQAAAA==.Nordie:BAAANQADCggICAAAAA==.Northik:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Nosredna:BAAANQAECgEIAQAAAA==.Nosrednàx:BAAANQADCgUIBQAAAA==.Novata:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Nu='Nuzz:BAABNQAECoEYAAIDAAkJwiV5AQDbAwADAAkJwiV5AQDbAwAAAA==.',
Ny='Nydav:BAAANQAECgQIBgAAAA==.',
Ob='Obalma:BAAANQAECgQIBwAAAA==.',
Od='Odwalla:BAAANQAECgUIBwAAAA==.',
Ol='Olmec:BAAANQAECgEIAQAAAA==.',
On='Onlydesert:BAAANQAECgYICQAAAA==.Onranui:BAAANQADCgEIAQAAAA==.',
Op='Optiks:BAAANQAECgEIAQAAAA==.',
Or='Orksauce:BAAANQAECgYIDgAAAA==.Orphella:BAAANQAECgEIAQAAAA==.',
Os='Osares:BAAANQAECgEIAQAAAA==.',
Ow='Owils:BAAANQADCgYIBgABNQAECgUIBwABAAAAAA==.',
Pa='Pallytree:BAAANQADCggIFQAAAA==.Papiblanco:BAAANQADCgIIAgABNQADCgYICgABAAAAAA==.',
Pe='Percepcions:BAAANQAECgEIAQAAAA==.Percksmash:BAAANQAECgUIAwAAAA==.Perkbane:BAAANQADCgMIAwABNQAECgUIAwABAAAAAA==.Perkyl:BAAANQADCgcIEgAAAA==.',
Ph='Phage:BAAANQADCggICAABNQAECgQIBwABAAAAAA==.Photophobia:BAAANQAECgcIEQAAAA==.',
Pi='Piezo:BAAANQADCgQIBgAAAA==.Pikevarr:BAAANQADCgYICAAAAA==.Pivy:BAAANQADCgYIBgABNQAECgIIAwABAAAAAA==.',
Pk='Pkrage:BAAANQAECgcIDQAAAA==.',
Pl='Plazlie:BAAANQAECgYICgAAAA==.Ploppstein:BAEANQAECgIIAgAAAA==.',
Po='Polyethylene:BAAANQAECgQIBQAAAA==.',
Pu='Punkpikachu:BAAANQADCgYICwAAAA==.',
Qk='Qkoira:BAAANQAECgIIBAAAAA==.',
Qu='Quanlain:BAAANQADCgYICAAAAA==.Quillathe:BAAANQAECgUIBQAAAA==.',
Ra='Raagh:BAAANQAECgQIBAAAAA==.Rancore:BAAANQAECgIIAgAAAA==.Rashdar:BAAANQAECgYICgAAAA==.Rasto:BAAANQADCgMIAwABNQADCggIDQABAAAAAA==.Rattpacck:BAAANQADCgUIBQAAAA==.Rattpack:BAAANQAECgMIAwAAAA==.Raves:BAAANQADCgcIBwAAAA==.',
Re='Regilz:BAAANQADCgMIAwAAAA==.',
Rh='Rhys:BAAANQADCgMIAwAAAA==.',
Ri='Ribeyye:BAAANQADCggIDwAAAA==.Rider:BAAANQAECgEIAQAAAA==.Rigormortiis:BAAANQAECgEIAQAAAA==.Rilde:BAAANQADCgUICAAAAA==.Rinjiabri:BAAANQADCgYIDQAAAA==.',
Ro='Robroy:BAAANQAECggIAQAAAA==.Robrøy:BAAANQADCggIEAAAAA==.Rokmage:BAAANQAECgMIAwAAAA==.Roseclaw:BAEANQADCgYICwABNQAECgYIBgABAAAAAA==.Roseclawed:BAEANQAECgYIBgAAAA==.Roxso:BAABNQAECoEZAAMCAAkJfRxAGwDzAgACAAkJexxAGwDzAgAEAAYJegwgCQArAQAAAA==.',
Ru='Rukaiz:BAAANQAECgQIBQAAAA==.',
['Rë']='Rëdmagma:BAAANQAECgQIDQAAAA==.',
['Rò']='Ròbroy:BAAANQAECgEIAQAAAA==.',
['Ró']='Rónan:BAAANQADCgUIBgAAAA==.',
['Rû']='Rûsh:BAAANQADCgYICAAAAA==.',
Sa='Sacrelicious:BAAANQADCggIFQAAAA==.Sagewynn:BAAANQADCggIFAAAAA==.Salfroc:BAAANQAECgUIBwAAAA==.Samhain:BAAANQAECgMIBQAAAA==.Sanasianana:BAAANQADCgUIBQABNQAFFAEIAQABAAAAAA==.Saplo:BAAANQADCgYICQAAAA==.Sarif:BAAANQADCggIEwAAAA==.Saxel:BAAANQADCggICAAAAA==.',
Sc='Schwarzenman:BAAANQADCgEIAQAAAA==.',
Se='Segio:BAAANQAECgEIAQAAAA==.Selcia:BAAANQADCgYICAAAAA==.Serenati:BAAANQADCgYIBgAAAA==.Seïya:BAAANQADCggIDgAAAA==.',
Sh='Shamawockee:BAAANQADCgIIAgABNQAECgUICQABAAAAAA==.Shango:BAAANQADCgUIBQAAAA==.Sharavia:BAAANQADCggICwAAAA==.Shasu:BAAANQADCgEIAQAAAA==.Shaundi:BAAANQADCgYIDQAAAA==.Shocktuah:BAAANQAECgUIBwAAAA==.Shonúff:BAAANQAECgQIBQAAAA==.Shotaru:BAAANQADCgYICwAAAA==.Shotpace:BAAANQADCgYIBwAAAA==.Showerhandle:BAAANQADCgMIAwAAAA==.Shui:BAAANQADCggIEgAAAA==.Shädöw:BAAANQADCgIIAgAAAA==.',
Si='Silmeria:BAAANQAECgEIAQAAAA==.Sinful:BAAANQAECgYICwAAAA==.',
Sk='Skalagrim:BAAANQADCgcIBwAAAA==.Skeptyk:BAAANQAECgQIBQAAAA==.Sko:BAEANQAECgQICQABNQADCgcICQABAAAAAA==.Skol:BAAANQAECgQIBgAAAA==.Skolivia:BAEANQADCgcICQAAAA==.',
Sm='Smiley:BAAANQAECgMIAwAAAA==.Smokeydabear:BAAANQADCgEIAQAAAA==.Smug:BAAANQAECgUICQAAAA==.',
Sn='Snapee:BAAANQADCgQIBAAAAA==.Sniffledoo:BAAANQAECgEIAQAAAA==.Snuwuf:BAAANQADCgUIBQAAAA==.',
So='Sockz:BAAANQAECgEIAQAAAA==.Soonmia:BAAANQABCgUIDAAAAA==.Sourfangs:BAAANQAECgYIDAAAAA==.Soxx:BAAANQADCgYICwABNQAECgQIBQABAAAAAA==.',
Sp='Spicypeño:BAAANQAECgYIEgAAAA==.Spicý:BAAANQAECgYIDAAAAA==.Splack:BAAANQAECgUICQAAAA==.Splithoofe:BAEANQADCgEIAQABNQADCggIDQABAAAAAA==.Sprawl:BAAANQAECgEIAQAAAA==.Sprawlher:BAAANQADCggIFAABNQAECgEIAQABAAAAAA==.',
Sq='Squrrlydan:BAAANQADCgcIBwAAAA==.',
St='Staint:BAAANQAECgQIBwAAAA==.Starnights:BAAANQADCgcICwAAAA==.Statman:BAAANQADCgYICQAAAA==.Steelbubble:BAAANQAECgQIBwAAAA==.Stella:BAAANQADCgYIBgAAAA==.Stengah:BAAANQAECgUIBwAAAA==.Stone:BAAANQABCgEIAgAAAA==.Strela:BAAANQAECgYICwAAAQ==.',
Su='Suraki:BAAANQAECgQIBQAAAA==.',
Sw='Swtblsphmy:BAAANQADCggIDwAAAA==.',
['Sä']='Säber:BAAANQADCgcIBwAAAA==.',
['Sè']='Sèd:BAAANQAECgYIDAAAAA==.Sèitheach:BAAANQADCgYIBgAAAA==.',
Ta='Tahrin:BAAANQAECgIIAgAAAA==.Talamon:BAAANQAECgQIBQAAAA==.Tandruid:BAAANQAECgYICgAAAA==.Tarasis:BAAANQADCgEIAQAAAA==.Tashi:BAAANQAECgQIBAAAAA==.Tasina:BAAANQADCgMIAwAAAA==.Taurenamos:BAAANQAECgQIBQAAAA==.Taynam:BAAANQADCgQIBQABNQAECgQIBgABAAAAAA==.',
Te='Tempëst:BAAANQADCgEIAQAAAA==.Tenchu:BAAANQAECgMIAwAAAA==.Tendra:BAAANQADCgMIAwAAAA==.Tenseven:BAAANQAECgMIBAAAAA==.',
Th='Thalorain:BAAANQADCgYICAAAAA==.Thark:BAAANQADCgIIAgABNQAECgQICAABAAAAAA==.Thatdruid:BAAANQABCgMIAwAAAA==.Thicknfluffy:BAAANQABCgEIAgAAAA==.Throwd:BAAANQAECgMIBQAAAA==.Thundah:BAAANQAECgEIAQAAAA==.Thurk:BAAANQAECgQICAAAAA==.',
Ti='Tideshunter:BAAANQAECgcIDwAAAA==.Tinytony:BAAANQAECgQIBAAAAA==.Tinyweakling:BAAANQABCgQICgABNQAECgQIBAABAAAAAA==.',
To='Toranis:BAAANQADCgQIBwAAAA==.Torrents:BAAANQAECgUIBwAAAA==.',
Tr='Triepas:BAAANQADCgcICAAAAA==.Trinytee:BAAANQAECgMIBgAAAA==.Trippytotem:BAAANQAECgUICAAAAA==.',
Ty='Tyriäel:BAAANQAECgUICQAAAA==.Tyrrible:BAAANQADCgYIBgAAAA==.',
Ug='Ugolino:BAAANQADCgEIAQAAAA==.',
Ul='Ulther:BAAANQADCgYICAAAAA==.',
Va='Vacare:BAAANQADCgYICAAAAA==.Valdyria:BAAANQADCgQIBAAAAA==.Valistar:BAAANQADCgUIDQAAAA==.Valkoienne:BAAANQADCgQIBQAAAA==.Varnashar:BAAANQADCgYIBgAAAA==.Vavictus:BAAANQADCgYICAAAAA==.',
Ve='Vedronorael:BAAANQADCgYIBgAAAA==.Veinos:BAAANQAECgUIBQAAAA==.Velanthia:BAAANQADCgcIBwAAAA==.Velora:BAAANQAECgIIAgAAAA==.Vengrath:BAAANQAECgQIBgAAAA==.Verderben:BAAANQADCgYICwAAAA==.Verind:BAAANQAFFAEIAQAAAA==.',
Vi='Vinhelsin:BAAANQADCgQIBAAAAA==.',
Vo='Voideater:BAAANQADCgEIAQAAAA==.Voron:BAAANQAECgQICgAAAA==.',
Vu='Vulperra:BAAANQAECgQIBQAAAA==.',
Wa='Walk:BAAANQADCgYIBgAAAA==.Waq:BAAANQAECgQIBAAAAA==.Waterwhip:BAAANQAECgQIBQAAAA==.',
We='Wemeo:BAAANQADCgcIDQAAAA==.Westfall:BAAANQAECgIIBQAAAA==.',
Wi='Willrun:BAAANQADCgYICgAAAA==.Wipeit:BAAANQADCgIIAgAAAA==.',
Wo='Wolfbayne:BAAANQAECgEIAQAAAA==.Wompeal:BAAANQADCggIDgAAAA==.Wonkwonk:BAAANQAECgEIAQAAAA==.Worth:BAAANQAECgQICAAAAA==.',
Wr='Wrukolas:BAAANQAECgMIAwAAAA==.',
Wy='Wystan:BAAANQAECgQIBgAAAA==.',
['Wè']='Wès:BAAANQADCgEIAQAAAA==.',
['Wé']='Wés:BAAANQAECgUIBwAAAA==.',
Xa='Xamsuciteey:BAAANQADCgUIBQAAAA==.Xanthe:BAAANQAECgMIAwAAAA==.Xavin:BAAANQADCgIIAgAAAA==.',
Xe='Xentow:BAAANQAECgQIBQAAAA==.',
Ya='Yamling:BAAANQADCgUIBwAAAA==.Yayaka:BAAANQADCgcIDQAAAA==.',
Yi='Yizdano:BAAANQAFFAIIBAAAAA==.',
Yu='Yukiina:BAAANQADCgYICAAAAA==.Yungbean:BAAANQADCgYICAAAAA==.',
['Yû']='Yûm:BAAANQADCggICgAAAA==.',
Za='Zaccheus:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.Zambora:BAAANQADCgcICgAAAA==.',
Ze='Zeebra:BAAANQADCgYIEQAAAA==.Zeesaw:BAAANQAECgMIAwAAAA==.Zenden:BAAANQADCgYICgAAAA==.Zeretrix:BAAANQAECgUICQAAAA==.Zerospace:BAAANQAECgUIBwAAAA==.',
Zl='Zlutar:BAAANQADCgUICgAAAA==.',
Zy='Zynos:BAAANQAECgIIBAAAAA==.Zynothrian:BAAANQADCgMIAwAAAA==.',
['Ça']='Çalindrel:BAAANQADCgUIBQAAAA==.',
['Üb']='Überhealz:BAAANQAECgYICgAAAA==.',
['ßö']='ßöw:BAAANQAECgUIBwAAAA==.',
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
