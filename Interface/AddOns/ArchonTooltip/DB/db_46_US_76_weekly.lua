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

local lookup = {'Paladin-Retribution','DeathKnight-Unholy','DemonHunter-Havoc','Priest-Holy','Warrior-Fury','Monk-Windwalker','Druid-Restoration','Druid-Balance','Priest-Shadow','Hunter-Marksmanship','Paladin-Protection','DemonHunter-Devourer','Warrior-Protection','Mage-Frost','Paladin-Holy','Shaman-Restoration','Rogue-Subtlety','Druid-Guardian','Unknown-Unknown','DeathKnight-Blood','Shaman-Elemental','Evoker-Preservation','Evoker-Augmentation','Hunter-Survival','Monk-Mistweaver','DeathKnight-Frost','Warlock-Demonology','Rogue-Assassination','Priest-Discipline','Warlock-Destruction','Hunter-BeastMastery','Shaman-Enhancement','Monk-Brewmaster','Druid-Feral','Evoker-Devastation','Mage-Arcane','Rogue-Outlaw','Warrior-Arms','Warlock-Affliction','DemonHunter-Vengeance',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Aberaht:BAABLgAECn8mAAIBAAkJYCOqDQAgAwABAAkJYCOqDQAgAwAAAA==.',
Ad='Adamaro:BAAALgADCgYJCQAAAA==.',
Ae='Aenastian:BAABLgAFFH8IAAICAAMJSxkhjgDuAAACAAMJSxkhjgDuAAABLgAFFAQJDQADAAobAA==.',
Af='Affrica:BAAALgADCgEJAQABLgAECgYJGQAEAJ4PAA==.',
Ag='Agnu:BAAALgADCgcJBwAAAA==.Agraar:BAAALgAECgUJBwAAAA==.',
Ah='Ahgra:BAABLgAECn89AAIBAAkJugyVewB3AQABAAkJugyVewB3AQAAAA==.',
Ak='Akre:BAAALgAFFAIJBgAAAQ==.Akumä:BAAALgAECgUJCgAAAA==.',
Al='Aleannia:BAAALgAECgYJCgAAAA==.Alekz:BAAALgAECgYJDgAAAA==.Alestria:BAABLgAECn8bAAIBAAgJBRWobACVAQABAAgJBRWobACVAQAAAA==.Alibrexia:BAACLgAFFH8NAAIFAAQJTgWmFQC1AAAFAAQJTgWmFQC1AAAuAAQKfyAAAgUACQlrCRE2AHABAAUACQlrCRE2AHABAAAA.Alida:BAABLgAECn8sAAIFAAkJqAo8OABmAQAFAAkJqAo8OABmAQAAAA==.Alithvia:BAAALgAECgYJBgABLgAECgkJJQAGAAskAA==.Allisara:BAAALgADCgkJFgAAAA==.Alysae:BAACLgAFFH8lAAMHAAgJuBg0EQDtAQAHAAgJuBg0EQDtAQAIAAEJSQArWAAZAAAuAAQKfxsAAwcACAkrHeUdAE8CAAcACAkrHeUdAE8CAAgAAgllBxiYACgAAAAA.',
Am='Amabear:BAAALgAECgEJAQABLgAECgcJHAAJAP0cAA==.Ambrosse:BAAALgADCggJDwABLgAECgkJLQAGAHcaAA==.',
An='Anabug:BAAALgAECgMJBQAAAA==.Andelwynn:BAAALgAECgMJAwABLgAECgkJIwAKAB8LAA==.Angelsmentor:BAAALgAECgYJCgAAAA==.Aniellas:BAAALgAECgIJAgAAAA==.Annalese:BAAALgADCgUJCQABLgAECgkJIwAKAB8LAA==.',
Ar='Arabeli:BAAALgAECgEJAQAAAA==.Arbyss:BAAALgADCgcJDAAAAA==.Ardatha:BAAALgADCgcJFwAAAA==.Ariêz:BAAALgAECgIJAgAAAA==.Artio:BAABLgAECn8fAAMLAAgJIAW8BwB3AAABAAcJVAIgKQGIAAALAAUJAAe8BwB3AAAAAA==.',
As='Ashkada:BAAALgADCgQJBAAAAA==.Asterön:BAAALgAECgcJEwAAAA==.Astrocakes:BAAALgAECgMJAwABLgAFFAQJEgAMAMEUAA==.',
At='Athenä:BAACLgAFFH8rAAILAAgJbRGIAQDYAQALAAgJbRGIAQDYAQAuAAQKfzwAAgsACQl7HPkFAI4CAAsACQl7HPkFAI4CAAAA.Atsuma:BAABLgAECn8gAAINAAgJIAszJAAPAQANAAgJIAszJAAPAQAAAA==.',
Av='Avacynn:BAAALgAECgMJAwAAAA==.Aviz:BAAALgADCgMJAwAAAA==.',
Aw='Awtysmbb:BAAALgAECgUJBgABLgAFFAMJCgAOABIXAA==.',
Ay='Aylli:BAAALgAECgYJDAABLgAECgkJPwAEAIocAA==.',
['Aí']='Aísling:BAABLgAECn8yAAIPAAkJFB9sAQAdAgAPAAkJFB9sAQAdAgAAAA==.',
Ba='Baboii:BAAALgADCgIJAgAAAA==.Baconmecrazy:BAAALgAECgEJAQAAAA==.Badinngo:BAAALgADCggJDwABLgAECgkJJAAQABcgAA==.Bahiu:BAAALgAECgQJBAAAAA==.Bajafresh:BAAALgAECgQJBQAAAA==.Battleshaman:BAAALgADCgYJBgAAAA==.',
Bd='Bd:BAABLgAECn8dAAIRAAgJJxU5GABGAgARAAgJJxU5GABGAgAAAA==.',
Be='Beardmedaddy:BAAALgAECgYJBgABLgAECgkJMAAFAI4hAA==.Bearstavious:BAABLgAFFH8HAAISAAMJXxZoGADDAAASAAMJXxZoGADDAAAAAA==.Benjinana:BAABLgAECn8ZAAMEAAYJng+dOwAHAQAEAAYJng+dOwAHAQAJAAIJJQPOWgBMAAAAAA==.Benjis:BAAALgAECgIJAQAAAA==.Betterthanu:BAAALgADCgUJBQABLgADCgYJCgATAAAAAA==.',
Bg='Bg:BAAALgAECgYJBwAAAA==.',
Bi='Bige:BAAALgAECgYJEwAAAA==.Bilo:BAAALgAECgYJCAAAAA==.Bitelyus:BAAALgAECgUJCAAAAA==.',
Bl='Blazara:BAAALgAECgEJAQAAAA==.Blessedbymom:BAAALgADCgEJAQAAAA==.',
Bo='Bobius:BAAALgAECgkJDwAAAA==.Bobohizan:BAAALgADCgQJBAAAAA==.Bohde:BAABLgAFFH8QAAMCAAYJAiMZSwBcAQACAAUJAiMZSwBcAQAUAAEJAAAtUwAAAAAAAA==.Bolognaman:BAAALgAECgUJDAAAAA==.Bombjovi:BAABLgAECn8gAAMLAAkJchWNDgDaAQALAAkJchWNDgDaAQAPAAUJlA9ZVADmAAAAAA==.Bountty:BAAALgAECgQJBAAAAA==.',
Br='Brahmsthoven:BAAALgADCgIJAwAAAA==.Brandhoon:BAAALgAECgIJAwAAAA==.Branndhon:BAABLgAECn8qAAIHAAcJ5hV1NgC/AQAHAAcJ5hV1NgC/AQAAAA==.Bronislav:BAAALgAECgEJAQAAAA==.',
Bt='Btrflyprncss:BAAALgADCgMJAwAAAA==.',
Bu='Bubblemedic:BAAALgADCgIJAgAAAA==.Budde:BAAALgAECgUJBQAAAA==.Buffaloseven:BAABLgAECn8VAAMPAAcJ9gpMRAAvAQAPAAcJ9gpMRAAvAQABAAUJ9QSqIQGRAAABLgAFFAgJFgAOAOwMAA==.',
Ca='Cairdamane:BAABLgAECn8hAAIVAAkJ5BHuLgCFAQAVAAkJ5BHuLgCFAQAAAA==.Calidrina:BAABLgAECn8iAAIMAAkJMhyIQQDEAQAMAAkJMhyIQQDEAQAAAA==.Carm:BAAALgAECgYJBgAAAA==.Caroliná:BAAALgAECgUJDgAAAA==.Catcast:BAAALgAECgUJCAABLgAFFAMJCwAWACcPAA==.Catclaw:BAAALgAECgEJAQABLgAFFAMJCwAWACcPAA==.',
Ce='Celiri:BAABLgAECn8nAAIGAAkJrxCAIQCjAQAGAAkJrxCAIQCjAQAAAA==.Celldrassil:BAABLgAECn84AAIHAAkJZwhZXQAfAQAHAAkJZwhZXQAfAQAAAA==.Cereel:BAAALgAECgMJAwABLgAFFAQJEgAMAMEUAA==.',
Ch='Chadaracka:BAAALgAECgYJBwAAAA==.Chandelure:BAAALgAECgUJCwAAAA==.Chardaney:BAABLgAECn8jAAIKAAkJHwtDEwAqAQAKAAkJHwtDEwAqAQAAAA==.Cherryontop:BAABLgAECn8uAAIHAAgJVBQlMgDXAQAHAAgJVBQlMgDXAQAAAA==.Chido:BAAALgAECgUJBQAAAA==.Chozenone:BAAALgAECgUJEgAAAA==.Chozi:BAAALgAECgYJBwAAAA==.Chromosomie:BAABLgAFFH8JAAIXAAQJWgV5PwDJAAAXAAQJWgV5PwDJAAABLgAECgkJMAAOAOcbAA==.',
Ci='Cii:BAABLgAECn8iAAMLAAkJiBAiFwBoAQALAAgJNRAiFwBoAQABAAYJHw6t2wDkAAAAAA==.',
Co='Coconutwater:BAAALgAFFAEJAQAAAA==.Colandros:BAABLgAECn9CAAIYAAkJjQ2oGgDJAQAYAAkJjQ2oGgDJAQAAAA==.Colara:BAABLgAECn8iAAIMAAcJQQUvFgB7AAAMAAcJQQUvFgB7AAAAAA==.Colaux:BAAALgADCgQJBAAAAA==.Combobreaker:BAACLgAFFH8OAAIZAAMJVx56LgAAAQAZAAMJVx56LgAAAQAuAAQKfzQAAhkACQm+H/cHAB0DABkACQm+H/cHAB0DAAAA.Comoo:BAAALgAECgEJAQAAAA==.Correct:BAAALgAECgEJAQAAAA==.Cowbôy:BAAALgADCgkJEQAAAA==.',
Cr='Crassberry:BAACLgAFFH8lAAMCAAgJXx9ODgBsAgACAAgJXx9ODgBsAgAaAAEJkQhtEgBIAAAuAAQKfygAAgIACQk2JBQFAIMDAAIACQk2JBQFAIMDAAAA.Crazyraptor:BAAALgAECgYJDAABLgAECggJFQAbAHcLAA==.Crazèd:BAAALgADCgQJBAAAAA==.Crimes:BAAALgAECgIJAwAAAA==.',
Cu='Cutco:BAABLgAFFH8MAAIcAAUJ3xYuAQAgAQAcAAUJ3xYuAQAgAQAAAA==.',
Cy='Cyndal:BAABLgAECn8bAAIOAAYJOx1NcQCXAQAOAAYJOx1NcQCXAQAAAA==.Cyndle:BAABLgAECn8aAAIGAAYJARy2IwCUAQAGAAYJARy2IwCUAQABLgAECgYJGwAOADsdAA==.Cyntu:BAAALgAECgUJDwABLgAECgYJGwAOADsdAA==.',
['Cü']='Cüpid:BAAALgAECgYJBgAAAA==.',
Da='Dada:BAAALgAECgEJAQAAAA==.Dammithells:BAAALgADCgQJBAAAAA==.Dandamar:BAAALgAECgYJBgAAAA==.Dankbuds:BAAALgAECgkJDAAAAA==.Dankfists:BAAALgAECgUJBQABLgAECgkJDAATAAAAAA==.Dankhaze:BAAALgAFFAIJAgABLgAECgkJDAATAAAAAA==.Danksmash:BAAALgAECgkJBQABLgAECgkJDAATAAAAAA==.Dankzor:BAAALgAECgcJBQABLgAECgkJDAATAAAAAA==.Dark:BAAALgADCgEJAQAAAA==.Darthrevan:BAAALgAECgQJBwAAAA==.Dasharnkal:BAAALgADCgUJCAAAAA==.Dasvult:BAAALgAECgQJBgAAAA==.Dazex:BAABLgAECn8kAAMEAAcJHAY9TwCkAAAEAAcJ2gU9TwCkAAAdAAUJRwIVXQCLAAAAAA==.',
De='Deadpump:BAABLgAECn8fAAMbAAcJfRLFegBDAQAbAAcJfRLFegBDAQAeAAQJUQ4aOQDQAAAAAA==.Delainy:BAAALgAECgYJBgAAAA==.Demonsnotkey:BAAALgAECgYJCwAAAA==.Demoxus:BAAALgAECgQJBAAAAA==.Denker:BAAALgADCggJCAAAAA==.Denkzilla:BAAALgADCgIJAgAAAA==.Denzvic:BAAALgAECgEJAQAAAA==.Destro:BAAALgAECgEJAQAAAA==.Deusclaw:BAAALgAECgYJCgAAAA==.Devilah:BAAALgAECgEJAQAAAA==.',
Dh='Dharm:BAABLgAECn8wAAMfAAkJ9BjmMQAUAgAfAAkJ9BjmMQAUAgAYAAIJxQwAUABwAAAAAA==.',
Di='Dialsl:BAAALgADCgUJCQAAAA==.Digbickpanda:BAAALgAECgUJEQABLgAFFAQJEgAMAMEUAA==.Disowneege:BAABLgAECn8oAAIBAAgJuyE/IQCCAgABAAgJuyE/IQCCAgABLgAFFAgJIgAFAAcgAA==.Divinehymn:BAAALgAECgUJBQAAAA==.Diyos:BAAALgADCgYJCgAAAA==.',
Do='Dotndash:BAAALgAECgMJAwAAAA==.Doubledge:BAAALgAECgEJAQAAAA==.Doublejump:BAACLgAFFH8bAAIMAAUJjBN1SQANAQAMAAUJjBN1SQANAQAuAAQKfykAAgwACAk4HgMmADUCAAwACAk4HgMmADUCAAAA.',
Dr='Dragdh:BAAALgAECgcJEwABLgAECggJKgAgAJ8cAA==.Dragnas:BAABLgAECn8qAAQgAAgJnxxRDADtAQAgAAgJnxxRDADtAQAQAAcJrBT2PQC2AQAVAAQJvhaKXgDJAAAAAA==.Dragonisa:BAAALgAFFAEJAQAAAA==.Dragun:BAAALgADCgIJAgAAAA==.Draiocht:BAAALgADCgMJBAABLgAECgkJPwAEAIocAA==.Drakeskid:BAAALgAECgQJBwABLgAFFAQJBgAhALgKAA==.Drakthall:BAAALgAECgIJAwAAAA==.Dralionethny:BAAALgAECgIJAgAAAA==.Dramakiller:BAABLgAECn8aAAMfAAcJowqDlAAXAQAfAAcJowqDlAAXAQAKAAMJPAKLOAA9AAAAAA==.Drchi:BAAALgAECgEJAQABLgAECgYJGQAiAIcVAA==.Drcornbread:BAABLgAECn8ZAAMiAAYJhxXUGgA2AQAiAAYJhxXUGgA2AQASAAEJ0AMnigATAAAAAA==.Drcornellia:BAAALgAECgUJCAABLgAECgYJGQAiAIcVAA==.Drdarkskin:BAAALgAECgcJDQAAAA==.Drdreggs:BAABLgAECn8pAAMeAAkJmBZhEQAwAQAbAAgJuBSYTwDZAQAeAAYJmxdhEQAwAQAAAA==.Dreggs:BAAALgADCgcJEwAAAA==.Drewskie:BAAALgADCgQJBAAAAA==.Drizztin:BAAALgADCgEJAQAAAA==.Drprominus:BAABLgAECn8gAAIPAAgJACLaCQDuAgAPAAgJACLaCQDuAgAAAA==.Drthargyll:BAAALgADCgYJDgABLgAECggJIAAPAAAiAA==.Drvoid:BAAALgAECgEJAQAAAA==.',
Du='Dushman:BAAALgAECgEJAQAAAA==.',
Dy='Dykdanglr:BAAALgADCgYJBgABLgAECgQJCAATAAAAAA==.',
['Dí']='Dígifóx:BAAALgAECgEJAgAAAA==.Dígífóx:BAAALgAFFAEJAQAAAA==.',
Ea='Earthereal:BAABLgAECn83AAIZAAkJ5hePFQBtAgAZAAkJ5hePFQBtAgAAAA==.',
El='Elastar:BAABLgAECn8mAAINAAkJ6RYKDgApAgANAAkJ6RYKDgApAgAAAA==.Ellimist:BAECLgAFFH8nAAIQAAcJMhyZBQBvAgAQAAcJMhyZBQBvAgAuAAQKfykAAxAACQl9G3QXAFoCABAACQl9G3QXAFoCABUABQk0FxdQAAcBAAAA.Elsan:BAAALgAECgEJAQAAAA==.Elycee:BAACLgAFFH8IAAIfAAMJyyXKRwAeAQAfAAMJyyXKRwAeAQAuAAQKfyIAAx8ACQmtJcwIABMDAB8ACAk+JswIABMDAAoACAmWGZYgACECAAAA.Elysria:BAAALgADCgYJBgAAAA==.Elí:BAAALgAECgQJBAAAAA==.',
En='Encrid:BAAALgAECgcJDwABLgAFFAMJCwAXAGUZAA==.Enhasa:BAABLgAECn8gAAICAAkJ/hUnMQA6AgACAAkJ/hUnMQA6AgABLgAECgYJGgABAOggAA==.Enoeht:BAABLgAECn82AAIDAAkJ2gsiIQBvAQADAAkJ2gsiIQBvAQAAAA==.Enveliria:BAAALgAECgcJEgABLgAFFAQJDQADAAobAA==.',
Er='Eraser:BAAALgAECgYJDgAAAA==.Erazar:BAABLgAECn9HAAIjAAgJ+hcNAQA7AQAjAAgJ+hcNAQA7AQAAAA==.Eriah:BAAALgADCgkJCQAAAA==.Erickk:BAABLgAECn8wAAMOAAkJ5xuuQgATAgAOAAkJnBquQgATAgAkAAQJVx1SCwAkAQAAAA==.',
Es='Essense:BAABLgAECn8mAAIEAAkJmyRIAwApAwAEAAkJmyRIAwApAwAAAA==.',
Ex='Exodari:BAABLgAECn87AAIgAAkJ7hgICwAHAgAgAAkJ7hgICwAHAgAAAA==.',
Fa='Fabbioh:BAAALgADCgEJAQAAAA==.Fadeddh:BAACLgAFFH8SAAIMAAQJwRR4JAC7AAAMAAQJwRR4JAC7AAAuAAQKfzAAAgwACQn/G04jAEMCAAwACQn/G04jAEMCAAAA.Faizarah:BAAALgAECgYJBgAAAA==.Faydien:BAAALgAECgEJAgAAAA==.',
Fe='Fearnoevil:BAAALgADCgMJAwAAAA==.Fel:BAABLgAECn8RAAIMAAgJjRqSXgBtAQAMAAgJjRqSXgBtAQAAAA==.Fellius:BAAALgAECgEJAQAAAA==.Fellkarras:BAAALgAECgYJDwABLgAFFAMJDgAZAFceAA==.Fent:BAABLgAECn8VAAIbAAgJdwsBcgBWAQAbAAgJdwsBcgBWAQAAAA==.',
Fi='Fiddich:BAAALgAECgYJBgAAAA==.Fillthy:BAACLgAFFH8gAAIZAAcJYRlxDgAmAgAZAAcJYRlxDgAmAgAuAAQKfy4AAxkACQlYIkYDAEcDABkACQlYIkYDAEcDAAYAAwkhCQJ2AGQAAAAA.Finnigann:BAAALgAECgYJCwAAAA==.Firenmylazer:BAAALgAECgQJBAAAAA==.Fistav:BAAALgADCgcJDgAAAA==.Fizban:BAABLgAECn8mAAIOAAgJnQqLFADOAAAOAAgJnQqLFADOAAAAAA==.',
Fl='Flappybird:BAAALgAECgYJCQABLgAFFAQJEgAMAMEUAA==.Flasan:BAAALgADCgEJAQAAAA==.Flazz:BAAALgADCgIJAwAAAA==.Flazzan:BAAALgADCgEJAQAAAA==.Flik:BAAALgAECggJCAABLgAFFAMJFAAHANMZAA==.',
Fo='Fogbringer:BAAALgAECgIJAwAAAA==.Four:BAAALgADCgQJBAAAAA==.',
Fr='Frejä:BAAALgAECgQJBQABLgAECgQJDAATAAAAAA==.Freyah:BAAALgAECgYJEwAAAA==.Frostmay:BAAALgAECgIJAgAAAA==.',
Fu='Furrybawlz:BAAALgAECgUJCgABLgAECgYJDQATAAAAAA==.',
Ga='Gabran:BAAALgAECgcJBwAAAA==.Gadogear:BAABLgAECn8oAAIOAAkJ7hdGPQAmAgAOAAkJ7hdGPQAmAgAAAA==.Galahan:BAAALgAECgUJBgAAAA==.Garlick:BAAALgAECgUJBQABLgAECggJRwAjAPoXAA==.Garlik:BAAALgADCgMJBAAAAA==.',
Ge='Gertra:BAAALgAECgEJAgABLgAECgYJCAATAAAAAA==.',
Gf='Gfr:BAABLgAECn8YAAMeAAkJmBjJAwBRAgAeAAkJmBjJAwBRAgAbAAMJbRXRDQC+AAAAAA==.',
Gi='Girthrichard:BAAALgAECgYJDAAAAA==.',
Gl='Glassdragon:BAABLgAECn8nAAIBAAkJUQz+hABlAQABAAkJUQz+hABlAQAAAA==.Gllor:BAAALgADCgIJAgAAAA==.',
Go='Goatcheeze:BAABLgAECn8cAAIkAAkJLhUFBADGAQAkAAkJLhUFBADGAQAAAA==.Goatylocks:BAABLgAECn8rAAMeAAkJ7RWADQBlAQAbAAgJvRCWVACeAQAeAAYJLByADQBlAQAAAA==.Gohlemsaurus:BAAALgAECgYJEQAAAA==.Goldenchild:BAAALgAFFAMJBAABLgAFFAQJEgAMAMEUAA==.',
Gr='Gratfldeadly:BAAALgADCgEJAQABLgAECgYJDAATAAAAAA==.Greatluckydo:BAAALgADCgEJAQAAAA==.Grishnakh:BAAALgAECgQJBAAAAA==.Grozlek:BAAALgADCgYJBgAAAA==.',
Gu='Gulen:BAABLgAECn8ZAAIQAAkJaR7PIwA4AgAQAAkJaR7PIwA4AgAAAA==.',
Gw='Gwendyla:BAAALgADCgkJFgAAAA==.',
Gy='Gyousei:BAAALgAECgUJBQAAAA==.',
['Gí']='Gíga:BAABLgAECn8XAAIfAAgJ7RPdKQAPAgAfAAgJ7RPdKQAPAgAAAA==.',
Ha='Hafnium:BAAALgAECgIJAgAAAA==.Hamish:BAAALgAFFAEJAQAAAA==.Hanhaine:BAACLgAFFH8GAAIIAAMJcwWzOQCUAAAIAAMJcwWzOQCUAAAuAAQKfywAAggACQnqFlETADoCAAgACQnqFlETADoCAAAA.Hazirat:BAAALgAECgYJDAAAAA==.',
He='Hedlie:BAAALgAECggJDQAAAA==.Hellenkeller:BAECLgAFFH8HAAIZAAYJhw/TIgBYAQAZAAYJhw/TIgBYAQAuAAQKfx8AAhkABwkzITQTADMCABkABwkzITQTADMCAAEuAAUUBwkgACUA9xsA.Heloisa:BAAALgAECgYJEQAAAA==.Helrazr:BAAALgAFFAEJAgAAAA==.Henshin:BAACLgAFFH8UAAIHAAMJ0xnHDQDfAAAHAAMJ0xnHDQDfAAAuAAQKf0QAAwcACQmxHXcQAM4CAAcACQmxHXcQAM4CAAgAAgk4Dl+LADUAAAAA.',
Hi='Hitt:BAAALgAECgcJCAAAAA==.',
Ho='Hogwortsfun:BAAALgAECgkJAgAAAA==.Holirolla:BAAALgAECgMJAwAAAA==.Holyhim:BAAALgADCgIJAgAAAA==.Holyshawk:BAAALgAECgEJAwAAAA==.Holysudz:BAAALgAECgEJAQAAAA==.Hooflora:BAAALgADCgEJAQABLgAECgYJHwADAHAXAA==.Hottyshmotty:BAAALgAECgEJAQAAAA==.Hourglass:BAABLgAECn9AAAMfAAkJlhrLHQByAgAfAAkJlhrLHQByAgAKAAQJ1g3oXwDBAAAAAA==.',
Hr='Hroc:BAAALgAECgUJCwAAAA==.',
Hu='Hunterviral:BAAALgADCgEJAgAAAA==.Huntthejuan:BAAALgADCgUJBQAAAA==.',
Ic='Icyowneege:BAAALgADCgUJBQABLgAFFAgJIgAFAAcgAA==.Icywolfy:BAAALgAECgYJCAAAAA==.',
Ig='Igreetyou:BAABLgAECn8pAAIbAAcJXR5uLAAoAgAbAAcJXR5uLAAoAgAAAA==.',
Il='Illie:BAABLgAECn8mAAIgAAkJShyHBQCtAgAgAAkJShyHBQCtAgAAAA==.Illune:BAACLgAFFH8KAAIOAAMJEhf2eADnAAAOAAMJEhf2eADnAAAuAAQKfysAAw4ACQlgGkkzAEwCAA4ACQlgGkkzAEwCACQABglSDhkJAFsBAAAA.',
Im='Imanbearpig:BAABLgAFFH8HAAISAAMJ+whyFQBdAAASAAMJ+whyFQBdAAAAAA==.Imleapingit:BAABLgAECn8wAAIFAAkJjiHZBgDxAgAFAAkJjiHZBgDxAgAAAA==.',
In='Intoodeep:BAABLgAFFH8FAAIcAAMJ3QNoAgCmAAAcAAMJ3QNoAgCmAAAAAA==.Intoodragons:BAACLgAFFH8RAAIXAAMJJQhYGwCgAAAXAAMJJQhYGwCgAAAuAAQKfzYAAxcACQmcFGocAPIBABcACQmcFGocAPIBACMABglaBfokAP4AAAAA.Inyah:BAAALgAECgIJAgAAAA==.',
Io='Ionzz:BAABLgAECn8ZAAIDAAkJrx+iCADYAgADAAkJrx+iCADYAgAAAA==.',
Ir='Ir:BAAALgAFFAMJAwAAAA==.Iroann:BAAALgAECgcJEgAAAA==.',
Is='Isawarriorr:BAACLgAFFH8FAAINAAMJJR0vFwDiAAANAAMJJR0vFwDiAAAuAAQKfywAAg0ACQmCI4kDAB8DAA0ACQmCI4kDAB8DAAAA.Ishaq:BAAALgAECgQJBQABLgAECggJIgAhAP0FAA==.Ishdo:BAAALgAECgUJBgABLgAECggJIgAhAP0FAA==.Ishdu:BAAALgAECgQJBAABLgAECggJIgAhAP0FAA==.Ishkhan:BAABLgAECn8iAAMhAAgJ/QVLQgDxAAAhAAgJgAVLQgDxAAAGAAYJUQUMYACaAAAAAA==.Ishmael:BAACLgAFFH8RAAMNAAMJjxkfGQDPAAANAAMJjxkfGQDPAAAFAAEJiw2cUwBEAAAuAAQKfxQAAwUACQk6HkIWAD0CAAUACQkwHEIWAD0CAA0AAglmGzk8AIIAAAAA.Ishwar:BAAALgADCgYJBgABLgAECggJIgAhAP0FAA==.',
Ja='Jakytreehorn:BAACLgAFFH8PAAMQAAcJsQglSwDEAAAQAAUJ5QMlSwDEAAAVAAYJwwlyEwC7AAAuAAQKfzkAAxUACQn9Fn4cAP0BABUACAn3F34cAP0BABAACQlCFQwoAPABAAAA.Jasher:BAAALgAECgYJBgAAAA==.Jaydm:BAABLgAECn8dAAImAAYJRxiPHwBhAQAmAAYJRxiPHwBhAQABLgAFFAgJFgAOAOwMAA==.',
Je='Jenevelle:BAAALgAECgcJCgAAAA==.Jerisil:BAAALgADCgQJBAAAAA==.Jet:BAABLgAECn8aAAIBAAYJ6CAySwABAgABAAYJ6CAySwABAgAAAA==.',
Ji='Jibbajabba:BAAALgADCgcJBwAAAA==.Jimbo:BAABLgAFFH8KAAIbAAMJDh/dXgAKAQAbAAMJDh/dXgAKAQABLgAFFAgJJQACAF8fAA==.',
Jo='Johnmayer:BAAALgAECgQJBQAAAA==.',
Ju='Judgecalypso:BAAALgAECgQJBgAAAA==.Judgiah:BAAALgAECgUJBQAAAA==.Julthaenia:BAABLgAECn8lAAQnAAcJZx8ZBgAgAgAnAAcJZx8ZBgAgAgAeAAQJGAr1SwCJAAAbAAUJcQsK9QB4AAABLgAFFAQJDQADAAobAA==.Justeatjuan:BAAALgAECgMJAwAAAA==.',
Ka='Kagebushin:BAAALgAECgMJBAAAAA==.Kalazin:BAAALgAECgUJBQAAAA==.Kalimah:BAAALgADCgMJAwAAAA==.Kallekgos:BAAALgAECgEJAQAAAA==.Kalofelement:BAAALgAECgcJCAAAAA==.Kamiguru:BAAALgADCgEJAQABLgAFFAUJCAAPAHsJAA==.Karash:BAAALgAECgYJCAABLgAECggJGAAfAJgNAA==.Karmaisab:BAAALgADCgEJAQAAAA==.Karnrae:BAACLgAFFH8MAAIBAAMJNQ48IwDJAAABAAMJNQ48IwDJAAAuAAQKfzAAAgEACQnuE2cIAGcBAAEACQnuE2cIAGcBAAAA.Karynos:BAABLgAECn8nAAMbAAkJyQ1zVQCcAQAbAAkJmgxzVQCcAQAeAAcJyQkOIwA/AQAAAA==.Katnelly:BAAALgAECgMJAwAAAA==.Kazmacoryy:BAAALgAECgYJEAAAAA==.',
Ke='Keedis:BAAALgAECgEJAQAAAA==.Keristrasza:BAAALgAFFAEJAQABLgAFFAgJKAAQAOYbAA==.',
Kh='Khlarm:BAAALgADCgIJAgABLgAECgkJMAAfAPQYAA==.',
Ki='Kileely:BAAALgAECgMJAwAAAA==.Kirintore:BAAALgAECgUJCQAAAA==.',
Kk='Kkaiser:BAAALgAECgUJBQAAAA==.',
Kl='Klaudeus:BAAALgAECgEJAQAAAA==.',
Ko='Kodian:BAAALgADCgEJAQAAAA==.Kolypso:BAABLgAECn8bAAIfAAkJvhWxLwAeAgAfAAkJvhWxLwAeAgAAAA==.Konceal:BAAALgAECgEJAQAAAA==.Konspiracy:BAABLgAECn8pAAIeAAkJpxawBgD0AQAeAAkJpxawBgD0AQAAAA==.Konvict:BAAALgAECgIJAwABLgAECgYJDQATAAAAAA==.',
Kr='Kraguva:BAAALgAECgUJBQAAAA==.Krataar:BAABLgAECn8hAAIFAAkJEyGhDACgAgAFAAkJEyGhDACgAgAAAA==.Kravvan:BAAALgAECgUJCgABLgAECggJJgAOAJ0KAA==.Krousvor:BAAALgAECgQJBwAAAA==.Kryph:BAABLgAECn8dAAICAAkJQAiQegBuAQACAAkJQAiQegBuAQAAAA==.',
Ku='Kugruk:BAAALgAECgcJDAAAAA==.Kurjo:BAAALgAECgMJBAAAAA==.',
Ky='Kyleschlong:BAAALgAECgMJCAAAAA==.Kyndreith:BAAALgAECgMJAwAAAA==.',
['Kä']='Kämpfer:BAABLgAECn9SAAIFAAkJFiEUCADeAgAFAAkJFiEUCADeAgAAAA==.',
La='Lafiel:BAABLgAECn8dAAMEAAkJGgtKPABJAQAEAAkJGgtKPABJAQAJAAIJ1QiQdwBRAAAAAA==.Landiedoo:BAAALgAECgkJCgAAAA==.Laurana:BAAALgADCgYJBgAAAA==.Laurandre:BAAALgAECgcJBwAAAA==.Laverna:BAAALgADCgMJBAAAAA==.Lazeras:BAAALgAECgUJCgABLgAFFAEJAgATAAAAAA==.',
Le='Lefay:BAAALgAECgEJAgAAAA==.Leprawnjames:BAAALgAECggJCwABLgAECgkJGQASAKofAA==.Letsgetwet:BAAALgADCgYJBgAAAA==.',
Li='Liefic:BAAALgAECgcJDgAAAA==.Lillavender:BAAALgADCgYJBgAAAA==.Limon:BAAALgADCgIJAgAAAA==.',
Lo='Loadin:BAAALgAECgIJAgAAAA==.Lockaflockå:BAAALgADCgMJAwAAAA==.Locke:BAAALgAECgMJAgABLgAECgYJGgABAOggAA==.Lonoh:BAAALgAECgcJEgAAAA==.Lozmoji:BAAALgAECgYJBgABLgAFFAMJBgAIAHMFAA==.',
Lu='Luan:BAAALgAECgMJAwAAAA==.Lucariø:BAAALgADCgcJDAAAAA==.Lucidbonsai:BAAALgADCggJCAAAAA==.Luckykilla:BAACLgAFFH8FAAIcAAQJ+Qg1CADXAAAcAAQJ+Qg1CADXAAAuAAQKfy4AAhwACQleHtACAJ4CABwACQleHtACAJ4CAAAA.Lucÿ:BAACLgAFFH8RAAIQAAYJKBCcHgB8AQAQAAYJKBCcHgB8AQAuAAQKfyoAAxAACAnjHiEFAJIBABAABwnvHyEFAJIBABUABglREskIAMcAAAAA.Lula:BAAALgADCgMJAwAAAA==.Lurith:BAABLgAECn9qAAMCAAkJhhwUAwAtAgACAAkJfBwUAwAtAgAUAAkJQRWYAgCBAQAAAA==.Lutreaux:BAAALgADCgEJAQAAAA==.Luxtyrannica:BAABLgAECn8pAAIBAAkJ3R6fFQDBAgABAAkJ3R6fFQDBAgAAAA==.',
Ly='Lydrain:BAAALgAECgEJAQAAAA==.Lysandria:BAABLgAECn8rAAIOAAkJmw3bagCmAQAOAAkJmw3bagCmAQAAAA==.',
Ma='Macrosblack:BAAALgADCgMJAwAAAA==.Madamerouge:BAAALgAECgIJAgABLgAECgYJGQAiAIcVAA==.Magearino:BAABLgAECn8nAAIOAAgJnRasXwDBAQAOAAgJnRasXwDBAQAAAA==.Malafore:BAAALgADCgEJAQAAAA==.Malcolm:BAAALgAECgEJAgABLgAECgkJMwAFACsWAA==.Malcrux:BAAALgAECgIJAgAAAA==.Marcopally:BAAALgAECgQJBAAAAA==.Marluxia:BAACLgAFFH8mAAISAAgJ7wkjCADWAAASAAgJ7wkjCADWAAAuAAQKfxoAAhIACAkhE/YMALkBABIACAkhE/YMALkBAAAA.Mastamonk:BAAALgAECgQJBAAAAA==.Materfamilia:BAAALgAECgQJBAAAAA==.Mattbull:BAACLgAFFH8LAAMXAAMJZRmJOwDZAAAXAAMJZRmJOwDZAAAjAAEJ1xNICQBXAAAuAAQKfx4AAyMABgmqJFcNAAQCACMABglCIlcNAAQCABcABgl5Il8gANYBAAAA.Mayu:BAAALgAECgEJAwAAAA==.',
Me='Medjrab:BAACLgAFFH8UAAICAAUJxhjmYwAvAQACAAUJxhjmYwAvAQAuAAQKfzIAAgIACQlLIjcTANUCAAIACQlLIjcTANUCAAAA.Meristem:BAABLgAECn80AAIIAAkJABJSIgC2AQAIAAkJABJSIgC2AQAAAA==.Merko:BAAALgADCgkJEQAAAA==.',
Mi='Miaan:BAAALgADCgYJBgAAAA==.Miette:BAAALgADCgMJAwAAAA==.Mihonk:BAAALgADCgQJBAAAAA==.Mintycrx:BAABLgAECn8fAAIOAAkJHhGZUwDiAQAOAAkJHhGZUwDiAQAAAA==.Missfist:BAAALgADCgIJAgAAAA==.Mistlocke:BAAALgADCgMJAwAAAA==.',
Mn='Mngwa:BAAALgAECgQJCwAAAA==.',
Mo='Moegu:BAABLgAECn8cAAIoAAkJFBYXCAD3AQAoAAkJFRYXCAD3AQAAAA==.Mog:BAACLgAFFH8SAAMbAAMJLyAWLACrAAAbAAIJwSIWLACrAAAnAAEJCxs8CgBbAAAuAAQKfzkABBsACQmeI/sVAKECABsABwnVI/sVAKECACcAAwmVI6kYAP4AAB4AAwkJEsI2ANsAAAAA.Mogma:BAAALgAECgQJBAAAAA==.Moncatsera:BAAALgAECgQJBAAAAA==.Mondgrille:BAAALgAECgQJBAABLgAECgYJDQATAAAAAA==.Monora:BAABLgAECn8aAAIZAAgJ6wutSgBBAQAZAAgJ6wutSgBBAQAAAA==.Montress:BAABLgAECn8UAAIEAAgJBhD3JwCGAQAEAAgJBhD3JwCGAQAAAA==.Moomoohealz:BAACLgAFFH8TAAIIAAMJ8RneDwC9AAAIAAMJ8RneDwC9AAAuAAQKfz4AAggACQkoIW8IAM0CAAgACQkoIW8IAM0CAAAA.Moomoorage:BAAALgAECgEJAQABLgAECggJCwATAAAAAA==.Moonbounds:BAACLgAFFH8oAAIQAAgJ5hu+AwCZAgAQAAgJ5hu+AwCZAgAuAAQKfzgAAxAACQndJFEDAEQDABAACQndJFEDAEQDABUAAQnZH4Z5AF0AAAAA.Moondoggey:BAAALgAECgMJAwAAAA==.Morgana:BAAALgADCgIJAgAAAA==.Mortemcleric:BAAALgADCgYJBgAAAA==.Mousechief:BAABLgAECn9LAAIVAAkJvwlzBQAiAQAVAAkJvwlzBQAiAQAAAA==.Moxnix:BAABLgAECn8fAAMZAAgJeBAwCwD/AAAZAAcJfA4wCwD/AAAhAAQJjgVYXQCZAAABLgAECggJGAAfAJgNAA==.Moxxzi:BAAALgAFFAEJAgAAAA==.',
Mu='Muhfookinbak:BAABLgAECn8kAAMQAAkJFyDbEADJAgAQAAkJFyDbEADJAgAVAAQJhxiYXQDLAAAAAA==.Mulann:BAAALgAECgEJAQAAAA==.',
Mv='Mvse:BAAALgAECgEJAgAAAA==.',
My='Myor:BAAALgADCgMJAwAAAA==.',
['Mà']='Màttbull:BAABLgAFFH8HAAIMAAMJcw7xZwC9AAAMAAMJcw7xZwC9AAABLgAFFAMJCwAXAGUZAA==.',
['Mä']='Märcøsferätv:BAAALgAECgEJAQAAAA==.',
Na='Naesta:BAAALgAECgYJCAAAAA==.Naksu:BAAALgAECgEJAQABLgAECgkJKAAMAHEJAA==.Naksù:BAABLgAECn8oAAIMAAkJcQkijAAIAQAMAAkJcQkijAAIAQAAAA==.Namal:BAAALgAECgQJBQAAAA==.Narenae:BAABLgAECn8lAAIGAAkJCyRABABIAwAGAAkJCyRABABIAwAAAA==.Nastalan:BAAALgADCgYJEAAAAA==.',
Ne='Necrovoid:BAAALgAECgEJAQAAAA==.Nefari:BAAALgADCgMJAwAAAA==.Neifeb:BAABLgAECn8uAAIfAAkJeRf2NwD+AQAfAAkJeRf2NwD+AQAAAA==.Nephthys:BAAALgADCgQJBAAAAA==.',
Ni='Niallivdam:BAABLgAECn8wAAMjAAgJUxztAwBHAgAjAAgJUxztAwBHAgAWAAYJ0hfJEwCNAQAAAA==.Nights:BAAALgAECgIJAgABLgAFFAgJDgACAEEUAA==.Nightsoul:BAAALgADCgEJAQAAAA==.Ninh:BAACLgAFFH8WAAIZAAMJvwVHIQB2AAAZAAMJvwVHIQB2AAAuAAQKf1UAAhkACQn6FOkcADECABkACQn6FOkcADECAAAA.',
No='Nomissius:BAAALgADCgcJDQAAAA==.Nooblè:BAAALgADCgMJAwAAAA==.Notsodemon:BAABLgAECn8eAAMMAAgJfxSGUwCLAQAMAAgJfxSGUwCLAQADAAIJnwrPYwBUAAAAAA==.Notsoevoker:BAAALgAECgMJAwABLgAECggJHgAMAH8UAA==.Notsomonk:BAAALgADCgMJAwABLgAECggJHgAMAH8UAA==.',
Ny='Nykara:BAAALgAECgUJBQAAAA==.Nyxwing:BAAALgADCgYJBgAAAA==.',
['Nå']='Nåld:BAAALgAFFAEJAQAAAA==.',
Oa='Oakendorf:BAAALgAECgEJAQABLgAECgEJAgATAAAAAA==.',
Ob='Obvinotagirl:BAAALgAECggJDwAAAA==.',
Od='Oddpocalypse:BAAALgAECgEJAgAAAA==.',
Og='Ogsikko:BAAALgAECgYJCwABLgAECggJGAAbAJAeAA==.Ogsikkotv:BAABLgAECn8YAAIOAAYJ/BmQhwDCAQAOAAYJ/BmQhwDCAQABLgAECggJGAAbAJAeAA==.',
Ok='Okathra:BAAALgAECgQJBAABLgAFFAMJCQAgAMIbAA==.',
On='Onebadmutha:BAABLgAECn8ZAAIbAAkJ+AwpVACgAQAbAAkJ+AwpVACgAQAAAA==.Ontop:BAACLgAFFH8HAAIfAAMJoBX7HgD0AAAfAAMJoBX7HgD0AAAuAAQKfygAAh8ACQnvGxocAF4CAB8ACQnvGxocAF4CAAAA.',
Or='Orb:BAABLgAECn8/AAQBAAkJfhu4AwAMAgABAAkJexu4AwAMAgAPAAkJOBY/BQAUAQALAAYJlQ/EHgATAQAAAA==.Orcfreeza:BAAALgAECgQJDAAAAA==.Ortinks:BAABLgAECn8tAAIOAAkJuhUfBwCLAQAOAAkJuhUfBwCLAQAAAA==.',
Ow='Owneege:BAACLgAFFH8iAAIFAAgJByD/AQCKAgAFAAgJByD/AQCKAgAuAAQKfzMAAgUACQkEIx4CAKADAAUACQkEIx4CAKADAAAA.',
Pa='Painsaw:BAAALgADCgYJBgAAAA==.Pallinar:BAABLgAECn83AAIBAAkJGhUwPwAJAgABAAkJGhUwPwAJAgAAAA==.Pandamak:BAAALgAECgUJCAAAAA==.Pasquale:BAABLgAECn8hAAIhAAcJRSH9FAAFAgAhAAcJRSH9FAAFAgAAAA==.',
Pe='Pebbles:BAABLgAECn8jAAIBAAgJbxkrRAD5AQABAAgJbxkrRAD5AQAAAA==.Pedorus:BAAALgAECgEJAQABLgAFFAYJEQAQACgQAA==.Pedroia:BAABLgAECn8hAAQcAAgJsBEDAQBOAQAcAAgJsBEDAQBOAQARAAcJMQYDNgD9AAAlAAIJNAcAIABPAAAAAA==.Peridaxx:BAAALgAECgIJAgAAAA==.Pesty:BAAALgAECgMJCQAAAA==.',
Ph='Phe:BAABLgAECn8XAAMIAAcJhw4QPAAhAQAIAAcJhw4QPAAhAQAHAAYJpQvzcAADAQAAAA==.Pheraree:BAAALgAECgEJAQAAAA==.Phooboo:BAAALgAECgkJBQAAAA==.',
Pi='Pidion:BAAALgADCgYJDAAAAA==.Pilgrimm:BAECLgAFFH8gAAMlAAcJ9xvSAQC8AQAlAAYJ+RrSAQC8AQARAAYJQR5ODQDzAAAuAAQKfyQAAxEACQl7IrIDAGADABEACQl0IrIDAGADACUABQkIHzgLAGcBAAAA.Pixyl:BAAALgAECgYJDAAAAA==.',
Pl='Plaguerott:BAABLgAECn83AAIaAAkJeA9TDgCQAQAaAAkJeA9TDgCQAQAAAA==.Plusultra:BAAALgADCgkJEQAAAA==.Pluto:BAAALgAFFAQJBAAAAA==.',
Po='Poby:BAAALgADCgcJBwAAAA==.Polydh:BAABLgAECn8wAAIoAAkJriT3AAA9AwAoAAkJriT3AAA9AwAAAA==.Poobah:BAABLgAECn8kAAMVAAkJYQaVWQDXAAAVAAgJHQaVWQDXAAAQAAcJCgMLigDHAAAAAA==.Popscotch:BAABLgAECn8jAAMnAAkJEg3OCQCkAQAnAAcJRg7OCQCkAQAbAAkJwAu3XQCGAQAAAA==.Pouffant:BAABLgAECn8iAAIBAAkJyBNhVwDFAQABAAkJyBNhVwDFAQAAAA==.',
Pr='Pronoz:BAABLgAECn8mAAIBAAcJfRJjlABLAQABAAcJfRJjlABLAQAAAA==.',
Pu='Punchy:BAAALgADCgEJAQAAAA==.Purpyl:BAAALgADCgkJCQABLgAECggJIQAcALARAA==.',
Pw='Pwnageddon:BAABLgAECn82AAMLAAgJ2h6pCABLAgALAAcJkyKpCABLAgABAAUJhxUW4gDJAAAAAA==.Pwnjitsu:BAACLgAFFH8IAAIGAAMJ2R61FgALAQAGAAMJ2R61FgALAQAuAAQKfz4AAgYACQk8JT8CAEsDAAYACQk8JT8CAEsDAAAA.',
Py='Pyrothermia:BAACLgAFFH8WAAIOAAgJ7AxyIQD6AQAOAAgJ7AxyIQD6AQAuAAQKfyYAAg4ACQn/HIoqAMgCAA4ACQn/HIoqAMgCAAAA.',
['Pô']='Pôlgara:BAAALgADCgYJBgABLgAECgkJMgAPABQfAA==.',
Qt='Qtkillz:BAAALgADCgQJBAAAAA==.',
Qu='Quinlekd:BAAALgAECgQJBAABLgAECgkJMwAbAJ4iAA==.',
Ra='Rakugan:BAAALgAECgQJAwAAAA==.Rancayden:BAAALgAECgMJBAAAAA==.Rawhoof:BAACLgAFFH8WAAIFAAMJFSAJEADiAAAFAAMJFSAJEADiAAAuAAQKf1UAAgUACQlHJq4BAGMDAAUACQlHJq4BAGMDAAAA.Razak:BAACLgAFFH8JAAIgAAMJwhvNDAD0AAAgAAMJwhvNDAD0AAAuAAQKfzoAAiAACQniI1oBACsDACAACQniI1oBACsDAAAA.',
Re='Redlock:BAAALgAECgYJBgAAAA==.Redtiger:BAAALgADCgYJBgAAAA==.Renisa:BAABLgAECn8iAAIMAAgJqRkLUgCPAQAMAAgJqRkLUgCPAQAAAA==.Retman:BAABLgAECn8UAAIBAAcJtg+X8QDJAAABAAcJtg+X8QDJAAAAAA==.Reu:BAAALgAECgUJBwAAAA==.Revlyk:BAACLgAFFH8FAAIgAAMJORWUDgDXAAAgAAMJORWUDgDXAAAuAAQKfycAAiAACAkWI3oEAKgCACAACAkWI3oEAKgCAAEuAAUUBAkNAAMAChsA.Reze:BAAALgAECgkJCQAAAA==.Rezloh:BAAALgAECgkJDAAAAA==.',
Rh='Rhoanna:BAAALgADCgUJBwAAAA==.',
Ri='Rinja:BAAALgADCgYJBgAAAA==.Rintaro:BAABLgAECn8kAAILAAkJrAvSGwA4AQALAAkJrAvSGwA4AQAAAA==.Ritanana:BAAALgAECgIJAgAAAA==.',
Ro='Roccot:BAAALgAECggJDgAAAA==.Roflstomp:BAAALgAECgUJCAABLgAECgkJGQASAKofAA==.Roostrr:BAABLgAECn8XAAIBAAYJ4B2EcwCUAQABAAYJ4B2EcwCUAQAAAA==.Rotfather:BAAALgADCgYJBgAAAA==.Rotjaw:BAAALgAECgYJDAAAAA==.Roughedge:BAAALgADCgIJAgAAAA==.',
Ru='Rurik:BAAALgAECgEJAQAAAA==.',
['Rä']='Rävthor:BAAALgAFFAEJAQAAAA==.Rävthör:BAAALgAECggJEwAAAA==.',
['Rè']='Rèjuva:BAAALgAECgcJDQAAAA==.Rèptílè:BAAALgADCgMJAwABLgAFFAQJCAAfAOYcAA==.',
['Rî']='Rîcflair:BAAALgAECgcJEwAAAA==.',
Sa='Saiyax:BAAALgADCgYJBwAAAA==.Salidfingers:BAAALgADCgYJBgAAAA==.Sanyakulak:BAAALgADCgcJBwABLgAFFAgJGwASABcWAA==.Sanzo:BAAALgAECgEJAgAAAA==.Savathûn:BAAALgAECgQJCAAAAA==.',
Sc='Scalycat:BAACLgAFFH8LAAMWAAMJJw/uIACgAAAWAAMJJw/uIACgAAAXAAMJjgEFVQB2AAAuAAQKfyoABBYACQnYDpwZAMEBABYACQnYDpwZAMEBABcABwksBsVnAKMAACMAAgluB/snAC0AAAAA.Schalla:BAAALgAECgEJAQAAAA==.Scum:BAAALgAECgYJDQAAAA==.Scòrpìòn:BAAALgADCgcJBgABLgAFFAQJCAAfAOYcAA==.',
Se='Seancody:BAAALgADCgIJAgAAAA==.Sekhmett:BAABLgAECn8hAAMOAAgJHARYHwB9AAAkAAYJ1gOODgCQAAAOAAgJ0ANYHwB9AAAAAA==.Selandria:BAAALgADCgQJBAAAAA==.Senate:BAAALgAECgYJCwAAAA==.',
Sh='Shablaam:BAAALgADCgQJBAAAAA==.Shadowbear:BAABLgAECn8cAAIJAAcJ/RztHwDGAQAJAAcJ/RztHwDGAQAAAA==.Shadowoss:BAAALgAECgYJCAAAAA==.Shadygrump:BAAALgAECgYJEQAAAA==.Shamdeaus:BAAALgADCgUJBQABLgAECgkJMAAfAPQYAA==.Shammacass:BAAALgAECgUJBQAAAA==.Shamwick:BAAALgAECgYJCgAAAA==.Shaolincito:BAAALgAECgQJCAAAAA==.Sherrilyn:BAAALgAECgUJBQAAAA==.Shocklocke:BAAALgAECgQJBAAAAA==.',
Si='Sigmachad:BAABLgAECn8UAAIBAAUJBB8qCABtAQABAAUJBB8qCABtAQAAAA==.Silandrus:BAAALgAECgMJBAAAAA==.Silverocean:BAACLgAFFH8GAAIPAAMJgwpSEQCaAAAPAAMJgwpSEQCaAAAuAAQKfzMAAg8ACQkxHOoPAJQCAA8ACQkxHOoPAJQCAAAA.Silvia:BAAALgADCgUJCQAAAA==.Singularity:BAACLgAFFH8WAAINAAMJbiQeBgArAQANAAMJbiQeBgArAQAuAAQKf1IAAg0ACQltJpQAAHUDAA0ACQltJpQAAHUDAAAA.',
Sk='Skaerx:BAABLgAECn8WAAMFAAYJVBeOQwCXAQAFAAYJ9RWOQwCXAQAmAAQJZhSYHQADAQAAAA==.Skittlez:BAABLgAECn8mAAIYAAkJkR/SCQCBAgAYAAkJkR/SCQCBAgABLgAFFAUJDAAcAN8WAA==.',
Sl='Slaykween:BAABLgAECn8fAAILAAgJLQvZIAANAQALAAgJLQvZIAANAQAAAA==.Sloots:BAAALgADCgMJAwAAAA==.Slootybooty:BAABLgAECn8ZAAISAAkJqh81BQC8AgASAAkJqh81BQC8AgAAAA==.',
Sm='Smallz:BAAALgAECgYJEQABLgAECggJJgAOAJ0KAA==.',
Sn='Snipersmash:BAAALgAECgQJCAAAAA==.Snooptrogg:BAABLgAECn8zAAIFAAkJKxZuIADtAQAFAAkJKxZuIADtAQAAAA==.Snoozumi:BAABLgAFFH8GAAIZAAMJKQZISgB9AAAZAAMJKQZISgB9AAAAAA==.Snuups:BAABLgAECn9DAAIbAAkJAhomLwAcAgAbAAkJAhomLwAcAgAAAA==.Snyper:BAAALgADCgQJBAAAAA==.',
So='Soldiah:BAABLgAECn8bAAIFAAgJrQ16OQBgAQAFAAgJrQ16OQBgAQAAAA==.Sommbra:BAAALgAECgYJBwAAAA==.Souljax:BAAALgADCgcJCQAAAA==.',
Sp='Spacelaser:BAAALgAECgQJBQAAAA==.',
Sq='Sqwurl:BAAALgADCgQJBAAAAA==.',
St='Steakhaus:BAAALgADCgkJCwAAAA==.Stiros:BAAALgAECgMJAwAAAA==.Stonedragon:BAECLgAFFH8YAAMfAAYJERwEDgBqAQAfAAUJnSAEDgBqAQAKAAEJ4gnCEgBSAAAuAAQKf0gAAx8ACQlSJcwFADEDAB8ACQlSJcwFADEDAAoACAkPIKwDAI4CAAAA.Stormfist:BAABLgAECn8ZAAIOAAkJ3BAOUADsAQAOAAkJ3BAOUADsAQAAAA==.Stormhaven:BAAALgAECgIJAgABLgAECgkJMgAPABQfAA==.Stormrender:BAAALgAECgYJEAAAAA==.Stormriders:BAAALgAECgUJCgAAAA==.Stormstag:BAAALgADCgYJBgAAAA==.Stouty:BAAALgADCgMJAwABLgAECgcJFAAjAOkaAA==.',
Su='Sukonamí:BAABLgAECn8iAAMFAAkJghckKAAdAgAFAAgJdhUkKAAdAgAmAAQJGhs7KQAoAQAAAA==.Suxtosuck:BAAALgAECgkJBwAAAA==.Suzhou:BAABLgAECn8kAAIeAAkJFwnkFAAFAQAeAAkJFwnkFAAFAQAAAA==.Suzoomies:BAAALgADCgcJBwAAAA==.Suzumii:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetcarolin:BAABLgAECn8WAAICAAkJRg+GXgDXAQACAAkJRg+GXgDXAQAAAA==.Sweetsmercy:BAAALgAECgQJBQAAAA==.Swiftleaf:BAAALgADCgcJBwAAAA==.Swisscheese:BAABLgAECn8zAAIbAAkJniLWBwAZAwAbAAkJniLWBwAZAwAAAA==.',
Sy='Syraxa:BAAALgAECgUJDgABLgAFFAQJEAAHAKQRAA==.Syril:BAAALgADCgcJDAAAAA==.',
Ta='Taedish:BAAALgADCgMJAwAAAA==.Tahret:BAAALgADCgcJDAAAAA==.Taidoetha:BAAALgAECgMJAwAAAA==.Talfurim:BAAALgADCgYJBgAAAA==.Talorien:BAAALgAECgYJDQABLgAFFAMJCgAOABIXAA==.Tannith:BAAALgAECgEJAQABLgADCgEJAQATAAAAAA==.Taquillya:BAAALgAECgQJBQAAAA==.Tarina:BAAALgADCgEJAQAAAA==.Tatersaladin:BAAALgADCgMJAwAAAA==.',
Te='Tenlortin:BAAALgAECgEJAQABLgAECgYJEAATAAAAAA==.Terragosa:BAABLgAECn86AAIOAAkJXBrYLQBiAgAOAAkJXBrYLQBiAgAAAA==.Teryail:BAAALgAECgEJAgAAAA==.Tetchybono:BAAALgADCgYJBgAAAA==.',
Th='Thade:BAABLgAECn8kAAMmAAkJByHUBQCpAgAmAAgJGiDUBQCpAgAFAAgJfB5XHwBWAgAAAA==.Thaeleon:BAABLgAECn8hAAMIAAgJbx98EgBCAgAIAAgJbx98EgBCAgAHAAYJixz+NADUAQABLgAFFAMJEQANAI8ZAA==.Thahawtz:BAAALgADCggJCAAAAA==.Thanattos:BAAALgAECgQJBwAAAA==.Thaneblade:BAAALgAECgQJBgAAAA==.Therizzler:BAAALgAECgcJCQABLgAFFAQJEgAMAMEUAA==.Thickening:BAABLgAECn8ZAAMZAAUJhQ1UagDYAAAZAAUJhQ1UagDYAAAGAAUJ9QfJYQCVAAAAAA==.Thirinis:BAAALgADCgYJBgAAAA==.Thope:BAABLgAECn8nAAIOAAcJTA0kpgAxAQAOAAcJTA0kpgAxAQAAAA==.Thoranubran:BAABLgAECn8fAAIDAAYJcBc4BAAuAQADAAYJcBc4BAAuAQAAAA==.Thrivia:BAAALgAECgYJBgAAAA==.',
Ti='Ticklemychin:BAAALgAECgcJDwAAAA==.Tigani:BAAALgAECgUJDAAAAA==.Tinstey:BAAALgAECgYJAwAAAA==.Titantu:BAAALgAFFAMJAwABLgAFFAMJBgAIAHMFAA==.',
To='Toestiir:BAAALgAECggJEgAAAA==.Tokemaddab:BAAALgADCgUJBQAAAA==.Tontoee:BAAALgAECgEJAQAAAA==.Torlanos:BAAALgADCgIJAgAAAA==.Tosindruid:BAAALgAECgEJAQAAAA==.Toughasnails:BAAALgAECgEJAwAAAA==.',
Tr='Traesdyne:BAAALgAECgEJAQABLgAECgMJAwATAAAAAA==.Trainar:BAAALgAECgQJCQAAAA==.Trazle:BAAALgAECgMJAwAAAA==.Trekkiegeek:BAAALgAECgIJBAAAAA==.Trickybackup:BAAALgADCgMJAwAAAA==.Triggs:BAAALgAECgcJBwAAAA==.Trollbear:BAABLgAECn8WAAIHAAgJhBUJKQAKAgAHAAgJhBUJKQAKAgAAAA==.Trondruid:BAAALgADCgYJDQAAAA==.Trooze:BAABLgAECn87AAIPAAkJLiNhAwBrAwAPAAkJLiNhAwBrAwAAAA==.Trr:BAABLgAECn8pAAIbAAkJmBe2IwCFAgAbAAkJmBe2IwCFAgAAAA==.Truckz:BAAALgADCgEJAQABLgAECgYJCQATAAAAAA==.Truckzage:BAAALgAECgEJAQABLgAECgYJCQATAAAAAA==.Truckzbrr:BAAALgAECgYJCQAAAA==.',
Tu='Tuba:BAAALgAECgYJEAAAAA==.Turim:BAABLgAECn8VAAICAAgJNgcdpwAhAQACAAgJNgcdpwAhAQAAAA==.Tusksrus:BAAALgADCgcJFwAAAA==.',
Ty='Tyrlidd:BAABLgAECn87AAIfAAkJERbuLgAhAgAfAAkJERbuLgAhAgAAAA==.',
Ud='Udon:BAACLgAFFH8IAAMCAAUJmgveeQARAQACAAUJmgveeQARAQAaAAEJkQGeLQAyAAAuAAQKfyIAAwIABwkQGodrAI4BAAIABgm4GodrAI4BABoABQk6FogXABoBAAAA.',
Ug='Ugoar:BAAALgAECggJEwAAAA==.',
Ul='Ultimazero:BAAALgADCgEJAQAAAA==.',
Un='Unavoidable:BAAALgADCgkJEQAAAA==.Unholirolla:BAAALgAECgEJAQAAAA==.Unlikelytale:BAABLgAECn8mAAIQAAkJAyEuCgDXAgAQAAkJAyEuCgDXAgAAAA==.Unmilked:BAAALgAECgYJBwAAAA==.',
Ur='Uricash:BAACLgAFFH8HAAIOAAMJcBh5dgDuAAAOAAMJcBh5dgDuAAAuAAQKf1AAAg4ACQmWIIgRAPECAA4ACQmWIIgRAPECAAAA.Urzual:BAABLgAECn8tAAIgAAkJDyD2BQB+AgAgAAkJDyD2BQB+AgAAAA==.',
Ut='Utiniócast:BAAALgAECgQJBAAAAA==.',
Va='Vandreynna:BAACLgAFFH8NAAIDAAQJCht0DABIAQADAAQJCht0DABIAQAuAAQKf1MAAgMACQnWJVUBAGkDAAMACQnWJVUBAGkDAAAA.',
Ve='Vegèta:BAABLgAECn8gAAICAAkJZAsKgwBdAQACAAkJZAsKgwBdAQABLgAFFAQJCAAfAOYcAA==.Veilaura:BAAALgAECggJDQAAAA==.Velarria:BAABLgAECn8lAAMfAAkJUh83FQCOAgAfAAkJUh83FQCOAgAYAAUJHw3DRACtAAAAAA==.Velikan:BAAALgAECgQJBwABLgAECgcJCAATAAAAAA==.Velsiana:BAABLgAECn8UAAMeAAgJuRHvFQD5AAAbAAgJFg5ofQA+AQAeAAQJ4xXvFQD5AAAAAA==.Velveetah:BAAALgAECgUJCAABLgAECgYJGQAEAJ4PAA==.Verbrennen:BAAALgAECgUJEQABLgAECgkJUgAFABYhAA==.Verdreht:BAAALgADCgEJAQABLgAECgkJUgAFABYhAA==.Verita:BAABLgAECn8zAAIlAAgJXiMcAgCxAgAlAAgJXiMcAgCxAgAAAA==.Verlynne:BAAALgADCgYJBgAAAA==.Verylikely:BAAALgAECgEJAgAAAA==.',
Vi='Viviann:BAABLgAECn8kAAIWAAkJeRFtEADFAQAWAAkJeRFtEADFAQAAAA==.',
Vo='Voiager:BAAALgADCgcJCgAAAA==.',
Vr='Vrakal:BAAALgAECgkJDQAAAA==.',
Wa='Wantabehavoc:BAAALgADCgYJDQAAAA==.Wantadeznutz:BAAALgAECgIJAgAAAA==.Warnick:BAAALgADCgQJBQAAAA==.Warraxe:BAAALgAECgEJAgAAAA==.Wayloren:BAABLgAECn8yAAIBAAkJ9gzTdACEAQABAAkJ9gzTdACEAQAAAA==.Waystalker:BAAALgAECgMJAwAAAA==.Wayverly:BAAALgADCgUJBwABLgAECgkJIwAKAB8LAA==.',
Wi='Wickathy:BAABLgAECn9RAAMoAAkJQSFwAAB6AgAoAAkJQSFwAAB6AgAMAAMJlg/vxACkAAAAAA==.Withering:BAAALgAECgUJBgAAAA==.',
Wo='Wolfcity:BAAALgADCgEJAQAAAA==.Wondertauren:BAAALgADCgYJCQAAAA==.Woodson:BAAALgADCgkJEAABLgAECggJIQAcALARAA==.Worstdps:BAAALgAFFAIJAwAAAA==.',
Wr='Wrkandtank:BAAALgAECgYJBgABLgAECggJFQAbAHcLAA==.',
Wu='Wuldorr:BAACLgAFFH8SAAIBAAQJexfhQgAlAQABAAQJexfhQgAlAQAuAAQKfyQAAgEACAm1H0gkAJYCAAEACAm1H0gkAJYCAAAA.',
Wy='Wynnifred:BAAALgAECggJDQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.',
Xe='Xethreal:BAAALgADCgMJAwAAAA==.',
Xy='Xype:BAAALgAECgkJEQAAAA==.',
Xz='Xzara:BAAALgAECgYJEwABLgAECgYJGwAOADsdAA==.',
Ya='Yastoria:BAAALgAECgcJEAAAAA==.',
Yi='Yinandtonic:BAAALgAECgEJBAAAAA==.',
Ys='Yssaria:BAAALgADCgEJAQAAAA==.',
Yv='Yvvee:BAAALgADCgcJBwAAAA==.',
Za='Zaalim:BAAALgADCgQJBAAAAA==.Zaddy:BAAALgAECgEJAQAAAA==.Zapdôs:BAAALgAECgQJBAAAAA==.Zasko:BAAALgAECgEJAQAAAA==.',
Ze='Zeda:BAABLgAECn8ZAAIFAAYJCRz7BAA/AQAFAAYJCRz7BAA/AQABLgAECgYJGwAOADsdAA==.Zephyris:BAAALgAECgUJDAABLgAFFAgJJQAmAGMhAA==.',
Zh='Zheng:BAAALgAECgYJBgAAAA==.',
Zi='Zillia:BAAALgADCgMJAwAAAA==.',
Zo='Zonora:BAABLgAECn8YAAIPAAkJlQ1hKADJAQAPAAkJlQ1hKADJAQAAAA==.',
Zy='Zyphexd:BAAALgAECgYJDwAAAA==.Zyris:BAAALgADCgcJDQAAAA==.',
['Àz']='Àzñós:BAAALgAECgQJBwAAAA==.',
['Äs']='Ästro:BAAALgAECgQJBgABLgAECgkJLQAGAHcaAA==.',
['Äz']='Äzrael:BAABLgAECn8/AAIEAAkJihxFCQDUAgAEAAkJihxFCQDUAgAAAA==.',
['Åz']='Åznos:BAAALgAECgQJCAAAAA==.',
['Çr']='Çréwüsæðèr:BAABLgAECn8kAAINAAkJ2B5ACwA5AgANAAkJ2B5ACwA5AgAAAA==.',
['Ðe']='Ðecimus:BAAALgAECgQJCQAAAA==.',
['Ðì']='Ðìaßlo:BAACLgAFFH8IAAIfAAQJ5hzbWgDvAAAfAAQJ5hzbWgDvAAAuAAQKfzUABB8ACQljHf4cAHcCAB8ACAljHf4cAHcCABgABwlYFAQRALMBAAoAAQleABqbABUAAAAA.',
['Öb']='Öblïvïöñ:BAAALgAECgEJAwAAAA==.',
['Ød']='Ødin:BAAALgADCgYJBgABLgAECgkJMgAPABQfAA==.',
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
