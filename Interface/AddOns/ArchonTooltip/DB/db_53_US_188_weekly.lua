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

local lookup = {'Warrior-Protection','Paladin-Holy','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Warrior-Arms','Shaman-Elemental','DeathKnight-Unholy','DemonHunter-Havoc','Druid-Feral','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Monk-Mistweaver','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Mage-Arcane','Paladin-Protection','Monk-Windwalker','DemonHunter-Vengeance','Unknown-Unknown','DemonHunter-Devourer','Druid-Guardian','Priest-Shadow','Shaman-Enhancement','Evoker-Devastation','Druid-Restoration','Mage-Frost','DeathKnight-Blood','DeathKnight-Frost','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Priest-Discipline','Mage-Fire','Shaman-Restoration','Warrior-Fury',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abrocklock:BAAANQAECgEIAQAAAA==.',
Ad='Adorabull:BAABNQAECn8sAAIBAAoKnx+vBAA4AwABAAoKnx+vBAA4AwAAAA==.Adunal:BAAANQADCgEIAQAAAA==.',
Ae='Aevelee:BAAANQAECgYIDwAAAA==.',
Al='Alari:BAAANQADCgYIBgAAAA==.Aleeta:BAAANQAECgQIBAAAAA==.Alleriae:BAAANQAECgMIAwAAAA==.Allucard:BAAANQAECggICQAAAA==.',
Am='Amaria:BAAANQAECgQIBwABNQAECgkJGgACAM4aAA==.',
An='Anaki:BAAANQADCgUIBQAAAA==.Anduîiîn:BAAANQADCggICgAAAA==.Angelstörm:BAAANQAFFAEIAQAAAA==.Angelusnox:BAAANQAECgIIAgAAAA==.Antarias:BAAANQAECgQIBwAAAA==.Anubiz:BAAANQADCgEIAQAAAA==.Anzhe:BAABNQAECn8fAAQDAAoKtBubAgCjAgADAAkKtBubAgCjAgAEAAUKIg+/3AD5AAAFAAMKiA8kTQBsAAAAAA==.',
Ar='Araydin:BAAANQADCgEIAQAAAA==.Arckenon:BAACNQAFFH8JAAIGAAIK2R3fHACwAAAGAAIK2R3fHACwAAA1AAQKfz8AAgYACgqdIEQnAMQCAAYACgqdIEQnAMQCAAAA.Ardarl:BAAANQADCggICAAAAA==.Armdandrëady:BAAANQAECgUIBQAAAA==.Arranix:BAAANQADCgMIAwAAAA==.Arrica:BAAANQAECgEIAgAAAA==.Artemisv:BAAANQADCgIIAgAAAA==.Artorias:BAAANQAECgQIBAAAAA==.',
As='Ashog:BAAANQAECgIIAQAAAA==.',
At='Atillis:BAAANQAECggICwAAAA==.',
Au='Austenpally:BAABNQAECn8eAAMCAAgKHg93igB9AQACAAgKHg93igB9AQAGAAcKMg4z9AD8AAAAAA==.',
Av='Avarek:BAAANQADCgEIAQAAAA==.Aveycado:BAAANQAECgYIEwAAAA==.',
Ax='Axeflack:BAABNQAECn8wAAMBAAoK1BucCQA8AgABAAoK1BucCQA8AgAHAAUKMgf4/gDeAAAAAA==.Axegor:BAAANQAECgQIBwABNQAECgoKJwAIAKAdAA==.',
Az='Azaral:BAAANQADCgUJBQABNQAECggIGgAJAMMEAA==.Azmarija:BAAANQADCgEIAgAAAA==.',
Ba='Bacuda:BAAANQAECgUICQAAAA==.Batbane:BAAANQADCgYICAAAAA==.',
Be='Beggles:BAAANQADCgUIBQAAAA==.',
Bi='Biancadelrio:BAABNQAECn8WAAIKAAgKcwYsTQDyAAAKAAgKcwYsTQDyAAAAAA==.Bigguberment:BAABNQAECn8ZAAMLAAcK9hlvHQAdAQALAAcK9hlvHQAdAQAMAAEKEwa0jgAuAAAAAA==.Bigsneaky:BAABNQAECn8UAAQNAAcK6BEhKAD1AAANAAUKvxAhKAD1AAAOAAUKxQ9XoQDBAAAPAAEKAADTDgAAAAABNQAECgcIGwAQAKoVAA==.',
Bl='Blackbird:BAABNQAECn8gAAMRAAkKGwpZFgCPAQARAAkKGwpZFgCPAQASAAYKsgSIFADmAAABNQAFFAQICAATAKoSAA==.Bladekrim:BAAANQAECgEIAgAAAA==.Blindashunae:BAAANQADCgEIAQAAAA==.Blitzo:BAAANQADCgMIAwAAAA==.',
Bo='Boomhammer:BAAANQADCgYIBgAAAA==.Boredgored:BAAANQADCgcIBwABNQAECgoKMAAUAN0YAA==.Botia:BAABNQAECn8aAAIMAAkKZgNKZwCLAAAMAAkKZgNKZwCLAAAAAA==.Bourdeaux:BAAANQADCgcIFQAAAA==.',
Br='Braedia:BAAANQABCgEIAQAAAA==.Brainnmatter:BAAANQADCgEIAQAAAA==.Brashmoore:BAAANQADCgMIAwAAAA==.Brizik:BAAANQABCgUIBQAAAA==.Brookshields:BAAANQAECgcICwAAAA==.Bruised:BAAANQAECgIIAgAAAA==.Brunae:BAABNQAECn8pAAIBAAkKuQ/lFQBnAQABAAkKuQ/lFQBnAQAAAA==.Brunnera:BAAANQADCggIDgAAAA==.Bruuenor:BAAANQAECgEIAQAAAA==.Bruul:BAABNQAECn8cAAQGAAcKqBN/BgEUAQAGAAUKUg9/BgEUAQACAAQKpAYd/gCAAAAVAAEKAAAMbQA4AAAAAA==.',
By='Bytour:BAAANQAECgUIBwABNQAFFAMIBQAWAEUXAA==.',
Ca='Caenji:BAAANQAECgMIAwAAAA==.Captbenson:BAAANQADCgYIAQAAAA==.Carcharoth:BAAANQADCgMIAwAAAA==.Carmelina:BAAANQADCgQIBQAAAA==.Castanthrax:BAAANQADCgQIBAAAAA==.Cathryl:BAAANQADCgQIBAABNQAECgkJNgAXAL0dAA==.',
Ch='Chadgar:BAABNQAECn8wAAIUAAoK3RjEcACcAgAUAAoK3RjEcACcAgAAAA==.Chaoshammer:BAAANQADCggICAAAAA==.Chey:BAABNQAECn9OAAMOAAoKdiR6DQAKAwAOAAoKLyF6DQAKAwANAAYKDCTQHgAxAQAAAA==.Chipsahoy:BAAANQADCgEIAQAAAA==.Chormage:BAAANQADCgUICAAAAA==.Chíef:BAAANQAFFAMIBAAAAA==.',
Cl='Clarke:BAAANQABCgEIAQAAAA==.Close:BAAANQADCgUIBQABNQAECgoKFwACAIMMAA==.Clouds:BAAANQAECgIIAwABNQAECgQICQAYAAAAAA==.',
Co='Conorix:BAAANQADCggITgAAAA==.Corvo:BAAANQADCggICAABNQAECgkJNgAXAL0dAA==.',
Cr='Crataxxis:BAABNQAECn88AAMKAAoKbQ65MwCAAQAKAAoKbQ65MwCAAQAZAAEKAADOcwAnAAAAAA==.',
Cu='Cudara:BAAANQADCgIIAgABNQAECgUICQAYAAAAAA==.Cupra:BAAANQADCgIIAgAAAA==.',
Cy='Cydon:BAABNQAECn8/AAIaAAkK5R9iCwC2AgAaAAkK5R9iCwC2AgAAAA==.Cythraul:BAABNQAECn82AAIXAAkKvR3rBgApAgAXAAkKvR3rBgApAgAAAA==.',
Da='Daerith:BAAANQADCgYICgAAAA==.Daerrith:BAAANQADCgYIBgAAAA==.Dagni:BAAANQAECgEIAQAAAA==.Dantey:BAAANQADCgUIBQABNQAECgoKOgAbAEMfAA==.Darkveil:BAAANQADCgQIBAAAAA==.Darrwin:BAABNQAECn8hAAIGAAkKcBUTogCKAQAGAAkKcBUTogCKAQAAAA==.Daylight:BAAANQADCgYIBgAAAA==.',
De='Deathhor:BAAANQADCgQIBQAAAA==.Deathspacito:BAAANQADCgMIAwAAAA==.Demonalsa:BAAANQADCgUIBQABNQAECggIGwAcABIVAA==.Derrith:BAAANQADCgUIBgAAAA==.Dezgra:BAAANQAECgcIDwAAAA==.',
Df='Dfabness:BAABNQAECn8pAAIWAAoKbxEmGgDcAQAWAAoKbxEmGgDcAQAAAA==.',
Do='Doomfury:BAAANQADCgEIAgAAAA==.Dotbush:BAAANQAECgQIBAABNQAFFAUICAAGAAcDAA==.',
Dr='Dracthayr:BAABNQAECn8/AAIdAAoKWgucDACJAQAdAAoKWgucDACJAQAAAA==.Dragonhammer:BAABNQAECn83AAIGAAoKHSI4EQAkAwAGAAoKHSI4EQAkAwAAAA==.Dreaming:BAAANQAECggICAABNQAECgoKFwACAIMMAA==.Drimclaw:BAAANQAECgIIAwAAAA==.Drubo:BAABNQAECn8UAAMeAAYKNgusTgDBAAAeAAUK3wqsTgDBAAAMAAMK6AGhhgA5AAAAAA==.Drx:BAABNQAECn81AAQRAAkKzQe3HgAcAQARAAkKzQe3HgAcAQAdAAYKsQjHFwC9AAASAAIKGAWtGgBOAAAAAA==.',
Du='Dukkelemon:BAAANQAECgQIBwAAAA==.',
Ed='Edenaza:BAAANQAECgQIBAAAAA==.',
El='Elanore:BAACNQAFFH8IAAITAAQKqhLrGAAxAQATAAQKqhLrGAAxAQA1AAQKfy4AAxMACgolHGwaAAQDABMACgolHGwaAAQDABsAAQoAALB+AAAAAAAA.Elicithy:BAAANQABCgUIBQABNQAECggIGwAcABIVAA==.Elison:BAAANQAECgQIBAABNQAECggIGgAJAMMEAA==.Ellaini:BAAANQAECgYICQAAAA==.Elliana:BAAANQAECgUIDAABNQAFFAQICAATAKoSAA==.Ellie:BAAANQAECgEIAgABNQAECgoKMAACANwgAA==.Elloise:BAAANQADCgQIBQABNQAFFAQICAATAKoSAA==.Elmichi:BAAANQAECgMIAQABNQAECggIBAAYAAAAAA==.Elsae:BAABNQAECn85AAIVAAoKahRmIQDYAQAVAAoKahRmIQDYAQAAAA==.Elseb:BAAANQADCgEIAQAAAA==.',
Em='Emeric:BAAANQADCgQIBAAAAA==.',
Ev='Evasion:BAABNQAFFH8FAAINAAMKgQzKEADfAAANAAMKgQzKEADfAAAAAA==.Everios:BAACNQAFFH8IAAIBAAUKLxS3AwDDAAABAAUKLxS3AwDDAAA1AAQKfzUAAgEACgrJHzEIANECAAEACgrJHzEIANECAAAA.Evic:BAAANQADCgYICAAAAA==.Evielyn:BAAANQADCgUJBQABNQAFFAQICAATAKoSAA==.',
Fa='Faeleader:BAAANQAECgEIAQAAAA==.Faevelina:BAAANQAECgEIAQABNQAECgcIGQAfAMsKAA==.Faytadori:BAABNQAECn9WAAMMAAoKAByeFAB1AgAMAAoKAByeFAB1AgAeAAQKmQpsYwB4AAAAAA==.',
Fe='Felgrrl:BAAANQADCggISQAAAA==.Feyreh:BAAANQAECgIIBAAAAA==.',
Fi='Fidget:BAABNQAECn8uAAINAAgKRgpVGQBbAQANAAgKRgpVGQBbAQAAAA==.',
Fl='Fletch:BAABNQAECn8WAAIHAAkKFQW4zwBUAQAHAAkKFQW4zwBUAQAAAA==.',
Fo='Forever:BAABNQAECn8XAAMCAAoKgwwnkgAEAQACAAoKgwwnkgAEAQAGAAIKfQO7uAEaAAAAAA==.',
Fr='Frahra:BAAANQAECgIIAgAAAA==.Frique:BAAANQAECgUIEAAAAA==.Frozenyogert:BAAANQAECgQICQAAAA==.',
Ga='Galbur:BAACNQAFFH8IAAMgAAUKZwxeIQB9AAAgAAMKxxFeIQB9AAAJAAIKpgHTFQA4AAA1AAQKfzYABCAACgpxFmYtAGACACAACQpJFmYtAGACAAkACQpAFegyAFkBACEAAgozCCmcAGUAAAAA.Galdrin:BAABNQAECn8ZAAIfAAcKywr4FgBFAQAfAAcKywr4FgBFAQAAAA==.Gaspode:BAAANQADCgYICwAAAA==.Gassann:BAABNQAECn8ZAAIGAAgKWBa5rgDCAQAGAAgKWBa5rgDCAQAAAA==.',
Ge='Geers:BAABNQAECn82AAIfAAoK/iIkAQCRAwAfAAoK/iIkAQCRAwAAAA==.Geta:BAAANQAECgYICQABNQAECgoKOAAHAEYiAA==.Getabrew:BAAANQAECgYICQABNQAECgoKOAAHAEYiAA==.Getacurse:BAAANQAECgUIBQABNQAECgoKOAAHAEYiAA==.Getagrip:BAAANQADCgIIAgABNQAECgoKOAAHAEYiAA==.Getalife:BAAANQAECgEIAQABNQAECgoKOAAHAEYiAA==.Getarage:BAABNQAECn84AAMHAAoKRiLLEgAJAwAHAAoKRiLLEgAJAwABAAMKsx+YJQAXAQAAAA==.Getasoar:BAAANQADCgQIBgABNQAECgoKOAAHAEYiAA==.Getastab:BAAANQAECggIEQABNQAECgoKOAAHAEYiAA==.',
Gh='Ghil:BAABNQAECn8fAAQiAAoKuBlVAwDIAgAiAAoKuBlVAwDIAgAjAAMKtAseYQBjAAAkAAEKMw/vPQE6AAAAAA==.',
Gi='Gildersleeve:BAAANQAECgUIBgAAAA==.Gilia:BAAANQAECgIIBAAAAA==.Gimlí:BAAANQADCgEIAQAAAA==.Gingersnaps:BAAANQABCgYICAAAAA==.',
Gl='Glynix:BAAANQAECgIIBAAAAA==.',
Gn='Gnosher:BAABNQAFFH8FAAIIAAQKsQY+FgC8AAAIAAQKsQY+FgC8AAAAAA==.Gnosherson:BAAANQAECgUICQABNQAFFAQIBQAIALEGAA==.',
Go='Goku:BAABNQAECn8zAAQWAAkKURPiHQCzAQAWAAkKURPiHQCzAQAlAAYK8QwPHQAXAQAQAAEKsgUIVAAiAAAAAA==.Goldiwarlock:BAAANQADCgUIBwAAAA==.Goloron:BAAANQAECgQIBAAAAA==.Gornub:BAAANQADCgYIBgAAAA==.Gorzok:BAAANQABCgEIAQAAAA==.',
Gr='Graymayn:BAAANQAECgYICwAAAA==.Grekk:BAAANQAECgMIAwAAAA==.Grelldar:BAAANQADCgEIAQAAAA==.Grimflaps:BAABNQAECn84AAMdAAkKAQ66DACGAQAdAAkKAQ66DACGAQARAAUKSwRZOwC+AAAAAA==.',
Gu='Gunderthirth:BAACNQAFFH8NAAIBAAYKqxy2AAApAgABAAYKqxy2AAApAgA1AAQKfyIAAgEACgpqIyUDAHIDAAEACgpqIyUDAHIDAAAA.Guulfang:BAAANQADCgMIAwAAAA==.',
Gw='Gwaeniiha:BAABNQAECn8uAAIGAAkKEg0rqwB5AQAGAAkKEg0rqwB5AQAAAA==.',
Ha='Haan:BAAANQADCgYIDQAAAA==.Haliran:BAAANQAECgQIBQAAAA==.Handsoap:BAABNQAECn8qAAIKAAkKaguVNwBpAQAKAAkKaguVNwBpAQAAAA==.Harakhty:BAAANQAECgUICQAAAA==.Hardhitter:BAABNQAECn9TAAMBAAoKGBrsDwArAgABAAoKZRfsDwArAgAHAAoKERRsWAD1AQAAAA==.',
He='Hellumph:BAABNQAECn8sAAIXAAoKKBXiCADnAQAXAAoKKBXiCADnAQAAAA==.Hevensdemon:BAABNQAECn8WAAIXAAkKiBaSBwARAgAXAAkKiBaSBwARAgAAAA==.Hevensrath:BAABNQAECn83AAMVAAoKBx/DEgAAAgAGAAoKrxtFUwA0AgAVAAoKHBzDEgAAAgAAAA==.Hevensreaper:BAABNQAECn8gAAMgAAcKzRudIgDlAQAgAAcKzRudIgDlAQAJAAQKwAKatwB+AAAAAA==.Hevensvoid:BAABNQAECn8ZAAQbAAoKQRPYJABdAQAbAAcKmg3YJABdAQATAAMKyAj0ywCPAAAmAAEKsALLHwAaAAAAAA==.Hevshaolin:BAAANQAECgYIDAAAAA==.Hexhorn:BAAANQADCggJDgAAAA==.Hextermorgan:BAAANQABCggIEAABNQAECgoKNgAhALMbAA==.',
Ho='Hokuden:BAABNQAECn9AAAIhAAoKxRQ8MAAkAgAhAAoKxRQ8MAAkAgAAAA==.Holphie:BAAANQAECggICwAAAA==.Holyholyholy:BAAANQADCggICAAAAA==.Homet:BAAANQADCgQIBQAAAA==.Horsebananas:BAABNQAECn8UAAMDAAoKkAl3DQDEAAAEAAkKkAdS4gA8AQADAAMKswt3DQDEAAAAAA==.',
Hu='Huddington:BAABNQAECn8eAAIUAAoKzgmEnQBqAQAUAAoKzgmEnQBqAQAAAA==.',
Hy='Hyperion:BAABNQAECn8YAAIeAAkKzRkqEgCmAgAeAAkKzRkqEgCmAgABNQAECgkJNgAXAL0dAA==.',
Ig='Igknight:BAAANQAECgcICgABNQAECgoKPQACAGkXAA==.',
Il='Ilsi:BAAANQADCgYIBgABNQAECgoKJwAIAKAdAA==.',
Im='Impthrower:BAAANQAECgIIAgABNQADCgYJDwAYAAAAAA==.',
In='Indecent:BAABNQAECn8wAAMkAAoKxhs9QACRAgAkAAoKhhs9QACRAgAjAAIKHxusTQCWAAAAAA==.Indeed:BAAANQAECggICQAAAA==.Indree:BAAANQAECgQIBAAAAA==.Inibble:BAAANQABCgUICAAAAA==.',
Iq='Iqfbeef:BAAANQADCgYICgAAAA==.',
Is='Ishy:BAABNQAECn8wAAMUAAkK7xosZgCyAgAUAAkK7xosZgCyAgAnAAMKLAusCQBpAAAAAA==.',
Iw='Iwannalive:BAAANQADCgIIAgAAAA==.',
Iz='Izziey:BAAANQADCgEIAQAAAA==.',
Ja='Jack:BAABNQAECn8qAAQbAAoKNRlkIgAhAgAbAAgKQxZkIgAhAgATAAcKrBXOcwCAAQAmAAMKURWSFwC5AAAAAA==.Jackieblaze:BAAANQAECgUICgABNQAFFAUICAAmAIQTAA==.Jackieplays:BAACNQAFFH8IAAQmAAUKhBPdAgCIAAATAAIKChiZKACiAAAbAAIK5AluEQCJAAAmAAIK7QvdAgCIAAA1AAQKfz4ABCYACgo5IF8DAL4CACYACAqNHl8DAL4CABMACgqiHMs5AIICABsAAQo2DCp6ADQAAAAA.Jaded:BAABNQAECn8uAAMoAAoKsRzEIwClAgAoAAoKsRzEIwClAgAIAAMKjwrPAAGPAAAAAA==.Jandexx:BAAANQADCgMIAwAAAA==.',
Je='Jeses:BAABNQAECn8WAAMVAAoKdRQLKQCUAQAVAAoKdRQLKQCUAQAGAAIKxglmWwFvAAAAAA==.Jessa:BAAANQADCgQIBAAAAA==.',
Jo='Jollah:BAABNQAECn8bAAQQAAcKqhUuLQACAQAQAAUKjg8uLQACAQAWAAYKchNgNQD2AAAlAAEKAAB8MAA6AAAAAA==.Jorawa:BAAANQAECgUIBQAAAA==.',
Ju='Jutic:BAABNQAECn9BAAIoAAoKTiMoDQBXAwAoAAoKTiMoDQBXAwAAAA==.',
Ka='Kageken:BAAANQADCgQIBAABNQADCgYJEQAYAAAAAA==.Kaithul:BAAANQADCgEIAQAAAA==.Kanetsu:BAAANQADCgEIAQAAAA==.Kardas:BAABNQAECn8jAAIEAAoKoghQugCPAQAEAAoKoghQugCPAQAAAA==.',
Kb='Kbilly:BAABNQAECn89AAIoAAoK7x6uIADnAgAoAAoK7x6uIADnAgAAAA==.',
Ke='Kentarou:BAAANQABCgUIBQAAAA==.Keylerin:BAACNQAFFH8PAAIOAAYKahbQDABBAQAOAAYKahbQDABBAQA1AAQKfyoAAg4ACgqJHjwIAPYCAA4ACgqJHjwIAPYCAAAA.',
Ki='Kiikee:BAAANQADCgQICAAAAA==.Kimosabi:BAAANQABCgIIAgAAAA==.Kitto:BAAANQADCgYJBgAAAA==.Kittvulpy:BAAANQADCgYICgAAAA==.',
Kl='Klausinator:BAAANQADCggIEQAAAA==.',
Kn='Knottes:BAAANQABCggILAAAAA==.',
Ko='Komos:BAAANQAECgEIAQAAAA==.',
Kr='Krampus:BAABNQAECn8xAAIcAAoKuQsMFQDEAQAcAAoKuQsMFQDEAQAAAA==.Kranok:BAABNQAECn8pAAIFAAkKvw8BGgC0AQAFAAkKvw8BGgC0AQAAAA==.Krennthis:BAAANQAECgUIBQAAAA==.Krimbruiser:BAAANQADCgYIBwABNQAECgEIAgAYAAAAAA==.Krimhuntress:BAAANQADCgYIBgAAAA==.',
Ku='Kunac:BAAANQADCgYIEAAAAA==.',
Ky='Kyran:BAAANQADCgUIBwAAAA==.Kyrun:BAABNQAECn8cAAIcAAgKYgnOHABPAQAcAAgKYgnOHABPAQAAAA==.Kytrina:BAAANQADCgIIAgAAAA==.',
La='Lactoes:BAAANQADCgYIBgAAAA==.Lamoran:BAAANQAECgUICQAAAA==.',
Le='Lemón:BAAANQAECgEIAQAAAA==.',
Lh='Lhani:BAABNQAECn83AAITAAoKZxJ+RwAZAgATAAoKZxJ+RwAZAgAAAA==.',
Li='Lilguysci:BAAANQAECgMIBAAAAA==.Lizord:BAABNQAECn8dAAIRAAoKkhLQDQA5AgARAAoKkhLQDQA5AgAAAA==.',
Ll='Llothien:BAAANQAECgIIAgAAAA==.Llyrael:BAABNQAECn81AAMTAAoKRAdeeABxAQATAAoKRAdeeABxAQAbAAEK2gILhAAlAAAAAA==.',
Lo='Lonard:BAAANQAECgIIAgAAAA==.',
Lu='Lugosi:BAAANQAECgEIAQAAAA==.',
Ly='Lyfe:BAAANQABCgUIBwAAAA==.',
Ma='Machlain:BAAANQADCgQIBAABNQAECgoKIwAVAKsaAA==.Macklin:BAAANQAECgEIAQAAAA==.Maddeleine:BAAANQADCgYIEwAAAA==.Magara:BAAANQAECgQIBAAAAA==.Magicdemon:BAABNQAECn87AAIKAAoKOyU9CAARAwAKAAoKOyU9CAARAwAAAA==.Magichunter:BAAANQAECggIDwABNQAECgoKOwAKADslAA==.Magicpaladin:BAABNQAECn8aAAIGAAkKdRzZOQB/AgAGAAkKdRzZOQB/AgABNQAECgoKOwAKADslAA==.Magicshaman:BAABNQAECn8WAAIcAAcKYhh2FQC9AQAcAAcKYhh2FQC9AQABNQAECgoKOwAKADslAA==.Magnafratrem:BAAANQAECgQIBgAAAA==.Makall:BAAANQABCgQIBAAAAA==.Malaah:BAABNQAECn8oAAIIAAoKphH0dwC6AQAIAAoKphH0dwC6AQAAAA==.Malatrixx:BAAANQAECgUIBQAAAA==.Mansuno:BAABNQAECn9DAAQGAAkKfxn0YAB3AgAGAAkKfxn0YAB3AgACAAcKTQwmegBHAQAVAAQKYgxQRwCIAAAAAA==.Mapachote:BAABNQAECn8xAAIFAAkKXhPFEgAWAgAFAAkKXhPFEgAWAgAAAA==.Marodin:BAAANQADCggITgAAAA==.Maynor:BAAANQABCggIFQAAAA==.Mazboda:BAABNQAECn85AAQkAAkK4RVJXgC6AQAkAAkKhxVJXgC6AQAiAAMKCRAXHgCKAAAjAAIKugg3ZABcAAAAAA==.',
Me='Meatbaal:BAAANQAECgUIDQAAAA==.Medïc:BAAANQADCggICAAAAA==.Melinaria:BAABNQAECn8nAAMbAAoKfhUlJgD9AQAbAAoKfhUlJgD9AQAmAAEK2w6rFwBAAAAAAA==.Merewene:BAABNQAECn8UAAIEAAYKLQIUCgGeAAAEAAYKLQIUCgGeAAAAAA==.Merkabai:BAAANQADCgIIAgAAAA==.',
Mi='Mileta:BAABNQAECn86AAIMAAoKCRzTHADiAgAMAAoKCRzTHADiAgAAAA==.Minuette:BAAANQAECgMIAwAAAA==.',
Mo='Montblanc:BAAANQAECgQIBAABNQAECgUICgAYAAAAAA==.Moonwatcher:BAAANQADCgQIBAABNQAFFAQICAATAKoSAA==.Morgnox:BAAANQAECgIIAgAAAA==.Morne:BAAANQADCgEIAQAAAA==.',
Mu='Murdercookie:BAAANQAECgEIAQAAAA==.',
Na='Nazgul:BAAANQADCgcICAAAAA==.',
Ne='Necrokrim:BAAANQAECgEIAgAAAA==.Necronic:BAAANQAECgIIAwAAAA==.Necronight:BAAANQAECgMIAwAAAA==.Necroreign:BAABNQAECn9UAAIKAAoKWB2XEQCdAgAKAAoKWB2XEQCdAgAAAA==.Need:BAAANQAECgIIAgAAAA==.Neherenia:BAABNQAECn86AAIhAAoKHRViKQARAgAhAAoKHRViKQARAgAAAA==.Nekronn:BAAANQAECgMIAwAAAA==.Nervous:BAAANQAECggIAgABNQAECgoKFwACAIMMAA==.Nessee:BAABNQAECn8XAAIfAAcKnAviHgDzAAAfAAcKnAviHgDzAAAAAA==.',
Ni='Niall:BAAANQAECgEIAgAAAA==.Nightfire:BAAANQABCgcIEwAAAA==.Nihowdy:BAABNQAECn9EAAIPAAoK3iOGAAAUAwAPAAoK3iOGAAAUAwAAAA==.',
No='Norrin:BAAANQABCggIDgAAAA==.',
Oc='Octalexane:BAAANQADCgYIBgABNQAECgkJKQABALkPAA==.',
Od='Odelagt:BAAANQAECggIBAAAAA==.',
On='Onimusha:BAAANQAECgEIAQAAAA==.',
Or='Orci:BAABNQAECn8vAAIjAAkKYA15CABGAQAjAAkKYA15CABGAQAAAA==.Orryn:BAAANQADCgEIAQAAAA==.Ortalbem:BAABNQAECn9KAAMUAAoKzh1wPgBTAgAUAAoKQx1wPgBTAgAfAAkKvRtoDwCbAQAAAA==.',
Ou='Oulli:BAAANQABCggIHwAAAA==.',
Ov='Ovi:BAAANQAECgUICwAAAA==.',
Pa='Painthuffer:BAABNQAECn8jAAMOAAoKxBQZMgAzAgAOAAkKURMZMgAzAgANAAoK9xB7MAAgAgABNQAECgoKMAAUAN0YAA==.Paramour:BAAANQAECgIIAgAAAA==.Pazuuzu:BAAANQAECgEIAQAAAA==.',
Pe='Peddles:BAAANQAECgUIDQAAAA==.Petmedaddy:BAAANQABCgEIAQAAAA==.',
Ph='Pherix:BAABNQAECn86AAIbAAoKQx/wDQB7AgAbAAoKQx/wDQB7AgAAAA==.Philipfry:BAABNQAECn9GAAMCAAoKxBMBTgAyAgACAAoKxBMBTgAyAgAGAAcKbBj1nACTAQAAAA==.Phill:BAAANQADCgcIEwAAAA==.Phuuta:BAAANQAECgMIAwAAAA==.',
Pl='Plaguetusk:BAAANQADCgQIBAAAAA==.',
Po='Pontoon:BAAANQAECgUIBQAAAA==.Poomacha:BAAANQAECgYIEgAAAA==.Potatopants:BAAANQAECgEIAQAAAA==.',
Pr='Prinlina:BAAANQADCggIDQAAAA==.Proeliator:BAAANQADCgYICQAAAA==.',
Py='Pyree:BAABNQAECn8uAAIdAAoKmwzyDQBqAQAdAAoKmwzyDQBqAQAAAA==.Pyxrin:BAAANQAECgUIBQAAAA==.',
Qe='Qed:BAAANQADCggICQAAAA==.',
Ra='Radimus:BAAANQAECgEIAQAAAA==.Raenne:BAAANQADCgMIAwAAAA==.Rainvelle:BAAANQADCgQIBAAAAA==.Raistlain:BAABNQAECn8fAAIbAAgKwRQKJgD+AQAbAAgKwRQKJgD+AQAAAA==.Ralli:BAABNQAECn9CAAMZAAoKlh+ZCQC8AgAKAAkKxBq9FgDmAgAZAAoK1B6ZCQC8AgAAAA==.Ralls:BAAANQAECgYIBgABNQAECgcIDAAYAAAAAA==.Rallsdk:BAAANQADCgYIBgABNQAECgcIDAAYAAAAAA==.Rallsodins:BAAANQAECgcIDAAAAA==.Ranulf:BAAANQAECgQIDgAAAA==.Ratava:BAAANQAECgYIDwAAAA==.Ratrot:BAAANQADCggICQAAAA==.Raztar:BAAANQADCgUIBQAAAA==.',
Re='Reddemon:BAAANQAECggIEgAAAA==.Rehvenge:BAAANQAECgMIBAAAAA==.Rekarra:BAAANQADCgcIBwAAAA==.Reks:BAAANQAECgUIBQAAAA==.Reldarus:BAEBNQAECn8wAAQmAAoKCSP4AgDVAgAmAAcK1CP4AgDVAgATAAoK3xtlSQBKAgAbAAEK9BWCcABHAAAAAA==.Rena:BAABNQAECn8qAAQdAAoKKhIHFAD1AAAdAAcKJwoHFAD1AAARAAMKywM2MAB5AAASAAQKxQNkHQB5AAAAAA==.Revilation:BAABNQAECn8mAAIVAAoK9RLrHAAEAgAVAAoK9RLrHAAEAgAAAA==.Rezjyk:BAAANQADCgYIBgABNQAECgoKSgAGAHUbAA==.Rezzyk:BAABNQAECn9KAAIGAAoKdRsHOQCCAgAGAAoKdRsHOQCCAgAAAA==.',
Rh='Rhyxali:BAAANQAECgUIEQAAAA==.',
Ri='Riibirth:BAAANQADCgYIBgAAAA==.Riis:BAAANQADCgEIAQAAAA==.',
Ru='Ruknan:BAAANQADCgQIBAABNQAECgoKQQAZAOcUAA==.',
Ry='Rygelon:BAAANQAECgQICQAAAA==.',
Sa='Sableanne:BAAANQAECgQICQAAAA==.Sacredscales:BAAANQADCgMJAwAAAA==.Samvimes:BAAANQAECgIIBQAAAA==.Sangreene:BAABNQAECn8yAAIbAAoKexzkCwCdAgAbAAoKexzkCwCdAgAAAA==.Sargis:BAABNQAECn9aAAMGAAoKnyInFQAPAwAGAAoKnyInFQAPAwACAAgKOBhuaADeAQAAAA==.',
Sc='Schrödinger:BAAANQAECgEIAQABNQAECgkJNgAXAL0dAA==.Scott:BAAANQAECgQIBAAAAA==.',
Se='Selira:BAAANQAECgcIEAABNQAECgoKNgAUAHETAA==.Serissa:BAAANQAECgIIAgAAAA==.Serjankins:BAAANQADCgQIBAAAAA==.Setsuna:BAAANQABCgYIDAABNQAECgoKIAAbAGYeAA==.',
Sh='Shadowbrooks:BAAANQADCgIIAgAAAA==.Shadowgiver:BAAANQADCgcICwAAAA==.Shagol:BAABNQAECn8mAAITAAcKnxkJcgCFAQATAAcKnxkJcgCFAQAAAA==.Shaidic:BAABNQAECn8XAAINAAcKzguwJAAKAQANAAcKzguwJAAKAQAAAA==.Shamemoon:BAAANQAECgEJAQABNQAECgkJHwAkANUMAA==.Shamunroe:BAABNQAECn8xAAMIAAoKsBebUwArAgAIAAoKsBebUwArAgAoAAUK1Aow1gC6AAAAAA==.Shatterhoof:BAABNQAECn8YAAILAAcKRg2qIAD9AAALAAcKRg2qIAD9AAAAAA==.Shelle:BAAANQAECgMIAwAAAA==.Shiftysmage:BAAANQAECgEIAQABNQAECgoKIQAaAOAUAA==.Shingra:BAACNQAFFH8LAAISAAQKEhMCBwD3AAASAAQKEhMCBwD3AAA1AAQKfyMAAhIACQrKFjoGAGoCABIACQrKFjoGAGoCAAAA.Shores:BAAANQABCgIIAQAAAA==.Shylindra:BAAANQAECgQIBAAAAA==.',
Si='Sigourney:BAAANQAECgYIDwABNQAECgoKFAADAJAJAA==.Silversho:BAAANQAECgUIBQAAAA==.Silvren:BAAANQADCgIIAgAAAA==.',
Sk='Skill:BAABNQAECn8eAAMeAAoKHRKIKgDKAQAeAAoKHRKIKgDKAQAMAAQKRw6wegDgAAAAAA==.',
Sl='Slighttrash:BAAANQAECgUIDQAAAA==.',
Sm='Smallcrow:BAABNQAECn8bAAMWAAkKbR40FwCSAgAWAAgKbR40FwCSAgAQAAQK0Q1HMwDQAAAAAA==.',
So='Somdot:BAEBNQAECn9OAAIbAAoK/yBpCABWAwAbAAoK/yBpCABWAwAAAA==.Somedeekay:BAAANQAECgYIDgAAAA==.',
Sp='Spirit:BAABNQAECn8VAAMRAAgKFRrtEQCNAgARAAgKFRrtEQCNAgAdAAEKCwjLQQAmAAABNQAFFAMIBQANAIEMAA==.',
Sq='Squirrellock:BAAANQAECgEIAgAAAA==.',
St='Starga:BAAANQADCgQIBAAAAA==.Starge:BAAANQADCgUIBQAAAA==.Starre:BAAANQADCgQIBAAAAA==.Steffey:BAAANQAECgYIEgAAAA==.Stepbro:BAAANQADCgcIDAAAAA==.Stoikk:BAABNQAECn8UAAIIAAcK3hCPkQB4AQAIAAcK3hCPkQB4AQAAAA==.Straven:BAABNQAECn8gAAIfAAkK4xNaEAChAQAfAAkK4xNaEAChAQAAAA==.Sturgeson:BAACNQAFFH8VAAIBAAYKqxnsAQApAQABAAYKqxnsAQApAQA1AAQKfy0AAgEACQp1IW4JALUCAAEACQp1IW4JALUCAAAA.',
Su='Suffocation:BAEANQAECgYIBgABNQAFFAkJKQAjAIEhAA==.Sulwen:BAABNQAECn8wAAITAAoKHxUtUgDxAQATAAoKHxUtUgDxAQAAAA==.Sundance:BAAANQADCgUIBQAAAA==.Sunray:BAAANQAECgUIBQAAAA==.',
Sw='Swiftfeet:BAABNQAECn8oAAIEAAoK9BQSkACWAQAEAAoK9BQSkACWAQAAAA==.',
['Sé']='Sésho:BAAANQADCgQIBgAAAA==.',
['Sö']='Söranin:BAAANQAECgMIBAAAAA==.',
['Sø']='Sømdøt:BAEANQAECggIDAABNQAECgoKTgAbAP8gAA==.',
Ta='Taeili:BAABNQAECn8cAAIaAAgK1BY6FwD5AQAaAAgK1BY6FwD5AQAAAA==.Taeror:BAAANQADCgQIBAAAAA==.Tanequil:BAACNQAFFH8IAAIeAAUKNAM0CwAHAQAeAAUKNAM0CwAHAQA1AAQKfzcAAh4ACgpjD/spAM8BAB4ACgpjD/spAM8BAAAA.',
Te='Techromancer:BAABNQAECn8tAAMJAAoKlhopKgCPAgAJAAoKeRYpKgCPAgAhAAgKnhlFKAAXAgABNQAECgoKOgAbAEMfAA==.Tem:BAAANQABCgQIBAABNQADCgcIDgAYAAAAAA==.',
Th='Thanatias:BAAANQAECgYIDAAAAA==.Thantasia:BAAANQAECgMIAgAAAA==.Theakunda:BAABNQAECn8UAAMIAAoKSxWzVQAjAgAIAAkKGxazVQAjAgAoAAIK/Aqr8AA8AAAAAA==.Theodis:BAAANQAECgQIBAAAAA==.Thistlebrew:BAAANQAECgQIBAAAAA==.Thokdar:BAAANQAECgQIBQAAAA==.Thorid:BAAANQADCgEIAQAAAA==.',
Ti='Tifà:BAAANQAECgIIAgAAAA==.Tillago:BAAANQADCggICgAAAA==.Timothy:BAAANQAECgYICgAAAA==.Timothyjohn:BAAANQAECgYIDwAAAA==.Tinkphooey:BAAANQAECgMIBAAAAA==.Tirianna:BAAANQADCgEIAQABNQAFFAQICAATAKoSAA==.Tituba:BAABNQAECn88AAIkAAoKbBpkOAAwAgAkAAoKbBpkOAAwAgAAAA==.',
To='Toklore:BAAANQADCgcIDgAAAA==.Tonepavone:BAAANQADCgYIBgAAAA==.Tormmok:BAAANQADCgQIBAAAAA==.',
Tr='Traazz:BAAANQADCgYICgAAAA==.Trey:BAAANQAECgcICwAAAA==.Trior:BAAANQAECgQIBQAAAA==.',
Ts='Tsuruga:BAABNQAECn8nAAIlAAoKPAYyDwAyAQAlAAoKPAYyDwAyAQAAAA==.',
Tu='Turkwise:BAABNQAECn9OAAQaAAoKdxSHGwCnAQAaAAoKShGHGwCnAQALAAkKRROMGABSAQAeAAQKwgQnZgBhAAAAAA==.',
Uc='Ucallmesam:BAAANQAECgQIBwAAAA==.',
Ul='Ulodude:BAAANQADCgYIBgAAAA==.',
Un='Unholydiddy:BAAANQADCggICQAAAA==.',
Ur='Urobolos:BAAANQAECgMIAwAAAA==.',
Uv='Uvari:BAAANQAECgcIEwAAAA==.',
Va='Vacalaca:BAABNQAECn8fAAMkAAkK1QwNbACUAQAkAAkK1QwNbACUAQAjAAEK9AGjhwAeAAAAAA==.Valany:BAAANQADCgIIAgAAAA==.Valkira:BAACNQAFFH8IAAIcAAUKlgxvBADPAAAcAAUKlgxvBADPAAA1AAQKfzcAAxwACgpNHSIPAHgCABwACgptHCIPAHgCAAgABgpxGVSLAIgBAAAA.Valton:BAACNQAFFH8FAAIWAAMKRRcUCwDFAAAWAAMKRRcUCwDFAAA1AAQKf0YAAhYACgrKJcEDAJkDABYACgrKJcEDAJkDAAAA.Vancede:BAAANQAECgQIBAABNQAECgoKKAAZAKITAA==.Vanillanice:BAAANQADCgMJBAAAAA==.Varrfife:BAAANQABCgIIAgAAAA==.Vaxaldan:BAABNQAECn8vAAIgAAoKoQ4LMACOAQAgAAoKoQ4LMACOAQAAAA==.',
Ve='Velindsong:BAAANQADCggICAAAAA==.Venj:BAAANQAECgIIAgAAAA==.Ventosa:BAACNQAFFH8HAAIoAAQKsQpmGADsAAAoAAQKsQpmGADsAAA1AAQKfzkAAigACgqSHBg6AHYCACgACgqSHBg6AHYCAAAA.Vex:BAAANQAECgIIBAAAAA==.',
Vi='Vilox:BAAANQADCgIIAgAAAA==.Viltex:BAAANQADCgYICwAAAA==.Vilxten:BAAANQAECgUICQAAAA==.',
Vo='Voidleader:BAABNQAECn8nAAITAAoKzg41agCfAQATAAoKzg41agCfAQAAAA==.Vostok:BAABNQAECn8oAAIkAAoKoQ7ujADHAQAkAAoKoQ7ujADHAQAAAA==.',
Vy='Vylleria:BAAANQADCgYIBgAAAA==.',
['Vá']='Váyne:BAAANQAECgEIAQABNQAECgYICwAYAAAAAA==.',
Wa='Warmth:BAAANQADCgEIAQAAAA==.Warralok:BAAANQADCgYIBgAAAA==.Warramag:BAAANQAECgYICgAAAA==.Warranni:BAABNQAECn8vAAIIAAoKPB2uKADeAgAIAAoKPB2uKADeAgAAAA==.',
We='Weekend:BAABNQAECn8nAAIIAAoKVRBXSAC0AQAIAAoKVRBXSAC0AQAAAA==.',
Wh='Whatafox:BAABNQAECn8lAAMIAAkKlB1pTABFAgAIAAcKRB1pTABFAgAoAAYKEBAC1QC9AAAAAA==.Whittail:BAAANQABCggIFgAAAA==.',
Wi='Wikket:BAABNQAECn81AAIMAAoK6xBgKQC1AQAMAAoK6xBgKQC1AQAAAA==.',
Wo='Wortel:BAAANQADCgYIBgAAAA==.',
Wy='Wyelie:BAABNQAECn8ZAAMVAAkK3gzePAANAQAVAAcKqQzePAANAQAGAAMK4QqpMAGjAAAAAA==.',
Xa='Xade:BAABNQAECn9RAAIOAAoKzR0zCgDSAgAOAAoKzR0zCgDSAgAAAA==.Xandendon:BAABNQAECn8XAAIJAAkKtw0KWACwAQAJAAkKtw0KWACwAQAAAA==.',
Xe='Xerond:BAABNQAECn8bAAIpAAgKZgVgIACpAAApAAgKZgVgIACpAAAAAA==.Xevin:BAABNQAECn8nAAIIAAoKoB0uOwCJAgAIAAoKoB0uOwCJAgAAAA==.',
Xo='Xotha:BAAANQAECgYIBgAAAA==.',
Ya='Yaákov:BAABNQAECn9BAAIZAAoK5xSjGwDMAQAZAAoK5xSjGwDMAQAAAA==.',
Yi='Yinosai:BAAANQADCgYICQAAAA==.',
Yo='Yougot:BAAANQADCggIDwAAAA==.',
Za='Zademedic:BAAANQAECgQIBgAAAA==.Zanarkin:BAAANQAECgEIAQAAAA==.Zanedore:BAAANQABCggIEwAAAA==.Zaranji:BAAANQADCgYIBgAAAA==.Zarisedra:BAACNQAFFH8SAAMCAAYKwAzeDAB8AQACAAYKwAzeDAB8AQAGAAEKcArgMwA9AAA1AAQKfy4AAwIACgoaHJcmAM8CAAIACgoaHJcmAM8CAAYAAwoMCUB6AUsAAAAA.Zarissena:BAABNQAECn8aAAIJAAgKwwSdTADSAAAJAAgKwwSdTADSAAAAAA==.Zarmina:BAAANQADCgEIAQAAAA==.Zarris:BAAANQABCgYIBAAAAA==.',
Ze='Zerdah:BAAANQADCgcIEwAAAA==.Zerogasm:BAAANQAECgMIAwAAAA==.Zerolicious:BAAANQAECgMJAwAAAA==.Zeroprophecy:BAAANQAECgIIAgAAAA==.Zevvo:BAABNQAECn8vAAIHAAoK1x7KPQBLAgAHAAoK1x7KPQBLAgAAAA==.',
Zo='Zoeybear:BAAANQAECgMIBAAAAA==.Zoraji:BAABNQAECn86AAIlAAoKIh7UAwBKAwAlAAoKIh7UAwBKAwAAAA==.',
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
