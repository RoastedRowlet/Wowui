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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Druid-Restoration','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Hunter-Survival','Druid-Balance','DeathKnight-Frost','Paladin-Holy','Warrior-Arms','Warrior-Fury','Warrior-Protection','Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','Warlock-Destruction','Monk-Brewmaster','Mage-Frost','Mage-Arcane','Mage-Fire','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Rogue-Subtlety','Rogue-Assassination','Monk-Mistweaver','Monk-Windwalker','Warlock-Demonology','Warlock-Affliction','Shaman-Enhancement','DemonHunter-Devourer','Rogue-Outlaw','Druid-Feral','Druid-Guardian','DemonHunter-Havoc',}
local provider = {region='US',realm='Arathor',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abavok:BAAANQADCgcIBwAAAA==.Absoul:BAACNQAFFH8bAAIBAAUKmw9VFgBSAQABAAUKmw9VFgBSAQA1AAQKf1AAAgEACgqoGk04AIcCAAEACgqoGk04AIcCAAAA.Abuudd:BAAANQAECggIDwABNQAECgoKNAACAEggAA==.Abyssian:BAABNQAECn8nAAQBAAoK1wt/XADNAQABAAoK0gt/XADNAQADAAcK7APtFgDAAAACAAYKkgXGRACaAAAAAA==.',
Ac='Acedia:BAABNQAECn83AAIBAAoK5hlJKQCnAgABAAoK5hlJKQCnAgAAAA==.',
Ad='Adellas:BAABNQAECn9YAAIEAAoKbR7FCQA2AwAEAAoKbR7FCQA2AwAAAA==.Adern:BAABNQAECn9iAAICAAoKgB1dDACVAgACAAoKgB1dDACVAgAAAA==.Adon:BAAANQADCgUIBQABNQAECgYIDgAFAAAAAA==.Adonn:BAABNQAECn9OAAMGAAoK+RzfTwClAgAGAAoK+RzfTwClAgAHAAIKBgpAZwBGAAAAAA==.Adonshadriel:BAAANQAECgYIDgAAAA==.',
Ae='Aelali:BAABNQAECn8mAAIIAAoKFwlbBwAFAgAIAAoKFwlbBwAFAgAAAA==.',
Af='Afador:BAAANQADCggIEgABNQAECgcIEQAFAAAAAA==.',
Ag='Ageling:BAAANQADCgUIBQAAAA==.',
Al='Aladestar:BAACNQAFFH8TAAIJAAYKLhlgDABBAQAJAAYKLhlgDABBAQA1AAQKfzYAAwkACgqMHKElAKUCAAkACgqMHKElAKUCAAQABgpOFLw4AFgBAAAA.Albinodh:BAAANQAECgMIBAAAAA==.Alderleise:BAAANQADCgcIBwAAAA==.Alexein:BAACNQAFFH8XAAIKAAYKMwrhCwAMAQAKAAYKMwrhCwAMAQA1AAQKfzIAAgoACgrLGqcqAEYCAAoACgrLGqcqAEYCAAAA.',
Am='Amets:BAABNQAECn8sAAMLAAoKWxQzLgBqAgALAAoKWxQzLgBqAgAGAAQKZAxVOQHEAAAAAA==.Amorae:BAAANQADCggIDwAAAA==.',
An='Anabel:BAAANQAECgcIDQAAAA==.Anamii:BAAANQAECgYICQAAAA==.Andorsi:BAAANQAECgEIAQAAAA==.',
Ao='Aoratos:BAAANQAECgEIAQAAAA==.',
Ar='Arachne:BAABNQAECn8iAAICAAkKQwoaNgBzAQACAAkKQwoaNgBzAQAAAA==.Aracianluz:BAAANQAECggIDQAAAA==.Arak:BAAANQADCgIIAgAAAA==.Arce:BAAANQAECgQIBAABNQAECgoKQwAKAOgXAA==.Arysia:BAAANQAECgUIBgAAAA==.Aryya:BAAANQADCgIIAgAAAA==.',
As='Ascaris:BAABNQAECn8VAAIMAAgK6BbVjgD3AQAMAAgK6BbVjgD3AQAAAA==.',
Av='Avalan:BAABNQAECn9LAAQNAAoKXyBeCwDXAQAMAAoKph3xQgDBAgANAAcK7CBeCwDXAQAOAAYKjhu2GAClAQAAAA==.Avanolatwo:BAAANQADCgYIBgABNQAECgoKLwAPADUZAA==.Avashammy:BAABNQAECn8vAAMPAAoKNRlNLgCoAgAPAAoKNRlNLgCoAgAQAAYKyhCJlABxAQAAAA==.Aviendah:BAABNQAECn8tAAIRAAoKgAoVdgDSAQARAAoKgAoVdgDSAQAAAA==.',
Aw='Awsomeonet:BAAANQAECggICAAAAA==.',
Az='Azdfghop:BAACNQAFFH8PAAMSAAgKHA8mCgCgAQASAAcKCgwmCgCgAQARAAIKcx54IACxAAA1AAQKfyYAAxIACgrqIkAWAKkCABIACQqsIUAWAKkCABEAAgqUI4MvAVkAAAAA.Azzinotica:BAAANQAECgQIBgAAAA==.',
Ba='Baalsanaro:BAAANQADCggIFQABNQAECgQIBQAFAAAAAA==.Babeshot:BAABNQAECn9PAAIRAAoKZw9MdAAoAgARAAoKZw9MdAAoAgAAAA==.Baelgar:BAAANQAECgMIAwAAAA==.',
Be='Bergur:BAAANQAECgYIDgABNQAECgoKPAATAKgjAA==.',
Bi='Bigbear:BAAANQADCggICAABNQAECgcIFgAUACQRAA==.Biggy:BAAANQADCgIIAgAAAA==.Bignose:BAABNQAECn8bAAMHAAoKSiaMAACNAwAHAAoKSiaMAACNAwAGAAEKAAA+zgEAAAABNQAFFAYIEwAVANomAA==.Binksy:BAAANQAECggICAAAAA==.',
Bl='Blaaze:BAAANQADCgYIBgAAAA==.Blackfrost:BAABNQAECn8dAAIWAAkKNBEHEQCWAQAWAAkKNBEHEQCWAQAAAA==.Blaiddyd:BAABNQAECn9KAAIRAAoKMx4uJwCjAgARAAoKMx4uJwCjAgAAAA==.',
Bo='Bomi:BAAANQAECgEIAQAAAA==.Boogereater:BAAANQAECgMIAgABNQAECgUICQAFAAAAAA==.',
Br='Brandawn:BAABNQAECn8aAAMHAAYKuAwsRQCRAAAGAAYK5AaqKwGpAAAHAAQKEg8sRQCRAAAAAA==.Bred:BAAANQADCggICAAAAA==.',
Bu='Burndasheep:BAABNQAECn9GAAQXAAoKfRPacQDNAQAXAAoKYRPacQDNAQAWAAIK4xO/KwCHAAAYAAEKew0ZDQA6AAAAAA==.',
['Bæ']='Bæyy:BAABNQAECn8cAAIXAAYKCwoo1AACAQAXAAYKCwoo1AACAQAAAA==.',
Ca='Calyris:BAAANQADCgIIBAAAAA==.Caspias:BAEANQADCggIEgAAAA==.Caylynn:BAAANQAECgUICAAAAA==.Caynelin:BAAANQAECgEIAQAAAA==.',
Ce='Cestbusiness:BAAANQADCgUIBQAAAA==.',
Ch='Chaoslock:BAABNQAECn8WAAIUAAcKJBHQFgC2AQAUAAcKJBHQFgC2AQAAAA==.Chetter:BAAANQAECggIBgAAAA==.Chicknfajita:BAAANQAECgcICQABNQAECgoKHAAQAEcgAA==.Chickpea:BAAANQAECgQIBwAAAA==.',
Ci='Civilian:BAAANQAECgYICAABNQAECgoKNAACAEggAA==.',
Co='Cocytus:BAAANQAECgIIAQAAAA==.Colbith:BAABNQAECn8aAAIJAAcKYwx2YgBEAQAJAAcKYwx2YgBEAQAAAA==.Corblixx:BAAANQAECgEIAQAAAA==.Cordaddy:BAAANQAECggIEQABNQAECgoKLQAPAKAlAA==.Cordelvo:BAAANQAECggIEAABNQAECgoKLQAPAKAlAA==.Cordragon:BAAANQAECgIIBAABNQAECgoKLQAPAKAlAA==.Cordragu:BAABNQAECn8tAAIPAAoKoCVEBACoAwAPAAoKoCVEBACoAwAAAA==.Cordran:BAAANQAECgEIAgABNQAECgoKLQAPAKAlAA==.Corinthin:BAAANQAECgUIBQAAAA==.Corraa:BAAANQADCgEIAQAAAA==.',
Cr='Crakum:BAABNQAECn8XAAIQAAYKrRS0iwCHAQAQAAYKrRS0iwCHAQAAAA==.Crinn:BAABNQAECn8bAAMZAAcKDg3FagBnAQAZAAcKDg3FagBnAQAKAAIK3AN5owBHAAAAAA==.Crizmon:BAABNQAECn8eAAIKAAkKRx8MFQDkAgAKAAkKRx8MFQDkAgAAAA==.',
Cu='Cucumber:BAAANQAECgQIBAAAAA==.',
Da='Damorthyx:BAABNQAECn8nAAIaAAoKJhQQMwB+AQAaAAoKJhQQMwB+AQAAAA==.Darazarke:BAACNQAFFH8gAAMbAAgKAA2JBQAOAgAbAAgKAA2JBQAOAgAcAAEKLQVIDQA9AAA1AAQKfzIABBsACgqUGAcTAHwCABsACgqUGAcTAHwCAB0AAQqKFsMiAEgAABwAAQqCGF0bAEYAAAAA.Darkquill:BAABNQAECn8mAAIQAAoKOQ2LcwDGAQAQAAoKOQ2LcwDGAQAAAA==.Daspoof:BAAANQADCgYIBgAAAA==.Dayquil:BAEANQADCgcIBwABNQAFFAQICgAGANYMAA==.',
De='Deadaddie:BAABNQAECn8bAAMKAAkKMRx8LgAuAgAKAAkKMRx8LgAuAgAZAAEKZhdH1gBCAAABNQAECgoKPgAXAMEiAA==.Deamoneyes:BAAANQAECgQIBgAAAA==.Deathkauf:BAAANQAECgEIAQAAAA==.Deathvok:BAAANQADCgMIAwAAAA==.Demolitions:BAAANQAECggICAAAAA==.Dezatra:BAAANQADCgcIBgAAAA==.',
Dh='Dhonaan:BAAANQAECgMIAQAAAA==.',
Di='Dieselcon:BAACNQAFFH8GAAIHAAQKUgZdCQCWAAAHAAQKUgZdCQCWAAA1AAQKf00AAwcACgqNFrARABACAAcACgqNFrARABACAAYABAr+BdRKAagAAAAA.Diprivan:BAABNQAECn9LAAMeAAoKDCEuEQDuAgAfAAoK9BzZEQDuAgAeAAoKPh8uEQDuAgAAAA==.',
Dk='Dkbabe:BAAANQAECgEIAgAAAA==.',
Do='Dolobrik:BAAANQABCgYIBwAAAA==.Domdog:BAABNQAECn8dAAIXAAcKvgdJBQGFAQAXAAcKvgdJBQGFAQAAAA==.Domína:BAAANQAECggIDAAAAA==.Dontforget:BAAANQAECggIEwAAAA==.Doomdealer:BAABNQAECn84AAMKAAoK4BDaMADmAQAKAAoK4BDaMADmAQAaAAEKAACKugBSAAAAAA==.Doomed:BAABNQAECn8iAAILAAkK1iBvJgDQAgALAAkK1iBvJgDQAgABNQAECgoKMQAgAKsjAA==.Doonya:BAAANQAECgEIAgAAAA==.Dottee:BAAANQAECggIAwAAAA==.Dougwalker:BAAANQADCgIIAgAAAA==.',
Dr='Dracodaddy:BAAANQADCgIIAgAAAA==.Draftymonk:BAABNQAECn8XAAMVAAcKMR9QCgBxAgAVAAYK6SNQCgBxAgAhAAMKLBAwUQCuAAABNQAECgoKIwAaAGghAA==.Drage:BAABNQAECn9GAAMiAAoKMRgCRACGAgAiAAoKMRgCRACGAgAUAAEKdgMvhQAkAAAAAA==.Drax:BAABNQAECn8pAAMjAAoKfQt/DwBWAQAiAAoKmgiMogCQAQAjAAcKvQt/DwBWAQAAAA==.Dreadgar:BAAANQAECgQIBQABNQAECgoKKAAQAPIgAA==.Dritzzagain:BAAANQAECgUIDAAAAA==.Dritzzcat:BAAANQADCgYICwAAAA==.',
Dw='Dwreck:BAAANQAECggIDgAAAA==.',
Ed='Ediann:BAAANQAECgcIDgAAAA==.',
El='Elandrus:BAAANQAECgUICgABNQAECgoKMwAXAFEVAA==.Eldarine:BAAANQADCgUIBQAAAA==.Elishiveth:BAAANQAECgYIDgAAAA==.',
Em='Emmara:BAABNQAECn8jAAISAAoKVQOvMwDZAAASAAoKVQOvMwDZAAAAAA==.',
En='Enitar:BAAANQADCgcICAABNQAECgoKRgAXAH0TAA==.',
Er='Erata:BAABNQAECn8uAAIjAAgKMAfwEQAYAQAjAAgKMAfwEQAYAQAAAA==.Erlik:BAAANQADCgMIBAAAAA==.Erzakzaktraz:BAAANQADCgYIBgABNQADCgcIBgAFAAAAAA==.',
Et='Etuba:BAAANQAECgEIAgAAAA==.',
Ev='Evullight:BAAANQADCgEJAQAAAA==.',
Ez='Ezlok:BAABNQAECn8oAAIQAAoK8iBpIAAKAwAQAAoK8iBpIAAKAwAAAA==.',
Fa='Facemash:BAAANQAECgQIBAABNQAECgoKRgAXAH0TAA==.Fae:BAAANQABCgUIBQAAAA==.Faedra:BAAANQADCggIFAABNQABCgUIBQAFAAAAAA==.Faelyn:BAAANQADCgIIAgABNQABCgUIBQAFAAAAAA==.Falerin:BAABNQAECn8yAAIEAAoK4Rt0GAB7AgAEAAoK4Rt0GAB7AgAAAA==.Farryn:BAAANQADCgEIAQAAAA==.',
Fe='Feenex:BAABNQAECn8bAAIZAAkKeQ0/LwByAQAZAAkKeQ0/LwByAQAAAA==.Feldora:BAAANQADCgYIBgAAAA==.Festiva:BAAANQAECgIIBAAAAA==.',
Fi='Fillorey:BAAANQADCggICAABNQAECgoKMwAXAFEVAA==.Firedealer:BAABNQAECn9OAAMSAAoKRRjvDgBNAgASAAoKRRjvDgBNAgARAAQKbxKN8gAcAQAAAA==.',
Fl='Flappy:BAAANQAECgIIBAABNQAECgkJNgAPACYbAA==.Flashmaster:BAAANQAFFAEIAQAAAA==.Flawlessheal:BAAANQADCgMIAwAAAA==.Flora:BAAANQADCgIIAgABNQABCgUIBQAFAAAAAA==.Fluffybutt:BAAANQADCggIFAAAAA==.',
Fo='Fossora:BAAANQADCgcIBgAAAA==.Foxygrandpa:BAAANQADCgUIBwAAAA==.',
Fr='Freyiah:BAAANQADCgYIBgAAAA==.',
Fy='Fyatre:BAAANQAECgYIDwAAAA==.',
Ga='Galadran:BAAANQABCgIIAgAAAA==.Galath:BAAANQAECgUJCAABNQAECgMIAwAFAAAAAA==.Gandallf:BAAANQADCgUIBQAAAA==.',
Ge='Gerree:BAAANQADCgYICgAAAA==.Gerry:BAABNQAECn8qAAIIAAoKYRokAwCFAgAIAAoKYRokAwCFAgAAAA==.',
Gg='Ggkando:BAABNQAECn8nAAIRAAkK/wwJbwDjAQARAAkK/wwJbwDjAQAAAA==.',
Gh='Ghemaldir:BAAANQABCgIIAgAAAA==.',
Gi='Gildius:BAAANQADCgIIAgAAAA==.Gingerail:BAAANQAECgQICQAAAA==.',
Gl='Glory:BAABNQAECn8mAAIaAAoK6Rw9IwCdAgAaAAoK6Rw9IwCdAgAAAA==.',
Gn='Gnayami:BAAANQADCgcIDwAAAA==.',
Go='Goochsquirts:BAABNQAECn8fAAIPAAgKRxsOUAAlAgAPAAgKRxsOUAAlAgAAAA==.Govna:BAAANQADCggIFAAAAA==.',
Gr='Grakkaem:BAAANQAECgMIBAAAAA==.Grannet:BAAANQAECgEIAQAAAA==.Gravedygger:BAABNQAECn9SAAIRAAoKqBfrSgCNAgARAAoKqBfrSgCNAgAAAA==.Graveflame:BAAANQABCgYICgAAAA==.Greenfear:BAAANQADCgYIDAAAAA==.Grenswood:BAAANQAECgcIEgAAAA==.Greybeeredd:BAAANQAECgIIBAAAAA==.Grimmkin:BAABNQAECn8sAAQkAAoKOxpKCwC8AgAkAAoKOxpKCwC8AgAPAAIKrA8e/gBuAAAQAAEKAACtQwEsAAAAAA==.Grind:BAAANQAECgQIBAABNQAECgcIEQAFAAAAAA==.Growl:BAAANQAECgEIAgAAAA==.Grumbo:BAAANQADCgcIBgAAAA==.',
Gu='Gunnerr:BAAANQAECgEIAQABNQAECgEIAQAFAAAAAA==.Guuldurak:BAAANQADCgcIBgAAAA==.',
Ha='Hailcat:BAAANQAECgMIBAABNQAECgoKJAAiAC0PAA==.Handivhe:BAAANQADCgYIBgAAAA==.Hasew:BAABNQAECn9UAAIRAAoKKCJRIQC6AgARAAoKKCJRIQC6AgAAAA==.',
He='He:BAAANQAECgcIDwABNQAECgoKQwAKAOgXAA==.Hellanor:BAAANQABCgUICQAAAA==.Helpimßlind:BAABNQAECn8jAAIlAAoKfxd5FgAGAgAlAAoKfxd5FgAGAgAAAA==.Hera:BAACNQAFFH8YAAIRAAYK5iQbBQCtAQARAAYK5iQbBQCtAQA1AAQKfzUAAhEACgq2Jh4EAMcDABEACgq2Jh4EAMcDAAAA.Heyner:BAABNQAECn9UAAMmAAoKeh0/AQCkAgAmAAoKeh0/AQCkAgAeAAgKuA+zaQBtAQAAAA==.',
Hi='Hinral:BAACNQAFFH8XAAIgAAYK9Rv+AgDyAQAgAAYK9Rv+AgDyAQA1AAQKfzgAAiAACgoyJKACAJMDACAACgoyJKACAJMDAAAA.Hiya:BAAANQADCgIIAgABNQAECgoKQwAKAOgXAA==.',
Ho='Holyiaa:BAABNQAECn8gAAIBAAoK+g82SQATAgABAAoK+g82SQATAgABNQAECggIGgAbAJkHAA==.Holyluz:BAAANQAECgYICgABNQAECggIDQAFAAAAAA==.Holysmacker:BAAANQAECgUIBQABNQAECgoKJQAWAGwZAA==.',
Hy='Hymns:BAAANQAECggIAgAAAA==.',
['Hë']='Hëll:BAABNQAECn8kAAMiAAoKLQ9acwAHAgAiAAoKLQ9acwAHAgAUAAEKGRC/cwA7AAAAAA==.',
Il='Illaynne:BAABNQAECn9AAAMBAAoK2xfPOQBVAgABAAoK2xfPOQBVAgACAAEKAgnpYgA2AAAAAA==.',
Im='Imani:BAACNQAFFH8XAAIkAAYKSgQUAwAAAQAkAAYKSgQUAwAAAQA1AAQKfzUAAiQACgpeDhgVABcCACQACgpeDhgVABcCAAAA.Immensepain:BAAANQAECgUIBAAAAA==.',
In='Inoshikacho:BAABNQAECn8uAAInAAoKSgy3FgBpAQAnAAoKSgy3FgBpAQAAAA==.Involio:BAAANQAECgEIAQAAAA==.',
Ir='Irishmecha:BAACNQAFFH8VAAIfAAYKdxKzAwA1AQAfAAYKdxKzAwA1AQA1AAQKfzQAAh8ACgrEIUQNAPgBAB8ACgrEIUQNAPgBAAAA.Irishpaws:BAAANQAECgEIAQAAAA==.Ironshot:BAAANQADCggIBgAAAA==.',
Is='Isaeus:BAAANQAECgEIAQAAAA==.',
It='Itharillys:BAABNQAECn8tAAIRAAoK+BPrcwAoAgARAAoK+BPrcwAoAgAAAA==.',
Ja='Jaadu:BAAANQADCgQIBAAAAA==.Jangus:BAABNQAECn8ZAAIdAAYK2BGrEQAeAQAdAAYK2BGrEQAeAQABNQAECgcIEQAFAAAAAA==.Jaybone:BAAANQAECgIIAQAAAA==.',
Je='Jeefus:BAAANQAECggIAgAAAA==.Jeennkiins:BAAANQADCgYIBgABNQAECgUICQAFAAAAAA==.Jenifur:BAAANQAECgIIAwABNQABCgUIBQAFAAAAAA==.Jessibella:BAAANQADCgQIBAAAAA==.Jezzako:BAAANQAECgcIEAAAAA==.',
Ji='Jingles:BAAANQABCgMIAwAAAA==.Jinx:BAAANQADCggIEgABNQABCgUIBQAFAAAAAA==.',
Jo='Johali:BAAANQAECggIEgAAAA==.Jozan:BAAANQADCggIIQAAAA==.',
Ju='Justise:BAAANQADCgIIAgABNQADCgYJCwAFAAAAAA==.Jutojerry:BAABNQAECn8xAAIgAAoKqyNJAQAMBAAgAAoKqyNJAQAMBAAAAA==.',
Jz='Jz:BAAANQAECggICgABNQAECgoKQwAKAOgXAA==.',
['Jö']='Jöhnblaze:BAABNQAECn9JAAMMAAoKKRK7WgDuAQAMAAoKKRK7WgDuAQAOAAcKKg3sHQAQAQAAAA==.',
Ka='Kaga:BAAANQADCgEJAQABNQAECgoKRgAXAH0TAA==.Kahoona:BAAANQAECgEIAQAAAA==.Kailys:BAABNQAECn82AAIHAAoKWxLVHQCBAQAHAAoKWxLVHQCBAQAAAA==.Kaisana:BAAANQAECgYICwAAAA==.Kaishias:BAABNQAECn8wAAMHAAkKaxgLGAC5AQAGAAkKaxgJaQD+AQAHAAgKaxULGAC5AQAAAA==.Kaldrek:BAAANQAECgMIBgABNQAECgoKKQAGAMgXAA==.Kandoh:BAAANQAECggICAABNQAECgkJJwARAP8MAA==.Kanimeh:BAAANQAECgEIAQAAAA==.Kankuró:BAACNQAFFH8IAAIRAAIKqBvqIACdAAARAAIKqBvqIACdAAA1AAQKf04AAhEACgqvITYXAOoCABEACgqvITYXAOoCAAAA.Karelleira:BAAANQADCgUIBQAAAA==.Kautie:BAABNQAECn8cAAILAAoKJR3VEgAkAwALAAoKJR3VEgAkAwAAAA==.',
Ki='Killahmike:BAAANQAECgQIBgAAAA==.Killudead:BAABNQAECn8bAAIGAAoKgBgwRwBUAgAGAAoKgBgwRwBUAgAAAA==.Kishana:BAAANQADCgcIBgAAAA==.',
Kl='Klatz:BAAANQAECgUIBQAAAA==.',
Ko='Kodetra:BAABNQAECn8jAAIcAAgKMwwWDQAdAQAcAAgKMwwWDQAdAQAAAA==.Kolgrim:BAABNQAECn86AAMaAAoKsh28DwCkAgAaAAoKsh28DwCkAgAKAAkKlhG6PQDVAQAAAA==.Kong:BAAANQAECgMIAgAAAA==.Korvuk:BAABNQAECn8pAAMGAAoKyBfdUQA3AgAGAAoKyBfdUQA3AgALAAoKKBBfSgDqAQAAAA==.',
Kr='Kristafur:BAAANQADCggIDgABNQABCgUIBQAFAAAAAA==.Krom:BAABNQAECn8qAAMPAAoKqgYgfQA7AQAPAAoKqgYgfQA7AQAQAAgKBBCKiAD8AAAAAA==.Krysta:BAABNQAECn9DAAMBAAoKeiE9GAAVAwABAAoKeiE9GAAVAwACAAEKAACegQAoAAABNQABCgUIBQAFAAAAAA==.',
Ky='Kynris:BAAANQADCggIEQABNQAECgoKMwAXAFEVAA==.',
La='Lairia:BAAANQAECgMIAwABNQAFFAgIHgARAKshAA==.Lanaal:BAAANQADCgEIAQAAAA==.Lancewh:BAAANQADCgcIDAAAAA==.Lanciwinluna:BAAANQADCgQIBAAAAA==.Lancywinelia:BAAANQADCgQIBgAAAA==.Lauryssa:BAAANQADCggICAAAAA==.',
Ld='Ldydthstryke:BAAANQAECgYIBgABNQAECgoKTgASAEUYAA==.',
Le='Legg:BAAANQABCgMIAwAAAA==.Legolâs:BAAANQADCgUIBQAAAA==.Leonora:BAABNQAECn8aAAISAAoKSwaZJgAzAQASAAoKSwaZJgAzAQAAAA==.Leviathañ:BAAANQADCgIIAgABNQAECggIDgAFAAAAAA==.Lezene:BAAANQAECgUIEAAAAA==.',
Li='Linstriker:BAABNQAECn8yAAIoAAkKiCFkCgDKAgAoAAkKiCFkCgDKAgABNQAFFAcIFQAPANEeAA==.',
Lo='Lockbone:BAAANQAECgIIAQAAAA==.Lorette:BAABNQAECn9JAAMBAAoKJCC1FwAZAwABAAoKJCC1FwAZAwACAAoKYhwWDwBoAgAAAA==.Lorzik:BAAANQABCgQIAwAAAA==.',
Lu='Lucethegoose:BAAANQADCgQIBAAAAA==.Luckynyx:BAAANQAECgYIDgAAAA==.Lunate:BAAANQAECgEIAQABNQAECgoKNAACAEggAA==.',
Ma='Machotedan:BAABNQAECn9IAAIGAAoKsiIDGQD+AgAGAAoKsiIDGQD+AgAAAA==.Macmittens:BAAANQAECgcIDAAAAA==.Makoes:BAAANQADCggICAAAAA==.Mamadrag:BAABNQAECn8aAAIbAAgKmQc2HQAtAQAbAAgKmQc2HQAtAQAAAA==.Managua:BAAANQADCgEIAQAAAA==.Mandwa:BAAANQADCggIGAABNQAECgoKRgAXAH0TAA==.Mangojuulpod:BAAANQAECgYIBwABNQAECgoKMQAgAKsjAA==.Mario:BAABNQAECn8lAAIWAAoKbBk2CAAvAgAWAAoKbBk2CAAvAgAAAA==.Mastashifta:BAABNQAECn8WAAMJAAYKsA5PVADNAAAJAAYKsA5PVADNAAAEAAEKzAFqgwAaAAAAAA==.Mataa:BAABNQAECn8zAAIXAAoKURUakwB/AQAXAAoKURUakwB/AQAAAA==.Matryoshka:BAAANQADCgUIDQABNQAECgEIAgAFAAAAAA==.Mattsadler:BAAANQAECgIIAQAAAA==.Maxxim:BAAANQAECgIIAgAAAA==.Mayihmpurleg:BAAANQAECgUIBQABNQAECgoKTgASAEUYAA==.Mazeman:BAAANQADCgUIBQAAAA==.',
Me='Meilin:BAAANQAECgMIAwAAAA==.Mellachion:BAAANQAECgYICAABNQAECgoKJQAWAGwZAA==.Meta:BAABNQAECn8iAAIpAAoK7hkeHQAlAgApAAoK7hkeHQAlAgABNQAECgoKSwAeAAwhAA==.',
Mi='Mistaya:BAAANQADCgUIBQABNQAECgoKLAAiAIcKAA==.Mists:BAABNQAFFH8FAAMiAAUK4BHIFwA2AQAiAAQKABjIFwA2AQAUAAEKoAUQIgBFAAAAAA==.Miththrawndo:BAABNQAECn8zAAIaAAoKXw4LVACkAQAaAAoKXw4LVACkAQABNQAFFAQIBgAHAFIGAA==.',
Mo='Moadib:BAAANQAECggIDAAAAA==.Momjeans:BAABNQAECn84AAIXAAoKNR5iQABMAgAXAAoKNR5iQABMAgAAAA==.',
Mu='Mumbo:BAAANQADCgcIBwABNQAECgcIEQAFAAAAAA==.Muu:BAAANQADCgYICAAAAA==.',
My='Mydaan:BAAANQADCgIIAwAAAA==.Mythunsarian:BAABNQAECn8pAAIpAAoKLQ3tLACrAQApAAoKLQ3tLACrAQAAAA==.',
['Má']='Mákï:BAABNQAECn8aAAIMAAgKNBCHkQDwAQAMAAgKNBCHkQDwAQAAAA==.',
['Mä']='Mäylä:BAABNQAECn8xAAMJAAoKNg0gMwBzAQAJAAoKNg0gMwBzAQAEAAEKlA6EfAApAAAAAA==.',
['Mí']='Míst:BAABNQAECn9KAAIGAAoK4RjpXgB8AgAGAAoK4RjpXgB8AgAAAA==.',
Na='Narlis:BAABNQAECn8wAAIZAAoKriM7CgBrAwAZAAoKriM7CgBrAwAAAA==.Nautprepared:BAAANQAECgMIAQABNQAECgoKMQAgAKsjAA==.',
Ne='Nephie:BAAANQAECgYICwAAAA==.Nezqk:BAACNQAFFH8WAAQKAAYKhA2kCwARAQAKAAUKeg2kCwARAQAZAAIKlxHyFwCaAAAaAAEKAAAFNQAAAAA1AAQKfzEABBkACgpjHPcyAF8CABkACQpuHPcyAF8CABoACAqQEvZOALkBAAoABwr3F6pNAGABAAAA.Nezquick:BAAANQAECgIIAgAAAA==.',
Ni='Niano:BAAANQABCgIIAgAAAA==.',
Nm='Nmnenthe:BAABNQAECn8wAAIdAAoKRBWFBwAbAgAdAAoKRBWFBwAbAgAAAA==.',
No='Notrealword:BAABNQAECn8dAAMHAAcKyRHqMwDlAAAGAAcK3wtvwwBNAQAHAAUK1BPqMwDlAAABNQAECgoKVAARACgiAA==.Noxluminous:BAAANQABCgIIAgAAAA==.',
Ob='Obin:BAABNQAECn82AAMMAAoKrRBRYwDWAQAMAAoKoQ5RYwDWAQANAAcKaA+3GgD6AAAAAA==.',
Oc='Occasionally:BAAANQAECgIIAgAAAA==.',
Ok='Okukoy:BAAANQABCgEIAQAAAA==.',
Om='Ominious:BAABNQAECn8oAAMkAAoKvxIuFAAmAgAkAAkKJxEuFAAmAgAQAAUKtRcBqgBAAQABNQAECggIEAAFAAAAAA==.Omnissia:BAAANQAECgUIAwABNQAECggIEAAFAAAAAA==.Omnius:BAABNQAECn8iAAMQAAoKeRxeYAAAAgAQAAoKeRxeYAAAAgAPAAEKMAu9KQEkAAAAAA==.Omnya:BAAANQAECgcIDQABNQAECggIEAAFAAAAAA==.Omnyi:BAAANQAECggIEAAAAA==.',
Ow='Owendriel:BAACNQAFFH8MAAMlAAYKwQk0CgC+AAAlAAUKNQw0CgC+AAApAAEKZQLkGwBCAAA1AAQKfxkAAyUACgq9FR0oAAMCACUACQpiFB0oAAMCACkAAwrpEglxALUAAAAA.',
Pa='Paindya:BAABNQAECn8ZAAIkAAcKRg6eGQB8AQAkAAcKRg6eGQB8AQAAAA==.Paleigh:BAAANQABCgYICwAAAA==.Palivok:BAAANQAECgUIBwAAAA==.Pandress:BAABNQAECn8ZAAIRAAgKjgxYxwBzAQARAAgKjgxYxwBzAQAAAA==.Pankake:BAAANQAECgQIBAABNQAECgoKPAATAKgjAA==.Paralysis:BAACNQAFFH8YAAIlAAYK/RQ9BQAnAQAlAAYK/RQ9BQAnAQA1AAQKfzQAAiUACgq1HSEeAGACACUACgq1HSEeAGACAAAA.Parody:BAAANQAECgEIAQABNQAECgIIBAAFAAAAAA==.',
Pe='Peetza:BAAANQAECgEIAQABNQAECgoKPAATAKgjAA==.Peryite:BAABNQAECn9PAAMBAAoK6BlYOQBXAgABAAoK6BlYOQBXAgADAAUKFRbkCQAHAQAAAA==.',
Ph='Phaedrana:BAAANQAECgcIDgAAAA==.',
Pi='Pisscat:BAABNQAECn8cAAIoAAgKhgOoSwCPAAAoAAgKhgOoSwCPAAAAAA==.Pixsil:BAAANQADCgQIBAAAAA==.',
Po='Pocketdragon:BAABNQAECn8tAAMdAAoKZxUhDwBpAgAdAAoKchQhDwBpAgAcAAYKWhBOEAA1AQAAAA==.Polymerase:BAAANQAECgQIBgABNQAECgoKRgAZAM0hAA==.',
Pr='Prideindeath:BAAANQAECgYICQAAAA==.Promiscuity:BAABNQAECn88AAMiAAoKWxzeHgCZAgAiAAoKWxzeHgCZAgAjAAIKwwlCIgBpAAABNQAECgoKSwAeAAwhAA==.Prængle:BAAANQADCgYIAwAAAA==.',
Ps='Psoas:BAABNQAECn80AAMCAAoKSCAnCABaAwACAAoKSCAnCABaAwABAAIK4BBH5AB7AAAAAA==.Psypriest:BAECNQAFFH8OAAIBAAYKUhm3CgAHAgABAAYKUhm3CgAHAgA1AAQKf0QAAgEACgpeIr0HALgDAAEACgpeIr0HALgDAAE1AAUUCQklAAEApQ4A.',
Py='Pyroheal:BAAANQAECggIEAAAAA==.',
Qu='Quaichang:BAAANQADCgYIBgAAAA==.',
Ra='Rabbi:BAABNQAECn84AAMCAAoKXxrkEgDTAgACAAoKXxrkEgDTAgABAAMKiiDBlwATAQAAAA==.Rahfna:BAAANQADCgcIDwAAAA==.Railænu:BAAANQADCggIDgAAAA==.Rainmist:BAAANQAECgUIBgAAAA==.Ranric:BAAANQAECgMIAwAAAA==.',
Re='Redall:BAAANQAECgMIAwAAAA==.Reesespbc:BAAANQAECgYIDQAAAA==.Reina:BAABNQAECn8fAAQHAAkKKxDyIwBPAQAHAAgKkRHyIwBPAQAGAAMKNgjicQFsAAALAAEKQQXgLAEqAAABNQABCgUIBQAFAAAAAA==.Reinz:BAABNQAECn8mAAQVAAoKtCKgAQAmAwAVAAoKtCKgAQAmAwAhAAIKmQntXgBkAAAgAAEK4AZ0QwAhAAAAAA==.Rektagar:BAABNQAECn88AAMQAAoKyiTUBQC8AwAQAAoKyiTUBQC8AwAPAAEKbwsR+gAyAAABNQAFFAgIHgARAKshAA==.Ressandra:BAAANQADCgMIBgAAAA==.Rezo:BAAANQAECgEIAgAAAA==.',
Ri='Riverarose:BAAANQADCggIFQAAAA==.',
Ro='Roar:BAAANQAECgYIEgABNQAECgcIEQAFAAAAAA==.',
Ry='Rysi:BAAANQADCgQIBAAAAA==.',
['Rò']='Ròs:BAACNQAFFH8aAAIHAAYKJRyHAwBHAQAHAAYKJRyHAwBHAQA1AAQKfzUAAgcACgrCIUcKAPYCAAcACgrCIUcKAPYCAAAA.',
['Rö']='Rös:BAAANQADCgEIAQABNQAFFAYIGgAHACUcAA==.',
Sa='Saberie:BAAANQADCggIFwABNQADCgMIBgAFAAAAAA==.Salaria:BAABNQAECn8sAAIlAAoKcw75MwCjAQAlAAoKcw75MwCjAQAAAA==.Salina:BAABNQAECn8WAAITAAgKJBV5EACqAQATAAgKJBV5EACqAQAAAA==.Sandstique:BAABNQAECn8xAAIPAAoKZyQpEwAxAwAPAAoKZyQpEwAxAwAAAA==.Sandweaver:BAAANQADCgcIBwAAAA==.Sanjira:BAAANQADCgYIBgAAAA==.Sanorrah:BAAANQADCgIIAgAAAA==.Sarlak:BAABNQAECn88AAMRAAoKch45JQACAwARAAoKch45JQACAwASAAEK8AYalwAqAAAAAA==.Sarusuby:BAABNQAECn9cAAIoAAoKhhOEGgCyAQAoAAoKhhOEGgCyAQAAAA==.Satae:BAABNQAECn88AAITAAoKqCOBAgBZAwATAAoKqCOBAgBZAwAAAA==.',
Sc='Schufft:BAABNQAECn8aAAIUAAcKzBuCCAB1AgAUAAcKzBuCCAB1AgAAAA==.Scottydh:BAAANQAECgIIAgABNQAECgoKTgAaAB4iAA==.Scottymac:BAABNQAECn9OAAIaAAoKHiKECgDnAgAaAAoKHiKECgDnAgAAAA==.Scottypal:BAAANQAECgQIBQABNQAECgoKTgAaAB4iAA==.',
Se='Seatah:BAAANQAECgMIAwAAAA==.Seba:BAABNQAECn8sAAIQAAoKWRauNAADAgAQAAoKWRauNAADAgAAAA==.Seeta:BAAANQAECgIIAgAAAA==.Seetah:BAABNQAECn8tAAMBAAoKzhRvWQAVAgABAAoKzhRvWQAVAgACAAQK3Qm3UwBdAAAAAA==.Seraphtharia:BAAANQABCgIIAgAAAA==.Sermon:BAAANQADCgQIBAABNQAECgcIEQAFAAAAAA==.',
Sh='Shadaddy:BAABNQAECn8+AAMXAAoKwSIZUgDcAgAXAAkKoyIZUgDcAgAWAAMKjiB5GwD9AAAAAA==.Shadowheart:BAAANQAECgQIBQAAAA==.Shakasana:BAAANQAECgIIAQAAAA==.Shal:BAABNQAECn8/AAIMAAoK1RpgNgBmAgAMAAoK1RpgNgBmAgAAAA==.Shamanluz:BAAANQADCgIIAgABNQAECggIDQAFAAAAAA==.Shamommy:BAAANQADCgUIBAAAAA==.Shamtaz:BAAANQAECgUICgAAAA==.Shimmerstar:BAABNQAECn8cAAIGAAkKYR0pcQBNAgAGAAkKYR0pcQBNAgAAAA==.Shroomgirl:BAAANQAECgUIBQAAAA==.Shrubhub:BAAANQAECgEIAQABNQAECgoKMQAgAKsjAA==.',
Si='Silexe:BAABNQAECn8yAAMdAAkKUhWECQDgAQAdAAgK6hSECQDgAQAcAAkKrRKHCQB9AQAAAA==.Sitga:BAAANQADCgIIAgAAAA==.',
Sk='Skåld:BAAANQADCgUIAwAAAA==.',
Sl='Slinga:BAAANQADCgcICQAAAA==.Slipperyboi:BAAANQAECgQICQAAAA==.Slÿ:BAAANQAECgIIAgAAAA==.',
So='Solarion:BAAANQAECgYIDwABNQAECgoKKAAQAPIgAA==.Soldraca:BAAANQAECgUICAAAAA==.',
St='Stabbirabbi:BAAANQAECgQIAgAAAA==.Stats:BAAANQAECgcIEQAAAA==.Stinkbug:BAAANQADCgQIBAAAAA==.Stutters:BAABNQAECn9GAAMZAAoKzSHmCADoAgAaAAoKrRz8FgD1AgAZAAoKoCDmCADoAgAAAA==.',
Su='Subayyru:BAAANQADCgEIAQABNQAECgYIHAAXAAsKAA==.Sudachi:BAAANQADCgYIBgABNQAFFAcKFQAhACscAA==.Sunnyräy:BAAANQAECgMIAwAAAA==.Superiorkill:BAAANQADCgcIBwAAAA==.Suthrheimr:BAABNQAECn9GAAINAAoKvRzFBQB0AgANAAoKvRzFBQB0AgABNQAECgoKKgAIAGEaAA==.',
Sy='Symphany:BAAANQABCggIEQAAAA==.',
['Sý']='Sýndrá:BAAANQAECgYIDQAAAA==.',
Ta='Talespin:BAAANQAECgUIBQAAAA==.Talysiah:BAABNQAECn8sAAIiAAoKhwpFZwChAQAiAAoKhwpFZwChAQAAAA==.Talzind:BAAANQADCgIIAgAAAA==.Tavok:BAABNQAECn9BAAINAAoKyx0yBAC2AgANAAoKyx0yBAC2AgAAAA==.Tazbis:BAAANQAECgQIBgAAAA==.',
Te='Teishuku:BAABNQAECn9ZAAIGAAoK6xW7WAAlAgAGAAoK6xW7WAAlAgAAAA==.Teusday:BAABNQAECn9DAAMKAAoK6BfhOADxAQAKAAoK6BfhOADxAQAaAAQKRgZYfwBqAAAAAA==.',
Th='Thiux:BAABNQAECn8/AAMiAAoKiCDkKQBnAgAiAAkK6iDkKQBnAgAUAAIKYB9vRACzAAAAAA==.Thoeleden:BAAANQAECgMIBgABNQAFFAcIFQAPANEeAA==.Thotsnprayrs:BAAANQAECgMIBgABNQAECgoKMQAgAKsjAA==.Thrappy:BAABNQAECn82AAMPAAkKJhseRgBJAgAPAAkKJhseRgBJAgAQAAcK1w9hogBRAQAAAA==.Thryna:BAAANQADCgEIAQAAAA==.Thugstyle:BAAANQABCgcIDgAAAA==.',
Ti='Tinsoon:BAAANQAECgUIBQAAAA==.Tintaglia:BAABNQAECn9EAAMiAAoKjxq/MgBEAgAiAAoKjxq/MgBEAgAjAAEKZBHPMQAxAAABNQAECgoKJQAWAGwZAA==.Tirtun:BAABNQAECn9ZAAIWAAoK+SA9AgBQAwAWAAoK+SA9AgBQAwAAAA==.',
Tr='Triggeer:BAABNQAECn8uAAIOAAoKEhhjDQDoAQAOAAoKEhhjDQDoAQAAAA==.Trolldemort:BAAANQADCgYIBgABNQAECgoKJgAiADQYAA==.',
Tu='Tully:BAABNQAECn8fAAIRAAYKxgO/6gDaAAARAAYKxgO/6gDaAAAAAA==.Tunkhan:BAAANQADCgQIBwAAAA==.Turnaround:BAAANQABCgIIAgAAAA==.',
Tw='Twelvekill:BAACNQAFFH8YAAIRAAYKxBbhCABgAQARAAYKxBbhCABgAQA1AAQKfzIAAhEACgpgIa4nAPkCABEACgpgIa4nAPkCAAAA.',
Ty='Tyliaa:BAABNQAECn9NAAMPAAoKDxxcLwCkAgAPAAoKDxxcLwCkAgAQAAoKjBRhMwAJAgABNQAECggIGgAbAJkHAA==.',
Ul='Ultramon:BAABNQAECn8wAAIGAAoKqBSygwAgAgAGAAoKqBSygwAgAgAAAA==.',
Un='Unbreakabull:BAAANQAECgEIAQAAAA==.Unwell:BAABNQAECn80AAIlAAoKkRshEwAvAgAlAAoKkRshEwAvAgAAAA==.',
Ur='Urgoochness:BAAANQADCgQIBAAAAA==.Urikhai:BAAANQADCggIAgAAAA==.',
Va='Vainglorious:BAAANQADCggIEwABNQAECgoKJgAaAOkcAA==.Valanora:BAABNQAECn9AAAIjAAoKLBbGBgABAgAjAAoKLBbGBgABAgAAAA==.Valerie:BAAANQAECggICwABNQAECgoKPwASAH4fAA==.Valianya:BAAANQABCgMIAwAAAA==.Valinaxius:BAABNQAECn8ZAAMaAAcK2BEoTwABAQAaAAYK4BQoTwABAQAKAAIKuAWlsAAwAAAAAA==.Vanyr:BAAANQAECgEIAQAAAA==.Vapturov:BAABNQAECn8YAAIZAAYKVAV3VgCsAAAZAAYKVAV3VgCsAAAAAA==.',
Ve='Veeks:BAABNQAECn9DAAIQAAoKvwwpSwCpAQAQAAoKvwwpSwCpAQAAAA==.Velibast:BAAANQAECgQIBAAAAA==.Velikirn:BAABNQAECn80AAMhAAoKEiEtCADpAgAhAAkKEiEtCADpAgAVAAkKKRZPDwD8AQAAAA==.Velimald:BAAANQAECgQIBAAAAA==.Velydia:BAAANQAECgYIBgAAAA==.Venefica:BAAANQAECgEIBAAAAA==.Verdracee:BAAANQABCgMIAwABNQAECgYIHAATAJ0EAA==.Versø:BAABNQAECn8iAAQfAAkKIRRhPgDVAQAfAAkKIRRhPgDVAQAeAAEKAAAiUwA1AAAmAAEKAADLDgAAAAAAAA==.Veryzi:BAAANQAECgEIAgAAAA==.',
Vi='Vine:BAAANQADCgQIBQABNQAECgoKSwAeAAwhAA==.',
Vl='Vlyrae:BAAANQADCgMIAwAAAA==.',
Vo='Voidbreaker:BAAANQADCgcIBwAAAA==.Voidhearted:BAABNQAECn9NAAICAAoKGxBGIwAYAgACAAoKGxBGIwAYAgAAAA==.Vonzuo:BAAANQAECgIIAgAAAA==.',
Vu='Vukodlak:BAAANQAECggICAABNQAECgoKJQAWAGwZAA==.',
['Vì']='Vìolet:BAAANQADCgMIAwABNQAECgkJNAAJALAfAA==.',
Wa='Warriorwuu:BAAANQABCgIIAgAAAA==.Wayshua:BAAANQADCgYIBgAAAA==.',
We='Werkajerk:BAAANQADCggICAABNQAFFAcIFQAPANEeAA==.Werkjathal:BAACNQAFFH8VAAIPAAcK0R53BgD8AQAPAAcK0R53BgD8AQA1AAQKfzoAAw8ACgpwJjkBANcDAA8ACgpwJjkBANcDABAABgq4H/ZEAMABAAAA.',
Wi='Wibbles:BAAANQADCgcICwAAAA==.Wigarthan:BAAANQADCgEIAQAAAA==.Wildsenpai:BAAANQADCgEIAgAAAA==.',
Wo='Wolfblitzer:BAABNQAECn87AAMGAAoKMBm4YgANAgAGAAoKMBm4YgANAgALAAYKyQKMuACqAAAAAA==.Wolfmanbro:BAAANQADCgMIAwAAAA==.Wolfpride:BAAANQADCgUIBQAAAA==.Worgenator:BAAANQADCgMIAwAAAA==.Worldbane:BAABNQAECn8oAAIUAAoKJA5qEQDtAQAUAAoKJA5qEQDtAQAAAA==.',
Wr='Wraithlash:BAAANQAECggIDgAAAA==.',
Wu='Wuu:BAAANQABCgIIAgAAAA==.Wuulock:BAAANQABCgEJAQAAAA==.',
Wy='Wynnhrt:BAAANQADCggICAAAAA==.',
Xa='Xalatath:BAABNQAECn87AAMBAAoKyh22FQApAwABAAoKyh22FQApAwACAAEKAACJdAAAAAAAAA==.Xanakmando:BAAANQADCggIFQAAAA==.Xandertay:BAAANQADCggIDQAAAA==.Xanthos:BAAANQADCgIIAgAAAA==.Xantosz:BAAANQAECgEIAQABNQAFFAYIGgAQAIEaAA==.',
Xi='Xianyu:BAABNQAECn8mAAMVAAgKHwTJFQDNAAAVAAgKHwTJFQDNAAAgAAEKIAC5WQAEAAAAAA==.',
Ya='Yahman:BAAANQADCgMIAwAAAA==.Yarian:BAAANQAECgMIAwAAAA==.',
Ym='Ymirr:BAAANQABCgcICAAAAA==.',
Yu='Yuck:BAAANQAECgIIAgABNQAFFAcIFQAPANEeAA==.',
Za='Zachhunter:BAACNQAFFH8eAAMRAAgKqyEtDQCAAQASAAUKHh0tCgCgAQARAAUKDyMtDQCAAQA1AAQKfzwAAxIACgopJTMQAOcCABIACApYJDMQAOcCABEACAo5IpZwADACAAAA.Zachmage:BAAANQADCggIFgAAAA==.Zan:BAACNQAFFH8aAAMQAAYKgRq7DgD5AAAQAAQKkxu7DgD5AAAPAAUK+wgeHgCvAAA1AAQKfzUAAxAACgrDHxcjAPsCABAACgrDHxcjAPsCAA8AAwomETLcALAAAAAA.',
Ze='Zephrie:BAAANQADCggICAAAAA==.Zeronation:BAAANQAECgMIBAAAAA==.',
Zi='Zinderella:BAAANQAECgUICAABNQAECgoKNgARAN0VAA==.',
Zu='Zultrix:BAAANQAECgUIDwAAAA==.',
Zy='Zylaeri:BAABNQAECn8WAAIBAAkKnghJjgBrAQABAAkKnghJjgBrAQAAAA==.',
['Éo']='Éowyn:BAAANQADCgEIAQAAAA==.',
['Ël']='Ëllër:BAABNQAECn8dAAIUAAkKQQohCwAPAQAUAAkKQQohCwAPAQAAAA==.',
['ßä']='ßädër:BAAANQAECgMIAwABNQAECgoKTgASAEUYAA==.',
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
