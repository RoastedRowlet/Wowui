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

local lookup = {'DemonHunter-Vengeance','Paladin-Retribution','DeathKnight-Frost','Paladin-Holy','Mage-Arcane','Unknown-Unknown','DeathKnight-Blood','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Priest-Holy','Warrior-Fury','DeathKnight-Unholy','Hunter-BeastMastery','DemonHunter-Devourer','Paladin-Protection','Rogue-Assassination','Shaman-Enhancement','Druid-Restoration','Druid-Balance','Druid-Feral','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Havoc','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Rogue-Subtlety','Mage-Frost','Druid-Guardian',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abberleigh:BAAANQAECgUICwAAAA==.Abron:BAAANQAECgIIAQAAAA==.',
Ad='Adahma:BAAANQADCgYIEQABNQAECgcIKgABAMQIAA==.Adelerock:BAAANQAECgUIBwAAAA==.',
Ae='Aerostotle:BAABNQAECn8WAAICAAcKSAoCCAERAQACAAcKSAoCCAERAQAAAA==.',
Ag='Aganoth:BAAANQAECgcJEAAAAA==.',
Al='Alaraa:BAAANQADCgUIBwABNQAECgoKNgADAA4XAA==.Algonq:BAAANQAECgIIAwABNQAECgYIJgAEAHcDAA==.Alkamaz:BAABNQAECn8dAAIFAAkK8wtssABEAQAFAAkK8wtssABEAQAAAA==.Alkiris:BAAANQADCgEIAQABNQAECgQICQAGAAAAAA==.Alssar:BAAANQAECgIIAgAAAA==.Alstar:BAABNQAECn8hAAIHAAoKQBPASgDMAQAHAAoKQBPASgDMAQAAAA==.Alynis:BAAANQADCgQIBAAAAA==.',
Am='Amac:BAAANQADCgUIBQAAAA==.Amathus:BAABNQAECn9YAAQIAAoKVhYfBgASAgAIAAoKVhYfBgASAgAJAAYKRhCMwQBIAQAKAAIKwwsaOQAyAAAAAA==.',
An='Andarial:BAAANQAECggIDgAAAA==.Andreth:BAAANQAECgQIDgAAAA==.Anoxyn:BAAANQAECgQIBAAAAA==.Anthe:BAAANQADCgUIFAAAAA==.',
Ar='Arcanmaggy:BAAANQAECgcIBwABNQAFFAQIBQAJAJsEAA==.Arcee:BAAANQADCgQIBgAAAA==.Ares:BAABNQAECn8hAAILAAcKKA4trgAeAQALAAcKKA4trgAeAQABNQADCgMJAwAGAAAAAA==.Aryxi:BAAANQADCgUJBQABNQADCgMJAwAGAAAAAA==.',
As='Asiägo:BAAANQABCgcJCgAAAA==.',
At='Atlas:BAAANQAECgYIDAAAAA==.',
Ba='Baelhal:BAABNQAECn9IAAMHAAoKlRsnEwB5AgAHAAoKlRsnEwB5AgADAAEKVQ+NsgA4AAAAAA==.',
Be='Bearden:BAAANQADCgMIAgAAAA==.Bearypotter:BAAANQADCgUIBQAAAA==.Benedin:BAAANQADCgcJDAABNQAECgoKKAAMAM0eAA==.',
Bi='Bigtex:BAABNQAECn8qAAINAAcKngdcGgD/AAANAAcKngdcGgD/AAAAAA==.Biped:BAABNQAECn8wAAIIAAoKQxXuBwDiAQAIAAoKQxXuBwDiAQAAAA==.Bishul:BAAANQAECgQIBAAAAA==.',
Bl='Blackdeath:BAABNQAECn8wAAIOAAoKWRJOIADeAQAOAAoKWRJOIADeAQAAAA==.Bloodsport:BAAANQADCgIIAgAAAA==.',
Bo='Bofadees:BAAANQADCggIFAAAAA==.Boloevo:BAAANQADCgUIBQABNQAECgYIEgAGAAAAAA==.Bolopal:BAAANQAECgIIAgABNQAECgYIEgAGAAAAAA==.Boolin:BAAANQADCgQIBAABNQAECgoKKAAKAIQgAA==.Boomstique:BAABNQAECn8qAAIPAAcK7BDruQCQAQAPAAcK7BDruQCQAQAAAA==.Boondocka:BAABNQAECn8oAAIPAAkKzhbYUAB9AgAPAAkKzhbYUAB9AgAAAA==.',
Br='Brex:BAAANQAECggIAQAAAA==.Brissennissa:BAABNQAECn8sAAIQAAkK5hzjEgDUAgAQAAkK5hzjEgDUAgAAAA==.Brokkr:BAAANQADCggIEwAAAA==.Bronar:BAAANQADCgMIAwAAAA==.Brutalís:BAABNQAECn8pAAIPAAoKyQ9LaQDxAQAPAAoKyQ9LaQDxAQAAAA==.Brèwtality:BAAANQADCgUICwAAAA==.',
Bt='Btrain:BAABNQAECn8eAAICAAYKLAdaJgGxAAACAAYKLAdaJgGxAAAAAA==.',
Bu='Bubblebae:BAAANQADCggIFgABNQAECgYIDAAGAAAAAA==.',
['Bó']='Bóunty:BAABNQAECn8dAAIPAAkKEyMcVgBwAgAPAAkKEyMcVgBwAgAAAA==.',
Ca='Calypsto:BAAANQAECgIIAgAAAA==.',
Ce='Cenobité:BAABNQAECn8zAAIDAAoKrg7RNgDGAQADAAoKrg7RNgDGAQAAAA==.',
Ch='Chamber:BAAANQAECggIDgABNQAECgkJIwAFAHMZAA==.Chialing:BAAANQAECgYIEwAAAA==.Chickenhead:BAAANQAECgUIBwAAAA==.Chip:BAAANQADCggIKgAAAA==.Chromefury:BAAANQADCgQIBAAAAA==.Chuckfinley:BAAANQAECgMIBQAAAA==.Chuong:BAAANQADCgIIAgABNQAECgcIDAAGAAAAAA==.',
Ci='Cirax:BAABNQAECn8oAAIPAAcK+hUypgBmAQAPAAcK+hUypgBmAQAAAA==.',
Cl='Classic:BAAANQADCgYIDQABNQAECgcIKgARAKsVAA==.Cleetess:BAAANQADCgYIDgAAAA==.Clenton:BAABNQAECn9BAAIRAAoK/gz2JABHAQARAAoK/gz2JABHAQAAAA==.Clown:BAAANQAECgQIDgAAAA==.',
Co='Cobrakai:BAAANQADCgEIAQAAAA==.Cosplay:BAAANQAECgcIEgABNQAFFAIICgASAJQFAA==.',
Cr='Crichton:BAABNQAECn9DAAIQAAoKMiK8BwBWAwAQAAoKMiK8BwBWAwAAAA==.Crowford:BAABNQAECn8gAAIPAAkKMQuWpgBlAQAPAAkKMQuWpgBlAQAAAA==.',
Cy='Cyris:BAAANQAECgIIAgABNQAECgcIKQATAJcDAA==.',
['Cá']='Cástle:BAABNQAECn8jAAIFAAkKcxmBMQB7AgAFAAkKcxmBMQB7AgAAAA==.',
Da='Daemonhanta:BAAANQABCgEIAQAAAA==.Daevahna:BAAANQADCggIEQAAAA==.Dak:BAABNQAECn89AAMRAAoKDhpSEgB9AgARAAoKlxlSEgB9AgACAAoKxBDAeADcAQAAAA==.Daksmash:BAAANQAECgYIDwABNQAECgoKPQARAA4aAA==.Dakstorm:BAABNQAECn8uAAITAAoKShldCgB3AgATAAoKShldCgB3AgABNQAECgoKPQARAA4aAA==.Darkmiza:BAACNQAFFH8FAAIJAAQKmwQRIQCtAAAJAAQKmwQRIQCtAAA1AAQKfzEAAgkACgpcEzNxAAwCAAkACgpcEzNxAAwCAAAA.Dawnstrike:BAAANQAECgEIAQAAAA==.',
De='Deadmangalad:BAAANQADCggIHQAAAA==.Deedees:BAAANQAECgYICwAAAA==.Demonhandler:BAAANQADCgUICQAAAA==.Demonikk:BAAANQAECgQICAAAAA==.Deo:BAAANQAECgYIDAABNQAFFAIICgASAJQFAA==.Depression:BAAANQAECggIBwAAAA==.',
Di='Diioo:BAAANQAECgMIBQAAAA==.Dirtnåp:BAAANQAECgIIAwAAAA==.Diskbänk:BAAANQADCgUIBQAAAA==.',
Dr='Dragontoast:BAAANQAECgQIDwAAAA==.Drama:BAAANQAECgUIBQAAAA==.Druidïan:BAABNQAECn8mAAMUAAkK9RMuHAAmAgAUAAkK9RMuHAAmAgAVAAMKMwNofwBIAAAAAA==.',
Dy='Dynwor:BAAANQADCggICwAAAA==.',
Ea='Easme:BAAANQAECgcIEAAAAA==.',
El='Elaric:BAAANQAECgYICQAAAA==.',
En='Engi:BAABNQAECn81AAMLAAoKlA8vdACnAQALAAoKlA8vdACnAQANAAEKjQVcOAAqAAAAAA==.Enhuna:BAAANQADCgIIAgAAAA==.',
Es='Escaper:BAABNQAECn8nAAIDAAgKwxTDMwAPAgADAAgKwxTDMwAPAgAAAA==.',
Ev='Eversteel:BAAANQADCgUIBQABNQAECgcIKgARAKsVAA==.',
Ex='Extrema:BAAANQAECgQIDwAAAA==.',
Fa='Faelyna:BAAANQAECgYIBgAAAA==.',
Fe='Felesha:BAAANQADCgQIBAAAAA==.',
Fh='Fhait:BAAANQAECgIIAwABNQAECgcIKgABAMQIAA==.',
Fi='Fionab:BAAANQADCgIIAgAAAA==.',
Fo='Foxfu:BAAANQADCgYICwAAAA==.',
Fu='Fujika:BAAANQADCgQIBAAAAA==.',
Ga='Galadan:BAABNQAECn8eAAIWAAYKUQagJgDYAAAWAAYKUQagJgDYAAABNQADCggIHQAGAAAAAA==.Garius:BAABNQAECn8fAAILAAkKjQuBbAC8AQALAAkKjQuBbAC8AQAAAA==.Garrekton:BAABNQAECn8oAAMMAAoKzR68MACAAgAMAAoKzR68MACAAgAXAAEKAACghQAjAAAAAA==.Gaskelmarg:BAAANQADCgYIHQAAAA==.',
Ge='Gellane:BAAANQAECgMIAwAAAA==.',
Gh='Ghozt:BAAANQADCgUICgABNQAECgkJIwAFAHMZAA==.',
Gl='Glory:BAABNQAECn8mAAMEAAkKfRhrLgCtAgAEAAkKfRhrLgCtAgACAAEKYwpjlQE2AAAAAA==.',
Go='Goldtusk:BAAANQAECgUIDQAAAA==.',
Gr='Grundler:BAAANQAECgEIAQAAAA==.Gryphone:BAAANQADCggIEAAAAA==.',
Ha='Hakmud:BAAANQAECgIIAwAAAA==.Harandee:BAAANQADCgYICwAAAA==.Hasmus:BAAANQADCgUIBQAAAA==.Haufa:BAAANQAECgIIAwAAAA==.',
He='Headstrong:BAAANQADCgcIBwAAAA==.Hettokal:BAAANQADCgQIBAAAAA==.Heximal:BAAANQADCgQIBwABNQAECgkJKAAPAM4WAA==.',
Ho='Hondojoe:BAEBNQAECn8yAAMMAAoKzRdkMACCAgAMAAoKzRdkMACCAgAXAAkKWQ3jHgCWAQAAAA==.Honey:BAAANQAECggICgAAAA==.Honeydrake:BAABNQAECn8cAAQYAAkKLAsTJgCMAQAYAAkKLAsTJgCMAQAZAAYKKAZNFwBxAAAaAAEKTQGMRQASAAAAAA==.Hopewell:BAABNQAECn8mAAIEAAYKdwNMwACZAAAEAAYKdwNMwACZAAAAAA==.',
Hu='Hugnsnuggle:BAABNQAECn8qAAIBAAcKxAgrGwC7AAABAAcKxAgrGwC7AAAAAA==.Huhu:BAAANQAECggICwAAAA==.Humilitas:BAAANQADCgUICQAAAA==.',
['Hä']='Häväç:BAAANQAECgQIBAAAAA==.',
Ib='Ibn:BAABNQAECn8sAAILAAoKHQhfgwB/AQALAAoKHQhfgwB/AQAAAA==.',
Il='Illadus:BAAANQADCgYICwAAAA==.Illidab:BAABNQAECn8lAAIbAAoKtxyBFAD5AgAbAAoKtxyBFAD5AgAAAA==.',
In='Infectus:BAABNQAECn8YAAMOAAkKgQM9rACcAAAOAAgKTQM9rACcAAADAAkKvgHUlABsAAAAAA==.',
Ir='Irielle:BAAANQAECgEIAgAAAA==.',
Iv='Ivylyn:BAABNQAECn8VAAMbAAoK1gngMwB/AQAbAAoK1gngMwB/AQAQAAEKAADKdwAcAAAAAA==.',
Ix='Ixiyá:BAABNQAECn8wAAIcAAoKGCUqBQCeAwAcAAoKGCUqBQCeAwAAAA==.Ixií:BAAANQADCgYIBgAAAA==.Ixì:BAAANQADCgEIAQAAAA==.',
Ja='Jakbenimble:BAAANQADCgcIDQAAAA==.Jakeyprogue:BAAANQAECgMIBAAAAA==.Jakota:BAAANQADCggIKQAAAA==.Jakskeleton:BAABNQAECn8pAAIHAAgKBw++QwAuAQAHAAgKBw++QwAuAQAAAA==.',
Je='Jeamica:BAAANQADCggIFQAAAA==.Jethroy:BAAANQADCgQIBAAAAA==.',
Jo='Joerollin:BAEANQADCggICQABNQAECgoKMgAMAM0XAA==.Joeronin:BAEANQAECggICAABNQAECgoKMgAMAM0XAA==.',
Ju='Judax:BAABNQAECn85AAIdAAoKHBf0TwA4AgAdAAoKHBf0TwA4AgAAAA==.Justagirl:BAABNQAECn8oAAIeAAcK7gZPOwDOAAAeAAcK7gZPOwDOAAABNQAECgcIKgABAMQIAA==.Juti:BAAANQADCggIKQAAAA==.Juvu:BAAANQADCgQIBAAAAA==.',
Ka='Kadooka:BAABNQAECn8pAAIPAAkKnBbQagDtAQAPAAkKnBbQagDtAQAAAA==.Kahlyn:BAAANQADCgQIBAAAAA==.Kai:BAAANQAECgYIEAAAAA==.Kaldaran:BAAANQADCgcIBwABNQAFFAYIBwALAMcMAA==.Kallan:BAAANQADCgQJBAABNQAECgcIKgARAKsVAA==.Kaléanor:BAACNQAFFH8HAAILAAYKxwx4FQAFAQALAAYKxwx4FQAFAQA1AAQKfyoAAgsACgrQIWMfAMgCAAsACgrQIWMfAMgCAAAA.Karen:BAAANQADCgYIDAAAAA==.Katabell:BAABNQAECn8mAAMXAAcKjQQ4QgClAAAXAAcKjQQ4QgClAAAMAAQKHwZlzACOAAAAAA==.Katira:BAAANQADCggIFgAAAA==.',
Ke='Keeganw:BAAANQAECgYIDwAAAA==.Keelay:BAAANQAECgcIDwAAAA==.Kelste:BAABNQAECn8VAAINAAoKAgMpJACSAAANAAoKAgMpJACSAAAAAA==.',
Ki='Kilabo:BAAANQABCgUIAwAAAA==.Killaclowns:BAAANQADCgUIEwAAAA==.Killjadan:BAAANQAECgMIAwAAAA==.Kimiko:BAAANQADCgUICQAAAA==.Kioki:BAAANQADCggIEAAAAA==.',
Kl='Klitess:BAAANQADCgYICAAAAA==.',
Ko='Kodrac:BAAANQAECgEIAQAAAA==.Koffcmorbius:BAAANQADCggIMQAAAA==.Kostian:BAAANQADCgUICQABNQAECgcIKgARAKsVAA==.',
Kr='Kraken:BAABNQAECn8oAAIKAAoKhCClAQBpAwAKAAoKhCClAQBpAwAAAA==.',
Ku='Kubb:BAABNQAECn8pAAITAAcKlwOwJAARAQATAAcKlwOwJAARAQAAAA==.',
Kw='Kweh:BAACNQAFFH8KAAIWAAQKOBRFAgD8AAAWAAQKOBRFAgD8AAA1AAQKfywAAhYACgrYHx0GABADABYACgrYHx0GABADAAAA.',
['Kê']='Kêlsen:BAAANQAECgIIAQAAAA==.',
La='Laero:BAAANQADCgYICwABNQAECgcIKQATAJcDAA==.Larrissa:BAAANQAECgQIBAAAAA==.Laurlynn:BAAANQADCgYICwAAAA==.',
Le='Lenwe:BAAANQAECgQICgABNQAECgcIDAAGAAAAAA==.Lettuceprey:BAAANQAECgcIDgAAAA==.',
Li='Lierise:BAAANQADCgcIDgAAAA==.Lilindra:BAABNQAECn82AAQDAAoKDhcwRACJAQADAAgKVhUwRACJAQAOAAcKMhSTgQAYAQAHAAYKRg7yXwDEAAAAAA==.Lillymay:BAAANQAECgEIAQAAAA==.Lilspazz:BAAANQAECgQIBwAAAA==.',
Ll='Lluiz:BAAANQAECgEIAQAAAA==.',
Lo='Lockdeath:BAAANQADCgcIDAAAAA==.Locknessy:BAAANQAECgYIBQAAAA==.Logoruk:BAAANQADCgQIBAAAAA==.Lorelleya:BAAANQADCgEIAQAAAA==.Loxia:BAAANQAECgYICwAAAA==.',
Lu='Lucille:BAAANQADCgYIBgAAAA==.Luckett:BAAANQADCgMJAwAAAA==.Lui:BAAANQAECgIIAgAAAA==.Lumi:BAAANQAECgUIDAAAAA==.',
Ma='Maavarra:BAABNQAECn8YAAIWAAgK7xhEFACIAQAWAAgK7xhEFACIAQAAAA==.Madshaggy:BAABNQAECn81AAIRAAkKZxmtGQAmAgARAAkKZxmtGQAmAgAAAA==.Magicdance:BAAANQAECgUIBQABNQAECgoKFgAVAA4JAA==.Magikern:BAAANQADCgMIAwABNQADCgUIBQAGAAAAAA==.Magy:BAAANQADCgIIAgAAAA==.Mahallomi:BAAANQADCgQIBAABNQAECgUIDgAGAAAAAA==.Maki:BAAANQAECgIIAwAAAA==.Maldreth:BAAANQADCgYIBgAAAA==.Maxlin:BAABNQAECn8kAAIWAAoKPRSJFwBeAQAWAAoKPRSJFwBeAQAAAA==.',
Me='Mehänemäntä:BAAANQAECgQICAAAAA==.Melarii:BAAANQADCgYIEQAAAA==.Merixa:BAAANQAECgYIDgAAAA==.',
Mi='Midou:BAABNQAECn8WAAIVAAoKDgmbNQBjAQAVAAoKDgmbNQBjAQAAAA==.Misstreater:BAAANQAECgYIDAAAAA==.',
Mo='Momentomori:BAABNQAECn8dAAIJAAoKqwb8zQAuAQAJAAoKqwb8zQAuAQAAAA==.Monbeau:BAABNQAECn8oAAIFAAoK2hbQZAC0AgAFAAoK2hbQZAC0AgAAAA==.Monocerotis:BAABNQAECn9AAAIDAAoKjBJhKwAFAgADAAoKjBJhKwAFAgAAAA==.Moosebear:BAAANQADCgYIBgAAAA==.Morishima:BAABNQAECn9bAAMfAAoKpCFJEQDtAgAfAAoKNSFJEQDtAgASAAkKpBtmEwDhAgAAAA==.',
Mu='Multipàss:BAAANQADCgQIBQAAAA==.',
My='Mydarling:BAACNQAFFH8IAAMEAAUK/BNhFwDtAAAEAAMK6AxhFwDtAAACAAMK0wMSIQCdAAA1AAQKfzEAAwIACgpGGvR4ADoCAAIACQr6GPR4ADoCAAQABgqGFUGaAO8AAAAA.Mymoon:BAAANQAECgcIDAAAAA==.Myris:BAABNQAECn8jAAIOAAgKtx2jLQB8AgAOAAgKtx2jLQB8AgAAAA==.',
['Mî']='Mîsgüïdëð:BAAANQAECgEIAQAAAA==.',
Na='Naturalchi:BAABNQAECn8oAAIeAAkKBx2hFQClAgAeAAkKBx2hFQClAgAAAA==.',
Nb='Nbi:BAAANQAECgEIAQAAAA==.',
Ne='Nefilion:BAAANQAECgQIBwAAAA==.Nefy:BAAANQAECgUICgAAAA==.Nezin:BAAANQADCgMJAwAAAA==.',
Ni='Nightrunnêr:BAAANQAECgEIAQABNQAECgcIKgARAKsVAA==.Niselo:BAAANQADCgUIBQAAAA==.',
No='Nogods:BAAANQAECgYIDAABNQAECgkJIwAFAHMZAA==.Nohzul:BAACNQAFFH8RAAIdAAcKnhglCgA6AQAdAAcKnhglCgA6AQA1AAQKfygAAh0ACgroJBENAAYDAB0ACgroJBENAAYDAAAA.Nomik:BAAANQAECgcIDAAAAA==.Nonah:BAAANQADCgYIBwAAAA==.',
Nu='Nullspace:BAABNQAECn8gAAMMAAoKERuyQABoAgAMAAoKERuyQABoAgAXAAIKnglaaAAsAAAAAA==.',
Ny='Nyleelyr:BAAANQAECgQIBQAAAA==.',
['Ní']='Níght:BAAANQAECgEIAQAAAA==.',
Og='Oggy:BAAANQADCgUIBQAAAA==.',
Om='Omegasham:BAAANQABCgIIAgAAAA==.',
Or='Orgresh:BAAANQADCggICAAAAA==.Orym:BAABNQAECn8ZAAIRAAkKWgcOLwACAQARAAkKWgcOLwACAQAAAA==.',
Pa='Palacia:BAABNQAECn8gAAMRAAgKTQ6AMQBUAQARAAYK9xOAMQBUAQACAAcKXAO7TQF+AAAAAA==.Pallythetank:BAABNQAECn8ZAAMRAAcKlwhhNADjAAARAAcKlwhhNADjAAACAAMKlwFAkwFBAAAAAA==.Pancakeeater:BAAANQAECgEIAQAAAA==.Pappabeary:BAAANQADCgIIAwAAAA==.',
Pe='Peerow:BAAANQAECgEIAgAAAA==.Petrichorica:BAAANQADCgcICgAAAA==.',
Ph='Phenomenon:BAAANQAECgEIAQAAAA==.',
Pi='Pintobeans:BAABNQAECn8UAAIPAAgK9APk6AAvAQAPAAgK9APk6AAvAQAAAA==.',
Po='Popeadin:BAAANQADCgQIBgAAAA==.',
Pr='Preachêr:BAAANQADCggICAABNQAECgcIKgARAKsVAA==.Primeatheist:BAABNQAECn8dAAIXAAkKXRg8FgD+AQAXAAkKXRg8FgD+AQAAAA==.',
Pu='Puuhceew:BAABNQAECn8mAAIMAAkKSAr6agCcAQAMAAkKSAr6agCcAQAAAA==.',
Py='Pyaghra:BAAANQAECgQICAAAAA==.',
Qu='Quina:BAAANQADCgMIAwAAAA==.',
Ra='Rainbrews:BAAANQAECgEIAQAAAA==.Rainera:BAABNQAECn8wAAIIAAkKyR+CAwC9AgAIAAkKyR+CAwC9AgABNQAFFAYIEQABAJwjAA==.Ramanas:BAAANQAECgYICgAAAA==.Ramrod:BAABNQAECn8XAAIVAAcKewdhbwANAQAVAAcKewdhbwANAQAAAA==.Ramstank:BAAANQAECgMIBwAAAA==.Rattles:BAAANQAECgIIAwAAAA==.',
Re='Redgicide:BAAANQAECgYIDwABNQAECgkJKAAPAM4WAA==.Releafme:BAACNQAFFH8UAAIUAAcKcxp0BAD4AQAUAAcKcxp0BAD4AQA1AAQKfzkAAhQACgqOJaQBALsDABQACgqOJaQBALsDAAAA.Resurgencê:BAABNQAECn8qAAIRAAcKqxXuJAC5AQARAAcKqxXuJAC5AQAAAA==.',
Ri='Riordan:BAABNQAECn8hAAICAAkK5g1gpACFAQACAAkK5g1gpACFAQAAAA==.',
Ro='Rohz:BAAANQAECggICAABNQAECgkJIwAFAHMZAA==.Rojeton:BAAANQADCgIIAgAAAA==.Rothema:BAABNQAECn8dAAIdAAYK9gN50gDvAAAdAAYK9gN50gDvAAAAAA==.Routh:BAAANQAECgEIAQAAAA==.',
Ru='Rubberbizkit:BAAANQADCggIEAAAAA==.Rubee:BAAANQADCgMIAwAAAA==.',
Rw='Rwlmaster:BAABNQAECn8uAAIHAAkKahLPRADoAQAHAAkKahLPRADoAQAAAA==.',
Sa='Sandwiches:BAAANQAECgEIAQABNQAECgQIDgAGAAAAAA==.',
Sc='Scerra:BAABNQAECn88AAMDAAoKIxcnLAABAgADAAoKIxcnLAABAgAOAAMKogJewQBoAAAAAA==.Scridders:BAABNQAECn8ZAAIEAAoKpxQaRAAEAgAEAAoKpxQaRAAEAgAAAA==.Scridderz:BAAANQAECgEIAQAAAA==.Scriddle:BAAANQAECgUIBAAAAA==.Scridman:BAAANQAECgUIBQAAAA==.',
Se='Secre:BAAANQADCgQJBAABNQAECgIIAwAGAAAAAA==.Sellandre:BAAANQADCgYIBgABNQAECgoKHwAgANQVAA==.Seru:BAAANQAECgQIDwAAAA==.',
Sh='Shamarha:BAABNQAECn82AAMcAAoKVxy6IgCsAgAcAAoKVxy6IgCsAgAdAAEKAADJKAEAAAAAAA==.Shamonbo:BAAANQADCgUIBQABNQAECgoKKAAFANoWAA==.Sharriavolf:BAABNQAECn8cAAMJAAcKPR3dmgCjAQAJAAUK+RzdmgCjAQAKAAIKox1lSQCjAAAAAA==.Shaz:BAAANQABCgEIAQAAAA==.Shion:BAAANQAECgQIBAABNQAFFAcIIQAQAIgeAA==.Shreder:BAAANQADCgIIAgAAAA==.Shuma:BAAANQADCgUIBgAAAA==.',
Si='Simichaelton:BAACNQAFFH8GAAMgAAIKTBHOEgBJAAAFAAEKbRIhWABQAAAgAAEKKxDOEgBJAAA1AAQKf0UAAyAACgoGGxAbABoBAAUACQpoGXl+AK4BACAABQp+HBAbABoBAAE1AAUUBggLAB4A6AwA.Sinahi:BAAANQAECgEIAQAAAA==.Sinpal:BAAANQAECgcIDAAAAA==.Sinthea:BAAANQAECggIAwAAAA==.',
Sk='Skyblaze:BAAANQADCgMIAwAAAA==.',
Sn='Sneakysoul:BAACNQAFFH8KAAMSAAIKlAVqFACmAAASAAIKlAVqFACmAAAfAAEKAADzLAAAAAA1AAQKfzEAAxIACgo3IgMEAPQCABIACgo3IgMEAPQCAB8ACArcE9xaAJ0BAAAA.',
So='Solyn:BAABNQAECn8ZAAICAAgKeQal8QA5AQACAAgKeQal8QA5AQAAAA==.Sonea:BAAANQADCgEIAQAAAA==.Sonic:BAAANQADCgUIBQAAAA==.',
Sp='Spagooti:BAAANQAECggIDAAAAA==.Spanxya:BAAANQADCgQIBAAAAA==.Spartaaxd:BAABNQAECn8ZAAIDAAkKswwNRgCoAQADAAkKswwNRgCoAQAAAA==.',
St='Stabbard:BAAANQADCgQIBAAAAA==.Stagerrind:BAAANQAECgIIAgAAAA==.Starfall:BAAANQAECgEIAwAAAA==.Steiner:BAAANQADCgUIBwAAAA==.Stejamarha:BAAANQADCgQIBAAAAA==.',
Su='Sugarseer:BAABNQAECn8ZAAIcAAoKcxN2UwAZAgAcAAoKcxN2UwAZAgAAAA==.Suka:BAAANQAECgIIAwAAAA==.Suzi:BAABNQAECn8gAAIPAAoKRwj7jgCYAQAPAAoKRwj7jgCYAQAAAA==.',
Sw='Swiftleaf:BAAANQADCggICAAAAA==.',
Sy='Syevoid:BAAANQADCgIIAwAAAA==.Sylentcurse:BAAANQAECgYIDAABNQAECgoKKQAPAMkPAA==.Sylentstorm:BAAANQAECgEIAQABNQAECgoKKQAPAMkPAA==.Sylentwolvez:BAABNQAECn8UAAIPAAYKdhDb1QAHAQAPAAYKdhDb1QAHAQAAAA==.Syleta:BAAANQADCgEIAQABNQAECgoKNgADAA4XAA==.Sylvarus:BAAANQADCgQIBAAAAA==.',
Ta='Tabraxis:BAAANQADCgYIBwAAAA==.Tagalorc:BAABNQAECn8iAAIFAAoKKApYjACOAQAFAAoKKApYjACOAQAAAA==.Takamaki:BAAANQAECgEIAgAAAA==.Talionwrite:BAAANQAECgcIEwAAAA==.Tanksbacon:BAAANQAECgUIBQAAAA==.',
Te='Teana:BAAANQAECgcIEAAAAA==.Tempestas:BAAANQADCgYICQAAAA==.',
Th='Thechadd:BAAANQAECggIDgAAAA==.Thelegendáry:BAABNQAECn86AAMcAAkKeR6dNwCBAgAcAAkKeR6dNwCBAgAdAAEKRhLsBgEuAAAAAA==.Themigrant:BAAANQABCgUIBQAAAA==.Therosewood:BAAANQAECgcICgAAAA==.Thorgrimm:BAAANQADCgYIBgAAAA==.Thraine:BAABNQAECn8aAAILAAgKbxDBdQCjAQALAAgKbxDBdQCjAQAAAA==.Threedog:BAAANQADCgIIAgAAAA==.',
Ti='Tione:BAABNQAECn8jAAMUAAkKXxuxEwCQAgAUAAkKXxuxEwCQAgAVAAEKAABOwAAhAAAAAA==.',
To='Toadvoker:BAABNQAECn8lAAMYAAoK+hb/EwBuAgAYAAoK+hb/EwBuAgAZAAEKxwB0KQARAAAAAA==.Topao:BAAANQADCgYIBgABNQAECgQICQAGAAAAAA==.Toriee:BAAANQAECggIDAAAAA==.Totembish:BAABNQAECn8hAAIdAAkK4AmrZwBQAQAdAAkK4AmrZwBQAQAAAA==.',
Tr='Trisstan:BAABNQAECn8mAAIgAAYKcAi2IADjAAAgAAYKcAi2IADjAAAAAA==.Trollthrall:BAAANQAECgUICgAAAA==.',
Ty='Tyster:BAACNQAFFH8NAAICAAQK7g0IGADOAAACAAQK7g0IGADOAAA1AAQKfy4AAgIACgppHWJfAHsCAAIACgppHWJfAHsCAAAA.',
['Tï']='Tïghtgrïp:BAABNQAECn87AAQDAAoKmRwhIwA4AgADAAoK3RshIwA4AgAHAAcKnR1qOQBdAQAOAAIK2gjTzgBPAAAAAA==.',
['Tø']='Tørmented:BAAANQADCgUIBQAAAA==.',
Un='Undol:BAAANQADCggIHQABNQAECgcIKQATAJcDAA==.',
Va='Vaellborn:BAAANQADCgEIAQAAAA==.Vandress:BAAANQADCgMIAQABNQAECgQICQAGAAAAAA==.',
Ve='Velobeef:BAAANQADCgEIAQAAAA==.Veloth:BAACNQAFFH8aAAMgAAcKIhXPAAB6AQAgAAcKIhXPAAB6AQAFAAMKbA0IOgDdAAA1AAQKf0gAAyAACgpHJZ4BAHQDACAACgprJJ4BAHQDAAUACQqYHrtIAPECAAAA.Verminus:BAABNQAECn8bAAQUAAkKVwwgNgBrAQAUAAgKNAwgNgBrAQAVAAYKCgapcwD8AAAWAAEK6gZqSAApAAAAAA==.',
Vi='Viggle:BAAANQADCgUICAABNQAECgcIKgARAKsVAA==.Viho:BAABNQAECn87AAICAAoK9hThkQCoAQACAAoK9hThkQCoAQAAAA==.Vilekin:BAAANQAECgUIBwAAAA==.Vithaxa:BAAANQAECgMICAAAAA==.',
Vo='Voidra:BAAANQAECgEIAQAAAA==.',
Vy='Vyinson:BAAANQAECgQIBAABNQAECgUIDQAGAAAAAA==.',
Wa='Warloque:BAAANQADCgMIAwAAAA==.',
We='Weechuup:BAAANQAECgQIDAAAAA==.',
Wi='Wifeotusk:BAAANQAECgQIBAAAAA==.Wiggle:BAAANQADCgYICwAAAA==.Willmar:BAABNQAECn8oAAICAAgKUgoN3wAfAQACAAgKUgoN3wAfAQAAAA==.Windrun:BAABNQAECn8XAAIHAAcKeBOdQAA8AQAHAAcKeBOdQAA8AQAAAA==.',
Wo='Wolf:BAABNQAECn8nAAIhAAoKVRKSGQDdAQAhAAoKVRKSGQDdAQAAAA==.Woodtique:BAAANQADCggILgAAAA==.',
Wu='Wulthan:BAAANQADCgYICwAAAA==.',
Xa='Xandercruise:BAAANQAECgEIAQAAAA==.',
Xe='Xelphie:BAAANQAECgMIBQAAAA==.',
Xu='Xuchilbara:BAABNQAECn8WAAIWAAYKXx3FEAD7AQAWAAYKXx3FEAD7AQAAAA==.',
Ya='Yamato:BAABNQAECn8YAAICAAkKRQ8yrwByAQACAAkKRQ8yrwByAQAAAA==.',
Za='Zaledron:BAABNQAECn8bAAIOAAkK4w7tKgCOAQAOAAkK4w7tKgCOAQAAAA==.',
Zb='Zbelladonna:BAAANQADCggIEgABNQAECgoKWgADAB0jAA==.',
Ze='Zezera:BAAANQAECgQIDQAAAA==.',
Zh='Zhades:BAABNQAECn9aAAMDAAoKHSOgBQCGAwADAAoKHSOgBQCGAwAOAAkKOBEuWwCjAQAAAA==.Zhandaria:BAAANQAECgIIAgAAAA==.Zhort:BAAANQAECgIIAgAAAA==.',
Zi='Zioki:BAAANQADCggICQAAAA==.',
Zo='Zodgul:BAAANQADCggICAAAAA==.Zomby:BAABNQAECn8oAAIHAAoKKBMFJADaAQAHAAoKKBMFJADaAQABNQAFFAYICwAeAOgMAA==.',
Zu='Zultan:BAABNQAECn9KAAIJAAoKdAszZQCnAQAJAAoKdAszZQCnAQAAAA==.',
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
