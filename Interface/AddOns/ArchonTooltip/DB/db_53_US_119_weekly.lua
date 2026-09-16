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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Shaman-Restoration','Mage-Arcane','DeathKnight-Blood','Hunter-Marksmanship','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Evoker-Devastation','Hunter-BeastMastery',}
local provider = {region='US',realm='Hellscream',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aarix:BAAANQAECgYICwAAAA==.',
Ac='Achmed:BAAANQADCgYIEwAAAA==.',
Ad='Addÿ:BAAANQAECgMIBAAAAA==.',
Ae='Aelasong:BAABNQAECoEWAAIBAAgJbiBUGADeAgABAAgJbiBUGADeAgABNQADCgUIBQACAAAAAA==.Aelinessa:BAAANQADCggIFwAAAA==.',
Af='Afflíctd:BAAANQADCgcICAAAAA==.',
Al='Aldrîch:BAAANQAECgEIAgAAAA==.Allyra:BAAANQAECgQICgAAAA==.Allzora:BAAANQADCggIFQAAAA==.Aloki:BAAANQADCggIEAAAAA==.Alorarose:BAAANQAECgEIAQAAAA==.',
Am='Amberness:BAAANQAECgYIEQAAAA==.Ametrius:BAAANQADCgYICAAAAA==.Ampd:BAAANQADCgYIEgAAAA==.',
An='Anastassia:BAAANQAECgcIDwAAAA==.André:BAAANQAECggIEAAAAA==.Anuke:BAAANQADCgcIEQAAAA==.',
Ar='Arestoz:BAAANQAECgMIAwAAAA==.Arkhmonk:BAAANQAECgcIDgAAAA==.Armonos:BAAANQAECgQIBQAAAA==.Arrowhoof:BAEANQADCggIDQAAAA==.Arthurian:BAAANQADCgEIAQAAAA==.Artémis:BAAANQADCgEIAgAAAA==.',
As='Ashiri:BAAANQABCgMIBQAAAA==.Ashmage:BAAANQAECgEIAQAAAA==.Asterisk:BAAANQAECgYIDAAAAA==.Astromo:BAAANQADCgIIAwAAAA==.Asya:BAAANQAECgEIAQAAAA==.',
At='Attilathepun:BAAANQADCggICAAAAA==.',
Au='Auriêl:BAAANQADCgYIEwAAAA==.',
Ax='Axxium:BAABNQAECoEZAAIDAAgJpR21FgCgAgADAAgJpR21FgCgAgAAAA==.',
Az='Azastra:BAAANQADCggIFQAAAA==.',
['Añ']='Aña:BAAANQAECgQICAAAAA==.Añarchist:BAAANQADCgEIAQABNQAECgQICAACAAAAAA==.',
Ba='Babymonstter:BAAANQADCgEIAQAAAA==.Baelzharon:BAAANQAECgMIBAAAAA==.Baericade:BAAANQADCgMIAwABNQADCgYIBgACAAAAAA==.Bagelpanda:BAAANQADCggIEAAAAA==.Balgrim:BAAANQAECgYICwAAAA==.Bandicoot:BAAANQADCgYIDQAAAA==.Barsch:BAAANQABCgYIBwAAAA==.Basalt:BAAANQAECgEIAQAAAA==.Bastenwode:BAAANQADCgcIEQAAAA==.Bawce:BAAANQADCgcIDgAAAA==.',
Bb='Bbye:BAAANQADCggIDQAAAA==.',
Be='Beanboi:BAAANQADCgIIAgAAAA==.Bebynoob:BAAANQAECgMIBQAAAA==.Becký:BAAANQAECgQICAAAAA==.Beroan:BAAANQAECgEIAQAAAA==.Bertrille:BAAANQADCgMIAwAAAA==.',
Bi='Bigcøøkie:BAAANQADCgUICwAAAA==.Bigolcrities:BAAANQADCgYICgAAAA==.Bigshaft:BAAANQADCgYICgABNQADCggICgACAAAAAA==.Bigwannabe:BAAANQAECgQICAAAAA==.',
Bl='Blackmagma:BAAANQADCggIDgABNQAECgQIDwACAAAAAA==.Blackpinkk:BAAANQAECgMIAwAAAA==.Blackppinkk:BAAANQAECgEIAQAAAA==.Bloodbunny:BAAANQADCgcIEQAAAA==.',
Bo='Boggartt:BAAANQAECgIIAgAAAA==.Bootscoots:BAAANQAECgYICAAAAA==.Bornite:BAAANQADCgUIBQAAAA==.Bowme:BAAANQADCgMIAwAAAA==.',
Br='Braedae:BAAANQADCggICQAAAA==.Brickaton:BAAANQAECgIIAgAAAA==.Brocknor:BAAANQAECgQICQAAAA==.Broodling:BAAANQABCgEIAQAAAA==.',
Bu='Butterdtoast:BAEANQAECgMIAwAAAA==.',
Bw='Bwansamdi:BAAANQADCgQICAAAAA==.',
Ca='Cabbresoa:BAAANQAECgEIAQAAAA==.Caboose:BAAANQAECgQIBgAAAA==.Cadbvucolta:BAAANQADCgUIBwAAAA==.Caledor:BAAANQAECggIDAAAAA==.Calindrel:BAAANQAECgYIBgAAAA==.Caliriya:BAAANQADCggIFAAAAA==.Candren:BAAANQAECgEIAQAAAA==.Caraway:BAAANQADCggIEwAAAA==.',
Ce='Celaela:BAAANQAECggIAgAAAA==.Celant:BAAANQADCgYIDAAAAA==.Celson:BAAANQADCggIDQAAAA==.Celticlore:BAAANQADCgcICgAAAA==.Cerrvantes:BAAANQADCgcIDgAAAA==.',
Ch='Chernaboz:BAAANQAECgUICwAAAA==.Chevelot:BAAANQADCgQIBgAAAA==.Chibbo:BAAANQAECgQIBAAAAA==.Chiblet:BAAANQAECgYICgAAAA==.Chioma:BAAANQADCgcIDAABNQAECgYICwACAAAAAA==.',
Ci='Ci:BAAANQADCgMIBgAAAA==.',
Cl='Cledwyn:BAAANQADCgMIAwAAAA==.Cloudsinger:BAAANQAECgcIBwAAAA==.',
Co='Codysseuz:BAAANQADCgQIBAAAAA==.Columbo:BAAANQADCgUIBQAAAA==.Combustdeez:BAAANQAECggIDwAAAA==.Convrge:BAAANQADCgYIBwAAAA==.Corenthos:BAAANQAECgYIDQAAAA==.Corên:BAAANQADCgYIDwAAAA==.',
Cr='Crashed:BAAANQABCgUIBgAAAA==.Crazymoron:BAAANQAECgQICAAAAA==.Creepndeath:BAAANQADCgcICAAAAA==.Creselia:BAAANQADCgcIDgAAAA==.Crowley:BAAANQADCgYICwAAAA==.Crum:BAAANQADCgYIBgAAAA==.Crumdumpster:BAAANQAECgMIAwABNQADCgYIBgACAAAAAA==.Crèmefraîche:BAAANQAECgQIBgAAAA==.',
Cu='Cuddlerz:BAAANQAECgQICgAAAA==.',
Cy='Cypherrellik:BAAANQAECgQIBgABNQADCgYIBgACAAAAAA==.',
Da='Dagthunderer:BAAANQAECgEIAgAAAA==.Dakkenrahl:BAAANQADCgUIBQAAAA==.Dalatras:BAAANQADCgYICAABNQAECgQICgACAAAAAA==.Dalistra:BAAANQAECgQIBAABNQAECgQICgACAAAAAA==.Dalweaver:BAAANQADCgUIBQABNQAECgQICgACAAAAAA==.Damogdem:BAAANQADCgYICAAAAA==.Dangly:BAAANQAECgcIEQAAAA==.Dantes:BAAANQABCgYICAAAAA==.Dar:BAAANQADCgcIEAAAAA==.Darkflame:BAAANQAECgQIBQAAAA==.Darklûrker:BAAANQAECgIIAgAAAA==.Darksidedbro:BAAANQADCgUIBQAAAA==.Darkzelda:BAAANQADCggICAAAAA==.Dayve:BAAANQAECgQICQAAAA==.',
Dc='Dcpt:BAAANQADCgYIEAAAAA==.',
De='Deadgeinside:BAAANQADCgQIBAAAAA==.Deadgenah:BAAANQADCgMIAwAAAA==.Deadgnome:BAAANQAECgEIAQABNQAECgMIAwACAAAAAA==.Deathgimbo:BAAANQAECggIDQAAAA==.Deathstomper:BAAANQAECgUICAAAAA==.Demondono:BAAANQAECgUICgAAAA==.Devomo:BAAANQAECgIIAgAAAA==.Deyedora:BAAANQADCggIFwAAAA==.Dezax:BAAANQAECgYIDQAAAA==.',
Di='Diaboli:BAAANQADCgQICAAAAA==.Dinohunter:BAAANQAECgYIBwAAAA==.',
Dj='Djdiddles:BAAANQAECgQIAwAAAA==.',
Do='Dorimane:BAAANQAECgQIBwAAAQ==.Dorlock:BAAANQAECgQICQAAAA==.',
Dr='Drais:BAAANQADCgIIBQABNQADCgQIBgACAAAAAA==.Drdukesilver:BAAANQADCgQIBAAAAA==.Dreadpanda:BAAANQAECgcIEgAAAA==.Dred:BAAANQADCgUIBgAAAA==.Dredwarrior:BAAANQADCgEIAQAAAA==.Drosmoke:BAAANQADCgMIAwAAAA==.Drprodigy:BAAANQAECgUICQAAAA==.',
Dy='Dybuck:BAAANQAECgMIAwAAAA==.Dyrcyn:BAAANQAECgMIAwAAAA==.',
['Dà']='Dànger:BAAANQAECggIEAAAAA==.',
Ed='Edroh:BAAANQAECgEIAQAAAA==.',
Ei='Eidur:BAAANQAECgYICwAAAA==.Eightohfive:BAAANQADCgUIBwAAAA==.',
Ek='Ekøh:BAAANQADCgQICAAAAA==.',
El='Elará:BAAANQADCgYIBgAAAA==.Elemane:BAAANQADCgEIAQABNQAECgQIBwACAAAAAQ==.Elemefayoh:BAAANQAECgQICQAAAA==.Elementlo:BAAANQAECgcIEQABNQABCgIIAgACAAAAAA==.Elsafromtemu:BAAANQAECgUICAAAAA==.Elspeth:BAAANQAECgQICQAAAA==.',
Em='Emagonasooth:BAAANQAECgcIDwAAAA==.Emerey:BAAANQADCggIEgAAAA==.',
En='Endknightt:BAAANQADCggIDgAAAA==.Enflamee:BAAANQADCgUIBQAAAA==.Enma:BAAANQADCgQIBQAAAA==.',
Ep='Ephriia:BAAANQADCgcICAAAAA==.',
Er='Erikprince:BAAANQAECgMIBQAAAA==.Erso:BAAANQADCgYIEQAAAA==.',
Et='Eternalpaín:BAABNQAECoEVAAIBAAcJ4hxfNAAyAgABAAcJ4hxfNAAyAgAAAA==.',
Ev='Evagria:BAAANQADCgYIBgAAAA==.Evanrude:BAAANQABCgYIBgAAAA==.',
Fa='Fal:BAAANQADCggIEgAAAA==.Falcyon:BAAANQADCgIIAgAAAA==.Falroot:BAAANQAECgYICwAAAA==.',
Fe='Feliché:BAAANQADCgYIDAABNQAECgcIDwACAAAAAA==.Fevirin:BAAANQAECgQIBAAAAA==.',
Fi='Firefawkes:BAAANQADCgcIBwAAAA==.Fistbump:BAAANQAECgYICQAAAA==.',
Fl='Fletchling:BAAANQAECgUICQAAAA==.Flizrak:BAAANQADCggIEAABNQAFFAUIBgAEAD4MAA==.',
Fo='Footsteps:BAAANQADCgcIEQAAAA==.',
Fr='Freefallen:BAAANQADCgMIAwAAAA==.Frostclot:BAABNQAECoEbAAIFAAgJuRo6FgB6AgAFAAgJuRo6FgB6AgAAAA==.Frostsalad:BAAANQAECgIIAgAAAA==.Frozoned:BAAANQAECggICwABNQAFFAEIAQACAAAAAA==.',
Fu='Fulta:BAAANQAECgQICgAAAA==.',
['Fø']='Føxhound:BAAANQADCgUIBQAAAA==.',
Ga='Garadin:BAAANQAECgIIAgAAAA==.Garnok:BAAANQADCgUIBQAAAA==.Garwa:BAAANQAECgYIDwAAAA==.',
Ge='Geniver:BAAANQADCgcIEQAAAA==.Gerla:BAAANQAECgQIBwAAAA==.',
Gi='Gigas:BAAANQAECgUIBwAAAA==.Gilgameshh:BAAANQAECgQICAAAAA==.Girthbrooks:BAAANQAECgYICwAAAA==.',
Go='Gomory:BAAANQADCgcIEQAAAA==.Gondark:BAAANQADCgcIEQAAAA==.Gorgrim:BAAANQAECgEIAQAAAA==.Gorpse:BAAANQADCgcIDgABNQAECgQIBwACAAAAAA==.',
Gr='Graverael:BAAANQADCgUIBQAAAA==.Gretchen:BAAANQAECgUICgABNQAECgkJGAAGAKsUAA==.Greyley:BAAANQAECgQIBAABNQABCgIIAgACAAAAAQ==.Greywolf:BAAANQAECgYIDgAAAA==.',
['Gä']='Gärry:BAAANQAECgIIAgAAAA==.',
Ha='Hanzoff:BAAANQADCgQIBAAAAA==.Harrow:BAAANQADCggIGwAAAA==.Haxx:BAAANQAECgQICQAAAA==.',
He='Healls:BAAANQADCgUIBQAAAA==.Hearge:BAAANQAECgYIDAAAAA==.Hellhawk:BAAANQAECgEIAQAAAA==.Hevydevy:BAAANQAECgMIBQABNQAECgQIBQACAAAAAA==.Hexhain:BAAANQAECgUICgAAAA==.',
Ho='Hockay:BAAANQAECgYIDwAAAA==.Holygun:BAAANQAECgcIDAAAAA==.Holyshiets:BAAANQADCgUIBQAAAA==.Holyshiza:BAAANQAECgQICAAAAA==.Holystan:BAAANQAECgEIAQAAAA==.Hondoe:BAAANQAECgUIBwAAAA==.',
Ht='Htownglaivez:BAAANQADCgYIBgABNQADCgcIDgACAAAAAA==.Htownhots:BAAANQADCgYIBgABNQADCgcIDgACAAAAAA==.Htownshaman:BAAANQADCgcIDgAAAA==.',
Hu='Humblepotato:BAAANQADCgEIAgAAAA==.Hungsten:BAAANQADCgQIBAABNQAECgcIEQACAAAAAA==.Huntfromhell:BAAANQAECgUICAAAAA==.',
Ic='Iceagaint:BAAANQADCgQIBQAAAA==.Icedpissfox:BAAANQADCgUIBQAAAA==.',
Id='Idonttank:BAAANQADCggIEgAAAA==.',
Il='Illio:BAAANQADCggIGQAAAA==.',
Im='Imarea:BAAANQAECgQIBQAAAA==.Impirious:BAAANQAECgYIDQAAAA==.Implumz:BAAANQADCgMIAwABNQAECgYIDQACAAAAAA==.Imptard:BAAANQADCgIIAgABNQAECgYIDQACAAAAAA==.Imyx:BAAANQADCggIFQAAAA==.',
In='Infamuspikel:BAAANQAECgYIBwAAAA==.Infel:BAAANQAECgIIBAAAAA==.Inkkish:BAAANQAECgIIBAAAAA==.Innovates:BAAANQAECgcIEQAAAA==.Interstellar:BAAANQAECgQIBAAAAA==.Intervene:BAAANQADCgYIEAABNQAECgcIFQABAOIcAA==.Invictus:BAAANQAECgYICgAAAA==.',
Is='Ist:BAAANQADCgEIAQAAAA==.',
Ja='Jackjr:BAAANQADCgQIBgAAAA==.Jadea:BAAANQADCgUIBQAAAA==.Jalim:BAAANQADCgcIBwAAAA==.Jamesy:BAAANQADCgQIBAABNQAFFAIIAgACAAAAAA==.Jandoar:BAAANQADCggIFAAAAA==.Jarlen:BAAANQADCgEIAQAAAA==.Jaylea:BAAANQAECgYIDgAAAA==.Jaynee:BAAANQABCgUIBgAAAA==.',
Je='Jegallidin:BAAANQADCgEIAQAAAA==.Jetpilot:BAAANQADCggIFAAAAA==.Jeypi:BAAANQADCgYIBgAAAA==.',
Ji='Jiq:BAAANQAECgIIAgAAAA==.',
Jo='Johli:BAAANQADCggICAAAAA==.',
Ju='Junesong:BAAANQAECgQICQAAAA==.Justwipeit:BAAANQADCggICAAAAA==.',
Ka='Kabilos:BAAANQADCgYICAAAAA==.Kalesmora:BAAANQAECgUICgAAAA==.Kamikaze:BAAANQADCggIEQAAAA==.Karlov:BAAANQAECgcICgAAAA==.Karthis:BAAANQADCggIDAAAAA==.Kazgrim:BAAANQADCgYICgAAAA==.',
Ke='Keanah:BAAANQAECgUICQAAAA==.Keynn:BAAANQADCgUIBQABNQAECgQICgACAAAAAA==.',
Kh='Kheims:BAAANQADCggICQAAAA==.Khrom:BAAANQADCgIIAgAAAA==.Khytoem:BAAANQADCggIGwAAAA==.',
Ki='Killduran:BAAANQAECgUICgAAAA==.Kimaga:BAAANQADCgUICQABNQAECgQIBwACAAAAAA==.Kindle:BAAANQADCgMIAwABNQAECgEIAQACAAAAAA==.Kirasha:BAAANQADCgQIBAAAAA==.Kitom:BAAANQAECgIIAwAAAA==.Kiwia:BAAANQAECgQIBgAAAA==.',
Ko='Kolaniber:BAAANQABCgEIAQAAAA==.Korkrum:BAAANQADCgYIBAABNQADCgYIDgACAAAAAA==.',
Kr='Kracked:BAAANQADCgMIAgAAAA==.Krank:BAAANQADCgUIDAABNQADCgcICAACAAAAAA==.Krellyroll:BAAANQADCggIDgABNQAECgQIBQACAAAAAA==.Krelthyr:BAAANQAECgQIBQAAAA==.Krumm:BAAANQAECgYIDQAAAA==.Kruul:BAAANQABCgQIBAAAAA==.',
Ku='Kuhne:BAAANQADCgYIEwAAAA==.Kungfudrew:BAAANQADCggICAAAAA==.',
Ky='Kyber:BAAANQAECgIIAgAAAA==.Kyther:BAAANQAECgQIBwAAAA==.',
['Kñ']='Kñightboat:BAAANQADCggIFQAAAA==.',
La='Ladeiene:BAAANQADCggIFAAAAA==.Laelwyn:BAAANQADCgcIBwAAAA==.Laelynd:BAAANQADCgYICgAAAA==.Laeritides:BAAANQADCgYICQABNQAECgEIAQACAAAAAA==.Laeritidesdk:BAAANQAECgEIAQAAAA==.Lastditch:BAAANQAECgMIAwAAAA==.Lateralas:BAAANQADCggIDwAAAA==.',
Le='Leothedog:BAAANQAECgQIBQAAAA==.Lethas:BAAANQADCgMIAwAAAA==.Leukheimsia:BAAANQADCgUIBQABNQADCggICQACAAAAAA==.',
Li='Liere:BAAANQADCgYICgAAAA==.Lightrising:BAAANQADCgcIBgAAAA==.Lilenalol:BAAANQADCgYICAAAAA==.Lilfiorella:BAAANQADCgUIBQAAAA==.Lilmonstrman:BAAANQAECgYIDgAAAA==.Liltree:BAAANQADCggIDQAAAA==.Limbbiscuit:BAAANQAECgcIDgAAAA==.Listmonk:BAAANQAECgEIAQAAAA==.',
Ll='Llothae:BAAANQAECgEIAQAAAA==.',
Lo='Lonjick:BAAANQADCgIIAgAAAA==.Lots:BAAANQADCgYIEQAAAA==.Loyalty:BAAANQAECgEIAgAAAA==.',
Lu='Lul:BAABNQAECoEcAAIHAAgJDCL0GAAEAwAHAAgJDCL0GAAEAwAAAA==.Luminar:BAAANQAECgEIAQAAAA==.Lunaaru:BAAANQADCgMIAwAAAA==.Luvrstriplet:BAAANQADCgYIDAAAAA==.',
['Lð']='Lðvergirl:BAAANQAECgQIBwAAAA==.',
Ma='Madcow:BAAANQAECgEIAQAAAA==.Maelk:BAAANQADCgQIBQABNQADCgYIDgACAAAAAA==.Magistella:BAAANQADCgUICwAAAA==.Maisrii:BAEANQADCgcIDQAAAA==.Maivz:BAAANQAECgYICwAAAA==.Malignantt:BAAANQAECgUICgAAAA==.Mapletoast:BAAANQADCgQIBAAAAA==.Marthren:BAAANQADCgUICQAAAA==.Marzyna:BAAANQADCgcICAAAAA==.Maurphious:BAAANQADCgcIDwAAAA==.',
Me='Mekaniker:BAAANQABCgQIAwAAAA==.Melbee:BAAANQAECgQIBAAAAA==.Melodrama:BAAANQAECgIIAgAAAA==.Metri:BAAANQABCgUIBwAAAA==.',
Mi='Michaeljrdan:BAAANQADCgQIBAAAAA==.Mikela:BAAANQAECgQIBQABNQAECgYIDQACAAAAAA==.Milkee:BAAANQADCgEIAQAAAA==.Mirgaree:BAAANQAECgQIBwAAAA==.',
Mo='Moarass:BAAANQAECgYIBgAAAA==.Monty:BAAANQADCgYIEwAAAA==.Moodswingz:BAAANQADCgIIAwAAAA==.Mordos:BAAANQADCgMIAwAAAA==.',
Mu='Muffinz:BAAANQAECgMIAwAAAA==.Multipass:BAAANQABCgEIAQAAAA==.',
My='Myau:BAAANQADCggIFgAAAA==.Mylou:BAAANQAECgEIAQAAAA==.Mynia:BAAANQAECgYIDQAAAA==.',
Na='Nano:BAAANQAECgQIBwAAAA==.Nazdreg:BAAANQAECgUIDAAAAA==.',
Ne='Negan:BAAANQABCgUIBQAAAA==.Neotoldir:BAAANQAECgQICQAAAA==.Nerfdisc:BAAANQADCgcIFAAAAA==.Nevershocked:BAAANQAECgQICAAAAA==.Nezziee:BAAANQADCgYIBgAAAA==.',
Ni='Ninjaznpariz:BAAANQADCgQIBAAAAA==.',
No='Noblewrack:BAAANQADCgEIAQAAAA==.Nordie:BAAANQADCggICAAAAA==.Northik:BAAANQADCgUIBQABNQAECgQIBwACAAAAAA==.Nosredna:BAAANQAECgEIAQAAAA==.Nosrednàx:BAAANQADCgUIBQAAAA==.Novata:BAAANQADCgUIBQABNQAECgIIAgACAAAAAA==.',
Nu='Nuzz:BAACNQAFFIEFAAIHAAQJSSLnBAChAQAHAAQJSSLnBAChAQA1AAQKgRoAAgcACQnCJQMEAL8DAAcACQnCJQMEAL8DAAAA.',
Ny='Nydav:BAAANQAECgQICgAAAA==.',
Ob='Obalma:BAAANQAECgUIDAAAAA==.',
Od='Odwalla:BAAANQAECggIDwAAAA==.',
Ol='Oleegar:BAAANQADCgEIAQAAAA==.Olmec:BAAANQAECgEIAgAAAA==.',
On='Onlydesert:BAAANQAECgYIDQAAAA==.Onranui:BAAANQADCgEIAQAAAA==.',
Op='Optiks:BAAANQAECgMIAwAAAA==.',
Or='Orksauce:BAABNQAECoEXAAMIAAcJURztGAC4AQAIAAUJHB3tGAC4AQAJAAIJUxoGNwCtAAAAAA==.Orphella:BAAANQAECgEIAQAAAA==.',
Os='Osares:BAAANQAECgMIBAAAAA==.',
Ou='Outtamanna:BAAANQADCgUIBQAAAA==.',
Ow='Owils:BAAANQADCgYIBgABNQAECgYIDQACAAAAAA==.',
Ox='Oxl:BAAANQADCgQIBAAAAA==.',
Pa='Pagophobia:BAAANQAECgMIAwAAAA==.Pallytree:BAAANQADCggIGwAAAA==.Papiblanco:BAAANQADCggICgAAAA==.',
Pe='Percepcions:BAAANQAECgEIAQAAAA==.Percksmash:BAAANQAECggIBAAAAA==.Perkyl:BAAANQADCggIGgAAAA==.',
Ph='Phage:BAAANQADCggICAABNQAECgQICwACAAAAAA==.Photophobia:BAABNQAECoEYAAIKAAgJ8B/ACQDqAgAKAAgJ8B/ACQDqAgAAAA==.',
Pi='Piezo:BAAANQADCgQIBgAAAA==.Pikevarr:BAAANQADCgYICAAAAA==.Pivy:BAAANQADCgYIBgABNQAECgYICQACAAAAAA==.',
Pk='Pkrage:BAAANQAECgcIEgAAAA==.',
Pl='Plazlie:BAAANQAECgcIEAAAAA==.Ploppstein:BAEANQAECgQIBgAAAA==.',
Po='Polyethylene:BAAANQAECgQIBQAAAA==.Poucastranca:BAABNQAECoEpAAMLAAgJ/iQ5DQD4AgALAAcJpyQ5DQD4AgAMAAMJuSSBHgBHAQAAAA==.',
Pu='Punkpikachu:BAAANQADCgYIEAAAAA==.',
Qk='Qkoira:BAAANQAECgQIBwAAAA==.',
Qu='Quanlain:BAAANQAECgEIAQAAAA==.Quillathe:BAAANQAECgYICwAAAA==.',
Ra='Raagh:BAAANQAECgQIBAAAAA==.Rancore:BAAANQAECgIIAgAAAA==.Rashdar:BAAANQAECgcIEQAAAA==.Rasto:BAAANQADCgYICQABNQAECgQIBAACAAAAAA==.Rattpacck:BAAANQADCgUIBgAAAA==.Rattpack:BAAANQAECgQIBgAAAA==.Raves:BAAANQADCgcIDgAAAA==.',
Re='Regilz:BAAANQADCgMIAwAAAA==.',
Rh='Rhys:BAAANQADCgMIAwAAAA==.',
Ri='Ribeyye:BAAANQADCggIFwAAAA==.Rider:BAAANQAECgEIAQAAAA==.Rigormortiis:BAAANQAECgEIAQAAAA==.Rilde:BAAANQADCgYIDgAAAA==.Rinjiabri:BAAANQADCgYIEQAAAA==.',
Ro='Robroy:BAAANQAECggIAgAAAA==.Robrøy:BAAANQADCggIGAAAAA==.Rokmage:BAAANQAECgMIBAAAAA==.Roseclaw:BAEANQADCgcIDAABNQAECgYIDAACAAAAAA==.Roseclawed:BAEANQAECgYIDAAAAA==.Roxso:BAACNQAFFIEGAAIEAAUJPgztBgChAQAEAAUJPgztBgChAQA1AAQKgSIAAwQACQmnH4AaAC8DAAQACQmmH4AaAC8DAA0ABgl6DEoNABoBAAAA.',
Ru='Rukaiz:BAAANQAECgQICQAAAA==.',
['Rë']='Rëdmagma:BAAANQAECgQIDwAAAA==.',
['Rò']='Ròbroy:BAAANQAECggICQAAAA==.',
['Rû']='Rûsh:BAAANQADCgYICAAAAA==.',
Sa='Sacrelicious:BAAANQADCggIFQAAAA==.Saennah:BAAANQADCgIIAgAAAA==.Sagewynn:BAAANQADCggIFAAAAA==.Salfroc:BAAANQAECgYIDQAAAA==.Samhain:BAAANQAECgUICgAAAA==.Sanasianana:BAAANQADCgUIBQABNQAFFAEIAQACAAAAAA==.Saplo:BAAANQAECgEIAQAAAA==.Sarif:BAAANQAECgEIAQAAAA==.Saxel:BAAANQAECgEIAQAAAA==.',
Sc='Scallop:BAAANQADCgQIBAAAAA==.Schwarzenman:BAAANQADCgEIAQAAAA==.',
Se='Segio:BAAANQAECgEIAQAAAA==.Selcia:BAAANQADCgYICAAAAA==.Serenati:BAAANQAECgEIAQAAAA==.Seïya:BAAANQADCggIFAAAAA==.',
Sh='Shamawockee:BAAANQADCggICgABNQAECgYIDgACAAAAAA==.Shango:BAAANQADCgUIBQAAAA==.Sharavia:BAAANQAECgMIAwAAAA==.Shasu:BAAANQADCgEIAQAAAA==.Shaundi:BAAANQADCgYIEwAAAA==.Shautistic:BAAANQADCgYIBgAAAA==.Shocktuah:BAAANQAECgYIDQAAAA==.Shonúff:BAAANQAECgQIBQAAAA==.Shotaru:BAAANQADCgYICwAAAA==.Shotpace:BAAANQAECgQIBQAAAA==.Showerhandle:BAAANQADCgMIAwAAAA==.Shui:BAAANQAECgEIAQAAAA==.Shädöw:BAAANQADCgIIAgAAAA==.',
Si='Silmeria:BAAANQAECgIIAwAAAA==.Sinful:BAAANQAECgYIDwAAAA==.',
Sk='Skalagrim:BAAANQADCggIDwAAAA==.Skeptyk:BAAANQAECgUICgAAAA==.Sko:BAEANQAECgcIEAAAAA==.Skol:BAAANQAECgUICwAAAA==.',
Sm='Smiley:BAAANQAECgMIAwAAAA==.Smokeydabear:BAAANQADCgEIAQAAAA==.Smug:BAAANQAECgcICwAAAA==.',
Sn='Snapee:BAAANQADCgYIBgAAAA==.Sniffledoo:BAAANQAECgMIAwAAAA==.Snuwuf:BAAANQADCgUIBQAAAA==.',
So='Sockz:BAAANQAECgEIAgAAAA==.Soonmia:BAAANQADCgQIBAAAAA==.Sourfangs:BAAANQAECgcIEwAAAA==.Soxx:BAAANQADCgYICwABNQAECgQICQACAAAAAA==.',
Sp='Spicypeño:BAABNQAECoEaAAIOAAgJUyDiBAABAwAOAAgJUyDiBAABAwABNQAFFAcIEAAOALEZAA==.Spicý:BAAANQAECgcIDgAAAA==.Splack:BAAANQAECgYIDgAAAA==.Splithoofe:BAEANQADCgEIAQABNQADCggIDQACAAAAAA==.Sprawl:BAAANQAECgQIBQAAAA==.Sprawlher:BAAANQADCggIFAABNQAECgQIBQACAAAAAA==.',
Sq='Squrrlydan:BAEANQAECgQIBAAAAA==.',
St='Stabzuplenty:BAAANQAECgIIAgABNQAFFAUIBgAEAD4MAA==.Staint:BAAANQAECgQICwAAAA==.Staints:BAAANQAECgMIAwABNQAECgQICwACAAAAAA==.Starnights:BAAANQAECgEIAQAAAA==.Statman:BAAANQAECgEIAQAAAA==.Steelbubble:BAAANQAECgcIDgAAAA==.Stella:BAAANQADCgYIDAAAAA==.Stengah:BAAANQAECgYIDQAAAA==.Strela:BAAANQAECgcIEgAAAQ==.',
Su='Suraki:BAAANQAECgYICwAAAA==.',
Sw='Swtblsphmy:BAAANQADCggIEgAAAA==.',
['Sä']='Säber:BAAANQADCgcIBwAAAA==.',
['Sè']='Sèd:BAAANQAECgcIEwAAAA==.Sèitheach:BAAANQADCgYIDAAAAA==.',
['Sí']='Síd:BAAANQAECgQIBQAAAA==.',
Ta='Tahrin:BAAANQAECgUIBwAAAA==.Talamon:BAAANQAECgQICQAAAA==.Tandruid:BAAANQAECgcIEQAAAA==.Tarasis:BAAANQADCgEIAQAAAA==.Tashi:BAAANQAECgQICAAAAA==.Tasina:BAAANQADCgMIBAAAAA==.Taurenamos:BAAANQAECgUICwAAAA==.Taynam:BAAANQAECgIIAgABNQAECgQIBgACAAAAAA==.',
Te='Tempëst:BAAANQADCgEIAQAAAA==.Tenchu:BAAANQAECgQIBAAAAA==.Tendra:BAAANQADCgMIAwAAAA==.Tenseven:BAAANQAECgQICAAAAA==.',
Th='Thalorain:BAAANQADCgYIDgAAAA==.Thark:BAAANQADCgIIAgABNQAECgUIDQACAAAAAA==.Thatdruid:BAAANQAECgEIAQAAAA==.Thicknfluffy:BAAANQABCgEIAgAAAA==.Throwd:BAAANQAECgYICwAAAA==.Thundah:BAAANQAECgEIAQAAAA==.Thurk:BAAANQAECgUIDQAAAA==.',
Ti='Tideshunter:BAABNQAECoEXAAMPAAgJLBxAFwC/AgAPAAgJkhtAFwC/AgAGAAYJNxCdIgB6AQAAAA==.Tinytony:BAAANQAECgUICQAAAA==.Tinyweakling:BAAANQABCggIEQABNQAECgUICQACAAAAAA==.',
To='Toranis:BAAANQADCgQIBwAAAA==.Torrents:BAAANQAECgYIDQAAAA==.Totemik:BAAANQAECgEIAQAAAA==.',
Tr='Triepas:BAAANQAECgQIBAAAAA==.Trinytee:BAAANQAECgUIDAAAAA==.Trippytotem:BAAANQAECgYIDQAAAA==.Trolltoll:BAAANQADCgEIAQAAAA==.Trollypolly:BAAANQABCgMIAQAAAA==.',
Ty='Tyriäel:BAAANQAECgYIDgAAAA==.',
Ug='Ugolino:BAAANQADCgEIAQAAAA==.',
Ul='Ulther:BAAANQADCgYICAAAAA==.',
Va='Vacare:BAAANQADCgYICAAAAA==.Valdyria:BAAANQADCgQIBwAAAA==.Valistar:BAAANQADCgcIFAAAAA==.Valkoienne:BAAANQADCgQIBQAAAA==.Varnashar:BAAANQADCgYIBgAAAA==.Vavictus:BAAANQADCgYICAAAAA==.Vazaenei:BAAANQABCgMIAwAAAA==.',
Ve='Vedronorael:BAAANQADCgYIBgAAAA==.Veinos:BAAANQAECgYICwAAAQ==.Velanthia:BAAANQADCgcIBwAAAA==.Velora:BAAANQAECgIIBAAAAA==.Vengrath:BAAANQAECgYIDAAAAA==.Verderben:BAAANQADCgYICwAAAA==.Verind:BAAANQAFFAEIAQAAAA==.',
Vi='Vinhelsin:BAAANQADCgUIBgAAAA==.',
Vo='Voideater:BAAANQADCgEIAQAAAA==.Voron:BAAANQAECgQIEgAAAA==.',
Vu='Vulperra:BAAANQAECgUICgAAAA==.',
Wa='Walk:BAAANQADCgYIBgAAAA==.Waq:BAAANQAECgYIBwAAAA==.Waterwhip:BAAANQAECgcIDAAAAA==.',
We='Wemeo:BAAANQADCgcIFAAAAA==.Westfall:BAAANQAECgQICgAAAA==.',
Wi='Willrun:BAAANQADCgYIEAAAAA==.Wipeit:BAAANQADCgIIAgAAAA==.',
Wo='Wolfbayne:BAAANQAECgEIAQAAAA==.Wompeal:BAAANQAECgQIBAAAAA==.Wonkwonk:BAAANQAECgMIAwAAAA==.Worth:BAAANQAECgUIDQAAAA==.',
Wr='Wrukolas:BAAANQAECgQIBQAAAA==.',
Wy='Wystan:BAAANQAECgUICwAAAA==.',
['Wè']='Wès:BAAANQADCgEIAQAAAA==.',
['Wé']='Wés:BAAANQAECgUICwAAAA==.',
Xa='Xamsuciteey:BAAANQADCgUIBQAAAA==.Xandritten:BAAANQABCgIIAgAAAA==.Xanthe:BAAANQAECgQIBwAAAA==.Xavin:BAAANQADCgIIAgAAAA==.',
Xe='Xentow:BAAANQAECgUICgAAAA==.',
Ya='Yamling:BAAANQADCgcIDgAAAA==.Yayaka:BAAANQADCgcIDQAAAA==.',
Yi='Yizdano:BAABNQAECoEZAAMJAAkJRBHeDwA+AgAJAAgJNRLeDwA+AgAIAAkJdQpZDwA3AgAAAA==.',
Yu='Yukiina:BAAANQADCgYICAAAAA==.Yungbean:BAAANQAECgMIBAAAAA==.',
['Yû']='Yûm:BAAANQADCggICgAAAA==.',
Za='Zaccheus:BAAANQADCgYIBwABNQAECgcIDwACAAAAAA==.Zambora:BAAANQADCgcICgAAAA==.',
Ze='Zeebra:BAAANQADCgcIGAAAAA==.Zeesaw:BAAANQAECgQIBwAAAA==.Zenden:BAAANQADCgcIEQAAAA==.Zeretrix:BAAANQAECgYIDgAAAA==.Zerospace:BAAANQAECgYIDQAAAA==.',
Zl='Zlutar:BAAANQADCgUICgAAAA==.',
Zy='Zynos:BAAANQAECgMIBQAAAA==.Zynothrian:BAAANQADCgMIAwAAAA==.',
['Ça']='Çalindrel:BAAANQADCgUIBQAAAA==.',
['Úà']='Úà:BAAANQADCgIIAQABNQAECgQIBwACAAAAAA==.',
['Üb']='Überhealz:BAAANQAECgcIDwAAAA==.',
['ßö']='ßöw:BAAANQAECgYIDQAAAA==.',
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
