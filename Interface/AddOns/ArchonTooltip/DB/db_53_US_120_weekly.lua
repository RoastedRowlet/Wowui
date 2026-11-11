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

local lookup = {'DemonHunter-Vengeance','DeathKnight-Frost','Paladin-Holy','Mage-Arcane','Unknown-Unknown','DeathKnight-Blood','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Priest-Holy','Warrior-Fury','DeathKnight-Unholy','Hunter-BeastMastery','DemonHunter-Devourer','Paladin-Retribution','Paladin-Protection','Rogue-Assassination','Shaman-Enhancement','Druid-Restoration','Druid-Balance','Druid-Feral','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Havoc','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Rogue-Subtlety','Mage-Frost','Druid-Guardian',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abberleigh:BAAANQAECgUICwAAAA==.Abron:BAAANQAECgIIAQAAAA==.',
Ad='Adahma:BAAANQADCgYIEQABNQAECgcIJgABAMQIAA==.Adelerock:BAAANQAECgUIBwAAAA==.',
Ae='Aerostotle:BAAANQAECgcIDwAAAA==.',
Ag='Aganoth:BAAANQAECgcJEAAAAA==.',
Al='Alaraa:BAAANQADCgUIBwABNQAECgkJMgACAKsWAA==.Algonq:BAAANQAECgEIAQABNQAECgYIIgADAHcDAA==.Alkamaz:BAABNQAECn8bAAIEAAkKxAvd9gCeAQAEAAkKxAvd9gCeAQAAAA==.Alkiris:BAAANQADCgEIAQABNQAECgQICQAFAAAAAA==.Alssar:BAAANQAECgIIAgAAAA==.Alstar:BAABNQAECn8hAAIGAAoKQBPASgDMAQAGAAoKQBPASgDMAQAAAA==.Alynis:BAAANQADCgQIBAAAAA==.',
Am='Amac:BAAANQADCgUIBQAAAA==.Amathus:BAABNQAECn9UAAQHAAoK8BWCBQAVAgAHAAoK8BWCBQAVAgAIAAYKRhCMwQBIAQAJAAIKwwu2NQA0AAAAAA==.',
An='Andarial:BAAANQAECgcIDQAAAA==.Andreth:BAAANQAECgUICwAAAA==.Anoxyn:BAAANQAECgQIBAAAAA==.Anthe:BAAANQADCgUIFAAAAA==.',
Ar='Arcee:BAAANQADCgQIBgAAAA==.Ares:BAABNQAECn8dAAIKAAcKKA6VpAAeAQAKAAcKKA6VpAAeAQABNQADCgMJAwAFAAAAAA==.Aryxi:BAAANQADCgUJBQABNQADCgMJAwAFAAAAAA==.',
As='Asiägo:BAAANQABCgcJCgAAAA==.',
At='Atlas:BAAANQAECgYIDAAAAA==.',
Ba='Baelhal:BAABNQAECn8+AAMGAAoK1BYuHwDzAQAGAAoKnBYuHwDzAQACAAEKVQ+uqQA4AAAAAA==.',
Be='Bearden:BAAANQADCgMIAgAAAA==.Bearypotter:BAAANQADCgUIBQAAAA==.Benedin:BAAANQADCgcJDAABNQAECgoKKAALAM0eAA==.',
Bi='Bigtex:BAABNQAECn8mAAIMAAcKhgdcGgD/AAAMAAcKhgdcGgD/AAAAAA==.Biped:BAABNQAECn8wAAIHAAoKQxX/BgDoAQAHAAoKQxX/BgDoAQAAAA==.Bishul:BAAANQAECgQIBAAAAA==.',
Bl='Blackdeath:BAABNQAECn8tAAINAAoKRRL7HQDfAQANAAoKRRL7HQDfAQAAAA==.Bloodsport:BAAANQADCgIIAgAAAA==.',
Bo='Bofadees:BAAANQADCggIFAAAAA==.Boloevo:BAAANQADCgUIBQABNQAECgYIEgAFAAAAAA==.Bolopal:BAAANQAECgIIAgABNQAECgYIEgAFAAAAAA==.Boolin:BAAANQADCgQIBAABNQAECgoKKAAJAIQgAA==.Boomstique:BAABNQAECn8mAAIOAAcK7BDruQCQAQAOAAcK7BDruQCQAQAAAA==.Boondocka:BAABNQAECn8oAAIOAAkKzhbYUAB9AgAOAAkKzhbYUAB9AgAAAA==.',
Br='Brex:BAAANQAECggIAQAAAA==.Brissennissa:BAABNQAECn8sAAIPAAkK5hzjEgDUAgAPAAkK5hzjEgDUAgAAAA==.Brokkr:BAAANQADCggIEwAAAA==.Bronar:BAAANQADCgMIAwAAAA==.Brutalís:BAABNQAECn8pAAIOAAoKyQ9ZXgDzAQAOAAoKyQ9ZXgDzAQAAAA==.Brèwtality:BAAANQADCgUICwAAAA==.',
Bt='Btrain:BAABNQAECn8ZAAIQAAYKvgbEIAGlAAAQAAYKvgbEIAGlAAAAAA==.',
Bu='Bubblebae:BAAANQADCggIFgABNQAECgYIDAAFAAAAAA==.',
['Bó']='Bóunty:BAABNQAECn8dAAIOAAkKEyMcVgBwAgAOAAkKEyMcVgBwAgAAAA==.',
Ca='Calypsto:BAAANQAECgIIAgAAAA==.',
Ce='Cenobité:BAABNQAECn8tAAICAAoKjA4HMwDEAQACAAoKjA4HMwDEAQAAAA==.',
Ch='Chamber:BAAANQAECgYIBwABNQAECgkJHQAEADYZAA==.Chialing:BAAANQAECgYIEwAAAA==.Chickenhead:BAAANQAECgUIBgAAAA==.Chip:BAAANQADCggIIgAAAA==.Chromefury:BAAANQADCgQIBAAAAA==.Chuckfinley:BAAANQAECgIIAwAAAA==.Chuong:BAAANQADCgIIAgABNQAECgcICgAFAAAAAA==.',
Ci='Cirax:BAABNQAECn8kAAIOAAcK+hUvmABoAQAOAAcK+hUvmABoAQAAAA==.',
Cl='Classic:BAAANQADCgYIDQABNQAECgcIJgARAKsVAA==.Cleetess:BAAANQADCgYIDgAAAA==.Clenton:BAABNQAECn9BAAIRAAoK/gwnIgBHAQARAAoK/gwnIgBHAQAAAA==.Clown:BAAANQAECgQICgAAAA==.',
Co='Cobrakai:BAAANQADCgEIAQAAAA==.Cosplay:BAAANQAECgcIEgABNQAFFAIICgASAJQFAA==.',
Cr='Crichton:BAABNQAECn9CAAIPAAoKMiK8BwBWAwAPAAoKMiK8BwBWAwAAAA==.Crowford:BAABNQAECn8cAAIOAAgKxwr+tAAsAQAOAAgKxwr+tAAsAQAAAA==.',
Cy='Cyris:BAAANQADCgcIDgABNQAECgcIJQATAJcDAA==.',
['Cá']='Cástle:BAABNQAECn8dAAIEAAkKNhkZMQBxAgAEAAkKNhkZMQBxAgAAAA==.',
Da='Daemonhanta:BAAANQABCgEIAQAAAA==.Daevahna:BAAANQADCggIEQAAAA==.Dak:BAABNQAECn89AAMRAAoKDhpSEgB9AgARAAoKlxlSEgB9AgAQAAoKxBAUbQDjAQAAAA==.Daksmash:BAAANQAECgYIDwABNQAECgoKPQARAA4aAA==.Dakstorm:BAABNQAECn8tAAITAAoKNBl3CQB5AgATAAoKNBl3CQB5AgABNQAECgoKPQARAA4aAA==.Darkmiza:BAACNQAFFH8FAAIIAAQKmwRIHQCwAAAIAAQKmwRIHQCwAAA1AAQKfzAAAggACgpcEzNxAAwCAAgACgpcEzNxAAwCAAAA.Dawnstrike:BAAANQAECgEIAQAAAA==.',
De='Deadmangalad:BAAANQADCggIHQAAAA==.Deedees:BAAANQAECgYICwAAAA==.Demonhandler:BAAANQADCgUICQAAAA==.Demonikk:BAAANQAECgQICAAAAA==.Deo:BAAANQAECgYIDAABNQAFFAIICgASAJQFAA==.Depression:BAAANQAECggIBwAAAA==.',
Di='Diioo:BAAANQAECgMIBQAAAA==.Dirtnåp:BAAANQAECgEIAQAAAA==.Diskbänk:BAAANQADCgUIBQAAAA==.',
Dr='Dragontoast:BAAANQAECgUICwAAAA==.Drama:BAAANQAECgUIBQAAAA==.Druidïan:BAABNQAECn8hAAMUAAkKwBI4GwATAgAUAAkKwBI4GwATAgAVAAIKHgJUjAAoAAAAAA==.',
Dy='Dynwor:BAAANQADCggICwAAAA==.',
Ea='Easme:BAAANQAECgcIEAAAAA==.',
El='Elaric:BAAANQAECgYICQAAAA==.',
En='Engi:BAABNQAECn8wAAMKAAkKTBDGkQDwAQAKAAkKTBDGkQDwAQAMAAEKjQXHMwArAAAAAA==.Enhuna:BAAANQADCgIIAgAAAA==.',
Es='Escaper:BAABNQAECn8nAAICAAgKwxTDMwAPAgACAAgKwxTDMwAPAgAAAA==.',
Ev='Eversteel:BAAANQADCgUIBQABNQAECgcIJgARAKsVAA==.',
Ex='Extrema:BAAANQAECgUICwAAAA==.',
Fe='Felesha:BAAANQADCgQIBAAAAA==.',
Fh='Fhait:BAAANQAECgEIAQABNQAECgcIJgABAMQIAA==.',
Fi='Fionab:BAAANQADCgIIAgAAAA==.',
Fo='Foxfu:BAAANQADCgYICwAAAA==.',
Fu='Fujika:BAAANQADCgQIBAAAAA==.',
Ga='Galadan:BAABNQAECn8bAAIWAAYK+QWgJgDYAAAWAAYK+QWgJgDYAAABNQADCggIHQAFAAAAAA==.Garius:BAABNQAECn8ZAAIKAAkKdwhCcgCWAQAKAAkKdwhCcgCWAQAAAA==.Garrekton:BAABNQAECn8oAAMLAAoKzR4MKwCJAgALAAoKzR4MKwCJAgAXAAEKAACghQAjAAAAAA==.Gaskelmarg:BAAANQADCgYIHQAAAA==.',
Ge='Gellane:BAAANQAECgMIAwAAAA==.',
Gh='Ghozt:BAAANQADCgUICgABNQAECgkJHQAEADYZAA==.',
Gl='Glory:BAABNQAECn8mAAMDAAkKfRhrLgCtAgADAAkKfRhrLgCtAgAQAAEKYwpygwE3AAAAAA==.',
Go='Goldtusk:BAAANQAECgUIDQAAAA==.',
Gr='Graveyard:BAAANQADCgcICwABNQAECgkJHQAEADYZAA==.Grundler:BAAANQAECgEIAQAAAA==.Gryphone:BAAANQADCggIEAAAAA==.',
Ha='Hakmud:BAAANQAECgEIAQAAAA==.Harandee:BAAANQADCgYICwAAAA==.Hasmus:BAAANQADCgUIBQAAAA==.Haufa:BAAANQAECgIIAwAAAA==.',
He='Headstrong:BAAANQADCgcIBwAAAA==.Hettokal:BAAANQADCgQIBAAAAA==.Heximal:BAAANQADCgQIBwABNQAECgkJKAAOAM4WAA==.',
Ho='Hondojoe:BAEBNQAECn8yAAMLAAoKzRdnKgCNAgALAAoKzRdnKgCNAgAXAAkKWQ2SHACWAQAAAA==.Honey:BAAANQAECggICQAAAA==.Honeydrake:BAABNQAECn8cAAQYAAkKLAsTJgCMAQAYAAkKLAsTJgCMAQAZAAYKKAbyFQBxAAAaAAEKTQGMRQASAAAAAA==.Hopewell:BAABNQAECn8iAAIDAAYKdwMRuACZAAADAAYKdwMRuACZAAAAAA==.',
Hu='Hugnsnuggle:BAABNQAECn8mAAIBAAcKxAj6GAC8AAABAAcKxAj6GAC8AAAAAA==.Huhu:BAAANQAECggICwAAAA==.Humilitas:BAAANQADCgUICQAAAA==.',
['Hä']='Häväç:BAAANQAECgQIBAAAAA==.',
Ib='Ibn:BAABNQAECn8sAAIKAAoKHQj5eQCBAQAKAAoKHQj5eQCBAQAAAA==.',
Il='Illadus:BAAANQADCgYICwAAAA==.Illidab:BAABNQAECn8lAAIbAAoKtxyBFAD5AgAbAAoKtxyBFAD5AgAAAA==.',
In='Infectus:BAABNQAECn8YAAMNAAkKgQM9rACcAAANAAgKTQM9rACcAAACAAkKvgHUlABsAAAAAA==.',
Ir='Irielle:BAAANQAECgEIAQAAAA==.',
Iv='Ivylyn:BAAANQAECggIEQAAAA==.',
Ix='Ixiyá:BAABNQAECn8qAAIcAAoKGCUqBQCeAwAcAAoKGCUqBQCeAwAAAA==.Ixií:BAAANQADCgYIBgAAAA==.Ixì:BAAANQADCgEIAQAAAA==.',
Ja='Jakbenimble:BAAANQADCgcIDQAAAA==.Jakeyprogue:BAAANQAECgMIBAAAAA==.Jakota:BAAANQADCggIIQAAAA==.Jakskeleton:BAABNQAECn8jAAIGAAcKKg8ySwACAQAGAAcKKg8ySwACAQAAAA==.',
Je='Jeamica:BAAANQADCggIFQAAAA==.Jethroy:BAAANQADCgQIBAAAAA==.',
Jo='Joerollin:BAEANQADCggICQABNQAECgoKMgALAM0XAA==.',
Ju='Judax:BAABNQAECn81AAIdAAoK1Bb0TwA4AgAdAAoK1Bb0TwA4AgAAAA==.Justagirl:BAABNQAECn8kAAIeAAcK7gbSNwDPAAAeAAcK7gbSNwDPAAABNQAECgcIJgABAMQIAA==.Juti:BAAANQADCggIIQAAAA==.Juvu:BAAANQADCgQIBAAAAA==.',
Ka='Kadooka:BAABNQAECn8oAAIOAAkKSBZ9YADtAQAOAAkKSBZ9YADtAQAAAA==.Kahlyn:BAAANQADCgQIBAAAAA==.Kai:BAAANQAECgYIEAAAAA==.Kaldaran:BAAANQADCgcIBwABNQAFFAYIBwAKAMcMAA==.Kallan:BAAANQADCgQJBAABNQAECgcIJgARAKsVAA==.Kaléanor:BAACNQAFFH8HAAIKAAYKxwxZEgAKAQAKAAYKxwxZEgAKAQA1AAQKfykAAgoACgrQIZocAMwCAAoACgrQIZocAMwCAAAA.Karen:BAAANQADCgYIDAAAAA==.Katabell:BAABNQAECn8iAAMXAAcKjQTnPQClAAAXAAcKjQTnPQClAAALAAQKHwb4xgCFAAAAAA==.Katira:BAAANQADCggIFgAAAA==.',
Ke='Keeganw:BAAANQAECgYIDwAAAA==.Keelay:BAAANQAECgcIDwAAAA==.Kelste:BAABNQAECn8VAAIMAAoKAgMpJACSAAAMAAoKAgMpJACSAAAAAA==.',
Ki='Kilabo:BAAANQABCgUIAwAAAA==.Killaclowns:BAAANQADCgUIEwAAAA==.Killjadan:BAAANQAECgMIAwAAAA==.Kimiko:BAAANQADCgUICQAAAA==.Kioki:BAAANQADCggIEAAAAA==.',
Kl='Klitess:BAAANQADCgYICAAAAA==.',
Ko='Kodrac:BAAANQAECgEIAQAAAA==.Koffcmorbius:BAAANQADCggIKQAAAA==.Kostian:BAAANQADCgUICQABNQAECgcIJgARAKsVAA==.',
Kr='Kraken:BAABNQAECn8oAAIJAAoKhCClAQBpAwAJAAoKhCClAQBpAwAAAA==.',
Ku='Kubb:BAABNQAECn8lAAITAAcKlwOwJAARAQATAAcKlwOwJAARAQAAAA==.',
Kw='Kweh:BAACNQAFFH8KAAIWAAQKOBRFAgD8AAAWAAQKOBRFAgD8AAA1AAQKfywAAhYACgrYHx0GABADABYACgrYHx0GABADAAAA.',
['Kê']='Kêlsen:BAAANQAECgIIAQAAAA==.',
La='Laero:BAAANQADCgYICwABNQAECgcIJQATAJcDAA==.Larrissa:BAAANQAECgQIBAAAAA==.Laurlynn:BAAANQADCgYICwAAAA==.',
Le='Lenwe:BAAANQAECgQICQABNQAECgcICgAFAAAAAA==.Lettuceprey:BAAANQAECgUIDAAAAA==.',
Li='Lierise:BAAANQADCgcIDgAAAA==.Lilindra:BAABNQAECn8yAAQCAAkKqxaQUAA7AQACAAcKmBSQUAA7AQANAAcKMhSTgQAYAQAGAAYKRg4qWgDKAAAAAA==.Lillymay:BAAANQAECgEIAQAAAA==.Lilspazz:BAAANQAECgQIBwAAAA==.',
Ll='Lluiz:BAAANQAECgEIAQAAAA==.',
Lo='Lockdeath:BAAANQADCgcIDAAAAA==.Logoruk:BAAANQADCgQIBAAAAA==.Lorelleya:BAAANQADCgEIAQAAAA==.Loxia:BAAANQAECgYICwAAAA==.',
Lu='Lucille:BAAANQADCgYIBgAAAA==.Luckett:BAAANQADCgMJAwAAAA==.Lui:BAAANQAECgIIAgAAAA==.Lumi:BAAANQAECgUIDAAAAA==.',
Ma='Maavarra:BAABNQAECn8WAAIWAAYKIBk/FwBCAQAWAAYKIBk/FwBCAQAAAA==.Madshaggy:BAABNQAECn81AAIRAAkKZxmxFQC8AQARAAkKZxmxFQC8AQAAAA==.Magicdance:BAAANQAECgUIBQABNQAFFAEIAQAFAAAAAA==.Magikern:BAAANQADCgMIAwABNQADCgUIBQAFAAAAAA==.Magy:BAAANQADCgIIAgAAAA==.Mahallomi:BAAANQADCgQIBAABNQAECgUIDgAFAAAAAA==.Maki:BAAANQAECgIIAwAAAA==.Maldreth:BAAANQADCgYIBgAAAA==.Maxlin:BAABNQAECn8eAAIWAAoKPRREFQBZAQAWAAoKPRREFQBZAQAAAA==.',
Me='Mehänemäntä:BAAANQAECgQIBAAAAA==.Melarii:BAAANQADCgYIEQAAAA==.Merixa:BAAANQAECgQICQAAAA==.',
Mi='Midou:BAAANQAFFAEIAQAAAA==.Misstreater:BAAANQAECgUICwAAAA==.',
Mo='Momentomori:BAABNQAECn8dAAIIAAoKqwb8zQAuAQAIAAoKqwb8zQAuAQAAAA==.Monbeau:BAABNQAECn8kAAIEAAoKfBbQZAC0AgAEAAoKfBbQZAC0AgAAAA==.Monocerotis:BAABNQAECn82AAICAAoKABGpLQDiAQACAAoKABGpLQDiAQAAAA==.Moosebear:BAAANQADCgYIBgAAAA==.Morishima:BAABNQAECn9RAAMfAAoKpCHSEQDfAgASAAkKpBtmEwDhAgAfAAoKNSHSEQDfAgAAAA==.',
Mu='Multipàss:BAAANQADCgQIBQAAAA==.',
My='Mydarling:BAACNQAFFH8IAAMDAAUK/BNhFwDtAAADAAMK6AxhFwDtAAAQAAMK0wMSIQCdAAA1AAQKfzEAAxAACgpGGvR4ADoCABAACQr6GPR4ADoCAAMABgqGFTmSAPEAAAAA.Mymoon:BAAANQAECgcIDAAAAA==.Myris:BAABNQAECn8jAAINAAgKtx2jLQB8AgANAAgKtx2jLQB8AgAAAA==.',
['Mî']='Mîsgüïdëð:BAAANQAECgEIAQAAAA==.',
Na='Naturalchi:BAABNQAECn8oAAIeAAkKBx2hFQClAgAeAAkKBx2hFQClAgAAAA==.',
Nb='Nbi:BAAANQAECgEIAQAAAA==.',
Ne='Nefilion:BAAANQAECgQIBwAAAA==.Nefy:BAAANQAECgUICgAAAA==.Nezin:BAAANQADCgMJAwAAAA==.',
Ni='Nightrunnêr:BAAANQAECgEIAQABNQAECgcIJgARAKsVAA==.Niselo:BAAANQADCgUIBQAAAA==.',
No='Nogods:BAAANQAECgYIBgABNQAECgkJHQAEADYZAA==.Nohzul:BAACNQAFFH8RAAIdAAcKnhhSCABAAQAdAAcKnhhSCABAAQA1AAQKfygAAh0ACgroJNkLAAsDAB0ACgroJNkLAAsDAAAA.Nomik:BAAANQAECgcICgAAAA==.Nonah:BAAANQADCgYIBwAAAA==.',
Nu='Nullspace:BAABNQAECn8gAAMLAAoKERuyQABoAgALAAoKERuyQABoAgAXAAIKnglTYgAsAAAAAA==.',
Ny='Nyleelyr:BAAANQAECgQIBQAAAA==.',
['Ní']='Níght:BAAANQAECgEIAQAAAA==.',
Og='Oggy:BAAANQADCgUIBQAAAA==.',
Or='Orgresh:BAAANQADCggICAAAAA==.Orym:BAABNQAECn8VAAIRAAgK6AZdNQDKAAARAAgK6AZdNQDKAAAAAA==.',
Pa='Palacia:BAABNQAECn8gAAMRAAgKTQ6AMQBUAQARAAYK9xOAMQBUAQAQAAcKXAOvPQF/AAAAAA==.Pallythetank:BAABNQAECn8YAAMRAAcKbghIMQDgAAARAAcKbghIMQDgAAAQAAMKlwFAkwFBAAAAAA==.Pancakeeater:BAAANQAECgEIAQAAAA==.',
Pe='Peerow:BAAANQAECgEIAQAAAA==.Petrichorica:BAAANQADCgcICgAAAA==.',
Ph='Phenomenon:BAAANQAECgEIAQAAAA==.',
Pi='Pintobeans:BAABNQAECn8UAAIOAAgK9APk6AAvAQAOAAgK9APk6AAvAQAAAA==.',
Po='Popeadin:BAAANQADCgQIBgAAAA==.',
Pr='Preachêr:BAAANQABCgQIBAABNQAECgcIJgARAKsVAA==.Primeatheist:BAABNQAECn8dAAIXAAkKXRioFAD+AQAXAAkKXRioFAD+AQAAAA==.',
Pu='Puuhceew:BAABNQAECn8kAAILAAkKSArXYACnAQALAAkKSArXYACnAQAAAA==.',
Py='Pyaghra:BAAANQAECgQIBAAAAA==.',
Qu='Quina:BAAANQADCgMIAwAAAA==.',
Ra='Rainbrews:BAAANQAECgEIAQAAAA==.Rainera:BAABNQAECn8uAAIHAAkKyR+CAwC9AgAHAAkKyR+CAwC9AgABNQAFFAYIEQABAJwjAA==.Ramanas:BAAANQAECgYICgAAAA==.Ramrod:BAAANQAECgYIEQAAAA==.Ramstank:BAAANQAECgMIBQAAAA==.Rattles:BAAANQAECgIIAwAAAA==.',
Re='Redgicide:BAAANQAECgYIDwABNQAECgkJKAAOAM4WAA==.Releafme:BAACNQAFFH8UAAIUAAcKcxqqAwD8AQAUAAcKcxqqAwD8AQA1AAQKfzkAAhQACgqOJaQBALsDABQACgqOJaQBALsDAAAA.Resurgencê:BAABNQAECn8mAAIRAAcKqxXuJAC5AQARAAcKqxXuJAC5AQAAAA==.',
Ri='Riordan:BAABNQAECn8fAAIQAAkKuQ0TmQCFAQAQAAkKuQ0TmQCFAQAAAA==.',
Ro='Rojeton:BAAANQADCgIIAgAAAA==.Rothema:BAABNQAECn8dAAIdAAYK9gN50gDvAAAdAAYK9gN50gDvAAAAAA==.Routh:BAAANQAECgEIAQAAAA==.',
Ru='Rubberbizkit:BAAANQADCgYICAAAAA==.Rubee:BAAANQADCgMIAwAAAA==.',
Rw='Rwlmaster:BAABNQAECn8sAAIGAAkKahLPRADoAQAGAAkKahLPRADoAQAAAA==.',
Sa='Sandwiches:BAAANQAECgEIAQABNQAECgQICgAFAAAAAA==.',
Sc='Scerra:BAABNQAECn84AAMCAAoKxRaBKAACAgACAAoKxRaBKAACAgANAAMKogJewQBoAAAAAA==.Scridders:BAABNQAECn8YAAIDAAkK7xRVSwDTAQADAAkK7xRVSwDTAQAAAA==.Scridderz:BAAANQAECgEIAQAAAA==.Scriddle:BAAANQAECgUIBAAAAA==.Scridman:BAAANQADCgEIAQAAAA==.',
Se='Secre:BAAANQADCgQJBAABNQAECgIIAwAFAAAAAA==.Sellandre:BAAANQADCgYIBgABNQAECgoKHwAgANQVAA==.Seru:BAAANQAECgUICwAAAA==.',
Sh='Shamarha:BAABNQAECn8xAAMcAAoKSBxkHwCtAgAcAAoKSBxkHwCtAgAdAAEKAAAqHAEAAAAAAA==.Shamonbo:BAAANQADCgUIBQABNQAECgoKJAAEAHwWAA==.Sharriavolf:BAABNQAECn8cAAMIAAcKPR3dmgCjAQAIAAUK+RzdmgCjAQAJAAIKox1lSQCjAAAAAA==.Shion:BAAANQAECgQIBAABNQAFFAcIIQAPAIgeAA==.Shreder:BAAANQADCgIIAgAAAA==.Shuma:BAAANQADCgUIBgAAAA==.',
Si='Simichaelton:BAECNQAFFH8GAAMgAAIKTBHOEgBJAAAEAAEKbRIhWABQAAAgAAEKKxDOEgBJAAA1AAQKf0QAAyAACgoGGxAbABoBAAQACQpoGcN1ALABACAABAp+HBAbABoBAAE1AAUUBggLAB4A6AwA.Sinahi:BAAANQAECgEIAQAAAA==.Sinpal:BAAANQAECgcIDAAAAA==.Sinthea:BAAANQAECggIAwAAAA==.',
Sn='Sneakysoul:BAACNQAFFH8KAAMSAAIKlAVqFACmAAASAAIKlAVqFACmAAAfAAEKAACdKQAAAAA1AAQKfzEAAxIACgo3IqwDAPoCABIACgo3IqwDAPoCAB8ACArcE8BRAKABAAAA.',
So='Solyn:BAABNQAECn8YAAIQAAcKQwal8QA5AQAQAAcKQwal8QA5AQAAAA==.Sonea:BAAANQADCgEIAQAAAA==.Sonic:BAAANQADCgUIBQAAAA==.',
Sp='Spagooti:BAAANQAECgYIDAAAAA==.Spanxya:BAAANQADCgQIBAAAAA==.Spartaaxd:BAABNQAECn8ZAAICAAkKswwNRgCoAQACAAkKswwNRgCoAQAAAA==.',
St='Stabbard:BAAANQADCgQIBAAAAA==.Stagerrind:BAAANQADCgMIAwAAAA==.Starfall:BAAANQAECgEIAwAAAA==.Steiner:BAAANQADCgUIBwAAAA==.Stejamarha:BAAANQADCgQIBAAAAA==.',
Su='Sugarseer:BAABNQAECn8ZAAIcAAoKcxN2UwAZAgAcAAoKcxN2UwAZAgAAAA==.Suka:BAAANQAECgEIAQAAAA==.Suzi:BAABNQAECn8fAAIOAAkKGQjkngBaAQAOAAkKGQjkngBaAQAAAA==.',
Sw='Swiftleaf:BAAANQADCggICAAAAA==.',
Sy='Syevoid:BAAANQADCgIIAwAAAA==.Sylentcurse:BAAANQAECgUICwABNQAECgoKKQAOAMkPAA==.Sylentstorm:BAAANQAECgEIAQABNQAECgoKKQAOAMkPAA==.Sylentwolvez:BAAANQAECgYIDQAAAA==.Syleta:BAAANQADCgEIAQABNQAECgkJMgACAKsWAA==.Sylvarus:BAAANQADCgQIBAAAAA==.',
Ta='Tabraxis:BAAANQADCgYIBwAAAA==.Tagalorc:BAABNQAECn8gAAIEAAgKrQrgtQAnAQAEAAgKrQrgtQAnAQAAAA==.Takamaki:BAAANQAECgEIAQAAAA==.Talionwrite:BAAANQAECgcIEwAAAA==.Tanksbacon:BAAANQAECgUIBQAAAA==.',
Te='Teana:BAAANQAECgcIEAAAAA==.Tempestas:BAAANQADCgYICAAAAA==.',
Th='Thechadd:BAAANQAECggIDgAAAA==.Thelegendáry:BAABNQAECn86AAMcAAkKeR6dNwCBAgAcAAkKeR6dNwCBAgAdAAEKRhIs+wAuAAAAAA==.Themigrant:BAAANQABCgUIBQAAAA==.Therosewood:BAAANQAECgcICgAAAA==.Thorgrimm:BAAANQADCgYIBgAAAA==.Thraine:BAABNQAECn8aAAIKAAgKbxDRbAClAQAKAAgKbxDRbAClAQAAAA==.Threedog:BAAANQADCgIIAgAAAA==.',
Ti='Tione:BAABNQAECn8jAAMUAAkKXxvBEQCSAgAUAAkKXxvBEQCSAgAVAAEKAABOwAAhAAAAAA==.',
To='Toadvoker:BAABNQAECn8lAAMYAAoK+hb/EwBuAgAYAAoK+hb/EwBuAgAZAAEKxwB0KQARAAAAAA==.Topao:BAAANQADCgYIBgABNQAECgQICQAFAAAAAA==.Toriee:BAAANQAECggICAAAAA==.Totembish:BAABNQAECn8hAAIdAAkK4Al7XwBQAQAdAAkK4Al7XwBQAQAAAA==.',
Tr='Trisstan:BAABNQAECn8iAAIgAAYKBwi2IADjAAAgAAYKBwi2IADjAAAAAA==.Trollthrall:BAAANQAECgUICgAAAA==.',
Ty='Tyster:BAACNQAFFH8LAAIQAAQKEQmrFwDBAAAQAAQKEQmrFwDBAAA1AAQKfy4AAhAACgppHWJfAHsCABAACgppHWJfAHsCAAAA.',
['Tï']='Tïghtgrïp:BAABNQAECn81AAQCAAoKmRxhIQAxAgACAAoK1BthIQAxAgAGAAcKnR22NQBhAQANAAIK2gjTzgBPAAAAAA==.',
['Tø']='Tørmented:BAAANQADCgUIBQAAAA==.',
Un='Undol:BAAANQADCggIGgABNQAECgcIJQATAJcDAA==.',
Va='Vaellborn:BAAANQADCgEIAQAAAA==.Vandress:BAAANQADCgMIAQABNQAECgQICQAFAAAAAA==.',
Ve='Velobeef:BAAANQADCgEIAQAAAA==.Veloth:BAACNQAFFH8aAAMgAAcKIhWZAAB7AQAgAAcKIhWZAAB7AQAEAAMKbA0IOgDdAAA1AAQKf0cAAyAACgpFJZ4BAHQDACAACgpqJJ4BAHQDAAQACQqYHrtIAPECAAAA.Verminus:BAABNQAECn8bAAQUAAkKVwwgNgBrAQAUAAgKNAwgNgBrAQAVAAYKCgapcwD8AAAWAAEK6gZqSAApAAAAAA==.',
Vi='Viggle:BAAANQADCgUICAABNQAECgcIJgARAKsVAA==.Viho:BAABNQAECn8yAAIQAAoK9RNjmgDuAQAQAAoK9RNjmgDuAQAAAA==.Vilekin:BAAANQAECgUIBwAAAA==.Vithaxa:BAAANQAECgMICAAAAA==.',
Vo='Voidra:BAAANQAECgEIAQAAAA==.',
Vy='Vyinson:BAAANQAECgQIBAABNQAECgUIDQAFAAAAAA==.',
Wa='Warloque:BAAANQADCgMIAwAAAA==.',
We='Weechuup:BAAANQAECgUIDAAAAA==.',
Wi='Wifeotusk:BAAANQAECgQIBAAAAA==.Wiggle:BAAANQADCgYICwAAAA==.Willmar:BAABNQAECn8iAAIQAAcKRwog8gDqAAAQAAcKRwog8gDqAAAAAA==.Windrun:BAAANQAECgUIDwAAAA==.',
Wo='Wolf:BAABNQAECn8jAAIhAAoKRhKSGQDdAQAhAAoKRhKSGQDdAQAAAA==.Woodtique:BAAANQADCggIJgAAAA==.',
Wu='Wulthan:BAAANQADCgYICwAAAA==.',
Xa='Xandercruise:BAAANQAECgEIAQAAAA==.',
Xe='Xelphie:BAAANQAECgMIBQAAAA==.',
Xu='Xuchilbara:BAABNQAECn8WAAIWAAYKXx3FEAD7AQAWAAYKXx3FEAD7AQAAAA==.',
Ya='Yamato:BAABNQAECn8YAAIQAAkKRQ+toAB3AQAQAAkKRQ+toAB3AQAAAA==.',
Za='Zaledron:BAABNQAECn8VAAINAAgK4gytOQAgAQANAAgK4gytOQAgAQAAAA==.',
Zb='Zbelladonna:BAAANQADCggIEgABNQAECgoKWgACAB0jAA==.',
Ze='Zezera:BAAANQAECgUICQAAAA==.',
Zh='Zhades:BAABNQAECn9aAAMCAAoKHSOgBQCGAwACAAoKHSOgBQCGAwANAAkKOBEuWwCjAQAAAA==.Zhort:BAAANQAECgIIAgAAAA==.',
Zi='Zioki:BAAANQADCggICQAAAA==.',
Zo='Zodgul:BAAANQADCggICAAAAA==.Zomby:BAEBNQAECn8kAAIGAAoKKBMwIQDhAQAGAAoKKBMwIQDhAQABNQAFFAYICwAeAOgMAA==.',
Zu='Zultan:BAABNQAECn9AAAIIAAoKUQobcwBsAQAIAAoKUQobcwBsAQAAAA==.',
Zy='Zynblasted:BAAANQADCgQIBAAAAA==.Zynhunter:BAAANQADCgYIGgAAAA==.',
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
