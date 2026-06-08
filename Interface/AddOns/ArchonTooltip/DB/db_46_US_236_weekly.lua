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

local lookup = {'Druid-Balance','Unknown-Unknown','Paladin-Holy','Mage-Frost','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Druid-Guardian','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Shaman-Restoration','Druid-Restoration','Warrior-Fury','Monk-Brewmaster','Evoker-Preservation','Monk-Windwalker','DeathKnight-Frost','Priest-Discipline','Hunter-Marksmanship','Rogue-Outlaw','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Shaman-Elemental','Druid-Feral','Warlock-Destruction','Priest-Holy','Warrior-Arms','Paladin-Protection','Warrior-Protection','Warlock-Affliction','DemonHunter-Havoc','Shaman-Enhancement',}
local provider = {region='US',realm='Warsong',name='US',type='weekly',zone=46,date='2026-06-07',data={Ad='Adeyna:BAAALgAECgEJAQAAAA==.Adònis:BAAALgADCgEJAQAAAA==.',
Ae='Aesudan:BAAALgADCgEJAQAAAA==.',
Ah='Aharan:BAABLgAECn8yAAIBAAgJ8g/jKwBrAQABAAgJ8g/jKwBrAQAAAA==.',
Ai='Aiona:BAAALgADCgYJDAAAAA==.',
Al='Alandrov:BAAALgADCgEJAQAAAA==.Alexanzalone:BAAALgADCggJCAAAAA==.Allenduin:BAAALgAECgEJAQAAAA==.Alodso:BAAALgADCgEJAQAAAA==.',
An='Angelique:BAAALgAECgYJCgAAAA==.Angryballz:BAAALgAECgYJBwABLgAECgYJDAACAAAAAA==.Angz:BAAALgAECgUJDQAAAA==.Anielor:BAAALgAECgIJAgAAAA==.Anuksuna:BAAALgAECgUJCQABLgAECgkJHgADAE4XAA==.',
Ar='Arcadia:BAAALgAECgYJDgAAAA==.Arcane:BAACLgAFFH8RAAIEAAUJox6MQQBdAQAEAAUJox6MQQBdAQAuAAQKfx8AAwQACQngIVwQAEYDAAQACQngIVwQAEYDAAUABQlDJBcFAOkBAAAA.',
As='Asta:BAAALgAECgQJBAAAAA==.',
At='Atulan:BAAALgADCgQJBAAAAA==.',
Au='Austin:BAAALgADCggJFgAAAA==.Automobeer:BAAALgAECgEJBAAAAA==.',
Aw='Awake:BAACLgAFFH8JAAIGAAQJFRiXUgBAAQAGAAQJFRiXUgBAAQAuAAQKfycAAwYABwnJF0lmAJMBAAYABwmAFklmAJMBAAcABgnaElYfAEoBAAAA.',
Az='Azazzel:BAAALgADCgEJAQAAAA==.',
Ba='Bambietta:BAAALgADCgkJCQAAAA==.Barebelly:BAAALgAECggJEAAAAA==.',
Be='Bearforce:BAABLgAECn8eAAIIAAkJjxnZCAAbAgAIAAkJjxnZCAAbAgAAAA==.',
Bi='Biggbird:BAABLgAECn8nAAIBAAcJAB1zGgDtAQABAAcJAB1zGgDtAQAAAA==.',
Bl='Blewbawl:BAAALgADCgEJAQAAAA==.Blutwin:BAABLgAECn8sAAIJAAkJThPvRQDqAQAJAAkJThPvRQDqAQAAAA==.Bluud:BAAALgADCgMJAwAAAA==.',
Bo='Bootyhünter:BAAALgAECgEJAgAAAA==.Bossdierr:BAACLgAFFH8bAAMKAAQJxSPUHwCeAQAKAAQJxSPUHwCeAQALAAQJQg9jBgDmAAAuAAQKfzIAAwoACQkyI5wQALUCAAoACQkyI5wQALUCAAsACAlCE04PAEsBAAAA.Bossdisan:BAACLgAFFH8LAAIEAAQJQxr7TwA9AQAEAAQJQxr7TwA9AQAuAAQKfygAAgQABglsJFdXADMCAAQABglsJFdXADMCAAAA.Bossmasster:BAAALgAFFAIJAgAAAA==.Bosswudi:BAABLgAFFH8JAAMMAAIJMRNjCgCTAAANAAIJwRK0FQCgAAAMAAIJihFjCgCTAAAAAA==.',
Br='Brashe:BAABLgAECn8oAAIEAAcJqw4QlQBKAQAEAAcJqw4QlQBKAQAAAA==.Breathe:BAAALgAECgQJBAABLgAECgYJCgACAAAAAA==.Brickbeard:BAAALgAECggJDgAAAA==.Bruv:BAABLgAECn8jAAIOAAYJhhU5bwCCAQAOAAYJhhU5bwCCAQABLgAECgkJFQAPAEwYAA==.',
Ca='Calathis:BAAALgAECgEJAQAAAA==.Cazadòr:BAAALgAECgIJAgAAAA==.',
Ch='Chromiepip:BAAALgADCgMJAwAAAA==.',
Co='Corbann:BAAALgAECgYJCgAAAA==.',
Cr='Creamcheese:BAABLgAECn8aAAIQAAcJUB27LAD8AQAQAAcJUB27LAD8AQAAAA==.Creamy:BAABLgAECn8yAAIRAAkJ+xrzEwBMAgARAAkJ+xrzEwBMAgAAAA==.Crossbreed:BAAALgAFFAIJBAAAAA==.',
Cy='Cyr:BAAALgADCgUJBQAAAA==.Cytosine:BAAALgAFFAEJAQAAAA==.',
Da='Daddyhaz:BAACLgAFFH8SAAIKAAYJThZtHgCmAQAKAAYJThZtHgCmAQAuAAQKf0MAAgoACQmzJBwEAD4DAAoACQmzJBwEAD4DAAAA.Daddywhyudie:BAAALgADCgEJAQAAAA==.Daelyte:BAAALgAECgYJDwAAAA==.Daghor:BAABLgAFFH8IAAINAAIJPiLFKgC4AAANAAIJPiLFKgC4AAAAAA==.',
De='Deltron:BAAALgAECgEJAQAAAA==.Desetre:BAAALgADCgIJAgAAAA==.',
Di='Diabos:BAAALgAECgYJBwABLgAFFAQJFgACAAAAAA==.Dinks:BAABLgAECn9MAAMEAAkJihkyKQBvAgAEAAkJihkyKQBvAgAFAAEJJRPeEwA6AAAAAA==.Ditzy:BAAALgAECgEJAQAAAA==.',
Do='Docc:BAABLgAECn8XAAINAAkJGA+nFgBXAgANAAkJGA+nFgBXAgAAAA==.Domdps:BAAALgAECgEJAQAAAA==.',
Dr='Draan:BAAALgADCgUJBwAAAA==.Dragorr:BAAALgADCgcJBwAAAA==.Dreadpanda:BAAALgADCgMJAwABLgAFFAQJDQASAOokAA==.Drekkarn:BAAALgADCgMJBgAAAA==.Drood:BAAALgAECgQJCgAAAA==.',
El='Elzath:BAAALgADCggJEAABLgAECgkJIwATAIkUAA==.',
En='Enix:BAAALgADCgYJBgABLgAFFAIJCAAQALwTAA==.',
Er='Erdrick:BAAALgAECgIJBQAAAA==.',
Es='Espeon:BAAALgAECgcJDgAAAA==.',
Eu='Eudisius:BAAALgADCgEJAQAAAA==.',
Ev='Evara:BAABLgAECn8UAAIEAAYJAwdU7gAcAQAEAAYJAwdU7gAcAQAAAA==.',
Fa='Faded:BAAALgAECgYJEwAAAA==.Fangbot:BAAALgAECgEJAgAAAA==.',
Fe='Felcaas:BAAALgADCgQJBAAAAA==.Felini:BAABLgAECn8fAAIRAAkJsAfpOABcAQARAAkJsAfpOABcAQAAAA==.Feronar:BAABLgAECn8uAAIRAAkJ+wuULACbAQARAAkJ+wuULACbAQAAAA==.',
Fi='Fizzwater:BAAALgAECgYJDgAAAA==.',
Fl='Fleepity:BAAALgAECgcJEAAAAA==.Floopity:BAAALgADCgYJBwAAAA==.Flowermom:BAAALgAECgEJAwAAAA==.Flume:BAABLgAECn8VAAMMAAgJ5BW4CQCYAQAMAAgJZhG4CQCYAQANAAQJKBP0MAANAQAAAA==.',
Fu='Fusíon:BAEBLgAECn8zAAIKAAkJeiIwDgANAwAKAAkJeiIwDgANAwAAAA==.',
Gi='Gin:BAACLgAFFH8TAAIUAAQJaROvFAAUAQAUAAQJaROvFAAUAQAuAAQKfzIAAhQACQkuG2YWAPgBABQACQkuG2YWAPgBAAAA.',
Gj='Gjana:BAAALgAFFAIJBAABLgAFFAQJCQAEALwIAA==.',
Gl='Glamdring:BAAALgADCgMJAwAAAA==.Glunty:BAAALgAECgUJCAAAAA==.',
Go='Goldpaw:BAAALgADCgEJAQAAAA==.Gorlash:BAAALgAECgcJCAAAAA==.',
Gr='Gridinn:BAAALgADCgIJAgAAAA==.Grimdark:BAAALgAECgYJCQAAAA==.Grimgeth:BAACLgAFFH8UAAMGAAQJ4BN5YgApAQAGAAQJ4BN5YgApAQAHAAIJ9AxnLgByAAAuAAQKf0IABAYACQlsIdoOAO8CAAYACQmQINoOAO8CAAcAAwlXH4Y3AK0AABUAAwlOFJEqAGoAAAAA.Grimwrath:BAAALgAECgUJBwABLgAFFAQJFAAGAOATAA==.',
Gu='Gugaman:BAAALgADCgcJDgAAAA==.Guishin:BAAALgAECgEJAwAAAA==.',
He='Healpls:BAAALgAECgEJAgAAAA==.Heidriel:BAAALgAECgMJAwAAAA==.Herumesu:BAAALgADCgcJCgABLgAFFAUJEwAGAAIdAA==.',
Ho='Holapes:BAAALgAECgUJEAABLgAECgMJBAACAAAAAA==.',
Hu='Huhbruh:BAAALgAECgIJAgABLgAECgkJFQAPAEwYAA==.',
Hw='Hwasa:BAABLgAECn8jAAISAAkJ4h3ICwBxAgASAAkJ4h3ICwBxAgAAAA==.',
Il='Illigari:BAAALgAFFAEJAQAAAA==.',
In='Indy:BAAALgAECgEJAQAAAA==.Insanities:BAABLgAECn9TAAIWAAkJaCXPAADZAwAWAAkJaCXPAADZAwAAAA==.Inti:BAABLgAECn8WAAIDAAYJZhuRLgCZAQADAAYJZhuRLgCZAQABLgAFFAIJCAAQALwTAA==.',
Iz='Izumisakai:BAAALgAFFAIJAgABLgAFFAUJEwAGAAIdAA==.',
Ja='Jaidie:BAABLgAECn8UAAIXAAcJsAmZFwDqAAAXAAcJsAmZFwDqAAAAAA==.',
Je='Jeffreyx:BAAALgAECgYJCAAAAA==.Jeffreyz:BAAALgADCgYJBgAAAA==.',
Jo='Joak:BAAALgADCgUJBQAAAA==.Jota:BAAALgADCgcJCAAAAA==.',
Ka='Kahlune:BAAALgAECgEJAQABLgAECgkJHgADAE4XAA==.Kahlán:BAABLgAECn8eAAIDAAkJThcnHgAIAgADAAkJThcnHgAIAgAAAA==.Karlangas:BAAALgAECgMJBAAAAA==.',
Ki='Kifu:BAAALgAECgIJAgABLgAFFAQJCQAEALwIAA==.Kikipants:BAAALgADCgEJAQAAAA==.Kitrix:BAAALgADCgUJBQAAAA==.Kitty:BAABLgAFFH8GAAITAAMJDgTwIACOAAATAAMJDgTwIACOAAABLgAFFAQJDgAIAHYHAA==.',
Kr='Krue:BAAALgADCggJDQAAAA==.',
Ku='Kubimage:BAABLgAECn8aAAIEAAkJKhu2MgCoAgAEAAkJKhu2MgCoAgAAAA==.',
La='Laguna:BAAALgAECgkJBAAAAA==.Lane:BAAALgADCgEJAQAAAA==.Layona:BAAALgAECgYJCgAAAA==.',
Le='Lerroy:BAAALgADCgcJCQAAAA==.',
Li='Liana:BAAALgAECgEJAQAAAA==.Lildar:BAABLgAECn8nAAIGAAgJnhrBPwD+AQAGAAgJnhrBPwD+AQAAAA==.Linelli:BAAALgAFFAIJBAABLgAFFAYJEwAYAFwjAA==.Lirra:BAAALgAFFAIJBAABLgAFFAIJCAAQALwTAA==.',
Lo='Londo:BAAALgAECgUJBgAAAA==.Lorthiel:BAAALgADCgIJAgAAAA==.Lothus:BAACLgAFFH8IAAIZAAIJgh7lawCpAAAZAAIJgh7lawCpAAAuAAQKfxUAAxkACQkPGzAYAHgCABkACQkPGzAYAHgCABcAAQl2BGOTACcAAAEuAAUUAgkIABAAvBMA.Lox:BAAALgAECgYJCQAAAA==.',
Ls='Lsblkxd:BAAALgADCgYJBgAAAA==.',
Lu='Lumen:BAAALgAECgIJAgAAAA==.Lumverjvcked:BAABLgAECn8VAAIPAAcJTBhELgDyAQAPAAcJTBhELgDyAQAAAA==.',
Lx='Lxrbread:BAACLgAFFH8ZAAMaAAQJZA1ZMAD3AAAaAAQJZA1ZMAD3AAATAAEJ5QPaGAA8AAAuAAQKfzoABBoACQn4FY4dAOMBABoACQnXFY4dAOMBABMABQlBBdY3AK0AABsAAgmoCgwjADkAAAAA.',
['Lë']='Lëgitz:BAABLgAECn8lAAMPAAkJuR84CwD6AgAPAAkJuR84CwD6AgAcAAgJIBTWKwCJAQAAAA==.',
Ma='Macca:BAAALgAECgUJBQABLgAECgYJDAACAAAAAA==.Maccazilla:BAAALgAECgYJDAAAAA==.Magdalena:BAACLgAFFH8WAAIUAAUJcSTlBgCbAQAUAAUJcSTlBgCbAQAuAAQKfyYAAhQACQkXJb8CAG0DABQACQkXJb8CAG0DAAAA.Magedand:BAAALgAECgMJAwAAAA==.Magnesson:BAAALgAFFAEJAgAAAA==.Manakaren:BAAALgADCggJDAAAAA==.Martini:BAAALgADCgEJAQAAAA==.Mazuro:BAACLgAFFH8eAAINAAYJThuEDACoAQANAAYJThuEDACoAQAuAAQKfzMAAw0ACQm5Hc8IAI4CAA0ACQm5Hc8IAI4CAAwAAQlGGVodAEAAAAAA.',
Me='Meatkleaver:BAABLgAECn8bAAMVAAkJ0BUhAwBnAgAVAAkJ0BUhAwBnAgAGAAEJqAGXNgEiAAAAAA==.Meau:BAABLgAECn8jAAIdAAkJmh5mBQCQAgAdAAkJmh5mBQCQAgAAAA==.Mechadar:BAAALgAECgMJAwAAAA==.Mechanizedtv:BAACLgAFFH8RAAIIAAQJ7iPkBACgAQAIAAQJ7iPkBACgAQAuAAQKf+QABAgACQmwJkAAAIQDAAgACQmwJkAAAIQDAB0ABwnpJJIFAIwCAAEAAQlmAomdABwAAAAA.',
Mi='Mitskí:BAAALgAECgQJBAAAAA==.',
Mo='Mongerasta:BAAALgAECgMJBwAAAA==.Monkerooz:BAAALgAECgUJCAAAAA==.Moodeng:BAAALgADCgYJBwAAAA==.Morphîne:BAACLgAFFH8IAAIQAAIJvBM8UAB3AAAQAAIJvBM8UAB3AAAuAAQKfxcAAhAABwkZHvEoABACABAABwkZHvEoABACAAAA.',
Mu='Mugwump:BAAALgAECggJDQAAAA==.Murdõk:BAAALgAECgEJAQABLgAECgkJHAAGAK4YAA==.Murdøk:BAABLgAECn8cAAMGAAkJrhiIWAC2AQAGAAkJrhiIWAC2AQAHAAEJ6Q04RAA4AAAAAA==.',
My='Mythic:BAABLgAECn8pAAIUAAkJdBu9DQBiAgAUAAkJdBu9DQBiAgAAAA==.',
['Mû']='Mûrdok:BAAALgAECgUJDQABLgAECgkJHAAGAK4YAA==.',
['Mü']='Mürdok:BAAALgAECgYJDAABLgAECgkJHAAGAK4YAA==.',
Ne='Necromortas:BAAALgAECgcJBwAAAA==.Nefarius:BAABLgAECn8WAAMOAAkJLhuEVwCRAQAOAAgJLhuEVwCRAQAeAAMJWxRgOwDGAAAAAA==.Neph:BAABLgAECn8aAAMfAAkJQw96HwDlAQAfAAkJQw96HwDlAQAWAAIJbgNeUABNAAAAAA==.Nezot:BAAALgAECgEJAQAAAA==.',
Ni='Nihilism:BAAALgADCgYJBgAAAA==.Ninsu:BAAALgAECgYJCgAAAA==.Nishale:BAAALgAECgMJBQAAAA==.',
No='Noir:BAAALgADCgQJBAAAAA==.',
Nu='Nutdraggin:BAAALgADCgcJBwAAAA==.',
Ny='Nyki:BAAALgAECgcJDQAAAA==.',
On='Onlyfist:BAAALgAECgEJAgAAAA==.',
Op='Opius:BAAALgAECgkJEgAAAA==.',
Or='Orcmagic:BAAALgADCgUJBwAAAA==.',
Os='Oshift:BAAALgAECgYJBgAAAA==.',
Pa='Pakk:BAAALgAECgMJAwAAAA==.Pandinha:BAACLgAFFH8ZAAIGAAQJ8B1jWAA3AQAGAAQJ8B1jWAA3AQAuAAQKfzgAAgYACQkEIywMADkDAAYACQkEIywMADkDAAAA.Paolinelli:BAAALgAFFAIJAwABLgAFFAYJEwAYAFwjAA==.Pattêrn:BAAALgAECgYJDQAAAA==.',
Pd='Pdr:BAAALgADCgcJBwAAAA==.',
Pe='Pedri:BAABLgAFFH8KAAMGAAMJQhnpfQD7AAAGAAMJQhnpfQD7AAAVAAEJlw8QIgBHAAAAAA==.Pedrok:BAAALgAECgQJDAAAAA==.Perses:BAAALgAECgQJBAAAAA==.',
Ph='Phoenixashes:BAAALgADCgIJAgAAAA==.',
Pi='Picklestein:BAAALgAECgEJAQAAAA==.',
Po='Pokz:BAAALgADCgEJAQAAAA==.',
Pr='Priestiality:BAAALgAECgIJBAAAAA==.Promix:BAAALgAECgEJAQAAAA==.Prowl:BAAALgAECgEJAQABLgAFFAcJFgAgAE8ZAA==.Prscilla:BAAALgADCgcJBgAAAA==.',
['Pë']='Përseu:BAAALgAECgMJAwAAAA==.',
Qu='Quixote:BAAALgAECgYJCAAAAA==.',
Ra='Radagast:BAAALgADCgcJDQABLgAFFAQJEAAKADcNAA==.Radulf:BAAALgAECgQJBAAAAA==.Raph:BAACLgAFFH8TAAIGAAUJAh3vVAA8AQAGAAUJAh3vVAA8AQAuAAQKfyoAAgYACAnmH/01ACACAAYACAnmH/01ACACAAAA.Raphy:BAABLgAFFH8FAAIGAAMJtwnOoQDIAAAGAAMJtwnOoQDIAAABLgAFFAUJEwAGAAIdAA==.Ravyn:BAAALgADCgUJBQAAAA==.',
Re='Reckon:BAAALgAECgYJDAAAAA==.Redthedeer:BAAALgAFFAIJAgAAAA==.Redthedragon:BAAALgAECgEJAQAAAA==.Redthepriest:BAAALgAECgEJAQAAAA==.Redzone:BAAALgAECgQJBgAAAA==.Refuliya:BAAALgADCgkJBwAAAA==.Remmahcm:BAABLgAECn8VAAIJAAgJUBYvPwApAgAJAAgJUBYvPwApAgAAAA==.Renewing:BAAALgADCgQJBAAAAA==.Renrir:BAAALgADCgcJCAAAAA==.Rezen:BAAALgAECgEJAQAAAA==.',
Rh='Rhark:BAAALgAECgUJDQAAAA==.',
Ri='Rikku:BAAALgAFFAIJAwAAAA==.',
Ro='Rook:BAABLgAECn8yAAMJAAkJKyL8CwD+AgAJAAkJKyL8CwD+AgAhAAUJBgi9NACDAAAAAA==.',
Ru='Runnow:BAAALgADCgYJCwAAAA==.',
Sa='Sagas:BAAALgAECgEJAQAAAA==.Salina:BAAALgAECgEJAQABLgAECgMJBQACAAAAAA==.Sammysam:BAAALgADCgUJBwAAAA==.Santairon:BAAALgAECgEJAQAAAA==.Sathor:BAAALgADCgkJDgAAAA==.',
Sc='Scotch:BAAALgADCgQJBAABLgAFFAQJEwAUAGkTAA==.',
Sh='Shaffios:BAAALgAECgYJDAAAAA==.Shelton:BAAALgADCgMJAwABLgADCggJDQACAAAAAA==.Shinjey:BAAALgAECgMJBwAAAA==.Shocker:BAAALgAECgEJAQAAAA==.',
Si='Sil:BAABLgAECn8ZAAIiAAkJCwr1FwCXAQAiAAkJCwr1FwCXAQAAAA==.Silents:BAAALgAECgUJBQAAAA==.Siphon:BAAALgAECgYJDAAAAA==.Siphons:BAAALgAECgMJBAAAAA==.',
Sk='Ska:BAACLgAFFH8bAAIOAAcJvBbYFwDdAQAOAAcJvBbYFwDdAQAuAAQKfxsAAw4ACAm7H1oYAMICAA4ACAm7H1oYAMICAB4AAQkAAJNwADUAAAAA.',
Sl='Slyzete:BAAALgAECgQJBwAAAA==.',
So='Softbutt:BAAALgAECggJEgAAAA==.Sophiae:BAAALgAECgIJAgAAAA==.Sophie:BAAALgADCgcJBwAAAA==.Soulseeker:BAABLgAECn8lAAQOAAgJbhT7TwCmAQAOAAgJKxT7TwCmAQAeAAIJfBRoUAB9AAAjAAEJgBE5OQA3AAAAAA==.',
Sp='Spriz:BAAALgAFFAEJAwAAAA==.',
St='Stölen:BAAALgAECgEJAQAAAA==.',
Sy='Sylthas:BAAALgADCgMJAwAAAA==.Syrensong:BAAALgAECgQJBAAAAA==.',
Ta='Tankli:BAAALgAECgIJBgAAAA==.Tanriel:BAAALgAECgEJAQAAAA==.Tatl:BAAALgAECgIJBAAAAA==.',
Te='Tertletoes:BAABLgAECn8cAAQkAAkJECXvAAC+AwAkAAkJECXvAAC+AwALAAEJ2x46JwBMAAAKAAEJ/h3c2gA5AAAAAA==.Terts:BAAALgAECgEJAQABLgAECgkJHAAkABAlAA==.Teto:BAAALgAECgYJDgAAAA==.',
Th='Thanaz:BAAALgAECgQJBgAAAA==.Thebartender:BAAALgAECgcJDAAAAA==.Thella:BAAALgAECgQJBgAAAA==.Thopowisiwi:BAAALgAFFAIJBAAAAA==.',
To='Tog:BAABLgAECn8bAAIQAAkJciLGAwBVAwAQAAkJciLGAwBVAwAAAA==.Togame:BAAALgAECgUJCAAAAA==.Toggie:BAAALgAECgEJAQAAAA==.Tognahok:BAAALgADCgYJDgAAAA==.Togy:BAAALgADCgEJAQAAAA==.Tortoisetoes:BAAALgAECgIJAgABLgAECgkJHAAkABAlAA==.',
Tr='Tremboladin:BAABLgAECn8aAAIDAAcJHxo1JgD2AQADAAcJHxo1JgD2AQABLgAFFAQJFgACAAAAAA==.',
Ts='Tsnt:BAAALgAECgEJAQAAAA==.',
Tu='Turbosocks:BAAALgAECgIJBQAAAA==.Turok:BAAALgADCgMJAwAAAA==.Turtles:BAAALgADCgEJAQABLgAECgkJHAAkABAlAA==.Tuskydin:BAAALgADCgcJCQAAAA==.',
Ty='Tydrin:BAAALgAECgIJAwAAAA==.Tylandord:BAAALgADCgEJAQAAAA==.',
['Tý']='Týråél:BAAALgADCgYJCwAAAA==.',
Ur='Urra:BAABLgAECn8rAAIcAAgJEB4rHQDsAQAcAAgJEB4rHQDsAQAAAA==.',
Va='Vai:BAAALgAECgYJCQAAAA==.Valkyrie:BAABLgAFFH8GAAIJAAQJ2xgpLABMAQAJAAQJ2xgpLABMAQABLgAFFAUJEQAEAKMeAA==.Valoo:BAAALgAECgQJCgAAAA==.Valunar:BAAALgADCgUJBQAAAA==.',
Ve='Veyron:BAAALgADCgMJAwAAAA==.',
Vi='Vicar:BAAALgAECgYJCwAAAA==.',
Vo='Voidstrider:BAAALgAECggJEAAAAA==.',
Wa='Wargyu:BAAALgAECgMJAwABLgAFFAYJDAAaABgVAA==.',
We='Weezard:BAACLgAFFH8JAAIEAAQJvAiHZgAUAQAEAAQJvAiHZgAUAQAuAAQKfy8AAgQACQmPFhA5AC4CAAQACQmPFhA5AC4CAAAA.',
Wh='Wheein:BAABLgAECn8jAAIWAAkJ1iHtBgAFAwAWAAkJ1iHtBgAFAwAAAA==.',
Wi='Wingolingo:BAAALgAECgIJAgAAAA==.',
Xe='Xeren:BAAALgADCgEJAQAAAA==.',
Ya='Yaamoonn:BAAALgADCgUJBQAAAA==.',
Ye='Yenn:BAABLgAECn8bAAMOAAkJXhtHFgDPAgAOAAkJXhtHFgDPAgAeAAIJwAEuWgBgAAAAAA==.',
Za='Zardnax:BAAALgAECgIJAgAAAA==.',
Ze='Zenin:BAAALgADCggJFQAAAA==.Zensky:BAAALgAECgMJAwAAAA==.Zenu:BAACLgAFFH8MAAMcAAQJwhSYIAARAQAcAAQJ1hKYIAARAQAlAAMJqg5zDQDVAAAuAAQKfyUAAxwACQlQGxYSAJICABwACQlQGxYSAJICACUABAk1FsklALUAAAAA.',
Zu='Zugg:BAAALgADCgEJAQAAAA==.',
['Çh']='Çhakra:BAAALgAECgUJBwAAAA==.',
['Ðð']='Ððn:BAAALgADCgMJAQAAAA==.',
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
