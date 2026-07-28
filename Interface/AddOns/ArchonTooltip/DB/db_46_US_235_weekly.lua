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

local lookup = {'Shaman-Restoration','Priest-Holy','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Druid-Restoration','Evoker-Preservation','Evoker-Devastation','Paladin-Retribution','DeathKnight-Unholy','Priest-Shadow','Druid-Balance','Warlock-Demonology','Mage-Frost','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Warrior-Fury','DeathKnight-Blood','Paladin-Holy','Unknown-Unknown','Shaman-Elemental','DemonHunter-Devourer','Warlock-Affliction','Shaman-Enhancement','DemonHunter-Havoc','DeathKnight-Frost','Monk-Mistweaver','DemonHunter-Vengeance','Warlock-Destruction','Warrior-Arms','Priest-Discipline','Mage-Fire','Warrior-Protection','Rogue-Subtlety','Monk-Brewmaster','Rogue-Assassination','Rogue-Outlaw','Monk-Windwalker','Paladin-Protection','Mage-Arcane',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=46,date='2026-07-28',data={Aa='Aardnon:BAAALgADCgEJAQAAAA==.',
Ad='Addisyn:BAAALgAECgEJBAAAAA==.',
Ae='Aekal:BAAALgAECgUJBQAAAA==.Aemetris:BAABLgAECn8cAAIBAAgJARb1NADeAQABAAgJARb1NADeAQAAAA==.Aenicus:BAAALgADCgcJBwAAAA==.Aerina:BAAALgAECgQJCwAAAA==.Aethra:BAAALgADCgYJBgAAAA==.',
Ag='Agamotto:BAAALgAECgYJCgAAAA==.Agromagnetic:BAAALgAECgcJDQAAAA==.Agytha:BAAALgAECgMJAwAAAA==.Agøny:BAAALgADCgMJAwAAAA==.',
Ah='Ahskul:BAAALgADCgEJAQAAAA==.',
Ai='Aidendawn:BAABLgAECn8aAAICAAYJZQh7DQCpAAACAAYJZQh7DQCpAAAAAA==.',
Aj='Ajheria:BAAALgAECgEJAQAAAA==.',
Al='Aleiah:BAAALgAECgQJBAAAAA==.Alejandro:BAAALgADCgIJAQAAAA==.',
Am='Ameildoran:BAAALgADCgkJCQAAAA==.Amelicea:BAAALgADCgMJAwAAAA==.',
An='Anaire:BAAALgAECgMJAwAAAA==.Anaru:BAAALgAECgMJBgAAAA==.Anatyriel:BAAALgADCgEJAQAAAA==.Anayanci:BAAALgADCgUJBgAAAA==.Andalaine:BAAALgAECgQJCAAAAA==.Andari:BAAALgADCgEJAQAAAA==.Andramaedra:BAAALgAECgkJAgAAAA==.Anoobornot:BAAALgADCgMJAwAAAA==.Anraleth:BAACLgAFFH8fAAIDAAUJ9iMGBgBcAQADAAUJ9iMGBgBcAQAuAAQKfzwAAwMACQkLJQgDAKwCAAMACAnnJAgDAKwCAAQAAQkGJqP6AGUAAAAA.',
Ap='Apaum:BAAALgADCgYJBgAAAA==.Aponi:BAAALgAECgUJCAAAAA==.',
Aq='Aquiles:BAAALgADCgEJAQAAAA==.',
Ar='Arckillion:BAAALgAECgUJBgAAAA==.Ardour:BAAALgAECgMJBgABLgAECgkJLAAFADgVAA==.Arduous:BAAALgAECgMJBAAAAA==.Areyea:BAAALgAECgQJBAAAAA==.Ariana:BAAALgAECgEJAQAAAA==.Arihu:BAABLgAECn8fAAIGAAkJlxT7LgDoAQAGAAkJlxT7LgDoAQAAAA==.Arkhana:BAAALgADCgEJAQAAAA==.Arrawm:BAAALgAECgEJAQAAAA==.',
As='Ashenaya:BAABLgAECn8YAAMHAAgJLxlbDAAQAgAHAAgJLxlbDAAQAgAIAAEJMQpQQgArAAAAAA==.Asparagus:BAABLgAECn8aAAIJAAkJVw59YwCpAQAJAAkJVw59YwCpAQAAAA==.',
At='Atlass:BAACLgAFFH8GAAIKAAIJLhXh0gCOAAAKAAIJLhXh0gCOAAAuAAQKfxgAAgoABwnxGYtjAMkBAAoABwnxGYtjAMkBAAAA.Atrest:BAAALgAECgYJBwAAAA==.',
Au='Augmenter:BAAALgAECgQJBQABLgAFFAkJOwALADMjAA==.Aust:BAABLgAECn8UAAIJAAgJ6hMCbACWAQAJAAgJ6hMCbACWAQAAAA==.',
Av='Averlin:BAAALgAECgUJCAAAAA==.Averlis:BAABLgAECn8nAAIMAAkJShh3BgBSAQAMAAkJShh3BgBSAQAAAA==.Avoiddance:BAAALgAECgYJBgAAAA==.',
Ax='Axee:BAAALgADCgYJBgAAAA==.',
Az='Azima:BAAALgAECgMJAwAAAA==.Azmithrilim:BAAALgAECgEJAQAAAA==.Azura:BAAALgADCgIJAgAAAA==.Azurargentyr:BAABLgAECn8UAAMHAAkJgQtuFQB1AQAHAAkJgQtuFQB1AQAIAAMJ1AI7NgBkAAAAAA==.',
Ba='Babeolicious:BAAALgADCgEJAQAAAA==.Bacon:BAABLgAECn8lAAIJAAkJzAp1hgBjAQAJAAkJzAp1hgBjAQAAAA==.Bambøøze:BAAALgADCgEJAQAAAA==.Bandadi:BAECLgAFFH8IAAINAAYJwhWeKwCXAQANAAYJwhWeKwCXAQAuAAQKfzEAAg0ACAkzIG0VANUCAA0ACAkzIG0VANUCAAEuAAUUCAkOAA4AHxMA.Barbelo:BAAALgAECgcJCgAAAA==.Barely:BAAALgAECgkJEQAAAA==.Barkweldort:BAAALgAECgYJEQAAAA==.Barreled:BAAALgADCgMJAwAAAA==.Batistabomba:BAAALgAECgYJBgAAAA==.',
Be='Beargruk:BAAALgAECgUJBwAAAA==.Beastly:BAAALgAECggJEQAAAA==.Beeble:BAABLgAECn8XAAIOAAYJvwmF0ADxAAAOAAYJvwmF0ADxAAAAAA==.Belii:BAAALgAECgYJDAAAAA==.Bended:BAAALgADCgIJAgAAAA==.Bepisthepall:BAAALgAECgEJAgAAAA==.Betterkevin:BAAALgAECgQJDwAAAA==.Bezerkachew:BAAALgAECgEJAgAAAA==.',
Bi='Bigbootijudi:BAAALgAECgEJAQAAAA==.Bigbooty:BAABLgAECn8rAAMPAAkJdgpOBwAQAQAPAAkJ5ghOBwAQAQAQAAcJpQgeCwBrAAAAAA==.',
Bl='Blikey:BAABLgAFFH8GAAIKAAIJfia0vQCuAAAKAAIJfia0vQCuAAAAAA==.Bloodyrott:BAAALgAECgUJCgAAAA==.Bluedrake:BAACLgAFFH8NAAMIAAQJ1BtUAwBEAQAIAAQJ1BtUAwBEAQARAAEJPROlZABAAAAuAAQKfyMAAwgACAlfHr4EALoCAAgACAmGHb4EALoCABEACAk9FlIZAAMCAAEuAAUUBgkUAAwAAh8A.Blueparrot:BAABLgAECn8+AAICAAgJXxXjGwDoAQACAAgJXxXjGwDoAQAAAA==.Blur:BAAALgADCgEJAQAAAA==.Bluy:BAAALgADCgMJAwAAAA==.Blädèstorm:BAABLgAECn8ZAAISAAgJphwOJADUAQASAAgJphwOJADUAQAAAA==.',
Bo='Bonesnap:BAACLgAFFH8VAAMKAAcJeR5yHAAHAgAKAAYJeR5yHAAHAgATAAEJAAA/VQAAAAAuAAQKfyAAAwoACQmrIaMXAO4CAAoACQmrIaMXAO4CABMABAmuE2A+AJYAAAAA.Bowkatan:BAAALgAECgEJAgAAAA==.',
Br='Brianisita:BAAALgAECgUJBgAAAA==.Brightmane:BAABLgAECn8WAAIUAAYJUx4zJQD8AQAUAAYJUx4zJQD8AQAAAA==.Bringinlight:BAABLgAECn8nAAICAAYJFRD+CQDvAAACAAYJFRD+CQDvAAABLgAECgcJDgAVAAAAAA==.',
Bu='Bubbleicious:BAAALgAECgYJEgAAAA==.Bubbletea:BAABLgAECn8YAAIJAAgJLhb5SQDoAQAJAAgJLhb5SQDoAQABLgAECgkJLAAEAMkjAA==.Bulletz:BAABLgAECn8eAAIDAAgJ7x0LBQBbAgADAAgJ7x0LBQBbAgAAAA==.Bumpersnouts:BAAALgADCgkJCQAAAA==.Buttfur:BAAALgADCgYJBgAAAA==.',
['Bê']='Bêarwithme:BAAALgAFFAEJAQABLgAECgcJHAALAF8RAA==.',
Ca='Caenzo:BAAALgADCgkJCgAAAA==.Casanna:BAAALgADCgYJBgAAAA==.Cassandria:BAABLgAECn8sAAMGAAgJBxDRVAA8AQAGAAcJqw7RVAA8AQAMAAgJ2Az+OgAmAQAAAA==.Cassiradra:BAAALgAECgEJAQAAAA==.Caylastus:BAAALgAECgEJBAAAAA==.',
Ce='Cearas:BAAALgAECgEJAQAAAA==.Cedrick:BAAALgAECgUJBQAAAA==.Celiona:BAAALgAECgkJBwAAAA==.Celody:BAAALgAECgYJDAAAAA==.Celticsinsix:BAAALgAECgMJBQAAAA==.Cervixticklr:BAAALgAECgYJDAAAAA==.',
Ch='Chaoten:BAAALgADCgEJAQAAAA==.Chathlia:BAAALgAECgQJBAAAAA==.Chavdar:BAAALgADCgEJAQAAAA==.Chewster:BAACLgAFFH8FAAIOAAMJgQRXRQCpAAAOAAMJgQRXRQCpAAAuAAQKfzwAAg4ACQlQE5YUACABAA4ACQlQE5YUACABAAAA.Chewy:BAAALgAECgEJAQAAAA==.Chixie:BAAALgADCgEJAQAAAA==.Choal:BAABLgAECn8WAAIGAAYJyBCkYQAQAQAGAAYJyBCkYQAQAQAAAA==.Choglana:BAAALgAECgcJCQAAAA==.Chogli:BAAALgAECgEJAQABLgAECgcJCQAVAAAAAA==.Chogric:BAABLgAECn85AAMUAAkJhh+NBQATAwAUAAkJhh+NBQATAwAJAAQJZw2MKAGJAAABLgAECgcJCQAVAAAAAA==.',
Ci='Civetta:BAABLgAECn8WAAIEAAkJhwznUQCtAQAEAAkJhwznUQCtAQAAAA==.',
Cl='Clannininick:BAAALgADCgUJBgAAAA==.Clark:BAAALgADCgEJAQAAAA==.Clavicular:BAAALgAECgIJAwAAAA==.',
Co='Cogswell:BAAALgADCgIJAgABLgAECgIJAgAVAAAAAA==.Comespankit:BAAALgAECgUJBQAAAA==.Constiua:BAAALgAECgcJDwABLgAECgcJCQAVAAAAAA==.Convalesor:BAABLgAECn8UAAILAAYJQQibTwDSAAALAAYJQQibTwDSAAAAAA==.',
Cr='Crazzywazzy:BAABLgAFFH8KAAIKAAQJcBhtbAAjAQAKAAQJcBhtbAAjAQAAAA==.Crep:BAAALgAECgEJAQABLgAFFAEJAQAVAAAAAA==.Crona:BAABLgAECn8aAAIUAAkJtg4LPACJAQAUAAkJtg4LPACJAQAAAA==.Crsteel:BAAALgAECgEJAQAAAA==.Crzyblnkrton:BAACLgAFFH8PAAIOAAYJthAGRgBaAQAOAAYJthAGRgBaAQAuAAQKfxcAAg4ACAnmH2k5AJACAA4ACAnmH2k5AJACAAAA.Crzzy:BAABLgAFFH8NAAIWAAgJxxUoEACsAQAWAAgJxxUoEACsAQAAAA==.',
Cu='Cuddlez:BAABLgAECn8gAAICAAkJGQtXLQBiAQACAAkJGQtXLQBiAQAAAA==.Cultera:BAACLgAFFH8WAAIXAAQJlRVXSAAPAQAXAAQJlRVXSAAPAQAuAAQKfyEAAhcACQmvIIACAFkCABcACQmvIIACAFkCAAAA.Cumintogitya:BAAALgAECgMJAwABLgAECgcJDgAVAAAAAA==.',
Cy='Cyhyraethia:BAABLgAECn8fAAIYAAgJDB+sBQANAgAYAAgJDB+sBQANAgABLgAECgkJOAAXAEEaAA==.Cyndera:BAAALgADCgEJAQAAAA==.Cyrienna:BAAALgAECgEJAQAAAA==.',
Da='Dagden:BAAALgADCgYJCAAAAA==.Dalaa:BAAALgAECgIJAgAAAA==.Dammnation:BAAALgAFFAEJAwABLgAECgcJHAALAF8RAA==.Danda:BAAALgAECggJEgAAAA==.Daricepicker:BAABLgAECn8sAAIEAAkJySNPBQA3AwAEAAkJySNPBQA3AwAAAA==.Darkyn:BAABLgAECn8ZAAINAAkJPRCzRwDDAQANAAkJPRCzRwDDAQAAAA==.Davedadude:BAABLgAECn8wAAIJAAkJEyI1DAADAwAJAAkJEyI1DAADAwAAAA==.',
Dd='Ddeonu:BAAALgAECgEJAQAAAA==.Ddeonuu:BAABLgAFFH8MAAMEAAYJCw2kJwBoAQAEAAYJAwukJwBoAQADAAQJ2gxnGAD1AAAAAA==.',
De='Deadlysins:BAABLgAECn8WAAIKAAgJ8wvpbACwAQAKAAgJ8wvpbACwAQAAAA==.Deadscar:BAECLgAFFH8QAAIZAAQJ+SOAAwCcAQAZAAQJ+SOAAwCcAQAuAAQKfzQAAhkACQlSJq0AAFwDABkACQlSJq0AAFwDAAAA.Deathmasterj:BAAALgADCggJDgAAAA==.Deaths:BAABLgAECn8eAAMaAAgJTRJaHACaAQAaAAgJTRJaHACaAQAXAAEJJQRLOAEdAAAAAA==.Dedfrosty:BAABLgAECn8mAAMbAAgJ/hDDEQBcAQAbAAgJIg3DEQBcAQATAAgJQw4uJgAiAQAAAA==.Delindra:BAAALgADCgEJAQAAAA==.Demomcgee:BAAALgADCgEJAgABLgAECgYJDwAVAAAAAA==.Demonio:BAAALgAECgEJAQAAAA==.Demonpimp:BAAALgAECgYJEAAAAA==.Dermon:BAAALgAECggJCwABLgAFFAQJCAAcAIIhAA==.Deviously:BAAALgADCgQJBAABLgAECgkJHgADAO8dAA==.Dewyhuey:BAAALgADCgIJAgAAAA==.',
Dh='Dhoong:BAAALgAECgIJAgAAAA==.',
Di='Dilaudid:BAAALgAECgEJAQAAAA==.Dimebagdaryl:BAAALgADCgkJCQAAAA==.Dimpiana:BAAALgAECgQJBAAAAA==.Disciplea:BAAALgAECgQJBAAAAA==.Dithariaa:BAABLgAECn8zAAIdAAgJOBDjAgAyAQAdAAgJOBDjAgAyAQAAAA==.',
Do='Docryktor:BAACLgAFFH8MAAIZAAQJKQ/NBQABAQAZAAQJKQ/NBQABAQAuAAQKf0MAAhkACQkXHQwKABoCABkACQkXHQwKABoCAAAA.Doomgears:BAABLgAECn8pAAIeAAYJ0xzMAgBcAQAeAAYJ0xzMAgBcAQAAAA==.Dotsdead:BAAALgADCgYJDgAAAA==.Dotöri:BAAALgAECggJDwAAAA==.',
Dr='Drachuntress:BAAALgADCgIJAgAAAA==.Draculä:BAAALgAECgUJBQABLgAFFAIJAgAVAAAAAA==.Dragonair:BAABLgAECn8bAAMHAAcJ8QMjJADNAAAHAAcJ8QMjJADNAAAIAAcJ7ALdFwCcAAAAAA==.Drashta:BAAALgAECgEJAQAAAA==.Drhoe:BAAALgAECgEJAQAAAA==.Drhurtouch:BAABLgAECn8kAAIfAAkJCx2IBQCxAgAfAAkJCx2IBQCxAgAAAA==.Dro:BAAALgAECgUJCwAAAA==.Drogas:BAAALgAECgcJCgABLgAECggJIwAWAKcUAA==.Drtybear:BAABLgAECn8oAAMPAAkJBxWHIwA0AQAPAAgJ+BKHIwA0AQAQAAUJ5hNvIQD9AAAAAA==.Druithh:BAAALgAFFAEJAQABLgAFFAYJFQAOAGsYAA==.Drulissa:BAACLgAFFH8OAAIUAAQJOCMQFQCBAQAUAAQJOCMQFQCBAQAuAAQKfxkAAhQACQl1GZktAM0BABQACQl1GZktAM0BAAAA.Druu:BAAALgADCgMJAwABLgAFFAYJFQAOAGsYAA==.',
Du='Duh:BAAALgAECgEJAQAAAA==.Duogear:BAAALgADCgEJAQAAAA==.Dusters:BAAALgADCgcJCwAAAA==.',
['Dâ']='Dârrius:BAAALgAFFAIJAgAAAA==.',
Eb='Ebonwings:BAAALgAFFAEJAgAAAA==.',
Ed='Ediana:BAACLgAFFH8FAAIOAAMJxAKqlACpAAAOAAMJxAKqlACpAAAuAAQKfycAAg4ACQnqCRd4AIkBAA4ACQnqCRd4AIkBAAAA.',
Ee='Eebzy:BAAALgAECgcJCAAAAA==.',
El='Elandrah:BAAALgAECgkJEwAAAA==.Eld:BAAALgAECgEJAQAAAA==.Elmô:BAABLgAECn8/AAIUAAkJ+x9ZAQCZAgAUAAkJ+x9ZAQCZAgAAAA==.Elody:BAAALgADCggJCQAAAA==.Elvara:BAAALgAECgUJDQAAAA==.',
Eq='Equipwooman:BAAALgADCgIJAgAAAA==.',
Er='Erissannia:BAAALgAECgEJAQAAAA==.',
Es='Estameling:BAABLgAECn8qAAIPAAgJyhZpGACNAQAPAAgJyhZpGACNAQAAAA==.',
Ex='Exash:BAACLgAFFH8PAAIWAAQJwRrTHAA1AQAWAAQJwRrTHAA1AQAuAAQKfycAAhYACQk7ITUJAP8CABYACQk7ITUJAP8CAAAA.Excizion:BAACLgAFFH8OAAIKAAMJVgqfSADCAAAKAAMJVgqfSADCAAAuAAQKfyUAAgoACQnzCzVgAKkBAAoACQnzCzVgAKkBAAAA.',
Fa='Faelynne:BAAALgADCgUJBQAAAA==.Fathertim:BAABLgAECn8zAAMgAAgJDxxpAgBMAgAgAAgJDxxpAgBMAgALAAEJHw4QJgAqAAAAAA==.',
Fe='Feannara:BAAALgAECgYJCQAAAA==.Felar:BAAALgADCgEJAQAAAA==.Feldrena:BAAALgADCgcJDAAAAA==.',
Fl='Flangus:BAAALgADCgMJBAAAAA==.Flappydragon:BAAALgADCgIJAgAAAA==.Floraria:BAAALgADCgYJBgAAAA==.',
Fr='Frosticulz:BAAALgAECgUJBQAAAA==.Frostii:BAABLgAECn8dAAIOAAkJdhzAFQAVAQAOAAkJdhzAFQAVAQAAAA==.',
Fu='Fudestamp:BAAALgAECgUJBQAAAA==.Fufight:BAAALgAECgIJBQABLgAFFAQJCAAcAIIhAA==.Fugryktor:BAABLgAECn9MAAIYAAkJahmiAABrAgAYAAkJahmiAABrAgABLgAFFAQJDAAZACkPAA==.Fuzzywuzzy:BAAALgADCgMJAwAAAA==.',
Fy='Fyrebug:BAABLgAECn8iAAIBAAgJawuWbQATAQABAAgJawuWbQATAQAAAA==.',
Ga='Galandor:BAABLgAECn8jAAIUAAgJchwgGwArAgAUAAgJchwgGwArAgAAAA==.Gandaalf:BAABLgAECn8WAAMhAAcJCR7XAQBrAgAhAAcJCR7XAQBrAgAOAAIJ4Q9RRgFzAAAAAA==.Garrinda:BAAALgAECgkJDgAAAA==.Gaya:BAAALgAECgYJBgAAAA==.',
Ge='Geeked:BAAALgADCgUJBQAAAA==.Gemhide:BAABLgAECn8sAAIeAAkJcRafCADCAQAeAAkJcRafCADCAQAAAA==.Georgharison:BAAALgAECgEJAQAAAA==.Geroy:BAAALgAECgEJAgAAAA==.',
Gg='Ggwp:BAAALgAECgEJAQAAAA==.',
Gh='Ghae:BAAALgAECgUJBAAAAA==.Ghostsaber:BAAALgADCgEJAQABLgAECggJGQAiAM8cAA==.',
Gi='Gigglyguff:BAABLgAECn8YAAIGAAgJRiAgEgC9AgAGAAgJRiAgEgC9AgAAAA==.Gimly:BAAALgAECgEJAQAAAA==.Gityadruid:BAAALgAECgcJDgAAAA==.Gityahunter:BAABLgAECn8eAAIEAAYJ2A+jGAAAAQAEAAYJ2A+jGAAAAQABLgAECgcJDgAVAAAAAA==.',
Gl='Glavenus:BAAALgADCgEJAQAAAA==.',
Go='Gobank:BAAALgADCgIJAgAAAA==.Gobanks:BAABLgAECn87AAIJAAkJXCCNEwDNAgAJAAkJXCCNEwDNAgAAAA==.',
Gr='Graycat:BAAALgADCgIJAgABLgAFFAkJJAAFAFQkAA==.Grayele:BAAALgAECgIJAgAAAA==.Grayson:BAABLgAECn8fAAIJAAgJDgf7MQBxAAAJAAgJDgf7MQBxAAAAAA==.Graysurv:BAACLgAFFH8kAAIFAAkJVCQEAACBAgAFAAkJVCQEAACBAgAuAAQKfywAAgUACQn6JgUAABQEAAUACQn6JgUAABQEAAAA.Gregmiller:BAAALgADCgYJBgAAAA==.Grizzly:BAAALgADCgYJCwAAAA==.Gromlin:BAAALgAECgUJDAAAAA==.Grothfen:BAAALgAECgYJDQAAAA==.',
['Gä']='Gäreth:BAAALgADCgYJCwAAAA==.',
Ha='Habachi:BAAALgADCgEJAQAAAA==.Halcrenian:BAAALgAECgIJAgAAAA==.Hamelot:BAAALgADCgMJBAAAAA==.Hamremmi:BAAALgAFFAEJAQABLgAFFAkJOwALADMjAA==.Handrider:BAAALgAECgEJAgAAAA==.Haruharu:BAAALgAFFAEJAQAAAA==.Hasalia:BAAALgAECggJCAABLgAFFAQJDgAUADgjAA==.',
He='Healsforu:BAAALgAECgYJDgABLgAECgcJDwAVAAAAAA==.Helly:BAAALgAECgEJAQAAAA==.Hemidall:BAAALgADCgMJAwAAAA==.Herbievore:BAABLgAECn8UAAMPAAgJORgtJQApAQAPAAUJ8RotJQApAQAMAAYJAhHcVAC8AAAAAA==.Heunno:BAAALgADCgYJBgABLgAFFAEJAQAVAAAAAA==.',
Hi='Hiemy:BAAALgAECgYJBgAAAA==.Hif:BAACLgAFFH8IAAIGAAQJAh3iIABRAQAGAAQJAh3iIABRAQAuAAQKfyMAAgYACQn2I7QFADEDAAYACQn2I7QFADEDAAAA.Highbrittz:BAAALgAECgYJDgAAAA==.',
Hm='Hmmisee:BAAALgAECgEJBAAAAA==.',
Ho='Hoakaren:BAABLgAECn8ZAAIXAAkJAxZ5MAAEAgAXAAkJAxZ5MAAEAgAAAA==.Hobiscuits:BAEALgADCgQJBAABLgAECgkJJAANAL4eAA==.Hocus:BAAALgADCgYJBgAAAA==.Holde:BAAALgAECgUJDQAAAA==.Hornyrott:BAAALgAECgQJBgAAAA==.',
Hu='Hunterzamb:BAAALgAECgEJAQAAAA==.Huntinator:BAABLgAECn8VAAIEAAcJHhtwMADvAQAEAAcJHhtwMADvAQAAAA==.',
Hy='Hydrobubble:BAABLgAECn8UAAQBAAcJex6KBgDUAQABAAYJLx2KBgDUAQAWAAQJKg+8cwCQAAAZAAEJ5gwCQAAwAAAAAA==.',
['Há']='Hátfield:BAAALgADCgEJAQAAAA==.',
Ih='Ihyo:BAAALgAECgEJAQAAAA==.',
Il='Illyy:BAABLgAECn8mAAICAAgJMgvgNgAkAQACAAgJMgvgNgAkAQAAAA==.',
Im='Impkingguy:BAAALgADCgYJBgAAAA==.',
In='Indawhole:BAACLgAFFH8kAAIXAAkJFxe3FwD0AQAXAAkJFxe3FwD0AQAuAAQKfxoAAhcACAl8JfcjAEACABcACAl8JfcjAEACAAAA.Innatecurse:BAAALgAECgEJAQAAAA==.Instakill:BAAALgAECgIJAQAAAA==.',
Ir='Iridori:BAABLgAECn8wAAICAAgJuCB+CwCvAgACAAgJuCB+CwCvAgAAAA==.Irönfist:BAAALgADCgkJEgAAAA==.',
It='Itzzender:BAAALgADCgIJAgAAAA==.',
Iz='Izumiwitabow:BAABLgAECn8gAAIEAAgJFRQ2ZwB1AQAEAAgJFRQ2ZwB1AQAAAA==.',
Ja='Jabberthehut:BAAALgAFFAEJAQAAAA==.Jadé:BAAALgADCgMJAwAAAA==.Jamerius:BAAALgAECgIJAgAAAA==.Jankovic:BAAALgADCgcJBwAAAA==.Jasmean:BAAALgADCgcJDwAAAA==.Javaluminous:BAABLgAECn8oAAIJAAgJQCBfLABQAgAJAAgJQCBfLABQAgAAAA==.Jay:BAABLgAFFH8GAAIRAAMJjxDyQwC2AAARAAMJjxDyQwC2AAABLgAFFAcJFQAjAJcWAA==.Jaytsukitori:BAACLgAFFH8fAAMGAAYJpx8YDgATAgAGAAYJpx8YDgATAgAMAAMJMxJ/FQDDAAAuAAQKfx8AAwYACQljILkMANcCAAYACQljILkMANcCAAwAAQlmEESNADMAAAAA.',
Jh='Jhaeriao:BAAALgAECgYJDAAAAA==.Jhantherox:BAAALgAECgYJBgAAAA==.',
Jo='Joesepi:BAABLgAFFH8eAAIKAAYJ6xpyKQDDAQAKAAYJ6xpyKQDDAQAAAA==.Joham:BAAALgAECgEJAQAAAA==.Jojosus:BAAALgADCgcJBwABLgADCgkJRAAVAAAAAA==.Jonah:BAAALgAFFAEJAQABLgAFFAIJBQAKAB4YAA==.Joodee:BAAALgADCggJCQAAAA==.',
Ju='Judgeroybean:BAAALgAECgMJAwAAAA==.Juliofoolioo:BAAALgAECgEJAgAAAA==.',
Ka='Karti:BAAALgADCgQJBAAAAA==.Katrine:BAAALgAECgkJDwAAAA==.Kayahli:BAAALgAECgQJBAAAAA==.Kazghul:BAAALgADCgEJAQAAAA==.',
Ke='Kelaeus:BAABLgAECn8VAAIOAAYJUQ5x0ABMAQAOAAYJUQ5x0ABMAQAAAA==.Kendreth:BAAALgADCgIJAgAAAA==.Keyonslayz:BAAALgADCggJCAAAAA==.',
Kh='Khrønos:BAAALgAECggJDAAAAA==.',
Ki='Kij:BAEBLgAFFH8OAAIOAAgJHxNqDQAiAgAOAAgJHxNqDQAiAgAAAA==.Killzom:BAAALgADCgEJAQABLgAFFAQJCwAPACkVAA==.Kilrah:BAABLgAECn82AAIaAAkJahbdEgABAgAaAAkJahbdEgABAgAAAA==.Kirian:BAAALgADCgEJAQAAAA==.Kissmyash:BAABLgAECn8WAAIOAAYJ9Amd0wDtAAAOAAYJ9Amd0wDtAAAAAA==.Kissmycrits:BAABLgAECn8ZAAIEAAQJsB2QgwA3AQAEAAQJsB2QgwA3AQAAAA==.Kissmywrath:BAAALgAECgEJAQAAAA==.Kiyana:BAABLgAECn8wAAIaAAgJ6hATLQAZAQAaAAgJ6hATLQAZAQAAAA==.Kiyoine:BAABLgAECn8iAAIQAAgJKRkSDAD4AQAQAAgJKRkSDAD4AQAAAA==.',
Kn='Knocksteady:BAACLgAFFH8VAAIJAAcJOhehCgBXAQAJAAcJOhehCgBXAQAuAAQKfyAAAgkABwm2IYskAJUCAAkABwm2IYskAJUCAAAA.Knoxform:BAAALgAECgMJBAAAAA==.Knoxhops:BAAALgAECgMJAwABLgAECgMJBAAVAAAAAA==.Knoxreaps:BAAALgAECgYJBAABLgAECgMJBAAVAAAAAA==.Knoxstaggers:BAABLgAECn8lAAIkAAgJ3iBWEwAXAgAkAAgJ3iBWEwAXAgABLgAECgMJBAAVAAAAAA==.',
Ko='Korozzma:BAAALgADCgYJBgABLgADCgMJAwAVAAAAAA==.',
Kr='Krzzy:BAAALgAFFAIJAgABLgAFFAgJDQAWAMcVAA==.',
Ku='Kuray:BAAALgAECgEJAgAAAA==.',
Ky='Kyleclark:BAAALgADCgUJBQAAAA==.Kynbrookera:BAABLgAECn8iAAIGAAkJFQy9RQB5AQAGAAkJFQy9RQB5AQAAAA==.Kyujin:BAAALgADCgEJAQAAAA==.',
['Kì']='Kìnky:BAABLgAECn8UAAISAAgJChcXMQCIAQASAAgJChcXMQCIAQAAAA==.',
La='Laetha:BAAALgADCgUJBQABLgAECgkJIAARAHUZAA==.',
Le='Lemicall:BAAALgADCgQJCAAAAA==.Lethiferous:BAAALgAECgIJAgAAAA==.Letmespankit:BAAALgADCgYJDAAAAA==.Lezigo:BAABLgAECn8jAAIOAAkJaBQdSwD6AQAOAAkJaBQdSwD6AQAAAA==.',
Lh='Lhynne:BAAALgAECgEJAQAAAA==.',
Li='Licht:BAAALgAECgYJDQAAAA==.Lik:BAAALgAECgQJBwAAAA==.Lilhorror:BAAALgADCgMJAwAAAA==.Lilpyro:BAAALgAECgQJBAAAAA==.Lilyheart:BAAALgADCgYJBgAAAA==.Linai:BAABLgAECn8tAAMjAAkJHhIwBABhAQAjAAkJHhIwBABhAQAlAAgJEQggDwAyAQAAAA==.Lit:BAAALgAECgEJAwAAAA==.Littledog:BAACLgAFFH8KAAILAAQJbRQMGQAfAQALAAQJbRQMGQAfAQAuAAQKfy4AAwsACQnXFZocAOABAAsACQnXFZocAOABACAABAlyFq09AL8AAAAA.Liz:BAAALgADCgEJAQABLgAECgUJDQAVAAAAAA==.',
Lo='Lockdout:BAAALgADCgEJAQABLgAECggJGQAOANkWAA==.Loky:BAACLgAFFH8HAAINAAIJWht4jwClAAANAAIJWht4jwClAAAuAAQKfyUABA0ACQkCH8c8AOgBAA0ACQncHsc8AOgBAB4ABAl+GMskADUBABgAAQl6ISwwAF4AAAAA.Longshanks:BAAALgADCgUJDAAAAA==.Longshenks:BAAALgAECgEJAQAAAA==.Lorna:BAAALgADCgEJAQAAAA==.Lotten:BAAALgAECgUJDAAAAA==.',
Lu='Luckevin:BAAALgAECgYJDgAAAA==.Lumianir:BAAALgAECgEJAwAAAA==.Lunitari:BAABLgAECn8dAAImAAYJ8Qv3AgCoAAAmAAYJ8Qv3AgCoAAAAAA==.Luthiean:BAAALgADCgQJBAAAAA==.Luthran:BAAALgAECgUJCwABLgAECggJGAAQAD8PAA==.',
Ly='Lynnali:BAAALgADCggJEQAAAA==.Lyrrin:BAAALgADCgYJBgAAAA==.',
Ma='Magedon:BAAALgAECgEJAQAAAA==.Mageyoulaugh:BAABLgAECn8ZAAIOAAgJ2RZhYAC/AQAOAAgJ2RZhYAC/AQAAAA==.Magezamb:BAAALgAECgUJDQAAAA==.Magicmann:BAAALgAECgEJAQAAAA==.Magmash:BAAALgADCggJDwAAAA==.Mahito:BAAALgADCgEJAQAAAA==.Mahru:BAAALgADCgYJCAAAAA==.Majhduul:BAAALgAECgIJAgAAAA==.Malafang:BAABLgAECn8XAAIJAAcJEgYSBQGyAAAJAAcJEgYSBQGyAAAAAA==.Malanah:BAABLgAECn8cAAILAAkJwQ8yDADcAAALAAkJwQ8yDADcAAAAAA==.Marandra:BAAALgAECgQJCwAAAA==.Marlie:BAAALgAECgMJAwAAAA==.Mathalios:BAAALgAECgIJAgAAAA==.Mattu:BAABLgAECn8aAAIhAAcJXQMXDgCDAAAhAAcJXQMXDgCDAAAAAA==.Maverick:BAACLgAFFH8VAAIjAAcJlxanCABiAQAjAAcJlxanCABiAQAuAAQKfxwAAyMACAkiIsIVAGECACMACAkcIsIVAGECACUABAmBIpcMAFgBAAAA.Maxbaba:BAAALgAECgEJAQAAAA==.',
Mc='Mcskittelz:BAAALgADCgQJBAAAAA==.',
Me='Meleshanorak:BAAALgADCgUJCgAAAA==.Metaunmeta:BAAALgAECgMJAwABLgAFFAEJBAAVAAAAAA==.',
Mi='Michaella:BAAALgAECgUJCwAAAA==.Michartson:BAAALgADCgYJBAAAAA==.Mingres:BAABLgAECn8XAAIEAAcJQw9AegBLAQAEAAcJQw9AegBLAQAAAA==.Minipwn:BAAALgAECgEJAQAAAA==.Miramanie:BAAALgADCgYJBgAAAA==.Misdiagnosed:BAAALgADCgIJAgAAAA==.Mistbrewer:BAAALgADCgIJAgAAAA==.',
Mk='Mk:BAEBLgAECn8UAAIXAAYJ8RaoFADOAAAXAAYJ8RaoFADOAAABLgAECgkJTQAnAIoiAA==.',
Mo='Mogar:BAACLgAFFH8KAAIfAAQJPRXOCAAfAQAfAAQJPRXOCAAfAQAuAAQKfx8AAh8ACAkRHjwMACMCAB8ACAkRHjwMACMCAAAA.Mogina:BAAALgADCggJCAAAAA==.Monkish:BAAALgADCgMJAwAAAA==.Monster:BAAALgAECggJCwAAAA==.Moonzhine:BAABLgAECn8jAAITAAkJXhWZFQC/AQATAAkJXhWZFQC/AQAAAA==.Moosejaw:BAAALgAECgcJDwAAAA==.Mordread:BAABLgAECn8VAAMeAAgJiRBSDwBKAQAeAAgJiRBSDwBKAQANAAMJOgnl7ACGAAAAAA==.Morgalruk:BAABLgAFFH8FAAIKAAQJXwQAkQDpAAAKAAQJXwQAkQDpAAAAAA==.',
Mu='Muulgortal:BAAALgAECgIJAgAAAA==.',
My='Myriosheal:BAAALgADCgQJBAAAAA==.Mythx:BAACLgAFFH8pAAQEAAgJnRwDAgCBAQAEAAYJJh0DAgCBAQAFAAQJShIvFwAYAQADAAIJRRR9KwBZAAAuAAQKfysABAQACAlXI3wIAAoDAAQACAlXI3wIAAoDAAUABgn7GLkrAEUBAAMABQkFEe5MAB0BAAAA.',
Na='Nalanelin:BAABLgAECn8WAAIKAAcJKQ0cmAA4AQAKAAcJKQ0cmAA4AQAAAA==.Narukin:BAABLgAECn8cAAIXAAcJVBr+RwCuAQAXAAcJVBr+RwCuAQAAAA==.Nasai:BAAALgAECgcJBwAAAA==.Naturboy:BAAALgADCgYJBgAAAA==.',
Ne='Nemmessiss:BAAALgAECgEJAgAAAA==.Nessirebette:BAAALgADCgUJCAAAAA==.Netherwalker:BAAALgAECgIJAgABLgAFFAkJOwALADMjAA==.Netherward:BAAALgAFFAEJAwABLgAFFAkJOwALADMjAA==.',
Ni='Niknikboy:BAAALgAECgEJAgAAAA==.Nivmizzet:BAACLgAFFH8IAAINAAQJMQ6tIgAFAQANAAQJMQ6tIgAFAQAuAAQKfzAAAw0ACAn4GXJPAKwBAA0ABwl8GnJPAKwBAB4ABgnwFSotAAkBAAAA.',
No='Nolakai:BAAALgAECgEJAQAAAA==.Nomiro:BAAALgAECgYJDAAAAA==.Noradori:BAAALgAECgEJAQAAAA==.Notdip:BAAALgADCgIJAgAAAA==.Novalea:BAACLgAFFH8PAAMBAAQJ1yUgFwCtAQABAAQJ1yUgFwCtAQAWAAEJVwguOQAzAAAuAAQKf00AAwEACQlhIwwFAGMDAAEACQlhIwwFAGMDABYABwkeHkAuAIkBAAAA.',
Nu='Nuru:BAAALgAECgcJEAAAAA==.Nutcutter:BAAALgAECgYJDgABLgAECggJMwAKAIYRAA==.',
['Nø']='Nøstalgic:BAAALgAECgEJAgAAAA==.',
Ob='Obala:BAAALgADCgIJAgAAAA==.',
Od='Odogaren:BAABLgAECn8ZAAMiAAgJzxxbCwBYAgAiAAcJgB1bCwBYAgASAAgJhRoVIQBLAgAAAA==.',
Om='Omnithorn:BAAALgAECggJDQAAAA==.',
On='Onei:BAAALgADCgEJAQAAAA==.',
Or='Oramos:BAAALgAECgQJBgAAAA==.Orgóndó:BAABLgAFFH8NAAITAAYJmR0vEACAAQATAAYJmR0vEACAAQAAAA==.',
Ov='Ova:BAAALgAECgYJCgAAAA==.Ovelaa:BAAALgAECgQJBAAAAA==.',
Ox='Oxxo:BAABLgAECn8tAAImAAgJ5RNBAQBLAQAmAAgJ5RNBAQBLAQAAAA==.',
Pa='Palzamb:BAAALgADCgYJCwAAAA==.Pandacillin:BAAALgAECgQJBAAAAA==.Paraggonn:BAABLgAECn87AAIEAAgJBB4ZBgAiAgAEAAgJBB4ZBgAiAgAAAA==.',
Pe='Penelöpe:BAAALgAECgMJBQAAAA==.Penoosê:BAAALgADCgEJAgAAAA==.Pepperice:BAAALgADCgIJAgAAAA==.Perlonis:BAAALgAECgYJEwAAAA==.',
Ph='Phatocaster:BAAALgADCgIJBAAAAA==.Pherkle:BAAALgAECggJEAABLgAFFAQJDAAZACkPAA==.Phoinyx:BAAALgAECgkJDwAAAA==.Phuriosa:BAABLgAECn8WAAIjAAcJ8w8JBgAbAQAjAAcJ8w8JBgAbAQABLgAFFAMJCQAGAO8VAA==.Phury:BAACLgAFFH8JAAIGAAMJ7xWgOQDHAAAGAAMJ7xWgOQDHAAAuAAQKfykAAwYACQlyGoknABQCAAYACAlAGYknABQCAAwAAgkmF9lgAJYAAAAA.Physta:BAAALgADCggJCwAAAA==.',
Pi='Pizza:BAABLgAECn8wAAIPAAgJlhglAwCuAQAPAAgJlhglAwCuAQAAAA==.',
Pl='Plagafel:BAAALgADCgYJBgAAAA==.',
Po='Pomomies:BAAALgAFFAMJAwAAAA==.Pooseunpoose:BAAALgAFFAEJBAAAAA==.Porkmancer:BAAALgAECgYJCgABLgAECgkJJgAKAEwfAA==.Porkslope:BAABLgAECn8mAAIKAAgJTB+vJgBoAgAKAAgJTB+vJgBoAgAAAA==.',
Pr='Praahv:BAAALgADCgYJBgAAAA==.Prayhole:BAAALgADCgYJBgAAAA==.Profryktor:BAABLgAECn8eAAMfAAcJrReMBgDhAAAfAAcJrReMBgDhAAAiAAEJyxOoEQA6AAAAAA==.',
Pu='Purebloods:BAAALgADCgEJAQAAAA==.Purpleparrot:BAABLgAECn8dAAIBAAkJ8gh7DQA1AQABAAkJ8gh7DQA1AQAAAA==.',
Qu='Quickben:BAAALgAECgIJAgAAAA==.',
Ra='Raenyx:BAABLgAECn9AAAMNAAgJ3x5THgBvAgANAAgJ3x5THgBvAgAYAAMJag4hLABrAAAAAA==.Raiflock:BAABLgAECn8cAAIYAAkJBxSgCQDJAQAYAAkJBxSgCQDJAQAAAA==.Raiif:BAAALgAECgQJAwABLgAECgkJHAAYAAcUAA==.Ranalastus:BAAALgAECgYJDgAAAA==.Raveneyes:BAEBLgAECn8jAAINAAkJjhFDRQDLAQANAAkJjhFDRQDLAQAAAA==.Rayn:BAAALgAECgMJAwAAAA==.',
Re='Reiena:BAAALgAECgcJEAAAAA==.Relas:BAAALgADCgUJBQAAAA==.Reylilyn:BAABLgAECn8oAAIcAAkJqBUVGwA/AgAcAAkJqBUVGwA/AgAAAA==.Reynarena:BAAALgAECgYJEAAAAA==.',
Rh='Rhaenfyre:BAABLgAECn8jAAMXAAkJMBVGOgDeAQAXAAkJMBVGOgDeAQAdAAEJ9QzwOAAlAAAAAA==.',
Ri='Richardhurtz:BAAALgAECgYJCwAAAA==.Rick:BAAALgAECgEJAgAAAA==.Ricola:BAAALgAFFAIJBAAAAA==.Rivenel:BAACLgAFFH8ZAAIeAAgJZBNgAQCgAQAeAAgJZBNgAQCgAQAuAAQKfykAAx4ACQkgIkMCAJ0CAB4ACAlaI0MCAJ0CAA0AAQmHGbQdAUoAAAAA.Rivèn:BAAALgADCgEJAQAAAA==.',
Ro='Robinvoid:BAABLgAECn8dAAMXAAkJgCAPFQDZAgAXAAkJgCAPFQDZAgAaAAEJ+RRiaQBAAAAAAA==.Rocksann:BAAALgAECgEJBAAAAA==.Rodel:BAAALgAECgEJAgABLgAECgMJAwAVAAAAAA==.Roquan:BAABLgAECn8wAAIbAAgJ7RvhCAD8AQAbAAgJ7RvhCAD8AQAAAA==.Roulette:BAAALgAECgUJDwAAAA==.',
Ru='Rubmyrott:BAABLgAFFH8HAAIOAAUJcAUKeADpAAAOAAUJcAUKeADpAAAAAA==.Runalot:BAAALgAECgYJBwAAAA==.Rundas:BAAALgADCgMJAwABLgAECgkJIwAkANkcAA==.Runelle:BAAALgADCgQJBAAAAA==.Rush:BAAALgAECgEJAQAAAA==.',
['Ré']='Rébél:BAAALgADCgEJAQAAAA==.',
['Rê']='Rêdd:BAABLgAECn8cAAILAAcJXxHCLwBgAQALAAcJXxHCLwBgAQAAAA==.',
Sa='Sabeion:BAAALgAECgYJDAAAAA==.Saboo:BAAALgAECgQJAQABLgAFFAEJAQAVAAAAAA==.Sadiebuding:BAAALgAECgEJAQAAAA==.Salswarriah:BAABLgAECn8lAAISAAgJ1xBZOQBhAQASAAgJ1xBZOQBhAQAAAA==.Sanaku:BAAALgAECgYJCAAAAA==.Sanangra:BAAALgADCgEJAQAAAA==.Santo:BAAALgADCgMJAwAAAA==.Sarlyan:BAAALgADCgkJFwAAAA==.Sassafrazz:BAAALgAECgQJBAAAAA==.',
Sc='Scrumbles:BAAALgAECgkJDwAAAA==.',
Se='Sealgair:BAAALgADCgMJAwAAAA==.Secksytoes:BAAALgAECgMJAwABLgADCgYJCwAVAAAAAA==.Segador:BAAALgADCgMJAwAAAA==.Seis:BAAALgAECgEJAQABLgAFFAEJAQAVAAAAAA==.Seraphim:BAAALgADCgEJAQAAAA==.Serion:BAAALgADCgMJAwAAAA==.Sewerrat:BAAALgADCggJCAAAAA==.',
Sg='Sgtbonesnap:BAAALgAECgcJDwAAAA==.Sgtpunchy:BAAALgADCgMJBQABLgAECgcJDwAVAAAAAA==.',
Sh='Shadowslam:BAAALgAECgEJAQABLgAECgkJAQAVAAAAAA==.Shakuro:BAAALgAECgEJAgAAAA==.Shallash:BAAALgAECgEJAQAAAA==.Shamageddon:BAAALgAECgIJBAAAAA==.Shamanizim:BAACLgAFFH8XAAMWAAYJcRaRCwBzAQAWAAYJcRaRCwBzAQAZAAIJsQidFgA5AAAuAAQKfyoABBYACAmUHEIdAPcBABYACAkpHEIdAPcBABkABwnlFb8XAEwBAAEAAgknBmjQADsAAAAA.Shaniquua:BAAALgADCgMJAwAAAA==.Shausin:BAAALgAECggJCAAAAA==.Sheeanna:BAAALgAFFAEJAQABLgAFFAQJDgAUADgjAA==.Shiftmyself:BAAALgADCgkJDgAAAA==.Shikigami:BAAALgAECgkJBwAAAA==.Shinoikari:BAACLgAFFH8KAAIbAAIJjQZNFQBlAAAbAAIJjQZNFQBlAAAuAAQKfygAAxsACQkNEcYKAM8BABsACQkNEcYKAM8BABMABQnJCKJDAIAAAAAA.Shinotenshi:BAABLgAECn8bAAQgAAcJtwm9OQAqAQAgAAcJvAi9OQAqAQACAAUJBweMYgCmAAALAAEJKAR6lQAlAAABLgAFFAIJCgAbAI0GAA==.Shirase:BAABLgAECn8eAAMNAAkJdw7VbQBgAQANAAkJHgzVbQBgAQAYAAYJRQ4eGAADAQABLgAFFAQJDwABANclAA==.Shugarae:BAABLgAECn8cAAMMAAgJPQgVPgAXAQAMAAgJPQgVPgAXAQAGAAUJcATcnwBwAAAAAA==.',
Si='Sigsauer:BAAALgAECggJEAAAAA==.Sionnocht:BAAALgADCgEJAQAAAA==.Sirlemage:BAAALgADCgMJAwAAAA==.',
Sk='Skina:BAAALgAECgEJAQAAAA==.Skotonyx:BAAALgAECgkJCQAAAA==.Skreezy:BAAALgAECgcJDAAAAA==.Skuls:BAAALgAECgMJBwAAAA==.',
Sl='Slashemup:BAABLgAECn8jAAIaAAkJ+RYpEgAKAgAaAAkJ+RYpEgAKAgAAAA==.Slayter:BAABLgAECn8lAAIGAAkJ2R8yHQBdAgAGAAkJ2R8yHQBdAgABLgAFFAEJAQAVAAAAAA==.Slithiss:BAAALgADCgIJAgAAAA==.',
Sm='Smaugin:BAAALgAECgIJAgAAAA==.Smaugor:BAAALgAECgEJAQABLgAFFAIJAgAVAAAAAA==.',
Sn='Snakelazers:BAACLgAFFH8IAAIcAAQJgiEwHgB+AQAcAAQJgiEwHgB+AQAuAAQKfyUAAhwACQn6IrQEAGMDABwACQn6IrQEAGMDAAAA.Snufulafagus:BAABLgAECn8WAAIQAAUJbRtlGgA6AQAQAAUJbRtlGgA6AQAAAA==.',
So='Soju:BAABLgAECn8oAAMBAAkJ9BdkGwBwAgABAAkJ9BdkGwBwAgAWAAQJJxKYbQCgAAABLgAECgkJLAAEAMkjAA==.Soliloquy:BAAALgAECgkJEQAAAA==.Songwind:BAABLgAECn8qAAInAAgJYg3QLQBUAQAnAAgJYg3QLQBUAQAAAA==.Soonie:BAAALgADCgEJAQAAAA==.Soulreever:BAAALgADCggJCAAAAA==.',
Sq='Squishyman:BAACLgAFFH8HAAMNAAMJ0BqGJQD1AAANAAMJ0BqGJQD1AAAYAAEJlAJMGQAyAAAuAAQKfx0AAg0ABwlTIiMDAFoCAA0ABwlTIiMDAFoCAAEuAAUUBAkJAAkAPBUA.Squishypal:BAACLgAFFH8JAAIJAAQJPBUZGwAfAQAJAAQJPBUZGwAfAQAuAAQKfx0AAwkACQl8Ho8VAMECAAkACQl8Ho8VAMECACgAAQnrFiM/AEEAAAAA.',
St='Starfirelmao:BAAALgAECgYJDwAAAA==.Steelcure:BAAALgAECgkJEwAAAA==.Strabo:BAAALgADCggJCQAAAA==.Strawdicks:BAAALgAECgcJAQAAAA==.',
Su='Sugma:BAAALgAECgEJAQAAAA==.Suzsette:BAABLgAECn8kAAILAAgJKhCHCwDnAAALAAgJKhCHCwDnAAAAAA==.',
Sy='Sylris:BAAALgADCgkJFgAAAA==.Sylvanthis:BAAALgAECgQJBAABLgAECgkJIgAGABUMAA==.',
['Sç']='Sçoxx:BAAALgADCgEJAQAAAA==.',
Ta='Taazdingo:BAAALgADCgEJAQAAAA==.Taeleth:BAAALgADCgcJBwAAAA==.Talnora:BAAALgAECgYJDwAAAA==.Tardovski:BAABLgAECn8lAAMEAAkJGSEtEADPAgAEAAkJGSEtEADPAgADAAQJ2BP2VgDsAAAAAA==.Taurentino:BAAALgAECgkJBQAAAA==.',
Te='Telaris:BAAALgADCgIJAgAAAA==.Telda:BAABLgAECn8bAAIlAAcJGAdtAwDEAAAlAAcJGAdtAwDEAAAAAA==.Teneturadvos:BAAALgAECgEJAQABLgAFFAEJAgAVAAAAAA==.Teneturadvós:BAAALgAECgkJDgABLgAFFAEJAgAVAAAAAA==.Tentreeadvos:BAAALgAECgEJAQABLgAFFAEJAgAVAAAAAA==.Terrorbear:BAAALgAECgYJBgAAAA==.Tetris:BAACLgAFFH8dAAIOAAUJ3hx9KAAnAQAOAAUJ3hx9KAAnAQAuAAQKfzgAAg4ACQmgIlwWANMCAA4ACQmgIlwWANMCAAAA.',
Th='Thellaria:BAAALgAECgYJBwAAAA==.Thraggoar:BAAALgADCgEJAQAAAA==.Thunsar:BAAALgAECgkJDwAAAA==.Thuzzad:BAAALgADCgUJBQAAAA==.',
Ti='Tickler:BAAALgAECgUJEQAAAA==.Tiroelin:BAAALgAECgUJBwAAAA==.',
To='Toetem:BAAALgADCgQJBgAAAA==.Tosselus:BAAALgAECgEJAwAAAA==.Tox:BAAALgADCgUJBQAAAA==.Toyotama:BAAALgAFFAIJAgABLgAFFAYJHwAGAKcfAA==.',
Tr='Tragedeigh:BAAALgAECgUJBQABLgAECgkJKQAHAEMaAA==.Trane:BAAALgAECgIJAgAAAA==.Trañsformer:BAAALgAFFAIJAgAAAA==.Treala:BAAALgADCggJCAABLgAECgkJHAALAMEPAA==.Tritoch:BAAALgAECgYJEAAAAA==.Troche:BAACLgAFFH8JAAIoAAQJEQh9DACwAAAoAAQJEQh9DACwAAAuAAQKfxgAAygACQmDESIQAMIBACgACQmDESIQAMIBABQAAQlNCEKYACgAAAAA.Truthfully:BAABLgAECn8WAAIJAAkJPQ4dEQA+AQAJAAkJPQ4dEQA+AQAAAA==.Trávpac:BAAALgADCgEJAQAAAA==.',
Tt='Ttjpll:BAAALgAFFAEJAQAAAA==.',
Tu='Tubs:BAAALgAECgEJAQAAAA==.Tuckncloak:BAAALgAECgMJAwAAAA==.',
Tw='Twohand:BAAALgADCgIJBAAAAA==.',
['Tî']='Tîmon:BAAALgAFFAIJAgABLgAFFAIJAgAVAAAAAA==.',
Ug='Ugrup:BAAALgAECgcJEgAAAA==.',
Uj='Ujabula:BAAALgAECgYJEgAAAA==.',
Ul='Ulurak:BAABLgAECn8YAAMQAAgJPw8aGwAaAQAQAAYJkwkaGwAaAQAGAAQJ9QqjpgBlAAAAAA==.',
Um='Umaguma:BAAALgAECgUJAwAAAA==.',
Un='Uncleskip:BAABLgAECn8bAAIfAAcJ0wd0FgBJAQAfAAcJ0wd0FgBJAQAAAA==.Unhappytoast:BAABLgAECn8WAAIoAAkJdBgpCgAoAgAoAAkJdBgpCgAoAgAAAA==.Unstobubble:BAAALgAECgYJCQAAAA==.',
Va='Valeriya:BAAALgADCgcJCAABLgAECgMJAwAVAAAAAA==.Valisanna:BAAALgAECgEJBAAAAA==.Valklemor:BAAALgAECgUJBgAAAA==.Vallorien:BAABLgAECn8lAAIoAAgJpyAGCwAZAgAoAAgJpyAGCwAZAgAAAA==.Valsharess:BAAALgADCgcJBwABLgAECgkJOAAXAEEaAA==.',
Ve='Vegetagos:BAAALgAECgQJBgAAAA==.Vegtam:BAAALgAECgEJAQAAAA==.Velaryn:BAAALgAFFAIJAgAAAA==.Velnia:BAAALgAECgYJCwAAAA==.Verencia:BAAALgAECgEJAQAAAA==.',
Vi='Vildaren:BAAALgAECgUJCQAAAA==.Vivachel:BAAALgADCgcJCAAAAA==.Viztrix:BAAALgADCgEJAgAAAA==.',
Vo='Vorsan:BAAALgADCgcJBwAAAA==.Vorsane:BAAALgADCgQJBAAAAA==.',
['Và']='Vàli:BAAALgAECgcJEgAAAA==.',
Wa='Wanks:BAAALgAECgYJDwAAAA==.Warmoon:BAAALgAECgMJAwAAAA==.Warskul:BAAALgAECgEJAQAAAA==.Wasenshi:BAAALgADCgUJBQAAAA==.',
We='Weeb:BAAALgADCgUJCwAAAA==.Weeny:BAAALgAECgcJCwAAAA==.',
Wh='Whiffle:BAAALgAECgcJDAAAAA==.Wholy:BAAALgAECgMJBgAAAA==.',
Wi='Wickedromeo:BAAALgAECgMJAwAAAA==.',
Wo='Wolfmother:BAABLgAECn8jAAIWAAgJpxS2KgCdAQAWAAgJpxS2KgCdAQAAAA==.Wolvarro:BAAALgADCgMJAwAAAA==.',
Xa='Xaanii:BAABLgAECn8iAAIUAAgJ4hxeIwDqAQAUAAgJ4hxeIwDqAQAAAA==.Xandius:BAAALgADCgcJDAAAAA==.Xarferrin:BAABLgAECn8vAAIOAAgJXAbtHADcAAAOAAgJXAbtHADcAAAAAA==.Xarnethia:BAAALgAECgQJBAAAAA==.',
Xe='Xeeria:BAACLgAFFH8jAAIBAAcJwBGtLQAsAQABAAcJwBGtLQAsAQAuAAQKfzAAAwEACQnyHwoNALUCAAEACQnyHwoNALUCABYAAQlXG8aSAE4AAAAA.Xenzull:BAAALgAECgIJAgAAAA==.',
Xi='Xidane:BAAALgAECgIJAgAAAA==.',
Xk='Xkaliber:BAAALgADCgEJAQAAAA==.',
Xu='Xuecat:BAABLgAECn8kAAIGAAgJ3xYQLgD1AQAGAAgJ3xYQLgD1AQAAAA==.',
Yn='Yn:BAAALgAECgYJDAAAAA==.',
Za='Zamzak:BAAALgADCgQJBAABLgAECgEJAQAVAAAAAA==.Zanthor:BAACLgAFFH8IAAIKAAIJ/AT2bwBuAAAKAAIJ/AT2bwBuAAAuAAQKfxsAAxsABgloDmUJAJcAAAoABgnDCr73ALcAABsAAwn3D2UJAJcAAAAA.Zaralina:BAACLgAFFH8IAAILAAQJBglwIQDoAAALAAQJBglwIQDoAAAuAAQKfzQAAgsACQlPF3ISAEACAAsACQlPF3ISAEACAAAA.Zartox:BAABLgAECn8cAAIpAAkJoRa3AgAaAgApAAkJoRa3AgAaAgAAAA==.Zaryn:BAAALgADCgIJAgAAAA==.Zarynth:BAAALgAECgEJAQAAAA==.Zaryssa:BAABLgAECn8eAAIWAAgJjwUSUwDtAAAWAAgJjwUSUwDtAAAAAA==.Zavinus:BAAALgADCgYJCAAAAA==.',
Ze='Zeena:BAAALgAECgEJAQAAAA==.Zenzug:BAAALgAECgUJDwAAAA==.Zephystra:BAAALgADCgQJBAABLgAFFAQJDwABANclAA==.Zeusqt:BAAALgADCgYJBgAAAA==.',
Zh='Zharfrost:BAAALgAECgYJCAAAAA==.',
Zi='Zicroniah:BAAALgADCgYJCgAAAA==.Zimfestation:BAABLgAFFH8JAAIKAAMJxBUvPQDdAAAKAAMJxBUvPQDdAAABLgAFFAYJFwAWAHEWAA==.Zimquisition:BAAALgAFFAMJAwABLgAFFAYJFwAWAHEWAA==.Zinwaz:BAAALgAECgMJAwAAAA==.Ziyuu:BAAALgADCgUJBQAAAA==.',
Zm='Zmaj:BAAALgAECgEJAQAAAA==.',
Zo='Zombiehunter:BAABLgAECn8jAAIEAAkJaR/9EQDCAgAEAAkJaR/9EQDCAgAAAA==.',
Zu='Zug:BAAALgAECgEJAQAAAA==.Zuzu:BAAALgADCgMJAwAAAA==.',
['Âr']='Ârc:BAAALgAFFAMJAwAAAA==.',
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
