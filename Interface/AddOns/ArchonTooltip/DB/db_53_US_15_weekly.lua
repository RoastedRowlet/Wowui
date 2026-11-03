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

local lookup = {'Unknown-Unknown','Druid-Guardian','Druid-Balance','Hunter-BeastMastery','Paladin-Retribution','Mage-Frost','Warlock-Demonology','DemonHunter-Vengeance','DeathKnight-Unholy','Shaman-Restoration','Druid-Restoration','Shaman-Elemental','Hunter-Marksmanship','Monk-Brewmaster','Priest-Holy','Warrior-Arms','Warrior-Fury','Mage-Arcane','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Feral','Warrior-Protection','Shaman-Enhancement','Monk-Windwalker','DeathKnight-Frost','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Rogue-Outlaw','Paladin-Holy','Mage-Fire','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Warlock-Destruction','Warlock-Affliction','Priest-Discipline',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aaril:BAAANQADCgcIIAAAAQ==.',
Ab='Abnaren:BAAANQAECgQIBAABNQAECgQIBQABAAAAAA==.Abrams:BAABNQAECn8wAAMCAAoKiRCeHgCqAQACAAoKiRCeHgCqAQADAAgKAgeVWAByAQAAAA==.Absínthè:BAAANQABCgQIBAAAAA==.',
Ag='Agnass:BAAANQADCgcIHwAAAA==.',
Ak='Akina:BAABNQAECn8eAAIEAAkKoBbPcACWAQAEAAkKoBbPcACWAQAAAA==.',
Al='Alcholic:BAAANQAECggIAwAAAA==.Aldea:BAAANQADCgYIBgAAAA==.Alialista:BAABNQAECn8iAAIEAAgKHhQnlQDeAQAEAAgKHhQnlQDeAQAAAA==.Alirrayia:BAAANQADCgMIAwAAAA==.Alirrayiia:BAACNQAFFH8HAAIFAAMKYAQCFwCuAAAFAAMKYAQCFwCuAAA1AAQKf0AAAgUACgrpE7pvALEBAAUACgrpE7pvALEBAAAA.Allmight:BAAANQADCgMIAwAAAA==.Allystar:BAAANQADCgUICgAAAA==.Alvidor:BAABNQAECn8wAAIGAAkKugiZEQAzAQAGAAkKugiZEQAzAQAAAA==.',
Am='Amachine:BAAANQADCggIDgABNQAFFAcIGgAHAPkeAA==.Amethen:BAAANQAECgQICgAAAA==.Amybabe:BAABNQAECn8UAAIEAAYKnhH2zQBlAQAEAAYKnhH2zQBlAQAAAA==.',
An='Andydufresne:BAAANQAECgcICwABNQAECgoKRgAIAAslAA==.Anestesiax:BAAANQAECgYIBAAAAA==.Anorivia:BAABNQAECn8yAAIJAAkK9Ai3LQBJAQAJAAkK9Ai3LQBJAQAAAA==.',
Ap='Apolloerosp:BAAANQAECgYIDwABNQAECgkJLwAKAOoRAA==.Apollossham:BAABNQAECn8vAAIKAAkK6hFZdACvAQAKAAkK6hFZdACvAQAAAA==.',
Ar='Araluen:BAAANQABCgMIAwAAAA==.Arkagob:BAAANQADCgcIBwAAAA==.Arragora:BAAANQAECgQIBQAAAA==.Arrowdynamix:BAABNQAECn8nAAIEAAoK7Re4KwBlAgAEAAoK7Re4KwBlAgAAAA==.',
As='Ashyani:BAAANQADCgUIBQAAAA==.',
At='Atlan:BAAANQADCgUIBQABNQAECgcIKQALAJUiAA==.',
Au='Aurnhadon:BAAANQABCggIDAAAAA==.',
Ba='Babbayagga:BAABNQAECn8pAAIMAAoKxxLrUQAxAgAMAAoKxxLrUQAxAgAAAA==.Baji:BAABNQAECn89AAMKAAoKIRw9FwDQAgAKAAoKIRw9FwDQAgAMAAgK0xYtXQAKAgAAAA==.Barefaall:BAACNQAFFH8MAAMEAAgK9gr4CwCRAQAEAAUK1wr4CwCRAQANAAQKFQseFgDdAAA1AAQKf0oAAwQACgozJl8fABoDAAQACQqHJl8fABoDAA0ABgo/IbokACcCAAAA.Barefalls:BAABNQAECn8eAAMEAAoK5BSISQAAAgAEAAoK3RSISQAAAgANAAEKOhQmTgBMAAABNQAFFAgIDAAEAPYKAA==.Baénoth:BAAANQAECgMIBAAAAA==.',
Be='Bealzebub:BAAANQAECgYIBAAAAA==.Bellucci:BAAANQADCgcICAABNQAECgkJKwAHACENAA==.Berglock:BAAANQADCgcIBwABNQAECggIDwABAAAAAA==.Bergonator:BAAANQAECggIDwAAAA==.Bergue:BAAANQADCgQIBAABNQAECggIDwABAAAAAA==.Berrodiah:BAAANQADCgcIDQABNQAECgoKMAAOAJkaAA==.Bestlays:BAAANQAECgMIAQAAAA==.Bettiepage:BAAANQAECgUIBAAAAA==.',
Bh='Bheiroth:BAABNQAECn83AAIPAAoKXiPACwBiAwAPAAoKXiPACwBiAwAAAA==.',
Bl='Blackchapell:BAAANQABCgYICQAAAA==.Blewmyload:BAAANQAECggIDQAAAA==.Bluett:BAAANQADCgcIHAAAAA==.',
Bo='Bogertus:BAABNQAECn9AAAMQAAoKvya4AQCFAwAQAAoKvya4AQCFAwARAAMK/h/YHgDJAAAAAA==.Boomertunes:BAAANQADCgQIBAAAAA==.Boxnasty:BAAANQADCgEIAQAAAA==.',
Br='Brein:BAABNQAECn8wAAILAAoKCyLSAgC/AwALAAoKCyLSAgC/AwAAAA==.',
Bu='Bucketeer:BAAANQAECgUICQAAAA==.Burzona:BAAANQABCgMIAwAAAA==.',
Ca='Cameltoetoe:BAAANQAECgEIAgAAAA==.Canaprey:BAABNQAECn8WAAIEAAkK2w/7kwDhAQAEAAkK2w/7kwDhAQAAAA==.Cathogin:BAAANQADCggIDgAAAA==.Catsdruid:BAAANQADCgcIBwAAAA==.Catshunter:BAAANQAECgUICgAAAA==.',
Ce='Celaa:BAAANQADCgQIBAABNQAECgkJHgAEAKAWAA==.Celebrían:BAAANQAECgEIAQAAAA==.Celor:BAAANQABCgQIBgAAAA==.',
Ch='Chanka:BAAANQADCgcIFgAAAA==.Chantillary:BAAANQADCgcIHwAAAA==.Charise:BAAANQAECgUIDAAAAA==.Cheesy:BAAANQADCgYIDAAAAA==.Chopzullee:BAAANQAECgUICgAAAA==.',
Ci='Cinnaz:BAAANQAECgUICwABNQAECgoKNQASAN4UAA==.',
Cl='Clortho:BAAANQAECgUIDQAAAA==.Clorthö:BAAANQADCgYIFAAAAA==.',
Co='Colbiw:BAAANQABCgIIAgAAAA==.Colljack:BAACNQAFFH8cAAITAAcKMB/JAQA7AgATAAcKMB/JAQA7AgA1AAQKfzQAAhMACgpQJT8DAC0DABMACgpQJT8DAC0DAAAA.Corvath:BAAANQAECgUIEQAAAA==.',
Cr='Cryptoe:BAABNQAECn9QAAISAAoK8R5aQQACAwASAAoK8R5aQQACAwAAAA==.',
Cy='Cyngin:BAAANQAECgQIBAAAAA==.',
Da='Daedamus:BAAANQAECgEIAQAAAA==.Daedelus:BAABNQAECn8oAAMUAAoK6xbgFgDOAQAUAAoK6xbgFgDOAQAIAAIKew3hKABuAAAAAA==.Daglon:BAABNQAECn8bAAIFAAkK9xPsZQDIAQAFAAkK9xPsZQDIAQAAAA==.Daraedra:BAAANQAECgIIAgAAAA==.Dardolur:BAAANQADCgIIAgAAAA==.Darknìght:BAABNQAECn8eAAIVAAcK8x3/MAAgAgAVAAcK8x3/MAAgAgAAAA==.Darkraider:BAAANQAECgQICAAAAA==.Darkshade:BAAANQADCgMIAwAAAA==.Darkslayer:BAAANQADCgMIBQAAAA==.Darkthyr:BAAANQAECgQIBQAAAA==.',
De='Deeznutticus:BAACNQAFFH8NAAIQAAYKCBP4FQB5AQAQAAYKCBP4FQB5AQA1AAQKfz8AAhAACgomIJ0eAD0DABAACgomIJ0eAD0DAAAA.Demonspud:BAABNQAECn8UAAIUAAcKLg5wNgCQAQAUAAcKLg5wNgCQAQAAAA==.Dersan:BAAANQADCgIIAgAAAA==.Destriant:BAABNQAECn9BAAITAAoK9yAuBgDTAgATAAoK9yAuBgDTAgAAAA==.Devourer:BAAANQABCgMIAwAAAA==.Dewburt:BAAANQAECgcIBwAAAA==.Deylia:BAAANQAECgYICgABNQAFFAUIGAAPAOgKAA==.',
Dh='Dhori:BAAANQADCgcIHwAAAA==.',
Di='Dillion:BAAANQAECgEIAQABNQAECgkJKwAHACENAA==.Dionin:BAAANQADCgUICgAAAA==.Dirky:BAABNQAECn8UAAIWAAoKtws5EgBWAQAWAAoKtws5EgBWAQAAAA==.Dirtychai:BAABNQAECn8aAAIFAAkKRgu9fACTAQAFAAkKRgu9fACTAQAAAA==.Disappear:BAAANQADCgYICgABNQAECgoKNQASAN4UAA==.Dizzyhealz:BAAANQAECgEIAQAAAA==.Dizzyhuntres:BAAANQADCgYIBwAAAA==.',
Do='Dooberrt:BAAANQAECgcIBQAAAA==.Dooberto:BAABNQAECn8pAAMXAAoK1xWcDAC2AQAXAAoK1xWcDAC2AQAQAAMKywReMgFwAAAAAA==.Dooburt:BAABNQAECn8aAAMFAAkKFwcn8gA4AQAFAAgKfQcn8gA4AQATAAcK3QQ5PgCEAAAAAA==.',
Dr='Dracaric:BAAANQADCgYIBgAAAA==.Draeca:BAAANQADCgcIHAAAAA==.Dragondznut:BAAANQADCggIDwAAAA==.Drfrostie:BAAANQAECgYIBgAAAA==.Driatin:BAAANQAECgEIAQAAAA==.',
Du='Durø:BAABNQAECn9CAAIUAAoKQyQ1BgDlAgAUAAoKQyQ1BgDlAgAAAA==.',
['Dè']='Dègenerate:BAABNQAECn9HAAIXAAoK8SO7AgABAwAXAAoK8SO7AgABAwAAAA==.',
Ed='Eddy:BAABNQAECn8yAAIYAAoK6w/zFQAJAgAYAAoK6w/zFQAJAgAAAA==.',
Ei='Eilae:BAAANQADCgcIDQAAAA==.Einherjarr:BAAANQADCgYICgAAAA==.',
El='Eldumpling:BAABNQAECn8bAAIZAAkKsBSdGQCnAQAZAAkKsBSdGQCnAQAAAA==.Elefante:BAAANQADCgYIDAAAAA==.',
Ep='Epicnym:BAABNQAECn8rAAMMAAcKvBn4fACtAQAMAAYK5Br4fACtAQAYAAcK/hF1GABJAQAAAA==.',
Es='Esdeath:BAABNQAECn8pAAQJAAgKzgz6KgBbAQAJAAgKLwv6KgBbAQAaAAYKowwbXAA4AQAbAAMK4gHauQBUAAAAAA==.',
Ev='Evoberg:BAAANQABCgYIBgABNQAECggIDwABAAAAAA==.',
Ex='Extenze:BAABNQAECn8pAAIUAAkKARdEFQDhAQAUAAkKARdEFQDhAQAAAA==.',
Fa='Faegrin:BAAANQAECgQIBAAAAA==.',
Fe='Feda:BAAANQADCgQIBAAAAA==.Felyna:BAAANQAECggICAAAAA==.Ferryman:BAABNQAECn8eAAIEAAgKbRGtgwBpAQAEAAgKbRGtgwBpAQAAAA==.',
Fi='Findria:BAAANQADCgYIBgABNQAFFAUIBwAEABUZAA==.',
Fo='Forphium:BAACNQAFFH8QAAMcAAUKggoTCQBcAQAcAAUKwgcTCQBcAQAdAAEKTQtyIABHAAA1AAQKfy0AAxwACgqOHxcPAIkCABwACQrvIBcPAIkCAB0AAQrnFXGcAEQAAAAA.',
Fr='Fredolf:BAAANQADCgQJBAAAAA==.Freespirit:BAABNQAECn8cAAMNAAoKVh+PEwDRAQANAAkKXSOPEwDRAQAEAAEKIwPeOAEkAAABNQAFFAcIHQAeACIhAA==.Friarkuck:BAAANQADCgEIAQAAAA==.Frierenn:BAAANQADCgYIBgAAAA==.Frosteddonut:BAAANQAECggIDAABNQAECgoKPgALAAIlAA==.Frostieheals:BAAANQAECgQIAwAAAA==.',
Ft='Fthrhealgood:BAAANQAECggICAAAAA==.',
Ga='Gahlina:BAAANQAECgEIAQAAAA==.Gambaaddict:BAABNQAECn8bAAIfAAgKoBIdCgDdAQAfAAgKoBIdCgDdAQAAAA==.Ganhammer:BAAANQADCgIIAgAAAA==.Garshan:BAAANQAECgMIAwAAAA==.',
Ge='Genestarwind:BAAANQAECgQIDAAAAA==.',
Gh='Ghexn:BAAANQADCgIIAgAAAA==.',
Gi='Gilleyy:BAAANQAECgQICQAAAA==.Gird:BAABNQAECn8uAAIgAAgKCBZzOwD2AQAgAAgKCBZzOwD2AQAAAA==.Girdlock:BAAANQAECgIIAgAAAA==.',
Gl='Glyph:BAAANQAECgYICwABNQAECgoKNQAKAI8bAA==.',
Gn='Gnymesis:BAAANQADCgYICwAAAA==.',
Go='Goatmonger:BAAANQAECggICgAAAA==.Goinpostal:BAAANQADCgYICwAAAA==.Goldblade:BAAANQAECggIEAAAAA==.Gordek:BAABNQAECn8YAAIFAAoKLRXsngDkAQAFAAoKLRXsngDkAQAAAA==.',
Gr='Graceteena:BAAANQADCgUIBAAAAA==.Grahra:BAAANQABCgIIBAAAAA==.Grantaron:BAABNQAECn88AAIFAAoK7Bx5OQBRAgAFAAoK7Bx5OQBRAgAAAA==.Grimskul:BAABNQAECn81AAIJAAkKLxkBMQBqAgAJAAkKLxkBMQBqAgAAAA==.Grntitan:BAAANQADCgcIHQAAAA==.Gruid:BAAANQAECgMIAwAAAA==.',
Gw='Gwoohoori:BAABNQAECn8kAAIFAAkKwxexZADMAQAFAAkKwxexZADMAQAAAA==.',
Ha='Halukari:BAAANQADCggIDAABNQAFFAUIGAAPAOgKAA==.Haléon:BAABNQAECn8WAAISAAcKhAbS4gC8AAASAAcKhAbS4gC8AAAAAA==.Hamnier:BAAANQABCgcIDwAAAA==.Harfnan:BAAANQADCgYICQAAAA==.Harperlee:BAAANQAECggICgAAAA==.Harrin:BAAANQADCggIEQAAAA==.',
He='Headshotty:BAAANQAECgUICAAAAA==.Hellfire:BAAANQADCgYIBgAAAA==.Hezrel:BAAANQAECgcICAAAAA==.',
Hi='Hinal:BAABNQAECn8dAAMFAAcKyhSXsAC+AQAFAAcKyhSXsAC+AQATAAYKDA3nOACeAAAAAA==.',
Ho='Holyenabler:BAAANQAECgYIEAAAAA==.Honzo:BAABNQAECn8fAAMbAAkKZwhXbgA8AQAbAAkKGAhXbgA8AQAaAAMKJAlchwBlAAAAAA==.',
Hu='Hungor:BAAANQABCgQIBAAAAA==.',
['Hè']='Hèalz:BAAANQAECgEIAQABNQAECggIIQARADwWAA==.',
Ic='Iceberg:BAAANQADCgEIAQABNQAECggIDwABAAAAAA==.Icecrystal:BAAANQABCgIIAgAAAA==.',
Ih='Iheartbailey:BAAANQADCgQIBAAAAA==.',
Im='Imcruel:BAACNQAFFH8aAAISAAcKjhsEDgAHAgASAAcKjhsEDgAHAgA1AAQKf04ABBIACgpIJQkIADYDABIACgooJQkIADYDACEAAwoBIqEDACYBAAYAAQpVIXAqAGIAAAAA.Iminyë:BAAANQAECgYICQAAAA==.',
Io='Iorese:BAAANQADCggIDwAAAA==.',
Ir='Iriana:BAEANQADCgYIMQABNQAECgMIBgABAAAAAA==.',
Ja='Jabes:BAAANQAECgUIBQAAAA==.Jackiegan:BAAANQADCgEIAQAAAA==.Jagershamer:BAAANQAECgcIBwABNQAECggIBwABAAAAAA==.Jasperine:BAAANQAECggIEQABNQAFFAcIHQAeACIhAA==.',
Je='Jenneldots:BAAANQAECgUIEgABNQAECgYICgABAAAAAA==.Jerce:BAAANQADCgUICQAAAA==.',
Jo='Johnnyhuntz:BAAANQADCgYICAAAAA==.Joregis:BAAANQAECggICAAAAA==.',
Ju='Juacqer:BAAANQADCgcIGgAAAA==.Junamara:BAAANQAECgQICQAAAA==.',
Ka='Kaant:BAABNQAECn81AAMMAAoKvhoKHwBMAgAMAAoKvhoKHwBMAgAKAAcK1BZmSAC+AQAAAA==.Kaetiegh:BAAANQADCgUIDwAAAA==.Kaidevyn:BAABNQAECn8hAAIaAAgKHRKbPgDRAQAaAAgKHRKbPgDRAQAAAA==.Kardead:BAAANQAECgMIBAAAAA==.Kardren:BAAANQADCgEIAQAAAA==.Kat:BAAANQADCgQICAAAAA==.',
Kb='Kbang:BAAANQAECgIIAgAAAA==.',
Ke='Keiran:BAABNQAECn8+AAIEAAoKDiBSGgC4AgAEAAoKDiBSGgC4AgAAAA==.Kenix:BAAANQADCgUIDQABNQADCgYICgABAAAAAA==.',
Kh='Khalnerys:BAABNQAECn8hAAQiAAYKzQYhFwCaAAAiAAYKvgYhFwCaAAAjAAQKUALQQwCFAAAkAAMKTQWSHgBsAAAAAA==.Khaotick:BAEBNQAECn8rAAQHAAoKJRlsVQBWAgAHAAkKcxhsVQBWAgAlAAQK5A4VPQDNAAAmAAEKAABJMwAtAAABNQAECgkJGgAHAPIPAA==.Khoulock:BAABNQAECn8hAAQHAAkK6B8HLgDOAgAHAAkKfR8HLgDOAgAlAAYK4B/1FwCtAQAmAAEKAABlLAA+AAAAAA==.',
Ki='Kimmi:BAAANQAECgQIBQAAAA==.Kimmispally:BAAANQADCggICAAAAA==.Kiro:BAAANQADCgYIDAAAAA==.',
Ko='Kotawar:BAAANQAECgMIAwAAAA==.Kozana:BAAANQADCgIIAgAAAA==.',
Kt='Kthxbye:BAAANQAECggIBwAAAA==.',
Ku='Kuraishin:BAABNQAECn8zAAIWAAoKjyRtAQBJAwAWAAoKjyRtAQBJAwAAAA==.Kuterr:BAAANQADCgUIBQAAAA==.',
Ky='Kyrae:BAAANQADCgYIEAABNQAECgYIDwABAAAAAA==.Kyrub:BAAANQABCggICAAAAA==.',
La='Latheal:BAAANQADCgcIFAAAAA==.Latto:BAABNQAECn8UAAMbAAUKNBM6fAAIAQAbAAUKNBM6fAAIAQAaAAEKAABhqwA3AAABNQAECgYICgABAAAAAA==.',
Le='Lengex:BAAANQAECgcIBQAAAA==.Lero:BAAANQAECgIIAgAAAA==.Levatan:BAAANQAECgEIAQAAAA==.Lexoh:BAAANQAECgQIAgAAAA==.',
Li='Lilieth:BAAANQADCgcIGgAAAA==.Liltankarmor:BAAANQAECgYICgAAAA==.Lindir:BAACNQAFFH8HAAIEAAUKFRnhDgD1AAAEAAUKFRnhDgD1AAA1AAQKfzQAAgQACgo/Ja0MAHkDAAQACgo/Ja0MAHkDAAAA.Liquid:BAACNQAFFH8JAAIeAAYKCAzABQAbAQAeAAYKCAzABQAbAQA1AAQKfzIAAx4ACgpjHNkLAHMCAB4ACgpjHNkLAHMCACcAAQq0A2cuACgAAAAA.Litasfk:BAAANQAECgQICAAAAA==.Lithic:BAAANQABCgIIAgAAAA==.Liuni:BAABNQAECn82AAIOAAoK4BX5BQD4AQAOAAoK4BX5BQD4AQAAAA==.',
Lo='Lobopeste:BAABNQAECn8zAAIbAAkKhA3LNABKAQAbAAkKhA3LNABKAQAAAA==.Loborocco:BAAANQADCgIIAgAAAA==.Lobotomi:BAAANQADCgYIDgAAAA==.Lorantell:BAAANQADCgYIBgAAAA==.Lorelynn:BAABNQAECn8qAAIlAAkKDxnACgBLAgAlAAkKDxnACgBLAgAAAA==.Loðbrók:BAAANQAECgUIBwAAAA==.',
Lu='Luci:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.Luckycritz:BAAANQAECgIIAQABNQAECgcIDgABAAAAAA==.Lucìan:BAABNQAECn8pAAILAAYKlSIYHgA/AgALAAYKlSIYHgA/AgAAAA==.Luna:BAAANQAECgQIBAABNQAECgkJGwAPAPYbAA==.Lunaclair:BAABNQAECn8sAAMJAAoKXxbxFgAHAgAJAAoKXxbxFgAHAgAbAAMK8wlMtABgAAABNQAECgoKMwAWAI8kAA==.Lunarielle:BAAANQAECgQIBgAAAA==.',
Ma='Mabrito:BAAANQAECgcIDgABNQAFFAcIGAADAIUVAA==.Macfly:BAABNQAECn9EAAIEAAoK6RprMABTAgAEAAoK6RprMABTAgAAAA==.Macneel:BAAANQADCgEIAQABNQADCgcIHgABAAAAAA==.Magicmissile:BAAANQADCgQIBAABNQAFFAMIBQAQAHwIAA==.Malevalous:BAAANQADCgQICQABNQAECgoKNgAJANsYAA==.Mancath:BAABNQAECn8vAAIFAAoKMhk/YwBxAgAFAAoKMhk/YwBxAgAAAA==.Maplè:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Marlei:BAAANQAECgUICwABNQAECgkJHgAEAKAWAA==.Maru:BAAANQADCgcIBwABNQAECgoKPQAKACEcAA==.Marylayetta:BAAANQADCgYIBgAAAA==.Maxzang:BAAANQABCggIEAAAAA==.',
Me='Medenà:BAAANQADCgUICAAAAA==.Meeko:BAACNQAFFH8HAAIjAAMKOxv9DwD3AAAjAAMKOxv9DwD3AAA1AAQKfyEAAiMACQqhHMoOALwCACMACQqhHMoOALwCAAE1AAUUCAgTACMApRQA.Melfie:BAAANQAECgEIAQAAAA==.',
Mi='Midoriya:BAABNQAECn8gAAIZAAoKShbHEQAQAgAZAAoKShbHEQAQAgAAAA==.Mihoshi:BAAANQAECgUICgAAAA==.Mistjack:BAAANQADCggICAAAAA==.',
Mo='Moldyjack:BAAANQAECggIDgAAAA==.Morphium:BAAANQAECgYIBgABNQAFFAUIEAAcAIIKAA==.Mortiis:BAAANQADCgMIAwAAAA==.Moxi:BAAANQADCgUIBQAAAA==.',
Mu='Murderbot:BAAANQAECggIAgAAAA==.',
My='Myzyry:BAACNQAFFH8GAAIQAAMKaAn7GADDAAAQAAMKaAn7GADDAAA1AAQKfycAAhAACgpeFrM/ABcCABAACgpeFrM/ABcCAAAA.',
['Mä']='Märtyr:BAAANQADCgUIBQAAAA==.',
['Må']='Måze:BAAANQAECgQIBAAAAA==.',
['Më']='Mërlïn:BAAANQADCgYIBgAAAA==.',
Na='Nards:BAAANQAECggICgAAAA==.Nazdormu:BAAANQAECgYIDwAAAA==.',
Ne='Nebulous:BAAANQADCgUIBQAAAA==.Neisen:BAAANQAECggIEwAAAA==.Neptune:BAAANQADCggICAAAAA==.Nevare:BAAANQAECgcIEAAAAA==.',
Ni='Nite:BAABNQAECn81AAISAAoK3hRLlwBSAgASAAoK3hRLlwBSAgAAAA==.',
No='Nou:BAEANQAECggIBwABNQAECgkJGgAHAPIPAA==.',
Nu='Nubi:BAAANQADCgIIAgAAAA==.Nugent:BAABNQAECn8jAAIEAAoK8BoSOgC8AgAEAAoK8BoSOgC8AgAAAA==.',
Ny='Nymmie:BAAANQAECgQIBQAAAA==.Nymofthedead:BAAANQADCgcIBwAAAA==.',
Oa='Oakgrove:BAAANQADCgIIAgAAAA==.',
Ok='Okarun:BAAANQADCgEIAQAAAA==.Okiro:BAAANQADCgQIBAAAAA==.',
On='Oneforall:BAACNQAFFH8JAAIgAAQKDg/YDgAZAQAgAAQKDg/YDgAZAQA1AAQKf0EAAyAACgoHHDIbALECACAACgoHHDIbALECAAUAAQoAAJagAQAAAAAA.',
Or='Orphen:BAAANQAECgcIDAAAAA==.',
Pa='Pailly:BAAANQABCgQIBAAAAA==.Papalion:BAABNQAECn8gAAIEAAoKKAl0rACsAQAEAAoKKAl0rACsAQAAAA==.Paryl:BAABNQAECn8rAAIHAAkKIQ1sYgB0AQAHAAkKIQ1sYgB0AQAAAA==.Pawbs:BAAANQADCgYIBgAAAA==.',
Pe='Peanuts:BAAANQAECggICAAAAA==.',
Pi='Pikake:BAAANQADCgUICQAAAA==.Pinklilydrd:BAAANQADCgcIGQAAAA==.',
Pl='Plaindonut:BAABNQAECn8+AAMLAAoKAiVaAQADBAALAAoKAiVaAQADBAADAAEKAAAYpQBPAAAAAA==.Pluffeh:BAAANQADCgYICgABNQAECgMIBQABAAAAAA==.',
Pm='Pmoney:BAAANQAECgcIDgAAAA==.',
Pr='Prissidebow:BAAANQADCgcIEQAAAA==.Prissygalore:BAAANQADCgEIAQAAAA==.',
Pu='Puddinpie:BAAANQADCgEIAQAAAA==.Punkhazard:BAAANQAECgUIBQAAAA==.Putras:BAAANQABCgIIAgAAAA==.',
Qu='Quartz:BAAANQAECgYICgABNQAECgoKQAAQAL8mAA==.Quinraidar:BAAANQAECgQIAwABNQAECgoKPQAKACEcAA==.',
Ra='Ranor:BAAANQAECgIIAgABNQAECgoKNgAOAOAVAA==.Ravenbrook:BAACNQAFFH8FAAIRAAQKNCQSAgDmAAARAAQKNCQSAgDmAAA1AAQKf0EAAhEACgrBJi8AAPgDABEACgrBJi8AAPgDAAAA.Ravus:BAAANQADCgIIAgAAAA==.Rawrr:BAABNQAECn8YAAIVAAcKvgY/RgDZAAAVAAcKvgY/RgDZAAAAAA==.Raxie:BAACNQAFFH8YAAQPAAUK6AoAEgBLAQAPAAUK6AoAEgBLAQAeAAQKZgvSCQDRAAAnAAEKSQFiBQAxAAA1AAQKfzcABB4ACgq1GNgdAFECAB4ACQraF9gdAFECACcABwo6EZULAIYBAA8ABAqWFw2dAM8AAAAA.',
Re='Reddfoxx:BAABNQAECn8XAAMdAAoKKwyVRQCwAQAdAAkKtQuVRQCwAQAcAAUK4Ar+gADKAAAAAA==.Resepuff:BAAANQADCggIEAAAAA==.',
Rh='Rhymunky:BAAANQADCgMIAwAAAA==.',
Ri='Rifthor:BAAANQADCgYIBgAAAA==.Ripmxi:BAAANQAECgYIEgAAAA==.',
Ro='Roknarogue:BAAANQAECgEIAgAAAA==.',
Ru='Runelight:BAAANQADCgUICAABNQAECgoKNQAKAI8bAA==.Runeshock:BAABNQAECn81AAIKAAoKjxvZIgB7AgAKAAoKjxvZIgB7AgAAAA==.Runestick:BAAANQADCgUIBQABNQAECgoKNQAKAI8bAA==.Runesummon:BAAANQADCggIDAAAAA==.Rupertgiless:BAACNQAFFH8VAAIHAAcKXRA4CgDGAQAHAAcKXRA4CgDGAQA1AAQKf0IAAgcACgpQHz8MAPACAAcACgpQHz8MAPACAAAA.',
Sa='Sadoh:BAAANQABCgMIAwABNQAECgMIBQABAAAAAA==.Sainttristan:BAAANQABCgEIAQAAAA==.Saluran:BAAANQABCgYIBgAAAA==.Sanitariums:BAAANQADCgQIBAABNQADCgcIGwABAAAAAA==.Sannea:BAAANQADCgUICgABNQAECgkJHgAEAKAWAA==.Sarcastyx:BAABNQAECn8UAAIlAAcKUxC3GQCeAQAlAAcKUxC3GQCeAQAAAA==.Saværo:BAAANQADCgMIBAAAAA==.Saxines:BAAANQAECgMIBQAAAA==.',
Sc='Scaliefox:BAAANQADCgQIBAABNQAECgkJKgAPAM0OAA==.Schwarznacht:BAAANQAECgQIBAAAAA==.',
Se='Seekndestroy:BAABNQAECn8bAAIMAAgKuQbBqABCAQAMAAgKuQbBqABCAQAAAA==.Semperfimack:BAAANQADCgQIBAAAAA==.',
Sh='Shadedlock:BAAANQAECgUIBAAAAA==.Shamwhoa:BAAANQADCgYIBgAAAA==.Shankkerz:BAABNQAECn8UAAMDAAgKeQv4TwCeAQADAAgKeQv4TwCeAQAWAAQKDgaPLgCdAAAAAA==.',
Si='Sicarune:BAAANQADCgYIAgABNQAECgoKNQAKAI8bAA==.Simonx:BAABNQAECn8hAAIFAAkKhA4IcQCtAQAFAAkKhA4IcQCtAQAAAA==.Sindusk:BAAANQAECgYIDAAAAA==.Sitzho:BAAANQADCggIGgAAAA==.',
Sk='Skeleton:BAAANQABCgIIAgAAAA==.Skullblade:BAAANQAECgQIDwAAAA==.Skybringer:BAABNQAECn8rAAIFAAgKZgZlwgARAQAFAAgKZgZlwgARAQAAAA==.Skydras:BAABNQAECn81AAMbAAoKWx/YJQCOAgAbAAkKFB/YJQCOAgAJAAcKPRPAZAB+AQAAAA==.Skyhoof:BAAANQAECgYIBgABNQAECgoKNQAbAFsfAA==.',
Sm='Smolbeans:BAAANQADCgQIBAAAAA==.Smoothscales:BAAANQADCgUIBQAAAA==.Smoothtotem:BAAANQADCggICQAAAA==.',
So='Sonofgrumpy:BAAANQAECgQIBAABNQAECgkJFgAEANsPAA==.Sorphium:BAABNQAECn8aAAIbAAkKkxTrIQC+AQAbAAkKkxTrIQC+AQABNQAFFAUIEAAcAIIKAA==.Soxxy:BAAANQADCgEIAQABNQAECgYICgABAAAAAA==.',
Sp='Sparhawk:BAAANQADCgYIEQAAAA==.',
St='Stham:BAAANQADCgQIBQAAAA==.Stormhartt:BAAANQAECgIIAgAAAA==.Stormyprissi:BAAANQADCgUIDQAAAA==.Strombjorn:BAAANQAECgEIAQAAAA==.',
Ta='Talie:BAABNQAECn8VAAMSAAYKgAdc1ADXAAASAAYKYAdc1ADXAAAGAAIKUQeeNwAyAAABNQAECgcIDgABAAAAAA==.Tasireth:BAAANQADCgMIAwAAAA==.',
Te='Tessi:BAABNQAECn8jAAMGAAcKcQnKHAAIAQAGAAYKWQvKHAAIAQASAAUK1QLOhAG7AAAAAA==.Testamental:BAAANQAECgIJAgAAAA==.Texi:BAAANQAECggICAAAAA==.',
Th='Thaloran:BAAANQADCgcICAAAAA==.Thalrian:BAABNQAECn8cAAIeAAoK5R67CAC1AgAeAAoK5R67CAC1AgABNQAECgoKRAAQACkkAA==.Theberes:BAAANQAECgYIBgAAAA==.Thelance:BAAANQABCggIDQAAAA==.Theylive:BAAANQADCgcIBwAAAA==.Thighs:BAAANQAECgQIBgAAAA==.Thordanil:BAABNQAECn8jAAMFAAkK3Q8migB3AQAFAAgK3Q8migB3AQATAAEKAABCZwBGAAAAAA==.',
Ti='Tiahina:BAAANQADCgUIBQAAAA==.Tioklarus:BAAANQAECgUICAAAAA==.',
To='Tokifuji:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Tourettes:BAAANQADCggJCAAAAA==.Toya:BAABNQAECn9CAAMcAAoKPRlwKgAfAgAcAAoKPRlwKgAfAgAdAAQKZwUhgACzAAAAAA==.',
Tr='Transfurmer:BAAANQADCgMIAwABNQAECgoKOwAaAGAkAA==.Trashdk:BAAANQADCgcIEQAAAA==.Trevain:BAAANQADCgcIHgAAAA==.Trivia:BAAANQAECgIIAgAAAA==.Truthordare:BAABNQAECn8aAAIlAAUKdQNeQwC3AAAlAAUKdQNeQwC3AAAAAA==.',
Tu='Turtei:BAAANQADCggICAABNQAFFAcIGgAZAGAiAA==.Turtl:BAACNQAFFH8aAAIZAAcKYCJ8AQClAgAZAAcKYCJ8AQClAgA1AAQKf0EAAhkACgrwJlIAAJADABkACgrwJlIAAJADAAAA.',
Ty='Tylenolz:BAAANQADCgYIDAAAAA==.',
Ug='Uglypetguy:BAAANQADCgEIAQAAAA==.Uglypriest:BAAANQADCggIDgAAAA==.Uglyrogue:BAAANQAECgIIAgAAAA==.',
Ul='Ulgrym:BAAANQADCgcIGgAAAA==.',
Un='Unbalancéd:BAAANQADCgcIGwAAAA==.',
Va='Vaeadin:BAAANQAECgEIAQAAAA==.Vahra:BAAANQADCgcIGgAAAA==.Valantis:BAAANQAECgQIBAAAAA==.Valgaskav:BAACNQAFFH8JAAIFAAYKxRoNBwA+AQAFAAYKxRoNBwA+AQA1AAQKfyMAAgUACApaJG5SAJ4CAAUACApaJG5SAJ4CAAAA.Valkor:BAAANQADCgMIAgAAAA==.Valric:BAAANQAECggIAgAAAA==.',
Ve='Vegasnight:BAAANQADCggIEwAAAA==.Vella:BAAANQAECgIIAQAAAA==.Venithan:BAAANQAECgYIDwAAAA==.Verdesoul:BAAANQADCgQIBAABNQAECggIGwAFAO0HAA==.',
Vi='Vikkrum:BAAANQADCgYICwABNQADCgcIHgABAAAAAA==.Virani:BAAANQAECgYICQAAAA==.',
Vo='Voladre:BAAANQAECgIIAQAAAA==.Voladro:BAAANQAECggICgAAAA==.Volanie:BAAANQADCgYIBgAAAA==.Volos:BAABNQAECn8iAAIFAAYKIhII1gBvAQAFAAYKIhII1gBvAQAAAA==.Vordaman:BAABNQAECn8tAAMJAAgKMBaTVAC/AQAJAAgKMBaTVAC/AQAaAAEKYAXWtAArAAAAAA==.',
Vy='Vynír:BAACNQAFFH8KAAMlAAYKLg7vDwCUAAAHAAUKrgtwKADEAAAlAAIKBw3vDwCUAAA1AAQKfzcABCYACgpqIoEBAN4CACYACgrnIYEBAN4CAAcACArhINcyAL0CACUABApsHFsoADYBAAAA.',
Wa='Waandur:BAAANQADCgEIAQAAAA==.Waghoba:BAACNQAFFH8IAAIWAAIK1xl0AgCJAAAWAAIK1xl0AgCJAAA1AAQKf40AAhYACgquJkMAAJMDABYACgquJkMAAJMDAAAA.Waito:BAAANQADCggIDQAAAA==.Wandä:BAABNQAECn8wAAMOAAoKmRqKBQAKAgAOAAkKnBmKBQAKAgAZAAgKAxewEwD2AQAAAA==.Warborn:BAAANQADCggIDAAAAA==.Warrionomous:BAACNQAFFH8FAAIQAAMKfAg7JAB5AAAQAAMKfAg7JAB5AAA1AAQKfy4AAhAACgpQGCRUAI4CABAACgpQGCRUAI4CAAAA.Washu:BAABNQAECn9AAAMVAAoKGxpXFABNAgAVAAoKGxpXFABNAgAIAAUKagh/GwCHAAAAAA==.',
We='Wetkittyy:BAAANQABCgUICAAAAA==.',
Wh='Whobetter:BAAANQADCgYICQAAAA==.',
Wi='Winterous:BAAANQAECgQIBgAAAA==.Wisdomheart:BAAANQAECggICQAAAA==.',
Wo='Wonderbread:BAABNQAECn9DAAIFAAoKXxJxXQDgAQAFAAoKXxJxXQDgAQAAAA==.',
['Wá']='Wáshu:BAAANQAECgUIDgAAAA==.',
Xa='Xaani:BAAANQAECgMIAgAAAA==.',
Xe='Xenan:BAABNQAECn8pAAIFAAoKpwr0ggCGAQAFAAoKpwr0ggCGAQAAAA==.',
Xt='Xtrolldinary:BAAANQAECgYIBgAAAA==.',
Ye='Yeastmode:BAABNQAECn8jAAMEAAgK3grdwwB6AQAEAAgK3grdwwB6AQANAAEKogKQnQAhAAAAAA==.',
Yi='Yingsol:BAAANQAECgUIBAABNQAECgYIDwABAAAAAA==.',
Yo='Yonahh:BAAANQAECgcIDQAAAA==.',
Yv='Yvelthilios:BAAANQAECggIDQAAAA==.',
Za='Zangsha:BAAANQADCgcIBwAAAA==.',
Ze='Zeebra:BAABNQAECn8nAAIEAAgKoBKgWwDNAQAEAAgKoBKgWwDNAQAAAA==.Zeg:BAABNQAECn8wAAMKAAoKKiIvCwBPAwAKAAoKKiIvCwBPAwAMAAIK1gsLFAFlAAAAAA==.Zega:BAAANQAECggICAAAAA==.Zegafur:BAAANQAECgIIAgAAAA==.',
Zi='Zillionbucks:BAABNQAECn8UAAIQAAkKJBfOcQA/AgAQAAkKJBfOcQA/AgAAAA==.Zillionbúcks:BAAANQAECgUICQABNQAECgkJFAAQACQXAA==.',
Zo='Zoidworf:BAAANQAECgIIAgAAAA==.',
Zu='Zulg:BAAANQADCgQIBAAAAA==.Zulgore:BAAANQAECgYIBgAAAA==.Zullee:BAAANQADCgIIAgAAAA==.',
['Zê']='Zêddicus:BAABNQAECn89AAMlAAoKzhTWJQBGAQAlAAYK4xbWJQBGAQAHAAcKOBJUewA0AQAAAA==.',
['Áq']='Áquafina:BAABNQAECn8vAAISAAoK7QvDxwD1AQASAAoK7QvDxwD1AQAAAA==.',
['Ðr']='Ðrâgøñ:BAAANQAECgYIBgAAAA==.',
['Ðö']='Ðö:BAABNQAECn8hAAIRAAgKPBbvCwCIAQARAAgKPBbvCwCIAQAAAA==.',
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
