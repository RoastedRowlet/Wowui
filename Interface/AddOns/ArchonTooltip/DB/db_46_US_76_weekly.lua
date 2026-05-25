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

local lookup = {'Paladin-Retribution','DemonHunter-Havoc','Priest-Holy','Warrior-Fury','Monk-Windwalker','Druid-Restoration','Druid-Balance','Priest-Shadow','Unknown-Unknown','DemonHunter-Devourer','Paladin-Protection','Warrior-Protection','Mage-Frost','Paladin-Holy','Rogue-Subtlety','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Elemental','Evoker-Preservation','Hunter-Survival','Monk-Mistweaver','Priest-Discipline','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Shaman-Restoration','Shaman-Enhancement','Monk-Brewmaster','Druid-Feral','Druid-Guardian','Hunter-Marksmanship','Evoker-Augmentation','Evoker-Devastation','Mage-Arcane','Rogue-Outlaw','Warrior-Arms','Warlock-Affliction','Rogue-Assassination','DemonHunter-Vengeance','DeathKnight-Frost',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Aberaht:BAABLgAECn8mAAIBAAkJYCOqDQAgAwABAAkJYCOqDQAgAwAAAA==.',
Ad='Adamaro:BAAALgADCgYJCQAAAA==.',
Ae='Aenastian:BAAALgAECgUJCQABLgAECgkJQwACAGYlAA==.',
Af='Affrica:BAAALgADCgEJAQABLgAECgYJGQADAJ4PAA==.',
Ag='Agnu:BAAALgADCgcJBwAAAA==.',
Ah='Ahgra:BAABLgAECn8tAAIBAAgJ+QociQA9AQABAAgJ+QociQA9AQAAAA==.',
Ak='Akre:BAAALgAFFAIJBgAAAQ==.Akumä:BAAALgAECgUJCgAAAA==.',
Al='Aleannia:BAAALgAECgUJBQAAAA==.Alekz:BAAALgAECgUJBQAAAA==.Alestria:BAABLgAECn8VAAIBAAcJEBWscQBrAQABAAcJEBWscQBrAQAAAA==.Alibrexia:BAABLgAECn8eAAIEAAgJnAkKNwBFAQAEAAgJnAkKNwBFAQAAAA==.Alida:BAABLgAECn8oAAIEAAgJNQpPNgBIAQAEAAgJNQpPNgBIAQAAAA==.Alithvia:BAAALgAECgYJBgABLgAECgkJJQAFAAskAA==.Allisara:BAAALgADCgkJFgAAAA==.Alysae:BAACLgAFFH8cAAMGAAUJahx1EAClAQAGAAUJahx1EAClAQAHAAEJSQB8QQAcAAAuAAQKfxsAAwYACAkrHeUdAE8CAAYACAkrHeUdAE8CAAcAAgllB1Z+ACkAAAAA.',
Am='Amabear:BAAALgAECgEJAQABLgAECgcJHAAIAP0cAA==.Ambrosse:BAAALgADCggJDwABLgAECgkJLQAFAHcaAA==.',
An='Anabug:BAAALgAECgMJBQAAAA==.Andelwynn:BAAALgAECgIJAgABLgAECgcJEgAJAAAAAA==.Aniellas:BAAALgAECgIJAgAAAA==.Annalese:BAAALgADCgUJCQABLgAECgcJEgAJAAAAAA==.',
Ar='Arabeli:BAAALgAECgEJAQAAAA==.Arbyss:BAAALgADCgcJDAAAAA==.Ardatha:BAAALgADCgcJFwAAAA==.Artio:BAAALgADCgEJAQAAAA==.',
As='Asterön:BAAALgAECgcJEgAAAA==.Astrocakes:BAAALgAECgMJAwABLgAFFAMJCQAKAAUPAA==.',
At='Athenä:BAACLgAFFH8ZAAILAAcJCwyeAgBfAQALAAcJCwyeAgBfAQAuAAQKfzYAAgsACQlwHPkFAI4CAAsACQlwHPkFAI4CAAAA.Atsuma:BAABLgAECn8gAAIMAAgJIAtOHQAhAQAMAAgJIAtOHQAhAQAAAA==.',
Av='Avacynn:BAAALgAECgMJAwAAAA==.Aviz:BAAALgADCgMJAwAAAA==.',
Aw='Awtysmbb:BAAALgAECgIJAwABLgAECgkJJQANAJYXAA==.',
['Aí']='Aísling:BAABLgAECn8jAAIOAAcJkSEvDwB+AgAOAAcJkSEvDwB+AgAAAA==.',
Ba='Baboii:BAAALgADCgIJAgAAAA==.Baconmecrazy:BAAALgAECgEJAQAAAA==.Badinngo:BAAALgADCggJDwAAAA==.Bahiu:BAAALgAECgQJBAAAAA==.Bajafresh:BAAALgAECgQJBQAAAA==.Battleshaman:BAAALgADCgYJBgAAAA==.',
Bd='Bd:BAABLgAECn8dAAIPAAgJJxU5GABGAgAPAAgJJxU5GABGAgAAAA==.',
Be='Beardmedaddy:BAAALgAECgYJBgAAAA==.Bearstavious:BAAALgAECgcJAgAAAA==.Benjinana:BAABLgAECn8ZAAMDAAYJng+8MgAYAQADAAYJng+8MgAYAQAIAAIJJQPOWgBMAAAAAA==.Betterthanu:BAAALgADCgUJBQABLgADCgYJCgAJAAAAAA==.',
Bg='Bg:BAAALgAECgQJBQAAAA==.',
Bi='Bige:BAAALgAECgYJDgAAAA==.Bilo:BAAALgAECgYJCAAAAA==.Bitelyus:BAAALgAECgUJCAAAAA==.',
Bo='Bobius:BAAALgAECgkJDwAAAA==.Bobohizan:BAAALgADCgQJBAAAAA==.Bohde:BAABLgAFFH8OAAMQAAUJ6iKSJgB+AQAQAAQJ6iKSJgB+AQARAAEJAABxOwAAAAAAAA==.Bolognaman:BAAALgAECgUJCAAAAA==.Bombjovi:BAABLgAECn8gAAMLAAkJchU0CwDnAQALAAkJchU0CwDnAQAOAAUJlA9jSQDtAAAAAA==.Bountty:BAAALgAECgQJBAAAAA==.',
Br='Brahmsthoven:BAAALgADCgIJAwAAAA==.Branndhon:BAABLgAECn8gAAIGAAYJzxUaPQB8AQAGAAYJzxUaPQB8AQAAAA==.',
Bt='Btrflyprncss:BAAALgADCgMJAwAAAA==.',
Bu='Bubblemedic:BAAALgADCgIJAgAAAA==.Budde:BAAALgAECgUJBQAAAA==.Buffaloseven:BAAALgADCgcJBwABLgAFFAcJDwANAAQLAA==.',
Ca='Cairdamane:BAABLgAECn8hAAISAAkJ5BG9JgCIAQASAAkJ5BG9JgCIAQAAAA==.Calidrina:BAABLgAECn8hAAIKAAkJMhzbOwC3AQAKAAkJMhzbOwC3AQAAAA==.Carm:BAAALgAECgYJBgAAAA==.Caroliná:BAAALgAECgMJBgAAAA==.Catcast:BAAALgAECgUJCAABLgAECgkJKgATANgOAA==.Catclaw:BAAALgAECgEJAQABLgAECgkJKgATANgOAA==.',
Ce='Celiri:BAABLgAECn8nAAIFAAkJrxC4GQC4AQAFAAkJrxC4GQC4AQAAAA==.Celldrassil:BAABLgAECn8sAAIGAAgJ1ga1XgD5AAAGAAgJ1ga1XgD5AAAAAA==.Cereel:BAAALgAECgMJAwABLgAFFAMJCQAKAAUPAA==.',
Ch='Chadaracka:BAAALgAECgYJBwAAAA==.Chandelure:BAAALgAECgUJCwAAAA==.Chardaney:BAAALgAECgcJEgAAAA==.Cherryontop:BAABLgAECn8jAAIGAAgJMhIzMQC4AQAGAAgJMhIzMQC4AQAAAA==.Chozenone:BAAALgAECgQJCQAAAA==.Chozi:BAAALgAECgYJBgAAAA==.Chromosomie:BAAALgADCgYJBgABLgAECgkJMAANAOcbAA==.',
Ci='Cii:BAAALgAFFAEJAQAAAA==.',
Co='Coconutwater:BAAALgAECggJCwAAAA==.Colandros:BAABLgAECn8vAAIUAAcJDwsRJwBEAQAUAAcJDwsRJwBEAQAAAA==.Colara:BAAALgAECgcJEwAAAA==.Combobreaker:BAACLgAFFH8FAAIVAAMJBhRjJQDJAAAVAAMJBhRjJQDJAAAuAAQKfzAAAhUACQkyHrcGAAgDABUACQkyHrcGAAgDAAAA.Comoo:BAAALgADCgIJBQAAAA==.Correct:BAAALgAECgEJAQAAAA==.Cowbôy:BAAALgADCgkJEQAAAA==.',
Cr='Crassberry:BAACLgAFFH8XAAIQAAcJEx8pCQAiAgAQAAcJEx8pCQAiAgAuAAQKfygAAhAACQk2JBQFAIMDABAACQk2JBQFAIMDAAAA.Crazyraptor:BAAALgAECgIJAgABLgAECgYJEwAJAAAAAA==.Crazèd:BAAALgADCgQJBAAAAA==.',
Cy='Cyndal:BAAALgAECgQJCQABLgAECgUJCgAJAAAAAA==.Cyndle:BAAALgAECgUJBgABLgAECgUJCgAJAAAAAA==.Cyntu:BAAALgAECgUJCgAAAA==.',
['Cü']='Cüpid:BAAALgAECgYJBgAAAA==.',
Da='Dada:BAAALgAECgEJAQAAAA==.Dammithells:BAAALgADCgQJBAAAAA==.Dandamar:BAAALgAECgYJBgAAAA==.Dankfists:BAAALgAECgUJBQABLgAFFAIJAgAJAAAAAA==.Dankhaze:BAAALgAFFAIJAgAAAA==.Dankzor:BAAALgAECgcJBQABLgAFFAIJAgAJAAAAAA==.Dark:BAAALgADCgEJAQAAAA==.Darthrevan:BAAALgAECgQJBwAAAA==.Dasharnkal:BAAALgADCgUJCAAAAA==.Dasvult:BAAALgAECgMJBAAAAA==.Dazex:BAABLgAECn8bAAMDAAYJdwJgRQCpAAADAAYJKgJgRQCpAAAWAAUJRwJVSgCXAAAAAA==.',
De='Deadpump:BAABLgAECn8fAAMXAAcJfRLzZABeAQAXAAcJfRLzZABeAQAYAAQJUQ4aOQDQAAAAAA==.Demonsnotkey:BAAALgAECgYJCwAAAA==.Demoxus:BAAALgAECgQJBAAAAA==.Denker:BAAALgADCggJCAAAAA==.Denkzilla:BAAALgADCgIJAgAAAA==.Denzvic:BAAALgAECgEJAQAAAA==.Destro:BAAALgAECgEJAQAAAA==.Deusclaw:BAAALgAECgYJCgAAAA==.Devilah:BAAALgAECgEJAQAAAA==.',
Dh='Dharm:BAABLgAECn8oAAMZAAcJvRrlSACaAQAZAAcJvRrlSACaAQAUAAIJxQx0RQBzAAAAAA==.',
Di='Dialsl:BAAALgADCgUJBgAAAA==.Digbickpanda:BAAALgADCgYJBgABLgAFFAMJCQAKAAUPAA==.Disowneege:BAABLgAECn8ZAAIBAAgJqx/xHgBuAgABAAgJqx/xHgBuAgABLgAFFAcJFgAEAGEjAA==.Diyos:BAAALgADCgYJCgAAAA==.',
Do='Dotndash:BAAALgADCgIJAgAAAA==.Doubledge:BAAALgAECgEJAQAAAA==.Doublejump:BAACLgAFFH8LAAIKAAQJUwy1OwALAQAKAAQJUwy1OwALAQAuAAQKfykAAgoACAk4HiMfADwCAAoACAk4HiMfADwCAAAA.',
Dr='Dragdh:BAAALgAECgcJEwABLgAECggJJAAaAHQVAA==.Dragnas:BAABLgAECn8kAAMaAAgJdBVUMgC6AQAaAAcJrBRUMgC6AQAbAAcJkB2QDACyAQAAAA==.Dragonisa:BAAALgAFFAEJAQAAAA==.Dragun:BAAALgADCgIJAgAAAA==.Draiocht:BAAALgADCgMJAwABLgAECgkJKAADAGkaAA==.Drakeskid:BAAALgAECgQJBwABLgAFFAQJBgAcALgKAA==.Drakthall:BAAALgAECgIJAwAAAA==.Dralionethny:BAAALgAECgIJAgAAAA==.Dramakiller:BAAALgAECgUJCQAAAA==.Drchi:BAAALgAECgEJAQABLgAECgYJGQAdAIcVAA==.Drcornbread:BAABLgAECn8ZAAMdAAYJhxX8FAA6AQAdAAYJhxX8FAA6AQAeAAEJ0APiYwATAAAAAA==.Drcornellia:BAAALgAECgUJCAABLgAECgYJGQAdAIcVAA==.Drdarkskin:BAAALgAECgcJDQAAAA==.Drdreggs:BAABLgAECn8nAAMYAAkJmBbaDQAzAQAXAAgJuBSYTwDZAQAYAAYJmxfaDQAzAQAAAA==.Dreggs:BAAALgADCgcJEwAAAA==.Drizztin:BAAALgADCgEJAQAAAA==.Drprominus:BAABLgAECn8gAAIOAAgJACIeBwD3AgAOAAgJACIeBwD3AgAAAA==.Drthargyll:BAAALgADCgYJDgABLgAECggJIAAOAAAiAA==.',
Dy='Dykdanglr:BAAALgADCgYJBgABLgAECgQJCAAJAAAAAA==.',
['Dí']='Dígífóx:BAAALgAECgYJDgAAAA==.',
Ea='Earthereal:BAABLgAECn8vAAIVAAgJpxdUFgAqAgAVAAgJpxdUFgAqAgAAAA==.',
El='Elastar:BAABLgAECn8mAAIMAAkJ6RYEDgDfAQAMAAkJ6RYEDgDfAQAAAA==.Ellimist:BAECLgAFFH8WAAIaAAYJqheSBwD8AQAaAAYJqheSBwD8AQAuAAQKfyIAAxoACQmJGHQXAFoCABoACQmJGHQXAFoCABIABQk0FxdQAAcBAAAA.Elsan:BAAALgAECgEJAQAAAA==.Elycee:BAACLgAFFH8FAAIZAAMJyyV8JAA8AQAZAAMJyyV8JAA8AQAuAAQKfxgAAxkACQmXIugXAG4CABkACAkzIegXAG4CAB8ACAlSGJYgACECAAAA.Elysria:BAAALgADCgYJBgAAAA==.Elí:BAAALgAECgQJBAAAAA==.',
En='Encrid:BAAALgAECgcJDwABLgAFFAMJBQAgAPwWAA==.Enhasa:BAABLgAECn8ZAAIQAAkJ0hQcNAALAgAQAAkJ0hQcNAALAgABLgAECgYJGgABAOggAA==.Enoeht:BAABLgAECn8wAAICAAgJGQuUHwBBAQACAAgJGQuUHwBBAQAAAA==.Enveliria:BAAALgAECgEJAQABLgAECgkJQwACAGYlAA==.',
Er='Eraser:BAAALgAECgYJBgAAAA==.Erazar:BAABLgAECn8uAAIhAAgJ1xJ7BwCjAQAhAAgJ1xJ7BwCjAQAAAA==.Eriah:BAAALgADCgkJCQAAAA==.Erickk:BAABLgAECn8wAAMNAAkJ5xsNNgAjAgANAAkJnBoNNgAjAgAiAAQJVx1SCwAkAQAAAA==.',
Es='Essense:BAABLgAECn8mAAIDAAkJmyRIAwApAwADAAkJmyRIAwApAwAAAA==.',
Ex='Exodari:BAABLgAECn87AAIbAAkJ7hgFCAAWAgAbAAkJ7hgFCAAWAgAAAA==.',
Fa='Fabbioh:BAAALgADCgEJAQAAAA==.Fadeddh:BAACLgAFFH8JAAIKAAMJBQ+2TADTAAAKAAMJBQ+2TADTAAAuAAQKfzAAAgoACQn/G6kbAFECAAoACQn/G6kbAFECAAAA.Faizarah:BAAALgAECgYJBgAAAA==.Faydien:BAAALgAECgEJAQAAAA==.',
Fe='Fearnoevil:BAAALgADCgMJAwAAAA==.Fel:BAABLgAECn8RAAIKAAgJjRpbUAByAQAKAAgJjRpbUAByAQAAAA==.Fellkarras:BAAALgAECgYJCwABLgAFFAMJBQAVAAYUAA==.Fent:BAAALgAECgYJEwAAAA==.',
Fi='Fiddich:BAAALgAECgYJBgAAAA==.Fillthy:BAACLgAFFH8TAAIVAAcJzxPwCQDxAQAVAAcJzxPwCQDxAQAuAAQKfy4AAxUACQlYIkYDAEcDABUACQlYIkYDAEcDAAUAAwkhCWlgAGcAAAAA.Finnigann:BAAALgAECgYJCwAAAA==.Firenmylazer:BAAALgADCgMJAwAAAA==.Fistav:BAAALgADCgcJDgAAAA==.Fizban:BAABLgAECn8YAAINAAgJIwjPiwBEAQANAAgJIwjPiwBEAQAAAA==.',
Fl='Flappybird:BAAALgAECgMJAwABLgAFFAMJCQAKAAUPAA==.Flasan:BAAALgADCgEJAQAAAA==.Flazz:BAAALgADCgIJAwAAAA==.Flazzan:BAAALgADCgEJAQAAAA==.',
Fo='Fogbringer:BAAALgAECgIJAwAAAA==.Four:BAAALgADCgQJBAAAAA==.',
Fr='Frejä:BAAALgAECgQJBQABLgAECgQJDAAJAAAAAA==.Freyah:BAAALgAECgUJDgAAAA==.Frostmay:BAAALgAECgIJAgAAAA==.',
Fu='Furrybawlz:BAAALgAECgUJCgABLgAECgYJDQAJAAAAAA==.',
Ga='Gabran:BAAALgAECgUJBQAAAA==.Gadogear:BAABLgAECn8jAAINAAgJNBjaSADlAQANAAgJNBjaSADlAQAAAA==.Garlick:BAAALgADCggJDwABLgAECggJLgAhANcSAA==.Garlik:BAAALgADCgMJBAAAAA==.',
Ge='Gertra:BAAALgAECgEJAgAAAA==.',
Gf='Gfr:BAAALgAECgcJDgAAAA==.',
Gi='Girthrichard:BAAALgAECgYJDAAAAA==.',
Gl='Glassdragon:BAABLgAECn8mAAIBAAkJUQyBZwCAAQABAAkJUQyBZwCAAQAAAA==.Gllor:BAAALgADCgIJAgAAAA==.',
Go='Goatcheeze:BAABLgAECn8cAAIiAAkJLhUVAwDdAQAiAAkJLhUVAwDdAQAAAA==.Goatylocks:BAABLgAECn8lAAMYAAkJ7RWFCgBsAQAXAAcJbQ7SVQCEAQAYAAYJLByFCgBsAQAAAA==.Goldenchild:BAAALgAFFAIJAgABLgAFFAMJCQAKAAUPAA==.',
Gr='Greatluckydo:BAAALgADCgEJAQAAAA==.Grozlek:BAAALgADCgYJBgAAAA==.',
Gu='Gulen:BAABLgAECn8WAAIaAAYJpSEKHAA+AgAaAAYJpSEKHAA+AgAAAA==.',
Gw='Gwendyla:BAAALgADCgYJCgAAAA==.',
['Gí']='Gíga:BAABLgAECn8XAAIZAAgJ7RPdKQAPAgAZAAgJ7RPdKQAPAgAAAA==.',
Ha='Hafnium:BAAALgADCgkJEAAAAA==.Hamish:BAAALgAECgUJCAAAAA==.Hanhaine:BAABLgAECn8eAAIHAAgJkg/KJQBvAQAHAAgJkg/KJQBvAQAAAA==.Hazirat:BAAALgAECgYJCAAAAA==.',
He='Hedlie:BAAALgAECggJCwAAAA==.Hellenkeller:BAECLgAFFH8HAAIVAAYJhw8KEgCBAQAVAAYJhw8KEgCBAQAuAAQKfx8AAhUABwkzITQTADMCABUABwkzITQTADMCAAEuAAUUBgkSACMACRwA.Heloisa:BAAALgAECgYJDwAAAA==.Helrazr:BAAALgAFFAEJAgAAAA==.Henshin:BAACLgAFFH8IAAIGAAMJiA4WMwDEAAAGAAMJiA4WMwDEAAAuAAQKf0IAAwYACQk2Hf0NAMoCAAYACQk2Hf0NAMoCAAcAAgk4DpN0ADUAAAAA.',
Hi='Hitt:BAAALgAECgEJAgAAAA==.',
Ho='Holyhim:BAAALgADCgIJAgAAAA==.Holyshawk:BAAALgAECgEJAQAAAA==.Hottyshmotty:BAAALgAECgEJAQAAAA==.Hourglass:BAABLgAECn8vAAMZAAkJjBU+LwD2AQAZAAkJjBU+LwD2AQAfAAQJ1g3oXwDBAAAAAA==.',
Hr='Hroc:BAAALgAECgEJAgAAAA==.',
Hu='Huntthejuan:BAAALgADCgUJBQAAAA==.',
Ic='Icyowneege:BAAALgADCgUJBQABLgAFFAcJFgAEAGEjAA==.Icywolfy:BAAALgAECgYJCAAAAA==.',
Ig='Igreetyou:BAABLgAECn8bAAIXAAcJbxgORQC1AQAXAAcJbxgORQC1AQAAAA==.',
Il='Illie:BAABLgAECn8mAAIbAAkJShyHBQCtAgAbAAkJShyHBQCtAgAAAA==.Illune:BAABLgAECn8lAAMNAAkJlhcuQwD2AQANAAkJlhcuQwD2AQAiAAYJUg4ZCQBbAQAAAA==.',
Im='Imanbearpig:BAAALgADCgIJAgAAAA==.Imleapingit:BAABLgAECn8sAAIEAAkJPiE5BQDzAgAEAAkJPiE5BQDzAgAAAA==.',
In='Intoodragons:BAACLgAFFH8IAAIgAAMJ/AV9OACwAAAgAAMJ/AV9OACwAAAuAAQKfzQAAyAACQl7FJIXAPoBACAACQl7FJIXAPoBACEABglaBfokAP4AAAAA.Inyah:BAAALgAECgIJAgAAAA==.',
Io='Ionzz:BAABLgAECn8ZAAICAAkJrx+iCADYAgACAAkJrx+iCADYAgAAAA==.',
Ir='Iroann:BAAALgAECgYJDwAAAA==.',
Is='Isawarriorr:BAABLgAECn8sAAIMAAkJgiOJAwAfAwAMAAkJgiOJAwAfAwAAAA==.Ishaq:BAAALgAECgQJBQABLgAECggJGgAcACsFAA==.Ishdo:BAAALgADCgMJAwABLgAECggJGgAcACsFAA==.Ishdu:BAAALgADCgMJAwABLgAECggJGgAcACsFAA==.Ishkhan:BAABLgAECn8aAAMcAAgJKwWHOwDuAAAcAAgJTwSHOwDuAAAFAAYJUQXoTQCiAAAAAA==.Ishmael:BAAALgAFFAMJBAAAAA==.Ishwar:BAAALgADCgYJBgAAAA==.',
Ja='Jakytreehorn:BAACLgAFFH8HAAMaAAUJKQXBQwCjAAAaAAQJZQTBQwCjAAASAAIJowJNRQA2AAAuAAQKfyQAAxoACQkqEgwoAPABABoACQkqEgwoAPABABIABwkMD0s8ABQBAAAA.Jasher:BAAALgAECgYJBgAAAA==.Jaydm:BAABLgAECn8VAAIkAAYJgBSNIAAvAQAkAAYJgBSNIAAvAQABLgAFFAcJDwANAAQLAA==.',
Je='Jenevelle:BAAALgAECgUJBgAAAA==.Jerisil:BAAALgADCgQJBAAAAA==.Jet:BAABLgAECn8aAAIBAAYJ6CAySwABAgABAAYJ6CAySwABAgAAAA==.',
Ji='Jibbajabba:BAAALgADCgcJBwAAAA==.Jimbo:BAAALgAFFAIJBAABLgAFFAcJFwAQABMfAA==.',
Ju='Judgecalypso:BAAALgAECgQJBQAAAA==.Julthaenia:BAABLgAECn8gAAQlAAcJ/h6YBAAcAgAlAAcJ/h6YBAAcAgAXAAUJcQuC1gCCAAAYAAQJGAroKgBVAAABLgAECgkJQwACAGYlAA==.Justeatjuan:BAAALgAECgMJAwAAAA==.',
Ka='Kagebushin:BAAALgAECgMJBAAAAA==.Kalazin:BAAALgAECgUJBQAAAA==.Kalimah:BAAALgADCgMJAwAAAA==.Kalofelement:BAAALgADCgUJBQAAAA==.Karnrae:BAABLgAECn8iAAIBAAgJbxI/WgCfAQABAAgJbxI/WgCfAQAAAA==.Karynos:BAABLgAECn8kAAMXAAkJeAoMUQCRAQAXAAkJSgkMUQCRAQAYAAcJyQkOIwA/AQAAAA==.Katnelly:BAAALgAECgMJAwAAAA==.Kazmacoryy:BAAALgAECgYJEAAAAA==.',
Ke='Keedis:BAAALgADCggJCwAAAA==.Keristrasza:BAAALgAFFAEJAQABLgAFFAYJIQAaAE4eAA==.',
Ki='Kileely:BAAALgAECgMJAwAAAA==.Kirintore:BAAALgAECgUJCQAAAA==.',
Kk='Kkaiser:BAAALgADCgUJBQAAAA==.',
Kl='Klaudeus:BAAALgAECgEJAQAAAA==.',
Ko='Kodian:BAAALgADCgEJAQAAAA==.Kolypso:BAAALgAECgYJEwAAAA==.Konceal:BAAALgAECgEJAQAAAA==.Konspiracy:BAABLgAECn8oAAIYAAgJUxktBQDyAQAYAAgJUxktBQDyAQAAAA==.Konvict:BAAALgAECgIJAwABLgAECgYJDQAJAAAAAA==.',
Kr='Krataar:BAABLgAECn8hAAIEAAkJEyF5CAC6AgAEAAkJEyF5CAC6AgAAAA==.Kravvan:BAAALgAECgMJAwABLgAECggJGAANACMIAA==.Krousvor:BAAALgAECgQJBwAAAA==.Kryph:BAABLgAECn8aAAIQAAkJGgh1ZwBzAQAQAAkJGgh1ZwBzAQAAAA==.',
Ku='Kugruk:BAAALgAECgcJDAAAAA==.Kurjo:BAAALgAECgMJBAAAAA==.',
Ky='Kyleschlong:BAAALgAECgMJCAAAAA==.Kyndreith:BAAALgAECgMJAwAAAA==.',
['Kä']='Kämpfer:BAABLgAECn9LAAIEAAkJFiETBQD2AgAEAAkJFiETBQD2AgAAAA==.',
La='Lafiel:BAABLgAECn8dAAMDAAkJGgtKPABJAQADAAkJGgtKPABJAQAIAAIJ1QhJXwBcAAAAAA==.Landiedoo:BAAALgAECgkJCgAAAA==.Laverna:BAAALgADCgMJBAAAAA==.',
Le='Lefay:BAAALgADCgcJFwAAAA==.Leprawnjames:BAAALgAECgIJAgABLgAECgYJDwAJAAAAAA==.Letsgetwet:BAAALgADCgYJBgAAAA==.',
Li='Liefic:BAAALgAECgYJCAAAAA==.Limon:BAAALgADCgIJAgAAAA==.',
Lo='Loadin:BAAALgAECgIJAgAAAA==.Lockaflockå:BAAALgADCgMJAwAAAA==.Locke:BAAALgAECgMJAgABLgAECgYJGgABAOggAA==.Lonoh:BAAALgAECgcJEgAAAA==.',
Lu='Luan:BAAALgADCgEJAQAAAA==.Lucariø:BAAALgADCgcJDAAAAA==.Lucidbonsai:BAAALgADCggJCAAAAA==.Luckykilla:BAABLgAECn8jAAImAAkJHhnuAwA8AgAmAAkJHhnuAwA8AgAAAA==.Lucÿ:BAACLgAFFH8LAAIaAAQJewk3NADcAAAaAAQJewk3NADcAAAuAAQKfyIAAxoABwmsGPQoAOwBABoABwmsGPQoAOwBABIAAwkVDAZlAIMAAAAA.Lula:BAAALgADCgMJAwAAAA==.Lurith:BAABLgAECn87AAMRAAgJHhN8FwB5AQARAAgJaxJ8FwB5AQAQAAYJrgjYuAARAQAAAA==.Lutreaux:BAAALgADCgEJAQAAAA==.Luxtyrannica:BAABLgAECn8ZAAIBAAcJjhhdWACkAQABAAcJjhhdWACkAQAAAA==.',
Ly='Lydrain:BAAALgAECgEJAQAAAA==.Lysandria:BAABLgAECn8pAAINAAkJmw3FVgC7AQANAAkJmw3FVgC7AQAAAA==.',
Ma='Macrosblack:BAAALgADCgMJAwAAAA==.Madamerouge:BAAALgAECgIJAgABLgAECgYJGQAdAIcVAA==.Magearino:BAABLgAECn8lAAINAAgJnRbvTgDSAQANAAgJnRbvTgDSAQAAAA==.Marcopally:BAAALgAECgQJBAAAAA==.Marluxia:BAACLgAFFH8dAAIeAAUJkgj3DwC+AAAeAAUJkgj3DwC+AAAuAAQKfxoAAh4ACAkhE/YMALkBAB4ACAkhE/YMALkBAAAA.Materfamilia:BAAALgAECgQJBAAAAA==.Mattbull:BAACLgAFFH8FAAMgAAMJ/BbgLQDdAAAgAAMJ/BbgLQDdAAAhAAEJ1xNICQBXAAAuAAQKfx4AAyEABgmqJFcNAAQCACEABglCIlcNAAQCACAABgl5IigbANwBAAAA.',
Me='Medjrab:BAACLgAFFH8RAAIQAAQJxhhzQgBAAQAQAAQJxhhzQgBAAQAuAAQKfzIAAhAACQlLIvsMAOUCABAACQlLIvsMAOUCAAAA.Meristem:BAABLgAECn8oAAIHAAgJkA62JQBvAQAHAAgJkA62JQBvAQAAAA==.Merko:BAAALgADCgkJDwAAAA==.',
Mi='Miaan:BAAALgADCgYJBgAAAA==.Miette:BAAALgADCgMJAwAAAA==.Mihonk:BAAALgADCgQJBAAAAA==.Mintycrx:BAABLgAECn8fAAINAAkJHhHnQwD0AQANAAkJHhHnQwD0AQAAAA==.Missfist:BAAALgADCgIJAgAAAA==.Mistlocke:BAAALgADCgMJAwAAAA==.',
Mn='Mngwa:BAAALgAECgIJBQAAAA==.',
Mo='Moegu:BAABLgAECn8aAAInAAgJXxZOCADHAQAnAAgJXxZOCADHAQAAAA==.Mog:BAACLgAFFH8GAAMlAAMJERrgFABSAAAXAAIJlhllcQCtAAAlAAEJBxvgFABSAAAuAAQKfzYABBcACQljIwISAKUCABcABwmSIwISAKUCACUAAwmVI5ASAAUBABgAAwkcEcI2ANsAAAAA.Moncatsera:BAAALgAECgQJBAAAAA==.Mondgrille:BAAALgAECgQJBAABLgAECgYJDQAJAAAAAA==.Monora:BAABLgAECn8WAAIVAAcJ6QgNTgDXAAAVAAcJ6QgNTgDXAAAAAA==.Montress:BAAALgAECggJEwAAAA==.Moomoohealz:BAACLgAFFH8IAAIHAAMJCRc/IQDsAAAHAAMJCRc/IQDsAAAuAAQKfzsAAgcACQkoIfEFANsCAAcACQkoIfEFANsCAAAA.Moonbounds:BAACLgAFFH8hAAIaAAYJTh6JBgAMAgAaAAYJTh6JBgAMAgAuAAQKfzgAAxoACQndJFEDAEQDABoACQndJFEDAEQDABIAAQnZH4Z5AF0AAAAA.Moondoggey:BAAALgAECgMJAwAAAA==.Morgana:BAAALgADCgIJAgAAAA==.Mousechief:BAABLgAECn8kAAISAAcJmQQpUQDDAAASAAcJmQQpUQDDAAAAAA==.Moxnix:BAABLgAECn8UAAMVAAcJXgzIPwAVAQAVAAcJXgzIPwAVAQAcAAMJ4QWMXgBzAAABLgAECggJFwAZAHgNAA==.Moxxzi:BAAALgAFFAEJAgAAAA==.',
Mu='Muhfookinbak:BAABLgAECn8kAAMaAAkJFyAXDADSAgAaAAkJFyAXDADSAgASAAQJhxgUTgDNAAAAAA==.',
My='Myor:BAAALgADCgMJAwAAAA==.',
['Mà']='Màttbull:BAABLgAFFH8GAAIKAAIJrg5AYwCOAAAKAAIJrg5AYwCOAAABLgAFFAMJBQAgAPwWAA==.',
Na='Naesta:BAAALgAECgIJAgABLgAECggJIQAGAP4fAA==.Naksù:BAEBLgAECn8UAAIKAAYJqgOlsACWAAAKAAYJqgOlsACWAAAAAA==.Namal:BAAALgAECgQJBQAAAA==.Narenae:BAABLgAECn8lAAIFAAkJCyRABABIAwAFAAkJCyRABABIAwAAAA==.Nastalan:BAAALgADCgYJCgAAAA==.',
Ne='Nefari:BAAALgADCgMJAwAAAA==.Neifeb:BAABLgAECn8lAAIZAAkJCRZRLgD6AQAZAAkJCRZRLgD6AQAAAA==.Nephthys:BAAALgADCgQJBAAAAA==.',
Ni='Niallivdam:BAABLgAECn8nAAMhAAcJWRdYBwCnAQAhAAcJWRdYBwCnAQATAAYJoheVEQCLAQAAAA==.Nights:BAAALgADCgkJCQABLgAFFAUJDgABANcRAA==.Nightsoul:BAAALgADCgEJAQAAAA==.Ninh:BAACLgAFFH8IAAIVAAMJNALTMwBvAAAVAAMJNALTMwBvAAAuAAQKf0MAAhUACQlvD1soAJoBABUACQlvD1soAJoBAAAA.',
No='Nomissius:BAAALgADCgcJDQAAAA==.Nooblè:BAAALgADCgMJAwAAAA==.Notsodemon:BAABLgAECn8eAAMKAAgJfxRjRgCRAQAKAAgJfxRjRgCRAQACAAIJnwrPYwBUAAAAAA==.Notsoevoker:BAAALgAECgMJAwABLgAECggJHgAKAH8UAA==.Notsomonk:BAAALgADCgMJAwABLgAECggJHgAKAH8UAA==.',
Ny='Nykara:BAAALgAECgUJBQAAAA==.',
['Nå']='Nåld:BAAALgAECgEJAQAAAA==.',
Oa='Oakendorf:BAAALgAECgEJAQAAAA==.',
Ob='Obvinotagirl:BAAALgAECggJDwAAAA==.',
Od='Oddpocalypse:BAAALgAECgEJAQAAAA==.',
Og='Ogsikko:BAAALgAECgYJCwABLgAECggJGAAXAJAeAA==.Ogsikkotv:BAABLgAECn8YAAINAAYJ/BmQhwDCAQANAAYJ/BmQhwDCAQABLgAECggJGAAXAJAeAA==.',
Ok='Okathra:BAAALgAECgQJBAABLgAECgkJMgAbAEwjAA==.',
On='Onebadmutha:BAABLgAECn8ZAAIXAAkJ+AxwQwC5AQAXAAkJ+AxwQwC5AQAAAA==.Ontop:BAABLgAECn8oAAIZAAkJ7xsaHABeAgAZAAkJ7xsaHABeAgAAAA==.',
Or='Orb:BAABLgAECn8kAAQBAAkJ5BY9SQDLAQABAAgJlBg9SQDLAQAOAAgJ3gxWLQCCAQALAAUJQQ/EHgATAQAAAA==.Orcfreeza:BAAALgAECgQJDAAAAA==.Ortinks:BAABLgAECn8YAAINAAgJvA+dYgCdAQANAAgJvA+dYgCdAQAAAA==.',
Ow='Owneege:BAACLgAFFH8WAAIEAAcJYSNiAQA1AgAEAAcJYSNiAQA1AgAuAAQKfzMAAgQACQkEIx4CAKADAAQACQkEIx4CAKADAAAA.',
Pa='Painsaw:BAAALgADCgYJBgAAAA==.Pallinar:BAABLgAECn8wAAIBAAgJEhZvSgDIAQABAAgJEhZvSgDIAQAAAA==.Pasquale:BAABLgAECn8hAAIcAAcJRSFREQAOAgAcAAcJRSFREQAOAgAAAA==.',
Pe='Pebbles:BAAALgAECggJDQAAAA==.Pedroia:BAAALgAECgcJCAAAAA==.Pesty:BAAALgAECgMJCQAAAA==.',
Ph='Phe:BAABLgAECn8XAAMHAAcJhw7lMQAkAQAHAAcJhw7lMQAkAQAGAAYJpQvzcAADAQAAAA==.Pheraree:BAAALgAECgEJAQAAAA==.Phooboo:BAAALgAECgkJBQAAAA==.',
Pi='Pidion:BAAALgADCgYJDAAAAA==.Pilgrimm:BAECLgAFFH8SAAMjAAYJCRxnAwBKAQAjAAUJTxlnAwBKAQAPAAMJpyAgCwA4AQAuAAQKfyQAAw8ACQl7IrIDAGADAA8ACQl0IrIDAGADACMABQkIH2cJAGcBAAAA.',
Pl='Plaguerott:BAABLgAECn83AAIoAAkJeA/zCQCdAQAoAAkJeA/zCQCdAQAAAA==.Plusultra:BAAALgADCgkJEQAAAA==.Pluto:BAAALgAECgcJCgAAAA==.',
Po='Poby:BAAALgADCgcJBwAAAA==.Pocketsand:BAAALgAECgEJAQABLgAECgUJFQAZANkeAA==.Polydh:BAABLgAECn8sAAInAAkJjSSrAAA8AwAnAAkJjSSrAAA8AwAAAA==.Poobah:BAABLgAECn8jAAMSAAgJvAZ4SADhAAASAAcJfAZ4SADhAAAaAAcJCgMPcwDIAAAAAA==.Popscotch:BAABLgAECn8jAAMlAAkJEg3OCQCkAQAlAAcJRg7OCQCkAQAXAAkJwAvuSwCgAQAAAA==.Pouffant:BAABLgAECn8iAAIBAAkJyBMgQgDhAQABAAkJyBMgQgDhAQAAAA==.',
Pr='Pronoz:BAABLgAECn8iAAIBAAcJfRKedQBjAQABAAcJfRKedQBjAQAAAA==.',
Pu='Punchy:BAAALgADCgEJAQAAAA==.',
Pw='Pwnageddon:BAABLgAECn8nAAMLAAgJAB5MBwA9AgALAAcJlSFMBwA9AgABAAUJhxUW4gDJAAAAAA==.Pwnjitsu:BAABLgAECn86AAIFAAkJPCVmAQBZAwAFAAkJPCVmAQBZAwAAAA==.',
Py='Pyrothermia:BAACLgAFFH8PAAINAAcJBAumGgC7AQANAAcJBAumGgC7AQAuAAQKfyYAAg0ACQn/HIoqAMgCAA0ACQn/HIoqAMgCAAAA.',
['Pô']='Pôlgara:BAAALgADCgYJBgABLgAECgcJIwAOAJEhAA==.',
Qt='Qtkillz:BAAALgADCgQJBAAAAA==.',
Ra='Rancayden:BAAALgAECgMJBAAAAA==.Rawhoof:BAACLgAFFH8IAAIEAAMJEhydHwAJAQAEAAMJEhydHwAJAQAuAAQKf0MAAgQACQkDJV0CADgDAAQACQkDJV0CADgDAAAA.Razak:BAABLgAECn8yAAIbAAkJTCM3AQAWAwAbAAkJTCM3AQAWAwAAAA==.',
Re='Renisa:BAABLgAECn8iAAIKAAgJqRlZRACYAQAKAAgJqRlZRACYAQAAAA==.Retman:BAABLgAECn8UAAIBAAcJtg/dwwDfAAABAAcJtg/dwwDfAAAAAA==.Reu:BAAALgAECgUJBwAAAA==.Revlyk:BAABLgAECn8gAAIbAAcJFiKECAAIAgAbAAcJFiKECAAIAgABLgAECgkJQwACAGYlAA==.Rezloh:BAAALgAECgEJAQAAAA==.',
Rh='Rhoanna:BAAALgADCgQJBAAAAA==.',
Ri='Rintaro:BAABLgAECn8eAAILAAkJnQnYHQD3AAALAAkJnQnYHQD3AAAAAA==.Ritanana:BAAALgAECgIJAgAAAA==.',
Ro='Roccot:BAAALgAECggJDgAAAA==.Roflstomp:BAAALgAECgQJBwABLgAECgYJDwAJAAAAAA==.Roostrr:BAABLgAECn8XAAIBAAYJ4B2EcwCUAQABAAYJ4B2EcwCUAQAAAA==.Rotfather:BAAALgADCgYJBgAAAA==.Rotjaw:BAAALgAECgUJCwAAAA==.Roughedge:BAAALgADCgIJAgAAAA==.',
Ru='Rurik:BAAALgAECgEJAQAAAA==.',
['Rè']='Rèjuva:BAAALgAECgcJDQAAAA==.Rèptílè:BAAALgADCgMJAwABLgAFFAMJBQAZAA8iAA==.',
['Rî']='Rîcflair:BAAALgAECgcJEwAAAA==.',
Sa='Saiyax:BAAALgADCgYJBwAAAA==.Salidfingers:BAAALgADCgYJBgAAAA==.Sanyakulak:BAAALgADCgcJBwABLgAFFAgJFwAeAGMTAA==.Sanzo:BAAALgADCgkJEgAAAA==.Savathûn:BAAALgAECgQJCAAAAA==.',
Sc='Scalycat:BAABLgAECn8qAAQTAAkJ2A6cGQDBAQATAAkJ2A6cGQDBAQAgAAcJLAZJVQCxAAAhAAIJbgfRIQAwAAAAAA==.Schalla:BAAALgAECgEJAQAAAA==.Scum:BAAALgAECgYJDQAAAA==.Scòrpìòn:BAAALgADCgcJBgABLgAFFAMJBQAZAA8iAA==.',
Se='Seancody:BAAALgADCgIJAgAAAA==.Sekhmett:BAAALgADCgEJAQAAAA==.Selandria:BAAALgADCgQJBAAAAA==.Senate:BAAALgAECgYJCwAAAA==.',
Sh='Shadowbear:BAABLgAECn8cAAIIAAcJ/Rw/GgDOAQAIAAcJ/Rw/GgDOAQAAAA==.Shadowoss:BAAALgAECgYJCAAAAA==.Shadygrump:BAAALgAECgYJEQAAAA==.Shammacass:BAAALgAECgUJBQAAAA==.Shaolincito:BAAALgAECgQJBgAAAA==.Sherrilyn:BAAALgAECgEJAQAAAA==.Shocklocke:BAAALgAECgQJBAAAAA==.',
Si='Sigmachad:BAAALgAECgUJDwAAAA==.Silandrus:BAAALgAECgEJAQAAAA==.Silverocean:BAABLgAECn8uAAIOAAkJzxvqDwCUAgAOAAkJzxvqDwCUAgAAAA==.Silvia:BAAALgADCgUJCQAAAA==.Singularity:BAACLgAFFH8IAAIMAAMJPCTkCwA2AQAMAAMJPCTkCwA2AQAuAAQKf0AAAgwACQlgJnEAAHMDAAwACQlgJnEAAHMDAAAA.',
Sk='Skaerx:BAABLgAECn8WAAMEAAYJVBeOQwCXAQAEAAYJ9RWOQwCXAQAkAAQJZhSYHQADAQAAAA==.Skittlez:BAABLgAECn8mAAIUAAkJkR8lBwCUAgAUAAkJkR8lBwCUAgAAAA==.',
Sl='Slaykween:BAAALgAECgYJCgAAAA==.Slootybooty:BAAALgAECgYJDwAAAA==.',
Sm='Smallz:BAAALgAECgYJDwABLgAECggJGAANACMIAA==.',
Sn='Snipersmash:BAAALgAECgQJCAAAAA==.Snooptrogg:BAABLgAECn8oAAIEAAkJGRXvGwDpAQAEAAkJGRXvGwDpAQAAAA==.Snoozumi:BAABLgAFFH8GAAIVAAMJKQa7LQCVAAAVAAMJKQa7LQCVAAAAAA==.Snuups:BAABLgAECn86AAIXAAkJKxndJwAjAgAXAAkJKxndJwAjAgAAAA==.',
So='Soldiah:BAABLgAECn8VAAIEAAgJqQykMQBfAQAEAAgJqQykMQBfAQAAAA==.Sommbra:BAAALgAECgYJBwAAAA==.Souljax:BAAALgADCgcJCQAAAA==.',
Sp='Spacelaser:BAAALgAECgQJBQAAAA==.',
Sq='Sqwurl:BAAALgADCgQJBAAAAA==.',
St='Steakhaus:BAAALgADCgIJAgAAAA==.Stiros:BAAALgAECgMJAwAAAA==.Stonedragon:BAECLgAFFH8QAAIZAAUJnx+iGQBaAQAZAAUJnx+iGQBaAQAuAAQKfysAAxkACAn+JMwFADEDABkACAn+JMwFADEDAB8AAgn/DiMoAFwAAAAA.Stormfist:BAAALgAECggJEAAAAA==.Stormhaven:BAAALgADCggJIgABLgAECgcJIwAOAJEhAA==.Stormrender:BAAALgAECgYJEAAAAA==.Stormstag:BAAALgADCgYJBgAAAA==.Stouty:BAAALgADCgMJAwABLgAECgcJFAAhAOkaAA==.',
Su='Sukonamí:BAABLgAECn8iAAMEAAkJghckKAAdAgAEAAgJdhUkKAAdAgAkAAQJGhvdHwAzAQAAAA==.Suzhou:BAABLgAECn8jAAIYAAgJowkoEAAUAQAYAAgJowkoEAAUAQAAAA==.Suzoomies:BAAALgADCgcJBwAAAA==.Suzumii:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetcarolin:BAABLgAECn8WAAIQAAkJRg+GXgDXAQAQAAkJRg+GXgDXAQAAAA==.Sweetsmercy:BAAALgAECgQJBQAAAA==.Swiftleaf:BAAALgADCgcJBwAAAA==.Swisscheese:BAABLgAECn8qAAIXAAgJSSEaFACXAgAXAAgJSSEaFACXAgAAAA==.',
Sy='Syraxa:BAAALgAECgEJAgABLgAFFAMJCAAGAPUQAA==.Syril:BAAALgADCgcJDAAAAA==.',
Ta='Taedish:BAAALgADCgMJAwAAAA==.Tahret:BAAALgADCgQJBQAAAA==.Taquillya:BAAALgAECgMJAwAAAA==.Tarina:BAAALgADCgEJAQAAAA==.Tatersaladin:BAAALgADCgMJAwAAAA==.',
Te='Tenlortin:BAAALgAECgEJAQAAAA==.Terragosa:BAABLgAECn8uAAINAAgJXRirQAD/AQANAAgJXRirQAD/AQAAAA==.Teryail:BAAALgADCgkJCwAAAA==.Tetchybono:BAAALgADCgYJBgAAAA==.',
Th='Thade:BAABLgAECn8kAAMkAAkJByEKBAC7AgAkAAgJGiAKBAC7AgAEAAgJfB5XHwBWAgAAAA==.Thaeleon:BAABLgAECn8hAAMHAAgJbx/SDgBHAgAHAAgJbx/SDgBHAgAGAAYJixz+NADUAQABLgAFFAMJBAAJAAAAAA==.Thahawtz:BAAALgADCggJCAAAAA==.Thaneblade:BAAALgAECgQJBgAAAA==.Therizzler:BAAALgAECgcJCQABLgAFFAMJCQAKAAUPAA==.Thickening:BAABLgAECn8ZAAMVAAUJhQ3eTgDUAAAVAAUJhQ3eTgDUAAAFAAUJ9Qd2TwCdAAAAAA==.Thope:BAABLgAECn8YAAINAAYJSAisuwDzAAANAAYJSAisuwDzAAAAAA==.Thoranubran:BAABLgAECn8WAAICAAYJ/w4bMwA+AQACAAYJ/w4bMwA+AQAAAA==.Thrivia:BAAALgAECgYJBgAAAA==.',
Ti='Ticklemychin:BAAALgAECgMJBgAAAA==.Tigani:BAAALgAECgUJDAAAAA==.Tinstey:BAAALgADCgEJAQAAAA==.',
To='Toestiir:BAAALgADCgUJBQAAAA==.Tokemaddab:BAAALgADCgUJBQAAAA==.Toughasnails:BAAALgAECgEJAQAAAA==.',
Tr='Traesdyne:BAAALgAECgEJAQABLgAECgMJAwAJAAAAAA==.Trainar:BAAALgAECgQJCQAAAA==.Trazle:BAAALgAECgIJAgAAAA==.Trekkiegeek:BAAALgADCgEJAQAAAA==.Trickybackup:BAAALgADCgMJAwAAAA==.Triggs:BAAALgAECgcJAgAAAA==.Trollbear:BAAALgAECgcJDwAAAA==.Trondruid:BAAALgADCgYJDQAAAA==.Trooze:BAABLgAECn8uAAIOAAgJhSPFBQAVAwAOAAgJhSPFBQAVAwAAAA==.Trr:BAABLgAECn8pAAIXAAkJmBe2IwCFAgAXAAkJmBe2IwCFAgAAAA==.Truckz:BAAALgADCgEJAQABLgAECgkJLgAZAC0eAA==.Truckzage:BAAALgADCgcJBwABLgAECgkJLgAZAC0eAA==.',
Tu='Tuba:BAAALgAECgYJEAAAAA==.Turim:BAAALgAECgUJBQAAAA==.Tusksrus:BAAALgADCgcJFwAAAA==.',
Ty='Tyrlidd:BAABLgAECn8vAAIZAAgJfxaCNADgAQAZAAgJfxaCNADgAQAAAA==.',
Ud='Udon:BAABLgAECn8UAAIQAAYJ6xHAgAA8AQAQAAYJ6xHAgAA8AQAAAA==.',
Ul='Ultimazero:BAAALgADCgEJAQAAAA==.',
Un='Unavoidable:BAAALgADCgkJEQAAAA==.Unlikelytale:BAABLgAECn8mAAIaAAkJAyEuCgDXAgAaAAkJAyEuCgDXAgAAAA==.Unmilked:BAAALgAECgYJBwAAAA==.',
Ur='Uricash:BAABLgAECn9HAAINAAkJ2h5TEgDTAgANAAkJ2h5TEgDTAgAAAA==.Urzual:BAABLgAECn8oAAIbAAkJDyArBACMAgAbAAkJDyArBACMAgAAAA==.',
Ut='Utiniócast:BAAALgADCgEJAQAAAA==.',
Va='Vandreynna:BAABLgAECn9DAAICAAkJZiUvAQBSAwACAAkJZiUvAQBSAwAAAA==.',
Ve='Vegèta:BAABLgAECn8gAAIQAAkJZAvYawBpAQAQAAkJZAvYawBpAQABLgAFFAMJBQAZAA8iAA==.Veilaura:BAAALgAECgYJCQAAAA==.Velarria:BAABLgAECn8dAAMZAAkJ4h43FQCOAgAZAAkJ4h43FQCOAgAUAAQJjwwcIQDSAAAAAA==.Velikan:BAAALgAECgQJBwABLgAECgcJCAAJAAAAAA==.Velsiana:BAAALgAECgYJDQAAAA==.Velveetah:BAAALgAECgUJCAABLgAECgYJGQADAJ4PAA==.Verbrennen:BAAALgADCgYJBgABLgAECgkJSwAEABYhAA==.Verdreht:BAAALgADCgEJAQABLgAECgkJSwAEABYhAA==.Verita:BAABLgAECn8rAAIjAAcJcCOBAwBAAgAjAAcJcCOBAwBAAgAAAA==.Verlynne:BAAALgADCgYJBgAAAA==.Verylikely:BAAALgAECgEJAgAAAA==.',
Vi='Viviann:BAABLgAECn8kAAITAAkJeRHDDQDOAQATAAkJeRHDDQDOAQAAAA==.',
Vo='Voiager:BAAALgADCgcJCgAAAA==.',
Vr='Vrakal:BAAALgAECgkJDQAAAA==.',
Wa='Wantabehavoc:BAAALgADCgYJDQAAAA==.Wantadeznutz:BAAALgAECgIJAgAAAA==.Warnick:BAAALgADCgQJBQAAAA==.Warraxe:BAAALgADCgUJCAABLgAECgEJAQAJAAAAAA==.Wayloren:BAABLgAECn8nAAIBAAkJVQreYQCNAQABAAkJVQreYQCNAQAAAA==.Waystalker:BAAALgAECgMJAwAAAA==.Wayverly:BAAALgADCgUJBwABLgAECgcJEgAJAAAAAA==.',
Wi='Wickathy:BAABLgAECn88AAInAAkJtB8xAgDFAgAnAAkJtB8xAgDFAgAAAA==.',
Wo='Wolfcity:BAAALgADCgEJAQAAAA==.Wondertauren:BAAALgADCgYJCQAAAA==.Woodson:BAAALgADCgkJEAAAAA==.Worstdps:BAAALgAECgQJBAAAAA==.',
Wr='Wrkandtank:BAAALgAECgEJAQABLgAECgYJEwAJAAAAAA==.',
Wu='Wuldorr:BAACLgAFFH8NAAIBAAQJeRJnMAAuAQABAAQJeRJnMAAuAQAuAAQKfyQAAgEACAm1H0gkAJYCAAEACAm1H0gkAJYCAAAA.',
Wy='Wynnifred:BAAALgAECggJDQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.',
Xe='Xethreal:BAAALgADCgMJAwAAAA==.',
Xy='Xype:BAAALgAECgkJEQAAAA==.',
Ya='Yastoria:BAAALgAECgcJEAAAAA==.',
Yi='Yinandtonic:BAAALgAECgEJBAAAAA==.',
Yv='Yvvee:BAAALgADCgcJBwAAAA==.',
Za='Zaalim:BAAALgADCgQJBAAAAA==.Zapdôs:BAAALgAECgQJBAAAAA==.',
Ze='Zeda:BAAALgAECgEJAQABLgAECgUJCgAJAAAAAA==.Zephyris:BAAALgAECgUJDAABLgAFFAYJIgAkAA8mAA==.',
Zh='Zheng:BAAALgAECgYJBgAAAA==.',
Zi='Zillia:BAAALgADCgMJAwAAAA==.',
Zo='Zonora:BAAALgAECgcJEwAAAA==.',
Zy='Zyphexd:BAAALgAECgYJDwAAAA==.Zyris:BAAALgADCgcJDQAAAA==.',
['Àz']='Àzñós:BAAALgAECgQJBwAAAA==.',
['Äs']='Ästro:BAAALgAECgQJBgABLgAECgkJLQAFAHcaAA==.',
['Äz']='Äzrael:BAABLgAECn8oAAIDAAkJaRqTCgCXAgADAAkJaRqTCgCXAgAAAA==.',
['Åz']='Åznos:BAAALgAECgQJCAAAAA==.',
['Çr']='Çréwüsæðèr:BAABLgAECn8jAAIMAAgJZiA4CABUAgAMAAgJZiA4CABUAgAAAA==.',
['Ðe']='Ðecimus:BAAALgAECgQJCQAAAA==.',
['Ðì']='Ðìaßlo:BAACLgAFFH8FAAIZAAMJDyKAOgD9AAAZAAMJDyKAOgD9AAAuAAQKfzAABBkACAlAHFUvAPUBABkABwnbG1UvAPUBABQABwlYFAQRALMBAB8AAQleABqbABUAAAAA.',
['Öb']='Öblïvïöñ:BAAALgAECgEJAQAAAA==.',
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
