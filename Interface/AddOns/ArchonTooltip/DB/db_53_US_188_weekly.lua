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

local lookup = {'Warrior-Protection','Paladin-Holy','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Warrior-Arms','Shaman-Elemental','DeathKnight-Unholy','DemonHunter-Havoc','Druid-Feral','Druid-Balance','Monk-Mistweaver','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Mage-Arcane','Paladin-Protection','Monk-Windwalker','Druid-Restoration','Rogue-Subtlety','Rogue-Assassination','Unknown-Unknown','DemonHunter-Devourer','Druid-Guardian','DemonHunter-Vengeance','Priest-Shadow','Shaman-Enhancement','Evoker-Devastation','DeathKnight-Blood','DeathKnight-Frost','Mage-Frost','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Priest-Discipline','Mage-Fire','Shaman-Restoration','Rogue-Outlaw','Warrior-Fury',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abrocklock:BAAANQAECgEIAQAAAA==.',
Ad='Adorabull:BAABNQAECn8rAAIBAAkKDyGvBAA4AwABAAkKDyGvBAA4AwAAAA==.',
Ae='Aevelee:BAAANQAECgYIDwAAAA==.',
Al='Alari:BAAANQADCgYIBgAAAA==.Aleeta:BAAANQAECgQIBAAAAA==.Alleriae:BAAANQAECgMIAwAAAA==.Allucard:BAAANQAECggICwAAAA==.',
Am='Amaria:BAAANQAECgQIBwABNQAECgkJGgACAM4aAA==.',
An='Anaki:BAAANQADCgUIBQAAAA==.Anduîiîn:BAAANQADCggICgAAAA==.Angelstörm:BAAANQAFFAEIAQAAAA==.Angelusnox:BAAANQAECgIIAgAAAA==.Antarias:BAAANQAECgMIBwAAAA==.Anubiz:BAAANQADCgEIAQAAAA==.Anzhe:BAABNQAECn8ZAAQDAAoKkRtPAgCmAgADAAkKkRtPAgCmAgAEAAUKIg9ozwD5AAAFAAMKiA9QSQBsAAAAAA==.',
Ar='Araydin:BAAANQADCgEIAQAAAA==.Arckenon:BAACNQAFFH8IAAIGAAIKxxmiHQCaAAAGAAIKxxmiHQCaAAA1AAQKfz8AAgYACgqdILAhANECAAYACgqdILAhANECAAAA.Ardarl:BAAANQADCggICAAAAA==.Armdandrëady:BAAANQAECgUIBQAAAA==.Arranix:BAAANQADCgMIAwAAAA==.Arrica:BAAANQAECgIIAwAAAA==.Artemisv:BAAANQADCgIIAgAAAA==.Artorias:BAAANQAECgQIBAAAAA==.',
As='Ashog:BAAANQAECgIIAQAAAA==.',
At='Atillis:BAAANQAECggICwAAAA==.',
Au='Austenpally:BAABNQAECn8eAAMCAAgKHg93igB9AQACAAgKHg93igB9AQAGAAcKMg4l5QD/AAAAAA==.',
Av='Avarek:BAAANQADCgEIAQAAAA==.Aveycado:BAAANQAECgYIEwAAAA==.',
Ax='Axeflack:BAABNQAECn8wAAMBAAoK1BuRCABAAgABAAoK1BuRCABAAgAHAAUKMgf4/gDeAAAAAA==.Axegor:BAAANQAECgQIBwABNQAECgoKJwAIAKAdAA==.',
Az='Azaral:BAAANQADCgUJBQABNQAECggIGgAJAMMEAA==.Azmarija:BAAANQADCgEIAgAAAA==.',
Ba='Bacuda:BAAANQAECgUICQAAAA==.Batbane:BAAANQADCgYICAAAAA==.',
Be='Beggles:BAAANQADCgUIBQAAAA==.',
Bi='Biancadelrio:BAABNQAECn8WAAIKAAgKcwYLSAD0AAAKAAgKcwYLSAD0AAAAAA==.Bigguberment:BAABNQAECn8XAAMLAAcKVRhKHAAIAQALAAcKVRhKHAAIAQAMAAEKEwZniAAuAAAAAA==.Bigsneaky:BAAANQAECgYICwABNQAECggIFwANAKoVAA==.',
Bl='Blackbird:BAABNQAECn8gAAMOAAkKGwq/FACRAQAOAAkKGwq/FACRAQAPAAYKsgSIFADmAAABNQAFFAQICAAQAKoSAA==.Bladekrim:BAAANQAECgEIBAAAAA==.Blindashunae:BAAANQADCgEIAQAAAA==.Blitzo:BAAANQADCgMIAwAAAA==.',
Bo='Boomhammer:BAAANQADCgYIBgAAAA==.Boredgored:BAAANQADCgcIBwABNQAECgoKMAARAN0YAA==.Botia:BAABNQAECn8XAAIMAAgKAQOEiQCuAAAMAAgKAQOEiQCuAAAAAA==.Bourdeaux:BAAANQADCgcIFQAAAA==.',
Br='Braedia:BAAANQABCgEIAQAAAA==.Brainnmatter:BAAANQADCgEIAQAAAA==.Brashmoore:BAAANQADCgMIAwAAAA==.Brizik:BAAANQABCgUIBQAAAA==.Brookshields:BAAANQAECgcIDAAAAA==.Bruised:BAAANQAECgIIAwAAAA==.Brunae:BAABNQAECn8hAAIBAAgKIRArGAA0AQABAAgKIRArGAA0AQAAAA==.Brunnera:BAAANQADCggIDgAAAA==.Bruuenor:BAAANQAECgEIAQAAAA==.Bruul:BAABNQAECn8cAAQGAAcKqBN/BgEUAQAGAAUKUg9/BgEUAQACAAQKpAYd/gCAAAASAAEKAAAMbQA4AAAAAA==.',
By='Bytour:BAAANQAECgUIBwABNQAFFAMIBQATAEUXAA==.',
Ca='Caenji:BAAANQAECgIIAgAAAA==.Captbenson:BAAANQADCgYIAQAAAA==.Carcharoth:BAAANQADCgMIAwAAAA==.Carmelina:BAAANQADCgQIBQAAAA==.Castanthrax:BAAANQADCgQIBAAAAA==.Cathryl:BAAANQADCgQIBAABNQAECgkJGAAUAM0ZAA==.',
Ch='Chadgar:BAABNQAECn8wAAIRAAoK3RjEcACcAgARAAoK3RjEcACcAgAAAA==.Chaoshammer:BAAANQADCggICAAAAA==.Chey:BAABNQAECn9OAAMVAAoKdiRxDAAMAwAVAAoKLyFxDAAMAwAWAAYKDCR7HQAzAQAAAA==.Chipsahoy:BAAANQADCgEIAQAAAA==.Chormage:BAAANQADCgQIBAAAAA==.Chíef:BAAANQAFFAMIBAAAAA==.',
Cl='Clarke:BAAANQABCgEIAQAAAA==.Close:BAAANQADCgUIBQABNQAECgoKFgACAIMMAA==.Clouds:BAAANQAECgIIAwABNQAECgQICQAXAAAAAA==.',
Co='Conorix:BAAANQADCggIQgAAAA==.Corvo:BAAANQADCggICAABNQAECgkJGAAUAM0ZAA==.',
Cr='Crataxxis:BAABNQAECn88AAMKAAoKbQ6ILwCDAQAKAAoKbQ6ILwCDAQAYAAEKAADOcwAnAAAAAA==.',
Cu='Cudara:BAAANQADCgIIAgABNQAECgUICQAXAAAAAA==.Cupra:BAAANQADCgIIAgAAAA==.',
Cy='Cydon:BAABNQAECn8+AAIZAAkKQR9iCwC2AgAZAAkKQR9iCwC2AgAAAA==.Cythraul:BAABNQAECn8uAAIaAAgKth0FCAB8AgAaAAgKth0FCAB8AgABNQAECgkJGAAUAM0ZAA==.',
Da='Daerith:BAAANQADCgYICgAAAA==.Daerrith:BAAANQADCgYIBgAAAA==.Dagni:BAAANQAECgEIAQAAAA==.Dantey:BAAANQADCgUIBQABNQAECgoKOgAbAEMfAA==.Darkveil:BAAANQADCgQIBAAAAA==.Darrwin:BAABNQAECn8aAAIGAAgKPhVi6wBFAQAGAAgKPhVi6wBFAQAAAA==.',
De='Deathhor:BAAANQAECgEIAQAAAA==.Deathspacito:BAAANQADCgMIAwAAAA==.Demonalsa:BAAANQADCgUIBQABNQAECggIGwAcABIVAA==.Derrith:BAAANQADCgUIBgAAAA==.Dezgra:BAAANQAECgcIEAAAAA==.',
Df='Dfabness:BAABNQAECn8nAAITAAkKSxKDHACoAQATAAkKSxKDHACoAQAAAA==.',
Do='Doomfury:BAAANQADCgEIAgAAAA==.Dotbush:BAAANQAECgQIBAABNQAFFAUICAAGAAcDAA==.',
Dr='Dracthayr:BAABNQAECn8/AAIdAAoKWgvQCwCKAQAdAAoKWgvQCwCKAQAAAA==.Dragonhammer:BAABNQAECn8zAAIGAAoK3CE0EAAkAwAGAAoK3CE0EAAkAwAAAA==.Dreaming:BAAANQAECggICAABNQAECgoKFgACAIMMAA==.Drimclaw:BAAANQAECgIIAwAAAA==.Drubo:BAABNQAECn8UAAMUAAYKNgusSQDBAAAUAAUK3wqsSQDBAAAMAAMK6AGqgAA5AAAAAA==.Drx:BAABNQAECn80AAQOAAgKMwjWHwD5AAAOAAgKMwjWHwD5AAAdAAYKsQh+FgC+AAAPAAIKGAUlGQBOAAAAAA==.',
Du='Dukkelemon:BAAANQAECgQIBwAAAA==.',
Ed='Edenaza:BAAANQAECgQIBAAAAA==.',
El='Elanore:BAACNQAFFH8IAAIQAAQKqhIVFgA4AQAQAAQKqhIVFgA4AQA1AAQKfykAAxAACgolHEwXAAoDABAACgolHEwXAAoDABsAAQoAAId3AAAAAAAA.Elicithy:BAAANQABCgUIBQABNQAECggIGwAcABIVAA==.Elison:BAAANQAECgQIBAABNQAECggIGgAJAMMEAA==.Ellaini:BAAANQAECgUICAAAAA==.Elliana:BAAANQAECgUIDAABNQAFFAQICAAQAKoSAA==.Ellie:BAAANQAECgEIAgABNQAECgoKMAACANwgAA==.Elloise:BAAANQADCgQIBQABNQAFFAQICAAQAKoSAA==.Elmichi:BAAANQAECgMIAwABNQAECggICgAXAAAAAA==.Elsae:BAABNQAECn81AAISAAoKIBRmIQDYAQASAAoKIBRmIQDYAQAAAA==.Elseb:BAAANQADCgEIAQAAAA==.',
Em='Emeric:BAAANQADCgQIBAAAAA==.',
Ev='Evasion:BAABNQAFFH8FAAIWAAMKgQzKEADfAAAWAAMKgQzKEADfAAAAAA==.Everios:BAACNQAFFH8IAAIBAAUKLxQ2AwDJAAABAAUKLxQ2AwDJAAA1AAQKfzQAAgEACgrJHzEIANECAAEACgrJHzEIANECAAAA.Evic:BAAANQADCgYICAAAAA==.Evielyn:BAAANQADCgUJBQABNQAFFAQICAAQAKoSAA==.',
Ex='Exodous:BAAANQAECgEIBAAAAA==.',
Fa='Faeleader:BAAANQAECgEIAQAAAA==.Faevelina:BAAANQAECgEIAQABNQAECgcIDwAXAAAAAA==.Faytadori:BAABNQAECn9QAAMMAAoK+xrEFQBXAgAMAAoK+xrEFQBXAgAUAAQKmQpsYwB4AAAAAA==.',
Fe='Felgrrl:BAAANQADCggIRgAAAA==.Feyreh:BAAANQAECgIIBAAAAA==.',
Fi='Fidget:BAABNQAECn8uAAIWAAgKRgrYFwBeAQAWAAgKRgrYFwBeAQAAAA==.',
Fl='Fletch:BAABNQAECn8WAAIHAAkKFQW4zwBUAQAHAAkKFQW4zwBUAQAAAA==.',
Fo='Forever:BAABNQAECn8WAAMCAAoKgwwtigAGAQACAAoKgwwtigAGAQAGAAIKNwLbsAENAAAAAA==.',
Fr='Frahra:BAAANQAECgIIAgAAAA==.Frique:BAAANQAECgUIEQAAAA==.Frozenyogert:BAAANQAECgQICQAAAA==.',
Ga='Galbur:BAACNQAFFH8IAAMeAAUKZwxeIQB9AAAeAAMKxxFeIQB9AAAJAAIKpgE5FAA4AAA1AAQKfzUABB4ACgpxFmYtAGACAB4ACQpJFmYtAGACAAkACQpAFbgvAFsBAB8AAgozCAKUAGUAAAAA.Galdrin:BAAANQAECgcIDwAAAA==.Gaspode:BAAANQADCgYICwAAAA==.Gassann:BAABNQAECn8ZAAIGAAgKWBa5rgDCAQAGAAgKWBa5rgDCAQAAAA==.',
Ge='Geers:BAABNQAECn8yAAIgAAoK/iIkAQCRAwAgAAoK/iIkAQCRAwAAAA==.Geta:BAAANQAECgYICgABNQAECgoKNwAHAEYiAA==.Getabrew:BAAANQAECgYICQABNQAECgoKNwAHAEYiAA==.Getacurse:BAAANQAECgUIBQABNQAECgoKNwAHAEYiAA==.Getagrip:BAAANQADCgIIAgABNQAECgoKNwAHAEYiAA==.Getalife:BAAANQAECgEIAgABNQAECgoKNwAHAEYiAA==.Getarage:BAABNQAECn83AAMHAAoKRiJUEAARAwAHAAoKRiJUEAARAwABAAMKsx+YJQAXAQAAAA==.Getasoar:BAAANQADCgQIBgABNQAECgoKNwAHAEYiAA==.Getastab:BAAANQAECggIEwABNQAECgoKNwAHAEYiAA==.',
Gh='Ghil:BAABNQAECn8fAAQhAAoKuBlVAwDIAgAhAAoKuBlVAwDIAgAiAAMKtAseYQBjAAAjAAEKMw/vPQE6AAAAAA==.',
Gi='Gildersleeve:BAAANQAECgUIBgAAAA==.Gilia:BAAANQAECgIIBAAAAA==.Gimlí:BAAANQADCgEIAQAAAA==.',
Gl='Glynix:BAAANQAECgIIBAAAAA==.',
Gn='Gnosher:BAAANQAFFAMIBAAAAA==.Gnosherson:BAAANQAECgQIBAABNQAFFAMIBAAXAAAAAA==.',
Go='Goku:BAABNQAECn8zAAQTAAkKURN0GwCzAQATAAkKURN0GwCzAQAkAAYK8QwPHQAXAQANAAEKsgUIVAAiAAAAAA==.Goldiwarlock:BAAANQADCgUIBwAAAA==.Goloron:BAAANQAECgQIBAAAAA==.Gornub:BAAANQADCgYIBgAAAA==.Gorzok:BAAANQABCgEIAQAAAA==.',
Gr='Graymayn:BAAANQAECgQIDAAAAA==.Grekk:BAAANQAECgMIAwAAAA==.Grelldar:BAAANQADCgEIAQAAAA==.Grimflaps:BAABNQAECn8wAAMdAAgKWw0SDwA9AQAdAAgKWw0SDwA9AQAOAAUKSwRZOwC+AAAAAA==.',
Gu='Gunderthirth:BAACNQAFFH8NAAIBAAYKqxy2AAApAgABAAYKqxy2AAApAgA1AAQKfyIAAgEACgpqIyUDAHIDAAEACgpqIyUDAHIDAAAA.Guulfang:BAAANQADCgMIAwAAAA==.',
Gw='Gwaeniiha:BAABNQAECn8tAAIGAAgKhgxBugBHAQAGAAgKhgxBugBHAQAAAA==.',
Ha='Haan:BAAANQADCgYIDAAAAA==.Haliran:BAAANQAECgQIBQAAAA==.Handsoap:BAABNQAECn8iAAIKAAcKHQm7TgBgAQAKAAcKHQm7TgBgAQAAAA==.Harakhty:BAAANQAECgUICQAAAA==.Hardhitter:BAABNQAECn9HAAMBAAoKrBjsDwArAgABAAoKZRfsDwArAgAHAAoKYA6BgwBpAQAAAA==.',
He='Hellstorm:BAAANQAECgEIAgAAAA==.Hellumph:BAABNQAECn8sAAIaAAoKKBUICADoAQAaAAoKKBUICADoAQAAAA==.Hevensdemon:BAABNQAECn8UAAIaAAkKYxb5BgAPAgAaAAkKYxb5BgAPAgAAAA==.Hevensrath:BAABNQAECn82AAMSAAoKxB57FABgAgASAAoK2Rt7FABgAgAGAAoKrxvZSQA9AgAAAA==.Hevensreaper:BAABNQAECn8fAAMeAAcKehkEJADLAQAeAAcKehkEJADLAQAJAAQKwAKatwB+AAAAAA==.Hevensvoid:BAABNQAECn8XAAQbAAoKJRMEIgBeAQAbAAcKmg0EIgBeAQAQAAMKaQhiwQCUAAAlAAEKsALAHQAaAAAAAA==.Hevshaolin:BAAANQAECgcIDwAAAA==.Hexhorn:BAAANQADCggJDgAAAA==.Hextermorgan:BAAANQABCggIEAABNQAECgoKNgAfALMbAA==.',
Ho='Hokuden:BAABNQAECn9AAAIfAAoKxRQ8MAAkAgAfAAoKxRQ8MAAkAgAAAA==.Holphie:BAAANQAECggIDAAAAA==.Holyholyholy:BAAANQADCggICAAAAA==.Homet:BAAANQADCgQIBAAAAA==.Horsebananas:BAAANQAECggIEgAAAA==.',
Hu='Huddington:BAABNQAECn8eAAIRAAoKzgkjlABqAQARAAoKzgkjlABqAQAAAA==.',
Hy='Hyperion:BAABNQAECn8YAAIUAAkKzRlMEACqAgAUAAkKzRlMEACqAgAAAA==.',
Ig='Igknight:BAAANQAECgcIDQABNQAECgoKNwACAGkXAA==.',
Il='Ilsi:BAAANQADCgYIBgABNQAECgoKJwAIAKAdAA==.',
Im='Impthrower:BAAANQAECgIIAgABNQADCgYJDwAXAAAAAA==.',
In='Indecent:BAABNQAECn8tAAMjAAoKtBtTNQArAgAjAAoKdBtTNQArAgAiAAIKHxusTQCWAAAAAA==.Indeed:BAAANQAECggICQAAAA==.Indree:BAAANQAECgQIBAAAAA==.Inibble:BAAANQABCgUICAAAAA==.',
Iq='Iqfbeef:BAAANQADCgYICgAAAA==.',
Is='Ishy:BAABNQAECn8wAAMRAAkK7xosZgCyAgARAAkK7xosZgCyAgAmAAMKLAuZCABrAAAAAA==.',
Iw='Iwannalive:BAAANQADCgIIAgAAAA==.',
Iz='Izziey:BAAANQADCgEIAQAAAA==.',
Ja='Jack:BAABNQAECn8kAAQbAAoKNRlkIgAhAgAbAAgKQxZkIgAhAgAQAAcKqhDVjwBnAQAlAAMKURWSFwC5AAAAAA==.Jackieblaze:BAAANQAECgUICgABNQAFFAUICAAlAIQTAA==.Jackieplays:BAACNQAFFH8IAAQlAAUKhBPdAgCIAAAQAAIKChhGJQCiAAAbAAIK5AnCDwCJAAAlAAIK7QvdAgCIAAA1AAQKfz0ABCUACgo5IF8DAL4CACUACAqNHl8DAL4CABAACgqiHMs5AIICABsAAQo2DCp6ADQAAAAA.Jaded:BAABNQAECn8uAAMnAAoKsRyTHwCrAgAnAAoKsRyTHwCrAgAIAAMKjwrPAAGPAAAAAA==.Jandexx:BAAANQADCgMIAwAAAA==.',
Je='Jeses:BAABNQAECn8VAAMSAAoKdRQLKQCUAQASAAoKdRQLKQCUAQAGAAEKUgqafwE6AAAAAA==.Jessa:BAAANQADCgQIBAAAAA==.',
Jo='Jollah:BAABNQAECn8XAAQNAAcKqhUuLQACAQANAAUKjg8uLQACAQATAAYKchMXMgD2AAAkAAEKAAB8MAA6AAAAAA==.Jorawa:BAAANQAECgUIBQAAAA==.',
Ju='Jurassic:BAAANQADCgYIBgAAAA==.Jutic:BAABNQAECn9BAAInAAoKTiMoDQBXAwAnAAoKTiMoDQBXAwAAAA==.',
Ka='Kageken:BAAANQADCgQIBAABNQADCgYJEQAXAAAAAA==.Kaithul:BAAANQABCgQIAwAAAA==.Kardas:BAABNQAECn8hAAIEAAgKuAhQugCPAQAEAAgKuAhQugCPAQAAAA==.',
Kb='Kbilly:BAABNQAECn89AAInAAoK7x45GwDJAgAnAAoK7x45GwDJAgAAAA==.',
Ke='Kentarou:BAAANQABCgUIBQAAAA==.Keylerin:BAACNQAFFH8PAAIVAAYKahYXCwBCAQAVAAYKahYXCwBCAQA1AAQKfyoAAhUACgqJHjwIAPYCABUACgqJHjwIAPYCAAAA.',
Ki='Kiikee:BAAANQADCgQIBwAAAA==.Kimosabi:BAAANQABCgIIAgAAAA==.Kitto:BAAANQADCgYJBgAAAA==.Kittvulpy:BAAANQADCgYICgAAAA==.',
Kl='Klausinator:BAAANQAECgEIAQAAAA==.',
Kn='Knottes:BAAANQAECgIIAwAAAA==.',
Ko='Komos:BAAANQAECgEIAQAAAA==.',
Kr='Krampus:BAABNQAECn8wAAIcAAoKuQtdEwDGAQAcAAoKuQtdEwDGAQAAAA==.Kranok:BAABNQAECn8hAAIFAAgKLhAhHwBjAQAFAAgKLhAhHwBjAQAAAA==.Krennthis:BAAANQAECgUIBQAAAA==.Krimbruiser:BAAANQADCgYIBwABNQAECgEIBAAXAAAAAA==.Krimhuntress:BAAANQADCgYIBgAAAA==.',
Ku='Kunac:BAAANQADCgYIEAAAAA==.',
Ky='Kyran:BAAANQADCgUIBwAAAA==.Kyrun:BAABNQAECn8bAAIcAAcKzAlmHgAfAQAcAAcKzAlmHgAfAQAAAA==.Kytrina:BAAANQADCgIIAgAAAA==.',
La='Lactoes:BAAANQADCgYIBgAAAA==.Lamoran:BAAANQAECgUICgAAAA==.',
Le='Lemón:BAAANQAECgEIAgAAAA==.',
Lh='Lhani:BAABNQAECn8vAAIQAAkKUhJoVQDPAQAQAAkKUhJoVQDPAQAAAA==.',
Li='Lilguysci:BAAANQAECgMIBAAAAA==.Lizord:BAABNQAECn8dAAIOAAoKkhK8DAA8AgAOAAoKkhK8DAA8AgAAAA==.',
Ll='Llothien:BAAANQAECgIIAgAAAA==.Llyrael:BAABNQAECn80AAMQAAoKQAchbgB6AQAQAAoKQAchbgB6AQAbAAEK2gILhAAlAAAAAA==.',
Lo='Lonard:BAAANQAECgIIAgAAAA==.',
Lu='Lugosi:BAAANQAECgEIAQAAAA==.',
Ly='Lyfe:BAAANQABCgUIBwAAAA==.',
Ma='Machlain:BAAANQADCgQIBAABNQAECggIIQASAAkcAA==.Maddeleine:BAAANQADCgYIEwAAAA==.Magara:BAAANQAECgQIBAAAAA==.Magicdemon:BAABNQAECn87AAIKAAoKOyVhBwAVAwAKAAoKOyVhBwAVAwAAAA==.Magichunter:BAAANQAECggIEgABNQAECgoKOwAKADslAA==.Magicpaladin:BAABNQAECn8UAAIGAAkKHhtePABnAgAGAAkKHhtePABnAgABNQAECgoKOwAKADslAA==.Magicshaman:BAAANQAECgYIEQABNQAECgoKOwAKADslAA==.Magnafratrem:BAAANQAECgQICAAAAA==.Makall:BAAANQABCgQIBAAAAA==.Malaah:BAABNQAECn8iAAIIAAkKCBD0dwC6AQAIAAkKCBD0dwC6AQAAAA==.Mansuno:BAABNQAECn8/AAMGAAkKfxmAVAAfAgAGAAkKfxmAVAAfAgACAAcKTQx/cgBKAQAAAA==.Mapachote:BAABNQAECn8oAAIFAAgKuBIVFgDTAQAFAAgKuBIVFgDTAQAAAA==.Marodin:BAAANQADCggIQwAAAA==.Maynor:BAAANQABCggIFQAAAA==.Mazboda:BAABNQAECn84AAQjAAgKJBcxaQCHAQAjAAgKvBYxaQCHAQAhAAMKCRAXHgCKAAAiAAIKugg3ZABcAAAAAA==.',
Me='Meatbaal:BAAANQAECgUIDQAAAA==.Medïc:BAAANQADCggICAAAAA==.Melinaria:BAABNQAECn8lAAMbAAgKdBclJgD9AQAbAAgKdBclJgD9AQAlAAEK2w4PFgBAAAAAAA==.Merewene:BAAANQAECgUIEwAAAA==.Merkabai:BAAANQADCgIIAgAAAA==.',
Mi='Mileta:BAABNQAECn85AAIMAAoKCRzTHADiAgAMAAoKCRzTHADiAgAAAA==.Minuette:BAAANQAECgMIAwAAAA==.',
Mo='Montblanc:BAAANQAECgQIBAABNQAECgUICgAXAAAAAA==.Moonwatcher:BAAANQADCgQIBAABNQAFFAQICAAQAKoSAA==.Morgnox:BAAANQAECgIIAgAAAA==.',
Mu='Murdercookie:BAAANQAECgEIAQAAAA==.',
Na='Nazgul:BAAANQADCgcICAAAAA==.',
Ne='Necrokrim:BAAANQAECgEIBAAAAA==.Necronic:BAAANQAECgIIAwAAAA==.Necronight:BAAANQAECgMIAwAAAA==.Necroreign:BAABNQAECn9LAAIKAAoKzBwWEQCSAgAKAAoKzBwWEQCSAgAAAA==.Need:BAAANQAECgIIAgAAAA==.Neherenia:BAABNQAECn8yAAIfAAoK2hQmJgARAgAfAAoK2hQmJgARAgAAAA==.Nervous:BAAANQAECggIAgABNQAECgoKFgACAIMMAA==.Nessee:BAABNQAECn8XAAIgAAcKnAviHgDzAAAgAAcKnAviHgDzAAAAAA==.',
Ni='Niall:BAAANQAECgEIAgAAAA==.Nightfire:BAAANQABCgcIEwAAAA==.Nihowdy:BAABNQAECn9AAAIoAAoKLiJXAQB/AwAoAAoKLiJXAQB/AwAAAA==.',
No='Norrin:BAAANQABCggIDgAAAA==.',
Oc='Octalexane:BAAANQADCgYIBgABNQAECggIIQABACEQAA==.',
Od='Odelagt:BAAANQAECggICgAAAA==.',
On='Onimusha:BAAANQAECgEIAQAAAA==.',
Or='Orci:BAABNQAECn8sAAIiAAgKnQ1YCQAfAQAiAAgKnQ1YCQAfAQAAAA==.Orryn:BAAANQABCgIIAgAAAA==.Ortalbem:BAABNQAECn9KAAMRAAoKzh0hOQBWAgARAAoKQx0hOQBWAgAgAAkKvRt4DQChAQAAAA==.',
Ou='Oulli:BAAANQABCggIHwAAAA==.',
Ov='Ovi:BAAANQAECgUICwAAAA==.',
Pa='Painthuffer:BAABNQAECn8iAAMVAAoKxBSaLQA0AgAVAAkKUROaLQA0AgAWAAoK9xB7MAAgAgABNQAECgoKMAARAN0YAA==.Paramour:BAAANQAECgIIAgAAAA==.Pazuuzu:BAAANQAECgEIAQAAAA==.',
Pe='Peddles:BAAANQAECgUIDQAAAA==.Petmedaddy:BAAANQAECgEIAQAAAA==.',
Ph='Pherix:BAABNQAECn86AAIbAAoKQx/oDAB7AgAbAAoKQx/oDAB7AgAAAA==.Philipfry:BAABNQAECn9GAAMCAAoKxBMBTgAyAgACAAoKxBMBTgAyAgAGAAcKbBjDjgCZAQAAAA==.Phill:BAAANQADCgcIEgAAAA==.Phuuta:BAAANQAECgMIBAAAAA==.',
Pl='Plaguetusk:BAAANQADCgQIBAAAAA==.',
Po='Pontoon:BAAANQAECgUIBQAAAA==.Poomacha:BAAANQAECgUIEQAAAA==.Potatopants:BAAANQAECgEIAgAAAA==.',
Pr='Prinlina:BAAANQADCggIDQAAAA==.Proeliator:BAAANQADCgIIAgAAAA==.',
Py='Pyree:BAABNQAECn8uAAIdAAoKmwwLDQBrAQAdAAoKmwwLDQBrAQAAAA==.',
Ra='Radimus:BAAANQAECgEIAQAAAA==.Raenne:BAAANQADCgMIAwAAAA==.Rainvelle:BAAANQADCgQIBAAAAA==.Raistlain:BAABNQAECn8fAAIbAAgKwRQKJgD+AQAbAAgKwRQKJgD+AQAAAA==.Ralli:BAABNQAECn8/AAMYAAoKFh8PCgCpAgAKAAkKxBq9FgDmAgAYAAoK/h0PCgCpAgAAAA==.Ralls:BAAANQAECgYIBwABNQAECgcIDAAXAAAAAA==.Rallsdk:BAAANQADCgYIBgABNQAECgcIDAAXAAAAAA==.Rallsodins:BAAANQAECgcIDAAAAA==.Ranulf:BAAANQAECgQIEAAAAA==.Ratava:BAAANQAECgYIDwAAAA==.Ratrot:BAAANQADCggICQAAAA==.Raztar:BAAANQADCgUIBQAAAA==.',
Re='Reddemon:BAAANQAECggIEgAAAA==.Rehvenge:BAAANQAECgMIAwAAAA==.Rekarra:BAAANQADCgcIBwAAAA==.Reks:BAAANQAECgUICQAAAA==.Reldarus:BAEBNQAECn8wAAQlAAoKCSP4AgDVAgAlAAcK1CP4AgDVAgAQAAoK3xtlSQBKAgAbAAEK9BWCcABHAAAAAA==.Rena:BAABNQAECn8qAAQdAAoKKhLQEgD2AAAdAAcKJwrQEgD2AAAOAAMKywOyLQB5AAAPAAQKxQNkHQB5AAAAAA==.Revilation:BAABNQAECn8kAAISAAkKIBTrHAAEAgASAAkKIBTrHAAEAgAAAA==.Rezjyk:BAAANQADCgYIBgABNQAECgkJPwAGAKgbAA==.Rezzyk:BAABNQAECn8/AAIGAAkKqBvUWAAUAgAGAAkKqBvUWAAUAgAAAA==.',
Rh='Rhyxali:BAAANQAECgUIEgAAAA==.',
Ri='Riibirth:BAAANQADCgYIBgAAAA==.Riis:BAAANQADCgEIAQAAAA==.',
Ru='Ruknan:BAAANQADCgQIBAABNQAECgoKQQAYAOcUAA==.',
Ry='Rygelon:BAAANQAECgQICQAAAA==.',
Sa='Sableanne:BAAANQAECgQICAAAAA==.Sacredscales:BAAANQADCgMJAwAAAA==.Samvimes:BAAANQAECgIIBQAAAA==.Sangreene:BAABNQAECn8xAAIbAAoKxRtlCwCWAgAbAAoKxRtlCwCWAgAAAA==.Sargis:BAABNQAECn9SAAMGAAoK2iHHGAD4AgAGAAoK2iHHGAD4AgACAAgKbBZuaADeAQAAAA==.',
Sc='Schrödinger:BAAANQAECgEIAQABNQAECgkJGAAUAM0ZAA==.Scott:BAAANQAECgQIBAAAAA==.',
Se='Selira:BAAANQAECgcICgABNQAECgoKLgARAGMQAA==.Serissa:BAAANQAECgIIAgAAAA==.Serjankins:BAAANQADCgQIBAAAAA==.Setsuna:BAAANQABCgYIDAABNQAECgoKIAAbAGYeAA==.',
Sh='Shadowgiver:BAAANQADCgcICwAAAA==.Shagol:BAABNQAECn8jAAIQAAcKQhkRbACBAQAQAAcKQhkRbACBAQAAAA==.Shaidic:BAAANQAECgYIDAAAAA==.Shamemoon:BAAANQAECgEJAQABNQAECggIFwAjAGAMAA==.Shamunroe:BAABNQAECn8xAAMIAAoKsBebUwArAgAIAAoKsBebUwArAgAnAAUK1Aow1gC6AAAAAA==.Shatterhoof:BAABNQAECn8YAAILAAcKRg19HQD9AAALAAcKRg19HQD9AAAAAA==.Shelle:BAAANQAECgMIAwAAAA==.Shiftysmage:BAAANQAECgEIBAABNQAECgoKIQAZAOAUAA==.Shingra:BAACNQAFFH8LAAIPAAQKEhMCBwD3AAAPAAQKEhMCBwD3AAA1AAQKfyMAAg8ACQrKFjoGAGoCAA8ACQrKFjoGAGoCAAAA.Shockdragon:BAAANQAECgMIAQAAAA==.Shores:BAAANQABCgIIAQAAAA==.Shylindra:BAAANQAECgQIBAAAAA==.',
Si='Sigourney:BAAANQAECgYIDwABNQAECggIEgAXAAAAAA==.Silversho:BAAANQAECgUIBQAAAA==.Silvren:BAAANQADCgIIAgAAAA==.',
Sk='Skill:BAABNQAECn8cAAMUAAgKghKIKgDKAQAUAAgKghKIKgDKAQAMAAQKRw6wegDgAAAAAA==.',
Sl='Slighttrash:BAAANQAECgUIDQAAAA==.',
Sm='Smallcrow:BAABNQAECn8bAAMTAAkKbR40FwCSAgATAAgKbR40FwCSAgANAAQK0Q1HMwDQAAAAAA==.',
So='Somdot:BAEBNQAECn9OAAIbAAoK/yBpCABWAwAbAAoK/yBpCABWAwAAAA==.Somedeekay:BAAANQAECgYIDgAAAA==.',
Sp='Spirit:BAABNQAECn8VAAMOAAgKFRrtEQCNAgAOAAgKFRrtEQCNAgAdAAEKCwjLQQAmAAABNQAFFAMIBQAWAIEMAA==.',
Sq='Squirrellock:BAAANQAECgEIAgAAAA==.',
St='Starga:BAAANQADCgQIBAAAAA==.Starge:BAAANQADCgUIBQAAAA==.Starre:BAAANQADCgQIBAAAAA==.Steffey:BAAANQAECgYIEwAAAA==.Stepbro:BAAANQADCgcIDAAAAA==.Stoikk:BAABNQAECn8UAAIIAAcK3hCPkQB4AQAIAAcK3hCPkQB4AQAAAA==.Straven:BAABNQAECn8bAAIgAAgKjhNaEAChAQAgAAgKjhNaEAChAQAAAA==.Sturgeson:BAACNQAFFH8VAAIBAAYKqxmPAQAwAQABAAYKqxmPAQAwAQA1AAQKfy0AAgEACQp1IW4JALUCAAEACQp1IW4JALUCAAAA.',
Su='Suffocation:BAEANQAECgYIBgABNQAFFAkJJwAiAGUfAA==.Sulwen:BAABNQAECn8lAAIQAAoKxhPLXgAFAgAQAAoKxhPLXgAFAgAAAA==.Sundance:BAAANQADCgUIBQAAAA==.Sunray:BAAANQAECgUIBgAAAA==.',
Sw='Swiftfeet:BAABNQAECn8mAAIEAAkKuxXplADeAQAEAAkKuxXplADeAQAAAA==.',
['Sé']='Sésho:BAAANQADCgQIBgAAAA==.',
['Sö']='Söranin:BAAANQAECgMIBAAAAA==.',
['Sø']='Sømdøt:BAEANQAECggIDAABNQAECgoKTgAbAP8gAA==.',
Ta='Taeili:BAABNQAECn8cAAIZAAgK1BY6FwD5AQAZAAgK1BY6FwD5AQAAAA==.Taeror:BAAANQADCgQIBAAAAA==.Tanequil:BAACNQAFFH8IAAIUAAUKNAP+CQAHAQAUAAUKNAP+CQAHAQA1AAQKfzYAAhQACgpjD/spAM8BABQACgpjD/spAM8BAAAA.',
Te='Techromancer:BAABNQAECn8tAAMJAAoKlhopKgCPAgAJAAoKeRYpKgCPAgAfAAgKnhkoJAAdAgABNQAECgoKOgAbAEMfAA==.Tem:BAAANQABCgQIBAABNQADCgcIDgAXAAAAAA==.',
Th='Thanatias:BAAANQAECgYIDAAAAA==.Thantasia:BAAANQAECgMIAwAAAA==.Theakunda:BAAANQAECgcIEAAAAA==.Theodis:BAAANQAECgQIBQAAAA==.Thistlebrew:BAAANQAECgQIBAAAAA==.Thokdar:BAAANQAECgQIBQAAAA==.',
Ti='Tifà:BAAANQAECgIIAgAAAA==.Tillago:BAAANQADCggICgAAAA==.Timothy:BAAANQAECgYICwAAAA==.Timothyjohn:BAAANQAECgYIDwAAAA==.Tinkphooey:BAAANQAECgMIBAAAAA==.Tirianna:BAAANQADCgEIAQABNQAFFAQICAAQAKoSAA==.Tituba:BAABNQAECn88AAIjAAoKbBrmMgA1AgAjAAoKbBrmMgA1AgAAAA==.',
To='Toklore:BAAANQADCgcIDgAAAA==.Tonepavone:BAAANQADCgYIBgAAAA==.Tormmok:BAAANQADCgQIBAAAAA==.',
Tr='Traazz:BAAANQADCgYICgAAAA==.Trey:BAAANQAECgcIDAAAAA==.Trior:BAAANQAECgQIBQAAAA==.',
Ts='Tsuruga:BAABNQAECn8nAAIkAAoKPAYbDgAyAQAkAAoKPAYbDgAyAQAAAA==.',
Tu='Turkwise:BAABNQAECn9CAAQZAAoKcRBsIwB7AQAZAAkKug5sIwB7AQALAAgKqQ+AHAA+AQAUAAQKwgRyYABhAAAAAA==.',
Uc='Ucallmesam:BAAANQAECgUIBQAAAA==.',
Ul='Ulodude:BAAANQADCgYIBgAAAA==.',
Un='Unholydiddy:BAAANQADCggICQAAAA==.',
Ur='Urobolos:BAAANQAECgMIAwAAAA==.',
Uv='Uvari:BAABNQAECn8ZAAIQAAkKEhKuagCFAQAQAAkKEhKuagCFAQAAAA==.',
Va='Vacalaca:BAABNQAECn8XAAMjAAgKYAzpegBYAQAjAAgKYAzpegBYAQAiAAEK9AGjhwAeAAAAAA==.Valany:BAAANQADCgIIAgAAAA==.Valkira:BAACNQAFFH8IAAIcAAUKlgwDBADTAAAcAAUKlgwDBADTAAA1AAQKfzYAAxwACgpNHSIPAHgCABwACgptHCIPAHgCAAgABgpxGVSLAIgBAAAA.Valton:BAACNQAFFH8FAAITAAMKRRfdCQDJAAATAAMKRRfdCQDJAAA1AAQKf0QAAhMACgqbJcEDAJkDABMACgqbJcEDAJkDAAAA.Vancede:BAAANQAECgQIBwABNQAECgkJJwAYACsUAA==.Vanillanice:BAAANQADCgMJBAAAAA==.Varrfife:BAAANQABCgIJAgAAAA==.Vaxaldan:BAABNQAECn8vAAIeAAoKoQ5iLACVAQAeAAoKoQ5iLACVAQAAAA==.',
Ve='Velindsong:BAAANQADCggICAAAAA==.Venj:BAAANQAECgIIAgAAAA==.Ventosa:BAACNQAFFH8HAAInAAQKsQrzFQDsAAAnAAQKsQrzFQDsAAA1AAQKfzgAAicACgqSHBg6AHYCACcACgqSHBg6AHYCAAAA.Vex:BAAANQAECgIIBgAAAA==.',
Vi='Vilox:BAAANQADCgIIAgAAAA==.Viltex:BAAANQADCgYICwAAAA==.Vilxten:BAAANQAECgUICQAAAA==.Virtues:BAAANQAECgEIAQAAAA==.',
Vo='Voidleader:BAABNQAECn8mAAIQAAkKnA82cABzAQAQAAkKnA82cABzAQAAAA==.Vostok:BAABNQAECn8mAAIjAAgKuRDujADHAQAjAAgKuRDujADHAQAAAA==.',
Vy='Vylleria:BAAANQADCgYIBgAAAA==.',
['Vá']='Váyne:BAAANQAECgEIAQABNQAECgYICwAXAAAAAA==.',
Wa='Warralok:BAAANQADCgYIBgAAAA==.Warramag:BAAANQAECgYICgAAAA==.Warranni:BAABNQAECn8vAAIIAAoKPB2uKADeAgAIAAoKPB2uKADeAgAAAA==.',
We='Weekend:BAABNQAECn8mAAIIAAoK7g9VQwCvAQAIAAoK7g9VQwCvAQAAAA==.',
Wh='Whatafox:BAABNQAECn8kAAMIAAkKjxxpTABFAgAIAAcKRB1pTABFAgAnAAYKEBAC1QC9AAAAAA==.Whittail:BAAANQABCggIFgAAAA==.',
Wi='Wikket:BAABNQAECn81AAIMAAoK6xBrJgC1AQAMAAoK6xBrJgC1AQAAAA==.',
Wo='Wortel:BAAANQADCgYIBgAAAA==.',
Wy='Wyelie:BAABNQAECn8ZAAMSAAkK3gzePAANAQASAAcKqQzePAANAQAGAAMK4Qq7HwGmAAAAAA==.',
Xa='Xade:BAABNQAECn9LAAIVAAoKzR3rGQClAgAVAAoKzR3rGQClAgAAAA==.Xandendon:BAABNQAECn8XAAIJAAkKtw0KWACwAQAJAAkKtw0KWACwAQAAAA==.',
Xe='Xerond:BAABNQAECn8XAAIpAAgKTwWsHQCpAAApAAgKTwWsHQCpAAAAAA==.Xevin:BAABNQAECn8nAAIIAAoKoB0uOwCJAgAIAAoKoB0uOwCJAgAAAA==.',
Xo='Xotha:BAAANQAECgYIBgAAAA==.',
Ya='Yaákov:BAABNQAECn9BAAIYAAoK5xSEGQDQAQAYAAoK5xSEGQDQAQAAAA==.',
Yi='Yinosai:BAAANQAECgEIAQAAAA==.',
Yo='Yougot:BAAANQADCggIDwAAAA==.',
Za='Zademedic:BAAANQAECgQIBgAAAA==.Zanarkin:BAAANQAECgEIAQAAAA==.Zanedore:BAAANQABCggIEwAAAA==.Zaranji:BAAANQADCgYIBgAAAA==.Zarisedra:BAACNQAFFH8SAAMCAAYKwAwmCwCCAQACAAYKwAwmCwCCAQAGAAEKcAo3MAA+AAA1AAQKfywAAwIACgoaHJcmAM8CAAIACgoaHJcmAM8CAAYAAQoAAAjeARIAAAAA.Zarissena:BAABNQAECn8aAAIJAAgKwwQdSQDTAAAJAAgKwwQdSQDTAAAAAA==.Zarmina:BAAANQADCgEIAQAAAA==.Zarris:BAAANQABCgYIBAAAAA==.',
Ze='Zerdah:BAAANQADCgcIEwAAAA==.Zerogasm:BAAANQAECgMIAwAAAA==.Zerolicious:BAAANQAECgMJAwAAAA==.Zeroprophecy:BAAANQAECgIIAgAAAA==.Zevvo:BAABNQAECn8tAAIHAAoK1x57OABQAgAHAAoK1x57OABQAgAAAA==.',
Zo='Zoeybear:BAAANQAECgMIBAAAAA==.Zoraji:BAABNQAECn86AAIkAAoKIh7UAwBKAwAkAAoKIh7UAwBKAwAAAA==.',
['Év']='Évangeline:BAAANQAECgUIDAAAAA==.',
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
