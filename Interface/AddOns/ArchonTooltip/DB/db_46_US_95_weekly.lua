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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Rogue-Assassination','Paladin-Retribution','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warlock-Affliction','Mage-Frost','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','Shaman-Restoration','Unknown-Unknown','Monk-Brewmaster','Shaman-Elemental','DemonHunter-Havoc','Druid-Feral','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Paladin-Holy','Priest-Discipline','Shaman-Enhancement','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Priest-Holy','Mage-Fire','DemonHunter-Devourer','Mage-Arcane','Rogue-Outlaw','Druid-Balance','Priest-Shadow','Warrior-Fury','Paladin-Protection','Druid-Restoration',}
local provider = {region='US',realm='Fenris',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aayu:BAABLgAECn8vAAIBAAgJyxmINgD/AQABAAgJyxmINgD/AQAAAA==.',
Ad='Addie:BAEBLgAFFH8GAAICAAIJ4hZ2DgCDAAACAAIJ4hZ2DgCDAAABLgAFFAkJOgADAIAmAA==.Adranelidk:BAABLgAECn8gAAICAAYJ6hQTJAAvAQACAAYJ6hQTJAAvAQAAAA==.',
Ae='Aeromina:BAABLgAECn8cAAMBAAcJORQ+ewBEAQABAAcJORQ+ewBEAQAEAAEJZABYnAAKAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgABLgAECggJKAAFANcbAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIGAAgJAxpDNQBNAgAGAAgJAxpDNQBNAgAAAA==.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJDQAAAA==.Alphabet:BAAALgADCgMJBQAAAA==.Alypiia:BAAALgAECgIJAgAAAA==.',
Am='Amadori:BAAALgAECgEJAQAAAA==.',
An='Ancalagon:BAABLgAECn8iAAQHAAgJDyEkBADwAgAHAAgJDyEkBADwAgAIAAgJ2wuCPgAsAQAJAAEJRhbQPAA7AAAAAA==.Angelic:BAAALgAECgIJAgAAAA==.Anguish:BAAALgAECgUJBwAAAA==.Antia:BAAALgAECgQJBAABLgAFFAUJDQAKAMMLAA==.',
Ap='April:BAABLgAECn8bAAILAAkJXwWo9gC2AAALAAkJXwWo9gC2AAAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIEAAIJLxlYGwCqAAAEAAIJLxlYGwCqAAAuAAQKfx8AAgQACQm5IigDAHgDAAQACQm5IigDAHgDAAAA.',
As='Ashveil:BAABLgAECn8qAAIIAAgJ0w/uNQBWAQAIAAgJ0w/uNQBWAQAAAA==.Asray:BAAALgAECgMJBwABLgAFFAQJEgAMABUeAA==.',
At='Athenã:BAAALgADCgEJAQAAAA==.',
Au='Aussiesauce:BAAALgAECgUJBQABLgAECgkJHgANADQVAA==.Aussilicious:BAABLgAECn8eAAMNAAkJNBVGHAAwAgANAAkJNBVGHAAwAgAOAAIJqAQdbwBVAAAAAA==.',
Az='Azerennia:BAABLgAECn8WAAILAAkJXwa6igBeAQALAAkJXwa6igBeAQAAAA==.Azerious:BAAALgAECgIJAwAAAA==.Azreya:BAAALgAECgEJAgAAAA==.Azrokke:BAABLgAECn8WAAIPAAkJwRkmGACFAgAPAAkJwRkmGACFAgAAAA==.',
Ba='Babetter:BAABLgAECn8tAAIBAAgJ9wZLfwA7AQABAAgJ9wZLfwA7AQAAAA==.Baby:BAAALgAECgYJBgAAAA==.Bacstabbe:BAAALgAECgEJAQAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAAQAAAAAA==.Baelz:BAAALgAECgMJAgAAAA==.Bahamaut:BAAALgAECgQJBgABLgAECgkJHgANADQVAA==.Balzan:BAAALgADCgYJBwAAAA==.',
Be='Beerless:BAABLgAECn8lAAIRAAkJMxQDFwDvAQARAAkJMxQDFwDvAQAAAA==.Belphegör:BAAALgAECgYJDgAAAA==.Bencicil:BAAALgAECgcJDwAAAA==.Berkleyf:BAAALgADCgYJCQABLgAFFAMJBwASADIMAA==.Beydoon:BAAALgAECgMJBwAAAA==.',
Bl='Blindmagg:BAAALgAECgYJCAABLgAECggJGAABAFAdAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgcJCAABLgAECgcJDAAQAAAAAA==.',
Br='Brain:BAAALgAECgEJAwAAAA==.Brawnhilda:BAAALgADCgcJDAABLgAECgkJHQABABYUAA==.Brewdude:BAAALgADCgcJBwAAAA==.Brewmanchu:BAAALgADCggJCAABLgAECgcJCAAQAAAAAA==.Bro:BAAALgAECgUJEQAAAA==.',
Bu='Bunky:BAAALgAECgMJBgABLgAFFAMJBwASADIMAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8eAAITAAcJjSTwAQBNAgATAAcJjSTwAQBNAgAuAAQKfygAAhMACQnuJcMBAIYDABMACQnuJcMBAIYDAAAA.Calayra:BAAALgADCgIJAgAAAA==.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8jAAQNAAgJKhjoJwDiAQANAAcJDxroJwDiAQARAAUJGQVXYADBAAAOAAEJ3A6angAuAAAAAA==.Cartheron:BAAALgAECgkJAgAAAA==.',
Ce='Cellynna:BAAALgADCggJFAAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgAAAA==.Crims:BAAALgADCgcJDgABLgADCgcJDgAQAAAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECggJDwAAAA==.',
Cy='Cynla:BAAALgAECgMJAwAAAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.Darremiah:BAAALgADCgEJAQAAAA==.David:BAACLgAFFH8HAAILAAMJfgr+hADVAAALAAMJfgr+hADVAAAuAAQKfygAAgsACQlKHYQmAH4CAAsACQlKHYQmAH4CAAAA.',
Db='Dbsheep:BAAALgAECgMJBQAAAA==.',
De='Deezhealz:BAAALgAECgYJDAAAAA==.Dezal:BAAALgADCgIJAgAAAA==.',
Di='Diddyfisting:BAACLgAFFH8aAAIOAAUJwCV4BgCpAQAOAAUJwCV4BgCpAQAuAAQKfzAAAw4ACQneI3MGAOICAA4ACQneI3MGAOICABEAAQk6A4mPACYAAAAA.Divinefistin:BAECLgAFFH8RAAIRAAQJEB/LFQBsAQARAAQJEB/LFQBsAQAuAAQKfzgAAxEACQnCIv0MAGUCABEACQnLHf0MAGUCAA4ABwlYIm4RADYCAAAA.Divinepain:BAEALgAECgMJAwABLgAFFAQJEQARABAfAA==.',
Dn='Dnova:BAAALgAECgMJBAAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCwAAAA==.Dornadions:BAAALgAECgYJDgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAABLgAECn8UAAMHAAgJAw5WFACCAQAHAAgJAw5WFACCAQAIAAYJJg6/TAD2AAAAAA==.Draka:BAABLgAECn8VAAIUAAkJaA5CEgCRAQAUAAkJaA5CEgCRAQAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Drunk:BAAALgAECgcJDAAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJCAAAAA==.',
Dy='Dymetra:BAAALgAECgEJAQAAAA==.',
Ec='Ecks:BAACLgAFFH8RAAIVAAcJGxoACgCGAQAVAAcJGxoACgCGAQAuAAQKfzMAAxUACQl8HswCADgDABUACQl8HswCADgDABYAAQkAAMOMAAAAAAAA.',
El='Elfuego:BAAALgAECggJDQAAAA==.',
Em='Employee:BAAALgAECgcJCwAAAA==.',
En='Energgy:BAAALgAECgkJCgAAAA==.Enigmanta:BAAALgADCgUJBQAAAA==.',
Er='Erodorina:BAAALgAECgUJCwAAAA==.',
Ev='Eviljoke:BAAALgADCgkJDwAAAA==.',
Fa='Faeda:BAAALgAECgUJCAAAAA==.Faestaul:BAABLgAECn8fAAIGAAgJtxZtTwDYAQAGAAgJtxZtTwDYAQAAAA==.Fatima:BAAALgAECgEJAgAAAA==.',
Fe='Fearyourface:BAAALgADCgMJAwAAAA==.Fenrisulfr:BAAALgADCgYJBgAAAA==.Fentdemon:BAAALgAFFAMJBAAAAA==.',
Fi='Findinnan:BAABLgAECn8aAAIFAAkJeQUpDQBVAQAFAAkJeQUpDQBVAQAAAA==.Fishtotem:BAAALgADCgcJDQAAAA==.',
Fl='Flor:BAAALgAECgEJAQAAAA==.',
Fr='Freeze:BAAALgAECgYJCQAAAA==.Freezerbern:BAAALgAECggJDwAAAA==.Frissbee:BAAALgADCgMJAwABLgAECgMJAwAQAAAAAA==.Frostblood:BAAALgADCgIJAgAAAA==.Froststd:BAAALgADCgEJAQAAAA==.Fréki:BAAALgAECgIJAgAAAA==.',
Fu='Fullpeny:BAAALgADCgEJAQAAAA==.',
Ga='Gametheory:BAAALgAECgIJBwAAAA==.Ganzar:BAACLgAFFH8TAAIXAAMJwyRXWQA9AQAXAAMJwyRXWQA9AQAuAAQKfycAAhcACQmnIiQIADADABcACQmnIiQIADADAAAA.Gathan:BAAALgADCgcJGQAAAA==.',
Ge='Genderdruid:BAAALgAECgIJAgAAAA==.Genge:BAABLgAECn83AAMGAAgJCxNXaACcAQAGAAgJCxNXaACcAQAYAAEJIQMNkgArAAAAAA==.Gertrex:BAABLgAECn8bAAIZAAkJDgsAJgCeAQAZAAkJDgsAJgCeAQAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.Gitchusum:BAAALgAECgcJBgAAAA==.',
Gl='Glennhelen:BAAALgADCgkJDwAAAA==.',
Go='Goatlord:BAABLgAECn8eAAIaAAkJMw/ZDwCvAQAaAAkJMw/ZDwCvAQAAAA==.Goatsavior:BAAALgAECgUJDgAAAA==.Goblinsrhot:BAAALgADCgkJDwAAAA==.Gotharm:BAABLgAECn8bAAIbAAkJsww7GADfAQAbAAkJsww7GADfAQAAAA==.',
Gr='Grester:BAAALgAECggJEwAAAA==.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAABLgAECn8cAAIBAAYJHB/8SwC5AQABAAYJHB/8SwC5AQAAAA==.',
Ha='Hahmicydal:BAABLgAECn8ZAAQKAAcJ9wfYHADTAAAKAAcJEgbYHADTAAAcAAYJXwYQIgCbAAAdAAEJ5gF2YgEWAAAAAA==.Hal:BAAALgAECgYJDwAAAA==.Hardcore:BAAALgADCgUJBQAAAA==.Havökush:BAACLgAFFH8JAAITAAMJIRAzGgDJAAATAAMJIRAzGgDJAAAuAAQKfyUAAhMACQmBIcwEAPcCABMACQmBIcwEAPcCAAAA.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgAECgEJAgAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAIZAAcJmw0bNABFAQAZAAcJmw0bNABFAQAAAA==.Holyguard:BAACLgAFFH8cAAIYAAYJGQ+GEgCVAQAYAAYJGQ+GEgCVAQAuAAQKfywAAhgACQkqFz0bACgCABgACQkqFz0bACgCAAAA.Holyhand:BAABLgAECn8UAAIeAAYJAg4DSQAVAQAeAAYJAg4DSQAVAQABLgAFFAYJHAAYABkPAA==.',
Ic='Ickis:BAAALgAECgYJBgABLgAECggJGAABAFAdAA==.',
Il='Ilin:BAAALgAECggJEAAAAA==.Illidres:BAAALgADCgQJBQAAAA==.Ilou:BAAALgAECgYJBgABLgAFFAUJDQAKAMMLAA==.',
In='Influenza:BAAALgAECgMJAwAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAABLgAECn8yAAIfAAkJzxePAgAkAgAfAAkJzxePAgAkAgAAAA==.',
Is='Isabela:BAABLgAFFH8IAAIgAAIJsyTMYADHAAAgAAIJsyTMYADHAAAAAA==.Isharadai:BAAALgADCgMJAwAAAA==.Isilian:BAAALgADCgUJCAAAAA==.',
Iw='Iwillpull:BAAALgADCgcJAQAAAA==.',
Iy='Iyora:BAAALgADCgUJBQAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgYJCAABLgAFFAUJGgAOAMAlAA==.Judyhopp:BAABLgAECn8aAAQhAAgJWhYxCAB2AQAhAAcJsBIxCAB2AQALAAcJFxMJpwAsAQAfAAEJAAAQGAAAAAABLgAFFAUJGgAOAMAlAA==.Judyhopps:BAAALgAECgcJEQABLgAFFAUJGgAOAMAlAA==.Judyhoppsimp:BAAALgAFFAEJAgAAAA==.',
Ka='Kaeln:BAAALgAFFAMJAwABLgAFFAUJEAAhAMYdAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kagronn:BAAALgADCggJCgAAAA==.Kakez:BAAALgAECgEJAQABLgAFFAgJJAAeANwXAA==.Kaluanights:BAAALgAECgEJAQAAAA==.Kalzak:BAABLgAECn8lAAIUAAkJhRDbEACkAQAUAAkJhRDbEACkAQAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAABLgAECn8ZAAIdAAYJ2wZ3vADRAAAdAAYJ2wZ3vADRAAAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kithiandra:BAAALgADCgIJAgAAAA==.Kiwistunna:BAAALgAECgYJDAABLgAECgkJHAASAOYRAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAABLgAECn8gAAIiAAkJSgveCQCHAQAiAAkJSgveCQCHAQAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAAQAAAAAA==.',
['Kï']='Kïtana:BAAALgAECgMJBAAAAA==.',
La='Laddyboy:BAAALgADCgMJAwAAAA==.Ladiemacbeth:BAAALgADCgkJDwABLgAECgkJJQAUAIUQAA==.Lanwynne:BAAALgADCgYJBAABLgAECgkJHQABABYUAA==.Laxion:BAAALgADCgkJGwAAAA==.',
Le='Leafs:BAAALgAECgEJAQAAAA==.Leggo:BAABLgAECn8dAAIYAAYJfhExPQBOAQAYAAYJfhExPQBOAQAAAA==.',
Li='Lidravos:BAAALgAECgEJAQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilia:BAACLgAFFH8KAAIGAAMJPwUsggCmAAAGAAMJPwUsggCmAAAuAAQKfyEAAwYACAlYHCQqAHwCAAYACAlYHCQqAHwCABgABAnYAX16AI8AAAAA.Lilmorty:BAAALgAECgYJDgAAAA==.',
Ll='Lluvioso:BAACLgAFFH8NAAMXAAMJ4h/mhgD3AAAXAAMJFB/mhgD3AAACAAEJ/iHpNwBSAAAuAAQKfyMAAwIACQnrI1oCAEwDAAIACQlNI1oCAEwDABcAAQkOH0VGAVQAAAAA.',
Lo='Loaf:BAABLgAECn8YAAILAAYJeR1gZACyAQALAAYJeR1gZACyAQAAAA==.Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8fAAIjAAcJeBwsIgC0AQAjAAcJeBwsIgC0AQAAAA==.',
Lu='Lunarbelle:BAAALgADCgkJDwAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAABLgAECn8gAAILAAgJKwxjhABrAQALAAgJKwxjhABrAQAAAA==.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwAQAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJbhw6HwBKAgABAAgJbhw6HwBKAgAEAAMJ+AWWcQB4AAAAAA==.',
Me='Mekkadorque:BAAALgADCgUJBQABLgAECgcJCAAQAAAAAA==.Merien:BAABLgAECn8jAAIBAAcJuwikiAAoAQABAAcJuwikiAAoAQAAAA==.Meros:BAABLgAECn8gAAIBAAYJ6gqZlgANAQABAAYJ6gqZlgANAQAAAA==.',
Mo='Monstrosoh:BAAALgAECgUJCQAAAA==.Moonstrudels:BAAALgAECgQJBQABLgAECgkJHgANADQVAA==.',
Mt='Mtdewmachine:BAAALgAECgIJAwAAAA==.',
Mu='Muertesdemon:BAAALgADCgUJBQAAAA==.Munstar:BAAALgADCgYJBgAAAA==.',
My='Mynxana:BAAALgADCgQJBAAAAA==.',
Na='Nafari:BAAALgAECgUJBgAAAA==.Narasil:BAAALgAECgEJAQAAAA==.Natea:BAAALgAECgcJDAAAAA==.',
Ne='Nebüla:BAABLgAECn8ZAAIRAAkJ+gybJQB+AQARAAkJ+gybJQB+AQAAAA==.Necrökush:BAAALgAFFAIJAgAAAA==.Nestro:BAAALgADCgUJBQAAAA==.',
Ni='Nightwinds:BAAALgAECgEJAgAAAA==.Ninajavin:BAAALgAECgUJBQAAAA==.',
No='Norinna:BAAALgAECggJEQABLgAFFAIJCAALAHoLAA==.Norlairas:BAAALgADCgUJBQAAAA==.',
Ny='Nyxxalecgos:BAACLgAFFH8GAAIIAAQJxwfIOwDUAAAIAAQJxwfIOwDUAAAuAAQKfyQAAggACAmiE8YbAOoBAAgACAmiE8YbAOoBAAEuAAUUBAkSAAkAWw8A.',
Od='Odiousego:BAACLgAFFH8NAAIKAAUJwwv5BQAeAQAKAAUJwwv5BQAeAQAuAAQKfx4AAgoACAmdGIEGABECAAoACAmdGIEGABECAAAA.',
Ol='Oldkrusty:BAAALgADCgMJAwAAAA==.',
On='Onyxfïend:BAAALgADCgMJAwAAAA==.',
Oo='Ooryl:BAAALgAECgEJAQAAAA==.',
Op='Opheliajavin:BAAALgAECgEJAQAAAA==.',
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAABLgAECn8hAAILAAkJNhYYNgA9AgALAAkJNhYYNgA9AgAAAA==.',
Pa='Painless:BAABLgAECn8YAAIZAAcJFg2bMwBHAQAZAAcJFg2bMwBHAQAAAA==.',
Ph='Phloemie:BAAALgADCgYJCQAAAA==.',
Po='Popeleo:BAAALgAECgEJAwAAAA==.Poronuma:BAAALgADCgEJAQAAAA==.Powerhøuse:BAACLgAFFH8cAAILAAgJUxw9DwBtAgALAAgJUxw9DwBtAgAuAAQKfycAAwsACAlgIp0YABcDAAsACAlgIp0YABcDAB8AAQkAAB0RAC4AAAAA.Powerwordhug:BAABLgAECn8tAAIeAAkJnx1tDACcAgAeAAkJnx1tDACcAgAAAA==.',
Pr='Proctolodin:BAACLgAFFH8GAAIGAAMJYAjGeAC9AAAGAAMJYAjGeAC9AAAuAAQKfyUAAgYACAlGFERiAKkBAAYACAlGFERiAKkBAAAA.',
Pu='Purplefart:BAABLgAECn8qAAMkAAkJfBQ8GwDqAQAkAAkJfBQ8GwDqAQAZAAIJshrYWACXAAAAAA==.',
Ql='Qlaryx:BAABLgAECn8dAAIBAAgJFhSuRQDMAQABAAgJFhSuRQDMAQAAAA==.',
Qu='Quinner:BAACLgAFFH8QAAIIAAQJcREqMQD7AAAIAAQJcREqMQD7AAAuAAQKfzUABAgACQneG8UNAIICAAgACQneG8UNAIICAAcABAm+BTo3ALIAAAkAAwlTC4IuAKUAAAAA.Qut:BAABLgAECn8cAAIMAAgJxh1nGgDBAQAMAAgJxh1nGgDBAQAAAA==.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Rark:BAAALgAECgEJAQAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAABLgAECn8eAAILAAYJRxyihQBoAQALAAYJRxyihQBoAQAAAA==.',
Ri='Rickle:BAAALgAECgMJAwAAAA==.Riptoe:BAAALgAECgcJCAAAAA==.',
Ro='Roantami:BAAALgADCgUJBQAAAA==.Rokey:BAAALgAFFAEJAgABLgAFFAMJCgALAMcfAA==.Rolling:BAAALgADCgMJAwAAAA==.Ronmaru:BAAALgAECgcJEAAAAA==.Rosejavin:BAAALgAECgEJAQAAAA==.Roxy:BAAALgAECgEJAQAAAA==.',
Ry='Ryujin:BAAALgAECgYJBgABLgAECgkJHgANADQVAA==.',
Sa='Sabel:BAAALgAECgMJAwAAAA==.Sagori:BAAALgAECgEJAgAAAA==.Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn84AAMdAAgJxxI9WwCLAQAdAAgJWRI9WwCLAQAKAAQJ9xIrFADtAAAAAA==.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAABLgAECn8kAAMlAAkJACGKBQAHAwAlAAkJACGKBQAHAwAVAAEJVQsSWgAfAAAAAA==.Seiken:BAAALgAECggJEgAAAA==.Selas:BAABLgAECn8hAAMCAAYJSBFHKgADAQACAAYJSBFHKgADAQAXAAYJkwkj2QDZAAAAAA==.Seryiana:BAAALgAECgYJEgAAAA==.',
Sg='Sgtkabukiman:BAAALgAECgYJDAABLgAECggJGAABAFAdAA==.',
Sh='Shackiechan:BAAALgAECgIJBAAAAA==.Shadowflood:BAAALgAECgMJBAAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBQABLgAECgIJBAAQAAAAAA==.',
Si='Silk:BAABLgAECn8iAAIBAAgJeRDsVACgAQABAAgJeRDsVACgAQAAAA==.Silren:BAAALgAECgQJCQAAAA==.Sita:BAAALgADCgkJDwAAAA==.',
Sk='Skoldsmoyer:BAAALgADCgUJBQAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAAALgAECgcJDgABLgAFFAMJBgAGAGAIAA==.',
So='Sofferenza:BAAALgADCgcJGwAAAA==.Sorulus:BAAALgAECgEJAgAAAA==.Souldance:BAABLgAECn8sAAMdAAkJcRZLKgAvAgAdAAkJcRZLKgAvAgAcAAMJQA6pMQBVAAAAAA==.',
Sp='Spaceguy:BAABLgAECn8kAAISAAkJuQi/PAA+AQASAAkJuQi/PAA+AQAAAA==.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgAECgEJAQABLgAECgkJLAARALEPAA==.Starwind:BAAALgAECgYJDAAAAA==.Stolock:BAAALgAECgMJAwABLgAECggJGgAmAOgZAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Sugammadex:BAAALgAECgIJBQABLgAECgIJBwAQAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAABLgAECn8WAAISAAkJsCHVBgDsAgASAAkJsCHVBgDsAgAAAA==.',
Sw='Swato:BAAALgAECgEJAQABLgAECggJEAAQAAAAAA==.',
Sy='Sylaang:BAAALgAECgIJAgAAAA==.',
Ta='Talie:BAAALgADCgYJBQAAAA==.Taliria:BAABLgAECn8eAAIkAAYJehhWJgClAQAkAAYJehhWJgClAQAAAA==.Talladar:BAAALgAECgUJCwAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Tampax:BAAALgAECgEJAQABLgAECgkJHgANADQVAA==.Targ:BAABLgAECn8YAAIBAAgJUB3ALgAdAgABAAgJUB3ALgAdAgAAAA==.',
Te='Tenshiro:BAAALgADCgYJDQAAAA==.Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgAECgYJBgAAAA==.Thundamon:BAAALgAECgEJAQAAAA==.',
Ti='Tidefang:BAAALgAECgcJDAABLgAECggJFgADAJUJAA==.',
To='Toblakai:BAAALgADCgUJBQABLgAECgkJAgAQAAAAAA==.Torryn:BAAALgADCgkJCQAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.Truthteiier:BAAALgAECgEJAwAAAA==.',
Ty='Tyladrillian:BAAALgAECgEJAQAAAA==.',
Un='Unholyguard:BAAALgADCgEJAQABLgAFFAYJHAAYABkPAA==.',
Uz='Uzumaki:BAABLgAECn8WAAIOAAgJGBYUGwDTAQAOAAgJGBYUGwDTAQAAAA==.',
Va='Vajrajavin:BAAALgAECgYJDwABLgAECggJKgAIANMPAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAACLgAFFH8cAAINAAcJYRVWDwAMAgANAAcJYRVWDwAMAgAuAAQKfyUAAg0ACQkhI9cDAHcDAA0ACQkhI9cDAHcDAAAA.Valasca:BAAALgADCgcJBwAAAA==.Valonar:BAAALgAECgUJCAAAAA==.Valonkyr:BAAALgADCgEJAQAAAA==.Valor:BAAALgAECggJEwAAAA==.Vardeath:BAAALgAECgMJAwAAAA==.',
Ve='Veldaan:BAAALgADCgkJFQAAAA==.',
Vi='Victra:BAAALgAECgUJBQABLgAECggJGAABAFAdAA==.Vinskey:BAAALgAECgUJBQAAAA==.Vipe:BAAALgAECggJEgAAAA==.Viperlock:BAAALgADCgYJCAAAAA==.Visenyaa:BAAALgADCgEJAQAAAA==.Vita:BAAALgAECgQJBAAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.Voodoochild:BAAALgAFFAIJAgAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECggJGAABAFAdAA==.',
Wa='Waltwitemane:BAAALgAECgEJAgAAAA==.Warliff:BAAALgADCgMJAwAAAA==.',
Wh='Whish:BAABLgAECn8aAAInAAcJnwhgbADtAAAnAAcJnwhgbADtAAAAAA==.Whiteleaf:BAABLgAECn8sAAIlAAkJZBEgIQDnAQAlAAkJZBEgIQDnAQAAAA==.',
Wi='Wisdom:BAAALgADCggJDQABLgAECggJEwAQAAAAAA==.',
Wt='Wtfishéaling:BAAALgAECgkJCwAAAA==.',
Xe='Xenonga:BAAALgADCgEJAQAAAA==.',
Ye='Yenneth:BAAALgAECgYJEAAAAA==.',
['Yî']='Yîn:BAAALgAECgkJCgAAAA==.',
Ze='Zeradias:BAAALgADCgYJBgAAAA==.',
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
