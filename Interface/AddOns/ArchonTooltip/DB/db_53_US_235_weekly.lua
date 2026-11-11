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

local lookup = {'Shaman-Restoration','DemonHunter-Devourer','Warlock-Demonology','Druid-Balance','Hunter-Marksmanship','Paladin-Retribution','Warlock-Destruction','Evoker-Devastation','Priest-Holy','Hunter-BeastMastery','Druid-Restoration','Paladin-Holy','Unknown-Unknown','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Warlock-Affliction','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','Druid-Feral','Druid-Guardian','Mage-Frost','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Mage-Fire','Paladin-Protection','Hunter-Survival','Priest-Shadow','DemonHunter-Havoc','DemonHunter-Vengeance','DeathKnight-Frost','Priest-Discipline','Monk-Windwalker','DeathKnight-Blood','Monk-Mistweaver',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=53,date='2026-11-10',data={Ad='Addisyn:BAAANQAECgEIAgAAAA==.',
Ae='Aemetris:BAABNQAECn8aAAIBAAkK2hFsYgB4AQABAAkK2hFsYgB4AQAAAA==.Aendrel:BAABNQAECn81AAICAAoK+SCACQCzAgACAAoK+SCACQCzAgAAAA==.',
Ai='Airaquafira:BAABNQAECn8pAAIBAAoK5x5LKQC+AgABAAoK5x5LKQC+AgAAAA==.',
Aj='Ajheria:BAAANQADCgYIDQABNQAECgoKIgADACMVAA==.',
Al='Alejandro:BAAANQAECggICwAAAA==.Alégria:BAAANQAECgcIDwAAAA==.',
Am='Amiragosa:BAAANQABCgYICAAAAA==.',
An='Anaire:BAAANQAECgEIAgAAAA==.Anaiya:BAAANQADCgEIAQAAAA==.Anaru:BAABNQAECn8vAAIEAAoKqwV7OwAsAQAEAAoKqwV7OwAsAQAAAA==.Andalaine:BAAANQAECgEIAQAAAA==.Angriff:BAAANQAECgEIAQAAAA==.Anraleth:BAABNQAECn9BAAIFAAoKKyTrAwCYAwAFAAoKKyTrAwCYAwAAAA==.Anxiqtt:BAAANQAECgEIAQAAAA==.',
Ar='Arckillion:BAABNQAECn8ZAAIGAAoKkBYBswC5AQAGAAoKkBYBswC5AQAAAA==.Arcángel:BAAANQAECgIIAgAAAA==.Arduous:BAAANQADCgcIBwAAAA==.Ariana:BAAANQADCgYIDAAAAA==.Arkadio:BAAANQAECgEIAQAAAA==.Armâgeddon:BAAANQADCgYIBgAAAA==.',
As='Asparagus:BAAANQAECggIEwAAAA==.Asturoth:BAAANQADCggIDgAAAA==.',
Au='Aust:BAAANQADCgcIBwAAAA==.Authority:BAAANQAECggICQAAAA==.',
Av='Averlis:BAABNQAECn8ZAAIEAAcKhhASXQBdAQAEAAcKhhASXQBdAQAAAA==.Avoiddance:BAAANQADCgYICgABNQAECgoKIgADACMVAA==.',
Ay='Ayci:BAAANQAECgQICQAAAA==.',
Az='Azmithrilim:BAABNQAECn8YAAIFAAgKygNEMgDQAAAFAAgKygNEMgDQAAAAAA==.Azurargentyr:BAAANQABCgEIAQAAAA==.',
Ba='Baconbo:BAAANQAECgUIDwAAAA==.Batistabomba:BAAANQADCgUIBQAAAA==.',
Be='Beanbeater:BAAANQAECgEIAQAAAA==.Bellyroll:BAAANQAECgEIAQAAAA==.Bended:BAABNQAECn89AAMDAAoK9BbfLgBEAgADAAoKqRbfLgBEAgAHAAQKfBZ+MQABAQAAAA==.',
Bl='Blikey:BAAANQAECgcICAAAAA==.Bloodyrott:BAAANQADCgIIAgAAAA==.Bluedrake:BAACNQAFFH8FAAIIAAMKTxeoAgDkAAAIAAMKTxeoAgDkAAA1AAQKfx4AAggACgpFGw4HABkCAAgACgpFGw4HABkCAAE1AAUUBggKAAQA9xkA.Blueparrot:BAABNQAECn87AAIJAAoKrQ+vQQAcAgAJAAoKrQ+vQQAcAgAAAA==.',
Bo='Bocantwo:BAAANQAECgEJAgAAAA==.Boggyboomer:BAAANQADCgMIAwAAAA==.Bombfaucet:BAAANQAECgEIAQAAAA==.',
Br='Bramul:BAAANQAECgEIAQAAAA==.Brewteaful:BAAANQADCgEIAQAAAA==.Bringinlight:BAABNQAECn8WAAIJAAcKJgGzxwCDAAAJAAcKJgGzxwCDAAABNQAECgcIFwAKAKwGAA==.',
Bu='Bubbleicious:BAAANQAECgEIAQAAAA==.Bubbletea:BAAANQAECgMIBgABNQAECgoKRAAKAOkhAA==.Bubbleyum:BAAANQADCgQIBAAAAA==.Bulletz:BAAANQAECgYICgAAAA==.Buzzsha:BAAANQAECgEIAgAAAA==.',
Ca='Cahhwa:BAAANQADCgMIAwAAAA==.Camillie:BAAANQADCgIIAgAAAA==.Casanna:BAAANQADCgQIBAAAAA==.Cassandria:BAABNQAECn87AAMEAAoK/wvVKQCbAQAEAAoK/wvVKQCbAQALAAcKNg1bLwBYAQAAAA==.Cassiradra:BAAANQAECgEIAQAAAA==.',
Ce='Cervixticklr:BAAANQAECggICwAAAA==.',
Ch='Chathlia:BAAANQAECgEIAQAAAA==.Choglana:BAAANQADCgQIBAAAAA==.Chogric:BAABNQAECn8sAAIMAAoKQyO0CwBrAwAMAAoKQyO0CwBrAwABNQADCgQIBAANAAAAAA==.Châos:BAABNQAECn8rAAIGAAkKLROQgQC1AQAGAAkKLROQgQC1AQAAAA==.',
Ci='Cif:BAAANQAECgQICgAAAA==.Civetta:BAABNQAECn8pAAIKAAoKJxbGUQB7AgAKAAoKJxbGUQB7AgAAAA==.',
Cr='Crazzywazzy:BAAANQAECgYIDgAAAA==.Crona:BAAANQAECgcIEwAAAA==.Crzyblnkrton:BAACNQAFFH8XAAIOAAcKHQ2OGAC0AQAOAAcKHQ2OGAC0AQA1AAQKfywAAg4ACgpjH3JDADUCAA4ACgpjH3JDADUCAAAA.Crzzy:BAAANQAECgQIBAAAAA==.Crzzyystabby:BAABNQAECn8ZAAMPAAoK/Rd7IwBpAgAPAAoK/Rd7IwBpAgAQAAEKZg3fZAAxAAAAAA==.',
Cu='Cultera:BAACNQAFFH8FAAICAAIK3AmYDQBtAAACAAIK3AmYDQBtAAA1AAQKfzoAAgIACgqYHyEMAB8DAAIACgqYHyEMAB8DAAAA.Cuzon:BAABNQAECn8VAAMBAAkKMhsGPQBrAgABAAkKMhsGPQBrAgARAAYK/he/kQB4AQABNQAFFAMICAALAEUTAA==.',
Cy='Cyhyraethia:BAABNQAECn8vAAISAAoKxBkOAwDVAgASAAoKxBkOAwDVAgABNQAFFAQIDwACAGAZAA==.',
Da='Dagden:BAAANQAECgUIBQAAAA==.Daish:BAAANQADCgMIAwAAAA==.Danda:BAAANQADCggIFgAAAA==.Dare:BAAANQAFFAQIBAABNQAFFAYICAAPANALAA==.Daricepicker:BAABNQAECn9EAAIKAAoK6SF4FQDpAgAKAAoK6SF4FQDpAgAAAA==.Darkyn:BAABNQAECn8iAAIDAAoKIxV/awAbAgADAAoKIxV/awAbAgAAAA==.',
Dd='Ddeonù:BAACNQAFFH8LAAICAAQKJANiCwCXAAACAAQKJANiCwCXAAA1AAQKfyoAAgIACgrtFFwhAEECAAIACgrtFFwhAEECAAAA.',
De='Deadlysins:BAAANQADCggICAABNQAECggICQANAAAAAA==.Deadscar:BAECNQAFFH8RAAITAAUK3yBVAgAUAQATAAUK3yBVAgAUAQA1AAQKfz0AAhMACgozJUwCADQDABMACgozJUwCADQDAAAA.Deathmasterj:BAAANQADCggIDwAAAA==.Deaths:BAAANQAECgMIBAAAAA==.Delphinium:BAAANQADCgYIDAAAAA==.Dentheaded:BAACNQAFFH8oAAIGAAcKaiQ/AQCyAgAGAAcKaiQ/AQCyAgA1AAQKfz8AAgYACgprJvwGAF4DAAYACgprJvwGAF4DAAAA.',
Di='Diablosucio:BAAANQADCgMIAwAAAA==.Dithariaa:BAAANQAECgQIBAAAAA==.',
Do='Docryktor:BAABNQAECn8+AAITAAoK/haHEABhAgATAAoK/haHEABhAgAAAA==.Doomgears:BAAANQAECgMIAwAAAA==.',
Dr='Draculä:BAAANQAECgEIAQABNQAECgcJBwANAAAAAA==.Drashta:BAAANQAECgYIEQAAAA==.Drhurtouch:BAAANQAECgQIEAAAAA==.Drogas:BAABNQAECn9AAAQUAAoK7xOhCwBYAgAUAAoK7xOhCwBYAgAIAAYKsQeYJAAbAQAVAAUK3wsDFQDeAAAAAA==.Drtybear:BAABNQAECn8XAAMWAAYKKhUsKACoAAAXAAUKkhUIOgDcAAAWAAUKCxIsKACoAAAAAA==.Druithz:BAAANQAECgQIBAABNQAFFAQIBwAMACkXAA==.Drussila:BAAANQADCgQIBAABNQAECgcIDwANAAAAAA==.',
['Dâ']='Dârrius:BAAANQADCggICQAAAA==.',
Eb='Ebonwings:BAAANQAECggICQAAAA==.',
Ed='Ediana:BAACNQAFFH8GAAIOAAMK0wDzRQBKAAAOAAMK0wDzRQBKAAA1AAQKfykAAw4ACgorB9P/AI4BAA4ACgorB9P/AI4BABgAAgpyA3NBAEEAAAAA.Edisian:BAAANQABCgQIBAAAAA==.',
Ee='Eebz:BAAANQADCggIDAAAAA==.Eebzy:BAABNQAECn8bAAMZAAoK5g+UHQBqAQAZAAkKHRGUHQBqAQAaAAIKZAdsLQEhAAAAAA==.',
El='Elandrah:BAABNQAECn8VAAIJAAcKkgJBsAAGAQAJAAcKkgJBsAAGAQAAAA==.Elithsong:BAAANQABCgIIAgAAAA==.Elmô:BAABNQAECn9HAAIMAAoKSB1bDgBCAwAMAAoKSB1bDgBCAwAAAA==.',
Es='Essence:BAAANQADCgYIBgAAAA==.Estameling:BAABNQAECn84AAIXAAkKwBEKHQCFAQAXAAkKwBEKHQCFAQAAAA==.',
Et='Etherah:BAAANQABCgEIAQAAAA==.',
Ex='Excizion:BAABNQAECn8cAAIbAAkKbw8aZQB8AQAbAAkKbw8aZQB8AQAAAA==.',
Fa='Fantabulouus:BAABNQAECn8pAAIaAAoKLxEAVQDtAQAaAAoKLxEAVQDtAQAAAA==.Fantym:BAAANQABCgYJBgAAAA==.Farorê:BAAANQABCgEIAQAAAA==.Fatherrahl:BAAANQAECggICAAAAA==.Fathertim:BAAANQAECgQICAAAAA==.',
Fe='Feldrena:BAAANQADCggIEQAAAA==.',
Fl='Flangus:BAAANQAECgEIAQAAAA==.',
Fo='Forgiven:BAABNQAECn8XAAIEAAgKLSOYLQBwAgAEAAgKLSOYLQBwAgAAAA==.Foxyhound:BAAANQAECggIBgAAAA==.',
Fr='Franksredhot:BAAANQAECgEIAQAAAA==.Frostii:BAAANQAECgYIEQAAAA==.',
Fu='Fudestamp:BAABNQAECn8aAAIGAAoKOgmHtQBPAQAGAAoKOgmHtQBPAQAAAA==.Fugryktor:BAABNQAECn8gAAISAAcK7BDTDQBEAQASAAcK7BDTDQBEAQABNQAECgoKPgATAP4WAA==.Fuu:BAAANQABCgMJAwAAAA==.Fuzzywuzzy:BAAANQADCgYIBgAAAA==.',
Fy='Fyre:BAAANQADCgYIBQAAAA==.',
Ga='Gagarazzi:BAAANQADCgMIAwAAAA==.Galandor:BAABNQAECn8VAAIMAAUKSh7waQBkAQAMAAUKSh7waQBkAQAAAA==.Galethia:BAAANQADCgMIAwAAAA==.Gandaalf:BAABNQAECn82AAQcAAoKpyDxAQAHAgAcAAgK+x/xAQAHAgAYAAQK8hrsGAD+AAAOAAEKAABCqwFqAAAAAA==.Gandelfzz:BAAANQADCgEIAQAAAA==.',
Ge='Geedorah:BAAANQADCgIIAgAAAA==.Gemhide:BAABNQAECn8YAAMHAAoKJQ6PFQDBAQAHAAoKJQ6PFQDBAQADAAMKvQPULgFfAAAAAA==.Gerbo:BAAANQAECgEIAgAAAA==.',
Gi='Gityadruid:BAAANQADCgYIMgABNQAECgcIFwAKAKwGAA==.Gityahunter:BAABNQAECn8XAAIKAAcKrAZ8wgASAQAKAAcKrAZ8wgASAQAAAA==.',
Go='Gobanks:BAABNQAECn84AAMdAAoKwh58CAAWAwAdAAoKwh58CAAWAwAGAAQKog9l6gD2AAAAAA==.',
Gr='Grayarms:BAAANQAECgQIBwAAAA==.Graygoat:BAAANQADCgYIBgABNQAFFAkJHgAeAMIiAA==.Grayl:BAAANQAECgEIAQAAAA==.Grayresto:BAAANQAECgMIBgAAAA==.Grayson:BAABNQAECn8UAAIGAAUKmwSWQwF4AAAGAAUKmwSWQwF4AAAAAA==.Graysurv:BAACNQAFFH8eAAIeAAkKwiIDAABjAwAeAAkKwiIDAABjAwA1AAQKfzQAAh4ACgr7JmIAAM8DAB4ACgr7JmIAAM8DAAAA.Grimik:BAABNQAECn8aAAMFAAoK1wmlNgCZAQAFAAkKHgelNgCZAQAKAAoKnwgmzQBnAQAAAA==.Grimwali:BAAANQAECgUIDAAAAA==.',
Ha='Hallêlujah:BAAANQAECgEIAQAAAA==.Hamelot:BAAANQAECgEIAQAAAA==.Hamremmi:BAAANQADCgIIAgABNQAECgkJGwAfAAYkAA==.Hardrock:BAEANQADCgcIEAABNQAECgoKOQARACMLAA==.',
He='Healsforu:BAAANQAECgEIAQAAAA==.Healulater:BAAANQADCgUIBwABNQAECgYIDgANAAAAAA==.',
Hi='Highbrittz:BAAANQADCggIDQAAAA==.',
Ho='Hobiscuits:BAEANQABCgcIEQABNQAECgoKFgADAEsYAA==.Hodgy:BAAANQADCgQIBAAAAA==.',
Hu='Hurtfinger:BAAANQADCgYIEwAAAA==.',
Hy='Hydrobubble:BAAANQADCgYIBgAAAA==.',
Il='Illyy:BAAANQAECgQJBgAAAA==.',
Im='Imagine:BAABNQAECn8gAAMIAAoKQh1bBACFAgAIAAkKQh1bBACFAgAUAAgKBwx4IwCqAQAAAA==.',
In='Indagussy:BAAANQAECgcIEgABNQAFFAcIFAAgAMIcAA==.Indawhole:BAACNQAFFH8UAAMgAAcKwhzIAwA/AgAgAAYK3h3IAwA/AgACAAEKUBjDDgBZAAA1AAQKfzMABCAACgpIJQcVAPUCACAACQoYJQcVAPUCAAIACgr6HoQWAPMBACEAAQoKE2EqAD0AAAAA.',
Ir='Ironsparc:BAAANQADCggICAABNQAECgoKIgADACMVAA==.',
Is='Isamna:BAAANQAECgEIAgAAAA==.',
Iv='Ivi:BAAANQADCgQIBAAAAA==.',
Iz='Izumiwitabow:BAAANQAECgQIEgAAAA==.',
Ja='Jasmean:BAAANQAECgEIAQAAAA==.Jassabella:BAAANQAECgEIAwAAAA==.Javaluminous:BAABNQAECn87AAIGAAoKyxXQTgAuAgAGAAoKyxXQTgAuAgAAAA==.Jaytsukitori:BAACNQAFFH8IAAILAAMKRRPuCwDVAAALAAMKRRPuCwDVAAA1AAQKfxoABAsACQrTIA80AHoBAAsABgrlHg80AHoBAAQABgoVE3xjAEABABcAAQoAAN5kACsAAAAA.',
Jd='Jdots:BAAANQADCggIEwAAAA==.',
Jh='Jhantherox:BAAANQABCgQIBAABNQAECgoKIgADACMVAA==.Jheranton:BAAANQAECgEIAQABNQAECgoKIgADACMVAA==.',
Ji='Jiannae:BAAANQADCgIIAgABNQAECgkJGgABANoRAA==.Jif:BAAANQAECgcIDAAAAA==.',
Jo='Joesepi:BAABNQAECn8nAAIbAAoK6hqyDQCSAgAbAAoK6hqyDQCSAgAAAA==.Jonah:BAABNQAECn8qAAQHAAoKGSPrAwDSAQASAAkKrx71BACAAgADAAgK1h5xUwBbAgAHAAgKaSDrAwDSAQABNQAECgoKKAAbAFUkAA==.Joodee:BAABNQAECn8eAAIBAAcKShGRdQA8AQABAAcKShGRdQA8AQAAAA==.Jordi:BAAANQADCgcIBwAAAA==.Joseon:BAAANQAECgQICQABNQAECgoKNgALADQlAA==.',
Ka='Kackarot:BAABNQAECn8nAAIRAAkK/RLGUQAyAgARAAkK/RLGUQAyAgAAAA==.Kartelz:BAABNQAECn8cAAIgAAgKNgbkUwBBAQAgAAgKNgbkUwBBAQAAAA==.Katrine:BAABNQAECn84AAIiAAoK2xdNKgBIAgAiAAoK2xdNKgBIAgAAAA==.',
Ke='Kendreth:BAAANQADCgQICAAAAA==.',
Ki='Kij:BAECNQAFFH8TAAMYAAYKbRw1AQAzAQAYAAQK7hc1AQAzAQAOAAMKpRpCSQCWAAA1AAQKfzYAAxgACgodIwQIABwCAA4ACgpQIC1RAN4CABgABwreHgQIABwCAAAA.Kilrah:BAABNQAECn8qAAIgAAoK9AmqQgCtAQAgAAoK9AmqQgCtAQAAAA==.Kissmycrits:BAABNQAECn8tAAIKAAkKthL8awDPAQAKAAkKthL8awDPAQAAAA==.Kissmywrath:BAABNQAECn8VAAIGAAkKpQg6xQA0AQAGAAkKpQg6xQA0AQAAAA==.Kiyoine:BAABNQAECn8vAAIWAAkKdxFrDwCxAQAWAAkKdxFrDwCxAQAAAA==.',
Kn='Knocksteady:BAAANQAECgcIEAAAAA==.Knoxreaps:BAAANQADCgUIBQAAAA==.',
Ko='Kookie:BAAANQAECgYICQAAAA==.',
Kr='Kryyng:BAAANQADCgMIAwAAAA==.Krzyng:BAAANQADCgMIAwAAAA==.',
Ky='Kynbrookera:BAABNQAECn8yAAILAAoK0RJHGQArAgALAAoK0RJHGQArAgAAAA==.',
Kz='Kzmyng:BAAANQADCgcIBwAAAA==.',
['Kì']='Kìnky:BAAANQAECgEIAQAAAA==.',
La='Lacquerhead:BAAANQAECgEIAQAAAA==.Laetha:BAAANQADCggIDgABNQAECggIHwAIAKETAA==.Larriat:BAAANQADCgcICAAAAA==.Layonscoob:BAAANQAECgYIBwAAAA==.',
Le='Leefs:BAAANQAECgYIBQABNQAECggIEgANAAAAAA==.',
Li='Lightweaver:BAAANQAECggICQAAAA==.Linai:BAABNQAECn9BAAIPAAoKxQnRHQDkAQAPAAoKxQnRHQDkAQAAAA==.Linthe:BAABNQAECn8kAAMMAAoKMg6sagDXAQAMAAoKMg6sagDXAQAGAAEKdwagrgEwAAAAAA==.Lit:BAABNQAECn8eAAMMAAkKSQrqeAA3AQAMAAkKSQrqeAA3AQAGAAEKAAAaqwEyAAAAAA==.Lites:BAAANQAECggIEgAAAA==.Lithica:BAAANQAECgEIAQAAAA==.Littledog:BAACNQAFFH8GAAIJAAUKrgzPEwBXAQAJAAUKrgzPEwBXAQA1AAQKfyAABB8ACQqlEMs/ADABAB8ABgphEcs/ADABAAkABAqZGFKHACoBACMABgpdEIAQACEBAAAA.',
Lo='Lockdout:BAAANQADCgQIBAABNQAECgYIDgANAAAAAA==.Lokiantonio:BAAANQADCgQIBAAAAA==.Longshenks:BAAANQADCgIIAgAAAA==.Lotten:BAABNQAECn8pAAIGAAgKJRhPiAAWAgAGAAgKJRhPiAAWAgAAAA==.',
Lu='Luckevin:BAAANQAECggICgAAAA==.Lumi:BAAANQAECgIIBQAAAA==.Luminare:BAAANQAECgEIAQAAAA==.Lurashtai:BAAANQAECggIDAAAAA==.Luvido:BAAANQAECgEIAgAAAA==.',
Ma='Magicmann:BAAANQADCgUIBwAAAA==.Malafang:BAAANQAECgMIBgAAAA==.Malanah:BAAANQAECgQIEAAAAA==.Malgaren:BAAANQAECgEIAQAAAA==.Malphen:BAAANQADCggICAABNQAECgoKGQALAEMVAA==.Mangoo:BAAANQADCgYIBgAAAA==.Marandra:BAAANQADCgcIFgAAAA==.Mattu:BAAANQAECgEIAQAAAA==.Maverick:BAACNQAFFH8IAAIPAAYK0Av4CQBCAQAPAAYK0Av4CQBCAQA1AAQKfy0AAg8ACgpFIMEGABMDAA8ACgpFIMEGABMDAAAA.',
Me='Meregryn:BAAANQADCgUIBQAAAA==.Merunyaa:BAAANQAECgcIEAAAAA==.',
Mi='Michaella:BAAANQADCgYIEAAAAA==.Mil:BAAANQADCgQJBQAAAA==.Minipwn:BAABNQAECn8YAAIYAAkKcQ10EwBxAQAYAAkKcQ10EwBxAQAAAA==.',
Mk='Mk:BAEANQAECgUIBgABNQAECgoKPQAkAFkfAA==.',
Mo='Mogar:BAABNQAECn8YAAIaAAkKIQvlyQBjAQAaAAkKIQvlyQBjAQAAAA==.Moogician:BAAANQAECgUIBAAAAA==.Moonzhine:BAAANQAECgEIAQAAAA==.Moosejaw:BAAANQAECgQIBwAAAA==.Mordread:BAAANQAECgQICgAAAA==.Morgalruk:BAAANQADCgcIFgAAAA==.',
My='Mythx:BAACNQAFFH8OAAIKAAYKhBXGBACcAQAKAAYKhBXGBACcAQA1AAQKfykAAwoACgpgIvMiAAsDAAoACgpgIvMiAAsDAAUACArsDig2AJ0BAAAA.',
['Mý']='Mýthh:BAAANQAECgEIAwAAAA==.',
Na='Naturboy:BAAANQADCgYIBgABNQAECgEIAQANAAAAAA==.',
Ne='Netherward:BAACNQAFFH8fAAMSAAgKHx1aAAAjAgASAAcKVx9aAAAjAgADAAYKYhniCgC9AQA1AAQKfz8AAxIACgphJfoAAGwDABIACgqoJPoAAGwDAAMACAp6IxkkAHMCAAE1AAQKCQkbAB8ABiQA.',
Ni='Niknikboy:BAAANQABCgYICwAAAA==.Nivmizzet:BAACNQAFFH8GAAMDAAMKgAroIwCWAAADAAIKfw7oIwCWAAAHAAEKgwLTFAA8AAA1AAQKf1MAAwMACgoWH3AVAMECAAMACgrUHnAVAMECAAcAAgoYG0hLAJ4AAAAA.',
No='Nolakai:BAAANQAECgQIBQAAAA==.Nonliving:BAAANQADCgYIBgAAAA==.Novagosa:BAAANQAECgUICwABNQAECgoKQgABAMglAA==.Novalea:BAABNQAECn9CAAMBAAoKyCX5BADAAwABAAoKyCX5BADAAwARAAMKMw2KwgBzAAAAAA==.Nozom:BAAANQADCgYIBgAAAA==.',
Np='Np:BAAANQAECgMJBwAAAA==.',
Nu='Nutcutter:BAAANQAECgQIBQABNQAECggIKQAbAA4OAA==.',
Ny='Nyvera:BAAANQADCgIIAgAAAA==.Nyxon:BAAANQADCgYIEQAAAA==.',
Os='Osirus:BAAANQAECgIIAgAAAA==.',
Ou='Outforarip:BAAANQADCgIIAgAAAA==.',
Ox='Oxxo:BAAANQAECgQIBAAAAA==.',
Pa='Palomar:BAAANQAECgQIEAAAAA==.Paraggonn:BAABNQAECn8dAAIKAAcK8xL1mQBkAQAKAAcK8xL1mQBkAQAAAA==.',
Ph='Pherkle:BAAANQAECgQICwABNQAECgoKPgATAP4WAA==.Phuriosa:BAAANQAECgIIAgABNQAECgoKHgALACkSAA==.Phury:BAABNQAECn8eAAILAAoKKRJiKADdAQALAAoKKRJiKADdAQAAAA==.Physinyx:BAABNQAECn8+AAMRAAoKuRamKwAbAgARAAoKuRamKwAbAgABAAgKmwAn8gCGAAAAAA==.',
Pi='Pizza:BAAANQAECgQIBAAAAA==.',
Po='Pomomies:BAAANQAECgEIAQAAAA==.Pooseunpoose:BAABNQAECn8dAAIlAAoKzRbHJADFAQAlAAoKzRbHJADFAQAAAA==.',
Pr='Preparedrice:BAAANQAECgQIBwABNQAECgoKRAAKAOkhAA==.',
Pu='Pumbaa:BAAANQAECgIIAgABNQAECgcJBwANAAAAAA==.Purpleparrot:BAAANQADCggICAAAAA==.',
Qu='Quilby:BAAANQADCgUICgAAAA==.',
Ra='Raenyx:BAABNQAECn81AAMDAAoKNw0lhgA9AQADAAoKNw0lhgA9AQAHAAEKAADNhwAeAAABNQAECgoKPgARALkWAA==.Ragnarrok:BAAANQADCgYIBgAAAA==.Raif:BAABNQAECn8tAAIcAAgKlBA3AwB7AQAcAAgKlBA3AwB7AQAAAA==.Randir:BAAANQADCgIIAgAAAA==.Raveneyes:BAEBNQAECn8bAAIDAAoKBwoRwgBHAQADAAoKBwoRwgBHAQAAAA==.',
Re='Reightous:BAAANQAECgQIBwAAAA==.Reylilyn:BAABNQAECn8fAAImAAoKSQ8zFQCVAQAmAAoKSQ8zFQCVAQAAAA==.Reynarena:BAAANQAECgMIBQAAAA==.',
Rh='Rhaenfyre:BAACNQAFFH8HAAMCAAQKyQ7KCADNAAACAAQKyQ7KCADNAAAgAAEKkA09GgA/AAA1AAQKfzoAAwIACgpTIIYKAJ8CAAIACgpTIIYKAJ8CACAAAwrMFR9hAIsAAAAA.',
Ri='Ripley:BAAANQAECgcIBwABNQAFFAYICAAPANALAA==.Rivenel:BAACNQAFFH8RAAMHAAYKVA95BAChAAADAAQKdwuQFgDhAAAHAAIKIRV5BAChAAA1AAQKfz8AAwcACgriIdoFALQCAAcACAqXH9oFALQCAAMACAqOIGIzADMCAAAA.',
Ro='Robinvoid:BAABNQAECn8aAAMCAAoKThtBFgCwAgACAAoKThtBFgCwAgAgAAEK3wsNkwA1AAAAAA==.Rodel:BAAANQAECgMICAAAAA==.Rondrey:BAAANQADCgYIBgAAAA==.Roquan:BAABNQAECn8xAAIiAAkKnxHXLwDWAQAiAAkKnxHXLwDWAQAAAA==.Rosè:BAAANQAECgYICAABNQAFFAYICAAPANALAA==.',
Ru='Rubmyrott:BAAANQAECgEIAQAAAA==.Runawäy:BAAANQAECgYIDgAAAA==.Rundas:BAAANQAECgcIEgAAAA==.',
['Ré']='Rébél:BAAANQADCgYICAAAAA==.',
['Rê']='Rêdd:BAABNQAECn8xAAIfAAkKJBCTGwCjAQAfAAkKJBCTGwCjAQAAAA==.',
['Rì']='Rìven:BAAANQADCgYICAAAAA==.',
Sa='Sabeion:BAAANQAECggIEwAAAA==.Saddie:BAAANQADCgcIEgAAAA==.Saharaa:BAAANQAECgEIBgAAAA==.Salswarriah:BAABNQAECn8VAAIaAAUKVwZO8gB7AAAaAAUKVwZO8gB7AAAAAA==.Sanasath:BAABNQAECn8hAAMIAAkKLw1gDAB7AQAIAAkKLw1gDAB7AQAUAAgKFA4NLgAxAQAAAA==.',
Sc='Scrumbles:BAAANQAECggIDQAAAA==.',
Se='Sealgair:BAAANQADCgYIBgAAAA==.Segador:BAAANQAECgYIDQAAAA==.Seonwoo:BAAANQAECgEIAQAAAA==.Seraphim:BAAANQADCggICAAAAA==.',
Sg='Sgtbonesnap:BAAANQADCgUIBQABNQAECgEIAQANAAAAAA==.',
Sh='Shamanizim:BAACNQAFFH8OAAIRAAQKohttDgDqAAARAAQKohttDgDqAAA1AAQKf0oAAhEACgpVJBoNAP8CABEACgpVJBoNAP8CAAAA.Shamanka:BAAANQADCgIIAgAAAA==.Sheetara:BAAANQAECgQIBAAAAA==.Shenzii:BAAANQAECgQICQAAAA==.Shikigami:BAAANQAECgEIAQAAAA==.Shinoikari:BAAANQADCgYIEwABNQAECgoKPgAaAPEQAA==.Shinotenshi:BAAANQAECgUIDQABNQAECgoKPgAaAPEQAA==.Shugarae:BAABNQAECn8oAAIEAAkKtgU4OgAyAQAEAAkKtgU4OgAyAQAAAA==.',
Si='Silvafist:BAAANQAECgEJAwAAAA==.',
Sk='Skreezy:BAAANQAECgYIDQAAAA==.Skully:BAAANQAECgIIAQABNQAECggIEgANAAAAAA==.Skuls:BAAANQADCgQIBAAAAA==.',
Sl='Slashemup:BAABNQAECn8UAAIgAAgKCBFVPQDOAQAgAAgKCBFVPQDOAQAAAA==.Slayter:BAABNQAECn82AAILAAoKNCW2BQB+AwALAAoKNCW2BQB+AwAAAA==.',
Sm='Smaugor:BAAANQAECgYIEwABNQAECgcJBwANAAAAAA==.',
So='Soju:BAAANQAECggIDwABNQAECgoKRAAKAOkhAA==.Solder:BAAANQAECgEIAQAAAA==.Soliloquy:BAABNQAECn85AAMfAAoKhRlGDQB1AgAfAAoKhRlGDQB1AgAjAAUKiBEzDwA4AQAAAA==.Solosith:BAAANQADCggIDwAAAA==.',
Sq='Squishyman:BAABNQAECn8+AAIDAAoKGyB1DwDpAgADAAoKGyB1DwDpAgAAAA==.Squishypal:BAAANQAECgQIBgABNQAECgoKPgADABsgAA==.',
St='Stare:BAEANQAECgEIAgABNQAFFAUIEQATAN8gAA==.Stuperdrood:BAAANQAECggIAwABNQAECggIFgANAAAAAA==.Stõrm:BAAANQADCgYIBgABNQAECgcJBwANAAAAAA==.',
Su='Sunoô:BAAANQADCgcIBwAAAA==.Suzsette:BAABNQAECn8dAAIfAAoK8AiSIABsAQAfAAoK8AiSIABsAQAAAA==.',
Sw='Swïper:BAAANQAECgEIAgAAAA==.',
Sy='Sylris:BAAANQADCgIIAgAAAA==.Syrelyia:BAAANQAECgIIAgAAAA==.',
Ta='Tardovski:BAAANQAECgYIEQAAAA==.Taze:BAABNQAECn8XAAQGAAoKuBk/RwBEAgAGAAkKuBk/RwBEAgAMAAQK4xUW9gCTAAAdAAEKAACEagA9AAAAAA==.',
Te='Telda:BAAANQAECgEIAQAAAA==.Teneturadvos:BAAANQAECgIIAgABNQAECggICQANAAAAAA==.Terrorwynd:BAAANQAECgUIDQAAAA==.Tezan:BAAANQADCgUIBQAAAA==.',
Th='Thellaria:BAAANQAECgEIBAAAAA==.Thiccterror:BAAANQAECgQIBAAAAA==.Thumpér:BAAANQADCgQIBAAAAA==.Thunderkeg:BAAANQAECgEIAQAAAA==.',
Ti='Tirgo:BAAANQABCgQIBQAAAA==.',
Tr='Traevel:BAAANQADCgYIBgABNQAECgEIAQANAAAAAA==.Travesti:BAAANQADCgQIBAAAAA==.Trañsformer:BAAANQAECgEIAgAAAA==.Treala:BAAANQADCgUICQABNQAECgQIEAANAAAAAA==.Treme:BAAANQAECgUIDAAAAA==.Troche:BAABNQAECn8cAAIdAAcK8hoBIADlAQAdAAcK8hoBIADlAQABNQAECgkJIQAIAC8NAA==.Truthfully:BAABNQAECn8gAAIGAAoKcguTuwBFAQAGAAoKcguTuwBFAQAAAA==.',
Tt='Ttjpll:BAAANQAECgQIDgAAAA==.',
Tu='Tuckncloak:BAAANQAECgcIBwAAAA==.',
Un='Undeadtoast:BAABNQAECn8mAAIlAAkKLhdlNQA2AgAlAAkKLhdlNQA2AgABNQAFFAcIFwAdAPYcAA==.Unhappytoast:BAACNQAFFH8XAAIdAAcK9hzMAQCkAQAdAAcK9hzMAQCkAQA1AAQKfykAAh0ACgqWI2IJAAcDAB0ACgqWI2IJAAcDAAAA.Unstobubble:BAAANQAECgMIAwAAAA==.',
Ur='Uriania:BAAANQADCgIIAgAAAA==.',
Us='Ushioni:BAACNQAFFH8OAAIaAAQKDwuvHgAWAQAaAAQKDwuvHgAWAQA1AAQKfykAAhoACgqzFuFmAFsCABoACgqzFuFmAFsCAAAA.',
Va='Valeriya:BAAANQADCgYICgABNQAECgMICAANAAAAAA==.Valisanna:BAAANQADCgYIDgAAAA==.Valklemor:BAAANQAECgEIBQAAAA==.Vallorien:BAABNQAECn8YAAIdAAYK8h1kJAA2AQAdAAYK8h1kJAA2AQAAAA==.',
Ve='Velaryn:BAAANQAECgcJBwAAAA==.Vengeânce:BAAANQADCgYICwAAAA==.Verenoth:BAAANQAECgIIBAAAAA==.',
Vi='Viveca:BAABNQAECn84AAIMAAkKuyPlBwCUAwAMAAkKuyPlBwCUAwAAAA==.Viztrix:BAAANQABCgIIAgAAAA==.',
Vu='Vulpe:BAAANQADCgEIAQABNQAECggICQANAAAAAA==.',
['Và']='Vàli:BAAANQAECgEIBQAAAA==.',
Wh='Whiteparrot:BAAANQAECgcICQAAAA==.Wholy:BAABNQAECn80AAMMAAoKsB4tHQDAAgAMAAoKsB4tHQDAAgAGAAQK5hJxNwHHAAAAAA==.',
Wo='Woden:BAAANQAFFAEIAgABNQAECgkJGwAfAAYkAA==.',
Wr='Wreckxneffec:BAAANQAECggICQAAAA==.',
Xa='Xaanii:BAABNQAECn8VAAIMAAUKYhw9eQA2AQAMAAUKYhw9eQA2AQAAAA==.Xarferrin:BAAANQAECgMIAwAAAA==.',
Xe='Xeeria:BAACNQAFFH8KAAMBAAUK0hB6DgBVAQABAAUK0hB6DgBVAQARAAEKtgEaMwBDAAA1AAQKfy4AAwEACgqvHZgoAMECAAEACgqvHZgoAMECABEAAwpfFMviANEAAAAA.Xenzull:BAAANQAECgEIAQAAAA==.Xey:BAAANQABCgIIAgAAAA==.',
Xh='Xhardcore:BAAANQADCgYIBQAAAA==.',
Xu='Xuecat:BAAANQADCggIEQAAAA==.Xuefeiyan:BAAANQAECgUIBwAAAA==.',
Yu='Yuni:BAAANQADCgEIAQAAAA==.',
Za='Zadee:BAAANQADCgYIBwAAAA==.Zaralina:BAABNQAECn8hAAIfAAoKwgx0IwBSAQAfAAoKwgx0IwBSAQAAAA==.Zarithra:BAAANQAECgEIAwAAAA==.Zarynth:BAAANQAECgUIBQAAAA==.Zaryssa:BAAANQAECgQIBwAAAA==.',
Ze='Zenagosa:BAAANQAECgEIAwAAAA==.Zenzhu:BAAANQAECgQICAAAAA==.Zenzug:BAAANQADCgUIBQAAAA==.Zeronightt:BAAANQADCgMIAwAAAA==.',
Zh='Zharazi:BAAANQABCgQIBAABNQAECgEIAQANAAAAAA==.Zhieri:BAAANQADCgUICAAAAA==.',
Zm='Zmaj:BAAANQABCgIIAgAAAA==.',
Zo='Zombiehunter:BAABNQAECn8rAAIKAAgKshRLcAAxAgAKAAgKshRLcAAxAgAAAA==.Zomboy:BAAANQAECgEIAQAAAA==.Zornqueff:BAAANQADCggICAAAAA==.Zortax:BAAANQAECgcIDgAAAA==.',
Zu='Zu:BAAANQAECgUICgAAAA==.Zug:BAABNQAECn8iAAIKAAoKixgFdwC0AQAKAAoKixgFdwC0AQAAAA==.Zurgyn:BAAANQAECgIIAgAAAA==.',
['Âr']='Ârc:BAAANQAECgMIBQAAAA==.',
['Ðr']='Ðream:BAAANQAECggICAABNQAECggICQANAAAAAA==.',
['ßl']='ßlue:BAABNQAECn8iAAMlAAoKmRGOJADHAQAlAAkK8BOOJADHAQAbAAIKRwPwkgAcAAAAAA==.',
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
