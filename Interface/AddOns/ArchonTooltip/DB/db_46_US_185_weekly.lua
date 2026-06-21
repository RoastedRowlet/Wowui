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

local lookup = {'Warlock-Destruction','Warlock-Demonology','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','Unknown-Unknown','Warrior-Fury','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','Paladin-Protection','Hunter-Survival','Monk-Brewmaster','DeathKnight-Blood','Priest-Shadow','Warrior-Arms','Evoker-Devastation','Monk-Windwalker','Druid-Guardian','Shaman-Elemental','Shaman-Restoration','Warrior-Protection','Warlock-Affliction','Druid-Restoration','Rogue-Outlaw','DemonHunter-Devourer','Monk-Mistweaver','Mage-Arcane','Mage-Fire','Druid-Feral','Priest-Holy','Rogue-Assassination','DemonHunter-Vengeance','Priest-Discipline','Rogue-Subtlety','Druid-Balance','Hunter-BeastMastery',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abeblinkin:BAAALgAECgcJDAAAAA==.Aborlight:BAAALgAECgUJDwAAAA==.',
Ad='Adit:BAABLgAECn8XAAMBAAgJyxA2DgBZAQABAAgJyxA2DgBZAQACAAYJjwqjtQDbAAAAAA==.Adug:BAAALgADCgMJAwAAAA==.',
Ae='Aedrius:BAABLgAECn8ZAAMDAAcJLhjINQClAQADAAYJrRnINQClAQAEAAQJlxECwQAFAQAAAA==.',
Ag='Agnekie:BAABLgAECn8XAAIEAAcJqRcbZgCjAQAEAAcJqRcbZgCjAQAAAA==.',
Ai='Aiwass:BAABLgAECn9SAAIBAAkJJBToBgDuAQABAAkJJBToBgDuAQAAAA==.Aiyo:BAABLgAFFH8GAAMFAAIJxAqP6wB+AAAFAAIJxAqP6wB+AAAGAAEJOgvlJwBGAAABLgAFFAQJBAAHAAAAAA==.',
Al='Alexander:BAAALgAECgMJAwAAAA==.Alpharius:BAAALgAECgUJCAAAAA==.',
Am='Amathricus:BAABLgAECn8zAAIEAAkJkg7SYACvAQAEAAkJkg7SYACvAQAAAA==.Amerika:BAAALgADCgIJAgAAAA==.',
Ar='Arawak:BAAALgADCgEJAQAAAA==.',
As='Ashuk:BAABLgAECn8fAAIIAAYJtggHXADiAAAIAAYJtggHXADiAAAAAA==.',
At='Athena:BAAALgAECgMJAwAAAA==.',
Au='Augtism:BAECLgAFFH8KAAMJAAUJgA+hGQD8AAAJAAQJ1Q+hGQD8AAAKAAQJgAq3OwDYAAAuAAQKfx0AAwoABwmfHrMgANQBAAoABwmfHrMgANQBAAkAAgm2Ef0tAHsAAAEuAAUUBQkKAAkAgA8A.Auitou:BAAALgAECggJCQAAAA==.Auralei:BAABLgAECn8iAAILAAgJGgkLmgBFAQALAAgJGgkLmgBFAQAAAA==.',
Az='Azelia:BAAALgAECggJEwABLgAECgkJKgADADoVAA==.Azzy:BAABLgAECn8qAAQDAAkJOhXuJQDYAQADAAgJpRfuJQDYAQAMAAMJLgK4SgBAAAAEAAIJ9gGztQEoAAAAAA==.',
Ba='Bacta:BAAALgADCgUJBQAAAA==.',
Be='Beasti:BAAALgAECgIJAgAAAA==.Beelzebul:BAAALgAFFAQJBAABLgAFFAYJKwAFADsiAA==.',
Bi='Bigb:BAABLgAECn8mAAINAAcJKSYEBQDEAgANAAcJKSYEBQDEAgAAAA==.Bigpaladin:BAAALgADCgEJAQAAAA==.',
Bl='Black:BAAALgAECgUJCQAAAA==.',
Bo='Bombaclat:BAAALgADCgEJAQAAAA==.Boor:BAAALgAECgcJCAAAAA==.',
Br='Brilline:BAAALgAECgYJBwAAAA==.Brochese:BAAALgAECgYJCwABLgAECgkJJQADAEMdAA==.Broka:BAAALgAECgMJAwAAAA==.',
Bu='Bubblewrap:BAAALgAECgcJDwABLgAFFAcJFwAOAMoRAA==.Buwumkin:BAAALgAECgUJCwABLgAECggJDQAHAAAAAA==.',
['Bò']='Bònz:BAAALgADCgQJBQAAAA==.',
Ca='Cadaverous:BAACLgAFFH8IAAIGAAMJIBt7EQAIAQAGAAMJIBt7EQAIAQAuAAQKfxQAAwYACQnWGnQEAIQCAAYACQnWGnQEAIQCAA8AAgnmCUVXAEAAAAAA.Canadianguy:BAAALgAECgEJAQABLgAECgcJDAAHAAAAAA==.',
Ch='Cheyeon:BAAALgAECgYJBgAAAA==.Chonk:BAAALgADCgkJCwAAAA==.Chunguskhan:BAACLgAFFH8FAAIQAAMJfRKQIwDZAAAQAAMJfRKQIwDZAAAuAAQKfxYAAhAACQlQGiENAIECABAACQlQGiENAIECAAAA.',
Cl='Classcarry:BAAALgADCgYJBgABLgAFFAgJHAAFAGggAA==.Claybigsby:BAACLgAFFH8VAAMCAAcJkRRSUAAmAQACAAUJIhlSUAAmAQABAAIJbwuPIQBSAAAuAAQKfx4AAwEACQlPGxADAMoCAAEACAm5HRADAMoCAAIABwlwFq5xAHwBAAAA.Clif:BAACLgAFFH8JAAMRAAQJhAvfIgDlAAARAAQJhAvfIgDlAAAIAAIJxAd2SQB+AAAuAAQKfxkAAwgACAmqHNwWAJYCAAgACAmqHNwWAJYCABEAAQl+HSNrAEsAAAAA.',
Co='Cosmiccosmo:BAAALgAECgQJCQAAAA==.',
Cr='Crippledlady:BAAALgAECggJDQAAAA==.',
Cu='Cucurbita:BAAALgADCgYJBgAAAA==.',
Cy='Cyndre:BAAALgADCgEJAQAAAA==.',
Da='Dargon:BAABLgAECn8XAAMKAAgJ3yNnBgAZAwAKAAgJ3yNnBgAZAwASAAYJ7hzSGwBSAQABLgAFFAUJCQAEANEYAA==.',
De='Deadlylady:BAAALgAECgUJBQAAAA==.Deadlyorc:BAAALgAECgIJAQAAAA==.Deaf:BAAALgAFFAEJAQABLgAFFAMJBgAOAOAdAA==.Delphine:BAAALgADCgYJBgAAAA==.Demonblade:BAAALgADCgEJAQAAAA==.Demonifrita:BAAALgADCgkJCQAAAA==.Demoniosushi:BAAALgAECgMJBwABLgAECgYJDgAHAAAAAA==.Demonmane:BAAALgADCgMJAwAAAA==.Derpy:BAABLgAECn8sAAMTAAgJbhEmJgCEAQATAAgJbhEmJgCEAQAOAAgJ+wMoRADqAAAAAA==.',
Di='Dippindotz:BAAALgAECgEJAgABLgAFFAgJHAAFAGggAA==.',
Dj='Djheals:BAAALgAECgQJBQAAAA==.',
Do='Doobiedruid:BAAALgAFFAIJAgAAAA==.Doobiemage:BAAALgAECgEJAgAAAA==.Dorenis:BAAALgAECgEJAgAAAA==.',
Dr='Drachese:BAAALgAECgEJAQABLgAECgkJJQADAEMdAA==.Droopox:BAABLgAECn8eAAIUAAkJBQlaLgD0AAAUAAkJBQlaLgD0AAAAAA==.Druchese:BAAALgAECgcJDAABLgAECgkJJQADAEMdAA==.',
['Dö']='Döx:BAAALgAECgYJBgABLgAFFAcJFwALAEYWAA==.',
Ea='Eagleeye:BAABLgAECn8lAAIEAAgJOhCUgwBoAQAEAAgJOhCUgwBoAQAAAA==.',
Em='Emsley:BAACLgAFFH8TAAIVAAQJmAt5LADjAAAVAAQJmAt5LADjAAAuAAQKf0gAAhUACQmkF4gjAMoBABUACQmkF4gjAMoBAAAA.',
Er='Eri:BAACLgAFFH8QAAIWAAMJEx64OwD0AAAWAAMJEx64OwD0AAAuAAQKfycAAhYABgmHIvcpABQCABYABgmHIvcpABQCAAAA.Erised:BAAALgAECgMJAwAAAA==.',
Ev='Ev:BAABLgAFFH8GAAIOAAMJ4B0nAwDDAAAOAAMJ4B0nAwDDAAAAAA==.',
Ex='Exo:BAACLgAFFH8XAAILAAcJRhYjPAB8AQALAAcJRhYjPAB8AQAuAAQKfx8AAgsACAkrIjYgAPMCAAsACAkrIjYgAPMCAAAA.',
Fe='Felrid:BAAALgAECgYJBgABLgAFFAUJCQAEANEYAA==.',
Fl='Floudruid:BAAALgADCgMJAwABLgABCgcJBwAHAAAAAA==.',
Fo='Focalors:BAAALgAFFAIJBAABLgAFFAYJKwAFADsiAA==.Foobear:BAACLgAFFH8XAAIUAAcJeBGMCwA7AQAUAAcJeBGMCwA7AQAuAAQKfywAAhQACQlyIL8FAKwCABQACQlyIL8FAKwCAAAA.Fozzy:BAABLgAECn8YAAIKAAgJpgeoUQDoAAAKAAgJpgeoUQDoAAAAAA==.Fozél:BAAALgAECgEJAQAAAA==.',
Fr='Franchescold:BAABLgAECn8gAAIFAAkJLxxbNwAhAgAFAAkJLxxbNwAhAgAAAA==.Franfran:BAABLgAECn8fAAILAAkJdA+WZwCtAQALAAkJdA+WZwCtAQAAAA==.Freasey:BAABLgAECn8fAAIEAAcJXg6XrgAhAQAEAAcJXg6XrgAhAQAAAA==.Frostbeard:BAAALgADCgQJBwAAAA==.',
Fu='Furiousfoo:BAABLgAECn8ZAAQXAAYJxBcWHABWAQAXAAYJuRcWHABWAQAIAAUJCRFsXADgAAARAAMJ5AmcLQCIAAABLgAFFAcJFwAUAHgRAA==.Furlock:BAABLgAECn8jAAMYAAgJuB8KAwCQAgAYAAgJuB8KAwCQAgACAAYJPRfLhwAqAQAAAA==.',
Ga='Gabriel:BAAALgAECgcJCAAAAA==.Galicia:BAAALgAECgYJBgAAAA==.Gantaris:BAABLgAECn8UAAIZAAcJcQlGAwB4AAAZAAcJcQlGAwB4AAAAAA==.',
Ge='Gengiskaan:BAAALgAECgYJCgAAAA==.',
Gi='Gir:BAAALgAECgcJEgAAAA==.Gixian:BAAALgAECgYJEAAAAA==.',
Go='Gochese:BAABLgAECn8lAAMDAAkJQx1mCgDlAgADAAkJQx1mCgDlAgAEAAcJehDdAgAlAQAAAA==.',
Gr='Gramid:BAACLgAFFH8JAAIEAAUJ0RhqRgAfAQAEAAUJ0RhqRgAfAQAuAAQKfxoAAgQACAlpJnceAI8CAAQACAlpJnceAI8CAAAA.Greenseer:BAABLgAECn8vAAICAAcJ0xeJTAC1AQACAAcJ0xeJTAC1AQAAAA==.Grognag:BAAALgAECgYJDgAAAA==.',
Gt='Gtoffmydh:BAAALgADCgIJAgAAAA==.',
Gw='Gwaralmighty:BAACLgAFFH8YAAIIAAUJcR+GAQBPAQAIAAUJcR+GAQBPAQAuAAQKfzYAAggACQlfIOcOAIUCAAgACQlfIOcOAIUCAAAA.',
Gy='Gypo:BAAALgAECgYJCwAAAA==.',
Ha='Haagen:BAAALgAECgUJDwAAAA==.Haagoon:BAAALgAECgQJBgAAAA==.Haagoonus:BAAALgAECgEJAQAAAA==.Halfwolf:BAAALgADCgQJBAAAAA==.Hatch:BAACLgAFFH8FAAIaAAMJwiFkCAD5AAAaAAMJwiFkCAD5AAAuAAQKfx0AAhoABwmCJR0BAPMCABoABwmCJR0BAPMCAAEuAAUUAwkGAA4A4B0A.',
Hh='Hholdem:BAAALgAECgQJBAABLgAECgkJKQATAC8PAA==.',
Hi='Hightones:BAACLgAFFH8PAAIbAAcJegfxPQAvAQAbAAcJegfxPQAvAQAuAAQKfyUAAhsACAk2IEoWANECABsACAk2IEoWANECAAAA.Him:BAAALgAECgYJBgAAAA==.',
Ho='Holdêm:BAABLgAECn8pAAITAAkJLw9CJACQAQATAAkJLw9CJACQAQAAAA==.Holeytoast:BAAALgAECgQJBAABLgAFFAcJFwAVAOccAA==.Hollee:BAABLgAECn8UAAIcAAcJPgiNBACpAAAcAAcJPgiNBACpAAABLgAFFAUJGwAWALIWAA==.Horsdoeuvres:BAAALgAECgkJEAAAAA==.',
Hu='Humberto:BAAALgAECgEJAQAAAA==.Hung:BAAALgAECgYJCwAAAA==.',
Ic='Icylady:BAAALgAECgYJCwAAAA==.',
If='Ifrita:BAACLgAFFH8JAAMLAAMJDglOkQC1AAALAAMJEAZOkQC1AAAdAAEJ4QoMBwBCAAAuAAQKf08ABAsACQl4G9kgAJsCAAsACQl4G9kgAJsCAB0ABgkjE6oHAIYBAB4AAQm1CdQVACgAAAAA.Ifrite:BAABLgAECn8lAAMGAAkJsxLPCQDmAQAGAAkJSBHPCQDmAQAFAAgJeQ7FfgCGAQAAAA==.',
Ik='Ikur:BAABLgAECn8ZAAMJAAgJERFVFgBpAQAJAAcJkBFVFgBpAQAKAAcJ0Ae0UQDoAAABLgAFFAQJDwADAK8bAA==.',
Im='Imbasoul:BAABLgAFFH8HAAICAAUJpQLlBQDuAAACAAUJpQLlBQDuAAAAAA==.Imyerchese:BAAALgADCgYJBgABLgAECgkJJQADAEMdAA==.',
It='Itita:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneill:BAACLgAFFH8NAAIEAAMJxAd6gQCzAAAEAAMJxAd6gQCzAAAuAAQKfyUAAgQACQnjECdvAJABAAQACQnjECdvAJABAAAA.',
Je='Jezlana:BAAALgAECgcJCwAAAA==.',
Ji='Jillidan:BAAALgAECgIJAwAAAA==.',
Jo='Johnnynapalm:BAAALgAECgIJBAABLgAECgQJBAAHAAAAAA==.Jonnycraig:BAAALgAECgEJAgAAAA==.Jormi:BAABLgAECn9CAAMRAAkJ1iOdAgAeAwARAAkJ1iOdAgAeAwAXAAMJlyGGJQAGAQAAAA==.',
Ka='Kabaayi:BAAALgADCgEJAQAAAA==.Kaihu:BAAALgAECgMJAwAAAA==.Kalthael:BAAALgADCgkJGAAAAA==.Kamilliara:BAAALgAECgEJAQAAAA==.Kasura:BAABLgAECn8sAAMfAAkJTRsUCwAMAgAfAAgJAx0UCwAMAgAZAAcJdA68gwDQAAAAAA==.Katakuri:BAAALgAECgEJAgAAAA==.',
Kh='Kharahealer:BAABLgAECn8UAAIgAAcJIhfRNABrAQAgAAcJIhfRNABrAQAAAA==.',
Kl='Kllausy:BAAALgAECgIJAwAAAA==.',
Ko='Kochese:BAAALgAECgEJAQABLgAECgkJJQADAEMdAA==.Kolto:BAAALgAECgEJAQAAAA==.',
Kr='Krayt:BAAALgAECgEJBgAAAA==.',
Kw='Kwrr:BAAALgADCgYJBgABLgAFFAgJJgACAEslAA==.',
La='Lambo:BAABLgAECn8eAAIVAAgJDSDlEQBhAgAVAAgJDSDlEQBhAgAAAA==.',
Le='Leafhoof:BAAALgAECgEJAQAAAA==.Leonna:BAAALgAECgIJAgAAAA==.Lexidia:BAAALgADCgUJBQAAAA==.Leynnar:BAAALgAECgUJDwAAAA==.',
Li='Licha:BAAALgAECgcJBQAAAA==.',
Lo='Lockme:BAABLgAFFH8KAAICAAQJshHVaQDxAAACAAQJshHVaQDxAAAAAA==.Lothiriel:BAAALgAECgcJDAAAAA==.Loveyuling:BAAALgAECgEJBAABLgAECgQJBwAHAAAAAA==.',
Lu='Lunk:BAAALgAECgEJAwAAAA==.',
Ly='Lynel:BAAALgAECgEJAgAAAA==.',
['Ló']='Lóvecandy:BAAALgAECgQJBwAAAA==.',
Ma='Maruzensky:BAACLgAFFH8yAAILAAgJUhtQEwBUAgALAAgJUhtQEwBUAgAuAAQKfyoAAwsACQleI6oPAEoDAAsACQleI6oPAEoDAB4ABAmtD6IHAP8AAAAA.Mary:BAACLgAFFH8ZAAIhAAgJnyKzAAA+AgAhAAgJnyKzAAA+AgAuAAQKfxkAAiEACAnqH7MCAMECACEACAnqH7MCAMECAAAA.',
Me='Mechfury:BAAALgADCgEJAgAAAA==.Melitha:BAAALgADCggJCAABLgAECgkJQgARANYjAA==.Mero:BAACLgAFFH8TAAMbAAUJ/xbGTAAEAQAbAAQJ+hHGTAAEAQAiAAIJLCCMDwBXAAAuAAQKfyQAAyIACAl1HFsJANkBACIABwlaH1sJANkBABsABwnYFfpmAG0BAAAA.Metal:BAABLgAECn8pAAIjAAgJAhq5EQBaAgAjAAgJAhq5EQBaAgAAAA==.Meyrey:BAAALgADCgYJCwAAAA==.',
Mi='Miorine:BAAALgAECgEJAQABLgAFFAYJKwAFADsiAA==.Mistbehavin:BAACLgAFFH8XAAIOAAcJyhEKGgBUAQAOAAcJyhEKGgBUAQAuAAQKfyUAAg4ACQlCGfgcABsCAA4ACQlCGfgcABsCAAAA.',
Mo='Mog:BAABLgAECn8iAAIDAAcJMyXtGgA9AgADAAcJMyXtGgA9AgAAAA==.Moochese:BAAALgAECgYJCgABLgAECgkJJQADAEMdAA==.Moostache:BAAALgAECgMJBAAAAA==.',
My='Mytz:BAAALgAECgcJCQAAAA==.',
['Má']='Mátthéw:BAAALgADCgkJDAAAAA==.',
Ne='Nemisai:BAAALgAECggJEAAAAA==.',
No='Nobody:BAAALgADCgcJBwAAAA==.',
Nu='Nuttinerbutt:BAABLgAFFH8GAAIEAAMJXAXmiQCeAAAEAAMJXAXmiQCeAAAAAA==.',
Oc='Ochra:BAAALgAECgEJAwAAAA==.',
Og='Ogparadox:BAABLgAECn8UAAILAAYJLxkagAB3AQALAAYJLxkagAB3AQAAAA==.',
Ok='Ok:BAABLgAECn8ZAAINAAgJ7ROpHwCfAQANAAgJ7ROpHwCfAQAAAA==.',
Or='Orionbtch:BAABLgAECn8iAAIkAAgJEg35IACOAQAkAAgJEg35IACOAQAAAA==.',
Ov='Overheat:BAACLgAFFH8NAAILAAMJeBuJdgDuAAALAAMJeBuJdgDuAAAuAAQKfyAAAgsACQmdH4wZAMACAAsACQmdH4wZAMACAAAA.',
Po='Poppy:BAABLgAECn8eAAILAAgJhgdAowA2AQALAAgJhgdAowA2AQAAAA==.Portinglol:BAABLgAFFH8FAAITAAQJ8hB0GwDwAAATAAQJ8hB0GwDwAAABLgAFFAgJHAAFAGggAA==.',
Ps='Psycilocibin:BAAALgADCgEJAQAAAA==.',
Qu='Qué:BAAALgAECgEJAgAAAA==.',
Qw='Qwiix:BAAALgADCgMJAwAAAA==.Qwixx:BAAALgADCgEJAQAAAA==.',
Ra='Rafikki:BAABLgAECn8VAAIUAAkJphclEgDOAQAUAAkJphclEgDOAQAAAA==.Ragerok:BAAALgAECgUJBQAAAA==.Ratidari:BAABLgAECn88AAIbAAkJ8RZWKgAgAgAbAAkJ8RZWKgAgAgAAAA==.Ravenstorm:BAABLgAECn8jAAIlAAYJUhREOQAuAQAlAAYJUhREOQAuAQAAAA==.',
Re='Remmîngton:BAABLgAECn9AAAMDAAkJwB5kDQC8AgADAAkJwB5kDQC8AgAEAAMJ1wwSSQFkAAAAAA==.Retbulls:BAABLgAECn8XAAIEAAkJZiADDwDuAgAEAAkJZiADDwDuAgAAAA==.Reverie:BAAALgADCgMJAwAAAA==.',
Rh='Rhynehardt:BAAALgAECgQJBAAAAA==.',
Ri='Rip:BAABLgAFFH8FAAINAAIJEhRcKACUAAANAAIJEhRcKACUAAABLgAFFAMJEAAWABMeAA==.Riptidedro:BAACLgAFFH8UAAMWAAUJpR0FGACmAQAWAAUJpR0FGACmAQAVAAEJ9QD5YQApAAAuAAQKfyoAAhYACQlgHZ0TAHgCABYACQlgHZ0TAHgCAAAA.',
Ru='Rukaz:BAAALgADCgYJBgAAAA==.Runslikedeer:BAABLgAECn8gAAIZAAkJExoHHQBeAgAZAAkJExoHHQBeAgAAAA==.Runé:BAAALgAECgcJCAAAAA==.Rustyarrow:BAAALgAECgEJAQAAAA==.',
Ry='Ryan:BAAALgAECgUJCwAAAA==.Ryukk:BAABLgAECn8uAAIFAAkJdxYGUADTAQAFAAkJdxYGUADTAQAAAA==.',
Sa='Sanoth:BAAALgAECgEJAQAAAA==.Sarana:BAAALgADCgMJAwAAAA==.Sarkhael:BAAALgAECgUJCAAAAA==.',
Se='Sean:BAACLgAFFH8XAAILAAcJqBbvOwB9AQALAAcJqBbvOwB9AQAuAAQKfyUAAgsACQlwIUkXAB4DAAsACQlwIUkXAB4DAAAA.Secksecute:BAAALgAECgIJBQAAAA==.Seinsleer:BAAALgAECgQJBAABLgAECgUJCwAHAAAAAA==.Serah:BAAALgAFFAQJBAAAAA==.Seris:BAAALgAECgYJBgABLgAFFAUJCQAEANEYAA==.',
Sh='Shel:BAABLgAECn8oAAIbAAkJHwsDZQBdAQAbAAkJHwsDZQBdAQAAAA==.Sheppy:BAABLgAFFH8GAAIEAAYJjgXjQQAnAQAEAAYJjgXjQQAnAQAAAA==.Shimakaze:BAACLgAFFH8rAAMFAAYJOyLPAgCjAQAFAAQJQybPAgCjAQAPAAIJGhIZOwBKAAAuAAQKfyIAAgUABwljJNcrAIkCAAUABwljJNcrAIkCAAAA.Shizaam:BAACLgAFFH8XAAMVAAcJ5xzVHQAuAQAVAAYJAh7VHQAuAQAWAAEJ4iA0bgBhAAAuAAQKfyQAAxUACQlMI4gFAD4DABUACQlMI4gFAD4DABYAAQkrCXSdADQAAAAA.Shlommy:BAABLgAECn8YAAICAAgJ5xNDUACqAQACAAgJ5xNDUACqAQAAAA==.',
Si='Siinns:BAACLgAFFH8QAAITAAQJ7h2TDABeAQATAAQJ7h2TDABeAQAuAAQKfyoABBMACQnPHbEPAE8CABMACQnPHbEPAE8CABwABQlaEMddAP8AAA4AAgnOE0J6AFsAAAAA.Simp:BAAALgAECgIJAgAAAA==.Sinfxl:BAAALgAECgYJDgABLgAECgcJCAAHAAAAAA==.Sippinsizurp:BAAALgAECggJDwAAAA==.',
Sk='Skadooget:BAAALgADCgYJBgAAAA==.Skullkíng:BAAALgADCgEJAQAAAA==.Skullmages:BAACLgAFFH8QAAIEAAQJABgACQBnAQAEAAQJABgACQBnAQAuAAQKfxkAAgQABwk3I6QgAKkCAAQABwk3I6QgAKkCAAAA.',
Sl='Slayur:BAABLgAECn8gAAIIAAkJwQ3SKwClAQAIAAkJwQ3SKwClAQAAAA==.Slinkeril:BAABLgAECn8hAAIhAAgJaxTFCgCIAQAhAAgJaxTFCgCIAQAAAA==.Sloppydro:BAAALgAECgcJEQAAAA==.',
Sm='Smackthat:BAAALgAECgQJBgABLgAECgYJDgAHAAAAAA==.Smokey:BAAALgAECgUJCQABLgAECgYJDgAHAAAAAA==.Smokinpurrp:BAAALgAECgQJBAAAAA==.Smoky:BAAALgAECgYJDgAAAA==.',
So='Soju:BAAALgAECgEJBgAAAA==.Sotari:BAAALgADCggJCQAAAA==.',
Sp='Spintowin:BAAALgAECgkJCAAAAA==.Sploosh:BAAALgAECgYJCgAAAA==.',
St='Stabberz:BAACLgAFFH8UAAIhAAQJQBoXBABNAQAhAAQJQBoXBABNAQAuAAQKf0kAAyEACQmfIX8DAHoCACEACQmfIX8DAHoCACQABAk8EqhLAM0AAAAA.Stõrmy:BAAALgAECgIJAgAAAA==.',
Su='Sushiroll:BAAALgAFFAEJAQABLgAFFAgJHAAFAGggAA==.',
Sw='Sweetsourrex:BAAALgAFFAQJBAAAAA==.',
Sy='Synkro:BAAALgAECgYJCwABLgAECgcJCAAHAAAAAA==.',
Ta='Tatisjr:BAAALgAECgYJCgAAAA==.',
Te='Temoin:BAAALgAECgEJBAAAAA==.Tempprance:BAAALgAECgQJBAAAAA==.',
Th='Thelasthope:BAAALgAECgQJBAAAAA==.Thewordalive:BAAALgADCgIJAgAAAA==.Tholdraz:BAAALgAECgEJAQAAAA==.Thooran:BAAALgAECgIJBwAAAA==.Thrass:BAABLgAECn8gAAILAAkJ+hH4VQDbAQALAAkJ+hH4VQDbAQAAAA==.Throngler:BAAALgAECgYJEQABLgAFFAUJEQACAIkGAA==.',
To='Tohru:BAAALgAECgIJAgABLgAFFAYJKwAFADsiAA==.Toobrunner:BAACLgAFFH8nAAIbAAgJgCImBgCxAgAbAAgJgCImBgCxAgAuAAQKfx4AAhsACAlSImUbAK4CABsACAlSImUbAK4CAAAA.Tool:BAACLgAFFH8vAAIbAAkJESXIAABYAwAbAAkJESXIAABYAwAuAAQKfyUAAhsACQmbJXoCAGADABsACQmbJXoCAGADAAAA.',
Tr='Trollz:BAABLgAECn8bAAIYAAgJqRHFCQDGAQAYAAgJqRHFCQDGAQAAAA==.',
Up='Upside:BAAALgAECgIJAwAAAA==.',
Va='Vampress:BAAALgAECgQJBQAAAA==.Varvera:BAAALgADCgMJAwAAAA==.',
Ve='Velannis:BAACLgAFFH8FAAMhAAMJ3h5dCQCxAAAhAAIJURxdCQCxAAAaAAEJ9yOODwBmAAAuAAQKfzIAAxoACQl6IycBAPsCABoACQk5IycBAPsCACEABwm9INAHANcBAAAA.',
Vi='Virikas:BAABLgAECn8kAAMWAAgJABxpIQBHAgAWAAgJABxpIQBHAgAVAAQJKAwyeQCCAAAAAA==.',
Vo='Voidhunter:BAABLgAECn8TAAIbAAgJUxXCWwCOAQAbAAgJUxXCWwCOAQAAAA==.Voodooki:BAABLgAECn9BAAIlAAkJHRd6EwA5AgAlAAkJHRd6EwA5AgAAAA==.',
Vu='Vuo:BAABLgAECn8/AAImAAkJ6RasOwDxAQAmAAkJ6RasOwDxAQAAAA==.',
Wa='Wayside:BAAALgAECgkJCAAAAA==.',
We='Weedonice:BAAALgAECgcJBQAAAA==.',
Wh='Wheelytank:BAABLgAFFH8SAAIEAAUJQhZ8QAAqAQAEAAUJQhZ8QAAqAQAAAA==.White:BAAALgAECgQJBwABLgABCgIJAgAHAAAAAA==.',
Wi='Wickedshaman:BAAALgADCgkJCQABLgAECgkJPwAmAOkWAA==.Wilburoni:BAAALgADCgIJAgAAAA==.Wiping:BAAALgAECgIJAQABLgAECgcJIgADADMlAA==.',
Xf='Xfreshh:BAAALgAECgYJDQAAAA==.',
Xn='Xnomorp:BAAALgAECgQJBAAAAA==.',
Ya='Yamalock:BAABLgAFFH8TAAMCAAUJJxkGRwA6AQACAAUJJxkGRwA6AQAYAAEJ8QGHLgAzAAAAAA==.Yamamist:BAAALgAECgYJCgABLgAFFAMJBgALAK4WAA==.Yamå:BAACLgAFFH8GAAILAAMJrhYygwDRAAALAAMJrhYygwDRAAAuAAQKfxoAAgsABglrIktfAB0CAAsABglrIktfAB0CAAAA.',
Ye='Yeaffa:BAAALgADCgYJBgAAAA==.',
Yi='Yingzhi:BAAALgAECgUJBQAAAA==.',
Za='Zavalu:BAABLgAECn84AAIWAAgJIiFXEwCxAgAWAAgJIiFXEwCxAgAAAA==.',
Ze='Zerosh:BAABLgAECn8xAAIhAAkJJRMnBgAKAgAhAAkJJRMnBgAKAgAAAA==.',
Zi='Zinaida:BAAALgADCggJCAAAAA==.',
Zo='Zortok:BAABLgAECn8hAAIVAAkJcxPrKACoAQAVAAkJcxPrKACoAQAAAA==.',
Zu='Zugszy:BAAALgAECgYJCwAAAA==.',
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
