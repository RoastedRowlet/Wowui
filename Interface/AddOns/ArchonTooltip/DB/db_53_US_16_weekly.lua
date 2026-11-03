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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Druid-Restoration','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Hunter-Survival','Druid-Balance','DeathKnight-Frost','Paladin-Holy','Warrior-Arms','Warrior-Protection','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','Warlock-Destruction','Monk-Brewmaster','Mage-Frost','Mage-Arcane','Mage-Fire','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Rogue-Assassination','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','Warlock-Demonology','Warlock-Affliction','Shaman-Enhancement','DemonHunter-Devourer','Rogue-Outlaw','Druid-Feral','Druid-Guardian','DemonHunter-Havoc',}
local provider = {region='US',realm='Arathor',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abavok:BAAANQADCgcIBwAAAA==.Absoul:BAACNQAFFH8bAAIBAAUKmw8+EABkAQABAAUKmw8+EABkAQA1AAQKf1AAAgEACgqoGk04AIcCAAEACgqoGk04AIcCAAAA.Abuudd:BAAANQAECggIBwABNQAECgoKNAACAEggAA==.Abyssian:BAABNQAECn8kAAQBAAoKqwpNYgB9AQABAAoK8AlNYgB9AQADAAcK7APtFgDAAAACAAYKkgWyOQCaAAAAAA==.',
Ac='Acedia:BAABNQAECn8uAAIBAAkK4Rr7JgB/AgABAAkK4Rr7JgB/AgAAAA==.',
Ad='Adellas:BAABNQAECn9LAAIEAAoK8x0OCAAhAwAEAAoK8x0OCAAhAwAAAA==.Adern:BAABNQAECn9VAAICAAoKAh24DgAFAwACAAoKAh24DgAFAwAAAA==.Adon:BAAANQADCgUIBQABNQAECgYIDgAFAAAAAA==.Adonn:BAABNQAECn9BAAMGAAoKSByUQQAzAgAGAAoKSByUQQAzAgAHAAIKBgpAZwBGAAAAAA==.Adonshadriel:BAAANQAECgYIDgAAAA==.',
Ae='Aelali:BAABNQAECn8mAAIIAAoKFwlbBwAFAgAIAAoKFwlbBwAFAgAAAA==.',
Af='Afador:BAAANQADCggIEgABNQAECgcIEQAFAAAAAA==.',
Ag='Ageling:BAAANQADCgUIBQAAAA==.',
Al='Aladestar:BAACNQAFFH8PAAIJAAYKLhn9BwBNAQAJAAYKLhn9BwBNAQA1AAQKfzUAAwkACgqBHKElAKUCAAkACgqBHKElAKUCAAQABgpOFLw4AFgBAAAA.Albinodh:BAAANQAECgMIBAAAAA==.Alderleise:BAAANQADCgcIBwAAAA==.Alexein:BAACNQAFFH8SAAIKAAYKrwesCAAJAQAKAAYKrwesCAAJAQA1AAQKfzEAAgoACgq7GqcqAEYCAAoACgq7GqcqAEYCAAAA.',
Am='Amets:BAABNQAECn8lAAMLAAoKXhDTMAAqAgALAAoKXhDTMAAqAgAGAAQKZAxVOQHEAAAAAA==.Amorae:BAAANQADCggIDwAAAA==.',
An='Anabel:BAAANQAECgEIAQAAAA==.Anamii:BAAANQAECgYICQAAAA==.Andorsi:BAAANQAECgEIAQAAAA==.',
Ao='Aoratos:BAAANQAECgEIAQAAAA==.',
Ar='Arachne:BAABNQAECn8fAAICAAgKtgoaNgBzAQACAAgKtgoaNgBzAQAAAA==.Aracianluz:BAAANQAECggIDQAAAA==.Arak:BAAANQADCgIIAgAAAA==.Arce:BAAANQAECgQIBAABNQAECgoKNAAKABcWAA==.Arysia:BAAANQAECgUIBgAAAA==.Aryya:BAAANQADCgIIAgAAAA==.',
As='Ascaris:BAABNQAECn8VAAIMAAgK6BbVjgD3AQAMAAgK6BbVjgD3AQAAAA==.',
Av='Avalan:BAABNQAECn8+AAQMAAoKsh7xQgDBAgAMAAoKjx3xQgDBAgANAAYKjhu2GAClAQAOAAYKIxxaEQCPAQAAAA==.Avanolatwo:BAAANQADCgYIBgABNQAECgoKLwAPADUZAA==.Avashammy:BAABNQAECn8vAAMPAAoKNRlNLgCoAgAPAAoKNRlNLgCoAgAQAAYKyhCJlABxAQAAAA==.Aviendah:BAABNQAECn8iAAIRAAkKlwo1fQB4AQARAAkKlwo1fQB4AQAAAA==.',
Aw='Awsomeonet:BAAANQAECggICAAAAA==.',
Az='Azdfghop:BAACNQAFFH8PAAMSAAgKHA8mCgCgAQASAAcKCgwmCgCgAQARAAIKcx54IACxAAA1AAQKfyYAAxIACgrqIkAWAKkCABIACQqsIUAWAKkCABEAAgqUIykOAVwAAAAA.Azzinotica:BAAANQAECgUIBgAAAA==.',
Ba='Baalsanaro:BAAANQADCggIFQABNQAECgQIBQAFAAAAAA==.Babeshot:BAABNQAECn9EAAIRAAoKCg5MdAAoAgARAAoKCg5MdAAoAgAAAA==.Baelgar:BAAANQAECgMIAwAAAA==.',
Be='Bergur:BAAANQAECgMIBQABNQAECgoKPAATAKgjAA==.',
Bi='Bigbear:BAAANQADCggICAABNQAECgcIFgAUACQRAA==.Biggy:BAAANQADCgIIAgAAAA==.Bignose:BAABNQAECn8aAAMHAAoKSiZfAACTAwAHAAoKSiZfAACTAwAGAAEKAAD+nwEAAAABNQAFFAYIEwAVANomAA==.Binksy:BAAANQAECggICAAAAA==.',
Bl='Blaaze:BAAANQADCgYIBgAAAA==.Blackfrost:BAABNQAECn8WAAIWAAkKFg4HEQCWAQAWAAkKFg4HEQCWAQAAAA==.Blaiddyd:BAABNQAECn83AAIRAAkKQx3DQwCgAgARAAkKQx3DQwCgAgAAAA==.',
Bo='Bomi:BAAANQAECgEIAQAAAA==.Boogereater:BAAANQAECgMIAgABNQAECggIDgAFAAAAAA==.',
Br='Brandawn:BAAANQAECgUIDQAAAA==.Bred:BAAANQADCggICAAAAA==.',
Bu='Burndasheep:BAABNQAECn9AAAQXAAoKNxK3agCuAQAXAAoKGxK3agCuAQAWAAIK4xOyJACFAAAYAAEKew0ZDQA6AAAAAA==.',
['Bæ']='Bæyy:BAABNQAECn8bAAIXAAUKEgsH1ADXAAAXAAUKEgsH1ADXAAAAAA==.',
Ca='Calyris:BAAANQADCgIIBAAAAA==.Caspias:BAEANQADCggJEgAAAA==.Caylynn:BAAANQAECgQIAwAAAA==.Caynelin:BAAANQAECgEIAQAAAA==.',
Ce='Cestbusiness:BAAANQADCgUIBQAAAA==.',
Ch='Chaoslock:BAABNQAECn8WAAIUAAcKJBHQFgC2AQAUAAcKJBHQFgC2AQAAAA==.Chetter:BAAANQAECggIBgAAAA==.Chicknfajita:BAAANQAECgcICQABNQAECgoKHAAQAEcgAA==.Chickpea:BAAANQAECgMIBQAAAA==.',
Ci='Civilian:BAAANQAECgYIBgABNQAECgoKNAACAEggAA==.',
Co='Cocytus:BAAANQAECgIIAQAAAA==.Colbith:BAABNQAECn8YAAIJAAYKxA12YgBEAQAJAAYKxA12YgBEAQAAAA==.Corblixx:BAAANQAECgEIAQAAAA==.Cordaddy:BAAANQAECgYIBwABNQAECgkJLAAPANUlAA==.Cordelvo:BAAANQAECggIEAABNQAECgkJLAAPANUlAA==.Cordragon:BAAANQAECgIIBAABNQAECgkJLAAPANUlAA==.Cordragu:BAABNQAECn8sAAIPAAkK1SVEBACoAwAPAAkK1SVEBACoAwAAAA==.Cordran:BAAANQAECgEIAgABNQAECgkJLAAPANUlAA==.Corinthin:BAAANQADCgQIBAAAAA==.Corraa:BAAANQADCgEIAQAAAA==.',
Cr='Crakum:BAABNQAECn8XAAIQAAYKrRS0iwCHAQAQAAYKrRS0iwCHAQAAAA==.Crinn:BAABNQAECn8bAAMZAAcKDg3FagBnAQAZAAcKDg3FagBnAQAKAAIK3AN5owBHAAAAAA==.Crizmon:BAABNQAECn8eAAIKAAkKRx8MFQDkAgAKAAkKRx8MFQDkAgAAAA==.',
Cu='Cucumber:BAAANQAECgQIBAAAAA==.',
Da='Damorthyx:BAABNQAECn8bAAIaAAkKrQ/NVQCcAQAaAAkKrQ/NVQCcAQAAAA==.Darazarke:BAACNQAFFH8eAAMbAAcKmQ6JBQAOAgAbAAcKmQ6JBQAOAgAcAAEKLQVIDQA9AAA1AAQKfzIABBsACgqUGAcTAHwCABsACgqUGAcTAHwCAB0AAQqKFs8eAEgAABwAAQqCGIMXAEcAAAAA.Darkquill:BAABNQAECn8mAAIQAAoKOQ2LcwDGAQAQAAoKOQ2LcwDGAQAAAA==.Daspoof:BAAANQADCgYIBgAAAA==.Dayquil:BAEANQADCgcIBwABNQAFFAMIBgAGACUKAA==.',
De='Deadaddie:BAABNQAECn8ZAAMKAAkKMRx8LgAuAgAKAAkKMRx8LgAuAgAZAAEKZhdH1gBCAAABNQAECgoKOAAXAL4iAA==.Deamoneyes:BAAANQAECgQIBgAAAA==.Deathkauf:BAAANQAECgEIAQAAAA==.Deathvok:BAAANQADCgMIAwAAAA==.Demolitions:BAAANQAECggICAAAAA==.Dezatra:BAAANQADCgcIBgAAAA==.',
Dh='Dhonaan:BAAANQAECgMIAQAAAA==.',
Di='Dieselcon:BAACNQAFFH8GAAIHAAQKUgZOBwCXAAAHAAQKUgZOBwCXAAA1AAQKf0UAAwcACgqtFM4RAM8BAAcACgqtFM4RAM8BAAYABAr+BdRKAagAAAAA.Diprivan:BAABNQAECn8+AAMeAAoK+SDZEQDuAgAeAAoK9BzZEQDuAgAfAAkKER7mHABzAgAAAA==.',
Do='Dolobrik:BAAANQABCgYIBwAAAA==.Domdog:BAABNQAECn8dAAIXAAcKvgdJBQGFAQAXAAcKvgdJBQGFAQAAAA==.Domína:BAAANQAECgYICQAAAA==.Dontforget:BAAANQAECggIEwAAAA==.Doomdealer:BAABNQAECn8rAAMKAAoKShBtKgDOAQAKAAoKShBtKgDOAQAaAAEKAACKugBSAAAAAA==.Doomed:BAABNQAECn8eAAILAAgKtx9vJgDQAgALAAgKtx9vJgDQAgABNQAECggIHQAgAJAdAA==.Doonya:BAAANQAECgEIAgAAAA==.Dottee:BAAANQAECggIAwAAAA==.Dougwalker:BAAANQADCgIIAgAAAA==.',
Dr='Dracodaddy:BAAANQADCgIIAgAAAA==.Draftymonk:BAABNQAECn8XAAMVAAcKMR9QCgBxAgAVAAYK6SNQCgBxAgAhAAMKLBAwUQCuAAABNQAECgkJIAAaAAQgAA==.Drage:BAABNQAECn86AAMiAAoKAxf3NAANAgAiAAoKAxf3NAANAgAUAAEKdgMvhQAkAAAAAA==.Drax:BAABNQAECn8lAAMjAAoKcQp/DwBWAQAiAAoKCQiMogCQAQAjAAYKEwx/DwBWAQAAAA==.Dreadgar:BAAANQAECgQIBQABNQAECgoKJgAQAHEgAA==.Dritzzagain:BAAANQAECgUIDAAAAA==.Dritzzcat:BAAANQADCgYICwAAAA==.',
Dw='Dwreck:BAAANQAECgcIDgAAAA==.',
Ed='Ediann:BAAANQAECggIDgAAAA==.',
El='Elandrus:BAAANQAECgUICgABNQAECgkJKwAXAAkWAA==.Eldarine:BAAANQADCgUIBQAAAA==.Elishiveth:BAAANQAECgYIBgAAAA==.',
Em='Emmara:BAABNQAECn8jAAISAAoKVQPIKgDdAAASAAoKVQPIKgDdAAAAAA==.',
En='Enitar:BAAANQADCgcICAABNQAECgoKQAAXADcSAA==.',
Er='Erata:BAABNQAECn8hAAIjAAcKrgZWEQDUAAAjAAcKrgZWEQDUAAAAAA==.Erlik:BAAANQADCgMIBAAAAA==.Erzakzaktraz:BAAANQADCgYIBgABNQADCgcIBgAFAAAAAA==.',
Et='Etuba:BAAANQAECgEIAQAAAA==.',
Ev='Evullight:BAAANQADCgEJAQAAAA==.',
Ez='Ezlok:BAABNQAECn8mAAIQAAoKcSAaFwCOAgAQAAoKcSAaFwCOAgAAAA==.',
Fa='Facemash:BAAANQAECgQIBAABNQAECgoKQAAXADcSAA==.Fae:BAAANQABCgUIBQAAAA==.Faedra:BAAANQADCggIEwABNQABCgUIBQAFAAAAAA==.Faelyn:BAAANQADCgIIAgABNQABCgUIBQAFAAAAAA==.Falerin:BAABNQAECn8tAAIEAAoK4Rt0GAB7AgAEAAoK4Rt0GAB7AgAAAA==.Farryn:BAAANQADCgEIAQAAAA==.',
Fe='Feenex:BAABNQAECn8ZAAIZAAcKvA5xNAAjAQAZAAcKvA5xNAAjAQAAAA==.Feldora:BAAANQADCgYIBgAAAA==.Festiva:BAAANQAECgIIBAAAAA==.',
Fi='Fillorey:BAAANQADCggICAABNQAECgkJKwAXAAkWAA==.Firedealer:BAABNQAECn9BAAMSAAoKgBVaDgAqAgASAAoKgBVaDgAqAgARAAQKbxKN8gAcAQAAAA==.',
Fl='Flappy:BAAANQAECgIIBAABNQAECgkJNgAPACYbAA==.Flashmaster:BAAANQAFFAEIAQAAAA==.Flawlessheal:BAAANQADCgMIAwAAAA==.Fluffybutt:BAAANQADCggIFAAAAA==.',
Fo='Fossora:BAAANQADCgcIBgAAAA==.Foxygrandpa:BAAANQADCgUIBwAAAA==.',
Fr='Freyiah:BAAANQADCgYIBgAAAA==.',
Fy='Fyatre:BAAANQAECgYIDwAAAA==.',
Ga='Galadran:BAAANQABCgIIAgAAAA==.Galath:BAAANQAECgUJCAABNQAECgMIAwAFAAAAAA==.Gandallf:BAAANQADCgUIBQAAAA==.',
Ge='Gerree:BAAANQADCgYICgAAAA==.Gerry:BAABNQAECn8cAAIIAAoKchf2AgBjAgAIAAoKchf2AgBjAgABNQAECgoKOQAOAPIbAA==.',
Gg='Ggkando:BAABNQAECn8hAAIRAAYK+Q4NjQBUAQARAAYK+Q4NjQBUAQAAAA==.',
Gh='Ghemaldir:BAAANQABCgIIAgAAAA==.',
Gi='Gildius:BAAANQADCgIIAgAAAA==.Gingerail:BAAANQAECgQICQAAAA==.',
Gl='Glory:BAABNQAECn8mAAIaAAoK6Rw9IwCdAgAaAAoK6Rw9IwCdAgAAAA==.',
Gn='Gnayami:BAAANQADCgcIDwAAAA==.',
Go='Goochsquirts:BAABNQAECn8fAAIPAAgKRxsOUAAlAgAPAAgKRxsOUAAlAgAAAA==.Govna:BAAANQADCggIFAAAAA==.',
Gr='Grakkaem:BAAANQAECgMIBAAAAA==.Grannet:BAAANQADCgMIBQAAAA==.Gravedygger:BAABNQAECn9FAAIRAAoKqBcqOQA0AgARAAoKqBcqOQA0AgAAAA==.Greenfear:BAAANQADCgYIDAAAAA==.Grenswood:BAAANQAECgcIEgAAAA==.Greybeeredd:BAAANQAECgIIBAAAAA==.Grimmkin:BAABNQAECn8sAAQkAAoKOxpKCwC8AgAkAAoKOxpKCwC8AgAPAAIKrA8e/gBuAAAQAAEKAACtQwEsAAAAAA==.Grind:BAAANQAECgQIBAABNQAECgcIEQAFAAAAAA==.Growl:BAAANQAECgEIAgAAAA==.Grumbo:BAAANQADCgcIBgAAAA==.',
Gu='Gunnerr:BAAANQAECgEIAQABNQAECgEIAQAFAAAAAA==.Guuldurak:BAAANQADCgcIBgAAAA==.',
Ha='Hailcat:BAAANQAECgMIBAABNQAECgoKJAAiAC0PAA==.Handivhe:BAAANQADCgYIBgAAAA==.Hasew:BAABNQAECn9LAAIRAAoKKCJkFwDIAgARAAoKKCJkFwDIAgAAAA==.',
He='He:BAAANQAECgcIDwABNQAECgoKNAAKABcWAA==.Hellanor:BAAANQABCgUICQAAAA==.Helpimßlind:BAABNQAECn8jAAIlAAoKfxeyEQASAgAlAAoKfxeyEQASAgAAAA==.Hera:BAACNQAFFH8TAAIRAAYKTCRIAwCmAQARAAYKTCRIAwCmAQA1AAQKfzQAAhEACgq2Jh4EAMcDABEACgq2Jh4EAMcDAAAA.Heyner:BAABNQAECn9HAAImAAoKeh30AACtAgAmAAoKeh30AACtAgAAAA==.',
Hi='Hinral:BAACNQAFFH8TAAIgAAYKdhggAgDkAQAgAAYKdhggAgDkAQA1AAQKfzcAAiAACgoyJKACAJMDACAACgoyJKACAJMDAAAA.Hiya:BAAANQADCgIIAgABNQAECgoKNAAKABcWAA==.',
Ho='Holyiaa:BAAANQAECggIDQABNQAECgYIEAAFAAAAAA==.Holyluz:BAAANQAECgYICgABNQAECggIDQAFAAAAAA==.Holysmacker:BAAANQAECgUIBQABNQAECggIHQAWAC0ZAA==.',
Hy='Hymns:BAAANQAECggIAgAAAA==.',
['Hë']='Hëll:BAABNQAECn8kAAMiAAoKLQ9acwAHAgAiAAoKLQ9acwAHAgAUAAEKGRC/cwA7AAAAAA==.',
Il='Illaynne:BAABNQAECn8yAAIBAAkKphhrNgAuAgABAAkKphhrNgAuAgAAAA==.',
Im='Imani:BAACNQAFFH8SAAIkAAUKqQIOBAC6AAAkAAUKqQIOBAC6AAA1AAQKfzQAAiQACgqeDRgVABcCACQACgqeDRgVABcCAAAA.Immensepain:BAAANQAECgUIBAAAAA==.',
In='Inoshikacho:BAABNQAECn8uAAInAAoKSgylEABtAQAnAAoKSgylEABtAQAAAA==.Involio:BAAANQAECgEIAQAAAA==.',
Ir='Irishmecha:BAACNQAFFH8UAAIeAAYKIBF2AgA1AQAeAAYKIBF2AgA1AQA1AAQKfzQAAh4ACgrEIcMKAAACAB4ACgrEIcMKAAACAAAA.Irishpaws:BAAANQAECgEIAQAAAA==.Ironshot:BAAANQADCggIBgAAAA==.',
Is='Isaeus:BAAANQAECgEIAQAAAA==.',
It='Itharillys:BAABNQAECn8pAAIRAAoK6BLrcwAoAgARAAoK6BLrcwAoAgAAAA==.',
Ja='Jaadu:BAAANQADCgQIBAAAAA==.Jangus:BAABNQAECn8ZAAIdAAYK4RHIDgAiAQAdAAYK4RHIDgAiAQABNQAECgcIEQAFAAAAAA==.Jaybone:BAAANQAECgIIAQAAAA==.',
Je='Jeefus:BAAANQAECggIAgAAAA==.Jeennkiins:BAAANQADCgYIBgABNQAECgYICQAFAAAAAA==.Jenifur:BAAANQAECgIIAwABNQABCgUIBQAFAAAAAA==.Jessibella:BAAANQADCgQIBAAAAA==.Jezzako:BAAANQAECgcICwAAAA==.',
Ji='Jinx:BAAANQADCggIEgABNQABCgUIBQAFAAAAAA==.',
Jo='Johali:BAAANQAECggIEgAAAA==.Jozan:BAAANQADCgcIHwAAAA==.',
Ju='Justise:BAAANQADCgIIAgABNQADCgYJCwAFAAAAAA==.Jutojerry:BAABNQAECn8dAAIgAAgKkB11BwDIAgAgAAgKkB11BwDIAgAAAA==.',
Jz='Jz:BAAANQAECgYIBgABNQAECgoKNAAKABcWAA==.',
['Jö']='Jöhnblaze:BAABNQAECn9FAAMMAAoKIRIDSQD1AQAMAAoKIRIDSQD1AQANAAcKKg2RFwAXAQAAAA==.',
Ka='Kaga:BAAANQADCgEJAQABNQAECgoKQAAXADcSAA==.Kailys:BAABNQAECn8vAAIHAAoKUxDKIADeAQAHAAoKUxDKIADeAQAAAA==.Kaisana:BAAANQAECgYICwAAAA==.Kaishias:BAABNQAECn8wAAMHAAkKaxg2EgDJAQAGAAkKaxgsUgAAAgAHAAgKaxU2EgDJAQAAAA==.Kaldrek:BAAANQAECgMIBgABNQAECgoKIAAGAJYWAA==.Kandoh:BAAANQADCggIEwABNQAECgYIIQARAPkOAA==.Kanimeh:BAAANQADCgcICQAAAA==.Kankuró:BAACNQAFFH8GAAIRAAIKnBkFHACZAAARAAIKnBkFHACZAAA1AAQKf0EAAhEACgomIX4TAN8CABEACgomIX4TAN8CAAAA.Karelleira:BAAANQADCgUIBQAAAA==.Kautie:BAABNQAECn8cAAILAAoKJR3EDAA9AwALAAoKJR3EDAA9AwAAAA==.',
Ki='Killahmike:BAAANQAECgQIBgAAAA==.Killudead:BAABNQAECn8YAAIGAAoK/heIOQBRAgAGAAoK/heIOQBRAgAAAA==.Kishana:BAAANQADCgcIBgAAAA==.',
Ko='Kodetra:BAABNQAECn8eAAIcAAgKMwzpCgAdAQAcAAgKMwzpCgAdAQAAAA==.Kolgrim:BAABNQAECn8xAAMaAAoKAB0YDQCqAgAaAAoKAB0YDQCqAgAKAAkKaw66PQDVAQAAAA==.Kong:BAAANQAECgIIAgAAAA==.Korvuk:BAABNQAECn8gAAMGAAoKlhZ+QQAzAgAGAAoKlhZ+QQAzAgALAAcKThEHcAAzAQAAAA==.',
Kr='Kristafur:BAAANQADCggIDgABNQABCgUIBQAFAAAAAA==.Krom:BAABNQAECn8mAAMQAAoKbwsCpwBGAQAQAAcKbQ8CpwBGAQAPAAkK/wXGjQDcAAAAAA==.Krysta:BAABNQAECn89AAMBAAoKeCAGFQADAwABAAoKeCAGFQADAwACAAEKAACegQAoAAABNQABCgUIBQAFAAAAAA==.',
Ky='Kynris:BAAANQADCggIEQABNQAECgkJKwAXAAkWAA==.',
La='Lanaal:BAAANQADCgEIAQAAAA==.Lancewh:BAAANQADCgcIDAAAAA==.Lanciwinluna:BAAANQADCgQIBAAAAA==.Lancywinelia:BAAANQADCgQIBgAAAA==.Lauryssa:BAAANQADCggICAAAAA==.',
Ld='Ldydthstryke:BAAANQAECgYIBgABNQAECgoKQQASAIAVAA==.',
Le='Legg:BAAANQABCgMIAwAAAA==.Legolâs:BAAANQADCgUIBQAAAA==.Leonora:BAABNQAECn8WAAISAAgK8wSWQABQAQASAAgK8wSWQABQAQAAAA==.Leviathañ:BAAANQADCgIIAgABNQAECgcIDgAFAAAAAA==.Lezene:BAAANQAECgUIBwAAAA==.',
Li='Linstriker:BAABNQAECn8uAAIoAAkKhiFkCgDKAgAoAAkKhiFkCgDKAgABNQAFFAcIFQAPANEeAA==.',
Lo='Lockbone:BAAANQAECgIIAQAAAA==.Lorette:BAABNQAECn88AAMBAAoK3B9qEQAkAwABAAoK3B9qEQAkAwACAAoKBBs9FwCyAQAAAA==.',
Lu='Lucethegoose:BAAANQADCgQIBAAAAA==.Luckynyx:BAAANQAECgUIBQAAAA==.Lunate:BAAANQAECgEIAQABNQAECgoKNAACAEggAA==.',
Ma='Machotedan:BAABNQAECn9CAAIGAAoKMyIeGADpAgAGAAoKMyIeGADpAgAAAA==.Macmittens:BAAANQAECggICAAAAA==.Makoes:BAAANQADCgYIBgAAAA==.Mamadrag:BAAANQAECgYIEAAAAA==.Managua:BAAANQADCgEIAQAAAA==.Mandwa:BAAANQADCggIGAABNQAECgoKQAAXADcSAA==.Mangojuulpod:BAAANQAECgMIAwABNQAECggIHQAgAJAdAA==.Mario:BAABNQAECn8dAAIWAAgKLRlmDgDEAQAWAAgKLRlmDgDEAQAAAA==.Mastashifta:BAAANQAECgUIDAAAAA==.Mataa:BAABNQAECn8rAAIXAAkKCRZM0ADlAQAXAAkKCRZM0ADlAQAAAA==.Matryoshka:BAAANQADCgUIDQABNQAECgEIAgAFAAAAAA==.Mattsadler:BAAANQAECgIIAQAAAA==.Maxxim:BAAANQAECgIIAgAAAA==.Mayihmpurleg:BAAANQAECgUIBQABNQAECgoKQQASAIAVAA==.Mazeman:BAAANQADCgUIBQAAAA==.',
Me='Meilin:BAAANQAECgMIAwAAAA==.Mellachion:BAAANQAECgYICAABNQAECggIHQAWAC0ZAA==.Meta:BAABNQAECn8ZAAIpAAoKkBMeKgB/AQApAAoKkBMeKgB/AQABNQAECgoKPgAeAPkgAA==.',
Mi='Mistaya:BAAANQADCgUIBQABNQAECgkJIQAiAKYIAA==.Mists:BAABNQAFFH8FAAMiAAUK4BHIFwA2AQAiAAQKABjIFwA2AQAUAAEKoAUQIgBFAAAAAA==.Miththrawndo:BAABNQAECn8vAAIaAAoKHQ4LVACkAQAaAAoKHQ4LVACkAQABNQAFFAQIBgAHAFIGAA==.',
Mo='Momjeans:BAABNQAECn80AAIXAAoK0x1EOgA8AgAXAAoK0x1EOgA8AgAAAA==.',
Mu='Mumbo:BAAANQADCgcIBwABNQAECgcIEQAFAAAAAA==.Muu:BAAANQADCgYICAAAAA==.',
My='Mydaan:BAAANQADCgIIAwAAAA==.Mythunsarian:BAABNQAECn8gAAIpAAkKCQzALgBgAQApAAkKCQzALgBgAQAAAA==.',
['Má']='Mákï:BAABNQAECn8aAAIMAAgKNBCHkQDwAQAMAAgKNBCHkQDwAQAAAA==.',
['Mä']='Mäylä:BAABNQAECn8oAAMJAAoKnwxDSgC+AQAJAAoKnwxDSgC+AQAEAAEKlA79awAqAAAAAA==.',
['Mí']='Míst:BAABNQAECn9FAAIGAAoK4RjpXgB8AgAGAAoK4RjpXgB8AgAAAA==.',
Na='Narlis:BAABNQAECn8vAAIZAAoKLCM7CgBrAwAZAAoKLCM7CgBrAwAAAA==.Nautprepared:BAAANQAECgMIAQABNQAECggIHQAgAJAdAA==.',
Ne='Nephie:BAAANQAECgYICwAAAA==.Nezqk:BAACNQAFFH8RAAQKAAYK+gwRCAAVAQAKAAUK8AwRCAAVAQAZAAIKlxHyFwCaAAAaAAEKAADqLAAAAAA1AAQKfzAABBkACgqgG/cyAF8CABkACQpuHPcyAF8CABoACAqQEvZOALkBAAoABwr0Fk1AAFsBAAAA.Nezquick:BAAANQAECgIIAgAAAA==.',
Ni='Niano:BAAANQABCgIIAgAAAA==.',
Nm='Nmnenthe:BAABNQAECn8kAAIdAAgKXBdxCgCMAQAdAAgKXBdxCgCMAQAAAA==.',
No='Notrealword:BAAANQAECgcIEAABNQAECgoKSwARACgiAA==.Noxluminous:BAAANQABCgIIAgAAAA==.',
Ob='Obin:BAABNQAECn8rAAMMAAkK9xD8cwBuAQAMAAgKQA/8cwBuAQAOAAcKaA+3GgD6AAAAAA==.',
Oc='Occasionally:BAAANQAECgIIAgAAAA==.',
Ok='Okukoy:BAAANQABCgEIAQAAAA==.',
Om='Ominious:BAABNQAECn8oAAMkAAoKvxIuFAAmAgAkAAkKJxEuFAAmAgAQAAUKtRcBqgBAAQABNQAECggIEAAFAAAAAA==.Omnissia:BAAANQAECgUIAwABNQAECggIEAAFAAAAAA==.Omnius:BAABNQAECn8fAAMQAAoKMhxeYAAAAgAQAAoKMhxeYAAAAgAPAAEKMAu9KQEkAAAAAA==.Omnya:BAAANQAECgcIDQABNQAECggIEAAFAAAAAA==.Omnyi:BAAANQAECggIEAAAAA==.',
Ow='Owendriel:BAACNQAFFH8LAAIlAAUKNQwxCADIAAAlAAUKNQwxCADIAAA1AAQKfxkAAyUACgq9FR0oAAMCACUACQpiFB0oAAMCACkAAwrpEglxALUAAAAA.',
Pa='Paindya:BAAANQAECggIEwAAAA==.Paleigh:BAAANQABCgYICwAAAA==.Palivok:BAAANQAECgYIBwAAAA==.Pandress:BAABNQAECn8ZAAIRAAgKjgxYxwBzAQARAAgKjgxYxwBzAQAAAA==.Pankake:BAAANQAECgQIBAABNQAECgoKPAATAKgjAA==.Paralysis:BAACNQAFFH8TAAIlAAYKYhLXAwAuAQAlAAYKYhLXAwAuAQA1AAQKfzMAAiUACgq1HSEeAGACACUACgq1HSEeAGACAAAA.Parody:BAAANQAECgEIAQABNQAECgIIBAAFAAAAAA==.',
Pe='Peetza:BAAANQADCgYIBgABNQAECgoKPAATAKgjAA==.Peryite:BAABNQAECn9DAAMBAAoK6BnqLwBPAgABAAoK6BnqLwBPAgADAAQK6xBhFQDUAAAAAA==.',
Ph='Phaedrana:BAAANQAECgcIDgAAAA==.',
Pi='Pisscat:BAABNQAECn8ZAAIoAAcKhQLjRAB5AAAoAAcKhQLjRAB5AAAAAA==.Pixsil:BAAANQADCgQIBAAAAA==.',
Po='Pocketdragon:BAABNQAECn8tAAMdAAoKZxUhDwBpAgAdAAoKchQhDwBpAgAcAAYKWhBOEAA1AQAAAA==.',
Pr='Prideindeath:BAAANQAECgYICQAAAA==.Promiscuity:BAABNQAECn8wAAMiAAoKaxobIABuAgAiAAoKaxobIABuAgAjAAIKwwlCIgBpAAABNQAECgoKPgAeAPkgAA==.Prængle:BAAANQADCgYIAwAAAA==.',
Ps='Psoas:BAABNQAECn80AAMCAAoKSCAnCABaAwACAAoKSCAnCABaAwABAAIK4BBH5AB7AAAAAA==.Psypriest:BAECNQAFFH8IAAIBAAMKgxeTGQDrAAABAAMKgxeTGQDrAAA1AAQKfzkAAgEACgrWIA0OAEYDAAEACgrWIA0OAEYDAAE1AAUUCAgiAAEAXA4A.',
Py='Pyroheal:BAAANQAECggICwAAAA==.',
Qu='Quaichang:BAAANQADCgYIBgAAAA==.',
Ra='Rabbi:BAABNQAECn82AAMCAAoKVxnkEgDTAgACAAkKJBvkEgDTAgABAAMKiiAmgQAaAQAAAA==.Rahfna:BAAANQADCgcIDwAAAA==.Railænu:BAAANQADCggIDgAAAA==.Rainmist:BAAANQAECgUIBgAAAA==.Ranric:BAAANQAECgMIAwAAAA==.',
Re='Redall:BAAANQAECgIIAgAAAA==.Reesespbc:BAAANQAECgYIDQAAAA==.Reina:BAAANQAECggIDgABNQABCgUIBQAFAAAAAA==.Reinz:BAABNQAECn8aAAMVAAoKoiJcAQAkAwAVAAoKoiJcAQAkAwAhAAIKmQntXgBkAAAAAA==.Rektagar:BAABNQAECn84AAMQAAoKcCTUBQC8AwAQAAoKcCTUBQC8AwAPAAEKbwuB4wAyAAABNQAFFAcIHAARAKAhAA==.Ressandra:BAAANQADCgMIBgAAAA==.Rezo:BAAANQAECgEIAgAAAA==.',
Ri='Riverarose:BAAANQADCggIFQAAAA==.',
Ro='Roar:BAAANQAECgYIEgABNQAECgcIEQAFAAAAAA==.',
Ry='Rysi:BAAANQADCgQIBAAAAA==.',
['Rò']='Ròs:BAACNQAFFH8VAAIHAAYKfxiuAgA7AQAHAAYKfxiuAgA7AQA1AAQKfzQAAgcACgrCIUcKAPYCAAcACgrCIUcKAPYCAAAA.',
['Rö']='Rös:BAAANQADCgEIAQABNQAFFAYIFQAHAH8YAA==.',
Sa='Saberie:BAAANQADCggIFwABNQADCgMIBgAFAAAAAA==.Salaria:BAABNQAECn8mAAIlAAkKdA/5MwCjAQAlAAkKdA/5MwCjAQAAAA==.Salina:BAEBNQAECn8WAAITAAgKJBV5EACqAQATAAgKJBV5EACqAQAAAA==.Sandstique:BAABNQAECn8xAAIPAAoKZyQpEwAxAwAPAAoKZyQpEwAxAwAAAA==.Sandweaver:BAAANQADCgcIBwAAAA==.Sanjira:BAAANQADCgYIBgAAAA==.Sarlak:BAABNQAECn80AAMRAAoKHh05JQACAwARAAoKHh05JQACAwASAAEK8AYalwAqAAAAAA==.Sarusuby:BAABNQAECn9PAAIoAAoKzBE/GQCEAQAoAAoKzBE/GQCEAQAAAA==.Satae:BAABNQAECn88AAITAAoKqCOBAgBZAwATAAoKqCOBAgBZAwAAAA==.',
Sc='Schufft:BAABNQAECn8aAAIUAAcKzBuCCAB1AgAUAAcKzBuCCAB1AgAAAA==.Scottydh:BAAANQAECgIIAgABNQAECgoKQQAaAKwgAA==.Scottymac:BAABNQAECn9BAAIaAAoKrCBIDwA0AwAaAAoKrCBIDwA0AwAAAA==.Scottypal:BAAANQAECgQIBQABNQAECgoKQQAaAKwgAA==.',
Se='Seatah:BAAANQAECgMIAwAAAA==.Seba:BAABNQAECn8jAAIQAAgKcBY0TABGAgAQAAgKcBY0TABGAgAAAA==.Seetah:BAABNQAECn8kAAMBAAoKuhNvWQAVAgABAAoKuhNvWQAVAgACAAIK6wyOZwBiAAAAAA==.Seraphtharia:BAAANQABCgIIAgAAAA==.Sermon:BAAANQADCgQIBAABNQAECgcIEQAFAAAAAA==.',
Sh='Shadaddy:BAABNQAECn84AAMXAAoKviIZUgDcAgAXAAkKoyIZUgDcAgAWAAMKNyALHwDyAAAAAA==.Shadowheart:BAAANQAECgQIBQAAAA==.Shakasana:BAAANQAECgIIAQAAAA==.Shal:BAABNQAECn8sAAIMAAkKlxlQXACxAQAMAAkKlxlQXACxAQAAAA==.Shamanluz:BAAANQADCgIIAgABNQAECggIDQAFAAAAAA==.Shamommy:BAAANQADCgUIBAAAAA==.Shamtaz:BAAANQAECgUICgAAAA==.Shimmerstar:BAABNQAECn8cAAIGAAkKYR0pcQBNAgAGAAkKYR0pcQBNAgAAAA==.Shroomgirl:BAAANQAECgUIBQAAAA==.Shrubhub:BAAANQAECgEIAQABNQAECggIHQAgAJAdAA==.',
Si='Silexe:BAABNQAECn8mAAMdAAgKiBQxDQBFAQAcAAcKaRRsDQB3AQAdAAYK8hQxDQBFAQAAAA==.Sitga:BAAANQADCgIIAgAAAA==.',
Sk='Skåld:BAAANQADCgUIAwAAAA==.',
Sl='Slinga:BAAANQADCgcICQAAAA==.Slipperyboi:BAAANQAECgQICQAAAA==.Slÿ:BAAANQAECgIIAgAAAA==.',
So='Solarion:BAAANQAECgYIDwABNQAECgoKJgAQAHEgAA==.Soldraca:BAAANQAECgMIAwAAAA==.',
St='Stabbirabbi:BAAANQAECgQIAgAAAA==.Stats:BAAANQAECgcIEQAAAA==.Stinkbug:BAAANQADCgQIBAAAAA==.Stutters:BAABNQAECn9BAAMZAAoKVyCgCQC8AgAaAAoKrRz8FgD1AgAZAAoKmh6gCQC8AgAAAA==.',
Su='Subayyru:BAAANQADCgEIAQABNQAECgUIGwAXABILAA==.Sudachi:BAAANQADCgYIBgABNQAFFAcKFAAhACscAA==.Sunnyräy:BAAANQAECgMIAwAAAA==.Superiorkill:BAAANQADCgcIBwAAAA==.Suthrheimr:BAABNQAECn85AAIOAAoK8hsVBQBcAgAOAAoK8hsVBQBcAgAAAA==.',
Sy='Symphany:BAAANQABCggIEQAAAA==.',
['Sý']='Sýndrá:BAAANQAECgYIDQAAAA==.',
Ta='Talespin:BAAANQAECgUIBQAAAA==.Talysiah:BAABNQAECn8hAAIiAAkKpgg7cABOAQAiAAkKpgg7cABOAQAAAA==.Tavok:BAABNQAECn8vAAIOAAkK/hxbBgCnAgAOAAkK/hxbBgCnAgAAAA==.Tazbis:BAAANQAECgQIBgAAAA==.',
Te='Teishuku:BAABNQAECn9MAAIGAAoKQRPIXADhAQAGAAoKQRPIXADhAQAAAA==.Teusday:BAABNQAECn80AAMKAAoKFxbhOADxAQAKAAoKFxbhOADxAQAaAAQKRga5cABuAAAAAA==.',
Th='Thiux:BAABNQAECn81AAMiAAoKNSAkIgBjAgAiAAkKiiAkIgBjAgAUAAIKYB9vRACzAAAAAA==.Thoeleden:BAAANQAECgMIBgABNQAFFAcIFQAPANEeAA==.Thotsnprayrs:BAAANQAECgMIBgABNQAECggIHQAgAJAdAA==.Thrappy:BAABNQAECn82AAMPAAkKJhseRgBJAgAPAAkKJhseRgBJAgAQAAcK1w9hogBRAQAAAA==.Thryna:BAAANQADCgEIAQAAAA==.Thugstyle:BAAANQABCgcIDgAAAA==.',
Ti='Tinsoon:BAAANQAECgUIBQAAAA==.Tintaglia:BAABNQAECn9AAAMiAAoKshmcKQA+AgAiAAoKshmcKQA+AgAjAAEKZBHPMQAxAAABNQAECggIHQAWAC0ZAA==.Tirtun:BAABNQAECn9MAAIWAAoK4CA9AgBQAwAWAAoK4CA9AgBQAwAAAA==.',
Tr='Triggeer:BAABNQAECn8oAAINAAkK9BfiDACxAQANAAkK9BfiDACxAQAAAA==.Trolldemort:BAAANQADCgYIBgABNQAECgoKJAAiAOMVAA==.',
Tu='Tully:BAABNQAECn8eAAIRAAUKVQNd5QCmAAARAAUKVQNd5QCmAAAAAA==.Tunkhan:BAAANQADCgQIBwAAAA==.Turnaround:BAAANQABCgIIAgAAAA==.',
Tw='Twelvekill:BAACNQAFFH8TAAIRAAYKPhPDBgBSAQARAAYKPhPDBgBSAQA1AAQKfzEAAhEACgpgIa4nAPkCABEACgpgIa4nAPkCAAAA.',
Ty='Tyliaa:BAABNQAECn8/AAMPAAoKkBpcLwCkAgAPAAoKkBpcLwCkAgAQAAkKtxBoQQCUAQABNQAECgYIEAAFAAAAAA==.',
Ul='Ultramon:BAABNQAECn8iAAIGAAoKtBKygwAgAgAGAAoKtBKygwAgAgAAAA==.',
Un='Unbreakabull:BAAANQAECgEIAQAAAA==.Unwell:BAABNQAECn8rAAIlAAoK7RiAEQAVAgAlAAoK7RiAEQAVAgAAAA==.',
Ur='Urgoochness:BAAANQADCgQIBAAAAA==.Urikhai:BAAANQADCggIAgAAAA==.',
Va='Vainglorious:BAAANQADCggIEwABNQAECgoKJgAaAOkcAA==.Valanora:BAABNQAECn88AAIjAAoKUxVXBQDxAQAjAAoKUxVXBQDxAQAAAA==.Valerie:BAAANQAECggICwABNQAECgoKPwASAH4fAA==.Valianya:BAAANQABCgMIAwAAAA==.Valinaxius:BAAANQAECgYIDAAAAA==.Vanyr:BAAANQADCggICgAAAA==.Vapturov:BAAANQAECgUIDAAAAA==.',
Ve='Veeks:BAABNQAECn9AAAIQAAoKaAz0PAClAQAQAAoKaAz0PAClAQAAAA==.Velibast:BAAANQAECgQIBAAAAA==.Velikirn:BAABNQAECn8uAAMhAAoKLCB2BwDXAgAhAAkKLCB2BwDXAgAVAAkKKRZPDwD8AQAAAA==.Velimald:BAAANQAECgQIBAAAAA==.Velydia:BAAANQAECgYIBgAAAA==.Venefica:BAAANQAECgEIBAAAAA==.Verdracee:BAAANQABCgMIAwABNQAECgYIHAATAJ0EAA==.Versø:BAABNQAECn8eAAMeAAgK/BRhPgDVAQAeAAgK/BRhPgDVAQAfAAEKAAAiUwA1AAAAAA==.Veryzi:BAAANQAECgEIAgAAAA==.',
Vi='Vine:BAAANQADCgQIBQABNQAECgoKPgAeAPkgAA==.',
Vl='Vlyrae:BAAANQADCgMIAwAAAA==.',
Vo='Voidbreaker:BAAANQADCgcIBwAAAA==.Voidhearted:BAABNQAECn9NAAICAAoKGxBGIwAYAgACAAoKGxBGIwAYAgAAAA==.Vonzuo:BAAANQAECgIIAgAAAA==.',
Vu='Vukodlak:BAAANQADCgcIDQABNQAECggIHQAWAC0ZAA==.',
['Vì']='Vìolet:BAAANQADCgMIAwABNQAECgkJNAAJALAfAA==.',
Wa='Warriorwuu:BAAANQABCgIIAgAAAA==.Wayshua:BAAANQADCgYIBgAAAA==.',
We='Werkajerk:BAAANQADCggICAABNQAFFAcIFQAPANEeAA==.Werkjathal:BAACNQAFFH8VAAIPAAcK0R53BgD8AQAPAAcK0R53BgD8AQA1AAQKfzYAAw8ACgpwJjkBANcDAA8ACgpwJjkBANcDABAABgq4Hwo1AMkBAAAA.',
Wi='Wibbles:BAAANQADCgcICwAAAA==.Wigarthan:BAAANQADCgEIAQAAAA==.Wildsenpai:BAAANQADCgEIAgAAAA==.',
Wo='Wolfblitzer:BAABNQAECn81AAMGAAoKoxbPXADhAQAGAAoKoxbPXADhAQALAAYKyQLHnQC6AAAAAA==.Wolfmanbro:BAAANQADCgMIAwAAAA==.Wolfpride:BAAANQADCgUIBQAAAA==.Worgenator:BAAANQADCgMIAwAAAA==.Worldbane:BAABNQAECn8oAAIUAAoKJA5HBgBMAQAUAAoKJA5HBgBMAQAAAA==.',
Wr='Wraithlash:BAAANQAECggIDgAAAA==.',
Wu='Wuu:BAAANQABCgIIAgAAAA==.Wuulock:BAAANQABCgEJAQAAAA==.',
Wy='Wynnhrt:BAAANQADCggICAAAAA==.',
Xa='Xalatath:BAABNQAECn8wAAMBAAoKJRxUEQAlAwABAAoKJRxUEQAlAwACAAEKAACCZAAAAAAAAA==.Xanakmando:BAAANQADCggIFQAAAA==.Xandertay:BAAANQADCgMIBQAAAA==.Xanthos:BAAANQADCgIIAgAAAA==.Xantosz:BAAANQAECgEIAQABNQAFFAYIFQAQAIAVAA==.',
Xi='Xianyu:BAABNQAECn8hAAMVAAcKmAPlFACrAAAVAAcKmAPlFACrAAAgAAEKIAC5WQAEAAAAAA==.',
Ya='Yahman:BAAANQADCgMIAwAAAA==.Yarian:BAAANQAECgMIAwAAAA==.',
Ym='Ymirr:BAAANQABCgcICAAAAA==.',
Yu='Yuck:BAAANQAECgIIAgABNQAFFAcIFQAPANEeAA==.',
Za='Zachhunter:BAACNQAFFH8cAAMRAAcKoCEtDQCAAQASAAUKHh0tCgCgAQARAAQKdSMtDQCAAQA1AAQKfzsAAxIACgopJTMQAOcCABIACApYJDMQAOcCABEACAo5IpZwADACAAAA.Zachmage:BAAANQADCggIFgAAAA==.Zan:BAACNQAFFH8VAAMQAAYKgBXhDADqAAAQAAQK5xThDADqAAAPAAUKWAhfGACvAAA1AAQKfzQAAxAACgrDHxcjAPsCABAACgrDHxcjAPsCAA8AAwomETLcALAAAAAA.',
Ze='Zephrie:BAAANQADCgYIBgAAAA==.Zeronation:BAAANQAECgMIBAAAAA==.',
Zi='Zinderella:BAAANQAECgUICAABNQAECgoKNgARAN0VAA==.',
Zu='Zultrix:BAAANQAECgUICgAAAA==.',
Zy='Zylaeri:BAABNQAECn8WAAIBAAkKnghJjgBrAQABAAkKnghJjgBrAQAAAA==.',
['Éo']='Éowyn:BAAANQADCgEIAQAAAA==.',
['Ël']='Ëllër:BAABNQAECn8aAAIUAAgKKQpUCgDxAAAUAAgKKQpUCgDxAAAAAA==.',
['ßä']='ßädër:BAAANQAECgMIAwABNQAECgoKQQASAIAVAA==.',
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
