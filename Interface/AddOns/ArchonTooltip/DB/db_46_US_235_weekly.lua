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

local lookup = {'Shaman-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Unknown-Unknown','Druid-Restoration','Evoker-Preservation','Evoker-Devastation','Paladin-Retribution','DeathKnight-Unholy','Priest-Shadow','Druid-Balance','Warlock-Demonology','Mage-Frost','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Priest-Holy','Warrior-Fury','DeathKnight-Blood','Paladin-Holy','Shaman-Elemental','DemonHunter-Devourer','Warlock-Affliction','Shaman-Enhancement','DemonHunter-Havoc','DeathKnight-Frost','Monk-Mistweaver','DemonHunter-Vengeance','Warlock-Destruction','Warrior-Arms','Priest-Discipline','Mage-Fire','Warrior-Protection','Hunter-Survival','Rogue-Subtlety','Monk-Brewmaster','Rogue-Assassination','Monk-Windwalker','Rogue-Outlaw','Paladin-Protection','Mage-Arcane',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=46,date='2026-06-14',data={Ad='Addisyn:BAAALgAECgEJBAAAAA==.',
Ae='Aekal:BAAALgAECgUJBQAAAA==.Aemetris:BAABLgAECn8ZAAIBAAcJMxdUNADeAQABAAcJMxdUNADeAQAAAA==.Aenicus:BAAALgADCgcJBwAAAA==.Aerina:BAAALgAECgQJCwAAAA==.Aethra:BAAALgADCgYJBgAAAA==.',
Ag='Agamotto:BAAALgAECgYJCgAAAA==.Agromagnetic:BAAALgAECgcJDQAAAA==.Agytha:BAAALgAECgMJAwAAAA==.Agøny:BAAALgADCgMJAwAAAA==.',
Ah='Ahskul:BAAALgADCgEJAQAAAA==.',
Ai='Aidendawn:BAAALgAECgYJDwAAAA==.',
Aj='Ajheria:BAAALgAECgEJAQAAAA==.',
Am='Ameildoran:BAAALgADCgkJCQAAAA==.',
An='Anaru:BAAALgAECgMJBgAAAA==.Anatyriel:BAAALgADCgEJAQAAAA==.Anayanci:BAAALgADCgUJBgAAAA==.Andalaine:BAAALgAECgMJBQAAAA==.Andari:BAAALgADCgEJAQAAAA==.Andramaedra:BAAALgAECgkJAgAAAA==.Anoobornot:BAAALgADCgMJAwAAAA==.Anraleth:BAACLgAFFH8RAAICAAQJ9iO/CwCkAQACAAQJ9iO/CwCkAQAuAAQKfzwAAwIACQkLJfwCAK0CAAIACAnnJPwCAK0CAAMAAQkGJtX2AGUAAAAA.',
Ap='Aponi:BAAALgAECgUJCAAAAA==.',
Ar='Arckillion:BAAALgAECgMJAwAAAA==.Ardour:BAAALgAECgMJBgABLgAECgcJEwAEAAAAAA==.Arduous:BAAALgAECgMJAwAAAA==.Arihu:BAABLgAECn8fAAIFAAkJlxSzLgDoAQAFAAkJlxSzLgDoAQAAAA==.Arkhana:BAAALgADCgEJAQAAAA==.',
As='Ashenaya:BAABLgAECn8YAAMGAAgJLxk9DAAQAgAGAAgJLxk9DAAQAgAHAAEJMQpQQgArAAAAAA==.Asparagus:BAABLgAECn8aAAIIAAkJVw6cYQCsAQAIAAkJVw6cYQCsAQAAAA==.',
At='Atlass:BAACLgAFFH8GAAIJAAIJLhVAzgCOAAAJAAIJLhVAzgCOAAAuAAQKfxgAAgkABwnxGYtjAMkBAAkABwnxGYtjAMkBAAAA.Atrest:BAAALgAECgYJBwAAAA==.',
Au='Augmenter:BAAALgAECgQJBQABLgAFFAcJHgAKAGAaAA==.Aust:BAABLgAECn8UAAIIAAgJ6hP6agCXAQAIAAgJ6hP6agCXAQAAAA==.',
Av='Averlin:BAAALgAECgMJAwAAAA==.Averlis:BAABLgAECn8gAAILAAgJ+BUDHwDNAQALAAgJ+BUDHwDNAQAAAA==.Avoiddance:BAAALgADCgEJAQAAAA==.',
Ax='Axee:BAAALgADCgYJBgAAAA==.',
Az='Azima:BAAALgAECgMJAwAAAA==.Azura:BAAALgADCgIJAgAAAA==.Azurargentyr:BAAALgAECgkJEAAAAA==.',
Ba='Babeolicious:BAAALgADCgEJAQAAAA==.Bacon:BAABLgAECn8lAAIIAAkJzArtgwBmAQAIAAkJzArtgwBmAQAAAA==.Bambøøze:BAAALgADCgEJAQAAAA==.Bandadi:BAECLgAFFH8IAAIMAAYJwhVJKQCZAQAMAAYJwhVJKQCZAQAuAAQKfzEAAgwACAkzIG0VANUCAAwACAkzIG0VANUCAAAA.Barbelo:BAAALgAECgcJCgAAAA==.Barely:BAAALgAECggJDwAAAA==.Barkweldort:BAAALgAECgYJEQAAAA==.Barreled:BAAALgADCgMJAwAAAA==.Batistabomba:BAAALgAECgYJBgAAAA==.',
Be='Beargruk:BAAALgAECgUJBwAAAA==.Beastly:BAAALgAECggJEQAAAA==.Beeble:BAABLgAECn8WAAINAAYJvwm5zgDxAAANAAYJvwm5zgDxAAAAAA==.Belii:BAAALgAECgYJDAAAAA==.Bended:BAAALgADCgIJAgAAAA==.Bepisthepall:BAAALgAECgEJAgAAAA==.Betterkevin:BAAALgAECgQJDwAAAA==.Bezerkachew:BAAALgAECgEJAgAAAA==.',
Bi='Bigbootijudi:BAAALgAECgEJAQAAAA==.Bigbooty:BAABLgAECn8fAAMOAAgJPAf1OwCyAAAOAAgJyAX1OwCyAAAPAAUJIAe5NgB8AAAAAA==.',
Bl='Blikey:BAABLgAFFH8GAAIJAAIJfiYPuQCvAAAJAAIJfiYPuQCvAAAAAA==.Bloodyrott:BAAALgAECgUJCgAAAA==.Bluedrake:BAACLgAFFH8NAAMHAAQJ1BsvAwBFAQAHAAQJ1BsvAwBFAQAQAAEJPRN9YgBAAAAuAAQKfyMAAwcACAlfHr4EALoCAAcACAmGHb4EALoCABAACAk9FlIZAAMCAAEuAAUUBQkTAAsAwyIA.Blueparrot:BAABLgAECn8yAAIRAAgJpBSKGwDoAQARAAgJpBSKGwDoAQAAAA==.Bluy:BAAALgADCgMJAwAAAA==.Blädèstorm:BAABLgAECn8ZAAISAAgJphyHIwDXAQASAAgJphyHIwDXAQAAAA==.',
Bo='Bonesnap:BAACLgAFFH8VAAMJAAcJeR5kGgAGAgAJAAYJeR5kGgAGAgATAAEJAAAPUwAAAAAuAAQKfyAAAwkACQmrIaMXAO4CAAkACQmrIaMXAO4CABMABAmuE8s9AJcAAAAA.Bowkatan:BAAALgAECgEJAgAAAA==.',
Br='Brianisita:BAAALgAECgUJBgAAAA==.Brightmane:BAABLgAECn8WAAIUAAYJUx4zJQD8AQAUAAYJUx4zJQD8AQAAAA==.Bringinlight:BAAALgAECgYJEgAAAA==.',
Bu='Bubbleicious:BAAALgAECgYJEgAAAA==.Bubbletea:BAABLgAECn8YAAIIAAgJLhZSSADsAQAIAAgJLhZSSADsAQABLgAECgkJLAADAMkjAA==.Bulletz:BAABLgAECn8eAAICAAgJ7x3xBABcAgACAAgJ7x3xBABcAgAAAA==.Bumpersnouts:BAAALgADCgcJBwAAAA==.Buttfur:BAAALgADCgYJBgAAAA==.',
['Bê']='Bêarwithme:BAAALgAECgIJBgABLgAECgcJGwAKAF8RAA==.',
Ca='Caenzo:BAAALgADCgkJCgAAAA==.Casanna:BAAALgADCgYJBgAAAA==.Cassandria:BAABLgAECn8sAAMFAAgJBxBvVAA8AQAFAAcJqw5vVAA8AQALAAgJ2AxaOgAmAQAAAA==.Cassiradra:BAAALgADCgEJAQAAAA==.Caylastus:BAAALgAECgEJAgAAAA==.',
Ce='Cearas:BAAALgAECgEJAQAAAA==.Cedrick:BAAALgAECgUJBQAAAA==.Celiona:BAAALgAECgkJBwAAAA==.Celody:BAAALgAECgYJDAAAAA==.Celticsinsix:BAAALgAECgMJBQAAAA==.Cervixticklr:BAAALgAECgQJBQAAAA==.',
Ch='Chaoten:BAAALgADCgEJAQAAAA==.Chathlia:BAAALgAECgQJBAAAAA==.Chavdar:BAAALgADCgEJAQAAAA==.Chewster:BAABLgAECn81AAINAAgJJhBMdQCMAQANAAgJJhBMdQCMAQAAAA==.Chixie:BAAALgADCgEJAQAAAA==.Choal:BAABLgAECn8VAAIFAAYJuQ0OYQAQAQAFAAYJuQ0OYQAQAQAAAA==.Choglana:BAAALgAECgcJCQAAAA==.Chogli:BAAALgAECgEJAQABLgAECgcJCQAEAAAAAA==.Chogric:BAABLgAECn85AAMUAAkJhh+NBQATAwAUAAkJhh+NBQATAwAIAAQJZw0gIwGMAAABLgAECgcJCQAEAAAAAA==.',
Ci='Civetta:BAABLgAECn8WAAIDAAkJhwzRUACtAQADAAkJhwzRUACtAQAAAA==.',
Cl='Clannininick:BAAALgADCgUJBgAAAA==.Clark:BAAALgADCgEJAQAAAA==.',
Co='Cogswell:BAAALgADCgIJAgAAAA==.Comespankit:BAAALgAECgUJBQAAAA==.Constiua:BAAALgAECgcJDwABLgAECgcJCQAEAAAAAA==.Convalesor:BAABLgAECn8UAAIKAAYJQQiNTgDUAAAKAAYJQQiNTgDUAAAAAA==.',
Cr='Crazzywazzy:BAABLgAFFH8KAAIJAAQJcBjcaQAjAQAJAAQJcBjcaQAjAQAAAA==.Crona:BAABLgAECn8aAAIUAAkJtg4LPACJAQAUAAkJtg4LPACJAQAAAA==.Crsteel:BAAALgAECgEJAQAAAA==.Crzyblnkrton:BAACLgAFFH8PAAINAAYJthAlQwBmAQANAAYJthAlQwBmAQAuAAQKfxcAAg0ACAnmH2k5AJACAA0ACAnmH2k5AJACAAAA.Crzzy:BAABLgAFFH8IAAIVAAcJKA7dEgCCAQAVAAcJKA7dEgCCAQAAAA==.',
Cu='Cuddlez:BAABLgAECn8gAAIRAAkJGQvbLABiAQARAAkJGQvbLABiAQAAAA==.Cultera:BAACLgAFFH8PAAIWAAQJuxK6RgAPAQAWAAQJuxK6RgAPAQAuAAQKfxkAAhYACAlUHPQ1AOwBABYACAlUHPQ1AOwBAAAA.',
Cy='Cyhyraethia:BAABLgAECn8fAAIXAAgJDB+sBQANAgAXAAgJDB+sBQANAgABLgAECgkJOAAWAEEaAA==.Cyndera:BAAALgADCgEJAQAAAA==.',
Da='Dagden:BAAALgADCgYJCAAAAA==.Dalaa:BAAALgAECgIJAgAAAA==.Dammnation:BAAALgAECgYJBwABLgAECgcJGwAKAF8RAA==.Danda:BAAALgAECgYJCgAAAA==.Daricepicker:BAABLgAECn8sAAIDAAkJySNPBQA3AwADAAkJySNPBQA3AwAAAA==.Darkyn:BAABLgAECn8ZAAIMAAkJPRBoRgDHAQAMAAkJPRBoRgDHAQAAAA==.Davedadude:BAABLgAECn8wAAIIAAkJEyL0CwAEAwAIAAkJEyL0CwAEAwAAAA==.',
Dd='Ddeonu:BAAALgAECgEJAQAAAA==.Ddeonuu:BAABLgAFFH8LAAMCAAUJPA7DFwD6AAADAAUJsgubSAAWAQACAAQJ2gzDFwD6AAAAAA==.',
De='Deadlysins:BAABLgAECn8WAAIJAAgJ8wvpbACwAQAJAAgJ8wvpbACwAQAAAA==.Deadscar:BAECLgAFFH8OAAIYAAQJ+SNPAwCeAQAYAAQJ+SNPAwCeAQAuAAQKfzQAAhgACQlSJqcAAF0DABgACQlSJqcAAF0DAAAA.Deathmasterj:BAAALgADCggJDgAAAA==.Deaths:BAABLgAECn8eAAMZAAgJTRLnGwCaAQAZAAgJTRLnGwCaAQAWAAEJJQSDNAEdAAAAAA==.Dedfrosty:BAABLgAECn8lAAMTAAgJNxHsHwBSAQATAAgJfA7sHwBSAQAaAAgJIg1/GAAOAQAAAA==.Demomcgee:BAAALgADCgEJAgABLgAECgYJDwAEAAAAAA==.Demonio:BAAALgADCgQJBgAAAA==.Demonpimp:BAAALgAECgYJEAAAAA==.Dermon:BAAALgAECggJCwABLgAFFAQJBwAbAIIhAA==.Deviously:BAAALgADCgQJBAABLgAECgkJHgACAO8dAA==.Dewyhuey:BAAALgADCgIJAgAAAA==.',
Dh='Dhoong:BAAALgAECgIJAgAAAA==.',
Di='Dimpiana:BAAALgAECgQJBAAAAA==.Disciplea:BAAALgAECgQJBAAAAA==.Dithariaa:BAABLgAECn8jAAIcAAcJHg66EgAiAQAcAAcJHg66EgAiAQAAAA==.',
Do='Docryktor:BAABLgAECn87AAIYAAgJ3xrcCQAaAgAYAAgJ3xrcCQAaAgAAAA==.Doomgears:BAABLgAECn8cAAIdAAYJ1havDgBQAQAdAAYJ1havDgBQAQAAAA==.Dotsdead:BAAALgADCgYJDgAAAA==.Dotöri:BAAALgAECggJDwAAAA==.',
Dr='Draculä:BAAALgAECgQJBAAAAA==.Dragonair:BAABLgAECn8bAAMGAAcJ8QPOIwDNAAAGAAcJ8QPOIwDNAAAHAAcJ7AKTFwCcAAAAAA==.Drashta:BAAALgAECgEJAQAAAA==.Drhoe:BAAALgAECgEJAQAAAA==.Drhurtouch:BAABLgAECn8iAAIeAAkJCx1zBQCxAgAeAAkJCx1zBQCxAgAAAA==.Dro:BAAALgAECgQJCgAAAA==.Drogas:BAAALgAECgIJBAAAAA==.Drtybear:BAABLgAECn8jAAMOAAkJ3BT+IgA0AQAOAAcJbhL+IgA0AQAPAAUJ5hP1IAD8AAAAAA==.Drulissa:BAACLgAFFH8NAAIUAAQJOCNTFACCAQAUAAQJOCNTFACCAQAuAAQKfxkAAhQACQl1GZktAM0BABQACQl1GZktAM0BAAAA.Druu:BAAALgADCgMJAwABLgAFFAYJFQANAGsYAA==.',
Du='Duh:BAAALgAECgEJAQAAAA==.Duogear:BAAALgADCgEJAQAAAA==.Dusters:BAAALgADCgcJCwAAAA==.',
Eb='Ebonwings:BAAALgAECgcJDQAAAA==.',
Ed='Ediana:BAACLgAFFH8FAAINAAMJxAIQkgCwAAANAAMJxAIQkgCwAAAuAAQKfycAAg0ACQnqCfB2AIkBAA0ACQnqCfB2AIkBAAAA.',
El='Eld:BAAALgAECgEJAQAAAA==.Elmô:BAABLgAECn83AAIUAAgJHiGZCgDhAgAUAAgJHiGZCgDhAgAAAA==.Elody:BAAALgADCgYJBgAAAA==.Elvara:BAAALgAECgUJDQAAAA==.',
Eq='Equipwooman:BAAALgADCgIJAgAAAA==.',
Es='Estameling:BAABLgAECn8qAAIOAAgJyhYGGACMAQAOAAgJyhYGGACMAQAAAA==.',
Ex='Exash:BAACLgAFFH8NAAIVAAQJwRrHGwA3AQAVAAQJwRrHGwA3AQAuAAQKfycAAhUACQk7ITUJAP8CABUACQk7ITUJAP8CAAAA.Excizion:BAACLgAFFH8FAAIJAAIJpQNX7QB5AAAJAAIJpQNX7QB5AAAuAAQKfyUAAgkACQnzC1VfAKkBAAkACQnzC1VfAKkBAAAA.',
Fa='Faelynne:BAAALgADCgUJBQAAAA==.Fari:BAAALgAECgcJDAAAAA==.Fathertim:BAABLgAECn8jAAIfAAcJEhlxGAAOAgAfAAcJEhlxGAAOAgAAAA==.',
Fe='Feannara:BAAALgAECgYJCQAAAA==.Felar:BAAALgADCgEJAQAAAA==.Feldrena:BAAALgADCgcJDAAAAA==.',
Fl='Flangus:BAAALgADCgMJBAAAAA==.Flappydragon:BAAALgADCgIJAgAAAA==.Floraria:BAAALgADCgYJBgAAAA==.',
Fr='Frostii:BAABLgAECn8ZAAINAAgJxRluZgCuAQANAAgJxRluZgCuAQAAAA==.',
Fu='Fudestamp:BAAALgADCgQJBQAAAA==.Fufight:BAAALgAECgIJBQABLgAFFAQJBwAbAIIhAA==.Fugryktor:BAABLgAECn8sAAIXAAcJsBXxCwCbAQAXAAcJsBXxCwCbAQAAAA==.',
Fy='Fyrebug:BAABLgAECn8bAAIBAAYJ2QxZbAATAQABAAYJ2QxZbAATAQAAAA==.',
Ga='Galandor:BAABLgAECn8cAAIUAAcJYBvhGgAsAgAUAAcJYBvhGgAsAgAAAA==.Gandaalf:BAABLgAECn8WAAMgAAcJCR7XAQBrAgAgAAcJCR7XAQBrAgANAAIJ4Q9RRgFzAAAAAA==.Garrinda:BAAALgAECgkJDgAAAA==.Gaya:BAAALgAECgYJBgAAAA==.',
Ge='Geeked:BAAALgADCgUJBQAAAA==.Gemhide:BAABLgAECn8jAAIdAAkJzxJvCADDAQAdAAkJzxJvCADDAQAAAA==.Georgharison:BAAALgAECgEJAQAAAA==.Geroy:BAAALgAECgEJAQAAAA==.',
Gg='Ggwp:BAAALgAECgEJAQAAAA==.',
Gh='Ghae:BAAALgAECgUJBAAAAA==.Ghostsaber:BAAALgADCgEJAQABLgAECggJGQAhAM8cAA==.',
Gi='Gigglyguff:BAABLgAECn8YAAIFAAgJRiDwEQC9AgAFAAgJRiDwEQC9AgAAAA==.Gimly:BAAALgAECgEJAQAAAA==.Gityadruid:BAAALgAECgEJAQABLgAECgYJEgAEAAAAAA==.Gityahunter:BAAALgAECgQJBQABLgAECgYJEgAEAAAAAA==.',
Gl='Glavenus:BAAALgADCgEJAQAAAA==.',
Go='Gobank:BAAALgADCgIJAgAAAA==.Gobanks:BAABLgAECn87AAIIAAkJXCAwEwDOAgAIAAkJXCAwEwDOAgAAAA==.',
Gr='Graycat:BAAALgADCgIJAgABLgAFFAgJGgAiAMsjAA==.Grayele:BAAALgAECgIJAgAAAA==.Grayson:BAABLgAECn8aAAIIAAcJMwXg8ADHAAAIAAcJMwXg8ADHAAAAAA==.Graysurv:BAACLgAFFH8aAAIiAAgJyyMEAACBAgAiAAgJyyMEAACBAgAuAAQKfykAAiIACQn6JgUAABQEACIACQn6JgUAABQEAAAA.Gregmiller:BAAALgADCgYJBgAAAA==.Grizzly:BAAALgADCgUJBQAAAA==.Gromlin:BAAALgAECgUJCgAAAA==.Grothfen:BAAALgAECgEJAQAAAA==.',
['Gä']='Gäreth:BAAALgADCgYJCwAAAA==.',
Ha='Habachi:BAAALgADCgEJAQAAAA==.Halcrenian:BAAALgAECgIJAgAAAA==.Hamelot:BAAALgADCgMJBAAAAA==.Hamremmi:BAAALgAECgEJAQABLgAFFAcJHgAKAGAaAA==.Handrider:BAAALgAECgEJAQAAAA==.Haruharu:BAAALgAECgUJCQABLgAECgkJJQAFANkfAA==.Hasalia:BAAALgAECggJCAABLgAFFAQJDQAUADgjAA==.',
He='Healsforu:BAAALgAECgUJDQABLgAECgYJDQAEAAAAAA==.Helly:BAAALgAECgEJAQAAAA==.Hemidall:BAAALgADCgMJAwAAAA==.Herbievore:BAABLgAECn8UAAMOAAgJORifJAApAQAOAAUJ8RqfJAApAQALAAYJAhHWUwC8AAAAAA==.Heunno:BAAALgADCgYJBgABLgAECgYJBgAEAAAAAA==.',
Hi='Hiemy:BAAALgAECgYJBgAAAA==.Hif:BAACLgAFFH8HAAIFAAQJAh0CIABSAQAFAAQJAh0CIABSAQAuAAQKfyMAAgUACQn2I7QFADEDAAUACQn2I7QFADEDAAAA.Highbrittz:BAAALgAECgYJDgAAAA==.',
Hm='Hmmisee:BAAALgAECgEJAQAAAA==.',
Ho='Hoakaren:BAABLgAECn8ZAAIWAAkJAxb/LwAEAgAWAAkJAxb/LwAEAgAAAA==.Hobiscuits:BAEALgADCgQJBAABLgAECgYJHwAMAGwiAA==.Hocus:BAAALgADCgYJBgAAAA==.Holde:BAAALgAECgUJDQAAAA==.Hornyrott:BAAALgAECgQJBQAAAA==.',
Hu='Hunterzamb:BAAALgAECgEJAQAAAA==.Huntinator:BAABLgAECn8VAAIDAAcJHhtwMADvAQADAAcJHhtwMADvAQAAAA==.',
Hy='Hydrobubble:BAAALgAECgYJBwAAAA==.',
['Há']='Hátfield:BAAALgADCgEJAQAAAA==.',
Ih='Ihyo:BAAALgAECgEJAQABLgAECgcJBwAEAAAAAA==.',
Il='Illyy:BAABLgAECn8mAAIRAAgJMgs/NgAkAQARAAgJMgs/NgAkAQAAAA==.',
In='Indawhole:BAACLgAFFH8eAAIWAAgJABjyFQD4AQAWAAgJABjyFQD4AQAuAAQKfxoAAhYACAl8JYojAEACABYACAl8JYojAEACAAAA.',
Ir='Iridori:BAABLgAECn8wAAIRAAgJuCBWCwCvAgARAAgJuCBWCwCvAgAAAA==.Irönfist:BAAALgADCgkJEgAAAA==.',
It='Itzzender:BAAALgADCgIJAgAAAA==.',
Iz='Izumiwitabow:BAABLgAECn8aAAIDAAcJpxLRZQB1AQADAAcJpxLRZQB1AQAAAA==.',
Ja='Jabberthehut:BAAALgAFFAEJAQAAAA==.Jamerius:BAAALgAECgIJAgAAAA==.Jankovic:BAAALgADCgcJBwAAAA==.Jasmean:BAAALgADCgcJCAAAAA==.Javaluminous:BAABLgAECn8oAAIIAAgJQCDBKwBRAgAIAAgJQCDBKwBRAgAAAA==.Jay:BAABLgAFFH8GAAIQAAMJjxBtQgC3AAAQAAMJjxBtQgC3AAABLgAFFAYJFAAjADgXAA==.Jaytsukitori:BAACLgAFFH8ZAAMFAAUJ+SSYDQAUAgAFAAUJ+SSYDQAUAgALAAEJgwiHTQA4AAAuAAQKfx0AAwUACAmKIbkMANcCAAUACAmKIbkMANcCAAsAAQlmEJSLADMAAAAA.',
Jh='Jhaeriao:BAAALgAECgYJDAAAAA==.Jhantherox:BAAALgAECgYJBgAAAA==.',
Jo='Joesepi:BAABLgAFFH8aAAIJAAYJ6xoGJwDDAQAJAAYJ6xoGJwDDAQAAAA==.Joham:BAAALgAECgEJAQAAAA==.Jojosus:BAAALgADCgcJBwABLgADCgkJLAAEAAAAAA==.Jonah:BAAALgAFFAEJAQABLgAFFAIJBQAJAB4YAA==.',
Ju='Judgeroybean:BAAALgAECgMJAwAAAA==.Juliofoolioo:BAAALgAECgEJAgAAAA==.',
Ka='Karti:BAAALgADCgQJBAAAAA==.Kayahli:BAAALgAECgQJBAAAAA==.Kazghul:BAAALgADCgEJAQAAAA==.',
Ke='Kelaeus:BAABLgAECn8VAAINAAYJUQ5x0ABMAQANAAYJUQ5x0ABMAQAAAA==.Keyonslayz:BAAALgADCggJCAAAAA==.',
Kh='Khrønos:BAAALgAECggJCwAAAA==.',
Ki='Killzom:BAAALgADCgEJAQABLgAFFAQJCgAOACkVAA==.Kilrah:BAABLgAECn82AAIZAAkJahalEgABAgAZAAkJahalEgABAgAAAA==.Kirian:BAAALgADCgEJAQAAAA==.Kissmyash:BAABLgAECn8WAAINAAYJ9AnO0QDtAAANAAYJ9AnO0QDtAAAAAA==.Kissmycrits:BAABLgAECn8ZAAIDAAQJsB2kgQA4AQADAAQJsB2kgQA4AQAAAA==.Kissmywrath:BAAALgAECgEJAQAAAA==.Kiyana:BAABLgAECn8vAAIZAAcJIA96LAAZAQAZAAcJIA96LAAZAQAAAA==.Kiyoine:BAABLgAECn8iAAIPAAgJKRnoCwD3AQAPAAgJKRnoCwD3AQAAAA==.',
Kn='Knocksteady:BAACLgAFFH8TAAIIAAYJLRoCJAByAQAIAAYJLRoCJAByAQAuAAQKfyAAAggABwm2IYskAJUCAAgABwm2IYskAJUCAAAA.Knoxform:BAAALgAECgMJBAAAAA==.Knoxhops:BAAALgAECgMJAwABLgAECgMJBAAEAAAAAA==.Knoxreaps:BAAALgAECgYJBAABLgAECgMJBAAEAAAAAA==.Knoxstaggers:BAABLgAECn8lAAIkAAgJ3iAkEwAXAgAkAAgJ3iAkEwAXAgABLgAECgMJBAAEAAAAAA==.',
Ko='Korozzma:BAAALgADCgYJBgABLgADCgEJAQAEAAAAAA==.',
Kr='Krzzy:BAAALgAFFAEJAQABLgAFFAcJCAAVACgOAA==.',
Ku='Kuray:BAAALgAECgEJAgAAAA==.',
Ky='Kynbrookera:BAABLgAECn8eAAIFAAkJFQxORQB5AQAFAAkJFQxORQB5AQAAAA==.Kyujin:BAAALgADCgEJAQAAAA==.',
['Kì']='Kìnky:BAAALgAECgcJEwAAAA==.',
La='Laetha:BAAALgADCgUJBQAAAA==.',
Le='Lemicall:BAAALgADCgQJCAAAAA==.Lethiferous:BAAALgAECgIJAgAAAA==.Letmespankit:BAAALgADCgYJDAAAAA==.Lezigo:BAABLgAECn8jAAINAAkJaBRkSgD6AQANAAkJaBRkSgD6AQAAAA==.',
Li='Licht:BAAALgAECgYJCwAAAA==.Lik:BAAALgAECgQJBwAAAA==.Lilhorror:BAAALgADCgMJAwAAAA==.Lilpyro:BAAALgAECgQJBAAAAA==.Lilyheart:BAAALgADCgYJBgAAAA==.Linai:BAABLgAECn8kAAMjAAkJuQ6UFgDmAQAjAAkJuQ6UFgDmAQAlAAgJEQgEDwAyAQAAAA==.Lit:BAAALgAECgEJAwAAAA==.Littledog:BAACLgAFFH8KAAIKAAQJbRRYGAAgAQAKAAQJbRRYGAAgAQAuAAQKfy4AAwoACQnXFZMbAOgBAAoACQnXFZMbAOgBAB8ABAlyFq09AL8AAAAA.',
Lo='Lockdout:BAAALgADCgEJAQABLgAECggJGQANANkWAA==.Loky:BAACLgAFFH8HAAIMAAIJWhsSjQCmAAAMAAIJWhsSjQCmAAAuAAQKfyUABAwACQkCH1A8AOoBAAwACQncHlA8AOoBAB0ABAl+GMskADUBABcAAQl6IVMvAF4AAAAA.Longshanks:BAAALgADCgUJDAAAAA==.Longshenks:BAAALgADCgUJBQAAAA==.Lorna:BAAALgADCgEJAQAAAA==.Lotten:BAAALgAECgUJDAAAAA==.',
Lu='Luckevin:BAAALgAECgYJDgAAAA==.Lumianir:BAAALgAECgEJAQAAAA==.Lunitari:BAAALgAECgYJEgAAAA==.Luthiean:BAAALgADCgQJBAAAAA==.Luthran:BAAALgAECgUJCwABLgAECggJGAAPAD8PAA==.',
Ly='Lynnali:BAAALgADCggJEQAAAA==.Lyrrin:BAAALgADCgYJBgAAAA==.',
Ma='Magedon:BAAALgAECgEJAQAAAA==.Mageyoulaugh:BAABLgAECn8ZAAINAAgJ2RZoXwC/AQANAAgJ2RZoXwC/AQAAAA==.Magezamb:BAAALgAECgUJDQAAAA==.Magicmann:BAAALgAECgEJAQAAAA==.Magmash:BAAALgADCggJDwAAAA==.Mahito:BAAALgADCgEJAQAAAA==.Mahru:BAAALgADCgYJCAAAAA==.Majhduul:BAAALgADCgMJAwAAAA==.Malafang:BAABLgAECn8VAAIIAAYJygQ5AQG0AAAIAAYJygQ5AQG0AAAAAA==.Malanah:BAABLgAECn8XAAIKAAcJ4w1zOQAsAQAKAAcJ4w1zOQAsAQAAAA==.Marandra:BAAALgAECgQJBwAAAA==.Marlie:BAAALgAECgMJAwAAAA==.Mathalios:BAAALgAECgIJAgAAAA==.Mattu:BAABLgAECn8WAAIgAAYJMgPSDQCDAAAgAAYJMgPSDQCDAAAAAA==.Maverick:BAACLgAFFH8UAAIjAAYJOBenCABiAQAjAAYJOBenCABiAQAuAAQKfxsAAyMABwlUIsIVAGECACMABwlNIsIVAGECACUABAmBIpcMAFgBAAAA.Maxbaba:BAAALgAECgEJAQAAAA==.',
Mc='Mcskittelz:BAAALgADCgQJBAAAAA==.',
Me='Meleshanorak:BAAALgADCgUJCgAAAA==.',
Mi='Michaella:BAAALgAECgUJCwAAAA==.Michartson:BAAALgADCgYJBAAAAA==.Mingres:BAABLgAECn8XAAIDAAcJQw/QeABLAQADAAcJQw/QeABLAQAAAA==.Miramanie:BAAALgADCgYJBgAAAA==.Misdiagnosed:BAAALgADCgIJAgAAAA==.Mistbrewer:BAAALgADCgIJAgAAAA==.',
Mk='Mk:BAEALgAECgYJEQABLgAECgkJQQAmAIAgAA==.',
Mo='Mogar:BAABLgAECn8cAAIeAAcJLx8QDAAkAgAeAAcJLx8QDAAkAgAAAA==.Mogina:BAAALgADCggJCAAAAA==.Monkish:BAAALgADCgMJAwAAAA==.Monster:BAAALgAECgUJBQAAAA==.Moonzhine:BAABLgAECn8jAAITAAkJXhVDFQDBAQATAAkJXhVDFQDBAQAAAA==.Moosejaw:BAAALgAECgYJCwAAAA==.Mordread:BAAALgAECggJEgAAAA==.Morgalruk:BAAALgAFFAQJBAAAAA==.',
My='Myriosheal:BAAALgADCgQJBAAAAA==.Mythx:BAACLgAFFH8iAAQDAAgJTRsDAgCBAQADAAYJJh0DAgCBAQAiAAQJCQzSFgAYAQACAAIJRRRoKgBZAAAuAAQKfysABAMACAlXI3wIAAoDAAMACAlXI3wIAAoDACIABgn7GNgrAEUBAAIABQkFEe5MAB0BAAAA.',
Na='Nalanelin:BAABLgAECn8WAAIJAAcJKQ3hlgA5AQAJAAcJKQ3hlgA5AQAAAA==.Narukin:BAABLgAECn8cAAIWAAcJVBpNRwCuAQAWAAcJVBpNRwCuAQAAAA==.Naturboy:BAAALgADCgYJBgAAAA==.',
Ne='Nemmessiss:BAAALgAECgEJAgAAAA==.Nessirebette:BAAALgADCgUJCAAAAA==.Netherwalker:BAAALgAECgIJAgABLgAFFAcJHgAKAGAaAA==.Netherward:BAAALgADCgEJAQABLgAFFAcJHgAKAGAaAA==.',
Ni='Nivmizzet:BAABLgAECn8wAAMMAAgJ+BkHTwCuAQAMAAcJfBoHTwCuAQAdAAYJ8BUqLQAJAQAAAA==.',
No='Nolakai:BAAALgAECgEJAQAAAA==.Nomiro:BAAALgAECgYJDAAAAA==.Noradori:BAAALgAECgEJAQAAAA==.Notdip:BAAALgADCgIJAgAAAA==.Novalea:BAACLgAFFH8NAAIBAAQJ1yXlFQCuAQABAAQJ1yXlFQCuAQAuAAQKf00AAwEACQlhI+UEAGQDAAEACQlhI+UEAGQDABUABwkeHr0tAIkBAAAA.',
Nu='Nuru:BAAALgAECgcJEAAAAA==.Nutcutter:BAAALgAECgQJBAAAAA==.',
['Nø']='Nøstalgic:BAAALgAECgEJAgAAAA==.',
Ob='Obala:BAAALgADCgIJAgAAAA==.',
Od='Odogaren:BAABLgAECn8ZAAMhAAgJzxxbCwBYAgAhAAcJgB1bCwBYAgASAAgJhRoVIQBLAgAAAA==.',
Om='Omnithorn:BAAALgAECggJDQAAAA==.',
On='Onei:BAAALgADCgEJAQAAAA==.',
Or='Oramos:BAAALgAECgQJBgAAAA==.Orgóndó:BAABLgAFFH8NAAITAAYJmR1cDwCEAQATAAYJmR1cDwCEAQAAAA==.',
Ov='Ova:BAAALgAECgQJBQAAAA==.Ovelaa:BAAALgAECgQJBAAAAA==.',
Ox='Oxxo:BAABLgAECn8jAAInAAcJ1A69DABGAQAnAAcJ1A69DABGAQAAAA==.',
Pa='Palzamb:BAAALgADCgYJCwAAAA==.Pandacillin:BAAALgAECgQJBAAAAA==.Paraggonn:BAABLgAECn8qAAIDAAcJwBdpTwCxAQADAAcJwBdpTwCxAQAAAA==.',
Pe='Penelöpe:BAAALgAECgMJBAAAAA==.Penoosê:BAAALgADCgEJAgAAAA==.Perlonis:BAAALgAECgYJEwAAAA==.',
Ph='Phatocaster:BAAALgADCgIJBAAAAA==.Phoinyx:BAAALgAECgkJDwAAAA==.Phuriosa:BAAALgAECgcJDwABLgAFFAMJCQAFAO8VAA==.Phury:BAACLgAFFH8JAAIFAAMJ7xWkOADHAAAFAAMJ7xWkOADHAAAuAAQKfyQAAwUACQlSGjYnABQCAAUACAkbGTYnABQCAAsAAgkmF7hfAJYAAAAA.Physinyx:BAAALgAECgkJCgAAAA==.Physta:BAAALgADCggJCwAAAA==.',
Pi='Pizza:BAABLgAECn8gAAIOAAcJTxhmFgCcAQAOAAcJTxhmFgCcAQAAAA==.',
Pl='Plagafel:BAAALgADCgYJBgAAAA==.',
Po='Pomomies:BAAALgAECgMJBAAAAA==.Pooseunpoose:BAAALgAFFAEJBAAAAA==.Porkmancer:BAAALgAECgYJCgABLgAECgkJJgAJAEwfAA==.Porkslope:BAABLgAECn8mAAIJAAgJTB8/JgBpAgAJAAgJTB8/JgBpAgAAAA==.',
Pr='Praahv:BAAALgADCgYJBgAAAA==.Profryktor:BAABLgAECn8ZAAIeAAYJIRUTJABBAQAeAAYJIRUTJABBAQAAAA==.',
Pu='Purebloods:BAAALgADCgEJAQAAAA==.Purpleparrot:BAAALgAECgQJBAAAAA==.',
Qu='Quickben:BAAALgAECgIJAgAAAA==.',
Ra='Raenyx:BAABLgAECn8/AAMMAAgJ3x7oHQBwAgAMAAgJ3x7oHQBwAgAXAAMJag5iKwBrAAAAAA==.Raiflock:BAABLgAECn8aAAIXAAgJ4xN+CQDJAQAXAAgJ4xN+CQDJAQAAAA==.Ranalastus:BAAALgAECgUJDQAAAA==.Raveneyes:BAEBLgAECn8jAAIMAAkJjhHRQwDPAQAMAAkJjhHRQwDPAQAAAA==.',
Re='Reiena:BAAALgAECgcJEAAAAA==.Relas:BAAALgADCgUJBQAAAA==.Reylilyn:BAABLgAECn8oAAIbAAkJqBW3GgA+AgAbAAkJqBW3GgA+AgAAAA==.Reynarena:BAAALgAECgYJEAAAAA==.',
Rh='Rhaenfyre:BAABLgAECn8jAAMWAAkJMBXAOQDdAQAWAAkJMBXAOQDdAQAcAAEJ9QwkOAAlAAAAAA==.',
Ri='Richardhurtz:BAAALgAECgYJBgAAAA==.Ricola:BAAALgAFFAIJBAAAAA==.Rivenel:BAACLgAFFH8SAAIdAAYJVRNpAwCRAQAdAAYJVRNpAwCRAQAuAAQKfykAAx0ACQkgIjUCAJ8CAB0ACAlaIzUCAJ8CAAwAAQmHGZ8bAUoAAAAA.Rivèn:BAAALgADCgEJAQAAAA==.',
Ro='Robinvoid:BAABLgAECn8dAAMWAAkJgCAPFQDZAgAWAAkJgCAPFQDZAgAZAAEJ+RRiaQBAAAAAAA==.Rocksann:BAAALgAECgEJAwAAAA==.Rodel:BAAALgAECgEJAgABLgAECgMJAwAEAAAAAA==.Roquan:BAABLgAECn8wAAIaAAgJ7Ru+CAD9AQAaAAgJ7Ru+CAD9AQAAAA==.Roulette:BAAALgAECgUJDwAAAA==.',
Ru='Rubmyrott:BAAALgAFFAQJBAAAAA==.Runalot:BAAALgAECgYJBgAAAA==.Runelle:BAAALgADCgEJAQAAAA==.',
['Ré']='Rébél:BAAALgADCgEJAQAAAA==.',
['Rê']='Rêdd:BAABLgAECn8bAAIKAAcJXxH7LgBkAQAKAAcJXxH7LgBkAQAAAA==.',
Sa='Sabeion:BAAALgAECgYJDAAAAA==.Saboo:BAAALgAECgQJAQABLgAECgYJBgAEAAAAAA==.Sadiebuding:BAAALgAECgEJAQAAAA==.Salswarriah:BAABLgAECn8bAAISAAcJEhGWOABkAQASAAcJEhGWOABkAQAAAA==.Sanaku:BAAALgAECgYJCAAAAA==.Sanangra:BAAALgADCgEJAQAAAA==.Santo:BAAALgADCgMJAwAAAA==.Sarlyan:BAAALgADCgkJFwAAAA==.Sassafrazz:BAAALgAECgQJBAAAAA==.',
Sc='Scrumbles:BAAALgAECgkJDwAAAA==.',
Se='Secksytoes:BAAALgAECgMJAwABLgADCgYJCwAEAAAAAA==.Seraphim:BAAALgADCgEJAQAAAA==.Serion:BAAALgADCgMJAwAAAA==.Sewerrat:BAAALgADCggJCAAAAA==.',
Sg='Sgtbonesnap:BAAALgAECgYJDQAAAA==.Sgtpunchy:BAAALgADCgMJBQABLgAECgYJDQAEAAAAAA==.',
Sh='Shakuro:BAAALgAECgEJAgAAAA==.Shallash:BAAALgAECgEJAQAAAA==.Shamageddon:BAAALgAECgIJBAAAAA==.Shamanizim:BAACLgAFFH8MAAMVAAUJshROIAAZAQAVAAUJshROIAAZAQAYAAEJfgSvGwA7AAAuAAQKfyoABBUACAmUHPQcAPgBABUACAkpHPQcAPgBABgABwnlFV4XAE0BAAEAAgknBrTNADsAAAAA.Shausin:BAAALgAECggJCAAAAA==.Sheeanna:BAAALgAFFAEJAQABLgAFFAQJDQAUADgjAA==.Shiftmyself:BAAALgADCgkJDgAAAA==.Shikigami:BAAALgAECgkJBwAAAA==.Shinoikari:BAACLgAFFH8IAAIaAAIJjQY9IAB+AAAaAAIJjQY9IAB+AAAuAAQKfygAAxoACQkNEWkKANUBABoACQkNEWkKANUBABMABQnJCApDAIEAAAAA.Shinotenshi:BAABLgAECn8bAAQfAAcJtwmWOAAwAQAfAAcJvAiWOAAwAQARAAUJBweMYgCmAAAKAAEJKASOkwAlAAABLgAFFAIJCAAaAI0GAA==.Shirase:BAABLgAECn8eAAMMAAkJdw4ObABkAQAMAAkJHgwObABkAQAXAAYJRQ6vFwAFAQABLgAFFAQJDQABANclAA==.Shugarae:BAABLgAECn8cAAMLAAgJPQhXPQAXAQALAAgJPQhXPQAXAQAFAAUJcATVngBwAAAAAA==.',
Si='Sionnocht:BAAALgADCgEJAQAAAA==.Sirlemage:BAAALgADCgMJAwAAAA==.',
Sk='Skina:BAAALgAECgEJAQAAAA==.Skreezy:BAAALgAECgcJDAAAAA==.Skuls:BAAALgAECgMJBwAAAA==.',
Sl='Slashemup:BAABLgAECn8jAAIZAAkJ+RbjEQALAgAZAAkJ+RbjEQALAgAAAA==.Slayter:BAABLgAECn8lAAIFAAkJ2R/sHABcAgAFAAkJ2R/sHABcAgAAAA==.',
Sm='Smaugin:BAAALgAECgIJAgAAAA==.',
Sn='Snakelazers:BAACLgAFFH8HAAIbAAQJgiHMHAB/AQAbAAQJgiHMHAB/AQAuAAQKfyUAAhsACQn6IqgEAGMDABsACQn6IqgEAGMDAAAA.Snufulafagus:BAABLgAECn8WAAIPAAUJbRv3GQA6AQAPAAUJbRv3GQA6AQAAAA==.',
So='Soju:BAABLgAECn8oAAMBAAkJ9BcDGwBwAgABAAkJ9BcDGwBwAgAVAAQJJxJhbACgAAABLgAECgkJLAADAMkjAA==.Soliloquy:BAAALgAECgYJBgAAAA==.Songwind:BAABLgAECn8qAAImAAgJYg1ZLQBVAQAmAAgJYg1ZLQBVAQAAAA==.Soonie:BAAALgADCgEJAQAAAA==.Soulreever:BAAALgADCggJCAAAAA==.',
Sq='Squishyman:BAAALgAECgEJAQABLgAECgkJHAAIACkeAA==.Squishypal:BAABLgAECn8cAAMIAAkJKR4wFQDCAgAIAAkJKR4wFQDCAgAoAAEJ6xYjPwBBAAAAAA==.',
St='Starfirelmao:BAAALgAECgYJDwAAAA==.Steelcure:BAAALgAECggJCgAAAA==.Strabo:BAAALgADCggJCQAAAA==.Strawdicks:BAAALgAECgcJAQAAAA==.',
Su='Sugma:BAAALgAECgEJAQAAAA==.Suzsette:BAABLgAECn8eAAIKAAcJNglwQQAJAQAKAAcJNglwQQAJAQAAAA==.',
Sy='Sylris:BAAALgADCgkJFgAAAA==.Sylvanthis:BAAALgAECgQJBAABLgAECgkJHgAFABUMAA==.',
['Sç']='Sçoxx:BAAALgADCgEJAQAAAA==.',
Ta='Taazdingo:BAAALgADCgEJAQAAAA==.Taeleth:BAAALgADCgcJBwAAAA==.Talnora:BAAALgAECgYJDwAAAA==.Tardovski:BAABLgAECn8lAAMDAAkJGSG8DwDQAgADAAkJGSG8DwDQAgACAAQJ2BP2VgDsAAAAAA==.Taurentino:BAAALgAECgkJBQAAAA==.',
Te='Telaris:BAAALgADCgIJAgAAAA==.Telda:BAABLgAECn8WAAIlAAYJZwSEFwC4AAAlAAYJZwSEFwC4AAAAAA==.Teneturadvós:BAAALgAECgcJAwABLgAECgcJDQAEAAAAAA==.Tentreeadvos:BAAALgAECgEJAQABLgAECgcJDQAEAAAAAA==.Tetris:BAACLgAFFH8QAAINAAUJ3hzsSgBPAQANAAUJ3hzsSgBPAQAuAAQKfzgAAg0ACQmgIvQVANQCAA0ACQmgIvQVANQCAAAA.',
Th='Thellaria:BAAALgADCgQJBAAAAA==.Thraggoar:BAAALgADCgEJAQAAAA==.Thunsar:BAAALgAECgkJDwAAAA==.Thuzzad:BAAALgADCgUJBQAAAA==.',
Ti='Tickler:BAAALgAECgUJEQAAAA==.Tiroelin:BAAALgAECgUJBwAAAA==.',
To='Toetem:BAAALgADCgQJBgAAAA==.Tosselus:BAAALgAECgEJAQAAAA==.Tox:BAAALgADCgUJBQAAAA==.Toyotama:BAAALgAFFAIJAgABLgAFFAUJGQAFAPkkAA==.',
Tr='Tragedeigh:BAAALgAECgUJBQABLgAECgkJIwAGALsZAA==.Trane:BAAALgAECgIJAgAAAA==.Tritoch:BAAALgAECgYJEAAAAA==.Troche:BAACLgAFFH8IAAIoAAQJEQgyDACxAAAoAAQJEQgyDACxAAAuAAQKfxgAAygACQmDEfUPAMIBACgACQmDEfUPAMIBABQAAQlNCPmWACgAAAAA.Truthfully:BAAALgAECgcJEAAAAA==.Trávpac:BAAALgADCgEJAQAAAA==.',
Tt='Ttjpll:BAAALgAECgYJDwAAAA==.',
Tu='Tubs:BAAALgAECgEJAQAAAA==.Tuckncloak:BAAALgAECgIJAgAAAA==.',
Tw='Twohand:BAAALgADCgIJBAAAAA==.',
['Tî']='Tîmon:BAAALgAFFAIJAgAAAA==.',
Ug='Ugrup:BAAALgAECgYJDgAAAA==.',
Uj='Ujabula:BAAALgAECgYJEgAAAA==.',
Ul='Ulurak:BAABLgAECn8YAAMPAAgJPw8aGwAaAQAPAAYJkwkaGwAaAQAFAAQJ9QqVpQBlAAAAAA==.',
Un='Uncleskip:BAABLgAECn8bAAIeAAcJ0wd0FgBJAQAeAAcJ0wd0FgBJAQAAAA==.Unhappytoast:BAABLgAECn8WAAIoAAkJdBgICgApAgAoAAkJdBgICgApAgAAAA==.Unstobubble:BAAALgAECgYJCQAAAA==.',
Va='Valeriya:BAAALgADCgcJCAABLgAECgMJAwAEAAAAAA==.Valisanna:BAAALgADCggJDQAAAA==.Vallorien:BAABLgAECn8eAAIoAAcJyh/jCgAZAgAoAAcJyh/jCgAZAgAAAA==.Valsharess:BAAALgADCgcJBwABLgAECgkJOAAWAEEaAA==.',
Ve='Vegtam:BAAALgAECgEJAQAAAA==.Velaryn:BAAALgAFFAIJAgAAAA==.Velnia:BAAALgAECgYJCwAAAA==.Verencia:BAAALgAECgEJAQAAAA==.',
Vi='Vildaren:BAAALgAECgUJCQAAAA==.Vivachel:BAAALgADCgcJCAAAAA==.Viztrix:BAAALgADCgEJAQAAAA==.',
Vo='Vorsan:BAAALgADCgcJBwAAAA==.Vorsane:BAAALgADCgQJBAAAAA==.',
['Và']='Vàli:BAAALgAECgQJCQAAAA==.',
Wa='Wanks:BAAALgAECgYJDwAAAA==.Warmoon:BAAALgAECgMJAwAAAA==.Warskul:BAAALgADCgEJAQAAAA==.Wasenshi:BAAALgADCgUJBQAAAA==.',
We='Weeb:BAAALgADCgUJCwAAAA==.Weeny:BAAALgAECgcJCwAAAA==.',
Wh='Wholy:BAAALgAECgMJBgAAAA==.',
Wi='Wickedromeo:BAAALgAECgMJAwAAAA==.',
Wo='Wolfmother:BAABLgAECn8jAAIVAAgJpxRGKgCdAQAVAAgJpxRGKgCdAQAAAA==.',
Xa='Xaanii:BAABLgAECn8bAAIUAAYJUB0FIwDrAQAUAAYJUB0FIwDrAQAAAA==.Xandius:BAAALgADCgcJDAAAAA==.Xarferrin:BAABLgAECn8jAAINAAcJDgMF6QDLAAANAAcJDgMF6QDLAAAAAA==.',
Xe='Xeeria:BAACLgAFFH8hAAIBAAUJShN7LAArAQABAAUJShN7LAArAQAuAAQKfzAAAwEACQnyHwoNALUCAAEACQnyHwoNALUCABUAAQlXG+SQAE4AAAAA.Xenzull:BAAALgAECgIJAgAAAA==.',
Xk='Xkaliber:BAAALgADCgEJAQAAAA==.',
Xu='Xuecat:BAABLgAECn8kAAIFAAgJ3xYQLgD1AQAFAAgJ3xYQLgD1AQAAAA==.',
Yn='Yn:BAAALgAECgYJDAAAAA==.',
Za='Zamzak:BAAALgADCgQJBAABLgAECgEJAQAEAAAAAA==.Zanthor:BAABLgAECn8WAAIJAAUJbggm9AC4AAAJAAUJbggm9AC4AAAAAA==.Zaralina:BAACLgAFFH8HAAIKAAQJkQi4IADpAAAKAAQJkQi4IADpAAAuAAQKfzQAAgoACQlPFx8SAEUCAAoACQlPFx8SAEUCAAAA.Zartox:BAABLgAECn8cAAIpAAkJoRanAgAcAgApAAkJoRanAgAcAgAAAA==.Zaryn:BAAALgADCgIJAgAAAA==.Zarynth:BAAALgAECgEJAQAAAA==.Zaryssa:BAABLgAECn8eAAIVAAgJjwXIUQDuAAAVAAgJjwXIUQDuAAAAAA==.Zavinus:BAAALgADCgYJCAAAAA==.',
Ze='Zenzug:BAAALgAECgUJDwAAAA==.Zephystra:BAAALgADCgQJBAABLgAFFAQJDQABANclAA==.Zeusqt:BAAALgADCgYJBgAAAA==.',
Zh='Zharfrost:BAAALgAECgYJCAAAAA==.',
Zi='Zicroniah:BAAALgADCgYJCgAAAA==.Ziyuu:BAAALgADCgUJBQAAAA==.',
Zo='Zombiehunter:BAABLgAECn8jAAIDAAkJaR+LEQDDAgADAAkJaR+LEQDDAgAAAA==.',
Zu='Zuzu:BAAALgADCgMJAwAAAA==.',
['Âr']='Ârc:BAAALgAECgEJAgAAAA==.',
['Èd']='Èddy:BAACLgAFFH8GAAIFAAMJTQlLSgCOAAAFAAMJTQlLSgCOAAAuAAQKfx0AAgUACQk0FpUcAF8CAAUACQk0FpUcAF8CAAAA.',
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
