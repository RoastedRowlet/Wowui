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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Rogue-Assassination','Paladin-Retribution','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warlock-Affliction','Mage-Frost','DemonHunter-Devourer','Rogue-Subtlety','Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Shaman-Restoration','Monk-Brewmaster','Shaman-Elemental','DemonHunter-Havoc','Druid-Feral','Paladin-Holy','Warrior-Protection','Warrior-Fury','Warrior-Arms','Rogue-Outlaw','DeathKnight-Unholy','Priest-Discipline','Shaman-Enhancement','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Priest-Holy','Mage-Fire','Mage-Arcane','Druid-Balance','Priest-Shadow','Paladin-Protection','Druid-Restoration',}
local provider = {region='US',realm='Fenris',name='US',type='weekly',zone=46,date='2026-07-28',data={Aa='Aayu:BAABLgAECn8vAAIBAAgJyxn7NwD+AQABAAgJyxn7NwD+AQAAAA==.',
Ab='Abb:BAAALgAECgIJAgAAAA==.',
Ad='Addieana:BAEBLgAFFH8HAAICAAIJ4hZ2DgCDAAACAAIJ4hZ2DgCDAAABLgAFFAkJRAADAK0mAA==.Adranelidk:BAABLgAECn8tAAICAAkJAhIDBACPAQACAAkJAhIDBACPAQAAAA==.',
Ae='Aeromina:BAABLgAECn8cAAMBAAcJORTOfQBEAQABAAcJORTOfQBEAQAEAAEJZABYnAAKAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgABLgAECggJKAAFANcbAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIGAAgJAxpDNQBNAgAGAAgJAxpDNQBNAgAAAA==.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJDQAAAA==.Alphabet:BAAALgADCgMJBQAAAA==.Alypiia:BAAALgAECgMJAwAAAA==.',
Am='Amadori:BAAALgAECgUJDgAAAA==.',
An='Ancalagon:BAABLgAECn8jAAQHAAgJqCE1BADvAgAHAAgJqCE1BADvAgAIAAgJ2wvZPwAqAQAJAAEJRhbQPAA7AAAAAA==.Angelic:BAAALgAECgYJBwAAAA==.Anguish:BAAALgAECgUJDQAAAA==.Antia:BAAALgAECgQJBAABLgAFFAYJFgAKALgOAA==.',
Ap='April:BAABLgAECn8bAAILAAkJXwW++QC2AAALAAkJXwW++QC2AAAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIEAAIJLxlYGwCqAAAEAAIJLxlYGwCqAAAuAAQKfx8AAgQACQm5IigDAHgDAAQACQm5IigDAHgDAAEuAAUUBAkHAAwAFh0A.',
As='Ashtara:BAAALgADCgMJAwAAAA==.Ashveil:BAABLgAECn8qAAIIAAgJ0w8UNwBTAQAIAAgJ0w8UNwBTAQAAAA==.Asray:BAAALgAECgMJBwABLgAFFAQJEwANABUeAA==.',
At='Athenã:BAAALgADCgEJAQAAAA==.',
Au='Aurillian:BAAALgADCgUJBQAAAA==.Aussie:BAAALgAECgYJBgABLgAFFAMJBAAOAAAAAA==.Aussiesauce:BAAALgAECgUJCgABLgAFFAMJBAAOAAAAAA==.Aussilicious:BAABLgAECn8iAAMPAAkJBRbaHAAxAgAPAAkJBRbaHAAxAgAQAAIJqAQdbwBVAAABLgAFFAMJBAAOAAAAAA==.',
Az='Azerennia:BAABLgAECn8gAAILAAkJCQivFgAOAQALAAkJCQivFgAOAQAAAA==.Azerious:BAAALgAECgIJAwAAAA==.Azreya:BAAALgAECgEJAgAAAA==.Azrokke:BAABLgAECn8WAAIRAAkJwRmnGACEAgARAAkJwRmnGACEAgAAAA==.',
Ba='Babetter:BAABLgAECn8vAAIBAAgJygfGgQA7AQABAAgJygfGgQA7AQAAAA==.Baby:BAAALgAECgYJBgAAAA==.Bacstabbe:BAAALgAECgEJAQAAAA==.Badasbro:BAAALgAECgEJAgAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAAOAAAAAA==.Baelz:BAAALgAECgYJCQAAAA==.Bahamaut:BAAALgAFFAMJBAAAAA==.Balzan:BAAALgADCgYJBwAAAA==.',
Be='Beerless:BAABLgAECn8vAAISAAkJIRVSAgCxAQASAAkJIRVSAgCxAQAAAA==.Belphegör:BAAALgAECgYJDgAAAA==.Bencicil:BAAALgAECgcJDwAAAA==.Berkleyf:BAAALgADCgYJCQABLgAFFAMJBwATADIMAA==.Beydoon:BAAALgAECgMJBwAAAA==.',
Bl='Blindmagg:BAAALgAECgYJCAABLgAECgkJIgABAGogAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgcJCAABLgAECggJDgAOAAAAAA==.',
Br='Brain:BAAALgAECgEJAwAAAA==.Brbtacos:BAAALgAECgQJBAAAAA==.Brewdude:BAAALgADCgcJBwAAAA==.Brewmanchu:BAAALgADCggJDQABLgAECgkJCgAOAAAAAA==.Bro:BAAALgAECgUJEQAAAA==.',
Bu='Bunky:BAAALgAECgMJBgABLgAFFAMJBwATADIMAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8oAAIUAAgJuSA1AgBJAgAUAAgJuSA1AgBJAgAuAAQKfygAAhQACQnuJcMBAIYDABQACQnuJcMBAIYDAAAA.Calayra:BAAALgADCgIJAgAAAA==.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8jAAQPAAgJKhgNKQDiAQAPAAcJDxoNKQDiAQASAAUJGQVXYADBAAAQAAEJ3A7GoQAuAAAAAA==.Carneasadá:BAAALgADCgMJAwAAAA==.Cartheron:BAAALgAECgkJAgAAAA==.',
Ce='Cellynna:BAAALgADCggJFAAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chlonghorn:BAAALgAECgQJBgAAAA==.Chubacka:BAAALgADCgcJBwAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgAAAA==.Crims:BAAALgADCgcJDgABLgADCgcJDgAOAAAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECggJDwAAAA==.',
Cy='Cynla:BAAALgAECgMJAwAAAA==.',
['Cí']='Círce:BAEALgAFFAEJAQABLgAFFAQJEgASABAfAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.Darremiah:BAAALgADCgEJAQAAAA==.David:BAACLgAFFH8OAAILAAMJ7w9WPQDIAAALAAMJ7w9WPQDIAAAuAAQKfygAAgsACQlKHS8nAH4CAAsACQlKHS8nAH4CAAAA.',
Db='Dbsheep:BAAALgAECgMJBgAAAA==.',
De='Deathshand:BAAALgAECgQJBAAAAA==.Dedaedra:BAAALgAECgYJBgABLgAFFAYJFgAKALgOAA==.Deezhealz:BAAALgAECgYJDAAAAA==.Detharian:BAAALgADCgMJAwAAAA==.Dezal:BAAALgADCgIJAgAAAA==.',
Di='Diddyfisting:BAACLgAFFH8wAAMQAAkJux20AADWAgAQAAkJux20AADWAgAPAAEJ8QKVSgAeAAAuAAQKfzAAAxAACQneI5oGAOECABAACQneI5oGAOECABIAAQk6A4mPACYAAAAA.Divinefistin:BAECLgAFFH8SAAISAAQJEB/dFgBrAQASAAQJEB/dFgBrAQAuAAQKfzgAAxIACQnCIi0NAGQCABIACQnLHS0NAGQCABAABwlYIr4RADUCAAAA.Divinepain:BAEALgAECgMJAwABLgAFFAQJEgASABAfAA==.',
Dn='Dnova:BAAALgAECgMJBAAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCwAAAA==.Dornadions:BAAALgAECgYJDgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAABLgAECn8XAAMHAAkJgg6HFACCAQAHAAkJgg6HFACCAQAIAAYJJg7JTQD2AAAAAA==.Draka:BAABLgAECn8VAAIVAAkJaA6UEgCSAQAVAAkJaA6UEgCSAQAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Dreadtide:BAAALgAECgMJBQAAAA==.Drlecter:BAAALgADCgcJDgABLgAECgYJFwAWAC8OAA==.Drunk:BAAALgAECggJDgAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJCAAAAA==.',
Dy='Dymetra:BAAALgAECgEJAQAAAA==.',
['Dö']='Döritö:BAABLgAECn8WAAIMAAcJGgm5EwDWAAAMAAcJGgm5EwDWAAAAAA==.',
Ec='Ecks:BAACLgAFFH8SAAIXAAgJ/RqcCgCGAQAXAAgJ/RqcCgCGAQAuAAQKfzYABBcACQl8HswCADgDABcACQl8HswCADgDABgAAgm3EsEXAHMAABkAAQkAAAqQAAAAAAAA.',
El='Elfuego:BAAALgAECgkJEgAAAA==.Elviraw:BAAALgADCgIJAgABLgAECgkJLwAGAFUIAA==.',
Em='Employee:BAAALgAECgcJDAAAAA==.',
En='Energgy:BAAALgAECgkJCgAAAA==.Enigmanta:BAAALgADCgUJBQAAAA==.',
Ev='Eviljoke:BAAALgADCgkJDwAAAA==.',
Fa='Faeda:BAAALgAECgUJCAAAAA==.Faestaul:BAABLgAECn8jAAIGAAkJEBmlQAAFAgAGAAkJEBmlQAAFAgAAAA==.Fatima:BAAALgAECgEJAgAAAA==.Fatty:BAABLgAFFH8GAAIaAAQJFhJCAgAeAQAaAAQJFhJCAgAeAQABLgAFFAkJQgAIAAggAA==.',
Fe='Fearyourface:BAAALgADCgMJAwAAAA==.Fennecshand:BAAALgADCgMJAwAAAA==.Fenrisulfr:BAAALgADCgYJBgAAAA==.Fentdemon:BAABLgAFFH8HAAMUAAQJkwZCHwCmAAAUAAMJiwZCHwCmAAAMAAIJEQQ9VwAzAAAAAA==.Feoriela:BAAALgADCgIJAwAAAA==.',
Fi='Findinnan:BAABLgAECn8aAAIFAAkJeQVMDQBVAQAFAAkJeQVMDQBVAQAAAA==.Fishtotem:BAAALgADCgcJDQAAAA==.',
Fl='Flor:BAAALgAECgEJAQAAAA==.',
Fr='Freeze:BAAALgAECgYJCQAAAA==.Freezerbern:BAAALgAECggJDwAAAA==.Frissbee:BAAALgADCgMJAwABLgAECgMJAwAOAAAAAA==.Frostblood:BAAALgADCgIJAgAAAA==.Froststd:BAAALgADCgEJAQAAAA==.Fréki:BAAALgAECgIJAgAAAA==.',
Fu='Fullpeny:BAAALgADCgEJAQAAAA==.',
Ga='Gabion:BAAALgADCgQJBAAAAA==.Gamernuts:BAAALgADCggJEAAAAA==.Gametheory:BAAALgAECgIJBwAAAA==.Ganzar:BAACLgAFFH8XAAIbAAQJVR1LJQA3AQAbAAQJVR1LJQA3AQAuAAQKfycAAhsACQmnInoIAC4DABsACQmnInoIAC4DAAAA.Gathan:BAAALgAECgYJCAAAAA==.',
Ge='Genderdruid:BAAALgAECgIJAwAAAA==.Genge:BAABLgAECn9GAAMGAAkJZBRKEQA8AQAGAAkJZBRKEQA8AQAWAAcJKQe7CgDdAAAAAA==.Gertrex:BAABLgAECn8kAAIcAAkJuQuPBwBbAQAcAAkJuQuPBwBbAQAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.Gitchusum:BAAALgAECgcJBgAAAA==.',
Gl='Glennhelen:BAAALgADCgkJDwAAAA==.',
Go='Goatlord:BAABLgAECn8eAAIdAAkJMw85EACuAQAdAAkJMw85EACuAQAAAA==.Goatsavior:BAAALgAECgUJDgAAAA==.Goblinsrhot:BAAALgADCgkJDwAAAA==.Gotharm:BAABLgAECn8bAAIeAAkJswy8GADaAQAeAAkJswy8GADaAQAAAA==.',
Gr='Grester:BAAALgAECggJEwAAAA==.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAABLgAECn8zAAIBAAkJnRxpBQA9AgABAAkJnRxpBQA9AgAAAA==.',
Ha='Haanaa:BAAALgAECgIJAgAAAA==.Hahmicydal:BAABLgAECn8gAAQfAAcJ8giGIACpAAAKAAcJSAadHQDSAAAfAAYJTAiGIACpAAAgAAIJHwJuOQE2AAAAAA==.Hal:BAABLgAECn8oAAIBAAYJ1xLAEwAsAQABAAYJ1xLAEwAsAQAAAA==.Hardcore:BAAALgADCgUJBQAAAA==.Havökush:BAACLgAFFH8JAAIUAAMJIRArGwDJAAAUAAMJIRArGwDJAAAuAAQKfycAAhQACQmBIfsEAPUCABQACQmBIfsEAPUCAAAA.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgAECgEJAgABLgAFFAMJAwAOAAAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAIcAAcJmw22NQA+AQAcAAcJmw22NQA+AQAAAA==.Holyguard:BAACLgAFFH8eAAIWAAgJIwxSEwCUAQAWAAgJIwxSEwCUAQAuAAQKfywAAhYACQkqF5QbACcCABYACQkqF5QbACcCAAAA.Holyhand:BAABLgAECn8UAAIhAAYJAg4DSQAVAQAhAAYJAg4DSQAVAQABLgAFFAgJHgAWACMMAA==.',
Ic='Ickis:BAAALgAECgYJBgABLgAECgkJIgABAGogAA==.',
Il='Ilin:BAAALgAECggJEAAAAA==.Illidres:BAAALgADCgQJBQAAAA==.Ilou:BAAALgAECgcJDQABLgAFFAYJFgAKALgOAA==.',
Im='Immadruid:BAAALgAFFAEJAgAAAA==.',
In='Influenza:BAAALgAECgMJAwAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAABLgAECn80AAIiAAkJ5xejAgAjAgAiAAkJ5xejAgAjAgABLgAECggJFgAYAM0WAA==.',
Is='Isabela:BAABLgAFFH8IAAIMAAIJsyQIZADGAAAMAAIJsyQIZADGAAAAAA==.Isilian:BAAALgADCgUJCAAAAA==.',
Iw='Iwillpull:BAAALgADCgcJAQAAAA==.',
Iy='Iyora:BAAALgADCgUJBQAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Je='Jessika:BAACLgAFFH9CAAMIAAkJCCABAgDxAgAIAAkJCCABAgDxAgAJAAEJygr9CQBTAAAuAAQKfyoAAwgACQmjJfcBAGIDAAgACQmjJfcBAGIDAAkABgmRI78PAN8BAAEuAAUUCQlCAAgACCAA.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgYJCAABLgAFFAkJMAAQALsdAA==.Judyhopondik:BAAALgAECgYJBgAAAA==.Judyhopp:BAABLgAECn8aAAQjAAgJWhYxCAB2AQAjAAcJsBIxCAB2AQALAAcJFxORqQAsAQAiAAEJAADhGAAAAAABLgAFFAkJMAAQALsdAA==.Judyhopps:BAAALgAFFAIJAgABLgAFFAkJMAAQALsdAA==.Judyhoppsimp:BAABLgAFFH8LAAMQAAcJUBSpBABiAQAQAAYJeBapBABiAQAPAAMJmQ2DTQBwAAAAAA==.',
Ka='Kaeln:BAAALgAFFAMJAwABLgAFFAYJEgAjAPMcAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kagronn:BAAALgADCggJCgAAAA==.Kakez:BAAALgAECgEJAQABLgAFFAgJJgAhANwXAA==.Kaluanights:BAAALgAECgEJAwAAAA==.Kalzak:BAABLgAECn8vAAIVAAkJ+RGqAwBGAQAVAAkJ+RGqAwBGAQAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAABLgAECn8ZAAIgAAYJ2wb/vgDNAAAgAAYJ2wb/vgDNAAAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kithiandra:BAAALgADCgIJAgAAAA==.Kiwistunna:BAAALgAECgYJDAABLgAECgkJHAATAOYRAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAABLgAECn8qAAIaAAkJqhAxAQBVAQAaAAkJqhAxAQBVAQAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAAOAAAAAA==.',
Ky='Kylepriestt:BAAALgAECgQJBAAAAA==.',
['Kï']='Kïtana:BAAALgAECgMJBAAAAA==.',
La='Laddyboy:BAAALgADCgMJAwAAAA==.Ladiemacbeth:BAAALgADCgkJDwABLgAECgkJLwAVAPkRAA==.Lanwynne:BAAALgADCgYJBAABLgAECgkJJgABAOIXAA==.Laxion:BAAALgADCgkJGwAAAA==.',
Le='Leafs:BAAALgAECgEJAQAAAA==.Leggo:BAABLgAECn8oAAIWAAcJLhWvBAChAQAWAAcJLhWvBAChAQAAAA==.',
Li='Lidravos:BAAALgAECgEJAQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilfist:BAAALgAECggJEwAAAA==.Lilia:BAACLgAFFH8KAAIGAAMJPwVzhgCmAAAGAAMJPwVzhgCmAAAuAAQKfyEAAwYACAlYHCQqAHwCAAYACAlYHCQqAHwCABYABAnYAX16AI8AAAAA.Lilmorty:BAAALgAECgYJDgABLgAFFAcJIQAEAAcYAA==.',
Ll='Lluvioso:BAACLgAFFH8NAAMbAAMJ4h9ZjADxAAAbAAMJFB9ZjADxAAACAAEJ/iE3OQBRAAAuAAQKfyMAAwIACQnrI1oCAEwDAAIACQlNI1oCAEwDABsAAQkOHzFMAVQAAAAA.',
Lo='Loaf:BAABLgAECn8YAAILAAYJeR3SZQCyAQALAAYJeR3SZQCyAQAAAA==.Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8fAAIkAAcJeByeIgC0AQAkAAcJeByeIgC0AQAAAA==.',
Lr='Lrgmarge:BAAALgAECgMJAwAAAA==.',
Lu='Lucia:BAAALgADCggJDgAAAA==.Lunacy:BAAALgAECgUJBQAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAABLgAECn8lAAILAAgJzQ8UGwDqAAALAAgJzQ8UGwDqAAAAAA==.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwAOAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Marath:BAAALgADCgEJAQAAAA==.Martyra:BAAALgAECgQJBAAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJbhw6HwBKAgABAAgJbhw6HwBKAgAEAAMJ+AWWcQB4AAAAAA==.Maxfield:BAAALgAECggJCAAAAA==.',
Me='Mekkadorque:BAAALgADCgUJBQABLgAECgkJCgAOAAAAAA==.Merien:BAABLgAECn8tAAIBAAkJIQ4mEQBGAQABAAkJIQ4mEQBGAQAAAA==.Meros:BAABLgAECn9DAAIBAAkJHxLRCADRAQABAAkJHxLRCADRAQAAAA==.',
Mi='Miasmá:BAAALgADCgEJAQAAAA==.Minathiel:BAAALgADCgIJAgAAAA==.',
Mo='Monstrosoh:BAAALgAECgUJCQAAAA==.Moonkins:BAAALgAECgEJAQABLgAECgMJAwAOAAAAAA==.Moonstrudels:BAAALgAECgQJBQABLgAFFAMJBAAOAAAAAA==.',
Mt='Mtdewmachine:BAAALgAECgIJAwAAAA==.',
Mu='Muertesdemon:BAAALgADCgUJBQAAAA==.Munstar:BAAALgADCgYJBgAAAA==.Mutagenic:BAAALgADCgEJAQAAAA==.',
Na='Nafari:BAAALgAECgUJBgAAAA==.Narasil:BAAALgAECgEJAQAAAA==.Natea:BAAALgAECgcJDAAAAA==.Nayrb:BAAALgAECgIJAgABLgAFFAMJAwAOAAAAAA==.',
Ne='Nebüla:BAABLgAECn8ZAAISAAkJ+gwAJgB+AQASAAkJ+gwAJgB+AQAAAA==.Necrökush:BAAALgAFFAIJAgAAAA==.Nestro:BAAALgADCgUJBQAAAA==.',
Ni='Nightwinds:BAAALgAECgEJAgAAAA==.Ninajavin:BAAALgAECgUJBQAAAA==.',
No='Norinna:BAAALgAECggJEQABLgAFFAMJCwALANwIAA==.Norlairas:BAAALgADCgUJBQAAAA==.Notsujan:BAAALgADCgYJCQAAAA==.',
Ny='Nyxxalecgos:BAACLgAFFH8GAAIIAAQJxwcVPgDPAAAIAAQJxwcVPgDPAAAuAAQKfyoAAggACAlGFFwFADUBAAgACAlGFFwFADUBAAEuAAUUBQkcAAkANBAA.',
Od='Odiousego:BAACLgAFFH8WAAIKAAYJuA7nAQBVAQAKAAYJuA7nAQBVAQAuAAQKfzEAAgoACQkDIEUAAO0CAAoACQkDIEUAAO0CAAAA.',
Ol='Oldkrusty:BAAALgADCgMJAwAAAA==.',
On='Onyxfïend:BAAALgADCgMJAwAAAA==.',
Oo='Ooryl:BAAALgAECgEJAgAAAA==.',
Op='Opheliajavin:BAAALgAECgEJAQAAAA==.',
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAABLgAECn8kAAILAAkJMhgCNwA8AgALAAkJMhgCNwA8AgAAAA==.',
Pa='Painless:BAABLgAECn8YAAIcAAcJFg0dNQBBAQAcAAcJFg0dNQBBAQAAAA==.',
Pe='Petag:BAAALgADCggJAwABLgAECgkJFwAHAIIOAA==.Pewsmash:BAAALgAECggJDAAAAA==.',
Ph='Phloemie:BAAALgADCgYJCQAAAA==.',
Po='Popeleo:BAAALgAECgYJDAAAAA==.Poronuma:BAAALgAECgEJAQAAAA==.Powerhøuse:BAACLgAFFH8cAAILAAgJUxwFEQBkAgALAAgJUxwFEQBkAgAuAAQKfycAAwsACAlgIp0YABcDAAsACAlgIp0YABcDACIAAQkAAB0RAC4AAAAA.Powerwordhug:BAABLgAECn8tAAIhAAkJnx2zDACbAgAhAAkJnx2zDACbAgAAAA==.',
Pr='Proctolodin:BAACLgAFFH8QAAIGAAMJfhAzMQDGAAAGAAMJfhAzMQDGAAAuAAQKfywAAgYACQkZFkJhAK4BAAYACQkZFkJhAK4BAAAA.',
Pu='Purplefart:BAABLgAECn87AAMlAAkJWhn9AQBOAgAlAAkJWhn9AQBOAgAcAAIJwhziGQBXAAAAAA==.',
Ql='Qlaryx:BAABLgAECn8mAAIBAAkJ4hfACQC6AQABAAkJ4hfACQC6AQAAAA==.',
Qu='Quinner:BAACLgAFFH8SAAIIAAQJcRFiMwD0AAAIAAQJcRFiMwD0AAAuAAQKfzUABAgACQneG/gNAIECAAgACQneG/gNAIECAAcABAm+BTo3ALIAAAkAAwlTC4IuAKUAAAAA.Qut:BAABLgAECn8cAAINAAgJxh3WGgDBAQANAAgJxh3WGgDBAQAAAA==.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Rahomira:BAAALgAECgUJBAAAAA==.Rark:BAAALgAECgEJAQAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAABLgAECn8fAAILAAYJRxxmhwBoAQALAAYJRxxmhwBoAQAAAA==.Renaissa:BAAALgAECgQJBAAAAA==.Restore:BAAALgAECgMJAwAAAA==.',
Ri='Rickle:BAAALgAECgMJAwAAAA==.Riptoe:BAAALgAECgcJCAAAAA==.',
Ro='Roantami:BAAALgADCgUJBQAAAA==.Rokey:BAAALgAFFAIJBAABLgAFFAMJCwALAMcfAA==.Rolling:BAAALgADCgMJAwAAAA==.Ronmaru:BAAALgAECgcJEAAAAA==.Rosejavin:BAAALgAECgEJAQAAAA==.Roxy:BAAALgAECgEJAQAAAA==.',
Ry='Ryujin:BAAALgAECgYJBgABLgAFFAMJBAAOAAAAAA==.',
Sa='Sabel:BAAALgAECgMJAwAAAA==.Sagori:BAAALgAECgEJAgAAAA==.Salina:BAAALgADCgMJAwAAAA==.Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn84AAMgAAgJxxLiWwCKAQAgAAgJWRLiWwCKAQAKAAQJ9xIrFADtAAAAAA==.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAABLgAECn8tAAMYAAkJACG9BQAEAwAYAAkJACG9BQAEAwAXAAMJJxNmCAC0AAAAAA==.Seiken:BAAALgAECggJEgAAAA==.Selas:BAABLgAECn8hAAMCAAYJSBEBKwABAQACAAYJSBEBKwABAQAbAAYJkwkk3QDYAAAAAA==.Seryiana:BAABLgAECn8UAAIfAAcJKxmGDQBlAQAfAAcJKxmGDQBlAQAAAA==.',
Sg='Sgtkabukiman:BAAALgAECgYJDAABLgAECgkJIgABAGogAA==.',
Sh='Shackiechan:BAAALgAECgIJBAAAAA==.Shadowflood:BAAALgAECgMJBAAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBQABLgAECgIJBAAOAAAAAA==.Shnukems:BAAALgAECgMJAwAAAA==.',
Si='Silk:BAABLgAECn8jAAIBAAkJrg/WVgCfAQABAAkJrg/WVgCfAQAAAA==.Silren:BAAALgAECgQJCQAAAA==.Sita:BAAALgADCgkJDwAAAA==.',
Sk='Skippitypaps:BAAALgADCgMJAwAAAA==.Skoldsmoyer:BAAALgADCgUJBQAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAABLgAECn8WAAILAAkJFRIwCwCTAQALAAkJFRIwCwCTAQABLgAFFAMJEAAGAH4QAA==.',
So='Sofferenza:BAAALgADCgcJGwAAAA==.Sorulus:BAAALgAECgEJAgAAAA==.Souldance:BAACLgAFFH8RAAIgAAUJqhbgGwA2AQAgAAUJqhbgGwA2AQAuAAQKfzIAAyAACQm1GDciAFkCACAACQm1GDciAFkCAB8AAwlADq0yAFQAAAAA.Soulslawter:BAAALgADCgUJBQABLgAECgkJLgAhALsYAA==.',
Sp='Spaceguy:BAABLgAECn8kAAITAAkJuQjmPQA9AQATAAkJuQjmPQA9AQAAAA==.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgAFFAIJAwAAAA==.Starwind:BAAALgAECgYJDAAAAA==.Stolock:BAAALgAECgMJAwABLgAECggJGgAmAOgZAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Succupriest:BAAALgAECgIJAgAAAA==.Sugammadex:BAAALgAECgIJBQABLgAECgIJBwAOAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAABLgAECn8fAAMTAAkJ7SEZBwDrAgATAAkJ7SEZBwDrAgARAAIJ9RGuHwBwAAAAAA==.',
Sw='Swato:BAAALgAECgEJAQABLgAECggJEAAOAAAAAA==.',
Sy='Sylaang:BAAALgAECgIJAwAAAA==.',
Ta='Talie:BAAALgADCgYJBQAAAA==.Taliria:BAABLgAECn8eAAIlAAYJehhWJgClAQAlAAYJehhWJgClAQAAAA==.Talladar:BAAALgAECgYJEAAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Tampax:BAAALgAFFAEJAQABLgAFFAMJBAAOAAAAAA==.Tanfurem:BAAALgAECgMJAwAAAA==.Tanny:BAAALgADCgQJAwAAAA==.Targ:BAABLgAECn8iAAIBAAkJaiAMBAB8AgABAAkJaiAMBAB8AgAAAA==.Targantua:BAAALgADCgcJBwAAAA==.',
Te='Tenshiro:BAAALgADCgYJDQAAAA==.Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgAECgYJBgAAAA==.Thugzug:BAAALgAECgcJBwAAAA==.Thundamon:BAAALgAECgEJAQAAAA==.Thunderbeard:BAAALgAECgUJBQAAAA==.',
Ti='Tidefang:BAAALgAFFAEJAQAAAA==.',
To='Toblakai:BAAALgAECgMJAQABLgAECgkJAgAOAAAAAA==.Torryn:BAAALgADCgkJCQAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.Truthteiier:BAAALgAECgEJAwAAAA==.',
Ts='Tsukuyomi:BAAALgADCgEJAQAAAA==.',
Ty='Tyladrillian:BAAALgAECgEJAQAAAA==.',
Tz='Tzaviel:BAAALgAFFAIJAgAAAA==.',
Un='Unholyguard:BAAALgADCgEJAQABLgAFFAgJHgAWACMMAA==.',
Uz='Uzumaki:BAABLgAECn8WAAIQAAgJGBaiGwDTAQAQAAgJGBaiGwDTAQAAAA==.',
Va='Vajrajavin:BAAALgAECgYJDwABLgAECggJKgAIANMPAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAACLgAFFH8eAAIPAAgJ2hWUCgBeAgAPAAgJ2hWUCgBeAgAuAAQKfyUAAg8ACQkhI/EDAHcDAA8ACQkhI/EDAHcDAAAA.Valasca:BAAALgADCgcJBwAAAA==.Valonar:BAAALgAECgYJCQAAAA==.Valonkyr:BAAALgAECgYJBwAAAA==.Valor:BAAALgAECggJEwAAAA==.Vardeath:BAAALgAECgMJAwAAAA==.',
Ve='Veldaan:BAAALgAECggJDAAAAA==.',
Vi='Victra:BAAALgAECgUJBQABLgAECgkJIgABAGogAA==.Vinskey:BAAALgAECgUJBQAAAA==.Vipe:BAAALgAECggJEwAAAA==.Viperlock:BAAALgAECgQJBgAAAA==.Visenyaa:BAAALgADCgEJAQAAAA==.Vita:BAAALgAECgUJBQAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.Voodoochild:BAAALgAFFAIJAgAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECgkJIgABAGogAA==.',
Wa='Waltwitemane:BAAALgAECgEJAwAAAA==.Warliff:BAAALgADCgMJAwAAAA==.',
We='Wetnoodle:BAAALgAECgYJCQAAAA==.',
Wh='Whish:BAABLgAECn8gAAInAAcJFgovbQDtAAAnAAcJFgovbQDtAAAAAA==.Whiteleaf:BAABLgAECn82AAIYAAkJJxK+IADrAQAYAAkJJxK+IADrAQAAAA==.',
Wi='Wisdom:BAAALgADCggJDQABLgAECggJEwAOAAAAAA==.',
Wt='Wtfishéaling:BAAALgAFFAMJAwAAAA==.',
Xe='Xenababy:BAAALgADCgIJAgAAAA==.Xenonga:BAAALgADCgEJAQAAAA==.',
Ye='Yenneth:BAAALgAECgYJEAAAAA==.',
['Yî']='Yîn:BAABLgAECn8YAAIIAAkJeRwxAQB7AgAIAAkJeRwxAQB7AgAAAA==.',
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
