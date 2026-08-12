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

local lookup = {'Druid-Balance','Unknown-Unknown','Paladin-Holy','Mage-Frost','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Assassination','Druid-Guardian','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Subtlety','Paladin-Protection','Warlock-Demonology','Shaman-Restoration','Druid-Restoration','Warrior-Fury','Monk-Mistweaver','Evoker-Augmentation','Monk-Brewmaster','Priest-Discipline','Evoker-Preservation','Monk-Windwalker','DeathKnight-Frost','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Rogue-Outlaw','Evoker-Devastation','Shaman-Elemental','Druid-Feral','Warlock-Destruction','Priest-Holy','Priest-Shadow','Warrior-Arms','Warrior-Protection','Warlock-Affliction','DemonHunter-Havoc','Shaman-Enhancement',}
local provider = {region='US',realm='Warsong',name='US',type='weekly',zone=46,date='2026-08-11',data={Ad='Adeyna:BAAALgAECgEJAQAAAA==.Adònis:BAAALgADCgEJAQAAAA==.',
Ae='Aesudan:BAAALgADCgEJAQAAAA==.',
Ah='Aharan:BAABLgAECn9OAAIBAAkJnBZwAwAEAgABAAkJnBZwAwAEAgAAAA==.',
Ai='Aiona:BAAALgADCgYJDAAAAA==.',
Al='Alandrov:BAAALgADCgEJAQAAAA==.Alexanzalone:BAAALgADCggJCAAAAA==.Allenduin:BAAALgAECgEJAQAAAA==.Alocasia:BAAALgAECgEJAQAAAA==.Alodso:BAAALgADCgEJAQAAAA==.',
An='Angelique:BAAALgAECgYJCgAAAA==.Angryballz:BAAALgAECgYJBwABLgAECgYJDgACAAAAAA==.Angz:BAAALgAECgUJDQAAAA==.Anielor:BAAALgAECgMJBAAAAA==.Anuksuna:BAAALgAFFAEJAgABLgAFFAIJBQADAD8JAA==.',
Ar='Arcadia:BAAALgAECgYJDgAAAA==.Arcane:BAACLgAFFH8RAAIEAAUJox6sSQBPAQAEAAUJox6sSQBPAQAuAAQKfx8AAwQACQngIVwQAEYDAAQACQngIVwQAEYDAAUABQlDJBcFAOkBAAAA.Arèana:BAAALgADCgMJAwAAAA==.',
As='Asta:BAAALgAECgQJBAAAAA==.Astrea:BAAALgAFFAEJAQAAAA==.',
At='Atulan:BAAALgADCgQJBAAAAA==.',
Au='Austin:BAAALgADCggJFgABLgAECgUJCgACAAAAAA==.Automobeer:BAAALgAECgYJCwAAAA==.',
Aw='Awake:BAACLgAFFH8XAAIGAAUJiR1OSABiAQAGAAUJiR1OSABiAQAuAAQKfycAAwYABwnJFxZrAI8BAAYABwmAFhZrAI8BAAcABgnaElYfAEoBAAAA.',
Az='Azazzel:BAAALgADCgEJAQAAAA==.',
Ba='Bambietta:BAABLgAECn8cAAIIAAkJBRAtAQC6AQAIAAkJBRAtAQC6AQAAAA==.Barebelly:BAAALgAECggJEAAAAA==.',
Be='Bearforce:BAABLgAECn8eAAIJAAkJjxnZCAAbAgAJAAkJjxnZCAAbAgAAAA==.',
Bi='Biggbird:BAACLgAFFH8KAAIBAAMJ1BPhFwDDAAABAAMJ1BPhFwDDAAAuAAQKfy4AAgEACQlJHlsDAAkCAAEACQlJHlsDAAkCAAAA.',
Bl='Blewbawl:BAAALgADCgEJAQAAAA==.Blutwin:BAABLgAECn8sAAIKAAkJThMbSgDoAQAKAAkJThMbSgDoAQAAAA==.Bluud:BAAALgADCgMJAwAAAA==.',
Bo='Bossdierr:BAACLgAFFH8bAAMLAAQJxSMxJgCUAQALAAQJxSMxJgCUAQAMAAQJQg9WBwDkAAAuAAQKfzIAAwsACQkyI74RALQCAAsACQkyI74RALQCAAwACAlCExQQAEsBAAAA.Bossdisan:BAACLgAFFH8LAAIEAAQJQxq6WAAsAQAEAAQJQxq6WAAsAQAuAAQKfygAAgQABglsJFdXADMCAAQABglsJFdXADMCAAAA.Bossmasster:BAAALgAFFAIJAgABLgAFFAUJGwALAMUjAA==.Bosswudi:BAABLgAFFH8JAAMIAAIJMRNWCwCJAAANAAIJwRK0FQCgAAAIAAIJihFWCwCJAAABLgAFFAUJGwALAMUjAA==.',
Br='Brashe:BAABLgAECn8xAAIEAAkJBw/iGgAEAQAEAAkJBw/iGgAEAQAAAA==.Breakahorde:BAAALgAECgEJAQAAAA==.Breathe:BAAALgAECgQJBAABLgAFFAIJAgACAAAAAA==.Brickbeard:BAABLgAECn8XAAQDAAgJPwlKRQArAQADAAgJPwlKRQArAQAOAAYJOxAvCwCtAAAKAAIJBws2bAAnAAAAAA==.Bruv:BAABLgAECn8jAAIPAAYJhhU5bwCCAQAPAAYJhhU5bwCCAQABLgAECgkJFQAQAEwYAA==.',
Ca='Calathis:BAAALgAECgEJAQAAAA==.Cazadòr:BAAALgAECgIJAgAAAA==.',
Ch='Chromiepip:BAAALgADCgMJAwAAAA==.',
Co='Corbann:BAAALgAECgYJCgAAAA==.',
Cr='Creamcheese:BAABLgAECn8aAAIRAAcJUB27LAD8AQARAAcJUB27LAD8AQAAAA==.Creamy:BAABLgAECn8zAAISAAkJ+xoNFQBHAgASAAkJ+xoNFQBHAgAAAA==.Crossbreed:BAABLgAFFH8FAAIRAAIJ1BKiUQB9AAARAAIJ1BKiUQB9AAAAAA==.',
Cy='Cyr:BAAALgADCgUJBQAAAA==.Cytosine:BAAALgAFFAEJAQAAAA==.',
Da='Daddyhaz:BAACLgAFFH8aAAILAAgJJhg1DwDGAQALAAgJJhg1DwDGAQAuAAQKf0MAAgsACQmzJKUEADwDAAsACQmzJKUEADwDAAAA.Daddywhyudie:BAAALgADCgEJAQAAAA==.Daelyte:BAAALgAECgYJEAAAAA==.Daghor:BAABLgAFFH8IAAINAAIJPiL3LgCzAAANAAIJPiL3LgCzAAAAAA==.Darkfyre:BAABLgAECn8fAAITAAkJ4hoaAgCzAgATAAkJ4hoaAgCzAgAAAA==.',
De='Deltron:BAAALgAECgIJAwABLgAECgkJEgACAAAAAA==.Desetre:BAAALgADCgIJAgAAAA==.Desmodus:BAAALgAECgIJAgAAAA==.',
Di='Diabos:BAAALgAECgYJBwABLgAFFAQJFgAUABYQAA==.Dinkledots:BAAALgAECggJCwABLgAECgkJYAAEAAUeAA==.Dinks:BAABLgAECn9gAAMEAAkJBR7MBwAEAgAEAAkJBR7MBwAEAgAFAAEJJRPuFQA6AAAAAA==.Ditzy:BAAALgAECgEJAQAAAA==.Divineßovine:BAAALgADCgEJAQAAAA==.',
Do='Docc:BAABLgAECn8XAAINAAkJGA+nFgBXAgANAAkJGA+nFgBXAgAAAA==.Domdps:BAAALgAECgEJAQAAAA==.',
Dr='Draan:BAAALgADCgUJBwAAAA==.Dragorr:BAAALgADCgcJBwAAAA==.Drakkia:BAAALgAECgEJAgAAAA==.Dreadpanda:BAAALgADCgMJAwABLgAFFAQJEAAVAAIlAA==.Drekkarn:BAAALgADCgMJBgABLgAECgkJbwAWAOclAA==.Drood:BAABLgAECn8XAAMRAAcJyxwRAwA9AgARAAcJyxwRAwA9AgABAAEJEhTnIwA7AAAAAA==.',
El='Elzath:BAAALgADCggJEAABLgAECgkJIwAXAIkUAA==.',
En='Enix:BAAALgADCgYJBgABLgAFFAIJCAARALwTAA==.',
Er='Erdrick:BAAALgAECgIJBQAAAA==.',
Es='Espeon:BAAALgAECgcJDgAAAA==.',
Eu='Eudisius:BAAALgADCgEJAQAAAA==.',
Ev='Evara:BAABLgAECn8UAAIEAAYJAwdU7gAcAQAEAAYJAwdU7gAcAQAAAA==.',
Fa='Faded:BAABLgAECn8bAAIWAAcJnhx4AwAmAgAWAAcJnhx4AwAmAgAAAA==.Fangbot:BAAALgAECgEJAgAAAA==.Farmchicken:BAABLgAECn8VAAIUAAkJxhL8AgCxAQAUAAkJxhL8AgCxAQAAAA==.',
Fe='Felcaas:BAAALgADCgQJBAAAAA==.Felini:BAABLgAECn8fAAISAAkJsAcvPQBRAQASAAkJsAcvPQBRAQAAAA==.Feronar:BAABLgAECn8xAAISAAkJrA3LLwCPAQASAAkJrA3LLwCPAQAAAA==.',
Fi='Fizzwater:BAAALgAECgYJEAAAAA==.',
Fl='Fleepity:BAAALgAECgcJEAAAAA==.Floopity:BAAALgADCgYJBwAAAA==.Flowermom:BAAALgAECgEJBAAAAA==.Flume:BAACLgAFFH8GAAINAAMJvgLULwCoAAANAAMJvgLULwCoAAAuAAQKfxwAAwgACQmPFxsKAJgBAA0ABglmFjkbAL0BAAgACAlmERsKAJgBAAAA.',
Fr='Fresco:BAAALgAECgUJBQAAAA==.',
Fu='Fusíon:BAEBLgAECn8zAAILAAkJeiIwDgANAwALAAkJeiIwDgANAwAAAA==.',
Fx='Fx:BAAALgAECgQJBAAAAA==.',
Ga='Galedra:BAAALgAECgMJBQABLgAECgcJCwACAAAAAA==.',
Gi='Gin:BAACLgAFFH8aAAIYAAUJcRTqFwADAQAYAAUJcRTqFwADAQAuAAQKfzIAAhgACQkuG7wXAPYBABgACQkuG7wXAPYBAAAA.',
Gj='Gjana:BAABLgAFFH8GAAIPAAMJKQv6XABHAAAPAAMJKQv6XABHAAABLgAFFAUJDQAEAOALAA==.',
Gl='Glamdring:BAAALgADCgMJAwAAAA==.Glunty:BAAALgAECgUJCAAAAA==.',
Go='Goldpaw:BAAALgADCgEJAQAAAA==.Gorlash:BAAALgAECgcJCAAAAA==.',
Gr='Gridinn:BAAALgADCgIJAgAAAA==.Grimdark:BAABLgAECn8gAAIPAAcJ8BWECACIAQAPAAcJ8BWECACIAQAAAA==.Grimfeather:BAAALgAECgYJEAAAAA==.Grimgeth:BAACLgAFFH8hAAMGAAYJ5BWKGgCPAQAGAAYJ5BWKGgCPAQAHAAQJYQwkNABoAAAuAAQKf1oABAYACQlhInQCAPgCAAYACQnrIXQCAPgCAAcABQlCGCoRAGsAABkAAwlOFOktAGkAAAAA.Grimpact:BAAALgAECgMJAwAAAA==.Grimresolve:BAAALgAECgYJBgABLgAFFAYJIQAGAOQVAA==.Grimwrath:BAABLgAFFH8FAAISAAUJ5AMVHQDCAAASAAUJ5AMVHQDCAAABLgAFFAYJIQAGAOQVAA==.Grouch:BAAALgAECggJDgABLgAFFAUJDQAEAOALAA==.',
Gu='Gugaman:BAAALgADCgcJDgAAAA==.Guishin:BAAALgAECgIJBwAAAA==.Guyver:BAAALgADCgMJAwAAAA==.',
He='Healpls:BAAALgAECgEJAgAAAA==.Heidriel:BAAALgAECgMJAwAAAA==.Heontwo:BAAALgAECgEJAQABLgAFFAEJAwACAAAAAA==.Herumesu:BAAALgAFFAEJAQABLgAFFAcJGgAGAH4cAA==.Heshan:BAABLgAECn8xAAIEAAkJbRmDBQBcAgAEAAkJbRmDBQBcAgAAAA==.',
Ho='Holapes:BAAALgAECgUJEAABLgAECgMJBAACAAAAAA==.Hornk:BAAALgAECgUJBQAAAA==.',
Hu='Huhbruh:BAAALgAECgIJAgABLgAECgkJFQAQAEwYAA==.',
Hw='Hwasa:BAABLgAECn8jAAIVAAkJ4h1zDABuAgAVAAkJ4h1zDABuAgAAAA==.',
Il='Illigari:BAAALgAFFAEJAQAAAA==.',
In='Indy:BAAALgAECgEJAgAAAA==.Insanities:BAABLgAECn9vAAIWAAkJ5yXUAADaAwAWAAkJ5yXUAADaAwAAAA==.Inti:BAABLgAECn8WAAIDAAYJZhtdMACYAQADAAYJZhtdMACYAQABLgAFFAIJCAARALwTAA==.',
Iz='Izumisakai:BAAALgAFFAIJAwABLgAFFAcJGgAGAH4cAA==.',
Ja='Jaidie:BAABLgAECn8nAAIaAAkJZhG7AgBHAQAaAAkJZhG7AgBHAQAAAA==.',
Je='Jeffreyx:BAAALgAECgYJCAAAAA==.Jeffreyz:BAAALgADCgYJCwAAAA==.Jerlonge:BAAALgAECgEJAgAAAA==.',
Jo='Joak:BAAALgADCgUJBQAAAA==.Jota:BAAALgADCgcJCAAAAA==.',
Ka='Kahlune:BAAALgAECgEJAQABLgAFFAIJBQADAD8JAA==.Kahlán:BAACLgAFFH8FAAIDAAIJPwlVQABhAAADAAIJPwlVQABhAAAuAAQKfx4AAgMACQlOF+AfAAQCAAMACQlOF+AfAAQCAAAA.Karlangas:BAAALgAECgMJBAAAAA==.Kasaar:BAAALgAECgUJBQAAAA==.',
Ki='Kifu:BAAALgAFFAIJAgABLgAFFAUJDQAEAOALAA==.Kijann:BAAALgADCgUJBQAAAA==.Kikipants:BAAALgADCgEJAQAAAA==.Kitrix:BAAALgADCgUJBQAAAA==.Kitty:BAABLgAFFH8GAAIXAAMJDgQwIwCIAAAXAAMJDgQwIwCIAAABLgAFFAQJDgAJAHYHAA==.',
Kn='Knell:BAAALgAECgcJDAAAAA==.',
Kr='Krue:BAAALgADCggJDQAAAA==.Kryptix:BAAALgAECgMJAwAAAA==.',
Ku='Kubimage:BAABLgAECn8aAAIEAAkJKhu2MgCoAgAEAAkJKhu2MgCoAgAAAA==.Kurta:BAAALgAFFAEJAQAAAA==.',
La='Laguna:BAAALgAECgkJBAAAAA==.Lane:BAAALgADCgEJAQAAAA==.Layona:BAAALgAECgYJCgAAAA==.',
Le='Lerroy:BAAALgADCgcJCQAAAA==.',
Li='Liana:BAAALgAECgEJAQAAAA==.Lildar:BAABLgAECn8nAAIGAAgJnhrWQwD3AQAGAAgJnhrWQwD3AQAAAA==.Linelli:BAABLgAFFH8NAAQbAAUJdxwWAwCjAQAbAAUJBBwWAwCjAQAaAAMJcxnPCQDvAAAcAAIJhSKQcAC/AAABLgAFFAcJGgAdAD0iAA==.Lirra:BAAALgAFFAIJBAABLgAFFAIJCAARALwTAA==.',
Lo='Lobixona:BAAALgAECgEJAQAAAA==.Londo:BAAALgAECgUJBgAAAA==.Lorthiel:BAAALgADCgIJAgAAAA==.Lothus:BAACLgAFFH8IAAIcAAIJgh6UeQClAAAcAAIJgh6UeQClAAAuAAQKfxUAAxwACQkPGzAYAHgCABwACQkPGzAYAHgCABoAAQl2BGOTACcAAAEuAAUUAgkIABEAvBMA.Lowakacho:BAAALgAECgQJBQAAAA==.Lox:BAAALgAECgYJCQAAAA==.',
Ls='Lsblkxd:BAAALgADCgYJBgAAAA==.',
Lu='Lumen:BAAALgAECgIJAgAAAA==.Lumverjvcked:BAABLgAECn8VAAIQAAcJTBjrMADxAQAQAAcJTBjrMADxAQAAAA==.',
Lx='Lxrbread:BAACLgAFFH8ZAAMUAAQJZA1rNgDqAAAUAAQJZA1rNgDqAAAXAAEJ5QPaGAA8AAAuAAQKf0QABBQACQn4FckeAOEBABQACQnXFckeAOEBABcABwlvC6UGAMEAAB4ABAlaFesDAMAAAAAA.',
['Lë']='Lëgitz:BAABLgAECn8lAAMQAAkJuR89DAD4AgAQAAkJuR89DAD4AgAfAAgJIBR5LgCHAQAAAA==.',
Ma='Macca:BAAALgAECgUJBQABLgAECgYJDgACAAAAAA==.Maccazilla:BAAALgAECgYJDgAAAA==.Magdalena:BAACLgAFFH8cAAIYAAUJcSRtCACSAQAYAAUJcSRtCACSAQAuAAQKfyYAAhgACQkXJb8CAG0DABgACQkXJb8CAG0DAAAA.Magedand:BAAALgAECgMJAwAAAA==.Magnesson:BAAALgAFFAEJAgAAAA==.Maldrax:BAAALgADCgYJBAAAAA==.Manakaren:BAAALgADCggJDAAAAA==.Martini:BAAALgAFFAEJAgAAAA==.Maverik:BAAALgAECgUJBgAAAA==.Mavja:BAAALgAECgYJDgAAAA==.Mazuro:BAACLgAFFH8fAAINAAcJLxmOCgDzAQANAAcJLxmOCgDzAQAuAAQKfzMAAw0ACQm5HZsJAIsCAA0ACQm5HZsJAIsCAAgAAQlGGVodAEAAAAAA.',
Me='Meatkleaver:BAABLgAECn8bAAMZAAkJ0BUhAwBnAgAZAAkJ0BUhAwBnAgAGAAEJqAGXNgEiAAAAAA==.Meau:BAABLgAECn8jAAIgAAkJmh4hBgCJAgAgAAkJmh4hBgCJAgAAAA==.Mechadar:BAAALgAECgMJAwAAAA==.',
Mi='Mitskí:BAAALgAECgQJBAAAAA==.',
Mo='Mongerasta:BAAALgAECgMJBwAAAA==.Monkerooz:BAAALgAECgUJCAAAAA==.Moodeng:BAAALgADCgYJBwAAAA==.Morbius:BAAALgAFFAEJAQAAAA==.Morix:BAAALgAECgEJAQAAAA==.Morphîne:BAACLgAFFH8IAAIRAAIJvBNBVQBxAAARAAIJvBNBVQBxAAAuAAQKfxcAAhEABwkZHvEoABACABEABwkZHvEoABACAAAA.',
Mu='Mugwump:BAABLgAECn8WAAMQAAgJwBjoIwA3AgAQAAgJwBjoIwA3AgAfAAMJKBkDFgCUAAAAAA==.Murdõk:BAAALgAECgEJAQABLgAFFAIJBQAGALsMAA==.Murdøk:BAACLgAFFH8FAAMGAAIJuwy06ACAAAAGAAIJuwy06ACAAAAZAAEJhgNKLQA0AAAuAAQKfx4ABAYACQnYGAxdALEBAAYACQnYGAxdALEBAAcAAQnpDThEADgAABkAAQmqCYE+ACoAAAAA.',
My='Mythic:BAABLgAECn8pAAIYAAkJdBuHDgBgAgAYAAkJdBuHDgBgAgAAAA==.',
['Mû']='Mûrdok:BAAALgAFFAEJAQABLgAFFAIJBQAGALsMAA==.',
['Mü']='Mürdok:BAAALgAFFAEJAQABLgAFFAIJBQAGALsMAA==.',
Ne='Necromortas:BAAALgAECgcJBwAAAA==.Nefarius:BAABLgAECn8WAAMPAAkJLhscWgCPAQAPAAgJLhscWgCPAQAhAAMJWxRgOwDGAAABLgAFFAEJAQACAAAAAA==.Neph:BAABLgAECn8aAAMiAAkJQw96HwDlAQAiAAkJQw96HwDlAQAWAAIJbgNeUABNAAAAAA==.Nettle:BAAALgAECgUJBQAAAA==.Nezot:BAAALgAECgUJBgAAAA==.',
Ni='Nihilism:BAAALgADCgYJBgAAAA==.Ninsu:BAAALgAECgYJCgAAAA==.Nira:BAAALgAECgEJAQAAAA==.Nishale:BAAALgAECgQJCQABLgAECgcJCwACAAAAAA==.Niver:BAAALgAECgEJAgAAAA==.',
No='Noir:BAAALgADCgQJBAAAAA==.',
Nu='Nutdraggin:BAAALgADCgcJBwAAAA==.',
Ny='Nyki:BAABLgAECn8cAAQjAAgJVRd0BgB7AQAjAAcJOxd0BgB7AQAWAAcJSxBYCgA5AQAiAAIJgxa7FwBTAAAAAA==.',
Of='Offline:BAAALgAECgUJBQABLgAFFAQJGAAGAKQUAA==.',
On='Onlyfist:BAAALgAECgEJAgAAAA==.',
Op='Opius:BAAALgAECgkJEgAAAA==.',
Or='Orcmagic:BAAALgADCgcJCQAAAA==.',
Os='Oscrixi:BAAALgAECgEJAQAAAA==.Oshift:BAAALgAECgYJBgAAAA==.',
Pa='Pakk:BAAALgAECgYJCgABLgAECgkJEgACAAAAAA==.Pandinha:BAACLgAFFH8ZAAIGAAQJ8B1HYwAwAQAGAAQJ8B1HYwAwAQAuAAQKfzgAAgYACQkEIywMADkDAAYACQkEIywMADkDAAAA.Paolinelli:BAABLgAFFH8IAAMkAAQJPB3+DwDRAAAkAAQJeBb+DwDRAAASAAMJKB46PQC4AAABLgAFFAcJGgAdAD0iAA==.Pattêrn:BAAALgAECgYJEwAAAA==.',
Pd='Pdr:BAAALgADCgcJBwAAAA==.',
Pe='Pedri:BAABLgAFFH8LAAMGAAMJQhm4igD0AAAGAAMJQhm4igD0AAAZAAEJlw+ZJwBHAAAAAA==.Pedrok:BAABLgAECn8VAAQkAAgJEw/kCgC4AAAkAAcJzwzkCgC4AAAlAAQJggerDQBwAAASAAQJzgomJgBFAAAAAA==.Perses:BAAALgAECgYJCgAAAA==.',
Ph='Phoenixashes:BAAALgADCgIJAgAAAA==.',
Pi='Picklestein:BAAALgAECgEJAQAAAA==.',
Po='Pokz:BAAALgADCgEJAQAAAA==.',
Pr='Predatorxy:BAAALgAFFAIJAgAAAA==.Priestiality:BAAALgAECgIJBAAAAA==.Promix:BAAALgAECgEJAQAAAA==.Promorph:BAAALgAECgEJAgAAAA==.Prowl:BAAALgAECgEJAQABLgAFFAgJFwAkAGsYAA==.Prscilla:BAAALgADCgcJBgAAAA==.',
['Pë']='Përseu:BAAALgAECgMJAwAAAA==.',
Qu='Quixote:BAAALgAECggJEQAAAA==.',
Ra='Radagast:BAAALgADCgcJDQABLgAFFAQJGgALAC0QAA==.Radulf:BAAALgAECgQJBAAAAA==.Raph:BAACLgAFFH8aAAIGAAcJfhx7HQB3AQAGAAcJfhx7HQB3AQAuAAQKfyoAAgYACAnmH+A4ABwCAAYACAnmH+A4ABwCAAAA.Raphy:BAABLgAFFH8IAAIGAAMJthBjoADUAAAGAAMJthBjoADUAAABLgAFFAcJGgAGAH4cAA==.Ravyn:BAAALgADCgUJBQAAAA==.',
Re='Reckon:BAAALgAECgYJDAAAAA==.Redthedeer:BAAALgAFFAIJAgAAAA==.Redthedragon:BAAALgAECgEJAQAAAA==.Redthepriest:BAAALgAECgEJAQAAAA==.Redzone:BAAALgAECgQJBgAAAA==.Refuliya:BAAALgADCgkJBwAAAA==.Remmahcm:BAABLgAECn8VAAIKAAgJUBYvPwApAgAKAAgJUBYvPwApAgAAAA==.Renewing:BAAALgADCgQJBAAAAA==.Renrir:BAAALgADCgcJCAAAAA==.Rezen:BAAALgAFFAIJAgAAAA==.',
Rh='Rhark:BAAALgAECgUJDQAAAA==.',
Ri='Rikku:BAABLgAFFH8NAAIIAAMJqgd5AwC8AAAIAAMJqgd5AwC8AAAAAA==.',
Ro='Rook:BAABLgAECn8yAAMKAAkJKyJoDQD6AgAKAAkJKyJoDQD6AgAOAAUJBgheNwCCAAAAAA==.',
Ru='Runnow:BAAALgADCgYJCwAAAA==.',
Sa='Saebi:BAAALgADCgkJCQABLgAFFAIJAgACAAAAAA==.Sagas:BAAALgAFFAMJAwAAAA==.Salina:BAAALgAECgcJCwAAAA==.Sammysam:BAAALgADCgUJBwAAAA==.Santairon:BAAALgAECgEJAgAAAA==.Sathor:BAAALgADCgkJDgAAAA==.',
Sc='Scotch:BAAALgADCgQJBAABLgAFFAUJGgAYAHEUAA==.',
Sh='Shaffios:BAAALgAECgYJDAAAAA==.Shelton:BAAALgADCgMJAwABLgADCggJDQACAAAAAA==.Shinjey:BAAALgAECgMJBwAAAA==.Shocker:BAAALgAECgEJAQAAAA==.',
Si='Sil:BAABLgAECn8ZAAIlAAkJCwr1FwCXAQAlAAkJCwr1FwCXAQAAAA==.Silents:BAAALgAECgUJBQAAAA==.Siphon:BAAALgAECgYJDAAAAA==.Siphons:BAAALgAECgMJBAAAAA==.',
Sk='Ska:BAACLgAFFH8iAAIPAAkJHhaIHwDUAQAPAAkJHhaIHwDUAQAuAAQKfxsAAw8ACAm7H1oYAMICAA8ACAm7H1oYAMICACEAAQkAAJNwADUAAAAA.',
Sl='Slyzete:BAAALgAECgQJBwAAAA==.',
So='Softbutt:BAABLgAECn8gAAISAAgJEhOcBQCiAQASAAgJEhOcBQCiAQAAAA==.Sophiae:BAAALgAECgIJAgAAAA==.Sophie:BAAALgAECgUJBQAAAA==.Soulseeker:BAABLgAECn8tAAQPAAgJExVWSQC+AQAPAAgJExVWSQC+AQAhAAIJfBRoUAB9AAAmAAEJgBGNPQA3AAAAAA==.',
Sp='Splatterdash:BAAALgAECgYJCQAAAA==.Spriz:BAABLgAFFH8GAAIRAAEJdANgNwAlAAARAAEJdANgNwAlAAAAAA==.',
St='Staby:BAAALgAECgEJAQABLgAECgkJBAACAAAAAA==.Stölen:BAAALgAECgEJAQAAAA==.',
Sy='Sylthas:BAAALgADCgMJAwABLgAECgQJBAACAAAAAA==.Syrensong:BAAALgAECgQJBAAAAA==.',
Ta='Tankli:BAAALgAECgIJBgAAAA==.Tanriel:BAAALgAECgEJAQAAAA==.Tatl:BAAALgAECgUJCwAAAA==.',
Te='Tertletoes:BAABLgAECn8cAAQnAAkJECXvAAC+AwAnAAkJECXvAAC+AwAMAAEJ2x46JwBMAAALAAEJ/h3c2gA5AAAAAA==.Terts:BAAALgAECgEJAQABLgAECgkJHAAnABAlAA==.Teto:BAAALgAECgYJDgAAAA==.Tetsunen:BAAALgAECggJDQAAAA==.',
Th='Thanaz:BAAALgAECgUJCQAAAA==.Thebartender:BAAALgAECgcJDAAAAA==.Thella:BAAALgAECgQJBgAAAA==.Thopowisiwi:BAAALgAFFAIJBAAAAA==.',
To='Tog:BAABLgAECn8cAAMRAAkJciLGAwBVAwARAAkJciLGAwBVAwABAAEJVxG5JgAxAAAAAA==.Togame:BAAALgAECgUJCAAAAA==.Toggie:BAAALgAECgEJAgAAAA==.Tognahok:BAAALgADCgYJDgAAAA==.Togy:BAAALgADCgEJAQAAAA==.Tortoisetoes:BAAALgAECgIJAgABLgAECgkJHAAnABAlAA==.',
Tr='Tremboladin:BAABLgAECn8aAAIDAAcJHxo1JgD2AQADAAcJHxo1JgD2AQABLgAFFAQJFgAUABYQAA==.Trollsroyce:BAAALgAECgEJAQAAAA==.',
Ts='Tsnt:BAAALgAECgEJAQAAAA==.',
Tu='Turbosocks:BAAALgAECgYJCgAAAA==.Turok:BAAALgADCgMJAwAAAA==.Turtles:BAAALgADCgEJAQABLgAECgkJHAAnABAlAA==.Tuskydin:BAAALgADCgcJCQAAAA==.',
Ty='Tyank:BAAALgAECggJDQAAAA==.Tydrin:BAAALgAECgIJAwAAAA==.Tylandord:BAAALgADCgEJAQAAAA==.',
['Tý']='Týråél:BAAALgADCgYJCwAAAA==.',
Ur='Urra:BAABLgAECn8rAAIfAAgJEB4OHwDqAQAfAAgJEB4OHwDqAQAAAA==.',
Va='Vai:BAAALgAECgYJCQAAAA==.Valkyrie:BAABLgAFFH8JAAIKAAUJtx5VNQBEAQAKAAUJtx5VNQBEAQABLgAFFAUJEQAEAKMeAA==.Valoo:BAAALgAECgQJCgAAAA==.Valunar:BAAALgADCgUJBQAAAA==.',
Ve='Vex:BAAALgADCgEJAQABLgAECgkJGAAPAG8aAA==.Veyron:BAAALgADCgMJAwAAAA==.',
Vi='Vicar:BAABLgAECn8WAAMiAAcJVRc5CgAKAQAiAAcJVRc5CgAKAQAjAAUJ9hRiDAD3AAAAAA==.',
Vo='Voidstrider:BAAALgAECggJEAAAAA==.',
Wa='Wargyu:BAAALgAECgMJAwABLgAFFAcJDQAUAJITAA==.',
We='Weezard:BAACLgAFFH8NAAIEAAUJ4At9PgDMAAAEAAUJ4At9PgDMAAAuAAQKfzAAAgQACQmPFvA7ACoCAAQACQmPFvA7ACoCAAAA.',
Wh='Wheein:BAABLgAECn8jAAIWAAkJ1iGCBwACAwAWAAkJ1iGCBwACAwABLgAECgEJAwACAAAAAA==.',
Wi='Wingolingo:BAAALgAECgIJAgAAAA==.',
Xe='Xeren:BAAALgADCgEJAQAAAA==.',
Xi='Xioa:BAAALgADCgEJAQAAAA==.',
Ya='Yaamoonn:BAAALgADCgUJBQAAAA==.',
Ye='Yenn:BAABLgAECn8cAAMPAAkJXhtHFgDPAgAPAAkJXhtHFgDPAgAhAAIJwAEuWgBgAAAAAA==.',
Za='Zardnax:BAAALgAECgIJAgAAAA==.',
Ze='Zenin:BAAALgADCggJFQABLgAECgQJBAACAAAAAA==.Zensky:BAAALgAECgQJBAAAAA==.Zenu:BAACLgAFFH8MAAMfAAQJwhR9JAAHAQAfAAQJ1hJ9JAAHAQAoAAMJqg7JDwDJAAAuAAQKfyUAAx8ACQlQGxYSAJICAB8ACQlQGxYSAJICACgABAk1FlwoALQAAAEuAAQKBAkEAAIAAAAA.',
Zu='Zugg:BAAALgADCgEJAQAAAA==.',
['Çh']='Çhakra:BAAALgAECgUJBwAAAA==.',
['Ðð']='Ððn:BAAALgADCgMJAQAAAA==.',
['Øm']='Ømen:BAAALgAECgMJAwAAAA==.',
['Úl']='Úllr:BAAALgAECgEJAwAAAA==.',
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
