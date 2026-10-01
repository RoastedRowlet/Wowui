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

local lookup = {'Hunter-BeastMastery','Hunter-Survival','Paladin-Retribution','Unknown-Unknown','Paladin-Holy','Monk-Windwalker','Shaman-Restoration','Warrior-Arms','Priest-Shadow','DemonHunter-Havoc','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Druid-Balance','Warlock-Demonology','Hunter-Marksmanship','Shaman-Elemental','Shaman-Enhancement','Mage-Frost','Mage-Fire','Paladin-Protection','Priest-Holy','Monk-Mistweaver','Rogue-Subtlety','Rogue-Assassination','Warlock-Destruction','Priest-Discipline','Warrior-Protection','DeathKnight-Frost','Warrior-Fury','Warlock-Affliction','DemonHunter-Devourer','Evoker-Devastation','Evoker-Preservation','Monk-Brewmaster','Druid-Restoration',}
local provider = {region='US',realm='Hellscream',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aarix:BAABNQAECoEbAAMBAAgKURj7OQB3AgABAAgKFhj7OQB3AgACAAIKyA1ADQBuAAAAAA==.',
Ac='Achmed:BAAANQADCgYIEwAAAA==.',
Ad='Addÿ:BAAANQAECgQIEAAAAA==.',
Ae='Aelasong:BAABNQAECoEcAAIDAAkK1h/JJAD9AgADAAkK1h/JJAD9AgABNQADCgUIBQAEAAAAAA==.Aelinessa:BAAANQAECgUICQAAAA==.',
Af='Afflíctd:BAAANQADCgcICAAAAA==.',
Al='Aldrîch:BAAANQAECgQICgAAAA==.Allyra:BAAANQAECgUICwAAAA==.Allzerim:BAAANQADCgYIBQABNQAECgQIBgAEAAAAAA==.Allzora:BAAANQAECgQIBgAAAA==.Aloki:BAAANQADCggIEAAAAA==.Alorarose:BAAANQAECgEIAQAAAA==.',
Am='Amberness:BAABNQAECoEdAAIBAAkKOyVLBwCIAwABAAkKOyVLBwCIAwAAAA==.Ametrius:BAAANQADCggJEAAAAA==.Ampd:BAAANQADCgYIEgAAAA==.',
An='Anastassia:BAABNQAECoEeAAIFAAgKbx0kHQDQAgAFAAgKbx0kHQDQAgAAAA==.André:BAABNQAECoEcAAIDAAkKEB6QKwDeAgADAAkKEB6QKwDeAgAAAA==.Anuke:BAAANQAECgIIAgAAAA==.',
Ar='Arestoz:BAAANQAECgcIDQAAAA==.Ariakith:BAAANQADCgEIAQAAAA==.Arkhlight:BAAANQAECgcIBwAAAA==.Arkhmonk:BAABNQAECoEaAAIGAAgKLw5wJAChAQAGAAgKLw5wJAChAQAAAA==.Armonos:BAAANQAECgYIEAAAAA==.Arowynn:BAAANQADCgUIBQABNQAECgQIBwAEAAAAAA==.Arrowhoof:BAEANQAECgQIBwAAAA==.Arthurian:BAAANQADCgEJAQAAAA==.Artémis:BAAANQADCgEIAgAAAA==.',
As='Ashiri:BAAANQABCgUIBgAAAA==.Ashmage:BAAANQAECgQJBAAAAA==.Ashmorph:BAAANQAECgUIBQABNQAECgQJBAAEAAAAAA==.Asterisk:BAABNQAECoEbAAIBAAgKqhAkVwAcAgABAAgKqhAkVwAcAgAAAA==.Astromo:BAAANQADCgMJBQAAAA==.Asya:BAAANQAECgEIAQAAAA==.',
At='Attilathepun:BAAANQADCggICAAAAA==.',
Au='Auriêl:BAAANQAECgEIAQAAAA==.',
Ax='Axxiom:BAAANQABCgUIBQAAAA==.Axxium:BAABNQAECoEqAAIHAAkKLxxOGgDVAgAHAAkKLxxOGgDVAgAAAA==.',
Az='Azastra:BAAANQAECgUICQAAAA==.Azorian:BAAANQAECgIIAQAAAA==.',
['Añ']='Aña:BAAANQAECgQIDAAAAA==.Añarchist:BAAANQADCgUJBwABNQAECgQIDAAEAAAAAA==.',
Ba='Babymonstter:BAAANQADCgEIAQAAAA==.Baelzharon:BAAANQAECgYIEAAAAA==.Baericade:BAAANQADCgMIAwABNQADCgYIBgAEAAAAAA==.Bagelpanda:BAAANQADCggIGQAAAA==.Balgrim:BAABNQAECoEVAAIIAAcKkhNxhQC2AQAIAAcKkhNxhQC2AQAAAA==.Balki:BAAANQADCgcJBwABNQAECgYIEAAEAAAAAA==.Bandicoot:BAAANQADCgYIDQAAAA==.Barsch:BAAANQADCggICAAAAA==.Basalt:BAAANQAECgUICQAAAA==.Bastenwode:BAAANQADCggIIQAAAA==.Bawce:BAAANQADCgcIDgAAAA==.',
Bb='Bbye:BAAANQADCggIDQAAAA==.',
Be='Beanboi:BAAANQADCgIIAgAAAA==.Bebynoob:BAAANQAECgYIDgAAAA==.Becký:BAAANQAECgQIDAAAAA==.Beroan:BAAANQAECgQJBAAAAA==.Bertrille:BAAANQADCgMIAwAAAA==.',
Bi='Bigcøøkie:BAAANQAECgEIAQAAAA==.Bigolcrities:BAAANQADCggJEgAAAA==.Bigshaft:BAAANQADCgYICgABNQADCggICgAEAAAAAA==.Bigwannabe:BAAANQAECgYICgAAAA==.',
Bl='Blackmagma:BAAANQAECgUIBQABNQAECgUJEQAEAAAAAA==.Blackpinkk:BAAANQAECgUIDgAAAA==.Blackppinkk:BAAANQAECgYICwAAAA==.Bloodbunny:BAAANQADCggIGwAAAA==.Blëssed:BAAANQADCgIIAgAAAA==.',
Bo='Boggartt:BAAANQAECgIIAgAAAA==.Bootscoots:BAAANQAECgYICAAAAA==.Bornite:BAAANQADCgUICgAAAA==.Bowme:BAAANQAECgQIBAAAAA==.Boyce:BAAANQAECgUIBQAAAA==.',
Br='Braedae:BAAANQAECgEIAQAAAA==.Brickaton:BAAANQAECgQIBgAAAA==.Brocknor:BAABNQAECoEaAAIIAAgKBhhhWQA7AgAIAAgKBhhhWQA7AgAAAA==.Broodling:BAAANQABCgEIAQAAAA==.',
Bu='Buckeyes:BAAANQADCgcIBwAAAA==.Butterdtoast:BAEANQAECgYIDgAAAA==.',
Bw='Bwansamdi:BAAANQADCgYIDgAAAA==.',
Ca='Cabbresoa:BAAANQAECgQICQAAAA==.Caboose:BAAANQAECgQIEAAAAA==.Cadbvucolta:BAAANQADCgUIBwAAAA==.Caledor:BAAANQAECggIDAAAAA==.Calet:BAAANQADCgYIBwAAAA==.Calindrel:BAAANQAECgYICgAAAA==.Caliriya:BAAANQADCggIFAAAAA==.Candren:BAAANQAECgEIAQAAAA==.Caraway:BAAANQAECgQIBwAAAA==.',
Ce='Celaela:BAAANQAECggIAgAAAA==.Celant:BAAANQADCggIFAAAAA==.Celson:BAAANQAECgQIBAAAAA==.Celticlore:BAAANQADCgcIFAAAAA==.Cerrvantes:BAAANQADCgcIDwAAAA==.',
Ch='Chernaboz:BAAANQAECgUIEAAAAA==.Chevelot:BAAANQADCgQIBgAAAA==.Chibbo:BAAANQAECgQIBAAAAA==.Chiblet:BAABNQAECoEYAAIJAAcKSAcwLwBZAQAJAAcKSAcwLwBZAQAAAA==.Chioma:BAAANQADCgcIDAABNQAECggIHQAKAJkQAA==.',
Ci='Ci:BAAANQADCgMIBgAAAA==.Cinccino:BAAANQAECgQIBAAAAA==.',
Cl='Cledwyn:BAAANQADCgMIAwAAAA==.Cloudsinger:BAABNQAECoEaAAIGAAkKGhlAEgCFAgAGAAkKGhlAEgCFAgAAAA==.',
Co='Codysseuz:BAAANQADCgQIBAAAAA==.Columbo:BAAANQADCgUIBQAAAA==.Combustdeez:BAABNQAECoEdAAILAAgKNSZDEACEAwALAAgKNSZDEACEAwAAAA==.Convrge:BAAANQADCgYIBwAAAA==.Corenthos:BAABNQAECoEfAAMMAAgKBBaDPADKAQAMAAgKCRODPADKAQANAAcKahLASQCNAQAAAA==.Corlys:BAAANQAECgEIAQAAAA==.Corên:BAAANQAECgEIAQAAAA==.',
Cr='Cranker:BAAANQADCgUIBQAAAA==.Crashed:BAAANQABCgUIBgAAAA==.Crazymoron:BAAANQAECgYIDgAAAA==.Creepndeath:BAAANQADCggICwAAAA==.Creselia:BAAANQAECgUICQAAAA==.Critmaw:BAAANQAECgEIAQABNQAECgkJGgALABIgAA==.Crowley:BAAANQADCgYICwAAAA==.Crum:BAAANQADCgYIBgAAAA==.Crumdumpster:BAAANQAECgYICgABNQADCgYIBgAEAAAAAA==.Crèmefraîche:BAAANQAECgYIEQAAAA==.',
Cu='Cuddlerz:BAAANQAECgQIDwAAAA==.',
Cy='Cypherrellik:BAAANQAECgQIBgABNQAECgYICwAEAAAAAA==.',
Da='Dagthunderer:BAAANQAECgMIBAAAAA==.Dakkenrahl:BAAANQADCgcICwAAAA==.Dalatras:BAAANQADCgYICAABNQAECgUICwAEAAAAAA==.Dalistra:BAAANQAECgQIBAABNQAECgUICwAEAAAAAA==.Dalweaver:BAAANQADCgUIBQABNQAECgUICwAEAAAAAA==.Damogdem:BAAANQADCgYICAAAAA==.Dangly:BAABNQAECoEYAAMDAAkKDBnhRQB3AgADAAkKDBnhRQB3AgAFAAcKhAhpgABFAQAAAA==.Dantes:BAAANQADCgMJAwAAAA==.Dar:BAAANQADCggIIAAAAA==.Darkflame:BAAANQAECgcIDwAAAA==.Darklûrker:BAAANQAECgIIAgAAAA==.Darksidedbro:BAAANQADCgUIBQAAAA==.Darkzelda:BAAANQADCggICAAAAA==.Dayve:BAABNQAECoEaAAIOAAgK7hFRMwABAgAOAAgK7hFRMwABAgAAAA==.',
Dc='Dcpt:BAAANQADCgcIFwAAAA==.',
De='Deadgeinside:BAAANQAECgQIBAAAAA==.Deadgenah:BAAANQADCgMIAwAAAA==.Deadgnome:BAAANQAECgYICAAAAA==.Deathgimbo:BAAANQAECggIDQAAAA==.Deathstomper:BAAANQAFFAEIAQAAAA==.Demondono:BAABNQAECoEbAAIKAAgKHgzTLwDLAQAKAAgKHgzTLwDLAQAAAA==.Dethalas:BAAANQADCggIDgAAAA==.Devomo:BAAANQAECgIIAgAAAA==.Deyedora:BAAANQAECgUICQAAAA==.Dezax:BAABNQAECoEYAAIPAAgKRRyzMgCDAgAPAAgKRRyzMgCDAgAAAA==.',
Di='Diaboli:BAAANQADCgQICAAAAA==.Dilligafnope:BAAANQADCgcJBwAAAA==.Dinohunter:BAAANQAECgcIDgAAAA==.Disabler:BAAANQAECgEIAQABNQAECggIHQALADUmAA==.',
Dj='Djdiddles:BAAANQAECgcIEgAAAA==.',
Do='Dorimane:BAAANQAECgYIEgAAAQ==.Dorlock:BAAANQAECgUJDgAAAA==.Dorotti:BAAANQAECgQIBAABNQAECgcIFgALAKIZAA==.Doubled:BAAANQADCgIIAgAAAA==.',
Dr='Drais:BAAANQADCgIIBQABNQADCgQIBgAEAAAAAA==.Drazgul:BAAANQADCgcIDAAAAA==.Drdukesilver:BAAANQADCgQIBAAAAA==.Dreadpanda:BAABNQAECoEuAAIIAAkKPCHyGgAuAwAIAAkKPCHyGgAuAwAAAA==.Dred:BAAANQAECgQIBAAAAA==.Dredkin:BAAANQADCgQIBAAAAA==.Dredwarrior:BAAANQADCgIIAgAAAA==.Drosmoke:BAAANQADCgUICQAAAA==.Drprodigy:BAAANQAECgUICQAAAA==.Drunkbaby:BAAANQAECgQIBQAAAA==.',
Dy='Dybuck:BAAANQAECgMIAwAAAA==.Dyrcyn:BAAANQAECgYIEAAAAA==.',
['Dà']='Dànger:BAABNQAECoEdAAQBAAkK1CF4EgAuAwABAAkK1CF4EgAuAwACAAMKygyICwDHAAAQAAQKWwpQTwCXAAAAAA==.',
Ed='Edroh:BAAANQAECgYIDAAAAA==.',
Ei='Eidur:BAAANQAECgYIEAAAAA==.Eightohfive:BAAANQADCgUIBwAAAA==.',
Ek='Ekøh:BAAANQADCgQICAAAAA==.',
El='Elará:BAAANQADCgYIBgAAAA==.Elemane:BAAANQADCgEIAQABNQAECgYIEgAEAAAAAQ==.Elemefayoh:BAABNQAECoEYAAMHAAcK2CKhIACxAgAHAAcK2CKhIACxAgARAAEKmBt06ABPAAAAAA==.Elementlo:BAABNQAECoEbAAISAAgKyCOkBQANAwASAAgKyCOkBQANAwABNQABCgIIAgAEAAAAAA==.Elsafromtemu:BAABNQAECoEXAAMTAAcK/gy1DgB3AQATAAcK/gy1DgB3AQAUAAMKfAD+CABHAAAAAA==.Elspeth:BAABNQAECoEaAAIVAAgK4h5CCgC5AgAVAAgK4h5CCgC5AgAAAA==.',
Em='Emagonarain:BAAANQAECgEIAQABNQAFFAEIAQAEAAAAAA==.Emagonasooth:BAAANQAFFAEIAQAAAA==.Emerey:BAAANQADCggIEgAAAA==.',
En='Endknightt:BAAANQADCggIDgAAAA==.Enflamee:BAAANQADCgUIBQAAAA==.Enma:BAAANQADCgQIBQAAAA==.Ennola:BAAANQADCgYJBwAAAA==.',
Ep='Ephriia:BAAANQAECgYIBgAAAA==.',
Er='Erikprince:BAAANQAECgQICgAAAA==.Erso:BAAANQADCggJEwAAAA==.',
Et='Eternalpaín:BAABNQAECoEhAAIDAAcKYB2nZAAUAgADAAcKYB2nZAAUAgAAAA==.',
Ev='Evagria:BAAANQADCgYIBgAAAA==.Evanrude:BAAANQABCggIDQAAAA==.',
Fa='Fal:BAAANQADCggIEgAAAA==.Falcyon:BAAANQADCgIIAgAAAA==.Falroot:BAAANQAECgcIEwAAAA==.',
Fe='Feliché:BAAANQAECgYIBgABNQAECggIGAAWAMQXAA==.Fevirin:BAAANQAECgQIBgAAAA==.',
Fi='Fiddlesticks:BAAANQAECgYIBgAAAA==.Firefawkes:BAAANQAECgQJBAAAAA==.Fistbump:BAABNQAECoEYAAIXAAgKfh7KCQC8AgAXAAgKfh7KCQC8AgAAAA==.',
Fl='Fletchling:BAAANQAECgcIEAAAAA==.Flizrak:BAAANQADCggIEAABNQAFFAcIEwALAJ0SAA==.',
Fo='Footsteps:BAAANQADCgcJEQAAAA==.',
Fr='Freefallen:BAAANQADCgMIAwAAAA==.Frostclot:BAABNQAECoEgAAINAAgKsB/XGQCuAgANAAgKsB/XGQCuAgAAAA==.Frostsalad:BAAANQAECgQIBgAAAA==.Frozoned:BAAANQAECggICwABNQAFFAEIAQAEAAAAAA==.',
Fu='Fulta:BAABNQAECoEVAAIQAAYK3BY7KQCyAQAQAAYK3BY7KQCyAQAAAA==.',
['Fø']='Føxhound:BAAANQADCgUIBQAAAA==.',
Ga='Garadin:BAAANQAECgIIAgAAAA==.Garnok:BAAANQAECgcICAAAAA==.Garwa:BAABNQAECoEgAAMBAAkKQyFiDwBCAwABAAkKQyFiDwBCAwAQAAMKNRWlRwC8AAAAAA==.',
Ge='Geniver:BAAANQADCggIIQAAAA==.Gerla:BAAANQAECgYIEgAAAA==.',
Gi='Gigas:BAAANQAECgUIEQAAAA==.Gilgameshh:BAABNQAECoEYAAIDAAgKnA4rgwC8AQADAAgKnA4rgwC8AQAAAA==.Girthbrooks:BAABNQAECoEbAAIYAAgKlRrWDgBtAgAYAAgKlRrWDgBtAgAAAA==.',
Gl='Glimmerfangs:BAAANQAECgYIDAAAAA==.',
Go='Gomory:BAAANQADCggIIQAAAA==.Gondark:BAAANQAECgIIAgAAAA==.Gooseblade:BAAANQABCgIIAgAAAA==.Gorgrim:BAAANQAECgEIAQAAAA==.Gorpse:BAAANQADCggIFgABNQAECgYIEgAEAAAAAA==.',
Gr='Grantham:BAAANQABCgQIBAAAAA==.Graverael:BAAANQADCgcICQAAAA==.Gretchen:BAABNQAECoEfAAIMAAkKfx4NEQD/AgAMAAkKfx4NEQD/AgABNQAECgkJJQAQADgbAA==.Greyley:BAAANQAECgQIBAABNQABCgIIAgAEAAAAAQ==.Greywolf:BAABNQAECoEbAAIHAAcKcBtfRAADAgAHAAcKcBtfRAADAgAAAA==.Grimlight:BAAANQAECgcIDAABNQAFFAQIBAAEAAAAAA==.Grymmhain:BAAANQADCggICAAAAA==.',
Gw='Gwawls:BAAANQADCgcIBwABNQAECgQIBAAEAAAAAA==.',
['Gä']='Gärry:BAAANQAECgMIBQAAAA==.',
Ha='Hanzoff:BAAANQADCgQIBAAAAA==.Harrow:BAAANQAECgUICQAAAA==.Haxx:BAABNQAECoEaAAMYAAgKehBFFgAMAgAYAAgKHxBFFgAMAgAZAAEKaQc8dAA6AAAAAA==.',
He='Healls:BAAANQADCgUIBQAAAA==.Hearge:BAABNQAECoEXAAMVAAkKRQiDJABgAQAVAAkKRQiDJABgAQAFAAEK5AGtAgEeAAAAAA==.Hellhawk:BAAANQAECgUICQAAAA==.Hevydevy:BAAANQAECgcIEQAAAA==.Hexhain:BAABNQAECoEXAAIaAAgKmgugEgDPAQAaAAgKmgugEgDPAQAAAA==.',
Ho='Hockay:BAAANQAECgYJDwAAAA==.Holygun:BAAANQAECgcIDQAAAA==.Holyshiets:BAAANQADCgUIBQAAAA==.Holyshiza:BAAANQAECgQIDAAAAA==.Holysmokess:BAAANQAECgQIBAAAAA==.Holystan:BAAANQAECgEIAQAAAA==.Hondoe:BAAANQAECgUJBwAAAA==.Hopi:BAAANQABCgQIBAAAAA==.',
Ht='Htownglaivez:BAAANQADCgYIBgABNQAECgMIAwAEAAAAAA==.Htownhots:BAAANQAECgMIAwAAAA==.Htownprot:BAAANQADCgMIAwABNQAECgMIAwAEAAAAAA==.Htownshaman:BAAANQADCgcIDgABNQAECgMIAwAEAAAAAA==.',
Hu='Humblepotato:BAAANQADCgEIAgAAAA==.Hungsten:BAAANQAECgEIAQABNQAECgkJGAADAAwZAA==.Huntfromhell:BAABNQAECoEYAAIKAAgKORksIABPAgAKAAgKORksIABPAgAAAA==.',
Ic='Iceagaint:BAAANQADCgQIBQAAAA==.Icedpissfox:BAAANQADCgUJBwAAAA==.',
Id='Idonttank:BAAANQADCggIEgAAAA==.',
Il='Illio:BAAANQAECgQIBgAAAA==.',
Im='Imarea:BAAANQAECgYIEAAAAA==.Impirious:BAABNQAECoEgAAINAAgKoxSqPADOAQANAAgKoxSqPADOAQAAAA==.Implumz:BAAANQADCgMIAwABNQAECggIIAANAKMUAA==.Imptard:BAAANQADCgIIAgABNQAECggIIAANAKMUAA==.Imyx:BAAANQAECgUICQAAAA==.',
In='Incubussy:BAAANQADCgcIBwABNQAECgkJKwAbAKsiAA==.Infamuspikel:BAABNQAECoEVAAIMAAcKyhkAMwACAgAMAAcKyhkAMwACAgAAAA==.Infel:BAAANQAECgIICAAAAA==.Inkkish:BAAANQAECgUIDQAAAA==.Innovates:BAABNQAECoEgAAIVAAkKZxa7EgAnAgAVAAkKZxa7EgAnAgAAAA==.Interstellar:BAAANQAECgQIBAAAAA==.Intervene:BAAANQADCgYJFAABNQAECgcIIQADAGAdAA==.Invictus:BAABNQAECoEcAAILAAgK1w9OmgAHAgALAAgK1w9OmgAHAgAAAA==.',
Is='Isaßeau:BAAANQADCgEIAQAAAA==.Ist:BAAANQAECgMIAwAAAA==.',
Iz='Izuael:BAAANQAECgYJBgAAAA==.',
Ja='Jackjr:BAAANQADCgQIBgAAAA==.Jadea:BAAANQADCgUIBQAAAA==.Jahdar:BAAANQABCgQIBAAAAA==.Jalim:BAAANQADCgcIBwAAAA==.Jamesy:BAAANQADCgQJBAABNQAFFAQICAAIAAoZAA==.Jandoar:BAAANQAECgUICQAAAA==.Jarlen:BAAANQADCgEIAQAAAA==.Jaylea:BAABNQAECoEbAAIaAAcKcQokGwCGAQAaAAcKcQokGwCGAQAAAA==.Jaynee:BAAANQABCgUIBgAAAA==.',
Je='Jegallidin:BAAANQADCgEIAgAAAA==.Jetpilot:BAAANQAECgMIAwAAAA==.Jeypi:BAAANQAECgUICgAAAA==.',
Ji='Jiq:BAAANQAECgUICwAAAA==.',
Jo='Johli:BAAANQADCggICAAAAA==.',
Ju='Judikai:BAAANQAECgUICQAAAA==.Junesong:BAAANQAECgQIDQAAAA==.Justwipeit:BAAANQADCggJCAAAAA==.',
Ka='Kabilos:BAAANQADCggJEAAAAA==.Kaedian:BAAANQAECgQIBAABNQAECgYIFQAGAPEgAA==.Kalesmora:BAABNQAECoEaAAIIAAgKpA+seQDZAQAIAAgKpA+seQDZAQAAAA==.Kamikaze:BAAANQAECgQIBgAAAA==.Karlov:BAAANQAECgcICwAAAA==.Karthis:BAAANQADCggIDAAAAA==.Kazera:BAAANQADCgMIBAAAAA==.Kazgrim:BAAANQADCgYICgAAAA==.',
Ke='Keanah:BAAANQAECgUIEQAAAA==.Kelrosh:BAAANQABCgIJAgAAAA==.Keynn:BAAANQADCgUIBQABNQAECgYIFQAGAPEgAA==.',
Kh='Kheims:BAAANQAECgQIBQAAAA==.Khrom:BAAANQADCgIIAgAAAA==.Khytoem:BAAANQAECgQICAAAAA==.',
Ki='Killduran:BAAANQAECgUICgAAAA==.Kimaga:BAAANQADCgUICQABNQAECgYIEgAEAAAAAA==.Kindle:BAAANQAECgQIBAAAAA==.Kirasha:BAAANQADCgQIBAAAAA==.Kitom:BAAANQAECgYIDQAAAA==.Kiwia:BAAANQAECgcIEgAAAA==.',
Kl='Klunt:BAAANQADCgEIAQABNQAECgYIEgAEAAAAAA==.',
Ko='Kochiyo:BAAANQABCgcIDAAAAA==.Kolaniber:BAAANQABCgEIAQAAAA==.Korkrum:BAAANQAECgEIAQAAAA==.',
Kr='Kracked:BAAANQADCgMIAgAAAA==.Krank:BAAANQADCgUIDAABNQADCgkJCQAEAAAAAA==.Krellyroll:BAAANQAECgEIAQABNQAECgYIEAAEAAAAAA==.Krelthyr:BAAANQAECgYIEAAAAA==.Krumm:BAABNQAECoEfAAIcAAgKfAq6FAB9AQAcAAgKfAq6FAB9AQAAAA==.Kruul:BAAANQABCgQJBAAAAA==.',
Ku='Kuhne:BAAANQADCggJFQAAAA==.Kungfudrew:BAAANQADCggICAAAAA==.',
Ky='Kyber:BAAANQAECgIIAwAAAA==.Kyther:BAAANQAECgQIBwAAAA==.',
['Kñ']='Kñightboat:BAAANQAECgUICQAAAA==.',
La='Ladeiene:BAAANQAECgQIBgAAAA==.Laelwyn:BAAANQADCggIFwAAAA==.Laelynd:BAAANQADCgYICgAAAA==.Laeritides:BAAANQADCgYICQABNQAECgUICQAEAAAAAA==.Laeritidesdk:BAAANQAECgUICQAAAA==.Lastditch:BAAANQAECgMIAwAAAA==.Lateralas:BAAANQADCggJEQAAAA==.',
Le='Leonard:BAAANQAECgcIBQAAAA==.Leothedog:BAAANQAECgYICwAAAA==.Lethas:BAAANQADCgMIAwAAAA==.Leukheimsia:BAAANQADCgUJBQABNQAECgQIBQAEAAAAAA==.',
Li='Lichgibber:BAAANQAECgEIAQAAAA==.Liere:BAAANQADCgcIDAAAAA==.Lightrising:BAAANQADCgcICAAAAA==.Lilenalol:BAAANQADCgcIEwAAAA==.Lilfiorella:BAAANQADCgYIDAAAAA==.Lilmonstrman:BAABNQAECoEaAAILAAcKIhdnnwD7AQALAAcKIhdnnwD7AQAAAA==.Liltree:BAAANQAECgUICwAAAA==.Limbbiscuit:BAABNQAECoEZAAMBAAcK2hqvSABHAgABAAcK2hqvSABHAgAQAAQKrgMBTwCZAAAAAA==.Listmonk:BAAANQAECgEIAQAAAA==.',
Ll='Llothae:BAAANQAECgUICQAAAA==.',
Lo='Lonjick:BAAANQADCgIIAgAAAA==.Lots:BAAANQADCgcIGAAAAA==.Loyalty:BAAANQAECgIIBQAAAA==.',
Lu='Lucinsia:BAAANQADCgQIBAAAAA==.Lul:BAABNQAECoEhAAIIAAkKCSLCGQA0AwAIAAkKCSLCGQA0AwAAAA==.Luminar:BAAANQAECgEIAQAAAA==.Lunaaru:BAAANQADCgMIAwAAAA==.Luvrstriplet:BAAANQADCggIDgAAAA==.',
['Lð']='Lðvergirl:BAAANQAECgYIDgAAAA==.',
Ma='Madcow:BAAANQAECgQIBgAAAA==.Maelk:BAAANQADCgQIBQABNQAECgEIAQAEAAAAAA==.Magistella:BAAANQAECgIIAgAAAA==.Maisrii:BAEANQAECgUIBwAAAA==.Maivz:BAABNQAECoEaAAMFAAcKew/KZQCXAQAFAAcKew/KZQCXAQADAAEKjwRqXgEqAAAAAA==.Malignantt:BAABNQAECoEbAAINAAgKHQ4CRgCfAQANAAgKHQ4CRgCfAQAAAA==.Maloch:BAAANQADCgIIAgAAAA==.Mapletoast:BAAANQADCgQIBAAAAA==.Marthren:BAAANQADCgUICQAAAA==.Marzyna:BAAANQADCgkJCQAAAA==.Maurphious:BAAANQADCggIHAAAAA==.',
Me='Mekaniker:BAAANQABCgMIAwAAAA==.Melbee:BAAANQAECgYIDwAAAA==.Melodrama:BAAANQAECgQIBgAAAA==.Metri:BAAANQABCgUIBwAAAA==.',
Mi='Micassa:BAAANQADCgIIAgAAAA==.Michaeljrdan:BAAANQADCgQIBAAAAA==.Mikela:BAAANQAECgQIDQABNQAECgcIFgALAKIZAA==.Milkee:BAAANQADCgEIAQAAAA==.Mirgaree:BAAANQAECgYIEgAAAA==.Mirjelys:BAAANQAECgEJAQAAAA==.',
Mo='Moarass:BAAANQAECgcIEwAAAA==.Monty:BAAANQADCggJFQAAAA==.Moodswingz:BAAANQADCgIIAwAAAA==.Mordos:BAAANQADCgMIAwAAAA==.',
Mu='Muffinz:BAAANQAECgQJBwABNQAECgYICAAEAAAAAA==.Mugo:BAAANQADCgUIBgABNQAECggIGAAWAMQXAA==.Multiabuse:BAAANQAECgMIAgAAAA==.Multipass:BAAANQABCgEJAQAAAA==.',
My='Myau:BAAANQAECgUJBQAAAA==.Mylou:BAAANQAECgQJBQAAAA==.Mynia:BAABNQAECoEfAAICAAgKzgUiBwCxAQACAAgKzgUiBwCxAQAAAA==.',
Na='Nano:BAAANQAECgYIEgAAAA==.Nazdreg:BAAANQAECgUIEAAAAA==.',
Ne='Negan:BAAANQABCgUIBQAAAA==.Neotoldir:BAABNQAECoEaAAIdAAgKXRJtKQDtAQAdAAgKXRJtKQDtAQAAAA==.Nerfdisc:BAAANQAECgIIAgAAAA==.Nevershocked:BAAANQAECgYIEwAAAA==.',
Ni='Ninjaznpariz:BAAANQADCgQJBAAAAA==.',
No='Noblewrack:BAAANQADCgEIAQAAAA==.Noobles:BAAANQAECgEIAQAAAA==.Nordie:BAAANQADCggICAAAAA==.Northik:BAAANQADCgUIBQABNQAECgcIEwAEAAAAAA==.Nosredna:BAAANQAECgMIBAAAAA==.Nosrednàx:BAAANQADCgUIBQAAAA==.Notintheface:BAAANQADCgQIBAAAAA==.Novata:BAAANQADCgUIBQABNQAECgIIAgAEAAAAAA==.',
Nu='Nuzz:BAACNQAFFIEPAAIIAAUK/iI2BgD/AQAIAAUK/iI2BgD/AQA1AAQKgR4AAggACQrIJQINAH4DAAgACQrIJQINAH4DAAAA.',
Ny='Nydav:BAABNQAECoEVAAIGAAYK8SBOFwA+AgAGAAYK8SBOFwA+AgAAAA==.',
Ob='Obalma:BAAANQAECgYJEgAAAA==.',
Od='Odwalla:BAABNQAECoEbAAIBAAkKkCLFCgBmAwABAAkKkCLFCgBmAwAAAA==.',
Ol='Olmec:BAAANQAECgMIBQAAAA==.Olmek:BAAANQAECgIIAgAAAA==.',
On='Onlydesert:BAABNQAECoEWAAMLAAcKohkNjAAnAgALAAcKohkNjAAnAgAUAAEKKhEXCQBGAAAAAA==.Onranui:BAAANQADCgcIDQAAAA==.',
Oo='Oopsyourdead:BAAANQAECgUICgAAAA==.',
Op='Optiks:BAAANQAECgYIDgAAAA==.',
Or='Orcfan:BAAANQABCgIJAgAAAA==.Orksauce:BAABNQAECoEmAAMYAAgKkh/1FAAbAgAYAAYKBB/1FAAbAgAZAAIKPSF7WgCyAAAAAA==.Orphella:BAAANQAECgEIAQAAAA==.',
Os='Osares:BAAANQAECgYIDwAAAA==.Osong:BAAANQADCgcIBwABNQAECgQIBAAEAAAAAA==.',
Ou='Outtamanna:BAAANQADCgUICQAAAA==.',
Ow='Owils:BAAANQADCgYIBgABNQAECggIHwAMAAQWAA==.',
Ox='Oxl:BAAANQADCgQIBAAAAA==.',
['Oß']='Oß:BAAANQAECgEIAQABNQAECgQIBwAEAAAAAA==.',
Pa='Pagophobia:BAAANQAECgMIAwAAAA==.Pallytree:BAAANQAECgIIAgAAAA==.Papiblanco:BAAANQADCggICgAAAA==.Pariahdruid:BAAANQAECgQIBAAAAA==.',
Pe='Percepcions:BAAANQAECgUIBwAAAA==.Percksmash:BAAANQAECggIDAAAAA==.Perkyl:BAAANQAECgIIAwAAAA==.',
Ph='Phage:BAAANQADCggICAABNQAECgYIEgAEAAAAAA==.Philon:BAAANQADCgEIAQAAAA==.Photophobia:BAABNQAECoEaAAIJAAkKlB98DQDnAgAJAAkKlB98DQDnAgAAAA==.',
Pi='Piezo:BAAANQADCgQIBgAAAA==.Pikevarr:BAAANQADCggJEAAAAA==.Pivy:BAAANQADCgYIBgABNQAECggIGAAXAH4eAA==.',
Pk='Pkrage:BAABNQAECoEhAAMcAAgKVx0YCACIAgAcAAgKVx0YCACIAgAIAAEKOBIsHwEuAAAAAA==.',
Pl='Plaugez:BAAANQABCgIIAwAAAA==.Plazlie:BAABNQAECoEiAAMeAAkKzCPLAQBEAwAeAAgK9yPLAQBEAwAIAAEKciIHAgFmAAAAAA==.Ploppstein:BAEANQAECgYIEQAAAA==.',
Po='Polyethylene:BAAANQAECgcIEQAAAA==.Poucastranca:BAABNQAECoEpAAMaAAgK/iQ5NwDQAAAaAAMKuSQ5NwDQAAAPAAcKpyR57QB0AAAAAA==.',
Pu='Punkpikachu:BAAANQADCgcIFwAAAA==.',
Pw='Pwnman:BAAANQADCgUIBQAAAA==.',
Qk='Qkoira:BAAANQAECgQICgAAAA==.',
Qu='Quanlain:BAAANQAECgUICQAAAA==.Quillathe:BAABNQAECoEbAAMbAAgKGBIaEADyAAAWAAYKrxVwYACbAQAbAAUKLQcaEADyAAAAAA==.',
Ra='Raagh:BAAANQAECgQIBAAAAA==.Rancore:BAAANQAECgQICgABNQAECgUICwAEAAAAAA==.Rashdar:BAABNQAECoEiAAIDAAgKRx3hQgCCAgADAAgKRx3hQgCCAgAAAA==.Rasto:BAAANQADCgYICQABNQAECgQJBwAEAAAAAA==.Rattpacck:BAAANQADCgUIBgAAAA==.Rattpack:BAAANQAECgQICQAAAA==.Raves:BAAANQAECgQIBgAAAA==.Rayvynn:BAAANQADCgIJAgAAAA==.',
Re='Regilz:BAAANQADCgMIAwAAAA==.',
Rh='Rhys:BAAANQADCgMIAwAAAA==.',
Ri='Ribeyye:BAAANQAECgUICQAAAA==.Rider:BAAANQAECgEIAQAAAA==.Rigormortiis:BAAANQAECgEIAQAAAA==.Rilde:BAAANQADCgYIGAAAAA==.Rinjiabri:BAAANQAECgIIAgAAAA==.',
Ro='Robroy:BAAANQAECggICQAAAA==.Robrøy:BAAANQADCggJGQAAAA==.Rokmage:BAAANQAECgMIBAAAAA==.Roseclaw:BAEANQAECgIIAgABNQAECggIHQABAJghAA==.Roseclawed:BAEBNQAECoEdAAIBAAgKmCEaGwD5AgABAAgKmCEaGwD5AgAAAA==.Roxso:BAACNQAFFIETAAMLAAcKnRKACQDxAQALAAYKzRGACQDxAQATAAEKfRe8BgBhAAA1AAQKgS8AAwsACQpwIP8uABQDAAsACQpuIP8uABQDABMABgp6DFUWAAgBAAAA.',
Ru='Rukaiz:BAAANQAECgYIEQAAAA==.',
['Rë']='Rëdmagma:BAAANQAECgUJEQAAAA==.',
['Rò']='Ròbroy:BAAANQAECggJCQAAAA==.',
['Ró']='Rónan:BAAANQAECgEJAQAAAA==.',
['Rû']='Rûsh:BAAANQADCggJEAAAAA==.',
Sa='Sacrelicious:BAAANQAECgUIBQAAAA==.Saennah:BAAANQADCgIJAgAAAA==.Sagewynn:BAAANQAECgQIBwAAAA==.Sainei:BAAANQADCgUIBQABNQAECggIHAAIAP8aAA==.Salfroc:BAABNQAECoEeAAIfAAgKuxaABABRAgAfAAgKuxaABABRAgAAAA==.Samhain:BAABNQAECoEcAAIgAAgKGQ1tJQDeAQAgAAgKGQ1tJQDeAQAAAA==.Sanasianana:BAAANQADCgUIBQABNQAFFAEIAQAEAAAAAA==.Saplo:BAAANQAECgUICQAAAA==.Sapphirosa:BAAANQAECgEIAQABNQAECgkJGgAGABoZAA==.Sarif:BAAANQAECgQICAAAAA==.Saxel:BAAANQAECgEIAQAAAA==.',
Sc='Scallop:BAAANQADCgQIBAAAAA==.Schwarzenman:BAAANQADCgEIAQAAAA==.',
Se='Segio:BAAANQAECgEIAQAAAA==.Selcia:BAAANQADCggJEAAAAA==.Serenati:BAAANQAECgUICQAAAA==.Seïya:BAAANQADCggIIAAAAA==.',
Sg='Sgthulka:BAAANQADCgQJBAAAAA==.',
Sh='Shamawockee:BAAANQAECgQICgABNQAECggIHgABACsfAA==.Shango:BAAANQADCgUIBQAAAA==.Sharavia:BAAANQAECgYIDgAAAA==.Shasu:BAAANQADCgEIAQAAAA==.Shaundi:BAAANQADCggJFQAAAA==.Shautistic:BAAANQADCgYIBgAAAA==.Shocktuah:BAABNQAECoEfAAIRAAgKVCTtEQA+AwARAAgKVCTtEQA+AwAAAA==.Shonúff:BAAANQAECgcIEgAAAA==.Shotaru:BAAANQAECgQIBwAAAA==.Shotpace:BAAANQAECgQICAAAAA==.Showerhandle:BAAANQADCgMIAwAAAA==.Shui:BAAANQAECgEIAQABNQAECgQIBAAEAAAAAA==.Shädöw:BAAANQADCgIIAgAAAA==.',
Si='Silmeria:BAAANQAECgcIDQAAAA==.Sinful:BAABNQAECoEhAAMeAAgKSw7QCgDNAQAeAAgKSw7QCgDNAQAIAAEKrwchKAEiAAAAAA==.',
Sk='Skalagrim:BAAANQADCggIDwAAAA==.Skeptyk:BAABNQAECoEaAAIWAAgKdhwBKACOAgAWAAgKdhwBKACOAgAAAA==.Sko:BAEBNQAECoEgAAMFAAgKdxuEKACRAgAFAAgKdxuEKACRAgADAAYKqgpBygATAQABNQADCgcJCQAEAAAAAA==.Skol:BAAANQAECgcIEgAAAA==.Skolivia:BAEANQADCgcJCQAAAA==.',
Sm='Smiley:BAAANQAECgMIAwAAAA==.Smitti:BAAANQAECgQIBAABNQAECgcIFgALAKIZAA==.Smokeydabear:BAAANQADCgEIAQAAAA==.Smug:BAABNQAECoEXAAIgAAcKJCWzDgDdAgAgAAcKJCWzDgDdAgAAAA==.',
Sn='Snapee:BAAANQAECgIIAwAAAA==.Sniffledoo:BAAANQAECgYIDgAAAA==.Snuwuf:BAAANQADCgcICwAAAA==.',
So='Sockz:BAAANQAECgEIBAAAAA==.Soonmia:BAAANQADCgQIBAAAAA==.Sourfangs:BAABNQAECoEYAAMIAAgK3iJpLgDVAgAIAAgK3iJpLgDVAgAeAAEKpCJeIABiAAAAAA==.Soxx:BAAANQADCgYICwABNQAECggIGgAYAHoQAA==.',
Sp='Spicypeño:BAABNQAECoEiAAIhAAkKDiGbAwBOAwAhAAkKDiGbAwBOAwABNQAFFAcIHQAhAGchAA==.Spicý:BAABNQAECoEZAAILAAkKUSEbKgAkAwALAAkKUSEbKgAkAwAAAA==.Splack:BAABNQAECoEeAAIBAAgKKx9DJwDAAgABAAgKKx9DJwDAAgAAAA==.Splithoofe:BAEANQADCgUIBgABNQAECgQIBwAEAAAAAA==.Sprawl:BAAANQAECgYIEAAAAA==.Sprawlher:BAAANQAECgQIBgABNQAECgYIEAAEAAAAAA==.',
Sq='Squrrlydan:BAEANQAECgQJBAAAAA==.',
St='Stabzuplenty:BAAANQAECgIIAgABNQAFFAcIEwALAJ0SAA==.Staint:BAAANQAECgYIEgAAAA==.Staints:BAAANQAECgMIAwABNQAECgYIEgAEAAAAAA==.Starnights:BAAANQAECgQJBQAAAA==.Starstrike:BAAANQAECggICAAAAA==.Statman:BAAANQAECgUICQAAAA==.Steelbubble:BAABNQAECoEYAAMIAAkKkxwmOgCmAgAIAAkKxhomOgCmAgAeAAMKViLYFAD8AAAAAA==.Stella:BAAANQAECgIIAgAAAA==.Stengah:BAABNQAECoEbAAIiAAgKkxy0DgCRAgAiAAgKkxy0DgCRAgAAAA==.Stonebrew:BAAANQABCgEIAQAAAA==.Strela:BAAANQAFFAEIAQAAAQ==.',
Su='Suraki:BAABNQAECoEdAAIKAAgKmRAGLADqAQAKAAgKmRAGLADqAQAAAA==.',
Sv='Svetlian:BAAANQADCgMIAwABNQAFFAEIAQAEAAAAAA==.',
Sw='Swtblsphmy:BAAANQAECgQICAAAAA==.',
Sy='Sylverwolf:BAAANQADCgEIAQAAAA==.Sylvestrus:BAAANQAECgQIBAABNQAECggIGAAWAMQXAA==.',
['Sä']='Säber:BAAANQADCgcIBwAAAA==.',
['Sè']='Sèd:BAABNQAECoEgAAIWAAgK/xs3JACiAgAWAAgK/xs3JACiAgAAAA==.Sèitheach:BAAANQADCggJDgAAAA==.',
['Sí']='Síd:BAABNQAECoEdAAMfAAkKMQ0OCgCGAQAPAAkKMglHYgDhAQAfAAYKVg8OCgCGAQAAAA==.',
Ta='Tahrin:BAAANQAECgUIEQAAAA==.Talamon:BAABNQAECoEaAAIjAAgKxhSLDAD2AQAjAAgKxhSLDAD2AQAAAA==.Tamerlynn:BAAANQADCgUIBAAAAA==.Tandruid:BAABNQAECoEiAAIOAAgKfB/zGADTAgAOAAgKfB/zGADTAgAAAA==.Tarasis:BAAANQADCgEIAQAAAA==.Tashi:BAAANQAECgUIEgAAAA==.Tasina:BAAANQADCgUIBgAAAA==.Taurenamos:BAABNQAECoEiAAMOAAgK1xNtNwDkAQAOAAcK0RVtNwDkAQAkAAcKZhCvJQCSAQAAAA==.Taynam:BAAANQAECgQICAABNQAECgUICwAEAAAAAA==.',
Te='Tempëst:BAAANQAECgIJAgAAAA==.Tenchu:BAAANQAECgYIDwAAAA==.Tendra:BAAANQADCgMIAwAAAA==.Tenseven:BAAANQAECgQICAAAAA==.Terrørßlade:BAAANQAECgEIAQABNQAECgUICQAEAAAAAA==.',
Th='Thalorain:BAAANQADCgYIFAABNQAECgEIAQAEAAAAAA==.Thark:BAAANQADCgIIAgABNQAECggIHQARAG8lAA==.Thatdruid:BAAANQAECgEIAQAAAA==.Thicknfluffy:BAAANQABCgEIAgAAAA==.Throwd:BAABNQAECoEdAAIYAAgKMw43FwACAgAYAAgKMw43FwACAgAAAA==.Thundah:BAAANQAECgEIAQAAAA==.Thurk:BAABNQAECoEdAAIRAAgKbyVWDgBbAwARAAgKbyVWDgBbAwAAAA==.',
Ti='Tideshunter:BAABNQAECoEcAAMBAAkKCRzjMwCOAgABAAgKghzjMwCOAgAQAAgKIhIaIwDxAQAAAA==.Tinytony:BAABNQAECoEXAAMVAAcKDhdBGADeAQAVAAcKzhZBGADeAQADAAIKdQo+GwF2AAAAAA==.Tinyweakling:BAAANQAECgEIAQABNQAECgcIEAAEAAAAAA==.',
To='Toranis:BAAANQADCgQIBwAAAA==.Torrents:BAABNQAECoEfAAMHAAgKkyVsCgBNAwAHAAgKkyVsCgBNAwARAAEKMwx78wA7AAAAAA==.Totemik:BAAANQAECgEIAQAAAA==.Touchofchaos:BAAANQADCggICAAAAA==.',
Tr='Trailerpark:BAAANQAECggIBgAAAA==.Triepas:BAAANQAECgUICQAAAA==.Trinytee:BAABNQAECoEXAAIBAAYKgxg7fwCuAQABAAYKgxg7fwCuAQAAAA==.Trippytotem:BAABNQAECoEbAAMRAAcK1wtzZgCZAQARAAcK1wtzZgCZAQAHAAQKSgWWuwCfAAAAAA==.Trolltoll:BAAANQADCgEIAQAAAA==.Trollypolly:BAAANQABCgMIAQAAAA==.',
Ty='Tyriäel:BAABNQAECoEWAAMMAAcKax7pKQA7AgAMAAcKVx3pKQA7AgANAAcKIxv/MQAGAgAAAA==.Tyrrible:BAAANQAECggIAQAAAA==.',
['Tà']='Tàyla:BAAANQADCgQIBAABNQAECgYIFwABAIMYAA==.',
Ug='Ugolino:BAAANQADCgEIAQAAAA==.',
Ul='Ulther:BAAANQADCggJEAAAAA==.',
Va='Vacare:BAAANQADCggJEAAAAA==.Valdyria:BAAANQADCgUIDwAAAA==.Valistar:BAAANQAECgIIAgAAAA==.Valkoienne:BAAANQADCgQJCQAAAA==.Varnashar:BAAANQADCgYIBgAAAA==.Vavictus:BAAANQADCggJEAAAAA==.Vazaenei:BAAANQABCgMIAwAAAA==.',
Ve='Vedronorael:BAAANQADCgcJBgAAAA==.Veinos:BAAANQAECggIDwAAAQ==.Velanthia:BAAANQADCgcIBwAAAA==.Velora:BAAANQAECgIIBAAAAA==.Vengrath:BAAANQAECgYIDgAAAA==.Verderben:BAAANQAECgQIBwAAAA==.Verind:BAAANQAFFAEIAQAAAA==.',
Vi='Vinhelsin:BAAANQADCgYIDwAAAA==.',
Vo='Voideater:BAAANQADCgEIAQAAAA==.Voron:BAABNQAECoEfAAIDAAYKGhblkQCWAQADAAYKGhblkQCWAQAAAA==.',
Vu='Vulperra:BAABNQAECoEXAAIIAAgKlREncgDvAQAIAAgKlREncgDvAQAAAA==.',
Vy='Vynessa:BAAANQADCgMJAwAAAA==.',
Wa='Wade:BAAANQAECgcICAAAAA==.Walk:BAAANQADCgYIBgAAAA==.Waq:BAAANQAECgYIEAAAAA==.Waterwhip:BAAANQAECgcIEwAAAA==.',
We='Wemeo:BAAANQAECgEJAQAAAA==.Westfall:BAABNQAECoEYAAMNAAcKrB4zJQBaAgANAAcKrB4zJQBaAgAMAAIKKAI1qAA+AAAAAA==.',
Wi='Willowweewoo:BAAANQAECgcIBwAAAA==.Willrun:BAAANQAECgMIAwAAAA==.Wipeit:BAAANQADCgIIAgAAAA==.',
Wo='Wolfbayne:BAAANQAECgUIBwAAAA==.Wompeal:BAAANQAECgYIDgAAAA==.Wonkwonk:BAAANQAECgYIDgAAAA==.Worth:BAABNQAECoEgAAIDAAgKzx4bNwCuAgADAAgKzx4bNwCuAgAAAA==.',
Wr='Wrukolas:BAAANQAECgYIDwAAAA==.',
Wy='Wystan:BAABNQAECoEdAAIHAAgKwx7FHwC2AgAHAAgKwx7FHwC2AgAAAA==.',
['Wè']='Wès:BAAANQADCgEIAQAAAA==.',
['Wé']='Wés:BAAANQAECgcIEwAAAA==.',
Xa='Xamsuciteey:BAAANQADCgUIBQAAAA==.Xandritten:BAAANQABCgIIAgAAAA==.Xanthe:BAAANQAECgYIEgAAAA==.Xavin:BAAANQADCgcICQAAAA==.',
Xe='Xentow:BAABNQAECoEbAAIBAAgKOAWuhwCZAQABAAgKOAWuhwCZAQAAAA==.',
Ya='Yamling:BAAANQADCggIGwAAAA==.Yayaka:BAAANQADCgcIEgAAAA==.',
Yi='Yizdano:BAABNQAECoEmAAMZAAkKCBcnGABqAgAZAAgKUBknGABqAgAYAAkKdQoTFgAOAgAAAA==.',
Yu='Yukiina:BAAANQADCgcIEQAAAA==.Yungbean:BAAANQAECgQIBwAAAA==.',
['Yû']='Yûm:BAAANQADCggICgAAAA==.',
Za='Zaccheus:BAAANQAECgMIAwABNQAECggIGAAWAMQXAA==.Zambora:BAAANQADCgcICgAAAA==.Zamwi:BAAANQAECgQIBgAAAA==.',
Ze='Zeebra:BAAANQAECgQIBQAAAA==.Zeesaw:BAAANQAECgYIEwAAAA==.Zenden:BAAANQADCggIIQAAAA==.Zeretrix:BAABNQAECoEcAAMLAAcKnB2XfgBHAgALAAcK6xyXfgBHAgATAAQKFhFGGwDSAAAAAA==.Zerospace:BAABNQAECoEdAAIDAAgK7QvOiwClAQADAAgK7QvOiwClAQAAAA==.',
Zl='Zlutar:BAAANQAECgQIBgAAAA==.',
Zy='Zynos:BAAANQAECgcIEgAAAA==.Zynothrian:BAAANQADCgMIAwAAAA==.',
['Ça']='Çalindrel:BAAANQADCgUIBQAAAA==.',
['Úà']='Úà:BAAANQADCgIIAQABNQAECgQICgAEAAAAAA==.',
['Üb']='Überhealz:BAABNQAECoEYAAMWAAgKxBfsTADqAQAWAAgKxBfsTADqAQAJAAMKWAskSAChAAAAAA==.',
['ßö']='ßöw:BAABNQAECoEfAAIBAAgKASG+JADLAgABAAgKASG+JADLAgAAAA==.',
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
