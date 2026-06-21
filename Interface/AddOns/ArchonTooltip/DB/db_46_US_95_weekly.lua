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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Rogue-Assassination','Paladin-Retribution','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warlock-Affliction','Mage-Frost','DemonHunter-Devourer','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','Shaman-Restoration','Unknown-Unknown','Monk-Brewmaster','Shaman-Elemental','DemonHunter-Havoc','Druid-Feral','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Paladin-Holy','Priest-Discipline','Shaman-Enhancement','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Priest-Holy','Mage-Fire','Mage-Arcane','Rogue-Outlaw','Druid-Balance','Priest-Shadow','Warrior-Fury','Paladin-Protection','Druid-Restoration',}
local provider = {region='US',realm='Fenris',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aayu:BAABLgAECn8vAAIBAAgJyxn9NwD+AQABAAgJyxn9NwD+AQAAAA==.',
Ad='Addie:BAEBLgAFFH8GAAICAAIJ4hZ2DgCDAAACAAIJ4hZ2DgCDAAABLgAFFAkJPQADAIAmAA==.Adranelidk:BAABLgAECn8kAAICAAYJ6hSqJAAuAQACAAYJ6hSqJAAuAQAAAA==.',
Ae='Aeromina:BAABLgAECn8cAAMBAAcJORTQfQBEAQABAAcJORTQfQBEAQAEAAEJZABYnAAKAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgABLgAECggJKAAFANcbAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIGAAgJAxpDNQBNAgAGAAgJAxpDNQBNAgAAAA==.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJDQAAAA==.Alphabet:BAAALgADCgMJBQAAAA==.Alypiia:BAAALgAECgIJAgAAAA==.',
Am='Amadori:BAAALgAECgEJAQAAAA==.',
An='Ancalagon:BAABLgAECn8jAAQHAAgJqCE1BADvAgAHAAgJqCE1BADvAgAIAAgJ2wvXPwAqAQAJAAEJRhbQPAA7AAAAAA==.Angelic:BAAALgAECgIJAgAAAA==.Anguish:BAAALgAECgUJCwAAAA==.Antia:BAAALgAECgQJBAABLgAFFAUJEAAKAMMLAA==.',
Ap='April:BAABLgAECn8bAAILAAkJXwW5+QC2AAALAAkJXwW5+QC2AAAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIEAAIJLxlYGwCqAAAEAAIJLxlYGwCqAAAuAAQKfx8AAgQACQm5IigDAHgDAAQACQm5IigDAHgDAAEuAAUUBAkGAAwAFh0A.',
As='Ashveil:BAABLgAECn8qAAIIAAgJ0w8SNwBTAQAIAAgJ0w8SNwBTAQAAAA==.Asray:BAAALgAECgMJBwABLgAFFAQJEgANABUeAA==.',
At='Athenã:BAAALgADCgEJAQAAAA==.',
Au='Aussiesauce:BAAALgAECgUJCgABLgAECgkJHgAOADQVAA==.Aussilicious:BAABLgAECn8eAAMOAAkJNBXbHAAxAgAOAAkJNBXbHAAxAgAPAAIJqAQdbwBVAAAAAA==.',
Az='Azerennia:BAABLgAECn8eAAILAAkJZQdPAwAhAQALAAkJZQdPAwAhAQAAAA==.Azerious:BAAALgAECgIJAwAAAA==.Azreya:BAAALgAECgEJAgAAAA==.Azrokke:BAABLgAECn8WAAIQAAkJwRmmGACEAgAQAAkJwRmmGACEAgAAAA==.',
Ba='Babetter:BAABLgAECn8uAAIBAAgJ9wbIgQA7AQABAAgJ9wbIgQA7AQAAAA==.Baby:BAAALgAECgYJBgAAAA==.Bacstabbe:BAAALgAECgEJAQAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAARAAAAAA==.Baelz:BAAALgAECgYJBQAAAA==.Bahamaut:BAAALgAECgQJBgABLgAECgkJHgAOADQVAA==.Balzan:BAAALgADCgYJBwAAAA==.',
Be='Beerless:BAABLgAECn8tAAISAAkJMhVXAADiAQASAAkJMhVXAADiAQAAAA==.Belphegör:BAAALgAECgYJDgAAAA==.Bencicil:BAAALgAECgcJDwAAAA==.Berkleyf:BAAALgADCgYJCQABLgAFFAMJBwATADIMAA==.Beydoon:BAAALgAECgMJBwAAAA==.',
Bl='Blindmagg:BAAALgAECgYJCAABLgAECggJGQABAJAeAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgcJCAABLgAECgcJDAARAAAAAA==.',
Br='Brain:BAAALgAECgEJAwAAAA==.Brawnhilda:BAAALgADCgcJDAABLgAECgkJJAABAMkYAA==.Brewdude:BAAALgADCgcJBwAAAA==.Brewmanchu:BAAALgADCggJCAABLgAECgcJCAARAAAAAA==.Bro:BAAALgAECgUJEQAAAA==.',
Bu='Bunky:BAAALgAECgMJBgABLgAFFAMJBwATADIMAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8fAAIUAAgJuSA1AgBJAgAUAAgJuSA1AgBJAgAuAAQKfygAAhQACQnuJcMBAIYDABQACQnuJcMBAIYDAAAA.Calayra:BAAALgADCgIJAgAAAA==.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8jAAQOAAgJKhgMKQDiAQAOAAcJDxoMKQDiAQASAAUJGQVXYADBAAAPAAEJ3A7HoQAuAAAAAA==.Cartheron:BAAALgAECgkJAgAAAA==.',
Ce='Cellynna:BAAALgADCggJFAAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgAAAA==.Crims:BAAALgADCgcJDgABLgADCgcJDgARAAAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECggJDwAAAA==.',
Cy='Cynla:BAAALgAECgMJAwAAAA==.',
['Cí']='Círce:BAEALgAECgIJAgABLgAFFAQJEgASABAfAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.Darremiah:BAAALgADCgEJAQAAAA==.David:BAACLgAFFH8HAAILAAMJfgoWiADJAAALAAMJfgoWiADJAAAuAAQKfygAAgsACQlKHTInAH4CAAsACQlKHTInAH4CAAAA.',
Db='Dbsheep:BAAALgAECgMJBQAAAA==.',
De='Deezhealz:BAAALgAECgYJDAAAAA==.Dezal:BAAALgADCgIJAgAAAA==.',
Di='Diddyfisting:BAACLgAFFH8bAAIPAAUJwCXxBgCnAQAPAAUJwCXxBgCnAQAuAAQKfzAAAw8ACQneI5oGAOECAA8ACQneI5oGAOECABIAAQk6A4mPACYAAAAA.Divinefistin:BAECLgAFFH8SAAISAAQJEB/rFgBrAQASAAQJEB/rFgBrAQAuAAQKfzgAAxIACQnCIi0NAGQCABIACQnLHS0NAGQCAA8ABwlYIr4RADUCAAAA.Divinepain:BAEALgAECgMJAwABLgAFFAQJEgASABAfAA==.',
Dn='Dnova:BAAALgAECgMJBAAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCwAAAA==.Dornadions:BAAALgAECgYJDgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAABLgAECn8WAAMHAAkJgg6HFACCAQAHAAkJgg6HFACCAQAIAAYJJg7JTQD2AAAAAA==.Draka:BAABLgAECn8VAAIVAAkJaA6SEgCSAQAVAAkJaA6SEgCSAQAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Dreadtide:BAAALgADCgUJBgAAAA==.Drunk:BAAALgAECgcJDAAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJCAAAAA==.',
Dy='Dymetra:BAAALgAECgEJAQAAAA==.',
['Dö']='Döritö:BAAALgAECgYJEAAAAA==.',
Ec='Ecks:BAACLgAFFH8RAAIWAAcJGxqfCgCGAQAWAAcJGxqfCgCGAQAuAAQKfzMAAxYACQl8HswCADgDABYACQl8HswCADgDABcAAQkAAA2QAAAAAAAA.',
El='Elfuego:BAAALgAECggJDQAAAA==.',
Em='Employee:BAAALgAECgcJCwAAAA==.',
En='Energgy:BAAALgAECgkJCgAAAA==.Enigmanta:BAAALgADCgUJBQAAAA==.',
Ev='Eviljoke:BAAALgADCgkJDwAAAA==.',
Fa='Faeda:BAAALgAECgUJCAAAAA==.Faestaul:BAABLgAECn8gAAIGAAgJjBmmQAAFAgAGAAgJjBmmQAAFAgAAAA==.Fatima:BAAALgAECgEJAgAAAA==.',
Fe='Fearyourface:BAAALgADCgMJAwAAAA==.Fenrisulfr:BAAALgADCgYJBgAAAA==.Fentdemon:BAAALgAFFAMJBAAAAA==.',
Fi='Findinnan:BAABLgAECn8aAAIFAAkJeQVODQBVAQAFAAkJeQVODQBVAQAAAA==.Fishtotem:BAAALgADCgcJDQAAAA==.',
Fl='Flor:BAAALgAECgEJAQAAAA==.',
Fr='Freeze:BAAALgAECgYJCQAAAA==.Freezerbern:BAAALgAECggJDwAAAA==.Frissbee:BAAALgADCgMJAwABLgAECgMJAwARAAAAAA==.Frostblood:BAAALgADCgIJAgAAAA==.Froststd:BAAALgADCgEJAQAAAA==.Fréki:BAAALgAECgIJAgAAAA==.',
Fu='Fullpeny:BAAALgADCgEJAQAAAA==.',
Ga='Gametheory:BAAALgAECgIJBwAAAA==.Ganzar:BAACLgAFFH8TAAIYAAMJwySxXAA6AQAYAAMJwySxXAA6AQAuAAQKfycAAhgACQmnInoIAC4DABgACQmnInoIAC4DAAAA.Gathan:BAAALgADCgcJHAAAAA==.',
Ge='Genderdruid:BAAALgAECgIJAwAAAA==.Genge:BAABLgAECn84AAMGAAgJERPjagCZAQAGAAgJERPjagCZAQAZAAEJIQPokwArAAAAAA==.Gertrex:BAABLgAECn8jAAIaAAkJzQvkAABwAQAaAAkJzQvkAABwAQAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.Gitchusum:BAAALgAECgcJBgAAAA==.',
Gl='Glennhelen:BAAALgADCgkJDwAAAA==.',
Go='Goatlord:BAABLgAECn8eAAIbAAkJMw86EACuAQAbAAkJMw86EACuAQAAAA==.Goatsavior:BAAALgAECgUJDgAAAA==.Goblinsrhot:BAAALgADCgkJDwAAAA==.Gotharm:BAABLgAECn8bAAIcAAkJswy+GADaAQAcAAkJswy+GADaAQAAAA==.',
Gr='Grester:BAAALgAECggJEwAAAA==.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAABLgAECn8cAAIBAAYJHB/wTQC4AQABAAYJHB/wTQC4AQAAAA==.',
Ha='Hahmicydal:BAABLgAECn8fAAQdAAcJ8giDIACpAAAKAAcJEgadHQDSAAAdAAYJTAiDIACpAAAeAAIJHwJvOQE2AAAAAA==.Hal:BAAALgAECgYJEQAAAA==.Hardcore:BAAALgADCgUJBQAAAA==.Havökush:BAACLgAFFH8JAAIUAAMJIRAoGwDJAAAUAAMJIRAoGwDJAAAuAAQKfycAAhQACQmBIfsEAPUCABQACQmBIfsEAPUCAAAA.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgAECgEJAgABLgAECgkJDAARAAAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAIaAAcJmw23NQA+AQAaAAcJmw23NQA+AQAAAA==.Holyguard:BAACLgAFFH8cAAIZAAYJGQ9cEwCUAQAZAAYJGQ9cEwCUAQAuAAQKfywAAhkACQkqF5gbACcCABkACQkqF5gbACcCAAAA.Holyhand:BAABLgAECn8UAAIfAAYJAg4DSQAVAQAfAAYJAg4DSQAVAQABLgAFFAYJHAAZABkPAA==.',
Ic='Ickis:BAAALgAECgYJBgABLgAECggJGQABAJAeAA==.',
Il='Ilin:BAAALgAECggJEAAAAA==.Illidres:BAAALgADCgQJBQAAAA==.Ilou:BAAALgAECgYJBgABLgAFFAUJEAAKAMMLAA==.',
In='Influenza:BAAALgAECgMJAwAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAABLgAECn8yAAIgAAkJzxejAgAjAgAgAAkJzxejAgAjAgAAAA==.',
Is='Isabela:BAABLgAFFH8IAAIMAAIJsyQdZADGAAAMAAIJsyQdZADGAAAAAA==.Isilian:BAAALgADCgUJCAAAAA==.',
Iw='Iwillpull:BAAALgADCgcJAQAAAA==.',
Iy='Iyora:BAAALgADCgUJBQAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgYJCAABLgAFFAUJGwAPAMAlAA==.Judyhopp:BAABLgAECn8aAAQhAAgJWhYxCAB2AQAhAAcJsBIxCAB2AQALAAcJFxONqQAsAQAgAAEJAADfGAAAAAABLgAFFAUJGwAPAMAlAA==.Judyhopps:BAAALgAFFAIJAgABLgAFFAUJGwAPAMAlAA==.Judyhoppsimp:BAAALgAFFAIJBAAAAA==.',
Ka='Kaeln:BAAALgAFFAMJAwABLgAFFAUJEAAhAMYdAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kagronn:BAAALgADCggJCgAAAA==.Kakez:BAAALgAECgEJAQABLgAFFAgJJAAfANwXAA==.Kaluanights:BAAALgAECgEJAQAAAA==.Kalzak:BAABLgAECn8tAAIVAAkJzRFrAABkAQAVAAkJzRFrAABkAQAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAABLgAECn8ZAAIeAAYJ2wYAvwDNAAAeAAYJ2wYAvwDNAAAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kithiandra:BAAALgADCgIJAgAAAA==.Kiwistunna:BAAALgAECgYJDAABLgAECgkJHAATAOYRAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAABLgAECn8oAAIiAAkJpQ8pAABFAQAiAAkJpQ8pAABFAQAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAARAAAAAA==.',
['Kï']='Kïtana:BAAALgAECgMJBAAAAA==.',
La='Laddyboy:BAAALgADCgMJAwAAAA==.Ladiemacbeth:BAAALgADCgkJDwABLgAECgkJLQAVAM0RAA==.Lanwynne:BAAALgADCgYJBAABLgAECgkJJAABAMkYAA==.Laxion:BAAALgADCgkJGwAAAA==.',
Le='Leafs:BAAALgAECgEJAQAAAA==.Leggo:BAABLgAECn8dAAIZAAYJfhFfPgBLAQAZAAYJfhFfPgBLAQAAAA==.',
Li='Lidravos:BAAALgAECgEJAQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilfist:BAAALgAECgUJBQAAAA==.Lilia:BAACLgAFFH8KAAIGAAMJPwV7hgCmAAAGAAMJPwV7hgCmAAAuAAQKfyEAAwYACAlYHCQqAHwCAAYACAlYHCQqAHwCABkABAnYAX16AI8AAAAA.Lilmorty:BAAALgAECgYJDgABLgAFFAcJGwAEAAcYAA==.',
Ll='Lluvioso:BAACLgAFFH8NAAMYAAMJ4h9hjADxAAAYAAMJFB9hjADxAAACAAEJ/iE6OQBRAAAuAAQKfyMAAwIACQnrI1oCAEwDAAIACQlNI1oCAEwDABgAAQkOHyhMAVQAAAAA.',
Lo='Loaf:BAABLgAECn8YAAILAAYJeR3TZQCyAQALAAYJeR3TZQCyAQAAAA==.Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8fAAIjAAcJeByZIgC0AQAjAAcJeByZIgC0AQAAAA==.',
Lu='Lunarbelle:BAAALgADCgkJDwAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAABLgAECn8gAAILAAgJKwxphgBqAQALAAgJKwxphgBqAQAAAA==.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwARAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJbhw6HwBKAgABAAgJbhw6HwBKAgAEAAMJ+AWWcQB4AAAAAA==.',
Me='Mekkadorque:BAAALgADCgUJBQABLgAECgcJCAARAAAAAA==.Merien:BAABLgAECn8lAAIBAAcJuwg/iwAoAQABAAcJuwg/iwAoAQAAAA==.Meros:BAABLgAECn8kAAIBAAYJewtNBwCcAAABAAYJewtNBwCcAAAAAA==.',
Mi='Minathiel:BAAALgADCgIJAgAAAA==.',
Mo='Monstrosoh:BAAALgAECgUJCQAAAA==.Moonkins:BAAALgAECgEJAQABLgAECgMJAwARAAAAAA==.Moonstrudels:BAAALgAECgQJBQABLgAECgkJHgAOADQVAA==.',
Mt='Mtdewmachine:BAAALgAECgIJAwAAAA==.',
Mu='Muertesdemon:BAAALgADCgUJBQAAAA==.Munstar:BAAALgADCgYJBgAAAA==.',
Na='Nafari:BAAALgAECgUJBgAAAA==.Narasil:BAAALgAECgEJAQAAAA==.Natea:BAAALgAECgcJDAAAAA==.Nayrb:BAAALgAECgEJAQABLgAECgkJDAARAAAAAA==.',
Ne='Nebüla:BAABLgAECn8ZAAISAAkJ+gz9JQB+AQASAAkJ+gz9JQB+AQAAAA==.Necrökush:BAAALgAFFAIJAgAAAA==.Nestro:BAAALgADCgUJBQAAAA==.',
Ni='Nightwinds:BAAALgAECgEJAgAAAA==.Ninajavin:BAAALgAECgUJBQAAAA==.',
No='Norinna:BAAALgAECggJEQABLgAFFAIJCAALAHoLAA==.Norlairas:BAAALgADCgUJBQAAAA==.Notsujan:BAAALgADCgYJBgAAAA==.',
Ny='Nyxxalecgos:BAACLgAFFH8GAAIIAAQJxwcTPgDPAAAIAAQJxwcTPgDPAAAuAAQKfyQAAggACAmiE8YbAOoBAAgACAmiE8YbAOoBAAEuAAUUBQkUAAkAWw8A.',
Od='Odiousego:BAACLgAFFH8QAAIKAAUJwwtKBgAcAQAKAAUJwwtKBgAcAQAuAAQKfyMAAgoACAlFGlwFADQCAAoACAlFGlwFADQCAAAA.',
Ol='Oldkrusty:BAAALgADCgMJAwAAAA==.',
On='Onyxfïend:BAAALgADCgMJAwAAAA==.',
Oo='Ooryl:BAAALgAECgEJAQAAAA==.',
Op='Opheliajavin:BAAALgAECgEJAQAAAA==.',
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAABLgAECn8hAAILAAkJNhYENwA8AgALAAkJNhYENwA8AgAAAA==.',
Pa='Painless:BAABLgAECn8YAAIaAAcJFg0dNQBBAQAaAAcJFg0dNQBBAQAAAA==.',
Ph='Phloemie:BAAALgADCgYJCQAAAA==.',
Po='Popeleo:BAAALgAECgEJAwAAAA==.Poronuma:BAAALgADCgEJAQAAAA==.Powerhøuse:BAACLgAFFH8cAAILAAgJUxwQEQBkAgALAAgJUxwQEQBkAgAuAAQKfycAAwsACAlgIp0YABcDAAsACAlgIp0YABcDACAAAQkAAB0RAC4AAAAA.Powerwordhug:BAABLgAECn8tAAIfAAkJnx2zDACbAgAfAAkJnx2zDACbAgAAAA==.',
Pr='Proctolodin:BAACLgAFFH8JAAIGAAMJbgs/dgDIAAAGAAMJbgs/dgDIAAAuAAQKfyoAAgYACAmHFENhAK4BAAYACAmHFENhAK4BAAAA.',
Pu='Purplefart:BAABLgAECn8qAAMkAAkJfBQPHADkAQAkAAkJfBQPHADkAQAaAAIJshr9WQCYAAAAAA==.',
Ql='Qlaryx:BAABLgAECn8kAAIBAAgJyRi1AQCkAQABAAgJyRi1AQCkAQAAAA==.',
Qu='Quinner:BAACLgAFFH8RAAIIAAQJcRFmMwD0AAAIAAQJcRFmMwD0AAAuAAQKfzUABAgACQneG/oNAIECAAgACQneG/oNAIECAAcABAm+BTo3ALIAAAkAAwlTC4IuAKUAAAAA.Qut:BAABLgAECn8cAAINAAgJxh3VGgDBAQANAAgJxh3VGgDBAQAAAA==.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Rark:BAAALgAECgEJAQAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAABLgAECn8eAAILAAYJRxxlhwBoAQALAAYJRxxlhwBoAQAAAA==.Restore:BAAALgAECgMJAwAAAA==.',
Ri='Rickle:BAAALgAECgMJAwAAAA==.Riptoe:BAAALgAECgcJCAAAAA==.',
Ro='Roantami:BAAALgADCgUJBQAAAA==.Rokey:BAAALgAFFAEJAgABLgAFFAMJCgALAMcfAA==.Rolling:BAAALgADCgMJAwAAAA==.Ronmaru:BAAALgAECgcJEAAAAA==.Rosejavin:BAAALgAECgEJAQAAAA==.Roxy:BAAALgAECgEJAQAAAA==.',
Ry='Ryujin:BAAALgAECgYJBgABLgAECgkJHgAOADQVAA==.',
Sa='Sabel:BAAALgAECgMJAwAAAA==.Sagori:BAAALgAECgEJAgAAAA==.Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn84AAMeAAgJxxLlWwCKAQAeAAgJWRLlWwCKAQAKAAQJ9xIrFADtAAAAAA==.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAABLgAECn8sAAMlAAkJCyG8BQAEAwAlAAkJCyG8BQAEAwAWAAMJJxNEAQDHAAAAAA==.Seiken:BAAALgAECggJEgAAAA==.Selas:BAABLgAECn8hAAMCAAYJSBH9KgABAQACAAYJSBH9KgABAQAYAAYJkwkc3QDYAAAAAA==.Seryiana:BAAALgAECgYJEgAAAA==.',
Sg='Sgtkabukiman:BAAALgAECgYJDAABLgAECggJGQABAJAeAA==.',
Sh='Shackiechan:BAAALgAECgIJBAAAAA==.Shadowflood:BAAALgAECgMJBAAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBQABLgAECgIJBAARAAAAAA==.',
Si='Silk:BAABLgAECn8iAAIBAAgJeRDVVgCfAQABAAgJeRDVVgCfAQAAAA==.Silren:BAAALgAECgQJCQAAAA==.Sita:BAAALgADCgkJDwAAAA==.',
Sk='Skoldsmoyer:BAAALgADCgUJBQAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAABLgAECn8VAAILAAkJ2RCXAQChAQALAAkJ2RCXAQChAQABLgAFFAMJCQAGAG4LAA==.',
So='Sofferenza:BAAALgADCgcJGwAAAA==.Sorulus:BAAALgAECgEJAgAAAA==.Souldance:BAABLgAECn8xAAMeAAkJVhg2IgBZAgAeAAkJVhg2IgBZAgAdAAMJQA6sMgBUAAAAAA==.',
Sp='Spaceguy:BAABLgAECn8kAAITAAkJuQjkPQA9AQATAAkJuQjkPQA9AQAAAA==.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgAFFAEJAQABLgAECgkJLAASALEPAA==.Starwind:BAAALgAECgYJDAAAAA==.Stolock:BAAALgAECgMJAwABLgAECggJGgAmAOgZAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Sugammadex:BAAALgAECgIJBQABLgAECgIJBwARAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAABLgAECn8eAAMTAAkJ/yEYBwDrAgATAAkJ/yEYBwDrAgAQAAEJtw/ICAA/AAAAAA==.',
Sw='Swato:BAAALgAECgEJAQABLgAECggJEAARAAAAAA==.',
Sy='Sylaang:BAAALgAECgIJAwAAAA==.',
Ta='Talie:BAAALgADCgYJBQAAAA==.Taliria:BAABLgAECn8eAAIkAAYJehhWJgClAQAkAAYJehhWJgClAQAAAA==.Talladar:BAAALgAECgYJEAAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Tampax:BAAALgAECgUJBQABLgAECgkJHgAOADQVAA==.Targ:BAABLgAECn8ZAAIBAAgJkB73LwAcAgABAAgJkB73LwAcAgAAAA==.',
Te='Tenshiro:BAAALgADCgYJDQAAAA==.Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgAECgYJBgAAAA==.Thugzug:BAAALgADCggJCAAAAA==.Thundamon:BAAALgAECgEJAQAAAA==.',
Ti='Tidefang:BAAALgAFFAEJAQAAAA==.',
To='Toblakai:BAAALgAECgIJAQABLgAECgkJAgARAAAAAA==.Torryn:BAAALgADCgkJCQAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.Truthteiier:BAAALgAECgEJAwAAAA==.',
Ty='Tyladrillian:BAAALgAECgEJAQAAAA==.',
Un='Unholyguard:BAAALgADCgEJAQABLgAFFAYJHAAZABkPAA==.',
Uz='Uzumaki:BAABLgAECn8WAAIPAAgJGBaiGwDTAQAPAAgJGBaiGwDTAQAAAA==.',
Va='Vajrajavin:BAAALgAECgYJDwABLgAECggJKgAIANMPAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAACLgAFFH8dAAIOAAgJ2hWXCgBeAgAOAAgJ2hWXCgBeAgAuAAQKfyUAAg4ACQkhI/IDAHcDAA4ACQkhI/IDAHcDAAAA.Valasca:BAAALgADCgcJBwAAAA==.Valonar:BAAALgAECgUJCAAAAA==.Valonkyr:BAAALgAECgEJAQAAAA==.Valor:BAAALgAECggJEwAAAA==.Vardeath:BAAALgAECgMJAwAAAA==.',
Ve='Veldaan:BAAALgADCgkJGwAAAA==.',
Vi='Victra:BAAALgAECgUJBQABLgAECggJGQABAJAeAA==.Vinskey:BAAALgAECgUJBQAAAA==.Vipe:BAAALgAECggJEwAAAA==.Viperlock:BAAALgADCgYJCAAAAA==.Visenyaa:BAAALgADCgEJAQAAAA==.Vita:BAAALgAECgQJBAAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.Voodoochild:BAAALgAFFAIJAgAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECggJGQABAJAeAA==.',
Wa='Waltwitemane:BAAALgAECgEJAwAAAA==.Warliff:BAAALgADCgMJAwAAAA==.',
Wh='Whish:BAABLgAECn8bAAInAAcJFgowbQDtAAAnAAcJFgowbQDtAAAAAA==.Whiteleaf:BAABLgAECn8yAAIlAAkJJxK9IADrAQAlAAkJJxK9IADrAQAAAA==.',
Wi='Wisdom:BAAALgADCggJDQABLgAECggJEwARAAAAAA==.',
Wt='Wtfishéaling:BAAALgAECgkJDAAAAA==.',
Xe='Xenonga:BAAALgADCgEJAQAAAA==.',
Ye='Yenneth:BAAALgAECgYJEAAAAA==.',
['Yî']='Yîn:BAAALgAECgkJDgAAAA==.',
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
