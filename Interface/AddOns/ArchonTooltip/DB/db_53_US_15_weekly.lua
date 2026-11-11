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

local lookup = {'Unknown-Unknown','Druid-Guardian','Druid-Balance','Hunter-BeastMastery','Paladin-Retribution','Mage-Frost','Warlock-Demonology','DemonHunter-Vengeance','DeathKnight-Unholy','Shaman-Restoration','Druid-Restoration','Shaman-Elemental','Hunter-Marksmanship','Warrior-Arms','Monk-Brewmaster','Priest-Holy','Warrior-Fury','Mage-Arcane','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Feral','Warrior-Protection','Shaman-Enhancement','Monk-Windwalker','DeathKnight-Frost','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Rogue-Outlaw','Paladin-Holy','Mage-Fire','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Warlock-Destruction','Warlock-Affliction','Priest-Discipline','Monk-Mistweaver',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aaril:BAAANQADCgcIIAAAAQ==.',
Ab='Abnaren:BAAANQAECgQIBAABNQAECgQIBQABAAAAAA==.Abrams:BAABNQAECn8zAAMCAAoKABKeHgCqAQACAAoKABKeHgCqAQADAAgKAgeVWAByAQAAAA==.Absínthè:BAAANQABCgQIBAAAAA==.',
Ag='Agnass:BAAANQADCgcIHwAAAA==.',
Ak='Akali:BAAANQAECgIIAgABNQAECgYICgABAAAAAA==.Akina:BAABNQAECn8eAAIEAAkKoBb1gAALAgAEAAkKoBb1gAALAgAAAA==.',
Al='Alcholic:BAAANQAECggIAwAAAA==.Aldea:BAAANQADCgYIBgAAAA==.Alialista:BAABNQAECn8iAAIEAAgKHhQnlQDeAQAEAAgKHhQnlQDeAQAAAA==.Alirrayia:BAAANQADCgMIAwAAAA==.Alirrayiia:BAACNQAFFH8JAAIFAAMKQgZRGQC2AAAFAAMKQgZRGQC2AAA1AAQKf0IAAgUACgqwFK56AMQBAAUACgqwFK56AMQBAAAA.Allmight:BAAANQADCgMIAwAAAA==.Allystar:BAAANQADCgUICgAAAA==.Alvidor:BAABNQAECn82AAIGAAkKugiNFAAxAQAGAAkKugiNFAAxAQAAAA==.',
Am='Amachine:BAAANQADCggIDgABNQAFFAgIHAAHAJgdAA==.Amethen:BAAANQAECgQICgAAAA==.Amybabe:BAABNQAECn8UAAIEAAYKnhH2zQBlAQAEAAYKnhH2zQBlAQAAAA==.',
An='Andydufresne:BAAANQAECgcICwABNQAECgoKTwAIACYlAA==.Anestesiax:BAAANQAECgQIBAAAAA==.Anorivia:BAABNQAECn81AAIJAAkKSQnVMQBMAQAJAAkKSQnVMQBMAQAAAA==.',
Ap='Apolloerosp:BAAANQAECgUIEQABNQAECgoKNQAKAM4QAA==.Apollossham:BAABNQAECn81AAIKAAoKzhCHWQCYAQAKAAoKzhCHWQCYAQAAAA==.',
Ar='Araluen:BAAANQABCgMIAwAAAA==.Arkagob:BAAANQADCgcIBwAAAA==.Arragora:BAAANQAECgQIBQAAAA==.Arrowdynamix:BAABNQAECn8pAAIEAAoKdxjKNABkAgAEAAoKdxjKNABkAgAAAA==.',
As='Ashyani:BAAANQADCgUIBQAAAA==.',
At='Atlan:BAAANQADCgUIBQABNQAECgcILQALAJUiAA==.',
Au='Aurnhadon:BAAANQABCggIDAAAAA==.',
Ba='Babbayagga:BAABNQAECn8rAAIMAAoKsRPrUQAxAgAMAAoKsRPrUQAxAgAAAA==.Baji:BAABNQAECn9GAAMKAAoKqCCQCgBmAwAKAAoKqCCQCgBmAwAMAAgK0xYtXQAKAgAAAA==.Barefaall:BAACNQAFFH8MAAMEAAgK9gr4CwCRAQAEAAUK1wr4CwCRAQANAAQKFQseFgDdAAA1AAQKf0wAAwQACgozJl8fABoDAAQACQqHJl8fABoDAA0ABwo/H6kYALEBAAAA.Barefalls:BAABNQAECn8jAAMEAAoKJRZ0QQA/AgAEAAoKHhZ0QQA/AgANAAEKOhRxVQBKAAABNQAFFAgIDAAEAPYKAA==.Baénoth:BAAANQAECgMIBAAAAA==.',
Be='Bealzebub:BAAANQAECgYIBAAAAA==.Bellucci:BAAANQADCgcICAABNQAECgkJKwAHACENAA==.Berglock:BAAANQADCgcIBwABNQAECgoKFgAOAG4MAA==.Bergonator:BAABNQAECn8WAAIOAAoKbgwTZQC7AQAOAAoKbgwTZQC7AQAAAA==.Bergue:BAAANQADCgQIBAABNQAECgoKFgAOAG4MAA==.Berrodiah:BAAANQADCgcIDQABNQAECgoKNgAPAJkaAA==.Bestlays:BAAANQAECgIIAQAAAA==.Bettiepage:BAAANQAECgUIBAAAAA==.',
Bh='Bheiroth:BAABNQAECn87AAIQAAoKJSRNDABwAwAQAAoKJSRNDABwAwAAAA==.',
Bl='Blackchapell:BAAANQABCgYICQAAAA==.Blewmyload:BAAANQAECggIDgAAAA==.Bluett:BAAANQADCgcIHAAAAA==.',
Bo='Bogertus:BAABNQAECn9BAAMOAAoKvyZnAgCAAwAOAAoKvyZnAgCAAwARAAMK/h/YHgDJAAAAAA==.Boomertunes:BAAANQADCgQIBAAAAA==.Boxnasty:BAAANQADCgEIAQAAAA==.',
Br='Brein:BAABNQAECn8xAAILAAoKCyKBAwC8AwALAAoKCyKBAwC8AwAAAA==.',
Bu='Bucketeer:BAAANQAECgUICQAAAA==.Burzona:BAAANQABCgMIAwAAAA==.',
Ca='Cameltoetoe:BAAANQAECgEIAgAAAA==.Canaprey:BAABNQAECn8WAAIEAAkK2w/7kwDhAQAEAAkK2w/7kwDhAQAAAA==.Cathogin:BAAANQADCggIDgAAAA==.Catsdruid:BAAANQADCgcIBwAAAA==.Catshunter:BAAANQAECgUICgAAAA==.',
Ce='Celaa:BAAANQADCgQIBAABNQAECgkJHgAEAKAWAA==.Celebrían:BAAANQAECgEIAQAAAA==.Celor:BAAANQABCgQIBgAAAA==.',
Ch='Chanka:BAAANQADCgcIFgAAAA==.Chantillary:BAAANQADCgcIHwAAAA==.Charise:BAAANQAECgUIDAAAAA==.Cheesy:BAAANQADCgYIDAAAAA==.Chopzullee:BAAANQAECgUICgAAAA==.',
Ci='Cinnaz:BAAANQAECgUICwABNQAECgoKNwASADIWAA==.',
Cl='Clortho:BAAANQAECgUIEgAAAA==.Clorthö:BAAANQADCgYIFAAAAA==.',
Co='Colbiw:BAAANQABCgIIAgAAAA==.Colljack:BAACNQAFFH8dAAITAAgKtx3JAQA7AgATAAgKtx3JAQA7AgA1AAQKfzQAAhMACgpQJfcDACQDABMACgpQJfcDACQDAAAA.Corvath:BAAANQAECgUIEQAAAA==.',
Cr='Cryptoe:BAABNQAECn9QAAISAAoK8R5aQQACAwASAAoK8R5aQQACAwAAAA==.',
Cy='Cyngin:BAAANQAECgQICAAAAA==.',
Da='Daedamus:BAAANQAECgEIAQAAAA==.Daedelus:BAABNQAECn8oAAMUAAoK7xZXGgDHAQAUAAoK7xZXGgDHAQAIAAIKew3hKABuAAAAAA==.Daglon:BAABNQAECn8hAAIFAAoKMhdzXwADAgAFAAoKMhdzXwADAgAAAA==.Daraedra:BAAANQAECgYIBwAAAA==.Dardolur:BAAANQADCgIIAgAAAA==.Darknìght:BAABNQAECn8iAAIVAAcK8x3/MAAgAgAVAAcK8x3/MAAgAgAAAA==.Darkraider:BAAANQAECgQICAAAAA==.Darkshade:BAAANQADCgMIAwAAAA==.Darkslayer:BAAANQADCgMIBQAAAA==.Darkthyr:BAAANQAECgQIBQAAAA==.',
De='Deeznutticus:BAACNQAFFH8NAAIOAAYKCBP4FQB5AQAOAAYKCBP4FQB5AQA1AAQKfz8AAg4ACgomIJ0eAD0DAA4ACgomIJ0eAD0DAAAA.Demonspud:BAABNQAECn8XAAIUAAcKLg5wNgCQAQAUAAcKLg5wNgCQAQAAAA==.Dersan:BAAANQADCgIIAgAAAA==.Destriant:BAABNQAECn9HAAMTAAoK9yAwBwDNAgATAAoK9yAwBwDNAgAFAAEKHxYccwFDAAAAAA==.Devourer:BAAANQABCgMIAwAAAA==.Dewburt:BAAANQAECgcIBwAAAA==.Deylia:BAAANQAECgYICgABNQAFFAUIHAAQANkMAA==.',
Dh='Dhori:BAAANQADCgcIHwAAAA==.',
Di='Dillion:BAAANQAECgEIAQABNQAECgkJKwAHACENAA==.Dionin:BAAANQADCgUICgAAAA==.Dirky:BAABNQAECn8cAAIWAAoKBA87EQCTAQAWAAoKBA87EQCTAQAAAA==.Dirtychai:BAABNQAECn8aAAIFAAkKRgsmjACfAQAFAAkKRgsmjACfAQAAAA==.Disappear:BAAANQADCgYICgABNQAECgoKNwASADIWAA==.Dizzyhealz:BAAANQAECgEIAQAAAA==.Dizzyhuntres:BAAANQADCgYIBwAAAA==.',
Do='Dooberrt:BAAANQAECgUIBQAAAA==.Dooberto:BAABNQAECn8sAAMXAAoK1xUeDwCsAQAXAAoK1xUeDwCsAQAOAAMKywReMgFwAAAAAA==.Dooburt:BAABNQAECn8dAAMFAAkKNAgn8gA4AQAFAAgKyAgn8gA4AQATAAcK3QT4SwC6AAAAAA==.',
Dr='Dracaric:BAAANQADCgYIBgAAAA==.Draeca:BAAANQADCgcIHAAAAA==.Dragondznut:BAAANQADCggIDwAAAA==.Drfrostie:BAAANQAECgYIBgAAAA==.Driatin:BAAANQAECgEIAQAAAA==.',
Du='Durø:BAABNQAECn9LAAIUAAoKQyTIBQD8AgAUAAoKQyTIBQD8AgAAAA==.',
['Dè']='Dègenerate:BAABNQAECn9WAAIXAAoK8SOFAgAfAwAXAAoK8SOFAgAfAwAAAA==.',
Ed='Eddy:BAABNQAECn84AAIYAAoK6w+7EwDAAQAYAAoK6w+7EwDAAQAAAA==.',
Ei='Eilae:BAAANQADCgcIDQAAAA==.Einherjarr:BAAANQADCgYICgAAAA==.',
El='Eldumpling:BAABNQAECn8eAAIZAAkKUxcFFAASAgAZAAkKUxcFFAASAgAAAA==.Elefante:BAAANQADCgYIDAAAAA==.',
Ep='Epicnym:BAABNQAECn8sAAMMAAgKeBjbYABMAQAMAAcKJRnbYABMAQAYAAcK/hFGGwBJAQAAAA==.',
Es='Esdeath:BAABNQAECn8tAAQJAAkKRA0RKACOAQAJAAkKRAwRKACOAQAaAAYKowwbXAA4AQAbAAMK4gHauQBUAAAAAA==.',
Ev='Evoberg:BAAANQABCgYIBgABNQAECgoKFgAOAG4MAA==.',
Ex='Extenze:BAABNQAECn8pAAIUAAkKARebGADbAQAUAAkKARebGADbAQAAAA==.',
Fa='Faegrin:BAAANQAECgQIBAAAAA==.',
Fe='Feda:BAAANQADCgQIBAAAAA==.Felyna:BAAANQAECggIDgAAAA==.Ferryman:BAABNQAECn8iAAIEAAgKbRE/kAB5AQAEAAgKbRE/kAB5AQAAAA==.',
Fi='Findria:BAAANQADCgYIBgABNQAFFAUIBwAEABUZAA==.',
Fo='Forphium:BAACNQAFFH8QAAMcAAUKggoTCQBcAQAcAAUKwgcTCQBcAQAdAAEKTQtyIABHAAA1AAQKfy0AAxwACgqOHxcPAIkCABwACQrvIBcPAIkCAB0AAQrnFXGcAEQAAAAA.',
Fr='Fredolf:BAAANQADCgQIBAAAAA==.Freespirit:BAABNQAECn8dAAMNAAoKVh/LFgDKAQANAAkKXSPLFgDKAQAEAAEKIwMrTAEjAAABNQAFFAgIHgAeAA8fAA==.Friarkuck:BAAANQADCgEIAQAAAA==.Frierenn:BAAANQADCgYIBgAAAA==.Frosteddonut:BAAANQAECgcIDQABNQAECgoKQgALAB0lAA==.Frostieheals:BAAANQAECgQIAwAAAA==.',
Ft='Fthrhealgood:BAAANQAECggICAAAAA==.',
Ga='Gahlina:BAAANQAECgEIAQAAAA==.Gambaaddict:BAABNQAECn8bAAIfAAgKoBIdCgDdAQAfAAgKoBIdCgDdAQAAAA==.Ganhammer:BAAANQADCgIIAgAAAA==.Garshan:BAAANQAECgMIAwAAAA==.',
Ge='Genestarwind:BAAANQAECgQIDAAAAA==.',
Gh='Ghexn:BAAANQADCgIIAgAAAA==.',
Gi='Gilleyy:BAAANQAECgQICQAAAA==.Gird:BAABNQAECn8yAAIgAAkKexZpMgBEAgAgAAkKexZpMgBEAgAAAA==.Girdlock:BAAANQAECgIIAgAAAA==.',
Gl='Glyph:BAAANQAECgYICwABNQAECgoKPgAKAN8bAA==.',
Gn='Gnymesis:BAAANQADCgYICwAAAA==.',
Go='Goatmonger:BAAANQAECggICgAAAA==.Goinpostal:BAAANQADCgYICwAAAA==.Goldblade:BAABNQAECn8ZAAIOAAkKFwMJ4gCbAAAOAAkKFwMJ4gCbAAAAAA==.Gordek:BAABNQAECn8YAAIFAAoKLRXsngDkAQAFAAoKLRXsngDkAQAAAA==.',
Gr='Graceteena:BAAANQADCgUICQAAAA==.Grahra:BAAANQABCgIIBAAAAA==.Grantaron:BAABNQAECn8+AAMFAAoK7BxERgBIAgAFAAoK7BxERgBIAgAgAAIKPwujzQBpAAAAAA==.Grimskul:BAABNQAECn86AAIJAAkKLxkBMQBqAgAJAAkKLxkBMQBqAgAAAA==.Grntitan:BAAANQADCgcIHQAAAA==.Gruid:BAAANQAECgMIAwAAAA==.',
Gw='Gwoohoori:BAABNQAECn8pAAIFAAoKCxj+TgAuAgAFAAoKCxj+TgAuAgAAAA==.',
Ha='Halukari:BAAANQADCggIDAABNQAFFAUIHAAQANkMAA==.Haléon:BAABNQAECn8XAAISAAgKGAYw3ADhAAASAAgKGAYw3ADhAAAAAA==.Hans:BAAANQAECgUICAAAAA==.Harfnan:BAAANQADCgYICQAAAA==.Harperlee:BAAANQAECggICQAAAA==.Harrin:BAAANQADCggIEQAAAA==.',
He='Headshotty:BAAANQAECgUICAAAAA==.Hellfire:BAAANQADCgYIBgAAAA==.Hezrel:BAAANQAECgYICQAAAA==.',
Hi='Hinal:BAABNQAECn8dAAMFAAcKyhSXsAC+AQAFAAcKyhSXsAC+AQATAAYKDA3jPgCcAAAAAA==.',
Ho='Holyenabler:BAAANQAECgYIEAAAAA==.Honzo:BAABNQAECn8hAAMbAAkKJwlXbgA8AQAbAAkK1whXbgA8AQAaAAMKJAlhkwBmAAAAAA==.',
Hu='Hungor:BAAANQABCgQIBAAAAA==.',
['Hè']='Hèalz:BAAANQAECgEIAQABNQAECgoKIwARAOkWAA==.',
Ic='Iceberg:BAAANQADCgEIAQABNQAECgoKFgAOAG4MAA==.Icecrystal:BAAANQABCgIIAgAAAA==.',
Ih='Iheartbailey:BAAANQADCgQIBAAAAA==.',
Im='Imcruel:BAACNQAFFH8aAAISAAcKjhsEDgAHAgASAAcKjhsEDgAHAgA1AAQKf1MABBIACgpIJaEJADMDABIACgooJaEJADMDACEAAwoBIm4EAB4BAAYAAgqNFxkmAJoAAAAA.Iminyë:BAAANQAECgYICQAAAA==.',
Io='Iorese:BAAANQADCggIDwAAAA==.',
Ir='Iriana:BAEANQADCgYIMQABNQAECgMIBgABAAAAAA==.',
Ja='Jabes:BAAANQAECgUIBQAAAA==.Jackiegan:BAAANQADCgEIAQAAAA==.Jagershamer:BAAANQAECgcIBwABNQAECggIBwABAAAAAA==.Jasperine:BAAANQAECggIEQABNQAFFAgIHgAeAA8fAA==.',
Je='Jenneldots:BAAANQAECgUIEgABNQAECgYICgABAAAAAA==.Jerce:BAAANQADCgUICQAAAA==.',
Jo='Johnnyhuntz:BAAANQADCgYICAAAAA==.Joregis:BAAANQAECggIDgAAAA==.',
Ju='Juacqer:BAAANQADCgcIGgAAAA==.Junamara:BAAANQAECgQICQAAAA==.',
Ka='Kaant:BAABNQAECn87AAMMAAoKvhqpIwBKAgAMAAoKvhqpIwBKAgAKAAcKRBigTQDEAQAAAA==.Kaetiegh:BAAANQADCgUIDwAAAA==.Kaidevyn:BAABNQAECn8mAAIaAAkKAxGbPgDRAQAaAAkKAxGbPgDRAQAAAA==.Kardead:BAAANQAECgMIBAAAAA==.Kardren:BAAANQADCgEIAQAAAA==.Kat:BAAANQADCgQICAAAAA==.',
Kb='Kbang:BAAANQAECgIIAgAAAA==.',
Ke='Keiran:BAABNQAECn9EAAIEAAoKwSLNEQD+AgAEAAoKwSLNEQD+AgAAAA==.Kenix:BAAANQADCgUIDQABNQADCgYICgABAAAAAA==.',
Kh='Khalnerys:BAABNQAECn8lAAQiAAYKzQbTGACgAAAiAAYKvgbTGACgAAAjAAQKUALQQwCFAAAkAAMKTQWSHgBsAAAAAA==.Khaotick:BAEBNQAECn8rAAQHAAoKJRlsVQBWAgAHAAkKcxhsVQBWAgAlAAQK5A4VPQDNAAAmAAEKAABJMwAtAAABNQAECgkJIAAHAJ8QAA==.Khoulock:BAABNQAECn8hAAQHAAkK6B8HLgDOAgAHAAkKfR8HLgDOAgAlAAYK4B/1FwCtAQAmAAEKAABlLAA+AAAAAA==.',
Ki='Kimmi:BAAANQAECgQIBQAAAA==.Kimmispally:BAAANQADCggICAAAAA==.Kiro:BAAANQADCgYIDAAAAA==.',
Ko='Kotawar:BAAANQAECgMIAwAAAA==.Kozana:BAAANQADCgIIAgAAAA==.',
Kt='Kthxbye:BAAANQAECggIBwAAAA==.',
Ku='Kuraishin:BAABNQAECn84AAMWAAoKqiSrAQBLAwAWAAoKqiSrAQBLAwACAAIK7R6GPQC2AAAAAA==.Kuterr:BAAANQADCgUIBQAAAA==.',
Ky='Kyrae:BAAANQADCgYIEAABNQAECgYIDwABAAAAAA==.Kyrub:BAAANQABCggICAAAAA==.',
La='Latheal:BAAANQADCgcIFAAAAA==.Latto:BAABNQAECn8UAAMbAAUKNBM6fAAIAQAbAAUKNBM6fAAIAQAaAAEKAABhqwA3AAABNQAECgYICgABAAAAAA==.',
Le='Lengex:BAAANQAECgcIBgAAAA==.Lero:BAAANQAECgIIAgAAAA==.Levatan:BAAANQAECgEIAQAAAA==.Lexoh:BAAANQAECgQIAgAAAA==.',
Li='Lilieth:BAAANQADCgcIGgAAAA==.Liltankarmor:BAAANQAECgYICgAAAA==.Lindir:BAACNQAFFH8HAAIEAAUKFRmmEQDwAAAEAAUKFRmmEQDwAAA1AAQKfzgAAgQACgo/Ja0MAHkDAAQACgo/Ja0MAHkDAAAA.Liquid:BAACNQAFFH8JAAIeAAYKCAwKBwATAQAeAAYKCAwKBwATAQA1AAQKfzMAAx4ACgpjHJcNAG8CAB4ACgpjHJcNAG8CACcAAQq0A2cuACgAAAAA.Liuni:BAABNQAECn86AAIPAAoKVhbjBgDzAQAPAAoKVhbjBgDzAQAAAA==.',
Lo='Lobopeste:BAABNQAECn85AAIbAAkKhA1QOgBKAQAbAAkKhA1QOgBKAQAAAA==.Loborocco:BAAANQADCgIIAgAAAA==.Lobotomi:BAAANQADCgYIDgAAAA==.Lorantell:BAAANQADCgYIBgAAAA==.Lorelynn:BAABNQAECn8uAAIlAAoKShjACgBLAgAlAAoKShjACgBLAgAAAA==.Loðbrók:BAAANQAECgUIBwAAAA==.',
Lu='Luci:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.Luckycritz:BAAANQAECgIIAQABNQAECgcIDgABAAAAAA==.Lucìan:BAABNQAECn8tAAILAAYKlSIYHgA/AgALAAYKlSIYHgA/AgAAAA==.Luna:BAAANQAECgQIBAABNQAECgkJGwAQAPYbAA==.Lunaclair:BAABNQAECn8zAAMJAAoKkBcgGAAXAgAJAAoKkBcgGAAXAgAbAAMK8wlMtABgAAABNQAECgoKOAAWAKokAA==.Lunarielle:BAAANQAECgQIBgAAAA==.',
Ma='Mabrito:BAAANQAECgcIDgABNQAFFAcIGAADAIUVAA==.Macfly:BAABNQAECn9IAAIEAAoKahvCPABNAgAEAAoKahvCPABNAgAAAA==.Macneel:BAAANQADCgEIAQABNQADCgcIHgABAAAAAA==.Magicmissile:BAAANQADCgQIBAABNQAFFAMIBQAOAHwIAA==.Malevalous:BAAANQAECgIIAgABNQAECgoKPAAJAHwaAA==.Mancath:BAABNQAECn8yAAIFAAoKBho/YwBxAgAFAAoKBho/YwBxAgAAAA==.Maplè:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Marlei:BAAANQAECgUICwABNQAECgkJHgAEAKAWAA==.Maru:BAAANQADCgcIBwABNQAECgoKRgAKAKggAA==.Marylayetta:BAAANQADCgYIBgAAAA==.Maxzang:BAAANQABCggIEAAAAA==.',
Me='Medenà:BAAANQADCgUICAAAAA==.Meeko:BAACNQAFFH8HAAIjAAMKOxv9DwD3AAAjAAMKOxv9DwD3AAA1AAQKfyEAAiMACQqhHMoOALwCACMACQqhHMoOALwCAAE1AAUUCAgUACMApRQA.Melfie:BAAANQAECgEIAQAAAA==.',
Mi='Midoriya:BAABNQAECn8iAAIZAAoKShaHFAALAgAZAAoKShaHFAALAgAAAA==.Mihoshi:BAAANQAECgUIDwAAAA==.Mistjack:BAAANQADCggICAAAAA==.',
Mo='Moldyjack:BAAANQAFFAEIAQAAAA==.Morphium:BAAANQAECgYIBgABNQAFFAUIEAAcAIIKAA==.Mortiis:BAAANQADCgMIAwAAAA==.Moxi:BAAANQADCgUIBQAAAA==.',
Mu='Murderbot:BAAANQAECggIAgAAAA==.',
My='Myzyry:BAACNQAFFH8GAAIOAAMKaAkEHQC+AAAOAAMKaAkEHQC+AAA1AAQKfy4AAg4ACgqxGdAxAGoCAA4ACgqxGdAxAGoCAAAA.',
['Mä']='Märtyr:BAAANQAECgUIBQAAAA==.',
['Må']='Måze:BAAANQAECgUIBAAAAA==.',
['Më']='Mërlïn:BAAANQADCgYIBgAAAA==.',
Na='Nards:BAAANQAECggICgAAAA==.Nazdormu:BAAANQAECgcIEAAAAA==.',
Ne='Nebulous:BAAANQAECgMIAwAAAA==.Neisen:BAAANQAECggIEwAAAA==.Neptune:BAAANQAECgUIBQAAAA==.Nevare:BAAANQAECgcIEAAAAA==.',
Ni='Nite:BAABNQAECn83AAISAAoKMhZLlwBSAgASAAoKMhZLlwBSAgAAAA==.',
No='Nou:BAEANQAFFAIIAgABNQAECgkJIAAHAJ8QAA==.',
Nu='Nubi:BAAANQADCgIIAgAAAA==.Nugent:BAABNQAECn8jAAIEAAoK8BoSOgC8AgAEAAoK8BoSOgC8AgAAAA==.',
Ny='Nymmie:BAAANQAECgQIBQAAAA==.Nymofthedead:BAAANQADCgcIBwAAAA==.',
Oa='Oakgrove:BAAANQADCgIIAgAAAA==.',
Ok='Okarun:BAAANQADCgEIAQAAAA==.Okiro:BAAANQADCgQIBAAAAA==.',
On='Oneforall:BAACNQAFFH8JAAIgAAQKDg8iEQAXAQAgAAQKDg8iEQAXAQA1AAQKf0oAAyAACgoXHHIaANUCACAACgoXHHIaANUCAAUAAQoAADW8AQAAAAAA.',
Or='Orphen:BAAANQAECgcIDAAAAA==.',
Pa='Pailly:BAAANQABCgQIBAAAAA==.Papalion:BAABNQAECn8gAAIEAAoKKAl0rACsAQAEAAoKKAl0rACsAQAAAA==.Paryl:BAABNQAECn8rAAIHAAkKIQ2hbgB4AQAHAAkKIQ2hbgB4AQAAAA==.Pawbs:BAAANQADCgYIBgAAAA==.',
Pe='Peanuts:BAAANQAECggICAAAAA==.',
Pi='Pikake:BAAANQADCgUICQAAAA==.Pinklilydrd:BAAANQADCgcIGQAAAA==.',
Pl='Plaindonut:BAABNQAECn9CAAMLAAoKHSWGAQAJBAALAAoKHSWGAQAJBAADAAEKAAAYpQBPAAAAAA==.Pluffeh:BAAANQADCgYICgABNQAECgMIBQABAAAAAA==.',
Pm='Pmoney:BAAANQAECgcIDgAAAA==.',
Pr='Prissidebow:BAAANQADCgcIEQAAAA==.Prissygalore:BAAANQADCgEIAQAAAA==.',
Pu='Puddinpie:BAAANQADCgEIAQAAAA==.Punkhazard:BAAANQAECgUIBQAAAA==.Putras:BAAANQABCgIIAgAAAA==.',
Qu='Quartz:BAAANQAECgYICgABNQAECgoKQQAOAL8mAA==.Quinraidar:BAAANQAECggICQABNQAECgoKRgAKAKggAA==.',
Ra='Ranor:BAAANQAECgIIAgABNQAECgoKOgAPAFYWAA==.Ravenbrook:BAACNQAFFH8GAAIRAAUK4SReAQDQAAARAAUK4SReAQDQAAA1AAQKf0YAAhEACgrDJi8AAPgDABEACgrDJi8AAPgDAAAA.Ravus:BAAANQADCgIIAgAAAA==.Rawrr:BAABNQAECn8YAAIVAAcKvgYsTgDXAAAVAAcKvgYsTgDXAAAAAA==.Raxie:BAACNQAFFH8cAAQQAAUK2QycFABLAQAQAAUK2QycFABLAQAeAAQKZgtiCwDMAAAnAAEKSQFiBQAxAAA1AAQKfzgABB4ACgq1GNgdAFECAB4ACQraF9gdAFECACcABwo6EZULAIYBABAABAqWF9ipAM4AAAAA.',
Re='Reddfoxx:BAABNQAECn8YAAMdAAoKKwyVRQCwAQAdAAkKtQuVRQCwAQAcAAUK/wqLjwDUAAAAAA==.Resepuff:BAAANQADCggIEAAAAA==.',
Rh='Rhymunky:BAAANQADCgMIAwAAAA==.',
Ri='Rifthor:BAAANQADCgYIBgAAAA==.Ripmxi:BAAANQAECgYIEgAAAA==.',
Ro='Roknarogue:BAAANQAECgEIAgAAAA==.',
Ru='Runelight:BAAANQADCgUICAABNQAECgoKPgAKAN8bAA==.Runeshock:BAABNQAECn8+AAMKAAoK3xvSJwB4AgAKAAoK3xvSJwB4AgAMAAQKwgofsACVAAAAAA==.Runestick:BAAANQADCgUIBQABNQAECgoKPgAKAN8bAA==.Runesummon:BAAANQADCggIDAAAAA==.Rupertgiless:BAACNQAFFH8XAAIHAAgKchA4CgDGAQAHAAgKchA4CgDGAQA1AAQKf0IAAgcACgpQH54PAOgCAAcACgpQH54PAOgCAAAA.',
Sa='Sadoh:BAAANQABCgMIAwABNQAECgMIBQABAAAAAA==.Sainttristan:BAAANQABCgEIAQAAAA==.Saluran:BAAANQABCgYIBgAAAA==.Sanitariums:BAAANQADCgQIBAABNQADCgcIGwABAAAAAA==.Sannea:BAAANQADCgUICgABNQAECgkJHgAEAKAWAA==.Sarcastyx:BAABNQAECn8UAAIlAAcKUxC3GQCeAQAlAAcKUxC3GQCeAQAAAA==.Saværo:BAAANQADCgMIBAAAAA==.Saxines:BAAANQAECgMIBQAAAA==.',
Sc='Scaliefox:BAAANQADCgQIBAABNQAECgkJMAAQAKURAA==.Schwarznacht:BAAANQAECgQIBAAAAA==.',
Se='Seekndestroy:BAABNQAECn8cAAIMAAkKwgbBqABCAQAMAAkKwgbBqABCAQAAAA==.Semperfimack:BAAANQADCgQIBAAAAA==.',
Sh='Shadedlock:BAAANQAECgQICQAAAA==.Shamwhoa:BAAANQADCgYIBgAAAA==.Shankkerz:BAABNQAECn8UAAMDAAgKeQv4TwCeAQADAAgKeQv4TwCeAQAWAAQKDgaPLgCdAAAAAA==.',
Si='Sicarune:BAAANQADCgYIAgABNQAECgoKPgAKAN8bAA==.Simonx:BAABNQAECn8kAAIFAAkKVA8pegDFAQAFAAkKVA8pegDFAQAAAA==.Sindusk:BAAANQAECgYIDAAAAA==.Sitzho:BAAANQADCggIGgAAAA==.',
Sk='Skeleton:BAAANQABCgIIAgAAAA==.Skullblade:BAAANQAECgQIDwAAAA==.Skybringer:BAABNQAECn80AAIFAAkKDwekqwBhAQAFAAkKDwekqwBhAQAAAA==.Skydras:BAABNQAECn81AAMbAAoKWx/YJQCOAgAbAAkKFB/YJQCOAgAJAAcKPRPAZAB+AQAAAA==.Skyhoof:BAAANQAECgYIBgABNQAECgoKNQAbAFsfAA==.',
Sm='Smolbeans:BAAANQADCgQIBAAAAA==.Smoothtotem:BAAANQADCggICQAAAA==.',
So='Sonofgrumpy:BAAANQAECgQIBAABNQAECgkJFgAEANsPAA==.Sorphium:BAABNQAECn8eAAIbAAkK+halJgC5AQAbAAkK+halJgC5AQABNQAFFAUIEAAcAIIKAA==.Soxxy:BAAANQADCgEIAQABNQAECgYICgABAAAAAA==.',
Sp='Sparhawk:BAAANQADCgYIEQAAAA==.',
St='Stham:BAAANQADCgQIBQAAAA==.Stormhartt:BAAANQAECgIIAgAAAA==.Stormyprissi:BAAANQADCgUIDQAAAA==.Strombjorn:BAAANQAECgEIAQAAAA==.',
Su='Sujing:BAAANQAECgMIAwAAAA==.',
Ta='Talie:BAABNQAECn8VAAMSAAYKgAc55wDNAAASAAYKYAc55wDNAAAGAAIKUQcfPQAyAAABNQAECgcIEwABAAAAAA==.Tasireth:BAAANQADCgMIAwAAAA==.',
Te='Tessi:BAABNQAECn8jAAMGAAcKcQnKHAAIAQAGAAYKWQvKHAAIAQASAAUK1QLOhAG7AAAAAA==.Testamental:BAAANQAECgIJAgAAAA==.Texi:BAAANQAECggICAAAAA==.',
Th='Thaloran:BAAANQADCgcICAAAAA==.Thalrian:BAABNQAECn8oAAIeAAoKch9OBwDqAgAeAAoKch9OBwDqAgABNQAFFAQIBQAOAPsZAA==.Theberes:BAAANQAECgYIBgAAAA==.Thelance:BAAANQABCggIDQAAAA==.Theylive:BAAANQADCgcIBwAAAA==.Thighs:BAAANQAECgQIBgAAAA==.Thordanil:BAABNQAECn8nAAMFAAkKyxL1fQC8AQAFAAgKyxL1fQC8AQATAAEKAABCZwBGAAAAAA==.',
Ti='Tiahina:BAAANQADCgUIBQAAAA==.Tioklarus:BAAANQAECgUICAAAAA==.',
To='Tokifuji:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Tourettes:BAAANQADCggJCAAAAA==.Toya:BAABNQAECn9JAAMcAAoKJBoMLwAtAgAcAAoKJBoMLwAtAgAdAAQKZwUhgACzAAAAAA==.',
Tr='Transfurmer:BAAANQADCgMIAwABNQAECgoKPQAaAKMkAA==.Trashdk:BAAANQADCgcIGAAAAA==.Trevain:BAAANQADCgcIHgAAAA==.Trivia:BAAANQAECgYIBwAAAA==.Truthordare:BAABNQAECn8dAAIlAAUKdQNeQwC3AAAlAAUKdQNeQwC3AAAAAA==.',
Tu='Turtei:BAAANQADCggICAABNQAFFAgIHAAZAGIhAA==.Turtl:BAACNQAFFH8cAAIZAAgKYiF8AQClAgAZAAgKYiF8AQClAgA1AAQKf0IAAhkACgrwJnUAAI0DABkACgrwJnUAAI0DAAAA.',
Ty='Tylenolz:BAAANQADCgYIDAAAAA==.',
Ug='Uglypetguy:BAAANQADCgEIAQAAAA==.Uglypriest:BAAANQADCggIDgAAAA==.Uglyrogue:BAAANQAECgIIAgAAAA==.',
Ul='Ulgrym:BAAANQADCgcIGgAAAA==.',
Un='Unbalancéd:BAAANQADCgcIGwAAAA==.Unbroken:BAAANQABCgcIBgAAAA==.',
Va='Vaeadin:BAAANQAECgEIAQAAAA==.Vahra:BAAANQADCgcIGgAAAA==.Valantis:BAAANQAECgQIBAAAAA==.Valgaskav:BAACNQAFFH8JAAIFAAYKxRo+CQA6AQAFAAYKxRo+CQA6AQA1AAQKfyQAAgUACApaJG5SAJ4CAAUACApaJG5SAJ4CAAAA.Valkor:BAAANQADCgIIAgAAAA==.Valric:BAAANQAECggIAgAAAA==.',
Ve='Vegasnight:BAAANQADCggIEwAAAA==.Vella:BAAANQAECgIIAQAAAA==.Venithan:BAAANQAECgYIDwAAAA==.Verdesoul:BAAANQADCgQIBAABNQAECggIGwAFAO8FAA==.',
Vi='Vikkrum:BAAANQADCgYICwABNQADCgcIHgABAAAAAA==.Virani:BAAANQAECgYICQAAAA==.',
Vo='Voladre:BAAANQAECgEIAQAAAA==.Voladro:BAAANQAECggICgAAAA==.Volanie:BAAANQADCgYIBgAAAA==.Volos:BAABNQAECn8mAAIFAAYKIhII1gBvAQAFAAYKIhII1gBvAQAAAA==.Vordaman:BAABNQAECn82AAMJAAkKtxYZHQDnAQAJAAkKtxYZHQDnAQAaAAEKYAXWtAArAAAAAA==.',
Vy='Vynír:BAACNQAFFH8KAAMlAAYKLg7vDwCUAAAHAAUKrgtwKADEAAAlAAIKBw3vDwCUAAA1AAQKfzcABCYACgpqIhACAMkCACYACgrnIRACAMkCAAcACArhINcyAL0CACUABApsHFsoADYBAAAA.',
Wa='Waandur:BAAANQADCgEIAQAAAA==.Waghoba:BAACNQAFFH8IAAIWAAIK1xnXAgCHAAAWAAIK1xnXAgCHAAA1AAQKf6AAAhYACgrCJi8AAJsDABYACgrCJi8AAJsDAAAA.Waito:BAAANQADCggIDQAAAA==.Wandä:BAABNQAECn82AAQPAAoKmRrVBQAiAgAPAAkKMBvVBQAiAgAZAAgKAxeKFgDxAQAoAAMKOBQnKACxAAAAAA==.Warborn:BAAANQADCggIDAAAAA==.Warrionomous:BAACNQAFFH8FAAIOAAMKfAgIKQB3AAAOAAMKfAgIKQB3AAA1AAQKfy4AAg4ACgpQGCRUAI4CAA4ACgpQGCRUAI4CAAAA.Washu:BAABNQAECn9EAAMVAAoKUhr0FgBPAgAVAAoKUhr0FgBPAgAIAAUKaghlHgCFAAAAAA==.',
We='Wetkittyy:BAAANQABCgUICAAAAA==.',
Wh='Whobetter:BAAANQADCgYICQAAAA==.',
Wi='Winterous:BAAANQAECgQIBgAAAA==.Wisdomheart:BAAANQAECggICgAAAA==.',
Wo='Wonderbread:BAABNQAECn9MAAIFAAoKpxRoUgAkAgAFAAoKpxRoUgAkAgAAAA==.',
['Wá']='Wáshu:BAAANQAECgUIDgAAAA==.',
Xa='Xaani:BAAANQAECgMIAgAAAA==.',
Xe='Xenan:BAABNQAECn8vAAIFAAoKtgqtjwCYAQAFAAoKtgqtjwCYAQAAAA==.',
Xt='Xtrolldinary:BAAANQAECgYIBgAAAA==.',
Ye='Yeastmode:BAABNQAECn8jAAMEAAgK3grdwwB6AQAEAAgK3grdwwB6AQANAAEKogKQnQAhAAAAAA==.',
Yi='Yingsol:BAAANQAECgUIBAABNQAECgYIDwABAAAAAA==.',
Yo='Yonahh:BAAANQAECgcIDQAAAA==.',
Yv='Yvelthilios:BAABNQAECn8VAAISAAkKBAfrmQBeAQASAAkKBAfrmQBeAQAAAA==.',
Za='Zangsha:BAAANQADCgcIBwAAAA==.',
Ze='Zeebra:BAABNQAECn8rAAIEAAkKbhPCTQAeAgAEAAkKbhPCTQAeAgAAAA==.Zeg:BAABNQAECn8wAAMKAAoKKiIEDgBBAwAKAAoKKiIEDgBBAwAMAAIK1gsLFAFlAAAAAA==.Zega:BAAANQAECggICAAAAA==.Zegafur:BAAANQAECgIIAgAAAA==.',
Zi='Zillionbucks:BAABNQAECn8UAAIOAAkKJBfOcQA/AgAOAAkKJBfOcQA/AgAAAA==.Zillionbúcks:BAAANQAECgUICQABNQAECgkJFAAOACQXAA==.',
Zo='Zoidworf:BAAANQAECgMIBQAAAA==.',
Zu='Zulg:BAAANQADCgQIBAAAAA==.Zulgore:BAAANQAECgYIBgAAAA==.Zullee:BAAANQADCgIIAgAAAA==.',
['Zê']='Zêddicus:BAABNQAECn9BAAMlAAoK0BTWJQBGAQAHAAgKvRIOagCFAQAlAAYK4xbWJQBGAQAAAA==.',
['Áq']='Áquafina:BAABNQAECn8vAAISAAoK7QvDxwD1AQASAAoK7QvDxwD1AQAAAA==.',
['Ðr']='Ðrâgøñ:BAAANQAECggICAAAAA==.',
['Ðö']='Ðö:BAABNQAECn8jAAIRAAoK6RayBwAeAgARAAoK6RayBwAeAgAAAA==.',
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
