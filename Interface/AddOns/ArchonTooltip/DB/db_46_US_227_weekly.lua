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

local lookup = {'Warlock-Demonology','Paladin-Retribution','Warlock-Destruction','Warrior-Protection','DeathKnight-Unholy','Priest-Holy','DemonHunter-Devourer','Warrior-Fury','Rogue-Assassination','Paladin-Holy','Paladin-Protection','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Restoration','DeathKnight-Blood','Warrior-Arms','DemonHunter-Vengeance','DemonHunter-Havoc','Mage-Frost','Priest-Shadow','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Evoker-Devastation','Druid-Restoration','DeathKnight-Frost','Druid-Balance','Unknown-Unknown','Mage-Arcane','Evoker-Augmentation','Evoker-Preservation','Mage-Fire','Priest-Discipline','Druid-Guardian','Hunter-Survival','Rogue-Subtlety',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=46,date='2026-05-31',data={Ab='Abharn:BAAALgAECgYJDQAAAA==.',
Ag='Agoneer:BAAALgAECgQJBwAAAA==.',
Ak='Akeera:BAABLgAECn8VAAIBAAcJUA4eggAsAQABAAcJUA4eggAsAQAAAA==.Akkiya:BAAALgAECgYJDwABLgAFFAUJFQACAEYXAA==.',
Al='Althtar:BAAALgADCgQJBAAAAA==.',
Am='Amalyn:BAAALgAECgYJCAAAAA==.Amarantha:BAABLgAECn8gAAMDAAkJBwhoGADNAAADAAcJDwdoGADNAAABAAMJ0Anw2gCSAAAAAA==.',
An='Anaesthetize:BAAALgAECgYJBwAAAA==.Aness:BAABLgAECn8hAAIEAAgJagNcKQDUAAAEAAgJagNcKQDUAAAAAA==.Angelinalizy:BAAALgADCgkJCQAAAA==.Animagon:BAAALgADCgkJCQAAAA==.Animaker:BAABLgAECn8vAAIFAAkJDBZLOAANAgAFAAkJDBZLOAANAgAAAA==.Anngus:BAAALgAECgEJAQAAAA==.Anvilkrash:BAAALgADCgcJCwAAAA==.',
Ar='Ariese:BAAALgADCgcJCAAAAA==.',
As='Ashido:BAABLgAECn8UAAIGAAYJJhwsHADQAQAGAAYJJhwsHADQAQAAAA==.Astreos:BAABLgAFFH8LAAIBAAUJHB18OABCAQABAAUJHB18OABCAQABLgAFFAgJHgAHAO8dAA==.Astrikin:BAAALgAECgYJDwABLgAFFAgJHgAHAO8dAA==.',
Au='Auraiel:BAAALgADCgcJFAAAAA==.Aurhon:BAAALgAECgYJDAAAAA==.Aurorastar:BAAALgAECgEJAQAAAA==.',
Ba='Bagawgwah:BAAALgAECgEJAgAAAA==.Baluu:BAAALgAECgQJBAAAAA==.Baultier:BAAALgADCgkJDgAAAA==.',
Be='Bel:BAABLgAECn88AAIEAAkJACV7AQA9AwAEAAkJACV7AQA9AwAAAA==.Beraxes:BAABLgAECn8mAAIIAAgJ0xFsKQChAQAIAAgJ0xFsKQChAQAAAA==.Bethäny:BAAALgAECgEJAQAAAA==.',
Bl='Blasser:BAABLgAECn8fAAIJAAkJ6BpEBABDAgAJAAkJ6BpEBABDAgAAAA==.Blizizdumz:BAACLgAFFH8FAAMCAAMJuQyeYwDKAAACAAMJuQyeYwDKAAAKAAEJEQrRQgA4AAAuAAQKfzcABAIACQneHb0ZAJMCAAIACQmFHb0ZAJMCAAsABgmPISsSAIwBAAoAAQmYAkCVAB8AAAAA.',
Bm='Bmcgilicuddy:BAAALgAECgYJCwAAAA==.',
Br='Bralindra:BAAALgAECgEJAgAAAA==.Breadpitt:BAAALgAECggJEQAAAA==.Brewdhism:BAAALgAECgMJAwAAAA==.Brillane:BAAALgAECgMJAwAAAA==.',
Bu='Bulsy:BAACLgAFFH8UAAMMAAUJdR5kIABbAQAMAAUJdR5kIABbAQANAAEJcgFWMgAsAAAuAAQKfyQAAwwACQnwHfkPAL4CAAwACQnwHfkPAL4CAA0ABAmQBOtoAJsAAAAA.',
Ca='Calamidade:BAABLgAECn8rAAMOAAkJfQTzFwApAQAOAAkJfQTzFwApAQAPAAMJdwHNvQA4AAAAAA==.Calashlar:BAAALgAECgIJBQAAAA==.Camri:BAAALgADCgMJAwAAAA==.Capwnd:BAAALgAECgMJAwAAAA==.',
Ce='Cerryan:BAABLgAECn8xAAIKAAgJphCKLACbAQAKAAgJphCKLACbAQAAAA==.Cexar:BAABLgAECn8ZAAIIAAcJgA3oOwBDAQAIAAcJgA3oOwBDAQAAAA==.',
Ch='Chaoticprime:BAAALgADCgQJBgAAAA==.Charivium:BAAALgADCgQJBAAAAA==.Charo:BAAALgAECgcJEwAAAA==.Chaòs:BAAALgADCgMJAwAAAA==.Chinup:BAABLgAECn82AAIQAAkJQCHNBwCJAgAQAAkJQCHNBwCJAgAAAA==.',
Cl='Clother:BAACLgAFFH8YAAMIAAUJQSRLBACwAQAIAAUJ7RhLBACwAQARAAUJQST3AQBkAQAuAAQKfxoAAwgACAkEIfYKAAQDAAgACAkEIfYKAAQDABEABgnmIGEHAEkCAAEuAAUUBgkUAAUAkB0A.',
Co='Cokenopepsi:BAABLgAECn8ZAAIQAAgJiB64DwD0AQAQAAgJiB64DwD0AQAAAA==.Cormigo:BAAALgAECgYJBwAAAA==.',
Cr='Crackle:BAAALgADCgcJDAAAAA==.Crazyhorse:BAAALgAECgYJCwAAAA==.Cristos:BAAALgADCgYJCwAAAA==.',
Cu='Curses:BAAALgAECggJEAABLgAECggJFQACAMYSAA==.',
['Cø']='Cøløssus:BAAALgAECgEJAQAAAA==.',
Da='Daddypie:BAABLgAECn8+AAQSAAkJ0iTTAAA6AwASAAkJ0iTTAAA6AwATAAEJdR2dVQBKAAAHAAEJ7AwE8gA/AAAAAA==.Damasscus:BAAALgAECgcJDQAAAA==.Darkdesire:BAAALgADCgUJBQAAAA==.',
De='Deathkanight:BAAALgAECgMJBAAAAA==.Desdakharii:BAAALgAECgEJAQAAAA==.',
Di='Diktug:BAAALgAECgEJAQAAAA==.Disney:BAABLgAECn8WAAIJAAcJshLOCgCDAQAJAAcJshLOCgCDAQAAAA==.',
Dj='Djaztech:BAACLgAFFH8KAAMRAAUJNxUaFQARAQARAAQJgxIaFQARAQAIAAMJxROTOACYAAAuAAQKfyYAAwgACQnFIlUPAG4CAAgACAnxIVUPAG4CABEABwlQGucPANoBAAAA.',
Do='Donkie:BAABLgAECn8gAAIMAAgJUxw4JQA4AgAMAAgJUxw4JQA4AgAAAA==.',
Dr='Dracsano:BAAALgAECgUJCwABLgAECggJFAAHANoIAA==.Dreadhunter:BAAALgAECgMJAwAAAA==.Dreamzz:BAAALgADCgMJAwAAAA==.Drixadin:BAAALgAECgQJBwAAAA==.Drshockêr:BAACLgAFFH8HAAIPAAMJ7RuWNADxAAAPAAMJ7RuWNADxAAAuAAQKf08AAw8ACQkTIn0DAHMDAA8ACQkTIn0DAHMDAA4ACAmeDEoUAFcBAAAA.',
Ds='Dsakony:BAABLgAECn8WAAIUAAkJZhTRjABEAQAUAAkJZhTRjABEAQAAAA==.',
Du='Dunthat:BAAALgAECgUJBQAAAA==.Duskdruid:BAAALgAECgUJBQABLgAFFAYJBgAQAIYfAA==.Duthir:BAACLgAFFH8NAAIFAAMJRxSSgADiAAAFAAMJRxSSgADiAAAuAAQKfywAAgUACQldHc8/ADkCAAUACQldHc8/ADkCAAEuAAUUBQkOABUAcBUA.',
Dy='Dyte:BAAALgAECgEJAQAAAA==.',
Ea='East:BAAALgAECgYJEwAAAA==.',
Ed='Edd:BAAALgAECgEJAQAAAA==.',
Eg='Egrok:BAABLgAECn8ZAAIWAAcJVhK3NABPAQAWAAcJVhK3NABPAQAAAA==.',
Em='Emaeel:BAABLgAECn8cAAQXAAgJqRDkMACLAQAXAAgJqRDkMACLAQAYAAgJOQ8OKABhAQAZAAEJpwHooAAYAAAAAA==.Emporia:BAAALgAFFAEJAgAAAA==.',
En='Envyqt:BAAALgADCgEJAQAAAA==.',
Er='Erissel:BAAALgAECgYJBwAAAA==.',
Es='Esso:BAACLgAFFH8VAAMFAAUJiBjBQQBPAQAFAAQJiBjBQQBPAQAQAAEJAADoSgAAAAAuAAQKfxgAAgUABwluFw5fAJoBAAUABwluFw5fAJoBAAAA.',
Fa='Faelenor:BAAALgAECgYJCAAAAA==.Faelure:BAABLgAECn8cAAICAAgJ/QkjrQAIAQACAAgJ/QkjrQAIAQAAAA==.',
Fe='Feyed:BAAALgAECgEJAQAAAA==.',
Fi='Fiddleoux:BAAALgAECgYJEAAAAA==.Fiending:BAAALgAECgEJAQAAAA==.Finnarius:BAAALgADCgYJBgAAAA==.Firenze:BAAALgAECgYJDgAAAA==.Fizzlewar:BAAALgADCgIJAgABLgAFFAMJBQACALkMAQ==.',
Fo='Foros:BAABLgAECn8gAAIKAAgJLSUsEACSAgAKAAgJLSUsEACSAgAAAA==.',
Fr='Frozone:BAABLgAECn8kAAIUAAgJWhh2TQDdAQAUAAgJWhh2TQDdAQAAAA==.Fryiertuck:BAAALgAECgYJCgAAAA==.',
Ga='Gabil:BAABLgAECn8xAAIaAAgJrQnaCwBDAQAaAAgJrQnaCwBDAQAAAA==.Gaunshots:BAAALgAECgQJBwABLgAECggJFQACAMYSAA==.',
Ge='Gendorosan:BAABLgAECn8xAAIbAAgJiyLlCQAMAwAbAAgJiyLlCQAMAwAAAA==.',
Gn='Gnork:BAAALgAECgcJEQABLgAFFAMJBgAbALsIAA==.',
Go='Goldwolf:BAAALgADCgYJBgAAAA==.Gotarrnianan:BAAALgAECgEJBAAAAA==.Gothpally:BAAALgAECgQJBAAAAA==.',
Gr='Grandmasterx:BAAALgAECgIJAwAAAA==.Graveworm:BAAALgAECgEJAQAAAA==.Gravewurm:BAAALgAECgEJAQAAAA==.Grayfoxx:BAABLgAECn8xAAIFAAgJHBsLOgAGAgAFAAgJHBsLOgAGAgAAAA==.Grayhard:BAAALgAECgYJBwAAAA==.Greenhornn:BAAALgAECgkJCQAAAA==.Grìmmgor:BAACLgAFFH8TAAIcAAQJTSLoBgBSAQAcAAQJTSLoBgBSAQAuAAQKfysAAhwACQmDIkwAAIgDABwACQmDIkwAAIgDAAAA.',
Gu='Guerriera:BAAALgAECggJDwAAAA==.Gulkenn:BAAALgADCgcJBwAAAA==.',
['Gô']='Gôôdbye:BAAALgAECgcJEAAAAA==.',
['Gö']='Gööse:BAAALgAECggJEwAAAA==.',
Ha='Hado:BAAALgAECgQJBAAAAA==.Halbrand:BAACLgAFFH8HAAIFAAIJTBJ5tgCQAAAFAAIJTBJ5tgCQAAAuAAQKfxsAAgUACAm8GZxlAIoBAAUACAm8GZxlAIoBAAEuAAUUBQkOAB0A8xYA.Hamburgmeat:BAAALgADCgYJBQAAAA==.',
He='Healovathyme:BAACLgAFFH8IAAIbAAIJqSAeOAC/AAAbAAIJqSAeOAC/AAAuAAQKfxoAAhsACAlxIugVAIcCABsACAlxIugVAIcCAAAA.Hellstomper:BAAALgAECgQJDQAAAA==.Heygrlhey:BAABLgAECn8/AAMMAAkJniNxCQD7AgAMAAkJniNxCQD7AgANAAQJRwe0YAC+AAAAAA==.',
Hi='Hidaoushi:BAAALgADCgkJCQAAAA==.',
Ho='Holdstillbro:BAAALgADCgEJAQABLgAECgkJNgAQAEAhAA==.',
Hu='Hukkaluzul:BAAALgAECgEJAQAAAA==.Humaladin:BAAALgAECgEJAQAAAA==.Humanpaladin:BAABLgAECn8VAAMCAAgJxhJ0cQByAQACAAcJcRN0cQByAQALAAgJcwn1HgAFAQAAAA==.Hungryghost:BAAALgAECgkJCwAAAA==.Hunna:BAABLgAECn8dAAIMAAgJxxpgNQDzAQAMAAgJxxpgNQDzAQAAAA==.Hurtzdonit:BAAALgAECgEJAQAAAA==.',
Hv='Hvtn:BAAALgAECgYJEAAAAA==.',
Ic='Icyfractals:BAAALgADCgQJBQAAAA==.',
In='Inebriated:BAABLgAECn8bAAIMAAgJIgtNcQBIAQAMAAgJIgtNcQBIAQAAAA==.',
Io='Iondia:BAAALgAECgQJCgAAAA==.',
Is='Iselune:BAAALgAECgIJAgAAAA==.',
It='Itwítçh:BAAALgAECgEJAQAAAA==.',
Iz='Izanami:BAAALgAECgEJAQAAAA==.',
Ja='Jambi:BAAALgAECgYJCgAAAA==.Jandrina:BAAALgADCgYJCgAAAA==.Jaraxxus:BAAALgADCgcJBwAAAA==.Jardran:BAAALgAECgEJAgAAAA==.',
Jo='Joanchokkea:BAAALgADCgcJDgAAAA==.Joankorel:BAAALgADCgkJCQAAAA==.Johnconnor:BAAALgADCgYJCgAAAA==.Jolty:BAAALgAECgcJCAABLgAFFAUJFAAFAAUiAA==.',
['Jê']='Jêanne:BAAALgAECgYJCAAAAA==.',
Ka='Kael:BAAALgAECgQJCQAAAA==.Kahira:BAEALgADCgQJBAAAAA==.Kalidra:BAAALgAECgQJBQAAAA==.Kaname:BAAALgADCgYJCQABLgAECgUJEAAeAAAAAA==.',
Ke='Kenpashi:BAAALgADCgYJBgAAAA==.Kermitted:BAAALgAECgEJAgABLgAECgUJBwAeAAAAAA==.',
Ki='Kirlo:BAAALgADCgcJDQAAAA==.Kittytiddies:BAAALgADCgUJBQAAAA==.',
Ko='Kobethama:BAAALgAECgEJBQAAAA==.Kohnan:BAABLgAECn8UAAIHAAgJ2ghBhwD2AAAHAAgJ2ghBhwD2AAAAAA==.Kotoko:BAABLgAECn8ZAAIPAAkJaxrrEwCVAgAPAAkJaxrrEwCVAgAAAA==.',
Kr='Kring:BAAALgAECgEJAQAAAA==.',
Ks='Ksauce:BAABLgAECn8lAAIfAAgJaQMfCgDJAAAfAAgJaQMfCgDJAAAAAA==.',
Ku='Kungfumama:BAAALgAECgEJAQAAAA==.',
Ky='Kynan:BAACLgAFFH8LAAICAAQJ/A3XPQAbAQACAAQJ/A3XPQAbAQAuAAQKfyQAAwIACAmFGs07AP0BAAIACAmFGs07AP0BAAsAAQmfA9RVABMAAAEuAAQKBAkEAB4AAAAA.Kynon:BAABLgAECn8ZAAMYAAYJbRTOMABjAQAYAAYJbRTOMABjAQAXAAEJLgFmdwAUAAABLgAECgQJBAAeAAAAAA==.Kyran:BAAALgAECgQJBAAAAA==.',
La='Laerai:BAAALgADCgcJDAAAAA==.Lament:BAABLgAECn8UAAIHAAgJQxqoKAAUAgAHAAgJQxqoKAAUAgAAAA==.Lamurun:BAAALgAECgQJBAAAAA==.Lancelöt:BAACLgAFFH8JAAICAAQJ0yCmHwBnAQACAAQJ0yCmHwBnAQAuAAQKf0cAAgIACQloJM4GACYDAAIACQloJM4GACYDAAAA.Lastra:BAAALgAECgkJEgABLgAFFAIJBgANAC8ZAA==.Lathina:BAAALgAECgUJBwAAAA==.Lavendere:BAAALgAECgYJEgABLgAFFAUJDgAVAHAVAA==.',
Le='Lectra:BAAALgAECgIJAgAAAA==.Leechang:BAAALgADCgMJAwAAAA==.',
Li='Liiam:BAAALgADCgYJBgAAAA==.Linafox:BAABLgAECn8cAAIUAAgJ1gcjlwAxAQAUAAgJ1gcjlwAxAQAAAA==.Linnëa:BAABLgAFFH8HAAMQAAMJ6hKrIADAAAAQAAMJ6hKrIADAAAAFAAEJUATo9QA6AAAAAA==.Linta:BAAALgADCgcJCQAAAA==.Lizardwizard:BAABLgAECn8XAAIgAAgJQRG4KwB1AQAgAAgJQRG4KwB1AQAAAA==.',
Ll='Llonia:BAAALgADCgMJAwAAAA==.',
Lo='Lockraum:BAAALgAECgMJBAAAAA==.Lokix:BAABLgAECn8yAAIFAAgJoyLBGACgAgAFAAgJoyLBGACgAgAAAA==.',
Lu='Luexis:BAAALgADCgkJFgAAAA==.Luobo:BAAALgADCgQJBQAAAA==.Lustie:BAAALgADCgMJAwAAAA==.',
Ly='Lysistratta:BAABLgAECn82AAIQAAgJWg4VIAA7AQAQAAgJWg4VIAA7AQAAAA==.',
Ma='Magikishi:BAABLgAECn8cAAIUAAgJYR8xOwCKAgAUAAgJYR8xOwCKAgAAAA==.Magimal:BAAALgAECgYJBgABLgAECggJHAAXAKkQAA==.Mahka:BAABLgAECn9GAAMbAAkJByDqDQDaAgAbAAkJByDqDQDaAgAdAAMJHyOeOQASAQABLgADCgEJAQAeAAAAAA==.Mainframe:BAAALgAECgEJAQAAAA==.Maldar:BAAALgAECgIJAgABLgAECggJHAAXAKkQAA==.Maldrakesus:BAAALgADCgEJAQABLgAECggJHAAXAKkQAA==.Malifecent:BAAALgAECgMJAwAAAA==.Manthalus:BAAALgAECgIJAgAAAA==.Marquista:BAAALgAECgcJDQAAAA==.Masika:BAAALgAECgIJAgAAAA==.',
Mc='Mchammer:BAAALgADCgMJAwAAAA==.',
Me='Meatball:BAAALgAECgMJAwAAAA==.Meganstoon:BAAALgAECgMJBAAAAA==.Meladaris:BAAALgAECgQJCwAAAA==.Mey:BAABLgAECn9HAAIGAAkJBRvsEQBSAgAGAAkJBRvsEQBSAgAAAA==.',
Mi='Misfortune:BAAALgADCgUJBQAAAA==.Missperfect:BAAALgAECgcJEQAAAA==.Mitenalla:BAACLgAFFH8VAAICAAUJRheaMgAxAQACAAUJRheaMgAxAQAuAAQKfxoAAgIACAm6GxBJANQBAAIACAm6GxBJANQBAAAA.',
Mo='Morninbreath:BAAALgAECgUJBQAAAA==.Mossberger:BAAALgAECgUJBQAAAA==.',
Mu='Muatahawa:BAAALgAECgMJBQAAAA==.Muglackh:BAAALgAECgcJEwAAAA==.',
My='Myoue:BAAALgAECgMJBQAAAA==.Mysticraven:BAABLgAECn8bAAIdAAgJ7QSGRADgAAAdAAgJ7QSGRADgAAAAAA==.Mythbredor:BAAALgAECgYJBgAAAA==.',
Na='Naariah:BAAALgAECgEJAQAAAA==.Nagendra:BAACLgAFFH8RAAIgAAUJjht9HgA4AQAgAAUJjht9HgA4AQAuAAQKfxwAAiAACQkaIOgHAPoCACAACQkaIOgHAPoCAAAA.Natharion:BAAALgADCgUJCgAAAA==.',
Ne='Neoptolemos:BAAALgAECgQJBQAAAA==.Nezpak:BAAALgADCgcJEAAAAA==.',
Ni='Nicnevin:BAABLgAECn8kAAIaAAgJige9DAAyAQAaAAgJige9DAAyAQAAAA==.Nitrochrist:BAABLgAECn9DAAIBAAkJSRYjOADuAQABAAkJSRYjOADuAQAAAA==.Nixxy:BAAALgAECgYJBgABLgAFFAYJFgAhAMARAA==.',
No='Nokansee:BAAALgADCgQJBAAAAA==.Nokimi:BAAALgAECgUJCAAAAA==.Noobru:BAAALgAECgYJDwAAAA==.Nordathair:BAABLgAECn8hAAIgAAgJvw5nLwBfAQAgAAgJvw5nLwBfAQAAAA==.Nori:BAACLgAFFH8sAAIUAAgJUiRNAgDnAgAUAAgJUiRNAgDnAgAuAAQKfywAAxQACQm9JpoAAPwDABQACQm9JpoAAPwDAB8AAwkSILcPAMcAAAAA.',
Ob='Oblivion:BAAALgADCgQJBAAAAA==.',
On='Onebuttonman:BAAALgAECgEJAQAAAA==.Onlyfoxes:BAAALgAECgIJAgAAAA==.',
Or='Original:BAABLgAECn8WAAICAAgJDSBMIwBhAgACAAgJDSBMIwBhAgAAAA==.Originals:BAAALgAFFAIJBAAAAA==.',
Ot='Otome:BAAALgAECggJEwAAAA==.',
Ov='Overpoweredd:BAAALgAECggJCQAAAA==.',
Pa='Painfulpoo:BAAALgAECgIJAgAAAA==.Parsemae:BAACLgAFFH8QAAIUAAUJixpYPABXAQAUAAUJixpYPABXAQAuAAQKfyMAAxQACAm2HW0vALQCABQACAm2HW0vALQCACIAAQkdD64QADEAAAAA.Pastries:BAACLgAFFH8eAAIHAAgJ7x1KAgAyAgAHAAgJ7x1KAgAyAgAuAAQKfzcAAwcACQmrIrkCAKUDAAcACQmrIrkCAKUDABMAAgnMFBRGAHkAAAAA.',
Pb='Pbd:BAAALgAECgIJAgAAAA==.',
Pi='Pitlin:BAABLgAECn8kAAIjAAkJFiEBBQAmAwAjAAkJFiEBBQAmAwAAAA==.',
Pm='Pmsavenger:BAAALgADCgkJEgAAAA==.',
Po='Polynya:BAAALgAECgQJCgAAAA==.Pooshot:BAAALgAECgYJCwAAAA==.',
Pr='Priestalisha:BAACLgAFFH8nAAIGAAYJmSWxAQBjAgAGAAYJmSWxAQBjAgAuAAQKf0cAAgYACQkWJaAAAM8DAAYACQkWJaAAAM8DAAAA.Prognie:BAAALgADCgcJCAAAAA==.',
Ra='Raelana:BAABLgAECn8xAAICAAgJLgpJkAA3AQACAAgJLgpJkAA3AQAAAA==.Ragetatertot:BAAALgAECgYJDgAAAA==.Ragingpoo:BAABLgAECn8ZAAIFAAkJlxSZPQD6AQAFAAkJlxSZPQD6AQAAAA==.Rakenroll:BAAALgADCggJCAAAAA==.Rawsteak:BAABLgAECn8cAAIQAAkJQhckDgAOAgAQAAkJQhckDgAOAgAAAA==.Razdaz:BAABLgAECn8eAAMjAAcJfh3/FQD0AQAjAAYJxhv/FQD0AQAGAAcJUhnOGgDdAQAAAA==.',
Re='Redcrow:BAABLgAECn8WAAIIAAkJsAYMPABCAQAIAAkJsAYMPABCAQAAAA==.Reheal:BAABLgAECn8eAAIGAAgJjR1wDACKAgAGAAgJjR1wDACKAgAAAA==.Reshocker:BAABLgAECn8tAAIWAAkJghouFwAUAgAWAAkJghouFwAUAgAAAA==.Restosexualz:BAAALgAECgMJBAAAAA==.',
Ri='Rixxy:BAACLgAFFH8WAAMhAAYJwBHpDgCKAQAhAAYJwBHpDgCKAQAgAAEJsAEyXwAxAAAuAAQKfzsAAyEACQmsI0UCAFEDACEACQmsI0UCAFEDACAABwmrC8g+AO8AAAAA.',
Ro='Roastbeefdr:BAABLgAECn9EAAMQAAkJ8STaAQA0AwAQAAkJ8STaAQA0AwAFAAQJwR6qvADuAAAAAA==.Roderigo:BAABLgAECn8lAAIbAAgJBRFxOQCfAQAbAAgJBRFxOQCfAQAAAA==.Root:BAAALgAECgYJEQAAAA==.',
Ru='Runian:BAAALgAECgUJCwAAAA==.',
Sa='Sadlypink:BAABLgAECn8XAAIUAAcJLBRKhwDDAQAUAAcJLBRKhwDDAQAAAA==.Saisaith:BAACLgAFFH8OAAIVAAUJcBWVEwAsAQAVAAUJcBWVEwAsAQAuAAQKfxwAAxUACQlHGYgMAHACABUACQlHGYgMAHACAAYAAQlkBe5vACQAAAAA.Sanarian:BAAALgADCgMJAwAAAA==.Sand:BAABLgAECn8kAAIFAAcJLhU8aAC9AQAFAAcJLhU8aAC9AQAAAA==.Sandy:BAAALgAECgcJBQAAAA==.Savadar:BAAALgAECggJDwAAAA==.Saymourcox:BAAALgAECgcJCwAAAA==.',
Se='Seadra:BAAALgADCggJDQABLgAECgYJFAALAM4ZAA==.Sealyboi:BAAALgADCgQJBAAAAA==.Serpeng:BAABLgAECn8bAAMTAAgJEBG4HgBjAQATAAgJ1g+4HgBjAQASAAYJ9Qr+FwDIAAAAAA==.Setareh:BAABLgAECn8YAAIUAAgJvwaaowAcAQAUAAgJvwaaowAcAQAAAA==.Settra:BAAALgADCgcJDAAAAA==.',
Sh='Shakuru:BAABLgAECn8yAAIUAAkJyw70WQC4AQAUAAkJyw70WQC4AQAAAA==.Shanta:BAAALgAECgMJAwAAAA==.Shkar:BAABLgAECn9XAAIIAAkJPBpgGACJAgAIAAkJPBpgGACJAgAAAA==.Shokan:BAAALgAECgYJCgAAAA==.',
Si='Silanah:BAAALgADCgEJAQAAAA==.Silandrya:BAAALgAECgMJAwAAAA==.Sildin:BAAALgAECgUJCAAAAA==.Silverclaws:BAAALgAECgcJBwAAAA==.',
Sj='Sjaridin:BAEALgAECgQJDAABLgAFFAYJIAAkAFIDAA==.',
Sk='Skittle:BAABLgAECn8rAAMkAAcJVQkAMQDDAAAkAAcJVQkAMQDDAAAbAAUJdALplwBwAAAAAA==.Skullhunter:BAABLgAFFH8HAAQNAAYJKR39GgCqAAANAAQJXiH9GgCqAAAlAAEJ2RUMLABNAAAMAAEJ3BcuiABIAAAAAA==.',
Sl='Slenderama:BAAALgADCgYJCQAAAA==.Slenderella:BAAALgADCgUJBQAAAA==.',
Sm='Small:BAAALgADCgEJAQAAAA==.Smawbrawl:BAAALgAECggJCQAAAA==.Smoothroller:BAABLgAECn8jAAIXAAgJAxWeIQDrAQAXAAgJAxWeIQDrAQAAAA==.',
So='Sogen:BAAALgADCgMJAwAAAA==.Soloxtremist:BAAALgADCgEJAQAAAA==.Soulripper:BAAALgAECgEJAQABLgAECggJFAAHANoIAA==.',
St='Staysalty:BAAALgADCgEJAQAAAA==.Stickyricky:BAAALgADCgUJCgAAAA==.Strongmandan:BAAALgAECgEJAQAAAA==.Stubs:BAAALgADCgYJDAAAAA==.',
Su='Sule:BAEBLgAECn88AAIUAAkJRhYPQQADAgAUAAkJRhYPQQADAgAAAA==.',
Sw='Sweetpea:BAAALgAFFAEJAQABLgAFFAYJGAAZAK8YAA==.',
['Sä']='Sämuel:BAAALgAECgEJAQAAAA==.',
Ta='Tanks:BAAALgAECgIJAgAAAA==.',
Th='Thelorax:BAACLgAFFH8FAAIHAAMJyAajYQCrAAAHAAMJyAajYQCrAAAuAAQKfx8AAgcACQlDEAY+ALoBAAcACQlDEAY+ALoBAAAA.Theyeti:BAAALgADCgEJAgABLgADCgQJBwAeAAAAAA==.Thhee:BAABLgAECn8wAAImAAgJRhr1EAANAgAmAAgJRhr1EAANAgAAAA==.Thumbelyna:BAABLgAECn8jAAMbAAgJtRvYHQBGAgAbAAgJtRvYHQBGAgAkAAEJMQrzNQAeAAAAAA==.',
To='Towelp:BAAALgAECgYJCAABLgAFFAUJHQAVADAeAA==.',
Ts='Tsuro:BAAALgAECgcJCwAAAA==.',
Tu='Tukktukk:BAAALgAECgEJAQAAAA==.',
Ty='Tyrini:BAAALgADCgIJAgAAAA==.',
Um='Umie:BAAALgAECgEJAQAAAA==.',
Un='Unholylife:BAABLgAECn8aAAICAAgJSAZ1sAADAQACAAgJSAZ1sAADAQAAAA==.',
Up='Up:BAABLgAECn8VAAISAAcJVB/nBABjAgASAAcJVB/nBABjAgAAAA==.',
Va='Valasi:BAAALgAECgEJAwAAAA==.',
Ve='Velocet:BAACLgAFFH8VAAImAAUJMQvrGgAnAQAmAAUJMQvrGgAnAQAuAAQKfzcAAyYACQm0GngVAGQCACYACQm0GngVAGQCAAkAAwmICL0WAIsAAAAA.Vetlance:BAAALgAECgQJBQAAAA==.',
Vo='Voroak:BAAALgADCgYJBgAAAA==.',
Wa='Waghdaddy:BAABLgAECn8pAAICAAkJlCJyEgDBAgACAAkJlCJyEgDBAgAAAA==.Waghiechan:BAAALgAECgcJDQAAAA==.',
We='Werewolf:BAAALgAECgUJBQAAAA==.',
Wh='Whatøncewas:BAAALgAFFAEJAQAAAA==.Whitfield:BAAALgADCgUJBQAAAA==.Whordie:BAAALgAECgEJAQAAAA==.',
Wi='Wildlily:BAAALgADCgkJCQABLgAFFAQJBAAeAAAAAA==.Wistful:BAAALgAECgQJBwAAAA==.',
Wo='Wobiwabi:BAAALgADCgIJAgAAAA==.',
Wr='Wratheon:BAACLgAFFH8VAAIZAAUJiiJGDQCXAQAZAAUJiiJGDQCXAQAuAAQKfzsAAxkACQm4HvUGALgCABkACQm4HvUGALgCABgAAgmxC4CXACsAAAAA.',
Wu='Wuji:BAABLgAECn8xAAIjAAgJHA1cJgB8AQAjAAgJHA1cJgB8AQAAAA==.',
['Wê']='Wêrewôlf:BAAALgADCgUJBQAAAA==.',
Xa='Xablau:BAAALgAECgYJBgAAAA==.',
Ye='Yeli:BAAALgAECggJEAAAAA==.',
Za='Zardasa:BAAALgAECgIJAgABLgADCgQJBwAeAAAAAA==.',
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
