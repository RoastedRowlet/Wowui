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

local lookup = {'Druid-Balance','Unknown-Unknown','Paladin-Holy','Mage-Frost','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Druid-Guardian','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Shaman-Restoration','Druid-Restoration','Warrior-Fury','Monk-Brewmaster','Priest-Discipline','Evoker-Preservation','Monk-Windwalker','DeathKnight-Frost','Hunter-Marksmanship','Rogue-Outlaw','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Shaman-Elemental','Druid-Feral','Warlock-Destruction','Priest-Holy','Warrior-Arms','Paladin-Protection','Warrior-Protection','Warlock-Affliction','DemonHunter-Havoc','Shaman-Enhancement',}
local provider = {region='US',realm='Warsong',name='US',type='weekly',zone=46,date='2026-06-21',data={Ad='Adeyna:BAAALgAECgEJAQAAAA==.Adònis:BAAALgADCgEJAQAAAA==.',
Ae='Aesudan:BAAALgADCgEJAQAAAA==.',
Ah='Aharan:BAABLgAECn83AAIBAAkJSxDWKgB+AQABAAkJSxDWKgB+AQAAAA==.',
Ai='Aiona:BAAALgADCgYJDAAAAA==.',
Al='Alandrov:BAAALgADCgEJAQAAAA==.Alexanzalone:BAAALgADCggJCAAAAA==.Allenduin:BAAALgAECgEJAQAAAA==.Alodso:BAAALgADCgEJAQAAAA==.',
An='Angelique:BAAALgAECgYJCgAAAA==.Angryballz:BAAALgAECgYJBwABLgAECgYJDAACAAAAAA==.Angz:BAAALgAECgUJDQAAAA==.Anielor:BAAALgAECgMJBAAAAA==.Anuksuna:BAAALgAFFAEJAQABLgAECgkJHgADAE4XAA==.',
Ar='Arcadia:BAAALgAECgYJDgAAAA==.Arcane:BAACLgAFFH8RAAIEAAUJox6qSQBPAQAEAAUJox6qSQBPAQAuAAQKfx8AAwQACQngIVwQAEYDAAQACQngIVwQAEYDAAUABQlDJBcFAOkBAAAA.',
As='Asta:BAAALgAECgQJBAAAAA==.Astrea:BAAALgAFFAEJAQAAAA==.',
At='Atulan:BAAALgADCgQJBAAAAA==.',
Au='Austin:BAAALgADCggJFgAAAA==.Automobeer:BAAALgAECgIJBgAAAA==.',
Aw='Awake:BAACLgAFFH8QAAIGAAQJiR1UDADrAAAGAAQJiR1UDADrAAAuAAQKfycAAwYABwnJFxdrAI8BAAYABwmAFhdrAI8BAAcABgnaElYfAEoBAAAA.',
Az='Azazzel:BAAALgADCgEJAQAAAA==.',
Ba='Bambietta:BAAALgAECgcJDgAAAA==.Barebelly:BAAALgAECggJEAAAAA==.',
Be='Bearforce:BAABLgAECn8eAAIIAAkJjxnZCAAbAgAIAAkJjxnZCAAbAgAAAA==.',
Bi='Biggbird:BAABLgAECn8oAAIBAAgJ9hydEgBBAgABAAgJ9hydEgBBAgAAAA==.',
Bl='Blewbawl:BAAALgADCgEJAQAAAA==.Blutwin:BAABLgAECn8sAAIJAAkJThMaSgDoAQAJAAkJThMaSgDoAQAAAA==.Bluud:BAAALgADCgMJAwAAAA==.',
Bo='Bootyhünter:BAAALgAECgEJAwAAAA==.Bossdierr:BAACLgAFFH8bAAMKAAQJxSMvJgCUAQAKAAQJxSMvJgCUAQALAAQJQg9UBwDkAAAuAAQKfzIAAwoACQkyI8ERALQCAAoACQkyI8ERALQCAAsACAlCExQQAEsBAAAA.Bossdisan:BAACLgAFFH8LAAIEAAQJQxq2WAAsAQAEAAQJQxq2WAAsAQAuAAQKfygAAgQABglsJFdXADMCAAQABglsJFdXADMCAAAA.Bossmasster:BAAALgAFFAIJAgAAAA==.Bosswudi:BAABLgAFFH8JAAMMAAIJMRNWCwCJAAANAAIJwRK0FQCgAAAMAAIJihFWCwCJAAAAAA==.',
Br='Brashe:BAABLgAECn8tAAIEAAgJ+A5LfQB9AQAEAAgJ+A5LfQB9AQAAAA==.Breathe:BAAALgAECgQJBAABLgAECgYJCgACAAAAAA==.Brickbeard:BAAALgAECggJEwAAAA==.Bruv:BAABLgAECn8jAAIOAAYJhhU5bwCCAQAOAAYJhhU5bwCCAQABLgAECgkJFQAPAEwYAA==.',
Ca='Calathis:BAAALgAECgEJAQAAAA==.Cazadòr:BAAALgAECgIJAgAAAA==.',
Ch='Chromiepip:BAAALgADCgMJAwAAAA==.',
Co='Corbann:BAAALgAECgYJCgAAAA==.',
Cr='Creamcheese:BAABLgAECn8aAAIQAAcJUB27LAD8AQAQAAcJUB27LAD8AQAAAA==.Creamy:BAABLgAECn8zAAIRAAkJ+xoNFQBHAgARAAkJ+xoNFQBHAgAAAA==.Crossbreed:BAABLgAFFH8FAAIQAAIJ1BKhUQB9AAAQAAIJ1BKhUQB9AAAAAA==.',
Cy='Cyr:BAAALgADCgUJBQAAAA==.Cytosine:BAAALgAFFAEJAQAAAA==.',
Da='Daddyhaz:BAACLgAFFH8TAAIKAAYJThYMJQCaAQAKAAYJThYMJQCaAQAuAAQKf0MAAgoACQmzJKUEADwDAAoACQmzJKUEADwDAAAA.Daddywhyudie:BAAALgADCgEJAQAAAA==.Daelyte:BAAALgAECgYJDwAAAA==.Daghor:BAABLgAFFH8IAAINAAIJPiL1LgCzAAANAAIJPiL1LgCzAAABLgAFFAQJBQAGAGkMAA==.',
De='Deltron:BAAALgAECgEJAQAAAA==.Desetre:BAAALgADCgIJAgAAAA==.Desmodus:BAAALgAECgIJAgAAAA==.',
Di='Diabos:BAAALgAECgYJBwABLgAFFAQJFgACAAAAAA==.Dinks:BAABLgAECn9OAAMEAAkJaBuKKwBsAgAEAAkJaBuKKwBsAgAFAAEJJRPuFQA6AAAAAA==.Ditzy:BAAALgAECgEJAQAAAA==.',
Do='Docc:BAABLgAECn8XAAINAAkJGA+nFgBXAgANAAkJGA+nFgBXAgAAAA==.Domdps:BAAALgAECgEJAQAAAA==.',
Dr='Draan:BAAALgADCgUJBwAAAA==.Dragorr:BAAALgADCgcJBwAAAA==.Drakkia:BAAALgAECgEJAgAAAA==.Dreadpanda:BAAALgADCgMJAwABLgAFFAQJEAASAAIlAA==.Drekkarn:BAAALgADCgMJBgABLgAECgkJZQATAIYlAA==.Drood:BAAALgAECgYJDAAAAA==.',
El='Elzath:BAAALgADCggJEAABLgAECgkJIwAUAIkUAA==.',
En='Enix:BAAALgADCgYJBgABLgAFFAIJCAAQALwTAA==.',
Er='Erdrick:BAAALgAECgIJBQAAAA==.',
Es='Espeon:BAAALgAECgcJDgAAAA==.',
Eu='Eudisius:BAAALgADCgEJAQAAAA==.',
Ev='Evara:BAABLgAECn8UAAIEAAYJAwdU7gAcAQAEAAYJAwdU7gAcAQAAAA==.',
Fa='Faded:BAAALgAECgYJEwAAAA==.Fangbot:BAAALgAECgEJAgAAAA==.Farmchicken:BAAALgAFFAIJAgAAAA==.',
Fe='Felcaas:BAAALgADCgQJBAAAAA==.Felini:BAABLgAECn8fAAIRAAkJsAcuPQBRAQARAAkJsAcuPQBRAQAAAA==.Feronar:BAABLgAECn8uAAIRAAkJ+wvMLwCPAQARAAkJ+wvMLwCPAQAAAA==.',
Fi='Fizzwater:BAAALgAECgYJEAAAAA==.',
Fl='Fleepity:BAAALgAECgcJEAAAAA==.Floopity:BAAALgADCgYJBwAAAA==.Flowermom:BAAALgAECgEJAwAAAA==.Flume:BAACLgAFFH8FAAINAAMJvgLRLwCoAAANAAMJvgLRLwCoAAAuAAQKfxoAAwwACQmPFxsKAJgBAA0ABglmFjkbAL0BAAwACAlmERsKAJgBAAAA.',
Fu='Fusíon:BAEBLgAECn8zAAIKAAkJeiIwDgANAwAKAAkJeiIwDgANAwAAAA==.',
Gi='Gin:BAACLgAFFH8VAAIVAAUJaRPpFwADAQAVAAUJaRPpFwADAQAuAAQKfzIAAhUACQkuG7wXAPYBABUACQkuG7wXAPYBAAAA.',
Gj='Gjana:BAAALgAFFAIJBAABLgAFFAQJCQAEALwIAA==.',
Gl='Glamdring:BAAALgADCgMJAwAAAA==.Glunty:BAAALgAECgUJCAAAAA==.',
Go='Goldpaw:BAAALgADCgEJAQAAAA==.Gorlash:BAAALgAECgcJCAAAAA==.',
Gr='Gridinn:BAAALgADCgIJAgAAAA==.Grimdark:BAAALgAECgYJDwAAAA==.Grimfeather:BAAALgAECgYJCgAAAA==.Grimgeth:BAACLgAFFH8XAAMGAAUJKxSSbQAhAQAGAAQJKxSSbQAhAQAHAAQJYQwiNABoAAAuAAQKf0QABAYACQnVIWIQAOoCAAYACQn6IGIQAOoCAAcAAwlXH+E5AKwAABYAAwlOFOotAGkAAAAA.Grimwrath:BAAALgAECgUJBwABLgAFFAUJFwAGACsUAA==.',
Gu='Gugaman:BAAALgADCgcJDgAAAA==.Guishin:BAAALgAECgEJBQAAAA==.',
He='Healpls:BAAALgAECgEJAgAAAA==.Heidriel:BAAALgAECgMJAwAAAA==.Heon:BAAALgADCgEJAQAAAA==.Herumesu:BAAALgAFFAEJAQABLgAFFAYJFQAGACEaAA==.Heshan:BAAALgADCgMJAwAAAA==.',
Ho='Holapes:BAAALgAECgUJEAABLgAECgMJBAACAAAAAA==.',
Hu='Huhbruh:BAAALgAECgIJAgABLgAECgkJFQAPAEwYAA==.',
Hw='Hwasa:BAABLgAECn8jAAISAAkJ4h1yDABuAgASAAkJ4h1yDABuAgAAAA==.',
Il='Illigari:BAAALgAFFAEJAQAAAA==.',
In='Indy:BAAALgAECgEJAgAAAA==.Insanities:BAABLgAECn9lAAITAAkJhiXUAADaAwATAAkJhiXUAADaAwAAAA==.Inti:BAABLgAECn8WAAIDAAYJZhtcMACYAQADAAYJZhtcMACYAQABLgAFFAIJCAAQALwTAA==.',
Iz='Izumisakai:BAAALgAFFAIJAwABLgAFFAYJFQAGACEaAA==.',
Ja='Jaidie:BAABLgAECn8YAAIXAAgJDQu2EwAlAQAXAAgJDQu2EwAlAQAAAA==.',
Je='Jeffreyx:BAAALgAECgYJCAAAAA==.Jeffreyz:BAAALgADCgYJBgAAAA==.Jerlonge:BAAALgAECgEJAgAAAA==.',
Jo='Joak:BAAALgADCgUJBQAAAA==.Jota:BAAALgADCgcJCAAAAA==.',
Ka='Kahlune:BAAALgAECgEJAQABLgAECgkJHgADAE4XAA==.Kahlán:BAABLgAECn8eAAIDAAkJThfhHwAEAgADAAkJThfhHwAEAgAAAA==.Karlangas:BAAALgAECgMJBAAAAA==.',
Ki='Kifu:BAAALgAECgQJCAABLgAFFAQJCQAEALwIAA==.Kikipants:BAAALgADCgEJAQAAAA==.Kitrix:BAAALgADCgUJBQAAAA==.Kitty:BAABLgAFFH8GAAIUAAMJDgQvIwCIAAAUAAMJDgQvIwCIAAABLgAFFAQJDgAIAHYHAA==.',
Kr='Krue:BAAALgADCggJDQAAAA==.',
Ku='Kubimage:BAABLgAECn8aAAIEAAkJKhu2MgCoAgAEAAkJKhu2MgCoAgAAAA==.',
La='Laguna:BAAALgAECgkJBAAAAA==.Lane:BAAALgADCgEJAQAAAA==.Layona:BAAALgAECgYJCgAAAA==.',
Le='Lerroy:BAAALgADCgcJCQAAAA==.',
Li='Liana:BAAALgAECgEJAQAAAA==.Lildar:BAABLgAECn8nAAIGAAgJnhrSQwD3AQAGAAgJnhrSQwD3AQAAAA==.Linelli:BAAALgAFFAIJBAABLgAFFAcJFQAYACQiAA==.Lirra:BAAALgAFFAIJBAABLgAFFAIJCAAQALwTAA==.',
Lo='Londo:BAAALgAECgUJBgAAAA==.Lorthiel:BAAALgADCgIJAgAAAA==.Lothus:BAACLgAFFH8IAAIZAAIJgh6SeQClAAAZAAIJgh6SeQClAAAuAAQKfxUAAxkACQkPGzAYAHgCABkACQkPGzAYAHgCABcAAQl2BGOTACcAAAEuAAUUAgkIABAAvBMA.Lox:BAAALgAECgYJCQAAAA==.',
Ls='Lsblkxd:BAAALgADCgYJBgAAAA==.',
Lu='Lumen:BAAALgAECgIJAgAAAA==.Lumverjvcked:BAABLgAECn8VAAIPAAcJTBjpMADxAQAPAAcJTBjpMADxAQAAAA==.',
Lx='Lxrbread:BAACLgAFFH8ZAAMaAAQJZA1lNgDqAAAaAAQJZA1lNgDqAAAUAAEJ5QPaGAA8AAAuAAQKf0AABBoACQn4FcseAOEBABoACQnXFcseAOEBABQABwlvC+4AAMgAABsAAwnOCQolADcAAAAA.',
['Lë']='Lëgitz:BAABLgAECn8lAAMPAAkJuR8+DAD4AgAPAAkJuR8+DAD4AgAcAAgJIBR3LgCHAQAAAA==.',
Ma='Macca:BAAALgAECgUJBQABLgAECgYJDAACAAAAAA==.Maccazilla:BAAALgAECgYJDAAAAA==.Magdalena:BAACLgAFFH8bAAIVAAUJcSRwCACSAQAVAAUJcSRwCACSAQAuAAQKfyYAAhUACQkXJb8CAG0DABUACQkXJb8CAG0DAAAA.Magedand:BAAALgAECgMJAwAAAA==.Magnesson:BAAALgAFFAEJAgAAAA==.Maldrax:BAAALgADCgQJBAAAAA==.Manakaren:BAAALgADCggJDAAAAA==.Martini:BAAALgAFFAEJAQAAAA==.Mavja:BAAALgAECgMJBAAAAA==.Mazuro:BAACLgAFFH8fAAINAAcJLxmNCgDzAQANAAcJLxmNCgDzAQAuAAQKfzMAAw0ACQm5HZoJAIsCAA0ACQm5HZoJAIsCAAwAAQlGGVodAEAAAAAA.',
Me='Meatkleaver:BAABLgAECn8bAAMWAAkJ0BUhAwBnAgAWAAkJ0BUhAwBnAgAGAAEJqAGXNgEiAAAAAA==.Meau:BAABLgAECn8jAAIdAAkJmh4gBgCJAgAdAAkJmh4gBgCJAgAAAA==.Mechadar:BAAALgAECgMJAwAAAA==.Mechanizedtv:BAACLgAFFH8RAAIIAAQJ7iMeBgCZAQAIAAQJ7iMeBgCZAQAuAAQKf/AABAgACQmwJk8AAIMDAAgACQmwJk8AAIMDAB0ACAm8JNACAPMCAAEAAQlmAlylABwAAAAA.',
Mi='Mitskí:BAAALgAECgQJBAAAAA==.',
Mo='Mongerasta:BAAALgAECgMJBwAAAA==.Monkerooz:BAAALgAECgUJCAAAAA==.Moodeng:BAAALgADCgYJBwAAAA==.Morphîne:BAACLgAFFH8IAAIQAAIJvBNAVQBxAAAQAAIJvBNAVQBxAAAuAAQKfxcAAhAABwkZHvEoABACABAABwkZHvEoABACAAAA.',
Mu='Mugwump:BAAALgAECggJEwAAAA==.Murdõk:BAAALgAECgEJAQABLgAFFAIJBQAGALsMAA==.Murdøk:BAACLgAFFH8FAAMGAAIJuwy16ACAAAAGAAIJuwy16ACAAAAWAAEJhgNLLQA0AAAuAAQKfx0ABAYACQmuGAtdALEBAAYACQmuGAtdALEBAAcAAQnpDThEADgAABYAAQmqCYI+ACoAAAAA.',
My='Mythic:BAABLgAECn8pAAIVAAkJdBuHDgBgAgAVAAkJdBuHDgBgAgAAAA==.',
['Mû']='Mûrdok:BAAALgAECgUJDQABLgAFFAIJBQAGALsMAA==.',
['Mü']='Mürdok:BAAALgAECgYJDAABLgAFFAIJBQAGALsMAA==.',
Ne='Necromortas:BAAALgAECgcJBwAAAA==.Nefarius:BAABLgAECn8WAAMOAAkJLhseWgCPAQAOAAgJLhseWgCPAQAeAAMJWxRgOwDGAAABLgAFFAEJAQACAAAAAA==.Neph:BAABLgAECn8aAAMfAAkJQw96HwDlAQAfAAkJQw96HwDlAQATAAIJbgNeUABNAAAAAA==.Nezot:BAAALgAECgUJBgAAAA==.',
Ni='Nihilism:BAAALgADCgYJBgAAAA==.Ninsu:BAAALgAECgYJCgAAAA==.Nishale:BAAALgAECgMJBQAAAA==.',
No='Noir:BAAALgADCgQJBAAAAA==.',
Nu='Nutdraggin:BAAALgADCgcJBwAAAA==.',
Ny='Nyki:BAAALgAECggJDwAAAA==.',
On='Onlyfist:BAAALgAECgEJAgAAAA==.',
Op='Opius:BAAALgAECgkJEgAAAA==.',
Or='Orcmagic:BAAALgADCgcJCQAAAA==.',
Os='Oshift:BAAALgAECgYJBgAAAA==.',
Pa='Pakk:BAAALgAECgUJBwAAAA==.Pandinha:BAACLgAFFH8ZAAIGAAQJ8B1GYwAwAQAGAAQJ8B1GYwAwAQAuAAQKfzgAAgYACQkEIywMADkDAAYACQkEIywMADkDAAAA.Paolinelli:BAABLgAFFH8HAAMgAAQJRBiHAgDuAAAgAAQJeBaHAgDuAAARAAIJhiA3PQC4AAABLgAFFAcJFQAYACQiAA==.Pattêrn:BAAALgAECgYJEwAAAA==.',
Pd='Pdr:BAAALgADCgcJBwAAAA==.',
Pe='Pedri:BAABLgAFFH8KAAMGAAMJQhm0igD0AAAGAAMJQhm0igD0AAAWAAEJlw+bJwBHAAAAAA==.Pedrok:BAAALgAECgUJDQAAAA==.Perses:BAAALgAECgYJCgAAAA==.',
Ph='Phoenixashes:BAAALgADCgIJAgAAAA==.',
Pi='Picklestein:BAAALgAECgEJAQAAAA==.',
Po='Pokz:BAAALgADCgEJAQAAAA==.',
Pr='Priestiality:BAAALgAECgIJBAAAAA==.Promix:BAAALgAECgEJAQAAAA==.Prowl:BAAALgAECgEJAQABLgAFFAgJFwAgAGsYAA==.Prscilla:BAAALgADCgcJBgAAAA==.',
['Pë']='Përseu:BAAALgAECgMJAwAAAA==.',
Qu='Quixote:BAAALgAECgcJCwAAAA==.',
Ra='Radagast:BAAALgADCgcJDQABLgAFFAQJFgAKADcNAA==.Radulf:BAAALgAECgQJBAAAAA==.Raph:BAACLgAFFH8VAAIGAAYJIRreMQChAQAGAAYJIRreMQChAQAuAAQKfyoAAgYACAnmH+A4ABwCAAYACAnmH+A4ABwCAAAA.Raphy:BAABLgAFFH8IAAIGAAMJthBfoADUAAAGAAMJthBfoADUAAABLgAFFAYJFQAGACEaAA==.Ravyn:BAAALgADCgUJBQAAAA==.',
Re='Reckon:BAAALgAECgYJDAAAAA==.Redthedeer:BAAALgAFFAIJAgAAAA==.Redthedragon:BAAALgAECgEJAQAAAA==.Redthepriest:BAAALgAECgEJAQAAAA==.Redzone:BAAALgAECgQJBgAAAA==.Refuliya:BAAALgADCgkJBwAAAA==.Remmahcm:BAABLgAECn8VAAIJAAgJUBYvPwApAgAJAAgJUBYvPwApAgAAAA==.Renewing:BAAALgADCgQJBAAAAA==.Renrir:BAAALgADCgcJCAAAAA==.Rezen:BAAALgAFFAIJAgAAAA==.',
Rh='Rhark:BAAALgAECgUJDQAAAA==.',
Ri='Rikku:BAABLgAFFH8FAAIMAAIJrAXSAAB+AAAMAAIJrAXSAAB+AAAAAA==.',
Ro='Rook:BAABLgAECn8yAAMJAAkJKyJmDQD6AgAJAAkJKyJmDQD6AgAhAAUJBghdNwCCAAAAAA==.',
Ru='Runnow:BAAALgADCgYJCwAAAA==.',
Sa='Saebi:BAAALgADCgkJCQAAAA==.Sagas:BAAALgAFFAMJAwAAAA==.Salina:BAAALgAECgEJAQABLgAECgMJBQACAAAAAA==.Sammysam:BAAALgADCgUJBwAAAA==.Santairon:BAAALgAECgEJAgAAAA==.Sathor:BAAALgADCgkJDgAAAA==.',
Sc='Scotch:BAAALgADCgQJBAABLgAFFAUJFQAVAGkTAA==.',
Sh='Shaffios:BAAALgAECgYJDAAAAA==.Shelton:BAAALgADCgMJAwABLgADCggJDQACAAAAAA==.Shinjey:BAAALgAECgMJBwAAAA==.Shocker:BAAALgAECgEJAQAAAA==.',
Si='Sil:BAABLgAECn8ZAAIiAAkJCwr1FwCXAQAiAAkJCwr1FwCXAQAAAA==.Silents:BAAALgAECgUJBQAAAA==.Siphon:BAAALgAECgYJDAAAAA==.Siphons:BAAALgAECgMJBAAAAA==.',
Sk='Ska:BAACLgAFFH8bAAIOAAcJvBaLHwDUAQAOAAcJvBaLHwDUAQAuAAQKfxsAAw4ACAm7H1oYAMICAA4ACAm7H1oYAMICAB4AAQkAAJNwADUAAAAA.',
Sl='Slyzete:BAAALgAECgQJBwAAAA==.',
So='Softbutt:BAABLgAECn8aAAIRAAgJcQx3AQBKAQARAAgJcQx3AQBKAQAAAA==.Sophiae:BAAALgAECgIJAgAAAA==.Sophie:BAAALgADCgcJBwAAAA==.Soulseeker:BAABLgAECn8pAAQOAAgJChVVSQC+AQAOAAgJyBRVSQC+AQAeAAIJfBRoUAB9AAAjAAEJgBFQBAA6AAAAAA==.',
Sp='Spriz:BAAALgAFFAEJBAAAAA==.',
St='Stölen:BAAALgAECgEJAQAAAA==.',
Sy='Sylthas:BAAALgADCgMJAwAAAA==.Syrensong:BAAALgAECgQJBAAAAA==.',
Ta='Tankli:BAAALgAECgIJBgAAAA==.Tanriel:BAAALgAECgEJAQAAAA==.Tatl:BAAALgAECgIJBwAAAA==.',
Te='Tertletoes:BAABLgAECn8cAAQkAAkJECXvAAC+AwAkAAkJECXvAAC+AwALAAEJ2x46JwBMAAAKAAEJ/h3c2gA5AAAAAA==.Terts:BAAALgAECgEJAQABLgAECgkJHAAkABAlAA==.Teto:BAAALgAECgYJDgAAAA==.',
Th='Thanaz:BAAALgAECgUJCQAAAA==.Thebartender:BAAALgAECgcJDAAAAA==.Thella:BAAALgAECgQJBgAAAA==.Thopowisiwi:BAAALgAFFAIJBAAAAA==.',
To='Tog:BAABLgAECn8bAAIQAAkJciLGAwBVAwAQAAkJciLGAwBVAwAAAA==.Togame:BAAALgAECgUJCAAAAA==.Toggie:BAAALgAECgEJAQAAAA==.Tognahok:BAAALgADCgYJDgAAAA==.Togy:BAAALgADCgEJAQAAAA==.Tortoisetoes:BAAALgAECgIJAgABLgAECgkJHAAkABAlAA==.',
Tr='Tremboladin:BAABLgAECn8aAAIDAAcJHxo1JgD2AQADAAcJHxo1JgD2AQABLgAFFAQJFgACAAAAAA==.',
Ts='Tsnt:BAAALgAECgEJAQAAAA==.',
Tu='Turbosocks:BAAALgAECgYJCgAAAA==.Turok:BAAALgADCgMJAwAAAA==.Turtles:BAAALgADCgEJAQABLgAECgkJHAAkABAlAA==.Tuskydin:BAAALgADCgcJCQAAAA==.',
Ty='Tydrin:BAAALgAECgIJAwAAAA==.Tylandord:BAAALgADCgEJAQAAAA==.',
['Tý']='Týråél:BAAALgADCgYJCwAAAA==.',
Ur='Urra:BAABLgAECn8rAAIcAAgJEB4OHwDqAQAcAAgJEB4OHwDqAQAAAA==.',
Va='Vai:BAAALgAECgYJCQAAAA==.Valkyrie:BAABLgAFFH8GAAIJAAQJ2xhYNQBEAQAJAAQJ2xhYNQBEAQABLgAFFAUJEQAEAKMeAA==.Valoo:BAAALgAECgQJCgAAAA==.Valunar:BAAALgADCgUJBQAAAA==.',
Ve='Veyron:BAAALgADCgMJAwAAAA==.',
Vi='Vicar:BAAALgAECgcJDAAAAA==.',
Vo='Voidstrider:BAAALgAECggJEAAAAA==.',
Wa='Wargyu:BAAALgAECgMJAwABLgAFFAYJDAAaABgVAA==.',
We='Weezard:BAACLgAFFH8JAAIEAAQJvAihbgAFAQAEAAQJvAihbgAFAQAuAAQKfy8AAgQACQmPFvI7ACoCAAQACQmPFvI7ACoCAAAA.',
Wh='Wheein:BAABLgAECn8jAAITAAkJ1iGDBwACAwATAAkJ1iGDBwACAwAAAA==.',
Wi='Wingolingo:BAAALgAECgIJAgAAAA==.',
Xe='Xeren:BAAALgADCgEJAQAAAA==.',
Xi='Xioa:BAAALgADCgEJAQAAAA==.',
Ya='Yaamoonn:BAAALgADCgUJBQAAAA==.',
Ye='Yenn:BAABLgAECn8bAAMOAAkJXhtHFgDPAgAOAAkJXhtHFgDPAgAeAAIJwAEuWgBgAAAAAA==.',
Za='Zardnax:BAAALgAECgIJAgAAAA==.',
Ze='Zenin:BAAALgADCggJFQAAAA==.Zensky:BAAALgAECgMJAwAAAA==.Zenu:BAACLgAFFH8MAAMcAAQJwhR8JAAHAQAcAAQJ1hJ8JAAHAQAlAAMJqg7JDwDJAAAuAAQKfyUAAxwACQlQGxYSAJICABwACQlQGxYSAJICACUABAk1FlwoALQAAAAA.',
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
