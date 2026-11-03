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

local lookup = {'DemonHunter-Vengeance','DeathKnight-Blood','Paladin-Holy','Mage-Arcane','Unknown-Unknown','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','DeathKnight-Frost','Priest-Holy','Warrior-Fury','DeathKnight-Unholy','Hunter-BeastMastery','DemonHunter-Devourer','Paladin-Retribution','Paladin-Protection','Rogue-Assassination','Shaman-Enhancement','Druid-Restoration','Druid-Balance','Druid-Feral','Priest-Shadow','DemonHunter-Havoc','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Rogue-Subtlety','Mage-Frost','Evoker-Preservation','Evoker-Augmentation','Druid-Guardian',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abberleigh:BAAANQAECgQIBwAAAA==.Abron:BAAANQAECgIIAgAAAA==.',
Ad='Adahma:BAAANQADCgYIEQABNQAECgcIIgABAKQIAA==.Adelerock:BAAANQAECgUIBwAAAA==.',
Ae='Aerostotle:BAAANQAECgcICQAAAA==.',
Ag='Aganoth:BAAANQAECgcJEAAAAA==.',
Al='Alaraa:BAAANQADCgUIBwABNQAECgkJLQACAAoVAA==.Algonq:BAAANQAECgEIAQABNQAECgYIHgADAFQDAA==.Alkamaz:BAABNQAECn8bAAIEAAkKxAvd9gCeAQAEAAkKxAvd9gCeAQAAAA==.Alkiris:BAAANQADCgEIAQABNQAECgQIBQAFAAAAAA==.Alsisst:BAAANQAECgEIAQAAAA==.Alssar:BAAANQAECgIIAgAAAA==.Alstar:BAABNQAECn8hAAICAAoKQBPASgDMAQACAAoKQBPASgDMAQAAAA==.Alynis:BAAANQADCgQIBAAAAA==.',
Am='Amac:BAAANQADCgUIBQAAAA==.Amathus:BAABNQAECn9OAAQGAAoK7BTNBAAGAgAGAAoK7BTNBAAGAgAHAAYKRhCMwQBIAQAIAAIKwwvBMAA3AAAAAA==.',
An='Andarial:BAAANQAECgYICwAAAA==.Andreth:BAAANQAECgQICAAAAA==.Anoxyn:BAAANQAECgQIBAAAAA==.Anthe:BAAANQADCgUIFAAAAA==.',
Ar='Arcanmaggy:BAAANQAECgIIAQABNQAFFAQIBQAHAJsEAA==.Arcee:BAAANQADCgQIBgAAAA==.Ares:BAABNQAECn8ZAAIJAAcKKA7ElQAeAQAJAAcKKA7ElQAeAQABNQADCgMJAwAFAAAAAA==.Aryxi:BAAANQADCgUJBQABNQADCgMJAwAFAAAAAA==.',
As='Asiägo:BAAANQABCgcJCgAAAA==.Assassynmike:BAAANQAECgEIAQAAAA==.',
At='Atlas:BAAANQAECgYIDgAAAA==.',
Ba='Baelhal:BAABNQAECn89AAMCAAoK1BY2IADMAQACAAkK5hc2IADMAQAKAAEKVQ/OmwA4AAAAAA==.',
Be='Bearden:BAAANQADCgMIAgAAAA==.Bearypotter:BAAANQADCgUIBQAAAA==.Benedin:BAAANQADCgcJDAABNQAECgoKKAALAM0eAA==.',
Bi='Bigtex:BAABNQAECn8iAAIMAAcKhgdcGgD/AAAMAAcKhgdcGgD/AAAAAA==.Biped:BAABNQAECn8sAAIGAAkKERU8CAAOAgAGAAkKERU8CAAOAgAAAA==.Bishul:BAAANQAECgQIBgAAAA==.',
Bl='Blackdeath:BAABNQAECn8lAAINAAoKVxAkIACuAQANAAoKVxAkIACuAQAAAA==.Bloodsport:BAAANQADCgIIAgAAAA==.',
Bo='Bofadees:BAAANQADCggIFAAAAA==.Boloevo:BAAANQADCgUIBQABNQAECgYIEgAFAAAAAA==.Bolopal:BAAANQAECgIIAgABNQAECgYIEgAFAAAAAA==.Boolin:BAAANQADCgQIBAABNQAECgoKKAAIAIQgAA==.Boomstique:BAABNQAECn8iAAIOAAcK7BBUmwA3AQAOAAcK7BBUmwA3AQAAAA==.Boondocka:BAABNQAECn8oAAIOAAkKzhbYUAB9AgAOAAkKzhbYUAB9AgAAAA==.',
Br='Brex:BAAANQAECggIAQAAAA==.Brissennissa:BAABNQAECn8sAAIPAAkK5hzjEgDUAgAPAAkK5hzjEgDUAgAAAA==.Brokkr:BAAANQADCggIEwAAAA==.Bronar:BAAANQADCgMIAwAAAA==.Brutalís:BAABNQAECn8lAAIOAAkKng40bQCeAQAOAAkKng40bQCeAQAAAA==.Brèwtality:BAAANQADCgUICwAAAA==.',
Bt='Btrain:BAABNQAECn8YAAIQAAYKvgbfBQGnAAAQAAYKvgbfBQGnAAAAAA==.',
Bu='Bubblebae:BAAANQADCggIFgABNQAECgYIDAAFAAAAAA==.',
['Bó']='Bóunty:BAABNQAECn8cAAIOAAgKoiMcVgBwAgAOAAgKoiMcVgBwAgAAAA==.',
Ca='Calypsto:BAAANQAECgIIAgAAAA==.',
Ce='Cenobité:BAABNQAECn8oAAIKAAkKLA/UNQCOAQAKAAkKLA/UNQCOAQAAAA==.',
Ch='Chialing:BAAANQAECgYIEwAAAA==.Chickenhead:BAAANQAECgEIAgAAAA==.Chip:BAAANQADCggIIgAAAA==.Chromefury:BAAANQADCgQIBAAAAA==.Chuckfinley:BAAANQAECgIIAwAAAA==.Chuong:BAAANQADCgIIAgABNQAECgUICAAFAAAAAA==.',
Ci='Cirax:BAABNQAECn8gAAIOAAcK+hWchgBiAQAOAAcK+hWchgBiAQAAAA==.',
Cl='Classic:BAAANQADCgYIDQABNQAECgcIIgARAKsVAA==.Cleetess:BAAANQADCgYIDgAAAA==.Clenton:BAABNQAECn9BAAIRAAoK/gwjHQBQAQARAAoK/gwjHQBQAQAAAA==.Clown:BAAANQAECgUIBwAAAA==.',
Co='Cobrakai:BAAANQADCgEIAQAAAA==.Cosplay:BAAANQAECgcIEwABNQAFFAIICgASAJQFAA==.',
Cr='Crichton:BAABNQAECn9BAAIPAAoKMiK8BwBWAwAPAAoKMiK8BwBWAwAAAA==.Crowford:BAABNQAECn8ZAAIOAAgKxwohpwAfAQAOAAgKxwohpwAfAQAAAA==.',
Cy='Cyris:BAAANQADCgcIDgABNQAECgcIIQATAJcDAA==.',
['Cá']='Cástle:BAABNQAECn8YAAIEAAgKuhcbSQANAgAEAAgKuhcbSQANAgAAAA==.',
Da='Daemonhanta:BAAANQABCgEIAQAAAA==.Daevahna:BAAANQADCggIEQAAAA==.Dak:BAABNQAECn82AAMRAAoK3hhSEgB9AgARAAkKgBpSEgB9AgAQAAoKxBAIYADYAQAAAA==.Daksmash:BAAANQAECgYICgABNQAECgoKNgARAN4YAA==.Dakstorm:BAABNQAECn8nAAITAAoKGBk+CQBeAgATAAoKGBk+CQBeAgABNQAECgoKNgARAN4YAA==.Darkmiza:BAACNQAFFH8FAAIHAAQKmwRdGAC1AAAHAAQKmwRdGAC1AAA1AAQKfywAAgcACgpcEzNxAAwCAAcACgpcEzNxAAwCAAAA.Dawnstrike:BAAANQAECgEIAQAAAA==.',
De='Deadmangalad:BAAANQADCggIHQAAAA==.Deedees:BAAANQAECgQICgAAAA==.Demonhandler:BAAANQADCgUICQAAAA==.Demonikk:BAAANQAECgQICQAAAA==.Deo:BAAANQAECgYIDAABNQAFFAIICgASAJQFAA==.Depression:BAAANQAECggIBwAAAA==.',
Di='Dies:BAAANQAECggIAgAAAA==.Diioo:BAAANQAECgMIBQAAAA==.Dirtnåp:BAAANQAECgEIAQAAAA==.Diskbänk:BAAANQADCgUIBQAAAA==.',
Dr='Dragontoast:BAAANQAECgQIBwAAAA==.Drama:BAAANQAECgUIBQAAAA==.Druidïan:BAABNQAECn8bAAMUAAgKYBGvIQCbAQAUAAgKYBGvIQCbAQAVAAIKHgJRgwAoAAAAAA==.',
Dy='Dynwor:BAAANQADCggICwAAAA==.',
Ea='Easme:BAAANQAECgcIEAAAAA==.',
El='Elaric:BAAANQAECgYICQAAAA==.',
En='Engi:BAABNQAECn8pAAMJAAkKTBDGkQDwAQAJAAkKTBDGkQDwAQAMAAEKjQV/LQAsAAAAAA==.Enhuna:BAAANQADCgIIAgAAAA==.',
Es='Escaper:BAABNQAECn8nAAIKAAgKwxTDMwAPAgAKAAgKwxTDMwAPAgAAAA==.',
Ev='Eversteel:BAAANQADCgUIBQABNQAECgcIIgARAKsVAA==.',
Ex='Extrema:BAAANQAECgQIBwAAAA==.',
Fe='Felesha:BAAANQADCgQIBAAAAA==.',
Fh='Fhait:BAAANQAECgEIAQABNQAECgcIIgABAKQIAA==.',
Fi='Fionab:BAAANQADCgIIAgAAAA==.',
Fo='Foxfu:BAAANQADCgYICwAAAA==.',
Fr='Frost:BAAANQAECgEIAQAAAA==.',
Fu='Fujika:BAAANQADCgQIBAAAAA==.',
Ga='Galadan:BAABNQAECn8XAAIWAAYKGgWgJgDYAAAWAAYKGgWgJgDYAAABNQADCggIHQAFAAAAAA==.Garius:BAAANQAECgcIEQAAAA==.Garrekton:BAABNQAECn8oAAMLAAoKzR6hIwCUAgALAAoKzR6hIwCUAgAXAAEKAACghQAjAAAAAA==.Gaskelmarg:BAAANQADCgYIHQAAAA==.',
Ge='Gellane:BAAANQAECgMIAwAAAA==.',
Gh='Ghozt:BAAANQADCgUICgABNQAECggIGAAEALoXAA==.',
Gl='Glory:BAABNQAECn8mAAMDAAkKfRhrLgCtAgADAAkKfRhrLgCtAgAQAAEKYwocZAE6AAAAAA==.',
Go='Goldtusk:BAAANQAECgUIDQAAAA==.',
Gr='Graveyard:BAAANQAECgEIAwABNQAECggIGAAEALoXAA==.Grundler:BAAANQAECgEIAQAAAA==.Gryphone:BAAANQADCggIEAAAAA==.',
Ha='Hakmud:BAAANQAECgEIAQAAAA==.Harandee:BAAANQADCgYICwAAAA==.Hasmus:BAAANQADCgUIBQAAAA==.Haufa:BAAANQAECgIIAwAAAA==.',
He='Headstrong:BAAANQADCgcIBwAAAA==.Hettokal:BAAANQADCgQIBAAAAA==.Heximal:BAAANQADCgQIBwABNQAECgkJKAAOAM4WAA==.',
Ho='Hondojoe:BAEBNQAECn8xAAMLAAoKwBedIgCbAgALAAoKwBedIgCbAgAXAAkKWQ1MGQCYAQAAAA==.Honey:BAAANQAECggICgAAAA==.Honeydrake:BAAANQAECggIEwAAAA==.Hopewell:BAABNQAECn8eAAIDAAYKVANoqAChAAADAAYKVANoqAChAAAAAA==.',
Hu='Hugnsnuggle:BAABNQAECn8iAAIBAAcKpAh5FgC8AAABAAcKpAh5FgC8AAAAAA==.Huhu:BAAANQAECggIDAAAAA==.Humilitas:BAAANQADCgUICQAAAA==.',
['Hä']='Häväç:BAAANQADCgQIBQAAAA==.',
Ib='Ibn:BAABNQAECn8oAAIJAAkKqQf7fwBQAQAJAAkKqQf7fwBQAQAAAA==.',
Il='Illadus:BAAANQADCgYICwAAAA==.Illidab:BAABNQAECn8lAAIYAAoKtxyBFAD5AgAYAAoKtxyBFAD5AgAAAA==.',
In='Infectus:BAABNQAECn8YAAMNAAkKgQM9rACcAAANAAgKTQM9rACcAAAKAAkKvgHUlABsAAAAAA==.',
Ir='Irielle:BAAANQADCgcILQAAAA==.',
Iv='Ivylyn:BAAANQAECggIEgAAAA==.',
Ix='Ixiyá:BAABNQAECn8lAAIZAAoKGCUqBQCeAwAZAAoKGCUqBQCeAwAAAA==.Ixií:BAAANQADCgYIBgAAAA==.Ixì:BAAANQADCgEIAQAAAA==.',
Ja='Jakbenimble:BAAANQADCgcIDQAAAA==.Jakeyprogue:BAAANQAECgMIBQAAAA==.Jakota:BAAANQADCggIHAAAAA==.Jakskeleton:BAABNQAECn8fAAICAAcK7A2aSADxAAACAAcK7A2aSADxAAAAAA==.',
Je='Jeamica:BAAANQADCggIEAAAAA==.Jethroy:BAAANQADCgQIBAAAAA==.',
Jo='Joerollin:BAEANQADCggICQABNQAECgoKMQALAMAXAA==.Johnjrambo:BAAANQADCgcIBwAAAA==.',
Ju='Judax:BAABNQAECn8yAAIaAAoK8hX0TwA4AgAaAAoK8hX0TwA4AgAAAA==.Justagirl:BAABNQAECn8gAAIbAAcK7gYuRQDxAAAbAAcK7gYuRQDxAAABNQAECgcIIgABAKQIAA==.Juti:BAAANQADCggIHAAAAA==.Juvu:BAAANQADCgQIBAAAAA==.',
Ka='Kadooka:BAABNQAECn8jAAIOAAkK4BV7UwDkAQAOAAkK4BV7UwDkAQAAAA==.Kahlyn:BAAANQADCgQIBAAAAA==.Kai:BAAANQAECgYIEAAAAA==.Kaldaran:BAAANQAECgEIAgABNQAFFAQIBQAJAMIPAA==.Kallan:BAAANQADCgQJBAABNQAECgcIIgARAKsVAA==.Kaléanor:BAACNQAFFH8FAAIJAAQKwg/NFwDKAAAJAAQKwg/NFwDKAAA1AAQKfygAAgkACgrQIXQXANgCAAkACgrQIXQXANgCAAAA.Karen:BAAANQADCgUIBwAAAA==.Katabell:BAABNQAECn8iAAMXAAcKjQSFNwCmAAAXAAcKjQSFNwCmAAALAAQKHwYvtgCRAAAAAA==.Katira:BAAANQADCgcIEAAAAA==.',
Ke='Keeganw:BAAANQAECgYIEAAAAA==.Keelay:BAAANQAECgcIDwAAAA==.Kelste:BAAANQAECggIDgAAAA==.',
Ki='Killaclowns:BAAANQADCgUIEwAAAA==.Killjadan:BAAANQAECgMIAwAAAA==.Kimiko:BAAANQAECgEIAQAAAA==.Kioki:BAAANQADCggIEAAAAA==.',
Kl='Klitess:BAAANQADCgYICAAAAA==.',
Ko='Kodrac:BAAANQAECgEIAQAAAA==.Koffcmorbius:BAAANQADCggIHwAAAA==.Kostian:BAAANQADCgUICQABNQAECgcIIgARAKsVAA==.',
Kr='Kraken:BAABNQAECn8oAAIIAAoKhCClAQBpAwAIAAoKhCClAQBpAwAAAA==.',
Ku='Kubb:BAABNQAECn8hAAITAAcKlwN6IADeAAATAAcKlwN6IADeAAAAAA==.',
Kw='Kweh:BAACNQAFFH8KAAIWAAQKOBTjAQCwAAAWAAQKOBTjAQCwAAA1AAQKfywAAhYACgrYHx0GABADABYACgrYHx0GABADAAAA.',
['Kê']='Kêlsen:BAAANQAECgIIAQAAAA==.',
La='Laero:BAAANQADCgYICwABNQAECgcIIQATAJcDAA==.Larrissa:BAAANQADCgcIGQAAAA==.Laurlynn:BAAANQADCgYICwAAAA==.',
Le='Lenwe:BAAANQAECgQICAABNQAECgUICAAFAAAAAA==.Lettuceprey:BAAANQAECgMIBwAAAA==.',
Li='Lierise:BAAANQADCgcIDgAAAA==.Lilindra:BAABNQAECn8tAAQCAAkKChUUUgDNAAAKAAcKdxPKXQAwAQANAAcKHxOTgQAYAQACAAYKRg4UUgDNAAAAAA==.Lillymay:BAAANQAECgEIAQAAAA==.Lilspazz:BAAANQAECgQIBwAAAA==.',
Ll='Lluiz:BAAANQAECgEIAQAAAA==.',
Lo='Lockdeath:BAAANQAECgEIAQAAAA==.Logoruk:BAAANQADCgQIBAAAAA==.Lorelleya:BAAANQADCgEIAQAAAA==.Loxia:BAAANQAECgYIDAAAAA==.',
Lu='Lucille:BAAANQADCgYIBgAAAA==.Luckett:BAAANQADCgMJAwAAAA==.Lui:BAAANQAECgIIAgAAAA==.Lumi:BAAANQAECgUIDAAAAA==.',
Ma='Maavarra:BAABNQAECn8VAAIWAAYK1hi6EwBBAQAWAAYK1hi6EwBBAQAAAA==.Madischa:BAAANQAECgIIBQAAAA==.Madshaggy:BAABNQAECn8vAAIRAAkKZxnwEwCxAQARAAkKZxnwEwCxAQAAAA==.Magicdance:BAAANQAECgUIBQABNQAFFAEIAQAFAAAAAA==.Magikern:BAAANQADCgMIAwABNQADCgUIBQAFAAAAAA==.Magy:BAAANQADCgIIAgAAAA==.Mahallomi:BAAANQADCgQIBAAAAA==.Maki:BAAANQAECgMIBQAAAA==.Maldreth:BAAANQADCgYIBgAAAA==.Maxlin:BAABNQAECn8ZAAIWAAgK+BIWGAAIAQAWAAgK+BIWGAAIAQAAAA==.',
Me='Mehänemäntä:BAAANQADCggIEgAAAA==.Melarii:BAAANQADCgYIEQAAAA==.Merixa:BAAANQAECgQICgAAAA==.',
Mi='Midou:BAAANQAFFAEIAQAAAA==.Misstreater:BAAANQAECgUIDAAAAA==.',
Mo='Momentomori:BAABNQAECn8dAAIHAAoKqwb8zQAuAQAHAAoKqwb8zQAuAQAAAA==.Monbeau:BAABNQAECn8kAAIEAAoKfBbQZAC0AgAEAAoKfBbQZAC0AgAAAA==.Monocerotis:BAABNQAECn81AAIKAAoKABEXJwDjAQAKAAoKABEXJwDjAQAAAA==.Moosebear:BAAANQADCgYIBgAAAA==.Morishima:BAABNQAECn9QAAMcAAoKpCHkDwDcAgASAAkKpBtmEwDhAgAcAAoKNSHkDwDcAgAAAA==.',
Mu='Multipàss:BAAANQADCgQIBQAAAA==.',
My='Mydarling:BAACNQAFFH8IAAMDAAUK/BNhFwDtAAADAAMK6AxhFwDtAAAQAAMK0wMSIQCdAAA1AAQKfzAAAxAACgo8GvR4ADoCABAACQr6GPR4ADoCAAMABgpkFC20ABYBAAAA.Mymoon:BAAANQAECgcIDQAAAA==.Myris:BAABNQAECn8jAAINAAgKtx2jLQB8AgANAAgKtx2jLQB8AgAAAA==.',
['Mî']='Mîsgüïdëð:BAAANQAECgEIAQAAAA==.',
Na='Naturalchi:BAABNQAECn8oAAIbAAkKBx2hFQClAgAbAAkKBx2hFQClAgAAAA==.',
Nb='Nbi:BAAANQAECgEIAQAAAA==.',
Ne='Nefilion:BAAANQAECgIIBAAAAA==.Nefy:BAAANQAECgUIDAAAAA==.Nezin:BAAANQADCgMJAwAAAA==.',
Ni='Nightrunnêr:BAAANQAECgEIAQABNQAECgcIIgARAKsVAA==.Niselo:BAAANQADCgUIBQAAAA==.',
No='Nogods:BAAANQAECgEIAQAAAA==.Nohzul:BAACNQAFFH8RAAIaAAcKnhjmBgBEAQAaAAcKnhjmBgBEAQA1AAQKfycAAhoACgroJPQJABEDABoACgroJPQJABEDAAAA.Nomik:BAAANQAECgUICAAAAA==.Nonah:BAAANQADCgYIBwAAAA==.',
Nu='Nullspace:BAABNQAECn8gAAMLAAoKERuyQABoAgALAAoKERuyQABoAgAXAAIKngm2WQAsAAAAAA==.',
Ny='Nyleelyr:BAAANQAECgMIAwAAAA==.',
['Ní']='Níght:BAAANQAECgEIAQAAAA==.',
Or='Orgresh:BAAANQADCggICAAAAA==.Orym:BAAANQAECgcIEAAAAA==.',
Pa='Palacia:BAABNQAECn8gAAMRAAgKTQ6AMQBUAQARAAYK9xOAMQBUAQAQAAcKXAMEIgGCAAAAAA==.Pallythetank:BAABNQAECn8VAAMRAAcKyQdtNQCvAAARAAcKyQdtNQCvAAAQAAMKlwFAkwFBAAAAAA==.Pappabeary:BAAANQAECgEIAQAAAA==.',
Pe='Peerow:BAAANQADCgcIKAAAAA==.Petrichorica:BAAANQADCgcICgAAAA==.',
Pi='Pintobeans:BAABNQAECn8UAAIOAAgK9APk6AAvAQAOAAgK9APk6AAvAQAAAA==.',
Po='Popeadin:BAAANQADCgQIBgAAAA==.',
Pr='Preachêr:BAAANQABCgQIBAABNQAECgcIIgARAKsVAA==.Primeatheist:BAABNQAECn8ZAAIXAAkK9xfvEgDzAQAXAAkK9xfvEgDzAQAAAA==.',
Pu='Puuhceew:BAABNQAECn8fAAILAAkKYghuZAB2AQALAAkKYghuZAB2AQAAAA==.',
Qu='Quina:BAAANQADCgMIAwAAAA==.',
Ra='Rainbrews:BAAANQAECgEIAQAAAA==.Rainera:BAABNQAECn8rAAIGAAkKXR+CAwC9AgAGAAkKXR+CAwC9AgABNQAFFAUIEAABAEIjAA==.Ramanas:BAAANQAECgYICgAAAA==.Ramrod:BAAANQAECgYIDQAAAA==.Ramstank:BAAANQAECgMIBQAAAA==.Rattles:BAAANQAECgIIAwAAAA==.',
Re='Redgicide:BAAANQAECgYIDwABNQAECgkJKAAOAM4WAA==.Releafme:BAACNQAFFH8UAAIUAAcKcxq2AgANAgAUAAcKcxq2AgANAgA1AAQKfzgAAhQACgqOJaQBALsDABQACgqOJaQBALsDAAAA.Resurgencê:BAABNQAECn8iAAIRAAcKqxXuJAC5AQARAAcKqxXuJAC5AQAAAA==.',
Ri='Riordan:BAABNQAECn8XAAIQAAgK7Qti5gBOAQAQAAgK7Qti5gBOAQAAAA==.',
Ro='Rojeton:BAAANQADCgIIAgAAAA==.Rothema:BAABNQAECn8dAAIaAAYK9gN50gDvAAAaAAYK9gN50gDvAAAAAA==.Routh:BAAANQAECgEIAQAAAA==.',
Ru='Rubberbizkit:BAAANQADCgMIAwAAAA==.Rubee:BAAANQADCgMIAwAAAA==.',
Rw='Rwlmaster:BAABNQAECn8pAAICAAkK8hHPRADoAQACAAkK8hHPRADoAQAAAA==.',
Sa='Sandwiches:BAAANQAECgEIAQABNQAECgUIBwAFAAAAAA==.',
Sc='Scerra:BAABNQAECn80AAMKAAoKUxXoJQDrAQAKAAoKUxXoJQDrAQANAAMKogJewQBoAAAAAA==.Scridders:BAABNQAECn8YAAIDAAkK7xSsQADeAQADAAkK7xSsQADeAQAAAA==.Scridderz:BAAANQAECgEIAQAAAA==.Scriddle:BAAANQAECgUIBQAAAA==.',
Se='Secre:BAAANQADCgQJBAABNQAECgMIBQAFAAAAAA==.Sellandre:BAAANQADCgYIBgABNQAECgoKHwAdANQVAA==.Seru:BAAANQAECgQIBwAAAA==.',
Sh='Shamarha:BAABNQAECn8qAAMZAAoKSBzeGQC7AgAZAAoKSBzeGQC7AgAaAAEKAACoCAEAAAAAAA==.Shamonbo:BAAANQADCgUIBQABNQAECgoKJAAEAHwWAA==.Sharriavolf:BAABNQAECn8cAAMHAAcKPR3dmgCjAQAHAAUK+RzdmgCjAQAIAAIKox1lSQCjAAAAAA==.Shion:BAAANQAECgQIBAABNQAFFAcIIQAPAIgeAA==.Shreder:BAAANQADCgIIAgAAAA==.Shuma:BAAANQADCgYIBgAAAA==.',
Si='Simichaelton:BAECNQAFFH8GAAMdAAIKTBHOEgBJAAAEAAEKbRIhWABQAAAdAAEKKxDOEgBJAAA1AAQKf0EAAx0ACgqxGhAbABoBAAQACQqhF210AJYBAB0ABAp+HBAbABoBAAAA.Sinahi:BAAANQAECgEIAQAAAA==.Sinpal:BAAANQAECgcIDAAAAA==.Sinthea:BAAANQAECggIAwAAAA==.',
Sn='Sneakysoul:BAACNQAFFH8KAAMSAAIKlAVqFACmAAASAAIKlAVqFACmAAAcAAEKAAA3JQAAAAA1AAQKfzEAAxIACgo3Iv4CAAQDABIACgo3Iv4CAAQDABwACArcE2NFAJ8BAAAA.',
So='Solyn:BAABNQAECn8YAAIQAAcKQwal8QA5AQAQAAcKQwal8QA5AQAAAA==.Sonic:BAAANQADCgUIBQAAAA==.',
Sp='Spagooti:BAAANQAECgYIDgAAAA==.Spanxya:BAAANQADCgQIBAAAAA==.Spartaaxd:BAABNQAECn8YAAIKAAgKnw0NRgCoAQAKAAgKnw0NRgCoAQAAAA==.',
St='Stabbard:BAAANQADCgQIBAAAAA==.Stagerrind:BAAANQADCgMIAwAAAA==.Starfall:BAAANQAECgEIBAAAAA==.Steiner:BAAANQADCgUIBwAAAA==.Stejamarha:BAAANQADCgQIBAAAAA==.',
Su='Sugarseer:BAABNQAECn8ZAAIZAAoKcxN2UwAZAgAZAAoKcxN2UwAZAgAAAA==.Suka:BAAANQAECgEIAQAAAA==.Suzi:BAABNQAECn8cAAIOAAgKlQdcrgARAQAOAAgKlQdcrgARAQAAAA==.',
Sw='Swiftleaf:BAAANQADCggICAAAAA==.',
Sy='Syevoid:BAAANQADCgIIAwAAAA==.Sylentcurse:BAAANQAECgUIDAABNQAECgkJJQAOAJ4OAA==.Sylentstorm:BAAANQAECgEIAQABNQAECgkJJQAOAJ4OAA==.Sylentwolvez:BAAANQAECgUICwAAAA==.Syleta:BAAANQADCgEIAQABNQAECgkJLQACAAoVAA==.Sylvarus:BAAANQADCgQIBAAAAA==.',
Ta='Tabraxis:BAAANQADCgYIBwAAAA==.Tagalorc:BAABNQAECn8fAAIEAAcKAAyzAgGJAQAEAAcKAAyzAgGJAQAAAA==.Takamaki:BAAANQADCgcIHgAAAA==.Talionwrite:BAAANQAECgUIEwAAAA==.Tanksbacon:BAAANQAECgUIBQAAAA==.',
Te='Teana:BAAANQAECgcIEAAAAA==.Tempestas:BAAANQADCgYICAAAAA==.',
Th='Thechadd:BAAANQAECggIDwAAAA==.Thelegendáry:BAABNQAECn84AAMZAAkK1xydNwCBAgAZAAkK1xydNwCBAgAaAAEKRhKL6QAuAAAAAA==.Themigrant:BAAANQABCgUIBQAAAA==.Therosewood:BAAANQAECgcIBwAAAA==.Thorgrimm:BAAANQADCgYIBgAAAA==.Thraine:BAABNQAECn8XAAIJAAcK3RCcdgBnAQAJAAcK3RCcdgBnAQAAAA==.Threedog:BAAANQADCgIIAgAAAA==.',
Ti='Tione:BAABNQAECn8hAAMUAAcKLR5JFgAfAgAUAAcKLR5JFgAfAgAVAAEKAABOwAAhAAAAAA==.',
To='Toadvoker:BAABNQAECn8lAAMeAAoK+hb/EwBuAgAeAAoK+hb/EwBuAgAfAAEKxwB0KQARAAAAAA==.Topao:BAAANQADCgYIBgABNQAECgQIBQAFAAAAAA==.Toriee:BAAANQAECgEIAQAAAA==.Totembish:BAABNQAECn8hAAIaAAkK4AkaVABQAQAaAAkK4AkaVABQAQAAAA==.',
Tr='Trisstan:BAABNQAECn8eAAIdAAYKBwi2IADjAAAdAAYKBwi2IADjAAAAAA==.Trollthrall:BAAANQAECgUICQAAAA==.',
Ty='Tyster:BAACNQAFFH8IAAIQAAMKYwn9HwB9AAAQAAMKYwn9HwB9AAA1AAQKfycAAhAACgppHWJfAHsCABAACgppHWJfAHsCAAAA.',
['Tï']='Tïghtgrïp:BAABNQAECn8uAAQKAAoKQRkVJQBqAgAKAAoKCRcVJQBqAgACAAcKnR2WLwBmAQANAAIK2gjTzgBPAAAAAA==.',
['Tø']='Tørmented:BAAANQADCgUIBQAAAA==.',
Un='Undol:BAAANQADCggIGgABNQAECgcIIQATAJcDAA==.',
Va='Vaellborn:BAAANQADCgEIAQAAAA==.Vandress:BAAANQADCgMIAQABNQAECgQIBQAFAAAAAA==.',
Ve='Velobeef:BAAANQADCgEIAQAAAA==.Veloth:BAACNQAFFH8aAAMdAAcKIhVrAACNAQAdAAcKIhVrAACNAQAEAAMKbA0IOgDdAAA1AAQKf0YAAx0ACgpFJZ4BAHQDAB0ACgpqJJ4BAHQDAAQACQqYHrtIAPECAAAA.Verminus:BAABNQAECn8bAAQUAAkKVwwgNgBrAQAUAAgKNAwgNgBrAQAVAAYKCgapcwD8AAAWAAEK6gZqSAApAAAAAA==.',
Vi='Viggle:BAAANQADCgUICAABNQAECgcIIgARAKsVAA==.Viho:BAABNQAECn8sAAIQAAkK6BJjmgDuAQAQAAkK6BJjmgDuAQAAAA==.Vilekin:BAAANQAECgUIBwAAAA==.Vithaxa:BAAANQAECgMICAAAAA==.',
Vo='Voidra:BAAANQAECgEIAQAAAA==.Voodoomike:BAAANQAECgIIBAAAAA==.',
Vy='Vyinson:BAAANQAECgQIBAABNQAECgUIDQAFAAAAAA==.',
Wa='Wallacehoyt:BAAANQAECgEIAQAAAA==.Warloque:BAAANQADCgMIAwAAAA==.',
We='Weechuup:BAAANQAECgQICQAAAA==.',
Wi='Wifeotusk:BAAANQAECgQIBAAAAA==.Wiggle:BAAANQADCgYICwAAAA==.Willmar:BAABNQAECn8eAAIQAAcKpAkw3wDhAAAQAAcKpAkw3wDhAAAAAA==.Window:BAAANQAECgEIAwABNQAECggIGAAEALoXAA==.Windrun:BAAANQAECgUIDAAAAA==.',
Wo='Wolf:BAABNQAECn8jAAIgAAoKRhLYGQB+AQAgAAoKRhLYGQB+AQAAAA==.Woodtique:BAAANQADCggIIQAAAA==.',
Wu='Wulthan:BAAANQADCgYICwAAAA==.',
Xa='Xandercruise:BAAANQAECgEIAQAAAA==.',
Xe='Xelphie:BAAANQAECgMIBQAAAA==.',
Xu='Xuchilbara:BAABNQAECn8WAAIWAAYKXx3FEAD7AQAWAAYKXx3FEAD7AQAAAA==.',
Ya='Yamato:BAABNQAECn8VAAIQAAgK+A6/rwAwAQAQAAgK+A6/rwAwAQAAAA==.',
Za='Zaledron:BAAANQAECgcIEwAAAA==.',
Zb='Zbelladonna:BAAANQADCggIEgABNQAECgoKWgAKAB0jAA==.',
Ze='Zezera:BAAANQAECgQIBQAAAA==.',
Zh='Zhades:BAABNQAECn9aAAMKAAoKHSOgBQCGAwAKAAoKHSOgBQCGAwANAAkKOBEuWwCjAQAAAA==.Zhort:BAAANQAECgIIAgAAAA==.',
Zi='Zioki:BAAANQADCggICQAAAA==.',
Zo='Zodgul:BAAANQADCggICAAAAA==.Zomby:BAEBNQAECn8gAAICAAoK5BJ2HQDlAQACAAoK5BJ2HQDlAQABNQAFFAIIBgAdAEwRAA==.',
Zu='Zultan:BAABNQAECn8/AAIHAAoKIQoMaABkAQAHAAoKIQoMaABkAQAAAA==.',
Zy='Zynblasted:BAAANQADCgQIBAAAAA==.Zynhunter:BAAANQADCgYIGgAAAA==.Zyuxis:BAAANQAECgEIAQABNQAECgYIBwAFAAAAAA==.',
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
