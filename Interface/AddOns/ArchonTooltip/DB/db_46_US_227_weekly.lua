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
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=46,date='2026-06-07',data={Ab='Abharn:BAAALgAECgYJDQAAAA==.',
Ag='Agoneer:BAAALgAECgQJBwAAAA==.',
Ak='Akeera:BAABLgAECn8VAAIBAAcJUA5ghwAmAQABAAcJUA5ghwAmAQAAAA==.Akkiya:BAAALgAECgYJDwABLgAFFAUJFQACAEYXAA==.',
Al='Althtar:BAAALgADCgQJBAAAAA==.',
Am='Amalyn:BAAALgAECgYJCAAAAA==.Amarantha:BAABLgAECn8gAAMDAAkJBwghGgDJAAADAAcJDwchGgDJAAABAAMJ0AnJ3ACYAAAAAA==.',
An='Anaesthetize:BAAALgAECgYJCAAAAA==.Aness:BAABLgAECn8hAAIEAAgJagOEKwDRAAAEAAgJagOEKwDRAAAAAA==.Angelinalizy:BAAALgAECgMJAwAAAA==.Animagon:BAAALgAECgQJAwAAAA==.Animaker:BAABLgAECn8vAAIFAAkJDBa5OwAMAgAFAAkJDBa5OwAMAgAAAA==.Anngus:BAAALgAECgEJAQAAAA==.Anvilkrash:BAAALgADCgcJCwAAAA==.',
Ar='Ariese:BAAALgADCgcJCAAAAA==.',
As='Ashido:BAABLgAECn8VAAIGAAYJJhzCHQDLAQAGAAYJJhzCHQDLAQAAAA==.Astreos:BAABLgAFFH8NAAIBAAUJOR0APABIAQABAAUJOR0APABIAQABLgAFFAgJHgAHAO8dAA==.Astrikin:BAAALgAECgYJDwABLgAFFAgJHgAHAO8dAA==.',
Au='Auraiel:BAAALgADCgcJFAAAAA==.Aurhon:BAAALgAECgYJDAAAAA==.Aurorastar:BAAALgAECgEJAQAAAA==.',
Ba='Bagawgwah:BAAALgAECgEJAwAAAA==.Baluu:BAAALgAECgQJBAAAAA==.Baultier:BAAALgADCgkJDgAAAA==.',
Be='Bel:BAABLgAECn89AAIEAAkJACXCAQA1AwAEAAkJACXCAQA1AwAAAA==.Beraxes:BAABLgAECn8nAAIIAAgJ0xG0KwCgAQAIAAgJ0xG0KwCgAQAAAA==.Bethäny:BAAALgAECgQJAQAAAA==.',
Bl='Blasser:BAABLgAECn8fAAIJAAkJ6BqYBAA9AgAJAAkJ6BqYBAA9AgAAAA==.Blizizdumz:BAACLgAFFH8MAAMCAAQJQBFtQQAcAQACAAQJQBFtQQAcAQAKAAEJEQpuSQAyAAAuAAQKfzgABAIACQmZHnwcAJACAAIACQmFHXwcAJACAAsABgm7IowRAKEBAAoAAQmYAouaAB8AAAAA.',
Bm='Bmcgilicuddy:BAAALgAECgYJCwAAAA==.',
Br='Bralindra:BAAALgAECgEJAgAAAA==.Breadpitt:BAAALgAECggJEQAAAA==.Brewdhism:BAAALgAECgMJAwAAAA==.Brillane:BAAALgAECgMJAwAAAA==.',
Bu='Bulsy:BAACLgAFFH8UAAMMAAUJdR6EJwBXAQAMAAUJdR6EJwBXAQANAAEJcgGHNwAsAAAuAAQKfyQAAwwACQnwHfARALgCAAwACQnwHfARALgCAA0ABAmQBOtoAJsAAAAA.',
Ca='Calamidade:BAABLgAECn8rAAMOAAkJfQTcGQAnAQAOAAkJfQTcGQAnAQAPAAMJdwHXxwA4AAAAAA==.Calashlar:BAAALgAECgIJBQAAAA==.Camri:BAAALgADCgMJAwAAAA==.Capwnd:BAAALgAECgMJAwAAAA==.',
Ce='Cerryan:BAABLgAECn8zAAIKAAkJUQ9bJwDGAQAKAAkJUQ9bJwDGAQAAAA==.Cexar:BAABLgAECn8ZAAIIAAcJgA3pPgBCAQAIAAcJgA3pPgBCAQAAAA==.',
Ch='Chaoticprime:BAAALgADCgQJBwAAAA==.Charivium:BAAALgADCgQJBAAAAA==.Charo:BAABLgAECn8WAAMQAAkJ8hLbJACBAQAQAAYJ5RPbJACBAQARAAgJUA9YJgB1AQAAAA==.Chaòs:BAAALgADCgMJAwAAAA==.Chinup:BAABLgAECn82AAISAAkJQCGgCACDAgASAAkJQCGgCACDAgAAAA==.',
Cl='Clother:BAACLgAFFH8YAAMIAAUJQSRLBACwAQAIAAUJ7RhLBACwAQATAAUJQST3AQBkAQAuAAQKfxoAAwgACAkEIfYKAAQDAAgACAkEIfYKAAQDABMABgnmIGEHAEkCAAEuAAUUBgkUAAUAkB0A.',
Co='Cokenopepsi:BAABLgAECn8ZAAISAAgJiB4eEQDvAQASAAgJiB4eEQDvAQAAAA==.Cormigo:BAAALgAECgcJCAAAAA==.',
Cr='Crackle:BAAALgADCgcJDAAAAA==.Crazyhorse:BAAALgAECgYJCwAAAA==.Cristos:BAAALgADCgYJCwAAAA==.Crusade:BAAALgADCgYJBgAAAA==.',
Cu='Curses:BAAALgAECggJEAABLgAECgkJGAACAE0TAA==.',
['Cø']='Cøløssus:BAAALgAECgEJAQAAAA==.',
Da='Daddypie:BAABLgAECn8+AAQUAAkJ0iQAAQA0AwAUAAkJ0iQAAQA0AwAVAAEJdR3DWwBJAAAHAAEJ7AweAQE8AAAAAA==.Damasscus:BAAALgAECgcJDQAAAA==.Darkdesire:BAAALgADCgUJBQAAAA==.',
De='Deathkanight:BAAALgAECgQJBQAAAA==.Desdakharii:BAAALgAECgEJAQAAAA==.',
Di='Diktug:BAAALgAECgEJAQAAAA==.Disney:BAABLgAECn8WAAIJAAcJshLOCgCDAQAJAAcJshLOCgCDAQAAAA==.',
Dj='Djaztech:BAACLgAFFH8KAAMTAAUJNxWrGAANAQATAAQJgxKrGAANAQAIAAMJxRMyPQCXAAAuAAQKfyYAAwgACQnFIr0QAGsCAAgACAnxIb0QAGsCABMABwlQGikRANgBAAAA.',
Do='Donkie:BAABLgAECn8gAAIMAAgJUxyMKAAzAgAMAAgJUxyMKAAzAgAAAA==.',
Dr='Dracsano:BAAALgAFFAIJAgAAAA==.Dreadhunter:BAAALgAECgMJAwAAAA==.Dreamzz:BAAALgADCgMJAwAAAA==.Drixadin:BAAALgAECgQJBwAAAA==.Drshockêr:BAACLgAFFH8LAAIPAAQJpRkJJwA0AQAPAAQJpRkJJwA0AQAuAAQKf1MAAw8ACQlnIr8DAHgDAA8ACQlnIr8DAHgDAA4ACAmeDLsVAFcBAAAA.',
Ds='Dsakony:BAABLgAECn8WAAIWAAkJZhTamQBCAQAWAAkJZhTamQBCAQAAAA==.',
Du='Dunthat:BAAALgAECgUJBQAAAA==.Duskdruid:BAAALgAECgUJBQABLgAFFAYJBwASAHYiAA==.Duthir:BAACLgAFFH8NAAIFAAMJRxSsjQDhAAAFAAMJRxSsjQDhAAAuAAQKfywAAgUACQldHc8/ADkCAAUACQldHc8/ADkCAAEuAAUUBQkOABcAcBUA.',
Dy='Dyte:BAAALgAECgEJAQAAAA==.',
Ea='East:BAAALgAECgYJEwAAAA==.',
Ed='Edd:BAAALgAECgEJAQAAAA==.',
Eg='Egrok:BAABLgAECn8ZAAIYAAcJVhLrNwBLAQAYAAcJVhLrNwBLAQAAAA==.',
Em='Emaeel:BAABLgAECn8fAAQZAAkJfBJGNQCKAQAZAAgJqRBGNQCKAQAQAAgJOQ/kKgBaAQARAAQJJgSJXACUAAAAAA==.Emporia:BAAALgAFFAEJAgAAAA==.',
En='Envyqt:BAAALgADCgEJAQAAAA==.',
Er='Erissel:BAAALgAECgcJCAAAAA==.',
Es='Esso:BAACLgAFFH8VAAMFAAUJiBj0SwBMAQAFAAQJiBj0SwBMAQASAAEJAAAwUgAAAAAuAAQKfxgAAgUABwluFyJkAJgBAAUABwluFyJkAJgBAAAA.',
Fa='Faelenor:BAAALgAECgYJCAAAAA==.Faelure:BAABLgAECn8cAAICAAgJ/QkpsgARAQACAAgJ/QkpsgARAQAAAA==.',
Fe='Feyed:BAAALgAECgEJAgAAAA==.',
Fi='Fiddleoux:BAAALgAECgYJEAAAAA==.Fiending:BAAALgAECgEJAQAAAA==.Finnarius:BAAALgADCgYJBgAAAA==.Firenze:BAAALgAECgYJDgAAAA==.Fizzlewar:BAAALgADCgIJAgABLgAFFAQJDAACAEARAQ==.',
Fo='Foros:BAABLgAECn8jAAIKAAkJ5SFsDwCYAgAKAAkJ5SFsDwCYAgAAAA==.',
Fr='Frozone:BAABLgAECn8kAAIWAAgJWhj1UQDhAQAWAAgJWhj1UQDhAQAAAA==.Fryiertuck:BAAALgAECgYJCgAAAA==.',
Ga='Gabil:BAABLgAECn80AAIaAAkJcQlcCgBvAQAaAAkJcQlcCgBvAQAAAA==.Gaunshots:BAAALgAECgQJBwABLgAECgkJGAACAE0TAA==.',
Ge='Gendorosan:BAABLgAECn80AAIbAAkJmyGEBQBZAwAbAAkJmyGEBQBZAwAAAA==.',
Gn='Gnork:BAAALgAECgcJEQABLgAFFAMJBgAbALsIAA==.',
Go='Goldwolf:BAAALgAECgYJBwAAAA==.Gotarrnianan:BAAALgAECgEJBAAAAA==.Gothpally:BAAALgAECgQJBAAAAA==.',
Gr='Grandmasterx:BAAALgAECgIJAwAAAA==.Graveworm:BAAALgAECgEJAgAAAA==.Gravewurm:BAAALgAECgEJAQAAAA==.Grayfoxx:BAABLgAECn80AAIFAAkJaxopKQBWAgAFAAkJaxopKQBWAgAAAA==.Grayhard:BAAALgAECgYJBwAAAA==.Greenhornn:BAAALgAECgkJCQAAAA==.Grìmmgor:BAACLgAFFH8TAAIcAAQJTSKrAAA2AQAcAAQJTSKrAAA2AQAuAAQKfysAAhwACQmDIkwAAIgDABwACQmDIkwAAIgDAAAA.',
Gu='Guerriera:BAAALgAECggJDwAAAA==.Gulkenn:BAAALgADCgcJBwAAAA==.',
['Gô']='Gôôdbye:BAAALgAECggJEAAAAA==.',
['Gö']='Gööse:BAABLgAECn8VAAICAAkJwgs6bACMAQACAAkJwgs6bACMAQAAAA==.',
Ha='Hado:BAAALgAECgQJBAAAAA==.Halbrand:BAACLgAFFH8IAAIFAAIJTBLayQCNAAAFAAIJTBLayQCNAAAuAAQKfxsAAgUACAm8GZBqAIoBAAUACAm8GZBqAIoBAAEuAAUUBgkQAB0AHBQA.Hamburgmeat:BAAALgADCgYJBQAAAA==.',
He='Healovathyme:BAACLgAFFH8IAAIbAAIJqSBKOwC8AAAbAAIJqSBKOwC8AAAuAAQKfxoAAhsACAlxIugVAIcCABsACAlxIugVAIcCAAAA.Hellstomper:BAAALgAECgQJDQAAAA==.Heygrlhey:BAACLgAFFH8FAAIMAAMJuhSKUgDsAAAMAAMJuhSKUgDsAAAuAAQKfz8AAwwACQmeIwoLAPQCAAwACQmeIwoLAPQCAA0ABAlHB7RgAL4AAAAA.',
Hi='Hidaoushi:BAAALgADCgkJCQAAAA==.',
Ho='Holdstillbro:BAAALgADCgEJAQABLgAECgkJNgASAEAhAA==.',
Hu='Hukkaluzul:BAAALgAECgEJAQAAAA==.Humaladin:BAAALgAECgEJAQAAAA==.Humanpaladin:BAABLgAECn8YAAMCAAkJTRMmWAC6AQACAAgJ8xMmWAC6AQALAAgJcwn3IAABAQAAAA==.Hungryghost:BAAALgAECgkJCwAAAA==.Hunna:BAABLgAECn8dAAIMAAgJxxoHOgDtAQAMAAgJxxoHOgDtAQAAAA==.Hurtzdonit:BAAALgAECgIJAgAAAA==.',
Hv='Hvtn:BAAALgAECgYJEAAAAA==.',
Ic='Icyfractals:BAAALgADCgQJBQAAAA==.',
In='Inebriated:BAABLgAECn8bAAIMAAgJIgtveABEAQAMAAgJIgtveABEAQAAAA==.',
Io='Iondia:BAAALgAECgQJCgAAAA==.',
Is='Iselune:BAAALgAECgIJAgAAAA==.',
It='Itwítçh:BAAALgAECgEJAgAAAA==.',
Iz='Izanami:BAAALgAECgEJAQAAAA==.',
Ja='Jambi:BAAALgAECgYJDAAAAA==.Jandrina:BAAALgADCgYJCgAAAA==.Jaraxxus:BAAALgADCgcJBwAAAA==.Jardran:BAAALgAECgEJAgAAAA==.',
Jo='Joanchokkea:BAAALgADCgcJDgAAAA==.Joankorel:BAAALgADCgkJCQAAAA==.Johnconnor:BAAALgADCgYJCgAAAA==.Jolty:BAAALgAECgcJCAABLgAFFAYJFQAFAEMgAA==.',
['Jê']='Jêanne:BAAALgAECgcJDwAAAA==.',
Ka='Kael:BAAALgAECgUJCgAAAA==.Kahira:BAEALgADCgQJBAAAAA==.Kalidra:BAAALgAECgQJBQAAAA==.Kaname:BAAALgADCgYJCQABLgAECgUJEAAeAAAAAA==.',
Ke='Kenpashi:BAAALgADCgYJBgAAAA==.Kermitted:BAAALgAECgEJAgABLgAECgYJCAAeAAAAAA==.',
Ki='Kirlo:BAAALgADCgcJDQAAAA==.Kittytiddies:BAAALgADCgUJBQAAAA==.',
Ko='Kobethama:BAAALgAECgEJBQAAAA==.Kohnan:BAABLgAECn8UAAIHAAgJ2ghPjAD7AAAHAAgJ2ghPjAD7AAABLgAFFAIJAgAeAAAAAA==.Kotoko:BAABLgAECn8eAAIPAAkJmRqRFACcAgAPAAkJmRqRFACcAgAAAA==.',
Kr='Kring:BAAALgAECggJCQAAAA==.',
Ks='Ksauce:BAABLgAECn8oAAIfAAkJ0wPxCQDZAAAfAAkJ0wPxCQDZAAAAAA==.',
Ku='Kungfumama:BAAALgAECgEJAQAAAA==.',
Ky='Kynan:BAACLgAFFH8PAAICAAQJaRPaPAAkAQACAAQJaRPaPAAkAQAuAAQKfyUAAwIACAmFGjs/AP8BAAIACAmFGjs/AP8BAAsAAQmfA0RaABMAAAEuAAQKBAkEAB4AAAAA.Kynon:BAABLgAECn8ZAAMQAAYJbRTOMABjAQAQAAYJbRTOMABjAQAZAAEJLgFmdwAUAAABLgAECgQJBAAeAAAAAA==.Kyran:BAAALgAECgQJBAAAAA==.',
La='Laerai:BAAALgADCgcJDAAAAA==.Lament:BAABLgAECn8UAAIHAAgJQxq8KwAPAgAHAAgJQxq8KwAPAgAAAA==.Lamurun:BAAALgAECgQJBAAAAA==.Lancelöt:BAACLgAFFH8JAAICAAQJ0yCtJgBdAQACAAQJ0yCtJgBdAQAuAAQKf0cAAgIACQloJPEHACUDAAIACQloJPEHACUDAAAA.Lastra:BAAALgAECgkJEgABLgAECgcJGAAHAGMZAA==.Lathina:BAAALgAECgYJCAAAAA==.Lavendere:BAAALgAECgYJEgABLgAFFAUJDgAXAHAVAA==.',
Le='Lectra:BAAALgAECgIJAgAAAA==.Leechang:BAAALgADCgMJAwAAAA==.',
Li='Liiam:BAAALgADCgYJBgAAAA==.Linafox:BAABLgAECn8lAAIWAAkJTggbcwCOAQAWAAkJTggbcwCOAQAAAA==.Linnëa:BAABLgAFFH8HAAMSAAMJ6hL5JAC4AAASAAMJ6hL5JAC4AAAFAAEJUAT9CQE4AAAAAA==.Linta:BAAALgADCgcJCQAAAA==.Lizardwizard:BAABLgAECn8XAAIgAAgJQRG8LgB1AQAgAAgJQRG8LgB1AQAAAA==.',
Ll='Llonia:BAAALgADCgMJAwAAAA==.',
Lo='Lockraum:BAAALgAECgMJBAAAAA==.Lokix:BAABLgAECn80AAIFAAkJ+CEFDgD2AgAFAAkJ+CEFDgD2AgAAAA==.',
Lu='Luexis:BAAALgADCgkJFgAAAA==.Luobo:BAAALgADCgQJBQAAAA==.Lustie:BAAALgADCgMJAwAAAA==.',
Ly='Lysistratta:BAABLgAECn85AAISAAkJdA1WHABsAQASAAkJdA1WHABsAQAAAA==.',
Ma='Magikishi:BAABLgAECn8cAAIWAAgJYR8xOwCKAgAWAAgJYR8xOwCKAgAAAA==.Magimal:BAAALgAECgYJBgABLgAECgkJHwAZAHwSAA==.Mahka:BAACLgAFFH8FAAIbAAMJQwm0RACeAAAbAAMJQwm0RACeAAAuAAQKf0gABBsACQkHIK4OANkCABsACQkHIK4OANkCAB0AAwkfI4g8ABEBACEAAgmtDnpVAFUAAAEuAAMKAQkBAB4AAAAA.Mainframe:BAAALgAECgEJAQAAAA==.Maldar:BAAALgAECgIJAgABLgAECgkJHwAZAHwSAA==.Maldrakesus:BAAALgADCgEJAQABLgAECgkJHwAZAHwSAA==.Malifecent:BAAALgAECgMJAwAAAA==.Manthalus:BAAALgAECgIJAgAAAA==.Marquista:BAAALgAECgcJEwAAAA==.Masika:BAAALgAECgIJAgAAAA==.',
Mc='Mchammer:BAAALgADCgMJAwAAAA==.',
Me='Meatball:BAAALgAECgMJAwAAAA==.Meganstoon:BAAALgAECgMJBAAAAA==.Meladaris:BAAALgAECgQJCwAAAA==.Mey:BAABLgAECn9HAAIGAAkJBRvsEQBSAgAGAAkJBRvsEQBSAgAAAA==.',
Mi='Misfortune:BAAALgADCgUJBQAAAA==.Missperfect:BAAALgAECgcJEQAAAA==.Mitenalla:BAACLgAFFH8VAAICAAUJRhclOwAoAQACAAUJRhclOwAoAQAuAAQKfxoAAgIACAm6G+1NANQBAAIACAm6G+1NANQBAAAA.',
Mo='Mokris:BAAALgAECgQJBAAAAA==.Morninbreath:BAAALgAECgUJBQAAAA==.Mossberger:BAAALgAECgUJBQAAAA==.',
Mu='Muatahawa:BAAALgAECgMJBQAAAA==.Muglackh:BAAALgAECgcJEwAAAA==.',
My='Myoue:BAAALgAECgMJBQAAAA==.Mysticraven:BAABLgAECn8dAAIdAAkJ3wVuOwAXAQAdAAkJ3wVuOwAXAQAAAA==.Mythbredor:BAAALgAECgYJBgAAAA==.',
Na='Naariah:BAAALgAECgEJAQAAAA==.Nagendra:BAACLgAFFH8RAAIgAAUJjhuMIwAxAQAgAAUJjhuMIwAxAQAuAAQKfxwAAiAACQkaIOgHAPoCACAACQkaIOgHAPoCAAAA.Natharion:BAAALgADCgUJCgAAAA==.',
Ne='Neoptolemos:BAAALgAECgUJBwAAAA==.Nezpak:BAAALgADCgcJEAAAAA==.',
Ni='Nicnevin:BAABLgAECn8tAAIaAAkJQQpzCQCGAQAaAAkJQQpzCQCGAQAAAA==.Nitrochrist:BAABLgAECn9DAAIBAAkJSRbjOgDpAQABAAkJSRbjOgDpAQAAAA==.Nixxy:BAAALgAECgYJBwABLgAFFAYJFgAiAMARAA==.',
No='Nokansee:BAAALgADCgQJBAAAAA==.Nokimi:BAAALgAECgUJCAAAAA==.Noobru:BAAALgAECgYJDwAAAA==.Nordathair:BAABLgAECn8jAAIgAAkJyQ6QJACwAQAgAAkJyQ6QJACwAQAAAA==.Nori:BAACLgAFFH8vAAMWAAgJUiQCBADbAgAWAAgJUiQCBADbAgAjAAIJdiSlAgDbAAAuAAQKfywAAxYACQm9JpoAAPwDABYACQm9JpoAAPwDAB8AAwkSILcPAMcAAAAA.',
Ob='Oblivion:BAAALgADCgQJBAAAAA==.',
On='Onebuttonman:BAAALgAECgEJAQAAAA==.Onlyfoxes:BAAALgAECgIJAgAAAA==.',
Or='Original:BAACLgAFFH8HAAICAAMJBRwVUwD6AAACAAMJBRwVUwD6AAAuAAQKfxYAAgIACAkNIH4mAGACAAIACAkNIH4mAGACAAAA.Originals:BAABLgAFFH8FAAIFAAIJYRLTxwCPAAAFAAIJYRLTxwCPAAAAAA==.',
Ot='Otome:BAAALgAECggJEwAAAA==.',
Ov='Overpoweredd:BAAALgAECggJCQAAAA==.',
Pa='Painfulpoo:BAAALgAECgIJAgAAAA==.Parsemae:BAACLgAFFH8QAAIWAAUJixonRQBTAQAWAAUJixonRQBTAQAuAAQKfyMAAxYACAm2HW0vALQCABYACAm2HW0vALQCACMAAQkdD64QADEAAAAA.Pastries:BAACLgAFFH8eAAIHAAgJ7x1KAgAyAgAHAAgJ7x1KAgAyAgAuAAQKfzcAAwcACQmrIrkCAKUDAAcACQmrIrkCAKUDABUAAgnMFK5KAHkAAAAA.',
Pb='Pbd:BAAALgAECgIJAgAAAA==.',
Pi='Pitlin:BAABLgAECn8kAAIkAAkJFiFpBQAqAwAkAAkJFiFpBQAqAwAAAA==.',
Pm='Pmsavenger:BAAALgADCgkJEgAAAA==.',
Po='Polynya:BAAALgAECgQJCgAAAA==.Pooshot:BAAALgAECgYJCwAAAA==.',
Pr='Priestalisha:BAACLgAFFH8oAAIGAAcJdyQFAQC0AgAGAAcJdyQFAQC0AgAuAAQKf0oAAgYACQmtJjsAAO0DAAYACQmtJjsAAO0DAAAA.Prognie:BAAALgADCgcJCAAAAA==.',
Ra='Raelana:BAABLgAECn8zAAICAAkJzQlIewBtAQACAAkJzQlIewBtAQAAAA==.Ragetatertot:BAAALgAECgYJDgAAAA==.Ragingpoo:BAABLgAECn8ZAAIFAAkJlxQ7QQD5AQAFAAkJlxQ7QQD5AQAAAA==.Rakenroll:BAAALgADCggJCAAAAA==.Rawsteak:BAABLgAECn8cAAISAAkJPRc6DwALAgASAAkJPRc6DwALAgAAAA==.Razdaz:BAABLgAECn8eAAMkAAcJfh3/FQD0AQAkAAYJxhv/FQD0AQAGAAcJUhmTHADVAQAAAA==.',
Re='Redcrow:BAABLgAECn8WAAIIAAkJsAb2PgBCAQAIAAkJsAb2PgBCAQAAAA==.Reheal:BAABLgAECn8eAAIGAAgJjR14DQCDAgAGAAgJjR14DQCDAgAAAA==.Reshocker:BAABLgAECn8tAAIYAAkJghrAGAARAgAYAAkJghrAGAARAgAAAA==.Restosexualz:BAAALgAECgMJBAAAAA==.',
Ri='Rixxy:BAACLgAFFH8WAAMiAAYJwBHHCABdAQAiAAYJwBHHCABdAQAgAAEJsAGRZQAxAAAuAAQKfzsAAyIACQmsI0UCAFEDACIACQmsI0UCAFEDACAABwmrC8g+AO8AAAAA.',
Ro='Roastbeefdr:BAACLgAFFH8GAAMSAAMJ6h0HGwD7AAASAAMJ6h0HGwD7AAAFAAEJhh2X8QBVAAAuAAQKf0gAAxIACQnxJA8CADMDABIACQnxJA8CADMDAAUABAnBHkHGAO0AAAAA.Roderigo:BAABLgAECn8lAAIbAAgJBRFGOwCfAQAbAAgJBRFGOwCfAQAAAA==.Root:BAAALgAECgYJEQAAAA==.',
Ru='Runian:BAAALgAECgUJCwAAAA==.',
Sa='Sadlypink:BAABLgAECn8XAAIWAAcJLBRKhwDDAQAWAAcJLBRKhwDDAQAAAA==.Saisaith:BAACLgAFFH8OAAIXAAUJcBXMFQAmAQAXAAUJcBXMFQAmAQAuAAQKfxwAAxcACQlHGaINAHQCABcACQlHGaINAHQCAAYAAQlkBWl1AB8AAAAA.Sanarian:BAAALgADCgMJAwAAAA==.Sand:BAACLgAFFH8JAAIFAAUJKhRLKwCeAQAFAAUJKhRLKwCeAQAuAAQKfyQAAgUABwkuFTxoAL0BAAUABwkuFTxoAL0BAAAA.Sandy:BAAALgAECgcJBQAAAA==.Savadar:BAAALgAECgkJEQAAAA==.Saymourcox:BAAALgAECggJDAAAAA==.',
Se='Seadra:BAAALgADCggJDQABLgAECgYJFAALAM4ZAA==.Sealyboi:BAAALgADCgQJBAAAAA==.Serpeng:BAABLgAECn8bAAMVAAgJEBFHIQBdAQAVAAgJ1g9HIQBdAQAUAAYJ9QpgGQDGAAAAAA==.Setareh:BAABLgAECn8YAAIWAAgJvwb+ogAyAQAWAAgJvwb+ogAyAQAAAA==.Settra:BAAALgADCgcJDAAAAA==.',
Sh='Shakuru:BAABLgAECn8yAAIWAAkJyw5+XADEAQAWAAkJyw5+XADEAQAAAA==.Shanta:BAAALgAECgMJAwAAAA==.Shkar:BAACLgAFFH8JAAIIAAMJrgm0NQDHAAAIAAMJrgm0NQDHAAAuAAQKf2AAAggACQnhGh8RAGcCAAgACQnhGh8RAGcCAAAA.Shokan:BAAALgAECgYJCwAAAA==.',
Si='Silanah:BAAALgADCgEJAQAAAA==.Silandrya:BAAALgAECgMJAwAAAA==.Sildin:BAAALgAECgUJCAAAAA==.Silverclaws:BAAALgAECgcJBwAAAA==.',
Sj='Sjaridin:BAEALgAECgQJDAABLgAFFAYJIAAhAFIDAA==.',
Sk='Skittle:BAABLgAECn8sAAQhAAgJCAk+NQDAAAAhAAcJVQk+NQDAAAAbAAUJdALsnABuAAAlAAEJPQdlXQAWAAAAAA==.Skullhunter:BAABLgAFFH8HAAQNAAYJKR34HQCmAAANAAQJXiH4HQCmAAAmAAEJ2RVpLgBLAAAMAAEJ3BcvlQBIAAAAAA==.',
Sl='Slenderama:BAAALgADCgYJCQAAAA==.Slenderella:BAAALgADCgUJBQAAAA==.',
Sm='Small:BAAALgADCgEJAQAAAA==.Smawbrawl:BAAALgAECggJCQAAAA==.Smoothroller:BAABLgAECn8sAAMZAAkJbhZCFgBXAgAZAAkJbhZCFgBXAgAQAAIJAAdziwA8AAAAAA==.',
So='Sogen:BAAALgADCgMJAwAAAA==.Soloxtremist:BAAALgADCgEJAQAAAA==.Soulripper:BAAALgAECgEJAQABLgAFFAIJAgAeAAAAAA==.',
St='Staysalty:BAAALgADCgEJAQAAAA==.Stickyricky:BAAALgADCgUJCgAAAA==.Strongmandan:BAAALgAECgEJAQAAAA==.Stubs:BAAALgADCgYJDAAAAA==.',
Su='Sule:BAEBLgAECn88AAIWAAkJRhZdRQAGAgAWAAkJRhZdRQAGAgAAAA==.',
Sw='Sweetpea:BAAALgAFFAEJAQABLgAFFAYJGAARAK8YAA==.',
['Sä']='Sämuel:BAAALgAECgEJAQAAAA==.',
Ta='Tanks:BAAALgAECgIJAgAAAA==.',
Th='Thelorax:BAACLgAFFH8FAAIHAAMJyAYJaQCoAAAHAAMJyAYJaQCoAAAuAAQKfx8AAgcACQlDENlCALQBAAcACQlDENlCALQBAAAA.Theyeti:BAAALgADCgEJAgABLgADCgQJBwAeAAAAAA==.Thhee:BAABLgAECn8zAAInAAkJOhlaDABVAgAnAAkJOhlaDABVAgAAAA==.Thumbelyna:BAABLgAECn8jAAMbAAgJtRsgHwBFAgAbAAgJtRsgHwBFAgAhAAEJMQrzNQAeAAAAAA==.',
To='Towelp:BAAALgAECgYJCAABLgAFFAYJIwAXAIYgAA==.',
Ts='Tsuro:BAAALgAECgcJCwAAAA==.',
Tu='Tukktukk:BAAALgAECgEJAQAAAA==.',
Ty='Tyrini:BAAALgADCgIJAgAAAA==.',
Um='Umie:BAAALgAECgEJAQAAAA==.',
Un='Unholylife:BAABLgAECn8aAAICAAgJSAaZtQAMAQACAAgJSAaZtQAMAQAAAA==.',
Up='Up:BAABLgAECn8VAAIUAAcJVB/nBABjAgAUAAcJVB/nBABjAgAAAA==.',
Va='Valasi:BAAALgAECgEJAwAAAA==.',
Ve='Velocet:BAACLgAFFH8VAAInAAUJMQvKHQAjAQAnAAUJMQvKHQAjAQAuAAQKfzcAAycACQm0GngVAGQCACcACQm0GngVAGQCAAkAAwmICL0WAIsAAAAA.Vetlance:BAAALgAECgQJBQAAAA==.',
Vo='Voroak:BAAALgADCgYJBgAAAA==.',
Wa='Waghdaddy:BAABLgAECn8pAAICAAkJlCKZFAC/AgACAAkJlCKZFAC/AgAAAA==.Waghiechan:BAAALgAECgcJDQAAAA==.',
We='Werewolf:BAAALgAECgUJBQAAAA==.',
Wh='Whatøncewas:BAAALgAFFAEJAQABLgAFFAIJAwAeAAAAAA==.Whitfield:BAAALgADCgUJBQAAAA==.Whordie:BAAALgAECgEJAQAAAA==.',
Wi='Wildlily:BAAALgADCgkJCQABLgAFFAQJBgACAM4OAA==.Wistful:BAAALgAECgQJBwAAAA==.',
Wo='Wobiwabi:BAAALgADCgIJAgAAAA==.',
Wr='Wratheon:BAACLgAFFH8VAAIRAAUJiiIeEACRAQARAAUJiiIeEACRAQAuAAQKfzsAAxEACQm4HogHALUCABEACQm4HogHALUCABAAAgmxC66iACcAAAAA.',
Wu='Wuji:BAABLgAECn8zAAIkAAkJywyYIAC9AQAkAAkJywyYIAC9AQAAAA==.',
['Wê']='Wêrewôlf:BAAALgADCgUJBQAAAA==.',
Xa='Xablau:BAAALgAECgYJBwAAAA==.',
Ye='Yeli:BAAALgAECggJEQAAAA==.',
Za='Zardasa:BAAALgAECgIJAgABLgADCgQJBwAeAAAAAA==.',
Ze='Zenaf:BAAALgAECgUJBwAAAA==.Zeryph:BAAALgADCgYJCwABLgAECgUJBwAeAAAAAA==.',
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
