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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Rogue-Assassination','Paladin-Retribution','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warlock-Affliction','Mage-Frost','DemonHunter-Devourer','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','Shaman-Restoration','Unknown-Unknown','Monk-Brewmaster','Shaman-Elemental','DemonHunter-Havoc','Druid-Feral','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Paladin-Holy','Priest-Discipline','Shaman-Enhancement','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Priest-Holy','Mage-Fire','Warrior-Fury','Mage-Arcane','Rogue-Outlaw','Druid-Balance','Priest-Shadow','Paladin-Protection','Druid-Restoration',}
local provider = {region='US',realm='Fenris',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aayu:BAABLgAECn8vAAIBAAgJyxn7NwD+AQABAAgJyxn7NwD+AQAAAA==.',
Ad='Addie:BAEBLgAFFH8HAAICAAIJ4hZ2DgCDAAACAAIJ4hZ2DgCDAAABLgAFFAkJPQADAIAmAA==.Adranelidk:BAABLgAECn8mAAICAAcJfBVlAwDjAAACAAcJfBVlAwDjAAAAAA==.',
Ae='Aeromina:BAABLgAECn8cAAMBAAcJORTOfQBEAQABAAcJORTOfQBEAQAEAAEJZABYnAAKAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgABLgAECggJKAAFANcbAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIGAAgJAxpDNQBNAgAGAAgJAxpDNQBNAgAAAA==.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJDQAAAA==.Alphabet:BAAALgADCgMJBQAAAA==.Alypiia:BAAALgAECgMJAwAAAA==.',
Am='Amadori:BAAALgAECgQJBQAAAA==.',
An='Ancalagon:BAABLgAECn8jAAQHAAgJqCE1BADvAgAHAAgJqCE1BADvAgAIAAgJ2wvZPwAqAQAJAAEJRhbQPAA7AAAAAA==.Angelic:BAAALgAECgIJAgAAAA==.Anguish:BAAALgAECgUJDAAAAA==.Antia:BAAALgAECgQJBAABLgAFFAUJEQAKAMMLAA==.',
Ap='April:BAABLgAECn8bAAILAAkJXwW++QC2AAALAAkJXwW++QC2AAAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIEAAIJLxlYGwCqAAAEAAIJLxlYGwCqAAAuAAQKfx8AAgQACQm5IigDAHgDAAQACQm5IigDAHgDAAEuAAUUBAkHAAwAFh0A.',
As='Ashveil:BAABLgAECn8qAAIIAAgJ0w8UNwBTAQAIAAgJ0w8UNwBTAQAAAA==.Asray:BAAALgAECgMJBwABLgAFFAQJEgANABUeAA==.',
At='Athenã:BAAALgADCgEJAQAAAA==.',
Au='Aussie:BAAALgAECgUJBQABLgAECgkJIQAOALYVAA==.Aussiesauce:BAAALgAECgUJCgABLgAECgkJIQAOALYVAA==.Aussilicious:BAABLgAECn8hAAMOAAkJthXaHAAxAgAOAAkJthXaHAAxAgAPAAIJqAQdbwBVAAAAAA==.',
Az='Azerennia:BAABLgAECn8fAAILAAkJdgdhCQAdAQALAAkJdgdhCQAdAQAAAA==.Azerious:BAAALgAECgIJAwAAAA==.Azreya:BAAALgAECgEJAgAAAA==.Azrokke:BAABLgAECn8WAAIQAAkJwRmnGACEAgAQAAkJwRmnGACEAgAAAA==.',
Ba='Babetter:BAABLgAECn8uAAIBAAgJ9wbGgQA7AQABAAgJ9wbGgQA7AQAAAA==.Baby:BAAALgAECgYJBgAAAA==.Bacstabbe:BAAALgAECgEJAQAAAA==.Badasbro:BAAALgAECgEJAgAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAARAAAAAA==.Baelz:BAAALgAECgYJBgAAAA==.Bahamaut:BAAALgAECgQJBgABLgAECgkJIQAOALYVAA==.Balzan:BAAALgADCgYJBwAAAA==.',
Be='Beerless:BAABLgAECn8uAAISAAkJORXTAADmAQASAAkJORXTAADmAQAAAA==.Belphegör:BAAALgAECgYJDgAAAA==.Bencicil:BAAALgAECgcJDwAAAA==.Berkleyf:BAAALgADCgYJCQABLgAFFAMJBwATADIMAA==.Beydoon:BAAALgAECgMJBwAAAA==.',
Bl='Blindmagg:BAAALgAECgYJCAABLgAECggJGQABAJAeAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgcJCAABLgAECgcJDQARAAAAAA==.',
Br='Brain:BAAALgAECgEJAwAAAA==.Brawnhilda:BAAALgADCgcJDAABLgAECgkJJQABAL0XAA==.Brewdude:BAAALgADCgcJBwAAAA==.Brewmanchu:BAAALgADCggJCAABLgAECgcJCAARAAAAAA==.Bro:BAAALgAECgUJEQAAAA==.',
Bu='Bunky:BAAALgAECgMJBgABLgAFFAMJBwATADIMAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8hAAIUAAgJuSA1AgBJAgAUAAgJuSA1AgBJAgAuAAQKfygAAhQACQnuJcMBAIYDABQACQnuJcMBAIYDAAAA.Calayra:BAAALgADCgIJAgAAAA==.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8jAAQOAAgJKhgNKQDiAQAOAAcJDxoNKQDiAQASAAUJGQVXYADBAAAPAAEJ3A7GoQAuAAAAAA==.Cartheron:BAAALgAECgkJAgAAAA==.',
Ce='Cellynna:BAAALgADCggJFAAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgAAAA==.Crims:BAAALgADCgcJDgABLgADCgcJDgARAAAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECggJDwAAAA==.',
Cy='Cynla:BAAALgAECgMJAwAAAA==.',
['Cí']='Círce:BAEALgAECgUJBwABLgAFFAQJEgASABAfAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.Darremiah:BAAALgADCgEJAQAAAA==.David:BAACLgAFFH8KAAILAAMJRAuYJADAAAALAAMJRAuYJADAAAAuAAQKfygAAgsACQlKHS8nAH4CAAsACQlKHS8nAH4CAAAA.',
Db='Dbsheep:BAAALgAECgMJBQAAAA==.',
De='Deezhealz:BAAALgAECgYJDAAAAA==.Dezal:BAAALgADCgIJAgAAAA==.',
Di='Diddyfisting:BAACLgAFFH8cAAIPAAYJQCLwBgCnAQAPAAYJQCLwBgCnAQAuAAQKfzAAAw8ACQneI5oGAOECAA8ACQneI5oGAOECABIAAQk6A4mPACYAAAAA.Divinefistin:BAECLgAFFH8SAAISAAQJEB/dFgBrAQASAAQJEB/dFgBrAQAuAAQKfzgAAxIACQnCIi0NAGQCABIACQnLHS0NAGQCAA8ABwlYIr4RADUCAAAA.Divinepain:BAEALgAECgMJAwABLgAFFAQJEgASABAfAA==.',
Dn='Dnova:BAAALgAECgMJBAAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCwAAAA==.Dornadions:BAAALgAECgYJDgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAABLgAECn8WAAMHAAkJgg6HFACCAQAHAAkJgg6HFACCAQAIAAYJJg7JTQD2AAAAAA==.Draka:BAABLgAECn8VAAIVAAkJaA6UEgCSAQAVAAkJaA6UEgCSAQAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Dreadtide:BAAALgADCgcJEAAAAA==.Drunk:BAAALgAECgcJDQAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJCAAAAA==.',
Dy='Dymetra:BAAALgAECgEJAQAAAA==.',
['Dö']='Döritö:BAABLgAECn8WAAIMAAcJGgkbCADrAAAMAAcJGgkbCADrAAAAAA==.',
Ec='Ecks:BAACLgAFFH8SAAIWAAgJ/RqcCgCGAQAWAAgJ/RqcCgCGAQAuAAQKfzMAAxYACQl8HswCADgDABYACQl8HswCADgDABcAAQkAAAqQAAAAAAAA.',
El='Elfuego:BAAALgAECggJDQAAAA==.',
Em='Employee:BAAALgAECgcJCwAAAA==.',
En='Energgy:BAAALgAECgkJCgAAAA==.Enigmanta:BAAALgADCgUJBQAAAA==.',
Ev='Eviljoke:BAAALgADCgkJDwAAAA==.',
Fa='Faeda:BAAALgAECgUJCAAAAA==.Faestaul:BAABLgAECn8hAAIGAAkJEBmlQAAFAgAGAAkJEBmlQAAFAgAAAA==.Fatima:BAAALgAECgEJAgAAAA==.Fatty:BAAALgAFFAEJAQABLgAFFAkJKwAIAL8bAA==.',
Fe='Fearyourface:BAAALgADCgMJAwAAAA==.Fenrisulfr:BAAALgADCgYJBgAAAA==.Fentdemon:BAABLgAFFH8GAAMUAAMJiwaNCgBxAAAUAAMJiwaNCgBxAAAMAAEJeAEPrQAlAAAAAA==.',
Fi='Findinnan:BAABLgAECn8aAAIFAAkJeQVMDQBVAQAFAAkJeQVMDQBVAQAAAA==.Fishtotem:BAAALgADCgcJDQAAAA==.',
Fl='Flor:BAAALgAECgEJAQAAAA==.',
Fr='Freeze:BAAALgAECgYJCQAAAA==.Freezerbern:BAAALgAECggJDwAAAA==.Frissbee:BAAALgADCgMJAwABLgAECgMJAwARAAAAAA==.Frostblood:BAAALgADCgIJAgAAAA==.Froststd:BAAALgADCgEJAQAAAA==.Fréki:BAAALgAECgIJAgAAAA==.',
Fu='Fullpeny:BAAALgADCgEJAQAAAA==.',
Ga='Gametheory:BAAALgAECgIJBwAAAA==.Ganzar:BAACLgAFFH8WAAIYAAMJwyRIGAARAQAYAAMJwyRIGAARAQAuAAQKfycAAhgACQmnInoIAC4DABgACQmnInoIAC4DAAAA.Gathan:BAAALgADCgcJHgAAAA==.',
Ge='Genderdruid:BAAALgAECgIJAwAAAA==.Genge:BAABLgAECn89AAMGAAgJnROHCwDuAAAGAAgJnROHCwDuAAAZAAIJewbZDQAzAAAAAA==.Gertrex:BAABLgAECn8jAAIaAAkJzQuUAgBrAQAaAAkJzQuUAgBrAQAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.Gitchusum:BAAALgAECgcJBgAAAA==.',
Gl='Glennhelen:BAAALgADCgkJDwAAAA==.',
Go='Goatlord:BAABLgAECn8eAAIbAAkJMw85EACuAQAbAAkJMw85EACuAQAAAA==.Goatsavior:BAAALgAECgUJDgAAAA==.Goblinsrhot:BAAALgADCgkJDwAAAA==.Gotharm:BAABLgAECn8bAAIcAAkJswy8GADaAQAcAAkJswy8GADaAQAAAA==.',
Gr='Grester:BAAALgAECggJEwAAAA==.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAABLgAECn8fAAIBAAYJVR9YCwAEAQABAAYJVR9YCwAEAQAAAA==.',
Ha='Hahmicydal:BAABLgAECn8gAAQdAAcJ8giGIACpAAAKAAcJSAadHQDSAAAdAAYJTAiGIACpAAAeAAIJHwJuOQE2AAAAAA==.Hal:BAABLgAECn8YAAIBAAYJvwoMDgDbAAABAAYJvwoMDgDbAAAAAA==.Hardcore:BAAALgADCgUJBQAAAA==.Havökush:BAACLgAFFH8JAAIUAAMJIRArGwDJAAAUAAMJIRArGwDJAAAuAAQKfycAAhQACQmBIfsEAPUCABQACQmBIfsEAPUCAAAA.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgAECgEJAgABLgAFFAEJAQARAAAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAIaAAcJmw22NQA+AQAaAAcJmw22NQA+AQAAAA==.Holyguard:BAACLgAFFH8cAAIZAAYJGQ9SEwCUAQAZAAYJGQ9SEwCUAQAuAAQKfywAAhkACQkqF5QbACcCABkACQkqF5QbACcCAAAA.Holyhand:BAABLgAECn8UAAIfAAYJAg4DSQAVAQAfAAYJAg4DSQAVAQABLgAFFAYJHAAZABkPAA==.',
Ic='Ickis:BAAALgAECgYJBgABLgAECggJGQABAJAeAA==.',
Il='Ilin:BAAALgAECggJEAAAAA==.Illidres:BAAALgADCgQJBQAAAA==.Ilou:BAAALgAECgcJCAABLgAFFAUJEQAKAMMLAA==.',
In='Influenza:BAAALgAECgMJAwAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAABLgAECn8zAAIgAAkJzxejAgAjAgAgAAkJzxejAgAjAgABLgAECggJFgAhAM0WAA==.',
Is='Isabela:BAABLgAFFH8IAAIMAAIJsyQIZADGAAAMAAIJsyQIZADGAAAAAA==.Isilian:BAAALgADCgUJCAAAAA==.',
Iw='Iwillpull:BAAALgADCgcJAQAAAA==.',
Iy='Iyora:BAAALgADCgUJBQAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgYJCAABLgAFFAYJHAAPAEAiAA==.Judyhopondik:BAAALgAECgYJBgAAAA==.Judyhopp:BAABLgAECn8aAAQiAAgJWhYxCAB2AQAiAAcJsBIxCAB2AQALAAcJFxORqQAsAQAgAAEJAADhGAAAAAABLgAFFAYJHAAPAEAiAA==.Judyhopps:BAAALgAFFAIJAgABLgAFFAYJHAAPAEAiAA==.Judyhoppsimp:BAABLgAFFH8LAAMPAAcJYxR8AQCLAQAPAAYJjxZ8AQCLAQAOAAMJmQ2DTQBwAAAAAA==.',
Ka='Kaeln:BAAALgAFFAMJAwABLgAFFAUJEQAiAMYdAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kagronn:BAAALgADCggJCgAAAA==.Kakez:BAAALgAECgEJAQABLgAFFAgJJQAfANwXAA==.Kaluanights:BAAALgAECgEJAgAAAA==.Kalzak:BAABLgAECn8uAAIVAAkJzRE/AQBhAQAVAAkJzRE/AQBhAQAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAABLgAECn8ZAAIeAAYJ2wb/vgDNAAAeAAYJ2wb/vgDNAAAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kithiandra:BAAALgADCgIJAgAAAA==.Kiwistunna:BAAALgAECgYJDAABLgAECgkJHAATAOYRAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAABLgAECn8pAAIjAAkJXxBtAABRAQAjAAkJXxBtAABRAQAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAARAAAAAA==.',
Ky='Kylepriestt:BAAALgAECgQJBAAAAA==.',
['Kï']='Kïtana:BAAALgAECgMJBAAAAA==.',
La='Laddyboy:BAAALgADCgMJAwAAAA==.Ladiemacbeth:BAAALgADCgkJDwABLgAECgkJLgAVAM0RAA==.Lanwynne:BAAALgADCgYJBAABLgAECgkJJQABAL0XAA==.Laxion:BAAALgADCgkJGwAAAA==.',
Le='Leafs:BAAALgAECgEJAQAAAA==.Leggo:BAABLgAECn8dAAIZAAYJfhFiPgBLAQAZAAYJfhFiPgBLAQAAAA==.',
Li='Lidravos:BAAALgAECgEJAQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilfist:BAAALgAECgYJBwAAAA==.Lilia:BAACLgAFFH8KAAIGAAMJPwVzhgCmAAAGAAMJPwVzhgCmAAAuAAQKfyEAAwYACAlYHCQqAHwCAAYACAlYHCQqAHwCABkABAnYAX16AI8AAAAA.Lilmorty:BAAALgAECgYJDgABLgAFFAcJGwAEAAcYAA==.',
Ll='Lluvioso:BAACLgAFFH8NAAMYAAMJ4h9ZjADxAAAYAAMJFB9ZjADxAAACAAEJ/iE3OQBRAAAuAAQKfyMAAwIACQnrI1oCAEwDAAIACQlNI1oCAEwDABgAAQkOHzFMAVQAAAAA.',
Lo='Loaf:BAABLgAECn8YAAILAAYJeR3SZQCyAQALAAYJeR3SZQCyAQAAAA==.Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8fAAIkAAcJeByeIgC0AQAkAAcJeByeIgC0AQAAAA==.',
Lu='Lucia:BAAALgADCggJDAAAAA==.Lunarbelle:BAAALgADCgkJDwAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAABLgAECn8lAAILAAgJzQ+HCwD4AAALAAgJzQ+HCwD4AAAAAA==.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwARAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Marath:BAAALgADCgEJAQAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJbhw6HwBKAgABAAgJbhw6HwBKAgAEAAMJ+AWWcQB4AAAAAA==.',
Me='Mekkadorque:BAAALgADCgUJBQABLgAECgcJCAARAAAAAA==.Merien:BAABLgAECn8mAAIBAAgJeAg9iwAoAQABAAgJeAg9iwAoAQAAAA==.Meros:BAABLgAECn8mAAIBAAcJrgypCgAQAQABAAcJrgypCgAQAQAAAA==.',
Mi='Minathiel:BAAALgADCgIJAgAAAA==.',
Mo='Monstrosoh:BAAALgAECgUJCQAAAA==.Moonkins:BAAALgAECgEJAQABLgAECgMJAwARAAAAAA==.Moonstrudels:BAAALgAECgQJBQABLgAECgkJIQAOALYVAA==.',
Mt='Mtdewmachine:BAAALgAECgIJAwAAAA==.',
Mu='Muertesdemon:BAAALgADCgUJBQAAAA==.Munstar:BAAALgADCgYJBgAAAA==.Mutagenic:BAAALgADCgEJAQAAAA==.',
Na='Nafari:BAAALgAECgUJBgAAAA==.Narasil:BAAALgAECgEJAQAAAA==.Natea:BAAALgAECgcJDAAAAA==.Nayrb:BAAALgAECgEJAQABLgAFFAEJAQARAAAAAA==.',
Ne='Nebüla:BAABLgAECn8ZAAISAAkJ+gwAJgB+AQASAAkJ+gwAJgB+AQAAAA==.Necrökush:BAAALgAFFAIJAgAAAA==.Nestro:BAAALgADCgUJBQAAAA==.',
Ni='Nightwinds:BAAALgAECgEJAgAAAA==.Ninajavin:BAAALgAECgUJBQAAAA==.',
No='Norinna:BAAALgAECggJEQABLgAFFAMJCwALANwIAA==.Norlairas:BAAALgADCgUJBQAAAA==.Notsujan:BAAALgADCgYJBgAAAA==.',
Ny='Nyxxalecgos:BAACLgAFFH8GAAIIAAQJxwcVPgDPAAAIAAQJxwcVPgDPAAAuAAQKfyoAAggACAlGFDECAEIBAAgACAlGFDECAEIBAAEuAAUUBQkXAAkAhA8A.',
Od='Odiousego:BAACLgAFFH8RAAIKAAUJwwtKBgAcAQAKAAUJwwtKBgAcAQAuAAQKfyMAAgoACAlFGlwFADQCAAoACAlFGlwFADQCAAAA.',
Ol='Oldkrusty:BAAALgADCgMJAwAAAA==.',
On='Onyxfïend:BAAALgADCgMJAwAAAA==.',
Oo='Ooryl:BAAALgAECgEJAQAAAA==.',
Op='Opheliajavin:BAAALgAECgEJAQAAAA==.',
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAABLgAECn8hAAILAAkJNhYCNwA8AgALAAkJNhYCNwA8AgAAAA==.',
Pa='Painless:BAABLgAECn8YAAIaAAcJFg0dNQBBAQAaAAcJFg0dNQBBAQAAAA==.',
Pe='Pewsmash:BAAALgAECgQJBAAAAA==.',
Ph='Phloemie:BAAALgADCgYJCQAAAA==.',
Po='Popeleo:BAAALgAECgMJBgAAAA==.Poronuma:BAAALgADCgEJAQAAAA==.Powerhøuse:BAACLgAFFH8cAAILAAgJUxwFEQBkAgALAAgJUxwFEQBkAgAuAAQKfycAAwsACAlgIp0YABcDAAsACAlgIp0YABcDACAAAQkAAB0RAC4AAAAA.Powerwordhug:BAABLgAECn8tAAIfAAkJnx2zDACbAgAfAAkJnx2zDACbAgAAAA==.',
Pr='Proctolodin:BAACLgAFFH8JAAIGAAMJbgs0dgDIAAAGAAMJbgs0dgDIAAAuAAQKfywAAgYACQkZFkJhAK4BAAYACQkZFkJhAK4BAAAA.',
Pu='Purplefart:BAABLgAECn8rAAMlAAkJfBQPHADkAQAlAAkJfBQPHADkAQAaAAIJwhxXCwBYAAAAAA==.',
Ql='Qlaryx:BAABLgAECn8lAAIBAAkJvReKAwDXAQABAAkJvReKAwDXAQAAAA==.',
Qu='Quinner:BAACLgAFFH8RAAIIAAQJcRFiMwD0AAAIAAQJcRFiMwD0AAAuAAQKfzUABAgACQneG/gNAIECAAgACQneG/gNAIECAAcABAm+BTo3ALIAAAkAAwlTC4IuAKUAAAAA.Qut:BAABLgAECn8cAAINAAgJxh3WGgDBAQANAAgJxh3WGgDBAQAAAA==.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Rark:BAAALgAECgEJAQAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAABLgAECn8eAAILAAYJRxxmhwBoAQALAAYJRxxmhwBoAQAAAA==.Restore:BAAALgAECgMJAwAAAA==.',
Ri='Rickle:BAAALgAECgMJAwAAAA==.Riptoe:BAAALgAECgcJCAAAAA==.',
Ro='Roantami:BAAALgADCgUJBQAAAA==.Rokey:BAAALgAFFAEJAgABLgAFFAMJCwALAMcfAA==.Rolling:BAAALgADCgMJAwAAAA==.Ronmaru:BAAALgAECgcJEAAAAA==.Rosejavin:BAAALgAECgEJAQAAAA==.Roxy:BAAALgAECgEJAQAAAA==.',
Ry='Ryujin:BAAALgAECgYJBgABLgAECgkJIQAOALYVAA==.',
Sa='Sabel:BAAALgAECgMJAwAAAA==.Sagori:BAAALgAECgEJAgAAAA==.Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn84AAMeAAgJxxLiWwCKAQAeAAgJWRLiWwCKAQAKAAQJ9xIrFADtAAAAAA==.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAABLgAECn8tAAMhAAkJCyG9BQAEAwAhAAkJCyG9BQAEAwAWAAMJJxObAwC8AAAAAA==.Seiken:BAAALgAECggJEgAAAA==.Selas:BAABLgAECn8hAAMCAAYJSBEBKwABAQACAAYJSBEBKwABAQAYAAYJkwkk3QDYAAAAAA==.Seryiana:BAAALgAECgYJEgAAAA==.',
Sg='Sgtkabukiman:BAAALgAECgYJDAABLgAECggJGQABAJAeAA==.',
Sh='Shackiechan:BAAALgAECgIJBAAAAA==.Shadowflood:BAAALgAECgMJBAAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBQABLgAECgIJBAARAAAAAA==.',
Si='Silk:BAABLgAECn8jAAIBAAkJrA/WVgCfAQABAAkJrA/WVgCfAQAAAA==.Silren:BAAALgAECgQJCQAAAA==.Sita:BAAALgADCgkJDwAAAA==.',
Sk='Skoldsmoyer:BAAALgADCgUJBQAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAABLgAECn8WAAILAAkJEhJXBACmAQALAAkJEhJXBACmAQABLgAFFAMJCQAGAG4LAA==.',
So='Sofferenza:BAAALgADCgcJGwAAAA==.Sorulus:BAAALgAECgEJAgAAAA==.Souldance:BAABLgAECn8xAAMeAAkJVhg3IgBZAgAeAAkJVhg3IgBZAgAdAAMJQA6tMgBUAAAAAA==.Soulslawter:BAAALgADCgUJBQABLgAECgkJLQAfALsYAA==.',
Sp='Spaceguy:BAABLgAECn8kAAITAAkJuQjmPQA9AQATAAkJuQjmPQA9AQAAAA==.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgAFFAEJAgABLgAECgkJLAASALEPAA==.Starwind:BAAALgAECgYJDAAAAA==.Stolock:BAAALgAECgMJAwABLgAECggJGgAmAOgZAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Sugammadex:BAAALgAECgIJBQABLgAECgIJBwARAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAABLgAECn8fAAMTAAkJ/yEZBwDrAgATAAkJ/yEZBwDrAgAQAAIJGxKkDQB6AAAAAA==.',
Sw='Swato:BAAALgAECgEJAQABLgAECggJEAARAAAAAA==.',
Sy='Sylaang:BAAALgAECgIJAwAAAA==.',
Ta='Talie:BAAALgADCgYJBQAAAA==.Taliria:BAABLgAECn8eAAIlAAYJehhWJgClAQAlAAYJehhWJgClAQAAAA==.Talladar:BAAALgAECgYJEAAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Tampax:BAAALgAECggJCQABLgAECgkJIQAOALYVAA==.Targ:BAABLgAECn8ZAAIBAAgJkB70LwAcAgABAAgJkB70LwAcAgAAAA==.',
Te='Tenshiro:BAAALgADCgYJDQAAAA==.Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgAECgYJBgAAAA==.Thugzug:BAAALgADCggJCAAAAA==.Thundamon:BAAALgAECgEJAQAAAA==.',
Ti='Tidefang:BAAALgAFFAEJAQAAAA==.',
To='Toblakai:BAAALgAECgMJAQABLgAECgkJAgARAAAAAA==.Torryn:BAAALgADCgkJCQAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.Truthteiier:BAAALgAECgEJAwAAAA==.',
Ty='Tyladrillian:BAAALgAECgEJAQAAAA==.',
Un='Unholyguard:BAAALgADCgEJAQABLgAFFAYJHAAZABkPAA==.',
Uz='Uzumaki:BAABLgAECn8WAAIPAAgJGBaiGwDTAQAPAAgJGBaiGwDTAQAAAA==.',
Va='Vajrajavin:BAAALgAECgYJDwABLgAECggJKgAIANMPAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAACLgAFFH8eAAIOAAgJ2hWUCgBeAgAOAAgJ2hWUCgBeAgAuAAQKfyUAAg4ACQkhI/EDAHcDAA4ACQkhI/EDAHcDAAAA.Valasca:BAAALgADCgcJBwAAAA==.Valonar:BAAALgAECgYJCQAAAA==.Valonkyr:BAAALgAECgEJAQAAAA==.Valor:BAAALgAECggJEwAAAA==.Vardeath:BAAALgAECgMJAwAAAA==.',
Ve='Veldaan:BAAALgAECgEJAQAAAA==.',
Vi='Victra:BAAALgAECgUJBQABLgAECggJGQABAJAeAA==.Vinskey:BAAALgAECgUJBQAAAA==.Vipe:BAAALgAECggJEwAAAA==.Viperlock:BAAALgAECgIJAgAAAA==.Visenyaa:BAAALgADCgEJAQAAAA==.Vita:BAAALgAECgUJBQAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.Voodoochild:BAAALgAFFAIJAgAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECggJGQABAJAeAA==.',
Wa='Waltwitemane:BAAALgAECgEJAwAAAA==.Warliff:BAAALgADCgMJAwAAAA==.',
Wh='Whish:BAABLgAECn8cAAInAAcJFgovbQDtAAAnAAcJFgovbQDtAAAAAA==.Whiteleaf:BAABLgAECn81AAIhAAkJJxK+IADrAQAhAAkJJxK+IADrAQAAAA==.',
Wi='Wisdom:BAAALgADCggJDQABLgAECggJEwARAAAAAA==.',
Wt='Wtfishéaling:BAAALgAFFAEJAQAAAA==.',
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
