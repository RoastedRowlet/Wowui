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

local lookup = {'Unknown-Unknown','Druid-Guardian','Druid-Balance','Hunter-BeastMastery','Paladin-Retribution','Mage-Frost','Warlock-Demonology','DemonHunter-Vengeance','DeathKnight-Unholy','Shaman-Restoration','Druid-Restoration','Shaman-Elemental','Hunter-Marksmanship','Monk-Windwalker','Priest-Holy','Warrior-Arms','Warrior-Fury','Mage-Arcane','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Protection','Shaman-Enhancement','DeathKnight-Frost','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Rogue-Outlaw','Paladin-Holy','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Priest-Discipline','Monk-Brewmaster',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aaril:BAAANQADCgcIHAAAAQ==.',
Ab='Abnaren:BAAANQAECgQIBAABNQAECgQIBQABAAAAAA==.Abrams:BAABNQAECn8qAAMCAAoKkg+eHgCqAQACAAoKkg+eHgCqAQADAAgKAgeVWAByAQAAAA==.Absínthè:BAAANQABCgQIBAAAAA==.',
Ag='Agnass:BAAANQADCgcIGwAAAA==.',
Ak='Akina:BAABNQAECn8XAAIEAAgK1Rf1gAALAgAEAAgK1Rf1gAALAgAAAA==.',
Al='Alcholic:BAAANQAECggIAgAAAA==.Aldea:BAAANQADCgYIBgAAAA==.Alialista:BAABNQAECn8cAAIEAAgKNRInlQDeAQAEAAgKNRInlQDeAQAAAA==.Alirrayia:BAAANQADCgMIAwAAAA==.Alirrayiia:BAABNQAECn84AAIFAAoKuRO4TgDKAQAFAAoKuRO4TgDKAQAAAA==.Allmight:BAAANQADCgMIAwAAAA==.Allystar:BAAANQADCgUICgAAAA==.Alvidor:BAABNQAECn8nAAIGAAgKvQh5GQArAQAGAAgKvQh5GQArAQAAAA==.',
Am='Amachine:BAAANQADCggIDgABNQAFFAcIGgAHAPkeAA==.Amethen:BAAANQAECgQICgAAAA==.Amybabe:BAABNQAECn8UAAIEAAYKnhFJnwDwAAAEAAYKnhFJnwDwAAAAAA==.',
An='Andydufresne:BAAANQAECgcICwABNQAECgoKPAAIAAojAA==.Anestesiax:BAAANQAECgQIBAAAAA==.Anorivia:BAABNQAECn8uAAIJAAkKxgj0JABPAQAJAAkKxgj0JABPAQAAAA==.',
Ap='Apolloerosp:BAAANQAECgQICwABNQAECgkJKQAKAOoRAA==.Apollossham:BAABNQAECn8pAAIKAAkK6hFbUQBSAQAKAAkK6hFbUQBSAQAAAA==.',
Ar='Araluen:BAAANQABCgMIAwAAAA==.Arkagob:BAAANQADCgcIBwAAAA==.Arragora:BAAANQAECgQIBQAAAA==.Arrowdynamix:BAABNQAECn8fAAIEAAoKbBRYKwAzAgAEAAoKbBRYKwAzAgAAAA==.',
As='Ashyani:BAAANQADCgUIBQAAAA==.',
At='Atlan:BAAANQADCgUIBQABNQAECgcIKQALAJUiAA==.',
Au='Aurnhadon:BAAANQABCggIDAAAAA==.',
Ba='Babbayagga:BAABNQAECn8mAAIMAAkKshHrUQAxAgAMAAkKshHrUQAxAgAAAA==.Baji:BAABNQAECn82AAMKAAoKShryKAALAgAKAAoKShryKAALAgAMAAgK0xYtXQAKAgAAAA==.Barefaall:BAACNQAFFH8MAAMEAAgK9gr4CwCRAQAEAAUK1wr4CwCRAQANAAQKFQseFgDdAAA1AAQKf0kAAwQACgozJl8fABoDAAQACQqHJl8fABoDAA0ABgo/IdMTAIIBAAAA.Barefalls:BAABNQAECn8ZAAIEAAkKWxOwRwDHAQAEAAkKWxOwRwDHAQABNQAFFAgIDAAEAPYKAA==.Baénoth:BAAANQABCgQIBgAAAA==.',
Be='Bealzebub:BAAANQAECgQIBAAAAA==.Bellucci:BAAANQADCgcICAABNQAECgcIIgAHAIINAA==.Berglock:BAAANQADCgcIBwABNQAECgcIDAABAAAAAA==.Bergonator:BAAANQAECgcIDAAAAA==.Bergue:BAAANQADCgQIBAABNQAECgcIDAABAAAAAA==.Berrodiah:BAAANQADCgcIDQABNQAECgoKKAAOAOgZAA==.Bestlays:BAAANQADCgUIBQAAAA==.Bettiepage:BAAANQAECgUIBAAAAA==.',
Bh='Bheiroth:BAABNQAECn8zAAIPAAoKJCMuBwBuAwAPAAoKJCMuBwBuAwAAAA==.',
Bl='Blackchapell:BAAANQABCgYICQAAAA==.Blewmyload:BAAANQAECgUIBgAAAA==.Bluett:BAAANQADCgcIGAAAAA==.',
Bo='Bogertus:BAABNQAECn82AAMQAAoKvyYrBwA2AwAQAAoKvyYrBwA2AwARAAMK/h/YHgDJAAAAAA==.Boomertunes:BAAANQADCgQIBAAAAA==.Boxnasty:BAAANQADCgEIAQAAAA==.',
Br='Brein:BAABNQAECn8rAAILAAkKkyJGAwB3AwALAAkKkyJGAwB3AwAAAA==.',
Bu='Bucketeer:BAAANQAECgUICQAAAA==.Burzona:BAAANQABCgMIAwAAAA==.',
Ca='Cameltoetoe:BAAANQAECgEIAgAAAA==.Canaprey:BAAANQAECggIEQAAAA==.Cathogin:BAAANQADCggIDgAAAA==.Catsdruid:BAAANQADCgcIBwAAAA==.Catshunter:BAAANQAECgYIBQAAAA==.',
Ce='Celaa:BAAANQADCgQIBAABNQAECggIFwAEANUXAA==.Celebrían:BAAANQADCgUICAAAAA==.Celor:BAAANQABCgQIBgAAAA==.',
Ch='Chanka:BAAANQADCgcIEAAAAA==.Chantillary:BAAANQADCgcIGwAAAA==.Charise:BAAANQAECgUIDAAAAA==.Cheesy:BAAANQADCgYIDAAAAA==.Chopzullee:BAAANQAECgUIBQAAAA==.',
Ci='Cinnaz:BAAANQAECgUICwABNQAECgoKMwASAN4UAA==.',
Cl='Clortho:BAAANQAECgUIDAAAAA==.Clorthö:BAAANQADCgYIFAAAAA==.',
Co='Colljack:BAACNQAFFH8cAAITAAcKMB/JAQA7AgATAAcKMB/JAQA7AgA1AAQKfzQAAhMACgpQJewBADwDABMACgpQJewBADwDAAAA.Corvath:BAAANQAECgUIEQAAAA==.',
Cr='Cryptoe:BAABNQAECn9KAAISAAoK8R5aQQACAwASAAoK8R5aQQACAwAAAA==.',
Cy='Cyngin:BAAANQAECgQIBAAAAA==.',
Da='Daedelus:BAABNQAECn8lAAMUAAkK6BaTFQCXAQAUAAkK6BaTFQCXAQAIAAIKew3hKABuAAAAAA==.Daglon:BAABNQAECn8XAAIFAAcKahNsfwBSAQAFAAcKahNsfwBSAQAAAA==.Daraedra:BAAANQADCggIKgAAAA==.Dardolur:BAAANQADCgIIAgAAAA==.Darkbane:BAAANQADCggICAAAAA==.Darknìght:BAABNQAECn8dAAIVAAcK8x0oIwB8AQAVAAcK8x0oIwB8AQAAAA==.Darkraider:BAAANQAECgQICAAAAA==.Darkshade:BAAANQADCgMIAwAAAA==.Darkslayer:BAAANQADCgMIBQAAAA==.Darkthyr:BAAANQAECgQIBQAAAA==.',
De='Deeznutticus:BAACNQAFFH8NAAIQAAYKCBP4FQB5AQAQAAYKCBP4FQB5AQA1AAQKfzkAAhAACgojIJ0eAD0DABAACgojIJ0eAD0DAAAA.Demonspud:BAAANQAECgYIEAAAAA==.Dersan:BAAANQADCgIIAgAAAA==.Destriant:BAABNQAECn86AAITAAkKdiCWBwBeAgATAAkKdiCWBwBeAgAAAA==.Devourer:BAAANQABCgMIAwAAAA==.Dewburt:BAAANQAECgQIBgAAAA==.Deylia:BAAANQAECgYIBQABNQAFFAUIEwAPAOgKAA==.',
Dh='Dhori:BAAANQADCgcIGwAAAA==.',
Di='Dillion:BAAANQAECgEIAQABNQAECgcIIgAHAIINAA==.Dionin:BAAANQADCgUICgAAAA==.Dirky:BAAANQAECggICQAAAA==.Dirtychai:BAAANQAECggIDwAAAA==.Disappear:BAAANQADCgYICgABNQAECgoKMwASAN4UAA==.Dizzyhealz:BAAANQADCgMICQAAAA==.Dizzyhuntres:BAAANQADCgYIBwAAAA==.',
Do='Dooberrt:BAAANQAECgUIBQAAAA==.Dooberto:BAABNQAECn8jAAMWAAkKbg51GQCbAQAWAAkKbg51GQCbAQAQAAMKywReMgFwAAAAAA==.Dooburt:BAABNQAECn8WAAMFAAkKuAYn8gA4AQAFAAgKDgcn8gA4AQATAAYKOQT4SwC6AAAAAA==.',
Dr='Dracaric:BAAANQADCgYIBgAAAA==.Draeca:BAAANQADCgcIGAAAAA==.Dragondznut:BAAANQADCggIDwAAAA==.Drfrostie:BAAANQAECgYIBgAAAA==.Driatin:BAAANQAECgEIAQAAAA==.',
Du='Durø:BAABNQAECn87AAIUAAoK5yFtCQBBAwAUAAoK5yFtCQBBAwAAAA==.',
['Dè']='Dègenerate:BAABNQAECn9AAAIWAAoKiiKIAwBiAwAWAAoKiiKIAwBiAwAAAA==.',
Ed='Eddy:BAABNQAECn8qAAIXAAoKww/zFQAJAgAXAAoKww/zFQAJAgAAAA==.',
Ei='Eilae:BAAANQADCgcIDQAAAA==.Einherjarr:BAAANQADCgYICgAAAA==.',
El='Eldumpling:BAABNQAECn8aAAIOAAkKfRKIFgCIAQAOAAkKfRKIFgCIAQAAAA==.Elefante:BAAANQADCgYICwAAAA==.',
Ep='Epicnym:BAABNQAECn8kAAMMAAcKvBn4fACtAQAMAAYK5Br4fACtAQAXAAYK/hGUEwBNAQAAAA==.',
Es='Esdeath:BAABNQAECn8mAAQJAAgK6AuZIwBYAQAJAAgKXgmZIwBYAQAYAAYKowwbXAA4AQAZAAMK4gHauQBUAAAAAA==.',
Ev='Evoberg:BAAANQABCgYIBgABNQAECgcIDAABAAAAAA==.',
Ex='Extenze:BAABNQAECn8mAAIUAAkKyBaZDwDvAQAUAAkKyBaZDwDvAQAAAA==.',
Ez='Ezykiah:BAAANQADCggIFgAAAA==.',
Fa='Faegrin:BAAANQADCgIIAgAAAA==.',
Fe='Feda:BAAANQADCgQIBAAAAA==.Felyna:BAAANQAECgcIBwAAAA==.Ferryman:BAABNQAECn8dAAIEAAgKbRHcYgB4AQAEAAgKbRHcYgB4AQAAAA==.',
Fi='Findria:BAAANQADCgYIBgABNQAFFAQIBgAEABUZAA==.',
Fo='Forphium:BAACNQAFFH8QAAMaAAUKggoTCQBcAQAaAAUKwgcTCQBcAQAbAAEKTQtyIABHAAA1AAQKfywAAxoACgqOHxcPAIkCABoACQrvIBcPAIkCABsAAQrnFXGcAEQAAAAA.',
Fr='Fredolf:BAAANQADCgQJBAAAAA==.Freespirit:BAAANQAECggIEAABNQAFFAcIHQAcACIhAA==.Friarkuck:BAAANQADCgEIAQAAAA==.Frierenn:BAAANQADCgYIBgAAAA==.Frosteddonut:BAAANQAECgcICQABNQAECgoKNwALAGAjAA==.Frostieheals:BAAANQAECgMIAwAAAA==.',
Ft='Fthrhealgood:BAAANQADCgYIBgAAAA==.',
Ga='Gahlina:BAAANQAECgEIAQAAAA==.Gambaaddict:BAABNQAECn8bAAIdAAgKoBIdCgDdAQAdAAgKoBIdCgDdAQAAAA==.Ganhammer:BAAANQADCgIIAgAAAA==.Garshan:BAAANQAECgMIAwAAAA==.',
Ge='Genestarwind:BAAANQAECgQIDAAAAA==.',
Gh='Ghexn:BAAANQADCgIIAgAAAA==.',
Gi='Gilleyy:BAAANQAECgUICQAAAA==.Gird:BAABNQAECn8rAAIeAAgKCBb7KAALAgAeAAgKCBb7KAALAgAAAA==.Girdlock:BAAANQAECgIIAgAAAA==.',
Gl='Glyph:BAAANQAECgYIBgABNQAECgoKLwAKALEZAA==.',
Gn='Gnymesis:BAAANQADCgYICwAAAA==.',
Go='Goatmonger:BAAANQAECggICgAAAA==.Goinpostal:BAAANQADCgYICwAAAA==.Goldblade:BAAANQAECggICAAAAA==.Gordek:BAABNQAECn8XAAIFAAkKdBPsngDkAQAFAAkKdBPsngDkAQAAAA==.',
Gr='Graceteena:BAAANQADCgUIBAAAAA==.Grahra:BAAANQABCgIIBAAAAA==.Grantaron:BAABNQAECn82AAIFAAkK9hstPwD+AQAFAAkK9hstPwD+AQAAAA==.Grimskul:BAABNQAECn80AAIJAAkKLxkBMQBqAgAJAAkKLxkBMQBqAgAAAA==.Grntitan:BAAANQADCgcIHQAAAA==.Gruid:BAAANQAECgMIAgAAAA==.',
Gw='Gwoohoori:BAABNQAECn8eAAIFAAkKNRf9UwC6AQAFAAkKNRf9UwC6AQAAAA==.',
Ha='Halukari:BAAANQADCggIDAABNQAFFAUIEwAPAOgKAA==.Haléon:BAAANQAECgUIDwAAAA==.Hamnier:BAAANQABCgcIDwAAAA==.Harfnan:BAAANQADCgYICQAAAA==.Harperlee:BAAANQAECgYICQAAAA==.Harrin:BAAANQADCggIEQAAAA==.',
He='Headshotty:BAAANQAECgUICAAAAA==.Hellfire:BAAANQADCgYIBgAAAA==.Hezrel:BAAANQAECgcICAAAAA==.',
Hi='Hinal:BAABNQAECn8cAAMFAAcKkhSXsAC+AQAFAAcKkhSXsAC+AQATAAYKDA2ELgCgAAAAAA==.',
Ho='Holyenabler:BAAANQAECgYIEAAAAA==.Honzo:BAABNQAECn8ZAAMZAAkKUQdXbgA8AQAZAAkKqQZXbgA8AQAYAAMKJAkvdABmAAAAAA==.',
Hu='Hungor:BAAANQABCgQIBAAAAA==.',
Ic='Iceberg:BAAANQADCgEIAQABNQAECgcIDAABAAAAAA==.Icecrystal:BAAANQABCgIIAgAAAA==.',
Ih='Iheartbailey:BAAANQADCgQIBAAAAA==.',
Im='Imcruel:BAACNQAFFH8aAAISAAcKjhsEDgAHAgASAAcKjhsEDgAHAgA1AAQKf0MAAhIACgooJVUEAEYDABIACgooJVUEAEYDAAAA.Iminyë:BAAANQAECgYIBQAAAA==.',
Io='Iorese:BAAANQADCggIDwAAAA==.',
Ir='Iriana:BAEANQADCgYIMQABNQADCggICAABAAAAAA==.',
Ja='Jabes:BAAANQAECgUIBQAAAA==.Jackiegan:BAAANQADCgEIAQAAAA==.Jagershamer:BAAANQAECgcIBwABNQAECggIBwABAAAAAA==.Jasperine:BAAANQAECgcIEAABNQAFFAcIHQAcACIhAA==.',
Je='Jenneldots:BAAANQAECgYIEgAAAA==.Jerce:BAAANQADCgUICQAAAA==.',
Jo='Johnnyhuntz:BAAANQADCgYICAAAAA==.',
Ju='Juacqer:BAAANQADCgcIFgAAAA==.Junamara:BAAANQAECgQICQAAAA==.',
Ka='Kaant:BAABNQAECn8rAAMMAAkKHhq1IAD4AQAMAAkKHhq1IAD4AQAKAAcKchTcRgB5AQAAAA==.Kaetiegh:BAAANQADCgUIDwAAAA==.Kaidevyn:BAABNQAECn8hAAIYAAgKHRKbPgDRAQAYAAgKHRKbPgDRAQAAAA==.Kardead:BAAANQAECgMIBAAAAA==.Kat:BAAANQADCgQICAAAAA==.',
Kb='Kbang:BAAANQAECgIIAgAAAA==.',
Ke='Keiran:BAABNQAECn85AAIEAAkKDx/LLQDkAgAEAAkKDx/LLQDkAgAAAA==.Kenix:BAAANQADCgUIDQABNQADCgYICgABAAAAAA==.',
Kh='Khalnerys:BAABNQAECn8hAAQfAAYKzQYXEwCiAAAfAAYKvgYXEwCiAAAgAAQKUALQQwCFAAAhAAMKTQWSHgBsAAAAAA==.Khaotick:BAEBNQAECn8rAAQHAAoKJRlsVQBWAgAHAAkKcxhsVQBWAgAiAAQK5A4VPQDNAAAjAAEKAABJMwAtAAABNQAECgkJGgAHAPIPAA==.Khoulock:BAABNQAECn8hAAQHAAkK6B8HLgDOAgAHAAkKfR8HLgDOAgAiAAYK4B/1FwCtAQAjAAEKAABlLAA+AAAAAA==.',
Ki='Kimmi:BAAANQAECgQIBQAAAA==.Kimmispally:BAAANQADCggICAAAAA==.Kiro:BAAANQADCgYIDAAAAA==.',
Ko='Kotawar:BAAANQAECgMIAwAAAA==.Kozana:BAAANQADCgIIAgAAAA==.',
Kt='Kthxbye:BAAANQAECggIBwAAAA==.',
Ku='Kuraishin:BAABNQAECn8qAAIkAAoKECHZBgD7AgAkAAoKECHZBgD7AgAAAA==.Kuterr:BAAANQADCgUIBQAAAA==.',
Ky='Kyrae:BAAANQADCgYIEAABNQAECgYIDwABAAAAAA==.Kyrub:BAAANQABCggICAAAAA==.',
La='Latheal:BAAANQADCgcIFAAAAA==.Latto:BAABNQAECn8UAAMZAAUKNBM6fAAIAQAZAAUKNBM6fAAIAQAYAAEKAABhqwA3AAABNQAECgYIEgABAAAAAA==.',
Le='Lengex:BAAANQAECgcIBQAAAA==.Lero:BAAANQAECgIIAgAAAA==.Levatan:BAAANQAECgEIAQAAAA==.Lexoh:BAAANQAECgQIAgAAAA==.',
Li='Lilieth:BAAANQADCgcIFgAAAA==.Liltankarmor:BAAANQAECgYICgABNQAECgYIEgABAAAAAA==.Lindir:BAACNQAFFH8GAAIEAAQKFRnsCgD7AAAEAAQKFRnsCgD7AAA1AAQKfzAAAgQACgqfJK0MAHkDAAQACgqfJK0MAHkDAAAA.Liquid:BAACNQAFFH8IAAIcAAUKmQ3fBwDYAAAcAAUKmQ3fBwDYAAA1AAQKfykAAxwACgp8GQYWAK0CABwACgp8GQYWAK0CACUAAQq0A2cuACgAAAAA.Litasfk:BAAANQAECgQICAAAAA==.Liuni:BAABNQAECn8yAAImAAoK3xUiBAAOAgAmAAoK3xUiBAAOAgAAAA==.',
Lo='Lobopeste:BAABNQAECn8qAAIZAAgK7QykNgALAQAZAAgK7QykNgALAQAAAA==.Loborocco:BAAANQADCgIIAgAAAA==.Lobotomi:BAAANQADCgYIDgAAAA==.Lorantell:BAAANQADCgYIBgAAAA==.Lorelynn:BAABNQAECn8nAAIiAAgKKxnACgBLAgAiAAgKKxnACgBLAgAAAA==.Loðbrók:BAAANQAECgQIBAAAAA==.',
Lu='Luci:BAAANQADCgQIBAABNQAECgYIEgABAAAAAA==.Luckycritz:BAAANQAECgIIAQABNQAECggIDAABAAAAAA==.Lucìan:BAABNQAECn8pAAILAAYKlSIYHgA/AgALAAYKlSIYHgA/AgAAAA==.Luna:BAAANQAECgQIBAABNQAECgkJGwAPAPYbAA==.Lunaclair:BAABNQAECn8lAAMJAAoK7RN7FADkAQAJAAoK7RN7FADkAQAZAAMK8wlMtABgAAABNQAECgoKKgAkABAhAA==.Lunarielle:BAAANQAECgQIBgAAAA==.',
Ma='Mabrito:BAAANQAECgcIDgABNQAFFAcIGAADAIUVAA==.Macfly:BAABNQAECn88AAIEAAoKnRrgIwBVAgAEAAoKnRrgIwBVAgAAAA==.Macneel:BAAANQADCgEIAQABNQADCgcIGgABAAAAAA==.Magicmissile:BAAANQADCgQIBAABNQAFFAMIBQAQAHwIAA==.Malevalous:BAAANQADCgQICQABNQAECgoKMAAJAI8WAA==.Mancath:BAABNQAECn8pAAIFAAoK0Rc/YwBxAgAFAAoK0Rc/YwBxAgAAAA==.Maplè:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Marlei:BAAANQAECgUICwABNQAECggIFwAEANUXAA==.Maru:BAAANQADCgcIBwABNQAECgoKNgAKAEoaAA==.Marylayetta:BAAANQADCgYIBgAAAA==.Maxzang:BAAANQABCggIEAAAAA==.',
Me='Medenà:BAAANQADCgUICAAAAA==.Meeko:BAACNQAFFH8HAAIgAAMKOxv9DwD3AAAgAAMKOxv9DwD3AAA1AAQKfyEAAiAACQqhHMoOALwCACAACQqhHMoOALwCAAE1AAUUCAgSACAApRQA.Melfie:BAAANQAECgEIAQAAAA==.',
Mi='Midoriya:BAABNQAECn8XAAIOAAoKjRD2GQBhAQAOAAoKjRD2GQBhAQAAAA==.Mihoshi:BAAANQAECgQICAAAAA==.Mistjack:BAAANQADCggICAAAAA==.',
Mo='Moldyjack:BAAANQAECgMIBgAAAA==.Morphium:BAAANQAECgYIBgABNQAFFAUIEAAaAIIKAA==.Mortiis:BAAANQADCgMIAwAAAA==.Moxi:BAAANQADCgUIBQAAAA==.',
Mu='Murderbot:BAAANQAECggIAgAAAA==.',
My='Myzyry:BAABNQAECn8jAAIQAAoKEBWrMQAQAgAQAAoKEBWrMQAQAgAAAA==.',
['Mä']='Märtyr:BAAANQADCgUIBQAAAA==.',
['Må']='Måze:BAAANQAECgQIBAAAAA==.',
['Më']='Mërlïn:BAAANQADCgYIBgAAAA==.',
Na='Nards:BAAANQAECggICgAAAA==.Nazdormu:BAAANQAECgQICQAAAA==.',
Ne='Nebulous:BAAANQADCgUIAgAAAA==.Neisen:BAAANQAECgUIDQAAAA==.Neptune:BAAANQADCggICAAAAA==.Nevare:BAAANQAECgcIEAAAAA==.',
Ni='Nite:BAABNQAECn8zAAISAAoK3hRLlwBSAgASAAoK3hRLlwBSAgAAAA==.',
No='Nou:BAEANQAECggIBwABNQAECgkJGgAHAPIPAA==.',
Nu='Nubi:BAAANQADCgIIAgAAAA==.Nugent:BAABNQAECn8gAAIEAAoKDxoSOgC8AgAEAAoKDxoSOgC8AgAAAA==.',
Ny='Nymmie:BAAANQAECgMIAwAAAA==.Nymofthedead:BAAANQADCgcIBwAAAA==.',
Oa='Oakgrove:BAAANQADCgIIAgAAAA==.',
Ok='Okarun:BAAANQADCgEIAQAAAA==.Okiro:BAAANQADCgQIBAAAAA==.',
On='Oneforall:BAACNQAFFH8IAAIeAAMKlg0rDwDUAAAeAAMKlg0rDwDUAAA1AAQKfzcAAx4ACgpoGzQrALsCAB4ACgpoGzQrALsCAAUAAQoAABpxAQAAAAAA.',
Or='Orphen:BAAANQAECgQICAAAAA==.',
Pa='Pailly:BAAANQABCgQIBAAAAA==.Papalion:BAABNQAECn8fAAIEAAkK/Ql0rACsAQAEAAkK/Ql0rACsAQAAAA==.Paryl:BAABNQAECn8iAAIHAAcKgg1/ewAAAQAHAAcKgg1/ewAAAQAAAA==.Pawbs:BAAANQADCgYIBgAAAA==.',
Pe='Peanuts:BAAANQAECggICAAAAA==.',
Pi='Pikake:BAAANQADCgUICQAAAA==.Pinklilydrd:BAAANQADCgcIFQAAAA==.',
Pl='Plaindonut:BAABNQAECn83AAMLAAoKYCP0AwBbAwALAAoKYCP0AwBbAwADAAEKAAAYpQBPAAAAAA==.Pluffeh:BAAANQADCgYICgABNQAECgMIBQABAAAAAA==.',
Pm='Pmoney:BAAANQAECggIDAAAAA==.',
Pr='Prissidebow:BAAANQADCgcIDQAAAA==.Prissygalore:BAAANQADCgEIAQAAAA==.',
Pu='Puddinpie:BAAANQADCgEIAQAAAA==.Punkhazard:BAAANQAECgUIBQAAAA==.Putras:BAAANQABCgIIAgAAAA==.',
Qu='Quartz:BAAANQAECgcICgABNQAECgoKNgAQAL8mAA==.Quinraidar:BAAANQAECgQIAwABNQAECgoKNgAKAEoaAA==.',
Ra='Ranor:BAAANQAECgIIAgABNQAECgoKMgAmAN8VAA==.Ravenbrook:BAACNQAFFH8FAAIRAAQKNCQSAgDmAAARAAQKNCQSAgDmAAA1AAQKfzoAAhEACgq4Ji8AAPgDABEACgq4Ji8AAPgDAAAA.Ravus:BAAANQADCgIIAgAAAA==.Rawrr:BAAANQAECgUIEQAAAA==.Raxie:BAACNQAFFH8TAAQPAAUK6ArlDQBNAQAPAAUK6ArlDQBNAQAcAAMKKQWAEADFAAAlAAEKSQFiBQAxAAA1AAQKfzMABBwACgovFtgdAFECABwACQr4FNgdAFECACUABwo6EZULAIYBAA8ABAqWFzaDANIAAAAA.',
Re='Reddfoxx:BAAANQAECgcIEAAAAA==.Resepuff:BAAANQADCggIEAAAAA==.',
Rh='Rhymunky:BAAANQADCgMIAwAAAA==.',
Ri='Rifthor:BAAANQADCgYIBgAAAA==.Ripmxi:BAAANQAECgYIEgAAAA==.',
Ro='Roknarogue:BAAANQAECgEIAgAAAA==.',
Ru='Runelight:BAAANQADCgMIAwABNQAECgoKLwAKALEZAA==.Runeshock:BAABNQAECn8vAAIKAAoKsRk/IQA8AgAKAAoKsRk/IQA8AgAAAA==.Runesummon:BAAANQADCggIDAAAAA==.Rupertgiless:BAACNQAFFH8VAAIHAAcKXRA4CgDGAQAHAAcKXRA4CgDGAQA1AAQKfzkAAgcACgrkHtMRAJkCAAcACgrkHtMRAJkCAAAA.',
Sa='Sadoh:BAAANQABCgMIAwABNQAECgMIBQABAAAAAA==.Sainttristan:BAAANQABCgEIAQAAAA==.Saluran:BAAANQABCgYIBgAAAA==.Sanitariums:BAAANQADCgQIBAABNQADCgcIFwABAAAAAA==.Sannea:BAAANQADCgUICgABNQAECggIFwAEANUXAA==.Sarcastyx:BAABNQAECn8UAAIiAAcKUxC3GQCeAQAiAAcKUxC3GQCeAQAAAA==.Saværo:BAAANQADCgMIBAAAAA==.Saxines:BAAANQAECgMIBAAAAA==.',
Sc='Scaliefox:BAAANQADCgQIBAABNQAECgcIIgAPAMwQAA==.Schwarznacht:BAAANQAECgQIBAAAAA==.',
Se='Seekndestroy:BAABNQAECn8bAAIMAAgKuQbBqABCAQAMAAgKuQbBqABCAQAAAA==.Semperfimack:BAAANQADCgQJBAAAAA==.',
Sh='Shadedlock:BAAANQADCgYIBgAAAA==.Shamwhoa:BAAANQADCgYIBgAAAA==.Shankkerz:BAABNQAECn8UAAMDAAgKeQv4TwCeAQADAAgKeQv4TwCeAQAkAAQKDgaPLgCdAAAAAA==.',
Si='Simonx:BAABNQAECn8eAAIFAAkK1A0QUgC/AQAFAAkK1A0QUgC/AQAAAA==.Sindusk:BAAANQAECgYIDAAAAA==.Sitzho:BAAANQADCggIGgAAAA==.',
Sk='Skeleton:BAAANQABCgIIAgAAAA==.Skullblade:BAAANQAECgQICwAAAA==.Skybringer:BAABNQAECn8jAAIFAAgKRwZx+QArAQAFAAgKRwZx+QArAQAAAA==.Skydras:BAABNQAECn8xAAMZAAoKGx/YJQCOAgAZAAkK1B7YJQCOAgAJAAcKPRPAZAB+AQAAAA==.Skyhoof:BAAANQAECgYIBgABNQAECgoKMQAZABsfAA==.',
Sm='Smolbeans:BAAANQADCgQIBAAAAA==.Smoothscales:BAAANQADCgUIBQAAAA==.Smoothtotem:BAAANQADCggICQAAAA==.',
So='Sonofgrumpy:BAAANQADCggIEAABNQAECggIEQABAAAAAA==.Sorphium:BAAANQAECggIEQABNQAFFAUIEAAaAIIKAA==.Soxxy:BAAANQADCgEIAQABNQAECgYIEgABAAAAAA==.',
Sp='Sparhawk:BAAANQADCgYIEQAAAA==.',
St='Stham:BAAANQADCgQIBQAAAA==.Stormyprissi:BAAANQADCgUIDQAAAA==.Strombjorn:BAAANQAECgEIAQAAAA==.',
Ta='Talie:BAAANQAECgUICQABNQAECgcIDQABAAAAAA==.Tasireth:BAAANQADCgMIAwAAAA==.',
Te='Tessi:BAABNQAECn8iAAMGAAcKcQnKHAAIAQAGAAYKWQvKHAAIAQASAAUK1QLOhAG7AAAAAA==.Testamental:BAAANQAECgIJAgAAAA==.',
Th='Thaloran:BAAANQADCgcICAAAAA==.Thalrian:BAABNQAECn8ZAAIcAAoKYB11BwCVAgAcAAoKYB11BwCVAgABNQAECgoKPQAQANMiAA==.Theberes:BAAANQAECgYIBgAAAA==.Thelance:BAAANQABCggIDQAAAA==.Theylive:BAAANQADCgcIBwAAAA==.Thighs:BAAANQAECgQIBgAAAA==.Thordanil:BAABNQAECn8YAAMFAAgKOA+L2gBmAQAFAAcKOA+L2gBmAQATAAEKAABCZwBGAAAAAA==.',
Ti='Tiahina:BAAANQADCgUIBQAAAA==.Tioklarus:BAAANQAECgUIBAAAAA==.',
To='Tokifuji:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Tourettes:BAAANQADCggJCAAAAA==.Toya:BAABNQAECn83AAMaAAoKjxdLEgBeAgAaAAoKjxdLEgBeAgAbAAQKZwUhgACzAAAAAA==.',
Tr='Transfurmer:BAAANQADCgMIAwABNQAECgoKOQAYAF0kAA==.Trashdk:BAAANQADCgcIDQAAAA==.Trevain:BAAANQADCgcIGgAAAA==.Trivia:BAAANQADCgcIJAAAAA==.Truthordare:BAABNQAECn8WAAIiAAUKdQNeQwC3AAAiAAUKdQNeQwC3AAAAAA==.',
Tu='Turtei:BAAANQADCggICAABNQAFFAcIGgAOAGAiAA==.Turtl:BAACNQAFFH8aAAIOAAcKYCJ8AQClAgAOAAcKYCJ8AQClAgA1AAQKfzcAAg4ACgrwJi0BAN0DAA4ACgrwJi0BAN0DAAAA.',
Ty='Tylenolz:BAAANQADCgYIDAAAAA==.',
Ug='Uglypetguy:BAAANQADCgEIAQAAAA==.Uglypriest:BAAANQADCggIDgAAAA==.Uglyrogue:BAAANQAECgIIAgAAAA==.',
Ul='Ulgrym:BAAANQADCgcIGgAAAA==.',
Un='Unbalancéd:BAAANQADCgcIFwAAAA==.',
Va='Vaeadin:BAAANQAECgEIAQAAAA==.Vahra:BAAANQADCgcIFgAAAA==.Valantis:BAAANQAECgQIBAAAAA==.Valgaskav:BAACNQAFFH8IAAIFAAUKZRotCwDsAAAFAAUKZRotCwDsAAA1AAQKfx8AAgUACAr6I25SAJ4CAAUACAr6I25SAJ4CAAAA.Valkor:BAAANQADCgMIAgAAAA==.Valric:BAAANQAECggIAgAAAA==.',
Ve='Vegasnight:BAAANQADCggIEwAAAA==.Vella:BAAANQAECgIIAQAAAA==.Venithan:BAAANQAECgYIDwAAAA==.Verdesoul:BAAANQADCgQIBAABNQAECgUIEgABAAAAAA==.',
Vi='Vikkrum:BAAANQADCgYICwABNQADCgcIGgABAAAAAA==.Virani:BAAANQAECgYICQAAAA==.',
Vo='Voladro:BAAANQAECgUIBQAAAA==.Volanie:BAAANQADCgYIBgAAAA==.Volos:BAABNQAECn8iAAIFAAYKIhII1gBvAQAFAAYKIhII1gBvAQAAAA==.Vordaman:BAABNQAECn8tAAMJAAgKMBaTVAC/AQAJAAgKMBaTVAC/AQAYAAEKYAXWtAArAAAAAA==.',
Vy='Vynír:BAACNQAFFH8JAAMiAAUKjg3vDwCUAAAHAAQKBApwKADEAAAiAAIKBw3vDwCUAAA1AAQKfy0ABCMACgr8IKMBAHwCAAcACArhINcyAL0CACMACQrqGaMBAHwCACIABApsHFsoADYBAAAA.',
Wa='Waandur:BAAANQADCgEIAQAAAA==.Waghoba:BAACNQAFFH8GAAIkAAIK0hRdAwCbAAAkAAIK0hRdAwCbAAA1AAQKf3MAAiQACgqEJksAAAMEACQACgqEJksAAAMEAAAA.Waito:BAAANQADCggIDQAAAA==.Wandä:BAABNQAECn8oAAMOAAoK6BlCDgAJAgAOAAgKAxdCDgAJAgAmAAcK/RvJCABSAQAAAA==.Warborn:BAAANQADCggIDAAAAA==.Warrionomous:BAACNQAFFH8FAAIQAAMKfAiLHQB9AAAQAAMKfAiLHQB9AAA1AAQKfy4AAhAACgpQGCRUAI4CABAACgpQGCRUAI4CAAAA.Washu:BAABNQAECn83AAMVAAoKvxhADwBYAgAVAAoKvxhADwBYAgAIAAUKagggFgCIAAAAAA==.',
We='Wetkittyy:BAAANQABCgUICAAAAA==.',
Wh='Whobetter:BAAANQADCgYICQAAAA==.',
Wi='Winterous:BAAANQAECgQIBgAAAA==.Wisdomheart:BAAANQAECgIIAgAAAA==.',
Wo='Wonderbread:BAABNQAECn88AAIFAAoKthCNUADEAQAFAAoKthCNUADEAQAAAA==.',
['Wá']='Wáshu:BAAANQAECgQICwAAAA==.',
Xa='Xaani:BAAANQAECgIIAgAAAA==.',
Xe='Xenan:BAABNQAECn8fAAIFAAcKaApM7ABDAQAFAAcKaApM7ABDAQAAAA==.',
Xt='Xtrolldinary:BAAANQAECgMIAgAAAA==.',
Ye='Yeastmode:BAABNQAECn8dAAMEAAgKqQrdwwB6AQAEAAgKqQrdwwB6AQANAAEKogKQnQAhAAAAAA==.',
Yi='Yingsol:BAAANQAECgMIAgABNQAECgYIDwABAAAAAA==.',
Yo='Yonahh:BAAANQAECgcIDQAAAA==.',
Yv='Yvelthilios:BAAANQAECggICQAAAA==.',
Za='Zangsha:BAAANQADCgcIBwAAAA==.',
Ze='Zeebra:BAABNQAECn8kAAIEAAgKixF1RADSAQAEAAgKixF1RADSAQAAAA==.Zeg:BAABNQAECn8nAAMKAAoK3CATDQD3AgAKAAoK3CATDQD3AgAMAAIK1gsLFAFlAAAAAA==.Zega:BAAANQADCgcIBwAAAA==.Zegafur:BAAANQAECgIIAgAAAA==.',
Zi='Zillionbucks:BAABNQAECn8UAAIQAAkKJBfOcQA/AgAQAAkKJBfOcQA/AgAAAA==.Zillionbúcks:BAAANQAECgUICQABNQAECgkJFAAQACQXAA==.',
Zo='Zoidworf:BAAANQADCggICwAAAA==.',
Zu='Zulg:BAAANQADCgQIBAAAAA==.Zulgore:BAAANQAECgYIBgAAAA==.Zullee:BAAANQADCgIIAgAAAA==.',
['Zê']='Zêddicus:BAABNQAECn84AAMiAAoKOBMmDQC1AAAHAAcK8xBiYQBBAQAiAAYKThUmDQC1AAAAAA==.',
['Áq']='Áquafina:BAABNQAECn8vAAISAAoK7QvDxwD1AQASAAoK7QvDxwD1AQAAAA==.',
['Ðö']='Ðö:BAABNQAECn8cAAIRAAgKPBYuCACbAQARAAgKPBYuCACbAQAAAA==.',
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
