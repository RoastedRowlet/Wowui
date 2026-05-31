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

local lookup = {'Paladin-Retribution','DemonHunter-Havoc','Priest-Holy','Warrior-Fury','Monk-Windwalker','Druid-Restoration','Druid-Balance','Priest-Shadow','Hunter-Marksmanship','DemonHunter-Devourer','Paladin-Protection','Warrior-Protection','Mage-Frost','Paladin-Holy','Shaman-Restoration','Rogue-Subtlety','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Elemental','Evoker-Augmentation','Hunter-Survival','Monk-Mistweaver','Warlock-Demonology','Priest-Discipline','Warlock-Destruction','Hunter-BeastMastery','Shaman-Enhancement','Monk-Brewmaster','Druid-Feral','Druid-Guardian','Evoker-Devastation','Mage-Arcane','Rogue-Outlaw','Warrior-Arms','Warlock-Affliction','Rogue-Assassination','DemonHunter-Vengeance','Evoker-Preservation','DeathKnight-Frost',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Aberaht:BAABLgAECn8mAAIBAAkJYCOqDQAgAwABAAkJYCOqDQAgAwAAAA==.',
Ad='Adamaro:BAAALgADCgYJCQAAAA==.',
Ae='Aenastian:BAAALgAECgUJCQABLgAFFAQJCwACAAobAA==.',
Af='Affrica:BAAALgADCgEJAQABLgAECgYJGQADAJ4PAA==.',
Ag='Agnu:BAAALgADCgcJBwAAAA==.',
Ah='Ahgra:BAABLgAECn80AAIBAAgJ+QormwAkAQABAAgJ+QormwAkAQAAAA==.',
Ak='Akre:BAAALgAFFAIJBgAAAQ==.Akumä:BAAALgAECgUJCgAAAA==.',
Al='Aleannia:BAAALgAECgUJBQAAAA==.Alekz:BAAALgAECgYJCgAAAA==.Alestria:BAABLgAECn8WAAIBAAcJEBUCgwBOAQABAAcJEBUCgwBOAQAAAA==.Alibrexia:BAABLgAECn8gAAIEAAkJawmWLwB8AQAEAAkJawmWLwB8AQAAAA==.Alida:BAABLgAECn8sAAIEAAkJqAppMQByAQAEAAkJqAppMQByAQAAAA==.Alithvia:BAAALgAECgYJBgABLgAECgkJJQAFAAskAA==.Allisara:BAAALgADCgkJFgAAAA==.Alysae:BAACLgAFFH8eAAMGAAYJYhuKDAD9AQAGAAYJYhuKDAD9AQAHAAEJSQBsSQAZAAAuAAQKfxsAAwYACAkrHeUdAE8CAAYACAkrHeUdAE8CAAcAAgllB02IACkAAAAA.',
Am='Amabear:BAAALgAECgEJAQABLgAECgcJHAAIAP0cAA==.Ambrosse:BAAALgADCggJDwABLgAECgkJLQAFAHcaAA==.',
An='Anabug:BAAALgAECgMJBQAAAA==.Andelwynn:BAAALgAECgIJAgABLgAECggJHQAJAEAJAA==.Angelsmentor:BAAALgAECgYJCQAAAA==.Aniellas:BAAALgAECgIJAgAAAA==.Annalese:BAAALgADCgUJCQABLgAECggJHQAJAEAJAA==.',
Ar='Arabeli:BAAALgAECgEJAQAAAA==.Arbyss:BAAALgADCgcJDAAAAA==.Ardatha:BAAALgADCgcJFwAAAA==.Artio:BAAALgADCgkJDQAAAA==.',
As='Asterön:BAAALgAECgcJEgAAAA==.Astrocakes:BAAALgAECgMJAwABLgAFFAMJCwAKAP8UAA==.',
At='Athenä:BAACLgAFFH8dAAILAAcJwA9AAgCFAQALAAcJwA9AAgCFAQAuAAQKfzwAAgsACQl7HPkFAI4CAAsACQl7HPkFAI4CAAAA.Atsuma:BAABLgAECn8gAAIMAAgJIAsrIAAXAQAMAAgJIAsrIAAXAQAAAA==.',
Av='Avacynn:BAAALgAECgMJAwAAAA==.Aviz:BAAALgADCgMJAwAAAA==.',
Aw='Awtysmbb:BAAALgAECgIJBAABLgAECgkJKgANAEoZAA==.',
['Aí']='Aísling:BAABLgAECn8pAAIOAAgJ6x6BDACzAgAOAAgJ6x6BDACzAgAAAA==.',
Ba='Baboii:BAAALgADCgIJAgAAAA==.Baconmecrazy:BAAALgAECgEJAQAAAA==.Badinngo:BAAALgADCggJDwABLgAECgkJJAAPABcgAA==.Bahiu:BAAALgAECgQJBAAAAA==.Bajafresh:BAAALgAECgQJBQAAAA==.Battleshaman:BAAALgADCgYJBgAAAA==.',
Bd='Bd:BAABLgAECn8dAAIQAAgJJxU5GABGAgAQAAgJJxU5GABGAgAAAA==.',
Be='Beardmedaddy:BAAALgAECgYJBgABLgAECgkJLwAEAI4hAA==.Bearstavious:BAAALgAECgkJBAAAAA==.Benjinana:BAABLgAECn8ZAAMDAAYJng9pNgAPAQADAAYJng9pNgAPAQAIAAIJJQPOWgBMAAAAAA==.Betterthanu:BAAALgADCgUJBQABLgADCgYJCgARAAAAAA==.',
Bg='Bg:BAAALgAECgYJBwAAAA==.',
Bi='Bige:BAAALgAECgYJDgAAAA==.Bilo:BAAALgAECgYJCAAAAA==.Bitelyus:BAAALgAECgUJCAAAAA==.',
Bl='Blazara:BAAALgADCgcJBwAAAA==.',
Bo='Bobius:BAAALgAECgkJDwAAAA==.Bobohizan:BAAALgADCgQJBAAAAA==.Bohde:BAABLgAFFH8OAAMSAAUJ6iJgMgBxAQASAAQJ6iJgMgBxAQATAAEJAACkQwAAAAAAAA==.Bolognaman:BAAALgAECgUJCAAAAA==.Bombjovi:BAABLgAECn8gAAMLAAkJchVzDADjAQALAAkJchVzDADjAQAOAAUJlA/WTQDrAAAAAA==.Bountty:BAAALgAECgQJBAAAAA==.',
Br='Brahmsthoven:BAAALgADCgIJAwAAAA==.Branndhon:BAABLgAECn8lAAIGAAcJdBV9NAC2AQAGAAcJdBV9NAC2AQAAAA==.',
Bt='Btrflyprncss:BAAALgADCgMJAwAAAA==.',
Bu='Bubblemedic:BAAALgADCgIJAgAAAA==.Budde:BAAALgAECgUJBQAAAA==.Buffaloseven:BAAALgAECgYJCQABLgAFFAcJEQANADYOAA==.',
Ca='Cairdamane:BAABLgAECn8hAAIUAAkJ5BEKKgCHAQAUAAkJ5BEKKgCHAQAAAA==.Calidrina:BAABLgAECn8hAAIKAAkJMhwmQACxAQAKAAkJMhwmQACxAQAAAA==.Carm:BAAALgAECgYJBgAAAA==.Caroliná:BAAALgAECgMJBgAAAA==.Catcast:BAAALgAECgUJCAABLgAFFAMJBgAVAKQBAA==.Catclaw:BAAALgAECgEJAQABLgAFFAMJBgAVAKQBAA==.',
Ce='Celiri:BAABLgAECn8nAAIFAAkJrxCeHACxAQAFAAkJrxCeHACxAQAAAA==.Celldrassil:BAABLgAECn8vAAIGAAgJZQfNYAABAQAGAAgJZQfNYAABAQAAAA==.Cereel:BAAALgAECgMJAwABLgAFFAMJCwAKAP8UAA==.',
Ch='Chadaracka:BAAALgAECgYJBwAAAA==.Chandelure:BAAALgAECgUJCwAAAA==.Chardaney:BAABLgAECn8dAAIJAAgJQAldEgAgAQAJAAgJQAldEgAgAQAAAA==.Cherryontop:BAABLgAECn8kAAIGAAgJMhIXNAC4AQAGAAgJMhIXNAC4AQAAAA==.Chozenone:BAAALgAECgUJDgAAAA==.Chozi:BAAALgAECgYJBgAAAA==.Chromosomie:BAAALgAFFAEJAQABLgAECgkJMAANAOcbAA==.',
Ci='Cii:BAABLgAECn8VAAMLAAgJWRCZFQBeAQALAAgJ0Q6ZFQBeAQABAAUJew2vygDcAAAAAA==.',
Co='Coconutwater:BAAALgAFFAEJAQAAAA==.Colandros:BAABLgAECn8yAAIWAAgJKgxyIACLAQAWAAgJKgxyIACLAQAAAA==.Colara:BAABLgAECn8aAAIKAAcJSwQtrACtAAAKAAcJSwQtrACtAAAAAA==.Combobreaker:BAACLgAFFH8IAAIXAAMJVx4WIgAJAQAXAAMJVx4WIgAJAQAuAAQKfzQAAhcACQm+H5UGABwDABcACQm+H5UGABwDAAAA.Comoo:BAAALgADCgIJBQAAAA==.Correct:BAAALgAECgEJAQAAAA==.Cowbôy:BAAALgADCgkJEQAAAA==.',
Cr='Crassberry:BAACLgAFFH8aAAISAAcJEx/eDwAOAgASAAcJEx/eDwAOAgAuAAQKfygAAhIACQk2JBQFAIMDABIACQk2JBQFAIMDAAAA.Crazyraptor:BAAALgAECgYJDAABLgAECggJFQAYAHcLAA==.Crazèd:BAAALgADCgQJBAAAAA==.',
Cu='Cutco:BAAALgAFFAEJAQAAAA==.',
Cy='Cyndal:BAAALgAECgQJEAABLgAECgYJEgARAAAAAA==.Cyndle:BAAALgAECgYJEgAAAA==.Cyntu:BAAALgAECgUJCgABLgAECgYJEgARAAAAAA==.',
['Cü']='Cüpid:BAAALgAECgYJBgAAAA==.',
Da='Dada:BAAALgAECgEJAQAAAA==.Dammithells:BAAALgADCgQJBAAAAA==.Dandamar:BAAALgAECgYJBgAAAA==.Dankfists:BAAALgAECgUJBQABLgAFFAIJAgARAAAAAA==.Dankhaze:BAAALgAFFAIJAgAAAA==.Dankzor:BAAALgAECgcJBQABLgAFFAIJAgARAAAAAA==.Dark:BAAALgADCgEJAQAAAA==.Darthrevan:BAAALgAECgQJBwAAAA==.Dasharnkal:BAAALgADCgUJCAAAAA==.Dasvult:BAAALgAECgMJBAAAAA==.Dazex:BAABLgAECn8eAAMDAAYJNQOOSACqAAADAAYJ6AKOSACqAAAZAAUJRwILUwCBAAAAAA==.',
De='Deadpump:BAABLgAECn8fAAMYAAcJfRIKbQBWAQAYAAcJfRIKbQBWAQAaAAQJUQ4aOQDQAAAAAA==.Demonsnotkey:BAAALgAECgYJCwAAAA==.Demoxus:BAAALgAECgQJBAAAAA==.Denker:BAAALgADCggJCAAAAA==.Denkzilla:BAAALgADCgIJAgAAAA==.Denzvic:BAAALgAECgEJAQAAAA==.Destro:BAAALgAECgEJAQAAAA==.Deusclaw:BAAALgAECgYJCgAAAA==.Devilah:BAAALgAECgEJAQAAAA==.',
Dh='Dharm:BAABLgAECn8rAAMbAAcJvRomUACZAQAbAAcJvRomUACZAQAWAAIJxQzhSQBzAAAAAA==.',
Di='Dialsl:BAAALgADCgUJBgAAAA==.Digbickpanda:BAAALgADCgYJBgABLgAFFAMJCwAKAP8UAA==.Disowneege:BAABLgAECn8fAAIBAAgJ0B8sHwB1AgABAAgJ0B8sHwB1AgABLgAFFAcJGAAEAGEjAA==.Diyos:BAAALgADCgYJCgAAAA==.',
Do='Dotndash:BAAALgADCgIJAgAAAA==.Doubledge:BAAALgAECgEJAQAAAA==.Doublejump:BAACLgAFFH8TAAIKAAQJvRI2OgAcAQAKAAQJvRI2OgAcAQAuAAQKfykAAgoACAk4Hk4iADMCAAoACAk4Hk4iADMCAAAA.',
Dr='Dragdh:BAAALgAECgcJEwABLgAECggJKQAcAJ8cAA==.Dragnas:BAABLgAECn8pAAQcAAgJnxyXCgDzAQAcAAgJnxyXCgDzAQAPAAcJrBQwNwC4AQAUAAQJvhazVADLAAAAAA==.Dragonisa:BAAALgAFFAEJAQAAAA==.Dragun:BAAALgADCgIJAgAAAA==.Draiocht:BAAALgADCgMJAwABLgAECgkJMAADAEEbAA==.Drakeskid:BAAALgAECgQJBwABLgAFFAQJBgAdALgKAA==.Drakthall:BAAALgAECgIJAwAAAA==.Dralionethny:BAAALgAECgIJAgAAAA==.Dramakiller:BAAALgAECgUJDQAAAA==.Drchi:BAAALgAECgEJAQABLgAECgYJGQAeAIcVAA==.Drcornbread:BAABLgAECn8ZAAMeAAYJhxX8FgA2AQAeAAYJhxX8FgA2AQAfAAEJ0AOicwATAAAAAA==.Drcornellia:BAAALgAECgUJCAABLgAECgYJGQAeAIcVAA==.Drdarkskin:BAAALgAECgcJDQAAAA==.Drdreggs:BAABLgAECn8pAAMaAAkJmBYoDwAzAQAYAAgJuBSYTwDZAQAaAAYJmxcoDwAzAQAAAA==.Dreggs:BAAALgADCgcJEwAAAA==.Drizztin:BAAALgADCgEJAQAAAA==.Drprominus:BAABLgAECn8gAAIOAAgJACI/CADzAgAOAAgJACI/CADzAgAAAA==.Drthargyll:BAAALgADCgYJDgABLgAECggJIAAOAAAiAA==.',
Dy='Dykdanglr:BAAALgADCgYJBgABLgAECgQJCAARAAAAAA==.',
['Dí']='Dígifóx:BAAALgADCgMJBAAAAA==.Dígífóx:BAAALgAFFAEJAQAAAA==.',
Ea='Earthereal:BAABLgAECn8yAAIXAAgJpxcJGQAqAgAXAAgJpxcJGQAqAgAAAA==.',
El='Elastar:BAABLgAECn8mAAIMAAkJ6RYKDgApAgAMAAkJ6RYKDgApAgAAAA==.Ellimist:BAECLgAFFH8aAAIPAAYJDBr9BwAOAgAPAAYJDBr9BwAOAgAuAAQKfykAAw8ACQl9G3QXAFoCAA8ACQl9G3QXAFoCABQABQk0FxdQAAcBAAAA.Elsan:BAAALgAECgEJAQAAAA==.Elycee:BAACLgAFFH8HAAIbAAMJyyWOMgAwAQAbAAMJyyWOMgAwAQAuAAQKfyIAAxsACQmtJZkGABsDABsACAk+JpkGABsDAAkACAmWGZYgACECAAAA.Elysria:BAAALgADCgYJBgAAAA==.Elí:BAAALgAECgQJBAAAAA==.',
En='Encrid:BAAALgAECgcJDwABLgAFFAMJBwAVANEYAA==.Enhasa:BAABLgAECn8eAAISAAkJ/hWmKgBCAgASAAkJ/hWmKgBCAgABLgAECgYJGgABAOggAA==.Enoeht:BAABLgAECn8zAAICAAgJTgv6IgA8AQACAAgJTgv6IgA8AQAAAA==.Enveliria:BAAALgAECgEJAQABLgAFFAQJCwACAAobAA==.',
Er='Eraser:BAAALgAECgYJBgAAAA==.Erazar:BAABLgAECn80AAIgAAgJ4BIQCAChAQAgAAgJ4BIQCAChAQAAAA==.Eriah:BAAALgADCgkJCQAAAA==.Erickk:BAABLgAECn8wAAMNAAkJ5xu8OgAXAgANAAkJnBq8OgAXAgAhAAQJVx1SCwAkAQAAAA==.',
Es='Essense:BAABLgAECn8mAAIDAAkJmyRIAwApAwADAAkJmyRIAwApAwAAAA==.',
Ex='Exodari:BAABLgAECn87AAIcAAkJ7hg9CQASAgAcAAkJ7hg9CQASAgAAAA==.',
Fa='Fabbioh:BAAALgADCgEJAQAAAA==.Fadeddh:BAACLgAFFH8LAAIKAAMJ/xQCUADaAAAKAAMJ/xQCUADaAAAuAAQKfzAAAgoACQn/Gx0fAEUCAAoACQn/Gx0fAEUCAAAA.Faizarah:BAAALgAECgYJBgAAAA==.Faydien:BAAALgAECgEJAQAAAA==.',
Fe='Fearnoevil:BAAALgADCgMJAwAAAA==.Fel:BAABLgAECn8RAAIKAAgJjRrrVQBsAQAKAAgJjRrrVQBsAQAAAA==.Fellkarras:BAAALgAECgYJDwABLgAFFAMJCAAXAFceAA==.Fent:BAABLgAECn8VAAIYAAgJdwuuZwBjAQAYAAgJdwuuZwBjAQAAAA==.',
Fi='Fiddich:BAAALgAECgYJBgAAAA==.Fillthy:BAACLgAFFH8TAAIXAAcJzxM+DQDlAQAXAAcJzxM+DQDlAQAuAAQKfy4AAxcACQlYIkYDAEcDABcACQlYIkYDAEcDAAUAAwkhCfxoAGYAAAAA.Finnigann:BAAALgAECgYJCwAAAA==.Firenmylazer:BAAALgADCgMJAwAAAA==.Fistav:BAAALgADCgcJDgAAAA==.Fizban:BAABLgAECn8eAAINAAgJsAgHlgAyAQANAAgJsAgHlgAyAQAAAA==.',
Fl='Flappybird:BAAALgAECgYJCAABLgAFFAMJCwAKAP8UAA==.Flasan:BAAALgADCgEJAQAAAA==.Flazz:BAAALgADCgIJAwAAAA==.Flazzan:BAAALgADCgEJAQAAAA==.',
Fo='Fogbringer:BAAALgAECgIJAwAAAA==.Four:BAAALgADCgQJBAAAAA==.',
Fr='Frejä:BAAALgAECgQJBQABLgAECgQJDAARAAAAAA==.Freyah:BAAALgAECgUJEgAAAA==.Frostmay:BAAALgAECgIJAgAAAA==.',
Fu='Furrybawlz:BAAALgAECgUJCgABLgAECgYJDQARAAAAAA==.',
Ga='Gabran:BAAALgAECgUJBQAAAA==.Gadogear:BAABLgAECn8lAAINAAgJNBieTgDYAQANAAgJNBieTgDYAQAAAA==.Galahan:BAAALgAECgMJAwAAAA==.Garlick:BAAALgADCggJDwABLgAECggJNAAgAOASAA==.Garlik:BAAALgADCgMJBAAAAA==.',
Ge='Gertra:BAAALgAECgEJAgAAAA==.',
Gf='Gfr:BAAALgAECggJEAAAAA==.',
Gi='Girthrichard:BAAALgAECgYJDAAAAA==.',
Gl='Glassdragon:BAABLgAECn8mAAIBAAkJUQwWeQBhAQABAAkJUQwWeQBhAQAAAA==.Gllor:BAAALgADCgIJAgAAAA==.',
Go='Goatcheeze:BAABLgAECn8cAAIhAAkJLhV+AwDSAQAhAAkJLhV+AwDSAQAAAA==.Goatylocks:BAABLgAECn8rAAMaAAkJ7RWHCwBqAQAYAAgJvRC0TACpAQAaAAYJLByHCwBqAQAAAA==.Gohlemsaurus:BAAALgADCgYJBgAAAA==.Goldenchild:BAAALgAFFAIJAgABLgAFFAMJCwAKAP8UAA==.',
Gr='Greatluckydo:BAAALgADCgEJAQAAAA==.Grozlek:BAAALgADCgYJBgAAAA==.',
Gu='Gulen:BAABLgAECn8WAAIPAAYJpSEkHwA7AgAPAAYJpSEkHwA7AgAAAA==.',
Gw='Gwendyla:BAAALgADCgkJFgAAAA==.',
Gy='Gyousei:BAAALgAECgEJAQAAAA==.',
['Gí']='Gíga:BAABLgAECn8XAAIbAAgJ7RPdKQAPAgAbAAgJ7RPdKQAPAgAAAA==.',
Ha='Hafnium:BAAALgAECgIJAgAAAA==.Hamish:BAAALgAECgUJCAAAAA==.Hanhaine:BAABLgAECn8nAAIHAAkJ8hV7EgAuAgAHAAkJ8hV7EgAuAgAAAA==.Hazirat:BAAALgAECgYJCgAAAA==.',
He='Hedlie:BAAALgAECggJCwAAAA==.Hellenkeller:BAECLgAFFH8HAAIXAAYJhw+GFwBqAQAXAAYJhw+GFwBqAQAuAAQKfx8AAhcABwkzITQTADMCABcABwkzITQTADMCAAEuAAUUBgkVACIACRwA.Heloisa:BAAALgAECgYJDwAAAA==.Helrazr:BAAALgAFFAEJAgAAAA==.Henshin:BAACLgAFFH8IAAIGAAMJiA5UOQC5AAAGAAMJiA5UOQC5AAAuAAQKf0QAAwYACQmxHckOAM8CAAYACQmxHckOAM8CAAcAAgk4Dpl9ADUAAAAA.',
Hi='Hitt:BAAALgAECgcJCAAAAA==.',
Ho='Holyhim:BAAALgADCgIJAgAAAA==.Holyshawk:BAAALgAECgEJAgAAAA==.Holysudz:BAAALgADCgYJBgAAAA==.Hottyshmotty:BAAALgAECgEJAQAAAA==.Hourglass:BAABLgAECn89AAMbAAkJSBnZIQBHAgAbAAkJSBnZIQBHAgAJAAQJ1g3oXwDBAAAAAA==.',
Hr='Hroc:BAAALgAECgUJCwAAAA==.',
Hu='Hunterviral:BAAALgADCgEJAQAAAA==.Huntthejuan:BAAALgADCgUJBQAAAA==.',
Ic='Icyowneege:BAAALgADCgUJBQABLgAFFAcJGAAEAGEjAA==.Icywolfy:BAAALgAECgYJCAAAAA==.',
Ig='Igreetyou:BAABLgAECn8gAAIYAAcJnRw/LwAPAgAYAAcJnRw/LwAPAgAAAA==.',
Il='Illie:BAABLgAECn8mAAIcAAkJShyHBQCtAgAcAAkJShyHBQCtAgAAAA==.Illune:BAABLgAECn8qAAMNAAkJShmWNAAuAgANAAkJShmWNAAuAgAhAAYJUg4ZCQBbAQAAAA==.',
Im='Imanbearpig:BAAALgADCgIJAgAAAA==.Imleapingit:BAABLgAECn8vAAIEAAkJjiElBQD+AgAEAAkJjiElBQD+AgAAAA==.',
In='Intoodeep:BAAALgAECggJCAAAAA==.Intoodragons:BAACLgAFFH8KAAIVAAMJ/AXjPwCmAAAVAAMJ/AXjPwCmAAAuAAQKfzYAAxUACQmcFGkZAPIBABUACQmcFGkZAPIBACAABglaBfokAP4AAAAA.Inyah:BAAALgAECgIJAgAAAA==.',
Io='Ionzz:BAABLgAECn8ZAAICAAkJrx+iCADYAgACAAkJrx+iCADYAgAAAA==.',
Ir='Ir:BAAALgAECgcJBwAAAA==.Iroann:BAAALgAECgYJEQAAAA==.',
Is='Isawarriorr:BAACLgAFFH8FAAIMAAMJJR3eEQD+AAAMAAMJJR3eEQD+AAAuAAQKfywAAgwACQmCI4kDAB8DAAwACQmCI4kDAB8DAAAA.Ishaq:BAAALgAECgQJBQABLgAECggJHgAdACsFAA==.Ishdo:BAAALgADCgMJAwABLgAECggJHgAdACsFAA==.Ishdu:BAAALgAECgQJBAABLgAECggJHgAdACsFAA==.Ishkhan:BAABLgAECn8eAAMdAAgJKwXVPQDyAAAdAAgJrQTVPQDyAAAFAAYJUQWWVACiAAAAAA==.Ishmael:BAACLgAFFH8GAAMMAAMJ+BUDGADBAAAMAAMJ+BUDGADBAAAEAAEJiw2yRgBGAAAuAAQKfxQAAwQACQk6HhcTAEcCAAQACQkwHBcTAEcCAAwAAglmG901AIgAAAAA.Ishwar:BAAALgADCgYJBgAAAA==.',
Ja='Jakytreehorn:BAACLgAFFH8JAAMPAAYJnQTTOwDYAAAPAAUJ5QPTOwDYAAAUAAMJlgTRPgBrAAAuAAQKfywAAw8ACQlCFQwoAPABAA8ACQlCFQwoAPABABQABwmAEq4wAGIBAAAA.Jasher:BAAALgAECgYJBgAAAA==.Jaydm:BAABLgAECn8ZAAIjAAYJ4RRyIwAwAQAjAAYJ4RRyIwAwAQABLgAFFAcJEQANADYOAA==.',
Je='Jenevelle:BAAALgAECgUJBgAAAA==.Jerisil:BAAALgADCgQJBAAAAA==.Jet:BAABLgAECn8aAAIBAAYJ6CAySwABAgABAAYJ6CAySwABAgAAAA==.',
Ji='Jibbajabba:BAAALgADCgcJBwAAAA==.Jimbo:BAABLgAFFH8GAAIYAAIJ+B1JeQC1AAAYAAIJ+B1JeQC1AAABLgAFFAcJGgASABMfAA==.',
Ju='Judgecalypso:BAAALgAECgQJBgAAAA==.Judgiah:BAAALgAECgUJBQAAAA==.Julthaenia:BAABLgAECn8gAAQkAAcJ/h5hBQAUAgAkAAcJ/h5hBQAUAgAYAAUJcQvb4gB/AAAaAAQJGAqRLgBRAAABLgAFFAQJCwACAAobAA==.Justeatjuan:BAAALgAECgMJAwAAAA==.',
Ka='Kagebushin:BAAALgAECgMJBAAAAA==.Kalazin:BAAALgAECgUJBQAAAA==.Kalimah:BAAALgADCgMJAwAAAA==.Kalofelement:BAAALgADCgUJBQAAAA==.Karmaisab:BAAALgADCgEJAQAAAA==.Karnrae:BAABLgAECn8pAAIBAAkJKxJ/RwDYAQABAAkJKxJ/RwDYAQAAAA==.Karynos:BAABLgAECn8kAAMYAAkJeAqiVwCKAQAYAAkJSgmiVwCKAQAaAAcJyQkOIwA/AQAAAA==.Katnelly:BAAALgAECgMJAwAAAA==.Kazmacoryy:BAAALgAECgYJEAAAAA==.',
Ke='Keedis:BAAALgADCggJCwAAAA==.Keristrasza:BAAALgAFFAEJAQABLgAFFAcJIwAPAEUbAA==.',
Ki='Kileely:BAAALgAECgMJAwAAAA==.Kirintore:BAAALgAECgUJCQAAAA==.',
Kk='Kkaiser:BAAALgADCgcJCwAAAA==.',
Kl='Klaudeus:BAAALgAECgEJAQAAAA==.',
Ko='Kodian:BAAALgADCgEJAQAAAA==.Kolypso:BAABLgAECn8XAAIbAAgJOxVFOwDbAQAbAAgJOxVFOwDbAQAAAA==.Konceal:BAAALgAECgEJAQAAAA==.Konspiracy:BAABLgAECn8pAAIaAAkJpxaJBQD7AQAaAAkJpxaJBQD7AQAAAA==.Konvict:BAAALgAECgIJAwABLgAECgYJDQARAAAAAA==.',
Kr='Krataar:BAABLgAECn8hAAIEAAkJEyFFCgCsAgAEAAkJEyFFCgCsAgAAAA==.Kravvan:BAAALgAECgQJCQABLgAECggJHgANALAIAA==.Krousvor:BAAALgAECgQJBwAAAA==.Kryph:BAABLgAECn8dAAISAAkJQAgMbQB3AQASAAkJQAgMbQB3AQAAAA==.',
Ku='Kugruk:BAAALgAECgcJDAAAAA==.Kurjo:BAAALgAECgMJBAAAAA==.',
Ky='Kyleschlong:BAAALgAECgMJCAAAAA==.Kyndreith:BAAALgAECgMJAwAAAA==.',
['Kä']='Kämpfer:BAABLgAECn9QAAIEAAkJFiE4BgDrAgAEAAkJFiE4BgDrAgAAAA==.',
La='Lafiel:BAABLgAECn8dAAMDAAkJGgtKPABJAQADAAkJGgtKPABJAQAIAAIJ1QgibgBCAAAAAA==.Landiedoo:BAAALgAECgkJCgAAAA==.Laverna:BAAALgADCgMJBAAAAA==.Lazeras:BAAALgAECgUJCQABLgAFFAEJAgARAAAAAA==.',
Le='Lefay:BAAALgADCgcJFwAAAA==.Leprawnjames:BAAALgAECgIJAgABLgAECgYJDwARAAAAAA==.Letsgetwet:BAAALgADCgYJBgAAAA==.',
Li='Liefic:BAAALgAECgYJCAAAAA==.Limon:BAAALgADCgIJAgAAAA==.',
Lo='Loadin:BAAALgAECgIJAgAAAA==.Lockaflockå:BAAALgADCgMJAwAAAA==.Locke:BAAALgAECgMJAgABLgAECgYJGgABAOggAA==.Lonoh:BAAALgAECgcJEgAAAA==.',
Lu='Luan:BAAALgADCgEJAQAAAA==.Lucariø:BAAALgADCgcJDAAAAA==.Lucidbonsai:BAAALgADCggJCAAAAA==.Luckykilla:BAABLgAECn8mAAIlAAkJHhlrBAA3AgAlAAkJHhlrBAA3AgAAAA==.Lucÿ:BAACLgAFFH8QAAIPAAUJtA7pIQA9AQAPAAUJtA7pIQA9AQAuAAQKfyIAAw8ABwmsGPQoAOwBAA8ABwmsGPQoAOwBABQAAwkVDKRsAIIAAAAA.Lula:BAAALgADCgMJAwAAAA==.Lurith:BAABLgAECn9EAAMTAAkJwBWhEQDYAQATAAkJMhShEQDYAQASAAcJlgrYuAARAQAAAA==.Lutreaux:BAAALgADCgEJAQAAAA==.Luxtyrannica:BAABLgAECn8fAAIBAAcJExvkSQDRAQABAAcJExvkSQDRAQAAAA==.',
Ly='Lydrain:BAAALgAECgEJAQAAAA==.Lysandria:BAABLgAECn8pAAINAAkJmw3xYAClAQANAAkJmw3xYAClAQAAAA==.',
Ma='Macrosblack:BAAALgADCgMJAwAAAA==.Madamerouge:BAAALgAECgIJAgABLgAECgYJGQAeAIcVAA==.Magearino:BAABLgAECn8nAAINAAgJnRYiWAC8AQANAAgJnRYiWAC8AQAAAA==.Malafore:BAAALgADCgEJAQAAAA==.Marcopally:BAAALgAECgQJBAAAAA==.Marluxia:BAACLgAFFH8fAAIfAAYJ7wpTDAABAQAfAAYJ7wpTDAABAQAuAAQKfxoAAh8ACAkhE/YMALkBAB8ACAkhE/YMALkBAAAA.Materfamilia:BAAALgAECgQJBAAAAA==.Mattbull:BAACLgAFFH8HAAMVAAMJ0RidMADlAAAVAAMJ0RidMADlAAAgAAEJ1xNICQBXAAAuAAQKfx4AAyAABgmqJFcNAAQCACAABglCIlcNAAQCABUABgl5ItQdAM8BAAAA.Mayu:BAAALgADCgkJCAAAAA==.',
Me='Medjrab:BAACLgAFFH8SAAISAAQJxhiATAA6AQASAAQJxhiATAA6AQAuAAQKfzIAAhIACQlLIl0PAN8CABIACQlLIl0PAN8CAAAA.Meristem:BAABLgAECn8rAAIHAAgJkA4DKQBuAQAHAAgJkA4DKQBuAQAAAA==.Merko:BAAALgADCgkJDwAAAA==.',
Mi='Miaan:BAAALgADCgYJBgAAAA==.Miette:BAAALgADCgMJAwAAAA==.Mihonk:BAAALgADCgQJBAAAAA==.Mintycrx:BAABLgAECn8fAAINAAkJHhGMSQDnAQANAAkJHhGMSQDnAQAAAA==.Missfist:BAAALgADCgIJAgAAAA==.Mistlocke:BAAALgADCgMJAwAAAA==.',
Mn='Mngwa:BAAALgAECgQJCQAAAA==.',
Mo='Moegu:BAABLgAECn8bAAImAAgJXxY9CQC/AQAmAAgJXxY9CQC/AQAAAA==.Mog:BAACLgAFFH8GAAMYAAMJERoDfgCoAAAYAAIJlhkDfgCoAAAkAAEJBxt2GgBSAAAuAAQKfzYABBgACQljI2wUAJ8CABgABwmSI2wUAJ8CACQAAwmVI9oUAAABABoAAwkcEcI2ANsAAAAA.Moncatsera:BAAALgAECgQJBAAAAA==.Mondgrille:BAAALgAECgQJBAABLgAECgYJDQARAAAAAA==.Monora:BAABLgAECn8XAAIXAAcJzAp8SgANAQAXAAcJzAp8SgANAQAAAA==.Montress:BAABLgAECn8UAAIDAAgJBhBlIwCSAQADAAgJBhBlIwCSAQAAAA==.Moomoohealz:BAACLgAFFH8KAAIHAAMJxxcHJADiAAAHAAMJxxcHJADiAAAuAAQKfz4AAgcACQkoIcoGANgCAAcACQkoIcoGANgCAAAA.Moonbounds:BAACLgAFFH8jAAIPAAcJRRuMBABKAgAPAAcJRRuMBABKAgAuAAQKfzgAAw8ACQndJFEDAEQDAA8ACQndJFEDAEQDABQAAQnZH4Z5AF0AAAAA.Moondoggey:BAAALgAECgMJAwAAAA==.Morgana:BAAALgADCgIJAgAAAA==.Mousechief:BAABLgAECn8rAAIUAAcJNgaOUgDSAAAUAAcJNgaOUgDSAAAAAA==.Moxnix:BAABLgAECn8VAAMXAAgJng5kSAAVAQAXAAcJXgxkSAAVAQAdAAQJjgUDVwCbAAAAAA==.Moxxzi:BAAALgAFFAEJAgAAAA==.',
Mu='Muhfookinbak:BAABLgAECn8kAAMPAAkJFyAYDgDNAgAPAAkJFyAYDgDNAgAUAAQJhxhYVADMAAAAAA==.',
My='Myor:BAAALgADCgMJAwAAAA==.',
['Mà']='Màttbull:BAABLgAFFH8HAAIKAAMJcw42VgDKAAAKAAMJcw42VgDKAAABLgAFFAMJBwAVANEYAA==.',
['Mä']='Märcøsferätv:BAAALgAECgEJAQAAAA==.',
Na='Naesta:BAAALgAECgIJAgABLgAECggJIQAGAP4fAA==.Naksu:BAEALgAECgEJAQABLgAECgcJGgAKAJ8FAA==.Naksù:BAEBLgAECn8aAAIKAAcJnwW3ngDGAAAKAAcJnwW3ngDGAAAAAA==.Namal:BAAALgAECgQJBQAAAA==.Narenae:BAABLgAECn8lAAIFAAkJCyRABABIAwAFAAkJCyRABABIAwAAAA==.Nastalan:BAAALgADCgYJCgAAAA==.',
Ne='Nefari:BAAALgADCgMJAwAAAA==.Neifeb:BAABLgAECn8oAAIbAAkJeha7MQD+AQAbAAkJeha7MQD+AQAAAA==.Nephthys:BAAALgADCgQJBAAAAA==.',
Ni='Niallivdam:BAABLgAECn8qAAMgAAgJNxmvBAASAgAgAAgJNxmvBAASAgAnAAYJ0hdREgCQAQAAAA==.Nights:BAAALgAECgIJAgABLgAECggJFwAQAM0YAA==.Nightsoul:BAAALgADCgEJAQAAAA==.Ninh:BAACLgAFFH8KAAIXAAMJrAKiPABrAAAXAAMJrAKiPABrAAAuAAQKf00AAhcACQn6FFEYADACABcACQn6FFEYADACAAAA.',
No='Nomissius:BAAALgADCgcJDQAAAA==.Nooblè:BAAALgADCgMJAwAAAA==.Notsodemon:BAABLgAECn8eAAMKAAgJfxTKSwCKAQAKAAgJfxTKSwCKAQACAAIJnwrPYwBUAAAAAA==.Notsoevoker:BAAALgAECgMJAwABLgAECggJHgAKAH8UAA==.Notsomonk:BAAALgADCgMJAwABLgAECggJHgAKAH8UAA==.',
Ny='Nykara:BAAALgAECgUJBQAAAA==.',
['Nå']='Nåld:BAAALgAECgUJBgAAAA==.',
Oa='Oakendorf:BAAALgAECgEJAQABLgAECgEJAgARAAAAAA==.',
Ob='Obvinotagirl:BAAALgAECggJDwAAAA==.',
Od='Oddpocalypse:BAAALgAECgEJAQAAAA==.',
Og='Ogsikko:BAAALgAECgYJCwABLgAECggJGAAYAJAeAA==.Ogsikkotv:BAABLgAECn8YAAINAAYJ/BmQhwDCAQANAAYJ/BmQhwDCAQABLgAECggJGAAYAJAeAA==.',
Ok='Okathra:BAAALgAECgQJBAABLgAECgkJMgAcAEwjAA==.',
On='Onebadmutha:BAABLgAECn8ZAAIYAAkJ+AzDSQCyAQAYAAkJ+AzDSQCyAQAAAA==.Ontop:BAABLgAECn8oAAIbAAkJ7xsaHABeAgAbAAkJ7xsaHABeAgAAAA==.',
Or='Orb:BAABLgAECn8tAAQBAAkJKhm9OQADAgABAAkJLRi9OQADAgAOAAgJexLmIwDRAQALAAUJQQ/EHgATAQAAAA==.Orcfreeza:BAAALgAECgQJDAAAAA==.Ortinks:BAABLgAECn8eAAINAAgJvA8vaQCRAQANAAgJvA8vaQCRAQAAAA==.',
Ow='Owneege:BAACLgAFFH8YAAIEAAcJYSP9AQA5AgAEAAcJYSP9AQA5AgAuAAQKfzMAAgQACQkEIx4CAKADAAQACQkEIx4CAKADAAAA.',
Pa='Painsaw:BAAALgADCgYJBgAAAA==.Pallinar:BAABLgAECn8zAAIBAAgJEhZTUwC3AQABAAgJEhZTUwC3AQAAAA==.Pasquale:BAABLgAECn8hAAIdAAcJRSHYEgAKAgAdAAcJRSHYEgAKAgAAAA==.',
Pe='Pebbles:BAAALgAECggJEwAAAA==.Pedroia:BAAALgAECgcJCAAAAA==.Peridaxx:BAAALgAECgIJAgAAAA==.Pesty:BAAALgAECgMJCQAAAA==.',
Ph='Phe:BAABLgAECn8XAAMHAAcJhw4bNgAjAQAHAAcJhw4bNgAjAQAGAAYJpQvzcAADAQAAAA==.Pheraree:BAAALgAECgEJAQAAAA==.Phooboo:BAAALgAECgkJBQAAAA==.',
Pi='Pidion:BAAALgADCgYJDAAAAA==.Pilgrimm:BAECLgAFFH8VAAMiAAYJCRxlAwBUAQAiAAUJTxllAwBUAQAQAAMJpyAgCwA4AQAuAAQKfyQAAxAACQl7IrIDAGADABAACQl0IrIDAGADACIABQkIH0kKAGYBAAAA.Pixyl:BAAALgADCgYJBgAAAA==.',
Pl='Plaguerott:BAABLgAECn83AAIoAAkJeA/GCwCOAQAoAAkJeA/GCwCOAQAAAA==.Plusultra:BAAALgADCgkJEQAAAA==.Pluto:BAAALgAFFAMJAwAAAA==.',
Po='Poby:BAAALgADCgcJBwAAAA==.Polydh:BAABLgAECn8wAAImAAkJriSmAABFAwAmAAkJriSmAABFAwAAAA==.Poobah:BAABLgAECn8jAAMUAAgJvAZvTgDfAAAUAAcJfAZvTgDfAAAPAAcJCgNcfADIAAAAAA==.Popscotch:BAABLgAECn8jAAMkAAkJEg3OCQCkAQAkAAcJRg7OCQCkAQAYAAkJwAtnUgCZAQAAAA==.Pouffant:BAABLgAECn8iAAIBAAkJyBMsTgDFAQABAAkJyBMsTgDFAQAAAA==.',
Pr='Pronoz:BAABLgAECn8jAAIBAAcJfRJ/hwBGAQABAAcJfRJ/hwBGAQAAAA==.',
Pu='Punchy:BAAALgADCgEJAQAAAA==.',
Pw='Pwnageddon:BAABLgAECn8nAAMLAAgJAB4/CAA6AgALAAcJlSE/CAA6AgABAAUJhxUW4gDJAAAAAA==.Pwnjitsu:BAACLgAFFH8FAAIFAAMJAh4aFAANAQAFAAMJAh4aFAANAQAuAAQKfzoAAgUACQk8JagBAFQDAAUACQk8JagBAFQDAAAA.',
Py='Pyrothermia:BAACLgAFFH8RAAINAAcJNg7iHQDMAQANAAcJNg7iHQDMAQAuAAQKfyYAAg0ACQn/HIoqAMgCAA0ACQn/HIoqAMgCAAAA.',
['Pô']='Pôlgara:BAAALgADCgYJBgABLgAECggJKQAOAOseAA==.',
Qt='Qtkillz:BAAALgADCgQJBAAAAA==.',
Ra='Rancayden:BAAALgAECgMJBAAAAA==.Rawhoof:BAACLgAFFH8KAAIEAAMJEhxpJQAAAQAEAAMJEhxpJQAAAQAuAAQKf00AAgQACQm7JY0BAF0DAAQACQm7JY0BAF0DAAAA.Razak:BAABLgAECn8yAAIcAAkJTCOEAQARAwAcAAkJTCOEAQARAwAAAA==.',
Re='Renisa:BAABLgAECn8iAAIKAAgJqRnaSQCRAQAKAAgJqRnaSQCRAQAAAA==.Retman:BAABLgAECn8UAAIBAAcJtg+p2gDGAAABAAcJtg+p2gDGAAAAAA==.Reu:BAAALgAECgUJBwAAAA==.Revlyk:BAABLgAECn8nAAIcAAgJFiOsAwCwAgAcAAgJFiOsAwCwAgABLgAFFAQJCwACAAobAA==.Rezloh:BAAALgAECgkJDAAAAA==.',
Rh='Rhoanna:BAAALgADCgUJBwAAAA==.',
Ri='Rinja:BAAALgADCgYJBgAAAA==.Rintaro:BAABLgAECn8kAAILAAkJrAvAGAA7AQALAAkJrAvAGAA7AQAAAA==.Ritanana:BAAALgAECgIJAgAAAA==.',
Ro='Roccot:BAAALgAECggJDgAAAA==.Roflstomp:BAAALgAECgQJBwABLgAECgYJDwARAAAAAA==.Roostrr:BAABLgAECn8XAAIBAAYJ4B2EcwCUAQABAAYJ4B2EcwCUAQAAAA==.Rotfather:BAAALgADCgYJBgAAAA==.Rotjaw:BAAALgAECgUJCwAAAA==.Roughedge:BAAALgADCgIJAgAAAA==.',
Ru='Rurik:BAAALgAECgEJAQAAAA==.',
['Rè']='Rèjuva:BAAALgAECgcJDQAAAA==.Rèptílè:BAAALgADCgMJAwABLgAFFAMJBwAbAA8iAA==.',
['Rî']='Rîcflair:BAAALgAECgcJEwAAAA==.',
Sa='Saiyax:BAAALgADCgYJBwAAAA==.Salidfingers:BAAALgADCgYJBgAAAA==.Sanyakulak:BAAALgADCgcJBwABLgAFFAgJGwAfABcWAA==.Sanzo:BAAALgADCgkJEgAAAA==.Savathûn:BAAALgAECgQJCAAAAA==.',
Sc='Scalycat:BAACLgAFFH8GAAMVAAMJpAGZRQCFAAAVAAMJpAGZRQCFAAAnAAIJkgfdIgBqAAAuAAQKfyoABCcACQnYDpwZAMEBACcACQnYDpwZAMEBABUABwksBj1ZAKgAACAAAgluBzMkADAAAAAA.Schalla:BAAALgAECgEJAQAAAA==.Scum:BAAALgAECgYJDQAAAA==.Scòrpìòn:BAAALgADCgcJBgABLgAFFAMJBwAbAA8iAA==.',
Se='Seancody:BAAALgADCgIJAgAAAA==.Sekhmett:BAAALgAECgUJBQAAAA==.Selandria:BAAALgADCgQJBAAAAA==.Senate:BAAALgAECgYJCwAAAA==.',
Sh='Shadowbear:BAABLgAECn8cAAIIAAcJ/RyrHADCAQAIAAcJ/RyrHADCAQAAAA==.Shadowoss:BAAALgAECgYJCAAAAA==.Shadygrump:BAAALgAECgYJEQAAAA==.Shammacass:BAAALgAECgUJBQAAAA==.Shamwick:BAAALgAECgMJAwAAAA==.Shaolincito:BAAALgAECgQJCAAAAA==.Sherrilyn:BAAALgAECgQJBAAAAA==.Shocklocke:BAAALgAECgQJBAAAAA==.',
Si='Sigmachad:BAAALgAECgUJDwAAAA==.Silandrus:BAAALgAECgEJAQAAAA==.Silverocean:BAABLgAECn8zAAIOAAkJMRzqDwCUAgAOAAkJMRzqDwCUAgAAAA==.Silvia:BAAALgADCgUJCQAAAA==.Singularity:BAACLgAFFH8KAAIMAAMJPCR3DQA0AQAMAAMJPCR3DQA0AQAuAAQKf0oAAgwACQlmJlUAAHsDAAwACQlmJlUAAHsDAAAA.',
Sk='Skaerx:BAABLgAECn8WAAMEAAYJVBeOQwCXAQAEAAYJ9RWOQwCXAQAjAAQJZhSYHQADAQAAAA==.Skittlez:BAABLgAECn8mAAIWAAkJkR9SCACNAgAWAAkJkR9SCACNAgABLgAFFAEJAQARAAAAAA==.',
Sl='Slaykween:BAAALgAECgYJEAAAAA==.Slootybooty:BAAALgAECgYJDwAAAA==.',
Sm='Smallz:BAAALgAECgYJEQABLgAECggJHgANALAIAA==.',
Sn='Snipersmash:BAAALgAECgQJCAAAAA==.Snooptrogg:BAABLgAECn8rAAIEAAkJGRV9HwDfAQAEAAkJGRV9HwDfAQAAAA==.Snoozumi:BAABLgAFFH8GAAIXAAMJKQZMNwCIAAAXAAMJKQZMNwCIAAAAAA==.Snuups:BAABLgAECn86AAIYAAkJKxkpLAAbAgAYAAkJKxkpLAAbAgAAAA==.',
So='Soldiah:BAABLgAECn8bAAIEAAgJrQ2VMgBsAQAEAAgJrQ2VMgBsAQAAAA==.Sommbra:BAAALgAECgYJBwAAAA==.Souljax:BAAALgADCgcJCQAAAA==.',
Sp='Spacelaser:BAAALgAECgQJBQAAAA==.',
Sq='Sqwurl:BAAALgADCgQJBAAAAA==.',
St='Steakhaus:BAAALgADCgIJAgAAAA==.Stiros:BAAALgAECgMJAwAAAA==.Stonedragon:BAECLgAFFH8RAAIbAAUJdiBnGwBrAQAbAAUJdiBnGwBrAQAuAAQKfzMAAxsACAn+JMwFADEDABsACAn+JMwFADEDAAkAAgn/DsIqAFwAAAAA.Stormfist:BAAALgAECggJEAAAAA==.Stormhaven:BAAALgADCggJKgABLgAECggJKQAOAOseAA==.Stormrender:BAAALgAECgYJEAAAAA==.Stormstag:BAAALgADCgYJBgAAAA==.Stouty:BAAALgADCgMJAwABLgAECgcJFAAgAOkaAA==.',
Su='Sukonamí:BAABLgAECn8iAAMEAAkJghckKAAdAgAEAAgJdhUkKAAdAgAjAAQJGhu5IwAuAQAAAA==.Suzhou:BAABLgAECn8jAAIaAAgJown4EQAOAQAaAAgJown4EQAOAQAAAA==.Suzoomies:BAAALgADCgcJBwAAAA==.Suzumii:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetcarolin:BAABLgAECn8WAAISAAkJRg+GXgDXAQASAAkJRg+GXgDXAQAAAA==.Sweetsmercy:BAAALgAECgQJBQAAAA==.Swiftleaf:BAAALgADCgcJBwAAAA==.Swisscheese:BAABLgAECn8rAAIYAAgJSSFxFgCRAgAYAAgJSSFxFgCRAgAAAA==.',
Sy='Syraxa:BAAALgAECgMJBQABLgAFFAMJCQAGAPUQAA==.Syril:BAAALgADCgcJDAAAAA==.',
Ta='Taedish:BAAALgADCgMJAwAAAA==.Tahret:BAAALgADCgQJBQAAAA==.Taquillya:BAAALgAECgMJAwAAAA==.Tarina:BAAALgADCgEJAQAAAA==.Tatersaladin:BAAALgADCgMJAwAAAA==.',
Te='Tenlortin:BAAALgAECgEJAQAAAA==.Terragosa:BAABLgAECn8wAAINAAgJXRg6RgDxAQANAAgJXRg6RgDxAQAAAA==.Teryail:BAAALgAECgEJAQAAAA==.Tetchybono:BAAALgADCgYJBgAAAA==.',
Th='Thade:BAABLgAECn8kAAMjAAkJByHHBACxAgAjAAgJGiDHBACxAgAEAAgJfB5XHwBWAgAAAA==.Thaeleon:BAABLgAECn8hAAMHAAgJbx9mEABFAgAHAAgJbx9mEABFAgAGAAYJixz+NADUAQABLgAFFAMJBgAMAPgVAA==.Thahawtz:BAAALgADCggJCAAAAA==.Thaneblade:BAAALgAECgQJBgAAAA==.Therizzler:BAAALgAECgcJCQABLgAFFAMJCwAKAP8UAA==.Thickening:BAABLgAECn8ZAAMXAAUJhQ0DWQDVAAAXAAUJhQ0DWQDVAAAFAAUJ9QcyVgCdAAAAAA==.Thope:BAABLgAECn8YAAINAAYJSAg5zADYAAANAAYJSAg5zADYAAAAAA==.Thoranubran:BAABLgAECn8WAAICAAYJ/w4bMwA+AQACAAYJ/w4bMwA+AQAAAA==.Thrivia:BAAALgAECgYJBgAAAA==.',
Ti='Ticklemychin:BAAALgAECgQJBwAAAA==.Tigani:BAAALgAECgUJDAAAAA==.Tinstey:BAAALgADCgEJAQAAAA==.',
To='Toestiir:BAAALgADCgcJDAAAAA==.Tokemaddab:BAAALgADCgUJBQAAAA==.Toughasnails:BAAALgAECgEJAQAAAA==.',
Tr='Traesdyne:BAAALgAECgEJAQABLgAECgMJAwARAAAAAA==.Trainar:BAAALgAECgQJCQAAAA==.Trazle:BAAALgAECgIJAgAAAA==.Trekkiegeek:BAAALgADCgYJBwAAAA==.Trickybackup:BAAALgADCgMJAwAAAA==.Triggs:BAAALgAECgcJBgAAAA==.Trollbear:BAABLgAECn8WAAIGAAgJhBV+JQAOAgAGAAgJhBV+JQAOAgAAAA==.Trondruid:BAAALgADCgYJDQAAAA==.Trooze:BAABLgAECn81AAIOAAgJKCTYBQAgAwAOAAgJKCTYBQAgAwAAAA==.Trr:BAABLgAECn8pAAIYAAkJmBe2IwCFAgAYAAkJmBe2IwCFAgAAAA==.Truckz:BAAALgADCgEJAQABLgAECgkJNwAbAE0gAA==.Truckzage:BAAALgADCgcJBwABLgAECgkJNwAbAE0gAA==.',
Tu='Tuba:BAAALgAECgYJEAAAAA==.Turim:BAAALgAECgYJBgAAAA==.Tusksrus:BAAALgADCgcJFwAAAA==.',
Ty='Tyrlidd:BAABLgAECn8yAAIbAAgJfxZOOgDeAQAbAAgJfxZOOgDeAQAAAA==.',
Ud='Udon:BAABLgAECn8YAAISAAYJcBe+bwBxAQASAAYJcBe+bwBxAQAAAA==.',
Ul='Ultimazero:BAAALgADCgEJAQAAAA==.',
Un='Unavoidable:BAAALgADCgkJEQAAAA==.Unlikelytale:BAABLgAECn8mAAIPAAkJAyEuCgDXAgAPAAkJAyEuCgDXAgAAAA==.Unmilked:BAAALgAECgYJBwAAAA==.',
Ur='Uricash:BAABLgAECn9QAAINAAkJliBHDgDzAgANAAkJliBHDgDzAgAAAA==.Urzual:BAABLgAECn8rAAIcAAkJDyDrBACGAgAcAAkJDyDrBACGAgAAAA==.',
Ut='Utiniócast:BAAALgAECgQJBAAAAA==.',
Va='Vandreynna:BAACLgAFFH8LAAICAAQJChspBwBlAQACAAQJChspBwBlAQAuAAQKf0kAAgIACQlmJX4BAE8DAAIACQlmJX4BAE8DAAAA.',
Ve='Vegèta:BAABLgAECn8gAAISAAkJZAuVdABmAQASAAkJZAuVdABmAQABLgAFFAMJBwAbAA8iAA==.Veilaura:BAAALgAECgYJCgAAAA==.Velarria:BAABLgAECn8dAAMbAAkJ4h43FQCOAgAbAAkJ4h43FQCOAgAWAAQJjwwcIQDSAAAAAA==.Velikan:BAAALgAECgQJBwABLgAECgcJCAARAAAAAA==.Velsiana:BAAALgAECgYJDQAAAA==.Velveetah:BAAALgAECgUJCAABLgAECgYJGQADAJ4PAA==.Verbrennen:BAAALgAECgUJCQABLgAECgkJUAAEABYhAA==.Verdreht:BAAALgADCgEJAQABLgAECgkJUAAEABYhAA==.Verita:BAABLgAECn8rAAIiAAcJcCPxAwA9AgAiAAcJcCPxAwA9AgAAAA==.Verlynne:BAAALgADCgYJBgAAAA==.Verylikely:BAAALgAECgEJAgAAAA==.',
Vi='Viviann:BAABLgAECn8kAAInAAkJeREkDwDIAQAnAAkJeREkDwDIAQAAAA==.',
Vo='Voiager:BAAALgADCgcJCgAAAA==.',
Vr='Vrakal:BAAALgAECgkJDQAAAA==.',
Wa='Wantabehavoc:BAAALgADCgYJDQAAAA==.Wantadeznutz:BAAALgAECgIJAgAAAA==.Warnick:BAAALgADCgQJBQAAAA==.Warraxe:BAAALgAECgEJAgAAAA==.Wayloren:BAABLgAECn8qAAIBAAkJzArXcAByAQABAAkJzArXcAByAQAAAA==.Waystalker:BAAALgAECgMJAwAAAA==.Wayverly:BAAALgADCgUJBwABLgAECggJHQAJAEAJAA==.',
Wi='Wickathy:BAABLgAECn9CAAImAAkJbSBCAgDNAgAmAAkJbSBCAgDNAgAAAA==.',
Wo='Wolfcity:BAAALgADCgEJAQAAAA==.Wondertauren:BAAALgADCgYJCQAAAA==.Woodson:BAAALgADCgkJEAAAAA==.Worstdps:BAAALgAFFAEJAQAAAA==.',
Wr='Wrkandtank:BAAALgAECgYJBgABLgAECggJFQAYAHcLAA==.',
Wu='Wuldorr:BAACLgAFFH8NAAIBAAQJeRJrOwAdAQABAAQJeRJrOwAdAQAuAAQKfyQAAgEACAm1H0gkAJYCAAEACAm1H0gkAJYCAAAA.',
Wy='Wynnifred:BAAALgAECggJDQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.',
Xe='Xethreal:BAAALgADCgMJAwAAAA==.',
Xy='Xype:BAAALgAECgkJEQAAAA==.',
Ya='Yastoria:BAAALgAECgcJEAAAAA==.',
Yi='Yinandtonic:BAAALgAECgEJBAAAAA==.',
Yv='Yvvee:BAAALgADCgcJBwAAAA==.',
Za='Zaalim:BAAALgADCgQJBAAAAA==.Zaddy:BAAALgAECgEJAQAAAA==.Zapdôs:BAAALgAECgQJBAAAAA==.',
Ze='Zeda:BAAALgAECgUJCAABLgAECgYJEgARAAAAAA==.Zephyris:BAAALgAECgUJDAABLgAFFAcJJAAjAKolAA==.',
Zh='Zheng:BAAALgAECgYJBgAAAA==.',
Zi='Zillia:BAAALgADCgMJAwAAAA==.',
Zo='Zonora:BAABLgAECn8WAAIOAAgJuQyiMACAAQAOAAgJuQyiMACAAQAAAA==.',
Zy='Zyphexd:BAAALgAECgYJDwAAAA==.Zyris:BAAALgADCgcJDQAAAA==.',
['Àz']='Àzñós:BAAALgAECgQJBwAAAA==.',
['Äs']='Ästro:BAAALgAECgQJBgABLgAECgkJLQAFAHcaAA==.',
['Äz']='Äzrael:BAABLgAECn8wAAIDAAkJQRvyCQC0AgADAAkJQRvyCQC0AgAAAA==.',
['Åz']='Åznos:BAAALgAECgQJCAAAAA==.',
['Çr']='Çréwüsæðèr:BAABLgAECn8jAAIMAAgJZiBsCQBIAgAMAAgJZiBsCQBIAgAAAA==.',
['Ðe']='Ðecimus:BAAALgAECgQJCQAAAA==.',
['Ðì']='Ðìaßlo:BAACLgAFFH8HAAIbAAMJDyIDRgD5AAAbAAMJDyIDRgD5AAAuAAQKfzEABBsACQlsHKIiAEMCABsACAkUHKIiAEMCABYABwlYFAQRALMBAAkAAQleABqbABUAAAAA.',
['Öb']='Öblïvïöñ:BAAALgAECgEJAgAAAA==.',
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
