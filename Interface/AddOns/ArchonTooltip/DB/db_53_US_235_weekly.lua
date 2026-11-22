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

local lookup = {'Shaman-Restoration','DemonHunter-Devourer','Warlock-Demonology','Druid-Balance','Hunter-Marksmanship','Paladin-Retribution','Warlock-Destruction','Evoker-Devastation','Priest-Holy','Mage-Fire','Hunter-BeastMastery','Druid-Restoration','Paladin-Holy','Unknown-Unknown','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Warlock-Affliction','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','Druid-Feral','Druid-Guardian','Mage-Frost','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Paladin-Protection','Hunter-Survival','Priest-Shadow','DemonHunter-Havoc','DemonHunter-Vengeance','DeathKnight-Frost','Priest-Discipline','Monk-Windwalker','DeathKnight-Blood','Monk-Mistweaver',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=53,date='2026-11-17',data={Ad='Addisyn:BAAANQAECgEIAQAAAA==.',
Ae='Aemetris:BAABNQAECn8aAAIBAAkK2hHaagB0AQABAAkK2hHaagB0AQAAAA==.Aendrel:BAABNQAECn82AAICAAoK+SDFCgCoAgACAAoK+SDFCgCoAgAAAA==.',
Ai='Airaquafira:BAABNQAECn8sAAIBAAoK5x5LKQC+AgABAAoK5x5LKQC+AgAAAA==.',
Aj='Ajheria:BAAANQADCgYIDQABNQAECgoKIgADACMVAA==.',
Al='Alejandro:BAAANQAECggICgAAAA==.Alégria:BAAANQAECgcIDAAAAA==.',
Am='Amiragosa:BAAANQABCgYICAAAAA==.',
An='Anaire:BAAANQAECgEIAQAAAA==.Anaiya:BAAANQADCgEIAQAAAA==.Anaru:BAABNQAECn8vAAIEAAoKqwWePwArAQAEAAoKqwWePwArAQAAAA==.Andalaine:BAAANQADCggIHwAAAA==.Angriff:BAAANQAECgEIAQAAAA==.Anraleth:BAABNQAECn9HAAIFAAoKSiTrAwCYAwAFAAoKSiTrAwCYAwAAAA==.Anxiqtt:BAAANQAECgEIAQAAAA==.',
Ar='Arckillion:BAABNQAECn8fAAIGAAoKwBclWgAhAgAGAAoKwBclWgAhAgAAAA==.Arcángel:BAAANQAECgIIAgAAAA==.Arduous:BAAANQADCgcIBwAAAA==.Ariana:BAAANQADCgYIDAAAAA==.Arkadio:BAAANQABCgIIAgAAAA==.Armâgeddon:BAAANQADCgYIBgAAAA==.',
As='Asparagus:BAAANQAECggIDgAAAA==.Asturoth:BAAANQADCggIDgAAAA==.',
Au='Aust:BAAANQADCgcIBwAAAA==.Authority:BAAANQAECggICQAAAA==.',
Av='Averlis:BAABNQAECn8ZAAIEAAcKhhASXQBdAQAEAAcKhhASXQBdAQAAAA==.Avoiddance:BAAANQADCgYICgABNQAECgoKIgADACMVAA==.',
Ay='Ayci:BAAANQAECgQIBgAAAA==.',
Az='Azmithrilim:BAABNQAECn8YAAIFAAgKygOjNQDOAAAFAAgKygOjNQDOAAAAAA==.Azurargentyr:BAAANQABCgEIAQAAAA==.',
Ba='Baconbo:BAAANQAECgUIDwAAAA==.Batistabomba:BAAANQADCgUIBQAAAA==.',
Be='Bellyroll:BAAANQAECgEIAQAAAA==.Bended:BAABNQAECn9BAAMDAAoKBhclNAA/AgADAAoKvBYlNAA/AgAHAAQKfBZ+MQABAQAAAA==.',
Bl='Blikey:BAAANQAECgcIBwAAAA==.Bloodyrott:BAAANQADCgIIAgAAAA==.Bluedrake:BAACNQAFFH8FAAIIAAMKTxf6AgDgAAAIAAMKTxf6AgDgAAA1AAQKfyEAAggACgqtHJMGADsCAAgACgqtHJMGADsCAAE1AAUUBggKAAQA9xkA.Blueparrot:BAABNQAECn9BAAIJAAoKlxL+NgBhAgAJAAoKlxL+NgBhAgAAAA==.',
Bo='Bocantwo:BAAANQAECgEJAQAAAA==.Boggyboomer:BAAANQADCgMIAwAAAA==.Bombfaucet:BAAANQADCgEIAQAAAA==.Bowkatan:BAAANQADCgQIBAAAAA==.',
Br='Brewteaful:BAAANQADCgEIAQAAAA==.Brickt:BAAANQAECgQIBAABNQAECgoKOAAKAKcgAA==.Bringinlight:BAABNQAECn8ZAAIJAAcKSgEPzQCMAAAJAAcKSgEPzQCMAAABNQAECgkJHwALAOYGAA==.',
Bu='Bubbleicious:BAAANQAECgEIAQAAAA==.Bubbletea:BAAANQAECgMICQABNQAECgoKRAALAOkhAA==.Bubbleyum:BAAANQADCgQIBAAAAA==.Bulletz:BAAANQAECgYICgAAAA==.Buzzsha:BAAANQAECgUICAAAAA==.',
Ca='Cahhwa:BAAANQADCgMIAwAAAA==.Camillie:BAAANQADCgIIAgAAAA==.Casanna:BAAANQADCgQIBAAAAA==.Cassandria:BAABNQAECn9EAAMEAAoKnQy1KwCkAQAEAAoKnQy1KwCkAQAMAAcKNg1pMwBWAQAAAA==.Cassiradra:BAAANQAECgEIAQAAAA==.',
Ce='Cervixticklr:BAAANQAECggICwAAAA==.',
Ch='Chathlia:BAAANQABCgIIAgAAAA==.Choglana:BAAANQADCgQIBAAAAA==.Chogric:BAABNQAECn8sAAINAAoKQyO0CwBrAwANAAoKQyO0CwBrAwABNQADCgQIBAAOAAAAAA==.Châos:BAABNQAECn8rAAIGAAkKLRMqjgCvAQAGAAkKLRMqjgCvAQAAAA==.',
Ci='Cif:BAAANQAECgQICQAAAA==.Civetta:BAABNQAECn8rAAILAAoKJxbGUQB7AgALAAoKJxbGUQB7AgAAAA==.',
Cr='Crazzywazzy:BAAANQAECgYIDgAAAA==.Crona:BAAANQAECgcIEQAAAA==.Crzyblnkrton:BAACNQAFFH8XAAIPAAcKHQ2OGAC0AQAPAAcKHQ2OGAC0AQA1AAQKfywAAg8ACgpjHw5JADICAA8ACgpjHw5JADICAAAA.Crzzy:BAAANQAECgQIBAAAAA==.Crzzyystabby:BAABNQAECn8ZAAMQAAoK/RfFJgBoAgAQAAoK/RfFJgBoAgARAAEKZg0+ZwAxAAAAAA==.',
Cu='Cultera:BAACNQAFFH8FAAICAAIK3Am/DgBsAAACAAIK3Am/DgBsAAA1AAQKfzoAAgIACgqYHyEMAB8DAAIACgqYHyEMAB8DAAAA.Cuzon:BAABNQAECn8ZAAMBAAoKqhsGPQBrAgABAAoKqhsGPQBrAgASAAYK/he/kQB4AQABNQAFFAMICAAMAEUTAA==.',
Cy='Cyhyraethia:BAABNQAECn8vAAITAAoKxBkOAwDVAgATAAoKxBkOAwDVAgABNQAFFAQIDwACAGAZAA==.',
Da='Dagden:BAAANQAECgUIBQAAAA==.Daish:BAAANQADCgMIAwAAAA==.Danda:BAAANQADCggIFgAAAA==.Dare:BAAANQAFFAQIBAABNQAFFAYICAAQANALAA==.Daricepicker:BAABNQAECn9EAAILAAoK6SG5GADhAgALAAoK6SG5GADhAgAAAA==.Darkyn:BAABNQAECn8iAAIDAAoKIxV/awAbAgADAAoKIxV/awAbAgAAAA==.',
Dd='Ddeonù:BAACNQAFFH8LAAICAAQKJAOUDACSAAACAAQKJAOUDACSAAA1AAQKfyoAAgIACgrtFFwhAEECAAIACgrtFFwhAEECAAAA.',
De='Deadlysins:BAAANQADCggICAABNQAECggICQAOAAAAAA==.Deadscar:BAECNQAFFH8WAAIUAAYK0R+FAQBxAQAUAAYK0R+FAQBxAQA1AAQKfz0AAhQACgozJYYCAIIDABQACgozJYYCAIIDAAAA.Deathmasterj:BAAANQADCggIDwAAAA==.Deaths:BAAANQAECggIDgAAAA==.Delphinium:BAAANQADCgYIDAAAAA==.Dentheaded:BAACNQAFFH8oAAIGAAcKaiQ/AQCyAgAGAAcKaiQ/AQCyAgA1AAQKfz8AAgYACgprJoAIAFcDAAYACgprJoAIAFcDAAAA.',
Di='Diablosucio:BAAANQADCgMIAwAAAA==.Dithariaa:BAAANQAECgUIBQAAAA==.',
Do='Docryktor:BAABNQAECn9CAAIUAAoKQBiHEABhAgAUAAoKQBiHEABhAgAAAA==.Doomgears:BAAANQAECgMIAwAAAA==.',
Dr='Draculä:BAAANQAECgEIAQABNQAECgcJBwAOAAAAAA==.Drashta:BAAANQAECgYIDgAAAA==.Drhurtouch:BAAANQAECgQIEQAAAA==.Drogas:BAABNQAECn9AAAQVAAoK7xOcDABXAgAVAAoK7xOcDABXAgAIAAYKsQeYJAAbAQAWAAUK3wsDFQDeAAAAAA==.Drtybear:BAABNQAECn8ZAAMXAAYKKhV/JADdAAAXAAYKvhB/JADdAAAYAAUKkhUIOgDcAAAAAA==.Druithz:BAAANQAECgQIBAABNQAFFAQIBwANACkXAA==.Drussila:BAAANQADCgQIBAABNQAECgcIDAAOAAAAAA==.',
['Dâ']='Dârrius:BAAANQADCggICQAAAA==.',
Eb='Ebonwings:BAAANQAECggIBwAAAA==.',
Ed='Ediana:BAACNQAFFH8GAAIPAAMK0wCzSgBJAAAPAAMK0wCzSgBJAAA1AAQKfykAAw8ACgorB9P/AI4BAA8ACgorB9P/AI4BABkAAgpyA3NBAEEAAAAA.Edisian:BAAANQABCgQIBAAAAA==.',
Ee='Eebz:BAAANQADCggIDAAAAA==.Eebzy:BAABNQAECn8eAAMaAAoKDBIWHgAPAQAaAAoKDBIWHgAPAQAbAAIKZAf6OAEhAAAAAA==.',
El='Elandrah:BAABNQAECn8VAAIJAAcKkgJBsAAGAQAJAAcKkgJBsAAGAQAAAA==.Elithsong:BAAANQABCgIIAgAAAA==.Elmô:BAABNQAECn9NAAINAAoK5x03DgBRAwANAAoK5x03DgBRAwAAAA==.',
Es='Essence:BAAANQADCgYIBgAAAA==.Estameling:BAABNQAECn9BAAIYAAkK5xFaHwCHAQAYAAkK5xFaHwCHAQAAAA==.',
Et='Etherah:BAAANQABCgEIAQAAAA==.',
Ex='Excizion:BAABNQAECn8cAAIcAAkKbw8aZQB8AQAcAAkKbw8aZQB8AQAAAA==.',
Fa='Fantabulouus:BAABNQAECn8pAAIbAAoKLxG7XADpAQAbAAoKLxG7XADpAQAAAA==.Fantym:BAAANQABCgYJBgAAAA==.Farorê:BAAANQABCgEIAQAAAA==.Fatherrahl:BAAANQAECggICAAAAA==.Fathertim:BAAANQAECgUIBQAAAA==.',
Fe='Feldrena:BAAANQADCggIEQAAAA==.',
Fi='Fistvendor:BAAANQADCgIIAgAAAA==.',
Fl='Flangus:BAAANQADCgYICQAAAA==.',
Fo='Forgiven:BAABNQAECn8XAAIEAAgKLSOYLQBwAgAEAAgKLSOYLQBwAgAAAA==.Foxyhound:BAAANQAECggIBgAAAA==.',
Fr='Franksredhot:BAAANQAECgEIAQAAAA==.Frostii:BAAANQAECgYICwAAAA==.',
Fu='Fudestamp:BAABNQAECn8dAAIGAAoKOgkSxABMAQAGAAoKOgkSxABMAQAAAA==.Fugryktor:BAABNQAECn8jAAITAAgKuA90DAB5AQATAAgKuA90DAB5AQABNQAECgoKQgAUAEAYAA==.Fuu:BAAANQABCgMJAwAAAA==.Fuzzywuzzy:BAAANQADCgYIBgAAAA==.',
Fy='Fyre:BAAANQADCgYIBQAAAA==.',
Ga='Gagarazzi:BAAANQADCgMIAwAAAA==.Galandor:BAABNQAECn8XAAINAAYK/x2KWAC0AQANAAYK/x2KWAC0AQAAAA==.Galethia:BAAANQADCgMIAwAAAA==.Gandaalf:BAABNQAECn84AAQKAAoKpyAWAgAOAgAKAAgK+x8WAgAOAgAZAAQK8hqIGwD8AAAPAAEKAABCqwFqAAAAAA==.Gandelfzz:BAAANQADCgEIAQAAAA==.',
Ge='Geedorah:BAAANQADCgIIAgAAAA==.Gemhide:BAABNQAECn8dAAMHAAoKww+iCABCAQAHAAoKww+iCABCAQADAAMKvQPULgFfAAAAAA==.Gerbo:BAAANQABCgIIAwAAAA==.',
Gi='Gityadruid:BAAANQADCgYINwABNQAECgkJHwALAOYGAA==.Gityahunter:BAABNQAECn8fAAILAAkK5gZomwB9AQALAAkK5gZomwB9AQAAAA==.',
Go='Gobanks:BAABNQAECn9AAAMdAAoKMx98CAAWAwAdAAoKMx98CAAWAwAGAAQKog9A+gDyAAAAAA==.',
Gr='Grayarms:BAAANQAECgQIBwAAAA==.Graygoat:BAAANQADCgYIBgABNQAFFAkJJgAeANYlAA==.Grayresto:BAAANQAECgMIBgAAAA==.Grayson:BAABNQAECn8ZAAIGAAUKJwXBTgF9AAAGAAUKJwXBTgF9AAAAAA==.Graysurv:BAACNQAFFH8mAAIeAAkK1iUDAABjAwAeAAkK1iUDAABjAwA1AAQKfzQAAh4ACgr7JmIAAM8DAB4ACgr7JmIAAM8DAAAA.Grimik:BAABNQAECn8aAAMFAAoK1wmlNgCZAQAFAAkKHgelNgCZAQALAAoKnwgmzQBnAQAAAA==.Grimwali:BAAANQAECgUICgAAAA==.',
Ha='Hallêlujah:BAAANQABCgMIBAAAAA==.Hamelot:BAAANQAECgEIAQAAAA==.Hamremmi:BAAANQADCgIIAgABNQAECgkJGwAfAAYkAA==.Hardrock:BAEANQADCgcIEAABNQAECgoKOgASACMLAA==.',
He='Healsforu:BAAANQAECgEIAQAAAA==.Healulater:BAAANQADCgUIBwABNQAECgYIDgAOAAAAAA==.Herbievore:BAAANQAECgQIBAABNQAECgoKOAAKAKcgAA==.',
Hi='Highbrittz:BAAANQAECgcIBwAAAA==.',
Ho='Hobiscuits:BAEANQABCgcIEQABNQAECgoKGAADAEsYAA==.Hodgy:BAAANQADCgQIBAAAAA==.',
Hu='Hurtfinger:BAAANQADCgYIEwAAAA==.',
Hy='Hydrobubble:BAAANQAECgEIAQAAAA==.',
Il='Illyy:BAAANQAECgQIBgAAAA==.',
Im='Imagine:BAABNQAECn8gAAMIAAoKQh3ZBACCAgAIAAkKQh3ZBACCAgAVAAgKBwx4IwCqAQAAAA==.',
In='Indagussy:BAAANQAECgcIEgABNQAFFAgIFQAgAKQbAA==.Indawhole:BAACNQAFFH8VAAMgAAgKpBvIAwA/AgAgAAcKThzIAwA/AgACAAEKUBgbEABSAAA1AAQKfzMABCAACgpIJQcVAPUCACAACQoYJQcVAPUCAAIACgr6HuUYAOoBACEAAQoKEyQtAD0AAAAA.',
Ir='Ironsparc:BAAANQADCggICAABNQAECgoKIgADACMVAA==.',
Is='Isamna:BAAANQABCgIJAgAAAA==.',
Iv='Ivi:BAAANQADCgUIBQAAAA==.',
Iz='Izumiwitabow:BAAANQAECgQIEgAAAA==.',
Ja='Jasmean:BAAANQAECgMIBQAAAA==.Jassabella:BAAANQAECgEIAgAAAA==.Javaluminous:BAABNQAECn9EAAIGAAoKoxbHUAA6AgAGAAoKoxbHUAA6AgAAAA==.Jaytsukitori:BAACNQAFFH8IAAIMAAMKRRNnDQDTAAAMAAMKRRNnDQDTAAA1AAQKfxoABAwACQrTIA80AHoBAAwABgrlHg80AHoBAAQABgoVE3xjAEABABgAAQoAAN5kACsAAAAA.',
Jd='Jdots:BAAANQADCggIEwAAAA==.',
Jh='Jhantherox:BAAANQABCgQIBAABNQAECgoKIgADACMVAA==.Jheranton:BAAANQAECgEIAQABNQAECgoKIgADACMVAA==.',
Ji='Jiannae:BAAANQADCgIIAgABNQAECgkJGgABANoRAA==.Jif:BAAANQAECggIEQAAAA==.',
Jo='Joesepi:BAACNQAFFH8FAAIcAAIKHBnjCgCrAAAcAAIKHBnjCgCrAAA1AAQKfywAAhwACgruGvAOAI4CABwACgruGvAOAI4CAAAA.Jonah:BAABNQAECn8qAAQHAAoKGSNeBADRAQATAAkKrx71BACAAgADAAgK1h5xUwBbAgAHAAgKaSBeBADRAQABNQAECgoKKAAcAFUkAA==.Joodee:BAABNQAECn8eAAIBAAcKShFsfwA1AQABAAcKShFsfwA1AQAAAA==.Jordi:BAAANQADCgcIBwAAAA==.Joseon:BAAANQAECgQICQABNQAECgoKNwAMADQlAA==.',
Ka='Kackarot:BAABNQAECn8nAAISAAkK/RLGUQAyAgASAAkK/RLGUQAyAgAAAA==.Kartelz:BAABNQAECn8fAAIgAAoKHQdvRQAbAQAgAAoKHQdvRQAbAQAAAA==.Katrine:BAABNQAECn84AAIiAAoK2xdNKgBIAgAiAAoK2xdNKgBIAgAAAA==.',
Ke='Kendreth:BAAANQADCgQICAAAAA==.',
Ki='Kij:BAECNQAFFH8TAAMZAAYKbRyQAQAyAQAZAAQK7heQAQAyAQAPAAMKpRpCSQCWAAA1AAQKfzYAAxkACgodIx0JABgCAA8ACgpQIC1RAN4CABkABwreHh0JABgCAAAA.Kilrah:BAABNQAECn8qAAIgAAoK9AmqQgCtAQAgAAoK9AmqQgCtAQAAAA==.Kissmycrits:BAABNQAECn8uAAILAAkKthLMdADVAQALAAkKthLMdADVAQAAAA==.Kissmywrath:BAABNQAECn8ZAAIGAAoKcwgGuwBcAQAGAAoKcwgGuwBcAQAAAA==.Kiyoine:BAABNQAECn8vAAIXAAkKdxF7EQCwAQAXAAkKdxF7EQCwAQAAAA==.',
Kn='Knocksteady:BAAANQAECgcIEAAAAA==.Knoxreaps:BAAANQADCgUIBQAAAA==.',
Ko='Kookie:BAAANQAECgYICQAAAA==.',
Kr='Kryyng:BAAANQADCgMIAwAAAA==.Krzyng:BAAANQADCgMIAwAAAA==.',
Ky='Kynbrookera:BAABNQAECn8yAAIMAAoK0RIJHAAoAgAMAAoK0RIJHAAoAgAAAA==.',
Kz='Kzmyng:BAAANQADCgcIBwAAAA==.',
['Kì']='Kìnky:BAAANQADCgcIBwAAAA==.',
La='Lacquerhead:BAAANQADCgQIBAABNQADCgYIBgAOAAAAAA==.Laetha:BAAANQADCggIFQABNQAECgoKIwAIAHoSAA==.Larriat:BAAANQADCgcICAAAAA==.Layonscoob:BAAANQAECgYIBwAAAA==.',
Le='Leefs:BAAANQAECgcICAABNQAECggIEwAOAAAAAA==.',
Li='Lightweaver:BAAANQAECggICQAAAA==.Linai:BAABNQAECn9IAAIQAAoKdAvRHQDkAQAQAAoKdAvRHQDkAQAAAA==.Linthe:BAACNQAFFH8FAAINAAIKbgs4IAB+AAANAAIKbgs4IAB+AAA1AAQKfyQAAw0ACgoyDqxqANcBAA0ACgoyDqxqANcBAAYAAQp3BqCuATAAAAAA.Lit:BAABNQAECn8eAAMNAAkKSQrxggAuAQANAAkKSQrxggAuAQAGAAEKAAAaqwEyAAAAAA==.Lites:BAAANQAECggIEwAAAA==.Lithica:BAAANQAECgEIAQAAAA==.Littledog:BAACNQAFFH8GAAIJAAUKrgyqFgBOAQAJAAUKrgyqFgBOAQA1AAQKfyEABB8ACQqmD8s/ADABAB8ABwpCEss/ADABAAkABAqZGK6QACcBACMABgpdEIAQACEBAAAA.',
Lo='Lockdout:BAAANQADCgQIBAABNQAECgYIDgAOAAAAAA==.Lokiantonio:BAAANQADCgQIBAAAAA==.Longshenks:BAAANQADCgIIAgAAAA==.Lotten:BAABNQAECn8pAAIGAAgKJRhPiAAWAgAGAAgKJRhPiAAWAgAAAA==.',
Lu='Luckevin:BAAANQAECggICAAAAA==.Lumi:BAAANQAECgIIBAAAAA==.Lurashtai:BAAANQAECgYIDAAAAA==.Luvido:BAAANQABCgcICQAAAA==.',
Ma='Magicmann:BAAANQADCgUIBwAAAA==.Magicor:BAAANQADCggICAAAAA==.Malafang:BAAANQAECgMIBgAAAA==.Malanah:BAAANQAECgQIDwAAAA==.Malgaren:BAAANQABCggIEwAAAA==.Malphen:BAAANQADCggICAABNQAECgoKHwAMAEMVAA==.Mangoo:BAAANQADCgYIBgAAAA==.Marandra:BAAANQADCgcIFgAAAA==.Maverick:BAACNQAFFH8IAAIQAAYK0Av4CQBCAQAQAAYK0Av4CQBCAQA1AAQKfy4AAhAACgooIcEGABMDABAACgooIcEGABMDAAAA.',
Me='Meregryn:BAAANQADCgUIBQAAAA==.Merunyaa:BAAANQAECgcIDQAAAA==.',
Mi='Michaella:BAAANQADCgYIEAAAAA==.Mil:BAAANQADCgQJBQAAAA==.Minipwn:BAABNQAECn8YAAIZAAkKcQ10EwBxAQAZAAkKcQ10EwBxAQAAAA==.',
Mk='Mk:BAEANQAECgUIBgABNQAECgoKPQAkAFkfAA==.',
Mo='Mogar:BAABNQAECn8YAAIbAAkKIQvlyQBjAQAbAAkKIQvlyQBjAQAAAA==.Moogician:BAAANQAECgUIBAAAAA==.Moonzhine:BAAANQADCggJEQAAAA==.Moosejaw:BAAANQAECgQIBgAAAA==.Mordread:BAAANQAECgQICQAAAA==.Morgalruk:BAAANQADCgcIFgAAAA==.',
My='Mythx:BAACNQAFFH8OAAILAAYKhBUaBgCZAQALAAYKhBUaBgCZAQA1AAQKfykAAwsACgpgIvMiAAsDAAsACgpgIvMiAAsDAAUACArsDig2AJ0BAAAA.',
['Mý']='Mýthh:BAAANQADCggIAQAAAA==.',
Na='Naturboy:BAAANQADCgYIBgAAAA==.',
Ne='Netherward:BAACNQAFFH8fAAMTAAgKHx1aAAAjAgATAAcKVx9aAAAjAgADAAYKYhniCgC9AQA1AAQKfz8AAxMACgphJfoAAGwDABMACgqoJPoAAGwDAAMACAp6I3koAG0CAAE1AAQKCQkbAB8ABiQA.',
Ni='Niknikboy:BAAANQABCgYICwAAAA==.Nivmizzet:BAACNQAFFH8GAAMDAAMKgAroJwCTAAADAAIKfw7oJwCTAAAHAAEKgwJCFgA7AAA1AAQKf1cAAwMACgoWH+YYALkCAAMACgrUHuYYALkCAAcAAgoYG0hLAJ4AAAAA.',
No='Nolakai:BAAANQAECgQIBAAAAA==.Nonliving:BAAANQADCgYIBgAAAA==.Novagosa:BAAANQAECgUICwABNQAECgoKRgABAMglAA==.Novalea:BAABNQAECn9GAAMBAAoKyCXcBQC8AwABAAoKyCXcBQC8AwASAAUK8RA1jQDxAAAAAA==.Nozom:BAAANQADCgYIBgAAAA==.',
Np='Np:BAAANQAECgMJBQAAAA==.',
Nu='Nutcutter:BAAANQAECgQIBQABNQAECgoKLQAcAN4MAA==.',
Ny='Nyriune:BAAANQADCggICAAAAA==.Nyvera:BAAANQAECgUIBQAAAA==.Nyxon:BAAANQADCgYIEQAAAA==.',
Os='Osirus:BAAANQAECgIIAgAAAA==.',
Ou='Outforarip:BAAANQAECggICAAAAA==.',
Ox='Oxxo:BAAANQAECgUIBQAAAA==.',
Pa='Palomar:BAAANQAECgQIDgAAAA==.Paraggonn:BAABNQAECn8gAAILAAgKnBH/iwCfAQALAAgKnBH/iwCfAQAAAA==.',
Ph='Pherkle:BAAANQAECgQICwABNQAECgoKQgAUAEAYAA==.Phuriosa:BAAANQAECgIIAgABNQAECgoKHgAMACkSAA==.Phury:BAABNQAECn8eAAIMAAoKKRJiKADdAQAMAAoKKRJiKADdAQAAAA==.Physinyx:BAABNQAECn8/AAMSAAoKTxksIwBgAgASAAoKTxksIwBgAgABAAgKmwAn8gCGAAAAAA==.',
Pi='Pizza:BAAANQAECgUIBQAAAA==.',
Po='Pomomies:BAAANQABCgIIAgAAAA==.Pooseunpoose:BAABNQAECn8dAAIlAAoKzRY3KAC9AQAlAAoKzRY3KAC9AQAAAA==.',
Pr='Preparedrice:BAAANQAECgUICQABNQAECgoKRAALAOkhAA==.Profryktor:BAAANQAECgUIBQAAAA==.',
Pu='Pumbaa:BAAANQAECgIIAgABNQAECgcJBwAOAAAAAA==.Purpleparrot:BAAANQADCggICAAAAA==.',
Qu='Quilby:BAAANQADCgUICgAAAA==.',
Ra='Raenyx:BAABNQAECn84AAMDAAoKhw1EjABEAQADAAoKhw1EjABEAQAHAAEKAADNhwAeAAABNQAECgoKPwASAE8ZAA==.Ragnarrok:BAAANQADCgYIBgAAAA==.Raif:BAABNQAECn8uAAIKAAgKlBCnAwB3AQAKAAgKlBCnAwB3AQAAAA==.Randir:BAAANQADCgIIAgAAAA==.Raveneyes:BAEBNQAECn8bAAIDAAoKBwoRwgBHAQADAAoKBwoRwgBHAQAAAA==.',
Re='Reightous:BAAANQAECgQIBwAAAA==.Reylilyn:BAABNQAECn8mAAImAAoKKBA5FQCvAQAmAAoKKBA5FQCvAQAAAA==.Reynarena:BAAANQAECgQIBgAAAA==.',
Rh='Rhaenfyre:BAACNQAFFH8HAAMCAAQKyQ6zCQDHAAACAAQKyQ6zCQDHAAAgAAEKkA0/HAA/AAA1AAQKfz0AAwIACgpTILULAJcCAAIACgpTILULAJcCACAAAwrMFTxmAIwAAAAA.',
Ri='Ripley:BAAANQAECgcIBwABNQAFFAYICAAQANALAA==.Rivenel:BAACNQAFFH8RAAMHAAYKVA9GBQCdAAADAAQKdwsoGgDbAAAHAAIKIRVGBQCdAAA1AAQKf0gAAwcACgquItoFALQCAAcACAqXH9oFALQCAAMACAryIe8tAFcCAAAA.',
Ro='Robinvoid:BAABNQAECn8aAAMCAAoKThtBFgCwAgACAAoKThtBFgCwAgAgAAEK3wsNkwA1AAAAAA==.Rodel:BAAANQAECgQICAAAAA==.Rondrey:BAAANQADCgYIBgAAAA==.Roquan:BAABNQAECn86AAIiAAkK6BEWMADrAQAiAAkK6BEWMADrAQAAAA==.Rosè:BAAANQAECgYIBgABNQAFFAYICAAQANALAA==.',
Ru='Rubmyrott:BAAANQAECgEIAQAAAA==.Runawäy:BAAANQAECgYIDgAAAA==.Rundas:BAAANQAECgcIDAAAAA==.',
['Ré']='Rébél:BAAANQADCgYICAAAAA==.',
['Rê']='Rêdd:BAABNQAECn80AAIfAAoK/xA1FwDyAQAfAAoK/xA1FwDyAQAAAA==.',
['Rì']='Rìven:BAAANQADCgYICAAAAA==.',
Sa='Sabeion:BAAANQAECggIEQAAAA==.Saddie:BAAANQADCggIGgAAAA==.Saharaa:BAAANQAECgEIAwAAAA==.Salswarriah:BAABNQAECn8VAAIbAAUKVwZv/AB7AAAbAAUKVwZv/AB7AAAAAA==.Sanasath:BAABNQAECn8iAAMIAAkKLw01DQB6AQAIAAkKLw01DQB6AQAVAAgK/A4NLgAxAQAAAA==.',
Sc='Scrumbles:BAAANQAECggIEQAAAA==.',
Se='Sealgair:BAAANQADCgYIBgAAAA==.Segador:BAAANQAECgYICAAAAA==.Seonwoo:BAAANQAECgEIAQAAAA==.Seraphim:BAAANQADCggICAAAAA==.',
Sg='Sgtbonesnap:BAAANQADCgUIBQABNQAECgEIAQAOAAAAAA==.',
Sh='Shamanizim:BAACNQAFFH8OAAISAAQKohtqEADoAAASAAQKohtqEADoAAA1AAQKf0oAAhIACgpVJJoQAGgDABIACgpVJJoQAGgDAAAA.Shamanka:BAAANQADCgIIAgAAAA==.Sheetara:BAAANQAECgQIBAAAAA==.Shenzii:BAAANQAECgQICAAAAA==.Shikigami:BAAANQABCgcICAAAAA==.Shinoikari:BAAANQADCgYIEwABNQAECgoKPgAbAPEQAA==.Shinotenshi:BAAANQAECgUIDQABNQAECgoKPgAbAPEQAA==.Shugarae:BAABNQAECn8xAAIEAAkKUgYZPAA+AQAEAAkKUgYZPAA+AQAAAA==.',
Si='Silvafist:BAAANQAECgEJAwAAAA==.',
Sk='Skreezy:BAAANQAECgYIDAAAAA==.Skuls:BAAANQADCgQIBAAAAA==.Skyrim:BAAANQADCggICAAAAA==.',
Sl='Slashemup:BAABNQAECn8UAAIgAAgKCBFVPQDOAQAgAAgKCBFVPQDOAQAAAA==.Slayter:BAABNQAECn83AAIMAAoKNCX6BQBjAwAMAAoKNCX6BQBjAwAAAA==.',
Sm='Smaugor:BAAANQAECgYIEQABNQAECgcJBwAOAAAAAA==.',
So='Soju:BAAANQAECgcIDgABNQAECgoKRAALAOkhAA==.Solder:BAAANQAECgEIAQAAAA==.Soliloquy:BAABNQAECn87AAMfAAoKfhrjDACMAgAfAAoKfhrjDACMAgAjAAUKiBEzDwA4AQAAAA==.Solosith:BAAANQADCggIDwAAAA==.',
Sq='Squishyman:BAABNQAECn8/AAIDAAoKGyBEEgDgAgADAAoKGyBEEgDgAgAAAA==.Squishypal:BAAANQAECgQIBQABNQAECgoKPwADABsgAA==.',
St='Stare:BAEANQAECgEIAQABNQAFFAYIFgAUANEfAA==.Stuperdrood:BAAANQAECggIAQABNQAECggIFgAOAAAAAA==.Stõrm:BAAANQADCgYIBgABNQAECgcJBwAOAAAAAA==.',
Su='Sunoô:BAAANQADCgcIBwAAAA==.Suzsette:BAABNQAECn8hAAIfAAoK3glMIACIAQAfAAoK3glMIACIAQAAAA==.',
Sy='Sylris:BAAANQADCgIIAgAAAA==.Syrelyia:BAAANQAECgIIAQAAAA==.',
Ta='Tardovski:BAAANQAECgYIDAAAAA==.Taze:BAABNQAECn8YAAQGAAoKcR26NACRAgAGAAkKcR26NACRAgANAAQK4xUW9gCTAAAdAAEKAACEagA9AAAAAA==.',
Te='Telda:BAAANQADCggIGQAAAA==.Teneturadvos:BAAANQAECgIIAgABNQAECggIBwAOAAAAAA==.Terrorwynd:BAAANQAECgUICgAAAA==.Tezan:BAAANQADCgUIBQAAAA==.',
Th='Thellaria:BAAANQAECgYIBwAAAA==.Thiccterror:BAAANQAECgQIBAAAAA==.Thumpér:BAAANQADCgQIBAAAAA==.Thunderkeg:BAAANQADCgUIBQAAAA==.',
Ti='Tirgo:BAAANQABCgQIBQAAAA==.',
Tr='Traevel:BAAANQADCgYIBgABNQADCgYIBgAOAAAAAA==.Travesti:BAAANQADCgQIBAAAAA==.Trañsformer:BAAANQAECgEIAgAAAA==.Treala:BAAANQADCgUICQABNQAECgQIDwAOAAAAAA==.Treme:BAAANQAECgUICgAAAA==.Troche:BAABNQAECn8cAAIdAAcK8hoBIADlAQAdAAcK8hoBIADlAQABNQAECgkJIgAIAC8NAA==.Truthfully:BAABNQAECn8kAAIGAAoKsAwewQBRAQAGAAoKsAwewQBRAQAAAA==.',
Tt='Ttjpll:BAAANQAECgQIDgAAAA==.',
Tu='Tuckncloak:BAAANQAECgcIBwAAAA==.',
Un='Undeadtoast:BAABNQAECn8mAAIlAAkKLhdlNQA2AgAlAAkKLhdlNQA2AgABNQAFFAcIFwAdAPYcAA==.Unhappytoast:BAACNQAFFH8XAAIdAAcK9hw5AgCgAQAdAAcK9hw5AgCgAQA1AAQKfykAAh0ACgqWI2IJAAcDAB0ACgqWI2IJAAcDAAAA.Unstobubble:BAAANQAECgMIAwAAAA==.',
Ur='Uriania:BAAANQADCgIIAgAAAA==.',
Us='Ushioni:BAACNQAFFH8OAAIbAAQKDwuvHgAWAQAbAAQKDwuvHgAWAQA1AAQKfysAAhsACgr/F+FmAFsCABsACgr/F+FmAFsCAAE1AAUUBggXAAsArCMA.',
Va='Valeriya:BAAANQADCgYICgABNQAECgQICAAOAAAAAA==.Valisanna:BAAANQADCgYIDgAAAA==.Valklemor:BAAANQAECgEIAwAAAA==.Vallorien:BAABNQAECn8bAAMdAAcK1Rn5JwAyAQAdAAYK8h35JwAyAQAGAAEKYAm8qAEqAAAAAA==.',
Ve='Velaryn:BAAANQAECgcJBwAAAA==.Vengeânce:BAAANQADCgYICwAAAA==.Verenoth:BAAANQAECgIIBAAAAA==.',
Vi='Viveca:BAABNQAECn9BAAINAAkKOCSpBwCjAwANAAkKOCSpBwCjAwAAAA==.Viztrix:BAAANQABCgIIAgAAAA==.',
Vu='Vulpe:BAAANQADCgEIAQABNQAECggIBwAOAAAAAA==.',
['Và']='Vàli:BAAANQAECgMIBAAAAA==.',
Wh='Whiteparrot:BAAANQAECgcIDAAAAA==.Wholy:BAABNQAECn80AAMNAAoKsB71IAC4AgANAAoKsB71IAC4AgAGAAQK5hJxNwHHAAAAAA==.',
Wo='Woden:BAAANQAFFAEIAgABNQAECgkJGwAfAAYkAA==.',
Wr='Wreckxneffec:BAAANQAECggICQAAAA==.',
Xa='Xaanii:BAAANQAECgQIEgAAAA==.Xarferrin:BAAANQAECgQIBAAAAA==.',
Xe='Xeeria:BAACNQAFFH8KAAMBAAUK0hCcEABUAQABAAUK0hCcEABUAQASAAEKtgEaMwBDAAA1AAQKfy8AAwEACgqvHZgoAMECAAEACgqvHZgoAMECABIAAwpfFMviANEAAAAA.Xenzull:BAAANQAECgEIAQAAAA==.Xey:BAAANQABCgIIAgAAAA==.',
Xh='Xhardcore:BAAANQADCgYIBQAAAA==.',
Xu='Xuecat:BAAANQADCggIEQAAAA==.Xuefeiyan:BAAANQAECgUIBwAAAA==.',
Yu='Yuni:BAAANQADCgEIAQAAAA==.',
Za='Zadee:BAAANQADCggIEgAAAA==.Zaralina:BAABNQAECn8nAAIfAAoKxg3gHQChAQAfAAoKxg3gHQChAQAAAA==.Zarithra:BAAANQAECgEIAQAAAA==.Zarynth:BAAANQAECgQIBQAAAA==.Zaryssa:BAAANQAECgQIBwAAAA==.',
Ze='Zenagosa:BAAANQABCgIIAgAAAA==.Zenzhu:BAAANQAECgQIBwAAAA==.Zenzug:BAAANQADCgUIBQAAAA==.Zephystra:BAAANQAECgcIBwABNQAECgoKRgABAMglAA==.Zeronightt:BAAANQADCgMIAwAAAA==.',
Zh='Zharazi:BAAANQABCgQIBAABNQADCggJEQAOAAAAAA==.Zharfrost:BAAANQADCggIEQABNQAECgoKIgADACMVAA==.Zhieri:BAAANQADCgUICAAAAA==.',
Zm='Zmaj:BAAANQABCgIIAgAAAA==.',
Zo='Zombiehunter:BAABNQAECn8uAAILAAkKGBRLcAAxAgALAAkKGBRLcAAxAgAAAA==.Zomboy:BAAANQAECgEIAQAAAA==.Zornqueff:BAAANQADCggICAAAAA==.Zortax:BAAANQAECgcICwAAAA==.',
Zu='Zu:BAAANQAECgUIBgAAAA==.Zug:BAABNQAECn8iAAILAAoKixh0hACwAQALAAoKixh0hACwAQAAAA==.Zurgyn:BAAANQAECgIIAgAAAA==.',
['Âr']='Ârc:BAAANQAECgMIBAAAAA==.',
['Ðr']='Ðream:BAAANQAECggICAABNQAECggICQAOAAAAAA==.',
['ßl']='ßlue:BAABNQAECn9DAAQlAAoKWxyDDwCnAgAlAAoKWxyDDwCnAgAiAAYKaAgwagDzAAAcAAIKRwMmmQAcAAAAAA==.',
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
