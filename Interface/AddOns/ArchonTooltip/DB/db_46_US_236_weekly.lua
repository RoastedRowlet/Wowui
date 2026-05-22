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

local lookup = {'Druid-Balance','Unknown-Unknown','Mage-Frost','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Druid-Guardian','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Druid-Restoration','Warrior-Fury','Monk-Brewmaster','Evoker-Preservation','Monk-Windwalker','DeathKnight-Frost','Priest-Discipline','Paladin-Holy','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Augmentation','Evoker-Devastation','Shaman-Restoration','Shaman-Elemental','Druid-Feral','Priest-Holy','Warrior-Arms','Warrior-Protection','Warlock-Destruction','DemonHunter-Havoc','Shaman-Enhancement',}
local provider = {region='US',realm='Warsong',name='US',type='weekly',zone=46,date='2026-05-17',data={Ad='Adònis:BAAALgADCgEJAQAAAA==.',
Ae='Aesudan:BAAALgADCgEJAQAAAA==.',
Ah='Aharan:BAABLgAECn8gAAIBAAYJ5gxIOADnAAABAAYJ5gxIOADnAAAAAA==.',
Ai='Aiona:BAAALgADCgYJDAAAAA==.',
Al='Alandrov:BAAALgADCgEJAQAAAA==.Alexanzalone:BAAALgADCggJCAAAAA==.Allenduin:BAAALgAECgEJAQAAAA==.Alodso:BAAALgADCgEJAQAAAA==.',
An='Angryballz:BAAALgAECgYJBwABLgAECgYJCwACAAAAAA==.Angz:BAAALgAECgUJDQAAAA==.Anielor:BAAALgADCgMJAwAAAA==.Anuksuna:BAAALgAECgUJCQABLgAECgYJEwACAAAAAA==.',
Ar='Arcadia:BAAALgAECgYJDgAAAA==.Arcane:BAACLgAFFH8JAAIDAAUJLh1jJgBuAQADAAUJLh1jJgBuAQAuAAQKfx8AAwMACQngIVwQAEYDAAMACQngIVwQAEYDAAQABQlDJBcFAOkBAAAA.',
As='Asta:BAAALgAECgQJBAAAAA==.',
At='Atulan:BAAALgADCgQJBAAAAA==.',
Au='Austin:BAAALgADCggJFgAAAA==.Automobeer:BAAALgAECgEJBAAAAA==.',
Aw='Awake:BAABLgAECn8hAAMFAAcJZBQiZgBiAQAFAAcJjRIiZgBiAQAGAAYJ2hJWHwBKAQAAAA==.',
Az='Azazzel:BAAALgADCgEJAQAAAA==.',
Ba='Bambietta:BAAALgADCgkJCQAAAA==.Barebelly:BAAALgAECggJEAAAAA==.',
Be='Bearforce:BAABLgAECn8eAAIHAAkJjxnZCAAbAgAHAAkJjxnZCAAbAgAAAA==.',
Bi='Biggbird:BAABLgAECn8bAAIBAAYJkRo/IgBpAQABAAYJkRo/IgBpAQAAAA==.',
Bl='Blewbawl:BAAALgADCgEJAQAAAA==.Blutwin:BAABLgAECn8kAAIIAAkJThKoNwDnAQAIAAkJThKoNwDnAQAAAA==.Bluud:BAAALgADCgMJAwAAAA==.',
Bo='Bossdierr:BAACLgAFFH8PAAIJAAMJFyNQJwA0AQAJAAMJFyNQJwA0AQAuAAQKfzIAAwkACQkyI/8KAL8CAAkACQkyI/8KAL8CAAoACAlCE38LAFkBAAAA.Bossdisan:BAACLgAFFH8KAAIDAAQJMho9KgAMAQADAAQJMho9KgAMAQAuAAQKfygAAgMABglsJLJBAN4BAAMABglsJLJBAN4BAAAA.Bossmasster:BAAALgAFFAIJAgAAAA==.Bosswudi:BAABLgAFFH8HAAMLAAIJMRPLBwCZAAAMAAIJygi0FQCgAAALAAIJsQ7LBwCZAAAAAA==.',
Br='Brashe:BAABLgAECn8YAAIDAAYJkg6FlwAaAQADAAYJkg6FlwAaAQAAAA==.Breathe:BAAALgAECgQJBAAAAA==.Brickbeard:BAAALgAECgYJBgABLgAECgcJEQACAAAAAA==.Bruv:BAABLgAECn8jAAINAAYJhhU5bwCCAQANAAYJhhU5bwCCAQAAAA==.',
Ca='Calathis:BAAALgAECgEJAQAAAA==.Cazadòr:BAAALgAECgIJAgAAAA==.',
Ch='Chromiepip:BAAALgADCgMJAwAAAA==.',
Co='Corbann:BAAALgAECgYJCgAAAA==.',
Cr='Creamcheese:BAABLgAECn8aAAIOAAcJUB2MJwDaAQAOAAcJUB2MJwDaAQAAAA==.Creamy:BAABLgAECn8oAAIPAAgJ2hniGADmAQAPAAgJ2hniGADmAQAAAA==.Crossbreed:BAAALgAECgQJBQAAAA==.',
Cy='Cyr:BAAALgADCgUJBQAAAA==.Cytosine:BAAALgAFFAEJAQAAAA==.',
Da='Daddyhaz:BAACLgAFFH8FAAIJAAMJZBS3PQDsAAAJAAMJZBS3PQDsAAAuAAQKf0MAAgkACQmzJGkCAEcDAAkACQmzJGkCAEcDAAAA.Daddywhyudie:BAAALgADCgEJAQAAAA==.Daelyte:BAAALgAECgYJDwAAAA==.Daghor:BAABLgAFFH8GAAIMAAIJLBqSIACkAAAMAAIJLBqSIACkAAAAAA==.',
De='Deltron:BAAALgAECgEJAQAAAA==.Desetre:BAAALgADCgIJAgAAAA==.',
Di='Dinks:BAABLgAECn8xAAIDAAkJ4hbrOAD9AQADAAkJ4hbrOAD9AQAAAA==.Ditzy:BAAALgAECgEJAQAAAA==.',
Do='Docc:BAABLgAECn8XAAIMAAkJGA+nFgBXAgAMAAkJGA+nFgBXAgAAAA==.Domdps:BAAALgAECgEJAQAAAA==.',
Dr='Draan:BAAALgADCgUJBwAAAA==.Dragorr:BAAALgADCgcJBwAAAA==.Dreadpanda:BAAALgADCgMJAwABLgAFFAQJCAAQALIiAA==.Drekkarn:BAAALgADCgMJBAAAAA==.Drood:BAAALgAECgEJAQAAAA==.',
El='Elzath:BAAALgADCggJEAABLgAECgkJIwARAIkUAA==.',
En='Enix:BAAALgADCgYJBgABLgAFFAIJCAAOALwTAA==.',
Er='Erdrick:BAAALgAECgIJBAAAAA==.',
Es='Espeon:BAAALgAECgcJDgAAAA==.',
Eu='Eudisius:BAAALgADCgEJAQAAAA==.',
Ev='Evara:BAABLgAECn8UAAIDAAYJAwdU7gAcAQADAAYJAwdU7gAcAQAAAA==.',
Fa='Fangbot:BAAALgAECgEJAgAAAA==.',
Fe='Felcaas:BAAALgADCgQJBAAAAA==.Felini:BAABLgAECn8bAAIPAAcJvQfXQAD/AAAPAAcJvQfXQAD/AAAAAA==.Feronar:BAABLgAECn8nAAIPAAkJsgpuJACRAQAPAAkJsgpuJACRAQAAAA==.',
Fi='Fizzwater:BAAALgAECgUJBQAAAA==.',
Fl='Fleepity:BAAALgAECgcJDQAAAA==.Floopity:BAAALgADCgYJBwAAAA==.Flowermom:BAAALgAECgEJAgAAAA==.Flume:BAAALgAECgcJBwAAAA==.',
Fu='Fusíon:BAEBLgAECn8zAAIJAAkJdiIwDgANAwAJAAkJdiIwDgANAwAAAA==.',
Gi='Gin:BAACLgAFFH8JAAISAAQJMwrpEAD/AAASAAQJMwrpEAD/AAAuAAQKfy8AAhIACQn3GigNAC8CABIACQn3GigNAC8CAAAA.',
Gj='Gjana:BAAALgAECgQJBAABLgAECgYJFAADAIMQAA==.',
Gl='Glamdring:BAAALgADCgMJAwAAAA==.Glunty:BAAALgAECgUJCAAAAA==.',
Go='Goldpaw:BAAALgADCgEJAQAAAA==.Gorlash:BAAALgAECgYJBwAAAA==.',
Gr='Gridinn:BAAALgADCgIJAgAAAA==.Grimgeth:BAACLgAFFH8JAAIFAAMJcBSgZQDxAAAFAAMJcBSgZQDxAAAuAAQKfy4ABAUACAmMH0YgAE4CAAUACAmRHkYgAE4CAAYAAwlXHwwrALUAABMAAgnlF/oiADkAAAAA.Grimwrath:BAAALgAECgUJBwABLgAFFAMJCQAFAHAUAA==.',
Gu='Gugaman:BAAALgADCgcJDgAAAA==.Guishin:BAAALgAECgEJAgAAAA==.',
He='Healpls:BAAALgAECgEJAgAAAA==.Heidriel:BAAALgAECgMJAwAAAA==.Herumesu:BAAALgADCgcJCgABLgAFFAQJDgAFAAIdAA==.',
Ho='Holapes:BAAALgAECgUJDwABLgAECgMJBAACAAAAAA==.',
Hu='Huhbruh:BAAALgAECgIJAgABLgAECgYJIwANAIYVAA==.',
Hw='Hwasa:BAABLgAECn8jAAIQAAkJ4h08CACDAgAQAAkJ4h08CACDAgAAAA==.',
Il='Illigari:BAAALgAFFAEJAQAAAA==.',
In='Indy:BAAALgADCgUJCAAAAA==.Insanities:BAABLgAECn83AAIUAAkJQSFMAwA/AwAUAAkJQSFMAwA/AwAAAA==.Inti:BAABLgAECn8WAAIVAAYJZhu0JACjAQAVAAYJZhu0JACjAQABLgAFFAIJCAAOALwTAA==.',
Ja='Jaidie:BAAALgAECgQJBgAAAA==.',
Je='Jeffreyx:BAAALgAECgYJCAAAAA==.Jeffreyz:BAAALgADCgYJBgAAAA==.',
Jo='Joak:BAAALgADCgUJBQAAAA==.Jota:BAAALgADCgcJCAAAAA==.',
Ka='Kahlán:BAAALgAECgYJEwAAAA==.Karlangas:BAAALgAECgMJBAAAAA==.',
Ki='Kifu:BAAALgADCgEJAQABLgAECgYJFAADAIMQAA==.Kikipants:BAAALgADCgEJAQAAAA==.Kitrix:BAAALgADCgUJBQAAAA==.Kitty:BAAALgAECgQJBAABLgAFFAMJCgAHAIEIAA==.',
Kr='Krue:BAAALgADCggJDQAAAA==.',
Ku='Kubimage:BAABLgAECn8aAAIDAAkJKhu2MgCoAgADAAkJKhu2MgCoAgAAAA==.',
La='Lane:BAAALgADCgEJAQAAAA==.Layona:BAAALgAECgYJCgAAAA==.',
Le='Lerroy:BAAALgADCgcJCQAAAA==.',
Li='Lildar:BAABLgAECn8gAAIFAAgJjxrTOwDaAQAFAAgJjxrTOwDaAQAAAA==.Linelli:BAAALgAECgcJCwABLgAFFAUJEgAWALUkAA==.Lirra:BAAALgAFFAIJBAABLgAFFAIJCAAOALwTAA==.',
Lo='Lorthiel:BAAALgADCgIJAgAAAA==.Lothus:BAACLgAFFH8GAAIXAAIJKhuHSwCkAAAXAAIJKhuHSwCkAAAuAAQKfxUAAxcACQkPGzAYAHgCABcACQkPGzAYAHgCABgAAQl2BGOTACcAAAEuAAUUAgkIAA4AvBMA.Lox:BAAALgAECgMJAwAAAA==.',
Ls='Lsblkxd:BAAALgADCgYJBgAAAA==.',
Lu='Lumen:BAAALgAECgEJAQAAAA==.Lumverjvcked:BAAALgAECgYJDAABLgAECgYJIwANAIYVAA==.',
Lx='Lxrbread:BAACLgAFFH8OAAMZAAMJbgxrLADTAAAZAAMJbgxrLADTAAARAAEJ5QPaGAA8AAAuAAQKfzkABBkACQlQFR8ZAMsBABkACQkuFR8ZAMsBABEABQlBBdY3AK0AABoAAgmoCsEcADkAAAAA.',
['Lë']='Lëgitz:BAABLgAECn8lAAMbAAkJuh9yBgAJAwAbAAkJuh9yBgAJAwAcAAgJIBRtIACXAQAAAA==.',
Ma='Macca:BAAALgAECgUJBQABLgAECgYJCwACAAAAAA==.Maccazilla:BAAALgAECgYJCwAAAA==.Magdalena:BAACLgAFFH8NAAISAAQJnCFJBACLAQASAAQJnCFJBACLAQAuAAQKfyUAAhIACQkDJb8CAG0DABIACQkDJb8CAG0DAAAA.Magedand:BAAALgAECgMJAwAAAA==.Magnesson:BAAALgAFFAEJAgAAAA==.Manakaren:BAAALgADCggJDAAAAA==.Mazuro:BAACLgAFFH8UAAIMAAUJah0eDwBMAQAMAAUJah0eDwBMAQAuAAQKfy4AAwwACQm5HToIAGICAAwACQm5HToIAGICAAsAAQlGGVodAEAAAAAA.',
Me='Meatkleaver:BAABLgAECn8bAAMTAAkJ0BUhAwBnAgATAAkJ0BUhAwBnAgAFAAEJqAGXNgEiAAAAAA==.Meau:BAABLgAECn8jAAIdAAkJmR4uAwCkAgAdAAkJmR4uAwCkAgAAAA==.Mechadar:BAAALgAECgMJAwAAAA==.Mechanizedtv:BAACLgAFFH8JAAIHAAMJnx8rBgAeAQAHAAMJnx8rBgAeAQAuAAQKf8wABAcACQmyJh0AAIwDAAcACQmyJh0AAIwDAB0ABgl4HH4MAJ0BAAEAAQlmArZ9ABwAAAAA.',
Mi='Mitskí:BAAALgAECgQJBAAAAA==.',
Mo='Monkerooz:BAAALgAECgUJCAAAAA==.Moodeng:BAAALgADCgYJBwAAAA==.Morphîne:BAACLgAFFH8IAAIOAAIJvBP3OwCHAAAOAAIJvBP3OwCHAAAuAAQKfxcAAg4ABwkZHvEoABACAA4ABwkZHvEoABACAAAA.',
Mu='Mugwump:BAAALgAECgQJBAAAAA==.Murdøk:BAABLgAECn8VAAMFAAYJKBdMlwBRAQAFAAYJKBdMlwBRAQAGAAEJ6Q04RAA4AAAAAA==.',
My='Mythic:BAABLgAECn8mAAISAAgJ6Rq1DgAbAgASAAgJ6Rq1DgAbAgAAAA==.',
['Mû']='Mûrdok:BAAALgAECgUJDAABLgAECgYJFQAFACgXAA==.',
['Mü']='Mürdok:BAAALgAECgYJCAABLgAECgYJFQAFACgXAA==.',
Ne='Necromortas:BAAALgAECgcJBwAAAA==.Nefarius:BAAALgAECggJEwAAAA==.Neph:BAABLgAECn8aAAMeAAkJQw96HwDlAQAeAAkJQw96HwDlAQAUAAIJbgNeUABNAAAAAA==.Nezot:BAAALgADCgcJBwAAAA==.',
Ni='Nihilism:BAAALgADCgYJBgAAAA==.Ninsu:BAAALgAECgYJCgAAAA==.Nishale:BAAALgAECgMJBQAAAA==.',
No='Noir:BAAALgADCgQJBAAAAA==.',
Nu='Nutdraggin:BAAALgADCgcJBwAAAA==.',
Ny='Nyki:BAAALgAECgcJDQAAAA==.',
On='Onlyfist:BAAALgAECgEJAgAAAA==.',
Op='Opius:BAAALgAECggJDgAAAA==.',
Or='Orcmagic:BAAALgADCgUJBwAAAA==.',
Os='Oshift:BAAALgAECgYJBgAAAA==.',
Pa='Pandinha:BAACLgAFFH8VAAIFAAQJ8B3/MABVAQAFAAQJ8B3/MABVAQAuAAQKfzYAAgUACQk1ISwMADkDAAUACQk1ISwMADkDAAAA.Paolinelli:BAAALgAECgMJBQABLgAFFAUJEgAWALUkAA==.Pattêrn:BAAALgAECgYJCAAAAA==.',
Pd='Pdr:BAAALgADCgcJBwAAAA==.',
Pe='Pedri:BAABLgAFFH8HAAIFAAIJvyIHdwDIAAAFAAIJvyIHdwDIAAAAAA==.Pedrok:BAAALgAECgMJBQAAAA==.',
Ph='Phoenixashes:BAAALgADCgIJAgAAAA==.',
Pi='Picklestein:BAAALgADCgcJBwAAAA==.',
Po='Pokz:BAAALgADCgEJAQAAAA==.',
Pr='Priestiality:BAAALgAECgIJAwAAAA==.Prowl:BAAALgAECgEJAQABLgAFFAYJFAAfALgYAA==.Prscilla:BAAALgADCgcJBgAAAA==.',
Qu='Quixote:BAAALgAECgUJBQAAAA==.',
Ra='Radagast:BAAALgADCgcJDQABLgAFFAMJBQAJAJ4DAA==.Radulf:BAAALgAECgQJBAAAAA==.Raph:BAACLgAFFH8OAAIFAAQJAh2qMQBUAQAFAAQJAh2qMQBUAQAuAAQKfykAAgUACAnhHxspACICAAUACAnhHxspACICAAAA.Raphy:BAAALgAFFAMJAwABLgAFFAQJDgAFAAIdAA==.Ravyn:BAAALgADCgUJBQAAAA==.',
Re='Reckon:BAAALgAECgYJDAAAAA==.Redthedeer:BAAALgAECgcJCgAAAA==.Redzone:BAAALgAECgQJBgAAAA==.Refuliya:BAAALgADCgkJBwAAAA==.Remmahcm:BAABLgAECn8VAAIIAAgJUBYvPwApAgAIAAgJUBYvPwApAgAAAA==.Renewing:BAAALgADCgQJBAAAAA==.Renrir:BAAALgADCgcJCAAAAA==.',
Rh='Rhark:BAAALgAECgUJDQAAAA==.',
Ri='Rikku:BAAALgAFFAIJAwAAAA==.',
Ro='Rook:BAABLgAECn8iAAIIAAkJ4CGdBgAQAwAIAAkJ4CGdBgAQAwAAAA==.',
Ru='Runnow:BAAALgADCgYJCwAAAA==.',
Sa='Sagas:BAAALgAECgEJAQAAAA==.Salina:BAAALgAECgEJAQABLgAECgMJBQACAAAAAA==.Sammysam:BAAALgADCgUJBwAAAA==.Sathor:BAAALgADCgkJDgAAAA==.',
Sc='Scotch:BAAALgADCgQJBAABLgAFFAQJCQASADMKAA==.',
Sh='Shelton:BAAALgADCgMJAwABLgADCggJDQACAAAAAA==.Shinjey:BAAALgAECgMJBwAAAA==.Shocker:BAAALgAECgEJAQAAAA==.',
Si='Sil:BAABLgAECn8ZAAIgAAkJCwr1FwCXAQAgAAkJCwr1FwCXAQAAAA==.Silents:BAAALgAECgUJBQAAAA==.Siphon:BAAALgAECgYJDAAAAA==.Siphons:BAAALgAECgMJBAAAAA==.',
Sk='Ska:BAACLgAFFH8WAAINAAcJsBLECQDWAQANAAcJsBLECQDWAQAuAAQKfxsAAw0ACAm7H1oYAMICAA0ACAm7H1oYAMICACEAAQkAAJNwADUAAAAA.',
Sl='Slyzete:BAAALgAECgQJBwAAAA==.',
So='Softbutt:BAAALgAECggJDwAAAA==.Sophie:BAAALgADCgcJBwAAAA==.Soulseeker:BAABLgAECn8dAAMNAAcJsxQ4bQAyAQANAAcJZhQ4bQAyAQAhAAIJfBRoUAB9AAAAAA==.',
St='Stölen:BAAALgAECgEJAQAAAA==.',
Sy='Sylthas:BAAALgADCgMJAwAAAA==.Syrensong:BAAALgAECgQJBAAAAA==.',
Ta='Tankli:BAAALgAECgIJBgAAAA==.Tanriel:BAAALgAECgEJAQAAAA==.Tatl:BAAALgADCgkJEQAAAA==.',
Te='Tertletoes:BAABLgAECn8cAAQiAAkJECXvAAC+AwAiAAkJECXvAAC+AwAKAAEJ2x46JwBMAAAJAAEJ/h3c2gA5AAAAAA==.Terts:BAAALgAECgEJAQABLgAECgkJHAAiABAlAA==.Teto:BAAALgAECgYJDgAAAA==.',
Th='Thanaz:BAAALgAECgEJAQAAAA==.Thebartender:BAAALgAECgcJDAAAAA==.Thella:BAAALgAECgQJBgAAAA==.Thopowisiwi:BAAALgAECggJDgAAAA==.',
To='Tog:BAABLgAECn8bAAIOAAkJciLGAwBVAwAOAAkJciLGAwBVAwAAAA==.Togame:BAAALgAECgUJCAAAAA==.Toggie:BAAALgADCgkJDAAAAA==.Tognahok:BAAALgADCgYJDgAAAA==.Togy:BAAALgADCgEJAQAAAA==.Tortoisetoes:BAAALgAECgIJAgABLgAECgkJHAAiABAlAA==.',
Tr='Tremboladin:BAABLgAECn8aAAIVAAcJHxo1JgD2AQAVAAcJHxo1JgD2AQABLgAFFAQJDAAZAP0MAA==.',
Ts='Tsnt:BAAALgAECgEJAQAAAA==.',
Tu='Turbosocks:BAAALgAECgIJBQAAAA==.Turok:BAAALgADCgMJAwAAAA==.Turtles:BAAALgADCgEJAQABLgAECgkJHAAiABAlAA==.Tuskydin:BAAALgADCgcJCQAAAA==.',
Ty='Tydrin:BAAALgAECgIJAwAAAA==.Tylandord:BAAALgADCgEJAQAAAA==.',
['Tý']='Týråél:BAAALgADCgYJCwAAAA==.',
Ur='Urra:BAABLgAECn8rAAIcAAgJEh6XFAD9AQAcAAgJEh6XFAD9AQAAAA==.',
Va='Valoo:BAAALgAECgQJCgAAAA==.Valunar:BAAALgADCgUJBQAAAA==.',
Ve='Veyron:BAAALgADCgMJAwAAAA==.',
Vi='Vicar:BAAALgAECgIJAgAAAA==.',
Vo='Voidstrider:BAAALgAECggJEAAAAA==.',
We='Weezard:BAABLgAECn8UAAIDAAYJgxBm1wCrAAADAAYJgxBm1wCrAAAAAA==.',
Wh='Wheein:BAABLgAECn8jAAIUAAkJ1yF1BAAUAwAUAAkJ1yF1BAAUAwAAAA==.',
Wi='Wingolingo:BAAALgAECgIJAgAAAA==.',
Xe='Xeren:BAAALgADCgEJAQAAAA==.',
Ya='Yaamoonn:BAAALgADCgUJBQAAAA==.',
Ye='Yenn:BAABLgAECn8bAAMNAAkJXhtHFgDPAgANAAkJXhtHFgDPAgAhAAIJwAEuWgBgAAAAAA==.',
Za='Zardnax:BAAALgADCgIJBAAAAA==.',
Ze='Zenin:BAAALgADCggJFQAAAA==.Zenu:BAACLgAFFH8FAAIcAAMJyAwRIgDQAAAcAAMJyAwRIgDQAAAuAAQKfyQAAxwACQnrGhYSAJICABwACQnrGhYSAJICACMABAk1FskaALkAAAAA.',
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
