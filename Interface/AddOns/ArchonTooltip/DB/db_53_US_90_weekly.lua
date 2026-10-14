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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Unknown-Unknown','Mage-Arcane','Monk-Mistweaver','Rogue-Outlaw','Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','Rogue-Assassination','DemonHunter-Havoc','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Druid-Guardian','Warrior-Fury','Priest-Shadow','Paladin-Holy','DeathKnight-Frost','Mage-Frost','Paladin-Protection','DeathKnight-Unholy','Priest-Holy','Priest-Discipline','Shaman-Enhancement','Evoker-Preservation','Druid-Feral','Warrior-Arms','Evoker-Devastation','Evoker-Augmentation',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abacus:BAAANQAECgQIBgAAAA==.',
Ad='Adam:BAACNQAFFH8XAAMBAAcKihgABwD9AQABAAYKnhUABwD9AQACAAIKdB3ECwCjAAA1AAQKfykABAIACQqAJH4IAHQCAAEACAocJEEwAMQCAAIACApSGX4IAHQCAAMAAQoAAIYuADgAAAAA.',
Ak='Akurama:BAAANQAECgUIBwAAAA==.',
Al='Allfrowns:BAAANQAECgcJDgAAAA==.Allsmiles:BAAANQAECgYIDQAAAA==.Allura:BAAANQAECgIIAgAAAA==.Alunaris:BAAANQAECgEJAgAAAA==.',
Am='Amoon:BAABNQAECn8iAAMEAAgKpxJaKQD1AQAEAAgKpxJaKQD1AQAFAAIKZxCZKQBiAAAAAA==.',
An='Ancalagon:BAAANQADCgQIBAAAAA==.',
Ar='Archymedes:BAAANQAECgIIAQAAAA==.Arckady:BAAANQAECgIIAgAAAA==.Array:BAAANQADCggICAAAAA==.Artharius:BAABNQAECn8cAAMGAAgKyyFEFgCaAgAGAAgKyyFEFgCaAgAHAAUKNxTWGwAlAQAAAA==.',
Au='Auburnbeard:BAAANQAECgEJAQAAAA==.',
Av='Averle:BAAANQAECgIIAgAAAA==.',
Ba='Badchoices:BAAANQAECgEIAQAAAA==.Badkittie:BAAANQADCgUICgAAAA==.Baretta:BAAANQAECgYIBwAAAA==.',
Be='Beefsnake:BAEBNQAECn8gAAIIAAkK+RK0KwB5AgAIAAkK+RK0KwB5AgAAAA==.Beefytips:BAAANQADCgIJAgAAAA==.Bettyßaraxus:BAAANQAECgYICgAAAA==.Bettyßarrage:BAAANQADCgUIBQABNQAECgYICgAJAAAAAA==.Bettyßlight:BAAANQADCgUICAABNQAECgYICgAJAAAAAA==.',
Bi='Bigunsforu:BAAANQAECgYIBwAAAA==.',
Bo='Bogs:BAABNQAECn8aAAIKAAkKNRs1eACNAgAKAAkKNRs1eACNAgAAAA==.Bolomorte:BAAANQADCgYJBgAAAA==.Boragish:BAAANQAECgcIDgAAAA==.Boulderfist:BAAANQADCggIFAAAAA==.',
Br='Brolic:BAAANQAECgcIEwAAAA==.',
Bu='Bubbleman:BAAANQADCgQIBAAAAA==.Bubblestomps:BAAANQADCgMIAwAAAA==.Burial:BAAANQAECgIIAgAAAA==.Burntchicken:BAAANQABCgMIAwAAAA==.',
Bw='Bwonsamdy:BAAANQAECgIIAgAAAA==.',
['Bä']='Bämboo:BAABNQAECn8dAAILAAgKUhrmEABsAgALAAgKUhrmEABsAgAAAA==.',
Ca='Cail:BAEANQAECgUIEwAAAA==.Calamìty:BAAANQAECgMIAwAAAA==.Calisa:BAABNQAECn8hAAIMAAgKQxO1BwAyAgAMAAgKQxO1BwAyAgAAAA==.Cantstandya:BAABNQAECn8ZAAINAAkK8B1RVQCSAgANAAkK8B1RVQCSAgAAAA==.Carnifex:BAABNQAECn8VAAMOAAcK+BaciACLAQAOAAYK8xiciACLAQAPAAcKLA5YjQBkAQABNQAECggIEQAJAAAAAA==.',
Ce='Ceryph:BAAANQADCgUJBQAAAA==.',
Ch='Charis:BAAANQADCgEIAQAAAA==.Chewbub:BAAANQADCgIIAgAAAA==.Chigutotems:BAEBNQAECn8lAAIPAAkKux48FQAjAwAPAAkKux48FQAjAwAAAA==.Chow:BAAANQABCgUIBQABNQAECgYIBgAJAAAAAA==.Chozen:BAACNQAFFH8GAAIQAAMKOiCXDAArAQAQAAMKOiCXDAArAQA1AAQKfykAAhAACQolI/gKADADABAACQolI/gKADADAAAA.Chroniccloud:BAAANQAECgEIAQAAAA==.',
Co='Cornelius:BAAANQAECgUICgAAAA==.Corporicky:BAAANQAECgEIAQAAAA==.Coulee:BAAANQADCgQJCAABNQAECggIGQARANwdAA==.',
Cr='Cronicpain:BAAANQAECgUIBgAAAA==.',
Cy='Cymbi:BAAANQABCgQIAwAAAA==.',
Da='Daks:BAAANQADCgQIBAAAAA==.Darklucrezia:BAABNQAECn8eAAMSAAkKIxadZwBCAgASAAgKTBidZwBCAgATAAEKLAnJjAAxAAAAAA==.Darkpyro:BAAANQADCggIEAAAAA==.',
De='Deetsy:BAAANQADCgYICAAAAA==.Dextrose:BAAANQAECgcICwABNQAECggIEwAJAAAAAA==.',
Di='Dicey:BAAANQAECgcIBwABNQAECggIEQAJAAAAAA==.',
Dk='Dkbig:BAAANQAECgUIBgAAAA==.',
Dr='Dracarius:BAAANQAECgIIAgAAAA==.Drtypinkcake:BAAANQAECgUICgAAAA==.Druidcant:BAAANQADCgYJBgAAAA==.Drworldwide:BAAANQAECggICQAAAA==.Dryad:BAAANQAECgIIAgAAAA==.',
Du='Durkk:BAABNQAECn8lAAIUAAgKVx8bHgC/AgAUAAgKVx8bHgC/AgAAAA==.Durza:BAAANQADCggICAAAAA==.',
['Dä']='Dännydevito:BAAANQADCgMIBAAAAA==.',
En='Enss:BAAANQADCgUJBQAAAA==.',
Es='Estara:BAABNQAECn8jAAIVAAgKMQ0RIwB4AQAVAAgKMQ0RIwB4AQAAAA==.',
Et='Etali:BAABNQAECn8aAAIWAAgKrBUEDAD7AQAWAAgKrBUEDAD7AQAAAA==.Etherious:BAAANQAECgQIBAABNQAECgcICwAJAAAAAA==.',
Fa='Fanis:BAABNQAECn8aAAITAAgKUwttNACmAQATAAgKUwttNACmAQAAAA==.',
Fi='Fibo:BAAANQADCgQIBAAAAA==.',
Fl='Flashis:BAAANQAECggIEQABNQAECgkJGAAXAAgRAA==.Floor:BAAANQABCgIIAgAAAA==.Florago:BAAANQAECgIIAgAAAA==.',
Fo='Force:BAAANQAECgEIAgAAAA==.',
Fr='Frakir:BAABNQAECn8lAAMPAAgKTRqfPgBjAgAPAAgKTRqfPgBjAgAOAAEKAACATgEkAAAAAA==.',
Fu='Furrypaw:BAABNQAECn8eAAMLAAgK3x1XDgCZAgALAAgK3x1XDgCZAgAGAAEKAAAQcQAnAAAAAA==.',
Fw='Fwapp:BAACNQAFFH8UAAIYAAYKvxTEBgD6AQAYAAYKvxTEBgD6AQA1AAQKfywAAhgACQp6JagEAKsDABgACQp6JagEAKsDAAAA.',
Ga='Galvanize:BAAANQAECgQICwAAAA==.',
Gi='Gijaick:BAAANQAECgYIDwAAAA==.',
Gl='Glizzo:BAABNQAECn8vAAIKAAkKiRSdggB4AgAKAAkKiRSdggB4AgAAAA==.Gloomrider:BAAANQADCgUIBQAAAA==.',
Go='Gold:BAAANQADCgUIBQAAAA==.Goldhawk:BAAANQADCgEIAQAAAA==.Gotwiped:BAABNQAECn8hAAIZAAgKCR5/GgCzAgAZAAgKCR5/GgCzAgAAAA==.',
Gu='Gunnery:BAAANQAECggIDgAAAA==.',
Ha='Hantaz:BAAANQAECgMIAwAAAA==.Haoleboy:BAAANQADCggIIQAAAA==.Hatter:BAABNQAECn8mAAMEAAkKgBq/FQCzAgAEAAkKhhm/FQCzAgAFAAcKXBewDwC1AQAAAA==.',
He='Hellraiser:BAAANQAECgUIDwAAAA==.',
Hi='Hidduka:BAABNQAECn8aAAIYAAgKbxz8OwByAgAYAAgKbxz8OwByAgAAAA==.Hills:BAAANQAECgEIAQAAAA==.',
Ho='Holyascended:BAAANQADCggIFgAAAA==.Holydarkness:BAAANQADCgYIBgAAAA==.Holykilla:BAAANQADCgUIBQAAAA==.Holykiller:BAAANQADCgEIAQAAAA==.Hoplite:BAAANQADCgYICAABNQAECgcICwAJAAAAAA==.Howlly:BAABNQAECn8YAAIaAAcKRSLqBADQAgAaAAcKRSLqBADQAgAAAA==.',
Hr='Hraun:BAAANQADCgIIAQAAAA==.',
Hu='Hulner:BAAANQAECggIAgAAAA==.',
Ik='Ikeanola:BAABNQAECn8eAAINAAkKlgX16QBBAQANAAkKlgX16QBBAQAAAA==.',
In='Indras:BAAANQADCgcIFAAAAA==.Ines:BAABNQAECn8lAAIZAAkKih8JEgD7AgAZAAkKih8JEgD7AgAAAA==.Inhume:BAAANQADCggJCQAAAA==.',
Is='Ismarus:BAAANQAECgQIBQAAAA==.',
Ja='Jaarus:BAAANQAECgIIAwABNQAECgQIBQAJAAAAAA==.Jajal:BAABNQAECn8YAAIXAAkKCBGeJAAIAgAXAAkKCBGeJAAIAgAAAA==.Jankadish:BAAANQAECgUICQAAAA==.Jaspirian:BAAANQADCgYIBgAAAA==.',
Je='Jehm:BAABNQAECn8fAAIUAAgK+A4HUwCmAQAUAAgK+A4HUwCmAQAAAA==.Jerome:BAAANQADCgMIAwAAAA==.',
Ju='Juiceboxer:BAAANQAECgQICAABNQAECgUICwAJAAAAAA==.Juicy:BAAANQADCgYIBgAAAA==.Justicehand:BAAANQAECgIIAgAAAA==.',
Ka='Kaestia:BAAANQAECgEIAQABNQAECgkJKgAaAIkgAA==.Kagor:BAAANQADCgMIAwABNQAECgQIBQAJAAAAAA==.Kalia:BAABNQAECn8qAAMaAAkKiSDCBADWAgAaAAgKaiHCBADWAgAKAAgKgxbJuQAPAgAAAA==.Kalipto:BAAANQADCgcICAAAAA==.Katatonik:BAAANQAECgQIBQAAAA==.Katharina:BAAANQAECgcIEgAAAA==.Katoumae:BAAANQAFFAEIAQAAAA==.Katoumey:BAAANQAECgQICwABNQAFFAEIAQAJAAAAAA==.',
Kh='Khumfuu:BAAANQAECgQIBgAAAA==.',
Ki='Kinan:BAABNQAECn8jAAMTAAgKtyJ4DAASAwATAAgKcCJ4DAASAwASAAIKlST/HAG7AAAAAA==.',
Ko='Konan:BAAANQADCgMIAwAAAA==.Korlo:BAAANQAECgUIBwAAAA==.',
Ku='Kuala:BAAANQADCgIIAgAAAA==.',
Ky='Kythin:BAAANQAECgMICAABNQAECgkJKgAaAIkgAA==.',
La='Lacutis:BAAANQADCggICAAAAA==.',
Li='Lichmcconnel:BAABNQAECn8iAAMDAAgK8xukBQBhAgADAAgK8xukBQBhAgACAAEKWAe+egAyAAAAAA==.Lillica:BAAANQADCgQIBAAAAA==.Lilmeesh:BAAANQADCgQIBAAAAA==.Lisabeth:BAAANQAECgEIAQABNQAFFAcIFAATAIEfAA==.',
Lo='Lomponic:BAEBNQAECn8jAAIXAAgK2B/6EADoAgAXAAgK2B/6EADoAgAAAA==.Lonelyone:BAAANQADCggIGwAAAA==.Lore:BAACNQAFFH8FAAIbAAIKHxR8CwCHAAAbAAIKHxR8CwCHAAA1AAQKfyYAAhsACQpqGB8ZACoCABsACQpqGB8ZACoCAAAA.',
Lu='Lunethra:BAABNQAECn8qAAISAAkKcg4zagA8AgASAAkKcg4zagA8AgAAAA==.Luukiss:BAAANQADCgQIBQAAAA==.Luyang:BAAANQADCgIIAgAAAA==.',
Ma='Madcow:BAAANQADCgcIBwABNQAECggIHQASAFAiAA==.Madhat:BAAANQAECgcIDQAAAA==.Magerag:BAABNQAECn8lAAIKAAkKqCEOHgBgAwAKAAkKqCEOHgBgAwAAAA==.Malyc:BAAANQAECgEIAQAAAA==.',
Mc='Mcribz:BAACNQAFFH8IAAIcAAUKnBlQBgC3AQAcAAUKnBlQBgC3AQA1AAQKfycAAhwACQqpJVEQADMDABwACQqpJVEQADMDAAAA.',
Me='Meap:BAAANQAECgQIBQAAAA==.Mecatank:BAAANQAECgEJAQAAAA==.Medra:BAAANQABCgQIBAAAAA==.Meelonusk:BAAANQAECggIEwAAAA==.',
Mi='Michaelcoyle:BAABNQAECn8qAAISAAkKZSD0FABIAwASAAkKZSD0FABIAwAAAA==.Milo:BAAANQAECgYICwAAAA==.Mitra:BAABNQAECn8ZAAIMAAcKoxivCAALAgAMAAcKoxivCAALAgAAAA==.',
Mo='Moesko:BAAANQAECgYIEQAAAA==.Mogianna:BAAANQABCgMIAwABNQADCgcICAAJAAAAAA==.Monktup:BAAANQAECgEIAQAAAA==.Monkzo:BAAANQADCgcIBwABNQAFFAIIAgAJAAAAAA==.Monnehbaggs:BAACNQAFFH8FAAIdAAUKpRvHDgCfAQAdAAUKpRvHDgCfAQA1AAQKfzcAAx0ACQoZJngAAPUDAB0ACQoZJngAAPUDAB4AAQqWIlcfAGMAAAAA.',
Mu='Munchies:BAAANQABCgIIAgAAAA==.Murdersamich:BAAANQADCggJCQAAAA==.',
My='Myraghor:BAABNQAECn8sAAIVAAkKcyAaBQBLAwAVAAkKcyAaBQBLAwAAAA==.',
Na='Nalmec:BAAANQADCgQIBAAAAA==.Naysayre:BAAANQABCgEIAQAAAA==.',
Ne='Nebody:BAAANQADCggIHgAAAA==.Necriss:BAABNQAECn8fAAINAAgK1w8jrADCAQANAAgK1w8jrADCAQAAAA==.',
Ni='Nike:BAAANQAECgcICwAAAA==.',
No='Norni:BAAANQAECgYIDQAAAA==.Nowarning:BAAANQADCgQIBQAAAA==.',
Og='Oghom:BAAANQADCggIEAAAAA==.',
Op='Opeep:BAAANQAECgUICwAAAA==.',
Or='Oruum:BAAANQADCgYICAAAAA==.',
Pa='Papachance:BAAANQADCggIKAAAAA==.Papafrank:BAAANQADCggIJgAAAA==.Papapump:BAABNQAECn8aAAIfAAgKGBypDwBsAgAfAAgKGBypDwBsAgAAAA==.Parlare:BAAANQAECgYIEgABNQAECgkJKgAgAMocAA==.',
Pe='Perrinaya:BAAANQADCgQIBwAAAA==.',
Ph='Phoenixwing:BAAANQADCgYIDAAAAA==.',
Pi='Piedrita:BAAANQADCgMIAwAAAA==.Pinga:BAABNQAECn8mAAMeAAYKayL9CADMAQAdAAYKYiFgSwBAAgAeAAYKMhr9CADMAQABNQAECgkJKgAgAMocAA==.',
Po='Poshifru:BAAANQAECgUIDgABNQABCgIIAgAJAAAAAA==.',
Pr='Preposition:BAABNQAECn8cAAISAAgKcRUoVwBqAgASAAgKcRUoVwBqAgAAAA==.',
Pu='Pussduty:BAABNQAECn8pAAISAAkKCiMHEwBSAwASAAkKCiMHEwBSAwAAAA==.',
Ra='Raaziel:BAAANQAECgYIBgAAAA==.Rafìki:BAAANQADCgcIBwAAAA==.Raggnar:BAABNQAECn8eAAIOAAkKgSHxGgAmAwAOAAkKgSHxGgAmAwAAAA==.Ragingwaters:BAAANQADCgYIBgAAAA==.Ranvir:BAAANQADCggIEgAAAA==.Raun:BAABNQAECn8oAAMNAAgKvR83UAChAgANAAgKvR83UAChAgAYAAYKIAbJtgAMAQAAAA==.',
Re='Reactionhank:BAAANQAECgUJBQAAAA==.Relaire:BAAANQAECgcIEgAAAA==.',
Ri='Riku:BAABNQAECn8dAAIhAAgKFh1ZCgCSAgAhAAgKFh1ZCgCSAgAAAA==.',
Ro='Roots:BAABNQAECn8gAAIIAAkKdSAwDQBfAwAIAAkKdSAwDQBfAwAAAA==.',
Ru='Rumplfourskn:BAAANQADCgIIAgAAAA==.',
Ry='Ryveri:BAABNQAECn8cAAIiAAkKZxuXWQB8AgAiAAkKZxuXWQB8AgAAAA==.',
Sa='Sablehide:BAABNQAECn8dAAQjAAgK3hBGGQCyAQAjAAgK8gxGGQCyAQAkAAUKiRSCEQAZAQAgAAIKvA9PRQBxAAAAAA==.Salute:BAAANQAECgUIBgAAAA==.Sanaty:BAAANQAECgUIDgAAAA==.Saryn:BAAANQAECgMIAwAAAA==.Sathanus:BAAANQAECgEIAQAAAA==.Sazuni:BAAANQAECgUICwAAAA==.',
Sc='Scuffedname:BAAANQABCgQIBAAAAA==.',
Se='Secrett:BAAANQADCgcIDgAAAA==.',
Sf='Sfora:BAAANQADCgcICAAAAA==.',
Sh='Shelby:BAAANQADCgYICQAAAA==.Shiggs:BAAANQADCggIJwAAAA==.Shortsighted:BAAANQAECggICAABNQAFFAUICAAcAJwZAA==.Shoçknezz:BAAANQADCgYICwAAAA==.',
Si='Silentsnake:BAEANQAECggIBwABNQAECgkJIAAIAPkSAA==.Silverwolf:BAABNQAECn8pAAIfAAgKWhUKEgBGAgAfAAgKWhUKEgBGAgAAAA==.Simplyunlock:BAABNQAECn8kAAMBAAkKiRNVeQDzAQABAAgKnRJVeQDzAQACAAQKbRGnNwDhAAAAAA==.Simplyvoided:BAAANQAECgEIAQAAAA==.Siphin:BAAANQAECggIAQAAAA==.Sizzlechop:BAABNQAECn8cAAIUAAcKxBL9WQCIAQAUAAcKxBL9WQCIAQAAAA==.Sizzlerocks:BAAANQADCgYIBgAAAA==.',
Sk='Skizzak:BAAANQAECggICwABNQAFFAUICAAcAJwZAA==.',
Sl='Slee:BAAANQAECgMIBwAAAA==.Slimedog:BAAANQAECgEJAQAAAA==.',
Sm='Smelvin:BAAANQAECgYIEQABNQAECggIEwAJAAAAAA==.',
Sn='Snailslolol:BAABNQAECn8aAAIYAAgKkhNkXwD3AQAYAAgKkhNkXwD3AQAAAA==.Snakes:BAEANQAECggIEQABNQAECgkJIAAIAPkSAA==.Sneaksatoke:BAAANQADCgMIAwAAAA==.',
So='Solåra:BAAANQADCgUIBQABNQAECggIHAAFAIEQAA==.Songs:BAAANQADCgQIBQABNQADCgcIEQAJAAAAAA==.',
Sq='Squirtin:BAAANQAECgYICgAAAA==.',
St='Stalath:BAAANQAECgEIAQAAAA==.Stormquota:BAAANQAECgYIBgABNQAECgkJGwAOACMhAA==.Stormwing:BAAANQAECgEIAQAAAA==.',
Su='Sumarr:BAAANQAECggIBwAAAA==.',
Sv='Svenn:BAAANQADCggIDwAAAA==.',
Sw='Swiftstrike:BAAANQADCgYIBgAAAA==.',
Ta='Taboo:BAAANQAECgYIDAAAAA==.Talron:BAAANQADCgcIEQAAAA==.Tatertots:BAABNQAECn8eAAIZAAgKchrAKABOAgAZAAgKchrAKABOAgAAAA==.',
Te='Tea:BAABNQAECn8kAAISAAkK8B9FHQAhAwASAAkK8B9FHQAhAwAAAA==.Teilsande:BAAANQADCgYJBgAAAA==.Teleportato:BAAANQAECgQIBAAAAA==.Templyn:BAABNQAECn8gAAMUAAkKjA3LTwCzAQAUAAkKjA3LTwCzAQAcAAEKAACR4gAvAAAAAA==.',
Th='Thannos:BAAANQADCggIEwAAAA==.Theus:BAAANQADCgUICQAAAA==.Thyrus:BAABNQAECn8qAAIgAAkKyhzJDADYAgAgAAkKyhzJDADYAgAAAA==.',
Ti='Tirna:BAABNQAECn8lAAIKAAgKqxTUugANAgAKAAgKqxTUugANAgAAAA==.',
To='Tomsellock:BAAANQADCggIFQAAAA==.',
Tu='Tullen:BAEBNQAECn8jAAIdAAgK/Q/TaQDdAQAdAAgK/Q/TaQDdAQAAAA==.Turanos:BAAANQAECgIIAgAAAA==.Tutio:BAAANQADCgYIBgAAAA==.',
Ty='Tyindaris:BAAANQADCgUJCAAAAA==.',
['Té']='Témplýn:BAAANQAECgEIAQABNQAECgkJIAAUAIwNAA==.',
['Të']='Tëmplýn:BAAANQADCgMIAwABNQAECgkJIAAUAIwNAA==.Tëmplÿn:BAAANQAECgYIBgABNQAECgkJIAAUAIwNAA==.',
Ul='Ullr:BAAANQADCggIEwAAAA==.Ultrachad:BAACNQAFFH8TAAIUAAYKPiC2BAAqAgAUAAYKPiC2BAAqAgA1AAQKfyoAAhQACQqNHp4ZAN8CABQACQqNHp4ZAN8CAAAA.',
Un='Unggoy:BAACNQAFFH8UAAMTAAcKgR+xBwDMAQATAAYK7R2xBwDMAQASAAEK0CVjLQBlAAA1AAQKfyQAAxMACQqYJIkOAPgCABMACQorJIkOAPgCABIAAQrrJv44AWkAAAAA.Unholysin:BAAANQADCggIIQAAAA==.',
Uw='Uwuther:BAAANQAECgIIBAAAAA==.',
Va='Vaelthirion:BAAANQADCggIGQAAAA==.Vahidamus:BAAANQAECgQIBgAAAA==.Valmirax:BAAANQADCgcICgAAAA==.Valton:BAAANQAECgIIAgAAAA==.Vaurix:BAAANQAECgQICAAAAA==.',
Ve='Vezarion:BAAANQADCgUIBgAAAA==.',
Wa='Wafuzz:BAAANQAECgQIBAAAAA==.Waters:BAAANQADCgMIAwAAAA==.',
We='Wesellpallys:BAAANQADCgUIBQABNQAECggIEwAJAAAAAA==.',
Wi='Windhorn:BAAANQADCgUIEQAAAA==.Winds:BAAANQADCgcIEQAAAA==.Windtalker:BAAANQADCgQIBAABNQADCgUIBQAJAAAAAA==.',
Wo='Wolfen:BAAANQADCggICAAAAA==.Wolfquota:BAABNQAECn8bAAIOAAkKIyE3GAA1AwAOAAkKIyE3GAA1AwAAAA==.Wombaa:BAABNQAECn8jAAMcAAkKJyXdCAB4AwAcAAkKJyXdCAB4AwAZAAEKGx+VnQBOAAAAAA==.',
Wr='Wrathdk:BAAANQAECgcIDgABNQAFFAIIAwAJAAAAAA==.Wrathm:BAAANQAFFAIIAwAAAA==.Wrathmo:BAABNQAECn8WAAMGAAgKOhDcLwCUAQAGAAcKExLcLwCUAQAHAAQKawcqJACtAAABNQAFFAIIAwAJAAAAAA==.Wrenkyian:BAAANQADCgUIBQAAAA==.',
Ya='Yani:BAAANQADCgYICgAAAA==.',
Ye='Yeah:BAAANQABCgUIBAAAAA==.',
Yo='Yougotsniped:BAAANQADCgUIBQAAAA==.',
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
