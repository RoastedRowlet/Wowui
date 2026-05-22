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

local lookup = {'Evoker-Preservation','Evoker-Augmentation','Druid-Feral','DeathKnight-Blood','DemonHunter-Havoc','Unknown-Unknown','DemonHunter-Devourer','Druid-Guardian','Monk-Brewmaster','Mage-Frost','Warrior-Fury','Rogue-Subtlety','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Unholy','Druid-Restoration','Shaman-Enhancement','Paladin-Holy','Paladin-Protection','Priest-Discipline','Priest-Shadow','Warrior-Protection','Rogue-Assassination','Rogue-Outlaw','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Balance','Shaman-Restoration','Paladin-Retribution','Monk-Windwalker','DeathKnight-Frost','Evoker-Devastation','Monk-Mistweaver','Hunter-Marksmanship','Shaman-Elemental','DemonHunter-Vengeance','Warrior-Arms',}
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=46,date='2026-05-16',data={Ac='Acefu:BAAALgAECgYJDQAAAA==.Acorneo:BAAALgAFFAQJBAABLgAFFAQJDAABALMNAA==.Acornita:BAACLgAFFH8MAAMBAAQJsw1aEQCsAAABAAMJ5w9aEQCsAAACAAIJXwLZPQBvAAAuAAQKfyoAAwEACQnlD0YRACgCAAEACQnlD0YRACgCAAIABwlIEgokAJ0BAAAA.',
Ae='Aelana:BAAALgADCgkJCQAAAA==.',
Ai='Ailanthus:BAABLgAECn8cAAIDAAcJwg4gEgA0AQADAAcJwg4gEgA0AQAAAA==.',
Ak='Akinira:BAEBLgAECn88AAIEAAkJkh7ZAwByAgAEAAkJkh7ZAwByAgAAAA==.',
Al='Aleinadris:BAAALgADCgQJBAAAAA==.Alikchi:BAAALgADCgEJAgAAAA==.Alloisaber:BAAALgAECgYJCAAAAA==.Alternis:BAAALgAECgMJAwAAAA==.',
An='Andrelsia:BAAALgAECgYJCQAAAA==.Andrilla:BAAALgAECgMJAwAAAA==.Ankeseth:BAAALgADCgkJEwAAAA==.',
Ap='Apôllyon:BAACLgAFFH8MAAIFAAMJASTHCgDOAAAFAAMJASTHCgDOAAAuAAQKfywAAgUACQmeJfAAAL4DAAUACQmeJfAAAL4DAAAA.',
Ar='Aracelis:BAAALgAECgcJBwAAAA==.Aradius:BAAALgAECgEJAgABLgAECgIJBgAGAAAAAA==.Archertower:BAAALgADCgUJBQAAAA==.Artemiswynd:BAAALgADCgYJBgAAAA==.Arén:BAABLgAECn8hAAMHAAgJfx9iIwD+AQAHAAcJvB5iIwD+AQAFAAcJhx+YGwDkAQAAAA==.',
As='Ashenshugär:BAAALgAECgQJBQAAAA==.',
Av='Avadda:BAABLgAECn8YAAIIAAcJthE8EgBPAQAIAAcJthE8EgBPAQABLgAECggJFQAJAHsJAA==.',
Az='Azmar:BAABLgAECn8eAAIKAAgJ9h8pIgBYAgAKAAgJ9h8pIgBYAgAAAA==.',
Ba='Badffinger:BAAALgADCgYJBgAAAA==.Balain:BAAALgAECgEJAQABLgAECgYJFwAJAEoPAA==.',
Be='Bearmont:BAAALgAECgYJDQAAAA==.Bearzerk:BAABLgAECn8iAAILAAgJ3hPsIACdAQALAAgJ3hPsIACdAQAAAA==.Beastmonk:BAAALgADCgEJAQAAAA==.Benathar:BAABLgAECn8fAAIKAAcJ7A0xdABUAQAKAAcJ7A0xdABUAQAAAA==.',
Bi='Bifrost:BAAALgAECgUJBQAAAA==.Bionico:BAAALgAECgUJCgAAAA==.Birgir:BAAALgAECgEJAQAAAA==.',
Bl='Blackmagék:BAAALgADCgcJBwAAAA==.Blazer:BAAALgADCggJCAAAAA==.Bloodrager:BAAALgADCgIJAgAAAA==.Bloodthorn:BAABLgAECn8aAAIMAAgJJgaUIgAiAQAMAAgJJgaUIgAiAQAAAA==.Blortimor:BAAALgADCgcJBwAAAA==.',
Bo='Bombad:BAAALgAECgYJDQAAAA==.Boomnescient:BAAALgAECgYJDgAAAA==.Bortt:BAAALgADCgkJCQAAAA==.Bozscaggs:BAABLgAECn8uAAMNAAkJjQ95LgDTAQANAAkJjQ95LgDTAQAOAAUJAwMFMwC6AAAAAA==.',
Br='Bramis:BAAALgADCgkJHAAAAA==.Brantu:BAAALgADCgQJCAABLgADCgkJDwAGAAAAAA==.Braultus:BAABLgAECn8rAAIEAAkJKBx9BwAaAgAEAAkJKBx9BwAaAgAAAA==.Breyastrasza:BAAALgADCgMJAwAAAA==.Bruinn:BAAALgAECgQJBAABLgAECgYJFwAJAEoPAA==.',
Bu='Burstangel:BAAALgAECgUJBwAAAA==.',
By='Byrddh:BAAALgADCgQJBAAAAA==.',
Ca='Cadenza:BAAALgAECgMJAwAAAA==.Caliopedk:BAACLgAFFH8HAAMEAAIJrRgKIwBYAAAPAAIJrRjjOACqAAAEAAIJqAIKIwBYAAAuAAQKfxsAAw8ACAlIIWUhALsCAA8ACAlIIWUhALsCAAQABQlJDjQqAO0AAAAA.Capra:BAAALgAECgMJAwAAAA==.Carillanklip:BAAALgADCgUJBQAAAA==.',
Cd='Cdmickey:BAAALgADCgUJBQAAAA==.',
Ce='Celestè:BAAALgAECggJEQAAAA==.Celéste:BAAALgAECgkJEAAAAA==.Cerdwin:BAAALgAECggJDAABLgAECgkJMgAQAKUWAA==.',
Ch='Charferad:BAAALgAECgMJAwAAAA==.Cheaptrick:BAAALgADCgcJDQAAAA==.Chibeard:BAABLgAECn8hAAIJAAgJeCIzBgCjAgAJAAgJeCIzBgCjAgAAAA==.Chonglin:BAAALgADCgMJAwAAAA==.',
Cl='Clearcast:BAAALgADCgkJCQAAAA==.Clubsdh:BAAALgAECgEJAQAAAA==.',
Co='Coolbro:BAAALgADCgIJAgAAAA==.Corialis:BAAALgAECgkJEgAAAA==.Counsel:BAAALgAECgUJBQAAAA==.',
Cr='Crom:BAABLgAECn8pAAIRAAgJvAwwDgBeAQARAAgJvAwwDgBeAQAAAA==.Crosis:BAAALgADCgYJBgAAAA==.Cruelladvoid:BAAALgAECgQJBAAAAA==.Cruush:BAAALgAECgYJBQAAAA==.',
Cu='Culerro:BAAALgAECgYJAwABLgAECgYJBQAGAAAAAA==.Cursive:BAAALgADCgUJDQAAAA==.',
Cy='Cygnes:BAABLgAECn8bAAIPAAgJrhtILwD9AQAPAAgJrhtILwD9AQAAAA==.',
Da='Daddywarrior:BAAALgADCgUJBgAAAA==.Daeva:BAAALgADCgEJAQAAAA==.Dantey:BAAALgADCgcJEgAAAA==.Daus:BAAALgAFFAEJAQAAAA==.Dazanna:BAABLgAECn8nAAMSAAgJXRf8FwD9AQASAAgJXRf8FwD9AQATAAUJTAtjJwCLAAAAAA==.Dazre:BAAALgAECgUJBgAAAA==.',
De='Deeminor:BAAALgADCgkJEwAAAA==.Desktop:BAABLgAECn8qAAMUAAgJxRgNDwAoAgAUAAgJxRgNDwAoAgAVAAUJxQ1eOgDWAAAAAA==.',
Di='Diod:BAABLgAECn8qAAIWAAgJDxbJEQB9AQAWAAgJDxbJEQB9AQAAAA==.Divineßovine:BAAALgADCgcJBwAAAA==.',
Do='Doomtheory:BAAALgADCgMJAwAAAA==.',
Dr='Dracovoid:BAAALgADCgUJBQAAAA==.Draegyns:BAAALgAECgIJAgABLgAFFAQJCwAXALwUAA==.Draehton:BAAALgAECgYJBwAAAA==.Dragyns:BAACLgAFFH8LAAIXAAQJvBTmAgBQAQAXAAQJvBTmAgBQAQAuAAQKfy8ABBcACQngG4ECAMoCABcACQmvGYECAMoCAAwABgmMGz8sAJwBABgAAwmrFFIJANwAAAAA.Dragynseye:BAAALgADCgIJAgABLgAFFAQJCwAXALwUAA==.Drayper:BAABLgAECn8YAAMZAAcJch/nCwBdAgAZAAcJch/nCwBdAgAUAAEJZw3AWQAvAAAAAA==.Druugal:BAACLgAFFH8KAAIMAAMJhBqKFwAAAQAMAAMJhBqKFwAAAQAuAAQKfy0AAwwACAlVIkYMANQCAAwACAlVIkYMANQCABcAAQl6C+ofADMAAAAA.',
Du='Dubs:BAABLgAECn8hAAQaAAgJhhyORwCHAQAaAAUJ9RyORwCHAQAbAAIJ7BlHGwCSAAAcAAIJwxt2KgBKAAAAAA==.Dunbarke:BAAALgAECgYJEAAAAA==.',
Ef='Efishient:BAABLgAECn8eAAIQAAYJWCRKGAA8AgAQAAYJWCRKGAA8AgABLgAFFAYJGQAQAH8TAA==.',
El='Elisoria:BAAALgAECgMJAwAAAA==.Elliwynd:BAABLgAECn8hAAIQAAgJIQ3fPwBLAQAQAAgJIQ3fPwBLAQAAAA==.',
Eo='Eoshot:BAAALgAECgUJCAAAAA==.',
Er='Erinnys:BAABLgAECn8iAAMFAAgJWg6TFwBhAQAFAAgJWg6TFwBhAQAHAAYJsgWPlgDvAAAAAA==.Ermoril:BAAALgAECgQJBQAAAA==.Ernesta:BAAALgADCgcJCAAAAA==.',
Eu='Eufemia:BAAALgAECgYJCQAAAA==.',
['Eø']='Eøs:BAAALgAECgEJAQAAAA==.',
Fa='Famine:BAAALgAECgcJDAAAAA==.',
Fe='Felern:BAAALgAECgUJBwABLgAECggJHgAKAPYfAA==.Feyrun:BAAALgADCgkJEwAAAA==.Feyrè:BAAALgADCgQJBQAAAA==.',
Fi='Finalomega:BAAALgAECgYJCwAAAA==.',
Fl='Flaminfalcon:BAABLgAFFH8FAAIVAAIJQBifGgC+AAAVAAIJQBifGgC+AAAAAA==.Flody:BAAALgAECgYJDAAAAA==.',
Fo='Foxflame:BAABLgAECn8yAAMQAAkJpRYnFwBHAgAQAAkJpRYnFwBHAgAdAAcJMAyhLAAZAQAAAA==.',
Fr='Franzen:BAAALgAECgEJAQAAAA==.Freakbob:BAAALgADCgYJCQAAAA==.Froglocky:BAABLgAECn8mAAMcAAgJ7hZSBgCxAQAcAAgJ7hZSBgCxAQAaAAMJcwRi9ABwAAAAAA==.Fronsac:BAAALgADCgQJBAAAAA==.',
Fu='Fulanita:BAABLgAECn8XAAMdAAYJDA6oNADtAAAdAAYJDA6oNADtAAAQAAIJSwosnABGAAAAAA==.',
Ga='Gallager:BAAALgADCgMJAwAAAA==.Garzok:BAABLgAECn8fAAMcAAgJpApYCgBNAQAcAAgJpApYCgBNAQAaAAMJzQHnCAFLAAAAAA==.',
Ge='Genkithered:BAABLgAECn8mAAIeAAgJQBolFQBPAgAeAAgJQBolFQBPAgAAAA==.',
Gi='Gilaras:BAAALgADCgIJAgAAAA==.Gilernil:BAAALgAECgQJCAAAAA==.',
Gl='Gladtohelp:BAAALgAECgIJAgAAAA==.',
Gn='Gnoquarter:BAAALgADCgIJAgAAAA==.',
Gr='Gravemarks:BAABLgAECn8YAAMYAAgJqBNNBgChAQAYAAgJqBNNBgChAQAXAAQJzAncEQDoAAAAAA==.Grimhorn:BAABLgAECn8UAAMdAAUJuAWGSgCNAAAdAAUJuAWGSgCNAAAIAAEJywDKUAAMAAAAAA==.Grimlie:BAAALgADCgkJDwAAAA==.Grimmrock:BAAALgAECgMJAwAAAA==.Grumblen:BAAALgADCgMJAwAAAA==.',
Gu='Guaritrice:BAAALgAECgUJBwAAAA==.Gubb:BAAALgAECgMJAwAAAA==.',
Gw='Gwenylane:BAABLgAECn8kAAIfAAkJPAkSVQCDAQAfAAkJPAkSVQCDAQAAAA==.Gwindor:BAAALgAECgYJCQAAAA==.Gwyndelyn:BAABLgAECn8oAAIgAAgJjAtkJAA8AQAgAAgJjAtkJAA8AQAAAA==.',
Ha='Hatterus:BAABLgAECn8vAAIfAAgJWQorcQBCAQAfAAgJWQorcQBCAQAAAA==.',
He='Herculeze:BAAALgAECgYJCQAAAA==.Hessian:BAAALgADCgEJAQAAAA==.Hetairoi:BAAALgAECgIJAgABLgAECgQJDQAGAAAAAA==.Hetd:BAAALgAECgEJAgAAAA==.',
Hi='Hillbroken:BAABLgAECn83AAIhAAkJ6iCsAQC3AgAhAAkJ6iCsAQC3AgAAAA==.',
Ho='Holycross:BAAALgAECgIJAgAAAA==.Holysmokers:BAAALgAECgYJCwABLgAFFAQJCwAXALwUAA==.Holysnow:BAAALgADCgkJDAABLgAECgcJGAANABoNAA==.Holysoul:BAAALgAECgEJAQAAAA==.',
Hu='Huntertidus:BAAALgAECggJCgABLgAECgkJJgAfAGYVAA==.',
['Hà']='Hànks:BAABLgAECn8UAAIfAAgJNAz1ZQBaAQAfAAgJNAz1ZQBaAQAAAA==.',
Im='Imo:BAABLgAECn8kAAMaAAgJNRLoWABWAQAaAAcJhxHoWABWAQAbAAUJIhJJHACJAAAAAA==.',
In='Intrepidz:BAAALgAECgEJAgABLgAFFAIJBQAVAEAYAA==.Inèvitable:BAABLgAECn8wAAIPAAkJHR0iFwB7AgAPAAkJHR0iFwB7AgAAAA==.',
Is='Istara:BAAALgADCggJDQAAAA==.',
Ja='Javeech:BAABLgAECn8aAAMNAAgJdxbNRgB2AQANAAcJhhjNRgB2AQAOAAEJGwrVTAA0AAAAAA==.',
Je='Jebib:BAAALgAECgYJBgABLgAFFAgJKQAQACAdAA==.Jeod:BAAALgAECgYJCQAAAA==.',
Jo='Jolty:BAACLgAFFH8PAAIPAAQJJR59JgANAQAPAAQJJR59JgANAQAuAAQKfykAAw8ACQlWIq8MADUDAA8ACQlWIq8MADUDAAQABAmgFuEgAOUAAAAA.',
Ka='Kaiou:BAAALgADCgMJBgAAAA==.Kantor:BAABLgAECn83AAIZAAkJVxdKEAAeAgAZAAkJVxdKEAAeAgAAAA==.Karboomkin:BAAALgAECgcJBwABLgAFFAYJFAAfALIiAA==.Karnstein:BAABLgAECn8cAAQBAAcJDQnuMwDOAAABAAUJgwTuMwDOAAACAAYJvgzJRADEAAAiAAEJlA0+HQA0AAAAAA==.Kasenko:BAAALgAECgIJAgABLgAECgYJDgAGAAAAAA==.Kasryna:BAAALgAECgYJDgAAAA==.Kathinja:BAABLgAECn8dAAINAAgJnQj9UQBUAQANAAgJnQj9UQBUAQAAAA==.',
Ke='Kelumbria:BAAALgAECggJDQAAAA==.Keta:BAAALgADCgYJBgAAAA==.Ketameanie:BAABLgAECn8iAAIHAAgJ7hewLADNAQAHAAgJ7hewLADNAQAAAA==.',
Ki='Kieran:BAAALgAECgQJCgAAAA==.Kitsunè:BAAALgAECgEJAQAAAA==.',
Km='Kmazing:BAABLgAECn8cAAMgAAgJZww2IwBEAQAgAAgJZww2IwBEAQAjAAIJRAQzaQA9AAAAAA==.',
Kn='Knifèparty:BAAALgAECgMJAwAAAA==.',
Ko='Konoha:BAABLgAECn8nAAMUAAgJ/SGuBQDkAgAUAAgJziCuBQDkAgAZAAMJfiPoQwApAQAAAA==.',
Ku='Kultag:BAAALgAECggJEAAAAA==.',
Ky='Kyaw:BAABLgAECn8UAAQMAAYJbRyAKAC2AQAMAAYJbRyAKAC2AQAXAAIJxRJbFgCTAAAYAAEJPRSdFwA8AAAAAA==.Kynzo:BAABLgAECn8xAAIDAAkJNBmKBABmAgADAAkJNBmKBABmAgAAAA==.',
La='Laykeezenith:BAACLgAFFH8UAAQkAAYJJh0rBwCrAQAkAAYJmxorBwCrAQANAAMJ7SIxRACuAAAOAAEJvQeFIgBOAAAuAAQKfx8ABCQACQmZIl4VAIcCACQACAnqIl4VAIcCAA0ACAm9IVojAAgCAA4AAgl3EgooAHUAAAAA.Lazuli:BAABLgAECn8yAAIlAAgJrBUkHACsAQAlAAgJrBUkHACsAQAAAA==.',
Le='Lehann:BAABLgAECn8rAAINAAkJxg/ILgDRAQANAAkJxg/ILgDRAQAAAA==.',
Li='Lichtech:BAAALgAECgYJDQABLgAFFAYJGQACANAbAA==.',
Lu='Luciselda:BAAALgADCgUJBgAAAA==.Lunariah:BAAALgADCgkJEwAAAA==.Luvtarhugar:BAAALgADCgMJAwAAAA==.',
Ma='Magdalene:BAEALgAECgUJCQABLgAFFAQJDAAcAFsRAA==.Marenus:BAABLgAECn81AAINAAkJIxGaLwDOAQANAAkJIxGaLwDOAQAAAA==.Masume:BAAALgAECgYJCAAAAA==.Maély:BAAALgAECgEJAgAAAA==.',
Me='Mechadead:BAAALgADCgIJAgAAAA==.Medal:BAAALgADCgYJBgAAAA==.Meowmix:BAAALgADCgcJCgAAAA==.',
Mi='Miantha:BAAALgAECgUJBgAAAA==.Michi:BAABLgAECn8vAAIQAAkJgyKgAgB7AwAQAAkJgyKgAgB7AwAAAA==.Midnights:BAAALgAECggJDwAAAA==.Mightymopo:BAAALgADCgMJAwAAAA==.Mikuki:BAABLgAECn8dAAINAAkJWCKiDQDRAgANAAkJWCKiDQDRAgAAAA==.Milkinghands:BAABLgAECn8cAAMjAAkJvg+0JQCFAQAjAAkJvg+0JQCFAQAgAAEJlAL6gQAlAAAAAA==.Mizmonk:BAACLgAFFH8WAAIJAAUJEhsFEABNAQAJAAUJEhsFEABNAQAuAAQKfyIAAgkACQnxHqMJAO4CAAkACQnxHqMJAO4CAAAA.',
Mj='Mjölnir:BAAALgAECgEJAQAAAA==.',
Mo='Montfort:BAAALgADCggJDwAAAA==.Moovover:BAAALgAECggJCgAAAA==.',
Ms='Msmaho:BAAALgAECgMJAwAAAA==.',
Mu='Murionor:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgADCgcJBwAAAA==.',
My='Mykian:BAABLgAECn8gAAMiAAgJ8wb9CwARAQAiAAcJ1Qf9CwARAQACAAMJqgLlbQAzAAAAAA==.Myrwynn:BAAALgAECgMJAwABLgAECggJKwAVAHMZAA==.Mythundon:BAAALgADCgUJBQAAAA==.',
Na='Nahion:BAAALgAECgYJCQAAAA==.Nashira:BAABLgAECn8eAAINAAgJ6xFlQACNAQANAAgJ6xFlQACNAQAAAA==.Nature:BAAALgAECgUJCwAAAA==.',
Ne='Necrana:BAAALgADCgEJAQAAAA==.Necrobyarg:BAAALgAECgYJDQAAAA==.Nemasus:BAABLgAECn8mAAIQAAgJZR1/DwCXAgAQAAgJZR1/DwCXAgAAAA==.Nembie:BAAALgADCgMJAwAAAA==.',
Ni='Ninjahh:BAACLgAFFH8GAAIMAAUJUAaKFgAKAQAMAAUJUAaKFgAKAQAuAAQKfx0AAgwACAmHFTITALYBAAwACAmHFTITALYBAAAA.Nioshei:BAABLgAECn8tAAIeAAgJUxVYHQAMAgAeAAgJUxVYHQAMAgAAAA==.Nisara:BAABLgAECn8mAAMjAAgJXiCDCgCpAgAjAAgJXiCDCgCpAgAgAAcJiBpeFQC8AQAAAA==.',
No='Nochmuerta:BAABLgAECn8YAAIPAAkJdxWDKwAMAgAPAAkJdxWDKwAMAgAAAA==.Nogrid:BAABLgAECn83AAITAAkJrBeQBgAqAgATAAkJrBeQBgAqAgAAAA==.Nossaria:BAAALgAECgIJAgAAAA==.Notmyface:BAAALgAECgcJEgABLgAECgcJKQALACMmAA==.',
Nu='Nuthar:BAABLgAECn8oAAIfAAcJ4CSQGABxAgAfAAcJ4CSQGABxAgAAAA==.',
Ny='Nyxandra:BAAALgAECgMJAwAAAA==.',
['Nò']='Nòhva:BAAALgAECgQJBAAAAA==.',
Ol='Oldeis:BAAALgAECgEJAQAAAA==.',
Om='Ominousowl:BAAALgAFFAIJAgABLgAFFAIJBQAVAEAYAA==.',
Or='Oregizm:BAAALgAFFAEJAQAAAA==.',
Pa='Pamburu:BAABLgAECn8jAAQNAAgJ8w1DUQBWAQANAAgJpw1DUQBWAQAkAAYJvgXsGACQAAAOAAIJrQUPKgBgAAAAAA==.Papagrape:BAABLgAECn8vAAQBAAgJeyIkAgAeAwABAAgJeyIkAgAeAwAiAAIJ4wzDGgA/AAACAAEJUgyAYgAyAAAAAA==.Parzivàl:BAABLgAECn8mAAISAAgJehiaEwB1AgASAAgJehiaEwB1AgAAAA==.Paxa:BAABLgAECn8jAAMZAAcJKh1KEgAEAgAZAAcJKh1KEgAEAgAVAAQJgwpQRwCVAAAAAA==.',
Pe='Peacebox:BAAALgADCggJDAABLgAECggJHAAgAGcMAA==.Persayis:BAAALgAECgMJAwAAAA==.',
Ph='Phoebel:BAAALgADCgkJEgAAAA==.Phoenixbodhi:BAAALgAECgQJBAAAAA==.',
Pi='Pickledeggs:BAAALgADCgEJAQABLgAECgUJCwAGAAAAAA==.',
Po='Podnov:BAACLgAFFH8RAAMkAAQJNB1BCQBVAQAkAAQJ/RxBCQBVAQANAAIJpB3XSgCgAAAuAAQKfyMAAiQACQlHHcwNANYCACQACQlHHcwNANYCAAAA.Pollyanna:BAAALgADCgEJAQAAAA==.',
Pr='Preyon:BAAALgAECgUJCgABLgAECgYJFwAJAEoPAA==.',
Py='Pyne:BAAALgADCgEJAQAAAA==.Pyrista:BAAALgAECgkJDAAAAA==.',
Qo='Qotho:BAABLgAECn82AAINAAkJuBl0GQBBAgANAAkJuBl0GQBBAgAAAA==.',
Ra='Raistliin:BAAALgAECgYJDgAAAA==.Raithis:BAACLgAFFH8WAAINAAUJLx1cFABaAQANAAUJLx1cFABaAQAuAAQKfzEAAg0ACQl4IcAEAEEDAA0ACQl4IcAEAEEDAAAA.Ramhadin:BAEALgAECgMJBAABLgAECgYJHAAVAHoeAA==.',
Re='Rednaxel:BAABLgAECn8tAAMMAAgJoiK9BwBlAgAMAAgJoiK9BwBlAgAXAAUJnhlnBwCZAQAAAA==.Redvelvet:BAABLgAECn8lAAMjAAgJkxdWFAALAgAjAAgJkxdWFAALAgAgAAQJggb5WwCgAAAAAA==.Rekoner:BAABLgAECn8gAAIPAAgJAhDpUQCIAQAPAAgJAhDpUQCIAQAAAA==.Resi:BAAALgAECgEJAQAAAA==.Resii:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.Retarganator:BAABLgAECn8zAAMHAAgJbRxeHQAhAgAHAAgJuhteHQAhAgAmAAQJjBjREgAlAQAAAA==.',
Ri='Rixaa:BAAALgADCgMJAwABLgAECgcJFAANAJwXAA==.',
Ro='Rocks:BAAALgAECgYJCAAAAA==.Romam:BAAALgAECgYJCQAAAA==.',
Ru='Rubyknight:BAAALgAECgEJAQAAAA==.',
Ry='Rydran:BAAALgAECgEJAQAAAA==.Rykria:BAAALgADCgkJHQAAAA==.',
Sa='Samsonknight:BAAALgADCgYJBgAAAA==.Sanguinarian:BAABLgAECn8XAAIfAAgJIA12fQAqAQAfAAgJIA12fQAqAQAAAA==.Savash:BAAALgAECggJCwAAAA==.',
Sc='Scrubtotem:BAAALgAECgMJAwAAAA==.',
Se='Secksiecutie:BAABLgAECn8nAAMhAAgJhxqJBQDlAQAhAAgJhxqJBQDlAQAEAAUJdQvQLQCRAAAAAA==.Selanda:BAAALgADCgkJGgAAAA==.Serinar:BAAALgAECgUJDAAAAA==.',
Sh='Shoshin:BAABLgAECn8XAAMJAAYJSg/SSAChAAAJAAYJSg/SSAChAAAgAAQJJgxhXQCbAAAAAA==.Shïvana:BAAALgAECgMJDAAAAA==.',
Si='Silversaiyan:BAABLgAECn84AAMLAAgJqSGrCgB2AgALAAgJqSGrCgB2AgAnAAEJXRiEOgBGAAAAAA==.',
Sl='Slade:BAABLgAECn81AAMMAAkJNyNTAgD9AgAMAAkJNyNTAgD9AgAXAAMJ+xraDwDkAAAAAA==.Slap:BAAALgAECgEJAQAAAA==.Sliyce:BAAALgAECgIJBgAAAA==.',
Sm='Smóke:BAABLgAECn83AAIHAAkJHRQlLwDCAQAHAAkJHRQlLwDCAQAAAA==.',
Sn='Snowfawn:BAAALgAECgYJEwABLgAECgcJGAANABoNAA==.',
So='Sofedan:BAABLgAECn83AAIkAAkJhA5jCABsAQAkAAkJhA5jCABsAQAAAA==.Sorgath:BAAALgAECgIJAgAAAA==.Soriel:BAABLgAECn8VAAIJAAgJewmmKQArAQAJAAgJewmmKQArAQAAAA==.Sorokwa:BAABLgAECn8XAAIPAAkJKgImtwC6AAAPAAkJKgImtwC6AAAAAA==.',
Sq='Squids:BAAALgADCgQJBAAAAA==.',
St='Strongstork:BAAALgAECgEJAgABLgAECgQJDQAGAAAAAA==.',
Su='Sunsword:BAAALgAECgYJEQAAAA==.Suriden:BAAALgAECgYJBwAAAA==.',
Sw='Swagidan:BAABLgAECn8iAAIFAAgJkxgAEgBMAgAFAAgJkxgAEgBMAgAAAA==.Sweatermonk:BAAALgADCgIJAgABLgAECgYJBgAGAAAAAA==.Sweaterpally:BAAALgAECgYJBgAAAA==.Swiftera:BAABLgAECn8iAAISAAkJZhWEKADqAQASAAkJZhWEKADqAQAAAA==.Swiftlier:BAABLgAECn8hAAIJAAgJtxn6GQCaAQAJAAgJtxn6GQCaAQABLgAECgkJFwAEAMEMAA==.Swipegirl:BAAALgAECgYJCQAAAA==.',
Sy='Sylphrène:BAABLgAECn8gAAIFAAgJmQY5IAAQAQAFAAgJmQY5IAAQAQAAAA==.',
Ta='Taladan:BAAALgAECgQJBQAAAA==.Tandrana:BAAALgAECgMJAwAAAA==.Tankmepapi:BAAALgAECgMJAwAAAA==.Tanwen:BAAALgAECgYJEAAAAA==.Targypunch:BAAALgADCgcJBwABLgAECggJMwAHAG0cAA==.Tatsunoshinn:BAAALgADCgEJAQAAAA==.',
Te='Techniqe:BAACLgAFFH8ZAAMCAAYJ0BumCgCyAQACAAYJ0BumCgCyAQABAAEJrwE5IgA2AAAuAAQKfzQAAwIACAkkIxsHAAoDAAIACAkkIxsHAAoDACIABgkgIe8SALMBAAAA.Techtides:BAAALgADCgUJBQABLgAFFAYJGQACANAbAA==.Temperance:BAAALgADCgEJAQAAAA==.Temptations:BAAALgAECgUJBgAAAA==.Terminus:BAAALgAECgEJAQAAAA==.Terrylin:BAAALgAECgUJBgAAAA==.',
Th='Thaliá:BAAALgADCgkJFQAAAA==.Themachinist:BAAALgAECgYJBgAAAA==.Thomag:BAAALgADCgIJAgAAAA==.',
Ti='Tiaracy:BAAALgAECgEJAQAAAA==.Ticebane:BAACLgAFFH8MAAMEAAQJqAjMFQDbAAAEAAQJqAjMFQDbAAAPAAIJfwHBsQA3AAAuAAQKfyMAAgQACQk0GbALAFgCAAQACQk0GbALAFgCAAAA.Tiduspullo:BAABLgAECn8mAAMfAAkJZhWTRAAWAgAfAAkJIBWTRAAWAgATAAMJKRMIKgB5AAAAAA==.Tiduswar:BAABLgAECn8fAAMWAAcJ2BoNFABgAQAWAAcJ2BoNFABgAQALAAIJfRJzYAByAAABLgAECgkJJgAfAGYVAA==.Tinafay:BAAALgAECgcJDAAAAA==.Titanbeard:BAAALgAECgEJAgAAAA==.Titor:BAABLgAECn8cAAMBAAcJ1BlDDQCzAQABAAYJERlDDQCzAQAiAAUJeQ6wDgDdAAAAAA==.Tituspullo:BAAALgAECgUJBgABLgAECgkJJgAfAGYVAA==.',
To='Tolduan:BAAALgAECgUJDQAAAA==.Totemik:BAAALgAECgQJBgAAAA==.Toughturkey:BAAALgAECgQJDQAAAA==.Toy:BAAALgADCgYJBgAAAA==.',
Tr='Tremorhoof:BAAALgADCgIJAwAAAA==.Tresera:BAAALgADCgEJAQAAAA==.Tricarnetry:BAABLgAECn8UAAIfAAcJPQa/qADeAAAfAAcJPQa/qADeAAAAAA==.Trufleshufle:BAAALgAECggJEQAAAA==.',
Uh='Uhtread:BAAALgADCgYJBQAAAA==.',
Ul='Ulfer:BAAALgADCgkJCQAAAA==.',
Un='Unholyfury:BAAALgADCgYJBgAAAA==.',
Va='Vapor:BAAALgAECgQJBQAAAA==.Vaquinha:BAAALgADCgUJBQAAAA==.Varyel:BAAALgAECgIJAgAAAA==.',
Ve='Velianne:BAAALgADCgUJBQAAAA==.Vellinada:BAAALgADCgMJAwABLgAFFAQJFAAZAPceAA==.Verakis:BAABLgAECn8tAAIWAAgJJRURDwCqAQAWAAgJJRURDwCqAQAAAA==.Verndarí:BAABLgAECn8XAAMEAAkJwQxZFQBMAQAEAAkJwQxZFQBMAQAhAAMJzgU4GgBuAAAAAA==.Vervain:BAAALgAECgUJBQAAAA==.',
Vo='Vonnie:BAAALgADCgkJCQAAAA==.Vortheus:BAAALgAECgQJCgAAAA==.Votollis:BAAALgAECgQJBQAAAA==.',
Wa='Warlanen:BAAALgAECgUJBgAAAA==.Warning:BAAALgADCgUJBQAAAA==.Warpiggies:BAAALgADCgkJCAAAAA==.',
Wi='Widdy:BAAALgAECgcJEAAAAA==.Willbur:BAABLgAECn83AAIKAAkJFRhlJABMAgAKAAkJFRhlJABMAgAAAA==.Wittledwagon:BAAALgADCgkJCQAAAA==.',
Wu='Wurthwhile:BAAALgAECgYJCAAAAA==.',
Wy='Wylaniris:BAAALgADCgQJBAAAAA==.Wyndywalker:BAABLgAECn8jAAIdAAgJVQfXLQASAQAdAAgJVQfXLQASAQAAAA==.',
Xa='Xaveil:BAAALgADCgEJAQAAAA==.',
Xe='Xenosian:BAAALgAECgkJCQAAAA==.',
Xi='Xinnuo:BAAALgAECgIJAQAAAA==.',
Xy='Xydias:BAAALgAECggJDwAAAA==.Xyra:BAAALgADCgcJBwAAAA==.',
Yo='Yoku:BAAALgAECggJEwAAAA==.',
Za='Zag:BAAALgADCgcJBwABLgAECgkJLwAmALgWAA==.Zalgarian:BAAALgAECgMJAwAAAA==.Zamønk:BAABLgAECn8YAAMJAAcJFg8WOABqAQAJAAcJFg8WOABqAQAgAAIJYAx6bgBXAAAAAA==.Zaphoidvtwo:BAAALgADCgcJBwAAAA==.Zason:BAAALgADCgMJAwAAAA==.Zatari:BAAALgADCgMJAwAAAA==.',
Ze='Zelectie:BAABLgAECn8XAAIIAAgJbhcyCgD3AQAIAAgJbhcyCgD3AQABLgAFFAYJFQAJADgcAA==.Zelzaikin:BAAALgAECgQJBgAAAA==.Zevon:BAAALgADCgkJCQAAAA==.',
Zi='Ziarra:BAAALgADCgYJBgABLgADCgcJDQAGAAAAAA==.Zinazarinara:BAAALgADCgkJFAAAAA==.Zirril:BAAALgADCgcJDwAAAA==.',
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
