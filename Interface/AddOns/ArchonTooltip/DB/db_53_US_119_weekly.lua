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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Hunter-BeastMastery','Paladin-Holy','Monk-Windwalker','Shaman-Restoration','Mage-Arcane','Warlock-Demonology','Warrior-Arms','Hunter-Marksmanship','Shaman-Enhancement','Priest-Holy','DeathKnight-Blood','Paladin-Protection','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Warrior-Protection','Warrior-Fury','Mage-Frost','Evoker-Devastation','Druid-Balance','Shaman-Elemental',}
local provider = {region='US',realm='Hellscream',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aarix:BAAANQAECgYJEQAAAA==.',
Ac='Achmed:BAAANQADCgYJEwAAAA==.',
Ad='Addÿ:BAAANQAECgQJDAAAAA==.',
Ae='Aelasong:BAABNQAECoEZAAIBAAkKWx8KGwAJAwABAAkKWx8KGwAJAwABNQADCgUJBQACAAAAAA==.Aelinessa:BAAANQAECgQJBAAAAA==.',
Af='Afflíctd:BAAANQADCgcICAAAAA==.',
Al='Aldrîch:BAAANQAECgQICAAAAA==.Allyra:BAAANQAECgQICgAAAA==.Allzora:BAAANQAECgMIAwAAAA==.Aloki:BAAANQADCggIEAAAAA==.Alorarose:BAAANQAECgEIAQAAAA==.',
Am='Amberness:BAABNQAECoEaAAIDAAkKOyX1AwCmAwADAAkKOyX1AwCmAwAAAA==.Ametrius:BAAANQADCggJEAAAAA==.Ampd:BAAANQADCgYIEgAAAA==.',
An='Anastassia:BAABNQAECoEWAAIEAAgKuRoLIACZAgAEAAgKuRoLIACZAgAAAA==.Anuke:BAAANQADCggJEgAAAA==.',
Ar='Arestoz:BAAANQAECgYJCQAAAA==.Ariakith:BAAANQADCgEIAQAAAA==.Arkhlight:BAAANQADCgYIAwAAAA==.Arkhmonk:BAABNQAECoEVAAIFAAcKOQ3dIACIAQAFAAcKOQ3dIACIAQAAAA==.Armonos:BAAANQAECgYJCwAAAA==.Arrowhoof:BAEANQAECgMIAwAAAA==.Arthurian:BAAANQADCgEJAQAAAA==.Artémis:BAAANQADCgEIAgAAAA==.',
As='Ashiri:BAAANQABCgUJBgAAAA==.Ashmage:BAAANQAECgQJBAAAAA==.Asterisk:BAAANQAECgcJEwAAAA==.Astromo:BAAANQADCgMJBQAAAA==.Asya:BAAANQAECgEIAQAAAA==.',
At='Attilathepun:BAAANQADCggICAAAAA==.',
Au='Auriêl:BAAANQADCgcIFAAAAA==.',
Ax='Axxium:BAABNQAECoEhAAIGAAkKqxtUFwDNAgAGAAkKqxtUFwDNAgAAAA==.',
Az='Azastra:BAAANQAECgQIBAAAAA==.',
['Añ']='Aña:BAAANQAECgQIDAAAAA==.Añarchist:BAAANQADCgUJBwABNQAECgQIDAACAAAAAA==.',
Ba='Babymonstter:BAAANQADCgEIAQAAAA==.Baelzharon:BAAANQAECgYJCgAAAA==.Baericade:BAAANQADCgMIAwABNQADCgYIBgACAAAAAA==.Bagelpanda:BAAANQADCggIFwAAAA==.Balgrim:BAAANQAECgcIDwAAAA==.Balki:BAAANQADCgcJBwABNQAECgUJCgACAAAAAA==.Bandicoot:BAAANQADCgYIDQAAAA==.Barsch:BAAANQADCgQJBAAAAA==.Basalt:BAAANQAECgQJBAAAAA==.Bastenwode:BAAANQADCggJGQAAAA==.Bawce:BAAANQADCgcIDgAAAA==.',
Bb='Bbye:BAAANQADCggIDQAAAA==.',
Be='Beanboi:BAAANQADCgIIAgAAAA==.Bebynoob:BAAANQAECgQICQAAAA==.Becký:BAAANQAECgQIDAAAAA==.Beroan:BAAANQAECgQJBAAAAA==.Bertrille:BAAANQADCgMIAwAAAA==.',
Bi='Bigcøøkie:BAAANQADCgUICwAAAA==.Bigolcrities:BAAANQADCggJEgAAAA==.Bigshaft:BAAANQADCgYICgABNQADCggICgACAAAAAA==.Bigwannabe:BAAANQAECgUICQAAAA==.',
Bl='Blackmagma:BAAANQADCggIDgABNQAECgUJEQACAAAAAA==.Blackpinkk:BAAANQAECgUICAAAAA==.Blackppinkk:BAAANQAECgMIBAAAAA==.Bloodbunny:BAAANQADCggIEwAAAA==.',
Bo='Boggartt:BAAANQAECgIIAgAAAA==.Bootscoots:BAAANQAECgYICAAAAA==.Bornite:BAAANQADCgUICgAAAA==.Bowme:BAAANQAECgQIBAAAAA==.',
Br='Braedae:BAAANQADCggICgAAAA==.Brickaton:BAAANQAECgQIBgAAAA==.Brocknor:BAAANQAECgcIDwAAAA==.Broodling:BAAANQABCgEIAQAAAA==.',
Bu='Butterdtoast:BAEANQAECgUJCAAAAA==.',
Bw='Bwansamdi:BAAANQADCgYJDgAAAA==.',
Ca='Cabbresoa:BAAANQAECgQJBQAAAA==.Caboose:BAAANQAECgQJCgAAAA==.Cadbvucolta:BAAANQADCgUIBwAAAA==.Caledor:BAAANQAECggIDAAAAA==.Calindrel:BAAANQAECgYJCgAAAA==.Caliriya:BAAANQADCggIFAAAAA==.Candren:BAAANQAECgEIAQAAAA==.Caraway:BAAANQAECgMIAwAAAA==.',
Ce='Celaela:BAAANQAECggIAgAAAA==.Celant:BAAANQADCggJEwAAAA==.Celson:BAAANQADCggIDQAAAA==.Celticlore:BAAANQADCgcIEQAAAA==.Cerrvantes:BAAANQADCgcIDgAAAA==.',
Ch='Chernaboz:BAAANQAECgUIEAAAAA==.Chevelot:BAAANQADCgQIBgAAAA==.Chibbo:BAAANQAECgQIBAAAAA==.Chiblet:BAAANQAECgcJEQAAAA==.Chioma:BAAANQADCgcIDAABNQAECgcJEgACAAAAAA==.',
Ci='Ci:BAAANQADCgMIBgAAAA==.',
Cl='Cledwyn:BAAANQADCgMIAwAAAA==.Cloudsinger:BAAANQAECgcIDwAAAA==.',
Co='Codysseuz:BAAANQADCgQIBAAAAA==.Columbo:BAAANQADCgUIBQAAAA==.Combustdeez:BAABNQAECoEWAAIHAAgKxSESJwAeAwAHAAgKxSESJwAeAwAAAA==.Convrge:BAAANQADCgYIBwAAAA==.Corenthos:BAAANQAECgYJEwAAAA==.Corlys:BAAANQADCgYJBgAAAA==.Corên:BAAANQADCgcJEAAAAA==.',
Cr='Cranker:BAAANQADCgUIBQAAAA==.Crashed:BAAANQABCgUIBgAAAA==.Crazymoron:BAAANQAECgYJCgAAAA==.Creepndeath:BAAANQADCgcICAAAAA==.Creselia:BAAANQAECgQJBAAAAA==.Crowley:BAAANQADCgYICwAAAA==.Crum:BAAANQADCgYIBgAAAA==.Crumdumpster:BAAANQAECgQJBAABNQADCgYIBgACAAAAAA==.Crèmefraîche:BAAANQAECgUICwAAAA==.',
Cu='Cuddlerz:BAAANQAECgQJDAAAAA==.',
Cy='Cypherrellik:BAAANQAECgQIBgABNQAECgUJBQACAAAAAA==.',
Da='Dagthunderer:BAAANQAECgMIBAAAAA==.Dakkenrahl:BAAANQADCgcICwAAAA==.Dalatras:BAAANQADCgYICAABNQAECgQICgACAAAAAA==.Dalistra:BAAANQAECgQIBAABNQAECgQICgACAAAAAA==.Dalweaver:BAAANQADCgUIBQABNQAECgQICgACAAAAAA==.Damogdem:BAAANQADCgYICAAAAA==.Dangly:BAAANQAECgcIEwAAAA==.Dantes:BAAANQADCgMJAwAAAA==.Dar:BAAANQADCggJGAAAAA==.Darkflame:BAAANQAECgUICAAAAA==.Darklûrker:BAAANQAECgIIAgAAAA==.Darksidedbro:BAAANQADCgUIBQAAAA==.Darkzelda:BAAANQADCggICAAAAA==.Dayve:BAAANQAECgYJDwAAAA==.',
Dc='Dcpt:BAAANQADCgYIFgAAAA==.',
De='Deadgeinside:BAAANQADCgQIBAAAAA==.Deadgenah:BAAANQADCgMJAwAAAA==.Deadgnome:BAAANQAECgEIAgABNQAECgQJBwACAAAAAA==.Deathgimbo:BAAANQAECggIDQAAAA==.Deathstomper:BAAANQAECgUICgAAAA==.Demondono:BAAANQAECgYIEAAAAA==.Dethalas:BAAANQADCggICAAAAA==.Devomo:BAAANQAECgIIAgAAAA==.Deyedora:BAAANQAECgQJBAAAAA==.Dezax:BAABNQAECoEYAAIIAAgKRRxlIwCZAgAIAAgKRRxlIwCZAgAAAA==.',
Di='Diaboli:BAAANQADCgQICAAAAA==.Dilligafnope:BAAANQADCgcJBwAAAA==.Dinohunter:BAAANQAECgYIBwAAAA==.Disabler:BAAANQAECgEIAQABNQAECggIFgAHAMUhAA==.',
Dj='Djdiddles:BAAANQAECgcICgAAAA==.',
Do='Dorimane:BAAANQAECgUJDAAAAQ==.Dorlock:BAAANQAECgUJDgAAAA==.Dorotti:BAAANQAECgIJAgABNQAECgYJEQACAAAAAA==.',
Dr='Drais:BAAANQADCgIIBQABNQADCgQIBgACAAAAAA==.Drazgul:BAAANQADCgYIBgAAAA==.Drdukesilver:BAAANQADCgQIBAAAAA==.Dreadpanda:BAABNQAECoEkAAIJAAkKgiDTFQA1AwAJAAkKgiDTFQA1AwAAAA==.Dred:BAAANQAECgQIBAAAAA==.Dredwarrior:BAAANQADCgEIAQAAAA==.Drosmoke:BAAANQADCgUIBAAAAA==.Drprodigy:BAAANQAECgUICQAAAA==.',
Dy='Dybuck:BAAANQAECgMIAwAAAA==.Dyrcyn:BAAANQAECgUJCgAAAA==.',
['Dà']='Dànger:BAABNQAECoEaAAMDAAkK1CHzCgBRAwADAAkK1CHzCgBRAwAKAAQKWwrvQQCmAAAAAA==.',
Ed='Edroh:BAAANQAECgUJBgAAAA==.',
Ei='Eidur:BAAANQAECgYIEAAAAA==.Eightohfive:BAAANQADCgUIBwAAAA==.',
Ek='Ekøh:BAAANQADCgQICAAAAA==.',
El='Elará:BAAANQADCgYIBgAAAA==.Elemane:BAAANQADCgEIAQABNQAECgUJDAACAAAAAQ==.Elemefayoh:BAAANQAECgUJDgAAAA==.Elementlo:BAABNQAECoEbAAILAAgKyCPbAwAuAwALAAgKyCPbAwAuAwABNQABCgIIAgACAAAAAA==.Elsafromtemu:BAAANQAECgYIDgAAAA==.Elspeth:BAAANQAECgYJDwAAAA==.',
Em='Emagonasooth:BAAANQAECggIEAAAAA==.Emerey:BAAANQADCggIEgAAAA==.',
En='Endknightt:BAAANQADCggIDgAAAA==.Enflamee:BAAANQADCgUJBQAAAA==.Enma:BAAANQADCgQIBQAAAA==.Ennola:BAAANQADCgYJBwAAAA==.',
Ep='Ephriia:BAAANQAECgYIBgAAAA==.',
Er='Erikprince:BAAANQAECgQJCQAAAA==.Erso:BAAANQADCggJEwAAAA==.',
Et='Eternalpaín:BAABNQAECoEbAAIBAAcKYB31SAAwAgABAAcKYB31SAAwAgAAAA==.',
Ev='Evagria:BAAANQADCgYIBgAAAA==.Evanrude:BAAANQABCgcJCgAAAA==.',
Fa='Fal:BAAANQADCggIEgAAAA==.Falcyon:BAAANQADCgIIAgAAAA==.Falroot:BAAANQAECgcJEgAAAA==.',
Fe='Feliché:BAAANQAECgMJAwABNQAECggIFgAMACkXAA==.Fevirin:BAAANQAECgQJBQAAAA==.',
Fi='Firefawkes:BAAANQAECgQJBAAAAA==.Fistbump:BAAANQAFFAEIAQAAAA==.',
Fl='Fletchling:BAAANQAECgYJDwAAAA==.Flizrak:BAAANQADCggIEAABNQAFFAYIDAAHAHgQAA==.',
Fo='Footsteps:BAAANQADCgcJEQAAAA==.',
Fr='Freefallen:BAAANQADCgMIAwAAAA==.Frostclot:BAABNQAECoEeAAINAAgKVx/2FAC3AgANAAgKVx/2FAC3AgAAAA==.Frostsalad:BAAANQAECgQIBgAAAA==.Frozoned:BAAANQAECggICwABNQAFFAEIAQACAAAAAA==.',
Fu='Fulta:BAAANQAECgUJDwAAAA==.',
['Fø']='Føxhound:BAAANQADCgUIBQAAAA==.',
Ga='Garadin:BAAANQAECgIIAgAAAA==.Garnok:BAAANQADCgUIBQAAAA==.Garwa:BAABNQAECoEYAAMDAAgKVSGyFQD4AgADAAgKVSGyFQD4AgAKAAIK2xK5SwB1AAAAAA==.',
Ge='Geniver:BAAANQADCggJGQAAAA==.Gerla:BAAANQAECgUJDAAAAA==.',
Gi='Gigas:BAAANQAECgUJDAAAAA==.Gilgameshh:BAAANQAECgYIDgAAAA==.Girthbrooks:BAAANQAECgcJEgAAAA==.',
Gl='Glimmerfangs:BAAANQAECgYJBgAAAA==.',
Go='Gomory:BAAANQADCggJGQAAAA==.Gondark:BAAANQADCgcIEQAAAA==.Gorgrim:BAAANQAECgEIAQAAAA==.Gorpse:BAAANQADCggIDwABNQAECgUIDAACAAAAAA==.',
Gr='Graverael:BAAANQADCgcICQAAAA==.Gretchen:BAAANQAECgYIEQABNQAECgkJHgAKANYYAA==.Greyley:BAAANQAECgQIBAABNQABCgIIAgACAAAAAQ==.Greywolf:BAABNQAECoEVAAIGAAcKIhn0QgDhAQAGAAcKIhn0QgDhAQAAAA==.Grimlight:BAAANQAECgYIBgABNQAFFAMIAwACAAAAAA==.',
['Gä']='Gärry:BAAANQAECgMIBQAAAA==.',
Ha='Hanzoff:BAAANQADCgQJBAAAAA==.Harrow:BAAANQAECgQJBAAAAA==.Haxx:BAAANQAECgYJDwAAAA==.',
He='Healls:BAAANQADCgUIBQAAAA==.Hearge:BAAANQAECgcJEwAAAA==.Hellhawk:BAAANQAECgQJBAAAAA==.Hevydevy:BAAANQAECgQJCgABNQAECgUICQACAAAAAA==.Hexhain:BAAANQAECgYIEAAAAA==.',
Ho='Hockay:BAAANQAECgYJDwAAAA==.Holygun:BAAANQAECgcJDQAAAA==.Holyshiets:BAAANQADCgUIBQAAAA==.Holyshiza:BAAANQAECgQIDAAAAA==.Holystan:BAAANQAECgEIAQAAAA==.Hondoe:BAAANQAECgUJBwAAAA==.Hopi:BAAANQABCgQIBAAAAA==.',
Ht='Htownglaivez:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Htownhots:BAAANQAECgEIAQAAAA==.Htownshaman:BAAANQADCgcIDgABNQAECgEIAQACAAAAAA==.',
Hu='Humblepotato:BAAANQADCgEIAgAAAA==.Hungsten:BAAANQAECgEJAQABNQAECgcIEwACAAAAAA==.Huntfromhell:BAAANQAECgYIDgAAAA==.',
Ic='Iceagaint:BAAANQADCgQIBQAAAA==.Icedpissfox:BAAANQADCgUJBwAAAA==.',
Id='Idonttank:BAAANQADCggIEgAAAA==.',
Il='Illio:BAAANQAECgIIAgAAAA==.',
Im='Imarea:BAAANQAECgUJCgAAAA==.Impirious:BAABNQAECoEYAAINAAgK0hLvNQDCAQANAAgK0hLvNQDCAQAAAA==.Implumz:BAAANQADCgMIAwABNQAECggJGAANANISAA==.Imptard:BAAANQADCgIIAgABNQAECggJGAANANISAA==.Imyx:BAAANQAECgQIBAAAAA==.',
In='Incubussy:BAAANQADCgcIBwAAAA==.Infamuspikel:BAAANQAECgcIDgAAAA==.Infel:BAAANQAECgIIBgAAAA==.Inkkish:BAAANQAECgQJCAAAAA==.Innovates:BAABNQAECoEbAAIOAAkKZBUpDQBOAgAOAAkKZBUpDQBOAgAAAA==.Interstellar:BAAANQAECgQIBAAAAA==.Intervene:BAAANQADCgYJFAABNQAECgcIGwABAGAdAA==.Invictus:BAAANQAECgYJEAAAAA==.',
Is='Ist:BAAANQAECgEJAQAAAA==.',
Iz='Izuael:BAAANQAECgYJBgAAAA==.',
Ja='Jackjr:BAAANQADCgQIBgAAAA==.Jadea:BAAANQADCgUIBQAAAA==.Jalim:BAAANQADCgcIBwAAAA==.Jamesy:BAAANQADCgQJBAABNQAECgkJGQAJAKsdAA==.Jandoar:BAAANQAECgQIBAAAAA==.Jarlen:BAAANQADCgEIAQAAAA==.Jaylea:BAABNQAECoEVAAIPAAcKRghqGwB1AQAPAAcKRghqGwB1AQAAAA==.Jaynee:BAAANQABCgUIBgAAAA==.',
Je='Jegallidin:BAAANQADCgEIAgAAAA==.Jetpilot:BAAANQADCggIFAAAAA==.Jeypi:BAAANQAECgUIBgAAAA==.',
Ji='Jiq:BAAANQAECgQJBgAAAA==.',
Jo='Johli:BAAANQADCggICAAAAA==.',
Ju='Judikai:BAAANQAECgQIBAAAAA==.Junesong:BAAANQAECgQICQAAAA==.Justwipeit:BAAANQADCggJCAAAAA==.',
Ka='Kabilos:BAAANQADCggJEAAAAA==.Kaedian:BAAANQADCggICQABNQAECgUIDwACAAAAAA==.Kalesmora:BAAANQAECgYIEAAAAA==.Kamikaze:BAAANQAECgMJAwAAAA==.Karlov:BAAANQAECgcICwAAAA==.Karthis:BAAANQADCggIDAAAAA==.Kazera:BAAANQADCgIJAgAAAA==.Kazgrim:BAAANQADCgYICgAAAA==.',
Ke='Keanah:BAAANQAECgUJDgAAAA==.Kelrosh:BAAANQABCgIJAgAAAA==.Keynn:BAAANQADCgUIBQABNQAECgUIDwACAAAAAA==.',
Kh='Kheims:BAAANQADCggICQAAAA==.Khrom:BAAANQADCgIIAgAAAA==.Khytoem:BAAANQAECgQJBAAAAA==.',
Ki='Killduran:BAAANQAECgUICgAAAA==.Kimaga:BAAANQADCgUICQABNQAECgUIDAACAAAAAA==.Kindle:BAAANQADCgMIAwABNQAECgEIAQACAAAAAA==.Kirasha:BAAANQADCgQIBAAAAA==.Kitom:BAAANQAECgYICQAAAA==.Kiwia:BAAANQAECgUICwAAAA==.',
Kl='Klunt:BAAANQADCgEJAQABNQAECgQIDgACAAAAAA==.',
Ko='Kolaniber:BAAANQABCgEIAQAAAA==.',
Kr='Kracked:BAAANQADCgMIAgAAAA==.Krank:BAAANQADCgUIDAABNQADCgkJCQACAAAAAA==.Krellyroll:BAAANQADCggIDgABNQAECgUJCgACAAAAAA==.Krelthyr:BAAANQAECgUJCgAAAA==.Krumm:BAAANQAECgYJEwAAAA==.Kruul:BAAANQABCgQJBAAAAA==.',
Ku='Kuhne:BAAANQADCggJFQAAAA==.Kungfudrew:BAAANQADCggICAAAAA==.',
Ky='Kyber:BAAANQAECgIIAgAAAA==.Kyther:BAAANQAECgQIBwAAAA==.',
['Kñ']='Kñightboat:BAAANQAECgQIBAAAAA==.',
La='Ladeiene:BAAANQAECgMJAwAAAA==.Laelwyn:BAAANQADCggJDwAAAA==.Laelynd:BAAANQADCgYICgAAAA==.Laeritides:BAAANQADCgYICQABNQAECgQJBAACAAAAAA==.Laeritidesdk:BAAANQAECgQJBAAAAA==.Lastditch:BAAANQAECgMIAwAAAA==.Lateralas:BAAANQADCggJEQAAAA==.',
Le='Leothedog:BAAANQAECgUJBgAAAA==.Lethas:BAAANQADCgMIAwAAAA==.Leukheimsia:BAAANQADCgUJBQABNQADCggICQACAAAAAA==.',
Li='Liere:BAAANQADCgcIDAAAAA==.Lightrising:BAAANQADCggJCAAAAA==.Lilenalol:BAAANQADCgcJDgAAAA==.Lilfiorella:BAAANQADCgYJCwAAAA==.Lilmonstrman:BAAANQAECgcJEwAAAA==.Liltree:BAAANQAECgQJBAAAAA==.Limbbiscuit:BAABNQAECoEUAAMDAAcKDhY6RwAfAgADAAcK/RU6RwAfAgAKAAQKrgMJQgClAAAAAA==.Listmonk:BAAANQAECgEJAQAAAA==.',
Ll='Llothae:BAAANQAECgQJBAAAAA==.',
Lo='Lonjick:BAAANQADCgIIAgAAAA==.Lots:BAAANQADCgcIGAAAAA==.Loyalty:BAAANQAECgEIAgAAAA==.',
Lu='Lul:BAABNQAECoEeAAIJAAgKDCKNJgDWAgAJAAgKDCKNJgDWAgAAAA==.Luminar:BAAANQAECgEIAQAAAA==.Lunaaru:BAAANQADCgMIAwAAAA==.Luvrstriplet:BAAANQADCggJDgAAAA==.',
['Lð']='Lðvergirl:BAAANQAECgUIDAAAAA==.',
Ma='Madcow:BAAANQAECgIJAgAAAA==.Maelk:BAAANQADCgQIBQABNQADCgYIDgACAAAAAA==.Magistella:BAAANQAECgIIAgAAAA==.Maisrii:BAEANQAECgQIBQAAAA==.Maivz:BAAANQAECgYJEQAAAA==.Malignantt:BAAANQAECgYIEAAAAA==.Maloch:BAAANQADCgIJAgAAAA==.Mapletoast:BAAANQADCgQIBAAAAA==.Marthren:BAAANQADCgUICQAAAA==.Marzyna:BAAANQADCgkJCQAAAA==.Maurphious:BAAANQADCgcIFgAAAA==.',
Me='Mekaniker:BAAANQABCgMJAwAAAA==.Melbee:BAAANQAECgUICQAAAA==.Melodrama:BAAANQAECgIIAgAAAA==.Metri:BAAANQABCgUIBwAAAA==.',
Mi='Micassa:BAAANQADCgIJAgAAAA==.Michaeljrdan:BAAANQADCgQIBAAAAA==.Mikela:BAAANQAECgQJCQABNQAECgYJEQACAAAAAA==.Milkee:BAAANQADCgEIAQAAAA==.Mirgaree:BAAANQAECgUJDAAAAA==.Mirjelys:BAAANQAECgEJAQAAAA==.',
Mo='Moarass:BAAANQAECgYIDAAAAA==.Monty:BAAANQADCggJFQAAAA==.Moodswingz:BAAANQADCgIJAwAAAA==.Mordos:BAAANQADCgMIAwAAAA==.',
Mu='Muffinz:BAAANQAECgQJBwAAAA==.Mugo:BAAANQADCgQIBAABNQAECggIFgAMACkXAA==.Multiabuse:BAAANQAECgMJAQAAAA==.Multipass:BAAANQABCgEJAQAAAA==.',
My='Myau:BAAANQAECgUJBQAAAA==.Mylou:BAAANQAECgQJBQAAAA==.Mynia:BAAANQAECgYJEwAAAA==.',
Na='Nano:BAAANQAECgUJDAAAAA==.Nazdreg:BAAANQAECgUIEAAAAA==.',
Ne='Negan:BAAANQABCgUIBQAAAA==.Neotoldir:BAAANQAECgYJDwAAAA==.Nerfdisc:BAAANQADCgkJFQAAAA==.Nevershocked:BAAANQAECgUJDQAAAA==.Nezziee:BAAANQADCgYIDAAAAA==.',
Ni='Ninjaznpariz:BAAANQADCgQJBAAAAA==.',
No='Noblewrack:BAAANQADCgEIAQAAAA==.Noobles:BAAANQADCgYIBgAAAA==.Nordie:BAAANQADCggICAAAAA==.Northik:BAAANQADCgUIBQABNQAECgYJDAACAAAAAA==.Nosredna:BAAANQAECgEIAQAAAA==.Nosrednàx:BAAANQADCgUIBQAAAA==.Novata:BAAANQADCgUIBQABNQAECgIIAgACAAAAAA==.',
Nu='Nuzz:BAACNQAFFIEKAAIJAAUKDSL/AwABAgAJAAUKDSL/AwABAgA1AAQKgRwAAgkACQrIJZ0HAJ4DAAkACQrIJZ0HAJ4DAAAA.',
Ny='Nydav:BAAANQAECgUIDwAAAA==.',
Ob='Obalma:BAAANQAECgYJEgAAAA==.',
Od='Odwalla:BAABNQAECoEYAAIDAAkKUyJOCABtAwADAAkKUyJOCABtAwAAAA==.',
Ol='Olmec:BAAANQAECgIIBAAAAA==.',
On='Onlydesert:BAAANQAECgYJEQAAAA==.Onranui:BAAANQADCgcICAAAAA==.',
Op='Optiks:BAAANQAECgUJCAAAAA==.',
Or='Orcfan:BAAANQABCgIJAgAAAA==.Orksauce:BAABNQAECoEfAAMQAAgKdB4aFQAEAgAQAAYKhh0aFQAEAgARAAIKPSGWRwC5AAAAAA==.Orphella:BAAANQAECgEIAQAAAA==.',
Os='Osares:BAAANQAECgUICQAAAA==.Osong:BAAANQADCgcIBwABNQAECgEIAQACAAAAAA==.',
Ou='Outtamanna:BAAANQADCgUJBQAAAA==.',
Ow='Owils:BAAANQADCgYIBgABNQAECgYJEwACAAAAAA==.',
Ox='Oxl:BAAANQADCgQIBAAAAA==.',
Pa='Pagophobia:BAAANQAECgMIAwAAAA==.Pallytree:BAAANQADCggIGwAAAA==.Papiblanco:BAAANQADCggICgAAAA==.',
Pe='Percepcions:BAAANQAECgIJAgAAAA==.Percksmash:BAAANQAECggJCAAAAA==.Perkyl:BAAANQAECgEIAQAAAA==.',
Ph='Phage:BAAANQADCggICAABNQAECgQIDgACAAAAAA==.Philon:BAAANQADCgEJAQAAAA==.Photophobia:BAABNQAECoEYAAISAAgK8B+XDQDIAgASAAgK8B+XDQDIAgAAAA==.',
Pi='Piezo:BAAANQADCgQIBgAAAA==.Pikevarr:BAAANQADCggJEAAAAA==.Pivy:BAAANQADCgYIBgABNQAFFAEIAQACAAAAAA==.',
Pk='Pkrage:BAABNQAECoEbAAMTAAgKXBx1BgCIAgATAAgK9Bt1BgCIAgAJAAEKOBL2/AAyAAAAAA==.',
Pl='Plazlie:BAABNQAECoEZAAIUAAgKwyJ9AQAzAwAUAAgKwyJ9AQAzAwAAAA==.Ploppstein:BAEANQAECgUICwAAAA==.',
Po='Polyethylene:BAAANQAECgYICwAAAA==.Poucastranca:BAABNQAECoEpAAMIAAgK/iQuFgDkAgAIAAcKpyQuFgDkAgAPAAMKuST/IQA9AQAAAA==.',
Pu='Punkpikachu:BAAANQADCgYIFgAAAA==.',
Qk='Qkoira:BAAANQAECgQICgAAAA==.',
Qu='Quanlain:BAAANQAECgQJBAAAAA==.Quillathe:BAAANQAECgYIEQAAAA==.',
Ra='Raagh:BAAANQAECgQIBAAAAA==.Rancore:BAAANQAECgQJBgAAAA==.Rashdar:BAABNQAECoEbAAIBAAgKShvXPABgAgABAAgKShvXPABgAgAAAA==.Rasto:BAAANQADCgYICQABNQAECgQJBwACAAAAAA==.Rattpacck:BAAANQADCgUIBgAAAA==.Rattpack:BAAANQAECgQJCQAAAA==.Raves:BAAANQAECgQIBAAAAA==.Rayvynn:BAAANQADCgIJAgAAAA==.',
Re='Regilz:BAAANQADCgMIAwAAAA==.',
Rh='Rhys:BAAANQADCgMIAwAAAA==.',
Ri='Ribeyye:BAAANQAECgQJBAAAAA==.Rider:BAAANQAECgEIAQAAAA==.Rigormortiis:BAAANQAECgEIAQAAAA==.Rilde:BAAANQADCgYJFAAAAA==.Rinjiabri:BAAANQADCgYIEQAAAA==.',
Ro='Robroy:BAAANQAECggJBAAAAA==.Robrøy:BAAANQADCggJGQAAAA==.Rokmage:BAAANQAECgMIBAAAAA==.Roseclaw:BAEANQADCggJDQABNQAECgcIEwACAAAAAA==.Roseclawed:BAEANQAECgcIEwAAAA==.Roxso:BAACNQAFFIEMAAIHAAYKeBDUBQADAgAHAAYKeBDUBQADAgA1AAQKgSoAAwcACQpwINIgADQDAAcACQpuINIgADQDABUABgp6DJ0RABMBAAAA.',
Ru='Rukaiz:BAAANQAECgUICwAAAA==.',
['Rë']='Rëdmagma:BAAANQAECgUJEQAAAA==.',
['Rò']='Ròbroy:BAAANQAECggJCQAAAA==.',
['Ró']='Rónan:BAAANQAECgEJAQAAAA==.',
['Rû']='Rûsh:BAAANQADCggJEAAAAA==.',
Sa='Sacrelicious:BAAANQADCggIFQAAAA==.Saennah:BAAANQADCgIJAgAAAA==.Sagewynn:BAAANQAECgMIAwAAAA==.Sainei:BAAANQADCgUIBQABNQAECggIFgAJAEAaAA==.Salfroc:BAAANQAECgYJEwAAAA==.Samhain:BAAANQAECgYIEAAAAA==.Sanasianana:BAAANQADCgUIBQABNQAFFAEIAQACAAAAAA==.Saplo:BAAANQAECgQJBAAAAA==.Sarif:BAAANQAECgMIBAAAAA==.Saxel:BAAANQAECgEIAQAAAA==.',
Sc='Scallop:BAAANQADCgQIBAAAAA==.Schwarzenman:BAAANQADCgEIAQAAAA==.',
Se='Segio:BAAANQAECgEIAQAAAA==.Selcia:BAAANQADCggJEAAAAA==.Serenati:BAAANQAECgQJBAAAAA==.Seïya:BAAANQADCggIGgAAAA==.',
Sg='Sgthulka:BAAANQADCgQJBAAAAA==.',
Sh='Shamawockee:BAAANQAECgQIBQABNQAECgcJFgADAM8bAA==.Shango:BAAANQADCgUIBQAAAA==.Sharavia:BAAANQAECgUJCAAAAA==.Shasu:BAAANQADCgEIAQAAAA==.Shaundi:BAAANQADCggJFQAAAA==.Shautistic:BAAANQADCgYIBgAAAA==.Shocktuah:BAAANQAECgYJEwAAAA==.Shonúff:BAAANQAECgYICwAAAA==.Shotaru:BAAANQAECgMIAwAAAA==.Shotpace:BAAANQAECgQJCAAAAA==.Showerhandle:BAAANQADCgMIAwAAAA==.Shui:BAAANQAECgEIAQAAAA==.Shädöw:BAAANQADCgIIAgAAAA==.',
Si='Silmeria:BAAANQAECgMJBgAAAA==.Sinful:BAABNQAECoEZAAMUAAgKng2MCADTAQAUAAgKng2MCADTAQAJAAEKrweCBgEmAAAAAA==.',
Sk='Skalagrim:BAAANQADCggIDwAAAA==.Skeptyk:BAAANQAECgYIEAAAAA==.Sko:BAEBNQAECoEZAAMEAAgK/BlGIQCRAgAEAAgK/BlGIQCRAgABAAYKHgoCpgAdAQABNQADCgcJCQACAAAAAA==.Skol:BAAANQAECgUIDwAAAA==.Skolivia:BAEANQADCgcJCQAAAA==.',
Sm='Smiley:BAAANQAECgMIAwAAAA==.Smokeydabear:BAAANQADCgEIAQAAAA==.Smug:BAAANQAECgcIEQAAAA==.',
Sn='Snapee:BAAANQAECgEJAQAAAA==.Sniffledoo:BAAANQAECgUJCAAAAA==.Snuwuf:BAAANQADCgcICwAAAA==.',
So='Sockz:BAAANQAECgEJAwAAAA==.Soonmia:BAAANQADCgQIBAAAAA==.Sourfangs:BAABNQAECoEXAAMJAAgKcSI8IwDoAgAJAAgKcSI8IwDoAgAUAAEKpCKWGwBjAAAAAA==.Soxx:BAAANQADCgYICwABNQAECgYJDwACAAAAAA==.',
Sp='Spicypeño:BAABNQAECoEiAAIWAAkKDiF9AgBxAwAWAAkKDiF9AgBxAwABNQAFFAcIFgAWAKobAA==.Spicý:BAAANQAECggJEgAAAA==.Splack:BAABNQAECoEWAAIDAAcKzxsiRQAlAgADAAcKzxsiRQAlAgAAAA==.Splithoofe:BAEANQADCgEIAQABNQAECgMIAwACAAAAAA==.Sprawl:BAAANQAECgYJCwAAAA==.Sprawlher:BAAANQAECgMIAwABNQAECgYJCwACAAAAAA==.',
Sq='Squrrlydan:BAEANQAECgQJBAAAAA==.',
St='Stabzuplenty:BAAANQAECgIIAgABNQAFFAYIDAAHAHgQAA==.Staint:BAAANQAECgQIDgAAAA==.Staints:BAAANQAECgMJAwABNQAECgQIDgACAAAAAA==.Starnights:BAAANQAECgQJBQAAAA==.Statman:BAAANQAECgQJBAAAAA==.Steelbubble:BAAANQAECgcIEwAAAA==.Stella:BAAANQADCgYIDAAAAA==.Stengah:BAAANQAECgYJEwAAAA==.Stonebrew:BAAANQABCgEIAQAAAA==.Strela:BAAANQAECggIGgAAAQ==.',
Su='Suraki:BAAANQAECgcJEgAAAA==.',
Sv='Svetlian:BAAANQADCgMIAwABNQAECggIGgACAAAAAA==.',
Sw='Swtblsphmy:BAAANQAECgQJBAAAAA==.',
Sy='Sylvestrus:BAAANQADCgMIAwABNQAECggIFgAMACkXAA==.',
['Sä']='Säber:BAAANQADCgcIBwAAAA==.',
['Sè']='Sèd:BAABNQAECoEXAAIMAAgKCBNIPAD5AQAMAAgKCBNIPAD5AQAAAA==.Sèitheach:BAAANQADCggJDgAAAA==.',
['Sí']='Síd:BAAANQAECgcJEQAAAA==.',
Ta='Tahrin:BAAANQAECgUJDAAAAA==.Talamon:BAAANQAECgYJDwAAAA==.Tamerlynn:BAAANQADCgUIBAAAAA==.Tandruid:BAABNQAECoEbAAIXAAgKzxv5HACJAgAXAAgKzxv5HACJAgAAAA==.Tarasis:BAAANQADCgEIAQAAAA==.Tashi:BAAANQAECgUJDQAAAA==.Tasina:BAAANQADCgMIBAAAAA==.Taurenamos:BAAANQAECgYIEwAAAA==.Taynam:BAAANQAECgMIBAABNQAECgQIBgACAAAAAA==.',
Te='Tempëst:BAAANQAECgIJAgAAAA==.Tenchu:BAAANQAECgUICQAAAA==.Tendra:BAAANQADCgMIAwAAAA==.Tenseven:BAAANQAECgQICAAAAA==.',
Th='Thalorain:BAAANQADCgYIDgAAAA==.Thark:BAAANQADCgIIAgABNQAECgYIEgACAAAAAA==.Thatdruid:BAAANQAECgEIAQAAAA==.Thicknfluffy:BAAANQABCgEIAgAAAA==.Throwd:BAAANQAECgYJEQAAAA==.Thundah:BAAANQAECgEIAQAAAA==.Thurk:BAAANQAECgYIEgAAAA==.',
Ti='Tideshunter:BAABNQAECoEYAAMDAAgKHB0DIwCtAgADAAgKghwDIwCtAgAKAAYKNxCZKgBsAQAAAA==.Tinytony:BAAANQAECgcIEAAAAA==.Tinyweakling:BAAANQAECgEIAQABNQAECgYJDwACAAAAAA==.',
To='Toranis:BAAANQADCgQIBwAAAA==.Torrents:BAAANQAECgYJEwAAAA==.Totemik:BAAANQAECgEIAQAAAA==.',
Tr='Trailerpark:BAAANQAECgYIBgAAAA==.Triepas:BAAANQAECgQIBAAAAA==.Trinytee:BAAANQAECgUJEwAAAA==.Trippytotem:BAABNQAECoEUAAMYAAcKuweTXQCAAQAYAAcKuweTXQCAAQAGAAMKWwJauQBrAAAAAA==.Trolltoll:BAAANQADCgEIAQAAAA==.Trollypolly:BAAANQABCgMIAQAAAA==.',
Ty='Tyriäel:BAAANQAECgcJDwAAAA==.Tyrrible:BAAANQAECggIAQAAAA==.',
Ug='Ugolino:BAAANQADCgEIAQAAAA==.',
Ul='Ulther:BAAANQADCggJEAAAAA==.',
Va='Vacare:BAAANQADCggJEAAAAA==.Valdyria:BAAANQADCgQIBwAAAA==.Valistar:BAAANQAECgEIAQAAAA==.Valkoienne:BAAANQADCgQJCQAAAA==.Varnashar:BAAANQADCgYIBgAAAA==.Vavictus:BAAANQADCggJEAAAAA==.Vazaenei:BAAANQABCgMIAwAAAA==.',
Ve='Vedronorael:BAAANQADCgcJBgAAAA==.Veinos:BAAANQAECggICwAAAQ==.Velanthia:BAAANQADCgcIBwAAAA==.Velora:BAAANQAECgIIBAAAAA==.Vengrath:BAAANQAECgYIDgAAAA==.Verderben:BAAANQAECgMIAwAAAA==.Verind:BAAANQAFFAEIAQAAAA==.',
Vi='Vinhelsin:BAAANQADCgUICAAAAA==.',
Vo='Voideater:BAAANQADCgEIAQAAAA==.Voron:BAABNQAECoEYAAIBAAUK9Q0mqwASAQABAAUK9Q0mqwASAQAAAA==.',
Vu='Vulperra:BAAANQAECgYIDwAAAA==.',
Vy='Vynessa:BAAANQADCgMJAwAAAA==.',
Wa='Wade:BAAANQAECgcJAwAAAA==.Walk:BAAANQADCgYIBgAAAA==.Waq:BAAANQAECgYJDwAAAA==.Waterwhip:BAAANQAECgcIEwAAAA==.',
We='Wemeo:BAAANQAECgEJAQAAAA==.Westfall:BAAANQAECgUIDwAAAA==.',
Wi='Willrun:BAAANQADCggJEgAAAA==.Wipeit:BAAANQADCgIIAgAAAA==.',
Wo='Wolfbayne:BAAANQAECgIJAgAAAA==.Wompeal:BAAANQAECgYJCgAAAA==.Wonkwonk:BAAANQAECgUJCAAAAA==.Worth:BAABNQAECoEYAAIBAAgKgB03OQBvAgABAAgKgB03OQBvAgAAAA==.',
Wr='Wrukolas:BAAANQAECgUICQAAAA==.',
Wy='Wystan:BAAANQAECgYJEQAAAA==.',
['Wè']='Wès:BAAANQADCgEIAQAAAA==.',
['Wé']='Wés:BAAANQAECgUIDgAAAA==.',
Xa='Xamsuciteey:BAAANQADCgUIBQAAAA==.Xandritten:BAAANQABCgIIAgAAAA==.Xanthe:BAAANQAECgUJDAAAAA==.Xavin:BAAANQADCgcICQAAAA==.',
Xe='Xentow:BAAANQAECgYIEAAAAA==.',
Ya='Yamling:BAAANQADCgcIFQAAAA==.Yayaka:BAAANQADCgcIEgAAAA==.',
Yi='Yizdano:BAABNQAECoEfAAMRAAkKYBS+EwBgAgARAAgKUxa+EwBgAgAQAAkKdQrEEgAhAgAAAA==.',
Yu='Yukiina:BAAANQADCgcIDwAAAA==.Yungbean:BAAANQAECgMJBQAAAA==.',
['Yû']='Yûm:BAAANQADCggICgAAAA==.',
Za='Zaccheus:BAAANQAECgIIAgABNQAECggIFgAMACkXAA==.Zambora:BAAANQADCgcICgAAAA==.Zamwi:BAAANQAECgQIBAAAAA==.',
Ze='Zeebra:BAAANQAECgEJAQAAAA==.Zeesaw:BAAANQAECgYJDQAAAA==.Zenden:BAAANQADCggJGQAAAA==.Zeretrix:BAABNQAECoEVAAMHAAcKmhzubgBGAgAHAAcK5BvubgBGAgAVAAQKFhFmFQDeAAAAAA==.Zerospace:BAAANQAECgYIEQAAAA==.',
Zl='Zlutar:BAAANQAECgIIAgAAAA==.',
Zy='Zynos:BAAANQAECgYJCwAAAA==.Zynothrian:BAAANQADCgMIAwAAAA==.',
['Ça']='Çalindrel:BAAANQADCgUIBQAAAA==.',
['Úà']='Úà:BAAANQADCgIIAQABNQAECgQICgACAAAAAA==.',
['Üb']='Überhealz:BAABNQAECoEWAAMMAAgKKRdkPAD4AQAMAAgKKRdkPAD4AQASAAMKWAthPQCuAAAAAA==.',
['ßö']='ßöw:BAAANQAECgYJEwAAAA==.',
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
