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

local lookup = {'Warlock-Destruction','Warlock-Demonology','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','Unknown-Unknown','Warrior-Fury','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','Paladin-Protection','Hunter-Survival','Monk-Brewmaster','DeathKnight-Blood','Priest-Shadow','Warrior-Arms','Evoker-Devastation','Rogue-Outlaw','Monk-Windwalker','Druid-Guardian','Shaman-Elemental','Shaman-Restoration','Warrior-Protection','Warlock-Affliction','DemonHunter-Devourer','Mage-Arcane','Mage-Fire','Druid-Feral','Druid-Restoration','Priest-Holy','Rogue-Assassination','DemonHunter-Vengeance','Priest-Discipline','Rogue-Subtlety','Druid-Balance','Monk-Mistweaver','Hunter-BeastMastery',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abeblinkin:BAAALgAECgcJCwAAAA==.Aborlight:BAAALgAECgUJDwAAAA==.',
Ad='Adit:BAABLgAECn8UAAMBAAgJyxDsDQBZAQABAAgJyxDsDQBZAQACAAYJCAqwtADcAAAAAA==.Adug:BAAALgADCgMJAwAAAA==.',
Ae='Aedrius:BAABLgAECn8ZAAMDAAcJLhjINQClAQADAAYJrRnINQClAQAEAAQJlxECwQAFAQAAAA==.',
Ag='Agnekie:BAABLgAECn8XAAIEAAcJqRd0ZACkAQAEAAcJqRd0ZACkAQAAAA==.',
Ai='Aiwass:BAABLgAECn9SAAIBAAkJJBS7BgDvAQABAAkJJBS7BgDvAQAAAA==.Aiyo:BAABLgAFFH8GAAMFAAIJxAr04wCCAAAFAAIJxAr04wCCAAAGAAEJagsbJgBGAAABLgAFFAQJBAAHAAAAAA==.',
Al='Alexander:BAAALgAECgMJAwAAAA==.Alpharius:BAAALgAECgUJCAAAAA==.',
Am='Amathricus:BAABLgAECn8zAAIEAAkJkg6FXwCvAQAEAAkJkg6FXwCvAQAAAA==.Amerika:BAAALgADCgIJAgAAAA==.',
Ar='Arawak:BAAALgADCgEJAQAAAA==.',
As='Ashuk:BAABLgAECn8cAAIIAAYJsAjrWQDnAAAIAAYJsAjrWQDnAAAAAA==.',
At='Athena:BAAALgAECgMJAwAAAA==.',
Au='Augtism:BAECLgAFFH8IAAMJAAUJgA8DGQD9AAAJAAQJ1Q8DGQD9AAAKAAQJdAp+OQDeAAAuAAQKfx0AAwoABwmfHmYgANQBAAoABwmfHmYgANQBAAkAAgm2EV0tAHoAAAEuAAUUBQkIAAkAgA8A.Auitou:BAAALgAECggJCQAAAA==.Auralei:BAABLgAECn8fAAILAAgJXwjIlwBGAQALAAgJXwjIlwBGAQAAAA==.',
Az='Azelia:BAAALgAECggJEwABLgAECgkJKgADADoVAA==.Azzy:BAABLgAECn8qAAQDAAkJOhUdJQDbAQADAAgJpRcdJQDbAQAMAAMJLgKSSQBAAAAEAAIJ9gHfqAEpAAAAAA==.',
Ba='Bacta:BAAALgADCgUJBQAAAA==.',
Be='Beasti:BAAALgAECgIJAgAAAA==.Beelzebul:BAAALgAFFAQJBAABLgAFFAYJJgAFADsiAA==.',
Bi='Bigb:BAABLgAECn8mAAINAAcJKSYEBQDEAgANAAcJKSYEBQDEAgAAAA==.Bigpaladin:BAAALgADCgEJAQAAAA==.',
Bl='Black:BAAALgAECgUJCQAAAA==.',
Bo='Bombaclat:BAAALgADCgEJAQAAAA==.Boor:BAAALgAECgcJCAAAAA==.',
Br='Brilline:BAAALgAECgYJBwAAAA==.Brochese:BAAALgAECgUJBgABLgAECgkJHgADAD8dAA==.Broka:BAAALgAECgMJAwAAAA==.',
Bu='Bubblewrap:BAAALgAECgcJDwABLgAFFAYJFgAOAE4TAA==.Buwumkin:BAAALgAECgUJCwABLgAECgcJBwAHAAAAAA==.',
['Bò']='Bònz:BAAALgADCgQJBAAAAA==.',
Ca='Cadaverous:BAACLgAFFH8IAAIGAAMJMxuBEAAJAQAGAAMJMxuBEAAJAQAuAAQKfxQAAwYACQnWGlwEAIYCAAYACQnWGlwEAIYCAA8AAgnmCftVAEAAAAAA.Canadianguy:BAAALgADCgIJAgABLgAECgcJCwAHAAAAAA==.',
Ch='Cheyeon:BAAALgAECgYJBgAAAA==.Chonk:BAAALgADCgkJCwAAAA==.Chunguskhan:BAABLgAFFH8FAAIQAAMJfRJoIgDaAAAQAAMJfRJoIgDaAAAAAA==.',
Cl='Classcarry:BAAALgADCgYJBgABLgAFFAgJHAAFAGggAA==.Claybigsby:BAACLgAFFH8UAAMCAAYJQBcRTgAmAQACAAUJIhkRTgAmAQABAAEJtQ/ZIABSAAAuAAQKfx4AAwEACQlPGxADAMoCAAEACAm5HRADAMoCAAIABwlwFq5xAHwBAAAA.Clif:BAACLgAFFH8JAAMRAAQJhAtpIQDnAAARAAQJhAtpIQDnAAAIAAIJxAdjRwB+AAAuAAQKfxkAAwgACAmqHNwWAJYCAAgACAmqHNwWAJYCABEAAQl+HYhoAEsAAAAA.',
Co='Cosmiccosmo:BAAALgAECgQJCQAAAA==.',
Cr='Crippledlady:BAAALgAECgcJBwAAAA==.',
Cu='Cucurbita:BAAALgADCgYJBgAAAA==.',
Cy='Cyndre:BAAALgADCgEJAQAAAA==.',
Da='Dargon:BAABLgAECn8XAAMKAAgJ3yNnBgAZAwAKAAgJ3yNnBgAZAwASAAYJ7hzSGwBSAQABLgAFFAUJCQAEANEYAA==.',
De='Deadlylady:BAAALgAECgUJBQAAAA==.Deadlyorc:BAAALgAECgIJAQAAAA==.Deaf:BAAALgAFFAEJAQABLgAFFAMJBQATAMIhAA==.Delphine:BAAALgADCgYJBgAAAA==.Demonblade:BAAALgADCgEJAQAAAA==.Demonifrita:BAAALgADCgkJCQAAAA==.Demoniosushi:BAAALgAECgMJBwABLgAECgYJDgAHAAAAAA==.Demonmane:BAAALgADCgMJAwAAAA==.Derpy:BAABLgAECn8sAAMUAAgJbhGPJQCEAQAUAAgJbhGPJQCEAQAOAAgJ+wN7QwDqAAAAAA==.',
Di='Dippindotz:BAAALgAECgEJAgABLgAFFAgJHAAFAGggAA==.',
Dj='Djheals:BAAALgAECgQJBQAAAA==.',
Do='Doobiedruid:BAAALgAFFAIJAgAAAA==.Doobiemage:BAAALgAECgEJAgAAAA==.Dorenis:BAAALgAECgEJAgAAAA==.',
Dr='Drachese:BAAALgAECgEJAQABLgAECgkJHgADAD8dAA==.Droopox:BAABLgAECn8eAAIVAAkJBQknLQD0AAAVAAkJBQknLQD0AAAAAA==.Druchese:BAAALgAECgYJCwABLgAECgkJHgADAD8dAA==.',
['Dö']='Döx:BAAALgAECgYJBgABLgAFFAYJFgALADMXAA==.',
Ea='Eagleeye:BAABLgAECn8kAAIEAAcJdRGHlwBCAQAEAAcJdRGHlwBCAQAAAA==.',
Em='Emsley:BAACLgAFFH8TAAIWAAQJmAvaKgDkAAAWAAQJmAvaKgDkAAAuAAQKf0gAAhYACQmkF84iAMsBABYACQmkF84iAMsBAAAA.',
Er='Eri:BAACLgAFFH8QAAIXAAMJEx52OQD1AAAXAAMJEx52OQD1AAAuAAQKfycAAhcABgmHIiQpABQCABcABgmHIiQpABQCAAAA.Erised:BAAALgADCgkJDwAAAA==.',
Ev='Ev:BAAALgAFFAIJAwABLgAFFAMJBQATAMIhAA==.',
Ex='Exo:BAACLgAFFH8WAAILAAYJMxeVNwCOAQALAAYJMxeVNwCOAQAuAAQKfx8AAgsACAkrIjYgAPMCAAsACAkrIjYgAPMCAAAA.',
Fe='Felrid:BAAALgAECgYJBgABLgAFFAUJCQAEANEYAA==.',
Fl='Floudruid:BAAALgADCgMJAwABLgABCgcJBwAHAAAAAA==.',
Fo='Focalors:BAAALgAFFAIJBAABLgAFFAYJJgAFADsiAA==.Foobear:BAACLgAFFH8WAAIVAAYJ+xLUCgA+AQAVAAYJ+xLUCgA+AQAuAAQKfysAAhUACQklIOEFAKMCABUACQklIOEFAKMCAAAA.Fozzy:BAABLgAECn8YAAIKAAgJpgdLUADpAAAKAAgJpgdLUADpAAAAAA==.Fozél:BAAALgAECgEJAQAAAA==.',
Fr='Franchescold:BAABLgAECn8gAAIFAAkJLxwlNgAjAgAFAAkJLxwlNgAjAgAAAA==.Franfran:BAABLgAECn8fAAILAAkJdA/7ZQCuAQALAAkJdA/7ZQCuAQAAAA==.Freasey:BAABLgAECn8eAAIEAAYJkQ8nxwD8AAAEAAYJkQ8nxwD8AAAAAA==.Frostbeard:BAAALgADCgQJBwAAAA==.',
Fu='Furiousfoo:BAABLgAECn8ZAAQYAAYJxBeTGwBXAQAYAAYJuReTGwBXAQAIAAUJCREfWgDmAAARAAMJ5AmcLQCIAAABLgAFFAYJFgAVAPsSAA==.Furlock:BAABLgAECn8iAAMZAAcJrSDgBABDAgAZAAcJrSDgBABDAgACAAYJPRe8hQAtAQAAAA==.',
Ga='Gabriel:BAAALgAECgcJCAAAAA==.Galicia:BAAALgAECgYJBgAAAA==.Gantaris:BAAALgAECgcJEQAAAA==.',
Ge='Gengiskaan:BAAALgAECgYJCgAAAA==.',
Gi='Gir:BAAALgAECgcJEAAAAA==.Gixian:BAAALgAECgYJEAAAAA==.',
Go='Gochese:BAABLgAECn8eAAMDAAkJPx1xCgDjAgADAAkJPx1xCgDjAgAEAAYJcQuz0ADvAAAAAA==.',
Gr='Gramid:BAACLgAFFH8JAAIEAAUJ0RgnQwAgAQAEAAUJ0RgnQwAgAQAuAAQKfxoAAgQACAlpJsodAJECAAQACAlpJsodAJECAAAA.Greenseer:BAABLgAECn8uAAICAAYJPBo6XACJAQACAAYJPBo6XACJAQAAAA==.Grognag:BAAALgAECgYJDgAAAA==.',
Gt='Gtoffmydh:BAAALgADCgIJAgAAAA==.',
Gw='Gwaralmighty:BAACLgAFFH8TAAIIAAUJcR+LEgBuAQAIAAUJcR+LEgBuAQAuAAQKfzIAAggACQlfIH8OAIgCAAgACQlfIH8OAIgCAAAA.',
Gy='Gypo:BAAALgAECgYJBwAAAA==.',
Ha='Haagen:BAAALgAECgUJDgAAAA==.Haagoon:BAAALgAECgMJBAAAAA==.Haagoonus:BAAALgAECgEJAQAAAA==.Halfwolf:BAAALgADCgQJBAAAAA==.Hatch:BAACLgAFFH8FAAITAAMJwiErCAD5AAATAAMJwiErCAD5AAAuAAQKfx0AAhMABwmCJR0BAPMCABMABwmCJR0BAPMCAAAA.',
Hh='Hholdem:BAAALgADCgcJBwABLgAECgkJJgAUAMkOAA==.',
Hi='Hightones:BAACLgAFFH8OAAIaAAYJCgjEOwAvAQAaAAYJCgjEOwAvAQAuAAQKfyUAAhoACAk2IEoWANECABoACAk2IEoWANECAAAA.Him:BAAALgAECgYJBgAAAA==.',
Ho='Holdêm:BAABLgAECn8mAAIUAAkJyQ6eIwCRAQAUAAkJyQ6eIwCRAQAAAA==.Holeytoast:BAAALgAECgQJBAABLgAFFAYJFgAWADkdAA==.Hollee:BAAALgAECgYJCwABLgAFFAUJGwAXALIWAA==.Horsdoeuvres:BAAALgAECgkJEAAAAA==.',
Hu='Humberto:BAAALgAECgEJAQAAAA==.Hung:BAAALgAECgYJCwAAAA==.',
Ic='Icylady:BAAALgAECgYJCgAAAA==.',
If='Ifrita:BAACLgAFFH8HAAMLAAMJDgnXjQC/AAALAAMJEAbXjQC/AAAbAAEJ4QqNBgBCAAAuAAQKf00ABAsACQnoGiUgAJsCAAsACQnoGiUgAJsCABsABgkjE6oHAIYBABwAAQm1CSEVACgAAAAA.Ifrite:BAABLgAECn8lAAMGAAkJsxKHCQDqAQAGAAkJSBGHCQDqAQAFAAgJeQ7FfgCGAQAAAA==.',
Ik='Ikur:BAABLgAECn8ZAAMJAAgJEREZFgBoAQAJAAcJkBEZFgBoAQAKAAcJ0Ad3UADoAAABLgAFFAQJDwADAK8bAA==.',
Im='Imbasoul:BAAALgAFFAIJAgAAAA==.Imyerchese:BAAALgADCgYJBgABLgAECgkJHgADAD8dAA==.',
It='Itita:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneill:BAACLgAFFH8NAAIEAAMJxAdOfQCzAAAEAAMJxAdOfQCzAAAuAAQKfyUAAgQACQnjEKttAJABAAQACQnjEKttAJABAAAA.',
Je='Jezlana:BAAALgAECgcJCwAAAA==.',
Ji='Jillidan:BAAALgAECgIJAwAAAA==.',
Jo='Johnnynapalm:BAAALgAECgIJBAABLgAECgQJBAAHAAAAAA==.Jonnycraig:BAAALgAECgEJAgAAAA==.Jormi:BAABLgAECn9CAAMRAAkJ1iN+AgAfAwARAAkJ1iN+AgAfAwAYAAMJlyHlJAAGAQAAAA==.',
Ka='Kabaayi:BAAALgADCgEJAQAAAA==.Kaihu:BAAALgAECgMJAwAAAA==.Kalthael:BAAALgADCgkJGAAAAA==.Kasura:BAABLgAECn8sAAMdAAkJTRvbCgALAgAdAAgJAx3bCgALAgAeAAcJdA68gwDQAAAAAA==.Katakuri:BAAALgAECgEJAgAAAA==.',
Kh='Kharahealer:BAABLgAECn8UAAIfAAcJIhfRNABrAQAfAAcJIhfRNABrAQAAAA==.',
Kl='Kllausy:BAAALgAECgIJAwAAAA==.',
Ko='Kochese:BAAALgAECgEJAQABLgAECgkJHgADAD8dAA==.',
Kr='Krayt:BAAALgAECgEJBgAAAA==.',
Kw='Kwrr:BAAALgADCgYJBgABLgAFFAgJJgACAEslAA==.',
La='Lambo:BAABLgAECn8eAAIWAAgJDSCBEQBiAgAWAAgJDSCBEQBiAgAAAA==.',
Le='Leafhoof:BAAALgAECgEJAQAAAA==.Lenona:BAAALgAECgIJAgAAAA==.Lexidia:BAAALgADCgUJBQAAAA==.Leynnar:BAAALgAECgUJDwAAAA==.',
Li='Licha:BAAALgAECgcJBQAAAA==.',
Lo='Lockme:BAABLgAFFH8KAAICAAQJshERZwDyAAACAAQJshERZwDyAAAAAA==.Lothiriel:BAAALgAECgcJDAAAAA==.Loveyuling:BAAALgAECgEJBAABLgAECgQJBwAHAAAAAA==.',
Lu='Lunk:BAAALgAECgEJAwAAAA==.',
Ly='Lynel:BAAALgAECgEJAgAAAA==.',
['Ló']='Lóvecandy:BAAALgAECgQJBwAAAA==.',
Ma='Maruzensky:BAACLgAFFH8yAAILAAgJUhtrEQBeAgALAAgJUhtrEQBeAgAuAAQKfyoAAwsACQleI6oPAEoDAAsACQleI6oPAEoDABwABAmtD6IHAP8AAAAA.Mary:BAACLgAFFH8XAAIgAAcJFCKfAABBAgAgAAcJFCKfAABBAgAuAAQKfxkAAiAACAnqH7MCAMECACAACAnqH7MCAMECAAAA.',
Me='Mechfury:BAAALgADCgEJAgAAAA==.Melitha:BAAALgADCggJCAABLgAECgkJQgARANYjAA==.Mero:BAACLgAFFH8TAAMaAAUJ/xZrSgAEAQAaAAQJ+hFrSgAEAQAhAAIJLCD9DgBXAAAuAAQKfyQAAyEACAl1HFsJANkBACEABwlaH1sJANkBABoABwnYFfpmAG0BAAAA.Metal:BAABLgAECn8oAAIiAAgJ5hlREQBcAgAiAAgJ5hlREQBcAgAAAA==.Meyrey:BAAALgADCgYJCwAAAA==.',
Mi='Miorine:BAAALgAECgEJAQABLgAFFAYJJgAFADsiAA==.Mistbehavin:BAACLgAFFH8WAAIOAAYJThMIGQBVAQAOAAYJThMIGQBVAQAuAAQKfyQAAg4ACQlCGfgcABsCAA4ACQlCGfgcABsCAAAA.',
Mo='Mog:BAABLgAECn8iAAIDAAcJMyXtGgA9AgADAAcJMyXtGgA9AgAAAA==.Moochese:BAAALgAECgEJAQABLgAECgkJHgADAD8dAA==.Moostache:BAAALgAECgMJBAAAAA==.',
My='Mytz:BAAALgAECgYJBwAAAA==.',
['Má']='Mátthéw:BAAALgADCgcJCQAAAA==.',
Ne='Nemisai:BAAALgAECggJEAAAAA==.',
No='Nobody:BAAALgADCgcJBwAAAA==.',
Nu='Nuttinerbutt:BAABLgAFFH8GAAIEAAMJXAV3hQCeAAAEAAMJXAV3hQCeAAAAAA==.',
Oc='Ochra:BAAALgAECgEJAwAAAA==.',
Og='Ogparadox:BAABLgAECn8UAAILAAYJLxmHfgB3AQALAAYJLxmHfgB3AQAAAA==.',
Ok='Ok:BAABLgAECn8ZAAINAAgJ7RMOHwCjAQANAAgJ7RMOHwCjAQAAAA==.',
Or='Orionbtch:BAABLgAECn8iAAIjAAgJEg10IACOAQAjAAgJEg10IACOAQAAAA==.',
Ov='Overheat:BAACLgAFFH8LAAILAAMJcRj4dwDvAAALAAMJcRj4dwDvAAAuAAQKfyAAAgsACQmdH/sYAMECAAsACQmdH/sYAMECAAAA.',
Po='Poppy:BAABLgAECn8eAAILAAgJhgf9oAA2AQALAAgJhgf9oAA2AQAAAA==.Portinglol:BAABLgAFFH8FAAIUAAQJ8hCCGgDxAAAUAAQJ8hCCGgDxAAABLgAFFAgJHAAFAGggAA==.',
Ps='Psycilocibin:BAAALgADCgEJAQAAAA==.',
Qu='Qué:BAAALgAECgEJAgAAAA==.',
Qw='Qwiix:BAAALgADCgMJAwAAAA==.Qwixx:BAAALgADCgEJAQAAAA==.',
Ra='Rafikki:BAABLgAECn8UAAIVAAgJ4RezEQDOAQAVAAgJ4RezEQDOAQAAAA==.Ragerok:BAAALgAECgUJBQAAAA==.Ratidari:BAABLgAECn86AAIaAAkJhxbxKwAVAgAaAAkJhxbxKwAVAgAAAA==.Ravenstorm:BAABLgAECn8gAAIkAAYJIRSYOAAtAQAkAAYJIRSYOAAtAQAAAA==.',
Re='Remmîngton:BAABLgAECn8/AAMDAAkJwB4lDQC9AgADAAkJwB4lDQC9AgAEAAMJ1wwDRAFkAAAAAA==.Retbulls:BAAALgAECgkJEgAAAA==.Reverie:BAAALgADCgMJAwAAAA==.',
Rh='Rhynehardt:BAAALgAECgQJBAAAAA==.',
Ri='Rip:BAAALgAFFAIJAwABLgAFFAMJEAAXABMeAA==.Riptidedro:BAACLgAFFH8UAAMXAAUJpR1TFgCnAQAXAAUJpR1TFgCnAQAWAAEJ9QBjXgApAAAuAAQKfyoAAhcACQlgHZ0TAHgCABcACQlgHZ0TAHgCAAAA.',
Ru='Rukaz:BAAALgADCgYJBgAAAA==.Runslikedeer:BAABLgAECn8eAAIeAAgJChqtHABdAgAeAAgJChqtHABdAgAAAA==.Runé:BAAALgAECgcJBwAAAA==.Rustyarrow:BAAALgAECgEJAQAAAA==.',
Ry='Ryan:BAAALgAECgQJBwAAAA==.Ryukk:BAABLgAECn8uAAIFAAkJdxYpTgDWAQAFAAkJdxYpTgDWAQAAAA==.',
Sa='Sanoth:BAAALgADCgEJAgAAAA==.Sarana:BAAALgADCgMJAwAAAA==.Sarkhael:BAAALgAECgUJCAAAAA==.',
Se='Sean:BAACLgAFFH8WAAILAAYJ1RhnNwCPAQALAAYJ1RhnNwCPAQAuAAQKfyQAAgsACQlwIUkXAB4DAAsACQlwIUkXAB4DAAAA.Secksecute:BAAALgAECgIJBQAAAA==.Seinsleer:BAAALgAECgQJBAABLgAECgQJBwAHAAAAAA==.Serah:BAAALgAFFAQJBAAAAA==.Seris:BAAALgAECgYJBgABLgAFFAUJCQAEANEYAA==.',
Sh='Shel:BAABLgAECn8oAAIaAAkJHwtmYwBdAQAaAAkJHwtmYwBdAQAAAA==.Sheppy:BAABLgAFFH8FAAIEAAUJ2wQNPwAnAQAEAAUJ2wQNPwAnAQAAAA==.Shimakaze:BAACLgAFFH8mAAMFAAYJOyKTKAC7AQAFAAQJQyaTKAC7AQAPAAIJGhJyOQBLAAAuAAQKfyIAAgUABwljJNcrAIkCAAUABwljJNcrAIkCAAAA.Shizaam:BAACLgAFFH8WAAMWAAYJOR2FHAAwAQAWAAUJsB6FHAAwAQAXAAEJ4iDCagBhAAAuAAQKfyQAAxYACQlMI4gFAD4DABYACQlMI4gFAD4DABcAAQkrCXSdADQAAAAA.Shlommy:BAABLgAECn8YAAICAAgJ5xNiTgCvAQACAAgJ5xNiTgCvAQAAAA==.',
Si='Siinns:BAACLgAFFH8QAAIUAAQJ7h3sCwBgAQAUAAQJ7h3sCwBgAQAuAAQKfyoABBQACQnPHXEPAFACABQACQnPHXEPAFACACUABQlaEEZbAP4AAA4AAgnOE0J6AFsAAAAA.Simp:BAAALgAECgIJAgAAAA==.Sinfxl:BAAALgAECgYJCwABLgAECgcJBwAHAAAAAA==.Sippinsizurp:BAAALgAECggJDwAAAA==.',
Sk='Skadooget:BAAALgADCgYJBgAAAA==.Skullkíng:BAAALgADCgEJAQAAAA==.Skullmages:BAACLgAFFH8QAAIEAAQJABgACQBnAQAEAAQJABgACQBnAQAuAAQKfxkAAgQABwk3I6QgAKkCAAQABwk3I6QgAKkCAAAA.',
Sl='Slayur:BAABLgAECn8gAAIIAAkJwQ1oKgCsAQAIAAkJwQ1oKgCsAQAAAA==.Slinkeril:BAABLgAECn8gAAIgAAcJXBShCgCIAQAgAAcJXBShCgCIAQAAAA==.Sloppydro:BAAALgAECgcJEQAAAA==.',
Sm='Smackthat:BAAALgAECgQJBgABLgAECgYJDgAHAAAAAA==.Smokey:BAAALgAECgUJCQABLgAECgYJDgAHAAAAAA==.Smokinpurrp:BAAALgAECgQJBAAAAA==.Smoky:BAAALgAECgYJDgAAAA==.',
So='Soju:BAAALgAECgEJBgAAAA==.Sotari:BAAALgADCggJCQAAAA==.',
Sp='Spintowin:BAAALgAECgkJCAAAAA==.Sploosh:BAAALgAECgYJCgAAAA==.',
St='Stabberz:BAACLgAFFH8UAAIgAAQJQBoRBABOAQAgAAQJQBoRBABOAQAuAAQKf0kAAyAACQmfIW4DAHoCACAACQmfIW4DAHoCACMABAk8EqhLAM0AAAAA.Stõrmy:BAAALgAECgIJAgAAAA==.',
Su='Sushiroll:BAAALgAFFAEJAQABLgAFFAgJHAAFAGggAA==.',
Sw='Sweetsourrex:BAAALgAFFAQJBAAAAA==.',
Sy='Synkro:BAAALgAECgYJBwABLgAECgcJBwAHAAAAAA==.',
Ta='Tatisjr:BAAALgAECgYJCgAAAA==.',
Te='Temoin:BAAALgAECgEJAwAAAA==.Tempprance:BAAALgAECgQJBAAAAA==.',
Th='Thewordalive:BAAALgADCgIJAgAAAA==.Tholdraz:BAAALgAECgEJAQAAAA==.Thooran:BAAALgAECgIJBwAAAA==.Thrass:BAABLgAECn8gAAILAAkJ+hGSVADcAQALAAkJ+hGSVADcAQAAAA==.Throngler:BAAALgAECgYJEQABLgAFFAUJDwACADEGAA==.',
To='Tohru:BAAALgAECgIJAgABLgAFFAYJJgAFADsiAA==.Toobrunner:BAACLgAFFH8kAAIaAAgJgCJQBQC2AgAaAAgJgCJQBQC2AgAuAAQKfx4AAhoACAlSImUbAK4CABoACAlSImUbAK4CAAAA.Tool:BAACLgAFFH8vAAIaAAkJESWvAABeAwAaAAkJESWvAABeAwAuAAQKfyUAAhoACQmbJWECAGADABoACQmbJWECAGADAAAA.',
Tr='Trollz:BAABLgAECn8UAAIZAAgJbQelEwAvAQAZAAgJbQelEwAvAQAAAA==.',
Up='Upside:BAAALgAECgIJAwAAAA==.',
Va='Vampress:BAAALgAECgQJBQAAAA==.Varvera:BAAALgADCgMJAwAAAA==.',
Ve='Velannis:BAACLgAFFH8FAAMgAAMJ3h47CQCyAAAgAAIJURw7CQCyAAATAAEJ9yMADwBnAAAuAAQKfzIAAxMACQl6IyMBAPwCABMACQk5IyMBAPwCACAABwm9ILMHANcBAAAA.',
Vi='Virikas:BAABLgAECn8kAAMXAAgJABy2IABHAgAXAAgJABy2IABHAgAWAAQJKAwldwCCAAAAAA==.',
Vo='Voidhunter:BAABLgAECn8TAAIaAAgJUxXCWwCOAQAaAAgJUxXCWwCOAQAAAA==.Voodooki:BAABLgAECn9BAAIkAAkJHRfvEgA8AgAkAAkJHRfvEgA8AgAAAA==.',
Vu='Vuo:BAABLgAECn88AAImAAkJ6RYyOgDyAQAmAAkJ6RYyOgDyAQAAAA==.',
Wa='Wayside:BAAALgAECgkJCAAAAA==.',
We='Weedonice:BAAALgAECgcJBQAAAA==.',
Wh='Wheelytank:BAABLgAFFH8RAAIEAAQJQhaPPQAqAQAEAAQJQhaPPQAqAQAAAA==.White:BAAALgAECgQJBwABLgABCgIJAgAHAAAAAA==.',
Wi='Wickedshaman:BAAALgADCgkJCQABLgAECgkJPAAmAOkWAA==.Wilburoni:BAAALgADCgIJAgAAAA==.Wiping:BAAALgAECgIJAQABLgAECgcJIgADADMlAA==.',
Xf='Xfreshh:BAAALgAECgYJDQAAAA==.',
Xn='Xnomorp:BAAALgAECgQJBAAAAA==.',
Ya='Yamalock:BAABLgAFFH8TAAMCAAUJJxl+RAA7AQACAAUJJxl+RAA7AQAZAAEJ8QExLQAzAAAAAA==.Yamamist:BAAALgAECgYJCgABLgAFFAMJBgALAK4WAA==.Yamå:BAACLgAFFH8GAAILAAMJrhZxgADdAAALAAMJrhZxgADdAAAuAAQKfxoAAgsABglrIktfAB0CAAsABglrIktfAB0CAAAA.',
Ye='Yeaffa:BAAALgADCgYJBgAAAA==.',
Yi='Yingzhi:BAAALgAECgUJBQAAAA==.',
Za='Zavalu:BAABLgAECn84AAIXAAgJIiHnEgCyAgAXAAgJIiHnEgCyAgAAAA==.',
Ze='Zerosh:BAABLgAECn8xAAIgAAkJJRMRBgAKAgAgAAkJJRMRBgAKAgAAAA==.',
Zi='Zinaida:BAAALgADCggJCAAAAA==.',
Zo='Zortok:BAABLgAECn8hAAIWAAkJcxM2KACpAQAWAAkJcxM2KACpAQAAAA==.',
Zu='Zugszy:BAAALgAECgYJBgAAAA==.',
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
