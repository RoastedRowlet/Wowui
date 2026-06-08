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
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Aberaht:BAABLgAECn8mAAIBAAkJYCOqDQAgAwABAAkJYCOqDQAgAwAAAA==.',
Ad='Adamaro:BAAALgADCgYJCQAAAA==.',
Ae='Aenastian:BAAALgAFFAIJAwABLgAFFAQJCwACAAobAA==.',
Af='Affrica:BAAALgADCgEJAQABLgAECgYJGQADAJ4PAA==.',
Ag='Agnu:BAAALgADCgcJBwAAAA==.Agraar:BAAALgAECgQJBAAAAA==.',
Ah='Ahgra:BAABLgAECn89AAIBAAkJugyydAB5AQABAAkJugyydAB5AQAAAA==.',
Ak='Akre:BAAALgAFFAIJBgAAAQ==.Akumä:BAAALgAECgUJCgAAAA==.',
Al='Aleannia:BAAALgAECgUJBgAAAA==.Alekz:BAAALgAECgYJCgAAAA==.Alestria:BAABLgAECn8YAAIBAAcJFxUdhABcAQABAAcJFxUdhABcAQAAAA==.Alibrexia:BAACLgAFFH8IAAIEAAMJmgRyOACyAAAEAAMJmgRyOACyAAAuAAQKfyAAAgQACQlrCSEyAHwBAAQACQlrCSEyAHwBAAAA.Alida:BAABLgAECn8sAAIEAAkJqArtMwByAQAEAAkJqArtMwByAQAAAA==.Alithvia:BAAALgAECgYJBgABLgAECgkJJQAFAAskAA==.Allisara:BAAALgADCgkJFgAAAA==.Alysae:BAACLgAFFH8fAAMGAAYJNhwaDgAAAgAGAAYJNhwaDgAAAgAHAAEJSQAqUAAZAAAuAAQKfxsAAwYACAkrHeUdAE8CAAYACAkrHeUdAE8CAAcAAgllB/2PACgAAAAA.',
Am='Amabear:BAAALgAECgEJAQABLgAECgcJHAAIAP0cAA==.Ambrosse:BAAALgADCggJDwABLgAECgkJLQAFAHcaAA==.',
An='Anabug:BAAALgAECgMJBQAAAA==.Andelwynn:BAAALgAECgMJAwABLgAECgkJHgAJAF4IAA==.Angelsmentor:BAAALgAECgYJCQAAAA==.Aniellas:BAAALgAECgIJAgAAAA==.Annalese:BAAALgADCgUJCQABLgAECgkJHgAJAF4IAA==.',
Ar='Arabeli:BAAALgAECgEJAQAAAA==.Arbyss:BAAALgADCgcJDAAAAA==.Ardatha:BAAALgADCgcJFwAAAA==.Ariêz:BAAALgAECgIJAgAAAA==.Artio:BAAALgAECgUJBgAAAA==.',
As='Asterön:BAAALgAECgcJEwAAAA==.Astrocakes:BAAALgAECgMJAwABLgAFFAMJDQAKAG4VAA==.',
At='Athenä:BAACLgAFFH8iAAILAAgJ+w48AQDSAQALAAgJ+w48AQDSAQAuAAQKfzwAAgsACQl7HPkFAI4CAAsACQl7HPkFAI4CAAAA.Atsuma:BAABLgAECn8gAAIMAAgJIAsbIgASAQAMAAgJIAsbIgASAQAAAA==.',
Av='Avacynn:BAAALgAECgMJAwAAAA==.Aviz:BAAALgADCgMJAwAAAA==.',
Aw='Awtysmbb:BAAALgAECgUJBQABLgAECgkJKwANAGAaAA==.',
Ay='Aylli:BAAALgAECgUJBgABLgAECgkJMwADACEcAA==.',
['Aí']='Aísling:BAABLgAECn8pAAIOAAgJ6x5xDQCwAgAOAAgJ6x5xDQCwAgAAAA==.',
Ba='Baboii:BAAALgADCgIJAgAAAA==.Baconmecrazy:BAAALgAECgEJAQAAAA==.Badinngo:BAAALgADCggJDwABLgAECgkJJAAPABcgAA==.Bahiu:BAAALgAECgQJBAAAAA==.Bajafresh:BAAALgAECgQJBQAAAA==.Battleshaman:BAAALgADCgYJBgAAAA==.',
Bd='Bd:BAABLgAECn8dAAIQAAgJJxU5GABGAgAQAAgJJxU5GABGAgAAAA==.',
Be='Beardmedaddy:BAAALgAECgYJBgABLgAECgkJMAAEAI4hAA==.Bearstavious:BAAALgAFFAIJAgAAAA==.Benjinana:BAABLgAECn8ZAAMDAAYJng+vOAAJAQADAAYJng+vOAAJAQAIAAIJJQPOWgBMAAAAAA==.Betterthanu:BAAALgADCgUJBQABLgADCgYJCgARAAAAAA==.',
Bg='Bg:BAAALgAECgYJBwAAAA==.',
Bi='Bige:BAAALgAECgYJDgAAAA==.Bilo:BAAALgAECgYJCAAAAA==.Bitelyus:BAAALgAECgUJCAAAAA==.',
Bl='Blazara:BAAALgAECgEJAQAAAA==.Blessedbymom:BAAALgADCgEJAQAAAA==.',
Bo='Bobius:BAAALgAECgkJDwAAAA==.Bobohizan:BAAALgADCgQJBAAAAA==.Bohde:BAABLgAFFH8OAAMSAAUJ6iLZPQBoAQASAAQJ6iLZPQBoAQATAAEJAACSSgAAAAAAAA==.Bolognaman:BAAALgAECgUJCAAAAA==.Bombjovi:BAABLgAECn8gAAMLAAkJchWJDQDeAQALAAkJchWJDQDeAQAOAAUJlA/vUADqAAAAAA==.Bountty:BAAALgAECgQJBAAAAA==.',
Br='Brahmsthoven:BAAALgADCgIJAwAAAA==.Branndhon:BAABLgAECn8lAAIGAAcJdBVbNgC2AQAGAAcJdBVbNgC2AQAAAA==.',
Bt='Btrflyprncss:BAAALgADCgMJAwAAAA==.',
Bu='Bubblemedic:BAAALgADCgIJAgAAAA==.Budde:BAAALgAECgUJBQAAAA==.Buffaloseven:BAAALgAECgYJDwABLgAFFAgJFAANAOwMAA==.',
Ca='Cairdamane:BAABLgAECn8hAAIUAAkJ5BFALACFAQAUAAkJ5BFALACFAQAAAA==.Calidrina:BAABLgAECn8iAAIKAAkJMhx1PgDCAQAKAAkJMhx1PgDCAQAAAA==.Carm:BAAALgAECgYJBgAAAA==.Caroliná:BAAALgAECgUJCgAAAA==.Catcast:BAAALgAECgUJCAABLgAFFAMJBgAVAI4BAA==.Catclaw:BAAALgAECgEJAQABLgAFFAMJBgAVAI4BAA==.',
Ce='Celiri:BAABLgAECn8nAAIFAAkJrxAnHwCnAQAFAAkJrxAnHwCnAQAAAA==.Celldrassil:BAABLgAECn8zAAIGAAkJAQfbWQAgAQAGAAkJAQfbWQAgAQAAAA==.Cereel:BAAALgAECgMJAwABLgAFFAMJDQAKAG4VAA==.',
Ch='Chadaracka:BAAALgAECgYJBwAAAA==.Chandelure:BAAALgAECgUJCwAAAA==.Chardaney:BAABLgAECn8eAAIJAAkJXgh7EgApAQAJAAkJXgh7EgApAQAAAA==.Cherryontop:BAABLgAECn8mAAIGAAgJLBSzMADVAQAGAAgJLBSzMADVAQAAAA==.Chozenone:BAAALgAECgUJDwAAAA==.Chozi:BAAALgAECgYJBgAAAA==.Chromosomie:BAAALgAFFAIJAgABLgAECgkJMAANAOcbAA==.',
Ci='Cii:BAABLgAECn8VAAMLAAgJWRA/FwBZAQALAAgJ0Q4/FwBZAQABAAUJew2EzwDnAAAAAA==.',
Co='Coconutwater:BAAALgAFFAEJAQAAAA==.Colandros:BAABLgAECn89AAIWAAkJhQuBGgDFAQAWAAkJhQuBGgDFAQAAAA==.Colara:BAABLgAECn8dAAIKAAcJSwRusgC1AAAKAAcJSwRusgC1AAAAAA==.Combobreaker:BAACLgAFFH8IAAIXAAMJVx58JwAFAQAXAAMJVx58JwAFAQAuAAQKfzQAAhcACQm+H0sHABwDABcACQm+H0sHABwDAAAA.Comoo:BAAALgAECgEJAQAAAA==.Correct:BAAALgAECgEJAQAAAA==.Cowbôy:BAAALgADCgkJEQAAAA==.',
Cr='Crassberry:BAACLgAFFH8eAAISAAgJXx+1CAB8AgASAAgJXx+1CAB8AgAuAAQKfygAAhIACQk2JBQFAIMDABIACQk2JBQFAIMDAAAA.Crazyraptor:BAAALgAECgYJDAABLgAECggJFQAYAHcLAA==.Crazèd:BAAALgADCgQJBAAAAA==.Crimes:BAAALgAECgEJAgAAAA==.',
Cu='Cutco:BAAALgAFFAMJBAAAAA==.',
Cy='Cyndal:BAAALgAECgQJEAABLgAECgYJFgAFAMwbAA==.Cyndle:BAABLgAECn8WAAIFAAYJzBsnIgCSAQAFAAYJzBsnIgCSAQAAAA==.Cyntu:BAAALgAECgUJCgABLgAECgYJFgAFAMwbAA==.',
['Cü']='Cüpid:BAAALgAECgYJBgAAAA==.',
Da='Dada:BAAALgAECgEJAQAAAA==.Dammithells:BAAALgADCgQJBAAAAA==.Dandamar:BAAALgAECgYJBgAAAA==.Dankbuds:BAAALgAECgYJAgABLgAFFAIJAgARAAAAAA==.Dankfists:BAAALgAECgUJBQABLgAFFAIJAgARAAAAAA==.Dankhaze:BAAALgAFFAIJAgAAAA==.Dankzor:BAAALgAECgcJBQABLgAFFAIJAgARAAAAAA==.Dark:BAAALgADCgEJAQAAAA==.Darthrevan:BAAALgAECgQJBwAAAA==.Dasharnkal:BAAALgADCgUJCAAAAA==.Dasvult:BAAALgAECgMJBAAAAA==.Dazex:BAABLgAECn8eAAMDAAYJNQNHTAChAAADAAYJ6AJHTAChAAAZAAUJRwJnVgCQAAAAAA==.',
De='Deadpump:BAABLgAECn8fAAMYAAcJfRJscgBQAQAYAAcJfRJscgBQAQAaAAQJUQ4aOQDQAAAAAA==.Demonsnotkey:BAAALgAECgYJCwAAAA==.Demoxus:BAAALgAECgQJBAAAAA==.Denker:BAAALgADCggJCAAAAA==.Denkzilla:BAAALgADCgIJAgAAAA==.Denzvic:BAAALgAECgEJAQAAAA==.Destro:BAAALgAECgEJAQAAAA==.Deusclaw:BAAALgAECgYJCgAAAA==.Devilah:BAAALgAECgEJAQAAAA==.',
Dh='Dharm:BAABLgAECn8rAAMbAAcJvRqcVgCTAQAbAAcJvRqcVgCTAQAWAAIJxQzBTABzAAAAAA==.',
Di='Dialsl:BAAALgADCgUJBgAAAA==.Digbickpanda:BAAALgAECgUJBQABLgAFFAMJDQAKAG4VAA==.Disowneege:BAABLgAECn8fAAIBAAgJ0B9HIgBzAgABAAgJ0B9HIgBzAgABLgAFFAgJGwAEAMIfAA==.Diyos:BAAALgADCgYJCgAAAA==.',
Do='Dotndash:BAAALgADCgIJAgAAAA==.Doubledge:BAAALgAECgEJAQAAAA==.Doublejump:BAACLgAFFH8XAAIKAAUJjBPTQAAVAQAKAAUJjBPTQAAVAQAuAAQKfykAAgoACAk4HusjADUCAAoACAk4HusjADUCAAAA.',
Dr='Dragdh:BAAALgAECgcJEwABLgAECggJKgAcAJ8cAA==.Dragnas:BAABLgAECn8qAAQcAAgJnxxnCwDxAQAcAAgJnxxnCwDxAQAPAAcJrBSeOgC2AQAUAAQJvhYAWQDJAAAAAA==.Dragonisa:BAAALgAFFAEJAQAAAA==.Dragun:BAAALgADCgIJAgAAAA==.Draiocht:BAAALgADCgMJBAABLgAECgkJMwADACEcAA==.Drakeskid:BAAALgAECgQJBwABLgAFFAQJBgAdALgKAA==.Drakthall:BAAALgAECgIJAwAAAA==.Dralionethny:BAAALgAECgIJAgAAAA==.Dramakiller:BAABLgAECn8VAAMbAAYJIwk/lgAGAQAbAAYJIwk/lgAGAQAJAAMJPAKdNQA9AAAAAA==.Drchi:BAAALgAECgEJAQABLgAECgYJGQAeAIcVAA==.Drcornbread:BAABLgAECn8ZAAMeAAYJhxX4GAA1AQAeAAYJhxX4GAA1AQAfAAEJ0AOTfAATAAAAAA==.Drcornellia:BAAALgAECgUJCAABLgAECgYJGQAeAIcVAA==.Drdarkskin:BAAALgAECgcJDQAAAA==.Drdreggs:BAABLgAECn8pAAMaAAkJmBYiEAAyAQAYAAgJuBSYTwDZAQAaAAYJmxciEAAyAQAAAA==.Dreggs:BAAALgADCgcJEwAAAA==.Drizztin:BAAALgADCgEJAQAAAA==.Drprominus:BAABLgAECn8gAAIOAAgJACL8CADxAgAOAAgJACL8CADxAgAAAA==.Drthargyll:BAAALgADCgYJDgABLgAECggJIAAOAAAiAA==.',
Du='Dushman:BAAALgADCgYJBgAAAA==.',
Dy='Dykdanglr:BAAALgADCgYJBgABLgAECgQJCAARAAAAAA==.',
['Dí']='Dígifóx:BAAALgAECgEJAQAAAA==.Dígífóx:BAAALgAFFAEJAQAAAA==.',
Ea='Earthereal:BAABLgAECn8yAAIXAAgJpxdOGwApAgAXAAgJpxdOGwApAgAAAA==.',
El='Elastar:BAABLgAECn8mAAIMAAkJ6RYKDgApAgAMAAkJ6RYKDgApAgAAAA==.Ellimist:BAECLgAFFH8eAAIPAAcJsRutAwB0AgAPAAcJsRutAwB0AgAuAAQKfykAAw8ACQl9G3QXAFoCAA8ACQl9G3QXAFoCABQABQk0FxdQAAcBAAAA.Elsan:BAAALgAECgEJAQAAAA==.Elycee:BAACLgAFFH8IAAIbAAMJyyVoPAApAQAbAAMJyyVoPAApAQAuAAQKfyIAAxsACQmtJbEHABgDABsACAk+JrEHABgDAAkACAmWGZYgACECAAAA.Elysria:BAAALgADCgYJBgAAAA==.Elí:BAAALgAECgQJBAAAAA==.',
En='Encrid:BAAALgAECgcJDwABLgAFFAMJCQAVANEYAA==.Enhasa:BAABLgAECn8eAAISAAkJ/hWVLQBAAgASAAkJ/hWVLQBAAgABLgAECgYJGgABAOggAA==.Enoeht:BAABLgAECn80AAICAAkJFguLHwBrAQACAAkJFguLHwBrAQAAAA==.Enveliria:BAAALgAECgYJBwABLgAFFAQJCwACAAobAA==.',
Er='Eraser:BAAALgAECgYJCAAAAA==.Erazar:BAABLgAECn86AAIgAAgJ4BK0CACZAQAgAAgJ4BK0CACZAQAAAA==.Eriah:BAAALgADCgkJCQAAAA==.Erickk:BAABLgAECn8wAAMNAAkJ5xuhPgAbAgANAAkJnBqhPgAbAgAhAAQJVx1SCwAkAQAAAA==.',
Es='Essense:BAABLgAECn8mAAIDAAkJmyRIAwApAwADAAkJmyRIAwApAwAAAA==.',
Ex='Exodari:BAABLgAECn87AAIcAAkJ7hgTCgAMAgAcAAkJ7hgTCgAMAgAAAA==.',
Fa='Fabbioh:BAAALgADCgEJAQAAAA==.Fadeddh:BAACLgAFFH8NAAIKAAMJbhU3VwDVAAAKAAMJbhU3VwDVAAAuAAQKfzAAAgoACQn/G4UhAEICAAoACQn/G4UhAEICAAAA.Faizarah:BAAALgAECgYJBgAAAA==.Faydien:BAAALgAECgEJAgAAAA==.',
Fe='Fearnoevil:BAAALgADCgMJAwAAAA==.Fel:BAABLgAECn8RAAIKAAgJjRpFWgBtAQAKAAgJjRpFWgBtAQAAAA==.Fellkarras:BAAALgAECgYJDwABLgAFFAMJCAAXAFceAA==.Fent:BAABLgAECn8VAAIYAAgJdwuVbABdAQAYAAgJdwuVbABdAQAAAA==.',
Fi='Fiddich:BAAALgAECgYJBgAAAA==.Fillthy:BAACLgAFFH8XAAIXAAcJNBcaCwApAgAXAAcJNBcaCwApAgAuAAQKfy4AAxcACQlYIkYDAEcDABcACQlYIkYDAEcDAAUAAwkhCStvAGQAAAAA.Finnigann:BAAALgAECgYJCwAAAA==.Firenmylazer:BAAALgADCgMJAwAAAA==.Fistav:BAAALgADCgcJDgAAAA==.Fizban:BAABLgAECn8fAAINAAgJsAjplwBEAQANAAgJsAjplwBEAQAAAA==.',
Fl='Flappybird:BAAALgAECgYJCAABLgAFFAMJDQAKAG4VAA==.Flasan:BAAALgADCgEJAQAAAA==.Flazz:BAAALgADCgIJAwAAAA==.Flazzan:BAAALgADCgEJAQAAAA==.Flik:BAAALgAECggJCAABLgAFFAMJCwAGAE0TAA==.',
Fo='Fogbringer:BAAALgAECgIJAwAAAA==.Four:BAAALgADCgQJBAAAAA==.',
Fr='Frejä:BAAALgAECgQJBQABLgAECgQJDAARAAAAAA==.Freyah:BAAALgAECgUJEgAAAA==.Frostmay:BAAALgAECgIJAgAAAA==.',
Fu='Furrybawlz:BAAALgAECgUJCgABLgAECgYJDQARAAAAAA==.',
Ga='Gabran:BAAALgAECgcJBwAAAA==.Gadogear:BAABLgAECn8lAAINAAgJNBh5UwDbAQANAAgJNBh5UwDbAQAAAA==.Galahan:BAAALgAECgMJAwAAAA==.Garlick:BAAALgADCggJDwABLgAECggJOgAgAOASAA==.Garlik:BAAALgADCgMJBAAAAA==.',
Ge='Gertra:BAAALgAECgEJAgABLgAECgYJBwARAAAAAA==.',
Gf='Gfr:BAABLgAECn8UAAIaAAkJmBhgAwBXAgAaAAkJmBhgAwBXAgAAAA==.',
Gi='Girthrichard:BAAALgAECgYJDAAAAA==.',
Gl='Glassdragon:BAABLgAECn8mAAIBAAkJUQzWfABpAQABAAkJUQzWfABpAQAAAA==.Gllor:BAAALgADCgIJAgAAAA==.',
Go='Goatcheeze:BAABLgAECn8cAAIhAAkJLhXFAwDIAQAhAAkJLhXFAwDIAQAAAA==.Goatylocks:BAABLgAECn8rAAMaAAkJ7RVwDABoAQAYAAgJvRAcUACmAQAaAAYJLBxwDABoAQAAAA==.Gohlemsaurus:BAAALgAECgQJBAAAAA==.Goldenchild:BAAALgAFFAMJAwABLgAFFAMJDQAKAG4VAA==.',
Gr='Greatluckydo:BAAALgADCgEJAQAAAA==.Grozlek:BAAALgADCgYJBgAAAA==.',
Gu='Gulen:BAABLgAECn8WAAIPAAYJpSFSIQA6AgAPAAYJpSFSIQA6AgAAAA==.',
Gw='Gwendyla:BAAALgADCgkJFgAAAA==.',
Gy='Gyousei:BAAALgAECgUJBQAAAA==.',
['Gí']='Gíga:BAABLgAECn8XAAIbAAgJ7RPdKQAPAgAbAAgJ7RPdKQAPAgAAAA==.',
Ha='Hafnium:BAAALgAECgIJAgAAAA==.Hamish:BAAALgAECgUJDQAAAA==.Hanhaine:BAACLgAFFH8GAAIHAAMJcwWBNACUAAAHAAMJcwWBNACUAAAuAAQKfywAAgcACQnqFg8SADwCAAcACQnqFg8SADwCAAAA.Hazirat:BAAALgAECgYJDAAAAA==.',
He='Hedlie:BAAALgAECggJCwAAAA==.Hellenkeller:BAECLgAFFH8HAAIXAAYJhw9jHABgAQAXAAYJhw9jHABgAQAuAAQKfx8AAhcABwkzITQTADMCABcABwkzITQTADMCAAEuAAUUBwkZACIArxsA.Heloisa:BAAALgAECgYJEQAAAA==.Helrazr:BAAALgAFFAEJAgAAAA==.Henshin:BAACLgAFFH8LAAIGAAMJTROWOwC5AAAGAAMJTROWOwC5AAAuAAQKf0QAAwYACQmxHZcPAM4CAAYACQmxHZcPAM4CAAcAAgk4DhKEADUAAAAA.',
Hi='Hitt:BAAALgAECgcJCAAAAA==.',
Ho='Hogwortsfun:BAAALgAECgkJAgAAAA==.Holirolla:BAAALgAECgMJAwAAAA==.Holyhim:BAAALgADCgIJAgAAAA==.Holyshawk:BAAALgAECgEJAwAAAA==.Holysudz:BAAALgADCgYJBgAAAA==.Hottyshmotty:BAAALgAECgEJAQAAAA==.Hourglass:BAABLgAECn9AAAMbAAkJlhrbGgB4AgAbAAkJlhrbGgB4AgAJAAQJ1g3oXwDBAAAAAA==.',
Hr='Hroc:BAAALgAECgUJCwAAAA==.',
Hu='Hunterviral:BAAALgADCgEJAQAAAA==.Huntthejuan:BAAALgADCgUJBQAAAA==.',
Ic='Icyowneege:BAAALgADCgUJBQABLgAFFAgJGwAEAMIfAA==.Icywolfy:BAAALgAECgYJCAAAAA==.',
Ig='Igreetyou:BAABLgAECn8gAAIYAAcJnRwMMgALAgAYAAcJnRwMMgALAgAAAA==.',
Il='Illie:BAABLgAECn8mAAIcAAkJShyHBQCtAgAcAAkJShyHBQCtAgAAAA==.Illune:BAABLgAECn8rAAMNAAkJYBpCMABRAgANAAkJYBpCMABRAgAhAAYJUg4ZCQBbAQAAAA==.',
Im='Imanbearpig:BAAALgAFFAEJAQAAAA==.Imleapingit:BAABLgAECn8wAAIEAAkJjiEABgD4AgAEAAkJjiEABgD4AgAAAA==.',
In='Intoodeep:BAAALgAFFAIJAgAAAA==.Intoodragons:BAACLgAFFH8LAAIVAAMJogeDRACoAAAVAAMJogeDRACoAAAuAAQKfzYAAxUACQmcFAUbAPUBABUACQmcFAUbAPUBACAABglaBfokAP4AAAAA.Inyah:BAAALgAECgIJAgAAAA==.',
Io='Ionzz:BAABLgAECn8ZAAICAAkJrx+iCADYAgACAAkJrx+iCADYAgAAAA==.',
Ir='Ir:BAAALgAECggJDwAAAA==.Iroann:BAAALgAECgcJEgAAAA==.',
Is='Isawarriorr:BAACLgAFFH8FAAIMAAMJJR0DFADxAAAMAAMJJR0DFADxAAAuAAQKfywAAgwACQmCI4kDAB8DAAwACQmCI4kDAB8DAAAA.Ishaq:BAAALgAECgQJBQABLgAECggJIAAdAF4FAA==.Ishdo:BAAALgAECgUJBgABLgAECggJIAAdAF4FAA==.Ishdu:BAAALgAECgQJBAABLgAECggJIAAdAF4FAA==.Ishkhan:BAABLgAECn8gAAMdAAgJXgW0PwD0AAAdAAgJ4QS0PwD0AAAFAAYJUQVMWgCcAAAAAA==.Ishmael:BAACLgAFFH8IAAMMAAMJjxlaFwDPAAAMAAMJjxlaFwDPAAAEAAEJiw1rTABEAAAuAAQKfxQAAwQACQk6Hq8UAEQCAAQACQkwHK8UAEQCAAwAAglmG6w4AIQAAAAA.Ishwar:BAAALgADCgYJBgAAAA==.',
Ja='Jakytreehorn:BAACLgAFFH8JAAMPAAYJnQRZQwDIAAAPAAUJ5QNZQwDIAAAUAAMJlgR7RQBnAAAuAAQKfzMAAw8ACQlCFQwoAPABAA8ACQlCFQwoAPABABQACAn6EjkoAJ0BAAAA.Jasher:BAAALgAECgYJBgAAAA==.Jaydm:BAABLgAECn8dAAIjAAYJRxjXHQBjAQAjAAYJRxjXHQBjAQABLgAFFAgJFAANAOwMAA==.',
Je='Jenevelle:BAAALgAECgYJCAAAAA==.Jerisil:BAAALgADCgQJBAAAAA==.Jet:BAABLgAECn8aAAIBAAYJ6CAySwABAgABAAYJ6CAySwABAgAAAA==.',
Ji='Jibbajabba:BAAALgADCgcJBwAAAA==.Jimbo:BAABLgAFFH8IAAIYAAMJDh9gUwATAQAYAAMJDh9gUwATAQABLgAFFAgJHgASAF8fAA==.',
Ju='Judgecalypso:BAAALgAECgQJBgAAAA==.Judgiah:BAAALgAECgUJBQAAAA==.Julthaenia:BAABLgAECn8lAAQkAAcJZh9YBQAlAgAkAAcJZh9YBQAlAgAaAAQJGAr1SwCJAAAYAAUJcQtO6wB8AAABLgAFFAQJCwACAAobAA==.Justeatjuan:BAAALgAECgMJAwAAAA==.',
Ka='Kagebushin:BAAALgAECgMJBAAAAA==.Kalazin:BAAALgAECgUJBQAAAA==.Kalimah:BAAALgADCgMJAwAAAA==.Kalofelement:BAAALgAECgYJBgAAAA==.Karmaisab:BAAALgADCgEJAQAAAA==.Karnrae:BAACLgAFFH8FAAIBAAIJ9wtlhQCNAAABAAIJ9wtlhQCNAAAuAAQKfykAAgEACQkrEoNMANcBAAEACQkrEoNMANcBAAAA.Karynos:BAABLgAECn8nAAMYAAkJyQ1GTwCoAQAYAAkJmgxGTwCoAQAaAAcJyQkOIwA/AQAAAA==.Katnelly:BAAALgAECgMJAwAAAA==.Kazmacoryy:BAAALgAECgYJEAAAAA==.',
Ke='Keedis:BAAALgADCggJCwAAAA==.Keristrasza:BAAALgAFFAEJAQABLgAFFAcJJwAPAEUbAA==.',
Ki='Kileely:BAAALgAECgMJAwAAAA==.Kirintore:BAAALgAECgUJCQAAAA==.',
Kk='Kkaiser:BAAALgADCgcJCwAAAA==.',
Kl='Klaudeus:BAAALgAECgEJAQAAAA==.',
Ko='Kodian:BAAALgADCgEJAQAAAA==.Kolypso:BAABLgAECn8aAAIbAAkJoBVTKwAlAgAbAAkJoBVTKwAlAgAAAA==.Konceal:BAAALgAECgEJAQAAAA==.Konspiracy:BAABLgAECn8pAAIaAAkJpxb+BQD5AQAaAAkJpxb+BQD5AQAAAA==.Konvict:BAAALgAECgIJAwABLgAECgYJDQARAAAAAA==.',
Kr='Krataar:BAABLgAECn8hAAIEAAkJEyFtCwCpAgAEAAkJEyFtCwCpAgAAAA==.Kravvan:BAAALgAECgUJCgABLgAECggJHwANALAIAA==.Krousvor:BAAALgAECgQJBwAAAA==.Kryph:BAABLgAECn8dAAISAAkJQAhycgB3AQASAAkJQAhycgB3AQAAAA==.',
Ku='Kugruk:BAAALgAECgcJDAAAAA==.Kurjo:BAAALgAECgMJBAAAAA==.',
Ky='Kyleschlong:BAAALgAECgMJCAAAAA==.Kyndreith:BAAALgAECgMJAwAAAA==.',
['Kä']='Kämpfer:BAABLgAECn9QAAIEAAkJFiETBwDlAgAEAAkJFiETBwDlAgAAAA==.',
La='Lafiel:BAABLgAECn8dAAMDAAkJGgtKPABJAQADAAkJGgtKPABJAQAIAAIJ1QimbQBaAAAAAA==.Landiedoo:BAAALgAECgkJCgAAAA==.Laurana:BAAALgADCgYJBgAAAA==.Laverna:BAAALgADCgMJBAAAAA==.Lazeras:BAAALgAECgUJCQABLgAFFAEJAgARAAAAAA==.',
Le='Lefay:BAAALgADCgcJFwAAAA==.Leprawnjames:BAAALgAECgIJAgABLgAECggJFwAfAEkgAA==.Letsgetwet:BAAALgADCgYJBgAAAA==.',
Li='Liefic:BAAALgAECgYJCAAAAA==.Lillavender:BAAALgADCgYJBgAAAA==.Limon:BAAALgADCgIJAgAAAA==.',
Lo='Loadin:BAAALgAECgIJAgAAAA==.Lockaflockå:BAAALgADCgMJAwAAAA==.Locke:BAAALgAECgMJAgABLgAECgYJGgABAOggAA==.Lonoh:BAAALgAECgcJEgAAAA==.',
Lu='Luan:BAAALgADCgEJAQAAAA==.Lucariø:BAAALgADCgcJDAAAAA==.Lucidbonsai:BAAALgADCggJCAAAAA==.Luckykilla:BAABLgAECn8mAAIlAAkJHhnTBAAwAgAlAAkJHhnTBAAwAgAAAA==.Lucÿ:BAACLgAFFH8QAAIPAAUJtA5jKAArAQAPAAUJtA5jKAArAQAuAAQKfyIAAw8ABwmsGPQoAOwBAA8ABwmsGPQoAOwBABQAAwkVDDJyAIIAAAAA.Lula:BAAALgADCgMJAwAAAA==.Lurith:BAABLgAECn9JAAMTAAkJBBewEQDmAQATAAkJLRWwEQDmAQASAAgJEA1+1wDUAAAAAA==.Lutreaux:BAAALgADCgEJAQAAAA==.Luxtyrannica:BAABLgAECn8nAAIBAAkJMx58EwDFAgABAAkJMx58EwDFAgAAAA==.',
Ly='Lydrain:BAAALgAECgEJAQAAAA==.Lysandria:BAABLgAECn8rAAINAAkJmw0SYwCyAQANAAkJmw0SYwCyAQAAAA==.',
Ma='Macrosblack:BAAALgADCgMJAwAAAA==.Madamerouge:BAAALgAECgIJAgABLgAECgYJGQAeAIcVAA==.Magearino:BAABLgAECn8nAAINAAgJnRZIWwDGAQANAAgJnRZIWwDGAQAAAA==.Malafore:BAAALgADCgEJAQAAAA==.Malcrux:BAAALgAECgIJAgAAAA==.Marcopally:BAAALgAECgQJBAAAAA==.Marluxia:BAACLgAFFH8gAAIfAAYJ7wpoDwD1AAAfAAYJ7wpoDwD1AAAuAAQKfxoAAh8ACAkhE/YMALkBAB8ACAkhE/YMALkBAAAA.Mastamonk:BAAALgAECgQJBAAAAA==.Materfamilia:BAAALgAECgQJBAAAAA==.Mattbull:BAACLgAFFH8JAAMVAAMJ0RifNQDiAAAVAAMJ0RifNQDiAAAgAAEJ1xNICQBXAAAuAAQKfx4AAyAABgmqJFcNAAQCACAABglCIlcNAAQCABUABgl5IiIfANcBAAAA.Mayu:BAAALgAECgEJAQAAAA==.',
Me='Medjrab:BAACLgAFFH8UAAISAAUJxhh6VwA3AQASAAUJxhh6VwA3AQAuAAQKfzIAAhIACQlLIh8RANwCABIACQlLIh8RANwCAAAA.Meristem:BAABLgAECn8vAAIHAAkJLg5OIgCpAQAHAAkJLg5OIgCpAQAAAA==.Merko:BAAALgADCgkJDwAAAA==.',
Mi='Miaan:BAAALgADCgYJBgAAAA==.Miette:BAAALgADCgMJAwAAAA==.Mihonk:BAAALgADCgQJBAAAAA==.Mintycrx:BAABLgAECn8fAAINAAkJHhEXTgDrAQANAAkJHhEXTgDrAQAAAA==.Missfist:BAAALgADCgIJAgAAAA==.Mistlocke:BAAALgADCgMJAwAAAA==.',
Mn='Mngwa:BAAALgAECgQJCwAAAA==.',
Mo='Moegu:BAABLgAECn8bAAImAAgJXxbVCQC6AQAmAAgJXxbVCQC6AQAAAA==.Mog:BAACLgAFFH8JAAMYAAMJLSDldgDGAAAYAAIJwSLldgDGAAAkAAEJBxuRHABSAAAuAAQKfzkABBgACQmeIyoUAKcCABgABwnVIyoUAKcCACQAAwmVI58WAP8AABoAAwkJEsI2ANsAAAAA.Mogma:BAAALgAECgQJBAAAAA==.Moncatsera:BAAALgAECgQJBAAAAA==.Mondgrille:BAAALgAECgQJBAABLgAECgYJDQARAAAAAA==.Monora:BAABLgAECn8ZAAIXAAcJfgvUTwATAQAXAAcJfgvUTwATAQAAAA==.Montress:BAABLgAECn8UAAIDAAgJBhDaJQCIAQADAAgJBhDaJQCIAQAAAA==.Moomoohealz:BAACLgAFFH8NAAIHAAMJ8RkQJwDkAAAHAAMJ8RkQJwDkAAAuAAQKfz4AAgcACQkoIYsHANMCAAcACQkoIYsHANMCAAAA.Moonbounds:BAACLgAFFH8nAAIPAAcJRRs9BgA+AgAPAAcJRRs9BgA+AgAuAAQKfzgAAw8ACQndJFEDAEQDAA8ACQndJFEDAEQDABQAAQnZH4Z5AF0AAAAA.Moondoggey:BAAALgAECgMJAwAAAA==.Morgana:BAAALgADCgIJAgAAAA==.Mousechief:BAABLgAECn8zAAIUAAgJjgZpSwD3AAAUAAgJjgZpSwD3AAAAAA==.Moxnix:BAABLgAECn8VAAMXAAgJng7+TgAWAQAXAAcJXgz+TgAWAQAdAAQJjgX4WQCbAAAAAA==.Moxxzi:BAAALgAFFAEJAgAAAA==.',
Mu='Muhfookinbak:BAABLgAECn8kAAMPAAkJFyCIDwDKAgAPAAkJFyCIDwDKAgAUAAQJhxgwWADMAAAAAA==.',
My='Myor:BAAALgADCgMJAwAAAA==.',
['Mà']='Màttbull:BAABLgAFFH8HAAIKAAMJcw6ZXgDBAAAKAAMJcw6ZXgDBAAABLgAFFAMJCQAVANEYAA==.',
['Mä']='Märcøsferätv:BAAALgAECgEJAQAAAA==.',
Na='Naesta:BAAALgAECgIJAgABLgAECggJIQAGAP4fAA==.Naksu:BAEALgAECgEJAQABLgAECgcJHQAKAJYHAA==.Naksù:BAEBLgAECn8dAAIKAAcJlgeemgDeAAAKAAcJlgeemgDeAAAAAA==.Namal:BAAALgAECgQJBQAAAA==.Narenae:BAABLgAECn8lAAIFAAkJCyRABABIAwAFAAkJCyRABABIAwAAAA==.Nastalan:BAAALgADCgYJCgAAAA==.',
Ne='Nefari:BAAALgADCgMJAwAAAA==.Neifeb:BAABLgAECn8oAAIbAAkJehY2NgD5AQAbAAkJehY2NgD5AQAAAA==.Nephthys:BAAALgADCgQJBAAAAA==.',
Ni='Niallivdam:BAABLgAECn8tAAMgAAgJWhv7AwA2AgAgAAgJWhv7AwA2AgAnAAYJ0hcUEwCQAQAAAA==.Nights:BAAALgAECgIJAgABLgAFFAMJBgATAIMLAA==.Nightsoul:BAAALgADCgEJAQAAAA==.Ninh:BAACLgAFFH8NAAIXAAMJkgPTQgBzAAAXAAMJkgPTQgBzAAAuAAQKf1UAAhcACQn6FIcaADACABcACQn6FIcaADACAAAA.',
No='Nomissius:BAAALgADCgcJDQAAAA==.Nooblè:BAAALgADCgMJAwAAAA==.Notsodemon:BAABLgAECn8eAAMKAAgJfxSgTwCLAQAKAAgJfxSgTwCLAQACAAIJnwrPYwBUAAAAAA==.Notsoevoker:BAAALgAECgMJAwABLgAECggJHgAKAH8UAA==.Notsomonk:BAAALgADCgMJAwABLgAECggJHgAKAH8UAA==.',
Ny='Nykara:BAAALgAECgUJBQAAAA==.',
['Nå']='Nåld:BAAALgAECgUJCwAAAA==.',
Oa='Oakendorf:BAAALgAECgEJAQABLgAECgEJAgARAAAAAA==.',
Ob='Obvinotagirl:BAAALgAECggJDwAAAA==.',
Od='Oddpocalypse:BAAALgAECgEJAgAAAA==.',
Og='Ogsikko:BAAALgAECgYJCwABLgAECggJGAAYAJAeAA==.Ogsikkotv:BAABLgAECn8YAAINAAYJ/BmQhwDCAQANAAYJ/BmQhwDCAQABLgAECggJGAAYAJAeAA==.',
Ok='Okathra:BAAALgAECgQJBAABLgAFFAMJBQAcAGQaAA==.',
On='Onebadmutha:BAABLgAECn8ZAAIYAAkJ+AySTgCqAQAYAAkJ+AySTgCqAQAAAA==.Ontop:BAABLgAECn8oAAIbAAkJ7xsaHABeAgAbAAkJ7xsaHABeAgAAAA==.',
Or='Orb:BAABLgAECn8vAAQBAAkJKhlBPgACAgABAAkJLRhBPgACAgAOAAgJexLtJQDOAQALAAYJlQ/EHgATAQAAAA==.Orcfreeza:BAAALgAECgQJDAAAAA==.Ortinks:BAABLgAECn8iAAINAAgJAxEgZwCoAQANAAgJAxEgZwCoAQAAAA==.',
Ow='Owneege:BAACLgAFFH8bAAIEAAgJwh92AQB9AgAEAAgJwh92AQB9AgAuAAQKfzMAAgQACQkEIx4CAKADAAQACQkEIx4CAKADAAAA.',
Pa='Painsaw:BAAALgADCgYJBgAAAA==.Pallinar:BAABLgAECn83AAIBAAkJGhUEOgAQAgABAAkJGhUEOgAQAgAAAA==.Pasquale:BAABLgAECn8hAAIdAAcJRSHdEwAIAgAdAAcJRSHdEwAIAgAAAA==.',
Pe='Pebbles:BAABLgAECn8ZAAIBAAgJGhgEQgD2AQABAAgJGhgEQgD2AQAAAA==.Pedroia:BAAALgAECgcJDgAAAA==.Peridaxx:BAAALgAECgIJAgAAAA==.Pesty:BAAALgAECgMJCQAAAA==.',
Ph='Phe:BAABLgAECn8XAAMHAAcJhw7kOAAiAQAHAAcJhw7kOAAiAQAGAAYJpQvzcAADAQAAAA==.Pheraree:BAAALgAECgEJAQAAAA==.Phooboo:BAAALgAECgkJBQAAAA==.',
Pi='Pidion:BAAALgADCgYJDAAAAA==.Pilgrimm:BAECLgAFFH8ZAAMiAAcJrxsgAwBrAQAiAAUJARsgAwBrAQAQAAQJ+B4gCwA4AQAuAAQKfyQAAxAACQl7IrIDAGADABAACQl0IrIDAGADACIABQkIH8MKAGcBAAAA.Pixyl:BAAALgADCgYJBgAAAA==.',
Pl='Plaguerott:BAABLgAECn83AAIoAAkJeA+RDACeAQAoAAkJeA+RDACeAQAAAA==.Plusultra:BAAALgADCgkJEQAAAA==.Pluto:BAAALgAFFAMJAwAAAA==.',
Po='Poby:BAAALgADCgcJBwAAAA==.Polydh:BAABLgAECn8wAAImAAkJriTRAAA/AwAmAAkJriTRAAA/AwAAAA==.Poobah:BAABLgAECn8jAAMUAAgJvAboUwDZAAAUAAcJfAboUwDZAAAPAAcJCgMogwDHAAAAAA==.Popscotch:BAABLgAECn8jAAMkAAkJEg3OCQCkAQAkAAcJRg7OCQCkAQAYAAkJwAs7VwCSAQAAAA==.Pouffant:BAABLgAECn8iAAIBAAkJyBNjUgDHAQABAAkJyBNjUgDHAQAAAA==.',
Pr='Pronoz:BAABLgAECn8kAAIBAAcJfRJIiwBPAQABAAcJfRJIiwBPAQAAAA==.',
Pu='Punchy:BAAALgADCgEJAQAAAA==.',
Pw='Pwnageddon:BAABLgAECn8tAAMLAAgJZh6BCABCAgALAAcJDSKBCABCAgABAAUJhxUW4gDJAAAAAA==.Pwnjitsu:BAACLgAFFH8HAAIFAAMJAh5vFgAIAQAFAAMJAh5vFgAIAQAuAAQKfzwAAgUACQk8Je0BAE4DAAUACQk8Je0BAE4DAAAA.',
Py='Pyrothermia:BAACLgAFFH8UAAINAAgJ7AyzGAAPAgANAAgJ7AyzGAAPAgAuAAQKfyYAAg0ACQn/HIoqAMgCAA0ACQn/HIoqAMgCAAAA.',
['Pô']='Pôlgara:BAAALgADCgYJBgABLgAECggJKQAOAOseAA==.',
Qt='Qtkillz:BAAALgADCgQJBAAAAA==.',
Qu='Quinlekd:BAAALgAECgQJBAABLgAECggJLAAYAIIhAA==.',
Ra='Rancayden:BAAALgAECgMJBAAAAA==.Rawhoof:BAACLgAFFH8NAAIEAAMJFSBNJgAKAQAEAAMJFSBNJgAKAQAuAAQKf1UAAgQACQlHJlEBAGoDAAQACQlHJlEBAGoDAAAA.Razak:BAACLgAFFH8FAAIcAAMJZBrhCgD8AAAcAAMJZBrhCgD8AAAuAAQKfzIAAhwACQlMI8QBAA0DABwACQlMI8QBAA0DAAAA.',
Re='Redlock:BAAALgAECgMJAwAAAA==.Redtiger:BAAALgADCgYJBgAAAA==.Renisa:BAABLgAECn8iAAIKAAgJqRlyTgCOAQAKAAgJqRlyTgCOAQAAAA==.Retman:BAABLgAECn8UAAIBAAcJtg8R5QDLAAABAAcJtg8R5QDLAAAAAA==.Reu:BAAALgAECgUJBwAAAA==.Revlyk:BAABLgAECn8nAAIcAAgJFiMNBACtAgAcAAgJFiMNBACtAgABLgAFFAQJCwACAAobAA==.Rezloh:BAAALgAECgkJDAAAAA==.',
Rh='Rhoanna:BAAALgADCgUJBwAAAA==.',
Ri='Rinja:BAAALgADCgYJBgAAAA==.Rintaro:BAABLgAECn8kAAILAAkJrAs6GgA6AQALAAkJrAs6GgA6AQAAAA==.Ritanana:BAAALgAECgIJAgAAAA==.',
Ro='Roccot:BAAALgAECggJDgAAAA==.Roflstomp:BAAALgAECgQJBwABLgAECggJFwAfAEkgAA==.Roostrr:BAABLgAECn8XAAIBAAYJ4B2EcwCUAQABAAYJ4B2EcwCUAQAAAA==.Rotfather:BAAALgADCgYJBgAAAA==.Rotjaw:BAAALgAECgUJCwAAAA==.Roughedge:BAAALgADCgIJAgAAAA==.',
Ru='Rurik:BAAALgAECgEJAQAAAA==.',
['Rä']='Rävthor:BAAALgAFFAEJAQAAAA==.Rävthör:BAAALgAECgYJBgAAAA==.',
['Rè']='Rèjuva:BAAALgAECgcJDQAAAA==.Rèptílè:BAAALgADCgMJAwABLgAFFAMJBwAbAA8iAA==.',
['Rî']='Rîcflair:BAAALgAECgcJEwAAAA==.',
Sa='Saiyax:BAAALgADCgYJBwAAAA==.Salidfingers:BAAALgADCgYJBgAAAA==.Sanyakulak:BAAALgADCgcJBwABLgAFFAgJGwAfABcWAA==.Sanzo:BAAALgAECgEJAQAAAA==.Savathûn:BAAALgAECgQJCAAAAA==.',
Sc='Scalycat:BAACLgAFFH8GAAMVAAMJjgFtTQB+AAAVAAMJjgFtTQB+AAAnAAIJtw6vIwBnAAAuAAQKfyoABCcACQnYDpwZAMEBACcACQnYDpwZAMEBABUABwksBnhiAKUAACAAAgluB4AmAC0AAAAA.Schalla:BAAALgAECgEJAQAAAA==.Scum:BAAALgAECgYJDQAAAA==.Scòrpìòn:BAAALgADCgcJBgABLgAFFAMJBwAbAA8iAA==.',
Se='Seancody:BAAALgADCgIJAgAAAA==.Sekhmett:BAAALgAECgYJCQAAAA==.Selandria:BAAALgADCgQJBAAAAA==.Senate:BAAALgAECgYJCwAAAA==.',
Sh='Shadowbear:BAABLgAECn8cAAIIAAcJ/RyYHgDJAQAIAAcJ/RyYHgDJAQAAAA==.Shadowoss:BAAALgAECgYJCAAAAA==.Shadygrump:BAAALgAECgYJEQAAAA==.Shammacass:BAAALgAECgUJBQAAAA==.Shamwick:BAAALgAECgQJBAAAAA==.Shaolincito:BAAALgAECgQJCAAAAA==.Sherrilyn:BAAALgAECgQJBAAAAA==.Shocklocke:BAAALgAECgQJBAAAAA==.',
Si='Sigmachad:BAAALgAECgUJDwAAAA==.Silandrus:BAAALgAECgMJBAAAAA==.Silverocean:BAABLgAECn8zAAIOAAkJMRzqDwCUAgAOAAkJMRzqDwCUAgAAAA==.Silvia:BAAALgADCgUJCQAAAA==.Singularity:BAACLgAFFH8NAAIMAAMJPCTuDgAsAQAMAAMJPCTuDgAsAQAuAAQKf1IAAgwACQltJmkAAHkDAAwACQltJmkAAHkDAAAA.',
Sk='Skaerx:BAABLgAECn8WAAMEAAYJVBeOQwCXAQAEAAYJ9RWOQwCXAQAjAAQJZhSYHQADAQAAAA==.Skittlez:BAABLgAECn8mAAIWAAkJkR8nCQCHAgAWAAkJkR8nCQCHAgABLgAFFAMJBAARAAAAAA==.',
Sl='Slaykween:BAAALgAECgYJEAAAAA==.Slootybooty:BAABLgAECn8XAAIfAAgJSSCGBwBtAgAfAAgJSSCGBwBtAgAAAA==.',
Sm='Smallz:BAAALgAECgYJEQABLgAECggJHwANALAIAA==.',
Sn='Snipersmash:BAAALgAECgQJCAAAAA==.Snooptrogg:BAABLgAECn8rAAIEAAkJGRVsIQDfAQAEAAkJGRVsIQDfAQAAAA==.Snoozumi:BAABLgAFFH8GAAIXAAMJKQaNPwCEAAAXAAMJKQaNPwCEAAAAAA==.Snuups:BAABLgAECn9DAAIYAAkJAhr7LAAfAgAYAAkJAhr7LAAfAgAAAA==.',
So='Soldiah:BAABLgAECn8bAAIEAAgJrQ03NQBsAQAEAAgJrQ03NQBsAQAAAA==.Sommbra:BAAALgAECgYJBwAAAA==.Souljax:BAAALgADCgcJCQAAAA==.',
Sp='Spacelaser:BAAALgAECgQJBQAAAA==.',
Sq='Sqwurl:BAAALgADCgQJBAAAAA==.',
St='Steakhaus:BAAALgADCgIJAgAAAA==.Stiros:BAAALgAECgMJAwAAAA==.Stonedragon:BAECLgAFFH8SAAMbAAYJuxr9IwBhAQAbAAUJdiD9IwBhAQAJAAEJzwMJMQBGAAAuAAQKfzsAAxsACAn+JMwFADEDABsACAn+JMwFADEDAAkACAnPHtYDAHgCAAAA.Stormfist:BAAALgAECggJEAAAAA==.Stormhaven:BAAALgADCggJKgABLgAECggJKQAOAOseAA==.Stormrender:BAAALgAECgYJEAAAAA==.Stormstag:BAAALgADCgYJBgAAAA==.Stouty:BAAALgADCgMJAwABLgAECgcJFAAgAOkaAA==.',
Su='Sukonamí:BAABLgAECn8iAAMEAAkJghckKAAdAgAEAAgJdhUkKAAdAgAjAAQJGhvVJgAqAQAAAA==.Suzhou:BAABLgAECn8jAAIaAAgJowk4EwAMAQAaAAgJowk4EwAMAQAAAA==.Suzoomies:BAAALgADCgcJBwAAAA==.Suzumii:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetcarolin:BAABLgAECn8WAAISAAkJRg+GXgDXAQASAAkJRg+GXgDXAQAAAA==.Sweetsmercy:BAAALgAECgQJBQAAAA==.Swiftleaf:BAAALgADCgcJBwAAAA==.Swisscheese:BAABLgAECn8sAAIYAAgJgiEtFwCUAgAYAAgJgiEtFwCUAgAAAA==.',
Sy='Syraxa:BAAALgAECgQJBwABLgAFFAMJDAAGAPUQAA==.Syril:BAAALgADCgcJDAAAAA==.',
Ta='Taedish:BAAALgADCgMJAwAAAA==.Tahret:BAAALgADCgQJBQAAAA==.Taquillya:BAAALgAECgQJBQAAAA==.Tarina:BAAALgADCgEJAQAAAA==.Tatersaladin:BAAALgADCgMJAwAAAA==.',
Te='Tenlortin:BAAALgAECgEJAQAAAA==.Terragosa:BAABLgAECn81AAINAAkJ5xmcKgBpAgANAAkJ5xmcKgBpAgAAAA==.Teryail:BAAALgAECgEJAQAAAA==.Tetchybono:BAAALgADCgYJBgAAAA==.',
Th='Thade:BAABLgAECn8kAAMjAAkJByFSBQCsAgAjAAgJGiBSBQCsAgAEAAgJfB5XHwBWAgAAAA==.Thaeleon:BAABLgAECn8hAAMHAAgJbx9KEQBDAgAHAAgJbx9KEQBDAgAGAAYJixz+NADUAQABLgAFFAMJCAAMAI8ZAA==.Thahawtz:BAAALgADCggJCAAAAA==.Thaneblade:BAAALgAECgQJBgAAAA==.Therizzler:BAAALgAECgcJCQABLgAFFAMJDQAKAG4VAA==.Thickening:BAABLgAECn8ZAAMXAAUJhQ0xYQDVAAAXAAUJhQ0xYQDVAAAFAAUJ9QfRWwCYAAAAAA==.Thope:BAABLgAECn8fAAINAAcJ8glvogAyAQANAAcJ8glvogAyAQAAAA==.Thoranubran:BAABLgAECn8WAAICAAYJ/w4bMwA+AQACAAYJ/w4bMwA+AQAAAA==.Thrivia:BAAALgAECgYJBgAAAA==.',
Ti='Ticklemychin:BAAALgAECgQJBwAAAA==.Tigani:BAAALgAECgUJDAAAAA==.Tinstey:BAAALgADCgEJAQAAAA==.',
To='Toestiir:BAAALgADCgcJDQAAAA==.Tokemaddab:BAAALgADCgUJBQAAAA==.Toughasnails:BAAALgAECgEJAgAAAA==.',
Tr='Traesdyne:BAAALgAECgEJAQABLgAECgMJAwARAAAAAA==.Trainar:BAAALgAECgQJCQAAAA==.Trazle:BAAALgAECgMJAwAAAA==.Trekkiegeek:BAAALgADCgYJBwAAAA==.Trickybackup:BAAALgADCgMJAwAAAA==.Triggs:BAAALgAECgcJBgAAAA==.Trollbear:BAABLgAECn8WAAIGAAgJhBUoJwANAgAGAAgJhBUoJwANAgAAAA==.Trondruid:BAAALgADCgYJDQAAAA==.Trooze:BAABLgAECn82AAIOAAgJKCRnBgAdAwAOAAgJKCRnBgAdAwAAAA==.Trr:BAABLgAECn8pAAIYAAkJmBe2IwCFAgAYAAkJmBe2IwCFAgAAAA==.Truckz:BAAALgADCgEJAQABLgAECgkJQAAbAE0gAA==.Truckzage:BAAALgADCgcJBwABLgAECgkJQAAbAE0gAA==.',
Tu='Tuba:BAAALgAECgYJEAAAAA==.Turim:BAAALgAECgcJEAAAAA==.Tusksrus:BAAALgADCgcJFwAAAA==.',
Ty='Tyrlidd:BAABLgAECn82AAIbAAkJERYxKwAmAgAbAAkJERYxKwAmAgAAAA==.',
Ud='Udon:BAABLgAECn8YAAISAAYJcBfsdQBvAQASAAYJcBfsdQBvAQAAAA==.',
Ul='Ultimazero:BAAALgADCgEJAQAAAA==.',
Un='Unavoidable:BAAALgADCgkJEQAAAA==.Unlikelytale:BAABLgAECn8mAAIPAAkJAyEuCgDXAgAPAAkJAyEuCgDXAgAAAA==.Unmilked:BAAALgAECgYJBwAAAA==.',
Ur='Uricash:BAABLgAECn9QAAINAAkJliDYDwD4AgANAAkJliDYDwD4AgAAAA==.Urzual:BAABLgAECn8rAAIcAAkJDyBrBQCCAgAcAAkJDyBrBQCCAgAAAA==.',
Ut='Utiniócast:BAAALgAECgQJBAAAAA==.',
Va='Vandreynna:BAACLgAFFH8LAAICAAQJChuUCQBUAQACAAQJChuUCQBUAQAuAAQKf08AAgIACQl/JYUBAFkDAAIACQl/JYUBAFkDAAAA.',
Ve='Vegèta:BAABLgAECn8gAAISAAkJZAthegBmAQASAAkJZAthegBmAQABLgAFFAMJBwAbAA8iAA==.Veilaura:BAAALgAECgYJCwAAAA==.Velarria:BAABLgAECn8gAAMbAAkJ4h43FQCOAgAbAAkJ4h43FQCOAgAWAAQJjwwcIQDSAAAAAA==.Velikan:BAAALgAECgQJBwABLgAECgcJCAARAAAAAA==.Velsiana:BAAALgAECgcJDwAAAA==.Velveetah:BAAALgAECgUJCAABLgAECgYJGQADAJ4PAA==.Verbrennen:BAAALgAECgUJDgABLgAECgkJUAAEABYhAA==.Verdreht:BAAALgADCgEJAQABLgAECgkJUAAEABYhAA==.Verita:BAABLgAECn8rAAIiAAcJcCM3BAA8AgAiAAcJcCM3BAA8AgAAAA==.Verlynne:BAAALgADCgYJBgAAAA==.Verylikely:BAAALgAECgEJAgAAAA==.',
Vi='Viviann:BAABLgAECn8kAAInAAkJeRHPDwDHAQAnAAkJeRHPDwDHAQAAAA==.',
Vo='Voiager:BAAALgADCgcJCgAAAA==.',
Vr='Vrakal:BAAALgAECgkJDQAAAA==.',
Wa='Wantabehavoc:BAAALgADCgYJDQAAAA==.Wantadeznutz:BAAALgAECgIJAgAAAA==.Warnick:BAAALgADCgQJBQAAAA==.Warraxe:BAAALgAECgEJAgAAAA==.Wayloren:BAABLgAECn8qAAIBAAkJzApxdAB6AQABAAkJzApxdAB6AQAAAA==.Waystalker:BAAALgAECgMJAwAAAA==.Wayverly:BAAALgADCgUJBwABLgAECgkJHgAJAF4IAA==.',
Wi='Wickathy:BAABLgAECn9FAAMmAAkJbSCQAgDFAgAmAAkJbSCQAgDFAgAKAAMJlAy+xgCQAAAAAA==.',
Wo='Wolfcity:BAAALgADCgEJAQAAAA==.Wondertauren:BAAALgADCgYJCQAAAA==.Woodson:BAAALgADCgkJEAAAAA==.Worstdps:BAAALgAFFAEJAQAAAA==.',
Wr='Wrkandtank:BAAALgAECgYJBgABLgAECggJFQAYAHcLAA==.',
Wu='Wuldorr:BAACLgAFFH8QAAIBAAQJexd8OQApAQABAAQJexd8OQApAQAuAAQKfyQAAgEACAm1H0gkAJYCAAEACAm1H0gkAJYCAAAA.',
Wy='Wynnifred:BAAALgAECggJDQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.',
Xe='Xethreal:BAAALgADCgMJAwAAAA==.',
Xy='Xype:BAAALgAECgkJEQAAAA==.',
Xz='Xzara:BAAALgAECgYJBgABLgAECgYJFgAFAMwbAA==.',
Ya='Yastoria:BAAALgAECgcJEAAAAA==.',
Yi='Yinandtonic:BAAALgAECgEJBAAAAA==.',
Yv='Yvvee:BAAALgADCgcJBwAAAA==.',
Za='Zaalim:BAAALgADCgQJBAAAAA==.Zaddy:BAAALgAECgEJAQAAAA==.Zapdôs:BAAALgAECgQJBAAAAA==.',
Ze='Zeda:BAAALgAECgYJDQABLgAECgYJFgAFAMwbAA==.Zephyris:BAAALgAECgUJDAABLgAFFAcJJAAjAKolAA==.',
Zh='Zheng:BAAALgAECgYJBgAAAA==.',
Zi='Zillia:BAAALgADCgMJAwAAAA==.',
Zo='Zonora:BAABLgAECn8YAAIOAAkJlQ1GJgDMAQAOAAkJlQ1GJgDMAQAAAA==.',
Zy='Zyphexd:BAAALgAECgYJDwAAAA==.Zyris:BAAALgADCgcJDQAAAA==.',
['Àz']='Àzñós:BAAALgAECgQJBwAAAA==.',
['Äs']='Ästro:BAAALgAECgQJBgABLgAECgkJLQAFAHcaAA==.',
['Äz']='Äzrael:BAABLgAECn8zAAIDAAkJIRy7CADSAgADAAkJIRy7CADSAgAAAA==.',
['Åz']='Åznos:BAAALgAECgQJCAAAAA==.',
['Çr']='Çréwüsæðèr:BAABLgAECn8jAAIMAAgJZiBHCgBAAgAMAAgJZiBHCgBAAgAAAA==.',
['Ðe']='Ðecimus:BAAALgAECgQJCQAAAA==.',
['Ðì']='Ðìaßlo:BAACLgAFFH8HAAIbAAMJDyJYTwD1AAAbAAMJDyJYTwD1AAAuAAQKfzEABBsACQlsHHYmADsCABsACAkUHHYmADsCABYABwlYFAQRALMBAAkAAQleABqbABUAAAAA.',
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
