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

local lookup = {'Warrior-Protection','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Shaman-Elemental','DeathKnight-Unholy','Monk-Mistweaver','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Mage-Arcane','Druid-Balance','Paladin-Protection','Monk-Windwalker','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Guardian','Priest-Shadow','Shaman-Enhancement','Evoker-Devastation','Druid-Restoration','DeathKnight-Blood','DeathKnight-Frost','Mage-Frost','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Mage-Fire','Priest-Discipline','Shaman-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Outlaw','Druid-Feral',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abrocklock:BAAANQAECgEIAQAAAA==.',
Ad='Adorabull:BAABNQAECn8rAAIBAAkKDyGvBAA4AwABAAkKDyGvBAA4AwAAAA==.',
Ae='Aevelee:BAAANQAECgYIDwAAAA==.',
Al='Alari:BAAANQADCgYIBgAAAA==.Aleeta:BAAANQAECgQIBAAAAA==.Alleriae:BAAANQAECgMIAwAAAA==.Allucard:BAAANQAECggICQAAAA==.',
Am='Amaria:BAAANQAECgQIBwABNQAECgkJGgACAM4aAA==.',
An='Anaki:BAAANQADCgUIBQAAAA==.Anduîiîn:BAAANQADCggICgAAAA==.Angelstörm:BAAANQAECggICgAAAA==.Angelusnox:BAAANQAECgIIAgAAAA==.Antarias:BAAANQAECgQIBgAAAA==.Anubiz:BAAANQADCgEIAQAAAA==.Anzhe:BAAANQAECgcIDQAAAA==.',
Ar='Araydin:BAAANQADCgEIAQAAAA==.Arckenon:BAACNQAFFH8IAAIDAAIKxxlAGQCeAAADAAIKxxlAGQCeAAA1AAQKfzUAAgMACgqhHsc9ANwCAAMACgqhHsc9ANwCAAAA.Ardarl:BAAANQADCggICAAAAA==.Armdandrëady:BAAANQAECgUIBQAAAA==.Arranix:BAAANQADCgMIAwAAAA==.Arrica:BAAANQABCgUIBQAAAA==.Artemisv:BAAANQADCgIIAgAAAA==.Artorias:BAAANQAECgQIBAAAAA==.',
As='Ashog:BAAANQAECgIIAQAAAA==.',
At='Atillis:BAAANQAECggICwAAAA==.',
Au='Austenpally:BAABNQAECn8eAAMCAAgKHg93igB9AQACAAgKHg93igB9AQADAAcKMg7gygACAQAAAA==.',
Av='Avarek:BAAANQADCgEIAQAAAA==.Aveycado:BAAANQAECgYIEwAAAA==.',
Ax='Axeflack:BAABNQAECn8wAAMBAAoK1BsCBwBLAgABAAoK1BsCBwBLAgAEAAUKMgf4/gDeAAAAAA==.Axegor:BAAANQAECgQIBwABNQAECgoKJgAFAAcdAA==.',
Az='Azaral:BAAANQADCgUJBQABNQAECggIGgAGAMMEAA==.Azmarija:BAAANQADCgEIAgAAAA==.',
Ba='Bacuda:BAAANQAECgUICQAAAA==.Batbane:BAAANQADCgYICAAAAA==.',
Be='Beggles:BAAANQADCgUIBQAAAA==.',
Bi='Biancadelrio:BAAANQAECgYIDwAAAA==.Bigguberment:BAAANQAECgQIEAAAAA==.Bigsneaky:BAAANQAECgYIBAABNQAECgcIFQAHAEIRAA==.',
Bl='Blackbird:BAABNQAECn8aAAMIAAkK3QZaFQBdAQAIAAkK3QZaFQBdAQAJAAYKsgSIFADmAAABNQAFFAQIBgAKAKoSAA==.Bladekrim:BAAANQAECgEIAgAAAA==.Blindashunae:BAAANQADCgEIAQAAAA==.Blitzo:BAAANQADCgMIAwAAAA==.',
Bo='Boomhammer:BAAANQADCgYIBgAAAA==.Boredgored:BAAANQADCgcIBwABNQAECgoKMAALAN0YAA==.Botia:BAABNQAECn8XAAIMAAgKAQOEiQCuAAAMAAgKAQOEiQCuAAAAAA==.Bourdeaux:BAAANQADCgcIFQAAAA==.',
Br='Braedia:BAAANQABCgEIAQAAAA==.Brainnmatter:BAAANQADCgEIAQAAAA==.Brashmoore:BAAANQADCgMIAwAAAA==.Brizik:BAAANQABCgUIBQAAAA==.Brookshields:BAAANQAECgYICgAAAA==.Bruised:BAAANQAECgIIAgAAAA==.Brunae:BAABNQAECn8hAAIBAAgKIRBsFAA9AQABAAgKIRBsFAA9AQAAAA==.Brunnera:BAAANQADCggIDgAAAA==.Bruuenor:BAAANQAECgEIAQAAAA==.Bruul:BAABNQAECn8cAAQDAAcKqBN/BgEUAQADAAUKUg9/BgEUAQACAAQKpAYd/gCAAAANAAEKAAAMbQA4AAAAAA==.',
By='Bytour:BAAANQAECgUIBwABNQAFFAMIBQAOAEUXAA==.',
Ca='Caenji:BAAANQAECgIIAgAAAA==.Captbenson:BAAANQADCgYIAQAAAA==.Carcharoth:BAAANQADCgMIAwAAAA==.Carmelina:BAAANQADCgQIBQAAAA==.Castanthrax:BAAANQADCgQIBAAAAA==.Cathryl:BAAANQADCgQIBAABNQAECggIKAAPALYdAA==.',
Ch='Chadgar:BAABNQAECn8wAAILAAoK3RjEcACcAgALAAoK3RjEcACcAgAAAA==.Chaoshammer:BAAANQADCggICAAAAA==.Chey:BAABNQAECn9IAAMQAAoKBCQ5DwDiAgAQAAoKpyA5DwDiAgARAAYKDCQ8GwA2AQAAAA==.Chipsahoy:BAAANQADCgEIAQAAAA==.Chormage:BAAANQADCgQIBAAAAA==.Chíef:BAAANQAFFAMIBAAAAA==.',
Cl='Clarke:BAAANQABCgEIAQAAAA==.Close:BAAANQADCgUIBQABNQAECggIEQASAAAAAA==.Clouds:BAAANQAECgIIAwABNQAECgQICQASAAAAAA==.',
Co='Conorix:BAAANQADCggIQAAAAA==.Corvo:BAAANQADCggICAABNQAECggIKAAPALYdAA==.',
Cr='Crataxxis:BAABNQAECn80AAMTAAoKtQ3XKwB0AQATAAoKtQ3XKwB0AQAUAAEKAADOcwAnAAAAAA==.',
Cu='Cudara:BAAANQADCgIIAgABNQAECgUICQASAAAAAA==.Cupra:BAAANQADCgIIAgAAAA==.',
Cy='Cydon:BAABNQAECn86AAIVAAkKgR5iCwC2AgAVAAkKgR5iCwC2AgAAAA==.Cythraul:BAABNQAECn8oAAIPAAgKth0FCAB8AgAPAAgKth0FCAB8AgAAAA==.',
Da='Daerith:BAAANQADCgYICgAAAA==.Daerrith:BAAANQADCgYIBgAAAA==.Dagni:BAAANQAECgEIAQAAAA==.Dantey:BAAANQADCgUIBQABNQAECgoKNAAWAM8dAA==.Darkveil:BAAANQADCgQIBAAAAA==.Darrwin:BAABNQAECn8WAAIDAAcKkxNi6wBFAQADAAcKkxNi6wBFAQAAAA==.',
De='Deathhor:BAAANQADCgQIBAAAAA==.Deathspacito:BAAANQADCgMIAwAAAA==.Demonalsa:BAAANQADCgUIBQABNQAECggIGwAXABIVAA==.Derrith:BAAANQADCgUIBgAAAA==.Dezgra:BAAANQAECgcIDwAAAA==.',
Df='Dfabness:BAABNQAECn8lAAIOAAkKSxKPHgB0AQAOAAkKSxKPHgB0AQAAAA==.',
Do='Doomfury:BAAANQADCgEIAgAAAA==.Dotbush:BAAANQAECgQIBAABNQAFFAUICAADAAcDAA==.',
Dr='Dracthayr:BAABNQAECn8/AAIYAAoKWgtsCgCMAQAYAAoKWgtsCgCMAQAAAA==.Dragonhammer:BAABNQAECn8pAAIDAAoKOx2IJgChAgADAAoKOx2IJgChAgAAAA==.Dreaming:BAAANQAECggICAABNQAECggIEQASAAAAAA==.Drimclaw:BAAANQAECgIIAwAAAA==.Drubo:BAAANQAECgUIDwAAAA==.Drx:BAABNQAECn8xAAQIAAgKbQkuIQDMAAAIAAcKiAguIQDMAAAYAAYKsQiaFAC9AAAJAAIKGAX6FgBOAAAAAA==.',
Du='Dukkelemon:BAAANQAECgQIBwAAAA==.',
Ed='Edenaza:BAAANQAECgQIBAAAAA==.',
El='Elanore:BAACNQAFFH8GAAIKAAQKqhLLEgA/AQAKAAQKqhLLEgA/AQA1AAQKfykAAwoACgolHL4SABcDAAoACgolHL4SABcDABYAAQoAAAttAAAAAAAA.Elicithy:BAAANQABCgUIBQABNQAECggIGwAXABIVAA==.Elison:BAAANQAECgQIBAABNQAECggIGgAGAMMEAA==.Ellaini:BAAANQAECgUICAAAAA==.Elliana:BAAANQAECgUIBwABNQAFFAQIBgAKAKoSAA==.Ellie:BAAANQAECgEIAgABNQAECgoKMAACANwgAA==.Elloise:BAAANQADCgQIBQABNQAFFAQIBgAKAKoSAA==.Elmichi:BAAANQAECgMIAQABNQAECggIBAASAAAAAA==.Elsae:BAABNQAECn8zAAINAAoKIBRmIQDYAQANAAoKIBRmIQDYAQAAAA==.Elseb:BAAANQADCgEIAQAAAA==.',
Em='Emeric:BAAANQADCgQIBAAAAA==.',
Ev='Evasion:BAABNQAFFH8FAAIRAAMKgQzKEADfAAARAAMKgQzKEADfAAAAAA==.Everios:BAACNQAFFH8IAAIBAAUKLxSnAgDOAAABAAUKLxSnAgDOAAA1AAQKfzAAAgEACgqaHzEIANECAAEACgqaHzEIANECAAAA.Evic:BAAANQADCgYICAAAAA==.Evielyn:BAAANQADCgUJBQABNQAFFAQIBgAKAKoSAA==.',
Ex='Exodous:BAAANQABCgYIBAAAAA==.',
Fa='Faeleader:BAAANQAECgEIAQAAAA==.Faevelina:BAAANQAECgEIAQABNQAECgcIDwASAAAAAA==.Faytadori:BAABNQAECn9HAAMMAAoKrBlTFwAlAgAMAAoKrBlTFwAlAgAZAAQKmQpsYwB4AAAAAA==.',
Fe='Felgrrl:BAAANQADCggIRAAAAA==.Feyreh:BAAANQAECgIIBAAAAA==.',
Fi='Fidget:BAABNQAECn8oAAIRAAgKvwkyFwBWAQARAAgKvwkyFwBWAQAAAA==.',
Fl='Fletch:BAABNQAECn8WAAIEAAkKFQW4zwBUAQAEAAkKFQW4zwBUAQAAAA==.',
Fo='Forever:BAAANQAECggIEQAAAA==.',
Fr='Frahra:BAAANQAECgIIAgAAAA==.Frique:BAAANQAECgUICgAAAA==.Frozenyogert:BAAANQAECgQICQAAAA==.',
Ga='Galbur:BAACNQAFFH8IAAMaAAUKZwxeIQB9AAAaAAMKxxFeIQB9AAAGAAIKpgELEgA5AAA1AAQKfzEABBoACgqFFWYtAGACABoACQpJFmYtAGACAAYACQoyFNorAFUBABsAAgozCJmHAGUAAAAA.Galdrin:BAAANQAECgcIDwAAAA==.Gaspode:BAAANQADCgYICwAAAA==.Gassann:BAABNQAECn8ZAAIDAAgKWBa5rgDCAQADAAgKWBa5rgDCAQAAAA==.',
Ge='Geers:BAABNQAECn8vAAIcAAoK/iIkAQCRAwAcAAoK/iIkAQCRAwAAAA==.Geta:BAAANQAECgYICQABNQAECgoKNgAEAEYiAA==.Getabrew:BAAANQAECgYICQABNQAECgoKNgAEAEYiAA==.Getacurse:BAAANQAECgUIBQABNQAECgoKNgAEAEYiAA==.Getagrip:BAAANQADCgIIAgABNQAECgoKNgAEAEYiAA==.Getalife:BAAANQAECgEIAQABNQAECgoKNgAEAEYiAA==.Getarage:BAABNQAECn82AAMEAAoKRiJeDQAbAwAEAAoKRiJeDQAbAwABAAMKsx+YJQAXAQAAAA==.Getasoar:BAAANQADCgQIBgABNQAECgoKNgAEAEYiAA==.Getastab:BAAANQAECggIEQABNQAECgoKNgAEAEYiAA==.',
Gh='Ghil:BAABNQAECn8fAAQdAAoKuBlVAwDIAgAdAAoKuBlVAwDIAgAeAAMKtAseYQBjAAAfAAEKMw/vPQE6AAAAAA==.',
Gi='Gildersleeve:BAAANQAECgUIBgAAAA==.Gilia:BAAANQAECgIIBAAAAA==.Gimlí:BAAANQADCgEIAQAAAA==.',
Gl='Glynix:BAAANQAECgIIBAAAAA==.',
Gn='Gnosher:BAAANQAFFAMIAwAAAA==.',
Go='Goku:BAABNQAECn8sAAQOAAkK3RJCLQCvAQAOAAkK3RJCLQCvAQAgAAYK8QwPHQAXAQAHAAEKsgUIVAAiAAAAAA==.Goldiwarlock:BAAANQADCgUIBwAAAA==.Goloron:BAAANQAECgQIBAAAAA==.Gornub:BAAANQADCgYIBgAAAA==.Gorzok:BAAANQABCgEIAQAAAA==.',
Gr='Graymayn:BAAANQAECgQICgAAAA==.Grekk:BAAANQAECgMIAwAAAA==.Grelldar:BAAANQADCgEIAQAAAA==.Grimflaps:BAABNQAECn8qAAMYAAgKWw1/DQA/AQAYAAgKWw1/DQA/AQAIAAUKSwRZOwC+AAAAAA==.',
Gu='Gunderthirth:BAACNQAFFH8NAAIBAAYKqxy2AAApAgABAAYKqxy2AAApAgA1AAQKfyIAAgEACgpqIyUDAHIDAAEACgpqIyUDAHIDAAAA.Guulfang:BAAANQADCgMIAwAAAA==.',
Gw='Gwaeniiha:BAABNQAECn8qAAIDAAgKfwv6sAAuAQADAAgKfwv6sAAuAQAAAA==.',
Ha='Haan:BAAANQADCgYIDAAAAA==.Haliran:BAAANQAECgQIBQAAAA==.Handsoap:BAABNQAECn8cAAITAAcKFgm7TgBgAQATAAcKFgm7TgBgAQAAAA==.Harakhty:BAAANQAECgUICQAAAA==.Hardhitter:BAABNQAECn9EAAMBAAoKQRjsDwArAgABAAoKZRfsDwArAgAEAAkKAA7SrACtAQAAAA==.',
He='Hellstorm:BAAANQABCgYICgAAAA==.Hellumph:BAABNQAECn8pAAIPAAoKwROMBwDSAQAPAAoKwROMBwDSAQAAAA==.Hevensdemon:BAAANQAECggICwAAAA==.Hevensrath:BAABNQAECn8yAAMDAAoKIR4vPABHAgANAAoKHRl7FABgAgADAAoKrxsvPABHAgAAAA==.Hevensreaper:BAABNQAECn8aAAMaAAcK6BUSKQCOAQAaAAcK6BUSKQCOAQAGAAQKwAKatwB+AAAAAA==.Hevensvoid:BAAANQAECggIDgAAAA==.Hevshaolin:BAAANQAECgUIBgAAAA==.Hexhorn:BAAANQADCggJDgAAAA==.Hextermorgan:BAAANQABCggIEAABNQAECgoKNgAbALMbAA==.',
Ho='Hokuden:BAABNQAECn9AAAIbAAoKxRRgKQDUAQAbAAoKxRRgKQDUAQAAAA==.Holphie:BAAANQAECggICwAAAA==.Holyholyholy:BAAANQADCggICAAAAA==.Homet:BAAANQADCgQIBAAAAA==.Horsebananas:BAAANQAECgcIDQAAAA==.',
Hu='Huddington:BAABNQAECn8eAAILAAoKzgmbgwByAQALAAoKzgmbgwByAQAAAA==.',
Hy='Hyperion:BAAANQAECgUICwABNQAECggIKAAPALYdAA==.',
Ig='Igknight:BAAANQAECgcICgABNQAECgoKMAACAJUUAA==.',
Il='Ilsi:BAAANQADCgYIBgABNQAECgoKJgAFAAcdAA==.',
Im='Impthrower:BAAANQAECgIIAgABNQADCgYJDwASAAAAAA==.',
In='Indecent:BAABNQAECn8sAAMfAAoKtBuAKwA1AgAfAAoKdBuAKwA1AgAeAAIKHxusTQCWAAAAAA==.Indeed:BAAANQAECggICQAAAA==.Indree:BAAANQAECgQIBAAAAA==.Inibble:BAAANQABCgUICAAAAA==.',
Iq='Iqfbeef:BAAANQADCgYICgAAAA==.',
Is='Ishy:BAABNQAECn8wAAMLAAkK7xosZgCyAgALAAkK7xosZgCyAgAhAAMKLAvuBgByAAAAAA==.',
Iw='Iwannalive:BAAANQADCgIIAgAAAA==.',
Iz='Izziey:BAAANQADCgEIAQAAAA==.',
Ja='Jack:BAABNQAECn8kAAQWAAoKNRlkIgAhAgAWAAgKQxZkIgAhAgAKAAcKqhDVjwBnAQAiAAMKURWSFwC5AAAAAA==.Jackieblaze:BAAANQAECgUICgABNQAFFAUICAAiAIQTAA==.Jackieplays:BAACNQAFFH8IAAQiAAUKhBPdAgCIAAAKAAIKChjQIACmAAAWAAIK5Am3DQCMAAAiAAIK7QvdAgCIAAA1AAQKfzkABCIACgo5IF8DAL4CACIACAqNHl8DAL4CAAoACgqiHMs5AIICABYAAQo2DCp6ADQAAAAA.Jaded:BAABNQAECn8uAAMjAAoKsRz4GQC6AgAjAAoKsRz4GQC6AgAFAAMKjwrPAAGPAAAAAA==.Jandexx:BAAANQADCgMIAwAAAA==.',
Je='Jeses:BAAANQAECggIDwAAAA==.',
Jo='Jollah:BAABNQAECn8VAAQHAAcKQhEuLQACAQAHAAUKjg8uLQACAQAOAAYKrxB+MADhAAAgAAEKAAB8MAA6AAAAAA==.Jorawa:BAAANQAECgUIBQAAAA==.',
Ju='Jurassic:BAAANQADCgYIBgAAAA==.Jutic:BAABNQAECn9BAAIjAAoKTiMoDQBXAwAjAAoKTiMoDQBXAwAAAA==.',
Ka='Kageken:BAAANQADCgQIBAABNQADCgYJEQASAAAAAA==.Kaithul:BAAANQABCgQIAwAAAA==.Kardas:BAABNQAECn8hAAIkAAgKuAhQugCPAQAkAAgKuAhQugCPAQAAAA==.',
Kb='Kbilly:BAABNQAECn81AAIjAAoKRR6uIADnAgAjAAoKRR6uIADnAgAAAA==.',
Ke='Kentarou:BAAANQABCgUIBQAAAA==.Keylerin:BAACNQAFFH8PAAIQAAYKahYuCQBCAQAQAAYKahYuCQBCAQA1AAQKfyoAAhAACgqJHjwIAPYCABAACgqJHjwIAPYCAAAA.',
Ki='Kiikee:BAAANQADCgQIBAAAAA==.Kimosabi:BAAANQABCgIIAgAAAA==.Kitto:BAAANQADCgYJBgAAAA==.Kittvulpy:BAAANQADCgYICgAAAA==.',
Kl='Klausinator:BAAANQADCggIEQAAAA==.',
Kn='Knottes:BAAANQABCggIKgAAAA==.',
Ko='Komos:BAAANQAECgEIAQAAAA==.',
Kr='Krampus:BAABNQAECn8vAAIXAAoKuQv7EADHAQAXAAoKuQv7EADHAQAAAA==.Kranok:BAABNQAECn8hAAIlAAgKLhAKGwBoAQAlAAgKLhAKGwBoAQAAAA==.Krennthis:BAAANQAECgQIBAAAAA==.Krimbruiser:BAAANQADCgYIBwABNQAECgEIAgASAAAAAA==.Krimhuntress:BAAANQADCgYIBgAAAA==.',
Ku='Kunac:BAAANQADCgYIEAAAAA==.',
Ky='Kyran:BAAANQADCgUIBwAAAA==.Kyrun:BAABNQAECn8ZAAIXAAcKzAlkGwAfAQAXAAcKzAlkGwAfAQAAAA==.Kytrina:BAAANQADCgIIAgAAAA==.',
La='Lactoes:BAAANQADCgYIBgAAAA==.Lamoran:BAAANQAECgUICQAAAA==.',
Le='Lemón:BAAANQAECgEIAQAAAA==.',
Lh='Lhani:BAABNQAECn8pAAIKAAkK5RG7TQDIAQAKAAkK5RG7TQDIAQAAAA==.',
Li='Lilguysci:BAAANQAECgMIBAAAAA==.Lizord:BAABNQAECn8cAAIIAAoKaRIdCwBAAgAIAAoKaRIdCwBAAgAAAA==.',
Ll='Llothien:BAAANQAECgIIAgAAAA==.Llyrael:BAABNQAECn8xAAMKAAkKBwdrcwBEAQAKAAkKBwdrcwBEAQAWAAEK2gILhAAlAAAAAA==.',
Lo='Lonard:BAAANQAECgIIAgAAAA==.',
Lu='Lugosi:BAAANQAECgEIAQAAAA==.',
Ly='Lyfe:BAAANQABCgUIBwAAAA==.',
Ma='Machlain:BAAANQADCgQIBAABNQAECggIIQANAAkcAA==.Maddeleine:BAAANQADCgYIEwAAAA==.Magara:BAAANQAECgQIBAAAAA==.Magicdemon:BAABNQAECn81AAITAAoKOyWZCADzAgATAAoKOyWZCADzAgAAAA==.Magichunter:BAAANQAECgcIDAABNQAECgoKNQATADslAA==.Magicpaladin:BAAANQAECgcIDQABNQAECgoKNQATADslAA==.Magicshaman:BAAANQAECgUICgABNQAECgoKNQATADslAA==.Magnafratrem:BAAANQAECgQIBAAAAA==.Makall:BAAANQABCgQIBAAAAA==.Malaah:BAABNQAECn8iAAIFAAkKCBD0dwC6AQAFAAkKCBD0dwC6AQAAAA==.Mansuno:BAABNQAECn83AAMDAAkK3Rf0YAB3AgADAAkK3Rf0YAB3AgACAAcKTQwLZQBVAQAAAA==.Mapachote:BAABNQAECn8hAAIlAAgKsRDXFQCtAQAlAAgKsRDXFQCtAQAAAA==.Marodin:BAAANQADCggIQQAAAA==.Maynor:BAAANQABCggIFQAAAA==.Mazboda:BAABNQAECn81AAQfAAgKCBYrYQB4AQAfAAgKoBUrYQB4AQAdAAIKFRkXHgCKAAAeAAIKugg3ZABcAAAAAA==.',
Me='Meatbaal:BAAANQAECgUIDQAAAA==.Medïc:BAAANQADCggICAAAAA==.Melinaria:BAABNQAECn8lAAMWAAgKdBclJgD9AQAWAAgKdBclJgD9AQAiAAEK2w6nEwBAAAAAAA==.Merewene:BAAANQAECgUIDgAAAA==.Merkabai:BAAANQADCgIIAgAAAA==.',
Mi='Mileta:BAABNQAECn82AAIMAAoKCRxHFABNAgAMAAoKCRxHFABNAgAAAA==.Minuette:BAAANQAECgMIAwAAAA==.',
Mo='Montblanc:BAAANQAECgQIBAABNQAECgUICgASAAAAAA==.Moonwatcher:BAAANQADCgQIBAABNQAFFAQIBgAKAKoSAA==.Morgnox:BAAANQAECgIIAgAAAA==.',
Mu='Murdercookie:BAAANQAECgEIAQAAAA==.',
Na='Nazgul:BAAANQADCgcICAAAAA==.',
Ne='Necrokrim:BAAANQAECgEIAQAAAA==.Necronic:BAAANQAECgIIAwAAAA==.Necroreign:BAABNQAECn9CAAITAAoK1BvkEwBSAgATAAoK1BvkEwBSAgAAAA==.Need:BAAANQAECgIIAgAAAA==.Neherenia:BAABNQAECn8yAAIbAAoK2hT/HwAWAgAbAAoK2hT/HwAWAgAAAA==.Nervous:BAAANQAECggIAgABNQAECggIEQASAAAAAA==.Nessee:BAABNQAECn8WAAIcAAYKNgviHgDzAAAcAAYKNgviHgDzAAAAAA==.',
Ni='Niall:BAAANQAECgEIAgAAAA==.Nightfire:BAAANQABCgcIEwAAAA==.Nihowdy:BAABNQAECn8+AAImAAoKkyFXAQB/AwAmAAoKkyFXAQB/AwAAAA==.',
No='Norrin:BAAANQABCggIDgAAAA==.',
Oc='Octalexane:BAAANQADCgYIBgABNQAECggIIQABACEQAA==.',
Od='Odelagt:BAAANQAECggIBAAAAA==.',
On='Onimusha:BAAANQAECgEIAQAAAA==.',
Or='Orci:BAABNQAECn8mAAIeAAgKwQyfCAAUAQAeAAgKwQyfCAAUAQAAAA==.Orryn:BAAANQABCgIIAgAAAA==.Ortalbem:BAABNQAECn9KAAMLAAoKzh3ZMABeAgALAAoKQx3ZMABeAgAcAAkKvRv8CgCpAQAAAA==.',
Ou='Oulli:BAAANQABCggIHwAAAA==.',
Ov='Ovi:BAAANQAECgUICwAAAA==.',
Pa='Painthuffer:BAABNQAECn8hAAMQAAoKdhNtLQAQAgARAAoK9xB7MAAgAgAQAAkKBBJtLQAQAgABNQAECgoKMAALAN0YAA==.Paramour:BAAANQAECgIIAgAAAA==.Pazuuzu:BAAANQAECgEIAQAAAA==.',
Pe='Peddles:BAAANQAECgUIDQAAAA==.Petmedaddy:BAAANQABCgEIAQAAAA==.',
Ph='Pherix:BAABNQAECn80AAIWAAoKzx1QEgDbAgAWAAoKzx1QEgDbAgAAAA==.Philipfry:BAABNQAECn9CAAMCAAoKaxkBTgAyAgACAAgKBhcBTgAyAgADAAcKbBgGdwCgAQAAAA==.Phill:BAAANQADCgcIEgAAAA==.Phuuta:BAAANQAECgMIAwAAAA==.',
Pl='Plaguetusk:BAAANQADCgQIBAAAAA==.',
Po='Pontoon:BAAANQAECgUIBQAAAA==.Poomacha:BAAANQAECgUIEQAAAA==.Potatopants:BAAANQAECgEIAQAAAA==.',
Pr='Prinlina:BAAANQADCggIDQAAAA==.',
Py='Pyree:BAABNQAECn8uAAIYAAoKmwyICwBuAQAYAAoKmwyICwBuAQAAAA==.',
Ra='Radimus:BAAANQAECgEIAQAAAA==.Raenne:BAAANQADCgMIAwAAAA==.Rainvelle:BAAANQADCgQIBAAAAA==.Raistlain:BAABNQAECn8fAAIWAAgKwRQKJgD+AQAWAAgKwRQKJgD+AQAAAA==.Ralli:BAABNQAECn82AAMUAAoK4R45CgCQAgATAAkKxBq9FgDmAgAUAAoKgB05CgCQAgAAAA==.Ralls:BAAANQAECgYIBgABNQAECgcIDAASAAAAAA==.Rallsdk:BAAANQADCgYIBgABNQAECgcIDAASAAAAAA==.Rallsodins:BAAANQAECgcIDAAAAA==.Ranulf:BAAANQAECgQIDgAAAA==.Ratava:BAAANQAECgYIDwAAAA==.Ratrot:BAAANQADCggICQAAAA==.Raztar:BAAANQADCgUIBQAAAA==.',
Re='Reddemon:BAAANQAECggIEgAAAA==.Rehvenge:BAAANQAECgIIAgAAAA==.Rekarra:BAAANQADCgcIBwAAAA==.Reks:BAAANQAECgQIBAAAAA==.Reldarus:BAEBNQAECn8vAAQiAAoKCSP4AgDVAgAiAAcK1CP4AgDVAgAKAAoK3xtlSQBKAgAWAAEK9BWCcABHAAAAAA==.Rena:BAABNQAECn8qAAQYAAoKKhL7EAD5AAAYAAcKJwr7EAD5AAAIAAMKywOtKQB8AAAJAAQKxQNkHQB5AAAAAA==.Revilation:BAABNQAECn8kAAINAAkKIBTrHAAEAgANAAkKIBTrHAAEAgAAAA==.Rezjyk:BAAANQADCgYIBgABNQAECgkJNwADAHAaAA==.Rezzyk:BAABNQAECn83AAIDAAkKcBqiTgAKAgADAAkKcBqiTgAKAgAAAA==.',
Rh='Rhyxali:BAAANQAECgUIEQAAAA==.',
Ri='Riibirth:BAAANQADCgYIBgAAAA==.Riis:BAAANQADCgEIAQAAAA==.',
Ru='Ruknan:BAAANQADCgQIBAABNQAECgoKOgAUANAUAA==.',
Ry='Rygelon:BAAANQAECgQICQAAAA==.',
Sa='Sableanne:BAAANQAECgEIAQAAAA==.Sacredscales:BAAANQADCgMJAwAAAA==.Samvimes:BAAANQAECgIIBQAAAA==.Sangreene:BAABNQAECn8xAAIWAAoKxRvwCQCaAgAWAAoKxRvwCQCaAgAAAA==.Sargis:BAABNQAECn9NAAMDAAoKnyAAHQDQAgADAAoKnyAAHQDQAgACAAgKCBVuaADeAQAAAA==.',
Sc='Schrödinger:BAAANQAECgEIAQABNQAECggIKAAPALYdAA==.Scott:BAAANQAECgQIBAAAAA==.',
Se='Selira:BAAANQAECgcIBwABNQAECgoKKAALAMAOAA==.Serissa:BAAANQAECgEIAQAAAA==.Serjankins:BAAANQADCgQIBAAAAA==.Setsuna:BAAANQABCgYIDAABNQAECgoKIAAWAGYeAA==.',
Sh='Shadowbrooks:BAAANQADCgIIAgAAAA==.Shadowgiver:BAAANQADCgcICwAAAA==.Shagol:BAABNQAECn8hAAIKAAcKNBZDZwBsAQAKAAcKNBZDZwBsAQAAAA==.Shaidic:BAAANQAECgQIBAAAAA==.Shamemoon:BAAANQAECgEJAQABNQAECggIFwAfAGAMAA==.Shamunroe:BAABNQAECn8wAAMFAAoKsBdhOwCsAQAFAAoKsBdhOwCsAQAjAAUK1Aow1gC6AAAAAA==.Shatterhoof:BAAANQAECgYIEwAAAA==.Shelle:BAAANQAECgMIAwAAAA==.Shiftysmage:BAAANQAECgEIAQABNQAECgoKHwAVANcUAA==.Shingra:BAACNQAFFH8LAAIJAAQKEhMCBwD3AAAJAAQKEhMCBwD3AAA1AAQKfyMAAgkACQrKFjoGAGoCAAkACQrKFjoGAGoCAAAA.Shores:BAAANQABCgIIAQAAAA==.Shylindra:BAAANQAECgQIBAAAAA==.',
Si='Sigourney:BAAANQAECgYIDwABNQAECgcIDQASAAAAAA==.Silversho:BAAANQAECgQIBAAAAA==.Silvren:BAAANQADCgIIAgAAAA==.',
Sk='Skill:BAABNQAECn8cAAMZAAgKghKIKgDKAQAZAAgKghKIKgDKAQAMAAQKRw6wegDgAAAAAA==.',
Sl='Slighttrash:BAAANQAECgUIDAAAAA==.',
Sm='Smallcrow:BAABNQAECn8bAAMOAAkKbR40FwCSAgAOAAgKbR40FwCSAgAHAAQK0Q1HMwDQAAAAAA==.',
So='Somdot:BAEBNQAECn9LAAIWAAoK/yBpCABWAwAWAAoK/yBpCABWAwAAAA==.Somedeekay:BAAANQAECgYIDgAAAA==.',
Sp='Spirit:BAABNQAECn8VAAMIAAgKFRrtEQCNAgAIAAgKFRrtEQCNAgAYAAEKCwjLQQAmAAABNQAFFAMIBQARAIEMAA==.',
Sq='Squirrellock:BAAANQAECgEIAgAAAA==.',
St='Starga:BAAANQADCgQIBAAAAA==.Starge:BAAANQADCgUIBQAAAA==.Starre:BAAANQADCgQIBAAAAA==.Steffey:BAAANQAECgYIEgAAAA==.Stepbro:BAAANQADCgcIDAAAAA==.Stoikk:BAABNQAECn8UAAIFAAcK3hCPkQB4AQAFAAcK3hCPkQB4AQAAAA==.Straven:BAABNQAECn8bAAIcAAgKjhNaEAChAQAcAAgKjhNaEAChAQAAAA==.Sturgeson:BAACNQAFFH8VAAIBAAYKqxksAQA8AQABAAYKqxksAQA8AQA1AAQKfy0AAgEACQp1IW4JALUCAAEACQp1IW4JALUCAAAA.',
Su='Suffocation:BAEANQAECgYIBgABNQAFFAkJIwAeAAYfAA==.Sulwen:BAABNQAECn8iAAIKAAkKBBTLXgAFAgAKAAkKBBTLXgAFAgAAAA==.Sundance:BAAANQADCgUIBQAAAA==.Sunray:BAAANQAECgUIBQAAAA==.',
Sw='Swiftfeet:BAABNQAECn8mAAIkAAkKuxXplADeAQAkAAkKuxXplADeAQAAAA==.',
['Sé']='Sésho:BAAANQADCgQIBgAAAA==.',
['Sö']='Söranin:BAAANQAECgMIBAAAAA==.',
['Sø']='Sømdøt:BAEANQAECggIDAABNQAECgoKSwAWAP8gAA==.',
Ta='Taeili:BAABNQAECn8cAAIVAAgK1BY6FwD5AQAVAAgK1BY6FwD5AQAAAA==.Taeror:BAAANQADCgQIBAAAAA==.Tanequil:BAACNQAFFH8IAAIZAAUKNAOdCAAVAQAZAAUKNAOdCAAVAQA1AAQKfzIAAhkACgrODPspAM8BABkACgrODPspAM8BAAAA.',
Te='Techromancer:BAABNQAECn8pAAMGAAoKYBkpKgCPAgAGAAoKeRYpKgCPAgAbAAcK9xh4KwDHAQABNQAECgoKNAAWAM8dAA==.Tem:BAAANQABCgQIBAABNQADCgcIDgASAAAAAA==.',
Th='Thanatias:BAAANQAECgYIBgAAAA==.Thantasia:BAAANQAECgMIAgAAAA==.Theakunda:BAAANQAECgcIDwAAAA==.Theodis:BAAANQAECgQIBAAAAA==.Thistlebrew:BAAANQAECgQIBAAAAA==.Thokdar:BAAANQAECgQIBQAAAA==.',
Ti='Tifà:BAAANQAECgIIAgAAAA==.Tillago:BAAANQADCggICgAAAA==.Timothy:BAAANQAECgUICAAAAA==.Timothyjohn:BAAANQAECgYIDwAAAA==.Tinkphooey:BAAANQAECgMIBAAAAA==.Tirianna:BAAANQADCgEIAQABNQAFFAQIBgAKAKoSAA==.Tituba:BAABNQAECn88AAIfAAoKbBqGKgA6AgAfAAoKbBqGKgA6AgAAAA==.',
To='Toklore:BAAANQADCgcIDgAAAA==.Tonepavone:BAAANQADCgYIBgAAAA==.Tormmok:BAAANQADCgQIBAAAAA==.',
Tr='Traazz:BAAANQADCgYICgAAAA==.Trey:BAAANQAECgUIBgAAAA==.Trior:BAAANQAECgQIBQAAAA==.',
Ts='Tsuruga:BAABNQAECn8nAAIgAAoKPAZTDAA4AQAgAAoKPAZTDAA4AQAAAA==.',
Tu='Turkwise:BAABNQAECn8+AAQVAAkKmxFsIwB7AQAVAAcK4Q9sIwB7AQAnAAgKqQ+AHAA+AQAZAAQKwgTQVwBhAAAAAA==.',
Ul='Ulodude:BAAANQADCgYIBgAAAA==.',
Un='Unholydiddy:BAAANQADCggICQAAAA==.',
Ur='Urobolos:BAAANQAECgMIAwAAAA==.',
Uv='Uvari:BAAANQAECgcIEgAAAA==.',
Va='Vacalaca:BAABNQAECn8XAAMfAAgKYAzoaQBfAQAfAAgKYAzoaQBfAQAeAAEK9AGjhwAeAAAAAA==.Valany:BAAANQADCgIIAgAAAA==.Valkira:BAACNQAFFH8IAAIXAAUKlgyEAwDXAAAXAAUKlgyEAwDXAAA1AAQKfzIAAxcACgoAHSIPAHgCABcACgogHCIPAHgCAAUABgpxGVSLAIgBAAAA.Valton:BAACNQAFFH8FAAIOAAMKRReCCADLAAAOAAMKRReCCADLAAA1AAQKfz4AAg4ACgqbJcEDAJkDAA4ACgqbJcEDAJkDAAAA.Vancede:BAAANQAECgQIBAABNQAECgkJJgAUAKsTAA==.Vanillanice:BAAANQADCgMJBAAAAA==.Varrfife:BAAANQABCgIJAgAAAA==.Vaxaldan:BAABNQAECn8vAAIaAAoKoQ4VJwCaAQAaAAoKoQ4VJwCaAQAAAA==.',
Ve='Velindsong:BAAANQADCggICAAAAA==.Venj:BAAANQAECgIIAgAAAA==.Ventosa:BAACNQAFFH8HAAIjAAQKsQr5EgDsAAAjAAQKsQr5EgDsAAA1AAQKfzQAAiMACgrXGhg6AHYCACMACgrXGhg6AHYCAAAA.Vex:BAAANQAECgIIAgAAAA==.',
Vi='Vilox:BAAANQADCgIIAgAAAA==.Viltex:BAAANQADCgYICwAAAA==.Vilxten:BAAANQAECgUICQAAAA==.',
Vo='Voidleader:BAABNQAECn8mAAIKAAkKnA9EYwB6AQAKAAkKnA9EYwB6AQAAAA==.Vostok:BAABNQAECn8mAAIfAAgKuRDujADHAQAfAAgKuRDujADHAQAAAA==.',
Vy='Vylleria:BAAANQADCgYIBgAAAA==.',
['Vá']='Váyne:BAAANQAECgEIAQABNQAECgYICwASAAAAAA==.',
Wa='Warralok:BAAANQADCgYIBgAAAA==.Warramag:BAAANQAECgYICgAAAA==.Warranni:BAABNQAECn8vAAIFAAoKPB2uKADeAgAFAAoKPB2uKADeAgAAAA==.',
We='Weekend:BAABNQAECn8mAAIFAAoK7g+fOgCwAQAFAAoK7g+fOgCwAQAAAA==.',
Wh='Whatafox:BAABNQAECn8kAAMFAAkKjxxpTABFAgAFAAcKRB1pTABFAgAjAAYKEBAC1QC9AAAAAA==.Whittail:BAAANQABCggIFgAAAA==.',
Wi='Wikket:BAABNQAECn80AAIMAAoK6xAKIgC3AQAMAAoK6xAKIgC3AQAAAA==.',
Wo='Wortel:BAAANQADCgYIBgAAAA==.',
Wy='Wyelie:BAABNQAECn8ZAAMNAAkK3gzePAANAQANAAcKqQzePAANAQADAAMK4Qq7EQGXAAAAAA==.',
Xa='Xade:BAABNQAECn9CAAIQAAoKzR32FwCYAgAQAAoKzR32FwCYAgAAAA==.Xandendon:BAABNQAECn8XAAIGAAkKtw0KWACwAQAGAAkKtw0KWACwAQAAAA==.',
Xe='Xerond:BAAANQAECgUIDAAAAA==.Xevin:BAABNQAECn8mAAIFAAoKBx0uOwCJAgAFAAoKBx0uOwCJAgAAAA==.',
Xo='Xotha:BAAANQAECgYIBgAAAA==.',
Ya='Yaákov:BAABNQAECn86AAIUAAoK0BTOFwDDAQAUAAoK0BTOFwDDAQAAAA==.',
Yi='Yinosai:BAAANQADCgYICQAAAA==.',
Yo='Yougot:BAAANQADCggIDwAAAA==.',
Za='Zademedic:BAAANQAECgQIBgAAAA==.Zanarkin:BAAANQAECgEIAQAAAA==.Zanedore:BAAANQABCggIEwAAAA==.Zaranji:BAAANQADCgYIBgAAAA==.Zarisedra:BAACNQAFFH8SAAMCAAYKwAwuCQCHAQACAAYKwAwuCQCHAQADAAEKcAoZKwA+AAA1AAQKfywAAwIACgoaHJcmAM8CAAIACgoaHJcmAM8CAAMAAQoAAAjeARIAAAAA.Zarissena:BAABNQAECn8aAAIGAAgKwwQDQwDVAAAGAAgKwwQDQwDVAAAAAA==.Zarmina:BAAANQADCgEIAQAAAA==.Zarris:BAAANQABCgYIBAAAAA==.',
Ze='Zerdah:BAAANQADCgcIEwAAAA==.Zerogasm:BAAANQAECgMIAwAAAA==.Zerolicious:BAAANQAECgMJAwAAAA==.Zeroprophecy:BAAANQAECgIIAgAAAA==.Zevvo:BAABNQAECn8sAAIEAAoK1x5CMABXAgAEAAoK1x5CMABXAgAAAA==.',
Zo='Zoeybear:BAAANQAECgMIBAAAAA==.Zoraji:BAABNQAECn86AAIgAAoKIh7UAwBKAwAgAAoKIh7UAwBKAwAAAA==.',
['Év']='Évangeline:BAAANQAECgUICgAAAA==.',
['Ëd']='Ëdën:BAAANQAECgcICgAAAA==.',
['Ða']='Ðarkmoon:BAAANQABCgYICAAAAA==.',
['Ön']='Önyx:BAAANQADCgYIBgAAAA==.',
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
