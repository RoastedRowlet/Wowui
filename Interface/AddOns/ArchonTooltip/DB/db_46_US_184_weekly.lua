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

local lookup = {'Evoker-Preservation','Evoker-Augmentation','Druid-Feral','DeathKnight-Blood','DemonHunter-Havoc','Unknown-Unknown','DemonHunter-Devourer','Druid-Guardian','Monk-Brewmaster','Mage-Frost','Paladin-Protection','Warrior-Fury','Rogue-Subtlety','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Unholy','Druid-Restoration','Shaman-Enhancement','Paladin-Holy','Priest-Discipline','Priest-Shadow','Warrior-Protection','Rogue-Assassination','Rogue-Outlaw','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Balance','Shaman-Restoration','Paladin-Retribution','Monk-Windwalker','DeathKnight-Frost','Evoker-Devastation','Monk-Mistweaver','Hunter-Marksmanship','Shaman-Elemental','DemonHunter-Vengeance','Warrior-Arms',}
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=46,date='2026-05-23',data={Ac='Acefu:BAAALgAECgYJDQAAAA==.Acorneo:BAAALgAFFAQJBAABLgAFFAQJDAABALMNAA==.Acornita:BAACLgAFFH8MAAMBAAQJsw1aEQCsAAABAAMJ5w9aEQCsAAACAAIJXwLiRwBoAAAuAAQKfyoAAwEACQnlD0YRACgCAAEACQnlD0YRACgCAAIABwlIEgokAJ0BAAAA.',
Ae='Aelana:BAAALgADCgkJCQAAAA==.',
Ah='Ahyoka:BAAALgAFFAEJAQAAAA==.',
Ai='Ailanthus:BAABLgAECn8cAAIDAAcJwg5dFgArAQADAAcJwg5dFgArAQAAAA==.',
Ak='Akinira:BAECLgAFFH8IAAIEAAQJ5RtlDgBBAQAEAAQJ5RtlDgBBAQAuAAQKfzwAAgQACQmVHqUGAJICAAQACQmVHqUGAJICAAAA.',
Al='Aleinadris:BAAALgADCgQJBAAAAA==.Alikchi:BAAALgADCgEJAgAAAA==.Alloisaber:BAAALgAECgYJCAAAAA==.Alternis:BAAALgAECgMJAwAAAA==.',
An='Andrelsia:BAAALgAECgYJCQAAAA==.Andrilla:BAAALgAECgMJAwAAAA==.Ankeseth:BAAALgAECgUJBQAAAA==.',
Ap='Apôllyon:BAACLgAFFH8OAAIFAAMJASQoCwAqAQAFAAMJASQoCwAqAQAuAAQKfy4AAgUACQmeJfAAAL4DAAUACQmeJfAAAL4DAAAA.',
Ar='Aracelis:BAAALgAECgcJBwAAAA==.Aradius:BAAALgAECgEJAgABLgAECgIJBgAGAAAAAA==.Archertower:BAAALgADCgUJBQAAAA==.Artemiswynd:BAAALgAECgUJBQAAAA==.Arén:BAABLgAECn8jAAMHAAgJsR9KKwD9AQAHAAcJ9h5KKwD9AQAFAAcJhx+YGwDkAQAAAA==.',
As='Ashenshugär:BAAALgAECgQJCAAAAA==.',
Av='Avadda:BAABLgAECn8YAAIIAAcJthE8EgBPAQAIAAcJthE8EgBPAQABLgAECggJHgAJAPgOAA==.',
Az='Azmar:BAABLgAECn8iAAIKAAgJ9x9GKgBUAgAKAAgJ9x9GKgBUAgAAAA==.',
Ba='Badffinger:BAAALgADCgYJBgAAAA==.Balain:BAAALgAECgEJAQABLgAECgcJGgAJAN8NAA==.',
Be='Bearmont:BAABLgAECn8YAAILAAYJxRl0EwBmAQALAAYJxRl0EwBmAQAAAA==.Bearzerk:BAABLgAECn8lAAIMAAkJCBQXHQDhAQAMAAkJCBQXHQDhAQAAAA==.Beastmonk:BAAALgADCgEJAQAAAA==.Benathar:BAABLgAECn8hAAIKAAcJGw4eiQBJAQAKAAcJGw4eiQBJAQAAAA==.',
Bi='Bifrost:BAAALgAECgcJCwAAAA==.Bionico:BAAALgAECgUJDgAAAA==.Birgir:BAAALgAECgUJBwAAAA==.',
Bl='Blackmagék:BAAALgADCgkJCQAAAA==.Blazer:BAAALgAECgUJCAAAAA==.Bloodrager:BAAALgADCgIJAgAAAA==.Bloodthorn:BAABLgAECn8cAAINAAgJJgbNJwApAQANAAgJJgbNJwApAQAAAA==.Blortimor:BAAALgADCgcJBwAAAA==.',
Bo='Bombad:BAAALgAECgYJDQAAAA==.Boomnescient:BAABLgAECn8YAAIOAAYJnwfKiwD1AAAOAAYJnwfKiwD1AAAAAA==.Bortt:BAAALgADCgkJCgAAAA==.Bozscaggs:BAABLgAECn83AAMOAAkJqxCLMgDoAQAOAAkJqxCLMgDoAQAPAAUJAwNMOwC1AAAAAA==.',
Br='Bramis:BAAALgADCgkJHAAAAA==.Brantu:BAAALgADCgQJCAABLgADCgkJDwAGAAAAAA==.Braultus:BAABLgAECn8vAAIEAAkJXx0XCABvAgAEAAkJXx0XCABvAgAAAA==.Breuddwydwr:BAAALgADCgEJAQAAAA==.Breyastrasza:BAAALgADCgMJAwAAAA==.Brood:BAAALgAECgYJBgAAAA==.Bruceleroy:BAAALgAECgEJAQAAAA==.Bruinn:BAAALgAECgQJBAABLgAECgcJGgAJAN8NAA==.',
Bu='Burstangel:BAAALgAECgYJCAAAAA==.',
By='Byrddh:BAAALgADCgQJBAAAAA==.',
Ca='Cadenza:BAAALgAECgMJAwAAAA==.Caelthar:BAAALgAECgUJBQAAAA==.Caliopedk:BAACLgAFFH8HAAMEAAIJrRjTKQBWAAAQAAIJrRjjOACqAAAEAAIJqALTKQBWAAAuAAQKfxsAAxAACAlIIWUhALsCABAACAlIIWUhALsCAAQABQlJDjQqAO0AAAAA.Capra:BAAALgAECgMJAwAAAA==.Carillanklip:BAAALgADCgUJBQAAAA==.',
Cd='Cdmickey:BAAALgADCgUJBQAAAA==.',
Ce='Celestè:BAAALgAECggJEQAAAA==.Celéste:BAAALgAECgkJEAAAAA==.Cerdwin:BAAALgAECggJEAABLgAECgkJNwARAKUWAA==.',
Ch='Charferad:BAAALgAECgMJAwAAAA==.Cheaptrick:BAAALgADCgcJEgAAAA==.Chibeard:BAABLgAECn8iAAIJAAgJeSK+BwCcAgAJAAgJeSK+BwCcAgAAAA==.Chonglin:BAAALgADCgMJAwAAAA==.',
Cl='Clearcast:BAAALgADCgkJCQAAAA==.Clubsdh:BAAALgAECgMJBAAAAA==.',
Co='Coolbro:BAAALgADCgIJAgAAAA==.Corialis:BAAALgAECgkJEgAAAA==.Counsel:BAAALgAECgUJBQAAAA==.',
Cr='Criantha:BAAALgADCgIJAgAAAA==.Crom:BAABLgAECn8wAAISAAgJUg3WEABoAQASAAgJUg3WEABoAQAAAA==.Crosis:BAAALgADCgYJBgAAAA==.Cruelladvoid:BAAALgAECgQJBAAAAA==.Cruush:BAAALgAECgYJBQAAAA==.',
Cu='Culerro:BAAALgAECgYJAwABLgAECgYJBQAGAAAAAA==.Cursive:BAAALgADCgUJDQAAAA==.',
Cy='Cygnes:BAABLgAECn8bAAIQAAgJsBs1PADuAQAQAAgJsBs1PADuAQAAAA==.',
Da='Daddywarrior:BAAALgADCgUJBgAAAA==.Daeva:BAAALgADCgEJAQAAAA==.Dantey:BAAALgADCgcJEgAAAA==.Daus:BAAALgAFFAEJAQAAAA==.Dazanna:BAABLgAECn8vAAMTAAkJaxroCgC7AgATAAkJaxroCgC7AgALAAUJTAtELQCJAAAAAA==.Dazre:BAAALgAECgUJBgAAAA==.',
De='Deeminor:BAAALgADCgkJEwAAAA==.Desktop:BAABLgAECn8xAAMUAAgJHRrCDgBVAgAUAAgJHRrCDgBVAgAVAAUJxg/lPwDmAAAAAA==.',
Di='Diod:BAABLgAECn8sAAIWAAgJERZJFQB4AQAWAAgJERZJFQB4AQAAAA==.Divineßovine:BAAALgADCgcJBwAAAA==.',
Do='Doomtheory:BAAALgADCgQJBAAAAA==.',
Dr='Dracovoid:BAAALgADCgYJBwAAAA==.Dracvoker:BAAALgAECgEJAQABLgAECggJIwAHALEfAA==.Draegyns:BAAALgAECgIJAgABLgAFFAQJDwAXAG0WAA==.Draehton:BAAALgAECgYJBwABLgAFFAQJCwAPAH4XAA==.Dragyns:BAACLgAFFH8PAAIXAAQJbRZiAwBYAQAXAAQJbRZiAwBYAQAuAAQKfy8ABBcACQngG4ECAMoCABcACQmxGYECAMoCAA0ABgmMGz8sAJwBABgAAwmrFFIJANwAAAAA.Dragynseye:BAAALgADCgIJAgABLgAFFAQJDwAXAG0WAA==.Drayper:BAABLgAECn8hAAMZAAgJoRxzCgCaAgAZAAgJoRxzCgCaAgAUAAEJZw3AWQAvAAAAAA==.Druugal:BAACLgAFFH8KAAINAAMJhBorHQD3AAANAAMJhBorHQD3AAAuAAQKfy8AAw0ACQlwH2QKAFoCAA0ACQlwH2QKAFoCABcAAQl6C+ofADMAAAAA.',
Du='Dubs:BAABLgAECn8pAAQaAAkJghoXOQDdAQAaAAYJNRoXOQDdAQAbAAIJ7hkhHgCWAAAcAAIJwxt2KgBKAAAAAA==.Dunbarke:BAAALgAECgcJEQAAAA==.',
Ef='Efishient:BAABLgAECn8eAAIRAAYJWCToHAA7AgARAAYJWCToHAA7AgABLgAFFAYJGQARAH8TAA==.',
El='Elisoria:BAAALgAECgMJAwAAAA==.Elliwynd:BAABLgAECn8qAAIRAAkJvBImIQAcAgARAAkJvBImIQAcAgAAAA==.',
Eo='Eoshot:BAAALgAECgUJCAAAAA==.',
Er='Erinnys:BAABLgAECn8rAAMFAAgJURFyGACHAQAFAAgJURFyGACHAQAHAAYJsgWPlgDvAAAAAA==.Ermoril:BAAALgAECgUJBgAAAA==.Ernesta:BAAALgADCgcJCAAAAA==.Eroksix:BAAALgADCgEJAQAAAA==.',
Eu='Eufemia:BAAALgAECgYJCQAAAA==.',
['Eø']='Eøs:BAAALgAECgEJAQAAAA==.',
Fa='Famine:BAAALgAECgcJDAAAAA==.',
Fe='Felern:BAAALgAECgcJCwABLgAECggJIgAKAPcfAA==.Feyrun:BAAALgADCgkJEwAAAA==.Feyrè:BAAALgADCgQJBQAAAA==.',
Fi='Finalomega:BAAALgAECgYJEAAAAA==.',
Fl='Flaminfalcon:BAABLgAFFH8FAAIVAAIJQBhxHwC6AAAVAAIJQBhxHwC6AAABLgAFFAMJBAAGAAAAAA==.Flody:BAAALgAECgYJDAAAAA==.',
Fo='Foxflame:BAABLgAECn83AAMRAAkJpRZyGwBHAgARAAkJpRZyGwBHAgAdAAgJuw3AJAB2AQAAAA==.',
Fr='Franzen:BAAALgAECgEJAQAAAA==.Freakbob:BAAALgADCgYJCQAAAA==.Froglocky:BAABLgAECn8tAAMcAAgJ7hYJCAC1AQAcAAgJ7hYJCAC1AQAaAAMJcwRi9ABwAAAAAA==.Fronsac:BAAALgADCgQJBAAAAA==.',
Fu='Fulanita:BAABLgAECn8XAAMdAAYJDA4rPgDkAAAdAAYJDA4rPgDkAAARAAIJSwq5qwBGAAAAAA==.',
Ga='Gallager:BAAALgADCgMJAwAAAA==.Garzok:BAABLgAECn8hAAMcAAgJ/wt6DABdAQAcAAgJ/wt6DABdAQAaAAMJzQHnCAFLAAAAAA==.',
Ge='Genkithered:BAABLgAECn8tAAIeAAgJ0hq6GABXAgAeAAgJ0hq6GABXAgAAAA==.',
Gi='Gilaras:BAAALgAECgYJBgAAAA==.Gilernil:BAAALgAECgUJDQAAAA==.',
Gl='Gladtohelp:BAAALgAECgIJAgAAAA==.',
Gn='Gnoquarter:BAAALgADCgIJAgAAAA==.',
Gr='Gravemarks:BAABLgAECn8YAAMYAAgJqBOTBwCdAQAYAAgJqBOTBwCdAQAXAAQJzAncEQDoAAAAAA==.Grimhorn:BAABLgAECn8aAAMdAAYJWQWRVACMAAAdAAUJXQaRVACMAAAIAAIJCAHiYQAWAAAAAA==.Grimlie:BAAALgADCgkJDwAAAA==.Grimmrock:BAAALgAECgMJAwAAAA==.Grumblen:BAAALgADCgMJAwAAAA==.',
Gu='Guaritrice:BAAALgAECgYJDQAAAA==.Gubb:BAAALgAECgMJAwAAAA==.',
Gw='Gwenylane:BAABLgAECn8kAAIfAAkJPQkWZACIAQAfAAkJPQkWZACIAQAAAA==.Gwindor:BAAALgAECgYJCQAAAA==.Gwyndelyn:BAABLgAECn8xAAIgAAgJ9wsMKQBDAQAgAAgJ9wsMKQBDAQAAAA==.',
Ha='Hatterus:BAABLgAECn82AAIfAAkJWQqRZACHAQAfAAkJWQqRZACHAQAAAA==.',
He='Herculeze:BAAALgAFFAEJAQAAAA==.Hessian:BAAALgADCgEJAQAAAA==.Hetairoi:BAAALgAECgIJAgABLgAFFAIJAwAGAAAAAA==.Hetd:BAAALgAECgEJAgAAAA==.',
Hi='Hillbroken:BAABLgAECn9AAAIhAAkJJCLGAQDWAgAhAAkJJCLGAQDWAgAAAA==.',
Ho='Hohalt:BAAALgAECgEJAgAAAA==.Holycross:BAAALgAECgIJAgAAAA==.Holysmokers:BAAALgAECgYJCwABLgAFFAQJDwAXAG0WAA==.Holysnow:BAAALgADCgkJDAABLgAFFAIJAgAGAAAAAA==.Holysoul:BAAALgAECgEJAgAAAA==.',
Hu='Huntertidus:BAAALgAECggJDQABLgAECgkJKgAfAJobAA==.',
['Hà']='Hànks:BAABLgAECn8bAAIfAAgJzw7DZQCEAQAfAAgJzw7DZQCEAQAAAA==.',
Ib='Ibíng:BAAALgAECgYJBgAAAA==.',
Im='Imo:BAABLgAECn8mAAMaAAkJIRH3RAC1AQAaAAkJyQ73RAC1AQAbAAUJIhIxIACEAAAAAA==.',
In='Intrepidz:BAAALgAECgEJAgABLgAFFAMJBAAGAAAAAA==.Inèvitable:BAABLgAECn85AAIQAAkJHh1bHQB2AgAQAAkJHh1bHQB2AgAAAA==.',
Ir='Ironphant:BAAALgAECgUJBQAAAA==.',
Is='Istara:BAAALgADCgkJEAAAAA==.',
Ja='Javeech:BAABLgAECn8lAAMOAAkJcxmvIAA6AgAOAAgJpRuvIAA6AgAPAAEJFQpkVAA5AAAAAA==.',
Je='Jebib:BAAALgAECgYJBgABLgAFFAgJKQARAB0dAA==.Jeod:BAAALgAECgYJCQAAAA==.',
Jo='Jolty:BAACLgAFFH8TAAIQAAQJBSL3IACOAQAQAAQJBSL3IACOAQAuAAQKfykAAxAACQlWIq8MADUDABAACQlWIq8MADUDAAQABAmkFqApANoAAAAA.',
Ju='Julian:BAAALgAECggJCAAAAA==.',
Ka='Kaiou:BAAALgADCgQJCAAAAA==.Kantor:BAABLgAECn9AAAIZAAkJLhiOEQAvAgAZAAkJLhiOEQAvAgAAAA==.Karboomkin:BAAALgAECgcJBwABLgAFFAYJFQAfAGkjAA==.Karnstein:BAABLgAECn8kAAQiAAcJCg2DEADeAAAiAAQJVw+DEADeAAABAAUJgwTuMwDOAAACAAYJvgz+TwDDAAAAAA==.Kasenko:BAAALgAECgIJAgABLgAECgYJEwAGAAAAAA==.Kasryna:BAAALgAECgYJEwAAAA==.Kathinja:BAABLgAECn8lAAIOAAkJhAiLSgCVAQAOAAkJhAiLSgCVAQAAAA==.',
Ke='Kelumbria:BAAALgAECggJDQAAAA==.Keta:BAAALgADCgYJBgAAAA==.Ketameanie:BAABLgAECn8oAAIHAAgJUBgzNQDRAQAHAAgJUBgzNQDRAQAAAA==.',
Ki='Kieran:BAAALgAECgQJCgAAAA==.Kitsunè:BAAALgAECgEJAQAAAA==.',
Km='Kmazing:BAABLgAECn8kAAMgAAkJfA0dHwCNAQAgAAkJfA0dHwCNAQAjAAMJIRBjXQCgAAAAAA==.',
Kn='Knifèparty:BAAALgAECgMJAwAAAA==.',
Ko='Konoha:BAABLgAECn8pAAMUAAkJcR8EBQAaAwAUAAkJZB4EBQAaAwAZAAMJfiPoQwApAQAAAA==.',
Ku='Kultag:BAABLgAECn8YAAIfAAkJfxE3QQDkAQAfAAkJfxE3QQDkAQAAAA==.',
Ky='Kyaw:BAABLgAECn8VAAQNAAYJbRyAKAC2AQANAAYJbRyAKAC2AQAXAAIJxRJbFgCTAAAYAAEJPRQ3HAA7AAAAAA==.Kynzo:BAABLgAECn86AAIDAAkJKR4jAwDDAgADAAkJKR4jAwDDAgAAAA==.',
La='Laykeezenith:BAACLgAFFH8UAAQkAAYJJh0rBwCrAQAkAAYJmxorBwCrAQAOAAMJ7SIWVgCjAAAPAAEJvQc7KQBHAAAuAAQKfx8ABCQACQmZIl4VAIcCACQACAnqIl4VAIcCAA4ACAm9IdwsAAACAA8AAgl3EgooAHUAAAAA.Lazuli:BAABLgAECn86AAIlAAgJpRZNIAC0AQAlAAgJpRZNIAC0AQAAAA==.',
Le='Lehann:BAABLgAECn8rAAIOAAkJxw9fOgDKAQAOAAkJxw9fOgDKAQAAAA==.',
Li='Lichtech:BAAALgAECgYJDQABLgAFFAYJGwACAB8fAA==.Lightsbane:BAAALgAECgYJBgAAAA==.',
Lu='Luciselda:BAAALgADCgUJBgAAAA==.Lunariah:BAAALgADCgkJEwAAAA==.Luvtarhugar:BAAALgADCgMJAwAAAA==.',
Ma='Madaran:BAAALgADCgEJAQABLgAECgUJCwAGAAAAAA==.Magdalene:BAEALgAECgUJCQABLgAFFAQJDQAcAKoRAA==.Marenus:BAABLgAECn8+AAIOAAkJOxFSOADSAQAOAAkJOxFSOADSAQAAAA==.Masume:BAAALgAECgYJCAAAAA==.Maély:BAAALgAECgEJAgAAAA==.',
Me='Mechadead:BAAALgADCgIJAgAAAA==.Medal:BAAALgADCgYJCAAAAA==.Meowmix:BAAALgADCgcJDAAAAA==.',
Mi='Miantha:BAAALgAECgYJBwAAAA==.Michi:BAABLgAECn8wAAIRAAkJgyJDAwB6AwARAAkJgyJDAwB6AwAAAA==.Midnights:BAAALgAECggJEAAAAA==.Mightymopo:BAAALgADCgMJAwAAAA==.Mikuki:BAABLgAECn8jAAIOAAkJvCNwDADKAgAOAAkJvCNwDADKAgAAAA==.Milkinghands:BAABLgAECn8hAAMjAAkJ1g/+LAB7AQAjAAkJ1g/+LAB7AQAgAAEJlAL+lAAjAAAAAA==.Mizmonk:BAACLgAFFH8XAAIJAAUJEhviFABGAQAJAAUJEhviFABGAQAuAAQKfyIAAgkACQnxHqMJAO4CAAkACQnxHqMJAO4CAAAA.',
Mj='Mjölnir:BAAALgAECgEJAQAAAA==.',
Mo='Montfort:BAAALgADCggJDwAAAA==.Moovover:BAAALgAECggJCgAAAA==.',
Ms='Msmaho:BAAALgAECgMJAwAAAA==.',
Mu='Murionor:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgAECgYJBgAAAA==.',
My='Mykian:BAABLgAECn8pAAMiAAkJAQcdDgALAQACAAkJ0QTxNgArAQAiAAcJ1QcdDgALAQAAAA==.Myrwynn:BAAALgAECgMJAwABLgAECggJNQAVAHEZAA==.Mythlee:BAAALgAECgQJBAAAAA==.Mythundon:BAAALgADCgUJBQAAAA==.',
Na='Nahion:BAAALgAECgYJCQAAAA==.Nashira:BAABLgAECn8gAAIOAAkJVBM7LwD2AQAOAAkJVBM7LwD2AQAAAA==.Nathalas:BAAALgAECgEJAgAAAA==.Nature:BAAALgAECgUJCwAAAA==.',
Ne='Necrana:BAAALgADCgEJAQAAAA==.Necrobyarg:BAAALgAECgYJDQAAAA==.Nemasus:BAABLgAECn8tAAIRAAgJrB0oEgCcAgARAAgJrB0oEgCcAgAAAA==.Nembie:BAAALgADCgMJAwAAAA==.Nethertech:BAAALgAECgMJAwABLgAFFAYJGwACAB8fAA==.',
Ni='Ninjahh:BAACLgAFFH8GAAINAAUJUAakGwACAQANAAUJUAakGwACAQAuAAQKfyMAAg0ACAnaFYoUANcBAA0ACAnaFYoUANcBAAAA.Nioshei:BAABLgAECn82AAIeAAgJGBYiIQAbAgAeAAgJGBYiIQAbAgAAAA==.Nisara:BAACLgAFFH8FAAIjAAMJHBKaJwC4AAAjAAMJHBKaJwC4AAAuAAQKfzAAAyMACQndHq8NAIwCACMACQndHq8NAIwCACAABwm3H3kPACoCAAAA.',
No='Nochmuerta:BAABLgAECn8ZAAIQAAkJRRnKIABjAgAQAAkJRRnKIABjAgAAAA==.Nogrid:BAABLgAECn9AAAILAAkJ1xlZBgBXAgALAAkJ1xlZBgBXAgAAAA==.Nossaria:BAAALgAECgIJAgAAAA==.Notmyface:BAAALgAECgcJEwABLgAECgcJLwAMACkmAA==.',
Nu='Nuthar:BAABLgAECn8xAAIfAAcJ4CQfHwBuAgAfAAcJ4CQfHwBuAgAAAA==.',
Ny='Nyxandra:BAAALgAECgMJAwAAAA==.',
['Nò']='Nòhva:BAAALgAECgQJBAAAAA==.',
Ol='Oldeis:BAAALgAECgEJAQAAAA==.',
Om='Ominousowl:BAAALgAFFAMJBAAAAA==.',
Or='Oregizm:BAAALgAFFAEJAQAAAA==.Orneryosprey:BAAALgAECgMJAwABLgAFFAIJAwAGAAAAAA==.',
Pa='Pamburu:BAABLgAECn8jAAQOAAgJ8w00YgBUAQAOAAgJpg00YgBUAQAkAAYJvgVxGwCxAAAPAAIJrQUPKgBgAAAAAA==.Papagrape:BAABLgAECn84AAQBAAgJcCKwAgAYAwABAAgJcCKwAgAYAwAiAAIJAhJ4GgBaAAACAAEJUgyAYgAyAAAAAA==.Parzivàl:BAABLgAECn8mAAITAAgJehiaEwB1AgATAAgJehiaEwB1AgAAAA==.Paxa:BAABLgAECn8jAAMZAAcJKh1UFgD3AQAZAAcJKh1UFgD3AQAVAAQJgwr+UQCUAAAAAA==.',
Pe='Peacebox:BAAALgADCggJDAABLgAECgkJJAAgAHwNAA==.Persayis:BAAALgAECgMJAwAAAA==.',
Ph='Phoebel:BAAALgADCgkJEgAAAA==.Phoenixbodhi:BAAALgAECgQJBAAAAA==.',
Pi='Pickledeggs:BAAALgAECgEJAQABLgAECggJEgAGAAAAAA==.',
Po='Podnov:BAACLgAFFH8VAAMkAAQJkiCbCQCBAQAkAAQJkiCbCQCBAQAOAAIJpB1MXQCXAAAuAAQKfyMAAiQACQlEHcwNANYCACQACQlEHcwNANYCAAAA.Pollyanna:BAAALgADCgEJAQAAAA==.',
Pr='Preyon:BAAALgAECgUJEAABLgAECgcJGgAJAN8NAA==.',
Py='Pyne:BAAALgADCgEJAQAAAA==.Pyrista:BAAALgAECgkJDAAAAA==.',
Qo='Qotho:BAABLgAECn8/AAIOAAkJYhveHABPAgAOAAkJYhveHABPAgAAAA==.',
Ra='Raikou:BAAALgAECgUJBQABLgAFFAYJHAAVAH8iAA==.Raistliin:BAAALgAECgYJDgAAAA==.Raithis:BAACLgAFFH8XAAIOAAUJLx0+IQBEAQAOAAUJLx0+IQBEAQAuAAQKfzEAAg4ACQl4IcAEAEEDAA4ACQl4IcAEAEEDAAAA.Raito:BAAALgADCgUJBQAAAA==.Ramhadin:BAEALgAECgMJBwABLgAECggJJQAVAPoZAA==.',
Re='Rednaxel:BAABLgAECn82AAMNAAgJPyPTBgCcAgANAAgJPyPTBgCcAgAXAAUJdBkMCQCPAQAAAA==.Redvelvet:BAABLgAECn8nAAMjAAkJqBVwFgApAgAjAAkJqBVwFgApAgAgAAQJ9Ab5WwCgAAAAAA==.Rekoner:BAABLgAECn8jAAIQAAkJNBF8QADfAQAQAAkJNBF8QADfAQAAAA==.Resi:BAAALgAECgIJAgAAAA==.Resii:BAAALgAECgEJAgABLgAECgIJAgAGAAAAAA==.Retarganator:BAABLgAECn9AAAMHAAkJyByDFACCAgAHAAkJLByDFACCAgAmAAQJjBjREgAlAQAAAA==.',
Ri='Ringmistress:BAAALgADCgcJBwAAAA==.Rixaa:BAAALgADCgQJBQABLgAECgcJFQAOAJwXAA==.',
Ro='Rocks:BAAALgAECgYJCAAAAA==.Romam:BAAALgAECgYJCQAAAA==.',
Ru='Rubyknight:BAAALgAECgEJAQAAAA==.',
Ry='Rydran:BAAALgAECgQJBQAAAA==.Rykria:BAAALgADCgkJHgAAAA==.',
Sa='Samsonknight:BAAALgADCgYJBgAAAA==.Sanguinarian:BAABLgAECn8XAAIfAAgJIQ2jjQA1AQAfAAgJIQ2jjQA1AQAAAA==.Savash:BAAALgAECggJEAAAAA==.',
Sc='Scrubtotem:BAAALgAECgMJAwAAAA==.',
Se='Secksiecutie:BAABLgAECn8vAAMhAAkJIBphBQAhAgAhAAgJJBxhBQAhAgAEAAcJPQxSJgDyAAAAAA==.Selanda:BAAALgADCgkJHQAAAA==.Serinar:BAAALgAECgUJDwAAAA==.',
Sh='Shoshin:BAABLgAECn8aAAMJAAcJ3w39QgDSAAAJAAcJ3w39QgDSAAAgAAQJJgxhXQCbAAAAAA==.Shïvana:BAAALgAECgMJDwAAAA==.',
Si='Silversaiyan:BAABLgAECn9AAAMMAAgJqSF6DQBzAgAMAAgJqSF6DQBzAgAnAAEJXRiEOgBGAAAAAA==.',
Sl='Slade:BAABLgAECn82AAMNAAkJPCOhAwDvAgANAAkJPCOhAwDvAgAXAAMJ9xoXEgDfAAAAAA==.Slap:BAAALgAECgEJAQAAAA==.Sliyce:BAAALgAECgIJBgAAAA==.',
Sm='Smóke:BAABLgAECn9AAAIHAAkJjBTSLwDnAQAHAAkJjBTSLwDnAQAAAA==.',
Sn='Snore:BAAALgADCgMJAwAAAA==.Snowfawn:BAABLgAECn8fAAIOAAYJDxQ5ZQBMAQAOAAYJDxQ5ZQBMAQABLgAFFAIJAgAGAAAAAA==.',
So='Sofedan:BAABLgAECn9AAAIkAAkJ4w6LCgCeAQAkAAkJ4w6LCgCeAQAAAA==.Sorgath:BAAALgAECgIJAgAAAA==.Soriel:BAABLgAECn8eAAIJAAgJ+A6FJABpAQAJAAgJ+A6FJABpAQAAAA==.Sorokwa:BAABLgAECn8XAAIQAAkJKgK00wC1AAAQAAkJKgK00wC1AAAAAA==.',
Sq='Squids:BAAALgADCgQJBAAAAA==.',
St='Strongstork:BAAALgAECgEJAgABLgAFFAIJAwAGAAAAAA==.',
Su='Sunsword:BAAALgAECgYJEQAAAA==.Suriden:BAAALgAECgYJBwAAAA==.',
Sw='Swagidan:BAABLgAECn8sAAIFAAgJoxgAEgBMAgAFAAgJoxgAEgBMAgAAAA==.Sweatermonk:BAAALgADCgIJAgABLgAECgYJBgAGAAAAAA==.Sweaterpally:BAAALgAECgYJBgAAAA==.Swiftera:BAABLgAECn8iAAITAAkJZhWEKADqAQATAAkJZhWEKADqAQAAAA==.Swiftlier:BAABLgAECn8qAAIJAAkJgxmWEgAAAgAJAAkJgxmWEgAAAgAAAA==.Swipegirl:BAAALgAECgYJCQAAAA==.',
Sy='Sybelyyia:BAAALgAECgEJAQAAAA==.Sylphrène:BAABLgAECn8pAAIFAAkJ8AbSHwA+AQAFAAkJ8AbSHwA+AQAAAA==.',
Ta='Taladan:BAAALgAECgQJBQAAAA==.Tandrana:BAAALgAECgMJBAAAAA==.Tankmepapi:BAAALgAECgMJAwAAAA==.Tanwen:BAAALgAECgYJEAAAAA==.Targypunch:BAAALgADCgcJBwABLgAECgkJQAAHAMgcAA==.Tatsunoshinn:BAAALgADCgEJAQAAAA==.',
Te='Techniqe:BAACLgAFFH8bAAMCAAYJHx8WDgCrAQACAAYJHx8WDgCrAQABAAEJrwGJJgA1AAAuAAQKfzQAAwIACAkkIxsHAAoDAAIACAkkIxsHAAoDACIABgkgIe8SALMBAAAA.Techtides:BAAALgADCgUJBQABLgAFFAYJGwACAB8fAA==.Temperance:BAAALgADCgEJAQAAAA==.Temptations:BAAALgAECgUJBgAAAA==.Terminus:BAAALgAECgIJAgAAAA==.Terrylin:BAAALgAECgYJBwAAAA==.',
Th='Thaliá:BAAALgADCgkJFQAAAA==.Themachinist:BAAALgAECgYJBgAAAA==.Thomag:BAAALgADCgIJAgAAAA==.',
Ti='Tiaracy:BAAALgAECgEJAQAAAA==.Ticebane:BAACLgAFFH8OAAMEAAQJ8QizGgDUAAAEAAQJ8QizGgDUAAAQAAIJfwG1wQBuAAAuAAQKfyMAAgQACQk0GbALAFgCAAQACQk0GbALAFgCAAAA.Tiduspullo:BAABLgAECn8qAAMfAAkJmhuTRAAWAgAfAAkJdxWTRAAWAgALAAUJoRq+FABUAQAAAA==.Tiduswar:BAABLgAECn8fAAMWAAcJ2BpSFgCqAQAWAAcJ2BpSFgCqAQAMAAIJfRKabQByAAABLgAECgkJKgAfAJobAA==.Tinafay:BAAALgAECgcJDAAAAA==.Titanbeard:BAAALgAECgEJAwAAAA==.Titor:BAABLgAECn8jAAMBAAcJJRmJCwD7AQABAAcJJRmJCwD7AQAiAAUJeQ4MEQDWAAAAAA==.Tituspullo:BAAALgAECgcJCgABLgAECgkJKgAfAJobAA==.',
To='Tolduan:BAAALgAECgUJDQAAAA==.Totemik:BAAALgAECgUJCwAAAA==.Toughturkey:BAAALgAFFAIJAwAAAA==.Towen:BAAALgADCgMJAwAAAA==.Toy:BAAALgADCgYJDAAAAA==.',
Tr='Tremorhoof:BAAALgADCgIJAwAAAA==.Tresera:BAAALgADCgEJAQAAAA==.Tricarnetry:BAABLgAECn8VAAIfAAcJKQh/pQANAQAfAAcJKQh/pQANAQAAAA==.Trufleshufle:BAAALgAECggJEQAAAA==.',
Uh='Uhtread:BAAALgADCgYJBQAAAA==.',
Ul='Ulfer:BAAALgAECgIJAgABLgAECgkJQQAEANokAA==.',
Un='Unholyfury:BAAALgADCgYJBgAAAA==.',
Va='Vapor:BAAALgAECgQJBQAAAA==.Vaquinha:BAAALgADCgUJBQAAAA==.Varyel:BAAALgAECgIJAgAAAA==.',
Ve='Velianne:BAAALgADCgUJBQAAAA==.Vellinada:BAAALgADCgMJAwAAAA==.Verakis:BAABLgAECn82AAIWAAgJzxVQEAC7AQAWAAgJzxVQEAC7AQAAAA==.Verndarí:BAABLgAECn8XAAMEAAkJwQxhGQBkAQAEAAkJwQxhGQBkAQAhAAMJzgVfIQBrAAABLgAECgkJKgAJAIMZAA==.Vervain:BAAALgAECgUJBQAAAA==.',
Vo='Vonnie:BAAALgADCgkJCQAAAA==.Vortheus:BAAALgAECgQJCgAAAA==.Votollis:BAAALgAECgQJBQAAAA==.',
Wa='Warlanen:BAAALgAECgUJBgAAAA==.Warning:BAAALgADCgUJBQAAAA==.Warpiggies:BAAALgADCgkJCAAAAA==.',
Wi='Widdy:BAAALgAECgcJEAAAAA==.Willbur:BAABLgAECn9AAAIKAAkJpxjrKQBWAgAKAAkJpxjrKQBWAgAAAA==.Wittledwagon:BAAALgADCgkJCQAAAA==.',
Wu='Wurthwhile:BAAALgAECgYJDgAAAA==.',
Wy='Wylaniris:BAAALgADCgQJBAAAAA==.Wyndywalker:BAABLgAECn8lAAIdAAgJZQeONAAUAQAdAAgJZQeONAAUAQAAAA==.',
Xa='Xaveil:BAAALgADCgEJAQAAAA==.',
Xe='Xenosian:BAAALgAECgkJCQAAAA==.',
Xi='Xinnuo:BAAALgAECgQJBAAAAA==.',
Xy='Xydias:BAAALgAECggJDwAAAA==.Xyra:BAAALgADCgcJBwAAAA==.',
Yo='Yoku:BAAALgAECggJEwAAAA==.',
Za='Zag:BAAALgAECgEJAQABLgAECgkJMAAmALYWAA==.Zalgarian:BAAALgAECgMJAwAAAA==.Zamønk:BAABLgAECn8ZAAMJAAcJFg8WOABqAQAJAAcJFg8WOABqAQAgAAIJ+wx6bgBXAAAAAA==.Zaphoidvtwo:BAAALgADCgcJBwAAAA==.Zason:BAAALgADCgMJAwAAAA==.Zatari:BAAALgADCgMJAwAAAA==.',
Ze='Zelectie:BAABLgAECn8XAAIIAAgJbhcyCgD3AQAIAAgJbhcyCgD3AQABLgAFFAYJCwAEAHYSAA==.Zelzaikin:BAAALgAECgQJBgAAAA==.Zevon:BAAALgAECgYJBgAAAA==.',
Zi='Ziarra:BAAALgADCgYJBgABLgADCgcJDQAGAAAAAA==.Zinazarinara:BAAALgADCgkJFwAAAA==.Zirril:BAAALgADCgcJDwAAAA==.',
Zo='Zombiechick:BAAALgAECgMJBAAAAA==.Zorn:BAAALgAECgMJAwAAAA==.',
['ßr']='ßrigitte:BAAALgADCgkJEQAAAA==.',
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
