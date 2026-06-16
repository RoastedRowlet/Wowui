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

local lookup = {'Warlock-Demonology','Paladin-Retribution','Warlock-Destruction','Warrior-Protection','DeathKnight-Unholy','Priest-Holy','DemonHunter-Devourer','Warrior-Fury','Rogue-Assassination','Paladin-Holy','Paladin-Protection','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Restoration','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Blood','Warrior-Arms','DemonHunter-Vengeance','DemonHunter-Havoc','Mage-Frost','Priest-Shadow','Shaman-Elemental','Monk-Mistweaver','Evoker-Devastation','Druid-Restoration','DeathKnight-Frost','Druid-Balance','Unknown-Unknown','Mage-Arcane','Evoker-Augmentation','Druid-Guardian','Evoker-Preservation','Mage-Fire','Priest-Discipline','Druid-Feral','Hunter-Survival','Rogue-Subtlety',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=46,date='2026-06-14',data={Ab='Abharn:BAAALgAECgYJDQAAAA==.',
Ag='Agoneer:BAAALgAECgQJBwAAAA==.',
Ak='Akeera:BAABLgAECn8VAAIBAAcJUA6UiwAjAQABAAcJUA6UiwAjAQAAAA==.Akkiya:BAAALgAECgYJDwABLgAFFAYJFgACAGMUAA==.',
Al='Althtar:BAAALgADCgQJBAAAAA==.',
Am='Amalyn:BAAALgAECgYJCAAAAA==.Amarantha:BAABLgAECn8mAAMDAAkJGgl+GwDGAAADAAcJDwd+GwDGAAABAAYJPQkq4gCXAAAAAA==.',
An='Anaesthetize:BAAALgAECgYJCAAAAA==.Aness:BAABLgAECn8hAAIEAAgJagNBLQDOAAAEAAgJagNBLQDOAAAAAA==.Angelinalizy:BAAALgAECgMJAwAAAA==.Animagon:BAAALgAECgQJBgAAAA==.Animaker:BAABLgAECn8vAAIFAAkJDBYlPwAEAgAFAAkJDBYlPwAEAgAAAA==.Anngus:BAAALgAECgEJAQAAAA==.Anvilkrash:BAAALgADCgcJCwAAAA==.',
Ar='Ariese:BAAALgADCgcJCAAAAA==.',
As='Ashido:BAABLgAECn8WAAIGAAYJJhwhHwDIAQAGAAYJJhwhHwDIAQAAAA==.Astreos:BAABLgAFFH8NAAIBAAUJOR0EQgBDAQABAAUJOR0EQgBDAQABLgAFFAgJHgAHAO8dAA==.Astrikin:BAAALgAECgYJDwABLgAFFAgJHgAHAO8dAA==.',
Au='Auraiel:BAAALgADCgcJFAAAAA==.Aurhon:BAAALgAECgYJDAAAAA==.Aurorastar:BAAALgAECgEJAQAAAA==.',
Ba='Bagawgwah:BAAALgAECgEJAwAAAA==.Baluu:BAAALgAECgQJBAAAAA==.Baultier:BAAALgADCgkJDgAAAA==.',
Be='Bel:BAABLgAECn89AAIEAAkJACXzAQAwAwAEAAkJACXzAQAwAwAAAA==.Beraxes:BAABLgAECn8pAAIIAAkJixFHIgDgAQAIAAkJixFHIgDgAQAAAA==.Bethäny:BAAALgAECgQJAQAAAA==.',
Bl='Blasser:BAABLgAECn8fAAIJAAkJ6BrMBAA9AgAJAAkJ6BrMBAA9AgAAAA==.Blizizdumz:BAACLgAFFH8MAAMCAAQJQBEMSAAYAQACAAQJQBEMSAAYAQAKAAEJEQrbSQAyAAAuAAQKfzgABAIACQmZHmgeAI8CAAIACQmFHWgeAI8CAAsABgm7Ij4SAKABAAoAAQmYAr6eAB8AAAAA.',
Bm='Bmcgilicuddy:BAAALgAECgYJCwAAAA==.',
Br='Bralindra:BAAALgAECgEJAgAAAA==.Breadpitt:BAAALgAECggJEQAAAA==.Brewdhism:BAAALgAECgMJAwAAAA==.Brillane:BAAALgAECgQJBwAAAA==.',
Bu='Bulsy:BAACLgAFFH8VAAMMAAUJdR5nLgBOAQAMAAUJdR5nLgBOAQANAAEJcgGUOwAsAAAuAAQKfyQAAwwACQnwHa4TALICAAwACQnwHa4TALICAA0ABAmQBOtoAJsAAAAA.',
Ca='Calamidade:BAABLgAECn8rAAMOAAkJfQRsGwAiAQAOAAkJfQRsGwAiAQAPAAMJdwEX0AA4AAAAAA==.Calashlar:BAAALgAECgIJBQAAAA==.Camri:BAAALgADCgMJAwAAAA==.Capwnd:BAAALgAECgMJAwAAAA==.',
Ce='Cerryan:BAABLgAECn81AAIKAAkJQBF8IQD2AQAKAAkJQBF8IQD2AQAAAA==.Cexar:BAABLgAECn8aAAIIAAcJjA3LQABCAQAIAAcJjA3LQABCAQAAAA==.',
Ch='Chaoticprime:BAAALgAECgEJAQAAAA==.Charivium:BAAALgADCgQJBAAAAA==.Charo:BAABLgAECn8lAAMQAAkJPSFzBgDjAgAQAAgJOiRzBgDjAgARAAgJCRHTJACFAQAAAA==.Chaòs:BAAALgADCgMJAwAAAA==.Chinup:BAABLgAECn82AAISAAkJQCE3CQB+AgASAAkJQCE3CQB+AgAAAA==.',
Cl='Clother:BAACLgAFFH8YAAMIAAUJQSRLBACwAQAIAAUJ7RhLBACwAQATAAUJQST3AQBkAQAuAAQKfxoAAwgACAkEIfYKAAQDAAgACAkEIfYKAAQDABMABgnmIGEHAEkCAAEuAAUUBgkUAAUAkB0A.',
Co='Cokenopepsi:BAABLgAECn8ZAAISAAgJiB4MEgDrAQASAAgJiB4MEgDrAQAAAA==.Cole:BAAALgAFFAEJAQAAAA==.Cormigo:BAAALgAECgcJCgAAAA==.',
Cr='Crackle:BAAALgADCgcJDAAAAA==.Crazyhorse:BAAALgAECgYJCwAAAA==.Cristos:BAAALgADCgYJCwAAAA==.Crusade:BAAALgADCgYJBgAAAA==.',
Cu='Curses:BAAALgAECggJEAABLgAECgkJGAACAE0TAA==.',
['Cø']='Cøløssus:BAAALgAECgEJAQAAAA==.',
Da='Daddypie:BAABLgAECn8+AAQUAAkJ0iQZAQAyAwAUAAkJ0iQZAQAyAwAVAAEJdR32YABIAAAHAAEJ7AzSCgE8AAAAAA==.Damasscus:BAAALgAECgcJDQAAAA==.Darkdesire:BAAALgADCgUJBQAAAA==.',
De='Deathkanight:BAAALgAECgQJBQAAAA==.Desdakharii:BAAALgAECgEJAQAAAA==.',
Di='Diktug:BAAALgAECgMJAwAAAA==.Disney:BAABLgAECn8WAAIJAAcJshLOCgCDAQAJAAcJshLOCgCDAQAAAA==.',
Dj='Djaztech:BAACLgAFFH8OAAMIAAUJCh8QEACAAQAIAAUJCh8QEACAAQATAAQJgxJZGwAKAQAuAAQKfyYAAwgACQnFIpERAGgCAAgACAnxIZERAGgCABMABwlQGg4SANQBAAAA.',
Do='Donkie:BAABLgAECn8gAAIMAAgJUxxnKwAtAgAMAAgJUxxnKwAtAgAAAA==.',
Dr='Dracsano:BAAALgAFFAIJAgAAAA==.Dreadhunter:BAAALgAECgMJAwAAAA==.Dreamzz:BAAALgADCgMJAwAAAA==.Drixadin:BAAALgAECgQJBwAAAA==.Drshockêr:BAACLgAFFH8OAAIPAAQJpRl5KwAwAQAPAAQJpRl5KwAwAQAuAAQKf1MAAw8ACQlnIhgEAHYDAA8ACQlnIhgEAHYDAA4ACAmeDPoWAFEBAAAA.',
Ds='Dsakony:BAABLgAECn8WAAIWAAkJZhRNmwBBAQAWAAkJZhRNmwBBAQAAAA==.',
Du='Dunthat:BAAALgAECgUJBQAAAA==.Duskdruid:BAAALgAECgUJBQABLgAFFAYJBwASAHYiAA==.Duthir:BAACLgAFFH8NAAIFAAMJRxQ4mQDYAAAFAAMJRxQ4mQDYAAAuAAQKfywAAgUACQldHc8/ADkCAAUACQldHc8/ADkCAAEuAAUUBgkPABcADxQA.',
Dy='Dyte:BAAALgAECgEJAQAAAA==.',
Ea='East:BAAALgAECgYJEwAAAA==.',
Ed='Edd:BAAALgAECgEJAQAAAA==.',
Eg='Egrok:BAABLgAECn8ZAAIYAAcJVhJdOgBKAQAYAAcJVhJdOgBKAQAAAA==.',
Em='Emaeel:BAABLgAECn8fAAQZAAkJfBKsOACKAQAZAAgJqRCsOACKAQAQAAgJOQ8rLQBWAQARAAQJJgRBXgCUAAAAAA==.Emporia:BAAALgAFFAEJAgAAAA==.',
En='Enhae:BAAALgAECgQJBAAAAA==.Envyqt:BAAALgADCgEJAQAAAA==.',
Er='Erissel:BAAALgAECgcJCgAAAA==.',
Es='Esso:BAACLgAFFH8WAAMFAAYJgxXXMQCYAQAFAAUJgxXXMQCYAQASAAEJAABjWAAAAAAuAAQKfxcAAgUABwmNFvaDAFoBAAUABwmNFvaDAFoBAAAA.',
Fa='Faelenor:BAAALgAECgYJCAAAAA==.Faelure:BAABLgAECn8cAAICAAgJ/QmxuAARAQACAAgJ/QmxuAARAQAAAA==.',
Fe='Feyed:BAAALgAECgEJAgAAAA==.',
Fi='Fiddleoux:BAAALgAECgYJEAAAAA==.Fiending:BAAALgAECgEJAQAAAA==.Finnarius:BAAALgADCgYJBgAAAA==.Firenze:BAAALgAECgYJDgAAAA==.Fizzlewar:BAAALgADCgIJAgABLgAFFAQJDAACAEARAQ==.',
Fo='Foros:BAABLgAECn8sAAIKAAkJxCRbBgAmAwAKAAkJxCRbBgAmAwAAAA==.',
Fr='Frozone:BAABLgAECn8kAAIWAAgJWhg4VADdAQAWAAgJWhg4VADdAQAAAA==.Fryiertuck:BAAALgAECgYJCgAAAA==.',
Ga='Gabil:BAABLgAECn80AAIaAAkJcQnaCgBqAQAaAAkJcQnaCgBqAQAAAA==.Gaunshots:BAAALgAECgQJBwABLgAECgkJGAACAE0TAA==.',
Ge='Gendorosan:BAABLgAECn80AAIbAAkJmyHbBQBYAwAbAAkJmyHbBQBYAwAAAA==.',
Gh='Ghoran:BAAALgAECgEJAQAAAA==.',
Gn='Gnork:BAAALgAECgcJEQABLgAFFAMJBgAbALsIAA==.',
Go='Goldwolf:BAAALgAECgYJBwAAAA==.Gotarrnianan:BAAALgAECgEJBAAAAA==.Gothpally:BAAALgAECgQJBAAAAA==.',
Gr='Grandmasterx:BAAALgAECgIJAwAAAA==.Graveworm:BAAALgAECgEJAgAAAA==.Gravewurm:BAAALgAECgEJAQAAAA==.Grayfoxx:BAABLgAECn80AAIFAAkJaxosKwBSAgAFAAkJaxosKwBSAgAAAA==.Grayhard:BAAALgAECgYJBwAAAA==.Greenhornn:BAAALgAECgkJCQAAAA==.Grìmmgor:BAACLgAFFH8TAAIcAAQJTSKrAAA2AQAcAAQJTSKrAAA2AQAuAAQKfysAAhwACQmDIkwAAIgDABwACQmDIkwAAIgDAAAA.',
Gu='Guerriera:BAAALgAECggJDwAAAA==.Gulkenn:BAAALgADCgcJBwAAAA==.',
['Gô']='Gôôdbye:BAAALgAECggJEAAAAA==.',
['Gö']='Gööse:BAABLgAECn8fAAICAAkJXxAMUwDPAQACAAkJXxAMUwDPAQAAAA==.',
Ha='Hado:BAAALgAECgQJBAAAAA==.Halbrand:BAACLgAFFH8IAAIFAAIJTBJZ1gCIAAAFAAIJTBJZ1gCIAAAuAAQKfxwAAgUACAmDGyNQANEBAAUACAmDGyNQANEBAAEuAAUUBgkQAB0AHBQA.Hamburgmeat:BAAALgADCgYJBQAAAA==.',
He='Healovathyme:BAACLgAFFH8IAAIbAAIJqSDjPAC4AAAbAAIJqSDjPAC4AAAuAAQKfxoAAhsACAlxIugVAIcCABsACAlxIugVAIcCAAAA.Hellstomper:BAAALgAECgQJDgAAAA==.Heygrlhey:BAACLgAFFH8FAAIMAAMJuhTEWQDrAAAMAAMJuhTEWQDrAAAuAAQKfz8AAwwACQmeI1cMAO4CAAwACQmeI1cMAO4CAA0ABAlHB7RgAL4AAAAA.',
Hi='Hidaoushi:BAAALgADCgkJCQAAAA==.',
Ho='Holdstillbro:BAAALgADCgEJAQABLgAECgkJNgASAEAhAA==.',
Hu='Hukkaluzul:BAAALgAECgEJAQAAAA==.Humaladin:BAAALgAECgEJAQAAAA==.Humanpaladin:BAABLgAECn8YAAMCAAkJTRNqXAC4AQACAAgJ8xNqXAC4AQALAAgJcwkdIgABAQAAAA==.Hungryghost:BAAALgAECgkJCwAAAA==.Hunna:BAABLgAECn8dAAIMAAgJxxrjPQDmAQAMAAgJxxrjPQDmAQAAAA==.Hurtzdonit:BAAALgAFFAIJAgAAAA==.',
Hv='Hvtn:BAAALgAECgYJEAAAAA==.',
Ic='Icyfractals:BAAALgADCgQJBQAAAA==.',
In='Inebriated:BAABLgAECn8bAAIMAAgJIgvKfgA+AQAMAAgJIgvKfgA+AQAAAA==.',
Io='Iondia:BAAALgAECgQJCgAAAA==.',
Is='Iselune:BAAALgAECgIJAgAAAA==.',
It='Itwítçh:BAAALgAECgEJAwAAAA==.',
Iz='Izanami:BAAALgAECgEJAQAAAA==.',
Ja='Jambi:BAAALgAECgcJDQAAAA==.Jandrina:BAAALgADCgYJCgAAAA==.Jaraxxus:BAAALgADCgcJBwAAAA==.Jardran:BAAALgAECgEJAgAAAA==.',
Jo='Joanchokkea:BAAALgADCgcJDgAAAA==.Joankorel:BAAALgADCgkJCQAAAA==.Johnconnor:BAAALgADCgYJCgAAAA==.Jolty:BAAALgAECgcJCAABLgAFFAYJGQAFAFEgAA==.',
['Jê']='Jêanne:BAAALgAECgcJDwAAAA==.',
Ka='Kael:BAAALgAECgYJDAAAAA==.Kahira:BAEALgADCgQJBAAAAA==.Kalidra:BAAALgAECgQJBQAAAA==.Kaname:BAAALgADCgYJCQABLgAECgUJEAAeAAAAAA==.',
Ke='Kenpashi:BAAALgADCgYJBgAAAA==.Kermitted:BAAALgAECgEJAgABLgAECgYJCQAeAAAAAA==.',
Ki='Kirlo:BAAALgADCgcJDQAAAA==.Kittytiddies:BAAALgADCgUJBQAAAA==.',
Ko='Kobethama:BAAALgAECgEJBQAAAA==.Kohnan:BAABLgAECn8UAAIHAAgJ2ggHkQD7AAAHAAgJ2ggHkQD7AAABLgAFFAIJAgAeAAAAAA==.Kotoko:BAABLgAECn8nAAIPAAkJvB7ECQAVAwAPAAkJvB7ECQAVAwAAAA==.',
Kr='Kring:BAAALgAECggJCgAAAA==.',
Ks='Ksauce:BAABLgAECn8oAAIfAAkJ0wN2CgDbAAAfAAkJ0wN2CgDbAAAAAA==.',
Ku='Kungfumama:BAAALgAECgEJAQAAAA==.',
Ky='Kynan:BAACLgAFFH8QAAICAAQJaRNLQwAhAQACAAQJaRNLQwAhAQAuAAQKfyUAAwIACAmFGqFCAP0BAAIACAmFGqFCAP0BAAsAAQmfA6FdABMAAAEuAAQKBAkEAB4AAAAA.Kynon:BAABLgAECn8ZAAMQAAYJbRTOMABjAQAQAAYJbRTOMABjAQAZAAEJLgFmdwAUAAABLgAECgQJBAAeAAAAAA==.Kyran:BAAALgAECgQJBAAAAA==.',
La='Laerai:BAAALgADCgcJDAAAAA==.Lament:BAABLgAECn8UAAIHAAgJQxp5LQAPAgAHAAgJQxp5LQAPAgAAAA==.Lamurun:BAAALgAECgQJBAAAAA==.Lancelöt:BAACLgAFFH8JAAICAAQJ0yCwLABXAQACAAQJ0yCwLABXAQAuAAQKf0cAAgIACQloJNAIACIDAAIACQloJNAIACIDAAAA.Lastra:BAAALgAECgkJEgABLgAECgcJGAAHAGMZAA==.Lathina:BAAALgAECgYJCQAAAA==.Lavendere:BAAALgAECgYJEgABLgAFFAYJDwAXAA8UAA==.',
Le='Lectra:BAAALgAECgIJAgAAAA==.Leechang:BAAALgADCgMJAwAAAA==.',
Li='Liiam:BAAALgADCgYJBgAAAA==.Linafox:BAABLgAECn8rAAIWAAkJrgshagClAQAWAAkJrgshagClAQAAAA==.Linnëa:BAABLgAFFH8HAAMSAAMJ6hI8KACwAAASAAMJ6hI8KACwAAAFAAEJUASBGwE1AAAAAA==.Linta:BAAALgADCgcJCQAAAA==.Lizardwizard:BAABLgAECn8XAAIgAAgJQRGAMAB0AQAgAAgJQRGAMAB0AQAAAA==.',
Ll='Llonia:BAAALgADCgMJAwAAAA==.',
Lo='Lockraum:BAAALgAFFAEJAQAAAA==.Lokix:BAABLgAECn82AAIFAAkJNCJ9DQD/AgAFAAkJNCJ9DQD/AgAAAA==.',
Lu='Luexis:BAAALgADCgkJFgAAAA==.Luobo:BAAALgADCgQJBQAAAA==.Lustie:BAAALgADCgMJAwAAAA==.',
Ly='Lysistratta:BAABLgAECn85AAISAAkJdA25HQBoAQASAAkJdA25HQBoAQAAAA==.',
Ma='Magikishi:BAABLgAECn8cAAIWAAgJYR8xOwCKAgAWAAgJYR8xOwCKAgAAAA==.Magimal:BAAALgAECgYJBgABLgAECgkJHwAZAHwSAA==.Mahka:BAACLgAFFH8FAAIbAAMJQwnNSQCQAAAbAAMJQwnNSQCQAAAuAAQKf0gABBsACQkHIEoPANkCABsACQkHIEoPANkCAB0AAwkfI8U+ABEBACEAAgmtDv5aAFUAAAEuAAMKAQkBAB4AAAAA.Mainframe:BAAALgAECgEJAQAAAA==.Maldar:BAAALgAECgIJAgABLgAECgkJHwAZAHwSAA==.Maldrakesus:BAAALgADCgEJAQABLgAECgkJHwAZAHwSAA==.Malifecent:BAAALgAECgMJAwAAAA==.Manthalus:BAAALgAECgIJAgAAAA==.Marquista:BAABLgAECn8XAAICAAcJbA97ngA4AQACAAcJbA97ngA4AQAAAA==.Masika:BAAALgAECgIJAgAAAA==.',
Mc='Mchammer:BAAALgADCgMJAwAAAA==.',
Me='Meatball:BAAALgAECgMJAwAAAA==.Meganstoon:BAAALgAECgMJBAAAAA==.Meladaris:BAAALgAECgQJCwAAAA==.Mey:BAABLgAECn9PAAIGAAkJpRvhCwCnAgAGAAkJpRvhCwCnAgAAAA==.',
Mi='Misfortune:BAAALgADCgUJBQAAAA==.Missperfect:BAAALgAECgcJEQAAAA==.Mitenalla:BAACLgAFFH8WAAICAAYJYxTLJQBsAQACAAYJYxTLJQBsAQAuAAQKfxoAAgIACAm6G/pRANIBAAIACAm6G/pRANIBAAAA.',
Mo='Mokris:BAAALgAECgQJBAAAAA==.Monkrobin:BAAALgAECgEJAQAAAA==.Morninbreath:BAAALgAECgUJBQAAAA==.Mossberger:BAAALgAECgUJBgAAAA==.',
Mu='Muatahawa:BAAALgAECgMJBQAAAA==.Muglackh:BAAALgAECgcJEwAAAA==.',
My='Myoue:BAAALgAECgMJBQAAAA==.Mysticraven:BAABLgAECn8oAAIdAAkJXgfTNwAyAQAdAAkJXgfTNwAyAQAAAA==.Mythbredor:BAAALgAECgYJBgAAAA==.',
Na='Naariah:BAAALgAECgEJAQAAAA==.Nagendra:BAACLgAFFH8RAAIgAAUJjhtXJwAqAQAgAAUJjhtXJwAqAQAuAAQKfx4AAiAACQmYIOgHAPoCACAACQmYIOgHAPoCAAAA.Natharion:BAAALgADCgUJCgAAAA==.',
Ne='Neoptolemos:BAAALgAECgYJCwAAAA==.Nezpak:BAAALgADCgcJEAAAAA==.',
Ni='Nicnevin:BAABLgAECn8zAAIaAAkJZgwFCQCZAQAaAAkJZgwFCQCZAQAAAA==.Nitrochrist:BAABLgAECn9DAAIBAAkJSRbgPADoAQABAAkJSRbgPADoAQAAAA==.Nixxy:BAAALgAECgYJBwABLgAFFAYJFgAiAMARAA==.',
No='Nokansee:BAAALgADCgQJBAAAAA==.Nokimi:BAAALgAECgUJCAAAAA==.Noobru:BAAALgAECgYJDwAAAA==.Nordathair:BAABLgAECn8lAAIgAAkJOw/WJAC2AQAgAAkJOw/WJAC2AQAAAA==.Nori:BAACLgAFFH8wAAMWAAgJUiQhBgDRAgAWAAgJUiQhBgDRAgAjAAIJdiQ7AwDXAAAuAAQKfywAAxYACQm9JpoAAPwDABYACQm9JpoAAPwDAB8AAwkSILcPAMcAAAAA.',
Ob='Oblivion:BAAALgADCgQJBAAAAA==.',
On='Onebuttonman:BAAALgAECgEJAQAAAA==.Onlyfoxes:BAAALgAECgIJAgAAAA==.',
Or='Original:BAACLgAFFH8IAAICAAQJThabOQA0AQACAAQJThabOQA0AQAuAAQKfxgAAgIACAl+IMclAGwCAAIACAl+IMclAGwCAAAA.Originals:BAABLgAFFH8GAAIFAAMJ/w+uoADQAAAFAAMJ/w+uoADQAAAAAA==.',
Ot='Otome:BAABLgAECn8UAAIFAAgJSQnIkgA/AQAFAAgJSQnIkgA/AQAAAA==.',
Ov='Overpoweredd:BAAALgAECggJCQAAAA==.',
Pa='Painfulpoo:BAAALgAECgIJAgAAAA==.Parsemae:BAACLgAFFH8RAAIWAAYJ5RVQNQCVAQAWAAYJ5RVQNQCVAQAuAAQKfyMAAxYACAm2HW0vALQCABYACAm2HW0vALQCACMAAQkdD64QADEAAAAA.Pastries:BAACLgAFFH8eAAIHAAgJ7x1KAgAyAgAHAAgJ7x1KAgAyAgAuAAQKfzcAAwcACQmrIrkCAKUDAAcACQmrIrkCAKUDABUAAgnMFHdOAHgAAAAA.',
Pb='Pbd:BAAALgAECgIJAgAAAA==.',
Pi='Pierce:BAAALgAECgYJBgAAAA==.Pitlin:BAABLgAECn8kAAIkAAkJFiG+BQApAwAkAAkJFiG+BQApAwAAAA==.',
Pm='Pmsavenger:BAAALgADCgkJEgAAAA==.',
Po='Polynya:BAAALgAECgQJCgAAAA==.Pooshot:BAAALgAECgYJCwAAAA==.',
Pr='Priestalisha:BAACLgAFFH8pAAIGAAcJdyTzAADMAgAGAAcJdyTzAADMAgAuAAQKf0oAAgYACQmtJksAAOwDAAYACQmtJksAAOwDAAAA.Prognie:BAAALgADCgcJCAAAAA==.',
Ra='Raelana:BAABLgAECn81AAICAAkJzQkBgABtAQACAAkJzQkBgABtAQAAAA==.Ragetatertot:BAAALgAECgYJDgAAAA==.Ragingpoo:BAABLgAECn8ZAAIFAAkJlxSWRADzAQAFAAkJlxSWRADzAQAAAA==.Rakenroll:BAAALgADCggJCAAAAA==.Rawsteak:BAABLgAECn8iAAISAAkJgh46EAAGAgASAAkJgh46EAAGAgAAAA==.Razdaz:BAABLgAECn8eAAMkAAcJfh3/FQD0AQAkAAYJxhv/FQD0AQAGAAcJUhnkHQDTAQAAAA==.',
Re='Redcrow:BAABLgAECn8WAAIIAAkJsAa+QQA+AQAIAAkJsAa+QQA+AQAAAA==.Reheal:BAABLgAECn8eAAIGAAgJjR1LDgCBAgAGAAgJjR1LDgCBAgAAAA==.Reshocker:BAABLgAECn8tAAIYAAkJghoKGgAPAgAYAAkJghoKGgAPAgAAAA==.Restosexualz:BAAALgAECgMJBAAAAA==.',
Ri='Rixxy:BAACLgAFFH8WAAMiAAYJwBHHCABdAQAiAAYJwBHHCABdAQAgAAEJsAFqagAuAAAuAAQKfzsAAyIACQmsI0UCAFEDACIACQmsI0UCAFEDACAABwmrC8g+AO8AAAAA.',
Ro='Roastbeefdr:BAACLgAFFH8JAAMSAAMJdR7IGwAEAQASAAMJdR7IGwAEAQAFAAEJhh23AQFSAAAuAAQKf00AAxIACQnxJEECAC4DABIACQnxJEECAC4DAAUABAkjH6exABABAAAA.Roderigo:BAABLgAECn8lAAIbAAgJBREIPQCdAQAbAAgJBREIPQCdAQAAAA==.Root:BAAALgAECgYJEQAAAA==.',
Ru='Runian:BAAALgAECgUJCwAAAA==.',
Sa='Sadlypink:BAABLgAECn8XAAIWAAcJLBRKhwDDAQAWAAcJLBRKhwDDAQAAAA==.Saisaith:BAACLgAFFH8PAAMXAAYJDxTtFwAiAQAXAAUJcBXtFwAiAQAGAAEJUgiUMgBJAAAuAAQKfxwAAxcACQlHGVUOAHICABcACQlHGVUOAHICAAYAAQlkBR95AB8AAAAA.Sanarian:BAAALgADCgMJAwAAAA==.Sand:BAACLgAFFH8KAAIFAAUJQxQOMwCUAQAFAAUJQxQOMwCUAQAuAAQKfyQAAgUABwkuFTxoAL0BAAUABwkuFTxoAL0BAAAA.Sandy:BAAALgAECgcJBQAAAA==.Savadar:BAAALgAECgkJEwAAAA==.Saymourcox:BAAALgAECggJDAAAAA==.',
Se='Seadra:BAAALgADCggJDQABLgAECgYJFAALAM4ZAA==.Sealyboi:BAAALgADCgQJBAAAAA==.Serpeng:BAABLgAECn8bAAMVAAgJEBERIwBbAQAVAAgJ1g8RIwBbAQAUAAYJ9QqEGgDGAAAAAA==.Setareh:BAABLgAECn8YAAIWAAgJvwYTqQAqAQAWAAgJvwYTqQAqAQAAAA==.Settra:BAAALgADCgcJDAAAAA==.',
Sh='Shakuru:BAABLgAECn8yAAIWAAkJyw5xYQC6AQAWAAkJyw5xYQC6AQAAAA==.Shanta:BAAALgAECgMJAwAAAA==.Shkar:BAACLgAFFH8LAAIIAAMJ3goFOQDKAAAIAAMJ3goFOQDKAAAuAAQKf2AAAggACQnhGh0SAGICAAgACQnhGh0SAGICAAAA.Shokan:BAAALgAECgYJDAAAAA==.',
Si='Silanah:BAAALgADCgEJAQAAAA==.Silandrya:BAAALgAECgMJAwAAAA==.Sildin:BAAALgAECgUJCAAAAA==.Silverclaws:BAAALgAECgcJBwAAAA==.',
Sj='Sjaridin:BAEALgAECgQJDAABLgAFFAcJIQAhAEsDAA==.',
Sk='Skittle:BAABLgAECn8wAAQhAAgJVAkhMgDdAAAhAAgJVAkhMgDdAAAbAAUJdAIhoABuAAAlAAEJPQfEYwAXAAAAAA==.Skullhunter:BAABLgAFFH8HAAQNAAYJKR3LIACgAAANAAQJXiHLIACgAAAmAAEJ2RXfMABLAAAMAAEJ3BdMoQBIAAAAAA==.',
Sl='Slenderama:BAAALgADCgYJCQAAAA==.Slenderella:BAAALgADCgUJBQAAAA==.',
Sm='Small:BAAALgADCgEJAQAAAA==.Smawbrawl:BAAALgAECggJCQAAAA==.Smoothroller:BAABLgAECn8sAAMZAAkJbhaRFwBYAgAZAAkJbhaRFwBYAgAQAAIJAAfPkQA8AAAAAA==.',
So='Sogen:BAAALgADCgMJAwAAAA==.Soloxtremist:BAAALgADCgEJAQAAAA==.Soulripper:BAAALgAECgYJBwABLgAFFAIJAgAeAAAAAA==.Soultank:BAAALgADCgMJAwAAAA==.',
St='Staysalty:BAAALgADCgEJAQAAAA==.Stickyricky:BAAALgADCgUJCgAAAA==.Strongmandan:BAAALgAECgEJAQAAAA==.Stubs:BAAALgADCgYJDAAAAA==.',
Su='Sule:BAEBLgAECn88AAIWAAkJRhY6SAAAAgAWAAkJRhY6SAAAAgAAAA==.',
Sw='Sweetpea:BAAALgAFFAEJAQABLgAFFAYJGAARAK8YAA==.',
['Sä']='Sämuel:BAAALgAECgEJAQAAAA==.',
Ta='Tanks:BAAALgAECgIJAgAAAA==.',
Th='Thelorax:BAACLgAFFH8FAAIHAAMJyAa3cAChAAAHAAMJyAa3cAChAAAuAAQKfx8AAgcACQlDEPFEALUBAAcACQlDEPFEALUBAAAA.Theyeti:BAAALgADCgEJAgABLgADCgQJBwAeAAAAAA==.Thhee:BAABLgAECn8zAAInAAkJOhkGDQBUAgAnAAkJOhkGDQBUAgAAAA==.Thumbelina:BAAALgAECgMJAwABLgAECggJIwAbALUbAA==.Thumbelyna:BAABLgAECn8jAAMbAAgJtRvuHwBFAgAbAAgJtRvuHwBFAgAhAAEJMQrzNQAeAAAAAA==.',
To='Towelp:BAAALgAECgYJCAABLgAFFAYJJwAXABohAA==.',
Ts='Tsuro:BAAALgAECgcJCwAAAA==.',
Tu='Tukktukk:BAAALgAECgEJAQAAAA==.',
Ty='Tyrini:BAAALgADCgIJAgAAAA==.',
Um='Umie:BAAALgAECgEJAQAAAA==.',
Un='Unholylife:BAABLgAECn8aAAICAAgJSAYsvAAMAQACAAgJSAYsvAAMAQAAAA==.',
Up='Up:BAABLgAECn8VAAIUAAcJVB/nBABjAgAUAAcJVB/nBABjAgAAAA==.',
Ur='Ursan:BAAALgAECgYJBwAAAA==.',
Va='Valasi:BAAALgAECgEJAwAAAA==.',
Ve='Velocet:BAACLgAFFH8WAAInAAYJPwoAEwBvAQAnAAYJPwoAEwBvAQAuAAQKfzcAAycACQm0GngVAGQCACcACQm0GngVAGQCAAkAAwmICL0WAIsAAAAA.Vetlance:BAAALgAECgQJBQAAAA==.',
Vo='Voroak:BAAALgADCgYJBgAAAA==.',
Wa='Waghdaddy:BAABLgAECn8pAAICAAkJlCJHFgC8AgACAAkJlCJHFgC8AgAAAA==.Waghiechan:BAAALgAECgcJDQAAAA==.Walzy:BAAALgAECgEJAQAAAA==.',
We='Werewolf:BAAALgAECgUJBQAAAA==.',
Wh='Whatøncewas:BAAALgAFFAEJAQABLgAFFAIJAwAeAAAAAA==.Whitfield:BAAALgADCgUJBQAAAA==.Whordie:BAAALgAECgEJAQAAAA==.',
Wi='Wildlily:BAAALgADCgkJCQABLgAFFAQJBgACAM4OAA==.Wistful:BAAALgAECgQJBwAAAA==.',
Wo='Wobiwabi:BAAALgADCgIJAgAAAA==.',
Wr='Wratheon:BAACLgAFFH8WAAIRAAYJ8RxNDADHAQARAAYJ8RxNDADHAQAuAAQKfzsAAxEACQm4HvkHALMCABEACQm4HvkHALMCABAAAgmxCxqqACcAAAAA.',
Wu='Wuji:BAABLgAECn81AAIkAAkJRQ2VIQDBAQAkAAkJRQ2VIQDBAQAAAA==.',
['Wê']='Wêrewôlf:BAAALgADCgUJBQAAAA==.',
Xa='Xablau:BAAALgAECgYJBwAAAA==.',
Ye='Yeli:BAAALgAECggJEQAAAA==.',
Za='Zardasa:BAAALgAECgIJAgABLgADCgQJBwAeAAAAAA==.',
Ze='Zenaf:BAAALgAECgUJBwAAAA==.Zeryph:BAAALgADCgYJCwABLgAECgkJJAAEAMgeAA==.',
Zi='Zimbabway:BAAALgAECgYJBwAAAA==.',
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
