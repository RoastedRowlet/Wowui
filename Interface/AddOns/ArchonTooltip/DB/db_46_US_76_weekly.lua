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

local lookup = {'Paladin-Retribution','DemonHunter-Havoc','Priest-Holy','Warrior-Fury','Monk-Windwalker','Druid-Restoration','Druid-Balance','Priest-Shadow','Unknown-Unknown','DemonHunter-Devourer','Paladin-Protection','Warrior-Protection','Mage-Frost','Paladin-Holy','Rogue-Subtlety','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Elemental','Evoker-Preservation','Hunter-Survival','Monk-Mistweaver','Priest-Discipline','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Shaman-Restoration','Shaman-Enhancement','Druid-Feral','Druid-Guardian','Hunter-Marksmanship','Evoker-Augmentation','Evoker-Devastation','Mage-Arcane','Monk-Brewmaster','Warrior-Arms','Warlock-Affliction','Rogue-Assassination','DemonHunter-Vengeance','Rogue-Outlaw','DeathKnight-Frost',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Aberaht:BAABLgAECn8mAAIBAAkJYCNMCgDhAgABAAkJYCNMCgDhAgAAAA==.',
Ad='Adamaro:BAAALgADCgYJCQAAAA==.',
Ae='Aenastian:BAAALgAECgUJCQABLgAECgkJOwACACglAA==.',
Af='Affrica:BAAALgADCgEJAQABLgAECgQJFwADADMTAA==.',
Ag='Agnu:BAAALgADCgcJBwAAAA==.',
Ah='Ahgra:BAABLgAECn8mAAIBAAgJ+QqpfQAnAQABAAgJ+QqpfQAnAQAAAA==.',
Ak='Akre:BAAALgAFFAIJBgAAAQ==.Akumä:BAAALgAECgUJCgAAAA==.',
Al='Aleannia:BAAALgAECgUJBQAAAA==.Alekz:BAAALgADCggJBwAAAA==.Alestria:BAAALgAECgYJEgAAAA==.Alibrexia:BAABLgAECn8WAAIEAAYJbQqPQADwAAAEAAYJbQqPQADwAAAAAA==.Alida:BAABLgAECn8oAAIEAAgJNQraLQBKAQAEAAgJNQraLQBKAQAAAA==.Alithvia:BAAALgAECgYJBgABLgAECgkJJQAFAAskAA==.Allisara:BAAALgADCgkJFgAAAA==.Alysae:BAACLgAFFH8XAAMGAAUJVxhgEQB0AQAGAAUJVxhgEQB0AQAHAAEJSQBdNwAcAAAuAAQKfxsAAwYACAkrHeUdAE8CAAYACAkrHeUdAE8CAAcAAgllBxZvACkAAAAA.',
Am='Amabear:BAAALgAECgEJAQABLgAECgcJHAAIAPwcAA==.Ambrosse:BAAALgADCggJCQABLgAECgQJBgAJAAAAAA==.',
An='Anabug:BAAALgAECgMJBQAAAA==.Andelwynn:BAAALgAECgIJAgABLgAECgcJEAAJAAAAAA==.Aniellas:BAAALgAECgIJAgAAAA==.Annalese:BAAALgADCgUJCQABLgAECgcJEAAJAAAAAA==.',
Ar='Arabeli:BAAALgAECgEJAQAAAA==.Arbyss:BAAALgADCgcJDAAAAA==.Ardatha:BAAALgADCgcJFwAAAA==.',
As='Asterön:BAAALgAECgYJDwAAAA==.Astrocakes:BAAALgAECgMJAwABLgAFFAMJCAAKAEINAA==.',
At='Athenä:BAACLgAFFH8XAAILAAYJiAxEAwAoAQALAAYJiAxEAwAoAQAuAAQKfzAAAgsACQnxG/kFAI4CAAsACQnxG/kFAI4CAAAA.Atsuma:BAABLgAECn8dAAIMAAYJQwtAIwDLAAAMAAYJQwtAIwDLAAAAAA==.',
Av='Aviz:BAAALgADCgMJAwAAAA==.',
Aw='Awtysmbb:BAAALgAECgEJAQABLgAECgkJJQANAJYXAA==.',
['Aí']='Aísling:BAABLgAECn8VAAIOAAYJ0yLVEwAmAgAOAAYJ0yLVEwAmAgAAAA==.',
Ba='Baboii:BAAALgADCgIJAgAAAA==.Baconmecrazy:BAAALgAECgEJAQAAAA==.Badinngo:BAAALgADCggJDwAAAA==.Bahiu:BAAALgAECgQJBAAAAA==.Bajafresh:BAAALgAECgQJBQAAAA==.Battleshaman:BAAALgADCgYJBgAAAA==.',
Bd='Bd:BAABLgAECn8dAAIPAAgJJxU5GABGAgAPAAgJJxU5GABGAgAAAA==.',
Be='Beardmedaddy:BAAALgAECgYJBgAAAA==.Bearstavious:BAAALgAECgcJAgAAAA==.Benjinana:BAABLgAECn8XAAMDAAQJMxMFOQDKAAADAAQJMxMFOQDKAAAIAAIJJQPOWgBMAAAAAA==.Betterthanu:BAAALgADCgUJBQABLgADCgYJCgAJAAAAAA==.',
Bg='Bg:BAAALgAECgMJAwAAAA==.',
Bi='Bige:BAAALgAECgYJDgAAAA==.Bilo:BAAALgAECgYJCAAAAA==.Bitelyus:BAAALgAECgMJAwAAAA==.',
Bo='Bobius:BAAALgAECgcJBwAAAA==.Bobohizan:BAAALgADCgQJBAAAAA==.Bohde:BAABLgAFFH8OAAMQAAUJ6iIoGQCPAQAQAAQJ6iIoGQCPAQARAAEJAABeMQAAAAAAAA==.Bolognaman:BAAALgAECgUJCAAAAA==.Bombjovi:BAABLgAECn8YAAMLAAgJ0RUTEABqAQALAAgJ0RUTEABqAQAOAAUJlA/APwDxAAAAAA==.Bountty:BAAALgAECgQJBAAAAA==.',
Br='Brahmsthoven:BAAALgADCgIJAwAAAA==.Branndhon:BAABLgAECn8ZAAIGAAYJghSkOgBiAQAGAAYJghSkOgBiAQAAAA==.',
Bt='Btrflyprncss:BAAALgADCgMJAwAAAA==.',
Bu='Bubblemedic:BAAALgADCgIJAgAAAA==.Budde:BAAALgAECgUJBQAAAA==.',
Ca='Cairdamane:BAABLgAECn8hAAISAAkJ5BE3HwCUAQASAAkJ5BE3HwCUAQAAAA==.Calidrina:BAABLgAECn8hAAIKAAkJMhzELwC9AQAKAAkJMhzELwC9AQAAAA==.Carm:BAAALgAECgYJBgAAAA==.Caroliná:BAAALgAECgIJBAAAAA==.Catcast:BAAALgAECgUJCAABLgAECgkJKgATANgOAA==.Catclaw:BAAALgAECgEJAQABLgAECgkJKgATANgOAA==.',
Ce='Celiri:BAABLgAECn8nAAIFAAkJrhCXFQC4AQAFAAkJrhCXFQC4AQAAAA==.Celldrassil:BAABLgAECn8kAAIGAAgJ4QW4WQDlAAAGAAgJ4QW4WQDlAAAAAA==.Cereel:BAAALgAECgMJAwABLgAFFAMJCAAKAEINAA==.',
Ch='Chadaracka:BAAALgAECgYJBwAAAA==.Chandelure:BAAALgAECgUJCwAAAA==.Chardaney:BAAALgAECgcJEAAAAA==.Cherryontop:BAABLgAECn8aAAIGAAYJ8BX8NwBvAQAGAAYJ8BX8NwBvAQAAAA==.Chozenone:BAAALgAECgQJBQAAAA==.Chozi:BAAALgAECgYJBgAAAA==.',
Ci='Cii:BAAALgAECgYJCgAAAA==.',
Co='Coconutwater:BAAALgAECggJCwAAAA==.Colandros:BAABLgAECn8nAAIUAAcJDwsqIABKAQAUAAcJDwsqIABKAQAAAA==.Colara:BAAALgAECgYJDwAAAA==.Combobreaker:BAABLgAECn8wAAIVAAkJMx6tBAARAwAVAAkJMx6tBAARAwAAAA==.Comoo:BAAALgADCgIJBQAAAA==.Correct:BAAALgAECgEJAQAAAA==.Cowbôy:BAAALgADCgkJEQAAAA==.',
Cr='Crassberry:BAACLgAFFH8VAAIQAAYJ6SRUCAADAgAQAAYJ6SRUCAADAgAuAAQKfygAAhAACQk2JBQFAIMDABAACQk2JBQFAIMDAAAA.Crazyraptor:BAAALgAECgIJAgABLgAECgYJEAAJAAAAAA==.Crazèd:BAAALgADCgQJBAAAAA==.',
Cy='Cyndal:BAAALgAECgQJBgABLgAECgUJCQAJAAAAAA==.Cyndle:BAAALgAECgEJAgABLgAECgUJCQAJAAAAAA==.Cyntu:BAAALgAECgUJCQAAAA==.',
['Cü']='Cüpid:BAAALgAECgYJBgAAAA==.',
Da='Dada:BAAALgAECgEJAQAAAA==.Dammithells:BAAALgADCgQJBAAAAA==.Dandamar:BAAALgAECgYJBgAAAA==.Dankfists:BAAALgAECgUJBQAAAA==.Dankhaze:BAAALgAFFAIJAgAAAA==.Dark:BAAALgADCgEJAQAAAA==.Darthrevan:BAAALgAECgQJBwAAAA==.Dasharnkal:BAAALgADCgUJCAAAAA==.Dasvult:BAAALgAECgMJBAAAAA==.Dazex:BAABLgAECn8VAAMWAAYJSQKLPwCZAAAWAAUJRwKLPwCZAAADAAEJUwJAYQAgAAAAAA==.',
De='Deadpump:BAABLgAECn8fAAMXAAcJfRKiVABfAQAXAAcJfRKiVABfAQAYAAQJUQ4aOQDQAAAAAA==.Demonsnotkey:BAAALgAECgYJCwAAAA==.Demoxus:BAAALgAECgQJBAAAAA==.Denker:BAAALgADCggJCAAAAA==.Denkzilla:BAAALgADCgIJAgAAAA==.Denzvic:BAAALgAECgEJAQAAAA==.Destro:BAAALgAECgEJAQAAAA==.Deusclaw:BAAALgAECgYJCgAAAA==.Devilah:BAAALgAECgEJAQAAAA==.',
Dh='Dharm:BAABLgAECn8hAAMZAAYJaxtrTQBfAQAZAAYJaxtrTQBfAQAUAAEJEQ5OSgA5AAAAAA==.',
Di='Dialsl:BAAALgADCgUJBgAAAA==.Digbickpanda:BAAALgADCgYJBgABLgAFFAMJCAAKAEINAA==.Disowneege:BAABLgAECn8YAAIBAAcJNSB6JQAmAgABAAcJNSB6JQAmAgABLgAFFAYJFQAEAPUjAA==.Diyos:BAAALgADCgYJCgAAAA==.',
Do='Dotndash:BAAALgADCgIJAgAAAA==.Doubledge:BAAALgADCggJCAAAAA==.Doublejump:BAACLgAFFH8JAAIKAAQJUwwvMQASAQAKAAQJUwwvMQASAQAuAAQKfykAAgoACAk4HtcYAD8CAAoACAk4HtcYAD8CAAAA.',
Dr='Dragdh:BAAALgAECgQJCAABLgAECgcJIwAaAKwUAA==.Dragnas:BAABLgAECn8jAAMaAAcJrBQYKQDAAQAaAAcJrBQYKQDAAQAbAAYJTx/9CwCIAQAAAA==.Dragonisa:BAAALgAFFAEJAQAAAA==.Dragun:BAAALgADCgIJAgAAAA==.Draiocht:BAAALgADCgMJAwABLgAECgkJIwADAF0aAA==.Drakeskid:BAAALgAECgQJBwAAAA==.Drakthall:BAAALgAECgIJAwAAAA==.Dralionethny:BAAALgAECgIJAgAAAA==.Dramakiller:BAAALgAECgQJBAAAAA==.Drchi:BAAALgAECgEJAQABLgAECgQJFwAcAOgWAA==.Drcornbread:BAABLgAECn8XAAMcAAQJ6BYUFQAMAQAcAAQJ6BYUFQAMAQAdAAEJ0APcTQATAAAAAA==.Drcornellia:BAAALgAECgIJBAABLgAECgQJFwAcAOgWAA==.Drdarkskin:BAAALgAECgcJDAAAAA==.Drdreggs:BAABLgAECn8nAAMYAAkJmBZMCwA8AQAXAAgJuBSYTwDZAQAYAAYJmxdMCwA8AQAAAA==.Dreggs:BAAALgADCgcJBwAAAA==.Drizztin:BAAALgADCgEJAQAAAA==.Drprominus:BAABLgAECn8eAAIOAAgJXiExBgDsAgAOAAgJXiExBgDsAgAAAA==.Drthargyll:BAAALgADCgYJDgABLgAECggJHgAOAF4hAA==.',
Dy='Dykdanglr:BAAALgADCgYJBgABLgAECgQJCAAJAAAAAA==.',
['Dí']='Dígífóx:BAAALgAECgUJDAAAAA==.',
Ea='Earthereal:BAABLgAECn8nAAIVAAgJYhM/GwDDAQAVAAgJYhM/GwDDAQAAAA==.',
El='Elastar:BAABLgAECn8mAAIMAAkJ6Rb0CgDyAQAMAAkJ6Rb0CgDyAQAAAA==.Ellimist:BAECLgAFFH8UAAIaAAUJbBshCQC4AQAaAAUJbBshCQC4AQAuAAQKfyIAAxoACQmJGHQXAFoCABoACQmJGHQXAFoCABIABQk0FxdQAAcBAAAA.Elsan:BAAALgAECgEJAQAAAA==.Elycee:BAABLgAECn8XAAMZAAkJlyLHEACDAgAZAAgJNCHHEACDAgAeAAgJUhiWIAAhAgAAAA==.Elysria:BAAALgADCgYJBgAAAA==.Elí:BAAALgAECgQJBAAAAA==.',
En='Encrid:BAAALgAECgcJDgABLgAFFAMJBQAfAPwWAA==.Enhasa:BAABLgAECn8XAAIQAAkJwxOgMwDqAQAQAAkJwxOgMwDqAQABLgAECgYJGgABAOggAA==.Enoeht:BAABLgAECn8oAAICAAgJjwm2GwA2AQACAAgJjwm2GwA2AQAAAA==.Enveliria:BAAALgADCgYJBgABLgAECgkJOwACACglAA==.',
Er='Erazar:BAABLgAECn8tAAIgAAgJnRFeBgCfAQAgAAgJnRFeBgCfAQAAAA==.Eriah:BAAALgADCgkJCQAAAA==.Erickk:BAABLgAECn8wAAMNAAkJ5xvtLAAjAgANAAkJnBrtLAAjAgAhAAQJVx1SCwAkAQAAAA==.',
Es='Essense:BAABLgAECn8mAAIDAAkJmyRIAwApAwADAAkJmyRIAwApAwAAAA==.',
Ex='Exodari:BAABLgAECn87AAIbAAkJ6hikBQAuAgAbAAkJ6hikBQAuAgAAAA==.',
Fa='Fabbioh:BAAALgADCgEJAQAAAA==.Fadeddh:BAACLgAFFH8IAAIKAAMJQg1VQgDWAAAKAAMJQg1VQgDWAAAuAAQKfzAAAgoACQn+G2kWAE8CAAoACQn+G2kWAE8CAAAA.Faizarah:BAAALgAECgYJBgAAAA==.',
Fe='Fearnoevil:BAAALgADCgMJAwAAAA==.Fel:BAABLgAECn8RAAIKAAgJjBqgQQB1AQAKAAgJjBqgQQB1AQAAAA==.Fellkarras:BAAALgAECgYJCwABLgAECgkJMAAVADMeAA==.Fent:BAAALgAECgYJEAAAAA==.',
Fi='Fiddich:BAAALgAECgYJBgAAAA==.Fillthy:BAACLgAFFH8RAAIVAAYJHhZUCgC3AQAVAAYJHhZUCgC3AQAuAAQKfy4AAxUACQlYIkYDAEcDABUACQlYIkYDAEcDAAUAAwkhCctSAGoAAAAA.Finnigann:BAAALgAECgYJBgAAAA==.Firenmylazer:BAAALgADCgMJAwAAAA==.Fistav:BAAALgADCgcJDgAAAA==.Fizban:BAAALgAECggJEgAAAA==.',
Fl='Flappybird:BAAALgAECgMJAwABLgAFFAMJCAAKAEINAA==.Flasan:BAAALgADCgEJAQAAAA==.Flazz:BAAALgADCgIJAwAAAA==.Flazzan:BAAALgADCgEJAQAAAA==.',
Fo='Fogbringer:BAAALgAECgIJAwAAAA==.Four:BAAALgADCgQJBAAAAA==.',
Fr='Frejä:BAAALgAECgQJBQABLgAECgQJDAAJAAAAAA==.Freyah:BAAALgAECgUJCgAAAA==.Frostmay:BAAALgAECgIJAgAAAA==.',
Fu='Furrybawlz:BAAALgAECgUJCgABLgAECgYJDQAJAAAAAA==.',
Ga='Gabran:BAAALgAECgUJBQAAAA==.Gadogear:BAABLgAECn8gAAINAAcJcBjVVgCWAQANAAcJcBjVVgCWAQAAAA==.Garlik:BAAALgADCgMJBAAAAA==.',
Ge='Gertra:BAAALgAECgEJAgAAAA==.',
Gi='Girthrichard:BAAALgAECgYJDAAAAA==.',
Gl='Glassdragon:BAABLgAECn8hAAIBAAgJeAzDbwBDAQABAAgJeAzDbwBDAQAAAA==.Gllor:BAAALgADCgIJAgAAAA==.',
Go='Goatcheeze:BAABLgAECn8cAAIhAAkJLhV1AgDxAQAhAAkJLhV1AgDxAQAAAA==.Goatylocks:BAABLgAECn8iAAMYAAgJ5hVgCAB2AQAYAAYJLBxgCAB2AQAXAAYJIw1lZwAxAQAAAA==.Goldenchild:BAAALgAFFAIJAgABLgAFFAMJCAAKAEINAA==.',
Gr='Greatluckydo:BAAALgADCgEJAQAAAA==.',
Gu='Gulen:BAABLgAECn8VAAIaAAYJkSFuFwA6AgAaAAYJkSFuFwA6AgAAAA==.',
Gw='Gwendyla:BAAALgADCgYJCgAAAA==.',
['Gí']='Gíga:BAABLgAECn8XAAIZAAgJ7RPdKQAPAgAZAAgJ7RPdKQAPAgAAAA==.',
Ha='Hafnium:BAAALgADCgkJEAAAAA==.Hamish:BAAALgAECgMJAwAAAA==.Hanhaine:BAABLgAECn8aAAIHAAgJjw2JJABKAQAHAAgJjw2JJABKAQAAAA==.Hazirat:BAAALgAECgEJAQAAAA==.',
He='Hedlie:BAAALgAECggJCwAAAA==.Hellenkeller:BAACLgAFFH8HAAIVAAYJhw9wDACVAQAVAAYJhw9wDACVAQAuAAQKfxoAAhUABwkzITQTADMCABUABwkzITQTADMCAAAA.Heloisa:BAAALgAECgYJCgAAAA==.Helrazr:BAAALgAFFAEJAQAAAA==.Henshin:BAABLgAECn89AAMGAAkJtxwOEgB6AgAGAAkJtxwOEgB6AgAHAAIJOA5DZgA1AAAAAA==.',
Hi='Hitt:BAAALgAECgEJAgAAAA==.',
Ho='Holyhim:BAAALgADCgIJAgAAAA==.Hottyshmotty:BAAALgAECgEJAQAAAA==.Hourglass:BAABLgAECn8kAAMZAAgJ9hQsOwCdAQAZAAgJfxQsOwCdAQAeAAQJ1g3oXwDBAAAAAA==.',
Hu='Huntthejuan:BAAALgADCgUJBQAAAA==.',
Ic='Icyowneege:BAAALgADCgUJBQABLgAFFAYJFQAEAPUjAA==.Icywolfy:BAAALgAECgYJCAAAAA==.',
Ig='Igreetyou:BAABLgAECn8UAAIXAAcJQRbeRQCKAQAXAAcJQRbeRQCKAQAAAA==.',
Il='Illie:BAABLgAECn8mAAIbAAkJShyHBQCtAgAbAAkJShyHBQCtAgAAAA==.Illune:BAABLgAECn8lAAMNAAkJlhcwNgD+AQANAAkJlhcwNgD+AQAhAAYJUg4ZCQBbAQAAAA==.',
Im='Imanbearpig:BAAALgADCgIJAgAAAA==.Imleapingit:BAABLgAECn8kAAIEAAkJFyCPBgC6AgAEAAkJFyCPBgC6AgAAAA==.',
In='Intoodragons:BAABLgAECn8vAAMfAAkJkhNeFwDPAQAfAAkJkhNeFwDPAQAgAAYJWgX6JAD+AAAAAA==.Inyah:BAAALgAECgIJAgAAAA==.',
Io='Ionzz:BAABLgAECn8ZAAICAAkJqh+iCADYAgACAAkJqh+iCADYAgAAAA==.',
Ir='Iroann:BAAALgAECgYJDgAAAA==.',
Is='Isawarriorr:BAABLgAECn8sAAIMAAkJgyOJAwAfAwAMAAkJgyOJAwAfAwAAAA==.Ishaq:BAAALgAECgQJBQABLgAECggJFQAiACsFAA==.Ishdo:BAAALgADCgMJAwABLgAECggJFQAiACsFAA==.Ishkhan:BAABLgAECn8VAAMiAAgJKwVWNQDtAAAiAAgJQgRWNQDtAAAFAAYJUQUbQQCtAAAAAA==.Ishmael:BAAALgAFFAMJBAAAAA==.Ishwar:BAAALgADCgYJBgAAAA==.',
Ja='Jakytreehorn:BAACLgAFFH8HAAMaAAUJKQXMNgCoAAAaAAQJZQTMNgCoAAASAAIJowLPOgA2AAAuAAQKfyQAAxoACQkqEgwoAPABABoACQkqEgwoAPABABIABwkMDygyABoBAAAA.Jasher:BAAALgAECgYJBgAAAA==.Jaydm:BAABLgAECn8VAAIjAAYJgBQCGQA2AQAjAAYJgBQCGQA2AQABLgAFFAYJDQANAOkMAA==.',
Je='Jenevelle:BAAALgAECgQJBQAAAA==.Jerisil:BAAALgADCgQJBAAAAA==.Jet:BAABLgAECn8aAAIBAAYJ6CAySwABAgABAAYJ6CAySwABAgAAAA==.',
Ji='Jibbajabba:BAAALgADCgcJBwAAAA==.Jimbo:BAAALgAFFAIJAwABLgAFFAYJFQAQAOkkAA==.',
Ju='Judgecalypso:BAAALgAECgQJBQAAAA==.Julthaenia:BAABLgAECn8ZAAQkAAYJExpFCgBNAQAkAAUJTR5FCgBNAQAXAAUJcQvmvACDAAAYAAQJGArYJQBVAAABLgAECgkJOwACACglAA==.Justeatjuan:BAAALgAECgMJAwAAAA==.',
Ka='Kagebushin:BAAALgAECgMJBAAAAA==.Kalazin:BAAALgAECgUJBQAAAA==.Kalimah:BAAALgADCgMJAwAAAA==.Karnrae:BAABLgAECn8eAAIBAAgJFBE3UQCLAQABAAgJFBE3UQCLAQAAAA==.Karynos:BAABLgAECn8kAAMXAAkJeAqPRQCLAQAXAAkJSQmPRQCLAQAYAAcJyQkOIwA/AQAAAA==.Katnelly:BAAALgAECgIJAgAAAA==.Kazmacoryy:BAAALgAECgYJCgAAAA==.',
Ke='Keedis:BAAALgADCggJCwAAAA==.',
Ki='Kileely:BAAALgAECgMJAwAAAA==.Kirintore:BAAALgAECgUJCQAAAA==.',
Kl='Klaudeus:BAAALgAECgEJAQAAAA==.',
Ko='Kodian:BAAALgADCgEJAQAAAA==.Kolypso:BAAALgAECgYJDgAAAA==.Konceal:BAAALgAECgEJAQAAAA==.Konspiracy:BAABLgAECn8oAAIYAAgJUxk2BAD0AQAYAAgJUxk2BAD0AQAAAA==.Konvict:BAAALgAECgIJAwABLgAECgYJDQAJAAAAAA==.',
Kr='Krataar:BAABLgAECn8gAAIEAAkJEyFBBQDSAgAEAAkJEyFBBQDSAgAAAA==.Kravvan:BAAALgADCgEJAQABLgAECggJEgAJAAAAAA==.Krousvor:BAAALgAECgQJBwAAAA==.Kryph:BAABLgAECn8VAAIQAAYJ2Am9mQDqAAAQAAYJ2Am9mQDqAAAAAA==.',
Ku='Kugruk:BAAALgAECgcJDAAAAA==.Kurjo:BAAALgAECgMJBAAAAA==.',
Ky='Kyleschlong:BAAALgAECgMJCAAAAA==.',
['Kä']='Kämpfer:BAABLgAECn86AAIEAAgJnB3+DwAwAgAEAAgJnB3+DwAwAgAAAA==.',
La='Lafiel:BAABLgAECn8dAAMDAAkJGgtKPABJAQADAAkJGgtKPABJAQAIAAIJ1QjaUgBdAAAAAA==.Landiedoo:BAAALgAECgkJCgAAAA==.Laverna:BAAALgADCgMJBAAAAA==.',
Le='Lefay:BAAALgADCgcJEwAAAA==.Leprawnjames:BAAALgAECgIJAgABLgAECgYJDgAJAAAAAA==.Letsgetwet:BAAALgADCgYJBgAAAA==.',
Li='Liefic:BAAALgAECgYJCAAAAA==.Limon:BAAALgADCgIJAgAAAA==.',
Lo='Loadin:BAAALgAECgIJAgAAAA==.Lockaflockå:BAAALgADCgMJAwAAAA==.Locke:BAAALgAECgMJAgABLgAECgYJGgABAOggAA==.Lonoh:BAAALgAECgcJEgAAAA==.',
Lu='Luan:BAAALgADCgEJAQAAAA==.Lucariø:BAAALgADCgcJDAAAAA==.Lucidbonsai:BAAALgADCggJCAAAAA==.Luckykilla:BAABLgAECn8eAAIlAAgJhxl8BQDXAQAlAAgJhxl8BQDXAQAAAA==.Lucÿ:BAACLgAFFH8JAAIaAAQJeglLKQDiAAAaAAQJeglLKQDiAAAuAAQKfyIAAxoABwmsGPQoAOwBABoABwmsGPQoAOwBABIAAwkVDJVWAIcAAAAA.Lula:BAAALgADCgMJAwAAAA==.Lurith:BAABLgAECn8vAAMRAAgJZxDlGABBAQARAAgJrQ7lGABBAQAQAAYJrQjYuAARAQAAAA==.Lutreaux:BAAALgADCgEJAQAAAA==.Luxtyrannica:BAAALgAECgYJEwAAAA==.',
Ly='Lydrain:BAAALgAECgEJAQAAAA==.Lysandria:BAABLgAECn8pAAINAAkJmg0+SQC8AQANAAkJmg0+SQC8AQAAAA==.',
Ma='Macrosblack:BAAALgADCgMJAwAAAA==.Madamerouge:BAAALgAECgIJAgABLgAECgQJFwAcAOgWAA==.Magearino:BAABLgAECn8dAAINAAYJbhmodwBLAQANAAYJbhmodwBLAQAAAA==.Marcopally:BAAALgAECgQJBAAAAA==.Marluxia:BAACLgAFFH8YAAIdAAUJ8gekCgDCAAAdAAUJ8gekCgDCAAAuAAQKfxoAAh0ACAkhE/YMALkBAB0ACAkhE/YMALkBAAAA.Materfamilia:BAAALgAECgQJBAAAAA==.Mattbull:BAACLgAFFH8FAAMfAAMJ/BY6JgDqAAAfAAMJ/BY6JgDqAAAgAAEJ1xNICQBXAAAuAAQKfx0AAx8ABgmqJC8WANsBACAABglCIlcNAAQCAB8ABgl5Ii8WANsBAAAA.',
Me='Medjrab:BAACLgAFFH8NAAIQAAQJchYZNgBIAQAQAAQJchYZNgBIAQAuAAQKfzIAAhAACQlIIpYJAO0CABAACQlIIpYJAO0CAAAA.Meristem:BAABLgAECn8iAAIHAAgJFg7IIABmAQAHAAgJFg7IIABmAQAAAA==.Merko:BAAALgADCggJCAAAAA==.',
Mi='Miaan:BAAALgADCgYJBgAAAA==.Miette:BAAALgADCgMJAwAAAA==.Mihonk:BAAALgADCgQJBAAAAA==.Mintycrx:BAABLgAECn8YAAINAAkJFw7IQQDUAQANAAkJFw7IQQDUAQAAAA==.Missfist:BAAALgADCgIJAgAAAA==.Mistlocke:BAAALgADCgMJAwAAAA==.',
Mn='Mngwa:BAAALgAECgIJBQAAAA==.',
Mo='Moegu:BAABLgAECn8XAAImAAgJ5RJzCACWAQAmAAgJ5RJzCACWAQAAAA==.Mog:BAABLgAECn82AAQXAAkJYyPmDACzAgAXAAcJkiPmDACzAgAkAAMJliO/DQAOAQAYAAMJHBHCNgDbAAAAAA==.Moncatsera:BAAALgAECgQJBAAAAA==.Mondgrille:BAAALgAECgQJBAABLgAECgYJDQAJAAAAAA==.Monora:BAAALgAECgcJEwAAAA==.Montress:BAAALgAECgcJCgAAAA==.Moomoohealz:BAABLgAECn82AAIHAAkJJyHyBADRAgAHAAkJJyHyBADRAgAAAA==.Moonbounds:BAACLgAFFH8bAAIaAAYJ3Rz8BAD9AQAaAAYJ3Rz8BAD9AQAuAAQKfzgAAxoACQndJFEDAEQDABoACQndJFEDAEQDABIAAQnZH4Z5AF0AAAAA.Moondoggey:BAAALgAECgMJAwAAAA==.Morgana:BAAALgADCgIJAgAAAA==.Mousechief:BAABLgAECn8dAAISAAcJYQSIRgDBAAASAAcJYQSIRgDBAAAAAA==.Moxnix:BAAALgAECgcJDwAAAA==.Moxxzi:BAAALgAFFAEJAQAAAA==.',
Mu='Muhfookinbak:BAABLgAECn8fAAMaAAkJhB04DQCfAgAaAAkJhB04DQCfAgASAAQJhxhlQQDVAAAAAA==.',
My='Myor:BAAALgADCgMJAwAAAA==.',
['Mà']='Màttbull:BAAALgAFFAIJBAABLgAFFAMJBQAfAPwWAA==.',
Na='Naesta:BAAALgAECgIJAgABLgAECggJIQAGAAEgAA==.Naksù:BAAALgAECgUJDgAAAA==.Namal:BAAALgAECgQJBQAAAA==.Narenae:BAABLgAECn8lAAIFAAkJCyRABABIAwAFAAkJCyRABABIAwAAAA==.Nastalan:BAAALgADCgYJCgAAAA==.',
Ne='Nefari:BAAALgADCgMJAwAAAA==.Neifeb:BAABLgAECn8gAAIZAAgJbxcCNQC2AQAZAAgJbxcCNQC2AQAAAA==.Nephthys:BAAALgADCgQJBAAAAA==.',
Ni='Niallivdam:BAABLgAECn8eAAMgAAcJxxc1CgA1AQAgAAYJGRU1CgA1AQATAAYJpBfWFAAyAQAAAA==.Nightsoul:BAAALgADCgEJAQAAAA==.Ninh:BAABLgAECn8+AAIVAAkJ0A5GJQBxAQAVAAkJ0A5GJQBxAQAAAA==.',
No='Nomissius:BAAALgADCgcJDQAAAA==.Nooblè:BAAALgADCgMJAwAAAA==.Notsodemon:BAABLgAECn8ZAAMKAAgJEhSOXwCCAQAKAAgJEhSOXwCCAQACAAIJnwrPYwBUAAAAAA==.Notsoevoker:BAAALgAECgMJAwABLgAECggJGQAKABIUAA==.Notsomonk:BAAALgADCgMJAwABLgAECggJGQAKABIUAA==.',
Ny='Nykara:BAAALgAECgUJBQAAAA==.',
['Nå']='Nåld:BAAALgAECgEJAQAAAA==.',
Ob='Obvinotagirl:BAAALgAECggJDwAAAA==.',
Og='Ogsikko:BAAALgAECgYJCwABLgAECggJGAAXAJAeAA==.Ogsikkotv:BAABLgAECn8YAAINAAYJ/BmQhwDCAQANAAYJ/BmQhwDCAQABLgAECggJGAAXAJAeAA==.',
Ok='Okathra:BAAALgAECgQJBAABLgAECgkJLwAbAFchAA==.',
On='Onebadmutha:BAAALgAECggJEQAAAA==.Ontop:BAABLgAECn8oAAIZAAkJ7xsaHABeAgAZAAkJ7xsaHABeAgAAAA==.',
Or='Orb:BAABLgAECn8jAAQBAAkJ4Ra4PADJAQABAAgJkxi4PADJAQALAAUJQQ/EHgATAQAOAAgJuQvyOwAFAQAAAA==.Orcfreeza:BAAALgAECgQJDAAAAA==.Ortinks:BAAALgAECgYJEAAAAA==.',
Ow='Owneege:BAACLgAFFH8VAAIEAAYJ9SPDAQDuAQAEAAYJ9SPDAQDuAQAuAAQKfzMAAgQACQkEIx4CAKADAAQACQkEIx4CAKADAAAA.',
Pa='Painsaw:BAAALgADCgYJBgAAAA==.Pallinar:BAABLgAECn8oAAIBAAgJVhQgRgCrAQABAAgJVhQgRgCrAQAAAA==.Pasquale:BAABLgAECn8hAAIiAAcJRSEwDgAXAgAiAAcJRSEwDgAXAgAAAA==.',
Pe='Pebbles:BAAALgAECgcJDAAAAA==.Pedroia:BAAALgAECgYJBwAAAA==.Pesty:BAAALgAECgMJCQAAAA==.',
Ph='Phe:BAABLgAECn8XAAMHAAcJgw7gKgAhAQAHAAcJgw7gKgAhAQAGAAYJpQvzcAADAQAAAA==.Pheraree:BAAALgAECgEJAQAAAA==.Phooboo:BAAALgAECgkJBQAAAA==.',
Pi='Pidion:BAAALgADCgYJDAAAAA==.Pilgrimm:BAACLgAFFH8QAAMnAAUJmCBKBAAQAQAPAAMJpyAgCwA4AQAnAAQJeR5KBAAQAQAuAAQKfyQAAw8ACQl7IrIDAGADAA8ACQl0IrIDAGADACcABQkIH7oHAGwBAAEuAAUUBgkHABUAhw8A.',
Pl='Plaguerott:BAABLgAECn83AAIoAAkJeQ/uBgCxAQAoAAkJeQ/uBgCxAQAAAA==.Plusultra:BAAALgADCgkJEQAAAA==.Pluto:BAAALgAECgYJCQAAAA==.',
Po='Poby:BAAALgADCgcJBwAAAA==.Polydh:BAABLgAECn8sAAImAAkJiyRlAABGAwAmAAkJiyRlAABGAwAAAA==.Poobah:BAABLgAECn8jAAMSAAgJvAapPQDkAAASAAcJfAapPQDkAAAaAAcJCQNJYgDIAAAAAA==.Popscotch:BAABLgAECn8jAAMkAAkJEQ3OCQCkAQAkAAcJRg7OCQCkAQAXAAkJvwv9QACaAQAAAA==.Pouffant:BAABLgAECn8iAAIBAAkJyBPuNwDaAQABAAkJyBPuNwDaAQAAAA==.',
Pr='Pronoz:BAABLgAECn8cAAIBAAcJtg9SagBPAQABAAcJtg9SagBPAQAAAA==.',
Pu='Punchy:BAAALgADCgEJAQAAAA==.',
Pw='Pwnageddon:BAABLgAECn8fAAMLAAgJZRrVCQDYAQALAAcJxRzVCQDYAQABAAUJhxUW4gDJAAAAAA==.Pwnjitsu:BAABLgAECn8yAAIFAAkJrCFQAwD4AgAFAAkJrCFQAwD4AgAAAA==.',
Py='Pyrothermia:BAACLgAFFH8NAAINAAYJ6QwwIAB/AQANAAYJ6QwwIAB/AQAuAAQKfyUAAg0ACQlGG4oqAMgCAA0ACQlGG4oqAMgCAAAA.',
Qt='Qtkillz:BAAALgADCgQJBAAAAA==.',
Ra='Rancayden:BAAALgAECgEJAQAAAA==.Rawhoof:BAABLgAECn8+AAIEAAkJASW3AQA4AwAEAAkJASW3AQA4AwAAAA==.Razak:BAABLgAECn8vAAIbAAkJVyEPAQAIAwAbAAkJVyEPAQAIAwAAAA==.',
Re='Renisa:BAABLgAECn8iAAIKAAgJqRnDNwCaAQAKAAgJqRnDNwCaAQAAAA==.Retman:BAABLgAECn8UAAIBAAcJtg8BpADkAAABAAcJtg8BpADkAAAAAA==.Reu:BAAALgAECgUJBwAAAA==.Revlyk:BAABLgAECn8gAAIbAAcJFiIWBgAfAgAbAAcJFiIWBgAfAgABLgAECgkJOwACACglAA==.Rezloh:BAAALgADCgMJAQAAAA==.',
Ri='Rintaro:BAABLgAECn8aAAILAAkJcwmNHwAMAQALAAkJcwmNHwAMAQAAAA==.Ritanana:BAAALgAECgIJAgAAAA==.',
Ro='Roccot:BAAALgAECggJDgAAAA==.Roflstomp:BAAALgAECgQJBwABLgAECgYJDgAJAAAAAA==.Roostrr:BAABLgAECn8XAAIBAAYJ4B2EcwCUAQABAAYJ4B2EcwCUAQAAAA==.Rotjaw:BAAALgAECgUJCwAAAA==.Roughedge:BAAALgADCgIJAgAAAA==.',
Ru='Rurik:BAAALgAECgEJAQAAAA==.',
['Rè']='Rèjuva:BAAALgAECgcJDQAAAA==.',
['Rî']='Rîcflair:BAAALgAECgcJEwAAAA==.',
Sa='Saiyax:BAAALgADCgYJBwAAAA==.Salidfingers:BAAALgADCgYJBgAAAA==.Sanyakulak:BAAALgADCgcJBwABLgAFFAcJFgAdADUVAA==.Sanzo:BAAALgADCgkJDAAAAA==.Savathûn:BAAALgAECgQJCAAAAA==.',
Sc='Scalycat:BAABLgAECn8qAAQTAAkJ2A6cGQDBAQATAAkJ2A6cGQDBAQAfAAcJKgahSQCvAAAgAAIJbgfoHQAwAAAAAA==.Schalla:BAAALgAECgEJAQAAAA==.Scum:BAAALgAECgYJDQAAAA==.Scòrpìòn:BAAALgADCgcJBgABLgAFFAMJBQAZAA8iAA==.',
Se='Seancody:BAAALgADCgIJAgAAAA==.Selandria:BAAALgADCgQJBAAAAA==.Senate:BAAALgAECgYJCwAAAA==.',
Sh='Shadowbear:BAABLgAECn8cAAIIAAcJ/ByNFADZAQAIAAcJ/ByNFADZAQAAAA==.Shadowoss:BAAALgAECgIJAgAAAA==.Shadygrump:BAAALgAECgYJEQAAAA==.Shaolincito:BAAALgAECgQJBgAAAA==.Sherrilyn:BAAALgADCgkJFQAAAA==.Shocklocke:BAAALgAECgQJBAAAAA==.',
Si='Sigmachad:BAAALgAECgUJCgAAAA==.Silandrus:BAAALgAECgEJAQAAAA==.Silverocean:BAABLgAECn8uAAIOAAkJ0BvqDwCUAgAOAAkJ0BvqDwCUAgAAAA==.Silvia:BAAALgADCgUJCQAAAA==.Singularity:BAABLgAECn87AAIMAAkJRCZgAABwAwAMAAkJRCZgAABwAwAAAA==.',
Sk='Skaerx:BAABLgAECn8WAAMEAAYJVBeOQwCXAQAEAAYJ9RWOQwCXAQAjAAQJZhSYHQADAQAAAA==.Skittlez:BAABLgAECn8mAAIUAAkJkR/BBACpAgAUAAkJkR/BBACpAgAAAA==.',
Sl='Slaykween:BAAALgAECgYJCgAAAA==.Slootybooty:BAAALgAECgYJDgAAAA==.',
Sm='Smallz:BAAALgAECgYJDwABLgAECggJEgAJAAAAAA==.',
Sn='Snipersmash:BAAALgAECgQJCAAAAA==.Snooptrogg:BAABLgAECn8jAAIEAAgJQBXvHwChAQAEAAgJQBXvHwChAQAAAA==.Snoozumi:BAABLgAFFH8GAAIVAAMJKQY9IwCfAAAVAAMJKQY9IwCfAAAAAA==.Snuups:BAABLgAECn8xAAIXAAkJKhliIQAgAgAXAAkJKhliIQAgAgAAAA==.',
So='Soldiah:BAABLgAECn8VAAIEAAgJqQzYKQBhAQAEAAgJqQzYKQBhAQAAAA==.Sommbra:BAAALgAECgYJBwAAAA==.Souljax:BAAALgADCgcJCQAAAA==.',
Sp='Spacelaser:BAAALgAECgQJBQAAAA==.',
Sq='Sqwurl:BAAALgADCgQJBAAAAA==.',
St='Steakhaus:BAAALgADCgIJAgAAAA==.Stiros:BAAALgADCgUJBgAAAA==.Stonedragon:BAECLgAFFH8PAAIZAAQJnx8NDwBuAQAZAAQJnx8NDwBuAQAuAAQKfysAAxkACAn+JMwFADEDABkACAn+JMwFADEDAB4AAgn/DsMiAGIAAAAA.Stormfist:BAAALgAECgcJDgAAAA==.Stormhaven:BAAALgADCggJIQABLgAECgYJFQAOANMiAA==.Stormrender:BAAALgAECgYJEAAAAA==.Stouty:BAAALgADCgMJAwABLgAECgcJFAAgAOkaAA==.',
Su='Sukonamí:BAABLgAECn8iAAMEAAkJghckKAAdAgAEAAgJdRUkKAAdAgAjAAQJGhv4FwA+AQAAAA==.Suzhou:BAABLgAECn8jAAIYAAgJown4DQASAQAYAAgJown4DQASAQAAAA==.Suzoomies:BAAALgADCgcJBwAAAA==.Suzumii:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetcarolin:BAABLgAECn8WAAIQAAkJRg+GXgDXAQAQAAkJRg+GXgDXAQAAAA==.Sweetsmercy:BAAALgAECgQJBQAAAA==.Swiftleaf:BAAALgADCgcJBwAAAA==.Swisscheese:BAABLgAECn8jAAIXAAgJgyArFwBgAgAXAAgJgyArFwBgAgAAAA==.',
Sy='Syraxa:BAAALgAECgEJAQABLgAFFAMJBwAGAEgNAA==.Syril:BAAALgADCgcJDAAAAA==.',
Ta='Tahret:BAAALgADCgQJBQAAAA==.Taquillya:BAAALgAECgIJAgAAAA==.Tarina:BAAALgADCgEJAQAAAA==.Tatersaladin:BAAALgADCgMJAwAAAA==.',
Te='Tenlortin:BAAALgAECgEJAQAAAA==.Terragosa:BAABLgAECn8mAAINAAgJ4hWxPQDiAQANAAgJ4hWxPQDiAQAAAA==.Teryail:BAAALgADCggJCAAAAA==.Tetchybono:BAAALgADCgYJBgAAAA==.',
Th='Thade:BAABLgAECn8fAAMjAAkJdCBTBACKAgAjAAgJFh5TBACKAgAEAAcJUB5XHwBWAgAAAA==.Thaeleon:BAABLgAECn8hAAMHAAgJaR9rCwBRAgAHAAgJaR9rCwBRAgAGAAYJixz+NADUAQABLgAFFAMJBAAJAAAAAA==.Thaneblade:BAAALgAECgIJAgAAAA==.Therizzler:BAAALgAECgUJBQABLgAFFAMJCAAKAEINAA==.Thickening:BAABLgAECn8ZAAMVAAUJhQ16PwDSAAAVAAUJhQ16PwDSAAAFAAUJ9QdaQgCoAAAAAA==.Thope:BAAALgAECgYJEgAAAA==.Thoranubran:BAABLgAECn8WAAICAAYJ/w5bIwD2AAACAAYJ/w5bIwD2AAAAAA==.Thrivia:BAAALgAECgYJBgAAAA==.',
Ti='Ticklemychin:BAAALgAECgMJAwAAAA==.Tigani:BAAALgAECgUJDAAAAA==.Tinstey:BAAALgADCgEJAQAAAA==.',
To='Tokemaddab:BAAALgADCgUJBQAAAA==.',
Tr='Trainar:BAAALgAECgQJCAAAAA==.Trickybackup:BAAALgADCgMJAwAAAA==.Triggs:BAAALgAECgcJAgAAAA==.Trollbear:BAAALgAECgcJDwAAAA==.Trondruid:BAAALgADCgYJDQAAAA==.Trooze:BAABLgAECn8nAAIOAAcJpiSFCAC+AgAOAAcJpiSFCAC+AgAAAA==.Trr:BAABLgAECn8pAAIXAAkJmBe2IwCFAgAXAAkJmBe2IwCFAgAAAA==.Truckzage:BAAALgADCgcJBwABLgAECggJJQAZAB8eAA==.',
Tu='Tuba:BAAALgAECgYJEAAAAA==.Turim:BAAALgADCgkJDQAAAA==.Tusksrus:BAAALgADCgcJFwAAAA==.',
Ty='Tyrlidd:BAABLgAECn8nAAIZAAgJzw9SPwCPAQAZAAgJzw9SPwCPAQAAAA==.',
Ud='Udon:BAAALgAFFAEJAQAAAA==.',
Ul='Ultimazero:BAAALgADCgEJAQAAAA==.',
Un='Unavoidable:BAAALgADCgkJEQAAAA==.Unlikelytale:BAABLgAECn8lAAIaAAkJAyGcCQDPAgAaAAkJAyGcCQDPAgAAAA==.Unmilked:BAAALgAECgIJAgAAAA==.',
Ur='Uricash:BAABLgAECn8+AAINAAkJ+BmbIABfAgANAAkJ+BmbIABfAgAAAA==.Urzual:BAABLgAECn8jAAIbAAgJDB9RBgAYAgAbAAgJDB9RBgAYAgAAAA==.',
Ut='Utiniócast:BAAALgADCgEJAQAAAA==.',
Va='Vandreynna:BAABLgAECn87AAICAAkJKCXPAABXAwACAAkJKCXPAABXAwAAAA==.',
Ve='Vegèta:BAABLgAECn8fAAIQAAkJZAuuWABzAQAQAAkJZAuuWABzAQABLgAFFAMJBQAZAA8iAA==.Veilaura:BAAALgAECgQJBgAAAA==.Velarria:BAABLgAECn8dAAMZAAkJ4h43FQCOAgAZAAkJ4h43FQCOAgAUAAQJjwwcIQDSAAAAAA==.Velikan:BAAALgAECgQJBwABLgAECgcJCAAJAAAAAA==.Velsiana:BAAALgAECgQJBwAAAA==.Velveetah:BAAALgAECgIJBAABLgAECgQJFwADADMTAA==.Verdreht:BAAALgADCgEJAQABLgAECggJOgAEAJwdAA==.Verita:BAABLgAECn8rAAInAAcJcCOsAgBKAgAnAAcJcCOsAgBKAgAAAA==.Verylikely:BAAALgAECgEJAgAAAA==.',
Vi='Viviann:BAABLgAECn8kAAITAAkJeRGMCwDVAQATAAkJeRGMCwDVAQAAAA==.',
Vo='Voiager:BAAALgADCgcJCgAAAA==.',
Vr='Vrakal:BAAALgAECgkJDQAAAA==.',
Wa='Wantabehavoc:BAAALgADCgYJDQAAAA==.Wantadeznutz:BAAALgAECgIJAgAAAA==.Warnick:BAAALgADCgQJBQAAAA==.Warraxe:BAAALgADCgUJCAAAAA==.Wayloren:BAABLgAECn8iAAIBAAgJRAnocgA8AQABAAgJRAnocgA8AQAAAA==.Waystalker:BAAALgAECgMJAwAAAA==.Wayverly:BAAALgADCgUJBwABLgAECgcJEAAJAAAAAA==.',
Wi='Wickathy:BAABLgAECn8zAAImAAkJbh6nAQDGAgAmAAkJbh6nAQDGAgAAAA==.',
Wo='Wolfcity:BAAALgADCgEJAQAAAA==.Wondertauren:BAAALgADCgUJBwAAAA==.Woodson:BAAALgADCgkJCQAAAA==.Worstdps:BAAALgADCgcJEwAAAA==.',
Wr='Wrkandtank:BAAALgAECgEJAQABLgAECgYJEAAJAAAAAA==.',
Wu='Wuldorr:BAACLgAFFH8JAAIBAAQJGQoyLQAiAQABAAQJGQoyLQAiAQAuAAQKfyQAAgEACAmvH0gkAJYCAAEACAmvH0gkAJYCAAAA.',
Wy='Wynnifred:BAAALgAECggJDQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.',
Xe='Xethreal:BAAALgADCgMJAwAAAA==.',
Xy='Xype:BAAALgAECgkJEQAAAA==.',
Ya='Yastoria:BAAALgAECgcJEAAAAA==.',
Yi='Yinandtonic:BAAALgAECgEJAwAAAA==.',
Yv='Yvvee:BAAALgADCgcJBwAAAA==.',
Za='Zaalim:BAAALgADCgQJBAAAAA==.Zapdôs:BAAALgAECgQJBAAAAA==.',
Ze='Zeda:BAAALgADCgcJCQABLgAECgUJCQAJAAAAAA==.Zephyris:BAAALgAECgUJDAABLgAFFAYJHAAjAPElAA==.',
Zh='Zheng:BAAALgAECgYJBgAAAA==.',
Zi='Zillia:BAAALgADCgMJAwAAAA==.',
Zo='Zonora:BAAALgAECgcJDgAAAA==.',
Zy='Zyphexd:BAAALgAECgYJDwAAAA==.Zyris:BAAALgADCgcJDQAAAA==.',
['Àz']='Àzñós:BAAALgAECgQJBAAAAA==.',
['Äs']='Ästro:BAAALgAECgQJBgAAAA==.',
['Äz']='Äzrael:BAABLgAECn8jAAIDAAkJXRpICACfAgADAAkJXRpICACfAgAAAA==.',
['Åz']='Åznos:BAAALgAECgQJCAAAAA==.',
['Çr']='Çréwüsæðèr:BAABLgAECn8jAAIMAAgJZSA/BgBmAgAMAAgJZSA/BgBmAgAAAA==.',
['Ðe']='Ðecimus:BAAALgAECgQJCQAAAA==.',
['Ðì']='Ðìaßlo:BAACLgAFFH8FAAIZAAMJDyIQKgAUAQAZAAMJDyIQKgAUAQAuAAQKfywABBkACAk2HBMuANIBABkABwkXGxMuANIBABQABwlYFAQRALMBAB4AAQleABqbABUAAAAA.',
['Öb']='Öblïvïöñ:BAAALgADCgkJEgAAAA==.',
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
