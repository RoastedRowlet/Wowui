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

local lookup = {'Unknown-Unknown','Druid-Guardian','Druid-Balance','Hunter-BeastMastery','Paladin-Retribution','Mage-Frost','Warlock-Demonology','DemonHunter-Vengeance','DeathKnight-Unholy','Priest-Discipline','Shaman-Restoration','Druid-Restoration','Shaman-Elemental','Hunter-Marksmanship','Warrior-Arms','Monk-Brewmaster','Priest-Holy','Warrior-Fury','Mage-Arcane','DemonHunter-Havoc','Paladin-Protection','DemonHunter-Devourer','Druid-Feral','Warrior-Protection','Shaman-Enhancement','Monk-Windwalker','DeathKnight-Frost','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Rogue-Outlaw','Paladin-Holy','Mage-Fire','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Warlock-Destruction','Warlock-Affliction','Monk-Mistweaver',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aaril:BAAANQADCgcIIAAAAQ==.',
Ab='Abnaren:BAAANQAECgQIBAABNQAECgQIBQABAAAAAA==.Abrams:BAABNQAECn8zAAMCAAoKABKeHgCqAQACAAoKABKeHgCqAQADAAgKAgeVWAByAQAAAA==.Absínthè:BAAANQABCgQIBAAAAA==.',
Ag='Agnass:BAAANQADCgcIHwAAAA==.',
Ak='Akali:BAAANQAECgIIAgABNQAECgYICgABAAAAAA==.Akina:BAABNQAECn8eAAIEAAkKoBb1gAALAgAEAAkKoBb1gAALAgAAAA==.',
Al='Alcholic:BAAANQAECggIAwAAAA==.Aldea:BAAANQADCgYIBgAAAA==.Alialista:BAABNQAECn8iAAIEAAgKHhQnlQDeAQAEAAgKHhQnlQDeAQAAAA==.Alirrayia:BAAANQADCgMIAwAAAA==.Alirrayiia:BAACNQAFFH8KAAIFAAMKQgZ5HACzAAAFAAMKQgZ5HACzAAA1AAQKf0IAAgUACgqwFB6HAL4BAAUACgqwFB6HAL4BAAAA.Allmight:BAAANQADCgMIAwAAAA==.Allystar:BAAANQADCgUICgAAAA==.Alvidor:BAABNQAECn83AAIGAAoKjwiKEwBVAQAGAAoKjwiKEwBVAQAAAA==.',
Am='Amachine:BAAANQADCggIDgABNQAFFAgIHAAHAJgdAA==.Amethen:BAAANQAECgQICgAAAA==.Amybabe:BAABNQAECn8UAAIEAAYKnhH2zQBlAQAEAAYKnhH2zQBlAQAAAA==.',
An='Andydufresne:BAAANQAECgcICwABNQAECgoKVAAIACYlAA==.Anestesiax:BAAANQAECgQIBAAAAA==.Anorivia:BAABNQAECn81AAIJAAkKSQn9NABMAQAJAAkKSQn9NABMAQAAAA==.',
Ap='Apolloerosp:BAABNQAECn8dAAIKAAkKsBIcBAARAgAKAAkKsBIcBAARAgABNQAECgoKPQALAM4QAA==.Apollossham:BAABNQAECn89AAILAAoKzhDPUgDIAQALAAoKzhDPUgDIAQAAAA==.',
Ar='Araluen:BAAANQABCgMIAwAAAA==.Arkagob:BAAANQADCgcIBwAAAA==.Arragora:BAAANQAECgQIBQAAAA==.Arrowdynamix:BAABNQAECn8pAAIEAAoKdxgwPABfAgAEAAoKdxgwPABfAgAAAA==.',
As='Ashyani:BAAANQADCgUIBQAAAA==.',
At='Atlan:BAAANQADCgUIBQABNQAECggIMwAMAKAhAA==.',
Au='Aurnhadon:BAAANQABCggIDAAAAA==.Auroradinlee:BAAANQAECgEIAQAAAA==.',
Ba='Babbayagga:BAABNQAECn8rAAINAAoKsRPrUQAxAgANAAoKsRPrUQAxAgAAAA==.Baji:BAABNQAECn9PAAMLAAoKqCBeDABgAwALAAoKqCBeDABgAwANAAkKwxt0HACMAgAAAA==.Barefaall:BAACNQAFFH8OAAMEAAkKown4CwCRAQAEAAUK1wr4CwCRAQAOAAUKvQgeFgDdAAA1AAQKf00AAwQACgozJl8fABoDAAQACQqHJl8fABoDAA4ABwo/HxwZAL8BAAAA.Barefalls:BAABNQAECn8mAAMEAAoKUBe4OgBjAgAEAAoKSRe4OgBjAgAOAAEKOhSuWQBJAAABNQAFFAkJDgAEAKMJAA==.Baénoth:BAAANQAECgMIBAAAAA==.',
Be='Bealzebub:BAAANQAECgYIBAAAAA==.Bellucci:BAAANQADCgcICAABNQAECgkJKwAHACENAA==.Berglock:BAAANQADCgcIBwABNQAECgoKGgAPAIIOAA==.Bergonator:BAABNQAECn8aAAIPAAoKgg5BZgDOAQAPAAoKgg5BZgDOAQAAAA==.Bergue:BAAANQADCgQIBAABNQAECgoKGgAPAIIOAA==.Berrodiah:BAAANQADCgcIDQABNQAECgoKNwAQAI4cAA==.Bestlays:BAAANQAECgQIBQAAAA==.Bettiepage:BAAANQAECgUIBAAAAA==.',
Bh='Bheiroth:BAABNQAECn87AAIRAAoKJSS3DgBmAwARAAoKJSS3DgBmAwAAAA==.',
Bl='Blackchapell:BAAANQABCgYICQAAAA==.Blewmyload:BAAANQAECggIEAAAAA==.Bluett:BAAANQADCgcIHAAAAA==.',
Bo='Bogertus:BAABNQAECn9GAAMPAAoKwSZMAgCDAwAPAAoKwSZMAgCDAwASAAMK/h/YHgDJAAAAAA==.Boomertunes:BAAANQADCgQIBAAAAA==.Boxnasty:BAAANQADCgEIAQAAAA==.',
Br='Brein:BAABNQAECn8yAAIMAAoKSyLNAwDBAwAMAAoKSyLNAwDBAwAAAA==.',
Bu='Bucketeer:BAAANQAECgUICQAAAA==.Burzona:BAAANQABCgMIAwAAAA==.',
Ca='Cameltoetoe:BAAANQAECgEIAgAAAA==.Canaprey:BAABNQAECn8WAAIEAAkK2w/7kwDhAQAEAAkK2w/7kwDhAQAAAA==.Cathogin:BAAANQADCggIDgAAAA==.Catsdruid:BAAANQADCgcIBwAAAA==.Catshunter:BAAANQAECgUICgAAAA==.',
Ce='Celaa:BAAANQADCgQIBAABNQAECgkJHgAEAKAWAA==.Celebrían:BAAANQAECgEIAQAAAA==.Celor:BAAANQABCgQIBgAAAA==.',
Ch='Chanka:BAAANQADCgcIFgAAAA==.Chantillary:BAAANQADCgcIHwAAAA==.Charise:BAAANQAECgUIDAAAAA==.Cheesy:BAAANQADCgYIDAAAAA==.Chopzullee:BAAANQAECgUICgAAAA==.',
Ci='Cinnaz:BAAANQAECgUICwABNQAECgoKNwATADIWAA==.',
Cl='Clortho:BAABNQAECn8XAAIUAAUKdQOpawB3AAAUAAUKdQOpawB3AAAAAA==.Clorthö:BAAANQADCgYIGAAAAA==.',
Co='Colbiw:BAAANQABCgIIAgAAAA==.Colljack:BAACNQAFFH8dAAIVAAgKtx3JAQA7AgAVAAgKtx3JAQA7AgA1AAQKfzQAAhUACgpQJZoEAG0DABUACgpQJZoEAG0DAAAA.Corvath:BAAANQAECgUIEQAAAA==.',
Cr='Crocbait:BAAANQAECgYIBgAAAA==.Cryptoe:BAABNQAECn9QAAITAAoK8R5aQQACAwATAAoK8R5aQQACAwAAAA==.',
Cy='Cyngin:BAAANQAECgQICAAAAA==.',
Da='Daedamus:BAAANQAECgEIAQAAAA==.Daedelus:BAABNQAECn8oAAMWAAoK7xafHADCAQAWAAoK7xafHADCAQAIAAIKew3hKABuAAAAAA==.Daglon:BAABNQAECn8hAAIFAAoKMhf3aQD8AQAFAAoKMhf3aQD8AQAAAA==.Daraedra:BAAANQAECgUICwAAAA==.Dardolur:BAAANQADCgIIAgAAAA==.Darkbane:BAAANQADCggICAAAAA==.Darknìght:BAABNQAECn8oAAIUAAgKNB0kJQDhAQAUAAgKNB0kJQDhAQAAAA==.Darkraider:BAAANQAECgQICAAAAA==.Darkshade:BAAANQAECgEIAQAAAA==.Darkslayer:BAAANQAECgEIAQAAAA==.Darkthyr:BAAANQAECgQIBQAAAA==.',
De='Deeznutticus:BAACNQAFFH8NAAIPAAYKCBP4FQB5AQAPAAYKCBP4FQB5AQA1AAQKf0AAAg8ACgosIJ0eAD0DAA8ACgosIJ0eAD0DAAAA.Demonspud:BAABNQAECn8XAAIWAAcKLg5wNgCQAQAWAAcKLg5wNgCQAQAAAA==.Dersan:BAAANQADCgIIAgAAAA==.Destriant:BAABNQAECn9KAAMVAAoKFyLhBgDlAgAVAAoKFyLhBgDlAgAFAAEKHxZYhAFCAAAAAA==.Devourer:BAAANQABCgMIAwAAAA==.Dewburt:BAAANQAECgcIBwAAAA==.Deylia:BAAANQAECgYICgABNQAFFAUIIAARACMQAA==.',
Dh='Dhori:BAAANQADCgcIHwAAAA==.',
Di='Dillion:BAAANQAECgEIAQABNQAECgkJKwAHACENAA==.Dionin:BAAANQADCgUICgAAAA==.Dirky:BAABNQAECn8cAAIXAAoKBA+4EwCQAQAXAAoKBA+4EwCQAQAAAA==.Dirtychai:BAABNQAECn8aAAIFAAkKRgtHmQCaAQAFAAkKRgtHmQCaAQAAAA==.Disappear:BAAANQADCgYICgABNQAECgoKNwATADIWAA==.Dizzyhealz:BAAANQAECgEIAQAAAA==.Dizzyhuntres:BAAANQADCgYIBwAAAA==.',
Do='Dooberrt:BAAANQAECgUIBQAAAA==.Dooberto:BAABNQAECn8sAAMYAAoK1xXrEACoAQAYAAoK1xXrEACoAQAPAAMKywReMgFwAAAAAA==.Dooburt:BAABNQAECn8dAAMFAAkKNAgn8gA4AQAFAAgKyAgn8gA4AQAVAAcK3QT4SwC6AAAAAA==.',
Dr='Dracaric:BAAANQADCgYIBgAAAA==.Draeca:BAAANQADCgcIHAAAAA==.Dragondznut:BAAANQADCggIDwAAAA==.Drfrostie:BAAANQAECgYIBgAAAA==.Driatin:BAAANQAECgEIAQAAAA==.',
Du='Durø:BAABNQAECn9UAAIWAAoKUCTKBAAYAwAWAAoKUCTKBAAYAwAAAA==.',
['Dè']='Dègenerate:BAABNQAECn9fAAIYAAoK8SOtAgAkAwAYAAoK8SOtAgAkAwAAAA==.',
Ed='Eddy:BAABNQAECn84AAIZAAoK6w9oFQC+AQAZAAoK6w9oFQC+AQAAAA==.',
Ei='Eilae:BAAANQADCgcIDQAAAA==.Einherjarr:BAAANQADCgYICgAAAA==.',
El='Eldumpling:BAABNQAECn8fAAIaAAkKcBeXFQATAgAaAAkKcBeXFQATAgAAAA==.Elefante:BAAANQADCgYIDAAAAA==.',
En='Engineers:BAAANQAECgQIBAAAAA==.',
Ep='Epicnym:BAABNQAECn8zAAMNAAkKgBf4fACtAQANAAcKJRn4fACtAQAZAAgK0RJCFwCgAQAAAA==.',
Es='Esdeath:BAABNQAECn8tAAQJAAkKRA0gKwCNAQAJAAkKRAwgKwCNAQAbAAYKowwbXAA4AQAcAAMK4gHauQBUAAAAAA==.',
Ev='Evoberg:BAAANQABCgYIBgABNQAECgoKGgAPAIIOAA==.',
Ex='Extenze:BAABNQAECn8pAAIWAAkKARewGgDXAQAWAAkKARewGgDXAQAAAA==.',
Fa='Faegrin:BAAANQAECgQIBAAAAA==.',
Fe='Feda:BAAANQADCgQIBAAAAA==.Felyna:BAAANQAECggIDwAAAA==.Ferryman:BAABNQAECn8nAAIEAAgK/xFglwCGAQAEAAgK/xFglwCGAQAAAA==.',
Fi='Findria:BAAANQADCgYIBgABNQAFFAUIBwAEABUZAA==.',
Fo='Forphium:BAACNQAFFH8QAAMdAAUKggoTCQBcAQAdAAUKwgcTCQBcAQAeAAEKTQtyIABHAAA1AAQKfy0AAx0ACgqOHxcPAIkCAB0ACQrvIBcPAIkCAB4AAQrnFXGcAEQAAAAA.',
Fr='Fredolf:BAAANQADCgQIBAAAAA==.Freespirit:BAABNQAECn8dAAMOAAoKVh8WHwBXAgAOAAkKXSMWHwBXAgAEAAEKIwNOWQEjAAABNQAFFAgIIQAfAFYiAA==.Friarkuck:BAAANQADCgEIAQAAAA==.Frierenn:BAAANQADCgYIBgAAAA==.Frosteddonut:BAAANQAECgcIDwABNQAECgoKRgAMAB0lAA==.Frostieheals:BAAANQAECgQIAwAAAA==.',
Ft='Fthrhealgood:BAAANQAECggIDwAAAA==.',
Ga='Gahlina:BAAANQAECgEIAQAAAA==.Gambaaddict:BAABNQAECn8bAAIgAAgKoBIdCgDdAQAgAAgKoBIdCgDdAQAAAA==.Ganhammer:BAAANQADCgIIAgAAAA==.Garshan:BAAANQAECgMIAwAAAA==.',
Ge='Genestarwind:BAAANQAECgQIDAAAAA==.',
Gh='Ghexn:BAAANQADCgIIAgAAAA==.',
Gi='Gilleyy:BAAANQAECgQICQAAAA==.Gird:BAABNQAECn8yAAIhAAkKexY7OAA6AgAhAAkKexY7OAA6AgAAAA==.Girdlock:BAAANQAECgIIAgAAAA==.',
Gl='Glyph:BAAANQAECgYICwABNQAECgoKPwALAN8bAA==.',
Gn='Gnymesis:BAAANQADCgYICwAAAA==.',
Go='Goatmonger:BAAANQAECggICgAAAA==.Goinpostal:BAAANQADCgYICwAAAA==.Goldblade:BAABNQAECn8ZAAIPAAkKGANe7ACaAAAPAAkKGANe7ACaAAAAAA==.Gordek:BAABNQAECn8YAAIFAAoKLRXsngDkAQAFAAoKLRXsngDkAQAAAA==.',
Gr='Graceteena:BAAANQAECgcIBwAAAA==.Grahra:BAAANQABCgIIBAAAAA==.Grantaron:BAABNQAECn9BAAMFAAoK7BxuSgBLAgAFAAoK7BxuSgBLAgAhAAIKPwvl1wBmAAAAAA==.Grimskul:BAABNQAECn9DAAIJAAoKZhcBMQBqAgAJAAoKZhcBMQBqAgAAAA==.Grntitan:BAAANQADCgcIHQAAAA==.Gruid:BAAANQAECgMIAwAAAA==.',
Gw='Gwoohoori:BAABNQAECn8yAAIFAAoK7xgtTQBDAgAFAAoK7xgtTQBDAgAAAA==.',
Ha='Halukari:BAAANQADCggIDAABNQAFFAUIIAARACMQAA==.Haléon:BAABNQAECn8XAAITAAgKGAZq5gDhAAATAAgKGAZq5gDhAAAAAA==.Hans:BAAANQAECgUICAAAAA==.Harfnan:BAAANQADCgYICQAAAA==.Harperlee:BAAANQAECggICQAAAA==.Harrin:BAAANQADCggIEQAAAA==.',
He='Headshotty:BAAANQAECgUICAAAAA==.Hellfire:BAAANQADCgYIBgAAAA==.Hezrel:BAAANQAECgYICQAAAA==.',
Hi='Hinal:BAABNQAECn8dAAMFAAcKyhSXsAC+AQAFAAcKyhSXsAC+AQAVAAYKDA0HQwCcAAAAAA==.',
Ho='Holyenabler:BAAANQAECgYIEAAAAA==.Honzo:BAABNQAECn8hAAMcAAkKJwlXbgA8AQAcAAkK1whXbgA8AQAbAAMKJAnMnABjAAAAAA==.',
Hu='Hungor:BAAANQABCgQIBAAAAA==.',
['Hè']='Hèalz:BAAANQAECgYIBwABNQAECgoKIwASAOkWAA==.',
Ic='Iceberg:BAAANQADCgEIAQABNQAECgoKGgAPAIIOAA==.Icecrystal:BAAANQABCgIIAgAAAA==.',
Ih='Iheartbailey:BAAANQADCgQIBAAAAA==.',
Im='Imcruel:BAACNQAFFH8bAAITAAgKghgEDgAHAgATAAgKghgEDgAHAgA1AAQKf1sABBMACgqsJX8IAEEDABMACgqLJX8IAEEDACIAAwoBIgEFAB0BAAYAAgqNFx8pAJoAAAAA.Iminyë:BAAANQAECgYICQAAAA==.',
Io='Iorese:BAAANQADCggIDwAAAA==.',
Ir='Iriana:BAEANQADCgYIMQABNQAECgMIBgABAAAAAA==.',
Ja='Jabes:BAAANQAECgUIBQAAAA==.Jackiegan:BAAANQADCgEIAQAAAA==.Jagershamer:BAAANQAECgcIBwABNQAECggIBwABAAAAAA==.Jasperine:BAAANQAECggIEQABNQAFFAgIIQAfAFYiAA==.',
Je='Jenneldots:BAAANQAECgUIEgABNQAECgYICgABAAAAAA==.Jerce:BAAANQADCgUICQAAAA==.',
Jo='Johnnyhuntz:BAAANQADCgYICAAAAA==.Joregis:BAABNQAECn8aAAIbAAoKVQWaVQA/AQAbAAoKVQWaVQA/AQAAAA==.',
Ju='Juacqer:BAAANQADCgcIGgAAAA==.Junamara:BAAANQAECgQICQAAAA==.',
Ka='Kaant:BAABNQAECn88AAMNAAoKAxv4JABVAgANAAoKAxv4JABVAgALAAcKRBgmVQC+AQAAAA==.Kaetiegh:BAAANQADCgUIDwAAAA==.Kaidevyn:BAABNQAECn8sAAIbAAoK3RB7OAC+AQAbAAoK3RB7OAC+AQAAAA==.Kardead:BAAANQAECgMIBAAAAA==.Kardren:BAAANQAECgIIAgAAAA==.Kat:BAAANQADCgQICAAAAA==.',
Kb='Kbang:BAAANQAECgIIAgAAAA==.',
Ke='Keiran:BAABNQAECn9LAAIEAAoKwSKiEgADAwAEAAoKwSKiEgADAwAAAA==.Kenix:BAAANQADCgUIDQABNQADCgYICgABAAAAAA==.',
Kh='Khalnerys:BAABNQAECn8rAAQjAAcKdAbjFgDJAAAjAAcKaAbjFgDJAAAkAAUKVgLQQwCFAAAlAAMKTQWSHgBsAAAAAA==.Khaotick:BAEBNQAECn8rAAQHAAoKJRlsVQBWAgAHAAkKcxhsVQBWAgAmAAQK5A4VPQDNAAAnAAEKAABJMwAtAAABNQAECgkJJgAHALcTAA==.Khoulock:BAABNQAECn8hAAQHAAkK6B8HLgDOAgAHAAkKfR8HLgDOAgAmAAYK4B/1FwCtAQAnAAEKAABlLAA+AAAAAA==.',
Ki='Kimmi:BAAANQAECgQIBQAAAA==.Kimmispally:BAAANQADCggICAAAAA==.Kiro:BAAANQADCgYIDAAAAA==.',
Ko='Kotawar:BAAANQAECgMIAwAAAA==.Kozana:BAAANQADCgIIAgAAAA==.',
Kt='Kthxbye:BAAANQAECggIBwAAAA==.',
Ku='Kuraishin:BAABNQAECn8/AAMXAAoKqiTZAQBLAwAXAAoKqiTZAQBLAwACAAIK7R4kQgC2AAAAAA==.Kuterr:BAAANQADCgUIBQAAAA==.',
Ky='Kyrae:BAAANQADCgYIEAABNQAECgYIDwABAAAAAA==.Kyrub:BAAANQABCggICAAAAA==.',
La='Latheal:BAAANQADCgcIFAAAAA==.Latto:BAABNQAECn8UAAMcAAUKNBM6fAAIAQAcAAUKNBM6fAAIAQAbAAEKAABhqwA3AAABNQAECgYICgABAAAAAA==.',
Le='Lengex:BAAANQAECgcIDAAAAA==.Lero:BAAANQAECgIIAgAAAA==.Levatan:BAAANQAECgEIAQAAAA==.Lexoh:BAAANQAECgQIAgAAAA==.',
Li='Lilieth:BAAANQADCgcIGgAAAA==.Liltankarmor:BAAANQAECgYICgAAAA==.Lindir:BAACNQAFFH8HAAIEAAUKFRkFFADtAAAEAAUKFRkFFADtAAA1AAQKfzkAAgQACgo/Ja0MAHkDAAQACgo/Ja0MAHkDAAAA.Liquid:BAACNQAFFH8JAAIfAAYKCAwxCAASAQAfAAYKCAwxCAASAQA1AAQKfzYAAx8ACgpjHD8NAIYCAB8ACgpjHD8NAIYCAAoAAQq0A2cuACgAAAAA.Liuni:BAABNQAECn86AAIQAAoKVhZ4BwDzAQAQAAoKVhZ4BwDzAQAAAA==.',
Lo='Lobopeste:BAABNQAECn86AAIcAAoKxgyCOABhAQAcAAoKxgyCOABhAQAAAA==.Loborocco:BAAANQADCgIIAgAAAA==.Lobotomi:BAAANQADCgYIDgAAAA==.Lorantell:BAAANQADCgYIBgAAAA==.Lorelynn:BAABNQAECn8uAAImAAoKShjACgBLAgAmAAoKShjACgBLAgAAAA==.Loðbrók:BAAANQAECgYICwAAAA==.',
Lu='Luci:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.Luckycritz:BAAANQAECgIIAQABNQAECgcIDgABAAAAAA==.Lucìan:BAABNQAECn8zAAIMAAcKoCFRHgAOAgAMAAcKoCFRHgAOAgAAAA==.Luna:BAAANQAECgQIBAABNQAECgkJGwARAPYbAA==.Lunaclair:BAABNQAECn8zAAMJAAoKkBdQGgAUAgAJAAoKkBdQGgAUAgAcAAMK8wlMtABgAAABNQAECgoKPwAXAKokAA==.Lunarielle:BAAANQAECgQIBgAAAA==.',
Ma='Mabrito:BAAANQAECgcIDgABNQAFFAcIGAADAIUVAA==.Macfly:BAABNQAECn9IAAIEAAoKahvRRABJAgAEAAoKahvRRABJAgAAAA==.Macneel:BAAANQADCgEIAQABNQADCgcIHgABAAAAAA==.Magicmissile:BAAANQADCgQIBAABNQAFFAMIBQAPAHwIAA==.Malevalous:BAAANQAECgIIAgABNQAECgoKQgAJAIQaAA==.Mancath:BAABNQAECn8yAAIFAAoKBho/YwBxAgAFAAoKBho/YwBxAgAAAA==.Maplè:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Marlei:BAAANQAECgUICwABNQAECgkJHgAEAKAWAA==.Maru:BAAANQADCgcIBwABNQAECgoKTwALAKggAA==.Marylayetta:BAAANQADCgYIBgAAAA==.Maxzang:BAAANQABCggIEAAAAA==.',
Me='Medenà:BAAANQADCgUICAAAAA==.Meeko:BAACNQAFFH8HAAIkAAMKOxv9DwD3AAAkAAMKOxv9DwD3AAA1AAQKfyEAAiQACQqhHMoOALwCACQACQqhHMoOALwCAAE1AAUUCQkWACQA+BUA.Melfie:BAAANQAECgEIAQAAAA==.',
Mi='Midoriya:BAABNQAECn8rAAIaAAoKLhdMFAAjAgAaAAoKLhdMFAAjAgAAAA==.Mihoshi:BAAANQAECgUIDwAAAA==.Mistjack:BAAANQADCggICAAAAA==.',
Mo='Morphium:BAAANQAECgYIBgABNQAFFAUIEAAdAIIKAA==.Mortiis:BAAANQADCgMIAwAAAA==.Moxi:BAAANQADCgUIBQAAAA==.',
Mu='Murderbot:BAAANQAECggIAgAAAA==.',
My='Myzyry:BAACNQAFFH8HAAIPAAQKaAkGIAC+AAAPAAQKaAkGIAC+AAA1AAQKfzUAAg8ACgqoGkEtAIoCAA8ACgqoGkEtAIoCAAAA.',
['Mä']='Märtyr:BAAANQAECgUIBQAAAA==.',
['Må']='Måze:BAAANQAECgQIBAAAAA==.',
['Më']='Mërlïn:BAAANQADCgYIBgAAAA==.',
Na='Nards:BAAANQAECggICgAAAA==.Nazdormu:BAAANQAECgcIEAAAAA==.',
Ne='Nebulous:BAAANQAECgMIAwAAAA==.Neisen:BAAANQAECggIEwAAAA==.Neptune:BAAANQAECgUIBQAAAA==.Nevare:BAAANQAECgcIEAAAAA==.',
Ni='Nite:BAABNQAECn83AAITAAoKMhZLlwBSAgATAAoKMhZLlwBSAgAAAA==.',
No='Nou:BAEANQAFFAIIAgABNQAECgkJJgAHALcTAA==.',
Nu='Nubi:BAAANQADCgIIAgAAAA==.Nugent:BAABNQAECn8jAAIEAAoK8BoSOgC8AgAEAAoK8BoSOgC8AgAAAA==.',
Ny='Nymmie:BAAANQAECgQIBQAAAA==.Nymofthedead:BAAANQADCgcIBwAAAA==.',
Oa='Oakgrove:BAAANQADCgIIAgAAAA==.',
Ok='Okarun:BAAANQADCgEIAQAAAA==.Okiro:BAAANQADCgQIBAAAAA==.',
On='Oneforall:BAACNQAFFH8JAAIhAAQKDg8fEwARAQAhAAQKDg8fEwARAQA1AAQKf0sAAyEACgo4HLccANQCACEACgo4HLccANQCAAUAAQoAAOnOAQAAAAAA.',
Or='Orphen:BAAANQAECgcIDAAAAA==.',
Pa='Pailly:BAAANQABCgQIBAAAAA==.Papalion:BAABNQAECn8gAAIEAAoKKAl0rACsAQAEAAoKKAl0rACsAQAAAA==.Paryl:BAABNQAECn8rAAIHAAkKIQ3VdwB1AQAHAAkKIQ3VdwB1AQAAAA==.Pawbs:BAAANQADCgYIBgAAAA==.',
Pe='Peanuts:BAAANQAECggICAAAAA==.',
Pi='Pikake:BAAANQADCgUICQAAAA==.Pinklilydrd:BAAANQADCgcIGQAAAA==.',
Pl='Plaindonut:BAABNQAECn9GAAMMAAoKHSXVAQAGBAAMAAoKHSXVAQAGBAADAAUK1BjDTwDgAAAAAA==.Pluffeh:BAAANQADCgYICgABNQAECgMIBQABAAAAAA==.',
Pm='Pmoney:BAAANQAECgcIDgAAAA==.',
Pr='Prissidebow:BAAANQADCgcIEQAAAA==.Prissygalore:BAAANQADCgEIAQAAAA==.',
Pu='Puddinpie:BAAANQADCgEIAQAAAA==.Punkhazard:BAAANQAECgUIBQAAAA==.Putras:BAAANQABCgIIAgAAAA==.',
Qu='Quartz:BAAANQAECgYICgABNQAECgoKRgAPAMEmAA==.Quinraidar:BAAANQAECggICQABNQAECgoKTwALAKggAA==.',
Ra='Ranor:BAAANQAECgIIAgABNQAECgoKOgAQAFYWAA==.Ravenbrook:BAACNQAFFH8GAAISAAUK4SSZAQDOAAASAAUK4SSZAQDOAAA1AAQKf0YAAhIACgrDJi8AAPgDABIACgrDJi8AAPgDAAAA.Ravus:BAAANQADCgIIAgAAAA==.Rawrr:BAABNQAECn8YAAIUAAcKvgaUUwDUAAAUAAcKvgaUUwDUAAAAAA==.Raxie:BAACNQAFFH8gAAQRAAUKIxBIFgBSAQARAAUKIxBIFgBSAQAfAAQKZgu9DADMAAAKAAEKSQFiBQAxAAA1AAQKfzkABB8ACgq1GNgdAFECAB8ACQraF9gdAFECAAoABwo6EZULAIYBABEABAqWF+qzAMoAAAAA.',
Re='Reddfoxx:BAABNQAECn8YAAMeAAoKKwyVRQCwAQAeAAkKtQuVRQCwAQAdAAUK/woKmwDUAAAAAA==.Resepuff:BAAANQADCggIEAAAAA==.',
Rh='Rhymunky:BAAANQADCgMIAwAAAA==.',
Ri='Rifthor:BAAANQADCgYIBgAAAA==.Ripmxi:BAAANQAECgYIEgAAAA==.',
Ro='Roknarogue:BAAANQAECgEIAgAAAA==.',
Ru='Runelight:BAAANQADCgUICAABNQAECgoKPwALAN8bAA==.Runeshock:BAABNQAECn8/AAMLAAoK3xuVLAByAgALAAoK3xuVLAByAgANAAQKwgpnugCVAAAAAA==.Runestick:BAAANQADCgUIBQABNQAECgoKPwALAN8bAA==.Runesummon:BAAANQADCggIDAAAAA==.Rupertgiless:BAACNQAFFH8XAAIHAAgKchA4CgDGAQAHAAgKchA4CgDGAQA1AAQKf0IAAgcACgpQH0ASAOACAAcACgpQH0ASAOACAAAA.',
Sa='Sadoh:BAAANQABCgMIAwABNQAECgMIBQABAAAAAA==.Sainttristan:BAAANQABCgEIAQAAAA==.Saluran:BAAANQABCgYIBgAAAA==.Sanitariums:BAAANQADCgQIBAABNQADCgcIGwABAAAAAA==.Sannea:BAAANQADCgUICgABNQAECgkJHgAEAKAWAA==.Sarcastyx:BAABNQAECn8UAAImAAcKUxC3GQCeAQAmAAcKUxC3GQCeAQAAAA==.Saværo:BAAANQADCgMIBAAAAA==.Saxines:BAAANQAECgQICQAAAA==.',
Sc='Scaliefox:BAAANQADCgQIBAABNQAECgoKMQARAPwRAA==.Schwarznacht:BAAANQAECgQIBAAAAA==.',
Se='Seekndestroy:BAABNQAECn8cAAINAAkKwgbBqABCAQANAAkKwgbBqABCAQAAAA==.Semperfimack:BAAANQADCgQIBAAAAA==.',
Sh='Shadedlock:BAAANQAECgQICQAAAA==.Shamwhoa:BAAANQADCgYIBgAAAA==.Shankkerz:BAABNQAECn8UAAMDAAgKeQv4TwCeAQADAAgKeQv4TwCeAQAXAAQKDgaPLgCdAAAAAA==.',
Si='Sicarune:BAAANQADCgYIAgABNQAECgoKPwALAN8bAA==.Simonx:BAABNQAECn8kAAIFAAkKVA8ghgDAAQAFAAkKVA8ghgDAAQAAAA==.Sindusk:BAAANQAECgYIDAAAAA==.Sitzho:BAAANQADCggIGgAAAA==.',
Sk='Skeleton:BAAANQABCgIIAgAAAA==.Skullblade:BAAANQAECgQIDwAAAA==.Skybringer:BAABNQAECn8/AAIFAAkKPAewtABnAQAFAAkKPAewtABnAQAAAA==.Skydras:BAABNQAECn81AAMcAAoKWx/YJQCOAgAcAAkKFB/YJQCOAgAJAAcKPRPAZAB+AQAAAA==.Skyhoof:BAAANQAECgYIBgABNQAECgoKNQAcAFsfAA==.',
Sm='Smolbeans:BAAANQADCgQIBAAAAA==.Smoothtotem:BAAANQAECgYIBgAAAA==.',
So='Sonofgrumpy:BAAANQAECgQIBAABNQAECgkJFgAEANsPAA==.Sorphium:BAABNQAECn8jAAIcAAoK1Bc3GABEAgAcAAoK1Bc3GABEAgABNQAFFAUIEAAdAIIKAA==.Soxxy:BAAANQADCgEIAQABNQAECgYICgABAAAAAA==.',
Sp='Sparhawk:BAAANQADCgYIEQAAAA==.',
St='Stham:BAAANQADCgQIBQAAAA==.Stormhartt:BAAANQAECgIIAgAAAA==.Stormyprissi:BAAANQADCgUIDQAAAA==.Strombjorn:BAAANQAECgEIAQAAAA==.',
Su='Sujing:BAAANQAECgMIAwAAAA==.',
Ta='Talie:BAABNQAECn8VAAMTAAYKgAeb8QDMAAATAAYKYAeb8QDMAAAGAAIKUQc+QQAyAAABNQAECgcIEwABAAAAAA==.Tasireth:BAAANQADCgMIAwAAAA==.',
Te='Tessi:BAABNQAECn8jAAMGAAcKcQnKHAAIAQAGAAYKWQvKHAAIAQATAAUK1QLOhAG7AAAAAA==.Testamental:BAAANQAECgIJAgAAAA==.Texi:BAAANQAECggICAAAAA==.',
Th='Thaloran:BAAANQADCgcICAAAAA==.Thalrian:BAABNQAECn8xAAIfAAoKxCEMBQAnAwAfAAoKxCEMBQAnAwABNQAFFAUICQAPAJUfAA==.Theberes:BAAANQAECgYIBgAAAA==.Thelance:BAAANQABCggIDQAAAA==.Theylive:BAAANQADCgcIBwAAAA==.Thighs:BAAANQAECgQIBgAAAA==.Thordanil:BAABNQAECn8uAAMFAAoK1hI9ZwACAgAFAAkK1hI9ZwACAgAVAAEKAABCZwBGAAAAAA==.',
Ti='Tiahina:BAAANQADCgUIBQAAAA==.Tioklarus:BAAANQAECgUICAAAAA==.',
To='Tokifuji:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Tourettes:BAAANQADCggJCAAAAA==.Toya:BAABNQAECn9KAAMdAAoKJBpLEgBeAgAdAAoKJBpLEgBeAgAeAAQKZwUhgACzAAAAAA==.',
Tr='Transfurmer:BAAANQADCgMIAwABNQAECgoKPQAbAKMkAA==.Trashdk:BAAANQADCgcIGAAAAA==.Trevain:BAAANQADCgcIHgAAAA==.Trivia:BAAANQAECgUICwAAAA==.Truthordare:BAABNQAECn8gAAImAAUKdQNeQwC3AAAmAAUKdQNeQwC3AAAAAA==.',
Tu='Turtei:BAAANQADCggICAABNQAFFAgIHAAaAFUhAA==.Turtl:BAACNQAFFH8cAAIaAAgKVSF8AQClAgAaAAgKVSF8AQClAgA1AAQKf0IAAhoACgrwJowAAIwDABoACgrwJowAAIwDAAAA.',
Ty='Tylenolz:BAAANQADCgYIDAAAAA==.',
Ug='Uglypetguy:BAAANQADCgEIAQAAAA==.Uglypriest:BAAANQADCggIDgAAAA==.Uglyrogue:BAAANQAECgIIAgAAAA==.',
Ul='Ulgrym:BAAANQADCgcIGgAAAA==.',
Un='Unbalancéd:BAAANQADCgcIGwAAAA==.Unbroken:BAAANQABCgcIBgAAAA==.',
Va='Vaeadin:BAAANQAECgEIAQAAAA==.Vahra:BAAANQADCgcIGgAAAA==.Valantis:BAAANQAECgQIBAAAAA==.Valgaskav:BAACNQAFFH8JAAIFAAYKxRpYCwA1AQAFAAYKxRpYCwA1AQA1AAQKfygAAgUACApaJG5SAJ4CAAUACApaJG5SAJ4CAAAA.Valkor:BAAANQADCgIIAgAAAA==.Valric:BAAANQAECggIBgAAAA==.',
Ve='Vegasnight:BAAANQADCggIEwAAAA==.Vella:BAAANQAECgQIBQAAAA==.Venithan:BAAANQAECgYIDwAAAA==.Verdesoul:BAAANQADCgQIBAABNQAECggIIgAFANUGAA==.',
Vi='Vikkrum:BAAANQADCgYICwABNQADCgcIHgABAAAAAA==.Virani:BAAANQAECgYICQAAAA==.',
Vo='Voladre:BAAANQAECgEIAQAAAA==.Voladro:BAAANQAECggICgAAAA==.Volanie:BAAANQADCgYIBgAAAA==.Volos:BAABNQAECn8sAAIFAAcKJhEI1gBvAQAFAAcKJhEI1gBvAQAAAA==.Vordaman:BAABNQAECn82AAMJAAkKtxZfHwDmAQAJAAkKtxZfHwDmAQAbAAEKYAXWtAArAAAAAA==.',
Vy='Vynír:BAACNQAFFH8KAAMmAAYKLg7vDwCUAAAHAAUKrgtwKADEAAAmAAIKBw3vDwCUAAA1AAQKfzcABCcACgpqIl4CAMACACcACgrnIV4CAMACAAcACArhINcyAL0CACYABApsHFsoADYBAAAA.',
Wa='Waandur:BAAANQADCgEIAQAAAA==.Waghoba:BAACNQAFFH8IAAIXAAIK1xk1AwCEAAAXAAIK1xk1AwCEAAA1AAQKf7IAAhcACgrLJhwAAKMDABcACgrLJhwAAKMDAAAA.Waito:BAAANQADCggIDQAAAA==.Wandä:BAABNQAECn83AAQQAAoKjhyfBABvAgAQAAoKEBufBABvAgAaAAgKAxeYGADuAQAoAAMKOBR2KgCxAAAAAA==.Warborn:BAAANQADCggIDAAAAA==.Warrionomous:BAACNQAFFH8FAAIPAAMKfAghLQB3AAAPAAMKfAghLQB3AAA1AAQKfy4AAg8ACgpQGCRUAI4CAA8ACgpQGCRUAI4CAAAA.Washu:BAABNQAECn9EAAMUAAoKUhobGQBMAgAUAAoKUhobGQBMAgAIAAUKagjCIACEAAAAAA==.',
We='Wetkittyy:BAAANQABCgUICAAAAA==.',
Wh='Whobetter:BAAANQADCgYICQAAAA==.',
Wi='Winterous:BAAANQAECgQIBgAAAA==.Wisdomheart:BAAANQAECggIDQAAAA==.',
Wo='Wonderbread:BAABNQAECn9PAAIFAAoKBxUtWgAhAgAFAAoKBxUtWgAhAgAAAA==.',
['Wá']='Wáshu:BAAANQAECgUIDgAAAA==.',
Xa='Xaani:BAAANQAECgMIAgAAAA==.',
Xe='Xenan:BAABNQAECn8wAAIFAAoKtgrqnACTAQAFAAoKtgrqnACTAQAAAA==.',
Xt='Xtrolldinary:BAAANQAECgYIBgAAAA==.',
Ye='Yeastmode:BAABNQAECn8pAAMEAAkK4g0dlwCGAQAEAAkK4g0dlwCGAQAOAAEKogKQnQAhAAAAAA==.',
Yi='Yingsol:BAAANQAECgUIBAABNQAECgYIDwABAAAAAA==.',
Yo='Yonahh:BAAANQAECgcIDQAAAA==.',
Yv='Yvelthilios:BAABNQAECn8VAAITAAkKBAdTowBdAQATAAkKBAdTowBdAQAAAA==.',
Za='Zangsha:BAAANQADCgcIBwAAAA==.',
Ze='Zeebra:BAABNQAECn8rAAIEAAkKbhNzVwAcAgAEAAkKbhNzVwAcAgAAAA==.Zeg:BAABNQAECn8wAAMLAAoKKiLxDwA9AwALAAoKKiLxDwA9AwANAAIK1gsLFAFlAAAAAA==.Zega:BAAANQAECggICAAAAA==.Zegafur:BAAANQAECgIIAgAAAA==.',
Zi='Zillionbucks:BAABNQAECn8UAAIPAAkKJBfOcQA/AgAPAAkKJBfOcQA/AgAAAA==.Zillionbúcks:BAAANQAECgUICQABNQAECgkJFAAPACQXAA==.',
Zo='Zoidworf:BAAANQAECgMIBQAAAA==.',
Zu='Zulg:BAAANQADCgQIBAAAAA==.Zulgore:BAAANQAECgYIBgAAAA==.Zullee:BAAANQADCgIIAgAAAA==.',
['Zê']='Zêddicus:BAABNQAECn9CAAMmAAoK0BTWJQBGAQAHAAgKvRL4cgCCAQAmAAYK4xbWJQBGAQAAAA==.',
['Áq']='Áquafina:BAABNQAECn8vAAITAAoK7QvDxwD1AQATAAoK7QvDxwD1AQAAAA==.',
['Ðr']='Ðrâgøñ:BAAANQAECggICAAAAA==.',
['Ðö']='Ðö:BAABNQAECn8jAAISAAoK6RboCAAWAgASAAoK6RboCAAWAgAAAA==.',
['ßr']='ßruenor:BAAANQAECgUIBQAAAA==.',
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
