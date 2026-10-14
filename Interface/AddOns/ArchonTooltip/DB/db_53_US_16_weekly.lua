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

local lookup = {'Priest-Holy','Druid-Restoration','Priest-Shadow','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Hunter-Survival','Druid-Balance','DeathKnight-Frost','Warrior-Arms','Warrior-Protection','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Monk-Brewmaster','Mage-Arcane','Mage-Fire','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Preservation','Evoker-Augmentation','Rogue-Assassination','Rogue-Subtlety','Paladin-Holy','Warlock-Demonology','Warlock-Affliction','Shaman-Enhancement','Rogue-Outlaw','Monk-Mistweaver','Druid-Feral','Druid-Guardian','Evoker-Devastation','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Discipline','Mage-Frost','Monk-Windwalker',}
local provider = {region='US',realm='Arathor',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abavok:BAAANQADCgcIBwAAAA==.Absoul:BAACNQAFFH8MAAIBAAMKMg3TIADUAAABAAMKMg3TIADUAAA1AAQKfz0AAgEACQrmGWw3AIgCAAEACQrmGWw3AIgCAAAA.Abyssian:BAAANQAECgcIDAAAAA==.',
Ac='Acedia:BAABNQAECn8cAAIBAAgKShnGSQBFAgABAAgKShnGSQBFAgAAAA==.',
Ad='Adellas:BAABNQAECn8wAAICAAkKyxnBEwCqAgACAAkKyxnBEwCqAgAAAA==.Adern:BAABNQAECn82AAIDAAkKER2GDgAFAwADAAkKER2GDgAFAwAAAA==.Adon:BAAANQADCgUIBQABNQAECgUIBQAEAAAAAA==.Adonn:BAABNQAECn8rAAMFAAkKehwtTgCnAgAFAAkKehwtTgCnAgAGAAIKBgoHZgBGAAAAAA==.Adonshadriel:BAAANQAECgUIBQAAAA==.',
Ae='Aelali:BAABNQAECn8XAAIHAAkKvQhNBwAFAgAHAAkKvQhNBwAFAgAAAA==.',
Af='Afador:BAAANQADCggIDwABNQAECgUIDwAEAAAAAA==.',
Al='Aladestar:BAABNQAECn8oAAMIAAkKVRkiJQCmAgAIAAkKVRkiJQCmAgACAAYKThQXOABXAQAAAA==.Albinodh:BAAANQAECgMIBAAAAA==.Alderleise:BAAANQADCgcIBwAAAA==.Alexein:BAACNQAFFH8HAAIJAAMKlAnMEQC3AAAJAAMKlAnMEQC3AAA1AAQKfycAAgkACQrwFwYqAEYCAAkACQrwFwYqAEYCAAAA.',
Am='Amets:BAAANQAECgcIEQAAAA==.Amorae:BAAANQADCggIDwAAAA==.',
An='Anabel:BAAANQAECgEIAQAAAA==.Anamii:BAAANQAECgQIBAAAAA==.Andorsi:BAAANQAECgEIAQAAAA==.',
Ar='Arachne:BAABNQAECn8aAAIDAAcK/QqTNQBzAQADAAcK/QqTNQBzAQAAAA==.Aracianluz:BAAANQAECggICwAAAA==.Arak:BAAANQADCgIIAgAAAA==.Arce:BAAANQADCggIHgABNQAECgcIHgAJAKAVAA==.Arysia:BAAANQAECgQIBQAAAA==.Aryya:BAAANQADCgIIAgAAAA==.',
As='Ascaris:BAAANQAECgYIDwAAAA==.',
Av='Avalan:BAABNQAECn8sAAQKAAkKFxzvQQDBAgAKAAkKHxvvQQDBAgALAAYKjhtUGACmAQAMAAYKExYwEQCPAQAAAA==.Avanolatwo:BAAANQADCgYIBgABNQAECgkJKwANACsaAA==.Avashammy:BAABNQAECn8rAAMNAAkKKxq3LQCpAgANAAkKKxq3LQCpAgAOAAYKyhCikgBxAQAAAA==.Aviendah:BAAANQAECgYIEAAAAA==.',
Aw='Awsomeonet:BAAANQAECggICAAAAA==.',
Az='Azdfghop:BAACNQAFFH8NAAMPAAcKqBHiCQCgAQAPAAYKdg7iCQCgAQAQAAIKcx61HwCxAAA1AAQKfyQAAw8ACQpMI+kVAKoCAA8ACQqsIekVAKoCABAAAQryJqQ4AWoAAAAA.Azzinotica:BAAANQAECgQIBgAAAA==.',
Ba='Baalsanaro:BAAANQADCggIDQABNQAECgMIAwAEAAAAAA==.Babeshot:BAABNQAECn8rAAIQAAkKGQudcgApAgAQAAkKGQudcgApAgAAAA==.Baelgar:BAAANQAECgMIAwAAAA==.',
Bi='Bigbear:BAAANQADCggICAABNQAECgcIFgARACQRAA==.Biggy:BAAANQADCgIIAgAAAA==.Bignose:BAAANQAECgMIBgABNQAFFAQIDQASAP0mAA==.Binksy:BAAANQAECgYIBgAAAA==.',
Bl='Blaaze:BAAANQADCgYIBgAAAA==.Blackfrost:BAAANQAECggIDQAAAA==.Blaiddyd:BAABNQAECn8lAAIQAAgK8BxZQgCiAgAQAAgK8BxZQgCiAgAAAA==.Bloodboi:BAAANQADCgYIBgAAAA==.',
Br='Brandawn:BAAANQAECgMIBAAAAA==.',
Bu='Burndasheep:BAABNQAECn8pAAMTAAgK/BH2rgAjAgATAAgK/BH2rgAjAgAUAAEKew3sDAA6AAAAAA==.',
['Bæ']='Bæyy:BAAANQAECgQIDwAAAA==.',
Ca='Calyris:BAAANQADCgIIAgAAAA==.Caspias:BAEANQADCggJEgAAAA==.Caylynn:BAAANQAECgQIAgAAAA==.Caynelin:BAAANQAECgEIAQAAAA==.',
Ce='Cestbusiness:BAAANQABCgIIAgAAAA==.',
Ch='Chaoslock:BAABNQAECn8WAAIRAAcKJBGpFgC2AQARAAcKJBGpFgC2AQAAAA==.Chetter:BAAANQAECggIBgAAAA==.Chicknfajita:BAAANQAECgcICQABNQAECgkJGAAOAGgfAA==.Chickpea:BAAANQADCggIIQAAAA==.',
Co='Cocytus:BAAANQADCgcIEAAAAA==.Colbith:BAAANQAECgUIEwAAAA==.Corblixx:BAAANQAECgEIAQAAAA==.Cordaddy:BAAANQAECgEIAwABNQAECgkJJQANABslAA==.Cordelvo:BAAANQAECgUICgABNQAECgkJJQANABslAA==.Cordragu:BAABNQAECn8lAAINAAkKGyUlBACpAwANAAkKGyUlBACpAwAAAA==.Cordran:BAAANQAECgEIAgABNQAECgkJJQANABslAA==.Corinthin:BAAANQADCgQIBAAAAA==.Corraa:BAAANQADCgEIAQAAAA==.',
Cr='Crakum:BAABNQAECn8XAAIOAAYKrRTziQCHAQAOAAYKrRTziQCHAQAAAA==.Crinn:BAABNQAECn8bAAMVAAcKDg2/aQBnAQAVAAcKDg2/aQBnAQAJAAIK3AM1oABHAAAAAA==.Crizmon:BAABNQAECn8eAAIJAAkKRx+KFADlAgAJAAkKRx+KFADlAgAAAA==.',
Cu='Cucumber:BAAANQADCgcIBwAAAA==.',
Da='Damorthyx:BAABNQAECn8XAAIWAAgKYwsgVQCcAQAWAAgKYwsgVQCcAQAAAA==.Darazarke:BAACNQAFFH8cAAMXAAcKmQ5ZBQAOAgAXAAcKmQ5ZBQAOAgAYAAEKLQX8DAA9AAA1AAQKfyYAAhcACQqWF+ESAH0CABcACQqWF+ESAH0CAAAA.Darkquill:BAABNQAECn8eAAIOAAgKtg7ocQDHAQAOAAgKtg7ocQDHAQAAAA==.Daspoof:BAAANQADCgYIBgAAAA==.Dayquil:BAEANQADCgcIBwABNQAFFAEIAQAEAAAAAA==.',
De='Deadaddie:BAAANQAECgcICAABNQAECgkJIQATAKkhAA==.Deamoneyes:BAAANQAECgQIBgAAAA==.Deathkauf:BAAANQAECgEIAQAAAA==.Deathvok:BAAANQADCgMIAwAAAA==.Demolitions:BAAANQAECggICAAAAA==.Dezatra:BAAANQADCgcIBgAAAA==.',
Dh='Dhonaan:BAAANQADCgEIAQAAAA==.',
Di='Dieselcon:BAABNQAECn8zAAMGAAkKMBbEGQAiAgAGAAkKMBbEGQAiAgAFAAQK/gUERgGoAAAAAA==.Diprivan:BAABNQAECn8lAAMZAAkKuhyLEQDuAgAZAAkKuhyLEQDuAgAaAAMKnhdnPADOAAAAAA==.',
Do='Dolobrik:BAAANQABCgYIBwAAAA==.Domdog:BAABNQAECn8dAAITAAcKvgfZAgGFAQATAAcKvgfZAgGFAQAAAA==.Domína:BAAANQAECgQIBwAAAA==.Dontforget:BAAANQAECgQIBwAAAA==.Doomdealer:BAAANQAECgcIEgAAAA==.Doomed:BAABNQAECn8YAAIbAAgKPB8DJgDQAgAbAAgKPB8DJgDQAgAAAA==.Doonya:BAAANQADCgcICAAAAA==.Dottee:BAAANQAECggIAwAAAA==.Dougwalker:BAAANQADCgIIAgAAAA==.',
Dr='Dracodaddy:BAAANQADCgIIAgAAAA==.Draftymonk:BAAANQAECgYIEwAAAA==.Drage:BAABNQAECn8kAAMcAAkKrRW5QgCHAgAcAAkKrRW5QgCHAgARAAEKdgN+hAAkAAAAAA==.Drax:BAABNQAECn8fAAMdAAgKkwtVDwBWAQAcAAgKXghKoACQAQAdAAYKEwxVDwBWAQAAAA==.Dreadgar:BAAANQAECgQIBQABNQAECgkJFwAOAP8eAA==.Dritzzagain:BAAANQAECgUIDAAAAA==.Dritzzcat:BAAANQADCgYICwAAAA==.',
Dw='Dwreck:BAAANQAECgcIDgAAAA==.',
Ed='Ediann:BAAANQAECgcIDgAAAA==.',
El='Elandrus:BAAANQAECgQICAABNQAECgcIJwATAP0WAA==.Eldarine:BAAANQADCgUIBQAAAA==.',
Em='Emmara:BAABNQAECn8bAAIPAAgKnwIMSQARAQAPAAgKnwIMSQARAQAAAA==.',
En='Enitar:BAAANQADCgcICAABNQAECggIKQATAPwRAA==.',
Er='Erata:BAAANQAECgQIDAAAAA==.Erlik:BAAANQADCgMIBAAAAA==.Erzakzaktraz:BAAANQADCgYIBgABNQADCgcIBgAEAAAAAA==.',
Ev='Evullight:BAAANQADCgEJAQAAAA==.',
Ez='Ezlok:BAABNQAECn8XAAIOAAkK/x7uHwAKAwAOAAkK/x7uHwAKAwAAAA==.',
Fa='Facemash:BAAANQAECgQIBAABNQAECggIKQATAPwRAA==.Faedra:BAAANQADCggICAABNQAECggIKAABAMohAA==.Falerin:BAABNQAECn8dAAICAAkKrRcgGAB6AgACAAkKrRcgGAB6AgAAAA==.Farryn:BAAANQADCgEIAQAAAA==.',
Fe='Feenex:BAAANQAECgUICgAAAA==.Feldora:BAAANQADCgYIBgAAAA==.Festiva:BAAANQAECgEIAQAAAA==.',
Fi='Fillorey:BAAANQADCggICAABNQAECgcIJwATAP0WAA==.Firedealer:BAABNQAECn8rAAMPAAkKixGzJQAbAgAPAAkKXxGzJQAbAgAQAAQKbxKi7wAdAQAAAA==.',
Fl='Flappy:BAAANQAECgIIBAABNQAECggIKAANAK4ZAA==.Flashmaster:BAAANQAECgUIDgAAAA==.Flawlessheal:BAAANQADCgMIAwAAAA==.Fluffybutt:BAAANQADCggIFAAAAA==.',
Fo='Fossora:BAAANQADCgcIBgAAAA==.',
Fr='Freyiah:BAAANQADCgYJBgAAAA==.',
Fy='Fyatre:BAAANQAECgYIDwAAAA==.',
Ga='Galath:BAAANQAECgUJCAABNQAECgMIAwAEAAAAAA==.Gandallf:BAAANQADCgUIBQAAAA==.',
Ge='Gerree:BAAANQADCgYICgAAAA==.Gerry:BAAANQADCggIGgABNQAECggIIwAMAPUbAA==.',
Gg='Ggkando:BAAANQAECgUIEAAAAA==.',
Gh='Ghemaldir:BAAANQABCgIIAgAAAA==.',
Gi='Gildius:BAAANQADCgIIAgAAAA==.Gingerail:BAAANQAECgQIBgAAAA==.',
Gl='Glory:BAABNQAECn8bAAIWAAgK8xzFIgCeAgAWAAgK8xzFIgCeAgAAAA==.',
Gn='Gnayami:BAAANQADCgcIBwAAAA==.',
Go='Goochsquirts:BAABNQAECn8cAAINAAcK+RzwTgAlAgANAAcK+RzwTgAlAgAAAA==.Govna:BAAANQADCggIFAAAAA==.',
Gr='Grakkaem:BAAANQAECgMJBAAAAA==.Grannet:BAAANQADCgMIBQAAAA==.Gravedygger:BAABNQAECn8sAAIQAAkKhxOfSQCOAgAQAAkKhxOfSQCOAgAAAA==.Greenfear:BAAANQADCgYIBgAAAA==.Grenswood:BAAANQAECgcIDgAAAA==.Greybeeredd:BAAANQAECgEIAQAAAA==.Grimmkin:BAABNQAECn8iAAQeAAkKqBgXCwC9AgAeAAkKqBgXCwC9AgANAAIKrA9S+wBuAAAOAAEKAAA3PwEsAAAAAA==.Grind:BAAANQAECgQIBAABNQAECgUIDwAEAAAAAA==.Growl:BAAANQADCgUJBQAAAA==.Grumbo:BAAANQADCgcIBgAAAA==.',
Gu='Guuldurak:BAAANQADCgcIBgAAAA==.',
Ha='Hailcat:BAAANQAECgMIBAABNQAECgkJIQAcAP4OAA==.Handivhe:BAAANQADCgYIBgAAAA==.Hasew:BAABNQAECn8uAAIQAAgKjSAnLwDdAgAQAAgKjSAnLwDdAgAAAA==.',
He='He:BAAANQAECgQIBAABNQAECgcIHgAJAKAVAA==.Helpimßlind:BAAANQAECgcIDAAAAA==.Hera:BAACNQAFFH8HAAIQAAMKVCJeFAAZAQAQAAMKVCJeFAAZAQA1AAQKfycAAhAACQp7JgMEAMgDABAACQp7JgMEAMgDAAAA.Heyner:BAABNQAECn8tAAIfAAkKrhf2BACtAgAfAAkKrhf2BACtAgAAAA==.',
Hi='Hinral:BAACNQAFFH8GAAIgAAMKLhphBwDnAAAgAAMKLhphBwDnAAA1AAQKfyYAAiAACQpSJJICAJMDACAACQpSJJICAJMDAAAA.',
Ho='Holyluz:BAAANQAECgEJAQABNQAECggICwAEAAAAAA==.',
Hy='Hymns:BAAANQAECggIAgAAAA==.',
['Hë']='Hëll:BAABNQAECn8hAAMcAAkK/g6ucQAHAgAcAAkK/g6ucQAHAgARAAEKGRAncwA7AAAAAA==.',
Il='Illaynne:BAABNQAECn8gAAIBAAgKpA8ecwC+AQABAAgKpA8ecwC+AQAAAA==.',
Im='Imani:BAACNQAFFH8GAAIeAAMKNQJ3BQCzAAAeAAMKNQJ3BQCzAAA1AAQKfycAAh4ACQrwC9EUABcCAB4ACQrwC9EUABcCAAAA.Immensepain:BAAANQAECgQIBAAAAA==.',
In='Inoshikacho:BAABNQAECn8cAAIhAAcKygjTGwBDAQAhAAcKygjTGwBDAQAAAA==.Involio:BAAANQADCgcIDQAAAA==.',
Ir='Irishmecha:BAACNQAFFH8IAAIZAAMKWwrYEADXAAAZAAMKWwrYEADXAAA1AAQKfycAAhkACQq4Ho8VAMwCABkACQq4Ho8VAMwCAAAA.Irishpaws:BAAANQAECgEIAQAAAA==.Ironshot:BAAANQADCggIBgAAAA==.',
Is='Isaeus:BAAANQAECgEIAQAAAA==.',
It='Itharillys:BAABNQAECn8iAAIQAAgKThROcgApAgAQAAgKThROcgApAgAAAA==.',
Ja='Jaadu:BAAANQADCgQIBAAAAA==.Jangus:BAAANQAECgUIDAABNQAECgUIDwAEAAAAAA==.Jaybone:BAAANQADCgcICAAAAA==.',
Je='Jeefus:BAAANQAECggIAgAAAA==.Jeennkiins:BAAANQADCgYIBgABNQAECgMIAwAEAAAAAA==.Jenifur:BAAANQAECgIIAwABNQAECggIKAABAMohAA==.Jessibella:BAAANQADCgQIBAAAAA==.Jezzako:BAAANQAECgUICgAAAA==.',
Ji='Jinx:BAAANQADCgQIBAABNQAECggIKAABAMohAA==.',
Jo='Johali:BAAANQAECgUICgAAAA==.Jozan:BAAANQADCgcIEwAAAA==.',
Ju='Justise:BAAANQADCgIIAgABNQADCgYJCwAEAAAAAA==.',
['Jö']='Jöhnblaze:BAABNQAECn8qAAIKAAkK/Q/PfQAdAgAKAAkK/Q/PfQAdAgAAAA==.',
Ka='Kaga:BAAANQADCgEJAQABNQAECggIKQATAPwRAA==.Kailys:BAABNQAECn8nAAIGAAgKJhFSIADfAQAGAAgKJhFSIADfAQAAAA==.Kaisana:BAAANQAECgYICwAAAA==.Kaishias:BAABNQAECn8bAAIFAAcKJxpzjwABAgAFAAcKJxpzjwABAgAAAA==.Kaldrek:BAAANQAECgMIAwAAAA==.Kandoh:BAAANQADCggIEwABNQAECgUIEAAEAAAAAA==.Kankuró:BAABNQAECn8pAAIQAAkKmR46HgAdAwAQAAkKmR46HgAdAwAAAA==.Karelleira:BAAANQADCgUIBQAAAA==.Katighthole:BAAANQAECgQICQAAAA==.',
Ki='Killahmike:BAAANQAECgQIBgAAAA==.Killudead:BAAANQAECgQIBQAAAA==.Kishana:BAAANQADCgcIBgAAAA==.',
Ko='Kodetra:BAAANQAECgMICAAAAA==.Kolgrim:BAABNQAECn8aAAMJAAkKvRCsPADVAQAJAAkK8wysPADVAQAWAAYKiRKIYwBhAQAAAA==.Kong:BAAANQADCgUIBQAAAA==.Korimya:BAAANQADCggIDAAAAA==.Korvuk:BAAANQAECgUICQAAAA==.',
Kr='Krom:BAAANQAECggIEwAAAA==.Krysta:BAABNQAECn8oAAMBAAgKyiFLMQCgAgABAAgKyiFLMQCgAgADAAEKAADmfwAoAAAAAA==.',
Ky='Kynris:BAAANQADCggIEQABNQAECgcIJwATAP0WAA==.',
La='Lanaal:BAAANQADCgEIAQAAAA==.Lancewh:BAAANQADCgcIDAAAAA==.Lanciwinluna:BAAANQADCgQIBAAAAA==.Lancywinelia:BAAANQADCgQIBgAAAA==.Lauryssa:BAAANQADCggICAAAAA==.',
Ld='Ldydthstryke:BAAANQADCgcIBwABNQAECgkJKwAPAIsRAA==.',
Le='Legg:BAAANQABCgMIAwAAAA==.Legolâs:BAAANQADCgUIBQAAAA==.Leonora:BAAANQAECgcIDQAAAA==.Leviathañ:BAAANQADCgIIAgABNQAECgcIDgAEAAAAAA==.Lezene:BAAANQAECgMIAwAAAA==.',
Li='Linstriker:BAABNQAECn8mAAIiAAcKViM8CgDKAgAiAAcKViM8CgDKAgABNQAFFAUIEwANAE8jAA==.',
Lo='Lorette:BAABNQAECn8cAAMBAAgKOxq1RwBMAgABAAgKOxq1RwBMAgADAAcKtxq4HwA6AgAAAA==.',
Lu='Lucethegoose:BAAANQADCgQIBAAAAA==.Luckynyx:BAAANQAECgEIAQAAAA==.Lunate:BAAANQADCgQIBAABNQAECgkJKgADACghAA==.Lunavere:BAAANQADCgQIBgAAAA==.',
Ma='Machotedan:BAABNQAECn8uAAIFAAkKOSAAKgAdAwAFAAkKOSAAKgAdAwAAAA==.Macmittens:BAAANQADCggIFgAAAA==.Mamadrag:BAAANQAECgQIBgAAAA==.Managua:BAAANQADCgEIAQAAAA==.Mandwa:BAAANQADCggIGAABNQAECggIKQATAPwRAA==.Mangojuulpod:BAAANQADCgYIBgAAAA==.Mario:BAAANQAECgUIDwAAAA==.Mastashifta:BAAANQAECgMIAwAAAA==.Mataa:BAABNQAECn8nAAITAAcK/RYCzgDnAQATAAcK/RYCzgDnAQAAAA==.Matryoshka:BAAANQADCgUIDQABNQADCgcICAAEAAAAAA==.Maxxim:BAAANQADCgcIHAAAAA==.Mayihmpurleg:BAAANQAECgUIBQABNQAECgkJKwAPAIsRAA==.Mazeman:BAAANQADCgUIBQAAAA==.',
Me='Mellachion:BAAANQAECgUIBQABNQAECgUIDwAEAAAAAA==.Meta:BAAANQAECgcICAAAAA==.',
Mi='Mistaya:BAAANQADCgUIBQABNQAECgUIDwAEAAAAAA==.Mists:BAAANQAFFAQIBAAAAA==.Miththrawndo:BAABNQAECn8lAAIWAAkKLg5PUwClAQAWAAkKLg5PUwClAQAAAA==.',
Mo='Momjeans:BAABNQAECn8oAAITAAkKLRtQXADHAgATAAkKLRtQXADHAgAAAA==.',
Mu='Muu:BAAANQADCgYICAAAAA==.',
My='Mydaan:BAAANQADCgIIAwAAAA==.Mythunsarian:BAAANQAECgcIDAAAAA==.',
['Má']='Mákï:BAABNQAECn8aAAIKAAgKNBC2jwDwAQAKAAgKNBC2jwDwAQAAAA==.',
['Mä']='Mäylä:BAABNQAECn8dAAIIAAgKngyDSQC+AQAIAAgKngyDSQC+AQAAAA==.',
['Mí']='Míst:BAABNQAECn8uAAIFAAkKsxgWXQB9AgAFAAkKsxgWXQB9AgAAAA==.',
Na='Narlis:BAABNQAECn8qAAIVAAkK0yMWCgBrAwAVAAkK0yMWCgBrAwAAAA==.',
Ne='Nephie:BAAANQAECgYICwAAAA==.Nezqk:BAACNQAFFH8IAAQJAAMKKBWWFACVAAAVAAIKlxGfFwCaAAAJAAIKExWWFACVAAAWAAEKAAB6PAAZAAA1AAQKfycABBUACQpuHIkyAF8CABUACQpuHIkyAF8CABYACAqQEjJOALoBAAkABAqWFa5pAO8AAAAA.Nezquick:BAAANQAECgIIAgAAAA==.',
Ni='Niano:BAAANQABCgIIAgAAAA==.',
Nm='Nmnenthe:BAABNQAECn8cAAIjAAcKsRaWFAABAgAjAAcKsRaWFAABAgAAAA==.',
No='Notrealword:BAAANQAECgMIAwABNQAECggILgAQAI0gAA==.Noxluminous:BAAANQABCgIIAgAAAA==.',
Ob='Obin:BAABNQAECn8aAAMMAAYKlw93GgD6AAAKAAYKgg4X0gBIAQAMAAUKlg13GgD6AAAAAA==.',
Oc='Occasionally:BAAANQAECgIIAgAAAA==.',
Om='Ominious:BAABNQAECn8nAAMeAAkKBhXoEwAnAgAeAAgKMxPoEwAnAgAOAAUKtRf3pwBAAQABNQABCgEIAQAEAAAAAA==.Omnissia:BAAANQAECgUIAwABNQABCgEIAQAEAAAAAA==.Omnius:BAABNQAECn8VAAMOAAgKqRYLXwABAgAOAAgKqRYLXwABAgANAAEKMAtlJgEkAAAAAA==.Omnya:BAAANQAECgcIDQABNQABCgEIAQAEAAAAAA==.',
Ow='Owendriel:BAAANQAFFAIIBAAAAA==.',
Pa='Paindya:BAAANQAECgQIBAAAAA==.Paleigh:BAAANQABCgYICwAAAA==.Palivok:BAAANQADCgEIAQAAAA==.Pandress:BAAANQAECgUIEQAAAA==.Pankake:BAAANQAECgQIBAABNQAECgkJKQAkAHkhAA==.Paralysis:BAACNQAFFH8HAAIlAAMKvQ8dDQDYAAAlAAMKvQ8dDQDYAAA1AAQKfyYAAiUACQqHF8odAGACACUACQqHF8odAGACAAAA.',
Pe='Peetza:BAAANQADCgYIBgABNQAECgkJKQAkAHkhAA==.Peryite:BAABNQAECn8sAAMBAAkK5xaVOwB4AgABAAkK3xaVOwB4AgAmAAQK6xAzFQDUAAAAAA==.',
Ph='Phaedrana:BAAANQAECgUICAAAAA==.',
Pi='Pisscat:BAAANQAECgIIBQAAAA==.',
Po='Pocketdragon:BAABNQAECn8pAAMjAAkKYRYGDwBpAgAjAAkKShUGDwBpAgAYAAYKWhAhEAA1AQAAAA==.',
Pr='Prideindeath:BAAANQADCgUIBQAAAA==.Promiscuity:BAAANQAECgcIEwAAAA==.Prængle:BAAANQADCgYIAwAAAA==.',
Ps='Psoas:BAABNQAECn8qAAMDAAkKKCH8BwBaAwADAAkKKCH8BwBaAwABAAIK4BAY4QB7AAAAAA==.Psypriest:BAEBNQAECn8lAAIBAAgKyRlsOgB8AgABAAgKyRlsOgB8AgABNQAFFAcIHwABAL4PAA==.',
Py='Pyroheal:BAAANQAECgUICAAAAA==.',
Qu='Quaichang:BAAANQADCgYIBgAAAA==.',
Ra='Rabbi:BAABNQAECn8pAAIDAAgK7x6nEgDUAgADAAgK7x6nEgDUAgAAAA==.Rahfna:BAAANQADCgcIDwAAAA==.Railænu:BAAANQADCggIDgAAAA==.Rainmist:BAAANQADCgYIBgAAAA==.Ranric:BAAANQAECgMIAwAAAA==.',
Re='Reesespbc:BAAANQAECgYIDQAAAA==.Reina:BAAANQAECgUICQABNQAECggIKAABAMohAA==.Reinz:BAAANQAECgYIBgAAAA==.Rektagar:BAABNQAECn8oAAIOAAkKmySoBQC8AwAOAAkKmySoBQC8AwABNQAFFAcIGgAQAKAhAA==.Ressandra:BAAANQADCgMIBgAAAA==.Rezo:BAAANQAECgEIAgAAAA==.',
Ri='Riverarose:BAAANQADCggIFQAAAA==.',
Ro='Roar:BAAANQAECgQIBwABNQAECgUIDwAEAAAAAA==.',
Ry='Rysi:BAAANQADCgQIBAAAAA==.',
['Rò']='Ròs:BAACNQAFFH8IAAIGAAMKmhnrBwDkAAAGAAMKmhnrBwDkAAA1AAQKfycAAgYACQqmICQKAPcCAAYACQqmICQKAPcCAAAA.',
['Rö']='Rös:BAAANQADCgEIAQABNQAFFAMICAAGAJoZAA==.',
Sa='Saberie:BAAANQADCggIFwABNQADCgMIBgAEAAAAAA==.Salaria:BAABNQAECn8fAAIlAAcKtw9XMwCjAQAlAAcKtw9XMwCjAQAAAA==.Salina:BAEANQAECgYIDwAAAA==.Sandstique:BAABNQAECn8pAAINAAgKqyTREgAxAwANAAgKqyTREgAxAwAAAA==.Sandweaver:BAAANQADCgcIBwAAAA==.Sanjira:BAAANQADCgYIBgAAAA==.Sarlak:BAABNQAECn8oAAMQAAkKER0+JAAEAwAQAAkKER0+JAAEAwAPAAEK8Ab9lAAqAAAAAA==.Sarusuby:BAABNQAECn8wAAIiAAkKKhERGADpAQAiAAkKKhERGADpAQAAAA==.Satae:BAABNQAECn8pAAIkAAkKeSF3AgBZAwAkAAkKeSF3AgBZAwAAAA==.',
Sc='Schufft:BAABNQAECn8ZAAIRAAcKzBtyCAB1AgARAAcKzBtyCAB1AgAAAA==.Scottydh:BAAANQAECgIIAgABNQAECgkJLQAWAJwgAA==.Scottymac:BAABNQAECn8tAAIWAAkKnCANDwA1AwAWAAkKnCANDwA1AwAAAA==.Scottypal:BAAANQAECgEIAQABNQAECgkJLQAWAJwgAA==.',
Se='Seatah:BAAANQAECgMIAwAAAA==.Seba:BAAANQAECgcIDgAAAA==.Seetah:BAABNQAECn8aAAMBAAgKMhUsWAAWAgABAAgKMhUsWAAWAgADAAIK6wxKZgBiAAAAAA==.Sermon:BAAANQADCgQIBAABNQAECgUIDwAEAAAAAA==.',
Sh='Shadaddy:BAABNQAECn8hAAMTAAkKqSFQUQDeAgATAAgK8SBQUQDeAgAnAAMKNyCbHgDyAAAAAA==.Shadowheart:BAAANQAECgEIAQAAAA==.Shakasana:BAAANQADCggIDwAAAA==.Shal:BAABNQAECn8aAAIKAAcKsxgceQAoAgAKAAcKsxgceQAoAgAAAA==.Shamanluz:BAAANQADCgIIAgABNQAECggICwAEAAAAAA==.Shamommy:BAAANQADCgUIBAAAAA==.Shamtaz:BAAANQAECgUIBwAAAA==.Shimmerstar:BAABNQAECn8cAAIFAAkKYR2RbwBNAgAFAAkKYR2RbwBNAgAAAA==.Shroomgirl:BAAANQAECgUIBQAAAA==.Shrubhub:BAAANQAECgEIAQABNQAECggIGAAbADwfAA==.',
Si='Silexe:BAAANQAECgYIEgAAAA==.Sitga:BAAANQADCgIIAgAAAA==.',
Sl='Slinga:BAAANQADCgcIBwAAAA==.Slipperyboi:BAAANQAECgQICQAAAA==.Slÿ:BAAANQAECgIIAgAAAA==.',
So='Solarion:BAAANQAECgYIDwABNQAECgkJFwAOAP8eAA==.Soldraca:BAAANQAECgIIAgAAAA==.',
St='Stats:BAAANQAECgUIDwAAAA==.Stinkbug:BAAANQADCgQIBAAAAA==.Stutters:BAABNQAECn8oAAIWAAkKoB2uFgD2AgAWAAkKoB2uFgD2AgAAAA==.',
Su='Subayyru:BAAANQADCgEIAQABNQAECgQIDwAEAAAAAA==.Sudachi:BAAANQADCgYIBgABNQAFFAYKEgAoAFscAA==.Sunnyräy:BAAANQAECgMIAwAAAA==.Superiorkill:BAAANQADCgcIBwAAAA==.Suthrheimr:BAABNQAECn8jAAIMAAgK9Ru+BgCWAgAMAAgK9Ru+BgCWAgAAAA==.',
Sy='Symphany:BAAANQABCggIDAAAAA==.',
['Sý']='Sýndrá:BAAANQAECgYIDQAAAA==.',
Ta='Takafune:BAAANQADCgQIBgAAAA==.Talespin:BAAANQAECgQIBAAAAA==.Talysiah:BAAANQAECgUIDwAAAA==.Tavok:BAABNQAECn8dAAIMAAgKNh1JBgCnAgAMAAgKNh1JBgCnAgAAAA==.Tazbis:BAAANQAECgIIAgAAAA==.',
Te='Teishuku:BAABNQAECn8wAAIFAAkKQRKlggAeAgAFAAkKQRKlggAeAgAAAA==.Teusday:BAABNQAECn8eAAIJAAcKoBW8NwDyAQAJAAcKoBW8NwDyAQAAAA==.',
Th='Thiux:BAABNQAECn8gAAMcAAcKeyDWZAAoAgAcAAYKkB7WZAAoAgARAAIKYB8BRAC0AAAAAA==.Thoeleden:BAAANQAECgMIBgABNQAFFAUIEwANAE8jAA==.Thotsnprayrs:BAAANQAECgMIBgABNQAECggIGAAbADwfAA==.Thrappy:BAABNQAECn8oAAMNAAgKrhlCRQBJAgANAAgKrhlCRQBJAgAOAAUKERU2oABSAQAAAA==.Thryna:BAAANQADCgEIAQAAAA==.',
Ti='Tinsoon:BAAANQAECgQIBAAAAA==.Tintaglia:BAABNQAECn8qAAMcAAkKQRgoQQCLAgAcAAkKQRgoQQCLAgAdAAEKZBFaMQAxAAABNQAECgUIDwAEAAAAAA==.Tirtun:BAABNQAECn8tAAInAAkKWyAtAgBRAwAnAAkKWyAtAgBRAwAAAA==.',
Tr='Triggeer:BAABNQAECn8dAAILAAgKMRkIDwA3AgALAAgKMRkIDwA3AgAAAA==.Trolldemort:BAAANQADCgYIBgABNQAECggIGwAcAA0XAA==.',
Tu='Tully:BAAANQAECgUIEAAAAA==.Tunkhan:BAAANQADCgQIBwAAAA==.',
Tw='Twelvekill:BAACNQAFFH8IAAIQAAMKjhLaGQDoAAAQAAMKjhLaGQDoAAA1AAQKfycAAhAACQqpIQQnAPoCABAACQqpIQQnAPoCAAAA.',
Ty='Tyliaa:BAABNQAECn8lAAMNAAkKUxrNLgCkAgANAAkKUxrNLgCkAgAOAAIKqBI+CAF0AAABNQAECgQIBgAEAAAAAA==.',
Ul='Ultramon:BAABNQAECn8aAAIFAAgKCBVSgQAhAgAFAAgKCBVSgQAhAgAAAA==.',
Un='Unbreakabull:BAAANQAECgEIAQAAAA==.Unwell:BAABNQAECn8bAAIlAAgK0RkAHQBpAgAlAAgK0RkAHQBpAgAAAA==.',
Ur='Urgoochness:BAAANQADCgQIBAAAAA==.Urikhai:BAAANQADCggIAgAAAA==.',
Va='Vainglorious:BAAANQADCggIEwABNQAECggIGwAWAPMcAA==.Valanora:BAABNQAECn8oAAIdAAgKZRVBBwApAgAdAAgKZRVBBwApAgAAAA==.Valerie:BAAANQAECgIIAgABNQAECgkJKAAPAGgcAA==.Valinaxius:BAAANQAECgMIAwAAAA==.Vapturov:BAAANQAECgMIAwAAAA==.',
Ve='Veeks:BAABNQAECn8oAAIOAAkKIAuKdQC8AQAOAAkKIAuKdQC8AQAAAA==.Velibast:BAAANQAECgQIBAAAAA==.Velikirn:BAABNQAECn8WAAMoAAkK9BoFGgBtAgAoAAgKgRkFGgBtAgASAAgKWRUkDwD8AQAAAA==.Velimald:BAAANQAECgQIBAAAAA==.Velydia:BAAANQAECgYIBgAAAA==.Venefica:BAAANQAECgEIAwAAAA==.Verdracee:BAAANQABCgMIAwABNQAECgQICAAEAAAAAA==.Versø:BAABNQAECn8ZAAMZAAcKnRVHPQDVAQAZAAcKnRVHPQDVAQAaAAEKAADLUQA1AAAAAA==.Veryzi:BAAANQAECgEIAgAAAA==.',
Vi='Vine:BAAANQADCgIIAgAAAA==.',
Vl='Vlyrae:BAAANQADCgMIAwABNQABCgEIAQAEAAAAAA==.',
Vo='Voidbreaker:BAAANQADCgcIBwAAAA==.Voidhearted:BAABNQAECn87AAIDAAkKIBHvIgAYAgADAAkKIBHvIgAYAgAAAA==.Vonzuo:BAAANQAECgIIAgAAAA==.',
Vu='Vukodlak:BAAANQADCgcIDQABNQAECgUIDwAEAAAAAA==.',
['Vì']='Vìolet:BAAANQADCgMIAwABNQAECggIJQAIAHYfAA==.',
Wa='Warriorwuu:BAAANQABCgIIAgAAAA==.Wayshua:BAAANQADCgYIBgAAAA==.',
We='Werkajerk:BAAANQADCggICAABNQAFFAUIEwANAE8jAA==.Werkjathal:BAACNQAFFH8TAAINAAUKTyM8BgD8AQANAAUKTyM8BgD8AQA1AAQKfyUAAg0ACQqvJi8BANcDAA0ACQqvJi8BANcDAAAA.',
Wi='Wibbles:BAAANQADCgcICwAAAA==.Wigarthan:BAAANQADCgEIAQAAAA==.Wildsenpai:BAAANQADCgEIAQAAAA==.',
Wo='Wolfblitzer:BAABNQAECn8gAAIFAAgK2xfQjwAAAgAFAAgK2xfQjwAAAgAAAA==.Worgenator:BAAANQADCgMIAwAAAA==.Worldbane:BAABNQAECn8gAAIRAAgKEA1NEQDtAQARAAgKEA1NEQDtAQAAAA==.',
Wr='Wraithlash:BAAANQAECggIDgAAAA==.',
Wt='Wtyczka:BAAANQABCgYIBwAAAA==.',
Wu='Wuulock:BAAANQABCgEJAQAAAA==.',
Wy='Wynnhrt:BAAANQADCggICAAAAA==.',
Xa='Xalatath:BAABNQAECn8WAAIBAAkKTBypGQAMAwABAAkKTBypGQAMAwAAAA==.Xanakmando:BAAANQADCggIFQAAAA==.Xandertay:BAAANQADCgMIAwAAAA==.Xanthos:BAAANQADCgIIAgAAAA==.Xantosz:BAAANQAECgEIAQABNQAFFAMICAAOAOsMAA==.',
Xi='Xianyu:BAAANQAECgUIDAAAAA==.',
Ya='Yarian:BAAANQAECgMIAwAAAA==.',
Ym='Ymirr:BAAANQABCgcICAAAAA==.',
Yu='Yuck:BAAANQAECgIIAgABNQAFFAUIEwANAE8jAA==.',
Za='Zachhunter:BAACNQAFFH8aAAMQAAcKoCGuDACBAQAPAAUKHh3eCQCgAQAQAAQKdSOuDACBAQA1AAQKfy0AAw8ACQq0JPUPAOgCAA8ACAoIJPUPAOgCABAABwpeIVFvADACAAAA.Zachmage:BAAANQADCggIFgAAAA==.Zan:BAACNQAFFH8IAAMOAAMK6wz0GwDcAAAOAAMK6wz0GwDcAAANAAIK8A1PIgCBAAA1AAQKfycAAw4ACQqXHrAiAPsCAA4ACQqXHrAiAPsCAA0AAwolEa7ZALAAAAAA.',
Ze='Zeronation:BAAANQAECgMIBAAAAA==.',
Zi='Zinar:BAAANQABCggIDgAAAA==.Zinderella:BAAANQADCggIDgAAAA==.',
Zu='Zultrix:BAAANQAECgMIAwAAAA==.',
Zy='Zylaeri:BAAANQAECgcIDgAAAA==.',
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
