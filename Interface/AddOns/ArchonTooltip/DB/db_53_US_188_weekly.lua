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

local lookup = {'Warrior-Protection','Mage-Arcane','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Shaman-Elemental','DeathKnight-Unholy','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Druid-Balance','Paladin-Protection','Monk-Windwalker','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Guardian','Priest-Shadow','Shaman-Enhancement','Evoker-Devastation','Druid-Restoration','DeathKnight-Blood','Mage-Frost','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Frost','Mage-Fire','Priest-Discipline','Shaman-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Outlaw','Druid-Feral',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abrocklock:BAAANQADCgYICQAAAA==.',
Ad='Adorabull:BAABNQAECn8rAAIBAAkKDyGvBAA4AwABAAkKDyGvBAA4AwAAAA==.',
Ae='Aedreline:BAAANQADCggIFQABNQAECgoKJwACAMAOAA==.Aevelee:BAAANQAECgYIDwAAAA==.',
Al='Alari:BAAANQADCgYIBgAAAA==.Aleeta:BAAANQAECgQIBAAAAA==.Alleriae:BAAANQAECgMIAwAAAA==.Allucard:BAAANQAECggICAAAAA==.',
Am='Amaria:BAAANQAECgQIBwABNQAECgkJGgADAM4aAA==.',
An='Anaki:BAAANQADCgUIBQAAAA==.Anduîiîn:BAAANQADCggICgAAAA==.Angelusnox:BAAANQAECgEIAQAAAA==.Antarias:BAAANQAECgQIBgAAAA==.Anubiz:BAAANQADCgEIAQAAAA==.Anzhe:BAAANQAECgYIBgAAAA==.',
Ar='Araydin:BAAANQADCgEIAQAAAA==.Arckenon:BAACNQAFFH8GAAIEAAIKrwqXGQCAAAAEAAIKrwqXGQCAAAA1AAQKfzIAAgQACgrRHcc9ANwCAAQACgrRHcc9ANwCAAAA.Ardarl:BAAANQADCggICAAAAA==.Arranix:BAAANQADCgMIAwAAAA==.Arrica:BAAANQABCgUIBQAAAA==.Artemisv:BAAANQADCgIIAgAAAA==.Artorias:BAAANQADCggICAAAAA==.',
As='Ashog:BAAANQAECgIIAQAAAA==.',
At='Atillis:BAAANQAECgMIBAAAAA==.',
Au='Austenpally:BAABNQAECn8dAAMDAAgKRw53igB9AQADAAgKRw53igB9AQAEAAcKMg6xpgAIAQAAAA==.',
Av='Avarek:BAAANQADCgEIAQAAAA==.Aveycado:BAAANQAECgYIEwAAAA==.',
Ax='Axeflack:BAABNQAECn8uAAMBAAoK1BuPBABlAgABAAoK1BuPBABlAgAFAAUKMgf4/gDeAAAAAA==.Axegor:BAAANQAECgQIBwABNQAECgoKIQAGAM0bAA==.',
Az='Azaral:BAAANQADCgUJBQABNQAECggIGgAHAMMEAA==.Azmarija:BAAANQADCgEIAgAAAA==.',
Ba='Bacuda:BAAANQAECgUICQAAAA==.Batbane:BAAANQADCgYICAAAAA==.',
Bi='Biancadelrio:BAAANQAECgUIDQAAAA==.Bigguberment:BAAANQAECgQIDwAAAA==.',
Bl='Blackbird:BAABNQAECn8aAAMIAAkK3QaOEABiAQAIAAkK3QaOEABiAQAJAAYKsgSIFADmAAABNQAECgoKKAAKAC4aAA==.Bladekrim:BAAANQAECgEIAgAAAA==.Blindashunae:BAAANQADCgEIAQAAAA==.Blitzo:BAAANQADCgMIAwAAAA==.',
Bo='Boomhammer:BAAANQADCgYIBgAAAA==.Boredgored:BAAANQADCgcIBwABNQAECgoKKgACAHcXAA==.Botia:BAABNQAECn8VAAILAAgK4AKEiQCuAAALAAgK4AKEiQCuAAAAAA==.Bourdeaux:BAAANQADCgcIFQAAAA==.',
Br='Braedia:BAAANQABCgEIAQAAAA==.Brainnmatter:BAAANQADCgEIAQAAAA==.Brashmoore:BAAANQADCgMIAwAAAA==.Brizik:BAAANQABCgUIBQAAAA==.Brookshields:BAAANQAECgYICgAAAA==.Bruised:BAAANQAECgIIAgAAAA==.Brunae:BAABNQAECn8aAAIBAAcKwQ16FAD7AAABAAcKwQ16FAD7AAAAAA==.Brunnera:BAAANQADCggIDgAAAA==.Bruuenor:BAAANQAECgEIAQAAAA==.Bruul:BAABNQAECn8aAAQEAAYKZxJ/BgEUAQAEAAUKUg9/BgEUAQADAAMKigcd/gCAAAAMAAEKAAAMbQA4AAAAAA==.',
By='Bytour:BAAANQAECgUIBwABNQAFFAMIBQANAEUXAA==.',
Ca='Caenji:BAAANQAECgEIAQAAAA==.Captbenson:BAAANQADCgYIAQAAAA==.Carcharoth:BAAANQADCgMIAwAAAA==.Carmelina:BAAANQADCgQIBQAAAA==.Castanthrax:BAAANQADCgQIBAAAAA==.Cathryl:BAAANQADCgQIBAABNQAECgcIIQAOAIofAA==.',
Ch='Chadgar:BAABNQAECn8qAAICAAoKdxfEcACcAgACAAoKdxfEcACcAgAAAA==.Chaoshammer:BAAANQADCggICAAAAA==.Chey:BAABNQAECn9AAAMPAAoKBCSPEQCZAgAPAAoKRR6PEQCZAgAQAAYKDCR4FwA/AQAAAA==.Chipsahoy:BAAANQADCgEIAQAAAA==.Chormage:BAAANQABCgQIBQAAAA==.Chíef:BAAANQAFFAMIBAAAAA==.',
Cl='Clarke:BAAANQABCgEIAQAAAA==.Close:BAAANQADCgUIBQABNQAECggIDwARAAAAAA==.Clouds:BAAANQAECgIIAwABNQAECgQICQARAAAAAA==.',
Co='Conorix:BAAANQADCggIOgAAAA==.Corvo:BAAANQADCggICAABNQAECgcIIQAOAIofAA==.',
Cr='Crataxxis:BAABNQAECn8uAAMSAAoKmg2xIQCIAQASAAoKmg2xIQCIAQATAAEKAADOcwAnAAAAAA==.',
Cu='Cudara:BAAANQADCgIIAgABNQAECgUICQARAAAAAA==.Cupra:BAAANQADCgIIAgAAAA==.',
Cy='Cydon:BAABNQAECn8wAAIUAAgKrR5iCwC2AgAUAAgKrR5iCwC2AgAAAA==.Cythraul:BAABNQAECn8hAAIOAAcKih8FCAB8AgAOAAcKih8FCAB8AgAAAA==.',
Da='Daerith:BAAANQADCgYICgAAAA==.Daerrith:BAAANQADCgYJBgAAAA==.Dagni:BAAANQAECgEIAQAAAA==.Dantey:BAAANQADCgUIBQABNQAECgoKLQAVAAMdAA==.Darkveil:BAAANQADCgQIBAAAAA==.Darrwin:BAABNQAECn8WAAIEAAcKkxNi6wBFAQAEAAcKkxNi6wBFAQAAAA==.',
De='Deathspacito:BAAANQADCgMIAwAAAA==.Demonalsa:BAAANQADCgUIBQABNQAECggIGwAWABIVAA==.Derrith:BAAANQADCgUIBgAAAA==.Dezgra:BAAANQAECgcIDwAAAA==.',
Df='Dfabness:BAABNQAECn8jAAINAAkKSxJ0FwB9AQANAAkKSxJ0FwB9AQAAAA==.',
Do='Doomfury:BAAANQADCgEIAgAAAA==.Dotbush:BAAANQAECgQIBAABNQAFFAQIBwAEAAcDAA==.',
Dr='Dracthayr:BAABNQAECn82AAIXAAoKkgp7FwDSAQAXAAoKkgp7FwDSAQAAAA==.Dragonhammer:BAABNQAECn8fAAIEAAoKlBqwPQAEAgAEAAoKlBqwPQAEAgAAAA==.Dreaming:BAAANQAECggICAABNQAECggIDwARAAAAAA==.Drimclaw:BAAANQAECgIIAwAAAA==.Drubo:BAAANQAECgUICwAAAA==.Drx:BAABNQAECn8pAAQIAAcKiAhVGwDQAAAIAAcKiAhVGwDQAAAXAAQKRgnYLAC6AAAJAAEKrAZNJgArAAAAAA==.',
Du='Dukkelemon:BAAANQAECgQIBwAAAA==.',
Ed='Edenaza:BAAANQAECgQIBAAAAA==.',
El='Elanore:BAABNQAECn8oAAMKAAoKLhrYDAAXAwAKAAoKLhrYDAAXAwAVAAEKAAAPWwAAAAAAAA==.Elicithy:BAAANQABCgUIBQABNQAECggIGwAWABIVAA==.Elison:BAAANQAECgQIBAABNQAECggIGgAHAMMEAA==.Ellaini:BAAANQAECgQIBwAAAA==.Elliana:BAAANQAECgUIBwABNQAECgoKKAAKAC4aAA==.Ellie:BAAANQAECgEIAgABNQAECgoKLgADANwgAA==.Elloise:BAAANQADCgQIBQABNQAECgoKKAAKAC4aAA==.Elmichi:BAAANQAECgMIAQAAAA==.Elsae:BAABNQAECn8vAAIMAAoKCBNmIQDYAQAMAAoKCBNmIQDYAQAAAA==.Elseb:BAAANQADCgEIAQAAAA==.',
Ev='Evasion:BAABNQAFFH8FAAIQAAMKgQzKEADfAAAQAAMKgQzKEADfAAAAAA==.Everios:BAACNQAFFH8HAAIBAAQKLxT8AQDTAAABAAQKLxT8AQDTAAA1AAQKfywAAgEACgqaHzEIANECAAEACgqaHzEIANECAAAA.Evic:BAAANQADCgYICAAAAA==.Evielyn:BAAANQADCgUJBQABNQAECgoKKAAKAC4aAA==.',
Ex='Exodous:BAAANQABCgYIBAAAAA==.',
Fa='Faeleader:BAAANQAECgEIAQAAAA==.Faevelina:BAAANQAECgEIAQABNQAECgcIDwARAAAAAA==.Faytadori:BAABNQAECn87AAMLAAoKIxgGFQABAgALAAoKIxgGFQABAgAYAAMKjglsYwB4AAAAAA==.',
Fe='Felgrrl:BAAANQADCggIPgAAAA==.Feyreh:BAAANQAECgIIBAAAAA==.',
Fi='Fidget:BAABNQAECn8iAAIQAAgKgwlxEgBrAQAQAAgKgwlxEgBrAQAAAA==.',
Fl='Fletch:BAABNQAECn8WAAIFAAkKFQW4zwBUAQAFAAkKFQW4zwBUAQAAAA==.',
Fo='Forever:BAAANQAECggIDwAAAA==.',
Fr='Frahra:BAAANQAECgIIAgAAAA==.Frique:BAAANQAECgQIBQAAAA==.Frozenyogert:BAAANQAECgQICQAAAA==.',
Ga='Galbur:BAACNQAFFH8HAAMZAAQKZwxXFQBtAAAZAAIKxxFXFQBtAAAHAAIKpgGoDgBAAAA1AAQKfy0AAxkACgqFFWYtAGACABkACQpJFmYtAGACAAcACQoFE9wlAEkBAAAA.Galdrin:BAAANQAECgcIDwAAAA==.Gaspode:BAAANQADCgYICwAAAA==.Gassann:BAABNQAECn8ZAAIEAAgKWBa5rgDCAQAEAAgKWBa5rgDCAQAAAA==.',
Ge='Geers:BAABNQAECn8mAAIaAAoK/iIkAQCRAwAaAAoK/iIkAQCRAwAAAA==.Geta:BAAANQAECgYICQABNQAECgoKLQAFAAIhAA==.Getabrew:BAAANQAECgYICQABNQAECgoKLQAFAAIhAA==.Getacurse:BAAANQAECgUIBQABNQAECgoKLQAFAAIhAA==.Getagrip:BAAANQADCgIIAgABNQAECgoKLQAFAAIhAA==.Getalife:BAAANQAECgEIAQABNQAECgoKLQAFAAIhAA==.Getarage:BAABNQAECn8tAAMFAAoKAiEQEQDcAgAFAAoKLiAQEQDcAgABAAMKsx+YJQAXAQAAAA==.Getasoar:BAAANQADCgQIBgABNQAECgoKLQAFAAIhAA==.Getastab:BAAANQAECggIEAABNQAECgoKLQAFAAIhAA==.',
Gh='Ghil:BAABNQAECn8dAAQbAAoKrRdVAwDIAgAbAAkKoRhVAwDIAgAcAAMKtAseYQBjAAAdAAEKMw/vPQE6AAAAAA==.',
Gi='Gildersleeve:BAAANQAECgUIBgAAAA==.Gilia:BAAANQAECgIIBAAAAA==.Gimlí:BAAANQADCgEIAQAAAA==.',
Gl='Glynix:BAAANQAECgIIBAAAAA==.',
Gn='Gnosher:BAAANQAECgYIDgAAAA==.',
Go='Goku:BAABNQAECn8oAAQNAAkK3RJCLQCvAQANAAkK3RJCLQCvAQAeAAYK8QwPHQAXAQAfAAEKsgUIVAAiAAAAAA==.Goldiwarlock:BAAANQADCgUIBwAAAA==.Goloron:BAAANQAECgQIBAAAAA==.Gornub:BAAANQADCgYIBgAAAA==.Gorzok:BAAANQABCgEIAQAAAA==.',
Gr='Graymayn:BAAANQAECgUICgAAAA==.Grekk:BAAANQAECgMIAwAAAA==.Grelldar:BAAANQADCgEIAQAAAA==.Grimflaps:BAABNQAECn8jAAMXAAcKbQ1vDQADAQAXAAcKbQ1vDQADAQAIAAUKSwRZOwC+AAAAAA==.',
Gu='Gunderthirth:BAACNQAFFH8NAAIBAAYKqxy2AAApAgABAAYKqxy2AAApAgA1AAQKfyAAAgEACgooIyUDAHIDAAEACgooIyUDAHIDAAAA.Guulfang:BAAANQADCgMIAwAAAA==.',
Gw='Gwaeniiha:BAABNQAECn8iAAIEAAcK4woVrwD5AAAEAAcK4woVrwD5AAAAAA==.',
Ha='Haan:BAAANQADCgYIBgAAAA==.Haliran:BAAANQAECgQIBQAAAA==.Handsoap:BAABNQAECn8cAAISAAcKFgm7TgBgAQASAAcKFgm7TgBgAQAAAA==.Harakhty:BAAANQAECgUICQAAAA==.Hardhitter:BAABNQAECn88AAMBAAoK2xbsDwArAgABAAoK2xbsDwArAgAFAAgKWg7SrACtAQAAAA==.',
He='Hellstorm:BAAANQABCgYICAAAAA==.Hellumph:BAABNQAECn8hAAIOAAoKpBHYBgCaAQAOAAoKpBHYBgCaAQAAAA==.Hevensdemon:BAAANQAECgYIBwAAAA==.Hevensrath:BAABNQAECn8rAAMEAAoKzhwyNwAcAgAMAAoKuxh7FABgAgAEAAoKmxgyNwAcAgAAAA==.Hevensreaper:BAAANQAECgYIEgAAAA==.Hevensvoid:BAAANQAECggICAAAAA==.Hevshaolin:BAAANQAECgUIBQAAAA==.Hexhorn:BAAANQADCggJDgAAAA==.Hextermorgan:BAAANQABCggIEAABNQAECgoKMgAgAF4bAA==.',
Ho='Hokuden:BAABNQAECn83AAIgAAoKxRQ8MAAkAgAgAAoKxRQ8MAAkAgAAAA==.Holphie:BAAANQAECggICwAAAA==.Holyholyholy:BAAANQADCggICAAAAA==.Horsebananas:BAAANQAECgcICgAAAA==.',
Hu='Huddington:BAABNQAECn8aAAICAAcKEQ3wngAIAQACAAcKEQ3wngAIAQAAAA==.',
Hy='Hyperion:BAAANQAECgQIBwABNQAECgcIIQAOAIofAA==.',
Ig='Igknight:BAAANQAECgYICgABNQAECgoKKAADAPEQAA==.',
Il='Ilsi:BAAANQADCgYIBgABNQAECgoKIQAGAM0bAA==.',
Im='Impthrower:BAAANQAECgIIAgABNQADCgYJDwARAAAAAA==.',
In='Indecent:BAABNQAECn8oAAMdAAoKoxlxIwAsAgAdAAoKYxlxIwAsAgAcAAIKHxusTQCWAAAAAA==.Indeed:BAAANQAECggICAAAAA==.Inibble:BAAANQABCgUICAAAAA==.',
Iq='Iqfbeef:BAAANQADCgYICgAAAA==.',
Is='Ishy:BAABNQAECn8wAAMCAAkK7xosZgCyAgACAAkK7xosZgCyAgAhAAMKLAuXBAB1AAAAAA==.',
Iw='Iwannalive:BAAANQADCgIIAgAAAA==.',
Iz='Izziey:BAAANQADCgEIAQAAAA==.',
Ja='Jack:BAABNQAECn8kAAQVAAoKNRlkIgAhAgAVAAgKQxZkIgAhAgAKAAcKqhDVjwBnAQAiAAMKURWSFwC5AAAAAA==.Jackieblaze:BAAANQAECgUICgABNQAFFAQIBwAVAKULAA==.Jackieplays:BAACNQAFFH8HAAQVAAQKpQs/CwCQAAAVAAIK5Ak/CwCQAAAiAAIK7QvdAgCIAAAKAAEK0hcmJQBSAAA1AAQKfzUABCIACgo5IF8DAL4CACIACAqNHl8DAL4CAAoACgqiHMs5AIICABUAAQo2DCp6ADQAAAAA.Jaded:BAABNQAECn8uAAMjAAoKsRySEADOAgAjAAoKsRySEADOAgAGAAMKjwrPAAGPAAAAAA==.',
Je='Jeses:BAAANQAECgcIDgAAAA==.',
Jo='Jollah:BAAANQAECgYIEQAAAA==.Jorawa:BAAANQAECgQIBAAAAA==.',
Ju='Jurassic:BAAANQADCgYIBgAAAA==.Jutic:BAABNQAECn84AAIjAAoKTiMoDQBXAwAjAAoKTiMoDQBXAwAAAA==.',
Ka='Kageken:BAAANQADCgQIBAABNQADCgYJEQARAAAAAA==.Kaithul:BAAANQABCgQIAwAAAA==.Kardas:BAABNQAECn8hAAIkAAgKuAhQugCPAQAkAAgKuAhQugCPAQAAAA==.',
Kb='Kbilly:BAABNQAECn8zAAIjAAoKCB2uIADnAgAjAAoKCB2uIADnAgAAAA==.',
Ke='Kentarou:BAAANQABCgUIBQAAAA==.Keylerin:BAACNQAFFH8PAAIPAAYKahadBgBDAQAPAAYKahadBgBDAQA1AAQKfykAAg8ACgqJHjwIAPYCAA8ACgqJHjwIAPYCAAAA.',
Ki='Kitto:BAAANQADCgYJBgAAAA==.Kittvulpy:BAAANQADCgYICgAAAA==.',
Kl='Klausinator:BAAANQADCggIDAAAAA==.',
Kn='Knottes:BAAANQABCggIIwAAAA==.',
Ko='Komos:BAAANQAECgEIAQAAAA==.',
Kr='Krampus:BAABNQAECn8rAAIWAAoKbQrDDQC0AQAWAAoKbQrDDQC0AQAAAA==.Kranok:BAABNQAECn8aAAIlAAcK0A8wHwADAQAlAAcK0A8wHwADAQAAAA==.Krennthis:BAAANQAECgMIAwAAAA==.Krimbruiser:BAAANQADCgYIBwABNQAECgEIAgARAAAAAA==.Krimhuntress:BAAANQADCgYIBgAAAA==.',
Ku='Kunac:BAAANQADCgYIEAAAAA==.',
Ky='Kyran:BAAANQADCgUIBwAAAA==.Kyrun:BAAANQAECgYIDwAAAA==.Kytrina:BAAANQADCgIIAgAAAA==.',
La='Lactoes:BAAANQADCgYIBgAAAA==.Lamoran:BAAANQAECgUICQAAAA==.',
Le='Lemón:BAAANQAECgEIAQAAAA==.',
Lh='Lhani:BAABNQAECn8iAAIKAAgKnBL2QwCiAQAKAAgKnBL2QwCiAQAAAA==.',
Li='Lilguysci:BAAANQAECgMIBAAAAA==.Lizord:BAAANQAECggIDgAAAA==.',
Ll='Llothien:BAAANQAECgIIAgAAAA==.Llyrael:BAABNQAECn8pAAMKAAkKzgRjdwDwAAAKAAkKzgRjdwDwAAAVAAEK2gILhAAlAAAAAA==.',
Lo='Lonard:BAAANQAECgIIAgAAAA==.',
Lu='Lugosi:BAAANQAECgEIAQAAAA==.',
Ly='Lyfe:BAAANQABCgUIBwAAAA==.',
Ma='Machlain:BAAANQADCgQIBAABNQAECggIIQAMAAkcAA==.Maddeleine:BAAANQADCgYIEwAAAA==.Magara:BAAANQAECgQIBAAAAA==.Magicdemon:BAABNQAECn8xAAISAAoKNCT+BgDqAgASAAoKNCT+BgDqAgAAAA==.Magichunter:BAAANQAECgcICAABNQAECgoKMQASADQkAA==.Magicpaladin:BAAANQAECgcIBwABNQAECgoKMQASADQkAA==.Magicshaman:BAAANQAECgQIBQABNQAECgoKMQASADQkAA==.Makall:BAAANQABCgQIBAAAAA==.Malaah:BAABNQAECn8hAAIGAAgKPA/0dwC6AQAGAAgKPA/0dwC6AQAAAA==.Mansuno:BAABNQAECn8uAAMEAAkKxRb0YAB3AgAEAAkKxRb0YAB3AgADAAUK/gvubgD1AAAAAA==.Mapachote:BAABNQAECn8ZAAIlAAYKKRKKGgAvAQAlAAYKKRKKGgAvAQAAAA==.Marodin:BAAANQADCggIOwAAAA==.Maynor:BAAANQABCggIFQAAAA==.Mazboda:BAABNQAECn8tAAQdAAcKShjiXgBHAQAdAAcKzRfiXgBHAQAbAAIKFRkXHgCKAAAcAAIKugg3ZABcAAAAAA==.',
Me='Meatbaal:BAAANQAECgUIDQAAAA==.Medïc:BAAANQADCggICAAAAA==.Melinaria:BAABNQAECn8lAAMVAAgKdBclJgD9AQAVAAgKdBclJgD9AQAiAAEK2w6wDwBAAAAAAA==.Merewene:BAAANQAECgUICgAAAA==.Merkabai:BAAANQADCgIIAgAAAA==.',
Mi='Mileta:BAABNQAECn8tAAILAAoKPhrTHADiAgALAAoKPhrTHADiAgAAAA==.Minuette:BAAANQAECgMIAwAAAA==.',
Mo='Montblanc:BAAANQAECgQIBAABNQAECgUICgARAAAAAA==.Morgnox:BAAANQAECgIIAgAAAA==.',
Mu='Murdercookie:BAAANQAECgEIAQAAAA==.',
Na='Nazgul:BAAANQADCgcICAAAAA==.',
Ne='Necronic:BAAANQAECgIIAwAAAA==.Necroreign:BAABNQAECn85AAISAAoKuBhXEQA3AgASAAoKuBhXEQA3AgAAAA==.Need:BAAANQAECgIIAgAAAA==.Neherenia:BAABNQAECn8pAAIgAAkKiBM+IwCzAQAgAAkKiBM+IwCzAQAAAA==.Nervous:BAAANQAECggIAgABNQAECggIDwARAAAAAA==.Nessee:BAABNQAECn8UAAIaAAUKugziHgDzAAAaAAUKugziHgDzAAAAAA==.',
Ni='Niall:BAAANQAECgEIAgAAAA==.Nightfire:BAAANQABCgcIEwAAAA==.Nihowdy:BAABNQAECn81AAImAAoKayBXAQB/AwAmAAoKayBXAQB/AwAAAA==.',
No='Norrin:BAAANQABCggIDgAAAA==.',
Oc='Octalexane:BAAANQADCgYIBgABNQAECgcIGgABAMENAA==.',
On='Onimusha:BAAANQAECgEIAQAAAA==.',
Or='Orci:BAABNQAECn8kAAIcAAcKKg1jCADnAAAcAAcKKg1jCADnAAAAAA==.Orryn:BAAANQABCgIIAgAAAA==.Ortalbem:BAABNQAECn8+AAMCAAoK1BulVwDRAgACAAoKwhmlVwDRAgAaAAgK0xsCGAA5AQAAAA==.',
Ou='Oulli:BAAANQABCggIHwAAAA==.',
Ov='Ovi:BAAANQAECgUICwAAAA==.',
Pa='Painthuffer:BAABNQAECn8YAAMQAAoKphJ7MAAgAgAQAAoK9xB7MAAgAgAPAAYKoA8aSgA1AQABNQAECgoKKgACAHcXAA==.Pazuuzu:BAAANQAECgEIAQAAAA==.',
Pe='Peddles:BAAANQAECgUICQAAAA==.Petmedaddy:BAAANQABCgEIAQAAAA==.',
Ph='Pherix:BAABNQAECn8tAAIVAAoKAx1QEgDbAgAVAAoKAx1QEgDbAgAAAA==.Philipfry:BAABNQAECn88AAMDAAoKaxkBTgAyAgADAAgKBhcBTgAyAgAEAAcK7RX1ZwCHAQAAAA==.Phill:BAAANQADCgcIEAAAAA==.',
Pl='Plaguetusk:BAAANQADCgQIBAAAAA==.',
Po='Poomacha:BAAANQAECgQIEAAAAA==.Potatopants:BAAANQADCgQIBQAAAA==.',
Pr='Prinlina:BAAANQADCggIDQAAAA==.',
Py='Pyree:BAABNQAECn8qAAIXAAoKEAw2CQBnAQAXAAoKEAw2CQBnAQAAAA==.',
Ra='Radimus:BAAANQAECgEIAQAAAA==.Raenne:BAAANQADCgMIAwAAAA==.Rainvelle:BAAANQADCgQIBAAAAA==.Raistlain:BAABNQAECn8fAAIVAAgKwRQKJgD+AQAVAAgKwRQKJgD+AQAAAA==.Ralli:BAABNQAECn8sAAMSAAoKYR29FgDmAgASAAkKxBq9FgDmAgATAAkKYxo5FwCBAQAAAA==.Ralls:BAAANQADCgUIBQABNQAECgYIDAARAAAAAA==.Rallsdk:BAAANQADCgYIBgABNQAECgYIDAARAAAAAA==.Rallsodins:BAAANQAECgYIDAAAAA==.Ranulf:BAAANQAECgQICwAAAA==.Ratava:BAAANQAECgYIDwAAAA==.Ratrot:BAAANQADCggICQAAAA==.Raztar:BAAANQADCgUIBQAAAA==.',
Re='Reddemon:BAAANQAECggIEgAAAA==.Rekarra:BAAANQADCgcIBwAAAA==.Reks:BAAANQAECgQIBAAAAA==.Reldarus:BAEBNQAECn8rAAQiAAoKQCH4AgDVAgAiAAcK1CP4AgDVAgAKAAoKFhplSQBKAgAVAAEK9BWCcABHAAAAAA==.Rena:BAABNQAECn8qAAQXAAoKKhJ1DQADAQAXAAcKJwp1DQADAQAIAAMKywNeIwB9AAAJAAQKxQNkHQB5AAAAAA==.Revilation:BAABNQAECn8iAAIMAAkK8RPrHAAEAgAMAAkK8RPrHAAEAgAAAA==.Rezjyk:BAAANQADCgYIBgABNQAECggILwAEAKYbAA==.Rezzyk:BAABNQAECn8vAAIEAAgKphvHTQDNAQAEAAgKphvHTQDNAQAAAA==.',
Rh='Rhyxali:BAAANQAECgUIEQAAAA==.',
Ri='Riibirth:BAAANQADCgYIBgAAAA==.Riis:BAAANQADCgEIAQAAAA==.',
Ry='Rygelon:BAAANQAECgQICQAAAA==.',
Sa='Sableanne:BAAANQABCgYIDQAAAA==.Sacredscales:BAAANQADCgMJAwAAAA==.Samvimes:BAAANQAECgIIBQAAAA==.Sangreene:BAABNQAECn8nAAIVAAoKOReZCwAvAgAVAAoKOReZCwAvAgAAAA==.Sargis:BAABNQAECn87AAMEAAoKoh0rHgCYAgAEAAoKoh0rHgCYAgADAAgKXBJuaADeAQAAAA==.',
Sc='Schrödinger:BAAANQADCggIGAABNQAECgcIIQAOAIofAA==.Scott:BAAANQAECgQIBAAAAA==.',
Se='Serissa:BAAANQAECgEIAQAAAA==.Serjankins:BAAANQADCgQIBAAAAA==.Setsuna:BAAANQABCgYIDAABNQAECgoKIAAVAGYeAA==.',
Sh='Shadowbrooks:BAAANQADCgIIAgAAAA==.Shadowgiver:BAAANQADCgcICwAAAA==.Shagol:BAABNQAECn8bAAIKAAYKbhjkjABvAQAKAAYKbhjkjABvAQAAAA==.Shaidic:BAAANQAECgQIBAAAAA==.Shamemoon:BAAANQAECgEJAQABNQAECgYIDgARAAAAAA==.Shamunroe:BAABNQAECn8sAAMGAAoK8hIoNACGAQAGAAoK8hIoNACGAQAjAAUK1Aow1gC6AAAAAA==.Shatterhoof:BAAANQAECgUIDQAAAA==.Shelle:BAAANQAECgIIAgAAAA==.Shiftysmage:BAAANQAECgEIAQABNQAECgoKFgALAMAOAA==.Shingra:BAACNQAFFH8LAAIJAAQKEhMCBwD3AAAJAAQKEhMCBwD3AAA1AAQKfxwAAgkACQomFDoGAGoCAAkACQomFDoGAGoCAAAA.Shores:BAAANQABCgIIAQAAAA==.Shylindra:BAAANQAECgMIAwAAAA==.',
Si='Sigourney:BAAANQAECgYIDwABNQAECgcICgARAAAAAA==.Silversho:BAAANQAECgMIAwAAAA==.Silvren:BAAANQADCgIIAgAAAA==.',
Sk='Skill:BAABNQAECn8cAAMYAAgKghKIKgDKAQAYAAgKghKIKgDKAQALAAQKRw6wegDgAAAAAA==.',
Sl='Slighttrash:BAAANQAECgUIDAAAAA==.',
Sm='Smallcrow:BAABNQAECn8bAAMNAAkKbR40FwCSAgANAAgKbR40FwCSAgAfAAQK0Q1HMwDQAAAAAA==.',
So='Somdot:BAEBNQAECn9GAAIVAAoKfSBpCABWAwAVAAoKfSBpCABWAwAAAA==.Somedeekay:BAAANQAECgYIDgAAAA==.',
Sp='Spirit:BAABNQAECn8VAAMIAAgKFRrtEQCNAgAIAAgKFRrtEQCNAgAXAAEKCwjLQQAmAAABNQAFFAMIBQAQAIEMAA==.',
Sq='Squirrellock:BAAANQAECgEIAgAAAA==.',
St='Starga:BAAANQADCgQIBAAAAA==.Starge:BAAANQADCgUIBQAAAA==.Starre:BAAANQADCgQIBAAAAA==.Steffey:BAAANQAECgYIDAAAAA==.Stepbro:BAAANQADCgcIDAAAAA==.Stoikk:BAABNQAECn8UAAIGAAcK3hCPkQB4AQAGAAcK3hCPkQB4AQAAAA==.Straven:BAAANQAECgcIEgAAAA==.Sturgeson:BAACNQAFFH8VAAIBAAYKqxnMAABCAQABAAYKqxnMAABCAQA1AAQKfygAAgEACQoIIW4JALUCAAEACQoIIW4JALUCAAAA.',
Su='Suffocation:BAEANQAECgYIBgABNQAFFAgIIQAcAHMeAA==.Sulwen:BAABNQAECn8hAAIKAAgKqBTLXgAFAgAKAAgKqBTLXgAFAgAAAA==.Sundance:BAAANQADCgUIBQAAAA==.Sunray:BAAANQAECgYIBQAAAA==.',
Sw='Swiftfeet:BAABNQAECn8lAAIkAAkKuxXjawBhAQAkAAkKuxXjawBhAQAAAA==.',
['Sé']='Sésho:BAAANQADCgQIBgAAAA==.',
['Sö']='Söranin:BAAANQAECgMIBAAAAA==.',
['Sø']='Sømdøt:BAEANQAECggIDAABNQAECgoKRgAVAH0gAA==.',
Ta='Taeili:BAABNQAECn8cAAIUAAgK1BY6FwD5AQAUAAgK1BY6FwD5AQAAAA==.Taeror:BAAANQADCgQIBAAAAA==.Tanequil:BAACNQAFFH8HAAIYAAQKBgMUCADeAAAYAAQKBgMUCADeAAA1AAQKfy4AAhgACgoNDPspAM8BABgACgoNDPspAM8BAAAA.',
Te='Techromancer:BAABNQAECn8iAAMHAAoKeRYpKgCPAgAHAAoKeRYpKgCPAgAgAAMKtRFLbgB1AAABNQAECgoKLQAVAAMdAA==.Tem:BAAANQABCgQIBAABNQADCgcIDgARAAAAAA==.',
Th='Thanatias:BAAANQAECgcIBgAAAA==.Thantasia:BAAANQAECgMIAgAAAA==.Theakunda:BAAANQAECgcIDwAAAA==.Theodis:BAAANQAECgQIBAAAAA==.Thokdar:BAAANQAECgQIBQAAAA==.',
Ti='Tifà:BAAANQAECgIIAgAAAA==.Tillago:BAAANQADCggICgAAAA==.Timothy:BAAANQAECgUICAAAAA==.Timothyjohn:BAAANQAECgYIDwAAAA==.Tinkphooey:BAAANQAECgMIBAAAAA==.Tirianna:BAAANQADCgEIAQABNQAECgoKKAAKAC4aAA==.Tituba:BAABNQAECn8zAAIdAAoK0xlbQgCLAgAdAAoK0xlbQgCLAgAAAA==.',
To='Toklore:BAAANQADCgcIDgAAAA==.Tonepavone:BAAANQADCgYIBgAAAA==.Tormmok:BAAANQADCgQIBAAAAA==.',
Tr='Traazz:BAAANQADCgYICgAAAA==.Trey:BAAANQAECgUIBgAAAA==.Trior:BAAANQAECgQIBQAAAA==.',
Ts='Tsuruga:BAABNQAECn8jAAIeAAoKRwWsCQA+AQAeAAoKRwWsCQA+AQAAAA==.',
Tu='Turkwise:BAABNQAECn83AAQUAAgKRBBsIwB7AQAUAAcK4Q9sIwB7AQAnAAcKqw2AHAA+AQAYAAQKwgSlSQBnAAAAAA==.',
Ul='Ulodude:BAAANQADCgYIBgAAAA==.',
Un='Unholydiddy:BAAANQADCgEIAQAAAA==.',
Ur='Urobolos:BAAANQAECgMIAwAAAA==.',
Uv='Uvari:BAAANQAECgYIEAAAAA==.',
Va='Vacalaca:BAAANQAECgYIDgAAAA==.Valany:BAAANQADCgIIAgAAAA==.Valkira:BAACNQAFFH8HAAIWAAQKlgydAgDcAAAWAAQKlgydAgDcAAA1AAQKfy4AAxYACgq3HCIPAHgCABYACgrWGyIPAHgCAAYABgpxGVSLAIgBAAAA.Valton:BAACNQAFFH8FAAINAAMKRReoBgDTAAANAAMKRReoBgDTAAA1AAQKfzoAAg0ACgp0JcEDAJkDAA0ACgp0JcEDAJkDAAAA.Vancede:BAAANQAECgQIBAABNQAECggIHwATAJ8UAA==.Vanillanice:BAAANQADCgMJBAAAAA==.Varrfife:BAAANQABCgIJAgAAAA==.Vaxaldan:BAABNQAECn8rAAIZAAoKrgziIACMAQAZAAoKrgziIACMAQAAAA==.',
Ve='Velindsong:BAAANQADCggICAAAAA==.Venj:BAAANQAECgIIAgAAAA==.Ventosa:BAACNQAFFH8HAAIjAAQKsQq+DgD0AAAjAAQKsQq+DgD0AAA1AAQKfzAAAiMACgrXGhg6AHYCACMACgrXGhg6AHYCAAAA.Vex:BAAANQAECgIIAgAAAA==.',
Vi='Vilox:BAAANQADCgIIAgAAAA==.Viltex:BAAANQADCgYICwAAAA==.Vilxten:BAAANQAECgUICQAAAA==.',
Vo='Voidleader:BAABNQAECn8eAAIKAAgKLBAKXQBCAQAKAAgKLBAKXQBCAQAAAA==.Vostok:BAABNQAECn8lAAIdAAgKuRDujADHAQAdAAgKuRDujADHAQAAAA==.',
Vy='Vylleria:BAAANQADCgYIBgAAAA==.',
['Vá']='Váyne:BAAANQAECgEIAQABNQAECgYICwARAAAAAA==.',
Wa='Warralok:BAAANQADCgYIBgAAAA==.Warramag:BAAANQAECgYICgAAAA==.Warranni:BAABNQAECn8rAAIGAAoKlhquKADeAgAGAAoKlhquKADeAgAAAA==.',
We='Weekend:BAABNQAECn8mAAIGAAoK7g/sKQC6AQAGAAoK7g/sKQC6AQAAAA==.',
Wh='Whatafox:BAABNQAECn8kAAMGAAkKjxxpTABFAgAGAAcKRB1pTABFAgAjAAYKEBAC1QC9AAAAAA==.Whittail:BAAANQABCggIFgAAAA==.',
Wi='Wikket:BAABNQAECn8wAAILAAoKbA8DGwC2AQALAAoKbA8DGwC2AQAAAA==.',
Wo='Wortel:BAAANQADCgYIBgAAAA==.',
Wy='Wyelie:BAABNQAECn8WAAIMAAcKqQzePAANAQAMAAcKqQzePAANAQAAAA==.',
Xa='Xade:BAABNQAECn86AAIPAAoKzR0zCgDSAgAPAAoKzR0zCgDSAgAAAA==.Xandendon:BAABNQAECn8XAAIHAAkKtw0KWACwAQAHAAkKtw0KWACwAQAAAA==.',
Xe='Xerond:BAAANQAECgUIDAAAAA==.Xevin:BAABNQAECn8hAAIGAAoKzRsuOwCJAgAGAAoKzRsuOwCJAgAAAA==.',
Xo='Xotha:BAAANQAECgQIBAAAAA==.',
Ya='Yaákov:BAABNQAECn8sAAITAAkKKhcoFACrAQATAAkKKhcoFACrAQAAAA==.',
Yi='Yinosai:BAAANQADCgYICQAAAA==.',
Yo='Yougot:BAAANQADCggIDwAAAA==.',
Za='Zademedic:BAAANQAECgQIBgAAAA==.Zanarkin:BAAANQAECgEIAQAAAA==.Zanedore:BAAANQABCggIEwAAAA==.Zaranji:BAAANQADCgYIBgAAAA==.Zarisedra:BAACNQAFFH8SAAMDAAYKwAyuBgCUAQADAAYKwAyuBgCUAQAEAAEKcAqyIwBAAAA1AAQKfysAAwMACgp0GpcmAM8CAAMACgp0GpcmAM8CAAQAAQoAAAjeARIAAAAA.Zarissena:BAABNQAECn8aAAIHAAgKwwS/NwDeAAAHAAgKwwS/NwDeAAAAAA==.Zarmina:BAAANQADCgEIAQAAAA==.Zarris:BAAANQABCgYIBAAAAA==.',
Ze='Zerdah:BAAANQADCgcIEwAAAA==.Zerogasm:BAAANQAECgMIAwAAAA==.Zerolicious:BAAANQAECgMJAwAAAA==.Zeroprophecy:BAAANQAECgIIAgAAAA==.Zevvo:BAABNQAECn8oAAIFAAoKWhvkMgAKAgAFAAoKWhvkMgAKAgAAAA==.',
Zo='Zoeybear:BAAANQAECgMIBAAAAA==.Zoraji:BAABNQAECn8xAAIeAAoKfB3UAwBKAwAeAAoKfB3UAwBKAwAAAA==.',
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
