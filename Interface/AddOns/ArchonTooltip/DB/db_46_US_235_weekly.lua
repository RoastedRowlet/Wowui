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

local lookup = {'Shaman-Restoration','Priest-Holy','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Druid-Restoration','Evoker-Preservation','Evoker-Devastation','Paladin-Retribution','DeathKnight-Unholy','Priest-Shadow','Druid-Balance','Warlock-Demonology','Mage-Frost','Evoker-Augmentation','Warrior-Fury','DeathKnight-Blood','Paladin-Holy','Unknown-Unknown','Shaman-Elemental','DemonHunter-Devourer','Warlock-Affliction','Shaman-Enhancement','DemonHunter-Havoc','DeathKnight-Frost','Monk-Mistweaver','DemonHunter-Vengeance','Warlock-Destruction','Warrior-Arms','Druid-Guardian','Druid-Feral','Priest-Discipline','Mage-Fire','Warrior-Protection','Paladin-Protection','Rogue-Subtlety','Monk-Brewmaster','Rogue-Assassination','Rogue-Outlaw','Monk-Windwalker','Mage-Arcane',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=46,date='2026-08-25',data={Aa='Aardnon:BAAALgADCgEJAQAAAA==.',
Ad='Addisyn:BAAALgAECgEJBAAAAA==.',
Ae='Aekal:BAAALgAECgUJBQAAAA==.Aemetris:BAABLgAECn8dAAIBAAkJSxX1NADeAQABAAkJSxX1NADeAQAAAA==.Aenicus:BAAALgADCgcJBwAAAA==.Aerina:BAAALgAECgQJCwAAAA==.Aethra:BAAALgADCgYJBgAAAA==.',
Ag='Agamotto:BAAALgAECgYJCgAAAA==.Agromagnetic:BAAALgAECgcJDQAAAA==.Agytha:BAAALgAECgMJAwAAAA==.Agøny:BAAALgADCgMJAwAAAA==.',
Ah='Ahskul:BAAALgADCgEJAQAAAA==.',
Ai='Aidendawn:BAABLgAECn8aAAICAAYJZQiLDwCoAAACAAYJZQiLDwCoAAAAAA==.',
Aj='Ajheria:BAAALgAECgEJAQAAAA==.',
Al='Aleiah:BAAALgAECgQJBAAAAA==.Alejandro:BAAALgADCgIJAQAAAA==.',
Am='Ameildoran:BAAALgADCgkJCQAAAA==.Amelicea:BAAALgADCgMJAwAAAA==.',
An='Anaire:BAAALgAECgMJAwAAAA==.Anaru:BAAALgAECgMJBgAAAA==.Anatyriel:BAAALgADCgEJAQAAAA==.Anayanci:BAAALgADCgUJBgAAAA==.Andalaine:BAAALgAECgQJCAAAAA==.Andari:BAAALgADCgEJAQAAAA==.Andramaedra:BAAALgAECgkJAgAAAA==.Angriff:BAAALgAECgEJAQAAAA==.Anoobornot:BAAALgADCgMJAwAAAA==.Anraleth:BAACLgAFFH8fAAIDAAUJ9iOEBgBZAQADAAUJ9iOEBgBZAQAuAAQKfzwAAwMACQkLJQgDAKwCAAMACAnnJAgDAKwCAAQAAQkGJqP6AGUAAAAA.',
Ap='Apaum:BAAALgADCgYJBgAAAA==.Aponi:BAAALgAECgUJCAAAAA==.',
Aq='Aquiles:BAAALgADCgEJAQAAAA==.',
Ar='Arckillion:BAAALgAECgUJCQAAAA==.Ardour:BAAALgAECgMJBgABLgAECgkJLAAFADgVAA==.Arduous:BAAALgAECgMJBAAAAA==.Areyea:BAAALgAECgQJBAAAAA==.Ariana:BAAALgAECgEJAQAAAA==.Arihu:BAABLgAECn8fAAIGAAkJlxT7LgDoAQAGAAkJlxT7LgDoAQAAAA==.Arkhana:BAAALgADCgEJAQAAAA==.Arrawm:BAAALgAECgEJAQAAAA==.',
As='Ashenaya:BAABLgAECn8YAAMHAAgJLxlbDAAQAgAHAAgJLxlbDAAQAgAIAAEJMQpQQgArAAAAAA==.Asparagus:BAABLgAECn8aAAIJAAkJVw59YwCpAQAJAAkJVw59YwCpAQAAAA==.',
At='Atlass:BAACLgAFFH8GAAIKAAIJLhXh0gCOAAAKAAIJLhXh0gCOAAAuAAQKfxgAAgoABwnxGYtjAMkBAAoABwnxGYtjAMkBAAAA.Atrest:BAAALgAECgYJBwAAAA==.',
Au='Augmenter:BAAALgAECgQJBQABLgAFFAkJPgALADMjAA==.Aust:BAABLgAECn8UAAIJAAgJ6hMCbACWAQAJAAgJ6hMCbACWAQAAAA==.',
Av='Averlin:BAAALgAECgUJCAAAAA==.Averlis:BAABLgAECn8nAAIMAAkJShj+BwBNAQAMAAkJShj+BwBNAQAAAA==.Avoiddance:BAAALgAECgYJBgAAAA==.',
Ax='Axee:BAAALgADCgYJBgAAAA==.',
Ay='Ayperos:BAAALgAECgQJBwAAAA==.',
Az='Azima:BAAALgAECgMJAwAAAA==.Azmithrilim:BAAALgAECgUJBQAAAA==.Azura:BAAALgADCgIJAgAAAA==.Azurargentyr:BAABLgAECn8UAAMHAAkJgQtuFQB1AQAHAAkJgQtuFQB1AQAIAAMJ1AI7NgBkAAAAAA==.',
Ba='Babeolicious:BAAALgADCgEJAQAAAA==.Bacon:BAABLgAECn8lAAIJAAkJzAp1hgBjAQAJAAkJzAp1hgBjAQAAAA==.Bambøøze:BAAALgADCgEJAQAAAA==.Bandadi:BAECLgAFFH8IAAINAAYJwhWeKwCXAQANAAYJwhWeKwCXAQAuAAQKfzEAAg0ACAkzIG0VANUCAA0ACAkzIG0VANUCAAEuAAUUCAkVAA4AkBkA.Barbelo:BAAALgAECgcJCgAAAA==.Barely:BAAALgAECgkJEQAAAA==.Barkweldort:BAAALgAECgYJEQAAAA==.Barreled:BAAALgADCgMJAwAAAA==.Batistabomba:BAAALgAECgYJBgAAAA==.',
Be='Beargruk:BAAALgAECgUJBwAAAA==.Beastly:BAAALgAECggJEQAAAA==.Beeble:BAABLgAECn8XAAIOAAYJvwmF0ADxAAAOAAYJvwmF0ADxAAAAAA==.Belii:BAAALgAECgYJDAAAAA==.Bended:BAAALgADCgIJAgAAAA==.Bepisthepall:BAAALgAECgEJAgAAAA==.Betterkevin:BAAALgAECgQJDwAAAA==.Bezerkachew:BAAALgAECgEJAgAAAA==.',
Bl='Blikey:BAABLgAFFH8GAAIKAAIJfia0vQCuAAAKAAIJfia0vQCuAAAAAA==.Bloodyrott:BAAALgAECgUJCgAAAA==.Bluedrake:BAACLgAFFH8NAAMIAAQJ1BtUAwBEAQAIAAQJ1BtUAwBEAQAPAAEJPROlZABAAAAuAAQKfyMAAwgACAlfHr4EALoCAAgACAmGHb4EALoCAA8ACAk9FlIZAAMCAAEuAAUUBgkUAAwAAh8A.Blueparrot:BAABLgAECn8+AAICAAgJXxXjGwDoAQACAAgJXxXjGwDoAQAAAA==.Blur:BAAALgADCgEJAQAAAA==.Bluy:BAAALgADCgMJAwAAAA==.Blädèstorm:BAABLgAECn8ZAAIQAAgJphwOJADUAQAQAAgJphwOJADUAQAAAA==.',
Bo='Bonesnap:BAACLgAFFH8VAAMKAAcJeR5yHAAHAgAKAAYJeR5yHAAHAgARAAEJAAA/VQAAAAAuAAQKfyAAAwoACQmrIaMXAO4CAAoACQmrIaMXAO4CABEABAmuE2A+AJYAAAAA.Bowkatan:BAAALgAECgEJAgAAAA==.',
Br='Brianisita:BAAALgAECgUJBgAAAA==.Brightmane:BAABLgAECn8WAAISAAYJUx4zJQD8AQASAAYJUx4zJQD8AQAAAA==.Bringinlight:BAABLgAECn8oAAICAAYJFRBoCwDuAAACAAYJFRBoCwDuAAABLgAECgcJEwATAAAAAA==.',
Bu='Bubbleicious:BAAALgAECgYJEgAAAA==.Bubbletea:BAABLgAECn8YAAIJAAgJLhb5SQDoAQAJAAgJLhb5SQDoAQABLgAECgkJLAAEAMkjAA==.Bulletz:BAABLgAECn8eAAIDAAgJ7x0LBQBbAgADAAgJ7x0LBQBbAgAAAA==.Bumpersnouts:BAAALgADCgkJCQAAAA==.Buttfur:BAAALgADCgYJBgAAAA==.',
['Bê']='Bêarwithme:BAAALgAFFAEJAQABLgAECgcJHAALAF8RAA==.',
Ca='Caenzo:BAAALgADCgkJCgAAAA==.Casanna:BAAALgADCgYJBgAAAA==.Cassandria:BAABLgAECn8sAAMGAAgJBxDRVAA8AQAGAAcJqw7RVAA8AQAMAAgJ2Az+OgAmAQAAAA==.Cassiradra:BAAALgAECgEJAQAAAA==.Caylastus:BAAALgAECgEJBAAAAA==.',
Ce='Cearas:BAAALgAECgEJAQAAAA==.Cedrick:BAAALgAECgUJBQAAAA==.Celiona:BAAALgAECgkJBwAAAA==.Celody:BAAALgAECgYJDAAAAA==.Celticsinsix:BAAALgAECgQJBgAAAA==.Cervixticklr:BAAALgAECgYJDAAAAA==.',
Ch='Chaoten:BAAALgADCgEJAQAAAA==.Chathlia:BAAALgAECgQJBAAAAA==.Chavdar:BAAALgADCgEJAQAAAA==.Chewster:BAACLgAFFH8FAAIOAAMJgQSdSgCjAAAOAAMJgQSdSgCjAAAuAAQKfzwAAg4ACQlQE7sXAB0BAA4ACQlQE7sXAB0BAAAA.Chewy:BAAALgAECgIJAwAAAA==.Chixie:BAAALgADCgEJAQAAAA==.Choal:BAABLgAECn8WAAIGAAYJyBCkYQAQAQAGAAYJyBCkYQAQAQAAAA==.Choglana:BAAALgAECgcJCQAAAA==.Chogli:BAAALgAECgEJAQABLgAECgcJCQATAAAAAA==.Chogric:BAABLgAECn85AAMSAAkJhh+NBQATAwASAAkJhh+NBQATAwAJAAQJZw2MKAGJAAABLgAECgcJCQATAAAAAA==.Chornan:BAAALgAECgQJBAAAAA==.',
Ci='Civetta:BAABLgAECn8WAAIEAAkJhwznUQCtAQAEAAkJhwznUQCtAQAAAA==.',
Cl='Clannininick:BAAALgADCgUJBgAAAA==.Clara:BAAALgAECgEJAQAAAA==.Clark:BAAALgADCgEJAQAAAA==.Clavicular:BAAALgAECgIJAwAAAA==.',
Co='Cogswell:BAAALgADCgIJAgABLgAECgIJAgATAAAAAA==.Comespankit:BAAALgAECgUJBQAAAA==.Constiua:BAAALgAECgcJDwABLgAECgcJCQATAAAAAA==.Convalesor:BAABLgAECn8UAAILAAYJQQibTwDSAAALAAYJQQibTwDSAAAAAA==.',
Cr='Crazzywazzy:BAABLgAFFH8LAAIKAAUJFhptbAAjAQAKAAUJFhptbAAjAQAAAA==.Crep:BAAALgAECgEJAQABLgAFFAEJAQATAAAAAA==.Crona:BAABLgAECn8bAAISAAkJtg4LPACJAQASAAkJtg4LPACJAQAAAA==.Crsteel:BAAALgAECgEJAQAAAA==.Crzyblnkrton:BAACLgAFFH8PAAIOAAYJthAGRgBaAQAOAAYJthAGRgBaAQAuAAQKfxcAAg4ACAnmH2k5AJACAA4ACAnmH2k5AJACAAAA.Crzzy:BAABLgAFFH8NAAIUAAgJxxUoEACsAQAUAAgJxxUoEACsAQAAAA==.',
Cu='Cuddlez:BAABLgAECn8gAAICAAkJGQtXLQBiAQACAAkJGQtXLQBiAQAAAA==.Cultera:BAACLgAFFH8WAAIVAAQJlRVXSAAPAQAVAAQJlRVXSAAPAQAuAAQKfyEAAhUACQmvIPUCAFMCABUACQmvIPUCAFMCAAAA.Cumintogitya:BAAALgAECgQJCAABLgAECgcJEwATAAAAAA==.',
Cy='Cyhyraethia:BAABLgAECn8fAAIWAAgJDB+sBQANAgAWAAgJDB+sBQANAgABLgAECgkJOAAVAEEaAA==.Cyndera:BAAALgADCgEJAQAAAA==.Cyrienna:BAAALgAECgEJAQAAAA==.',
Da='Dagden:BAAALgADCgYJCAAAAA==.Dalaa:BAAALgAECgIJAgAAAA==.Dammnation:BAAALgAFFAEJAwABLgAECgcJHAALAF8RAA==.Danda:BAAALgAECggJEgAAAA==.Daricepicker:BAABLgAECn8sAAIEAAkJySNPBQA3AwAEAAkJySNPBQA3AwAAAA==.Darkyn:BAABLgAECn8ZAAINAAkJPRCzRwDDAQANAAkJPRCzRwDDAQAAAA==.Davedadude:BAABLgAECn8wAAIJAAkJEyI1DAADAwAJAAkJEyI1DAADAwAAAA==.',
Dd='Ddeonu:BAAALgAECgEJAQAAAA==.Ddeonuu:BAABLgAFFH8MAAMEAAYJCw2kJwBoAQAEAAYJAwukJwBoAQADAAQJ2gxnGAD1AAAAAA==.',
De='Deadlysins:BAABLgAECn8XAAIKAAkJzAvpbACwAQAKAAkJzAvpbACwAQAAAA==.Deadscar:BAECLgAFFH8QAAIXAAQJ+SOAAwCcAQAXAAQJ+SOAAwCcAQAuAAQKfzoAAhcACQllJq0AAFwDABcACQllJq0AAFwDAAAA.Deathmasterj:BAAALgADCggJDgAAAA==.Deaths:BAABLgAECn8eAAMYAAgJTRJaHACaAQAYAAgJTRJaHACaAQAVAAEJJQRLOAEdAAAAAA==.Dedfrosty:BAABLgAECn8mAAMZAAgJ/hDDEQBcAQAZAAgJIg3DEQBcAQARAAgJQw4uJgAiAQAAAA==.Delindra:BAAALgADCgEJAQAAAA==.Demomcgee:BAAALgADCgEJAgABLgAECgYJDwATAAAAAA==.Demonio:BAAALgAECgEJAQAAAA==.Demonpimp:BAAALgAECgYJEAAAAA==.Dermon:BAAALgAECggJCwABLgAFFAQJCgAaAOcjAA==.Destan:BAAALgADCgEJAQAAAA==.Deviously:BAAALgADCgQJBAABLgAECgkJHgADAO8dAA==.Dewyhuey:BAAALgADCgIJAgAAAA==.',
Dh='Dhoong:BAAALgAECgIJAgAAAA==.',
Di='Dilaudid:BAAALgAECgEJAQAAAA==.Dimebagdaryl:BAAALgAECgQJBwAAAA==.Dimpiana:BAAALgAECgQJBAAAAA==.Disciplea:BAAALgAECgQJBAAAAA==.Dithariaa:BAABLgAECn8zAAIbAAgJOBBhAwAwAQAbAAgJOBBhAwAwAQAAAA==.',
Do='Docryktor:BAACLgAFFH8PAAIXAAQJsQ9TBgAEAQAXAAQJsQ9TBgAEAQAuAAQKf0YAAhcACQkVH4YDAHYBABcACQkVH4YDAHYBAAAA.Doomgears:BAABLgAECn8pAAIcAAYJ0xxuAwBbAQAcAAYJ0xxuAwBbAQAAAA==.Dotsdead:BAAALgADCgYJDgAAAA==.Dotöri:BAAALgAECggJDwAAAA==.',
Dr='Drachuntress:BAAALgADCgQJBAAAAA==.Draculä:BAAALgAECgUJBQABLgAFFAIJAgATAAAAAA==.Dragonair:BAABLgAECn8bAAMHAAcJ8QMjJADNAAAHAAcJ8QMjJADNAAAIAAcJ7ALdFwCcAAAAAA==.Drashta:BAAALgAECgEJAQAAAA==.Drhoe:BAAALgAECgEJAQAAAA==.Drhurtouch:BAABLgAECn8kAAIdAAkJCx2IBQCxAgAdAAkJCx2IBQCxAgAAAA==.Dro:BAAALgAECgUJCwAAAA==.Drogas:BAAALgAECgcJCgABLgAECggJIwAUAKcUAA==.Drtybear:BAABLgAECn8pAAMeAAkJBxWUCQDvAAAfAAUJ5hNvIQD9AAAeAAkJwROUCQDvAAAAAA==.Druithh:BAAALgAFFAEJAQABLgAFFAYJFQAOAGsYAA==.Drulissa:BAACLgAFFH8OAAISAAQJOCMQFQCBAQASAAQJOCMQFQCBAQAuAAQKfxkAAhIACQl1GZktAM0BABIACQl1GZktAM0BAAAA.Druu:BAAALgADCgMJAwABLgAFFAYJFQAOAGsYAA==.',
Du='Duh:BAAALgAECgEJAQAAAA==.Duogear:BAAALgADCgEJAQAAAA==.Dusters:BAAALgADCgcJCwAAAA==.',
['Dâ']='Dârrius:BAAALgAFFAIJAgAAAA==.',
Eb='Ebonwings:BAAALgAFFAEJAgAAAA==.',
Ed='Ediana:BAACLgAFFH8FAAIOAAMJxAKqlACpAAAOAAMJxAKqlACpAAAuAAQKfycAAg4ACQnqCRd4AIkBAA4ACQnqCRd4AIkBAAAA.',
Ee='Eebzy:BAAALgAECgcJCAAAAA==.',
El='Elandrah:BAAALgAECgkJEwAAAA==.Eld:BAAALgAECgEJAQAAAA==.Elmô:BAABLgAECn9GAAISAAkJJCAdAQDlAgASAAkJJCAdAQDlAgAAAA==.Elody:BAAALgADCggJCQAAAA==.Elvara:BAAALgAECgUJDQAAAA==.',
Eq='Equipwooman:BAAALgADCgIJAgAAAA==.',
Er='Erissannia:BAAALgAECgEJAQAAAA==.',
Es='Estameling:BAABLgAECn8qAAIeAAgJyhZpGACNAQAeAAgJyhZpGACNAQAAAA==.',
Ex='Exash:BAACLgAFFH8PAAIUAAQJwRrTHAA1AQAUAAQJwRrTHAA1AQAuAAQKfycAAhQACQk7ITUJAP8CABQACQk7ITUJAP8CAAAA.Excizion:BAACLgAFFH8OAAIKAAMJVgpfTgC+AAAKAAMJVgpfTgC+AAAuAAQKfyYAAgoACQlmDTVgAKkBAAoACQlmDTVgAKkBAAAA.',
Fa='Faelynne:BAAALgADCgUJBQAAAA==.Fathertim:BAABLgAECn8zAAMgAAgJDxz1AgBJAgAgAAgJDxz1AgBJAgALAAEJHw7tKgAqAAAAAA==.',
Fe='Feannara:BAAALgAECgYJCQAAAA==.Felar:BAAALgADCgEJAQAAAA==.Feldrena:BAAALgADCgcJDAAAAA==.',
Fl='Flangus:BAAALgADCgMJBAAAAA==.Flappydragon:BAAALgADCgIJAgAAAA==.Floraria:BAAALgADCgYJBgAAAA==.',
Fr='Frosticulz:BAAALgAECgUJBQAAAA==.Frostii:BAABLgAECn8dAAIOAAkJdhxCGQAQAQAOAAkJdhxCGQAQAQAAAA==.',
Fu='Fudestamp:BAAALgAECgUJBQAAAA==.Fufight:BAAALgAECgIJBQABLgAFFAQJCgAaAOcjAA==.Fugryktor:BAABLgAECn9MAAIWAAkJahnNAABmAgAWAAkJahnNAABmAgABLgAFFAQJDwAXALEPAA==.Fuzzywuzzy:BAAALgADCgMJAwAAAA==.',
Fy='Fyrebug:BAABLgAECn8jAAIBAAkJEwuWbQATAQABAAkJEwuWbQATAQAAAA==.',
Ga='Galandor:BAABLgAECn8kAAISAAkJ2xwgGwArAgASAAkJ2xwgGwArAgAAAA==.Gandaalf:BAABLgAECn8WAAMhAAcJCR7XAQBrAgAhAAcJCR7XAQBrAgAOAAIJ4Q9RRgFzAAAAAA==.Garrinda:BAAALgAECgkJDgAAAA==.Gaya:BAAALgAECgYJBgAAAA==.',
Ge='Geeked:BAAALgADCgUJBQAAAA==.Gemhide:BAABLgAECn8tAAIcAAkJGRf3AQDFAQAcAAkJGRf3AQDFAQAAAA==.Georgharison:BAAALgAECgEJAQAAAA==.Geroy:BAAALgAECgEJAgAAAA==.',
Gg='Ggwp:BAAALgAECgEJAQAAAA==.',
Gh='Ghae:BAAALgAECgUJBAAAAA==.Ghostsaber:BAAALgADCgEJAQABLgAECggJGQAiAM8cAA==.',
Gi='Gigglyguff:BAABLgAECn8YAAIGAAgJRiAgEgC9AgAGAAgJRiAgEgC9AgAAAA==.Gimly:BAAALgAECgEJAQAAAA==.Gityadruid:BAAALgAECgcJEwAAAA==.Gityahunter:BAABLgAECn8lAAIEAAYJ9g82HAAAAQAEAAYJ9g82HAAAAQABLgAECgcJEwATAAAAAA==.',
Gl='Glavenus:BAAALgADCgEJAQAAAA==.',
Go='Gobank:BAAALgADCgIJAgAAAA==.Gobanks:BAABLgAECn88AAIJAAkJpSCNEwDNAgAJAAkJpSCNEwDNAgAAAA==.',
Gr='Graycat:BAAALgADCgIJAgABLgAFFAkJJgAFAFQkAA==.Grayele:BAAALgAECgIJAgAAAA==.Grayson:BAABLgAECn8gAAMJAAkJMAjyOwBrAAAJAAgJDgfyOwBrAAAjAAEJJRDbGAAyAAAAAA==.Graysurv:BAACLgAFFH8mAAIFAAkJVCQEAACBAgAFAAkJVCQEAACBAgAuAAQKfywAAgUACQn6JgUAABQEAAUACQn6JgUAABQEAAAA.Gregmiller:BAAALgADCgYJBgAAAA==.Grimwali:BAAALgAECgQJBAAAAA==.Grizzly:BAAALgADCgYJCwAAAA==.Gromlin:BAAALgAECgUJDAAAAA==.Grothfen:BAAALgAECgYJDQAAAA==.',
['Gä']='Gäreth:BAAALgADCgYJCwAAAA==.',
Ha='Habachi:BAAALgADCgEJAQAAAA==.Halcrenian:BAAALgAECgIJAgAAAA==.Hamelot:BAAALgAECgIJAgAAAA==.Hamremmi:BAAALgAFFAEJAQABLgAFFAkJPgALADMjAA==.Handrider:BAAALgAECgEJAgAAAA==.Haruharu:BAAALgAFFAEJAQAAAA==.Hasalia:BAAALgAECggJCAABLgAFFAQJDgASADgjAA==.',
He='Healsforu:BAAALgAECgYJDgABLgAECgcJDwATAAAAAA==.Helly:BAAALgAECgEJAQAAAA==.Hemidall:BAAALgADCgMJAwAAAA==.Herbievore:BAABLgAECn8UAAMeAAgJORgtJQApAQAeAAUJ8RotJQApAQAMAAYJAhHcVAC8AAAAAA==.Heunno:BAAALgADCgYJBgABLgAFFAEJAQATAAAAAA==.',
Hi='Hiemy:BAAALgAECgYJBgAAAA==.Hif:BAACLgAFFH8KAAIGAAQJ1iDiIABRAQAGAAQJ1iDiIABRAQAuAAQKfyMAAgYACQn2I7QFADEDAAYACQn2I7QFADEDAAAA.Highbrittz:BAAALgAECgYJDgAAAA==.',
Hm='Hmmisee:BAAALgAECgEJBAAAAA==.',
Ho='Hoakaren:BAABLgAECn8ZAAIVAAkJAxZ5MAAEAgAVAAkJAxZ5MAAEAgAAAA==.Hobiscuits:BAEALgADCgQJBAABLgAECgkJJAANAL4eAA==.Hocus:BAAALgADCgYJBgAAAA==.Holde:BAAALgAECgUJDQAAAA==.Hornyrott:BAAALgAECgQJBgAAAA==.',
Hu='Hunnybear:BAAALgAECgcJCgAAAA==.Hunterzamb:BAAALgAECgEJAQAAAA==.Huntinator:BAABLgAECn8VAAIEAAcJHhtwMADvAQAEAAcJHhtwMADvAQAAAA==.',
Hy='Hydrobubble:BAABLgAECn8UAAQBAAcJex62BwDUAQABAAYJLx22BwDUAQAUAAQJKg+8cwCQAAAXAAEJ5gwCQAAwAAAAAA==.',
['Há']='Hátfield:BAAALgADCgEJAQAAAA==.',
Ih='Ihyo:BAAALgAECgEJAQAAAA==.',
Il='Illyy:BAABLgAECn8mAAICAAgJMgvgNgAkAQACAAgJMgvgNgAkAQAAAA==.',
Im='Impkingguy:BAAALgADCgYJBgAAAA==.',
In='Indawhole:BAACLgAFFH8qAAMVAAkJohhoDQDlAQAVAAkJPRdoDQDlAQAYAAMJdxifDADiAAAuAAQKfxoAAhUACAl8JfcjAEACABUACAl8JfcjAEACAAAA.Innatecurse:BAAALgAECgEJAQAAAA==.Instakill:BAAALgAECgIJAQAAAA==.',
Ir='Iridori:BAABLgAECn8wAAICAAgJuCB+CwCvAgACAAgJuCB+CwCvAgAAAA==.Irönfist:BAAALgADCgkJEgAAAA==.',
It='Itzzender:BAAALgADCgIJAgAAAA==.',
Iz='Izumiwitabow:BAABLgAECn8hAAIEAAkJ/hLnHgDsAAAEAAkJ/hLnHgDsAAAAAA==.',
Ja='Jabberthehut:BAAALgAFFAEJAQAAAA==.Jadé:BAAALgADCgMJAwAAAA==.Jamerius:BAAALgAECgIJAgAAAA==.Jankovic:BAAALgADCgcJBwAAAA==.Jasmean:BAAALgADCgcJDwAAAA==.Javaluminous:BAABLgAECn8oAAIJAAgJQCBfLABQAgAJAAgJQCBfLABQAgAAAA==.Jay:BAABLgAFFH8GAAIPAAMJjxDyQwC2AAAPAAMJjxDyQwC2AAABLgAFFAcJFQAkAJcWAA==.Jaytsukitori:BAACLgAFFH8fAAMGAAYJpx8YDgATAgAGAAYJpx8YDgATAgAMAAMJMxIEGADCAAAuAAQKfx8AAwYACQljILkMANcCAAYACQljILkMANcCAAwAAQlmEESNADMAAAAA.',
Jh='Jhaeriao:BAAALgAECgYJDAAAAA==.Jhantherox:BAAALgAECgYJBgAAAA==.',
Jo='Joesepi:BAABLgAFFH8eAAIKAAYJ6xpyKQDDAQAKAAYJ6xpyKQDDAQAAAA==.Joham:BAAALgAECgEJAQAAAA==.Jojosus:BAAALgADCgcJBwABLgADCgkJRAATAAAAAA==.Jonah:BAAALgAFFAEJAQABLgAFFAIJBQAKAB4YAA==.Joodee:BAAALgADCggJCQAAAA==.Joral:BAAALgAECgIJAgAAAA==.',
Ju='Judgeroybean:BAAALgAECgMJAwAAAA==.Juliofoolioo:BAAALgAECgEJAgAAAA==.',
Ka='Karti:BAAALgADCgQJBAAAAA==.Katrine:BAABLgAECn8YAAIZAAkJuyC1AAABAwAZAAkJuyC1AAABAwAAAA==.Kayahli:BAAALgAECgQJBAAAAA==.Kazghul:BAAALgADCgEJAQAAAA==.',
Ke='Kelaeus:BAABLgAECn8VAAIOAAYJUQ5x0ABMAQAOAAYJUQ5x0ABMAQAAAA==.Kendreth:BAAALgADCgIJAgAAAA==.Keyonslayz:BAAALgADCggJCAAAAA==.',
Kh='Khrønos:BAAALgAECggJDAAAAA==.',
Ki='Kij:BAEBLgAFFH8VAAIOAAgJkBmUCwBUAgAOAAgJkBmUCwBUAgAAAA==.Killzom:BAAALgADCgEJAQABLgAFFAQJCwAeACkVAA==.Kilrah:BAABLgAECn82AAIYAAkJahbdEgABAgAYAAkJahbdEgABAgAAAA==.Kirian:BAAALgADCgEJAQAAAA==.Kissmyash:BAABLgAECn8WAAIOAAYJ9Amd0wDtAAAOAAYJ9Amd0wDtAAAAAA==.Kissmycrits:BAABLgAECn8ZAAIEAAQJsB2QgwA3AQAEAAQJsB2QgwA3AQAAAA==.Kissmywrath:BAAALgAFFAEJAQAAAA==.Kiyana:BAABLgAECn8wAAIYAAgJ6hATLQAZAQAYAAgJ6hATLQAZAQAAAA==.Kiyoine:BAABLgAECn8iAAIfAAgJKRkSDAD4AQAfAAgJKRkSDAD4AQAAAA==.',
Kn='Knocksteady:BAACLgAFFH8VAAIJAAcJOhehCgBXAQAJAAcJOhehCgBXAQAuAAQKfyAAAgkABwm2IYskAJUCAAkABwm2IYskAJUCAAAA.Knoxform:BAAALgAECgMJBAAAAA==.Knoxhops:BAAALgAECgMJAwABLgAECgMJBAATAAAAAA==.Knoxreaps:BAAALgAECgYJBAABLgAECgMJBAATAAAAAA==.Knoxstaggers:BAABLgAECn8lAAIlAAgJ3iBWEwAXAgAlAAgJ3iBWEwAXAgABLgAECgMJBAATAAAAAA==.',
Ko='Korozzma:BAAALgADCgYJBgABLgADCgMJAwATAAAAAA==.',
Kr='Krzzy:BAAALgAFFAIJAgABLgAFFAgJDQAUAMcVAA==.',
Ku='Kuray:BAAALgAECgEJAgAAAA==.',
Ky='Kyleclark:BAAALgADCgUJBQAAAA==.Kynbrookera:BAABLgAECn8lAAIGAAkJzgy9RQB5AQAGAAkJzgy9RQB5AQAAAA==.Kyujin:BAAALgADCgEJAQAAAA==.',
['Kì']='Kìnky:BAABLgAECn8UAAIQAAgJChcXMQCIAQAQAAgJChcXMQCIAQAAAA==.',
La='Laetha:BAAALgAECgQJBAABLgAECgkJIAAPAHUZAA==.',
Le='Lemicall:BAAALgAECgQJBAAAAA==.Lethiferous:BAAALgAECgIJAgAAAA==.Letmespankit:BAAALgADCgYJDAAAAA==.Lezigo:BAABLgAECn8jAAIOAAkJaBQdSwD6AQAOAAkJaBQdSwD6AQAAAA==.',
Lh='Lhynne:BAAALgAECgEJAQAAAA==.',
Li='Licht:BAAALgAECgYJDQAAAA==.Lik:BAAALgAECgQJBwAAAA==.Lilhorror:BAAALgADCgMJAwAAAA==.Lilpyro:BAAALgAECgQJBAAAAA==.Lilyheart:BAAALgADCgYJBgAAAA==.Linai:BAABLgAECn8uAAMkAAkJHhK0AwCcAQAkAAkJHhK0AwCcAQAmAAgJEQggDwAyAQAAAA==.Lit:BAAALgAECgEJAwAAAA==.Littledog:BAACLgAFFH8KAAILAAQJbRQMGQAfAQALAAQJbRQMGQAfAQAuAAQKfy4AAwsACQnXFZocAOABAAsACQnXFZocAOABACAABAlyFq09AL8AAAAA.Liz:BAAALgADCgEJAQABLgAECgUJDQATAAAAAA==.',
Lo='Lockdout:BAAALgADCgEJAQABLgAECggJGQAOANkWAA==.Loky:BAACLgAFFH8HAAINAAIJWht4jwClAAANAAIJWht4jwClAAAuAAQKfyUABA0ACQkCH8c8AOgBAA0ACQncHsc8AOgBABwABAl+GMskADUBABYAAQl6ISwwAF4AAAAA.Longshanks:BAAALgADCgUJDAAAAA==.Longshenks:BAAALgAECgEJAQAAAA==.Lorna:BAAALgADCgEJAQAAAA==.Lotten:BAAALgAECgUJDAAAAA==.',
Lu='Luckevin:BAAALgAECgYJDgAAAA==.Lumianir:BAAALgAECgEJAwAAAA==.Lunitari:BAABLgAECn8dAAInAAYJ8Qt+AwCtAAAnAAYJ8Qt+AwCtAAAAAA==.Luthiean:BAAALgADCgQJBAAAAA==.Luthran:BAAALgAECgUJCwABLgAECggJGAAfAD8PAA==.',
Ly='Lynnali:BAAALgADCggJEQAAAA==.Lyrrin:BAAALgADCgYJBgAAAA==.',
Ma='Magedon:BAAALgAECgEJAQAAAA==.Mageyoulaugh:BAABLgAECn8ZAAIOAAgJ2RZhYAC/AQAOAAgJ2RZhYAC/AQAAAA==.Magezamb:BAAALgAECgUJDQAAAA==.Magicmann:BAAALgAECgEJAQAAAA==.Magmash:BAAALgADCggJDwAAAA==.Mahito:BAAALgADCgEJAQAAAA==.Mahru:BAAALgADCgYJCAAAAA==.Majhduul:BAAALgAECgIJAgAAAA==.Malafang:BAABLgAECn8dAAIJAAcJSAtoIQDbAAAJAAcJSAtoIQDbAAAAAA==.Malanah:BAABLgAECn8dAAILAAkJ+hBIDQDnAAALAAkJ+hBIDQDnAAAAAA==.Marandra:BAAALgAECgQJCwAAAA==.Marlie:BAAALgAECgMJAwAAAA==.Mathalios:BAAALgAECgIJAgAAAA==.Mattu:BAABLgAECn8aAAIhAAcJXQMXDgCDAAAhAAcJXQMXDgCDAAAAAA==.Maverick:BAACLgAFFH8VAAIkAAcJlxanCABiAQAkAAcJlxanCABiAQAuAAQKfxwAAyQACAkiIsIVAGECACQACAkcIsIVAGECACYABAmBIpcMAFgBAAAA.Maxbaba:BAAALgAECgEJAQAAAA==.',
Mc='Mcskittelz:BAAALgADCgQJBAAAAA==.',
Me='Meleshanorak:BAAALgADCgUJCgAAAA==.Metaunmeta:BAAALgAECgMJAwABLgAFFAEJBAATAAAAAA==.',
Mi='Michaella:BAAALgAECgUJCwAAAA==.Michartson:BAAALgADCgYJBAAAAA==.Mingres:BAABLgAECn8XAAIEAAcJQw9AegBLAQAEAAcJQw9AegBLAQAAAA==.Minipwn:BAAALgAECgIJAgAAAA==.Miramanie:BAAALgADCgYJBgAAAA==.Misdiagnosed:BAAALgADCgIJAgAAAA==.Mistbrewer:BAAALgADCgIJAgAAAA==.',
Mk='Mk:BAEBLgAECn8UAAIVAAYJ8RYZFwDNAAAVAAYJ8RYZFwDNAAABLgAECgkJTQAoAIoiAA==.',
Mo='Mogar:BAACLgAFFH8KAAIdAAQJPRUeCgAgAQAdAAQJPRUeCgAgAQAuAAQKfx8AAh0ACAkRHjwMACMCAB0ACAkRHjwMACMCAAAA.Mogina:BAAALgADCggJCAAAAA==.Monkish:BAAALgADCgMJAwAAAA==.Monster:BAAALgAECgkJDAAAAA==.Moonzhine:BAABLgAECn8jAAIRAAkJXhWZFQC/AQARAAkJXhWZFQC/AQAAAA==.Moosejaw:BAAALgAECgcJDwAAAA==.Mordread:BAABLgAECn8WAAMcAAkJ8RFSDwBKAQAcAAkJ8RFSDwBKAQANAAMJOgnl7ACGAAAAAA==.Morgalruk:BAABLgAFFH8FAAIKAAQJXwQAkQDpAAAKAAQJXwQAkQDpAAAAAA==.',
Mu='Muulgortal:BAAALgAECgIJAgAAAA==.',
My='Myriosheal:BAAALgADCgQJBAAAAA==.Mythx:BAACLgAFFH8sAAQEAAkJ1BsDAgCBAQAEAAcJAxwDAgCBAQAFAAQJShIvFwAYAQADAAIJRRR9KwBZAAAuAAQKfysABAQACAlXI3wIAAoDAAQACAlXI3wIAAoDAAUABgn7GLkrAEUBAAMABQkFEe5MAB0BAAAA.',
Na='Nalanelin:BAABLgAECn8WAAIKAAcJKQ0cmAA4AQAKAAcJKQ0cmAA4AQAAAA==.Narukin:BAABLgAECn8cAAIVAAcJVBr+RwCuAQAVAAcJVBr+RwCuAQAAAA==.Nasai:BAAALgAECgcJBwAAAA==.Naturboy:BAAALgADCgYJBgAAAA==.',
Ne='Nessirebette:BAAALgADCgUJCAAAAA==.Netherwalker:BAAALgAECgIJAgABLgAFFAkJPgALADMjAA==.Netherward:BAAALgAFFAEJAwABLgAFFAkJPgALADMjAA==.',
Ni='Niknikboy:BAAALgAECgEJAgAAAA==.Nivmizzet:BAACLgAFFH8IAAINAAQJMQ5ZJwDxAAANAAQJMQ5ZJwDxAAAuAAQKfzAAAw0ACAn4GXJPAKwBAA0ABwl8GnJPAKwBABwABgnwFSotAAkBAAAA.',
No='Nolakai:BAAALgAECgEJAQAAAA==.Nomiro:BAAALgAECgYJDAAAAA==.Noradori:BAAALgAECgEJAQAAAA==.Notdip:BAAALgADCgIJAgAAAA==.Novalea:BAACLgAFFH8PAAMBAAQJ1yUgFwCtAQABAAQJ1yUgFwCtAQAUAAEJVwjEPAAyAAAuAAQKf00AAwEACQlhIwwFAGMDAAEACQlhIwwFAGMDABQABwkeHkAuAIkBAAAA.',
Nu='Nuru:BAAALgAECgcJEAAAAA==.Nutcutter:BAAALgAECgYJDgABLgAECgkJNAAKAEwSAA==.',
['Nø']='Nøstalgic:BAAALgAECgEJAgAAAA==.',
Ob='Obala:BAAALgADCgIJAgAAAA==.',
Od='Odogaren:BAABLgAECn8ZAAMiAAgJzxxbCwBYAgAiAAcJgB1bCwBYAgAQAAgJhRoVIQBLAgAAAA==.',
Om='Omnithorn:BAAALgAECggJDQAAAA==.',
On='Onei:BAAALgADCgEJAQAAAA==.',
Or='Oramos:BAAALgAECgQJBgAAAA==.Orgóndó:BAABLgAFFH8NAAIRAAYJmR0vEACAAQARAAYJmR0vEACAAQAAAA==.',
Ov='Ova:BAAALgAECgYJCgAAAA==.Ovelaa:BAAALgAECgQJBAAAAA==.',
Ox='Oxxo:BAABLgAECn8tAAInAAgJ5RN8AQBNAQAnAAgJ5RN8AQBNAQAAAA==.',
Pa='Palzamb:BAAALgADCgYJCwAAAA==.Pandacillin:BAAALgAECgQJBAAAAA==.Paraggonn:BAABLgAECn87AAIEAAgJBB5VBwAeAgAEAAgJBB5VBwAeAgAAAA==.',
Pe='Penelöpe:BAAALgAECgMJBQAAAA==.Penoosê:BAAALgADCgEJAgAAAA==.Pepperice:BAAALgADCgIJAgAAAA==.Perlonis:BAAALgAECgYJEwAAAA==.',
Ph='Phatocaster:BAAALgADCgIJBAAAAA==.Pherkle:BAABLgAECn8VAAIkAAkJWxKSAgDuAQAkAAkJWxKSAgDuAQABLgAFFAQJDwAXALEPAA==.Phoinyx:BAAALgAECgkJDwAAAA==.Phuriosa:BAABLgAECn8WAAIkAAcJ8w/3BgAaAQAkAAcJ8w/3BgAaAQABLgAFFAMJCQAGAO8VAA==.Phury:BAACLgAFFH8JAAIGAAMJ7xWgOQDHAAAGAAMJ7xWgOQDHAAAuAAQKfykAAwYACQlyGoknABQCAAYACAlAGYknABQCAAwAAgkmF9lgAJYAAAAA.Physta:BAAALgADCggJCwAAAA==.',
Pi='Pizza:BAABLgAECn8wAAIeAAgJlhi3AwCpAQAeAAgJlhi3AwCpAQAAAA==.',
Pl='Plagafel:BAAALgADCgYJBgAAAA==.',
Po='Pomomies:BAAALgAFFAMJAwAAAA==.Pooseunpoose:BAAALgAFFAEJBAAAAA==.Porkmancer:BAAALgAECgYJCgABLgAECgkJJgAKAEwfAA==.Porkslope:BAABLgAECn8mAAIKAAgJTB+vJgBoAgAKAAgJTB+vJgBoAgAAAA==.',
Pr='Praahv:BAAALgADCgYJBgAAAA==.Profryktor:BAABLgAECn8hAAMdAAgJxhk7BABTAQAdAAgJxhk7BABTAQAiAAEJyxNnFAA5AAAAAA==.',
Ps='Psamathe:BAAALgAECgEJAQAAAA==.',
Pu='Purebloods:BAAALgADCgEJAQAAAA==.Purpleparrot:BAABLgAECn8dAAIBAAkJ8gjqDwAyAQABAAkJ8gjqDwAyAQAAAA==.',
Qu='Quickben:BAAALgAECgIJAgAAAA==.',
Ra='Raenyx:BAABLgAECn9AAAMNAAgJ3x5THgBvAgANAAgJ3x5THgBvAgAWAAMJag4hLABrAAAAAA==.Raiflock:BAABLgAECn8eAAIWAAkJUxSgCQDJAQAWAAkJUxSgCQDJAQAAAA==.Raiif:BAAALgAECgQJAwABLgAECgkJHgAWAFMUAA==.Ranalastus:BAAALgAECgYJDgAAAA==.Raveneyes:BAEBLgAECn8jAAINAAkJjhFDRQDLAQANAAkJjhFDRQDLAQAAAA==.Rayn:BAAALgAECgMJAwAAAA==.',
Re='Reiena:BAAALgAECgcJEAAAAA==.Relas:BAAALgADCgUJBQAAAA==.Revvan:BAAALgAECgEJAQAAAA==.Reylilyn:BAABLgAECn8oAAIaAAkJqBUVGwA/AgAaAAkJqBUVGwA/AgAAAA==.Reynarena:BAAALgAECgYJEAAAAA==.',
Rh='Rhaenfyre:BAABLgAECn8jAAMVAAkJMBVGOgDeAQAVAAkJMBVGOgDeAQAbAAEJ9QzwOAAlAAAAAA==.',
Ri='Richardhurtz:BAAALgAECgYJCwAAAA==.Rick:BAAALgAECgEJAgAAAA==.Ricola:BAAALgAFFAIJBAAAAA==.Rivenel:BAACLgAFFH8aAAIcAAgJ5xMpAQDlAQAcAAgJ5xMpAQDlAQAuAAQKfykAAxwACQkgIkMCAJ0CABwACAlaI0MCAJ0CAA0AAQmHGbQdAUoAAAAA.Rivèn:BAAALgADCgEJAQAAAA==.',
Ro='Robinvoid:BAABLgAECn8dAAMVAAkJgCAPFQDZAgAVAAkJgCAPFQDZAgAYAAEJ+RRiaQBAAAAAAA==.Rocksann:BAAALgAECgEJBAAAAA==.Rodel:BAAALgAECgEJAgABLgAECgMJAwATAAAAAA==.Roquan:BAABLgAECn8wAAIZAAgJ7RvhCAD8AQAZAAgJ7RvhCAD8AQAAAA==.Roulette:BAAALgAECgUJDwAAAA==.',
Ru='Rubmyrott:BAACLgAFFH8HAAIOAAUJcAUKeADpAAAOAAUJcAUKeADpAAAuAAQKfxQAAg4ACAnPF0sKAMIBAA4ACAnPF0sKAMIBAAAA.Runalot:BAAALgAECgYJBwAAAA==.Rundas:BAAALgADCgMJAwABLgAECgkJIwAlANkcAA==.Runelle:BAAALgADCgQJBAAAAA==.Rush:BAAALgAECgEJAQAAAA==.',
['Ré']='Rébél:BAAALgADCgEJAQAAAA==.',
['Rê']='Rêdd:BAABLgAECn8cAAILAAcJXxHCLwBgAQALAAcJXxHCLwBgAQAAAA==.',
Sa='Sabeion:BAAALgAECgYJDAAAAA==.Saboo:BAAALgAECgQJAQABLgAFFAEJAQATAAAAAA==.Salswarriah:BAABLgAECn8mAAIQAAkJrRBLDwDbAAAQAAkJrRBLDwDbAAAAAA==.Sanaku:BAAALgAECgYJCAAAAA==.Sanangra:BAAALgADCgEJAQAAAA==.Santo:BAAALgADCgMJAwAAAA==.Sarlyan:BAAALgADCgkJFwAAAA==.Sassafrazz:BAAALgAECgQJBAAAAA==.',
Sc='Scrumbles:BAAALgAECgkJDwAAAA==.',
Se='Sealgair:BAAALgADCgMJAwAAAA==.Secksytoes:BAAALgAECgMJAwABLgADCgYJCwATAAAAAA==.Segador:BAAALgADCgMJAwAAAA==.Seis:BAAALgAECgEJAQABLgAFFAEJAQATAAAAAA==.Seraphim:BAAALgADCgEJAQAAAA==.Serion:BAAALgADCgMJAwAAAA==.Sewerrat:BAAALgADCggJCAAAAA==.',
Sg='Sgtbonesnap:BAAALgAECgcJDwAAAA==.Sgtpunchy:BAAALgADCgMJBQABLgAECgcJDwATAAAAAA==.',
Sh='Shadowslam:BAAALgAFFAEJAQAAAA==.Shakuro:BAAALgAECgEJAgAAAA==.Shallash:BAAALgAECgEJAQAAAA==.Shamageddon:BAAALgAECgIJBAAAAA==.Shamanizim:BAACLgAFFH8XAAMUAAYJcRYyDQBqAQAUAAYJcRYyDQBqAQAXAAIJsQhkGAA5AAAuAAQKfyoABBQACAmUHEIdAPcBABQACAkpHEIdAPcBABcABwnlFb8XAEwBAAEAAgknBmjQADsAAAAA.Shaniquua:BAAALgADCgMJAwAAAA==.Shausin:BAAALgAECggJCAAAAA==.Sheeanna:BAAALgAFFAEJAQABLgAFFAQJDgASADgjAA==.Shiftmyself:BAAALgADCgkJDgAAAA==.Shikigami:BAAALgAECgkJBwAAAA==.Shinoikari:BAACLgAFFH8KAAIZAAIJjQYeFwBjAAAZAAIJjQYeFwBjAAAuAAQKfygAAxkACQkNEcYKAM8BABkACQkNEcYKAM8BABEABQnJCKJDAIAAAAAA.Shinotenshi:BAABLgAECn8bAAQgAAcJtwm9OQAqAQAgAAcJvAi9OQAqAQACAAUJBweMYgCmAAALAAEJKAR6lQAlAAABLgAFFAIJCgAZAI0GAA==.Shirase:BAABLgAECn8eAAMNAAkJdw7VbQBgAQANAAkJHgzVbQBgAQAWAAYJRQ4eGAADAQABLgAFFAQJDwABANclAA==.Shugarae:BAABLgAECn8cAAMMAAgJPQgVPgAXAQAMAAgJPQgVPgAXAQAGAAUJcATcnwBwAAAAAA==.',
Si='Sigsauer:BAAALgAFFAIJAgAAAA==.Sionnocht:BAAALgADCgEJAQAAAA==.Sirlemage:BAAALgADCgMJAwAAAA==.',
Sk='Skina:BAAALgAECgEJAQAAAA==.Skotonyx:BAAALgAECgkJCQAAAA==.Skreezy:BAAALgAECgcJDAAAAA==.Skuls:BAAALgAECgMJBwAAAA==.',
Sl='Slashemup:BAABLgAECn8jAAIYAAkJ+RYpEgAKAgAYAAkJ+RYpEgAKAgAAAA==.Slayter:BAABLgAECn8lAAIGAAkJ2R8yHQBdAgAGAAkJ2R8yHQBdAgABLgAFFAEJAQATAAAAAA==.Slithiss:BAAALgADCgIJAgAAAA==.',
Sm='Smaugin:BAAALgAECgIJAgAAAA==.Smaugor:BAAALgAECgEJAQABLgAFFAIJAgATAAAAAA==.',
Sn='Snakelazers:BAACLgAFFH8KAAIaAAQJ5yMwHgB+AQAaAAQJ5yMwHgB+AQAuAAQKfyUAAhoACQn6IrQEAGMDABoACQn6IrQEAGMDAAAA.Snufulafagus:BAABLgAECn8WAAIfAAUJbRtlGgA6AQAfAAUJbRtlGgA6AQAAAA==.',
So='Soju:BAABLgAECn8oAAMBAAkJ9BdkGwBwAgABAAkJ9BdkGwBwAgAUAAQJJxKYbQCgAAABLgAECgkJLAAEAMkjAA==.Soliloquy:BAAALgAECgkJEQAAAA==.Songwind:BAABLgAECn8qAAIoAAgJYg3QLQBUAQAoAAgJYg3QLQBUAQAAAA==.Soonie:BAAALgADCgEJAQAAAA==.Soulreever:BAAALgADCggJCAAAAA==.',
Sq='Squishyman:BAACLgAFFH8IAAMNAAMJOhsrJwDyAAANAAMJOhsrJwDyAAAWAAEJlQK6GgAxAAAuAAQKfyYAAg0ACQnGII4BAP0CAA0ACQnGII4BAP0CAAEuAAUUBAkJAAkAPBUA.Squishypal:BAACLgAFFH8JAAIJAAQJPBW+HQAXAQAJAAQJPBW+HQAXAQAuAAQKfx4AAwkACQl8Ho8VAMECAAkACQl8Ho8VAMECACMAAgnmHQUQAGcAAAAA.',
St='Starfirelmao:BAAALgAECgYJDwAAAA==.Steelcure:BAAALgAECgkJEwAAAA==.Strabo:BAAALgADCggJCQAAAA==.Strawdicks:BAAALgAECgcJAQAAAA==.',
Su='Sugma:BAAALgAECgEJAQAAAA==.Suzsette:BAABLgAECn8lAAILAAkJExHxCQAmAQALAAkJExHxCQAmAQAAAA==.',
Sy='Sylris:BAAALgADCgkJFgAAAA==.Sylvanthis:BAAALgAECgQJBAABLgAECgkJJQAGAM4MAA==.',
['Sç']='Sçoxx:BAAALgADCgEJAQAAAA==.',
Ta='Taazdingo:BAAALgADCgEJAQAAAA==.Taeleth:BAAALgADCgcJBwAAAA==.Talnora:BAAALgAECgYJDwAAAA==.Tardovski:BAABLgAECn8lAAMEAAkJGSEtEADPAgAEAAkJGSEtEADPAgADAAQJ2BP2VgDsAAAAAA==.Taurentino:BAAALgAECgkJBQAAAA==.',
Te='Telaris:BAAALgADCgIJAgAAAA==.Telda:BAABLgAECn8bAAImAAcJGAckBAC8AAAmAAcJGAckBAC8AAAAAA==.Teneturadvos:BAAALgAECgEJAQABLgAFFAEJAgATAAAAAA==.Teneturadvós:BAAALgAECgkJDgABLgAFFAEJAgATAAAAAA==.Tentreeadvos:BAAALgAECgEJAQABLgAFFAEJAgATAAAAAA==.Terrorbear:BAAALgAECgYJBgAAAA==.Tetris:BAACLgAFFH8dAAIOAAUJ3hwOLAAfAQAOAAUJ3hwOLAAfAQAuAAQKfzgAAg4ACQmgIlwWANMCAA4ACQmgIlwWANMCAAAA.',
Th='Thellaria:BAAALgAECgYJBwAAAA==.Thiccterror:BAABLgAECn8rAAMeAAkJdgpdCAAMAQAeAAkJ5ghdCAAMAQAfAAcJpQgQDQBoAAAAAA==.Thraggoar:BAAALgADCgEJAQAAAA==.Thunsar:BAAALgAECgkJDwAAAA==.Thuzzad:BAAALgADCgUJBQAAAA==.',
Ti='Tickler:BAAALgAECgUJEQAAAA==.Tiroelin:BAAALgAECgUJBwAAAA==.',
To='Toetem:BAAALgADCgQJBgAAAA==.Tosselus:BAAALgAECgEJAwAAAA==.Tox:BAAALgADCgUJBQAAAA==.Toyotama:BAAALgAFFAIJAgABLgAFFAYJHwAGAKcfAA==.',
Tr='Tragedeigh:BAAALgAECgUJBQABLgAECgkJKQAHAEMaAA==.Trane:BAAALgAECgIJAgAAAA==.Trañsformer:BAAALgAFFAIJAgAAAA==.Treala:BAAALgADCggJCAABLgAECgkJHQALAPoQAA==.Tritoch:BAAALgAECgYJEAAAAA==.Troche:BAACLgAFFH8LAAIjAAQJEQh9DACwAAAjAAQJEQh9DACwAAAuAAQKfxgAAyMACQmDESIQAMIBACMACQmDESIQAMIBABIAAQlNCEKYACgAAAAA.Truthfully:BAABLgAECn8WAAIJAAkJPQ6kFAA5AQAJAAkJPQ6kFAA5AQAAAA==.Trávpac:BAAALgADCgEJAQAAAA==.',
Tt='Ttjpll:BAAALgAFFAEJAQAAAA==.',
Tu='Tubs:BAAALgAECgEJAQAAAA==.Tuckncloak:BAAALgAECgMJAwAAAA==.',
Tw='Twohand:BAAALgADCgIJBAAAAA==.',
['Tî']='Tîmon:BAAALgAFFAIJAgABLgAFFAIJAgATAAAAAA==.',
Ug='Ugrup:BAAALgAECgcJEgAAAA==.',
Uj='Ujabula:BAAALgAECgYJEgAAAA==.',
Ul='Ulurak:BAABLgAECn8YAAMfAAgJPw8aGwAaAQAfAAYJkwkaGwAaAQAGAAQJ9QqjpgBlAAAAAA==.',
Um='Umaguma:BAAALgAECgUJAwAAAA==.',
Un='Uncleskip:BAABLgAECn8bAAIdAAcJ0wd0FgBJAQAdAAcJ0wd0FgBJAQAAAA==.Unhappytoast:BAABLgAECn8WAAIjAAkJdBgpCgAoAgAjAAkJdBgpCgAoAgAAAA==.Unstobubble:BAAALgAECgYJCQAAAA==.',
Va='Valeriya:BAAALgADCgcJCAABLgAECgMJAwATAAAAAA==.Valisanna:BAAALgAECgEJBAAAAA==.Valklemor:BAAALgAECgUJBgAAAA==.Vallorien:BAABLgAECn8mAAIjAAkJkyAGCwAZAgAjAAkJkyAGCwAZAgAAAA==.Valsharess:BAAALgADCgcJBwABLgAECgkJOAAVAEEaAA==.',
Ve='Vegetagos:BAAALgAECgQJBgAAAA==.Vegtam:BAAALgAECgEJAQAAAA==.Velaryn:BAAALgAFFAIJAgAAAA==.Velnia:BAAALgAECgYJCwAAAA==.Verencia:BAAALgAECgEJAQAAAA==.',
Vi='Vildaren:BAAALgAECgUJCQAAAA==.Vivachel:BAAALgADCgcJCAAAAA==.Viztrix:BAAALgADCgEJAgAAAA==.',
Vo='Vorsan:BAAALgADCgcJBwAAAA==.Vorsane:BAAALgADCgQJBAAAAA==.',
['Và']='Vàli:BAAALgAECgcJEgAAAA==.',
Wa='Wanks:BAAALgAECgYJDwAAAA==.Warmoon:BAAALgAECgMJAwAAAA==.Warskul:BAAALgAECgEJAQAAAA==.Wasenshi:BAAALgADCgUJBQAAAA==.',
We='Weeb:BAAALgADCgUJCwABLgAECgkJGgAkAMsaAA==.Weeny:BAAALgAECgcJCwAAAA==.',
Wh='Whiffle:BAAALgAECgcJDAAAAA==.Wholy:BAAALgAECgMJBgAAAA==.',
Wi='Wickedromeo:BAAALgAECgMJAwAAAA==.',
Wo='Wolfmother:BAABLgAECn8jAAIUAAgJpxS2KgCdAQAUAAgJpxS2KgCdAQAAAA==.Wolvarro:BAAALgADCgMJAwAAAA==.',
Xa='Xaanii:BAABLgAECn8jAAISAAkJoxxeIwDqAQASAAkJoxxeIwDqAQAAAA==.Xandius:BAAALgADCgcJDAAAAA==.Xarferrin:BAABLgAECn8vAAIOAAgJXAa2IQDXAAAOAAgJXAa2IQDXAAAAAA==.Xarnethia:BAAALgAECgQJBAAAAA==.',
Xe='Xeeria:BAACLgAFFH8lAAIBAAcJPhKtLQAsAQABAAcJPhKtLQAsAQAuAAQKfzEAAwEACQk9IAoNALUCAAEACQk9IAoNALUCABQAAQlXG8aSAE4AAAAA.Xenzull:BAAALgAECgIJAgAAAA==.',
Xi='Xidane:BAAALgAECgIJAgAAAA==.',
Xk='Xkaliber:BAAALgADCgEJAQAAAA==.',
Xu='Xuecat:BAABLgAECn8kAAIGAAgJ3xYQLgD1AQAGAAgJ3xYQLgD1AQAAAA==.',
Yn='Yn:BAAALgAECgYJDAAAAA==.',
Za='Zadee:BAAALgAECgEJAQAAAA==.Zamzak:BAAALgADCgQJBAABLgAECgEJAQATAAAAAA==.Zanthor:BAACLgAFFH8IAAIKAAIJ/ARbdQBuAAAKAAIJ/ARbdQBuAAAuAAQKfxsAAxkABgloDh0LAJkAAAoABgnDCr73ALcAABkAAwn3Dx0LAJkAAAAA.Zaralina:BAACLgAFFH8KAAILAAQJ1AtkFADBAAALAAQJ1AtkFADBAAAuAAQKfzQAAgsACQlPF3ISAEACAAsACQlPF3ISAEACAAAA.Zartox:BAABLgAECn8cAAIpAAkJoRa3AgAaAgApAAkJoRa3AgAaAgAAAA==.Zaryn:BAAALgADCgIJAgAAAA==.Zarynth:BAAALgAECgEJAQAAAA==.Zaryssa:BAABLgAECn8eAAIUAAgJjwUSUwDtAAAUAAgJjwUSUwDtAAAAAA==.Zavinus:BAAALgADCgYJCAAAAA==.',
Ze='Zenzug:BAAALgAECgUJDwAAAA==.Zephystra:BAAALgADCgQJBAABLgAFFAQJDwABANclAA==.Zeusqt:BAAALgADCgYJBgAAAA==.',
Zh='Zharfrost:BAAALgAECgYJCAAAAA==.',
Zi='Zicroniah:BAAALgAECgQJBAAAAA==.Zimfestation:BAABLgAFFH8JAAIKAAMJxBXqQQDaAAAKAAMJxBXqQQDaAAABLgAFFAYJFwAUAHEWAA==.Zimquisition:BAABLgAFFH8GAAMjAAMJVyJ6BgDCAAAjAAIJuiF6BgDCAAAJAAIJFRMlRgCNAAABLgAFFAYJFwAUAHEWAA==.Zinwaz:BAAALgAECgMJAwAAAA==.Ziyuu:BAAALgADCgUJBQAAAA==.',
Zm='Zmaj:BAAALgAECgEJAQAAAA==.',
Zo='Zombiehunter:BAABLgAECn8jAAIEAAkJaR/9EQDCAgAEAAkJaR/9EQDCAgAAAA==.Zophiah:BAAALgAECgEJAgAAAA==.',
Zu='Zug:BAAALgAECgEJAQAAAA==.Zuzu:BAAALgADCgMJAwAAAA==.',
['Âr']='Ârc:BAABLgAFFH8HAAIYAAQJVQ8ACwD7AAAYAAQJVQ8ACwD7AAAAAA==.',
['Èd']='Èddy:BAACLgAFFH8GAAIGAAMJTQmLSwCOAAAGAAMJTQmLSwCOAAAuAAQKfx0AAgYACQk0FuYcAF8CAAYACQk0FuYcAF8CAAAA.',
['Ðe']='Ðevdev:BAAALgADCggJDQAAAA==.',
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
