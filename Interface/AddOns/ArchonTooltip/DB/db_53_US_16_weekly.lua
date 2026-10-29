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

local lookup = {'Priest-Holy','Priest-Discipline','Priest-Shadow','Druid-Restoration','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Hunter-Survival','Druid-Balance','DeathKnight-Frost','Paladin-Holy','Warrior-Arms','Warrior-Protection','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','Warlock-Destruction','Mage-Arcane','Mage-Frost','Mage-Fire','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Rogue-Assassination','Rogue-Subtlety','Monk-Brewmaster','Monk-Windwalker','Warlock-Demonology','Warlock-Affliction','Shaman-Enhancement','DemonHunter-Devourer','Rogue-Outlaw','Monk-Mistweaver','Druid-Feral','Druid-Guardian','DemonHunter-Havoc',}
local provider = {region='US',realm='Arathor',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abavok:BAAANQADCgcIBwAAAA==.Absoul:BAACNQAFFH8bAAIBAAUKmw8wDABoAQABAAUKmw8wDABoAQA1AAQKf00AAgEACgqoGk04AIcCAAEACgqoGk04AIcCAAAA.Abyssian:BAABNQAECn8dAAQCAAoKqwrtFgDAAAABAAgKjwsiXwA7AQACAAcK7APtFgDAAAADAAYKkgXALgCdAAAAAA==.',
Ac='Acedia:BAABNQAECn8qAAIBAAgK4xqTNQDkAQABAAgK4xqTNQDkAQAAAA==.',
Ad='Adellas:BAABNQAECn9BAAIEAAoKXBwACADVAgAEAAoKXBwACADVAgAAAA==.Adern:BAABNQAECn9LAAIDAAoKAh24DgAFAwADAAoKAh24DgAFAwAAAA==.Adon:BAAANQADCgUIBQABNQAECgYIDgAFAAAAAA==.Adonn:BAABNQAECn83AAMGAAoKSBzcOwALAgAGAAoKSBzcOwALAgAHAAIKBgpAZwBGAAAAAA==.Adonshadriel:BAAANQAECgYIDgAAAA==.',
Ae='Aelali:BAABNQAECn8gAAIIAAoKlwhbBwAFAgAIAAoKlwhbBwAFAgAAAA==.',
Af='Afador:BAAANQADCggIEgABNQAECgYIEwAFAAAAAA==.',
Ag='Ageling:BAAANQADCgUIBQAAAA==.',
Al='Aladestar:BAACNQAFFH8LAAIJAAQKRhBoCwDfAAAJAAQKRhBoCwDfAAA1AAQKfy8AAwkACgqgGaElAKUCAAkACgqgGaElAKUCAAQABgpOFLw4AFgBAAAA.Albinodh:BAAANQAECgMIBAAAAA==.Alderleise:BAAANQADCgcIBwAAAA==.Alexein:BAACNQAFFH8OAAIKAAUKmgdVCwC9AAAKAAUKmgdVCwC9AAA1AAQKfy4AAgoACgrHGKcqAEYCAAoACgrHGKcqAEYCAAAA.',
Am='Amets:BAABNQAECn8bAAMLAAoK9Q6magDYAQALAAoK9Q6magDYAQAGAAQKZAxVOQHEAAAAAA==.Amorae:BAAANQADCggIDwAAAA==.',
An='Anabel:BAAANQAECgEIAQAAAA==.Anamii:BAAANQAECgQIBAAAAA==.Andorsi:BAAANQAECgEIAQAAAA==.',
Ao='Aoratos:BAAANQAECgEIAQAAAA==.',
Ar='Arachne:BAABNQAECn8fAAIDAAgKtgoaNgBzAQADAAgKtgoaNgBzAQAAAA==.Aracianluz:BAAANQAECggIDAAAAA==.Arak:BAAANQADCgIIAgAAAA==.Arce:BAAANQAECgQIBAABNQAECgkJKwAKAD4SAA==.Arysia:BAAANQAECgUIBgAAAA==.Aryya:BAAANQADCgIIAgAAAA==.',
As='Ascaris:BAABNQAECn8UAAIMAAgK6BbVjgD3AQAMAAgK6BbVjgD3AQAAAA==.',
Av='Avalan:BAABNQAECn88AAQMAAoKsh7xQgDBAgAMAAoKjx3xQgDBAgANAAYKjhu2GAClAQAOAAYKIxxaEQCPAQAAAA==.Avanolatwo:BAAANQADCgYIBgABNQAECgoKLwAPADUZAA==.Avashammy:BAABNQAECn8vAAMPAAoKNRlNLgCoAgAPAAoKNRlNLgCoAgAQAAYKyhCJlABxAQAAAA==.Aviendah:BAABNQAECn8aAAIRAAkKwQnnwwB6AQARAAkKwQnnwwB6AQAAAA==.',
Aw='Awsomeonet:BAAANQAECggICAAAAA==.',
Az='Azdfghop:BAACNQAFFH8PAAMSAAgKHA8mCgCgAQASAAcKCgwmCgCgAQARAAIKcx54IACxAAA1AAQKfyYAAxIACgrqIkAWAKkCABIACQqsIUAWAKkCABEAAgqUIxPrAGEAAAAA.Azzinotica:BAAANQAECgUIBgAAAA==.',
Ba='Baalsanaro:BAAANQADCggIFQABNQAECgQIBQAFAAAAAA==.Babeshot:BAABNQAECn87AAIRAAoKuQ2/TgCwAQARAAoKuQ2/TgCwAQAAAA==.Baelgar:BAAANQAECgMIAwAAAA==.',
Be='Bergur:BAAANQAECgMIAwABNQAECgoKNQATAJYjAA==.',
Bi='Bigbear:BAAANQADCggICAABNQAECgcIFgAUACQRAA==.Biggy:BAAANQADCgIIAgAAAA==.Binksy:BAAANQAECggICAAAAA==.',
Bl='Blaaze:BAAANQADCgYIBgAAAA==.Blackfrost:BAAANQAECggIEwAAAA==.Blaiddyd:BAABNQAECn80AAIRAAkKlxzDQwCgAgARAAkKlxzDQwCgAgAAAA==.',
Bo='Bomi:BAAANQADCgEIAQAAAA==.Boogereater:BAAANQAECgMIAgABNQAECgcIBwAFAAAAAA==.',
Br='Brandawn:BAAANQAECgQICQAAAA==.',
Bu='Burndasheep:BAABNQAECn86AAQVAAoKNxLdUAC7AQAVAAoKGxLdUAC7AQAWAAIK4xM/HQCFAAAXAAEKew0ZDQA6AAAAAA==.',
['Bæ']='Bæyy:BAABNQAECn8WAAIVAAUKEgtiwwDDAAAVAAUKEgtiwwDDAAAAAA==.',
Ca='Calyris:BAAANQADCgIIBAAAAA==.Caspias:BAEANQADCggJEgAAAA==.Caylynn:BAAANQAECgQIAwAAAA==.Caynelin:BAAANQAECgEIAQAAAA==.',
Ce='Cestbusiness:BAAANQADCgUIBQAAAA==.',
Ch='Chaoslock:BAABNQAECn8WAAIUAAcKJBHQFgC2AQAUAAcKJBHQFgC2AQAAAA==.Chetter:BAAANQAECggIBgAAAA==.Chicknfajita:BAAANQAECgcICQABNQAECgoKHAAQAEcgAA==.Chickpea:BAAANQAECgIIAgAAAA==.',
Ci='Civilian:BAAANQAECgYIBgABNQAECgoKNAADAEggAA==.',
Co='Cocytus:BAAANQAECgIIAQAAAA==.Colbith:BAABNQAECn8YAAIJAAYKxA12YgBEAQAJAAYKxA12YgBEAQAAAA==.Corblixx:BAAANQAECgEIAQAAAA==.Cordaddy:BAAANQAECgYIBwABNQAECgkJKwAPAMUlAA==.Cordelvo:BAAANQAECgUICgABNQAECgkJKwAPAMUlAA==.Cordragon:BAAANQAECgIIAgABNQAECgkJKwAPAMUlAA==.Cordragu:BAABNQAECn8rAAIPAAkKxSVEBACoAwAPAAkKxSVEBACoAwAAAA==.Cordran:BAAANQAECgEIAgABNQAECgkJKwAPAMUlAA==.Corinthin:BAAANQADCgQIBAAAAA==.Corraa:BAAANQADCgEIAQAAAA==.',
Cr='Crakum:BAABNQAECn8XAAIQAAYKrRS0iwCHAQAQAAYKrRS0iwCHAQAAAA==.Crinn:BAABNQAECn8bAAMYAAcKDg3FagBnAQAYAAcKDg3FagBnAQAKAAIK3AN5owBHAAAAAA==.Crizmon:BAABNQAECn8eAAIKAAkKRx8MFQDkAgAKAAkKRx8MFQDkAgAAAA==.',
Cu='Cucumber:BAAANQAECgQIBAAAAA==.',
Da='Damorthyx:BAABNQAECn8YAAIZAAkKGAzNVQCcAQAZAAkKGAzNVQCcAQAAAA==.Darazarke:BAACNQAFFH8eAAMaAAcKmQ6JBQAOAgAaAAcKmQ6JBQAOAgAbAAEKLQVIDQA9AAA1AAQKfy4ABBoACgqUGAcTAHwCABoACgqUGAcTAHwCABsAAQqCGDkTAEsAABwAAQqKFr0aAEgAAAAA.Darkquill:BAABNQAECn8mAAIQAAoKOQ2LcwDGAQAQAAoKOQ2LcwDGAQAAAA==.Daspoof:BAAANQADCgYIBgAAAA==.Dayquil:BAEANQADCgcIBwABNQAFFAIIAgAFAAAAAA==.',
De='Deadaddie:BAAANQAECgcIEQABNQAECgoKMQAVAKoiAA==.Deamoneyes:BAAANQAECgQIBgAAAA==.Deathkauf:BAAANQAECgEIAQAAAA==.Deathvok:BAAANQADCgMIAwAAAA==.Demolitions:BAAANQAECggICAAAAA==.Dezatra:BAAANQADCgcIBgAAAA==.',
Dh='Dhonaan:BAAANQADCgEIAQAAAA==.',
Di='Dieselcon:BAACNQAFFH8FAAIHAAQK3gT8BQCWAAAHAAQK3gT8BQCWAAA1AAQKfz0AAwcACgqNFBoaACECAAcACgqNFBoaACECAAYABAr+BdRKAagAAAAA.Diprivan:BAABNQAECn80AAMdAAoKlB/ZEQDuAgAdAAoK9BzZEQDuAgAeAAkKlRtqKQDeAQAAAA==.',
Do='Dolobrik:BAAANQABCgYIBwAAAA==.Domdog:BAABNQAECn8dAAIVAAcKvgdJBQGFAQAVAAcKvgdJBQGFAQAAAA==.Domína:BAAANQAECgUICQAAAA==.Dontforget:BAAANQAECgYIEAAAAA==.Doomdealer:BAABNQAECn8jAAMKAAoKXQ6uIwCxAQAKAAoKXQ6uIwCxAQAZAAEKAACKugBSAAAAAA==.Doomed:BAABNQAECn8dAAILAAgKnh9vJgDQAgALAAgKnh9vJgDQAgABNQAECggICAAFAAAAAA==.Doonya:BAAANQAECgIIAQAAAA==.Dottee:BAAANQAECggIAwAAAA==.Dougwalker:BAAANQADCgIIAgAAAA==.',
Dr='Dracodaddy:BAAANQADCgIIAgAAAA==.Draftymonk:BAABNQAECn8XAAMfAAcKMR9QCgBxAgAfAAYK6SNQCgBxAgAgAAMKLBAwUQCuAAAAAA==.Drage:BAABNQAECn8yAAMhAAoKuBY0JwAYAgAhAAoKuBY0JwAYAgAUAAEKdgMvhQAkAAAAAA==.Drax:BAABNQAECn8lAAMiAAoKcQp/DwBWAQAhAAoKCQiMogCQAQAiAAYKEwx/DwBWAQAAAA==.Dreadgar:BAAANQAECgQIBQABNQAECgoKJAAQAG4gAA==.Dritzzagain:BAAANQAECgUIDAAAAA==.Dritzzcat:BAAANQADCgYICwAAAA==.',
Dw='Dwreck:BAAANQAECggIDgAAAA==.',
Ed='Ediann:BAAANQAECgcIDgAAAA==.',
El='Elandrus:BAAANQAECgUICgABNQAECgkJKwAVAAkWAA==.Eldarine:BAAANQADCgUIBQAAAA==.',
Em='Emmara:BAABNQAECn8jAAISAAoKVQM9IwDkAAASAAoKVQM9IwDkAAAAAA==.',
En='Enitar:BAAANQADCgcICAABNQAECgoKOgAVADcSAA==.',
Er='Erata:BAABNQAECn8aAAIiAAYKbQclDQC8AAAiAAYKbQclDQC8AAAAAA==.Erlik:BAAANQADCgMIBAAAAA==.Erzakzaktraz:BAAANQADCgYIBgABNQADCgcIBgAFAAAAAA==.',
Ev='Evullight:BAAANQADCgEJAQAAAA==.',
Ez='Ezlok:BAABNQAECn8kAAIQAAoKbiDnDgCkAgAQAAoKbiDnDgCkAgAAAA==.',
Fa='Facemash:BAAANQAECgQIBAABNQAECgoKOgAVADcSAA==.Faedra:BAAANQADCggIDgABNQAECgoKNQABAIMfAA==.Falerin:BAABNQAECn8nAAIEAAoKuhp0GAB7AgAEAAoKuhp0GAB7AgAAAA==.Farryn:BAAANQADCgEIAQAAAA==.',
Fe='Feenex:BAAANQAECgYIEgAAAA==.Feldora:BAAANQADCgYIBgAAAA==.Festiva:BAAANQAECgIIBAAAAA==.',
Fi='Fillorey:BAAANQADCggICAABNQAECgkJKwAVAAkWAA==.Firedealer:BAABNQAECn83AAMSAAoKOhFjEQCuAQASAAoKFBFjEQCuAQARAAQKbxKN8gAcAQAAAA==.',
Fl='Flappy:BAAANQAECgIIBAABNQAECgkJNgAPACYbAA==.Flashmaster:BAAANQAFFAEIAQAAAA==.Flawlessheal:BAAANQADCgMIAwAAAA==.Fluffybutt:BAAANQADCggIFAAAAA==.',
Fo='Fossora:BAAANQADCgcIBgAAAA==.Foxygrandpa:BAAANQADCgIIAgAAAA==.',
Fr='Freyiah:BAAANQADCgYJBgAAAA==.',
Fy='Fyatre:BAAANQAECgYIDwAAAA==.',
Ga='Galath:BAAANQAECgUJCAABNQAECgMIAwAFAAAAAA==.Gandallf:BAAANQADCgUIBQAAAA==.',
Ge='Gerree:BAAANQADCgYICgAAAA==.Gerry:BAAANQAECggIDwABNQAECgkJLwAOADgbAA==.',
Gg='Ggkando:BAABNQAECn8bAAIRAAYK4QqnhQAnAQARAAYK4QqnhQAnAQAAAA==.',
Gh='Ghemaldir:BAAANQABCgIIAgAAAA==.',
Gi='Gildius:BAAANQADCgIIAgAAAA==.Gingerail:BAAANQAECgUICAAAAA==.',
Gl='Glory:BAABNQAECn8iAAIZAAkKAR09IwCdAgAZAAkKAR09IwCdAgAAAA==.',
Gn='Gnayami:BAAANQADCgcIDwAAAA==.',
Go='Goochsquirts:BAABNQAECn8fAAIPAAgKRxsOUAAlAgAPAAgKRxsOUAAlAgAAAA==.Govna:BAAANQADCggIFAAAAA==.',
Gr='Grakkaem:BAAANQAECgMIBAAAAA==.Grannet:BAAANQADCgMIBQAAAA==.Gravedygger:BAABNQAECn88AAIRAAoKuBVrLQAqAgARAAoKuBVrLQAqAgAAAA==.Greenfear:BAAANQADCgYIDAAAAA==.Grenswood:BAAANQAECgcIEgAAAA==.Greybeeredd:BAAANQAECgIIAwAAAA==.Grimmkin:BAABNQAECn8oAAQjAAoKrhlKCwC8AgAjAAoKrhlKCwC8AgAPAAIKrA8e/gBuAAAQAAEKAACtQwEsAAAAAA==.Grind:BAAANQAECgQIBAABNQAECgYIEwAFAAAAAA==.Growl:BAAANQAECgEIAQAAAA==.Grumbo:BAAANQADCgcIBgAAAA==.',
Gu='Guuldurak:BAAANQADCgcIBgAAAA==.',
Ha='Hailcat:BAAANQAECgMIBAABNQAECgoKJAAhAC0PAA==.Handivhe:BAAANQADCgYIBgAAAA==.Hasew:BAABNQAECn9AAAIRAAkKGyI0DwDVAgARAAkKGyI0DwDVAgAAAA==.',
He='He:BAAANQAECgcICwABNQAECgkJKwAKAD4SAA==.Hellanor:BAAANQABCgUIBwAAAA==.Helpimßlind:BAABNQAECn8dAAIkAAkKkxZXFQCaAQAkAAkKkxZXFQCaAQAAAA==.Hera:BAACNQAFFH8PAAIRAAUKYyOdBgAtAQARAAUKYyOdBgAtAQA1AAQKfy4AAhEACgp5Jh4EAMcDABEACgp5Jh4EAMcDAAAA.Heyner:BAABNQAECn89AAIlAAoKqBrmAACEAgAlAAoKqBrmAACEAgAAAA==.',
Hi='Hinral:BAACNQAFFH8OAAImAAUKVBhFAgCPAQAmAAUKVBhFAgCPAQA1AAQKfzEAAiYACgorJKACAJMDACYACgorJKACAJMDAAAA.',
Ho='Holyiaa:BAAANQAECgcIDAABNQAECgYIEAAFAAAAAA==.Holyluz:BAAANQAECgQIBAABNQAECggIDAAFAAAAAA==.Holysmacker:BAAANQAECgEIAQABNQAECgcIGQAWAGUZAA==.',
Hy='Hymns:BAAANQAECggIAgAAAA==.',
['Hë']='Hëll:BAABNQAECn8kAAMhAAoKLQ9acwAHAgAhAAoKLQ9acwAHAgAUAAEKGRC/cwA7AAAAAA==.',
Il='Illaynne:BAABNQAECn8vAAIBAAkKsxZCLgAJAgABAAkKsxZCLgAJAgAAAA==.',
Im='Imani:BAACNQAFFH8OAAIjAAUKqQIWAwC6AAAjAAUKqQIWAwC6AAA1AAQKfy4AAiMACgrVDBgVABcCACMACgrVDBgVABcCAAAA.Immensepain:BAAANQAECgUIBAAAAA==.',
In='Inoshikacho:BAABNQAECn8lAAInAAoK+QlVHABAAQAnAAoK+QlVHABAAQAAAA==.Involio:BAAANQAECgEIAQAAAA==.',
Ir='Irishmecha:BAACNQAFFH8PAAIdAAUK8AoJBADdAAAdAAUK8AoJBADdAAA1AAQKfy4AAh0ACgrwHt0VAM0CAB0ACgrwHt0VAM0CAAAA.Irishpaws:BAAANQAECgEIAQAAAA==.Ironshot:BAAANQADCggIBgAAAA==.',
Is='Isaeus:BAAANQAECgEIAQAAAA==.',
It='Itharillys:BAABNQAECn8mAAIRAAkK8BPrcwAoAgARAAkK8BPrcwAoAgAAAA==.',
Ja='Jaadu:BAAANQADCgQIBAAAAA==.Jangus:BAAANQAECgYIEwAAAA==.Jaybone:BAAANQAECgIIAQAAAA==.',
Je='Jeefus:BAAANQAECggIAgAAAA==.Jeennkiins:BAAANQADCgYIBgABNQAECgMIAwAFAAAAAA==.Jenifur:BAAANQAECgIIAwABNQAECgoKNQABAIMfAA==.Jessibella:BAAANQADCgQIBAAAAA==.Jezzako:BAAANQAECgcICwAAAA==.',
Ji='Jinx:BAAANQADCggIDAABNQAECgoKNQABAIMfAA==.',
Jo='Johali:BAAANQAECggICgAAAA==.Jozan:BAAANQADCgcIHwAAAA==.',
Ju='Justise:BAAANQADCgIIAgABNQADCgYJCwAFAAAAAA==.Jutojerry:BAAANQAECggICAAAAA==.',
['Jö']='Jöhnblaze:BAABNQAECn87AAMMAAoKew8VQgDGAQAMAAoKew8VQgDGAQANAAcKKg3kEQAdAQAAAA==.',
Ka='Kaga:BAAANQADCgEJAQABNQAECgoKOgAVADcSAA==.Kailys:BAABNQAECn8vAAIHAAoKUxAKFgBVAQAHAAoKUxAKFgBVAQAAAA==.Kaisana:BAAANQAECgYICwAAAA==.Kaishias:BAABNQAECn8oAAIGAAkKaxjpNQAhAgAGAAkKaxjpNQAhAgAAAA==.Kaldrek:BAAANQAECgMIBgABNQAECgcIEgAFAAAAAA==.Kandoh:BAAANQADCggIEwABNQAECgYIGwARAOEKAA==.Kanimeh:BAAANQADCgUIBQAAAA==.Kankuró:BAACNQAFFH8FAAIRAAIKvhkNFgCcAAARAAIKvhkNFgCcAAA1AAQKfzgAAhEACgokHSYfABsDABEACgokHSYfABsDAAAA.Karelleira:BAAANQADCgUIBQAAAA==.Kautie:BAAANQAECgUIDgAAAA==.',
Ki='Killahmike:BAAANQAECgQIBgAAAA==.Killudead:BAAANQAECggIDgAAAA==.Kishana:BAAANQADCgcIBgAAAA==.',
Ko='Kodetra:BAABNQAECn8XAAIbAAgKSAttCAAeAQAbAAgKSAttCAAeAQAAAA==.Kolgrim:BAABNQAECn8oAAMZAAoKIBWlLQA5AQAKAAkKaw66PQDVAQAZAAgKghilLQA5AQAAAA==.Kong:BAAANQAECgIIAgAAAA==.Korimya:BAAANQADCggIDAAAAA==.Korvuk:BAAANQAECgcIEgAAAA==.',
Kr='Kristafur:BAAANQADCggICAABNQAECgoKNQABAIMfAA==.Krom:BAABNQAECn8hAAMQAAoK0gkCpwBGAQAQAAYKXw8CpwBGAQAPAAkK/wXZkACdAAAAAA==.Krysta:BAABNQAECn81AAMBAAoKgx/TEADoAgABAAoKgx/TEADoAgADAAEKAACegQAoAAAAAA==.',
Ky='Kynris:BAAANQADCggIEQABNQAECgkJKwAVAAkWAA==.',
La='Lanaal:BAAANQADCgEIAQAAAA==.Lancewh:BAAANQADCgcIDAAAAA==.Lanciwinluna:BAAANQADCgQIBAAAAA==.Lancywinelia:BAAANQADCgQIBgAAAA==.Lauryssa:BAAANQADCggICAAAAA==.',
Ld='Ldydthstryke:BAAANQAECgYIBgABNQAECgoKNwASADoRAA==.',
Le='Legg:BAAANQABCgMIAwAAAA==.Legolâs:BAAANQADCgUIBQAAAA==.Leonora:BAABNQAECn8WAAISAAgK8wQ2JwDIAAASAAgK8wQ2JwDIAAAAAA==.Leviathañ:BAAANQADCgIIAgABNQAECggIDgAFAAAAAA==.Lezene:BAAANQAECgMIAwAAAA==.',
Li='Linstriker:BAABNQAECn8uAAIoAAkKhiFkCgDKAgAoAAkKhiFkCgDKAgABNQAFFAcIFQAPANEeAA==.',
Lo='Lorette:BAABNQAECn8yAAMBAAoKpR7SDwDzAgABAAoKpR7SDwDzAgADAAcK6xwRIAA6AgAAAA==.',
Lu='Lucethegoose:BAAANQADCgQIBAAAAA==.Luckynyx:BAAANQAECgUIBQAAAA==.Lunate:BAAANQAECgEIAQABNQAECgoKNAADAEggAA==.Lunavere:BAAANQADCgQIBgAAAA==.',
Ma='Machotedan:BAABNQAECn8+AAIGAAoKsiGLDwD6AgAGAAoKsiGLDwD6AgAAAA==.Macmittens:BAAANQAECgIIAgAAAA==.Makoes:BAAANQADCgYIBgAAAA==.Mamadrag:BAAANQAECgYIEAAAAA==.Managua:BAAANQADCgEIAQAAAA==.Mandwa:BAAANQADCggIGAABNQAECgoKOgAVADcSAA==.Mangojuulpod:BAAANQADCgYIBgAAAA==.Mario:BAABNQAECn8ZAAIWAAcKZRlmDgDEAQAWAAcKZRlmDgDEAQAAAA==.Mastashifta:BAAANQAECgQICAAAAA==.Mataa:BAABNQAECn8rAAIVAAkKCRZM0ADlAQAVAAkKCRZM0ADlAQAAAA==.Matryoshka:BAAANQADCgUIDQABNQAECgIIAQAFAAAAAA==.Maxxim:BAAANQAECgIIAQAAAA==.Mayihmpurleg:BAAANQAECgUIBQABNQAECgoKNwASADoRAA==.Mazeman:BAAANQADCgUIBQAAAA==.',
Me='Meilin:BAAANQAECgMIAwAAAA==.Mellachion:BAAANQAECgYICAABNQAECgcIGQAWAGUZAA==.Meta:BAAANQAECgcIEAAAAA==.',
Mi='Mistaya:BAAANQADCgUIBQABNQAECggIHAAhAM4IAA==.Mists:BAABNQAFFH8FAAMhAAUK4BHIFwA2AQAhAAQKABjIFwA2AQAUAAEKoAUQIgBFAAAAAA==.Miththrawndo:BAABNQAECn8sAAIZAAoKHQ4LVACkAQAZAAoKHQ4LVACkAQAAAA==.',
Mo='Momjeans:BAABNQAECn8sAAIVAAoK0x3pXQDEAgAVAAoK0x3pXQDEAgAAAA==.',
Mu='Mumbo:BAAANQADCgcIBwABNQAECgYIEwAFAAAAAA==.Muu:BAAANQADCgYICAAAAA==.',
My='Mydaan:BAAANQADCgIIAwAAAA==.Mythunsarian:BAABNQAECn8cAAIpAAgKwwmRLgAuAQApAAgKwwmRLgAuAQAAAA==.',
['Má']='Mákï:BAABNQAECn8aAAIMAAgKNBCHkQDwAQAMAAgKNBCHkQDwAQAAAA==.',
['Mä']='Mäylä:BAABNQAECn8lAAMJAAkKaAxDSgC+AQAJAAkKaAxDSgC+AQAEAAEKlA7JXAAsAAAAAA==.',
['Mí']='Míst:BAABNQAECn89AAIGAAoKixjpXgB8AgAGAAoKixjpXgB8AgAAAA==.',
Na='Narlis:BAABNQAECn8uAAIYAAoKLCM7CgBrAwAYAAoKLCM7CgBrAwAAAA==.Nautprepared:BAAANQAECgMIAQABNQAECggICAAFAAAAAA==.',
Ne='Nephie:BAAANQAECgYICwAAAA==.Nezqk:BAACNQAFFH8NAAQKAAUKFxB7CgDLAAAKAAQKCRB7CgDLAAAYAAIKlxHyFwCaAAAZAAEKAADGJQAAAAA1AAQKfyoABBgACgoUGvcyAF8CABgACQpuHPcyAF8CABkACAqQEvZOALkBAAoABQoyE85rAO8AAAAA.Nezquick:BAAANQAECgIIAgAAAA==.',
Ni='Niano:BAAANQABCgIIAgAAAA==.',
Nm='Nmnenthe:BAABNQAECn8dAAIcAAgKRhbGFAABAgAcAAgKRhbGFAABAgAAAA==.',
No='Notrealword:BAAANQAECgcICgABNQAECgkJQAARABsiAA==.Noxluminous:BAAANQABCgIIAgAAAA==.',
Ob='Obin:BAABNQAECn8jAAMOAAgK9A63GgD6AAAOAAYKaw23GgD6AAAMAAcKfg7cmADaAAAAAA==.',
Oc='Occasionally:BAAANQAECgIIAgAAAA==.',
Ok='Okukoy:BAAANQABCgEIAQAAAA==.',
Om='Ominious:BAABNQAECn8oAAMjAAoKvxIuFAAmAgAjAAkKJxEuFAAmAgAQAAUKtRcBqgBAAQABNQAECggIDwAFAAAAAA==.Omnissia:BAAANQAECgUIAwABNQAECggIDwAFAAAAAA==.Omnius:BAABNQAECn8bAAMQAAoK8Bs+PQBfAQAQAAoK8Bs+PQBfAQAPAAEKMAu9KQEkAAAAAA==.Omnya:BAAANQAECgcIDQABNQAECggIDwAFAAAAAA==.Omnyi:BAAANQAECggIDwAAAA==.',
Ow='Owendriel:BAACNQAFFH8HAAIkAAMKZg/KCQB9AAAkAAMKZg/KCQB9AAA1AAQKfxgAAyQACgpzEx0oAAMCACQACQrEER0oAAMCACkAAwrpEglxALUAAAAA.',
Pa='Paindya:BAAANQAECgYIDAAAAA==.Paleigh:BAAANQABCgYICwAAAA==.Palivok:BAAANQAECgIIAgAAAA==.Pandress:BAABNQAECn8YAAIRAAcKAg1YxwBzAQARAAcKAg1YxwBzAQAAAA==.Pankake:BAAANQAECgQIBAABNQAECgoKNQATAJYjAA==.Paralysis:BAACNQAFFH8OAAIkAAUKqw3WBgDHAAAkAAUKqw3WBgDHAAA1AAQKfy0AAiQACgr/FyEeAGACACQACgr/FyEeAGACAAAA.',
Pe='Peetza:BAAANQADCgYIBgABNQAECgoKNQATAJYjAA==.Peryite:BAABNQAECn85AAMBAAoK6Bk1JABGAgABAAoK6Bk1JABGAgACAAQK6xBhFQDUAAAAAA==.',
Ph='Phaedrana:BAAANQAECgcIDgAAAA==.',
Pi='Pisscat:BAAANQAECgUIDgAAAA==.',
Po='Pocketdragon:BAABNQAECn8tAAMcAAoKZxUhDwBpAgAcAAoKchQhDwBpAgAbAAYKWhBOEAA1AQAAAA==.',
Pr='Prideindeath:BAAANQAECgQIBAAAAA==.Promiscuity:BAABNQAECn8nAAMhAAoKuhhGIwAtAgAhAAoKuhhGIwAtAgAiAAIKwwlCIgBpAAAAAA==.Prængle:BAAANQADCgYIAwAAAA==.',
Ps='Psoas:BAABNQAECn80AAMDAAoKSCAnCABaAwADAAoKSCAnCABaAwABAAIK4BBH5AB7AAAAAA==.Psypriest:BAECNQAFFH8HAAIBAAMKgxc8GwCgAAABAAMKgxc8GwCgAAA1AAQKfzAAAgEACQoNHxwbAIYCAAEACQoNHxwbAIYCAAE1AAUUBwggAAEAvg8A.',
Py='Pyroheal:BAAANQAECggICAAAAA==.',
Qu='Quaichang:BAAANQADCgYIBgAAAA==.',
Ra='Rabbi:BAABNQAECn8xAAMDAAoKVxnkEgDTAgADAAkKJBvkEgDTAgABAAIK+BrQmQCaAAAAAA==.Rahfna:BAAANQADCgcIDwAAAA==.Railænu:BAAANQADCggIDgAAAA==.Rainmist:BAAANQAECgMIAgAAAA==.Ranric:BAAANQAECgMIAwAAAA==.',
Re='Redall:BAAANQADCgcIBwAAAA==.Reesespbc:BAAANQAECgYIDQAAAA==.Reina:BAAANQAECgYIDgABNQAECgoKNQABAIMfAA==.Reinz:BAAANQAECggIDgAAAA==.Rektagar:BAABNQAECn8vAAIQAAoKKSTUBQC8AwAQAAoKKSTUBQC8AwABNQAFFAcIHAARAKAhAA==.Ressandra:BAAANQADCgMIBgAAAA==.Rezo:BAAANQAECgEIAgAAAA==.',
Ri='Riverarose:BAAANQADCggIFQAAAA==.',
Ro='Roar:BAAANQAECgQIDgABNQAECgYIEwAFAAAAAA==.',
Ry='Rysi:BAAANQADCgQIBAAAAA==.',
['Rò']='Ròs:BAACNQAFFH8QAAIHAAUK7BnyAwDTAAAHAAUK7BnyAwDTAAA1AAQKfy4AAgcACgqJIUcKAPYCAAcACgqJIUcKAPYCAAAA.',
['Rö']='Rös:BAAANQADCgEIAQABNQAFFAUIEAAHAOwZAA==.',
Sa='Saberie:BAAANQADCggIFwABNQADCgMIBgAFAAAAAA==.Salaria:BAABNQAECn8jAAIkAAkKrg35MwCjAQAkAAkKrg35MwCjAQAAAA==.Salina:BAEBNQAECn8WAAITAAgKJBV5EACqAQATAAgKJBV5EACqAQAAAA==.Sandstique:BAABNQAECn8tAAIPAAoKYiQpEwAxAwAPAAoKYiQpEwAxAwAAAA==.Sandweaver:BAAANQADCgcIBwAAAA==.Sanjira:BAAANQADCgYIBgAAAA==.Sarlak:BAABNQAECn8rAAMRAAoKphw5JQACAwARAAoKphw5JQACAwASAAEK8AYalwAqAAAAAA==.Sarusuby:BAABNQAECn9FAAIoAAoKlhFiEwCAAQAoAAoKlhFiEwCAAQAAAA==.Satae:BAABNQAECn81AAITAAoKliOBAgBZAwATAAoKliOBAgBZAwAAAA==.',
Sc='Schufft:BAABNQAECn8aAAIUAAcKzBuCCAB1AgAUAAcKzBuCCAB1AgAAAA==.Scottydh:BAAANQAECgIIAgABNQAECgoKNwAZAJkgAA==.Scottymac:BAABNQAECn83AAIZAAoKmSBIDwA0AwAZAAoKmSBIDwA0AwAAAA==.Scottypal:BAAANQAECgQIBQABNQAECgoKNwAZAJkgAA==.',
Se='Seatah:BAAANQAECgMIAwAAAA==.Seba:BAABNQAECn8gAAIQAAgKyxU0TABGAgAQAAgKyxU0TABGAgAAAA==.Seetah:BAABNQAECn8gAAMBAAoKuhNvWQAVAgABAAoKuhNvWQAVAgADAAIK6wyOZwBiAAAAAA==.Seraphtharia:BAAANQABCgIIAgAAAA==.Sermon:BAAANQADCgQIBAABNQAECgYIEwAFAAAAAA==.',
Sh='Shadaddy:BAABNQAECn8xAAMVAAoKqiKxLQA7AgAVAAkKjCKxLQA7AgAWAAMKNyALHwDyAAAAAA==.Shadowheart:BAAANQAECgEIAQAAAA==.Shakasana:BAAANQAECgEIAQAAAA==.Shal:BAABNQAECn8pAAIMAAkKlxnzRAC7AQAMAAkKlxnzRAC7AQAAAA==.Shamanluz:BAAANQADCgIIAgABNQAECggIDAAFAAAAAA==.Shamommy:BAAANQADCgUIBAAAAA==.Shamtaz:BAAANQAECgUICgAAAA==.Shimmerstar:BAABNQAECn8cAAIGAAkKYR0pcQBNAgAGAAkKYR0pcQBNAgAAAA==.Shroomgirl:BAAANQAECgUIBQAAAA==.Shrubhub:BAAANQAECgEIAQABNQAECggICAAFAAAAAA==.',
Si='Silexe:BAABNQAECn8eAAMbAAYK7RZsDQB3AQAbAAYKTRZsDQB3AQAcAAUKphUtDQAIAQAAAA==.Sitga:BAAANQADCgIIAgAAAA==.',
Sl='Slinga:BAAANQADCgcICQAAAA==.Slipperyboi:BAAANQAECgQICQAAAA==.Slÿ:BAAANQAECgIIAgAAAA==.',
So='Solarion:BAAANQAECgYIDwABNQAECgoKJAAQAG4gAA==.Soldraca:BAAANQAECgMIAwAAAA==.',
St='Stats:BAAANQAECgYIEAABNQAECgYIEwAFAAAAAA==.Stinkbug:BAAANQADCgQIBAAAAA==.Stutters:BAABNQAECn84AAMYAAoKVCAjCQCTAgAZAAoKrRz8FgD1AgAYAAoKvhsjCQCTAgAAAA==.',
Su='Subayyru:BAAANQADCgEIAQABNQAECgUIFgAVABILAA==.Sudachi:BAAANQADCgYIBgABNQAFFAcKFAAgACscAA==.Sunnyräy:BAAANQAECgMIAwAAAA==.Superiorkill:BAAANQADCgcIBwAAAA==.Suthrheimr:BAABNQAECn8vAAIOAAkKOBvRBgCWAgAOAAkKOBvRBgCWAgAAAA==.',
Sy='Symphany:BAAANQABCggIEQAAAA==.',
['Sý']='Sýndrá:BAAANQAECgYIDQAAAA==.',
Ta='Takafune:BAAANQADCgQIBgAAAA==.Talespin:BAAANQAECgUIBQAAAA==.Talysiah:BAABNQAECn8cAAIhAAgKzgjdfQD7AAAhAAgKzgjdfQD7AAAAAA==.Tavok:BAABNQAECn8rAAIOAAkKWRxbBgCnAgAOAAkKWRxbBgCnAgAAAA==.Tazbis:BAAANQAECgQIBgAAAA==.',
Te='Teishuku:BAABNQAECn9CAAIGAAoKFRMNRADtAQAGAAoKFRMNRADtAQAAAA==.Teusday:BAABNQAECn8rAAMKAAkKPhLhOADxAQAKAAkKPhLhOADxAQAZAAQKRgZoYAByAAAAAA==.',
Th='Thiux:BAABNQAECn8vAAMhAAoKJh9OGwBbAgAhAAkKVR9OGwBbAgAUAAIKYB9vRACzAAAAAA==.Thoeleden:BAAANQAECgMIBgABNQAFFAcIFQAPANEeAA==.Thotsnprayrs:BAAANQAECgMIBgABNQAECggICAAFAAAAAA==.Thrappy:BAABNQAECn82AAMPAAkKJhseRgBJAgAPAAkKJhseRgBJAgAQAAcK1w9hogBRAQAAAA==.Thryna:BAAANQADCgEIAQAAAA==.Thugstyle:BAAANQABCgcIDgAAAA==.',
Ti='Tinsoon:BAAANQAECgQIBAAAAA==.Tintaglia:BAABNQAECn82AAMhAAoKoxmGKQANAgAhAAoKoxmGKQANAgAiAAEKZBHPMQAxAAABNQAECgcIGQAWAGUZAA==.Tirtun:BAABNQAECn9CAAIWAAoKmiA9AgBQAwAWAAoKmiA9AgBQAwAAAA==.',
Tr='Triggeer:BAABNQAECn8kAAINAAgKqhkcCwCPAQANAAgKqhkcCwCPAQAAAA==.Trolldemort:BAAANQADCgYIBgABNQAECggIGwAhAA0XAA==.',
Tu='Tully:BAABNQAECn8ZAAIRAAUK6gI81wCFAAARAAUK6gI81wCFAAAAAA==.Tunkhan:BAAANQADCgQIBwAAAA==.Turnaround:BAAANQABCgIIAgAAAA==.',
Tw='Twelvekill:BAACNQAFFH8PAAIRAAUK4BFTDQDqAAARAAUK4BFTDQDqAAA1AAQKfysAAhEACgpxH64nAPkCABEACgpxH64nAPkCAAAA.',
Ty='Tyliaa:BAABNQAECn82AAMPAAoKORpcLwCkAgAPAAoKORpcLwCkAgAQAAkKERB3MQCTAQABNQAECgYIEAAFAAAAAA==.',
Ul='Ultramon:BAABNQAECn8eAAIGAAkKWROygwAgAgAGAAkKWROygwAgAgAAAA==.',
Un='Unbreakabull:BAAANQAECgEIAQAAAA==.Unwell:BAABNQAECn8oAAIkAAoK1xeLDAAmAgAkAAoK1xeLDAAmAgAAAA==.',
Ur='Urgoochness:BAAANQADCgQIBAAAAA==.Urikhai:BAAANQADCggIAgAAAA==.',
Va='Vainglorious:BAAANQADCggIEwABNQAECgkJIgAZAAEdAA==.Valanora:BAABNQAECn81AAIiAAoKBhWsAgAbAgAiAAoKBhWsAgAbAgAAAA==.Valerie:BAAANQAECggICgABNQAECgoKNgASABQfAA==.Valinaxius:BAAANQAECgQICAAAAA==.Vanyr:BAAANQADCgIIAgAAAA==.Vapturov:BAAANQAECgQICAAAAA==.',
Ve='Veeks:BAABNQAECn82AAIQAAoKCAv3MwCHAQAQAAoKCAv3MwCHAQAAAA==.Velibast:BAAANQAECgQIBAAAAA==.Velikirn:BAABNQAECn8oAAMgAAoK2R7HBQDSAgAgAAkK2R7HBQDSAgAfAAkKKRZPDwD8AQAAAA==.Velimald:BAAANQAECgQIBAAAAA==.Velydia:BAAANQAECgYIBgAAAA==.Venefica:BAAANQAECgEIAwAAAA==.Verdracee:BAAANQABCgMIAwABNQAECgYIFwATAJ0EAA==.Versø:BAABNQAECn8eAAMdAAgK/BRhPgDVAQAdAAgK/BRhPgDVAQAeAAEKAAAiUwA1AAAAAA==.Veryzi:BAAANQAECgEIAgAAAA==.',
Vi='Vine:BAAANQADCgQIBQAAAA==.',
Vl='Vlyrae:BAAANQADCgMIAwAAAA==.',
Vo='Voidbreaker:BAAANQADCgcIBwAAAA==.Voidhearted:BAABNQAECn9HAAIDAAoKGxBGIwAYAgADAAoKGxBGIwAYAgAAAA==.Vonzuo:BAAANQAECgIIAgAAAA==.',
Vu='Vukodlak:BAAANQADCgcIDQABNQAECgcIGQAWAGUZAA==.',
['Vì']='Vìolet:BAAANQADCgMIAwABNQAECgkJNAAJALAfAA==.',
Wa='Warriorwuu:BAAANQABCgIIAgAAAA==.Wayshua:BAAANQADCgYIBgAAAA==.',
We='Werkajerk:BAAANQADCggICAABNQAFFAcIFQAPANEeAA==.Werkjathal:BAACNQAFFH8VAAIPAAcK0R53BgD8AQAPAAcK0R53BgD8AQA1AAQKfzIAAw8ACgrlJTkBANcDAA8ACgrlJTkBANcDABAABgq4H48lANYBAAAA.',
Wi='Wibbles:BAAANQADCgcICwAAAA==.Wigarthan:BAAANQADCgEIAQAAAA==.Wildsenpai:BAAANQADCgEIAgAAAA==.',
Wo='Wolfblitzer:BAABNQAECn8tAAIGAAoKoxbdRADqAQAGAAoKoxbdRADqAQAAAA==.Wolfmanbro:BAAANQADCgMIAwAAAA==.Wolfpride:BAAANQADCgUIBQAAAA==.Worgenator:BAAANQADCgMIAwAAAA==.Worldbane:BAABNQAECn8oAAIUAAoKJA6wBABTAQAUAAoKJA6wBABTAQAAAA==.',
Wr='Wraithlash:BAAANQAECggIDgAAAA==.',
Wt='Wtyczka:BAAANQABCgcIBwAAAA==.',
Wu='Wuu:BAAANQABCgIIAgAAAA==.Wuulock:BAAANQABCgEJAQAAAA==.',
Wy='Wynnhrt:BAAANQADCggICAAAAA==.',
Xa='Xalatath:BAABNQAECn8mAAIBAAoK2xuTCgA2AwABAAoK2xuTCgA2AwAAAA==.Xanakmando:BAAANQADCggIFQAAAA==.Xandertay:BAAANQADCgMIBQAAAA==.Xanthos:BAAANQADCgIIAgAAAA==.Xantosz:BAAANQAECgMIAQABNQAFFAUIEAAQAB8SAA==.',
Xi='Xianyu:BAABNQAECn8aAAMfAAYK7wKEFQB2AAAfAAYK7wKEFQB2AAAmAAEKIAC5WQAEAAAAAA==.',
Ya='Yarian:BAAANQAECgMIAwAAAA==.',
Ym='Ymirr:BAAANQABCgcICAAAAA==.',
Yu='Yuck:BAAANQAECgIIAgABNQAFFAcIFQAPANEeAA==.',
Za='Zachhunter:BAACNQAFFH8cAAMRAAcKoCEtDQCAAQASAAUKHh0tCgCgAQARAAQKdSMtDQCAAQA1AAQKfzkAAxIACgryJDMQAOcCABIACApYJDMQAOcCABEACArvIWtMALcBAAAA.Zachmage:BAAANQADCggIFgAAAA==.Zan:BAACNQAFFH8QAAMQAAUKHxLSCgDgAAAQAAQKHxLSCgDgAAAPAAQKPAkTIwCBAAA1AAQKfy4AAxAACgp+HxcjAPsCABAACgp+HxcjAPsCAA8AAwomETLcALAAAAAA.',
Ze='Zephrie:BAAANQADCgYIBgAAAA==.Zeronation:BAAANQAECgMIBAAAAA==.',
Zi='Zinderella:BAAANQAECgUICAABNQAECgoKMQARANMUAA==.',
Zu='Zultrix:BAAANQAECgQIBwAAAA==.',
Zy='Zylaeri:BAAANQAECgcIEQAAAA==.',
['Éo']='Éowyn:BAAANQADCgEIAQAAAA==.',
['Ël']='Ëllër:BAABNQAECn8XAAIUAAgK7Qb7JQBFAQAUAAgK7Qb7JQBFAQAAAA==.',
['ßä']='ßädër:BAAANQAECgMIAwABNQAECgoKNwASADoRAA==.',
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
