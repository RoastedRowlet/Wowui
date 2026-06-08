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

local lookup = {'Shaman-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Unknown-Unknown','Druid-Restoration','Evoker-Preservation','Evoker-Devastation','Paladin-Retribution','DeathKnight-Unholy','Priest-Shadow','Druid-Balance','Warlock-Demonology','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Priest-Holy','Warrior-Fury','DeathKnight-Blood','Paladin-Holy','Mage-Frost','Shaman-Elemental','DemonHunter-Devourer','Warlock-Affliction','Shaman-Enhancement','DemonHunter-Havoc','DeathKnight-Frost','Monk-Mistweaver','DemonHunter-Vengeance','Warlock-Destruction','Warrior-Arms','Priest-Discipline','Mage-Fire','Warrior-Protection','Hunter-Survival','Rogue-Subtlety','Monk-Brewmaster','Rogue-Assassination','Monk-Windwalker','Rogue-Outlaw','Paladin-Protection','Mage-Arcane',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=46,date='2026-06-07',data={Ad='Addisyn:BAAALgAECgEJBAAAAA==.',
Ae='Aekal:BAAALgAECgUJBQAAAA==.Aemetris:BAABLgAECn8UAAIBAAYJ4Rn4OQC7AQABAAYJ4Rn4OQC7AQAAAA==.Aenicus:BAAALgADCgcJBwAAAA==.Aerina:BAAALgAECgQJCwAAAA==.Aethra:BAAALgADCgYJBgAAAA==.',
Ag='Agamotto:BAAALgAECgYJCgAAAA==.Agromagnetic:BAAALgAECgUJBgAAAA==.Agytha:BAAALgAECgMJAwAAAA==.Agøny:BAAALgADCgMJAwAAAA==.',
Ai='Aidendawn:BAAALgAECgQJCQAAAA==.',
Aj='Ajheria:BAAALgADCgcJCAAAAA==.',
Al='Alukart:BAAALgAECgEJAgAAAA==.',
Am='Ameildoran:BAAALgADCgkJCQAAAA==.',
An='Anaru:BAAALgAECgMJBgAAAA==.Anatyriel:BAAALgADCgEJAQAAAA==.Anayanci:BAAALgADCgUJBgAAAA==.Andalaine:BAAALgAECgMJBQAAAA==.Andari:BAAALgADCgEJAQAAAA==.Andramaedra:BAAALgAECgkJAgAAAA==.Anoobornot:BAAALgADCgMJAwAAAA==.Anraleth:BAACLgAFFH8NAAICAAQJPiPFCwCSAQACAAQJPiPFCwCSAQAuAAQKfzwAAwIACQkLJcYCALACAAIACAnnJMYCALACAAMAAQkGJlftAGYAAAAA.',
Ap='Aponi:BAAALgAECgQJBwAAAA==.',
Ar='Arckillion:BAAALgADCgkJCQAAAA==.Ardour:BAAALgAECgMJBgABLgAECgcJEwAEAAAAAA==.Arduous:BAAALgAECgMJAwAAAA==.Arihu:BAABLgAECn8fAAIFAAkJlxSSLQDoAQAFAAkJlxSSLQDoAQAAAA==.Arkhana:BAAALgADCgEJAQAAAA==.',
As='Ashenaya:BAABLgAECn8YAAMGAAgJLxn9CwARAgAGAAgJLxn9CwARAgAHAAEJMQpQQgArAAAAAA==.Asparagus:BAABLgAECn8ZAAIIAAgJpQ76egBuAQAIAAgJpQ76egBuAQAAAA==.',
At='Atlass:BAACLgAFFH8GAAIJAAIJLhV8wwCRAAAJAAIJLhV8wwCRAAAuAAQKfxgAAgkABwnxGYtjAMkBAAkABwnxGYtjAMkBAAAA.Atrest:BAAALgAECgYJBwAAAA==.',
Au='Augmenter:BAAALgAECgQJBQABLgAFFAcJHgAKAGAaAA==.Aust:BAABLgAECn8UAAIIAAgJ6hOfZgCYAQAIAAgJ6hOfZgCYAQAAAA==.',
Av='Averlin:BAAALgAECgMJAwAAAA==.Averlis:BAABLgAECn8eAAILAAgJnhXKHgDGAQALAAgJnhXKHgDGAQAAAA==.Avoiddance:BAAALgADCgEJAQAAAA==.',
Ax='Axee:BAAALgADCgYJBgAAAA==.',
Az='Azima:BAAALgADCggJCAAAAA==.Azura:BAAALgADCgIJAgAAAA==.Azurargentyr:BAAALgAECgkJEAAAAA==.',
Ba='Babeolicious:BAAALgADCgEJAQAAAA==.Bacon:BAABLgAECn8lAAIIAAkJzAoifwBmAQAIAAkJzAoifwBmAQAAAA==.Bambøøze:BAAALgADCgEJAQAAAA==.Bandadi:BAEBLgAECn8wAAIMAAgJox9tFQDVAgAMAAgJox9tFQDVAgAAAA==.Barbelo:BAAALgAECgcJCgAAAA==.Barely:BAAALgAECggJDwAAAA==.Barkweldort:BAAALgAECgYJEQAAAA==.Barreled:BAAALgADCgMJAwAAAA==.Batistabomba:BAAALgAECgYJBgAAAA==.',
Be='Beargruk:BAAALgAECgUJBwAAAA==.Beastly:BAAALgAECggJEQAAAA==.Beeble:BAAALgAECgYJEgAAAA==.Belii:BAAALgAECgYJDAAAAA==.Bended:BAAALgADCgIJAgAAAA==.Bepisthepall:BAAALgAECgEJAgAAAA==.Betterkevin:BAAALgAECgQJDwAAAA==.Bezerkachew:BAAALgAECgEJAgAAAA==.',
Bi='Bigbooty:BAABLgAECn8dAAMNAAcJDQdNQACSAAANAAcJ6wVNQACSAAAOAAQJwAYFPABaAAAAAA==.Bigbootyjudi:BAAALgAECgEJAQAAAA==.',
Bl='Blikey:BAABLgAFFH8GAAIJAAIJfiY4rAC1AAAJAAIJfiY4rAC1AAAAAA==.Bloodyrott:BAAALgAECgUJCgAAAA==.Bluedrake:BAACLgAFFH8NAAMHAAQJ1BusAgBRAQAHAAQJ1BusAgBRAQAPAAEJPRPNXQBAAAAuAAQKfyMAAwcACAlfHr4EALoCAAcACAmGHb4EALoCAA8ACAk9FlIZAAMCAAEuAAUUBQkTAAsAwyIA.Blueparrot:BAABLgAECn8yAAIQAAgJpBQuGgDsAQAQAAgJpBQuGgDsAQAAAA==.Bluy:BAAALgADCgMJAwAAAA==.Blädèstorm:BAABLgAECn8ZAAIRAAgJphxGIgDaAQARAAgJphxGIgDaAQAAAA==.',
Bo='Bonesnap:BAACLgAFFH8UAAMJAAYJdiO9IwC+AQAJAAUJdiO9IwC+AQASAAEJAABGTQAAAAAuAAQKfyAAAwkACQmrIaMXAO4CAAkACQmrIaMXAO4CABIABAmuE487AJkAAAAA.Bowkatan:BAAALgAECgEJAgAAAA==.',
Br='Brianisita:BAAALgAECgUJBgAAAA==.Brightmane:BAABLgAECn8WAAITAAYJUx4zJQD8AQATAAYJUx4zJQD8AQAAAA==.Bringinlight:BAAALgAECgYJDQAAAA==.',
Bu='Bubbleicious:BAAALgAECgYJEgAAAA==.Bubbletea:BAAALgAECgcJEQABLgAECgkJLAADAMkjAA==.Bulletz:BAABLgAECn8eAAICAAgJ7x2aBABeAgACAAgJ7x2aBABeAgAAAA==.Bumpersnouts:BAAALgADCgcJBwAAAA==.Buttfur:BAAALgADCgYJBgAAAA==.',
['Bê']='Bêarwithme:BAAALgAECgIJBQABLgAECgcJGwAKAF8RAA==.',
Ca='Caenzo:BAAALgADCgkJCgAAAA==.Casanna:BAAALgADCgYJBgAAAA==.Cassandria:BAABLgAECn8sAAMFAAgJBxCpUgA8AQAFAAcJqw6pUgA8AQALAAgJ2AxkOAAmAQAAAA==.Cassiradra:BAAALgADCgEJAQAAAA==.Caylastus:BAAALgAECgEJAQAAAA==.',
Ce='Cearas:BAAALgAECgEJAQAAAA==.Cedrick:BAAALgAECgUJBQAAAA==.Celiona:BAAALgAECgkJBwAAAA==.Celody:BAAALgAECgYJDAAAAA==.Celticsinsix:BAAALgAECgMJBQAAAA==.Cervixticklr:BAAALgAECgEJAQAAAA==.',
Ch='Chaoten:BAAALgADCgEJAQAAAA==.Chathlia:BAAALgAECgQJBAAAAA==.Chavdar:BAAALgADCgEJAQAAAA==.Chewster:BAABLgAECn81AAIUAAgJJhCabwCWAQAUAAgJJhCabwCWAQAAAA==.Chixie:BAAALgADCgEJAQAAAA==.Choal:BAABLgAECn8VAAIFAAYJuQ1EXwAQAQAFAAYJuQ1EXwAQAQAAAA==.Choglana:BAAALgAECgcJCQAAAA==.Chogli:BAAALgAECgEJAQABLgAECgcJCQAEAAAAAA==.Chogric:BAABLgAECn84AAMTAAkJhh+NBQATAwATAAkJhh+NBQATAwAIAAQJZw1tGQGMAAABLgAECgcJCQAEAAAAAA==.',
Ci='Civetta:BAABLgAECn8WAAIDAAkJhwzfSwCzAQADAAkJhwzfSwCzAQAAAA==.',
Cl='Clannininick:BAAALgADCgUJBgAAAA==.Clark:BAAALgADCgEJAQAAAA==.',
Co='Cogswell:BAAALgADCgIJAgAAAA==.Comespankit:BAAALgAECgUJBQAAAA==.Constiua:BAAALgAECgcJBwABLgAECgcJCQAEAAAAAA==.Convalesor:BAABLgAECn8UAAIKAAYJQQg9SwDaAAAKAAYJQQg9SwDaAAAAAA==.',
Cr='Crazzywazzy:BAABLgAFFH8KAAIJAAQJcBhtXAAxAQAJAAQJcBhtXAAxAQAAAA==.Crona:BAABLgAECn8aAAITAAkJtg4LPACJAQATAAkJtg4LPACJAQAAAA==.Crsteel:BAAALgAECgEJAQAAAA==.Crzyblnkrton:BAACLgAFFH8PAAIUAAYJthBTPQBqAQAUAAYJthBTPQBqAQAuAAQKfxcAAhQACAnmH2k5AJACABQACAnmH2k5AJACAAAA.Crzzy:BAABLgAFFH8IAAIVAAcJKA61DwCVAQAVAAcJKA61DwCVAQAAAA==.',
Cu='Cuddlez:BAABLgAECn8gAAIQAAkJGQtKKwBkAQAQAAkJGQtKKwBkAQAAAA==.Cultera:BAACLgAFFH8LAAIWAAQJWhIsQQAWAQAWAAQJWhIsQQAWAQAuAAQKfxkAAhYACAlUHN4zAOwBABYACAlUHN4zAOwBAAAA.',
Cy='Cyhyraethia:BAABLgAECn8fAAIXAAgJDB+sBQANAgAXAAgJDB+sBQANAgABLgAECgkJOAAWAEEaAA==.Cyndera:BAAALgADCgEJAQAAAA==.',
Da='Dagden:BAAALgADCgYJCAAAAA==.Dalaa:BAAALgAECgIJAgAAAA==.Dammnation:BAAALgAECgYJBwABLgAECgcJGwAKAF8RAA==.Danda:BAAALgAECgYJCgAAAA==.Daricepicker:BAABLgAECn8sAAIDAAkJySNPBQA3AwADAAkJySNPBQA3AwAAAA==.Darkyn:BAABLgAECn8ZAAIMAAkJPRB0QwDLAQAMAAkJPRB0QwDLAQAAAA==.Davedadude:BAABLgAECn8wAAIIAAkJEyL6CgAHAwAIAAkJEyL6CgAHAwAAAA==.',
Dd='Ddeonu:BAAALgAECgEJAQAAAA==.Ddeonuu:BAABLgAFFH8LAAMCAAUJPA6KFQAFAQADAAUJsguYQQAbAQACAAQJ2gyKFQAFAQAAAA==.',
De='Deadlysins:BAABLgAECn8WAAIJAAgJ8wvpbACwAQAJAAgJ8wvpbACwAQAAAA==.Deadscar:BAECLgAFFH8LAAIYAAQJ+SOzAgCiAQAYAAQJ+SOzAgCiAQAuAAQKfzQAAhgACQlSJpUAAGEDABgACQlSJpUAAGEDAAAA.Deathmasterj:BAAALgADCggJDgAAAA==.Deaths:BAABLgAECn8eAAMZAAgJTRKFGgCcAQAZAAgJTRKFGgCcAQAWAAEJJQRdKQEdAAAAAA==.Dedfrosty:BAABLgAECn8aAAMSAAgJGA6VIgA0AQASAAgJzwyVIgA0AQAaAAYJqQc7GwDmAAAAAA==.Demomcgee:BAAALgADCgEJAgABLgAECgYJDwAEAAAAAA==.Demonio:BAAALgADCgQJBgAAAA==.Demonpimp:BAAALgAECgYJEAAAAA==.Dermon:BAAALgAECgcJCAABLgAFFAQJBgAbAIIhAA==.Deviously:BAAALgADCgQJBAABLgAECgkJHgACAO8dAA==.Dewyhuey:BAAALgADCgIJAgAAAA==.',
Di='Dimpiana:BAAALgAECgQJBAAAAA==.Disciplea:BAAALgAECgQJBAAAAA==.Dithariaa:BAABLgAECn8dAAIcAAcJiQf1FwDUAAAcAAcJiQf1FwDUAAAAAA==.',
Do='Docryktor:BAABLgAECn86AAIYAAgJ3xpHCQAeAgAYAAgJ3xpHCQAeAgAAAA==.Doomgears:BAABLgAECn8WAAIdAAYJFBWqDwA5AQAdAAYJFBWqDwA5AQAAAA==.Dotsdead:BAAALgADCgYJDgAAAA==.Dotöri:BAAALgAECggJDwAAAA==.',
Dr='Draculä:BAAALgAECgQJBAAAAA==.Dragonair:BAABLgAECn8aAAMGAAcJjgOVIgDTAAAGAAcJjgOVIgDTAAAHAAcJ7ALJFgCfAAAAAA==.Drashta:BAAALgAECgEJAQAAAA==.Drhoe:BAAALgAECgEJAQAAAA==.Drhurtouch:BAABLgAECn8dAAIeAAkJTBsGBwCAAgAeAAkJTBsGBwCAAgAAAA==.Dro:BAAALgAECgQJCgAAAA==.Drogas:BAAALgAECgIJBAAAAA==.Drtybear:BAABLgAECn8dAAMNAAgJ/BCuLQDmAAANAAYJAhCuLQDmAAAOAAQJqxEpKgCwAAAAAA==.Drulissa:BAACLgAFFH8MAAITAAQJOCMcEwCKAQATAAQJOCMcEwCKAQAuAAQKfxkAAhMACQl1GZktAM0BABMACQl1GZktAM0BAAAA.Druu:BAAALgADCgMJAwABLgAFFAUJEAAUAKUaAA==.',
Du='Duh:BAAALgAECgEJAQAAAA==.Duogear:BAAALgADCgEJAQAAAA==.Dusters:BAAALgADCgcJCwAAAA==.',
Eb='Ebonwings:BAAALgAECgcJDQAAAA==.',
Ed='Ediana:BAACLgAFFH8FAAIUAAMJxAL3igC0AAAUAAMJxAL3igC0AAAuAAQKfycAAhQACQnqCXpxAJIBABQACQnqCXpxAJIBAAAA.',
El='Eld:BAAALgAECgEJAQAAAA==.Elmô:BAABLgAECn83AAITAAgJHiHwCQDjAgATAAgJHiHwCQDjAgAAAA==.Elody:BAAALgADCgYJBgAAAA==.Elvara:BAAALgAECgUJDQAAAA==.',
Eq='Equipwooman:BAAALgADCgIJAgAAAA==.',
Es='Estameling:BAABLgAECn8qAAINAAgJyhabFgCNAQANAAgJyhabFgCNAQAAAA==.',
Ex='Exash:BAACLgAFFH8MAAIVAAQJwRrkGABBAQAVAAQJwRrkGABBAQAuAAQKfycAAhUACQk7ITUJAP8CABUACQk7ITUJAP8CAAAA.Excizion:BAABLgAECn8lAAIJAAkJ8wujWwCuAQAJAAkJ8wujWwCuAQAAAA==.',
Fa='Faelynne:BAAALgADCgUJBQAAAA==.Fari:BAAALgAECgcJDAAAAA==.Fathertim:BAABLgAECn8dAAIfAAcJ2RWUHgDNAQAfAAcJ2RWUHgDNAQAAAA==.',
Fe='Feannara:BAAALgAECgYJCQAAAA==.Felar:BAAALgADCgEJAQAAAA==.Feldrena:BAAALgADCgcJDAAAAA==.',
Fl='Flangus:BAAALgADCgMJBAAAAA==.Flappydragon:BAAALgADCgIJAgAAAA==.Floraria:BAAALgADCgYJBgAAAA==.',
Fr='Frostii:BAABLgAECn8YAAIUAAgJxRkwYQC4AQAUAAgJxRkwYQC4AQAAAA==.',
Fu='Fudestamp:BAAALgADCgQJBQAAAA==.Fufight:BAAALgAECgIJBAABLgAFFAQJBgAbAIIhAA==.Fugryktor:BAABLgAECn8lAAIXAAcJlRRMDACJAQAXAAcJlRRMDACJAQAAAA==.',
Fy='Fyrebug:BAABLgAECn8aAAIBAAYJ2QyoaAAUAQABAAYJ2QyoaAAUAQAAAA==.',
Ga='Galandor:BAABLgAECn8XAAITAAYJwh1dHwD/AQATAAYJwh1dHwD/AQAAAA==.Gandaalf:BAABLgAECn8WAAMgAAcJCR7XAQBrAgAgAAcJCR7XAQBrAgAUAAIJ4Q9RRgFzAAAAAA==.Garrinda:BAAALgAECgkJDgAAAA==.Gaya:BAAALgAECgYJBgAAAA==.',
Ge='Geeked:BAAALgADCgUJBQAAAA==.Gemhide:BAABLgAECn8jAAIdAAkJzhLGBwDIAQAdAAkJzhLGBwDIAQAAAA==.Georgharison:BAAALgAECgEJAQAAAA==.',
Gg='Ggwp:BAAALgAECgEJAQAAAA==.',
Gh='Ghae:BAAALgAECgUJBAAAAA==.Ghostsaber:BAAALgADCgEJAQABLgAECggJGQAhAM8cAA==.',
Gi='Gigglyguff:BAABLgAECn8YAAIFAAgJRiBIEQC+AgAFAAgJRiBIEQC+AgAAAA==.Gimly:BAAALgAECgEJAQAAAA==.Gityadruid:BAAALgADCgQJBAABLgAECgYJDQAEAAAAAA==.Gityahunter:BAAALgAECgEJAQABLgAECgYJDQAEAAAAAA==.',
Gl='Glavenus:BAAALgADCgEJAQAAAA==.',
Go='Gobank:BAAALgADCgIJAgAAAA==.Gobanks:BAABLgAECn87AAIIAAkJXCCsEQDRAgAIAAkJXCCsEQDRAgAAAA==.',
Gr='Graycat:BAAALgADCgIJAgABLgAFFAgJGgAiAMsjAA==.Grayele:BAAALgAECgIJAgAAAA==.Grayson:BAABLgAECn8VAAIIAAYJwANxBwGiAAAIAAYJwANxBwGiAAAAAA==.Graysurv:BAACLgAFFH8aAAIiAAgJyyMEAACBAgAiAAgJyyMEAACBAgAuAAQKfykAAiIACQn6JgUAABQEACIACQn6JgUAABQEAAAA.Gregmiller:BAAALgADCgYJBgAAAA==.Gromlin:BAAALgAECgUJCQAAAA==.',
['Gä']='Gäreth:BAAALgADCgYJCwAAAA==.',
Ha='Habachi:BAAALgADCgEJAQAAAA==.Halcrenian:BAAALgAECgIJAgAAAA==.Hamelot:BAAALgADCgMJBAAAAA==.Hamremmi:BAAALgAECgEJAQABLgAFFAcJHgAKAGAaAA==.Handrider:BAAALgAECgEJAQAAAA==.Haruharu:BAAALgAECgUJCQABLgAECgkJJQAFANkfAA==.Hasalia:BAAALgAECggJCAABLgAFFAQJDAATADgjAA==.',
He='Healsforu:BAAALgAECgUJDQABLgAECgYJCgAEAAAAAA==.Helly:BAAALgAECgEJAQAAAA==.Hemidall:BAAALgADCgMJAwAAAA==.Herbievore:BAABLgAECn8UAAMNAAgJORiuIgApAQANAAUJ8RquIgApAQALAAYJAhH/UAC8AAAAAA==.Heunno:BAAALgADCgYJBgABLgAECgQJAQAEAAAAAA==.',
Hi='Hiemy:BAAALgAECgYJBgAAAA==.Hif:BAACLgAFFH8GAAIFAAQJ8hyhHgBYAQAFAAQJ8hyhHgBYAQAuAAQKfyEAAgUACQmDI7QFADEDAAUACQmDI7QFADEDAAAA.Highbrittz:BAAALgAECgYJDgAAAA==.',
Ho='Hoakaren:BAABLgAECn8YAAIWAAgJfheRPADLAQAWAAgJfheRPADLAQAAAA==.Hobiscuits:BAEALgADCgQJBAABLgAECgYJGQAMAOYgAA==.Hocus:BAAALgADCgYJBgAAAA==.Holde:BAAALgAECgUJDQAAAA==.Hornyrott:BAAALgAECgQJBAAAAA==.',
Hu='Hunterzamb:BAAALgAECgEJAQAAAA==.Huntinator:BAABLgAECn8VAAIDAAcJHhtwMADvAQADAAcJHhtwMADvAQAAAA==.',
Hy='Hydrobubble:BAAALgAECgIJAgAAAA==.',
['Há']='Hátfield:BAAALgADCgEJAQAAAA==.',
Ih='Ihyo:BAAALgADCgIJAgABLgAECgcJBwAEAAAAAA==.',
Il='Illyy:BAABLgAECn8mAAIQAAgJMguPNAAlAQAQAAgJMguPNAAlAQAAAA==.',
In='Indawhole:BAACLgAFFH8eAAIWAAgJABjBEQAFAgAWAAgJABjBEQAFAgAuAAQKfxoAAhYACAl8JQYiAEACABYACAl8JQYiAEACAAAA.',
Ir='Iridori:BAABLgAECn8wAAIQAAgJuCCQCgCzAgAQAAgJuCCQCgCzAgAAAA==.Irönfist:BAAALgADCgkJEgAAAA==.',
It='Itzzender:BAAALgADCgIJAgAAAA==.',
Iz='Izumiwitabow:BAABLgAECn8VAAIDAAYJhRKwfAA6AQADAAYJhRKwfAA6AQAAAA==.',
Ja='Jabberthehut:BAAALgAECgYJCgAAAA==.Jamerius:BAAALgAECgIJAgAAAA==.Jankovic:BAAALgADCgcJBwAAAA==.Jasmean:BAAALgADCgcJBQAAAA==.Javaluminous:BAABLgAECn8oAAIIAAgJQCA+KQBUAgAIAAgJQCA+KQBUAgAAAA==.Jay:BAAALgAFFAMJAwABLgAFFAYJFAAjADgXAA==.Jaytsukitori:BAACLgAFFH8XAAMFAAUJiyPBDQAIAgAFAAUJiyPBDQAIAgALAAEJgwgQSQA4AAAuAAQKfx0AAwUACAmKIbkMANcCAAUACAmKIbkMANcCAAsAAQlmEL2GADMAAAAA.',
Jh='Jhaeriao:BAAALgAECgYJDAAAAA==.Jhantherox:BAAALgAECgYJBgAAAA==.',
Jo='Joesepi:BAABLgAFFH8aAAIJAAYJ6xreIADMAQAJAAYJ6xreIADMAQAAAA==.Joham:BAAALgAECgEJAQAAAA==.Jojosus:BAAALgADCgcJBwABLgADCgkJJAAEAAAAAA==.Jonah:BAAALgAFFAEJAQABLgAFFAIJBQAJAB4YAA==.',
Ju='Judgeroybean:BAAALgAECgEJAQAAAA==.Juliofoolioo:BAAALgAECgEJAgAAAA==.',
Ka='Kayahli:BAAALgAECgQJBAAAAA==.Kazghul:BAAALgADCgEJAQAAAA==.',
Ke='Kelaeus:BAABLgAECn8VAAIUAAYJUQ5x0ABMAQAUAAYJUQ5x0ABMAQAAAA==.Keyonslayz:BAAALgADCggJCAAAAA==.',
Kh='Khrønos:BAAALgAECggJCgAAAA==.',
Ki='Killzom:BAAALgADCgEJAQABLgAFFAQJCgANACkVAA==.Kilrah:BAABLgAECn82AAIZAAkJahamEQADAgAZAAkJahamEQADAgAAAA==.Kirian:BAAALgADCgEJAQAAAA==.Kissmyash:BAABLgAECn8WAAIUAAYJ9AkhywD1AAAUAAYJ9AkhywD1AAAAAA==.Kissmycrits:BAABLgAECn8ZAAIDAAQJsB2SewA9AQADAAQJsB2SewA9AQAAAA==.Kissmywrath:BAAALgAECgEJAQAAAA==.Kiyana:BAABLgAECn8rAAIZAAcJUA3OLQAEAQAZAAcJUA3OLQAEAQAAAA==.Kiyoine:BAABLgAECn8iAAIOAAgJKRlHCwD5AQAOAAgJKRlHCwD5AQAAAA==.',
Kn='Knocksteady:BAACLgAFFH8TAAIIAAYJLRo/HgB7AQAIAAYJLRo/HgB7AQAuAAQKfyAAAggABwm2IYskAJUCAAgABwm2IYskAJUCAAAA.Knoxform:BAAALgAECgMJBAAAAA==.Knoxhops:BAAALgAECgMJAwABLgAECgMJBAAEAAAAAA==.Knoxreaps:BAAALgAECgYJBAABLgAECgMJBAAEAAAAAA==.Knoxstaggers:BAABLgAECn8lAAIkAAgJ3iBsEgAZAgAkAAgJ3iBsEgAZAgABLgAECgMJBAAEAAAAAA==.',
Ko='Korozzma:BAAALgADCgYJBgABLgADCgEJAQAEAAAAAA==.',
Kr='Krzzy:BAAALgAFFAEJAQABLgAFFAcJCAAVACgOAA==.',
Ku='Kuray:BAAALgAECgEJAgAAAA==.',
Ky='Kynbrookera:BAABLgAECn8dAAIFAAgJ0AwbTQBSAQAFAAgJ0AwbTQBSAQAAAA==.Kyujin:BAAALgADCgEJAQAAAA==.',
['Kì']='Kìnky:BAAALgAECgcJEwAAAA==.',
La='Laetha:BAAALgADCgUJBQAAAA==.',
Le='Lemicall:BAAALgADCgQJCAAAAA==.Lethiferous:BAAALgAECgEJAQAAAA==.Letmespankit:BAAALgADCgYJDAAAAA==.Lezigo:BAABLgAECn8jAAIUAAkJaBTHRgABAgAUAAkJaBTHRgABAgAAAA==.',
Li='Licht:BAAALgAECgYJCwAAAA==.Lik:BAAALgAECgQJBwAAAA==.Lilhorror:BAAALgADCgMJAwAAAA==.Lilpyro:BAAALgAECgQJBAAAAA==.Lilyheart:BAAALgADCgYJBgAAAA==.Linai:BAABLgAECn8kAAMjAAkJuQ6lFQDmAQAjAAkJuQ6lFQDmAQAlAAgJEQiNDgAyAQAAAA==.Lit:BAAALgAECgEJAwAAAA==.Littledog:BAACLgAFFH8KAAIKAAQJbRRDFgAjAQAKAAQJbRRDFgAjAQAuAAQKfy0AAwoACQnXFZwaAOkBAAoACQnXFZwaAOkBAB8AAwkdFK09AL8AAAAA.',
Lo='Lockdout:BAAALgADCgEJAQABLgAECggJGQAUANkWAA==.Loky:BAACLgAFFH8GAAIMAAIJWhsOhQCrAAAMAAIJWhsOhQCrAAAuAAQKfyUABAwACQkCH3Y6AOsBAAwACQncHnY6AOsBAB0ABAl+GMskADUBABcAAQl6IaosAF8AAAAA.Longshanks:BAAALgADCgUJDAAAAA==.Lorna:BAAALgADCgEJAQAAAA==.Lotten:BAAALgAECgUJCwAAAA==.',
Lu='Luckevin:BAAALgAECgYJDgAAAA==.Lunitari:BAAALgAECgYJDAAAAA==.Luthiean:BAAALgADCgQJBAAAAA==.Luthran:BAAALgAECgUJCwABLgAECggJGAAOAD8PAA==.',
Ly='Lynnali:BAAALgADCggJEQAAAA==.Lyrrin:BAAALgADCgYJBgAAAA==.',
Ma='Magedon:BAAALgAECgEJAQAAAA==.Mageyoulaugh:BAABLgAECn8ZAAIUAAgJ2RaPWwDGAQAUAAgJ2RaPWwDGAQAAAA==.Magezamb:BAAALgAECgUJDQAAAA==.Magicmann:BAAALgAECgEJAQAAAA==.Magmash:BAAALgADCggJDwAAAA==.Mahito:BAAALgADCgEJAQAAAA==.Mahru:BAAALgADCgYJCAAAAA==.Majhduul:BAAALgADCgMJAwAAAA==.Malafang:BAABLgAECn8VAAIIAAYJygTo+AC0AAAIAAYJygTo+AC0AAAAAA==.Malanah:BAAALgAECgYJEgAAAA==.Marandra:BAAALgAECgMJAwAAAA==.Marlie:BAAALgAECgMJAwAAAA==.Mathalios:BAAALgAECgIJAgAAAA==.Mattu:BAAALgAECgUJEAAAAA==.Maverick:BAACLgAFFH8UAAIjAAYJOBd7EQBtAQAjAAYJOBd7EQBtAQAuAAQKfxsAAyMABwlUIsIVAGECACMABwlNIsIVAGECACUABAmBIpcMAFgBAAAA.Maxbaba:BAAALgAECgEJAQAAAA==.',
Mc='Mcskittelz:BAAALgADCgQJBAAAAA==.',
Me='Meleshanorak:BAAALgADCgUJCgAAAA==.',
Mi='Michaella:BAAALgAECgUJCwAAAA==.Michartson:BAAALgADCgYJBAAAAA==.Mingres:BAABLgAECn8XAAIDAAcJQw8LcgBSAQADAAcJQw8LcgBSAQAAAA==.Miramanie:BAAALgADCgYJBgAAAA==.Misdiagnosed:BAAALgADCgIJAgAAAA==.Mistbrewer:BAAALgADCgIJAgAAAA==.',
Mk='Mk:BAEALgAECgYJDQABLgAECgkJQQAmAIAgAA==.',
Mo='Mogar:BAABLgAECn8YAAIeAAcJPR3qDQADAgAeAAcJPR3qDQADAgAAAA==.Mogina:BAAALgADCggJCAAAAA==.Monkish:BAAALgADCgMJAwAAAA==.Monster:BAAALgAECgUJBQAAAA==.Moonzhine:BAABLgAECn8jAAISAAkJXhUuFADGAQASAAkJXhUuFADGAQAAAA==.Moosejaw:BAAALgAECgQJBwAAAA==.Mordread:BAAALgAECggJDgAAAA==.Morgalruk:BAAALgAFFAMJAwAAAA==.',
My='Myriosheal:BAAALgADCgQJBAAAAA==.Mythx:BAACLgAFFH8iAAQDAAgJTRsDAgCBAQADAAYJJh0DAgCBAQAiAAQJCQwLFQAaAQACAAIJRRQQJwBZAAAuAAQKfysABAMACAlXI3wIAAoDAAMACAlXI3wIAAoDACIABgn7GJIqAEkBAAIABQkFEe5MAB0BAAAA.',
Na='Nalanelin:BAABLgAECn8WAAIJAAcJKQ3SkQA7AQAJAAcJKQ3SkQA7AQAAAA==.Narukin:BAABLgAECn8cAAIWAAcJVBryRACtAQAWAAcJVBryRACtAQAAAA==.Naturboy:BAAALgADCgYJBgAAAA==.',
Ne='Nessirebette:BAAALgADCgUJCAAAAA==.Netherwalker:BAAALgAECgIJAgABLgAFFAcJHgAKAGAaAA==.',
Ni='Nivmizzet:BAABLgAECn8wAAMMAAgJ+Bn6TACuAQAMAAcJfBr6TACuAQAdAAYJ8BUqLQAJAQAAAA==.',
No='Nolakai:BAAALgAECgEJAQAAAA==.Nomiro:BAAALgAECgYJDAAAAA==.Noradori:BAAALgAECgEJAQAAAA==.Notdip:BAAALgADCgIJAgAAAA==.Novalea:BAACLgAFFH8NAAIBAAQJ1yXyEgCxAQABAAQJ1yXyEgCxAQAuAAQKf00AAwEACQlhI3wEAGYDAAEACQlhI3wEAGYDABUABwkeHpQrAIsBAAAA.',
Nu='Nuru:BAAALgAECgcJEAAAAA==.Nutcutter:BAAALgADCgYJBgAAAA==.',
['Nø']='Nøstalgic:BAAALgAECgEJAgAAAA==.',
Ob='Obala:BAAALgADCgIJAgAAAA==.',
Od='Odogaren:BAABLgAECn8ZAAMhAAgJzxxbCwBYAgAhAAcJgB1bCwBYAgARAAgJhRoVIQBLAgAAAA==.',
Om='Omnithorn:BAAALgAECggJDQAAAA==.',
On='Onei:BAAALgADCgEJAQAAAA==.',
Or='Oramos:BAAALgAECgQJBgAAAA==.Orgóndó:BAABLgAFFH8NAAISAAYJmR1FDQCNAQASAAYJmR1FDQCNAQAAAA==.',
Ov='Ova:BAAALgAECgEJAQAAAA==.',
Ox='Oxxo:BAABLgAECn8dAAInAAcJCAzIDQApAQAnAAcJCAzIDQApAQAAAA==.',
Pa='Palzamb:BAAALgADCgYJCwAAAA==.Pandacillin:BAAALgAECgQJBAAAAA==.Paraggonn:BAABLgAECn8jAAIDAAYJrhtcWgCLAQADAAYJrhtcWgCLAQAAAA==.',
Pe='Penelöpe:BAAALgAECgMJBAAAAA==.Penoosê:BAAALgADCgEJAgAAAA==.Perlonis:BAAALgAECgYJEwAAAA==.',
Ph='Phatocaster:BAAALgADCgIJBAAAAA==.Phoinyx:BAAALgAECgkJDwAAAA==.Phuriosa:BAAALgAECgcJDwABLgAFFAMJBwAFAO8VAA==.Phury:BAACLgAFFH8HAAIFAAMJ7xX/NgDOAAAFAAMJ7xX/NgDOAAAuAAQKfyQAAwUACQlSGmUmABQCAAUACAkbGWUmABQCAAsAAgkmFzhbAJoAAAAA.Physinyx:BAAALgAECgkJCgAAAA==.Physta:BAAALgADCggJCwAAAA==.',
Pi='Pizza:BAABLgAECn8aAAINAAcJHRjOFQCVAQANAAcJHRjOFQCVAQAAAA==.',
Pl='Plagafel:BAAALgADCgYJBgAAAA==.',
Po='Pomomies:BAAALgAECgMJBAAAAA==.Pooseunpoose:BAAALgAFFAEJBAAAAA==.Porkmancer:BAAALgAECgYJCgABLgAECgkJJgAJAEwfAA==.Porkslope:BAABLgAECn8mAAIJAAgJTB9oJABsAgAJAAgJTB9oJABsAgAAAA==.',
Pr='Praahv:BAAALgADCgYJBgAAAA==.Profryktor:BAAALgAECgYJEwAAAA==.',
Pu='Purebloods:BAAALgADCgEJAQAAAA==.Purpleparrot:BAAALgADCgcJBwAAAA==.',
Qu='Quickben:BAAALgAECgIJAgAAAA==.',
Ra='Raenyx:BAABLgAECn85AAMMAAgJ3x6gHAByAgAMAAgJ3x6gHAByAgAXAAMJag7hKABrAAAAAA==.Raiflock:BAAALgAECgcJEwAAAA==.Ranalastus:BAAALgAECgUJDAAAAA==.Raveneyes:BAEBLgAECn8jAAIMAAkJjhHRQADUAQAMAAkJjhHRQADUAQAAAA==.',
Re='Reiena:BAAALgAECgcJEAAAAA==.Relas:BAAALgADCgUJBQAAAA==.Reylilyn:BAABLgAECn8oAAIbAAkJqBVgGQA9AgAbAAkJqBVgGQA9AgAAAA==.Reynarena:BAAALgAECgYJEAAAAA==.',
Rh='Rhaenfyre:BAABLgAECn8jAAMWAAkJMBXhNwDdAQAWAAkJMBXhNwDdAQAcAAEJ9Qy5NQAlAAAAAA==.',
Ri='Richardhurtz:BAAALgAECgYJBgAAAA==.Ricola:BAAALgAFFAIJBAAAAA==.Rivenel:BAACLgAFFH8MAAIdAAUJxBQLBQBDAQAdAAUJxBQLBQBDAQAuAAQKfykAAx0ACQkgIgoCAKICAB0ACAlaIwoCAKICAAwAAQmHGcYTAUoAAAAA.Rivèn:BAAALgADCgEJAQAAAA==.',
Ro='Robinvoid:BAABLgAECn8dAAMWAAkJgCAPFQDZAgAWAAkJgCAPFQDZAgAZAAEJ+RRiaQBAAAAAAA==.Rocksann:BAAALgAECgEJAwAAAA==.Rodel:BAAALgAECgEJAgABLgAECgMJAwAEAAAAAA==.Roquan:BAABLgAECn8wAAIaAAgJ7RsdCAAAAgAaAAgJ7RsdCAAAAgAAAA==.Roulette:BAAALgAECgUJDwAAAA==.',
Ru='Rubmyrott:BAAALgAECgcJDQAAAA==.Runalot:BAAALgAECgYJBgAAAA==.',
['Rê']='Rêdd:BAABLgAECn8bAAIKAAcJXxF0LABsAQAKAAcJXxF0LABsAQAAAA==.',
Sa='Sabeion:BAAALgAECgYJDAAAAA==.Saboo:BAAALgAECgQJAQAAAA==.Sadiebuding:BAAALgAECgEJAQAAAA==.Salswarriah:BAABLgAECn8WAAIRAAYJEBDGRwAfAQARAAYJEBDGRwAfAQAAAA==.Sanaku:BAAALgAECgYJCAAAAA==.Sanangra:BAAALgADCgEJAQAAAA==.Santo:BAAALgADCgMJAwAAAA==.Sarlyan:BAAALgADCgkJFwAAAA==.Sassafrazz:BAAALgAECgQJBAAAAA==.',
Sc='Scrumbles:BAAALgAECgkJDwAAAA==.',
Se='Secksytoes:BAAALgAECgMJAwABLgADCgYJCwAEAAAAAA==.Seraphim:BAAALgADCgEJAQAAAA==.Serion:BAAALgADCgMJAwAAAA==.Sewerrat:BAAALgADCggJCAAAAA==.',
Sg='Sgtbonesnap:BAAALgAECgYJCgAAAA==.Sgtpunchy:BAAALgADCgMJBQABLgAECgYJCgAEAAAAAA==.',
Sh='Shakuro:BAAALgAECgEJAgAAAA==.Shallash:BAAALgADCgUJBgAAAA==.Shamageddon:BAAALgAECgIJBAAAAA==.Shamanizim:BAACLgAFFH8IAAMVAAQJRBGhIwADAQAVAAQJRBGhIwADAQAYAAEJfgQJGQA7AAAuAAQKfyoABBUACAmUHJEbAPkBABUACAkpHJEbAPkBABgABwnlFQUWAFMBAAEAAgknBiLEAD0AAAAA.Shausin:BAAALgAECggJCAAAAA==.Sheeanna:BAAALgAFFAEJAQABLgAFFAQJDAATADgjAA==.Shiftmyself:BAAALgADCgkJDgAAAA==.Shinoikari:BAACLgAFFH8IAAIaAAIJjQaSHAB+AAAaAAIJjQaSHAB+AAAuAAQKfygAAxoACQkNEYoJANwBABoACQkNEYoJANwBABIABQnJCEVAAIQAAAAA.Shinotenshi:BAABLgAECn8XAAQfAAcJtwn3NwAnAQAfAAcJtQf3NwAnAQAQAAUJWwaMYgCmAAAKAAEJKARJjQAlAAABLgAFFAIJCAAaAI0GAA==.Shirase:BAABLgAECn8eAAMMAAkJdw5zaABnAQAMAAkJHgxzaABnAQAXAAYJRQ4lFgAGAQABLgAFFAQJDQABANclAA==.Shugarae:BAABLgAECn8cAAMLAAgJPQguOwAYAQALAAgJPQguOwAYAQAFAAUJcATXmwBwAAAAAA==.',
Si='Sionnocht:BAAALgADCgEJAQAAAA==.Sirlemage:BAAALgADCgMJAwAAAA==.',
Sk='Skina:BAAALgAECgEJAQAAAA==.Skreezy:BAAALgAECgcJDAAAAA==.Skuls:BAAALgAECgMJBQAAAA==.',
Sl='Slashemup:BAABLgAECn8jAAIZAAkJ+RbeEAANAgAZAAkJ+RbeEAANAgAAAA==.Slayter:BAABLgAECn8lAAIFAAkJ2R8aHABcAgAFAAkJ2R8aHABcAgAAAA==.',
Sm='Smaugin:BAAALgAECgIJAgAAAA==.',
Sn='Snakelazers:BAACLgAFFH8GAAIbAAQJgiFMGQCEAQAbAAQJgiFMGQCEAQAuAAQKfyQAAhsACQn6IsMEAFcDABsACQn6IsMEAFcDAAAA.Snufulafagus:BAABLgAECn8WAAIOAAUJbRuTGAA7AQAOAAUJbRuTGAA7AQAAAA==.',
So='Soju:BAABLgAECn8kAAMBAAkJchS/JgAaAgABAAkJchS/JgAaAgAVAAQJJxIjaAChAAABLgAECgkJLAADAMkjAA==.Soliloquy:BAAALgAECgUJBQAAAA==.Songwind:BAABLgAECn8qAAImAAgJYg3tKgBZAQAmAAgJYg3tKgBZAQAAAA==.Soonie:BAAALgADCgEJAQAAAA==.Soulreever:BAAALgADCggJCAAAAA==.',
Sq='Squishypal:BAABLgAECn8WAAMIAAgJSBvIOgAOAgAIAAgJSBvIOgAOAgAoAAEJ6xYjPwBBAAAAAA==.',
St='Starfirelmao:BAAALgAECgYJDwAAAA==.Steelcure:BAAALgAECggJCgAAAA==.Strabo:BAAALgADCggJCQAAAA==.Strawdicks:BAAALgAECgcJAQAAAA==.',
Su='Sugma:BAAALgAECgEJAQAAAA==.Suzsette:BAABLgAECn8ZAAIKAAYJRwiOSQDgAAAKAAYJRwiOSQDgAAAAAA==.',
Sy='Sylris:BAAALgADCgkJFgAAAA==.Sylvanthis:BAAALgAECgQJBAABLgAECggJHQAFANAMAA==.',
['Sç']='Sçoxx:BAAALgADCgEJAQAAAA==.',
Ta='Taazdingo:BAAALgADCgEJAQAAAA==.Taeleth:BAAALgADCgcJBwAAAA==.Talnora:BAAALgAECgYJDwAAAA==.Tardovski:BAABLgAECn8kAAMDAAgJlyF0GgB8AgADAAgJlyF0GgB8AgACAAQJ2BP2VgDsAAAAAA==.Taurentino:BAAALgAECgkJBQAAAA==.',
Te='Telaris:BAAALgADCgIJAgAAAA==.Telda:BAAALgAECgUJEAAAAA==.Teneturadvós:BAAALgAECgcJAwABLgAECgcJDQAEAAAAAA==.Tentreeadvos:BAAALgAECgEJAQABLgAECgcJDQAEAAAAAA==.Tetris:BAACLgAFFH8PAAIUAAQJ3hw1QwBYAQAUAAQJ3hw1QwBYAQAuAAQKfzgAAhQACQmgIqUUANgCABQACQmgIqUUANgCAAAA.',
Th='Thellaria:BAAALgADCgIJAgAAAA==.Thraggoar:BAAALgADCgEJAQAAAA==.Thunsar:BAAALgAECgkJDwAAAA==.Thuzzad:BAAALgADCgUJBQAAAA==.',
Ti='Tickler:BAAALgAECgUJEQAAAA==.Tiroelin:BAAALgAECgUJBwAAAA==.',
To='Toetem:BAAALgADCgQJBgAAAA==.Tox:BAAALgADCgUJBQAAAA==.Toyotama:BAAALgAECgYJBgABLgAFFAUJFwAFAIsjAA==.',
Tr='Tragedeigh:BAAALgAECgUJBQAAAA==.Trane:BAAALgAECgIJAgAAAA==.Tritoch:BAAALgAECgYJEAAAAA==.Troche:BAACLgAFFH8GAAIoAAQJ4AZUCwC1AAAoAAQJ4AZUCwC1AAAuAAQKfxgAAygACQmDESwPAMQBACgACQmDESwPAMQBABMAAQlNCCSTACgAAAAA.Truthfully:BAAALgAECgYJDwAAAA==.Trávpac:BAAALgADCgEJAQAAAA==.',
Tt='Ttjpll:BAAALgAECgUJDQAAAA==.',
Tu='Tubs:BAAALgAECgEJAQAAAA==.Tuckncloak:BAAALgAECgIJAgAAAA==.',
Tw='Twohand:BAAALgADCgIJBAAAAA==.',
['Tî']='Tîmon:BAAALgAFFAIJAgAAAA==.',
Ug='Ugrup:BAAALgAECgYJDgAAAA==.',
Uj='Ujabula:BAAALgAECgYJEgAAAA==.',
Ul='Ulurak:BAABLgAECn8YAAMOAAgJPw8aGwAaAQAOAAYJkwkaGwAaAQAFAAQJ9QpSogBlAAAAAA==.',
Un='Uncleskip:BAABLgAECn8bAAIeAAcJ0wd0FgBJAQAeAAcJ0wd0FgBJAQAAAA==.Unhappytoast:BAABLgAECn8WAAIoAAkJdBiQCQAqAgAoAAkJdBiQCQAqAgAAAA==.Unstobubble:BAAALgAECgYJCQAAAA==.',
Va='Valeriya:BAAALgADCgUJAwABLgAECgMJAwAEAAAAAA==.Valisanna:BAAALgADCggJDQAAAA==.Vallorien:BAABLgAECn8ZAAIoAAYJOyF/DgDQAQAoAAYJOyF/DgDQAQAAAA==.Valsharess:BAAALgADCgcJBwABLgAECgkJOAAWAEEaAA==.',
Ve='Vegtam:BAAALgAECgEJAQAAAA==.Velaryn:BAAALgAFFAIJAgAAAA==.Velnia:BAAALgAECgYJCwAAAA==.Verencia:BAAALgAECgEJAQAAAA==.',
Vi='Vildaren:BAAALgAECgUJCQAAAA==.Vivachel:BAAALgADCgcJCAAAAA==.',
Vo='Vorsan:BAAALgADCgcJBwAAAA==.Vorsane:BAAALgADCgQJBAAAAA==.',
['Và']='Vàli:BAAALgAECgQJCQAAAA==.',
Wa='Wanks:BAAALgAECgYJDwAAAA==.Warmoon:BAAALgAECgMJAwAAAA==.Warskul:BAAALgADCgEJAQAAAA==.Wasenshi:BAAALgADCgUJBQAAAA==.',
We='Weeb:BAAALgADCgUJCwAAAA==.Weeny:BAAALgAECgcJCwAAAA==.',
Wh='Wholy:BAAALgAECgMJBgAAAA==.',
Wi='Wickedromeo:BAAALgAECgMJAwAAAA==.',
Wo='Wolfmother:BAABLgAECn8jAAIVAAgJpxR3KACdAQAVAAgJpxR3KACdAQAAAA==.',
Xa='Xaanii:BAABLgAECn8aAAITAAYJUB3JIQDsAQATAAYJUB3JIQDsAQAAAA==.Xandius:BAAALgADCgcJDAAAAA==.Xarferrin:BAABLgAECn8dAAIUAAcJDgN54gDSAAAUAAcJDgN54gDSAAAAAA==.',
Xe='Xeeria:BAACLgAFFH8fAAIBAAUJShNGKAAuAQABAAUJShNGKAAuAQAuAAQKfzAAAwEACQnyHwoNALUCAAEACQnyHwoNALUCABUAAQlXG4eKAE8AAAAA.Xenzull:BAAALgAECgIJAgAAAA==.',
Xk='Xkaliber:BAAALgADCgEJAQAAAA==.',
Xu='Xuecat:BAABLgAECn8kAAIFAAgJ3xYQLgD1AQAFAAgJ3xYQLgD1AQAAAA==.',
Yn='Yn:BAAALgAECgYJDAAAAA==.',
Za='Zamzak:BAAALgADCgQJBAABLgAECgEJAQAEAAAAAA==.Zanthor:BAABLgAECn8VAAIJAAUJbggG7AC6AAAJAAUJbggG7AC6AAAAAA==.Zaralina:BAACLgAFFH8GAAIKAAQJLAjCHgDpAAAKAAQJLAjCHgDpAAAuAAQKfzQAAgoACQlPFz4RAEYCAAoACQlPFz4RAEYCAAAA.Zartox:BAABLgAECn8bAAIpAAgJVBeVAwDSAQApAAgJVBeVAwDSAQAAAA==.Zaryn:BAAALgADCgIJAgAAAA==.Zarynth:BAAALgAECgEJAQAAAA==.Zaryssa:BAABLgAECn8dAAIVAAgJjwWATgDuAAAVAAgJjwWATgDuAAAAAA==.Zavinus:BAAALgADCgYJCAAAAA==.',
Ze='Zenzug:BAAALgAECgUJDwAAAA==.Zephystra:BAAALgADCgQJBAABLgAFFAQJDQABANclAA==.Zeusqt:BAAALgADCgYJBgAAAA==.',
Zh='Zharfrost:BAAALgAECgYJCAAAAA==.',
Zi='Zicroniah:BAAALgADCgYJCgAAAA==.Ziyuu:BAAALgADCgUJBQAAAA==.',
Zo='Zombiehunter:BAABLgAECn8jAAIDAAkJaR/oDwDJAgADAAkJaR/oDwDJAgAAAA==.',
Zu='Zuzu:BAAALgADCgMJAwAAAA==.',
['Âr']='Ârc:BAAALgAECgEJAgAAAA==.',
['Èd']='Èddy:BAACLgAFFH8GAAIFAAMJTQl4RQCcAAAFAAMJTQl4RQCcAAAuAAQKfx0AAgUACQk0FncbAGICAAUACQk0FncbAGICAAAA.',
['Ût']='Ûthèr:BAAALgADCgEJAQAAAA==.',
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
