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

local lookup = {'Warlock-Destruction','Warlock-Demonology','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Devourer','Warrior-Fury','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','Paladin-Protection','Hunter-Survival','Shaman-Restoration','Monk-Brewmaster','Unknown-Unknown','DeathKnight-Blood','Priest-Shadow','Warrior-Arms','Evoker-Devastation','Monk-Windwalker','Druid-Guardian','Shaman-Elemental','Warrior-Protection','Warlock-Affliction','Druid-Restoration','Rogue-Outlaw','Monk-Mistweaver','Mage-Arcane','Mage-Fire','Druid-Feral','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Vengeance','Priest-Discipline','Druid-Balance','Hunter-BeastMastery',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abeblinkin:BAAALgAECgkJDwAAAA==.Aborlight:BAAALgAECgUJDwAAAA==.',
Ad='Adit:BAABLgAECn8cAAMBAAgJGxI2DgBZAQABAAgJyxA2DgBZAQACAAYJ+BHrCQD7AAAAAA==.Adug:BAAALgADCgMJAwAAAA==.',
Ae='Aedrius:BAABLgAECn8ZAAMDAAcJLhjINQClAQADAAYJrRnINQClAQAEAAQJlxECwQAFAQAAAA==.',
Ag='Agnekie:BAABLgAECn8XAAIEAAcJqRcXZgCjAQAEAAcJqRcXZgCjAQAAAA==.',
Ai='Aiwass:BAABLgAECn9XAAIBAAkJnhToBgDuAQABAAkJnhToBgDuAQAAAA==.Aiyo:BAABLgAFFH8GAAMFAAIJxAqN6wB+AAAFAAIJxAqN6wB+AAAGAAEJOgviJwBGAAABLgAFFAUJBgAHAEAVAA==.',
Al='Alexander:BAAALgAECgMJAwAAAA==.Alpharius:BAAALgAECgUJCAAAAA==.',
Am='Amathricus:BAABLgAECn81AAIEAAkJihDPYACvAQAEAAkJihDPYACvAQAAAA==.Amerika:BAAALgADCgIJAgAAAA==.',
Ar='Arawak:BAAALgADCgEJAQAAAA==.',
As='Ashuk:BAABLgAECn8gAAIIAAYJzwgOXADiAAAIAAYJzwgOXADiAAAAAA==.',
At='Athena:BAAALgAECgMJAwAAAA==.',
Au='Augtism:BAECLgAFFH8KAAMJAAUJgA+dGQD8AAAJAAQJ1Q+dGQD8AAAKAAQJgAq7OwDYAAAuAAQKfx0AAwoABwmfHrMgANQBAAoABwmfHrMgANQBAAkAAgm2Ef4tAHsAAAEuAAUUBQkKAAkAgA8A.Auitou:BAAALgAECggJCQAAAA==.Auralei:BAABLgAECn8jAAILAAgJLwkOmgBFAQALAAgJLwkOmgBFAQAAAA==.',
Az='Azelia:BAAALgAECggJEwABLgAECgkJKgADADoVAA==.Aziendha:BAAALgAECgIJAgABLgAECgkJKgADADoVAA==.Azzy:BAABLgAECn8qAAQDAAkJOhXvJQDYAQADAAgJpRfvJQDYAQAMAAMJLgK3SgBAAAAEAAIJ9gG2tQEoAAAAAA==.',
Be='Beasti:BAAALgAECgIJAgAAAA==.Beelzebul:BAAALgAFFAQJBAABLgAFFAcJLAAFADQeAA==.',
Bi='Bigb:BAABLgAECn8mAAINAAcJKSYEBQDEAgANAAcJKSYEBQDEAgAAAA==.Bigpaladin:BAAALgADCgEJAQAAAA==.Bigrod:BAAALgAFFAMJBAABLgAFFAMJCQAGACAbAA==.',
Bl='Black:BAAALgAECgUJCQAAAA==.Blu:BAACLgAFFH8SAAIOAAMJEx4MHACyAAAOAAMJEx4MHACyAAAuAAQKfycAAg4ABgmHIvgpABQCAA4ABgmHIvgpABQCAAAA.',
Bo='Bombaclat:BAAALgADCgEJAQAAAA==.Boor:BAAALgAECgcJCAAAAA==.',
Br='Brilline:BAAALgAECgYJBwAAAA==.Brochese:BAAALgAECgYJCwABLgAECgkJLgADAEAgAA==.Broka:BAAALgAECgMJAwAAAA==.',
Bu='Bubblewrap:BAAALgAECgcJDwABLgAFFAcJGgAPANkSAA==.Bummergirl:BAAALgADCgMJAwAAAA==.Buwumkin:BAAALgAECgUJCwABLgAECggJDQAQAAAAAA==.',
['Bò']='Bònz:BAAALgADCgcJCwAAAA==.',
Ca='Cadaverous:BAACLgAFFH8JAAIGAAMJIBt8EQAIAQAGAAMJIBt8EQAIAQAuAAQKfxQAAwYACQnWGnQEAIQCAAYACQnWGnQEAIQCABEAAgnmCUNXAEAAAAAA.Canadianguy:BAAALgAECgIJAwABLgAECgkJDwAQAAAAAA==.',
Ch='Cheyeon:BAAALgAECgYJBgAAAA==.Chonk:BAAALgADCgkJCwAAAA==.Chunguskhan:BAACLgAFFH8FAAISAAMJfRKRIwDZAAASAAMJfRKRIwDZAAAuAAQKfxYAAhIACQlQGiANAIECABIACQlQGiANAIECAAAA.',
Ci='Cilocibin:BAAALgADCgUJBQAAAA==.',
Cl='Classcarry:BAAALgAECgEJAQABLgAFFAkJHQAFAMwdAA==.Claybigsby:BAACLgAFFH8YAAMCAAcJWhW+HgDfAAACAAUJmBq+HgDfAAABAAIJ4AqJIQBSAAAuAAQKfx4AAwEACQlPGxADAMoCAAEACAm5HRADAMoCAAIABwlwFq5xAHwBAAAA.Clif:BAACLgAFFH8MAAMIAAQJvw28FAC9AAATAAQJhAvZIgDlAAAIAAQJmgi8FAC9AAAuAAQKfxkAAwgACAmqHNwWAJYCAAgACAmqHNwWAJYCABMAAQl+HSBrAEsAAAAA.',
Co='Cosmiccosmo:BAAALgAECgQJCQAAAA==.',
Cr='Crippledlady:BAAALgAECggJDQAAAA==.Croi:BAAALgAECgIJAgAAAA==.',
Cu='Cucurbita:BAAALgADCgYJBgAAAA==.',
Cy='Cyndre:BAAALgADCgEJAQAAAA==.',
Da='Dareus:BAAALgADCgEJAQAAAA==.Dargon:BAABLgAECn8XAAMKAAgJ3yNnBgAZAwAKAAgJ3yNnBgAZAwAUAAYJ7hzSGwBSAQABLgAFFAUJCQAEANEYAA==.',
De='Deadlylady:BAAALgAECgUJBQAAAA==.Deadlyorc:BAAALgAECgIJAQAAAA==.Deaf:BAAALgAFFAEJAQABLgAFFAQJDAAPAGQlAA==.Delphine:BAAALgADCgYJBgAAAA==.Demonblade:BAAALgADCgEJAQAAAA==.Demonifrita:BAAALgADCgkJCQAAAA==.Demoniosushi:BAAALgAECgMJBwABLgAECgYJDgAQAAAAAA==.Demonmane:BAAALgADCgMJAwAAAA==.Derpy:BAABLgAECn8uAAMVAAgJmxEoJgCEAQAVAAgJmxEoJgCEAQAPAAgJ+wMrRADqAAAAAA==.',
Di='Dippindotz:BAAALgAECgEJAgABLgAFFAkJHQAFAMwdAA==.',
Dj='Djheals:BAAALgAECgQJCQAAAA==.',
Do='Doobiedruid:BAAALgAFFAIJAgAAAA==.Doobiemage:BAAALgAECgEJAgAAAA==.Dorenis:BAAALgAECgEJAgAAAA==.',
Dr='Drachese:BAAALgAECgYJBwABLgAECgkJLgADAEAgAA==.Droopox:BAABLgAECn8eAAIWAAkJBQlZLgD0AAAWAAkJBQlZLgD0AAAAAA==.Druchese:BAAALgAECggJDgABLgAECgkJLgADAEAgAA==.',
['Dö']='Döx:BAAALgAECgYJBgABLgAFFAcJFwALALIVAA==.',
Ea='Eagleeye:BAABLgAECn8lAAIEAAgJOhCUgwBoAQAEAAgJOhCUgwBoAQAAAA==.',
Em='Emsley:BAACLgAFFH8UAAIXAAQJmAt6LADjAAAXAAQJmAt6LADjAAAuAAQKf0gAAhcACQmkF4UjAMoBABcACQmkF4UjAMoBAAAA.',
Er='Erised:BAAALgAECgQJAwAAAA==.',
Ev='Ev:BAABLgAFFH8MAAIPAAQJZCWeAwC7AQAPAAQJZCWeAwC7AQAAAA==.',
Ex='Exo:BAACLgAFFH8XAAILAAcJshUCPAB8AQALAAcJshUCPAB8AQAuAAQKfx8AAgsACAkrIjYgAPMCAAsACAkrIjYgAPMCAAAA.',
Fe='Felrid:BAAALgAECgYJBgABLgAFFAUJCQAEANEYAA==.',
Fl='Floudruid:BAAALgADCgMJAwABLgABCgcJBwAQAAAAAA==.',
Fo='Focalors:BAAALgAFFAIJBAABLgAFFAcJLAAFADQeAA==.Foobear:BAACLgAFFH8aAAIWAAcJmxKOCwA7AQAWAAcJmxKOCwA7AQAuAAQKfywAAhYACQlyIL8FAKwCABYACQlyIL8FAKwCAAAA.Fozzy:BAABLgAECn8YAAIKAAgJpgenUQDoAAAKAAgJpgenUQDoAAAAAA==.Fozél:BAAALgAECgEJAQAAAA==.',
Fr='Franchescold:BAABLgAECn8gAAIFAAkJLxxcNwAhAgAFAAkJLxxcNwAhAgAAAA==.Franfran:BAABLgAECn8fAAILAAkJdA+YZwCtAQALAAkJdA+YZwCtAQAAAA==.Freasey:BAABLgAECn8fAAIEAAcJXg6WrgAhAQAEAAcJXg6WrgAhAQAAAA==.Frostbeard:BAAALgADCgQJBwAAAA==.',
Fu='Furiousfoo:BAABLgAECn8ZAAQYAAYJxBcWHABWAQAYAAYJuRcWHABWAQAIAAUJCRF0XADgAAATAAMJ5AmcLQCIAAABLgAFFAcJGgAWAJsSAA==.Furlock:BAABLgAECn8jAAMZAAgJuB8KAwCQAgAZAAgJuB8KAwCQAgACAAYJPRfRhwAqAQAAAA==.',
Ga='Gabriel:BAAALgAECgcJCAAAAA==.Galicia:BAAALgAECgYJBgAAAA==.Gantaris:BAABLgAECn8bAAIaAAcJlw3PBQATAQAaAAcJlw3PBQATAQAAAA==.Garbagevoker:BAAALgAFFAEJAQAAAA==.',
Ge='Gengiskaan:BAAALgAECgYJCgAAAA==.',
Gi='Gir:BAABLgAECn8TAAINAAgJbB0MGwDFAQANAAgJbB0MGwDFAQAAAA==.Gixian:BAAALgAECgYJEAAAAA==.',
Go='Gochese:BAABLgAECn8uAAMDAAkJQCDsAAB2AgADAAkJQCDsAAB2AgAEAAgJUxBKCQBWAQAAAA==.',
Gr='Gramid:BAACLgAFFH8JAAIEAAUJ0RhcRgAfAQAEAAUJ0RhcRgAfAQAuAAQKfxoAAgQACAlpJngeAI8CAAQACAlpJngeAI8CAAAA.Greenseer:BAABLgAECn8vAAICAAcJ0xeJTAC1AQACAAcJ0xeJTAC1AQAAAA==.Grognag:BAAALgAECgYJDgAAAA==.',
Gt='Gtoffmydh:BAAALgADCgIJAgAAAA==.',
Gw='Gwaralmighty:BAACLgAFFH8gAAIIAAUJdx+uBgBdAQAIAAUJdx+uBgBdAQAuAAQKfzYAAggACQlfIOcOAIUCAAgACQlfIOcOAIUCAAAA.',
Gy='Gypo:BAAALgAECgYJEAAAAA==.',
Ha='Haagen:BAAALgAECgUJEAAAAA==.Haagoon:BAAALgAECgcJCwAAAA==.Haagoonus:BAAALgAECgEJAQAAAA==.Halfwolf:BAAALgADCgQJBAAAAA==.Hatch:BAACLgAFFH8FAAIbAAMJwiFkCAD5AAAbAAMJwiFkCAD5AAAuAAQKfx0AAhsABwmCJR0BAPMCABsABwmCJR0BAPMCAAEuAAUUBAkMAA8AZCUA.',
Hh='Hholdem:BAAALgAECgQJBAABLgAECgkJKQAVADsPAA==.',
Hi='Hightones:BAACLgAFFH8SAAIHAAcJTwjnPQAvAQAHAAcJTwjnPQAvAQAuAAQKfyUAAgcACAk2IEoWANECAAcACAk2IEoWANECAAAA.Him:BAAALgAECgYJBgAAAA==.',
Ho='Holdêm:BAABLgAECn8pAAIVAAkJOw9FJACQAQAVAAkJOw9FJACQAQAAAA==.Holeytoast:BAAALgAECgQJBAABLgAFFAcJGgAXAOUcAA==.Hollee:BAABLgAECn8UAAIcAAcJPgiREQCpAAAcAAcJPgiREQCpAAABLgAFFAUJGwAOALIWAA==.Horsdoeuvres:BAAALgAECgkJEAAAAA==.',
Hu='Humberto:BAAALgAECgEJAQAAAA==.Hung:BAAALgAECgYJCwAAAA==.',
Ic='Icylady:BAAALgAECgYJEAAAAA==.',
If='Ifrita:BAACLgAFFH8JAAMLAAMJDgk2kQC1AAALAAMJEAY2kQC1AAAdAAEJ4QqMAwBFAAAuAAQKf1IABAsACQl0HdggAJsCAAsACQl0HdggAJsCAB0ABgkjE6oHAIYBAB4AAQm1CdUVACgAAAAA.Ifrite:BAABLgAECn8nAAMGAAkJNhTOCQDmAQAGAAkJyxLOCQDmAQAFAAgJeQ7FfgCGAQAAAA==.',
Ik='Ikur:BAABLgAECn8ZAAMJAAgJERFVFgBpAQAJAAcJkBFVFgBpAQAKAAcJ0AezUQDoAAABLgAFFAQJDwADAK8bAA==.',
Il='Ilovecandy:BAAALgAECgEJAQABLgAECgQJBwAQAAAAAA==.',
Im='Imbasoul:BAABLgAFFH8HAAICAAUJpQISHgDjAAACAAUJpQISHgDjAAAAAA==.Imyerchese:BAAALgAECgMJAwABLgAECgkJLgADAEAgAA==.',
It='Itita:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneill:BAACLgAFFH8NAAIEAAMJxAdwgQCzAAAEAAMJxAdwgQCzAAAuAAQKfyUAAgQACQnjECRvAJABAAQACQnjECRvAJABAAAA.',
Je='Jezlana:BAAALgAECgcJCwAAAA==.',
Ji='Jillidan:BAAALgAECgIJAwAAAA==.',
Jo='Johnnynapalm:BAAALgAECgIJBAABLgAECgQJBAAQAAAAAA==.Jonnycraig:BAAALgAECgEJAgAAAA==.Jormi:BAABLgAECn9EAAMTAAkJ1iOdAgAeAwATAAkJ1iOdAgAeAwAYAAMJlyGGJQAGAQAAAA==.',
Ka='Kabaayi:BAAALgADCgEJAQAAAA==.Kaihu:BAAALgAECgMJAwAAAA==.Kalthael:BAAALgADCgkJGAAAAA==.Kamilliara:BAAALgAECgEJAQAAAA==.Kasura:BAABLgAECn8sAAMfAAkJTRsVCwAMAgAfAAgJAx0VCwAMAgAaAAcJdA68gwDQAAAAAA==.Katakuri:BAAALgAECgEJAgAAAA==.',
Kh='Kharahealer:BAABLgAECn8UAAIgAAcJIhfRNABrAQAgAAcJIhfRNABrAQAAAA==.',
Kl='Kllausy:BAAALgAECgIJAwAAAA==.',
Ko='Kochese:BAAALgAECgEJAQABLgAECgkJLgADAEAgAA==.Kolto:BAAALgAECgEJAQABLgAECgEJAgAQAAAAAQ==.',
Kw='Kwrr:BAAALgADCgYJBgABLgAFFAkJMgACAGAlAA==.',
La='Lambo:BAABLgAECn8eAAIXAAgJDSDkEQBhAgAXAAgJDSDkEQBhAgAAAA==.',
Le='Leafhoof:BAAALgAECgEJAQAAAA==.Leonna:BAAALgAECgIJAgAAAA==.Lexidia:BAAALgADCgUJBQAAAA==.Leynnar:BAAALgAECgUJDwAAAA==.',
Li='Licha:BAAALgAECgcJBQAAAA==.Limedro:BAAALgADCgEJAQAAAA==.',
Lo='Lockme:BAABLgAFFH8KAAICAAQJshG8aQDxAAACAAQJshG8aQDxAAAAAA==.Lothiriel:BAAALgAECgcJDAAAAA==.Loveyuling:BAAALgAECgEJBAABLgAECgQJBwAQAAAAAA==.',
Lu='Lunk:BAAALgAECgEJAwAAAA==.',
Ly='Lynel:BAAALgAECgEJAgAAAA==.',
['Ló']='Lóvecandy:BAAALgAECgQJBwAAAA==.',
Ma='Mal:BAABLgAFFH8GAAIhAAUJPgtTBgB5AQAhAAUJPgtTBgB5AQABLgAFFAkJJwAhAL4XAA==.Maruzensky:BAACLgAFFH8zAAILAAkJwBhEEwBUAgALAAkJwBhEEwBUAgAuAAQKfyoAAwsACQleI6oPAEoDAAsACQleI6oPAEoDAB4ABAmtD6IHAP8AAAAA.Mary:BAACLgAFFH8hAAIiAAgJnyKzAAA+AgAiAAgJnyKzAAA+AgAuAAQKfxkAAiIACAnqH7MCAMECACIACAnqH7MCAMECAAAA.',
Me='Mechfury:BAAALgADCgEJAgAAAA==.Melitha:BAAALgADCggJCAABLgAECgkJRAATANYjAA==.Mero:BAACLgAFFH8TAAMHAAUJ/xa3TAAEAQAHAAQJ+hG3TAAEAQAjAAIJLCCNDwBXAAAuAAQKfyQAAyMACAl1HFsJANkBACMABwlaH1sJANkBAAcABwnYFfpmAG0BAAAA.Metal:BAABLgAECn8pAAIkAAgJAhq6EQBaAgAkAAgJAhq6EQBaAgAAAA==.Meyrey:BAAALgADCgYJCwAAAA==.',
Mi='Miorine:BAAALgAECgEJAQABLgAFFAcJLAAFADQeAA==.Mistbehavin:BAACLgAFFH8aAAIPAAcJ2RL/GQBUAQAPAAcJ2RL/GQBUAQAuAAQKfyUAAg8ACQlCGfgcABsCAA8ACQlCGfgcABsCAAAA.',
Mo='Mog:BAABLgAECn8iAAIDAAcJMyXtGgA9AgADAAcJMyXtGgA9AgAAAA==.Moochese:BAAALgAECgYJCgABLgAECgkJLgADAEAgAA==.Moostache:BAAALgAECgMJBAAAAA==.',
My='Mytz:BAAALgAECgcJEwAAAA==.',
['Má']='Mátthéw:BAAALgAECgEJAQAAAA==.',
Ne='Nemisai:BAAALgAECggJEQAAAA==.',
No='Nobody:BAAALgADCgcJBwAAAA==.',
Nu='Nuttinerbutt:BAABLgAFFH8GAAIEAAMJXAXeiQCeAAAEAAMJXAXeiQCeAAAAAA==.',
Oc='Ochra:BAAALgAECgEJAwAAAA==.',
Og='Ogparadox:BAABLgAECn8UAAILAAYJLxkXgAB3AQALAAYJLxkXgAB3AQAAAA==.',
Ok='Ok:BAABLgAECn8ZAAINAAgJ7ROpHwCfAQANAAgJ7ROpHwCfAQAAAA==.',
Op='Optimizer:BAAALgAECgYJBgAAAA==.',
Or='Orionbtch:BAABLgAECn8jAAIhAAgJEg35IACOAQAhAAgJEg35IACOAQAAAA==.',
Ov='Overheat:BAACLgAFFH8OAAILAAMJeBtrdgDvAAALAAMJeBtrdgDvAAAuAAQKfyAAAgsACQmdH4oZAMACAAsACQmdH4oZAMACAAAA.',
Po='Poppy:BAABLgAECn8eAAILAAgJhgdEowA2AQALAAgJhgdEowA2AQAAAA==.Portinglol:BAABLgAFFH8FAAIVAAQJ8hB0GwDwAAAVAAQJ8hB0GwDwAAABLgAFFAkJHQAFAMwdAA==.',
Ps='Psycilocibin:BAAALgADCgEJAQAAAA==.',
Qu='Qué:BAAALgAECgEJAwAAAA==.',
Qw='Qwiix:BAAALgADCgMJAwAAAA==.Qwixx:BAAALgADCgEJAQAAAA==.',
Ra='Rafikki:BAABLgAECn8VAAIWAAkJqBclEgDOAQAWAAkJqBclEgDOAQAAAA==.Ragerok:BAAALgAECgUJBQAAAA==.Ratidari:BAABLgAECn8+AAIHAAkJcBdUKgAgAgAHAAkJcBdUKgAgAgAAAA==.Ravenstorm:BAABLgAECn8kAAIlAAYJUhRIOQAuAQAlAAYJUhRIOQAuAQAAAA==.',
Re='Remmîngton:BAABLgAECn9CAAMDAAkJ6R5kDQC8AgADAAkJ6R5kDQC8AgAEAAMJ1wwaSQFkAAAAAA==.Retbulls:BAABLgAECn8XAAIEAAkJZiAGDwDuAgAEAAkJZiAGDwDuAgAAAA==.Reverie:BAAALgADCgMJAwAAAA==.',
Rh='Rhynehardt:BAAALgAECgQJBAAAAA==.',
Ri='Rip:BAABLgAFFH8GAAINAAIJCxlfKACUAAANAAIJCxlfKACUAAABLgAFFAMJEgAOABMeAA==.Riptidedro:BAACLgAFFH8cAAMOAAUJKR8qBwCVAQAOAAUJKR8qBwCVAQAXAAEJ9QD3YQApAAAuAAQKfyoAAg4ACQlgHZ0TAHgCAA4ACQlgHZ0TAHgCAAAA.',
Ru='Rukaz:BAAALgADCgYJBgAAAA==.Runslikedeer:BAABLgAECn8iAAIaAAkJSxoFHQBeAgAaAAkJSxoFHQBeAgAAAA==.Runé:BAAALgAECgcJCAABLgAECgkJEQAQAAAAAA==.Rustyarrow:BAAALgAECgEJAQAAAA==.',
Ry='Ryan:BAAALgAFFAEJAQAAAA==.Ryukk:BAABLgAECn8uAAIFAAkJdxYKUADTAQAFAAkJdxYKUADTAQAAAA==.',
Sa='Sanoth:BAAALgAECgEJAQAAAA==.Sarana:BAAALgADCgMJAwAAAA==.Sarkhael:BAAALgAECgUJCAAAAA==.',
Se='Sean:BAACLgAFFH8aAAILAAcJ1BaqGQA/AQALAAcJ1BaqGQA/AQAuAAQKfyUAAgsACQlwIUkXAB4DAAsACQlwIUkXAB4DAAAA.Secksecute:BAAALgAECgIJBQAAAA==.Seinsleer:BAAALgAECgQJBAABLgAFFAEJAQAQAAAAAA==.Sen:BAAALgAFFAEJAQABLgAFFAMJEgAOABMeAA==.Serah:BAAALgAFFAQJBAAAAA==.Seris:BAAALgAECgYJBgABLgAFFAUJCQAEANEYAA==.',
Sh='Shel:BAABLgAECn8oAAIHAAkJHwsDZQBdAQAHAAkJHwsDZQBdAQAAAA==.Sheppy:BAABLgAFFH8JAAIEAAYJsgopFAAUAQAEAAYJsgopFAAUAQAAAA==.Shimakaze:BAACLgAFFH8sAAMFAAcJNB4CCwDiAQAFAAUJoCACCwDiAQARAAIJGhIWOwBKAAAuAAQKfyIAAgUABwljJNcrAIkCAAUABwljJNcrAIkCAAAA.Shizaam:BAACLgAFFH8aAAMXAAcJ5RxyBwByAQAXAAYJAB5yBwByAQAOAAEJ4iAxbgBhAAAuAAQKfyQAAxcACQlMI4gFAD4DABcACQlMI4gFAD4DAA4AAQkrCXSdADQAAAAA.Shlommy:BAABLgAECn8aAAICAAgJgBRFUACqAQACAAgJgBRFUACqAQAAAA==.',
Si='Siinns:BAACLgAFFH8QAAIVAAQJ7h2UDABeAQAVAAQJ7h2UDABeAQAuAAQKfyoABBUACQnPHbIPAE8CABUACQnPHbIPAE8CABwABQlaEMhdAP8AAA8AAgnOE0J6AFsAAAAA.Simp:BAAALgAECgIJAgAAAA==.Sinfxl:BAAALgAECgkJEQAAAA==.Sippinsizurp:BAAALgAECggJDwAAAA==.',
Sk='Skadooget:BAAALgADCgYJBgAAAA==.Skullkíng:BAAALgADCgEJAQAAAA==.Skullmages:BAACLgAFFH8QAAIEAAQJABgACQBnAQAEAAQJABgACQBnAQAuAAQKfxkAAgQABwk3I6QgAKkCAAQABwk3I6QgAKkCAAAA.',
Sl='Slayur:BAABLgAECn8gAAIIAAkJwQ3SKwClAQAIAAkJwQ3SKwClAQAAAA==.Slinkeril:BAABLgAECn8hAAIiAAgJhBTFCgCIAQAiAAgJhBTFCgCIAQAAAA==.Sloppydro:BAAALgAFFAMJAgAAAA==.',
Sm='Smackthat:BAAALgAECgQJBgABLgAECgYJDgAQAAAAAA==.Smokey:BAAALgAECgUJCQABLgAECgYJDgAQAAAAAA==.Smokinpurrp:BAAALgAECgQJBAAAAA==.Smoky:BAAALgAECgYJDgAAAA==.',
So='Soju:BAAALgAECgEJBgAAAA==.Sotari:BAAALgADCggJCQAAAA==.',
Sp='Spintowin:BAAALgAECgkJCAAAAA==.Sploosh:BAAALgAECgYJCgAAAA==.',
St='Stabberz:BAACLgAFFH8VAAIiAAQJQBoXBABNAQAiAAQJQBoXBABNAQAuAAQKf0kAAyIACQmfIX4DAHoCACIACQmfIX4DAHoCACEABAk8EqhLAM0AAAAA.Sticks:BAAALgAECgUJCAAAAA==.Stõrmy:BAAALgAECgIJAgAAAA==.',
Su='Sushiroll:BAAALgAFFAEJAQABLgAFFAkJHQAFAMwdAA==.',
Sw='Sweetsourrex:BAABLgAFFH8GAAIHAAUJQBWkPwApAQAHAAUJQBWkPwApAQAAAA==.',
Sy='Synkro:BAAALgAECgYJCwABLgAECgkJEQAQAAAAAA==.',
Ta='Tatisjr:BAAALgAECgYJCgAAAA==.',
Te='Temoin:BAAALgAECgEJBAAAAA==.Tempprance:BAAALgAECgQJBAAAAA==.',
Th='Thelasthope:BAAALgAECgQJBAAAAA==.Thewordalive:BAAALgADCgIJAgAAAA==.Tholdraz:BAAALgAECgEJAQAAAA==.Thooran:BAAALgAECgIJBwAAAA==.Thrass:BAABLgAECn8gAAILAAkJ+hH2VQDbAQALAAkJ+hH2VQDbAQAAAA==.Throngler:BAAALgAECgYJEQABLgAFFAUJFAACAIkLAA==.',
To='Tohru:BAAALgAECgIJAgABLgAFFAcJLAAFADQeAA==.Toobrunner:BAACLgAFFH8qAAIHAAgJgCIfBgCxAgAHAAgJgCIfBgCxAgAuAAQKfx4AAgcACAlSImUbAK4CAAcACAlSImUbAK4CAAAA.Tool:BAACLgAFFH8vAAIHAAkJESXFAABZAwAHAAkJESXFAABZAwAuAAQKfyUAAgcACQmbJXoCAGADAAcACQmbJXoCAGADAAAA.',
Tr='Trollz:BAABLgAECn8bAAIZAAgJqRHGCQDGAQAZAAgJqRHGCQDGAQAAAA==.',
Up='Upside:BAAALgAECgIJAwAAAA==.',
Va='Vampress:BAAALgAECgQJBQAAAA==.Varvera:BAAALgADCgMJAwAAAA==.',
Ve='Velannis:BAACLgAFFH8FAAMiAAMJ3h5dCQCxAAAiAAIJURxdCQCxAAAbAAEJ9yOPDwBmAAAuAAQKfzIAAxsACQl6IycBAPsCABsACQk5IycBAPsCACIABwm9INAHANcBAAAA.',
Vi='Virikas:BAABLgAECn8kAAMOAAgJABxqIQBHAgAOAAgJABxqIQBHAgAXAAQJKAw1eQCCAAAAAA==.',
Vo='Voidhunter:BAABLgAECn8TAAIHAAgJUxXCWwCOAQAHAAgJUxXCWwCOAQAAAA==.Voodooki:BAABLgAECn9DAAIlAAkJvxh8EwA5AgAlAAkJvxh8EwA5AgAAAA==.',
Vu='Vuo:BAABLgAECn9BAAImAAkJKhepOwDxAQAmAAkJKhepOwDxAQAAAA==.',
Wa='Wayside:BAAALgAECgkJCAAAAA==.',
We='Weedonice:BAAALgAECgcJBQAAAA==.',
Wh='Wheelytank:BAABLgAFFH8VAAIEAAUJjhdwQAAqAQAEAAUJjhdwQAAqAQAAAA==.White:BAAALgAECgQJBwABLgABCgIJAgAQAAAAAA==.',
Wi='Wickedshaman:BAAALgADCgkJCQABLgAECgkJQQAmACoXAA==.Wilburoni:BAAALgADCgIJAgAAAA==.Wiping:BAAALgAECgIJAQABLgAECgcJIgADADMlAA==.',
Xf='Xfreshh:BAAALgAECgYJDQAAAA==.',
Xn='Xnomorp:BAAALgAECgQJBAAAAA==.',
Ya='Yamalock:BAABLgAFFH8TAAMCAAUJJxnqRgA6AQACAAUJJxnqRgA6AQAZAAEJ8QGKLgAzAAAAAA==.Yamamist:BAAALgAECgYJCgABLgAFFAMJBgALAK4WAA==.Yamå:BAACLgAFFH8GAAILAAMJrhYTgwDRAAALAAMJrhYTgwDRAAAuAAQKfxoAAgsABglrIktfAB0CAAsABglrIktfAB0CAAAA.',
Ye='Yeaffa:BAAALgADCgYJBgAAAA==.',
Yi='Yingzhi:BAAALgAECgkJEAAAAA==.',
Za='Zavalu:BAABLgAECn84AAIOAAgJIiFWEwCxAgAOAAgJIiFWEwCxAgAAAA==.',
Ze='Zerosh:BAABLgAECn8xAAIiAAkJJRMnBgAKAgAiAAkJJRMnBgAKAgAAAA==.',
Zi='Zinaida:BAAALgADCggJCAAAAA==.',
Zo='Zortok:BAABLgAECn8hAAIXAAkJcxPqKACoAQAXAAkJcxPqKACoAQAAAA==.',
Zu='Zugszy:BAAALgAECgYJEAAAAA==.',
Zv='Zvlana:BAAALgAECgkJCQAAAA==.',
['Âc']='Âce:BAAALgAECgEJAwAAAA==.',
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
