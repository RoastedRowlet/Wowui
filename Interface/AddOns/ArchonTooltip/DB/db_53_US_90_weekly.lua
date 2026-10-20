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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Hunter-BeastMastery','Mage-Arcane','DemonHunter-Havoc','Monk-Mistweaver','Shaman-Elemental','Rogue-Outlaw','Paladin-Retribution','Shaman-Restoration','Unknown-Unknown','Rogue-Assassination','Hunter-Marksmanship','DeathKnight-Blood','Druid-Guardian','Warrior-Fury','Paladin-Holy','DeathKnight-Frost','Mage-Frost','Priest-Shadow','Warrior-Arms','Warrior-Protection','Paladin-Protection','DeathKnight-Unholy','Priest-Holy','Priest-Discipline','Shaman-Enhancement','Druid-Restoration','Evoker-Preservation','Druid-Feral','Evoker-Devastation','Evoker-Augmentation',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abacus:BAAANQAECgQIBgAAAA==.',
Ad='Adam:BAACNQAFFH8ZAAQBAAgKphh5BwDxAQABAAYKnhV5BwDxAQACAAIKdB3xCwCgAAADAAEKNRmZAgBjAAA1AAQKfyoABAIACgpjJI0IAHQCAAEACQoJJGAxAMICAAIACApSGY0IAHQCAAMAAQoAAP8uADgAAAAA.',
Ak='Akurama:BAAANQAECgYICQAAAA==.',
Al='Allfrowns:BAAANQAECgcJDgAAAA==.Allsmiles:BAAANQAECggIDwAAAA==.Allura:BAAANQAECgQIBQAAAA==.Alunaris:BAAANQAECgEJAgAAAA==.',
Am='Amoon:BAABNQAECn8pAAMEAAgKHhXsBwCQAQAEAAgKHhXsBwCQAQAFAAIKZxA7KgBiAAAAAA==.',
An='Ancalagon:BAAANQADCgQIBAAAAA==.',
Ar='Archymedes:BAAANQAECgIIAQAAAA==.Arckady:BAAANQAECgUIBwAAAA==.Array:BAAANQADCggICAAAAA==.Artharius:BAABNQAECn8gAAMGAAoKwSE9CgBtAQAGAAoKwSE9CgBtAQAHAAUKNxQgHAAkAQAAAA==.',
As='Asbestos:BAAANQAECgMIAwAAAA==.',
Au='Auburnbeard:BAAANQAECgEJAQAAAA==.',
Av='Averle:BAAANQAECgMIAgAAAA==.',
Ba='Badchoices:BAAANQAECgEIAQAAAA==.Badkittie:BAAANQADCgUICgAAAA==.Baretta:BAAANQAECgYICwAAAA==.',
Be='Beefsnake:BAEBNQAECn8kAAIIAAoKwRMnLAB5AgAIAAoKwRMnLAB5AgAAAA==.Beefytips:BAAANQADCgIJAgAAAA==.Bettyßaraxus:BAAANQAECgYIDAABNQAECgoKHwAJAFkWAA==.Bettyßarrage:BAAANQADCgUIBQABNQAECgoKHwAJAFkWAA==.Bettyßlight:BAAANQADCgUICAABNQAECgoKHwAJAFkWAA==.',
Bi='Bigunsforu:BAAANQAECgYIBwAAAA==.',
Bo='Bogs:BAABNQAECn8fAAIKAAoK1BtFKwBuAQAKAAoK1BtFKwBuAQAAAA==.Bolomorte:BAAANQADCgYJBgAAAA==.Boragish:BAAANQAECgcIDgAAAA==.Boulderfist:BAAANQADCggIFAAAAA==.',
Br='Brolic:BAABNQAECn8eAAILAAkKORuXBAAeAgALAAkKORuXBAAeAgAAAA==.',
Bu='Bubbleman:BAAANQADCgQIBAAAAA==.Bubblestomps:BAAANQADCgMIAwAAAA==.Burial:BAAANQAECgUIBwAAAA==.Burntchicken:BAAANQABCgMIAwAAAA==.',
Bw='Bwonsamdy:BAAANQAECgIIAgAAAA==.',
['Bä']='Bämboo:BAABNQAECn8dAAIMAAgKUhomEQBsAgAMAAgKUhomEQBsAgAAAA==.',
Ca='Cail:BAEBNQAECn8aAAINAAcKBAwnpQBKAQANAAcKBAwnpQBKAQAAAA==.Calamìty:BAAANQAECgMIAwAAAA==.Calisa:BAABNQAECn8oAAIOAAgKOxjQAADEAQAOAAgKOxjQAADEAQAAAA==.Cantstandya:BAABNQAECn8eAAIPAAoKNB21VgCSAgAPAAoKNB21VgCSAgAAAA==.Carnifex:BAABNQAECn8VAAMNAAcK+BZRigCKAQANAAYK8xhRigCKAQAQAAcKLA7FjgBkAQABNQAECggIDwARAAAAAA==.',
Ce='Ceryph:BAAANQAECgEIAQAAAA==.',
Ch='Charis:BAAANQADCgEIAQAAAA==.Chewbub:BAAANQADCgIIAgAAAA==.Chigutotems:BAEBNQAECn8sAAIQAAoKgR2SFQAiAwAQAAoKgR2SFQAiAwAAAA==.Chow:BAAANQABCgUIBQABNQAECgYIBgARAAAAAA==.Chozen:BAACNQAFFH8IAAISAAMK5yGnAwDJAAASAAMK5yGnAwDJAAA1AAQKfy0AAhIACgoWIzoLADADABIACgoWIzoLADADAAAA.Chroniccloud:BAAANQAECgEIAQAAAA==.',
Co='Cornelius:BAAANQAECgUICgAAAA==.Corporicky:BAAANQAECgEIAQAAAA==.Coulee:BAAANQADCgQICgABNQAECgoKIQALAB0aAA==.',
Cr='Cronicpain:BAAANQAECgUIBgAAAA==.',
Cy='Cymbi:BAAANQABCgQIAwAAAA==.',
Da='Daks:BAAANQADCgQIBAAAAA==.Darklucrezia:BAABNQAECn8jAAMJAAoKWBZEaQBBAgAJAAkKORhEaQBBAgATAAEKLAncPgA0AAAAAA==.Darkpyro:BAAANQADCggIEAAAAA==.',
De='Deetsy:BAAANQADCgYICAAAAA==.Dextrose:BAAANQAECgcICwABNQAECgoKHAABAJMbAA==.',
Di='Dicey:BAAANQAECggIDwAAAA==.',
Dk='Dkbig:BAAANQAECgUICgAAAA==.',
Dr='Dracarius:BAAANQAECgYIBwAAAA==.Drtypinkcake:BAAANQAECgYICgAAAA==.Druidcant:BAAANQADCgYIBgAAAA==.Drworldwide:BAAANQAECggICQAAAA==.Dryad:BAAANQAECgUIBwAAAA==.',
Du='Durkk:BAABNQAECn8sAAIUAAgKxx+9BAALAgAUAAgKxx+9BAALAgAAAA==.Durza:BAAANQADCggICAAAAA==.',
['Dä']='Dännydevito:BAAANQADCgMIBAAAAA==.',
En='Enss:BAAANQADCgUJBQAAAA==.',
Es='Estara:BAABNQAECn8qAAIVAAgKlQ6wCwBCAQAVAAgKlQ6wCwBCAQAAAA==.',
Et='Etali:BAABNQAECn8hAAIWAAgKlBbDBABjAQAWAAgKlBbDBABjAQAAAA==.Etherious:BAAANQAECgQIBAABNQAECgcIDQARAAAAAA==.',
Fa='Fanis:BAABNQAECn8fAAITAAgKaguVEgDyAAATAAgKaguVEgDyAAAAAA==.',
Fi='Fibo:BAAANQADCgQIBAAAAA==.',
Fl='Flashis:BAABNQAECn8XAAQGAAoKFQu0LwCaAQAGAAoKAQu0LwCaAQAMAAUKWQM8OQClAAAHAAMK+gYGDQCHAAAAAA==.Floor:BAAANQABCgIIAgAAAA==.Florago:BAAANQAECgUIBwAAAA==.',
Fo='Force:BAAANQAECgEIAgAAAA==.',
Fr='Frakir:BAABNQAECn8sAAMQAAgKohp0EQDLAQAQAAgKohp0EQDLAQANAAEKAAApUwEkAAAAAA==.',
Fu='Furrypaw:BAABNQAECn8lAAMMAAgKER82AgBUAgAMAAgKER82AgBUAgAGAAEKAADocgAnAAAAAA==.Fuzzyy:BAAANQADCgUIBQAAAA==.',
Fw='Fwapp:BAACNQAFFH8WAAIXAAcKpxUBBwD6AQAXAAcKpxUBBwD6AQA1AAQKfy0AAhcACgq0JMoEAKoDABcACgq0JMoEAKoDAAAA.',
Ga='Galvanize:BAAANQAECgUIDwAAAA==.',
Gi='Gijaick:BAABNQAECn8aAAMBAAoKMA32LQA+AQABAAoKhAv2LQA+AQACAAQKeguSNQDsAAAAAA==.',
Gl='Glizzo:BAABNQAECn85AAIKAAoKPxPeCgAeAgAKAAoKPxPeCgAeAgAAAA==.Gloomrider:BAAANQADCgUIBQAAAA==.',
Go='Gold:BAAANQADCgUIBQAAAA==.Goldhawk:BAAANQADCgEIAQAAAA==.Gotwiped:BAABNQAECn8jAAIYAAgK7R4ZGwCyAgAYAAgK7R4ZGwCyAgAAAA==.',
Gu='Gunnery:BAAANQAECggIDgAAAA==.',
Ha='Hantaz:BAAANQAECgYIBgAAAA==.Hatter:BAABNQAECn8rAAMEAAoKFBs9CQB8AQAFAAcKXBfrDwC1AQAEAAoKeRo9CQB8AQAAAA==.',
He='Hellraiser:BAABNQAECn8UAAIUAAcKwBbnWQCLAQAUAAcKwBbnWQCLAQAAAA==.',
Hi='Hidduka:BAABNQAECn8aAAIXAAgKbxyaPAByAgAXAAgKbxyaPAByAgAAAA==.Hills:BAAANQAECgEIAQAAAA==.',
Ho='Holyascended:BAAANQADCggIFgAAAA==.Holydarkness:BAAANQADCgYIBgAAAA==.Holykilla:BAAANQADCgUIBQAAAA==.Holykiller:BAAANQADCgEIAQAAAA==.Hoplite:BAAANQAECgUIBQABNQAECgcICwARAAAAAA==.Hothots:BAAANQABCgYIBgABNQAECgYIBgARAAAAAA==.Howlly:BAABNQAECn8fAAIZAAcKcyL0BADPAgAZAAcKcyL0BADPAgAAAA==.',
Hr='Hraun:BAAANQADCgIIAQAAAA==.',
Hu='Hulner:BAAANQAECggIAgAAAA==.',
Ik='Ikeanola:BAABNQAECn8eAAIPAAkKlgVF7QBBAQAPAAkKlgVF7QBBAQAAAA==.',
In='Indras:BAAANQADCgcIFAAAAA==.Ines:BAABNQAECn8lAAIYAAkKih+EEgD5AgAYAAkKih+EEgD5AgAAAA==.Inhume:BAAANQADCggJCQAAAA==.',
Is='Ismarus:BAAANQAECgQIBQAAAA==.',
Ja='Jaarus:BAAANQAECgUIDAAAAA==.Jajal:BAABNQAECn8YAAIaAAkKCBH1JAAIAgAaAAkKCBH1JAAIAgABNQAECgoKFwAGABULAA==.Jankadish:BAABNQAECn8VAAMbAAgKeAqiSgAKAQAbAAYKhwmiSgAKAQAcAAYKaAn3JwD/AAAAAA==.Jaspirian:BAAANQADCgYIBgAAAA==.',
Je='Jehm:BAABNQAECn8fAAIUAAgK+A7PUwClAQAUAAgK+A7PUwClAQAAAA==.Jerome:BAAANQADCgMIAwAAAA==.',
Ju='Juiceboxer:BAAANQAECgQICAABNQAECgUICwARAAAAAA==.Juicy:BAAANQADCgYIBgAAAA==.Justicehand:BAAANQAECgIIAgAAAA==.',
Ka='Kaestia:BAAANQAECgEIAQABNQAECgoKLgAZALgdAA==.Kagor:BAAANQADCgMIAwABNQAECgUIDAARAAAAAA==.Kalia:BAABNQAECn8uAAMZAAoKuB3OBADWAgAZAAgKaiHOBADWAgAKAAkKMBjXOABMAQAAAA==.Kalipto:BAAANQADCgcICAAAAA==.Katatonik:BAAANQAECgUIBQABNQAECgUIDAARAAAAAA==.Katharina:BAAANQAECgcIEwAAAA==.Katoumae:BAAANQAFFAEIAgAAAA==.Katoumey:BAAANQAECgYIEAABNQAFFAEIAgARAAAAAA==.',
Kh='Khumfuu:BAAANQAECgQIBwAAAA==.',
Ki='Kinan:BAABNQAECn8qAAMJAAgKCCXdBQBwAgATAAgKcCKyDAARAwAJAAgKhSHdBQBwAgAAAA==.',
Ko='Konan:BAAANQADCgMIAwAAAA==.Korlo:BAAANQAECgUIBwAAAA==.',
Ku='Kuala:BAAANQADCgIIAgAAAA==.',
Ky='Kythin:BAAANQAECgMICAABNQAECgoKLgAZALgdAA==.',
La='Lacutis:BAAANQADCggICAAAAA==.',
Li='Lichmcconnel:BAABNQAECn8kAAMDAAgK8xu0BQBgAgADAAgK8xu0BQBgAgACAAEKWAdjewAyAAAAAA==.Lillica:BAAANQADCgQIBAAAAA==.Lilmeesh:BAAANQADCgQIBAAAAA==.Lisabeth:BAAANQAECgEIAQABNQAFFAgIFgATAEYcAA==.',
Lo='Lomponic:BAEBNQAECn8jAAIaAAgK2B80EQDoAgAaAAgK2B80EQDoAgAAAA==.Lore:BAACNQAFFH8JAAIdAAUKdRGtAgDYAAAdAAUKdRGtAgDYAAA1AAQKfyoAAh0ACgotGGgZACkCAB0ACgotGGgZACkCAAAA.',
Lu='Lunethra:BAABNQAECn8uAAIJAAoK+A2qawA8AgAJAAoK+A2qawA8AgAAAA==.Luukiss:BAAANQADCgQIBQAAAA==.Luyang:BAAANQADCgIIAgAAAA==.',
['Lü']='Lümen:BAAANQAECgIIAgAAAA==.',
Ma='Madcow:BAAANQADCgcIBwABNQAECggIHQAJAFAiAA==.Madhat:BAAANQAECgcIDQAAAA==.Magerag:BAABNQAECn8lAAIKAAkKqCHCHgBdAwAKAAkKqCHCHgBdAwAAAA==.Malyc:BAAANQAECgMIAwAAAA==.',
Mc='Mcribz:BAACNQAFFH8IAAIeAAUKnBlnBgC4AQAeAAUKnBlnBgC4AQA1AAQKfy0AAh4ACgqYJcsEAPEBAB4ACgqYJcsEAPEBAAAA.',
Me='Meap:BAAANQAECgQIBQAAAA==.Mecatank:BAAANQAECgEJAQAAAA==.Medra:BAAANQABCgQIBAAAAA==.Meelonusk:BAABNQAECn8XAAMCAAkK8Q4vMgD9AAABAAcKMgzYrwBxAQACAAQKpBAvMgD9AAAAAA==.',
Mi='Michaelcoyle:BAABNQAECn8wAAIJAAoKWR+OFQBGAwAJAAoKWR+OFQBGAwAAAA==.Milo:BAAANQAECgYICwAAAA==.Mitra:BAABNQAECn8hAAIOAAgKShimAADhAQAOAAgKShimAADhAQAAAA==.',
Mo='Moesko:BAAANQAECgYIEwAAAA==.Mogianna:BAAANQABCgMIAwABNQADCgcICAARAAAAAA==.Monktup:BAAANQAECgEIAQAAAA==.Monkzo:BAAANQADCgcIBwABNQAECgoKJQAaAFYRAA==.Monnehbaggs:BAACNQAFFH8FAAIfAAUKpRs7DwCfAQAfAAUKpRs7DwCfAQA1AAQKf0EAAx8ACgq2JH0AAPUDAB8ACgq2JH0AAPUDACAABQqeGkYCADsBAAAA.',
Mu='Munchies:BAAANQABCgIIAgAAAA==.Murdersamich:BAAANQADCggJCQAAAA==.',
My='Myraghor:BAABNQAECn8xAAIVAAoK0R8oBQBMAwAVAAoK0R8oBQBMAwAAAA==.',
Na='Nalmec:BAAANQADCgQIBAAAAA==.Naysayre:BAAANQABCgEIAQAAAA==.',
Ne='Nebody:BAAANQADCggIIAAAAA==.Necriss:BAABNQAECn8mAAIPAAgK1w+EOgBTAQAPAAgK1w+EOgBTAQAAAA==.',
Ni='Nike:BAAANQAECgcICwAAAA==.',
No='Norni:BAAANQAECgYIDwAAAA==.Nowarning:BAAANQAECgIIAgAAAA==.',
Og='Oghom:BAAANQADCggIGQAAAA==.',
Op='Opeep:BAAANQAECgYICwAAAA==.',
Or='Oruum:BAAANQADCgYICAAAAA==.',
Pa='Papapump:BAABNQAECn8eAAIhAAoKSBnUDwBrAgAhAAoKSBnUDwBrAgAAAA==.Parlare:BAABNQAECn8XAAIiAAkKOhrvIAAiAgAiAAkKOhrvIAAiAgABNQAECgoKLQAjAIkbAA==.',
Pe='Perrinaya:BAAANQADCgQIBwAAAA==.',
Ph='Phoenixwing:BAAANQADCgYIDAAAAA==.',
Pi='Piedrita:BAAANQADCgMIAwAAAA==.Pinga:BAABNQAECn8tAAMfAAgKRB9RCgA/AgAfAAgKfh5RCgA/AgAgAAYKMhoNCQDMAQABNQAECgoKLQAjAIkbAA==.',
Po='Poshifru:BAAANQAECgUIDwABNQABCgIIAgARAAAAAA==.',
Pr='Preposition:BAABNQAECn8hAAIJAAkKABShWABpAgAJAAkKABShWABpAgAAAA==.',
Pu='Pussduty:BAABNQAECn8tAAIJAAoKXiFwEwBRAwAJAAoKXiFwEwBRAwAAAA==.',
Ra='Raaziel:BAAANQAECgcICgAAAA==.Racknar:BAAANQAECgIIAgAAAA==.Rafìki:BAAANQAECgQIBAAAAA==.Raggnar:BAABNQAECn8eAAINAAkKgSFOGwAmAwANAAkKgSFOGwAmAwAAAA==.Ragingwaters:BAAANQADCgYIBgAAAA==.Ranvir:BAAANQADCggIGgAAAA==.Raun:BAABNQAECn8vAAMPAAgKiiCqDwD+AQAPAAgKiiCqDwD+AQAXAAYKIAabuAAMAQAAAA==.',
Re='Reactionhank:BAAANQAECgUJBQAAAA==.Relaire:BAABNQAECn8cAAIJAAgKSwjmVgABAQAJAAgKSwjmVgABAQAAAA==.',
Ri='Riku:BAABNQAECn8kAAIkAAgKVx3GAgC+AQAkAAgKVx3GAgC+AQAAAA==.',
Ro='Roots:BAABNQAECn8iAAIIAAoKrx9jDQBfAwAIAAoKrx9jDQBfAwAAAA==.',
Ru='Rumplfourskn:BAAANQADCgIIAgAAAA==.',
Ry='Ryveri:BAABNQAECn8gAAIbAAoKMhqgWgB8AgAbAAoKMhqgWgB8AgAAAA==.',
Sa='Sablehide:BAABNQAECn8jAAQlAAgKSRFuGQCyAQAlAAgKbA1uGQCyAQAmAAYKXBKyEQAaAQAjAAIKvA8cRgBxAAAAAA==.Salute:BAAANQAECgUIBgAAAA==.Sanaty:BAAANQAECgUIDgAAAA==.Saryn:BAAANQAECgMIAwAAAA==.Sathanus:BAAANQAECgEIAQAAAA==.Sazuna:BAAANQAECgUIBQAAAA==.Sazuni:BAAANQAECgUICwAAAA==.',
Sc='Scuffedname:BAAANQABCgQIBAAAAA==.',
Se='Secrett:BAAANQADCgcIDgAAAA==.',
Sf='Sfora:BAAANQADCgcICAAAAA==.',
Sh='Shadowreaper:BAAANQADCgUIBAAAAA==.Shelby:BAAANQADCgYICQAAAA==.Shiggs:BAAANQADCggIKgAAAA==.Shortsighted:BAAANQAECggICAABNQAFFAUICAAeAJwZAA==.Shoçknezz:BAAANQADCgYICwAAAA==.',
Si='Silentsnake:BAEANQAECggIBwABNQAECgoKJAAIAMETAA==.Silverwolf:BAABNQAECn8yAAIhAAoKPBPtAQA8AgAhAAoKPBPtAQA8AgAAAA==.Simplyunlock:BAABNQAECn8rAAMBAAoKYhEuewDzAQABAAkKSRAuewDzAQACAAQKbRHgNwDhAAAAAA==.Simplyvoided:BAAANQAECgIIAQAAAA==.Siphin:BAAANQAECggIAQAAAA==.Sizzlechop:BAABNQAECn8iAAIUAAgKwxBsIgDvAAAUAAgKwxBsIgDvAAAAAA==.Sizzlerocks:BAAANQADCgYIBgAAAA==.',
Sk='Skizzak:BAAANQAECggIDAABNQAFFAUICAAeAJwZAA==.',
Sl='Slee:BAAANQAECgMIBwAAAA==.Slimedog:BAAANQAECgEJAQAAAA==.',
Sm='Smelvin:BAAANQAECgYIEQABNQAECgkJFwACAPEOAA==.',
Sn='Snailslolol:BAABNQAECn8iAAIXAAoKYxZQCQAvAgAXAAoKYxZQCQAvAgAAAA==.Snakes:BAEANQAECggIEQABNQAECgoKJAAIAMETAA==.Sneaksatoke:BAAANQADCgMIAwAAAA==.',
So='Solåra:BAAANQADCgUIBQABNQAECggIHAAFAIEQAA==.Songs:BAAANQADCgQIBQABNQADCgcIEQARAAAAAA==.',
Sq='Squirtin:BAAANQAECgUIDgAAAA==.',
St='Stalath:BAAANQAECgIIAwAAAA==.Stormquota:BAAANQAECgYICQABNQAECgoKHQANAEogAA==.Stormwing:BAAANQAECgEIAQAAAA==.',
Su='Sumarr:BAAANQAECgcIBwAAAA==.',
Sv='Svenn:BAAANQADCggIDwAAAA==.',
Sw='Swiftstrike:BAAANQADCgYIBgAAAA==.',
Ta='Taboo:BAAANQAECgYIDAAAAA==.Talron:BAAANQADCgcIEQAAAA==.Tatertots:BAABNQAECn8lAAIYAAgKlRo8CQDFAQAYAAgKlRo8CQDFAQAAAA==.',
Te='Tea:BAABNQAECn8pAAIJAAoKTx/dHQAgAwAJAAoKTx/dHQAgAwAAAA==.Teilsande:BAAANQADCgYJBgAAAA==.Teleportato:BAAANQAECgQIBAAAAA==.Templyn:BAABNQAECn8kAAMUAAoKXAyAUACyAQAUAAoKXAyAUACyAQAeAAEKAAAl5QAvAAAAAA==.',
Th='Thannos:BAAANQADCggIEwAAAA==.Theus:BAAANQADCgUICQAAAA==.Thyrus:BAABNQAECn8tAAIjAAoKiRvkDADXAgAjAAoKiRvkDADXAgAAAA==.',
Ti='Tirna:BAABNQAECn8sAAIKAAgKqRUtGACvAQAKAAgKqRUtGACvAQAAAA==.',
To='Tomsellock:BAAANQADCggIFQAAAA==.Tonytemplar:BAAANQABCgIIBQAAAA==.',
Tu='Tullen:BAEBNQAECn8qAAIfAAgKJhCFKABcAQAfAAgKJhCFKABcAQAAAA==.Turanos:BAAANQAECgUIBwAAAA==.Tutio:BAAANQADCgYIBgAAAA==.',
Ty='Tyindaris:BAAANQADCgUJCAAAAA==.',
['Té']='Témplýn:BAAANQAECgIIAQABNQAECgoKJAAUAFwMAA==.',
['Të']='Tëmplÿn:BAAANQAECgYIBgABNQAECgoKJAAUAFwMAA==.',
Ul='Ullr:BAAANQADCggIIAAAAA==.Ultrachad:BAACNQAFFH8YAAIUAAYKoyD9BAAqAgAUAAYKoyD9BAAqAgA1AAQKfy0AAhQACgp5HgAaAN4CABQACgp5HgAaAN4CAAAA.',
Un='Unggoy:BAACNQAFFH8WAAMTAAgKRhzmBwDMAQATAAcKXhrmBwDMAQAJAAEK0CVLLgBlAAA1AAQKfyUAAxMACgpnJMQOAPcCABMACgoIJMQOAPcCAAkAAQrrJjk9AWkAAAAA.Unholysin:BAAANQADCggIIwAAAA==.',
Ur='Urianna:BAAANQAECgYIBAAAAA==.',
Uw='Uwuther:BAAANQAECgQICAAAAA==.',
Va='Vahidamus:BAAANQAECgUIBwAAAA==.Valmirax:BAAANQADCgcICgAAAA==.Valton:BAAANQAECgIIAgAAAA==.Vaurix:BAAANQAECgYIDAAAAA==.',
Ve='Vezarion:BAAANQADCgUIBgAAAA==.',
Wa='Wafuzz:BAAANQAECgQIBAAAAA==.Waters:BAAANQADCgMIAwAAAA==.',
We='Wesellpallys:BAAANQADCgUIBQABNQAECgkJFwACAPEOAA==.',
Wh='Whambamslam:BAAANQADCggICAAAAA==.',
Wi='Windhorn:BAAANQAECgEIAQAAAA==.Winds:BAAANQADCgcIEQAAAA==.Windtalker:BAAANQADCgQIBAABNQAECgUIBQARAAAAAA==.',
Wo='Wolfen:BAAANQADCggICAAAAA==.Wolfquota:BAABNQAECn8dAAINAAoKSiClGAA1AwANAAoKSiClGAA1AwAAAA==.Wombaa:BAABNQAECn8oAAMeAAoK4yT5CAB4AwAeAAkKJyX5CAB4AwAYAAMKIh5NOAC/AAAAAA==.',
Wr='Wrathdk:BAAANQAECgcIDgABNQAFFAIIAwARAAAAAA==.Wrathm:BAAANQAFFAIIAwAAAA==.Wrathmo:BAABNQAECn8WAAMGAAgKOhBqMACUAQAGAAcKExJqMACUAQAHAAQKaweFJACtAAABNQAFFAIIAwARAAAAAA==.Wrenkyian:BAAANQADCgUIBQAAAA==.',
Ya='Yani:BAAANQADCgYICgAAAA==.',
Ye='Yeah:BAAANQABCgUIBAAAAA==.',
Yo='Yoana:BAAANQABCgIIAgAAAA==.Yougotsniped:BAAANQADCgUIBQAAAA==.',
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
