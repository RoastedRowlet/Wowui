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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Warrior-Arms','Paladin-Protection','Paladin-Retribution','Warrior-Protection','Shaman-Restoration','Unknown-Unknown','Druid-Balance','Druid-Restoration','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Guardian','Druid-Feral','Evoker-Preservation','Priest-Shadow','DemonHunter-Havoc','Hunter-BeastMastery','Paladin-Holy','Warrior-Fury','Mage-Arcane','Shaman-Elemental','Mage-Frost','DeathKnight-Blood','DemonHunter-Devourer','Priest-Holy','DemonHunter-Vengeance','Monk-Brewmaster','Monk-Windwalker','Rogue-Assassination','Rogue-Subtlety','Evoker-Devastation','Hunter-Marksmanship','Rogue-Outlaw','Priest-Discipline','Evoker-Augmentation','Monk-Mistweaver','Shaman-Enhancement',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aanien:BAAANQADCgYICAAAAA==.',
Ac='Acedk:BAABNQAECn8hAAMBAAkKoiHlGQDvAgABAAkKPCDlGQDvAgACAAUKdiDaQgCzAQAAAA==.Aceslam:BAABNQAECn8YAAIDAAgKuiE+MgD0AgADAAgKuiE+MgD0AgABNQAECgkJIQABAKIhAA==.',
Ad='Adrador:BAABNQAECn8dAAMEAAgKZSCDCQADAwAEAAgKZSCDCQADAwAFAAMKgRGAHAHpAAAAAA==.Adrenaline:BAACNQAFFH8JAAIGAAUK1RkjAgCJAQAGAAUK1RkjAgCJAQA1AAQKfzMAAgYACQoEJG8CAI4DAAYACQoEJG8CAI4DAAAA.',
Ae='Aelik:BAABNQAECn8kAAIBAAYKmBnCZwBuAQABAAYKmBnCZwBuAQAAAA==.Aeolian:BAAANQADCgYIDgAAAA==.Aeru:BAAANQADCgQIBAAAAA==.',
Ak='Akueria:BAAANQADCgcIBwAAAA==.',
Al='Alayssa:BAAANQAECgUIDQAAAA==.Alda:BAAANQADCgYIFgAAAA==.Alemental:BAAANQAECgcIDwAAAA==.Aleska:BAAANQAECgQIDwAAAA==.Allarius:BAAANQAECgQIBAAAAA==.Allevist:BAAANQADCgUICQAAAA==.Alo:BAABNQAECn8rAAIHAAkKSxYBPgBlAgAHAAkKSxYBPgBlAgABNQAECgEJAQAIAAAAAA==.',
Am='Amilee:BAAANQADCggIDwAAAA==.Amoondai:BAAANQADCgYICAAAAA==.Amoondrin:BAABNQAECn8eAAMJAAkKTAgBVwB2AQAJAAgK5wcBVwB2AQAKAAEK3wO8eQAnAAAAAA==.',
An='Analiya:BAAANQADCgQJBQAAAA==.Anatyr:BAAANQADCggIDgAAAA==.Andoria:BAAANQABCggICwAAAA==.',
Ar='Aramathis:BAAANQAECgUIBQAAAA==.Araviin:BAAANQAECgUICAAAAA==.Arbor:BAAANQAECgQIBwAAAA==.Arcillias:BAAANQAECgQIBAABNQAECgQJBwAIAAAAAA==.Arilas:BAAANQAECgQICAABNQAECgQJBwAIAAAAAA==.Arkanist:BAAANQAECgUIEAAAAA==.Arthia:BAAANQADCgYICQAAAA==.Arvidpally:BAAANQAECgQICwAAAA==.',
As='Ashesius:BAABNQAECn81AAQLAAkKWhuBBADhAgALAAkKWhuBBADhAgAMAAMKYQkdGwGHAAANAAIKaxw8HgCHAAAAAA==.Ashmehameha:BAAANQAECgEIAQABNQAECgYIDwAIAAAAAA==.',
At='Atredes:BAAANQAECgYIDQAAAA==.',
Au='Auspex:BAABNQAECn8eAAIOAAcKfAe6MAARAQAOAAcKfAe6MAARAQAAAA==.',
Av='Avaryn:BAABNQAECn8aAAIKAAkKiBaVHwArAgAKAAkKiBaVHwArAgAAAA==.',
Ax='Aximlii:BAAANQADCgUICQAAAA==.',
Ba='Babs:BAAANQADCgcICgAAAA==.Badaracka:BAACNQAFFH8KAAIPAAUKlA4rAQCoAQAPAAUKlA4rAQCoAQA1AAQKfykAAw8ACQrHIqUDAGEDAA8ACQrHIqUDAGEDAA4ABQqrHA8eAKoBAAAA.Badash:BAAANQAECgMIAwABNQAECgYIDwAIAAAAAA==.Bahamuth:BAABNQAECn8qAAIFAAkK3Ba7bABUAgAFAAkK3Ba7bABUAgAAAA==.Bahamutsrage:BAAANQADCggIDgABNQAECgUICAAIAAAAAA==.Balder:BAAANQAECggIFQABNQAFFAQICgAIAAAAAQ==.Barbattos:BAACNQAFFH8JAAIQAAUKfhQdCgCEAQAQAAUKfhQdCgCEAQA1AAQKfy8AAhAACQpgIgcGAEkDABAACQpgIgcGAEkDAAAA.',
Bd='Bdyrk:BAAANQAECgYICgABNQAFFAUICgAPAJQOAA==.',
Be='Bealzeboss:BAAANQADCgcICQAAAA==.Bexley:BAABNQAECn8fAAIEAAgKbRyLEQCFAgAEAAgKbRyLEQCFAgAAAA==.',
Bi='Biggerbunny:BAABNQAECn8XAAIRAAgK7BKIJQAAAgARAAgK7BKIJQAAAgAAAA==.Biglarry:BAAANQADCgMJBQAAAA==.Biianca:BAAANQADCgUICQAAAA==.',
Bl='Blacklok:BAAANQAECgIIBAABNQAECgkJKQASAMAlAA==.Blanne:BAAANQABCgIIAgAAAA==.Blargle:BAAANQAECgIIAwAAAA==.Blegh:BAACNQAFFH8HAAIFAAMKARklFQABAQAFAAMKARklFQABAQA1AAQKfyMAAgUACQohIMkuAAsDAAUACQohIMkuAAsDAAAA.Blessyaheart:BAAANQAECgUICAABNQAECgYIEwAIAAAAAA==.Blinx:BAAANQAECgEIAgAAAA==.Bloodrake:BAABNQAECn8tAAITAAkKBxn+QQCjAgATAAkKBxn+QQCjAgAAAA==.Blueray:BAAANQADCgYIBgAAAA==.',
Bm='Bman:BAAANQAECgYIEQAAAA==.',
Br='Braneour:BAABNQAECn8pAAMEAAgKvBPgJgCkAQAEAAgKvBPgJgCkAQAUAAYK1QdHsQAYAQAAAA==.Browel:BAABNQAECn8bAAIMAAkKQBcUTQBpAgAMAAkKQBcUTQBpAgAAAA==.',
Bu='Bubblfett:BAAANQADCggICAAAAA==.Bumm:BAAANQAECgMIAwAAAA==.',
Bz='Bzspy:BAABNQAECn8iAAMDAAkKDhhCawBMAgADAAkKDhhCawBMAgAVAAIK9Aq4KgBZAAAAAA==.',
['Bë']='Bëar:BAAANQAECgEIAQAAAA==.',
Ca='Cabooselul:BAAANQAECgQIBAAAAA==.Calyptus:BAABNQAECn8bAAILAAgKSAtyGACnAQALAAgKSAtyGACnAQAAAA==.Capylaura:BAAANQAECgMIBgAAAA==.Caratine:BAAANQADCgcIDQAAAA==.Cassandrah:BAABNQAECn8pAAIWAAkK5hzdOgARAwAWAAkK5hzdOgARAwAAAA==.',
Ce='Celìa:BAAANQAECgUIBwAAAA==.',
Ch='Chillymage:BAAANQADCgcIBwAAAA==.Chpchop:BAAANQABCggIEQAAAA==.Christy:BAAANQADCgYIFQAAAA==.Chugg:BAAANQAECgYIEwAAAA==.',
Ci='Ciaphus:BAABNQAECn8rAAQFAAkKGA/btACvAQAFAAgK6A/btACvAQAUAAcKawqZjwBrAQAEAAcKNgyWNQA2AQAAAA==.Cinnamonster:BAAANQAECgQICgAAAA==.',
Cl='Clogs:BAAANQAECgUIBgAAAA==.',
Co='Coffeedemon:BAAANQAECgQIBgAAAA==.Coldslappins:BAAANQAECgMIAwABNQAECggIKQAEALwTAA==.Convalescent:BAAANQADCgYIBgAAAA==.Coragrr:BAAANQAECgIIAwAAAA==.',
Cr='Cracklepants:BAACNQAFFH8KAAIXAAUKaAntDwBoAQAXAAUKaAntDwBoAQA1AAQKfzYAAhcACQo9IeUWAD0DABcACQo9IeUWAD0DAAAA.Crashout:BAAANQAECgYIBgAAAA==.',
Cu='Curtastrophe:BAABNQAECn8qAAIYAAkKRCIkAQCQAwAYAAkKRCIkAQCQAwAAAA==.Curticus:BAAANQADCgYIBgAAAA==.',
Da='Daelanos:BAABNQAECn8YAAIDAAgKIAtRrQCmAQADAAgKIAtRrQCmAQAAAA==.Dallas:BAAANQADCgYICwAAAA==.',
De='Deathisreal:BAAANQADCgEIAgABNQAECgEIAwAIAAAAAA==.Deathoof:BAABNQAECn8aAAQBAAcK6xXoVQC2AQABAAcK6xXoVQC2AQAZAAMK/hFvlgCuAAACAAEKGgX6sAArAAAAAA==.Demonblaze:BAAANQAECgIIBgAAAA==.Demonilla:BAABNQAECn8ZAAIaAAkKcxRSHQBlAgAaAAkKcxRSHQBlAgAAAA==.Destro:BAABNQAECn8mAAIMAAkKygtHfQDoAQAMAAkKygtHfQDoAQAAAA==.',
Di='Dilaudyd:BAAANQADCgcICQAAAA==.Disbeleaf:BAAANQAECgYIEAAAAA==.Dishu:BAAANQABCgQIBAAAAA==.Dispel:BAAANQADCgYIBgAAAA==.Disputatious:BAAANQADCgQIBAAAAA==.',
Dn='Dntblink:BAAANQADCgUIBQAAAA==.',
Do='Dogaz:BAAANQADCgYIFQAAAA==.Dogsoldier:BAAANQADCgQIBAAAAA==.Donori:BAAANQADCgEIAQAAAA==.Doomphoenix:BAAANQADCgQJBAAAAA==.',
Dr='Dragonias:BAAANQAECgQICwAAAA==.Drakthorn:BAAANQADCggIEwAAAA==.Drinny:BAABNQAECn8gAAIbAAkKlwTFggCKAQAbAAkKlwTFggCKAQAAAA==.Dripington:BAABNQAECn8iAAMCAAkKoR8RFADpAgACAAkKoR8RFADpAgABAAEKAAD53QAzAAAAAA==.',
Ea='Earthangel:BAAANQAECgQICQAAAA==.',
Ef='Efon:BAAANQADCgUIBQABNQAECgUIDQAIAAAAAA==.',
Ei='Eine:BAABNQAECn8oAAITAAkK5BD/WQBjAgATAAkK5BD/WQBjAgAAAA==.',
El='Eldergreen:BAAANQAECgYIEQAAAA==.Elfwine:BAAANQAECgQICQAAAA==.Elindria:BAABNQAECn8pAAMSAAkKwCWsBACnAwASAAkKbiWsBACnAwAcAAQK2xtNEwB0AQAAAA==.Elminstir:BAABNQAECn8XAAIYAAcK0hm7CgAXAgAYAAcK0hm7CgAXAgAAAA==.Eluzhion:BAAANQADCgUICAAAAA==.Elysian:BAAANQAECgUICQAAAA==.',
Er='Erizhal:BAAANQABCgIIAgAAAA==.Eruptyon:BAAANQAECgEIAQABNQAECgcIHgAWAKsgAA==.',
Es='Esabel:BAAANQAECgcIDgABNQAECgUIDQAIAAAAAA==.',
Ev='Eviae:BAAANQAECgQICQAAAA==.Evillure:BAAANQAECgYICgAAAA==.',
Ex='Explanation:BAAANQADCgQIBAAAAA==.',
Fa='Falan:BAAANQAECgEIAQAAAA==.Farfins:BAAANQADCgYIBgAAAA==.',
Fe='Fedor:BAAANQAECggICAAAAA==.Feår:BAAANQAECgcIEwAAAA==.',
Fi='Finley:BAAANQADCgQIBAAAAA==.Fixation:BAAANQABCgIIAgAAAA==.',
Fl='Flane:BAACNQAFFH8VAAIdAAYKERy0AQD3AQAdAAYKERy0AQD3AQA1AAQKfyMAAx0ACQoAINgFAPcCAB0ACQoAINgFAPcCAB4AAQoAAKFiAE4AAAAA.Flexdruid:BAAANQAECgUIBQAAAA==.',
Fr='Fragil:BAABNQAECn8gAAMfAAkK1BzLFgDCAgAfAAkKNxzLFgDCAgAgAAQKAxW1NAAPAQAAAA==.',
Ga='Galena:BAAANQAECgQICwAAAA==.Galian:BAAANQADCggIEgAAAA==.Ganonn:BAAANQAECgQICQABNQAECgYICgAIAAAAAA==.',
Ge='Geshtal:BAAANQAECgYICwAAAA==.',
Gi='Girion:BAAANQAECgQICQAAAA==.',
Gl='Glaiven:BAECNQAFFH8JAAISAAUKlhI+CwBnAQASAAUKlhI+CwBnAQA1AAQKfzAAAxIACQrTIUEOADEDABIACQrTIUEOADEDABoABwoxF64wALcBAAAA.Glyr:BAAANQAECgEJAQAAAA==.',
Gn='Gnora:BAAANQADCggICQAAAA==.',
Go='Gorgrin:BAAANQAECgQIBQAAAA==.',
Gr='Groguu:BAAANQAECgQIBAABNQAECgkJIQABAKIhAA==.',
Ha='Harkanum:BAABNQAECn8sAAMhAAgKSAqHHACBAQAhAAgKSAqHHACBAQAQAAgK6QTYKgBTAQAAAA==.Harvester:BAAANQAECgMIBwAAAA==.',
He='Healinturds:BAAANQADCgEIAQAAAA==.Helloagain:BAAANQAECggJEgAAAA==.',
Hi='Hidethetotem:BAAANQAECgUIDAAAAA==.Hikari:BAACNQAFFH8HAAIFAAMKwQqgGgDOAAAFAAMKwQqgGgDOAAA1AAQKfyAAAgUACQpLHU1SAJsCAAUACQpLHU1SAJsCAAAA.Hiown:BAAANQABCgYICAAAAA==.',
Ho='Holyrebel:BAAANQAECgEIAQABNQAECgEIAwAIAAAAAA==.Holyspike:BAAANQAECgQICwAAAA==.Homerr:BAAANQAECgQICgAAAA==.Honiahaka:BAABNQAECn8rAAITAAkK3AydcwAmAgATAAkK3AydcwAmAgAAAA==.Hotsdog:BAAANQADCgIIAgAAAA==.Hottcakes:BAABNQAECn8wAAIWAAkK3yLCDgCYAwAWAAkK3yLCDgCYAwABNQAFFAcIFQAMABEWAA==.',
Hu='Humanoidlite:BAAANQAFFAEIAgABNQAFFAMIBQADAL0IAA==.Humanoidlock:BAAANQADCgYIDAABNQAFFAMIBQADAL0IAA==.Humanoidwar:BAACNQAFFH8FAAMDAAMKvQhtJgDHAAADAAMKvQhtJgDHAAAGAAEKoAO8CgAtAAA1AAQKfykAAwMACQraHR0zAPECAAMACQraHR0zAPECAAYABQr+DyUpAO4AAAAA.',
In='Inoru:BAAANQAECgQIBwAAAA==.',
Ir='Irmaline:BAAANQAECgQICwAAAA==.',
It='Ithurtshuh:BAAANQAECgEIAwAAAA==.',
Ja='Jabbawockie:BAABNQAECn8XAAISAAgKFwhCYgDsAAASAAgKFwhCYgDsAAAAAA==.Jackcat:BAAANQADCgQIAwAAAA==.Jackyl:BAAANQABCgYIBgAAAA==.',
Je='Jeffee:BAABNQAECn8bAAICAAgKgxlMKABRAgACAAgKgxlMKABRAgAAAA==.Jennifleur:BAAANQADCgcIBwAAAA==.Jequalsjosh:BAABNQAECn8VAAIfAAgKMRIyNAAFAgAfAAgKMRIyNAAFAgAAAA==.Jerk:BAACNQAFFH8VAAIaAAUKbiSSBADzAQAaAAUKbiSSBADzAQA1AAQKfy4AAhoACQpRJRsEAJMDABoACQpRJRsEAJMDAAAA.Jesper:BAABNQAECn81AAIHAAkKuh8/EgA0AwAHAAkKuh8/EgA0AwAAAA==.Jetz:BAAANQAECgQICQAAAA==.Jezelle:BAAANQADCggICAAAAA==.',
Ji='Jilara:BAAANQAECgUIDgAAAA==.Jimmyjim:BAAANQAECgQIBwAAAA==.',
Jo='Joink:BAAANQADCgYICQAAAA==.',
Jp='Jpepps:BAABNQAECn8kAAMMAAgK2A0miADNAQAMAAgK2A0miADNAQALAAMKcARgXgBoAAAAAA==.',
Jr='Jrose:BAAANQADCggIGQAAAA==.',
Ka='Kagozo:BAEANQAECgEIAQABNQAECgIIAgAIAAAAAA==.Kaiatra:BAAANQAECgQICwAAAA==.Kalamor:BAAANQAECgUIBQAAAA==.Kaliguala:BAAANQADCgMIAwAAAA==.Kaloran:BAAANQAECgYIDQAAAA==.Katalaystar:BAAANQADCgYIDAABNQAECgkJLgAKANseAA==.Katalegdh:BAAANQAECgMIBQAAAA==.Kative:BAAANQADCgUICAAAAA==.Kaìju:BAAANQAECgUIEgAAAA==.',
Ke='Kellytgt:BAAANQADCgQIAwAAAA==.',
Kh='Khaelyn:BAAANQADCgQIBQAAAA==.Khai:BAABNQAECn8VAAIFAAgKUw3B3ABbAQAFAAgKUw3B3ABbAQAAAA==.',
Ki='Kiae:BAAANQADCgYJBwAAAA==.Kidneyspears:BAAANQADCgYIBgAAAA==.Kilaura:BAAANQADCgUIBQAAAA==.Kilmandaros:BAAANQAECgUIBgAAAA==.Kimblee:BAAANQADCgQIBAAAAA==.',
Ko='Korbix:BAAANQABCgUIBAABNQAECgUIBgAIAAAAAA==.',
Kr='Kronmon:BAAANQADCgQIBAAAAA==.',
Ku='Kudria:BAABNQAECn8XAAITAAcKYRX+hwD3AQATAAcKYRX+hwD3AQAAAA==.Kunei:BAAANQABCgYICQABNQAECgEIAgAIAAAAAA==.Kurdran:BAAANQABCgQIAgAAAA==.Kuroyukihime:BAABNQAECn8iAAIYAAgKOBw9BgCfAgAYAAgKOBw9BgCfAgAAAA==.',
Ky='Kylas:BAAANQADCgUICAAAAA==.Kynae:BAAANQAECgQIEQAAAA==.Kyross:BAAANQABCgIIAgAAAA==.',
['Ká']='Kárma:BAAANQADCgYICwABNQAECgcIEwAIAAAAAA==.',
La='Lashela:BAAANQAECgUIEgAAAA==.Laughter:BAAANQAECgQIBgAAAA==.Lavamylash:BAAANQAECgYICgAAAA==.Laylla:BAAANQAECgMIBgAAAA==.Lazulie:BAAANQAECgQICAAAAA==.',
Le='Lefnedrav:BAAANQADCgYICgABNQAECggIIAAeAKcXAA==.Lektrik:BAAANQAECgEIAQAAAA==.Lenexa:BAAANQADCgUICAAAAA==.Lexapayne:BAAANQADCgEIAQABNQAECggIGAATALoPAA==.Leyra:BAABNQAECn8YAAIiAAgK3xXWJAAjAgAiAAgK3xXWJAAjAgABNQAECgkJKQASAMAlAA==.',
Li='Lighthammer:BAAANQADCggIDgAAAA==.Lightmessiah:BAABNQAECn8aAAMFAAgKERlPfAAtAgAFAAgKERlPfAAtAgAUAAUK0REgrgAgAQAAAA==.Lightnig:BAAANQADCgUIBQAAAA==.Lilyvain:BAAANQAECgEIAQAAAA==.Lireal:BAABNQAECn8eAAIUAAgK4R9XIwDcAgAUAAgK4R9XIwDcAgAAAA==.Livnod:BAAANQADCggIDgAAAA==.',
Lo='Lonon:BAAANQAECgcIEwAAAA==.Loosescrew:BAAANQADCgQIBQAAAA==.Lorine:BAABNQAECn8oAAIEAAkK+RlBEACXAgAEAAkK+RlBEACXAgAAAA==.',
Lu='Lunara:BAAANQADCgYIDAAAAA==.',
Ly='Lynnethe:BAAANQAECgYIDgAAAA==.',
Ma='Malkiel:BAAANQAECgQIDgAAAA==.Mantang:BAAANQABCgIIAgAAAA==.Mastakillah:BAAANQADCgQICAABNQAECgUIEQAIAAAAAA==.Maxamus:BAAANQADCgQIBAAAAA==.',
Me='Meeseeks:BAAANQAECgcIDQAAAA==.Merckel:BAABNQAECn8sAAIaAAkKDxv1DwDwAgAaAAkKDxv1DwDwAgAAAA==.Messorom:BAAANQADCgEIAQAAAA==.',
Mi='Michello:BAAANQAECgQICwAAAA==.Mightytot:BAAANQADCgcIDQAAAA==.Millia:BAABNQAECn8eAAMWAAcKqyDpywDrAQAWAAUKWSLpywDrAQAYAAIKJh4fKQCqAAAAAA==.Mint:BAABNQAECn8fAAIUAAkKGBXMQQBbAgAUAAkKGBXMQQBbAgAAAA==.Mintberrytea:BAAANQAECgQJBAABNQAECgkJHwAUABgVAA==.Misstress:BAABNQAECn8eAAMJAAgK4AneTwCaAQAJAAgK4AneTwCaAQAOAAEKAACLbQAdAAAAAA==.',
Mo='Moistweaver:BAAANQADCgYIBgAAAA==.Monoxide:BAAANQADCgUIBQABNQAECgYIEwAIAAAAAA==.Mooncloud:BAAANQADCggICQAAAA==.Moonhunt:BAAANQAECgQIBAAAAA==.Morkleb:BAAANQAECgUICwAAAA==.Morrag:BAAANQAECgYIEAAAAA==.Morrtisha:BAAANQAECgYICwAAAA==.',
Mu='Munchkins:BAAANQABCgcIDQAAAA==.Munden:BAAANQADCgUIBQABNQAECgQIDgAIAAAAAA==.',
My='Myxie:BAABNQAECn8bAAIHAAcKuxRIbADDAQAHAAcKuxRIbADDAQAAAA==.',
['Mí']='Mísfìt:BAABNQAECn8qAAIHAAkKrRxFIwDYAgAHAAkKrRxFIwDYAgAAAA==.',
Na='Nakaito:BAAANQAECgYIEQABNQAECggIIgAfAO4QAA==.Narcoleptic:BAABNQAECn8rAAMQAAkKVxVbEgCFAgAQAAkKVxVbEgCFAgAhAAUKzQtKJgABAQAAAA==.Nashty:BAAANQADCgIIAgAAAA==.Naturaljuice:BAAANQAECggICwABNQAFFAcIFQAMABEWAA==.Naturebreakr:BAAANQAECggIEwAAAA==.',
Ne='Nex:BAABNQAECn8iAAIWAAkKJSFhNwAaAwAWAAkKJSFhNwAaAwAAAA==.',
Ni='Nightsawdy:BAAANQAECgUIDwAAAA==.Niightstorm:BAAANQAECgQICAAAAA==.Nilvannas:BAAANQADCggICAAAAA==.Nitefire:BAAANQADCgYIFgAAAA==.Nitélifé:BAAANQAECgUIBQAAAA==.',
Of='Offspring:BAAANQABCgIIAgAAAA==.',
Om='Omora:BAAANQAECgUIEAABNQAECggIIAAeAKcXAA==.',
Op='Opalinnas:BAABNQAECn8uAAIKAAkK2x4xCABAAwAKAAkK2x4xCABAAwAAAA==.Optimism:BAAANQADCgIIAgAAAA==.',
Pa='Paladrone:BAAANQABCggIDwABNQADCgcICgAIAAAAAA==.Pallyandtank:BAAANQAECgEIAQAAAA==.Panzer:BAABNQAECn8eAAIOAAcKhhTnHgChAQAOAAcKhhTnHgChAQAAAA==.Parts:BAABNQAECn8YAAQfAAgKFA4uTwB8AQAfAAYKwg8uTwB8AQAjAAMK0gofFQCbAAAgAAEKNxD1TQBDAAABNQAECggIHAADAF0RAA==.Passionfruit:BAAANQAECgcIBwAAAA==.Paul:BAAANQAECgUICgAAAA==.',
Pe='Peachtea:BAAANQAECgYICQAAAA==.Pepecojon:BAAANQADCggIDwAAAA==.',
Pi='Piebaby:BAAANQADCgUIBgAAAA==.Pirodeath:BAAANQAECgYICAAAAA==.',
Pl='Plovdiv:BAAANQADCgcJCQAAAA==.',
Po='Poah:BAAANQAECgYIBgAAAA==.',
Pr='Pray:BAABNQAECn8rAAMkAAkKLSN2AQA5AwAbAAkKGSCzEABAAwAkAAgKMiR2AQA5AwAAAA==.Prodarkangel:BAAANQADCgcJCQAAAA==.',
Pu='Puckllane:BAAANQAECgEIAgAAAA==.Punkin:BAAANQADCggIEwAAAA==.',
Py='Pyre:BAABNQAECn8eAAIkAAgKWg2DCgCeAQAkAAgKWg2DCgCeAQABNQAECgEJAQAIAAAAAA==.',
['Pü']='Püff:BAAANQADCgEIAQABNQAECgQJBwAIAAAAAA==.',
Qu='Quanah:BAABNQAECn8VAAIHAAcK1B5TPwBgAgAHAAcK1B5TPwBgAgAAAA==.Quivver:BAAANQADCgYIEgAAAA==.',
Ra='Rabmaxx:BAABNQAECn8WAAISAAkKWQTgVgApAQASAAkKWQTgVgApAQAAAA==.Raina:BAAANQADCgYIBgAAAA==.Rap:BAAANQAECgMIAwAAAA==.Ravenlight:BAABNQAECn8fAAIFAAkK/xV1cwBDAgAFAAkK/xV1cwBDAgAAAA==.Ravenwynnd:BAABNQAECn8oAAMDAAkKCiD2HABCAwADAAkKCiD2HABCAwAGAAYKFh1rFQDNAQAAAA==.Raynman:BAABNQAECn8kAAIXAAgK5hLiYwDyAQAXAAgK5hLiYwDyAQAAAA==.',
Re='Reylariel:BAAANQADCgMIAwAAAA==.',
Rh='Rhydian:BAAANQADCgQIBAAAAA==.Rhyzer:BAAANQAECgQICQAAAA==.',
Ri='Riiver:BAAANQADCgYIBgAAAA==.',
Ro='Roderick:BAAANQADCggIEAAAAA==.Root:BAAANQAECggIEgAAAA==.',
Ru='Rubmytotem:BAAANQAECgYICwAAAA==.',
Sa='Sabazia:BAABNQAECn8pAAIZAAgKHxMWSADUAQAZAAgKHxMWSADUAQAAAA==.Sabelinå:BAAANQAECgEIAgAAAA==.Sable:BAAANQADCgEIAQAAAA==.Sacred:BAAANQAECgcICwAAAA==.Saerise:BAAANQADCggIDgAAAA==.Sairalindë:BAAANQAECgUIBwAAAA==.Salamandra:BAAANQADCggIEwABNQAECggIIAAeAKcXAA==.Saleath:BAAANQAECgIIAgAAAA==.Salios:BAAANQAECgEIAQAAAA==.Sanara:BAAANQABCgUIBwABNQAECgQICQAIAAAAAA==.Sanctifier:BAAANQADCgUIBQAAAA==.',
Sc='Scrept:BAAANQAECggICgAAAA==.Scynix:BAEBNQAECn8bAAMQAAgKJwnTJgCAAQAQAAgKJwnTJgCAAQAlAAcKRQyZDQBwAQAAAA==.',
Se='Seizuregoat:BAAANQAECgMJAwAAAA==.Senus:BAAANQADCgEIAQAAAA==.Servoker:BAAANQAECgcICwAAAA==.',
Sh='Shabzyt:BAAANQAECgYIEQAAAA==.Shaienne:BAAANQADCgcIDgAAAA==.Shammander:BAAANQAECgUIBgAAAA==.Shamrockshak:BAAANQAECgIIBAAAAA==.Shamron:BAAANQADCgcICgAAAA==.Shenuton:BAAANQAECgUICgAAAA==.Shieldbash:BAABNQAECn80AAIGAAkK0yT6AADNAwAGAAkK0yT6AADNAwAAAA==.Shockthêràpy:BAABNQAECn8iAAMHAAkKHCAyHgDxAgAHAAkKHCAyHgDxAgAXAAEKzw58LQE3AAAAAA==.Shoes:BAAANQAECgYICgAAAA==.Shtdruid:BAAANQAECgEIAQAAAA==.',
Si='Sibearian:BAAANQAECgUIDgABNQAECgcIGgABAOsVAA==.Sibeson:BAAANQAECgYIEAABNQAECgcIGgABAOsVAA==.Simi:BAABNQAECn8YAAITAAgKug+ofwAKAgATAAgKug+ofwAKAgAAAA==.',
Sm='Smithnwesson:BAAANQABCgUIBQAAAA==.Smokesçreen:BAABNQAECn8nAAMcAAgKXBHeDgDGAQAcAAgKXBHeDgDGAQASAAcKKQl7TgBcAQAAAA==.',
So='Soonerpride:BAABNQAECn8WAAIFAAcKbiPIVwCMAgAFAAcKbiPIVwCMAgAAAA==.Soothed:BAAANQADCggICAAAAA==.',
Sp='Spearminttea:BAAANQADCgIIAgAAAA==.Spellbreakr:BAABNQAECn8bAAIWAAkK3R2aZgCxAgAWAAkK3R2aZgCxAgAAAA==.Spirtbreaker:BAAANQAECgYIDQAAAA==.',
Sq='Squeak:BAAANQADCgUICQAAAA==.Squiby:BAABNQAECn8rAAMRAAkKayLQBQB6AwARAAkKayLQBQB6AwAbAAEKlxXF9gA3AAAAAA==.',
St='Stankowitz:BAAANQABCgQICAABNQADCgYIBgAIAAAAAA==.Starboi:BAAANQADCgUIBQAAAA==.Starce:BAAANQABCgMIAwAAAA==.Steveirwin:BAAANQADCgYICgAAAA==.Stheris:BAABNQAECn8YAAIfAAkKVA6rLwAfAgAfAAkKVA6rLwAfAgAAAA==.Stuefester:BAAANQAECgYIEQAAAA==.',
Sv='Sveika:BAAANQAECgQICwAAAA==.',
Sy='Sylaria:BAEANQADCggIEAAAAA==.Syreline:BAAANQAECgEIAQAAAA==.',
['Sï']='Sïn:BAAANQAECgUIEQAAAA==.',
['Sý']='Sýlver:BAABNQAECn8aAAIJAAcKNwyPUACXAQAJAAcKNwyPUACXAQAAAA==.',
Ta='Tarathiel:BAAANQADCgIIAgAAAA==.Tarpalantir:BAAANQADCgcICAAAAA==.Taurne:BAABNQAECn8sAAMKAAkKORljFgCNAgAKAAkKORljFgCNAgAJAAMKiQVVlgB5AAAAAA==.',
Tc='Tchnce:BAAANQADCgcICgAAAA==.',
Te='Teknoman:BAABNQAECn8rAAMDAAgKlBgsbwBCAgADAAgKlBgsbwBCAgAGAAEKBwV+SQAgAAAAAA==.Telephone:BAAANQAECgEIBQAAAA==.Tempered:BAABNQAECn8cAAIDAAgKXRGckgDpAQADAAgKXRGckgDpAQAAAA==.Teresen:BAAANQADCgIIAgAAAA==.',
Th='Thaitea:BAAANQADCgIIBAAAAA==.Thalindra:BAAANQAECgQICQAAAA==.Tharain:BAAANQAECgQIBQAAAA==.Thebigbeast:BAAANQAECgQIDAABNQAFFAcIFQAMABEWAA==.Thecurt:BAABNQAECn8rAAIdAAkKQiM0AgCMAwAdAAkKQiM0AgCMAwAAAA==.Thunderrbutt:BAAANQAECgYIEwAAAA==.Thyralizen:BAAANQADCgQIBQAAAA==.',
Ti='Tiael:BAAANQAECgIIAgAAAA==.Timaeus:BAAANQADCggIGgAAAA==.Tinylef:BAABNQAECn8gAAQeAAgKpxcTJwDlAQAeAAcKpxcTJwDlAQAmAAYK4wcrLwDrAAAdAAEKAACqLgBDAAAAAA==.Tirouke:BAAANQAECgMIBAAAAA==.Titanlock:BAAANQADCgcIDQAAAA==.',
Tk='Tkdfath:BAAANQADCgYIBgAAAA==.',
To='Toralina:BAAANQAECgEIAQAAAA==.Torvia:BAAANQADCgcIDwAAAA==.',
Tr='Trisinz:BAAANQAECgUJCQAAAA==.',
Tu='Tuerto:BAAANQAECgcIEAAAAA==.Tuiarmstrong:BAAANQAECgUICgABNQAFFAUICQAbAFoXAA==.Turbojohnson:BAAANQAECgEIAQAAAA==.Turk:BAABNQAECn80AAIaAAkK2xOJHQBjAgAaAAkK2xOJHQBjAgAAAA==.Turkish:BAABNQAECn8cAAICAAcKOg7NTgByAQACAAcKOg7NTgByAQAAAA==.',
Tw='Twinkytoes:BAAANQADCggIEwAAAA==.',
Ty='Tychaa:BAAANQADCgYIEgAAAA==.Tylat:BAAANQABCgMIAwAAAA==.Tyranax:BAABNQAECn8gAAIbAAcKpR4eQQBjAgAbAAcKpR4eQQBjAgAAAA==.Tyrith:BAAANQADCgMIAwAAAA==.',
Ui='Uintah:BAAANQAECgUIBwAAAA==.',
Ul='Ullyr:BAABNQAECn8ZAAMJAAkK2RfSLAByAgAJAAkK2RfSLAByAgAPAAEKAABrTAAZAAABNQAFFAUICgAXAGgJAA==.',
Us='Userdel:BAABNQAECn8ZAAIHAAYKhgf4ugDwAAAHAAYKhgf4ugDwAAAAAA==.',
Va='Vadose:BAAANQADCgYIBgABNQAECggIGAATALoPAA==.Valytrois:BAAANQAECgEIAQAAAA==.Variant:BAAANQAECgMIAwAAAA==.Varinix:BAAANQADCgUICAAAAA==.Vauld:BAAANQADCgQJBQAAAA==.',
Ve='Veiksla:BAAANQADCgYIFAAAAA==.Vengerr:BAAANQADCgYIDwAAAA==.Verace:BAAANQAECggIAQAAAA==.Verradic:BAAANQAECgUICAAAAA==.',
Vi='Vitur:BAABNQAECn84AAIaAAkKxCNhAwChAwAaAAkKxCNhAwChAwAAAA==.Vivi:BAAANQADCgYIBgAAAA==.',
Vo='Voidbunny:BAAANQAECgYJDwAAAA==.Volaine:BAAANQAECgQICQAAAA==.Volgar:BAAANQADCgUICQAAAA==.Volition:BAAANQADCgYIBgAAAA==.Volt:BAABNQAECn8gAAInAAgKlBnoDwBoAgAnAAgKlBnoDwBoAgABNQAECgkJJgAMAMoLAA==.',
Vr='Vrye:BAABNQAECn8XAAIaAAgK3gTrSgD6AAAaAAgK3gTrSgD6AAAAAA==.',
Vy='Vynaeda:BAAANQAECgYIEAAAAA==.',
['Vô']='Vôx:BAAANQAECgIIBQABNQAECgUICQAIAAAAAA==.',
Wa='Wakko:BAAANQADCgcIEwAAAA==.Walkure:BAAANQADCgYIFgAAAA==.',
We='Weirdscience:BAAANQABCgQIBAAAAA==.Wetasstotem:BAABNQAECn8WAAIXAAkKmRxdKwDPAgAXAAkKmRxdKwDPAgABNQAFFAcIFQAMABEWAA==.',
Wh='Whew:BAAANQADCggICQAAAA==.',
Wi='Widge:BAAANQAECgQIBAAAAA==.Wikker:BAAANQADCgQIBAAAAA==.',
Wo='Worldlight:BAAANQADCgIIAgAAAA==.',
Wr='Wreckbums:BAAANQAECgMIBAAAAA==.Wreckd:BAAANQAECgYIBgABNQAECggIHAADAF0RAA==.Wrongway:BAAANQADCgQIBQAAAA==.',
Xa='Xanthad:BAAANQADCgUICAAAAA==.',
Xb='Xb:BAAANQADCgYIFgAAAA==.',
Xi='Xitãozinho:BAAANQAECgMIAwAAAA==.',
Xy='Xyomi:BAAANQADCgIIAgAAAA==.',
Ya='Yaalia:BAAANQAECgQICQAAAA==.Yaan:BAAANQAECgcICgAAAA==.Yalane:BAAANQAECgMIAwAAAA==.',
Za='Zain:BAAANQADCgYIBgABNQAECgkJNQALAFobAA==.Zalaan:BAAANQAECgYICwABNQAECgUIDQAIAAAAAA==.Zandibar:BAAANQAECgQICQAAAA==.Zaptoasted:BAAANQADCgYIBgAAAA==.Zariea:BAAANQAECgIIAgABNQAECgcIJAABAJgZAA==.Zavac:BAAANQADCgUIBwAAAA==.',
Ze='Zelritch:BAAANQADCggICAAAAA==.',
Zi='Zinfandell:BAAANQAECgUIBgAAAA==.',
Zo='Zorrloc:BAAANQADCgQIBAAAAA==.',
Zu='Zuggie:BAAANQAECgQICgAAAA==.Zugtail:BAAANQAECgEIAQABNQAECgQICgAIAAAAAA==.Zurtrinik:BAAANQAECgUICwABNQAFFAYIFQAdABEcAA==.',
Zy='Zyntalla:BAAANQAECgQICQAAAA==.',
Zz='Zzonked:BAAANQAECgEIAQAAAA==.',
['Zê']='Zêp:BAAANQADCgcIFwAAAA==.',
['Àr']='Àrròw:BAAANQADCgYICgAAAA==.',
['Ðo']='Ðoogle:BAAANQAECgQICwABNQABCgUIBQAIAAAAAA==.',
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
