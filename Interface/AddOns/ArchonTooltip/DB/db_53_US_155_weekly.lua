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

local lookup = {'Unknown-Unknown','Druid-Feral','Shaman-Restoration','Shaman-Enhancement','Shaman-Elemental','Mage-Frost','Mage-Arcane','Paladin-Holy','Paladin-Retribution','Druid-Guardian','Paladin-Protection','Rogue-Subtlety','Priest-Holy','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Hunter-BeastMastery','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','DemonHunter-Havoc','Warrior-Fury','DemonHunter-Devourer','Evoker-Devastation','Rogue-Assassination','DeathKnight-Unholy','Priest-Discipline','Warlock-Affliction','Mage-Fire','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','Evoker-Preservation','DemonHunter-Vengeance','Priest-Shadow','DeathKnight-Frost','Hunter-Marksmanship','Evoker-Augmentation','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Medivh',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abashai:BAAANQAECgYIDwAAAA==.',
Ae='Aellyria:BAAANQADCgEIAQAAAA==.Aerrikon:BAAANQAECgEIAQABNQAECgUIDgABAAAAAA==.',
Ak='Akaili:BAAANQAECgQIBwAAAA==.',
Al='Alexiya:BAABNQAECoEZAAICAAcKDw+2EgCdAQACAAcKDw+2EgCdAQAAAA==.Allacari:BAAANQAECgUIEgAAAA==.Allumer:BAAANQAECgEIAQAAAA==.Alodir:BAAANQADCgYICgABNQAECgQJBgABAAAAAA==.Alstadin:BAAANQADCgMJAwAAAA==.Alucardd:BAAANQAECgIIAwAAAA==.',
Am='Amanda:BAAANQAECgYIEgAAAA==.Amonamarth:BAAANQAECgYIEAAAAA==.',
An='Anabelleigh:BAAANQABCggIEQAAAA==.Andrise:BAABNQAECoEaAAQDAAcKWBloTgD+AQADAAcKWBloTgD+AQAEAAUKqxjlGQCWAQAFAAUKLRuNdACTAQAAAA==.Annathesia:BAAANQADCgEIAQAAAA==.Antibear:BAAANQAECgUIDwAAAA==.',
Ap='Apol:BAAANQAECgUIEAAAAA==.',
Ar='Arachne:BAABNQAECoEjAAMGAAkKORnPBQCFAgAGAAgKexvPBQCFAgAHAAUKIA0gJAEqAQAAAA==.Arafina:BAAANQABCgUICQABNQAECggIHgAIAM4MAA==.Arakar:BAABNQAECoEeAAIIAAgKzgzvZwC5AQAIAAgKzgzvZwC5AQAAAA==.Aralynne:BAAANQAECgUIDgAAAA==.Arcee:BAAANQADCgIIAgAAAA==.Arch:BAAANQAECgIIAgAAAA==.Ardori:BAAANQAECgYICgAAAA==.Arlïnn:BAAANQAECgQIBgABNQAECgcICwABAAAAAA==.Armorya:BAABNQAECoEnAAIJAAkKVxrXUgB0AgAJAAkKVxrXUgB0AgAAAA==.Armyofone:BAAANQAECgQIBwAAAA==.Artaius:BAABNQAECoEZAAIKAAcKYCV8BgD5AgAKAAcKYCV8BgD5AgAAAA==.Arthonius:BAAANQADCgQIBAAAAA==.Arthuun:BAAANQAECggIEAAAAA==.Artom:BAAANQADCgUJBQAAAA==.',
As='Ashaw:BAAANQADCgYIBgAAAA==.Astariel:BAAANQADCggICAABNQAECgcIEAABAAAAAA==.Astarog:BAAANQAECgUIDwAAAA==.',
At='Atafloosy:BAEANQAECgUIDwAAAA==.Athelf:BAAANQAECggIEwAAAA==.Attina:BAAANQABCgEIAQAAAA==.',
Au='Aubriell:BAAANQAECgQIBwAAAA==.',
Ay='Ayrnerdam:BAAANQAECgUICQAAAA==.',
Ba='Babelfish:BAABNQAECoEZAAILAAgK2hb1GAADAgALAAgK2hb1GAADAgAAAA==.Bagleflinger:BAAANQAECgQICAAAAA==.Baldr:BAAANQAECgQJBgAAAA==.Batarang:BAABNQAECoEbAAIMAAcKFwloJQCGAQAMAAcKFwloJQCGAQAAAA==.',
Be='Bealzulbub:BAAANQABCgQIBwAAAA==.Bearbarian:BAABNQAECoEiAAIKAAgKlgt0HwBbAQAKAAgKlgt0HwBbAQAAAA==.Beastkael:BAAANQAECgMIAwAAAA==.Beg:BAABNQAECoEfAAINAAgKfxEEXwDTAQANAAgKfxEEXwDTAQAAAA==.Belfalas:BAAANQABCgQICAAAAA==.Beliir:BAAANQADCggICAABNQAECgcIHQALAGEdAA==.Berghain:BAAANQADCgQJAgAAAA==.Berick:BAAANQAECgEIAgAAAA==.Betzalel:BAABNQAECoEVAAINAAcK+BQMXgDWAQANAAcK+BQMXgDWAQAAAA==.Beytryx:BAAANQAECgIJAwAAAA==.',
Bi='Bittycakes:BAAANQADCgUIBQAAAA==.',
Bl='Bladeoftruth:BAABNQAECoEYAAIOAAkKUB6GFgDiAgAOAAkKUB6GFgDiAgAAAA==.Blaize:BAAANQADCgYICQAAAA==.Blitzwing:BAAANQAECgQIBQAAAA==.Bloodyaggro:BAAANQAECgQIBwAAAA==.',
Bo='Bobapstab:BAAANQADCgEIAQAAAA==.Bonnabelle:BAABNQAECoEkAAINAAkKkQbAaQCsAQANAAkKkQbAaQCsAQAAAA==.Boombawks:BAAANQAECgEIAQAAAA==.Bor:BAAANQAECgEIAQABNQAECggIGQAKAGAlAA==.Bos:BAAANQAECgUICwAAAA==.Bowtoahh:BAAANQABCgEIAQABNQAECgYIEgABAAAAAA==.',
Br='Brewnelle:BAAANQADCggIDgABNQAECggIGgAPAHgZAA==.Briest:BAAANQAECgQIBAABNQAECggIGgAPAHgZAA==.Brownbar:BAAANQAECgMIAwAAAA==.Bruid:BAABNQAECoEaAAMPAAgKeBnqIAD1AQAPAAcKzBfqIAD1AQAQAAcKaBPiRQCrAQAAAA==.Bruneigin:BAAANQAECgIIAgAAAA==.',
Ca='Cailey:BAAANQAECgIIAwAAAA==.Calzone:BAAANQADCgYIBgAAAA==.Cambria:BAAANQADCgEIAQABNQAECgIIAwABAAAAAA==.Cantliquor:BAAANQABCgQIBAAAAA==.Cardian:BAAANQADCgcIEwAAAA==.Caridin:BAAANQADCgYIEgAAAA==.Carmey:BAAANQAECgMIAwABNQAECgQIBAABAAAAAA==.Carrin:BAABNQAECoE4AAIJAAgK5SBINQDXAgAJAAgK5SBINQDXAgAAAA==.Catalyia:BAABNQAECoEhAAIRAAgK7xXTTgBbAgARAAgK7xXTTgBbAgAAAA==.Catris:BAAANQAECgIIAgAAAA==.Catset:BAABNQAECoEYAAIQAAgKvAbXUgBkAQAQAAgKvAbXUgBkAQAAAA==.',
Ce='Cecea:BAAANQABCggIFwAAAA==.',
Ch='Charades:BAAANQADCgYIDAAAAA==.Charlton:BAAANQAECgQIBwABNQAECggIEQABAAAAAA==.Chazzo:BAABNQAECoEYAAISAAkKkBOXaQA0AgASAAkKkBOXaQA0AgAAAA==.Chazzy:BAAANQADCgcIBwAAAA==.Chila:BAAANQAECgUIBwAAAA==.',
Co='Commy:BAABNQAECoEZAAMHAAgKrA5IswD6AQAHAAgKrA5IswD6AQAGAAEKng2MOwA+AAAAAA==.Concorde:BAAANQAECgQJCAAAAA==.Copiousconns:BAABNQAECoEdAAITAAcKTwkHJQBBAQATAAcKTwkHJQBBAQAAAA==.Corlock:BAAANQADCgYIDAAAAA==.',
Cr='Craitos:BAAANQABCgYIDQAAAA==.Cranjis:BAAANQAECgYIBgAAAA==.Crimsonfury:BAAANQAECgUIBgAAAA==.',
Cu='Cubos:BAABNQAECoElAAIUAAkKTSX5AQDUAwAUAAkKTSX5AQDUAwAAAA==.Cutlash:BAAANQAECgIIAgAAAA==.Cutslash:BAAANQADCgUJBQABNQAECgIIAgABAAAAAA==.',
Cy='Cynaea:BAAANQADCgQJBAABNQAECggIEQABAAAAAA==.',
Da='Daemona:BAABNQAECoEaAAIVAAgKmBJkLgAEAgAVAAgKmBJkLgAEAgAAAA==.Daieniceis:BAAANQAECgQIDAAAAA==.Dalkurn:BAACNQAFFIEQAAIPAAUKbiLQAgAAAgAPAAUKbiLQAgAAAgA1AAQKgSUAAg8ACQrrIygGAE4DAA8ACQrrIygGAE4DAAAA.',
De='Decayy:BAACNQAFFIELAAIOAAUK+hfZCgB8AQAOAAUK+hfZCgB8AQA1AAQKgSMAAg4ACQrIIikRABADAA4ACQrIIikRABADAAAA.Deceptakahn:BAABNQAECoEbAAIKAAcK9AQHLADwAAAKAAcK9AQHLADwAAAAAA==.Derailedbeef:BAABNQAECoEoAAMSAAkKqhmDPgC3AgASAAkKmxeDPgC3AgAWAAQKexnwEwA5AQAAAA==.Deydoralia:BAABNQAECoEtAAIIAAkKMSFHCwBgAwAIAAkKMSFHCwBgAwAAAA==.',
Di='Diabeetus:BAAANQADCgQICAAAAA==.',
Dn='Dnme:BAABNQAECoEbAAIXAAgKAg2jKADfAQAXAAgKAg2jKADfAQAAAA==.',
Do='Doieha:BAAANQADCggICAABNQAECgYICgABAAAAAA==.Doneldus:BAAANQAECgIIAgAAAA==.Dool:BAAANQAECgIIAwAAAA==.Dorfdragon:BAABNQAECoEXAAIYAAcK2ghmHgBPAQAYAAcK2ghmHgBPAQAAAA==.Dorfe:BAABNQAECoEmAAIZAAgKXRUcJAA6AgAZAAgKXRUcJAA6AgAAAA==.Dorflock:BAAANQADCggICAAAAA==.',
Dr='Drakona:BAAANQABCgQICAAAAA==.Drakthur:BAAANQADCgYIEgAAAA==.Draximus:BAAANQADCgUIBQAAAA==.Drewgarymore:BAABNQAECoEeAAMKAAgKQhReFwC1AQAQAAgK+g77PwDQAQAKAAcK0hVeFwC1AQAAAA==.Drough:BAAANQAECgQIBAABNQAECgcIFgAaALISAA==.',
Du='Dukker:BAAANQABCgIIAgAAAA==.Durandall:BAACNQAFFIELAAIJAAYKyQ6UBQDbAQAJAAYKyQ6UBQDbAQA1AAQKgSAAAgkACQqsGlhiAEYCAAkACQqsGlhiAEYCAAAA.Durleap:BAAANQAECgQIBwAAAA==.Durthmaul:BAAANQAECgUICQAAAA==.',
Dw='Dwarflock:BAABNQAECoEZAAIUAAgKHxWIUwA6AgAUAAgKHxWIUwA6AgAAAA==.',
Dy='Dylpickl:BAAANQAFFAIIAgAAAA==.Dylán:BAAANQAECgQIBAAAAA==.Dymàs:BAAANQAECgUIDAAAAA==.',
Ef='Eft:BAAANQABCgQIBAAAAA==.',
El='Elliemae:BAAANQAECgEIAQAAAA==.Elow:BAAANQADCgIIAgAAAA==.',
Er='Erazminash:BAAANQAECgMJBAAAAA==.',
Es='Esdeáth:BAAANQADCgIIAgAAAA==.Esmae:BAAANQAECgQIBwAAAA==.Ess:BAAANQAECgIIAgAAAA==.',
Ev='Evalina:BAAANQADCgQIBAABNQAECgQICAABAAAAAA==.Evvie:BAAANQAECgUIBwAAAA==.',
Ex='Executiepie:BAAANQADCggICAAAAA==.',
Fa='Fabulosoo:BAABNQAECoEdAAIJAAcKgxyBYgBGAgAJAAcKgxyBYgBGAgAAAA==.Falcondor:BAAANQADCgMIAwAAAA==.Fallin:BAAANQAECgUIBQAAAA==.Fantarius:BAACNQAFFIEHAAINAAMK4hJZFwABAQANAAMK4hJZFwABAQA1AAQKgSgAAw0ACQrNIdwfANUCAA0ACQrNIdwfANUCABsAAQqIBeEqACgAAAAA.Fantazee:BAAANQADCgUIBQABNQAFFAMIBwANAOISAA==.Fatdono:BAAANQAECgYIEQAAAA==.',
Fi='Fibbs:BAAANQAECgYIEAAAAA==.Fikti:BAABNQAECoEkAAMcAAgKoRvzAwCMAgAcAAgKaRvzAwCMAgAUAAQKsBZCugApAQAAAA==.Firetongue:BAAANQADCgUIBQAAAA==.Firocios:BAAANQAECgUIEgAAAA==.',
Fl='Flaminia:BAAANQADCgUICQAAAA==.',
Fo='Fossilz:BAAANQADCggJCAAAAA==.Foxybeans:BAAANQADCgYICgAAAA==.',
Fr='Fran:BAAANQAECgYIEwAAAA==.Frieda:BAAANQABCgIIAgAAAA==.Frink:BAAANQAECgEIAQAAAA==.Frostyfella:BAACNQAFFIEJAAIHAAUKaxsAEQDHAQAHAAUKaxsAEQDHAQA1AAQKgSQAAgcACQqlH2I7AAIDAAcACQqlH2I7AAIDAAE1AAEKAggCAAEAAAAA.',
Fu='Furman:BAAANQADCgMIAwAAAA==.Fuzzycakes:BAAANQADCggICAAAAA==.',
['Fá']='Fáith:BAAANQAECgQIBAAAAA==.',
Ga='Garypotter:BAABNQAECoEdAAIXAAgKcR2vEQDLAgAXAAgKcR2vEQDLAgAAAA==.Gazooks:BAAANQADCgYIDQAAAA==.',
Ge='Gelantria:BAAANQADCgcIBwAAAA==.',
Gi='Gillacs:BAAANQADCgMJAwAAAA==.',
Gl='Gleave:BAABNQAECoEhAAIRAAgKJiFQJQDjAgARAAgKJiFQJQDjAgAAAA==.Glâdiátor:BAAANQADCgMIAwAAAA==.',
Go='Goodbrew:BAAANQAECgUIDQAAAA==.',
Gr='Greystoke:BAAANQADCgQIBAAAAA==.Greyvee:BAAANQAECgIIBAAAAA==.Grindelbald:BAABNQAECoEaAAMHAAkKSBUGewBxAgAHAAkKSBUGewBxAgAdAAIKDwsyCAByAAAAAA==.',
Gt='Gtfofupá:BAAANQAECgIIAwAAAA==.',
Gu='Gushee:BAABNQAECoEVAAIWAAUK5hvyDwCEAQAWAAUK5hvyDwCEAQAAAA==.',
Gw='Gwenn:BAAANQADCgYIEgAAAA==.',
Gy='Gyes:BAAANQAECgIIAgAAAA==.',
Ha='Hadez:BAAANQADCgcICwAAAA==.Hae:BAAANQADCgEIAQAAAA==.Haegan:BAAANQABCgYIBwAAAA==.Hagioszoe:BAAANQAECgUIDAAAAA==.Hairypoóter:BAAANQADCgUICQAAAA==.Hanamari:BAACNQAFFIENAAIeAAUK7QdDBwBFAQAeAAUK7QdDBwBFAQA1AAQKgRwAAx4ACQooFpYfAAYCAB4ACQooFpYfAAYCAB8AAQrrAdVNAB0AAAAA.Hanoe:BAAANQADCggICAAAAA==.Harakrron:BAAANQAECgEIAQAAAA==.Harleyquìnn:BAAANQAECgEIAQAAAA==.Harydresden:BAAANQAECgUIDgAAAA==.Hawkesmage:BAAANQAECgIIAgAAAA==.Hawkslayer:BAAANQAECgIIAgAAAA==.Hazule:BAAANQAECgIIAwABNQAECggIGQADAGwXAA==.',
He='Hedgelord:BAABNQAECoEgAAIQAAgKLx+uIgCbAgAQAAgKLx+uIgCbAgAAAA==.',
Hi='Hisky:BAAANQAECgQIBgAAAA==.',
Ho='Hobe:BAABNQAECoEYAAIUAAcKZx8ESgBXAgAUAAcKZx8ESgBXAgAAAA==.Holytruck:BAAANQADCgEIAQAAAA==.Hoodmagik:BAAANQABCgYIBwABNQAECgkJHQAUADUVAA==.Hornadus:BAAANQADCgMIAwAAAA==.Hornride:BAAANQADCgMIAwAAAA==.',
Hu='Humoresque:BAAANQAECgIIAgAAAA==.Huntaredead:BAAANQAECgQIBgABNQAECgkJIgAUAEMhAA==.',
Ic='Icyblades:BAABNQAECoEWAAIaAAgK+gi1XwBqAQAaAAgK+gi1XwBqAQAAAA==.',
Il='Ilidania:BAAANQAECgEIAQABNQAECgQICAABAAAAAA==.Ilyna:BAABNQAECoEZAAIUAAcK3wddoABmAQAUAAcK3wddoABmAQAAAA==.',
Im='Immortalnut:BAAANQAECgYIEAAAAA==.',
In='Inori:BAAANQADCgcIBwAAAA==.Interrupted:BAAANQAECgIIAgAAAA==.',
It='Itscell:BAAANQADCgEIAQAAAA==.Ittyycakes:BAAANQADCgcIBwAAAA==.',
Ja='Jackypan:BAAANQADCgUIBQAAAA==.Jaedis:BAAANQAECgUICQAAAA==.Jaktar:BAAANQAECgcIDwAAAA==.Jane:BAAANQADCgMIAgAAAA==.Janet:BAABNQAECoEYAAIgAAgK6A9SFgCXAQAgAAgK6A9SFgCXAQAAAA==.Jani:BAAANQADCgQIBAABNQAECggIGAAgAOgPAA==.Janiina:BAAANQADCgYIDQAAAA==.',
Je='Jezak:BAAANQADCgIIAgABNQAECgQJBgABAAAAAA==.',
Jo='Jol:BAAANQABCgQIBAAAAA==.Jone:BAAANQAECgQIBwAAAA==.Joobs:BAAANQAECgcIEAAAAA==.Joosh:BAAANQAECgUIBQAAAA==.',
Js='Jslice:BAACNQAFFIEKAAISAAQKKBNZFABJAQASAAQKKBNZFABJAQA1AAQKgRsAAhIACQqnH7JBAKwCABIACQqnH7JBAKwCAAAA.',
Ju='Juda:BAAANQAECgUICAAAAA==.Jurant:BAAANQABCgQJAwAAAA==.Jurucil:BAAANQAECgEIAQAAAA==.',
Ka='Kaelys:BAAANQAECgQIDwAAAA==.Kahliea:BAAANQAECgIIAgAAAA==.Kaidance:BAAANQAECgEIAgAAAA==.Kaisaze:BAAANQAECgcIBwAAAA==.Kapachka:BAAANQAECgQIBgAAAA==.Karbide:BAAANQAECgIIAgAAAA==.Kardisa:BAAANQABCgIIAgAAAA==.Kateri:BAAANQAECgEIAQAAAA==.Katmarie:BAAANQAECgIIAgAAAA==.Kazothor:BAAANQAECgIIAgAAAA==.',
Ke='Keria:BAACNQAFFIETAAIVAAcKXx81AQCfAgAVAAcKXx81AQCfAgA1AAQKgTgAAhUACQruJcIBANYDABUACQruJcIBANYDAAAA.Keyz:BAAANQAECgYICwAAAA==.',
Ki='Kiretsu:BAABNQAECoEZAAMGAAkK2hIlFABBAQAHAAgKew3WzQDFAQAGAAUKghQlFABBAQAAAA==.',
Ko='Kovus:BAAANQAECgUIBwAAAA==.',
Kr='Kragami:BAAANQAECgQIBwAAAA==.Krelien:BAAANQAECgUICgAAAA==.Krispee:BAAANQAECgcIEQAAAA==.Kristanya:BAABNQAECoEeAAIhAAgKpQagJgBiAQAhAAgKpQagJgBiAQAAAA==.',
Ks='Ks:BAAANQADCgMIAwAAAA==.',
Ku='Kulaidmage:BAABNQAECoEbAAIHAAgKORXglwAzAgAHAAgKORXglwAzAgAAAA==.Kurtcowbain:BAAANQAECgYIEgAAAA==.Kushies:BAAANQADCgUIBQAAAA==.',
Ky='Kynetik:BAAANQAECggICAABNQAFFAQICwAFALUDAA==.Kyttin:BAAANQADCggICAAAAA==.',
La='Ladamirea:BAABNQAECoEnAAIiAAgK4yOdAgA0AwAiAAgK4yOdAgA0AwAAAA==.Lamashtu:BAABNQAECoEZAAIjAAcKfhQIJwDLAQAjAAcKfhQIJwDLAQAAAA==.Lashar:BAAANQADCgYIBgAAAA==.Layssar:BAAANQADCgUICgAAAA==.',
Le='Leddy:BAAANQAECgcIBwAAAA==.Leiman:BAAANQABCgQIBQAAAA==.Lenabug:BAAANQABCgIIAgAAAA==.Lexiê:BAAANQAECgYIEwAAAA==.',
Li='Lightninjack:BAAANQAECgEIAQAAAA==.Lightsworn:BAAANQADCgEIAQAAAA==.Lilifa:BAABNQAECoEYAAIfAAcKHCBuDQCIAgAfAAcKHCBuDQCIAgAAAA==.Lilillidari:BAABNQAECoEeAAIVAAkKChwdFwDCAgAVAAkKChwdFwDCAgABNQAFFAYIEQAaAEEWAA==.Lillirann:BAAANQAECgEIAQAAAA==.Lilmontaro:BAACNQAFFIERAAQaAAYKQRZSCQBZAQAaAAQKdhpSCQBZAQAkAAMK5xb1CQD4AAAOAAEK3wgPMgAjAAA1AAQKgTMAAyQACQoyJsEJADsDACQACQpdI8EJADsDABoACAqpIdQcAMICAAAA.Lilunholy:BAAANQAECgcIEgABNQAFFAYIEQAaAEEWAA==.Linali:BAAANQAECgIIAgAAAA==.Lirianna:BAAANQADCgMIAwAAAA==.Lisey:BAAANQAECgEIAgAAAA==.Lisyao:BAAANQAECgQIBAAAAA==.Littany:BAABNQAECoEZAAMIAAkKSAp+WwDjAQAIAAkKSAp+WwDjAQAJAAcK8xALqQCVAQAAAA==.Livane:BAAANQAECgMIBQAAAA==.',
Lo='Loestus:BAAANQADCgQIBAAAAA==.Looneytoones:BAAANQAECgUIBQAAAA==.Lowground:BAAANQAECgEIAQAAAA==.',
Lu='Lucïna:BAABNQAECoEYAAIVAAcKjwyaQACCAQAVAAcKjwyaQACCAQAAAA==.Ludk:BAABNQAECoEeAAIOAAgKyyElEwD+AgAOAAgKyyElEwD+AgAAAA==.Luk:BAABNQAECoErAAMXAAgKMxTiJAAAAgAXAAgKVxLiJAAAAgAiAAUKzhN6FQAiAQABNQAECgYIDQABAAAAAA==.Lumiela:BAAANQAECgQIBwAAAA==.Luminah:BAAANQAECgIJAgAAAA==.Lunacy:BAAANQADCgYICgAAAA==.Luni:BAAANQAECgEIAQAAAA==.Lunì:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Luxshot:BAAANQADCggIDwAAAA==.',
['Ló']='Lóner:BAABNQAECoEdAAIZAAgKDhAEKwAKAgAZAAgKDhAEKwAKAgAAAA==.',
['Lü']='Lüni:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Ma='Macbayne:BAAANQADCgEIAQAAAA==.Maebe:BAAANQAECgQIBQAAAA==.Mageblaster:BAAANQADCgYICgAAAA==.Maggnut:BAABNQAECoEeAAISAAgKexDFggDwAQASAAgKexDFggDwAQAAAA==.Magicg:BAABNQAECoEcAAMjAAkKhBzwEQDBAgAjAAkKhBzwEQDBAgANAAEKpgr63QA8AAAAAA==.Magordito:BAABNQAECoEbAAIHAAgKygh91wCyAQAHAAgKygh91wCyAQABNQAECggIHQAZAA4QAA==.Mairek:BAABNQAECoEuAAIHAAkKbh59OgAEAwAHAAkKbh59OgAEAwAAAA==.Maleigoron:BAABNQAECoEaAAIUAAkK4AlfdwDSAQAUAAkK4AlfdwDSAQAAAA==.Malkuri:BAABNQAECoEeAAMRAAgK7hXwZwAZAgARAAcKlhfwZwAZAgAlAAcKkgwENQB6AQAAAA==.Malorysera:BAACNQAFFIEGAAIYAAIK7SEFCQDAAAAYAAIK7SEFCQDAAAA1AAQKgSAABBgACQpGHzEHAPoCABgACQpMHTEHAPoCACEABgpZF4shAKIBACYAAwoNHboQAP8AAAAA.Matsuma:BAAANQAECgEIAQAAAA==.',
Mc='Mcbasketball:BAAANQAECgIIAgAAAA==.',
Me='Mechaljaxon:BAAANQAECgUIDQAAAA==.Menirva:BAAANQAECgcIEQABNQAECggIHgARAO4VAA==.Merv:BAAANQAECgUIBgAAAA==.Metapal:BAAANQAECggIEgABNQAFFAQICwAFALUDAA==.Metasham:BAACNQAFFIELAAIFAAQKtQNpEwAAAQAFAAQKtQNpEwAAAQA1AAQKgSYAAgUACQq5F6s2AHYCAAUACQq5F6s2AHYCAAAA.',
Mi='Miiaa:BAAANQAECgcIEAAAAA==.Mijoy:BAAANQAECgQIBAAAAA==.Milane:BAAANQADCgcIGwAAAA==.',
Mo='Moirasha:BAAANQAECgQICwAAAA==.Monran:BAAANQAECgUICgAAAA==.Moonwood:BAAANQADCgYIBgAAAA==.Moosand:BAAANQAECgQJBgAAAA==.Morphingtime:BAAANQAECgYIEAAAAA==.Mortivus:BAAANQAECgUIBwAAAA==.',
Mu='Mudsworn:BAAANQADCggIBwAAAA==.Muggs:BAAANQADCggJCAAAAA==.Mulvane:BAAANQAECgUIBwAAAA==.Mustachio:BAAANQAECgUIDwAAAA==.',
Mw='Mwc:BAACNQAFFIEMAAMMAAYKzhaVBQC0AQAMAAUK3hOVBQC0AQAZAAIK6Rd4EACiAAA1AAQKgRYAAwwACQoFJWgEAEYDAAwACQoFJWgEAEYDABkABAp3FitXAA0BAAAA.',
Mz='Mziao:BAAANQADCggIFQAAAA==.',
Na='Nashia:BAAANQADCgMIAwAAAA==.Nazureshal:BAAANQADCggICAABNQAECgUIDQABAAAAAA==.',
Ne='Neall:BAAANQAECgUIDAAAAA==.Ner:BAAANQADCgEIAQAAAA==.Nethryx:BAAANQADCgMIAwAAAA==.Nevets:BAAANQAECgUIDQAAAA==.',
Ni='Nightbird:BAAANQADCggIEgAAAA==.Nightheals:BAAANQADCgYIBgABNQAECgcIGgADAFgZAA==.',
No='Nonna:BAABNQAECoEeAAIFAAgK9Af7fgB3AQAFAAgK9Af7fgB3AQAAAA==.Noslrac:BAAANQAECgUIBwAAAA==.Notamonk:BAAANQABCggICgAAAA==.Notbysight:BAAANQADCgYIBgAAAA==.Notorious:BAAANQAECggIKwAAAQ==.',
Ny='Nyxjr:BAAANQADCgIJAgAAAA==.',
Ob='Oblast:BAABNQAECoE1AAIHAAkKsySyBwC6AwAHAAkKsySyBwC6AwAAAA==.',
Od='Odb:BAAANQADCgQIBAAAAA==.Odirtyblasta:BAAANQADCgYIBgAAAA==.',
Ol='Olmanjankins:BAAANQAECgYIDgAAAA==.',
On='Onlydks:BAAANQAECggIEwABNQAFFAQICQAWANoLAA==.Onlyslams:BAACNQAFFIEJAAMWAAQK2gsDAQA2AQAWAAQK2gsDAQA2AQASAAIKggXSLwBdAAA1AAQKgRgAAxYACApHHc0KAPYBABYABQqdIs0KAPYBABIABwrKF4qTAMMBAAAA.',
Oo='Ooze:BAAANQADCgMIAwAAAA==.',
Or='Orter:BAAANQAECgUIDgAAAA==.',
Ot='Ottan:BAAANQADCgYICwAAAA==.',
Ov='Overkill:BAAANQAECgMIAwAAAA==.Ovo:BAAANQADCgMIAwAAAA==.',
Pa='Pandorasfox:BAAANQADCgcICAAAAA==.Papsfear:BAAANQAECgYIEgAAAA==.Parceh:BAABNQAECoEfAAMDAAgKzCDNLwB9AgADAAcK8B/NLwB9AgAFAAYKySIJPwBPAgAAAA==.',
Ph='Phydaux:BAAANQAECgIIAgAAAA==.',
Pi='Pinkponyclub:BAAANQADCggICAAAAA==.Pizzaman:BAAANQAECgQIBwAAAA==.',
Pr='Pringle:BAAANQADCgYIEgABNQAECgQIBQABAAAAAA==.Prosciutto:BAAANQAECgUIEAAAAA==.Proxima:BAAANQAECgEIAQAAAA==.',
Pt='Ptoughneigh:BAAANQAECgQIBAAAAA==.',
Pu='Puckish:BAACNQAFFIEKAAINAAQK7wNgFQAcAQANAAQK7wNgFQAcAQA1AAQKgSMAAw0ACQp3Db5gAM0BAA0ACQp3Db5gAM0BABsAAQq8ARUsACQAAAAA.Punn:BAAANQAECgcIDAABNQAECgkJIgAUAEMhAA==.Punnisher:BAABNQAECoEiAAMUAAkKQyGdEQA1AwAUAAkKQyGdEQA1AwATAAEKvhvFZwBFAAAAAA==.Pureflow:BAAANQAECgYIDAAAAA==.',
['Pä']='Päiñ:BAAANQADCgUIBQAAAA==.',
Qu='Quackers:BAAANQAECgUIDQAAAA==.Quicks:BAABNQAECoEhAAIJAAkKYxruRwCXAgAJAAkKYxruRwCXAgAAAA==.',
Ra='Radünz:BAAANQABCgQIBwABNQAECggIHwACAE8dAA==.Raelianna:BAAANQAECgQICAABNQAECggILQAHAHslAA==.Raewyna:BAAANQAECgUICgAAAA==.Rahruhai:BAAANQAECgYIBgABNQAECgYICgABAAAAAA==.Rain:BAAANQAECgMIAwAAAA==.Raine:BAAANQAFFAIIAgAAAA==.Rainingblood:BAAANQAECgUIEAAAAA==.Rainjar:BAAANQAECgYIDQAAAA==.Rancîd:BAABNQAECoEWAAMaAAcKshLSUQCjAQAaAAcKshLSUQCjAQAkAAMKYAazeAB8AAAAAA==.Ranron:BAAANQAECgcIDgABNQAECgcIFgAaALISAA==.Raphael:BAABNQAECoEXAAMOAAcKGRldUgCJAQAOAAUKgxtdUgCJAQAaAAYKmw/uawA+AQAAAA==.Rasik:BAABNQAECoEeAAISAAgKgRvETACJAgASAAgKgRvETACJAgAAAA==.Ravenblood:BAAANQAECgQIBAAAAA==.Rayel:BAAANQAECgUICgAAAA==.Raylyn:BAAANQADCgYICwAAAA==.',
Rh='Rhadamancus:BAAANQAECgIIAwAAAA==.Rhani:BAAANQAECgQIBQAAAA==.Rheanon:BAAANQADCgcIFwAAAA==.Rhome:BAABNQAECoEjAAINAAgKNSMZEwAeAwANAAgKNSMZEwAeAwAAAA==.Rhox:BAAANQADCggJEQAAAA==.',
Ri='Rialu:BAABNQAECoEfAAINAAgKEBIGXQDaAQANAAgKEBIGXQDaAQAAAA==.Ribald:BAAANQAECgUICQAAAA==.Rickgrimes:BAABNQAECoErAAMkAAgKPiSNDgACAwAkAAgKrSCNDgACAwAaAAcK/yHNOQAXAgAAAA==.',
Ro='Roid:BAABNQAECoEgAAMIAAkKLw7KTwAMAgAIAAkKLw7KTwAMAgAJAAIKawIJZAFAAAAAAA==.Rotcorpse:BAAANQAECggIDAAAAA==.',
Ru='Ruddam:BAAANQAECgQIBwAAAA==.',
['Rä']='Räveñz:BAABNQAECoEYAAIKAAcKFhHCHQBsAQAKAAcKFhHCHQBsAQAAAA==.',
Sa='Saintabes:BAACNQAFFIEJAAINAAUKvBitCgC3AQANAAUKvBitCgC3AQA1AAQKgRoAAg0ACQq/H180AHUCAA0ACQq/H180AHUCAAAA.Sakurah:BAAANQAECgUIDwAAAA==.Samelan:BAAANQABCggIFwAAAA==.Sandara:BAAANQADCgMIAwAAAA==.Sanicor:BAAANQAECgQIBAAAAA==.Sanrinn:BAAANQAECgcIDgAAAA==.Sappy:BAAANQAECgEIAQAAAA==.Sarahboom:BAACNQAFFIENAAIHAAUKfQcpHQBeAQAHAAUKfQcpHQBeAQA1AAQKgSAAAgcACQq3EaeMAEsCAAcACQq3EaeMAEsCAAAA.Sarahjupiter:BAAANQAECgUICQABNQAFFAUIDQAHAH0HAA==.Sargarach:BAAANQADCgEIAQAAAA==.',
Sc='Scapegoat:BAEANQAECgcIGQAAAQ==.Scraime:BAAANQAECgIIAgAAAA==.',
Se='Seekýefirst:BAAANQADCgcIBwAAAA==.Seethe:BAAANQADCgYIBgAAAA==.Seilah:BAAANQAECgYIEAAAAA==.Seliah:BAAANQAECgUIDQAAAA==.Senuya:BAAANQADCgQIBAABNQAECgYIEgABAAAAAA==.Seräph:BAAANQAECgQIBQAAAA==.',
Sh='Shadowglade:BAABNQAECoEeAAIQAAgKiRZBLwBBAgAQAAgKiRZBLwBBAgAAAA==.Shadowmourne:BAAANQABCgIIAgAAAA==.Shalltear:BAAANQAECgIIAgAAAA==.Shamizzle:BAAANQAECgYIEAAAAA==.Shammydavis:BAAANQAECgUIEgAAAA==.Shaølinstørm:BAAANQADCgMIAwAAAA==.Shiftybud:BAAANQADCgQICwAAAA==.Shinobi:BAAANQAECgEIAQAAAA==.Shocknorris:BAAANQADCgUIBQAAAA==.Shrapnel:BAAANQAECgUIEgAAAA==.Shàmwôw:BAAANQADCgYIBAAAAA==.Shàytan:BAABNQAECoEZAAIVAAcKFww3QQB/AQAVAAcKFww3QQB/AQAAAA==.',
Si='Sinistral:BAAANQAECgIIAgAAAA==.',
Sl='Slise:BAAANQADCgIIAwAAAA==.',
Sm='Smithers:BAABNQAECoETAAQUAAgKIx2ggwCwAQAUAAUKVR6ggwCwAQATAAIKDR4IQgCxAAAcAAEKVhXmIwBKAAAAAA==.',
Sn='Snappycakes:BAAANQAECgEIAQAAAA==.Sneakybunny:BAABNQAECoEeAAInAAgKlQN/DwAYAQAnAAgKlQN/DwAYAQAAAA==.',
So='Solarica:BAAANQABCgIIAgAAAA==.Solómon:BAAANQAECgQIBQAAAA==.Sorabjr:BAAANQAECgIIAgAAAA==.Sorin:BAAANQADCgYIBgABNQAECgcICwABAAAAAA==.Soulbreaker:BAABNQAECoEdAAIXAAcKGhAALgCvAQAXAAcKGhAALgCvAQAAAA==.Southy:BAAANQAECgYIEgAAAA==.',
Sp='Sparxs:BAAANQADCgMIAwAAAA==.Spookz:BAAANQAECgEIAQAAAA==.',
St='Starblunder:BAAANQADCgUICgAAAA==.Storglen:BAAANQADCgUIBQAAAA==.Stormdeth:BAAANQADCgUICAAAAA==.Stormmystic:BAAANQAECgIIAgAAAA==.Stormwild:BAAANQADCgUJBQABNQAECgIIAgABAAAAAA==.Stylemonk:BAACNQAFFIEUAAIeAAYK5yNgAQCAAgAeAAYK5yNgAQCAAgA1AAQKgSMAAh4ACQoII0cEAIQDAB4ACQoII0cEAIQDAAAA.',
Su='Sulfalloway:BAAANQAECgUIBgAAAA==.Sumawfulot:BAABNQAECoEZAAISAAgK1BmDUAB9AgASAAgK1BmDUAB9AgAAAA==.Sunsparrow:BAAANQAECgQIAgAAAA==.',
Sw='Swankdave:BAAANQADCgcIBwAAAA==.Swiftysarah:BAAANQADCggICAABNQAFFAUIDQAHAH0HAA==.',
Sy='Syraelia:BAAANQADCggICAAAAA==.Syvarris:BAABNQAECoEiAAQoAAgKGR7qAwCVAgAoAAcKsx/qAwCVAgAlAAUKXwkqRgD2AAARAAEK4xJUKQFNAAAAAA==.',
Ta='Taeveren:BAAANQADCgYICAAAAA==.Tamesßond:BAAANQAECgQIBwAAAA==.Tandaiff:BAAANQADCgYIBgAAAA==.Tanguo:BAAANQADCgcIDgAAAA==.Tanksnotanks:BAAANQADCgYJFAAAAA==.Tanleron:BAAANQADCgMIAwAAAA==.Tarayn:BAABNQAECoEdAAILAAcKYR3FEwBDAgALAAcKYR3FEwBDAgAAAA==.',
Te='Teagan:BAAANQADCgcIEwAAAA==.Tenac:BAAANQADCggIDgAAAA==.Teoritta:BAEBNQAECoEdAAMlAAcKZAzhNgBrAQAlAAcKZAzhNgBrAQAoAAEKBgx+EQAzAAAAAA==.Terllin:BAAANQADCgQIBAAAAA==.',
Th='Thalimus:BAAANQADCgYICgAAAA==.Thelle:BAAANQAECgYICwABNQAFFAcIEwAVAF8fAA==.Thewhitelion:BAAANQAECgQIBQAAAA==.',
Ti='Tigg:BAACNQAFFIENAAMkAAUKHhH6BAB+AQAkAAUKHhH6BAB+AQAOAAEKBAN9NgAYAAA1AAQKgSQAAyQACQogIesVALkCACQACQq6IOsVALkCABoAAQpIIyLFAD4AAAAA.Tikifiki:BAAANQAECgYIEAAAAA==.',
To='Tokin:BAAANQADCgYICgAAAA==.Toochill:BAAANQADCgEIAQAAAA==.Toodoo:BAAANQADCgIIAgABNQAECgcIFgAaALISAA==.Toshidot:BAACNQAFFIEPAAIUAAUKgRUWCwCQAQAUAAUKgRUWCwCQAQA1AAQKgSQAAhQACQoBIgEWAB0DABQACQoBIgEWAB0DAAAA.Totemtila:BAAANQAECgEIAwABNQAECgkJIAAUANUjAA==.Totendead:BAAANQABCgMIBQAAAA==.',
Tr='Translucent:BAABNQAECoEhAAIDAAcKsxDydAB9AQADAAcKsxDydAB9AQAAAA==.Trazatra:BAAANQAECggIEQAAAA==.Truckah:BAAANQAECgYIEgAAAA==.Tràvdog:BAAANQAECgYIDQAAAA==.',
Tu='Tunalongarms:BAAANQAECgQICAAAAA==.Tuonadari:BAAANQADCgUIDQAAAA==.Tuonai:BAAANQAECgUIEgAAAA==.Tusknus:BAAANQAECgIIAgAAAA==.Tustone:BAAANQADCgQIBAAAAA==.',
Ty='Tygore:BAAANQAECgEIAQABNQAECggIGQAKAGAlAA==.Tylordis:BAAANQADCgYICgAAAA==.',
['Tý']='Týr:BAAANQAECgIIAgAAAA==.',
Ul='Ultimatum:BAAANQAECgUIBQAAAA==.',
Us='Usodead:BAAANQADCgQIBAAAAA==.Usosquishy:BAAANQAECgcIEgAAAA==.',
Va='Vader:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.Valkuridk:BAACNQAFFIETAAMaAAUKgCQxAgAQAgAaAAUKuyIxAgAQAgAkAAUKdyJYAgDnAQA1AAQKgScAAyQACQqaJooCALIDACQACQqKJooCALIDABoACAoqJpYeALYCAAAA.Valorlight:BAAANQADCggICAAAAA==.Vandy:BAABNQAECoEgAAMNAAkK4xbWPABSAgANAAkKARXWPABSAgAbAAQKqRa5EAAFAQAAAA==.',
Ve='Vedo:BAABNQAECoEXAAIlAAkKFRzQFACiAgAlAAkKFRzQFACiAgAAAA==.Vedora:BAAANQAECgcIEAAAAA==.Velf:BAAANQADCgEIAQAAAA==.Veradis:BAAANQADCgYIEgAAAA==.Vestiege:BAAANQABCgYIBwAAAA==.',
Vi='Vinland:BAAANQADCgYIEgAAAA==.Vinsmokesanj:BAAANQADCgQIBAAAAA==.Virulent:BAAANQAECgEIAQABNQAECgUICwABAAAAAA==.',
Vl='Vladak:BAAANQAECgYIDQAAAA==.',
Vo='Voc:BAAANQAECgcIEQAAAA==.Voz:BAAANQAECgIIAgABNQAECgUICwABAAAAAA==.',
Vu='Vulkin:BAAANQAECgIIAwAAAA==.',
Vv='Vv:BAABNQAECoEfAAIRAAgKGiK9IgDvAgARAAgKGiK9IgDvAgAAAA==.',
Vy='Vyridiondk:BAAANQAECgIIAwAAAA==.Vyx:BAAANQAECgIIAgAAAA==.',
Wa='Waggi:BAAANQAECgQIBQAAAA==.Waymán:BAAANQADCggIIAAAAA==.',
We='Weebjones:BAAANQADCgQIBAAAAA==.Weelilcurse:BAAANQADCggICAAAAA==.Wegberto:BAAANQADCggICAAAAA==.',
Wu='Wumply:BAACNQAFFIEOAAIjAAUKJQ4aBwB+AQAjAAUKJQ4aBwB+AQA1AAQKgSAAAiMACQohEkgfABwCACMACQohEkgfABwCAAAA.',
['Wà']='Wàyman:BAAANQADCgUICwAAAA==.',
['Wä']='Wäyman:BAABNQAECoEeAAIEAAgKnxS8DwBUAgAEAAgKnxS8DwBUAgAAAA==.',
Xa='Xaranthia:BAAANQAECgcIDwAAAA==.',
Xm='Xmcdizzle:BAAANQAECgUIDgAAAA==.',
Xy='Xylarra:BAABNQAECoEeAAMVAAgKfBmPIwBYAgAVAAgKfBmPIwBYAgAXAAIK4BXHUwB6AAAAAA==.',
Ya='Yautja:BAABNQAECoEfAAIlAAcKFRU/KwDNAQAlAAcKFRU/KwDNAQAAAA==.Yazule:BAABNQAECoEZAAIDAAgKbBdtRwAZAgADAAgKbBdtRwAZAgAAAA==.',
Yo='Yodawg:BAAANQAECgYIEAABNQAECggIHAALAMYbAA==.Yoruba:BAAANQADCgMIAwABNQAECgUIDwABAAAAAA==.',
Yu='Yuenna:BAAANQADCggICAABNQAECgYICgABAAAAAA==.',
Za='Zairroth:BAAANQADCgYIBwAAAA==.Zamali:BAABNQAECoEaAAIOAAcKQwqaYwBCAQAOAAcKQwqaYwBCAQAAAA==.Zantris:BAAANQADCgUIBwABNQAECgQIBQABAAAAAA==.Zartella:BAAANQAECgUIBgABNQAECgYICwABAAAAAA==.Zaxon:BAAANQAECgIIAgAAAA==.',
Ze='Zendraza:BAAANQAECgUIDgAAAA==.Zephyrion:BAACNQAFFIEGAAIOAAIKRQxFHgB2AAAOAAIKRQxFHgB2AAA1AAQKgScAAg4ACQquGY0hAI8CAA4ACQquGY0hAI8CAAE1AAQKBggPAAEAAAAA.Zepplin:BAAANQAECgcIDwAAAA==.Zerenity:BAAANQAECgQIBgAAAA==.Zetro:BAABNQAECoEkAAILAAgK4QmSKwBUAQALAAgK4QmSKwBUAQAAAA==.',
Zr='Zreydyn:BAAANQADCgYIDgAAAA==.',
Zu='Zuma:BAABNQAECoEXAAIGAAgKrhWyCAAiAgAGAAgKrhWyCAAiAgAAAA==.Zuraxxus:BAAANQABCgMIAwAAAA==.',
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
