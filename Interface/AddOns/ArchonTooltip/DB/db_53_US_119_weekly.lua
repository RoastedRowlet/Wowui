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

local lookup = {'Hunter-BeastMastery','Hunter-Survival','Mage-Frost','Paladin-Retribution','Unknown-Unknown','Paladin-Holy','Monk-Windwalker','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','Mage-Fire','Warrior-Arms','Evoker-Preservation','Warlock-Destruction','Priest-Shadow','DemonHunter-Havoc','Mage-Arcane','DeathKnight-Unholy','Shaman-Enhancement','Druid-Balance','Warlock-Demonology','Hunter-Marksmanship','Rogue-Assassination','Paladin-Protection','Priest-Holy','Monk-Mistweaver','Rogue-Subtlety','Druid-Feral','Priest-Discipline','Evoker-Devastation','Warrior-Protection','Druid-Restoration','DeathKnight-Frost','Evoker-Augmentation','Warrior-Fury','Warlock-Affliction','DemonHunter-Devourer','Rogue-Outlaw','Monk-Brewmaster',}
local provider = {region='US',realm='Hellscream',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aarix:BAABNQAECoEiAAMBAAgK9BlyQQCCAgABAAgKuBlyQQCCAgACAAIKyA0KDwBlAAAAAA==.',
Ac='Achmed:BAAANQAECgEIAQAAAA==.',
Ad='Addÿ:BAABNQAECoEYAAIDAAUK7iCQDAC7AQADAAUK7iCQDAC7AQAAAA==.',
Ae='Aelasong:BAACNQAFFIEFAAIEAAMKPhMiEgDuAAAEAAMKPhMiEgDuAAA1AAQKgR8AAgQACQrWH8AzANwCAAQACQrWH8AzANwCAAE1AAMKBQgFAAUAAAAA.Aelinessa:BAAANQAECgYICgAAAA==.',
Af='Afflíctd:BAAANQADCgcICAAAAA==.',
Al='Aldrîch:BAAANQAECgQICgAAAA==.Allyra:BAAANQAECgYIDAAAAA==.Allzerim:BAAANQADCgYIBQABNQAECgUICwAFAAAAAA==.Allzora:BAAANQAECgUICwAAAA==.Aloki:BAAANQAECgYIBgAAAA==.Alorarose:BAAANQAECgEIAQAAAA==.',
Am='Amberness:BAABNQAECoEjAAIBAAkKOyW9CQCAAwABAAkKOyW9CQCAAwAAAA==.Ametrius:BAAANQADCggJEAAAAA==.Ampd:BAAANQADCgYIEgAAAA==.',
An='Anastassia:BAABNQAECoEnAAIGAAgKER41IgDMAgAGAAgKER41IgDMAgAAAA==.André:BAABNQAECoElAAIEAAkKKyCUHQA3AwAEAAkKKyCUHQA3AwAAAA==.Anuke:BAAANQAECgQIBgAAAA==.',
Ar='Arestoz:BAAANQAECgcIDQAAAA==.Ariakith:BAAANQADCgEIAQAAAA==.Arkhlight:BAAANQAECgcICwAAAA==.Arkhmonk:BAABNQAECoEgAAIHAAgKahFCJwC1AQAHAAgKahFCJwC1AQAAAA==.Arkillos:BAAANQAECgYIBgAAAA==.Armonos:BAABNQAECoEbAAIIAAgKWRS+OQD+AQAIAAgKWRS+OQD+AQAAAA==.Arowynn:BAAANQADCgUIBQABNQAECgUIDAAFAAAAAA==.Arrowhoof:BAEANQAECgUIDAAAAA==.Arthurian:BAAANQADCgEJAQAAAA==.Artémis:BAAANQADCgEIAgAAAA==.',
As='Ashiri:BAAANQABCgUIBgAAAA==.Ashmage:BAAANQAECgQJBAAAAA==.Ashmorph:BAAANQAECgUICgABNQAECgQJBAAFAAAAAA==.Asterisk:BAABNQAECoEiAAIBAAgKMBL3XwAtAgABAAgKMBL3XwAtAgAAAA==.Astromo:BAAANQADCgMJBQAAAA==.Asya:BAAANQAECggICQAAAA==.Asymmetric:BAAANQAECggIAwAAAA==.',
At='Attilathepun:BAAANQADCggICAAAAA==.',
Au='Auriêl:BAAANQAECgEIAQAAAA==.',
Ax='Axxiom:BAAANQABCgUIBQAAAA==.Axxium:BAABNQAECoEzAAMJAAkKEh1EIQDFAgAJAAkKEh1EIQDFAgAKAAcKQwjzkgBFAQAAAA==.',
Az='Azastra:BAAANQAECgYIDwAAAA==.Azorian:BAAANQAECgIIAwAAAA==.',
['Añ']='Aña:BAAANQAECgQIDAAAAA==.Añarchist:BAAANQADCgUJBwABNQAECgQIDAAFAAAAAA==.',
Ba='Babymonstter:BAAANQADCgEIAQAAAA==.Baelzharon:BAABNQAECoEaAAILAAcK3QqBAwCLAQALAAcK3QqBAwCLAQAAAA==.Baericade:BAAANQADCgMIAwABNQADCgYIBgAFAAAAAA==.Bagelpanda:BAAANQADCggIIQAAAA==.Balgrim:BAABNQAECoEVAAIMAAcKkhMGmgCyAQAMAAcKkhMGmgCyAQAAAA==.Balki:BAAANQADCgcIBwABNQAECggIHAANAA4VAA==.Bandicoot:BAAANQADCgYIDQAAAA==.Barsch:BAAANQADCggICAAAAA==.Basalt:BAAANQAECgUIDgAAAA==.Bastenwode:BAAANQADCggIIwAAAA==.Bawce:BAAANQADCgcIDgAAAA==.',
Bb='Bbye:BAAANQADCggIDQAAAA==.',
Be='Beanboi:BAAANQADCgIIAgAAAA==.Bebynoob:BAAANQAECgYIDgAAAA==.Becký:BAAANQAECgQIDAAAAA==.Beedriven:BAAANQAECgQIBAABNQAECgcIGQAFAAAAAQ==.Beroan:BAAANQAECgUICQAAAA==.Bertrille:BAAANQADCgYICQAAAA==.',
Bi='Bigcøøkie:BAAANQAECgEIAQAAAA==.Bigolcrities:BAAANQADCggJEgAAAA==.Bigshaft:BAAANQADCgYICgABNQADCggICgAFAAAAAA==.Bigwannabe:BAAANQAECgYICgAAAA==.',
Bl='Blackmagma:BAAANQAECgUIBQABNQAECgYIFwAKAKUYAA==.Blackpinkk:BAABNQAECoEYAAIBAAgKIiMgFgAsAwABAAgKIiMgFgAsAwAAAA==.Blackppinkk:BAAANQAECgYIDwAAAA==.Bloodbunny:BAAANQADCggIHgAAAA==.Blëssed:BAAANQADCgIIAgAAAA==.',
Bo='Boggartt:BAAANQAECgIIAgAAAA==.Bootscoots:BAAANQAECgYICAAAAA==.Bornite:BAAANQADCgUICgAAAA==.Bowme:BAAANQAECgYICgAAAA==.',
Br='Braedae:BAAANQAECgEIAgAAAA==.Brickaton:BAAANQAECgQIBgAAAA==.Brocknor:BAABNQAECoEiAAIMAAgK4xpPWwBdAgAMAAgK4xpPWwBdAgAAAA==.Broodling:BAAANQABCgEIAQAAAA==.',
Bu='Buckeyes:BAAANQAECgcIBwAAAA==.Buddhaspalm:BAAANQAECgEIAQAAAA==.Butterdtoast:BAEBNQAECoEYAAIHAAcKOxdBJADVAQAHAAcKOxdBJADVAQAAAA==.',
Ca='Cabbresoa:BAAANQAECgQIDQAAAA==.Caboose:BAAANQAECgYIEQAAAA==.Cadbvucolta:BAAANQADCgUIBwAAAA==.Cadius:BAAANQAECgEIAQAAAA==.Caledor:BAAANQAECggIDQAAAA==.Calet:BAAANQADCgcIDgAAAA==.Calindrel:BAAANQAECgcIEQAAAA==.Caliriya:BAAANQADCggIFAAAAA==.Candren:BAAANQAECgEIAQAAAA==.Caraway:BAAANQAECgUIDAAAAA==.Castiêl:BAAANQADCgQIBAAAAA==.',
Ce='Celaela:BAAANQAECggIAgAAAA==.Celant:BAAANQADCggIGAAAAA==.Celson:BAAANQAECgUIBwAAAA==.Celticlore:BAAANQADCggIHQAAAA==.Cerrvantes:BAAANQADCgcIDwAAAA==.',
Ch='Chernaboz:BAABNQAECoEXAAIOAAcK1g4iGQCbAQAOAAcK1g4iGQCbAQAAAA==.Chevelot:BAAANQADCgQIBgAAAA==.Chibbo:BAAANQAECgQIBAAAAA==.Chiblet:BAABNQAECoEgAAIPAAgKUgj9LwB7AQAPAAgKUgj9LwB7AQAAAA==.Chioma:BAAANQADCgcIDAABNQAECggIJQAQAO0VAA==.',
Ci='Ci:BAAANQADCgMIBgAAAA==.Cinccino:BAAANQAECgQICAAAAA==.',
Cl='Cledwyn:BAAANQADCgMIAwAAAA==.Cloudsinger:BAABNQAECoEgAAIHAAkKRBvmEQCvAgAHAAkKRBvmEQCvAgAAAA==.',
Co='Codysseuz:BAAANQADCgQIBAAAAA==.Columbo:BAAANQADCgUIBQAAAA==.Combustdeez:BAABNQAECoEhAAIRAAgKOiamFAB6AwARAAgKOiamFAB6AwAAAA==.Convrge:BAAANQADCgYIBwAAAA==.Corenthos:BAABNQAECoEnAAMSAAgKgBYASQDMAQASAAgKTxQASQDMAQAIAAcKahLRUwCDAQAAAA==.Corlys:BAAANQAECgEIAQAAAA==.Corên:BAAANQAECgEIAQAAAA==.',
Cr='Cranker:BAAANQADCgUIBQAAAA==.Crashed:BAAANQABCgUIBgAAAA==.Crazymoron:BAAANQAECgYIDgAAAA==.Creepndeath:BAAANQADCggICwAAAA==.Creselia:BAAANQAECgUIDgAAAA==.Critmaw:BAAANQAECgEIAQABNQAECgkJHAARACkgAA==.Crowley:BAAANQADCgYICwAAAA==.Crum:BAAANQADCgYIBgAAAA==.Crumdumpster:BAAANQAECgYICgABNQADCgYIBgAFAAAAAA==.Crèmefraîche:BAABNQAECoEaAAITAAcKLRHDFQDhAQATAAcKLRHDFQDhAQAAAA==.',
Cu='Cuddlerz:BAAANQAECgQIDwAAAA==.',
Cy='Cypherrellik:BAAANQAECgQIBgABNQAECgYICwAFAAAAAA==.',
Da='Dagthunderer:BAAANQAECgQIBwAAAA==.Dakkenrahl:BAAANQADCgcIEAAAAA==.Dalatras:BAAANQADCgYICAABNQAECgYIDAAFAAAAAA==.Dalistra:BAAANQAECgQIBAABNQAECgYIDAAFAAAAAA==.Dalweaver:BAAANQADCgUIBQABNQAECgYIDAAFAAAAAA==.Damogdem:BAAANQADCgYICAAAAA==.Dangly:BAACNQAFFIEFAAIEAAMKgxPSEQDxAAAEAAMKgxPSEQDxAAA1AAQKgRsAAwQACQpfGeVUAG4CAAQACQpfGeVUAG4CAAYABwqECLaSAD0BAAAA.Dantes:BAAANQADCgcICgAAAA==.Dar:BAAANQADCggIIAAAAA==.Darkflame:BAABNQAECoEWAAIBAAgK9BKvYwAjAgABAAgK9BKvYwAjAgAAAA==.Darklûrker:BAAANQAECgIIAgAAAA==.Darksidedbro:BAAANQADCgUIBQAAAA==.Darkzelda:BAAANQADCggICAAAAA==.Dayve:BAABNQAECoEiAAIUAAgKDhNgOQD7AQAUAAgKDhNgOQD7AQAAAA==.',
Dc='Dcpt:BAAANQADCgcIHgAAAA==.',
De='Deadgeinside:BAAANQAECgQIBAAAAA==.Deadgenah:BAAANQADCgMIAwAAAA==.Deadgnome:BAAANQAECgcIDwAAAA==.Deadlÿ:BAAANQAECgEIAgABNQAECggIIQARADomAA==.Deathgimbo:BAAANQAECggIDQAAAA==.Deathstomper:BAAANQAFFAEIAgAAAA==.Demondono:BAABNQAECoEiAAIQAAgKRg30NgDEAQAQAAgKRg30NgDEAQAAAA==.Dethalas:BAAANQAECgEIAQAAAA==.Devomo:BAAANQAECgIIAgAAAA==.Deyedora:BAAANQAECgYICgAAAA==.Dezax:BAABNQAECoEYAAIVAAgKRRynQgBuAgAVAAgKRRynQgBuAgAAAA==.',
Di='Diaboli:BAAANQADCgQICAAAAA==.Dilligafnope:BAAANQADCgcJBwAAAA==.Dinohunter:BAAANQAECgcIDwAAAA==.Disabler:BAAANQAECgEIAQABNQAECggIIQARADomAA==.',
Dj='Djdiddles:BAABNQAECoEZAAITAAgKiRfkDQB0AgATAAgKiRfkDQB0AgAAAA==.',
Do='Dorimane:BAAANQAECgcIGQAAAQ==.Dorlock:BAAANQAECgUIEwAAAA==.Dorotti:BAAANQAECgQIBgABNQAECgcIFwARAKIZAA==.Doubled:BAAANQADCgIIAgAAAA==.',
Dr='Dragondznuts:BAAANQADCgEIAQAAAA==.Drais:BAAANQADCgIIBQABNQADCgQIBgAFAAAAAA==.Drazgul:BAAANQADCgcIDAAAAA==.Drdukesilver:BAAANQADCgQIBAAAAA==.Dreadpanda:BAABNQAECoEzAAIMAAkKziHTHwAqAwAMAAkKziHTHwAqAwAAAA==.Dred:BAAANQAECgQIBAAAAA==.Dredkin:BAAANQADCgQIBAAAAA==.Dredwarrior:BAAANQADCgIIAgAAAA==.Drosmoke:BAAANQAECgEIAgAAAA==.Drprodigy:BAAANQAECgUICQAAAA==.Drunkbaby:BAAANQAECgYICwAAAA==.',
Dy='Dybuck:BAAANQAECgMIAwAAAA==.Dyrcyn:BAAANQAECgYIEAAAAA==.',
['Dà']='Dànger:BAABNQAECoEfAAQBAAkK1CFfGQAbAwABAAkK1CFfGQAbAwACAAMKygzsDADDAAAWAAQKWwpfWgCVAAAAAA==.',
Ed='Edroh:BAAANQAECgcIEwAAAA==.',
Ei='Eidur:BAABNQAECoEZAAIXAAgKVBcQJAA6AgAXAAgKVBcQJAA6AgAAAA==.Eightohfive:BAAANQADCgUIBwAAAA==.',
Ek='Ekøh:BAAANQADCgQICAAAAA==.',
El='Elará:BAAANQADCgYIBgAAAA==.Elemane:BAAANQAECgEIAQABNQAECgcIGQAFAAAAAQ==.Elemefayoh:BAABNQAECoEeAAMJAAcKXSQYIQDGAgAJAAcKXSQYIQDGAgAKAAEKmBsfAwFNAAAAAA==.Elementlo:BAABNQAECoEbAAITAAgKyCOTBwD1AgATAAgKyCOTBwD1AgABNQABCgIIAgAFAAAAAA==.Elsafromtemu:BAABNQAECoEXAAMDAAcK/gyDEgBWAQADAAcK/gyDEgBWAQALAAMKfABmCgBDAAAAAA==.Elspeth:BAABNQAECoEiAAIYAAgKWSHMCAD1AgAYAAgKWSHMCAD1AgAAAA==.',
Em='Emagonarain:BAAANQAECgIIAQABNQAECgkJFQAPACodAA==.Emagonasooth:BAABNQAECoEVAAIPAAkKKh29EQDDAgAPAAkKKh29EQDDAgAAAA==.Emerey:BAAANQADCggIEwAAAA==.',
En='Endknightt:BAAANQADCggIDgAAAA==.Enflamee:BAAANQADCgUIBQAAAA==.Enma:BAAANQAECgMIAgAAAA==.Ennola:BAAANQADCgYJBwAAAA==.',
Ep='Ephriia:BAAANQAECgYIEgAAAA==.',
Er='Erikprince:BAAANQAECgUIDQAAAA==.Erso:BAAANQAECgEIAQAAAA==.',
Et='Eternalpaín:BAABNQAECoEoAAIEAAgKIRxhUQB4AgAEAAgKIRxhUQB4AgAAAA==.',
Ev='Evagria:BAAANQADCgYIBgAAAA==.Evanrude:BAAANQABCggIDwAAAA==.',
Fa='Fal:BAAANQADCggIFwAAAA==.Falcyon:BAAANQADCgIIAgAAAA==.Falroot:BAABNQAECoEdAAIUAAkK8gtHPADoAQAUAAkK8gtHPADoAQAAAA==.',
Fe='Feliché:BAAANQAECgcICAABNQAECggIHAAZAHIaAA==.Fevirin:BAAANQAECgQIBgAAAA==.',
Fi='Fiddlesticks:BAAANQAECgYIDAAAAA==.Firefawkes:BAAANQAECgQJBAAAAA==.Fistbump:BAABNQAECoEaAAIaAAgKfh6rCwCrAgAaAAgKfh6rCwCrAgAAAA==.',
Fl='Fletchling:BAABNQAECoEaAAMBAAkKWyKBGgAVAwABAAgKByOBGgAVAwAWAAUK4x9pKwDMAQAAAA==.Flizrak:BAAANQADCggIEAABNQAFFAcIFAARALATAA==.',
Fo='Footsteps:BAAANQADCgcJEQAAAA==.',
Fr='Freefallen:BAAANQADCgMIAwAAAA==.Frostclot:BAABNQAECoEhAAIIAAgKsB9XHwCfAgAIAAgKsB9XHwCfAgAAAA==.Frostsalad:BAAANQAECgQIBgAAAA==.Frozoned:BAAANQAECggICwABNQAFFAEIAQAFAAAAAA==.',
Fu='Fulta:BAABNQAECoEbAAIWAAYKbBjVLQC3AQAWAAYKbBjVLQC3AQAAAA==.',
['Fø']='Føxhound:BAAANQADCgUIBQAAAA==.',
Ga='Garadin:BAAANQAECgIIAgAAAA==.Garnok:BAAANQAECggIDAAAAA==.Garwa:BAABNQAECoEkAAMBAAkKQyGUFwAkAwABAAkKQyGUFwAkAwAWAAUKWhRrOgBPAQAAAA==.',
Ge='Geniver:BAAANQADCggIJAAAAA==.Gerla:BAABNQAECoEcAAIEAAgKagxwmwC1AQAEAAgKagxwmwC1AQAAAA==.',
Gi='Gigas:BAABNQAECoEiAAQWAAgKuxTvKwDIAQAWAAcKoRTvKwDIAQACAAMKDRGqDADOAAABAAIKrRCZDwGSAAAAAA==.Gilgameshh:BAABNQAECoEgAAIEAAgKmhAJjQDXAQAEAAgKmhAJjQDXAQAAAA==.Girthbrooks:BAABNQAECoEiAAIbAAkK1Rq5CQDOAgAbAAkK1Rq5CQDOAgAAAA==.',
Gl='Glimmerfangs:BAAANQAECgYIDAAAAA==.',
Go='Gondark:BAAANQAECgIIAgAAAA==.Gooseblade:BAAANQABCgIIAgAAAA==.Gorgrim:BAAANQAECgEIAQAAAA==.Gorpse:BAAANQADCggIFgABNQAECgYIEgAFAAAAAA==.',
Gr='Grantham:BAAANQABCgQIBAAAAA==.Graverael:BAAANQADCgcICQAAAA==.Gretchen:BAABNQAECoEnAAISAAkKXiBHEgAPAwASAAkKXiBHEgAPAwABNQAFFAQIBgAWAH0LAA==.Greyley:BAAANQAECgQIBAABNQABCgIIAgAFAAAAAQ==.Greywolf:BAABNQAECoEiAAIJAAcK4x2QPgA8AgAJAAcK4x2QPgA8AgAAAA==.Grimlight:BAAANQAECgcIDAABNQAECgkJHAAcACAjAA==.Grymmhain:BAAANQADCggICAAAAA==.',
Gw='Gwawls:BAAANQADCgcIBwABNQAECgQIBAAFAAAAAA==.',
['Gä']='Gärry:BAAANQAECgMIBQAAAA==.',
Ha='Hanzoff:BAAANQADCgQIBAAAAA==.Harrow:BAAANQAECgYICgAAAA==.Havulinnaan:BAAANQAECgQIAwAAAA==.Haxx:BAABNQAECoEiAAMbAAgKIhPNFgAZAgAbAAgKbRHNFgAZAgAXAAIKuQxJeAB2AAAAAA==.',
He='Healls:BAAANQADCgUIBQAAAA==.Hearge:BAABNQAECoEbAAMYAAkKawlsJgB+AQAYAAkKawlsJgB+AQAGAAIKyAJK+gBOAAAAAA==.Hellhawk:BAAANQAECgUIDgAAAA==.Hevydevy:BAAANQAECggIEgAAAA==.Hexhain:BAABNQAECoEXAAIOAAgKmguRFADBAQAOAAgKmguRFADBAQAAAA==.',
Hi='Hiddenhorde:BAAANQAECgEIAQAAAA==.',
Ho='Hockay:BAAANQAECgYIEwAAAA==.Holygun:BAAANQAECgcIDQAAAA==.Holyshiets:BAAANQADCgUIBQAAAA==.Holyshiza:BAAANQAECgQIDAAAAA==.Holysmokess:BAAANQAECgQIBAAAAA==.Holystan:BAAANQAECgcICAAAAA==.Hondoe:BAAANQAECgUIBwAAAA==.Hopi:BAAANQABCgQIBAAAAA==.',
Ht='Htownglaivez:BAAANQADCgYIBgABNQAECgQIBwAFAAAAAA==.Htownhots:BAAANQAECgQIBwAAAA==.Htownprot:BAAANQADCgMIAwABNQAECgQIBwAFAAAAAA==.Htownshaman:BAAANQADCgcIDgABNQAECgQIBwAFAAAAAA==.',
Hu='Humblepotato:BAAANQADCgEIAgAAAA==.Hungsten:BAAANQAECgEIAQABNQAFFAMIBQAEAIMTAA==.Huntfromhell:BAABNQAECoEdAAIQAAgKmRm9JgA+AgAQAAgKmRm9JgA+AgAAAA==.',
Ic='Iceagaint:BAAANQADCgQIBQAAAA==.Icedpissfox:BAAANQADCgUJBwAAAA==.',
Id='Idonttank:BAAANQADCggIEgAAAA==.',
Il='Illio:BAAANQAECgQICgAAAA==.',
Im='Imarea:BAABNQAECoEbAAIRAAcKlgQhFAFEAQARAAcKlgQhFAFEAQAAAA==.Impirious:BAABNQAECoEiAAIIAAgKrBTpRQDDAQAIAAgKrBTpRQDDAQAAAA==.Implumz:BAAANQADCgMIAwABNQAECggIIgAIAKwUAA==.Imptard:BAAANQADCgIIAgABNQAECggIIgAIAKwUAA==.Imyx:BAAANQAECgYIDwAAAA==.',
In='Incubussy:BAAANQADCgcIBwABNQAECgkJKwAdAKsiAA==.Infamuspikel:BAABNQAECoEcAAISAAcKWx6ZMgA+AgASAAcKWx6ZMgA+AgAAAA==.Infel:BAAANQAECgIICAAAAA==.Inkkish:BAAANQAECgcIEwAAAA==.Innovates:BAABNQAECoEnAAIYAAkKQRcaFQAyAgAYAAkKQRcaFQAyAgAAAA==.Interstellar:BAAANQAECgQIBAAAAA==.Intervene:BAAANQADCgYJFAABNQAECggIKAAEACEcAA==.Invictus:BAABNQAECoEkAAIRAAgKCRHWpgATAgARAAgKCRHWpgATAgAAAA==.',
Is='Isaßeau:BAAANQADCgEIAQAAAA==.Ist:BAAANQAECgUICQAAAA==.',
Iz='Izuael:BAAANQAECgYJBgAAAA==.',
Ja='Jackjr:BAAANQAECgcIBwAAAA==.Jadea:BAAANQADCgUIBQAAAA==.Jahdar:BAAANQABCgQIBAAAAA==.Jalim:BAAANQADCgcIBwAAAA==.Jamesy:BAAANQADCgQJBAABNQAFFAUIDAAMAIMaAA==.Jandoar:BAAANQAECgYIDwAAAA==.Jarlen:BAAANQADCgEIAQAAAA==.Jaylea:BAABNQAECoEiAAIOAAcKGgy7GwCHAQAOAAcKGgy7GwCHAQAAAA==.Jaynee:BAAANQABCgUIBgAAAA==.',
Je='Jegallidin:BAAANQADCgMIBAAAAA==.Jetpilot:BAAANQAECgUICAAAAA==.Jeypi:BAAANQAECgUIDAAAAA==.',
Ji='Jiq:BAAANQAECgcIEgAAAA==.',
Jo='Johli:BAAANQADCggICAAAAA==.',
Ju='Judikai:BAAANQAECgYIDwAAAA==.Junesong:BAAANQAECgQIDQAAAA==.Justwipeit:BAAANQADCggJCAAAAA==.',
Ka='Kabilos:BAAANQADCggJEAAAAA==.Kaedian:BAAANQAECgYICgABNQAECgYIFQAHAPEgAA==.Kalesmora:BAABNQAECoEhAAIMAAgKOhFKggDyAQAMAAgKOhFKggDyAQAAAA==.Kamikaze:BAAANQAECgUICwAAAA==.Karlov:BAAANQAECgcICwAAAA==.Karthis:BAAANQADCggIDAAAAA==.Kazera:BAAANQADCgMIBAAAAA==.Kazgrim:BAAANQADCgYICgAAAA==.',
Ke='Keanah:BAABNQAECoEaAAISAAYKHg6oawA/AQASAAYKHg6oawA/AQAAAA==.Kelrosh:BAAANQABCgIJAgAAAA==.Keynn:BAAANQADCgUIBQABNQAECgYIFQAHAPEgAA==.',
Kh='Kheil:BAAANQAECgUIBQAAAA==.Kheims:BAAANQAECgQIBQAAAA==.Khrom:BAAANQADCgIIAgAAAA==.Khytoem:BAAANQAECgQICgAAAA==.',
Ki='Killduran:BAAANQAECgUICgAAAA==.Kimaga:BAAANQADCgUICQABNQAECgYIEgAFAAAAAA==.Kindle:BAAANQAECgQICAAAAA==.Kirasha:BAAANQADCgQIBAAAAA==.Kitom:BAAANQAECgYIEwAAAA==.Kiwia:BAABNQAECoEdAAIUAAgK0CIeEgAiAwAUAAgK0CIeEgAiAwAAAA==.',
Kl='Klunt:BAAANQADCgEIAQABNQAECggIHgAeAL8YAA==.',
Ko='Kochiyo:BAAANQABCgcIDAAAAA==.Kogä:BAAANQADCgUIBgAAAA==.Kolaniber:BAAANQABCgEIAQAAAA==.Korkrum:BAAANQAECgIIAwABNQAECgUIBQAFAAAAAA==.',
Kr='Kracked:BAAANQADCgMIAgAAAA==.Krank:BAAANQADCgUIDAABNQAECgQIBAAFAAAAAA==.Krel:BAAANQADCggICAABNQAECggIHAANAA4VAA==.Krellyroll:BAAANQAECgEIAQABNQAECggIHAANAA4VAA==.Krelthyr:BAABNQAECoEcAAINAAgKDhXzFwAkAgANAAgKDhXzFwAkAgAAAA==.Krumm:BAABNQAECoEnAAIfAAgKhQ0WFgCbAQAfAAgKhQ0WFgCbAQAAAA==.Kruul:BAAANQABCgQJBAAAAA==.',
Ku='Kuhne:BAAANQAECgEIAQAAAA==.Kungfudrew:BAAANQADCggICAAAAA==.',
Ky='Kyber:BAAANQAECgMIBAAAAA==.Kyther:BAAANQAECgQIBwAAAA==.',
['Kñ']='Kñightboat:BAAANQAECgYIDwAAAA==.',
La='Ladeiene:BAAANQAECgUICwAAAA==.Laelwyn:BAAANQADCggIGgAAAA==.Laelynd:BAAANQADCgYICgAAAA==.Laeritides:BAAANQADCgYICQABNQAECgUIDgAFAAAAAA==.Laeritidesdk:BAAANQAECgUIDgAAAA==.Laraondra:BAAANQAECgMIAwAAAA==.Larix:BAAANQABCgEIAQABNQAECggIHAAZAHIaAA==.Lastditch:BAAANQAECgMIAwAAAA==.Lateralas:BAAANQADCggJEQAAAA==.Laxxium:BAAANQABCgEIAQAAAA==.',
Le='Leonard:BAAANQAECgcIBwAAAA==.Leothedog:BAAANQAECgcIEgAAAA==.Lethas:BAAANQADCgMIAwAAAA==.Leukheimsia:BAAANQADCgUJBQABNQAECgQIBQAFAAAAAA==.',
Li='Lichgibber:BAAANQAECgEIAQAAAA==.Liere:BAAANQADCgcIDAAAAA==.Lightrising:BAAANQAECgMIAwAAAA==.Lilenalol:BAAANQADCgcIEwAAAA==.Lilfiorella:BAAANQADCgYIDAAAAA==.Lilmonstrman:BAABNQAECoEhAAIRAAcK0BcxrAAIAgARAAcK0BcxrAAIAgAAAA==.Liltree:BAAANQAECgcIEgAAAA==.Limbbiscuit:BAABNQAECoEbAAMBAAgK6hmnRgByAgABAAgK6hmnRgByAgAWAAQKrgOaWgCVAAAAAA==.Listmonk:BAAANQAECgIIAwAAAA==.',
Ll='Llothae:BAAANQAECgUIDgAAAA==.',
Lo='Lonjick:BAAANQADCgIIAgAAAA==.Lots:BAAANQADCgcIHgAAAA==.Loyalty:BAAANQAECgIIBQAAAA==.',
Lu='Lucinsia:BAAANQADCgQIBgAAAA==.Lul:BAACNQAFFIEGAAIMAAMKmR+DFwAkAQAMAAMKmR+DFwAkAQA1AAQKgSQAAgwACQqiIp0cADgDAAwACQqiIp0cADgDAAAA.Luminar:BAAANQAECgEIAgAAAA==.Lunaaru:BAAANQADCgMIAwAAAA==.Luvrstriplet:BAAANQAECgEIAQAAAA==.',
['Lð']='Lðvergirl:BAAANQAECgYIDwAAAA==.',
Ma='Madcow:BAAANQAECgQIBgAAAA==.Maelk:BAAANQADCgQIBQABNQAECgUIBQAFAAAAAA==.Magistella:BAAANQAECgIIAgAAAA==.Maisrii:BAEANQAECgUIDAAAAA==.Maivz:BAABNQAECoEXAAMGAAcKrg0ijABOAQAGAAcKrg0ijABOAQAEAAEKjwQIjQEoAAAAAA==.Malignantt:BAABNQAECoEiAAIIAAgKrg4ETgCdAQAIAAgKrg4ETgCdAQAAAA==.Maloch:BAAANQADCgIIAgAAAA==.Mapletoast:BAAANQADCgQIBAAAAA==.Marthren:BAAANQADCgUICQAAAA==.Marzyna:BAAANQAECgQIBAAAAA==.Maurphious:BAAANQADCggIHwAAAA==.',
Me='Mekaniker:BAAANQABCgMIAwAAAA==.Melbee:BAABNQAECoEYAAIcAAcKMBTwDwDUAQAcAAcKMBTwDwDUAQAAAA==.Melodrama:BAAANQAECgQIBwAAAA==.Metri:BAAANQABCgUIBwAAAA==.',
Mi='Micassa:BAAANQADCgIIAgAAAA==.Michaeljrdan:BAAANQADCgQIBAAAAA==.Mikela:BAAANQAECgQIDQABNQAECgcIFwARAKIZAA==.Milkee:BAAANQADCgEIAQAAAA==.Mirgaree:BAABNQAECoEcAAISAAgKxxBkTAC7AQASAAgKxxBkTAC7AQAAAA==.Mirjelys:BAAANQAECgIIAwAAAA==.',
Mo='Moarass:BAABNQAECoEaAAIgAAcKKxZhIwDeAQAgAAcKKxZhIwDeAQAAAA==.Monty:BAAANQAECgEIAQAAAA==.Moodswingz:BAAANQADCgIIAwAAAA==.Mordos:BAAANQADCgMIAwAAAA==.Moridane:BAAANQAECgQIBAABNQAECgcIGQAFAAAAAQ==.',
Mu='Muffinz:BAAANQAECgQJBwABNQAECgcIDwAFAAAAAA==.Mugo:BAAANQAECgQIBAABNQAECggIHAAZAHIaAA==.Multiabuse:BAAANQAECgMIAwAAAA==.',
My='Myau:BAAANQAECgcIDAAAAA==.Mylou:BAAANQAECgQICQAAAA==.Mynia:BAABNQAECoEnAAICAAgKewYmCACrAQACAAgKewYmCACrAQAAAA==.',
Na='Nano:BAABNQAECoEcAAMVAAgKMxkPQgBvAgAVAAgKMxkPQgBvAgAOAAIKxA1uWABtAAAAAA==.Nayroon:BAEANQADCggICAABNQAECggIHwABAJ0hAA==.Nazdreg:BAABNQAECoEYAAMOAAYKfRQyMwDsAAAVAAYKphFxqwBLAQAOAAQKnREyMwDsAAAAAA==.',
Ne='Negan:BAAANQABCgUIBQAAAA==.Neotoldir:BAABNQAECoEiAAIhAAgKzhPuLgDzAQAhAAgKzhPuLgDzAQAAAA==.Nerfdisc:BAAANQAECgQIBgAAAA==.Nevershocked:BAABNQAECoEcAAIiAAcKfBemCADcAQAiAAcKfBemCADcAQAAAA==.Nezziee:BAAANQAECgIIAgAAAA==.',
Ni='Ninjaznpariz:BAAANQADCgQJBAAAAA==.',
No='Noblewrack:BAAANQADCgEIAQAAAA==.Noobles:BAAANQAECgQIBQAAAA==.Nordie:BAAANQADCggICAAAAA==.Northik:BAAANQADCgUIBQABNQAECgcIGQAWALIPAA==.Nosredna:BAAANQAECgMIBAAAAA==.Nosrednàx:BAAANQADCgUIBQAAAA==.Notintheface:BAAANQAECgIIAgAAAA==.Novata:BAAANQADCgUIBQABNQAECgIIAgAFAAAAAA==.',
Nu='Nuzz:BAACNQAFFIERAAIMAAYKXCRZBABpAgAMAAYKXCRZBABpAgA1AAQKgSAAAgwACQrJJUcSAGsDAAwACQrJJUcSAGsDAAAA.',
Ny='Nydav:BAABNQAECoEVAAIHAAYK8SB9HAApAgAHAAYK8SB9HAApAgAAAA==.',
Ob='Obalma:BAAANQAECgYJEgAAAA==.',
Od='Odwalla:BAABNQAECoEbAAIBAAkKkCKwEABMAwABAAkKkCKwEABMAwAAAA==.',
Ol='Olmec:BAAANQAECgUICgAAAA==.Olmek:BAAANQAECgIIAgAAAA==.',
On='Onlydesert:BAABNQAECoEXAAMRAAcKohndogAcAgARAAcKohndogAcAgALAAEKKhHdCgA+AAAAAA==.Onranui:BAAANQADCgcIDQAAAA==.',
Oo='Oopsyourdead:BAAANQAECgUICgAAAA==.',
Op='Optiks:BAABNQAECoEXAAMRAAcKORzlmwArAgARAAcK+RrlmwArAgADAAIKlhpcJwCUAAAAAA==.',
Or='Orcfan:BAAANQABCgIJAgAAAA==.Orksauce:BAABNQAECoEuAAMbAAkKkh+rFAAwAgAbAAYKjyCrFAAwAgAXAAMKlh29XADzAAAAAA==.Orphella:BAAANQAECgEIAQAAAA==.',
Os='Osares:BAAANQAECgYIDwAAAA==.Osong:BAAANQADCgcIBwABNQAECgUIBQAFAAAAAA==.',
Ou='Outtamanna:BAAANQADCgUICQAAAA==.',
Ow='Owils:BAAANQADCgYIBgABNQAECggIJwASAIAWAA==.',
['Oß']='Oß:BAAANQAECgEIAQABNQAECgQIBwAFAAAAAA==.',
Pa='Pagophobia:BAAANQAECgMIAwAAAA==.Pallytree:BAAANQAECgIIAgAAAA==.Papiblanco:BAAANQADCggICgAAAA==.Pariahdruid:BAAANQAECggIDQAAAA==.',
Pe='Percepcions:BAAANQAECgUICwAAAA==.Percksmash:BAAANQAECggIDAAAAA==.Perkbane:BAAANQAECggIBwABNQAECggIDAAFAAAAAA==.Perkyl:BAAANQAECgIIBQAAAA==.',
Ph='Phage:BAAANQAECgQIBAABNQAECggIHgAeAL8YAA==.Philon:BAAANQADCgEIAQAAAA==.Photophobia:BAABNQAECoEaAAIPAAkKlB97EQDHAgAPAAkKlB97EQDHAgAAAA==.',
Pi='Piezo:BAAANQADCgQIBgAAAA==.Pikevarr:BAAANQADCggIEAAAAA==.Pivy:BAAANQADCgYIBgABNQAECggIGgAaAH4eAA==.',
Pk='Pkrage:BAABNQAECoEpAAMfAAkKkR2DBgDcAgAfAAkKkR2DBgDcAgAMAAIK+Qx6GwFmAAAAAA==.',
Pl='Plaugez:BAAANQABCgIIAwAAAA==.Plazlie:BAABNQAECoEjAAMjAAkKzCOGAgAyAwAjAAgK9yOGAgAyAwAMAAEKciKwHAFjAAAAAA==.Plopp:BAEANQAECgYIBgABNQAECgYIEQAFAAAAAA==.Ploppstein:BAEANQAECgYIEQAAAA==.',
Po='Polyethylene:BAAANQAECgcIEQAAAA==.Poucastranca:BAABNQAECoEpAAMOAAgK/iSkOgDMAAAOAAMKuSSkOgDMAAAVAAcKpyQyCgFzAAAAAA==.',
Pu='Punkpikachu:BAAANQADCgcIHgAAAA==.',
Pw='Pwnman:BAAANQADCgUIBQAAAA==.',
Qk='Qkoira:BAAANQAECgQICgAAAA==.',
Qu='Quanlain:BAAANQAECgUIDgAAAA==.Quillathe:BAABNQAECoEjAAMdAAgKxRNvDwAdAQAZAAgKxRMGUwD+AQAdAAYKOghvDwAdAQAAAA==.',
Ra='Raagh:BAAANQAECgQIBAAAAA==.Rabblle:BAAANQADCggICAAAAA==.Rancore:BAAANQAECgUICwABNQAECgYIEQAFAAAAAA==.Rashdar:BAABNQAECoEjAAIEAAkKHxz/RQCdAgAEAAkKHxz/RQCdAgAAAA==.Rasto:BAAANQADCgYICQABNQAECgQJBwAFAAAAAA==.Rattpacck:BAAANQAECgEIAQAAAA==.Rattpack:BAAANQAECgQICwAAAA==.Raves:BAAANQAECgQICQAAAA==.Rayvynn:BAAANQADCgIIBAAAAA==.',
Re='Regilz:BAAANQADCgMIAwAAAA==.',
Rh='Rhys:BAAANQADCgMIAwAAAA==.',
Ri='Ribeyye:BAAANQAECgcICgAAAA==.Rider:BAAANQAECgEIAQAAAA==.Rigormortiis:BAAANQAECgEIAQAAAA==.Rilde:BAAANQADCgYIGAAAAA==.Rinjiabri:BAAANQAECgIIAgAAAA==.Rinjipally:BAAANQAECgUIBQAAAA==.',
Ro='Robroy:BAAANQAECggIDgAAAA==.Robrøy:BAAANQADCggJGQAAAA==.Rokmage:BAAANQAECgMIBAAAAA==.Roseclaw:BAEANQAECgQIBgABNQAECggIHwABAJ0hAA==.Roseclawed:BAEBNQAECoEfAAIBAAgKnSFKJwDbAgABAAgKnSFKJwDbAgAAAA==.Roxso:BAACNQAFFIEUAAMRAAcKsBPnDQDmAQARAAYKDhPnDQDmAQADAAEKfReWCQBcAAA1AAQKgTUAAxEACQobI4ggAE8DABEACQoaI4ggAE8DAAMABgp6DOQaAPIAAAAA.',
Ru='Rukaiz:BAABNQAECoEUAAIMAAYKqRi5nACrAQAMAAYKqRi5nACrAQAAAA==.',
Ry='Rylen:BAAANQADCgYIBgAAAA==.Rylun:BAAANQAECgEIAQAAAA==.',
['Rë']='Rëdmagma:BAABNQAECoEXAAIKAAYKpRj5ZwC4AQAKAAYKpRj5ZwC4AQAAAA==.',
['Rò']='Ròbroy:BAAANQAECggJCQAAAA==.',
['Ró']='Rónan:BAAANQAECgEIAQAAAA==.',
['Rû']='Rûsh:BAAANQADCggJEAAAAA==.',
Sa='Sacrelicious:BAAANQAECgYICwAAAA==.Saennah:BAAANQADCgIJAgAAAA==.Sagewynn:BAAANQAECgUIDAAAAA==.Sainei:BAAANQADCgUIBQABNQAECggIHAAMAP8aAA==.Salfroc:BAABNQAECoEmAAIkAAgKVxeoBQBBAgAkAAgKVxeoBQBBAgAAAA==.Samhain:BAABNQAECoEjAAIlAAgKABFNJQD8AQAlAAgKABFNJQD8AQAAAA==.Sanasianana:BAAANQADCgUIBQABNQAFFAEIAQAFAAAAAA==.Saplo:BAAANQAECgUICQAAAA==.Sapphirosa:BAAANQAECgEIAQABNQAECgkJIAAHAEQbAA==.Sarif:BAAANQAECgQICAAAAA==.Saxel:BAAANQAECgEIAQAAAA==.',
Sc='Scallop:BAAANQADCgQIBAAAAA==.Schwarzenman:BAAANQADCgEIAQAAAA==.',
Se='Segio:BAAANQAECgEIAQAAAA==.Selcia:BAAANQADCggJEAAAAA==.Serenati:BAAANQAECgUIDgAAAA==.Seïya:BAAANQADCggIJQAAAA==.',
Sg='Sgthulka:BAAANQADCgQJBAAAAA==.',
Sh='Shamawockee:BAAANQAECgUIEQABNQAECggIJQABAIUfAA==.Shango:BAAANQADCgUIBQAAAA==.Sharavia:BAABNQAECoEWAAIQAAcKWQgZRwBXAQAQAAcKWQgZRwBXAQAAAA==.Shasu:BAAANQADCgEIAQAAAA==.Shaundi:BAAANQAECgEIAQAAAA==.Shautistic:BAAANQADCggIDAAAAA==.Shocktuah:BAABNQAECoEnAAIKAAgKhiT1EwA/AwAKAAgKhiT1EwA/AwAAAA==.Shonúff:BAABNQAECoEcAAIHAAgKTRM+IwDfAQAHAAgKTRM+IwDfAQAAAA==.Shotaru:BAAANQAECgUIDAAAAA==.Shotpace:BAAANQAECgQICAAAAA==.Showerhandle:BAAANQADCgMIAwAAAA==.Shui:BAAANQAECgEIAQABNQAECgQICAAFAAAAAA==.Shädöw:BAAANQADCgUIBwAAAA==.',
Si='Silmeria:BAAANQAECgcIDQAAAA==.Sinful:BAABNQAECoEqAAMjAAkKrQ1/DADOAQAjAAgKUA5/DADOAQAMAAIKIQjNJQFMAAAAAA==.',
Sk='Skalagrim:BAAANQADCggIDwAAAA==.Skeptyk:BAABNQAECoEhAAIZAAgKKR+GIgDHAgAZAAgKKR+GIgDHAgAAAA==.Sko:BAEBNQAECoEjAAMGAAkKFxoZIgDNAgAGAAkKFxoZIgDNAgAEAAYKPQvB6AAQAQABNQADCgcJCQAFAAAAAA==.Skol:BAAANQAECgcIEgAAAA==.Skolivermist:BAEANQADCgEIAQABNQADCgcJCQAFAAAAAA==.Skolivia:BAEANQADCgcJCQAAAA==.',
Sm='Smiley:BAAANQAECgMIAwAAAA==.Smitti:BAAANQAECgQIBAABNQAECgcIFwARAKIZAA==.Smokeydabear:BAAANQADCgEIAQAAAA==.Smug:BAABNQAECoEdAAMlAAcKxSVtEQDPAgAlAAcKJCVtEQDPAgAQAAYKLCM7IQBqAgAAAA==.',
Sn='Snapee:BAAANQAECgQIBwAAAA==.Sniffledoo:BAABNQAECoEYAAIfAAcKLRLmFwCAAQAfAAcKLRLmFwCAAQAAAA==.Snol:BAAANQADCggICAAAAA==.Snuwuf:BAAANQADCgcIEAAAAA==.',
So='Sockz:BAAANQAECgYICQAAAA==.Soonmia:BAAANQADCgQIBAAAAA==.Sourfangs:BAABNQAECoEbAAMMAAkK3iD4KgD+AgAMAAkK3iD4KgD+AgAjAAEKpCIiJQBhAAAAAA==.Soxx:BAAANQADCgYICwABNQAECggIIgAbACITAA==.',
Sp='Spicypeño:BAABNQAECoEiAAIeAAkKDiHYBAA5AwAeAAkKDiHYBAA5AwABNQAFFAcIHgAeAGchAA==.Spicý:BAABNQAECoEZAAIRAAkKUSFtOAAKAwARAAkKUSFtOAAKAwAAAA==.Splack:BAABNQAECoElAAIBAAgKhR9NLQDEAgABAAgKhR9NLQDEAgAAAA==.Splithoofe:BAEANQADCgUICwABNQAECgUIDAAFAAAAAA==.Sprawl:BAABNQAECoEaAAImAAgK4BDeCADwAQAmAAgK4BDeCADwAQAAAA==.Sprawlher:BAAANQAECgUICwABNQAECggIGgAmAOAQAA==.',
Sq='Squrrlydan:BAEANQAECgQJBAAAAA==.',
St='Stabzuplenty:BAAANQAECgIIAgABNQAFFAcIFAARALATAA==.Staint:BAABNQAECoEeAAIeAAgKvxhADgBfAgAeAAgKvxhADgBfAgAAAA==.Staints:BAAANQAECgMIAwABNQAECggIHgAeAL8YAA==.Starnights:BAAANQAECgQICQAAAA==.Statman:BAAANQAECgUIDgAAAA==.Steelbubble:BAABNQAECoEZAAMMAAkKkxxPSgCRAgAMAAkKxhpPSgCRAgAjAAMKViKiGADzAAAAAA==.Stella:BAAANQAECgUIBgAAAA==.Stengah:BAABNQAECoEjAAINAAgKVR4ZDgCzAgANAAgKVR4ZDgCzAgAAAA==.Stonebrew:BAAANQABCgEIAQAAAA==.Strela:BAAANQAFFAEIAQAAAQ==.',
Su='Suraki:BAABNQAECoElAAIQAAgK7RWUKAAwAgAQAAgK7RWUKAAwAgAAAA==.',
Sv='Svetlian:BAAANQADCgMIBgABNQAFFAEIAQAFAAAAAA==.',
Sw='Swtblsphmy:BAAANQAECgYICQAAAA==.',
Sy='Sylverwolf:BAAANQADCgEIAQAAAA==.Sylvestrus:BAAANQAECgQIBwABNQAECggIHAAZAHIaAA==.',
['Sä']='Säber:BAAANQADCgcIBwAAAA==.',
['Sè']='Sèd:BAABNQAECoErAAIZAAkKIRphHQDiAgAZAAkKIRphHQDiAgAAAA==.Sèitheach:BAAANQADCggJDgAAAA==.',
['Sí']='Síd:BAABNQAECoEiAAMkAAkK6RG1BABjAgAkAAkKRxG1BABjAgAVAAkKMgktdQDYAQAAAA==.',
Ta='Tahrin:BAABNQAECoEbAAIBAAgKYSA+IAD6AgABAAgKYSA+IAD6AgAAAA==.Talamon:BAABNQAECoEiAAInAAgK5xQTDgD1AQAnAAgK5xQTDgD1AQAAAA==.Tamerlynn:BAAANQADCgUIBAAAAA==.Tandruid:BAABNQAECoEjAAIUAAgKfB+0HQDAAgAUAAgKfB+0HQDAAgAAAA==.Taproot:BAAANQAECgYIAQAAAA==.Tarasis:BAAANQADCgEIAQAAAA==.Tashi:BAABNQAECoEbAAMBAAcKphFBiQDHAQABAAcKphFBiQDHAQAWAAUK9wMRVACuAAAAAA==.Tasina:BAAANQADCgUIBgAAAA==.Taurenamos:BAABNQAECoEwAAMgAAgKGhaRHgAPAgAgAAcKBRiRHgAPAgAUAAgK7hNTNwAJAgAAAA==.Taynam:BAAANQAECgQICAABNQAECgUIDgAFAAAAAA==.',
Te='Tempëst:BAAANQAECgIJAgAAAA==.Tenchu:BAAANQAECgYIDwAAAA==.Tendra:BAAANQADCgMIAwAAAA==.Tenseven:BAAANQAECgQICAAAAA==.Terrørßlade:BAAANQAECgEIAQABNQAECgUICgAFAAAAAA==.',
Th='Thalorain:BAAANQAECgUIBQAAAA==.Thark:BAAANQAECgUIBQABNQAECggIIwAKAIolAA==.Thatdruid:BAAANQAECgEIAQAAAA==.Thicknfluffy:BAAANQABCgEIAgAAAA==.Throwd:BAABNQAECoElAAIbAAgKBxFzFgAdAgAbAAgKBxFzFgAdAgAAAA==.Thundah:BAAANQAECgEIAQAAAA==.Thurk:BAABNQAECoEjAAMKAAgKiiV0EABYAwAKAAgKiiV0EABYAwATAAMKhRkPIwDvAAAAAA==.',
Ti='Tideshunter:BAABNQAECoEcAAMBAAkKCRyTRQB1AgABAAgKghyTRQB1AgAWAAgKIhI7KQDfAQAAAA==.Tinytony:BAABNQAECoEeAAMYAAcKnBvpFQAoAgAYAAcKnBvpFQAoAgAEAAIKdQo6QwFwAAAAAA==.Tinyweakling:BAAANQAECgIIAgABNQAECgkJGgABAFsiAA==.',
To='Tookahxd:BAAANQAECgIIAgAAAA==.Toranis:BAAANQAECgEIAQAAAA==.Torrellan:BAAANQAECgEIAQAAAA==.Torrents:BAABNQAECoEgAAMJAAgKkyUMDQBEAwAJAAgKkyUMDQBEAwAKAAEKMww1DwE5AAAAAA==.Totemik:BAAANQAECgEIAQAAAA==.Touchofchaos:BAAANQADCggICAAAAA==.',
Tr='Trailerpark:BAAANQAECggIBwAAAA==.Triepas:BAAANQAECgUICQAAAA==.Trillest:BAAANQAECgcIBgAAAA==.Trinytee:BAABNQAECoEXAAIBAAYKgxhXmACkAQABAAYKgxhXmACkAQAAAA==.Trippytotem:BAABNQAECoEiAAMKAAcK1xCPZwC5AQAKAAcK1xCPZwC5AQAJAAQKSgUn0ACfAAAAAA==.Trolltoll:BAAANQADCgEIAQAAAA==.Trollypolly:BAAANQABCgMIAQAAAA==.',
Ty='Tyriäel:BAABNQAECoEdAAMSAAcKSSMXHQDAAgASAAcKSSMXHQDAAgAIAAcKIxt5OwD1AQAAAA==.Tyrrible:BAAANQAECggIAQAAAA==.',
['Tà']='Tàyla:BAAANQADCgQIBAABNQAECgYIFwABAIMYAA==.',
Ug='Ugolino:BAAANQADCgEIAQAAAA==.',
Ul='Ulmec:BAAANQADCgQIBAAAAA==.Ulther:BAAANQADCggJEAAAAA==.',
Va='Vacare:BAAANQADCggJEAAAAA==.Valdyria:BAAANQADCgUIEgAAAA==.Valistar:BAAANQAECgMIBAAAAA==.Valkoienne:BAAANQADCgQJCQAAAA==.Vavictus:BAAANQADCggJEAAAAA==.Vazaenei:BAAANQABCgMIAwAAAA==.',
Ve='Vedronorael:BAAANQADCgcJBgAAAA==.Veinos:BAAANQAECggIEQAAAQ==.Velanthia:BAAANQADCgcIBwAAAA==.Velora:BAAANQAECgIIBAAAAA==.Vengrath:BAABNQAECoEWAAIRAAgK+B6VZwCbAgARAAgK+B6VZwCbAgAAAA==.Verderben:BAAANQAECgUIDAAAAA==.Verind:BAAANQAFFAEIAQAAAA==.',
Vi='Vinhelsin:BAAANQAECgEIAQAAAA==.',
Vo='Voideater:BAAANQADCgEIAQAAAA==.Voron:BAABNQAECoEmAAIEAAcKmBWNkgDKAQAEAAcKmBWNkgDKAQAAAA==.',
Vu='Vulperra:BAABNQAECoEdAAIMAAkKgxGqagAxAgAMAAkKgxGqagAxAgAAAA==.',
Vy='Vynessa:BAAANQADCgMJAwAAAA==.',
Wa='Wade:BAAANQAECgcIDAAAAA==.Walk:BAAANQADCgYIBgAAAA==.Waq:BAABNQAECoEbAAQkAAgKhhawCQC8AQAkAAYKIxqwCQC8AQAVAAYKWguOrwBCAQAOAAQKXBVeKgAdAQAAAA==.Waterwhip:BAAANQAECgcIEwAAAA==.',
We='Wemeo:BAAANQAECgQIBQAAAA==.Westfall:BAABNQAECoEdAAMIAAcKrB7sKABfAgAIAAcKrB7sKABfAgASAAIKKAIVxQA+AAAAAA==.',
Wi='Willowweewoo:BAAANQAECgcIDgAAAA==.Willrun:BAAANQAECgUICAAAAA==.Wipeit:BAAANQADCgIIAgAAAA==.Witheredyam:BAAANQADCgYIBgAAAA==.',
Wo='Wolfbayne:BAAANQAECgUIBwAAAA==.Wompeal:BAABNQAECoEVAAMZAAcKjBp7TQATAgAZAAcKjBp7TQATAgAdAAEKIBKOIwA6AAAAAA==.Wonkwonk:BAABNQAECoEYAAMDAAcKygr8EgBQAQADAAcKygr8EgBQAQALAAEKfwEYDgAUAAAAAA==.Worth:BAABNQAECoEnAAIEAAgKiSCtMwDdAgAEAAgKiSCtMwDdAgAAAA==.',
Wr='Wrukolas:BAABNQAECoEXAAIVAAcKnAcNpABdAQAVAAcKnAcNpABdAQAAAA==.',
Wy='Wystan:BAABNQAECoEdAAIJAAgKwx5MJwCnAgAJAAgKwx5MJwCnAgAAAA==.',
['Wè']='Wès:BAAANQADCgEIAQAAAA==.',
['Wé']='Wés:BAABNQAECoEfAAMnAAgKahmwCgBKAgAnAAgKahmwCgBKAgAaAAMK5AtzOACBAAAAAA==.',
Xa='Xamsuciteey:BAAANQADCgUIBQAAAA==.Xandritten:BAAANQABCgIIAgAAAA==.Xanthe:BAABNQAECoEcAAMGAAgKpxMhSwAcAgAGAAgKpxMhSwAcAgAEAAEKkQFXngEcAAAAAA==.Xavin:BAAANQADCgcICQAAAA==.',
Xe='Xentow:BAABNQAECoEiAAIBAAgKGgYalACuAQABAAgKGgYalACuAQAAAA==.',
Ya='Yamling:BAAANQADCggIHgAAAA==.Yayaka:BAAANQADCgcIEgAAAA==.',
Yi='Yizdano:BAACNQAFFIEHAAMbAAMKlw4+CwDXAAAbAAMK0wo+CwDXAAAXAAIKMwjEEgCSAAA1AAQKgSsAAxcACQq7F8kdAGcCABcACAoaGskdAGcCABsACQp1CusYAAECAAAA.',
Yu='Yukiina:BAAANQADCgcIEQAAAA==.Yungbean:BAAANQAECgQIBwAAAA==.',
['Yû']='Yûm:BAAANQADCggICgAAAA==.',
Za='Zaccheus:BAAANQAECgQIBgABNQAECggIHAAZAHIaAA==.Zambora:BAAANQADCgcICgAAAA==.Zamwi:BAAANQAECgQICQAAAA==.Zavrix:BAAANQAECggIAQAAAA==.',
Ze='Zeebra:BAAANQAECgUICAAAAA==.Zeesaw:BAABNQAECoEcAAMMAAcKBBcygQD1AQAMAAcKzhYygQD1AQAjAAIKCxWhIACMAAAAAA==.Zenden:BAAANQADCggIJAAAAA==.Zeretrix:BAABNQAECoEjAAMRAAcKSiCRdAB+AgARAAcKyx+RdAB+AgADAAQKFhFMIQC+AAAAAA==.Zerospace:BAABNQAECoEdAAIEAAgK7Qv+pgCaAQAEAAgK7Qv+pgCaAQAAAA==.',
Zi='Ziros:BAAANQAECggICAAAAA==.',
Zl='Zlutar:BAAANQAECgQIBgAAAA==.',
Zy='Zynos:BAABNQAECoEaAAIQAAgKiQ3kNgDFAQAQAAgKiQ3kNgDFAQAAAA==.Zynothrian:BAAANQADCgMIAwAAAA==.Zyraethiel:BAAANQAECgIIAgAAAA==.',
['Ça']='Çalindrel:BAAANQADCgUIBQAAAA==.',
['Ðe']='Ðemonic:BAAANQADCgYIBgAAAA==.',
['Úà']='Úà:BAAANQADCgIIAQABNQAECgQICgAFAAAAAA==.',
['Üb']='Überhealz:BAABNQAECoEcAAMZAAgKchoMUgACAgAZAAgKchoMUgACAgAPAAMKWAvbUQCbAAAAAA==.',
['ßö']='ßöw:BAABNQAECoEnAAIBAAgKASEzKgDPAgABAAgKASEzKgDPAgAAAA==.',
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
