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

local lookup = {'Druid-Guardian','Druid-Balance','Hunter-BeastMastery','Paladin-Retribution','Mage-Frost','Warlock-Demonology','DemonHunter-Vengeance','DeathKnight-Unholy','Shaman-Restoration','Druid-Restoration','Shaman-Elemental','Hunter-Marksmanship','Unknown-Unknown','Monk-Brewmaster','Priest-Holy','Warrior-Arms','Warrior-Fury','Mage-Arcane','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Protection','Shaman-Enhancement','Monk-Windwalker','DeathKnight-Frost','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Rogue-Outlaw','Paladin-Holy','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Priest-Discipline',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aaril:BAAANQADCgYIGwAAAQ==.',
Ab='Abrams:BAABNQAECn8oAAMBAAoK5g2eHgCqAQABAAoK5g2eHgCqAQACAAgKAgeVWAByAQAAAA==.Absínthè:BAAANQABCgQIBAAAAA==.',
Ag='Agnass:BAAANQADCgYIGgAAAA==.',
Ak='Akina:BAAANQAECggIDgAAAA==.',
Al='Alcholic:BAAANQAECggIAgAAAA==.Aldea:BAAANQADCgYIBgAAAA==.Alialista:BAABNQAECn8WAAIDAAgKNRInlQDeAQADAAgKNRInlQDeAQAAAA==.Alirrayia:BAAANQADCgMIAwAAAA==.Alirrayiia:BAABNQAECn8tAAIEAAkKxA+2WQARAQAEAAkKxA+2WQARAQAAAA==.Allmight:BAAANQADCgMIAwAAAA==.Allystar:BAAANQADCgUICgAAAA==.Alvidor:BAABNQAECn8fAAIFAAcK/Ah5GQArAQAFAAcK/Ah5GQArAQAAAA==.',
Am='Amachine:BAAANQADCggIDgABNQAFFAcIGgAGAPkeAA==.Amethen:BAAANQAECgMIBgAAAA==.Amybabe:BAAANQAECgQICwAAAA==.',
An='Andydufresne:BAAANQAECgcICgABNQAECgoKMAAHAH8hAA==.Anestesiax:BAAANQAECgUIBAAAAA==.Anorivia:BAABNQAECn8lAAIIAAgKYQgqIQDmAAAIAAgKYQgqIQDmAAAAAA==.',
Ap='Apolloerosp:BAAANQAECgQICQABNQAECgkJIQAJAJYQAA==.Apollossham:BAABNQAECn8hAAIJAAkKlhB+LQAsAQAJAAkKlhB+LQAsAQAAAA==.',
Ar='Araluen:BAAANQABCgMIAwAAAA==.Arkagob:BAAANQADCgcIBwAAAA==.Arragora:BAAANQAECgQIBQAAAA==.Arrowdynamix:BAABNQAECn8WAAIDAAkKGxG3RQApAQADAAkKGxG3RQApAQAAAA==.',
As='Ashyani:BAAANQADCgUIBQAAAA==.',
At='Atlan:BAAANQADCgUIBQABNQAECggIJAAKAOshAA==.',
Au='Aurnhadon:BAAANQABCggIDAAAAA==.',
Ba='Babbayagga:BAABNQAECn8gAAILAAkKshHrUQAxAgALAAkKshHrUQAxAgAAAA==.Baji:BAABNQAECn8tAAMJAAoKRBpjCwAPAgAJAAoKRBpjCwAPAgALAAgK0xYtXQAKAgAAAA==.Barefaall:BAACNQAFFH8KAAMDAAcKkwr4CwCRAQADAAUK1wr4CwCRAQAMAAMKLAoeFgDdAAA1AAQKfz8AAwMACgrvJV8fABoDAAMACQo4Jl8fABoDAAwABgrXIC8OABkBAAAA.Barefalls:BAAANQAECgcIEgABNQAFFAcICgADAJMKAA==.Baénoth:BAAANQABCgQIBgAAAA==.',
Be='Bealzebub:BAAANQAECgQIBAAAAA==.Bellucci:BAAANQADCgcICAABNQAECgcIHQAGAIINAA==.Berglock:BAAANQADCgcIBwABNQAECgYICQANAAAAAA==.Bergonator:BAAANQAECgYICQAAAA==.Bergue:BAAANQADCgQIBAABNQAECgYICQANAAAAAA==.Berrodiah:BAAANQADCgcIDQABNQAECggIHwAOACMYAA==.Bestlays:BAAANQADCgUIBQAAAA==.Bettiepage:BAAANQAECgUIBAAAAA==.',
Bh='Bheiroth:BAABNQAECn8qAAIPAAkKeSSmAgAyAwAPAAkKeSSmAgAyAwAAAA==.',
Bl='Blackchapell:BAAANQABCgYICQAAAA==.Blewmyload:BAAANQAECgUIBgAAAA==.Bluett:BAAANQADCgYIFwAAAA==.',
Bo='Bogertus:BAABNQAECn8nAAMQAAkKeSV9EgByAwAQAAgKaSZ9EgByAwARAAMK/h/YHgDJAAAAAA==.Boomertunes:BAAANQADCgQIBAAAAA==.Boxnasty:BAAANQADCgEIAQAAAA==.',
Br='Brein:BAABNQAECn8iAAIKAAcKbSEpAwB0AgAKAAcKbSEpAwB0AgAAAA==.',
Bu='Bucketeer:BAAANQAECgUICQAAAA==.Burzona:BAAANQABCgMIAwAAAA==.',
Ca='Cameltoetoe:BAAANQAECgEIAgAAAA==.Canaprey:BAAANQAECggIEQAAAA==.Cathogin:BAAANQADCggIDgAAAA==.Catsdruid:BAAANQADCgcIBwAAAA==.Catshunter:BAAANQAECgEIAQAAAA==.',
Ce='Celaa:BAAANQADCgQIBAABNQAECggIDgANAAAAAA==.Celebrían:BAAANQADCgUICAAAAA==.Celor:BAAANQABCgQIBgAAAA==.',
Ch='Chanka:BAAANQADCgcIEAAAAA==.Chantillary:BAAANQADCgYIGgAAAA==.Charise:BAAANQAECgUIDAAAAA==.Cheesy:BAAANQADCgYIDAAAAA==.Chopzullee:BAAANQAECgEIAQAAAA==.',
Ci='Cinnaz:BAAANQAECgUICwABNQAECgoKLgASAFITAA==.',
Cl='Clortho:BAAANQAECgUICwAAAA==.Clorthö:BAAANQADCgcIEgAAAA==.',
Co='Colbiw:BAAANQABCgIIAgAAAA==.Colljack:BAACNQAFFH8cAAITAAcKCh/JAQA7AgATAAcKCh/JAQA7AgA1AAQKfyoAAhMACgpjJJoEAG0DABMACgpjJJoEAG0DAAAA.Corvath:BAAANQAECgUIEQAAAA==.',
Cr='Cryptoe:BAABNQAECn9BAAISAAoKch2KGACuAQASAAoKch2KGACuAQAAAA==.',
Cy='Cyngin:BAAANQAECgQIBAAAAA==.',
Da='Daedamus:BAAANQADCgYIBgAAAA==.Daedelus:BAABNQAECn8dAAMUAAgKzhfiJQAWAgAUAAgKzhfiJQAWAgAHAAIKew3hKABuAAAAAA==.Daglon:BAAANQAECgYIEgAAAA==.Daraedra:BAAANQADCggIKgAAAA==.Dardolur:BAAANQADCgIIAgAAAA==.Darkbane:BAAANQADCggICAAAAA==.Darknìght:BAABNQAECn8XAAIVAAYK0R7/MAAgAgAVAAYK0R7/MAAgAgAAAA==.Darkraider:BAAANQAECgQICAAAAA==.Darkshade:BAAANQADCgMIAwAAAA==.Darkslayer:BAAANQADCgMIBQAAAA==.Darkthyr:BAAANQAECgQIBQAAAA==.',
De='Deeznutticus:BAACNQAFFH8NAAIQAAYKCBP4FQB5AQAQAAYKCBP4FQB5AQA1AAQKfy8AAhAACgrNHp0eAD0DABAACgrNHp0eAD0DAAAA.Demonspud:BAAANQAECgYIEAAAAA==.Dersan:BAAANQADCgIIAgAAAA==.Destriant:BAABNQAECn8yAAITAAkKwx6TAQBwAgATAAkKwx6TAQBwAgAAAA==.Devourer:BAAANQABCgMIAwAAAA==.Dewburt:BAAANQAECgUIBQAAAA==.Deylia:BAAANQAECgEIAQABNQAFFAUIDgAPAJYKAA==.',
Dh='Dhori:BAAANQADCgYIGgAAAA==.',
Di='Dillion:BAAANQAECgEIAQABNQAECgcIHQAGAIINAA==.Dionin:BAAANQADCgUICgAAAA==.Dirky:BAAANQAECggIBwAAAA==.Dirtychai:BAAANQAECgQIBwAAAA==.Disappear:BAAANQADCgYICgABNQAECgoKLgASAFITAA==.Dizzyhealz:BAAANQADCgMICQAAAA==.Dizzyhuntres:BAAANQADCgYIBwAAAA==.',
Do='Dooberto:BAABNQAECn8fAAMWAAkKbg51GQCbAQAWAAkKbg51GQCbAQAQAAMKywReMgFwAAAAAA==.Dooburt:BAAANQAECggIDwAAAA==.',
Dr='Dracaric:BAAANQADCgYIBgAAAA==.Draeca:BAAANQADCgYIFwAAAA==.Dragondznut:BAAANQADCggIDwAAAA==.Drfrostie:BAAANQAECgYIBgAAAA==.Driatin:BAAANQAECgEIAQAAAA==.',
Du='Durø:BAABNQAECn8xAAIUAAoK1h9tCQBBAwAUAAoK1h9tCQBBAwAAAA==.',
['Dè']='Dègenerate:BAABNQAECn83AAIWAAoKeCCIAwBiAwAWAAoKeCCIAwBiAwAAAA==.',
Ed='Eddy:BAABNQAECn8lAAIXAAoKow3zFQAJAgAXAAoKow3zFQAJAgAAAA==.',
Ei='Eilae:BAAANQADCgcIDQAAAA==.Einherjarr:BAAANQADCgYICgAAAA==.',
El='Eldumpling:BAABNQAECn8XAAIYAAcK9hOoDgA8AQAYAAcK9hOoDgA8AQABNQAECggICwANAAAAAA==.Elefante:BAAANQADCgYICwAAAA==.',
Ep='Epicnym:BAABNQAECn8dAAMLAAcKvBlqIAA6AQALAAYK5BpqIAA6AQAXAAQKSBQGJQAMAQAAAA==.',
Es='Esdeath:BAABNQAECn8eAAQIAAcKowuRGAAfAQAZAAYKeAwbXAA4AQAIAAcKtQiRGAAfAQAaAAMK4gHauQBUAAAAAA==.',
Ev='Evoberg:BAAANQABCgYIBgABNQAECgYICQANAAAAAA==.',
Ex='Extenze:BAABNQAECn8dAAIUAAgKLBcjBQDDAQAUAAgKLBcjBQDDAQAAAA==.',
Ez='Ezykiah:BAAANQADCggIFgAAAA==.',
Fe='Feda:BAAANQADCgQIBAAAAA==.Ferryman:BAABNQAECn8VAAIDAAcKzRETvQCJAQADAAcKzRETvQCJAQAAAA==.',
Fi='Findria:BAAANQADCgYIBgABNQAFFAMIBQADABUZAA==.',
Fo='Forphium:BAACNQAFFH8QAAMbAAUKggoTCQBcAQAbAAUKwgcTCQBcAQAcAAEKTQtyIABHAAA1AAQKfysAAxsACgqOH2ALAIYBABsACQrvIGALAIYBABwAAQrnFXGcAEQAAAAA.',
Fr='Fredolf:BAAANQADCgQJBAAAAA==.Freespirit:BAAANQAECgcIDAABNQAFFAcIHQAdACIhAA==.Friarkuck:BAAANQADCgEIAQAAAA==.Frierenn:BAAANQABCggIFQAAAA==.Frosteddonut:BAAANQAECgIIAgABNQAECgoKLgAKAGAjAA==.Frostieheals:BAAANQAECgMIAwAAAA==.',
Ga='Gahlina:BAAANQAECgEIAQAAAA==.Gambaaddict:BAABNQAECn8bAAIeAAgKoBIdCgDdAQAeAAgKoBIdCgDdAQAAAA==.Ganhammer:BAAANQADCgIIAgAAAA==.Garshan:BAAANQAECgMIAwAAAA==.',
Ge='Genestarwind:BAAANQAECgQIDAAAAA==.',
Gh='Ghexn:BAAANQADCgIIAgAAAA==.',
Gi='Gilleyy:BAAANQAECgUICQAAAA==.Gird:BAABNQAECn8jAAIfAAgKAxJEDwDgAQAfAAgKAxJEDwDgAQAAAA==.Girdlock:BAAANQAECgIIAgAAAA==.',
Gl='Glyph:BAAANQADCgUIBQABNQAECgoKJgAJAOoYAA==.',
Gn='Gnymesis:BAAANQADCgYICwAAAA==.',
Go='Goatmonger:BAAANQAECggICgAAAA==.Goinpostal:BAAANQADCgYICwAAAA==.Goldblade:BAAANQAECggICAAAAA==.Gordek:BAABNQAECn8XAAIEAAkKbxPsngDkAQAEAAkKbxPsngDkAQAAAA==.',
Gr='Graceteena:BAAANQABCgQIBQAAAA==.Grahra:BAAANQABCgIIBAAAAA==.Grantaron:BAABNQAECn8uAAIEAAkKaRvwDAAZAgAEAAkKaRvwDAAZAgAAAA==.Grimskul:BAABNQAECn8rAAIIAAkKLxkBMQBqAgAIAAkKLxkBMQBqAgAAAA==.Grntitan:BAAANQADCgcIFwAAAA==.Gruid:BAAANQADCgYIBgAAAA==.',
Gw='Gwoohoori:BAABNQAECn8VAAIEAAgKixbrFQDPAQAEAAgKixbrFQDPAQAAAA==.',
Ha='Halukari:BAAANQADCggIDAABNQAFFAUIDgAPAJYKAA==.Haléon:BAAANQAECgUIDwAAAA==.Hamnier:BAAANQABCgcIDwAAAA==.Harfnan:BAAANQADCgYICQAAAA==.Harperlee:BAAANQAECgQIBAAAAA==.',
He='Headshotty:BAAANQAECgUICAAAAA==.Hellfire:BAAANQADCgYIBgAAAA==.Hezrel:BAAANQAECgQIBwAAAA==.',
Hi='Hinal:BAABNQAECn8WAAMEAAcKkhSXsAC+AQAEAAcKkhSXsAC+AQATAAQKEw2iUACjAAAAAA==.',
Ho='Holyenabler:BAAANQAECgYIEAAAAA==.Honzo:BAABNQAECn8XAAMaAAkKqQZXbgA8AQAaAAkKqQZXbgA8AQAZAAEKAADurgAyAAAAAA==.',
Hu='Hungor:BAAANQABCgQIBAAAAA==.',
Ic='Iceberg:BAAANQADCgEIAQABNQAECgYICQANAAAAAA==.Icecrystal:BAAANQABCgIIAgAAAA==.',
Ih='Iheartbailey:BAAANQADCgQIBAAAAA==.',
Im='Imcruel:BAACNQAFFH8ZAAISAAcKjhsEDgAHAgASAAcKjhsEDgAHAgA1AAQKfzkAAhIACgopI5kPAJQDABIACgopI5kPAJQDAAAA.Iminyë:BAAANQAECgEIAQAAAA==.',
Io='Iorese:BAAANQADCggIDwAAAA==.',
Ir='Iriana:BAEANQADCgYIMQABNQADCggICAANAAAAAA==.',
Ja='Jabes:BAAANQAECgUIBQAAAA==.Jackiegan:BAAANQADCgEIAQAAAA==.Jagershamer:BAAANQAECgcIBwABNQAECggIBwANAAAAAA==.Jasperine:BAAANQAECgcIEAABNQAFFAcIHQAdACIhAA==.',
Je='Jenneldots:BAAANQAECgYIEgAAAA==.Jerce:BAAANQADCgUICQAAAA==.',
Jo='Johnnyhuntz:BAAANQADCgYICAAAAA==.',
Ju='Juacqer:BAAANQADCgYIFQAAAA==.Junamara:BAAANQAECgQICQAAAA==.',
Ka='Kaant:BAABNQAECn8iAAMLAAcKdBX1IwAsAQALAAYK7Bj1IwAsAQAJAAcKSxCbpwAiAQAAAA==.Kaetiegh:BAAANQADCgUIDwAAAA==.Kaidevyn:BAABNQAECn8hAAIZAAgKHRIQHwAqAQAZAAgKHRIQHwAqAQAAAA==.Kardead:BAAANQAECgMIBAAAAA==.Kat:BAAANQADCgQICAAAAA==.',
Kb='Kbang:BAAANQAECgIIAgAAAA==.',
Ke='Keiran:BAABNQAECn8xAAIDAAkKDx+zBACKAgADAAkKDx+zBACKAgAAAA==.Kenix:BAAANQADCgUICAABNQADCgYICgANAAAAAA==.',
Kh='Khalnerys:BAABNQAECn8cAAQgAAYK2wUIKQDlAAAgAAYKsQQIKQDlAAAhAAQKUALQQwCFAAAiAAMKTQWSHgBsAAAAAA==.Khaotick:BAEBNQAECn8rAAQGAAoKJRnKMAA2AQAGAAkKcxjKMAA2AQAjAAQK5A4VPQDNAAAkAAEKAABJMwAtAAABNQAECgkJGgAGAPIPAA==.Khoulock:BAABNQAECn8hAAQGAAkK6B8HLgDOAgAGAAkKfR8HLgDOAgAjAAYK4B/1FwCtAQAkAAEKAABlLAA+AAAAAA==.',
Ki='Kimmi:BAAANQAECgQIBQAAAA==.Kimmispally:BAAANQADCggICAAAAA==.Kiro:BAAANQADCgYIDAAAAA==.',
Ko='Kotawar:BAAANQAECgMIAwAAAA==.Kozana:BAAANQADCgIIAgAAAA==.',
Kt='Kthxbye:BAAANQAECggIBwAAAA==.',
Ku='Kuraishin:BAABNQAECn8mAAIlAAoKch/ZBgD7AgAlAAoKch/ZBgD7AgAAAA==.Kuterr:BAAANQADCgUIBQAAAA==.',
Ky='Kyrae:BAAANQADCgYIEAABNQAECgYIDwANAAAAAA==.Kyrub:BAAANQABCggICAAAAA==.',
La='Latheal:BAAANQADCgYIEwAAAA==.Latto:BAAANQAECgUIEQABNQAECgYIEgANAAAAAA==.',
Le='Lengex:BAAANQAECgUIBAAAAA==.Lero:BAAANQAECgIIAgAAAA==.Levatan:BAAANQAECgEIAQAAAA==.Lexoh:BAAANQAECgQIAgAAAA==.',
Li='Lilieth:BAAANQADCgYIFQAAAA==.Liltankarmor:BAAANQAECgYICgABNQAECgYIEgANAAAAAA==.Lindir:BAACNQAFFH8FAAIDAAMKFRnaBQACAQADAAMKFRnaBQACAQA1AAQKfyoAAgMACgp6JK0MAHkDAAMACgp6JK0MAHkDAAAA.Liquid:BAACNQAFFH8IAAIdAAUKmQ36BADdAAAdAAUKmQ36BADdAAA1AAQKfycAAx0ACgp8GQYWAK0CAB0ACgp8GQYWAK0CACYAAQq0A2cuACgAAAAA.Litasfk:BAAANQAECgQICAAAAA==.Liuni:BAABNQAECn8pAAIOAAkKcRS6AgCSAQAOAAkKcRS6AgCSAQAAAA==.',
Lo='Lobopeste:BAABNQAECn8iAAIaAAcKzAvVJwDWAAAaAAcKzAvVJwDWAAAAAA==.Loborocco:BAAANQADCgIIAgAAAA==.Lobotomi:BAAANQADCgYIDgAAAA==.Lorantell:BAAANQADCgYIBgAAAA==.Lorelynn:BAABNQAECn8nAAIjAAgKKxnACgBLAgAjAAgKKxnACgBLAgAAAA==.Loðbrók:BAAANQADCgYIDgAAAA==.',
Lu='Luci:BAAANQADCgQIBAABNQAECgYIEgANAAAAAA==.Luckycritz:BAAANQAECgIIAQABNQAECgcIBwANAAAAAA==.Lucìan:BAABNQAECn8kAAIKAAYK6yFYCwCDAQAKAAYK6yFYCwCDAQAAAA==.Luna:BAAANQAECgQIBAABNQAECgkJGwAPAPYbAA==.Lunaclair:BAABNQAECn8cAAMIAAkKuxPNEgBGAQAIAAkKuxPNEgBGAQAaAAMK8wlMtABgAAABNQAECgoKJgAlAHIfAA==.Lunarielle:BAAANQAECgQIBgAAAA==.',
Ma='Mabrito:BAAANQAECgcIDgABNQAFFAcIGAACAIUVAA==.Macfly:BAABNQAECn82AAIDAAoKshnCBwBLAgADAAoKshnCBwBLAgAAAA==.Macneel:BAAANQADCgEIAQABNQADCgYIGQANAAAAAA==.Magicmissile:BAAANQADCgQIBAABNQAFFAMIBQAQAHwIAA==.Malevalous:BAAANQADCgQICQABNQAECgoKKAAIAAUWAA==.Mancath:BAABNQAECn8kAAIEAAoKLhe4HQCrAQAEAAoKLhe4HQCrAQAAAA==.Maplè:BAAANQADCgYIBgABNQAECgEIAQANAAAAAA==.Marlei:BAAANQAECgUICwABNQAECggIDgANAAAAAA==.Maru:BAAANQADCgcIBwABNQAECgoKLQAJAEQaAA==.Maxzang:BAAANQABCggIEAAAAA==.',
Me='Medenà:BAAANQADCgUICAAAAA==.Meeko:BAACNQAFFH8HAAIhAAMKOxv9DwD3AAAhAAMKOxv9DwD3AAA1AAQKfyEAAiEACQqhHAsCADsCACEACQqhHAsCADsCAAE1AAUUBwgQACEAuBYA.Melfie:BAAANQAECgEIAQAAAA==.',
Mi='Midoriya:BAAANQAECggIDgAAAA==.Mihoshi:BAAANQAECgQIBAAAAA==.Mistjack:BAAANQADCggICAAAAA==.',
Mo='Moldyjack:BAAANQAECgMIBgAAAA==.Morphium:BAAANQAECgYIBgABNQAFFAUIEAAbAIIKAA==.Mortiis:BAAANQADCgMIAwAAAA==.Moxi:BAAANQADCgUIBQAAAA==.',
My='Myzyry:BAABNQAECn8aAAIQAAkK9w/0iwD+AQAQAAkK9w/0iwD+AQAAAA==.',
['Mä']='Märtyr:BAAANQADCgUIBQAAAA==.',
['Må']='Måze:BAAANQAECgQIBAAAAA==.',
['Më']='Mërlïn:BAAANQADCgYIBgAAAA==.',
Na='Nards:BAAANQAECggICgAAAA==.Nazdormu:BAAANQAECgQICQAAAA==.',
Ne='Nebulous:BAAANQADCgIIAgAAAA==.Neisen:BAAANQAECgQICQAAAA==.Neptune:BAAANQADCggICAAAAA==.Nevare:BAAANQAECgcIEAAAAA==.',
Ni='Nite:BAABNQAECn8uAAISAAoKUhNLlwBSAgASAAoKUhNLlwBSAgAAAA==.',
No='Nou:BAEANQAECggIBwABNQAECgkJGgAGAPIPAA==.',
Nu='Nubi:BAAANQADCgIIAgAAAA==.Nugent:BAABNQAECn8aAAIDAAkKCxwSOgC8AgADAAkKCxwSOgC8AgAAAA==.',
Ny='Nymmie:BAAANQAECgMIAwAAAA==.Nymofthedead:BAAANQADCgcIBwAAAA==.',
Oa='Oakgrove:BAAANQADCgIIAgAAAA==.',
Ok='Okarun:BAAANQADCgEIAQAAAA==.',
On='Oneforall:BAACNQAFFH8FAAIfAAIK7Q4eDgCJAAAfAAIK7Q4eDgCJAAA1AAQKfzIAAh8ACgrjGjQrALsCAB8ACgrjGjQrALsCAAAA.',
Or='Orphen:BAAANQAECgQIBAAAAA==.',
Pa='Pailly:BAAANQABCgQIBAAAAA==.Papalion:BAABNQAECn8eAAIDAAgKZwp0rACsAQADAAgKZwp0rACsAQAAAA==.Paryl:BAABNQAECn8dAAIGAAcKgg03RgD/AAAGAAcKgg03RgD/AAAAAA==.Pawbs:BAAANQADCgYIBgAAAA==.',
Pe='Peanuts:BAAANQAECggICAAAAA==.',
Pi='Pikake:BAAANQADCgUICQAAAA==.Pinklilydrd:BAAANQADCgYIFAAAAA==.',
Pl='Plaindonut:BAABNQAECn8uAAMKAAoKYCMQAwB7AgAKAAoKYCMQAwB7AgACAAEKAAAYpQBPAAAAAA==.Pluffeh:BAAANQADCgUICQABNQAECgMIBQANAAAAAA==.',
Pm='Pmoney:BAAANQAECgcIBwAAAA==.',
Pr='Prissidebow:BAAANQADCgYIDAAAAA==.Prissygalore:BAAANQADCgEIAQAAAA==.',
Pu='Puddinpie:BAAANQADCgEIAQAAAA==.Punkhazard:BAAANQAECgIIAgAAAA==.Putras:BAAANQABCgIIAgAAAA==.',
Qu='Quartz:BAAANQAECgYICQABNQAECgkJJwAQAHklAA==.Quinraidar:BAAANQAECgQIAwABNQAECgoKLQAJAEQaAA==.',
Ra='Ranor:BAAANQAECgIIAgABNQAECgkJKQAOAHEUAA==.Ravenbrook:BAABNQAECn8zAAIRAAoKpSYvAAD4AwARAAoKpSYvAAD4AwAAAA==.Ravus:BAAANQADCgIIAgAAAA==.Rawrr:BAAANQAECgUIEQAAAA==.Raxie:BAACNQAFFH8OAAQPAAUKlgpACwARAQAPAAQK8QtACwARAQAdAAMKKQWAEADFAAAmAAEKSQFiBQAxAAA1AAQKfy8ABB0ACgovFtgdAFECAB0ACQr4FNgdAFECACYABwo6EZULAIYBAA8ABApGFzJxAIIAAAAA.',
Re='Reddfoxx:BAAANQAECgcIDQAAAA==.Resepuff:BAAANQADCggIEAAAAA==.',
Rh='Rhymunky:BAAANQADCgMIAwAAAA==.',
Ri='Rifthor:BAAANQADCgYIBgAAAA==.Ripmxi:BAAANQAECgYIEgAAAA==.',
Ro='Roknarogue:BAAANQAECgEIAQAAAA==.',
Ru='Runelight:BAAANQADCgMIAwABNQAECgoKJgAJAOoYAA==.Runeshock:BAABNQAECn8mAAIJAAoK6hirNwCAAgAJAAoK6hirNwCAAgAAAA==.Runesummon:BAAANQADCggIDAAAAA==.Rupertgiless:BAACNQAFFH8VAAIGAAcKXRA4CgDGAQAGAAcKXRA4CgDGAQA1AAQKfy8AAgYACgrYHBI0ALkCAAYACgrYHBI0ALkCAAAA.',
Sa='Sadoh:BAAANQABCgMIAwABNQAECgMIBQANAAAAAA==.Sainttristan:BAAANQABCgEIAQAAAA==.Saluran:BAAANQABCgYIBgAAAA==.Sanitariums:BAAANQADCgQIBAABNQADCgYIFgANAAAAAA==.Sannea:BAAANQADCgUICgABNQAECggIDgANAAAAAA==.Sarcastyx:BAABNQAECn8UAAIjAAcKUxC3GQCeAQAjAAcKUxC3GQCeAQAAAA==.Saværo:BAAANQADCgMIBAAAAA==.Saxines:BAAANQAECgMIBAAAAA==.',
Sc='Scaliefox:BAAANQADCgQIBAABNQAECgcIIgAPAMwQAA==.Schwarznacht:BAAANQAECgQIBAAAAA==.',
Se='Seekndestroy:BAABNQAECn8bAAILAAgKuQbBqABCAQALAAgKuQbBqABCAQAAAA==.Semperfimack:BAAANQADCgQJBAAAAA==.',
Sh='Shamwhoa:BAAANQABCgQIBQAAAA==.Shankkerz:BAABNQAECn8UAAMCAAgKeQv4TwCeAQACAAgKeQv4TwCeAQAlAAQKDgaPLgCdAAAAAA==.',
Si='Simonx:BAABNQAECn8WAAIEAAgKKwwjIwCXAQAEAAgKKwwjIwCXAQAAAA==.Sindusk:BAAANQAECgYIDAAAAA==.Sitzho:BAAANQADCggIGgAAAA==.',
Sk='Skeleton:BAAANQABCgIIAgAAAA==.Skullblade:BAAANQAECgQICwAAAA==.Skybringer:BAABNQAECn8eAAIEAAgKGAZylACvAAAEAAgKGAZylACvAAAAAA==.Skydras:BAABNQAECn8tAAMaAAoKhx2MEABdAQAIAAcKPRPAZAB+AQAaAAkKQR2MEABdAQAAAA==.Skyhoof:BAAANQAECgEIAQABNQAECgoKLQAaAIcdAA==.',
Sm='Smolbeans:BAAANQADCgQIBAAAAA==.Smoothscales:BAAANQADCgUIBQAAAA==.Smoothtotem:BAAANQADCgIIAgAAAA==.',
So='Sonofgrumpy:BAAANQADCggIEAABNQAECggIEQANAAAAAA==.Sorphium:BAAANQAECgUICQABNQAFFAUIEAAbAIIKAA==.Soxxy:BAAANQADCgEIAQABNQAECgYIEgANAAAAAA==.',
Sp='Sparhawk:BAAANQADCgYIEQAAAA==.',
St='Stham:BAAANQADCgQIBQAAAA==.Stormyprissi:BAAANQADCgUIDQAAAA==.Strombjorn:BAAANQAECgEIAQAAAA==.',
Ta='Talie:BAAANQAECgQIBwAAAA==.Tasireth:BAAANQADCgMIAwAAAA==.',
Te='Tessi:BAABNQAECn8iAAMFAAcKcQnKHAAIAQAFAAYKWQvKHAAIAQASAAUKyQLOhAG7AAAAAA==.Testamental:BAAANQAECgIJAgAAAA==.',
Th='Thaloran:BAAANQADCgcICAAAAA==.Thalrian:BAAANQAECgcIDAABNQAECgoKMwAQAHwiAA==.Theberes:BAAANQAECgEIAQAAAA==.Thelance:BAAANQABCggIDQAAAA==.Theylive:BAAANQADCgcIBwAAAA==.Thighs:BAAANQAECgQIBgAAAA==.Thordanil:BAABNQAECn8WAAMEAAcKthCL2gBmAQAEAAYKthCL2gBmAQATAAEKAABCZwBGAAAAAA==.',
Ti='Tiahina:BAAANQADCgUIBQAAAA==.Tioklarus:BAAANQADCggICQAAAA==.',
To='Tokifuji:BAAANQADCgIIAgABNQADCgYIBgANAAAAAA==.Tourettes:BAAANQADCggJCAAAAA==.Toya:BAABNQAECn8tAAMbAAoKjxaMBQDlAQAbAAoKjxaMBQDlAQAcAAQKZwUhgACzAAAAAA==.',
Tr='Transfurmer:BAAANQADCgMIAwABNQAECgoKNQAZANUgAA==.Trashdk:BAAANQADCgcICgAAAA==.Trevain:BAAANQADCgYIGQAAAA==.Trivia:BAAANQADCgcIJAAAAA==.Truthordare:BAAANQAECgUIDgAAAA==.',
Tu='Turtei:BAAANQADCggICAABNQAFFAcIGgAYAFYiAA==.Turtl:BAACNQAFFH8aAAIYAAcKViJ8AQClAgAYAAcKViJ8AQClAgA1AAQKfy4AAhgACgrwJi0BAN0DABgACgrwJi0BAN0DAAAA.',
Ty='Tylenolz:BAAANQADCgYIDAAAAA==.',
Ug='Uglypetguy:BAAANQADCgEIAQAAAA==.Uglypriest:BAAANQADCggIDgAAAA==.Uglyrogue:BAAANQAECgIIAgAAAA==.',
Ul='Ulgrym:BAAANQADCgYIGQAAAA==.',
Un='Unbalancéd:BAAANQADCgYIFgAAAA==.',
Va='Vaeadin:BAAANQAECgEIAQAAAA==.Vahra:BAAANQADCgYIFQAAAA==.Valantis:BAAANQAECgQIBAAAAA==.Valgaskav:BAACNQAFFH8IAAIEAAUKZRoFBgD+AAAEAAUKZRoFBgD+AAA1AAQKfxoAAgQACAr6I6YgAKABAAQACAr6I6YgAKABAAAA.Valkor:BAAANQADCgMIAgAAAA==.Valric:BAAANQAECgIIAgAAAA==.',
Ve='Vegasnight:BAAANQADCggIEwAAAA==.Vella:BAAANQAECgIIAQAAAA==.Venithan:BAAANQAECgYIDwAAAA==.Verdesoul:BAAANQADCgQIBAABNQAECgUIEQANAAAAAA==.',
Vi='Vikkrum:BAAANQADCgYICwABNQADCgYIGQANAAAAAA==.Virani:BAAANQAECgYICQAAAA==.',
Vo='Voladro:BAAANQAECgIIAgAAAA==.Volanie:BAAANQADCgYIBgAAAA==.Volos:BAABNQAECn8dAAIEAAYKIhLZdwDYAAAEAAYKIhLZdwDYAAAAAA==.Vordaman:BAABNQAECn8tAAMIAAgKMBZiHAAFAQAIAAgKMBZiHAAFAQAZAAEKYAXWtAArAAAAAA==.',
Vy='Vynír:BAACNQAFFH8JAAMjAAUKjg3vDwCUAAAGAAQKBApwKADEAAAjAAIKBw3vDwCUAAA1AAQKfyQAAwYACQoqIdcyAL0CAAYACArhINcyAL0CACMABApsHFsoADYBAAAA.',
Wa='Waandur:BAAANQADCgEIAQAAAA==.Waghoba:BAACNQAFFH8GAAIlAAIK0hRdAwCbAAAlAAIK0hRdAwCbAAA1AAQKf2UAAiUACgpTJhAAAIwDACUACgpTJhAAAIwDAAAA.Waito:BAAANQADCggIDQAAAA==.Wandä:BAABNQAECn8fAAMOAAgKIxgRBABWAQAOAAcK1hoRBABWAQAYAAUKiRT1SQDUAAAAAA==.Warborn:BAAANQADCggIDAAAAA==.Warrionomous:BAACNQAFFH8FAAIQAAMKfAgPEwCFAAAQAAMKfAgPEwCFAAA1AAQKfywAAhAACgpQGCRUAI4CABAACgpQGCRUAI4CAAAA.Washu:BAABNQAECn8tAAMVAAoKIRfhAgBxAgAVAAoKIRfhAgBxAgAHAAQK8AW1JwB5AAAAAA==.',
We='Wetkittyy:BAAANQABCgUICAAAAA==.',
Wh='Whobetter:BAAANQADCgYICQAAAA==.',
Wi='Winterous:BAAANQAECgQIBgAAAA==.',
Wo='Wonderbread:BAABNQAECn8zAAIEAAoKXBAhSQAzAQAEAAoKXBAhSQAzAQAAAA==.',
['Wá']='Wáshu:BAAANQAECgQIBwAAAA==.',
Xa='Xaani:BAAANQAECgIIAgAAAA==.',
Xe='Xenan:BAABNQAECn8fAAIEAAcKaAp8YwD+AAAEAAcKaAp8YwD+AAAAAA==.',
Xt='Xtrolldinary:BAAANQAECgEIAQAAAA==.',
Ye='Yeastmode:BAABNQAECn8YAAMDAAgKjwgIZwDdAAADAAgKjwgIZwDdAAAMAAEKogKQnQAhAAAAAA==.',
Yi='Yingsol:BAAANQAECgIIAgABNQAECgYIDwANAAAAAA==.',
Yo='Yonahh:BAAANQAECgcIDQAAAA==.',
Yv='Yvelthilios:BAAANQADCgcICgAAAA==.',
Za='Zangsha:BAAANQADCggIBwAAAA==.',
Ze='Zeebra:BAABNQAECn8cAAIDAAcKbg+QIgCOAQADAAcKbg+QIgCOAQAAAA==.Zeg:BAABNQAECn8kAAMJAAkKDiGMCAA6AgAJAAkKDiGMCAA6AgALAAIK1gsLFAFlAAAAAA==.Zega:BAAANQADCgcIBwAAAA==.Zegafur:BAAANQAECgIIAgAAAA==.',
Zi='Zillionbucks:BAABNQAECn8UAAIQAAkKJBfOcQA/AgAQAAkKJBfOcQA/AgAAAA==.Zillionbúcks:BAAANQAECgUICQABNQAECgkJFAAQACQXAA==.',
Zo='Zoidworf:BAAANQADCggICAAAAA==.',
Zu='Zulg:BAAANQADCgQIBAAAAA==.Zulgore:BAAANQAECgYIBgAAAA==.Zullee:BAAANQABCggIFgAAAA==.',
['Zê']='Zêddicus:BAABNQAECn8vAAMjAAkK4hL/BQDGAAAGAAYKyw8lRwD8AAAjAAYKThX/BQDGAAAAAA==.',
['Áq']='Áquafina:BAABNQAECn8rAAISAAoK7QvDxwD1AQASAAoK7QvDxwD1AQAAAA==.',
['Ðö']='Ðö:BAABNQAECn8YAAIRAAcKyRXgBABgAQARAAcKyRXgBABgAQAAAA==.',
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
