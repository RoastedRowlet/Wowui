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
local provider = {region='US',realm='Arathor',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abavok:BAAANQADCgcIBwAAAA==.Absoul:BAACNQAFFH8bAAIBAAUKmw9vEwBbAQABAAUKmw9vEwBbAQA1AAQKf1AAAgEACgqoGk04AIcCAAEACgqoGk04AIcCAAAA.Abuudd:BAAANQAECggIDQABNQAECgoKNAACAEggAA==.Abyssian:BAABNQAECn8nAAQBAAoK1wvnVQDNAQABAAoK0gvnVQDNAQADAAcK7APtFgDAAAACAAYKkgVIQACaAAAAAA==.',
Ac='Acedia:BAABNQAECn8yAAIBAAoKgxmbJQCoAgABAAoKgxmbJQCoAgAAAA==.',
Ad='Adellas:BAABNQAECn9PAAIEAAoKTB41CQAtAwAEAAoKTB41CQAtAwAAAA==.Adern:BAABNQAECn9ZAAICAAoKAh24DgAFAwACAAoKAh24DgAFAwAAAA==.Adon:BAAANQADCgUIBQABNQAECgYIDgAFAAAAAA==.Adonn:BAABNQAECn9FAAMGAAoK+Rx0SABBAgAGAAoK+Rx0SABBAgAHAAIKBgpAZwBGAAAAAA==.Adonshadriel:BAAANQAECgYIDgAAAA==.',
Ae='Aelali:BAABNQAECn8mAAIIAAoKFwlbBwAFAgAIAAoKFwlbBwAFAgAAAA==.',
Af='Afador:BAAANQADCggIEgABNQAECgcIEQAFAAAAAA==.',
Ag='Ageling:BAAANQADCgUIBQAAAA==.',
Al='Aladestar:BAACNQAFFH8TAAIJAAYKLhlQCgBEAQAJAAYKLhlQCgBEAQA1AAQKfzYAAwkACgqMHKElAKUCAAkACgqMHKElAKUCAAQABgpOFLw4AFgBAAAA.Albinodh:BAAANQAECgMIBAAAAA==.Alderleise:BAAANQADCgcIBwAAAA==.Alexein:BAACNQAFFH8WAAIKAAYKMwoRCgAQAQAKAAYKMwoRCgAQAQA1AAQKfzIAAgoACgrLGqcqAEYCAAoACgrLGqcqAEYCAAAA.',
Am='Amets:BAABNQAECn8sAAMLAAoKWxQqKAB6AgALAAoKWxQqKAB6AgAGAAQKZAxVOQHEAAAAAA==.Amorae:BAAANQADCggIDwAAAA==.',
An='Anabel:BAAANQAECggICAAAAA==.Anamii:BAAANQAECgYICQAAAA==.Andorsi:BAAANQAECgEIAQAAAA==.',
Ao='Aoratos:BAAANQAECgEIAQAAAA==.',
Ar='Arachne:BAABNQAECn8fAAICAAgKtgoaNgBzAQACAAgKtgoaNgBzAQAAAA==.Aracianluz:BAAANQAECggIDQAAAA==.Arak:BAAANQADCgIIAgAAAA==.Arce:BAAANQAECgQIBAABNQAECgoKPQAKAOgXAA==.Arysia:BAAANQAECgUIBgAAAA==.Aryya:BAAANQADCgIIAgAAAA==.',
As='Ascaris:BAABNQAECn8VAAIMAAgK6BbVjgD3AQAMAAgK6BbVjgD3AQAAAA==.',
Av='Avalan:BAABNQAECn9GAAQMAAoKyR7xQgDBAgAMAAoKph3xQgDBAgANAAYKjhu2GAClAQAOAAcKQB2mDACkAQAAAA==.Avanolatwo:BAAANQADCgYIBgABNQAECgoKLwAPADUZAA==.Avashammy:BAABNQAECn8vAAMPAAoKNRlNLgCoAgAPAAoKNRlNLgCoAgAQAAYKyhCJlABxAQAAAA==.Aviendah:BAABNQAECn8oAAIRAAoKgAoIawDSAQARAAoKgAoIawDSAQAAAA==.',
Aw='Awsomeonet:BAAANQAECggICAAAAA==.',
Az='Azdfghop:BAACNQAFFH8PAAMSAAgKHA8mCgCgAQASAAcKCgwmCgCgAQARAAIKcx54IACxAAA1AAQKfyYAAxIACgrqIkAWAKkCABIACQqsIUAWAKkCABEAAgqUI1YiAVkAAAAA.Azzinotica:BAAANQAECgUIBgAAAA==.',
Ba='Baalsanaro:BAAANQADCggIFQABNQAECgQIBQAFAAAAAA==.Babeshot:BAABNQAECn9LAAIRAAoKZw9MdAAoAgARAAoKZw9MdAAoAgAAAA==.Baelgar:BAAANQAECgMIAwAAAA==.',
Be='Bergur:BAAANQAECgYICwABNQAECgoKPAATAKgjAA==.',
Bi='Bigbear:BAAANQADCggICAABNQAECgcIFgAUACQRAA==.Biggy:BAAANQADCgIIAgAAAA==.Bignose:BAABNQAECn8bAAMHAAoKSiZ3AACNAwAHAAoKSiZ3AACNAwAGAAEKAACLuwEAAAABNQAFFAYIEwAVANomAA==.Binksy:BAAANQAECggICAAAAA==.',
Bl='Blaaze:BAAANQADCgYIBgAAAA==.Blackfrost:BAABNQAECn8aAAIWAAkKbA4HEQCWAQAWAAkKbA4HEQCWAQAAAA==.Blaiddyd:BAABNQAECn9AAAIRAAoKdR3DQwCgAgARAAoKdR3DQwCgAgAAAA==.',
Bo='Bomi:BAAANQAECgEIAQAAAA==.Boogereater:BAAANQAECgMIAgABNQAECgkJGAARAJoZAA==.',
Br='Brandawn:BAABNQAECn8VAAMHAAUKEg+jQACTAAAGAAUK1QbGNAHLAAAHAAQKEg+jQACTAAAAAA==.Bred:BAAANQADCggICAAAAA==.',
Bu='Burndasheep:BAABNQAECn9GAAQXAAoKfRMJagDOAQAXAAoKYRMJagDOAQAWAAIK4xNYKACJAAAYAAEKew0ZDQA6AAAAAA==.',
['Bæ']='Bæyy:BAABNQAECn8cAAIXAAYKCwpWygACAQAXAAYKCwpWygACAQAAAA==.',
Ca='Calyris:BAAANQADCgIIBAAAAA==.Caspias:BAEANQADCggIEgAAAA==.Caylynn:BAAANQAECgQIBwAAAA==.Caynelin:BAAANQAECgEIAQAAAA==.',
Ce='Cestbusiness:BAAANQADCgUIBQAAAA==.',
Ch='Chaoslock:BAABNQAECn8WAAIUAAcKJBHQFgC2AQAUAAcKJBHQFgC2AQAAAA==.Chetter:BAAANQAECggIBgAAAA==.Chicknfajita:BAAANQAECgcICQABNQAECgoKHAAQAEcgAA==.Chickpea:BAAANQAECgQIBwAAAA==.',
Ci='Civilian:BAAANQAECgYIBgABNQAECgoKNAACAEggAA==.',
Co='Cocytus:BAAANQAECgIIAQAAAA==.Colbith:BAABNQAECn8aAAIJAAcKYwx2YgBEAQAJAAcKYwx2YgBEAQAAAA==.Corblixx:BAAANQAECgEIAQAAAA==.Cordaddy:BAAANQAECggIDQABNQAECgkJLAAPANUlAA==.Cordelvo:BAAANQAECggIEAABNQAECgkJLAAPANUlAA==.Cordragon:BAAANQAECgIIBAABNQAECgkJLAAPANUlAA==.Cordragu:BAABNQAECn8sAAIPAAkK1SVEBACoAwAPAAkK1SVEBACoAwAAAA==.Cordran:BAAANQAECgEIAgABNQAECgkJLAAPANUlAA==.Corraa:BAAANQADCgEIAQAAAA==.',
Cr='Crakum:BAABNQAECn8XAAIQAAYKrRS0iwCHAQAQAAYKrRS0iwCHAQAAAA==.Crinn:BAABNQAECn8bAAMZAAcKDg3FagBnAQAZAAcKDg3FagBnAQAKAAIK3AN5owBHAAAAAA==.Crizmon:BAABNQAECn8eAAIKAAkKRx8MFQDkAgAKAAkKRx8MFQDkAgAAAA==.',
Cu='Cucumber:BAAANQAECgQIBAAAAA==.',
Da='Damorthyx:BAABNQAECn8hAAIaAAoKmhPlMQB1AQAaAAoKmhPlMQB1AQAAAA==.Darazarke:BAACNQAFFH8gAAMbAAgKAA2JBQAOAgAbAAgKAA2JBQAOAgAcAAEKLQVIDQA9AAA1AAQKfzIABBsACgqUGAcTAHwCABsACgqUGAcTAHwCAB0AAQqKFiYhAEgAABwAAQqCGMIZAEYAAAAA.Darkquill:BAABNQAECn8mAAIQAAoKOQ2LcwDGAQAQAAoKOQ2LcwDGAQAAAA==.Daspoof:BAAANQADCgYIBgAAAA==.Dayquil:BAEANQADCgcIBwABNQAFFAMIBgAGACUKAA==.',
De='Deadaddie:BAABNQAECn8bAAMKAAkKMRx8LgAuAgAKAAkKMRx8LgAuAgAZAAEKZhdH1gBCAAABNQAECgoKPgAXAMEiAA==.Deamoneyes:BAAANQAECgQIBgAAAA==.Deathkauf:BAAANQAECgEIAQAAAA==.Deathvok:BAAANQADCgMIAwAAAA==.Demolitions:BAAANQAECggICAAAAA==.Dezatra:BAAANQADCgcIBgAAAA==.',
Dh='Dhonaan:BAAANQAECgQIAQAAAA==.',
Di='Dieselcon:BAACNQAFFH8GAAIHAAQKUgZ0CACWAAAHAAQKUgZ0CACWAAA1AAQKf0kAAwcACgqvFTIRAAECAAcACgqvFTIRAAECAAYABAr+BdRKAagAAAAA.Diprivan:BAABNQAECn9EAAMeAAoK+SDZEQDuAgAeAAoK9BzZEQDuAgAfAAkKmx/OGwCYAgAAAA==.',
Dk='Dkbabe:BAAANQAECgEIAQAAAA==.',
Do='Dolobrik:BAAANQABCgYIBwAAAA==.Domdog:BAABNQAECn8dAAIXAAcKvgdJBQGFAQAXAAcKvgdJBQGFAQAAAA==.Domína:BAAANQAECgYICgAAAA==.Dontforget:BAAANQAECggIEwAAAA==.Doomdealer:BAABNQAECn8yAAMKAAoK4BAvLgDfAQAKAAoK4BAvLgDfAQAaAAEKAACKugBSAAAAAA==.Doomed:BAABNQAECn8gAAILAAgKYCFvJgDQAgALAAgKYCFvJgDQAgABNQAECgkJJwAgAHodAA==.Doonya:BAAANQAECgIIAgAAAA==.Dottee:BAAANQAECggIAwAAAA==.Dougwalker:BAAANQADCgIIAgAAAA==.',
Dr='Dracodaddy:BAAANQADCgIIAgAAAA==.Draftymonk:BAABNQAECn8XAAMVAAcKMR9QCgBxAgAVAAYK6SNQCgBxAgAhAAMKLBAwUQCuAAABNQAECgoKIgAaAKYfAA==.Drage:BAABNQAECn9BAAMiAAoK0hcCRACGAgAiAAoK0hcCRACGAgAUAAEKdgMvhQAkAAAAAA==.Drax:BAABNQAECn8pAAMjAAoKfQt/DwBWAQAiAAoKmgiMogCQAQAjAAcKvQt/DwBWAQAAAA==.Dreadgar:BAAANQAECgQIBQABNQAECgoKKAAQAPIgAA==.Dritzzagain:BAAANQAECgUIDAAAAA==.Dritzzcat:BAAANQADCgYICwAAAA==.',
Dw='Dwreck:BAAANQAECgcIDgAAAA==.',
Ed='Ediann:BAAANQAECggIDgAAAA==.',
El='Elandrus:BAAANQAECgUICgABNQAECgoKMAAXANUUAA==.Eldarine:BAAANQADCgUIBQAAAA==.Elishiveth:BAAANQAECgYICgAAAA==.',
Em='Emmara:BAABNQAECn8jAAISAAoKVQOEMADZAAASAAoKVQOEMADZAAAAAA==.',
En='Enitar:BAAANQADCgcICAABNQAECgoKRgAXAH0TAA==.',
Er='Erata:BAABNQAECn8jAAIjAAcKsgbJFADRAAAjAAcKsgbJFADRAAAAAA==.Erlik:BAAANQADCgMIBAAAAA==.Erzakzaktraz:BAAANQADCgYIBgABNQADCgcIBgAFAAAAAA==.',
Et='Etuba:BAAANQAECgEIAgAAAA==.',
Ev='Evullight:BAAANQADCgEJAQAAAA==.',
Ez='Ezlok:BAABNQAECn8oAAIQAAoK8iCOGACYAgAQAAoK8iCOGACYAgAAAA==.',
Fa='Facemash:BAAANQAECgQIBAABNQAECgoKRgAXAH0TAA==.Fae:BAAANQABCgUIBQAAAA==.Faedra:BAAANQADCggIFAABNQABCgUIBQAFAAAAAA==.Faelyn:BAAANQADCgIIAgABNQABCgUIBQAFAAAAAA==.Falerin:BAABNQAECn8wAAIEAAoK4Rt0GAB7AgAEAAoK4Rt0GAB7AgAAAA==.Farryn:BAAANQADCgEIAQAAAA==.',
Fe='Feenex:BAABNQAECn8aAAIZAAgK1g0IMgBLAQAZAAgK1g0IMgBLAQAAAA==.Feldora:BAAANQADCgYIBgAAAA==.Festiva:BAAANQAECgIIBAAAAA==.',
Fi='Fillorey:BAAANQADCggICAABNQAECgoKMAAXANUUAA==.Firedealer:BAABNQAECn9FAAMSAAoKmxXtDwAwAgASAAoKmxXtDwAwAgARAAQKbxKN8gAcAQAAAA==.',
Fl='Flappy:BAAANQAECgIIBAABNQAECgkJNgAPACYbAA==.Flashmaster:BAAANQAFFAEIAQAAAA==.Flawlessheal:BAAANQADCgMIAwAAAA==.Flora:BAAANQADCgIIAgABNQABCgUIBQAFAAAAAA==.Fluffybutt:BAAANQADCggIFAAAAA==.',
Fo='Fossora:BAAANQADCgcIBgAAAA==.Foxygrandpa:BAAANQADCgUIBwAAAA==.',
Fr='Freyiah:BAAANQADCgYIBgAAAA==.',
Fy='Fyatre:BAAANQAECgYIDwAAAA==.',
Ga='Galadran:BAAANQABCgIIAgAAAA==.Galath:BAAANQAECgUJCAABNQAECgMIAwAFAAAAAA==.Gandallf:BAAANQADCgUIBQAAAA==.',
Ge='Gerree:BAAANQADCgYICgAAAA==.Gerry:BAABNQAECn8kAAIIAAoK4Rd6AwBYAgAIAAoK4Rd6AwBYAgAAAA==.',
Gg='Ggkando:BAABNQAECn8lAAIRAAkKxQxCaQDXAQARAAkKxQxCaQDXAQAAAA==.',
Gh='Ghemaldir:BAAANQABCgIIAgAAAA==.',
Gi='Gildius:BAAANQADCgIIAgAAAA==.Gingerail:BAAANQAECgQICQAAAA==.',
Gl='Glory:BAABNQAECn8mAAIaAAoK6Rw9IwCdAgAaAAoK6Rw9IwCdAgAAAA==.',
Gn='Gnayami:BAAANQADCgcIDwAAAA==.',
Go='Goochsquirts:BAABNQAECn8fAAIPAAgKRxsOUAAlAgAPAAgKRxsOUAAlAgAAAA==.Govna:BAAANQADCggIFAAAAA==.',
Gr='Grakkaem:BAAANQAECgMIBAAAAA==.Grannet:BAAANQAECgEIAQAAAA==.Gravedygger:BAABNQAECn9NAAIRAAoKqBfrSgCNAgARAAoKqBfrSgCNAgAAAA==.Greenfear:BAAANQADCgYIDAAAAA==.Grenswood:BAAANQAECgcIEgAAAA==.Greybeeredd:BAAANQAECgIIBAAAAA==.Grimmkin:BAABNQAECn8sAAQkAAoKOxpKCwC8AgAkAAoKOxpKCwC8AgAPAAIKrA8e/gBuAAAQAAEKAACtQwEsAAAAAA==.Grind:BAAANQAECgQIBAABNQAECgcIEQAFAAAAAA==.Growl:BAAANQAECgEIAgAAAA==.Grumbo:BAAANQADCgcIBgAAAA==.',
Gu='Gunnerr:BAAANQAECgEIAQABNQAECgEIAQAFAAAAAA==.Guuldurak:BAAANQADCgcIBgAAAA==.',
Ha='Hailcat:BAAANQAECgMIBAABNQAECgoKJAAiAC0PAA==.Handivhe:BAAANQADCgYIBgAAAA==.Hasew:BAABNQAECn9UAAIRAAoKKCKYHADDAgARAAoKKCKYHADDAgAAAA==.',
He='He:BAAANQAECgcIDwABNQAECgoKPQAKAOgXAA==.Hellanor:BAAANQABCgUICQAAAA==.Helpimßlind:BAABNQAECn8jAAIlAAoKfxevFAAJAgAlAAoKfxevFAAJAgAAAA==.Hera:BAACNQAFFH8XAAIRAAYK5iS8AwCzAQARAAYK5iS8AwCzAQA1AAQKfzUAAhEACgq2Jh4EAMcDABEACgq2Jh4EAMcDAAAA.Heyner:BAABNQAECn9PAAMmAAoKeh0iAQCnAgAmAAoKeh0iAQCnAgAfAAgKvg1QZQBcAQAAAA==.',
Hi='Hinral:BAACNQAFFH8XAAIgAAYK9RtpAgD9AQAgAAYK9RtpAgD9AQA1AAQKfzgAAiAACgoyJKACAJMDACAACgoyJKACAJMDAAAA.Hiya:BAAANQADCgIIAgABNQAECgoKPQAKAOgXAA==.',
Ho='Holyiaa:BAAANQAECggIEwABNQAECggIFgAbAGQGAA==.Holyluz:BAAANQAECgYICgABNQAECggIDQAFAAAAAA==.Holysmacker:BAAANQAECgUIBQABNQAECgkJIAAWAC4ZAA==.',
Hy='Hymns:BAAANQAECggIAgAAAA==.',
['Hë']='Hëll:BAABNQAECn8kAAMiAAoKLQ9acwAHAgAiAAoKLQ9acwAHAgAUAAEKGRC/cwA7AAAAAA==.',
Il='Illaynne:BAABNQAECn87AAMBAAoK2xfUMwBbAgABAAoK2xfUMwBbAgACAAEKAgkXXQA2AAAAAA==.',
Im='Imani:BAACNQAFFH8WAAIkAAUKFgVOBADGAAAkAAUKFgVOBADGAAA1AAQKfzUAAiQACgpeDhgVABcCACQACgpeDhgVABcCAAAA.Immensepain:BAAANQAECgUIBAAAAA==.',
In='Inoshikacho:BAABNQAECn8uAAInAAoKSgwNFABqAQAnAAoKSgwNFABqAQAAAA==.Involio:BAAANQAECgEIAQAAAA==.',
Ir='Irishmecha:BAACNQAFFH8UAAIeAAYKIBEqAwAxAQAeAAYKIBEqAwAxAQA1AAQKfzQAAh4ACgrEIVIMAPsBAB4ACgrEIVIMAPsBAAAA.Irishpaws:BAAANQAECgEIAQAAAA==.Ironshot:BAAANQADCggIBgAAAA==.',
Is='Isaeus:BAAANQAECgEIAQAAAA==.',
It='Itharillys:BAABNQAECn8tAAIRAAoK+BPrcwAoAgARAAoK+BPrcwAoAgAAAA==.',
Ja='Jaadu:BAAANQADCgQIBAAAAA==.Jangus:BAABNQAECn8ZAAIdAAYK2BFzEAAfAQAdAAYK2BFzEAAfAQABNQAECgcIEQAFAAAAAA==.Jaybone:BAAANQAECgIIAQAAAA==.',
Je='Jeefus:BAAANQAECggIAgAAAA==.Jeennkiins:BAAANQADCgYIBgABNQAECgYICQAFAAAAAA==.Jenifur:BAAANQAECgIIAwABNQABCgUIBQAFAAAAAA==.Jessibella:BAAANQADCgQIBAAAAA==.Jezzako:BAAANQAECgcIEAAAAA==.',
Ji='Jingles:BAAANQABCgMIAwAAAA==.Jinx:BAAANQADCggIEgABNQABCgUIBQAFAAAAAA==.',
Jo='Johali:BAAANQAECggIEgAAAA==.Jozan:BAAANQADCgcIHwAAAA==.',
Ju='Justise:BAAANQADCgIIAgABNQADCgYJCwAFAAAAAA==.Jutojerry:BAABNQAECn8nAAIgAAkKeh1VBgAVAwAgAAkKeh1VBgAVAwAAAA==.',
Jz='Jz:BAAANQAECggICgABNQAECgoKPQAKAOgXAA==.',
['Jö']='Jöhnblaze:BAABNQAECn9JAAMMAAoKKRKjUwDxAQAMAAoKKRKjUwDxAQANAAcKKg2fGwAQAQAAAA==.',
Ka='Kaga:BAAANQADCgEJAQABNQAECgoKRgAXAH0TAA==.Kailys:BAABNQAECn82AAIHAAoKWxLpGgCEAQAHAAoKWxLpGgCEAQAAAA==.Kaisana:BAAANQAECgYICwAAAA==.Kaishias:BAABNQAECn8wAAMHAAkKaxiKFQC+AQAGAAkKaxi+XgAFAgAHAAgKaxWKFQC+AQAAAA==.Kaldrek:BAAANQAECgMIBgABNQAECgoKKQAGAMgXAA==.Kandoh:BAAANQADCggIEwABNQAECgkJJQARAMUMAA==.Kanimeh:BAAANQAECgEIAQAAAA==.Kankuró:BAACNQAFFH8IAAIRAAIKqBtlHQCgAAARAAIKqBtlHQCgAAA1AAQKf0kAAhEACgqiIacUAO4CABEACgqiIacUAO4CAAAA.Karelleira:BAAANQADCgUIBQAAAA==.Kautie:BAABNQAECn8cAAILAAoKJR0rEAAvAwALAAoKJR0rEAAvAwAAAA==.',
Ki='Killahmike:BAAANQAECgQIBgAAAA==.Killudead:BAABNQAECn8bAAIGAAoKgBjsPgBfAgAGAAoKgBjsPgBfAgAAAA==.Kishana:BAAANQADCgcIBgAAAA==.',
Ko='Kodetra:BAABNQAECn8eAAIcAAgKMwxMDAAcAQAcAAgKMwxMDAAcAQAAAA==.Kolgrim:BAABNQAECn86AAMaAAoKsh2dDgCpAgAaAAoKsh2dDgCpAgAKAAkKlhG6PQDVAQAAAA==.Kong:BAAANQAECgIIAgAAAA==.Korvuk:BAABNQAECn8pAAMGAAoKyBduSABBAgAGAAoKyBduSABBAgALAAoKKBC5QgD2AQAAAA==.',
Kr='Kristafur:BAAANQADCggIDgABNQABCgUIBQAFAAAAAA==.Krom:BAABNQAECn8qAAMPAAoKqgaGdAA/AQAPAAoKqgaGdAA/AQAQAAgKBBBCfwD8AAAAAA==.Krysta:BAABNQAECn9DAAMBAAoKeiG/FAAfAwABAAoKeiG/FAAfAwACAAEKAACegQAoAAABNQABCgUIBQAFAAAAAA==.',
Ky='Kynris:BAAANQADCggIEQABNQAECgoKMAAXANUUAA==.',
La='Lanaal:BAAANQADCgEIAQAAAA==.Lancewh:BAAANQADCgcIDAAAAA==.Lanciwinluna:BAAANQADCgQIBAAAAA==.Lancywinelia:BAAANQADCgQIBgAAAA==.Lauryssa:BAAANQADCggICAAAAA==.',
Ld='Ldydthstryke:BAAANQAECgYIBgABNQAECgoKRQASAJsVAA==.',
Le='Legg:BAAANQABCgMIAwAAAA==.Legolâs:BAAANQADCgUIBQAAAA==.Leonora:BAABNQAECn8WAAISAAgK8wSWQABQAQASAAgK8wSWQABQAQAAAA==.Leviathañ:BAAANQADCgIIAgABNQAECgcIDgAFAAAAAA==.Lezene:BAAANQAECgUICwAAAA==.',
Li='Linstriker:BAABNQAECn8yAAIoAAkKiCFkCgDKAgAoAAkKiCFkCgDKAgABNQAFFAcIFQAPANEeAA==.',
Lo='Lockbone:BAAANQAECgIIAQAAAA==.Lorette:BAABNQAECn9AAAMBAAoKJCA6FAAkAwABAAoKJCA6FAAkAwACAAoKBBsRIAA6AgAAAA==.Lorzik:BAAANQABCgQIAwAAAA==.',
Lu='Lucethegoose:BAAANQADCgQIBAAAAA==.Luckynyx:BAAANQAECgcICQAAAA==.Lunate:BAAANQAECgEIAQABNQAECgoKNAACAEggAA==.',
Ma='Machotedan:BAABNQAECn9EAAIGAAoKMyIaHwDcAgAGAAoKMyIaHwDcAgAAAA==.Macmittens:BAAANQAECggICAAAAA==.Makoes:BAAANQADCgYIBgAAAA==.Mamadrag:BAABNQAECn8WAAIbAAgKZAbpHAAbAQAbAAgKZAbpHAAbAQAAAA==.Managua:BAAANQADCgEIAQAAAA==.Mandwa:BAAANQADCggIGAABNQAECgoKRgAXAH0TAA==.Mangojuulpod:BAAANQAECgYIBwABNQAECgkJJwAgAHodAA==.Mario:BAABNQAECn8gAAIWAAkKLhl9CgDfAQAWAAkKLhl9CgDfAQAAAA==.Mastashifta:BAAANQAECgUIEAAAAA==.Mataa:BAABNQAECn8wAAIXAAoK1RTVjAB6AQAXAAoK1RTVjAB6AQAAAA==.Matryoshka:BAAANQADCgUIDQABNQAECgIIAgAFAAAAAA==.Mattsadler:BAAANQAECgIIAQAAAA==.Maxxim:BAAANQAECgIIAgAAAA==.Mayihmpurleg:BAAANQAECgUIBQABNQAECgoKRQASAJsVAA==.Mazeman:BAAANQADCgUIBQAAAA==.',
Me='Meilin:BAAANQAECgMIAwAAAA==.Mellachion:BAAANQAECgYICAABNQAECgkJIAAWAC4ZAA==.Meta:BAABNQAECn8fAAIpAAoKUBdRIQDrAQApAAoKUBdRIQDrAQABNQAECgoKRAAeAPkgAA==.',
Mi='Mistaya:BAAANQADCgUIBQABNQAECgkJKAAiAG0JAA==.Mists:BAABNQAFFH8FAAMiAAUK4BHIFwA2AQAiAAQKABjIFwA2AQAUAAEKoAUQIgBFAAAAAA==.Miththrawndo:BAABNQAECn8zAAIaAAoKXw4LVACkAQAaAAoKXw4LVACkAQABNQAFFAQIBgAHAFIGAA==.',
Mo='Moadib:BAAANQAECgUIBQAAAA==.Momjeans:BAABNQAECn84AAIXAAoKNR4nOwBPAgAXAAoKNR4nOwBPAgAAAA==.',
Mu='Mumbo:BAAANQADCgcIBwABNQAECgcIEQAFAAAAAA==.Muu:BAAANQADCgYICAAAAA==.',
My='Mydaan:BAAANQADCgIIAwAAAA==.Mythunsarian:BAABNQAECn8kAAIpAAoKZwwMKwChAQApAAoKZwwMKwChAQAAAA==.',
['Má']='Mákï:BAABNQAECn8aAAIMAAgKNBCHkQDwAQAMAAgKNBCHkQDwAQAAAA==.',
['Mä']='Mäylä:BAABNQAECn8xAAMJAAoKNg1mLwBzAQAJAAoKNg1mLwBzAQAEAAEKlA4EdgApAAAAAA==.',
['Mí']='Míst:BAABNQAECn9KAAIGAAoK4RjpXgB8AgAGAAoK4RjpXgB8AgAAAA==.',
Na='Narlis:BAABNQAECn8wAAIZAAoKriM7CgBrAwAZAAoKriM7CgBrAwAAAA==.Nautprepared:BAAANQAECgMIAQABNQAECgkJJwAgAHodAA==.',
Ne='Nephie:BAAANQAECgYICwAAAA==.Nezqk:BAACNQAFFH8VAAQKAAYKIA0ECgAQAQAKAAUKFg0ECgAQAQAZAAIKlxHyFwCaAAAaAAEKAACZMQAAAAA1AAQKfzEABBkACgpjHPcyAF8CABkACQpuHPcyAF8CABoACAqQEvZOALkBAAoABwr3F1JHAGMBAAAA.Nezquick:BAAANQAECgIIAgAAAA==.',
Ni='Niano:BAAANQABCgIIAgAAAA==.',
Nm='Nmnenthe:BAABNQAECn8uAAIdAAoKJhX1BgAcAgAdAAoKJhX1BgAcAgAAAA==.',
No='Notrealword:BAABNQAECn8WAAMHAAcK7RD8LwDoAAAGAAcK+gjL0QAfAQAHAAUK1BP8LwDoAAABNQAECgoKVAARACgiAA==.Noxluminous:BAAANQABCgIIAgAAAA==.',
Ob='Obin:BAABNQAECn8yAAMMAAkKqhFrfQB5AQAMAAgKiRBrfQB5AQAOAAcKaA+3GgD6AAAAAA==.',
Oc='Occasionally:BAAANQAECgIIAgAAAA==.',
Ok='Okukoy:BAAANQABCgEIAQAAAA==.',
Om='Ominious:BAABNQAECn8oAAMkAAoKvxIuFAAmAgAkAAkKJxEuFAAmAgAQAAUKtRcBqgBAAQABNQAECggIEAAFAAAAAA==.Omnissia:BAAANQAECgUIAwABNQAECggIEAAFAAAAAA==.Omnius:BAABNQAECn8fAAMQAAoKMhxeYAAAAgAQAAoKMhxeYAAAAgAPAAEKMAu9KQEkAAAAAA==.Omnya:BAAANQAECgcIDQABNQAECggIEAAFAAAAAA==.Omnyi:BAAANQAECggIEAAAAA==.',
Ow='Owendriel:BAACNQAFFH8LAAIlAAUKNQxCCQDEAAAlAAUKNQxCCQDEAAA1AAQKfxkAAyUACgq9FR0oAAMCACUACQpiFB0oAAMCACkAAwrpEglxALUAAAAA.',
Pa='Paindya:BAABNQAECn8WAAIkAAcKTQ0CGAB4AQAkAAcKTQ0CGAB4AQAAAA==.Paleigh:BAAANQABCgYICwAAAA==.Palivok:BAAANQAECgUIBwAAAA==.Pandress:BAABNQAECn8ZAAIRAAgKjgxYxwBzAQARAAgKjgxYxwBzAQAAAA==.Pankake:BAAANQAECgQIBAABNQAECgoKPAATAKgjAA==.Paralysis:BAACNQAFFH8XAAIlAAYK/RR2BAAyAQAlAAYK/RR2BAAyAQA1AAQKfzQAAiUACgq1HSEeAGACACUACgq1HSEeAGACAAAA.Parody:BAAANQAECgEIAQABNQAECgIIBAAFAAAAAA==.',
Pe='Peetza:BAAANQADCgYIBgABNQAECgoKPAATAKgjAA==.Peryite:BAABNQAECn9LAAMBAAoK6BllMgBiAgABAAoK6BllMgBiAgADAAUKFRY2CQAIAQAAAA==.',
Ph='Phaedrana:BAAANQAECgcIDgAAAA==.',
Pi='Pisscat:BAABNQAECn8ZAAIoAAcKhQLbTAB4AAAoAAcKhQLbTAB4AAAAAA==.Pixsil:BAAANQADCgQIBAAAAA==.',
Po='Pocketdragon:BAABNQAECn8tAAMdAAoKZxUhDwBpAgAdAAoKchQhDwBpAgAcAAYKWhBOEAA1AQAAAA==.Polymerase:BAAANQAECgQIBAABNQAECgoKRQAZAM0hAA==.',
Pr='Prideindeath:BAAANQAECgYICQAAAA==.Promiscuity:BAABNQAECn82AAMiAAoKaxrvJQBqAgAiAAoKaxrvJQBqAgAjAAIKwwlCIgBpAAABNQAECgoKRAAeAPkgAA==.Prængle:BAAANQADCgYIAwAAAA==.',
Ps='Psoas:BAABNQAECn80AAMCAAoKSCAnCABaAwACAAoKSCAnCABaAwABAAIK4BBH5AB7AAAAAA==.Psypriest:BAECNQAFFH8OAAIBAAYKUhl7CAASAgABAAYKUhl7CAASAgA1AAQKf0QAAgEACgpeIncGAL0DAAEACgpeIncGAL0DAAE1AAUUCAgjAAEAXA8A.',
Py='Pyroheal:BAAANQAECggICwAAAA==.',
Qu='Quaichang:BAAANQADCgYIBgAAAA==.',
Ra='Rabbi:BAABNQAECn84AAMCAAoKXxrkEgDTAgACAAoKXxrkEgDTAgABAAMKiiBEjgAWAQAAAA==.Rahfna:BAAANQADCgcIDwAAAA==.Railænu:BAAANQADCggIDgAAAA==.Rainmist:BAAANQAECgUIBgAAAA==.Ranric:BAAANQAECgMIAwAAAA==.',
Re='Redall:BAAANQAECgIIAgAAAA==.Reesespbc:BAAANQAECgYIDQAAAA==.Reina:BAABNQAECn8YAAQHAAgK7Q3KLQD1AAAHAAcKKQ/KLQD1AAAGAAMKNgjicQFsAAALAAEKQQXgLAEqAAABNQABCgUIBQAFAAAAAA==.Reinz:BAABNQAECn8iAAQVAAoKoiKXAQAhAwAVAAoKoiKXAQAhAwAhAAIKmQntXgBkAAAgAAEK4AYkQQAhAAAAAA==.Rektagar:BAABNQAECn88AAMQAAoKyiTUBQC8AwAQAAoKyiTUBQC8AwAPAAEKbwsm8QAyAAABNQAFFAgIHgARAKshAA==.Ressandra:BAAANQADCgMIBgAAAA==.Rezo:BAAANQAECgEIAgAAAA==.',
Ri='Riverarose:BAAANQADCggIFQAAAA==.',
Ro='Roar:BAAANQAECgYIEgABNQAECgcIEQAFAAAAAA==.',
Ry='Rysi:BAAANQADCgQIBAAAAA==.',
['Rò']='Ròs:BAACNQAFFH8ZAAIHAAYKohgrAwA7AQAHAAYKohgrAwA7AQA1AAQKfzUAAgcACgrCIUcKAPYCAAcACgrCIUcKAPYCAAAA.',
['Rö']='Rös:BAAANQADCgEIAQABNQAFFAYIGQAHAKIYAA==.',
Sa='Saberie:BAAANQADCggIFwABNQADCgMIBgAFAAAAAA==.Salaria:BAABNQAECn8rAAIlAAoKcw75MwCjAQAlAAoKcw75MwCjAQAAAA==.Salina:BAABNQAECn8WAAITAAgKJBV5EACqAQATAAgKJBV5EACqAQAAAA==.Sandstique:BAABNQAECn8xAAIPAAoKZyQpEwAxAwAPAAoKZyQpEwAxAwAAAA==.Sandweaver:BAAANQADCgcIBwAAAA==.Sanjira:BAAANQADCgYIBgAAAA==.Sarlak:BAABNQAECn84AAMRAAoKtB05JQACAwARAAoKtB05JQACAwASAAEK8AYalwAqAAAAAA==.Sarusuby:BAABNQAECn9TAAIoAAoKzBGKGADpAQAoAAoKzBGKGADpAQAAAA==.Satae:BAABNQAECn88AAITAAoKqCOBAgBZAwATAAoKqCOBAgBZAwAAAA==.',
Sc='Schufft:BAABNQAECn8aAAIUAAcKzBuCCAB1AgAUAAcKzBuCCAB1AgAAAA==.Scottydh:BAAANQAECgIIAgABNQAECgoKRQAaAE0hAA==.Scottymac:BAABNQAECn9FAAIaAAoKTSFIDwA0AwAaAAoKTSFIDwA0AwAAAA==.Scottypal:BAAANQAECgQIBQABNQAECgoKRQAaAE0hAA==.',
Se='Seatah:BAAANQAECgMIAwAAAA==.Seba:BAABNQAECn8nAAIQAAoK/BWvMQD8AQAQAAoK/BWvMQD8AQAAAA==.Seeta:BAAANQAECgIIAgAAAA==.Seetah:BAABNQAECn8lAAMBAAoK6RNvWQAVAgABAAoK6RNvWQAVAgACAAIK6wyOZwBiAAAAAA==.Seraphtharia:BAAANQABCgIIAgAAAA==.Sermon:BAAANQADCgQIBAABNQAECgcIEQAFAAAAAA==.',
Sh='Shadaddy:BAABNQAECn8+AAMXAAoKwSIZUgDcAgAXAAkKoyIZUgDcAgAWAAMKjiChGAACAQAAAA==.Shadowheart:BAAANQAECgQIBQAAAA==.Shakasana:BAAANQAECgIIAQAAAA==.Shal:BAABNQAECn81AAIMAAoKUBpuRwAZAgAMAAoKUBpuRwAZAgAAAA==.Shamanluz:BAAANQADCgIIAgABNQAECggIDQAFAAAAAA==.Shamommy:BAAANQADCgUIBAAAAA==.Shamtaz:BAAANQAECgUICgAAAA==.Shimmerstar:BAABNQAECn8cAAIGAAkKYR0pcQBNAgAGAAkKYR0pcQBNAgAAAA==.Shroomgirl:BAAANQAECgUIBQAAAA==.Shrubhub:BAAANQAECgEIAQABNQAECgkJJwAgAHodAA==.',
Si='Silexe:BAABNQAECn8nAAMcAAgKERVsDQB3AQAcAAcKCRVsDQB3AQAdAAYK8hTQDgBCAQAAAA==.Sitga:BAAANQADCgIIAgAAAA==.',
Sk='Skåld:BAAANQADCgUIAwAAAA==.',
Sl='Slinga:BAAANQADCgcICQAAAA==.Slipperyboi:BAAANQAECgQICQAAAA==.Slÿ:BAAANQAECgIIAgAAAA==.',
So='Solarion:BAAANQAECgYIDwABNQAECgoKKAAQAPIgAA==.Soldraca:BAAANQAECgMIAwAAAA==.',
St='Stabbirabbi:BAAANQAECgQIAgAAAA==.Stats:BAAANQAECgcIEQAAAA==.Stinkbug:BAAANQADCgQIBAAAAA==.Stutters:BAABNQAECn9FAAMZAAoKzSHhBwDuAgAaAAoKrRz8FgD1AgAZAAoKoCDhBwDuAgAAAA==.',
Su='Subayyru:BAAANQADCgEIAQABNQAECgYIHAAXAAsKAA==.Sudachi:BAAANQADCgYIBgABNQAFFAcKFAAhACscAA==.Sunnyräy:BAAANQAECgMIAwAAAA==.Superiorkill:BAAANQADCgcIBwAAAA==.Suthrheimr:BAABNQAECn9CAAIOAAoKgRxCBQB0AgAOAAoKgRxCBQB0AgABNQAECgoKJAAIAOEXAA==.',
['Sý']='Sýndrá:BAAANQAECgYIDQAAAA==.',
Ta='Talespin:BAAANQAECgUIBQAAAA==.Talysiah:BAABNQAECn8oAAIiAAkKbQnVdQBlAQAiAAkKbQnVdQBlAQAAAA==.Talzind:BAAANQADCgIIAgAAAA==.Tavok:BAABNQAECn84AAIOAAoKAB1bBgCnAgAOAAoKAB1bBgCnAgAAAA==.Tazbis:BAAANQAECgQIBgAAAA==.',
Te='Teishuku:BAABNQAECn9QAAIGAAoKiRMAZwDxAQAGAAoKiRMAZwDxAQAAAA==.Teusday:BAABNQAECn89AAMKAAoK6BfhOADxAQAKAAoK6BfhOADxAQAaAAQKRgaXeABuAAAAAA==.',
Th='Thiux:BAABNQAECn85AAMiAAoKNSCWKQBaAgAiAAkKiiCWKQBaAgAUAAIKYB9vRACzAAAAAA==.Thoeleden:BAAANQAECgMIBgABNQAFFAcIFQAPANEeAA==.Thotsnprayrs:BAAANQAECgMIBgABNQAECgkJJwAgAHodAA==.Thrappy:BAABNQAECn82AAMPAAkKJhseRgBJAgAPAAkKJhseRgBJAgAQAAcK1w9hogBRAQAAAA==.Thryna:BAAANQADCgEIAQAAAA==.Thugstyle:BAAANQABCgcIDgAAAA==.',
Ti='Tinsoon:BAAANQAECgUIBQAAAA==.Tintaglia:BAABNQAECn9EAAMiAAoKjxpxLQBKAgAiAAoKjxpxLQBKAgAjAAEKZBHPMQAxAAABNQAECgkJIAAWAC4ZAA==.Tirtun:BAABNQAECn9QAAIWAAoK+SA9AgBQAwAWAAoK+SA9AgBQAwAAAA==.',
Tr='Triggeer:BAABNQAECn8sAAINAAoKEhgMDADrAQANAAoKEhgMDADrAQAAAA==.Trolldemort:BAAANQADCgYIBgABNQAECgoKJgAiADQYAA==.',
Tu='Tully:BAABNQAECn8fAAIRAAYKxgMM3QDbAAARAAYKxgMM3QDbAAAAAA==.Tunkhan:BAAANQADCgQIBwAAAA==.Turnaround:BAAANQABCgIIAgAAAA==.',
Tw='Twelvekill:BAACNQAFFH8XAAIRAAYKxBZHBwBjAQARAAYKxBZHBwBjAQA1AAQKfzIAAhEACgpgIa4nAPkCABEACgpgIa4nAPkCAAAA.',
Ty='Tyliaa:BAABNQAECn9EAAMPAAoKvxtcLwCkAgAPAAoKvxtcLwCkAgAQAAkKtxBWSwCSAQABNQAECggIFgAbAGQGAA==.',
Ul='Ultramon:BAABNQAECn8pAAIGAAoKhBOygwAgAgAGAAoKhBOygwAgAgAAAA==.',
Un='Unbreakabull:BAAANQAECgEIAQAAAA==.Unwell:BAABNQAECn80AAIlAAoKkRs9EQA4AgAlAAoKkRs9EQA4AgAAAA==.',
Ur='Urgoochness:BAAANQADCgQIBAAAAA==.Urikhai:BAAANQADCggIAgAAAA==.',
Va='Vainglorious:BAAANQADCggIEwABNQAECgoKJgAaAOkcAA==.Valanora:BAABNQAECn9AAAIjAAoKLBbqBQAHAgAjAAoKLBbqBQAHAgAAAA==.Valerie:BAAANQAECggICwABNQAECgoKPwASAH4fAA==.Valianya:BAAANQABCgMIAwAAAA==.Valinaxius:BAABNQAECn8UAAMaAAYK8xCTXwC5AAAaAAUKsRSTXwC5AAAKAAIKuAWlsAAwAAAAAA==.Vanyr:BAAANQAECgEIAQAAAA==.Vapturov:BAAANQAECgUIEAAAAA==.',
Ve='Veeks:BAABNQAECn9DAAIQAAoKvwzURACqAQAQAAoKvwzURACqAQAAAA==.Velibast:BAAANQAECgQIBAAAAA==.Velikirn:BAABNQAECn80AAMhAAoKEiFzBwDrAgAhAAkKEiFzBwDrAgAVAAkKKRZPDwD8AQAAAA==.Velimald:BAAANQAECgQIBAAAAA==.Velydia:BAAANQAECgYIBgAAAA==.Venefica:BAAANQAECgEIBAAAAA==.Verdracee:BAAANQABCgMIAwABNQAECgYIHAATAJ0EAA==.Versø:BAABNQAECn8eAAMeAAgK/BRhPgDVAQAeAAgK/BRhPgDVAQAfAAEKAAAiUwA1AAAAAA==.Veryzi:BAAANQAECgEIAgAAAA==.',
Vi='Vine:BAAANQADCgQIBQABNQAECgoKRAAeAPkgAA==.',
Vl='Vlyrae:BAAANQADCgMIAwAAAA==.',
Vo='Voidbreaker:BAAANQADCgcIBwAAAA==.Voidhearted:BAABNQAECn9NAAICAAoKGxBGIwAYAgACAAoKGxBGIwAYAgAAAA==.Vonzuo:BAAANQAECgIIAgAAAA==.',
Vu='Vukodlak:BAAANQADCgcIDQABNQAECgkJIAAWAC4ZAA==.',
['Vì']='Vìolet:BAAANQADCgMIAwABNQAECgkJNAAJALAfAA==.',
Wa='Warriorwuu:BAAANQABCgIIAgAAAA==.Wayshua:BAAANQADCgYIBgAAAA==.',
We='Werkajerk:BAAANQADCggICAABNQAFFAcIFQAPANEeAA==.Werkjathal:BAACNQAFFH8VAAIPAAcK0R53BgD8AQAPAAcK0R53BgD8AQA1AAQKfzcAAw8ACgpwJjkBANcDAA8ACgpwJjkBANcDABAABgq4H4A+AMQBAAAA.',
Wi='Wibbles:BAAANQADCgcICwAAAA==.Wigarthan:BAAANQADCgEIAQAAAA==.Wildsenpai:BAAANQADCgEIAgAAAA==.',
Wo='Wolfblitzer:BAABNQAECn85AAMGAAoKMBm/WAAUAgAGAAoKMBm/WAAUAgALAAYKyQJSrgCuAAAAAA==.Wolfmanbro:BAAANQADCgMIAwAAAA==.Wolfpride:BAAANQADCgUIBQAAAA==.Worgenator:BAAANQADCgMIAwAAAA==.Worldbane:BAABNQAECn8oAAIUAAoKJA6VBwBGAQAUAAoKJA6VBwBGAQAAAA==.',
Wr='Wraithlash:BAAANQAECggIDgAAAA==.',
Wu='Wuu:BAAANQABCgIIAgAAAA==.Wuulock:BAAANQABCgEJAQAAAA==.',
Wy='Wynnhrt:BAAANQADCggICAAAAA==.',
Xa='Xalatath:BAABNQAECn82AAMBAAoKJRz/FQAWAwABAAoKJRz/FQAWAwACAAEKAAC+bQAAAAAAAA==.Xanakmando:BAAANQADCggIFQAAAA==.Xandertay:BAAANQADCgMIBQAAAA==.Xanthos:BAAANQADCgIIAgAAAA==.Xantosz:BAAANQAECgEIAQABNQAFFAYIGQAQAIEaAA==.',
Xi='Xianyu:BAABNQAECn8jAAMVAAcKvgP6FgCsAAAVAAcKvgP6FgCsAAAgAAEKIAC5WQAEAAAAAA==.',
Ya='Yahman:BAAANQADCgMIAwAAAA==.Yarian:BAAANQAECgMIAwAAAA==.',
Ym='Ymirr:BAAANQABCgcICAAAAA==.',
Yu='Yuck:BAAANQAECgIIAgABNQAFFAcIFQAPANEeAA==.',
Za='Zachhunter:BAACNQAFFH8eAAMRAAgKqyEtDQCAAQASAAUKHh0tCgCgAQARAAUKDyMtDQCAAQA1AAQKfzwAAxIACgopJTMQAOcCABIACApYJDMQAOcCABEACAo5IpZwADACAAAA.Zachmage:BAAANQADCggIFgAAAA==.Zan:BAACNQAFFH8ZAAMQAAYKgRqkDAD9AAAQAAQKkxukDAD9AAAPAAUKWAi5GwCsAAA1AAQKfzUAAxAACgrDHxcjAPsCABAACgrDHxcjAPsCAA8AAwomETLcALAAAAAA.',
Ze='Zephrie:BAAANQADCgYIBgAAAA==.Zeronation:BAAANQAECgMIBAAAAA==.',
Zi='Zinderella:BAAANQAECgUICAABNQAECgoKNgARAN0VAA==.',
Zu='Zultrix:BAAANQAECgUICgAAAA==.',
Zy='Zylaeri:BAABNQAECn8WAAIBAAkKnghJjgBrAQABAAkKnghJjgBrAQAAAA==.',
['Éo']='Éowyn:BAAANQADCgEIAQAAAA==.',
['Ël']='Ëllër:BAABNQAECn8dAAIUAAkKQQrsCQATAQAUAAkKQQrsCQATAQAAAA==.',
['ßä']='ßädër:BAAANQAECgMIAwABNQAECgoKRQASAJsVAA==.',
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
