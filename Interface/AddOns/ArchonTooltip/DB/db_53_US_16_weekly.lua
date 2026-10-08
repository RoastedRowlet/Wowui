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

local lookup = {'Priest-Holy','Druid-Restoration','Priest-Shadow','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Druid-Balance','DeathKnight-Frost','Warrior-Arms','Warrior-Protection','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Monk-Brewmaster','Mage-Arcane','Mage-Fire','DeathKnight-Unholy','Evoker-Preservation','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Warlock-Affliction','Shaman-Enhancement','Rogue-Outlaw','Monk-Mistweaver','Druid-Feral','Druid-Guardian','DeathKnight-Blood','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Discipline','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Monk-Windwalker',}
local provider = {region='US',realm='Arathor',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abavok:BAAANQADCgcIBwAAAA==.Absoul:BAACNQAFFIEGAAIBAAIK0hLqIACiAAABAAIK0hLqIACiAAA1AAQKgTYAAgEACQqlGSwtAJQCAAEACQqlGSwtAJQCAAAA.Abyssian:BAAANQAECgcIDAAAAA==.',
Ac='Acedia:BAAANQAECgYIDwAAAA==.',
Ad='Adellas:BAABNQAECoEnAAICAAkKyBcLFACJAgACAAkKyBcLFACJAgAAAA==.Adern:BAABNQAECoEtAAIDAAkKzBy+DQD6AgADAAkKzBy+DQD6AgAAAA==.Adon:BAAANQADCgUIBQABNQADCgYJBgAEAAAAAA==.Adonn:BAABNQAECoEnAAMFAAkKEhwlPgC2AgAFAAkKEhwlPgC2AgAGAAIKlQv6WgBIAAAAAA==.Adonshadriel:BAAANQADCgYJBgAAAA==.',
Ae='Aelali:BAAANQAECgcIDwAAAA==.',
Af='Afador:BAAANQADCggJCAABNQAECgUICwAEAAAAAA==.',
Al='Aladestar:BAABNQAECoEiAAMHAAkKxBh2JQCGAgAHAAkKxBh2JQCGAgACAAYKThTWMABfAQAAAA==.Albinodh:BAAANQAECgMIBAAAAA==.Alderleise:BAAANQADCgcIBwAAAA==.Alexein:BAACNQAFFIEFAAIIAAIKHQgtEwB+AAAIAAIKHQgtEwB+AAA1AAQKgSUAAggACQp5FpQjAEcCAAgACQp5FpQjAEcCAAAA.',
Am='Amets:BAAANQAECgcIEQAAAA==.Amorae:BAAANQADCggIDwAAAA==.',
An='Anabel:BAAANQAECgEIAQAAAA==.Anamii:BAAANQAECgQIBAAAAA==.Andorsi:BAAANQAECgEIAQAAAA==.',
Ar='Arachne:BAAANQAECgYIEwAAAA==.Aracianluz:BAAANQAECgQIBAAAAA==.Arak:BAAANQADCgIIAgAAAA==.Arce:BAAANQADCggIFwABNQAECgcIGgAIANcXAA==.Arysia:BAAANQAECgQIBQAAAA==.Aryya:BAAANQADCgIIAgAAAA==.',
As='Ascaris:BAAANQAECgUIDgAAAA==.',
Av='Avalan:BAABNQAECoEkAAQJAAgKZR2SUQB6AgAJAAgKjxuSUQB6AgAKAAYKLhxGFAC1AQALAAYKIRiQDgChAQAAAA==.Avanolatwo:BAAANQADCgYIBgABNQAECgkJJwAMANIUAA==.Avashammy:BAABNQAECoEnAAMMAAkK0hTxPwA2AgAMAAkK0hTxPwA2AgANAAYKcxGnfwB1AQAAAA==.Aviendah:BAAANQAECgYICgAAAA==.',
Aw='Awsomeonet:BAAANQAECggICAAAAA==.',
Az='Azdfghop:BAACNQAFFIENAAMOAAcKixJCBwCxAQAOAAYKLw9CBwCxAQAPAAIK6BwkGgCyAAA1AAQKgSQAAw4ACQokIAASAMECAA4ACQrhHgASAMECAA8AAQryJv0cAW0AAAAA.Azzinotica:BAAANQAECgIIAgAAAA==.',
Ba='Baalsanaro:BAAANQADCggIDQABNQAECgMIAwAEAAAAAA==.Babeshot:BAABNQAECoEjAAIPAAgKugybcwD7AQAPAAgKugybcwD7AQAAAA==.Baelgar:BAAANQAECgMIAwAAAA==.',
Bi='Bigbear:BAAANQADCggICAABNQAECgcIFgAQAH0TAA==.Biggy:BAAANQADCgIIAgAAAA==.Bignose:BAAANQAECgMIAwABNQAFFAQICQARAFkmAA==.Binksy:BAAANQAECgYIBgAAAA==.',
Bl='Blaaze:BAAANQADCgYIBgAAAA==.Blackfrost:BAAANQAECggICgAAAA==.Blaiddyd:BAABNQAECoEeAAIPAAcKeR94SwBkAgAPAAcKeR94SwBkAgAAAA==.Bloodboi:BAAANQADCgYIBgAAAA==.',
Br='Brandawn:BAAANQAECgEIAQAAAA==.',
Bu='Burndasheep:BAABNQAECoEiAAMSAAgK6hKznQAnAgASAAgK6hKznQAnAgATAAEKew1jCwA6AAAAAA==.',
['Bæ']='Bæyy:BAAANQAECgQICwAAAA==.',
Ca='Calyris:BAAANQADCgIIAgAAAA==.Caspias:BAEANQADCggJEgAAAA==.Caynelin:BAAANQAECgEIAQAAAA==.',
Ch='Chaoslock:BAABNQAECoEWAAIQAAcKfRNuFQC6AQAQAAcKfRNuFQC6AQAAAA==.Chetter:BAAANQAECggIBgAAAA==.Chicknfajita:BAAANQAECgcICQAAAA==.Chickpea:BAAANQADCggIGwAAAA==.',
Co='Cocytus:BAAANQADCgYIDwAAAA==.Colbith:BAAANQAECgUIDgAAAA==.Corblixx:BAAANQAECgEIAQAAAA==.Cordaddy:BAAANQAECgEIAgABNQAECggIHgAMAFElAA==.Cordelvo:BAAANQAECgUICQABNQAECggIHgAMAFElAA==.Cordragu:BAABNQAECoEeAAIMAAgKUSXLDABGAwAMAAgKUSXLDABGAwAAAA==.Cordran:BAAANQAECgEIAgABNQAECggIHgAMAFElAA==.Corraa:BAAANQADCgEIAQAAAA==.',
Cr='Crakum:BAABNQAECoEXAAINAAYKfRRwdwCLAQANAAYKfRRwdwCLAQAAAA==.Crinn:BAABNQAECoEbAAMUAAcKjA0dYABpAQAUAAcKjA0dYABpAQAIAAIKrgVkigBIAAAAAA==.Crizmon:BAABNQAECoEbAAIIAAgKjyFEFADJAgAIAAgKjyFEFADJAgAAAA==.',
Da='Damorthyx:BAAANQAECgYIEgAAAA==.Darazarke:BAACNQAFFIEWAAIVAAYKBBBnBgDJAQAVAAYKBBBnBgDJAQA1AAQKgSMAAhUACQqIFwMRAIUCABUACQqIFwMRAIUCAAAA.Darkquill:BAABNQAECoEeAAINAAgKEw/GYQDMAQANAAgKEw/GYQDMAQAAAA==.Daspoof:BAAANQADCgYIBgAAAA==.Dayquil:BAEANQADCgcIBwAAAA==.',
De='Deadaddie:BAAANQAECgQIBAABNQAECgkJHQASAP8gAA==.Deamoneyes:BAAANQAECgQIBgAAAA==.Deathkauf:BAAANQAECgEIAQAAAA==.Deathvok:BAAANQADCgMIAwAAAA==.Demolitions:BAAANQAECggICAAAAA==.Dezatra:BAAANQADCgcIBgAAAA==.',
Dh='Dhonaan:BAAANQADCgEIAQAAAA==.',
Di='Dieselcon:BAABNQAECoEpAAIGAAgKFRVQGgD0AQAGAAgKFRVQGgD0AQAAAA==.Diprivan:BAABNQAECoEeAAMWAAgKaBzBGACOAgAWAAgKaBzBGACOAgAXAAMK2hRwOADRAAAAAA==.',
Do='Dolobrik:BAAANQABCgYIBwAAAA==.Domdog:BAABNQAECoEdAAISAAcKXgkd6ACTAQASAAcKXgkd6ACTAQAAAA==.Domína:BAAANQAECgQIBwAAAA==.Dontforget:BAAANQAECgMIBAAAAA==.Doomdealer:BAAANQAECgcIDAAAAA==.Doomed:BAAANQAECgUIEwAAAA==.Doonya:BAAANQADCgMIAwABNQADCgUIDQAEAAAAAA==.Dottee:BAAANQAECggIAwAAAA==.Dougwalker:BAAANQADCgIIAgAAAA==.',
Dr='Dracodaddy:BAAANQADCgIIAgAAAA==.Draftymonk:BAAANQAECgUIDQABNQAECgYIDgAEAAAAAA==.Drage:BAABNQAECoEfAAMYAAgKwRg5TgBKAgAYAAgKwRg5TgBKAgAQAAEKdgP3fQAmAAAAAA==.Drax:BAABNQAECoEdAAMZAAgKBgtgDQBbAQAYAAgKlQchjgCUAQAZAAYKbgxgDQBbAQAAAA==.Dreadgar:BAAANQAECgQIBQABNQAECgYIEgAEAAAAAA==.Dritzzagain:BAAANQAECgUIBwAAAA==.Dritzzcat:BAAANQADCgYIBgAAAA==.',
Dw='Dwreck:BAAANQAECgUICgAAAA==.',
Ed='Ediann:BAAANQAECgYIBwAAAA==.',
El='Elandrus:BAAANQAECgQIBgABNQAECgcIIwASAMsWAA==.Eldarine:BAAANQADCgUIBQAAAA==.',
Em='Emmara:BAAANQAECgYIEgAAAA==.',
En='Enitar:BAAANQADCgcICAABNQAECggIIgASAOoSAA==.',
Er='Erata:BAAANQAECgQICQAAAA==.Erlik:BAAANQADCgMIBAAAAA==.Erzakzaktraz:BAAANQADCgYIBgABNQADCgcIBgAEAAAAAA==.',
Ev='Evullight:BAAANQADCgEJAQAAAA==.',
Ez='Ezlok:BAAANQAECgYIEgAAAA==.',
Fa='Faedra:BAAANQADCggICAABNQAECggIIQABAMohAA==.Falerin:BAABNQAECoEZAAICAAkKNRf2EwCKAgACAAkKNRf2EwCKAgAAAA==.Farryn:BAAANQADCgEIAQAAAA==.',
Fe='Feenex:BAAANQAECgQICQAAAA==.Festiva:BAAANQAECgEIAQAAAA==.',
Fi='Fillorey:BAAANQADCggICAABNQAECgcIIwASAMsWAA==.Firedealer:BAABNQAECoEnAAMOAAkKKBH+IgAVAgAOAAkK6A/+IgAVAgAPAAQKAhV31QAjAQAAAA==.',
Fl='Flappy:BAAANQAECgIIBAABNQAECggIIQAMADoVAA==.Flashmaster:BAAANQAECgUICQAAAA==.Flawlessheal:BAAANQADCgMIAwAAAA==.Fluffybutt:BAAANQADCggIFAAAAA==.',
Fo='Fossora:BAAANQADCgcIBgAAAA==.',
Fr='Freyiah:BAAANQADCgYJBgAAAA==.',
Fy='Fyatre:BAAANQAECgYICQAAAA==.',
Ga='Galath:BAAANQAECgUJCAABNQAECgMIAwAEAAAAAA==.',
Ge='Gerree:BAAANQADCgYICgAAAA==.Gerry:BAAANQADCggIFAABNQAECggIHAALALYbAA==.',
Gg='Ggkando:BAAANQAECgQICwAAAA==.',
Gh='Ghemaldir:BAAANQABCgIIAgAAAA==.',
Gi='Gildius:BAAANQADCgIIAgAAAA==.Gingerail:BAAANQAECgQIBQAAAA==.',
Gl='Glory:BAAANQAECgcIEwAAAA==.',
Go='Goochsquirts:BAABNQAECoEcAAIMAAcK+Rx4QQAwAgAMAAcK+Rx4QQAwAgAAAA==.Govna:BAAANQADCggIFAAAAA==.',
Gr='Grakkaem:BAAANQAECgMJBAAAAA==.Grannet:BAAANQADCgMIBQAAAA==.Gravedygger:BAABNQAECoEjAAIPAAgK5BRCVwBEAgAPAAgK5BRCVwBEAgAAAA==.Greenfear:BAAANQADCgYIBgAAAA==.Grenswood:BAAANQAECgcIDgAAAA==.Grimmkin:BAABNQAECoEeAAQaAAkKpxZ3CwCjAgAaAAkKpxZ3CwCjAgAMAAIKrA9T5wBsAAANAAEKbQrbIQEsAAAAAA==.Grind:BAAANQADCgYJBwABNQAECgUICwAEAAAAAA==.Growl:BAAANQADCgUJBQAAAA==.Grumbo:BAAANQADCgcIBgAAAA==.',
Gu='Guuldurak:BAAANQADCgcIBgAAAA==.',
Ha='Hailcat:BAAANQAECgMIBAABNQAECgkJGwAYADsNAA==.Handivhe:BAAANQADCgYIBgAAAA==.Hasew:BAABNQAECoElAAIPAAgKAh8aKQDUAgAPAAgKAh8aKQDUAgAAAA==.',
He='He:BAAANQADCggIHwABNQAECgcIGgAIANcXAA==.Helpimßlind:BAAANQAECgYICwAAAA==.Hera:BAACNQAFFIEEAAIPAAIK3hvcGgCvAAAPAAIK3hvcGgCvAAA1AAQKgSUAAg8ACQqQJmMCANgDAA8ACQqQJmMCANgDAAAA.Heyner:BAABNQAECoElAAIbAAgKuBf6BQBlAgAbAAgKuBf6BQBlAgAAAA==.',
Hi='Hinral:BAABNQAECoEhAAIcAAkK0iLrAwBZAwAcAAkK0iLrAwBZAwAAAA==.',
Ho='Holyluz:BAAANQAECgEJAQABNQAECgQIBAAEAAAAAA==.',
Hy='Hymns:BAAANQAECggIAgAAAA==.',
['Hë']='Hëll:BAABNQAECoEbAAMYAAkKOw1FegDKAQAYAAgK3wxFegDKAQAQAAEKGRAsbQA9AAAAAA==.',
Il='Illaynne:BAABNQAECoEZAAIBAAcK5QzvfgBiAQABAAcK5QzvfgBiAQAAAA==.',
Im='Imani:BAABNQAECoElAAIaAAkKrwy2EABBAgAaAAkKrwy2EABBAgAAAA==.Immensepain:BAAANQAECgQIBAAAAA==.',
In='Inoshikacho:BAABNQAECoEcAAIdAAcKswg6FwBOAQAdAAcKswg6FwBOAQAAAA==.Involio:BAAANQADCgcIBwAAAA==.',
Ir='Irishmecha:BAACNQAFFIEFAAIWAAIK3wUaEwCOAAAWAAIK3wUaEwCOAAA1AAQKgSUAAhYACQqrHYURANECABYACQqrHYURANECAAAA.Irishpaws:BAAANQAECgEIAQAAAA==.Ironshot:BAAANQADCggIBgAAAA==.',
Is='Isaeus:BAAANQAECgEIAQAAAA==.',
It='Itharillys:BAABNQAECoEgAAIPAAgKvBFcZgAdAgAPAAgKvBFcZgAdAgAAAA==.',
Ja='Jaadu:BAAANQADCgQIBAAAAA==.Jangus:BAAANQAECgUICwAAAA==.Jaybone:BAAANQADCgMIAwAAAA==.',
Je='Jeefus:BAAANQAECgYIAgAAAA==.Jeennkiins:BAAANQADCgYIBgABNQAECgMIAwAEAAAAAA==.Jenifur:BAAANQAECgIIAwABNQAECggIIQABAMohAA==.Jessibella:BAAANQADCgQIBAAAAA==.Jezzako:BAAANQAECgUIBQAAAA==.',
Ji='Jinx:BAAANQADCgQIBAABNQAECggIIQABAMohAA==.',
Jo='Johali:BAAANQAECgQIBQAAAA==.Jozan:BAAANQADCgYIDAAAAA==.',
Ju='Justise:BAAANQADCgIIAgABNQADCgYJCwAEAAAAAA==.',
['Jö']='Jöhnblaze:BAABNQAECoEhAAIJAAkKMg1qfQD+AQAJAAkKMg1qfQD+AQAAAA==.',
Ka='Kaga:BAAANQADCgEJAQABNQAECggIIgASAOoSAA==.Kailys:BAABNQAECoElAAIGAAgKshOqGwDmAQAGAAgKshOqGwDmAQAAAA==.Kaisana:BAAANQAECgYICwAAAA==.Kaishias:BAABNQAECoEUAAIFAAcKhRd/fwD5AQAFAAcKhRd/fwD5AQAAAA==.Kaldrek:BAAANQAECgMIAwAAAA==.Kandoh:BAAANQADCggIEwABNQAECgQICwAEAAAAAA==.Kankuró:BAABNQAECoEgAAIPAAkKLx02JADoAgAPAAkKLx02JADoAgAAAA==.Karelleira:BAAANQADCgUIBQAAAA==.Katighthole:BAAANQAECgQICQAAAA==.',
Ki='Killahmike:BAAANQAECgQIBgAAAA==.Killudead:BAAANQAECgQIBQAAAA==.Kishana:BAAANQADCgcIBgAAAA==.',
Ko='Kodetra:BAAANQAECgMIBgAAAA==.Kolgrim:BAAANQAECgcIEAAAAA==.Kong:BAAANQADCgUIBQAAAA==.Korimya:BAAANQADCggIBwAAAA==.Korvuk:BAAANQAECgQIBAAAAA==.',
Kr='Krom:BAAANQAECggIEQAAAA==.Krysta:BAABNQAECoEhAAMBAAgKyiHUJwCsAgABAAgKyiHUJwCsAgADAAEKOA0UcwApAAAAAA==.',
Ky='Kynris:BAAANQADCggIEQABNQAECgcIIwASAMsWAA==.',
La='Lanaal:BAAANQADCgEIAQAAAA==.Lancewh:BAAANQADCgcIDAAAAA==.Lanciwinluna:BAAANQADCgQIBAAAAA==.Lancywinelia:BAAANQADCgQIBgAAAA==.Lauryssa:BAAANQADCggICAAAAA==.',
Le='Legg:BAAANQABCgMIAwAAAA==.Legolâs:BAAANQADCgUIBQAAAA==.Leonora:BAAANQAECgYIBgAAAA==.Leviathañ:BAAANQADCgIIAgABNQAECgUICgAEAAAAAA==.Lezene:BAAANQADCggIFQAAAA==.',
Li='Linstriker:BAABNQAECoEfAAIeAAcKACPtBwDOAgAeAAcKACPtBwDOAgABNQAFFAUIDwAMAIgiAA==.',
Lo='Lorette:BAABNQAECoEcAAMBAAgKOxrkOwBWAgABAAgKOxrkOwBWAgADAAcKIRscGwBMAgAAAA==.',
Lu='Lucethegoose:BAAANQADCgQIBAAAAA==.Luckynyx:BAAANQAECgEIAQAAAA==.Lunate:BAAANQADCgQIBAABNQAECgkJIwADAEAhAA==.Lunavere:BAAANQADCgQIBgAAAA==.',
Ma='Machotedan:BAABNQAECoElAAIFAAgK/h7jQACtAgAFAAgK/h7jQACtAgAAAA==.Macmittens:BAAANQADCggIFgAAAA==.Mamadrag:BAAANQAECgMIBAAAAA==.Managua:BAAANQADCgEIAQAAAA==.Mandwa:BAAANQADCggIGAABNQAECggIIgASAOoSAA==.Mangojuulpod:BAAANQADCgYIBgAAAA==.Mario:BAAANQAECgUICgAAAA==.Mastashifta:BAAANQADCggIHAAAAA==.Mataa:BAABNQAECoEjAAISAAcKyxaAswD5AQASAAcKyxaAswD5AQAAAA==.Matryoshka:BAAANQADCgUIDQAAAA==.Maxxim:BAAANQADCgYIFwAAAA==.Mayihmpurleg:BAAANQADCgYIBgABNQAECgkJJwAOACgRAA==.',
Me='Meta:BAAANQADCggIDgAAAA==.',
Mi='Mistaya:BAAANQADCgUIBQABNQAECgUIDgAEAAAAAA==.Mists:BAAANQAFFAQIBAAAAA==.Miththrawndo:BAABNQAECoEeAAIfAAgK6wzfUwCCAQAfAAgK6wzfUwCCAQAAAA==.',
Mo='Momjeans:BAABNQAECoEhAAISAAkK9Rn/UgDKAgASAAkK9Rn/UgDKAgAAAA==.',
Mu='Muu:BAAANQADCgYICAAAAA==.',
My='Mydaan:BAAANQADCgIIAgAAAA==.Mythunsarian:BAAANQAECgUIBQAAAA==.',
['Má']='Mákï:BAAANQAECgUIEAAAAA==.',
['Mä']='Mäylä:BAAANQAECgcIEQAAAA==.',
['Mí']='Míst:BAABNQAECoEnAAIFAAgKNxZLcQAeAgAFAAgKNxZLcQAeAgAAAA==.',
Na='Narlis:BAABNQAECoEnAAIUAAgKESQHEwAJAwAUAAgKESQHEwAJAwAAAA==.',
Ne='Nephie:BAAANQAECgYICwAAAA==.Nezqk:BAACNQAFFIEFAAMUAAIKrRFuFACaAAAUAAIKlxFuFACaAAAIAAIKXgmqEgCEAAA1AAQKgSUABBQACQq5G/oqAGgCABQACQotGvoqAGgCAB8ACAqVEwdFAMcBAAgABAriE4VaAO4AAAAA.Nezquick:BAAANQADCgQIBAAAAA==.',
Ni='Niano:BAAANQABCgIIAgAAAA==.',
Nm='Nmnenthe:BAAANQAECgYIEwAAAA==.',
No='Notrealword:BAAANQAECgMIAwABNQAECggIJQAPAAIfAA==.Noxluminous:BAAANQABCgIIAgAAAA==.',
Ob='Obin:BAABNQAECoEZAAMLAAYKRg9DFwAHAQAJAAYK6AxavABUAQALAAUKAg5DFwAHAQAAAA==.',
Oc='Occasionally:BAAANQAECgIIAgAAAA==.',
Om='Ominious:BAABNQAECoEiAAMaAAgKmhU3FAD9AQAaAAcKaRI3FAD9AQANAAUKIRc7lQA/AQABNQABCgEIAQAEAAAAAA==.Omnius:BAABNQAECoEVAAMNAAgKtRXtTwALAgANAAgKtRXtTwALAgAMAAEKMAvrDwEkAAAAAA==.Omnya:BAAANQAECgcIDQABNQABCgEIAQAEAAAAAA==.',
Ow='Owendriel:BAAANQAFFAIIBAAAAA==.',
Pa='Paindya:BAAANQAECgQIBAAAAA==.Paleigh:BAAANQABCgYICwAAAA==.Palivok:BAAANQADCgEIAQAAAA==.Pandress:BAAANQAECgUIDQAAAA==.Pankake:BAAANQAECgQIBAABNQAECggIIAAgAKwgAA==.Paralysis:BAABNQAECoEkAAIhAAkKcRWbGAB9AgAhAAkKcRWbGAB9AgAAAA==.',
Pe='Peetza:BAAANQADCgYIBgABNQAECggIIAAgAKwgAA==.Peryite:BAABNQAECoElAAMBAAgKORgxQwA5AgABAAgKMBgxQwA5AgAiAAQK6xAiEwDbAAAAAA==.',
Ph='Phaedrana:BAAANQAECgUICAAAAA==.',
Pi='Pisscat:BAAANQAECgIIBQAAAA==.',
Po='Pocketdragon:BAABNQAECoElAAMjAAkK0hUxDQB1AgAjAAkK+BQxDQB1AgAkAAYKHREBDgA8AQAAAA==.',
Pr='Prideindeath:BAAANQADCgUIBQAAAA==.Promiscuity:BAAANQAECgcIDwAAAA==.Prængle:BAAANQADCgYIAwAAAA==.',
Ps='Psoas:BAABNQAECoEjAAMDAAkKQCGLBgBfAwADAAkKQCGLBgBfAwABAAIK4BBbywB8AAAAAA==.Psypriest:BAEBNQAECoEcAAIBAAgKzxYHQABFAgABAAgKzxYHQABFAgABNQAFFAcIGQABAAUPAA==.',
Py='Pyroheal:BAAANQAECgMIAwAAAA==.',
Qu='Quaichang:BAAANQADCgYIBgAAAA==.',
Ra='Rabbi:BAABNQAECoEiAAIDAAgK3x8sEgC+AgADAAgK3x8sEgC+AgAAAA==.Rahfna:BAAANQADCgcIDwAAAA==.Railænu:BAAANQADCggIDgAAAA==.Rainmist:BAAANQADCgYIBgAAAA==.Ranric:BAAANQADCggICAAAAA==.',
Re='Reesespbc:BAAANQAECgYIDQAAAA==.Reina:BAAANQAECgMIBAABNQAECggIIQABAMohAA==.Reinz:BAAANQAECgIIAgAAAA==.Rektagar:BAABNQAECoElAAINAAgKhCT5EQBMAwANAAgKhCT5EQBMAwABNQAFFAcIGQAPANkhAA==.Ressandra:BAAANQADCgMIBgAAAA==.Rezo:BAAANQAECgEIAgAAAA==.',
Ri='Riverarose:BAAANQADCggIFQAAAA==.',
Ro='Roar:BAAANQAECgIIAwABNQAECgUICwAEAAAAAA==.',
Ry='Rysi:BAAANQADCgQIBAAAAA==.',
['Rò']='Ròs:BAACNQAFFIEFAAIGAAIKmhndCACXAAAGAAIKmhndCACXAAA1AAQKgSUAAgYACQruH+YIAPMCAAYACQruH+YIAPMCAAAA.',
['Rö']='Rös:BAAANQADCgEIAQABNQAFFAIIBQAGAJoZAA==.',
Sa='Saberie:BAAANQADCggIFwABNQADCgMIBgAEAAAAAA==.Salaria:BAAANQAECgYIEwAAAA==.Salina:BAEANQAECgYIDwAAAA==.Sandstique:BAABNQAECoEiAAIMAAgKkST3DgA2AwAMAAgKkST3DgA2AwAAAA==.Sandweaver:BAAANQADCgcIBwAAAA==.Sanjira:BAAANQADCgYIBgAAAA==.Sarlak:BAABNQAECoElAAMPAAgK8B1EMAC6AgAPAAgK8B1EMAC6AgAOAAEK8Ab5gwArAAAAAA==.Sarusuby:BAABNQAECoEnAAIeAAkKRg+hFgC9AQAeAAkKRg+hFgC9AQAAAA==.Satae:BAABNQAECoEgAAIgAAgKrCAZBADmAgAgAAgKrCAZBADmAgAAAA==.',
Sc='Schufft:BAAANQAECgYIEAAAAA==.Scottydh:BAAANQADCgYJBgABNQAECgkJJgAfANogAA==.Scottymac:BAABNQAECoEmAAIfAAkK2iDSDAA6AwAfAAkK2iDSDAA6AwAAAA==.Scottypal:BAAANQAECgEIAQABNQAECgkJJgAfANogAA==.',
Se='Seatah:BAAANQAECgMIAwAAAA==.Seba:BAAANQAECgYICAAAAA==.Seetah:BAABNQAECoEYAAMBAAgKqxItWQDnAQABAAgKqxItWQDnAQADAAIK6wwhXABlAAAAAA==.',
Sh='Shadaddy:BAABNQAECoEdAAMSAAkK/yCnVQDEAgASAAgKYCCnVQDEAgAlAAMKNyASGgD7AAAAAA==.Shakasana:BAAANQADCggICAAAAA==.Shal:BAAANQAECgYIEgAAAA==.Shamanluz:BAAANQADCgIIAgABNQAECgQIBAAEAAAAAA==.Shamommy:BAAANQADCgUIBAAAAA==.Shamtaz:BAAANQAECgUIBQAAAA==.Shimmerstar:BAABNQAECoEcAAIFAAkKTRwUWABlAgAFAAkKTRwUWABlAgAAAA==.Shroomgirl:BAAANQAECgUIBQAAAA==.',
Si='Silexe:BAAANQAECgUIDAAAAA==.Sitga:BAAANQADCgIIAgAAAA==.',
Sl='Slipperyboi:BAAANQAECgQICQAAAA==.Slÿ:BAAANQAECgIIAgAAAA==.',
So='Solarion:BAAANQAECgYIDQABNQAECgYIEgAEAAAAAA==.Soldraca:BAAANQADCgYIEgAAAA==.',
St='Stats:BAAANQAECgUICgABNQAECgUICwAEAAAAAA==.Stinkbug:BAAANQADCgQIBAAAAA==.Stutters:BAABNQAECoEfAAIfAAgKlh2+HwCcAgAfAAgKlh2+HwCcAgAAAA==.',
Su='Subayyru:BAAANQADCgEIAQABNQAECgQICwAEAAAAAA==.Sudachi:BAAANQADCgYIBgABNQAFFAYKDAAmAMIYAA==.Sunnyräy:BAAANQAECgMIAwAAAA==.Suthrheimr:BAABNQAECoEcAAILAAgKthvQBQCRAgALAAgKthvQBQCRAgAAAA==.',
Sy='Symphany:BAAANQABCggIDAAAAA==.',
['Sý']='Sýndrá:BAAANQAECgYIDQAAAA==.',
Ta='Takafune:BAAANQADCgQIBgAAAA==.Talespin:BAAANQADCgcIBwAAAA==.Talysiah:BAAANQAECgUIDgAAAA==.Tavok:BAABNQAECoEbAAILAAcKJx+/BgBxAgALAAcKJx+/BgBxAgAAAA==.Tazbis:BAAANQAECgIIAgAAAA==.',
Te='Teishuku:BAABNQAECoEnAAIFAAkK2BAFdgASAgAFAAkK2BAFdgASAgAAAA==.Teusday:BAABNQAECoEaAAIIAAcK1xf/LAAAAgAIAAcK1xf/LAAAAgAAAA==.',
Th='Thiux:BAABNQAECoEaAAMYAAcKDiKDawD0AQAYAAUKISODawD0AQAQAAIKYB8yQAC3AAAAAA==.Thoeleden:BAAANQAECgMIBgABNQAFFAUIDwAMAIgiAA==.Thotsnprayrs:BAAANQAECgMIAwABNQAECgUIEwAEAAAAAA==.Thrappy:BAABNQAECoEhAAMMAAgKOhU8SAAVAgAMAAgKOhU8SAAVAgANAAUKSBjMjABTAQAAAA==.Thryna:BAAANQADCgEIAQAAAA==.',
Ti='Tinsoon:BAAANQAECgQIBAAAAA==.Tintaglia:BAABNQAECoEmAAMYAAgK3xeYRQBkAgAYAAgK3xeYRQBkAgAZAAEKZBE9LQAxAAABNQAECgUICgAEAAAAAA==.Tirtun:BAABNQAECoEkAAIlAAkK/B5TAgAqAwAlAAkK/B5TAgAqAwAAAA==.',
Tr='Triggeer:BAAANQAECgYIEwAAAA==.Trolldemort:BAAANQADCgYIBgAAAA==.',
Tu='Tully:BAAANQAECgQICwAAAA==.Tunkhan:BAAANQADCgQIBAAAAA==.',
Tw='Twelvekill:BAACNQAFFIEFAAIPAAIKGAtTIwCPAAAPAAIKGAtTIwCPAAA1AAQKgSUAAg8ACQqtH88cAAoDAA8ACQqtH88cAAoDAAAA.',
Ty='Tyliaa:BAABNQAECoEfAAIMAAgKYBm9OwBIAgAMAAgKYBm9OwBIAgABNQAECgMIBAAEAAAAAA==.',
Ul='Ultramon:BAAANQAECgcIEAAAAA==.',
Un='Unbreakabull:BAAANQADCgEIAgAAAA==.Unwell:BAAANQAECgYIEgABNQAECgkJJAAJALAcAA==.',
Ur='Urgoochness:BAAANQADCgQIBAAAAA==.Urikhai:BAAANQADCggIAgAAAA==.',
Va='Vainglorious:BAAANQADCggIEwABNQAECgcIEwAEAAAAAA==.Valanora:BAABNQAECoEhAAIZAAgKuxP2BQA1AgAZAAgKuxP2BQA1AgAAAA==.Valerie:BAAANQAECgIIAgABNQAECgkJIQAOAMwZAA==.Valinaxius:BAAANQADCggIGQAAAA==.Vapturov:BAAANQADCggIGQAAAA==.',
Ve='Veeks:BAABNQAECoEfAAINAAcKfgxefAB+AQANAAcKfgxefAB+AQAAAA==.Velikirn:BAAANQAECgcIDQAAAA==.Velydia:BAAANQAECgYIBgAAAA==.Venefica:BAAANQAECgEIAgAAAA==.Verdracee:BAAANQABCgMIAwABNQAECgMIBAAEAAAAAA==.Versø:BAAANQAECgYIEwAAAA==.Veryzi:BAAANQAECgEIAgAAAA==.',
Vi='Vine:BAAANQADCgIIAgAAAA==.',
Vl='Vlyrae:BAAANQADCgMIAwABNQABCgEIAQAEAAAAAA==.',
Vo='Voidhearted:BAABNQAECoEsAAIDAAgKOxENJADpAQADAAgKOxENJADpAQAAAA==.Vonzuo:BAAANQAECgIIAgAAAA==.',
Vu='Vukodlak:BAAANQADCgYIBgABNQAECgUICgAEAAAAAA==.',
['Vì']='Vìolet:BAAANQADCgMIAwABNQAECgcIHgAHAEwhAA==.',
Wa='Warriorwuu:BAAANQABCgIIAgAAAA==.Wayshua:BAAANQADCgYIBgAAAA==.',
We='Werkajerk:BAAANQADCggICAABNQAFFAUIDwAMAIgiAA==.Werkjathal:BAACNQAFFIEPAAIMAAUKiCL7BAD/AQAMAAUKiCL7BAD/AQA1AAQKgSIAAgwACQqvJsAAANkDAAwACQqvJsAAANkDAAAA.',
Wi='Wibbles:BAAANQADCgcICwAAAA==.Wigarthan:BAAANQADCgEIAQAAAA==.',
Wo='Wolfblitzer:BAABNQAECoEZAAIFAAgKExYmegAHAgAFAAgKExYmegAHAgAAAA==.Worgenator:BAAANQADCgMIAwAAAA==.Worldbane:BAABNQAECoEfAAIQAAgKxQ8pEQDlAQAQAAgKxQ8pEQDlAQAAAA==.',
Wr='Wraithlash:BAAANQAECggIDgAAAA==.',
Wt='Wtyczka:BAAANQABCgUIBQAAAA==.',
Wu='Wuulock:BAAANQABCgEJAQAAAA==.',
Wy='Wynnhrt:BAAANQADCggICAAAAA==.',
Xa='Xalatath:BAAANQAECgcIDQAAAA==.Xanakmando:BAAANQADCggIFQAAAA==.Xanthos:BAAANQADCgIIAgAAAA==.',
Xi='Xianyu:BAAANQAECgUIDAAAAA==.',
Ya='Yarian:BAAANQAECgMIAwAAAA==.',
Ym='Ymirr:BAAANQABCgcICAAAAA==.',
Yu='Yuck:BAAANQAECgIIAgABNQAFFAUIDwAMAIgiAA==.',
Za='Zachhunter:BAACNQAFFIEZAAMPAAcK2SHwCACSAQAOAAUK4h3XBgC5AQAPAAQKjyPwCACSAQA1AAQKgSoAAw4ACQp5JI0SALsCAA4ACApxI40SALsCAA8ABwp5H6paADsCAAAA.Zachmage:BAAANQADCggIFgAAAA==.Zan:BAACNQAFFIEFAAMMAAIKWAhzHgCIAAAMAAIKWAhzHgCIAAANAAEKVBV+JgBRAAA1AAQKgSUAAw0ACQofHsoeAPcCAA0ACQofHsoeAPcCAAwAAwomEVfJAKwAAAAA.',
Ze='Zeronation:BAAANQAECgIIAgAAAA==.',
Zi='Zinar:BAAANQABCggIDgAAAA==.Zinderella:BAAANQADCgYIBgAAAA==.',
Zu='Zultrix:BAAANQADCggIEQABNQAECgQIBQAEAAAAAA==.',
Zy='Zylaeri:BAAANQAECgYICAAAAA==.',
['Éo']='Éowyn:BAAANQADCgEIAQAAAA==.',
['Ël']='Ëllër:BAAANQAECgYIBwAAAA==.',
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
