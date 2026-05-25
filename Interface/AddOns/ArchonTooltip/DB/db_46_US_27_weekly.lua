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

local lookup = {'Warlock-Destruction','Hunter-BeastMastery','Unknown-Unknown','Mage-Arcane','Mage-Frost','Hunter-Survival','DeathKnight-Frost','DeathKnight-Unholy','Priest-Shadow','Paladin-Retribution','Priest-Holy','Hunter-Marksmanship','Paladin-Protection','DemonHunter-Devourer','DeathKnight-Blood','Monk-Mistweaver','Monk-Windwalker','Paladin-Holy','Druid-Balance','Shaman-Restoration','Rogue-Subtlety','DemonHunter-Havoc','Rogue-Outlaw','Rogue-Assassination','Warlock-Demonology','Priest-Discipline','Monk-Brewmaster','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warrior-Fury','Druid-Feral','Druid-Restoration','Druid-Guardian','Warrior-Arms','Shaman-Elemental','Shaman-Enhancement','Warlock-Affliction',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aaravos:BAABLgAECn8UAAIBAAgJLxNlCACZAQABAAgJLxNlCACZAQAAAA==.',
Ab='Abysseon:BAAALgAECgUJDQAAAA==.',
Ac='Accretion:BAAALgAECgYJBgAAAA==.',
Ad='Adaria:BAABLgAECn8WAAICAAcJWAWSZQA3AQACAAcJWAWSZQA3AQAAAA==.Adrillbear:BAAALgAECgIJAgABLgAECgYJDgADAAAAAA==.Adura:BAAALgADCgcJDwAAAA==.',
Ae='Aeirith:BAABLgAECn8kAAMEAAkJsB1LAQCBAgAEAAkJsB1LAQCBAgAFAAEJRQr0NgEyAAAAAA==.Aelion:BAAALgAECgEJAQAAAA==.',
Ah='Ahheevoker:BAAALgAECgYJEgAAAA==.',
Ai='Ailsà:BAAALgADCgEJAQAAAA==.',
Al='Aladaria:BAAALgAECgMJAwAAAA==.Aldyah:BAAALgAECgYJCQAAAA==.Alias:BAAALgAECgYJBQAAAA==.Allanonn:BAAALgAECgQJBAAAAA==.Alohomora:BAAALgAECgUJEAAAAA==.Alvist:BAAALgAECgQJDgAAAA==.',
Am='Amarasu:BAABLgAECn8ZAAIGAAgJUxBMHgCLAQAGAAgJUxBMHgCLAQAAAA==.Amarlly:BAABLgAECn8gAAIHAAcJuhW2DQBOAQAHAAcJuhW2DQBOAQAAAA==.Amenedil:BAAALgAECgUJDAAAAA==.',
An='Anbrew:BAAALgAECgUJCQABLgAFFAYJDwAIAN0dAA==.Ancelina:BAABLgAECn8bAAIJAAYJGSPaFwDkAQAJAAYJGSPaFwDkAQAAAA==.Anderton:BAABLgAECn8mAAIKAAcJwxlbUwCxAQAKAAcJwxlbUwCxAQAAAA==.Andilocks:BAAALgADCgMJAwAAAA==.Aneira:BAAALgAECgQJBwAAAA==.Annovera:BAAALgAECgMJBgAAAA==.Anuubis:BAAALgADCgYJBgAAAA==.Anyi:BAAALgAECgEJAQAAAA==.',
Ap='Apexxd:BAAALgADCgEJAQAAAA==.Applefritter:BAAALgAECgQJBAABLgAECggJIwALAFAUAA==.',
Ar='Archérhiro:BAACLgAFFH8dAAMCAAcJiRb/BwC6AQACAAYJChr/BwC6AQAMAAMJRwTfIQCHAAAuAAQKfygAAwIACQnrHjQSAJYCAAIACQnfHjQSAJYCAAwACAkrGdobAEoCAAAA.Arilias:BAAALgAECgEJAQABLgAECgkJJgACACMRAA==.Arillann:BAABLgAECn89AAINAAkJUR9UAwC4AgANAAkJUR9UAwC4AgAAAA==.Arrook:BAAALgADCgMJAwAAAA==.Arte:BAABLgAECn89AAICAAkJaxMRNwDWAQACAAkJaxMRNwDWAQAAAA==.Arthundermis:BAAALgAECgkJEQAAAA==.Artlunarmis:BAAALgADCgEJAQABLgAECgkJEQADAAAAAA==.Arvena:BAABLgAECn8nAAIOAAkJVgopYABEAQAOAAkJVgopYABEAQAAAA==.',
As='Asclëpius:BAAALgADCgcJBgABLgAECgEJAQADAAAAAA==.Asheron:BAAALgAECgYJCAAAAA==.Ashymage:BAACLgAFFH8MAAIFAAQJYBYNQwA/AQAFAAQJYBYNQwA/AQAuAAQKfzcAAgUACQlYHLYpAMwCAAUACQlYHLYpAMwCAAAA.Askevar:BAABLgAECn8dAAMIAAcJAgy6jgAiAQAIAAcJkwm6jgAiAQAPAAYJ5wlHJwAEAQAAAA==.Aspect:BAAALgADCgEJAQABLgAFFAIJAgADAAAAAA==.Asriél:BAAALgAECgQJBAAAAA==.Astrona:BAAALgADCgkJFwAAAA==.',
At='Atreus:BAABLgAECn8WAAIKAAgJMQWGugDtAAAKAAgJMQWGugDtAAAAAA==.Attalaguy:BAAALgAECgYJDgAAAA==.',
Au='Audra:BAAALgADCgUJBwAAAA==.',
Av='Avabeatrix:BAAALgADCgEJAQAAAA==.Avinthoro:BAAALgADCgIJAgAAAA==.',
Ay='Ayyayyron:BAAALgAECgUJBgAAAA==.',
Az='Azaleah:BAABLgAECn80AAIKAAkJLha1MQAYAgAKAAkJLha1MQAYAgAAAA==.Azanoth:BAAALgADCgIJAgAAAA==.Azraesha:BAABLgAECn8iAAIOAAgJOhJNSQCIAQAOAAgJOhJNSQCIAQAAAA==.Azureflamez:BAAALgAECgEJAQAAAA==.Azzul:BAAALgADCgcJBwAAAA==.',
Ba='Baiken:BAAALgAECgIJAgABLgAECgQJCAADAAAAAA==.Banjoman:BAABLgAECn8kAAILAAcJXSQACADJAgALAAcJXSQACADJAgAAAA==.Baza:BAAALgADCgYJBgAAAA==.Baýlei:BAABLgAECn8WAAIQAAYJ5A3AQwAEAQAQAAYJ5A3AQwAEAQAAAA==.',
Be='Beary:BAAALgAECgQJBwAAAA==.Beenaughty:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Belaanna:BAAALgADCgYJCQAAAA==.Beliria:BAAALgADCgUJBgAAAA==.Benimaru:BAAALgAECgMJAwAAAA==.Beriko:BAAALgAECgMJAwAAAA==.Bernat:BAAALgAECgEJAQAAAA==.Beàrdfáce:BAAALgADCgQJBAAAAA==.',
Bi='Bigjuicy:BAAALgAECggJCgAAAA==.Billie:BAAALgADCgcJBwAAAA==.Bimboficate:BAAALgADCgYJBwAAAA==.',
Bl='Blackadder:BAAALgAECgQJCgAAAA==.Blessthefall:BAAALgAECgYJCgAAAA==.Blondie:BAAALgADCgQJBAABLgAECgYJDQADAAAAAA==.Bloodie:BAAALgAECgMJAwAAAA==.Blue:BAABLgAECn88AAIRAAkJxRtDCwBqAgARAAkJxRtDCwBqAgAAAA==.Bluestreak:BAAALgAECgEJAwABLgAECgcJCQADAAAAAA==.',
Bo='Bode:BAAALgAECgYJEgAAAA==.Bogern:BAAALgADCgcJBwAAAA==.Bolau:BAAALgADCgYJBwAAAA==.Boltz:BAAALgADCgYJBgAAAA==.Boogy:BAAALgAECgYJBgAAAA==.Bopdiz:BAAALgAECgEJAQABLgAECgQJDgADAAAAAA==.Borledish:BAAALgAECgMJBAABLgAECgQJDgADAAAAAA==.Bottosai:BAAALgAECgEJAgAAAA==.',
Br='Branwynn:BAAALgAECgEJBQAAAA==.Breezyfight:BAAALgAECgQJBQAAAA==.Breezysha:BAAALgADCgcJCAAAAA==.Brenz:BAAALgAFFAMJBAAAAA==.Brewdaddy:BAAALgAECgUJCwABLgAECggJLQASAKwQAA==.Brewdude:BAAALgAECgEJAQAAAA==.Brigor:BAAALgADCgkJCwAAAA==.Brokenblade:BAAALgADCgYJBgAAAA==.Brotherblood:BAAALgADCggJCQAAAA==.',
Bu='Bulldoza:BAAALgAECgQJBAAAAA==.Bullwinkles:BAAALgAECgEJAQAAAA==.Butterknifeo:BAABLgAFFH8FAAITAAMJxxRuIwDaAAATAAMJxxRuIwDaAAAAAA==.',
By='Byryja:BAAALgAECgQJCgAAAA==.',
Ca='Cahrazie:BAAALgAFFAEJAQAAAA==.Caidinn:BAAALgAECgkJEQAAAA==.Caitrîn:BAAALgADCgkJCQAAAA==.Calissancia:BAABLgAECn8xAAIQAAgJ2hWAHADzAQAQAAgJ2hWAHADzAQAAAA==.Calkey:BAABLgAECn8WAAIBAAYJUQh6GAC/AAABAAYJUQh6GAC/AAAAAA==.Cathandris:BAAALgADCgEJAQAAAA==.',
Ce='Ceri:BAAALgAECgkJBwAAAA==.',
Ch='Channingtotm:BAACLgAFFH8XAAIUAAQJFiNkEACZAQAUAAQJFiNkEACZAQAuAAQKfzQAAhQACQm8IGoDAGQDABQACQm8IGoDAGQDAAAA.Chantix:BAAALgADCgUJBQAAAA==.Charlemoo:BAAALgADCgUJBQABLgAECgMJAwADAAAAAA==.Cheekymonkey:BAABLgAECn8cAAIEAAgJZAnkBQBEAQAEAAgJZAnkBQBEAQAAAA==.Chueyé:BAAALgAECgMJAwABLgAFFAMJCQAVAO8dAA==.Chunkyy:BAAALgADCgYJBgAAAA==.Churros:BAABLgAECn8jAAMLAAgJUBR1IACbAQALAAcJThV1IACbAQAJAAcJpxmWIQCSAQAAAA==.',
Ci='Cincog:BAAALgAECgQJBAABLgAECgYJCQADAAAAAA==.',
Cl='Closetcookie:BAAALgAECgQJBAAAAA==.',
Co='Coberren:BAAALgAECgEJAQAAAA==.Cordialkylie:BAAALgAECgIJAgAAAA==.Cowcrusader:BAAALgADCgcJBwAAAA==.',
Cr='Crazyugly:BAAALgAECgEJAQAAAA==.Crogrer:BAAALgADCgUJBQAAAA==.Crosslock:BAAALgAECgIJAwAAAA==.',
Cu='Cuppycakes:BAAALgADCgcJFAAAAA==.',
Cy='Cynnari:BAAALgAECgUJBQAAAA==.',
Da='Dalan:BAAALgAECgEJAQABLgAECgkJJAAEALAdAA==.Dalaris:BAABLgAECn8fAAIWAAgJoRa9EgDKAQAWAAgJoRa9EgDKAQAAAA==.Dano:BAAALgADCgYJDQAAAA==.Darci:BAAALgAECgYJCwAAAA==.Darkeon:BAAALgAECgQJBAAAAA==.Darlenedark:BAAALgAECgEJAQAAAA==.Darling:BAAALgAECgIJAgAAAA==.Darron:BAAALgAECgEJAwAAAA==.Darrosh:BAABLgAECn8bAAQXAAgJuxNWDwDjAAAXAAYJDhBWDwDjAAAVAAcJjQ1kNADRAAAYAAMJ9hB8FAC1AAAAAA==.Dartian:BAAALgADCgYJBgABLgAECgkJJgACACMRAA==.Dazdot:BAAALgADCgQJBAAAAA==.',
De='Deathdevil:BAAALgAECgUJBQAAAA==.Deathlurker:BAAALgADCgQJBAAAAA==.Deathmare:BAAALgADCgMJAwAAAA==.Deathmommy:BAAALgAECgEJAQAAAA==.Deathty:BAAALgAECgMJCgABLgAECgcJDwADAAAAAA==.Dementia:BAAALgADCgMJAwAAAA==.Design:BAABLgAECn8lAAIZAAkJ4ReEJQAuAgAZAAkJ4ReEJQAuAgAAAA==.Desmeridian:BAAALgAECgUJBQAAAA==.Devotee:BAAALgADCgIJAgAAAA==.',
Dh='Dhish:BAAALgADCgkJIAAAAA==.',
Di='Diltlish:BAAALgAECgMJBQAAAA==.Disconcern:BAAALgAECgEJAQAAAA==.Discontent:BAAALgAFFAIJBAAAAA==.Discordiä:BAABLgAECn8XAAIaAAgJHRcVFwDvAQAaAAgJHRcVFwDvAQAAAA==.Discspal:BAAALgAECgYJBwAAAA==.',
Dm='Dmginc:BAAALgADCgIJAgAAAA==.',
Do='Doeblin:BAAALgAECgMJBgAAAA==.Donkedixon:BAAALgADCgYJBgAAAA==.Doubtz:BAAALgAECgQJBQABLgAECgQJDgADAAAAAA==.',
Dp='Dpalx:BAAALgAECgQJBAAAAA==.Dpxs:BAABLgAFFH8HAAIUAAQJkhbYJwAKAQAUAAQJkhbYJwAKAQAAAA==.',
Dr='Dracones:BAAALgAECgYJDgAAAA==.Dragondz:BAAALgAECgUJBQAAAA==.Dragonflai:BAABLgAECn8kAAIFAAgJPRejYAChAQAFAAgJPRejYAChAQAAAA==.Dragonkin:BAAALgAECgQJCAAAAA==.Drakkari:BAAALgADCgcJBwAAAA==.Drakkei:BAABLgAECn8pAAMCAAgJhBU5OwDHAQACAAgJhBU5OwDHAQAGAAIJwgJnSwBQAAAAAA==.Drerane:BAAALgADCgYJBgAAAA==.Drexxsster:BAAALgADCgQJBAAAAA==.Drshortbus:BAAALgAECgIJAgAAAA==.Drumitus:BAAALgADCgYJCAAAAA==.Drunkngrundl:BAABLgAECn89AAIbAAkJHiPxAgARAwAbAAkJHiPxAgARAwAAAA==.Drylo:BAEBLgAECn8tAAMcAAkJJiCtBwDHAgAcAAkJix6tBwDHAgAdAAgJxR+LAwA3AgAAAA==.',
Du='Dunstir:BAABLgAECn8ZAAIKAAgJ6QWRmgAfAQAKAAgJ6QWRmgAfAQAAAA==.Dusktrekker:BAAALgAECgkJBwAAAA==.',
Dy='Dypshyt:BAABLgAECn8ZAAQcAAgJUxVEQwD1AAAdAAUJUBJRIgAYAQAcAAYJqxBEQwD1AAAeAAQJNgdALwBNAAAAAA==.',
Ed='Edelweíss:BAAALgAECgIJAwAAAA==.',
Ek='Ekoh:BAAALgAECgIJAgAAAA==.',
El='Elarol:BAAALgAECgEJAgAAAA==.Eldons:BAAALgADCgIJAgAAAA==.',
Em='Embers:BAABLgAECn8WAAIfAAYJGxOBSgDzAAAfAAYJGxOBSgDzAAAAAA==.Emeralde:BAAALgAECgYJBwAAAA==.Emilia:BAAALgADCgIJAwAAAA==.Emptyhands:BAAALgAECgUJBQAAAA==.Emptyheals:BAABLgAECn8xAAIaAAkJ3yB1AwBPAwAaAAkJ3yB1AwBPAwAAAA==.',
Er='Ereada:BAAALgADCgUJCgAAAA==.Erfinden:BAAALgADCgEJAQAAAA==.',
Es='Espers:BAABLgAECn8fAAITAAkJ6Q+RMgAgAQATAAkJ6Q+RMgAgAQAAAA==.',
Et='Ethellin:BAABLgAECn8jAAIKAAcJuwRfwADkAAAKAAcJuwRfwADkAAAAAA==.',
Fa='Fahrenheit:BAAALgAECgEJAgAAAA==.Farkuat:BAAALgADCgQJBAAAAA==.Fatcastle:BAAALgADCgYJCQAAAA==.',
Fe='Feedmepizzas:BAAALgAECgMJBwAAAA==.Feildmedic:BAAALgADCgUJBQAAAA==.Feleria:BAAALgAECgEJAQAAAA==.Fellslasher:BAAALgAECgIJAgAAAA==.Felmage:BAAALgADCgYJBgAAAA==.Felraiser:BAAALgADCgIJAgABLgADCgUJBgADAAAAAA==.Felwinter:BAABLgAECn81AAIZAAkJthqoGgBqAgAZAAkJthqoGgBqAgAAAA==.Femcelgoon:BAAALgADCgEJAQAAAA==.Fenna:BAAALgADCgYJDAAAAA==.Fetor:BAAALgAECgcJEAAAAA==.',
Fi='Finwé:BAAALgAECgMJAwAAAA==.Fistsalot:BAAALgAECgQJBQAAAA==.',
Fl='Flafferthorn:BAAALgADCgQJBAAAAA==.Fluxarata:BAABLgAECn8gAAIOAAkJKAxwSwCBAQAOAAkJKAxwSwCBAQAAAA==.',
Fo='Forthememes:BAAALgAECgEJAQAAAA==.',
Fr='Fred:BAABLgAECn8cAAIfAAYJ6giUTQDnAAAfAAYJ6giUTQDnAAAAAA==.Freddrick:BAAALgADCgQJBAAAAA==.Friendly:BAAALgAECgEJAQAAAA==.Frostbuddy:BAAALgAECgcJDQAAAA==.Frëya:BAAALgADCgYJDQAAAA==.Frío:BAAALgAECgEJAQAAAA==.Frøstitute:BAABLgAECn8WAAIFAAYJTwulsQAEAQAFAAYJTwulsQAEAQAAAA==.',
Fu='Fullmage:BAAALgADCgQJBAAAAA==.',
['Fè']='Fènrïr:BAAALgADCgQJBAAAAA==.',
Ga='Gabel:BAABLgAECn8kAAIgAAgJ6hrgCAAKAgAgAAgJ6hrgCAAKAgAAAA==.Gadnabit:BAAALgADCgkJCQAAAA==.Gailardia:BAABLgAECn8UAAICAAcJchN2UQCAAQACAAcJchN2UQCAAQAAAA==.Galand:BAABLgAECn8iAAMIAAYJ+h5GXgCKAQAIAAYJdB5GXgCKAQAPAAIJoiGEQgBVAAAAAA==.Galladin:BAAALgADCggJDgAAAA==.Gardyson:BAAALgAFFAEJAQAAAA==.Gazton:BAAALgAECgUJBQAAAA==.',
Go='Gooblet:BAAALgADCgQJBQAAAA==.Goodfellow:BAAALgAECgEJAQABLgAECgYJFQAgAMUcAA==.Goopy:BAAALgADCgYJAwAAAA==.',
Gr='Graendal:BAAALgADCgQJBAAAAA==.Granite:BAAALgAECgIJAgAAAA==.Granted:BAAALgADCgUJBQAAAA==.Greevil:BAAALgAECgEJAwAAAA==.Gremilien:BAABLgAECn8fAAIMAAkJvg8cCgCnAQAMAAkJvg8cCgCnAQAAAA==.Grimgorr:BAAALgADCgMJAwAAAA==.Grymdevours:BAAALgADCgYJBgAAAA==.',
Ha='Halcyonic:BAAALgAECgEJAQAAAA==.Halleyscomet:BAABLgAECn8WAAIKAAcJPBptRAAXAgAKAAcJPBptRAAXAgAAAA==.Happyhammer:BAAALgADCgcJCAAAAA==.Harrod:BAAALgAECgcJCQAAAA==.Hawkwave:BAAALgAECgcJEgABLgAECgkJEQADAAAAAA==.Hazardzone:BAAALgAECgMJCgAAAA==.',
He='Heavyweather:BAAALgADCgcJBwAAAA==.Hefty:BAAALgAECggJDAAAAA==.Heftyer:BAAALgAECgMJAwAAAA==.Helioween:BAAALgADCgMJAwAAAA==.Helixon:BAAALgADCgYJBgAAAA==.Hellbad:BAACLgAFFH8MAAIbAAQJ7hMhHQAbAQAbAAQJ7hMhHQAbAQAuAAQKfxUAAxsACAleGDkiAHkBABEABgmOG30jALoBABsACAkXEjkiAHkBAAAA.Hellbine:BAAALgADCgMJAgAAAA==.Hellsspawn:BAAALgAECgEJAQAAAA==.Hexaverse:BAAALgADCgYJBgABLgAECgQJBAADAAAAAA==.',
Ho='Hoardwither:BAAALgAECgEJAQAAAA==.Hogrog:BAAALgADCgMJAwAAAA==.Hokàge:BAACLgAFFH8JAAIVAAMJ7x18GQAXAQAVAAMJ7x18GQAXAQAuAAQKfzkABBUACQkpIhgGAKwCABUACQkpIhgGAKwCABgAAgkCGgwXAJAAABcAAQkZAsAiAAkAAAAA.Homealone:BAAALgAECgYJEQAAAA==.',
Hu='Huffles:BAAALgAECgQJBwAAAA==.Hugmachine:BAAALgAFFAEJAQAAAA==.Huntinfuzzy:BAAALgAECgkJDwAAAA==.Huntn:BAAALgADCggJCAAAAA==.',
Ia='Iamknot:BAAALgAECgQJBgAAAA==.',
Ic='Icemommy:BAAALgADCgQJCAAAAA==.',
Ig='Igothots:BAABLgAECn8eAAMhAAkJfx4CEAC4AgAhAAkJfx4CEAC4AgAgAAEJbQnpQgApAAAAAA==.',
Il='Illariana:BAABLgAECn8aAAQJAAgJNRI5JAB/AQAJAAgJNRI5JAB/AQALAAEJwQJMagAhAAAaAAEJvgE1bwAeAAAAAA==.Illirotica:BAAALgAECgcJCQAAAA==.',
In='Incredibro:BAAALgADCgEJAQAAAA==.Insanitty:BAAALgAECgcJDwAAAA==.Invincible:BAAALgAECgEJAQABLgAECgUJCgADAAAAAA==.',
Ir='Ironlobo:BAAALgAECgYJCwAAAA==.Ironsolari:BAAALgADCgYJBgAAAA==.Irritable:BAAALgAECgYJEQAAAA==.',
It='Itherious:BAAALgAECgIJAwAAAA==.',
Ja='Jacham:BAABLgAECn8VAAIfAAgJ3RMGJACvAQAfAAgJ3RMGJACvAQAAAA==.Jackyll:BAAALgAECgQJCAAAAA==.Jagerboy:BAAALgAECgYJBgAAAA==.Jango:BAAALgAECgIJAgABLgAFFAEJAQADAAAAAA==.Jatix:BAACLgAFFH8FAAIKAAIJch3gXAC4AAAKAAIJch3gXAC4AAAuAAQKfyoAAgoACQkcI4sJAAIDAAoACQkcI4sJAAIDAAAA.',
Je='Jeetkundo:BAAALgADCgEJAQABLgAECgUJCgADAAAAAA==.Jellymagus:BAAALgAECgIJAgAAAA==.Jellyms:BAAALgAECgQJCQAAAA==.Jellyspinoff:BAAALgAECgMJBwAAAA==.Jellytown:BAABLgAECn89AAIFAAkJaxR/OAAbAgAFAAkJaxR/OAAbAgAAAA==.Jelorinea:BAAALgAECgMJAwAAAA==.Jessiana:BAAALgAECgMJAwAAAA==.Jezelda:BAAALgAECgQJBgAAAA==.',
Jp='Jpeppers:BAAALgAECgMJBwAAAA==.',
Ju='Jumano:BAAALgAECgUJCgAAAA==.Jundra:BAAALgAECgEJAgAAAA==.',
Ka='Kaineh:BAABLgAECn8jAAIMAAgJbBhkCADTAQAMAAgJbBhkCADTAQAAAA==.Kainë:BAAALgADCgIJAgAAAA==.Kait:BAABLgAECn8+AAICAAkJ6R/FCgDdAgACAAkJ6R/FCgDdAgAAAA==.Kaladil:BAAALgAECgcJCgAAAA==.Kamis:BAAALgADCgQJBAAAAA==.Kanaga:BAAALgAECgQJBQAAAA==.Kannan:BAABLgAECn8YAAMOAAgJzxv/LwA8AgAOAAgJzxv/LwA8AgAWAAEJAQdWeQAqAAAAAA==.Kashmihhr:BAAALgADCgIJAgAAAA==.Kashmir:BAAALgAECgQJBAAAAA==.Kasmes:BAAALgADCggJGQAAAA==.Kasmius:BAAALgAECgMJAwAAAA==.Kasmus:BAAALgAECgQJBwAAAA==.Kawdor:BAABLgAECn8tAAQSAAgJrBCpNQBQAQASAAcJNw+pNQBQAQANAAYJ3A9SIADhAAAKAAMJ8wosEwFsAAAAAA==.',
Ke='Keetsz:BAAALgAECgYJDAAAAA==.Kelaino:BAAALgADCgQJBQAAAA==.Keledish:BAAALgADCgEJAQAAAA==.',
Kh='Khansmebduke:BAACLgAFFH8FAAMWAAQJNxa5DwDwAAAWAAMJkRm5DwDwAAAOAAEJKgyleQBJAAAuAAQKfxYAAxYACAmlHAcRAOQBAA4ACAk1F1w+APsBABYABwlXHQcRAOQBAAEuAAUUBQkFACAAjh4A.',
Ki='Kiaf:BAAALgADCgcJDQAAAA==.Kiba:BAAALgADCgEJAQAAAA==.Killanick:BAAALgAECgEJAQAAAA==.Killdar:BAAALgADCgcJBwAAAA==.Kimia:BAAALgADCgYJCQAAAA==.Kirtthedirt:BAAALgADCgQJBQAAAA==.Kirtthehurt:BAABLgAECn8oAAIFAAgJKxk6OQAYAgAFAAgJKxk6OQAYAgAAAA==.',
Ko='Koldfront:BAAALgAECgMJAwAAAA==.Kollinator:BAAALgAECgQJBAAAAA==.Korso:BAAALgADCgUJCwABLgADCgkJCQADAAAAAA==.Kotal:BAAALgAECgEJAQAAAA==.',
Ky='Kylair:BAABLgAECn80AAIJAAkJ/B5jBwC9AgAJAAkJ/B5jBwC9AgAAAA==.Kynreessa:BAAALgADCgYJCAAAAA==.Kyønshi:BAAALgADCgUJBgAAAA==.',
['Kì']='Kìrito:BAAALgAECgMJAwAAAA==.',
La='Labeya:BAAALgADCgMJAwAAAA==.Lafty:BAAALgAECgcJDwAAAA==.Laftydh:BAAALgAECgUJEAABLgAECgcJDwADAAAAAA==.Lailah:BAAALgADCgIJAgABLgAECgkJNAAKAC4WAA==.Laine:BAAALgADCgMJAwAAAA==.Landrra:BAAALgAECgQJBAAAAA==.Larac:BAAALgAECgcJDgAAAA==.Lathsong:BAAALgADCgYJDwAAAA==.Lavi:BAAALgADCgQJAwAAAA==.',
Le='Leadge:BAAALgADCgYJBwAAAA==.Lenik:BAABLgAECn8aAAIVAAYJ+glwLgD5AAAVAAYJ+glwLgD5AAAAAA==.Leskya:BAAALgADCgQJAwAAAA==.',
Li='Libras:BAAALgADCgMJAwAAAA==.Licorice:BAAALgAECgUJDQABLgAECggJIwALAFAUAA==.Lieree:BAAALgAECgcJEwAAAA==.Lifeguàrd:BAAALgAECgkJBwAAAA==.Lillana:BAAALgADCgcJDQAAAA==.Lilyfaye:BAAALgADCgcJBwAAAA==.Limosfire:BAAALgAECgUJEAAAAA==.Linsatha:BAAALgAECgcJCgAAAA==.',
Lo='Lockty:BAAALgAECgIJBQABLgAECgcJDwADAAAAAA==.Logi:BAAALgADCgYJCwAAAA==.Lorezever:BAAALgADCgcJDQAAAA==.Lotion:BAAALgADCgIJAgAAAA==.',
Lu='Luar:BAAALgAECgUJCAAAAA==.Lulubean:BAAALgADCgMJBAAAAA==.Lunaris:BAAALgADCgQJBAAAAA==.Lunà:BAAALgAECgcJEwAAAA==.',
Ly='Lythalle:BAAALgAECgEJAQAAAA==.Lythwynn:BAABLgAECn8rAAIKAAkJhQ/uVwClAQAKAAkJhQ/uVwClAQAAAA==.',
Ma='Mace:BAAALgAECgEJAQAAAA==.Madison:BAAALgAECgEJAQAAAA==.Magdolyn:BAAALgADCgMJAwAAAA==.Mageyboi:BAAALgAECgQJBgABLgAFFAMJCQAVAO8dAA==.Magickul:BAAALgAECgYJDAAAAA==.Magleon:BAAALgADCgIJAgAAAA==.Magonk:BAAALgADCgEJAQAAAA==.Mahano:BAAALgAECgYJDAABLgAFFAEJAQADAAAAAA==.Makis:BAAALgAECgMJBQAAAA==.Malachi:BAAALgADCgkJCQAAAA==.Manavoid:BAABLgAECn8cAAIOAAYJkAoEkADWAAAOAAYJkAoEkADWAAAAAA==.Mastor:BAAALgADCgQJBwAAAA==.Maynard:BAABLgAECn8eAAIQAAgJihKZKQCRAQAQAAgJihKZKQCRAQAAAA==.',
Mc='Mcdouble:BAAALgADCgMJAwAAAA==.',
Me='Meri:BAABLgAECn8bAAIhAAcJoB4rJgAfAgAhAAcJoB4rJgAfAgAAAA==.',
Mi='Miande:BAAALgAECgcJDAAAAA==.Microburst:BAAALgADCgUJBQAAAA==.Minecraft:BAAALgAECgIJAgAAAA==.Minilock:BAABLgAECn8eAAMBAAgJMA38GAC7AAAZAAgJ9ApGagBRAQABAAUJTg78GAC7AAAAAA==.Misogynixy:BAAALgADCgQJBAAAAA==.Missleading:BAAALgAECgEJAQAAAA==.Missused:BAAALgAECgYJDAAAAA==.Mithos:BAAALgAECgUJBwAAAA==.Mithraxa:BAAALgAECgQJBAAAAA==.',
Mo='Moash:BAAALgADCgkJCQAAAA==.Mongermook:BAABLgAECn8cAAMiAAgJCQq3KADNAAAiAAgJCQq3KADNAAATAAEJxgFpkQAVAAAAAA==.Monnkysham:BAAALgAECgQJBgABLgAECgYJCQADAAAAAA==.Moogledragon:BAAALgADCgMJAwAAAA==.Mooglefur:BAAALgAECgMJAwAAAA==.Moonbloom:BAABLgAECn8cAAIhAAgJQhytGgBNAgAhAAgJQhytGgBNAgAAAA==.Morlosh:BAAALgAECgMJAwAAAA==.Moryna:BAABLgAECn8kAAIjAAgJsAbXJwADAQAjAAgJsAbXJwADAQAAAA==.',
Mt='Mthrandir:BAAALgADCgUJBQAAAA==.',
Mu='Muford:BAAALgAECgQJBQABLgAFFAYJEQAbAI8fAA==.Mull:BAAALgAECgYJDQAAAA==.Muloc:BAAALgADCgEJAQAAAA==.',
My='Myaka:BAAALgAECgYJBgAAAA==.',
Na='Naatixa:BAAALgAECgMJAwAAAA==.Nacronor:BAAALgAECgIJAwAAAA==.Naiika:BAAALgAECgYJBwAAAA==.Nascha:BAAALgADCgEJAQAAAA==.Nasoj:BAAALgAECgUJCAABLgAECgYJEwADAAAAAA==.',
Ne='Necrotic:BAAALgAECgQJBAAAAA==.Nedalla:BAAALgAECgIJAgAAAA==.Neeve:BAAALgADCgYJBgAAAA==.Nekrotik:BAAALgADCgcJBgAAAA==.Neobahamut:BAAALgADCgEJAQABLgAECgMJAwADAAAAAA==.Netharel:BAAALgADCgIJAgAAAA==.Newports:BAAALgAECgEJAQAAAA==.',
Ni='Nichôlasmage:BAAALgAECgYJCwAAAA==.Nickatnite:BAAALgAECgEJAwAAAA==.Nickelodeon:BAAALgAECgQJBwAAAA==.Nicksaban:BAABLgAECn8mAAIKAAkJOButIQBgAgAKAAkJOButIQBgAgAAAA==.Nightgear:BAACLgAFFH8rAAMCAAYJoRcgBABeAQACAAUJyxogBABeAQAMAAIJ/ApfJQBRAAAuAAQKf1kAAwIACQm1Iv4JAOUCAAIACQm1Iv4JAOUCAAwABAnfEtYdAJwAAAAA.Nilux:BAAALgAECgYJDgAAAA==.Ninetails:BAAALgAECgUJCgAAAA==.Niteshadeth:BAAALgADCggJEwAAAA==.Nixeava:BAAALgAECgUJBwAAAA==.',
No='Nogooddruid:BAAALgAECgIJAwAAAA==.Nopetsneeded:BAABLgAECn8tAAIMAAkJrBEbCQC9AQAMAAkJrBEbCQC9AQAAAA==.Nostariel:BAAALgADCgEJAQAAAA==.Notadoctor:BAAALgAECgYJBwAAAA==.Noteworthy:BAAALgAECgYJEAABLgAFFAYJDwAIAN0dAA==.',
Ny='Nysong:BAABLgAECn8oAAMBAAgJhwcNEgD5AAABAAgJhwcNEgD5AAAZAAMJYwKu8QBXAAAAAA==.',
Od='Oddangel:BAAALgAECgYJEwAAAA==.Ode:BAAALgAECgMJAwAAAA==.Odex:BAABLgAECn8fAAIdAAgJ4QtNCQBwAQAdAAgJ4QtNCQBwAQAAAA==.',
Oh='Ohblergen:BAAALgAECgIJAgAAAA==.',
Ok='Okragren:BAABLgAECn81AAIkAAkJhwxnKQB4AQAkAAkJhwxnKQB4AQAAAA==.',
Ol='Olehi:BAAALgADCgcJBwAAAA==.',
On='Onos:BAABLgAECn8bAAICAAcJIyQ4IABEAgACAAcJIyQ4IABEAgAAAA==.Ontoquas:BAAALgADCgkJCgAAAA==.',
Pa='Paleclaw:BAAALgADCgQJBAAAAA==.Pally:BAAALgAECgUJBQAAAA==.Papasmurfz:BAAALgAECgEJAwAAAA==.Paramedic:BAAALgAECgQJBwAAAA==.Pathogen:BAABLgAECn8hAAIIAAkJDR8fLwAfAgAIAAkJDR8fLwAfAgAAAA==.',
Pe='Penryn:BAAALgAECgEJAQAAAA==.Pepster:BAAALgAECgkJCQAAAA==.Persephoknee:BAAALgADCgEJAQAAAA==.',
Pf='Pfchen:BAAALgADCgQJBAAAAA==.',
Pl='Plinkerbell:BAAALgADCgcJBgAAAA==.Plumprnickel:BAAALgAECgEJAQAAAA==.Plxkingg:BAAALgADCgUJBQAAAA==.',
Po='Porimma:BAAALgAECgYJDQAAAA==.Pormas:BAAALgAECgYJDwAAAA==.Poseydon:BAAALgADCgQJBAABLgAECgEJAQADAAAAAA==.',
Pr='Prayerz:BAAALgADCgMJAwAAAA==.Proctology:BAAALgAECgQJBAAAAA==.Promethèus:BAAALgAECgQJBAAAAA==.Prosby:BAAALgADCgIJAgAAAA==.Prowlnfool:BAAALgADCgUJBQAAAA==.Pryto:BAAALgADCgkJDgABLgAFFAIJAgADAAAAAA==.',
Qu='Queedle:BAABLgAECn8WAAIXAAgJDwgVDAAmAQAXAAgJDwgVDAAmAQAAAA==.',
Ra='Raennis:BAAALgAECgIJAgAAAA==.Ragalstan:BAAALgADCggJCQAAAA==.Rahanumn:BAABLgAECn8WAAIKAAcJqgrEmQAgAQAKAAcJqgrEmQAgAQAAAA==.Rainsvoker:BAACLgAFFH8jAAIeAAYJXQ3YDACUAQAeAAYJXQ3YDACUAQAuAAQKf1IAAx4ACQkOHIUFAJkCAB4ACQkOHIUFAJkCABwABgk7CHhPAMUAAAAA.Ramike:BAAALgAECggJCQAAAA==.Raqtar:BAAALgAECgIJAgABLgAECgkJEQADAAAAAA==.Ratrazarke:BAAALgADCgIJAgAAAA==.Razihel:BAAALgADCgYJCQAAAA==.',
Re='Reaver:BAAALgAECgQJBAAAAA==.Reddan:BAABLgAECn8qAAIKAAgJlgwregBZAQAKAAgJlgwregBZAQAAAA==.Renata:BAAALgAFFAIJAgAAAA==.Replicant:BAAALgAECgEJAQAAAA==.Retman:BAAALgAECgMJAQAAAA==.Reverìe:BAAALgAECgcJBwAAAA==.Reylinn:BAAALgAECgQJBAAAAA==.Reï:BAABLgAECn8VAAIhAAgJKhaDJQD/AQAhAAgJKhaDJQD/AQAAAA==.',
Ri='Ridlei:BAAALgAECgMJBAAAAA==.Ritzon:BAABLgAECn89AAMfAAkJJSThAwAQAwAfAAkJJSThAwAQAwAjAAEJmBfFWAA+AAAAAA==.',
Ro='Roxydan:BAABLgAECn8dAAMBAAgJiQ03KQAdAQAZAAgJiQ1KZwCWAQABAAYJ8Ag3KQAdAQAAAA==.',
Ry='Ryko:BAABLgAECn8aAAIlAAcJwRLFDwC8AQAlAAcJwRLFDwC8AQAAAA==.',
Sa='Sanandume:BAAALgADCgEJAQAAAA==.Sanctess:BAAALgAECggJDQAAAA==.Sankai:BAAALgAECgEJAQABLgAECgYJDgADAAAAAA==.Sarumanpally:BAAALgAECgYJBwAAAA==.Sayomi:BAAALgADCgcJEwAAAA==.',
Se='Secretjuice:BAAALgAECgYJCQAAAA==.Senseijundra:BAAALgAECgQJCAAAAA==.',
Sh='Shabadu:BAAALgADCgQJBAAAAA==.Shadyandi:BAAALgADCgcJCAAAAA==.Shamanhack:BAAALgAFFAEJAQAAAA==.Shan:BAAALgADCgYJBgAAAA==.Sheda:BAAALgAECgQJBAAAAA==.Shedia:BAAALgADCgYJCQAAAA==.Shmoove:BAEALgAECgQJBAAAAA==.Shmooves:BAEALgAECgMJAwABLgAECgQJBAADAAAAAA==.Shoukei:BAAALgADCgIJAwAAAA==.',
Si='Sianna:BAAALgADCgYJBgAAAA==.Siinful:BAAALgAECgEJAQAAAA==.Simbruh:BAAALgADCgMJAwAAAA==.Sinarria:BAAALgAECgEJAQAAAA==.Sithra:BAAALgADCgEJAQAAAA==.',
Sk='Skeemer:BAAALgAECgQJBAAAAA==.Skeetro:BAAALgAECgEJAQAAAA==.Skips:BAAALgAECgQJCQAAAA==.Skullace:BAABLgAECn8hAAIBAAgJyA2VDABHAQABAAgJyA2VDABHAQAAAA==.Skybreaker:BAAALgAECgUJCAAAAA==.',
Sm='Smashurfacen:BAAALgADCgcJFAAAAA==.',
Sn='Snitbit:BAAALgADCgkJGgAAAA==.Sno:BAAALgADCgEJAQABLgAECgUJBwADAAAAAA==.Snoopingas:BAAALgADCgEJAQAAAA==.Snpcrklpopu:BAAALgADCgYJCAAAAA==.',
So='Solarana:BAAALgAECgkJCQAAAA==.Sotzi:BAAALgADCggJEQAAAA==.Souldune:BAAALgAECgYJBgAAAA==.',
Sp='Sparkplugg:BAAALgAECgEJAQAAAA==.',
Sr='Srfreaky:BAAALgAECgIJAwAAAA==.',
St='Stormcunning:BAABLgAECn8WAAIkAAYJCAxiTAAWAQAkAAYJCAxiTAAWAQAAAA==.Stormfire:BAAALgADCgcJBwAAAA==.Stormßringer:BAABLgAECn8UAAIkAAgJERDXMwCJAQAkAAgJERDXMwCJAQAAAA==.Stownr:BAAALgAECgYJBgAAAA==.Strip:BAAALgADCgUJCAAAAA==.Strongclaw:BAAALgADCgUJBQAAAA==.Stumpyborg:BAABLgAECn8UAAQBAAcJaAYMKgBXAAAZAAYJNgSiwgCpAAABAAIJMwsMKgBXAAAmAAEJhAdmMwArAAABLgAECggJDAADAAAAAA==.Stónéhëárt:BAAALgADCgYJBwABLgAECgkJEQADAAAAAA==.',
Su='Subverse:BAAALgAECgQJBAAAAA==.Sundance:BAAALgAECgcJDgAAAA==.Sune:BAABLgAECn8cAAMJAAYJIQuRPAD2AAAJAAYJIQuRPAD2AAAaAAEJNwlHYwAyAAAAAA==.Supplicant:BAAALgADCgQJBwAAAA==.',
Sv='Svellulfr:BAAALgAECgEJAQAAAA==.Svuca:BAAALgADCgcJBwAAAA==.',
Sy='Sydneyweenie:BAAALgADCgcJBwAAAA==.Syldi:BAAALgAECgEJAQABLgAFFAEJAQADAAAAAA==.Sythis:BAAALgAECgEJAQAAAA==.',
['Sä']='Sästa:BAAALgADCgkJCQAAAA==.',
['Sö']='Sörren:BAAALgAECgQJCgAAAA==.',
Ta='Tacosdeasada:BAAALgAECgEJAQAAAA==.Taitertot:BAAALgADCgQJBQAAAA==.Tanelórn:BAAALgAECgEJAQAAAA==.Tanlon:BAAALgAECgEJAQABLgAECgEJAwADAAAAAA==.Taykorra:BAAALgADCggJDQAAAA==.',
Te='Telandril:BAABLgAECn8vAAIhAAkJvxG1LQDNAQAhAAkJvxG1LQDNAQAAAA==.Telphin:BAAALgAECgYJCQAAAA==.Tempestira:BAAALgADCgIJCAAAAA==.Tensuken:BAABLgAECn8ZAAIKAAYJpBjdkAAwAQAKAAYJpBjdkAAwAQAAAA==.Teylonna:BAAALgAECgEJAQAAAA==.',
Th='Thadgun:BAAALgADCgkJFQAAAA==.Thadium:BAAALgADCgYJCQAAAA==.Thalgan:BAAALgAECgEJAQAAAA==.Thecword:BAAALgADCgYJBgAAAA==.Themedic:BAAALgAECgYJDQAAAA==.Theremar:BAAALgAECgMJAwAAAA==.Thergothon:BAAALgAECgEJAQABLgAECgMJAwADAAAAAA==.Thisisdrexx:BAAALgAECgIJAwAAAA==.Thorwrath:BAAALgADCgEJAgAAAA==.Thrazoro:BAAALgAECgMJAwAAAA==.Thrazzoro:BAAALgAECgYJEwAAAA==.',
Ti='Tiarl:BAABLgAECn8mAAILAAgJixiFFAAMAgALAAgJixiFFAAMAgAAAA==.Tiia:BAAALgADCgIJAgAAAA==.Timex:BAABLgAECn8XAAMdAAYJRCD5DgDrAQAdAAYJRCD5DgDrAQAcAAEJUhf1dgBAAAAAAA==.Tinysitril:BAAALgAECgQJBAABLgAECggJHwAWAKEWAA==.Titañick:BAAALgAECgEJAwAAAA==.',
To='Tom:BAAALgAECgYJEAAAAA==.Toosxyfohair:BAAALgAECgUJCAAAAA==.',
Tr='Trainwrekk:BAAALgADCgYJBgAAAA==.Tranqar:BAAALgAECgQJBgAAAA==.Tresg:BAAALgAECgYJCQAAAA==.Trolltoll:BAAALgADCgEJAgAAAA==.Trüth:BAAALgADCggJEAAAAA==.',
Ty='Tyrannus:BAAALgADCgYJBgAAAA==.Tyregar:BAAALgADCgYJCgAAAA==.Tyrànda:BAAALgADCgMJAwAAAA==.Tyzy:BAAALgAECgEJAgAAAA==.',
['Tö']='Tötém:BAAALgAECgEJAQAAAA==.',
Ul='Ulanhi:BAABLgAECn8VAAIgAAUJzh31EACdAQAgAAUJzh31EACdAQAAAA==.',
Un='Undeadjelly:BAAALgAECgIJAgAAAA==.Unholy:BAAALgAECgYJDwAAAA==.',
Ur='Urkzul:BAAALgADCgMJAwAAAA==.Ursoth:BAAALgADCgUJCgAAAA==.',
Ut='Uthèrsmight:BAAALgAECgYJBgAAAA==.Uti:BAAALgADCgUJBQAAAA==.',
Uu='Uubs:BAAALgADCgEJAQABLgAECgIJAgADAAAAAA==.',
Va='Valakk:BAAALgAECgIJBQAAAA==.Vallak:BAAALgADCgIJBAAAAA==.Valsitril:BAAALgAECgYJCgABLgAECggJHwAWAKEWAA==.Valthaczar:BAAALgAECgMJBgAAAA==.Vanara:BAAALgAECgEJAgAAAA==.Varadun:BAAALgAFFAIJAgAAAA==.Varrosh:BAAALgADCgYJBgAAAA==.Vathan:BAAALgAECgQJBQAAAA==.',
Ve='Velmora:BAAALgAECgkJCQAAAA==.Velsetin:BAABLgAECn8dAAIFAAcJTBsyTABSAgAFAAcJTBsyTABSAgABLgAFFAMJBQATAMcUAA==.Versed:BAAALgADCgUJBQABLgAECgQJBAADAAAAAA==.Veryspooky:BAABLgAECn8XAAIZAAgJMhcbQADEAQAZAAgJMhcbQADEAQAAAA==.Vexian:BAAALgAECgkJCQAAAA==.',
Vi='Vicas:BAAALgAECgUJCQAAAA==.',
Vl='Vladdok:BAAALgAECgEJAQAAAA==.',
Vo='Voidofdeath:BAAALgADCgQJBAAAAA==.Voidshiekah:BAAALgADCgEJAQAAAA==.Vorteia:BAAALgADCgYJBgAAAA==.',
['Vé']='Véngéánçé:BAAALgAECgMJBAAAAA==.',
Wa='Wald:BAAALgAECgYJEAAAAA==.Warmongerr:BAAALgADCgIJAgAAAA==.Waruh:BAAALgADCgcJCQAAAA==.',
We='Webgar:BAAALgAECgEJAQAAAA==.',
Wh='Whisperlia:BAAALgADCgEJAQAAAA==.Whitetoothe:BAABLgAECn8YAAICAAYJRxKReAAfAQACAAYJRxKReAAfAQAAAA==.',
Wi='Wistmeaver:BAAALgAECgUJCgAAAA==.Witherbear:BAAALgADCgcJBwAAAA==.Witherhoard:BAAALgADCgEJAQAAAA==.',
['Wå']='Wånheda:BAAALgAECggJEwAAAA==.',
Xa='Xaniana:BAAALgAECgYJBgAAAA==.Xaosin:BAAALgADCgUJBQAAAA==.',
Xe='Xenzak:BAAALgAECgEJAQAAAA==.Xephir:BAAALgADCgMJAwAAAA==.Xerxës:BAAALgAECgEJAQAAAA==.',
Xl='Xl:BAAALgAECgQJBwAAAA==.',
Xo='Xotiko:BAAALgAECgYJDAAAAA==.',
Xu='Xubris:BAAALgADCgYJCQAAAA==.',
['Xâ']='Xâxâs:BAAALgAECgMJAwABLgAECgYJEQADAAAAAA==.',
Ya='Yaerin:BAACLgAFFH8NAAIaAAQJXh+aEwCGAQAaAAQJXh+aEwCGAQAuAAQKfyMAAhoACQmzIR0DAF4DABoACQmzIR0DAF4DAAAA.',
Yu='Yunarä:BAAALgAECgYJBwAAAA==.Yuukon:BAABLgAECn8VAAQPAAYJ4RGvKwDLAAAPAAYJ4RGvKwDLAAAIAAQJ5gOSBAFoAAAHAAEJDwgrGAAvAAAAAA==.',
Za='Zakuul:BAAALgADCgQJBAAAAA==.Zangetsu:BAAALgAECgcJBwAAAA==.Zaxie:BAABLgAECn8eAAIOAAcJFBo+PgCuAQAOAAcJFBo+PgCuAQAAAA==.',
Ze='Zenwu:BAAALgADCgkJGwAAAA==.Zephrylia:BAAALgAECgEJAQAAAA==.Zerama:BAAALgAECgUJBQAAAA==.',
Zh='Zheratul:BAAALgAECgEJAQAAAA==.Zhirl:BAAALgAECgkJCQAAAA==.Zhivet:BAAALgAECgUJBQAAAA==.',
Zi='Zilphia:BAAALgAECggJEgAAAA==.',
Zu='Zuriel:BAAALgAECgEJAQAAAA==.',
Zy='Zyku:BAAALgADCgIJAgAAAA==.Zylphie:BAAALgADCgcJBwAAAA==.',
['Àm']='Àmagezing:BAAALgAECgQJCAABLgAFFAQJCwAKABIgAA==.',
['Åj']='Åj:BAAALgADCgcJBwAAAA==.',
['Åp']='Åpexx:BAAALgAECgQJBAAAAA==.',
['Çw']='Çwÿbàbý:BAAALgAECgIJAgAAAA==.',
['Ór']='Órión:BAABLgAECn8VAAICAAYJ1BI9hAAGAQACAAYJ1BI9hAAGAQAAAA==.',
['Ös']='Östara:BAAALgAECgYJEQAAAA==.',
['ßj']='ßjörn:BAAALgADCgQJBAAAAA==.',
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
