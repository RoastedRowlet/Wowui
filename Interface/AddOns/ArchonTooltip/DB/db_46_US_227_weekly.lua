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

local lookup = {'Warlock-Demonology','Paladin-Retribution','Warlock-Destruction','Warrior-Protection','DeathKnight-Unholy','Priest-Holy','DemonHunter-Devourer','Warrior-Fury','Rogue-Assassination','Paladin-Protection','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Restoration','Paladin-Holy','DeathKnight-Blood','Warrior-Arms','DemonHunter-Vengeance','DemonHunter-Havoc','Mage-Frost','Priest-Shadow','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Evoker-Devastation','Unknown-Unknown','Druid-Restoration','DeathKnight-Frost','Druid-Balance','Mage-Arcane','Evoker-Augmentation','Evoker-Preservation','Mage-Fire','Priest-Discipline','Druid-Guardian','Hunter-Survival','Rogue-Subtlety',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=46,date='2026-05-24',data={Ab='Abharn:BAAALgAECgYJDQAAAA==.',
Ag='Agoneer:BAAALgAECgMJAwAAAA==.',
Ak='Akeera:BAABLgAECn8VAAIBAAcJUA7aegAwAQABAAcJUA7aegAwAQAAAA==.Akkiya:BAAALgAECgYJDwABLgAFFAUJEAACANwUAA==.',
Al='Althtar:BAAALgADCgQJBAAAAA==.',
Am='Amalyn:BAAALgAECgYJCAAAAA==.Amarantha:BAABLgAECn8dAAMDAAkJIgdKFgDRAAADAAcJDwdKFgDRAAABAAMJVgdC9wBTAAAAAA==.',
An='Anaesthetize:BAAALgAECgYJBwAAAA==.Aness:BAABLgAECn8aAAIEAAgJwwKlJwDPAAAEAAgJwwKlJwDPAAAAAA==.Angelinalizy:BAAALgADCgkJCQAAAA==.Animagon:BAAALgADCgkJCQAAAA==.Animaker:BAABLgAECn8tAAIFAAkJCRWwPADvAQAFAAkJCRWwPADvAQAAAA==.Anngus:BAAALgADCgcJCAAAAA==.Anvilkrash:BAAALgADCgcJCwAAAA==.',
Ar='Ariese:BAAALgADCgcJCAAAAA==.',
As='Ashido:BAABLgAECn8UAAIGAAYJJhzKGQDWAQAGAAYJJhzKGQDWAQAAAA==.Astreos:BAABLgAFFH8KAAIBAAUJABx1MgBFAQABAAUJABx1MgBFAQABLgAFFAgJHgAHAO8dAA==.Astrikin:BAAALgAECgYJDwABLgAFFAgJHgAHAO8dAA==.',
Au='Auraiel:BAAALgADCgcJFAAAAA==.Aurhon:BAAALgAECgYJBgAAAA==.Aurorastar:BAAALgAECgEJAQAAAA==.',
Ba='Bagawgwah:BAAALgAECgEJAQAAAA==.Baluu:BAAALgAECgQJBAAAAA==.Baultier:BAAALgADCgkJDgAAAA==.',
Be='Bel:BAABLgAECn87AAIEAAkJBySJAQAwAwAEAAkJBySJAQAwAwAAAA==.Beraxes:BAABLgAECn8eAAIIAAgJHA+zKwCDAQAIAAgJHA+zKwCDAQAAAA==.',
Bl='Blasser:BAABLgAECn8fAAIJAAkJ6BrCAwBKAgAJAAkJ6BrCAwBKAgAAAA==.Blizizdumz:BAABLgAECn80AAMCAAgJzh8nIgBfAgACAAgJaB8nIgBfAgAKAAYJjyGwEACPAQAAAA==.',
Bm='Bmcgilicuddy:BAAALgAECgYJCwAAAA==.',
Br='Bralindra:BAAALgAECgEJAgAAAA==.Breadpitt:BAAALgAECggJCQAAAA==.Brewdhism:BAAALgAECgMJAwAAAA==.Brillane:BAAALgADCgUJAwAAAA==.',
Bu='Bulsy:BAACLgAFFH8QAAMLAAUJdR5pGABiAQALAAUJdR5pGABiAQAMAAEJcgH/LAAtAAAuAAQKfyQAAwsACQnwHWENAMICAAsACQnwHWENAMICAAwABAmQBOtoAJsAAAAA.',
Ca='Calamidade:BAABLgAECn8rAAMNAAkJfQRzFQApAQANAAkJfQRzFQApAQAOAAMJdwFprwA4AAAAAA==.Calashlar:BAAALgAECgIJBQAAAA==.Camri:BAAALgADCgMJAwAAAA==.Capwnd:BAAALgAECgMJAwAAAA==.',
Ce='Cerryan:BAABLgAECn8uAAIPAAgJphCmKQCdAQAPAAgJphCmKQCdAQAAAA==.Cexar:BAABLgAECn8ZAAIIAAcJSw38NwBEAQAIAAcJSw38NwBEAQAAAA==.',
Ch='Chaoticprime:BAAALgADCgEJAwAAAA==.Charivium:BAAALgADCgQJBAAAAA==.Charo:BAAALgAECgQJBAAAAA==.Chaòs:BAAALgADCgMJAwAAAA==.Chinup:BAABLgAECn82AAIQAAkJQCG0BgCTAgAQAAkJQCG0BgCTAgAAAA==.',
Cl='Clother:BAACLgAFFH8YAAMIAAUJQSRLBACwAQAIAAUJ7RhLBACwAQARAAUJQST3AQBkAQAuAAQKfxoAAwgACAkEIfYKAAQDAAgACAkEIfYKAAQDABEABgnmIGEHAEkCAAEuAAUUBgkTAAUAkB0A.',
Co='Cokenopepsi:BAABLgAECn8YAAIQAAgJiB4JDgD8AQAQAAgJiB4JDgD8AQAAAA==.',
Cr='Crackle:BAAALgADCgcJDAAAAA==.Crazyhorse:BAAALgAECgYJCwAAAA==.Cristos:BAAALgADCgYJCwAAAA==.',
Cu='Curses:BAAALgAECggJEAAAAA==.',
['Cø']='Cøløssus:BAAALgAECgEJAQAAAA==.',
Da='Daddypie:BAABLgAECn88AAMSAAkJ0iSkAABBAwASAAkJ0iSkAABBAwATAAEJdR3YTQBLAAAAAA==.Damasscus:BAAALgAECgcJDQAAAA==.Darkdesire:BAAALgADCgUJBQAAAA==.',
De='Deathkanight:BAAALgAECgEJAQAAAA==.Desdakharii:BAAALgAECgEJAQAAAA==.',
Di='Diktug:BAAALgAECgEJAQAAAA==.Disney:BAABLgAECn8WAAIJAAcJshLOCgCDAQAJAAcJshLOCgCDAQAAAA==.',
Dj='Djaztech:BAACLgAFFH8HAAMRAAUJ6RSBEQAVAQARAAQJzhGBEQAVAQAIAAMJxROzMgCYAAAuAAQKfyUAAwgACQkOIlMQAFQCAAgACAkhIVMQAFQCABEABwlQGvMNAOUBAAAA.',
Do='Donkie:BAABLgAECn8eAAILAAcJ+R+NJwAbAgALAAcJ+R+NJwAbAgAAAA==.',
Dr='Dracsano:BAAALgAECgUJCQABLgAECggJFAAHANoIAA==.Dreadhunter:BAAALgAECgMJAwAAAA==.Dreamzz:BAAALgADCgMJAwAAAA==.Drixadin:BAAALgAECgQJBwAAAA==.Drshockêr:BAABLgAECn9CAAMOAAkJpiA9BABQAwAOAAkJpiA9BABQAwANAAgJngwpEgBYAQAAAA==.',
Ds='Dsakony:BAABLgAECn8WAAIUAAkJZhR+igBJAQAUAAkJZhR+igBJAQAAAA==.',
Du='Dunthat:BAAALgADCgYJBgAAAA==.Duskdruid:BAAALgAECgUJBQABLgAFFAYJBgAQAIYfAA==.Duthir:BAACLgAFFH8KAAIFAAMJ/g50fADdAAAFAAMJ/g50fADdAAAuAAQKfywAAgUACQldHc8/ADkCAAUACQldHc8/ADkCAAEuAAUUBQkJABUANBEA.',
Dy='Dyte:BAAALgAECgEJAQAAAA==.',
Ea='East:BAAALgAECgYJEwAAAA==.',
Ed='Edd:BAAALgAECgEJAQAAAA==.',
Eg='Egrok:BAABLgAECn8ZAAIWAAcJVhK+MABSAQAWAAcJVhK+MABSAQAAAA==.',
Em='Emaeel:BAABLgAECn8cAAQXAAgJqRBxKwCLAQAXAAgJqRBxKwCLAQAYAAgJOQ/dJABlAQAZAAEJpwFCmQAYAAAAAA==.Emporia:BAAALgAFFAEJAgAAAA==.',
En='Envyqt:BAAALgADCgEJAQAAAA==.',
Es='Esso:BAACLgAFFH8QAAMFAAUJzRQcRwA7AQAFAAQJzRQcRwA7AQAQAAEJAABWQgAAAAAuAAQKfxgAAgUABwluFydYAJwBAAUABwluFydYAJwBAAAA.',
Fa='Faelenor:BAAALgAECgYJCAAAAA==.Faelure:BAABLgAECn8YAAICAAgJDQleqQAJAQACAAgJDQleqQAJAQAAAA==.',
Fe='Feyed:BAAALgAECgEJAQAAAA==.',
Fi='Fiddleoux:BAAALgAECgYJEAAAAA==.Fiending:BAAALgAECgEJAQAAAA==.Finnarius:BAAALgADCgYJBgAAAA==.Firenze:BAAALgAECgYJDgAAAA==.Fizzlewar:BAAALgADCgIJAgABLgAECggJNAACAM4fAQ==.',
Fo='Foros:BAABLgAECn8eAAIPAAgJIyUsEACSAgAPAAgJIyUsEACSAgAAAA==.',
Fr='Frozone:BAABLgAECn8kAAIUAAgJWhgPSADqAQAUAAgJWhgPSADqAQAAAA==.Fryiertuck:BAAALgAECgYJCgAAAA==.',
Ga='Gabil:BAABLgAECn8vAAIaAAgJrQkKCwBKAQAaAAgJrQkKCwBKAQAAAA==.Gaunshots:BAAALgAECgQJBwABLgAECggJEAAbAAAAAA==.',
Ge='Gendorosan:BAABLgAECn8vAAIcAAgJiyIKCQANAwAcAAgJiyIKCQANAwAAAA==.',
Gn='Gnork:BAAALgAECgcJEQABLgAECgkJFgAcAKIRAA==.',
Go='Goldwolf:BAAALgADCgYJBgAAAA==.Gotarrnianan:BAAALgAECgEJBAAAAA==.Gothpally:BAAALgAECgQJBAAAAA==.',
Gr='Grandmasterx:BAAALgAECgIJAwAAAA==.Graveworm:BAAALgAECgEJAQAAAA==.Gravewurm:BAAALgAECgEJAQAAAA==.Grayfoxx:BAABLgAECn8tAAIFAAgJHBu3NAALAgAFAAgJHBu3NAALAgAAAA==.Grayhard:BAAALgAECgYJBwAAAA==.Greenhornn:BAAALgADCgQJBAAAAA==.Grìmmgor:BAACLgAFFH8TAAIdAAQJTSIwBQBcAQAdAAQJTSIwBQBcAQAuAAQKfysAAh0ACQmDIkwAAIgDAB0ACQmDIkwAAIgDAAAA.',
Gu='Guerriera:BAAALgAECggJDgAAAA==.Gulkenn:BAAALgADCgcJBwAAAA==.',
['Gô']='Gôôdbye:BAAALgAECgcJEAAAAA==.',
['Gö']='Gööse:BAAALgAECggJDAAAAA==.',
Ha='Hado:BAAALgAECgQJBAAAAA==.Halbrand:BAACLgAFFH8GAAIFAAIJKApbtQCLAAAFAAIJKApbtQCLAAAuAAQKfxsAAgUACAm8GdldAI4BAAUACAm8GdldAI4BAAEuAAUUBQkMAB4A8xYA.Hamburgmeat:BAAALgADCgYJBQAAAA==.',
He='Healovathyme:BAACLgAFFH8IAAIcAAIJqSAINQDAAAAcAAIJqSAINQDAAAAuAAQKfxoAAhwACAlxIugVAIcCABwACAlxIugVAIcCAAAA.Hellstomper:BAAALgAECgQJDQAAAA==.Heygrlhey:BAABLgAECn8/AAMLAAkJniM7BwAEAwALAAkJniM7BwAEAwAMAAQJRwe0YAC+AAAAAA==.',
Hi='Hidaoushi:BAAALgADCgkJCQAAAA==.',
Ho='Holdstillbro:BAAALgADCgEJAQABLgAECgkJNgAQAEAhAA==.',
Hu='Hukkaluzul:BAAALgAECgEJAQAAAA==.Humaladin:BAAALgAECgEJAQAAAA==.Humanpaladin:BAAALgAECggJDgABLgAECggJEAAbAAAAAA==.Hungryghost:BAAALgAECgkJCwAAAA==.Hunna:BAABLgAECn8dAAILAAgJxxohLwD3AQALAAgJxxohLwD3AQAAAA==.Hurtzdonit:BAAALgADCgIJAgAAAA==.',
Hv='Hvtn:BAAALgAECgYJEAAAAA==.',
Ic='Icyfractals:BAAALgADCgQJBQAAAA==.',
In='Inebriated:BAABLgAECn8bAAILAAgJIgvqaABGAQALAAgJIgvqaABGAQAAAA==.',
Io='Iondia:BAAALgAECgQJCgAAAA==.',
Is='Iselune:BAAALgAECgIJAgAAAA==.',
Iz='Izanami:BAAALgAECgEJAQAAAA==.',
Ja='Jambi:BAAALgAECgYJCgAAAA==.Jandrina:BAAALgADCgYJCgAAAA==.Jaraxxus:BAAALgADCgcJBwAAAA==.Jardran:BAAALgAECgEJAgAAAA==.',
Jo='Joanchokkea:BAAALgADCgcJDgAAAA==.Joankorel:BAAALgADCgkJCQAAAA==.Johnconnor:BAAALgADCgYJBwAAAA==.Jolty:BAAALgAECgcJCAABLgAFFAQJEwAFAAUiAA==.',
['Jê']='Jêanne:BAAALgAECgEJAQAAAA==.',
Ka='Kael:BAAALgAECgQJCAAAAA==.Kahira:BAEALgADCgQJBAAAAA==.Kalidra:BAAALgAECgQJBQAAAA==.Kaname:BAAALgADCgYJCQABLgAECgUJEAAbAAAAAA==.',
Ke='Kenpashi:BAAALgADCgYJBgAAAA==.Kermitted:BAAALgAECgEJAgABLgAECgUJBwAbAAAAAA==.',
Ki='Kirlo:BAAALgADCgcJDQAAAA==.Kittytiddies:BAAALgADCgUJBQAAAA==.',
Ko='Kobethama:BAAALgAECgEJBQAAAA==.Kohnan:BAABLgAECn8UAAIHAAgJ2ggJewAFAQAHAAgJ2ggJewAFAQAAAA==.Kotoko:BAABLgAECn8WAAIOAAgJOxr6GwBBAgAOAAgJOxr6GwBBAgAAAA==.',
Ks='Ksauce:BAABLgAECn8fAAIfAAgJSANPCQDNAAAfAAgJSANPCQDNAAAAAA==.',
Ku='Kungfumama:BAAALgAECgEJAQAAAA==.',
Ky='Kynan:BAACLgAFFH8FAAICAAIJ/A0VcACVAAACAAIJ/A0VcACVAAAuAAQKfx0AAwIACAmGGQ5DAOABAAIACAmGGQ5DAOABAAoAAQmfA9NPABMAAAEuAAQKBAkEABsAAAAA.Kynon:BAABLgAECn8ZAAMYAAYJbRTOMABjAQAYAAYJbRTOMABjAQAXAAEJLgFmdwAUAAABLgAECgQJBAAbAAAAAA==.Kyran:BAAALgAECgQJBAAAAA==.',
La='Laerai:BAAALgADCgcJDAAAAA==.Lament:BAABLgAECn8UAAIHAAgJQxrfJAAeAgAHAAgJQxrfJAAeAgAAAA==.Lamurun:BAAALgAECgQJBAAAAA==.Lancelöt:BAACLgAFFH8JAAICAAQJ0yDEFgB7AQACAAQJ0yDEFgB7AQAuAAQKf0UAAgIACQljJBkGACwDAAIACQljJBkGACwDAAAA.Lastra:BAAALgAECgkJEgABLgAFFAIJAwAbAAAAAA==.Lathina:BAAALgAECgUJBwAAAA==.Lavendere:BAAALgAECgYJEgABLgAFFAUJCQAVADQRAA==.',
Le='Lectra:BAAALgAECgIJAgAAAA==.Leechang:BAAALgADCgMJAwAAAA==.',
Li='Liiam:BAAALgADCgYJBgAAAA==.Linafox:BAABLgAECn8YAAIUAAgJaAdziABNAQAUAAgJaAdziABNAQAAAA==.Linnëa:BAABLgAFFH8FAAIQAAMJngx3HwCwAAAQAAMJngx3HwCwAAAAAA==.Linta:BAAALgADCgcJCQAAAA==.Lizardwizard:BAABLgAECn8XAAIgAAgJQREfKQB9AQAgAAgJQREfKQB9AQAAAA==.',
Ll='Llonia:BAAALgADCgMJAwAAAA==.',
Lo='Lockraum:BAAALgAECgMJBAAAAA==.Lokix:BAABLgAECn8vAAIFAAgJoyIIFgCkAgAFAAgJoyIIFgCkAgAAAA==.',
Lu='Luexis:BAAALgADCgkJFgAAAA==.Luobo:BAAALgADCgQJBQAAAA==.Lustie:BAAALgADCgMJAwAAAA==.',
Ly='Lysistratta:BAABLgAECn8vAAIQAAgJBA3aHwAoAQAQAAgJBA3aHwAoAQAAAA==.',
Ma='Magikishi:BAABLgAECn8cAAIUAAgJYR8xOwCKAgAUAAgJYR8xOwCKAgAAAA==.Magimal:BAAALgAECgYJBgABLgAECggJHAAXAKkQAA==.Mahka:BAABLgAECn9GAAMcAAkJByDjDADZAgAcAAkJByDjDADZAgAeAAMJHyOCNQATAQABLgADCgEJAQAbAAAAAA==.Maldrakesus:BAAALgADCgEJAQABLgAECggJHAAXAKkQAA==.Malifecent:BAAALgAECgMJAwAAAA==.Manthalus:BAAALgAECgIJAgAAAA==.Marquista:BAAALgAECgYJBgAAAA==.Masika:BAAALgAECgIJAgAAAA==.',
Mc='Mchammer:BAAALgADCgMJAwAAAA==.',
Me='Meatball:BAAALgAECgMJAwAAAA==.Meganstoon:BAAALgAECgMJBAAAAA==.Meladaris:BAAALgAECgQJCAAAAA==.Mey:BAABLgAECn8/AAIGAAkJBRunDQBmAgAGAAkJBRunDQBmAgAAAA==.',
Mi='Misfortune:BAAALgADCgUJBQAAAA==.Missperfect:BAAALgAECgcJEQAAAA==.Mitenalla:BAACLgAFFH8QAAICAAUJ3BQRLAA5AQACAAUJ3BQRLAA5AQAuAAQKfxoAAgIACAm6G6JDAN4BAAIACAm6G6JDAN4BAAAA.',
Mo='Morninbreath:BAAALgAECgUJBQAAAA==.Mossberger:BAAALgADCgQJBAAAAA==.',
Mu='Muatahawa:BAAALgAECgMJBQAAAA==.Muglackh:BAAALgAECgcJEwAAAA==.',
My='Myoue:BAAALgAECgMJBQAAAA==.Mysticraven:BAABLgAECn8UAAIeAAgJFASPQQDYAAAeAAgJFASPQQDYAAAAAA==.Mythbredor:BAAALgAECgYJBgAAAA==.',
Na='Naariah:BAAALgADCgcJCAAAAA==.Nagendra:BAACLgAFFH8MAAIgAAUJghs9GQBHAQAgAAUJghs9GQBHAQAuAAQKfxwAAiAACQkaIOgHAPoCACAACQkaIOgHAPoCAAAA.Natharion:BAAALgADCgUJCgAAAA==.',
Ne='Neoptolemos:BAAALgAECgMJBAAAAA==.Nezpak:BAAALgADCgcJEAAAAA==.',
Ni='Nicnevin:BAABLgAECn8gAAIaAAgJ2waeDAArAQAaAAgJ2waeDAArAQAAAA==.Nitrochrist:BAABLgAECn88AAIBAAkJxRWvNwDkAQABAAkJxRWvNwDkAQAAAA==.Nixxy:BAAALgAECgYJBgABLgAFFAUJFQAhAJ8TAA==.',
No='Nokansee:BAAALgADCgQJBAAAAA==.Nokimi:BAAALgAECgUJCAAAAA==.Noobru:BAAALgAECgYJDwAAAA==.Nordathair:BAABLgAECn8eAAIgAAcJGg/pNQAzAQAgAAcJGg/pNQAzAQAAAA==.Nori:BAACLgAFFH8oAAIUAAgJUiRfAQD0AgAUAAgJUiRfAQD0AgAuAAQKfywAAxQACQm9JpoAAPwDABQACQm9JpoAAPwDAB8AAwkSILcPAMcAAAAA.',
Ob='Oblivion:BAAALgADCgQJBAAAAA==.',
On='Onebuttonman:BAAALgAECgEJAQAAAA==.Onlyfoxes:BAAALgAECgIJAgAAAA==.',
Or='Original:BAABLgAECn8VAAICAAgJDSB8HwBtAgACAAgJDSB8HwBtAgAAAA==.Originals:BAAALgAFFAIJAgAAAA==.',
Ot='Otome:BAAALgAECggJEwAAAA==.',
Ov='Overpoweredd:BAAALgAECggJCQAAAA==.',
Pa='Painfulpoo:BAAALgAECgIJAgAAAA==.Parsemae:BAACLgAFFH8LAAIUAAQJfxnDPwBHAQAUAAQJfxnDPwBHAQAuAAQKfyMAAxQACAm2HW0vALQCABQACAm2HW0vALQCACIAAQkdD64QADEAAAAA.Pastries:BAACLgAFFH8eAAIHAAgJ7x1KAgAyAgAHAAgJ7x1KAgAyAgAuAAQKfzcAAwcACQmrIrkCAKUDAAcACQmrIrkCAKUDABMAAgnMFHJAAHoAAAAA.',
Pb='Pbd:BAAALgAECgIJAgAAAA==.',
Pi='Pitlin:BAABLgAECn8kAAIjAAkJFiFXBAAxAwAjAAkJFiFXBAAxAwAAAA==.',
Pm='Pmsavenger:BAAALgADCgkJEgAAAA==.',
Po='Polynya:BAAALgAECgQJCQAAAA==.Pooshot:BAAALgAECgYJCwAAAA==.',
Pr='Priestalisha:BAACLgAFFH8iAAIGAAYJwyMHAgAuAgAGAAYJwyMHAgAuAgAuAAQKf0AAAgYACQkWJX0AANEDAAYACQkWJX0AANEDAAAA.Prognie:BAAALgADCgcJCAAAAA==.',
Ra='Raelana:BAABLgAECn8uAAICAAgJLgr6fQBUAQACAAgJLgr6fQBUAQAAAA==.Ragetatertot:BAAALgAECgYJDgAAAA==.Ragingpoo:BAABLgAECn8ZAAIFAAkJlxQyOAD+AQAFAAkJlxQyOAD+AQAAAA==.Rakenroll:BAAALgADCggJCAAAAA==.Rawsteak:BAABLgAECn8ZAAIQAAkJBxfKEADSAQAQAAkJBxfKEADSAQAAAA==.Razdaz:BAABLgAECn8eAAMGAAcJfh15GADkAQAjAAYJxhv/FQD0AQAGAAcJUhl5GADkAQAAAA==.',
Re='Redcrow:BAABLgAECn8VAAIIAAkJbQa7OABBAQAIAAkJbQa7OABBAQAAAA==.Reheal:BAABLgAECn8WAAIGAAgJjR1CCwCNAgAGAAgJjR1CCwCNAgAAAA==.Reshocker:BAABLgAECn8rAAIWAAkJghrIGgDiAQAWAAkJghrIGgDiAQAAAA==.Restosexualz:BAAALgAECgMJBAAAAA==.',
Ri='Rixxy:BAACLgAFFH8VAAMhAAUJnxPHCABdAQAhAAUJnxPHCABdAQAgAAEJsAFZVgA0AAAuAAQKfzIAAyEACAmVIkUCAFEDACEACAmVIkUCAFEDACAABwmrC8g+AO8AAAAA.',
Ro='Roastbeefdr:BAABLgAECn9BAAMQAAkJ2iSqAQAwAwAQAAkJ2iSqAQAwAwAFAAQJwR7srwDvAAAAAA==.Roderigo:BAABLgAECn8kAAIcAAgJtQ/9OQCNAQAcAAgJtQ/9OQCNAQAAAA==.Root:BAAALgAECgYJEQAAAA==.',
Ru='Runian:BAAALgAECgUJCwAAAA==.',
Sa='Sadlypink:BAABLgAECn8VAAIUAAcJLBRKhwDDAQAUAAcJLBRKhwDDAQAAAA==.Saisaith:BAACLgAFFH8JAAIVAAUJNBEUEwA2AQAVAAUJNBEUEwA2AQAuAAQKfxwAAxUACQlHGTkLAH0CABUACQlHGTkLAH0CAAYAAQlkBf1pACQAAAAA.Sanarian:BAAALgADCgMJAwAAAA==.Sand:BAABLgAECn8jAAIFAAcJLhU8aAC9AQAFAAcJLhU8aAC9AQAAAA==.Sandy:BAAALgAECgcJBQAAAA==.Savadar:BAAALgAECgcJDQAAAA==.Saymourcox:BAAALgAECgcJCwAAAA==.',
Se='Seadra:BAAALgADCggJDQABLgAECgYJFAAKAM4ZAA==.Sealyboi:BAAALgADCgQJBAAAAA==.Serpeng:BAABLgAECn8bAAMTAAgJEBGsGwBoAQATAAgJ1g+sGwBoAQASAAYJ9QrzFQDQAAAAAA==.Setareh:BAABLgAECn8YAAIUAAgJvwYZkgA7AQAUAAgJvwYZkgA7AQAAAA==.Settra:BAAALgADCgcJDAAAAA==.',
Sh='Shakuru:BAABLgAECn8yAAIUAAkJyw7WUADPAQAUAAkJyw7WUADPAQAAAA==.Shanta:BAAALgADCgMJAwAAAA==.Shkar:BAABLgAECn9OAAIIAAkJPBpgGACJAgAIAAkJPBpgGACJAgAAAA==.Shokan:BAAALgAECgQJBAAAAA==.',
Si='Silanah:BAAALgADCgEJAQAAAA==.Silandrya:BAAALgADCggJDAAAAA==.Sildin:BAAALgAECgUJCAAAAA==.Silverclaws:BAAALgAECgYJBgAAAA==.',
Sj='Sjaridin:BAEALgAECgQJDAAAAA==.',
Sk='Skittle:BAABLgAECn8kAAMkAAcJVQn+KgDFAAAkAAcJVQn+KgDFAAAcAAUJdAJskQBwAAAAAA==.Skullhunter:BAABLgAFFH8HAAQMAAYJKR2XFwCzAAAMAAQJXiGXFwCzAAAlAAEJ2RVMJwBPAAALAAEJ3BeveABIAAAAAA==.',
Sl='Slenderama:BAAALgADCgYJCQAAAA==.Slenderella:BAAALgADCgUJBQAAAA==.',
Sm='Small:BAAALgADCgEJAQAAAA==.Smawbrawl:BAAALgAECggJCQAAAA==.Smoothroller:BAABLgAECn8VAAIXAAYJ2hI5OABBAQAXAAYJ2hI5OABBAQAAAA==.',
So='Sogen:BAAALgADCgMJAwAAAA==.Soloxtremist:BAAALgADCgEJAQAAAA==.',
St='Staysalty:BAAALgADCgEJAQAAAA==.Stickyricky:BAAALgADCgUJCgAAAA==.Strongmandan:BAAALgAECgEJAQAAAA==.Stubs:BAAALgADCgYJDAAAAA==.',
Su='Sule:BAEBLgAECn88AAIUAAkJRhbUOwARAgAUAAkJRhbUOwARAgAAAA==.',
Sw='Sweetpea:BAAALgAFFAEJAQABLgAFFAUJFwAZACMcAA==.',
['Sä']='Sämuel:BAAALgAECgEJAQAAAA==.',
Ta='Tanks:BAAALgADCgEJAgAAAA==.',
Th='Thelorax:BAABLgAECn8fAAIHAAkJQxACOQDDAQAHAAkJQxACOQDDAQAAAA==.Theyeti:BAAALgADCgEJAgABLgADCgQJBwAbAAAAAA==.Thhee:BAABLgAECn8vAAImAAgJRhoCDwAYAgAmAAgJRhoCDwAYAgAAAA==.Thumbelyna:BAABLgAECn8jAAMcAAgJtRvJGwBGAgAcAAgJtRvJGwBGAgAkAAEJMQrzNQAeAAAAAA==.',
To='Towelp:BAAALgAECgUJBQABLgAFFAUJGQAVADAeAA==.',
Ts='Tsuro:BAAALgAECgYJCgAAAA==.',
Tu='Tukktukk:BAAALgAECgEJAQAAAA==.',
Ty='Tyrini:BAAALgADCgIJAgAAAA==.',
Um='Umie:BAAALgAECgEJAQAAAA==.',
Un='Unholylife:BAABLgAECn8ZAAICAAgJSAZknAAeAQACAAgJSAZknAAeAQAAAA==.',
Up='Up:BAABLgAECn8VAAISAAcJVB/nBABjAgASAAcJVB/nBABjAgAAAA==.',
Va='Valasi:BAAALgAECgEJAwAAAA==.',
Ve='Velocet:BAACLgAFFH8QAAImAAUJQAqVGAAnAQAmAAUJQAqVGAAnAQAuAAQKfzcAAyYACQm0GngVAGQCACYACQm0GngVAGQCAAkAAwmICL0WAIsAAAAA.Vetlance:BAAALgAECgQJBQAAAA==.',
Vo='Voroak:BAAALgADCgYJBgAAAA==.',
Wa='Waghdaddy:BAABLgAECn8pAAICAAkJlCLjDwDOAgACAAkJlCLjDwDOAgAAAA==.Waghiechan:BAAALgAECgcJDQAAAA==.',
We='Werewolf:BAAALgAECgUJBQAAAA==.',
Wh='Whatøncewas:BAAALgAFFAEJAQAAAA==.Whitfield:BAAALgADCgUJBQAAAA==.Whordie:BAAALgAECgEJAQAAAA==.',
Wi='Wildlily:BAAALgADCgkJCQABLgAFFAEJAQAbAAAAAA==.Wistful:BAAALgAECgQJBwAAAA==.',
Wo='Wobiwabi:BAAALgADCgIJAgAAAA==.',
Wr='Wratheon:BAACLgAFFH8QAAIZAAUJXR7lEABkAQAZAAUJXR7lEABkAQAuAAQKfzsAAxkACQm4HicGAL4CABkACQm4HicGAL4CABgAAgmxC9qLACsAAAAA.',
Wu='Wuji:BAABLgAECn8uAAIjAAgJkwxjIwCGAQAjAAgJkwxjIwCGAQAAAA==.',
['Wê']='Wêrewôlf:BAAALgADCgUJBQAAAA==.',
Xa='Xablau:BAAALgAECgYJBgAAAA==.',
Ye='Yeli:BAAALgAECggJDgAAAA==.',
Za='Zardasa:BAAALgAECgIJAgABLgADCgQJBwAbAAAAAA==.',
Ze='Zenaf:BAAALgAECgUJBwAAAA==.Zeryph:BAAALgADCgYJCwABLgAECgkJIgAEAMgeAA==.',
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
