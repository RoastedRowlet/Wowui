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

local lookup = {'Paladin-Retribution','DemonHunter-Havoc','DeathKnight-Unholy','Priest-Holy','Paladin-Protection','Warrior-Fury','Monk-Windwalker','Druid-Restoration','Druid-Balance','Priest-Shadow','Hunter-Marksmanship','DemonHunter-Devourer','Warrior-Protection','Mage-Frost','Paladin-Holy','Shaman-Restoration','Evoker-Preservation','Rogue-Subtlety','Druid-Guardian','Unknown-Unknown','DeathKnight-Blood','Monk-Mistweaver','Shaman-Elemental','Evoker-Augmentation','Hunter-Survival','DeathKnight-Frost','Warlock-Demonology','Rogue-Assassination','Priest-Discipline','Warlock-Destruction','Hunter-BeastMastery','Shaman-Enhancement','Monk-Brewmaster','Druid-Feral','Evoker-Devastation','Mage-Arcane','Rogue-Outlaw','Warrior-Arms','Warlock-Affliction','DemonHunter-Vengeance',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=46,date='2026-08-04',data={Ab='Aberaht:BAABLgAECn8mAAIBAAkJYCOqDQAgAwABAAkJYCOqDQAgAwAAAA==.',
Ad='Adamaro:BAAALgADCgYJCQAAAA==.Adenwey:BAAALgAECggJCQABLgAFFAQJDQACAAobAA==.',
Ae='Aenastian:BAABLgAFFH8IAAIDAAMJSxkhjgDuAAADAAMJSxkhjgDuAAABLgAFFAQJDQACAAobAA==.',
Af='Affrica:BAAALgADCgEJAQABLgAECgkJHAAEAIkOAA==.',
Ag='Agnu:BAAALgADCgcJBwAAAA==.Agraar:BAAALgAECgUJBwAAAA==.',
Ah='Ahgra:BAABLgAECn89AAIBAAkJugyVewB3AQABAAkJugyVewB3AQAAAA==.',
Ak='Akre:BAAALgAFFAIJBgAAAQ==.Akumä:BAAALgAECgUJCgAAAA==.',
Al='Aleannia:BAAALgAECgYJDwAAAA==.Alekz:BAAALgAECgYJDgAAAA==.Alestria:BAABLgAECn8fAAMBAAkJHRaobACVAQABAAkJfBWobACVAQAFAAMJnhdmDACJAAAAAA==.Alibrexia:BAACLgAFFH8PAAIGAAQJTgWPHwCwAAAGAAQJTgWPHwCwAAAuAAQKfyAAAgYACQlrCRE2AHABAAYACQlrCRE2AHABAAAA.Alida:BAABLgAECn8sAAIGAAkJqAo8OABmAQAGAAkJqAo8OABmAQAAAA==.Alithvia:BAAALgAECgYJBgABLgAECgkJJQAHAAskAA==.Allisara:BAAALgADCgkJFgAAAA==.Alysae:BAACLgAFFH8lAAMIAAgJuBg0EQDtAQAIAAgJuBg0EQDtAQAJAAEJSQArWAAZAAAuAAQKfx0AAwgACQlRHOUdAE8CAAgACQlRHOUdAE8CAAkAAgllBxiYACgAAAAA.',
Am='Amabear:BAAALgAECgEJAQABLgAECgcJHAAKAP0cAA==.Ambrosse:BAAALgADCggJDwABLgAECgkJLQAHAHcaAA==.',
An='Anabug:BAAALgAECgMJBQAAAA==.Andelwynn:BAAALgAECgMJBAABLgAECgkJJAALAFsMAA==.Angelsmentor:BAAALgAECgYJCgAAAA==.Aniellas:BAAALgAECgIJAgAAAA==.Annalese:BAAALgAECgEJAQABLgAECgkJJAALAFsMAA==.',
Ar='Arabeli:BAAALgAECgEJAQAAAA==.Arbyss:BAAALgADCgcJDAAAAA==.Ardatha:BAAALgADCgcJFwAAAA==.Ariêz:BAAALgAECgIJAgAAAA==.Artio:BAABLgAECn8iAAMFAAgJMwYrDQB9AAABAAcJVAIgKQGIAAAFAAUJ4QgrDQB9AAAAAA==.',
As='Ashkada:BAAALgADCgQJBAAAAA==.Asterön:BAAALgAECgcJEwAAAA==.Astrocakes:BAAALgAECgMJAwABLgAFFAQJEgAMAMEUAA==.',
At='Athenä:BAACLgAFFH8uAAIFAAkJIBKIAQDYAQAFAAkJIBKIAQDYAQAuAAQKfzwAAgUACQl7HPkFAI4CAAUACQl7HPkFAI4CAAAA.Atsuma:BAABLgAECn8gAAINAAgJIAszJAAPAQANAAgJIAszJAAPAQAAAA==.',
Av='Avacynn:BAAALgAECgMJAwAAAA==.Aviz:BAAALgADCgMJAwAAAA==.',
Aw='Awtysmbb:BAAALgAECgUJBgABLgAFFAMJCgAOABIXAA==.',
Ay='Aylah:BAAALgAECgYJCQABLgAECgcJHAAOAEQcAA==.Aylli:BAAALgAECgYJDAABLgAECgkJRgAEAEwfAA==.',
['Aí']='Aísling:BAABLgAECn82AAIPAAkJFB+JAQCSAgAPAAkJFB+JAQCSAgAAAA==.',
Ba='Baboii:BAAALgADCgIJAgAAAA==.Baconmecrazy:BAAALgAECgEJAQAAAA==.Badinngo:BAAALgADCggJDwABLgAECgkJJAAQABcgAA==.Baela:BAAALgAFFAEJAgABLgAFFAgJCwARAE4WAA==.Bahiu:BAAALgAECgQJBAAAAA==.Bajafresh:BAAALgAECgQJBQAAAA==.Battleshaman:BAAALgADCgYJBgAAAA==.',
Bd='Bd:BAABLgAECn8dAAISAAgJJxU5GABGAgASAAgJJxU5GABGAgAAAA==.',
Be='Beardmedaddy:BAAALgAECgYJBgABLgAECgkJMAAGAI4hAA==.Bearstavious:BAABLgAFFH8KAAITAAMJdRdXDgC2AAATAAMJdRdXDgC2AAAAAA==.Benjinana:BAABLgAECn8cAAMEAAkJiQ6dOwAHAQAEAAkJiQ6dOwAHAQAKAAIJJQPOWgBMAAAAAA==.Benjis:BAAALgAECgIJAQAAAA==.Betterthanu:BAAALgADCgUJBQABLgADCgYJCgAUAAAAAA==.',
Bg='Bg:BAAALgAECgYJBwAAAA==.',
Bi='Bige:BAABLgAECn8QAAIMAAYJxwq8tQC+AAAMAAYJxwq8tQC+AAAAAA==.Bilo:BAAALgAECgYJCAAAAA==.Bitelyus:BAAALgAECgUJCAAAAA==.',
Bl='Blazara:BAAALgAECgEJAQAAAA==.Blessedbymom:BAAALgADCgEJAQAAAA==.Blòódbath:BAAALgAECgMJAwAAAA==.',
Bo='Bobius:BAAALgAECgkJDwAAAA==.Bobohizan:BAAALgADCgQJBAAAAA==.Bohde:BAACLgAFFH8UAAMDAAgJtiJ/HQByAQADAAcJtiJ/HQByAQAVAAEJAAAtUwAAAAAuAAQKfxQAAgMACQkvIe8xAHACAAMACQkvIe8xAHACAAAA.Bolognaman:BAAALgAECgUJDAAAAA==.Bombjovi:BAABLgAECn8gAAMFAAkJchWNDgDaAQAFAAkJchWNDgDaAQAPAAUJlA9ZVADmAAAAAA==.Bountty:BAAALgAECgQJBAAAAA==.',
Br='Braandhon:BAAALgAECgQJBwAAAA==.Brahmsthoven:BAAALgADCgIJAwAAAA==.Brandhoon:BAAALgAECgIJAwAAAA==.Branndhon:BAABLgAECn8yAAIIAAgJSheKAwANAgAIAAgJSheKAwANAgAAAA==.Bronislav:BAAALgAECgEJAQAAAA==.',
Bt='Btrflyprncss:BAAALgADCgMJAwAAAA==.',
Bu='Bubblemedic:BAAALgADCgIJAgAAAA==.Bubbly:BAAALgAECgYJBgABLgAFFAMJDgAWAFceAA==.Budde:BAAALgAECgUJBQAAAA==.Buffaloseven:BAABLgAECn8VAAMPAAcJ9gpMRAAvAQAPAAcJ9gpMRAAvAQABAAUJ9QSqIQGRAAABLgAFFAgJFwAOAOwMAA==.',
Ca='Cairdamane:BAABLgAECn8hAAIXAAkJ5BHuLgCFAQAXAAkJ5BHuLgCFAQAAAA==.Calidrina:BAABLgAECn8iAAIMAAkJMhyIQQDEAQAMAAkJMhyIQQDEAQAAAA==.Caness:BAAALgAECgYJBgAAAA==.Capn:BAAALgAECgYJBgAAAA==.Carm:BAAALgAECgYJBgAAAA==.Caroliná:BAAALgAECgUJDgAAAA==.Catcast:BAAALgAECgUJCAABLgAFFAMJCwARACcPAA==.Catclaw:BAAALgAECgcJBwABLgAFFAMJCwARACcPAA==.',
Ce='Celiri:BAABLgAECn8nAAIHAAkJrxCAIQCjAQAHAAkJrxCAIQCjAQAAAA==.Celldrassil:BAABLgAECn84AAIIAAkJZwhZXQAfAQAIAAkJZwhZXQAfAQAAAA==.Cereel:BAAALgAECgMJAwABLgAFFAQJEgAMAMEUAA==.',
Ch='Chadaracka:BAAALgAECgYJBwAAAA==.Chadjr:BAAALgAECgEJAgAAAA==.Chandelure:BAAALgAECgUJCwAAAA==.Chardaney:BAABLgAECn8kAAILAAkJWwxDEwAqAQALAAkJWwxDEwAqAQAAAA==.Cherryontop:BAABLgAECn83AAIIAAgJ0hXPBgBrAQAIAAgJ0hXPBgBrAQAAAA==.Chido:BAAALgAECgUJBQAAAA==.Chozenone:BAAALgAECgUJEgAAAA==.Chozi:BAAALgAECgYJBwAAAA==.Chromosomie:BAABLgAFFH8JAAIYAAQJWgV5PwDJAAAYAAQJWgV5PwDJAAABLgAECgkJNQAOAH0cAA==.Chuckgnorris:BAAALgAECgUJBQABLgAECgkJNQAOAH0cAA==.',
Ci='Cii:BAABLgAECn8iAAMFAAkJiBAiFwBoAQAFAAgJNRAiFwBoAQABAAYJHw6t2wDkAAAAAA==.',
Co='Coconutwater:BAAALgAFFAEJAQAAAA==.Colandros:BAABLgAECn9EAAIZAAkJjA6oGgDJAQAZAAkJjA6oGgDJAQAAAA==.Colara:BAABLgAECn8sAAIMAAcJEQmTGQC1AAAMAAcJEQmTGQC1AAAAAA==.Colaux:BAAALgADCgkJEAAAAA==.Combobreaker:BAACLgAFFH8OAAIWAAMJVx56LgAAAQAWAAMJVx56LgAAAQAuAAQKfzQAAhYACQm+H/cHAB0DABYACQm+H/cHAB0DAAAA.Comoo:BAAALgAECgEJAQAAAA==.Correct:BAAALgAECgEJAQAAAA==.Cowbôy:BAAALgADCgkJEQAAAA==.',
Cr='Crassberry:BAACLgAFFH8oAAMDAAkJVSNODgBsAgADAAkJVSNODgBsAgAaAAEJkQhnHQA/AAAuAAQKfygAAgMACQk2JBQFAIMDAAMACQk2JBQFAIMDAAAA.Crazyraptor:BAAALgAECgYJDAABLgAECggJFQAbAHcLAA==.Crazèd:BAAALgADCgQJBAAAAA==.Crimes:BAAALgAECgIJAwAAAA==.',
Cu='Cutco:BAABLgAFFH8MAAIcAAUJ3xY3AgAHAQAcAAUJ3xY3AgAHAQAAAA==.',
Cy='Cyndal:BAABLgAECn8cAAIOAAcJRBxNcQCXAQAOAAcJRBxNcQCXAQAAAA==.Cyndle:BAABLgAECn8aAAIHAAYJARy2IwCUAQAHAAYJARy2IwCUAQABLgAECgcJHAAOAEQcAA==.Cyntu:BAAALgAECgUJDwABLgAECgcJHAAOAEQcAA==.',
['Cü']='Cüpid:BAAALgAECgYJBgAAAA==.',
Da='Dada:BAAALgAECgEJAQAAAA==.Dammithells:BAAALgADCgQJBAAAAA==.Dandamar:BAAALgAECgYJBgAAAA==.Dankbreath:BAAALgAECgkJCgABLgAECgkJDQAUAAAAAA==.Dankbuds:BAAALgAECgkJDQAAAA==.Dankfists:BAAALgAECgUJBQABLgAECgkJDQAUAAAAAA==.Dankhaze:BAAALgAFFAIJAgABLgAECgkJDQAUAAAAAA==.Dankreaper:BAAALgAECgkJBQABLgAECgkJDQAUAAAAAA==.Dankshot:BAAALgAECgEJAQABLgAECgkJDQAUAAAAAA==.Danksmash:BAAALgAECgkJCgABLgAECgkJDQAUAAAAAA==.Dankzor:BAAALgAECgcJBQABLgAECgkJDQAUAAAAAA==.Dark:BAAALgADCgEJAQAAAA==.Darkpanther:BAAALgADCgIJAgAAAA==.Darthrevan:BAAALgAECgQJBwAAAA==.Dasharnkal:BAAALgADCgUJCAAAAA==.Dasvult:BAAALgAECgUJCwAAAA==.Dazex:BAABLgAECn8pAAMEAAcJHAbQEwBkAAAdAAUJRwIVXQCLAAAEAAcJGQbQEwBkAAAAAA==.',
De='Deadpump:BAABLgAECn8fAAMbAAcJfRLFegBDAQAbAAcJfRLFegBDAQAeAAQJUQ4aOQDQAAAAAA==.Delainy:BAAALgAECgYJBgAAAA==.Delrus:BAABLgAFFH8HAAIIAAMJ9x1bEQACAQAIAAMJ9x1bEQACAQAAAA==.Demise:BAAALgAECgEJAQAAAA==.Demon:BAABLgAFFH8LAAIMAAUJEBJRIQAJAQAMAAUJEBJRIQAJAQABLgAFFAkJGwABAGcTAA==.Demonsnotkey:BAAALgAECgYJCwAAAA==.Demoxus:BAAALgAECgQJBAAAAA==.Denker:BAAALgADCggJCAAAAA==.Denkzilla:BAAALgADCgIJAgAAAA==.Denzvic:BAAALgAECgEJAQAAAA==.Destro:BAAALgAECgEJAQAAAA==.Deusclaw:BAAALgAECgYJCgAAAA==.Devilah:BAAALgAECgEJAQAAAA==.',
Dh='Dharm:BAABLgAECn8wAAMfAAkJ9BjmMQAUAgAfAAkJ9BjmMQAUAgAZAAIJxQwAUABwAAAAAA==.',
Di='Dialsl:BAAALgADCgUJCQAAAA==.Digbickpanda:BAAALgAECgUJEQABLgAFFAQJEgAMAMEUAA==.Disowneege:BAABLgAECn8oAAIBAAgJuyE/IQCCAgABAAgJuyE/IQCCAgABLgAFFAkJJQAGAGAeAA==.Divinehymn:BAAALgAECgcJBwAAAA==.Diyos:BAAALgADCgYJCgAAAA==.',
Do='Dotndash:BAAALgAECgMJAwAAAA==.Doubledge:BAAALgAECgEJAQAAAA==.Doublejump:BAACLgAFFH8bAAIMAAUJjBN1SQANAQAMAAUJjBN1SQANAQAuAAQKfykAAgwACAk4HgMmADUCAAwACAk4HgMmADUCAAAA.',
Dr='Dragdh:BAAALgAECgcJEwABLgAECggJMgAgACweAA==.Dragnas:BAABLgAECn8yAAQgAAgJLB7rAQDZAQAgAAgJLB7rAQDZAQAQAAcJrBT2PQC2AQAXAAQJvhaKXgDJAAAAAA==.Dragonisa:BAAALgAFFAEJAQAAAA==.Dragun:BAAALgADCgIJAgAAAA==.Draiocht:BAAALgADCgUJCQABLgAECgkJRgAEAEwfAA==.Drakeskid:BAAALgAECgQJBwABLgAFFAQJBgAhALgKAA==.Drakthall:BAAALgAECgIJAwAAAA==.Dralionethny:BAAALgAECgIJAgAAAA==.Dramakiller:BAABLgAECn8cAAMfAAgJDgyDlAAXAQAfAAgJDgyDlAAXAQALAAMJPAKLOAA9AAAAAA==.Drchi:BAAALgAECgEJAQABLgAECgkJHAAiACoWAA==.Drcornbread:BAABLgAECn8cAAMiAAkJKhbUGgA2AQAiAAkJKhbUGgA2AQATAAEJ0AMnigATAAAAAA==.Drcornellia:BAAALgAECgUJCAABLgAECgkJHAAiACoWAA==.Drdarkskin:BAAALgAECgcJDQAAAA==.Drdreggs:BAABLgAECn8pAAMeAAkJmBZhEQAwAQAbAAgJuBSYTwDZAQAeAAYJmxdhEQAwAQAAAA==.Dreggs:BAAALgADCgcJEwAAAA==.Drewskie:BAAALgADCgQJBAAAAA==.Drizztin:BAAALgADCgEJAQAAAA==.Drprominus:BAABLgAECn8gAAIPAAgJACLaCQDuAgAPAAgJACLaCQDuAgAAAA==.Drthargyll:BAAALgADCgYJDgABLgAECggJIAAPAAAiAA==.Drvoid:BAAALgAECgEJAQAAAA==.',
Du='Dungaru:BAAALgAECgkJCQAAAA==.Durden:BAAALgAECgcJDAABLgAFFAQJCAAWAAwIAA==.Dushman:BAAALgAECgEJAgAAAA==.',
Dy='Dykdanglr:BAAALgADCgYJBgABLgAECgQJCAAUAAAAAA==.',
['Dí']='Dígifóx:BAAALgAECgEJAwAAAA==.Dígífóx:BAAALgAFFAEJAQAAAA==.',
Ea='Earthereal:BAABLgAECn83AAIWAAkJ5hePFQBtAgAWAAkJ5hePFQBtAgAAAA==.',
El='Elastar:BAABLgAECn8mAAINAAkJ6RYKDgApAgANAAkJ6RYKDgApAgAAAA==.Ellimist:BAECLgAFFH8qAAIQAAkJUx6AAwBMAgAQAAkJUx6AAwBMAgAuAAQKfykAAxAACQl9G3QXAFoCABAACQl9G3QXAFoCABcABQk0FxdQAAcBAAAA.Elsan:BAAALgAECgEJAQAAAA==.Elycee:BAACLgAFFH8IAAIfAAMJyyXKRwAeAQAfAAMJyyXKRwAeAQAuAAQKfyIAAx8ACQmtJcwIABMDAB8ACAk+JswIABMDAAsACAmWGZYgACECAAAA.Elysria:BAAALgADCgYJBgAAAA==.Elí:BAAALgAECgQJBAAAAA==.',
En='Encrid:BAAALgAECgcJDwABLgAFFAMJCwAYAGUZAA==.Enhasa:BAABLgAECn8gAAIDAAkJ/hUnMQA6AgADAAkJ/hUnMQA6AgABLgAECgYJGgABAOggAA==.Enoeht:BAABLgAECn82AAICAAkJ2gsiIQBvAQACAAkJ2gsiIQBvAQAAAA==.Enveliria:BAAALgAECgcJEgABLgAFFAQJDQACAAobAA==.',
Er='Eraser:BAAALgAECgYJDgAAAA==.Erazar:BAABLgAECn9NAAIjAAkJABgWAQDBAQAjAAkJABgWAQDBAQAAAA==.Eriah:BAAALgADCgkJCQAAAA==.Erickk:BAABLgAECn81AAMOAAkJfRwnDwBoAQAOAAkJJRwnDwBoAQAkAAQJVx1SCwAkAQAAAA==.',
Es='Essense:BAABLgAECn8mAAIEAAkJmyRIAwApAwAEAAkJmyRIAwApAwAAAA==.',
Ex='Exodari:BAABLgAECn87AAIgAAkJ7hgICwAHAgAgAAkJ7hgICwAHAgAAAA==.',
Fa='Fabbioh:BAAALgADCgEJAQAAAA==.Fadeddh:BAACLgAFFH8SAAIMAAQJwRSLMQCvAAAMAAQJwRSLMQCvAAAuAAQKfzAAAgwACQn/G04jAEMCAAwACQn/G04jAEMCAAAA.Faizarah:BAAALgAECgYJBgAAAA==.Faydien:BAAALgAECgEJAgAAAA==.',
Fe='Fearnoevil:BAAALgADCgMJAwAAAA==.Fel:BAABLgAECn8RAAIMAAgJjRqSXgBtAQAMAAgJjRqSXgBtAQAAAA==.Fellius:BAAALgAECgEJAQAAAA==.Fellkarras:BAAALgAECgYJDwABLgAFFAMJDgAWAFceAA==.Fent:BAABLgAECn8VAAIbAAgJdwsBcgBWAQAbAAgJdwsBcgBWAQAAAA==.',
Fi='Fibitz:BAAALgAECgcJCgAAAA==.Fiddich:BAAALgAECgYJBgAAAA==.Fillthy:BAACLgAFFH8jAAIWAAgJxBoXBQB7AgAWAAgJxBoXBQB7AgAuAAQKfy4AAxYACQlYIkYDAEcDABYACQlYIkYDAEcDAAcAAwkhCQJ2AGQAAAAA.Finnigann:BAAALgAECgYJCwAAAA==.Fiofio:BAAALgAECgEJAQAAAA==.Firenmylazer:BAAALgAECgQJBAAAAA==.Fistav:BAAALgADCgcJDgAAAA==.Fithvenom:BAAALgAECgMJAwAAAA==.Fizban:BAABLgAECn8nAAIOAAkJagq3GwD1AAAOAAkJagq3GwD1AAAAAA==.',
Fl='Flappybird:BAAALgAECgYJCQABLgAFFAQJEgAMAMEUAA==.Flasan:BAAALgADCgEJAQAAAA==.Flazz:BAAALgADCgIJAwAAAA==.Flazzan:BAAALgADCgEJAQAAAA==.Flik:BAAALgAECggJCAABLgAFFAMJFAAIANMZAA==.',
Fo='Fogbringer:BAAALgAECgIJAwAAAA==.Fortstavious:BAAALgAFFAMJBAAAAA==.Four:BAAALgADCgQJBAAAAA==.',
Fr='Frejä:BAAALgAECgQJBQABLgAECgQJDAAUAAAAAA==.Freyah:BAABLgAECn8YAAMdAAYJyglADgDmAAAdAAYJyglADgDmAAAKAAIJJwNemAAhAAAAAA==.Frostmay:BAAALgAECgIJAgAAAA==.',
Fu='Furrybawlz:BAAALgAECgUJCgABLgAECgYJDQAUAAAAAA==.',
Ga='Gabran:BAAALgAECgcJBwAAAA==.Gadogear:BAABLgAECn8oAAIOAAkJ7hdGPQAmAgAOAAkJ7hdGPQAmAgAAAA==.Galahan:BAAALgAECgUJBgAAAA==.Garlick:BAAALgAECgUJBQABLgAECgkJTQAjAAAYAA==.Garlik:BAAALgADCgMJBAAAAA==.',
Ge='Gertra:BAAALgAECgEJAgABLgAECgYJCAAUAAAAAA==.',
Gf='Gfr:BAABLgAECn8YAAMeAAkJmBjJAwBRAgAeAAkJmBjJAwBRAgAbAAMJbRVQFgC6AAAAAA==.',
Gi='Girthrichard:BAAALgAECgYJDAAAAA==.',
Gl='Glassdragon:BAABLgAECn8nAAIBAAkJUQz+hABlAQABAAkJUQz+hABlAQAAAA==.Gllor:BAAALgADCgIJAgAAAA==.',
Go='Goatcheeze:BAABLgAECn8cAAIkAAkJLhUFBADGAQAkAAkJLhUFBADGAQAAAA==.Goatylocks:BAABLgAECn8rAAMeAAkJ7RWADQBlAQAbAAgJvRCWVACeAQAeAAYJLByADQBlAQAAAA==.Gohlemsaurus:BAAALgAECgYJEwAAAA==.Goldenchild:BAAALgAFFAMJBAABLgAFFAQJEgAMAMEUAA==.',
Gr='Gratfldeadly:BAAALgADCgEJAQABLgAECgYJDgAUAAAAAA==.Greatluckydo:BAAALgADCgEJAQAAAA==.Grishnakh:BAAALgAECgQJBAAAAA==.Grozlek:BAAALgADCgYJBgAAAA==.',
Gu='Gulen:BAABLgAECn8ZAAIQAAkJaR7PIwA4AgAQAAkJaR7PIwA4AgAAAA==.',
Gw='Gwendyla:BAAALgADCgkJFgAAAA==.',
Gy='Gyousei:BAAALgAECgUJBgAAAA==.',
['Gí']='Gíga:BAABLgAECn8XAAIfAAgJ7RPdKQAPAgAfAAgJ7RPdKQAPAgAAAA==.',
Ha='Hafnium:BAAALgAECgIJAgAAAA==.Hamish:BAAALgAFFAEJAQAAAA==.Hanhaine:BAACLgAFFH8GAAIJAAMJcwWzOQCUAAAJAAMJcwWzOQCUAAAuAAQKfzAAAgkACQncF1ETADoCAAkACQncF1ETADoCAAAA.Hazirat:BAAALgAECgYJDAAAAA==.',
He='Hedlie:BAABLgAECn8UAAMhAAkJGhQvAgDPAQAhAAkJGhQvAgDPAQAHAAEJ+ACsxAALAAAAAA==.Hellenkeller:BAECLgAFFH8HAAIWAAYJhw/TIgBYAQAWAAYJhw/TIgBYAQAuAAQKfx8AAhYABwkzITQTADMCABYABwkzITQTADMCAAEuAAUUCAkhACUAvhkA.Heloisa:BAAALgAECgYJEQAAAA==.Helrazr:BAAALgAFFAEJAgAAAA==.Henshin:BAACLgAFFH8UAAIIAAMJ0xmOFADSAAAIAAMJ0xmOFADSAAAuAAQKf0QAAwgACQmxHXcQAM4CAAgACQmxHXcQAM4CAAkAAgk4Dl+LADUAAAAA.',
Hi='Hipolyta:BAAALgADCgMJBgAAAA==.Hitt:BAAALgAECgcJCAAAAA==.',
Ho='Hogwortsfun:BAAALgAECgkJAgAAAA==.Holirolla:BAAALgAECgMJAwAAAA==.Holyhim:BAAALgADCgIJAgAAAA==.Holyshawk:BAAALgAECgEJAwAAAA==.Holysudz:BAAALgAECgEJAQAAAA==.Hooflora:BAAALgADCgEJAQABLgAECgYJHwACAHAXAA==.Horde:BAAALgAECgEJAQAAAA==.Hottyshmotty:BAAALgAECgEJAQAAAA==.Hourglass:BAABLgAECn9CAAMfAAkJlhrLHQByAgAfAAkJlhrLHQByAgALAAQJ1g3oXwDBAAAAAA==.',
Hr='Hroc:BAAALgAECgUJCwAAAA==.',
Hu='Hunterviral:BAAALgADCgEJAgAAAA==.Huntthejuan:BAAALgADCgUJBQAAAA==.',
Ic='Icyowneege:BAAALgADCgUJBQABLgAFFAkJJQAGAGAeAA==.Icywolfy:BAAALgAECgYJCAAAAA==.',
Ig='Igreetyou:BAABLgAECn8pAAIbAAcJXR5uLAAoAgAbAAcJXR5uLAAoAgAAAA==.',
Il='Illie:BAABLgAECn8mAAIgAAkJShyHBQCtAgAgAAkJShyHBQCtAgAAAA==.Illune:BAACLgAFFH8KAAIOAAMJEhf2eADnAAAOAAMJEhf2eADnAAAuAAQKfy4AAw4ACQnhG0kzAEwCAA4ACQlgGkkzAEwCACQABgmoFlkDABgBAAAA.',
Im='Imanbearpig:BAABLgAFFH8HAAITAAMJ+wjDIABRAAATAAMJ+wjDIABRAAAAAA==.Imleapingit:BAABLgAECn8wAAIGAAkJjiHZBgDxAgAGAAkJjiHZBgDxAgAAAA==.',
In='Intoodeep:BAABLgAFFH8FAAIcAAMJ3QMBBACUAAAcAAMJ3QMBBACUAAAAAA==.Intoodragons:BAACLgAFFH8RAAIYAAMJJQhTKAB9AAAYAAMJJQhTKAB9AAAuAAQKfzYAAxgACQmcFGocAPIBABgACQmcFGocAPIBACMABglaBfokAP4AAAAA.Inyah:BAAALgAECgIJAgAAAA==.',
Io='Ionzz:BAABLgAECn8ZAAICAAkJrx+iCADYAgACAAkJrx+iCADYAgAAAA==.',
Ir='Ir:BAAALgAFFAMJAwAAAA==.Iroann:BAAALgAECgcJEgAAAA==.Ironfoot:BAAALgAECggJCAABLgAECgkJIQAhAGkcAA==.',
Is='Isasham:BAAALgAECgYJCgAAAA==.Isawarriorr:BAACLgAFFH8FAAINAAMJJR0vFwDiAAANAAMJJR0vFwDiAAAuAAQKfywAAg0ACQmCI4kDAB8DAA0ACQmCI4kDAB8DAAAA.Ishaq:BAAALgAECgQJBQABLgAECgkJKAAhALYGAA==.Ishdo:BAAALgAECgUJBgABLgAECgkJKAAhALYGAA==.Ishdu:BAAALgAECgQJBAABLgAECgkJKAAhALYGAA==.Ishkhan:BAABLgAECn8oAAMhAAkJtgaYBQD4AAAhAAkJmwaYBQD4AAAHAAYJUQUMYACaAAAAAA==.Ishmael:BAACLgAFFH8RAAMNAAMJjxkfGQDPAAANAAMJjxkfGQDPAAAGAAEJiw2cUwBEAAAuAAQKfxQAAwYACQk6HkIWAD0CAAYACQkwHEIWAD0CAA0AAglmGzk8AIIAAAAA.Ishmonk:BAAALgAECgIJAgABLgAFFAMJEQANAI8ZAA==.Ishwar:BAAALgADCgYJBgABLgAECgkJKAAhALYGAA==.',
Ja='Jakytreehorn:BAACLgAFFH8PAAMQAAcJsQglSwDEAAAQAAUJ5QMlSwDEAAAXAAYJwwlpHgCqAAAuAAQKfzkAAxcACQn9Fn4cAP0BABcACAn3F34cAP0BABAACQlCFQwoAPABAAAA.Jasher:BAAALgAECgYJBgAAAA==.Jaydm:BAABLgAECn8dAAImAAYJRxiPHwBhAQAmAAYJRxiPHwBhAQABLgAFFAgJFwAOAOwMAA==.',
Je='Jenevelle:BAAALgAECgcJCgAAAA==.Jerisil:BAAALgADCgQJBAAAAA==.Jet:BAABLgAECn8aAAIBAAYJ6CAySwABAgABAAYJ6CAySwABAgAAAA==.',
Ji='Jibbajabba:BAAALgADCgcJBwAAAA==.Jimbo:BAABLgAFFH8KAAIbAAMJDh/dXgAKAQAbAAMJDh/dXgAKAQABLgAFFAkJKAADAFUjAA==.',
Jo='Johnmayer:BAAALgAECgQJBQAAAA==.',
Ju='Judgecalypso:BAAALgAECgQJBgAAAA==.Judgiah:BAAALgAECgUJBQAAAA==.Julthaenia:BAABLgAECn8lAAQnAAcJZx8ZBgAgAgAnAAcJZx8ZBgAgAgAeAAQJGAr1SwCJAAAbAAUJcQsK9QB4AAABLgAFFAQJDQACAAobAA==.Justeatjuan:BAAALgAECgMJAwAAAA==.',
Ka='Kagebushin:BAAALgAECgMJBAAAAA==.Kalazin:BAAALgAECgUJBQAAAA==.Kalimah:BAAALgADCgMJAwAAAA==.Kallekgos:BAAALgAECgEJAQAAAA==.Kalofelement:BAAALgAECgcJCAAAAA==.Kamiguru:BAAALgADCgEJAQABLgAFFAYJCgAPAMgIAA==.Karash:BAAALgAECgYJDwABLgAFFAQJCAAWAAwIAA==.Karmaisab:BAAALgADCgEJAQAAAA==.Karnrae:BAACLgAFFH8OAAIBAAMJNQ67NADBAAABAAMJNQ67NADBAAAuAAQKfzEAAgEACQnuEyoQAF0BAAEACQnuEyoQAF0BAAAA.Karynos:BAACLgAFFH8GAAIbAAIJOwVoTQBoAAAbAAIJOwVoTQBoAAAuAAQKfycAAxsACQnJDXNVAJwBABsACQmaDHNVAJwBAB4ABwnJCQ4jAD8BAAAA.Katnelly:BAAALgAECgQJCQAAAA==.Katwolf:BAAALgAECgEJAgAAAA==.Kazmacoryy:BAAALgAECgYJEAAAAA==.',
Ke='Keedis:BAAALgAECgEJAQAAAA==.Keristrasza:BAAALgAFFAEJAQABLgAFFAkJKQAQAOgaAA==.',
Kh='Khlarm:BAAALgADCgIJAgABLgAECgkJMAAfAPQYAA==.',
Ki='Kileely:BAAALgAECgMJAwAAAA==.Kirintore:BAAALgAECgUJCQAAAA==.',
Kk='Kkaiser:BAAALgAECgUJBQAAAA==.',
Kl='Klaudeus:BAAALgAECgEJAQAAAA==.',
Ko='Kodian:BAAALgADCgEJAQAAAA==.Kolypso:BAABLgAECn8gAAIfAAkJuRuxLwAeAgAfAAkJuRuxLwAeAgAAAA==.Konceal:BAAALgAECgEJAQAAAA==.Konspiracy:BAABLgAECn8pAAIeAAkJpxawBgD0AQAeAAkJpxawBgD0AQAAAA==.Konvict:BAAALgAECgIJAwABLgAECgYJDQAUAAAAAA==.Kor:BAAALgAECgIJAgABLgAECgkJJwAOAGoKAA==.',
Kr='Kraguva:BAAALgAECgcJCQAAAA==.Krataar:BAABLgAECn8hAAIGAAkJEyGhDACgAgAGAAkJEyGhDACgAgAAAA==.Kravvan:BAAALgAECgUJCgABLgAECgkJJwAOAGoKAA==.Krootloops:BAAALgAECgMJAwABLgAECgcJCgAUAAAAAA==.Krousvor:BAAALgAECgQJBwAAAA==.Kryph:BAABLgAECn8dAAIDAAkJQAiQegBuAQADAAkJQAiQegBuAQAAAA==.',
Ku='Kugruk:BAAALgAECgcJDAAAAA==.Kurjo:BAAALgAECgMJBAAAAA==.',
Ky='Kyleschlong:BAAALgAECgMJCAAAAA==.Kyndreith:BAAALgAECgMJAwAAAA==.',
['Kä']='Kämpfer:BAABLgAECn9UAAIGAAkJFiEUCADeAgAGAAkJFiEUCADeAgAAAA==.',
La='Lafiel:BAABLgAECn8dAAMEAAkJGgtKPABJAQAEAAkJGgtKPABJAQAKAAIJ1QiQdwBRAAAAAA==.Landiedoo:BAAALgAECgkJCgAAAA==.Laurana:BAAALgADCgYJBgAAAA==.Laurandre:BAAALgAECgcJEwAAAA==.Laverna:BAAALgADCgMJBAAAAA==.Lazeras:BAAALgAECgUJCgABLgAFFAEJAgAUAAAAAA==.',
Le='Lefay:BAAALgAECgMJBAAAAA==.Leprawnjames:BAAALgAECggJCwABLgAECgkJGQATAKofAA==.Letsgetwet:BAAALgADCgYJBgAAAA==.',
Li='Liefic:BAAALgAECgcJDgAAAA==.Lillavender:BAAALgADCgYJBgAAAA==.Limon:BAAALgADCgIJAgAAAA==.',
Lo='Loadin:BAAALgAECgIJAgAAAA==.Lockaflockå:BAAALgADCgMJAwAAAA==.Locke:BAAALgAECgMJAgABLgAECgYJGgABAOggAA==.Lonoh:BAAALgAECgcJEgAAAA==.Lozmoji:BAAALgAECgYJCwABLgAFFAMJBgAJAHMFAA==.',
Lu='Luan:BAAALgAECgMJAwAAAA==.Lucariø:BAAALgADCgcJDAAAAA==.Lucidbonsai:BAAALgADCggJCAAAAA==.Luckykilla:BAACLgAFFH8FAAIcAAQJ+Qg1CADXAAAcAAQJ+Qg1CADXAAAuAAQKfy4AAhwACQleHtACAJ4CABwACQleHtACAJ4CAAAA.Lucÿ:BAACLgAFFH8SAAIQAAcJ8w6cHgB8AQAQAAcJ8w6cHgB8AQAuAAQKfywAAxAACQkhIKcJAJMBABAABwnvH6cJAJMBABcABwmmFiYIAEUBAAAA.Luffytaro:BAAALgADCgUJBQAAAA==.Lula:BAAALgADCgMJAwAAAA==.Lurith:BAABLgAECn+OAAMDAAkJOiFNAgD3AgADAAkJsyBNAgD3AgAVAAkJ/ByPAQCQAgAAAA==.Lutreaux:BAAALgADCgEJAQAAAA==.Luxtyrannica:BAABLgAECn8pAAIBAAkJ3R6fFQDBAgABAAkJ3R6fFQDBAgAAAA==.',
Ly='Lydrain:BAAALgAECgEJAQAAAA==.Lysandria:BAABLgAECn8rAAIOAAkJmw3bagCmAQAOAAkJmw3bagCmAQAAAA==.',
Ma='Macrosblack:BAAALgADCgMJAwAAAA==.Madamerouge:BAAALgAECgIJAgABLgAECgkJHAAiACoWAA==.Magearino:BAABLgAECn8nAAIOAAgJnRasXwDBAQAOAAgJnRasXwDBAQAAAA==.Malafore:BAAALgADCgEJAQAAAA==.Malcolm:BAAALgAECgEJAgABLgAECgkJMwAGACsWAA==.Malcrux:BAAALgAECgIJAgAAAA==.Marcopally:BAAALgAECgQJBAAAAA==.Marluxia:BAACLgAFFH8mAAITAAgJ7wm/EQD3AAATAAgJ7wm/EQD3AAAuAAQKfxwAAhMACQmOFPYMALkBABMACQmOFPYMALkBAAAA.Mastamonk:BAAALgAECgQJBAAAAA==.Materfamilia:BAAALgAECgQJBAAAAA==.Mattbull:BAACLgAFFH8LAAMYAAMJZRmJOwDZAAAYAAMJZRmJOwDZAAAjAAEJ1xNICQBXAAAuAAQKfx4AAyMABgmqJFcNAAQCACMABglCIlcNAAQCABgABgl5Il8gANYBAAAA.Mayu:BAAALgAECgcJEQAAAA==.',
Me='Medjrab:BAACLgAFFH8UAAIDAAUJxhjmYwAvAQADAAUJxhjmYwAvAQAuAAQKfzIAAgMACQlLIjcTANUCAAMACQlLIjcTANUCAAAA.Meristem:BAABLgAECn80AAIJAAkJABJSIgC2AQAJAAkJABJSIgC2AQAAAA==.Merko:BAAALgADCgkJEQAAAA==.',
Mi='Miaan:BAAALgADCgYJBgAAAA==.Miette:BAAALgADCgMJAwAAAA==.Mihonk:BAAALgADCgQJBAAAAA==.Mintycrx:BAABLgAECn8fAAIOAAkJHhGZUwDiAQAOAAkJHhGZUwDiAQAAAA==.Missfist:BAAALgADCgIJAgAAAA==.Mistlocke:BAAALgADCgMJAwAAAA==.',
Mn='Mngwa:BAAALgAECgQJCwAAAA==.',
Mo='Moedorai:BAAALgAECgIJAQABLgAECgkJHAAoABQWAA==.Moegu:BAABLgAECn8cAAIoAAkJFBYXCAD3AQAoAAkJFBYXCAD3AQAAAA==.Mog:BAACLgAFFH8SAAMbAAMJLyAfPgCdAAAbAAIJwSIfPgCdAAAnAAEJCxuTEABWAAAuAAQKfzkABBsACQmeI/sVAKECABsABwnVI/sVAKECACcAAwmVI6kYAP4AAB4AAwkJEsI2ANsAAAAA.Mogma:BAAALgAECgQJBAAAAA==.Moncatsera:BAAALgAECgQJBAAAAA==.Mondgrille:BAAALgAECgQJBAABLgAECgYJDQAUAAAAAA==.Monora:BAABLgAECn8cAAIWAAgJdw6tSgBBAQAWAAgJdw6tSgBBAQAAAA==.Montress:BAABLgAECn8UAAIEAAgJBhD3JwCGAQAEAAgJBhD3JwCGAQAAAA==.Moomoohealz:BAACLgAFFH8TAAIJAAMJ8RnJGQCpAAAJAAMJ8RnJGQCpAAAuAAQKfz4AAgkACQkoIW8IAM0CAAkACQkoIW8IAM0CAAAA.Moomoorage:BAAALgAECgQJBQABLgAECggJCQAUAAAAAA==.Moonbounds:BAACLgAFFH8pAAIQAAkJ6Bq+AwCZAgAQAAkJ6Bq+AwCZAgAuAAQKfzgAAxAACQndJFEDAEQDABAACQndJFEDAEQDABcAAQnZH4Z5AF0AAAAA.Moondoggey:BAAALgAECgMJAwAAAA==.Morgana:BAAALgADCgIJAgAAAA==.Mortemcleric:BAAALgADCgYJBgAAAA==.Morzanna:BAAALgADCgcJBwAAAA==.Mousechief:BAABLgAECn9QAAIXAAkJhgtuCQAqAQAXAAkJhgtuCQAqAQAAAA==.Moxnix:BAACLgAFFH8IAAMWAAQJDAhxLAB2AAAWAAMJjAZxLAB2AAAhAAEJpgetJQArAAAuAAQKfx8AAxYACAl4EFMSAAIBABYABwl8DlMSAAIBACEABAmOBVhdAJkAAAAA.Moxxzi:BAAALgAFFAEJAgAAAA==.',
Mu='Muhfookinbak:BAABLgAECn8kAAMQAAkJFyDbEADJAgAQAAkJFyDbEADJAgAXAAQJhxiYXQDLAAAAAA==.Mulann:BAAALgAECgEJAQAAAA==.',
Mv='Mvse:BAAALgAECgEJAgAAAA==.',
My='Myor:BAAALgADCgMJAwAAAA==.',
['Mà']='Màttbull:BAABLgAFFH8HAAIMAAMJcw7xZwC9AAAMAAMJcw7xZwC9AAABLgAFFAMJCwAYAGUZAA==.',
['Mä']='Märcøsferätv:BAAALgAECgEJAQAAAA==.',
Na='Naesta:BAAALgAECgYJCAABLgAFFAYJFwAIAKUWAA==.Naksu:BAAALgAECgEJAQABLgAECgkJLwAMAK8KAA==.Naksù:BAABLgAECn8vAAIMAAkJrwpNFgDMAAAMAAkJrwpNFgDMAAAAAA==.Namal:BAAALgAECgQJBQAAAA==.Narenae:BAABLgAECn8lAAIHAAkJCyRABABIAwAHAAkJCyRABABIAwAAAA==.Nastalan:BAAALgADCgYJEAAAAA==.',
Ne='Necrovoid:BAAALgAECgEJAQAAAA==.Nefari:BAAALgADCgMJAwAAAA==.Neifeb:BAABLgAECn8uAAIfAAkJeRf2NwD+AQAfAAkJeRf2NwD+AQAAAA==.Nephthys:BAAALgADCgQJBAAAAA==.',
Ni='Niallivdam:BAABLgAECn8wAAMjAAgJUxztAwBHAgAjAAgJUxztAwBHAgARAAYJ0hfJEwCNAQAAAA==.Nights:BAAALgAECgIJAgABLgAFFAkJGwABAGcTAA==.Nightsoul:BAAALgADCgEJAQAAAA==.Ninh:BAACLgAFFH8WAAIWAAMJvwW5LgBrAAAWAAMJvwW5LgBrAAAuAAQKf1UAAhYACQn6FOkcADECABYACQn6FOkcADECAAAA.',
No='Nomissius:BAAALgADCgcJDQAAAA==.Nooblè:BAAALgADCgMJAwAAAA==.Notsodemon:BAABLgAECn8eAAMMAAgJfxSGUwCLAQAMAAgJfxSGUwCLAQACAAIJnwrPYwBUAAAAAA==.Notsoevoker:BAAALgAECgMJAwABLgAECggJHgAMAH8UAA==.Notsomonk:BAAALgADCgMJAwABLgAECggJHgAMAH8UAA==.',
Ny='Nykara:BAAALgAECgUJBQAAAA==.Nyxwing:BAAALgAECgQJAwAAAA==.',
['Nå']='Nåld:BAABLgAECn8WAAIOAAYJKw94GwD3AAAOAAYJKw94GwD3AAAAAA==.',
Oa='Oakendorf:BAAALgAECgEJAQABLgAECgEJAgAUAAAAAA==.',
Ob='Obvinotagirl:BAAALgAECggJEwAAAA==.',
Od='Oddpocalypse:BAAALgAECgEJAgAAAA==.',
Og='Ogsikko:BAAALgAECgYJCwABLgAECggJGAAbAJAeAA==.Ogsikkotv:BAABLgAECn8YAAIOAAYJ/BmQhwDCAQAOAAYJ/BmQhwDCAQABLgAECggJGAAbAJAeAA==.',
Ok='Okathra:BAAALgAECgQJBAABLgAFFAQJDAAgAMIbAA==.',
On='Onebadmutha:BAABLgAECn8ZAAIbAAkJ+AwpVACgAQAbAAkJ+AwpVACgAQAAAA==.Ontop:BAACLgAFFH8HAAIfAAMJoBUDMQDdAAAfAAMJoBUDMQDdAAAuAAQKfygAAh8ACQnvGxocAF4CAB8ACQnvGxocAF4CAAAA.',
Or='Orb:BAABLgAECn9AAAQBAAkJfhvTBwD2AQABAAkJexvTBwD2AQAPAAkJOBatJwDNAQAFAAYJlQ/EHgATAQAAAA==.Orcfreeza:BAAALgAECgQJDAAAAA==.Ortinks:BAABLgAECn8zAAIOAAkJQBmFBgAjAgAOAAkJQBmFBgAjAgAAAA==.',
Ow='Owneege:BAACLgAFFH8lAAIGAAkJYB7/AQCKAgAGAAkJYB7/AQCKAgAuAAQKfzQAAgYACQmhIx4CAKADAAYACQmhIx4CAKADAAAA.',
Pa='Painsaw:BAAALgADCgYJBgAAAA==.Pallinar:BAABLgAECn83AAIBAAkJGhUwPwAJAgABAAkJGhUwPwAJAgAAAA==.Pandamak:BAAALgAECgUJDgAAAA==.Pasquale:BAABLgAECn8hAAIhAAcJRSH9FAAFAgAhAAcJRSH9FAAFAgAAAA==.',
Pe='Pebbles:BAABLgAECn8kAAIBAAkJphkrRAD5AQABAAkJphkrRAD5AQAAAA==.Pedorus:BAAALgAECgEJAQABLgAFFAcJEgAQAPMOAA==.Pedroia:BAABLgAECn8hAAQcAAgJsBHgAQBKAQAcAAgJsBHgAQBKAQASAAcJMQYDNgD9AAAlAAIJNAcAIABPAAAAAA==.Peridaxx:BAAALgAECgIJAgAAAA==.Pesty:BAAALgAECgMJCQAAAA==.',
Ph='Phe:BAABLgAECn8XAAMJAAcJhw4QPAAhAQAJAAcJhw4QPAAhAQAIAAYJpQvzcAADAQAAAA==.Pheraree:BAAALgAECgEJAQAAAA==.Phooboo:BAAALgAECgkJBQAAAA==.',
Pi='Pidion:BAAALgADCgYJDAAAAA==.Pilgrimm:BAECLgAFFH8hAAMlAAgJvhnSAQC8AQAlAAYJ+RrSAQC8AQASAAcJRxsfDQAzAQAuAAQKfyQAAxIACQl7IrIDAGADABIACQl0IrIDAGADACUABQkIHzgLAGcBAAAA.Pixyl:BAAALgAECgYJDgAAAA==.',
Pl='Plaguerott:BAABLgAECn83AAIaAAkJeA9TDgCQAQAaAAkJeA9TDgCQAQAAAA==.Plusultra:BAAALgADCgkJEQAAAA==.Pluto:BAAALgAFFAQJBAAAAA==.',
Po='Poby:BAAALgADCgcJBwAAAA==.Polydh:BAABLgAECn8wAAIoAAkJriT3AAA9AwAoAAkJriT3AAA9AwAAAA==.Poobah:BAABLgAECn8kAAMXAAkJYQaVWQDXAAAXAAgJHQaVWQDXAAAQAAcJCgMLigDHAAAAAA==.Popscotch:BAABLgAECn8jAAMnAAkJEg3OCQCkAQAnAAcJRg7OCQCkAQAbAAkJwAu3XQCGAQAAAA==.Pouffant:BAABLgAECn8iAAIBAAkJyBNhVwDFAQABAAkJyBNhVwDFAQAAAA==.',
Pr='Pronoz:BAABLgAECn8mAAIBAAcJfRJjlABLAQABAAcJfRJjlABLAQAAAA==.',
Pu='Punchy:BAAALgADCgEJAQAAAA==.Purpyl:BAAALgAECgIJAgABLgAECggJIQAcALARAA==.',
Pw='Pwnageddon:BAABLgAECn82AAMFAAgJ2h6pCABLAgAFAAcJkyKpCABLAgABAAUJhxUW4gDJAAAAAA==.Pwnjitsu:BAACLgAFFH8IAAIHAAMJ2R61FgALAQAHAAMJ2R61FgALAQAuAAQKfz4AAgcACQk8JT8CAEsDAAcACQk8JT8CAEsDAAAA.',
Py='Pyrothermia:BAACLgAFFH8XAAIOAAgJ7AxyIQD6AQAOAAgJ7AxyIQD6AQAuAAQKfyYAAg4ACQn/HIoqAMgCAA4ACQn/HIoqAMgCAAAA.',
['Pô']='Pôlgara:BAAALgADCgYJBgABLgAECgkJNgAPABQfAA==.',
Qt='Qtkillz:BAAALgADCgQJBAAAAA==.',
Qu='Quinlekd:BAAALgAECgQJBAABLgAECgkJMwAbAJ4iAA==.',
Ra='Rakugan:BAAALgAECgQJAwAAAA==.Rancayden:BAAALgAECgMJBAAAAA==.Rawhoof:BAACLgAFFH8WAAIGAAMJFSC3GQDRAAAGAAMJFSC3GQDRAAAuAAQKf1UAAgYACQlHJq4BAGMDAAYACQlHJq4BAGMDAAAA.Razak:BAACLgAFFH8MAAIgAAQJwhvNDAD0AAAgAAQJwhvNDAD0AAAuAAQKfzoAAiAACQniI1oBACsDACAACQniI1oBACsDAAAA.',
Re='Redlock:BAAALgAECgYJBgAAAA==.Redrum:BAAALgAECgUJBQABLgAFFAMJDgAWAFceAA==.Redtiger:BAAALgADCgcJBgAAAA==.Renisa:BAABLgAECn8iAAIMAAgJqRkLUgCPAQAMAAgJqRkLUgCPAQAAAA==.Retman:BAABLgAECn8UAAIBAAcJtg+X8QDJAAABAAcJtg+X8QDJAAAAAA==.Retrimution:BAAALgADCgMJAwAAAA==.Reu:BAAALgAECgUJBwAAAA==.Revlyk:BAACLgAFFH8FAAIgAAMJORWUDgDXAAAgAAMJORWUDgDXAAAuAAQKfycAAiAACAkWI3oEAKgCACAACAkWI3oEAKgCAAEuAAUUBAkNAAIAChsA.Rezloh:BAAALgAECgkJDAAAAA==.',
Rh='Rhoanna:BAAALgADCgUJBwAAAA==.Rhoupert:BAAALgAECgQJBQABLgAECgkJIwAiAOIYAA==.',
Ri='Rinja:BAAALgADCgYJBgAAAA==.Rintaro:BAABLgAECn8kAAIFAAkJrAvSGwA4AQAFAAkJrAvSGwA4AQAAAA==.Ritanana:BAAALgAECgIJAgAAAA==.',
Ro='Roccot:BAAALgAECggJDgAAAA==.Roflstomp:BAAALgAECgUJCAABLgAECgkJGQATAKofAA==.Roostrr:BAABLgAECn8XAAIBAAYJ4B2EcwCUAQABAAYJ4B2EcwCUAQAAAA==.Rotfather:BAAALgADCgYJBgAAAA==.Rotjaw:BAAALgAECgYJDgAAAA==.Roughedge:BAAALgADCgIJAgAAAA==.',
Ru='Rurik:BAAALgAECgEJAQAAAA==.',
['Rä']='Rävthor:BAAALgAFFAEJAQAAAA==.Rävthör:BAAALgAECggJEwAAAA==.',
['Rè']='Rèjuva:BAAALgAECgcJDQAAAA==.Rèptílè:BAAALgADCgMJAwABLgAFFAUJCAAfAOYcAA==.',
['Rî']='Rîcflair:BAAALgAECgcJEwAAAA==.',
Sa='Saiyax:BAAALgADCgYJBwAAAA==.Salidfingers:BAAALgADCgYJBgAAAA==.Samies:BAAALgAECgEJAQAAAA==.Sanyakulak:BAAALgADCgcJBwABLgAFFAkJIgATALQTAA==.Sanzo:BAAALgAECgEJAgAAAA==.Savathûn:BAAALgAECgQJCAAAAA==.',
Sc='Scalycat:BAACLgAFFH8LAAMRAAMJJw/uIACgAAARAAMJJw/uIACgAAAYAAMJjgEFVQB2AAAuAAQKfyoABBEACQnYDpwZAMEBABEACQnYDpwZAMEBABgABwksBsVnAKMAACMAAgluB/snAC0AAAAA.Schalla:BAAALgAECgEJAQAAAA==.Scum:BAAALgAECgYJDQAAAA==.Scòrpìòn:BAAALgADCgcJBgABLgAFFAUJCAAfAOYcAA==.',
Se='Seancody:BAAALgADCgIJAgAAAA==.Sekhmett:BAABLgAECn8hAAMkAAgJHASODgCQAAAkAAYJ1gOODgCQAAAOAAgJ0AMVNAByAAAAAA==.Selandria:BAAALgADCgQJBAAAAA==.Senate:BAAALgAECgYJCwAAAA==.',
Sh='Shablaam:BAAALgADCgQJBAAAAA==.Shadowbear:BAABLgAECn8cAAIKAAcJ/RztHwDGAQAKAAcJ/RztHwDGAQAAAA==.Shadowoss:BAAALgAECgYJCAAAAA==.Shadygrump:BAAALgAECgYJEQAAAA==.Shamdeaus:BAAALgADCgUJBQABLgAECgkJMAAfAPQYAA==.Shammacass:BAAALgAECgUJBQAAAA==.Shamwick:BAAALgAECgYJCgAAAA==.Shaolincito:BAAALgAECgQJCAAAAA==.Sherrilyn:BAAALgAECgUJBgAAAA==.Shocklocke:BAAALgAECgQJBAAAAA==.',
Si='Sigmachad:BAABLgAECn8VAAIBAAUJmR8tDwBpAQABAAUJmR8tDwBpAQAAAA==.Silandrus:BAAALgAECgMJBAAAAA==.Silverocean:BAACLgAFFH8GAAIPAAMJgwo5GQCIAAAPAAMJgwo5GQCIAAAuAAQKfzMAAg8ACQkxHOoPAJQCAA8ACQkxHOoPAJQCAAAA.Silvia:BAAALgADCgUJCQAAAA==.Singularity:BAACLgAFFH8WAAINAAMJbiQeCgAbAQANAAMJbiQeCgAbAQAuAAQKf1IAAg0ACQltJpQAAHUDAA0ACQltJpQAAHUDAAAA.',
Sk='Skaerx:BAABLgAECn8WAAMGAAYJVBeOQwCXAQAGAAYJ9RWOQwCXAQAmAAQJZhSYHQADAQAAAA==.Skittlez:BAABLgAECn8mAAIZAAkJkR/SCQCBAgAZAAkJkR/SCQCBAgABLgAFFAUJDAAcAN8WAA==.',
Sl='Slaykween:BAABLgAECn8fAAIFAAgJLQvZIAANAQAFAAgJLQvZIAANAQAAAA==.Sloots:BAAALgADCgMJAwAAAA==.Slootybooty:BAABLgAECn8ZAAITAAkJqh81BQC8AgATAAkJqh81BQC8AgAAAA==.',
Sm='Smallz:BAABLgAECn8XAAIBAAYJjg45zAD4AAABAAYJjg45zAD4AAABLgAECgkJJwAOAGoKAA==.',
Sn='Snackpack:BAAALgAECgMJAwAAAA==.Snipersmash:BAAALgAECgQJCAAAAA==.Snooptrogg:BAABLgAECn8zAAIGAAkJKxZuIADtAQAGAAkJKxZuIADtAQAAAA==.Snoozumi:BAABLgAFFH8GAAIWAAMJKQZISgB9AAAWAAMJKQZISgB9AAAAAA==.Snuups:BAABLgAECn9DAAIbAAkJAhomLwAcAgAbAAkJAhomLwAcAgAAAA==.Snyper:BAAALgADCgQJBwAAAA==.',
So='Soldiah:BAABLgAECn8bAAIGAAgJrQ16OQBgAQAGAAgJrQ16OQBgAQAAAA==.Sommbra:BAAALgAECgYJBwAAAA==.Souljax:BAAALgADCgcJCQAAAA==.',
Sp='Spacelaser:BAAALgAECgQJBQAAAA==.',
Sq='Sqwurl:BAAALgADCgQJBAAAAA==.',
St='Steakhaus:BAAALgADCgkJCwAAAA==.Stiros:BAAALgAECgMJAwAAAA==.Stonedragon:BAECLgAFFH8bAAMfAAgJARtWCQARAgAfAAcJ2x1WCQARAgALAAEJ4gn/HABEAAAuAAQKf0kAAx8ACQlSJcwFADEDAB8ACQlSJcwFADEDAAsACAkPIKwDAI4CAAAA.Stormfist:BAABLgAECn8ZAAIOAAkJ3BAOUADsAQAOAAkJ3BAOUADsAQAAAA==.Stormhaven:BAAALgAECgIJAgABLgAECgkJNgAPABQfAA==.Stormrender:BAAALgAECgYJEgAAAA==.Stormriders:BAAALgAECgUJDgAAAA==.Stormstag:BAAALgADCgYJBgAAAA==.Stouty:BAAALgADCgMJAwABLgAECgcJFAAjAOkaAA==.Stovakor:BAAALgAECgEJAQAAAA==.Streea:BAAALgADCgMJAwABLgAECgcJHAAOAEQcAA==.',
Su='Sukonamí:BAABLgAECn8iAAMGAAkJghckKAAdAgAGAAgJdhUkKAAdAgAmAAQJGhs7KQAoAQAAAA==.Sumo:BAAALgAECgEJAgAAAA==.Suxtosuck:BAAALgAECgkJBwAAAA==.Suzhou:BAABLgAECn8kAAIeAAkJFwnkFAAFAQAeAAkJFwnkFAAFAQAAAA==.Suzoomies:BAAALgADCgcJBwAAAA==.Suzumii:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetcarolin:BAABLgAECn8WAAIDAAkJRg+GXgDXAQADAAkJRg+GXgDXAQAAAA==.Sweetsmercy:BAAALgAECgQJBQAAAA==.Swiftleaf:BAAALgADCgcJBwAAAA==.Swisscheese:BAABLgAECn8zAAIbAAkJniLWBwAZAwAbAAkJniLWBwAZAwAAAA==.',
Sy='Syraxa:BAAALgAECgUJEgABLgAFFAYJFQAIAKgUAA==.Syril:BAAALgADCgcJDAAAAA==.',
Ta='Taedish:BAAALgADCgMJAwAAAA==.Tahret:BAAALgADCgcJDAAAAA==.Taidoetha:BAAALgAECgMJAwAAAA==.Talfurim:BAAALgADCgYJBgAAAA==.Talorien:BAAALgAECgYJDQABLgAFFAMJCgAOABIXAA==.Tannith:BAAALgAECgEJAQABLgADCgEJAQAUAAAAAA==.Taquillya:BAAALgAECgQJBQAAAA==.Tarina:BAAALgADCgEJAQAAAA==.Tatersaladin:BAAALgADCgMJAwAAAA==.',
Te='Tenlortin:BAAALgAECgEJAQABLgAECgYJEAAUAAAAAA==.Terragosa:BAABLgAECn86AAIOAAkJXBrYLQBiAgAOAAkJXBrYLQBiAgAAAA==.Teryail:BAAALgAECgEJAgAAAA==.Tetchybono:BAAALgADCgYJBgAAAA==.Tettra:BAAALgAECgYJDQABLgAECgcJHAAOAEQcAA==.',
Th='Thade:BAABLgAECn8kAAMmAAkJByHUBQCpAgAmAAgJGiDUBQCpAgAGAAgJfB5XHwBWAgAAAA==.Thaeleon:BAABLgAECn8hAAMJAAgJbx98EgBCAgAJAAgJbx98EgBCAgAIAAYJixz+NADUAQABLgAFFAMJEQANAI8ZAA==.Thahawtz:BAAALgADCggJCAAAAA==.Thanattos:BAAALgAECgQJBwAAAA==.Thaneblade:BAAALgAECgQJBgAAAA==.Therizzler:BAAALgAECgcJCQABLgAFFAQJEgAMAMEUAA==.Thickening:BAABLgAECn8ZAAMWAAUJhQ1UagDYAAAWAAUJhQ1UagDYAAAHAAUJ9QfJYQCVAAAAAA==.Thirinis:BAAALgADCgYJBgAAAA==.Thope:BAABLgAECn8nAAIOAAcJTA0kpgAxAQAOAAcJTA0kpgAxAQAAAA==.Thoranubran:BAABLgAECn8fAAICAAYJcBelBwAtAQACAAYJcBelBwAtAQAAAA==.Thrivia:BAAALgAECgYJBgAAAA==.',
Ti='Ticklemychin:BAABLgAECn8iAAIOAAcJBQz0GQACAQAOAAcJBQz0GQACAQAAAA==.Tigani:BAAALgAECgUJDAAAAA==.Tinstey:BAAALgAECgYJAwAAAA==.Titantu:BAAALgAFFAMJAwABLgAFFAMJBgAJAHMFAA==.',
To='Toestiir:BAAALgAECggJEgAAAA==.Tokemaddab:BAAALgADCgUJBQAAAA==.Tontoee:BAAALgAECgEJAQAAAA==.Torlanos:BAAALgADCgIJAgAAAA==.Tosindruid:BAAALgAECgEJAQAAAA==.Toughasnails:BAAALgAECgEJBAAAAA==.',
Tr='Traesdyne:BAAALgAECgEJAQABLgAECgMJAwAUAAAAAA==.Trainar:BAAALgAECgQJCQAAAA==.Trazle:BAAALgAECgMJAwAAAA==.Treatman:BAAALgAECgYJBwAAAA==.Trekkiegeek:BAAALgAECgIJBAAAAA==.Trickybackup:BAAALgADCgMJAwAAAA==.Triggs:BAAALgAECgcJBwAAAA==.Trollbear:BAABLgAECn8WAAIIAAgJhBUJKQAKAgAIAAgJhBUJKQAKAgAAAA==.Trondruid:BAAALgADCgYJDQAAAA==.Trooze:BAABLgAECn87AAIPAAkJLiNhAwBrAwAPAAkJLiNhAwBrAwAAAA==.Trr:BAABLgAECn8pAAIbAAkJmBe2IwCFAgAbAAkJmBe2IwCFAgAAAA==.Truckz:BAAALgADCgEJAQABLgAFFAMJCQAfAIMPAA==.Truckzage:BAAALgAECgEJAQABLgAFFAMJCQAfAIMPAA==.Truckzbrr:BAAALgAECgYJCQABLgAFFAMJCQAfAIMPAA==.Truckzstabs:BAAALgAECgIJAgABLgAFFAMJCQAfAIMPAA==.',
Tu='Tuba:BAAALgAECgYJEAAAAA==.Turim:BAABLgAECn8VAAIDAAgJNgcdpwAhAQADAAgJNgcdpwAhAQAAAA==.Tusksrus:BAAALgAECgMJAwAAAA==.',
Ty='Tyrannus:BAAALgADCgMJAwAAAA==.Tyrlidd:BAABLgAECn9BAAIfAAkJzBhhCADxAQAfAAkJzBhhCADxAQAAAA==.',
Ud='Udon:BAACLgAFFH8IAAMDAAUJmgveeQARAQADAAUJmgveeQARAQAaAAEJkQGeLQAyAAAuAAQKfyIAAwMABwkQGodrAI4BAAMABgm4GodrAI4BABoABQk6FogXABoBAAAA.',
Ug='Ugoar:BAAALgAECggJEwAAAA==.',
Ul='Ultimazero:BAAALgADCgEJAQAAAA==.',
Un='Unavoidable:BAAALgADCgkJEQAAAA==.Unholirolla:BAAALgAECgEJAQAAAA==.Unlikelytale:BAABLgAECn8mAAIQAAkJAyEuCgDXAgAQAAkJAyEuCgDXAgAAAA==.Unmilked:BAAALgAECgYJBwAAAA==.',
Ur='Uricash:BAACLgAFFH8HAAIOAAMJcBh5dgDuAAAOAAMJcBh5dgDuAAAuAAQKf1AAAg4ACQmWIIgRAPECAA4ACQmWIIgRAPECAAAA.Urzual:BAABLgAECn8tAAIgAAkJDyD2BQB+AgAgAAkJDyD2BQB+AgAAAA==.',
Ut='Utiniócast:BAAALgAECgQJBAAAAA==.',
Va='Valmorth:BAAALgADCgMJAwAAAA==.Vandreynna:BAACLgAFFH8NAAICAAQJCht0DABIAQACAAQJCht0DABIAQAuAAQKf1MAAgIACQnWJVUBAGkDAAIACQnWJVUBAGkDAAAA.',
Ve='Vegèta:BAABLgAECn8gAAIDAAkJZAsKgwBdAQADAAkJZAsKgwBdAQABLgAFFAUJCAAfAOYcAA==.Veilaura:BAAALgAECggJDQAAAA==.Velarria:BAABLgAECn8lAAMfAAkJUh83FQCOAgAfAAkJUh83FQCOAgAZAAUJHw3DRACtAAAAAA==.Velikan:BAAALgAECgQJBwABLgAECgcJCAAUAAAAAA==.Velsiana:BAABLgAECn8UAAMeAAgJuRHvFQD5AAAbAAgJFg5ofQA+AQAeAAQJ4xXvFQD5AAAAAA==.Velveetah:BAAALgAECgUJCAABLgAECgkJHAAEAIkOAA==.Verbrennen:BAAALgAECgUJEQABLgAECgkJVAAGABYhAA==.Verdreht:BAAALgADCgEJAQABLgAECgkJVAAGABYhAA==.Verita:BAABLgAECn8zAAIlAAgJXiMcAgCxAgAlAAgJXiMcAgCxAgAAAA==.Verlynne:BAAALgADCgYJBgAAAA==.Verylikely:BAAALgAECgEJAgAAAA==.',
Vi='Viviann:BAABLgAECn8kAAIRAAkJeRFtEADFAQARAAkJeRFtEADFAQAAAA==.',
Vo='Voiager:BAAALgADCgcJCgAAAA==.',
Vr='Vrakal:BAAALgAECgkJDQAAAA==.',
Wa='Wantabehavoc:BAAALgADCgYJDQAAAA==.Wantadeznutz:BAAALgAECgIJAgAAAA==.Warnick:BAAALgADCgQJBQAAAA==.Warraxe:BAAALgAECgEJAgAAAA==.Wayloren:BAABLgAECn8yAAIBAAkJ9gzTdACEAQABAAkJ9gzTdACEAQAAAA==.Waystalker:BAAALgAECgMJAwAAAA==.Wayverly:BAAALgADCgUJBwABLgAECgkJJAALAFsMAA==.',
Wi='Wickathy:BAABLgAECn9RAAMoAAkJQSHYAgDDAgAoAAkJQSHYAgDDAgAMAAMJlg/vxACkAAAAAA==.Withering:BAAALgAECgYJCgAAAA==.',
Wo='Wolfcity:BAAALgADCgEJAQAAAA==.Wondertauren:BAAALgADCgYJCQAAAA==.Woodson:BAAALgADCgkJEAABLgAECggJIQAcALARAA==.Worstdps:BAAALgAFFAIJAwAAAA==.',
Wr='Wrkandtank:BAAALgAECgYJBgABLgAECggJFQAbAHcLAA==.',
Wu='Wuldorr:BAACLgAFFH8YAAIBAAYJEhfbEwBYAQABAAYJEhfbEwBYAQAuAAQKfycAAgEACQmsH0gkAJYCAAEACQmsH0gkAJYCAAAA.',
Wy='Wynnifred:BAAALgAECggJDQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.',
Xe='Xethreal:BAAALgADCgMJAwAAAA==.',
Xy='Xype:BAAALgAECgkJEQAAAA==.',
Xz='Xzara:BAABLgAECn8WAAIaAAYJ/xYTBQAaAQAaAAYJ/xYTBQAaAQABLgAECgcJHAAOAEQcAA==.',
Ya='Yastoria:BAAALgAECgcJEAAAAA==.',
Yi='Yinandtonic:BAAALgAECgEJBAAAAA==.Yivet:BAAALgAECgEJAQAAAA==.',
Ys='Yssaria:BAAALgADCgEJAQAAAA==.',
Yu='Yura:BAAALgAECgMJBAAAAA==.Yushulien:BAAALgADCgkJCQAAAA==.',
Yv='Yvvee:BAAALgADCgcJBwAAAA==.',
Za='Zaalim:BAAALgADCgQJBAAAAA==.Zaddy:BAAALgAECgEJAQAAAA==.Zapdôs:BAAALgAECgQJBAAAAA==.Zasko:BAAALgAECgEJAQAAAA==.',
Ze='Zeda:BAABLgAECn8dAAIGAAYJDB1OBQCgAQAGAAYJDB1OBQCgAQABLgAECgcJHAAOAEQcAA==.Zephyris:BAAALgAECgUJDAABLgAFFAkJJgAmAHkfAA==.',
Zh='Zheng:BAAALgAECgYJBgAAAA==.',
Zi='Zillia:BAAALgADCgMJAwAAAA==.',
Zo='Zonora:BAABLgAECn8eAAIPAAkJPBBhKADJAQAPAAkJPBBhKADJAQAAAA==.',
Zy='Zyphexd:BAAALgAECgYJDwAAAA==.Zyris:BAAALgADCgcJDQAAAA==.',
['Àz']='Àzñós:BAAALgAECgQJBwAAAA==.',
['Äs']='Ästro:BAAALgAECgQJBgABLgAECgkJLQAHAHcaAA==.',
['Äz']='Äzrael:BAABLgAECn9GAAIEAAkJTB9zAQC2AgAEAAkJTB9zAQC2AgAAAA==.',
['Åz']='Åznos:BAAALgAECgQJCAAAAA==.',
['Çr']='Çréwüsæðèr:BAABLgAECn8kAAINAAkJ2B5ACwA5AgANAAkJ2B5ACwA5AgAAAA==.',
['Ðe']='Ðecimus:BAAALgAECgQJCQAAAA==.',
['Ðì']='Ðìaßlo:BAACLgAFFH8IAAIfAAQJ5hzbWgDvAAAfAAQJ5hzbWgDvAAAuAAQKfzUABB8ACQljHf4cAHcCAB8ACAljHf4cAHcCABkABwlYFAQRALMBAAsAAQleABqbABUAAAAA.',
['Öb']='Öblïvïöñ:BAAALgAECgEJAwAAAA==.',
['Ød']='Ødin:BAAALgADCgYJBgABLgAECgkJNgAPABQfAA==.',
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
