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
local provider = {region='US',realm='Warsong',name='US',type='weekly',zone=46,date='2026-06-14',data={Ad='Adeyna:BAAALgAECgEJAQAAAA==.Adònis:BAAALgADCgEJAQAAAA==.',
Ae='Aesudan:BAAALgADCgEJAQAAAA==.',
Ah='Aharan:BAABLgAECn80AAIBAAgJ+RBmKgB+AQABAAgJ+RBmKgB+AQAAAA==.',
Ai='Aiona:BAAALgADCgYJDAAAAA==.',
Al='Alandrov:BAAALgADCgEJAQAAAA==.Alexanzalone:BAAALgADCggJCAAAAA==.Allenduin:BAAALgAECgEJAQAAAA==.Alodso:BAAALgADCgEJAQAAAA==.',
An='Angelique:BAAALgAECgYJCgAAAA==.Angryballz:BAAALgAECgYJBwABLgAECgYJDAACAAAAAA==.Angz:BAAALgAECgUJDQAAAA==.Anielor:BAAALgAECgMJBAAAAA==.Anuksuna:BAAALgAFFAEJAQABLgAECgkJHgADAE4XAA==.',
Ar='Arcadia:BAAALgAECgYJDgAAAA==.Arcane:BAACLgAFFH8RAAIEAAUJox4mSABXAQAEAAUJox4mSABXAQAuAAQKfx8AAwQACQngIVwQAEYDAAQACQngIVwQAEYDAAUABQlDJBcFAOkBAAAA.',
As='Asta:BAAALgAECgQJBAAAAA==.',
At='Atulan:BAAALgADCgQJBAAAAA==.',
Au='Austin:BAAALgADCggJFgAAAA==.Automobeer:BAAALgAECgIJBgAAAA==.',
Aw='Awake:BAACLgAFFH8NAAIGAAQJiR1eRQBjAQAGAAQJiR1eRQBjAQAuAAQKfycAAwYABwnJFyBqAJABAAYABwmAFiBqAJABAAcABgnaElYfAEoBAAAA.',
Az='Azazzel:BAAALgADCgEJAQAAAA==.',
Ba='Bambietta:BAAALgAECgYJBgAAAA==.Barebelly:BAAALgAECggJEAAAAA==.',
Be='Bearforce:BAABLgAECn8eAAIIAAkJjxnZCAAbAgAIAAkJjxnZCAAbAgAAAA==.',
Bi='Biggbird:BAABLgAECn8nAAIBAAcJAB2BGwDrAQABAAcJAB2BGwDrAQAAAA==.',
Bl='Blewbawl:BAAALgADCgEJAQAAAA==.Blutwin:BAABLgAECn8sAAIJAAkJThNVSQDpAQAJAAkJThNVSQDpAQAAAA==.Bluud:BAAALgADCgMJAwAAAA==.',
Bo='Bootyhünter:BAAALgAECgEJAwAAAA==.Bossdierr:BAACLgAFFH8bAAMKAAQJxSNWJACWAQAKAAQJxSNWJACWAQALAAQJQg8fBwDkAAAuAAQKfzIAAwoACQkyI4URALQCAAoACQkyI4URALQCAAsACAlCE+QPAEsBAAAA.Bossdisan:BAACLgAFFH8LAAIEAAQJQxqDVgA3AQAEAAQJQxqDVgA3AQAuAAQKfygAAgQABglsJFdXADMCAAQABglsJFdXADMCAAAA.Bossmasster:BAAALgAFFAIJAgAAAA==.Bosswudi:BAABLgAFFH8JAAMMAAIJMRMmCwCJAAANAAIJwRK0FQCgAAAMAAIJihEmCwCJAAAAAA==.',
Br='Brashe:BAABLgAECn8sAAIEAAgJ+A4ufAB9AQAEAAgJ+A4ufAB9AQAAAA==.Breathe:BAAALgAECgQJBAABLgAECgYJCgACAAAAAA==.Brickbeard:BAAALgAECggJDgAAAA==.Bruv:BAABLgAECn8jAAIOAAYJhhU5bwCCAQAOAAYJhhU5bwCCAQABLgAECgkJFQAPAEwYAA==.',
Ca='Calathis:BAAALgAECgEJAQAAAA==.Cazadòr:BAAALgAECgIJAgAAAA==.',
Ch='Chromiepip:BAAALgADCgMJAwAAAA==.',
Co='Corbann:BAAALgAECgYJCgAAAA==.',
Cr='Creamcheese:BAABLgAECn8aAAIQAAcJUB27LAD8AQAQAAcJUB27LAD8AQAAAA==.Creamy:BAABLgAECn8yAAIRAAkJ+xpcFQBFAgARAAkJ+xpcFQBFAgAAAA==.Crossbreed:BAABLgAFFH8FAAIQAAIJ1BI0UAB9AAAQAAIJ1BI0UAB9AAAAAA==.',
Cy='Cyr:BAAALgADCgUJBQAAAA==.Cytosine:BAAALgAFFAEJAQAAAA==.',
Da='Daddyhaz:BAACLgAFFH8SAAIKAAYJThYKIwCdAQAKAAYJThYKIwCdAQAuAAQKf0MAAgoACQmzJIIEADwDAAoACQmzJIIEADwDAAAA.Daddywhyudie:BAAALgADCgEJAQAAAA==.Daelyte:BAAALgAECgYJDwAAAA==.Daghor:BAABLgAFFH8IAAINAAIJPiLsLQCzAAANAAIJPiLsLQCzAAABLgAFFAQJBQAEAHYJAA==.',
De='Deltron:BAAALgAECgEJAQAAAA==.Desetre:BAAALgADCgIJAgAAAA==.Desmodus:BAAALgAECgIJAgAAAA==.',
Di='Diabos:BAAALgAECgYJBwABLgAFFAQJFgACAAAAAA==.Dinks:BAABLgAECn9MAAMEAAkJihn/KgBsAgAEAAkJihn/KgBsAgAFAAEJJRNvFQA6AAAAAA==.Ditzy:BAAALgAECgEJAQAAAA==.',
Do='Docc:BAABLgAECn8XAAINAAkJGA+nFgBXAgANAAkJGA+nFgBXAgAAAA==.Domdps:BAAALgAECgEJAQAAAA==.',
Dr='Draan:BAAALgADCgUJBwAAAA==.Dragorr:BAAALgADCgcJBwAAAA==.Dreadpanda:BAAALgADCgMJAwABLgAFFAQJEAASAAIlAA==.Drekkarn:BAAALgADCgMJBgAAAA==.Drood:BAAALgAECgQJCgAAAA==.',
El='Elzath:BAAALgADCggJEAABLgAECgkJIwATAIkUAA==.',
En='Enix:BAAALgADCgYJBgABLgAFFAIJCAAQALwTAA==.',
Er='Erdrick:BAAALgAECgIJBQAAAA==.',
Es='Espeon:BAAALgAECgcJDgAAAA==.',
Eu='Eudisius:BAAALgADCgEJAQAAAA==.',
Ev='Evara:BAABLgAECn8UAAIEAAYJAwdU7gAcAQAEAAYJAwdU7gAcAQAAAA==.',
Fa='Faded:BAAALgAECgYJEwAAAA==.Fangbot:BAAALgAECgEJAgAAAA==.Farmchicken:BAAALgAECgUJBQAAAA==.',
Fe='Felcaas:BAAALgADCgQJBAAAAA==.Felini:BAABLgAECn8fAAIRAAkJsAfCOwBXAQARAAkJsAfCOwBXAQAAAA==.Feronar:BAABLgAECn8uAAIRAAkJ+wuPLgCWAQARAAkJ+wuPLgCWAQAAAA==.',
Fi='Fizzwater:BAAALgAECgYJEAAAAA==.',
Fl='Fleepity:BAAALgAECgcJEAAAAA==.Floopity:BAAALgADCgYJBwAAAA==.Flowermom:BAAALgAECgEJAwAAAA==.Flume:BAACLgAFFH8FAAINAAMJvgLTLgCpAAANAAMJvgLTLgCpAAAuAAQKfxoAAwwACQmPFwwKAJgBAA0ABglmFsEaAL8BAAwACAlmEQwKAJgBAAAA.',
Fu='Fusíon:BAEBLgAECn8zAAIKAAkJeiIwDgANAwAKAAkJeiIwDgANAwAAAA==.',
Gi='Gin:BAACLgAFFH8VAAIUAAUJaRNZFwAEAQAUAAUJaRNZFwAEAQAuAAQKfzIAAhQACQkuG20XAPYBABQACQkuG20XAPYBAAAA.',
Gj='Gjana:BAAALgAFFAIJBAABLgAFFAQJCQAEALwIAA==.',
Gl='Glamdring:BAAALgADCgMJAwAAAA==.Glunty:BAAALgAECgUJCAAAAA==.',
Go='Goldpaw:BAAALgADCgEJAQAAAA==.Gorlash:BAAALgAECgcJCAAAAA==.',
Gr='Gridinn:BAAALgADCgIJAgAAAA==.Grimdark:BAAALgAECgYJCQAAAA==.Grimfeather:BAAALgAECgYJBgAAAA==.Grimgeth:BAACLgAFFH8WAAMGAAUJKxSaagAiAQAGAAQJKxSaagAiAQAHAAMJ9AyAMgBtAAAuAAQKf0IABAYACQlsIRgQAOoCAAYACQmQIBgQAOoCAAcAAwlXH145AKwAABUAAwlOFCItAGkAAAAA.Grimwrath:BAAALgAECgUJBwABLgAFFAUJFgAGACsUAA==.',
Gu='Gugaman:BAAALgADCgcJDgAAAA==.Guishin:BAAALgAECgEJBAAAAA==.',
He='Healpls:BAAALgAECgEJAgAAAA==.Heidriel:BAAALgAECgMJAwAAAA==.Herumesu:BAAALgAFFAEJAQABLgAFFAYJFQAGACEaAA==.Heshan:BAAALgADCgEJAQAAAA==.',
Ho='Holapes:BAAALgAECgUJEAABLgAECgMJBAACAAAAAA==.',
Hu='Huhbruh:BAAALgAECgIJAgABLgAECgkJFQAPAEwYAA==.',
Hw='Hwasa:BAABLgAECn8jAAISAAkJ4h1WDABvAgASAAkJ4h1WDABvAgAAAA==.',
Il='Illigari:BAAALgAFFAEJAQAAAA==.',
In='Indy:BAAALgAECgEJAgAAAA==.Insanities:BAABLgAECn9cAAIWAAkJhiXNAADdAwAWAAkJhiXNAADdAwAAAA==.Inti:BAABLgAECn8WAAIDAAYJZhsGMACYAQADAAYJZhsGMACYAQABLgAFFAIJCAAQALwTAA==.',
Iz='Izumisakai:BAAALgAFFAIJAwABLgAFFAYJFQAGACEaAA==.',
Ja='Jaidie:BAABLgAECn8WAAIXAAcJsAmjGADpAAAXAAcJsAmjGADpAAAAAA==.',
Je='Jeffreyx:BAAALgAECgYJCAAAAA==.Jeffreyz:BAAALgADCgYJBgAAAA==.Jerlonge:BAAALgAECgEJAQAAAA==.',
Jo='Joak:BAAALgADCgUJBQAAAA==.Jota:BAAALgADCgcJCAAAAA==.',
Ka='Kahlune:BAAALgAECgEJAQABLgAECgkJHgADAE4XAA==.Kahlán:BAABLgAECn8eAAIDAAkJThdNHwAHAgADAAkJThdNHwAHAgAAAA==.Karlangas:BAAALgAECgMJBAAAAA==.',
Ki='Kifu:BAAALgAECgQJCAABLgAFFAQJCQAEALwIAA==.Kikipants:BAAALgADCgEJAQAAAA==.Kitrix:BAAALgADCgUJBQAAAA==.Kitty:BAABLgAFFH8GAAITAAMJDgSOIgCIAAATAAMJDgSOIgCIAAABLgAFFAQJDgAIAHYHAA==.',
Kr='Krue:BAAALgADCggJDQAAAA==.',
Ku='Kubimage:BAABLgAECn8aAAIEAAkJKhu2MgCoAgAEAAkJKhu2MgCoAgAAAA==.',
La='Laguna:BAAALgAECgkJBAAAAA==.Lane:BAAALgADCgEJAQAAAA==.Layona:BAAALgAECgYJCgAAAA==.',
Le='Lerroy:BAAALgADCgcJCQAAAA==.',
Li='Liana:BAAALgAECgEJAQAAAA==.Lildar:BAABLgAECn8nAAIGAAgJnho0QwD3AQAGAAgJnho0QwD3AQAAAA==.Linelli:BAAALgAFFAIJBAABLgAFFAcJFAAYACQiAA==.Lirra:BAAALgAFFAIJBAABLgAFFAIJCAAQALwTAA==.',
Lo='Londo:BAAALgAECgUJBgAAAA==.Lorthiel:BAAALgADCgIJAgAAAA==.Lothus:BAACLgAFFH8IAAIZAAIJgh7BdQCmAAAZAAIJgh7BdQCmAAAuAAQKfxUAAxkACQkPGzAYAHgCABkACQkPGzAYAHgCABcAAQl2BGOTACcAAAEuAAUUAgkIABAAvBMA.Lox:BAAALgAECgYJCQAAAA==.',
Ls='Lsblkxd:BAAALgADCgYJBgAAAA==.',
Lu='Lumen:BAAALgAECgIJAgAAAA==.Lumverjvcked:BAABLgAECn8VAAIPAAcJTBhRMADxAQAPAAcJTBhRMADxAQAAAA==.',
Lx='Lxrbread:BAACLgAFFH8ZAAMaAAQJZA3nNADsAAAaAAQJZA3nNADsAAATAAEJ5QPaGAA8AAAuAAQKfzoABBoACQn4FZkeAOIBABoACQnXFZkeAOIBABMABQlBBdY3AK0AABsAAgmoCp4kADcAAAAA.',
['Lë']='Lëgitz:BAABLgAECn8lAAMPAAkJuR/9CwD4AgAPAAkJuR/9CwD4AgAcAAgJIBTqLQCIAQAAAA==.',
Ma='Macca:BAAALgAECgUJBQABLgAECgYJDAACAAAAAA==.Maccazilla:BAAALgAECgYJDAAAAA==.Magdalena:BAACLgAFFH8WAAIUAAUJcSQHCACTAQAUAAUJcSQHCACTAQAuAAQKfyYAAhQACQkXJb8CAG0DABQACQkXJb8CAG0DAAAA.Magedand:BAAALgAECgMJAwAAAA==.Magnesson:BAAALgAFFAEJAgAAAA==.Manakaren:BAAALgADCggJDAAAAA==.Martini:BAAALgADCgEJAQAAAA==.Mavja:BAAALgAECgEJAQAAAA==.Mazuro:BAACLgAFFH8fAAINAAcJLxn8CQD1AQANAAcJLxn8CQD1AQAuAAQKfzMAAw0ACQm5HWwJAI0CAA0ACQm5HWwJAI0CAAwAAQlGGVodAEAAAAAA.',
Me='Meatkleaver:BAABLgAECn8bAAMVAAkJ0BUhAwBnAgAVAAkJ0BUhAwBnAgAGAAEJqAGXNgEiAAAAAA==.Meau:BAABLgAECn8jAAIdAAkJmh4LBgCJAgAdAAkJmh4LBgCJAgAAAA==.Mechadar:BAAALgAECgMJAwAAAA==.Mechanizedtv:BAACLgAFFH8RAAIIAAQJ7iPEBQCbAQAIAAQJ7iPEBQCbAQAuAAQKf+oABAgACQmwJkoAAIMDAAgACQmwJkoAAIMDAB0ACAm8JMACAPMCAAEAAQlmAlWjABwAAAAA.',
Mi='Mitskí:BAAALgAECgQJBAAAAA==.',
Mo='Mongerasta:BAAALgAECgMJBwAAAA==.Monkerooz:BAAALgAECgUJCAAAAA==.Moodeng:BAAALgADCgYJBwAAAA==.Morphîne:BAACLgAFFH8IAAIQAAIJvBPSUwBxAAAQAAIJvBPSUwBxAAAuAAQKfxcAAhAABwkZHvEoABACABAABwkZHvEoABACAAAA.',
Mu='Mugwump:BAAALgAECggJEwAAAA==.Murdõk:BAAALgAECgEJAQABLgAFFAIJBQAGALsMAA==.Murdøk:BAACLgAFFH8FAAMGAAIJuwx54wCAAAAGAAIJuwx54wCAAAAVAAEJhgO9KwA0AAAuAAQKfx0ABAYACQmuGCJcALEBAAYACQmuGCJcALEBAAcAAQnpDThEADgAABUAAQmqCQU9ACsAAAAA.',
My='Mythic:BAABLgAECn8pAAIUAAkJdBtUDgBgAgAUAAkJdBtUDgBgAgAAAA==.',
['Mû']='Mûrdok:BAAALgAECgUJDQABLgAFFAIJBQAGALsMAA==.',
['Mü']='Mürdok:BAAALgAECgYJDAABLgAFFAIJBQAGALsMAA==.',
Ne='Necromortas:BAAALgAECgcJBwAAAA==.Nefarius:BAABLgAECn8WAAMOAAkJLhvqWQCQAQAOAAgJLhvqWQCQAQAeAAMJWxRgOwDGAAABLgAFFAEJAQACAAAAAA==.Neph:BAABLgAECn8aAAMfAAkJQw96HwDlAQAfAAkJQw96HwDlAQAWAAIJbgNeUABNAAAAAA==.Nezot:BAAALgAECgEJAQAAAA==.',
Ni='Nihilism:BAAALgADCgYJBgAAAA==.Ninsu:BAAALgAECgYJCgAAAA==.Nishale:BAAALgAECgMJBQAAAA==.',
No='Noir:BAAALgADCgQJBAAAAA==.',
Nu='Nutdraggin:BAAALgADCgcJBwAAAA==.',
Ny='Nyki:BAAALgAECggJDwAAAA==.',
On='Onlyfist:BAAALgAECgEJAgAAAA==.',
Op='Opius:BAAALgAECgkJEgAAAA==.',
Or='Orcmagic:BAAALgADCgcJCQAAAA==.',
Os='Oshift:BAAALgAECgYJBgAAAA==.',
Ot='Othorion:BAAALgADCgEJAQAAAA==.',
Pa='Pakk:BAAALgAECgUJBwAAAA==.Pandinha:BAACLgAFFH8ZAAIGAAQJ8B2AYAAwAQAGAAQJ8B2AYAAwAQAuAAQKfzgAAgYACQkEIywMADkDAAYACQkEIywMADkDAAAA.Paolinelli:BAAALgAFFAIJAwABLgAFFAcJFAAYACQiAA==.Pattêrn:BAAALgAECgYJEwAAAA==.',
Pd='Pdr:BAAALgADCgcJBwAAAA==.',
Pe='Pedri:BAABLgAFFH8KAAMGAAMJQhk8hwD2AAAGAAMJQhk8hwD2AAAVAAEJlw85JgBHAAAAAA==.Pedrok:BAAALgAECgUJDQAAAA==.Perses:BAAALgAECgYJCgAAAA==.',
Ph='Phoenixashes:BAAALgADCgIJAgAAAA==.',
Pi='Picklestein:BAAALgAECgEJAQAAAA==.',
Po='Pokz:BAAALgADCgEJAQAAAA==.',
Pr='Priestiality:BAAALgAECgIJBAAAAA==.Promix:BAAALgAECgEJAQAAAA==.Prowl:BAAALgAECgEJAQABLgAFFAgJFwAgAGsYAA==.Prscilla:BAAALgADCgcJBgAAAA==.',
['Pë']='Përseu:BAAALgAECgMJAwAAAA==.',
Qu='Quixote:BAAALgAECgYJCAAAAA==.',
Ra='Radagast:BAAALgADCgcJDQABLgAFFAQJFAAKADcNAA==.Radulf:BAAALgAECgQJBAAAAA==.Raph:BAACLgAFFH8VAAIGAAYJIRoSLwChAQAGAAYJIRoSLwChAQAuAAQKfyoAAgYACAnmH1U4ABwCAAYACAnmH1U4ABwCAAAA.Raphy:BAABLgAFFH8GAAIGAAMJdArDrADCAAAGAAMJdArDrADCAAABLgAFFAYJFQAGACEaAA==.Ravyn:BAAALgADCgUJBQAAAA==.',
Re='Reckon:BAAALgAECgYJDAAAAA==.Redthedeer:BAAALgAFFAIJAgAAAA==.Redthedragon:BAAALgAECgEJAQAAAA==.Redthepriest:BAAALgAECgEJAQAAAA==.Redzone:BAAALgAECgQJBgAAAA==.Refuliya:BAAALgADCgkJBwAAAA==.Remmahcm:BAABLgAECn8VAAIJAAgJUBYvPwApAgAJAAgJUBYvPwApAgAAAA==.Renewing:BAAALgADCgQJBAAAAA==.Renrir:BAAALgADCgcJCAAAAA==.Rezen:BAAALgAFFAIJAgAAAA==.',
Rh='Rhark:BAAALgAECgUJDQAAAA==.',
Ri='Rikku:BAAALgAFFAIJAwAAAA==.',
Ro='Rook:BAABLgAECn8yAAMJAAkJKyIgDQD7AgAJAAkJKyIgDQD7AgAhAAUJBgjaNgCCAAAAAA==.',
Ru='Runnow:BAAALgADCgYJCwAAAA==.',
Sa='Sagas:BAAALgAFFAMJAwAAAA==.Salina:BAAALgAECgEJAQABLgAECgMJBQACAAAAAA==.Sammysam:BAAALgADCgUJBwAAAA==.Santairon:BAAALgAECgEJAQAAAA==.Sathor:BAAALgADCgkJDgAAAA==.',
Sc='Scotch:BAAALgADCgQJBAABLgAFFAUJFQAUAGkTAA==.',
Sh='Shaffios:BAAALgAECgYJDAAAAA==.Shelton:BAAALgADCgMJAwABLgADCggJDQACAAAAAA==.Shinjey:BAAALgAECgMJBwAAAA==.Shocker:BAAALgAECgEJAQAAAA==.',
Si='Sil:BAABLgAECn8ZAAIiAAkJCwr1FwCXAQAiAAkJCwr1FwCXAQAAAA==.Silents:BAAALgAECgUJBQAAAA==.Siphon:BAAALgAECgYJDAAAAA==.Siphons:BAAALgAECgMJBAAAAA==.',
Sk='Ska:BAACLgAFFH8bAAIOAAcJvBaMHQDUAQAOAAcJvBaMHQDUAQAuAAQKfxsAAw4ACAm7H1oYAMICAA4ACAm7H1oYAMICAB4AAQkAAJNwADUAAAAA.',
Sl='Slyzete:BAAALgAECgQJBwAAAA==.',
So='Softbutt:BAAALgAECggJEgAAAA==.Sophiae:BAAALgAECgIJAgAAAA==.Sophie:BAAALgADCgcJBwAAAA==.Soulseeker:BAABLgAECn8oAAQOAAgJChUgSQC/AQAOAAgJyBQgSQC/AQAeAAIJfBRoUAB9AAAjAAEJgBGOPAA3AAAAAA==.',
Sp='Spriz:BAAALgAFFAEJAwAAAA==.',
St='Stölen:BAAALgAECgEJAQAAAA==.',
Sy='Sylthas:BAAALgADCgMJAwAAAA==.Syrensong:BAAALgAECgQJBAAAAA==.',
Ta='Tankli:BAAALgAECgIJBgAAAA==.Tanriel:BAAALgAECgEJAQAAAA==.Tatl:BAAALgAECgIJBgAAAA==.',
Te='Tertletoes:BAABLgAECn8cAAQkAAkJECXvAAC+AwAkAAkJECXvAAC+AwALAAEJ2x46JwBMAAAKAAEJ/h3c2gA5AAAAAA==.Terts:BAAALgAECgEJAQABLgAECgkJHAAkABAlAA==.Teto:BAAALgAECgYJDgAAAA==.',
Th='Thanaz:BAAALgAECgQJCAAAAA==.Thebartender:BAAALgAECgcJDAAAAA==.Thella:BAAALgAECgQJBgAAAA==.Thopowisiwi:BAAALgAFFAIJBAAAAA==.',
To='Tog:BAABLgAECn8bAAIQAAkJciLGAwBVAwAQAAkJciLGAwBVAwAAAA==.Togame:BAAALgAECgUJCAAAAA==.Toggie:BAAALgAECgEJAQAAAA==.Tognahok:BAAALgADCgYJDgAAAA==.Togy:BAAALgADCgEJAQAAAA==.Tortoisetoes:BAAALgAECgIJAgABLgAECgkJHAAkABAlAA==.',
Tr='Tremboladin:BAABLgAECn8aAAIDAAcJHxo1JgD2AQADAAcJHxo1JgD2AQABLgAFFAQJFgACAAAAAA==.',
Ts='Tsnt:BAAALgAECgEJAQAAAA==.',
Tu='Turbosocks:BAAALgAECgIJBQAAAA==.Turok:BAAALgADCgMJAwAAAA==.Turtles:BAAALgADCgEJAQABLgAECgkJHAAkABAlAA==.Tuskydin:BAAALgADCgcJCQAAAA==.',
Ty='Tydrin:BAAALgAECgIJAwAAAA==.Tylandord:BAAALgADCgEJAQAAAA==.',
['Tý']='Týråél:BAAALgADCgYJCwAAAA==.',
Ur='Urra:BAABLgAECn8rAAIcAAgJEB6tHgDrAQAcAAgJEB6tHgDrAQAAAA==.',
Va='Vai:BAAALgAECgYJCQAAAA==.Valkyrie:BAABLgAFFH8GAAIJAAQJ2xgTMwBFAQAJAAQJ2xgTMwBFAQABLgAFFAUJEQAEAKMeAA==.Valoo:BAAALgAECgQJCgAAAA==.Valunar:BAAALgADCgUJBQAAAA==.',
Ve='Veyron:BAAALgADCgMJAwAAAA==.',
Vi='Vicar:BAAALgAECgYJCwAAAA==.',
Vo='Voidstrider:BAAALgAECggJEAAAAA==.',
Wa='Wargyu:BAAALgAECgMJAwABLgAFFAYJDAAaABgVAA==.',
We='Weezard:BAACLgAFFH8JAAIEAAQJvAjBbAAOAQAEAAQJvAjBbAAOAQAuAAQKfy8AAgQACQmPFkc7ACoCAAQACQmPFkc7ACoCAAAA.',
Wh='Wheein:BAABLgAECn8jAAIWAAkJ1iFaBwAFAwAWAAkJ1iFaBwAFAwAAAA==.',
Wi='Wingolingo:BAAALgAECgIJAgAAAA==.',
Xe='Xeren:BAAALgADCgEJAQAAAA==.',
Ya='Yaamoonn:BAAALgADCgUJBQAAAA==.',
Ye='Yenn:BAABLgAECn8bAAMOAAkJXhtHFgDPAgAOAAkJXhtHFgDPAgAeAAIJwAEuWgBgAAAAAA==.',
Za='Zardnax:BAAALgAECgIJAgAAAA==.',
Ze='Zenin:BAAALgADCggJFQAAAA==.Zensky:BAAALgAECgMJAwAAAA==.Zenu:BAACLgAFFH8MAAMcAAQJwhRFIwAIAQAcAAQJ1hJFIwAIAQAlAAMJqg4zDwDOAAAuAAQKfyUAAxwACQlQGxYSAJICABwACQlQGxYSAJICACUABAk1Fq8nALQAAAAA.',
Zu='Zugg:BAAALgADCgEJAQAAAA==.',
['Çh']='Çhakra:BAAALgAECgUJBwAAAA==.',
['Ðð']='Ððn:BAAALgADCgMJAQAAAA==.',
['Øm']='Ømen:BAAALgADCgYJBgAAAA==.',
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
