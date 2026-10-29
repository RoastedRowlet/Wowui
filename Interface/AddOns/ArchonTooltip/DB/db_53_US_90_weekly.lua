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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Mage-Arcane','DemonHunter-Havoc','Monk-Mistweaver','Shaman-Elemental','Unknown-Unknown','Rogue-Outlaw','Paladin-Retribution','Shaman-Restoration','Rogue-Assassination','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Druid-Guardian','Warrior-Fury','Paladin-Holy','DeathKnight-Frost','Priest-Holy','Mage-Frost','Priest-Shadow','Warrior-Protection','Warrior-Arms','Druid-Feral','Paladin-Protection','DeathKnight-Unholy','Druid-Restoration','Priest-Discipline','Shaman-Enhancement','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abacus:BAAANQAECggIEAAAAA==.',
Ad='Adam:BAACNQAFFH8ZAAQBAAgKphh5BwDxAQABAAYKnhV5BwDxAQACAAIKdB3xCwCgAAADAAEKNRlZBQBeAAA1AAQKfzMABAIACgrTJI0IAHQCAAEACQq3JO0RAJkCAAIACApSGY0IAHQCAAMAAQoAAP8uADgAAAAA.',
Ak='Akurama:BAAANQAECgYICgAAAA==.',
Al='Allfrowns:BAAANQAECgcJEQAAAA==.Allsmiles:BAAANQAECggIEQAAAA==.Allura:BAAANQAECgQIBQAAAA==.Alunaris:BAAANQAECgEJAgAAAA==.',
Am='Amoon:BAABNQAECn8wAAMEAAgKHhWCGABzAQAEAAgKHhWCGABzAQAFAAIKZxA7KgBiAAAAAA==.',
An='Ancalagon:BAAANQADCgQIBAAAAA==.',
Ar='Archymedes:BAAANQAECgIIAgAAAA==.Arckady:BAAANQAECgYICAAAAA==.Array:BAAANQADCggICAAAAA==.Artharius:BAABNQAECn8pAAMGAAoKSiIKCQB6AgAGAAoKSiIKCQB6AgAHAAUKNxQgHAAkAQAAAA==.',
As='Asbestos:BAAANQAECgMIAwAAAA==.',
Au='Auburnbeard:BAAANQAECgEJAQAAAA==.',
Av='Averle:BAAANQAECgMIBwAAAA==.',
Ba='Badchoices:BAAANQAECgEIAgAAAA==.Badkittie:BAAANQADCgUICgAAAA==.Bangbuscuir:BAAANQAECgEIBAAAAA==.Baretta:BAAANQAECgYIDAAAAA==.',
Be='Beefsnake:BAEBNQAECn8kAAIIAAoKwRMnLAB5AgAIAAoKwRMnLAB5AgAAAA==.Beefytips:BAAANQADCgIJAgAAAA==.Bettyßaraxus:BAABNQAECn8UAAIBAAgK3xDbcwASAQABAAgK3xDbcwASAQAAAA==.Bettyßarrage:BAAANQADCgUIBQABNQAECggIFAABAN8QAA==.Bettyßlight:BAAANQADCgUICAABNQAECggIFAABAN8QAA==.',
Bi='Bigunsforu:BAAANQAECgcICAAAAA==.',
Bo='Bogs:BAABNQAECn8pAAIJAAoKzRx7JwBXAgAJAAoKzRx7JwBXAgAAAA==.Bolomorte:BAAANQAECgEIAQAAAA==.Boragish:BAAANQAECggIDwAAAA==.Botname:BAAANQAECgEIAQABNQAECgkJFQABANEVAA==.Boulderfist:BAAANQADCggIFAAAAA==.',
Br='Brolic:BAABNQAECn8nAAIKAAoK9xojDwBZAgAKAAoK9xojDwBZAgAAAA==.',
Bu='Bubbleman:BAAANQADCgQIBAAAAA==.Bubblestomps:BAAANQADCgMIAwAAAA==.Burial:BAAANQAECgYICQAAAA==.Burntchicken:BAAANQABCgMIAwAAAA==.',
Bw='Bwonsamdy:BAAANQAECgIIAgAAAA==.',
['Bä']='Bämboo:BAABNQAECn8dAAILAAgKUhomEQBsAgALAAgKUhomEQBsAgAAAA==.',
Ca='Cail:BAEBNQAECn8fAAIMAAcKzAwnpQBKAQAMAAcKzAwnpQBKAQAAAA==.Calamìty:BAAANQAECgMIAwABNQAECggIBwANAAAAAA==.Calisa:BAABNQAECn8uAAIOAAgKOxiOAgCbAQAOAAgKOxiOAgCbAQAAAA==.Cantstandya:BAABNQAECn8oAAIPAAoKNx/GKgBUAgAPAAoKNx/GKgBUAgAAAA==.Carnifex:BAABNQAECn8VAAMMAAcK+BZRigCKAQAMAAYK8xhRigCKAQAQAAcKLA7FjgBkAQABNQAECgkJFQABANEVAA==.',
Ce='Ceryph:BAAANQAECgEIAQAAAA==.',
Ch='Charis:BAAANQADCgEIAQAAAA==.Chewbub:BAAANQADCgIIAgAAAA==.Chigutotems:BAEBNQAECn8wAAIQAAoKqh2SFQAiAwAQAAoKqh2SFQAiAwAAAA==.Chow:BAAANQAECgEIAQABNQAECgYICQANAAAAAA==.Chozen:BAACNQAFFH8IAAIRAAMK5yHuDAAqAQARAAMK5yHuDAAqAQA1AAQKfzMAAhEACgowJNwEAHsCABEACgowJNwEAHsCAAAA.Chroniccloud:BAAANQAECgEIAQAAAA==.',
Co='Cornelius:BAAANQAECgUIDgAAAA==.Corporicky:BAAANQAECgEIAQAAAA==.Coulee:BAAANQADCgUICwABNQAECgoKIgAKAB0aAA==.',
Cr='Cronicpain:BAAANQAECgUICQAAAA==.',
Cy='Cymbi:BAAANQABCgQIAwAAAA==.',
Da='Daks:BAAANQADCgQIBAAAAA==.Darklucrezia:BAABNQAECn8tAAMSAAoKexiiPADuAQASAAkKsBmiPADuAQATAAEKBBBHTwA2AAAAAA==.Darkpyro:BAAANQADCggIEAAAAA==.',
De='Deetsy:BAAANQADCgYICAAAAA==.Dextrose:BAAANQAECggIDAAAAA==.',
Di='Dicey:BAABNQAECn8VAAMBAAkK0RUCJwAZAgABAAkK0RUCJwAZAgACAAEK/A2ZdQA4AAAAAA==.',
Dk='Dkbig:BAAANQAECgYIEAAAAA==.',
Dr='Dracarius:BAAANQAECgYICgAAAA==.Drtypinkcake:BAAANQAECgYIDQAAAA==.Druidcant:BAAANQADCgYIBgAAAA==.Drworldwide:BAAANQAECggICgAAAA==.Dryad:BAAANQAECgYICAAAAA==.',
Du='Durkk:BAABNQAECn8zAAIUAAgK0h+DHgC+AgAUAAgK0h+DHgC+AgAAAA==.Durza:BAAANQADCggICAAAAA==.',
Dw='Dwayne:BAAANQAECgYIBgAAAA==.',
['Dä']='Dännydevito:BAAANQADCgMIBAAAAA==.',
En='Enss:BAAANQADCgUJBQAAAA==.',
Es='Estara:BAABNQAECn8xAAIVAAgKvA/TGwAsAQAVAAgKvA/TGwAsAQAAAA==.',
Et='Etali:BAABNQAECn8oAAIWAAgKARgfDAD8AQAWAAgKARgfDAD8AQAAAA==.Etherious:BAAANQAECgUIBgABNQAECggIEgANAAAAAA==.',
Fa='Fanis:BAABNQAECn8mAAITAAgK0wvCFwBNAQATAAgK0wvCFwBNAQAAAA==.Faynor:BAAANQADCgQIBAAAAA==.',
Fi='Fibo:BAAANQADCgQIBAAAAA==.',
Fl='Flashis:BAABNQAECn8XAAQGAAoKFQu0LwCaAQAGAAoKAQu0LwCaAQALAAUKWQM8OQClAAAHAAMK+gaUFACCAAAAAA==.Floor:BAAANQABCgIIAgAAAA==.Florago:BAAANQAECgYICAAAAA==.',
Fo='Force:BAAANQAECgEIAgAAAA==.',
Fr='Frakir:BAABNQAECn8zAAMQAAgKohpvPwBiAgAQAAgKohpvPwBiAgAMAAEKAAApUwEkAAAAAA==.',
Fu='Furrypaw:BAABNQAECn8sAAMLAAgK5R9oBwBvAgALAAgK5R9oBwBvAgAGAAEKAADocgAnAAAAAA==.Fuzzyy:BAAANQADCgUIBQABNQADCgQIBAANAAAAAA==.',
Fw='Fwapp:BAACNQAFFH8WAAIXAAcKpxUBBwD6AQAXAAcKpxUBBwD6AQA1AAQKfy4AAhcACgq0JMoEAKoDABcACgq0JMoEAKoDAAAA.',
Ga='Galvanize:BAABNQAECn8XAAMQAAYKXhIeqAAhAQAQAAYKXhIeqAAhAQAMAAUK1QrByAABAQAAAA==.',
Gi='Gijaick:BAABNQAECn8bAAMCAAoKMA2SNQDsAAABAAoKhAu6aQAsAQACAAQKeguSNQDsAAAAAA==.',
Gl='Glizzo:BAABNQAECn9CAAIJAAoKdBSuMQArAgAJAAoKdBSuMQArAgAAAA==.Gloomrider:BAAANQADCgUIBQAAAA==.',
Go='Gold:BAAANQADCgUIBQAAAA==.Goldhawk:BAAANQADCgEIAQAAAA==.Gotwiped:BAABNQAECn8rAAIYAAkKkR5bDACfAgAYAAkKkR5bDACfAgAAAA==.',
Gu='Gunnery:BAAANQAECggIDgAAAA==.',
Gy='Gyu:BAAANQADCgYIBwAAAA==.',
Ha='Hantaz:BAAANQAECggIEAAAAA==.Haoleboy:BAAANQAECgEIAQAAAA==.Hatter:BAABNQAECn8xAAMEAAoKFBv8FQCzAgAEAAoKvBr8FQCzAgAFAAcKXBfrDwC1AQAAAA==.',
He='Hellraiser:BAABNQAECn8UAAIUAAcKwBbnWQCLAQAUAAcKwBbnWQCLAQAAAA==.',
Hi='Hidduka:BAABNQAECn8aAAIXAAgKbxyaPAByAgAXAAgKbxyaPAByAgABNQAECgoKMQAZAKojAA==.Hills:BAAANQAECgEIAQAAAA==.',
Ho='Holyascended:BAAANQADCggIFgAAAA==.Holydarkness:BAAANQADCgYIBgAAAA==.Holykilla:BAAANQADCgUIBQAAAA==.Holykiller:BAAANQADCgEIAQAAAA==.Hoplite:BAAANQAECgUIBQABNQAECgcIDAANAAAAAA==.Hothots:BAAANQABCgYIBgABNQAECgYICQANAAAAAA==.Howlly:BAABNQAECn8lAAIaAAgKICH0BADPAgAaAAgKICH0BADPAgAAAA==.',
Hr='Hraun:BAAANQADCgIIAQAAAA==.',
Hu='Hulner:BAAANQAECggIAgAAAA==.',
Ik='Ikeanola:BAABNQAECn8eAAIPAAkKlgVF7QBBAQAPAAkKlgVF7QBBAQAAAA==.',
In='Inapa:BAAANQAECgYIBgAAAA==.Indras:BAAANQADCgcIFQAAAA==.Ines:BAABNQAECn8lAAIYAAkKih+EEgD5AgAYAAkKih+EEgD5AgAAAA==.Inhume:BAAANQADCggJCQAAAA==.',
Is='Ismarus:BAAANQAECgQIBQAAAA==.',
Ja='Jaarus:BAAANQAECgYIDgAAAA==.Jajal:BAABNQAECn8YAAIbAAkKCBH1JAAIAgAbAAkKCBH1JAAIAgABNQAECgoKFwAGABULAA==.Jankadish:BAABNQAECn8VAAMcAAgKeAr3JwD/AAAcAAYKaAn3JwD/AAAdAAYKhwmKjAD2AAAAAA==.Jaspirian:BAAANQADCgYIBgAAAA==.',
Je='Jehm:BAABNQAECn8hAAIUAAgKYA/PUwClAQAUAAgKYA/PUwClAQAAAA==.Jerome:BAAANQADCgMIAwAAAA==.',
Ju='Juiceboxer:BAAANQAECgQICQABNQAECgUIDAANAAAAAA==.Juicy:BAAANQADCgYIBgAAAA==.Justicehand:BAAANQAECgMIBQAAAA==.',
Ka='Kaestia:BAAANQAECgEIAQABNQAECgoKLwAaALgdAA==.Kagor:BAAANQADCgMIAwABNQAECgYIDgANAAAAAA==.Kalia:BAABNQAECn8vAAMaAAoKuB3OBADWAgAaAAkKhB3OBADWAgAJAAkKMBilvAALAgAAAA==.Kalipto:BAAANQADCgcICAAAAA==.Katatonik:BAAANQAECgUIBwABNQAECgYIDgANAAAAAA==.Katharina:BAABNQAECn8WAAMXAAgKlhN1YQD0AQAXAAgKlhN1YQD0AQAPAAEKAABAuAEsAAAAAA==.Katoume:BAABNQAECn8ZAAIeAAoKbyKUAQAbAwAeAAoKbyKUAQAbAwAAAA==.Katoumey:BAAANQAECgYIEgABNQAECgoKGQAeAG8iAA==.Kaulder:BAAANQADCgMIAwAAAA==.',
Kh='Khumfuu:BAAANQAECgUICQAAAA==.',
Ki='Kinan:BAABNQAECn8xAAMTAAgKySWyDAARAwATAAgKcCKyDAARAwASAAgKSSU5GgCJAgAAAA==.',
Ko='Konan:BAAANQADCgMIAwAAAA==.Korlo:BAAANQAECgUICQAAAA==.',
Ku='Kuala:BAAANQADCgIIAgAAAA==.',
Ky='Kythin:BAAANQAECgQICwABNQAECgoKLwAaALgdAA==.',
La='Lacutis:BAAANQAECgEIAQAAAA==.',
Le='Leonus:BAAANQADCgQIBAAAAA==.',
Li='Lichmcconnel:BAABNQAECn8tAAQDAAoKUBdjAwDvAQADAAoKUBdjAwDvAQACAAEKWAdjewAyAAABAAEKbQRo7wAuAAAAAA==.Lillica:BAAANQADCgQIBAAAAA==.Lilmeesh:BAAANQADCgQIBAAAAA==.Lisabeth:BAAANQAECgEIAwABNQAFFAgIFgATAEYcAA==.',
Lo='Lockcuir:BAAANQAECgEIAQABNQAECgEIBAANAAAAAA==.Lomponic:BAEBNQAECn8sAAIbAAoK/R00EQDoAgAbAAoK/R00EQDoAgAAAA==.Lonelyone:BAAANQAECgEIAgAAAA==.Lore:BAACNQAFFH8JAAIfAAUKdRF2BADFAAAfAAUKdRF2BADFAAA1AAQKfy4AAh8ACgrWGWgZACkCAB8ACgrWGWgZACkCAAAA.',
Lu='Lunethra:BAABNQAECn8vAAISAAoKEg6qawA8AgASAAoKEg6qawA8AgAAAA==.Luukiss:BAAANQADCgQIBQAAAA==.Luyang:BAAANQADCgIIAgAAAA==.',
['Lü']='Lümen:BAAANQAECgIIAwAAAA==.',
Ma='Madcow:BAAANQADCgcIBwABNQAECggIHQASAFAiAA==.Madhat:BAAANQAECggIEgAAAA==.Magerag:BAABNQAECn8lAAIJAAkKqCHCHgBdAwAJAAkKqCHCHgBdAwAAAA==.Malyc:BAAANQAECgQIBQAAAA==.',
Mc='Mcribz:BAACNQAFFH8IAAIgAAUKnBlnBgC4AQAgAAUKnBlnBgC4AQA1AAQKfzAAAiAACgqYJXYQADMDACAACgqYJXYQADMDAAAA.',
Me='Meap:BAAANQAECgQIBwAAAA==.Mecatank:BAAANQAECgEJAgAAAA==.Medra:BAAANQABCgQIBAAAAA==.Meelonusk:BAABNQAECn8XAAMCAAkK8Q4vMgD9AAABAAcKMgzYrwBxAQACAAQKpBAvMgD9AAAAAA==.',
Mi='Michaelcoyle:BAABNQAECn86AAISAAoKPyCOFQBGAwASAAoKPyCOFQBGAwAAAA==.Milo:BAAANQAECgYIDgAAAA==.Mitra:BAABNQAECn8mAAIOAAgKTxmOAQAQAgAOAAgKTxmOAQAQAgAAAA==.',
Mo='Moesko:BAABNQAECn8XAAIhAAcKiBuWJAAAAgAhAAcKiBuWJAAAAgAAAA==.Mogianna:BAAANQABCgMIAwABNQAECgEIBAANAAAAAA==.Monktup:BAAANQAECgEIAwAAAA==.Monkzo:BAAANQAECgEIAwABNQAECgoKLwAZALAYAA==.Monnehbaggs:BAACNQAFFH8GAAIZAAYKQxw7DwCfAQAZAAYKQxw7DwCfAQA1AAQKf0UAAxkACgrVJH0AAPUDABkACgrVJH0AAPUDACIABQqeGqcFACIBAAAA.',
Mu='Munchies:BAAANQABCgIIAgAAAA==.Murdersamich:BAAANQADCggJCQAAAA==.',
My='Myraghor:BAABNQAECn87AAIVAAoKUyAoBQBMAwAVAAoKUyAoBQBMAwAAAA==.',
Na='Nalmec:BAAANQADCgQIBAAAAA==.Naysayre:BAAANQAECgEIAQAAAA==.',
Ne='Nebody:BAAANQAECgEIAwAAAA==.Necriss:BAABNQAECn8sAAIPAAgK1w/JggBLAQAPAAgK1w/JggBLAQAAAA==.',
Ni='Nike:BAAANQAECggIEgAAAA==.',
No='Norni:BAAANQAECgcIEQAAAA==.Nowarning:BAAANQAECgQIBgAAAA==.',
Og='Oghom:BAAANQADCggIGQAAAA==.',
Op='Opeep:BAAANQAECgYIDgAAAA==.',
Or='Oruum:BAAANQADCgYICAAAAA==.',
Pa='Papachance:BAAANQAECgEIAwAAAA==.Papafrank:BAAANQAECgEIAgAAAA==.Papapump:BAABNQAECn8jAAIjAAoK6hzUDwBrAgAjAAoK6hzUDwBrAgAAAA==.Parlare:BAABNQAECn8XAAIhAAkKOhrvIAAiAgAhAAkKOhrvIAAiAgABNQAECgoKNgAZAKcfAA==.',
Pe='Perrinaya:BAAANQADCgQIBwAAAA==.',
Ph='Phoenixwing:BAAANQADCgYIDAAAAA==.',
Pi='Piedrita:BAAANQADCgMIAwAAAA==.Pinga:BAABNQAECn82AAMZAAoKpx+ZEQDeAgAZAAoKCB+ZEQDeAgAiAAYKMhoNCQDMAQAAAA==.',
Po='Poshifru:BAAANQAECgYIEAABNQABCgIIAgANAAAAAA==.',
Pr='Preposition:BAABNQAECn8nAAISAAoKAhahWABpAgASAAoKAhahWABpAgAAAA==.',
Pu='Pussduty:BAABNQAECn82AAISAAoKECIeDwDWAgASAAoKECIeDwDWAgAAAA==.',
Ra='Raaziel:BAAANQAECggIDQAAAA==.Racknar:BAAANQAECgUICgAAAA==.Rafìki:BAAANQAECgQICAAAAA==.Raggnar:BAABNQAECn8eAAIMAAkKgSFOGwAmAwAMAAkKgSFOGwAmAwAAAA==.Ragingwaters:BAAANQADCgYIBgAAAA==.Ranvir:BAAANQADCggIGgAAAA==.Raun:BAABNQAECn82AAMPAAgKrSDZUQCgAgAPAAgKrSDZUQCgAgAXAAYKIAabuAAMAQAAAA==.',
Re='Reactionhank:BAAANQAECgUJBQAAAA==.Relaire:BAABNQAECn8jAAISAAgKFwmPjQAWAQASAAgKFwmPjQAWAQAAAA==.',
Ri='Riku:BAABNQAECn8rAAIeAAgKVx2PCgCQAgAeAAgKVx2PCgCQAgAAAA==.',
Ro='Roots:BAABNQAECn8mAAIIAAoKrx9jDQBfAwAIAAoKrx9jDQBfAwAAAA==.',
Ru='Rumplfourskn:BAAANQADCgIIAgAAAA==.',
Ry='Ryveri:BAABNQAECn8kAAIdAAoKMhqgWgB8AgAdAAoKMhqgWgB8AgAAAA==.',
Sa='Sablehide:BAABNQAECn8qAAQkAAgK0hIkBwBNAQAlAAgKbA1uGQCyAQAkAAcK0hIkBwBNAQAmAAIKvA8cRgBxAAAAAA==.Salute:BAAANQAECgYIBwAAAA==.Sanaty:BAAANQAECgYIEAAAAA==.Saryn:BAAANQAECgMIAwAAAA==.Sathanus:BAAANQAECgIIAgAAAA==.Sazuna:BAAANQAECgUIBwAAAA==.Sazuni:BAAANQAECgUIDwAAAA==.',
Sc='Scuffedname:BAAANQAECgIIAgAAAA==.',
Se='Secrett:BAAANQADCgcIDgAAAA==.',
Sf='Sfora:BAAANQAECgEIBAAAAA==.',
Sh='Shadowreaper:BAAANQAECgUIBQAAAA==.Shelby:BAAANQAECgEIAgAAAA==.Shiggs:BAAANQAECgEIAQAAAA==.Shortsighted:BAAANQAECggIDAABNQAFFAUICAAgAJwZAA==.Shoçknezz:BAAANQAECgEIAgAAAA==.',
Si='Silentsnake:BAEANQAECggIBwABNQAECgoKJAAIAMETAA==.Silverwolf:BAABNQAECn86AAIjAAoKORiVBwBKAgAjAAoKORiVBwBKAgAAAA==.Simplyunlock:BAABNQAECn8uAAMBAAoKURMuewDzAQABAAkKfxIuewDzAQACAAQKbRHgNwDhAAAAAA==.Simplyvoided:BAAANQAECgIIAwAAAA==.Siphin:BAAANQAECggIAQAAAA==.Sizzlechop:BAABNQAECn8pAAIUAAgK5xCsMgAfAQAUAAgK5xCsMgAfAQAAAA==.Sizzlerocks:BAAANQADCgYIBgAAAA==.',
Sk='Skizzak:BAAANQAECggIEQABNQAFFAUICAAgAJwZAA==.',
Sl='Slee:BAAANQAECgMICgAAAA==.Slimedog:BAAANQAECgEJAgAAAA==.',
Sm='Smelvin:BAAANQAECgYIEwABNQAECgkJFwACAPEOAA==.',
Sn='Snailslolol:BAABNQAECn8oAAIXAAoKlBpcEwCtAgAXAAoKlBpcEwCtAgAAAA==.Snakes:BAEBNQAECn8eAAIUAAoKfxQLGwC8AQAUAAoKfxQLGwC8AQABNQAECgoKJAAIAMETAA==.Sneaksatoke:BAAANQADCgMIAwAAAA==.',
So='Solåra:BAAANQADCgUIBQABNQAECgoKHgAFAKUPAA==.Songs:BAAANQADCgQIBQABNQADCgcIEQANAAAAAA==.',
Sq='Squirtin:BAAANQAECgUIDwAAAA==.',
St='Stalath:BAAANQAECgIIBAAAAA==.Stormquota:BAABNQAECn8VAAIjAAoKzhytBQCEAgAjAAoKzhytBQCEAgABNQAECgoKJwAMAL8hAA==.Stormwing:BAAANQAECgIIBQAAAA==.',
Su='Sumarr:BAAANQAECggICgAAAA==.',
Sv='Svenn:BAAANQADCggIDwAAAA==.',
Sw='Swiftstrike:BAAANQADCgYIBgAAAA==.',
Ta='Taboo:BAAANQAECgYIDgAAAA==.Talron:BAAANQADCgcIEQAAAA==.Tango:BAAANQAECgIIAgAAAA==.Tatertots:BAABNQAECn8tAAIYAAkKXRglHADrAQAYAAkKXRglHADrAQAAAA==.',
Te='Tea:BAABNQAECn8rAAISAAoKjB/dHQAgAwASAAoKjB/dHQAgAwAAAA==.Teach:BAAANQAFFAIIAgABNQAFFAMIBwAbAFsNAA==.Teilsande:BAAANQAECggIAQAAAA==.Teleportato:BAAANQAECgQIBAAAAA==.Templyn:BAABNQAECn8oAAMUAAoK1A+AUACyAQAUAAoK1A+AUACyAQAgAAEKAAAl5QAvAAAAAA==.',
Th='Thannos:BAAANQADCggIEwAAAA==.Theus:BAAANQADCgUICQAAAA==.Thyrus:BAABNQAECn8zAAImAAoKSx3kDADXAgAmAAoKSx3kDADXAgABNQAECgoKNgAZAKcfAA==.',
Ti='Tirna:BAABNQAECn8sAAIJAAgKqRXBYwCEAQAJAAgKqRXBYwCEAQAAAA==.',
To='Tomsellock:BAAANQAECgEIAQAAAA==.Tonytemplar:BAAANQABCgIIBQAAAA==.',
Tu='Tullen:BAEBNQAECn8xAAIZAAgKNRFBawDcAQAZAAgKNRFBawDcAQAAAA==.Turanos:BAAANQAECgYICAAAAA==.Tutio:BAAANQADCgYIBgAAAA==.',
Ty='Tyindaris:BAAANQADCgUJCAAAAA==.',
['Té']='Témplýn:BAAANQAECgYIDgABNQAECgoKKAAUANQPAA==.',
['Të']='Tëmplýn:BAAANQAECgEIAQABNQAECgoKKAAUANQPAA==.Tëmplÿn:BAAANQAECgYIBgABNQAECgoKKAAUANQPAA==.',
Ul='Ullr:BAAANQAECgEIAgAAAA==.Ultrachad:BAACNQAFFH8ZAAIUAAcKWyApAwCiAQAUAAcKWyApAwCiAQA1AAQKfzUAAhQACgreImsFAAYDABQACgreImsFAAYDAAAA.',
Un='Unggoy:BAACNQAFFH8WAAMTAAgKRhzmBwDMAQATAAcKXhrmBwDMAQASAAEK0CVLLgBlAAA1AAQKfyYAAxMACgqEJMQOAPcCABMACgolJMQOAPcCABIAAQrrJjk9AWkAAAAA.Unholysin:BAAANQADCggIKwAAAA==.',
Ur='Urianna:BAAANQAECgYICgAAAA==.',
Uw='Uwuther:BAAANQAECgQICAAAAA==.',
Va='Vaelthirion:BAAANQAECgEIBQAAAA==.Vahidamus:BAAANQAECgcIEQAAAA==.Valmirax:BAAANQADCgcICgAAAA==.Valton:BAAANQAECgMIBgAAAA==.Vaurix:BAAANQAECgYIEAAAAA==.',
Ve='Vezarion:BAAANQADCgUIBgAAAA==.',
Wa='Wafuzz:BAAANQAECgQIBAAAAA==.Waters:BAAANQADCgMIAwAAAA==.',
We='Wesellpallys:BAAANQADCgUIBQABNQAECgkJFwACAPEOAA==.',
Wh='Whambamslam:BAAANQADCggICAAAAA==.',
Wi='Windhorn:BAAANQAECgEIAQAAAA==.Winds:BAAANQADCgcIEQAAAA==.Windtalker:BAAANQADCgQIBAABNQAECgUIBQANAAAAAA==.',
Wo='Wolfen:BAAANQADCggICAAAAA==.Wolfquota:BAABNQAECn8nAAIMAAoKvyFzDQC4AgAMAAoKvyFzDQC4AgAAAA==.Wombaa:BAABNQAECn8xAAMgAAoKOSX5CAB4AwAgAAkKiiX5CAB4AwAYAAkKziD+EwA6AgAAAA==.',
Wr='Wrathdk:BAAANQAECgcIEQABNQAFFAIIAwANAAAAAA==.Wrathm:BAAANQAFFAIIAwAAAA==.Wrathmo:BAABNQAECn8WAAMGAAgKOhBqMACUAQAGAAcKExJqMACUAQAHAAQKaweFJACtAAABNQAFFAIIAwANAAAAAA==.Wrenkyian:BAAANQADCgUIBQAAAA==.',
Ya='Yani:BAAANQADCgYICgAAAA==.',
Ye='Yeah:BAAANQABCgUIBAAAAA==.',
Yo='Yoana:BAAANQABCgIIAgAAAA==.Yougotsniped:BAAANQADCgUIBQAAAA==.',
Za='Zakos:BAAANQADCggICAAAAA==.Zareeq:BAAANQADCgIIAgAAAA==.',
Zo='Zoa:BAAANQAECgEIAQAAAA==.',
['Ìl']='Ìllidan:BAAANQAECgEIAQAAAA==.',
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
