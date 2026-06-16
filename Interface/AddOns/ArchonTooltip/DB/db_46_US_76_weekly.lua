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

local lookup = {'Paladin-Retribution','DeathKnight-Unholy','DemonHunter-Havoc','Priest-Holy','Warrior-Fury','Monk-Windwalker','Druid-Restoration','Druid-Balance','Priest-Shadow','Hunter-Marksmanship','Paladin-Protection','DemonHunter-Devourer','Warrior-Protection','Mage-Frost','Paladin-Holy','Shaman-Restoration','Rogue-Subtlety','Druid-Guardian','Unknown-Unknown','DeathKnight-Blood','Shaman-Elemental','Evoker-Preservation','Evoker-Augmentation','Hunter-Survival','Monk-Mistweaver','Warlock-Demonology','Priest-Discipline','Warlock-Destruction','Hunter-BeastMastery','Shaman-Enhancement','Monk-Brewmaster','Druid-Feral','Evoker-Devastation','Mage-Arcane','Rogue-Outlaw','Warrior-Arms','Warlock-Affliction','Rogue-Assassination','DemonHunter-Vengeance','DeathKnight-Frost',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Aberaht:BAABLgAECn8mAAIBAAkJYCOqDQAgAwABAAkJYCOqDQAgAwAAAA==.',
Ad='Adamaro:BAAALgADCgYJCQAAAA==.',
Ae='Aenastian:BAABLgAFFH8IAAICAAMJSxnQigDwAAACAAMJSxnQigDwAAABLgAFFAQJCwADAAobAA==.',
Af='Affrica:BAAALgADCgEJAQABLgAECgYJGQAEAJ4PAA==.',
Ag='Agnu:BAAALgADCgcJBwAAAA==.Agraar:BAAALgAECgUJBwAAAA==.',
Ah='Ahgra:BAABLgAECn89AAIBAAkJugz9eQB4AQABAAkJugz9eQB4AQAAAA==.',
Ak='Akre:BAAALgAFFAIJBgAAAQ==.Akumä:BAAALgAECgUJCgAAAA==.',
Al='Aleannia:BAAALgAECgUJBgAAAA==.Alekz:BAAALgAECgYJDQAAAA==.Alestria:BAABLgAECn8aAAIBAAgJ7BQlagCYAQABAAgJ7BQlagCYAQAAAA==.Alibrexia:BAACLgAFFH8IAAIFAAMJmgRePACyAAAFAAMJmgRePACyAAAuAAQKfyAAAgUACQlrCbc0AHYBAAUACQlrCbc0AHYBAAAA.Alida:BAABLgAECn8sAAIFAAkJqAqMNgBsAQAFAAkJqAqMNgBsAQAAAA==.Alithvia:BAAALgAECgYJBgABLgAECgkJJQAGAAskAA==.Allisara:BAAALgADCgkJFgAAAA==.Alysae:BAACLgAFFH8gAAMHAAYJNhwtEADwAQAHAAYJNhwtEADwAQAIAAEJSQBzVQAZAAAuAAQKfxsAAwcACAkrHeUdAE8CAAcACAkrHeUdAE8CAAgAAgllB2SVACgAAAAA.',
Am='Amabear:BAAALgAECgEJAQABLgAECgcJHAAJAP0cAA==.Ambrosse:BAAALgADCggJDwABLgAECgkJLQAGAHcaAA==.',
An='Anabug:BAAALgAECgMJBQAAAA==.Andelwynn:BAAALgAECgMJAwABLgAECgkJHwAKAMoIAA==.Angelsmentor:BAAALgAECgYJCgAAAA==.Aniellas:BAAALgAECgIJAgAAAA==.Annalese:BAAALgADCgUJCQABLgAECgkJHwAKAMoIAA==.',
Ar='Arabeli:BAAALgAECgEJAQAAAA==.Arbyss:BAAALgADCgcJDAAAAA==.Ardatha:BAAALgADCgcJFwAAAA==.Ariêz:BAAALgAECgIJAgAAAA==.Artio:BAABLgAECn8VAAMBAAgJ/AIaJAGJAAABAAcJVAIaJAGJAAALAAUJQQPHPgBfAAAAAA==.',
As='Asterön:BAAALgAECgcJEwAAAA==.Astrocakes:BAAALgAECgMJAwABLgAFFAMJDwAMADoWAA==.',
At='Athenä:BAACLgAFFH8mAAILAAgJng9nAQDbAQALAAgJng9nAQDbAQAuAAQKfzwAAgsACQl7HPkFAI4CAAsACQl7HPkFAI4CAAAA.Atsuma:BAABLgAECn8gAAINAAgJIAunIwAPAQANAAgJIAunIwAPAQAAAA==.',
Av='Avacynn:BAAALgAECgMJAwAAAA==.Aviz:BAAALgADCgMJAwAAAA==.',
Aw='Awtysmbb:BAAALgAECgUJBQABLgAFFAMJBwAOABIXAA==.',
Ay='Aylli:BAAALgAECgYJCgABLgAECgkJNwAEAFMcAA==.',
['Aí']='Aísling:BAABLgAECn8pAAIPAAgJ6x42DgCvAgAPAAgJ6x42DgCvAgAAAA==.',
Ba='Baboii:BAAALgADCgIJAgAAAA==.Baconmecrazy:BAAALgAECgEJAQAAAA==.Badinngo:BAAALgADCggJDwABLgAECgkJJAAQABcgAA==.Bahiu:BAAALgAECgQJBAAAAA==.Bajafresh:BAAALgAECgQJBQAAAA==.Battleshaman:BAAALgADCgYJBgAAAA==.',
Bd='Bd:BAABLgAECn8dAAIRAAgJJxU5GABGAgARAAgJJxU5GABGAgAAAA==.',
Be='Beardmedaddy:BAAALgAECgYJBgABLgAECgkJMAAFAI4hAA==.Bearstavious:BAABLgAFFH8FAAISAAMJXxZ9FwDFAAASAAMJXxZ9FwDFAAAAAA==.Benjinana:BAABLgAECn8ZAAMEAAYJng+3OgAHAQAEAAYJng+3OgAHAQAJAAIJJQPOWgBMAAAAAA==.Betterthanu:BAAALgADCgUJBQABLgADCgYJCgATAAAAAA==.',
Bg='Bg:BAAALgAECgYJBwAAAA==.',
Bi='Bige:BAAALgAECgYJEQAAAA==.Bilo:BAAALgAECgYJCAAAAA==.Bitelyus:BAAALgAECgUJCAAAAA==.',
Bl='Blazara:BAAALgAECgEJAQAAAA==.Blessedbymom:BAAALgADCgEJAQAAAA==.',
Bo='Bobius:BAAALgAECgkJDwAAAA==.Bobohizan:BAAALgADCgQJBAAAAA==.Bohde:BAABLgAFFH8OAAMCAAUJ6iIqRwBfAQACAAQJ6iIqRwBfAQAUAAEJAABGUAAAAAAAAA==.Bolognaman:BAAALgAECgUJCAAAAA==.Bombjovi:BAABLgAECn8gAAMLAAkJchVKDgDbAQALAAkJchVKDgDbAQAPAAUJlA8hUwDpAAAAAA==.Bountty:BAAALgAECgQJBAAAAA==.',
Br='Brahmsthoven:BAAALgADCgIJAwAAAA==.Branndhon:BAABLgAECn8lAAIHAAcJdBWgNwC2AQAHAAcJdBWgNwC2AQAAAA==.',
Bt='Btrflyprncss:BAAALgADCgMJAwAAAA==.',
Bu='Bubblemedic:BAAALgADCgIJAgAAAA==.Budde:BAAALgAECgUJBQAAAA==.Buffaloseven:BAABLgAECn8VAAMPAAcJ9gogQwAyAQAPAAcJ9gogQwAyAQABAAUJ9QTjGwGTAAABLgAFFAgJFgAOAOwMAA==.',
Ca='Cairdamane:BAABLgAECn8hAAIVAAkJ5BFPLgCFAQAVAAkJ5BFPLgCFAQAAAA==.Calidrina:BAABLgAECn8iAAIMAAkJMhyvQADDAQAMAAkJMhyvQADDAQAAAA==.Carm:BAAALgAECgYJBgAAAA==.Caroliná:BAAALgAECgUJCwAAAA==.Catcast:BAAALgAECgUJCAABLgAFFAMJCQAWAJAOAA==.Catclaw:BAAALgAECgEJAQABLgAFFAMJCQAWAJAOAA==.',
Ce='Celiri:BAABLgAECn8nAAIGAAkJrxACIQCjAQAGAAkJrxACIQCjAQAAAA==.Celldrassil:BAABLgAECn81AAIHAAkJAQdXXAAfAQAHAAkJAQdXXAAfAQAAAA==.Cereel:BAAALgAECgMJAwABLgAFFAMJDwAMADoWAA==.',
Ch='Chadaracka:BAAALgAECgYJBwAAAA==.Chandelure:BAAALgAECgUJCwAAAA==.Chardaney:BAABLgAECn8fAAIKAAkJygj3EgAqAQAKAAkJygj3EgAqAQAAAA==.Cherryontop:BAABLgAECn8qAAIHAAgJVBTMMQDXAQAHAAgJVBTMMQDXAQAAAA==.Chozenone:BAAALgAECgUJEgAAAA==.Chozi:BAAALgAECgYJBgAAAA==.Chromosomie:BAABLgAFFH8GAAIXAAQJEgUyPQDOAAAXAAQJEgUyPQDOAAABLgAECgkJMAAOAOcbAA==.',
Ci='Cii:BAABLgAECn8gAAMLAAgJWRDoFgBnAQALAAgJIhDoFgBnAQABAAUJew0A1wDnAAAAAA==.',
Co='Coconutwater:BAAALgAFFAEJAQAAAA==.Colandros:BAABLgAECn9AAAIYAAkJ/gsRGgDOAQAYAAkJ/gsRGgDOAQAAAA==.Colara:BAABLgAECn8dAAIMAAcJSwSiuAC1AAAMAAcJSwSiuAC1AAAAAA==.Combobreaker:BAACLgAFFH8LAAIZAAMJVx42LAABAQAZAAMJVx42LAABAQAuAAQKfzQAAhkACQm+H84HAB0DABkACQm+H84HAB0DAAAA.Comoo:BAAALgAECgEJAQAAAA==.Correct:BAAALgAECgEJAQAAAA==.Cowbôy:BAAALgADCgkJEQAAAA==.',
Cr='Crassberry:BAACLgAFFH8gAAICAAgJXx+LDABsAgACAAgJXx+LDABsAgAuAAQKfygAAgIACQk2JBQFAIMDAAIACQk2JBQFAIMDAAAA.Crazyraptor:BAAALgAECgYJDAABLgAECggJFQAaAHcLAA==.Crazèd:BAAALgADCgQJBAAAAA==.Crimes:BAAALgAECgIJAwAAAA==.',
Cu='Cutco:BAAALgAFFAMJBAAAAA==.',
Cy='Cyndal:BAABLgAECn8UAAIOAAUJsBjzqwAlAQAOAAUJsBjzqwAlAQABLgAECgYJGQAGAAEcAA==.Cyndle:BAABLgAECn8ZAAIGAAYJARwhIwCVAQAGAAYJARwhIwCVAQAAAA==.Cyntu:BAAALgAECgUJCwABLgAECgYJGQAGAAEcAA==.',
['Cü']='Cüpid:BAAALgAECgYJBgAAAA==.',
Da='Dada:BAAALgAECgEJAQAAAA==.Dammithells:BAAALgADCgQJBAAAAA==.Dandamar:BAAALgAECgYJBgAAAA==.Dankbuds:BAAALgAECgYJAgAAAA==.Dankfists:BAAALgAECgUJBQABLgAECgYJAgATAAAAAA==.Dankhaze:BAAALgAFFAIJAgABLgAECgYJAgATAAAAAA==.Danksmash:BAAALgAECgMJBAABLgAECgYJAgATAAAAAA==.Dankzor:BAAALgAECgcJBQABLgAECgYJAgATAAAAAA==.Dark:BAAALgADCgEJAQAAAA==.Darthrevan:BAAALgAECgQJBwAAAA==.Dasharnkal:BAAALgADCgUJCAAAAA==.Dasvult:BAAALgAECgMJBAAAAA==.Dazex:BAABLgAECn8fAAMEAAYJtwMlTgCkAAAEAAYJawMlTgCkAAAbAAUJRwLEWgCPAAAAAA==.',
De='Deadpump:BAABLgAECn8fAAMaAAcJfRIteABIAQAaAAcJfRIteABIAQAcAAQJUQ4aOQDQAAAAAA==.Demonsnotkey:BAAALgAECgYJCwAAAA==.Demoxus:BAAALgAECgQJBAAAAA==.Denker:BAAALgADCggJCAAAAA==.Denkzilla:BAAALgADCgIJAgAAAA==.Denzvic:BAAALgAECgEJAQAAAA==.Destro:BAAALgAECgEJAQAAAA==.Deusclaw:BAAALgAECgYJCgAAAA==.Devilah:BAAALgAECgEJAQAAAA==.',
Dh='Dharm:BAABLgAECn8tAAMdAAkJuRjBMAAVAgAdAAkJuRjBMAAVAgAYAAIJxQw3TwBwAAAAAA==.',
Di='Dialsl:BAAALgADCgUJCQAAAA==.Digbickpanda:BAAALgAECgUJBQABLgAFFAMJDwAMADoWAA==.Disowneege:BAABLgAECn8mAAIBAAgJsCCIIACDAgABAAgJsCCIIACDAgABLgAFFAgJHQAFAAcgAA==.Diyos:BAAALgADCgYJCgAAAA==.',
Do='Dotndash:BAAALgADCgIJAgAAAA==.Doubledge:BAAALgAECgEJAQAAAA==.Doublejump:BAACLgAFFH8ZAAIMAAUJjBNARwANAQAMAAUJjBNARwANAQAuAAQKfykAAgwACAk4HnglADUCAAwACAk4HnglADUCAAAA.',
Dr='Dragdh:BAAALgAECgcJEwABLgAECggJKgAeAJ8cAA==.Dragnas:BAABLgAECn8qAAQeAAgJnxz/CwDuAQAeAAgJnxz/CwDuAQAQAAcJrBT6PAC2AQAVAAQJvhZGXQDJAAAAAA==.Dragonisa:BAAALgAFFAEJAQAAAA==.Dragun:BAAALgADCgIJAgAAAA==.Draiocht:BAAALgADCgMJBAABLgAECgkJNwAEAFMcAA==.Drakeskid:BAAALgAECgQJBwABLgAFFAQJBgAfALgKAA==.Drakthall:BAAALgAECgIJAwAAAA==.Dralionethny:BAAALgAECgIJAgAAAA==.Dramakiller:BAABLgAECn8VAAMdAAYJIwl4nQAAAQAdAAYJIwl4nQAAAQAKAAMJPAK8NwA9AAAAAA==.Drchi:BAAALgAECgEJAQABLgAECgYJGQAgAIcVAA==.Drcornbread:BAABLgAECn8ZAAMgAAYJhxVGGgA1AQAgAAYJhxVGGgA1AQASAAEJ0APnhQATAAAAAA==.Drcornellia:BAAALgAECgUJCAABLgAECgYJGQAgAIcVAA==.Drdarkskin:BAAALgAECgcJDQAAAA==.Drdreggs:BAABLgAECn8pAAMcAAkJmBYGEQAwAQAaAAgJuBSYTwDZAQAcAAYJmxcGEQAwAQAAAA==.Dreggs:BAAALgADCgcJEwAAAA==.Drewskie:BAAALgADCgQJBAAAAA==.Drizztin:BAAALgADCgEJAQAAAA==.Drprominus:BAABLgAECn8gAAIPAAgJACKpCQDvAgAPAAgJACKpCQDvAgAAAA==.Drthargyll:BAAALgADCgYJDgABLgAECggJIAAPAAAiAA==.',
Du='Dushman:BAAALgADCgYJBgAAAA==.',
Dy='Dykdanglr:BAAALgADCgYJBgABLgAECgQJCAATAAAAAA==.',
['Dí']='Dígifóx:BAAALgAECgEJAgAAAA==.Dígífóx:BAAALgAFFAEJAQAAAA==.',
Ea='Earthereal:BAABLgAECn80AAIZAAkJbxcGFQBsAgAZAAkJbxcGFQBsAgAAAA==.',
El='Elastar:BAABLgAECn8mAAINAAkJ6RYKDgApAgANAAkJ6RYKDgApAgAAAA==.Ellimist:BAECLgAFFH8iAAIQAAcJsRvxBABvAgAQAAcJsRvxBABvAgAuAAQKfykAAxAACQl9G3QXAFoCABAACQl9G3QXAFoCABUABQk0FxdQAAcBAAAA.Elsan:BAAALgAECgEJAQAAAA==.Elycee:BAACLgAFFH8IAAIdAAMJyyU9QwAhAQAdAAMJyyU9QwAhAQAuAAQKfyIAAx0ACQmtJXgIABQDAB0ACAk+JngIABQDAAoACAmWGZYgACECAAAA.Elysria:BAAALgADCgYJBgAAAA==.Elí:BAAALgAECgQJBAAAAA==.',
En='Encrid:BAAALgAECgcJDwABLgAFFAMJCQAXANEYAA==.Enhasa:BAABLgAECn8gAAICAAkJ/hU9MAA7AgACAAkJ/hU9MAA7AgABLgAECgYJGgABAOggAA==.Enoeht:BAABLgAECn82AAIDAAkJ2gsfIABzAQADAAkJ2gsfIABzAQAAAA==.Enveliria:BAAALgAECgcJDQABLgAFFAQJCwADAAobAA==.',
Er='Eraser:BAAALgAECgYJCAAAAA==.Erazar:BAABLgAECn9CAAIhAAgJyhSTBwC+AQAhAAgJyhSTBwC+AQAAAA==.Eriah:BAAALgADCgkJCQAAAA==.Erickk:BAABLgAECn8wAAMOAAkJ5xujQQAUAgAOAAkJnBqjQQAUAgAiAAQJVx1SCwAkAQAAAA==.',
Es='Essense:BAABLgAECn8mAAIEAAkJmyRIAwApAwAEAAkJmyRIAwApAwAAAA==.',
Ex='Exodari:BAABLgAECn87AAIeAAkJ7hi8CgAIAgAeAAkJ7hi8CgAIAgAAAA==.',
Fa='Fabbioh:BAAALgADCgEJAQAAAA==.Fadeddh:BAACLgAFFH8PAAIMAAMJOhbUWQDaAAAMAAMJOhbUWQDaAAAuAAQKfzAAAgwACQn/G9ciAEICAAwACQn/G9ciAEICAAAA.Faizarah:BAAALgAECgYJBgAAAA==.Faydien:BAAALgAECgEJAgAAAA==.',
Fe='Fearnoevil:BAAALgADCgMJAwAAAA==.Fel:BAABLgAECn8RAAIMAAgJjRpQXQBtAQAMAAgJjRpQXQBtAQAAAA==.Fellkarras:BAAALgAECgYJDwABLgAFFAMJCwAZAFceAA==.Fent:BAABLgAECn8VAAIaAAgJdwvMbwBaAQAaAAgJdwvMbwBaAQAAAA==.',
Fi='Fiddich:BAAALgAECgYJBgAAAA==.Fillthy:BAACLgAFFH8bAAIZAAcJQRdJDQAnAgAZAAcJQRdJDQAnAgAuAAQKfy4AAxkACQlYIkYDAEcDABkACQlYIkYDAEcDAAYAAwkhCRh0AGQAAAAA.Finnigann:BAAALgAECgYJCwAAAA==.Firenmylazer:BAAALgAECgQJBAAAAA==.Fistav:BAAALgADCgcJDgAAAA==.Fizban:BAABLgAECn8fAAIOAAgJsAh4ngA6AQAOAAgJsAh4ngA6AQAAAA==.',
Fl='Flappybird:BAAALgAECgYJCAABLgAFFAMJDwAMADoWAA==.Flasan:BAAALgADCgEJAQAAAA==.Flazz:BAAALgADCgIJAwAAAA==.Flazzan:BAAALgADCgEJAQAAAA==.Flik:BAAALgAECggJCAABLgAFFAMJCwAHAE0TAA==.',
Fo='Fogbringer:BAAALgAECgIJAwAAAA==.Four:BAAALgADCgQJBAAAAA==.',
Fr='Frejä:BAAALgAECgQJBQABLgAECgQJDAATAAAAAA==.Freyah:BAAALgAECgUJEgAAAA==.Frostmay:BAAALgAECgIJAgAAAA==.',
Fu='Furrybawlz:BAAALgAECgUJCgABLgAECgYJDQATAAAAAA==.',
Ga='Gabran:BAAALgAECgcJBwAAAA==.Gadogear:BAABLgAECn8oAAIOAAkJ7hcwPAAnAgAOAAkJ7hcwPAAnAgAAAA==.Galahan:BAAALgAECgUJBgAAAA==.Garlick:BAAALgADCggJDwABLgAECggJQgAhAMoUAA==.Garlik:BAAALgADCgMJBAAAAA==.',
Ge='Gertra:BAAALgAECgEJAgABLgAECgYJCAATAAAAAA==.',
Gf='Gfr:BAABLgAECn8UAAIcAAkJmBicAwBTAgAcAAkJmBicAwBTAgAAAA==.',
Gi='Girthrichard:BAAALgAECgYJDAAAAA==.',
Gl='Glassdragon:BAABLgAECn8mAAIBAAkJUQw7ggBoAQABAAkJUQw7ggBoAQAAAA==.Gllor:BAAALgADCgIJAgAAAA==.',
Go='Goatcheeze:BAABLgAECn8cAAIiAAkJLhX1AwDHAQAiAAkJLhX1AwDHAQAAAA==.Goatylocks:BAABLgAECn8rAAMcAAkJ7RU2DQBmAQAaAAgJvRDfUwCfAQAcAAYJLBw2DQBmAQAAAA==.Gohlemsaurus:BAAALgAECgYJBgAAAA==.Goldenchild:BAAALgAFFAMJAwABLgAFFAMJDwAMADoWAA==.',
Gr='Greatluckydo:BAAALgADCgEJAQAAAA==.Grishnakh:BAAALgAECgMJAwAAAA==.Grozlek:BAAALgADCgYJBgAAAA==.',
Gu='Gulen:BAABLgAECn8WAAIQAAYJpSEOIwA4AgAQAAYJpSEOIwA4AgAAAA==.',
Gw='Gwendyla:BAAALgADCgkJFgAAAA==.',
Gy='Gyousei:BAAALgAECgUJBQAAAA==.',
['Gí']='Gíga:BAABLgAECn8XAAIdAAgJ7RPdKQAPAgAdAAgJ7RPdKQAPAgAAAA==.',
Ha='Hafnium:BAAALgAECgIJAgAAAA==.Hamish:BAAALgAECgUJDQAAAA==.Hanhaine:BAACLgAFFH8GAAIIAAMJcwUSOACUAAAIAAMJcwUSOACUAAAuAAQKfywAAggACQnqFgwTADsCAAgACQnqFgwTADsCAAAA.Hazirat:BAAALgAECgYJDAAAAA==.',
He='Hedlie:BAAALgAECggJCwAAAA==.Hellenkeller:BAECLgAFFH8HAAIZAAYJhw/qIABZAQAZAAYJhw/qIABZAQAuAAQKfx8AAhkABwkzITQTADMCABkABwkzITQTADMCAAEuAAUUBwkbACMA9xsA.Heloisa:BAAALgAECgYJEQAAAA==.Helrazr:BAAALgAFFAEJAgAAAA==.Henshin:BAACLgAFFH8LAAIHAAMJTRO2PgCwAAAHAAMJTRO2PgCwAAAuAAQKf0QAAwcACQmxHT0QAM4CAAcACQmxHT0QAM4CAAgAAgk4DuSIADUAAAAA.',
Hi='Hitt:BAAALgAECgcJCAAAAA==.',
Ho='Hogwortsfun:BAAALgAECgkJAgAAAA==.Holirolla:BAAALgAECgMJAwAAAA==.Holyhim:BAAALgADCgIJAgAAAA==.Holyshawk:BAAALgAECgEJAwAAAA==.Holysudz:BAAALgADCgYJBgAAAA==.Hottyshmotty:BAAALgAECgEJAQAAAA==.Hourglass:BAABLgAECn9AAAMdAAkJlhrkHABzAgAdAAkJlhrkHABzAgAKAAQJ1g3oXwDBAAAAAA==.',
Hr='Hroc:BAAALgAECgUJCwAAAA==.',
Hu='Hunterviral:BAAALgADCgEJAgAAAA==.Huntthejuan:BAAALgADCgUJBQAAAA==.',
Ic='Icyowneege:BAAALgADCgUJBQABLgAFFAgJHQAFAAcgAA==.Icywolfy:BAAALgAECgYJCAAAAA==.',
Ig='Igreetyou:BAABLgAECn8kAAIaAAcJTx7oKwAoAgAaAAcJTx7oKwAoAgAAAA==.',
Il='Illie:BAABLgAECn8mAAIeAAkJShyHBQCtAgAeAAkJShyHBQCtAgAAAA==.Illune:BAACLgAFFH8HAAIOAAMJEhfOdgDyAAAOAAMJEhfOdgDyAAAuAAQKfysAAw4ACQlgGnkyAE0CAA4ACQlgGnkyAE0CACIABglSDhkJAFsBAAAA.',
Im='Imanbearpig:BAAALgAFFAMJBAAAAA==.Imleapingit:BAABLgAECn8wAAIFAAkJjiGpBgDzAgAFAAkJjiGpBgDzAgAAAA==.',
In='Intoodeep:BAAALgAFFAIJAgAAAA==.Intoodragons:BAACLgAFFH8LAAIXAAMJogfWSQChAAAXAAMJogfWSQChAAAuAAQKfzYAAxcACQmcFBMcAPMBABcACQmcFBMcAPMBACEABglaBfokAP4AAAAA.Inyah:BAAALgAECgIJAgAAAA==.',
Io='Ionzz:BAABLgAECn8ZAAIDAAkJrx+iCADYAgADAAkJrx+iCADYAgAAAA==.',
Ir='Ir:BAAALgAECggJDwAAAA==.Iroann:BAAALgAECgcJEgAAAA==.',
Is='Isawarriorr:BAACLgAFFH8FAAINAAMJJR1BFgDkAAANAAMJJR1BFgDkAAAuAAQKfywAAg0ACQmCI4kDAB8DAA0ACQmCI4kDAB8DAAAA.Ishaq:BAAALgAECgQJBQABLgAECggJIAAfAF4FAA==.Ishdo:BAAALgAECgUJBgABLgAECggJIAAfAF4FAA==.Ishdu:BAAALgAECgQJBAABLgAECggJIAAfAF4FAA==.Ishkhan:BAABLgAECn8gAAMfAAgJXgWlQQDxAAAfAAgJ4QSlQQDxAAAGAAYJUQXxXQCcAAAAAA==.Ishmael:BAACLgAFFH8KAAMNAAMJjxmWGQDEAAANAAMJjxmWGQDEAAAFAAEJiw1DUQBEAAAuAAQKfxQAAwUACQk6Hu4VAD8CAAUACQkwHO4VAD8CAA0AAglmGyQ7AIIAAAAA.Ishwar:BAAALgADCgYJBgABLgAECggJIAAfAF4FAA==.',
Ja='Jakytreehorn:BAACLgAFFH8LAAMQAAcJrAXqSADEAAAQAAUJ5QPqSADEAAAVAAQJxQX5OQChAAAuAAQKfzkAAxUACQn9Fg8cAP4BABUACAn3Fw8cAP4BABAACQlCFQwoAPABAAAA.Jasher:BAAALgAECgYJBgAAAA==.Jaydm:BAABLgAECn8dAAIkAAYJRxj1HgBiAQAkAAYJRxj1HgBiAQABLgAFFAgJFgAOAOwMAA==.',
Je='Jenevelle:BAAALgAECgYJCQAAAA==.Jerisil:BAAALgADCgQJBAAAAA==.Jet:BAABLgAECn8aAAIBAAYJ6CAySwABAgABAAYJ6CAySwABAgAAAA==.',
Ji='Jibbajabba:BAAALgADCgcJBwAAAA==.Jimbo:BAABLgAFFH8KAAIaAAMJDh+wWwAMAQAaAAMJDh+wWwAMAQABLgAFFAgJIAACAF8fAA==.',
Jo='Johnmayer:BAAALgADCgcJDwAAAA==.',
Ju='Judgecalypso:BAAALgAECgQJBgAAAA==.Judgiah:BAAALgAECgUJBQAAAA==.Julthaenia:BAABLgAECn8lAAQlAAcJZx/xBQAhAgAlAAcJZx/xBQAhAgAcAAQJGAr1SwCJAAAaAAUJcQvz8AB8AAABLgAFFAQJCwADAAobAA==.Justeatjuan:BAAALgAECgMJAwAAAA==.',
Ka='Kagebushin:BAAALgAECgMJBAAAAA==.Kalazin:BAAALgAECgUJBQAAAA==.Kalimah:BAAALgADCgMJAwAAAA==.Kalofelement:BAAALgAECgcJCAAAAA==.Karash:BAAALgAECgYJBgABLgAECggJFQAZAJ4OAA==.Karmaisab:BAAALgADCgEJAQAAAA==.Karnrae:BAACLgAFFH8HAAIBAAIJMwwfjgCOAAABAAIJMwwfjgCOAAAuAAQKfyoAAgEACQkrEqNQANQBAAEACQkrEqNQANQBAAAA.Karynos:BAABLgAECn8nAAMaAAkJyQ2yUwCgAQAaAAkJmgyyUwCgAQAcAAcJyQkOIwA/AQAAAA==.Katnelly:BAAALgAECgMJAwAAAA==.Kazmacoryy:BAAALgAECgYJEAAAAA==.',
Ke='Keedis:BAAALgADCggJCwAAAA==.Keristrasza:BAAALgAFFAEJAQABLgAFFAgJKAAQAOYbAA==.',
Kh='Khlarm:BAAALgADCgIJAgABLgAECgkJLQAdALkYAA==.',
Ki='Kileely:BAAALgAECgMJAwAAAA==.Kirintore:BAAALgAECgUJCQAAAA==.',
Kk='Kkaiser:BAAALgAECgQJBAAAAA==.',
Kl='Klaudeus:BAAALgAECgEJAQAAAA==.',
Ko='Kodian:BAAALgADCgEJAQAAAA==.Kolypso:BAABLgAECn8aAAIdAAkJoBWDLgAeAgAdAAkJoBWDLgAeAgAAAA==.Konceal:BAAALgAECgEJAQAAAA==.Konspiracy:BAABLgAECn8pAAIcAAkJpxaBBgD0AQAcAAkJpxaBBgD0AQAAAA==.Konvict:BAAALgAECgIJAwABLgAECgYJDQATAAAAAA==.',
Kr='Krataar:BAABLgAECn8hAAIFAAkJEyFgDACiAgAFAAkJEyFgDACiAgAAAA==.Kravvan:BAAALgAECgUJCgABLgAECggJHwAOALAIAA==.Krousvor:BAAALgAECgQJBwAAAA==.Kryph:BAABLgAECn8dAAICAAkJQAgTeABxAQACAAkJQAgTeABxAQAAAA==.',
Ku='Kugruk:BAAALgAECgcJDAAAAA==.Kurjo:BAAALgAECgMJBAAAAA==.',
Ky='Kyleschlong:BAAALgAECgMJCAAAAA==.Kyndreith:BAAALgAECgMJAwAAAA==.',
['Kä']='Kämpfer:BAABLgAECn9QAAIFAAkJFiHbBwDgAgAFAAkJFiHbBwDgAgAAAA==.',
La='Lafiel:BAABLgAECn8dAAMEAAkJGgtKPABJAQAEAAkJGgtKPABJAQAJAAIJ1Qh8dABTAAAAAA==.Landiedoo:BAAALgAECgkJCgAAAA==.Laurana:BAAALgADCgYJBgAAAA==.Laurandre:BAAALgAECgcJBwAAAA==.Laverna:BAAALgADCgMJBAAAAA==.Lazeras:BAAALgAECgUJCQABLgAFFAEJAgATAAAAAA==.',
Le='Lefay:BAAALgADCgcJFwAAAA==.Leprawnjames:BAAALgAECgIJAgABLgAECgkJGQASAKofAA==.Letsgetwet:BAAALgADCgYJBgAAAA==.',
Li='Liefic:BAAALgAECgcJCQAAAA==.Lillavender:BAAALgADCgYJBgAAAA==.Limon:BAAALgADCgIJAgAAAA==.',
Lo='Loadin:BAAALgAECgIJAgAAAA==.Lockaflockå:BAAALgADCgMJAwAAAA==.Locke:BAAALgAECgMJAgABLgAECgYJGgABAOggAA==.Lonoh:BAAALgAECgcJEgAAAA==.',
Lu='Luan:BAAALgADCgEJAQAAAA==.Lucariø:BAAALgADCgcJDAAAAA==.Lucidbonsai:BAAALgADCggJCAAAAA==.Luckykilla:BAABLgAECn8mAAImAAkJHhkEBQAwAgAmAAkJHhkEBQAwAgAAAA==.Lucÿ:BAACLgAFFH8RAAIQAAYJKBANHQB8AQAQAAYJKBANHQB8AQAuAAQKfyIAAxAABwmsGPQoAOwBABAABwmsGPQoAOwBABUAAwkVDCB3AIIAAAAA.Lula:BAAALgADCgMJAwAAAA==.Lurith:BAABLgAECn9JAAMUAAkJBBfjEgDfAQAUAAkJLRXjEgDfAQACAAgJEA234ADQAAAAAA==.Lutreaux:BAAALgADCgEJAQAAAA==.Luxtyrannica:BAABLgAECn8nAAIBAAkJMx4TFQDCAgABAAkJMx4TFQDCAgAAAA==.',
Ly='Lydrain:BAAALgAECgEJAQAAAA==.Lysandria:BAABLgAECn8rAAIOAAkJmw1IaQCmAQAOAAkJmw1IaQCmAQAAAA==.',
Ma='Macrosblack:BAAALgADCgMJAwAAAA==.Madamerouge:BAAALgAECgIJAgABLgAECgYJGQAgAIcVAA==.Magearino:BAABLgAECn8nAAIOAAgJnRYZXgDCAQAOAAgJnRYZXgDCAQAAAA==.Malafore:BAAALgADCgEJAQAAAA==.Malcolm:BAAALgAECgEJAQABLgAECgkJKwAFABkVAA==.Malcrux:BAAALgAECgIJAgAAAA==.Marcopally:BAAALgAECgQJBAAAAA==.Marluxia:BAACLgAFFH8hAAISAAYJbQyjEAD7AAASAAYJbQyjEAD7AAAuAAQKfxoAAhIACAkhE/YMALkBABIACAkhE/YMALkBAAAA.Mastamonk:BAAALgAECgQJBAAAAA==.Materfamilia:BAAALgAECgQJBAAAAA==.Mattbull:BAACLgAFFH8JAAMXAAMJ0Rh1OQDeAAAXAAMJ0Rh1OQDeAAAhAAEJ1xNICQBXAAAuAAQKfx4AAyEABgmqJFcNAAQCACEABglCIlcNAAQCABcABgl5IisgANYBAAAA.Mayu:BAAALgAECgEJAQAAAA==.',
Me='Medjrab:BAACLgAFFH8UAAICAAUJxhihXwAzAQACAAUJxhihXwAzAQAuAAQKfzIAAgIACQlLIqwSANcCAAIACQlLIqwSANcCAAAA.Meristem:BAABLgAECn8xAAIIAAkJiw9pIQC5AQAIAAkJiw9pIQC5AQAAAA==.Merko:BAAALgADCgkJDwAAAA==.',
Mi='Miaan:BAAALgADCgYJBgAAAA==.Miette:BAAALgADCgMJAwAAAA==.Mihonk:BAAALgADCgQJBAAAAA==.Mintycrx:BAABLgAECn8fAAIOAAkJHhFPUgDiAQAOAAkJHhFPUgDiAQAAAA==.Missfist:BAAALgADCgIJAgAAAA==.Mistlocke:BAAALgADCgMJAwAAAA==.',
Mn='Mngwa:BAAALgAECgQJCwAAAA==.',
Mo='Moegu:BAABLgAECn8cAAInAAkJFBb9BwD3AQAnAAkJFBb9BwD3AQAAAA==.Mog:BAACLgAFFH8JAAMaAAMJLSD5fgDCAAAaAAIJwSL5fgDCAAAlAAEJBxtBHwBQAAAuAAQKfzkABBoACQmeI1oVAKMCABoABwnVI1oVAKMCACUAAwmVIyIYAP4AABwAAwkJEsI2ANsAAAAA.Mogma:BAAALgAECgQJBAAAAA==.Moncatsera:BAAALgAECgQJBAAAAA==.Mondgrille:BAAALgAECgQJBAABLgAECgYJDQATAAAAAA==.Monora:BAABLgAECn8ZAAIZAAcJfgvSVAAUAQAZAAcJfgvSVAAUAQAAAA==.Montress:BAABLgAECn8UAAIEAAgJBhBQJwCGAQAEAAgJBhBQJwCGAQAAAA==.Moomoohealz:BAACLgAFFH8NAAIIAAMJ8RkPKgDhAAAIAAMJ8RkPKgDhAAAuAAQKfz4AAggACQkoIQ4IANECAAgACQkoIQ4IANECAAAA.Moonbounds:BAACLgAFFH8oAAIQAAgJ5htCAwCbAgAQAAgJ5htCAwCbAgAuAAQKfzgAAxAACQndJFEDAEQDABAACQndJFEDAEQDABUAAQnZH4Z5AF0AAAAA.Moondoggey:BAAALgAECgMJAwAAAA==.Morgana:BAAALgADCgIJAgAAAA==.Mousechief:BAABLgAECn87AAIVAAgJAgcETQD9AAAVAAgJAgcETQD9AAAAAA==.Moxnix:BAABLgAECn8VAAMZAAgJng7fUwAYAQAZAAcJXgzfUwAYAQAfAAQJjgVqXACZAAAAAA==.Moxxzi:BAAALgAFFAEJAgAAAA==.',
Mu='Muhfookinbak:BAABLgAECn8kAAMQAAkJFyBwEADJAgAQAAkJFyBwEADJAgAVAAQJhxg6XADMAAAAAA==.',
My='Myor:BAAALgADCgMJAwAAAA==.',
['Mà']='Màttbull:BAABLgAFFH8HAAIMAAMJcw44ZQC9AAAMAAMJcw44ZQC9AAABLgAFFAMJCQAXANEYAA==.',
['Mä']='Märcøsferätv:BAAALgAECgEJAQAAAA==.',
Na='Naesta:BAAALgAECgIJAgABLgAECggJIQAHAP4fAA==.Naksu:BAEALgAECgEJAQABLgAECggJJAAMAH8IAA==.Naksù:BAEBLgAECn8kAAIMAAgJfwgligAHAQAMAAgJfwgligAHAQAAAA==.Namal:BAAALgAECgQJBQAAAA==.Narenae:BAABLgAECn8lAAIGAAkJCyRABABIAwAGAAkJCyRABABIAwAAAA==.Nastalan:BAAALgADCgYJCgAAAA==.',
Ne='Nefari:BAAALgADCgMJAwAAAA==.Neifeb:BAABLgAECn8oAAIdAAkJehYpOgDyAQAdAAkJehYpOgDyAQAAAA==.Nephthys:BAAALgADCgQJBAAAAA==.',
Ni='Niallivdam:BAABLgAECn8tAAMhAAgJWhtBBAAzAgAhAAgJWhtBBAAzAgAWAAYJ0heQEwCNAQAAAA==.Nights:BAAALgAECgIJAgABLgAFFAYJFAABABcWAA==.Nightsoul:BAAALgADCgEJAQAAAA==.Ninh:BAACLgAFFH8NAAIZAAMJkgO9SgBtAAAZAAMJkgO9SgBtAAAuAAQKf1UAAhkACQn6FEccADACABkACQn6FEccADACAAAA.',
No='Nomissius:BAAALgADCgcJDQAAAA==.Nooblè:BAAALgADCgMJAwAAAA==.Notsodemon:BAABLgAECn8eAAMMAAgJfxRyUgCLAQAMAAgJfxRyUgCLAQADAAIJnwrPYwBUAAAAAA==.Notsoevoker:BAAALgAECgMJAwABLgAECggJHgAMAH8UAA==.Notsomonk:BAAALgADCgMJAwABLgAECggJHgAMAH8UAA==.',
Ny='Nykara:BAAALgAECgUJBQAAAA==.',
['Nå']='Nåld:BAAALgAECgUJCwAAAA==.',
Oa='Oakendorf:BAAALgAECgEJAQABLgAECgEJAgATAAAAAA==.',
Ob='Obvinotagirl:BAAALgAECggJDwAAAA==.',
Od='Oddpocalypse:BAAALgAECgEJAgAAAA==.',
Og='Ogsikko:BAAALgAECgYJCwABLgAECggJGAAaAJAeAA==.Ogsikkotv:BAABLgAECn8YAAIOAAYJ/BmQhwDCAQAOAAYJ/BmQhwDCAQABLgAECggJGAAaAJAeAA==.',
Ok='Okathra:BAAALgAECgQJBAABLgAFFAMJCAAeAGgbAA==.',
On='Onebadmutha:BAABLgAECn8ZAAIaAAkJ+AwyUgCkAQAaAAkJ+AwyUgCkAQAAAA==.Ontop:BAABLgAECn8oAAIdAAkJ7xsaHABeAgAdAAkJ7xsaHABeAgAAAA==.',
Or='Orb:BAABLgAECn8vAAQBAAkJKhmDQQAAAgABAAkJLRiDQQAAAgAPAAgJexIrJwDOAQALAAYJlQ/EHgATAQAAAA==.Orcfreeza:BAAALgAECgQJDAAAAA==.Ortinks:BAABLgAECn8lAAIOAAgJqRGpZwCqAQAOAAgJqRGpZwCqAQAAAA==.',
Ow='Owneege:BAACLgAFFH8dAAIFAAgJByC5AQCLAgAFAAgJByC5AQCLAgAuAAQKfzMAAgUACQkEIx4CAKADAAUACQkEIx4CAKADAAAA.',
Pa='Painsaw:BAAALgADCgYJBgAAAA==.Pallinar:BAABLgAECn83AAIBAAkJGhVtPQANAgABAAkJGhVtPQANAgAAAA==.Pandamak:BAAALgAECgEJAQAAAA==.Pasquale:BAABLgAECn8hAAIfAAcJRSG6FAAGAgAfAAcJRSG6FAAGAgAAAA==.',
Pe='Pebbles:BAABLgAECn8hAAIBAAgJsBgZQwD6AQABAAgJsBgZQwD6AQAAAA==.Pedroia:BAABLgAECn8WAAQmAAgJcwtVDABlAQAmAAgJcwtVDABlAQARAAcJzgQgNQD9AAAjAAIJNAf7HgBSAAAAAA==.Peridaxx:BAAALgAECgIJAgAAAA==.Pesty:BAAALgAECgMJCQAAAA==.',
Ph='Phe:BAABLgAECn8XAAMIAAcJhw4xOwAhAQAIAAcJhw4xOwAhAQAHAAYJpQvzcAADAQAAAA==.Pheraree:BAAALgAECgEJAQAAAA==.Phooboo:BAAALgAECgkJBQAAAA==.',
Pi='Pidion:BAAALgADCgYJDAAAAA==.Pilgrimm:BAECLgAFFH8bAAMjAAcJ9xujAQC+AQAjAAYJ+RqjAQC+AQARAAQJ+B4gCwA4AQAuAAQKfyQAAxEACQl7IrIDAGADABEACQl0IrIDAGADACMABQkIHxYLAGgBAAAA.Pixyl:BAAALgAECgIJAgAAAA==.',
Pl='Plaguerott:BAABLgAECn83AAIoAAkJeA+pDQCYAQAoAAkJeA+pDQCYAQAAAA==.Plusultra:BAAALgADCgkJEQAAAA==.Pluto:BAAALgAFFAQJBAAAAA==.',
Po='Poby:BAAALgADCgcJBwAAAA==.Polydh:BAABLgAECn8wAAInAAkJriTuAAA9AwAnAAkJriTuAAA9AwAAAA==.Poobah:BAABLgAECn8jAAMVAAgJvAarVwDZAAAVAAcJfAarVwDZAAAQAAcJCgO6hwDHAAAAAA==.Popscotch:BAABLgAECn8jAAMlAAkJEg3OCQCkAQAlAAcJRg7OCQCkAQAaAAkJwAu1WwCKAQAAAA==.Pouffant:BAABLgAECn8iAAIBAAkJyBMrVgDGAQABAAkJyBMrVgDGAQAAAA==.',
Pr='Pronoz:BAABLgAECn8kAAIBAAcJfRLmkQBMAQABAAcJfRLmkQBMAQAAAA==.',
Pu='Punchy:BAAALgADCgEJAQAAAA==.',
Pw='Pwnageddon:BAABLgAECn8yAAMLAAgJ2h5+CABLAgALAAcJkyJ+CABLAgABAAUJhxUW4gDJAAAAAA==.Pwnjitsu:BAACLgAFFH8IAAIGAAMJ2R7KFQAMAQAGAAMJ2R7KFQAMAQAuAAQKfzwAAgYACQk8JS0CAEsDAAYACQk8JS0CAEsDAAAA.',
Py='Pyrothermia:BAACLgAFFH8WAAIOAAgJ7AyrHgAGAgAOAAgJ7AyrHgAGAgAuAAQKfyYAAg4ACQn/HIoqAMgCAA4ACQn/HIoqAMgCAAAA.',
['Pô']='Pôlgara:BAAALgADCgYJBgABLgAECggJKQAPAOseAA==.',
Qt='Qtkillz:BAAALgADCgQJBAAAAA==.',
Qu='Quinlekd:BAAALgAECgQJBAABLgAECggJLwAaAJ0jAA==.',
Ra='Rancayden:BAAALgAECgMJBAAAAA==.Rawhoof:BAACLgAFFH8NAAIFAAMJFSCiKgAEAQAFAAMJFSCiKgAEAQAuAAQKf1UAAgUACQlHJpsBAGYDAAUACQlHJpsBAGYDAAAA.Razak:BAACLgAFFH8IAAIeAAMJaBstDAD5AAAeAAMJaBstDAD5AAAuAAQKfzoAAh4ACQniI1EBACwDAB4ACQniI1EBACwDAAAA.',
Re='Redlock:BAAALgAECgMJAwAAAA==.Redtiger:BAAALgADCgYJBgAAAA==.Renisa:BAABLgAECn8iAAIMAAgJqRkYUQCPAQAMAAgJqRkYUQCPAQAAAA==.Retman:BAABLgAECn8UAAIBAAcJtg/S7gDJAAABAAcJtg/S7gDJAAAAAA==.Reu:BAAALgAECgUJBwAAAA==.Revlyk:BAABLgAECn8nAAIeAAgJFiNdBACpAgAeAAgJFiNdBACpAgABLgAFFAQJCwADAAobAA==.Rezloh:BAAALgAECgkJDAAAAA==.',
Rh='Rhoanna:BAAALgADCgUJBwAAAA==.',
Ri='Rinja:BAAALgADCgYJBgAAAA==.Rintaro:BAABLgAECn8kAAILAAkJrAttGwA4AQALAAkJrAttGwA4AQAAAA==.Ritanana:BAAALgAECgIJAgAAAA==.',
Ro='Roccot:BAAALgAECggJDgAAAA==.Roflstomp:BAAALgAECgQJBwABLgAECgkJGQASAKofAA==.Roostrr:BAABLgAECn8XAAIBAAYJ4B2EcwCUAQABAAYJ4B2EcwCUAQAAAA==.Rotfather:BAAALgADCgYJBgAAAA==.Rotjaw:BAAALgAECgUJCwAAAA==.Roughedge:BAAALgADCgIJAgAAAA==.',
Ru='Rurik:BAAALgAECgEJAQAAAA==.',
['Rä']='Rävthor:BAAALgAFFAEJAQAAAA==.Rävthör:BAAALgAECgYJBgAAAA==.',
['Rè']='Rèjuva:BAAALgAECgcJDQAAAA==.Rèptílè:BAAALgADCgMJAwABLgAFFAMJBwAdAA8iAA==.',
['Rî']='Rîcflair:BAAALgAECgcJEwAAAA==.',
Sa='Saiyax:BAAALgADCgYJBwAAAA==.Salidfingers:BAAALgADCgYJBgAAAA==.Sanyakulak:BAAALgADCgcJBwABLgAFFAgJGwASABcWAA==.Sanzo:BAAALgAECgEJAQAAAA==.Savathûn:BAAALgAECgQJCAAAAA==.',
Sc='Scalycat:BAACLgAFFH8JAAMWAAMJkA4yIACgAAAWAAMJkA4yIACgAAAXAAMJjgG+UgB5AAAuAAQKfyoABBYACQnYDpwZAMEBABYACQnYDpwZAMEBABcABwksBlhlAKYAACEAAgluB1snAC0AAAAA.Schalla:BAAALgAECgEJAQAAAA==.Scum:BAAALgAECgYJDQAAAA==.Scòrpìòn:BAAALgADCgcJBgABLgAFFAMJBwAdAA8iAA==.',
Se='Seancody:BAAALgADCgIJAgAAAA==.Sekhmett:BAABLgAECn8aAAMiAAgJvgMcDgCQAAAOAAgJFwOT1QDmAAAiAAYJ1gMcDgCQAAAAAA==.Selandria:BAAALgADCgQJBAAAAA==.Senate:BAAALgAECgYJCwAAAA==.',
Sh='Shablaam:BAAALgADCgQJBAAAAA==.Shadowbear:BAABLgAECn8cAAIJAAcJ/RyeHwDHAQAJAAcJ/RyeHwDHAQAAAA==.Shadowoss:BAAALgAECgYJCAAAAA==.Shadygrump:BAAALgAECgYJEQAAAA==.Shamdeaus:BAAALgADCgUJBQABLgAECgkJLQAdALkYAA==.Shammacass:BAAALgAECgUJBQAAAA==.Shamwick:BAAALgAECgYJCgAAAA==.Shaolincito:BAAALgAECgQJCAAAAA==.Sherrilyn:BAAALgAECgQJBAAAAA==.Shocklocke:BAAALgAECgQJBAAAAA==.',
Si='Sigmachad:BAAALgAECgUJDwAAAA==.Silandrus:BAAALgAECgMJBAAAAA==.Silverocean:BAABLgAECn8zAAIPAAkJMRzqDwCUAgAPAAkJMRzqDwCUAgAAAA==.Silvia:BAAALgADCgUJCQAAAA==.Singularity:BAACLgAFFH8NAAINAAMJPCR7EAAjAQANAAMJPCR7EAAjAQAuAAQKf1IAAg0ACQltJokAAHYDAA0ACQltJokAAHYDAAAA.',
Sk='Skaerx:BAABLgAECn8WAAMFAAYJVBeOQwCXAQAFAAYJ9RWOQwCXAQAkAAQJZhSYHQADAQAAAA==.Skittlez:BAABLgAECn8mAAIYAAkJkR+iCQCDAgAYAAkJkR+iCQCDAgABLgAFFAMJBAATAAAAAA==.',
Sl='Slaykween:BAABLgAECn8YAAILAAgJGwtoIAANAQALAAgJGwtoIAANAQAAAA==.Slootybooty:BAABLgAECn8ZAAISAAkJqh8GBQC8AgASAAkJqh8GBQC8AgAAAA==.',
Sm='Smallz:BAAALgAECgYJEQABLgAECggJHwAOALAIAA==.',
Sn='Snipersmash:BAAALgAECgQJCAAAAA==.Snooptrogg:BAABLgAECn8rAAIFAAkJGRUgIwDYAQAFAAkJGRUgIwDYAQAAAA==.Snoozumi:BAABLgAFFH8GAAIZAAMJKQbRRgB+AAAZAAMJKQbRRgB+AAAAAA==.Snuups:BAABLgAECn9DAAIaAAkJAhqaLgAcAgAaAAkJAhqaLgAcAgAAAA==.',
So='Soldiah:BAABLgAECn8bAAIFAAgJrQ24NwBnAQAFAAgJrQ24NwBnAQAAAA==.Sommbra:BAAALgAECgYJBwAAAA==.Souljax:BAAALgADCgcJCQAAAA==.',
Sp='Spacelaser:BAAALgAECgQJBQAAAA==.',
Sq='Sqwurl:BAAALgADCgQJBAAAAA==.',
St='Steakhaus:BAAALgADCgkJCwAAAA==.Stiros:BAAALgAECgMJAwAAAA==.Stonedragon:BAECLgAFFH8SAAMdAAYJuxqZCwAGAQAdAAUJdiCZCwAGAQAKAAEJzwPzNABGAAAuAAQKf0MAAx0ACAlyJcwFADEDAB0ACAlyJcwFADEDAAoACAkPIIsDAI8CAAAA.Stormfist:BAABLgAECn8ZAAIOAAkJ3BCaTgDtAQAOAAkJ3BCaTgDtAQAAAA==.Stormhaven:BAAALgADCggJKgABLgAECggJKQAPAOseAA==.Stormrender:BAAALgAECgYJEAAAAA==.Stormstag:BAAALgADCgYJBgAAAA==.Stouty:BAAALgADCgMJAwABLgAECgcJFAAhAOkaAA==.',
Su='Sukonamí:BAABLgAECn8iAAMFAAkJghckKAAdAgAFAAgJdhUkKAAdAgAkAAQJGhtUKAApAQAAAA==.Suxtosuck:BAAALgAECgkJBwAAAA==.Suzhou:BAABLgAECn8jAAIcAAgJowlhFAAGAQAcAAgJowlhFAAGAQAAAA==.Suzoomies:BAAALgADCgcJBwAAAA==.Suzumii:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetcarolin:BAABLgAECn8WAAICAAkJRg+GXgDXAQACAAkJRg+GXgDXAQAAAA==.Sweetsmercy:BAAALgAECgQJBQAAAA==.Swiftleaf:BAAALgADCgcJBwAAAA==.Swisscheese:BAABLgAECn8vAAIaAAgJnSNpEADIAgAaAAgJnSNpEADIAgAAAA==.',
Sy='Syraxa:BAAALgAECgQJBwABLgAFFAMJDgAHAEcRAA==.Syril:BAAALgADCgcJDAAAAA==.',
Ta='Taedish:BAAALgADCgMJAwAAAA==.Tahret:BAAALgADCgQJBQAAAA==.Talorien:BAAALgAECgEJAQABLgAFFAMJBwAOABIXAA==.Taquillya:BAAALgAECgQJBQAAAA==.Tarina:BAAALgADCgEJAQAAAA==.Tatersaladin:BAAALgADCgMJAwAAAA==.',
Te='Tenlortin:BAAALgAECgEJAQABLgAECgYJBgATAAAAAA==.Terragosa:BAABLgAECn83AAIOAAkJ5xk/LQBiAgAOAAkJ5xk/LQBiAgAAAA==.Teryail:BAAALgAECgEJAQAAAA==.Tetchybono:BAAALgADCgYJBgAAAA==.',
Th='Thade:BAABLgAECn8kAAMkAAkJByGyBQCqAgAkAAgJGiCyBQCqAgAFAAgJfB5XHwBWAgAAAA==.Thaeleon:BAABLgAECn8hAAMIAAgJbx8/EgBCAgAIAAgJbx8/EgBCAgAHAAYJixz+NADUAQABLgAFFAMJCgANAI8ZAA==.Thahawtz:BAAALgADCggJCAAAAA==.Thanattos:BAAALgADCgcJDgAAAA==.Thaneblade:BAAALgAECgQJBgAAAA==.Therizzler:BAAALgAECgcJCQABLgAFFAMJDwAMADoWAA==.Thickening:BAABLgAECn8ZAAMZAAUJhQ2RZwDXAAAZAAUJhQ2RZwDXAAAGAAUJ9QehXwCYAAAAAA==.Thirinis:BAAALgADCgYJBgAAAA==.Thope:BAABLgAECn8lAAIOAAcJ7QqxowAyAQAOAAcJ7QqxowAyAQAAAA==.Thoranubran:BAABLgAECn8aAAIDAAYJABKOLgALAQADAAYJABKOLgALAQAAAA==.Thrivia:BAAALgAECgYJBgAAAA==.',
Ti='Ticklemychin:BAAALgAECgYJDQAAAA==.Tigani:BAAALgAECgUJDAAAAA==.Tinstey:BAAALgADCgcJBwAAAA==.Titantu:BAAALgAECgYJBgABLgAFFAMJBgAIAHMFAA==.',
To='Toestiir:BAAALgAECgYJCQAAAA==.Tokemaddab:BAAALgADCgUJBQAAAA==.Toughasnails:BAAALgAECgEJAgAAAA==.',
Tr='Traesdyne:BAAALgAECgEJAQABLgAECgMJAwATAAAAAA==.Trainar:BAAALgAECgQJCQAAAA==.Trazle:BAAALgAECgMJAwAAAA==.Trekkiegeek:BAAALgAECgIJAwAAAA==.Trickybackup:BAAALgADCgMJAwAAAA==.Triggs:BAAALgAECgcJBwAAAA==.Trollbear:BAABLgAECn8WAAIHAAgJhBWAKAALAgAHAAgJhBWAKAALAgAAAA==.Trondruid:BAAALgADCgYJDQAAAA==.Trooze:BAABLgAECn87AAIPAAkJLiNEAwBsAwAPAAkJLiNEAwBsAwAAAA==.Trr:BAABLgAECn8pAAIaAAkJmBe2IwCFAgAaAAkJmBe2IwCFAgAAAA==.Truckz:BAAALgADCgEJAQABLgAECgkJQAAdAE0gAA==.Truckzage:BAAALgADCgcJBwABLgAECgkJQAAdAE0gAA==.',
Tu='Tuba:BAAALgAECgYJEAAAAA==.Turim:BAAALgAECgcJEwAAAA==.Tusksrus:BAAALgADCgcJFwAAAA==.',
Ty='Tyrlidd:BAABLgAECn84AAIdAAkJERa+LQAiAgAdAAkJERa+LQAiAgAAAA==.',
Ud='Udon:BAACLgAFFH8GAAMCAAQJmguXdQAVAQACAAQJmguXdQAVAQAoAAEJkQGTKwAyAAAuAAQKfyIAAwIABwkQGhJqAI8BAAIABgm4GhJqAI8BACgABQk6FiUXABoBAAAA.',
Ug='Ugoar:BAAALgAECgcJBwAAAA==.',
Ul='Ultimazero:BAAALgADCgEJAQAAAA==.',
Un='Unavoidable:BAAALgADCgkJEQAAAA==.Unlikelytale:BAABLgAECn8mAAIQAAkJAyEuCgDXAgAQAAkJAyEuCgDXAgAAAA==.Unmilked:BAAALgAECgYJBwAAAA==.',
Ur='Uricash:BAACLgAFFH8GAAIOAAMJcBgrcwD9AAAOAAMJcBgrcwD9AAAuAAQKf1AAAg4ACQmWIBURAPICAA4ACQmWIBURAPICAAAA.Urzual:BAABLgAECn8rAAIeAAkJDyDPBQB+AgAeAAkJDyDPBQB+AgAAAA==.',
Ut='Utiniócast:BAAALgAECgQJBAAAAA==.',
Va='Vandreynna:BAACLgAFFH8LAAIDAAQJChtpCwBPAQADAAQJChtpCwBPAQAuAAQKf1IAAgMACQnWJUIBAGoDAAMACQnWJUIBAGoDAAAA.',
Ve='Vegèta:BAABLgAECn8gAAICAAkJZAuWgABfAQACAAkJZAuWgABfAQABLgAFFAMJBwAdAA8iAA==.Veilaura:BAAALgAECgcJDAAAAA==.Velarria:BAABLgAECn8jAAMdAAkJ4h43FQCOAgAdAAkJ4h43FQCOAgAYAAQJBA8cIQDSAAAAAA==.Velikan:BAAALgAECgQJBwABLgAECgcJCAATAAAAAA==.Velsiana:BAAALgAECgcJEwAAAA==.Velveetah:BAAALgAECgUJCAABLgAECgYJGQAEAJ4PAA==.Verbrennen:BAAALgAECgUJDgABLgAECgkJUAAFABYhAA==.Verdreht:BAAALgADCgEJAQABLgAECgkJUAAFABYhAA==.Verita:BAABLgAECn8zAAIjAAgJXiMSAgCyAgAjAAgJXiMSAgCyAgAAAA==.Verlynne:BAAALgADCgYJBgAAAA==.Verylikely:BAAALgAECgEJAgAAAA==.',
Vi='Viviann:BAABLgAECn8kAAIWAAkJeRE1EADFAQAWAAkJeRE1EADFAQAAAA==.',
Vo='Voiager:BAAALgADCgcJCgAAAA==.',
Vr='Vrakal:BAAALgAECgkJDQAAAA==.',
Wa='Wantabehavoc:BAAALgADCgYJDQAAAA==.Wantadeznutz:BAAALgAECgIJAgAAAA==.Warnick:BAAALgADCgQJBQAAAA==.Warraxe:BAAALgAECgEJAgAAAA==.Wayloren:BAABLgAECn8qAAIBAAkJzAqaeQB5AQABAAkJzAqaeQB5AQAAAA==.Waystalker:BAAALgAECgMJAwAAAA==.Wayverly:BAAALgADCgUJBwABLgAECgkJHwAKAMoIAA==.',
Wi='Wickathy:BAABLgAECn9GAAMnAAkJbSDNAgDEAgAnAAkJbSDNAgDEAgAMAAMJlg/7wQCkAAAAAA==.',
Wo='Wolfcity:BAAALgADCgEJAQAAAA==.Wondertauren:BAAALgADCgYJCQAAAA==.Woodson:BAAALgADCgkJEAAAAA==.Worstdps:BAAALgAFFAIJAwAAAA==.',
Wr='Wrkandtank:BAAALgAECgYJBgABLgAECggJFQAaAHcLAA==.',
Wu='Wuldorr:BAACLgAFFH8QAAIBAAQJexcDQAAlAQABAAQJexcDQAAlAQAuAAQKfyQAAgEACAm1H0gkAJYCAAEACAm1H0gkAJYCAAAA.',
Wy='Wynnifred:BAAALgAECggJDQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.',
Xe='Xethreal:BAAALgADCgMJAwAAAA==.',
Xy='Xype:BAAALgAECgkJEQAAAA==.',
Xz='Xzara:BAAALgAECgYJDAABLgAECgYJGQAGAAEcAA==.',
Ya='Yastoria:BAAALgAECgcJEAAAAA==.',
Yi='Yinandtonic:BAAALgAECgEJBAAAAA==.',
Yv='Yvvee:BAAALgADCgcJBwAAAA==.',
Za='Zaalim:BAAALgADCgQJBAAAAA==.Zaddy:BAAALgAECgEJAQAAAA==.Zapdôs:BAAALgAECgQJBAAAAA==.',
Ze='Zeda:BAAALgAECgYJEwABLgAECgYJGQAGAAEcAA==.Zephyris:BAAALgAECgUJDAABLgAFFAgJJQAkAGMhAA==.',
Zh='Zheng:BAAALgAECgYJBgAAAA==.',
Zi='Zillia:BAAALgADCgMJAwAAAA==.',
Zo='Zonora:BAABLgAECn8YAAIPAAkJlQ2WJwDLAQAPAAkJlQ2WJwDLAQAAAA==.',
Zy='Zyphexd:BAAALgAECgYJDwAAAA==.Zyris:BAAALgADCgcJDQAAAA==.',
['Àz']='Àzñós:BAAALgAECgQJBwAAAA==.',
['Äs']='Ästro:BAAALgAECgQJBgABLgAECgkJLQAGAHcaAA==.',
['Äz']='Äzrael:BAABLgAECn83AAIEAAkJUxwKCQDVAgAEAAkJUxwKCQDVAgAAAA==.',
['Åz']='Åznos:BAAALgAECgQJCAAAAA==.',
['Çr']='Çréwüsæðèr:BAABLgAECn8jAAINAAgJZiD4CgA7AgANAAgJZiD4CgA7AgAAAA==.',
['Ðe']='Ðecimus:BAAALgAECgQJCQAAAA==.',
['Ðì']='Ðìaßlo:BAACLgAFFH8HAAIdAAMJDyIZVwDvAAAdAAMJDyIZVwDvAAAuAAQKfzQABB0ACQljHQMcAHgCAB0ACAljHQMcAHgCABgABwlYFAQRALMBAAoAAQleABqbABUAAAAA.',
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
