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
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Aberaht:BAABLgAECn8mAAIBAAkJYCOqDQAgAwABAAkJYCOqDQAgAwAAAA==.',
Ad='Adamaro:BAAALgADCgYJCQAAAA==.',
Ae='Aenastian:BAABLgAFFH8IAAICAAMJSxkljgDuAAACAAMJSxkljgDuAAABLgAFFAQJDQADAAobAA==.',
Af='Affrica:BAAALgADCgEJAQABLgAECgYJGQAEAJ4PAA==.',
Ag='Agnu:BAAALgADCgcJBwAAAA==.Agraar:BAAALgAECgUJBwAAAA==.',
Ah='Ahgra:BAABLgAECn89AAIBAAkJugyYewB3AQABAAkJugyYewB3AQAAAA==.',
Ak='Akre:BAAALgAFFAIJBgAAAQ==.Akumä:BAAALgAECgUJCgAAAA==.',
Al='Aleannia:BAAALgAECgYJCgAAAA==.Alekz:BAAALgAECgYJDQAAAA==.Alestria:BAABLgAECn8bAAIBAAgJBRWrbACVAQABAAgJBRWrbACVAQAAAA==.Alibrexia:BAACLgAFFH8IAAIFAAMJmgQtPgCyAAAFAAMJmgQtPgCyAAAuAAQKfyAAAgUACQlrCQ82AHABAAUACQlrCQ82AHABAAAA.Alida:BAABLgAECn8sAAIFAAkJqAo8OABmAQAFAAkJqAo8OABmAQAAAA==.Alithvia:BAAALgAECgYJBgABLgAECgkJJQAGAAskAA==.Allisara:BAAALgADCgkJFgAAAA==.Alysae:BAACLgAFFH8iAAMHAAcJcRs4EQDtAQAHAAcJcRs4EQDtAQAIAAEJSQAwWAAZAAAuAAQKfxsAAwcACAkrHeUdAE8CAAcACAkrHeUdAE8CAAgAAgllBxOYACgAAAAA.',
Am='Amabear:BAAALgAECgEJAQABLgAECgcJHAAJAP0cAA==.Ambrosse:BAAALgADCggJDwABLgAECgkJLQAGAHcaAA==.',
An='Anabug:BAAALgAECgMJBQAAAA==.Andelwynn:BAAALgAECgMJAwABLgAECgkJIAAKAMoIAA==.Angelsmentor:BAAALgAECgYJCgAAAA==.Aniellas:BAAALgAECgIJAgAAAA==.Annalese:BAAALgADCgUJCQABLgAECgkJIAAKAMoIAA==.',
Ap='Apocalyptic:BAAALgADCgEJAQAAAA==.',
Ar='Arabeli:BAAALgAECgEJAQAAAA==.Arbyss:BAAALgADCgcJDAAAAA==.Ardatha:BAAALgADCgcJFwAAAA==.Ariêz:BAAALgAECgIJAgAAAA==.Artio:BAABLgAECn8bAAMLAAgJSQOKAgBmAAABAAcJVAIaKQGIAAALAAUJxwOKAgBmAAAAAA==.',
As='Asterön:BAAALgAECgcJEwAAAA==.Astrocakes:BAAALgAECgMJAwABLgAFFAQJEgAMAMEUAA==.',
At='Athenä:BAACLgAFFH8rAAILAAgJbRGHAQDYAQALAAgJbRGHAQDYAQAuAAQKfzwAAgsACQl7HPkFAI4CAAsACQl7HPkFAI4CAAAA.Atsuma:BAABLgAECn8gAAINAAgJIAszJAAPAQANAAgJIAszJAAPAQAAAA==.',
Av='Avacynn:BAAALgAECgMJAwAAAA==.Aviz:BAAALgADCgMJAwAAAA==.',
Aw='Awtysmbb:BAAALgAECgUJBQABLgAFFAMJBwAOABIXAA==.',
Ay='Aylli:BAAALgAECgYJCgABLgAECgkJNwAEAFMcAA==.',
['Aí']='Aísling:BAABLgAECn8rAAIPAAkJuh50DgCtAgAPAAkJuh50DgCtAgAAAA==.',
Ba='Baboii:BAAALgADCgIJAgAAAA==.Baconmecrazy:BAAALgAECgEJAQAAAA==.Badinngo:BAAALgADCggJDwABLgAECgkJJAAQABcgAA==.Bahiu:BAAALgAECgQJBAAAAA==.Bajafresh:BAAALgAECgQJBQAAAA==.Battleshaman:BAAALgADCgYJBgAAAA==.',
Bd='Bd:BAABLgAECn8dAAIRAAgJJxU5GABGAgARAAgJJxU5GABGAgAAAA==.',
Be='Beardmedaddy:BAAALgAECgYJBgABLgAECgkJMAAFAI4hAA==.Bearstavious:BAABLgAFFH8GAAISAAMJXxZmGADDAAASAAMJXxZmGADDAAAAAA==.Benjinana:BAABLgAECn8ZAAMEAAYJng+ZOwAHAQAEAAYJng+ZOwAHAQAJAAIJJQPOWgBMAAAAAA==.Betterthanu:BAAALgADCgUJBQABLgADCgYJCgATAAAAAA==.',
Bg='Bg:BAAALgAECgYJBwAAAA==.',
Bi='Bige:BAAALgAECgYJEQAAAA==.Bilo:BAAALgAECgYJCAAAAA==.Bitelyus:BAAALgAECgUJCAAAAA==.',
Bl='Blazara:BAAALgAECgEJAQAAAA==.Blessedbymom:BAAALgADCgEJAQAAAA==.',
Bo='Bobius:BAAALgAECgkJDwAAAA==.Bobohizan:BAAALgADCgQJBAAAAA==.Bohde:BAABLgAFFH8OAAMCAAUJ6iIfSwBcAQACAAQJ6iIfSwBcAQAUAAEJAAAvUwAAAAAAAA==.Bolognaman:BAAALgAECgUJCAAAAA==.Bombjovi:BAABLgAECn8gAAMLAAkJchWNDgDaAQALAAkJchWNDgDaAQAPAAUJlA9YVADmAAAAAA==.Bountty:BAAALgAECgQJBAAAAA==.',
Br='Brahmsthoven:BAAALgADCgIJAwAAAA==.Branndhon:BAABLgAECn8qAAIHAAcJ5hV1NgC/AQAHAAcJ5hV1NgC/AQAAAA==.Bronislav:BAAALgAECgEJAQAAAA==.',
Bt='Btrflyprncss:BAAALgADCgMJAwAAAA==.',
Bu='Bubblemedic:BAAALgADCgIJAgAAAA==.Budde:BAAALgAECgUJBQAAAA==.Buffaloseven:BAABLgAECn8VAAMPAAcJ9gpMRAAvAQAPAAcJ9gpMRAAvAQABAAUJ9QSlIQGRAAABLgAFFAgJFgAOAOwMAA==.',
Ca='Cairdamane:BAABLgAECn8hAAIVAAkJ5BHqLgCFAQAVAAkJ5BHqLgCFAQAAAA==.Calidrina:BAABLgAECn8iAAIMAAkJMhyGQQDEAQAMAAkJMhyGQQDEAQAAAA==.Carm:BAAALgAECgYJBgAAAA==.Caroliná:BAAALgAECgUJCwAAAA==.Catcast:BAAALgAECgUJCAABLgAFFAMJCgAWACcPAA==.Catclaw:BAAALgAECgEJAQABLgAFFAMJCgAWACcPAA==.',
Ce='Celiri:BAABLgAECn8nAAIGAAkJrxB7IQCjAQAGAAkJrxB7IQCjAQAAAA==.Celldrassil:BAABLgAECn81AAIHAAkJAQddXQAfAQAHAAkJAQddXQAfAQAAAA==.Cereel:BAAALgAECgMJAwABLgAFFAQJEgAMAMEUAA==.',
Ch='Chadaracka:BAAALgAECgYJBwAAAA==.Chandelure:BAAALgAECgUJCwAAAA==.Chardaney:BAABLgAECn8gAAIKAAkJyghDEwAqAQAKAAkJyghDEwAqAQAAAA==.Cherryontop:BAABLgAECn8qAAIHAAgJVBQoMgDXAQAHAAgJVBQoMgDXAQAAAA==.Chozenone:BAAALgAECgUJEgAAAA==.Chozi:BAAALgAECgYJBgAAAA==.Chromosomie:BAABLgAFFH8IAAIXAAQJEgVxPwDJAAAXAAQJEgVxPwDJAAABLgAECgkJMAAOAOcbAA==.',
Ci='Cii:BAABLgAECn8hAAMLAAgJaxAiFwBoAQALAAgJNRAiFwBoAQABAAUJew2r2wDkAAAAAA==.',
Co='Coconutwater:BAAALgAFFAEJAQAAAA==.Colandros:BAABLgAECn9AAAIYAAkJ/gupGgDJAQAYAAkJ/gupGgDJAQAAAA==.Colara:BAABLgAECn8dAAIMAAcJSwRxuwC1AAAMAAcJSwRxuwC1AAAAAA==.Combobreaker:BAACLgAFFH8NAAIZAAMJVx50LgAAAQAZAAMJVx50LgAAAQAuAAQKfzQAAhkACQm+H/kHAB0DABkACQm+H/kHAB0DAAAA.Comoo:BAAALgAECgEJAQAAAA==.Correct:BAAALgAECgEJAQAAAA==.Cowbôy:BAAALgADCgkJEQAAAA==.',
Cr='Crassberry:BAACLgAFFH8lAAMCAAgJXx9ZDgBsAgACAAgJXx9ZDgBsAgAaAAEJkQi6BABMAAAuAAQKfygAAgIACQk2JBQFAIMDAAIACQk2JBQFAIMDAAAA.Crazyraptor:BAAALgAECgYJDAABLgAECggJFQAbAHcLAA==.Crazèd:BAAALgADCgQJBAAAAA==.Crimes:BAAALgAECgIJAwAAAA==.',
Cu='Cutco:BAABLgAFFH8HAAIcAAMJcB1cAADxAAAcAAMJcB1cAADxAAAAAA==.',
Cy='Cyndal:BAABLgAECn8ZAAIOAAYJhBtMcQCXAQAOAAYJhBtMcQCXAQAAAA==.Cyndle:BAABLgAECn8ZAAIGAAYJARy2IwCUAQAGAAYJARy2IwCUAQABLgAECgYJGQAOAIQbAA==.Cyntu:BAAALgAECgUJCwABLgAECgYJGQAOAIQbAA==.',
['Cü']='Cüpid:BAAALgAECgYJBgAAAA==.',
Da='Dada:BAAALgAECgEJAQAAAA==.Dammithells:BAAALgADCgQJBAAAAA==.Dandamar:BAAALgAECgYJBgAAAA==.Dankbuds:BAAALgAECgYJAwAAAA==.Dankfists:BAAALgAECgUJBQABLgAECgYJAwATAAAAAA==.Dankhaze:BAAALgAFFAIJAgABLgAECgYJAwATAAAAAA==.Danksmash:BAAALgAECgkJBQABLgAECgYJAwATAAAAAA==.Dankzor:BAAALgAECgcJBQABLgAECgYJAwATAAAAAA==.Dark:BAAALgADCgEJAQAAAA==.Darthrevan:BAAALgAECgQJBwAAAA==.Dasharnkal:BAAALgADCgUJCAAAAA==.Dasvult:BAAALgAECgMJBAAAAA==.Dazex:BAABLgAECn8hAAMEAAYJrgU2TwCkAAAEAAYJYQU2TwCkAAAdAAUJRwIUXQCLAAAAAA==.',
De='Deadpump:BAABLgAECn8fAAMbAAcJfRLDegBDAQAbAAcJfRLDegBDAQAeAAQJUQ4aOQDQAAAAAA==.Demonsnotkey:BAAALgAECgYJCwAAAA==.Demoxus:BAAALgAECgQJBAAAAA==.Denker:BAAALgADCggJCAAAAA==.Denkzilla:BAAALgADCgIJAgAAAA==.Denzvic:BAAALgAECgEJAQAAAA==.Destro:BAAALgAECgEJAQAAAA==.Deusclaw:BAAALgAECgYJCgAAAA==.Devilah:BAAALgAECgEJAQAAAA==.',
Dh='Dharm:BAABLgAECn8tAAMfAAkJuRjnMQAUAgAfAAkJuRjnMQAUAgAYAAIJxQz9TwBwAAAAAA==.',
Di='Dialsl:BAAALgADCgUJCQAAAA==.Digbickpanda:BAAALgAECgUJDwABLgAFFAQJEgAMAMEUAA==.Disowneege:BAABLgAECn8oAAIBAAgJuyE9IQCCAgABAAgJuyE9IQCCAgABLgAFFAgJIgAFAAcgAA==.Diyos:BAAALgADCgYJCgAAAA==.',
Do='Dotndash:BAAALgADCgIJAgAAAA==.Doubledge:BAAALgAECgEJAQAAAA==.Doublejump:BAACLgAFFH8bAAIMAAUJjBOCSQANAQAMAAUJjBOCSQANAQAuAAQKfykAAgwACAk4HgYmADUCAAwACAk4HgYmADUCAAAA.',
Dr='Dragdh:BAAALgAECgcJEwABLgAECggJKgAgAJ8cAA==.Dragnas:BAABLgAECn8qAAQgAAgJnxxRDADtAQAgAAgJnxxRDADtAQAQAAcJrBT0PQC2AQAVAAQJvhaFXgDJAAAAAA==.Dragonisa:BAAALgAFFAEJAQAAAA==.Dragun:BAAALgADCgIJAgAAAA==.Draiocht:BAAALgADCgMJBAABLgAECgkJNwAEAFMcAA==.Drakeskid:BAAALgAECgQJBwABLgAFFAQJBgAhALgKAA==.Drakthall:BAAALgAECgIJAwAAAA==.Dralionethny:BAAALgAECgIJAgAAAA==.Dramakiller:BAABLgAECn8XAAMfAAYJMgyDlAAXAQAfAAYJMgyDlAAXAQAKAAMJPAKOOAA9AAAAAA==.Drchi:BAAALgAECgEJAQABLgAECgYJGQAiAIcVAA==.Drcornbread:BAABLgAECn8ZAAMiAAYJhxXSGgA2AQAiAAYJhxXSGgA2AQASAAEJ0AMmigATAAAAAA==.Drcornellia:BAAALgAECgUJCAABLgAECgYJGQAiAIcVAA==.Drdarkskin:BAAALgAECgcJDQAAAA==.Drdreggs:BAABLgAECn8pAAMeAAkJmBZhEQAwAQAbAAgJuBSYTwDZAQAeAAYJmxdhEQAwAQAAAA==.Dreggs:BAAALgADCgcJEwAAAA==.Drewskie:BAAALgADCgQJBAAAAA==.Drizztin:BAAALgADCgEJAQAAAA==.Drprominus:BAABLgAECn8gAAIPAAgJACLaCQDuAgAPAAgJACLaCQDuAgAAAA==.Drthargyll:BAAALgADCgYJDgABLgAECggJIAAPAAAiAA==.',
Du='Dushman:BAAALgADCgYJBgAAAA==.',
Dy='Dykdanglr:BAAALgADCgYJBgABLgAECgQJCAATAAAAAA==.',
['Dí']='Dígifóx:BAAALgAECgEJAgAAAA==.Dígífóx:BAAALgAFFAEJAQAAAA==.',
Ea='Earthereal:BAABLgAECn80AAIZAAkJbxeSFQBtAgAZAAkJbxeSFQBtAgAAAA==.',
El='Elastar:BAABLgAECn8mAAINAAkJ6RYKDgApAgANAAkJ6RYKDgApAgAAAA==.Ellimist:BAECLgAFFH8nAAIQAAcJMhyfBQBuAgAQAAcJMhyfBQBuAgAuAAQKfykAAxAACQl9G3QXAFoCABAACQl9G3QXAFoCABUABQk0FxdQAAcBAAAA.Elsan:BAAALgAECgEJAQAAAA==.Elycee:BAACLgAFFH8IAAIfAAMJyyXMRwAeAQAfAAMJyyXMRwAeAQAuAAQKfyIAAx8ACQmtJc4IABMDAB8ACAk+Js4IABMDAAoACAmWGZYgACECAAAA.Elysria:BAAALgADCgYJBgAAAA==.Elí:BAAALgAECgQJBAAAAA==.',
En='Encrid:BAAALgAECgcJDwABLgAFFAMJCQAXANEYAA==.Enhasa:BAABLgAECn8gAAICAAkJ/hUnMQA6AgACAAkJ/hUnMQA6AgABLgAECgYJGgABAOggAA==.Enoeht:BAABLgAECn82AAIDAAkJ2gsgIQBvAQADAAkJ2gsgIQBvAQAAAA==.Enveliria:BAAALgAECgcJDQABLgAFFAQJDQADAAobAA==.',
Er='Eraser:BAAALgAECgYJCAAAAA==.Erazar:BAABLgAECn9EAAIjAAgJghWuBwC+AQAjAAgJghWuBwC+AQAAAA==.Eriah:BAAALgADCgkJCQAAAA==.Erickk:BAABLgAECn8wAAMOAAkJ5xuwQgATAgAOAAkJnBqwQgATAgAkAAQJVx1SCwAkAQAAAA==.',
Es='Essense:BAABLgAECn8mAAIEAAkJmyRIAwApAwAEAAkJmyRIAwApAwAAAA==.',
Ex='Exodari:BAABLgAECn87AAIgAAkJ7hgHCwAHAgAgAAkJ7hgHCwAHAgAAAA==.',
Fa='Fabbioh:BAAALgADCgEJAQAAAA==.Fadeddh:BAACLgAFFH8SAAIMAAQJwRTRBwDWAAAMAAQJwRTRBwDWAAAuAAQKfzAAAgwACQn/G08jAEMCAAwACQn/G08jAEMCAAAA.Faizarah:BAAALgAECgYJBgAAAA==.Faydien:BAAALgAECgEJAgAAAA==.',
Fe='Fearnoevil:BAAALgADCgMJAwAAAA==.Fel:BAABLgAECn8RAAIMAAgJjRqTXgBtAQAMAAgJjRqTXgBtAQAAAA==.Fellkarras:BAAALgAECgYJDwABLgAFFAMJDQAZAFceAA==.Fent:BAABLgAECn8VAAIbAAgJdwsBcgBWAQAbAAgJdwsBcgBWAQAAAA==.',
Fi='Fiddich:BAAALgAECgYJBgAAAA==.Fillthy:BAACLgAFFH8gAAIZAAcJYRnHAQCxAQAZAAcJYRnHAQCxAQAuAAQKfy4AAxkACQlYIkYDAEcDABkACQlYIkYDAEcDAAYAAwkhCQF2AGQAAAAA.Finnigann:BAAALgAECgYJCwAAAA==.Firenmylazer:BAAALgAECgQJBAAAAA==.Fistav:BAAALgADCgcJDgAAAA==.Fizban:BAABLgAECn8fAAIOAAgJsAizoAA6AQAOAAgJsAizoAA6AQAAAA==.',
Fl='Flappybird:BAAALgAECgYJCAABLgAFFAQJEgAMAMEUAA==.Flasan:BAAALgADCgEJAQAAAA==.Flazz:BAAALgADCgIJAwAAAA==.Flazzan:BAAALgADCgEJAQAAAA==.Flik:BAAALgAECggJCAABLgAFFAMJDgAHAE0TAA==.',
Fo='Fogbringer:BAAALgAECgIJAwAAAA==.Four:BAAALgADCgQJBAAAAA==.',
Fr='Frejä:BAAALgAECgQJBQABLgAECgQJDAATAAAAAA==.Freyah:BAAALgAECgUJEgAAAA==.Frostmay:BAAALgAECgIJAgAAAA==.',
Fu='Furrybawlz:BAAALgAECgUJCgABLgAECgYJDQATAAAAAA==.',
Ga='Gabran:BAAALgAECgcJBwAAAA==.Gadogear:BAABLgAECn8oAAIOAAkJ7hdJPQAmAgAOAAkJ7hdJPQAmAgAAAA==.Galahan:BAAALgAECgUJBgAAAA==.Garlick:BAAALgADCggJDwABLgAECggJRAAjAIIVAA==.Garlik:BAAALgADCgMJBAAAAA==.',
Ge='Gertra:BAAALgAECgEJAgABLgAECgYJCAATAAAAAA==.',
Gf='Gfr:BAABLgAECn8XAAMeAAkJmBjJAwBRAgAeAAkJmBjJAwBRAgAbAAMJ5xK7AwC2AAAAAA==.',
Gi='Girthrichard:BAAALgAECgYJDAAAAA==.',
Gl='Glassdragon:BAABLgAECn8nAAIBAAkJUQz9hABlAQABAAkJUQz9hABlAQAAAA==.Gllor:BAAALgADCgIJAgAAAA==.',
Go='Goatcheeze:BAABLgAECn8cAAIkAAkJLhUFBADGAQAkAAkJLhUFBADGAQAAAA==.Goatylocks:BAABLgAECn8rAAMeAAkJ7RWADQBlAQAbAAgJvRCVVACeAQAeAAYJLByADQBlAQAAAA==.Gohlemsaurus:BAAALgAECgYJDAAAAA==.Goldenchild:BAAALgAFFAMJBAABLgAFFAQJEgAMAMEUAA==.',
Gr='Greatluckydo:BAAALgADCgEJAQAAAA==.Grishnakh:BAAALgAECgQJBAAAAA==.Grozlek:BAAALgADCgYJBgAAAA==.',
Gu='Gulen:BAABLgAECn8YAAIQAAgJLB/NIwA4AgAQAAgJLB/NIwA4AgAAAA==.',
Gw='Gwendyla:BAAALgADCgkJFgAAAA==.',
Gy='Gyousei:BAAALgAECgUJBQAAAA==.',
['Gí']='Gíga:BAABLgAECn8XAAIfAAgJ7RPdKQAPAgAfAAgJ7RPdKQAPAgAAAA==.',
Ha='Hafnium:BAAALgAECgIJAgAAAA==.Hamish:BAAALgAECgUJDQAAAA==.Hanhaine:BAACLgAFFH8GAAIIAAMJcwW5OQCUAAAIAAMJcwW5OQCUAAAuAAQKfywAAggACQnqFlATADoCAAgACQnqFlATADoCAAAA.Hazirat:BAAALgAECgYJDAAAAA==.',
He='Hedlie:BAAALgAECggJCwAAAA==.Hellenkeller:BAECLgAFFH8HAAIZAAYJhw/NIgBYAQAZAAYJhw/NIgBYAQAuAAQKfx8AAhkABwkzITQTADMCABkABwkzITQTADMCAAEuAAUUBwkgACUA9xsA.Heloisa:BAAALgAECgYJEQAAAA==.Helrazr:BAAALgAFFAEJAgAAAA==.Henshin:BAACLgAFFH8OAAIHAAMJTROgBACcAAAHAAMJTROgBACcAAAuAAQKf0QAAwcACQmxHXcQAM4CAAcACQmxHXcQAM4CAAgAAgk4DluLADUAAAAA.',
Hi='Hitt:BAAALgAECgcJCAAAAA==.',
Ho='Hogwortsfun:BAAALgAECgkJAgAAAA==.Holirolla:BAAALgAECgMJAwAAAA==.Holyhim:BAAALgADCgIJAgAAAA==.Holyshawk:BAAALgAECgEJAwAAAA==.Holysudz:BAAALgADCgYJBgAAAA==.Hottyshmotty:BAAALgAECgEJAQAAAA==.Hourglass:BAABLgAECn9AAAMfAAkJlhrMHQByAgAfAAkJlhrMHQByAgAKAAQJ1g3oXwDBAAAAAA==.',
Hr='Hroc:BAAALgAECgUJCwAAAA==.',
Hu='Hunterviral:BAAALgADCgEJAgAAAA==.Huntthejuan:BAAALgADCgUJBQAAAA==.',
Ic='Icyowneege:BAAALgADCgUJBQABLgAFFAgJIgAFAAcgAA==.Icywolfy:BAAALgAECgYJCAAAAA==.',
Ig='Igreetyou:BAABLgAECn8pAAIbAAcJXR5vLAAoAgAbAAcJXR5vLAAoAgAAAA==.',
Il='Illie:BAABLgAECn8mAAIgAAkJShyHBQCtAgAgAAkJShyHBQCtAgAAAA==.Illune:BAACLgAFFH8HAAIOAAMJEhcXeQDnAAAOAAMJEhcXeQDnAAAuAAQKfysAAw4ACQlgGkwzAEwCAA4ACQlgGkwzAEwCACQABglSDhkJAFsBAAAA.',
Im='Imanbearpig:BAABLgAFFH8GAAISAAMJhwfFBABfAAASAAMJhwfFBABfAAAAAA==.Imleapingit:BAABLgAECn8wAAIFAAkJjiHXBgDxAgAFAAkJjiHXBgDxAgAAAA==.',
In='Intoodeep:BAABLgAFFH8FAAIcAAMJ3QOLAACuAAAcAAMJ3QOLAACuAAAAAA==.Intoodragons:BAACLgAFFH8LAAIXAAMJogcQTACdAAAXAAMJogcQTACdAAAuAAQKfzYAAxcACQmcFGscAPIBABcACQmcFGscAPIBACMABglaBfokAP4AAAAA.Inyah:BAAALgAECgIJAgAAAA==.',
Io='Ionzz:BAABLgAECn8ZAAIDAAkJrx+iCADYAgADAAkJrx+iCADYAgAAAA==.',
Ir='Ir:BAAALgAECggJDwAAAA==.Iroann:BAAALgAECgcJEgAAAA==.',
Is='Isawarriorr:BAACLgAFFH8FAAINAAMJJR0tFwDiAAANAAMJJR0tFwDiAAAuAAQKfywAAg0ACQmCI4kDAB8DAA0ACQmCI4kDAB8DAAAA.Ishaq:BAAALgAECgQJBQABLgAECggJIAAhAF4FAA==.Ishdo:BAAALgAECgUJBgABLgAECggJIAAhAF4FAA==.Ishdu:BAAALgAECgQJBAABLgAECggJIAAhAF4FAA==.Ishkhan:BAABLgAECn8gAAMhAAgJXgVIQgDxAAAhAAgJ4QRIQgDxAAAGAAYJUQUOYACaAAAAAA==.Ishmael:BAACLgAFFH8NAAMNAAMJjxkbGQDPAAANAAMJjxkbGQDPAAAFAAEJiw2YUwBEAAAuAAQKfxQAAwUACQk6HkIWAD0CAAUACQkwHEIWAD0CAA0AAglmGzU8AIIAAAAA.Ishwar:BAAALgADCgYJBgABLgAECggJIAAhAF4FAA==.',
Ja='Jakytreehorn:BAACLgAFFH8PAAMVAAcJhgkPBADLAAAVAAYJwwkPBADLAAAQAAUJ5QMiSwDEAAAuAAQKfzkAAxUACQn9Fn8cAP0BABUACAn3F38cAP0BABAACQlCFQwoAPABAAAA.Jasher:BAAALgAECgYJBgAAAA==.Jaydm:BAABLgAECn8dAAImAAYJRxiPHwBhAQAmAAYJRxiPHwBhAQABLgAFFAgJFgAOAOwMAA==.',
Je='Jenevelle:BAAALgAECgcJCgAAAA==.Jerisil:BAAALgADCgQJBAAAAA==.Jet:BAABLgAECn8aAAIBAAYJ6CAySwABAgABAAYJ6CAySwABAgAAAA==.',
Ji='Jibbajabba:BAAALgADCgcJBwAAAA==.Jimbo:BAABLgAFFH8KAAIbAAMJDh/4XgAKAQAbAAMJDh/4XgAKAQABLgAFFAgJJQACAF8fAA==.',
Jo='Johnmayer:BAAALgAECgEJAQAAAA==.',
Ju='Judgecalypso:BAAALgAECgQJBgAAAA==.Judgiah:BAAALgAECgUJBQAAAA==.Julthaenia:BAABLgAECn8lAAQnAAcJZx8ZBgAgAgAnAAcJZx8ZBgAgAgAeAAQJGAr1SwCJAAAbAAUJcQsJ9QB4AAABLgAFFAQJDQADAAobAA==.Justeatjuan:BAAALgAECgMJAwAAAA==.',
Ka='Kagebushin:BAAALgAECgMJBAAAAA==.Kalazin:BAAALgAECgUJBQAAAA==.Kalimah:BAAALgADCgMJAwAAAA==.Kallekgos:BAAALgAECgEJAQAAAA==.Kalofelement:BAAALgAECgcJCAAAAA==.Karash:BAAALgAECgYJCAABLgAECggJFQAZAJ4OAA==.Karmaisab:BAAALgADCgEJAQAAAA==.Karnrae:BAACLgAFFH8HAAIBAAIJMwzDkgCOAAABAAIJMwzDkgCOAAAuAAQKfyoAAgEACQkrEr9RANQBAAEACQkrEr9RANQBAAAA.Karynos:BAABLgAECn8nAAMbAAkJyQ10VQCcAQAbAAkJmgx0VQCcAQAeAAcJyQkOIwA/AQAAAA==.Katnelly:BAAALgAECgMJAwAAAA==.Kazmacoryy:BAAALgAECgYJEAAAAA==.',
Ke='Keedis:BAAALgAECgEJAQAAAA==.Keristrasza:BAAALgAFFAEJAQABLgAFFAgJKAAQAOYbAA==.',
Kh='Khlarm:BAAALgADCgIJAgABLgAECgkJLQAfALkYAA==.',
Ki='Kileely:BAAALgAECgMJAwAAAA==.Kirintore:BAAALgAECgUJCQAAAA==.',
Kk='Kkaiser:BAAALgAECgUJBQAAAA==.',
Kl='Klaudeus:BAAALgAECgEJAQAAAA==.',
Ko='Kodian:BAAALgADCgEJAQAAAA==.Kolypso:BAABLgAECn8aAAIfAAkJoBWzLwAeAgAfAAkJoBWzLwAeAgAAAA==.Konceal:BAAALgAECgEJAQAAAA==.Konspiracy:BAABLgAECn8pAAIeAAkJpxawBgD0AQAeAAkJpxawBgD0AQAAAA==.Konvict:BAAALgAECgIJAwABLgAECgYJDQATAAAAAA==.',
Kr='Krataar:BAABLgAECn8hAAIFAAkJEyGfDACgAgAFAAkJEyGfDACgAgAAAA==.Kravvan:BAAALgAECgUJCgABLgAECggJHwAOALAIAA==.Krousvor:BAAALgAECgQJBwAAAA==.Kryph:BAABLgAECn8dAAICAAkJQAiNegBuAQACAAkJQAiNegBuAQAAAA==.',
Ku='Kugruk:BAAALgAECgcJDAAAAA==.Kurjo:BAAALgAECgMJBAAAAA==.',
Ky='Kyleschlong:BAAALgAECgMJCAAAAA==.Kyndreith:BAAALgAECgMJAwAAAA==.',
['Kä']='Kämpfer:BAABLgAECn9QAAIFAAkJFiESCADeAgAFAAkJFiESCADeAgAAAA==.',
La='Lafiel:BAABLgAECn8dAAMEAAkJGgtKPABJAQAEAAkJGgtKPABJAQAJAAIJ1QiHdwBRAAAAAA==.Landiedoo:BAAALgAECgkJCgAAAA==.Laurana:BAAALgADCgYJBgAAAA==.Laurandre:BAAALgAECgcJBwAAAA==.Laverna:BAAALgADCgMJBAAAAA==.Lazeras:BAAALgAECgUJCQABLgAFFAEJAgATAAAAAA==.',
Le='Lefay:BAAALgADCgcJFwAAAA==.Leprawnjames:BAAALgAECggJCQABLgAECgkJGQASAKofAA==.Letsgetwet:BAAALgADCgYJBgAAAA==.',
Li='Liefic:BAAALgAECgcJCQAAAA==.Lillavender:BAAALgADCgYJBgAAAA==.Limon:BAAALgADCgIJAgAAAA==.',
Lo='Loadin:BAAALgAECgIJAgAAAA==.Lockaflockå:BAAALgADCgMJAwAAAA==.Locke:BAAALgAECgMJAgABLgAECgYJGgABAOggAA==.Lonoh:BAAALgAECgcJEgAAAA==.',
Lu='Luan:BAAALgAECgMJAwAAAA==.Lucariø:BAAALgADCgcJDAAAAA==.Lucidbonsai:BAAALgADCggJCAAAAA==.Luckykilla:BAABLgAECn8tAAIcAAkJJh3QAgCeAgAcAAkJJh3QAgCeAgAAAA==.Lucÿ:BAACLgAFFH8RAAIQAAYJKBCwHgB8AQAQAAYJKBCwHgB8AQAuAAQKfyIAAxAABwmsGPQoAOwBABAABwmsGPQoAOwBABUAAwkVDHR5AIIAAAAA.Lula:BAAALgADCgMJAwAAAA==.Lurith:BAABLgAECn9ZAAMCAAkJ1xqWJwBkAgACAAkJhRiWJwBkAgAUAAkJLRVFEwDdAQAAAA==.Lutreaux:BAAALgADCgEJAQAAAA==.Luxtyrannica:BAABLgAECn8pAAIBAAkJ2x6fFQDBAgABAAkJ2x6fFQDBAgAAAA==.',
Ly='Lydrain:BAAALgAECgEJAQAAAA==.Lysandria:BAABLgAECn8rAAIOAAkJmw3aagCmAQAOAAkJmw3aagCmAQAAAA==.',
Ma='Macrosblack:BAAALgADCgMJAwAAAA==.Madamerouge:BAAALgAECgIJAgABLgAECgYJGQAiAIcVAA==.Magearino:BAABLgAECn8nAAIOAAgJnRatXwDBAQAOAAgJnRatXwDBAQAAAA==.Malafore:BAAALgADCgEJAQAAAA==.Malcolm:BAAALgAECgEJAgABLgAECgkJMgAFACsWAA==.Malcrux:BAAALgAECgIJAgAAAA==.Marcopally:BAAALgAECgQJBAAAAA==.Marluxia:BAACLgAFFH8jAAISAAcJUAu+EQD3AAASAAcJUAu+EQD3AAAuAAQKfxoAAhIACAkhE/YMALkBABIACAkhE/YMALkBAAAA.Mastamonk:BAAALgAECgQJBAAAAA==.Materfamilia:BAAALgAECgQJBAAAAA==.Mattbull:BAACLgAFFH8JAAMXAAMJ0RiJOwDZAAAXAAMJ0RiJOwDZAAAjAAEJ1xNICQBXAAAuAAQKfx4AAyMABgmqJFcNAAQCACMABglCIlcNAAQCABcABgl5ImAgANYBAAAA.Mayu:BAAALgAECgEJAgAAAA==.',
Me='Medjrab:BAACLgAFFH8UAAICAAUJxhjpYwAvAQACAAUJxhjpYwAvAQAuAAQKfzIAAgIACQlLIjYTANUCAAIACQlLIjYTANUCAAAA.Meristem:BAABLgAECn8xAAIIAAkJiw9MIgC2AQAIAAkJiw9MIgC2AQAAAA==.Merko:BAAALgADCgkJDwAAAA==.',
Mi='Miaan:BAAALgADCgYJBgAAAA==.Miette:BAAALgADCgMJAwAAAA==.Mihonk:BAAALgADCgQJBAAAAA==.Mintycrx:BAABLgAECn8fAAIOAAkJHhGaUwDiAQAOAAkJHhGaUwDiAQAAAA==.Missfist:BAAALgADCgIJAgAAAA==.Mistlocke:BAAALgADCgMJAwAAAA==.',
Mn='Mngwa:BAAALgAECgQJCwAAAA==.',
Mo='Moegu:BAABLgAECn8cAAIoAAkJFBYXCAD3AQAoAAkJFBYXCAD3AQAAAA==.Mog:BAACLgAFFH8MAAMbAAMJLSB3CgCjAAAbAAIJwSJ3CgCjAAAnAAEJBxsxAwBUAAAuAAQKfzkABBsACQmeI/sVAKECABsABwnVI/sVAKECACcAAwmVI6oYAP4AAB4AAwkJEsI2ANsAAAAA.Mogma:BAAALgAECgQJBAAAAA==.Moncatsera:BAAALgAECgQJBAAAAA==.Mondgrille:BAAALgAECgQJBAABLgAECgYJDQATAAAAAA==.Monora:BAABLgAECn8aAAIZAAgJ6wuuSgBBAQAZAAgJ6wuuSgBBAQAAAA==.Montress:BAABLgAECn8UAAIEAAgJBhDvJwCGAQAEAAgJBhDvJwCGAQAAAA==.Moomoohealz:BAACLgAFFH8QAAIIAAMJ8RmmAwDIAAAIAAMJ8RmmAwDIAAAuAAQKfz4AAggACQkoIW8IAM0CAAgACQkoIW8IAM0CAAAA.Moonbounds:BAACLgAFFH8oAAIQAAgJ5hu+AwCZAgAQAAgJ5hu+AwCZAgAuAAQKfzgAAxAACQndJFEDAEQDABAACQndJFEDAEQDABUAAQnZH4Z5AF0AAAAA.Moondoggey:BAAALgAECgMJAwAAAA==.Morgana:BAAALgADCgIJAgAAAA==.Mortemcleric:BAAALgADCgYJBgAAAA==.Mousechief:BAABLgAECn9CAAIVAAgJiAjCAQDtAAAVAAgJiAjCAQDtAAAAAA==.Moxnix:BAABLgAECn8VAAMZAAgJng70VQAZAQAZAAcJXgz0VQAZAQAhAAQJjgVYXQCZAAAAAA==.Moxxzi:BAAALgAFFAEJAgAAAA==.',
Mu='Muhfookinbak:BAABLgAECn8kAAMQAAkJFyDbEADJAgAQAAkJFyDbEADJAgAVAAQJhxiUXQDLAAAAAA==.',
Mv='Mvse:BAAALgADCgcJBwAAAA==.',
My='Myor:BAAALgADCgMJAwAAAA==.',
['Mà']='Màttbull:BAABLgAFFH8HAAIMAAMJcw79ZwC9AAAMAAMJcw79ZwC9AAABLgAFFAMJCQAXANEYAA==.',
['Mä']='Märcøsferätv:BAAALgAECgEJAQAAAA==.',
Na='Naesta:BAAALgAECgIJAgABLgAFFAMJBgAHALgLAA==.Naksu:BAAALgAECgEJAQABLgAECggJJQAMACEJAA==.Naksù:BAABLgAECn8lAAIMAAgJIQkgjAAIAQAMAAgJIQkgjAAIAQAAAA==.Namal:BAAALgAECgQJBQAAAA==.Narenae:BAABLgAECn8lAAIGAAkJCyRABABIAwAGAAkJCyRABABIAwAAAA==.Nastalan:BAAALgADCgYJCgAAAA==.',
Ne='Nefari:BAAALgADCgMJAwAAAA==.Neifeb:BAABLgAECn8uAAIfAAkJeRf5NwD+AQAfAAkJeRf5NwD+AQAAAA==.Nephthys:BAAALgADCgQJBAAAAA==.',
Ni='Niallivdam:BAABLgAECn8wAAMjAAgJUxztAwBHAgAjAAgJUxztAwBHAgAWAAYJ0hfJEwCNAQAAAA==.Nights:BAAALgAECgIJAgABLgAFFAYJFAABABcWAA==.Nightsoul:BAAALgADCgEJAQAAAA==.Ninh:BAACLgAFFH8QAAIZAAMJkgObCABoAAAZAAMJkgObCABoAAAuAAQKf1UAAhkACQn6FOocADECABkACQn6FOocADECAAAA.',
No='Nomissius:BAAALgADCgcJDQAAAA==.Nooblè:BAAALgADCgMJAwAAAA==.Notsodemon:BAABLgAECn8eAAMMAAgJfxSHUwCLAQAMAAgJfxSHUwCLAQADAAIJnwrPYwBUAAAAAA==.Notsoevoker:BAAALgAECgMJAwABLgAECggJHgAMAH8UAA==.Notsomonk:BAAALgADCgMJAwABLgAECggJHgAMAH8UAA==.',
Ny='Nykara:BAAALgAECgUJBQAAAA==.',
['Nå']='Nåld:BAAALgAECgUJCwAAAA==.',
Oa='Oakendorf:BAAALgAECgEJAQABLgAECgEJAgATAAAAAA==.',
Ob='Obvinotagirl:BAAALgAECggJDwAAAA==.',
Od='Oddpocalypse:BAAALgAECgEJAgAAAA==.',
Og='Ogsikko:BAAALgAECgYJCwABLgAECggJGAAbAJAeAA==.Ogsikkotv:BAABLgAECn8YAAIOAAYJ/BmQhwDCAQAOAAYJ/BmQhwDCAQABLgAECggJGAAbAJAeAA==.',
Ok='Okathra:BAAALgAECgQJBAABLgAFFAMJCAAgAGgbAA==.',
On='Onebadmutha:BAABLgAECn8ZAAIbAAkJ+AwoVACgAQAbAAkJ+AwoVACgAQAAAA==.Ontop:BAABLgAECn8oAAIfAAkJ7xsaHABeAgAfAAkJ7xsaHABeAgAAAA==.',
Or='Orb:BAABLgAECn87AAQBAAkJfhvVAAAeAgABAAkJexvVAAAeAgAPAAgJexKrJwDNAQALAAYJlQ/EHgATAQAAAA==.Orcfreeza:BAAALgAECgQJDAAAAA==.Ortinks:BAABLgAECn8nAAIOAAgJrhFWaQCpAQAOAAgJrhFWaQCpAQAAAA==.',
Ow='Owneege:BAACLgAFFH8iAAIFAAgJByAAAgCJAgAFAAgJByAAAgCJAgAuAAQKfzMAAgUACQkEIx4CAKADAAUACQkEIx4CAKADAAAA.',
Pa='Painsaw:BAAALgADCgYJBgAAAA==.Pallinar:BAABLgAECn83AAIBAAkJGhUvPwAJAgABAAkJGhUvPwAJAgAAAA==.Pandamak:BAAALgAECgQJBQAAAA==.Pasquale:BAABLgAECn8hAAIhAAcJRSH8FAAFAgAhAAcJRSH8FAAFAgAAAA==.',
Pe='Pebbles:BAABLgAECn8jAAIBAAgJbxkuRAD5AQABAAgJbxkuRAD5AQAAAA==.Pedroia:BAABLgAECn8YAAQcAAgJ7wx5DABlAQAcAAgJ7wx5DABlAQARAAcJzgQBNgD9AAAlAAIJNAcBIABPAAAAAA==.Peridaxx:BAAALgAECgIJAgAAAA==.Pesty:BAAALgAECgMJCQAAAA==.',
Ph='Phe:BAABLgAECn8XAAMIAAcJhw4NPAAhAQAIAAcJhw4NPAAhAQAHAAYJpQvzcAADAQAAAA==.Pheraree:BAAALgAECgEJAQAAAA==.Phooboo:BAAALgAECgkJBQAAAA==.',
Pi='Pidion:BAAALgADCgYJDAAAAA==.Pilgrimm:BAECLgAFFH8gAAMlAAcJ9xvSAQC8AQAlAAYJ+RrSAQC8AQARAAYJQR7iAgADAQAuAAQKfyQAAxEACQl7IrIDAGADABEACQl0IrIDAGADACUABQkIHzgLAGcBAAAA.Pixyl:BAAALgAECgYJCAAAAA==.',
Pl='Plaguerott:BAABLgAECn83AAIaAAkJeA9TDgCQAQAaAAkJeA9TDgCQAQAAAA==.Plusultra:BAAALgADCgkJEQAAAA==.Pluto:BAAALgAFFAQJBAAAAA==.',
Po='Poby:BAAALgADCgcJBwAAAA==.Polydh:BAABLgAECn8wAAIoAAkJriT4AAA9AwAoAAkJriT4AAA9AwAAAA==.Poobah:BAABLgAECn8kAAMVAAkJYgaQWQDXAAAVAAgJHQaQWQDXAAAQAAcJCgMEigDHAAAAAA==.Popscotch:BAABLgAECn8jAAMnAAkJEg3OCQCkAQAnAAcJRg7OCQCkAQAbAAkJwAu4XQCGAQAAAA==.Pouffant:BAABLgAECn8iAAIBAAkJyBNjVwDFAQABAAkJyBNjVwDFAQAAAA==.',
Pr='Pronoz:BAABLgAECn8kAAIBAAcJfRJllABLAQABAAcJfRJllABLAQAAAA==.',
Pu='Punchy:BAAALgADCgEJAQAAAA==.',
Pw='Pwnageddon:BAABLgAECn82AAMLAAgJ2h6pCABLAgALAAcJkyKpCABLAgABAAUJhxUW4gDJAAAAAA==.Pwnjitsu:BAACLgAFFH8IAAIGAAMJ2R63FgALAQAGAAMJ2R63FgALAQAuAAQKfz4AAgYACQk8JT8CAEsDAAYACQk8JT8CAEsDAAAA.',
Py='Pyrothermia:BAACLgAFFH8WAAIOAAgJ7AyNIQD6AQAOAAgJ7AyNIQD6AQAuAAQKfyYAAg4ACQn/HIoqAMgCAA4ACQn/HIoqAMgCAAAA.',
['Pô']='Pôlgara:BAAALgADCgYJBgABLgAECgkJKwAPALoeAA==.',
Qt='Qtkillz:BAAALgADCgQJBAAAAA==.',
Qu='Quinlekd:BAAALgAECgQJBAABLgAECgkJMAAbAJ4iAA==.',
Ra='Rancayden:BAAALgAECgMJBAAAAA==.Rawhoof:BAACLgAFFH8QAAIFAAMJFSBsAwDoAAAFAAMJFSBsAwDoAAAuAAQKf1UAAgUACQlHJq4BAGMDAAUACQlHJq4BAGMDAAAA.Razak:BAACLgAFFH8IAAIgAAMJaBvPDAD0AAAgAAMJaBvPDAD0AAAuAAQKfzoAAiAACQniI1oBACsDACAACQniI1oBACsDAAAA.',
Re='Redlock:BAAALgAECgMJAwAAAA==.Redtiger:BAAALgADCgYJBgAAAA==.Renisa:BAABLgAECn8iAAIMAAgJqRkOUgCPAQAMAAgJqRkOUgCPAQAAAA==.Retman:BAABLgAECn8UAAIBAAcJtg+U8QDJAAABAAcJtg+U8QDJAAAAAA==.Reu:BAAALgAECgUJBwAAAA==.Revlyk:BAACLgAFFH8FAAIgAAMJORWWDgDXAAAgAAMJORWWDgDXAAAuAAQKfycAAiAACAkWI3oEAKgCACAACAkWI3oEAKgCAAEuAAUUBAkNAAMAChsA.Rezloh:BAAALgAECgkJDAAAAA==.',
Rh='Rhoanna:BAAALgADCgUJBwAAAA==.',
Ri='Rinja:BAAALgADCgYJBgAAAA==.Rintaro:BAABLgAECn8kAAILAAkJrAvSGwA4AQALAAkJrAvSGwA4AQAAAA==.Ritanana:BAAALgAECgIJAgAAAA==.',
Ro='Roccot:BAAALgAECggJDgAAAA==.Roflstomp:BAAALgAECgQJBwABLgAECgkJGQASAKofAA==.Roostrr:BAABLgAECn8XAAIBAAYJ4B2EcwCUAQABAAYJ4B2EcwCUAQAAAA==.Rotfather:BAAALgADCgYJBgAAAA==.Rotjaw:BAAALgAECgUJCwAAAA==.Roughedge:BAAALgADCgIJAgAAAA==.',
Ru='Rurik:BAAALgAECgEJAQAAAA==.',
['Rä']='Rävthor:BAAALgAFFAEJAQAAAA==.Rävthör:BAAALgAECgYJCwAAAA==.',
['Rè']='Rèjuva:BAAALgAECgcJDQAAAA==.Rèptílè:BAAALgADCgMJAwABLgAFFAMJBwAfAA8iAA==.',
['Rî']='Rîcflair:BAAALgAECgcJEwAAAA==.',
Sa='Saiyax:BAAALgADCgYJBwAAAA==.Salidfingers:BAAALgADCgYJBgAAAA==.Sanyakulak:BAAALgADCgcJBwABLgAFFAgJGwASABcWAA==.Sanzo:BAAALgAECgEJAQAAAA==.Savathûn:BAAALgAECgQJCAAAAA==.',
Sc='Scalycat:BAACLgAFFH8KAAMWAAMJJw/wIACgAAAWAAMJJw/wIACgAAAXAAMJjgEEVQB2AAAuAAQKfyoABBYACQnYDpwZAMEBABYACQnYDpwZAMEBABcABwksBsJnAKMAACMAAgluB/snAC0AAAAA.Schalla:BAAALgAECgEJAQAAAA==.Scum:BAAALgAECgYJDQAAAA==.Scòrpìòn:BAAALgADCgcJBgABLgAFFAMJBwAfAA8iAA==.',
Se='Seancody:BAAALgADCgIJAgAAAA==.Sekhmett:BAABLgAECn8gAAMOAAgJHAR6CACFAAAkAAYJ1gONDgCQAAAOAAgJ0AN6CACFAAAAAA==.Selandria:BAAALgADCgQJBAAAAA==.Senate:BAAALgAECgYJCwAAAA==.',
Sh='Shablaam:BAAALgADCgQJBAAAAA==.Shadowbear:BAABLgAECn8cAAIJAAcJ/RztHwDGAQAJAAcJ/RztHwDGAQAAAA==.Shadowoss:BAAALgAECgYJCAAAAA==.Shadygrump:BAAALgAECgYJEQAAAA==.Shamdeaus:BAAALgADCgUJBQABLgAECgkJLQAfALkYAA==.Shammacass:BAAALgAECgUJBQAAAA==.Shamwick:BAAALgAECgYJCgAAAA==.Shaolincito:BAAALgAECgQJCAAAAA==.Sherrilyn:BAAALgAECgUJBQAAAA==.Shocklocke:BAAALgAECgQJBAAAAA==.',
Si='Sigmachad:BAAALgAECgUJDwAAAA==.Silandrus:BAAALgAECgMJBAAAAA==.Silverocean:BAACLgAFFH8GAAIPAAMJgwrfAwCfAAAPAAMJgwrfAwCfAAAuAAQKfzMAAg8ACQkxHOoPAJQCAA8ACQkxHOoPAJQCAAAA.Silvia:BAAALgADCgUJCQAAAA==.Singularity:BAACLgAFFH8QAAINAAMJPCS2AQD2AAANAAMJPCS2AQD2AAAuAAQKf1IAAg0ACQltJpQAAHUDAA0ACQltJpQAAHUDAAAA.',
Sk='Skaerx:BAABLgAECn8WAAMFAAYJVBeOQwCXAQAFAAYJ9RWOQwCXAQAmAAQJZhSYHQADAQAAAA==.Skittlez:BAABLgAECn8mAAIYAAkJkR/TCQCBAgAYAAkJkR/TCQCBAgABLgAFFAMJBwAcAHAdAA==.',
Sl='Slaykween:BAABLgAECn8aAAILAAgJGwvYIAANAQALAAgJGwvYIAANAQAAAA==.Slootybooty:BAABLgAECn8ZAAISAAkJqh81BQC8AgASAAkJqh81BQC8AgAAAA==.',
Sm='Smallz:BAAALgAECgYJEQABLgAECggJHwAOALAIAA==.',
Sn='Snipersmash:BAAALgAECgQJCAAAAA==.Snooptrogg:BAABLgAECn8yAAIFAAkJKxZuIADtAQAFAAkJKxZuIADtAQAAAA==.Snoozumi:BAABLgAFFH8GAAIZAAMJKQZDSgB9AAAZAAMJKQZDSgB9AAAAAA==.Snuups:BAABLgAECn9DAAIbAAkJAhomLwAcAgAbAAkJAhomLwAcAgAAAA==.Snyper:BAAALgADCgQJBAAAAA==.',
So='Soldiah:BAABLgAECn8bAAIFAAgJrQ16OQBgAQAFAAgJrQ16OQBgAQAAAA==.Sommbra:BAAALgAECgYJBwAAAA==.Souljax:BAAALgADCgcJCQAAAA==.',
Sp='Spacelaser:BAAALgAECgQJBQAAAA==.',
Sq='Sqwurl:BAAALgADCgQJBAAAAA==.',
St='Steakhaus:BAAALgADCgkJCwAAAA==.Stiros:BAAALgAECgMJAwAAAA==.Stonedragon:BAECLgAFFH8SAAMfAAYJuxqZCwAGAQAfAAUJdiCZCwAGAQAKAAEJzwOMNgBGAAAuAAQKf0QAAx8ACQmGJMwFADEDAB8ACQmGJMwFADEDAAoACAkPIKsDAI4CAAAA.Stormfist:BAABLgAECn8ZAAIOAAkJ3BAOUADsAQAOAAkJ3BAOUADsAQAAAA==.Stormhaven:BAAALgADCggJKgABLgAECgkJKwAPALoeAA==.Stormrender:BAAALgAECgYJEAAAAA==.Stormriders:BAAALgADCgYJBgAAAA==.Stormstag:BAAALgADCgYJBgAAAA==.Stouty:BAAALgADCgMJAwABLgAECgcJFAAjAOkaAA==.',
Su='Sukonamí:BAABLgAECn8iAAMFAAkJghckKAAdAgAFAAgJdhUkKAAdAgAmAAQJGhs6KQAoAQAAAA==.Suxtosuck:BAAALgAECgkJBwAAAA==.Suzhou:BAABLgAECn8kAAIeAAkJGgnkFAAFAQAeAAkJGgnkFAAFAQAAAA==.Suzoomies:BAAALgADCgcJBwAAAA==.Suzumii:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetcarolin:BAABLgAECn8WAAICAAkJRg+GXgDXAQACAAkJRg+GXgDXAQAAAA==.Sweetsmercy:BAAALgAECgQJBQAAAA==.Swiftleaf:BAAALgADCgcJBwAAAA==.Swisscheese:BAABLgAECn8wAAIbAAkJniLWBwAZAwAbAAkJniLWBwAZAwAAAA==.',
Sy='Syraxa:BAAALgAECgQJBwABLgAFFAMJDgAHAEcRAA==.Syril:BAAALgADCgcJDAAAAA==.',
Ta='Taedish:BAAALgADCgMJAwAAAA==.Tahret:BAAALgADCgQJBgAAAA==.Talorien:BAAALgAECgYJBgABLgAFFAMJBwAOABIXAA==.Taquillya:BAAALgAECgQJBQAAAA==.Tarina:BAAALgADCgEJAQAAAA==.Tatersaladin:BAAALgADCgMJAwAAAA==.',
Te='Tenlortin:BAAALgAECgEJAQABLgAECgYJBwATAAAAAA==.Terragosa:BAABLgAECn83AAIOAAkJ5xncLQBiAgAOAAkJ5xncLQBiAgAAAA==.Teryail:BAAALgAECgEJAQAAAA==.Tetchybono:BAAALgADCgYJBgAAAA==.',
Th='Thade:BAABLgAECn8kAAMmAAkJByHUBQCpAgAmAAgJGiDUBQCpAgAFAAgJfB5XHwBWAgAAAA==.Thaeleon:BAABLgAECn8hAAMIAAgJbx97EgBCAgAIAAgJbx97EgBCAgAHAAYJixz+NADUAQABLgAFFAMJDQANAI8ZAA==.Thahawtz:BAAALgADCggJCAAAAA==.Thanattos:BAAALgAECgEJAQAAAA==.Thaneblade:BAAALgAECgQJBgAAAA==.Therizzler:BAAALgAECgcJCQABLgAFFAQJEgAMAMEUAA==.Thickening:BAABLgAECn8ZAAMZAAUJhQ1QagDYAAAZAAUJhQ1QagDYAAAGAAUJ9QfLYQCVAAAAAA==.Thirinis:BAAALgADCgYJBgAAAA==.Thope:BAABLgAECn8nAAIOAAcJTA0gpgAxAQAOAAcJTA0gpgAxAQAAAA==.Thoranubran:BAABLgAECn8aAAIDAAYJABJ5LwAKAQADAAYJABJ5LwAKAQAAAA==.Thrivia:BAAALgAECgYJBgAAAA==.',
Ti='Ticklemychin:BAAALgAECgcJDwAAAA==.Tigani:BAAALgAECgUJDAAAAA==.Tinstey:BAAALgADCgcJBwAAAA==.Titantu:BAAALgAECgcJCAABLgAFFAMJBgAIAHMFAA==.',
To='Toestiir:BAAALgAECgcJCgAAAA==.Tokemaddab:BAAALgADCgUJBQAAAA==.Tontoee:BAAALgAECgEJAQAAAA==.Toughasnails:BAAALgAECgEJAwAAAA==.',
Tr='Traesdyne:BAAALgAECgEJAQABLgAECgMJAwATAAAAAA==.Trainar:BAAALgAECgQJCQAAAA==.Trazle:BAAALgAECgMJAwAAAA==.Trekkiegeek:BAAALgAECgIJBAAAAA==.Trickybackup:BAAALgADCgMJAwAAAA==.Triggs:BAAALgAECgcJBwAAAA==.Trollbear:BAABLgAECn8WAAIHAAgJhBULKQAKAgAHAAgJhBULKQAKAgAAAA==.Trondruid:BAAALgADCgYJDQAAAA==.Trooze:BAABLgAECn87AAIPAAkJLiNiAwBrAwAPAAkJLiNiAwBrAwAAAA==.Trr:BAABLgAECn8pAAIbAAkJmBe2IwCFAgAbAAkJmBe2IwCFAgAAAA==.Truckz:BAAALgADCgEJAQABLgAECgkJSQAfAE0gAA==.Truckzage:BAAALgADCgcJBwABLgAECgkJSQAfAE0gAA==.',
Tu='Tuba:BAAALgAECgYJEAAAAA==.Turim:BAABLgAECn8UAAICAAgJGQcXpwAhAQACAAgJGQcXpwAhAQAAAA==.Tusksrus:BAAALgADCgcJFwAAAA==.',
Ty='Tyrlidd:BAABLgAECn84AAIfAAkJERbuLgAhAgAfAAkJERbuLgAhAgAAAA==.',
Ud='Udon:BAACLgAFFH8IAAMCAAUJmgvleQARAQACAAUJmgvleQARAQAaAAEJkQGgLQAyAAAuAAQKfyIAAwIABwkQGoVrAI4BAAIABgm4GoVrAI4BABoABQk6FogXABoBAAAA.',
Ug='Ugoar:BAAALgAECgcJBwAAAA==.',
Ul='Ultimazero:BAAALgADCgEJAQAAAA==.',
Un='Unavoidable:BAAALgADCgkJEQAAAA==.Unlikelytale:BAABLgAECn8mAAIQAAkJAyEuCgDXAgAQAAkJAyEuCgDXAgAAAA==.Unmilked:BAAALgAECgYJBwAAAA==.',
Ur='Uricash:BAACLgAFFH8GAAIOAAMJcBiXdgDuAAAOAAMJcBiXdgDuAAAuAAQKf1AAAg4ACQmWIIwRAPECAA4ACQmWIIwRAPECAAAA.Urzual:BAABLgAECn8sAAIgAAkJDyD2BQB+AgAgAAkJDyD2BQB+AgAAAA==.',
Ut='Utiniócast:BAAALgAECgQJBAAAAA==.',
Va='Vandreynna:BAACLgAFFH8NAAIDAAQJChtzDABIAQADAAQJChtzDABIAQAuAAQKf1MAAgMACQnWJVUBAGkDAAMACQnWJVUBAGkDAAAA.',
Ve='Vegèta:BAABLgAECn8gAAICAAkJZAsIgwBdAQACAAkJZAsIgwBdAQABLgAFFAMJBwAfAA8iAA==.Veilaura:BAAALgAECggJDQAAAA==.Velarria:BAABLgAECn8lAAMfAAkJUh83FQCOAgAfAAkJUh83FQCOAgAYAAUJHw3CRACtAAAAAA==.Velikan:BAAALgAECgQJBwABLgAECgcJCAATAAAAAA==.Velsiana:BAABLgAECn8UAAMeAAgJwhHtFQD5AAAbAAgJHw5lfQA+AQAeAAQJ4xXtFQD5AAAAAA==.Velveetah:BAAALgAECgUJCAABLgAECgYJGQAEAJ4PAA==.Verbrennen:BAAALgAECgUJDgABLgAECgkJUAAFABYhAA==.Verdreht:BAAALgADCgEJAQABLgAECgkJUAAFABYhAA==.Verita:BAABLgAECn8zAAIlAAgJXiMcAgCxAgAlAAgJXiMcAgCxAgAAAA==.Verlynne:BAAALgADCgYJBgAAAA==.Verylikely:BAAALgAECgEJAgAAAA==.',
Vi='Viviann:BAABLgAECn8kAAIWAAkJeRFuEADFAQAWAAkJeRFuEADFAQAAAA==.',
Vo='Voiager:BAAALgADCgcJCgAAAA==.',
Vr='Vrakal:BAAALgAECgkJDQAAAA==.',
Wa='Wantabehavoc:BAAALgADCgYJDQAAAA==.Wantadeznutz:BAAALgAECgIJAgAAAA==.Warnick:BAAALgADCgQJBQAAAA==.Warraxe:BAAALgAECgEJAgAAAA==.Wayloren:BAABLgAECn8xAAIBAAkJ9gzVdACEAQABAAkJ9gzVdACEAQAAAA==.Waystalker:BAAALgAECgMJAwAAAA==.Wayverly:BAAALgADCgUJBwABLgAECgkJIAAKAMoIAA==.',
Wi='Wickathy:BAABLgAECn9PAAMoAAkJFiEhAABwAgAoAAkJFiEhAABwAgAMAAMJlg/txACkAAAAAA==.Withering:BAAALgAECgMJAwAAAA==.',
Wo='Wolfcity:BAAALgADCgEJAQAAAA==.Wondertauren:BAAALgADCgYJCQAAAA==.Woodson:BAAALgADCgkJEAAAAA==.Worstdps:BAAALgAFFAIJAwAAAA==.',
Wr='Wrkandtank:BAAALgAECgYJBgABLgAECggJFQAbAHcLAA==.',
Wu='Wuldorr:BAACLgAFFH8QAAIBAAQJexftQgAlAQABAAQJexftQgAlAQAuAAQKfyQAAgEACAm1H0gkAJYCAAEACAm1H0gkAJYCAAAA.',
Wy='Wynnifred:BAAALgAECggJDQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.',
Xe='Xethreal:BAAALgADCgMJAwAAAA==.',
Xy='Xype:BAAALgAECgkJEQAAAA==.',
Xz='Xzara:BAAALgAECgYJDgABLgAECgYJGQAOAIQbAA==.',
Ya='Yastoria:BAAALgAECgcJEAAAAA==.',
Yi='Yinandtonic:BAAALgAECgEJBAAAAA==.',
Yv='Yvvee:BAAALgADCgcJBwAAAA==.',
Za='Zaalim:BAAALgADCgQJBAAAAA==.Zaddy:BAAALgAECgEJAQAAAA==.Zapdôs:BAAALgAECgQJBAAAAA==.Zasko:BAAALgAECgEJAQAAAA==.',
Ze='Zeda:BAAALgAECgYJEwABLgAECgYJGQAOAIQbAA==.Zephyris:BAAALgAECgUJDAABLgAFFAgJJQAmAGMhAA==.',
Zh='Zheng:BAAALgAECgYJBgAAAA==.',
Zi='Zillia:BAAALgADCgMJAwAAAA==.',
Zo='Zonora:BAABLgAECn8YAAIPAAkJlQ1eKADJAQAPAAkJlQ1eKADJAQAAAA==.',
Zy='Zyphexd:BAAALgAECgYJDwAAAA==.Zyris:BAAALgADCgcJDQAAAA==.',
['Àz']='Àzñós:BAAALgAECgQJBwAAAA==.',
['Äs']='Ästro:BAAALgAECgQJBgABLgAECgkJLQAGAHcaAA==.',
['Äz']='Äzrael:BAABLgAECn83AAIEAAkJUxxDCQDUAgAEAAkJUxxDCQDUAgAAAA==.',
['Åz']='Åznos:BAAALgAECgQJCAAAAA==.',
['Çr']='Çréwüsæðèr:BAABLgAECn8kAAINAAkJ2R5ACwA5AgANAAkJ2R5ACwA5AgAAAA==.',
['Ðe']='Ðecimus:BAAALgAECgQJCQAAAA==.',
['Ðì']='Ðìaßlo:BAACLgAFFH8HAAIfAAMJDyLcWgDvAAAfAAMJDyLcWgDvAAAuAAQKfzQABB8ACQljHQAdAHcCAB8ACAljHQAdAHcCABgABwlYFAQRALMBAAoAAQleABqbABUAAAAA.',
['Öb']='Öblïvïöñ:BAAALgAECgEJAwAAAA==.',
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
