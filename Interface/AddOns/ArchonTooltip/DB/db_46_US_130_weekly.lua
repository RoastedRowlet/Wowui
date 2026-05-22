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

local lookup = {'Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Mage-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','Unknown-Unknown','Shaman-Enhancement','Shaman-Elemental','Druid-Restoration','Warlock-Affliction','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Shadow','Paladin-Retribution','Druid-Balance','Priest-Holy','Mage-Fire','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','Paladin-Holy','Evoker-Preservation','Evoker-Augmentation','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','Warrior-Protection','Priest-Discipline','DeathKnight-Blood','Warrior-Fury','Hunter-Survival','Paladin-Protection','Evoker-Devastation','Warrior-Arms','Rogue-Outlaw','DeathKnight-Frost','Mage-Arcane',}
local provider = {region='US',realm='Khadgar',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Aberendh:BAAALgADCgkJBwAAAA==.Aberenmonk:BAABLgAECn8XAAQBAAcJjRhjKQC9AQABAAYJnRpjKQC9AQACAAcJPxBIJQA1AQADAAIJMQMZZQA9AAAAAA==.Abiz:BAAALgAECgQJAwAAAA==.Abonde:BAABLgAECn8VAAIEAAYJZgv3mwAIAQAEAAYJZgv3mwAIAQAAAA==.Abraxes:BAAALgAECgYJDgAAAA==.Abysmalguard:BAAALgADCgUJBQAAAA==.',
Ac='Acidemon:BAABLgAECn8gAAMFAAgJVRcaTwBIAQAFAAcJ4xAaTwBIAQAGAAgJVRduIAAMAQAAAA==.',
Ad='Adalaide:BAABLgAECn8WAAMHAAcJRxGyEQDeAAAHAAYJ3hCyEQDeAAAIAAUJRwsftwCQAAAAAA==.',
Ae='Aehda:BAAALgAECgYJCQAAAA==.Aeluna:BAAALgAECgEJAQAAAA==.Aethas:BAAALgADCgMJBAAAAA==.Aevari:BAABLgAECn8iAAIJAAYJuhraKgC2AQAJAAYJuhraKgC2AQAAAA==.',
Af='Affective:BAAALgAECgQJBAABLgAECgYJCwAKAAAAAA==.',
Ah='Ahkna:BAAALgAECgQJBQAAAA==.',
Aj='Ajaâx:BAABLgAECn8hAAMLAAYJDh2HDQBmAQALAAYJDh2HDQBmAQAMAAMJcxFDZwCmAAAAAA==.',
Al='Alanath:BAAALgADCgYJBgAAAA==.Alathia:BAAALgADCgYJBgAAAA==.Albatross:BAAALgAECgMJAwAAAA==.Aldarya:BAABLgAECn8VAAINAAUJ3R33LwCZAQANAAUJ3R33LwCZAQAAAA==.Aliraeda:BAABLgAECn8sAAQIAAkJCg3jQwCRAQAIAAgJtgvjQwCRAQAOAAYJ1A5gEwD4AAAHAAMJSwwrWQBjAAAAAA==.Alisara:BAACLgAFFH8LAAIPAAMJsCCqKAAaAQAPAAMJsCCqKAAaAQAuAAQKfxkAAg8ACAloIFINANMCAA8ACAloIFINANMCAAAA.Alish:BAABLgAECn8OAAIFAAYJqg0VdADmAAAFAAYJqg0VdADmAAAAAA==.Alissia:BAAALgAECgMJBQAAAA==.Alistraea:BAAALgAECgYJEAAAAA==.Alitrullbrat:BAABLgAECn8VAAMPAAkJMBywGABFAgAPAAkJMBywGABFAgAQAAIJNw/wdgBjAAAAAA==.Allargara:BAAALgAECggJCwAAAA==.Allexx:BAABLgAECn8sAAIPAAkJjR4tDgCZAgAPAAkJjR4tDgCZAgAAAA==.Alliin:BAAALgADCgcJBwAAAA==.Allyssel:BAACLgAFFH8KAAIGAAQJlyKOAgCUAQAGAAQJlyKOAgCUAQAuAAQKfygAAgYACQmQJT0EADYDAAYACQmQJT0EADYDAAAA.Alyssanan:BAAALgADCgUJBQAAAA==.Alyssarae:BAAALgADCgIJAgAAAA==.',
Am='Amasu:BAACLgAFFH8ZAAIRAAUJryFkBwCKAQARAAUJryFkBwCKAQAuAAQKfy8AAhEACQlPI8kCABEDABEACQlPI8kCABEDAAAA.Ammathendis:BAAALgADCgQJBAAAAA==.',
An='Anastriana:BAAALgAECgYJEQAAAA==.Andrei:BAAALgADCgcJBAAAAA==.Angeal:BAABLgAECn8LAAIPAAYJ1BW2YQAmAQAPAAYJ1BW2YQAmAQAAAA==.Animus:BAABLgAECn8eAAIMAAkJlA25IwBzAQAMAAkJlA25IwBzAQAAAA==.Annamei:BAAALgAECgUJEAAAAA==.',
Ao='Aorina:BAACLgAFFH8GAAIEAAQJwwOuVAD7AAAEAAQJwwOuVAD7AAAuAAQKfxkAAgQACAk5GftDAM0BAAQACAk5GftDAM0BAAAA.',
Ap='Aphis:BAAALgAECggJDgAAAA==.Apocalyptica:BAABLgAECn8UAAISAAcJrQmZlABTAQASAAcJrQmZlABTAQAAAA==.',
Ar='Arazalor:BAABLgAECn8pAAINAAkJ8Q0vLACvAQANAAkJ8Q0vLACvAQAAAA==.Arcangel:BAACLgAFFH8ZAAMNAAUJMxuFDACqAQANAAUJMxuFDACqAQATAAEJNAiGMwA+AAAuAAQKfy8AAw0ACQnBJe8FAC4DAA0ACAnaJe8FAC4DABMACAlsHLANAC0CAAAA.Arcbane:BAAALgAECgEJAQAAAA==.Arclight:BAAALgAECgEJAQAAAA==.Argand:BAABLgAECn8eAAINAAkJ8BytCQDiAgANAAkJ8BytCQDiAgAAAA==.Arkahnon:BAAALgADCgUJBgAAAA==.Arthurdent:BAABLgAECn8kAAIMAAkJlSLRAwD5AgAMAAkJlSLRAwD5AgAAAA==.',
As='Ashenrain:BAABLgAECn8XAAMIAAcJkB0VLwDdAQAIAAcJpBwVLwDdAQAHAAIJhhpHKQBIAAAAAA==.Ashvia:BAAALgAECgYJEgAAAA==.Ashyslashy:BAABLgAECn8jAAMGAAgJiRVkEgChAQAGAAgJWhRkEgChAQAFAAcJaBLUVwAuAQAAAA==.',
At='Atheren:BAABLgAECn8pAAIJAAkJhiCrBAAlAwAJAAkJhiCrBAAlAwAAAA==.Athshu:BAAALgADCgEJAgAAAA==.Atulan:BAAALgAECgkJEAAAAA==.',
Au='Augmented:BAAALgADCggJFAAAAA==.Auntiemimi:BAABLgAECn8aAAIJAAYJmxv8JQDSAQAJAAYJmxv8JQDSAQAAAA==.Aurenthos:BAAALgADCggJCwAAAA==.Auressali:BAAALgAECgcJDwAAAA==.Auu:BAAALgADCgYJBwAAAA==.',
Av='Avalina:BAABLgAECn8fAAMUAAcJEiQLDQCFAgAUAAcJEiQLDQCFAgARAAUJSBVhMgD9AAABLgAECggJFQAOADMgAA==.Avannar:BAAALgAECgUJCQAAAA==.Avelyn:BAACLgAFFH8YAAMVAAcJAycDAABAAgAVAAcJvSYDAABAAgAEAAMJqyPcZADLAAAuAAQKfyQAAxUACQkMJkQAAHMDABUACQkMJkQAAHMDAAQABQlEIxxXAJYBAAAA.Aveìl:BAAALgADCgQJBAAAAA==.Aviae:BAAALgAECggJDgAAAA==.',
Ay='Ayani:BAABLgAECn8vAAMRAAkJjxWtDwARAgARAAkJjxWtDwARAgAUAAUJ2gazRwBxAAAAAA==.',
Az='Azrine:BAAALgAECgIJAgAAAA==.',
Ba='Bacongrease:BAAALgADCgEJAgAAAA==.Baddkharma:BAAALgAECgEJAQAAAA==.Badras:BAABLgAECn8uAAIPAAkJlSS4BQAyAwAPAAkJlSS4BQAyAwAAAA==.Bagelz:BAACLgAFFH8ZAAIDAAUJ3CE+BwDxAQADAAUJ3CE+BwDxAQAuAAQKfzAAAgMACQkwJHoEABgDAAMACQkwJHoEABgDAAAA.Balafre:BAAALgADCgUJBQABLgAECgYJCgAKAAAAAA==.Balforyn:BAAALgAECgEJAQAAAA==.Bambi:BAAALgAECgYJBgAAAA==.Bannish:BAAALgAECgYJBwAAAA==.Barksyn:BAAALgAECgYJCgAAAA==.Bathool:BAABLgAECn8bAAIWAAcJSxnMCACQAQAWAAcJSxnMCACQAQAAAA==.Bayla:BAAALgAFFAIJBAABLgAFFAcJGQAEANwSAA==.Bazzlock:BAABLgAECn8WAAIOAAgJZx3hAwAFAgAOAAgJZx3hAwAFAgAAAA==.',
Be='Beeblebroxx:BAAALgADCgMJAwAAAA==.Beechezz:BAAALgADCgcJBwAAAA==.Beefcat:BAAALgAECgQJBQABLgAECgYJCQAKAAAAAA==.Beefsho:BAAALgAECgEJAQAAAA==.Beefycow:BAAALgADCgEJAgAAAA==.Belwar:BAAALgADCgcJCAAAAA==.Beric:BAACLgAFFH8OAAIXAAQJcyCYAQCGAQAXAAQJcyCYAQCGAQAuAAQKfzAAAxcACAkbHFEDAJoCABcACAkbHFEDAJoCABgAAwlxDD88AGEAAAAA.Berriuster:BAAALgAECgIJAgAAAA==.Betadine:BAABLgAECn8VAAMUAAcJaxqbGwAAAgAUAAcJaxqbGwAAAgARAAMJ2QG8bAAiAAAAAA==.',
Bi='Bigboymanguy:BAAALgAECgUJBQAAAA==.Bigdkenergy:BAAALgAECgEJAQAAAA==.Billd:BAAALgADCgIJAgAAAA==.Billiemays:BAAALgAECgEJAwAAAA==.',
Bl='Blade:BAABLgAECn8hAAIGAAgJRhA6FgBvAQAGAAgJRhA6FgBvAQAAAA==.Blasterblade:BAAALgADCgMJAwAAAA==.Blaydesong:BAAALgAECgEJAQAAAA==.Blayse:BAAALgADCgUJBQABLgAECgQJBwAKAAAAAA==.Blayseknight:BAAALgAECgQJBwAAAA==.Blazinjohnny:BAABLgAECn8iAAISAAgJHCNYDwCyAgASAAgJHCNYDwCyAgAAAA==.Blightburn:BAABLgAECn8ZAAMGAAYJGRaIGQBMAQAGAAYJGRaIGQBMAQAFAAQJawebrwCtAAAAAA==.Blingblang:BAAALgADCgEJAQAAAA==.Blurpleberry:BAAALgADCgUJAwAAAA==.',
Bo='Boldan:BAAALgADCgUJCAAAAA==.Bombaclat:BAAALgAECgEJAgAAAA==.Bondarias:BAABLgAECn8cAAIZAAYJlAi/RADWAAAZAAYJlAi/RADWAAAAAA==.Boohaha:BAABLgAECn8XAAIJAAYJrSLJJgD3AQAJAAYJrSLJJgD3AQAAAA==.Borris:BAAALgAFFAIJAgAAAA==.',
Br='Brightwing:BAACLgAFFH8NAAIaAAQJVhsaDgBTAQAaAAQJVhsaDgBTAQAuAAQKfyIAAxoACQkKIW4EAAwDABoACQkKIW4EAAwDABsAAQmeEM5sADQAAAAA.Brigoryn:BAABLgAECn8hAAMcAAcJ+hZREgBWAQAcAAcJphZREgBWAQAdAAQJaQ42IQDSAAAAAA==.Brokenarro:BAAALgADCggJDgAAAA==.Browneyepie:BAAALgAECgQJBAAAAA==.',
Bu='Buchis:BAAALgADCgcJBwAAAA==.Bullshivek:BAABLgAECn8nAAINAAgJjhmKFwBCAgANAAgJjhmKFwBCAgAAAA==.Bussincider:BAAALgAECgQJBgAAAA==.',
Ca='Caale:BAABLgAECn8XAAIYAAcJoBJ9HgBDAQAYAAcJoBJ9HgBDAQAAAA==.Caecus:BAABLgAECn8kAAIeAAgJkxwNMAD4AQAeAAgJkxwNMAD4AQAAAA==.Calannie:BAAALgAECgMJAwAAAA==.Callsaul:BAAALgAECgMJBQAAAA==.Careillena:BAABLgAECn8ZAAIeAAgJVB1DKQAVAgAeAAgJVB1DKQAVAgAAAA==.Cate:BAAALgADCgYJCAAAAA==.Caylessa:BAAALgADCgcJBwAAAA==.Caylissa:BAABLgAECn8gAAINAAYJBwxfVQD1AAANAAYJBwxfVQD1AAAAAA==.',
Ce='Celithsong:BAAALgADCgMJAwABLgAECggJDgAKAAAAAA==.Celryth:BAAALgADCgIJAgAAAA==.Cenvoked:BAABLgAECn8nAAMaAAkJphYYGADUAQAaAAkJphYYGADUAQAbAAcJXg7uLgAkAQAAAA==.',
Cf='Cfs:BAAALgAECgQJBQAAAA==.',
Ch='Charcrash:BAACLgAFFH8HAAIFAAMJ5xrZNgD+AAAFAAMJ5xrZNgD+AAAuAAQKfyIAAwUACQkRIW0nAOYBAAUACQkRIW0nAOYBABYABglsEvkOAAoBAAAA.Charl:BAAALgADCgkJFgAAAA==.Charlicious:BAABLgAFFH8LAAIIAAMJxh+CQQAFAQAIAAMJxh+CQQAFAQABLgAFFAMJBwAFAOcaAA==.Chedwiwwiper:BAAALgADCgIJAgABLgAECgYJBgAKAAAAAA==.Cheylia:BAAALgAECgcJDQAAAA==.Chiller:BAAALgAECgUJCQAAAA==.Chimster:BAABLgAECn8iAAIPAAcJFiAIIQA/AgAPAAcJFiAIIQA/AgAAAA==.Chimydakilla:BAAALgAECgUJDgAAAA==.Chiva:BAAALgADCgIJAgAAAA==.Chknlttl:BAABLgAECn8nAAIfAAgJOiQDBQCKAgAfAAgJOiQDBQCKAgAAAA==.Chocomochi:BAAALgAECgcJDwAAAA==.Chompsky:BAAALgADCgEJAQAAAA==.Chrønic:BAAALgADCgUJCgAAAA==.Chuckstrike:BAAALgAECgYJEwAAAA==.Chyna:BAAALgAECgIJAwAAAA==.',
Ci='Cieara:BAAALgADCgYJCgAAAA==.Cinnamonbuns:BAAALgAECgIJAwABLgAECgYJDAAKAAAAAA==.',
Cl='Clicked:BAAALgADCgQJBAAAAA==.Clouver:BAAALgADCgYJBgAAAA==.Clown:BAAALgADCgcJBwAAAA==.',
Co='Cody:BAAALgAECgYJDwAAAA==.Constipated:BAAALgADCgUJCAAAAA==.Coolbeans:BAAALgAECgEJAQABLgAECgYJCQAKAAAAAA==.Corvò:BAAALgAECgQJCwABLgAECggJJwAfADokAA==.Cowwynowwy:BAAALgAECgcJDQAAAA==.',
Cr='Craeus:BAABLgAECn8nAAIJAAkJUSEGBQAdAwAJAAkJUSEGBQAdAwAAAA==.Crankertron:BAAALgAECgEJAQAAAA==.Credit:BAABLgAECn8zAAQRAAkJeh6pEwBWAgARAAgJph6pEwBWAgAgAAcJkBzFHACuAQAUAAEJrRL1VQA4AAAAAA==.Crine:BAAALgAECgYJBwABLgAECggJIwAbADkcAA==.Criztal:BAAALgADCggJGQAAAA==.Crotalus:BAAALgADCgEJBAAAAA==.Crux:BAAALgADCgMJAwAAAA==.',
Cu='Cupofnoodles:BAAALgAECgYJEAAAAA==.Cursedmayo:BAAALgADCgMJAwAAAA==.',
Cy='Cyerius:BAAALgADCgYJBQAAAA==.Cyonarah:BAABLgAECn8dAAIEAAcJsg7fewBDAQAEAAcJsg7fewBDAQAAAA==.',
Da='Dablinky:BAAALgAECgcJCAAAAA==.Dad:BAAALgAECgMJCgAAAA==.Dahlìa:BAAALgAECgQJBQAAAA==.Dannycheese:BAAALgAECgIJAwAAAA==.Daquarius:BAAALgAECgcJCwAAAA==.Darem:BAAALgAECgkJEwAAAA==.Darthis:BAAALgADCgUJBQAAAA==.Daywalker:BAAALgAECgcJCwABLgAECgcJFwAFALwfAA==.Daísy:BAAALgAECgQJBgAAAA==.',
De='Deadsword:BAAALgADCgEJAQAAAA==.Deanlol:BAAALgAECgEJAwABLgAECgMJBgAKAAAAAA==.Deaorva:BAAALgAECgMJAwAAAA==.Deathbringr:BAAALgAECgQJCgAAAA==.Deathspecter:BAAALgAECgcJCwAAAA==.Deidra:BAAALgAECgQJCAAAAA==.Deigh:BAAALgADCgYJBgAAAA==.Delryth:BAAALgADCgUJBQAAAA==.Demonchimy:BAAALgAECgYJCQAAAA==.Demonsitter:BAAALgAECgYJDwAAAA==.Dersdomkie:BAAALgAECggJDwAAAA==.Deshathoris:BAAALgAECgMJAwAAAA==.',
Di='Diggi:BAAALgAECgcJEgAAAA==.Diosa:BAABLgAECn8mAAIHAAgJ7xgWBQDQAQAHAAgJ7xgWBQDQAQAAAA==.Disciple:BAAALgADCgEJAQAAAA==.Dish:BAAALgAECgUJDwAAAA==.Divinekat:BAAALgAECggJEQAAAA==.',
Dk='Dkagon:BAABLgAECn8YAAMhAAYJ3RmlHQATAQAhAAYJ3RmlHQATAQAeAAEJ2AHFOwEbAAAAAA==.',
Do='Docfeelgood:BAAALgADCgIJAgAAAA==.Docholiday:BAAALgAECggJDQAAAA==.Doode:BAAALgAECgkJEAAAAA==.Dooderonomy:BAABLgAECn8jAAMUAAcJMRXPFgDPAQAUAAcJMRXPFgDPAQARAAcJdRHyJQBFAQAAAA==.Doria:BAAALgAECgEJAQAAAA==.Dovhakiin:BAAALgAECgMJAwAAAA==.',
Dp='Dpsguide:BAAALgAECgUJCgAAAA==.',
Dr='Drac:BAAALgAECgYJBgAAAA==.Dragaan:BAABLgAECn8YAAIEAAcJIwq4ggA2AQAEAAcJIwq4ggA2AQAAAA==.Dragonbait:BAABLgAECn9QAAISAAgJZiKFFgB+AgASAAgJZiKFFgB+AgAAAA==.Dragondude:BAAALgAECgcJDwAAAA==.Dragonoodles:BAAALgAECgMJAwABLgAECggJFgABAEMXAA==.Dragonzbane:BAABLgAECn8YAAISAAcJOwhWlgD7AAASAAcJOwhWlgD7AAAAAA==.Drawk:BAAALgAECgYJBQAAAA==.Drdoom:BAACLgAFFH8MAAMgAAQJCQr0GAAaAQAgAAQJCQr0GAAaAQAUAAEJNwYZFwA5AAAuAAQKfysABCAACAnwG2QMAFICACAACAnwG2QMAFICABQACAnlCqQuAIkBABEAAgnOEhhPAGsAAAAA.Dreamawake:BAABLgAECn8fAAIEAAgJAht6PgDfAQAEAAgJAht6PgDfAQAAAA==.Dreegs:BAAALgADCgYJBgABLgAECgUJCAAKAAAAAA==.Drek:BAAALgAECgUJDwAAAA==.Drenched:BAAALgAECgYJDAAAAA==.Drenea:BAAALgAECgQJAQAAAA==.Drimlek:BAAALgAECgEJAQAAAA==.Drin:BAAALgAECgcJCAAAAA==.Drunkey:BAABLgAECn8YAAIBAAcJdBmjIwDlAQABAAcJdBmjIwDlAQAAAA==.Drâxus:BAAALgAECgIJAgAAAA==.',
Du='Dualeafa:BAAALgAECgEJAQAAAA==.Duplicitous:BAAALgAECgUJBQAAAA==.',
Dw='Dwarfsham:BAAALgAECgMJBwAAAA==.Dwarvenrogue:BAAALgADCgMJAwAAAA==.',
Dy='Dyriana:BAAALgAECgQJAQAAAA==.',
Ea='Earlgrei:BAAALgADCgMJAwAAAA==.Earthmother:BAAALgAECgQJBQAAAA==.',
Ec='Eckhar:BAAALgADCgEJAQAAAA==.',
Ed='Edum:BAAALgAECgUJDwAAAA==.',
El='Elaveir:BAAALgADCgYJBwAAAA==.Elcie:BAAALgADCgkJEQAAAA==.Elektraka:BAAALgADCgYJBwAAAA==.Ellasian:BAAALgAECggJEwAAAA==.Eltria:BAACLgAFFH8ZAAIEAAUJShwNGABqAQAEAAUJShwNGABqAQAuAAQKfzAAAgQACQlgIYUTADMDAAQACQlgIYUTADMDAAAA.Elyndy:BAABLgAECn8tAAIfAAkJmB7KBACRAgAfAAkJmB7KBACRAgAAAA==.',
Em='Emishalle:BAAALgADCgMJAwAAAA==.Empathy:BAAALgADCgYJBgAAAA==.',
En='Ensoc:BAAALgAECgcJEwAAAA==.',
Ep='Ephel:BAABLgAECn8rAAMUAAkJ3hU4EQAQAgAUAAkJ3hU4EQAQAgARAAYJ3gYbOQDaAAAAAA==.',
Er='Erenia:BAAALgADCgMJAwAAAA==.Erí:BAAALgAECgYJEAAAAA==.',
Es='Essential:BAACLgAFFH8ZAAIiAAUJDyBvCwBcAQAiAAUJDyBvCwBcAQAuAAQKfzAAAiIACQlTIOYJAIACACIACQlTIOYJAIACAAAA.',
Et='Ethop:BAAALgAECgMJBQABLgAECgYJCQAKAAAAAA==.',
Eu='Eulali:BAAALgADCgIJAgAAAA==.',
Ez='Ezalth:BAAALgADCgcJCgAAAA==.Ezz:BAAALgADCggJFgAAAA==.',
Fa='Fachzile:BAAALgADCgcJDAAAAA==.Faden:BAAALgAECgQJBAABLgAECggJGgABAJMjAA==.Faenara:BAABLgAECn8nAAMZAAkJHhaFIAC0AQAZAAkJHhaFIAC0AQASAAYJ0QmxpQDhAAAAAA==.Faint:BAAALgAECgQJBAABLgAECgkJLgAZAAwhAA==.Falafelguy:BAABLgAECn8dAAIEAAgJTBw2OwDrAQAEAAgJTBw2OwDrAQAAAA==.Falron:BAAALgADCgYJBgAAAA==.Fayzon:BAABLgAECn8fAAIYAAcJIxkyFgCWAQAYAAcJIxkyFgCWAQAAAA==.',
Fb='Fbomb:BAAALgAECgQJBAAAAA==.',
Fe='Fedange:BAABLgAECn8iAAIcAAkJegNGIgC5AAAcAAkJegNGIgC5AAAAAA==.Felartamiel:BAAALgAECgIJAQAAAA==.Felician:BAAALgADCgcJBwAAAA==.Felii:BAAALgAECgEJAQAAAA==.Felini:BAAALgADCgcJBgAAAA==.Felisin:BAAALgADCgYJBgAAAA==.Felkieler:BAABLgAECn8dAAIFAAcJnwTylACgAAAFAAcJnwTylACgAAAAAA==.Ferror:BAAALgADCgMJAwAAAA==.Festermight:BAAALgADCgEJAQAAAA==.Fey:BAABLgAECn8TAAIFAAYJrSEXPwD4AQAFAAYJrSEXPwD4AQAAAA==.Feydris:BAAALgADCgYJBgABLgADCgYJBgAKAAAAAA==.',
Fi='Fieperskaivu:BAAALgAECgYJCAABLgAECgcJFwAFALwfAA==.Fiorstrasza:BAAALgADCgIJBgAAAA==.Fireyfox:BAAALgAECgUJBgABLgAECggJIQAaAMcVAA==.',
Fj='Fjc:BAAALgADCgEJAQAAAA==.Fjshamie:BAAALgADCgcJCQABLgAECgIJAgAKAAAAAA==.',
Fl='Flavoune:BAAALgAECgEJAQAAAA==.Flee:BAAALgADCgYJCgAAAA==.',
Fo='Forestspirit:BAABLgAECn8pAAMNAAkJaBJDJwDPAQANAAkJaBJDJwDPAQATAAEJuwXBdQAhAAAAAA==.Forkliftcert:BAABLgAECn8XAAIFAAYJChJabwDxAAAFAAYJChJabwDxAAAAAA==.Foxxee:BAAALgAECgYJBgAAAA==.',
Fr='Friednoodle:BAAALgADCgEJAQAAAA==.',
Fu='Fuzzlessly:BAACLgAFFH8IAAIZAAMJayHRGgAAAQAZAAMJayHRGgAAAQAuAAQKfysAAhkACQmEI8UCAEsDABkACQmEI8UCAEsDAAAA.',
['Fá']='Fárhund:BAAALgAECgQJBAABLgAECgYJEgAKAAAAAA==.',
['Fí']='Físted:BAAALgADCgUJAwAAAA==.',
['Fö']='Föxxee:BAAALgAECgUJBQAAAA==.',
Ga='Galaxyman:BAAALgAECgMJAwAAAA==.Gano:BAAALgADCgcJBwAAAA==.Gapeilous:BAAALgAECgMJAwAAAA==.Garbanzo:BAAALgADCgYJBgAAAA==.Gargosa:BAABLgAECn8jAAMPAAgJ7BAvPQCWAQAPAAgJcBAvPQCWAQAjAAYJFAyoGQA1AQAAAA==.Garybusey:BAAALgAECgEJAQAAAA==.',
Ge='Geist:BAACLgAFFH8ZAAMSAAUJqh+eEQB3AQASAAUJqh+eEQB3AQAkAAEJ7gUNCQArAAAuAAQKfyoAAxIACQkkIcspAH0CABIACQkkIcspAH0CACQACAlhDpkUAIUBAAAA.Geraith:BAACLgAFFH8ZAAIhAAUJzyIHBwCDAQAhAAUJzyIHBwCDAQAuAAQKfzAAAiEACQmGIyYDANwCACEACQmGIyYDANwCAAAA.Gerios:BAABLgAECn8gAAIPAAkJBRcJIAAXAgAPAAkJBRcJIAAXAgAAAA==.',
Gg='Ggparts:BAAALgADCgIJAgABLgAECgUJCgAKAAAAAA==.',
Gh='Ghefgar:BAAALgAECgYJCwABLgAECgkJCQAKAAAAAA==.Ghostflair:BAAALgAECgEJAQAAAA==.Ghostflare:BAABLgAECn8bAAIUAAgJVR1ICwCbAgAUAAgJVR1ICwCbAgAAAA==.',
Gi='Girth:BAAALgAECgEJAgAAAA==.',
Gl='Glendra:BAABLgAECn8tAAIkAAkJuBUoCgDSAQAkAAkJuBUoCgDSAQAAAA==.Gloomfx:BAABLgAECn8dAAIRAAcJpA0BLwAPAQARAAcJpA0BLwAPAQAAAA==.Glowfish:BAABLgAECn8gAAIBAAgJ5hCvJABIAQABAAgJ5hCvJABIAQAAAA==.Glowleaf:BAAALgAECgEJAQAAAA==.Glynisle:BAAALgAECgYJBwAAAA==.',
Go='Goatboat:BAAALgADCgYJCgAAAA==.Gohan:BAAALgADCgYJBgAAAA==.Goopz:BAAALgADCgcJBwAAAA==.Gorasu:BAAALgADCgYJBgAAAA==.Gorbosplort:BAAALgAECgEJAQABLgAFFAYJFAAGALIUAA==.',
Gr='Grandeeny:BAAALgAECgYJEQAAAA==.Grandgrimm:BAAALgAECgQJBwAAAA==.Grandragon:BAAALgAECgMJBgAAAA==.Grandzob:BAABLgAECn8UAAITAAUJgwiARACjAAATAAUJgwiARACjAAAAAA==.Gravix:BAAALgADCgYJBgABLgAFFAQJCQAjAMohAA==.Greensleeves:BAAALgAECgQJAQAAAA==.Gregoriusz:BAACLgAFFH8NAAIQAAQJfB4uCABqAQAQAAQJfB4uCABqAQAuAAQKfyYAAhAACQk6IBEWAIACABAACQk6IBEWAIACAAAA.Greygull:BAABLgAECn8XAAIiAAYJ3g78PgD3AAAiAAYJ3g78PgD3AAAAAA==.Grimfrost:BAAALgAECgQJCwAAAA==.Grimshadows:BAAALgADCgEJAQAAAA==.Grissle:BAAALgADCgQJBAAAAA==.Grunin:BAAALgADCgcJEgAAAA==.Grußen:BAAALgADCgIJAgAAAA==.',
Gu='Guntank:BAABLgAECn8mAAMiAAkJdh5oCACYAgAiAAkJdh5oCACYAgAfAAQJwhLBLgDNAAAAAA==.Guntenk:BAAALgAECgQJBAAAAA==.Guzzi:BAAALgAECgQJBQAAAA==.',
Gy='Gyaltsen:BAAALgAFFAEJAQAAAA==.',
Ha='Hailo:BAAALgAECgMJBwAAAA==.Halliestar:BAAALgAECggJEgAAAA==.Hanui:BAAALgADCgYJBwAAAA==.Harrypalmz:BAAALgAECggJCAABLgAECgkJMgAkAIsTAA==.Hategnomer:BAAALgAECgQJAQAAAA==.Havenfell:BAABLgAECn8eAAIfAAkJGB4ZBwBOAgAfAAkJGB4ZBwBOAgAAAA==.Hawkfist:BAABLgAECn8qAAIPAAkJYxi8HQAlAgAPAAkJYxi8HQAlAgAAAA==.',
He='Healztruck:BAAALgAECgEJAgAAAA==.Hecate:BAABLgAECn8WAAIIAAkJqQUomAAoAQAIAAkJqQUomAAoAQAAAA==.Heinzz:BAAALgAECgcJDAAAAA==.Helah:BAAALgAECgYJBwAAAA==.Hercules:BAABLgAECn8bAAIeAAgJ8xcWOADZAQAeAAgJ8xcWOADZAQAAAA==.Hestet:BAAALgAECgUJBQAAAA==.',
Hi='Hierodoulos:BAABLgAECn8vAAINAAkJ1SPTAQCXAwANAAkJ1SPTAQCXAwAAAA==.Histano:BAAALgAECgcJDAAAAA==.',
Ho='Holopearl:BAAALgAECgEJAQAAAA==.Honeygold:BAAALgAECgEJAQABLgAFFAQJDQAQAHweAA==.Hotcha:BAAALgADCgUJBQAAAA==.Houdro:BAAALgAECgEJAgAAAA==.Howleyberry:BAAALgAECgEJAQAAAA==.',
Hr='Hroth:BAAALgAECgUJBQABLgAECgkJLgAZAAwhAA==.Hrothgar:BAAALgAECgUJBQABLgAECgkJLgAZAAwhAA==.',
Hu='Hunteroni:BAAALgAECgQJBgABLgAECggJFgABAEMXAA==.Huonn:BAAALgAECgYJDgAAAA==.Huuguu:BAAALgADCgEJAQABLgAECgEJAwAKAAAAAA==.',
Hy='Hyper:BAAALgADCgMJAwAAAA==.Hypoluxo:BAAALgAECgEJAQAAAA==.',
['Hô']='Hôjack:BAAALgADCgMJAwAAAA==.',
Ib='Ibanangel:BAAALgAECgYJCQAAAA==.',
Ic='Icenea:BAAALgAECgMJAwABLgAFFAMJCwAPALAgAA==.',
Il='Illeiria:BAAALgADCgUJBQAAAA==.Illerdanu:BAAALgAECggJDgAAAA==.Illhighbread:BAAALgADCgIJAgAAAA==.Illtud:BAAALgAECgQJBwAAAA==.',
Im='Impastable:BAAALgADCgcJCgABLgAECggJFgABAEMXAA==.Impastabrew:BAABLgAECn8WAAIBAAgJQxfkEwDTAQABAAgJQxfkEwDTAQAAAA==.Imrhien:BAAALgADCgcJCgAAAA==.',
In='Inohoe:BAAALgADCgYJBgAAAA==.Inola:BAABLgAECn8oAAIUAAgJzBI7HgCJAQAUAAgJzBI7HgCJAQAAAA==.Intheron:BAAALgAECgYJCwAAAA==.',
Ir='Ironfur:BAAALgADCgcJDAABLgAECgcJFwAfAK8fAA==.',
Is='Iskrå:BAABLgAECn8iAAIVAAcJzyC4AQAXAgAVAAcJzyC4AQAXAgAAAA==.',
Iv='Ivellos:BAAALgAECgQJBwABLgAECgcJEwAKAAAAAA==.',
Ja='Jacynth:BAAALgAECgYJCgAAAA==.Jaid:BAAALgADCggJCAAAAA==.Jaimers:BAABLgAECn8vAAQgAAkJcx4wBAASAwAgAAkJCB4wBAASAwAUAAcJ9Bv5FAA1AgARAAMJAAfWVABwAAAAAA==.Januz:BAAALgAECgYJCQAAAA==.Javlos:BAAALgAECgQJBgAAAA==.Jaxen:BAABLgAECn8YAAIIAAkJHAexWwBNAQAIAAkJHAexWwBNAQAAAA==.Jaywilde:BAABLgAECn8lAAIiAAkJ/B0QCACdAgAiAAkJ/B0QCACdAgAAAA==.Jaína:BAAALgADCgcJEwAAAA==.',
Je='Jedzia:BAAALgAECgIJAQAAAA==.Jeeffee:BAAALgAECgUJCgAAAA==.Jeep:BAABLgAECn8nAAIeAAkJvgzTQwCwAQAeAAkJvgzTQwCwAQAAAA==.Jezell:BAAALgADCgMJAwAAAA==.',
Ji='Jizakazam:BAAALgAECgUJBgAAAA==.',
Jo='Joode:BAAALgAECgEJAQAAAA==.',
Ju='Juggyspally:BAAALgAECgkJDgAAAA==.Julls:BAAALgAECgEJAQAAAA==.Justbringit:BAEALgADCgIJAgABLgAECgkJJAAFADsiAA==.',
Ka='Kammi:BAAALgAECgYJDwAAAA==.Karot:BAABLgAECn8XAAIFAAYJ+AxofgAuAQAFAAYJ+AxofgAuAQABLgAECgkJKgAeAMEdAA==.Karotten:BAABLgAECn8qAAMeAAkJwR0KEQCmAgAeAAkJwR0KEQCmAgAhAAIJvwIwQwA0AAAAAA==.Karthair:BAABLgAECn8hAAQaAAgJxxUyCQANAgAaAAgJxxUyCQANAgAbAAQJrwmYUACJAAAlAAEJgAioQgAqAAAAAA==.Katsumotto:BAAALgADCgMJAwABLgAECgEJAQAKAAAAAA==.Kaylessa:BAAALgAECgEJAQAAAA==.Kazi:BAAALgAECgYJDwAAAA==.',
Ke='Keello:BAAALgAECgkJCgAAAA==.Kezialilly:BAAALgAECgEJAwAAAA==.',
Kh='Khalasar:BAAALgAECgcJCQAAAA==.Khaleessi:BAAALgADCgYJBgAAAA==.',
Ki='Kianlan:BAAALgADCgUJBgAAAA==.Kiaraa:BAAALgADCggJEwAAAA==.Kintsugi:BAAALgAECgQJCwAAAA==.Kisatchie:BAABLgAECn8gAAIcAAYJAhfoEwBBAQAcAAYJAhfoEwBBAQAAAA==.Kival:BAABLgAECn8VAAIIAAYJRxPBagApAQAIAAYJRxPBagApAQAAAA==.Kivrin:BAAALgAECgEJAQAAAA==.',
Kn='Knawls:BAABLgAECn8aAAMTAAkJdhPJIwBQAQAdAAYJuxdxEQCWAQATAAgJ5A3JIwBQAQAAAA==.',
Ko='Koalitsiya:BAABLgAECn8eAAQIAAcJFQRWoAC9AAAIAAcJXQNWoAC9AAAHAAIJ0ATtXwBPAAAOAAEJQAOINQAwAAAAAA==.Kookykrum:BAAALgAECgQJBQAAAA==.Korlys:BAAALgADCgEJAQABLgAECgYJDwAKAAAAAA==.Korvidia:BAAALgAECgYJDAAAAA==.Koyoshial:BAAALgADCgYJCwABLgAECgQJBAAKAAAAAA==.Kozãk:BAAALgADCgYJCQAAAA==.',
Kp='Kpop:BAAALgADCgEJAQAAAA==.',
Kr='Kracklin:BAAALgAECgIJCgAAAA==.Krimez:BAABLgAECn8jAAIbAAgJORyMDwAlAgAbAAgJORyMDwAlAgAAAA==.Krow:BAAALgAECgIJBQABLgAECgIJBgAKAAAAAA==.Kruzex:BAAALgAECgEJAQABLgAECgIJBgAKAAAAAA==.Kryne:BAABLgAECn8UAAMGAAYJ7RKIHgAdAQAGAAYJzhKIHgAdAQAWAAIJQxGlHQBdAAABLgAECggJIwAbADkcAA==.Krynez:BAAALgADCgUJBQABLgAECggJIwAbADkcAA==.',
Ku='Kungfukat:BAAALgAECgQJBAAAAA==.Kurgash:BAAALgAECgQJBwAAAA==.',
Ky='Kyari:BAAALgAECgYJCAAAAA==.Kymerah:BAAALgAECgIJAgAAAA==.Kyrhios:BAABLgAECn8cAAIiAAYJ2SO+JgAlAgAiAAYJ2SO+JgAlAgAAAA==.',
['Kä']='Käggai:BAABLgAECn8XAAMiAAYJ1yGQMADsAQAiAAYJYiCQMADsAQAmAAQJwRkmHAAPAQAAAA==.',
La='Laindra:BAAALgADCgMJAwAAAA==.Lark:BAABLgAECn8eAAIfAAcJxRgUEQCGAQAfAAcJxRgUEQCGAQAAAA==.Larthas:BAAALgAECgYJCwAAAA==.Lascie:BAABLgAECn8jAAIEAAkJMBu3IgBUAgAEAAkJMBu3IgBUAgAAAA==.Latrunculon:BAAALgADCgQJBAAAAA==.Lazra:BAAALgADCgcJEQAAAA==.',
Le='Leafykat:BAAALgAECgQJCAAAAA==.Leaila:BAAALgAECgcJEQAAAA==.Lealia:BAABLgAECn8aAAMMAAYJtSFHIgD9AQAMAAYJtSFHIgD9AQALAAEJAALkLwAkAAABLgAFFAMJCwAPALAgAA==.Leatsz:BAABLgAECn8aAAMeAAgJRg7OaAC8AQAeAAgJRg7OaAC8AQAhAAEJAAAgUQAAAAAAAA==.Legendfox:BAAALgADCgIJAgAAAA==.Leiha:BAAALgAECgMJBAAAAA==.',
Lg='Lgfuad:BAAALgAECgcJDwAAAA==.',
Li='Liams:BAAALgAECgcJDgAAAA==.Lidori:BAAALgADCggJEwAAAA==.Lightsent:BAAALgADCgUJBQABLgAECgEJAQAKAAAAAA==.Lilmankog:BAAALgAECgkJCQAAAA==.Lilíth:BAABLgAECn8fAAIhAAkJ/wU8HgAOAQAhAAkJ/wU8HgAOAQAAAA==.Linux:BAABLgAECn8mAAIPAAgJrRmdKQDnAQAPAAgJrRmdKQDnAQAAAA==.Lisânalgaib:BAAALgAECgQJDAAAAA==.Livide:BAABLgAECn8YAAMUAAgJAR7PCwCUAgAUAAcJ9h/PCwCUAgAgAAgJsA19GwC6AQAAAA==.',
Ll='Llama:BAABLgAECn8nAAIBAAgJaBiqEgDgAQABAAgJaBiqEgDgAQAAAA==.',
Lo='Lokzilla:BAAALgAECgYJBgAAAA==.Lonamire:BAAALgADCgcJCQAAAA==.',
Lu='Lucithance:BAABLgAECn8WAAISAAgJIwiEewArAQASAAgJIwiEewArAQAAAA==.Luminarra:BAAALgADCgMJAwAAAA==.Luminianna:BAABLgAECn8hAAMlAAkJ0R22AgBKAgAlAAgJGh62AgBKAgAbAAgJKxIeMgA4AQAAAA==.',
Ly='Lydrin:BAAALgAECgQJBQABLgAECggJFAAcALcTAA==.Lynerys:BAAALgAECgYJDwAAAA==.Lynnsbussy:BAAALgAECgQJEgAAAA==.Lytol:BAAALgAECgYJCAAAAA==.',
Ma='Macloc:BAAALgAECgMJBAAAAA==.Madmike:BAAALgAECgQJBAAAAA==.Maedae:BAABLgAECn8XAAIgAAkJ2gYOHgCAAQAgAAkJ2gYOHgCAAQAAAA==.Maggiemae:BAAALgAECgEJAQAAAA==.Magmyr:BAAALgAECgcJEQAAAA==.Mahli:BAABLgAECn8kAAMIAAkJiCDxFABvAgAIAAgJWx7xFABvAgAHAAMJGh8BMgDwAAAAAA==.Maimah:BAABLgAECn8YAAIEAAYJ3x8kawD/AQAEAAYJ3x8kawD/AQAAAA==.Manpandalock:BAAALgAECgEJBAAAAA==.Maplefire:BAAALgAECgEJAQAAAA==.Marrias:BAAALgAECgUJBwAAAA==.Mawrix:BAABLgAECn8sAAQXAAgJARV6CAB5AQAYAAgJmBLwFACjAQAXAAcJlBN6CAB5AQAnAAQJzwyDDQDWAAAAAA==.Maxieflames:BAAALgAECgIJAgAAAA==.',
Mc='Mcguzzler:BAAALgAECgMJAwAAAA==.',
Me='Melwazul:BAAALgADCgUJBQAAAA==.Meoshi:BAABLgAECn8bAAIEAAgJhxA6WACTAQAEAAgJhxA6WACTAQAAAA==.Merk:BAAALgAECgcJDAAAAA==.Mesuryte:BAACLgAFFH8XAAIjAAYJqh2fAQDKAQAjAAYJqh2fAQDKAQAuAAQKfyYAAiMACAnxJAACAC4DACMACAnxJAACAC4DAAAA.',
Mi='Mibs:BAABLgAECn8rAAIiAAkJnyFuBQDQAgAiAAkJnyFuBQDQAgAAAA==.Micheälwilde:BAAALgADCgEJAQAAAA==.Mickal:BAABLgAECn8lAAISAAkJOQmmVwB7AQASAAkJOQmmVwB7AQAAAA==.Mihya:BAAALgADCgcJBwAAAA==.Mikaelangelo:BAAALgAECgcJEgAAAA==.Mintebrew:BAAALgAECgYJDQAAAA==.Mip:BAABLgAECn8VAAIIAAgJ4AqSXgBFAQAIAAgJ4AqSXgBFAQAAAA==.Mirie:BAAALgAECgYJEQAAAA==.Misfires:BAAALgADCgEJAQAAAA==.',
Mn='Mnrogar:BAAALgADCgMJBAAAAA==.',
Mo='Mohegon:BAAALgADCgMJAwAAAA==.Mohini:BAABLgAECn8qAAMTAAkJvhsECQB7AgATAAkJvhsECQB7AgANAAQJLQ/yiADDAAAAAA==.Mohproblems:BAAALgAECgQJBAAAAA==.Mojhohammers:BAAALgAECgQJCAAAAA==.Mokaki:BAABLgAECn8UAAISAAYJaCGZSgADAgASAAYJaCGZSgADAgAAAA==.Molumens:BAAALgAECgYJCAAAAA==.Monkified:BAAALgAECgIJAgABLgAFFAYJHwAaAJcVAA==.Montmorency:BAAALgAECgIJAgAAAA==.Monzil:BAAALgAECggJEgAAAA==.Moogician:BAABLgAECn8WAAIEAAgJBhPvUwCeAQAEAAgJBhPvUwCeAQAAAA==.Moomama:BAAALgADCgIJAgAAAA==.Moonren:BAAALgADCgYJBgAAAA==.Moonsinna:BAAALgAECgQJCAAAAA==.Mooshoofasa:BAAALgADCgMJAwAAAA==.Mooter:BAABLgAECn8qAAIXAAkJBhdCBQA9AgAXAAkJBhdCBQA9AgAAAA==.Mornix:BAABLgAECn8UAAIeAAgJPhcXPADLAQAeAAgJPhcXPADLAQABLgAECgEJAQAKAAAAAA==.Moronic:BAAALgAECgEJAQAAAA==.Mortincarne:BAAALgADCgIJAgAAAA==.',
Mu='Mukwaa:BAAALgAECgYJEAAAAA==.Munc:BAAALgADCgYJBgAAAA==.Munchwizard:BAAALgAECgEJAgAAAA==.Murglun:BAAALgAECgQJBAAAAA==.Mushroom:BAABLgAECn8iAAIEAAcJtCbgFgCXAgAEAAcJtCbgFgCXAgAAAA==.',
My='Mystic:BAAALgAECgYJDAAAAA==.',
Na='Nahaz:BAAALgAECgMJAQAAAA==.Namuswanbrok:BAAALgADCgIJAQAAAA==.Naota:BAABLgAECn8pAAIeAAkJVBy9GQBpAgAeAAkJVBy9GQBpAgAAAA==.Naqii:BAAALgAECgMJAwAAAA==.Naqsx:BAAALgAECgYJDwAAAA==.Nareda:BAAALgAECgIJAgAAAA==.Narfox:BAABLgAECn8jAAMMAAgJ9ge5MwASAQAMAAgJ9ge5MwASAQAJAAcJawk3UQAGAQAAAA==.Naryb:BAABLgAECn8aAAIIAAgJ+BKiQwCRAQAIAAgJ+BKiQwCRAQAAAA==.Naturchimye:BAAALgAECgEJAgAAAA==.Naughtia:BAAALgADCgEJAQAAAA==.',
Ne='Neameto:BAABLgAECn8jAAMbAAkJ3BWjFQDhAQAbAAkJ3BWjFQDhAQAlAAIJSwieOABUAAAAAA==.Necrophyle:BAABLgAECn8lAAMhAAgJ/hQpEgCUAQAhAAgJ/hQpEgCUAQAeAAYJTAYtuAASAQAAAA==.Ned:BAAALgAECgEJAgABLgAFFAQJDQAXAAolAA==.Nefarox:BAABLgAECn8hAAIWAAYJsxgdCwBUAQAWAAYJsxgdCwBUAQAAAA==.Neon:BAABLgAECn8rAAIMAAkJFR9OCACTAgAMAAkJFR9OCACTAgAAAA==.Nerfdarts:BAAALgADCgIJAgAAAA==.Ness:BAAALgADCgYJCgAAAA==.',
Nh='Nhugpow:BAAALgADCgkJCQAAAA==.',
Ni='Nicholas:BAACLgAFFH8QAAIbAAQJZBI4DQAuAQAbAAQJZBI4DQAuAQAuAAQKfzQAAxsACAkaIuQIAOoCABsACAkaIuQIAOoCACUAAQkrDHkdADIAAAEuAAUUBAkQABsAZBIA.Nightriderr:BAAALgAECgEJAgAAAA==.Nightstealer:BAABLgAECn8cAAMTAAcJewe+PQDAAAATAAcJewe+PQDAAAANAAEJBgG06wAXAAAAAA==.Nika:BAACLgAFFH8NAAMeAAQJZBetNgBHAQAeAAQJZBetNgBHAQAoAAIJoQeJDQCIAAAuAAQKfyAAAh4ACAnPHxsnAJ8CAB4ACAnPHxsnAJ8CAAAA.Nikkikayama:BAACLgAFFH8XAAMPAAUJOB0mBABdAQAPAAUJOB0mBABdAQAQAAEJnQLqLAA/AAAuAAQKfywAAw8ACQljJVoDACsDAA8ACQljJVoDACsDABAAAgmiBEN7AFYAAAAA.',
No='Nobzz:BAAALgADCggJEAAAAA==.Nofuratu:BAABLgAECn8lAAMTAAgJxAtnKQAqAQATAAgJxAtnKQAqAQANAAMJTQX6qwBuAAAAAA==.Noncomplex:BAAALgAECgYJBgAAAA==.Nonextinct:BAAALgADCggJFwAAAA==.Nonstopped:BAAALgADCgYJBgAAAA==.Nooglet:BAAALgAECgIJAgAAAA==.Noriel:BAAALgADCgEJAgAAAA==.Norikoff:BAACLgAFFH8JAAIiAAMJdBWcEAADAQAiAAMJdBWcEAADAQAuAAQKfywAAyIACQluIZgHAC8DACIACQluIZgHAC8DACYAAgnrHm4oAKwAAAAA.Noromir:BAAALgADCgQJBAABLgAECggJGwARAMENAA==.Norrad:BAAALgAECgEJAQAAAA==.',
Nu='Nubblz:BAAALgAECgQJBQAAAA==.Nutbar:BAAALgADCgYJBgAAAA==.',
Ny='Nynox:BAABLgAECn8bAAMPAAgJmwtoTwBZAQAPAAgJmwtoTwBZAQAQAAQJZgR+bgCFAAAAAA==.',
['Nê']='Nêin:BAABLgAECn8aAAIIAAgJpwkFXQBJAQAIAAgJpwkFXQBJAQAAAA==.',
['Nó']='Nóvà:BAAALgADCgYJBgAAAA==.',
Od='Odenpanda:BAAALgADCgEJAQABLgADCgQJBAAKAAAAAA==.',
Of='Offdensen:BAAALgAECgYJCQAAAA==.',
Oh='Ohdii:BAAALgADCgIJAgAAAA==.',
Ok='Okämi:BAAALgAECgQJCwAAAA==.',
Ol='Oldmims:BAAALgAECgkJDwAAAA==.Oldmimse:BAABLgAECn8fAAMOAAgJFyNAAwAhAgAOAAgJFyNAAwAhAgAIAAUJfhIscAAeAQABLgAECgkJDwAKAAAAAA==.Oldmimsy:BAAALgADCgEJAgABLgAECgkJDwAKAAAAAA==.',
On='Onedge:BAAALgAECgEJAQAAAA==.Onlybatfans:BAAALgAECgUJBQAAAA==.Onlyvlprfans:BAACLgAFFH8XAAILAAUJ5CGLAQCQAQALAAUJ5CGLAQCQAQAuAAQKfzAAAgsACQlEJCcBAAADAAsACQlEJCcBAAADAAAA.',
Oo='Oojoc:BAAALgADCgEJAQAAAA==.Oojocadin:BAAALgAECgYJDwAAAA==.Oojocshan:BAAALgADCgUJCgABLgAECgYJDwAKAAAAAA==.',
Op='Ophina:BAAALgAECgUJEQAAAA==.',
Or='Orangejello:BAABLgAECn8iAAISAAcJohLAfQAnAQASAAcJohLAfQAnAQAAAA==.Orasa:BAAALgAECgEJAQAAAA==.Ormar:BAABLgAECn8XAAIUAAkJzRlmDABUAgAUAAkJzRlmDABUAgAAAA==.Orodruin:BAAALgADCggJEwAAAA==.Orpseroth:BAABLgAECn8bAAMRAAgJwQ2oJQCrAQARAAgJwQ2oJQCrAQAgAAUJPg4nLwACAQAAAA==.',
Ow='Own:BAAALgAECgkJCwAAAA==.',
Ox='Oxenman:BAAALgAECgMJAwAAAA==.Oxensham:BAABLgAECn8oAAIMAAkJvBdNEgAKAgAMAAkJvBdNEgAKAgAAAA==.',
Pa='Paiah:BAAALgADCgQJBgAAAA==.Paladintank:BAABLgAECn8qAAMkAAkJXBo6BgA1AgAkAAkJXBo6BgA1AgASAAEJ9AEAAAAAAAAAAA==.Pallyboo:BAAALgADCgUJBQAAAA==.Pallykillers:BAAALgAECgQJCAAAAA==.Pallymedic:BAAALgAECgUJBwAAAA==.Pana:BAABLgAECn8YAAISAAkJLyGuNwDbAQASAAkJLyGuNwDbAQAAAA==.Pandaoden:BAAALgADCgQJBAAAAA==.Pandoora:BAAALgAECgQJBwAAAA==.Pandy:BAABLgAECn8UAAIJAAcJVA7YPABZAQAJAAcJVA7YPABZAQAAAA==.Pandóra:BAACLgAFFH8LAAIEAAQJIxl4MgBSAQAEAAQJIxl4MgBSAQAuAAQKfx8AAgQACQl4HUAzAKYCAAQACQl4HUAzAKYCAAAA.Panko:BAABLgAECn8lAAQDAAgJ+huMFQAYAgADAAgJ+huMFQAYAgABAAMJuQKhYABWAAACAAEJxQioiAAnAAAAAA==.Pannifer:BAAALgAECgYJCgAAAA==.Paolon:BAABLgAECn8YAAMMAAcJ9x6vFADxAQAMAAcJ9x6vFADxAQAJAAEJDBidngAyAAAAAA==.Papasmurph:BAAALgADCgMJBAAAAA==.Papst:BAAALgADCgMJAwAAAA==.Parple:BAAALgAECgYJCAABLgAECgkJMwARAMEkAA==.Passmidnight:BAAALgADCgEJAgAAAA==.',
Pe='Peeperoni:BAAALgADCgYJBgAAAA==.Pepperbacca:BAAALgADCgcJEwAAAA==.Persepolïs:BAAALgAECggJDgAAAA==.Pescara:BAABLgAECn8YAAIiAAcJ4wcYPAAEAQAiAAcJ4wcYPAAEAQAAAA==.Pestîlence:BAAALgADCgUJBQAAAA==.Peter:BAAALgAECgMJAwABLgAECggJEgAKAAAAAA==.Petestreat:BAABLgAECn8TAAIEAAgJbgwoagBoAQAEAAgJbgwoagBoAQAAAA==.Pewster:BAAALgADCgUJBQAAAA==.',
Ph='Phantõm:BAAALgADCgYJCAAAAA==.Phinns:BAAALgAECgQJAwAAAA==.Phylo:BAAALgADCgEJAQAAAA==.',
Pi='Pian:BAAALgADCgkJFgAAAA==.Picker:BAAALgAECgkJDwAAAA==.Pinecones:BAAALgAECgQJBAAAAA==.',
Po='Polycurious:BAAALgAFFAIJAgAAAA==.Porterah:BAAALgAECggJDgAAAA==.Poughkeepsie:BAAALgADCgkJDgAAAA==.',
Pr='Predation:BAAALgADCgUJBQAAAA==.Profanus:BAAALgAECggJCQABLgAECggJGgABAJMjAA==.',
Pt='Ptolemus:BAAALgADCggJDgAAAA==.',
Pu='Puffthemagic:BAAALgADCgMJAwABLgAECgYJCQAKAAAAAA==.Punchkun:BAABLgAECn8sAAMIAAkJKBg3IwAXAgAIAAkJKBg3IwAXAgAHAAQJmBs4EQDjAAAAAA==.Punkvc:BAABLgAECn8rAAIPAAkJwSBKCwC3AgAPAAkJwSBKCwC3AgAAAA==.Purificatory:BAAALgADCgIJAgAAAA==.',
['Pá']='Párts:BAAALgAECgEJAQABLgAECgUJCgAKAAAAAA==.',
Qu='Quaeras:BAABLgAECn8lAAIQAAkJ5xXTBQD7AQAQAAkJ5xXTBQD7AQAAAA==.Quonnoth:BAABLgAECn8dAAMbAAgJbQ6bJwBPAQAbAAgJbQ6bJwBPAQAlAAEJUQG9RgAVAAAAAA==.',
Ra='Raevynn:BAABLgAFFH8HAAIIAAIJexm5ZQClAAAIAAIJexm5ZQClAAABLgAFFAYJHwAaAJcVAA==.Ragath:BAAALgAECgYJDQAAAA==.Ragé:BAEBLgAECn8kAAMFAAkJOyJ8DACmAgAFAAgJzyN8DACmAgAGAAgJORqICgAgAgAAAA==.Ralphe:BAABLgAECn8dAAMYAAgJ0Ro8GwAnAgAYAAcJ/xs8GwAnAgAXAAcJdhbgCgBAAQAAAA==.Ranahu:BAABLgAECn8UAAQcAAgJtxOyDwB6AQAcAAcJoBayDwB6AQATAAYJPQoLWgC7AAAdAAEJRQLtPAAWAAAAAA==.Rashygroin:BAAALgADCgkJBwABLgAECgkJIwAEADAbAA==.Rawrionik:BAAALgADCgMJAwAAAA==.Raytow:BAAALgAECgQJDQAAAA==.Raytwo:BAAALgADCgQJBAAAAA==.Razath:BAAALgADCgEJAQABLgAECggJIwAeAEwZAA==.Razelle:BAABLgAECn8nAAIEAAgJ4wYgjAAkAQAEAAgJ4wYgjAAkAQAAAA==.',
Re='Reckies:BAABLgAECn8XAAITAAgJigrKPABBAQATAAgJigrKPABBAQAAAA==.Reconpalymix:BAAALgAECgQJCQAAAA==.Remus:BAABLgAECn8WAAMZAAYJ3gxJOgAOAQAZAAYJ3gxJOgAOAQASAAIJkApW9wBkAAAAAA==.Reshad:BAABLgAECn8dAAMJAAcJnQ07QgBCAQAJAAcJnQ07QgBCAQAMAAYJUgLlXQBsAAAAAA==.Respectwomen:BAAALgAECgEJAwAAAA==.Ressix:BAABLgAECn8pAAISAAkJtB7yDgC1AgASAAkJtB7yDgC1AgAAAA==.Retahdin:BAAALgAECgEJAQAAAA==.Retriblution:BAAALgAECgMJAwAAAA==.Rettung:BAAALgAECgIJAgABLgAECgkJGQAZAMUfAA==.Rettungslos:BAAALgAECgYJEgABLgAECgkJGQAZAMUfAA==.',
Rh='Rhaeyn:BAAALgAECgQJBAAAAA==.',
Ri='Ricktick:BAAALgADCgYJBgAAAA==.Rickybobby:BAAALgAECgQJBAAAAA==.Rininewblood:BAAALgADCgcJBwAAAA==.Rivvik:BAAALgAECgEJAQAAAA==.',
Ro='Rockhunter:BAAALgAECgYJEgAAAA==.Rokstarr:BAAALgAECgMJAwABLgAFFAUJGQANADMbAA==.Rolis:BAAALgAECgQJCAAAAA==.Ronborules:BAABLgAECn8nAAIiAAgJPRWlGQDSAQAiAAgJPRWlGQDSAQAAAA==.Rosales:BAAALgAECgYJCwAAAA==.Rosenta:BAABLgAECn8iAAIUAAcJWhflIAB0AQAUAAcJWhflIAB0AQAAAA==.Rozencrantz:BAABLgAECn8bAAIeAAkJ1BZiJQAnAgAeAAkJ1BZiJQAnAgAAAA==.Rozzel:BAAALgAECgEJAwAAAA==.',
Ru='Rubber:BAABLgAECn8ZAAMZAAkJxR/1GgA9AgAZAAkJxR/1GgA9AgASAAQJ9Ax71ADiAAAAAA==.Rumlock:BAABLgAECn8aAAMIAAgJZg95awAoAQAIAAYJ+Q15awAoAQAHAAMJ0hTJSACUAAAAAA==.',
Sa='Sabai:BAAALgADCgkJIwABLgAECgcJHgAfAMUYAA==.Sabing:BAAALgAECgQJAQAAAA==.Sadiewolf:BAAALgAECgEJAgAAAA==.Saeberis:BAAALgAECgYJDQAAAA==.Saganck:BAAALgADCgcJBwAAAA==.Saiah:BAAALgADCgcJBwAAAA==.Sal:BAABLgAECn8zAAIRAAkJwSTAAQA9AwARAAkJwSTAAQA9AwAAAA==.Salivan:BAABLgAECn8gAAIeAAYJpiJDRACvAQAeAAYJpiJDRACvAQAAAA==.Sapchat:BAAALgAECgEJAQAAAA==.Sargaris:BAAALgAECgYJDAAAAA==.Sariva:BAABLgAECn8VAAIOAAgJMyCIAQCOAgAOAAgJMyCIAQCOAgAAAA==.Sarss:BAAALgAECgQJCwAAAA==.Sarvajna:BAAALgAECgcJDAAAAA==.Sarzphids:BAAALgAECgEJAQAAAA==.Sasara:BAAALgAECgIJAgAAAA==.Satyricon:BAABLgAECn8cAAIiAAcJdB0MGgDOAQAiAAcJdB0MGgDOAQAAAA==.Saurva:BAAALgADCgUJBQAAAA==.Savvywalnut:BAAALgAECgUJCgAAAA==.Sawfang:BAAALgAECgQJBAABLgAECgkJLgAPAJUkAA==.',
Sc='Screám:BAAALgAECgMJAwAAAA==.',
Se='Sedae:BAAALgAECgYJBgAAAA==.Sedo:BAAALgADCgYJBgAAAA==.Seiya:BAAALgAECgYJEQAAAA==.Selenne:BAAALgADCgQJBAAAAA==.Sendrada:BAAALgAECgQJBAAAAA==.Senji:BAAALgAECgEJAQAAAA==.Sepult:BAAALgAECgIJAwAAAA==.Sevalina:BAAALgAECggJDAAAAA==.Seål:BAABLgAECn8aAAIPAAcJtAjmaAAVAQAPAAcJtAjmaAAVAQAAAA==.',
Sh='Shabadoo:BAAALgADCgYJBgABLgAFFAcJGgARAA0iAA==.Shadowstep:BAAALgAECgYJCgAAAA==.Shambalamps:BAAALgADCgcJCgAAAA==.Shamhuntzu:BAECLgAFFH8YAAMFAAUJmhNEJgAyAQAFAAQJmhNEJgAyAQAWAAEJAABhDQAAAAAuAAQKfywAAgUACQlPHfkSAOgCAAUACQlPHfkSAOgCAAAA.Shampaign:BAABLgAECn8wAAMMAAkJ8RY+EQAVAgAMAAkJ8RY+EQAVAgAJAAYJph4EHwD+AQAAAA==.Shantii:BAAALgAECgUJDgAAAA==.Shaoevoker:BAAALgAECggJCgAAAA==.Sharnara:BAABLgAECn8ZAAIJAAgJ9BVGHgADAgAJAAgJ9BVGHgADAgAAAA==.Shatterskull:BAABLgAECn8XAAIfAAcJrx9XCgBvAgAfAAcJrx9XCgBvAgAAAA==.Shazera:BAAALgADCgcJDQABLgAECgcJNgAZAPMiAA==.Shazira:BAABLgAECn82AAIZAAcJ8yJICgCfAgAZAAcJ8yJICgCfAgAAAA==.Sheffield:BAAALgAECgMJAwAAAA==.Sheman:BAAALgADCgUJBQAAAA==.Shep:BAAALgAECgcJDgAAAA==.Shermuta:BAAALgAECgMJAwAAAA==.Shocknthaw:BAAALgAFFAIJAwABLgAFFAUJDgAjAI8UAA==.Shockolate:BAAALgADCgUJBQAAAA==.Shortyrn:BAAALgAECgYJCQAAAA==.Showgun:BAAALgAECggJCAAAAA==.Shred:BAAALgAECgMJAwAAAA==.Shyvanâ:BAAALgAECgEJAQAAAA==.',
Si='Sidewinder:BAAALgAECgEJAwAAAA==.Silentwounds:BAABLgAECn8qAAMWAAkJbhzxBABiAgAWAAkJbhzxBABiAgAGAAQJJAxYRwDXAAAAAA==.Silvercircle:BAABLgAECn8mAAIIAAYJxBbnWQBSAQAIAAYJxBbnWQBSAQAAAA==.Silverlord:BAABLgAECn8aAAIBAAYJWBgAIwBTAQABAAYJWBgAIwBTAQAAAA==.Sinafay:BAACLgAFFH8IAAIEAAMJ4gHYZwC7AAAEAAMJ4gHYZwC7AAAuAAQKfygAAgQACAmhEkJoAAYCAAQACAmhEkJoAAYCAAAA.Sineu:BAAALgADCgcJCQABLgAECggJGgABAJMjAA==.Sinsong:BAABLgAECn8lAAISAAgJIhX6SQAEAgASAAgJIhX6SQAEAgAAAA==.Siv:BAABLgAECn8aAAIBAAgJkyMJBQA5AwABAAgJkyMJBQA5AwAAAA==.Sivormu:BAAALgADCgcJCQABLgAECggJGgABAJMjAA==.Siwel:BAAALgADCgcJCQAAAA==.',
Sk='Skooks:BAAALgADCgYJBwAAAA==.Skyprincess:BAAALgADCgIJAgAAAA==.',
Sl='Slash:BAAALgAECgQJBgAAAA==.',
Sm='Smallbud:BAAALgADCggJDgAAAA==.',
Sn='Snackpaack:BAAALgAECgcJBwAAAA==.Snapjutsu:BAABLgAFFH8KAAIBAAMJHRwNHgAEAQABAAMJHRwNHgAEAQAAAA==.Snorg:BAABLgAECn8hAAMEAAkJ7A9GQQDWAQAEAAkJ5g9GQQDWAQApAAIJbwiwGABTAAAAAA==.Snêaky:BAABLgAECn8pAAIYAAkJ1SAaBAC8AgAYAAkJ1SAaBAC8AgAAAA==.',
So='Solarnova:BAABLgAECn8OAAIPAAYJNw5SdgD0AAAPAAYJNw5SdgD0AAAAAA==.Soliloquy:BAAALgADCgYJCgAAAA==.Solorn:BAAALgAECgkJOAAAAQ==.Sooze:BAABLgAECn8pAAIBAAkJTR2EBgCcAgABAAkJTR2EBgCcAgAAAA==.Sorsen:BAAALgADCgkJCgAAAA==.',
Sp='Sports:BAAALgAECgYJCQAAAA==.Spygon:BAAALgADCgEJAQAAAA==.',
Sr='Srzbisnis:BAAALgADCgYJBgAAAA==.',
St='Stamina:BAAALgAECgEJAQAAAA==.Starstrike:BAAALgADCgMJAwAAAA==.Stennch:BAAALgADCgYJCQAAAA==.Stianis:BAABLgAECn8WAAIFAAgJzBdbLwC/AQAFAAgJzBdbLwC/AQAAAA==.Stolinaya:BAABLgAECn8qAAIFAAkJmR/FDACjAgAFAAkJmR/FDACjAgAAAA==.Stormbjorn:BAAALgAECgEJAQAAAA==.Stormcleave:BAAALgAECgQJBgABLgAFFAYJGgAMAJgZAA==.Strawberr:BAAALgAECgEJAQAAAA==.Strobila:BAAALgADCgYJBgAAAA==.Studdmuffin:BAAALgAFFAQJBAAAAA==.',
Su='Sudoxe:BAAALgADCgcJBwAAAA==.Supervillain:BAAALgAECgQJBAAAAA==.Suze:BAAALgADCgcJBwABLgAECgkJKQABAE0dAA==.Suzé:BAAALgADCgkJBwABLgAECgkJKQABAE0dAA==.',
Sw='Swamp:BAAALgAECgYJBgABLgAFFAUJGQASAKofAA==.',
Sy='Sylvipal:BAAALgAECgYJCAAAAA==.Sylvèè:BAAALgADCgMJAwAAAA==.Symuelil:BAAALgADCgcJEQAAAA==.Sync:BAAALgADCgYJBgAAAA==.Syrathos:BAACLgAFFH8WAAMFAAgJ/R2dAQBZAgAFAAgJ/R2dAQBZAgAGAAEJ/A/TFwBNAAAuAAQKfyQAAgUACQl9JBwFAHQDAAUACQl9JBwFAHQDAAAA.Syrioforel:BAABLgAECn8YAAMWAAcJBg8ODwAJAQAWAAcJBg8ODwAJAQAGAAEJFg8DSAA5AAAAAA==.',
['Sä']='Särs:BAAALgADCgcJDQAAAA==.',
['Sø']='Søcks:BAAALgAECgQJBwAAAA==.',
Ta='Talah:BAAALgAECgQJBQAAAA==.Talarar:BAAALgADCgQJBAAAAA==.Talfirith:BAAALgADCgYJBgAAAA==.Talla:BAAALgADCgEJAQAAAA==.Tarayn:BAAALgADCgkJEgAAAA==.Tariès:BAAALgAECgcJDQAAAA==.',
Te='Teclis:BAACLgAFFH8QAAIEAAUJfBwXKwBgAQAEAAUJfBwXKwBgAQAuAAQKfyQAAwQACAkNIq4pAMwCAAQACAkNIq4pAMwCACkABQl2FCYMABABAAAA.Teelove:BAAALgAECgYJDwAAAA==.Telzindrov:BAABLgAECn8eAAIaAAkJ6ArzDgCRAQAaAAkJ6ArzDgCRAQAAAA==.Tenden:BAAALgAECgMJAwAAAA==.Terrorwithin:BAAALgAECgkJCwAAAA==.',
Th='Thalgar:BAAALgAECgUJCAAAAA==.Thalmick:BAACLgAFFH8FAAIYAAMJUQ9MGQDxAAAYAAMJUQ9MGQDxAAAuAAQKfzQAAhgACQkpHQIJAEoCABgACQkpHQIJAEoCAAAA.Thanoslykev:BAAALgAECgYJDgAAAA==.Thatonetime:BAAALgADCgYJCQAAAA==.Theblackfish:BAABLgAECn8pAAIPAAkJ3xNJKQDoAQAPAAkJ3xNJKQDoAQAAAA==.Therealchuck:BAAALgADCgkJFQAAAA==.Thimbles:BAAALgADCgcJDQAAAA==.Thogarn:BAAALgADCgcJDgAAAA==.Thorb:BAAALgAFFAIJAgAAAA==.Thozan:BAAALgADCgIJAgAAAA==.Thundertem:BAAALgADCgIJAgAAAA==.Théière:BAABLgAECn8lAAMbAAkJFRl6DgAyAgAbAAkJFRl6DgAyAgAlAAMJ5wSFMwB5AAAAAA==.',
Ti='Tipper:BAAALgADCgEJAQAAAA==.Tiraeda:BAABLgAECn8eAAIFAAYJtwU6kACqAAAFAAYJtwU6kACqAAAAAA==.Titoxs:BAAALgAECgMJBgABLgAECgkJKgAFAJkfAA==.',
To='Tofper:BAAALgAECgIJAgAAAA==.Tonel:BAAALgADCgYJBgAAAA==.Tonelyn:BAAALgAECgQJCAAAAA==.Toomuchrum:BAABLgAECn8mAAMeAAcJsSG3NgDeAQAeAAcJEyG3NgDeAQAoAAQJuR77CwA4AQAAAA==.Torpedo:BAAALgAECgYJDwAAAA==.Totalvision:BAAALgAECgEJAQAAAA==.Totembot:BAACLgAFFH8KAAIMAAQJJQ2kFwAUAQAMAAQJJQ2kFwAUAQAuAAQKfygAAgwACAl3FxUeAJsBAAwACAl3FxUeAJsBAAAA.Toughlove:BAAALgAECgQJBgAAAA==.',
Tr='Traver:BAACLgAFFH8TAAIEAAQJvRoOKQBkAQAEAAQJvRoOKQBkAQAuAAQKfyUAAgQACQm2HLgSALMCAAQACQm2HLgSALMCAAAA.Trev:BAABLgAECn84AAIEAAkJZiB3EADEAgAEAAkJZiB3EADEAgAAAA==.Triboluminal:BAAALgADCgEJAgAAAA==.Tripletka:BAAALgAECgEJAQAAAA==.Trogdorgos:BAAALgAECgcJEwABLgAECggJGwARAMENAA==.Truedemon:BAAALgADCgIJAgAAAA==.Trustfäll:BAABLgAECn8jAAIUAAcJ8BkoEwD3AQAUAAcJ8BkoEwD3AQAAAA==.',
Ts='Tsukifang:BAABLgAECn8hAAMTAAcJvQtNLgANAQATAAcJvQtNLgANAQANAAEJiwGz6wAXAAAAAA==.',
Tu='Tuc:BAABLgAECn8cAAIRAAcJ2QzNKgAnAQARAAcJ2QzNKgAnAQAAAA==.Tulfagen:BAAALgAECgcJDgAAAA==.Turtledots:BAABLgAECn8iAAMHAAkJ9xKNJAA3AQAIAAcJLA66VQBcAQAHAAUJAhiNJAA3AQAAAA==.Tuxie:BAAALgADCgUJBQAAAA==.',
Ty='Tyndareos:BAAALgAECgYJDQAAAA==.Typhoontravv:BAACLgAFFH8JAAIkAAQJbBG6BAD1AAAkAAQJbBG6BAD1AAAuAAQKfywAAxIACQk4H4QqAHoCABIACAmmIoQqAHoCACQACAkNE8URAKwBAAAA.',
['Tø']='Tøkakagé:BAAALgAECgcJEAAAAA==.',
Uf='Ufearme:BAABLgAECn8UAAMIAAYJGgp/hQDxAAAIAAYJCAp/hQDxAAAHAAMJMARLIQBlAAAAAA==.',
Ug='Ugabooga:BAABLgAECn8VAAQpAAgJBh8nCQBaAQAEAAcJ9xhJcwDsAQApAAUJ8BwnCQBaAQAVAAQJXySQBgAyAQAAAA==.Uggon:BAABLgAECn8fAAMPAAYJXBY+WgA5AQAPAAYJXBY+WgA5AQAjAAQJEgOFNgCeAAAAAA==.',
Ul='Ultra:BAAALgAECgUJBQABLgAFFAQJDAAGAJoUAA==.',
Um='Umordruid:BAABLgAECn8hAAIdAAkJ0xj1BgARAgAdAAkJ0xj1BgARAgAAAA==.',
Un='Unable:BAABLgAECn8aAAIiAAgJwhIfHwCnAQAiAAgJwhIfHwCnAQAAAA==.Uncalledfor:BAAALgADCgIJAgABLgAECgkJKwAUAN4VAA==.',
Ut='Uthur:BAABLgAECn8WAAIkAAcJtgxiGwDmAAAkAAcJtgxiGwDmAAAAAA==.Utterchaos:BAACLgAFFH8UAAIIAAUJ1A4oGwAbAQAIAAUJ1A4oGwAbAQAuAAQKfx8ABAgACAk6GStBAAoCAAgACAnxGCtBAAoCAAcABQk3FBckADkBAA4AAQkAACYuAEIAAAAA.',
Va='Vaea:BAAALgAECgEJAgAAAA==.Vaelaven:BAAALgAECggJEgAAAA==.Vaelric:BAAALgADCgQJBAAAAA==.Vaeredor:BAABLgAECn8cAAMdAAgJ/xmWBgAcAgAdAAgJ/xmWBgAcAgAcAAcJKBUKEQBlAQAAAA==.Valack:BAAALgADCgYJBgAAAA==.Valdaroshi:BAAALgAECgEJAQAAAA==.Valizor:BAAALgAECgMJBAAAAA==.Varaylina:BAAALgADCgUJBQAAAA==.Varty:BAAALgAECgEJAQAAAA==.Vasila:BAABLgAECn8eAAQIAAkJbSFMGgBLAgAIAAcJYh5MGgBLAgAOAAYJtR46CAB7AQAHAAMJpCPXFADFAAAAAA==.',
Ve='Velaari:BAAALgADCgMJAwAAAA==.Velasti:BAAALgADCgEJAQAAAA==.Velivan:BAAALgAECgMJBgAAAA==.Venruki:BAAALgAECgEJAQAAAA==.Veraa:BAAALgAECgYJDgAAAA==.Vetta:BAACLgAFFH8TAAIMAAUJVwy3GAANAQAMAAUJVwy3GAANAQAuAAQKfzAAAwwACQlWGVMSAAoCAAwACQlWGVMSAAoCAAkABQnEBpBrAOEAAAAA.',
Vg='Vger:BAAALgAECgYJCAAAAA==.',
Vi='Vineriul:BAAALgADCgYJBgAAAA==.Vinh:BAABLgAECn8pAAMDAAYJ6xegKABZAQADAAYJ6xegKABZAQACAAUJmxg/KwASAQAAAA==.Vinick:BAAALgAECgEJAQAAAA==.',
Vl='Vl:BAAALgAECgIJAgAAAA==.',
Vo='Voideffects:BAAALgAFFAEJAQAAAA==.Voideon:BAAALgAECgEJAQAAAA==.Volathis:BAAALgADCgcJBwAAAA==.Volgagrad:BAAALgADCgYJCAAAAA==.Volgorion:BAAALgAECgIJAgABLgAFFAQJFgAmAG8kAA==.',
Wa='Walden:BAAALgADCgUJBQAAAA==.Walshaman:BAAALgAECgIJAgABLgAFFAcJGgARAA0iAA==.Walshy:BAAALgADCgkJCQABLgAFFAcJGgARAA0iAA==.Wardren:BAAALgADCgcJBwAAAA==.Wardum:BAAALgAECgIJBAAAAA==.Warmspray:BAAALgAECgQJBgAAAA==.Wauchula:BAAALgAECgYJEgABLgAECggJEgAKAAAAAA==.',
We='Websdh:BAAALgAECgcJDwAAAA==.Websup:BAAALgAECgMJAwAAAA==.Welkin:BAABLgAECn8WAAIEAAcJvBj3VgCWAQAEAAcJvBj3VgCWAQAAAA==.',
Wh='Whisp:BAAALgAECgYJDgAAAA==.Whitearrows:BAABLgAECn8eAAQjAAkJ4hSFCwAoAgAjAAkJ3BOFCwAoAgAQAAYJNBHkSAAwAQAPAAUJyQVXlQCqAAAAAA==.Whitelock:BAAALgAECgMJBgABLgAECgkJHgAjAOIUAA==.Whiteowls:BAABLgAECn8iAAINAAgJoSF5CwDlAgANAAgJoSF5CwDlAgABLgAECgkJHgAjAOIUAA==.Whitetotem:BAAALgAECgYJBgABLgAECgkJHgAjAOIUAA==.',
Wi='Wickfel:BAABLgAECn8VAAIOAAcJNwUREQDcAAAOAAcJNwUREQDcAAAAAA==.Willferrell:BAAALgAECgQJCQAAAA==.Winchesters:BAAALgADCgQJBAAAAA==.Windsong:BAAALgADCgEJAQABLgAECggJJQASACIVAA==.Windstone:BAAALgAECgQJBgABLgAECggJJQASACIVAA==.Windwalker:BAAALgAECgIJBgAAAA==.',
Wo='Wolfgrimm:BAAALgAECgYJEAAAAA==.Wolfsbanne:BAAALgAECgEJAQAAAA==.Woodyy:BAAALgADCgYJDwABLgADCgkJFQAKAAAAAA==.Wooferq:BAAALgADCgYJCQAAAA==.',
Wr='Wreckie:BAAALgAFFAIJBAAAAA==.',
Wu='Wupain:BAAALgAECgYJCwAAAA==.',
Wy='Wyld:BAABLgAECn8jAAIWAAcJ5BmSCgBhAQAWAAcJ5BmSCgBhAQAAAA==.',
Xa='Xanbrew:BAAALgAECgUJBgAAAA==.Xanid:BAAALgAECgQJCAAAAA==.',
Xd='Xdwarf:BAAALgAECgcJDAABLgAECgkJPwAXAJEXAA==.',
Xe='Xeroxoxo:BAACLgAFFH8RAAIeAAUJWxvBNABKAQAeAAUJWxvBNABKAQAuAAQKfyUAAh4ACQmuIYIHAGQDAB4ACQmuIYIHAGQDAAAA.Xevric:BAAALgAECgEJAQABLgAECgcJFwABAI0YAA==.',
Ya='Yasman:BAAALgADCgYJBgAAAA==.',
Ye='Yesenia:BAABLgAECn8dAAMiAAYJLSTrFwDiAQAiAAYJLSTrFwDiAQAfAAIJ5gtBNABfAAABLgAECggJFQAOADMgAA==.',
Yh='Yhòrm:BAAALgADCgYJBwAAAA==.',
Ym='Ymedead:BAACLgAFFH8WAAMUAAUJRBoJBgCRAQAUAAUJUBkJBgCRAQAgAAQJHhWpCQBFAQAuAAQKfzAAAyAACQm8H0MHAM8CACAACAkrH0MHAM8CABQACQklGWYPACcCAAEuAAMKAQkBAAoAAAAA.Ymedruid:BAAALgADCgEJAQAAAA==.',
Yo='Yoroichi:BAABLgAECn8/AAIXAAkJkRc9AwA9AgAXAAkJkRc9AwA9AgAAAA==.Yourmomsride:BAABLgAECn8ZAAIEAAcJrgsHhQAyAQAEAAcJrgsHhQAyAQAAAA==.',
Yu='Yudawl:BAAALgAECgMJAwAAAA==.Yueyue:BAAALgAECgYJDQAAAA==.Yuyutsu:BAAALgAECgQJCAABLgAECgYJEgAKAAAAAA==.',
['Yá']='Yáng:BAABLgAECn8iAAIaAAgJySS1AQA6AwAaAAgJySS1AQA6AwAAAA==.',
Za='Zacapan:BAABLgAECn8UAAIDAAcJQB7iFwAAAgADAAcJQB7iFwAAAgABLgAECgkJKgAFAJkfAA==.Zakila:BAAALgADCgMJBAAAAA==.Zamali:BAABLgAECn8uAAIZAAkJDCGQAgBQAwAZAAkJDCGQAgBQAwAAAA==.Zaraxxi:BAAALgAECggJDAAAAA==.Zarean:BAAALgAECgcJBwAAAA==.Zaridi:BAAALgAECgYJEgABLgAECgcJHgAfAMUYAA==.Zarrgos:BAAALgAECgYJBgAAAA==.Zarye:BAAALgAECgQJBQAAAA==.Zayala:BAAALgADCgUJBQABLgAECgkJLwARAI8VAA==.',
Ze='Zeldorie:BAABLgAECn8UAAIIAAgJQgfFcwAWAQAIAAgJQgfFcwAWAQAAAA==.Zempaï:BAAALgAECgMJAwAAAA==.Zeniel:BAAALgADCgcJBwAAAA==.Zerelion:BAAALgAECgEJAQAAAA==.',
Zi='Zindi:BAABLgAECn8eAAIPAAgJiRZpMgDAAQAPAAgJiRZpMgDAAQAAAA==.Ziral:BAAALgADCggJEgAAAA==.',
Zo='Zodd:BAAALgADCgQJBAAAAA==.Zoobee:BAABLgAECn8aAAIMAAgJ/BEHKABWAQAMAAgJ/BEHKABWAQAAAA==.Zoog:BAACLgAFFH8ZAAIZAAUJGhr9CgCfAQAZAAUJGhr9CgCfAQAuAAQKfzAAAhkACQkrGhEVABgCABkACQkrGhEVABgCAAAA.',
Zu='Zugalicious:BAAALgAECgcJCAABLgAFFAQJDAAGAJoUAA==.Zuz:BAAALgAECgIJAgAAAA==.',
Zy='Zykex:BAAALgAECgUJCQAAAA==.Zyphera:BAAALgAECgkJCQAAAA==.Zyvara:BAABLgAECn8cAAMDAAgJfBauFgDxAQADAAgJfBauFgDxAQACAAQJlhJaOADQAAAAAA==.',
['Zä']='Zärèlíä:BAACLgAFFH8LAAICAAQJaREuDQAbAQACAAQJaREuDQAbAQAuAAQKfycAAgIACAnoGfUQAHMCAAIACAnoGfUQAHMCAAAA.',
['Às']='Àstrid:BAABLgAECn8YAAIkAAgJlRZnDAABAgAkAAgJlRZnDAABAgABLgAFFAQJCQABAIQSAA==.',
['Áp']='Ápollia:BAAALgADCgkJEQAAAA==.Ápollo:BAAALgAECgcJEAAAAA==.',
['Æz']='Æz:BAAALgAECgMJAwAAAA==.',
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
