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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Hunter-Marksmanship','Rogue-Assassination','Paladin-Retribution','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warlock-Affliction','Mage-Frost','DemonHunter-Devourer','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','Shaman-Restoration','Unknown-Unknown','Monk-Brewmaster','Shaman-Elemental','DemonHunter-Havoc','Druid-Feral','Warrior-Protection','Warrior-Fury','Warrior-Arms','DeathKnight-Unholy','Paladin-Holy','Priest-Discipline','Shaman-Enhancement','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Priest-Holy','Mage-Fire','Mage-Arcane','Rogue-Outlaw','Druid-Balance','Priest-Shadow','Paladin-Protection','Druid-Restoration',}
local provider = {region='US',realm='Fenris',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aayu:BAABLgAECn8vAAIBAAgJyxn7NwD+AQABAAgJyxn7NwD+AQAAAA==.',
Ad='Addieana:BAABLgAFFH8HAAICAAIJ4hZ2DgCDAAACAAIJ4hZ2DgCDAAAAAA==.Adranelidk:BAABLgAECn8nAAICAAgJTBNKBAAFAQACAAgJTBNKBAAFAQAAAA==.',
Ae='Aeromina:BAABLgAECn8cAAMBAAcJORTOfQBEAQABAAcJORTOfQBEAQADAAEJZABYnAAKAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgABLgAECggJKAAEANcbAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIFAAgJAxpDNQBNAgAFAAgJAxpDNQBNAgAAAA==.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJDQAAAA==.Alphabet:BAAALgADCgMJBQAAAA==.Alypiia:BAAALgAECgMJAwAAAA==.',
Am='Amadori:BAAALgAECgUJCwAAAA==.',
An='Ancalagon:BAABLgAECn8jAAQGAAgJqCE1BADvAgAGAAgJqCE1BADvAgAHAAgJ2wvZPwAqAQAIAAEJRhbQPAA7AAAAAA==.Angelic:BAAALgAECgIJAgAAAA==.Anguish:BAAALgAECgUJDAAAAA==.Antia:BAAALgAECgQJBAABLgAFFAYJEwAJAKMMAA==.',
Ap='April:BAABLgAECn8bAAIKAAkJXwW++QC2AAAKAAkJXwW++QC2AAAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIDAAIJLxlYGwCqAAADAAIJLxlYGwCqAAAuAAQKfx8AAgMACQm5IigDAHgDAAMACQm5IigDAHgDAAEuAAUUBAkHAAsAFh0A.',
As='Ashveil:BAABLgAECn8qAAIHAAgJ0w8UNwBTAQAHAAgJ0w8UNwBTAQAAAA==.Asray:BAAALgAECgMJBwABLgAFFAQJEwAMABUeAA==.',
At='Athenã:BAAALgADCgEJAQAAAA==.',
Au='Aussie:BAAALgAECgYJBgABLgAECgkJIgANAAUWAA==.Aussiesauce:BAAALgAECgUJCgABLgAECgkJIgANAAUWAA==.Aussilicious:BAABLgAECn8iAAMNAAkJBRbaHAAxAgANAAkJBRbaHAAxAgAOAAIJqAQdbwBVAAAAAA==.',
Az='Azerennia:BAABLgAECn8gAAIKAAkJCQjuDQAVAQAKAAkJCQjuDQAVAQAAAA==.Azerious:BAAALgAECgIJAwAAAA==.Azreya:BAAALgAECgEJAgAAAA==.Azrokke:BAABLgAECn8WAAIPAAkJwRmnGACEAgAPAAkJwRmnGACEAgAAAA==.',
Ba='Babetter:BAABLgAECn8uAAIBAAgJ9wbGgQA7AQABAAgJ9wbGgQA7AQAAAA==.Baby:BAAALgAECgYJBgAAAA==.Bacstabbe:BAAALgAECgEJAQAAAA==.Badasbro:BAAALgAECgEJAgAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAAQAAAAAA==.Baelz:BAAALgAECgYJBwAAAA==.Bahamaut:BAAALgAECgQJBgABLgAECgkJIgANAAUWAA==.Balzan:BAAALgADCgYJBwAAAA==.',
Be='Beerless:BAABLgAECn8vAAIRAAkJIRVUAQDNAQARAAkJIRVUAQDNAQAAAA==.Belphegör:BAAALgAECgYJDgAAAA==.Bencicil:BAAALgAECgcJDwAAAA==.Berkleyf:BAAALgADCgYJCQABLgAFFAMJBwASADIMAA==.Beydoon:BAAALgAECgMJBwAAAA==.',
Bl='Blindmagg:BAAALgAECgYJCAABLgAECggJGQABAJAeAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgcJCAABLgAECgcJDgAQAAAAAA==.',
Br='Brain:BAAALgAECgEJAwAAAA==.Brawnhilda:BAAALgADCgcJDAABLgAECgkJJgABAOIXAA==.Brewdude:BAAALgADCgcJBwAAAA==.Brewmanchu:BAAALgADCggJDQABLgAECggJCQAQAAAAAA==.Bro:BAAALgAECgUJEQAAAA==.',
Bu='Bunky:BAAALgAECgMJBgABLgAFFAMJBwASADIMAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8kAAITAAgJuSA1AgBJAgATAAgJuSA1AgBJAgAuAAQKfygAAhMACQnuJcMBAIYDABMACQnuJcMBAIYDAAAA.Calayra:BAAALgADCgIJAgAAAA==.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8jAAQNAAgJKhgNKQDiAQANAAcJDxoNKQDiAQARAAUJGQVXYADBAAAOAAEJ3A7GoQAuAAAAAA==.Cartheron:BAAALgAECgkJAgAAAA==.',
Ce='Cellynna:BAAALgADCggJFAAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgAAAA==.Crims:BAAALgADCgcJDgABLgADCgcJDgAQAAAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECggJDwAAAA==.',
Cy='Cynla:BAAALgAECgMJAwAAAA==.',
['Cí']='Círce:BAEALgAECgUJCAABLgAFFAQJEgARABAfAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.Darremiah:BAAALgADCgEJAQAAAA==.David:BAACLgAFFH8MAAIKAAMJRAs9MgC8AAAKAAMJRAs9MgC8AAAuAAQKfygAAgoACQlKHS8nAH4CAAoACQlKHS8nAH4CAAAA.',
Db='Dbsheep:BAAALgAECgMJBgAAAA==.',
De='Dedaedra:BAAALgAECgYJBgABLgAFFAYJEwAJAKMMAA==.Deezhealz:BAAALgAECgYJDAAAAA==.Dezal:BAAALgADCgIJAgAAAA==.',
Di='Diddyfisting:BAACLgAFFH8iAAMOAAcJlh0XAQAQAgAOAAcJlh0XAQAQAgANAAEJ8QKWOwAgAAAuAAQKfzAAAw4ACQneI5oGAOECAA4ACQneI5oGAOECABEAAQk6A4mPACYAAAAA.Divinefistin:BAECLgAFFH8SAAIRAAQJEB/dFgBrAQARAAQJEB/dFgBrAQAuAAQKfzgAAxEACQnCIi0NAGQCABEACQnLHS0NAGQCAA4ABwlYIr4RADUCAAAA.Divinepain:BAEALgAECgMJAwABLgAFFAQJEgARABAfAA==.',
Dn='Dnova:BAAALgAECgMJBAAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCwAAAA==.Dornadions:BAAALgAECgYJDgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAABLgAECn8XAAMGAAkJgg6HFACCAQAGAAkJgg6HFACCAQAHAAYJJg7JTQD2AAAAAA==.Draka:BAABLgAECn8VAAIUAAkJaA6UEgCSAQAUAAkJaA6UEgCSAQAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Dreadtide:BAAALgAECgMJAwAAAA==.Drunk:BAAALgAECgcJDgAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJCAAAAA==.',
Dy='Dymetra:BAAALgAECgEJAQAAAA==.',
['Dö']='Döritö:BAABLgAECn8WAAILAAcJGgn5CwDnAAALAAcJGgn5CwDnAAAAAA==.',
Ec='Ecks:BAACLgAFFH8SAAIVAAgJ/RqcCgCGAQAVAAgJ/RqcCgCGAQAuAAQKfzUABBUACQl8HswCADgDABUACQl8HswCADgDABYAAgm3Et0PAHIAABcAAQkAAAqQAAAAAAAA.',
El='Elfuego:BAAALgAECggJDQAAAA==.',
Em='Employee:BAAALgAECgcJCwAAAA==.',
En='Energgy:BAAALgAECgkJCgAAAA==.Enigmanta:BAAALgADCgUJBQAAAA==.',
Ev='Eviljoke:BAAALgADCgkJDwAAAA==.',
Fa='Faeda:BAAALgAECgUJCAAAAA==.Faestaul:BAABLgAECn8jAAIFAAkJEBmlQAAFAgAFAAkJEBmlQAAFAgAAAA==.Fatima:BAAALgAECgEJAgAAAA==.Fatty:BAAALgAFFAIJAwABLgAFFAkJLQAHANsbAA==.',
Fe='Fearyourface:BAAALgADCgMJAwAAAA==.Fenrisulfr:BAAALgADCgYJBgAAAA==.Fentdemon:BAABLgAFFH8GAAMTAAMJiwZFDwBwAAATAAMJiwZFDwBwAAALAAEJeAEPrQAlAAAAAA==.',
Fi='Findinnan:BAABLgAECn8aAAIEAAkJeQVMDQBVAQAEAAkJeQVMDQBVAQAAAA==.Fishtotem:BAAALgADCgcJDQAAAA==.',
Fl='Flor:BAAALgAECgEJAQAAAA==.',
Fr='Freeze:BAAALgAECgYJCQAAAA==.Freezerbern:BAAALgAECggJDwAAAA==.Frissbee:BAAALgADCgMJAwABLgAECgMJAwAQAAAAAA==.Frostblood:BAAALgADCgIJAgAAAA==.Froststd:BAAALgADCgEJAQAAAA==.Fréki:BAAALgAECgIJAgAAAA==.',
Fu='Fullpeny:BAAALgADCgEJAQAAAA==.',
Ga='Gametheory:BAAALgAECgIJBwAAAA==.Ganzar:BAACLgAFFH8XAAIYAAQJVR3bFgBaAQAYAAQJVR3bFgBaAQAuAAQKfycAAhgACQmnInoIAC4DABgACQmnInoIAC4DAAAA.Gathan:BAAALgAECgYJBgAAAA==.',
Ge='Genderdruid:BAAALgAECgIJAwAAAA==.Genge:BAABLgAECn89AAMFAAgJnRMHEQDsAAAFAAgJnRMHEQDsAAAZAAIJewYvEgAvAAAAAA==.Gertrex:BAABLgAECn8kAAIaAAkJuQt0BABZAQAaAAkJuQt0BABZAQAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.Gitchusum:BAAALgAECgcJBgAAAA==.',
Gl='Glennhelen:BAAALgADCgkJDwAAAA==.',
Go='Goatlord:BAABLgAECn8eAAIbAAkJMw85EACuAQAbAAkJMw85EACuAQAAAA==.Goatsavior:BAAALgAECgUJDgAAAA==.Goblinsrhot:BAAALgADCgkJDwAAAA==.Gotharm:BAABLgAECn8bAAIcAAkJswy8GADaAQAcAAkJswy8GADaAQAAAA==.',
Gr='Grester:BAAALgAECggJEwAAAA==.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAABLgAECn8nAAIBAAYJ9SBbCQBjAQABAAYJ9SBbCQBjAQAAAA==.',
Ha='Haanaa:BAAALgAECgIJAgAAAA==.Hahmicydal:BAABLgAECn8gAAQdAAcJ8giGIACpAAAJAAcJSAadHQDSAAAdAAYJTAiGIACpAAAeAAIJHwJuOQE2AAAAAA==.Hal:BAABLgAECn8bAAIBAAYJHAxaEAD/AAABAAYJHAxaEAD/AAAAAA==.Hardcore:BAAALgADCgUJBQAAAA==.Havökush:BAACLgAFFH8JAAITAAMJIRArGwDJAAATAAMJIRArGwDJAAAuAAQKfycAAhMACQmBIfsEAPUCABMACQmBIfsEAPUCAAAA.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgAECgEJAgABLgAFFAMJAwAQAAAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAIaAAcJmw22NQA+AQAaAAcJmw22NQA+AQAAAA==.Holyguard:BAACLgAFFH8dAAIZAAcJWA1SEwCUAQAZAAcJWA1SEwCUAQAuAAQKfywAAhkACQkqF5QbACcCABkACQkqF5QbACcCAAAA.Holyhand:BAABLgAECn8UAAIfAAYJAg4DSQAVAQAfAAYJAg4DSQAVAQABLgAFFAcJHQAZAFgNAA==.',
Ic='Ickis:BAAALgAECgYJBgABLgAECggJGQABAJAeAA==.',
Il='Ilin:BAAALgAECggJEAAAAA==.Illidres:BAAALgADCgQJBQAAAA==.Ilou:BAAALgAECgcJDQABLgAFFAYJEwAJAKMMAA==.',
In='Influenza:BAAALgAECgMJAwAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAABLgAECn80AAIgAAkJ5xejAgAjAgAgAAkJ5xejAgAjAgABLgAECggJFgAWAM0WAA==.',
Is='Isabela:BAABLgAFFH8IAAILAAIJsyQIZADGAAALAAIJsyQIZADGAAAAAA==.Isilian:BAAALgADCgUJCAAAAA==.',
Iw='Iwillpull:BAAALgADCgcJAQAAAA==.',
Iy='Iyora:BAAALgADCgUJBQAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgYJCAABLgAFFAcJIgAOAJYdAA==.Judyhopondik:BAAALgAECgYJBgAAAA==.Judyhopp:BAABLgAECn8aAAQhAAgJWhYxCAB2AQAhAAcJsBIxCAB2AQAKAAcJFxORqQAsAQAgAAEJAADhGAAAAAABLgAFFAcJIgAOAJYdAA==.Judyhopps:BAAALgAFFAIJAgABLgAFFAcJIgAOAJYdAA==.Judyhoppsimp:BAABLgAFFH8LAAMOAAcJUBRWAgCDAQAOAAYJeBZWAgCDAQANAAMJmQ2DTQBwAAAAAA==.',
Ka='Kaeln:BAAALgAFFAMJAwABLgAFFAYJEgAhAPMcAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kagronn:BAAALgADCggJCgAAAA==.Kakez:BAAALgAECgEJAQABLgAFFAgJJgAfANwXAA==.Kaluanights:BAAALgAECgEJAgAAAA==.Kalzak:BAABLgAECn8vAAIUAAkJ+RHtAQBgAQAUAAkJ+RHtAQBgAQAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAABLgAECn8ZAAIeAAYJ2wb/vgDNAAAeAAYJ2wb/vgDNAAAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kithiandra:BAAALgADCgIJAgAAAA==.Kiwistunna:BAAALgAECgYJDAABLgAECgkJHAASAOYRAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAABLgAECn8qAAIiAAkJqhDAAABUAQAiAAkJqhDAAABUAQAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAAQAAAAAA==.',
Ky='Kylepriestt:BAAALgAECgQJBAAAAA==.',
['Kï']='Kïtana:BAAALgAECgMJBAAAAA==.',
La='Laddyboy:BAAALgADCgMJAwAAAA==.Ladiemacbeth:BAAALgADCgkJDwABLgAECgkJLwAUAPkRAA==.Lanwynne:BAAALgADCgYJBAABLgAECgkJJgABAOIXAA==.Laxion:BAAALgADCgkJGwAAAA==.',
Le='Leafs:BAAALgAECgEJAQAAAA==.Leggo:BAABLgAECn8eAAIZAAYJfhFiPgBLAQAZAAYJfhFiPgBLAQAAAA==.',
Li='Lidravos:BAAALgAECgEJAQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilfist:BAAALgAECgYJDAAAAA==.Lilia:BAACLgAFFH8KAAIFAAMJPwVzhgCmAAAFAAMJPwVzhgCmAAAuAAQKfyEAAwUACAlYHCQqAHwCAAUACAlYHCQqAHwCABkABAnYAX16AI8AAAAA.Lilmorty:BAAALgAECgYJDgABLgAFFAcJGwADAAcYAA==.',
Ll='Lluvioso:BAACLgAFFH8NAAMYAAMJ4h9ZjADxAAAYAAMJFB9ZjADxAAACAAEJ/iE3OQBRAAAuAAQKfyMAAwIACQnrI1oCAEwDAAIACQlNI1oCAEwDABgAAQkOHzFMAVQAAAAA.',
Lo='Loaf:BAABLgAECn8YAAIKAAYJeR3SZQCyAQAKAAYJeR3SZQCyAQAAAA==.Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8fAAIjAAcJeByeIgC0AQAjAAcJeByeIgC0AQAAAA==.',
Lu='Lucia:BAAALgADCggJDgAAAA==.Lunacy:BAAALgAECgUJBQAAAA==.Lunarbelle:BAAALgADCgkJDwAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAABLgAECn8lAAIKAAgJzQ/jEADzAAAKAAgJzQ/jEADzAAAAAA==.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwAQAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Marath:BAAALgADCgEJAQAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJbhw6HwBKAgABAAgJbhw6HwBKAgADAAMJ+AWWcQB4AAAAAA==.',
Me='Mekkadorque:BAAALgADCgUJBQABLgAECggJCQAQAAAAAA==.Merien:BAABLgAECn8nAAIBAAgJAAk9iwAoAQABAAgJAAk9iwAoAQAAAA==.Meros:BAABLgAECn8tAAIBAAgJSg5+CAB1AQABAAgJSg5+CAB1AQAAAA==.',
Mi='Minathiel:BAAALgADCgIJAgAAAA==.',
Mo='Monstrosoh:BAAALgAECgUJCQAAAA==.Moonkins:BAAALgAECgEJAQABLgAECgMJAwAQAAAAAA==.Moonstrudels:BAAALgAECgQJBQABLgAECgkJIgANAAUWAA==.',
Mt='Mtdewmachine:BAAALgAECgIJAwAAAA==.',
Mu='Muertesdemon:BAAALgADCgUJBQAAAA==.Munstar:BAAALgADCgYJBgAAAA==.Mutagenic:BAAALgADCgEJAQAAAA==.',
Na='Nafari:BAAALgAECgUJBgAAAA==.Narasil:BAAALgAECgEJAQAAAA==.Natea:BAAALgAECgcJDAAAAA==.Nayrb:BAAALgAECgIJAgABLgAFFAMJAwAQAAAAAA==.',
Ne='Nebüla:BAABLgAECn8ZAAIRAAkJ+gwAJgB+AQARAAkJ+gwAJgB+AQAAAA==.Necrökush:BAAALgAFFAIJAgAAAA==.Nestro:BAAALgADCgUJBQAAAA==.',
Ni='Nightwinds:BAAALgAECgEJAgAAAA==.Ninajavin:BAAALgAECgUJBQAAAA==.',
No='Norinna:BAAALgAECggJEQABLgAFFAMJCwAKANwIAA==.Norlairas:BAAALgADCgUJBQAAAA==.Notsujan:BAAALgADCgYJCQAAAA==.',
Ny='Nyxxalecgos:BAACLgAFFH8GAAIHAAQJxwcVPgDPAAAHAAQJxwcVPgDPAAAuAAQKfyoAAgcACAlGFEoDAEMBAAcACAlGFEoDAEMBAAEuAAUUBQkZAAgAhA8A.',
Od='Odiousego:BAACLgAFFH8TAAIJAAYJowzrAABjAQAJAAYJowzrAABjAQAuAAQKfyMAAgkACAlFGlwFADQCAAkACAlFGlwFADQCAAAA.',
Ol='Oldkrusty:BAAALgADCgMJAwAAAA==.',
On='Onyxfïend:BAAALgADCgMJAwAAAA==.',
Oo='Ooryl:BAAALgAECgEJAgAAAA==.',
Op='Opheliajavin:BAAALgAECgEJAQAAAA==.',
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAABLgAECn8hAAIKAAkJNhYCNwA8AgAKAAkJNhYCNwA8AgAAAA==.',
Pa='Painless:BAABLgAECn8YAAIaAAcJFg0dNQBBAQAaAAcJFg0dNQBBAQAAAA==.',
Pe='Pewsmash:BAAALgAECgcJCwAAAA==.',
Ph='Phloemie:BAAALgADCgYJCQAAAA==.',
Po='Popeleo:BAAALgAECgMJBgAAAA==.Poronuma:BAAALgADCgEJAQAAAA==.Powerhøuse:BAACLgAFFH8cAAIKAAgJUxwFEQBkAgAKAAgJUxwFEQBkAgAuAAQKfycAAwoACAlgIp0YABcDAAoACAlgIp0YABcDACAAAQkAAB0RAC4AAAAA.Powerwordhug:BAABLgAECn8tAAIfAAkJnx2zDACbAgAfAAkJnx2zDACbAgAAAA==.',
Pr='Priestítute:BAAALgAECgIJAgAAAA==.Proctolodin:BAACLgAFFH8JAAIFAAMJbgs0dgDIAAAFAAMJbgs0dgDIAAAuAAQKfywAAgUACQkZFkJhAK4BAAUACQkZFkJhAK4BAAAA.',
Pu='Purplefart:BAABLgAECn8xAAMkAAkJ/Bb3AwBSAQAkAAkJ/Bb3AwBSAQAaAAIJwhx/EABYAAAAAA==.',
Ql='Qlaryx:BAABLgAECn8mAAIBAAkJ4hdNBQDNAQABAAkJ4hdNBQDNAQAAAA==.',
Qu='Quinner:BAACLgAFFH8SAAIHAAQJcRFiMwD0AAAHAAQJcRFiMwD0AAAuAAQKfzUABAcACQneG/gNAIECAAcACQneG/gNAIECAAYABAm+BTo3ALIAAAgAAwlTC4IuAKUAAAAA.Qut:BAABLgAECn8cAAIMAAgJxh3WGgDBAQAMAAgJxh3WGgDBAQAAAA==.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Rark:BAAALgAECgEJAQAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAABLgAECn8eAAIKAAYJRxxmhwBoAQAKAAYJRxxmhwBoAQAAAA==.Renaissa:BAAALgAECgQJBAAAAA==.Restore:BAAALgAECgMJAwAAAA==.',
Ri='Rickle:BAAALgAECgMJAwAAAA==.Riptoe:BAAALgAECgcJCAAAAA==.',
Ro='Roantami:BAAALgADCgUJBQAAAA==.Rokey:BAAALgAFFAEJAgAAAA==.Rolling:BAAALgADCgMJAwAAAA==.Ronmaru:BAAALgAECgcJEAAAAA==.Rosejavin:BAAALgAECgEJAQAAAA==.Roxy:BAAALgAECgEJAQAAAA==.',
Ry='Ryujin:BAAALgAECgYJBgABLgAECgkJIgANAAUWAA==.',
Sa='Sabel:BAAALgAECgMJAwAAAA==.Sagori:BAAALgAECgEJAgAAAA==.Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn84AAMeAAgJxxLiWwCKAQAeAAgJWRLiWwCKAQAJAAQJ9xIrFADtAAAAAA==.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAABLgAECn8tAAMWAAkJACG9BQAEAwAWAAkJACG9BQAEAwAVAAMJJxMoBQC7AAAAAA==.Seiken:BAAALgAECggJEgAAAA==.Selas:BAABLgAECn8hAAMCAAYJSBEBKwABAQACAAYJSBEBKwABAQAYAAYJkwkk3QDYAAAAAA==.Seryiana:BAAALgAECgcJEwAAAA==.',
Sg='Sgtkabukiman:BAAALgAECgYJDAABLgAECggJGQABAJAeAA==.',
Sh='Shackiechan:BAAALgAECgIJBAAAAA==.Shadowflood:BAAALgAECgMJBAAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBQABLgAECgIJBAAQAAAAAA==.',
Si='Silk:BAABLgAECn8jAAIBAAkJrg/WVgCfAQABAAkJrg/WVgCfAQAAAA==.Silren:BAAALgAECgQJCQAAAA==.Sita:BAAALgADCgkJDwAAAA==.',
Sk='Skoldsmoyer:BAAALgADCgUJBQAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAABLgAECn8WAAIKAAkJFRJMBgCiAQAKAAkJFRJMBgCiAQABLgAFFAMJCQAFAG4LAA==.',
So='Sofferenza:BAAALgADCgcJGwAAAA==.Sorulus:BAAALgAECgEJAgAAAA==.Souldance:BAACLgAFFH8GAAIeAAQJKg7EFgAXAQAeAAQJKg7EFgAXAQAuAAQKfzEAAx4ACQlWGDciAFkCAB4ACQlWGDciAFkCAB0AAwlADq0yAFQAAAAA.Soulslawter:BAAALgADCgUJBQABLgAECgkJLQAfALsYAA==.',
Sp='Spaceguy:BAABLgAECn8kAAISAAkJuQjmPQA9AQASAAkJuQjmPQA9AQAAAA==.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgAFFAIJAwAAAA==.Starwind:BAAALgAECgYJDAAAAA==.Stolock:BAAALgAECgMJAwABLgAECggJGgAlAOgZAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Sugammadex:BAAALgAECgIJBQABLgAECgIJBwAQAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAABLgAECn8fAAMSAAkJ7SEZBwDrAgASAAkJ7SEZBwDrAgAPAAIJ9RFVFQBqAAAAAA==.',
Sw='Swato:BAAALgAECgEJAQABLgAECggJEAAQAAAAAA==.',
Sy='Sylaang:BAAALgAECgIJAwAAAA==.',
Ta='Talie:BAAALgADCgYJBQAAAA==.Taliria:BAABLgAECn8eAAIkAAYJehhWJgClAQAkAAYJehhWJgClAQAAAA==.Talladar:BAAALgAECgYJEAAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Tampax:BAAALgAECggJCQABLgAECgkJIgANAAUWAA==.Targ:BAABLgAECn8ZAAIBAAgJkB70LwAcAgABAAgJkB70LwAcAgAAAA==.',
Te='Tenshiro:BAAALgADCgYJDQAAAA==.Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgAECgYJBgAAAA==.Thugzug:BAAALgADCgkJDgAAAA==.Thundamon:BAAALgAECgEJAQAAAA==.Thunderbeard:BAAALgAECgUJBQAAAA==.',
Ti='Tidefang:BAAALgAFFAEJAQAAAA==.',
To='Toblakai:BAAALgAECgMJAQABLgAECgkJAgAQAAAAAA==.Torryn:BAAALgADCgkJCQAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.Truthteiier:BAAALgAECgEJAwAAAA==.',
Ty='Tyladrillian:BAAALgAECgEJAQAAAA==.',
Tz='Tzaviel:BAAALgAECgEJAQAAAA==.',
Un='Unholyguard:BAAALgADCgEJAQABLgAFFAcJHQAZAFgNAA==.',
Uz='Uzumaki:BAABLgAECn8WAAIOAAgJGBaiGwDTAQAOAAgJGBaiGwDTAQAAAA==.',
Va='Vajrajavin:BAAALgAECgYJDwABLgAECggJKgAHANMPAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAACLgAFFH8eAAINAAgJ2hWUCgBeAgANAAgJ2hWUCgBeAgAuAAQKfyUAAg0ACQkhI/EDAHcDAA0ACQkhI/EDAHcDAAAA.Valasca:BAAALgADCgcJBwAAAA==.Valonar:BAAALgAECgYJCQAAAA==.Valonkyr:BAAALgAECgYJBwAAAA==.Valor:BAAALgAECggJEwAAAA==.Vardeath:BAAALgAECgMJAwAAAA==.',
Ve='Veldaan:BAAALgAECgQJBQAAAA==.',
Vi='Victra:BAAALgAECgUJBQABLgAECggJGQABAJAeAA==.Vinskey:BAAALgAECgUJBQAAAA==.Vipe:BAAALgAECggJEwAAAA==.Viperlock:BAAALgAECgIJAgAAAA==.Visenyaa:BAAALgADCgEJAQAAAA==.Vita:BAAALgAECgUJBQAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.Voodoochild:BAAALgAFFAIJAgAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECggJGQABAJAeAA==.',
Wa='Waltwitemane:BAAALgAECgEJAwAAAA==.Warliff:BAAALgADCgMJAwAAAA==.',
Wh='Whish:BAABLgAECn8dAAImAAcJFgovbQDtAAAmAAcJFgovbQDtAAAAAA==.Whiteleaf:BAABLgAECn82AAIWAAkJJxK+IADrAQAWAAkJJxK+IADrAQAAAA==.',
Wi='Wisdom:BAAALgADCggJDQABLgAECggJEwAQAAAAAA==.',
Wt='Wtfishéaling:BAAALgAFFAMJAwAAAA==.',
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
