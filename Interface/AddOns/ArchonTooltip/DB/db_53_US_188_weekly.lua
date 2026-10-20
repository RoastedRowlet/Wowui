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

local lookup = {'Warrior-Protection','Mage-Arcane','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Shaman-Elemental','DeathKnight-Unholy','Unknown-Unknown','Paladin-Protection','Monk-Windwalker','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Guardian','Shaman-Enhancement','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Priest-Shadow','Druid-Balance','Druid-Restoration','DeathKnight-Blood','Mage-Frost','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Frost','Mage-Fire','Priest-Discipline','Shaman-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Outlaw','Druid-Feral',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abrocklock:BAAANQADCgYICQAAAA==.',
Ad='Adorabull:BAABNQAECn8kAAIBAAkKFiCvBAA4AwABAAkKFiCvBAA4AwAAAA==.',
Ae='Aedreline:BAAANQADCggIEAABNQAECggIHwACAGEMAA==.Aevelee:BAAANQAECgUIDwAAAA==.',
Al='Alari:BAAANQADCgYIBgAAAA==.Aleeta:BAAANQAECgQIBQAAAA==.Alleriae:BAAANQAECgMIAwAAAA==.Allucard:BAAANQAECggIBAAAAA==.',
Am='Amaria:BAAANQAECgQIBwABNQAECgkJGgADAM4aAA==.',
An='Anaki:BAAANQADCgUIBQAAAA==.Anduîiîn:BAAANQADCggICgAAAA==.Angelusnox:BAAANQAECgEIAQAAAA==.Antarias:BAAANQAECgQICQAAAA==.Anubiz:BAAANQADCgEIAQAAAA==.',
Ar='Araydin:BAAANQADCgEIAQAAAA==.Arckenon:BAABNQAECn8uAAIEAAoK0R3HPQDcAgAEAAoK0R3HPQDcAgAAAA==.Ardarl:BAAANQADCggICAAAAA==.Arranix:BAAANQADCgMIAwAAAA==.Arrica:BAAANQABCgUIBQAAAA==.Artemisv:BAAANQADCgIIAgAAAA==.',
As='Ashog:BAAANQAECgIIAQAAAA==.',
At='Atillis:BAAANQAECgMIBQAAAA==.',
Au='Austenpally:BAABNQAECn8XAAMDAAgKRw53igB9AQADAAgKRw53igB9AQAEAAUKHA5ADQEJAQAAAA==.',
Av='Avarek:BAAANQADCgEIAQAAAA==.Aveycado:BAAANQAECgYIEwAAAA==.',
Ax='Axeflack:BAABNQAECn8gAAMBAAoKSRnFBACGAQABAAoKSRnFBACGAQAFAAUKMgf4/gDeAAAAAA==.Axegor:BAAANQAECgQICgABNQAECgkJHgAGAMMbAA==.',
Az='Azaral:BAAANQADCgUJBQABNQAECggIFwAHABcEAA==.Azmarija:BAAANQADCgEIAgAAAA==.',
Ba='Bacuda:BAAANQAECgUICQAAAA==.Batbane:BAAANQADCgYICAAAAA==.',
Bi='Biancadelrio:BAAANQAECgQIDAAAAA==.Bigguberment:BAAANQAECgUIEAAAAA==.Bigsneaky:BAAANQAECgEIAQABNQAECgYIDwAIAAAAAA==.',
Bl='Blackbird:BAAANQAECgYICQABNQAECgIIAgAIAAAAAA==.Bladekrim:BAAANQAECgIIAgAAAA==.Blindashunae:BAAANQADCgEIAQAAAA==.Blitzo:BAAANQADCgMIAwAAAA==.',
Bo='Boomhammer:BAAANQAECgEIAQAAAA==.Boredgored:BAAANQADCgcIBwABNQAECgoKJAACAIIVAA==.Botia:BAAANQAECgYIEgAAAA==.Bourdeaux:BAAANQADCgcIFQAAAA==.',
Br='Braedia:BAAANQAECgEIAgAAAA==.Brainnmatter:BAAANQADCgEIAQAAAA==.Brashmoore:BAAANQADCgMIAwAAAA==.Brizik:BAAANQABCgUIBQAAAA==.Brookshields:BAAANQAECgYICgAAAA==.Bruised:BAAANQAECgIIBAAAAA==.Brunae:BAABNQAECn8UAAIBAAcK2Qr3IQA7AQABAAcK2Qr3IQA7AQAAAA==.Brunnera:BAAANQADCggIDgAAAA==.Bruuenor:BAAANQAECgEIAwAAAA==.Bruul:BAABNQAECn8aAAQEAAYKZxJ/BgEUAQAEAAUKUg9/BgEUAQADAAMKigcd/gCAAAAJAAEKAAAMbQA4AAAAAA==.',
By='Bytour:BAAANQAECgUIBwABNQAFFAMIBQAKAEUXAA==.',
Ca='Caenji:BAAANQAECgEIAQAAAA==.Captbenson:BAAANQADCgYIAQAAAA==.Carcharoth:BAAANQADCgMIAwAAAA==.Carmelina:BAAANQADCgQIBQAAAA==.Castanthrax:BAAANQADCgQIBAAAAA==.Cathryl:BAAANQADCgQIBAABNQAECgcIGwALADYfAA==.',
Ch='Chadgar:BAABNQAECn8kAAICAAoKghXEcACcAgACAAoKghXEcACcAgAAAA==.Chaoshammer:BAAANQADCggICAAAAA==.Chey:BAABNQAECn80AAMMAAoKACQVEABEAQANAAUKOSR+HgDdAQAMAAYKDCQVEABEAQAAAA==.Chipsahoy:BAAANQADCgEIAQAAAA==.Chormage:BAAANQABCgQIBQAAAA==.Chíef:BAAANQAFFAEIAQABNQAFFAQIDgAOACMSAA==.',
Cl='Clarke:BAAANQAECgEIAQAAAA==.Close:BAAANQADCgUIBQABNQAECggIEQAIAAAAAA==.Clouds:BAAANQAECgIIAwABNQAECgQICgAIAAAAAA==.',
Co='Conorix:BAAANQADCggIMgAAAA==.Corvo:BAAANQADCggICAABNQAECgcIGwALADYfAA==.',
Cr='Crataxxis:BAABNQAECn8mAAMOAAoKOgz1DQB+AQAOAAoKOgz1DQB+AQAPAAEKAADOcwAnAAAAAA==.',
Cu='Cudara:BAAANQADCgIIAgABNQAECgUICQAIAAAAAA==.Cupra:BAAANQADCgIIAgAAAA==.',
Cy='Cydon:BAABNQAECn8pAAIQAAgKkx1iCwC2AgAQAAgKkx1iCwC2AgAAAA==.Cythraul:BAABNQAECn8bAAILAAcKNh8FCAB8AgALAAcKNh8FCAB8AgAAAA==.',
Da='Daerith:BAAANQADCgYICgAAAA==.Daerrith:BAAANQADCgYJBgAAAA==.Dagni:BAAANQAECgEIAQAAAA==.Dantey:BAAANQADCgUIBQABNQAECgoKGwAHAHkWAA==.Darrwin:BAAANQAECgUIEgAAAA==.',
De='Deathhor:BAAANQAECgEIAgAAAA==.Deathspacito:BAAANQADCgMIAwAAAA==.Demonalsa:BAAANQADCgUIBQABNQAECggIGwARABIVAA==.Derrith:BAAANQADCgUIBgAAAA==.Dezgra:BAAANQAECgcIEQAAAA==.',
Df='Dfabness:BAABNQAECn8cAAIKAAgKVQ7BLgCiAQAKAAgKVQ7BLgCiAQAAAA==.',
Do='Doomfury:BAAANQADCgEIAgAAAA==.Dotbush:BAAANQAECgQIBAABNQAFFAMIBgAEAAcDAA==.',
Dr='Dracthayr:BAABNQAECn8wAAISAAoKggqlBgAVAQASAAoKggqlBgAVAQAAAA==.Dragonhammer:BAABNQAECn8YAAIEAAkKqxcHcwBIAgAEAAkKqxcHcwBIAgAAAA==.Dreaming:BAAANQAECggICAABNQAECggIEQAIAAAAAA==.Drimclaw:BAAANQAECgIIBAAAAA==.Drubo:BAAANQAECgQICgAAAA==.Drx:BAABNQAECn8iAAQSAAYKnwjYLAC6AAASAAQKRgnYLAC6AAATAAYKWAYiFQCaAAAUAAEKrAZNJgArAAAAAA==.',
Du='Dukkelemon:BAAANQAECgQIBwAAAA==.',
Ed='Edenaza:BAAANQAECgQIBAAAAA==.',
El='Elanore:BAABNQAECn8iAAMVAAoKzBSxIwByAQAVAAoKzBSxIwByAQAWAAEKAAC+QAAAAAABNQAECgIIAgAIAAAAAA==.Elicithy:BAAANQABCgUIBQABNQAECggIGwARABIVAA==.Elison:BAAANQAECgQIBQABNQAECggIFwAHABcEAA==.Ellaini:BAAANQAECgQIBwAAAA==.Elliana:BAAANQAECgIIAgAAAA==.Ellie:BAAANQAECgEIAwABNQAECgoKLAADANwgAA==.Elloise:BAAANQADCgQIBQABNQAECgIIAgAIAAAAAA==.Elsae:BAABNQAECn8rAAIJAAgKaxRmIQDYAQAJAAgKaxRmIQDYAQAAAA==.Elseb:BAAANQADCgEIAQAAAA==.',
Ev='Evasion:BAABNQAFFH8FAAIMAAMKgQzKEADfAAAMAAMKgQzKEADfAAAAAA==.Everios:BAACNQAFFH8GAAIBAAMKLxQ6AQDfAAABAAMKLxQ6AQDfAAA1AAQKfyYAAgEACgr6HTEIANECAAEACgr6HTEIANECAAAA.Evic:BAAANQADCgYICAAAAA==.Evielyn:BAAANQADCgUJBQABNQAECgIIAgAIAAAAAA==.',
Ex='Exodous:BAAANQAECgEIAwAAAA==.',
Fa='Faeleader:BAAANQAECgEIAgAAAA==.Faevelina:BAAANQAECgEIAQABNQAECgcIEwAIAAAAAA==.Faytadori:BAABNQAECn8xAAMXAAkK0BeIKgCEAgAXAAkK0BeIKgCEAgAYAAMKjglsYwB4AAAAAA==.',
Fe='Felgrrl:BAAANQADCggINgAAAA==.Feyreh:BAAANQAECgIIBAAAAA==.',
Fi='Fidget:BAABNQAECn8bAAIMAAcKFAjOEwAnAQAMAAcKFAjOEwAnAQAAAA==.',
Fl='Fletch:BAABNQAECn8WAAIFAAkKFQW4zwBUAQAFAAkKFQW4zwBUAQAAAA==.',
Fo='Forever:BAAANQAECggIEQAAAA==.',
Fr='Frahra:BAAANQAECgIIAgAAAA==.Frique:BAAANQAECgEIAQAAAA==.Frozenyogert:BAAANQAECgQICQAAAA==.',
Ga='Galbur:BAACNQAFFH8GAAMZAAMKZwweDgB3AAAZAAIKxxEeDgB3AAAHAAEKpgH8CQBAAAA1AAQKfycAAxkACgqWFGYtAGACABkACQpJFmYtAGACAAcACApZEbBtAF0BAAAA.Galdrin:BAAANQAECgcIEwAAAA==.Gaspode:BAAANQADCgYICwAAAA==.Gassann:BAABNQAECn8ZAAIEAAgKWBa5rgDCAQAEAAgKWBa5rgDCAQAAAA==.',
Ge='Geers:BAABNQAECn8iAAIaAAoKvB8kAQCRAwAaAAoKvB8kAQCRAwAAAA==.Geta:BAAANQAECgYICQABNQAECgoKJAAFANAfAA==.Getabrew:BAAANQAECgYICwABNQAECgoKJAAFANAfAA==.Getacurse:BAAANQAECgUIBgABNQAECgoKJAAFANAfAA==.Getagrip:BAAANQADCgIIAgABNQAECgoKJAAFANAfAA==.Getalife:BAAANQAECgEIAQABNQAECgoKJAAFANAfAA==.Getarage:BAABNQAECn8kAAMFAAoK0B9hEgDFAQAFAAoKsx5hEgDFAQABAAMKsx+YJQAXAQAAAA==.Getasoar:BAAANQADCgQIBgABNQAECgoKJAAFANAfAA==.Getastab:BAAANQAECgQICAABNQAECgoKJAAFANAfAA==.',
Gh='Ghil:BAABNQAECn8bAAQbAAgK2RpVAwDIAgAbAAgK2RpVAwDIAgAcAAIKCwkeYQBjAAAdAAEKMw/vPQE6AAAAAA==.',
Gi='Gildersleeve:BAAANQAECgUICwAAAA==.Gilia:BAAANQAECgIIBAAAAA==.Gimlí:BAAANQADCgEIAQAAAA==.Gingersnaps:BAAANQAECgEIAQAAAA==.',
Gl='Glynix:BAAANQAECgIIBQAAAA==.',
Gn='Gnosher:BAAANQAECgQIBgAAAA==.',
Go='Goku:BAABNQAECn8kAAQKAAgKyxNCLQCvAQAKAAgKyxNCLQCvAQAeAAYK8QwPHQAXAQAfAAEKsgUIVAAiAAAAAA==.Goldiwarlock:BAAANQADCgUIBwAAAA==.Goloron:BAAANQAECgQIBAAAAA==.Gornub:BAAANQADCgYIBgAAAA==.Gorzok:BAAANQABCgEIAQAAAA==.',
Gr='Graymayn:BAAANQAECgUIDgAAAA==.Grekk:BAAANQAECgMIBAAAAA==.Grelldar:BAAANQADCgEIAQAAAA==.Grimflaps:BAABNQAECn8dAAMSAAcKKw2BHACEAQASAAcKKw2BHACEAQATAAUKSwRZOwC+AAAAAA==.',
Gu='Gunderthirth:BAACNQAFFH8NAAIBAAYKqxy2AAApAgABAAYKqxy2AAApAgA1AAQKfyAAAgEACgooIyUDAHIDAAEACgooIyUDAHIDAAAA.Guulfang:BAAANQADCgMIAwAAAA==.',
Gw='Gwaeniiha:BAABNQAECn8bAAIEAAYK2wt6dADeAAAEAAYK2wt6dADeAAAAAA==.',
Ha='Haan:BAAANQADCgYIBgAAAA==.Haliran:BAAANQAECgMIBAAAAA==.Handsoap:BAABNQAECn8WAAIOAAcK1Qi7TgBgAQAOAAcK1Qi7TgBgAQAAAA==.Harakhty:BAAANQAECgUICQAAAA==.Hardhitter:BAABNQAECn87AAMBAAoK2xb8BwA2AQAFAAgKWg7SrACtAQABAAoK2xb8BwA2AQAAAA==.',
He='Hellstorm:BAAANQAECgEIAwAAAA==.Hellumph:BAABNQAECn8bAAILAAoKlxEDEQChAQALAAoKlxEDEQChAQAAAA==.Hevensdemon:BAAANQAECgIIAQAAAA==.Hevensrath:BAABNQAECn8jAAMEAAoKgxnFIACgAQAJAAoKWxh7FABgAgAEAAgKOhbFIACgAQAAAA==.Hevensreaper:BAAANQAECgcIDQAAAA==.Hexhorn:BAAANQADCggJDgAAAA==.Hextermorgan:BAAANQABCggIDgABNQAECgoKLgAgALsaAA==.',
Ho='Hokuden:BAABNQAECn8xAAIgAAoKnBM8MAAkAgAgAAoKnBM8MAAkAgAAAA==.Holphie:BAAANQAECgcICQAAAA==.Holyholyholy:BAAANQADCggICAAAAA==.Horsebananas:BAAANQAECggICQAAAA==.',
Hu='Huddington:BAABNQAECn8aAAICAAcKEQ0hTAAjAQACAAcKEQ0hTAAjAQAAAA==.',
Hy='Hyperion:BAAANQAECgIIAwABNQAECgcIGwALADYfAA==.',
Ig='Igknight:BAAANQAECgYIBwABNQAECgoKJgADAKUPAA==.',
Il='Ilsi:BAAANQADCgYIBgABNQAECgkJHgAGAMMbAA==.',
Im='Impthrower:BAAANQAECgIIAgABNQADCgYJDwAIAAAAAA==.',
In='Indecent:BAABNQAECn8kAAMdAAoK+Bj8BQBUAgAdAAoKfBj8BQBUAgAcAAIKHxusTQCWAAAAAA==.Inibble:BAAANQAECgEIAQAAAA==.',
Iq='Iqfbeef:BAAANQADCgYICgAAAA==.',
Is='Ishy:BAABNQAECn8uAAMCAAkK7xosZgCyAgACAAkK7xosZgCyAgAhAAMKLAvAAgCCAAAAAA==.',
Iw='Iwannalive:BAAANQADCgIIAgAAAA==.',
Iz='Izziey:BAAANQADCgEIAQAAAA==.',
Ja='Jack:BAABNQAECn8iAAQWAAkKrxdkIgAhAgAWAAgKQxZkIgAhAgAVAAYKag/VjwBnAQAiAAMKURWSFwC5AAAAAA==.Jackieblaze:BAAANQAECgUIBwABNQAFFAMIBgAWAKULAA==.Jackieplays:BAACNQAFFH8GAAMWAAMKpQuFBwCVAAAWAAIK5AmFBwCVAAAiAAIK7QvdAgCIAAA1AAQKfy8ABCIACgo2H18DAL4CACIACAqNHl8DAL4CABUACgrkGss5AIICABYAAQo2DCp6ADQAAAAA.Jaded:BAABNQAECn8mAAMjAAkKYhq9SQA8AgAjAAkKYhq9SQA8AgAGAAMKjwrPAAGPAAAAAA==.',
Je='Jeses:BAAANQAECgcIDgAAAA==.',
Jo='Jollah:BAAANQAECgYIDwAAAA==.Jorawa:BAAANQAECgIIAgAAAA==.',
Ju='Jurassic:BAAANQAECgEIAgAAAA==.Jutic:BAABNQAECn8yAAIjAAoKSCEoDQBXAwAjAAoKSCEoDQBXAwAAAA==.',
Ka='Kageken:BAAANQADCgQIBAABNQADCgYJEQAIAAAAAA==.Kaithul:BAAANQABCgQIAwAAAA==.Kardas:BAABNQAECn8hAAIkAAgKuAhQugCPAQAkAAgKuAhQugCPAQAAAA==.',
Kb='Kbilly:BAABNQAECn8qAAIjAAoKThyuIADnAgAjAAoKThyuIADnAgAAAA==.',
Ke='Kentarou:BAAANQABCgUIBQAAAA==.Keylerin:BAACNQAFFH8MAAINAAUKZhmjBQD4AAANAAUKZhmjBQD4AAA1AAQKfygAAg0ACgqWHTwIAPYCAA0ACgqWHTwIAPYCAAAA.',
Ki='Kitto:BAAANQADCgYJBgAAAA==.Kittvulpy:BAAANQADCgYICgAAAA==.',
Kl='Klausinator:BAAANQAECgEIAQAAAA==.',
Kn='Knottes:BAAANQAECgEIAwAAAA==.',
Ko='Komos:BAAANQAECgEIAQAAAA==.',
Kr='Krampus:BAABNQAECn8nAAIRAAgKzwsfCABzAQARAAgKzwsfCABzAQAAAA==.Kranok:BAABNQAECn8UAAIlAAcK0A+lOACLAQAlAAcK0A+lOACLAQAAAA==.Krennthis:BAAANQAECgEIAQAAAA==.Krimbruiser:BAAANQADCgYIBwABNQAECgIIAgAIAAAAAA==.Krimhuntress:BAAANQADCgYIBgAAAA==.',
Ku='Kunac:BAAANQADCgYIEAAAAA==.',
Ky='Kyran:BAAANQADCgUIBwAAAA==.Kyrun:BAAANQAECgYICgAAAA==.Kytrina:BAAANQADCgIIAgAAAA==.',
La='Lactoes:BAAANQADCgYIBgAAAA==.Lamoran:BAAANQAECgUICQAAAA==.',
Le='Lemón:BAAANQAECgEIAQAAAA==.',
Lh='Lhani:BAABNQAECn8bAAIVAAcKbxBzhQCGAQAVAAcKbxBzhQCGAQAAAA==.',
Li='Lilguysci:BAAANQAECgMIBgAAAA==.Lizord:BAAANQAECgQIBgAAAA==.',
Ll='Llothien:BAAANQAECgIIAwAAAA==.Llyrael:BAABNQAECn8jAAMVAAkKzgQNqAAdAQAVAAkKzgQNqAAdAQAWAAEK2gILhAAlAAAAAA==.',
Lo='Lonard:BAAANQAECgIIAgAAAA==.',
Lu='Lugosi:BAAANQAECgEIAwAAAA==.',
Ly='Lyfe:BAAANQABCgUIBwAAAA==.',
Ma='Machlain:BAAANQADCgQIBAABNQAECggIIQAJAAkcAA==.Maddeleine:BAAANQADCgYIEwAAAA==.Magara:BAAANQAECgQIBAAAAA==.Magicdemon:BAABNQAECn8pAAIOAAoKUyJcAQDoAgAOAAoKUyJcAQDoAgAAAA==.Magichunter:BAAANQAECgEIAQABNQAECgoKKQAOAFMiAA==.Magicpaladin:BAAANQAECgIIAQABNQAECgoKKQAOAFMiAA==.Magicshaman:BAAANQAECgEIAQABNQAECgoKKQAOAFMiAA==.Makall:BAAANQABCgQIBAAAAA==.Malaah:BAABNQAECn8hAAIGAAgKPA/0dwC6AQAGAAgKPA/0dwC6AQAAAA==.Mansuno:BAABNQAECn8pAAMEAAkKxRb0YAB3AgAEAAkKxRb0YAB3AgADAAEKUgPxpQAiAAAAAA==.Mapachote:BAABNQAECn8TAAIlAAYKDxIOPQBpAQAlAAYKDxIOPQBpAQAAAA==.Marodin:BAAANQADCggIOwAAAA==.Maynor:BAAANQABCggIEQAAAA==.Mazboda:BAABNQAECn8mAAQdAAcKoxUDOgAdAQAdAAcKkBMDOgAdAQAbAAIKFRkXHgCKAAAcAAIKugg3ZABcAAAAAA==.',
Me='Meatbaal:BAAANQAECgUIDwAAAA==.Medïc:BAAANQADCggICAAAAA==.Melinaria:BAABNQAECn8lAAMWAAgKdBclJgD9AQAWAAgKdBclJgD9AQAiAAEK2w6NCQBEAAAAAA==.Merewene:BAAANQAECgQIBwAAAA==.Merkabai:BAAANQADCgIIAgAAAA==.',
Mi='Mileta:BAABNQAECn8nAAIXAAoKbRjTHADiAgAXAAoKbRjTHADiAgAAAA==.Minuette:BAAANQAECgMIBAAAAA==.',
Mo='Montblanc:BAAANQAECgQIBAABNQAECgUICwAIAAAAAA==.Morgnox:BAAANQAECgIIAwAAAA==.',
Mu='Murdercookie:BAAANQAECgEIAgAAAA==.',
Na='Nazgul:BAAANQADCgcICAAAAA==.',
Ne='Necronic:BAAANQAECgIIBQAAAA==.Necroreign:BAABNQAECn8xAAIOAAoKWhcpBAAuAgAOAAoKWhcpBAAuAgAAAA==.Need:BAAANQAECgIIAgAAAA==.Neherenia:BAABNQAECn8aAAIgAAcKeRalOwDgAQAgAAcKeRalOwDgAQAAAA==.Nervous:BAAANQAECggIAwABNQAECggIEQAIAAAAAA==.Nessee:BAAANQAECgQIEgAAAA==.',
Ni='Niall:BAAANQAECgEIAwAAAA==.Nightfire:BAAANQABCgcIEgAAAA==.Nihowdy:BAABNQAECn8vAAImAAoKayBXAQB/AwAmAAoKayBXAQB/AwAAAA==.',
No='Norrin:BAAANQAECgEIAgAAAA==.',
Oc='Octalexane:BAAANQADCgYIBgABNQAECgcIFAABANkKAA==.',
On='Onimusha:BAAANQAECgEIAQAAAA==.',
Or='Orci:BAABNQAECn8eAAIcAAcKVws+HQCEAQAcAAcKVws+HQCEAQAAAA==.Orryn:BAAANQABCgIIAgAAAA==.Ortalbem:BAABNQAECn8zAAMCAAoKBxqlVwDRAgACAAoK1hilVwDRAgAaAAQK0hgCGAA5AQAAAA==.',
Ou='Oulli:BAAANQAECgEIAQAAAA==.',
Ov='Ovi:BAAANQAECgUIDwAAAA==.',
Pa='Painthuffer:BAAANQAECggIEQABNQAECgoKJAACAIIVAA==.Pazuuzu:BAAANQAECgEIAQAAAA==.',
Pe='Peddles:BAAANQAECgUICwAAAA==.',
Ph='Pherix:BAABNQAECn8iAAIWAAkKSRxQEgDbAgAWAAkKSRxQEgDbAgABNQAECgoKGwAHAHkWAA==.Philipfry:BAABNQAECn81AAMDAAoKaxkBTgAyAgADAAgKBhcBTgAyAgAEAAUKrRGBkQCzAAAAAA==.Phill:BAAANQADCgcIDwAAAA==.',
Pl='Plaguetusk:BAAANQADCgQIBAAAAA==.',
Po='Poomacha:BAAANQAECgQIDQAAAA==.Potatopants:BAAANQAECgEIAQAAAA==.',
Pr='Prinlina:BAAANQAECgEIAQAAAA==.',
Py='Pyree:BAABNQAECn8mAAISAAgK2A0CBgAmAQASAAgK2A0CBgAmAQAAAA==.',
Ra='Radimus:BAAANQAECgEIAQAAAA==.Raenne:BAAANQADCgMIAwAAAA==.Rainvelle:BAAANQADCgQIBAAAAA==.Raistlain:BAABNQAECn8fAAIWAAgKwRQKJgD+AQAWAAgKwRQKJgD+AQAAAA==.Ralli:BAABNQAECn8mAAMOAAoKIBm9FgDmAgAOAAkKxBq9FgDmAgAPAAYKqxenGQDfAAAAAA==.Ralls:BAAANQADCgUIBQABNQAECgYIDgAIAAAAAA==.Rallsdk:BAAANQADCgYIBgABNQAECgYIDgAIAAAAAA==.Rallsodins:BAAANQAECgYIDgAAAA==.Ranulf:BAAANQAECgQICgAAAA==.Ratava:BAAANQAECgUIDgAAAA==.Ratrot:BAAANQADCggICQAAAA==.Raztar:BAAANQADCgUIBQAAAA==.',
Re='Reddemon:BAAANQAECggIEgAAAA==.Rekarra:BAAANQAECgEIAQAAAA==.Reldarus:BAEBNQAECn8nAAQiAAkKUSD4AgDVAgAiAAcK1CP4AgDVAgAVAAkKWxhzIACCAQAWAAEK9BWCcABHAAAAAA==.Rena:BAABNQAECn8hAAQSAAoKqRBtIgA2AQASAAcKvwdtIgA2AQAUAAQKxQNkHQB5AAATAAMKpQL3FwB4AAAAAA==.Revilation:BAABNQAECn8bAAIJAAkKzhLrHAAEAgAJAAkKzhLrHAAEAgAAAA==.Rezjyk:BAAANQADCgYIBgABNQAECggIKAAEABsZAA==.Rezzyk:BAABNQAECn8oAAIEAAcKGxm1PABOAQAEAAcKGxm1PABOAQAAAA==.',
Rh='Rhyxali:BAAANQAECgUIEgAAAA==.',
Ri='Riibirth:BAAANQADCgYIBgAAAA==.Riis:BAAANQADCgEIAQAAAA==.',
Ry='Rygelon:BAAANQAECgQICgAAAA==.',
Sa='Sacredscales:BAAANQADCgMJAwAAAA==.Samvimes:BAAANQAECgIIBQAAAA==.Sangreene:BAABNQAECn8eAAIWAAoKgRaQGgB3AgAWAAoKgRaQGgB3AgAAAA==.Sargis:BAABNQAECn8sAAMEAAoKVRrgbQBVAgAEAAgKFBvgbQBVAgADAAgKXBJuaADeAQAAAA==.',
Sc='Schrödinger:BAAANQADCggIEgABNQAECgcIGwALADYfAA==.Scott:BAAANQAECgQIBQAAAA==.',
Se='Serissa:BAAANQAECgEIAQAAAA==.Serjankins:BAAANQADCgQIBAAAAA==.Setsuna:BAAANQABCgYIDAABNQAECggIGgAWADEgAA==.',
Sh='Shadowbrooks:BAAANQAECgEIAQAAAA==.Shadowgiver:BAAANQADCgcICwAAAA==.Shagol:BAABNQAECn8XAAIVAAYKaRjkjABvAQAVAAYKaRjkjABvAQAAAA==.Shaidic:BAAANQAECgEIAQAAAA==.Shamemoon:BAAANQAECgEJAgABNQAECgUICgAIAAAAAA==.Shamunroe:BAABNQAECn8oAAMGAAkKChZAHwA+AQAGAAgK3xVAHwA+AQAjAAUK1Aow1gC6AAAAAA==.Shatterhoof:BAAANQAECgUIEAAAAA==.Shelle:BAAANQADCgQIBQAAAA==.Shiftysmage:BAAANQAECgEIAQABNQAECgUIDQAIAAAAAA==.Shingra:BAACNQAFFH8KAAIUAAMKURgCBwD3AAAUAAMKURgCBwD3AAA1AAQKfxwAAhQACQomFDoGAGoCABQACQomFDoGAGoCAAAA.Shores:BAAANQAECgEIAQAAAA==.Shylindra:BAAANQAECgEIAQAAAA==.',
Si='Sigourney:BAAANQAECgYIEwABNQAECggICQAIAAAAAA==.Silversho:BAAANQAECgEIAQAAAA==.Silvren:BAAANQADCgIIAgAAAA==.',
Sk='Skill:BAABNQAECn8cAAMYAAgKghKIKgDKAQAYAAgKghKIKgDKAQAXAAQKRw6wegDgAAAAAA==.',
Sl='Slighttrash:BAAANQAECgUIDgAAAA==.',
Sm='Smallcrow:BAABNQAECn8bAAMKAAkKbR40FwCSAgAKAAgKbR40FwCSAgAfAAQK0Q1HMwDQAAAAAA==.',
So='Somdot:BAEBNQAECn87AAIWAAoKdyCHAQB0AgAWAAoKdyCHAQB0AgAAAA==.Somedeekay:BAAANQAECgYIEAAAAA==.',
Sp='Spirit:BAABNQAECn8VAAMTAAgKFRrtEQCNAgATAAgKFRrtEQCNAgASAAEKCwjLQQAmAAABNQAFFAMIBQAMAIEMAA==.',
St='Starga:BAAANQADCgQIBAAAAA==.Starge:BAAANQADCgUIBQAAAA==.Starre:BAAANQADCgQIBAAAAA==.Steffey:BAAANQAECgYIDgAAAA==.Stepbro:BAAANQADCgcIDAAAAA==.Stoikk:BAABNQAECn8UAAIGAAcK3hCPkQB4AQAGAAcK3hCPkQB4AQAAAA==.Straven:BAAANQAECgcIEgAAAA==.Sturgeson:BAACNQAFFH8QAAIBAAUKeBvvAAD8AAABAAUKeBvvAAD8AAA1AAQKfycAAgEACQoIIW4JALUCAAEACQoIIW4JALUCAAAA.',
Su='Suffocation:BAEANQAECgYIBgABNQAFFAgIIQAcAHMeAA==.Sulwen:BAABNQAECn8hAAIVAAgKqBTLXgAFAgAVAAgKqBTLXgAFAgAAAA==.Sundance:BAAANQADCgUIBQAAAA==.Sunray:BAAANQAECgYIBgAAAA==.',
Sw='Swiftfeet:BAABNQAECn8fAAIkAAgKSBPplADeAQAkAAgKSBPplADeAQAAAA==.',
['Sé']='Sésho:BAAANQADCgQIBgAAAA==.',
['Sö']='Söranin:BAAANQAECgMIBAAAAA==.',
['Sø']='Sømdøt:BAEANQAECggIDwABNQAECgoKOwAWAHcgAA==.',
Ta='Taeili:BAABNQAECn8WAAIQAAgK1BY6FwD5AQAQAAgK1BY6FwD5AQAAAA==.Taeror:BAAANQADCgQIBAAAAA==.Tanequil:BAACNQAFFH8GAAIYAAMK4QI9BgC0AAAYAAMK4QI9BgC0AAA1AAQKfy4AAhgACgoNDPspAM8BABgACgoNDPspAM8BAAAA.',
Te='Techromancer:BAABNQAECn8bAAIHAAoKeRbmBQDWAQAHAAoKeRbmBQDWAQAAAA==.Tem:BAAANQAECgEIAQAAAA==.',
Th='Thanatias:BAAANQAECgcIBwAAAA==.Thantasia:BAAANQAECgMIAwAAAA==.Theakunda:BAAANQAECgcIEQAAAA==.Theodis:BAAANQAECgIIAgAAAA==.Thokdar:BAAANQAECgQICAAAAA==.',
Ti='Tifà:BAAANQAECgIIAgAAAA==.Tillago:BAAANQAECgEIAQAAAA==.Timothy:BAAANQAECgQIBwAAAA==.Timothyjohn:BAAANQAECgUIDgAAAA==.Tinkphooey:BAAANQAECgMIBgAAAA==.Tirianna:BAAANQADCgEIAQABNQAECgIIAgAIAAAAAA==.Tituba:BAABNQAECn8tAAIdAAoK0xm9GACPAQAdAAoK0xm9GACPAQAAAA==.',
To='Toklore:BAAANQADCgcIDgABNQAECgEIAQAIAAAAAA==.Tonepavone:BAAANQADCgYIBgAAAA==.Tormmok:BAAANQADCgQIBAAAAA==.',
Tr='Traazz:BAAANQADCgYICgAAAA==.Trey:BAAANQAECgQIBAAAAA==.Trior:BAAANQAECgQIBgAAAA==.',
Ts='Tsuruga:BAABNQAECn8fAAIeAAgKDwSxBwDpAAAeAAgKDwSxBwDpAAAAAA==.',
Tu='Turkwise:BAABNQAECn8wAAQQAAgKRBBsIwB7AQAQAAcK4Q9sIwB7AQAnAAcKqw2AHAA+AQAYAAQKwgQLMABwAAAAAA==.',
Ul='Ulodude:BAAANQADCgYIBgAAAA==.',
Un='Unholydiddy:BAAANQABCggIEwAAAA==.',
Ur='Urobolos:BAAANQAECgMIAwAAAA==.',
Uv='Uvari:BAAANQAECgYIEgAAAA==.',
Va='Vacalaca:BAAANQAECgUICgAAAA==.Valany:BAAANQADCgIIAgAAAA==.Valkira:BAACNQAFFH8GAAIRAAMKlgyPAQDwAAARAAMKlgyPAQDwAAA1AAQKfygAAxEACgqzFyIPAHgCABEACgqtFiIPAHgCAAYABgpxGVSLAIgBAAAA.Valton:BAACNQAFFH8FAAIKAAMKRRcaBADdAAAKAAMKRRcaBADdAAA1AAQKfzQAAgoACgqDI8EDAJkDAAoACgqDI8EDAJkDAAAA.Vancede:BAAANQAECgUIBQAAAA==.Vanillanice:BAAANQADCgMJBAAAAA==.Varrfife:BAAANQAECgEIAQAAAA==.Vaxaldan:BAABNQAECn8nAAIZAAgKlQ2LEgBOAQAZAAgKlQ2LEgBOAQAAAA==.',
Ve='Velindsong:BAAANQADCggICAAAAA==.Venj:BAAANQAECgIIAgAAAA==.Ventosa:BAACNQAFFH8GAAIjAAMKkwoYDAC7AAAjAAMKkwoYDAC7AAA1AAQKfycAAiMACgq9GBg6AHYCACMACgq9GBg6AHYCAAAA.Vex:BAAANQAECgIIAwAAAA==.',
Vi='Vilox:BAAANQADCgIIAgAAAA==.Viltex:BAAANQADCgYICwAAAA==.Vilxten:BAAANQAECgUICQAAAA==.Virtues:BAAANQAECgEIBAAAAA==.',
Vo='Voidleader:BAABNQAECn8YAAIVAAgKLBC9ewCmAQAVAAgKLBC9ewCmAQAAAA==.Vostok:BAABNQAECn8kAAIdAAgKuRDujADHAQAdAAgKuRDujADHAQAAAA==.',
Vy='Vylleria:BAAANQADCgYIBgAAAA==.',
['Vá']='Váyne:BAAANQAECgEIAQABNQAECgYIDAAIAAAAAA==.',
Wa='Warralok:BAAANQADCgYIBgAAAA==.Warramag:BAAANQAECgYICgAAAA==.Warranni:BAABNQAECn8pAAIGAAoKVxmuKADeAgAGAAoKVxmuKADeAgAAAA==.',
We='Weekend:BAABNQAECn8dAAIGAAoKagkPQADKAAAGAAoKagkPQADKAAAAAA==.',
Wh='Whatafox:BAABNQAECn8eAAMGAAkKjxxpTABFAgAGAAcKRB1pTABFAgAjAAYKEBC5aACCAAAAAA==.Whittail:BAAANQABCggIFQAAAA==.',
Wi='Wikket:BAABNQAECn8sAAIXAAoKHQ9GBgDWAQAXAAoKHQ9GBgDWAQAAAA==.',
Wo='Wortel:BAAANQADCgYIBgAAAA==.',
Wy='Wyelie:BAABNQAECn8WAAIJAAcKqQzePAANAQAJAAcKqQzePAANAQAAAA==.',
Xa='Xade:BAABNQAECn8wAAINAAoKdRgzCgDSAgANAAoKdRgzCgDSAgAAAA==.Xandendon:BAABNQAECn8XAAIHAAkKtw0KWACwAQAHAAkKtw0KWACwAQAAAA==.',
Xe='Xerond:BAAANQAECgMICgAAAA==.Xevin:BAABNQAECn8eAAIGAAkKwxsuOwCJAgAGAAkKwxsuOwCJAgAAAA==.',
Xo='Xotha:BAAANQADCgEIAQAAAA==.',
Ya='Yaákov:BAABNQAECn8kAAIPAAkK6RRwCQB6AQAPAAkK6RRwCQB6AQAAAA==.',
Yi='Yinosai:BAAANQADCgYICQAAAA==.',
Yo='Yougot:BAAANQAECgEIAQAAAA==.',
Za='Zademedic:BAAANQAECgQIBgAAAA==.Zanarkin:BAAANQAECgEIBgAAAA==.Zanedore:BAAANQABCggIEAAAAA==.Zaranji:BAAANQADCgYIBgAAAA==.Zarisedra:BAACNQAFFH8NAAMDAAUKHA0YEwAwAQADAAUKHA0YEwAwAQAEAAEKcApBGABEAAA1AAQKfykAAwMACgp0GpcmAM8CAAMACgp0GpcmAM8CAAQAAQoAAAjeARIAAAAA.Zarissena:BAABNQAECn8XAAIHAAgKFwRMKgC6AAAHAAgKFwRMKgC6AAAAAA==.Zarmina:BAAANQADCgEIAQAAAA==.Zarris:BAAANQABCgYIBAAAAA==.',
Ze='Zerdah:BAAANQADCgcIEwAAAA==.Zerogasm:BAAANQAECgMIAwAAAA==.Zerolicious:BAAANQAECgMJBAAAAA==.Zeroprophecy:BAAANQAECgIIAgAAAA==.Zevvo:BAABNQAECn8lAAIFAAkKxBxODAD+AQAFAAkKxBxODAD+AQAAAA==.',
Zo='Zoeybear:BAAANQAECgMIBgAAAA==.Zoraji:BAABNQAECn8wAAIeAAoKAR3UAwBKAwAeAAoKAR3UAwBKAwAAAA==.',
['Ëd']='Ëdën:BAAANQAECgcICwAAAA==.',
['Ða']='Ðarkmoon:BAAANQABCgYICAAAAA==.',
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
