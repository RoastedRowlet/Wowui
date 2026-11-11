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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship','Warrior-Protection','Warrior-Arms','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Druid-Balance','DeathKnight-Unholy','Mage-Arcane','DemonHunter-Havoc','Monk-Mistweaver','Shaman-Elemental','Unknown-Unknown','Rogue-Outlaw','Paladin-Retribution','Shaman-Restoration','Rogue-Assassination','Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Paladin-Holy','DeathKnight-Frost','Priest-Holy','Mage-Frost','Priest-Shadow','Druid-Feral','Paladin-Protection','Druid-Restoration','Priest-Discipline','Shaman-Enhancement','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Mage-Fire',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abacus:BAAANQAECggIDwAAAA==.',
Ad='Adam:BAACNQAFFH8aAAQBAAkKzRd5BwDxAQABAAcKCRV5BwDxAQACAAIKdB3xCwCgAAADAAEKNRlGDwBWAAA1AAQKfzwABAIACgoSJY0IAHQCAAEACQq3JJsiAHoCAAIACApRG40IAHQCAAMAAwr5IOciAFQAAAAA.Adumb:BAAANQAECgQIBAABNQAFFAkJFwAEAKkaAA==.',
Ak='Akurama:BAAANQAECgYICgAAAA==.',
Al='Allfrowns:BAAANQAECgcJEQAAAA==.Allsmiles:BAABNQAECn8YAAMFAAgKhCFxDwAzAgAFAAgKhCFxDwAzAgAGAAQKpBG4AQHZAAAAAA==.Allura:BAAANQAECgQIBQAAAA==.Alunaris:BAAANQAECgEJAgAAAA==.',
Am='Amoon:BAABNQAECn87AAMHAAgK/xXTKQD1AQAHAAgK/xXTKQD1AQAIAAIKZxA7KgBiAAAAAA==.',
An='Ancalagon:BAAANQADCgQIBAAAAA==.',
Ar='Archymedes:BAAANQAECgIIAgAAAA==.Arckady:BAAANQAECgYICAAAAA==.Array:BAAANQADCggICAAAAA==.Artharius:BAABNQAECn8yAAMJAAoK1SLuCwCRAgAJAAoK1SLuCwCRAgAKAAUKNxQgHAAkAQAAAA==.',
As='Asbestos:BAAANQAECgMIAwAAAA==.',
Au='Auburnbeard:BAAANQAECgEJAQAAAA==.',
Av='Averle:BAAANQAECgIIBQAAAA==.',
Ba='Badchoices:BAAANQAECgEIAgAAAA==.Badkittie:BAAANQADCgUICgAAAA==.Bangbuscuir:BAAANQAECgEIBAAAAA==.Baretta:BAABNQAECn8WAAQFAAcK9glUKwCRAAAGAAUKyAXNCgHHAAAFAAUKVA1UKwCRAAALAAIK4wd0MgA4AAAAAA==.',
Be='Beefsnake:BAEBNQAECn8sAAIMAAoKOxUnLAB5AgAMAAoKOxUnLAB5AgAAAA==.Beefytips:BAAANQADCgIJAgAAAA==.Belinda:BAAANQAECgUIBAABNQAFFAUICAANAJwZAA==.Bettyßaraxus:BAABNQAECn8jAAIBAAkK3xI4UADQAQABAAkK3xI4UADQAQAAAA==.Bettyßarrage:BAAANQADCgUIBQABNQAECgkJIwABAN8SAA==.Bettyßlight:BAAANQADCgUICAABNQAECgkJIwABAN8SAA==.',
Bi='Bigunsforu:BAAANQAECgYICwAAAA==.',
Bl='Blóódlust:BAAANQAECgQIBAAAAA==.',
Bo='Bogs:BAABNQAECn8zAAIOAAoK4h5+KQCOAgAOAAoK4h5+KQCOAgAAAA==.Bolomorte:BAAANQAECgEIAQAAAA==.Boragish:BAABNQAECn8aAAIBAAkK0gqBogCQAQABAAkK0gqBogCQAQAAAA==.Botname:BAAANQAECgEIAQABNQAECgkJGgABACEWAA==.Boulderfist:BAAANQADCggIFAAAAA==.',
Br='Brolic:BAABNQAECn82AAIPAAoKFRwVFABuAgAPAAoKFRwVFABuAgAAAA==.',
Bu='Bubbleman:BAAANQADCgQIBAAAAA==.Bubblestomps:BAAANQADCgMIAwAAAA==.Burial:BAAANQAECgYICAAAAA==.Burntchicken:BAAANQABCgMIAwAAAA==.',
Bw='Bwonsamdy:BAAANQAECgIIAgAAAA==.',
['Bä']='Bämboo:BAABNQAECn8dAAIQAAgKUhomEQBsAgAQAAgKUhomEQBsAgAAAA==.',
Ca='Cail:BAEBNQAECn8fAAIRAAcKzAwnpQBKAQARAAcKzAwnpQBKAQAAAA==.Calamìty:BAAANQAECgMIAwABNQAECggIBwASAAAAAA==.Calisa:BAABNQAECn88AAITAAgKHhoVAwC6AQATAAgKHhoVAwC6AQAAAA==.Callowz:BAAANQABCgYIBAAAAA==.Cantstandya:BAABNQAECn8vAAIUAAoKsyHVHADlAgAUAAoKsyHVHADlAgAAAA==.Carnifex:BAABNQAECn8VAAMRAAcK+BZRigCKAQARAAYK8xhRigCKAQAVAAcKLA7FjgBkAQABNQAECgkJGgABACEWAA==.',
Ce='Ceryph:BAAANQAECgEIAQAAAA==.',
Ch='Charis:BAAANQADCgEIAQAAAA==.Chewbub:BAAANQADCgIIAgAAAA==.Chigutotems:BAEBNQAECn8wAAIVAAoKqh2SFQAiAwAVAAoKqh2SFQAiAwAAAA==.Chow:BAAANQAECgEIAQABNQAECgYICAASAAAAAA==.Chozen:BAACNQAFFH8IAAIWAAMK5yHuDAAqAQAWAAMK5yHuDAAqAQA1AAQKfzMAAhYACgowJDoLADADABYACgowJDoLADADAAAA.Chroniccloud:BAAANQAECgEIAQAAAA==.',
Co='Cornelius:BAAANQAECgYIDwAAAA==.Corporicky:BAAANQAECgEIAQAAAA==.Coulee:BAAANQADCgUICwABNQAECgoKIgAPAB0aAA==.',
Cr='Cronicpain:BAAANQAECggICQAAAA==.',
Cy='Cymbi:BAAANQABCgQIAwAAAA==.',
Da='Daks:BAAANQADCgQIBAAAAA==.Darklucrezia:BAABNQAECn83AAMXAAoKaxlLXAD4AQAXAAkKwxpLXAD4AQAEAAEKBBATZQAxAAAAAA==.Darkpyro:BAAANQADCggIEgAAAA==.',
De='Deetsy:BAAANQADCgYICAAAAA==.Dextrose:BAAANQAECggIDAAAAA==.',
Di='Dicey:BAABNQAECn8aAAMBAAkKIRb4QQD/AQABAAkKIRb4QQD/AQACAAEK/A2ZdQA4AAAAAA==.',
Dk='Dkbig:BAAANQAECgYIDwAAAA==.',
Dr='Dracarius:BAAANQAECgYICgAAAA==.Drtypinkcake:BAAANQAECgUIEAAAAA==.Druidcant:BAAANQADCgYIBgAAAA==.Drworldwide:BAAANQAECggICgAAAA==.Dryad:BAAANQAECgYICAAAAA==.',
Du='Durkk:BAABNQAECn9BAAIYAAgKOSCDHgC+AgAYAAgKOSCDHgC+AgAAAA==.Durza:BAAANQADCggICAAAAA==.',
Dw='Dwayne:BAAANQAECgYIBgAAAA==.',
['Dä']='Dännydevito:BAAANQADCgMIBAAAAA==.',
En='Enss:BAAANQADCgUJBQAAAA==.',
Es='Estara:BAABNQAECn8/AAIZAAgKvA+xIwB5AQAZAAgKvA+xIwB5AQAAAA==.',
Et='Etali:BAABNQAECn81AAILAAgKMxgfDAD8AQALAAgKMxgfDAD8AQAAAA==.Etherious:BAAANQAECgUICAABNQAECgoKGAAaAA8RAA==.',
Fa='Fanis:BAABNQAECn8tAAIEAAgKowwJHwBkAQAEAAgKowwJHwBkAQAAAA==.Faynor:BAAANQADCgQIBAAAAA==.',
Fi='Fibo:BAAANQADCgQIBAAAAA==.',
Fl='Flashis:BAABNQAECn8XAAQJAAoKFQu0LwCaAQAJAAoKAQu0LwCaAQAQAAUKWQM8OQClAAAKAAMK+gZ4HAByAAAAAA==.Floor:BAAANQABCgIIAgAAAA==.Florago:BAAANQAECgYICAAAAA==.',
Fo='Force:BAAANQAECgEIAgAAAA==.',
Fr='Frakir:BAABNQAECn9BAAMVAAgKKh+SKAB0AgAVAAgKKh+SKAB0AgARAAEKAAApUwEkAAAAAA==.',
Fu='Furrypaw:BAABNQAECn80AAMQAAgKliEHCgCVAgAQAAgKliEHCgCVAgAJAAEKAADocgAnAAAAAA==.Fuzzyy:BAAANQADCgUIBQABNQADCgQIBAASAAAAAA==.',
Fw='Fwapp:BAACNQAFFH8WAAIaAAcKpxUBBwD6AQAaAAcKpxUBBwD6AQA1AAQKfzEAAhoACgq0JMoEAKoDABoACgq0JMoEAKoDAAAA.',
Ga='Galvanize:BAABNQAECn8XAAMVAAYKXhIeqAAhAQAVAAYKXhIeqAAhAQARAAUK1QrByAABAQAAAA==.',
Ge='Genny:BAAANQAECggICAAAAA==.',
Gi='Gijaick:BAABNQAECn8cAAMCAAoKMA2SNQDsAAABAAoKhAsjkwAfAQACAAQKeguSNQDsAAAAAA==.',
Gl='Glizzo:BAABNQAECn9LAAIOAAoKrxaeRQAuAgAOAAoKrxaeRQAuAgAAAA==.Gloomrider:BAAANQADCgUIBQAAAA==.',
Go='Gold:BAAANQADCgUIBQAAAA==.Goldhawk:BAAANQAECgUIBQAAAA==.Gotwiped:BAABNQAECn81AAIbAAkKzyDHDQDcAgAbAAkKzyDHDQDcAgAAAA==.',
Gr='Grexx:BAAANQAECgMIBAABNQAFFAYIBgAcAEMcAA==.',
Gu='Gunnery:BAAANQAECggIDgAAAA==.',
Gy='Gyu:BAAANQADCgYIDQAAAA==.',
Ha='Hantaz:BAAANQAECggIDgAAAA==.Haoleboy:BAAANQAECgEIAQAAAA==.Hatter:BAABNQAECn8+AAMHAAoKzBuMDwBQAgAHAAoKzBuMDwBQAgAIAAcKXBfrDwC1AQAAAA==.',
He='Hellraiser:BAABNQAECn8aAAIYAAcK7BYWPgA5AQAYAAcK7BYWPgA5AQAAAA==.',
Hi='Hidduka:BAABNQAECn8aAAIaAAgKbxyaPAByAgAaAAgKbxyaPAByAgAAAA==.Hills:BAAANQAECgEIAQAAAA==.',
Ho='Holyascended:BAAANQADCggIFgAAAA==.Holydarkness:BAAANQADCgYIBgAAAA==.Holykilla:BAAANQADCgUIBQAAAA==.Holykiller:BAAANQADCgEIAQAAAA==.Hoplite:BAAANQAECggIDQAAAA==.Hothots:BAAANQABCgYIBgABNQAECgYICAASAAAAAA==.Howlly:BAABNQAECn8xAAIdAAoKnSG0AwCwAgAdAAoKnSG0AwCwAgAAAA==.',
Hr='Hraun:BAAANQADCgIIAQAAAA==.',
Hu='Hulner:BAAANQAECggIAgAAAA==.',
Ik='Ikeanola:BAABNQAECn8eAAIUAAkKlgVF7QBBAQAUAAkKlgVF7QBBAQAAAA==.',
In='Inapa:BAAANQAECgYIBgAAAA==.Indras:BAAANQADCgcIFgAAAA==.Ines:BAABNQAECn8lAAIbAAkKih+EEgD5AgAbAAkKih+EEgD5AgAAAA==.Inhume:BAAANQADCggJCQAAAA==.Inter:BAAANQADCgIIAgAAAA==.',
Is='Ismarus:BAAANQAECgQIBQAAAA==.',
Ja='Jaarus:BAAANQAECgcIDgAAAA==.Jajal:BAABNQAECn8YAAIeAAkKCBH1JAAIAgAeAAkKCBH1JAAIAgABNQAECgoKFwAJABULAA==.Jankadish:BAABNQAECn8dAAQGAAkKUAozkABMAQAGAAgKtAgzkABMAQAFAAYKaAn3JwD/AAALAAEKjQZUNAApAAAAAA==.Jaspirian:BAAANQADCgYIBgAAAA==.',
Je='Jehm:BAABNQAECn8pAAIYAAoKCBDPUwClAQAYAAoKCBDPUwClAQAAAA==.Jerome:BAAANQADCgMIAwAAAA==.',
Ju='Juiceboxer:BAAANQAECgQICQABNQAECgUIDAASAAAAAA==.Juicy:BAAANQADCgYIBgAAAA==.Justicehand:BAAANQAECgMIBQAAAA==.',
Ka='Kaestia:BAAANQAECgEIAQABNQAECgoKMQAdACEgAA==.Kagor:BAAANQADCgMIAwABNQAECgcIDgASAAAAAA==.Kalia:BAABNQAECn8xAAMdAAoKISDOBADWAgAdAAkK0iDOBADWAgAOAAkKMBilvAALAgAAAA==.Kalipto:BAAANQADCgcICAAAAA==.Katatonik:BAAANQAECgUIBwABNQAECgcIDgASAAAAAA==.Katharina:BAABNQAECn8bAAMaAAoKahN1YQD0AQAaAAoKahN1YQD0AQAUAAEKAABAuAEsAAAAAA==.Katoume:BAABNQAECn8jAAMfAAoKJCQvAgAxAwAfAAoKJCQvAgAxAwAZAAEKLRxzWgBTAAABNQAECgoKIwAfACQkAA==.Katoumey:BAAANQAECgYIEgABNQAECgoKIwAfACQkAA==.Kaulder:BAAANQADCgMIAwAAAA==.',
Kh='Khumfuu:BAAANQAECgQICQAAAA==.',
Ki='Kinan:BAABNQAECn9BAAMXAAkKCSVXFADwAgAEAAgKcCKyDAARAwAXAAkKCSVXFADwAgAAAA==.',
Ko='Konan:BAAANQADCgMIAwAAAA==.Korlo:BAAANQAECgUICQAAAA==.',
Ku='Kuala:BAAANQADCgIIAgAAAA==.',
Ky='Kythin:BAAANQAECgMIDAABNQAECgoKMQAdACEgAA==.',
La='Lacutis:BAAANQAECgEIAQAAAA==.',
Le='Leonus:BAAANQADCgQIBAAAAA==.',
Li='Lichmcconnel:BAABNQAECn8xAAQDAAoKAxq0BQBgAgADAAoKAxq0BQBgAgACAAEKWAdjewAyAAABAAEKbQQXFQEuAAAAAA==.Lillica:BAAANQADCgQIBAAAAA==.Lilmeesh:BAAANQADCgQIBAAAAA==.Lisabeth:BAAANQAECgEIAwABNQAFFAkJFwAEAKkaAA==.',
Lo='Lockcuir:BAAANQAECgEIAQABNQAECgEIBAASAAAAAA==.Lomponic:BAEBNQAECn80AAIeAAoK8R40EQDoAgAeAAoK8R40EQDoAgAAAA==.Lonelyone:BAAANQAECgMIBQAAAA==.Lore:BAACNQAFFH8KAAIgAAYKWxFTBAAHAQAgAAYKWxFTBAAHAQA1AAQKfzEAAiAACgpkG2gZACkCACAACgpkG2gZACkCAAAA.',
Lu='Lucífer:BAAANQABCgUIBQAAAA==.Lunethra:BAABNQAECn8wAAIXAAoKEg6qawA8AgAXAAoKEg6qawA8AgAAAA==.Luukiss:BAAANQADCgQIBQAAAA==.Luyang:BAAANQADCgIIAgAAAA==.',
['Lü']='Lümen:BAAANQAECgIIBAAAAA==.',
Ma='Madcow:BAAANQADCgcIBwABNQAECggIHQAXAFAiAA==.Madhat:BAAANQAECggIEgAAAA==.Magerag:BAABNQAECn8lAAIOAAkKqCHCHgBdAwAOAAkKqCHCHgBdAwAAAA==.Malyc:BAAANQAECgQIBQAAAA==.',
Mc='Mcribz:BAACNQAFFH8IAAINAAUKnBlnBgC4AQANAAUKnBlnBgC4AQA1AAQKf0oAAg0ACgriJZQBAG8DAA0ACgriJZQBAG8DAAAA.',
Me='Meap:BAAANQAECgQIBwAAAA==.Mecatank:BAAANQAECgEJAgAAAA==.Medra:BAAANQABCgQIBAAAAA==.Meelonusk:BAABNQAECn8XAAMCAAkK8Q4vMgD9AAABAAcKMgzYrwBxAQACAAQKpBAvMgD9AAAAAA==.',
Mi='Michaelcoyle:BAABNQAECn9IAAIXAAoKYiGOFQBGAwAXAAoKYiGOFQBGAwAAAA==.Milo:BAAANQAECgYIDgAAAA==.Mitra:BAABNQAECn8pAAITAAgK5xomAgAZAgATAAgK5xomAgAZAgAAAA==.',
Mo='Moesko:BAABNQAECn8dAAIhAAkKpBx/HwDkAQAhAAkKpBx/HwDkAQAAAA==.Mogianna:BAAANQABCgMIAwABNQAECgEIAgASAAAAAA==.Monktup:BAAANQAECgEIAwAAAA==.Monkzo:BAAANQAECgEIAwABNQAECgoKMQAcACgaAA==.Monnehbaggs:BAACNQAFFH8GAAIcAAYKQxw7DwCfAQAcAAYKQxw7DwCfAQA1AAQKf00AAxwACgrVJH0AAPUDABwACgrVJH0AAPUDACIABQqeGnEIAB8BAAAA.',
Mu='Munchies:BAAANQABCgIIAgAAAA==.Murdersamich:BAAANQADCggJCQAAAA==.',
My='Myraghor:BAABNQAECn88AAIZAAoKUyAoBQBMAwAZAAoKUyAoBQBMAwAAAA==.',
Na='Nalmec:BAAANQADCgQIBAAAAA==.Naysayre:BAAANQAECgEIAQAAAA==.',
Ne='Nebody:BAAANQAECgUIBwAAAA==.Necriss:BAABNQAECn85AAIUAAgK4A/ErgDCAQAUAAgK4A/ErgDCAQAAAA==.',
Ni='Nike:BAABNQAECn8gAAIXAAoKzR3TUAAWAgAXAAoKzR3TUAAWAgAAAA==.',
No='Norni:BAAANQAECgYIEQAAAA==.Nowarning:BAAANQAECgQIBgAAAA==.',
Og='Oghom:BAAANQADCggIGQAAAA==.',
Op='Opeep:BAAANQAECgYIDgAAAA==.',
Or='Ordestur:BAAANQADCggICAAAAA==.Oruum:BAAANQADCgYICAAAAA==.',
Os='Osos:BAAANQADCgQIBAAAAA==.',
Pa='Papachance:BAAANQAECgUICQAAAA==.Papafrank:BAAANQAECgYICAAAAA==.Papapump:BAABNQAECn8sAAIjAAoKxx5eCACRAgAjAAoKxx5eCACRAgAAAA==.Parlare:BAABNQAECn8hAAIhAAoKwxs1EQCbAgAhAAoKwxs1EQCbAgABNQAECgoKPAAcAKcfAA==.',
Pe='Perrinaya:BAAANQADCgQIBwAAAA==.',
Ph='Phoenixwing:BAAANQADCgYIDAAAAA==.',
Pi='Piedrita:BAAANQADCgMIAwAAAA==.Pinga:BAABNQAECn88AAMcAAoKpx8LIADLAgAcAAoKCB8LIADLAgAiAAYKMhoNCQDMAQAAAA==.',
Po='Poshifru:BAAANQAECgYIEAABNQABCgIIAgASAAAAAA==.',
Pr='Preposition:BAABNQAECn8uAAIXAAoKWBahWABpAgAXAAoKWBahWABpAgAAAA==.',
Pu='Pussduty:BAABNQAECn8/AAIXAAoK5yJwEwBRAwAXAAoK5yJwEwBRAwAAAA==.',
Ra='Raaziel:BAAANQAECggIEQAAAA==.Racknar:BAABNQAECn8aAAIXAAkKAQwpdwC0AQAXAAkKAQwpdwC0AQAAAA==.Rafìki:BAAANQAECgYIEgAAAA==.Raggnar:BAABNQAECn8qAAIRAAoK2h9OGwAmAwARAAoK2h9OGwAmAwAAAA==.Ragingwaters:BAAANQADCgYIBgAAAA==.Ranvir:BAAANQADCggIGgAAAA==.Raun:BAABNQAECn9EAAMUAAgKrSDZUQCgAgAUAAgKrSDZUQCgAgAaAAYKIAabuAAMAQAAAA==.',
Re='Reactionhank:BAAANQAECgUJBQAAAA==.Relaire:BAABNQAECn8xAAIXAAgK7QoHmQBmAQAXAAgK7QoHmQBmAQAAAA==.',
Ri='Riku:BAABNQAECn85AAIfAAgKGx+gCwD8AQAfAAgKGx+gCwD8AQAAAA==.',
Ro='Roots:BAABNQAECn8sAAIMAAoKZSFjDQBfAwAMAAoKZSFjDQBfAwAAAA==.',
Ru='Rumplfourskn:BAAANQADCgIIAgAAAA==.',
Ry='Ryveri:BAABNQAECn8nAAIGAAoKABugWgB8AgAGAAoKABugWgB8AgAAAA==.',
Sa='Sablehide:BAABNQAECn8uAAQkAAgK0hLDCgBBAQAlAAgKbA1uGQCyAQAkAAcK0hLDCgBBAQAmAAIKvA8cRgBxAAAAAA==.Salute:BAAANQAECgYIBwAAAA==.Sanaty:BAAANQAECgUIEAAAAA==.Saryn:BAAANQAECgMIAwAAAA==.Sathanus:BAAANQAECgIIAgAAAA==.Sazuna:BAAANQAECgUIBwAAAA==.Sazuni:BAAANQAECgYIEAAAAA==.',
Sc='Scuffedname:BAAANQAECgIIAQAAAA==.',
Se='Secrett:BAAANQADCgcIDgAAAA==.',
Sf='Sfora:BAAANQAECgEIAgAAAA==.',
Sh='Shadowreaper:BAAANQAECgUIBQAAAA==.Shelby:BAAANQAECgEIAgAAAA==.Shiggs:BAAANQAECgEIAQAAAA==.Shortsighted:BAABNQAECn8XAAIXAAoK1xYyQgA9AgAXAAoK1xYyQgA9AgABNQAFFAUICAANAJwZAA==.Shoçknezz:BAAANQAECgEIAgAAAA==.',
Si='Silentsnake:BAEANQAECggIBwABNQAECgoKLAAMADsVAA==.Silverwolf:BAABNQAECn9HAAIjAAoKEBrwCgBcAgAjAAoKEBrwCgBcAgAAAA==.Simplyunlock:BAACNQAFFH8FAAIBAAIKkwL5KQBwAAABAAIKkwL5KQBwAAA1AAQKfzQABAEACgrAEy57APMBAAEACQr+Ei57APMBAAIABAptEeA3AOEAAAMAAQorBZMtAC0AAAAA.Simplyvoided:BAAANQAECgIIAgAAAA==.Siphin:BAAANQAECggIAQAAAA==.Sizzlechop:BAABNQAECn8uAAIYAAkKLhIwMwBvAQAYAAkKLhIwMwBvAQAAAA==.Sizzlerocks:BAAANQADCgYIBgAAAA==.',
Sk='Skizzak:BAABNQAECn8oAAIMAAoK+RfVFgBMAgAMAAoK+RfVFgBMAgABNQAFFAUICAANAJwZAA==.',
Sl='Slee:BAAANQAECgMICgAAAA==.Slimedog:BAAANQAECgEIAgAAAA==.',
Sm='Smelvin:BAAANQAECgYIEQABNQAECgkJFwACAPEOAA==.',
Sn='Snailslolol:BAABNQAECn87AAIaAAoKnBtnFwDsAgAaAAoKnBtnFwDsAgAAAA==.Snakes:BAEBNQAECn8hAAIYAAoKfxT0KACqAQAYAAoKfxT0KACqAQABNQAECgoKLAAMADsVAA==.Sneaksatoke:BAAANQADCgMIAwAAAA==.',
So='Solåra:BAAANQADCgUIBQABNQAECgoKHgAIAKUPAA==.Songs:BAAANQADCgQIBQABNQADCgcIEQASAAAAAA==.',
Sq='Squirtin:BAABNQAECn8ZAAMVAAcK9B8QPwADAgAVAAYKHyMQPwADAgARAAEKAADKHgFTAAAAAA==.',
St='Stalath:BAAANQAECgUIBQAAAA==.Stormquota:BAABNQAECn8mAAIjAAoKLCIOAwAbAwAjAAoKLCIOAwAbAwABNQAECgoKLwARADMiAA==.Stormwing:BAAANQAECgIIAwAAAA==.',
Su='Sumarr:BAAANQAECgcICQAAAA==.',
Sv='Svenn:BAAANQADCggIDwAAAA==.',
Sw='Swiftstrike:BAAANQADCgYIBgAAAA==.',
Ta='Taboo:BAAANQAECgYIDgAAAA==.Talron:BAAANQADCgcIEQAAAA==.Tango:BAAANQAECgIIAgAAAA==.Tatertots:BAABNQAECn80AAIbAAkKlxicKQBNAgAbAAkKlxicKQBNAgAAAA==.',
Te='Tea:BAABNQAECn84AAIXAAoK6CDdHQAgAwAXAAoK6CDdHQAgAwAAAA==.Teach:BAABNQAFFH8HAAMnAAMKLQOsAACgAAAnAAMKvwKsAACgAAAOAAIK3gIgOwBvAAABNQAFFAMIBwAeAFsNAA==.Teilsande:BAAANQAECggIAQAAAA==.Teleportato:BAAANQAECgQIBAAAAA==.Templyn:BAABNQAECn81AAMYAAoK5BDAJQC/AQAYAAoK5BDAJQC/AQANAAEKAAAl5QAvAAAAAA==.',
Th='Thannos:BAAANQADCggIEwAAAA==.Theus:BAAANQADCgUICQAAAA==.Thyrus:BAABNQAECn82AAImAAoK3h3kDADXAgAmAAoK3h3kDADXAgABNQAECgoKPAAcAKcfAA==.',
Ti='Tirna:BAABNQAECn85AAIOAAgK0hVufwCYAQAOAAgK0hVufwCYAQAAAA==.',
To='Tomsellock:BAAANQAECgEIAQAAAA==.Tonytemplar:BAAANQABCgIIBQAAAA==.',
Tu='Tullen:BAEBNQAECn8/AAIcAAgKthcSTwDnAQAcAAgKthcSTwDnAQAAAA==.Turanos:BAAANQAECgYICAAAAA==.Tutio:BAAANQADCgYIBgAAAA==.',
Ty='Tyindaris:BAAANQADCgUJCAAAAA==.',
['Té']='Témplýn:BAAANQAECgYIDwABNQAECgoKNQAYAOQQAA==.',
['Të']='Tëmplýn:BAAANQAECgEIAgABNQAECgoKNQAYAOQQAA==.Tëmplÿn:BAAANQAECgYIBgABNQAECgoKNQAYAOQQAA==.',
Ul='Ullr:BAAANQAECgEIAQAAAA==.Ultrachad:BAACNQAFFH8bAAIYAAgKnh/9BAAqAgAYAAgKnh/9BAAqAgA1AAQKfzcAAhgACgreIgQKAOcCABgACgreIgQKAOcCAAAA.',
Un='Unggoy:BAACNQAFFH8XAAMEAAkKqRrmBwDMAQAEAAgKzRjmBwDMAQAXAAEK0CVLLgBlAAA1AAQKfyYAAwQACgqEJMQOAPcCAAQACgolJMQOAPcCABcAAQrrJjk9AWkAAAAA.Unholysin:BAAANQADCggIKwAAAA==.',
Ur='Urianna:BAAANQAECgYIBwAAAA==.',
Uw='Uwuther:BAAANQAECgQICQAAAA==.',
Va='Vaelthirion:BAAANQAECgEIAwAAAA==.Vahidamus:BAABNQAECn8bAAMVAAgKCQ64ZABxAQAVAAgKCQ64ZABxAQARAAEKAADCWwEeAAAAAA==.Valmirax:BAAANQADCgcICgAAAA==.Valton:BAAANQAECgMIBQAAAA==.Vaurix:BAABNQAECn8aAAIeAAkKkhWhFgDiAQAeAAkKkhWhFgDiAQAAAA==.',
Ve='Vezarion:BAAANQADCgUIBgAAAA==.',
Wa='Wafuzz:BAAANQAECgQIBAAAAA==.Waters:BAAANQADCgMIAwAAAA==.',
We='Wesellpallys:BAAANQADCgUIBQABNQAECgkJFwACAPEOAA==.',
Wh='Whambamslam:BAAANQADCggICAAAAA==.',
Wi='Windhorn:BAAANQAECgEIAQAAAA==.Winds:BAAANQADCgcIEQAAAA==.Windtalker:BAAANQADCgQIBAABNQAECgUIBQASAAAAAA==.',
Wo='Wolfen:BAAANQADCggICAAAAA==.Wolfquota:BAABNQAECn8vAAIRAAoKMyKlGAA1AwARAAoKMyKlGAA1AwAAAA==.Wombaa:BAABNQAECn86AAMNAAoKiCX5CAB4AwANAAkKiiX5CAB4AwAbAAoKlyN4BwAoAwAAAA==.',
Wr='Wrathdk:BAAANQAECgcIEQABNQAFFAIIAwASAAAAAA==.Wrathm:BAAANQAFFAIIAwAAAA==.Wrathmo:BAABNQAECn8WAAMJAAgKOhBqMACUAQAJAAcKExJqMACUAQAKAAQKaweFJACtAAABNQAFFAIIAwASAAAAAA==.Wrenkyian:BAAANQADCgUIBQAAAA==.',
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
