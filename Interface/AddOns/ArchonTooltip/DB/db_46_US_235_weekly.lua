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

local lookup = {'Shaman-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Druid-Restoration','Evoker-Preservation','Evoker-Devastation','Paladin-Retribution','DeathKnight-Unholy','Priest-Shadow','Druid-Balance','Warlock-Demonology','Unknown-Unknown','Mage-Frost','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Priest-Holy','Warrior-Fury','DeathKnight-Blood','Paladin-Holy','Shaman-Elemental','DemonHunter-Devourer','Warlock-Affliction','Shaman-Enhancement','DemonHunter-Havoc','DeathKnight-Frost','Monk-Mistweaver','DemonHunter-Vengeance','Warlock-Destruction','Warrior-Arms','Priest-Discipline','Mage-Fire','Warrior-Protection','Rogue-Subtlety','Monk-Brewmaster','Rogue-Assassination','Monk-Windwalker','Rogue-Outlaw','Paladin-Protection','Mage-Arcane',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=46,date='2026-06-21',data={Ad='Addisyn:BAAALgAECgEJBAAAAA==.',
Ae='Aekal:BAAALgAECgUJBQAAAA==.Aemetris:BAABLgAECn8ZAAIBAAcJMxfyNADeAQABAAcJMxfyNADeAQAAAA==.Aenicus:BAAALgADCgcJBwAAAA==.Aerina:BAAALgAECgQJCwAAAA==.Aethra:BAAALgADCgYJBgAAAA==.',
Ag='Agamotto:BAAALgAECgYJCgAAAA==.Agromagnetic:BAAALgAECgcJDQAAAA==.Agytha:BAAALgAECgMJAwAAAA==.Agøny:BAAALgADCgMJAwAAAA==.',
Ah='Ahskul:BAAALgADCgEJAQAAAA==.',
Ai='Aidendawn:BAAALgAECgYJEAAAAA==.',
Aj='Ajheria:BAAALgAECgEJAQAAAA==.',
Am='Ameildoran:BAAALgADCgkJCQAAAA==.Amelicea:BAAALgADCgMJAwAAAA==.',
An='Anaru:BAAALgAECgMJBgAAAA==.Anatyriel:BAAALgADCgEJAQAAAA==.Anayanci:BAAALgADCgUJBgAAAA==.Andalaine:BAAALgAECgMJBQAAAA==.Andari:BAAALgADCgEJAQAAAA==.Andramaedra:BAAALgAECgkJAgAAAA==.Anoobornot:BAAALgADCgMJAwAAAA==.Anraleth:BAACLgAFFH8SAAICAAQJ9iMjDACgAQACAAQJ9iMjDACgAQAuAAQKfzwAAwIACQkLJQgDAKwCAAIACAnnJAgDAKwCAAMAAQkGJqD6AGUAAAAA.',
Ap='Aponi:BAAALgAECgUJCAAAAA==.',
Ar='Arckillion:BAAALgAECgMJAwAAAA==.Ardour:BAAALgAECgMJBgABLgAECgcJGgAEABANAA==.Arduous:BAAALgAECgMJAwAAAA==.Arihu:BAABLgAECn8fAAIFAAkJlxT9LgDoAQAFAAkJlxT9LgDoAQAAAA==.Arkhana:BAAALgADCgEJAQAAAA==.Arrawm:BAAALgAECgEJAQAAAA==.',
As='Ashenaya:BAABLgAECn8YAAMGAAgJLxlbDAAQAgAGAAgJLxlbDAAQAgAHAAEJMQpQQgArAAAAAA==.Asparagus:BAABLgAECn8aAAIIAAkJVw59YwCpAQAIAAkJVw59YwCpAQAAAA==.',
At='Atlass:BAACLgAFFH8GAAIJAAIJLhXf0gCOAAAJAAIJLhXf0gCOAAAuAAQKfxgAAgkABwnxGYtjAMkBAAkABwnxGYtjAMkBAAAA.Atrest:BAAALgAECgYJBwAAAA==.',
Au='Augmenter:BAAALgAECgQJBQABLgAFFAcJHgAKAGAaAA==.Aust:BAABLgAECn8UAAIIAAgJ6hMDbACWAQAIAAgJ6hMDbACWAQAAAA==.',
Av='Averlin:BAAALgAECgUJCAAAAA==.Averlis:BAABLgAECn8hAAILAAgJSxZhHwDNAQALAAgJSxZhHwDNAQAAAA==.Avoiddance:BAAALgADCgEJAQAAAA==.',
Ax='Axee:BAAALgADCgYJBgAAAA==.',
Az='Azima:BAAALgAECgMJAwAAAA==.Azura:BAAALgADCgIJAgAAAA==.Azurargentyr:BAAALgAECgkJEAAAAA==.',
Ba='Babeolicious:BAAALgADCgEJAQAAAA==.Bacon:BAABLgAECn8lAAIIAAkJzAp1hgBjAQAIAAkJzAp1hgBjAQAAAA==.Bambøøze:BAAALgADCgEJAQAAAA==.Bandadi:BAECLgAFFH8IAAIMAAYJwhWeKwCXAQAMAAYJwhWeKwCXAQAuAAQKfzEAAgwACAkzIG0VANUCAAwACAkzIG0VANUCAAEuAAUUBAkEAA0AAAAA.Barbelo:BAAALgAECgcJCgAAAA==.Barely:BAAALgAECgkJEQAAAA==.Barkweldort:BAAALgAECgYJEQAAAA==.Barreled:BAAALgADCgMJAwAAAA==.Batistabomba:BAAALgAECgYJBgAAAA==.',
Be='Beargruk:BAAALgAECgUJBwAAAA==.Beastly:BAAALgAECggJEQAAAA==.Beeble:BAABLgAECn8XAAIOAAYJvwmA0ADxAAAOAAYJvwmA0ADxAAAAAA==.Belii:BAAALgAECgYJDAAAAA==.Bended:BAAALgADCgIJAgAAAA==.Bepisthepall:BAAALgAECgEJAgAAAA==.Betterkevin:BAAALgAECgQJDwAAAA==.Bezerkachew:BAAALgAECgEJAgAAAA==.',
Bi='Bigbootijudi:BAAALgAECgEJAQAAAA==.Bigbooty:BAABLgAECn8mAAMPAAgJPAn1AQDcAAAPAAgJNQn1AQDcAAAQAAUJIAe/NwB8AAAAAA==.',
Bl='Blikey:BAABLgAFFH8GAAIJAAIJfiazvQCuAAAJAAIJfiazvQCuAAAAAA==.Bloodyrott:BAAALgAECgUJCgAAAA==.Bluedrake:BAACLgAFFH8NAAMHAAQJ1BtUAwBEAQAHAAQJ1BtUAwBEAQARAAEJPROjZABAAAAuAAQKfyMAAwcACAlfHr4EALoCAAcACAmGHb4EALoCABEACAk9FlIZAAMCAAEuAAUUBgkUAAsAAh8A.Blueparrot:BAABLgAECn81AAISAAgJXxXhGwDoAQASAAgJXxXhGwDoAQAAAA==.Bluy:BAAALgADCgMJAwAAAA==.Blädèstorm:BAABLgAECn8ZAAITAAgJphwNJADUAQATAAgJphwNJADUAQAAAA==.',
Bo='Bonesnap:BAACLgAFFH8VAAMJAAcJeR52HAAHAgAJAAYJeR52HAAHAgAUAAEJAAA+VQAAAAAuAAQKfyAAAwkACQmrIaMXAO4CAAkACQmrIaMXAO4CABQABAmuE1w+AJYAAAAA.Bowkatan:BAAALgAECgEJAgAAAA==.',
Br='Brianisita:BAAALgAECgUJBgAAAA==.Brightmane:BAABLgAECn8WAAIVAAYJUx4zJQD8AQAVAAYJUx4zJQD8AQAAAA==.Bringinlight:BAABLgAECn8XAAISAAYJJwy4AwCJAAASAAYJJwy4AwCJAAAAAA==.',
Bu='Bubbleicious:BAAALgAECgYJEgAAAA==.Bubbletea:BAABLgAECn8YAAIIAAgJLhb4SQDoAQAIAAgJLhb4SQDoAQABLgAECgkJLAADAMkjAA==.Bulletz:BAABLgAECn8eAAICAAgJ7x0KBQBbAgACAAgJ7x0KBQBbAgAAAA==.Bumpersnouts:BAAALgADCgkJCQAAAA==.Buttfur:BAAALgADCgYJBgAAAA==.',
['Bê']='Bêarwithme:BAAALgAECgIJBgABLgAECgcJGwAKAF8RAA==.',
Ca='Caenzo:BAAALgADCgkJCgAAAA==.Casanna:BAAALgADCgYJBgAAAA==.Cassandria:BAABLgAECn8sAAMFAAgJBxDUVAA8AQAFAAcJqw7UVAA8AQALAAgJ2Az+OgAmAQAAAA==.Cassiradra:BAAALgADCgEJAQAAAA==.Caylastus:BAAALgAECgEJAgAAAA==.',
Ce='Cearas:BAAALgAECgEJAQAAAA==.Cedrick:BAAALgAECgUJBQAAAA==.Celiona:BAAALgAECgkJBwAAAA==.Celody:BAAALgAECgYJDAAAAA==.Celticsinsix:BAAALgAECgMJBQAAAA==.Cervixticklr:BAAALgAECgUJBgAAAA==.',
Ch='Chaoten:BAAALgADCgEJAQAAAA==.Chathlia:BAAALgAECgQJBAAAAA==.Chavdar:BAAALgADCgEJAQAAAA==.Chewster:BAABLgAECn81AAIOAAgJJhBwdgCMAQAOAAgJJhBwdgCMAQAAAA==.Chixie:BAAALgADCgEJAQAAAA==.Choal:BAABLgAECn8WAAIFAAYJyBCmYQAQAQAFAAYJyBCmYQAQAQAAAA==.Choglana:BAAALgAECgcJCQAAAA==.Chogli:BAAALgAECgEJAQABLgAECgcJCQANAAAAAA==.Chogric:BAABLgAECn85AAMVAAkJhh+NBQATAwAVAAkJhh+NBQATAwAIAAQJZw2JKAGJAAABLgAECgcJCQANAAAAAA==.',
Ci='Civetta:BAABLgAECn8WAAIDAAkJhwzqUQCtAQADAAkJhwzqUQCtAQAAAA==.',
Cl='Clannininick:BAAALgADCgUJBgAAAA==.Clark:BAAALgADCgEJAQAAAA==.',
Co='Cogswell:BAAALgADCgIJAgAAAA==.Comespankit:BAAALgAECgUJBQAAAA==.Constiua:BAAALgAECgcJDwABLgAECgcJCQANAAAAAA==.Convalesor:BAABLgAECn8UAAIKAAYJQQiaTwDSAAAKAAYJQQiaTwDSAAAAAA==.',
Cr='Crazzywazzy:BAABLgAFFH8KAAIJAAQJcBhtbAAjAQAJAAQJcBhtbAAjAQAAAA==.Crep:BAAALgAECgEJAQABLgAECgcJCgANAAAAAA==.Crona:BAABLgAECn8aAAIVAAkJtg4LPACJAQAVAAkJtg4LPACJAQAAAA==.Crsteel:BAAALgAECgEJAQAAAA==.Crzyblnkrton:BAACLgAFFH8PAAIOAAYJthAERgBaAQAOAAYJthAERgBaAQAuAAQKfxcAAg4ACAnmH2k5AJACAA4ACAnmH2k5AJACAAAA.Crzzy:BAABLgAFFH8LAAIWAAcJYRImEACsAQAWAAcJYRImEACsAQAAAA==.',
Cu='Cuddlez:BAABLgAECn8gAAISAAkJGQtTLQBiAQASAAkJGQtTLQBiAQAAAA==.Cultera:BAACLgAFFH8RAAIXAAQJuxJYSAAPAQAXAAQJuxJYSAAPAQAuAAQKfx8AAhcACAlUIOAAANIBABcACAlUIOAAANIBAAAA.',
Cy='Cyhyraethia:BAABLgAECn8fAAIYAAgJDB+sBQANAgAYAAgJDB+sBQANAgABLgAECgkJOAAXAEEaAA==.Cyndera:BAAALgADCgEJAQAAAA==.',
Da='Dagden:BAAALgADCgYJCAAAAA==.Dalaa:BAAALgAECgIJAgAAAA==.Dammnation:BAAALgAECgYJBwABLgAECgcJGwAKAF8RAA==.Danda:BAAALgAECgYJCgAAAA==.Daricepicker:BAABLgAECn8sAAIDAAkJySNPBQA3AwADAAkJySNPBQA3AwAAAA==.Darkyn:BAABLgAECn8ZAAIMAAkJPRCyRwDDAQAMAAkJPRCyRwDDAQAAAA==.Davedadude:BAABLgAECn8wAAIIAAkJEyIzDAADAwAIAAkJEyIzDAADAwAAAA==.',
Dd='Ddeonu:BAAALgAECgEJAQAAAA==.Ddeonuu:BAABLgAFFH8MAAMDAAYJCw2kJwBoAQADAAYJAwukJwBoAQACAAQJ2gxqGAD1AAAAAA==.',
De='Deadlysins:BAABLgAECn8WAAIJAAgJ8wvpbACwAQAJAAgJ8wvpbACwAQAAAA==.Deadscar:BAECLgAFFH8OAAIZAAQJ+SOAAwCcAQAZAAQJ+SOAAwCcAQAuAAQKfzQAAhkACQlSJq0AAFwDABkACQlSJq0AAFwDAAAA.Deathmasterj:BAAALgADCggJDgAAAA==.Deaths:BAABLgAECn8eAAMaAAgJTRJbHACaAQAaAAgJTRJbHACaAQAXAAEJJQRGOAEdAAAAAA==.Dedfrosty:BAABLgAECn8mAAMbAAgJ/hDDEQBcAQAbAAgJIg3DEQBcAQAUAAgJQw4sJgAiAQAAAA==.Demomcgee:BAAALgADCgEJAgABLgAECgYJDwANAAAAAA==.Demonio:BAAALgAECgEJAQAAAA==.Demonpimp:BAAALgAECgYJEAAAAA==.Dermon:BAAALgAECggJCwABLgAFFAQJBwAcAIIhAA==.Deviously:BAAALgADCgQJBAABLgAECgkJHgACAO8dAA==.Dewyhuey:BAAALgADCgIJAgAAAA==.',
Dh='Dhoong:BAAALgAECgIJAgAAAA==.',
Di='Dimpiana:BAAALgAECgQJBAAAAA==.Disciplea:BAAALgAECgQJBAAAAA==.Dithariaa:BAABLgAECn8mAAIdAAcJHg7xEgAiAQAdAAcJHg7xEgAiAQAAAA==.',
Do='Docryktor:BAABLgAECn8+AAIZAAkJ+hoMCgAaAgAZAAkJ+hoMCgAaAgAAAA==.Doomgears:BAABLgAECn8fAAIeAAYJZxfjDgBQAQAeAAYJZxfjDgBQAQAAAA==.Dotsdead:BAAALgADCgYJDgAAAA==.Dotöri:BAAALgAECggJDwAAAA==.',
Dr='Draculä:BAAALgAECgQJBAAAAA==.Dragonair:BAABLgAECn8bAAMGAAcJ8QMjJADNAAAGAAcJ8QMjJADNAAAHAAcJ7ALdFwCcAAAAAA==.Drashta:BAAALgAECgEJAQAAAA==.Drhoe:BAAALgAECgEJAQAAAA==.Drhurtouch:BAABLgAECn8jAAIfAAkJCx2IBQCxAgAfAAkJCx2IBQCxAgAAAA==.Dro:BAAALgAECgQJCgAAAA==.Drogas:BAAALgAECgIJBAAAAA==.Drtybear:BAABLgAECn8jAAMPAAkJ3BSHIwA0AQAPAAcJbhKHIwA0AQAQAAUJ5hNxIQD9AAAAAA==.Druithh:BAAALgAFFAEJAQABLgAFFAYJFQAOAGsYAA==.Drulissa:BAACLgAFFH8OAAIVAAQJOCMPFQCBAQAVAAQJOCMPFQCBAQAuAAQKfxkAAhUACQl1GZktAM0BABUACQl1GZktAM0BAAAA.Druu:BAAALgADCgMJAwABLgAFFAYJFQAOAGsYAA==.',
Du='Duh:BAAALgAECgEJAQAAAA==.Duogear:BAAALgADCgEJAQAAAA==.Dusters:BAAALgADCgcJCwAAAA==.',
['Dâ']='Dârrius:BAAALgAECggJCAAAAA==.',
Eb='Ebonwings:BAAALgAECgcJDgAAAA==.',
Ed='Ediana:BAACLgAFFH8FAAIOAAMJxAKmlACpAAAOAAMJxAKmlACpAAAuAAQKfycAAg4ACQnqCRZ4AIkBAA4ACQnqCRZ4AIkBAAAA.',
El='Eld:BAAALgAECgEJAQAAAA==.Elmô:BAABLgAECn83AAIVAAgJHiG7CgDgAgAVAAgJHiG7CgDgAgAAAA==.Elody:BAAALgADCgYJBgAAAA==.Elvara:BAAALgAECgUJDQAAAA==.',
Eq='Equipwooman:BAAALgADCgIJAgAAAA==.',
Es='Estameling:BAABLgAECn8qAAIPAAgJyhZpGACNAQAPAAgJyhZpGACNAQAAAA==.',
Ex='Exash:BAACLgAFFH8NAAIWAAQJwRrSHAA1AQAWAAQJwRrSHAA1AQAuAAQKfycAAhYACQk7ITUJAP8CABYACQk7ITUJAP8CAAAA.Excizion:BAACLgAFFH8FAAIJAAIJpQOZ8gB5AAAJAAIJpQOZ8gB5AAAuAAQKfyUAAgkACQnzCzRgAKkBAAkACQnzCzRgAKkBAAAA.',
Fa='Faelynne:BAAALgADCgUJBQAAAA==.Fari:BAAALgAECgcJDAAAAA==.Fathertim:BAABLgAECn8mAAIgAAcJsRvZGAAMAgAgAAcJsRvZGAAMAgAAAA==.',
Fe='Feannara:BAAALgAECgYJCQAAAA==.Felar:BAAALgADCgEJAQAAAA==.Feldrena:BAAALgADCgcJDAAAAA==.',
Fl='Flangus:BAAALgADCgMJBAAAAA==.Flappydragon:BAAALgADCgIJAgAAAA==.Floraria:BAAALgADCgYJBgAAAA==.',
Fr='Frostii:BAABLgAECn8aAAIOAAkJoBp0ZwCuAQAOAAkJoBp0ZwCuAQAAAA==.',
Fu='Fudestamp:BAAALgADCgQJBQAAAA==.Fufight:BAAALgAECgIJBQABLgAFFAQJBwAcAIIhAA==.Fugryktor:BAABLgAECn80AAIYAAgJVxWmCADcAQAYAAgJVxWmCADcAQAAAA==.',
Fy='Fyrebug:BAABLgAECn8bAAIBAAYJ2QyVbQATAQABAAYJ2QyVbQATAQAAAA==.',
Ga='Galandor:BAABLgAECn8cAAIVAAcJYBsjGwArAgAVAAcJYBsjGwArAgAAAA==.Gandaalf:BAABLgAECn8WAAMhAAcJCR7XAQBrAgAhAAcJCR7XAQBrAgAOAAIJ4Q9RRgFzAAAAAA==.Garrinda:BAAALgAECgkJDgAAAA==.Gaya:BAAALgAECgYJBgAAAA==.',
Ge='Geeked:BAAALgADCgUJBQAAAA==.Gemhide:BAABLgAECn8jAAIeAAkJzxKfCADCAQAeAAkJzxKfCADCAQAAAA==.Georgharison:BAAALgAECgEJAQAAAA==.Geroy:BAAALgAECgEJAQAAAA==.',
Gg='Ggwp:BAAALgAECgEJAQAAAA==.',
Gh='Ghae:BAAALgAECgUJBAAAAA==.Ghostsaber:BAAALgADCgEJAQABLgAECggJGQAiAM8cAA==.',
Gi='Gigglyguff:BAABLgAECn8YAAIFAAgJRiAgEgC9AgAFAAgJRiAgEgC9AgAAAA==.Gimly:BAAALgAECgEJAQAAAA==.Gityadruid:BAAALgAECgEJAQABLgAECgYJFwASACcMAA==.Gityahunter:BAAALgAECgQJBgABLgAECgYJFwASACcMAA==.',
Gl='Glavenus:BAAALgADCgEJAQAAAA==.',
Go='Gobank:BAAALgADCgIJAgAAAA==.Gobanks:BAABLgAECn87AAIIAAkJXCCMEwDNAgAIAAkJXCCMEwDNAgAAAA==.',
Gr='Graycat:BAAALgADCgIJAgABLgAFFAgJGgAEAMsjAA==.Grayele:BAAALgAECgIJAgAAAA==.Grayson:BAABLgAECn8aAAIIAAcJMwWB9QDEAAAIAAcJMwWB9QDEAAAAAA==.Graysurv:BAACLgAFFH8aAAIEAAgJyyMEAACBAgAEAAgJyyMEAACBAgAuAAQKfykAAgQACQn6JgUAABQEAAQACQn6JgUAABQEAAAA.Gregmiller:BAAALgADCgYJBgAAAA==.Grizzly:BAAALgADCgUJBQAAAA==.Gromlin:BAAALgAECgUJDAAAAA==.Grothfen:BAAALgAECgYJCwAAAA==.',
['Gä']='Gäreth:BAAALgADCgYJCwAAAA==.',
Ha='Habachi:BAAALgADCgEJAQAAAA==.Halcrenian:BAAALgAECgIJAgAAAA==.Hamelot:BAAALgADCgMJBAAAAA==.Hamremmi:BAAALgAECgEJAQABLgAFFAcJHgAKAGAaAA==.Handrider:BAAALgAECgEJAQAAAA==.Haruharu:BAAALgAECgUJCQABLgAECgkJJQAFANkfAA==.Hasalia:BAAALgAECggJCAABLgAFFAQJDgAVADgjAA==.',
He='Healsforu:BAAALgAECgUJDQABLgAECgcJDgANAAAAAA==.Helly:BAAALgAECgEJAQAAAA==.Hemidall:BAAALgADCgMJAwAAAA==.Herbievore:BAABLgAECn8UAAMPAAgJORgvJQApAQAPAAUJ8RovJQApAQALAAYJAhHWVAC8AAAAAA==.Heunno:BAAALgADCgYJBgABLgAECgcJCgANAAAAAA==.',
Hi='Hiemy:BAAALgAECgYJBgAAAA==.Hif:BAACLgAFFH8HAAIFAAQJAh3jIABRAQAFAAQJAh3jIABRAQAuAAQKfyMAAgUACQn2I7QFADEDAAUACQn2I7QFADEDAAAA.Highbrittz:BAAALgAECgYJDgAAAA==.',
Hm='Hmmisee:BAAALgAECgEJAgAAAA==.',
Ho='Hoakaren:BAABLgAECn8ZAAIXAAkJAxZ7MAAEAgAXAAkJAxZ7MAAEAgAAAA==.Hobiscuits:BAEALgADCgQJBAABLgAECgYJIQAMAGwiAA==.Hocus:BAAALgADCgYJBgAAAA==.Holde:BAAALgAECgUJDQAAAA==.Hornyrott:BAAALgAECgQJBQAAAA==.',
Hu='Hunterzamb:BAAALgAECgEJAQAAAA==.Huntinator:BAABLgAECn8VAAIDAAcJHhtwMADvAQADAAcJHhtwMADvAQAAAA==.',
Hy='Hydrobubble:BAAALgAECgYJCgAAAA==.',
['Há']='Hátfield:BAAALgADCgEJAQAAAA==.',
Ih='Ihyo:BAAALgAECgEJAQABLgAECgcJBwANAAAAAA==.',
Il='Illyy:BAABLgAECn8mAAISAAgJMgvcNgAkAQASAAgJMgvcNgAkAQAAAA==.',
Im='Impkingguy:BAAALgADCgQJBAAAAA==.',
In='Indawhole:BAACLgAFFH8eAAIXAAgJABi6FwD0AQAXAAgJABi6FwD0AQAuAAQKfxoAAhcACAl8JfkjAEACABcACAl8JfkjAEACAAAA.',
Ir='Iridori:BAABLgAECn8wAAISAAgJuCB9CwCvAgASAAgJuCB9CwCvAgAAAA==.Irönfist:BAAALgADCgkJEgAAAA==.',
It='Itzzender:BAAALgADCgIJAgAAAA==.',
Iz='Izumiwitabow:BAABLgAECn8aAAIDAAcJpxI2ZwB1AQADAAcJpxI2ZwB1AQAAAA==.',
Ja='Jabberthehut:BAAALgAFFAEJAQAAAA==.Jamerius:BAAALgAECgIJAgAAAA==.Jankovic:BAAALgADCgcJBwAAAA==.Jasmean:BAAALgADCgcJCwAAAA==.Javaluminous:BAABLgAECn8oAAIIAAgJQCBhLABQAgAIAAgJQCBhLABQAgAAAA==.Jay:BAABLgAFFH8GAAIRAAMJjxDsQwC2AAARAAMJjxDsQwC2AAABLgAFFAcJFQAjAJcWAA==.Jaytsukitori:BAACLgAFFH8aAAMFAAUJ+SQYDgATAgAFAAUJ+SQYDgATAgALAAEJgwhITwA4AAAuAAQKfx0AAwUACAmKIbkMANcCAAUACAmKIbkMANcCAAsAAQlmEEKNADMAAAAA.',
Jh='Jhaeriao:BAAALgAECgYJDAAAAA==.Jhantherox:BAAALgAECgYJBgAAAA==.',
Jo='Joesepi:BAABLgAFFH8aAAIJAAYJ6xp2KQDDAQAJAAYJ6xp2KQDDAQAAAA==.Joham:BAAALgAECgEJAQAAAA==.Jojosus:BAAALgADCgcJBwABLgADCgkJMwANAAAAAA==.Jonah:BAAALgAFFAEJAQABLgAFFAIJBQAJAB4YAA==.',
Ju='Judgeroybean:BAAALgAECgMJAwAAAA==.Juliofoolioo:BAAALgAECgEJAgAAAA==.',
Ka='Karti:BAAALgADCgQJBAAAAA==.Kayahli:BAAALgAECgQJBAAAAA==.Kazghul:BAAALgADCgEJAQAAAA==.',
Ke='Kelaeus:BAABLgAECn8VAAIOAAYJUQ5x0ABMAQAOAAYJUQ5x0ABMAQAAAA==.Keyonslayz:BAAALgADCggJCAAAAA==.',
Kh='Khrønos:BAAALgAECggJDAAAAA==.',
Ki='Kij:BAEALgAFFAQJBAAAAA==.Killzom:BAAALgADCgEJAQABLgAFFAQJCgAPACkVAA==.Kilrah:BAABLgAECn82AAIaAAkJahbfEgABAgAaAAkJahbfEgABAgAAAA==.Kirian:BAAALgADCgEJAQAAAA==.Kissmyash:BAABLgAECn8WAAIOAAYJ9AmY0wDtAAAOAAYJ9AmY0wDtAAAAAA==.Kissmycrits:BAABLgAECn8ZAAIDAAQJsB2NgwA3AQADAAQJsB2NgwA3AQAAAA==.Kissmywrath:BAAALgAECgEJAQAAAA==.Kiyana:BAABLgAECn8vAAIaAAcJIA8QLQAZAQAaAAcJIA8QLQAZAQAAAA==.Kiyoine:BAABLgAECn8iAAIQAAgJKRkRDAD4AQAQAAgJKRkRDAD4AQAAAA==.',
Kn='Knocksteady:BAACLgAFFH8TAAIIAAYJLRqhCgBXAQAIAAYJLRqhCgBXAQAuAAQKfyAAAggABwm2IYskAJUCAAgABwm2IYskAJUCAAAA.Knoxform:BAAALgAECgMJBAAAAA==.Knoxhops:BAAALgAECgMJAwABLgAECgMJBAANAAAAAA==.Knoxreaps:BAAALgAECgYJBAABLgAECgMJBAANAAAAAA==.Knoxstaggers:BAABLgAECn8lAAIkAAgJ3iBVEwAXAgAkAAgJ3iBVEwAXAgABLgAECgMJBAANAAAAAA==.',
Ko='Korozzma:BAAALgADCgYJBgABLgADCgMJAwANAAAAAA==.',
Kr='Krzzy:BAAALgAFFAIJAgABLgAFFAcJCwAWAGESAA==.',
Ku='Kuray:BAAALgAECgEJAgAAAA==.',
Ky='Kynbrookera:BAABLgAECn8iAAIFAAkJFQy/RQB5AQAFAAkJFQy/RQB5AQAAAA==.Kyujin:BAAALgADCgEJAQAAAA==.',
['Kì']='Kìnky:BAAALgAECgcJEwAAAA==.',
La='Laetha:BAAALgADCgUJBQAAAA==.',
Le='Lemicall:BAAALgADCgQJCAAAAA==.Lethiferous:BAAALgAECgIJAgAAAA==.Letmespankit:BAAALgADCgYJDAAAAA==.Lezigo:BAABLgAECn8jAAIOAAkJaBQfSwD6AQAOAAkJaBQfSwD6AQAAAA==.',
Li='Licht:BAAALgAECgYJCwAAAA==.Lik:BAAALgAECgQJBwAAAA==.Lilhorror:BAAALgADCgMJAwAAAA==.Lilpyro:BAAALgAECgQJBAAAAA==.Lilyheart:BAAALgADCgYJBgAAAA==.Linai:BAABLgAECn8kAAMjAAkJuQ7+FgDkAQAjAAkJuQ7+FgDkAQAlAAgJEQggDwAyAQAAAA==.Lit:BAAALgAECgEJAwAAAA==.Littledog:BAACLgAFFH8KAAIKAAQJbRQKGQAfAQAKAAQJbRQKGQAfAQAuAAQKfy4AAwoACQnXFZocAOABAAoACQnXFZocAOABACAABAlyFq09AL8AAAAA.Liz:BAAALgADCgEJAQABLgAECgUJDQANAAAAAA==.',
Lo='Lockdout:BAAALgADCgEJAQABLgAECggJGQAOANkWAA==.Loky:BAACLgAFFH8HAAIMAAIJWht4jwClAAAMAAIJWht4jwClAAAuAAQKfyUABAwACQkCH8U8AOgBAAwACQncHsU8AOgBAB4ABAl+GMskADUBABgAAQl6ISowAF4AAAAA.Longshanks:BAAALgADCgUJDAAAAA==.Longshenks:BAAALgADCgUJBQAAAA==.Lorna:BAAALgADCgEJAQAAAA==.Lotten:BAAALgAECgUJDAAAAA==.',
Lu='Luckevin:BAAALgAECgYJDgAAAA==.Lumianir:BAAALgAECgEJAgAAAA==.Lunitari:BAAALgAECgYJEwAAAA==.Luthiean:BAAALgADCgQJBAAAAA==.Luthran:BAAALgAECgUJCwABLgAECggJGAAQAD8PAA==.',
Ly='Lynnali:BAAALgADCggJEQAAAA==.Lyrrin:BAAALgADCgYJBgAAAA==.',
Ma='Magedon:BAAALgAECgEJAQAAAA==.Mageyoulaugh:BAABLgAECn8ZAAIOAAgJ2RZjYAC/AQAOAAgJ2RZjYAC/AQAAAA==.Magezamb:BAAALgAECgUJDQAAAA==.Magicmann:BAAALgAECgEJAQAAAA==.Magmash:BAAALgADCggJDwAAAA==.Mahito:BAAALgADCgEJAQAAAA==.Mahru:BAAALgADCgYJCAAAAA==.Majhduul:BAAALgADCgMJAwAAAA==.Malafang:BAABLgAECn8XAAIIAAcJIAYPBQGyAAAIAAcJIAYPBQGyAAAAAA==.Malanah:BAABLgAECn8XAAIKAAcJ4w0mOgAqAQAKAAcJ4w0mOgAqAQAAAA==.Marandra:BAAALgAECgQJBwAAAA==.Marlie:BAAALgAECgMJAwAAAA==.Mathalios:BAAALgAECgIJAgAAAA==.Mattu:BAABLgAECn8WAAIhAAYJMgMVDgCDAAAhAAYJMgMVDgCDAAAAAA==.Maverick:BAACLgAFFH8VAAIjAAcJlxanCABiAQAjAAcJlxanCABiAQAuAAQKfxsAAyMABwlUIsIVAGECACMABwlNIsIVAGECACUABAmBIpcMAFgBAAAA.Maxbaba:BAAALgAECgEJAQAAAA==.',
Mc='Mcskittelz:BAAALgADCgQJBAAAAA==.',
Me='Meleshanorak:BAAALgADCgUJCgAAAA==.',
Mi='Michaella:BAAALgAECgUJCwAAAA==.Michartson:BAAALgADCgYJBAAAAA==.Mingres:BAABLgAECn8XAAIDAAcJQw9BegBLAQADAAcJQw9BegBLAQAAAA==.Miramanie:BAAALgADCgYJBgAAAA==.Misdiagnosed:BAAALgADCgIJAgAAAA==.Mistbrewer:BAAALgADCgIJAgAAAA==.',
Mk='Mk:BAEBLgAECn8UAAIXAAYJ8RY2BADaAAAXAAYJ8RY2BADaAAABLgAECgkJTQAmAIoiAA==.',
Mo='Mogar:BAABLgAECn8dAAIfAAcJLx89DAAjAgAfAAcJLx89DAAjAgAAAA==.Mogina:BAAALgADCggJCAAAAA==.Monkish:BAAALgADCgMJAwAAAA==.Monster:BAAALgAECgUJBQAAAA==.Moonzhine:BAABLgAECn8jAAIUAAkJXhWZFQC/AQAUAAkJXhWZFQC/AQAAAA==.Moosejaw:BAAALgAECgYJCwAAAA==.Mordread:BAAALgAECggJEgAAAA==.Morgalruk:BAAALgAFFAQJBAAAAA==.',
My='Myriosheal:BAAALgADCgQJBAAAAA==.Mythx:BAACLgAFFH8lAAQDAAgJTRsDAgCBAQADAAYJJh0DAgCBAQAEAAQJCQwwFwAYAQACAAIJRRR/KwBZAAAuAAQKfysABAMACAlXI3wIAAoDAAMACAlXI3wIAAoDAAQABgn7GLYrAEUBAAIABQkFEe5MAB0BAAAA.',
Na='Nalanelin:BAABLgAECn8WAAIJAAcJKQ0bmAA4AQAJAAcJKQ0bmAA4AQAAAA==.Narukin:BAABLgAECn8cAAIXAAcJVBr8RwCuAQAXAAcJVBr8RwCuAQAAAA==.Naturboy:BAAALgADCgYJBgAAAA==.',
Ne='Nemmessiss:BAAALgAECgEJAgAAAA==.Nessirebette:BAAALgADCgUJCAAAAA==.Netherwalker:BAAALgAECgIJAgABLgAFFAcJHgAKAGAaAA==.Netherward:BAAALgAFFAEJAQABLgAFFAcJHgAKAGAaAA==.',
Ni='Nivmizzet:BAABLgAECn8wAAMMAAgJ+BlzTwCsAQAMAAcJfBpzTwCsAQAeAAYJ8BUqLQAJAQAAAA==.',
No='Nolakai:BAAALgAECgEJAQAAAA==.Nomiro:BAAALgAECgYJDAAAAA==.Noradori:BAAALgAECgEJAQAAAA==.Notdip:BAAALgADCgIJAgAAAA==.Novalea:BAACLgAFFH8NAAIBAAQJ1yUXFwCtAQABAAQJ1yUXFwCtAQAuAAQKf00AAwEACQlhIw0FAGMDAAEACQlhIw0FAGMDABYABwkeHj4uAIkBAAAA.',
Nu='Nuru:BAAALgAECgcJEAAAAA==.Nutcutter:BAAALgAECgUJBQAAAA==.',
['Nø']='Nøstalgic:BAAALgAECgEJAgAAAA==.',
Ob='Obala:BAAALgADCgIJAgAAAA==.',
Od='Odogaren:BAABLgAECn8ZAAMiAAgJzxxbCwBYAgAiAAcJgB1bCwBYAgATAAgJhRoVIQBLAgAAAA==.',
Om='Omnithorn:BAAALgAECggJDQAAAA==.',
On='Onei:BAAALgADCgEJAQAAAA==.',
Or='Oramos:BAAALgAECgQJBgAAAA==.Orgóndó:BAABLgAFFH8NAAIUAAYJmR0vEACAAQAUAAYJmR0vEACAAQAAAA==.',
Ov='Ova:BAAALgAECgQJBQAAAA==.Ovelaa:BAAALgAECgQJBAAAAA==.',
Ox='Oxxo:BAABLgAECn8mAAInAAcJfQ/JDABEAQAnAAcJfQ/JDABEAQAAAA==.',
Pa='Palzamb:BAAALgADCgYJCwAAAA==.Pandacillin:BAAALgAECgQJBAAAAA==.Paraggonn:BAABLgAECn8yAAIDAAgJihi9MwANAgADAAgJihi9MwANAgAAAA==.',
Pe='Penelöpe:BAAALgAECgMJBAAAAA==.Penoosê:BAAALgADCgEJAgAAAA==.Perlonis:BAAALgAECgYJEwAAAA==.',
Ph='Phatocaster:BAAALgADCgIJBAAAAA==.Phoinyx:BAAALgAECgkJDwAAAA==.Phuriosa:BAAALgAECgcJDwABLgAFFAMJCQAFAO8VAA==.Phury:BAACLgAFFH8JAAIFAAMJ7xWgOQDHAAAFAAMJ7xWgOQDHAAAuAAQKfyQAAwUACQlSGosnABQCAAUACAkbGYsnABQCAAsAAgkmF9RgAJYAAAAA.Physinyx:BAAALgAECgkJCgAAAA==.Physta:BAAALgADCggJCwAAAA==.',
Pi='Pizza:BAABLgAECn8jAAIPAAcJTxjPFgCcAQAPAAcJTxjPFgCcAQAAAA==.',
Pl='Plagafel:BAAALgADCgYJBgAAAA==.',
Po='Pomomies:BAAALgAECgMJBAAAAA==.Pooseunpoose:BAAALgAFFAEJBAAAAA==.Porkmancer:BAAALgAECgYJCgABLgAECgkJJgAJAEwfAA==.Porkslope:BAABLgAECn8mAAIJAAgJTB+vJgBoAgAJAAgJTB+vJgBoAgAAAA==.',
Pr='Praahv:BAAALgADCgYJBgAAAA==.Profryktor:BAABLgAECn8ZAAIfAAYJIRWtJABBAQAfAAYJIRWtJABBAQAAAA==.',
Pu='Purebloods:BAAALgADCgEJAQAAAA==.Purpleparrot:BAAALgAECgYJCgAAAA==.',
Qu='Quickben:BAAALgAECgIJAgAAAA==.',
Ra='Raenyx:BAABLgAECn8/AAMMAAgJ3x5THgBvAgAMAAgJ3x5THgBvAgAYAAMJag4eLABrAAAAAA==.Raiflock:BAABLgAECn8aAAIYAAgJ4xOfCQDJAQAYAAgJ4xOfCQDJAQAAAA==.Ranalastus:BAAALgAECgUJDQAAAA==.Raveneyes:BAEBLgAECn8jAAIMAAkJjhFBRQDLAQAMAAkJjhFBRQDLAQAAAA==.',
Re='Reiena:BAAALgAECgcJEAAAAA==.Relas:BAAALgADCgUJBQAAAA==.Reylilyn:BAABLgAECn8oAAIcAAkJqBUWGwA/AgAcAAkJqBUWGwA/AgAAAA==.Reynarena:BAAALgAECgYJEAAAAA==.',
Rh='Rhaenfyre:BAABLgAECn8jAAMXAAkJMBVFOgDeAQAXAAkJMBVFOgDeAQAdAAEJ9QztOAAlAAAAAA==.',
Ri='Richardhurtz:BAAALgAECgYJCwAAAA==.Ricola:BAAALgAFFAIJBAAAAA==.Rivenel:BAACLgAFFH8TAAIeAAYJVRORAwCPAQAeAAYJVRORAwCPAQAuAAQKfykAAx4ACQkgIkMCAJ0CAB4ACAlaI0MCAJ0CAAwAAQmHGbQdAUoAAAAA.Rivèn:BAAALgADCgEJAQAAAA==.',
Ro='Robinvoid:BAABLgAECn8dAAMXAAkJgCAPFQDZAgAXAAkJgCAPFQDZAgAaAAEJ+RRiaQBAAAAAAA==.Rocksann:BAAALgAECgEJBAAAAA==.Rodel:BAAALgAECgEJAgABLgAECgMJAwANAAAAAA==.Roquan:BAABLgAECn8wAAIbAAgJ7RvhCAD8AQAbAAgJ7RvhCAD8AQAAAA==.Roulette:BAAALgAECgUJDwAAAA==.',
Ru='Rubmyrott:BAAALgAFFAQJBAAAAA==.Runalot:BAAALgAECgYJBgAAAA==.Runelle:BAAALgADCgQJBAAAAA==.',
['Ré']='Rébél:BAAALgADCgEJAQAAAA==.',
['Rê']='Rêdd:BAABLgAECn8bAAIKAAcJXxHALwBgAQAKAAcJXxHALwBgAQAAAA==.',
Sa='Sabeion:BAAALgAECgYJDAAAAA==.Saboo:BAAALgAECgQJAQABLgAECgcJCgANAAAAAA==.Sadiebuding:BAAALgAECgEJAQAAAA==.Salswarriah:BAABLgAECn8bAAITAAcJEhFZOQBhAQATAAcJEhFZOQBhAQAAAA==.Sanaku:BAAALgAECgYJCAAAAA==.Sanangra:BAAALgADCgEJAQAAAA==.Santo:BAAALgADCgMJAwAAAA==.Sarlyan:BAAALgADCgkJFwAAAA==.Sassafrazz:BAAALgAECgQJBAAAAA==.',
Sc='Scrumbles:BAAALgAECgkJDwAAAA==.',
Se='Secksytoes:BAAALgAECgMJAwABLgADCgYJCwANAAAAAA==.Seis:BAAALgAECgEJAQABLgAECgcJCgANAAAAAA==.Seraphim:BAAALgADCgEJAQAAAA==.Serion:BAAALgADCgMJAwAAAA==.Sewerrat:BAAALgADCggJCAAAAA==.',
Sg='Sgtbonesnap:BAAALgAECgcJDgAAAA==.Sgtpunchy:BAAALgADCgMJBQABLgAECgcJDgANAAAAAA==.',
Sh='Shadowslam:BAAALgAECgEJAQABLgAECgkJAQANAAAAAA==.Shakuro:BAAALgAECgEJAgAAAA==.Shallash:BAAALgAECgEJAQAAAA==.Shamageddon:BAAALgAECgIJBAAAAA==.Shamanizim:BAACLgAFFH8MAAMWAAUJshRvIQAXAQAWAAUJshRvIQAXAQAZAAEJfgSqHAA7AAAuAAQKfyoABBYACAmUHEIdAPcBABYACAkpHEIdAPcBABkABwnlFb8XAEwBAAEAAgknBmfQADsAAAAA.Shausin:BAAALgAECggJCAAAAA==.Sheeanna:BAAALgAFFAEJAQABLgAFFAQJDgAVADgjAA==.Shiftmyself:BAAALgADCgkJDgAAAA==.Shikigami:BAAALgAECgkJBwAAAA==.Shinoikari:BAACLgAFFH8IAAIbAAIJjQZtIQB+AAAbAAIJjQZtIQB+AAAuAAQKfygAAxsACQkNEcUKAM8BABsACQkNEcUKAM8BABQABQnJCJ9DAIAAAAAA.Shinotenshi:BAABLgAECn8bAAQgAAcJtwm+OQAqAQAgAAcJvAi+OQAqAQASAAUJBweMYgCmAAAKAAEJKAR1lQAlAAABLgAFFAIJCAAbAI0GAA==.Shirase:BAABLgAECn8eAAMMAAkJdw7VbQBgAQAMAAkJHgzVbQBgAQAYAAYJRQ4fGAADAQABLgAFFAQJDQABANclAA==.Shugarae:BAABLgAECn8cAAMLAAgJPQgUPgAXAQALAAgJPQgUPgAXAQAFAAUJcATdnwBwAAAAAA==.',
Si='Sionnocht:BAAALgADCgEJAQAAAA==.Sirlemage:BAAALgADCgMJAwAAAA==.',
Sk='Skina:BAAALgAECgEJAQAAAA==.Skreezy:BAAALgAECgcJDAAAAA==.Skuls:BAAALgAECgMJBwAAAA==.',
Sl='Slashemup:BAABLgAECn8jAAIaAAkJ+RYrEgAKAgAaAAkJ+RYrEgAKAgAAAA==.Slayter:BAABLgAECn8lAAIFAAkJ2R8zHQBdAgAFAAkJ2R8zHQBdAgAAAA==.',
Sm='Smaugin:BAAALgAECgIJAgAAAA==.',
Sn='Snakelazers:BAACLgAFFH8HAAIcAAQJgiEsHgB+AQAcAAQJgiEsHgB+AQAuAAQKfyUAAhwACQn6IrUEAGMDABwACQn6IrUEAGMDAAAA.Snufulafagus:BAABLgAECn8WAAIQAAUJbRtlGgA6AQAQAAUJbRtlGgA6AQAAAA==.',
So='Soju:BAABLgAECn8oAAMBAAkJ9BdiGwBwAgABAAkJ9BdiGwBwAgAWAAQJJxKVbQCgAAABLgAECgkJLAADAMkjAA==.Soliloquy:BAAALgAECggJDQAAAA==.Songwind:BAABLgAECn8qAAImAAgJYg3QLQBUAQAmAAgJYg3QLQBUAQAAAA==.Soonie:BAAALgADCgEJAQAAAA==.Soulreever:BAAALgADCggJCAAAAA==.',
Sq='Squishyman:BAAALgAECgEJAgABLgAECgkJHAAIACkeAA==.Squishypal:BAABLgAECn8cAAMIAAkJKR6PFQDBAgAIAAkJKR6PFQDBAgAoAAEJ6xYjPwBBAAAAAA==.',
St='Starfirelmao:BAAALgAECgYJDwAAAA==.Steelcure:BAAALgAECggJCgAAAA==.Strabo:BAAALgADCggJCQAAAA==.Strawdicks:BAAALgAECgcJAQAAAA==.',
Su='Sugma:BAAALgAECgEJAQAAAA==.Suzsette:BAABLgAECn8eAAIKAAcJNglGQgAGAQAKAAcJNglGQgAGAQAAAA==.',
Sy='Sylris:BAAALgADCgkJFgAAAA==.Sylvanthis:BAAALgAECgQJBAABLgAECgkJIgAFABUMAA==.',
['Sç']='Sçoxx:BAAALgADCgEJAQAAAA==.',
Ta='Taazdingo:BAAALgADCgEJAQAAAA==.Taeleth:BAAALgADCgcJBwAAAA==.Talnora:BAAALgAECgYJDwAAAA==.Tardovski:BAABLgAECn8lAAMDAAkJGSEvEADPAgADAAkJGSEvEADPAgACAAQJ2BP2VgDsAAAAAA==.Taurentino:BAAALgAECgkJBQAAAA==.',
Te='Telaris:BAAALgADCgIJAgAAAA==.Telda:BAABLgAECn8WAAIlAAYJZwS4FwC4AAAlAAYJZwS4FwC4AAAAAA==.Teneturadvós:BAAALgAECgcJCQABLgAECgcJDgANAAAAAA==.Tentreeadvos:BAAALgAECgEJAQABLgAECgcJDgANAAAAAA==.Tetris:BAACLgAFFH8VAAIOAAUJ3hxgCAAoAQAOAAUJ3hxgCAAoAQAuAAQKfzgAAg4ACQmgIl0WANMCAA4ACQmgIl0WANMCAAAA.',
Th='Thellaria:BAAALgADCgQJBAAAAA==.Thraggoar:BAAALgADCgEJAQAAAA==.Thunsar:BAAALgAECgkJDwAAAA==.Thuzzad:BAAALgADCgUJBQAAAA==.',
Ti='Tickler:BAAALgAECgUJEQAAAA==.Tiroelin:BAAALgAECgUJBwAAAA==.',
To='Toetem:BAAALgADCgQJBgAAAA==.Tosselus:BAAALgAECgEJAQAAAA==.Tox:BAAALgADCgUJBQAAAA==.Toyotama:BAAALgAFFAIJAgABLgAFFAUJGgAFAPkkAA==.',
Tr='Tragedeigh:BAAALgAECgUJBQABLgAECgkJJQAGADgaAA==.Trane:BAAALgAECgIJAgAAAA==.Tritoch:BAAALgAECgYJEAAAAA==.Troche:BAACLgAFFH8IAAIoAAQJEQh9DACwAAAoAAQJEQh9DACwAAAuAAQKfxgAAygACQmDESIQAMIBACgACQmDESIQAMIBABUAAQlNCEKYACgAAAAA.Truthfully:BAABLgAECn8WAAIIAAkJPw7jAgBfAQAIAAkJPw7jAgBfAQAAAA==.Trávpac:BAAALgADCgEJAQAAAA==.',
Tt='Ttjpll:BAAALgAFFAEJAQAAAA==.',
Tu='Tubs:BAAALgAECgEJAQAAAA==.Tuckncloak:BAAALgAECgMJAwAAAA==.',
Tw='Twohand:BAAALgADCgIJBAAAAA==.',
['Tî']='Tîmon:BAAALgAFFAIJAgAAAA==.',
Ug='Ugrup:BAAALgAECgYJDwAAAA==.',
Uj='Ujabula:BAAALgAECgYJEgAAAA==.',
Ul='Ulurak:BAABLgAECn8YAAMQAAgJPw8aGwAaAQAQAAYJkwkaGwAaAQAFAAQJ9QqhpgBlAAAAAA==.',
Un='Uncleskip:BAABLgAECn8bAAIfAAcJ0wd0FgBJAQAfAAcJ0wd0FgBJAQAAAA==.Unhappytoast:BAABLgAECn8WAAIoAAkJdBgpCgAoAgAoAAkJdBgpCgAoAgAAAA==.Unstobubble:BAAALgAECgYJCQAAAA==.',
Va='Valeriya:BAAALgADCgcJCAABLgAECgMJAwANAAAAAA==.Valisanna:BAAALgADCggJDQAAAA==.Vallorien:BAABLgAECn8eAAIoAAcJyh8GCwAZAgAoAAcJyh8GCwAZAgAAAA==.Valsharess:BAAALgADCgcJBwABLgAECgkJOAAXAEEaAA==.',
Ve='Vegtam:BAAALgAECgEJAQAAAA==.Velaryn:BAAALgAFFAIJAgAAAA==.Velnia:BAAALgAECgYJCwAAAA==.Verencia:BAAALgAECgEJAQAAAA==.',
Vi='Vildaren:BAAALgAECgUJCQAAAA==.Vivachel:BAAALgADCgcJCAAAAA==.Viztrix:BAAALgADCgEJAQAAAA==.',
Vo='Vorsan:BAAALgADCgcJBwAAAA==.Vorsane:BAAALgADCgQJBAAAAA==.',
['Và']='Vàli:BAAALgAECgQJCQAAAA==.',
Wa='Wanks:BAAALgAECgYJDwAAAA==.Warmoon:BAAALgAECgMJAwAAAA==.Warskul:BAAALgAECgEJAQAAAA==.Wasenshi:BAAALgADCgUJBQAAAA==.',
We='Weeb:BAAALgADCgUJCwAAAA==.Weeny:BAAALgAECgcJCwAAAA==.',
Wh='Wholy:BAAALgAECgMJBgAAAA==.',
Wi='Wickedromeo:BAAALgAECgMJAwAAAA==.',
Wo='Wolfmother:BAABLgAECn8jAAIWAAgJpxS1KgCdAQAWAAgJpxS1KgCdAQAAAA==.',
Xa='Xaanii:BAABLgAECn8bAAIVAAYJUB1eIwDqAQAVAAYJUB1eIwDqAQAAAA==.Xandius:BAAALgADCgcJDAAAAA==.Xarferrin:BAABLgAECn8mAAIOAAcJQQMF6wDLAAAOAAcJQQMF6wDLAAAAAA==.',
Xe='Xeeria:BAACLgAFFH8iAAIBAAYJYhTKLQArAQABAAYJYhTKLQArAQAuAAQKfzAAAwEACQnyHwoNALUCAAEACQnyHwoNALUCABYAAQlXG8aSAE4AAAAA.Xenzull:BAAALgAECgIJAgAAAA==.',
Xk='Xkaliber:BAAALgADCgEJAQAAAA==.',
Xu='Xuecat:BAABLgAECn8kAAIFAAgJ3xYQLgD1AQAFAAgJ3xYQLgD1AQAAAA==.',
Yn='Yn:BAAALgAECgYJDAAAAA==.',
Za='Zamzak:BAAALgADCgQJBAABLgAECgEJAQANAAAAAA==.Zanthor:BAABLgAECn8WAAIJAAUJbgi19wC3AAAJAAUJbgi19wC3AAAAAA==.Zaralina:BAACLgAFFH8HAAIKAAQJkQhvIQDoAAAKAAQJkQhvIQDoAAAuAAQKfzQAAgoACQlPF3MSAEACAAoACQlPF3MSAEACAAAA.Zartox:BAABLgAECn8cAAIpAAkJoRa3AgAaAgApAAkJoRa3AgAaAgAAAA==.Zaryn:BAAALgADCgIJAgAAAA==.Zarynth:BAAALgAECgEJAQAAAA==.Zaryssa:BAABLgAECn8eAAIWAAgJjwUQUwDtAAAWAAgJjwUQUwDtAAAAAA==.Zavinus:BAAALgADCgYJCAAAAA==.',
Ze='Zenzug:BAAALgAECgUJDwAAAA==.Zephystra:BAAALgADCgQJBAABLgAFFAQJDQABANclAA==.Zeusqt:BAAALgADCgYJBgAAAA==.',
Zh='Zharfrost:BAAALgAECgYJCAAAAA==.',
Zi='Zicroniah:BAAALgADCgYJCgAAAA==.Zimfestation:BAAALgAFFAMJAwABLgAFFAUJDAAWALIUAA==.Ziyuu:BAAALgADCgUJBQAAAA==.',
Zo='Zombiehunter:BAABLgAECn8jAAIDAAkJaR8AEgDCAgADAAkJaR8AEgDCAgAAAA==.',
Zu='Zuzu:BAAALgADCgMJAwAAAA==.',
['Âr']='Ârc:BAAALgAECgEJAgAAAA==.',
['Èd']='Èddy:BAACLgAFFH8GAAIFAAMJTQmOSwCOAAAFAAMJTQmOSwCOAAAuAAQKfx0AAgUACQk0FugcAF8CAAUACQk0FugcAF8CAAAA.',
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
