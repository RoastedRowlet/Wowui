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

local lookup = {'Monk-Windwalker','Monk-Mistweaver','Evoker-Preservation','Evoker-Augmentation','Druid-Feral','DeathKnight-Blood','DemonHunter-Havoc','Unknown-Unknown','DemonHunter-Devourer','Druid-Guardian','Monk-Brewmaster','Mage-Frost','Paladin-Protection','Warrior-Fury','Warrior-Arms','Warlock-Affliction','Rogue-Subtlety','Warrior-Protection','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Unholy','Druid-Restoration','Shaman-Enhancement','Paladin-Holy','Priest-Discipline','Priest-Shadow','Rogue-Assassination','Rogue-Outlaw','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Druid-Balance','Shaman-Restoration','Paladin-Retribution','DeathKnight-Frost','Evoker-Devastation','Hunter-Marksmanship','Shaman-Elemental','DemonHunter-Vengeance',}
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=46,date='2026-06-06',data={Ac='Acefu:BAABLgAECn8WAAIBAAgJeSLxBwC/AgABAAgJeSLxBwC/AgAAAA==.Acornella:BAAALgAECgQJBAABLgAFFAYJBwACAK4GAA==.Acorneo:BAABLgAFFH8HAAICAAYJrgaGIwAiAQACAAYJrgaGIwAiAQAAAA==.Acornita:BAACLgAFFH8MAAMDAAQJsw1aEQCsAAADAAMJ5w9aEQCsAAAEAAIJXwJ+VgBjAAAuAAQKfyoAAwMACQnlD0YRACgCAAMACQnlD0YRACgCAAQABwlIEgokAJ0BAAEuAAUUBgkHAAIArgYA.',
Ad='Adoreith:BAAALgAECgEJAQAAAA==.',
Ae='Aelana:BAAALgADCgkJCQAAAA==.Aeria:BAAALgADCgYJBgAAAA==.Aeriith:BAAALgAECgEJAQAAAA==.',
Ah='Ahyoka:BAAALgAFFAEJAgAAAA==.',
Ai='Ailanthus:BAABLgAECn8cAAIFAAcJwg5eGwAdAQAFAAcJwg5eGwAdAQAAAA==.',
Ak='Akinira:BAECLgAFFH8QAAIGAAQJ5Rv+FAAtAQAGAAQJ5Rv+FAAtAQAuAAQKfz4AAgYACQmVHlsIAIgCAAYACQmVHlsIAIgCAAAA.',
Al='Aleinadris:BAAALgADCgQJBAAAAA==.Alendy:BAAALgAECgYJBgAAAA==.Alikchi:BAAALgADCgEJAgAAAA==.Alloisaber:BAAALgAECgYJCAAAAA==.Alternis:BAAALgAECgMJAwAAAA==.Alunne:BAAALgAECgEJAQAAAA==.',
An='Andrelsia:BAAALgAECgYJCQAAAA==.Andrilla:BAAALgAECgYJCQAAAA==.Ankeseth:BAAALgAECgcJCAAAAA==.',
Ap='Apôllyon:BAACLgAFFH8OAAIHAAMJASQUEAAQAQAHAAMJASQUEAAQAQAuAAQKfy4AAgcACQmeJfAAAL4DAAcACQmeJfAAAL4DAAAA.',
Ar='Aracelis:BAAALgAECgcJBwAAAA==.Aradius:BAAALgAECgEJAgABLgAECgIJBgAIAAAAAA==.Archertower:BAAALgADCgUJBQAAAA==.Artemiswynd:BAAALgAECgUJCAAAAA==.Arén:BAABLgAECn8pAAMJAAkJch/sFQCLAgAJAAkJMB3sFQCLAgAHAAcJhx+YGwDkAQAAAA==.',
As='Ashenshugär:BAAALgAECgQJCAAAAA==.',
Av='Avadda:BAABLgAECn8YAAIKAAcJthE8EgBPAQAKAAcJthE8EgBPAQABLgAECgkJKAALADsPAA==.',
Az='Azmar:BAABLgAECn8xAAIMAAgJ3yFwGwCvAgAMAAgJ3yFwGwCvAgAAAA==.',
Ba='Badffinger:BAAALgADCgYJCQAAAA==.Badtouchbull:BAAALgADCgcJBwAAAA==.Balain:BAAALgAECgQJBAABLgAECgcJGgALAN8NAA==.Bayorn:BAAALgAECgYJBwAAAA==.',
Be='Bear:BAAALgADCgcJBwAAAA==.Bearmont:BAABLgAECn8gAAINAAcJ+Bd7EgCTAQANAAcJ+Bd7EgCTAQAAAA==.Bearzerk:BAABLgAECn8mAAIOAAkJCBTNIgDWAQAOAAkJCBTNIgDWAQAAAA==.Beastmonk:BAAALgADCgEJAQAAAA==.Benathar:BAABLgAECn8oAAIMAAkJJw3gXQC/AQAMAAkJJw3gXQC/AQAAAA==.',
Bi='Bifrost:BAAALgAECgcJCwAAAA==.Bionico:BAABLgAECn8YAAIPAAYJpxOMJwAnAQAPAAYJpxOMJwAnAQAAAA==.Birgir:BAAALgAECgUJCAABLgAECgcJGAAQAHIgAA==.',
Bl='Blackmagék:BAAALgADCgkJCQAAAA==.Bladestormer:BAAALgADCgIJAQAAAA==.Blazer:BAAALgAFFAIJBAAAAA==.Bloodrager:BAAALgADCgIJAgAAAA==.Bloodthorn:BAABLgAECn8cAAIRAAgJJgbILQAfAQARAAgJJgbILQAfAQAAAA==.Blortimor:BAAALgADCgcJBwAAAA==.',
Bo='Bombad:BAABLgAECn8UAAQOAAgJchLkKwCdAQAOAAgJPhLkKwCdAQASAAMJNgsFPAB0AAAPAAEJdQysdAAsAAAAAA==.Boomnescient:BAABLgAECn8dAAITAAcJhAdeiAAhAQATAAcJhAdeiAAhAQAAAA==.Bortt:BAAALgAECgIJAgAAAA==.Bozscaggs:BAABLgAECn9IAAMTAAkJkBNRLwAUAgATAAkJkBNRLwAUAgAUAAUJAwPyQQCxAAAAAA==.',
Br='Bramis:BAAALgADCgkJHAAAAA==.Brantu:BAAALgADCgQJCAABLgADCgkJDwAIAAAAAA==.Braultus:BAABLgAECn8vAAIGAAkJXx2CCgBfAgAGAAkJXx2CCgBfAgAAAA==.Breuddwydwr:BAAALgADCgEJAQAAAA==.Breyastrasza:BAAALgADCgMJAwAAAA==.Brood:BAAALgAECgYJCgAAAA==.Bruceleroy:BAAALgAECgEJAQAAAA==.Bruinn:BAAALgAECgQJBAABLgAECgcJGgALAN8NAA==.',
Bu='Burstangel:BAAALgAECgYJCAAAAA==.',
By='Byrddh:BAAALgADCgQJBAAAAA==.',
['Bä']='Bäguette:BAAALgADCgEJAgAAAA==.',
Ca='Cadenza:BAAALgAECgYJCgAAAA==.Caelthar:BAAALgAECgUJCAAAAA==.Caliopedk:BAACLgAFFH8HAAMGAAIJrRjQNABPAAAVAAIJrRjjOACqAAAGAAIJqALQNABPAAAuAAQKfxsAAxUACAlIIWUhALsCABUACAlIIWUhALsCAAYABQlJDjQqAO0AAAAA.Caliseni:BAAALgADCgYJCwAAAA==.Capra:BAAALgAECgYJCAAAAA==.Carillanklip:BAAALgADCgUJBQAAAA==.',
Cd='Cdmickey:BAAALgADCgUJBQAAAA==.',
Ce='Celestè:BAAALgAECggJEQAAAA==.Celéste:BAAALgAECgkJEAAAAA==.Cerdwin:BAAALgAECggJEQABLgAECgkJPgAWABkXAA==.',
Ch='Charferad:BAAALgAECgUJCAAAAA==.Chatter:BAAALgADCgMJAwAAAA==.Cheaptrick:BAAALgADCgcJEwAAAA==.Chibeard:BAABLgAECn8nAAILAAkJtSJOAwAZAwALAAkJtSJOAwAZAwAAAA==.Chihîro:BAAALgADCgkJCQAAAA==.Chonglin:BAAALgADCgMJAwAAAA==.Chrysopteron:BAAALgAECgEJAQABLgAECgEJAQAIAAAAAA==.',
Cl='Clearcast:BAAALgADCgkJCQAAAA==.Clevercrane:BAAALgAFFAIJAgABLgAFFAMJBQAEAFgYAA==.Clubsdh:BAAALgAECgMJBAAAAA==.',
Co='Coolbro:BAAALgADCgIJAgABLgADCggJCAAIAAAAAA==.Corialis:BAAALgAFFAEJAQAAAA==.Counsel:BAAALgAECgUJBQAAAA==.',
Cr='Criantha:BAAALgADCgIJAgAAAA==.Crom:BAABLgAECn8zAAIXAAkJ4g+jDQDKAQAXAAkJ4g+jDQDKAQAAAA==.Crosis:BAAALgADCgYJBgAAAA==.Cruelladvoid:BAAALgAECgQJBAAAAA==.Cruush:BAAALgAECgYJBQAAAA==.',
Cu='Culerro:BAAALgAECgYJAwABLgAECgYJBQAIAAAAAA==.Cursive:BAAALgADCgUJDQAAAA==.',
Cy='Cygnes:BAABLgAECn8iAAIVAAkJUxy6IwBuAgAVAAkJUxy6IwBuAgAAAA==.',
Da='Daddywarrior:BAAALgADCgUJBgAAAA==.Daeva:BAAALgADCgEJAQAAAA==.Dantey:BAAALgADCgcJFAAAAA==.Daus:BAAALgAFFAEJAQAAAA==.Dazanna:BAABLgAECn82AAMYAAkJPxz6CQDhAgAYAAkJPxz6CQDhAgANAAUJTAslMwCJAAAAAA==.Dazre:BAAALgAECgUJBgAAAA==.',
De='Deeminor:BAAALgADCgkJEwAAAA==.Demeisen:BAAALgAECgMJAwAAAA==.Desktop:BAABLgAECn87AAMZAAkJUBzCBwDxAgAZAAkJUBzCBwDxAgAaAAYJdRGaNwAuAQAAAA==.',
Di='Digon:BAAALgAECgEJAQAAAA==.Diod:BAABLgAECn9AAAISAAkJHRUYEQDKAQASAAkJHRUYEQDKAQAAAA==.Divineßovine:BAAALgADCgcJBwAAAA==.',
Do='Doombarker:BAAALgADCgYJBgAAAA==.Doomtheory:BAAALgAECgMJAwAAAA==.Dorammu:BAAALgAECgEJAQAAAA==.',
Dr='Dracovoid:BAAALgADCgYJBwAAAA==.Dracvoker:BAAALgAECgQJCAABLgAECgkJKQAJAHIfAA==.Draegyns:BAAALgAECgIJAgABLgAFFAYJEQAbALgSAA==.Draehton:BAAALgAECgYJBwABLgAFFAQJCwAUAH4XAA==.Dragyns:BAACLgAFFH8RAAMbAAYJuBJ+BAA+AQAbAAQJbRZ+BAA+AQARAAIJ6APdNgBNAAAuAAQKfzEABBsACQngG4ECAMoCABsACQmxGYECAMoCABEABgmMGz8sAJwBABwAAwmrFFIJANwAAAAA.Dragynseye:BAAALgADCgIJAgABLgAFFAYJEQAbALgSAA==.Drayper:BAABLgAECn8rAAMdAAkJYB8yBQAhAwAdAAkJYB8yBQAhAwAZAAEJZw3AWQAvAAAAAA==.Druugal:BAACLgAFFH8OAAIRAAQJGhpUFQBSAQARAAQJGhpUFQBSAQAuAAQKfy8AAxEACQlwH0YMANQCABEACQlwH0YMANQCABsAAQl6C+ofADMAAAAA.',
Du='Dubs:BAABLgAECn8wAAQeAAkJ6hq3PQDfAQAeAAYJwBq3PQDfAQAfAAIJ7hmhIQCWAAAQAAIJwxt2KgBKAAAAAA==.Dunbarke:BAABLgAECn8YAAIQAAcJciC3BwDiAQAQAAcJciC3BwDiAQAAAA==.Dustrat:BAAALgADCgIJAgAAAA==.',
Ef='Efishient:BAABLgAECn8eAAIWAAYJWCTdHgBIAgAWAAYJWCTdHgBIAgABLgAFFAYJGQAWAH8TAA==.',
El='Elisoria:BAAALgAECgMJAwAAAA==.Elliwynd:BAABLgAECn8uAAIWAAkJGRRuIAA6AgAWAAkJGRRuIAA6AgAAAA==.',
Eo='Eoshot:BAAALgAECgUJCAAAAA==.',
Er='Erinnys:BAABLgAECn8yAAMHAAkJAxPbEwDlAQAHAAkJAxPbEwDlAQAJAAYJsgWPlgDvAAAAAA==.Ermoril:BAAALgAECgUJBgAAAA==.Ernesta:BAAALgADCgcJCAAAAA==.Eroksix:BAAALgADCgEJAQAAAA==.',
Eu='Eufemia:BAAALgAECgYJCQAAAA==.',
['Eø']='Eøs:BAAALgAECgEJAQAAAA==.',
Fa='Famine:BAAALgAECgcJDAAAAA==.',
Fe='Feelmebro:BAAALgADCggJCAAAAA==.Felern:BAAALgAECgcJCwABLgAECggJMQAMAN8hAA==.Feyrun:BAAALgADCgkJEwABLgAECgEJAQAIAAAAAA==.Feyrè:BAAALgAECgEJAgAAAA==.',
Fi='Finalomega:BAAALgAECgYJEwAAAA==.Finnshot:BAAALgAECgEJAQAAAA==.',
Fl='Flaminfalcon:BAABLgAFFH8FAAIaAAIJQBjVJgCpAAAaAAIJQBjVJgCpAAABLgAFFAMJBQAEAFgYAA==.Flody:BAAALgAECgYJDAAAAA==.',
Fo='Foxflame:BAABLgAECn8+AAMWAAkJGReLHgBIAgAWAAkJGReLHgBIAgAgAAgJPhAbJgCPAQAAAA==.',
Fr='Franzen:BAAALgAECgQJBQAAAA==.Freakbob:BAAALgADCgYJCQAAAA==.Froglocky:BAABLgAECn8/AAMQAAkJ+RZ7BQAgAgAQAAkJ+RZ7BQAgAgAeAAMJcwRi9ABwAAAAAA==.Fronsac:BAAALgADCgQJBAAAAA==.',
Fu='Fulanita:BAABLgAECn8XAAMgAAYJDA5jRgDkAAAgAAYJDA5jRgDkAAAWAAIJSwoBuwBEAAAAAA==.',
Ga='Gallager:BAAALgADCgMJAwAAAA==.Garzok:BAABLgAECn8qAAMQAAkJXwyYCgCkAQAQAAkJXwyYCgCkAQAeAAMJzQHnCAFLAAAAAA==.',
Ge='Genkithered:BAABLgAECn81AAIhAAkJoxzCDADnAgAhAAkJoxzCDADnAgAAAA==.',
Gi='Gilaras:BAAALgAECgYJBgAAAA==.Gilernil:BAAALgAECgUJDQAAAA==.',
Gl='Gladtohelp:BAAALgAECgIJAgAAAA==.',
Gn='Gnoquarter:BAAALgADCgIJAgAAAA==.',
Go='Gourak:BAAALgADCgEJAgAAAA==.',
Gr='Gravemarks:BAABLgAECn8YAAMcAAgJqBPACACaAQAcAAgJqBPACACaAQAbAAQJzAncEQDoAAAAAA==.Grimhorn:BAABLgAECn8iAAMgAAYJYghYWQCfAAAgAAUJAAlYWQCfAAAKAAIJWQOSbwAnAAAAAA==.Grimlie:BAAALgADCgkJDwAAAA==.Grimmrock:BAAALgAECgUJCAAAAA==.Grumblen:BAAALgADCgMJAwAAAA==.',
Gu='Guaritrice:BAABLgAECn8UAAMaAAcJJwp0OwAcAQAaAAcJJwp0OwAcAQAdAAEJYQfDdAAfAAAAAA==.Gubb:BAAALgAECgMJAwAAAA==.',
Gw='Gwenylane:BAABLgAECn8sAAIiAAkJSAvibACJAQAiAAkJSAvibACJAQAAAA==.Gwindor:BAAALgAECgYJCQAAAA==.Gwyndelyn:BAABLgAECn8xAAIBAAgJ9wvDMAA3AQABAAgJ9wvDMAA3AQAAAA==.',
Ha='Hatterus:BAABLgAECn9EAAIiAAkJTg0AYgCiAQAiAAkJTg0AYgCiAQAAAA==.',
He='Herculeze:BAAALgAFFAIJBAAAAA==.Hessian:BAAALgADCgEJAQAAAA==.Hetairoi:BAAALgAECgIJAgABLgAFFAMJCQABAF0hAA==.Hetd:BAAALgAECgEJAwABLgAFFAMJCQABAF0hAA==.',
Hi='Hillbroken:BAABLgAECn9QAAIjAAkJqSL9AQDzAgAjAAkJqSL9AQDzAgAAAA==.',
Ho='Hohalt:BAAALgAECgEJAgAAAA==.Holycross:BAAALgAECgIJAgAAAA==.Holysmokers:BAAALgAECgYJDAABLgAFFAYJEQAbALgSAA==.Holysnow:BAAALgADCgkJDAABLgAFFAIJBAAIAAAAAA==.Holysoul:BAAALgAECgEJAwAAAA==.',
Hu='Huntertidus:BAAALgAECggJDQABLgAECgkJKgAiAJobAA==.Huntrix:BAAALgAECgYJBgAAAA==.',
Hy='Hydan:BAAALgADCgIJAgAAAA==.',
['Hà']='Hànks:BAABLgAECn8gAAIiAAkJ7g0SYACmAQAiAAkJ7g0SYACmAQAAAA==.',
Ib='Ibíng:BAAALgAECgYJBwAAAA==.',
Ic='Iceatron:BAAALgADCgUJBQAAAA==.',
Im='Imo:BAABLgAECn8qAAMeAAkJIRFrTgCrAQAeAAkJyQ5rTgCrAQAfAAUJIhI1JACDAAAAAA==.',
In='Intrepidz:BAAALgAECgEJAgABLgAFFAMJBQAEAFgYAA==.Inèvitable:BAABLgAECn9CAAIVAAkJHh0pIQB7AgAVAAkJHh0pIQB7AgAAAA==.',
Ir='Ironphant:BAAALgAECgYJBgAAAA==.',
Is='Istara:BAAALgAECgQJBAAAAA==.',
Iv='Ivorin:BAAALgAECgUJBQAAAA==.',
Ja='Javeech:BAABLgAECn8nAAMTAAkJzhmSKAAxAgATAAgJDRySKAAxAgAUAAEJFQo7XgA5AAAAAA==.',
Je='Jebib:BAAALgAECgYJBgABLgAFFAgJKQAWAB0dAA==.Jeod:BAAALgAECgYJCQAAAA==.',
Jo='Jolty:BAACLgAFFH8VAAIVAAYJQyCPHgDVAQAVAAYJQyCPHgDVAQAuAAQKfykAAxUACQlWIq8MADUDABUACQlWIq8MADUDAAYABAmkFucvANYAAAAA.Joydivision:BAAALgADCgIJAgAAAA==.',
Ju='Julian:BAAALgAECggJCAABLgAECgkJPwARACwkAA==.',
['Jð']='Jð:BAAALgAECgQJBAABLgAECgYJJQAJAGAhAA==.',
Ka='Kaboomchickn:BAAALgAECgIJAgABLgAECgUJCAAIAAAAAA==.Kaiou:BAAALgADCgQJCAAAAA==.Kantor:BAABLgAECn9RAAMdAAkJLhj0FAAgAgAdAAkJLhj0FAAgAgAaAAIJvQuKfgAzAAAAAA==.Karboomkin:BAABLgAFFH8FAAMKAAUJpRMlEADuAAAKAAQJpRMlEADuAAAgAAEJAAAQUgAAAAABLgAFFAgJGAAiAMYgAA==.Karnstein:BAABLgAECn8nAAQkAAgJ4BFTCwBVAQAkAAYJuxBTCwBVAQAEAAYJBxELRwADAQADAAUJgwTuMwDOAAAAAA==.Kasenko:BAAALgAECgIJAgABLgAECgYJFwAKAGkUAA==.Kasryna:BAABLgAECn8XAAIKAAYJaRSSIwAgAQAKAAYJaRSSIwAgAQAAAA==.Kathinja:BAABLgAECn8oAAITAAkJCQlNVACaAQATAAkJCQlNVACaAQAAAA==.Katiebeary:BAAALgAECgUJBQAAAA==.',
Ke='Kelthera:BAAALgAECgYJBgAAAA==.Kelumbria:BAAALgAECggJDgAAAA==.Keta:BAAALgADCgYJBgAAAA==.Ketameanie:BAABLgAECn80AAIJAAkJQBdeJgAoAgAJAAkJQBdeJgAoAgAAAA==.',
Ki='Kieran:BAAALgAECgQJCgAAAA==.Killerkitten:BAAALgADCgEJAQAAAA==.Kitsunè:BAAALgAECgEJAQAAAA==.',
Km='Kmazing:BAABLgAECn8rAAMBAAkJFg76IwCFAQABAAkJFg76IwCFAQACAAMJIRB1cwChAAAAAA==.',
Kn='Knifèparty:BAABLgAECn85AAIbAAkJkSLPAQDQAgAbAAkJkSLPAQDQAgAAAA==.',
Ko='Konoha:BAABLgAECn8sAAMZAAkJzyC0BQAhAwAZAAkJwh+0BQAhAwAdAAMJfiPoQwApAQAAAA==.',
Ku='Kultag:BAABLgAECn8fAAIiAAkJBRY5NwAaAgAiAAkJBRY5NwAaAgAAAA==.',
Ky='Kyaw:BAABLgAECn8WAAQRAAYJbRyAKAC2AQARAAYJbRyAKAC2AQAbAAIJxRJbFgCTAAAcAAEJPRQBIQA6AAAAAA==.Kynzo:BAABLgAECn9FAAIFAAkJXB4RBAC6AgAFAAkJXB4RBAC6AgAAAA==.',
La='Laykeezenith:BAACLgAFFH8UAAQlAAYJJh0rBwCrAQAlAAYJmxorBwCrAQATAAMJ7SJxcgCbAAAUAAEJvQetLwBEAAAuAAQKfx8ABCUACQmZIl4VAIcCACUACAnqIl4VAIcCABMACAm9IaE1APsBABQAAgl3EgooAHUAAAAA.Lazuli:BAACLgAFFH8FAAImAAUJpQ3wJQD2AAAmAAUJpQ3wJQD2AAAuAAQKf00AAyYACQnDFfQZAAUCACYACQnDFfQZAAUCABcAAQk8BcI/ACYAAAAA.',
Le='Lehann:BAABLgAECn8rAAITAAkJxw8jRQDGAQATAAkJxw8jRQDGAQAAAA==.',
Li='Lichtech:BAAALgAFFAIJAgABLgAFFAgJHgAEAPwbAA==.Lightsbane:BAAALgAECgcJEgAAAA==.',
Lu='Luciselda:BAAALgADCgUJBgAAAA==.Lumosnox:BAAALgADCgMJAwAAAA==.Lunariah:BAAALgADCgkJEwAAAA==.Luvtarhugar:BAAALgADCgMJAwAAAA==.',
Ma='Madaran:BAAALgAECgUJBwABLgAECgkJFgAXAHgYAA==.Magdalene:BAEALgAECgUJCQABLgAFFAQJDgAQAK4SAA==.Marebear:BAAALgADCgEJAQAAAA==.Marenus:BAABLgAECn9PAAITAAkJQRGfQQDSAQATAAkJQRGfQQDSAQAAAA==.Masume:BAAALgAECgcJEAAAAA==.Maély:BAAALgAECgEJAgAAAA==.',
Me='Mechadead:BAAALgADCggJCAAAAA==.Medal:BAAALgAECgEJAQAAAA==.Meowmix:BAAALgADCgcJDAAAAA==.',
Mi='Miantha:BAAALgAECgYJBwAAAA==.Michi:BAABLgAECn82AAMWAAkJgyL6AwB4AwAWAAkJgyL6AwB4AwAFAAYJLBZZFwBGAQAAAA==.Midnights:BAAALgAECggJEAAAAA==.Mightymopo:BAAALgADCgMJAwAAAA==.Mikuki:BAABLgAECn8jAAITAAkJvCPgEAC/AgATAAkJvCPgEAC/AgAAAA==.Milkinghands:BAABLgAECn8hAAMCAAkJ1g8fNwB+AQACAAkJ1g8fNwB+AQABAAEJlALKqgAiAAAAAA==.Minabos:BAAALgAECgIJAgAAAA==.Mizmonk:BAACLgAFFH8ZAAILAAYJSBh5EgB6AQALAAYJSBh5EgB6AQAuAAQKfyIAAgsACQnxHqMJAO4CAAsACQnxHqMJAO4CAAAA.',
Mj='Mjölnir:BAAALgAECgEJAQAAAA==.',
Mo='Montfort:BAAALgADCggJDwAAAA==.Mootality:BAAALgAECgIJAwABLgAECggJMQAMAN8hAA==.Moovover:BAAALgAECggJCgAAAA==.Morningcrow:BAAALgAECgUJBgAAAA==.',
Ms='Msmaho:BAAALgAECgYJCgAAAA==.',
Mu='Muhdeeps:BAAALgADCgQJBAAAAA==.Murionor:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgAECgYJBgAAAA==.',
My='Mykian:BAABLgAECn8pAAMkAAkJAQfyDwAAAQAEAAkJ0QR2PwAgAQAkAAcJ1QfyDwAAAQAAAA==.Myrwynn:BAAALgAECgMJAwABLgAECgkJPgAaAIAZAA==.Mythlee:BAAALgAECgUJCAAAAA==.Mythundon:BAAALgADCgUJBQAAAA==.',
Na='Nahion:BAAALgAECgYJCQAAAA==.Nashira:BAABLgAECn8gAAITAAkJVBMiOQDvAQATAAkJVBMiOQDvAQAAAA==.Nathalas:BAAALgAECgEJAgABLgAECgkJPwARACwkAA==.Nature:BAAALgAECgUJCwAAAA==.',
Ne='Necrana:BAAALgADCgEJAQAAAA==.Necrobyarg:BAAALgAECgYJDQAAAA==.Nemasus:BAABLgAECn9BAAMWAAkJxB3+CgAEAwAWAAkJxB3+CgAEAwAgAAEJRQxIhwAxAAAAAA==.Nembie:BAAALgAECgQJBAAAAA==.Nethertech:BAABLgAFFH8HAAIJAAQJ0hGRQAAVAQAJAAQJ0hGRQAAVAQABLgAFFAgJHgAEAPwbAA==.',
Ni='Ninjahh:BAACLgAFFH8OAAIRAAUJswubHwASAQARAAUJswubHwASAQAuAAQKfycAAhEACAnxFYwXANIBABEACAnxFYwXANIBAAAA.Niobei:BAAALgADCgcJBwABLgAECgkJQAAhAJwYAA==.Nioshei:BAABLgAECn9AAAIhAAkJnBjMFACYAgAhAAkJnBjMFACYAgAAAA==.Nisara:BAACLgAFFH8LAAICAAQJvRMSKgDyAAACAAQJvRMSKgDyAAAuAAQKfzEAAwIACQndHpgQAIwCAAIACQndHpgQAIwCAAEACAlsH/4LAHkCAAAA.',
No='Nochmuerta:BAABLgAECn8ZAAIVAAkJRRl5JwBcAgAVAAkJRRl5JwBcAgAAAA==.Nogrid:BAABLgAECn9RAAINAAkJHBtLBgB2AgANAAkJHBtLBgB2AgAAAA==.Nossaria:BAAALgAECgIJAgAAAA==.Notmyface:BAAALgAECgcJEwABLgAFFAIJBQAOAGAVAA==.',
Nu='Nuorong:BAAALgAECgUJBQABLgAECgkJPgAWABkXAA==.Nuthar:BAABLgAECn9BAAIiAAgJ3CVkCwACAwAiAAgJ3CVkCwACAwAAAA==.',
Ny='Nyxandra:BAAALgAECgQJBAAAAA==.',
['Né']='Nésta:BAAALgAECgEJAQAAAA==.',
['Nò']='Nòhva:BAAALgAECgQJBAAAAA==.',
Ol='Oldeis:BAAALgAECgEJAQAAAA==.',
Om='Ominousowl:BAABLgAFFH8FAAIEAAMJWBi0MgDtAAAEAAMJWBi0MgDtAAAAAA==.',
Or='Oregizm:BAAALgAFFAEJAQAAAA==.Orneryosprey:BAAALgAFFAEJAQABLgAFFAMJCQABAF0hAA==.',
Pa='Pamburu:BAABLgAECn8jAAQTAAgJ8w3RcQBRAQATAAgJpg3RcQBRAQAlAAYJvgURHwCrAAAUAAIJrQUPKgBgAAAAAA==.Papagrape:BAABLgAECn9CAAQDAAkJxSAuAgBSAwADAAkJxSAuAgBSAwAEAAMJaRbAVgDKAAAkAAMJAhQbFgCmAAAAAA==.Parzivàl:BAABLgAECn8mAAIYAAgJehiaEwB1AgAYAAgJehiaEwB1AgAAAA==.Paxa:BAABLgAECn8rAAMdAAcJbB04GQD0AQAdAAcJbB04GQD0AQAaAAYJTgsjQwD6AAAAAA==.',
Pe='Peacebox:BAAALgADCggJDAABLgAECgkJKwABABYOAA==.Persayis:BAAALgAECgYJCgAAAA==.',
Ph='Phoebel:BAAALgADCgkJEgAAAA==.Phoenixbodhi:BAAALgAECgQJBAAAAA==.',
Pi='Pickledeggs:BAAALgAECgIJAgABLgAECggJIgAMAPEYAA==.',
Po='Podnov:BAACLgAFFH8XAAMlAAYJhiAmCQDBAQAlAAYJhiAmCQDBAQATAAIJpB2TeACSAAAuAAQKfyMAAiUACQlEHcwNANYCACUACQlEHcwNANYCAAAA.Pollyanna:BAAALgADCgEJAQAAAA==.',
Pr='Preyon:BAABLgAECn8YAAIKAAYJdg9yLQDlAAAKAAYJdg9yLQDlAAABLgAECgcJGgALAN8NAA==.',
Py='Pyne:BAAALgADCgEJAQAAAA==.Pyrista:BAAALgAECgkJDAAAAA==.',
Qa='Qang:BAAALgAECgYJBwAAAA==.',
Qo='Qotho:BAABLgAECn9IAAITAAkJYhvnJABDAgATAAkJYhvnJABDAgAAAA==.',
Ra='Raikou:BAAALgAECgUJBQABLgAFFAYJIQAaAH8iAA==.Raistliin:BAAALgAECgYJDgAAAA==.Raithis:BAACLgAFFH8XAAITAAUJLx32MQA+AQATAAUJLx32MQA+AQAuAAQKfzIAAhMACQlAIsAEAEEDABMACQlAIsAEAEEDAAAA.Raito:BAAALgADCgUJBQAAAA==.Ramhadin:BAEALgAECgMJCgABLgAECggJLwAaAHAeAA==.Ramzert:BAEALgAECgIJAgABLgAECggJLwAaAHAeAA==.',
Re='Rednaxel:BAABLgAECn9AAAMRAAkJ4CRMAgAyAwARAAkJeCRMAgAyAwAbAAUJRx8fCADFAQAAAA==.Redvelvet:BAABLgAECn8nAAMCAAkJqBUJGwAsAgACAAkJqBUJGwAsAgABAAQJ9Ab5WwCgAAAAAA==.Rekoner:BAABLgAECn8mAAIVAAkJRxO/QwDvAQAVAAkJRxO/QwDvAQAAAA==.Resi:BAAALgAECgIJAgAAAA==.Resii:BAAALgAECgEJAgABLgAECgIJAgAIAAAAAA==.Retarganator:BAABLgAECn9UAAMJAAkJ7R2MFACUAgAJAAkJtx2MFACUAgAnAAQJjBjREgAlAQAAAA==.',
Ri='Ringmistress:BAAALgADCgcJBwAAAA==.Rixaa:BAAALgADCgQJBQABLgAECggJIgATAB4eAA==.',
Ro='Rocks:BAAALgAECgYJCAAAAA==.Romam:BAAALgAECgYJCQAAAA==.',
Ru='Rubyknight:BAAALgAECgEJAQAAAA==.',
Ry='Rydran:BAAALgAECgUJCQAAAA==.Rykria:BAAALgAECgQJBAAAAA==.',
Sa='Samsonknight:BAAALgADCgYJBgAAAA==.Sanguinarian:BAABLgAECn8XAAIiAAgJIQ0vpwAgAQAiAAgJIQ0vpwAgAQAAAA==.Savash:BAAALgAECggJEgAAAA==.',
Sc='Scrubtotem:BAAALgAECgMJAwAAAA==.',
Se='Secksiecutie:BAABLgAECn82AAMjAAkJ7hqaBABvAgAjAAkJ7hqaBABvAgAGAAcJvQwjKgD8AAAAAA==.Selanda:BAAALgAECgQJBAAAAA==.Serinar:BAABLgAFFH8FAAIiAAMJlwMYdgCuAAAiAAMJlwMYdgCuAAAAAA==.Serraphem:BAAALgADCgkJCQAAAA==.',
Sh='Shafrog:BAAALgAECgIJAgABLgAECgkJPwAQAPkWAA==.Shoshin:BAABLgAECn8aAAMLAAcJ3w1NSQDQAAALAAcJ3w1NSQDQAAABAAQJJgxhXQCbAAAAAA==.Shïvana:BAAALgAECgMJDwAAAA==.',
Si='Silversaiyan:BAABLgAECn9KAAMOAAgJsyFTDQCRAgAOAAgJsyFTDQCRAgAPAAEJXRiEOgBGAAAAAA==.',
Sk='Skullpanda:BAAALgAECggJCAAAAA==.',
Sl='Slade:BAABLgAECn8/AAMRAAkJLCTwAgAYAwARAAkJLCTwAgAYAwAbAAMJ+xvNEgDvAAAAAA==.Slap:BAAALgAECgEJAQAAAA==.Sliyce:BAAALgAECgIJBgAAAA==.',
Sm='Smóke:BAABLgAECn9RAAIJAAkJKxUMNADqAQAJAAkJKxUMNADqAQAAAA==.',
Sn='Snore:BAAALgADCgQJBgAAAA==.Snowfawn:BAABLgAECn8nAAITAAgJohawNwD0AQATAAgJohawNwD0AQABLgAFFAIJBAAIAAAAAA==.',
So='Sofedan:BAABLgAECn9RAAIlAAkJuA9UCwCmAQAlAAkJuA9UCwCmAQAAAA==.Sorgath:BAAALgAECgMJAwAAAA==.Soriel:BAABLgAECn8oAAILAAkJOw/8HQCtAQALAAkJOw/8HQCtAQAAAA==.Sorokwa:BAABLgAECn8XAAIVAAkJKgJP7gC1AAAVAAkJKgJP7gC1AAAAAA==.',
Sq='Squids:BAAALgADCgQJBAAAAA==.',
St='Stallon:BAAALgAECgEJAQAAAA==.Strongstork:BAAALgAFFAEJAQABLgAFFAMJCQABAF0hAA==.',
Su='Sunsword:BAAALgAECgYJEQAAAA==.Suriden:BAAALgAECgYJBwAAAA==.',
Sw='Swagidan:BAABLgAECn8sAAIHAAgJoxgAEgBMAgAHAAgJoxgAEgBMAgAAAA==.Sweatermonk:BAAALgADCgIJAgABLgAECgYJBgAIAAAAAA==.Sweaterpally:BAAALgAECgYJBgAAAA==.Swiftera:BAABLgAECn8lAAIYAAkJIxaEKADqAQAYAAkJIxaEKADqAQAAAA==.Swiftlier:BAABLgAECn8vAAILAAkJtxnyFAD+AQALAAkJtxnyFAD+AQAAAA==.Swipegirl:BAAALgAECgYJCQAAAA==.',
Sy='Sybelyyia:BAAALgAECgUJBgAAAA==.Sylphrène:BAABLgAECn8yAAIHAAkJIwdNJgA0AQAHAAkJIwdNJgA0AQAAAA==.Sylriane:BAAALgAECgEJAgAAAA==.',
Ta='Taladan:BAAALgAECgQJBQAAAA==.Tallyian:BAAALgAECgEJAQAAAA==.Tandrana:BAAALgAECgMJBAAAAA==.Tankmepapi:BAAALgAECgMJAwAAAA==.Tanwen:BAABLgAECn8UAAQDAAYJ+QemJAC+AAADAAYJ+QemJAC+AAAkAAQJHAMENwBfAAAEAAIJAAIAkgAoAAAAAA==.Targquellin:BAAALgAECgcJBwABLgAECgkJVAAJAO0dAA==.Targypunch:BAAALgADCgcJBwABLgAECgkJVAAJAO0dAA==.Tatsunoshinn:BAAALgADCgEJAQAAAA==.',
Te='Techniqe:BAACLgAFFH8eAAMEAAgJ/BuQCQA9AgAEAAgJ/BuQCQA9AgADAAEJrwEQKgAxAAAuAAQKfzYAAwQACAkkIxsHAAoDAAQACAkkIxsHAAoDACQABgkgIe8SALMBAAAA.Techtides:BAAALgADCgUJBQABLgAFFAgJHgAEAPwbAA==.Temperance:BAAALgADCgEJAQAAAA==.Temptations:BAAALgAECgUJBgAAAA==.Terminus:BAAALgAECgcJCQAAAA==.Terrylin:BAAALgAECgYJBwAAAA==.',
Th='Thaliá:BAAALgADCgkJFQAAAA==.Themachinist:BAAALgAECgYJBgAAAA==.Thomag:BAAALgADCgIJAgAAAA==.Thor:BAAALgAECgMJAwAAAA==.',
Ti='Ticebane:BAACLgAFFH8PAAMGAAUJ8QjzIgDEAAAGAAUJ8QjzIgDEAAAVAAIJfwF16wBmAAAuAAQKfyMAAgYACQk0GbALAFgCAAYACQk0GbALAFgCAAAA.Tiduspullo:BAABLgAECn8qAAMiAAkJmhuTRAAWAgAiAAkJdxWTRAAWAgANAAUJoRoiGABOAQAAAA==.Tiduswar:BAABLgAECn8fAAMSAAcJ2BpSFgCqAQASAAcJ2BpSFgCqAQAOAAIJfRKDewByAAABLgAECgkJKgAiAJobAA==.Tinafay:BAAALgAECgcJDAAAAA==.Tiramisuu:BAAALgAECgcJCQAAAA==.Titanbeard:BAAALgAECgMJBQAAAA==.Titor:BAABLgAECn80AAMDAAgJKRqzCABaAgADAAgJKRqzCABaAgAkAAUJeQ5jEwDJAAAAAA==.Tituspullo:BAAALgAECgcJCgABLgAECgkJKgAiAJobAA==.',
To='Tolduan:BAAALgAECgUJDQAAAA==.Totemik:BAABLgAECn8WAAIXAAgJeBiYCgABAgAXAAgJeBiYCgABAgAAAA==.Toughturkey:BAABLgAFFH8JAAMBAAMJXSHLHwDRAAABAAIJJCPLHwDRAAACAAIJqxKzQwBvAAAAAA==.Towen:BAAALgADCgUJBQAAAA==.Toy:BAAALgADCgYJGAAAAA==.',
Tr='Tremorhoof:BAAALgADCgIJAwAAAA==.Tresera:BAAALgADCgEJAQAAAA==.Tricarnetry:BAABLgAECn8eAAIiAAcJow3TlQA8AQAiAAcJow3TlQA8AQAAAA==.Trufleshufle:BAAALgAECggJEQAAAA==.',
['Tà']='Tàlle:BAAALgAECgMJAwAAAA==.',
Uh='Uhtread:BAAALgADCgYJBQAAAA==.',
Ul='Ulfer:BAAALgAECgUJBQABLgAFFAMJBgAGAOodAA==.',
Un='Unholyfury:BAAALgADCgYJBgAAAA==.',
Va='Vapor:BAAALgAECgQJBQAAAA==.Vaquinha:BAAALgADCgUJBQAAAA==.Varyel:BAAALgAECgIJAgAAAA==.',
Ve='Velianne:BAAALgADCgUJBQAAAA==.Vellinada:BAAALgADCgMJAwABLgAFFAYJHwAdAB0lAA==.Verakis:BAABLgAECn9AAAISAAkJLRc+DQAMAgASAAkJLRc+DQAMAgAAAA==.Verndarí:BAABLgAECn8ZAAMGAAkJ1Q1dHABrAQAGAAkJ1Q1dHABrAQAjAAMJzgXMKQBrAAABLgAECgkJLwALALcZAA==.Verudora:BAAALgAECgUJBgAAAA==.Vervain:BAAALgAECgUJBQAAAA==.',
Vo='Vonnie:BAAALgADCgkJCQAAAA==.Vortheus:BAAALgAECgkJEwAAAA==.Votollis:BAAALgAECgQJBQAAAA==.',
Wa='Warlanen:BAAALgAECgUJBgAAAA==.Warning:BAAALgADCgUJBQAAAA==.Warpiggies:BAAALgADCgkJCAAAAA==.',
Wi='Widdy:BAAALgAECgcJEAAAAA==.Willbur:BAABLgAECn9JAAIMAAkJVxoJKgBrAgAMAAkJVxoJKgBrAgAAAA==.Wittledwagon:BAAALgADCgkJCQAAAA==.',
Wu='Wurthwhile:BAAALgAECgYJDgAAAA==.',
Wy='Wylaniris:BAAALgADCgQJBAAAAA==.Wyndywalker:BAABLgAECn81AAIgAAkJqQkYMQBKAQAgAAkJqQkYMQBKAQAAAA==.',
Xa='Xaveil:BAAALgADCgEJAQAAAA==.',
Xe='Xenosian:BAAALgAECgkJCQAAAA==.',
Xi='Xinnou:BAAALgAECgEJAQAAAA==.Xinnuo:BAAALgAECgQJBwAAAA==.',
Xy='Xydias:BAAALgAECggJDwAAAA==.Xyra:BAAALgADCgcJBwAAAA==.',
Yo='Yoku:BAAALgAECggJEwAAAA==.',
Yu='Yunxiao:BAAALgAECgEJAQAAAA==.',
Za='Zag:BAAALgAECgEJAQABLgAECgkJMAAnALYWAA==.Zalgarian:BAAALgAECgYJCgAAAA==.Zamønk:BAABLgAECn8ZAAMLAAcJFg8WOABqAQALAAcJFg8WOABqAQABAAIJ+wzYjgA3AAAAAA==.Zaphoidvtwo:BAAALgAECgUJCwAAAA==.Zason:BAAALgADCgMJAwAAAA==.Zatari:BAAALgADCgMJAwAAAA==.Zavaen:BAAALgADCgEJAQAAAA==.',
Ze='Zelectie:BAABLgAECn8XAAIKAAgJbhcyCgD3AQAKAAgJbhcyCgD3AQAAAA==.Zelzaikin:BAAALgAECgQJBgAAAA==.Zevon:BAAALgAECgYJCgAAAA==.',
Zi='Ziarra:BAAALgADCgYJBgABLgADCgcJDQAIAAAAAA==.Zinazarinara:BAAALgAECgIJAgAAAA==.Zirril:BAAALgADCgcJDwAAAA==.',
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
