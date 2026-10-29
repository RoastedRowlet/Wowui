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

local lookup = {'Monk-Windwalker','Unknown-Unknown','DeathKnight-Frost','Paladin-Holy','Mage-Arcane','DeathKnight-Blood','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Priest-Holy','Warrior-Fury','DeathKnight-Unholy','Hunter-BeastMastery','DemonHunter-Devourer','Paladin-Protection','Rogue-Assassination','Shaman-Enhancement','Paladin-Retribution','Druid-Restoration','Druid-Balance','Warrior-Arms','Druid-Feral','Priest-Shadow','DemonHunter-Vengeance','DemonHunter-Havoc','Shaman-Restoration','Shaman-Elemental','Rogue-Subtlety','Mage-Frost','Evoker-Preservation','Evoker-Augmentation','Druid-Guardian',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abberleigh:BAAANQAECgQIBgAAAA==.Abron:BAAANQAECgIIAwAAAA==.',
Ad='Adahma:BAAANQADCgYIEQABNQAECgYIGwABACMGAA==.Adelerock:BAAANQAECgUIBwAAAA==.',
Ae='Aerostotle:BAAANQAECgcICwAAAA==.',
Ag='Aganoth:BAAANQAECgcJEwAAAA==.',
Ai='Aideon:BAAANQAECgEIAQABNQAECgQIDgACAAAAAA==.',
Al='Alaraa:BAAANQADCgUIBwABNQAECgkJJwADAOMTAA==.Algonq:BAAANQADCggIKQABNQAECgYIGwAEAFQDAA==.Alkamaz:BAABNQAECn8bAAIFAAkKxAvAmwANAQAFAAkKxAvAmwANAQAAAA==.Alkiris:BAAANQADCgEIAQABNQAECgQIBgACAAAAAA==.Alsisst:BAAANQAECgEIAQAAAA==.Alssar:BAAANQAECgIIAgAAAA==.Alstar:BAABNQAECn8hAAIGAAoKQBNkKwBGAQAGAAoKQBNkKwBGAQAAAA==.Alynis:BAAANQADCgQIBAAAAA==.',
Am='Amac:BAAANQADCgUIBQAAAA==.Amathus:BAABNQAECn9IAAQHAAoKdRIAAwAGAgAHAAoKdRIAAwAGAgAIAAYKRhCMwQBIAQAJAAIKwwukKAA4AAAAAA==.',
An='Andarial:BAAANQAECgUIBQAAAA==.Andreth:BAAANQAECgQICAAAAA==.Anoxyn:BAAANQAECgQIBAAAAA==.Anthe:BAAANQADCgUIFAAAAA==.',
Ar='Arcanmaggy:BAAANQAECgIIAwABNQAFFAQIBQAIAJsEAA==.Arcee:BAAANQADCgQIBgAAAA==.Ares:BAAANQAECgQIEgABNQADCgMJAwACAAAAAA==.Aryxi:BAAANQADCgUJBQABNQADCgMJAwACAAAAAA==.',
As='Asiägo:BAAANQABCgcJCgAAAA==.Assassynmike:BAAANQAECgEIAQAAAA==.',
At='Atlas:BAAANQAECgYIDwAAAA==.',
Ba='Baelhal:BAABNQAECn8zAAMGAAoKPxTlGQDGAQAGAAkKFBblGQDGAQADAAEKbQfakAAoAAAAAA==.',
Be='Bearden:BAAANQADCgMIAgAAAA==.Bearypotter:BAAANQADCgUIBQAAAA==.Benedin:BAAANQADCgcJDAABNQAECgoKKAAKAM0eAA==.',
Bi='Bigtex:BAABNQAECn8bAAILAAYK9AdcGgD/AAALAAYK9AdcGgD/AAAAAA==.Biped:BAABNQAECn8qAAIHAAgKwRU8CAAOAgAHAAgKwRU8CAAOAgAAAA==.Bishul:BAAANQAECgQIBwAAAA==.',
Bl='Blackdeath:BAABNQAECn8eAAIMAAoKUg5THgCCAQAMAAoKUg5THgCCAQAAAA==.Bloodsport:BAAANQADCgIIAgAAAA==.',
Bo='Bofadees:BAAANQADCggIFAAAAA==.Boloevo:BAAANQADCgUIBQABNQAECgYIEgACAAAAAA==.Bolopal:BAAANQAECgIIAgABNQAECgYIEgACAAAAAA==.Boolin:BAAANQADCgQIBAABNQAECgoKKAAJAIQgAA==.Boomstique:BAABNQAECn8bAAINAAYKnRLruQCQAQANAAYKnRLruQCQAQAAAA==.Boondocka:BAABNQAECn8oAAINAAkKzhbYUAB9AgANAAkKzhbYUAB9AgAAAA==.',
Br='Brex:BAAANQAECggIAQAAAA==.Brissennissa:BAABNQAECn8sAAIOAAkK5hzjEgDUAgAOAAkK5hzjEgDUAgAAAA==.Brokkr:BAAANQADCggIEwAAAA==.Bronar:BAAANQADCgMIAwAAAA==.Brutalís:BAABNQAECn8jAAINAAgKQA//YwB1AQANAAgKQA//YwB1AQAAAA==.Brèwtality:BAAANQADCgUICwAAAA==.',
Bt='Btrain:BAAANQAECgQIEwAAAA==.',
Bu='Bubblebae:BAAANQADCggIFgABNQAECgcICwACAAAAAA==.',
['Bó']='Bóunty:BAABNQAECn8aAAINAAgKpiIcVgBwAgANAAgKpiIcVgBwAgAAAA==.',
Ca='Calypsto:BAAANQAECgIIAgAAAA==.',
Ce='Cenobité:BAABNQAECn8gAAIDAAkKQg5KNwA/AQADAAkKQg5KNwA/AQAAAA==.',
Ch='Chialing:BAAANQAECgUIDQAAAA==.Chichi:BAAANQAECggIDAAAAA==.Chickenhead:BAAANQAECgEIAwAAAA==.Chip:BAAANQADCgYIHQAAAA==.Chuckfinley:BAAANQAECgIIAwAAAA==.Chuong:BAAANQADCgIIAgABNQAECgUIBgACAAAAAA==.',
Ci='Cirax:BAABNQAECn8ZAAINAAYKzxSotQCZAQANAAYKzxSotQCZAQAAAA==.',
Cl='Classic:BAAANQADCgYIDQABNQAECgYIGwAPAOcXAA==.Cleetess:BAAANQADCgYIDgAAAA==.Clenton:BAABNQAECn84AAIPAAoK8QwnFgBTAQAPAAoK8QwnFgBTAQAAAA==.Clown:BAAANQAECgQIBQABNQAECgEIAgACAAAAAA==.',
Co='Cobrakai:BAAANQADCgEIAQAAAA==.Cosplay:BAAANQAECgcIEwABNQAFFAIICQAQAJQFAA==.',
Cr='Crichton:BAABNQAECn88AAIOAAoKtyG8BwBWAwAOAAoKtyG8BwBWAwAAAA==.Crowford:BAABNQAECn8UAAINAAgK5QnGyQBuAQANAAgK5QnGyQBuAQAAAA==.',
Cy='Cyris:BAAANQADCgUICwABNQAECgYIGQARACcDAA==.',
['Cá']='Cástle:BAAANQAECgUIEQAAAA==.',
Da='Daemonhanta:BAAANQABCgEIAQAAAA==.Daevahna:BAAANQADCggIEQAAAA==.Dak:BAABNQAECn8uAAMPAAoKZxhSEgB9AgAPAAkKgBpSEgB9AgASAAoKdg2mUwC7AQAAAA==.Daksmash:BAAANQAECgQIBQABNQAECgoKLgAPAGcYAA==.Dakstorm:BAABNQAECn8fAAIRAAoKKRekBwBJAgARAAoKKRekBwBJAgABNQAECgoKLgAPAGcYAA==.Darkmiza:BAACNQAFFH8FAAIIAAQKmwTSEgC3AAAIAAQKmwTSEgC3AAA1AAQKfykAAggACgodEjNxAAwCAAgACgodEjNxAAwCAAAA.Dawnstrike:BAAANQADCggIDAAAAA==.',
De='Deadmangalad:BAAANQADCggIHQAAAA==.Deedees:BAAANQAECgQIDAAAAA==.Demonhandler:BAAANQADCgUICQAAAA==.Demonikk:BAAANQAECgQICQAAAA==.Deo:BAAANQAECgYIDgABNQAFFAIICQAQAJQFAA==.Depression:BAAANQAECggIBwAAAA==.',
Di='Diioo:BAAANQAECgMIBQAAAA==.Dirtnåp:BAAANQADCgcIGwAAAA==.Diskbänk:BAAANQADCgUIBQAAAA==.',
Dr='Dragonthorns:BAAANQAECgEIBAAAAA==.Dragontoast:BAAANQAECgQIBgAAAA==.Dral:BAEANQAECgEIAQAAAA==.Drama:BAAANQAECgUIBQAAAA==.Druidïan:BAABNQAECn8XAAMTAAgKsBCBIABaAQATAAgKsBCBIABaAQAUAAIKHgLUcgArAAAAAA==.',
Dy='Dynwor:BAAANQADCggICwAAAA==.',
Ea='Easme:BAAANQAECgcIEAAAAA==.',
El='Elaric:BAAANQAECgUIBQAAAA==.',
En='Engi:BAABNQAECn8lAAMVAAkKTBDGkQDwAQAVAAkKTBDGkQDwAQALAAEKjQVeJAAsAAAAAA==.Enhuna:BAAANQADCgIIAgAAAA==.',
Es='Escaper:BAABNQAECn8nAAIDAAgKwxTDMwAPAgADAAgKwxTDMwAPAgAAAA==.',
Ev='Eversteel:BAAANQADCgUIBQABNQAECgYIGwAPAOcXAA==.',
Ex='Extrema:BAAANQAECgQIBgAAAA==.',
Fe='Felesha:BAAANQADCgQIBAAAAA==.',
Fh='Fhait:BAAANQADCggIJQABNQAECgYIGwABACMGAA==.',
Fi='Fionab:BAAANQADCgIIAgAAAA==.',
Fo='Foxfu:BAAANQADCgYICwAAAA==.',
Fu='Fujika:BAAANQADCgQIBAAAAA==.',
Ga='Galadan:BAABNQAECn8XAAIWAAYKGgWgJgDYAAAWAAYKGgWgJgDYAAABNQADCggIHQACAAAAAA==.Garius:BAAANQAECgUICQAAAA==.Garrekton:BAABNQAECn8oAAMKAAoKzR6LFwCnAgAKAAoKzR6LFwCnAgAXAAEKAACghQAjAAAAAA==.Gaskelmarg:BAAANQADCgYIHQAAAA==.',
Ge='Gellane:BAAANQAECgMIAwAAAA==.',
Gh='Ghozt:BAAANQADCgUICgABNQAECgUIEQACAAAAAA==.',
Gl='Glory:BAABNQAECn8mAAMEAAkKfRhrLgCtAgAEAAkKfRhrLgCtAgASAAEKYwpHPAE6AAAAAA==.',
Go='Goldtusk:BAAANQAECgUIDQAAAA==.',
Gr='Graveyard:BAAANQAECgEIAQABNQAECgUIEQACAAAAAA==.Grundler:BAAANQAECgEIAgAAAA==.Gryphone:BAAANQADCggIEAAAAA==.',
Ha='Hakmud:BAAANQADCggIHAAAAA==.Harandee:BAAANQADCgYICwAAAA==.Hasmus:BAAANQADCgUIBQAAAA==.Haufa:BAAANQAECgIIBAAAAA==.',
He='Headstrong:BAAANQADCgcIBwAAAA==.Hettokal:BAAANQADCgQIBAAAAA==.Heximal:BAAANQADCgQIBwABNQAECgkJKAANAM4WAA==.',
Ho='Hondojoe:BAEBNQAECn8nAAMKAAoKwBcYFgC0AgAKAAoKwBcYFgC0AgAXAAQKpg2mTgDZAAAAAA==.Honeydrake:BAAANQAECggIEgAAAA==.Hopewell:BAABNQAECn8bAAIEAAYKVAM8jQCnAAAEAAYKVAM8jQCnAAAAAA==.',
Hu='Hugnsnuggle:BAABNQAECn8bAAIYAAYKCgq/GwD+AAAYAAYKCgq/GwD+AAABNQAECgYIGwABACMGAA==.Huhu:BAAANQAECggIDgAAAA==.Humilitas:BAAANQADCgUICQAAAA==.',
Ib='Ibn:BAABNQAECn8mAAIVAAgKYQcJewAfAQAVAAgKYQcJewAfAQAAAA==.',
Il='Illadus:BAAANQADCgYICwAAAA==.Illidab:BAABNQAECn8lAAIZAAoKtxyBFAD5AgAZAAoKtxyBFAD5AgAAAA==.',
In='Infectus:BAABNQAECn8YAAMMAAkKgQM9rACcAAAMAAgKTQM9rACcAAADAAkKvgHUlABsAAAAAA==.',
Ir='Irielle:BAAANQADCgYIJwAAAA==.',
Iv='Ivylyn:BAAANQAECgUICwAAAA==.',
Ix='Ixiyá:BAABNQAECn8jAAIaAAoKGCUqBQCeAwAaAAoKGCUqBQCeAwAAAA==.Ixií:BAAANQADCgYIBgAAAA==.Ixì:BAAANQADCgEIAQAAAA==.',
Ja='Jakbenimble:BAAANQADCgcIDQAAAA==.Jakeyprogue:BAAANQAECgMIBAAAAA==.Jakota:BAAANQADCgYIFwAAAA==.Jakskeleton:BAABNQAECn8YAAIGAAYKjA2+VgCSAAAGAAYKjA2+VgCSAAAAAA==.',
Je='Jeamica:BAAANQADCggICwAAAA==.Jethroy:BAAANQADCgQIBAAAAA==.',
Jo='Joerollin:BAEANQADCggICQABNQAECgoKJwAKAMAXAA==.Johnjrambo:BAAANQADCgcIBwAAAA==.',
Ju='Judax:BAABNQAECn8xAAIbAAoK+hP0TwA4AgAbAAoK+hP0TwA4AgAAAA==.Justagirl:BAABNQAECn8bAAIBAAYKIwYuRQDxAAABAAYKIwYuRQDxAAAAAA==.Juti:BAAANQADCgYIFwAAAA==.Juvu:BAAANQADCgQIBAAAAA==.',
Ka='Kadooka:BAABNQAECn8bAAINAAkKdBXMjQDuAQANAAkKdBXMjQDuAQAAAA==.Kahlyn:BAAANQADCgQIBAAAAA==.Kai:BAAANQAECgYIEAAAAA==.Kaldaran:BAAANQAECgEIAgABNQAFFAQIBQAVAMIPAA==.Kallan:BAAANQADCgQJBAABNQAECgYIGwAPAOcXAA==.Kaléanor:BAACNQAFFH8FAAIVAAQKwg9HEgDRAAAVAAQKwg9HEgDRAAA1AAQKfxsAAhUACgqfHZ9AAMwBABUACgqfHZ9AAMwBAAAA.Karen:BAAANQADCgUIBwAAAA==.Katabell:BAABNQAECn8bAAMXAAYKrATLUwC/AAAXAAYKrATLUwC/AAAKAAQKHwY1nQCRAAAAAA==.Katira:BAAANQADCgcIEAAAAA==.',
Ke='Keeganw:BAAANQAECgUIDQAAAA==.Keelay:BAAANQAECgcIEgAAAA==.Kelste:BAAANQAECggIEgAAAA==.',
Ki='Killaclowns:BAAANQADCgUIEwAAAA==.Killjadan:BAAANQAECgMIAwAAAA==.Kimiko:BAAANQAECgEIAQAAAA==.Kioki:BAAANQADCggIEAAAAA==.',
Kl='Klitess:BAAANQADCgIIAgAAAA==.',
Ko='Koffcmorbius:BAAANQADCgYIGgAAAA==.Kostian:BAAANQADCgUICQABNQAECgYIGwAPAOcXAA==.',
Kr='Kraken:BAABNQAECn8oAAIJAAoKhCClAQBpAwAJAAoKhCClAQBpAwAAAA==.',
Ku='Kubb:BAABNQAECn8ZAAIRAAYKJwOwJAARAQARAAYKJwOwJAARAQAAAA==.',
Kw='Kweh:BAACNQAFFH8KAAIWAAQKOBRZAQDJAAAWAAQKOBRZAQDJAAA1AAQKfysAAhYACgrYHx0GABADABYACgrYHx0GABADAAAA.',
['Kê']='Kêlsen:BAAANQAECgIIAwAAAA==.',
La='Laero:BAAANQADCgYICwABNQAECgYIGQARACcDAA==.Larrissa:BAAANQADCgYIFAAAAA==.Laurlynn:BAAANQADCgYICwAAAA==.',
Le='Lenwe:BAAANQAECgUIBgAAAA==.Lettuceprey:BAAANQAECgMIBwAAAA==.',
Li='Lierise:BAAANQAECgEIAQAAAA==.Lilindra:BAABNQAECn8nAAQDAAkK4xPKXQAwAQADAAcKlxHKXQAwAQAMAAcKHxOTgQAYAQAGAAEKAAAa0gArAAAAAA==.Lillymay:BAAANQAECgEIAQAAAA==.Lilspazz:BAAANQAECgIIAwAAAA==.',
Ll='Lluiz:BAAANQAECgEIAQAAAA==.',
Lo='Lockdeath:BAAANQADCgcIDAAAAA==.Logoruk:BAAANQADCgQIBAAAAA==.Lorelleya:BAAANQADCgEIAQAAAA==.Loxia:BAAANQAECgUIDAAAAA==.',
Lu='Lucille:BAAANQADCgYIBgAAAA==.Luckett:BAAANQAECgEIAQAAAA==.Lui:BAAANQAECgIIAwAAAA==.Lumi:BAAANQAECgUIDgAAAA==.',
Ma='Maavarra:BAAANQAECgUIEAAAAA==.Madischa:BAAANQAECgEIBAAAAA==.Madshaggy:BAABNQAECn8oAAIPAAkKZxljEQCNAQAPAAkKZxljEQCNAQAAAA==.Magicdance:BAAANQAECgUIBgABNQAFFAEIAQACAAAAAA==.Magikern:BAAANQADCgMIAwABNQADCgUIBQACAAAAAA==.Magy:BAAANQADCgIIAgAAAA==.Mahallomi:BAAANQADCgQIBAABNQAECgUIDgACAAAAAA==.Maki:BAAANQAECgIIAwAAAA==.Maldreth:BAAANQADCgYIBgAAAA==.Maxlin:BAABNQAECn8WAAIWAAgKWBEeGgBcAQAWAAgKWBEeGgBcAQAAAA==.',
Me='Mehänemäntä:BAAANQADCggIEgAAAA==.Melarii:BAAANQADCgYIEQAAAA==.Merixa:BAAANQAECgQIDgAAAA==.',
Mi='Midou:BAAANQAFFAEIAQAAAA==.Misstreater:BAAANQAECgUICwAAAA==.',
Mo='Momentomori:BAABNQAECn8aAAIIAAoKqwb8zQAuAQAIAAoKqwb8zQAuAQAAAA==.Monbeau:BAABNQAECn8kAAIFAAoKfBbQZAC0AgAFAAoKfBbQZAC0AgAAAA==.Monocerotis:BAABNQAECn8rAAIDAAoKng9hIADJAQADAAoKng9hIADJAQAAAA==.Moosebear:BAAANQADCgYIBgAAAA==.Morishima:BAABNQAECn9GAAMcAAoKpCHoDADMAgAQAAkKpBtmEwDhAgAcAAoKNSHoDADMAgAAAA==.',
Mu='Multipàss:BAAANQADCgQIBQAAAA==.',
My='Mydarling:BAACNQAFFH8IAAMEAAUK/BNhFwDtAAAEAAMK6AxhFwDtAAASAAMK0wMSIQCdAAA1AAQKfy4AAxIACgo8GvR4ADoCABIACQr6GPR4ADoCAAQABgpkFC20ABYBAAAA.Mymoon:BAAANQAECgcIDgAAAA==.Myris:BAABNQAECn8jAAIMAAgKtx2jLQB8AgAMAAgKtx2jLQB8AgAAAA==.',
['Mî']='Mîsgüïdëð:BAAANQAECgEIAQAAAA==.',
Na='Naturalchi:BAABNQAECn8oAAIBAAkKBx00DgAKAgABAAkKBx00DgAKAgAAAA==.',
Nb='Nbi:BAAANQAECgEIAgAAAA==.',
Ne='Nefilion:BAAANQAECgEIBAAAAA==.Nefy:BAAANQAECgYIBgAAAA==.Nezin:BAAANQADCgMJAwAAAA==.',
Ni='Nightrunnêr:BAAANQADCgIIAgABNQAECgYIGwAPAOcXAA==.Niselo:BAAANQADCgUIBQAAAA==.',
No='Nohzul:BAACNQAFFH8QAAIbAAYK8hmjCwCwAQAbAAYK8hmjCwCwAQA1AAQKfyYAAhsACgpFJAQHABIDABsACgpFJAQHABIDAAAA.Nomik:BAAANQAECgIIAgABNQAECgUIBgACAAAAAA==.Nonah:BAAANQADCgYIBwAAAA==.',
Nu='Nullspace:BAABNQAECn8gAAMKAAoKERuyQABoAgAKAAoKERuyQABoAgAXAAIKnglmSwAsAAAAAA==.',
['Ní']='Níght:BAAANQAECgEIAQAAAA==.',
Om='Omfega:BAAANQAECgEIAQAAAA==.',
Or='Orgresh:BAAANQADCggICAAAAA==.Orym:BAAANQAECgYIEAAAAA==.',
Pa='Palacia:BAABNQAECn8gAAMPAAgKTQ6AMQBUAQAPAAYK9xOAMQBUAQASAAcKXAPV+wCEAAAAAA==.Pallythetank:BAAANQAECgUIDwAAAA==.Pappabeary:BAAANQAECgEIAQAAAA==.',
Pe='Peerow:BAAANQADCgYIIQAAAA==.Petrichorica:BAAANQADCgcICgAAAA==.',
Pi='Pintobeans:BAABNQAECn8UAAINAAgK9APk6AAvAQANAAgK9APk6AAvAQAAAA==.',
Po='Popeadin:BAAANQADCgIIAgAAAA==.',
Pr='Preachêr:BAAANQABCgQIBAABNQAECgYIGwAPAOcXAA==.Preistytute:BAAANQAECgEIBAAAAA==.Primeatheist:BAAANQAECggIEwAAAA==.',
Pu='Puuhceew:BAABNQAECn8XAAIKAAkKDwXanwA1AQAKAAkKDwXanwA1AQAAAA==.',
Qu='Quina:BAAANQADCgMIAwAAAA==.',
Ra='Rainbrews:BAAANQAECgEIAwAAAA==.Rainera:BAABNQAECn8pAAIHAAkKPR+CAwC9AgAHAAkKPR+CAwC9AgABNQAFFAUIDwAYAEIjAA==.Ramanas:BAAANQAECgQIBAAAAA==.Ramrod:BAAANQAECgYIDQAAAA==.Ramstank:BAAANQAECgMIBQAAAA==.Rattles:BAAANQAECgIIAwAAAA==.',
Re='Redgicide:BAAANQAECgYIDwABNQAECgkJKAANAM4WAA==.Releafme:BAACNQAFFH8TAAITAAYKIR6gAgDSAQATAAYKIR6gAgDSAQA1AAQKfzYAAhMACgqOJaQBALsDABMACgqOJaQBALsDAAAA.Resurgencê:BAABNQAECn8bAAIPAAYK5xfuJAC5AQAPAAYK5xfuJAC5AQAAAA==.',
Ri='Riordan:BAABNQAECn8VAAISAAYKJwxi5gBOAQASAAYKJwxi5gBOAQAAAA==.',
Ro='Rojeton:BAAANQADCgIIAgAAAA==.Rothema:BAABNQAECn8YAAIbAAYK9gN50gDvAAAbAAYK9gN50gDvAAAAAA==.Routh:BAAANQAECgEIAgAAAA==.',
Ru='Rubee:BAAANQADCgMIAwAAAA==.',
Rw='Rwlmaster:BAABNQAECn8nAAIGAAkKdBFEKgBMAQAGAAkKdBFEKgBMAQAAAA==.',
Sa='Sandwiches:BAAANQAECgEIAgAAAA==.',
Sc='Scerra:BAABNQAECn8vAAMDAAkKChaCLAA7AgADAAkKChaCLAA7AgAMAAMKogJewQBoAAAAAA==.Scridders:BAABNQAECn8YAAIEAAkK7xROLgDuAQAEAAkK7xROLgDuAQAAAA==.Scridderz:BAAANQAECgEIAQAAAA==.Scriddle:BAAANQAECgUIBQAAAA==.',
Se='Secre:BAAANQADCgQJBAABNQAECgIIAwACAAAAAA==.Sellandre:BAAANQADCgYIBgABNQAECgoKHgAdANQVAA==.Seru:BAAANQAECgQIBgAAAA==.',
Sh='Shamarha:BAABNQAECn8jAAIaAAgKqh3wHwBFAgAaAAgKqh3wHwBFAgAAAA==.Shamonbo:BAAANQADCgUIBQABNQAECgoKJAAFAHwWAA==.Sharriavolf:BAABNQAECn8cAAMIAAcKPR3dmgCjAQAIAAUK+RzdmgCjAQAJAAIKox1lSQCjAAAAAA==.Shion:BAAANQAECgQIBAABNQAFFAcIIQAOAIgeAA==.Shreder:BAAANQADCgIIAgAAAA==.Shuma:BAAANQADCgUIBgAAAA==.',
Si='Simichaelton:BAECNQAFFH8GAAMdAAIKTBHOEgBJAAAFAAEKbRIhWABQAAAdAAEKKxDOEgBJAAA1AAQKfzwAAx0ACgqxGhAbABoBAAUACQqhFwGxACECAB0ABAp+HBAbABoBAAE1AAUUBAgIAAEACgsA.Sinahi:BAAANQAECgEIAQAAAA==.Sinpal:BAAANQAECgcIDgAAAA==.Sinthea:BAAANQAECggIBQAAAA==.',
Sn='Sneakysoul:BAACNQAFFH8JAAMQAAIKlAVqFACmAAAQAAIKlAVqFACmAAAcAAEKAABwHgAAAAA1AAQKfygAAxAACgo3IswBACMDABAACgo3IswBACMDABwAAQoAABO0AAAAAAAA.',
So='Solyn:BAABNQAECn8YAAISAAcKQwal8QA5AQASAAcKQwal8QA5AQAAAA==.Sonic:BAAANQADCgUIBQAAAA==.',
Sp='Spagooti:BAAANQAECgcIEgAAAA==.Spanxya:BAAANQADCgQIBAAAAA==.Spartaaxd:BAABNQAECn8YAAIDAAgKnw0NRgCoAQADAAgKnw0NRgCoAQAAAA==.',
St='Stabbard:BAAANQADCgQIBAAAAA==.Stagerrind:BAAANQADCgMIAwAAAA==.Starfall:BAAANQAECgEIAgAAAA==.Steiner:BAAANQADCgUIBwAAAA==.Stejamarha:BAAANQADCgQIBAAAAA==.',
Su='Sugarseer:BAABNQAECn8ZAAIaAAoKcxN2UwAZAgAaAAoKcxN2UwAZAgAAAA==.Suka:BAAANQADCggIJgAAAA==.Suzi:BAABNQAECn8bAAINAAcKfwjNkQAOAQANAAcKfwjNkQAOAQAAAA==.',
Sw='Swiftleaf:BAAANQADCggICAAAAA==.',
Sy='Syevoid:BAAANQADCgIIAwAAAA==.Sylentcurse:BAAANQAECgUICwABNQAECggIIwANAEAPAA==.Sylentstorm:BAAANQAECgEIAgABNQAECggIIwANAEAPAA==.Sylentwolvez:BAAANQAECgUICQAAAA==.Syleta:BAAANQADCgEIAQABNQAECgkJJwADAOMTAA==.Sylvarus:BAAANQADCgQIBAAAAA==.',
Ta='Tabraxis:BAAANQAECgEIAwAAAA==.Tagalorc:BAABNQAECn8fAAIFAAcKAAyjogABAQAFAAcKAAyjogABAQAAAA==.Takamaki:BAAANQADCgUIFwAAAA==.Talionwrite:BAAANQADCgYIBwAAAA==.Tanksbacon:BAAANQAECgUIBgAAAA==.',
Te='Teana:BAAANQAECgcIEwAAAA==.Tempestas:BAAANQADCgYICAAAAA==.',
Th='Thechadd:BAAANQAECggIBwAAAA==.Thelegendáry:BAABNQAECn8wAAMaAAkKDRudNwCBAgAaAAkKDRudNwCBAgAbAAEKRhKgygAuAAAAAA==.Themigrant:BAAANQAECgEIAgAAAA==.Therosewood:BAAANQADCggICAAAAA==.Thomm:BAAANQAECgEIAQAAAA==.Thorgrimm:BAAANQADCgYIBgAAAA==.Thraine:BAABNQAECn8WAAIVAAcK3RDeWwBvAQAVAAcK3RDeWwBvAQAAAA==.Threedog:BAAANQADCgIIAgAAAA==.',
Ti='Tinder:BAAANQAECgEIAQAAAA==.Tione:BAABNQAECn8fAAMTAAYKASBjEwDyAQATAAYKASBjEwDyAQAUAAEKAABOwAAhAAAAAA==.',
To='Toadvoker:BAABNQAECn8hAAMeAAoK+hb/EwBuAgAeAAoK+hb/EwBuAgAfAAEKxwB0KQARAAAAAA==.Topao:BAAANQADCgYIBgABNQAECgQIBgACAAAAAA==.Toriee:BAAANQAECgEIAwAAAA==.Totembish:BAABNQAECn8gAAIbAAgKxgmoTAAnAQAbAAgKxgmoTAAnAQAAAA==.',
Tr='Trisstan:BAABNQAECn8bAAIdAAYK8Aa2IADjAAAdAAYK8Aa2IADjAAAAAA==.Trollthrall:BAAANQAECgMIBAAAAA==.',
Ty='Tyster:BAACNQAFFH8FAAISAAIKuQYsGwB2AAASAAIKuQYsGwB2AAA1AAQKfyQAAhIACgrHHGJfAHsCABIACgrHHGJfAHsCAAAA.',
['Tï']='Tïghtgrïp:BAABNQAECn8kAAQDAAoK0hgVJQBqAgADAAoKCRcVJQBqAgAGAAcKVhkmOAAEAQAMAAIK2gjTzgBPAAAAAA==.',
['Tø']='Tørmented:BAAANQADCgUIBQAAAA==.',
Un='Undol:BAAANQADCgcIFQABNQAECgYIGQARACcDAA==.',
Va='Vaellborn:BAAANQADCgEIAQAAAA==.Vandress:BAAANQADCgMIAQABNQAECgQIBgACAAAAAA==.',
Ve='Velobeef:BAAANQADCgEIAQAAAA==.Veloth:BAACNQAFFH8ZAAMdAAcKIhU5AACeAQAdAAcKIhU5AACeAQAFAAMKbA0IOgDdAAA1AAQKfz4AAx0ACgrnJJ4BAHQDAB0ACgoLJJ4BAHQDAAUACQqYHrtIAPECAAAA.Verminus:BAABNQAECn8bAAQTAAkKVwwgNgBrAQATAAgKNAwgNgBrAQAUAAYKCgapcwD8AAAWAAEK6gZqSAApAAAAAA==.',
Vi='Viggle:BAAANQADCgUICAABNQAECgYIGwAPAOcXAA==.Viho:BAABNQAECn8mAAISAAgKvhNjmgDuAQASAAgKvhNjmgDuAQAAAA==.Vilekin:BAAANQAECgUIBwAAAA==.Vithaxa:BAAANQAECgMICAAAAA==.',
Vo='Voidra:BAAANQAECgEIAQAAAA==.Voodoomike:BAAANQAECgIIAwAAAA==.',
Vy='Vyinson:BAAANQAECgQIBAABNQAECgUIDQACAAAAAA==.',
Wa='Warloque:BAAANQADCgMIAwAAAA==.',
We='Weechuup:BAAANQAECgQICQAAAA==.',
Wi='Wifeotusk:BAAANQAECgQIBAAAAA==.Wiggle:BAAANQADCgYICwAAAA==.Willmar:BAABNQAECn8XAAISAAYK4QmBHQHuAAASAAYK4QmBHQHuAAAAAA==.Window:BAAANQAECgEIBAABNQAECgUIEQACAAAAAA==.Windrun:BAAANQAECgUIDAAAAA==.',
Wo='Wolf:BAABNQAECn8jAAIgAAoKRhJkEgCMAQAgAAoKRhJkEgCMAQAAAA==.Woodtique:BAAANQADCgYIHAAAAA==.',
Wu='Wulthan:BAAANQADCgYICwAAAA==.',
Xa='Xandercruise:BAAANQAECgEIAwAAAA==.',
Xe='Xelphie:BAAANQADCggICQAAAA==.',
Xu='Xuchilbara:BAABNQAECn8WAAIWAAYKXx3FEAD7AQAWAAYKXx3FEAD7AQAAAA==.',
Ya='Yamato:BAABNQAECn8UAAISAAgK+A5FjQA3AQASAAgK+A5FjQA3AQAAAA==.',
Za='Zaledron:BAAANQAECgcIEwAAAA==.',
Zb='Zbelladonna:BAAANQAECgEIAgABNQAECgoKUAADAP0iAA==.',
Ze='Zezera:BAAANQAECgQIBgAAAA==.',
Zh='Zhades:BAABNQAECn9QAAMDAAoK/SKgBQCGAwADAAoK/SKgBQCGAwAMAAkKOBEuWwCjAQAAAA==.Zhort:BAAANQAECgIIAgAAAA==.',
Zi='Zioki:BAAANQADCggICQAAAA==.',
Zo='Zodgul:BAAANQADCggICAAAAA==.Zomby:BAEBNQAECn8VAAIGAAkKHw8VIgCCAQAGAAkKHw8VIgCCAQABNQAFFAQICAABAAoLAA==.',
Zu='Zultan:BAABNQAECn81AAIIAAoKIQpEUQBwAQAIAAoKIQpEUQBwAQAAAA==.',
Zy='Zynblasted:BAAANQADCgQIBAAAAA==.Zynhunter:BAAANQADCgYIGgAAAA==.Zyuxis:BAAANQAECgEIAgABNQAECgYICQACAAAAAA==.',
['Ðö']='Ðöçtørðöøm:BAAANQADCgIIAgAAAA==.',
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
