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

local lookup = {'Priest-Holy','Druid-Restoration','Priest-Shadow','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Hunter-Survival','Druid-Balance','Shaman-Restoration','DeathKnight-Frost','Warrior-Arms','Warrior-Protection','Warrior-Fury','Shaman-Elemental','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','Warlock-Destruction','Monk-Brewmaster','Mage-Arcane','Mage-Frost','Mage-Fire','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Rogue-Assassination','Rogue-Subtlety','Paladin-Holy','Monk-Windwalker','Warlock-Demonology','Warlock-Affliction','Shaman-Enhancement','Rogue-Outlaw','Monk-Mistweaver','Druid-Feral','Druid-Guardian','DemonHunter-Havoc','DemonHunter-Devourer','Priest-Discipline',}
local provider = {region='US',realm='Arathor',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abavok:BAAANQADCgcIBwAAAA==.Absoul:BAACNQAFFH8UAAIBAAQKJQsrDAD+AAABAAQKJQsrDAD+AAA1AAQKf0UAAgEACgovGU04AIcCAAEACgovGU04AIcCAAAA.Abyssian:BAAANQAECgcIEAAAAA==.',
Ac='Acedia:BAABNQAECn8jAAIBAAgKWhqxFgC8AQABAAgKWhqxFgC8AQAAAA==.',
Ad='Adellas:BAABNQAECn86AAICAAoKXBytAQD4AgACAAoKXBytAQD4AgAAAA==.Adern:BAABNQAECn9AAAIDAAoKAh06AQCiAgADAAoKAh06AQCiAgAAAA==.Adon:BAAANQADCgUIBQABNQAECgYICwAEAAAAAA==.Adonn:BAABNQAECn8vAAMFAAoK0RrfTwClAgAFAAoK0RrfTwClAgAGAAIKBgpAZwBGAAAAAA==.Adonshadriel:BAAANQAECgYICwAAAA==.',
Ae='Aelali:BAABNQAECn8bAAIHAAoKFAhbBwAFAgAHAAoKFAhbBwAFAgAAAA==.',
Af='Afador:BAAANQADCggIEgABNQAECgYIDgAEAAAAAA==.',
Al='Aladestar:BAACNQAFFH8JAAIIAAQK5w4RBwDuAAAIAAQK5w4RBwDuAAA1AAQKfysAAwgACgqaGKElAKUCAAgACgqaGKElAKUCAAIABgpOFLw4AFgBAAAA.Albinodh:BAAANQAECgMIBAAAAA==.Alchemy:BAAANQABCgEIAQABNQAFFAYIFAAJAFcjAA==.Alderleise:BAAANQADCgcIBwAAAA==.Alexein:BAACNQAFFH8KAAIKAAMKDgpdEgC3AAAKAAMKDgpdEgC3AAA1AAQKfyoAAgoACgoGF6cqAEYCAAoACgoGF6cqAEYCAAAA.',
Am='Amets:BAAANQAECggIEgAAAA==.Amorae:BAAANQADCggIDwAAAA==.',
An='Anabel:BAAANQAECgEIAQAAAA==.Anamii:BAAANQAECgQIBAAAAA==.Andorsi:BAAANQAECgEIAQAAAA==.',
Ao='Aoratos:BAAANQAECgEIAQAAAA==.',
Ar='Arachne:BAABNQAECn8dAAIDAAgKtgoaNgBzAQADAAgKtgoaNgBzAQAAAA==.Aracianluz:BAAANQAECggIDAAAAA==.Arak:BAAANQADCgIIAgAAAA==.Arce:BAAANQADCggIHgABNQAECgkJJQAKAD4SAA==.Arysia:BAAANQAECgUIBgAAAA==.Aryya:BAAANQADCgIIAgAAAA==.',
As='Ascaris:BAAANQAECgcIEAAAAA==.',
Av='Avalan:BAABNQAECn8yAAQLAAoKDBvxQgDBAgALAAoKNBrxQgDBAgAMAAYKjhu2GAClAQANAAYKExZaEQCPAQAAAA==.Avanolatwo:BAAANQADCgYIBgABNQAECgoKLwAJADUZAA==.Avashammy:BAABNQAECn8vAAMJAAoKNRlNLgCoAgAJAAoKNRlNLgCoAgAOAAYKyhCJlABxAQAAAA==.Aviendah:BAABNQAECn8WAAIPAAgKAQnnwwB6AQAPAAgKAQnnwwB6AQAAAA==.',
Aw='Awsomeonet:BAAANQAECggICAAAAA==.',
Az='Azdfghop:BAACNQAFFH8PAAMQAAgKHA8mCgCgAQAQAAcKCgwmCgCgAQAPAAIKcx54IACxAAA1AAQKfyUAAxAACgrbIkAWAKkCABAACQqsIUAWAKkCAA8AAgpZI0mkAGcAAAAA.Azzinotica:BAAANQAECgUIBgAAAA==.',
Ba='Baalsanaro:BAAANQADCggIFQABNQAECgQIBQAEAAAAAA==.Babeshot:BAABNQAECn8xAAIPAAoKxwpMdAAoAgAPAAoKxwpMdAAoAgAAAA==.Baelgar:BAAANQAECgMIAwAAAA==.',
Be='Bergur:BAAANQAECgEIAQABNQAECgoKLQARACojAA==.',
Bi='Bigbear:BAAANQADCggICAABNQAECgcIFgASACQRAA==.Biggy:BAAANQADCgIIAgAAAA==.Bignose:BAAANQAECgMICQABNQAFFAYIEwATANomAA==.Binksy:BAAANQAECgcIBwAAAA==.',
Bl='Blaaze:BAAANQADCgYIBgAAAA==.Blackfrost:BAAANQAECggIDwAAAA==.Blaiddyd:BAABNQAECn8sAAIPAAgK8BxXKQB1AQAPAAgK8BxXKQB1AQAAAA==.Bloodboi:BAAANQADCgYIBgAAAA==.',
Bo='Bomi:BAAANQADCgEIAQAAAA==.Boogereater:BAAANQAECgIIAgABNQAECgUICQAEAAAAAA==.',
Br='Brandawn:BAAANQAECgQIBQAAAA==.',
Bu='Burndasheep:BAABNQAECn8yAAQUAAoKUBH3IgCIAQAUAAoKJBH3IgCIAQAVAAIK4xPlDwCNAAAWAAEKew0ZDQA6AAAAAA==.',
['Bæ']='Bæyy:BAAANQAECgQIEQAAAA==.',
Ca='Calyris:BAAANQADCgIIBAAAAA==.Caspias:BAEANQADCggJEgAAAA==.Caylynn:BAAANQAECgQIAwAAAA==.Caynelin:BAAANQAECgEIAQAAAA==.',
Ce='Cestbusiness:BAAANQADCgUIBQAAAA==.',
Ch='Chaoslock:BAABNQAECn8WAAISAAcKJBHQFgC2AQASAAcKJBHQFgC2AQAAAA==.Chetter:BAAANQAECggIBgAAAA==.Chicknfajita:BAAANQAECgcICQABNQAECgoKGgAOAOwfAA==.Chickpea:BAAANQADCggIIQAAAA==.',
Co='Cocytus:BAAANQADCggIEgAAAA==.Colbith:BAABNQAECn8YAAIIAAYKxA12YgBEAQAIAAYKxA12YgBEAQAAAA==.Corblixx:BAAANQAECgEIAQAAAA==.Cordaddy:BAAANQAECgEIAwABNQAECgkJJwAJAHQlAA==.Cordelvo:BAAANQAECgUICgABNQAECgkJJwAJAHQlAA==.Cordragon:BAAANQAECgIIAgABNQAECgkJJwAJAHQlAA==.Cordragu:BAABNQAECn8nAAIJAAkKdCVEBACoAwAJAAkKdCVEBACoAwAAAA==.Cordran:BAAANQAECgEIAgABNQAECgkJJwAJAHQlAA==.Corinthin:BAAANQADCgQIBAAAAA==.Corraa:BAAANQADCgEIAQAAAA==.',
Cr='Crakum:BAABNQAECn8XAAIOAAYKrRS0iwCHAQAOAAYKrRS0iwCHAQAAAA==.Crinn:BAABNQAECn8bAAMXAAcKDg3FagBnAQAXAAcKDg3FagBnAQAKAAIK3AN5owBHAAAAAA==.Crizmon:BAABNQAECn8eAAIKAAkKRx8MFQDkAgAKAAkKRx8MFQDkAgAAAA==.',
Cu='Cucumber:BAAANQADCgcICQAAAA==.',
Da='Damorthyx:BAABNQAECn8XAAIYAAgKYwvNVQCcAQAYAAgKYwvNVQCcAQAAAA==.Darazarke:BAACNQAFFH8dAAMZAAcKmQ6JBQAOAgAZAAcKmQ6JBQAOAgAaAAEKLQVIDQA9AAA1AAQKfyoABBkACgp7GAcTAHwCABkACgp7GAcTAHwCABsAAQqKFrsRAFIAABoAAQrTFrYMAEcAAAAA.Darkquill:BAABNQAECn8hAAIOAAgKtg6LcwDGAQAOAAgKtg6LcwDGAQAAAA==.Daspoof:BAAANQADCgYIBgAAAA==.Dayquil:BAEANQADCgcIBwABNQAECgoKKAAFAKMZAA==.',
De='Deadaddie:BAAANQAECgcIDAABNQAECgoKJgAUAJ0hAA==.Deamoneyes:BAAANQAECgQIBgAAAA==.Deathkauf:BAAANQAECgEIAQAAAA==.Deathvok:BAAANQADCgMIAwAAAA==.Demolitions:BAAANQAECggICAAAAA==.Dezatra:BAAANQADCgcIBgAAAA==.',
Dh='Dhonaan:BAAANQADCgEIAQAAAA==.',
Di='Dieselcon:BAABNQAECn84AAMGAAoKjRQaGgAhAgAGAAoKjRQaGgAhAgAFAAQK/gXUSgGoAAAAAA==.Diprivan:BAABNQAECn8tAAMcAAoK5h7ZEQDuAgAcAAoKvhzZEQDuAgAdAAYKGBr7EgA/AQAAAA==.',
Do='Dolobrik:BAAANQABCgYIBwAAAA==.Domdog:BAABNQAECn8dAAIUAAcKvgdJBQGFAQAUAAcKvgdJBQGFAQAAAA==.Domína:BAAANQAECgQICAAAAA==.Dontforget:BAAANQAECgYIDAAAAA==.Doomdealer:BAABNQAECn8ZAAMKAAgKHA7NTACFAQAKAAcKHA7NTACFAQAYAAEKAACKugBSAAAAAA==.Doomed:BAABNQAECn8YAAIeAAgKPB9vJgDQAgAeAAgKPB9vJgDQAgAAAA==.Doonya:BAAANQADCggICwAAAA==.Dottee:BAAANQAECggIAwAAAA==.Dougwalker:BAAANQADCgIIAgAAAA==.',
Dr='Dracodaddy:BAAANQADCgIIAgAAAA==.Draftymonk:BAABNQAECn8XAAMTAAcKMR9QCgBxAgATAAYK6SNQCgBxAgAfAAMKLBAwUQCuAAAAAA==.Drage:BAABNQAECn8pAAMgAAoKzhUCRACGAgAgAAoKzhUCRACGAgASAAEKdgMvhQAkAAAAAA==.Drax:BAABNQAECn8hAAMhAAkKzgp/DwBWAQAgAAkKDwiMogCQAQAhAAYKEwx/DwBWAQAAAA==.Dreadgar:BAAANQAECgQIBQABNQAECgoKGwAOAAofAA==.Dritzzagain:BAAANQAECgUIDAAAAA==.Dritzzcat:BAAANQADCgYICwAAAA==.',
Dw='Dwreck:BAAANQAECgcIDgAAAA==.',
Ed='Ediann:BAAANQAECggIDgAAAA==.',
El='Elandrus:BAAANQAECgUICgABNQAECgkJKwAUAAkWAA==.Eldarine:BAAANQADCgUIBQAAAA==.',
Em='Emmara:BAABNQAECn8iAAIQAAkKfQMTFQDcAAAQAAkKfQMTFQDcAAAAAA==.',
En='Enitar:BAAANQADCgcICAABNQAECgoKMgAUAFARAA==.',
Er='Erata:BAAANQAECgQIEAAAAA==.Erlik:BAAANQADCgMIBAAAAA==.Erzakzaktraz:BAAANQADCgYIBgABNQADCgcIBgAEAAAAAA==.',
Ev='Evullight:BAAANQADCgEJAQAAAA==.',
Ez='Ezlok:BAABNQAECn8bAAIOAAoKCh9pIAAKAwAOAAoKCh9pIAAKAwAAAA==.',
Fa='Facemash:BAAANQAECgQIBAABNQAECgoKMgAUAFARAA==.Faedra:BAAANQADCggICAABNQAECgoKLAABAGgeAA==.Falerin:BAABNQAECn8hAAICAAoKIRp0GAB7AgACAAoKIRp0GAB7AgAAAA==.Farryn:BAAANQADCgEIAQAAAA==.',
Fe='Feenex:BAAANQAECgUIDgAAAA==.Feldora:BAAANQADCgYIBgAAAA==.Festiva:BAAANQAECgIIBAAAAA==.',
Fi='Fillorey:BAAANQADCggICAABNQAECgkJKwAUAAkWAA==.Firedealer:BAABNQAECn8vAAMQAAoKuhAbJgAbAgAQAAoKlBAbJgAbAgAPAAQKbxKN8gAcAQAAAA==.',
Fl='Flappy:BAAANQAECgIIBAABNQAECgkJLgAJAEsYAA==.Flashmaster:BAAANQAECgUIDgAAAA==.Flawlessheal:BAAANQADCgMIAwAAAA==.Fluffybutt:BAAANQADCggIFAAAAA==.',
Fo='Fossora:BAAANQADCgcIBgAAAA==.',
Fr='Freyiah:BAAANQADCgYJBgAAAA==.',
Fy='Fyatre:BAAANQAECgYIDwAAAA==.',
Ga='Galath:BAAANQAECgUJCAABNQAECgMIAwAEAAAAAA==.Gameover:BAAANQABCgEIAgAAAA==.Gandallf:BAAANQADCgUIBQAAAA==.',
Ge='Gerree:BAAANQADCgYICgAAAA==.Gerry:BAAANQAECgQIBAABNQAECgkJKQANAIQZAA==.',
Gg='Ggkando:BAABNQAECn8UAAIPAAUKPQrngACrAAAPAAUKPQrngACrAAAAAA==.',
Gh='Ghemaldir:BAAANQABCgIIAgAAAA==.',
Gi='Gildius:BAAANQADCgIIAgAAAA==.Gingerail:BAAANQAECgQIBwAAAA==.',
Gl='Glory:BAABNQAECn8cAAIYAAkKahs9IwCdAgAYAAkKahs9IwCdAgAAAA==.',
Gn='Gnayami:BAAANQADCggIDQAAAA==.',
Go='Goochsquirts:BAABNQAECn8fAAIJAAgKRxsOUAAlAgAJAAgKRxsOUAAlAgAAAA==.Govna:BAAANQADCggIFAAAAA==.',
Gr='Grakkaem:BAAANQAECgMJBAAAAA==.Grannet:BAAANQADCgMIBQAAAA==.Gravedygger:BAABNQAECn8yAAIPAAoKCBPrSgCNAgAPAAoKCBPrSgCNAgAAAA==.Greenfear:BAAANQADCgYIBgAAAA==.Grenswood:BAAANQAECgcIDgAAAA==.Greybeeredd:BAAANQAECgEIAgAAAA==.Grimmkin:BAABNQAECn8mAAQiAAoKrhlKCwC8AgAiAAoKrhlKCwC8AgAJAAIKrA8e/gBuAAAOAAEKAACtQwEsAAAAAA==.Grind:BAAANQAECgQIBAABNQAECgYIDgAEAAAAAA==.Growl:BAAANQADCgUIBQAAAA==.Grumbo:BAAANQADCgcIBgAAAA==.',
Gu='Guuldurak:BAAANQADCgcIBgAAAA==.',
Ha='Hailcat:BAAANQAECgMIBAABNQAECgoKIwAgAC0PAA==.Handivhe:BAAANQADCgYIBgAAAA==.Hasew:BAABNQAECn85AAIPAAkKBx96AgDVAgAPAAkKBx96AgDVAgAAAA==.',
He='He:BAAANQAECgQICAABNQAECgkJJQAKAD4SAA==.Helpimßlind:BAAANQAECgcIEAAAAA==.Hera:BAACNQAFFH8LAAIPAAQKTCFfBAAXAQAPAAQKTCFfBAAXAQA1AAQKfyoAAg8ACgoWJh4EAMcDAA8ACgoWJh4EAMcDAAAA.Heyner:BAABNQAECn8zAAIjAAoKARb+BACtAgAjAAoKARb+BACtAgAAAA==.',
Hi='Hinral:BAACNQAFFH8KAAIkAAQKnxrlAQBPAQAkAAQKnxrlAQBPAQA1AAQKfyoAAiQACgorJKACAJMDACQACgorJKACAJMDAAAA.',
Ho='Holyiaa:BAAANQAECgUIBQABNQAECgYIDAAEAAAAAA==.Holyluz:BAAANQAECgEIAQABNQAECggIDAAEAAAAAA==.Holysmacker:BAAANQAECgEIAQABNQAECgcIGQAVAGUZAA==.',
Hy='Hymns:BAAANQAECggIAgAAAA==.',
['Hë']='Hëll:BAABNQAECn8jAAMgAAoKLQ9acwAHAgAgAAoKLQ9acwAHAgASAAEKGRC/cwA7AAAAAA==.',
Il='Illaynne:BAABNQAECn8nAAIBAAgKIBD8IQB6AQABAAgKIBD8IQB6AQAAAA==.',
Im='Imani:BAACNQAFFH8KAAIiAAQKwAEOAgC3AAAiAAQKwAEOAgC3AAA1AAQKfyoAAiIACgqvChgVABcCACIACgqvChgVABcCAAAA.Immensepain:BAAANQAECgQIBAAAAA==.',
In='Inoshikacho:BAABNQAECn8gAAIlAAkKGAhVHABAAQAlAAkKGAhVHABAAQAAAA==.Involio:BAAANQAECgEIAQAAAA==.',
Ir='Irishmecha:BAACNQAFFH8MAAIcAAQKdAh3AwDSAAAcAAQKdAh3AwDSAAA1AAQKfyoAAhwACgqmHd0VAM0CABwACgqmHd0VAM0CAAAA.Irishpaws:BAAANQAECgEIAQAAAA==.Ironshot:BAAANQADCggIBgAAAA==.',
Is='Isaeus:BAAANQAECgEIAQAAAA==.',
It='Itharillys:BAABNQAECn8lAAIPAAkKaRLrcwAoAgAPAAkKaRLrcwAoAgAAAA==.',
Ja='Jaadu:BAAANQADCgQIBAAAAA==.Jangus:BAAANQAECgYIDgAAAA==.Jaybone:BAAANQADCggICQAAAA==.',
Je='Jeefus:BAAANQAECggIAgAAAA==.Jeennkiins:BAAANQADCgYIBgABNQAECgMIAwAEAAAAAA==.Jenifur:BAAANQAECgIIAwABNQAECgoKLAABAGgeAA==.Jessibella:BAAANQADCgQIBAAAAA==.Jezzako:BAAANQAECgcICwAAAA==.',
Ji='Jinx:BAAANQADCgQIBAABNQAECgoKLAABAGgeAA==.',
Jo='Johali:BAAANQAECgUICgAAAA==.Jozan:BAAANQADCggIGQAAAA==.',
Ju='Justise:BAAANQADCgIIAgABNQADCgYJCwAEAAAAAA==.',
['Jö']='Jöhnblaze:BAABNQAECn80AAILAAoKew8nDgDqAQALAAoKew8nDgDqAQAAAA==.',
Ka='Kaga:BAAANQADCgEJAQABNQAECgoKMgAUAFARAA==.Kailys:BAABNQAECn8nAAIGAAgKJhHKIADeAQAGAAgKJhHKIADeAQAAAA==.Kaisana:BAAANQAECgYICwAAAA==.Kaishias:BAABNQAECn8fAAIFAAkKCxjbkQABAgAFAAkKCxjbkQABAgAAAA==.Kaldrek:BAAANQAECgMIBQABNQAECgUIDQAEAAAAAA==.Kandoh:BAAANQADCggIEwABNQAECgUIFAAPAD0KAA==.Kankuró:BAABNQAECn8uAAIPAAoKWhwmHwAbAwAPAAoKWhwmHwAbAwAAAA==.Karelleira:BAAANQADCgUIBQAAAA==.Kautie:BAAANQAECgUICQAAAA==.',
Ki='Killahmike:BAAANQAECgQIBgAAAA==.Killudead:BAAANQAECgcICAAAAA==.Kishana:BAAANQADCgcIBgAAAA==.',
Ko='Kodetra:BAAANQAECgYIDgAAAA==.Kolgrim:BAABNQAECn8gAAMKAAkK5xG6PQDVAQAKAAkK8wy6PQDVAQAYAAYK4BVZZABhAQAAAA==.Kong:BAAANQAECgIIAgAAAA==.Korimya:BAAANQADCggIDAAAAA==.Korvuk:BAAANQAECgUIDQAAAA==.',
Kr='Krom:BAABNQAECn8ZAAMOAAcK1wwCpwBGAQAOAAYKXw8CpwBGAQAJAAUKKgbM0wC/AAAAAA==.Krysta:BAABNQAECn8sAAMBAAoKaB4qMgCfAgABAAoKaB4qMgCfAgADAAEKAACegQAoAAAAAA==.',
Ky='Kynris:BAAANQADCggIEQABNQAECgkJKwAUAAkWAA==.',
La='Lanaal:BAAANQADCgEIAQAAAA==.Lancewh:BAAANQADCgcIDAAAAA==.Lanciwinluna:BAAANQADCgQIBAAAAA==.Lancywinelia:BAAANQADCgQIBgAAAA==.Lauryssa:BAAANQADCggICAAAAA==.',
Ld='Ldydthstryke:BAAANQAECgYIBgABNQAECgoKLwAQALoQAA==.',
Le='Legg:BAAANQABCgMIAwAAAA==.Legolâs:BAAANQADCgUIBQAAAA==.Leonora:BAAANQAECgcIEwAAAA==.Leviathañ:BAAANQADCgIIAgABNQAECgcIDgAEAAAAAA==.Lezene:BAAANQAECgMIAwAAAA==.',
Li='Linstriker:BAABNQAECn8qAAImAAkKniBkCgDKAgAmAAkKniBkCgDKAgABNQAFFAYIFAAJAFcjAA==.',
Lo='Lorette:BAABNQAECn8mAAMBAAoK5BjrKQBWAQABAAoK5BjrKQBWAQADAAcK6xxOCgBRAQAAAA==.',
Lu='Lucethegoose:BAAANQADCgQIBAAAAA==.Luckynyx:BAAANQAECgEIAQAAAA==.Lunate:BAAANQAECgEIAQABNQAECgoKMAADAGofAA==.Lunavere:BAAANQADCgQIBgAAAA==.',
Ma='Machotedan:BAABNQAECn80AAIFAAoK+R/3KgAbAwAFAAoK+R/3KgAbAwAAAA==.Macmittens:BAAANQADCggIHQAAAA==.Mamadrag:BAAANQAECgYIDAAAAA==.Managua:BAAANQADCgEIAQAAAA==.Mandwa:BAAANQADCggIGAABNQAECgoKMgAUAFARAA==.Mangojuulpod:BAAANQADCgYIBgAAAA==.Mario:BAABNQAECn8ZAAIVAAcKZRkuBAB0AQAVAAcKZRkuBAB0AQAAAA==.Mastashifta:BAAANQAECgMIBAAAAA==.Mataa:BAABNQAECn8rAAIUAAkKCRZ3RwAtAQAUAAkKCRZ3RwAtAQAAAA==.Matryoshka:BAAANQADCgUIDQABNQADCggICwAEAAAAAA==.Mattsadler:BAAANQADCgMIAwAAAA==.Maxxim:BAAANQADCggIHwAAAA==.Mayihmpurleg:BAAANQAECgUIBQABNQAECgoKLwAQALoQAA==.Mazeman:BAAANQADCgUIBQAAAA==.',
Me='Mellachion:BAAANQAECgUIBQABNQAECgcIGQAVAGUZAA==.Meta:BAAANQAECgcICgAAAA==.',
Mi='Mishaps:BAAANQABCgEIAQAAAA==.Missaoife:BAAANQABCgEIAQAAAA==.Mistaya:BAAANQADCgUIBQABNQAECggIFgAgAIoIAA==.Mists:BAAANQAFFAQIBAAAAA==.Miththrawndo:BAABNQAECn8mAAIYAAkKLg4LVACkAQAYAAkKLg4LVACkAQAAAA==.',
Mo='Mohrgyn:BAAANQABCgEIAQAAAA==.Momjeans:BAABNQAECn8sAAIUAAoK0x3pXQDEAgAUAAoK0x3pXQDEAgAAAA==.',
Mu='Mumbo:BAAANQADCgcIBwABNQAECgYIDgAEAAAAAA==.Muu:BAAANQADCgYICAAAAA==.',
My='Mydaan:BAAANQADCgIIAwAAAA==.Mythunsarian:BAABNQAECn8VAAInAAgKtAcnGgAjAQAnAAgKtAcnGgAjAQAAAA==.',
['Má']='Mákï:BAABNQAECn8aAAILAAgKNBCHkQDwAQALAAgKNBCHkQDwAQAAAA==.',
['Mä']='Mäylä:BAABNQAECn8hAAIIAAkKaAxDSgC+AQAIAAkKaAxDSgC+AQAAAA==.',
['Mí']='Míst:BAABNQAECn82AAIFAAoKixhhGADCAQAFAAoKixhhGADCAQAAAA==.',
Na='Narlis:BAABNQAECn8tAAIXAAoKnCE7CgBrAwAXAAoKnCE7CgBrAwAAAA==.',
Ne='Nephie:BAAANQAECgYICwAAAA==.Nezqk:BAACNQAFFH8KAAQKAAMKKBU1FQCVAAAXAAIKlxHyFwCaAAAKAAIKExU1FQCVAAAYAAEKAADyGgAAAAA1AAQKfyoABBcACgoUGvcyAF8CABcACQpuHPcyAF8CABgACAqQEvZOALkBAAoABQoyE8w2AMQAAAAA.Nezquick:BAAANQAECgIIAgAAAA==.',
Ni='Niano:BAAANQABCgIIAgAAAA==.',
Nm='Nmnenthe:BAABNQAECn8dAAIbAAgKQhbGFAABAgAbAAgKQhbGFAABAgAAAA==.',
No='Notrealword:BAAANQAECgYICQABNQAECgkJOQAPAAcfAA==.Noxluminous:BAAANQABCgIIAgAAAA==.',
Ob='Obin:BAABNQAECn8dAAMNAAcKSA63GgD6AAALAAcKaw1v1ABIAQANAAUKlg23GgD6AAAAAA==.',
Oc='Occasionally:BAAANQAECgIIAgAAAA==.',
Ok='Okukoy:BAAANQABCgEIAQAAAA==.',
Om='Ominious:BAABNQAECn8oAAMiAAoKvxIuFAAmAgAiAAkKJxEuFAAmAgAOAAUKtRcBqgBAAQABNQAECgcIBwAEAAAAAA==.Omnissia:BAAANQAECgUIAwABNQAECgcIBwAEAAAAAA==.Omnius:BAABNQAECn8XAAMOAAoKdBdeYAAAAgAOAAoKdBdeYAAAAgAJAAEKMAu9KQEkAAAAAA==.Omnya:BAAANQAECgcIDQABNQAECgcIBwAEAAAAAA==.Omnyi:BAAANQAECgcIBwAAAA==.',
Ow='Owendriel:BAACNQAFFH8HAAIoAAMKZg+zBgCFAAAoAAMKZg+zBgCFAAA1AAQKfxgAAygACgpzEx0oAAMCACgACQrEER0oAAMCACcAAwrpEglxALUAAAAA.',
Pa='Paindya:BAAANQAECgUICQAAAA==.Paleigh:BAAANQABCgYIDQAAAA==.Palivok:BAAANQADCgMIAwAAAA==.Pandress:BAAANQAECgYIEgAAAA==.Pankake:BAAANQAECgQIBAABNQAECgoKLQARACojAA==.Paralysis:BAACNQAFFH8KAAIoAAQKpwxXDQDWAAAoAAQKpwxXDQDWAAA1AAQKfykAAigACgqpFiEeAGACACgACgqpFiEeAGACAAAA.',
Pe='Peetza:BAAANQADCgYIBgABNQAECgoKLQARACojAA==.Peryite:BAABNQAECn8vAAMBAAkK6BiAPAB4AgABAAkK6BiAPAB4AgApAAQK6xBhFQDUAAAAAA==.',
Ph='Phaedrana:BAAANQAECgcIDgAAAA==.',
Pi='Pisscat:BAAANQAECgQICQAAAA==.',
Po='Pocketdragon:BAABNQAECn8tAAMbAAoKZxUhDwBpAgAbAAoKchQhDwBpAgAaAAYKWhBOEAA1AQAAAA==.',
Pr='Prideindeath:BAAANQADCgUIBQAAAA==.Promiscuity:BAABNQAECn8fAAMgAAoK2RIYGACSAQAgAAoK2RIYGACSAQAhAAIKwwlCIgBpAAAAAA==.Prængle:BAAANQADCgYIAwAAAA==.',
Ps='Psoas:BAABNQAECn8wAAMDAAoKah8nCABaAwADAAoKah8nCABaAwABAAIK4BBH5AB7AAAAAA==.Psypriest:BAECNQAFFH8HAAIBAAMKYheVEQClAAABAAMKYheVEQClAAA1AAQKfywAAgEACQoNH44FAKYCAAEACQoNH44FAKYCAAE1AAUUBwggAAEAvg8A.',
Py='Pyroheal:BAAANQAECgUICAAAAA==.',
Qu='Quaichang:BAAANQADCgYIBgAAAA==.',
Ra='Rabbi:BAABNQAECn8tAAMDAAoK9xjkEgDTAgADAAkKJBvkEgDTAgABAAEKohkriQBQAAAAAA==.Radaster:BAAANQABCgEIAQAAAA==.Rahfna:BAAANQADCgcIDwAAAA==.Railænu:BAAANQADCggIDgAAAA==.Rainmist:BAAANQADCgYIBgAAAA==.Ranric:BAAANQAECgMIAwAAAA==.',
Re='Redall:BAAANQADCgQIBAAAAA==.Reesespbc:BAAANQAECgYIDQAAAA==.Reina:BAAANQAECgUICQABNQAECgoKLAABAGgeAA==.Reinz:BAAANQAECgYIBgAAAA==.Rektagar:BAABNQAECn8sAAIOAAoKKSTUBQC8AwAOAAoKKSTUBQC8AwABNQAFFAcIGwAPAKAhAA==.Ressandra:BAAANQADCgMIBgAAAA==.Rezo:BAAANQAECgEIAgAAAA==.',
Ri='Riverarose:BAAANQADCggIFQAAAA==.',
Ro='Roar:BAAANQAECgQICgABNQAECgYIDgAEAAAAAA==.',
Ry='Rysi:BAAANQADCgQIBAAAAA==.',
['Rò']='Ròs:BAACNQAFFH8MAAIGAAQKmhYGAwDJAAAGAAQKmhYGAwDJAAA1AAQKfyoAAgYACgoIH0cKAPYCAAYACgoIH0cKAPYCAAAA.',
['Rö']='Rös:BAAANQADCgEIAQABNQAFFAQIDAAGAJoWAA==.',
Sa='Saberie:BAAANQADCggIFwABNQADCgMIBgAEAAAAAA==.Salaria:BAABNQAECn8gAAIoAAcKtw/5MwCjAQAoAAcKtw/5MwCjAQAAAA==.Salina:BAEANQAECgcIEgAAAA==.Sandstique:BAABNQAECn8tAAIJAAoKYiQpEwAxAwAJAAoKYiQpEwAxAwAAAA==.Sandweaver:BAAANQADCgcIBwAAAA==.Sanjira:BAAANQADCgYIBgAAAA==.Sarlak:BAABNQAECn8rAAMPAAoKphw5JQACAwAPAAoKphw5JQACAwAQAAEK8AYalwAqAAAAAA==.Sarusuby:BAABNQAECn86AAImAAoKlhFVBgCgAQAmAAoKlhFVBgCgAQAAAA==.Satae:BAABNQAECn8tAAIRAAoKKiOBAgBZAwARAAoKKiOBAgBZAwAAAA==.',
Sc='Schufft:BAABNQAECn8ZAAISAAcKzBuCCAB1AgASAAcKzBuCCAB1AgAAAA==.Scottydh:BAAANQAECgIIAgABNQAECgoKMwAYAIsfAA==.Scottymac:BAABNQAECn8zAAIYAAoKix9IDwA0AwAYAAoKix9IDwA0AwAAAA==.Scottypal:BAAANQAECgQIBQABNQAECgoKMwAYAIsfAA==.',
Se='Seatah:BAAANQAECgMIAwAAAA==.Seba:BAABNQAECn8ZAAIOAAgKyxXQDgCdAQAOAAgKyxXQDgCdAQAAAA==.Seetah:BAABNQAECn8cAAMBAAkKPBRvWQAVAgABAAkKPBRvWQAVAgADAAIK6wyOZwBiAAAAAA==.Sekarius:BAAANQABCgEIAQAAAA==.Seraphtharia:BAAANQABCgIIAgAAAA==.Sermon:BAAANQADCgQIBAABNQAECgYIDgAEAAAAAA==.',
Sh='Shadaddy:BAABNQAECn8mAAMUAAoKnSEZUgDcAgAUAAkK/SAZUgDcAgAVAAMKNyALHwDyAAAAAA==.Shadowheart:BAAANQAECgEIAQAAAA==.Shakasana:BAAANQAECgEIAQAAAA==.Shal:BAABNQAECn8hAAILAAgK6ha+KwBbAQALAAgK6ha+KwBbAQAAAA==.Shamanluz:BAAANQADCgIIAgABNQAECggIDAAEAAAAAA==.Shamommy:BAAANQADCgUIBAAAAA==.Shamtaz:BAAANQAECgYICgAAAA==.Shimmerstar:BAABNQAECn8cAAIFAAkKYR0pcQBNAgAFAAkKYR0pcQBNAgAAAA==.Shroomgirl:BAAANQAECgUIBQAAAA==.Shrubhub:BAAANQAECgEIAQABNQAECggIGAAeADwfAA==.',
Si='Silexe:BAABNQAECn8YAAMaAAYKZhYaBAD7AAAaAAYKTRYaBAD7AAAbAAIKxRQMEwBHAAAAAA==.Sitga:BAAANQADCgIIAgAAAA==.',
Sl='Slinga:BAAANQADCgcICQAAAA==.Slipperyboi:BAAANQAECgQICQAAAA==.Slÿ:BAAANQAECgIIAgAAAA==.',
Sm='Smokintotems:BAAANQABCgEIAQAAAA==.',
So='Solarion:BAAANQAECgYIDwABNQAECgoKGwAOAAofAA==.Soldraca:BAAANQAECgMIAwAAAA==.',
St='Stats:BAAANQAECgUIDwABNQAECgYIDgAEAAAAAA==.Stinkbug:BAAANQADCgQIBAAAAA==.Stutters:BAABNQAECn8uAAIYAAoKrRxwCwCPAQAYAAoKrRxwCwCPAQAAAA==.',
Su='Subayyru:BAAANQADCgEIAQABNQAECgQIEQAEAAAAAA==.Sudachi:BAAANQADCgYIBgABNQAFFAYKEwAfAFscAA==.Sunnyräy:BAAANQAECgMIAwAAAA==.Superiorkill:BAAANQADCgcIBwAAAA==.Suthrheimr:BAABNQAECn8pAAINAAkKhBnRBgCWAgANAAkKhBnRBgCWAgAAAA==.',
Sy='Symphany:BAAANQABCggIEQAAAA==.',
['Sý']='Sýndrá:BAAANQAECgYIDQAAAA==.',
Ta='Takafune:BAAANQADCgQIBgAAAA==.Talespin:BAAANQAECgUIBQAAAA==.Talysiah:BAABNQAECn8WAAIgAAgKigivVgDVAAAgAAgKigivVgDVAAAAAA==.Tavok:BAABNQAECn8kAAINAAgKcx1bBgCnAgANAAgKcx1bBgCnAgAAAA==.Tazbis:BAAANQAECgIIAgAAAA==.',
Te='Teishuku:BAABNQAECn86AAIFAAoK6BFlEQDwAQAFAAoK6BFlEQDwAQAAAA==.Teusday:BAABNQAECn8lAAIKAAkKPhI5HwApAQAKAAkKPhI5HwApAQAAAA==.',
Th='Thiux:BAABNQAECn8oAAMgAAkKsh3GDADlAQAgAAgKqx3GDADlAQASAAIKYB9vRACzAAAAAA==.Thoeleden:BAAANQAECgMIBgABNQAFFAYIFAAJAFcjAA==.Thotsnprayrs:BAAANQAECgMIBgABNQAECggIGAAeADwfAA==.Thrappy:BAABNQAECn8uAAMJAAkKSxgeRgBJAgAJAAkKSxgeRgBJAgAOAAcK1w9hogBRAQAAAA==.Thryna:BAAANQADCgEIAQAAAA==.Thugstyle:BAAANQABCggIDgAAAA==.',
Ti='Tinsoon:BAAANQAECgQIBAAAAA==.Tintaglia:BAABNQAECn8uAAMgAAoKNRdiQgCLAgAgAAoKNRdiQgCLAgAhAAEKZBHPMQAxAAABNQAECgcIGQAVAGUZAA==.Tirtun:BAABNQAECn83AAIVAAoKph95AAChAgAVAAoKph95AAChAgAAAA==.',
Tr='Triggeer:BAABNQAECn8kAAIMAAgKqhltAwCwAQAMAAgKqhltAwCwAQAAAA==.Trolldemort:BAAANQADCgYIBgABNQAECggIGwAgAA0XAA==.',
Tu='Tully:BAABNQAECn8UAAIPAAUK6gIgowBpAAAPAAUK6gIgowBpAAAAAA==.Tunkhan:BAAANQADCgQIBwAAAA==.',
Tw='Twelvekill:BAACNQAFFH8LAAIPAAQKtxF2GgDnAAAPAAQKtxF2GgDnAAA1AAQKfyoAAg8ACgpxH64nAPkCAA8ACgpxH64nAPkCAAAA.',
Ty='Tyliaa:BAABNQAECn8qAAMJAAoKZxhcLwCkAgAJAAoKZxhcLwCkAgAOAAQKHQ60RwC2AAABNQAECgYIDAAEAAAAAA==.',
Ul='Ultramon:BAABNQAECn8eAAIFAAkKWROygwAgAgAFAAkKWROygwAgAgAAAA==.',
Un='Unbreakabull:BAAANQAECgEIAQAAAA==.Unwell:BAABNQAECn8lAAIoAAoK1xexAQB3AgAoAAoK1xexAQB3AgAAAA==.',
Ur='Urgoochness:BAAANQADCgQIBAAAAA==.Urikhai:BAAANQADCggIAgAAAA==.',
Va='Vainglorious:BAAANQADCggIEwABNQAECgkJHAAYAGobAA==.Valanora:BAABNQAECn8sAAIhAAoK9BRUBwApAgAhAAoK9BRUBwApAgAAAA==.Valerie:BAAANQAECgIIAgABNQAECgoKLgAQAJkcAA==.Valinaxius:BAAANQAECgQIBAAAAA==.Vanyr:BAAANQADCgIIAgAAAA==.Vapturov:BAAANQAECgMIBAAAAA==.',
Ve='Veeks:BAABNQAECn8tAAIOAAoKHAoUdwC8AQAOAAoKHAoUdwC8AQAAAA==.Velibast:BAAANQAECgQIBAAAAA==.Velikirn:BAABNQAECn8fAAMfAAoKSBsrAQCqAgAfAAkKSBsrAQCqAgATAAgKWRVPDwD8AQAAAA==.Velimald:BAAANQAECgQIBAAAAA==.Velydia:BAAANQAECgYIBgAAAA==.Venefica:BAAANQAECgEIAwAAAA==.Verdracee:BAAANQABCgMIBAABNQAECgUICwAEAAAAAA==.Versø:BAABNQAECn8cAAMcAAgK8xRhPgDVAQAcAAgK8xRhPgDVAQAdAAEKAAAiUwA1AAAAAA==.Veryzi:BAAANQAECgEIAgAAAA==.',
Vi='Vine:BAAANQADCgQIBQAAAA==.',
Vl='Vlyrae:BAAANQADCgMIAwAAAA==.',
Vo='Voidbreaker:BAAANQADCgcIBwAAAA==.Voidhearted:BAABNQAECn8/AAIDAAoKlg9GIwAYAgADAAoKlg9GIwAYAgAAAA==.Vonzuo:BAAANQAECgIIAgAAAA==.',
Vu='Vukodlak:BAAANQADCgcIDQABNQAECgcIGQAVAGUZAA==.',
['Vì']='Vìolet:BAAANQADCgMIAwABNQAECggILAAIAGggAA==.',
Wa='Warriorwuu:BAAANQABCgIIAgAAAA==.Wayshua:BAAANQADCgYIBgAAAA==.',
We='Werkajerk:BAAANQADCggICAABNQAFFAYIFAAJAFcjAA==.Werkjathal:BAACNQAFFH8UAAIJAAYKVyN3BgD8AQAJAAYKVyN3BgD8AQA1AAQKfykAAwkACgr5JDkBANcDAAkACgr5JDkBANcDAA4AAQqpIEJsAGYAAAAA.',
Wi='Wibbles:BAAANQADCgcICwAAAA==.Wigarthan:BAAANQADCgEIAQAAAA==.Wildsenpai:BAAANQADCgEIAgAAAA==.',
Wo='Wolfblitzer:BAABNQAECn8kAAIFAAoKPhY8kgAAAgAFAAoKPhY8kgAAAgAAAA==.Wolfpride:BAAANQADCgYIBQAAAA==.Worgenator:BAAANQADCgMIAwAAAA==.Worldbane:BAABNQAECn8mAAISAAgKFw9qEQDtAQASAAgKFw9qEQDtAQAAAA==.',
Wr='Wraithlash:BAAANQAECggIDgAAAA==.',
Wt='Wtyczka:BAAANQABCgcICAAAAA==.',
Wu='Wuu:BAAANQABCgIIAgAAAA==.Wuulock:BAAANQABCgEJAQAAAA==.',
Wy='Wynnhrt:BAAANQADCggICAAAAA==.',
Xa='Xalatath:BAABNQAECn8cAAIBAAoKHBseGgAMAwABAAoKHBseGgAMAwAAAA==.Xanakmando:BAAANQADCggIFQAAAA==.Xandertay:BAAANQADCgMIBQAAAA==.Xanthos:BAAANQADCgIIAgAAAA==.Xantosz:BAAANQAECgEIAQABNQAFFAQIDAAOAJANAA==.',
Xi='Xianyu:BAABNQAECn8UAAMTAAYKhgK7JACrAAATAAYKhgK7JACrAAAkAAEKIAC5WQAEAAAAAA==.',
Ya='Yarian:BAAANQAECgMIAwAAAA==.',
Ym='Ymirr:BAAANQABCgcICAAAAA==.',
Yu='Yuck:BAAANQAECgIIAgABNQAFFAYIFAAJAFcjAA==.',
Za='Zachhunter:BAACNQAFFH8bAAMPAAcKoCEtDQCAAQAQAAUKHh0tCgCgAQAPAAQKdSMtDQCAAQA1AAQKfzEAAxAACgqUJDMQAOcCABAACApYJDMQAOcCAA8ACApyIeEzAFUBAAAA.Zachmage:BAAANQADCggIFgAAAA==.Zan:BAACNQAFFH8MAAMOAAQKkA2xBwDZAAAOAAQKkA2xBwDZAAAJAAMK5gkTIwCBAAA1AAQKfyoAAw4ACgqFHhcjAPsCAA4ACgqFHhcjAPsCAAkAAwomETLcALAAAAAA.',
Ze='Zeronation:BAAANQAECgMIBAAAAA==.',
Zi='Zinar:BAAANQABCggIDwAAAA==.Zinderella:BAAANQAECgQIBAABNQAECgoKKgAPAEQUAA==.',
Zu='Zultrix:BAAANQAECgMIAwABNQAECgQIBgAEAAAAAA==.',
Zy='Zylaeri:BAAANQAECggIDwAAAA==.',
['Éo']='Éowyn:BAAANQADCgEIAQAAAA==.',
['Ël']='Ëllër:BAAANQAECgYIDQAAAA==.',
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
