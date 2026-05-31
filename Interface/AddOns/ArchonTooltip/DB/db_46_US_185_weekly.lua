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

local lookup = {'Paladin-Holy','Paladin-Retribution','Warlock-Destruction','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','Paladin-Protection','Hunter-Survival','Unknown-Unknown','Monk-Brewmaster','DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','DeathKnight-Unholy','Warlock-Demonology','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Rogue-Outlaw','Monk-Windwalker','Druid-Guardian','Shaman-Restoration','Warlock-Affliction','DemonHunter-Devourer','Mage-Arcane','Mage-Fire','Warrior-Protection','Druid-Feral','Druid-Restoration','Priest-Holy','Rogue-Assassination','DemonHunter-Vengeance','Priest-Discipline','Rogue-Subtlety','Druid-Balance','Monk-Mistweaver','Hunter-BeastMastery',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abeblinkin:BAAALgAECgQJBAAAAA==.Aborlight:BAAALgAECgQJCwAAAA==.',
Ad='Adit:BAAALgAECggJDgAAAA==.Adug:BAAALgADCgMJAwAAAA==.',
Ae='Aedrius:BAABLgAECn8ZAAMBAAcJLhjINQClAQABAAYJrRnINQClAQACAAQJlxECwQAFAQAAAA==.',
Ag='Agnekie:BAAALgAECgcJEQAAAA==.',
Ai='Aiwass:BAABLgAECn9BAAIDAAkJxhFbBwDCAQADAAkJxhFbBwDCAQAAAA==.Aiyo:BAAALgAFFAEJAgAAAA==.',
Al='Alexander:BAAALgAECgMJAwAAAA==.Alpharius:BAAALgAECgUJBQAAAA==.',
Am='Amathricus:BAABLgAECn8zAAICAAkJkg79VACzAQACAAkJkg79VACzAQAAAA==.Amerika:BAAALgADCgIJAgAAAA==.',
Ar='Arawak:BAAALgADCgEJAQAAAA==.',
As='Ashuk:BAAALgAECgYJEAAAAA==.',
At='Athena:BAAALgAECgMJAwAAAA==.',
Au='Augtism:BAECLgAFFH8HAAMEAAQJ1Q+LFQAcAQAEAAQJ1Q+LFQAcAQAFAAMJcw0OOgC8AAAuAAQKfx0AAwUABwmfHuMdAM8BAAUABwmfHuMdAM8BAAQAAgm2EZMqAHwAAAEuAAUUBAkHAAQA1Q8A.Auitou:BAAALgAECggJCQAAAA==.Auralei:BAABLgAECn8ZAAIGAAYJ7wgfxQDjAAAGAAYJ7wgfxQDjAAAAAA==.',
Az='Azelia:BAAALgAECggJEwABLgAECgkJKgABADoVAA==.Azzy:BAABLgAECn8qAAQBAAkJOhXQIQDgAQABAAgJpRfQIQDgAQAHAAMJLgJVQwBAAAACAAIJ9gEaiQEpAAAAAA==.',
Ba='Bacta:BAAALgADCgUJBQAAAA==.',
Be='Beasti:BAAALgAECgIJAgAAAA==.Beelzebul:BAAALgAFFAQJBAAAAA==.',
Bi='Bigb:BAABLgAECn8mAAIIAAcJKSYEBQDEAgAIAAcJKSYEBQDEAgAAAA==.Bigpaladin:BAAALgADCgEJAQAAAA==.',
Bl='Black:BAAALgAECgUJCQAAAA==.',
Bo='Bombaclat:BAAALgADCgEJAQAAAA==.Boor:BAAALgAECgcJCAAAAA==.',
Br='Brilline:BAAALgAECgYJBwAAAA==.Brochese:BAAALgAECgEJAQABLgAECgcJEwAJAAAAAA==.Broka:BAAALgAECgMJAwAAAA==.',
Bu='Bubblewrap:BAAALgAECgQJCAABLgAFFAUJFQAKAOISAA==.Buwumkin:BAAALgAECgUJCwAAAA==.',
Ca='Cadaverous:BAABLgAECn8UAAMLAAkJ1hpuAwCHAgALAAkJ1hpuAwCHAgAMAAIJ5gnWTQBDAAABLgAECgYJGgANAGckAA==.Canadianguy:BAAALgADCgIJAgABLgAECgQJBAAJAAAAAA==.',
Ch='Cheyeon:BAAALgAECgYJBgAAAA==.Chonk:BAAALgADCgkJCwAAAA==.Chunguskhan:BAAALgAECgYJCAAAAA==.',
Cl='Classcarry:BAAALgADCgYJBgABLgAFFAgJHAAOAGggAA==.Claybigsby:BAACLgAFFH8TAAIPAAUJIhlyPwA1AQAPAAUJIhlyPwA1AQAuAAQKfx4AAwMACQlPGxADAMoCAAMACAm5HRADAMoCAA8ABwlwFq5xAHwBAAAA.Clif:BAACLgAFFH8JAAMQAAQJhAs9GgDrAAAQAAQJhAs9GgDrAAARAAIJxAdmPQCEAAAuAAQKfxkAAxEACAmqHNwWAJYCABEACAmqHNwWAJYCABAAAQl+HYpcAEwAAAAA.',
Co='Cosmiccosmo:BAAALgAECgQJCQAAAA==.',
Cu='Cucurbita:BAAALgADCgYJBgAAAA==.',
Cy='Cyndre:BAAALgADCgEJAQAAAA==.',
Da='Dargon:BAABLgAECn8XAAMFAAgJ3yNnBgAZAwAFAAgJ3yNnBgAZAwASAAYJ7hzSGwBSAQABLgAFFAUJCQACANEYAA==.',
De='Deadlyorc:BAAALgAECgIJAQAAAA==.Deaf:BAAALgAFFAEJAQABLgAFFAMJBQATAMIhAA==.Delphine:BAAALgADCgYJBgAAAA==.Demonblade:BAAALgADCgEJAQAAAA==.Demonifrita:BAAALgADCgkJCQAAAA==.Demoniosushi:BAAALgAECgMJBwABLgAECgYJDgAJAAAAAA==.Demonmane:BAAALgADCgMJAwAAAA==.Derpy:BAABLgAECn8jAAMUAAgJIQzVKwBHAQAUAAgJEAzVKwBHAQAKAAgJ+wMxPwDsAAAAAA==.',
Di='Dippindotz:BAAALgAECgEJAgABLgAFFAgJHAAOAGggAA==.',
Dj='Djheals:BAAALgAECgQJBQAAAA==.',
Do='Doobiemage:BAAALgAECgEJAgAAAA==.Dorenis:BAAALgAECgEJAgAAAA==.',
Dr='Drachese:BAAALgAECgEJAQABLgAECgcJEwAJAAAAAA==.Droopox:BAABLgAECn8eAAIVAAkJBQlOJgD7AAAVAAkJBQlOJgD7AAAAAA==.Druchese:BAAALgAECgYJCwABLgAECgcJEwAJAAAAAA==.',
Ea='Eagleeye:BAABLgAECn8dAAICAAYJXRGgsAACAQACAAYJXRGgsAACAQAAAA==.',
Em='Emsley:BAACLgAFFH8QAAINAAQJTwibJQDnAAANAAQJTwibJQDnAAAuAAQKf0YAAg0ACQnaFksgAMgBAA0ACQnaFksgAMgBAAAA.',
Er='Eri:BAACLgAFFH8NAAIWAAMJVx1xMAD+AAAWAAMJVx1xMAD+AAAuAAQKfycAAhYABgmHItUkABcCABYABgmHItUkABcCAAAA.Erised:BAAALgADCgkJDwAAAA==.',
Ev='Ev:BAAALgAFFAIJAwABLgAFFAMJBQATAMIhAA==.',
Ex='Exo:BAACLgAFFH8VAAIGAAUJzhrkRgA/AQAGAAUJzhrkRgA/AQAuAAQKfx4AAgYACAkzITYgAPMCAAYACAkzITYgAPMCAAAA.',
Fe='Felrid:BAAALgAECgYJBgABLgAFFAUJCQACANEYAA==.',
Fl='Floudruid:BAAALgADCgMJAwABLgABCgcJBwAJAAAAAA==.',
Fo='Focalors:BAAALgAFFAIJBAABLgAFFAQJBAAJAAAAAA==.Foobear:BAACLgAFFH8VAAIVAAUJjxZiCgAaAQAVAAUJjxZiCgAaAQAuAAQKfyoAAhUACQkTH88IAD8CABUACQkTH88IAD8CAAAA.Fozzy:BAABLgAECn8YAAIFAAgJpgeZTADVAAAFAAgJpgeZTADVAAAAAA==.Fozél:BAAALgAECgEJAQAAAA==.',
Fr='Franchescold:BAABLgAECn8gAAIOAAkJLxx7LwAtAgAOAAkJLxx7LwAtAgAAAA==.Franfran:BAABLgAECn8fAAIGAAkJdA+rYAClAQAGAAkJdA+rYAClAQAAAA==.Freasey:BAABLgAECn8eAAICAAYJkQ9atQD6AAACAAYJkQ9atQD6AAAAAA==.Frostbeard:BAAALgADCgQJBwAAAA==.',
Fu='Furiousfoo:BAAALgAECgUJEwABLgAFFAUJFQAVAI8WAA==.Furlock:BAABLgAECn8bAAMXAAYJvR5qDAByAQAXAAUJ+iBqDAByAQAPAAYJPRcPfgAyAQAAAA==.',
Ga='Gabriel:BAAALgAECgcJCAAAAA==.Galicia:BAAALgAECgYJBgAAAA==.Gantaris:BAAALgAECgYJDwAAAA==.',
Ge='Gengiskaan:BAAALgAECgQJBAAAAA==.',
Gi='Gir:BAAALgAECgYJDgAAAA==.Gixian:BAAALgAECgYJEAAAAA==.',
Go='Gochese:BAAALgAECgcJEwAAAA==.',
Gr='Gramid:BAACLgAFFH8JAAICAAUJ0RhNNAArAQACAAUJ0RhNNAArAQAuAAQKfxoAAgIACAlpJqwZAJICAAIACAlpJqwZAJICAAAA.Greenseer:BAABLgAECn8uAAIPAAYJPBqXVgCNAQAPAAYJPBqXVgCNAQAAAA==.Grognag:BAAALgAECgYJDgAAAA==.',
Gt='Gtoffmydh:BAAALgADCgIJAgAAAA==.',
Gw='Gwaralmighty:BAACLgAFFH8KAAIRAAQJZR2vEABhAQARAAQJZR2vEABhAQAuAAQKfzIAAhEACQlfIAEMAJQCABEACQlfIAEMAJQCAAAA.',
Ha='Haagen:BAAALgAECgMJCQAAAA==.Haagoon:BAAALgAECgIJAwAAAA==.Halfwolf:BAAALgADCgQJBAAAAA==.Hatch:BAACLgAFFH8FAAITAAMJwiGKBgD+AAATAAMJwiGKBgD+AAAuAAQKfx0AAhMABwmCJR0BAPMCABMABwmCJR0BAPMCAAAA.',
Hh='Hholdem:BAAALgADCgcJBwABLgAECgkJJgAUAMkOAA==.',
Hi='Hightones:BAACLgAFFH8NAAIYAAUJcwhXRwD4AAAYAAUJcwhXRwD4AAAuAAQKfyUAAhgACAk2IEoWANECABgACAk2IEoWANECAAAA.Him:BAAALgAECgYJBgAAAA==.',
Ho='Holdêm:BAABLgAECn8mAAIUAAkJyQ5EHwCeAQAUAAkJyQ5EHwCeAQAAAA==.Holeytoast:BAAALgAECgQJBAABLgAFFAUJFQANALAeAA==.Hollee:BAAALgADCgQJBAABLgAFFAUJFwAWAEcTAA==.Horsdoeuvres:BAAALgAECgcJDgAAAA==.',
Hu='Humberto:BAAALgAECgEJAQAAAA==.Hung:BAAALgAECgYJCwAAAA==.',
Ic='Icylady:BAAALgAECgYJCQAAAA==.',
If='Ifrita:BAACLgAFFH8HAAMGAAMJDgm0fQDCAAAGAAMJEAa0fQDCAAAZAAEJ4QrWBABCAAAuAAQKf0gABAYACQm+GbAiAHwCAAYACQm+GbAiAHwCABkABgkjE6oHAIYBABoAAQm1CSUSACkAAAAA.Ifrite:BAABLgAECn8dAAMOAAkJFw7FfgCGAQAOAAcJtAzFfgCGAQALAAgJiAoOGgDMAAAAAA==.',
Ik='Ikur:BAABLgAECn8ZAAMEAAgJERF5FABwAQAEAAcJkBF5FABwAQAFAAcJ0AcUTADXAAABLgAFFAQJDwABAK8bAA==.',
Im='Imbasoul:BAAALgAECgEJAQAAAA==.',
It='Itita:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneill:BAACLgAFFH8NAAICAAMJxAfVZgC8AAACAAMJxAfVZgC8AAAuAAQKfyUAAgIACQnjEDJlAIsBAAIACQnjEDJlAIsBAAAA.',
Je='Jezlana:BAAALgAECgcJCwAAAA==.',
Ji='Jillidan:BAAALgAECgIJAwAAAA==.',
Jo='Johnnynapalm:BAAALgAECgIJBAABLgAECgQJBAAJAAAAAA==.Jonnycraig:BAAALgAECgEJAgAAAA==.Jormi:BAABLgAECn8/AAMQAAkJZCKjAgAEAwAQAAkJZCKjAgAEAwAbAAMJlyF8IQALAQAAAA==.',
Ka='Kabaayi:BAAALgADCgEJAQAAAA==.Kaihu:BAAALgAECgMJAwAAAA==.Kalthael:BAAALgADCgkJGAAAAA==.Kasura:BAABLgAECn8sAAMcAAkJTRstCQAUAgAcAAgJAx0tCQAUAgAdAAcJdA68gwDQAAAAAA==.Katakuri:BAAALgAECgEJAQAAAA==.',
Kh='Kharahealer:BAABLgAECn8UAAIeAAcJIhfRNABrAQAeAAcJIhfRNABrAQAAAA==.',
Kl='Kllausy:BAAALgAECgIJAwAAAA==.',
Ko='Kochese:BAAALgAECgEJAQABLgAECgcJEwAJAAAAAA==.',
Kr='Krayt:BAAALgAECgEJBAAAAA==.',
Kw='Kwrr:BAAALgADCgYJBgABLgAFFAgJJgAPAEslAA==.',
La='Lambo:BAABLgAECn8eAAINAAgJDSAqDwBoAgANAAgJDSAqDwBoAgAAAA==.',
Le='Leafhoof:BAAALgAECgEJAQAAAA==.Lenona:BAAALgAECgIJAgAAAA==.Lexidia:BAAALgADCgUJBQAAAA==.Leynnar:BAAALgAECgUJDwAAAA==.',
Li='Licha:BAAALgAECgcJBQAAAA==.',
Lo='Lockme:BAABLgAFFH8KAAIPAAQJshFCVwACAQAPAAQJshFCVwACAQAAAA==.Loveyuling:BAAALgAECgEJBAABLgAECgQJBwAJAAAAAA==.',
Lu='Lunk:BAAALgAECgEJAwAAAA==.',
Ly='Lynel:BAAALgAECgEJAgAAAA==.',
['Ló']='Lóvecandy:BAAALgAECgQJBwAAAA==.',
Ma='Maruzensky:BAACLgAFFH8tAAIGAAgJUhupCAB1AgAGAAgJUhupCAB1AgAuAAQKfyoAAwYACQleI6oPAEoDAAYACQleI6oPAEoDABoABAmtD6IHAP8AAAAA.Mary:BAACLgAFFH8QAAIfAAYJpSEuAQDBAQAfAAYJpSEuAQDBAQAuAAQKfxgAAh8ACAnqH7MCAMECAB8ACAnqH7MCAMECAAAA.',
Me='Mechfury:BAAALgADCgEJAgAAAA==.Melitha:BAAALgADCggJCAABLgAECgkJPwAQAGQiAA==.Mero:BAACLgAFFH8QAAMYAAUJ/xa1PAAWAQAYAAQJ+hG1PAAWAQAgAAIJLCA5DABaAAAuAAQKfyQAAyAACAl1HFsJANkBACAABwlaH1sJANkBABgABwnYFfpmAG0BAAAA.Metal:BAABLgAECn8lAAIhAAgJCRhxEwAlAgAhAAgJCRhxEwAlAgAAAA==.Meyrey:BAAALgADCgYJCwAAAA==.',
Mi='Miorine:BAAALgAECgEJAQABLgAFFAQJBAAJAAAAAA==.Mistbehavin:BAACLgAFFH8VAAIKAAUJ4hKPIAAVAQAKAAUJ4hKPIAAVAQAuAAQKfyQAAgoACQlCGfgcABsCAAoACQlCGfgcABsCAAAA.',
Mo='Mog:BAABLgAECn8iAAIBAAcJMyXtGgA9AgABAAcJMyXtGgA9AgAAAA==.Moochese:BAAALgAECgEJAQABLgAECgcJEwAJAAAAAA==.Moostache:BAAALgAECgMJBAAAAA==.',
My='Mytz:BAAALgADCgYJCwAAAA==.',
['Má']='Mátthéw:BAAALgADCgcJCQAAAA==.',
Ne='Nemisai:BAAALgAECgYJDAAAAA==.',
No='Nobody:BAAALgADCgcJBwAAAA==.',
Nu='Nuttinerbutt:BAAALgAFFAMJAwAAAA==.',
Oc='Ochra:BAAALgAECgEJAwAAAA==.',
Og='Ogparadox:BAABLgAECn8UAAIGAAYJLxkwdAB2AQAGAAYJLxkwdAB2AQAAAA==.',
Ok='Ok:BAABLgAECn8ZAAIIAAgJ7RNoHACrAQAIAAgJ7RNoHACrAQAAAA==.',
Or='Orionbtch:BAABLgAECn8cAAIiAAgJOAoYIQByAQAiAAgJOAoYIQByAQAAAA==.',
Ov='Overheat:BAACLgAFFH8HAAIGAAMJcRhkaADzAAAGAAMJcRhkaADzAAAuAAQKfx8AAgYACQlmHxUXALkCAAYACQlmHxUXALkCAAAA.',
Po='Poppy:BAABLgAECn8eAAIGAAgJhgdkmQAsAQAGAAgJhgdkmQAsAQAAAA==.Portinglol:BAAALgAFFAQJBAABLgAFFAgJHAAOAGggAA==.',
Ps='Psycilocibin:BAAALgADCgEJAQAAAA==.',
Qw='Qwiix:BAAALgADCgMJAwAAAA==.Qwixx:BAAALgADCgEJAQAAAA==.',
Ra='Rafikki:BAAALgAECggJEwAAAA==.Ragerok:BAAALgAECgUJBQAAAA==.Ratidari:BAABLgAECn85AAIYAAkJNxYwKgALAgAYAAkJNxYwKgALAgAAAA==.Ravenstorm:BAABLgAECn8UAAIjAAYJNQw0RADfAAAjAAYJNQw0RADfAAAAAA==.',
Re='Remmîngton:BAABLgAECn88AAMBAAkJwB5XCwDDAgABAAkJwB5XCwDDAgACAAIJCgobfAEuAAAAAA==.Retbulls:BAAALgAECgYJDwAAAA==.Reverie:BAAALgADCgMJAwAAAA==.',
Rh='Rhynehardt:BAAALgAECgQJBAAAAA==.',
Ri='Riptidedro:BAACLgAFFH8LAAMWAAQJShbOKgAUAQAWAAQJShbOKgAUAQANAAEJ9QB3TgAxAAAuAAQKfyoAAhYACQlgHZ0TAHgCABYACQlgHZ0TAHgCAAAA.',
Ru='Rukaz:BAAALgADCgYJBgAAAA==.Runslikedeer:BAABLgAECn8WAAIdAAgJChcGJQARAgAdAAgJChcGJQARAgAAAA==.Rustyarrow:BAAALgAECgEJAQAAAA==.',
Ry='Ryukk:BAABLgAECn8uAAIOAAkJdxZ4RgDcAQAOAAkJdxZ4RgDcAQAAAA==.',
Sa='Sanoth:BAAALgADCgEJAgAAAA==.Sarana:BAAALgADCgMJAwAAAA==.Sarkhael:BAAALgAECgUJCAAAAA==.',
Se='Sean:BAACLgAFFH8VAAIGAAUJOhsPSQA8AQAGAAUJOhsPSQA8AQAuAAQKfyQAAgYACQlwIUkXAB4DAAYACQlwIUkXAB4DAAAA.Secksecute:BAAALgAECgIJBQAAAA==.Seinsleer:BAAALgAECgQJBAAAAA==.Serah:BAAALgAFFAQJBAAAAA==.Seris:BAAALgAECgYJBgABLgAFFAUJCQACANEYAA==.',
Sh='Shel:BAABLgAECn8oAAIYAAkJHwtWXABaAQAYAAkJHwtWXABaAQAAAA==.Sheppy:BAAALgAFFAQJBAAAAA==.Shimakaze:BAACLgAFFH8gAAMOAAYJKSBEDgBpAQAOAAQJZiVEDgBpAQAMAAIJMwt+MQBEAAAuAAQKfyIAAg4ABwljJNcrAIkCAA4ABwljJNcrAIkCAAAA.Shizaam:BAACLgAFFH8VAAINAAUJsB68FABJAQANAAUJsB68FABJAQAuAAQKfyQAAw0ACQlMI4gFAD4DAA0ACQlMI4gFAD4DABYAAQkrCXSdADQAAAAA.Shlommy:BAABLgAECn8YAAIPAAgJ5xNTRwC5AQAPAAgJ5xNTRwC5AQAAAA==.',
Si='Siinns:BAACLgAFFH8MAAIUAAQJxBcVDgA5AQAUAAQJxBcVDgA5AQAuAAQKfyUABBQACQnPHX4NAFgCABQACQnPHX4NAFgCACQAAwmkEZ5rAJsAAAoAAgnOE0J6AFsAAAAA.Simp:BAAALgAECgIJAgAAAA==.Sinfxl:BAAALgAECgYJCgAAAA==.Sippinsizurp:BAAALgAECggJDwAAAA==.',
Sk='Skadooget:BAAALgADCgYJBgAAAA==.Skullkíng:BAAALgADCgEJAQAAAA==.Skullmages:BAACLgAFFH8QAAICAAQJABgACQBnAQACAAQJABgACQBnAQAuAAQKfxkAAgIABwk3I6QgAKkCAAIABwk3I6QgAKkCAAAA.',
Sl='Slayur:BAABLgAECn8gAAIRAAkJwQ0jJgCyAQARAAkJwQ0jJgCyAQAAAA==.Slinkeril:BAABLgAECn8fAAIfAAYJbxU5DABWAQAfAAYJbxU5DABWAQAAAA==.Sloppydro:BAAALgAECgYJEAAAAA==.',
Sm='Smackthat:BAAALgAECgQJBgABLgAECgYJDgAJAAAAAA==.Smokey:BAAALgAECgUJCQABLgAECgYJDgAJAAAAAA==.Smokinpurrp:BAAALgAECgQJBAAAAA==.Smoky:BAAALgAECgYJDgAAAA==.',
So='Soju:BAAALgAECgEJBgAAAA==.Sotari:BAAALgADCggJCQAAAA==.',
Sp='Spintowin:BAAALgAECgkJCAAAAA==.Sploosh:BAAALgAECgMJAwAAAA==.',
St='Stabberz:BAACLgAFFH8RAAIfAAQJeBloAwBQAQAfAAQJeBloAwBQAQAuAAQKf0kAAx8ACQmfIe0CAIECAB8ACQmfIe0CAIECACIABAk8EqhLAM0AAAAA.Stõrmy:BAAALgAECgIJAgAAAA==.',
Su='Sushiroll:BAAALgAFFAEJAQABLgAFFAgJHAAOAGggAA==.',
Sw='Sweetsourrex:BAAALgAFFAEJAQABLgAFFAEJAgAJAAAAAA==.',
Sy='Synkro:BAAALgAECgYJBgABLgAECgYJCgAJAAAAAA==.',
Ta='Tatisjr:BAAALgAECgQJBQAAAA==.',
Te='Temoin:BAAALgAECgEJAgAAAA==.Tempprance:BAAALgAECgQJBAAAAA==.',
Th='Thewordalive:BAAALgADCgIJAgAAAA==.Tholdraz:BAAALgAECgEJAQAAAA==.Thooran:BAAALgAECgIJBwAAAA==.Thrass:BAABLgAECn8gAAIGAAkJ+hGuTgDYAQAGAAkJ+hGuTgDYAQAAAA==.Throngler:BAAALgAECgYJEQAAAA==.',
To='Tohru:BAAALgAECgIJAgABLgAFFAQJBAAJAAAAAA==.Toobrunner:BAACLgAFFH8gAAIYAAcJICJcCABIAgAYAAcJICJcCABIAgAuAAQKfx4AAhgACAlSImUbAK4CABgACAlSImUbAK4CAAAA.Tool:BAACLgAFFH8lAAIYAAgJMCScAQDqAgAYAAgJMCScAQDqAgAuAAQKfyUAAhgACQmbJd4BAGIDABgACQmbJd4BAGIDAAAA.',
Tr='Trollz:BAABLgAECn8UAAIXAAgJbAfpEAAyAQAXAAgJbAfpEAAyAQAAAA==.',
Up='Upside:BAAALgAECgEJAgAAAA==.',
Va='Vampress:BAAALgAECgEJAgAAAA==.Varvera:BAAALgADCgMJAwAAAA==.',
Ve='Velannis:BAACLgAFFH8FAAMfAAMJ3h7iBwC4AAAfAAIJURziBwC4AAATAAEJ9yOiDABqAAAuAAQKfzIAAxMACQl6I+8AAP0CABMACQk5I+8AAP0CAB8ABwm9IAMHANsBAAAA.',
Vi='Virikas:BAABLgAECn8kAAMWAAgJABzoHABLAgAWAAgJABzoHABLAgANAAQJKAxAawCGAAAAAA==.',
Vo='Voidhunter:BAABLgAECn8TAAIYAAgJUxXCWwCOAQAYAAgJUxXCWwCOAQAAAA==.Voodooki:BAABLgAECn88AAIjAAkJ0BTCFAAVAgAjAAkJ0BTCFAAVAgAAAA==.',
Vu='Vuo:BAABLgAECn84AAIlAAgJBhhiOQDiAQAlAAgJBhhiOQDiAQAAAA==.',
Wa='Wayside:BAAALgAECgIJCAAAAA==.',
We='Weedonice:BAAALgAECgcJBQAAAA==.',
Wh='Wheelytank:BAABLgAFFH8MAAICAAQJNw8tOwAeAQACAAQJNw8tOwAeAQAAAA==.White:BAAALgAECgQJBwABLgABCgIJAgAJAAAAAA==.',
Wi='Wickedshaman:BAAALgADCgkJCQABLgAECggJOAAlAAYYAA==.Wilburoni:BAAALgADCgIJAgAAAA==.Wiping:BAAALgAECgIJAQABLgAECgcJIgABADMlAA==.',
Xf='Xfreshh:BAAALgAECgYJDQAAAA==.',
Ya='Yamalock:BAABLgAFFH8NAAMPAAUJrBPSQgAuAQAPAAUJrBPSQgAuAQAXAAEJ8QHPJAA1AAAAAA==.Yamamist:BAAALgAECgYJCgABLgAFFAMJBgAGAK4WAA==.Yamå:BAACLgAFFH8GAAIGAAMJrhZLcADhAAAGAAMJrhZLcADhAAAuAAQKfxoAAgYABglrIktfAB0CAAYABglrIktfAB0CAAAA.',
Ye='Yeaffa:BAAALgADCgYJBgAAAA==.',
Yi='Yingzhi:BAAALgADCgIJAgAAAA==.',
Za='Zavalu:BAABLgAECn84AAIWAAgJIiEqEAC3AgAWAAgJIiEqEAC3AgAAAA==.',
Ze='Zerosh:BAABLgAECn8xAAIfAAkJJRNSBQATAgAfAAkJJRNSBQATAgAAAA==.',
Zi='Zinaida:BAAALgADCggJCAAAAA==.',
Zo='Zortok:BAABLgAECn8hAAINAAkJcxNaJACrAQANAAkJcxNaJACrAQAAAA==.',
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
