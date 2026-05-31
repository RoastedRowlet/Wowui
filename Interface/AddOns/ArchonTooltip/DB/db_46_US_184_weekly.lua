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

local lookup = {'Monk-Mistweaver','Evoker-Preservation','Evoker-Augmentation','Druid-Feral','DeathKnight-Blood','DemonHunter-Havoc','Unknown-Unknown','DemonHunter-Devourer','Druid-Guardian','Monk-Brewmaster','Mage-Frost','Paladin-Protection','Warrior-Fury','Rogue-Subtlety','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Unholy','Druid-Restoration','Shaman-Enhancement','Paladin-Holy','Priest-Discipline','Priest-Shadow','Warrior-Protection','Rogue-Assassination','Rogue-Outlaw','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Balance','Shaman-Restoration','Paladin-Retribution','Monk-Windwalker','DeathKnight-Frost','Evoker-Devastation','Hunter-Marksmanship','Shaman-Elemental','DemonHunter-Vengeance','Warrior-Arms',}
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=46,date='2026-05-30',data={Ac='Acefu:BAAALgAECgYJEwAAAA==.Acorneo:BAABLgAFFH8GAAIBAAUJmQStJwDeAAABAAUJmQStJwDeAAAAAA==.Acornita:BAACLgAFFH8MAAMCAAQJsw1aEQCsAAACAAMJ5w9aEQCsAAADAAIJXwInUABjAAAuAAQKfyoAAwIACQnlD0YRACgCAAIACQnlD0YRACgCAAMABwlIEgokAJ0BAAEuAAUUBQkGAAEAmQQA.',
Ad='Adoreith:BAAALgAECgEJAQAAAA==.',
Ae='Aelana:BAAALgADCgkJCQAAAA==.Aeriith:BAAALgAECgEJAQAAAA==.',
Ah='Ahyoka:BAAALgAFFAEJAQAAAA==.',
Ai='Ailanthus:BAABLgAECn8cAAIEAAcJwg49GQAfAQAEAAcJwg49GQAfAQAAAA==.',
Ak='Akinira:BAECLgAFFH8MAAIFAAQJ5RvDEQA0AQAFAAQJ5RvDEQA0AQAuAAQKfz4AAgUACQmVHpwHAI0CAAUACQmVHpwHAI0CAAAA.',
Al='Aleinadris:BAAALgADCgQJBAAAAA==.Alendy:BAAALgAECgYJBgAAAA==.Alikchi:BAAALgADCgEJAgAAAA==.Alloisaber:BAAALgAECgYJCAAAAA==.Alternis:BAAALgAECgMJAwAAAA==.Alunne:BAAALgAECgEJAQAAAA==.',
An='Andrelsia:BAAALgAECgYJCQAAAA==.Andrilla:BAAALgAECgYJCQAAAA==.Ankeseth:BAAALgAECgYJBgAAAA==.',
Ap='Apôllyon:BAACLgAFFH8OAAIGAAMJASR2DQAZAQAGAAMJASR2DQAZAQAuAAQKfy4AAgYACQmeJfAAAL4DAAYACQmeJfAAAL4DAAAA.',
Ar='Aracelis:BAAALgAECgcJBwAAAA==.Aradius:BAAALgAECgEJAgABLgAECgIJBgAHAAAAAA==.Archertower:BAAALgADCgUJBQAAAA==.Artemiswynd:BAAALgAECgUJBQAAAA==.Arén:BAABLgAECn8kAAMIAAgJsR8BLgD5AQAIAAcJ9h4BLgD5AQAGAAcJhx+YGwDkAQAAAA==.',
As='Ashenshugär:BAAALgAECgQJCAAAAA==.',
Av='Avadda:BAABLgAECn8YAAIJAAcJthE8EgBPAQAJAAcJthE8EgBPAQABLgAECgkJKAAKADsPAA==.',
Az='Azmar:BAABLgAECn8qAAILAAgJCiCfKABiAgALAAgJCiCfKABiAgAAAA==.',
Ba='Badffinger:BAAALgADCgYJCQAAAA==.Badtouchbull:BAAALgADCgcJBwAAAA==.Balain:BAAALgAECgQJBAABLgAECgcJGgAKAN8NAA==.',
Be='Bear:BAAALgADCgcJBwAAAA==.Bearmont:BAABLgAECn8aAAIMAAcJyxc/EQCYAQAMAAcJyxc/EQCYAQAAAA==.Bearzerk:BAABLgAECn8mAAINAAkJCBTEIADXAQANAAkJCBTEIADXAQAAAA==.Beastmonk:BAAALgADCgEJAQAAAA==.Benathar:BAABLgAECn8iAAILAAcJGw6fjgA/AQALAAcJGw6fjgA/AQAAAA==.',
Bi='Bifrost:BAAALgAECgcJCwAAAA==.Bionico:BAAALgAECgUJDgAAAA==.Birgir:BAAALgAECgUJBwAAAA==.',
Bl='Blackmagék:BAAALgADCgkJCQAAAA==.Blazer:BAAALgAFFAIJAgAAAA==.Bloodrager:BAAALgADCgIJAgAAAA==.Bloodthorn:BAABLgAECn8cAAIOAAgJJgZfKwAjAQAOAAgJJgZfKwAjAQAAAA==.Blortimor:BAAALgADCgcJBwAAAA==.',
Bo='Bombad:BAAALgAECgYJDQAAAA==.Boomnescient:BAABLgAECn8cAAIPAAcJaAcPgQAjAQAPAAcJaAcPgQAjAQAAAA==.Bortt:BAAALgAECgEJAQAAAA==.Bozscaggs:BAABLgAECn9AAAMPAAkJRRJ6MAADAgAPAAkJRRJ6MAADAgAQAAUJAwN5PwCyAAAAAA==.',
Br='Bramis:BAAALgADCgkJHAAAAA==.Brantu:BAAALgADCgQJCAABLgADCgkJDwAHAAAAAA==.Braultus:BAABLgAECn8vAAIFAAkJXx2ICQBlAgAFAAkJXx2ICQBlAgAAAA==.Breuddwydwr:BAAALgADCgEJAQAAAA==.Breyastrasza:BAAALgADCgMJAwAAAA==.Brood:BAAALgAECgYJBgAAAA==.Bruceleroy:BAAALgAECgEJAQAAAA==.Bruinn:BAAALgAECgQJBAABLgAECgcJGgAKAN8NAA==.',
Bu='Burstangel:BAAALgAECgYJCAAAAA==.',
By='Byrddh:BAAALgADCgQJBAAAAA==.',
['Bä']='Bäguette:BAAALgADCgEJAgAAAA==.',
Ca='Cadenza:BAAALgAECgYJCgAAAA==.Caelthar:BAAALgAECgUJBQAAAA==.Caliopedk:BAACLgAFFH8HAAMFAAIJrRhWLwBRAAARAAIJrRjjOACqAAAFAAIJqAJWLwBRAAAuAAQKfxsAAxEACAlIIWUhALsCABEACAlIIWUhALsCAAUABQlJDjQqAO0AAAAA.Caliseni:BAAALgADCgYJBgAAAA==.Capra:BAAALgAECgYJCAAAAA==.Carillanklip:BAAALgADCgUJBQAAAA==.',
Cd='Cdmickey:BAAALgADCgUJBQAAAA==.',
Ce='Celestè:BAAALgAECggJEQAAAA==.Celéste:BAAALgAECgkJEAAAAA==.Cerdwin:BAAALgAECggJEAABLgAECgkJPAASABkXAA==.',
Ch='Charferad:BAAALgAECgUJCAAAAA==.Cheaptrick:BAAALgADCgcJEwAAAA==.Chibeard:BAABLgAECn8iAAIKAAgJeSKsCACXAgAKAAgJeSKsCACXAgAAAA==.Chonglin:BAAALgADCgMJAwAAAA==.Chrysopteron:BAAALgAECgEJAQAAAA==.',
Cl='Clearcast:BAAALgADCgkJCQAAAA==.Clubsdh:BAAALgAECgMJBAAAAA==.',
Co='Coolbro:BAAALgADCgIJAgABLgADCggJCAAHAAAAAA==.Corialis:BAAALgAECgkJEgAAAA==.Counsel:BAAALgAECgUJBQAAAA==.',
Cr='Criantha:BAAALgADCgIJAgAAAA==.Crom:BAABLgAECn8wAAITAAgJUg3PEgBoAQATAAgJUg3PEgBoAQAAAA==.Crosis:BAAALgADCgYJBgAAAA==.Cruelladvoid:BAAALgAECgQJBAAAAA==.Cruush:BAAALgAECgYJBQAAAA==.',
Cu='Culerro:BAAALgAECgYJAwABLgAECgYJBQAHAAAAAA==.Cursive:BAAALgADCgUJDQAAAA==.',
Cy='Cygnes:BAABLgAECn8bAAIRAAgJsBvpQQDqAQARAAgJsBvpQQDqAQAAAA==.',
Da='Daddywarrior:BAAALgADCgUJBgAAAA==.Daeva:BAAALgADCgEJAQAAAA==.Dantey:BAAALgADCgcJFAAAAA==.Daus:BAAALgAFFAEJAQAAAA==.Dazanna:BAABLgAECn8yAAMUAAkJBRtaCwDDAgAUAAkJBRtaCwDDAgAMAAUJTAuoMACJAAAAAA==.Dazre:BAAALgAECgUJBgAAAA==.',
De='Deeminor:BAAALgADCgkJEwAAAA==.Demeisen:BAAALgAECgMJAwAAAA==.Desktop:BAABLgAECn8yAAMVAAgJHRp0EABLAgAVAAgJHRp0EABLAgAWAAUJxg++RgDNAAAAAA==.',
Di='Diod:BAABLgAECn83AAIXAAgJERYeFwByAQAXAAgJERYeFwByAQAAAA==.Divineßovine:BAAALgADCgcJBwAAAA==.',
Do='Doomtheory:BAAALgADCgcJCwAAAA==.Dorammu:BAAALgAECgEJAQAAAA==.',
Dr='Dracovoid:BAAALgADCgYJBwAAAA==.Dracvoker:BAAALgAECgQJBQABLgAECggJJAAIALEfAA==.Draegyns:BAAALgAECgIJAgABLgAFFAUJEAAYAG0WAA==.Draehton:BAAALgAECgYJBwABLgAFFAQJCwAQAH4XAA==.Dragyns:BAACLgAFFH8QAAMYAAUJbRYKBAA/AQAYAAQJbRYKBAA/AQAOAAEJAAB8NwAAAAAuAAQKfy8ABBgACQngG4ECAMoCABgACQmxGYECAMoCAA4ABgmMGz8sAJwBABkAAwmrFFIJANwAAAAA.Dragynseye:BAAALgADCgIJAgABLgAFFAUJEAAYAG0WAA==.Drayper:BAABLgAECn8rAAMaAAkJYB+YBAApAwAaAAkJYB+YBAApAwAVAAEJZw3AWQAvAAAAAA==.Druugal:BAACLgAFFH8NAAIOAAMJnh3uHQAIAQAOAAMJnh3uHQAIAQAuAAQKfy8AAw4ACQlwH0YMANQCAA4ACQlwH0YMANQCABgAAQl6C+ofADMAAAAA.',
Du='Dubs:BAABLgAECn8sAAQbAAkJxxpBPQDaAQAbAAYJkhpBPQDaAQAcAAIJ7hnsHwCWAAAdAAIJwxt2KgBKAAAAAA==.Dunbarke:BAAALgAECgcJEQAAAA==.',
Ef='Efishient:BAABLgAECn8eAAISAAYJWCQbHwA6AgASAAYJWCQbHwA6AgABLgAFFAYJGQASAH8TAA==.',
El='Elisoria:BAAALgAECgMJAwAAAA==.Elliwynd:BAABLgAECn8qAAISAAkJvBKnIwAaAgASAAkJvBKnIwAaAgAAAA==.',
Eo='Eoshot:BAAALgAECgUJCAAAAA==.',
Er='Erinnys:BAABLgAECn8yAAMGAAkJAxM+EgDpAQAGAAkJAxM+EgDpAQAIAAYJsgWPlgDvAAAAAA==.Ermoril:BAAALgAECgUJBgAAAA==.Ernesta:BAAALgADCgcJCAAAAA==.Eroksix:BAAALgADCgEJAQAAAA==.',
Eu='Eufemia:BAAALgAECgYJCQAAAA==.',
['Eø']='Eøs:BAAALgAECgEJAQAAAA==.',
Fa='Famine:BAAALgAECgcJDAAAAA==.',
Fe='Feelmebro:BAAALgADCggJCAAAAA==.Felern:BAAALgAECgcJCwABLgAECggJKgALAAogAA==.Feyrun:BAAALgADCgkJEwAAAA==.Feyrè:BAAALgADCgQJBQAAAA==.',
Fi='Finalomega:BAAALgAECgYJEwAAAA==.',
Fl='Flaminfalcon:BAABLgAFFH8FAAIWAAIJQBgqIwCxAAAWAAIJQBgqIwCxAAABLgAFFAMJBAAHAAAAAA==.Flody:BAAALgAECgYJDAAAAA==.',
Fo='Foxflame:BAABLgAECn88AAMSAAkJGRc1HQBJAgASAAkJGRc1HQBJAgAeAAgJuw0kKAB0AQAAAA==.',
Fr='Franzen:BAAALgAECgMJBAAAAA==.Freakbob:BAAALgADCgYJCQAAAA==.Froglocky:BAABLgAECn84AAMdAAgJYRd8CADBAQAdAAgJYRd8CADBAQAbAAMJcwRi9ABwAAAAAA==.Fronsac:BAAALgADCgQJBAAAAA==.',
Fu='Fulanita:BAABLgAECn8XAAMeAAYJDA7zQgDkAAAeAAYJDA7zQgDkAAASAAIJSwrEswBGAAAAAA==.',
Ga='Gallager:BAAALgADCgMJAwAAAA==.Garzok:BAABLgAECn8hAAMdAAgJ/wuJDgBRAQAdAAgJ/wuJDgBRAQAbAAMJzQHnCAFLAAAAAA==.',
Ge='Genkithered:BAABLgAECn8uAAIfAAgJ0hq4GwBTAgAfAAgJ0hq4GwBTAgAAAA==.',
Gi='Gilaras:BAAALgAECgYJBgAAAA==.Gilernil:BAAALgAECgUJDQAAAA==.',
Gl='Gladtohelp:BAAALgAECgIJAgAAAA==.',
Gn='Gnoquarter:BAAALgADCgIJAgAAAA==.',
Gr='Gravemarks:BAABLgAECn8YAAMZAAgJqBNNCACcAQAZAAgJqBNNCACcAQAYAAQJzAncEQDoAAAAAA==.Grimhorn:BAABLgAECn8gAAMeAAYJYghCVQCfAAAeAAUJAAlCVQCfAAAJAAIJWQO4ZAAqAAAAAA==.Grimlie:BAAALgADCgkJDwAAAA==.Grimmrock:BAAALgAECgUJCAAAAA==.Grumblen:BAAALgADCgMJAwAAAA==.',
Gu='Guaritrice:BAAALgAECgYJDgAAAA==.Gubb:BAAALgAECgMJAwAAAA==.',
Gw='Gwenylane:BAABLgAECn8kAAIgAAkJPQmadQBoAQAgAAkJPQmadQBoAQAAAA==.Gwindor:BAAALgAECgYJCQAAAA==.Gwyndelyn:BAABLgAECn8xAAIhAAgJ9wvMLABBAQAhAAgJ9wvMLABBAQAAAA==.',
Ha='Hatterus:BAABLgAECn88AAIgAAkJPwzVYQCTAQAgAAkJPwzVYQCTAQAAAA==.',
He='Herculeze:BAAALgAFFAIJAgAAAA==.Hessian:BAAALgADCgEJAQAAAA==.Hetairoi:BAAALgAECgIJAgABLgAFFAIJBAAHAAAAAA==.Hetd:BAAALgAECgEJAgAAAA==.',
Hi='Hillbroken:BAABLgAECn9JAAIiAAkJoiLfAQDeAgAiAAkJoiLfAQDeAgAAAA==.',
Ho='Hohalt:BAAALgAECgEJAgAAAA==.Holycross:BAAALgAECgIJAgAAAA==.Holysmokers:BAAALgAECgYJCwABLgAFFAUJEAAYAG0WAA==.Holysnow:BAAALgADCgkJDAABLgAFFAIJAgAHAAAAAA==.Holysoul:BAAALgAECgEJAwAAAA==.',
Hu='Huntertidus:BAAALgAECggJDQABLgAECgkJKgAgAJobAA==.Huntrix:BAAALgAECgYJBgAAAA==.',
['Hà']='Hànks:BAABLgAECn8cAAIgAAgJzw6udQBoAQAgAAgJzw6udQBoAQAAAA==.',
Ib='Ibíng:BAAALgAECgYJBwAAAA==.',
Im='Imo:BAABLgAECn8mAAMbAAkJIRFASwCtAQAbAAkJyQ5ASwCtAQAcAAUJIhJCIgCDAAAAAA==.',
In='Intrepidz:BAAALgAECgEJAgABLgAFFAMJBAAHAAAAAA==.Inèvitable:BAABLgAECn9CAAIRAAkJHh2HHgB+AgARAAkJHh2HHgB+AgAAAA==.',
Ir='Ironphant:BAAALgAECgYJBgAAAA==.',
Is='Istara:BAAALgAECgMJAwAAAA==.',
Iv='Ivorin:BAAALgAECgUJBQAAAA==.',
Ja='Javeech:BAABLgAECn8nAAMPAAkJzhn5JAA3AgAPAAgJDRz5JAA3AgAQAAEJFQpGWgA5AAAAAA==.',
Je='Jebib:BAAALgAECgYJBgABLgAFFAgJKQASAB0dAA==.Jeod:BAAALgAECgYJCQAAAA==.',
Jo='Jolty:BAACLgAFFH8UAAIRAAUJBSLVKwCCAQARAAUJBSLVKwCCAQAuAAQKfykAAxEACQlWIq8MADUDABEACQlWIq8MADUDAAUABAmkFlQtANgAAAAA.Joydivision:BAAALgADCgIJAgAAAA==.',
Ju='Julian:BAAALgAECggJCAABLgAECgkJPwAOACwkAA==.',
Ka='Kaboomchickn:BAAALgAECgIJAgABLgAECgUJCAAHAAAAAA==.Kaiou:BAAALgADCgQJCAAAAA==.Kantor:BAABLgAECn9JAAIaAAkJLhhpEwAnAgAaAAkJLhhpEwAnAgAAAA==.Karboomkin:BAAALgAECgcJBwABLgAFFAcJFgAgAN4gAA==.Karnstein:BAABLgAECn8mAAQjAAgJ4BFiDQAmAQAjAAUJXhFiDQAmAQADAAYJBxEbQwD8AAACAAUJgwTuMwDOAAAAAA==.Kasenko:BAAALgAECgIJAgABLgAECgYJEwAHAAAAAA==.Kasryna:BAAALgAECgYJEwAAAA==.Kathinja:BAABLgAECn8oAAIPAAkJCQmITgCeAQAPAAkJCQmITgCeAQAAAA==.Katiebeary:BAAALgAECgUJBQAAAA==.',
Ke='Kelthera:BAAALgAECgEJAQAAAA==.Kelumbria:BAAALgAECggJDQAAAA==.Keta:BAAALgADCgYJBgAAAA==.Ketameanie:BAABLgAECn8uAAIIAAkJQBc2JQAjAgAIAAkJQBc2JQAjAgAAAA==.',
Ki='Kieran:BAAALgAECgQJCgAAAA==.Killerkitten:BAAALgADCgEJAQAAAA==.Kitsunè:BAAALgAECgEJAQAAAA==.',
Km='Kmazing:BAABLgAECn8nAAMhAAkJBA5GIQCOAQAhAAkJBA5GIQCOAQABAAMJIRCEaQChAAAAAA==.',
Kn='Knifèparty:BAAALgAECgMJAwAAAA==.',
Ko='Konoha:BAABLgAECn8sAAMVAAkJzyAmBQAgAwAVAAkJwh8mBQAgAwAaAAMJfiPoQwApAQAAAA==.',
Ku='Kultag:BAABLgAECn8bAAIgAAkJHBSpPgDzAQAgAAkJHBSpPgDzAQAAAA==.',
Ky='Kyaw:BAABLgAECn8WAAQOAAYJbRyAKAC2AQAOAAYJbRyAKAC2AQAYAAIJxRJbFgCTAAAZAAEJPRT9HgA6AAAAAA==.Kynzo:BAABLgAECn8/AAIEAAkJKR62AwC4AgAEAAkJKR62AwC4AgAAAA==.',
La='Laykeezenith:BAACLgAFFH8UAAQkAAYJJh0rBwCrAQAkAAYJmxorBwCrAQAPAAMJ7SL3ZQCeAAAQAAEJvQc0LgBFAAAuAAQKfx8ABCQACQmZIl4VAIcCACQACAnqIl4VAIcCAA8ACAm9IfMxAP0BABAAAgl3EgooAHUAAAAA.Lazuli:BAABLgAECn9BAAIlAAkJORUFGwDwAQAlAAkJORUFGwDwAQAAAA==.',
Le='Lehann:BAABLgAECn8rAAIPAAkJxw8KQADKAQAPAAkJxw8KQADKAQAAAA==.',
Li='Lichtech:BAAALgAECgYJDQABLgAFFAcJHQADAFEcAA==.Lightsbane:BAAALgAECgcJDAAAAA==.',
Lu='Luciselda:BAAALgADCgUJBgAAAA==.Lumosnox:BAAALgADCgMJAwAAAA==.Lunariah:BAAALgADCgkJEwAAAA==.Luvtarhugar:BAAALgADCgMJAwAAAA==.',
Ma='Madaran:BAAALgAECgEJAgABLgAECgcJEQAHAAAAAA==.Magdalene:BAEALgAECgUJCQABLgAFFAQJDgAdAK4SAA==.Marenus:BAABLgAECn9HAAIPAAkJQRHUPADVAQAPAAkJQRHUPADVAQAAAA==.Masume:BAAALgAECgcJDwAAAA==.Maély:BAAALgAECgEJAgAAAA==.',
Me='Mechadead:BAAALgADCggJCAAAAA==.Medal:BAAALgADCgYJCAAAAA==.Meowmix:BAAALgADCgcJDAAAAA==.',
Mi='Miantha:BAAALgAECgYJBwAAAA==.Michi:BAABLgAECn82AAMSAAkJgyKyAwB5AwASAAkJgyKyAwB5AwAEAAYJLBaAFQBIAQAAAA==.Midnights:BAAALgAECggJEAAAAA==.Mightymopo:BAAALgADCgMJAwAAAA==.Mikuki:BAABLgAECn8jAAIPAAkJvCMfDwDEAgAPAAkJvCMfDwDEAgAAAA==.Milkinghands:BAABLgAECn8hAAMBAAkJ1g/GMgB9AQABAAkJ1g/GMgB9AQAhAAEJlAKvogAjAAAAAA==.Mizmonk:BAACLgAFFH8ZAAIKAAYJSBhMDwCCAQAKAAYJSBhMDwCCAQAuAAQKfyIAAgoACQnxHqMJAO4CAAoACQnxHqMJAO4CAAAA.',
Mj='Mjölnir:BAAALgAECgEJAQAAAA==.',
Mo='Montfort:BAAALgADCggJDwAAAA==.Moovover:BAAALgAECggJCgAAAA==.',
Ms='Msmaho:BAAALgAECgYJCgAAAA==.',
Mu='Murionor:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgAECgYJBgAAAA==.',
My='Mykian:BAABLgAECn8pAAMjAAkJAQclDwAIAQADAAkJ0QTyPgANAQAjAAcJ1QclDwAIAQAAAA==.Myrwynn:BAAALgAECgMJAwABLgAECgkJOQAWAGIZAA==.Mythlee:BAAALgAECgUJCAAAAA==.Mythundon:BAAALgADCgUJBQAAAA==.',
Na='Nahion:BAAALgAECgYJCQAAAA==.Nashira:BAABLgAECn8gAAIPAAkJVBNqNAD0AQAPAAkJVBNqNAD0AQAAAA==.Nathalas:BAAALgAECgEJAgABLgAECgkJPwAOACwkAA==.Nature:BAAALgAECgUJCwAAAA==.',
Ne='Necrana:BAAALgADCgEJAQAAAA==.Necrobyarg:BAAALgAECgYJDQAAAA==.Nemasus:BAABLgAECn84AAISAAgJrB21EwCbAgASAAgJrB21EwCbAgAAAA==.Nembie:BAAALgADCgMJAwAAAA==.Nethertech:BAAALgAFFAMJAwABLgAFFAcJHQADAFEcAA==.',
Ni='Ninjahh:BAACLgAFFH8IAAIOAAUJswucHAAVAQAOAAUJswucHAAVAQAuAAQKfyYAAg4ACAnxFfgVANcBAA4ACAnxFfgVANcBAAAA.Niobei:BAAALgADCgcJBwABLgAECgkJQAAfAJwYAA==.Nioshei:BAABLgAECn9AAAIfAAkJnBgNEwCbAgAfAAkJnBgNEwCbAgAAAA==.Nisara:BAACLgAFFH8HAAIBAAMJTBPiLgCyAAABAAMJTBPiLgCyAAAuAAQKfzEAAwEACQndHlIPAIwCAAEACQndHlIPAIwCACEACAlsHwMLAH4CAAAA.',
No='Nochmuerta:BAABLgAECn8ZAAIRAAkJRRnGJABdAgARAAkJRRnGJABdAgAAAA==.Nogrid:BAABLgAECn9JAAIMAAkJFxqpBgBjAgAMAAkJFxqpBgBjAgAAAA==.Nossaria:BAAALgAECgIJAgAAAA==.Notmyface:BAAALgAECgcJEwABLgAECgcJMAANACkmAA==.',
Nu='Nuthar:BAABLgAECn84AAIgAAcJfyVBHgB5AgAgAAcJfyVBHgB5AgAAAA==.',
Ny='Nyxandra:BAAALgAECgQJBAAAAA==.',
['Né']='Nésta:BAAALgAECgEJAQAAAA==.',
['Nò']='Nòhva:BAAALgAECgQJBAAAAA==.',
Ol='Oldeis:BAAALgAECgEJAQAAAA==.',
Om='Ominousowl:BAAALgAFFAMJBAAAAA==.',
Or='Oregizm:BAAALgAFFAEJAQAAAA==.Orneryosprey:BAAALgAFFAEJAQABLgAFFAIJBAAHAAAAAA==.',
Pa='Pamburu:BAABLgAECn8jAAQPAAgJ8w3kagBUAQAPAAgJpg3kagBUAQAkAAYJvgVhHQCvAAAQAAIJrQUPKgBgAAAAAA==.Papagrape:BAABLgAECn9CAAQCAAkJxSANAgBSAwACAAkJxSANAgBSAwADAAMJaRZ0UQDCAAAjAAMJAhRPFQCnAAAAAA==.Parzivàl:BAABLgAECn8mAAIUAAgJehiaEwB1AgAUAAgJehiaEwB1AgAAAA==.Paxa:BAABLgAECn8qAAMaAAcJbB3BFwD6AQAaAAcJbB3BFwD6AQAWAAYJTgsiQADrAAAAAA==.',
Pe='Peacebox:BAAALgADCggJDAABLgAECgkJJwAhAAQOAA==.Persayis:BAAALgAECgYJCgAAAA==.',
Ph='Phoebel:BAAALgADCgkJEgAAAA==.Phoenixbodhi:BAAALgAECgQJBAAAAA==.',
Pi='Pickledeggs:BAAALgAECgEJAQABLgAECggJGQALAPEXAA==.',
Po='Podnov:BAACLgAFFH8WAAMkAAUJkiD0CwBtAQAkAAUJkiD0CwBtAQAPAAIJpB23awCWAAAuAAQKfyMAAiQACQlEHcwNANYCACQACQlEHcwNANYCAAAA.Pollyanna:BAAALgADCgEJAQAAAA==.',
Pr='Preyon:BAAALgAECgUJEgABLgAECgcJGgAKAN8NAA==.',
Py='Pyne:BAAALgADCgEJAQAAAA==.Pyrista:BAAALgAECgkJDAAAAA==.',
Qa='Qang:BAAALgAECgYJBwAAAA==.',
Qo='Qotho:BAABLgAECn9IAAIPAAkJYhtXIQBJAgAPAAkJYhtXIQBJAgAAAA==.',
Ra='Raikou:BAAALgAECgUJBQABLgAFFAYJHAAWAH8iAA==.Raistliin:BAAALgAECgYJDgAAAA==.Raithis:BAACLgAFFH8XAAIPAAUJLx0EKgBCAQAPAAUJLx0EKgBCAQAuAAQKfzEAAg8ACQl4IcAEAEEDAA8ACQl4IcAEAEEDAAAA.Raito:BAAALgADCgUJBQAAAA==.Ramhadin:BAEALgAECgMJCgABLgAECggJKAAWAJsdAA==.Ramzert:BAEALgAECgIJAgABLgAECggJKAAWAJsdAA==.',
Re='Rednaxel:BAABLgAECn9AAAMOAAkJ4CQDAgA4AwAOAAkJeCQDAgA4AwAYAAUJRx+iBwDIAQAAAA==.Redvelvet:BAABLgAECn8nAAMBAAkJqBX9GAArAgABAAkJqBX9GAArAgAhAAQJ9Ab5WwCgAAAAAA==.Rekoner:BAABLgAECn8mAAIRAAkJRxMmQADwAQARAAkJRxMmQADwAQAAAA==.Resi:BAAALgAECgIJAgAAAA==.Resii:BAAALgAECgEJAgABLgAECgIJAgAHAAAAAA==.Retarganator:BAABLgAECn9PAAMIAAkJ7R3zFACHAgAIAAkJUR3zFACHAgAmAAQJjBjREgAlAQAAAA==.',
Ri='Ringmistress:BAAALgADCgcJBwAAAA==.Rixaa:BAAALgADCgQJBQABLgAECgcJGwAPACMdAA==.',
Ro='Rocks:BAAALgAECgYJCAAAAA==.Romam:BAAALgAECgYJCQAAAA==.',
Ru='Rubyknight:BAAALgAECgEJAQAAAA==.',
Ry='Rydran:BAAALgAECgQJBQAAAA==.Rykria:BAAALgAECgMJAwAAAA==.',
Sa='Samsonknight:BAAALgADCgYJBgAAAA==.Sanguinarian:BAABLgAECn8XAAIgAAgJIQ0yoQAaAQAgAAgJIQ0yoQAaAQAAAA==.Savash:BAAALgAECggJEgAAAA==.',
Sc='Scrubtotem:BAAALgAECgMJAwAAAA==.',
Se='Secksiecutie:BAABLgAECn8yAAMiAAkJ7hoJBABsAgAiAAkJ7hoJBABsAgAFAAcJPQyXKQDxAAAAAA==.Selanda:BAAALgAECgMJAwAAAA==.Serinar:BAAALgAFFAMJAwAAAA==.',
Sh='Shoshin:BAABLgAECn8aAAMKAAcJ3w3DRgDQAAAKAAcJ3w3DRgDQAAAhAAQJJgxhXQCbAAAAAA==.Shïvana:BAAALgAECgMJDwAAAA==.',
Si='Silversaiyan:BAABLgAECn9JAAMNAAgJqSF4DACPAgANAAgJqSF4DACPAgAnAAEJXRiEOgBGAAAAAA==.',
Sl='Slade:BAABLgAECn8/AAMOAAkJLCSfAgAeAwAOAAkJLCSfAgAeAwAYAAMJ+xs5EgDvAAAAAA==.Slap:BAAALgAECgEJAQAAAA==.Sliyce:BAAALgAECgIJBgAAAA==.',
Sm='Smóke:BAABLgAECn9JAAIIAAkJKxWkMADtAQAIAAkJKxWkMADtAQAAAA==.',
Sn='Snore:BAAALgADCgQJBgAAAA==.Snowfawn:BAABLgAECn8jAAIPAAgJuRQUPADYAQAPAAgJuRQUPADYAQABLgAFFAIJAgAHAAAAAA==.',
So='Sofedan:BAABLgAECn9JAAIkAAkJMA+sCgCqAQAkAAkJMA+sCgCqAQAAAA==.Sorgath:BAAALgAECgIJAgAAAA==.Soriel:BAABLgAECn8oAAIKAAkJOw+eHACuAQAKAAkJOw+eHACuAQAAAA==.Sorokwa:BAABLgAECn8XAAIRAAkJKgLa4wC0AAARAAkJKgLa4wC0AAAAAA==.',
Sq='Squids:BAAALgADCgQJBAAAAA==.',
St='Strongstork:BAAALgAECgEJAgABLgAFFAIJBAAHAAAAAA==.',
Su='Sunsword:BAAALgAECgYJEQAAAA==.Suriden:BAAALgAECgYJBwAAAA==.',
Sw='Swagidan:BAABLgAECn8sAAIGAAgJoxgAEgBMAgAGAAgJoxgAEgBMAgAAAA==.Sweatermonk:BAAALgADCgIJAgABLgAECgYJBgAHAAAAAA==.Sweaterpally:BAAALgAECgYJBgAAAA==.Swiftera:BAABLgAECn8kAAIUAAkJIxaEKADqAQAUAAkJIxaEKADqAQAAAA==.Swiftlier:BAABLgAECn8tAAIKAAkJtxnaEwAAAgAKAAkJtxnaEwAAAgAAAA==.Swipegirl:BAAALgAECgYJCQAAAA==.',
Sy='Sybelyyia:BAAALgAECgUJBgAAAA==.Sylphrène:BAABLgAECn8yAAIGAAkJIwdpIwA4AQAGAAkJIwdpIwA4AQAAAA==.',
Ta='Taladan:BAAALgAECgQJBQAAAA==.Tandrana:BAAALgAECgMJBAAAAA==.Tankmepapi:BAAALgAECgMJAwAAAA==.Tanwen:BAABLgAECn8UAAQCAAYJ+QdXIwC/AAACAAYJ+QdXIwC/AAAjAAQJHAMENwBfAAADAAIJAAKfiQAoAAAAAA==.Targypunch:BAAALgADCgcJBwABLgAECgkJTwAIAO0dAA==.Tatsunoshinn:BAAALgADCgEJAQAAAA==.',
Te='Techniqe:BAACLgAFFH8dAAMDAAcJURxZDADwAQADAAcJURxZDADwAQACAAEJrwETKQA1AAAuAAQKfzUAAwMACAkkIxsHAAoDAAMACAkkIxsHAAoDACMABgkgIe8SALMBAAAA.Techtides:BAAALgADCgUJBQABLgAFFAcJHQADAFEcAA==.Temperance:BAAALgADCgEJAQAAAA==.Temptations:BAAALgAECgUJBgAAAA==.Terminus:BAAALgAECgcJCQAAAA==.Terrylin:BAAALgAECgYJBwAAAA==.',
Th='Thaliá:BAAALgADCgkJFQAAAA==.Themachinist:BAAALgAECgYJBgAAAA==.Thomag:BAAALgADCgIJAgAAAA==.Thor:BAAALgAECgIJAgAAAA==.',
Ti='Tiaracy:BAAALgAECgcJCAAAAA==.Ticebane:BAACLgAFFH8PAAMFAAUJ8QhAHwDGAAAFAAUJ8QhAHwDGAAARAAIJfwHW2ABnAAAuAAQKfyMAAgUACQk0GbALAFgCAAUACQk0GbALAFgCAAAA.Tiduspullo:BAABLgAECn8qAAMgAAkJmhuTRAAWAgAgAAkJdxWTRAAWAgAMAAUJoRqiFgBRAQAAAA==.Tiduswar:BAABLgAECn8fAAMXAAcJ2BpSFgCqAQAXAAcJ2BpSFgCqAQANAAIJfRJfdQByAAABLgAECgkJKgAgAJobAA==.Tinafay:BAAALgAECgcJDAAAAA==.Titanbeard:BAAALgAECgEJAwAAAA==.Titor:BAABLgAECn8qAAMCAAcJxhkGDAAEAgACAAcJxhkGDAAEAgAjAAUJeQ5OEgDSAAAAAA==.Tituspullo:BAAALgAECgcJCgABLgAECgkJKgAgAJobAA==.',
To='Tolduan:BAAALgAECgUJDQAAAA==.Totemik:BAAALgAECgcJEQAAAA==.Toughturkey:BAAALgAFFAIJBAAAAA==.Towen:BAAALgADCgMJAwAAAA==.Toy:BAAALgADCgYJEgAAAA==.',
Tr='Tremorhoof:BAAALgADCgIJAwAAAA==.Tresera:BAAALgADCgEJAQAAAA==.Tricarnetry:BAABLgAECn8cAAIgAAcJ+gw9lgAsAQAgAAcJ+gw9lgAsAQAAAA==.Trufleshufle:BAAALgAECggJEQAAAA==.',
Uh='Uhtread:BAAALgADCgYJBQAAAA==.',
Ul='Ulfer:BAAALgAECgUJBQABLgAECgkJRAAFAPEkAA==.',
Un='Unholyfury:BAAALgADCgYJBgAAAA==.',
Va='Vapor:BAAALgAECgQJBQAAAA==.Vaquinha:BAAALgADCgUJBQAAAA==.Varyel:BAAALgAECgIJAgAAAA==.',
Ve='Velianne:BAAALgADCgUJBQAAAA==.Vellinada:BAAALgADCgMJAwABLgAFFAYJGgAaABklAA==.Verakis:BAABLgAECn9AAAIXAAkJLRfzCwAXAgAXAAkJLRfzCwAXAgAAAA==.Verndarí:BAABLgAECn8XAAMFAAkJwQzPGwBhAQAFAAkJwQzPGwBhAQAiAAMJzgUoKABYAAABLgAECgkJLQAKALcZAA==.Verudora:BAAALgAECgUJBgAAAA==.Vervain:BAAALgAECgUJBQAAAA==.',
Vo='Vonnie:BAAALgADCgkJCQAAAA==.Vortheus:BAAALgAECgkJEwAAAA==.Votollis:BAAALgAECgQJBQAAAA==.',
Wa='Warlanen:BAAALgAECgUJBgAAAA==.Warning:BAAALgADCgUJBQAAAA==.Warpiggies:BAAALgADCgkJCAAAAA==.',
Wi='Widdy:BAAALgAECgcJEAAAAA==.Willbur:BAABLgAECn9JAAILAAkJVxoFJwBpAgALAAkJVxoFJwBpAgAAAA==.Wittledwagon:BAAALgADCgkJCQAAAA==.',
Wu='Wurthwhile:BAAALgAECgYJDgAAAA==.',
Wy='Wylaniris:BAAALgADCgQJBAAAAA==.Wyndywalker:BAABLgAECn8vAAIeAAgJCgiBNwAbAQAeAAgJCgiBNwAbAQAAAA==.',
Xa='Xaveil:BAAALgADCgEJAQAAAA==.',
Xe='Xenosian:BAAALgAECgkJCQAAAA==.',
Xi='Xinnuo:BAAALgAECgQJBQAAAA==.',
Xy='Xydias:BAAALgAECggJDwAAAA==.Xyra:BAAALgADCgcJBwAAAA==.',
Yo='Yoku:BAAALgAECggJEwAAAA==.',
Za='Zag:BAAALgAECgEJAQABLgAECgkJMAAmALYWAA==.Zalgarian:BAAALgAECgYJCgAAAA==.Zamønk:BAABLgAECn8ZAAMKAAcJFg8WOABqAQAKAAcJFg8WOABqAQAhAAIJ+wyGhgA4AAAAAA==.Zaphoidvtwo:BAAALgAECgQJBAAAAA==.Zason:BAAALgADCgMJAwAAAA==.Zatari:BAAALgADCgMJAwAAAA==.Zavaen:BAAALgADCgEJAQAAAA==.',
Ze='Zelectie:BAABLgAECn8XAAIJAAgJbhcyCgD3AQAJAAgJbhcyCgD3AQABLgAFFAcJEQAFALMQAA==.Zelzaikin:BAAALgAECgQJBgAAAA==.Zevon:BAAALgAECgYJBgAAAA==.',
Zi='Ziarra:BAAALgADCgYJBgABLgADCgcJDQAHAAAAAA==.Zinazarinara:BAAALgADCgkJFwAAAA==.Zirril:BAAALgADCgcJDwAAAA==.',
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
