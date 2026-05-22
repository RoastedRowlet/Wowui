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

local lookup = {'DeathKnight-Unholy','Shaman-Restoration','Paladin-Retribution','Druid-Restoration','Druid-Balance','Mage-Frost','DemonHunter-Devourer','Warrior-Fury','Shaman-Enhancement','DemonHunter-Havoc','Druid-Guardian','Rogue-Outlaw','DemonHunter-Vengeance','Rogue-Subtlety','Warrior-Arms','Warrior-Protection','DeathKnight-Frost','DeathKnight-Blood','Rogue-Assassination','Hunter-Survival','Hunter-Marksmanship','Priest-Discipline','Priest-Holy','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Protection','Monk-Mistweaver','Monk-Windwalker','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Hunter-BeastMastery','Druid-Feral','Mage-Fire','Monk-Brewmaster','Paladin-Holy','Mage-Arcane','Shaman-Elemental',}
local provider = {region='US',realm='Alleria',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aantoc:BAAALgADCgUJBQAAAA==.',
Ab='Abrut:BAAALgADCgMJAwAAAA==.',
Ad='Adramalech:BAAALgAECgIJAwABLgAFFAYJFQABADkfAA==.',
Ae='Aeakos:BAAALgADCgQJBQABLgAECgkJIQACAJEWAA==.Aelan:BAAALgADCgQJBAAAAA==.Aeryana:BAAALgADCgUJBwAAAA==.',
Ag='Agapitus:BAAALgADCgIJAgAAAA==.',
Ai='Ailuridae:BAAALgADCgcJEwAAAA==.Aimbot:BAAALgADCgYJCgAAAA==.Aisele:BAAALgAECgYJEwAAAA==.',
Al='Alathir:BAAALgAECgcJDQAAAA==.Alenton:BAAALgADCgUJBgAAAA==.Alessia:BAAALgADCgMJBAAAAA==.Alluri:BAABLgAECn8iAAIDAAkJxxkNPgDEAQADAAkJxxkNPgDEAQAAAA==.Alone:BAAALgAECgYJDgAAAA==.Althemia:BAAALgAECgQJBQAAAA==.Alunamora:BAABLgAECn8qAAIEAAgJsRyjEACJAgAEAAgJsRyjEACJAgAAAA==.Alwind:BAABLgAECn8XAAIFAAcJ+xA0KQArAQAFAAcJ+xA0KQArAQAAAA==.',
Am='Ambient:BAABLgAECn8gAAIGAAYJMBEmiQAqAQAGAAYJMBEmiQAqAQAAAA==.Amboosted:BAABLgAECn8yAAIDAAgJYRwpMQDzAQADAAgJYRwpMQDzAQAAAA==.Ameretat:BAECLgAFFH8IAAIHAAIJIBv5TgCiAAAHAAIJIBv5TgCiAAAuAAQKfxQAAgcABwk9HaskAPQBAAcABwk9HaskAPQBAAEuAAUUBAkSAAgAqB4A.',
An='Analani:BAAALgAECgQJBgAAAA==.Anali:BAAALgAECgcJDgAAAA==.Ancient:BAAALgAECgEJAQABLgAFFAQJCQAGAOgZAA==.Ancksunamun:BAAALgAECgIJAgAAAA==.Angerr:BAAALgAECgYJEgAAAA==.Angryheals:BAAALgAECgcJDgAAAA==.Anhri:BAAALgAECgEJAQAAAA==.Animalator:BAAALgAECgEJAQAAAA==.',
Ao='Aoi:BAAALgAECgEJAQAAAA==.',
Aq='Aquamann:BAAALgADCgMJBAAAAA==.',
Ar='Aranel:BAAALgAECgYJDQAAAA==.Aratiri:BAAALgADCgUJBQAAAA==.Arcamancer:BAAALgADCggJFwAAAA==.Arcannia:BAAALgADCgEJAQAAAA==.Arek:BAAALgAECgYJBwABLgAFFAYJFgAJAA0hAA==.Arinthal:BAAALgAECgYJEgAAAA==.Arril:BAAALgAECgYJEQAAAA==.Artemissy:BAAALgADCgUJDQAAAA==.Artorias:BAAALgAECgEJAgAAAA==.',
As='Ashed:BAAALgAECgcJDAAAAA==.Ashenskye:BAAALgADCgUJBQAAAA==.Ashlieghee:BAAALgAECgUJBQAAAA==.Ashou:BAAALgADCgMJAwAAAA==.Ashtari:BAAALgADCgEJAQAAAA==.Astien:BAAALgAECgYJDQAAAA==.Astra:BAAALgADCgMJAwAAAA==.',
Au='Aureille:BAAALgADCgEJAgAAAA==.Aurien:BAAALgADCgMJAwAAAA==.Autoaim:BAAALgAECgYJDwAAAA==.',
Av='Avelen:BAAALgAECgEJAwAAAA==.Avha:BAAALgAECgUJCwAAAA==.Avië:BAABLgAECn8XAAIGAAYJOBaWnACcAQAGAAYJOBaWnACcAQAAAA==.',
Ax='Axel:BAACLgAFFH8GAAIHAAMJpg39QQDXAAAHAAMJpg39QQDXAAAuAAQKfxsAAgcABwnzE2BaAJIBAAcABwnzE2BaAJIBAAAA.',
Ay='Aylden:BAABLgAECn8tAAMKAAgJ4RtODAAAAgAKAAgJ4RtODAAAAgAHAAUJmAmFlgCdAAAAAA==.',
Az='Azenezith:BAAALgAECgQJBAAAAA==.Azio:BAAALgAECgYJDAAAAA==.Azriah:BAAALgADCggJDwAAAA==.',
Ba='Bailas:BAAALgAECgEJAQAAAA==.Bananabear:BAABLgAECn8VAAILAAgJiiWGAQA+AwALAAgJiiWGAQA+AwABLgAFFAQJCgAMAJIeAA==.Barbiesresto:BAAALgADCgUJBQAAAA==.Bargs:BAAALgADCgMJAwAAAA==.Barra:BAAALgAECgQJBwAAAA==.Bashshield:BAEALgAFFAEJAQAAAA==.',
Bb='Bb:BAAALgAECgcJEQAAAA==.',
Be='Bearjax:BAAALgAECgIJAgABLgAFFAMJCwANADIjAA==.Beastm:BAAALgADCgQJBAAAAA==.Beathed:BAAALgAECgQJBQAAAA==.Beaver:BAAALgADCgIJAgAAAA==.Belanova:BAAALgAECgYJBwAAAA==.Belencina:BAAALgAECgYJBgAAAA==.Beleynn:BAABLgAECn8XAAIOAAgJKgbDHgBAAQAOAAgJKgbDHgBAAQAAAA==.Belwyn:BAAALgADCgMJAwAAAA==.Benjofamin:BAAALgAECgcJDQAAAA==.',
Bi='Bigheelz:BAAALgAECgUJBgAAAA==.Bigpuffer:BAAALgADCgMJBAAAAA==.Bitesize:BAECLgAFFH8SAAMIAAQJqB7KCgBhAQAIAAQJvxnKCgBhAQAPAAEJ6RqvCgBYAAAuAAQKfyYABA8ACQk+JCEMAN8BAAgABgluJEwjADsCAA8ABQnDJCEMAN8BABAAAgklEfA6AHQAAAAA.',
Bl='Blashster:BAAALgAFFAIJAwAAAA==.Blueprime:BAAALgADCgYJBgAAAA==.',
Bo='Boaw:BAAALgAECgMJBgAAAA==.Bonemilker:BAACLgAFFH8VAAQBAAYJOR+sEwCmAQABAAUJZRysEwCmAQARAAQJxR5GBgAZAQASAAEJAACELQAAAAAuAAQKfzoAAxEACAlhJm8AAGwDABEACAk/Jm8AAGwDAAEACAn/JS8IAF4DAAAA.Boosieboose:BAAALgAECgYJCAAAAA==.Boostymans:BAAALgADCgYJBgAAAA==.',
Br='Brackz:BAACLgAFFH8GAAIEAAMJLgsIMQCxAAAEAAMJLgsIMQCxAAAuAAQKfx0AAgQACQmgFugTAGYCAAQACQmgFugTAGYCAAAA.Brandt:BAAALgADCgEJAgAAAA==.Brannwynn:BAAALgADCgEJAQAAAA==.Breelyssa:BAAALgAECgcJBwAAAA==.Brewtangclan:BAAALgAECgYJEwAAAA==.Brighter:BAAALgAECgEJAQAAAA==.Broncopally:BAAALgADCgYJGwAAAA==.Brother:BAAALgADCgEJAQABLgAECggJKgAGAHIaAA==.Brutalbandit:BAAALgADCgUJBQAAAA==.Bryaan:BAABLgAFFH8FAAIDAAUJwAQmQwDkAAADAAUJwAQmQwDkAAAAAA==.',
Bu='Bullitproof:BAAALgADCgcJDgABLgAECggJMQADANkJAA==.Bulroc:BAAALgADCgEJAQAAAA==.Bunnkost:BAAALgADCgkJGQAAAA==.Bunnyparade:BAAALgAECgMJBQAAAA==.',
Ca='Caiden:BAAALgAECgMJAwAAAA==.Calari:BAAALgAECgQJBwAAAA==.Caledwar:BAABLgAECn8bAAIDAAYJ+RC4gQAgAQADAAYJ+RC4gQAgAQAAAA==.Calthirstrap:BAABLgAFFH8NAAIBAAQJ6BaoMABRAQABAAQJ6BaoMABRAQABLgAECgkJFwAGAGIYAA==.Camvoker:BAAALgADCgEJAQAAAA==.Carapace:BAABLgAECn8uAAIIAAgJog+CJgB1AQAIAAgJog+CJgB1AQAAAA==.Carare:BAAALgADCggJDQAAAA==.Catomaze:BAAALgAECgEJAQAAAA==.',
Ce='Ceefack:BAAALgAECgQJCAAAAA==.Celebsteele:BAAALgADCgYJBwAAAA==.Celestialsky:BAAALgAECgkJAQAAAA==.Celicel:BAAALgADCgcJBwAAAA==.Cena:BAABLgAECn8kAAMTAAcJIQtFCwA4AQATAAcJHwtFCwA4AQAOAAYJ/AgAKwDjAAAAAA==.Cethin:BAAALgAECgYJDQAAAA==.',
Ch='Chaosform:BAAALgADCgkJJgABLgAFFAMJCgAUACIjAA==.Chaosshot:BAACLgAFFH8KAAMUAAMJIiM5DQA2AQAUAAMJIiM5DQA2AQAVAAEJRCE7IwBlAAAuAAQKfyUAAxUACAlNJDQGADkDABUACAlNJDQGADkDABQAAQmLJEw+AGYAAAAA.Cherylindrea:BAAALgADCgcJFwAAAA==.Chronic:BAABLgAECn8ZAAIDAAgJ+A/cYABkAQADAAgJ+A/cYABkAQAAAA==.Chènch:BAAALgADCgEJAQABLgAECgcJGQAWACMMAA==.',
Ci='Cindera:BAAALgADCggJCAAAAA==.',
Cl='Claydemon:BAAALgAECgYJEAAAAA==.Clayman:BAAALgAECgYJBgAAAA==.Claytraps:BAAALgADCgkJJQAAAA==.Clayvicar:BAACLgAFFH8KAAMXAAMJPAc7FwCxAAAXAAMJPAc7FwCxAAAYAAEJYgDxFwA3AAAuAAQKfygAAxcACAkOE6ghANYBABcACAkOE6ghANYBABgAAwlgA59XAGAAAAAA.',
Co='Coconutty:BAAALgAECgYJBgAAAA==.Coridane:BAABLgAECn8XAAIXAAcJDBXlHQCNAQAXAAcJDBXlHQCNAQAAAA==.Corrum:BAAALgADCgIJAgAAAA==.Corwinfiron:BAAALgAECggJEgAAAA==.Cotreyy:BAACLgAFFH8RAAMZAAQJniUsBgC+AQAZAAQJniUsBgC+AQAaAAEJIyUBEABqAAAuAAQKfycABBkACAlKJhYRAPICABkABwnkJRYRAPICABsABQk4JvcEACMCABoABAkRIhwXAJEBAAAA.Covah:BAAALgADCgIJAgAAAA==.',
Cr='Cristen:BAAALgADCgYJCQAAAA==.Crobat:BAAALgAECgYJCAAAAA==.',
Cu='Cumgar:BAABLgAECn8gAAIZAAgJlBHGWAC9AQAZAAgJlBHGWAC9AQAAAA==.',
Cy='Cythera:BAACLgAFFH8WAAIJAAYJDSGwAADNAQAJAAYJDSGwAADNAQAuAAQKfx4AAgkACQkcJFoEANgCAAkACQkcJFoEANgCAAAA.',
['Cá']='Cámus:BAABLgAECn8dAAIDAAYJ3RriawBLAQADAAYJ3RriawBLAQAAAA==.',
['Cö']='Cöffee:BAAALgAECgUJEAAAAA==.',
Da='Daammy:BAAALgADCggJEAAAAA==.Dagran:BAAALgAECgQJCQABLgAECgcJFwAHALwfAA==.Dagren:BAAALgAECgYJCQAAAA==.Dankfrost:BAAALgADCgcJEgAAAA==.Daphine:BAAALgADCgcJFwAAAA==.Darimonk:BAAALgADCgMJBQAAAA==.Darkbeautie:BAABLgAECn8XAAIOAAYJnAOxLgDHAAAOAAYJnAOxLgDHAAAAAA==.Darkcarbon:BAABLgAECn8UAAIHAAYJCgvjegDWAAAHAAYJCgvjegDWAAAAAA==.Darmin:BAAALgAECgIJAgAAAA==.',
De='Deathmask:BAAALgADCgEJAQAAAA==.Deepdarkdank:BAAALgADCgEJAQAAAA==.Deepmoanpaw:BAAALgAECgYJCQAAAA==.Defnotash:BAACLgAFFH8KAAIcAAQJJgx8BQDhAAAcAAQJJgx8BQDhAAAuAAQKfyYAAhwACQmbH7sBADIDABwACQmbH7sBADIDAAAA.Dellinair:BAAALgADCgEJAQAAAA==.Dementedlock:BAAALgAECgcJEQAAAA==.Demontacos:BAAALgAECgYJCQAAAA==.Derodd:BAAALgAECgQJBQAAAA==.Desolend:BAAALgADCgIJAgAAAA==.Dewkiez:BAEALgAFFAIJBAAAAA==.',
Di='Diabolicarl:BAABLgAECn8nAAIKAAkJHxRnDQDsAQAKAAkJHxRnDQDsAQAAAA==.Dibsy:BAACLgAFFH8HAAMdAAQJvA4dGAAEAQAdAAQJvA4dGAAEAQAeAAIJ7RXiGwCWAAAuAAQKfzsAAx4ACQnDITQDAPwCAB4ACQnDITQDAPwCAB0ABgnOHvMTAA0CAAAA.Diri:BAAALgADCgcJBwABLgAECgkJIQAOADQVAA==.Dis:BAAALgAECgEJAQABLgAFFAMJCwAEANoMAA==.Disgrace:BAABLgAECn8oAAIQAAgJsg2HFwA0AQAQAAgJsg2HFwA0AQAAAA==.Dividane:BAAALgADCgYJBgAAAA==.',
Dm='Dmossyoak:BAAALgADCgkJAgAAAA==.',
Do='Donniedipes:BAABLgAECn8nAAIBAAkJ3g//PwC9AQABAAkJ3g//PwC9AQAAAA==.Dookiez:BAEBLgAECn8ZAAIJAAgJnSNoAgAmAwAJAAgJnSNoAgAmAwABLgAFFAIJBAAfAAAAAA==.Doublade:BAAALgAECgcJBwAAAA==.Doubledragin:BAABLgAECn8lAAMgAAcJ2BkgHQCcAQAgAAcJ2BkgHQCcAQAhAAMJ6gKVNgBiAAAAAA==.',
Dr='Dracantar:BAAALgADCgUJBQAAAA==.Dracotako:BAAALgAECgYJCwAAAA==.Dractini:BAACLgAFFH8IAAMiAAQJtgY+FADxAAAiAAQJtgY+FADxAAAgAAIJFgOAHQCEAAAuAAQKfxoAAyIACAm9CsckAFIBACIABwlcC8ckAFIBACAABwl8DgUyADgBAAEuAAUUBwknABcAZBEA.Draeneiamin:BAAALgADCgMJAwABLgAECgcJDQAfAAAAAA==.Dragfan:BAAALgAECgUJBwAAAA==.Dragonsniper:BAAALgAECgQJCAAAAA==.Dragore:BAABLgAECn8ZAAIIAAYJthu2NwDIAQAIAAYJthu2NwDIAQAAAA==.Druidgirls:BAACLgAFFH8IAAIEAAMJPxELKwDJAAAEAAMJPxELKwDJAAAuAAQKfygAAgQACQndGMUqAAYCAAQACQndGMUqAAYCAAAA.Dràugluin:BAAALgAFFAEJAQAAAA==.',
Du='Duasoras:BAABLgAECn8fAAICAAgJ9gRNWQDoAAACAAgJ9gRNWQDoAAAAAA==.Duelist:BAAALgADCgUJBQAAAA==.Dundlen:BAAALgADCggJDwABLgAFFAIJBgAGAOQDAA==.Dunvel:BAAALgAECgMJAwAAAA==.Durogdem:BAAALgAECgIJBAAAAA==.',
Dy='Dynamite:BAAALgAECgEJBAAAAA==.',
Ea='Earthaggie:BAAALgADCgcJFwAAAA==.',
Ed='Edea:BAAALgAECgEJAQAAAA==.Ederon:BAAALgAECgMJAQAAAA==.',
El='Elaelta:BAAALgAECgMJCQAAAA==.Eleetmage:BAAALgAECgEJAQAAAA==.Elenora:BAABLgAECn82AAIFAAkJhAQ7MQD9AAAFAAkJhAQ7MQD9AAAAAA==.Elesity:BAAALgADCgEJAQABLgAFFAUJEgAfAAAAAA==.Elye:BAAALgAECgMJAwABLgAECgYJEwAfAAAAAA==.',
Em='Emer:BAACLgAFFH8LAAMEAAMJ2gz+SQBLAAAEAAIJIwH+SQBLAAAFAAMJCQFoMABJAAAuAAQKfykAAwUACAnMCgc7AEkBAAUABwlPDAc7AEkBAAQABwnWBhV5AIcAAAAA.',
En='Encore:BAACLgAFFH8IAAIEAAMJvAQlMwCnAAAEAAMJvAQlMwCnAAAuAAQKfzQAAgQACAknEpEtAKcBAAQACAknEpEtAKcBAAAA.',
Eo='Eousphorus:BAACLgAFFH8RAAIGAAQJuRhBNABPAQAGAAQJuRhBNABPAQAuAAQKfyoAAgYACAmiIFshAFsCAAYACAmiIFshAFsCAAAA.',
Er='Erathen:BAAALgAECgUJBAAAAA==.Eridi:BAAALgADCgEJAQAAAA==.Eroenice:BAAALgAECgQJBAAAAA==.',
Et='Etile:BAAALgADCgkJFgAAAA==.',
Ev='Evelleion:BAABLgAECn8VAAMjAAgJyRGIPgCRAQAjAAgJKxCIPgCRAQAVAAQJDhFMWgDbAAAAAA==.',
Ex='Exoticlord:BAABLgAECn8eAAMjAAgJyRn6JgD0AQAjAAgJyRn6JgD0AQAVAAYJ6BDkQQBQAQAAAA==.',
Fa='Failagos:BAAALgADCgMJAwAAAA==.Fallujah:BAAALgADCgUJBQAAAA==.',
Fe='Felicene:BAABLgAECn8oAAIkAAgJuyTkAQDcAgAkAAgJuyTkAQDcAgAAAA==.Fellynn:BAACLgAFFH8LAAINAAMJMiMOAgA2AQANAAMJMiMOAgA2AQAuAAQKfygAAg0ACAmjJZ8AAFsDAA0ACAmjJZ8AAFsDAAAA.',
Fi='Fieperskaivu:BAABLgAECn8XAAMHAAcJvB8SIgCFAgAHAAcJvB8SIgCFAgAKAAUJMRqnNQAxAQAAAA==.Fierygrace:BAAALgADCgYJBgAAAA==.Firefalco:BAAALgADCggJCQAAAA==.',
Fl='Flameth:BAACLgAFFH8JAAIZAAMJZgGjagCeAAAZAAMJZgGjagCeAAAuAAQKfxwAAhkACAn7C6hqACkBABkACAn7C6hqACkBAAAA.Flamingbunz:BAAALgAECgIJAgAAAA==.Flashblood:BAACLgAFFH8MAAIIAAQJmSNNBwB/AQAIAAQJmSNNBwB/AQAuAAQKfykAAwgACQndJNEQAMoCAAgACQncJNEQAMoCAA8AAwnxIosYADQBAAAA.Flashers:BAAALgAECggJBwAAAA==.Flavortown:BAAALgAECgUJBQAAAA==.',
Fo='Forgiven:BAABLgAECn8VAAIDAAcJqBrIVADjAQADAAcJqBrIVADjAQAAAA==.Foxtrót:BAABLgAECn8aAAIjAAcJhA+hTQBfAQAjAAcJhA+hTQBfAQABLgAECgkJKwAQANUiAA==.',
Fr='Freeb:BAAALgAECgMJBQABLgAECggJMQADANkJAA==.Freebzz:BAAALgADCgQJBwABLgAECggJMQADANkJAA==.Freezrorburn:BAAALgAECgYJDQAAAA==.Frostyndikit:BAAALgAECgMJAwAAAA==.',
Fu='Fu:BAAALgADCgUJBQAAAA==.Fumanchu:BAABLgAECn8rAAIQAAkJ1SIKAgABAwAQAAkJ1SIKAgABAwAAAA==.',
Ga='Gaamora:BAAALgADCgcJFwAAAA==.Gainsborough:BAAALgAECggJCAAAAA==.Galadore:BAAALgADCgIJAwAAAA==.Garagos:BAACLgAFFH8LAAITAAMJORa8BAD+AAATAAMJORa8BAD+AAAuAAQKfygAAhMACAlmHSkEAHECABMACAlmHSkEAHECAAAA.Gatherina:BAAALgAECgQJBgABLgAECgcJFwAHALwfAA==.',
Ge='Gebuss:BAACLgAFFH8FAAITAAQJpRlOAgBlAQATAAQJpRlOAgBlAQAuAAQKfxwAAhMACQl9Iq8CAMECABMACQl9Iq8CAMECAAAA.Gempally:BAAALgADCgMJBgAAAA==.Genzo:BAAALgAECgUJCgAAAA==.',
Gh='Ghorynv:BAAALgAECgYJBgAAAA==.',
Gi='Giah:BAAALgAECgYJCAAAAA==.Giborim:BAAALgADCgEJAQAAAA==.Gigapriest:BAAALgAECgYJBgAAAA==.',
Gl='Glavela:BAAALgAECgYJEwAAAA==.Gloomfist:BAAALgAECgYJEwAAAQ==.',
Go='Goochaddi:BAAALgADCgMJAwABLgAECgUJBQAfAAAAAA==.Gozer:BAAALgADCgYJBgAAAA==.',
Gr='Graven:BAAALgAECggJEwAAAA==.Graveside:BAAALgAECgEJAQAAAA==.Greymist:BAAALgADCgEJAQAAAA==.Grizzlock:BAAALgADCgMJAwAAAA==.',
Gu='Gulivar:BAABLgAECn8ZAAIWAAcJIwyEIgBbAQAWAAcJIwyEIgBbAQAAAA==.Gunnerrata:BAAALgAECgYJCAAAAA==.',
Ha='Halfrican:BAAALgAECgQJBAAAAA==.Halifaxx:BAACLgAFFH8GAAMGAAIJ5AMNgQCJAAAGAAIJ5AMNgQCJAAAlAAEJNQEsAwBGAAAuAAQKfykAAyUACAlOH/oBAPwBACUACAmRHPoBAPwBAAYABwnyG3lBANUBAAAA.Happygilmore:BAAALgAECgIJAwAAAA==.Harambee:BAAALgAECgEJAQABLgAECgcJEAAfAAAAAA==.Hariasa:BAAALgAECgMJAwAAAA==.Harlyquin:BAAALgAECgkJAgAAAA==.Harmaa:BAAALgAECgYJEwAAAA==.Hawknor:BAAALgAECgYJEAAAAA==.',
He='Headpool:BAAALgAECgQJCAABLgAECgUJBQAfAAAAAA==.Healenya:BAAALgAECgcJBwAAAA==.Healthcare:BAAALgAECgcJDwABLgAFFAcJJwAXAGQRAA==.Healywilly:BAAALgADCggJGQAAAA==.Herm:BAACLgAFFH8IAAIeAAMJ8yTBCABFAQAeAAMJ8yTBCABFAQAuAAQKfycAAh4ACAlGI5IHAAMDAB4ACAlGI5IHAAMDAAAA.',
Hi='Highbear:BAAALgAECgYJDgAAAA==.Hiryu:BAAALgADCgYJBgAAAA==.',
Ho='Holyfaxx:BAAALgAECgUJBgABLgAFFAIJBgAGAOQDAA==.Holymidget:BAAALgADCggJDQAAAA==.Holysky:BAAALgAECgYJDwAAAA==.Holysmokes:BAAALgAECgUJBwAAAA==.Holytim:BAABLgAECn8oAAQWAAgJHBhSIwBVAQAWAAgJexZSIwBVAQAXAAYJ4xDLRAAmAQAYAAcJrw03LAAfAQAAAA==.Honnik:BAACLgAFFH8KAAITAAMJEA1aBQDsAAATAAMJEA1aBQDsAAAuAAQKfycAAhMACQn1F8gDAB8CABMACQn1F8gDAB8CAAAA.Hortance:BAAALgAECgcJBwAAAA==.Hothot:BAAALgAECgQJBQAAAA==.Hotsndots:BAAALgAECgEJAQAAAA==.Houndoom:BAABLgAECn8sAAImAAgJxhafGACkAQAmAAgJxhafGACkAQAAAA==.How:BAACLgAFFH8LAAIdAAQJ/RyCEQBMAQAdAAQJ/RyCEQBMAQAuAAQKfxwAAx0ACAkMHbcNAHkCAB0ACAkMHbcNAHkCAB4AAQkHCBKBAC8AAAAA.',
Hu='Hugspotato:BAAALgAFFAMJBAAAAA==.Huyrak:BAAALgADCgUJBQAAAA==.',
Hy='Hypoxic:BAAALgAECgYJEAAAAA==.',
Ia='Iah:BAACLgAFFH8IAAIJAAMJkQG2CAChAAAJAAMJkQG2CAChAAAuAAQKfyIAAgkACAmaCuoPALkBAAkACAmaCuoPALkBAAAA.',
Ic='Icastspells:BAAALgAECgUJBwAAAA==.Icritmepants:BAAALgAECgMJAwAAAA==.Icyveinuser:BAAALgADCgcJKAAAAA==.',
Ig='Ignored:BAABLgAECn8mAAMDAAgJVh5iHABZAgADAAgJVh5iHABZAgAnAAEJoAHugQAVAAAAAA==.',
Il='Illidæn:BAABLgAECn8bAAIHAAkJIRFQOwCNAQAHAAkJIRFQOwCNAQAAAA==.Illistra:BAAALgADCgYJBgABLgAECgcJDQAfAAAAAA==.',
Im='Impuratus:BAAALgAECgQJBwAAAA==.',
In='Inq:BAABLgAECn8bAAIGAAgJQR8SIABiAgAGAAgJQR8SIABiAgAAAA==.',
Ir='Iridaceaë:BAABLgAECn80AAMXAAkJnxwuBgDSAgAXAAkJnxwuBgDSAgAWAAMJHgiqRQCMAAABLgAECgkJLAAdAG8hAA==.Ironpaw:BAABLgAECn8UAAIeAAYJShCPLAAKAQAeAAYJShCPLAAKAQAAAA==.Iryris:BAABLgAECn8dAAIFAAcJ3QaYNgDhAAAFAAcJ3QaYNgDhAAAAAA==.',
Is='Isedeath:BAACLgAFFH8LAAMRAAMJ2Q9aCQDVAAARAAMJjAhaCQDVAAABAAIJ1hEUlACXAAAuAAQKfy8ABAEACAlSHKEwAHUCAAEACAlSHKEwAHUCABEAAglLGmkXAI4AABIAAglhAG9BAEYAAAAA.',
Ja='Jabber:BAAALgAECgYJDQABLgAECggJGQADAPgPAA==.Jabul:BAAALgADCgYJBgAAAA==.Jack:BAABLgAECn8jAAMZAAgJhSMwHAA+AgAZAAYJNiMwHAA+AgAaAAIJXSUIIQBmAAAAAA==.Jaegerr:BAABLgAECn8PAAIYAAkJzgmuLwAMAQAYAAkJzgmuLwAMAQAAAA==.Jaing:BAAALgADCgEJAQAAAA==.Jalene:BAAALgADCgcJAwAAAA==.Jamonk:BAAALgADCgYJBwABLgADCggJCAAfAAAAAA==.Jamuul:BAAALgADCggJCAAAAA==.Janton:BAABLgAECn8bAAIIAAgJRAniLgBFAQAIAAgJRAniLgBFAQAAAA==.Jarrhead:BAAALgAECgYJEgAAAA==.Jastor:BAAALgADCgcJDgAAAA==.Jaxirl:BAAALgAECgUJBQAAAA==.',
Je='Jenaveive:BAAALgAECgQJBAABLgAECggJGQAYAOcIAA==.Jethli:BAACLgAFFH8YAAImAAUJHxNeFgAmAQAmAAUJHxNeFgAmAQAuAAQKfygAAiYACQlUGvQJAFsCACYACQlUGvQJAFsCAAAA.',
Ji='Jigopocalyps:BAAALgADCgEJAQAAAA==.Jinn:BAAALgADCgYJBAAAAA==.',
Jj='Jjp:BAAALgADCgYJCQAAAA==.',
Jn='Jnex:BAAALgAECgEJAQAAAA==.',
Jo='Jojobeànfire:BAAALgADCggJDgAAAA==.Joube:BAAALgAECggJEwAAAA==.',
Ju='Judgepain:BAAALgAECgEJBQAAAA==.Judgmental:BAABLgAECn8YAAMnAAgJ1RDJIwCbAQAnAAgJ1RDJIwCbAQADAAYJaQI03wCGAAAAAA==.Juicytootsie:BAABLgAECn8UAAIGAAYJdwN4BwHtAAAGAAYJdwN4BwHtAAAAAA==.Justifried:BAAALgAECgQJBAAAAA==.',
['Jä']='Jävel:BAAALgAECgYJDgAAAA==.',
Ka='Kaelysong:BAAALgAECgMJBAAAAA==.Kairah:BAAALgAECgYJCgAAAA==.Kairiandel:BAAALgAECgIJAgAAAA==.Kaivig:BAAALgAECgEJAQAAAA==.Kalï:BAABLgAECn8iAAIjAAgJoSIyDACuAgAjAAgJoSIyDACuAgAAAA==.Karaha:BAAALgADCgcJBwAAAA==.Karukan:BAAALgAECgEJAQAAAA==.Kayllin:BAAALgAECgIJAgAAAA==.Kaysina:BAAALgADCgUJBQAAAA==.Kazarahu:BAAALgAECgEJAQAAAA==.',
Ke='Keener:BAABLgAECn8WAAMIAAYJhiEUHAC+AQAIAAYJhiEUHAC+AQAQAAIJMBNnOQB/AAAAAA==.Kelenil:BAAALgAECgEJAQABLgAECgQJBAAfAAAAAA==.Kerrla:BAACLgAFFH8XAAIFAAUJHBvvDgBJAQAFAAUJHBvvDgBJAQAuAAQKfycAAgUACAnqI58JAPsCAAUACAnqI58JAPsCAAEuAAMKAwkDAB8AAAAA.Keylleth:BAAALgAECgYJEQAAAA==.',
Kh='Khalanie:BAAALgADCgkJCQAAAA==.Khamari:BAAALgADCgYJBgABLgAECgYJEAAfAAAAAA==.Khamnox:BAAALgAECgYJEAAAAA==.Khlamps:BAAALgAECgMJAwAAAA==.',
Ki='Kielnmsoftly:BAABLgAECn8WAAIBAAkJ5BSTNADmAQABAAkJ5BSTNADmAQAAAA==.Kilaia:BAABLgAECn8UAAIjAAYJkxBxZgAaAQAjAAYJkxBxZgAaAQAAAA==.Kilda:BAAALgADCgcJBwAAAA==.Killerklown:BAAALgAECgUJCAAAAA==.Kirksñiper:BAAALgAECgYJDgAAAA==.Kirru:BAABLgAECn8jAAQXAAgJFA5oIwBgAQAXAAgJFA5oIwBgAQAWAAMJXAG/TQBbAAAYAAIJZgPXWwA+AAAAAA==.Kirsty:BAAALgADCgMJAwAAAA==.',
Kl='Klink:BAAALgAECgUJDwABLgAECgcJGQAWACMMAA==.',
Kn='Knoble:BAABLgAECn8WAAQIAAgJhh5vDQBRAgAIAAgJNR5vDQBRAgAPAAMJuQ/aNQCJAAAQAAEJHB/UNQBYAAAAAA==.',
Kr='Kraisee:BAAALgADCgEJAQAAAA==.Kreatan:BAAALgADCgUJBwAAAA==.Kreaton:BAAALgAECgkJEwAAAA==.Krel:BAAALgAECgEJAQAAAA==.Kryntoo:BAAALgADCggJCAAAAA==.Kryptic:BAAALgAECgYJBAAAAA==.Kryptix:BAAALgADCgYJCAAAAA==.',
Ks='Kshatriya:BAAALgADCgQJBAAAAA==.',
Ku='Kuchikix:BAAALgAECgEJAQAAAA==.Kuchíki:BAABLgAECn8ZAAIdAAcJNA5OMwAUAQAdAAcJNA5OMwAUAQAAAA==.Kushynuggles:BAAALgADCgEJAQAAAA==.',
Kw='Kwag:BAAALgAECgcJBgAAAA==.',
La='Laaklem:BAAALgADCgkJHgAAAA==.Laei:BAAALgAECggJEAAAAA==.Lagerthaa:BAAALgADCgIJAgAAAA==.Laserfingies:BAAALgAECgUJBwAAAA==.Lastsun:BAABLgAECn8VAAIGAAcJmQ1ZdgBNAQAGAAcJmQ1ZdgBNAQAAAA==.Lauridana:BAAALgADCgEJAQAAAA==.Lavacakes:BAACLgAFFH8LAAICAAMJviW2FABNAQACAAMJviW2FABNAQAuAAQKfyYAAgIACAnZJL8DADoDAAIACAnZJL8DADoDAAAA.Lazaren:BAAALgADCgMJAwAAAA==.Lazyboy:BAABLgAECn8ZAAIIAAcJpR4BHABtAgAIAAcJpR4BHABtAgAAAA==.',
Le='Lelantoz:BAABLgAECn8fAAIjAAYJuAnoZQA2AQAjAAYJuAnoZQA2AQAAAA==.Leliel:BAAALgADCgEJAQAAAA==.Lenailla:BAAALgADCgkJCQAAAA==.Lezibean:BAAALgADCgcJBwABLgAFFAMJBAAfAAAAAA==.',
Li='Lidan:BAABLgAECn8eAAITAAkJMg+IBQDVAQATAAkJMg+IBQDVAQAAAA==.Liebli:BAAALgAECgQJBAAAAA==.Liffry:BAAALgADCgEJAQAAAA==.Lilena:BAAALgADCgkJLQAAAA==.Lilnao:BAAALgAECgcJCAAAAA==.Linaeni:BAAALgAECgQJBAAAAA==.Linaradice:BAAALgAECggJDwAAAA==.Linkinbiox:BAAALgAECgUJCgAAAA==.',
Lo='Lockedown:BAAALgADCgkJCQAAAA==.Lockhart:BAAALgAECgEJAQAAAA==.Logyn:BAAALgAECgMJBAAAAA==.Lonnias:BAAALgADCgcJBwAAAA==.Lore:BAABLgAECn8dAAIGAAgJ1hHtegBFAQAGAAgJ1hHtegBFAQAAAA==.Lotsalock:BAAALgADCgcJCwAAAA==.',
Lu='Lululemons:BAAALgAECgMJBAAAAA==.',
Ly='Lyphysia:BAAALgAECgcJDQAAAA==.Lyrelia:BAAALgAECgYJDgAAAA==.Lyssiarose:BAAALgAECgYJEQAAAA==.',
['Lë']='Lëucocrystal:BAAALgADCgYJBwAAAA==.',
Ma='Mack:BAAALgADCgEJAQAAAA==.Madbones:BAABLgAECn8aAAMZAAkJ7ROrLgDfAQAZAAkJ4xGrLgDfAQAbAAMJXxqJEwD2AAAAAA==.Mado:BAAALgAECggJEQAAAA==.Maeveracy:BAAALgADCgUJBQAAAA==.Mageijuana:BAABLgAECn8bAAIGAAgJEh64LQAgAgAGAAgJEh64LQAgAgAAAA==.Magicky:BAABLgAECn8fAAIGAAcJdxeHTwCrAQAGAAcJdxeHTwCrAQAAAA==.Magicsauce:BAAALgAECgYJBwAAAA==.Mahlkier:BAAALgADCgcJFwAAAA==.Maikego:BAAALgAECgUJDQAAAA==.Malchelo:BAAALgAECggJEAAAAA==.Malfhunter:BAACLgAFFH8IAAIVAAQJOgzPDAAZAQAVAAQJOgzPDAAZAQAuAAQKfyoAAhUACQl+Gf0SAJ4CABUACQl+Gf0SAJ4CAAAA.Maligosa:BAAALgADCgUJBQAAAA==.Manabender:BAAALgAECgIJAgAAAA==.Mangolassi:BAAALgADCgEJAQAAAA==.Manofwood:BAABLgAFFH8JAAILAAQJSxEqBgAQAQALAAQJSxEqBgAQAQAAAA==.Mantodea:BAAALgAECgQJAQAAAA==.Manus:BAAALgAECgMJBQAAAA==.Maranatha:BAAALgADCgEJAQAAAA==.Marossa:BAAALgADCgMJAwAAAA==.Marymae:BAAALgADCgcJFwAAAA==.Masskiller:BAAALgADCgIJAgAAAA==.Masumi:BAAALgADCgEJAQAAAA==.Mattikus:BAAALgAECgQJDAAAAA==.Maximilion:BAAALgAECgYJCgAAAA==.',
Me='Megrim:BAAALgADCgIJAwAAAA==.Mehrartz:BAAALgADCgYJCwAAAA==.Melyn:BAAALgADCgIJAgAAAA==.Merdocki:BAACLgAFFH8IAAMZAAMJ+hczSgDrAAAZAAMJ+hczSgDrAAAaAAEJURVfGABNAAAuAAQKfygAAxoACAnkIcMPANIBABoABQk6H8MPANIBABkABQltIfFGAIcBAAAA.Merdra:BAAALgAECgcJCQAAAA==.Merdre:BAACLgAFFH8LAAQWAAMJthJHHgDdAAAWAAMJvA5HHgDdAAAXAAIJaxVlGwCHAAAYAAEJVACSKgAtAAAuAAQKfzYABBcACQnFGZAOAHUCABcACAlIHJAOAHUCABYACAktFKMZAKoBABgABQkAAgxLAK0AAAAA.Mertele:BAAALgAECgQJBAAAAA==.Messörem:BAAALgADCgYJBgAAAA==.Metasavage:BAAALgAECgQJBAABLgAECgUJBQAfAAAAAA==.',
Mi='Michealhunt:BAAALgAECgcJCQAAAA==.Midory:BAAALgAECgEJAQAAAA==.Mikimukka:BAAALgADCgIJAwAAAA==.Milim:BAAALgAECgQJBQABLgAECgUJBQAfAAAAAA==.Milkymocha:BAABLgAECn8jAAIcAAgJcBl+CQDhAQAcAAgJcBl+CQDhAQAAAA==.Minus:BAAALgADCgMJAwAAAA==.Misfitjoker:BAAALgAECgEJAQAAAA==.Misscorona:BAAALgADCggJDQAAAA==.Mistyque:BAAALgAECgQJCgAAAA==.Mithrond:BAAALgADCggJCgABLgAECgEJAQAfAAAAAA==.',
Mo='Modercai:BAAALgAECgQJBAAAAA==.Monkeymann:BAAALgADCgYJBgAAAA==.Morcant:BAAALgAECgYJDAAAAA==.Morhg:BAABLgAECn8lAAMaAAgJ1AjlEADnAAAZAAgJkAcefwD+AAAaAAcJGQjlEADnAAAAAA==.Morianoley:BAAALgADCggJEwAAAA==.Morlu:BAABLgAECn8fAAIIAAcJER8aIQBKAgAIAAcJER8aIQBKAgAAAA==.',
Ms='Msdonnapally:BAAALgAECgUJCQAAAA==.',
Mu='Mugnar:BAAALgADCgcJBwAAAA==.',
My='Myn:BAAALgAECgQJBAABLgAECggJCAAfAAAAAA==.',
['Mÿ']='Mÿsha:BAAALgAECgEJAQAAAA==.',
Na='Nadirya:BAEALgAECgcJCQABLgAFFAQJEgAIAKgeAA==.Nazkrul:BAAALgADCgMJAwAAAA==.',
Ne='Nellykorda:BAAALgAECgYJDwAAAA==.Neodruid:BAAALgAECgcJEQAAAA==.Nexxicus:BAAALgADCgYJCQAAAA==.',
Ni='Nightlywomen:BAAALgADCgcJDAAAAA==.Nightmehr:BAACLgAFFH8JAAIGAAQJ6BnLKQBiAQAGAAQJ6BnLKQBiAQAuAAQKfykAAgYACQkcI30QAEUDAAYACQkcI30QAEUDAAAA.Nightphaze:BAAALgAECgEJAQABLgAECggJGQADAPgPAA==.Nihm:BAAALgADCgcJEQAAAA==.Nikolatte:BAAALgAECgEJBAAAAA==.Nimda:BAABLgAECn8aAAIBAAgJfiFrGwDZAgABAAgJfiFrGwDZAgAAAA==.',
No='Nosaj:BAAALgADCgkJCwAAAA==.',
Nu='Nullex:BAABLgAECn8jAAQHAAgJ+hV1OgCQAQAHAAgJ+hV1OgCQAQAKAAEJ8wkMUwAoAAANAAEJZQiHKgAdAAAAAA==.',
Ny='Nycara:BAAALgADCgMJAwAAAA==.Nyki:BAAALgAECgEJAQAAAA==.',
Ob='Oberon:BAAALgADCgYJBgAAAA==.',
Od='Odlaw:BAABLgAECn8jAAIYAAgJeQwqIwBYAQAYAAgJeQwqIwBYAQAAAA==.',
Of='Officiant:BAAALgAECgIJAgAAAA==.',
Ol='Olaria:BAAALgAECgUJBgABLgAECgcJIQAjAFcXAA==.Oldsaggins:BAAALgAECgcJEQAAAA==.Olikel:BAAALgADCgEJAQAAAA==.Ollymay:BAAALgAECgYJBgABLgAECggJEwAfAAAAAA==.Olm:BAAALgAECgUJBQAAAA==.',
On='Onedruidtion:BAAALgAECgQJBQAAAA==.',
Op='Ophekins:BAAALgADCgcJCwAAAA==.',
Or='Orcman:BAAALgAECgEJAQAAAA==.Orheo:BAAALgADCgQJBAAAAA==.Originalchip:BAAALgAECgYJEQAAAA==.Orionmoon:BAAALgAECgkJCwAAAA==.Orley:BAAALgADCgYJBgAAAA==.Orlos:BAABLgAECn8hAAIjAAcJVxeVOwCbAQAjAAcJVxeVOwCbAQAAAA==.Oräkk:BAACLgAFFH8HAAIQAAMJShlSBwDuAAAQAAMJShlSBwDuAAAuAAQKfxwAAhAACAn9HlcJABcCABAACAn9HlcJABcCAAAA.',
Os='Osrs:BAAALgAECgMJAwAAAA==.',
Ox='Oxelmorphs:BAAALgADCgcJCwAAAA==.',
Pa='Padrin:BAABLgAECn8iAAMjAAgJpBZILwDNAQAjAAgJpBZILwDNAQAVAAUJMA3sUQAFAQAAAA==.Palehorsemen:BAAALgAECgUJCwAAAA==.Pandaberry:BAAALgAECgYJCQAAAA==.Pandapaws:BAACLgAFFH8KAAICAAMJnRpmKADnAAACAAMJnRpmKADnAAAuAAQKfysAAgIACQnPIWAHAPECAAIACQnPIWAHAPECAAAA.Pandomonium:BAAALgADCgIJAgAAAA==.Papawaas:BAAALgAECgEJAgAAAA==.Parthal:BAABLgAECn8VAAMDAAgJAQfTowDlAAADAAgJxgPTowDlAAAcAAMJqAugOgBUAAAAAA==.Partylock:BAAALgAECgMJAwABLgAECggJFwAjAC4XAA==.Partyshooter:BAABLgAECn8XAAIjAAgJLheALADaAQAjAAgJLheALADaAQAAAA==.Patmage:BAABLgAECn8rAAIGAAgJqxggQQDXAQAGAAgJqxggQQDXAQABLgAFFAUJEgAFADsUAA==.',
Pd='Pdiddi:BAABLgAECn8eAAMBAAkJUx8RLAAIAgABAAgJIxwRLAAIAgARAAcJ2x/4BAD6AQAAAA==.',
Pe='Peed:BAABLgAECn8QAAIHAAcJtQlFqwBvAAAHAAcJtQlFqwBvAAAAAA==.Pellaeon:BAABLgAECn8XAAIBAAkJ2RiOSQAWAgABAAkJ2RiOSQAWAgAAAA==.',
Ph='Phexia:BAAALgAECgUJCAAAAA==.Phlan:BAEALgAECgUJCAAAAA==.Phrostir:BAAALgAECgkJDAAAAA==.Phylactery:BAABLgAECn8nAAIBAAkJfxh6PQBCAgABAAkJfxh6PQBCAgAAAA==.',
Pi='Pierre:BAACLgAFFH8aAAQjAAYJRBehBQBJAQAUAAQJww++CQBTAQAjAAQJQxmhBQBJAQAVAAEJAADGJgAAAAAuAAQKfyUABCMACAmSIt0RAKkCACMACAnKId0RAKkCABQABQmXG6ojAC4BABUABgnpDYdOABYBAAAA.Pillgrimm:BAABLgAECn8bAAIVAAgJNhESCwBpAQAVAAgJNhESCwBpAQAAAA==.Pinktax:BAAALgAECgcJBwAAAA==.Pirotic:BAAALgADCgcJCwAAAA==.',
Po='Poisson:BAABLgAECn8hAAIOAAkJNBWEEQCUAgAOAAkJNBWEEQCUAgAAAA==.Polishdir:BAAALgAECgYJEAAAAA==.Polishduo:BAAALgAFFAEJAQAAAA==.Popsiclepete:BAAALgADCgIJAgAAAA==.Porzingus:BAAALgADCgcJBwAAAA==.Poxi:BAABLgAECn8WAAIgAAgJDRezEwBHAgAgAAgJDRezEwBHAgAAAA==.',
Pr='Praesidiel:BAABLgAECn8aAAIYAAgJ7RZ7GwABAgAYAAgJ7RZ7GwABAgAAAA==.Presxia:BAAALgADCgYJBgAAAA==.Providence:BAACLgAFFH8MAAIKAAQJmhQdBwBCAQAKAAQJmhQdBwBCAQAuAAQKfyoAAgoACQkTI+cBAH4DAAoACQkTI+cBAH4DAAAA.Prsr:BAAALgAECgMJAwABLgAFFAYJFQABADkfAA==.',
Pu='Pudgypaws:BAAALgAECgYJDAAAAA==.Puffed:BAAALgAECgIJAgABLgAFFAMJCwAWALYSAA==.Punchkick:BAAALgAECgUJCAAAAA==.Purfukt:BAAALgAECgYJBgAAAA==.',
Py='Pyrogasm:BAAALgAECgMJBQABLgAFFAYJFQABADkfAA==.Pyrotrue:BAAALgADCgIJAgAAAA==.',
['På']='Pån:BAAALgAECgEJAQAAAA==.',
['Pè']='Pèwpéw:BAAALgAECgUJCQAAAA==.',
Qu='Quickmend:BAAALgAECgQJBgAAAA==.Quickpal:BAAALgAECgcJDAAAAA==.Quickpaw:BAACLgAFFH8MAAIdAAQJhhP0FgAOAQAdAAQJhhP0FgAOAQAuAAQKfygAAh0ACQkgIxYDAEwDAB0ACQkgIxYDAEwDAAAA.Quickshot:BAAALgADCgEJAQAAAA==.',
Ra='Raani:BAAALgADCgcJBwAAAA==.Raccoons:BAACLgAFFH8WAAMjAAYJIhnlAgBuAQAjAAUJpB7lAgBuAQAVAAEJGQP6IABMAAAuAAQKfx8AAyMACQnUIHIbAGICACMACQnUIHIbAGICABUAAwkrCXFqAJQAAAAA.Rageproof:BAABLgAECn8xAAIDAAgJ2Qm1eQAvAQADAAgJ2Qm1eQAvAQAAAA==.Ragged:BAACLgAFFH8IAAIBAAMJCx6sVAAHAQABAAMJCx6sVAAHAQAuAAQKfyMAAgEACAk+IvoXAHQCAAEACAk+IvoXAHQCAAAA.Raidbloom:BAACLgAFFH8TAAIEAAQJTR8HEwBlAQAEAAQJTR8HEwBlAQAuAAQKfyIAAgQACQlxI0UGACcDAAQACQlxI0UGACcDAAAA.Raidheal:BAABLgAFFH8IAAIWAAMJrgZGIQDEAAAWAAMJrgZGIQDEAAABLgAFFAQJEwAEAE0fAA==.Rakroth:BAAALgAECgYJDwAAAA==.Ramook:BAAALgAECgMJAwAAAA==.Randomchar:BAABLgAECn8tAAMDAAgJ9Q6OdwCLAQADAAgJXwyOdwCLAQAcAAUJOBGaHwDAAAAAAA==.Rankor:BAAALgAECgYJEAABLgAECggJLgABAIgeAA==.Rastann:BAACLgAFFH8MAAIDAAQJZROSLQAgAQADAAQJZROSLQAgAQAuAAQKfyoAAgMACQnSIgUOAB4DAAMACQnSIgUOAB4DAAAA.Ratrun:BAAALgAECgEJAQAAAA==.Raycharles:BAAALgAECgYJAQAAAA==.',
Re='Realir:BAABLgAECn8YAAIKAAkJ3RLuDQDiAQAKAAkJ3RLuDQDiAQAAAA==.Reapertoo:BAACLgAFFH8cAAQBAAUJ2SSnBwCUAQABAAUJ2SSnBwCUAQARAAQJ6R2ZAgBqAQASAAEJAADpOAAAAAAuAAQKfzUAAxEACQkAJb8AABoDAAEACQlAJIYHAGQDABEACQkQIr8AABoDAAAA.Recreant:BAAALgADCgYJAQAAAA==.Redbaron:BAABLgAECn8jAAIKAAkJfRTZDgDTAQAKAAkJfRTZDgDTAQAAAA==.Regeth:BAAALgAECgcJEwAAAA==.Repyns:BAACLgAFFH8nAAQZAAgJ+xpfAwDuAQAZAAcJzBlfAwDuAQAaAAQJ7xzBBQAWAQAbAAIJ8iWQCQBjAAAuAAQKfx4ABBkACQnwJcEIADsDABkACAnwJcEIADsDABoAAwnzIoApABwBABsAAwlrH4YRABUBAAAA.Retep:BAAALgADCgEJAQABLgAECgYJDQAfAAAAAA==.Rethul:BAABLgAECn8iAAMgAAgJfBDBJgBVAQAgAAgJfBDBJgBVAQAiAAYJQwS3NADHAAAAAA==.Retsü:BAAALgAECggJDwABLgAFFAcJJwAXAGQRAA==.Rewind:BAAALgADCgUJBQAAAA==.',
Rh='Rhhonn:BAAALgAECgcJEAAAAA==.Rhollor:BAAALgAECgMJAwAAAA==.',
Ri='Ridic:BAABLgAECn8uAAIBAAgJiB6INABkAgABAAgJiB6INABkAgAAAA==.Rimeblade:BAAALgAECgQJBAAAAA==.',
Ro='Robutinblue:BAACLgAFFH8OAAIGAAUJjhf2NABOAQAGAAUJjhf2NABOAQAuAAQKfxsAAgYACAkvH2ElAN0CAAYACAkvH2ElAN0CAAAA.Rocklesnar:BAAALgAECgMJAwAAAA==.Rondle:BAAALgAECgIJBAAAAA==.Rootbeerd:BAAALgAECggJCAAAAA==.Roshak:BAAALgAECgYJCAAAAA==.Rozalin:BAACLgAFFH8LAAIGAAMJwR5lSAAjAQAGAAMJwR5lSAAjAQAuAAQKfygAAgYACAm0JekKAG0DAAYACAm0JekKAG0DAAAA.Rozalinamoon:BAAALgAECgIJAgAAAA==.',
Ru='Ruffprophet:BAAALgAECgEJAQAAAA==.Rugelach:BAEALgAECgEJAQABLgAECgUJCAAfAAAAAA==.Rumi:BAABLgAECn8bAAINAAgJshNxCQB/AQANAAgJshNxCQB/AQAAAA==.Rurouni:BAAALgADCgcJBwAAAA==.',
Ry='Ryoshi:BAACLgAFFH8LAAIUAAMJeRi/EQACAQAUAAMJeRi/EQACAQAuAAQKfy0AAhQACAkQIBADAAIDABQACAkQIBADAAIDAAAA.',
Sa='Sabotender:BAAALgADCgkJEAAAAA==.Sacredragon:BAAALgAECggJEQAAAA==.Sacredswords:BAACLgAFFH8QAAMIAAQJkhlTEAA/AQAIAAQJkhlTEAA/AQAPAAEJnwM2DQBLAAAuAAQKfxkAAggACAkiHvYVAJ0CAAgACAkiHvYVAJ0CAAAA.Saeys:BAAALgADCgMJAwAAAA==.Sandalis:BAAALgADCgkJEgABLgAECgkJIgADAMcZAA==.Sandscale:BAAALgADCggJCAAAAA==.Sannctuary:BAAALgAECgYJEQAAAA==.Sapphiremist:BAABLgAECn8YAAIKAAYJUw9oIQAFAQAKAAYJUw9oIQAFAQAAAA==.Sauerkraut:BAAALgAECgcJAQAAAA==.Savagesin:BAAALgAFFAIJAgABLgAECgUJBQAfAAAAAA==.Sayen:BAAALgADCgkJCQAAAA==.',
Sc='Scachity:BAABLgAECn8bAAMaAAgJDxoEBAD7AQAaAAgJDxoEBAD7AQAZAAMJywnJxgBvAAAAAA==.Scarekroe:BAABLgAECn8pAAMeAAkJ3ht4CQBkAgAeAAkJ3ht4CQBkAgAmAAEJixSAiQAzAAAAAA==.Schein:BAAALgADCgYJEwAAAA==.Scorch:BAAALgAECgEJAQABLgAECggJLgAHAK4cAA==.Scratchers:BAABLgAECn8eAAIFAAgJ4iLMBgArAwAFAAgJ4iLMBgArAwAAAA==.',
Se='Seelina:BAAALgADCgYJBgAAAA==.Sehëthi:BAABLgAECn8XAAMEAAkJyRT4GAA2AgAEAAkJyRT4GAA2AgAFAAEJ9gDjfAALAAAAAA==.Selanni:BAAALgADCgcJCAAAAA==.Sepulchre:BAAALgAECgYJCAAAAA==.Serlotte:BAAALgADCgcJEQAAAA==.',
Sh='Shadesfault:BAAALgAECgcJAQAAAA==.Shadowish:BAAALgADCgEJAQAAAA==.Shadunx:BAAALgADCgIJAgABLgAECgMJAwAfAAAAAA==.Shamaroo:BAAALgAECgUJBQAAAA==.Shaundakul:BAAALgAECgYJCAAAAA==.Shephion:BAAALgAECgEJAQABLgAFFAMJCAAeAPMkAA==.Shiee:BAAALgADCgEJAQAAAA==.Shortnstack:BAABLgAECn8fAAIjAAcJPhGWTgBcAQAjAAcJPhGWTgBcAQAAAA==.Shãdow:BAAALgAECgYJDgAAAA==.',
Si='Sidetracked:BAABLgAECn8mAAIGAAkJeRZmMAAVAgAGAAkJeRZmMAAVAgAAAA==.Silanah:BAACLgAFFH8LAAImAAMJ6hviIAD3AAAmAAMJ6hviIAD3AAAuAAQKfykAAiYACAkUHCUTAHgCACYACAkUHCUTAHgCAAAA.Silverheart:BAAALgAECgcJEQAAAA==.Silvershade:BAAALgADCgEJAQAAAA==.Simori:BAAALgADCgMJBAAAAA==.Sindrel:BAAALgADCgcJBwABLgAECggJGgAmAJMjAA==.',
Sk='Skawalker:BAACLgAFFH8IAAMkAAMJqQ1uCgChAAAkAAIJMQxuCgChAAAEAAIJLhRJOgCHAAAuAAQKfyQAAwQACQlKI/gFAC0DAAQACQlKI/gFAC0DACQABAnJD/AdALEAAAAA.Skyleebaby:BAAALgADCgcJBwAAAA==.',
Sl='Slashers:BAAALgADCgkJCQABLgAECggJHgAFAOIiAA==.Slaynne:BAACLgAFFH8LAAIIAAMJGiYWDgBLAQAIAAMJGiYWDgBLAQAuAAQKfzQAAwgACQm2I3cIACQDAAgACQm2I3cIACQDAA8AAQm9CEpEADAAAAAA.Sleven:BAAALgAECgUJCAABLgAFFAEJAQAfAAAAAA==.Slowfel:BAAALgADCgcJBwAAAA==.',
Sm='Smábes:BAAALgAECgQJBwAAAA==.Smäug:BAACLgAFFH8SAAMgAAYJnBq3CwCgAQAgAAUJnBq3CwCgAQAhAAEJAACmBwB1AAAuAAQKfyYABCEACAkPJd4EALUCACEABwlbI94EALUCACAABwl1JPQRAAYCACIABwkcBakmAEABAAAA.',
Sn='Snobaws:BAAALgAECggJDwAAAA==.',
So='Sockz:BAABLgAECn8bAAIOAAgJfBm2FABsAgAOAAgJfBm2FABsAgAAAA==.Solria:BAABLgAECn8vAAIXAAkJGhw1BgDRAgAXAAkJGhw1BgDRAgAAAA==.Solrosenborg:BAABLgAECn8xAAIBAAkJdyA4DQDIAgABAAkJdyA4DQDIAgAAAA==.Solrosenburg:BAAALgAECgcJEgABLgAECgkJMQABAHcgAA==.Sondreman:BAABLgAECn8pAAMkAAkJYArpDQB2AQAkAAkJYArpDQB2AQAEAAIJoABW5gAfAAAAAA==.Sonnytyphoon:BAABLgAECn8XAAIjAAcJKBhCPACZAQAjAAcJKBhCPACZAQAAAA==.Sorcereo:BAAALgADCgIJBQAAAA==.',
Sp='Spicychip:BAAALgADCgUJBQAAAA==.Spintwowin:BAAALgADCgUJBQAAAA==.Splashers:BAAALgADCgQJBAAAAA==.Spookyghost:BAAALgADCgMJAwAAAA==.Spookysin:BAAALgAECgcJBwABLgAECgUJBQAfAAAAAA==.Spærkle:BAAALgAECgUJBgAAAA==.',
Sq='Squirreltag:BAAALgAECgUJCQAAAA==.',
Sr='Srmorphsalot:BAAALgAECgEJAQABLgAFFAYJGgAjAEQXAA==.',
St='Starnex:BAAALgADCgYJAQAAAA==.Statyrea:BAAALgAECgQJAQAAAA==.Stomped:BAAALgAECgcJDQAAAA==.Strikes:BAAALgAECgYJCAABLgAFFAMJCwANADIjAA==.Stromlac:BAAALgADCgYJBgAAAA==.Styx:BAACLgAFFH8QAAIQAAQJwSEFBgB2AQAQAAQJwSEFBgB2AQAuAAQKfykAAhAACAlhJqoBAGoDABAACAlhJqoBAGoDAAAA.',
Su='Sukfoot:BAAALgAECgMJAwAAAA==.Sumbatadh:BAABLgAECn8dAAMKAAgJzQz/GABRAQAKAAgJzQz/GABRAQAHAAEJPgP67wAiAAAAAA==.Supergooner:BAAALgAFFAEJAQAAAA==.',
Sw='Swiftsoul:BAAALgADCgEJAQAAAA==.',
Sy='Sybexia:BAAALgAECgEJAQAAAA==.Sylvestris:BAABLgAECn8bAAIEAAgJ+htaLgDzAQAEAAgJ+htaLgDzAQAAAA==.',
Ta='Tabcast:BAAALgADCgUJBQAAAA==.Tabtank:BAAALgAECgYJBgAAAA==.Tacodad:BAAALgAECgQJBAAAAA==.Tacofart:BAAALgADCgMJAwAAAA==.Tacos:BAAALgAECgYJDwAAAA==.Tacotitan:BAAALgAECgkJBgAAAA==.Tailas:BAABLgAECn8XAAImAAYJxxzAGACjAQAmAAYJxxzAGACjAQAAAA==.Tailyan:BAAALgADCgEJAQAAAA==.Taiyana:BAAALgADCgcJDgAAAA==.Talanthir:BAAALgADCgMJAwAAAA==.Tangie:BAAALgADCgkJHgAAAA==.Tankjob:BAAALgAECgQJEAAAAA==.Tanklorswift:BAAALgAECgQJCQAAAA==.Taojin:BAABLgAECn8UAAQTAAcJhA+PDQALAQAOAAUJ6xAQOwBBAQATAAcJKg6PDQALAQAMAAEJ5AEFEAAbAAAAAA==.Taojïn:BAAALgAECgEJAQAAAA==.Tapandsap:BAAALgAECgEJAQAAAA==.Tatsuyâ:BAAALgADCgYJCwAAAA==.',
Td='Tdog:BAAALgAECgEJAQAAAA==.',
Te='Teapot:BAAALgAECgcJAQAAAA==.Tedoseirum:BAABLgAECn8dAAIKAAkJyCRoAwBNAwAKAAkJyCRoAwBNAwAAAA==.Tengen:BAAALgAECgEJAQABLgAECgEJAgAfAAAAAA==.Tengenthas:BAAALgAECgEJAgAAAA==.Terpyu:BAAALgAECgYJEAAAAA==.Testicuhls:BAAALgAECgYJEwAAAA==.Texasbilly:BAAALgAECgYJCAAAAA==.Texasredneck:BAAALgADCgQJAwAAAA==.',
Th='Thalchy:BAAALgAECgYJDAAAAA==.Thaydel:BAAALgADCgMJAwAAAA==.Thedtwo:BAABLgAECn8dAAIDAAYJnh7aYwBdAQADAAYJnh7aYwBdAQAAAA==.Thelizzah:BAABLgAECn8gAAMDAAcJZA/PiwANAQADAAYJlA3PiwANAQAnAAIJXwBtnQAsAAAAAA==.Thelvaris:BAAALgAECgYJCwAAAA==.Thorgarrus:BAACLgAFFH8MAAIDAAQJLCGrDgCHAQADAAQJLCGrDgCHAQAuAAQKfyoAAgMACQnCHrMYANUCAAMACQnCHrMYANUCAAAA.',
Ti='Tigerwoodz:BAAALgAECgYJDQAAAA==.Tilbourne:BAAALgAECgEJAQAAAA==.Timfist:BAAALgAECgUJCAAAAA==.Tinada:BAAALgADCgEJAQABLgADCgMJAwAfAAAAAA==.Tinytrina:BAAALgADCgYJBgAAAA==.',
To='Toddie:BAABLgAECn8mAAMjAAkJCB1wEwBtAgAjAAkJCB1wEwBtAgAVAAMJugxqbQCJAAAAAA==.Tolkein:BAAALgADCgEJAQAAAA==.Tommyj:BAAALgAECgQJBAAAAA==.Torep:BAAALgAECgQJBAAAAA==.Tormod:BAABLgAECn8iAAIjAAgJFRp6JwDxAQAjAAgJFRp6JwDxAQAAAA==.Tormodd:BAABLgAECn8bAAIKAAYJ4w0dIwD4AAAKAAYJ4w0dIwD4AAAAAA==.Torsyn:BAAALgAECgUJBQABLgAECgkJJgAjAAgdAA==.Torvaldt:BAAALgAECgIJAgABLgAECgkJJgAjAAgdAA==.',
Tr='Traedea:BAAALgAECgYJCQAAAA==.Traps:BAAALgAECggJCgAAAA==.Trashypanda:BAACLgAFFH8aAAIoAAYJ2SANAAAQAgAoAAYJ2SANAAAQAgAuAAQKfy4AAigACAmEJHsAADQDACgACAmEJHsAADQDAAAA.Trinagirl:BAAALgAECgYJCAAAAA==.Tristanyia:BAABLgAECn8WAAIdAAgJMRixEwAQAgAdAAgJMRixEwAQAgAAAA==.Troolen:BAAALgAECgYJCwAAAA==.Tryana:BAABLgAECn8nAAImAAgJIQZEMQABAQAmAAgJIQZEMQABAQAAAA==.Trystiania:BAAALgAECgYJDwAAAA==.',
Ts='Tseraphim:BAAALgADCgMJBAAAAA==.',
Tt='Tt:BAABLgAECn8aAAIBAAcJswcOlgDxAAABAAcJswcOlgDxAAAAAA==.',
Tu='Tuggnugg:BAAALgAECgEJAQAAAA==.Turcomund:BAAALgADCgMJBAAAAA==.',
Tw='Twentynein:BAAALgAECgcJBwAAAA==.Twentynine:BAABLgAECn80AAQUAAgJ4iI0CABgAgAUAAgJmR40CABgAgAVAAcJnhyhGwBMAgAjAAgJhxazWwA1AQAAAA==.',
Ty='Tyledis:BAAALgAECgUJBwABLgAFFAMJCwAmAOobAA==.Tyr:BAACLgAFFH8LAAIpAAMJeBfuDgD7AAApAAMJeBfuDgD7AAAuAAQKfx8AAykACQnTHb0MANICACkACQnTHb0MANICAAIAAQl1BW6oACIAAAAA.Tyrandi:BAAALgAFFAQJBAAAAA==.Tyrnova:BAAALgAFFAEJAQAAAA==.Tyrsa:BAAALgAECgQJBwAAAA==.',
Tz='Tzneetch:BAAALgAECgEJAQAAAA==.',
['Tï']='Tïnk:BAABLgAECn8hAAIHAAgJgRW0OwCMAQAHAAgJgRW0OwCMAQABLgAFFAIJBAAfAAAAAA==.',
['Tö']='Töshïrö:BAAALgAECgUJCgAAAA==.',
Ub='Ubel:BAAALgADCgEJAwAAAA==.',
Ud='Udderlee:BAAALgAECgYJEwAAAA==.',
Uh='Uhope:BAAALgAECgUJCgAAAA==.',
Uk='Ukog:BAABLgAECn8UAAIOAAgJyQiFHQBMAQAOAAgJyQiFHQBMAQAAAA==.',
Um='Umbravolt:BAACLgAFFH8MAAILAAQJqxjVBAAzAQALAAQJqxjVBAAzAQAuAAQKfy8AAgsACQmOIh0BAFgDAAsACQmOIh0BAFgDAAAA.Umineko:BAAALgAECgEJAQAAAA==.',
Un='Unravel:BAAALgADCgcJFwAAAA==.Unrealpriest:BAAALgAECgMJAwAAAA==.Unrealronin:BAABLgAECn8dAAMQAAgJRgSgIwDIAAAQAAgJxQKgIwDIAAAPAAYJmwXHJADHAAAAAA==.',
Ur='Uruchi:BAAALgADCgEJAQAAAA==.',
Va='Vaelorn:BAABLgAECn8VAAIHAAgJliDtFADaAgAHAAgJliDtFADaAgAAAA==.Vaelun:BAAALgADCgkJDwAAAA==.Vaeris:BAAALgAECgEJAQAAAA==.Vakero:BAABLgAECn8eAAMDAAcJxQb9mQD1AAADAAcJxQb9mQD1AAAnAAIJyQKyaQBBAAAAAA==.Valeriana:BAAALgADCgQJBQAAAA==.Valice:BAAALgAECgEJAQAAAA==.Vanadra:BAAALgADCgMJAwAAAA==.Vapor:BAAALgAECgEJAwAAAA==.Vatheus:BAAALgADCgYJBgAAAA==.Vathion:BAAALgAECgMJAwAAAA==.',
Ve='Vert:BAAALgADCgYJBgABLgAFFAQJCQAaAIAJAA==.',
Vi='Vibrance:BAABLgAECn8cAAQiAAgJNCCHBQDwAgAiAAgJNCCHBQDwAgAgAAYJFBrbKgBpAQAhAAIJSRL/MgB+AAAAAA==.Vindicus:BAAALgAECgUJCAAAAA==.Viridesa:BAAALgAECgQJAQAAAA==.Viserra:BAAALgADCgMJAwAAAA==.Vivienne:BAACLgAFFH8HAAInAAMJfwqfIgC/AAAnAAMJfwqfIgC/AAAuAAQKfyMAAicACQlrElosANUBACcACQlrElosANUBAAAA.',
Vo='Voidbacon:BAAALgAECgQJBAAAAA==.Voidcore:BAABLgAECn8eAAIHAAkJ7xzGDwCFAgAHAAkJ7xzGDwCFAgAAAA==.',
Vv='Vv:BAAALgAECgUJBgAAAA==.',
Vy='Vyagra:BAAALgAECgcJBwAAAA==.Vyrinthial:BAAALgADCgUJBwAAAA==.Vyrnath:BAAALgAECgEJAQAAAA==.',
Wa='Walon:BAAALgADCgcJDgABLgAECggJCAAfAAAAAA==.Warfarmer:BAAALgAECgUJEQAAAA==.Warhawke:BAAALgADCgYJCAAAAA==.Warmack:BAAALgADCgIJAgAAAA==.',
We='Weak:BAAALgAECgYJDgAAAA==.Weakhand:BAAALgADCgIJAwAAAA==.Webs:BAAALgADCgUJBQAAAA==.Weel:BAACLgAFFH8IAAIHAAMJXhaOOwDrAAAHAAMJXhaOOwDrAAAuAAQKfygAAgcACQlGHAgbAC8CAAcACQlGHAgbAC8CAAAA.',
Wh='When:BAAALgADCgQJBAABLgAFFAQJCwAdAP0cAA==.Wheresdparty:BAAALgAECgEJAQAAAA==.Whilaanna:BAACLgAFFH8JAAIHAAUJqwxeMwALAQAHAAUJqwxeMwALAQAuAAQKfxYAAwcACAncHBQVAFkCAAcACAncHBQVAFkCAA0AAQlGBVUxAB4AAAAA.Whis:BAAALgAECgYJEwAAAA==.Whispernight:BAAALgADCgYJDQAAAA==.',
Wi='Widja:BAAALgADCgcJFwAAAA==.Wiilock:BAABLgAECn8dAAIZAAYJ4B4eRAD/AQAZAAYJ4B4eRAD/AQAAAA==.Wiivinelight:BAAALgAECgYJCgABLgAECgYJHQAZAOAeAA==.Wiivoker:BAAALgAECgUJBAABLgAECgYJHQAZAOAeAA==.Wildhus:BAAALgAECgUJBQAAAA==.Wildwhitwlkr:BAAALgADCgMJBQAAAA==.Wilfrid:BAAALgADCgIJAgABLgAFFAEJAQAfAAAAAA==.',
Wr='Wraithlord:BAAALgAECgYJBgAAAA==.',
['Wå']='Wåffle:BAAALgAFFAIJAgABLgAFFAQJBQATAKUZAA==.',
Xa='Xandari:BAAALgADCgkJDwAAAA==.Xania:BAAALgADCgYJBwAAAA==.Xannica:BAAALgAECgUJBQAAAA==.',
Xe='Xenzel:BAAALgAECgMJBQAAAA==.',
Xx='Xxbadwar:BAAALgADCgEJAQAAAA==.',
['Xû']='Xûrû:BAAALgAECgcJEAAAAA==.',
Yc='Yce:BAABLgAECn8aAAMiAAcJlxGVEQBlAQAiAAcJlxGVEQBlAQAhAAMJjA0rEgCeAAAAAA==.',
Yo='Yoker:BAAALgADCgYJCwAAAA==.Yokersen:BAAALgAECgUJBQAAAA==.',
Yr='Yrana:BAAALgAECgYJBgAAAA==.',
Za='Zaeladen:BAAALgAECgYJCwAAAA==.Zalorea:BAAALgAECgQJBgAAAA==.Zamorak:BAAALgAECgUJBQAAAA==.Zamrog:BAACLgAFFH8LAAIMAAQJzR7TAQBuAQAMAAQJzR7TAQBuAQAuAAQKfykAAgwACQndIN4AABEDAAwACQndIN4AABEDAAAA.Zamthyr:BAAALgAECgkJDwABLgAFFAQJCwAMAM0eAA==.Zanya:BAAALgAECgYJCwAAAA==.',
Ze='Zeiko:BAAALgAECgQJBAAAAA==.Zellah:BAAALgAECgcJEQAAAA==.Zenez:BAAALgAECgYJDAAAAA==.Zexor:BAAALgADCgYJDwAAAA==.Zeäl:BAAALgAECgEJAQAAAA==.',
Zh='Zhaoyun:BAABLgAECn8jAAIdAAgJHxerFQD7AQAdAAgJHxerFQD7AQAAAA==.',
Zi='Zilen:BAAALgADCgUJBQAAAA==.Zilkir:BAACLgAFFH8LAAMnAAMJFCSpFgAhAQAnAAMJFCSpFgAhAQADAAIJDCEATQC3AAAuAAQKfzAAAycACAkwI9gEAB8DACcACAkwI9gEAB8DAAMABwnfIO1HAAsCAAAA.Ziran:BAAALgAECgYJCAAAAA==.Zivadhim:BAAALgAECgQJAQAAAA==.',
Zk='Zkollkrusher:BAAALgADCgYJBgAAAA==.Zkullkrushur:BAAALgAECgUJBQAAAA==.Zkvllkrusher:BAAALgADCgEJAQAAAA==.',
Zl='Zlyth:BAAALgAECgQJCQAAAA==.',
Zo='Zohan:BAAALgAECgMJAwAAAA==.Zooie:BAABLgAECn8hAAMCAAkJkRZgMwC3AQACAAkJkRZgMwC3AQApAAgJyBQrHgCaAQAAAA==.Zould:BAABLgAECn8YAAIGAAYJZA5mjQAiAQAGAAYJZA5mjQAiAQAAAA==.',
Zy='Zyrix:BAAALgADCgQJBAAAAA==.',
['Àr']='Àrthàs:BAAALgAECgcJBwAAAA==.',
['Är']='Ärtrix:BAAALgADCgEJAQAAAA==.',
['Ät']='Ätrixx:BAAALgAECgYJCgAAAA==.',
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
