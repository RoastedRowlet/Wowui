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

local lookup = {'Druid-Balance','Unknown-Unknown','Paladin-Holy','Mage-Frost','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Assassination','Druid-Guardian','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Subtlety','Paladin-Protection','Warlock-Demonology','Shaman-Restoration','Druid-Restoration','Warrior-Fury','Monk-Brewmaster','Priest-Discipline','Evoker-Preservation','Monk-Windwalker','DeathKnight-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Rogue-Outlaw','Evoker-Augmentation','Evoker-Devastation','Shaman-Elemental','Druid-Feral','Warlock-Destruction','Priest-Holy','Priest-Shadow','Warrior-Arms','Warrior-Protection','Warlock-Affliction','DemonHunter-Havoc','Shaman-Enhancement',}
local provider = {region='US',realm='Warsong',name='US',type='weekly',zone=46,date='2026-06-28',data={Ad='Adeyna:BAAALgAECgEJAQAAAA==.Adònis:BAAALgADCgEJAQAAAA==.',
Ae='Aesudan:BAAALgADCgEJAQAAAA==.',
Ah='Aharan:BAABLgAECn88AAIBAAkJFhHBAwAfAQABAAkJFhHBAwAfAQAAAA==.',
Ai='Aiona:BAAALgADCgYJDAAAAA==.',
Al='Alandrov:BAAALgADCgEJAQAAAA==.Alexanzalone:BAAALgADCggJCAAAAA==.Allenduin:BAAALgAECgEJAQAAAA==.Alocasia:BAAALgAECgEJAQAAAA==.Alodso:BAAALgADCgEJAQAAAA==.',
An='Angelique:BAAALgAECgYJCgAAAA==.Angryballz:BAAALgAECgYJBwABLgAECgYJDQACAAAAAA==.Angz:BAAALgAECgUJDQAAAA==.Anielor:BAAALgAECgMJBAAAAA==.Anuksuna:BAAALgAFFAEJAQABLgAFFAIJBQADAD8JAA==.',
Ar='Arcadia:BAAALgAECgYJDgAAAA==.Arcane:BAACLgAFFH8RAAIEAAUJox6sSQBPAQAEAAUJox6sSQBPAQAuAAQKfx8AAwQACQngIVwQAEYDAAQACQngIVwQAEYDAAUABQlDJBcFAOkBAAAA.Arèana:BAAALgADCgMJAwAAAA==.',
As='Asta:BAAALgAECgQJBAAAAA==.Astrea:BAAALgAFFAEJAQAAAA==.',
At='Atulan:BAAALgADCgQJBAAAAA==.',
Au='Austin:BAAALgADCggJFgAAAA==.Automobeer:BAAALgAECgUJCQAAAA==.',
Aw='Awake:BAACLgAFFH8TAAIGAAQJiR1OSABiAQAGAAQJiR1OSABiAQAuAAQKfycAAwYABwnJFxZrAI8BAAYABwmAFhZrAI8BAAcABgnaElYfAEoBAAAA.',
Az='Azazzel:BAAALgADCgEJAQAAAA==.',
Ba='Bambietta:BAABLgAECn8bAAIIAAgJQRF4AACXAQAIAAgJQRF4AACXAQAAAA==.Barebelly:BAAALgAECggJEAAAAA==.',
Be='Bearforce:BAABLgAECn8eAAIJAAkJjxnZCAAbAgAJAAkJjxnZCAAbAgAAAA==.',
Bi='Biggbird:BAACLgAFFH8HAAIBAAIJBA4+EACAAAABAAIJBA4+EACAAAAuAAQKfysAAgEACAntHZ4SAEECAAEACAntHZ4SAEECAAAA.',
Bl='Blewbawl:BAAALgADCgEJAQAAAA==.Blutwin:BAABLgAECn8sAAIKAAkJThMbSgDoAQAKAAkJThMbSgDoAQAAAA==.Bluud:BAAALgADCgMJAwAAAA==.',
Bo='Bootyhünter:BAAALgAECgEJAwAAAA==.Bossdierr:BAACLgAFFH8bAAMLAAQJxSMxJgCUAQALAAQJxSMxJgCUAQAMAAQJQg9WBwDkAAAuAAQKfzIAAwsACQkyI74RALQCAAsACQkyI74RALQCAAwACAlCExQQAEsBAAAA.Bossdisan:BAACLgAFFH8LAAIEAAQJQxq6WAAsAQAEAAQJQxq6WAAsAQAuAAQKfygAAgQABglsJFdXADMCAAQABglsJFdXADMCAAAA.Bossmasster:BAAALgAFFAIJAgABLgAFFAIJCQAIADETAA==.Bosswudi:BAABLgAFFH8JAAMIAAIJMRNWCwCJAAANAAIJwRK0FQCgAAAIAAIJihFWCwCJAAAAAA==.',
Br='Brashe:BAABLgAECn8wAAIEAAgJ+w6KDgDZAAAEAAgJ+w6KDgDZAAAAAA==.Breakahorde:BAAALgAECgEJAQAAAA==.Breathe:BAAALgAECgQJBAABLgAECgYJCgACAAAAAA==.Brickbeard:BAABLgAECn8UAAQOAAgJWBMkKgDIAAAOAAYJUg0kKgDIAAADAAgJPwlUBgC5AAAKAAIJBwvQMgAuAAAAAA==.Brofasa:BAAALgAECgEJAQAAAA==.Bruv:BAABLgAECn8jAAIPAAYJhhU5bwCCAQAPAAYJhhU5bwCCAQABLgAECgkJFQAQAEwYAA==.',
Ca='Calathis:BAAALgAECgEJAQAAAA==.Cazadòr:BAAALgAECgIJAgAAAA==.',
Ch='Chromiepip:BAAALgADCgMJAwAAAA==.',
Co='Corbann:BAAALgAECgYJCgAAAA==.',
Cr='Creamcheese:BAABLgAECn8aAAIRAAcJUB27LAD8AQARAAcJUB27LAD8AQAAAA==.Creamy:BAABLgAECn8zAAISAAkJ+xoNFQBHAgASAAkJ+xoNFQBHAgAAAA==.Crossbreed:BAABLgAFFH8FAAIRAAIJ1BKiUQB9AAARAAIJ1BKiUQB9AAAAAA==.',
Cy='Cyr:BAAALgADCgUJBQAAAA==.Cytosine:BAAALgAFFAEJAQAAAA==.',
Da='Daddyhaz:BAACLgAFFH8WAAILAAYJyRcNJQCaAQALAAYJyRcNJQCaAQAuAAQKf0MAAgsACQmzJKUEADwDAAsACQmzJKUEADwDAAAA.Daddywhyudie:BAAALgADCgEJAQAAAA==.Daelyte:BAAALgAECgYJDwAAAA==.Daghor:BAABLgAFFH8IAAINAAIJPiL3LgCzAAANAAIJPiL3LgCzAAAAAA==.',
De='Deltron:BAAALgAECgEJAQABLgAECgkJEgACAAAAAA==.Desetre:BAAALgADCgIJAgAAAA==.Desmodus:BAAALgAECgIJAgAAAA==.',
Di='Diabos:BAAALgAECgYJBwABLgAFFAQJFgACAAAAAA==.Dinks:BAABLgAECn9TAAMEAAkJQRxjBQCJAQAEAAkJQRxjBQCJAQAFAAEJJRPuFQA6AAAAAA==.Ditzy:BAAALgAECgEJAQAAAA==.Divineßovine:BAAALgADCgEJAQAAAA==.',
Do='Docc:BAABLgAECn8XAAINAAkJGA+nFgBXAgANAAkJGA+nFgBXAgAAAA==.Domdps:BAAALgAECgEJAQAAAA==.',
Dr='Draan:BAAALgADCgUJBwAAAA==.Dragorr:BAAALgADCgcJBwAAAA==.Drakkia:BAAALgAECgEJAgAAAA==.Dreadpanda:BAAALgADCgMJAwABLgAFFAQJEAATAAIlAA==.Drekkarn:BAAALgADCgMJBgABLgAECgkJZwAUAOYlAA==.Drood:BAAALgAECgcJEAAAAA==.',
El='Elzath:BAAALgADCggJEAABLgAECgkJIwAVAIkUAA==.',
En='Enix:BAAALgADCgYJBgABLgAFFAIJCAARALwTAA==.',
Er='Erdrick:BAAALgAECgIJBQAAAA==.',
Es='Espeon:BAAALgAECgcJDgAAAA==.',
Eu='Eudisius:BAAALgADCgEJAQAAAA==.',
Ev='Evara:BAABLgAECn8UAAIEAAYJAwdU7gAcAQAEAAYJAwdU7gAcAQAAAA==.',
Fa='Faded:BAABLgAECn8aAAIUAAcJRBwtAQAWAgAUAAcJRBwtAQAWAgAAAA==.Fangbot:BAAALgAECgEJAgAAAA==.Farmchicken:BAAALgAFFAIJAgAAAA==.',
Fe='Felcaas:BAAALgADCgQJBAAAAA==.Felini:BAABLgAECn8fAAISAAkJsAcvPQBRAQASAAkJsAcvPQBRAQAAAA==.Feronar:BAABLgAECn8wAAISAAkJPQ3LLwCPAQASAAkJPQ3LLwCPAQAAAA==.',
Fi='Fizzwater:BAAALgAECgYJEAAAAA==.',
Fl='Fleepity:BAAALgAECgcJEAAAAA==.Floopity:BAAALgADCgYJBwAAAA==.Flowermom:BAAALgAECgEJAwAAAA==.Flume:BAACLgAFFH8FAAINAAMJvgLULwCoAAANAAMJvgLULwCoAAAuAAQKfxoAAwgACQmPFxsKAJgBAA0ABglmFjkbAL0BAAgACAlmERsKAJgBAAAA.',
Fu='Fusíon:BAEBLgAECn8zAAILAAkJeiIwDgANAwALAAkJeiIwDgANAwAAAA==.',
Gi='Gin:BAACLgAFFH8WAAIWAAUJaRPqFwADAQAWAAUJaRPqFwADAQAuAAQKfzIAAhYACQkuG7wXAPYBABYACQkuG7wXAPYBAAAA.',
Gj='Gjana:BAAALgAFFAIJBAABLgAFFAUJCgAEALwIAA==.',
Gl='Glamdring:BAAALgADCgMJAwAAAA==.Glunty:BAAALgAECgUJCAAAAA==.',
Go='Goldpaw:BAAALgADCgEJAQAAAA==.Gorlash:BAAALgAECgcJCAAAAA==.',
Gr='Gridinn:BAAALgADCgIJAgAAAA==.Grimdark:BAAALgAECgcJEwAAAA==.Grimfeather:BAAALgAECgYJEAAAAA==.Grimgeth:BAACLgAFFH8XAAMGAAUJKxSSbQAhAQAGAAQJKxSSbQAhAQAHAAQJYQwkNABoAAAuAAQKf0QABAYACQnVIWQQAOkCAAYACQn6IGQQAOkCAAcAAwlXH+Q5AKwAABcAAwlOFOktAGkAAAAA.Grimwrath:BAAALgAECgUJBwABLgAFFAUJFwAGACsUAA==.',
Gu='Gugaman:BAAALgADCgcJDgAAAA==.Guishin:BAAALgAECgEJBgAAAA==.',
He='Healpls:BAAALgAECgEJAgAAAA==.Heidriel:BAAALgAECgMJAwAAAA==.Herumesu:BAAALgAFFAEJAQABLgAFFAcJGgAGAH4cAA==.Heshan:BAAALgADCgcJCwAAAA==.',
Ho='Holapes:BAAALgAECgUJEAABLgAECgMJBAACAAAAAA==.',
Hu='Huhbruh:BAAALgAECgIJAgABLgAECgkJFQAQAEwYAA==.',
Hw='Hwasa:BAABLgAECn8jAAITAAkJ4h1zDABuAgATAAkJ4h1zDABuAgAAAA==.',
Il='Illigari:BAAALgAFFAEJAQAAAA==.',
In='Indy:BAAALgAECgEJAgAAAA==.Insanities:BAABLgAECn9nAAIUAAkJ5iXUAADaAwAUAAkJ5iXUAADaAwAAAA==.Inti:BAABLgAECn8WAAIDAAYJZhtdMACYAQADAAYJZhtdMACYAQABLgAFFAIJCAARALwTAA==.',
Iz='Izumisakai:BAAALgAFFAIJAwABLgAFFAcJGgAGAH4cAA==.',
Ja='Jaidie:BAABLgAECn8cAAIYAAgJow7iAQDLAAAYAAgJow7iAQDLAAAAAA==.',
Je='Jeffreyx:BAAALgAECgYJCAAAAA==.Jeffreyz:BAAALgADCgYJBgAAAA==.Jerlonge:BAAALgAECgEJAgAAAA==.',
Jo='Joak:BAAALgADCgUJBQAAAA==.Jota:BAAALgADCgcJCAAAAA==.',
Ka='Kahlune:BAAALgAECgEJAQABLgAFFAIJBQADAD8JAA==.Kahlán:BAACLgAFFH8FAAIDAAIJPwlVQABhAAADAAIJPwlVQABhAAAuAAQKfx4AAgMACQlOF+AfAAQCAAMACQlOF+AfAAQCAAAA.Karlangas:BAAALgAECgMJBAAAAA==.',
Ki='Kifu:BAAALgAECgQJCAABLgAFFAUJCgAEALwIAA==.Kikipants:BAAALgADCgEJAQAAAA==.Kitrix:BAAALgADCgUJBQAAAA==.Kitty:BAABLgAFFH8GAAIVAAMJDgQwIwCIAAAVAAMJDgQwIwCIAAABLgAFFAQJDgAJAHYHAA==.',
Kn='Knell:BAAALgAECgMJAwAAAA==.',
Kr='Krue:BAAALgADCggJDQAAAA==.',
Ku='Kubimage:BAABLgAECn8aAAIEAAkJKhu2MgCoAgAEAAkJKhu2MgCoAgAAAA==.',
La='Laguna:BAAALgAECgkJBAAAAA==.Lane:BAAALgADCgEJAQAAAA==.Layona:BAAALgAECgYJCgAAAA==.',
Le='Lerroy:BAAALgADCgcJCQAAAA==.',
Li='Liana:BAAALgAECgEJAQAAAA==.Lildar:BAABLgAECn8nAAIGAAgJnhrWQwD3AQAGAAgJnhrWQwD3AQAAAA==.Linelli:BAABLgAFFH8GAAQZAAMJZRyQcAC/AAAZAAIJhSKQcAC/AAAaAAEJJhAKDgBUAAAYAAEJmhABEQBLAAABLgAFFAcJGQAbAD0iAA==.Lirra:BAAALgAFFAIJBAABLgAFFAIJCAARALwTAA==.',
Lo='Londo:BAAALgAECgUJBgAAAA==.Lorthiel:BAAALgADCgIJAgAAAA==.Lothus:BAACLgAFFH8IAAIZAAIJgh6UeQClAAAZAAIJgh6UeQClAAAuAAQKfxUAAxkACQkPGzAYAHgCABkACQkPGzAYAHgCABgAAQl2BGOTACcAAAEuAAUUAgkIABEAvBMA.Lox:BAAALgAECgYJCQAAAA==.',
Ls='Lsblkxd:BAAALgADCgYJBgAAAA==.',
Lu='Lumen:BAAALgAECgIJAgAAAA==.Lumverjvcked:BAABLgAECn8VAAIQAAcJTBjrMADxAQAQAAcJTBjrMADxAQAAAA==.',
Lx='Lxrbread:BAACLgAFFH8ZAAMcAAQJZA1rNgDqAAAcAAQJZA1rNgDqAAAVAAEJ5QPaGAA8AAAuAAQKf0EABBwACQn4FckeAOEBABwACQnXFckeAOEBABUABwlvC1ECAMMAAB0ABAm4C2cCAGQAAAAA.',
['Lë']='Lëgitz:BAABLgAECn8lAAMQAAkJuR89DAD4AgAQAAkJuR89DAD4AgAeAAgJIBR5LgCHAQAAAA==.',
Ma='Macca:BAAALgAECgUJBQABLgAECgYJDQACAAAAAA==.Maccazilla:BAAALgAECgYJDQAAAA==.Magdalena:BAACLgAFFH8cAAIWAAUJcSRtCACSAQAWAAUJcSRtCACSAQAuAAQKfyYAAhYACQkXJb8CAG0DABYACQkXJb8CAG0DAAAA.Magedand:BAAALgAECgMJAwAAAA==.Magnesson:BAAALgAFFAEJAgAAAA==.Maldrax:BAAALgADCgYJBAAAAA==.Manakaren:BAAALgADCggJDAAAAA==.Martini:BAAALgAFFAEJAQAAAA==.Mavja:BAAALgAECgMJBAAAAA==.Mazuro:BAACLgAFFH8fAAINAAcJLxmOCgDzAQANAAcJLxmOCgDzAQAuAAQKfzMAAw0ACQm5HZsJAIsCAA0ACQm5HZsJAIsCAAgAAQlGGVodAEAAAAAA.',
Me='Meatkleaver:BAABLgAECn8bAAMXAAkJ0BUhAwBnAgAXAAkJ0BUhAwBnAgAGAAEJqAGXNgEiAAAAAA==.Meau:BAABLgAECn8jAAIfAAkJmh4hBgCJAgAfAAkJmh4hBgCJAgAAAA==.Mechadar:BAAALgAECgMJAwAAAA==.Mechanizedtv:BAACLgAFFH8UAAIJAAQJ7iMeBgCZAQAJAAQJ7iMeBgCZAQAuAAQKf/AABAkACQmwJk8AAIMDAAkACQmwJk8AAIMDAB8ACAm8JNACAPMCAAEAAQlmAmGlABwAAAAA.',
Mi='Mitskí:BAAALgAECgQJBAAAAA==.',
Mo='Mongerasta:BAAALgAECgMJBwAAAA==.Monkerooz:BAAALgAECgUJCAAAAA==.Moodeng:BAAALgADCgYJBwAAAA==.Morbius:BAAALgAECgMJAwAAAA==.Morphîne:BAACLgAFFH8IAAIRAAIJvBNBVQBxAAARAAIJvBNBVQBxAAAuAAQKfxcAAhEABwkZHvEoABACABEABwkZHvEoABACAAAA.',
Mu='Mugwump:BAAALgAECggJEwAAAA==.Murdõk:BAAALgAECgEJAQABLgAFFAIJBQAGALsMAA==.Murdøk:BAACLgAFFH8FAAMGAAIJuwy06ACAAAAGAAIJuwy06ACAAAAXAAEJhgNKLQA0AAAuAAQKfx0ABAYACQmuGAxdALEBAAYACQmuGAxdALEBAAcAAQnpDThEADgAABcAAQmqCYE+ACoAAAAA.',
My='Mythic:BAABLgAECn8pAAIWAAkJdBuHDgBgAgAWAAkJdBuHDgBgAgAAAA==.',
['Mû']='Mûrdok:BAAALgAFFAEJAQABLgAFFAIJBQAGALsMAA==.',
['Mü']='Mürdok:BAAALgAECgYJDAABLgAFFAIJBQAGALsMAA==.',
Ne='Necromortas:BAAALgAECgcJBwAAAA==.Nefarius:BAABLgAECn8WAAMPAAkJLhscWgCPAQAPAAgJLhscWgCPAQAgAAMJWxRgOwDGAAABLgAFFAEJAQACAAAAAA==.Neph:BAABLgAECn8aAAMhAAkJQw96HwDlAQAhAAkJQw96HwDlAQAUAAIJbgNeUABNAAAAAA==.Nezot:BAAALgAECgUJBgAAAA==.',
Ni='Nihilism:BAAALgADCgYJBgAAAA==.Ninsu:BAAALgAECgYJCgAAAA==.Nishale:BAAALgAECgMJBQABLgAECgUJBgACAAAAAA==.',
No='Noir:BAAALgADCgQJBAAAAA==.',
Nu='Nutdraggin:BAAALgADCgcJBwAAAA==.',
Ny='Nyki:BAABLgAECn8XAAQiAAgJVRcAAgCPAQAiAAcJOxcAAgCPAQAUAAYJ+wsUDABZAAAhAAIJXgosbgA1AAAAAA==.',
Of='Offline:BAAALgAECgUJBQABLgAFFAQJGAAGAKQUAA==.',
On='Onlyfist:BAAALgAECgEJAgAAAA==.',
Op='Opius:BAAALgAECgkJEgAAAA==.',
Or='Orcmagic:BAAALgADCgcJCQAAAA==.',
Os='Oshift:BAAALgAECgYJBgAAAA==.',
Pa='Pakk:BAAALgAECgUJBwABLgAECgkJEgACAAAAAA==.Pandinha:BAACLgAFFH8ZAAIGAAQJ8B1HYwAwAQAGAAQJ8B1HYwAwAQAuAAQKfzgAAgYACQkEIywMADkDAAYACQkEIywMADkDAAAA.Paolinelli:BAABLgAFFH8IAAMjAAQJPB2rBgDlAAAjAAQJeBarBgDlAAASAAMJKB46PQC4AAABLgAFFAcJGQAbAD0iAA==.Pattêrn:BAAALgAECgYJEwAAAA==.',
Pd='Pdr:BAAALgADCgcJBwAAAA==.',
Pe='Pedri:BAABLgAFFH8KAAMGAAMJQhm4igD0AAAGAAMJQhm4igD0AAAXAAEJlw+ZJwBHAAAAAA==.Pedrok:BAAALgAECgUJDQAAAA==.Perses:BAAALgAECgYJCgAAAA==.',
Ph='Phoenixashes:BAAALgADCgIJAgAAAA==.',
Pi='Picklestein:BAAALgAECgEJAQAAAA==.',
Po='Pokz:BAAALgADCgEJAQAAAA==.',
Pr='Priestiality:BAAALgAECgIJBAAAAA==.Promix:BAAALgAECgEJAQAAAA==.Prowl:BAAALgAECgEJAQABLgAFFAgJFwAjAGsYAA==.Prscilla:BAAALgADCgcJBgAAAA==.',
['Pë']='Përseu:BAAALgAECgMJAwAAAA==.',
Qu='Quixote:BAAALgAECgcJCwAAAA==.',
Ra='Radagast:BAAALgADCgcJDQABLgAFFAQJFgALADcNAA==.Radulf:BAAALgAECgQJBAAAAA==.Raph:BAACLgAFFH8aAAIGAAcJfhzrCQCwAQAGAAcJfhzrCQCwAQAuAAQKfyoAAgYACAnmH+A4ABwCAAYACAnmH+A4ABwCAAAA.Raphy:BAABLgAFFH8IAAIGAAMJthBjoADUAAAGAAMJthBjoADUAAABLgAFFAcJGgAGAH4cAA==.Ravyn:BAAALgADCgUJBQAAAA==.',
Re='Reckon:BAAALgAECgYJDAAAAA==.Redthedeer:BAAALgAFFAIJAgAAAA==.Redthedragon:BAAALgAECgEJAQAAAA==.Redthepriest:BAAALgAECgEJAQAAAA==.Redzone:BAAALgAECgQJBgAAAA==.Refuliya:BAAALgADCgkJBwAAAA==.Remmahcm:BAABLgAECn8VAAIKAAgJUBYvPwApAgAKAAgJUBYvPwApAgAAAA==.Renewing:BAAALgADCgQJBAAAAA==.Renrir:BAAALgADCgcJCAAAAA==.Rezen:BAAALgAFFAIJAgAAAA==.',
Rh='Rhark:BAAALgAECgUJDQAAAA==.',
Ri='Rikku:BAABLgAFFH8HAAIIAAIJ1gUQAgCCAAAIAAIJ1gUQAgCCAAAAAA==.',
Ro='Rook:BAABLgAECn8yAAMKAAkJKyJoDQD6AgAKAAkJKyJoDQD6AgAOAAUJBgheNwCCAAAAAA==.',
Ru='Runnow:BAAALgADCgYJCwAAAA==.',
Sa='Saebi:BAAALgADCgkJCQAAAA==.Sagas:BAAALgAFFAMJAwAAAA==.Salina:BAAALgAECgUJBgAAAA==.Sammysam:BAAALgADCgUJBwAAAA==.Santairon:BAAALgAECgEJAgAAAA==.Sathor:BAAALgADCgkJDgAAAA==.',
Sc='Scotch:BAAALgADCgQJBAABLgAFFAUJFgAWAGkTAA==.',
Sh='Shaffios:BAAALgAECgYJDAAAAA==.Shelton:BAAALgADCgMJAwABLgADCggJDQACAAAAAA==.Shinjey:BAAALgAECgMJBwAAAA==.Shocker:BAAALgAECgEJAQAAAA==.',
Si='Sil:BAABLgAECn8ZAAIkAAkJCwr1FwCXAQAkAAkJCwr1FwCXAQAAAA==.Silents:BAAALgAECgUJBQAAAA==.Siphon:BAAALgAECgYJDAAAAA==.Siphons:BAAALgAECgMJBAAAAA==.',
Sk='Ska:BAACLgAFFH8bAAIPAAcJvBaIHwDUAQAPAAcJvBaIHwDUAQAuAAQKfxsAAw8ACAm7H1oYAMICAA8ACAm7H1oYAMICACAAAQkAAJNwADUAAAAA.',
Sl='Slyzete:BAAALgAECgQJBwAAAA==.',
So='Softbutt:BAABLgAECn8aAAISAAgJcQyMAwBGAQASAAgJcQyMAwBGAQAAAA==.Sophiae:BAAALgAECgIJAgAAAA==.Sophie:BAAALgADCgcJBwAAAA==.Soulseeker:BAABLgAECn8qAAQPAAgJChVWSQC+AQAPAAgJyBRWSQC+AQAgAAIJfBRoUAB9AAAlAAEJgBG2CAA2AAAAAA==.',
Sp='Spriz:BAAALgAFFAEJBAAAAA==.',
St='Staby:BAAALgAECgEJAQAAAA==.Stölen:BAAALgAECgEJAQAAAA==.',
Sy='Sylthas:BAAALgADCgMJAwAAAA==.Syrensong:BAAALgAECgQJBAAAAA==.',
Ta='Tankli:BAAALgAECgIJBgAAAA==.Tanriel:BAAALgAECgEJAQAAAA==.Tatl:BAAALgAECgUJCwAAAA==.',
Te='Tertletoes:BAABLgAECn8cAAQmAAkJECXvAAC+AwAmAAkJECXvAAC+AwAMAAEJ2x46JwBMAAALAAEJ/h3c2gA5AAAAAA==.Terts:BAAALgAECgEJAQABLgAECgkJHAAmABAlAA==.Teto:BAAALgAECgYJDgAAAA==.',
Th='Thanaz:BAAALgAECgUJCQAAAA==.Thebartender:BAAALgAECgcJDAAAAA==.Thella:BAAALgAECgQJBgAAAA==.Thopowisiwi:BAAALgAFFAIJBAAAAA==.',
To='Tog:BAABLgAECn8cAAMRAAkJciLGAwBVAwARAAkJciLGAwBVAwABAAEJVxHuDwA0AAAAAA==.Togame:BAAALgAECgUJCAAAAA==.Toggie:BAAALgAECgEJAgAAAA==.Tognahok:BAAALgADCgYJDgAAAA==.Togy:BAAALgADCgEJAQAAAA==.Tortoisetoes:BAAALgAECgIJAgABLgAECgkJHAAmABAlAA==.',
Tr='Tremboladin:BAABLgAECn8aAAIDAAcJHxo1JgD2AQADAAcJHxo1JgD2AQABLgAFFAQJFgACAAAAAA==.Trollsroyce:BAAALgAECgEJAQAAAA==.',
Ts='Tsnt:BAAALgAECgEJAQAAAA==.',
Tu='Turbosocks:BAAALgAECgYJCgAAAA==.Turok:BAAALgADCgMJAwAAAA==.Turtles:BAAALgADCgEJAQABLgAECgkJHAAmABAlAA==.Tuskydin:BAAALgADCgcJCQAAAA==.',
Ty='Tydrin:BAAALgAECgIJAwAAAA==.Tylandord:BAAALgADCgEJAQAAAA==.',
['Tý']='Týråél:BAAALgADCgYJCwAAAA==.',
Ur='Urra:BAABLgAECn8rAAIeAAgJEB4OHwDqAQAeAAgJEB4OHwDqAQAAAA==.',
Va='Vai:BAAALgAECgYJCQAAAA==.Valkyrie:BAABLgAFFH8HAAIKAAQJJx1VNQBEAQAKAAQJJx1VNQBEAQABLgAFFAUJEQAEAKMeAA==.Valoo:BAAALgAECgQJCgAAAA==.Valunar:BAAALgADCgUJBQAAAA==.',
Ve='Veyron:BAAALgADCgMJAwAAAA==.',
Vi='Vicar:BAAALgAECgcJDAAAAA==.',
Vo='Voidstrider:BAAALgAECggJEAAAAA==.',
Wa='Wargyu:BAAALgAECgMJAwABLgAFFAcJDQAcAJITAA==.',
We='Weezard:BAACLgAFFH8KAAIEAAUJvAikbgAFAQAEAAUJvAikbgAFAQAuAAQKfzAAAgQACQmPFvA7ACoCAAQACQmPFvA7ACoCAAAA.',
Wh='Wheein:BAABLgAECn8jAAIUAAkJ1iGCBwACAwAUAAkJ1iGCBwACAwAAAA==.',
Wi='Wingolingo:BAAALgAECgIJAgAAAA==.',
Xe='Xeren:BAAALgADCgEJAQAAAA==.',
Xi='Xioa:BAAALgADCgEJAQAAAA==.',
Ya='Yaamoonn:BAAALgADCgUJBQAAAA==.',
Ye='Yenn:BAABLgAECn8cAAMPAAkJXhtHFgDPAgAPAAkJXhtHFgDPAgAgAAIJwAEuWgBgAAAAAA==.',
Za='Zardnax:BAAALgAECgIJAgAAAA==.',
Ze='Zenin:BAAALgADCggJFQAAAA==.Zensky:BAAALgAECgMJAwAAAA==.Zenu:BAACLgAFFH8MAAMeAAQJwhR9JAAHAQAeAAQJ1hJ9JAAHAQAnAAMJqg7JDwDJAAAuAAQKfyUAAx4ACQlQGxYSAJICAB4ACQlQGxYSAJICACcABAk1FlwoALQAAAAA.',
Zu='Zugg:BAAALgADCgEJAQAAAA==.',
['Çh']='Çhakra:BAAALgAECgUJBwAAAA==.',
['Ðð']='Ððn:BAAALgADCgMJAQAAAA==.',
['Øm']='Ømen:BAAALgADCggJCAAAAA==.',
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
