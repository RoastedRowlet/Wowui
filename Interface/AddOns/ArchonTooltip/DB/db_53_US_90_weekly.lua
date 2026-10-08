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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Unknown-Unknown','Mage-Arcane','Monk-Mistweaver','Rogue-Outlaw','Shaman-Elemental','Shaman-Restoration','Rogue-Assassination','Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Paladin-Holy','DeathKnight-Frost','Paladin-Retribution','Mage-Frost','Hunter-Marksmanship','Priest-Shadow','Paladin-Protection','DeathKnight-Unholy','Priest-Holy','Priest-Discipline','Shaman-Enhancement','Evoker-Preservation','Druid-Feral','Warrior-Arms','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abacus:BAAANQAECgQIBgAAAA==.',
Ad='Adam:BAACNQAFFIEWAAMBAAcKehmiBAADAgABAAYKsBeiBAADAgACAAIKdB3KCQCpAAA1AAQKgSMABAIACQouJNUHAHkCAAEACAqoI8EoAMkCAAIACAprGtUHAHkCAAMAAQpqHsIpADoAAAAA.',
Ak='Akurama:BAAANQAECgUIBwAAAA==.',
Al='Allfrowns:BAAANQAECgcJDgAAAA==.Allsmiles:BAAANQAECgUICQAAAA==.Allura:BAAANQAECgIIAgAAAA==.Alunaris:BAAANQAECgEJAgAAAA==.',
Am='Amoon:BAABNQAECoEbAAMEAAgKrRE1JAAGAgAEAAgK6hA1JAAGAgAFAAIKoxJPJABkAAAAAA==.',
An='Ancalagon:BAAANQADCgQIBAAAAA==.',
Ar='Archymedes:BAAANQAECgIIAQAAAA==.Arckady:BAAANQAECgIIAgAAAA==.Array:BAAANQADCggICAAAAA==.Artharius:BAABNQAECoEaAAMGAAgKPyFpEwCcAgAGAAgKPyFpEwCcAgAHAAUK4RQNGQAuAQAAAA==.',
Au='Auburnbeard:BAAANQAECgEJAQAAAA==.',
Av='Averle:BAAANQAECgIIAgAAAA==.',
Ba='Badchoices:BAAANQAECgEIAQAAAA==.Badkittie:BAAANQADCgUICgAAAA==.Baretta:BAAANQAECgYIBwAAAA==.',
Be='Beefsnake:BAEBNQAECoEeAAIIAAkKFxWeJwB2AgAIAAkKFxWeJwB2AgAAAA==.Beefytips:BAAANQADCgIJAgAAAA==.Bettyßaraxus:BAAANQAECgQIBAABNQAECgYIEQAJAAAAAA==.Bettyßlight:BAAANQADCgUICAABNQAECgYIEQAJAAAAAA==.',
Bi='Bigunsforu:BAAANQAECgYIBgAAAA==.',
Bo='Bogs:BAABNQAECoEXAAIKAAkK7Rm6aQCWAgAKAAkK7Rm6aQCWAgAAAA==.Bolomorte:BAAANQADCgYJBgAAAA==.Boragish:BAAANQAECgcIDAAAAA==.Boulderfist:BAAANQADCggIFAAAAA==.',
Br='Brolic:BAAANQAECgYIEgAAAA==.',
Bu='Bubbleman:BAAANQADCgQIBAAAAA==.Bubblestomps:BAAANQADCgMIAwAAAA==.Burial:BAAANQAECgIIAgAAAA==.',
Bw='Bwonsamdy:BAAANQAECgIIAgAAAA==.',
['Bä']='Bämboo:BAABNQAECoEWAAILAAgK+Re5EQA3AgALAAgK+Re5EQA3AgAAAA==.',
Ca='Cail:BAEANQAECgQIDgAAAA==.Calamìty:BAAANQAECgMIAwAAAA==.Calisa:BAABNQAECoEbAAIMAAgKWRLDBwAaAgAMAAgKWRLDBwAaAgAAAA==.Cantstandya:BAAANQAECggIEwAAAA==.Carnifex:BAABNQAECoEUAAMNAAcKFRUTdACUAQANAAYKaxYTdACUAQAOAAYKZg6xkAAwAQAAAA==.',
Ce='Ceryph:BAAANQADCgUJBQAAAA==.',
Ch='Charis:BAAANQADCgEIAQAAAA==.Chewbub:BAAANQADCgIIAgAAAA==.Chigutotems:BAEBNQAECoEgAAIOAAkKrB2bFAAOAwAOAAkKrB2bFAAOAwAAAA==.Chow:BAAANQABCgUIBQAAAA==.Chozen:BAABNQAECoEmAAIPAAkKByOgCAA2AwAPAAkKByOgCAA2AwAAAA==.Chroniccloud:BAAANQAECgEIAQAAAA==.',
Co='Cornelius:BAAANQAECgUICgAAAA==.Coulee:BAAANQADCgQJCAABNQAECgcIEgAJAAAAAA==.',
Cr='Cronicpain:BAAANQAECgUIBgAAAA==.',
Cy='Cymbi:BAAANQABCgQIAwAAAA==.',
Da='Daks:BAAANQADCgQIBAAAAA==.Darklucrezia:BAABNQAECoEYAAIQAAgKPRWiYgAmAgAQAAgKPRWiYgAmAgAAAA==.Darkpyro:BAAANQADCggIEAAAAA==.',
De='Deetsy:BAAANQADCgYICAAAAA==.Dextrose:BAAANQAECgcICwABNQAECggIDwAJAAAAAA==.',
Dk='Dkbig:BAAANQAECgQIBAAAAA==.',
Dr='Dracarius:BAAANQAECgIIAgAAAA==.Drtypinkcake:BAAANQAECgUIBgAAAA==.Druidcant:BAAANQADCgYJBgAAAA==.Drworldwide:BAAANQAECggICQAAAA==.Dryad:BAAANQAECgIIAgAAAA==.',
Du='Durkk:BAABNQAECoEeAAIRAAgK6xjIKgBTAgARAAgK6xjIKgBTAgAAAA==.Durza:BAAANQADCggICAAAAA==.',
['Dä']='Dännydevito:BAAANQADCgMIBAAAAA==.',
En='Enss:BAAANQADCgUJBQAAAA==.',
Es='Estara:BAABNQAECoEcAAISAAgKxgv+HQBqAQASAAgKxgv+HQBqAQAAAA==.',
Et='Etali:BAAANQAECgYIEAAAAA==.Etherious:BAAANQAECgQIBAABNQAECgYICQAJAAAAAA==.',
Fa='Fanis:BAAANQAECgcIDwAAAA==.',
Fi='Fibo:BAAANQADCgQIBAAAAA==.',
Fl='Flashis:BAAANQAECggIEQAAAA==.Floor:BAAANQABCgIIAgAAAA==.Florago:BAAANQAECgIIAgAAAA==.',
Fo='Force:BAAANQAECgEIAgAAAA==.',
Fr='Frakir:BAABNQAECoEeAAMOAAgK/Q+IZgCqAQAOAAgK/Q+IZgCqAQANAAEKlQRVMAEkAAAAAA==.',
Fu='Furrypaw:BAABNQAECoEeAAMLAAgK3x3eCwCnAgALAAgK3x3eCwCnAgAGAAEKLAdcZQAnAAAAAA==.',
Fw='Fwapp:BAACNQAFFIETAAITAAYKvxTtBAAFAgATAAYKvxTtBAAFAgA1AAQKgSkAAhMACQp6JVgDALUDABMACQp6JVgDALUDAAAA.',
Ga='Galvanize:BAAANQAECgQIBwAAAA==.',
Gi='Gijaick:BAAANQAECgUICgAAAA==.',
Gl='Glizzo:BAABNQAECoEnAAIKAAkK+hPaeAB2AgAKAAkK+hPaeAB2AgAAAA==.Gloomrider:BAAANQADCgUIBQAAAA==.',
Go='Gold:BAAANQADCgUIBQAAAA==.Goldhawk:BAAANQADCgEIAQAAAA==.Gotwiped:BAABNQAECoEaAAIUAAcK+RkkLAAGAgAUAAcK+RkkLAAGAgAAAA==.',
Gu='Gunnery:BAAANQAECggIDgAAAA==.',
Ha='Haoleboy:BAAANQADCggIGQAAAA==.Hatter:BAABNQAECoEfAAMFAAgKuxnIDADGAQAEAAgKvxYjHQBOAgAFAAcK7RbIDADGAQAAAA==.',
He='Hellraiser:BAAANQAECgUICwAAAA==.',
Hi='Hidduka:BAABNQAECoEaAAITAAgKbxwGMwB9AgATAAgKbxwGMwB9AgAAAA==.Hills:BAAANQAECgEIAQAAAA==.',
Ho='Holyascended:BAAANQADCggIFgAAAA==.Holydarkness:BAAANQADCgYIBgAAAA==.Holykilla:BAAANQADCgUIBQAAAA==.Holykiller:BAAANQADCgEIAQAAAA==.Hoplite:BAAANQADCgIIAgABNQAECgYIBwAJAAAAAA==.Howlly:BAAANQAECgQIDgAAAA==.',
Hr='Hraun:BAAANQADCgIIAQAAAA==.',
Ik='Ikeanola:BAABNQAECoEeAAIVAAkKxwUjzABJAQAVAAkKxwUjzABJAQAAAA==.',
In='Indras:BAAANQADCgcIFAAAAA==.Ines:BAABNQAECoEiAAIUAAgKEiA7FADJAgAUAAgKEiA7FADJAgAAAA==.Inhume:BAAANQADCggJCQAAAA==.',
Is='Ismarus:BAAANQAECgEIAQAAAA==.',
Ja='Jaarus:BAAANQAECgIIAgABNQAECgQIBQAJAAAAAA==.Jajal:BAAANQAECgcIEAABNQAECggIEQAJAAAAAA==.Jankadish:BAAANQAECgUICQAAAA==.Jaspirian:BAAANQADCgYIBgAAAA==.',
Je='Jehm:BAABNQAECoEbAAIRAAgKDg8lTwCYAQARAAgKDg8lTwCYAQAAAA==.Jerome:BAAANQADCgMIAwAAAA==.',
Ju='Juiceboxer:BAAANQAECgQICAABNQAECgUICwAJAAAAAA==.Juicy:BAAANQADCgYIBgAAAA==.Justicehand:BAAANQAECgIIAgAAAA==.',
Ka='Kagor:BAAANQADCgMIAwABNQAECgQIBQAJAAAAAA==.Kalia:BAABNQAECoEnAAMWAAkKYiF8AwDqAgAWAAgKJSJ8AwDqAgAKAAgKxRYhoQAfAgAAAA==.Katatonik:BAAANQAECgQIBQAAAA==.Katharina:BAAANQAECgYIEQAAAA==.Katoumae:BAAANQAECgUICAAAAA==.Katoumey:BAAANQAECgQIBwABNQAECgUICAAJAAAAAA==.',
Kh='Khumfuu:BAAANQAECgQIBgAAAA==.',
Ki='Kinan:BAABNQAECoEcAAMXAAgKBCIODQD8AgAXAAgKViEODQD8AgAQAAIKuCT1AQHAAAAAAA==.',
Ko='Korlo:BAAANQAECgQIBgAAAA==.',
Ku='Kuala:BAAANQADCgIIAgAAAA==.',
Ky='Kythin:BAAANQAECgIIBgABNQAECgkJJwAWAGIhAA==.',
La='Lacutis:BAAANQADCggICAAAAA==.',
Li='Lichmcconnel:BAABNQAECoEiAAMDAAgKkhtwBABwAgADAAgKkhtwBABwAgACAAEKWAdJdQAzAAAAAA==.Lillica:BAAANQADCgQIBAAAAA==.Lilmeesh:BAAANQADCgQIBAAAAA==.Lisabeth:BAAANQAECgEIAQABNQAFFAcIEwAXAEAbAA==.',
Lo='Lomponic:BAEBNQAECoEbAAIYAAgKnB2gFQCQAgAYAAgKnB2gFQCQAgAAAA==.Lonelyone:BAAANQADCggIFAAAAA==.Lore:BAABNQAECoEjAAIZAAkKJxbLFgAdAgAZAAkKJxbLFgAdAgAAAA==.',
Lu='Lunethra:BAABNQAECoEnAAIQAAkKEQ/KVgBFAgAQAAkKEQ/KVgBFAgAAAA==.Luukiss:BAAANQADCgQIBQAAAA==.Luyang:BAAANQADCgIIAgAAAA==.',
Ma='Madcow:BAAANQADCgcIBwABNQAECggIHQAQAIYiAA==.Madhat:BAAANQAECgYICwAAAA==.Magerag:BAABNQAECoEiAAIKAAkKViJaGgBkAwAKAAkKViJaGgBkAwAAAA==.Malyc:BAAANQAECgEIAQAAAA==.',
Mc='Mcribz:BAACNQAFFIEIAAIaAAUK2BwbBQC2AQAaAAUK2BwbBQC2AQA1AAQKgSYAAhoACQrgJcsMAD4DABoACQrgJcsMAD4DAAAA.',
Me='Meap:BAAANQAECgQIBQAAAA==.Mecatank:BAAANQAECgEJAQAAAA==.Medra:BAAANQABCgQIBAAAAA==.Meelonusk:BAAANQAECggIEwAAAA==.',
Mi='Michaelcoyle:BAABNQAECoEhAAIQAAgKKh56MAC5AgAQAAgKKh56MAC5AgAAAA==.Milo:BAAANQAECgYICwAAAA==.Mitra:BAAANQAECgcIEwAAAA==.',
Mo='Moesko:BAAANQAECgYIDwAAAA==.Mogianna:BAAANQABCgMIAwABNQADCgcICAAJAAAAAA==.Monktup:BAAANQAECgEIAQAAAA==.Monkzo:BAAANQADCgcIBwABNQAFFAIIAgAJAAAAAA==.Monnehbaggs:BAABNQAECoEwAAMbAAkKziV7AADvAwAbAAkKziV7AADvAwAcAAEKliJqHABmAAAAAA==.',
Mu='Munchies:BAAANQABCgIIAgAAAA==.Murdersamich:BAAANQADCggJCQAAAA==.',
My='Myraghor:BAABNQAECoEoAAISAAkKkiBVBABDAwASAAkKkiBVBABDAwAAAA==.',
Na='Nalmec:BAAANQADCgQIBAAAAA==.Naysayre:BAAANQABCgEIAQAAAA==.',
Ne='Nebody:BAAANQADCggIHgAAAA==.Necriss:BAABNQAECoEYAAIVAAcKDA7PrACNAQAVAAcKDA7PrACNAQAAAA==.',
Ni='Nike:BAAANQAECgcICwAAAA==.',
No='Norni:BAAANQAECgYIDQAAAA==.Nowarning:BAAANQADCgQIBQAAAA==.',
Og='Oghom:BAAANQADCgUIBQAAAA==.',
Op='Opeep:BAAANQAECgUICwAAAA==.',
Or='Oruum:BAAANQADCgYICAAAAA==.',
Pa='Papachance:BAAANQADCggIIAAAAA==.Papafrank:BAAANQADCggIHgAAAA==.Papapump:BAABNQAECoEVAAIdAAcKmBiBEwALAgAdAAcKmBiBEwALAgAAAA==.Parlare:BAAANQAECgUIDQABNQAECggIIgAeAFAdAA==.',
Pe='Perrinaya:BAAANQADCgQIBwAAAA==.',
Ph='Phoenixwing:BAAANQADCgYIDAAAAA==.',
Pi='Piedrita:BAAANQADCgMIAwAAAA==.Pinga:BAABNQAECoEgAAMcAAYKkx3oBwDYAQAcAAYKMhroBwDYAQAbAAUKXiCfYADNAQABNQAECggIIgAeAFAdAA==.',
Po='Poshifru:BAAANQAECgQICQABNQABCgIIAgAJAAAAAA==.',
Pr='Preposition:BAAANQAECgcIEgAAAA==.',
Pu='Pussduty:BAABNQAECoEhAAIQAAgKlB9TKwDLAgAQAAgKlB9TKwDLAgAAAA==.',
Ra='Raggnar:BAABNQAECoEeAAINAAkKxSEFFQA4AwANAAkKxSEFFQA4AwAAAA==.Ragingwaters:BAAANQADCgYIBgAAAA==.Ranvir:BAAANQADCggIEgAAAA==.Raun:BAABNQAECoEhAAMVAAgKrhzySACTAgAVAAgKrhzySACTAgATAAEK/QlvEAErAAAAAA==.',
Re='Reactionhank:BAAANQAECgUJBQAAAA==.Relaire:BAAANQAECgUJCwAAAA==.',
Ri='Riku:BAABNQAECoEXAAIfAAgKtRqSCACXAgAfAAgKtRqSCACXAgAAAA==.',
Ro='Roots:BAABNQAECoEbAAIIAAgKHyHBFQACAwAIAAgKHyHBFQACAwAAAA==.',
Ru='Rumplfourskn:BAAANQADCgIIBAAAAA==.',
Ry='Ryveri:BAABNQAECoEcAAIgAAkKHhrlSACWAgAgAAkKHhrlSACWAgAAAA==.',
Sa='Sablehide:BAABNQAECoEbAAQhAAcKeBEnDwAhAQAiAAcK7w3dGgB/AQAhAAUK7BInDwAhAQAeAAIKvA+CQABxAAAAAA==.Salute:BAAANQAECgUIBgAAAA==.Sanaty:BAAANQAECgUIDgAAAA==.Sathanus:BAAANQAECgEIAQAAAA==.Sazuni:BAAANQAECgUICwAAAA==.',
Sc='Scuffedname:BAAANQABCgQIBAAAAA==.',
Se='Secrett:BAAANQADCgcIDgAAAA==.',
Sf='Sfora:BAAANQADCgcICAAAAA==.',
Sh='Shelby:BAAANQADCgYICQAAAA==.Shiggs:BAAANQADCggIIgAAAA==.Shoçknezz:BAAANQADCgYICwAAAA==.',
Si='Silentsnake:BAEANQAECggIBwABNQAECgkJHgAIABcVAA==.Silverwolf:BAABNQAECoEiAAIdAAgKlRS9DwBUAgAdAAgKlRS9DwBUAgAAAA==.Simplyunlock:BAABNQAECoEgAAMBAAgKqhUKdgDWAQABAAcK2RQKdgDWAQACAAQKFhKrNADkAAAAAA==.Simplyvoided:BAAANQADCgYICgAAAA==.Siphin:BAAANQAECggICQAAAA==.Sizzlechop:BAABNQAECoEcAAIRAAcKmBGATwCWAQARAAcKmBGATwCWAQAAAA==.Sizzlerocks:BAAANQADCgYIBgAAAA==.',
Sk='Skizzak:BAAANQAECggICwABNQAFFAUICAAaANgcAA==.',
Sl='Slee:BAAANQAECgMIBwAAAA==.Slimedog:BAAANQAECgEJAQAAAA==.',
Sm='Smelvin:BAAANQAECgQIDQABNQAECggIEwAJAAAAAA==.',
Sn='Snailslolol:BAABNQAECoEXAAITAAgKDBPEVgD0AQATAAgKDBPEVgD0AQAAAA==.Snakes:BAEANQAECggIDgABNQAECgkJHgAIABcVAA==.Sneaksatoke:BAAANQADCgMIAwAAAA==.',
So='Solåra:BAAANQADCgUIBQABNQAECggIGgAEADoOAA==.Songs:BAAANQADCgQIBQABNQADCgcIEQAJAAAAAA==.',
Sq='Squirtin:BAAANQAECgQIBQAAAA==.',
St='Stalath:BAAANQADCggIGAAAAA==.',
Su='Sumarr:BAAANQAECgcIBQAAAA==.',
Sv='Svenn:BAAANQADCggIDwAAAA==.',
Sw='Swiftstrike:BAAANQADCgYIBgAAAA==.',
Ta='Taboo:BAAANQAECgYIDAAAAA==.Talron:BAAANQADCgcIEQAAAA==.Tatertots:BAAANQAECgcIEwAAAA==.',
Te='Tea:BAABNQAECoEhAAIQAAgKxyBgKwDLAgAQAAgKxyBgKwDLAgAAAA==.Teilsande:BAAANQADCgYJBgAAAA==.Teleportato:BAAANQAECgQIBAAAAA==.Templyn:BAABNQAECoEbAAMRAAgKSA68TwCVAQARAAgKSA68TwCVAQAaAAEKGAuY0AAvAAAAAA==.',
Th='Thannos:BAAANQADCggIEwAAAA==.Theus:BAAANQADCgUICQAAAA==.Thyrus:BAABNQAECoEiAAIeAAgKUB0XEACUAgAeAAgKUB0XEACUAgAAAA==.',
Ti='Tirna:BAABNQAECoEeAAIKAAgKNRI2qAAQAgAKAAgKNRI2qAAQAgAAAA==.',
To='Tomsellock:BAAANQADCggIFQAAAA==.',
Tu='Tullen:BAEBNQAECoEcAAIbAAgKhApQbQCeAQAbAAgKhApQbQCeAQAAAA==.Turanos:BAAANQAECgIIAgAAAA==.Tutio:BAAANQADCgYIBgAAAA==.',
Ty='Tyindaris:BAAANQADCgUJCAAAAA==.',
['Té']='Témplýn:BAAANQAECgEIAQABNQAECggIGwARAEgOAA==.',
['Të']='Tëmplýn:BAAANQADCgMIAwABNQAECggIGwARAEgOAA==.Tëmplÿn:BAAANQADCgEIAQABNQAECggIGwARAEgOAA==.',
Ul='Ullr:BAAANQADCgYICwAAAA==.Ultrachad:BAACNQAFFIEOAAIRAAUKAB2ACACrAQARAAUKAB2ACACrAQA1AAQKgScAAhEACQoiHlQUAPQCABEACQoiHlQUAPQCAAAA.',
Un='Unggoy:BAACNQAFFIETAAMXAAcKQBtxBQDiAQAXAAYKfhlxBQDiAQAQAAEK0CUTJgBmAAA1AAQKgSIAAxcACQo5JNgMAP8CABcACQrlI9gMAP8CABAAAQrrJlIdAWwAAAAA.Unholysin:BAAANQADCggIGAAAAA==.',
Ur='Urianna:BAAANQADCggIGQAAAA==.',
Uw='Uwuther:BAAANQADCgUIBQAAAA==.',
Va='Vaelthirion:BAAANQADCggIFgAAAA==.Vahidamus:BAAANQAECgIIAgAAAA==.Valmirax:BAAANQADCgcICgAAAA==.Valton:BAAANQAECgIIAgAAAA==.Vaurix:BAAANQAECgQICAAAAA==.',
Ve='Vezarion:BAAANQADCgUIBgAAAA==.',
Wa='Wafuzz:BAAANQADCgYIBgAAAA==.Waters:BAAANQADCgMIAwAAAA==.',
We='Wesellpallys:BAAANQADCgUIBQABNQAECggIEwAJAAAAAA==.',
Wi='Windhorn:BAAANQADCgUICgAAAA==.Winds:BAAANQADCgcIEQAAAA==.Windtalker:BAAANQADCgQIBAABNQADCgUIBQAJAAAAAA==.',
Wo='Wolfquota:BAABNQAECoEXAAINAAkKRh+7HAAEAwANAAkKRh+7HAAEAwAAAA==.Wombaa:BAABNQAECoEgAAMaAAkKcSVYBwB5AwAaAAkKcSVYBwB5AwAUAAEKGx8phgBUAAAAAA==.',
Wr='Wrathdk:BAAANQAECgcIDgABNQAFFAIIAwAJAAAAAA==.Wrathm:BAAANQAFFAIIAwAAAA==.Wrathmo:BAAANQAECgYIDwABNQAFFAIIAwAJAAAAAA==.Wrenkyian:BAAANQADCgUIBQAAAA==.',
Ya='Yani:BAAANQADCgYICgAAAA==.',
Ye='Yeah:BAAANQABCgUIBAAAAA==.',
Za='Zakos:BAAANQADCggICAAAAA==.Zareeq:BAAANQADCgIIAgAAAA==.',
Zo='Zoa:BAAANQADCggIDAAAAA==.',
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
