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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Rogue-Assassination','Paladin-Retribution','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','DemonHunter-Devourer','Unknown-Unknown','Monk-Brewmaster','Shaman-Elemental','DemonHunter-Havoc','Monk-Mistweaver','Monk-Windwalker','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Paladin-Holy','Priest-Discipline','Shaman-Enhancement','Hunter-Survival','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Priest-Holy','Mage-Fire','Mage-Arcane','Druid-Feral','Rogue-Outlaw','Druid-Balance','Priest-Shadow','Rogue-Subtlety','Warrior-Fury','Paladin-Protection','Druid-Restoration',}
local provider = {region='US',realm='Fenris',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aayu:BAABLgAECn8uAAIBAAgJyxnnLgAKAgABAAgJyxnnLgAKAgAAAA==.',
Ad='Addie:BAEBLgAFFH8GAAICAAIJ4hZ2DgCDAAACAAIJ4hZ2DgCDAAABLgAFFAkJLgADAKIjAA==.Adranelidk:BAABLgAECn8UAAICAAYJbA6hLADcAAACAAYJbA6hLADcAAAAAA==.',
Ae='Aeromina:BAABLgAECn8bAAMBAAcJ/BMPcABIAQABAAcJ/BMPcABIAQAEAAEJZABYnAAKAAAAAA==.',
Af='Afatpanda:BAAALgADCgcJBwAAAA==.',
Ag='Agert:BAAALgADCgcJCwAAAA==.',
Ai='Aikar:BAAALgAECgIJAgABLgAECggJKAAFANcbAA==.',
Aj='Ajudicater:BAABLgAECn8XAAIGAAgJAxpDNQBNAgAGAAgJAxpDNQBNAgAAAA==.',
Ak='Akame:BAAALgADCgYJBgAAAA==.',
Al='Alcyonfax:BAAALgADCgYJCAAAAA==.Alkurn:BAAALgADCgYJDQAAAA==.Alphabet:BAAALgADCgMJBQAAAA==.Alypiia:BAAALgAECgIJAgAAAA==.',
Am='Amadori:BAAALgAECgEJAQAAAA==.',
An='Ancalagon:BAABLgAECn8hAAQHAAgJgiD2AwDnAgAHAAgJgiD2AwDnAgAIAAgJ2wtoOgAhAQAJAAEJRhbQPAA7AAAAAA==.Angelic:BAAALgAECgIJAgAAAA==.Anguish:BAAALgAECgUJBgAAAA==.',
Ap='April:BAABLgAECn8bAAIKAAkJXwUQ5ACyAAAKAAkJXwUQ5ACyAAAAAA==.',
Ar='Arahi:BAAALgADCgUJBwAAAA==.Arikaza:BAAALgADCgcJCgAAAA==.Arima:BAACLgAFFH8GAAIEAAIJLxlYGwCqAAAEAAIJLxlYGwCqAAAuAAQKfx8AAgQACQm5IigDAHgDAAQACQm5IigDAHgDAAAA.',
As='Ashveil:BAABLgAECn8qAAIIAAgJ0w/wMQBOAQAIAAgJ0w/wMQBOAQAAAA==.Asray:BAAALgAECgMJBgABLgAFFAMJBAALAIwNAA==.',
At='Athenã:BAAALgADCgEJAQAAAA==.',
Au='Aussiesauce:BAAALgAECgUJBQABLgAECggJEgAMAAAAAA==.Aussilicious:BAAALgAECggJEgAAAA==.',
Az='Azerennia:BAAALgAECgcJCgAAAA==.Azerious:BAAALgAECgIJAgAAAA==.Azreya:BAAALgAECgEJAgAAAA==.Azrokke:BAAALgAECggJDwAAAA==.',
Ba='Babetter:BAABLgAECn8sAAIBAAgJRQaQeAA1AQABAAgJRQaQeAA1AQAAAA==.Baby:BAAALgAECgYJBgAAAA==.Bacstabbe:BAAALgAECgEJAQAAAA==.Badderdragon:BAAALgADCgYJDAABLgAECgUJDAAMAAAAAA==.Bahamaut:BAAALgAECgQJBgABLgAECggJEgAMAAAAAA==.Balzan:BAAALgADCgYJBwAAAA==.',
Be='Beerless:BAABLgAECn8ZAAINAAgJvhFOIwB+AQANAAgJvhFOIwB+AQAAAA==.Belphegör:BAAALgAECgYJDQAAAA==.Bencicil:BAAALgAECgcJDwAAAA==.Berkleyf:BAAALgADCgYJCQABLgAFFAMJBgAOADIMAA==.Beydoon:BAAALgAECgMJBgAAAA==.',
Bl='Blindmagg:BAAALgAECgYJCAABLgAECggJFQABAAkdAA==.',
Bo='Bobmb:BAAALgADCgQJBAAAAA==.Botrollsnifr:BAAALgADCgcJCAABLgAECgcJDAAMAAAAAA==.',
Br='Brain:BAAALgAECgEJAwAAAA==.Brawnhilda:BAAALgADCgcJDAABLgAECggJEQAMAAAAAA==.Brewdude:BAAALgADCgcJBwAAAA==.Brewmanchu:BAAALgADCggJCAABLgAECgcJCAAMAAAAAA==.Bro:BAAALgAECgUJDQAAAA==.',
Bu='Bunky:BAAALgAECgMJBgABLgAFFAMJBgAOADIMAA==.Buongiorno:BAAALgAECgUJCAAAAA==.',
Bw='Bwonsamdii:BAAALgADCgYJCwAAAA==.',
Ca='Cair:BAACLgAFFH8ZAAIPAAcJzSOCAQAfAgAPAAcJzSOCAQAfAgAuAAQKfygAAg8ACQnuJcMBAIYDAA8ACQnuJcMBAIYDAAAA.Calayra:BAAALgADCgIJAgAAAA==.Calot:BAAALgADCgcJDQAAAA==.Camili:BAABLgAECn8jAAQQAAgJKhgxIgDjAQAQAAcJDxoxIgDjAQANAAUJGQVXYADBAAARAAEJ3A4FjgAwAAAAAA==.Cartheron:BAAALgAECgkJAgAAAA==.',
Ce='Cellynna:BAAALgADCggJFAAAAA==.Cevious:BAAALgAECgIJAgAAAA==.',
Ch='Chappers:BAAALgAECgYJDAAAAA==.Chuleton:BAAALgAECgEJAQAAAA==.',
Co='Colamachine:BAAALgADCgcJEgAAAA==.Coldcaster:BAAALgADCgYJCAAAAA==.',
Cr='Crim:BAAALgADCgcJDgAAAA==.Crims:BAAALgADCgcJDgABLgADCgcJDgAMAAAAAA==.Cronja:BAAALgADCgMJBgAAAA==.',
Cu='Cuffaladin:BAAALgAECggJDwAAAA==.',
Cy='Cynla:BAAALgAECgMJAwAAAA==.',
Da='Daddybear:BAAALgADCgQJBAAAAA==.Dangerdoomed:BAAALgAECgIJAgAAAA==.Darremiah:BAAALgADCgEJAQAAAA==.David:BAABLgAECn8oAAIKAAkJSh3QIQCBAgAKAAkJSh3QIQCBAgAAAA==.',
Db='Dbsheep:BAAALgAECgMJBAAAAA==.',
De='Deezhealz:BAAALgAECgYJDAAAAA==.Dezal:BAAALgADCgIJAgAAAA==.',
Di='Diddyfisting:BAACLgAFFH8aAAIRAAUJwCVbBAC1AQARAAUJwCVbBAC1AQAuAAQKfzAAAxEACQneI1QFAOsCABEACQneI1QFAOsCAA0AAQk6A4mPACYAAAAA.Divinefistin:BAECLgAFFH8KAAINAAMJqBzTIwAIAQANAAMJqBzTIwAIAQAuAAQKfzYAAw0ACQmMIqkLAGkCAA0ACQnLHakLAGkCABEABwkPIlIQADECAAAA.Divinepain:BAEALgAECgMJAwABLgAFFAMJCgANAKgcAA==.',
Dn='Dnova:BAAALgAECgMJBAAAAA==.',
Do='Dochypnotic:BAAALgAECgUJCwAAAA==.Dornadions:BAAALgAECgYJDgAAAA==.Dozzer:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpet:BAAALgAECggJDQAAAA==.Draka:BAAALgAECgcJEwAAAA==.Drdarksied:BAAALgAECgQJBAAAAA==.Drunk:BAAALgAECgcJDAAAAA==.',
Du='Dubb:BAAALgADCgQJBAAAAA==.Durto:BAAALgAECgQJCAAAAA==.',
Ec='Ecks:BAACLgAFFH8QAAISAAYJ6Ru+CQBrAQASAAYJ6Ru+CQBrAQAuAAQKfzMAAxIACQl8HswCADgDABIACQl8HswCADgDABMAAQkAADV8AAAAAAAA.',
El='Elfuego:BAAALgAECgcJCwAAAA==.',
Em='Employee:BAAALgAECgcJCwAAAA==.',
En='Energgy:BAAALgAECgkJCgAAAA==.Enigmanta:BAAALgADCgUJBQAAAA==.',
Er='Erodorina:BAAALgAECgIJAgAAAA==.',
Ev='Eviljoke:BAAALgADCgkJDwAAAA==.',
Fa='Faeda:BAAALgAECgUJCAAAAA==.Faestaul:BAABLgAECn8eAAIGAAgJtxZYRgDbAQAGAAgJtxZYRgDbAQAAAA==.Fatima:BAAALgAECgEJAgAAAA==.',
Fe='Fearyourface:BAAALgADCgMJAwAAAA==.Fenrisulfr:BAAALgADCgYJBgAAAA==.Fentdemon:BAAALgAECgEJAQAAAA==.',
Fi='Findinnan:BAABLgAECn8ZAAIFAAgJJgUKDwAjAQAFAAgJJgUKDwAjAQAAAA==.Fishtotem:BAAALgADCgcJDQAAAA==.',
Fl='Flor:BAAALgAECgEJAQAAAA==.',
Fr='Freeze:BAAALgAECgYJCQAAAA==.Freezerbern:BAAALgAECggJDwAAAA==.Frissbee:BAAALgADCgMJAwABLgAECgMJAwAMAAAAAA==.Frostblood:BAAALgADCgIJAgAAAA==.Froststd:BAAALgADCgEJAQAAAA==.Fréki:BAAALgAECgIJAgAAAA==.',
Fu='Fullpeny:BAAALgADCgEJAQAAAA==.',
Ga='Gametheory:BAAALgAECgIJBwAAAA==.Ganzar:BAACLgAFFH8NAAIUAAMJtyTaSgA8AQAUAAMJtyTaSgA8AQAuAAQKfyUAAhQACQkpILQLAP8CABQACQkpILQLAP8CAAAA.Gathan:BAAALgADCgcJFgAAAA==.',
Ge='Genderdruid:BAAALgAECgEJAQAAAA==.Genge:BAABLgAECn8vAAMGAAgJaBJDXwCZAQAGAAgJaBJDXwCZAQAVAAEJIQP6iAArAAAAAA==.Gertrex:BAABLgAECn8UAAIWAAgJWQvgJwBuAQAWAAgJWQvgJwBuAQAAAA==.',
Gi='Gilbertgrape:BAAALgADCgMJAwAAAA==.Gitchusum:BAAALgAECgcJBgAAAA==.',
Gl='Glennhelen:BAAALgADCgkJDwAAAA==.',
Go='Goatlord:BAABLgAECn8eAAIXAAkJMw/VDQC2AQAXAAkJMw/VDQC2AQAAAA==.Goatsavior:BAAALgAECgUJDgAAAA==.Goblinsrhot:BAAALgADCgkJDwAAAA==.Gotharm:BAABLgAECn8aAAIYAAkJKwyhFgDgAQAYAAkJKwyhFgDgAQAAAA==.',
Gr='Grester:BAAALgAECggJEwAAAA==.Grimgrog:BAAALgADCgkJCQAAAA==.Grombit:BAAALgADCgEJAQAAAA==.Grymauch:BAABLgAECn8UAAIBAAYJih1cSgCqAQABAAYJih1cSgCqAQAAAA==.',
Ha='Hahmicydal:BAABLgAECn8ZAAQZAAcJ9wdUHgChAAAaAAcJEgbqGADWAAAZAAYJXwZUHgChAAAbAAEJ5gH9SgEXAAAAAA==.Hal:BAAALgAECgMJBQAAAA==.Hardcore:BAAALgADCgUJBQAAAA==.Havökush:BAACLgAFFH8JAAIPAAMJIRBGFADQAAAPAAMJIRBGFADQAAAuAAQKfx8AAg8ACQkIHwUHAKkCAA8ACQkIHwUHAKkCAAAA.Hawkeys:BAAALgADCgEJAQAAAA==.Haxuary:BAAALgAECgEJAgAAAA==.',
Ho='Hollyjavin:BAABLgAECn8aAAIWAAcJmw2wLQBHAQAWAAcJmw2wLQBHAQAAAA==.Holyguard:BAACLgAFFH8VAAIVAAUJCwsXGwAuAQAVAAUJCwsXGwAuAQAuAAQKfywAAhUACQkqF3gYAC0CABUACQkqF3gYAC0CAAAA.Holyhand:BAABLgAECn8UAAIcAAYJAg4DSQAVAQAcAAYJAg4DSQAVAQABLgAFFAUJFQAVAAsLAA==.',
Ic='Ickis:BAAALgAECgYJBgABLgAECggJFQABAAkdAA==.',
Il='Ilin:BAAALgAECggJDwAAAA==.Illidres:BAAALgADCgQJBQAAAA==.',
In='Influenza:BAAALgAECgMJAwAAAA==.Innis:BAAALgADCgIJAgAAAA==.',
Ir='Irithyll:BAABLgAECn8tAAIdAAkJTBZmAgAWAgAdAAkJTBZmAgAWAgAAAA==.',
Is='Isabela:BAABLgAFFH8IAAILAAIJsyS+UwDQAAALAAIJsyS+UwDQAAAAAA==.Isharadai:BAAALgADCgMJAwAAAA==.Isilian:BAAALgADCgUJCAAAAA==.',
Iw='Iwillpull:BAAALgADCgcJAQAAAA==.',
Iy='Iyora:BAAALgADCgUJBQAAAA==.',
Ja='Jambipriest:BAAALgADCgYJBgAAAA==.',
Jo='Jonamonk:BAAALgAECgUJDAAAAA==.',
Ju='Judyhop:BAAALgAECgYJCAABLgAFFAUJGgARAMAlAA==.Judyhopp:BAABLgAECn8aAAQeAAgJWhYxCAB2AQAeAAcJsBIxCAB2AQAKAAcJFxMwlgAxAQAdAAEJAABHFAAAAAABLgAFFAUJGgARAMAlAA==.Judyhopps:BAAALgAECgYJDAABLgAFFAUJGgARAMAlAA==.Judyhoppsimp:BAAALgAECgYJBgAAAA==.',
Ka='Kaeln:BAAALgAFFAMJAwABLgAFFAUJDQAeAPkXAA==.Kagrol:BAAALgADCgIJAgAAAA==.Kagronn:BAAALgADCggJCgAAAA==.Kakez:BAAALgAECgEJAQABLgAFFAcJHAAcAF8aAA==.Kaluanights:BAAALgADCgMJAwAAAA==.Kalzak:BAABLgAECn8ZAAIfAAgJPgz4FgA3AQAfAAgJPgz4FgA3AQAAAA==.',
Ke='Kelfinbarn:BAAALgAECgEJAQAAAA==.Ketu:BAABLgAECn8ZAAIbAAYJ2waPsADYAAAbAAYJ2waPsADYAAAAAA==.',
Ki='Kirryn:BAAALgADCgEJAQAAAA==.Kithiandra:BAAALgADCgIJAgAAAA==.Kiwistunna:BAAALgAECgYJDAABLgAECgkJGgAOAOYRAA==.',
Ko='Kogori:BAAALgAECgQJAwAAAA==.',
Kr='Krystaline:BAABLgAECn8ZAAIgAAgJUwqkCwBHAQAgAAgJUwqkCwBHAQAAAA==.',
Ku='Kurtfelbane:BAAALgADCgEJAQABLgAECgUJDAAMAAAAAA==.',
['Kï']='Kïtana:BAAALgAECgMJBAAAAA==.',
La='Ladiemacbeth:BAAALgADCgkJDwABLgAECggJGQAfAD4MAA==.Lanwynne:BAAALgADCgYJBAABLgAECggJEQAMAAAAAA==.Laxion:BAAALgADCgkJGwAAAA==.',
Le='Leafs:BAAALgAECgEJAQAAAA==.Leggo:BAABLgAECn8YAAIVAAYJ6xBOPAA/AQAVAAYJ6xBOPAA/AQAAAA==.',
Li='Lidravos:BAAALgAECgEJAQAAAA==.Liendrela:BAAALgADCgQJBAAAAA==.Lilia:BAACLgAFFH8KAAIGAAMJPwV2agCwAAAGAAMJPwV2agCwAAAuAAQKfyEAAwYACAlYHCQqAHwCAAYACAlYHCQqAHwCABUABAnYAX16AI8AAAAA.Lilmorty:BAAALgAECgYJDgABLgAFFAcJFAAEAJ0WAA==.',
Ll='Lluvioso:BAACLgAFFH8NAAMUAAMJ4h9RbgACAQAUAAMJFB9RbgACAQACAAEJ/iFMLgBWAAAuAAQKfyMAAwIACQnrI1oCAEwDAAIACQlNI1oCAEwDABQAAQkOH48qAVQAAAAA.',
Lo='Loaf:BAAALgAECgYJEQAAAA==.Lokix:BAAALgADCgIJAgAAAA==.Lookadoo:BAAALgADCgYJCwAAAA==.Loredbd:BAABLgAECn8fAAIhAAcJeBwKHwC2AQAhAAcJeBwKHwC2AQAAAA==.',
Lu='Lunarbelle:BAAALgADCgkJDwAAAA==.',
Ma='Macharlaidin:BAAALgADCgUJCQAAAA==.Mageistic:BAABLgAECn8fAAIKAAgJmgs4ewBnAQAKAAgJmgs4ewBnAQAAAA==.Mageyouthink:BAAALgADCgIJAgABLgADCgcJBwAMAAAAAA==.Malserok:BAAALgAECgcJCQAAAA==.Mashulya:BAAALgAECgEJAQAAAA==.Mauklindaufe:BAABLgAECn8VAAMBAAgJbhw6HwBKAgABAAgJbhw6HwBKAgAEAAMJ+AWWcQB4AAAAAA==.',
Me='Mekkadorque:BAAALgADCgUJBQABLgAECgcJCAAMAAAAAA==.Merien:BAABLgAECn8fAAIBAAcJPAjymADyAAABAAcJPAjymADyAAAAAA==.Meros:BAABLgAECn8UAAIBAAYJkAgRkQACAQABAAYJkAgRkQACAQAAAA==.',
Mo='Monstrosoh:BAAALgAECgUJCQAAAA==.Moonstrudels:BAAALgAECgEJAQABLgAECggJEgAMAAAAAA==.',
Mt='Mtdewmachine:BAAALgAECgIJAwAAAA==.',
Mu='Muertesdemon:BAAALgADCgUJBQAAAA==.Munstar:BAAALgADCgYJBgAAAA==.',
Na='Nafari:BAAALgAECgUJBQAAAA==.Narasil:BAAALgAECgEJAQAAAA==.Natea:BAAALgAECgcJDAAAAA==.',
Ne='Nebüla:BAAALgAECggJEQAAAA==.Necrökush:BAAALgAECgcJAgAAAA==.Nestro:BAAALgADCgUJBQAAAA==.',
Ni='Nightwinds:BAAALgAECgEJAgAAAA==.Ninajavin:BAAALgAECgUJBQAAAA==.',
No='Norinna:BAAALgAECgcJEQABLgAFFAIJCAAKAHoLAA==.Norlairas:BAAALgADCgUJBQAAAA==.',
Od='Odiousego:BAABLgAECn8YAAIaAAgJ6RJsCQCrAQAaAAgJ6RJsCQCrAQAAAA==.',
Ol='Oldkrusty:BAAALgADCgMJAwAAAA==.',
On='Onyxfïend:BAAALgADCgMJAwAAAA==.',
Oo='Ooryl:BAAALgAECgEJAQAAAA==.',
Op='Opheliajavin:BAAALgAECgEJAQAAAA==.',
Or='Orleus:BAAALgADCgUJBAAAAA==.Orlin:BAABLgAECn8gAAIKAAgJNxcNRAD4AQAKAAgJNxcNRAD4AQAAAA==.',
Pa='Painless:BAABLgAECn8YAAIWAAcJFg0SMAA5AQAWAAcJFg0SMAA5AQAAAA==.',
Ph='Phloemie:BAAALgADCgYJCQAAAA==.',
Po='Poronuma:BAAALgADCgEJAQAAAA==.Powerhøuse:BAACLgAFFH8cAAIKAAgJUxxzBwCDAgAKAAgJUxxzBwCDAgAuAAQKfycAAwoACAlgIp0YABcDAAoACAlgIp0YABcDAB0AAQkAAB0RAC4AAAAA.Powerwordhug:BAABLgAECn8tAAIcAAkJnx2WCgCoAgAcAAkJnx2WCgCoAgAAAA==.',
Pr='Proctolodin:BAABLgAECn8jAAIGAAgJCBPXYwCOAQAGAAgJCBPXYwCOAQAAAA==.',
Pu='Purplefart:BAABLgAECn8kAAMiAAkJlxLSGwDJAQAiAAkJlxLSGwDJAQAWAAEJPxvgYABLAAAAAA==.',
Ql='Qlaryx:BAAALgAECggJEQAAAA==.',
Qu='Quinner:BAACLgAFFH8JAAIIAAMJtxDYNgDHAAAIAAMJtxDYNgDHAAAuAAQKfzIABAgACQneGzwMAH4CAAgACQneGzwMAH4CAAcABAm+BTo3ALIAAAkAAwlTC4IuAKUAAAAA.Qut:BAABLgAECn8cAAIjAAgJxh1vFwDHAQAjAAgJxh1vFwDHAQAAAA==.',
Ra='Ragis:BAAALgADCgMJAwAAAA==.Rark:BAAALgAECgEJAQAAAA==.Ravenge:BAAALgADCgUJBQAAAA==.',
Re='Reckzx:BAABLgAECn8eAAIKAAYJRxxPewBnAQAKAAYJRxxPewBnAQAAAA==.',
Ri='Rickle:BAAALgAECgMJAwAAAA==.Riptoe:BAAALgAECgEJAQAAAA==.',
Ro='Roantami:BAAALgADCgUJBQAAAA==.Rokey:BAAALgAFFAEJAgABLgAFFAMJCgAKAMcfAA==.Rolling:BAAALgADCgMJAwAAAA==.Ronmaru:BAAALgAECgcJEAAAAA==.Rosejavin:BAAALgAECgEJAQAAAA==.Roxy:BAAALgAECgEJAQAAAA==.',
Ry='Ryujin:BAAALgAECgYJBgABLgAECggJEgAMAAAAAA==.',
Sa='Sabel:BAAALgAECgMJAwAAAA==.Sagori:BAAALgAECgEJAgAAAA==.Salvaa:BAAALgAECgMJBAAAAA==.Salyavin:BAAALgADCgMJAwAAAA==.Sanatlock:BAABLgAECn84AAMbAAgJxxL9UQCaAQAbAAgJWRL9UQCaAQAaAAQJ9xIrFADtAAAAAA==.Sayijin:BAAALgADCgUJBQAAAA==.',
Se='Seda:BAABLgAECn8YAAMkAAgJFx8wDwBuAgAkAAgJFx8wDwBuAgASAAEJVQveUgAfAAAAAA==.Seiken:BAAALgAECggJEgAAAA==.Selas:BAABLgAECn8bAAMCAAYJFg3VMADCAAAUAAYJkwnNxgDdAAACAAYJKwvVMADCAAAAAA==.Seryiana:BAAALgAECgQJBgAAAA==.',
Sg='Sgtkabukiman:BAAALgAECgYJBgABLgAECggJFQABAAkdAA==.',
Sh='Shackiechan:BAAALgAECgIJAgAAAA==.Shadowflood:BAAALgAECgMJBAAAAA==.Shalamare:BAAALgADCgcJDAAAAA==.Shiftysmash:BAAALgADCgIJBQABLgAECgIJBAAMAAAAAA==.',
Si='Silk:BAABLgAECn8ZAAIBAAYJrBAOfgAqAQABAAYJrBAOfgAqAQAAAA==.Silren:BAAALgAECgQJBQAAAA==.Sita:BAAALgADCgkJDwAAAA==.',
Sk='Skoldsmoyer:BAAALgADCgUJBQAAAA==.',
Sm='Smiledotjpg:BAAALgADCgcJDAAAAA==.',
Sn='Snowlord:BAAALgAECgUJCgABLgAECggJIwAGAAgTAA==.',
So='Sofferenza:BAAALgADCgcJFwAAAA==.Sorulus:BAAALgAECgEJAgAAAA==.Souldance:BAABLgAECn8rAAMbAAkJARbZKQAlAgAbAAkJwBXZKQAlAgAZAAMJQA7nLABWAAAAAA==.',
Sp='Spaceguy:BAABLgAECn8jAAIOAAgJ5gjmPwAYAQAOAAgJ5gjmPwAYAQAAAA==.',
St='Stamurai:BAAALgADCgEJAQAAAA==.Starryknight:BAAALgADCgUJBAABLgAECgkJJAANANgNAA==.Starwind:BAAALgAECgYJDAAAAA==.Stolock:BAAALgAECgMJAwABLgAECggJGgAlAOgZAA==.',
Su='Subie:BAAALgADCgcJBwAAAA==.Sugammadex:BAAALgAECgIJBQABLgAECgIJBwAMAAAAAA==.Sunrider:BAAALgADCgMJAwAAAA==.Surtür:BAABLgAECn8VAAIOAAgJ4SG5CwCTAgAOAAgJ4SG5CwCTAgAAAA==.',
Sw='Swato:BAAALgAECgEJAQABLgAECggJDwAMAAAAAA==.',
Sy='Sylaang:BAAALgAECgIJAgAAAA==.',
Ta='Talie:BAAALgADCgYJBQAAAA==.Taliria:BAABLgAECn8eAAIiAAYJehhWJgClAQAiAAYJehhWJgClAQAAAA==.Talladar:BAAALgAECgQJBAAAAA==.Talmaar:BAAALgADCgEJAQAAAA==.Targ:BAABLgAECn8VAAIBAAgJCR1VKQAiAgABAAgJCR1VKQAiAgAAAA==.',
Te='Tenshiro:BAAALgADCgYJCwAAAA==.Tevin:BAAALgADCgMJAwAAAA==.',
Th='Thalor:BAAALgADCgcJDAAAAA==.Theros:BAAALgAECgYJBgAAAA==.Thundamon:BAAALgAECgEJAQAAAA==.',
Ti='Tidefang:BAAALgAECgYJBwABLgAECggJFQADAIIJAA==.',
To='Toblakai:BAAALgADCgUJBQABLgAECgkJAgAMAAAAAA==.Torryn:BAAALgADCgkJCQAAAA==.',
Tr='Trigon:BAAALgAECgMJCAAAAA==.Trité:BAAALgAECgcJDQAAAA==.Trollbossmom:BAAALgADCgMJAwAAAA==.Truthteiier:BAAALgAECgEJAgAAAA==.',
Ty='Tyladrillian:BAAALgAECgEJAQAAAA==.',
Un='Unholyguard:BAAALgADCgEJAQABLgAFFAUJFQAVAAsLAA==.',
Uz='Uzumaki:BAABLgAECn8VAAIRAAgJrBVEGADaAQARAAgJrBVEGADaAQAAAA==.',
Va='Vajrajavin:BAAALgAECgYJDwABLgAECggJKgAIANMPAA==.Valadoria:BAAALgAECgIJAwAAAA==.Valanya:BAACLgAFFH8WAAIQAAcJTRHjCwD2AQAQAAcJTRHjCwD2AQAuAAQKfyUAAhAACQkhIw4DAHkDABAACQkhIw4DAHkDAAAA.Valasca:BAAALgADCgcJBwAAAA==.Valonar:BAAALgAECgUJCAAAAA==.Valonkyr:BAAALgADCgEJAQAAAA==.Valor:BAAALgAECggJEwAAAA==.',
Ve='Veldaan:BAAALgADCgkJEQAAAA==.',
Vi='Victra:BAAALgAECgUJBQABLgAECggJFQABAAkdAA==.Vinskey:BAAALgADCgYJBgAAAA==.Vipe:BAAALgAECggJEQAAAA==.Viperlock:BAAALgADCgUJBQAAAA==.Visenyaa:BAAALgADCgEJAQAAAA==.Vita:BAAALgAECgQJBAAAAA==.',
Vo='Volaq:BAAALgAECgEJAQAAAA==.Voodoochild:BAAALgAECgIJAgAAAA==.',
Vy='Vyn:BAAALgAECgQJCAABLgAECggJFQABAAkdAA==.',
Wa='Waltwitemane:BAAALgAECgEJAQAAAA==.Warliff:BAAALgADCgMJAwAAAA==.',
Wh='Whish:BAABLgAECn8WAAImAAYJFQl3bwDUAAAmAAYJFQl3bwDUAAAAAA==.Whiteleaf:BAABLgAECn8eAAIkAAgJkwr3NgBWAQAkAAgJkwr3NgBWAQAAAA==.',
Wi='Wisdom:BAAALgADCggJDQABLgAECggJEwAMAAAAAA==.',
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
