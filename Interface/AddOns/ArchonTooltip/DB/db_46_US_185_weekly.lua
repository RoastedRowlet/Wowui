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

local lookup = {'Paladin-Holy','Paladin-Retribution','Warlock-Destruction','Warrior-Fury','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','Paladin-Protection','DeathKnight-Unholy','Hunter-Survival','Monk-Brewmaster','DeathKnight-Frost','DeathKnight-Blood','Unknown-Unknown','Warlock-Demonology','Warrior-Arms','Evoker-Devastation','Rogue-Outlaw','Monk-Windwalker','Druid-Guardian','Shaman-Elemental','Shaman-Restoration','Warlock-Affliction','DemonHunter-Devourer','Mage-Arcane','Mage-Fire','Warrior-Protection','Druid-Feral','Druid-Restoration','Priest-Holy','Rogue-Assassination','DemonHunter-Vengeance','Priest-Discipline','Rogue-Subtlety','Druid-Balance','Monk-Mistweaver','Hunter-BeastMastery',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abeblinkin:BAAALgAECgUJCAAAAA==.Aborlight:BAAALgAECgQJCwAAAA==.',
Ad='Adit:BAAALgAECggJDgAAAA==.Adug:BAAALgADCgMJAwAAAA==.',
Ae='Aedrius:BAABLgAECn8ZAAMBAAcJLhjINQClAQABAAYJrRnINQClAQACAAQJlxECwQAFAQAAAA==.',
Ag='Agnekie:BAAALgAECgcJEgAAAA==.',
Ai='Aiwass:BAABLgAECn9KAAIDAAkJjROnBgDkAQADAAkJjROnBgDkAQAAAA==.Aiyo:BAAALgAFFAIJAwAAAA==.',
Al='Alexander:BAAALgAECgMJAwAAAA==.Alpharius:BAAALgAECgUJBQAAAA==.',
Am='Amathricus:BAABLgAECn8zAAICAAkJkg7WWgCyAQACAAkJkg7WWgCyAQAAAA==.Amerika:BAAALgADCgIJAgAAAA==.',
Ar='Arawak:BAAALgADCgEJAQAAAA==.',
As='Ashuk:BAABLgAECn8WAAIEAAYJkgcRWwDaAAAEAAYJkgcRWwDaAAAAAA==.',
At='Athena:BAAALgAECgMJAwAAAA==.',
Au='Augtism:BAECLgAFFH8IAAMFAAUJgA+gFwAEAQAFAAQJ1Q+gFwAEAQAGAAQJdAq5NADmAAAuAAQKfx0AAwYABwmfHm4fANUBAAYABwmfHm4fANUBAAUAAgm2ER0sAHwAAAEuAAUUBQkIAAUAgA8A.Auitou:BAAALgAECggJCQAAAA==.Auralei:BAABLgAECn8eAAIHAAcJgAjCrAAiAQAHAAcJgAjCrAAiAQAAAA==.',
Az='Azelia:BAAALgAECggJEwABLgAECgkJKgABADoVAA==.Azzy:BAABLgAECn8qAAQBAAkJOhXUIwDcAQABAAgJpRfUIwDcAQAIAAMJLgLgRgBAAAACAAIJ9gHclwEqAAAAAA==.',
Ba='Bacta:BAAALgADCgUJBQAAAA==.',
Be='Beasti:BAAALgAECgIJAgAAAA==.Beelzebul:BAAALgAFFAQJBAABLgAFFAYJJAAJABwiAA==.',
Bi='Bigb:BAABLgAECn8mAAIKAAcJKSYEBQDEAgAKAAcJKSYEBQDEAgAAAA==.Bigpaladin:BAAALgADCgEJAQAAAA==.',
Bl='Black:BAAALgAECgUJCQAAAA==.',
Bo='Bombaclat:BAAALgADCgEJAQAAAA==.Boor:BAAALgAECgcJCAAAAA==.',
Br='Brilline:BAAALgAECgYJBwAAAA==.Brochese:BAAALgAECgUJBgABLgAECggJGQABACUdAA==.Broka:BAAALgAECgMJAwAAAA==.',
Bu='Bubblewrap:BAAALgAECgQJCAABLgAFFAYJFgALAE4TAA==.Buwumkin:BAAALgAECgUJCwAAAA==.',
Ca='Cadaverous:BAACLgAFFH8FAAIMAAMJPhS5EQDgAAAMAAMJPhS5EQDgAAAuAAQKfxQAAwwACQnWGuwDAIoCAAwACQnWGuwDAIoCAA0AAgnmCRJSAEIAAAAA.Canadianguy:BAAALgADCgIJAgABLgAECgUJCAAOAAAAAA==.',
Ch='Cheyeon:BAAALgAECgYJBgAAAA==.Chonk:BAAALgADCgkJCwAAAA==.Chunguskhan:BAAALgAFFAIJAgAAAA==.',
Cl='Classcarry:BAAALgADCgYJBgABLgAFFAgJHAAJAGggAA==.Claybigsby:BAACLgAFFH8UAAMPAAYJQBcZSAApAQAPAAUJIhkZSAApAQADAAEJtQ/AHgBTAAAuAAQKfx4AAwMACQlPGxADAMoCAAMACAm5HRADAMoCAA8ABwlwFq5xAHwBAAAA.Clif:BAACLgAFFH8JAAMQAAQJhAtWHgDnAAAQAAQJhAtWHgDnAAAEAAIJxAcUQwB+AAAuAAQKfxkAAwQACAmqHNwWAJYCAAQACAmqHNwWAJYCABAAAQl+HY1jAEsAAAAA.',
Co='Cosmiccosmo:BAAALgAECgQJCQAAAA==.',
Cu='Cucurbita:BAAALgADCgYJBgAAAA==.',
Cy='Cyndre:BAAALgADCgEJAQAAAA==.',
Da='Dargon:BAABLgAECn8XAAMGAAgJ3yNnBgAZAwAGAAgJ3yNnBgAZAwARAAYJ7hzSGwBSAQABLgAFFAUJCQACANEYAA==.',
De='Deadlylady:BAAALgAECgUJBQAAAA==.Deadlyorc:BAAALgAECgIJAQAAAA==.Deaf:BAAALgAFFAEJAQABLgAFFAMJBQASAMIhAA==.Delphine:BAAALgADCgYJBgAAAA==.Demonblade:BAAALgADCgEJAQAAAA==.Demonifrita:BAAALgADCgkJCQAAAA==.Demoniosushi:BAAALgAECgMJBwABLgAECgYJDgAOAAAAAA==.Demonmane:BAAALgADCgMJAwAAAA==.Derpy:BAABLgAECn8qAAMTAAgJWhENJACFAQATAAgJWhENJACFAQALAAgJ+wOKQQDsAAAAAA==.',
Di='Dippindotz:BAAALgAECgEJAgABLgAFFAgJHAAJAGggAA==.',
Dj='Djheals:BAAALgAECgQJBQAAAA==.',
Do='Doobiedruid:BAAALgAECgMJBQAAAA==.Doobiemage:BAAALgAECgEJAgAAAA==.Dorenis:BAAALgAECgEJAgAAAA==.',
Dr='Drachese:BAAALgAECgEJAQABLgAECggJGQABACUdAA==.Droopox:BAABLgAECn8eAAIUAAkJBQmPKgD1AAAUAAkJBQmPKgD1AAAAAA==.Druchese:BAAALgAECgYJCwABLgAECggJGQABACUdAA==.',
Ea='Eagleeye:BAABLgAECn8dAAICAAYJXRFyvAABAQACAAYJXRFyvAABAQAAAA==.',
Em='Emsley:BAACLgAFFH8TAAIVAAQJmAupJwDuAAAVAAQJmAupJwDuAAAuAAQKf0gAAhUACQmkFzMhAMwBABUACQmkFzMhAMwBAAAA.',
Er='Eri:BAACLgAFFH8PAAIWAAMJEx5qNAD5AAAWAAMJEx5qNAD5AAAuAAQKfycAAhYABgmHIjcnABYCABYABgmHIjcnABYCAAAA.Erised:BAAALgADCgkJDwAAAA==.',
Ev='Ev:BAAALgAFFAIJAwABLgAFFAMJBQASAMIhAA==.',
Ex='Exo:BAACLgAFFH8WAAIHAAYJMxeQMQCPAQAHAAYJMxeQMQCPAQAuAAQKfx4AAgcACAkzITYgAPMCAAcACAkzITYgAPMCAAAA.',
Fe='Felrid:BAAALgAECgYJBgABLgAFFAUJCQACANEYAA==.',
Fl='Floudruid:BAAALgADCgMJAwABLgABCgcJBwAOAAAAAA==.',
Fo='Focalors:BAAALgAFFAIJBAABLgAFFAYJJAAJABwiAA==.Foobear:BAACLgAFFH8WAAIUAAYJ+xLvCABJAQAUAAYJ+xLvCABJAQAuAAQKfyoAAhQACQkTH6UJADwCABQACQkTH6UJADwCAAAA.Fozzy:BAABLgAECn8YAAIGAAgJpgcNTQDsAAAGAAgJpgcNTQDsAAAAAA==.Fozél:BAAALgAECgEJAQAAAA==.',
Fr='Franchescold:BAABLgAECn8gAAIJAAkJLxzUMgArAgAJAAkJLxzUMgArAgAAAA==.Franfran:BAABLgAECn8fAAIHAAkJdA9oYAC5AQAHAAkJdA9oYAC5AQAAAA==.Freasey:BAABLgAECn8eAAICAAYJkQ/JvwD8AAACAAYJkQ/JvwD8AAAAAA==.Frostbeard:BAAALgADCgQJBwAAAA==.',
Fu='Furiousfoo:BAAALgAECgUJEwABLgAFFAYJFgAUAPsSAA==.Furlock:BAABLgAECn8bAAMXAAYJvR6qDQBuAQAXAAUJ+iCqDQBuAQAPAAYJPRdMgwAuAQAAAA==.',
Ga='Gabriel:BAAALgAECgcJCAAAAA==.Galicia:BAAALgAECgYJBgAAAA==.Gantaris:BAAALgAECgYJDwAAAA==.',
Ge='Gengiskaan:BAAALgAECgYJCgAAAA==.',
Gi='Gir:BAAALgAECgcJDwAAAA==.Gixian:BAAALgAECgYJEAAAAA==.',
Go='Gochese:BAABLgAECn8ZAAMBAAgJJR2eEgBzAgABAAgJJR2eEgBzAgACAAYJcQsKyADxAAAAAA==.',
Gr='Gramid:BAACLgAFFH8JAAICAAUJ0RhjPAAjAQACAAUJ0RhjPAAjAQAuAAQKfxoAAgIACAlpJuAbAJMCAAIACAlpJuAbAJMCAAAA.Greenseer:BAABLgAECn8uAAIPAAYJPBomWgCKAQAPAAYJPBomWgCKAQAAAA==.Grognag:BAAALgAECgYJDgAAAA==.',
Gt='Gtoffmydh:BAAALgADCgIJAgAAAA==.',
Gw='Gwaralmighty:BAACLgAFFH8OAAIEAAQJ7h2jEwBbAQAEAAQJ7h2jEwBbAQAuAAQKfzIAAgQACQlfIE4NAJECAAQACQlfIE4NAJECAAAA.',
Gy='Gypo:BAAALgAECgEJAQAAAA==.',
Ha='Haagen:BAAALgAECgUJCgAAAA==.Haagoon:BAAALgAECgMJBAAAAA==.Haagoonus:BAAALgAECgEJAQAAAA==.Halfwolf:BAAALgADCgQJBAAAAA==.Hatch:BAACLgAFFH8FAAISAAMJwiGCBwD7AAASAAMJwiGCBwD7AAAuAAQKfx0AAhIABwmCJR0BAPMCABIABwmCJR0BAPMCAAAA.',
Hh='Hholdem:BAAALgADCgcJBwABLgAECgkJJgATAMkOAA==.',
Hi='Hightones:BAACLgAFFH8OAAIYAAYJCggPNgA2AQAYAAYJCggPNgA2AQAuAAQKfyUAAhgACAk2IEoWANECABgACAk2IEoWANECAAAA.Him:BAAALgAECgYJBgAAAA==.',
Ho='Holdêm:BAABLgAECn8mAAITAAkJyQ7DIQCVAQATAAkJyQ7DIQCVAQAAAA==.Holeytoast:BAAALgAECgQJBAABLgAFFAYJFgAVADkdAA==.Hollee:BAAALgADCgUJCAABLgAFFAUJGAAWALIWAA==.Horsdoeuvres:BAAALgAECggJDwAAAA==.',
Hu='Humberto:BAAALgAECgEJAQAAAA==.Hung:BAAALgAECgYJCwAAAA==.',
Ic='Icylady:BAAALgAECgYJCgAAAA==.',
If='Ifrita:BAACLgAFFH8HAAMHAAMJDgmrhgDAAAAHAAMJEAarhgDAAAAZAAEJ4QrDBQBCAAAuAAQKf0kABAcACQlyGqYgAJYCAAcACQlyGqYgAJYCABkABgkjE6oHAIYBABoAAQm1CeUTACkAAAAA.Ifrite:BAABLgAECn8jAAMMAAkJrhFjCwCyAQAMAAgJ2hBjCwCyAQAJAAgJeQ7FfgCGAQAAAA==.',
Ik='Ikur:BAABLgAECn8ZAAMFAAgJEREsFQBwAQAFAAcJkBEsFQBwAQAGAAcJ0AcQTQDsAAABLgAFFAQJDwABAK8bAA==.',
Im='Imbasoul:BAAALgAECgEJAQAAAA==.',
It='Itita:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneill:BAACLgAFFH8NAAICAAMJxAdpcwC1AAACAAMJxAdpcwC1AAAuAAQKfyUAAgIACQnjENxoAJIBAAIACQnjENxoAJIBAAAA.',
Je='Jezlana:BAAALgAECgcJCwAAAA==.',
Ji='Jillidan:BAAALgAECgIJAwAAAA==.',
Jo='Johnnynapalm:BAAALgAECgIJBAABLgAECgQJBAAOAAAAAA==.Jonnycraig:BAAALgAECgEJAgAAAA==.Jormi:BAABLgAECn9AAAMQAAkJZCLVAgAEAwAQAAkJZCLVAgAEAwAbAAMJlyFnIwAIAQAAAA==.',
Ka='Kabaayi:BAAALgADCgEJAQAAAA==.Kaihu:BAAALgAECgMJAwAAAA==.Kalthael:BAAALgADCgkJGAAAAA==.Kasura:BAABLgAECn8sAAMcAAkJTRsDCgASAgAcAAgJAx0DCgASAgAdAAcJdA68gwDQAAAAAA==.Katakuri:BAAALgAECgEJAgAAAA==.',
Kh='Kharahealer:BAABLgAECn8UAAIeAAcJIhfRNABrAQAeAAcJIhfRNABrAQAAAA==.',
Kl='Kllausy:BAAALgAECgIJAwAAAA==.',
Ko='Kochese:BAAALgAECgEJAQABLgAECggJGQABACUdAA==.',
Kr='Krayt:BAAALgAECgEJBQAAAA==.',
Kw='Kwrr:BAAALgADCgYJBgABLgAFFAgJJgAPAEslAA==.',
La='Lambo:BAABLgAECn8eAAIVAAgJDSB/EABkAgAVAAgJDSB/EABkAgAAAA==.',
Le='Leafhoof:BAAALgAECgEJAQAAAA==.Lenona:BAAALgAECgIJAgAAAA==.Lexidia:BAAALgADCgUJBQAAAA==.Leynnar:BAAALgAECgUJDwAAAA==.',
Li='Licha:BAAALgAECgcJBQAAAA==.',
Lo='Lockme:BAABLgAFFH8KAAIPAAQJshHyYAD0AAAPAAQJshHyYAD0AAAAAA==.Lothiriel:BAAALgAECgUJBQAAAA==.Loveyuling:BAAALgAECgEJBAABLgAECgQJBwAOAAAAAA==.',
Lu='Lunk:BAAALgAECgEJAwAAAA==.',
Ly='Lynel:BAAALgAECgEJAgAAAA==.',
['Ló']='Lóvecandy:BAAALgAECgQJBwAAAA==.',
Ma='Maruzensky:BAACLgAFFH8yAAIHAAgJUhsiDQBnAgAHAAgJUhsiDQBnAgAuAAQKfyoAAwcACQleI6oPAEoDAAcACQleI6oPAEoDABoABAmtD6IHAP8AAAAA.Mary:BAACLgAFFH8RAAIfAAYJpSF5AQC7AQAfAAYJpSF5AQC7AQAuAAQKfxgAAh8ACAnqH7MCAMECAB8ACAnqH7MCAMECAAAA.',
Me='Mechfury:BAAALgADCgEJAgAAAA==.Melitha:BAAALgADCggJCAABLgAECgkJQAAQAGQiAA==.Mero:BAACLgAFFH8SAAMYAAUJ/xZrRAAMAQAYAAQJ+hFrRAAMAQAgAAIJLCCbDQBZAAAuAAQKfyQAAyAACAl1HFsJANkBACAABwlaH1sJANkBABgABwnYFfpmAG0BAAAA.Metal:BAABLgAECn8oAAIhAAgJ5hmOEABdAgAhAAgJ5hmOEABdAgAAAA==.Meyrey:BAAALgADCgYJCwAAAA==.',
Mi='Miorine:BAAALgAECgEJAQABLgAFFAYJJAAJABwiAA==.Mistbehavin:BAACLgAFFH8WAAILAAYJThO6FgBaAQALAAYJThO6FgBaAQAuAAQKfyQAAgsACQlCGfgcABsCAAsACQlCGfgcABsCAAAA.',
Mo='Mog:BAABLgAECn8iAAIBAAcJMyXtGgA9AgABAAcJMyXtGgA9AgAAAA==.Moochese:BAAALgAECgEJAQABLgAECggJGQABACUdAA==.Moostache:BAAALgAECgMJBAAAAA==.',
My='Mytz:BAAALgAECgEJAgAAAA==.',
['Má']='Mátthéw:BAAALgADCgcJCQAAAA==.',
Ne='Nemisai:BAAALgAECgcJDgAAAA==.',
No='Nobody:BAAALgADCgcJBwAAAA==.',
Nu='Nuttinerbutt:BAAALgAFFAMJBAAAAA==.',
Oc='Ochra:BAAALgAECgEJAwAAAA==.',
Og='Ogparadox:BAABLgAECn8UAAIHAAYJLxmXegB8AQAHAAYJLxmXegB8AQAAAA==.',
Ok='Ok:BAABLgAECn8ZAAIKAAgJ7ROkHQCqAQAKAAgJ7ROkHQCqAQAAAA==.',
Or='Orionbtch:BAABLgAECn8iAAIiAAgJEg0VHwCOAQAiAAgJEg0VHwCOAQAAAA==.',
Ov='Overheat:BAACLgAFFH8KAAIHAAMJcRgrcQDvAAAHAAMJcRgrcQDvAAAuAAQKfyAAAgcACQmdH5EXAMUCAAcACQmdH5EXAMUCAAAA.',
Po='Poppy:BAABLgAECn8eAAIHAAgJhgcFmwA+AQAHAAgJhgcFmwA+AQAAAA==.Portinglol:BAABLgAFFH8FAAITAAQJ8hAuGAD+AAATAAQJ8hAuGAD+AAABLgAFFAgJHAAJAGggAA==.',
Ps='Psycilocibin:BAAALgADCgEJAQAAAA==.',
Qu='Qué:BAAALgAECgEJAgAAAA==.',
Qw='Qwiix:BAAALgADCgMJAwAAAA==.Qwixx:BAAALgADCgEJAQAAAA==.',
Ra='Rafikki:BAABLgAECn8UAAIUAAgJ4ReVEADOAQAUAAgJ4ReVEADOAQAAAA==.Ragerok:BAAALgAECgUJBQAAAA==.Ratidari:BAABLgAECn85AAIYAAkJNxbjLAAJAgAYAAkJNxbjLAAJAgAAAA==.Ravenstorm:BAABLgAECn8aAAIjAAYJGxHfPAAOAQAjAAYJGxHfPAAOAQAAAA==.',
Re='Remmîngton:BAABLgAECn88AAMBAAkJwB5mDAC/AgABAAkJwB5mDAC/AgACAAIJCgrLiQEuAAAAAA==.Retbulls:BAAALgAECgcJEAAAAA==.Reverie:BAAALgADCgMJAwAAAA==.',
Rh='Rhynehardt:BAAALgAECgQJBAAAAA==.',
Ri='Riptidedro:BAACLgAFFH8PAAMWAAQJcxxAIwBEAQAWAAQJcxxAIwBEAQAVAAEJ9QA/VgAwAAAuAAQKfyoAAhYACQlgHZ0TAHgCABYACQlgHZ0TAHgCAAAA.',
Ru='Rukaz:BAAALgADCgYJBgAAAA==.Runslikedeer:BAABLgAECn8cAAIdAAgJChrUGwBdAgAdAAgJChrUGwBdAgAAAA==.Runé:BAAALgAECgUJBQABLgAECgYJCwAOAAAAAA==.Rustyarrow:BAAALgAECgEJAQAAAA==.',
Ry='Ryukk:BAABLgAECn8uAAIJAAkJdxaNSgDbAQAJAAkJdxaNSgDbAQAAAA==.',
Sa='Sanoth:BAAALgADCgEJAgAAAA==.Sarana:BAAALgADCgMJAwAAAA==.Sarkhael:BAAALgAECgUJCAAAAA==.',
Se='Sean:BAACLgAFFH8WAAIHAAYJ1RhiMQCQAQAHAAYJ1RhiMQCQAQAuAAQKfyQAAgcACQlwIUkXAB4DAAcACQlwIUkXAB4DAAAA.Secksecute:BAAALgAECgIJBQAAAA==.Seinsleer:BAAALgAECgQJBAAAAA==.Serah:BAAALgAFFAQJBAAAAA==.Seris:BAAALgAECgYJBgABLgAFFAUJCQACANEYAA==.',
Sh='Shel:BAABLgAECn8oAAIYAAkJHwsaYABdAQAYAAkJHwsaYABdAQAAAA==.Sheppy:BAABLgAFFH8FAAICAAUJ2wSiNwAtAQACAAUJ2wSiNwAtAQAAAA==.Shimakaze:BAACLgAFFH8kAAMJAAYJHCLOKACkAQAJAAQJHCbOKACkAQANAAIJGhJhNQBMAAAuAAQKfyIAAgkABwljJNcrAIkCAAkABwljJNcrAIkCAAAA.Shizaam:BAACLgAFFH8WAAMVAAYJOR37GAA8AQAVAAUJsB77GAA8AQAWAAEJ4iBmZABjAAAuAAQKfyQAAxUACQlMI4gFAD4DABUACQlMI4gFAD4DABYAAQkrCXSdADQAAAAA.Shlommy:BAABLgAECn8YAAIPAAgJ5xNRSwC0AQAPAAgJ5xNRSwC0AQAAAA==.',
Si='Siinns:BAACLgAFFH8QAAITAAQJ7h1mCgBqAQATAAQJ7h1mCgBqAQAuAAQKfyoABBMACQnPHb0OAFECABMACQnPHb0OAFECACQABQlXEPNcAOQAAAsAAgnOE0J6AFsAAAAA.Simp:BAAALgAECgIJAgAAAA==.Sinfxl:BAAALgAECgYJCwAAAA==.Sippinsizurp:BAAALgAECggJDwAAAA==.',
Sk='Skadooget:BAAALgADCgYJBgAAAA==.Skullkíng:BAAALgADCgEJAQAAAA==.Skullmages:BAACLgAFFH8QAAICAAQJABgACQBnAQACAAQJABgACQBnAQAuAAQKfxkAAgIABwk3I6QgAKkCAAIABwk3I6QgAKkCAAAA.',
Sl='Slayur:BAABLgAECn8gAAIEAAkJwQ1KKACyAQAEAAkJwQ1KKACyAQAAAA==.Slinkeril:BAABLgAECn8gAAIfAAcJXBRKCgCKAQAfAAcJXBRKCgCKAQAAAA==.Sloppydro:BAAALgAECgYJEAAAAA==.',
Sm='Smackthat:BAAALgAECgQJBgABLgAECgYJDgAOAAAAAA==.Smokey:BAAALgAECgUJCQABLgAECgYJDgAOAAAAAA==.Smokinpurrp:BAAALgAECgQJBAAAAA==.Smoky:BAAALgAECgYJDgAAAA==.',
So='Soju:BAAALgAECgEJBgAAAA==.Sotari:BAAALgADCggJCQAAAA==.',
Sp='Spintowin:BAAALgAECgkJCAAAAA==.Sploosh:BAAALgAECgMJBAAAAA==.',
St='Stabberz:BAACLgAFFH8UAAIfAAQJQBqbAwBYAQAfAAQJQBqbAwBYAQAuAAQKf0kAAx8ACQmfIUMDAHwCAB8ACQmfIUMDAHwCACIABAk8EqhLAM0AAAAA.Stõrmy:BAAALgAECgIJAgAAAA==.',
Su='Sushiroll:BAAALgAFFAEJAQABLgAFFAgJHAAJAGggAA==.',
Sw='Sweetsourrex:BAAALgAFFAEJAQABLgAFFAIJAwAOAAAAAA==.',
Sy='Synkro:BAAALgAECgYJBgABLgAECgYJCwAOAAAAAA==.',
Ta='Tatisjr:BAAALgAECgYJCgAAAA==.',
Te='Temoin:BAAALgAECgEJAgAAAA==.Tempprance:BAAALgAECgQJBAAAAA==.',
Th='Thewordalive:BAAALgADCgIJAgAAAA==.Tholdraz:BAAALgAECgEJAQAAAA==.Thooran:BAAALgAECgIJBwAAAA==.Thrass:BAABLgAECn8gAAIHAAkJ+hH3TwDmAQAHAAkJ+hH3TwDmAQAAAA==.Throngler:BAAALgAECgYJEQABLgAFFAUJCwAPAI8EAA==.',
To='Tohru:BAAALgAECgIJAgABLgAFFAYJJAAJABwiAA==.Toobrunner:BAACLgAFFH8hAAIYAAgJvCGCBQCYAgAYAAgJvCGCBQCYAgAuAAQKfx4AAhgACAlSImUbAK4CABgACAlSImUbAK4CAAAA.Tool:BAACLgAFFH8tAAIYAAkJESVaAABtAwAYAAkJESVaAABtAwAuAAQKfyUAAhgACQmbJSACAGIDABgACQmbJSACAGIDAAAA.',
Tr='Trollz:BAABLgAECn8UAAIXAAgJbQdqEgAvAQAXAAgJbQdqEgAvAQAAAA==.',
Up='Upside:BAAALgAECgIJAwAAAA==.',
Va='Vampress:BAAALgAECgEJAgAAAA==.Varvera:BAAALgADCgMJAwAAAA==.',
Ve='Velannis:BAACLgAFFH8FAAMfAAMJ3h6mCAC1AAAfAAIJURymCAC1AAASAAEJ9yP5DQBoAAAuAAQKfzIAAxIACQl6Iw8BAPsCABIACQk5Iw8BAPsCAB8ABwm9IGoHANkBAAAA.',
Vi='Virikas:BAABLgAECn8kAAMWAAgJABwqHwBJAgAWAAgJABwqHwBJAgAVAAQJKAw5cgCCAAAAAA==.',
Vo='Voidhunter:BAABLgAECn8TAAIYAAgJUxXCWwCOAQAYAAgJUxXCWwCOAQAAAA==.Voodooki:BAABLgAECn88AAIjAAkJ0BRcFgAQAgAjAAkJ0BRcFgAQAgAAAA==.',
Vu='Vuo:BAABLgAECn85AAIlAAgJtRi9NwD0AQAlAAgJtRi9NwD0AQAAAA==.',
Wa='Wayside:BAAALgAECgIJCAAAAA==.',
We='Weedonice:BAAALgAECgcJBQAAAA==.',
Wh='Wheelytank:BAABLgAFFH8MAAICAAQJNw9yRAAVAQACAAQJNw9yRAAVAQAAAA==.White:BAAALgAECgQJBwABLgABCgIJAgAOAAAAAA==.',
Wi='Wickedshaman:BAAALgADCgkJCQABLgAECggJOQAlALUYAA==.Wilburoni:BAAALgADCgIJAgAAAA==.Wiping:BAAALgAECgIJAQABLgAECgcJIgABADMlAA==.',
Xf='Xfreshh:BAAALgAECgYJDQAAAA==.',
Ya='Yamalock:BAABLgAFFH8SAAMPAAUJJxn0PQBBAQAPAAUJJxn0PQBBAQAXAAEJ8QHKKQA0AAAAAA==.Yamamist:BAAALgAECgYJCgABLgAFFAMJBgAHAK4WAA==.Yamå:BAACLgAFFH8GAAIHAAMJrhZoeQDeAAAHAAMJrhZoeQDeAAAuAAQKfxoAAgcABglrIktfAB0CAAcABglrIktfAB0CAAAA.',
Ye='Yeaffa:BAAALgADCgYJBgAAAA==.',
Yi='Yingzhi:BAAALgADCgIJAgAAAA==.',
Za='Zavalu:BAABLgAECn84AAIWAAgJIiHOEQC0AgAWAAgJIiHOEQC0AgAAAA==.',
Ze='Zerosh:BAABLgAECn8xAAIfAAkJJRPRBQAMAgAfAAkJJRPRBQAMAgAAAA==.',
Zi='Zinaida:BAAALgADCggJCAAAAA==.',
Zo='Zortok:BAABLgAECn8hAAIVAAkJcxNoJgCpAQAVAAkJcxNoJgCpAQAAAA==.',
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
