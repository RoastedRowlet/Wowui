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

local lookup = {'Shaman-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Druid-Restoration','Evoker-Preservation','Evoker-Devastation','Paladin-Retribution','DeathKnight-Unholy','Priest-Shadow','Druid-Balance','Warlock-Demonology','Mage-Frost','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Priest-Holy','Warrior-Fury','DeathKnight-Blood','Paladin-Holy','Unknown-Unknown','Shaman-Elemental','DemonHunter-Devourer','Warlock-Affliction','Shaman-Enhancement','DemonHunter-Havoc','DeathKnight-Frost','Monk-Mistweaver','DemonHunter-Vengeance','Warlock-Destruction','Warrior-Arms','Priest-Discipline','Mage-Fire','Warrior-Protection','Rogue-Subtlety','Monk-Brewmaster','Rogue-Assassination','Rogue-Outlaw','Monk-Windwalker','Paladin-Protection','Mage-Arcane',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=46,date='2026-06-28',data={Aa='Aardnon:BAAALgADCgEJAQAAAA==.',
Ad='Addisyn:BAAALgAECgEJBAAAAA==.',
Ae='Aekal:BAAALgAECgUJBQAAAA==.Aemetris:BAABLgAECn8ZAAIBAAcJMxf1NADeAQABAAcJMxf1NADeAQAAAA==.Aenicus:BAAALgADCgcJBwAAAA==.Aerina:BAAALgAECgQJCwAAAA==.Aethra:BAAALgADCgYJBgAAAA==.',
Ag='Agamotto:BAAALgAECgYJCgAAAA==.Agromagnetic:BAAALgAECgcJDQAAAA==.Agytha:BAAALgAECgMJAwAAAA==.Agøny:BAAALgADCgMJAwAAAA==.',
Ah='Ahskul:BAAALgADCgEJAQAAAA==.',
Ai='Aidendawn:BAAALgAECgYJEQAAAA==.',
Aj='Ajheria:BAAALgAECgEJAQAAAA==.',
Al='Alejandro:BAAALgADCgIJAQAAAA==.',
Am='Ameildoran:BAAALgADCgkJCQAAAA==.Amelicea:BAAALgADCgMJAwAAAA==.',
An='Anaire:BAAALgAECgEJAQAAAA==.Anaru:BAAALgAECgMJBgAAAA==.Anatyriel:BAAALgADCgEJAQAAAA==.Anayanci:BAAALgADCgUJBgAAAA==.Andalaine:BAAALgAECgMJBQAAAA==.Andari:BAAALgADCgEJAQAAAA==.Andramaedra:BAAALgAECgkJAgAAAA==.Anoobornot:BAAALgADCgMJAwAAAA==.Anraleth:BAACLgAFFH8SAAICAAQJ9iMgDACgAQACAAQJ9iMgDACgAQAuAAQKfzwAAwIACQkLJQgDAKwCAAIACAnnJAgDAKwCAAMAAQkGJqP6AGUAAAAA.',
Ap='Aponi:BAAALgAECgUJCAAAAA==.',
Ar='Arckillion:BAAALgAECgQJBAAAAA==.Ardour:BAAALgAECgMJBgABLgAECgcJGwAEABANAA==.Arduous:BAAALgAECgMJAwAAAA==.Arihu:BAABLgAECn8fAAIFAAkJlxT7LgDoAQAFAAkJlxT7LgDoAQAAAA==.Arkhana:BAAALgADCgEJAQAAAA==.Arrawm:BAAALgAECgEJAQAAAA==.',
As='Ashenaya:BAABLgAECn8YAAMGAAgJLxlbDAAQAgAGAAgJLxlbDAAQAgAHAAEJMQpQQgArAAAAAA==.Asparagus:BAABLgAECn8aAAIIAAkJVw59YwCpAQAIAAkJVw59YwCpAQAAAA==.',
At='Atlass:BAACLgAFFH8GAAIJAAIJLhXh0gCOAAAJAAIJLhXh0gCOAAAuAAQKfxgAAgkABwnxGYtjAMkBAAkABwnxGYtjAMkBAAAA.Atrest:BAAALgAECgYJBwAAAA==.',
Au='Augmenter:BAAALgAECgQJBQABLgAFFAkJJQAKAOYWAA==.Aust:BAABLgAECn8UAAIIAAgJ6hMCbACWAQAIAAgJ6hMCbACWAQAAAA==.',
Av='Averlin:BAAALgAECgUJCAAAAA==.Averlis:BAABLgAECn8mAAILAAkJSRiWAgBhAQALAAkJSRiWAgBhAQAAAA==.Avoiddance:BAAALgADCgEJAQAAAA==.',
Ax='Axee:BAAALgADCgYJBgAAAA==.',
Az='Azima:BAAALgAECgMJAwAAAA==.Azura:BAAALgADCgIJAgAAAA==.Azurargentyr:BAAALgAECgkJEAAAAA==.',
Ba='Babeolicious:BAAALgADCgEJAQAAAA==.Bacon:BAABLgAECn8lAAIIAAkJzAp1hgBjAQAIAAkJzAp1hgBjAQAAAA==.Bambøøze:BAAALgADCgEJAQAAAA==.Bandadi:BAECLgAFFH8IAAIMAAYJwhWeKwCXAQAMAAYJwhWeKwCXAQAuAAQKfzEAAgwACAkzIG0VANUCAAwACAkzIG0VANUCAAEuAAUUBgkGAA0AhwkA.Barbelo:BAAALgAECgcJCgAAAA==.Barely:BAAALgAECgkJEQAAAA==.Barkweldort:BAAALgAECgYJEQAAAA==.Barreled:BAAALgADCgMJAwAAAA==.Batistabomba:BAAALgAECgYJBgAAAA==.',
Be='Beargruk:BAAALgAECgUJBwAAAA==.Beastly:BAAALgAECggJEQAAAA==.Beeble:BAABLgAECn8XAAINAAYJvwmF0ADxAAANAAYJvwmF0ADxAAAAAA==.Belii:BAAALgAECgYJDAAAAA==.Bended:BAAALgADCgIJAgAAAA==.Bepisthepall:BAAALgAECgEJAgAAAA==.Betterkevin:BAAALgAECgQJDwAAAA==.Bezerkachew:BAAALgAECgEJAgAAAA==.',
Bi='Bigbootijudi:BAAALgAECgEJAQAAAA==.Bigbooty:BAABLgAECn8nAAMOAAgJPAnGBADTAAAOAAgJNQnGBADTAAAPAAUJIAe/NwB8AAAAAA==.',
Bl='Blikey:BAABLgAFFH8GAAIJAAIJfia0vQCuAAAJAAIJfia0vQCuAAAAAA==.Bloodyrott:BAAALgAECgUJCgAAAA==.Bluedrake:BAACLgAFFH8NAAMHAAQJ1BtUAwBEAQAHAAQJ1BtUAwBEAQAQAAEJPROlZABAAAAuAAQKfyMAAwcACAlfHr4EALoCAAcACAmGHb4EALoCABAACAk9FlIZAAMCAAEuAAUUBgkUAAsAAh8A.Blueparrot:BAABLgAECn84AAIRAAgJXxXjGwDoAQARAAgJXxXjGwDoAQAAAA==.Bluy:BAAALgADCgMJAwAAAA==.Blädèstorm:BAABLgAECn8ZAAISAAgJphwOJADUAQASAAgJphwOJADUAQAAAA==.',
Bo='Bonesnap:BAACLgAFFH8VAAMJAAcJeR5yHAAHAgAJAAYJeR5yHAAHAgATAAEJAAA/VQAAAAAuAAQKfyAAAwkACQmrIaMXAO4CAAkACQmrIaMXAO4CABMABAmuE2A+AJYAAAAA.Bowkatan:BAAALgAECgEJAgAAAA==.',
Br='Brianisita:BAAALgAECgUJBgAAAA==.Brightmane:BAABLgAECn8WAAIUAAYJUx4zJQD8AQAUAAYJUx4zJQD8AQAAAA==.Bringinlight:BAABLgAECn8YAAIRAAYJJwzTBwCEAAARAAYJJwzTBwCEAAAAAA==.',
Bu='Bubbleicious:BAAALgAECgYJEgAAAA==.Bubbletea:BAABLgAECn8YAAIIAAgJLhb5SQDoAQAIAAgJLhb5SQDoAQABLgAECgkJLAADAMkjAA==.Bulletz:BAABLgAECn8eAAICAAgJ7x0LBQBbAgACAAgJ7x0LBQBbAgAAAA==.Bumpersnouts:BAAALgADCgkJCQAAAA==.Buttfur:BAAALgADCgYJBgAAAA==.',
['Bê']='Bêarwithme:BAAALgAECgIJBgABLgAECgcJHAAKAF8RAA==.',
Ca='Caenzo:BAAALgADCgkJCgAAAA==.Casanna:BAAALgADCgYJBgAAAA==.Cassandria:BAABLgAECn8sAAMFAAgJBxDRVAA8AQAFAAcJqw7RVAA8AQALAAgJ2Az+OgAmAQAAAA==.Cassiradra:BAAALgAECgEJAQAAAA==.Caylastus:BAAALgAECgEJAwAAAA==.',
Ce='Cearas:BAAALgAECgEJAQAAAA==.Cedrick:BAAALgAECgUJBQAAAA==.Celiona:BAAALgAECgkJBwAAAA==.Celody:BAAALgAECgYJDAAAAA==.Celticsinsix:BAAALgAECgMJBQAAAA==.Cervixticklr:BAAALgAECgUJBgAAAA==.',
Ch='Chaoten:BAAALgADCgEJAQAAAA==.Chathlia:BAAALgAECgQJBAAAAA==.Chavdar:BAAALgADCgEJAQAAAA==.Chewster:BAABLgAECn82AAINAAgJ5xBzdgCMAQANAAgJ5xBzdgCMAQAAAA==.Chixie:BAAALgADCgEJAQAAAA==.Choal:BAABLgAECn8WAAIFAAYJyBCkYQAQAQAFAAYJyBCkYQAQAQAAAA==.Choglana:BAAALgAECgcJCQAAAA==.Chogli:BAAALgAECgEJAQABLgAECgcJCQAVAAAAAA==.Chogric:BAABLgAECn85AAMUAAkJhh+NBQATAwAUAAkJhh+NBQATAwAIAAQJZw2MKAGJAAABLgAECgcJCQAVAAAAAA==.',
Ci='Civetta:BAABLgAECn8WAAIDAAkJhwznUQCtAQADAAkJhwznUQCtAQAAAA==.',
Cl='Clannininick:BAAALgADCgUJBgAAAA==.Clark:BAAALgADCgEJAQAAAA==.',
Co='Cogswell:BAAALgADCgIJAgAAAA==.Comespankit:BAAALgAECgUJBQAAAA==.Constiua:BAAALgAECgcJDwABLgAECgcJCQAVAAAAAA==.Convalesor:BAABLgAECn8UAAIKAAYJQQibTwDSAAAKAAYJQQibTwDSAAAAAA==.',
Cr='Crazzywazzy:BAABLgAFFH8KAAIJAAQJcBhtbAAjAQAJAAQJcBhtbAAjAQAAAA==.Crep:BAAALgAECgEJAQABLgAFFAEJAQAVAAAAAA==.Crona:BAABLgAECn8aAAIUAAkJtg4LPACJAQAUAAkJtg4LPACJAQAAAA==.Crsteel:BAAALgAECgEJAQAAAA==.Crzyblnkrton:BAACLgAFFH8PAAINAAYJthAGRgBaAQANAAYJthAGRgBaAQAuAAQKfxcAAg0ACAnmH2k5AJACAA0ACAnmH2k5AJACAAAA.Crzzy:BAABLgAFFH8NAAIWAAgJxxUoEACsAQAWAAgJxxUoEACsAQAAAA==.',
Cu='Cuddlez:BAABLgAECn8gAAIRAAkJGQtXLQBiAQARAAkJGQtXLQBiAQAAAA==.Cultera:BAACLgAFFH8TAAIXAAQJuxJXSAAPAQAXAAQJuxJXSAAPAQAuAAQKfx8AAhcACAlUIA4CAMsBABcACAlUIA4CAMsBAAAA.',
Cy='Cyhyraethia:BAABLgAECn8fAAIYAAgJDB+sBQANAgAYAAgJDB+sBQANAgABLgAECgkJOAAXAEEaAA==.Cyndera:BAAALgADCgEJAQAAAA==.',
Da='Dagden:BAAALgADCgYJCAAAAA==.Dalaa:BAAALgAECgIJAgAAAA==.Dammnation:BAAALgAFFAEJAQABLgAECgcJHAAKAF8RAA==.Danda:BAAALgAECgYJCgAAAA==.Daricepicker:BAABLgAECn8sAAIDAAkJySNPBQA3AwADAAkJySNPBQA3AwAAAA==.Darkyn:BAABLgAECn8ZAAIMAAkJPRCzRwDDAQAMAAkJPRCzRwDDAQAAAA==.Davedadude:BAABLgAECn8wAAIIAAkJEyI1DAADAwAIAAkJEyI1DAADAwAAAA==.',
Dd='Ddeonu:BAAALgAECgEJAQAAAA==.Ddeonuu:BAABLgAFFH8MAAMDAAYJCw2kJwBoAQADAAYJAwukJwBoAQACAAQJ2gxnGAD1AAAAAA==.',
De='Deadlysins:BAABLgAECn8WAAIJAAgJ8wvpbACwAQAJAAgJ8wvpbACwAQAAAA==.Deadscar:BAECLgAFFH8OAAIZAAQJ+SOAAwCcAQAZAAQJ+SOAAwCcAQAuAAQKfzQAAhkACQlSJq0AAFwDABkACQlSJq0AAFwDAAAA.Deathmasterj:BAAALgADCggJDgAAAA==.Deaths:BAABLgAECn8eAAMaAAgJTRJaHACaAQAaAAgJTRJaHACaAQAXAAEJJQRLOAEdAAAAAA==.Dedfrosty:BAABLgAECn8mAAMbAAgJ/hDDEQBcAQAbAAgJIg3DEQBcAQATAAgJQw4uJgAiAQAAAA==.Demomcgee:BAAALgADCgEJAgABLgAECgYJDwAVAAAAAA==.Demonio:BAAALgAECgEJAQAAAA==.Demonpimp:BAAALgAECgYJEAAAAA==.Dermon:BAAALgAECggJCwABLgAFFAQJCAAcAIIhAA==.Deviously:BAAALgADCgQJBAABLgAECgkJHgACAO8dAA==.Dewyhuey:BAAALgADCgIJAgAAAA==.',
Dh='Dhoong:BAAALgAECgIJAgAAAA==.',
Di='Dilaudid:BAAALgAECgEJAQAAAA==.Dimpiana:BAAALgAECgQJBAAAAA==.Disciplea:BAAALgAECgQJBAAAAA==.Dithariaa:BAABLgAECn8oAAIdAAcJWA7yEgAiAQAdAAcJWA7yEgAiAQAAAA==.',
Do='Docryktor:BAABLgAECn8/AAIZAAkJ+hoMCgAaAgAZAAkJ+hoMCgAaAgAAAA==.Doomgears:BAABLgAECn8gAAIeAAYJsRfjDgBQAQAeAAYJsRfjDgBQAQAAAA==.Dotsdead:BAAALgADCgYJDgAAAA==.Dotöri:BAAALgAECggJDwAAAA==.',
Dr='Drachuntress:BAAALgADCgIJAgAAAA==.Draculä:BAAALgAECgQJBAAAAA==.Dragonair:BAABLgAECn8bAAMGAAcJ8QMjJADNAAAGAAcJ8QMjJADNAAAHAAcJ7ALdFwCcAAAAAA==.Drashta:BAAALgAECgEJAQAAAA==.Drhoe:BAAALgAECgEJAQAAAA==.Drhurtouch:BAABLgAECn8kAAIfAAkJCx2IBQCxAgAfAAkJCx2IBQCxAgAAAA==.Dro:BAAALgAECgUJCwAAAA==.Drogas:BAAALgAECgYJCQABLgAECggJIwAWAKcUAA==.Drtybear:BAABLgAECn8kAAMOAAkJ3BSHIwA0AQAOAAcJbhKHIwA0AQAPAAUJ5hNvIQD9AAAAAA==.Druithh:BAAALgAFFAEJAQABLgAFFAYJFQANAGsYAA==.Drulissa:BAACLgAFFH8OAAIUAAQJOCMQFQCBAQAUAAQJOCMQFQCBAQAuAAQKfxkAAhQACQl1GZktAM0BABQACQl1GZktAM0BAAAA.Druu:BAAALgADCgMJAwABLgAFFAYJFQANAGsYAA==.',
Du='Duh:BAAALgAECgEJAQAAAA==.Duogear:BAAALgADCgEJAQAAAA==.Dusters:BAAALgADCgcJCwAAAA==.',
['Dâ']='Dârrius:BAAALgAECggJDgAAAA==.',
Eb='Ebonwings:BAAALgAECgcJDgAAAA==.',
Ed='Ediana:BAACLgAFFH8FAAINAAMJxAKqlACpAAANAAMJxAKqlACpAAAuAAQKfycAAg0ACQnqCRd4AIkBAA0ACQnqCRd4AIkBAAAA.',
El='Elandrah:BAAALgAECgkJEwAAAA==.Eld:BAAALgAECgEJAQAAAA==.Elmô:BAABLgAECn83AAIUAAgJHiG7CgDgAgAUAAgJHiG7CgDgAgAAAA==.Elody:BAAALgADCgYJBgAAAA==.Elvara:BAAALgAECgUJDQAAAA==.',
Eq='Equipwooman:BAAALgADCgIJAgAAAA==.',
Es='Estameling:BAABLgAECn8qAAIOAAgJyhZpGACNAQAOAAgJyhZpGACNAQAAAA==.',
Ex='Exash:BAACLgAFFH8NAAIWAAQJwRrTHAA1AQAWAAQJwRrTHAA1AQAuAAQKfycAAhYACQk7ITUJAP8CABYACQk7ITUJAP8CAAAA.Excizion:BAACLgAFFH8FAAIJAAIJpQOY8gB5AAAJAAIJpQOY8gB5AAAuAAQKfyUAAgkACQnzCzVgAKkBAAkACQnzCzVgAKkBAAAA.',
Fa='Faelynne:BAAALgADCgUJBQAAAA==.Fari:BAAALgAECgcJDAAAAA==.Fathertim:BAABLgAECn8oAAMgAAcJsRvaGAAMAgAgAAcJsRvaGAAMAgAKAAEJHw51EQA0AAAAAA==.',
Fe='Feannara:BAAALgAECgYJCQAAAA==.Felar:BAAALgADCgEJAQAAAA==.Feldrena:BAAALgADCgcJDAAAAA==.',
Fl='Flangus:BAAALgADCgMJBAAAAA==.Flappydragon:BAAALgADCgIJAgAAAA==.Floraria:BAAALgADCgYJBgAAAA==.',
Fr='Frosticulz:BAAALgAECgUJBQAAAA==.Frostii:BAABLgAECn8bAAINAAkJoBpzZwCuAQANAAkJoBpzZwCuAQAAAA==.',
Fu='Fudestamp:BAAALgADCgQJBQAAAA==.Fufight:BAAALgAECgIJBQABLgAFFAQJCAAcAIIhAA==.Fugryktor:BAABLgAECn88AAIYAAgJThamAADEAQAYAAgJThamAADEAQAAAA==.',
Fy='Fyrebug:BAABLgAECn8dAAIBAAYJ2QyWbQATAQABAAYJ2QyWbQATAQAAAA==.',
Ga='Galandor:BAABLgAECn8eAAIUAAcJYBsgGwArAgAUAAcJYBsgGwArAgAAAA==.Gandaalf:BAABLgAECn8WAAMhAAcJCR7XAQBrAgAhAAcJCR7XAQBrAgANAAIJ4Q9RRgFzAAAAAA==.Garrinda:BAAALgAECgkJDgAAAA==.Gaya:BAAALgAECgYJBgAAAA==.',
Ge='Geeked:BAAALgADCgUJBQAAAA==.Gemhide:BAABLgAECn8jAAIeAAkJzxKfCADCAQAeAAkJzxKfCADCAQAAAA==.Georgharison:BAAALgAECgEJAQAAAA==.Geroy:BAAALgAECgEJAQAAAA==.',
Gg='Ggwp:BAAALgAECgEJAQAAAA==.',
Gh='Ghae:BAAALgAECgUJBAAAAA==.Ghostsaber:BAAALgADCgEJAQABLgAECggJGQAiAM8cAA==.',
Gi='Gigglyguff:BAABLgAECn8YAAIFAAgJRiAgEgC9AgAFAAgJRiAgEgC9AgAAAA==.Gimly:BAAALgAECgEJAQAAAA==.Gityadruid:BAAALgAECgEJAQABLgAECgYJGAARACcMAA==.Gityahunter:BAAALgAECgQJBgABLgAECgYJGAARACcMAA==.',
Gl='Glavenus:BAAALgADCgEJAQAAAA==.',
Go='Gobank:BAAALgADCgIJAgAAAA==.Gobanks:BAABLgAECn87AAIIAAkJXCCNEwDNAgAIAAkJXCCNEwDNAgAAAA==.',
Gr='Graycat:BAAALgADCgIJAgABLgAFFAgJGgAEAMsjAA==.Grayele:BAAALgAECgIJAgAAAA==.Grayson:BAABLgAECn8bAAIIAAcJMwWD9QDEAAAIAAcJMwWD9QDEAAAAAA==.Graysurv:BAACLgAFFH8aAAIEAAgJyyMEAACBAgAEAAgJyyMEAACBAgAuAAQKfykAAgQACQn6JgUAABQEAAQACQn6JgUAABQEAAAA.Gregmiller:BAAALgADCgYJBgAAAA==.Grizzly:BAAALgADCgYJCwAAAA==.Gromlin:BAAALgAECgUJDAAAAA==.Grothfen:BAAALgAECgYJDQAAAA==.',
['Gä']='Gäreth:BAAALgADCgYJCwAAAA==.',
Ha='Habachi:BAAALgADCgEJAQAAAA==.Halcrenian:BAAALgAECgIJAgAAAA==.Hamelot:BAAALgADCgMJBAAAAA==.Hamremmi:BAAALgAECgEJAQABLgAFFAkJJQAKAOYWAA==.Handrider:BAAALgAECgEJAQAAAA==.Haruharu:BAAALgAECgUJCQABLgAECgkJJQAFANkfAA==.Hasalia:BAAALgAECggJCAABLgAFFAQJDgAUADgjAA==.',
He='Healsforu:BAAALgAECgYJDgABLgAECgcJDgAVAAAAAA==.Helly:BAAALgAECgEJAQAAAA==.Hemidall:BAAALgADCgMJAwAAAA==.Herbievore:BAABLgAECn8UAAMOAAgJORgtJQApAQAOAAUJ8RotJQApAQALAAYJAhHcVAC8AAAAAA==.Heunno:BAAALgADCgYJBgABLgAFFAEJAQAVAAAAAA==.',
Hi='Hiemy:BAAALgAECgYJBgAAAA==.Hif:BAACLgAFFH8IAAIFAAQJAh3iIABRAQAFAAQJAh3iIABRAQAuAAQKfyMAAgUACQn2I7QFADEDAAUACQn2I7QFADEDAAAA.Highbrittz:BAAALgAECgYJDgAAAA==.',
Hm='Hmmisee:BAAALgAECgEJAwAAAA==.',
Ho='Hoakaren:BAABLgAECn8ZAAIXAAkJAxZ5MAAEAgAXAAkJAxZ5MAAEAgAAAA==.Hobiscuits:BAEALgADCgQJBAABLgAECgYJIQAMAGwiAA==.Hocus:BAAALgADCgYJBgAAAA==.Holde:BAAALgAECgUJDQAAAA==.Hornyrott:BAAALgAECgQJBgAAAA==.',
Hu='Hunterzamb:BAAALgAECgEJAQAAAA==.Huntinator:BAABLgAECn8VAAIDAAcJHhtwMADvAQADAAcJHhtwMADvAQAAAA==.',
Hy='Hydrobubble:BAAALgAECgYJCwAAAA==.',
['Há']='Hátfield:BAAALgADCgEJAQAAAA==.',
Ih='Ihyo:BAAALgAECgEJAQAAAA==.',
Il='Illyy:BAABLgAECn8mAAIRAAgJMgvgNgAkAQARAAgJMgvgNgAkAQAAAA==.',
Im='Impkingguy:BAAALgADCgYJBgAAAA==.',
In='Indawhole:BAACLgAFFH8eAAIXAAgJABi3FwD0AQAXAAgJABi3FwD0AQAuAAQKfxoAAhcACAl8JfcjAEACABcACAl8JfcjAEACAAAA.Instakill:BAAALgADCgIJAgAAAA==.',
Ir='Iridori:BAABLgAECn8wAAIRAAgJuCB+CwCvAgARAAgJuCB+CwCvAgAAAA==.Irönfist:BAAALgADCgkJEgAAAA==.',
It='Itzzender:BAAALgADCgIJAgAAAA==.',
Iz='Izumiwitabow:BAABLgAECn8cAAIDAAcJvxI2ZwB1AQADAAcJvxI2ZwB1AQAAAA==.',
Ja='Jabberthehut:BAAALgAFFAEJAQAAAA==.Jamerius:BAAALgAECgIJAgAAAA==.Jankovic:BAAALgADCgcJBwAAAA==.Jasmean:BAAALgADCgcJCwAAAA==.Javaluminous:BAABLgAECn8oAAIIAAgJQCBfLABQAgAIAAgJQCBfLABQAgAAAA==.Jay:BAABLgAFFH8GAAIQAAMJjxDyQwC2AAAQAAMJjxDyQwC2AAABLgAFFAcJFQAjAJcWAA==.Jaytsukitori:BAACLgAFFH8aAAMFAAUJ+SQYDgATAgAFAAUJ+SQYDgATAgALAAEJgwhITwA4AAAuAAQKfx0AAwUACAmKIbkMANcCAAUACAmKIbkMANcCAAsAAQlmEESNADMAAAAA.',
Jh='Jhaeriao:BAAALgAECgYJDAAAAA==.Jhantherox:BAAALgAECgYJBgAAAA==.',
Jo='Joesepi:BAABLgAFFH8aAAIJAAYJ6xpyKQDDAQAJAAYJ6xpyKQDDAQAAAA==.Joham:BAAALgAECgEJAQAAAA==.Jojosus:BAAALgADCgcJBwABLgADCgkJOgAVAAAAAA==.Jonah:BAAALgAFFAEJAQABLgAFFAIJBQAJAB4YAA==.',
Ju='Judgeroybean:BAAALgAECgMJAwAAAA==.Juliofoolioo:BAAALgAECgEJAgAAAA==.',
Ka='Karti:BAAALgADCgQJBAAAAA==.Kayahli:BAAALgAECgQJBAAAAA==.Kazghul:BAAALgADCgEJAQAAAA==.',
Ke='Kelaeus:BAABLgAECn8VAAINAAYJUQ5x0ABMAQANAAYJUQ5x0ABMAQAAAA==.Keyonslayz:BAAALgADCggJCAAAAA==.',
Kh='Khrønos:BAAALgAECggJDAAAAA==.',
Ki='Kij:BAEBLgAFFH8GAAINAAYJhwnqEABXAQANAAYJhwnqEABXAQAAAA==.Killzom:BAAALgADCgEJAQABLgAFFAQJCwAOACkVAA==.Kilrah:BAABLgAECn82AAIaAAkJahbdEgABAgAaAAkJahbdEgABAgAAAA==.Kirian:BAAALgADCgEJAQAAAA==.Kissmyash:BAABLgAECn8WAAINAAYJ9Amd0wDtAAANAAYJ9Amd0wDtAAAAAA==.Kissmycrits:BAABLgAECn8ZAAIDAAQJsB2QgwA3AQADAAQJsB2QgwA3AQAAAA==.Kissmywrath:BAAALgAECgEJAQAAAA==.Kiyana:BAABLgAECn8vAAIaAAcJIA8TLQAZAQAaAAcJIA8TLQAZAQAAAA==.Kiyoine:BAABLgAECn8iAAIPAAgJKRkSDAD4AQAPAAgJKRkSDAD4AQAAAA==.',
Kn='Knocksteady:BAACLgAFFH8VAAIIAAcJOhehCgBXAQAIAAcJOhehCgBXAQAuAAQKfyAAAggABwm2IYskAJUCAAgABwm2IYskAJUCAAAA.Knoxform:BAAALgAECgMJBAAAAA==.Knoxhops:BAAALgAECgMJAwABLgAECgMJBAAVAAAAAA==.Knoxreaps:BAAALgAECgYJBAABLgAECgMJBAAVAAAAAA==.Knoxstaggers:BAABLgAECn8lAAIkAAgJ3iBWEwAXAgAkAAgJ3iBWEwAXAgABLgAECgMJBAAVAAAAAA==.',
Ko='Korozzma:BAAALgADCgYJBgABLgADCgMJAwAVAAAAAA==.',
Kr='Krzzy:BAAALgAFFAIJAgABLgAFFAgJDQAWAMcVAA==.',
Ku='Kuray:BAAALgAECgEJAgAAAA==.',
Ky='Kynbrookera:BAABLgAECn8iAAIFAAkJFQy9RQB5AQAFAAkJFQy9RQB5AQAAAA==.Kyujin:BAAALgADCgEJAQAAAA==.',
['Kì']='Kìnky:BAAALgAECgcJEwAAAA==.',
La='Laetha:BAAALgADCgUJBQAAAA==.',
Le='Lemicall:BAAALgADCgQJCAAAAA==.Lethiferous:BAAALgAECgIJAgAAAA==.Letmespankit:BAAALgADCgYJDAAAAA==.Lezigo:BAABLgAECn8jAAINAAkJaBQdSwD6AQANAAkJaBQdSwD6AQAAAA==.',
Li='Licht:BAAALgAECgYJCwAAAA==.Lik:BAAALgAECgQJBwAAAA==.Lilhorror:BAAALgADCgMJAwAAAA==.Lilpyro:BAAALgAECgQJBAAAAA==.Lilyheart:BAAALgADCgYJBgAAAA==.Linai:BAABLgAECn8kAAMjAAkJuQ7/FgDkAQAjAAkJuQ7/FgDkAQAlAAgJEQggDwAyAQAAAA==.Lit:BAAALgAECgEJAwAAAA==.Littledog:BAACLgAFFH8KAAIKAAQJbRQMGQAfAQAKAAQJbRQMGQAfAQAuAAQKfy4AAwoACQnXFZocAOABAAoACQnXFZocAOABACAABAlyFq09AL8AAAAA.Liz:BAAALgADCgEJAQABLgAECgUJDQAVAAAAAA==.',
Lo='Lockdout:BAAALgADCgEJAQABLgAECggJGQANANkWAA==.Loky:BAACLgAFFH8HAAIMAAIJWht4jwClAAAMAAIJWht4jwClAAAuAAQKfyUABAwACQkCH8c8AOgBAAwACQncHsc8AOgBAB4ABAl+GMskADUBABgAAQl6ISwwAF4AAAAA.Longshanks:BAAALgADCgUJDAAAAA==.Longshenks:BAAALgAECgEJAQAAAA==.Lorna:BAAALgADCgEJAQAAAA==.Lotten:BAAALgAECgUJDAAAAA==.',
Lu='Luckevin:BAAALgAECgYJDgAAAA==.Lumianir:BAAALgAECgEJAgAAAA==.Lunitari:BAABLgAECn8UAAImAAYJ7wafFgCsAAAmAAYJ7wafFgCsAAAAAA==.Luthiean:BAAALgADCgQJBAAAAA==.Luthran:BAAALgAECgUJCwABLgAECggJGAAPAD8PAA==.',
Ly='Lynnali:BAAALgADCggJEQAAAA==.Lyrrin:BAAALgADCgYJBgAAAA==.',
Ma='Magedon:BAAALgAECgEJAQAAAA==.Mageyoulaugh:BAABLgAECn8ZAAINAAgJ2RZhYAC/AQANAAgJ2RZhYAC/AQAAAA==.Magezamb:BAAALgAECgUJDQAAAA==.Magicmann:BAAALgAECgEJAQAAAA==.Magmash:BAAALgADCggJDwAAAA==.Mahito:BAAALgADCgEJAQAAAA==.Mahru:BAAALgADCgYJCAAAAA==.Majhduul:BAAALgAECgIJAgAAAA==.Malafang:BAABLgAECn8XAAIIAAcJIAYSBQGyAAAIAAcJIAYSBQGyAAAAAA==.Malanah:BAABLgAECn8ZAAIKAAgJQw4oOgAqAQAKAAgJQw4oOgAqAQAAAA==.Marandra:BAAALgAECgQJCwAAAA==.Marlie:BAAALgAECgMJAwAAAA==.Mathalios:BAAALgAECgIJAgAAAA==.Mattu:BAABLgAECn8XAAIhAAcJRAMXDgCDAAAhAAcJRAMXDgCDAAAAAA==.Maverick:BAACLgAFFH8VAAIjAAcJlxanCABiAQAjAAcJlxanCABiAQAuAAQKfxsAAyMABwlUIsIVAGECACMABwlNIsIVAGECACUABAmBIpcMAFgBAAAA.Maxbaba:BAAALgAECgEJAQAAAA==.',
Mc='Mcskittelz:BAAALgADCgQJBAAAAA==.',
Me='Meleshanorak:BAAALgADCgUJCgAAAA==.',
Mi='Michaella:BAAALgAECgUJCwAAAA==.Michartson:BAAALgADCgYJBAAAAA==.Mingres:BAABLgAECn8XAAIDAAcJQw9AegBLAQADAAcJQw9AegBLAQAAAA==.Miramanie:BAAALgADCgYJBgAAAA==.Misdiagnosed:BAAALgADCgIJAgAAAA==.Mistbrewer:BAAALgADCgIJAgAAAA==.',
Mk='Mk:BAEBLgAECn8UAAIXAAYJ8RYOCgDUAAAXAAYJ8RYOCgDUAAABLgAECgkJTQAnAIoiAA==.',
Mo='Mogar:BAABLgAECn8fAAIfAAgJEh48DAAjAgAfAAgJEh48DAAjAgAAAA==.Mogina:BAAALgADCggJCAAAAA==.Monkish:BAAALgADCgMJAwAAAA==.Monster:BAAALgAECgYJBgAAAA==.Moonzhine:BAABLgAECn8jAAITAAkJXhWZFQC/AQATAAkJXhWZFQC/AQAAAA==.Moosejaw:BAAALgAECgYJCwAAAA==.Mordread:BAAALgAECggJEwAAAA==.Morgalruk:BAABLgAFFH8FAAIJAAQJXwQAkQDpAAAJAAQJXwQAkQDpAAAAAA==.',
My='Myriosheal:BAAALgADCgQJBAAAAA==.Mythx:BAACLgAFFH8lAAQDAAgJTRsDAgCBAQADAAYJJh0DAgCBAQAEAAQJCQwvFwAYAQACAAIJRRR9KwBZAAAuAAQKfysABAMACAlXI3wIAAoDAAMACAlXI3wIAAoDAAQABgn7GLkrAEUBAAIABQkFEe5MAB0BAAAA.',
Na='Nalanelin:BAABLgAECn8WAAIJAAcJKQ0cmAA4AQAJAAcJKQ0cmAA4AQAAAA==.Narukin:BAABLgAECn8cAAIXAAcJVBr+RwCuAQAXAAcJVBr+RwCuAQAAAA==.Nasai:BAAALgAECgcJBwAAAA==.Naturboy:BAAALgADCgYJBgAAAA==.',
Ne='Nemmessiss:BAAALgAECgEJAgAAAA==.Nessirebette:BAAALgADCgUJCAAAAA==.Netherwalker:BAAALgAECgIJAgABLgAFFAkJJQAKAOYWAA==.Netherward:BAAALgAFFAEJAQABLgAFFAkJJQAKAOYWAA==.',
Ni='Nivmizzet:BAACLgAFFH8FAAIMAAMJ5g4pGADXAAAMAAMJ5g4pGADXAAAuAAQKfzAAAwwACAn4GXJPAKwBAAwABwl8GnJPAKwBAB4ABgnwFSotAAkBAAAA.',
No='Nolakai:BAAALgAECgEJAQAAAA==.Nomiro:BAAALgAECgYJDAAAAA==.Noradori:BAAALgAECgEJAQAAAA==.Notdip:BAAALgADCgIJAgAAAA==.Novalea:BAACLgAFFH8PAAMBAAQJ1yUgFwCtAQABAAQJ1yUgFwCtAQAWAAEJVwgZIQA8AAAuAAQKf00AAwEACQlhIwwFAGMDAAEACQlhIwwFAGMDABYABwkeHkAuAIkBAAAA.',
Nu='Nuru:BAAALgAECgcJEAAAAA==.Nutcutter:BAAALgAECgUJCQABLgAECggJLgAJAGgPAA==.',
['Nø']='Nøstalgic:BAAALgAECgEJAgAAAA==.',
Ob='Obala:BAAALgADCgIJAgAAAA==.',
Od='Odogaren:BAABLgAECn8ZAAMiAAgJzxxbCwBYAgAiAAcJgB1bCwBYAgASAAgJhRoVIQBLAgAAAA==.',
Om='Omnithorn:BAAALgAECggJDQAAAA==.',
On='Onei:BAAALgADCgEJAQAAAA==.',
Or='Oramos:BAAALgAECgQJBgAAAA==.Orgóndó:BAABLgAFFH8NAAITAAYJmR0vEACAAQATAAYJmR0vEACAAQAAAA==.',
Ov='Ova:BAAALgAECgQJBQAAAA==.Ovelaa:BAAALgAECgQJBAAAAA==.',
Ox='Oxxo:BAABLgAECn8nAAImAAcJoQ/JDABEAQAmAAcJoQ/JDABEAQAAAA==.',
Pa='Palzamb:BAAALgADCgYJCwAAAA==.Pandacillin:BAAALgAECgQJBAAAAA==.Paraggonn:BAABLgAECn8yAAIDAAgJihi8MwANAgADAAgJihi8MwANAgAAAA==.',
Pe='Penelöpe:BAAALgAECgMJBQAAAA==.Penoosê:BAAALgADCgEJAgAAAA==.Pepperice:BAAALgADCgIJAgAAAA==.Perlonis:BAAALgAECgYJEwAAAA==.',
Ph='Phatocaster:BAAALgADCgIJBAAAAA==.Pherkle:BAAALgAECgcJBwAAAA==.Phoinyx:BAAALgAECgkJDwAAAA==.Phuriosa:BAABLgAECn8VAAIjAAcJgQ+DAgA4AQAjAAcJgQ+DAgA4AQABLgAFFAMJCQAFAO8VAA==.Phury:BAACLgAFFH8JAAIFAAMJ7xWgOQDHAAAFAAMJ7xWgOQDHAAAuAAQKfyQAAwUACQlSGoknABQCAAUACAkbGYknABQCAAsAAgkmF9lgAJYAAAAA.Physinyx:BAAALgAECgkJCgAAAA==.Physta:BAAALgADCggJCwAAAA==.',
Pi='Pizza:BAABLgAECn8lAAIOAAcJehjPFgCcAQAOAAcJehjPFgCcAQAAAA==.',
Pl='Plagafel:BAAALgADCgYJBgAAAA==.',
Po='Pomomies:BAAALgAECgMJBAAAAA==.Pooseunpoose:BAAALgAFFAEJBAAAAA==.Porkmancer:BAAALgAECgYJCgABLgAECgkJJgAJAEwfAA==.Porkslope:BAABLgAECn8mAAIJAAgJTB+vJgBoAgAJAAgJTB+vJgBoAgAAAA==.',
Pr='Praahv:BAAALgADCgYJBgAAAA==.Profryktor:BAABLgAECn8aAAIfAAYJIRWuJABBAQAfAAYJIRWuJABBAQAAAA==.',
Pu='Purebloods:BAAALgADCgEJAQAAAA==.Purpleparrot:BAAALgAECgYJDwAAAA==.',
Qu='Quickben:BAAALgAECgIJAgAAAA==.',
Ra='Raenyx:BAABLgAECn9AAAMMAAgJ3x5THgBvAgAMAAgJ3x5THgBvAgAYAAMJag4hLABrAAAAAA==.Raiflock:BAABLgAECn8aAAIYAAgJ4xOgCQDJAQAYAAgJ4xOgCQDJAQAAAA==.Ranalastus:BAAALgAECgYJDgAAAA==.Raveneyes:BAEBLgAECn8jAAIMAAkJjhFDRQDLAQAMAAkJjhFDRQDLAQAAAA==.',
Re='Reiena:BAAALgAECgcJEAAAAA==.Relas:BAAALgADCgUJBQAAAA==.Reylilyn:BAABLgAECn8oAAIcAAkJqBUVGwA/AgAcAAkJqBUVGwA/AgAAAA==.Reynarena:BAAALgAECgYJEAAAAA==.',
Rh='Rhaenfyre:BAABLgAECn8jAAMXAAkJMBVGOgDeAQAXAAkJMBVGOgDeAQAdAAEJ9QzwOAAlAAAAAA==.',
Ri='Richardhurtz:BAAALgAECgYJCwAAAA==.Ricola:BAAALgAFFAIJBAAAAA==.Rivenel:BAACLgAFFH8TAAIeAAYJVROSAwCPAQAeAAYJVROSAwCPAQAuAAQKfykAAx4ACQkgIkMCAJ0CAB4ACAlaI0MCAJ0CAAwAAQmHGbQdAUoAAAAA.Rivèn:BAAALgADCgEJAQAAAA==.',
Ro='Robinvoid:BAABLgAECn8dAAMXAAkJgCAPFQDZAgAXAAkJgCAPFQDZAgAaAAEJ+RRiaQBAAAAAAA==.Rocksann:BAAALgAECgEJBAAAAA==.Rodel:BAAALgAECgEJAgABLgAECgMJAwAVAAAAAA==.Roquan:BAABLgAECn8wAAIbAAgJ7RvhCAD8AQAbAAgJ7RvhCAD8AQAAAA==.Roulette:BAAALgAECgUJDwAAAA==.',
Ru='Rubmyrott:BAAALgAFFAQJBAAAAA==.Runalot:BAAALgAECgYJBgAAAA==.Rundas:BAAALgADCgMJAwABLgAECgkJIwAkANkcAA==.Runelle:BAAALgADCgQJBAAAAA==.',
['Ré']='Rébél:BAAALgADCgEJAQAAAA==.',
['Rê']='Rêdd:BAABLgAECn8cAAIKAAcJXxHCLwBgAQAKAAcJXxHCLwBgAQAAAA==.',
Sa='Sabeion:BAAALgAECgYJDAAAAA==.Saboo:BAAALgAECgQJAQABLgAFFAEJAQAVAAAAAA==.Sadiebuding:BAAALgAECgEJAQAAAA==.Salswarriah:BAABLgAECn8dAAISAAcJEhFZOQBhAQASAAcJEhFZOQBhAQAAAA==.Sanaku:BAAALgAECgYJCAAAAA==.Sanangra:BAAALgADCgEJAQAAAA==.Santo:BAAALgADCgMJAwAAAA==.Sarlyan:BAAALgADCgkJFwAAAA==.Sassafrazz:BAAALgAECgQJBAAAAA==.',
Sc='Scrumbles:BAAALgAECgkJDwAAAA==.',
Se='Secksytoes:BAAALgAECgMJAwABLgADCgYJCwAVAAAAAA==.Segador:BAAALgADCgMJAwAAAA==.Seis:BAAALgAECgEJAQABLgAFFAEJAQAVAAAAAA==.Seraphim:BAAALgADCgEJAQAAAA==.Serion:BAAALgADCgMJAwAAAA==.Sewerrat:BAAALgADCggJCAAAAA==.',
Sg='Sgtbonesnap:BAAALgAECgcJDgAAAA==.Sgtpunchy:BAAALgADCgMJBQABLgAECgcJDgAVAAAAAA==.',
Sh='Shadowslam:BAAALgAECgEJAQABLgAECgkJAQAVAAAAAA==.Shakuro:BAAALgAECgEJAgAAAA==.Shallash:BAAALgAECgEJAQAAAA==.Shamageddon:BAAALgAECgIJBAAAAA==.Shamanizim:BAACLgAFFH8SAAMWAAUJJxfXCAASAQAWAAUJJxfXCAASAQAZAAIJsQjxCgBEAAAuAAQKfyoABBYACAmUHEIdAPcBABYACAkpHEIdAPcBABkABwnlFb8XAEwBAAEAAgknBmjQADsAAAAA.Shausin:BAAALgAECggJCAAAAA==.Sheeanna:BAAALgAFFAEJAQABLgAFFAQJDgAUADgjAA==.Shiftmyself:BAAALgADCgkJDgAAAA==.Shikigami:BAAALgAECgkJBwAAAA==.Shinoikari:BAACLgAFFH8KAAIbAAIJjQYdCgByAAAbAAIJjQYdCgByAAAuAAQKfygAAxsACQkNEcYKAM8BABsACQkNEcYKAM8BABMABQnJCKJDAIAAAAAA.Shinotenshi:BAABLgAECn8bAAQgAAcJtwm9OQAqAQAgAAcJvAi9OQAqAQARAAUJBweMYgCmAAAKAAEJKAR6lQAlAAABLgAFFAIJCgAbAI0GAA==.Shirase:BAABLgAECn8eAAMMAAkJdw7VbQBgAQAMAAkJHgzVbQBgAQAYAAYJRQ4eGAADAQABLgAFFAQJDwABANclAA==.Shugarae:BAABLgAECn8cAAMLAAgJPQgVPgAXAQALAAgJPQgVPgAXAQAFAAUJcATcnwBwAAAAAA==.',
Si='Sionnocht:BAAALgADCgEJAQAAAA==.Sirlemage:BAAALgADCgMJAwAAAA==.',
Sk='Skina:BAAALgAECgEJAQAAAA==.Skreezy:BAAALgAECgcJDAAAAA==.Skuls:BAAALgAECgMJBwAAAA==.',
Sl='Slashemup:BAABLgAECn8jAAIaAAkJ+RYpEgAKAgAaAAkJ+RYpEgAKAgAAAA==.Slayter:BAABLgAECn8lAAIFAAkJ2R8yHQBdAgAFAAkJ2R8yHQBdAgAAAA==.',
Sm='Smaugin:BAAALgAECgIJAgAAAA==.',
Sn='Snakelazers:BAACLgAFFH8IAAIcAAQJgiEwHgB+AQAcAAQJgiEwHgB+AQAuAAQKfyUAAhwACQn6IrQEAGMDABwACQn6IrQEAGMDAAAA.Snufulafagus:BAABLgAECn8WAAIPAAUJbRtlGgA6AQAPAAUJbRtlGgA6AQAAAA==.',
So='Soju:BAABLgAECn8oAAMBAAkJ9BdkGwBwAgABAAkJ9BdkGwBwAgAWAAQJJxKYbQCgAAABLgAECgkJLAADAMkjAA==.Soliloquy:BAAALgAECgkJEQAAAA==.Songwind:BAABLgAECn8qAAInAAgJYg3QLQBUAQAnAAgJYg3QLQBUAQAAAA==.Soonie:BAAALgADCgEJAQAAAA==.Soulreever:BAAALgADCggJCAAAAA==.',
Sq='Squishyman:BAAALgAFFAIJAgABLgAFFAMJBQAIALURAA==.Squishypal:BAACLgAFFH8FAAIIAAMJtRGcGADXAAAIAAMJtRGcGADXAAAuAAQKfx0AAwgACQl8Ho8VAMECAAgACQl8Ho8VAMECACgAAQnrFiM/AEEAAAAA.',
St='Starfirelmao:BAAALgAECgYJDwAAAA==.Steelcure:BAAALgAECgkJDAAAAA==.Strabo:BAAALgADCggJCQAAAA==.Strawdicks:BAAALgAECgcJAQAAAA==.',
Su='Sugma:BAAALgAECgEJAQAAAA==.Suzsette:BAABLgAECn8fAAIKAAcJVAlJQgAGAQAKAAcJVAlJQgAGAQAAAA==.',
Sy='Sylris:BAAALgADCgkJFgAAAA==.Sylvanthis:BAAALgAECgQJBAABLgAECgkJIgAFABUMAA==.',
['Sç']='Sçoxx:BAAALgADCgEJAQAAAA==.',
Ta='Taazdingo:BAAALgADCgEJAQAAAA==.Taeleth:BAAALgADCgcJBwAAAA==.Talnora:BAAALgAECgYJDwAAAA==.Tardovski:BAABLgAECn8lAAMDAAkJGSEtEADPAgADAAkJGSEtEADPAgACAAQJ2BP2VgDsAAAAAA==.Taurentino:BAAALgAECgkJBQAAAA==.',
Te='Telaris:BAAALgADCgIJAgAAAA==.Telda:BAABLgAECn8XAAIlAAcJrgS6FwC4AAAlAAcJrgS6FwC4AAAAAA==.Teneturadvós:BAAALgAECgcJCgABLgAECgcJDgAVAAAAAA==.Tentreeadvos:BAAALgAECgEJAQABLgAECgcJDgAVAAAAAA==.Tetris:BAACLgAFFH8ZAAINAAUJ3hz4FAAtAQANAAUJ3hz4FAAtAQAuAAQKfzgAAg0ACQmgIlwWANMCAA0ACQmgIlwWANMCAAAA.',
Th='Thellaria:BAAALgADCgQJBAAAAA==.Thraggoar:BAAALgADCgEJAQAAAA==.Thunsar:BAAALgAECgkJDwAAAA==.Thuzzad:BAAALgADCgUJBQAAAA==.',
Ti='Tickler:BAAALgAECgUJEQAAAA==.Tiroelin:BAAALgAECgUJBwAAAA==.',
To='Toetem:BAAALgADCgQJBgAAAA==.Tosselus:BAAALgAECgEJAgAAAA==.Tox:BAAALgADCgUJBQAAAA==.Toyotama:BAAALgAFFAIJAgABLgAFFAUJGgAFAPkkAA==.',
Tr='Tragedeigh:BAAALgAECgUJBQABLgAECgkJKQAGADgaAA==.Trane:BAAALgAECgIJAgAAAA==.Trañsformer:BAAALgAECgUJBQAAAA==.Tritoch:BAAALgAECgYJEAAAAA==.Troche:BAACLgAFFH8JAAIoAAQJEQh9DACwAAAoAAQJEQh9DACwAAAuAAQKfxgAAygACQmDESIQAMIBACgACQmDESIQAMIBABQAAQlNCEKYACgAAAAA.Truthfully:BAABLgAECn8WAAIIAAkJPw7fBgBUAQAIAAkJPw7fBgBUAQAAAA==.Trávpac:BAAALgADCgEJAQAAAA==.',
Tt='Ttjpll:BAAALgAFFAEJAQAAAA==.',
Tu='Tubs:BAAALgAECgEJAQAAAA==.Tuckncloak:BAAALgAECgMJAwAAAA==.',
Tw='Twohand:BAAALgADCgIJBAAAAA==.',
['Tî']='Tîmon:BAAALgAFFAIJAgAAAA==.',
Ug='Ugrup:BAAALgAECgcJEQAAAA==.',
Uj='Ujabula:BAAALgAECgYJEgAAAA==.',
Ul='Ulurak:BAABLgAECn8YAAMPAAgJPw8aGwAaAQAPAAYJkwkaGwAaAQAFAAQJ9QqjpgBlAAAAAA==.',
Um='Umaguma:BAAALgAECgQJAQAAAA==.',
Un='Uncleskip:BAABLgAECn8bAAIfAAcJ0wd0FgBJAQAfAAcJ0wd0FgBJAQAAAA==.Unhappytoast:BAABLgAECn8WAAIoAAkJdBgpCgAoAgAoAAkJdBgpCgAoAgAAAA==.Unstobubble:BAAALgAECgYJCQAAAA==.',
Va='Valeriya:BAAALgADCgcJCAABLgAECgMJAwAVAAAAAA==.Valisanna:BAAALgADCggJDQAAAA==.Vallorien:BAABLgAECn8gAAIoAAcJyh8GCwAZAgAoAAcJyh8GCwAZAgAAAA==.Valsharess:BAAALgADCgcJBwABLgAECgkJOAAXAEEaAA==.',
Ve='Vegetagos:BAAALgAECgQJBgAAAA==.Vegtam:BAAALgAECgEJAQAAAA==.Velaryn:BAAALgAFFAIJAgAAAA==.Velnia:BAAALgAECgYJCwAAAA==.Verencia:BAAALgAECgEJAQAAAA==.',
Vi='Vildaren:BAAALgAECgUJCQAAAA==.Vivachel:BAAALgADCgcJCAAAAA==.Viztrix:BAAALgADCgEJAQAAAA==.',
Vo='Vorsan:BAAALgADCgcJBwAAAA==.Vorsane:BAAALgADCgQJBAAAAA==.',
['Và']='Vàli:BAAALgAECgQJCgAAAA==.',
Wa='Wanks:BAAALgAECgYJDwAAAA==.Warmoon:BAAALgAECgMJAwAAAA==.Warskul:BAAALgAECgEJAQAAAA==.Wasenshi:BAAALgADCgUJBQAAAA==.',
We='Weeb:BAAALgADCgUJCwAAAA==.Weeny:BAAALgAECgcJCwAAAA==.',
Wh='Wholy:BAAALgAECgMJBgAAAA==.',
Wi='Wickedromeo:BAAALgAECgMJAwAAAA==.',
Wo='Wolfmother:BAABLgAECn8jAAIWAAgJpxS2KgCdAQAWAAgJpxS2KgCdAQAAAA==.',
Xa='Xaanii:BAABLgAECn8dAAIUAAYJUB1eIwDqAQAUAAYJUB1eIwDqAQAAAA==.Xandius:BAAALgADCgcJDAAAAA==.Xarferrin:BAABLgAECn8oAAINAAcJswOGHABhAAANAAcJswOGHABhAAAAAA==.',
Xe='Xeeria:BAACLgAFFH8iAAIBAAYJYhStLQAsAQABAAYJYhStLQAsAQAuAAQKfzAAAwEACQnyHwoNALUCAAEACQnyHwoNALUCABYAAQlXG8aSAE4AAAAA.Xenzull:BAAALgAECgIJAgAAAA==.',
Xi='Xidane:BAAALgAECgEJAQAAAA==.',
Xk='Xkaliber:BAAALgADCgEJAQAAAA==.',
Xu='Xuecat:BAABLgAECn8kAAIFAAgJ3xYQLgD1AQAFAAgJ3xYQLgD1AQAAAA==.',
Yn='Yn:BAAALgAECgYJDAAAAA==.',
Za='Zamzak:BAAALgADCgQJBAABLgAECgEJAQAVAAAAAA==.Zanthor:BAABLgAECn8WAAIJAAUJbgi+9wC3AAAJAAUJbgi+9wC3AAAAAA==.Zaralina:BAACLgAFFH8IAAIKAAQJBglwIQDoAAAKAAQJBglwIQDoAAAuAAQKfzQAAgoACQlPF3ISAEACAAoACQlPF3ISAEACAAAA.Zartox:BAABLgAECn8cAAIpAAkJoRa3AgAaAgApAAkJoRa3AgAaAgAAAA==.Zaryn:BAAALgADCgIJAgAAAA==.Zarynth:BAAALgAECgEJAQAAAA==.Zaryssa:BAABLgAECn8eAAIWAAgJjwUSUwDtAAAWAAgJjwUSUwDtAAAAAA==.Zavinus:BAAALgADCgYJCAAAAA==.',
Ze='Zenzug:BAAALgAECgUJDwAAAA==.Zephystra:BAAALgADCgQJBAABLgAFFAQJDwABANclAA==.Zeusqt:BAAALgADCgYJBgAAAA==.',
Zh='Zharfrost:BAAALgAECgYJCAAAAA==.',
Zi='Zicroniah:BAAALgADCgYJCgAAAA==.Zimfestation:BAABLgAFFH8FAAIJAAMJIAttKADNAAAJAAMJIAttKADNAAABLgAFFAUJEgAWACcXAA==.Ziyuu:BAAALgADCgUJBQAAAA==.',
Zo='Zombiehunter:BAABLgAECn8jAAIDAAkJaR/9EQDCAgADAAkJaR/9EQDCAgAAAA==.',
Zu='Zuzu:BAAALgADCgMJAwAAAA==.',
['Âr']='Ârc:BAAALgAECgEJAgAAAA==.',
['Èd']='Èddy:BAACLgAFFH8GAAIFAAMJTQmLSwCOAAAFAAMJTQmLSwCOAAAuAAQKfx0AAgUACQk0FuYcAF8CAAUACQk0FuYcAF8CAAAA.',
['Ðe']='Ðevdev:BAAALgADCgUJBQAAAA==.',
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
