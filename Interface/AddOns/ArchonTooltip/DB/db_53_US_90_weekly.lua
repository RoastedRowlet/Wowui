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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Unknown-Unknown','Shaman-Restoration','Rogue-Assassination','Paladin-Holy','Mage-Arcane','DeathKnight-Frost','DemonHunter-Vengeance','DemonHunter-Devourer','Paladin-Retribution','Mage-Frost','Hunter-Marksmanship','Paladin-Protection','Hunter-BeastMastery','DeathKnight-Unholy','Priest-Holy','Druid-Guardian','Shaman-Enhancement','Evoker-Preservation','Priest-Discipline','Shaman-Elemental','Warrior-Arms','DeathKnight-Blood',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abacus:BAAANQAECgQIBgAAAA==.',
Ad='Adam:BAACNQAFFIEVAAMBAAcKehnAAgARAgABAAYKsBfAAgARAgACAAIKdB3KBwCzAAA1AAQKgSIABAIACQoEJNYGAIoCAAEACAp5I5UgAM8CAAIACAprGtYGAIoCAAMAAQpqHpUlADoAAAAA.',
Ak='Akurama:BAAANQAECgMIAwAAAA==.',
Al='Allfrowns:BAAANQAECgcJDgAAAA==.Allsmiles:BAAANQAECgQIBAAAAA==.Allura:BAAANQADCgcICQAAAA==.Alunaris:BAAANQAECgEJAgAAAA==.',
Am='Amoon:BAAANQAECgYIEAAAAA==.',
An='Ancalagon:BAAANQADCgQIBAAAAA==.',
Ar='Archymedes:BAAANQAECgIIAQAAAA==.Arckady:BAAANQADCggIDgAAAA==.Array:BAAANQADCggICAAAAA==.Artharius:BAABNQAECoEZAAMEAAcKSiHdFQBTAgAEAAcKSiHdFQBTAgAFAAUK4RQTFgA2AQAAAA==.',
Au='Auburnbeard:BAAANQAECgEJAQAAAA==.',
Av='Averle:BAAANQAECgIIAgAAAA==.',
Ba='Badchoices:BAAANQAECgEIAQAAAA==.Badkittie:BAAANQADCgUICgAAAA==.Baretta:BAAANQAECgYIBwAAAA==.',
Be='Beefsnake:BAEBNQAECoEaAAIGAAkKdhKkKgBDAgAGAAkKdhKkKgBDAgAAAA==.Beefytips:BAAANQADCgIJAgAAAA==.Bettyßaraxus:BAAANQADCgQIBAABNQAECgYIDAAHAAAAAA==.Bettyßlight:BAAANQADCgUICAABNQAECgYIDAAHAAAAAA==.',
Bi='Bigunsforu:BAAANQADCggIHgAAAA==.',
Bo='Bogs:BAAANQAECgcIEQAAAA==.Bolomorte:BAAANQADCgYJBgAAAA==.Boragish:BAAANQAECgYICwAAAA==.Boulderfist:BAAANQADCggIFAAAAA==.',
Br='Brolic:BAAANQAECgUIDAAAAA==.',
Bu='Bubbleman:BAAANQADCgQIBAAAAA==.Bubblestomps:BAAANQADCgMIAwAAAA==.Burial:BAAANQADCggICwAAAA==.',
Bw='Bwonsamdy:BAAANQAECgIIAgAAAA==.',
['Bä']='Bämboo:BAAANQAECgcIEwAAAA==.',
Ca='Cail:BAEANQAECgQICgAAAA==.Calamìty:BAAANQAECgMIAwAAAA==.Calisa:BAAANQAECgYIEQAAAA==.Cantstandya:BAAANQAECggIEgAAAA==.Carnifex:BAAANQAECgcIEwAAAA==.',
Ce='Ceryph:BAAANQADCgUJBQAAAA==.',
Ch='Charis:BAAANQADCgEIAQAAAA==.Chewbub:BAAANQADCgIIAgAAAA==.Chigutotems:BAABNQAECoEbAAIIAAkKrB26DgAmAwAIAAkKrB26DgAmAwAAAA==.Chozen:BAABNQAECoEhAAIJAAkK9yK9BQBNAwAJAAkK9yK9BQBNAwAAAA==.Chroniccloud:BAAANQAECgEIAQAAAA==.',
Co='Cornelius:BAAANQAECgMIBQAAAA==.Coulee:BAAANQADCgQJCAABNQAECgYIDgAHAAAAAA==.',
Cr='Cronicpain:BAAANQAECgQIBAAAAA==.',
Cy='Cymbi:BAAANQABCgQIAwAAAA==.',
Da='Daks:BAAANQADCgQIBAAAAA==.Darklucrezia:BAAANQAECgcIEwAAAA==.Darkpyro:BAAANQADCggICAAAAA==.',
De='Deetsy:BAAANQADCgYICAAAAA==.Dextrose:BAAANQAECgQIBAABNQAECggIDwAHAAAAAA==.',
Dk='Dkbig:BAAANQADCggIEwAAAA==.',
Dr='Dracarius:BAAANQADCggIDgAAAA==.Drtypinkcake:BAAANQAECgUIBgAAAA==.Druidcant:BAAANQADCgYJBgAAAA==.Drworldwide:BAAANQAECgQICAAAAA==.Dryad:BAAANQADCgcIDQAAAA==.',
Du='Durkk:BAAANQAECgYIEgAAAA==.Durza:BAAANQADCggICAAAAA==.',
['Dä']='Dännydevito:BAAANQADCgMIBAAAAA==.',
En='Enss:BAAANQADCgUJBQAAAA==.',
Es='Estara:BAAANQAECgYIEQAAAA==.',
Et='Etali:BAAANQAECgUICgAAAA==.Etherious:BAAANQADCgUIBQABNQAECgYICAAHAAAAAA==.',
Fa='Fanis:BAAANQAECgUICgAAAA==.',
Fi='Fibo:BAAANQADCgQIBAAAAA==.',
Fl='Flashis:BAAANQAECggIEQAAAA==.Floor:BAAANQABCgIIAgAAAA==.Florago:BAAANQADCggIDgAAAA==.',
Fo='Force:BAAANQAECgEIAgAAAA==.',
Fr='Frakir:BAAANQAECgYIEgAAAA==.',
Fu='Furrypaw:BAAANQAECgYIEgAAAA==.',
Fw='Fwapp:BAACNQAFFIENAAIKAAUKVBYlBgC1AQAKAAUKVBYlBgC1AQA1AAQKgSYAAgoACQp6JWoCALwDAAoACQp6JWoCALwDAAAA.',
Ga='Galvanize:BAAANQAECgQIBgAAAA==.',
Gi='Gijaick:BAAANQAECgIIBQAAAA==.',
Gl='Glizzo:BAABNQAECoEhAAILAAgKERMxkAAdAgALAAgKERMxkAAdAgAAAA==.Gloomrider:BAAANQADCgUIBQAAAA==.',
Go='Gold:BAAANQADCgUIBQAAAA==.Goldhawk:BAAANQADCgEIAQAAAA==.Gotwiped:BAABNQAECoEUAAIMAAcKARirLgDGAQAMAAcKARirLgDGAQAAAA==.',
Gu='Gunnery:BAAANQAECggIDgAAAA==.',
Ha='Haoleboy:BAAANQADCggIFAAAAA==.Hatter:BAABNQAECoEbAAMNAAgK8RhLCgDXAQAOAAgKFRXKGgBLAgANAAcK7RZLCgDXAQAAAA==.',
He='Hellraiser:BAAANQAECgUICAAAAA==.',
Hi='Hidduka:BAABNQAECoEaAAIKAAgKbxxQKgCHAgAKAAgKbxxQKgCHAgAAAA==.Hills:BAAANQAECgEIAQAAAA==.',
Ho='Holyascended:BAAANQADCggIFgAAAA==.Holydarkness:BAAANQADCgYIBgAAAA==.Holykilla:BAAANQADCgUIBQAAAA==.Holykiller:BAAANQADCgEIAQAAAA==.Hoplite:BAAANQADCgIIAgABNQAECgYIBwAHAAAAAA==.Howlly:BAAANQAECgQICgAAAA==.',
Hr='Hraun:BAAANQADCgIIAQAAAA==.',
Ik='Ikeanola:BAABNQAECoEeAAIPAAkKxwU6rQBTAQAPAAkKxwU6rQBTAQAAAA==.',
In='Indras:BAAANQADCgcIDgAAAA==.Ines:BAABNQAECoEbAAIMAAgK2R57FgCSAgAMAAgK2R57FgCSAgAAAA==.Inhume:BAAANQADCggJCQAAAA==.',
Is='Ismarus:BAAANQAECgEIAQAAAA==.',
Ja='Jaarus:BAAANQADCgQIBAABNQAECgQIBQAHAAAAAA==.Jajal:BAAANQAECgYICQABNQAECggIEQAHAAAAAA==.Jankadish:BAAANQAECgUICQAAAA==.Jaspirian:BAAANQADCgYIBgAAAA==.',
Je='Jehm:BAAANQAECgYIEwAAAA==.Jerome:BAAANQADCgMIAwAAAA==.',
Ju='Juiceboxer:BAAANQAECgQICAABNQAECgUIBwAHAAAAAA==.Juicy:BAAANQADCgYIBgAAAA==.Justicehand:BAAANQAECgIIAgAAAA==.',
Ka='Kagor:BAAANQADCgMIAwABNQAECgQIBQAHAAAAAA==.Kalia:BAABNQAECoEkAAMQAAkK5CDlAgDyAgAQAAgKlyHlAgDyAgALAAgKxRbZiQAsAgAAAA==.Katatonik:BAAANQAECgQIBQAAAA==.Katharina:BAAANQAECgYIEQAAAA==.Katoumae:BAAANQAECgIIAwABNQAECgMIAwAHAAAAAA==.Katoumey:BAAANQAECgMIAwAAAA==.',
Kh='Khumfuu:BAAANQAECgQIBgAAAA==.',
Ki='Kinan:BAAANQAECgYIEgAAAA==.',
Ko='Korlo:BAAANQAECgIIAgAAAA==.',
Ku='Kuala:BAAANQADCgIIAgAAAA==.',
Ky='Kythin:BAAANQAECgIJBAABNQAECgkJJAAQAOQgAA==.',
La='Lacutis:BAAANQADCggICAAAAA==.',
Li='Lichmcconnel:BAABNQAECoEaAAMDAAgKPBt2AwCCAgADAAgKPBt2AwCCAgACAAEKWAcSbgA1AAAAAA==.Lillica:BAAANQADCgQIBAAAAA==.Lilmeesh:BAAANQADCgQIBAAAAA==.Lisabeth:BAAANQAECgEIAQABNQAFFAcIEgARAEAbAA==.',
Lo='Lomponic:BAEANQAECgcIEAAAAA==.Lonelyone:BAAANQADCggIDAAAAA==.Lore:BAABNQAECoEgAAISAAkKUhTlHwCKAQASAAkKUhTlHwCKAQAAAA==.',
Lu='Lunethra:BAABNQAECoEkAAITAAkKwQ2aSwA+AgATAAkKwQ2aSwA+AgAAAA==.Luukiss:BAAANQADCgQIBQAAAA==.Luyang:BAAANQADCgIIAgAAAA==.',
Ma='Madcow:BAAANQADCgcIBwABNQAECggIGwATAGoiAA==.Madhat:BAAANQAECgYICwAAAA==.Magerag:BAABNQAECoEeAAILAAkKViKrEgB6AwALAAkKViKrEgB6AwAAAA==.Malyc:BAAANQAECgEIAQAAAA==.',
Mc='Mcribz:BAABNQAECoEjAAIUAAkKriXECQBMAwAUAAkKriXECQBMAwAAAA==.',
Me='Meap:BAAANQAECgQIBQAAAA==.Mecatank:BAAANQAECgEJAQAAAA==.Medra:BAAANQABCgQIBAAAAA==.Meelonusk:BAAANQAECgcJEgAAAA==.',
Mi='Michaelcoyle:BAABNQAECoEaAAITAAgKbR0EKgC0AgATAAgKbR0EKgC0AgAAAA==.Milo:BAAANQAECgYICwAAAA==.Mitra:BAAANQAECgYIEQAAAA==.',
Mo='Moesko:BAAANQAECgQICwAAAA==.Mogianna:BAAANQABCgMIAwABNQADCgcICAAHAAAAAA==.Monktup:BAAANQAECgEIAQAAAA==.Monkzo:BAAANQADCgcIBwABNQAFFAIIAgAHAAAAAA==.Monnehbaggs:BAABNQAECoEmAAIVAAkKFyNXAgC0AwAVAAkKFyNXAgC0AwAAAA==.',
Mu='Munchies:BAAANQABCgIIAgAAAA==.Murdersamich:BAAANQADCggJCQAAAA==.',
My='Myraghor:BAABNQAECoEkAAIWAAkKoR+eAwA2AwAWAAkKoR+eAwA2AwAAAA==.',
Na='Nalmec:BAAANQADCgQIBAAAAA==.Naysayre:BAAANQABCgEIAQAAAA==.',
Ne='Nebody:BAAANQADCgcIGAAAAA==.Necriss:BAAANQAECgYIEAAAAA==.',
Ni='Nike:BAAANQAECgQIBQAAAA==.',
No='Norni:BAAANQAECgQICQAAAA==.Nowarning:BAAANQADCgQIBQAAAA==.',
Op='Opeep:BAAANQAECgUICwAAAA==.',
Or='Oruum:BAAANQADCgYICAAAAA==.',
Pa='Papachance:BAAANQADCggIHgAAAA==.Papafrank:BAAANQADCggIFwAAAA==.Papapump:BAABNQAECoEUAAIXAAcKmBhyEAAbAgAXAAcKmBhyEAAbAgAAAA==.Parlare:BAAANQAECgUICQABNQAECggIHAAYAFAdAA==.',
Pe='Perrinaya:BAAANQADCgQIBwAAAA==.',
Ph='Phoenixwing:BAAANQADCgYJBgAAAA==.',
Pi='Piedrita:BAAANQADCgEJAQAAAA==.Pinga:BAABNQAECoEaAAMZAAYKTxzaBgDeAQAZAAYKMhraBgDeAQAVAAUKvRqDZgCEAQABNQAECggIHAAYAFAdAA==.',
Po='Poshifru:BAAANQAECgQIBgABNQABCgIIAgAHAAAAAA==.',
Pr='Preposition:BAAANQAECgYICwAAAA==.',
Pu='Pussduty:BAABNQAECoEfAAITAAgKlB/PIADcAgATAAgKlB/PIADcAgAAAA==.',
Ra='Raggnar:BAABNQAECoEeAAIaAAkKxSHODwBPAwAaAAkKxSHODwBPAwAAAA==.Ragingwaters:BAAANQADCgYIBgAAAA==.Ranvir:BAAANQADCgUICgAAAA==.Raun:BAABNQAECoEZAAMPAAgKIRoNTABiAgAPAAgKIRoNTABiAgAKAAEK/Qkw9wArAAAAAA==.',
Re='Reactionhank:BAAANQAECgUJBQAAAA==.Relaire:BAAANQAECgUJCwAAAA==.',
Ri='Riku:BAAANQAECgYIDgAAAA==.',
Ro='Roots:BAAANQAECgUIDwAAAA==.',
Ry='Ryveri:BAABNQAECoEZAAIbAAkKEhpKPwCTAgAbAAkKEhpKPwCTAgAAAA==.',
Sa='Sablehide:BAAANQAECgYIEwAAAA==.Salute:BAAANQAECgUIBgAAAA==.Sanaty:BAAANQAECgUICwAAAA==.Sathanus:BAAANQADCgQIBwAAAA==.Sazuni:BAAANQAECgMIBgAAAA==.',
Sc='Scuffedname:BAAANQABCgQIBAAAAA==.',
Se='Secrett:BAAANQADCgcIDgAAAA==.',
Sf='Sfora:BAAANQADCgcICAAAAA==.',
Sh='Shelby:BAAANQADCgYICQAAAA==.Shiggs:BAAANQADCggIGgAAAA==.Shortsighted:BAAANQADCgEIAQABNQAECgkJIwAUAK4lAA==.Shoçknezz:BAAANQADCgYICwAAAA==.',
Si='Silverwolf:BAABNQAECoEbAAIXAAcKRBUpEQAMAgAXAAcKRBUpEQAMAgAAAA==.Simplyunlock:BAABNQAECoEbAAMBAAgKgxUtYwDeAQABAAcKWxQtYwDeAQACAAQKFhJXMQDrAAAAAA==.Simplyvoided:BAAANQADCgYICgAAAA==.Siphin:BAAANQAECggICQAAAA==.Sizzlechop:BAAANQAECgYIEwAAAA==.Sizzlerocks:BAAANQADCgYIBgAAAA==.',
Sk='Skizzak:BAAANQAECgUIBAABNQAECgkJIwAUAK4lAA==.',
Sl='Slee:BAAANQAECgMIBQAAAA==.Slimedog:BAAANQAECgEJAQAAAA==.',
Sm='Smelvin:BAAANQAECgQICQABNQAECgcJEgAHAAAAAA==.',
Sn='Snailslolol:BAAANQAECgYIDgAAAA==.Snakes:BAEANQAECggICwABNQAECgkJGgAGAHYSAA==.Sneaksatoke:BAAANQADCgMIAwAAAA==.',
So='Solåra:BAAANQADCgUIBQABNQAECgcIGAAOALoLAA==.Songs:BAAANQADCgQIBQABNQADCgcIEQAHAAAAAA==.',
Sq='Squirtin:BAAANQAECgQIBAAAAA==.',
St='Stalath:BAAANQADCggIEQAAAA==.',
Su='Sumarr:BAAANQAECgcIBQAAAA==.',
Sv='Svenn:BAAANQADCggIDwAAAA==.',
Sw='Swiftstrike:BAAANQADCgYIBgAAAA==.',
Ta='Taboo:BAAANQAECgYIDAAAAA==.Talron:BAAANQADCgcIEQAAAA==.Tatertots:BAAANQAECgYIDAAAAA==.',
Te='Tea:BAABNQAECoEdAAITAAgK7B+QIgDUAgATAAgK7B+QIgDUAgAAAA==.Teilsande:BAAANQADCgYJBgAAAA==.Teleportato:BAAANQADCggICAAAAA==.Templyn:BAAANQAECgcIEAAAAA==.',
Th='Thannos:BAAANQADCggICwAAAA==.Theus:BAAANQADCgUICQAAAA==.Thyrus:BAABNQAECoEcAAIYAAgKUB34DQCeAgAYAAgKUB34DQCeAgAAAA==.',
Ti='Tirna:BAAANQAECgYIEgAAAA==.',
To='Tomsellock:BAAANQADCggIFQAAAA==.',
Tr='Tripinator:BAAANQADCgUIBQAAAA==.',
Tu='Tullen:BAEANQAECgYIEQAAAA==.Turanos:BAAANQADCggIDgAAAA==.Tutio:BAAANQADCgYIBgAAAA==.',
Ty='Tyindaris:BAAANQADCgUJCAAAAA==.',
['Té']='Témplýn:BAAANQAECgEIAQABNQAECgcIEAAHAAAAAA==.',
['Të']='Tëmplýn:BAAANQADCgMIAwABNQAECgcIEAAHAAAAAA==.',
Ul='Ultrachad:BAACNQAFFIEKAAIcAAUKMBM8CQBuAQAcAAUKMBM8CQBuAQA1AAQKgSQAAhwACQqjHVkSAPECABwACQqjHVkSAPECAAAA.',
Un='Unggoy:BAACNQAFFIESAAMRAAcKQBu2AwD7AQARAAYKfhm2AwD7AQATAAEK0CUTHgBqAAA1AAQKgSEAAxEACQo5JMYJABoDABEACQrlI8YJABoDABMAAQrrJor9AG4AAAAA.Unholysin:BAAANQADCggIEQAAAA==.',
Ur='Urianna:BAAANQADCggIEQAAAA==.',
Va='Vaelthirion:BAAANQADCggIEwAAAA==.Vahidamus:BAAANQADCgcICgAAAA==.Valmirax:BAAANQADCgcIBwAAAA==.Valton:BAAANQAECgIIAgAAAA==.Vaurix:BAAANQAECgQIBAAAAA==.',
Ve='Vezarion:BAAANQADCgUIBgAAAA==.',
Wa='Wafuzz:BAAANQADCgYIBgAAAA==.Waters:BAAANQADCgMIAwAAAA==.',
We='Wesellpallys:BAAANQADCgUIBQABNQAECgcJEgAHAAAAAA==.',
Wi='Winds:BAAANQADCgcIEQAAAA==.',
Wo='Wolfquota:BAAANQAECggJEAAAAA==.Wombaa:BAABNQAECoEdAAMUAAgKiyVEDgAcAwAUAAgKiyVEDgAcAwAMAAEKGx/EdQBZAAAAAA==.',
Wr='Wrathdk:BAAANQAECgcIDgABNQAFFAEIAQAHAAAAAA==.Wrathm:BAAANQAFFAEIAQAAAA==.Wrathmo:BAAANQAECgYICgABNQAFFAEIAQAHAAAAAA==.Wrenkyian:BAAANQADCgUIBQAAAA==.',
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
