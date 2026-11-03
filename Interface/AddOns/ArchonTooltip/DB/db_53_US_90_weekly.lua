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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship','Warrior-Protection','Warrior-Arms','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Mage-Arcane','DemonHunter-Havoc','Monk-Mistweaver','Shaman-Elemental','Unknown-Unknown','Rogue-Outlaw','Paladin-Retribution','Shaman-Restoration','Rogue-Assassination','Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Warrior-Fury','Paladin-Holy','DeathKnight-Frost','Priest-Holy','Mage-Frost','Priest-Shadow','Druid-Feral','Paladin-Protection','DeathKnight-Unholy','Druid-Restoration','Priest-Discipline','Shaman-Enhancement','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abacus:BAAANQAECggIDgAAAA==.',
Ad='Adam:BAACNQAFFH8ZAAQBAAgKphh5BwDxAQABAAYKnhV5BwDxAQACAAIKdB3xCwCgAAADAAEKNRmqCgBWAAA1AAQKfzsABAIACgoSJY0IAHQCAAEACQq3JLscAIACAAIACApRG40IAHQCAAMAAwr5IM4dAFgAAAAA.Adumb:BAAANQAECgQIBAABNQAFFAgIFgAEAEYcAA==.',
Ak='Akurama:BAAANQAECgYICQAAAA==.',
Al='Allfrowns:BAAANQAECgcJDgAAAA==.Allsmiles:BAABNQAECn8VAAMFAAgKhCFxDwAzAgAFAAgKhCFxDwAzAgAGAAQKpBG4AQHZAAAAAA==.Allura:BAAANQAECgQIBQAAAA==.Alumbrae:BAAANQADCgEIAQAAAA==.Alunaris:BAAANQAECgEJAgAAAA==.',
Am='Amoon:BAABNQAECn83AAMHAAgK/xXiHQB/AQAHAAgK/xXiHQB/AQAIAAIKZxA7KgBiAAAAAA==.',
An='Ancalagon:BAAANQADCgQIBAAAAA==.',
Ar='Archymedes:BAAANQAECgIIAQAAAA==.Arckady:BAAANQAECgYICAAAAA==.Array:BAAANQADCggICAAAAA==.Artharius:BAABNQAECn8yAAMJAAoK1SJoCgCWAgAJAAoK1SJoCgCWAgAKAAUKNxQgHAAkAQAAAA==.',
As='Asbestos:BAAANQAECgMIAwAAAA==.',
Au='Auburnbeard:BAAANQAECgEJAQAAAA==.',
Av='Averle:BAAANQAECgIIAgAAAA==.',
Az='Aztharot:BAAANQADCgEIAQAAAA==.',
Ba='Badchoices:BAAANQAECgEIAQAAAA==.Badkittie:BAAANQADCgUICwAAAA==.Baretta:BAAANQAECgYIEAAAAA==.',
Be='Beefsnake:BAEBNQAECn8kAAILAAoKwRMnLAB5AgALAAoKwRMnLAB5AgAAAA==.Beefytips:BAAANQADCgIJAgAAAA==.Bettyßaraxus:BAABNQAECn8dAAIBAAkKohGuTAC3AQABAAkKohGuTAC3AQAAAA==.Bettyßarrage:BAAANQADCgUIBQABNQAECgkJHQABAKIRAA==.Bettyßlight:BAAANQADCgUICgABNQAECgkJHQABAKIRAA==.',
Bi='Bigunsforu:BAAANQAECggIBwAAAA==.',
Bl='Blóódlust:BAAANQADCgcIBwAAAA==.',
Bo='Bogs:BAABNQAECn8wAAIMAAoK4x31LABtAgAMAAoK4x31LABtAgAAAA==.Bolomorte:BAAANQADCgYJBgAAAA==.Boragish:BAAANQAECgcIEgAAAA==.Boulderfist:BAAANQADCggIFAAAAA==.',
Br='Brolic:BAABNQAECn8wAAINAAoKFRyPEwBWAgANAAoKFRyPEwBWAgAAAA==.',
Bu='Bubbleman:BAAANQADCgQIBAAAAA==.Bubblestomps:BAAANQADCgMIAwAAAA==.Burial:BAAANQAECgYICAAAAA==.Burntchicken:BAAANQADCgEIAQAAAA==.',
Bw='Bwonsamdy:BAAANQAECgIIAgAAAA==.',
['Bä']='Bämboo:BAABNQAECn8dAAIOAAgKUhomEQBsAgAOAAgKUhomEQBsAgAAAA==.',
Ca='Cail:BAEBNQAECn8fAAIPAAcKzAwnpQBKAQAPAAcKzAwnpQBKAQAAAA==.Calamìty:BAAANQAECgMIAwABNQAECggIBQAQAAAAAA==.Calisa:BAABNQAECn81AAIRAAgKihnaAgCtAQARAAgKihnaAgCtAQAAAA==.Cantstandya:BAABNQAECn8vAAISAAoKsyFTFgDyAgASAAoKsyFTFgDyAgAAAA==.Carnifex:BAABNQAECn8VAAMPAAcK+BZRigCKAQAPAAYK8xhRigCKAQATAAcKLA7FjgBkAQABNQAECgkJGgABACEWAA==.',
Ce='Ceryph:BAAANQAECgEIAQAAAA==.',
Ch='Charis:BAAANQADCgEIAQAAAA==.Chewbub:BAAANQADCgIIAgAAAA==.Chigutotems:BAEBNQAECn8wAAITAAoKqh2SFQAiAwATAAoKqh2SFQAiAwAAAA==.Chow:BAAANQABCgUIBQABNQAECgYICAAQAAAAAA==.Chozen:BAACNQAFFH8IAAIUAAMK5yHuDAAqAQAUAAMK5yHuDAAqAQA1AAQKfzMAAhQACgowJDoLADADABQACgowJDoLADADAAAA.Chroniccloud:BAAANQAECgEIAQAAAA==.',
Co='Cornelius:BAAANQAECgYIDwAAAA==.Corporicky:BAAANQAECgEIAQAAAA==.Coulee:BAAANQADCgUICwABNQAECgoKIgANAB0aAA==.',
Cr='Cronicpain:BAAANQAECgUIBgAAAA==.',
Cy='Cymbi:BAAANQADCgEIAQAAAA==.',
Da='Daks:BAAANQADCgQIBAAAAA==.Darklucrezia:BAABNQAECn80AAMVAAoKexhcVgDcAQAVAAkKsBlcVgDcAQAEAAEKBBD7WwA0AAAAAA==.Darkpyro:BAAANQADCggIEQAAAA==.',
De='Deetsy:BAAANQADCgYICAAAAA==.Dextrose:BAAANQAECggICwAAAA==.',
Di='Dicey:BAABNQAECn8aAAMBAAkKIRbwOAD9AQABAAkKIRbwOAD9AQACAAEK/A2ZdQA4AAAAAA==.',
Dk='Dkbig:BAAANQAECgYIDwAAAA==.',
Dr='Dracarius:BAAANQAECgYICAAAAA==.Drtypinkcake:BAAANQAECgUIDQAAAA==.Druidcant:BAAANQADCgYIBgAAAA==.Drworldwide:BAAANQAECggICQAAAA==.Dryad:BAAANQAECgYICAAAAA==.',
Du='Durkk:BAABNQAECn86AAIWAAgKOSCDHgC+AgAWAAgKOSCDHgC+AgAAAA==.Durza:BAAANQADCggICAAAAA==.',
Dw='Dwayne:BAAANQAECgYIBgAAAA==.',
['Dä']='Dännydevito:BAAANQADCgMIBAAAAA==.',
En='Enss:BAAANQADCgUJBQAAAA==.',
Es='Estara:BAABNQAECn84AAIXAAgKvA9fJAAoAQAXAAgKvA9fJAAoAQAAAA==.',
Et='Etali:BAABNQAECn8vAAIYAAgKMxgfDAD8AQAYAAgKMxgfDAD8AQAAAA==.Etherious:BAAANQAECgYIBwABNQAECggIEwAQAAAAAA==.',
Fa='Fanis:BAABNQAECn8mAAIEAAgK0ws0HwA7AQAEAAgK0ws0HwA7AQAAAA==.Faynor:BAAANQADCgQIBAAAAA==.',
Fi='Fibo:BAAANQADCgQIBAAAAA==.',
Fl='Flashis:BAABNQAECn8XAAQJAAoKFQu0LwCaAQAJAAoKAQu0LwCaAQAOAAUKWQM8OQClAAAKAAMK+gbtGQBzAAAAAA==.Floor:BAAANQADCgEIAQAAAA==.Florago:BAAANQAECgYICAAAAA==.',
Fo='Force:BAAANQAECgEIAgAAAA==.',
Fr='Frakir:BAABNQAECn86AAMTAAgKohpvPwBiAgATAAgKohpvPwBiAgAPAAEKAAApUwEkAAAAAA==.',
Fu='Furrypaw:BAABNQAECn8zAAMOAAgKliGHCACeAgAOAAgKliGHCACeAgAJAAEKAADocgAnAAAAAA==.Fuzzyy:BAAANQADCgUIBQABNQADCgQIBAAQAAAAAA==.',
Fw='Fwapp:BAACNQAFFH8WAAIZAAcKpxUBBwD6AQAZAAcKpxUBBwD6AQA1AAQKfy8AAhkACgq0JMoEAKoDABkACgq0JMoEAKoDAAAA.',
Ga='Galvanize:BAAANQAECgQIDwAAAA==.',
Gi='Gijaick:BAABNQAECn8cAAMCAAoKMA2SNQDsAAABAAoKhAumiQATAQACAAQKeguSNQDsAAAAAA==.',
Gl='Glizzo:BAABNQAECn9LAAIMAAoKrxZSPQAyAgAMAAoKrxZSPQAyAgAAAA==.Gloomrider:BAAANQADCgUIBQAAAA==.',
Go='Gold:BAAANQADCgUIBQAAAA==.Goldhawk:BAAANQAECgUIBQAAAA==.Gotwiped:BAABNQAECn8xAAIaAAkKviCfDADUAgAaAAkKviCfDADUAgAAAA==.',
Gr='Grexx:BAAANQAECgMIBAABNQAFFAYIBgAbAEMcAA==.',
Gu='Gunnery:BAAANQAECggIDgAAAA==.',
Gy='Gyu:BAAANQADCgYIDQAAAA==.',
Ha='Hantaz:BAAANQAECggIDgAAAA==.Haoleboy:BAAANQADCggIJwAAAA==.Hatter:BAABNQAECn86AAMHAAoKLxtEDwA5AgAHAAoK1hpEDwA5AgAIAAcKXBfrDwC1AQAAAA==.',
He='Hellraiser:BAABNQAECn8aAAIWAAcK7BZeNwA9AQAWAAcK7BZeNwA9AQAAAA==.',
Hi='Hidduka:BAABNQAECn8aAAIZAAgKbxyaPAByAgAZAAgKbxyaPAByAgABNQAECgoKOwAbAKglAA==.Hills:BAAANQAECgEIAQAAAA==.',
Ho='Holyascended:BAAANQADCggIFgAAAA==.Holydarkness:BAAANQADCgYIBgAAAA==.Holykilla:BAAANQADCgUIBQAAAA==.Holykiller:BAAANQADCgEIAQAAAA==.Hoplite:BAAANQAECggIDQAAAA==.Hothots:BAAANQABCgYIBgABNQAECgYICAAQAAAAAA==.Howlly:BAABNQAECn8rAAIcAAoKNyH0BADPAgAcAAoKNyH0BADPAgAAAA==.',
Hr='Hraun:BAAANQADCgIIAQAAAA==.',
Hu='Hulner:BAAANQAECggIAgAAAA==.',
Ik='Ikeanola:BAABNQAECn8eAAISAAkKlgVF7QBBAQASAAkKlgVF7QBBAQAAAA==.',
Im='Imsosoft:BAAANQADCgEIAQAAAA==.',
In='Inapa:BAAANQAECgYIBgAAAA==.Indras:BAAANQADCgcIFQAAAA==.Ines:BAABNQAECn8lAAIaAAkKih+EEgD5AgAaAAkKih+EEgD5AgAAAA==.Inhume:BAAANQADCggJCQAAAA==.Innoruuk:BAAANQADCgEIAQAAAA==.Inter:BAAANQADCgIIAgAAAA==.',
Is='Ismarus:BAAANQAECgQIBQAAAA==.',
Ja='Jaarus:BAAANQAECgcIDgAAAA==.Jajal:BAABNQAECn8YAAIdAAkKCBH1JAAIAgAdAAkKCBH1JAAIAgABNQAECgoKFwAJABULAA==.Jankadish:BAABNQAECn8dAAQGAAkKUArrgABOAQAGAAgKtAjrgABOAQAFAAYKaAn3JwD/AAAYAAEKjQYXLgApAAAAAA==.Jaspirian:BAAANQADCgYIBgAAAA==.',
Je='Jehm:BAABNQAECn8lAAIWAAoKUQ7PUwClAQAWAAoKUQ7PUwClAQAAAA==.Jerome:BAAANQADCgMIBAAAAA==.',
Ju='Juiceboxer:BAAANQAECgQICAABNQAECgUICwAQAAAAAA==.Juicy:BAAANQADCgYIBgAAAA==.Justicehand:BAAANQAECgMIAgAAAA==.',
Ka='Kaestia:BAAANQAECgEIAQABNQAECgoKMAAcACEgAA==.Kagor:BAAANQADCgMIAwABNQAECgcIDgAQAAAAAA==.Kalia:BAABNQAECn8wAAMcAAoKISDOBADWAgAcAAkK0iDOBADWAgAMAAkKMBilvAALAgAAAA==.Kalipto:BAAANQADCgcICAAAAA==.Katatonik:BAAANQAECgUIBQABNQAECgcIDgAQAAAAAA==.Katharina:BAABNQAECn8aAAMZAAoKYxJ1YQD0AQAZAAoKYxJ1YQD0AQASAAEKAABAuAEsAAAAAA==.Katoume:BAABNQAECn8iAAMeAAoKJCS5AQA4AwAeAAoKJCS5AQA4AwAXAAEKLRytUQBUAAABNQAECgoKIgAeACQkAA==.Katoumey:BAAANQAECgYIEAABNQAECgoKIgAeACQkAA==.Kaulder:BAAANQADCgMIAwAAAA==.',
Kh='Khumfuu:BAAANQAECgQICQAAAA==.',
Ki='Kinan:BAABNQAECn85AAMVAAkKCSU2EAD2AgAEAAgKcCKyDAARAwAVAAkKCSU2EAD2AgAAAA==.',
Ko='Konan:BAAANQADCgMIAwAAAA==.Korlo:BAAANQAECgUIBwAAAA==.',
Ku='Kuala:BAAANQADCgIIAgAAAA==.',
Ky='Kythin:BAAANQAECgMICwABNQAECgoKMAAcACEgAA==.',
La='Lacutis:BAAANQADCggICQAAAA==.',
Le='Leonus:BAAANQADCgQIBAAAAA==.',
Li='Lichmcconnel:BAABNQAECn8tAAQDAAoKUBe0BQBgAgADAAoKUBe0BQBgAgACAAEKWAdjewAyAAABAAEKbQQgBwEuAAAAAA==.Lillica:BAAANQADCgQIBAAAAA==.Lilmeesh:BAAANQADCgQIBAAAAA==.Lisabeth:BAAANQAECgEIAQABNQAFFAgIFgAEAEYcAA==.',
Lo='Lockcuir:BAAANQADCgEIAQAAAA==.Lomponic:BAEBNQAECn8wAAIdAAoK/R00EQDoAgAdAAoK/R00EQDoAgAAAA==.Lore:BAACNQAFFH8KAAIfAAYKWxGkAwAJAQAfAAYKWxGkAwAJAQA1AAQKfzAAAh8ACgrWGWgZACkCAB8ACgrWGWgZACkCAAAA.',
Lu='Lunethra:BAABNQAECn8wAAIVAAoKEg6qawA8AgAVAAoKEg6qawA8AgAAAA==.Luukiss:BAAANQADCgQIBQAAAA==.Luyang:BAAANQADCgIIAgAAAA==.',
['Lü']='Lümen:BAAANQAECgIIBAAAAA==.',
Ma='Madcow:BAAANQADCgcIBwABNQAECggIHQAVAFAiAA==.Madhat:BAAANQAECggIDwAAAA==.Magerag:BAABNQAECn8lAAIMAAkKqCHCHgBdAwAMAAkKqCHCHgBdAwAAAA==.Malyc:BAAANQAECgQIBQAAAA==.',
Mc='Mcribz:BAACNQAFFH8IAAIgAAUKnBlnBgC4AQAgAAUKnBlnBgC4AQA1AAQKf0cAAiAACgrYJTsBAHUDACAACgrYJTsBAHUDAAAA.',
Me='Meap:BAAANQAECgQIBQAAAA==.Mecatank:BAAANQAECgEJAQAAAA==.Medra:BAAANQADCgEIAQAAAA==.Meelonusk:BAABNQAECn8XAAMCAAkK8Q4vMgD9AAABAAcKMgzYrwBxAQACAAQKpBAvMgD9AAAAAA==.',
Mi='Michaelcoyle:BAABNQAECn9AAAIVAAoKNCGOFQBGAwAVAAoKNCGOFQBGAwAAAA==.Milo:BAAANQAECgYICwAAAA==.Mitra:BAABNQAECn8oAAIRAAgK5xreAQAdAgARAAgK5xreAQAdAgAAAA==.',
Mo='Moesko:BAABNQAECn8dAAIhAAkKpByuGgDmAQAhAAkKpByuGgDmAQAAAA==.Mogianna:BAAANQADCgEIAQAAAA==.Monktup:BAAANQAECgEIAQAAAA==.Monkzo:BAAANQADCgcICAABNQAECgoKMQAbACgaAA==.Monnehbaggs:BAACNQAFFH8GAAIbAAYKQxw7DwCfAQAbAAYKQxw7DwCfAQA1AAQKf0sAAxsACgrVJH0AAPUDABsACgrVJH0AAPUDACIABQqeGnIHACABAAAA.',
Mu='Munchies:BAAANQADCgEIAQAAAA==.Murdersamich:BAAANQADCggJCQAAAA==.',
My='Myraghor:BAABNQAECn88AAIXAAoKUyAoBQBMAwAXAAoKUyAoBQBMAwAAAA==.',
Na='Nalmec:BAAANQADCgQIBAAAAA==.Naysayre:BAAANQABCgEIAQAAAA==.',
Ne='Nebody:BAAANQAECgEIAQAAAA==.Necriss:BAABNQAECn8zAAISAAgK4A/ErgDCAQASAAgK4A/ErgDCAQAAAA==.',
Ni='Nike:BAAANQAECggIEAAAAA==.',
No='Norni:BAAANQAECgcIEAAAAA==.Nowarning:BAAANQAECgQIBgAAAA==.',
Og='Oghom:BAAANQADCggIGQAAAA==.',
Op='Opeep:BAAANQAECgYICwAAAA==.',
Or='Ordestur:BAAANQADCggICAAAAA==.Oruum:BAAANQADCgYICAAAAA==.',
Os='Osos:BAAANQADCgQIBAAAAA==.',
Pa='Papachance:BAAANQAECgIIAgAAAA==.Papafrank:BAAANQAECgIIAgAAAA==.Papapump:BAABNQAECn8lAAIjAAoK6hzUDwBrAgAjAAoK6hzUDwBrAgAAAA==.Parlare:BAABNQAECn8hAAIhAAoKwxtjDgCdAgAhAAoKwxtjDgCdAgABNQAECgoKPAAbAKcfAA==.',
Pe='Perrinaya:BAAANQADCgQIBwAAAA==.',
Ph='Phoenixwing:BAAANQADCgYIDAAAAA==.',
Pi='Piedrita:BAAANQADCgMIAwAAAA==.Pinga:BAABNQAECn88AAMbAAoKpx/bGQDaAgAbAAoKCB/bGQDaAgAiAAYKMhoNCQDMAQAAAA==.',
Po='Portal:BAAANQADCgEIAQAAAA==.Poshifru:BAAANQAECgYIDwABNQABCgIIAgAQAAAAAA==.',
Pr='Preposition:BAABNQAECn8qAAIVAAoKWBahWABpAgAVAAoKWBahWABpAgAAAA==.',
Pu='Pussduty:BAABNQAECn8/AAIVAAoK5yJiEAD1AgAVAAoK5yJiEAD1AgAAAA==.',
Ra='Raaziel:BAAANQAECgcIDgAAAA==.Racknar:BAABNQAECn8UAAIVAAgKCAuyhQBkAQAVAAgKCAuyhQBkAQAAAA==.Rafìki:BAAANQAECgYIDgAAAA==.Raggnar:BAABNQAECn8mAAIPAAkKgSFOGwAmAwAPAAkKgSFOGwAmAwAAAA==.Ragingwaters:BAAANQADCgYIBgAAAA==.Ranvir:BAAANQADCggIGgAAAA==.Raun:BAABNQAECn89AAMSAAgKrSDZUQCgAgASAAgKrSDZUQCgAgAZAAYKIAabuAAMAQAAAA==.',
Re='Reactionhank:BAAANQAECgUJBQAAAA==.Relaire:BAABNQAECn8qAAIVAAgK7QofjABWAQAVAAgK7QofjABWAQAAAA==.',
Ri='Riku:BAABNQAECn8yAAIeAAgKGx80CgDvAQAeAAgKGx80CgDvAQAAAA==.',
Ro='Roots:BAABNQAECn8pAAILAAoKZyBjDQBfAwALAAoKZyBjDQBfAwAAAA==.',
Ru='Rumplfourskn:BAAANQADCgIIAgAAAA==.',
Ry='Ryveri:BAABNQAECn8kAAIGAAoKMhqgWgB8AgAGAAoKMhqgWgB8AgAAAA==.',
Sa='Sablehide:BAABNQAECn8sAAQkAAgK0hKYCQBAAQAlAAgKbA1uGQCyAQAkAAcK0hKYCQBAAQAmAAIKvA8cRgBxAAAAAA==.Salute:BAAANQAECgYIBgAAAA==.Sanaty:BAAANQAECgUIDgAAAA==.Saryn:BAAANQAECgMIAwAAAA==.Sathanus:BAAANQAECgIIAgAAAA==.Sazuna:BAAANQAECgUIBwAAAA==.Sazuni:BAAANQAECgYIEAAAAA==.',
Se='Secrett:BAAANQADCgcIDwAAAA==.',
Sh='Shadowreaper:BAAANQAECgUIBQAAAA==.Shelby:BAAANQADCgYICgAAAA==.Shortsighted:BAAANQAECggIDwABNQAFFAUICAAgAJwZAA==.Shoçknezz:BAAANQADCgYIDAAAAA==.',
Si='Silentsnake:BAEANQAECggIBwABNQAECgoKJAALAMETAA==.Silverwolf:BAABNQAECn8+AAIjAAoKLhk6CgBJAgAjAAoKLhk6CgBJAgAAAA==.Simplyunlock:BAABNQAECn8zAAMBAAoKwBMuewDzAQABAAkK/hIuewDzAQACAAQKbRHgNwDhAAAAAA==.Simplyvoided:BAAANQAECgIIAQAAAA==.Siphin:BAAANQAECggIAQAAAA==.Sizzlechop:BAABNQAECn8rAAIWAAgKoREJOgAxAQAWAAgKoREJOgAxAQAAAA==.Sizzlerocks:BAAANQADCgYIBgAAAA==.',
Sk='Skizzak:BAABNQAECn8fAAILAAkKmBSsHwDNAQALAAkKmBSsHwDNAQABNQAFFAUICAAgAJwZAA==.',
Sl='Slee:BAAANQAECgMIBwAAAA==.Slimedog:BAAANQAECgEIAQAAAA==.',
Sm='Smelvin:BAAANQAECgYIEQABNQAECgkJFwACAPEOAA==.',
Sn='Snailslolol:BAABNQAECn8yAAIZAAoKmxuzEgD6AgAZAAoKmxuzEgD6AgAAAA==.Snakes:BAEBNQAECn8fAAIWAAoKfxQ7JACuAQAWAAoKfxQ7JACuAQABNQAECgoKJAALAMETAA==.Sneaksatoke:BAAANQADCgMIAwAAAA==.',
So='Solåra:BAAANQADCgUIBQABNQAECgoKHgAIAKUPAA==.Songs:BAAANQADCgQIBQABNQADCgcIEQAQAAAAAA==.',
Sq='Squirtin:BAAANQAECgYIEwAAAA==.',
St='Stalath:BAAANQAECgIIAwAAAA==.Stormquota:BAABNQAECn8iAAIjAAoKiCFQAwAFAwAjAAoKiCFQAwAFAwABNQAECgoKLgAPADMiAA==.Stormwing:BAAANQAECgIIAQAAAA==.',
Su='Sumarr:BAAANQAECgcIBwAAAA==.',
Sv='Svenn:BAAANQADCggIDwAAAA==.',
Sw='Swiftstrike:BAAANQADCgYIBgAAAA==.',
Ta='Taboo:BAAANQAECgYIDAAAAA==.Talron:BAAANQADCgcIEQAAAA==.Tango:BAAANQAECgIIAQAAAA==.Tatertots:BAABNQAECn80AAIaAAkKlxiRJQDuAQAaAAkKlxiRJQDuAQAAAA==.',
Te='Tea:BAABNQAECn80AAIVAAoK6CA8GADDAgAVAAoK6CA8GADDAgAAAA==.Teach:BAAANQAFFAIIBAABNQAFFAMIBwAdAFsNAA==.Teilsande:BAAANQAECggIAQAAAA==.Teleportato:BAAANQAECgQIBAAAAA==.Templyn:BAABNQAECn8vAAMWAAoKRhCiIgC5AQAWAAoKRhCiIgC5AQAgAAEKAAAl5QAvAAAAAA==.',
Th='Thannos:BAAANQADCggIFAAAAA==.Theus:BAAANQADCgUICQAAAA==.Thyrus:BAABNQAECn82AAImAAoK3h3kDADXAgAmAAoK3h3kDADXAgABNQAECgoKPAAbAKcfAA==.',
Ti='Tirna:BAABNQAECn8zAAIMAAgK0hW5dACVAQAMAAgK0hW5dACVAQAAAA==.',
To='Tomsellock:BAAANQADCggIFQAAAA==.Tonytemplar:BAAANQABCgIIBQAAAA==.',
Tu='Tullen:BAEBNQAECn84AAIbAAgKNRFBawDcAQAbAAgKNRFBawDcAQAAAA==.Turanos:BAAANQAECgYICAAAAA==.Tutio:BAAANQADCgYIBgAAAA==.',
Ty='Tyindaris:BAAANQADCgUJCAAAAA==.',
['Té']='Témplýn:BAAANQAECgYIDAABNQAECgoKLwAWAEYQAA==.',
['Të']='Tëmplýn:BAAANQAECgEIAQABNQAECgoKLwAWAEYQAA==.Tëmplÿn:BAAANQAECgYIBgABNQAECgoKLwAWAEYQAA==.',
Ul='Ullr:BAAANQAECgEIAQAAAA==.Ultrachad:BAACNQAFFH8ZAAIWAAcKWyD9BAAqAgAWAAcKWyD9BAAqAgA1AAQKfzYAAhYACgreIoMIAPACABYACgreIoMIAPACAAAA.',
Un='Unggoy:BAACNQAFFH8WAAMEAAgKRhzmBwDMAQAEAAcKXhrmBwDMAQAVAAEK0CVLLgBlAAA1AAQKfyYAAwQACgqEJMQOAPcCAAQACgolJMQOAPcCABUAAQrrJjk9AWkAAAAA.Unholysin:BAAANQADCggIKwAAAA==.',
Ur='Urianna:BAAANQAECgYIBAAAAA==.',
Uw='Uwuther:BAAANQAECgQICQAAAA==.',
Va='Vaelthirion:BAAANQAECgEIAQAAAA==.Vahidamus:BAAANQAECgcIEAAAAA==.Valmirax:BAAANQADCgcICwAAAA==.Valton:BAAANQAECgIIAgAAAA==.Vaurix:BAAANQAECgQIDwAAAA==.',
Ve='Vezarion:BAAANQADCgUIBwAAAA==.',
Wa='Wafuzz:BAAANQAECgQIBAAAAA==.Waters:BAAANQADCgMIAwAAAA==.Waylen:BAAANQADCgEIAQAAAA==.',
We='Wesellpallys:BAAANQADCgUIBQABNQAECgkJFwACAPEOAA==.',
Wh='Whambamslam:BAAANQADCggICAAAAA==.',
Wi='Windhorn:BAAANQAECgEIAQAAAA==.Winds:BAAANQADCgcIEQAAAA==.Windtalker:BAAANQADCgQIBQABNQAECgUIBQAQAAAAAA==.',
Wo='Wolfen:BAAANQADCggICAAAAA==.Wolfquota:BAABNQAECn8uAAIPAAoKMyKbEQDBAgAPAAoKMyKbEQDBAgAAAA==.Wombaa:BAABNQAECn84AAMgAAoKbCX5CAB4AwAgAAkKiiX5CAB4AwAaAAoKZiN8BgAoAwAAAA==.',
Wr='Wrathdk:BAAANQAECgcIDgABNQAFFAIIAwAQAAAAAA==.Wrathm:BAAANQAFFAIIAwAAAA==.Wrathmo:BAABNQAECn8WAAMJAAgKOhBqMACUAQAJAAcKExJqMACUAQAKAAQKaweFJACtAAABNQAFFAIIAwAQAAAAAA==.Wrenkyian:BAAANQADCgUIBQAAAA==.',
Ya='Yani:BAAANQADCgYICwAAAA==.',
Ye='Yeah:BAAANQADCgEIAQAAAA==.',
Yo='Yoana:BAAANQADCgEIAQAAAA==.Yougotsniped:BAAANQADCgUIBQAAAA==.',
Za='Zakos:BAAANQADCggICAAAAA==.Zareeq:BAAANQADCgIIAgAAAA==.',
Zo='Zoa:BAAANQADCggIDAAAAA==.',
['Æs']='Æsir:BAAANQADCgEIAQAAAA==.',
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
