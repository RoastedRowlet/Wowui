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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Rogue-Assassination','Paladin-Retribution','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warlock-Affliction','Mage-Frost','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','Unknown-Unknown','Monk-Brewmaster','Shaman-Elemental','DemonHunter-Havoc','Druid-Feral','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Paladin-Holy','Priest-Discipline','Shaman-Enhancement','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Priest-Holy','Mage-Fire','DemonHunter-Devourer','Mage-Arcane','Rogue-Outlaw','Druid-Balance','Priest-Shadow','Warrior-Fury','Paladin-Protection','Druid-Restoration',}
local provider = {region='US',realm='Fenris',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aayu:BAABLgAECn8vAAIBAAgJyxmgMgAHAgABAAgJyxmgMgAHAgAAAA==.',
Ad='Addie:BAEBLgAFFH8GAAICAAIJ4hZ2DgCDAAACAAIJ4hZ2DgCDAAABLgAFFAkJMgADAJ4lAA==.Adranelidk:BAABLgAECn8aAAICAAYJnxJlJgAVAQACAAYJnxJlJgAVAQAAAA==.',
Ae='Aeromina:BAABLgAECn8cAAMBAAcJORSEdABKAQABAAcJORSEdABKAQAEAAEJZABYnAAKAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgABLgAECggJKAAFANcbAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIGAAgJAxpDNQBNAgAGAAgJAxpDNQBNAgAAAA==.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJDQAAAA==.Alphabet:BAAALgADCgMJBQAAAA==.Alypiia:BAAALgAECgIJAgAAAA==.',
Am='Amadori:BAAALgAECgEJAQAAAA==.',
An='Ancalagon:BAABLgAECn8hAAQHAAgJgiAtBADmAgAHAAgJgiAtBADmAgAIAAgJ2wuvOwAxAQAJAAEJRhbQPAA7AAAAAA==.Angelic:BAAALgAECgIJAgAAAA==.Anguish:BAAALgAECgUJBwAAAA==.Antia:BAAALgAECgQJBAABLgAFFAQJCAAKAHwGAA==.',
Ap='April:BAABLgAECn8bAAILAAkJXwU07gC+AAALAAkJXwU07gC+AAAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIEAAIJLxlYGwCqAAAEAAIJLxlYGwCqAAAuAAQKfx8AAgQACQm5IigDAHgDAAQACQm5IigDAHgDAAAA.',
As='Ashveil:BAABLgAECn8qAAIIAAgJ0w98MwBbAQAIAAgJ0w98MwBbAQAAAA==.Asray:BAAALgAECgMJBwABLgAFFAQJEgAMABUeAA==.',
At='Athenã:BAAALgADCgEJAQAAAA==.',
Au='Aussiesauce:BAAALgAECgUJBQABLgAECggJGgANADcVAA==.Aussilicious:BAABLgAECn8aAAMNAAgJNxWiIwDuAQANAAgJNxWiIwDuAQAOAAIJqAQdbwBVAAAAAA==.',
Az='Azerennia:BAAALgAECgcJDwAAAA==.Azerious:BAAALgAECgIJAgAAAA==.Azreya:BAAALgAECgEJAgAAAA==.Azrokke:BAAALgAECgkJEQAAAA==.',
Ba='Babetter:BAABLgAECn8sAAIBAAgJRQYvgAAxAQABAAgJRQYvgAAxAQAAAA==.Baby:BAAALgAECgYJBgAAAA==.Bacstabbe:BAAALgAECgEJAQAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAAPAAAAAA==.Bahamaut:BAAALgAECgQJBgABLgAECggJGgANADcVAA==.Balzan:BAAALgADCgYJBwAAAA==.',
Be='Beerless:BAABLgAECn8eAAIQAAgJvhHWJAB9AQAQAAgJvhHWJAB9AQAAAA==.Belphegör:BAAALgAECgYJDgAAAA==.Bencicil:BAAALgAECgcJDwAAAA==.Berkleyf:BAAALgADCgYJCQABLgAFFAMJBwARADIMAA==.Beydoon:BAAALgAECgMJBgAAAA==.',
Bl='Blindmagg:BAAALgAECgYJCAABLgAECggJFwABAFAdAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgcJCAABLgAECgcJDAAPAAAAAA==.',
Br='Brain:BAAALgAECgEJAwAAAA==.Brawnhilda:BAAALgADCgcJDAABLgAECggJFgABAO0TAA==.Brewdude:BAAALgADCgcJBwAAAA==.Brewmanchu:BAAALgADCggJCAABLgAECgcJCAAPAAAAAA==.Bro:BAAALgAECgUJDgAAAA==.',
Bu='Bunky:BAAALgAECgMJBgABLgAFFAMJBwARADIMAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8eAAISAAcJjSRoAQBaAgASAAcJjSRoAQBaAgAuAAQKfygAAhIACQnuJcMBAIYDABIACQnuJcMBAIYDAAAA.Calayra:BAAALgADCgIJAgAAAA==.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8jAAQNAAgJKhhlJQDiAQANAAcJDxplJQDiAQAQAAUJGQVXYADBAAAOAAEJ3A5zlwAuAAAAAA==.Cartheron:BAAALgAECgkJAgAAAA==.',
Ce='Cellynna:BAAALgADCggJFAAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgAAAA==.Crims:BAAALgADCgcJDgABLgADCgcJDgAPAAAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECggJDwAAAA==.',
Cy='Cynla:BAAALgAECgMJAwAAAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.Darremiah:BAAALgADCgEJAQAAAA==.David:BAABLgAECn8oAAILAAkJSh2VJACDAgALAAkJSh2VJACDAgAAAA==.',
Db='Dbsheep:BAAALgAECgMJBQAAAA==.',
De='Deezhealz:BAAALgAECgYJDAAAAA==.Dezal:BAAALgADCgIJAgAAAA==.',
Di='Diddyfisting:BAACLgAFFH8aAAIOAAUJwCWEBQCwAQAOAAUJwCWEBQCwAQAuAAQKfzAAAw4ACQneI/8FAOUCAA4ACQneI/8FAOUCABAAAQk6A4mPACYAAAAA.Divinefistin:BAECLgAFFH8OAAIQAAQJxR4RFABtAQAQAAQJxR4RFABtAQAuAAQKfzcAAxAACQmMImgMAGcCABAACQnLHWgMAGcCAA4ABwkPIoIRACwCAAAA.Divinepain:BAEALgAECgMJAwABLgAFFAQJDgAQAMUeAA==.',
Dn='Dnova:BAAALgAECgMJBAAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCwAAAA==.Dornadions:BAAALgAECgYJDgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAAALgAECggJDQAAAA==.Draka:BAABLgAECn8UAAITAAgJXg4YFQBhAQATAAgJXg4YFQBhAQAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Drunk:BAAALgAECgcJDAAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJCAAAAA==.',
Ec='Ecks:BAACLgAFFH8QAAIUAAYJ6RsgDABWAQAUAAYJ6RsgDABWAQAuAAQKfzMAAxQACQl8HswCADgDABQACQl8HswCADgDABUAAQkAAIyFAAAAAAAA.',
El='Elfuego:BAAALgAECgcJDAAAAA==.',
Em='Employee:BAAALgAECgcJCwAAAA==.',
En='Energgy:BAAALgAECgkJCgAAAA==.Enigmanta:BAAALgADCgUJBQAAAA==.',
Er='Erodorina:BAAALgAECgMJBQAAAA==.',
Ev='Eviljoke:BAAALgADCgkJDwAAAA==.',
Fa='Faeda:BAAALgAECgUJCAAAAA==.Faestaul:BAABLgAECn8fAAIGAAgJtxaBSwDaAQAGAAgJtxaBSwDaAQAAAA==.Fatima:BAAALgAECgEJAgAAAA==.',
Fe='Fearyourface:BAAALgADCgMJAwAAAA==.Fenrisulfr:BAAALgADCgYJBgAAAA==.Fentdemon:BAAALgAFFAIJAwAAAA==.',
Fi='Findinnan:BAABLgAECn8ZAAIFAAgJJgXEDwAeAQAFAAgJJgXEDwAeAQAAAA==.Fishtotem:BAAALgADCgcJDQAAAA==.',
Fl='Flor:BAAALgAECgEJAQAAAA==.',
Fr='Freeze:BAAALgAECgYJCQAAAA==.Freezerbern:BAAALgAECggJDwAAAA==.Frissbee:BAAALgADCgMJAwABLgAECgMJAwAPAAAAAA==.Frostblood:BAAALgADCgIJAgAAAA==.Froststd:BAAALgADCgEJAQAAAA==.Fréki:BAAALgAECgIJAgAAAA==.',
Fu='Fullpeny:BAAALgADCgEJAQAAAA==.',
Ga='Gametheory:BAAALgAECgIJBwAAAA==.Ganzar:BAACLgAFFH8QAAIWAAMJwyQyUABCAQAWAAMJwyQyUABCAQAuAAQKfyYAAhYACQlPIHoMAAIDABYACQlPIHoMAAIDAAAA.Gathan:BAAALgADCgcJFgAAAA==.',
Ge='Genderdruid:BAAALgAECgEJAQAAAA==.Genge:BAABLgAECn83AAMGAAgJCxPTYwCdAQAGAAgJCxPTYwCdAQAXAAEJIQMLjgArAAAAAA==.Gertrex:BAABLgAECn8ZAAIYAAgJmQsLKwBvAQAYAAgJmQsLKwBvAQAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.Gitchusum:BAAALgAECgcJBgAAAA==.',
Gl='Glennhelen:BAAALgADCgkJDwAAAA==.',
Go='Goatlord:BAABLgAECn8eAAIZAAkJMw8ZDwCyAQAZAAkJMw8ZDwCyAQAAAA==.Goatsavior:BAAALgAECgUJDgAAAA==.Goblinsrhot:BAAALgADCgkJDwAAAA==.Gotharm:BAABLgAECn8bAAIaAAkJswwYFwDmAQAaAAkJswwYFwDmAQAAAA==.',
Gr='Grester:BAAALgAECggJEwAAAA==.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAABLgAECn8ZAAIBAAYJMh6nTACwAQABAAYJMh6nTACwAQAAAA==.',
Ha='Hahmicydal:BAABLgAECn8ZAAQbAAcJ9wc4IACgAAAKAAcJEgYZGwDUAAAbAAYJXwY4IACgAAAcAAEJ5gHJVwEWAAAAAA==.Hal:BAAALgAECgMJBQAAAA==.Hardcore:BAAALgADCgUJBQAAAA==.Havökush:BAACLgAFFH8JAAISAAMJIRCXFwDJAAASAAMJIRCXFwDJAAAuAAQKfyQAAhIACQmyH+YFANACABIACQmyH+YFANACAAAA.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgAECgEJAgAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAIYAAcJmw1eMQBIAQAYAAcJmw1eMQBIAQAAAA==.Holyguard:BAACLgAFFH8WAAIXAAYJFwomFgBpAQAXAAYJFwomFgBpAQAuAAQKfywAAhcACQkqFxEaACkCABcACQkqFxEaACkCAAAA.Holyhand:BAABLgAECn8UAAIdAAYJAg4DSQAVAQAdAAYJAg4DSQAVAQABLgAFFAYJFgAXABcKAA==.',
Ic='Ickis:BAAALgAECgYJBgABLgAECggJFwABAFAdAA==.',
Il='Ilin:BAAALgAECggJDwAAAA==.Illidres:BAAALgADCgQJBQAAAA==.',
In='Influenza:BAAALgAECgMJAwAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAABLgAECn8yAAIeAAkJzxdTAgAoAgAeAAkJzxdTAgAoAgAAAA==.',
Is='Isabela:BAABLgAFFH8IAAIfAAIJsySfWgDLAAAfAAIJsySfWgDLAAAAAA==.Isharadai:BAAALgADCgMJAwAAAA==.Isilian:BAAALgADCgUJCAAAAA==.',
Iw='Iwillpull:BAAALgADCgcJAQAAAA==.',
Iy='Iyora:BAAALgADCgUJBQAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgYJCAABLgAFFAUJGgAOAMAlAA==.Judyhopp:BAABLgAECn8aAAQgAAgJWhYxCAB2AQAgAAcJsBIxCAB2AQALAAcJFxMepAAvAQAeAAEJAABSFgAAAAABLgAFFAUJGgAOAMAlAA==.Judyhopps:BAAALgAECgYJDAABLgAFFAUJGgAOAMAlAA==.Judyhoppsimp:BAAALgAFFAEJAgAAAA==.',
Ka='Kaeln:BAAALgAFFAMJAwABLgAFFAUJDQAgAPkXAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kagronn:BAAALgADCggJCgAAAA==.Kakez:BAAALgAECgEJAQABLgAFFAcJIgAdAF8aAA==.Kaluanights:BAAALgAECgEJAQAAAA==.Kalzak:BAABLgAECn8eAAITAAgJ3g1CFwBHAQATAAgJ3g1CFwBHAQAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAABLgAECn8ZAAIcAAYJ2wabtwDTAAAcAAYJ2wabtwDTAAAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kithiandra:BAAALgADCgIJAgAAAA==.Kiwistunna:BAAALgAECgYJDAABLgAECgkJHAARAOYRAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAABLgAECn8ZAAIhAAgJUwpLDABFAQAhAAgJUwpLDABFAQAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAAPAAAAAA==.',
['Kï']='Kïtana:BAAALgAECgMJBAAAAA==.',
La='Ladiemacbeth:BAAALgADCgkJDwABLgAECggJHgATAN4NAA==.Lanwynne:BAAALgADCgYJBAABLgAECggJFgABAO0TAA==.Laxion:BAAALgADCgkJGwAAAA==.',
Le='Leafs:BAAALgAECgEJAQAAAA==.Leggo:BAABLgAECn8ZAAIXAAYJehFlOwBPAQAXAAYJehFlOwBPAQAAAA==.',
Li='Lidravos:BAAALgAECgEJAQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilia:BAACLgAFFH8KAAIGAAMJPwXNdwCpAAAGAAMJPwXNdwCpAAAuAAQKfyEAAwYACAlYHCQqAHwCAAYACAlYHCQqAHwCABcABAnYAX16AI8AAAAA.Lilmorty:BAAALgAECgYJDgABLgAFFAcJFwAEAN0XAA==.',
Ll='Lluvioso:BAACLgAFFH8NAAMWAAMJ4h8CfAD8AAAWAAMJFB8CfAD8AAACAAEJ/iG/MwBUAAAuAAQKfyMAAwIACQnrI1oCAEwDAAIACQlNI1oCAEwDABYAAQkOHzk6AVQAAAAA.',
Lo='Loaf:BAAALgAECgYJEgAAAA==.Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8fAAIiAAcJeBywIAC1AQAiAAcJeBywIAC1AQAAAA==.',
Lu='Lunarbelle:BAAALgADCgkJDwAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAABLgAECn8fAAILAAgJmguYgABwAQALAAgJmguYgABwAQAAAA==.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwAPAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJbhw6HwBKAgABAAgJbhw6HwBKAgAEAAMJ+AWWcQB4AAAAAA==.',
Me='Mekkadorque:BAAALgADCgUJBQABLgAECgcJCAAPAAAAAA==.Merien:BAABLgAECn8jAAIBAAcJuwi8gwAqAQABAAcJuwi8gwAqAQAAAA==.Meros:BAABLgAECn8aAAIBAAYJ/wj/lwACAQABAAYJ/wj/lwACAQAAAA==.',
Mo='Monstrosoh:BAAALgAECgUJCQAAAA==.Moonstrudels:BAAALgAECgQJBQABLgAECggJGgANADcVAA==.',
Mt='Mtdewmachine:BAAALgAECgIJAwAAAA==.',
Mu='Muertesdemon:BAAALgADCgUJBQAAAA==.Munstar:BAAALgADCgYJBgAAAA==.',
Na='Nafari:BAAALgAECgUJBQAAAA==.Narasil:BAAALgAECgEJAQAAAA==.Natea:BAAALgAECgcJDAAAAA==.',
Ne='Nebüla:BAABLgAECn8UAAIQAAkJoAzWJQB3AQAQAAkJoAzWJQB3AQAAAA==.Necrökush:BAAALgAFFAEJAQAAAA==.Nestro:BAAALgADCgUJBQAAAA==.',
Ni='Nightwinds:BAAALgAECgEJAgAAAA==.Ninajavin:BAAALgAECgUJBQAAAA==.',
No='Norinna:BAAALgAECggJEQABLgAFFAIJCAALAHoLAA==.Norlairas:BAAALgADCgUJBQAAAA==.',
Ny='Nyxxalecgos:BAACLgAFFH8GAAIIAAQJxwc/NwDcAAAIAAQJxwc/NwDcAAAuAAQKfyQAAggACAmiE8YbAOoBAAgACAmiE8YbAOoBAAEuAAUUBAkSAAkAWw8A.',
Od='Odiousego:BAACLgAFFH8IAAIKAAQJfAYyBgARAQAKAAQJfAYyBgARAQAuAAQKfx4AAgoACAmdGOUFABMCAAoACAmdGOUFABMCAAAA.',
Ol='Oldkrusty:BAAALgADCgMJAwAAAA==.',
On='Onyxfïend:BAAALgADCgMJAwAAAA==.',
Oo='Ooryl:BAAALgAECgEJAQAAAA==.',
Op='Opheliajavin:BAAALgAECgEJAQAAAA==.',
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAABLgAECn8hAAILAAkJNhbOMgBHAgALAAkJNhbOMgBHAgAAAA==.',
Pa='Painless:BAABLgAECn8YAAIYAAcJFg0QMQBKAQAYAAcJFg0QMQBKAQAAAA==.',
Ph='Phloemie:BAAALgADCgYJCQAAAA==.',
Po='Popeleo:BAAALgAECgEJAgAAAA==.Poronuma:BAAALgADCgEJAQAAAA==.Powerhøuse:BAACLgAFFH8cAAILAAgJUxxQCwB2AgALAAgJUxxQCwB2AgAuAAQKfycAAwsACAlgIp0YABcDAAsACAlgIp0YABcDAB4AAQkAAB0RAC4AAAAA.Powerwordhug:BAABLgAECn8tAAIdAAkJnx2eCwCgAgAdAAkJnx2eCwCgAgAAAA==.',
Pr='Proctolodin:BAACLgAFFH8GAAIGAAMJYAhUbwDAAAAGAAMJYAhUbwDAAAAuAAQKfyUAAgYACAlGFJFdAKwBAAYACAlGFJFdAKwBAAAA.',
Pu='Purplefart:BAABLgAECn8qAAMjAAkJfBT3GQDvAQAjAAkJfBT3GQDvAQAYAAIJshrbVACXAAAAAA==.',
Ql='Qlaryx:BAABLgAECn8WAAIBAAYJ7RPNfAA4AQABAAYJ7RPNfAA4AQAAAA==.',
Qu='Quinner:BAACLgAFFH8NAAIIAAQJcREZLAAEAQAIAAQJcREZLAAEAQAuAAQKfzIABAgACQneGy0NAIQCAAgACQneGy0NAIQCAAcABAm+BTo3ALIAAAkAAwlTC4IuAKUAAAAA.Qut:BAABLgAECn8cAAIMAAgJxh0lGQDCAQAMAAgJxh0lGQDCAQAAAA==.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Rark:BAAALgAECgEJAQAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAABLgAECn8eAAILAAYJRxzZggBrAQALAAYJRxzZggBrAQAAAA==.',
Ri='Rickle:BAAALgAECgMJAwAAAA==.Riptoe:BAAALgAECgMJAwAAAA==.',
Ro='Roantami:BAAALgADCgUJBQAAAA==.Rokey:BAAALgAFFAEJAgABLgAFFAMJCgALAMcfAA==.Rolling:BAAALgADCgMJAwAAAA==.Ronmaru:BAAALgAECgcJEAAAAA==.Rosejavin:BAAALgAECgEJAQAAAA==.Roxy:BAAALgAECgEJAQAAAA==.',
Ry='Ryujin:BAAALgAECgYJBgABLgAECggJGgANADcVAA==.',
Sa='Sabel:BAAALgAECgMJAwAAAA==.Sagori:BAAALgAECgEJAgAAAA==.Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn84AAMcAAgJxxLIVgCTAQAcAAgJWRLIVgCTAQAKAAQJ9xIrFADtAAAAAA==.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAABLgAECn8dAAMkAAgJrh/EDQCLAgAkAAgJrh/EDQCLAgAUAAEJVQvhVgAfAAAAAA==.Seiken:BAAALgAECggJEgAAAA==.Selas:BAABLgAECn8hAAMCAAYJSBGVKAAHAQACAAYJSBGVKAAHAQAWAAYJkwn10ADdAAAAAA==.Seryiana:BAAALgAECgQJBwAAAA==.',
Sg='Sgtkabukiman:BAAALgAECgYJDAABLgAECggJFwABAFAdAA==.',
Sh='Shackiechan:BAAALgAECgIJAwAAAA==.Shadowflood:BAAALgAECgMJBAAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBQABLgAECgIJBAAPAAAAAA==.',
Si='Silk:BAABLgAECn8hAAIBAAgJeRDFTwCmAQABAAgJeRDFTwCmAQAAAA==.Silren:BAAALgAECgQJCQAAAA==.Sita:BAAALgADCgkJDwAAAA==.',
Sk='Skoldsmoyer:BAAALgADCgUJBQAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAAALgAECgUJCgABLgAFFAMJBgAGAGAIAA==.',
So='Sofferenza:BAAALgADCgcJGwAAAA==.Sorulus:BAAALgAECgEJAgAAAA==.Souldance:BAABLgAECn8sAAMcAAkJcRbLKAAyAgAcAAkJcRbLKAAyAgAbAAMJQA6mLwBVAAAAAA==.',
Sp='Spaceguy:BAABLgAECn8jAAIRAAgJ5giZRAARAQARAAgJ5giZRAARAQAAAA==.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgAECgEJAQABLgAECgkJLAAQALEPAA==.Starwind:BAAALgAECgYJDAAAAA==.Stolock:BAAALgAECgMJAwABLgAECggJGgAlAOgZAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Sugammadex:BAAALgAECgIJBQABLgAECgIJBwAPAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAABLgAECn8VAAIRAAgJ4SHMDACPAgARAAgJ4SHMDACPAgAAAA==.',
Sw='Swato:BAAALgAECgEJAQABLgAECggJDwAPAAAAAA==.',
Sy='Sylaang:BAAALgAECgIJAgAAAA==.',
Ta='Talie:BAAALgADCgYJBQAAAA==.Taliria:BAABLgAECn8eAAIjAAYJehhWJgClAQAjAAYJehhWJgClAQAAAA==.Talladar:BAAALgAECgUJCQAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Targ:BAABLgAECn8XAAIBAAgJUB1uKwAlAgABAAgJUB1uKwAlAgAAAA==.',
Te='Tenshiro:BAAALgADCgYJDQAAAA==.Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgAECgYJBgAAAA==.Thundamon:BAAALgAECgEJAQAAAA==.',
Ti='Tidefang:BAAALgAECgcJDAABLgAECggJFgADAJUJAA==.',
To='Toblakai:BAAALgADCgUJBQABLgAECgkJAgAPAAAAAA==.Torryn:BAAALgADCgkJCQAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.Truthteiier:BAAALgAECgEJAgAAAA==.',
Ty='Tyladrillian:BAAALgAECgEJAQAAAA==.',
Un='Unholyguard:BAAALgADCgEJAQABLgAFFAYJFgAXABcKAA==.',
Uz='Uzumaki:BAABLgAECn8VAAIOAAgJrBUIGgDUAQAOAAgJrBUIGgDUAQAAAA==.',
Va='Vajrajavin:BAAALgAECgYJDwABLgAECggJKgAIANMPAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAACLgAFFH8aAAINAAcJeBT6DAANAgANAAcJeBT6DAANAgAuAAQKfyUAAg0ACQkhI3oDAHgDAA0ACQkhI3oDAHgDAAAA.Valasca:BAAALgADCgcJBwAAAA==.Valonar:BAAALgAECgUJCAAAAA==.Valonkyr:BAAALgADCgEJAQAAAA==.Valor:BAAALgAECggJEwAAAA==.Vardeath:BAAALgAECgMJAwAAAA==.',
Ve='Veldaan:BAAALgADCgkJEwAAAA==.',
Vi='Victra:BAAALgAECgUJBQABLgAECggJFwABAFAdAA==.Vinskey:BAAALgADCgYJBgAAAA==.Vipe:BAAALgAECggJEQAAAA==.Viperlock:BAAALgADCgUJBQAAAA==.Visenyaa:BAAALgADCgEJAQAAAA==.Vita:BAAALgAECgQJBAAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.Voodoochild:BAAALgAECgUJBgAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECggJFwABAFAdAA==.',
Wa='Waltwitemane:BAAALgAECgEJAQAAAA==.Warliff:BAAALgADCgMJAwAAAA==.',
Wh='Whish:BAABLgAECn8XAAImAAYJFQl6cwDRAAAmAAYJFQl6cwDRAAAAAA==.Whiteleaf:BAABLgAECn8gAAIkAAkJYwwgKgCoAQAkAAkJYwwgKgCoAQAAAA==.',
Wi='Wisdom:BAAALgADCggJDQABLgAECggJEwAPAAAAAA==.',
Wt='Wtfishéaling:BAAALgAECgMJBAAAAA==.',
Xe='Xenonga:BAAALgADCgEJAQAAAA==.',
Ye='Yenneth:BAAALgAECgYJEAAAAA==.',
['Yî']='Yîn:BAAALgAECgEJAQAAAA==.',
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
