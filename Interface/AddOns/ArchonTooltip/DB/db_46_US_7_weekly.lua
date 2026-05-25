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

local lookup = {'DeathKnight-Unholy','Shaman-Restoration','Paladin-Retribution','Warlock-Affliction','Druid-Restoration','Druid-Balance','Druid-Guardian','Mage-Frost','DemonHunter-Devourer','Warrior-Fury','Paladin-Protection','Priest-Holy','Shaman-Enhancement','Hunter-BeastMastery','DemonHunter-Havoc','Rogue-Outlaw','DemonHunter-Vengeance','Rogue-Subtlety','Warrior-Arms','Warrior-Protection','DeathKnight-Frost','DeathKnight-Blood','Unknown-Unknown','Rogue-Assassination','Hunter-Survival','Hunter-Marksmanship','Priest-Discipline','Priest-Shadow','Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Monk-Mistweaver','Monk-Windwalker','Evoker-Devastation','Evoker-Preservation','Druid-Feral','Mage-Fire','Monk-Brewmaster','Mage-Arcane','Shaman-Elemental',}
local provider = {region='US',realm='Alleria',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aantoc:BAAALgADCgUJBQAAAA==.',
Ab='Abrut:BAAALgADCgMJAwAAAA==.',
Ad='Adramalech:BAAALgAECgIJAwABLgAFFAYJFQABADkfAA==.',
Ae='Aeakos:BAAALgADCgQJBQABLgAECgkJIQACAJAWAA==.Aelan:BAAALgADCgQJBAAAAA==.Aeryana:BAAALgADCgYJCAAAAA==.',
Ag='Agapitus:BAAALgADCgIJAgAAAA==.',
Ai='Ailuridae:BAAALgADCgcJEwAAAA==.Aimbot:BAAALgADCgkJEAAAAA==.Aisele:BAAALgAECgYJEwAAAA==.',
Al='Alathir:BAAALgAECgcJDQAAAA==.Alenton:BAAALgAECgQJBQAAAA==.Alessia:BAAALgADCgMJBAAAAA==.Alluri:BAABLgAECn8kAAIDAAkJxxl2TgC+AQADAAkJxxl2TgC+AQAAAA==.Alone:BAABLgAECn8UAAIEAAcJTxApDABjAQAEAAcJTxApDABjAQAAAA==.Althemia:BAAALgAECgQJBQAAAA==.Alunamora:BAABLgAECn8wAAIFAAkJjBr6DgC+AgAFAAkJjBr6DgC+AgAAAA==.Alwind:BAABLgAECn8eAAMGAAgJdBCxJAB3AQAGAAgJdBCxJAB3AQAHAAEJ7AadYQAWAAAAAA==.',
Am='Ambient:BAABLgAECn8nAAIIAAcJYhAIfgBfAQAIAAcJYhAIfgBfAQAAAA==.Ambientdk:BAAALgAECgYJBgAAAA==.Amboosted:BAABLgAECn81AAIDAAgJfR4eLAAuAgADAAgJfR4eLAAuAgAAAA==.Ameretat:BAECLgAFFH8JAAIJAAIJOBvgWgCiAAAJAAIJOBvgWgCiAAAuAAQKfxYAAgkABwk/Hf0rAPkBAAkABwk/Hf0rAPkBAAEuAAUUBAkSAAoAVB4A.',
An='Analani:BAAALgAECgUJCwAAAA==.Anali:BAABLgAECn8VAAILAAgJkAJaKQChAAALAAgJkAJaKQChAAAAAA==.Ancient:BAAALgAECgcJCAABLgAFFAQJCQAIAOgZAA==.Ancksunamun:BAAALgAECgIJAgAAAA==.Angerr:BAAALgAECgYJEgAAAA==.Angryheals:BAABLgAECn8VAAIMAAgJKSDUBwDNAgAMAAgJKSDUBwDNAgAAAA==.Anhri:BAAALgAECgEJAQAAAA==.Animalator:BAAALgAECgEJAQAAAA==.',
Ao='Aoi:BAAALgAECgEJAQAAAA==.',
Aq='Aquamann:BAAALgADCgMJBAAAAA==.',
Ar='Aranel:BAAALgAECgcJEQAAAA==.Aratiri:BAAALgADCgUJBQAAAA==.Arcamancer:BAAALgADCggJFwAAAA==.Arcannia:BAAALgADCgEJAQAAAA==.Arek:BAAALgAECgYJBwABLgAFFAYJFgANAA0hAA==.Arinthal:BAABLgAECn8dAAIOAAcJEQ6OZgBJAQAOAAcJEQ6OZgBJAQAAAA==.Arril:BAABLgAECn8cAAIIAAcJchARggBXAQAIAAcJchARggBXAQAAAA==.Artemissy:BAAALgADCgUJDQAAAA==.Artorias:BAAALgAECgEJAgAAAA==.',
As='Ashed:BAAALgAECgcJDQAAAA==.Ashenskye:BAAALgADCgUJBQAAAA==.Ashlieghee:BAAALgAECgYJEAAAAA==.Ashou:BAAALgADCgMJAwAAAA==.Ashtari:BAAALgADCgEJAQAAAA==.Ashuraa:BAAALgAECgQJBQAAAA==.Astien:BAABLgAECn8ZAAIDAAYJDxSzhwA/AQADAAYJDxSzhwA/AQAAAA==.Astra:BAAALgADCgMJAwAAAA==.',
Au='Aureille:BAAALgADCgEJAgAAAA==.Aurien:BAAALgADCgMJAwAAAA==.Autoaim:BAAALgAECgYJDwAAAA==.',
Av='Avelen:BAAALgAFFAIJAgAAAA==.Avha:BAAALgAECgUJCwAAAA==.Avistero:BAAALgAECgYJCwAAAA==.Avië:BAABLgAECn8XAAIIAAYJOBaWnACcAQAIAAYJOBaWnACcAQAAAA==.',
Ax='Axel:BAACLgAFFH8JAAIJAAMJ3g3dTQDQAAAJAAMJ3g3dTQDQAAAuAAQKfyAAAgkABwnSFWBaAJIBAAkABwnSFWBaAJIBAAAA.',
Ay='Aylden:BAABLgAECn8wAAMPAAgJFhzlDQARAgAPAAgJFhzlDQARAgAJAAUJmAl1qwCgAAAAAA==.',
Az='Azenezith:BAAALgAECgQJBAAAAA==.Azio:BAAALgAECgYJDAAAAA==.Azriah:BAAALgADCggJDwAAAA==.',
Ba='Bailas:BAAALgAECgMJBAAAAA==.Bananabear:BAABLgAECn8VAAIHAAgJiiWGAQA+AwAHAAgJiiWGAQA+AwABLgAFFAQJCwAQAJIeAA==.Barbiesresto:BAAALgADCgUJBQAAAA==.Bargs:BAAALgADCgMJAwAAAA==.Barra:BAAALgAECgQJBwAAAA==.Bashshield:BAEALgAFFAEJAQAAAA==.Battousai:BAAALgAECgEJAQAAAA==.',
Bb='Bb:BAAALgAECgcJEQAAAA==.',
Be='Bearjax:BAAALgAECgYJCAABLgAFFAMJDgARAOIjAA==.Beastm:BAAALgADCgQJBAAAAA==.Beathed:BAAALgAECgQJBQAAAA==.Beaver:BAAALgADCgIJAgAAAA==.Belanova:BAAALgAECgYJBwAAAA==.Belencina:BAAALgAECgYJBgAAAA==.Beleynn:BAABLgAECn8dAAISAAgJQwgXIgBWAQASAAgJQwgXIgBWAQAAAA==.Belwyn:BAAALgADCgMJAwAAAA==.Benjofamin:BAAALgAECgcJEAAAAA==.',
Bi='Bigheelz:BAAALgAECgUJBgAAAA==.Bigpuffer:BAAALgADCgMJBAAAAA==.Billmegatron:BAAALgAECgEJAQAAAA==.Bitesize:BAECLgAFFH8SAAMKAAQJVB6VEABQAQAKAAQJahmVEABQAQATAAEJ6RqvCgBYAAAuAAQKfygABBMACQmdJCEMAN8BAAoABgluJEwjADsCABMABQlbJSEMAN8BABQAAgklEfA6AHQAAAAA.',
Bl='Blashster:BAABLgAFFH8FAAIIAAIJVwnVhwCVAAAIAAIJVwnVhwCVAAAAAA==.Blueprime:BAAALgADCgYJBgAAAA==.',
Bo='Boaw:BAAALgAECgMJBgAAAA==.Bonemilker:BAACLgAFFH8VAAQBAAYJOR+lIQCMAQABAAUJZRylIQCMAQAVAAQJxR4nCgAOAQAWAAEJAACHNgAAAAAuAAQKfzoAAxUACAlhJm8AAGwDABUACAk/Jm8AAGwDAAEACAn/JS8IAF4DAAAA.Boosieboose:BAAALgAECgYJCAAAAA==.Boostymans:BAAALgADCgYJBgAAAA==.',
Br='Brackz:BAACLgAFFH8KAAIFAAQJdgtVKAD6AAAFAAQJdgtVKAD6AAAuAAQKfx0AAgUACQmhFqsXAGcCAAUACQmhFqsXAGcCAAAA.Brandt:BAAALgADCgEJAgAAAA==.Brannwynn:BAAALgADCgEJAQAAAA==.Breelyssa:BAAALgAECgcJBwAAAA==.Brewtangclan:BAAALgAECgYJEwAAAA==.Brighter:BAAALgAECgYJBwAAAA==.Broncopally:BAAALgAECgEJAQAAAA==.Brother:BAAALgADCgEJAQABLgAECggJKgAIAHIaAA==.Brozai:BAAALgAECgQJCAABLgAFFAQJBAAXAAAAAA==.Brutalbandit:BAAALgADCgUJBQAAAA==.Bryaan:BAABLgAFFH8FAAIDAAUJwARwVADYAAADAAUJwARwVADYAAAAAA==.Brynne:BAAALgADCgEJAQAAAA==.',
Bu='Bullitproof:BAAALgADCgcJDgABLgAECggJMQADANkJAA==.Bulroc:BAAALgADCgEJAQAAAA==.Bunnkost:BAAALgADCgkJGQAAAA==.Bunnyparade:BAAALgAECgMJBQAAAA==.',
Ca='Caiden:BAAALgAECgMJAwAAAA==.Calari:BAAALgAECgQJBwAAAA==.Caledwar:BAABLgAECn8hAAIDAAYJTRe9cwBnAQADAAYJTRe9cwBnAQAAAA==.Calthirstrap:BAABLgAFFH8OAAIBAAQJZhgVOwBNAQABAAQJZhgVOwBNAQABLgAECgkJFwAIAGIYAA==.Camvoker:BAAALgADCgEJAQAAAA==.Carapace:BAABLgAECn82AAIKAAgJvw+QKwCAAQAKAAgJvw+QKwCAAQAAAA==.Carare:BAAALgAECgQJBQAAAA==.Catomaze:BAAALgAECgEJAQAAAA==.',
Ce='Ceefack:BAAALgAECgQJDAAAAA==.Celbrooke:BAAALgAECgQJBAAAAA==.Celebsteele:BAAALgADCgYJBwAAAA==.Celestialsky:BAAALgAECgkJAQAAAA==.Celicel:BAAALgADCgcJBwAAAA==.Cena:BAABLgAECn8kAAMYAAcJIQvnDAA7AQASAAYJ/AjJOgBCAQAYAAcJHwvnDAA7AQAAAA==.Cethin:BAAALgAECgYJEwAAAA==.',
Ch='Chaosform:BAAALgAECgYJBgABLgAFFAQJDgAZAGoiAA==.Chaosshot:BAACLgAFFH8OAAMZAAQJaiKRBQCIAQAZAAQJaiKRBQCIAQAaAAEJRCE7IwBlAAAuAAQKfyYAAxoACAlNJDQGADkDABoACAlNJDQGADkDABkAAQnmJeZFAHAAAAAA.Cherylindrea:BAAALgAECgEJAQAAAA==.Chronic:BAABLgAECn8ZAAIDAAgJ9A8OcgBqAQADAAgJ9A8OcgBqAQAAAA==.Chènch:BAAALgADCgEJAQABLgAECgcJGQAbACMMAA==.',
Ci='Cindera:BAAALgAECgMJAwAAAA==.',
Cl='Claydemon:BAABLgAECn8VAAIPAAgJ0RKSGwBmAQAPAAgJ0RKSGwBmAQAAAA==.Clayman:BAAALgAECgYJDAAAAA==.Claytraps:BAAALgADCgkJJQAAAA==.Clayvicar:BAACLgAFFH8LAAMMAAQJMAaTFQDoAAAMAAQJMAaTFQDoAAAcAAEJYgDxFwA3AAAuAAQKfyoAAwwACAkOE6ghANYBAAwACAkOE6ghANYBABwAAwlgA59XAGAAAAAA.',
Co='Coconutty:BAABLgAECn8YAAMdAAcJcRdFHgDpAQAdAAcJcRdFHgDpAQADAAYJKAu+rgD/AAAAAA==.Coridane:BAABLgAECn8cAAIMAAgJKBUaGwDIAQAMAAgJKBUaGwDIAQAAAA==.Corrum:BAAALgADCgIJAgAAAA==.Corwinfiron:BAAALgAECggJEgAAAA==.Cotreyy:BAACLgAFFH8RAAMeAAQJniUsBgC+AQAeAAQJniUsBgC+AQAfAAEJIyUBEABqAAAuAAQKfycABB4ACAlKJhYRAPICAB4ABwnkJRYRAPICAAQABQk4JvcEACMCAB8ABAkRIhwXAJEBAAAA.Covah:BAAALgADCgIJAgAAAA==.',
Cr='Cristen:BAAALgADCgYJCQAAAA==.Crobat:BAAALgAECgYJCQAAAA==.',
Cu='Cumgar:BAABLgAECn8gAAIeAAgJlBHGWAC9AQAeAAgJlBHGWAC9AQAAAA==.Curkage:BAAALgAECgYJBQAAAA==.',
Cy='Cythera:BAACLgAFFH8WAAINAAYJDSFUAQC2AQANAAYJDSFUAQC2AQAuAAQKfx4AAg0ACQkcJFoEANgCAA0ACQkcJFoEANgCAAAA.',
['Cá']='Cámus:BAABLgAECn8dAAIDAAYJ3RoJiAA/AQADAAYJ3RoJiAA/AQAAAA==.',
['Cö']='Cöffee:BAAALgAECgUJEAAAAA==.',
Da='Daammy:BAAALgAECgQJBQAAAA==.Dagran:BAAALgAECgQJCQABLgAECgcJFwAJALwfAA==.Dagren:BAAALgAECgYJCQAAAA==.Dankfrost:BAAALgADCgcJEgAAAA==.Daphine:BAAALgADCgkJHAAAAA==.Darimonk:BAAALgADCggJDQAAAA==.Darkbeautie:BAABLgAECn8eAAISAAYJ4wPXNADOAAASAAYJ4wPXNADOAAAAAA==.Darkcarbon:BAABLgAECn8lAAIJAAcJ3g2JagApAQAJAAcJ3g2JagApAQAAAA==.Darmin:BAAALgAECgIJAgAAAA==.',
De='Deadpool:BAAALgAECgYJCwABLgAECgUJBQAXAAAAAA==.Deathmask:BAAALgADCgEJAQAAAA==.Deathonyou:BAAALgAECgkJAgAAAA==.Deepdarkdank:BAAALgADCgEJAQAAAA==.Deepmoanpaw:BAAALgAECgYJCQAAAA==.Deevoyd:BAAALgADCgEJAQAAAA==.Defnotash:BAACLgAFFH8KAAILAAQJJgwFBwDcAAALAAQJJgwFBwDcAAAuAAQKfy4AAgsACQlXILsBADIDAAsACQlXILsBADIDAAAA.Dellinair:BAAALgADCgEJAQAAAA==.Dementedlock:BAAALgAECgcJEQAAAA==.Demily:BAAALgAECgQJBAABLgAFFAQJCAAgAHMQAA==.Demontacos:BAAALgAECggJEQAAAA==.Derodd:BAAALgAECgQJBQAAAA==.Desolend:BAAALgADCgIJAgAAAA==.Dewkiez:BAEALgAFFAIJBAAAAA==.',
Di='Diabolicarl:BAABLgAECn8vAAIPAAkJ5RW6DQAUAgAPAAkJ5RW6DQAUAgAAAA==.Dibsy:BAACLgAFFH8MAAMhAAUJiRExFwBFAQAhAAUJiRExFwBFAQAiAAIJ7RXBIQCWAAAuAAQKfzsAAyIACQnFIXwEAPACACIACQnFIXwEAPACACEABgnOHsAZAAsCAAAA.Diri:BAAALgADCgcJBwABLgAECgkJIQASADQVAA==.Dis:BAAALgAECgIJAgABLgAFFAQJDwAFAPsJAA==.Disgrace:BAABLgAECn80AAIUAAkJGg2MFACBAQAUAAkJGg2MFACBAQAAAA==.Dividane:BAAALgADCgYJBgAAAA==.',
Dm='Dmossyoak:BAAALgADCgkJAgAAAA==.',
Do='Donniedipes:BAABLgAECn8pAAIBAAkJShAaRgDNAQABAAkJShAaRgDNAQAAAA==.Dookiez:BAEBLgAECn8ZAAINAAgJnSNoAgAmAwANAAgJnSNoAgAmAwABLgAFFAIJBAAXAAAAAA==.Doublade:BAAALgAECgcJBwAAAA==.Doubledragin:BAABLgAECn8sAAMgAAgJoBvXEwAeAgAgAAgJoBvXEwAeAgAjAAMJ6gKVNgBiAAAAAA==.',
Dr='Dracantar:BAAALgADCgUJBQAAAA==.Dracotako:BAAALgAECgYJDQAAAA==.Dractini:BAACLgAFFH8QAAMgAAQJsxmJGABHAQAgAAQJsxmJGABHAQAkAAQJrwfRFgD0AAAuAAQKfxwAAyQACQk7CsckAFIBACQABwlcC8ckAFIBACAACAnfEJM9AAwBAAEuAAUUCQkvAAwAxhEA.Draeneiamin:BAAALgADCgMJAwABLgAECgcJEAAXAAAAAA==.Dragfan:BAAALgAECgcJDgAAAA==.Dragonsniper:BAAALgAECgYJCgAAAA==.Dragore:BAABLgAECn8ZAAIKAAYJthu2NwDIAQAKAAYJthu2NwDIAQAAAA==.Druidgirls:BAACLgAFFH8IAAIFAAMJPxE8MgDHAAAFAAMJPxE8MgDHAAAuAAQKfzEAAgUACQndGI0eAC4CAAUACQndGI0eAC4CAAAA.Dràugluin:BAAALgAFFAEJAQAAAA==.',
Du='Duasoras:BAABLgAECn8fAAICAAgJ9gTfaADoAAACAAgJ9gTfaADoAAAAAA==.Duelist:BAAALgADCgUJBQAAAA==.Dundlen:BAAALgADCggJDwABLgAFFAIJCAAIAGMSAA==.Dunvel:BAAALgAECgMJAwAAAA==.Durogdem:BAAALgAECgIJBAAAAA==.',
Dy='Dynamite:BAAALgAECgEJBAAAAA==.',
Ea='Earthaggie:BAAALgAECgEJAQAAAA==.',
Ed='Edea:BAAALgAECgEJAQAAAA==.Ederon:BAAALgAECgUJAQAAAA==.',
El='Elaelta:BAAALgAECgMJCQAAAA==.Eleetmage:BAAALgAECgEJAQAAAA==.Elenora:BAABLgAECn8+AAIGAAkJ2QQSNwAHAQAGAAkJ2QQSNwAHAQAAAA==.Elesity:BAAALgADCgEJAQABLgAFFAYJGAAXAAAAAA==.Elye:BAAALgAECgMJAwABLgAECgYJEwAXAAAAAA==.',
Em='Emer:BAACLgAFFH8PAAMFAAQJ+wnDRACCAAAFAAMJmQHDRACCAAAGAAQJOAETNQBoAAAuAAQKfzAAAwYACAmNDXozABoBAAYABwmGD3ozABoBAAUABwnWBvyGAIgAAAAA.',
En='Encore:BAACLgAFFH8MAAIFAAMJvAReOwClAAAFAAMJvAReOwClAAAuAAQKf0AAAgUACQm7ELoqAN4BAAUACQm7ELoqAN4BAAAA.',
Eo='Eousphorus:BAACLgAFFH8SAAIIAAUJuRhCQwA/AQAIAAUJuRhCQwA/AQAuAAQKfyoAAggACAmjIPQrAEwCAAgACAmjIPQrAEwCAAAA.',
Er='Erathen:BAAALgAECgUJBAAAAA==.Eridi:BAAALgADCgEJAQAAAA==.Eroenice:BAAALgAECgQJBAAAAA==.',
Et='Etile:BAAALgADCgkJFgAAAA==.',
Ev='Evelleion:BAABLgAECn8bAAMOAAgJJBLaRACnAQAOAAgJzBDaRACnAQAaAAQJDhFMWgDbAAAAAA==.',
Ex='Exoticlord:BAABLgAECn8eAAMOAAgJyRlgNADhAQAOAAgJyRlgNADhAQAaAAYJ6BDkQQBQAQAAAA==.',
Fa='Failagos:BAAALgADCgMJAwAAAA==.Failas:BAAALgAECgUJBQAAAA==.Fallujah:BAAALgADCgUJBQAAAA==.',
Fe='Felicene:BAABLgAECn81AAIlAAkJdCWLAABqAwAlAAkJdCWLAABqAwAAAA==.Fellynn:BAACLgAFFH8OAAIRAAMJ4iOUAgA3AQARAAMJ4iOUAgA3AQAuAAQKfygAAhEACAmjJZ8AAFsDABEACAmjJZ8AAFsDAAAA.',
Fi='Fieperskaivu:BAABLgAECn8XAAMJAAcJvB8SIgCFAgAJAAcJvB8SIgCFAgAPAAUJMRqnNQAxAQAAAA==.Fierygrace:BAAALgADCgYJBgAAAA==.Firefalco:BAAALgADCggJCQAAAA==.',
Fl='Flameth:BAACLgAFFH8MAAIeAAMJ2QHQdQCiAAAeAAMJ2QHQdQCiAAAuAAQKfx0AAh4ACAkzDX10ADsBAB4ACAkzDX10ADsBAAAA.Flamingbunz:BAAALgAECgIJAgAAAA==.Flashblood:BAACLgAFFH8MAAIKAAQJmSOFDABrAQAKAAQJmSOFDABrAQAuAAQKfzAAAwoACQkEJa0DABUDAAoACQkEJa0DABUDABMAAwnxIosYADQBAAAA.Flashers:BAAALgAECggJBwABLgAECggJHgAGAOIiAA==.Flavortown:BAAALgAECgUJBgAAAA==.',
Fo='Forgiven:BAABLgAECn8VAAIDAAcJqBrIVADjAQADAAcJqBrIVADjAQAAAA==.Foxtrót:BAABLgAECn8aAAIOAAcJhA/4XgBcAQAOAAcJhA/4XgBcAQABLgAECgkJMQAUAIokAA==.',
Fr='Freeb:BAAALgAECgYJCwABLgAECggJMQADANkJAA==.Freebzz:BAAALgADCgQJBwABLgAECggJMQADANkJAA==.Freezrorburn:BAAALgAECgYJDwAAAA==.Frostyndikit:BAAALgAECgMJAwAAAA==.',
Fu='Fu:BAAALgADCgUJBQAAAA==.Fumanchu:BAABLgAECn8xAAIUAAkJiiQ3AQBEAwAUAAkJiiQ3AQBEAwAAAA==.',
Ga='Gaamora:BAAALgAECgEJAQAAAA==.Gainsborough:BAAALgAECggJCQAAAA==.Galadore:BAAALgADCgIJAwAAAA==.Garagos:BAACLgAFFH8PAAIYAAQJyxOfAwBQAQAYAAQJyxOfAwBQAQAuAAQKfyoAAhgACAmZHSkEAHECABgACAmZHSkEAHECAAAA.Gargisa:BAAALgAECgEJAQAAAA==.Gatherina:BAAALgAECgQJBgABLgAECgcJFwAJALwfAA==.',
Ge='Gebuss:BAACLgAFFH8FAAIYAAQJpRkBAwBiAQAYAAQJpRkBAwBiAQAuAAQKfx4AAhgACQlNJa8CAMECABgACQlNJa8CAMECAAAA.Gempally:BAAALgADCgMJBgAAAA==.Genzo:BAAALgAECgUJCwAAAA==.',
Gh='Ghorynv:BAAALgAECgYJBgAAAA==.',
Gi='Giah:BAAALgAECgYJDgAAAA==.Giborim:BAAALgADCgEJAQAAAA==.Gigapriest:BAAALgAECgYJBgAAAA==.',
Gl='Glavela:BAABLgAECn8UAAIIAAYJIB1iZQCWAQAIAAYJIB1iZQCWAQAAAA==.Gloomfist:BAAALgAECgYJEwAAAQ==.',
Go='Goochaddi:BAAALgADCgMJAwABLgAECgUJBQAXAAAAAA==.Gozer:BAAALgADCgcJBwAAAA==.',
Gr='Graven:BAABLgAECn8UAAIiAAkJHRXxEAAaAgAiAAkJHRXxEAAaAgAAAA==.Graveside:BAAALgAECgEJAQAAAA==.Grizzlock:BAAALgADCgMJAwAAAA==.',
Gu='Gulivar:BAABLgAECn8ZAAIbAAcJIwykKQBXAQAbAAcJIwykKQBXAQAAAA==.Gunnerrata:BAAALgAECgYJDQAAAA==.',
Ha='Halfrican:BAAALgAECgQJBAAAAA==.Halifaxx:BAACLgAFFH8IAAMIAAIJYxJVfQCkAAAIAAIJYxJVfQCkAAAmAAEJNQEBBABBAAAuAAQKfy8AAyYACAlOH3ACAPsBAAgACAlhGgU2ACMCACYACAmTHHACAPsBAAAA.Happygilmore:BAAALgAECgQJCAAAAA==.Harambee:BAAALgAECgEJAQABLgAECggJFwAiAOEfAA==.Hariasa:BAAALgAECgMJAwAAAA==.Harlyquin:BAAALgAECgkJAgAAAA==.Harmaa:BAABLgAECn8VAAIBAAgJJARgqQD1AAABAAgJJARgqQD1AAAAAA==.Hawknor:BAABLgAECn8XAAMWAAcJOB4bEADZAQAWAAcJOB4bEADZAQABAAMJ2ggICQFjAAAAAA==.',
He='Headpool:BAAALgAECgUJEAABLgAECgUJBQAXAAAAAA==.Healenya:BAAALgAECgcJBwAAAA==.Healthcare:BAAALgAECgcJDwABLgAFFAkJLwAMAMYRAA==.Healywilly:BAAALgADCggJGQAAAA==.Herm:BAACLgAFFH8IAAIiAAMJ8yQKDAA7AQAiAAMJ8yQKDAA7AQAuAAQKfycAAiIACAlGI5IHAAMDACIACAlGI5IHAAMDAAAA.',
Hi='Highbear:BAABLgAECn8UAAIFAAYJPxnkMwCpAQAFAAYJPxnkMwCpAQAAAA==.Hiryu:BAAALgADCgYJBgAAAA==.',
Ho='Holyfaxx:BAAALgAECgYJBwABLgAFFAIJCAAIAGMSAA==.Holymidget:BAAALgAECgMJAwAAAA==.Holysky:BAABLgAECn8bAAMdAAYJUiHGFgAsAgAdAAYJUiHGFgAsAgALAAUJ3wozLACQAAAAAA==.Holysmokes:BAAALgAECgUJBwAAAA==.Holytim:BAABLgAECn8oAAQbAAgJHBiRKgBRAQAbAAgJexaRKgBRAQAcAAcJrw3KMgAmAQAMAAYJ4xDLRAAmAQAAAA==.Honnik:BAACLgAFFH8PAAIYAAQJXAsoBAA9AQAYAAQJXAsoBAA9AQAuAAQKfygAAhgACQnEGGsEACUCABgACQnEGGsEACUCAAAA.Hortance:BAAALgAECgkJBwAAAA==.Hothot:BAAALgAECgQJBQAAAA==.Hotsndots:BAAALgAECgEJAQAAAA==.Houndoom:BAABLgAECn8xAAInAAkJdhcjEgAGAgAnAAkJdhcjEgAGAgAAAA==.How:BAACLgAFFH8PAAIhAAQJ7h6tFABiAQAhAAQJ7h6tFABiAQAuAAQKfxwAAyEACAkMHbcNAHkCACEACAkMHbcNAHkCACIAAQkHCBKBAC8AAAAA.',
Hu='Hugspotato:BAABLgAFFH8IAAIgAAQJcxAqIwAQAQAgAAQJcxAqIwAQAQAAAA==.Huyrak:BAAALgADCgUJBQAAAA==.',
Hy='Hypoxic:BAAALgAECgYJEAAAAA==.',
Ia='Iah:BAACLgAFFH8IAAINAAMJkQGtCwCdAAANAAMJkQGtCwCdAAAuAAQKfyIAAg0ACAmaCuoPALkBAA0ACAmaCuoPALkBAAAA.',
Ic='Icastspells:BAAALgAECgYJCgAAAA==.Icritmepants:BAAALgAECgMJAwAAAA==.Icyveinuser:BAAALgADCgcJKAAAAA==.',
Ig='Ignored:BAABLgAECn8uAAMDAAgJ1R7ZIgBbAgADAAgJ1R7ZIgBbAgAdAAEJoAFZjwAVAAAAAA==.',
Il='Illidæn:BAABLgAECn8bAAIJAAkJGREMRQCWAQAJAAkJGREMRQCWAQAAAA==.Illistra:BAAALgADCgYJBgABLgAECgcJDQAXAAAAAA==.',
Im='Imperîus:BAAALgAECgMJAwABLgAFFAYJFQABADkfAA==.Impuratus:BAAALgAFFAEJAQAAAA==.',
In='Inq:BAABLgAECn8kAAIIAAkJeiDTDAD7AgAIAAkJeiDTDAD7AgAAAA==.',
Ir='Iridaceaë:BAABLgAECn81AAMMAAkJnhw+CADEAgAMAAkJnhw+CADEAgAbAAMJHgiqRQCMAAABLgAECgkJLAAhAG8hAA==.Ironpaw:BAABLgAECn8UAAIiAAYJShANNgD/AAAiAAYJShANNgD/AAAAAA==.Iryris:BAABLgAECn8rAAIGAAgJiAdNNQARAQAGAAgJiAdNNQARAQAAAA==.',
Is='Isedeath:BAACLgAFFH8PAAQVAAQJyQ5gDgDKAAABAAMJGBAAeQDfAAAVAAMJjAhgDgDKAAAWAAEJPwnKLQA5AAAuAAQKfzcABAEACAkgHqEwAHUCAAEACAlfHKEwAHUCABUABwnUGgcIAMkBABYAAwmvEbI6AHcAAAAA.',
Ja='Jabber:BAAALgAECgYJDQABLgAECggJGQADAPQPAA==.Jabul:BAAALgADCgYJBgAAAA==.Jack:BAABLgAECn8kAAMeAAkJwSFKGAB5AgAeAAcJPiFKGAB5AgAfAAIJWSX+JABoAAAAAA==.Jaegerr:BAABLgAECn8PAAIcAAkJzQkxNwAQAQAcAAkJzQkxNwAQAQAAAA==.Jaing:BAAALgADCgEJAQAAAA==.Jalene:BAAALgADCgcJAwAAAA==.Jamonk:BAAALgADCgYJBwABLgADCggJCAAXAAAAAA==.Jamuul:BAAALgADCggJCAAAAA==.Janton:BAABLgAECn8gAAIKAAkJgQl3KwCBAQAKAAkJgQl3KwCBAQAAAA==.Jarrhead:BAAALgAECgYJEwAAAA==.Jastor:BAAALgADCgcJDgAAAA==.Jaxirl:BAAALgAECgUJBQAAAA==.',
Je='Jenaveive:BAAALgAECgQJBAABLgAECggJGQAcAOcIAA==.Jethli:BAACLgAFFH8bAAInAAYJRxGCEABkAQAnAAYJRxGCEABkAQAuAAQKfygAAicACQlVGlMMAFECACcACQlVGlMMAFECAAAA.Jez:BAAALgADCgQJBAAAAA==.',
Ji='Jigopocalyps:BAAALgADCgEJAQAAAA==.Jinn:BAAALgADCgYJBAAAAA==.Jinra:BAAALgADCgEJAQAAAA==.',
Jj='Jjp:BAAALgADCgYJCQAAAA==.',
Jn='Jnex:BAAALgAECgEJAQAAAA==.',
Jo='Joube:BAAALgAECggJEwAAAA==.',
Ju='Judgepain:BAAALgAECgEJBQAAAA==.Judgmental:BAABLgAECn8fAAMdAAgJvxWgGgAIAgAdAAgJvxWgGgAIAgADAAYJaQKnAwGCAAAAAA==.Juicybutt:BAAALgADCgYJBgABLgAFFAkJLwAMAMYRAA==.Juicytootsie:BAABLgAECn8UAAIIAAYJdwN4BwHtAAAIAAYJdwN4BwHtAAAAAA==.Julibella:BAAALgAECgEJAQAAAA==.Justifried:BAAALgAECgQJBAAAAA==.',
['Jä']='Jävel:BAAALgAECgYJEwAAAA==.',
Ka='Kaelysong:BAAALgAECgMJBAAAAA==.Kairah:BAAALgAECgYJCgAAAA==.Kairiandel:BAAALgAECgIJAgAAAA==.Kaivig:BAAALgAECgEJAQAAAA==.Kalï:BAABLgAECn8kAAIOAAkJ9x5UCwDWAgAOAAkJ9x5UCwDWAgAAAA==.Karaha:BAAALgADCgcJBwAAAA==.Karukan:BAAALgAECgEJAQAAAA==.Kayllin:BAAALgAECgQJBgAAAA==.Kaysina:BAAALgADCgUJBQAAAA==.Kazarahu:BAAALgAECgEJAQAAAA==.Kazbea:BAAALgADCgcJBwAAAA==.',
Ke='Keener:BAABLgAECn8XAAMKAAcJqyAOJACvAQAKAAYJhiEOJACvAQAUAAMJyhdnOQB/AAAAAA==.Kelenil:BAAALgAECgEJAQABLgAECgYJBgAXAAAAAA==.Kerrla:BAACLgAFFH8aAAIGAAYJSRdtCwCNAQAGAAYJSRdtCwCNAQAuAAQKfycAAgYACAkAJJ8JAPsCAAYACAkAJJ8JAPsCAAEuAAMKAwkDABcAAAAA.Keylleth:BAABLgAECn8YAAMFAAcJ4A3uSQBEAQAFAAcJ4A3uSQBEAQAGAAIJOQZcawBIAAAAAA==.',
Kh='Khalanie:BAAALgAECgYJCgAAAA==.Khamari:BAAALgADCgYJBgABLgAECgYJEAAXAAAAAA==.Khamnox:BAAALgAECgYJEAAAAA==.Khlamps:BAAALgAECgMJAwAAAA==.',
Ki='Kielnmsoftly:BAABLgAECn8gAAIBAAkJbxbQLgAgAgABAAkJbxbQLgAgAgAAAA==.Kilaia:BAABLgAECn8aAAIOAAYJFBE9cwArAQAOAAYJFBE9cwArAQAAAA==.Kilda:BAAALgADCgcJBwAAAA==.Killerklown:BAAALgAECgUJCAAAAA==.Kirksñiper:BAAALgAECgYJDgAAAA==.Kirru:BAABLgAECn8lAAQMAAkJLw1JKQBYAQAMAAgJFA5JKQBYAQAcAAQJcgMyVQCFAAAbAAMJXAG/TQBbAAAAAA==.Kirsty:BAAALgADCgMJAwAAAA==.',
Kl='Klink:BAAALgAECgUJDwABLgAECgcJGQAbACMMAA==.',
Kn='Knoble:BAABLgAECn8WAAQKAAgJhR7fEgA5AgAKAAgJNB7fEgA5AgATAAMJuQ8gQwCEAAAUAAEJHB/kPABWAAAAAA==.',
Kr='Kraisee:BAAALgADCgEJAQAAAA==.Kreatan:BAAALgADCgUJBwAAAA==.Kreaton:BAABLgAECn8UAAICAAkJhAW2dQDAAAACAAkJhAW2dQDAAAAAAA==.Krel:BAAALgAECgEJAQAAAA==.Kryntoo:BAAALgADCggJCAAAAA==.Kryptic:BAAALgAECgcJBgAAAA==.Kryptix:BAAALgADCgYJCAAAAA==.',
Ks='Kshatriya:BAAALgADCgQJBAAAAA==.',
Ku='Kuchikix:BAAALgAECgEJAQAAAA==.Kuchíki:BAABLgAECn8ZAAIhAAcJNA5+PwAXAQAhAAcJNA5+PwAXAQAAAA==.Kushynuggles:BAAALgADCgEJAQAAAA==.',
Kw='Kwag:BAAALgAECgcJBgAAAA==.',
La='Laaklem:BAAALgAECgUJBQAAAA==.Laei:BAAALgAECggJEAAAAA==.Lagerthaa:BAAALgADCgIJAgAAAA==.Laserfingies:BAAALgAECgUJBwAAAA==.Lastsun:BAABLgAECn8VAAIIAAcJmQ1wjABCAQAIAAcJmQ1wjABCAQAAAA==.Lauridana:BAAALgADCgEJAQAAAA==.Lavacakes:BAACLgAFFH8PAAICAAQJnyaeCwDGAQACAAQJnyaeCwDGAQAuAAQKfy4AAgIACAnZJL8DADoDAAIACAnZJL8DADoDAAAA.Lazaren:BAAALgADCgMJAwAAAA==.Lazyboy:BAABLgAECn8ZAAIKAAcJpR4BHABtAgAKAAcJpR4BHABtAgAAAA==.',
Le='Lelantoz:BAABLgAECn8lAAIOAAYJuAnoZQA2AQAOAAYJuAnoZQA2AQAAAA==.Leliel:BAAALgADCgEJAQAAAA==.Lenailla:BAAALgADCgkJCQAAAA==.Lezibean:BAAALgAECgIJAgABLgAFFAQJCAAgAHMQAA==.',
Li='Lidan:BAABLgAECn8jAAIYAAkJ8g/HBgDUAQAYAAkJ8g/HBgDUAQAAAA==.Liebli:BAAALgAECgQJBAAAAA==.Liffry:BAAALgADCgEJAQAAAA==.Lilena:BAAALgADCgkJLQAAAA==.Lilnao:BAAALgAECgcJCAAAAA==.Linaeni:BAAALgAECgQJBAAAAA==.Linaradice:BAAALgAECggJEgAAAA==.Linkinbiox:BAAALgAECgUJCwAAAA==.',
Lo='Lockedown:BAAALgADCgkJCQAAAA==.Lockhart:BAAALgAECgEJAQAAAA==.Logyn:BAAALgAECgMJBAAAAA==.Lonnias:BAAALgADCgcJDQAAAA==.Lore:BAABLgAECn8dAAIIAAgJ1hFjiQBJAQAIAAgJ1hFjiQBJAQAAAA==.Lotsalock:BAAALgAECgEJAQAAAA==.',
Lu='Lululemons:BAAALgAECgMJBAAAAA==.',
Ly='Lyllara:BAAALgADCggJCAABLgAECggJDgAXAAAAAA==.Lyphysia:BAAALgAECgcJDQAAAA==.Lyrelia:BAAALgAECgcJEwAAAA==.Lyssiarose:BAABLgAECn8aAAIOAAcJxRihPwC4AQAOAAcJxRihPwC4AQAAAA==.',
['Lë']='Lëucocrystal:BAAALgADCgYJBwAAAA==.',
Ma='Mack:BAAALgADCgEJAQAAAA==.Madbones:BAABLgAECn8aAAMeAAkJ5BMANwDlAQAeAAkJ2hEANwDlAQAEAAMJXxqJEwD2AAAAAA==.Mado:BAAALgAECggJEQAAAA==.Maeveracy:BAAALgADCgUJBQAAAA==.Mageijuana:BAABLgAECn8cAAIIAAkJXx2WJgBlAgAIAAkJXx2WJgBlAgAAAA==.Magicky:BAABLgAECn8lAAIIAAcJ0hjQWQCzAQAIAAcJ0hjQWQCzAQAAAA==.Magicsauce:BAAALgAECgYJBwAAAA==.Mahlkier:BAAALgAECgEJAQAAAA==.Maikego:BAAALgAECgUJEAAAAA==.Malachai:BAAALgAECgUJBQAAAA==.Malchelo:BAAALgAECgkJEQAAAA==.Malfhunter:BAACLgAFFH8IAAIaAAQJHww/EAAUAQAaAAQJHww/EAAUAQAuAAQKfzMAAhoACQnXG+QDAGICABoACQnXG+QDAGICAAAA.Maligosa:BAAALgADCgUJBQAAAA==.Manabender:BAAALgAECgIJAgAAAA==.Manbercatpig:BAAALgAECgYJBgAAAA==.Mangolassi:BAAALgADCgEJAQAAAA==.Manofwood:BAABLgAFFH8JAAIHAAQJSxEiCQAOAQAHAAQJSxEiCQAOAQAAAA==.Mantodea:BAAALgAECgQJAQAAAA==.Manus:BAAALgAECgMJBQAAAA==.Maranatha:BAAALgADCgEJAQAAAA==.Marmin:BAAALgAECgQJBAAAAA==.Marossa:BAAALgADCgMJAwAAAA==.Marymae:BAAALgAECgEJAQAAAA==.Masskiller:BAAALgADCgIJAgAAAA==.Masumi:BAAALgADCgEJAgAAAA==.Mattikus:BAAALgAECgQJDAAAAA==.Maximilion:BAAALgAECgcJDAAAAA==.',
Me='Megrim:BAAALgADCgIJAwAAAA==.Mehrartz:BAAALgADCgYJCwAAAA==.Melyn:BAAALgADCgIJAgAAAA==.Merdocki:BAACLgAFFH8MAAMfAAQJdRenDQCeAAAeAAMJrRnXUgD2AAAfAAIJDhOnDQCeAAAuAAQKfyoAAx8ACAmdIsMPANIBAB8ABQk6H8MPANIBAB4ABQlwIgJNAJ0BAAAA.Merdra:BAAALgAECgcJCQABLgAECgkJJQAIAJYXAA==.Merdre:BAACLgAFFH8PAAQbAAQJgw5RHgAXAQAbAAQJiAtRHgAXAQAMAAIJaxWVIACCAAAcAAEJVADuMQAsAAAuAAQKfzgABAwACQlVG5AOAHUCAAwACAlIHJAOAHUCABsACAmFFmoSACQCABwABQkAAgxLAK0AAAAA.Mertele:BAAALgAECgYJCgAAAA==.Messörem:BAAALgADCgYJBgAAAA==.Metasavage:BAAALgAECgQJBAABLgAECgUJBQAXAAAAAA==.',
Mi='Michealhunt:BAAALgAECgcJCQAAAA==.Midory:BAAALgAECgUJBQAAAA==.Mikimukka:BAAALgADCgIJAwAAAA==.Milim:BAAALgAECgQJBQABLgAECgUJBQAXAAAAAA==.Milkymocha:BAABLgAECn8lAAILAAkJzhjaCAAWAgALAAkJzhjaCAAWAgAAAA==.Minus:BAAALgADCgMJAwAAAA==.Misfitjoker:BAAALgAECgEJAQAAAA==.Misscorona:BAAALgADCggJDQAAAA==.Mistyque:BAAALgAECgQJCgAAAA==.Mithrond:BAAALgADCggJCgABLgAECgEJAQAXAAAAAA==.',
Mo='Modercai:BAAALgAECgQJBAAAAA==.Mom:BAAALgAECgYJCQAAAA==.Monkeymann:BAAALgADCgcJCQAAAA==.Morcant:BAAALgAECgYJDAAAAA==.Morhg:BAABLgAECn8lAAMfAAgJ1QiTFADdAAAeAAgJkQdHkAAFAQAfAAcJGQiTFADdAAAAAA==.Morianoley:BAAALgAECgQJBQAAAA==.Morlu:BAABLgAECn8lAAIKAAkJfh2CDwBcAgAKAAkJfh2CDwBcAgAAAA==.',
Ms='Msdonnapally:BAAALgAECgUJCQAAAA==.',
Mu='Mugnar:BAAALgADCgcJBwAAAA==.',
My='Myn:BAAALgAECgQJBAABLgAECggJCQAXAAAAAA==.Myxian:BAEALgAECgYJBgABLgAFFAQJEgAKAFQeAA==.',
['Mÿ']='Mÿsha:BAAALgAECgEJAQAAAA==.',
Na='Nadirya:BAEALgAECgcJCQABLgAFFAQJEgAKAFQeAA==.Nazkrul:BAAALgADCgMJAwAAAA==.',
Ne='Nellykorda:BAAALgAECgYJDwAAAA==.Neodruid:BAAALgAECgcJEQAAAA==.Nexxicus:BAAALgAECgEJAQAAAA==.',
Ni='Nightlywomen:BAAALgADCgcJDAAAAA==.Nightmehr:BAACLgAFFH8JAAIIAAQJ6Bm2OQBPAQAIAAQJ6Bm2OQBPAQAuAAQKfysAAggACQnoI30QAEUDAAgACQnoI30QAEUDAAAA.Nightphaze:BAAALgAECgEJAQABLgAECggJGQADAPQPAA==.Nihm:BAAALgAECgYJBgAAAA==.Nikolatte:BAAALgAECgEJBQAAAA==.Nimda:BAABLgAECn8aAAIBAAgJfiFrGwDZAgABAAgJfiFrGwDZAgAAAA==.',
No='Nosaj:BAAALgADCgkJCwAAAA==.',
Nu='Nullex:BAABLgAECn8kAAQJAAkJVRYjMgDdAQAJAAkJVRYjMgDdAQAPAAEJ/AkKVgAzAAARAAEJZQhbMQAbAAAAAA==.',
Ny='Nycara:BAAALgAECgIJAgAAAA==.Nyki:BAAALgAECgEJAQAAAA==.',
Ob='Oberon:BAAALgADCgYJBgAAAA==.',
Od='Odlaw:BAABLgAECn8jAAIcAAgJeAzgKABgAQAcAAgJeAzgKABgAQAAAA==.',
Of='Officiant:BAAALgAECgIJAgAAAA==.',
Ol='Olaria:BAAALgAECgYJBwABLgAECggJKQAOALwWAA==.Oldsaggins:BAAALgAECgcJEQAAAA==.Olikel:BAAALgADCgEJAQAAAA==.Ollymay:BAAALgAECgYJBgABLgAECggJEwAXAAAAAA==.Olm:BAAALgAECgUJBQAAAA==.',
On='Onedruidtion:BAAALgAECgQJCQAAAA==.',
Op='Ophekins:BAAALgADCgcJCwAAAA==.',
Or='Orcman:BAAALgAECgEJAQAAAA==.Orheo:BAAALgADCgQJBAAAAA==.Originalchip:BAABLgAECn8YAAIOAAcJ2BBSUgB+AQAOAAcJ2BBSUgB+AQAAAA==.Orionmoon:BAAALgAECgkJEgAAAA==.Orley:BAAALgADCgcJDAAAAA==.Orlos:BAABLgAECn8pAAIOAAgJvBZJMgDpAQAOAAgJvBZJMgDpAQAAAA==.Oräkk:BAACLgAFFH8LAAIUAAMJOCBSBwDuAAAUAAMJOCBSBwDuAAAuAAQKfxwAAhQACAn8HsILAAsCABQACAn8HsILAAsCAAAA.',
Os='Osrs:BAAALgAECgMJAwAAAA==.',
Ox='Oxelmorphs:BAAALgADCgcJCwAAAA==.',
Pa='Padrin:BAABLgAECn8lAAMOAAkJnBhvIAA7AgAOAAkJnBhvIAA7AgAaAAUJMA3sUQAFAQAAAA==.Palehorsemen:BAAALgAECgUJCwAAAA==.Pandaberry:BAAALgAECgYJCQAAAA==.Pandapaws:BAACLgAFFH8SAAICAAQJ7RvdGgBMAQACAAQJ7RvdGgBMAQAuAAQKfy0AAgIACQnPIU0KAOkCAAIACQnPIU0KAOkCAAAA.Pandomonium:BAAALgADCgIJAgAAAA==.Papawaas:BAAALgAECgUJBgAAAA==.Parthal:BAABLgAECn8dAAMDAAgJuQd0rQABAQADAAgJfwR0rQABAQALAAMJqAugOgBUAAAAAA==.Partylock:BAAALgAECgMJAwABLgAECggJIgAOAJAYAA==.Partyshooter:BAABLgAECn8iAAIOAAgJkBhMKgAKAgAOAAgJkBhMKgAKAgAAAA==.Patmage:BAABLgAECn8rAAIIAAgJqxgGTgDVAQAIAAgJqxgGTgDVAQABLgAFFAYJFgAGAEQTAA==.',
Pd='Pdiddi:BAABLgAECn8jAAMBAAkJVB/BOAD6AQAVAAcJ2x/4BAD6AQABAAgJJBzBOAD6AQAAAA==.',
Pe='Peed:BAABLgAECn8QAAIJAAcJtwk4vgB6AAAJAAcJtwk4vgB6AAAAAA==.Pellaeon:BAABLgAECn8XAAIBAAkJ2RiOSQAWAgABAAkJ2RiOSQAWAgAAAA==.',
Ph='Phexia:BAAALgAECgUJCAAAAA==.Phlan:BAEALgAECgYJCgAAAA==.Phrostir:BAAALgAFFAgJAQAAAA==.Phylactery:BAABLgAECn8nAAIBAAkJghh6PQBCAgABAAkJghh6PQBCAgAAAA==.',
Pi='Pierre:BAACLgAFFH8fAAQZAAYJRBcyBACcAQAZAAUJUhIyBACcAQAOAAQJQxmhBQBJAQAaAAEJAACCLQAAAAAuAAQKfyYABA4ACAnEIt0RAKkCAA4ACAnKId0RAKkCABkABgm6GxshAHQBABoABgnpDYdOABYBAAAA.Pillgrimm:BAABLgAECn8bAAIaAAgJNhFlDQBgAQAaAAgJNhFlDQBgAQAAAA==.Pinktax:BAAALgAECggJCAAAAA==.Pirotic:BAAALgADCgcJCwAAAA==.',
Po='Poisson:BAABLgAECn8hAAISAAkJNBWEEQCUAgASAAkJNBWEEQCUAgAAAA==.Polishdir:BAAALgAECgYJEAAAAA==.Polishduo:BAAALgAFFAEJAQAAAA==.Popsiclepete:BAAALgADCgIJAgAAAA==.Porzingus:BAAALgADCgcJBwAAAA==.Poxi:BAABLgAECn8WAAIgAAgJDRezEwBHAgAgAAgJDRezEwBHAgAAAA==.',
Pr='Praesidiel:BAABLgAECn8fAAIcAAgJwRh7GwABAgAcAAgJwRh7GwABAgAAAA==.Prescess:BAAALgAECgEJAQAAAA==.Presxia:BAAALgADCgYJBgABLgAECgEJAQAXAAAAAA==.Providence:BAACLgAFFH8MAAIPAAQJmhTvCQA2AQAPAAQJmhTvCQA2AQAuAAQKfzMAAg8ACQl+JOcBAH4DAA8ACQl+JOcBAH4DAAAA.Prsr:BAAALgAECgMJAwABLgAFFAYJFQABADkfAA==.',
Pu='Pudgypaws:BAAALgAECggJEAAAAA==.Puffed:BAAALgAECgIJAgABLgAFFAQJDwAbAIMOAA==.Punchkick:BAAALgAECgUJCAAAAA==.Purfukt:BAAALgAECgYJBgAAAA==.',
Py='Pyrogasm:BAAALgAECgMJBQABLgAFFAYJFQABADkfAA==.Pyrotrue:BAAALgADCgIJAgAAAA==.',
['På']='Pån:BAAALgAECgEJAQAAAA==.',
['Pè']='Pèwpéw:BAAALgAECgUJCQAAAA==.',
Qu='Quickmend:BAAALgAECgQJBgAAAA==.Quickpal:BAAALgAECgcJDAAAAA==.Quickpaw:BAACLgAFFH8MAAIhAAQJhhNwHgAAAQAhAAQJhhNwHgAAAQAuAAQKfyoAAiEACQkgIxYDAEwDACEACQkgIxYDAEwDAAAA.Quickshot:BAAALgADCgEJAQAAAA==.',
Ra='Raani:BAAALgADCgcJBwAAAA==.Raccoons:BAACLgAFFH8WAAMOAAYJIhnlAgBuAQAOAAUJpB7lAgBuAQAaAAEJGQO0JwBLAAAuAAQKfx8AAw4ACQnUIHIbAGICAA4ACQnUIHIbAGICABoAAwkrCXFqAJQAAAAA.Rageproof:BAABLgAECn8xAAIDAAgJ2Ql/jgA0AQADAAgJ2Ql/jgA0AQAAAA==.Ragged:BAACLgAFFH8IAAIBAAMJCx7laQD2AAABAAMJCx7laQD2AAAuAAQKfygAAgEACAk+IkkdAHYCAAEACAk+IkkdAHYCAAAA.Raidbloom:BAACLgAFFH8XAAIFAAQJUx8GFwBoAQAFAAQJUx8GFwBoAQAuAAQKfyIAAgUACQlxI0UGACcDAAUACQlxI0UGACcDAAAA.Raidheal:BAABLgAFFH8JAAIbAAMJPwuBJQDSAAAbAAMJPwuBJQDSAAABLgAFFAQJFwAFAFMfAA==.Rakroth:BAAALgAECgYJDwAAAA==.Ramook:BAAALgAECgMJAwAAAA==.Randomchar:BAACLgAFFH8HAAIDAAQJlgEqWwC/AAADAAQJlgEqWwC/AAAuAAQKfzUAAwMACAkIEY53AIsBAAMACAldDY53AIsBAAsABQn3ExsgAOMAAAAA.Rankor:BAAALgAECgYJEAABLgAFFAQJBwABAI4OAA==.Rastann:BAACLgAFFH8MAAIDAAQJIxNvPAAQAQADAAQJIxNvPAAQAQAuAAQKfysAAgMACQnsIgUOAB4DAAMACQnsIgUOAB4DAAAA.Ratrun:BAAALgAECgEJAQAAAA==.Raycharles:BAAALgAECgYJAQAAAA==.',
Re='Realir:BAABLgAECn8eAAIPAAkJfBNvEADtAQAPAAkJfBNvEADtAQAAAA==.Reapertoo:BAACLgAFFH8hAAQBAAUJ2SSnBwCUAQABAAUJ2SSnBwCUAQAVAAQJIB9BBABrAQAWAAEJAAByRAAAAAAuAAQKfzUAAwEACQkHJYYHAGQDAAEACQlHJIYHAGQDABUACQkPIkEBAAUDAAAA.Recreant:BAAALgADCgYJAQAAAA==.Redbaron:BAABLgAECn8jAAIPAAkJfRSVEgDMAQAPAAkJfRSVEgDMAQAAAA==.Regeth:BAAALgAECgcJEwAAAA==.Repyns:BAACLgAFFH8nAAQeAAgJ+xpfAwDuAQAeAAcJzBlfAwDuAQAfAAQJ7xzBBQAWAQAEAAIJ8iXCDwBZAAAuAAQKfyUABB4ACQnwJcEIADsDAB4ACAnwJcEIADsDAAQAAwnKJIYRABUBAB8AAwmmJGgVANYAAAAA.Retep:BAAALgADCgEJAQABLgAECgYJGQADAA8UAA==.Rethul:BAABLgAECn8iAAMgAAgJfBAELQBhAQAgAAgJfBAELQBhAQAkAAYJQwS3NADHAAAAAA==.Retsü:BAAALgAECggJDwABLgAFFAkJLwAMAMYRAA==.Rewind:BAAALgAECgEJAQAAAA==.',
Rh='Rhhonn:BAAALgAECgcJEQAAAA==.Rhollor:BAAALgAECgMJAwAAAA==.',
Ri='Ridic:BAACLgAFFH8HAAMBAAQJjg5RVwAgAQABAAQJjg5RVwAgAQAVAAEJiQFDGwA5AAAuAAQKfzEAAgEACAklH7AvAB0CAAEACAklH7AvAB0CAAAA.Rimeblade:BAAALgAECgYJCwAAAA==.',
Ro='Robutinblue:BAACLgAFFH8PAAIIAAUJARxePABKAQAIAAUJARxePABKAQAuAAQKfxsAAggACAkvH2ElAN0CAAgACAkvH2ElAN0CAAAA.Rocklesnar:BAAALgAECgMJAwAAAA==.Rondle:BAAALgAECgIJBAAAAA==.Rootbeerd:BAAALgAECggJCQAAAA==.Roshak:BAAALgAECgYJDQAAAA==.Rozalin:BAACLgAFFH8PAAIIAAQJ9honMQBjAQAIAAQJ9honMQBjAQAuAAQKfyoAAggACAm0JekKAG0DAAgACAm0JekKAG0DAAAA.Rozalinamoon:BAAALgAECgIJAgAAAA==.',
Ru='Ruffprophet:BAAALgAECgIJAwAAAA==.Rugelach:BAEALgAECgEJAQABLgAECgYJCgAXAAAAAA==.Rumi:BAABLgAECn8bAAIRAAgJsxOECwB3AQARAAgJsxOECwB3AQAAAA==.Rurouni:BAAALgADCgcJBwAAAA==.',
Ry='Ryoshi:BAACLgAFFH8PAAIZAAQJ8xUhDABMAQAZAAQJ8xUhDABMAQAuAAQKfzAAAhkACAmcIBADAAIDABkACAmcIBADAAIDAAAA.',
Sa='Sabotender:BAAALgADCgkJEAAAAA==.Sacredragon:BAAALgAECggJEQAAAA==.Sacredswords:BAACLgAFFH8RAAMKAAUJkhkdFgA2AQAKAAUJkhkdFgA2AQATAAEJnwM2DQBLAAAuAAQKfxkAAgoACAkiHvYVAJ0CAAoACAkiHvYVAJ0CAAAA.Saeys:BAAALgADCgMJAwAAAA==.Sakito:BAAALgAECgEJAQAAAA==.Salem:BAAALgAECgEJAQAAAA==.Sandalis:BAAALgADCgkJEgABLgAECgkJJAADAMcZAA==.Sandscale:BAAALgADCggJCAAAAA==.Sannctuary:BAAALgAECgYJEQAAAA==.Sapphiremist:BAABLgAECn8aAAIPAAYJ2BA4JgAMAQAPAAYJ2BA4JgAMAQAAAA==.Sauerkraut:BAAALgAECgcJAQAAAA==.Savagesin:BAAALgAFFAIJAgABLgAECgUJBQAXAAAAAA==.Sayen:BAAALgADCgkJCQAAAA==.',
Sc='Scachity:BAABLgAECn8gAAMfAAgJkBtGBAASAgAfAAgJkBtGBAASAgAeAAMJywkw4QBuAAAAAA==.Scarekroe:BAABLgAECn8pAAMiAAkJ3huuDABUAgAiAAkJ3huuDABUAgAnAAEJixSAiQAzAAAAAA==.Schein:BAAALgAECgEJAQAAAA==.Scorch:BAAALgAECgYJBwABLgAECggJLwAJAJMdAA==.Scratchers:BAABLgAECn8eAAIGAAgJ4iLMBgArAwAGAAgJ4iLMBgArAwAAAA==.',
Se='Seelina:BAAALgADCgYJBgAAAA==.Sehëthi:BAABLgAECn8eAAMFAAkJXBh4EwCOAgAFAAkJXBh4EwCOAgAGAAEJ9gD0jgAKAAAAAA==.Selanni:BAAALgADCgcJCAAAAA==.Sepulchre:BAAALgAECgYJDgAAAA==.Serlotte:BAAALgADCgcJEQAAAA==.',
Sh='Shadesfault:BAAALgAECgcJAwAAAA==.Shadowish:BAAALgADCgEJAQAAAA==.Shadunx:BAAALgADCgIJAgABLgAECgMJAwAXAAAAAA==.Shamaroo:BAAALgAECgUJBQAAAA==.Shaundakul:BAAALgAECgYJDgAAAA==.Shephion:BAAALgAECgEJAQABLgAFFAMJCAAiAPMkAA==.Shiee:BAAALgADCgEJAQAAAA==.Shnozberries:BAAALgAECgEJAQAAAA==.Shortnstack:BAABLgAECn8xAAIOAAgJzxAlRQCmAQAOAAgJzxAlRQCmAQAAAA==.Shãdow:BAAALgAECgYJDgAAAA==.',
Si='Sidetracked:BAABLgAECn8mAAIIAAkJehZFPgAHAgAIAAkJehZFPgAHAgAAAA==.Silanah:BAACLgAFFH8PAAInAAQJLRd6GAAxAQAnAAQJLRd6GAAxAQAuAAQKfywAAicACAk2HSUTAHgCACcACAk2HSUTAHgCAAAA.Silverheart:BAAALgAECgcJEQAAAA==.Silvershade:BAAALgADCgEJAQAAAA==.Simori:BAAALgAECgIJAgAAAA==.Sindrel:BAAALgADCgcJBwABLgAECggJGwAnAJQjAA==.',
Sk='Skawalker:BAACLgAFFH8KAAMlAAMJAA+kDQCVAAAlAAIJMQykDQCVAAAFAAIJLhT/QgCHAAAuAAQKfy0AAwUACQlKI/gFAC0DAAUACQlKI/gFAC0DACUACAkrGaYHACsCAAAA.Skyleebaby:BAAALgADCgcJBwAAAA==.',
Sl='Slashers:BAAALgADCgkJCQABLgAECggJHgAGAOIiAA==.Slaynne:BAACLgAFFH8PAAIKAAQJhR5ACQCFAQAKAAQJhR5ACQCFAQAuAAQKf0EABAoACQn7IzgGAOECAAoACQn7IzgGAOECABQABAlNIrQTAIsBABMAAQm9CEpEADAAAAAA.Sleven:BAAALgAECgUJCAABLgAFFAEJAQAXAAAAAA==.Slowfel:BAAALgADCgcJBwAAAA==.',
Sm='Smábes:BAAALgAECgQJBwAAAA==.Smäug:BAACLgAFFH8TAAMgAAcJzReqCgDiAQAgAAYJzReqCgDiAQAjAAEJAACmBwB1AAAuAAQKfyYABCMACAkPJd4EALUCACMABwlbI94EALUCACAABwl1JKIWAAICACQABwkcBakmAEABAAAA.',
Sn='Snobaws:BAAALgAECggJDwAAAA==.',
So='Sockz:BAABLgAECn8bAAISAAgJfBm2FABsAgASAAgJfBm2FABsAgAAAA==.Solria:BAABLgAECn82AAIMAAkJLhwhCADGAgAMAAkJLhwhCADGAgAAAA==.Solrosenborg:BAABLgAECn8yAAIBAAkJeCAJEgC+AgABAAkJeCAJEgC+AgABLgAFFAIJAgAXAAAAAA==.Solrosenburg:BAAALgAFFAIJAgAAAA==.Sondreman:BAABLgAECn8rAAMlAAkJZwoTEQBwAQAlAAkJZwoTEQBwAQAFAAIJoABW5gAfAAAAAA==.Sonnytyphoon:BAABLgAECn8ZAAIOAAgJjhcANgDbAQAOAAgJjhcANgDbAQAAAA==.Sorcereo:BAAALgADCgIJBQAAAA==.Soulzor:BAAALgAECgUJBwAAAA==.',
Sp='Spicychip:BAAALgADCgUJBQAAAA==.Spintwowin:BAAALgADCgUJBQAAAA==.Splashers:BAAALgADCgQJBAABLgAECggJHgAGAOIiAA==.Spookyghost:BAAALgADCgMJAwAAAA==.Spookysin:BAAALgAECgcJBwABLgAECgUJBQAXAAAAAA==.Spærkle:BAAALgAECgUJBgAAAA==.',
Sq='Squirreltag:BAAALgAECgUJCQAAAA==.',
Sr='Srmorphsalot:BAAALgAECgEJAQABLgAFFAYJHwAZAEQXAA==.',
St='Starnex:BAAALgADCgYJAQAAAA==.Statyrea:BAAALgAECgQJAQAAAA==.Stomped:BAAALgAECgcJDQAAAA==.Strikes:BAAALgAECgYJCAABLgAFFAMJDgARAOIjAA==.Stromlac:BAAALgADCgYJBgAAAA==.Styx:BAACLgAFFH8XAAIUAAQJwSEMCABxAQAUAAQJwSEMCABxAQAuAAQKfykAAhQACAlhJqoBAGoDABQACAlhJqoBAGoDAAAA.',
Su='Sukfoot:BAAALgAECgMJAwAAAA==.Sumbatadh:BAABLgAECn8mAAMPAAkJcw5+FgCdAQAPAAkJcw5+FgCdAQAJAAIJugLFDAEZAAAAAA==.Supergooner:BAAALgAFFAEJAQABLgAFFAYJHwAiAFIhAA==.Sutranova:BAAALgAECgEJAQABLgAECggJIgAgAHwQAA==.',
Sw='Swiftsoul:BAAALgADCgEJAQAAAA==.',
Sy='Sybexia:BAAALgAECgEJAQAAAA==.Sylvestris:BAABLgAECn8cAAIFAAgJ/xtaLgDzAQAFAAgJ/xtaLgDzAQAAAA==.',
Ta='Tabcast:BAAALgADCgUJBQAAAA==.Tabtank:BAAALgAECgYJBgAAAA==.Tacodad:BAAALgAECgQJBAAAAA==.Tacofart:BAAALgADCgMJAwAAAA==.Tacos:BAAALgAECgcJEAAAAA==.Tacotitan:BAAALgAECgkJBgAAAA==.Tailas:BAABLgAECn8ZAAInAAcJQxzvFADmAQAnAAcJQxzvFADmAQAAAA==.Tailyan:BAAALgADCgEJAQAAAA==.Taiyana:BAAALgADCgcJDgAAAA==.Talanthir:BAAALgADCgMJAwAAAA==.Tangie:BAAALgADCgkJHgAAAA==.Tankjob:BAAALgAECgQJEAAAAA==.Tanklorswift:BAAALgAECgQJDQAAAA==.Taojin:BAABLgAECn8UAAQYAAcJhA/zDwAFAQASAAUJ6xAQOwBBAQAYAAcJKg7zDwAFAQAQAAEJ5AEFEAAbAAAAAA==.Taojïn:BAAALgAECgIJAgAAAA==.Tapandsap:BAAALgAECgEJAQAAAA==.Tatsuyâ:BAAALgADCgYJCwAAAA==.',
Td='Tdog:BAAALgAECgEJAQAAAA==.',
Te='Teapot:BAAALgAECggJAQAAAA==.Tedoseirum:BAABLgAECn8dAAIPAAkJyCRoAwBNAwAPAAkJyCRoAwBNAwAAAA==.Tengen:BAAALgAECgEJAQABLgAECgEJAwAXAAAAAA==.Tengenthas:BAAALgAECgEJAwAAAA==.Terpyu:BAAALgAECgYJEwAAAA==.Testicuhls:BAAALgAECgYJEwAAAA==.Texasbilly:BAAALgAECgYJCwAAAA==.Texasredneck:BAAALgADCgQJAwAAAA==.',
Th='Thalchy:BAAALgAECgYJDAAAAA==.Thaydel:BAAALgADCgMJAwAAAA==.Thedtwo:BAABLgAECn8mAAIDAAcJ+CADOQD+AQADAAcJ+CADOQD+AQAAAA==.Thelizzah:BAABLgAECn8gAAMDAAcJZA89qQAHAQADAAYJlA09qQAHAQAdAAIJXwBtnQAsAAAAAA==.Thelvaris:BAAALgAECgYJCwAAAA==.Thorgarrus:BAACLgAFFH8MAAIDAAQJ4CBXFwB1AQADAAQJ4CBXFwB1AQAuAAQKfzMAAgMACQmdIO0RAL0CAAMACQmdIO0RAL0CAAAA.',
Ti='Tigerwoodz:BAAALgAECgYJDQAAAA==.Tilbourne:BAAALgAECgEJAQAAAA==.Timfist:BAAALgAECgUJCAAAAA==.Tinada:BAAALgADCgEJAQABLgADCgMJAwAXAAAAAA==.Tinytrina:BAAALgADCgYJBgAAAA==.',
To='Toddie:BAABLgAECn8uAAMOAAkJCB0aGQBnAgAOAAkJCB0aGQBnAgAaAAMJugxqbQCJAAAAAA==.Tolkein:BAAALgADCgEJAQAAAA==.Tommyj:BAAALgAECgcJCgAAAA==.Torep:BAAALgAECgQJBAAAAA==.Tormod:BAABLgAECn8qAAIOAAkJABrxHQBJAgAOAAkJABrxHQBJAgAAAA==.Tormodd:BAABLgAECn8kAAIPAAYJ7A82KAD+AAAPAAYJ7A82KAD+AAAAAA==.Torsyn:BAAALgAECgUJBQABLgAECgkJLgAOAAgdAA==.Torvaldt:BAAALgAECgIJAgABLgAECgkJLgAOAAgdAA==.',
Tr='Traedea:BAAALgAECgYJCQAAAA==.Traps:BAAALgAECggJDgAAAA==.Trashypanda:BAACLgAFFH8eAAIoAAYJ7SAaAAD7AQAoAAYJ7SAaAAD7AQAuAAQKfy4AAigACAmEJHsAADQDACgACAmEJHsAADQDAAAA.Trinagirl:BAAALgAECgYJCwAAAA==.Tristanyia:BAABLgAECn8eAAIhAAkJ0BvHCADbAgAhAAkJ0BvHCADbAgAAAA==.Troolen:BAAALgAECgYJEQAAAA==.Tryana:BAABLgAECn8uAAInAAgJ8AenMAAiAQAnAAgJ8AenMAAiAQAAAA==.Trystiania:BAAALgAECgYJDwAAAA==.',
Ts='Tseraphim:BAAALgADCgMJBAAAAA==.',
Tt='Tt:BAABLgAECn8gAAIBAAcJcQuSnQAIAQABAAcJcQuSnQAIAQAAAA==.',
Tu='Tuggnugg:BAAALgAECgEJAQAAAA==.Tumamï:BAAALgAECgQJBAAAAA==.Turcomund:BAAALgADCgMJBAAAAA==.',
Tw='Twentynein:BAAALgAECgcJDQAAAA==.Twentynine:BAACLgAFFH8HAAIZAAQJWRHTDQBBAQAZAAQJWRHTDQBBAQAuAAQKfzYABBkACAmSI3kIAHwCABkACAmFH3kIAHwCABoABwmeHKEbAEwCAA4ACAmHFq5zACoBAAAA.',
Ty='Tyledis:BAAALgAECgUJDAABLgAFFAQJDwAnAC0XAA==.Tyr:BAACLgAFFH8NAAIpAAMJeBfuDgD7AAApAAMJeBfuDgD7AAAuAAQKfx8AAykACQnTHb0MANICACkACQnTHb0MANICAAIAAQl1BSvCACIAAAAA.Tyrandi:BAABLgAFFH8FAAIJAAQJgwJkUQDFAAAJAAQJgwJkUQDFAAAAAA==.Tyrnova:BAAALgAFFAIJAgAAAA==.Tyrsa:BAAALgAECgQJBwAAAA==.',
Tz='Tzneetch:BAAALgAECgEJAQAAAA==.',
['Tï']='Tïnk:BAABLgAECn8hAAIJAAgJgRXSRgCPAQAJAAgJgRXSRgCPAQABLgAFFAIJBAAXAAAAAA==.',
['Tö']='Töshïrö:BAAALgAECgYJEAAAAA==.',
Ub='Ubel:BAAALgADCgEJAwAAAA==.',
Ud='Udderlee:BAABLgAECn8ZAAMiAAcJtBMoJQBfAQAiAAcJtBMoJQBfAQAnAAYJeA7sRAAuAQAAAA==.',
Uh='Uhope:BAAALgAECgcJEAAAAA==.',
Uk='Ukog:BAABLgAECn8UAAISAAgJygh1IgBTAQASAAgJygh1IgBTAQAAAA==.',
Um='Umbravolt:BAACLgAFFH8MAAIHAAQJqxgXBwAzAQAHAAQJqxgXBwAzAQAuAAQKfzIAAgcACQkXJB0BAFgDAAcACQkXJB0BAFgDAAAA.Umineko:BAAALgAECgEJAQAAAA==.',
Un='Unravel:BAAALgAECgEJAQAAAA==.Unrealpriest:BAAALgAECgMJAwAAAA==.Unrealronin:BAABLgAECn8dAAMUAAgJRgSjKADGAAATAAYJmwXHJADHAAAUAAgJxQKjKADGAAAAAA==.',
Ur='Uruchi:BAAALgADCgEJAQAAAA==.',
Va='Vaelorn:BAABLgAECn8VAAIJAAgJliDtFADaAgAJAAgJliDtFADaAgAAAA==.Vaelun:BAAALgAECgUJBQAAAA==.Vaeris:BAAALgAECgEJAgAAAA==.Vakero:BAABLgAECn8eAAMDAAcJxQadsgD5AAADAAcJxQadsgD5AAAdAAIJyQL3dABBAAAAAA==.Valeriana:BAAALgADCgQJBQAAAA==.Valice:BAAALgAECgEJAQAAAA==.Vanadra:BAAALgADCgMJAwAAAA==.Vapor:BAAALgAECgEJAwAAAA==.Vatheus:BAAALgADCgYJBgAAAA==.Vathion:BAAALgAECgMJAwAAAA==.',
Ve='Veneno:BAAALgADCgYJBgAAAA==.Vert:BAAALgADCgYJBgABLgAFFAQJCQAfAIAJAA==.',
Vi='Vibrance:BAABLgAECn8cAAQkAAgJNCCHBQDwAgAkAAgJNCCHBQDwAgAgAAYJFBrbKgBpAQAjAAIJSRL/MgB+AAAAAA==.Vindicus:BAAALgAECgUJCAAAAA==.Viridesa:BAAALgAECgQJAQAAAA==.Viserra:BAAALgADCgMJAwAAAA==.Vivienne:BAACLgAFFH8LAAIdAAQJMwjaIQDjAAAdAAQJMwjaIQDjAAAuAAQKfyMAAh0ACQlrElosANUBAB0ACQlrElosANUBAAAA.',
Vo='Voidbacon:BAAALgAECgQJBAAAAA==.Voidcore:BAABLgAECn8iAAIJAAkJfh29EACgAgAJAAkJfh29EACgAgAAAA==.',
Vv='Vv:BAAALgAECgUJBgAAAA==.',
Vy='Vyagra:BAAALgAECgcJCAAAAA==.Vyrinthial:BAAALgADCgUJBwAAAA==.Vyrnath:BAAALgAECgEJAQAAAA==.',
Wa='Walon:BAAALgADCgcJDgABLgAECggJCQAXAAAAAA==.Warfarmer:BAABLgAECn8XAAMUAAcJFRA/HwAPAQAUAAcJRA4/HwAPAQAKAAUJaA3UVQDKAAAAAA==.Warhawke:BAAALgADCgYJCAAAAA==.Warmack:BAAALgADCgMJBAAAAA==.',
We='Weak:BAAALgAECgcJDwAAAA==.Weakhand:BAAALgADCgIJAwAAAA==.Webs:BAAALgADCgUJBQAAAA==.Weel:BAACLgAFFH8KAAIJAAMJPR0XPgADAQAJAAMJPR0XPgADAQAuAAQKfygAAgkACQlGHKshAC0CAAkACQlGHKshAC0CAAAA.',
Wh='When:BAAALgADCgQJBAABLgAFFAQJDwAhAO4eAA==.Wheresdparty:BAAALgAECgEJAQAAAA==.Whilaanna:BAACLgAFFH8JAAIJAAUJqwwlPgADAQAJAAUJqwwlPgADAQAuAAQKfxYAAwkACAmGHDYbAFQCAAkACAmGHDYbAFQCABEAAQlGBVUxAB4AAAEuAAUUBgkGAAkANRUA.Whis:BAABLgAECn8lAAMYAAcJogrADAA+AQAYAAcJogrADAA+AQASAAQJ4Qg4OwCiAAAAAA==.Whispernight:BAAALgAECgEJAQAAAA==.',
Wi='Widja:BAAALgAECgEJAQAAAA==.Wiilock:BAABLgAECn8dAAIeAAYJ4B4eRAD/AQAeAAYJ4B4eRAD/AQAAAA==.Wiivinelight:BAAALgAECgYJCgABLgAECgYJHQAeAOAeAA==.Wiivoker:BAAALgAECgUJBAABLgAECgYJHQAeAOAeAA==.Wildhus:BAAALgAECgUJCgAAAA==.Wildwhitwlkr:BAAALgADCgMJBQAAAA==.Wilfrid:BAAALgAECgIJAgABLgAFFAEJAQAXAAAAAA==.',
Wr='Wraithlord:BAAALgAECgcJCAAAAA==.',
['Wå']='Wåffle:BAAALgAFFAIJAgABLgAFFAQJBQAYAKUZAA==.',
Xa='Xandari:BAAALgADCgkJDwAAAA==.Xania:BAAALgADCgYJBwAAAA==.Xannica:BAAALgAECgYJDAAAAA==.',
Xe='Xenzel:BAAALgAECggJBQAAAA==.',
Xx='Xxbadwar:BAAALgADCgEJAQAAAA==.',
['Xû']='Xûrû:BAAALgAECgcJEwAAAA==.',
Yc='Yce:BAABLgAECn8sAAMkAAcJuxdoDQDVAQAkAAcJuxdoDQDVAQAjAAMJjA0cFQCXAAAAAA==.',
Yo='Yoker:BAAALgADCgYJCwAAAA==.Yokersen:BAAALgAECgUJBQAAAA==.',
Yr='Yrana:BAAALgAECgYJBgAAAA==.',
Za='Zaeladen:BAABLgAECn8XAAIeAAYJcgKXzwCRAAAeAAYJcgKXzwCRAAAAAA==.Zalorea:BAAALgAECgQJBgAAAA==.Zamlock:BAAALgAECgcJBwABLgAFFAQJCwAQAM0eAA==.Zamorak:BAAALgAECgUJCAAAAA==.Zamrog:BAACLgAFFH8LAAIQAAQJzR7XAgBcAQAQAAQJzR7XAgBcAQAuAAQKfysAAhAACQkxIt4AABEDABAACQkxIt4AABEDAAAA.Zamthyr:BAAALgAECgkJDwABLgAFFAQJCwAQAM0eAA==.Zanya:BAABLgAECn8XAAMCAAYJ5w++UwAvAQACAAYJ5w++UwAvAQApAAEJ6gGdngAZAAAAAA==.',
Ze='Zeiko:BAAALgAECgUJBgAAAA==.Zellah:BAAALgAECgcJEQAAAA==.Zenez:BAAALgAECgYJDAAAAA==.Zexor:BAAALgADCgYJDwAAAA==.Zeäl:BAAALgAECgEJAQAAAA==.',
Zh='Zhaoyun:BAABLgAECn8lAAMhAAkJFRapFQAxAgAhAAkJFRapFQAxAgAnAAEJnwZskQAfAAAAAA==.',
Zi='Zilen:BAAALgADCgUJBQAAAA==.Zilkir:BAACLgAFFH8PAAMdAAQJLSRDDQChAQAdAAQJLSRDDQChAQADAAIJyyD+XwCtAAAuAAQKfzgAAx0ACAkwI9gEAB8DAB0ACAkwI9gEAB8DAAMABwnfIO1HAAsCAAAA.Ziran:BAAALgAECgYJCAAAAA==.Zivadhim:BAAALgAECgQJAQAAAA==.',
Zk='Zkollkrusher:BAAALgADCgYJBgAAAA==.Zkullkrushur:BAAALgAECgUJBQAAAA==.Zkvllkrusher:BAAALgADCgEJAQAAAA==.',
Zl='Zlyth:BAAALgAECgYJDwAAAA==.',
Zo='Zohan:BAAALgAECgQJCgAAAA==.Zooie:BAABLgAECn8hAAMCAAkJkBZgMwC3AQACAAkJkBZgMwC3AQApAAgJyBR9JQCQAQAAAA==.Zould:BAABLgAECn8aAAIIAAYJUxG4lQAyAQAIAAYJUxG4lQAyAQAAAA==.',
Zy='Zyrix:BAAALgADCgQJBAAAAA==.',
['Àr']='Àrthàs:BAAALgAECgcJDwAAAA==.',
['Är']='Ärtrix:BAAALgADCgEJAQAAAA==.',
['Ät']='Ätrixx:BAAALgAECgYJCwAAAA==.',
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
