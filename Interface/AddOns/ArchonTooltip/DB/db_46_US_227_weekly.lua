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

local lookup = {'Warlock-Demonology','Paladin-Retribution','Warlock-Destruction','Warrior-Protection','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','DemonHunter-Devourer','Warrior-Fury','Rogue-Assassination','Paladin-Holy','Paladin-Protection','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Restoration','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Warlock-Affliction','DemonHunter-Vengeance','DemonHunter-Havoc','Mage-Frost','Priest-Shadow','Shaman-Elemental','Rogue-Subtlety','Druid-Restoration','Unknown-Unknown','DeathKnight-Frost','Druid-Balance','Druid-Guardian','Druid-Feral','Mage-Arcane','Evoker-Preservation','Mage-Fire','Priest-Discipline','Hunter-Survival',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=46,date='2026-06-28',data={Ab='Abharn:BAAALgAECgYJDQAAAA==.',
Ag='Agoneer:BAAALgAECgQJBwAAAA==.',
Ak='Akeera:BAABLgAECn8VAAIBAAcJUA6TjQAfAQABAAcJUA6TjQAfAQAAAA==.Akkiya:BAAALgAECgYJDwABLgAFFAYJFgACAGMUAA==.',
Al='Althtar:BAAALgADCgQJBAAAAA==.',
Am='Amalyn:BAAALgAECgYJCAAAAA==.Amarantha:BAABLgAECn8mAAMDAAkJGwnqGwDGAAABAAYJPgmlkQAYAQADAAcJDwfqGwDGAAAAAA==.',
An='Anaesthetize:BAAALgAECgYJCAAAAA==.Aness:BAABLgAECn8hAAIEAAgJagOzLQDOAAAEAAgJagOzLQDOAAAAAA==.Angelinalizy:BAAALgAECgQJCgAAAA==.Animagon:BAAALgAECgUJDwAAAA==.Animaker:BAABLgAECn8wAAMFAAkJDBZKQAACAgAFAAkJDBZKQAACAgAGAAEJ1hVJCgA/AAAAAA==.Anngus:BAAALgAECgQJBQAAAA==.Anvilkrash:BAAALgADCgcJCwAAAA==.',
Ar='Ariese:BAAALgAECgEJAQAAAA==.',
As='Ashido:BAABLgAECn8WAAIHAAYJJhyDHwDIAQAHAAYJJhyDHwDIAQAAAA==.Astreos:BAABLgAFFH8QAAIBAAcJcBX+FADuAAABAAcJcBX+FADuAAABLgAFFAkJHwAIAJ8dAA==.Astrikin:BAAALgAECgYJDwABLgAFFAkJHwAIAJ8dAA==.',
Au='Auraiel:BAAALgADCgcJFAAAAA==.Aurhon:BAAALgAECgYJEAAAAA==.Aurorastar:BAAALgAECgEJAQAAAA==.',
Ba='Bagawgwah:BAAALgAECgEJAwAAAA==.Baluu:BAAALgAECgQJBAAAAA==.Baultier:BAAALgADCgkJDgAAAA==.',
Be='Bel:BAABLgAECn9MAAIEAAkJDiUEAgAvAwAEAAkJDiUEAgAvAwAAAA==.Beraxes:BAABLgAECn8pAAIJAAkJixGkIgDdAQAJAAkJixGkIgDdAQAAAA==.Bethäny:BAAALgAECgQJAQAAAA==.',
Bl='Blasser:BAABLgAECn8fAAIKAAkJ6BrTBAA+AgAKAAkJ6BrTBAA+AgAAAA==.Blizizdumz:BAACLgAFFH8NAAMCAAQJQBExSgAYAQACAAQJQBExSgAYAQALAAEJEQoGSwAyAAAuAAQKfzkABAIACQmtHtseAI0CAAIACQmFHdseAI0CAAwABgnAI3gSAJ8BAAsAAQmYAiigAB8AAAAA.',
Bm='Bmcgilicuddy:BAAALgAECgYJCwAAAA==.',
Br='Bralindra:BAAALgAECgEJAgAAAA==.Breadpitt:BAAALgAECggJEQAAAA==.Brewdhism:BAAALgAECgMJAwAAAA==.Brillane:BAAALgAECgQJBwAAAA==.',
Bu='Bulsy:BAACLgAFFH8dAAMNAAUJUiDECQBoAQANAAUJUiDECQBoAQAOAAEJcgHZPAAsAAAuAAQKfyQAAw0ACQnwHSwUALECAA0ACQnwHSwUALECAA4ABAmQBOtoAJsAAAAA.',
Ca='Calamidade:BAABLgAECn8rAAMPAAkJfQTjGwAhAQAPAAkJfQTjGwAhAQAQAAMJdwHh0gA4AAAAAA==.Calashlar:BAAALgAECgIJBQAAAA==.Camri:BAAALgADCgMJAwAAAA==.Capwnd:BAAALgAECgMJAwAAAA==.',
Ce='Cerryan:BAABLgAECn84AAILAAkJ0hHJIQD1AQALAAkJ0hHJIQD1AQAAAA==.Cexar:BAABLgAECn8aAAIJAAcJjA0IQgA9AQAJAAcJjA0IQgA9AQAAAA==.',
Ch='Chaoticprime:BAAALgAECgEJAQAAAA==.Charivium:BAAALgADCgQJBAAAAA==.Charo:BAABLgAECn8uAAQRAAkJPSGTBgDiAgARAAgJOiSTBgDiAgASAAgJIRbHAgDrAAATAAQJ9BNPCQDlAAAAAA==.Chaòs:BAAALgADCgMJAwAAAA==.Chinup:BAABLgAECn82AAIGAAkJQCFdCQB8AgAGAAkJQCFdCQB8AgAAAA==.',
Cl='Clother:BAACLgAFFH8YAAMJAAUJQSRLBACwAQAJAAUJ7RhLBACwAQAUAAUJQST3AQBkAQAuAAQKfxoAAwkACAkEIfYKAAQDAAkACAkEIfYKAAQDABQABgnmIGEHAEkCAAEuAAUUBwkVAAUA1BsA.',
Co='Cokenopepsi:BAABLgAECn8ZAAIGAAgJiB5LEgDpAQAGAAgJiB5LEgDpAQAAAA==.Cole:BAAALgAFFAMJAwAAAA==.Cormigo:BAABLgAECn8XAAMVAAcJLQywAwD6AAAVAAcJLQywAwD6AAAWAAEJWQSrKgAjAAAAAA==.',
Cr='Crackle:BAAALgADCgcJDAAAAA==.Crazyhorse:BAAALgAECgYJCwAAAA==.Cristos:BAAALgADCgYJCwAAAA==.Crusade:BAAALgADCgYJBgAAAA==.',
Cu='Curses:BAABLgAECn8XAAMBAAkJPBeoAgDAAQABAAkJmhaoAgDAAQAXAAMJwx20FQDYAAAAAA==.',
['Cø']='Cøløssus:BAAALgAECgEJAQAAAA==.',
Da='Daddypie:BAABLgAECn8/AAQYAAkJ0iQfAQAyAwAYAAkJ0iQfAQAyAwAZAAIJDx4wCgBbAAAIAAEJ7AwCDgE8AAAAAA==.Damasscus:BAAALgAECgcJDQAAAA==.Darkdesire:BAAALgADCgUJBQAAAA==.',
De='Deathkanight:BAAALgAECgUJCgAAAA==.Desdakharii:BAAALgAECgEJAQAAAA==.',
Di='Diktug:BAAALgAECgMJAwAAAA==.Disney:BAABLgAECn8WAAIKAAcJshLOCgCDAQAKAAcJshLOCgCDAQAAAA==.',
Dj='Djaztech:BAACLgAFFH8QAAMJAAYJlB3VEACAAQAJAAYJlB3VEACAAQAUAAQJgxIxHAAKAQAuAAQKfyYAAwkACQnFIrsRAGcCAAkACAnxIbsRAGcCABQABwlQGlMSANQBAAAA.',
Do='Donkie:BAABLgAECn8gAAINAAgJUxwzLAAsAgANAAgJUxwzLAAsAgAAAA==.',
Dr='Dracsano:BAAALgAFFAIJAgAAAA==.Dreadhunter:BAAALgAECgQJBAAAAA==.Dreamzz:BAAALgADCgMJAwAAAA==.Drixadin:BAAALgAECgQJBwAAAA==.Drshockêr:BAACLgAFFH8QAAIQAAQJpRnjLAAvAQAQAAQJpRnjLAAvAQAuAAQKf1MAAxAACQlnIjYEAHYDABAACQlnIjYEAHYDAA8ACAmeDFsXAFABAAAA.',
Ds='Dsakony:BAABLgAECn8WAAIaAAkJZhS1nABBAQAaAAkJZhS1nABBAQAAAA==.',
Du='Dunthat:BAAALgAECgUJBgAAAA==.Duskdruid:BAAALgAECgUJBQABLgAFFAYJBwAGAHYiAA==.Duthir:BAACLgAFFH8NAAIFAAMJRxRrnADYAAAFAAMJRxRrnADYAAAuAAQKfywAAgUACQldHc8/ADkCAAUACQldHc8/ADkCAAEuAAUUBgkRABsAQxUA.',
Dy='Dyte:BAAALgAECgEJAQAAAA==.',
Ea='East:BAAALgAECgYJEwAAAA==.',
Ed='Edd:BAAALgAECgEJAQAAAA==.',
Eg='Egrok:BAABLgAECn8fAAIcAAkJaxGEAwA4AQAcAAkJaxGEAwA4AQAAAA==.',
El='Elenor:BAAALgAECgIJAgAAAA==.',
Em='Emaeel:BAABLgAECn8fAAQTAAkJfBKtOQCLAQATAAgJqRCtOQCLAQARAAgJOQ+lLQBVAQASAAQJJgTjXgCUAAAAAA==.Emporia:BAAALgAFFAEJAgAAAA==.',
En='Enhae:BAAALgAECgUJCAAAAA==.Envyqt:BAAALgADCgEJAQAAAA==.',
Er='Erissel:BAABLgAECn8XAAIdAAcJxg0cAgBUAQAdAAcJxg0cAgBUAQAAAA==.',
Es='Esso:BAACLgAFFH8WAAMFAAYJgxUhNACZAQAFAAUJgxUhNACZAQAGAAEJAACxWgAAAAAuAAQKfxcAAgUABwmNFsiEAFoBAAUABwmNFsiEAFoBAAAA.',
Fa='Faelenor:BAAALgAECgYJCAAAAA==.Faelure:BAABLgAECn8cAAICAAgJ/QmnuwAOAQACAAgJ/QmnuwAOAQAAAA==.',
Fe='Feyed:BAAALgAECgEJAgAAAA==.',
Fi='Fiddleoux:BAAALgAECgYJEAAAAA==.Fiending:BAAALgAECgEJAQAAAA==.Finnarius:BAAALgADCgYJBgAAAA==.Firenze:BAAALgAECgYJDgAAAA==.Fizzlewar:BAAALgADCgIJAgABLgAFFAQJDQACAEARAQ==.Fizzpop:BAAALgAECgMJAwAAAA==.',
Fo='Foros:BAABLgAECn80AAILAAkJxCRyBQA8AwALAAkJxCRyBQA8AwAAAA==.',
Fr='Frozone:BAABLgAECn8kAAIaAAgJWhgWVQDdAQAaAAgJWhgWVQDdAQAAAA==.Fryiertuck:BAAALgAECgYJCgAAAA==.',
Ga='Gabil:BAABLgAECn80AAIWAAkJcQn0CgBqAQAWAAkJcQn0CgBqAQAAAA==.Gaunshots:BAAALgAECgQJBwABLgAECgkJFwABADwXAA==.',
Ge='Gendorosan:BAABLgAECn80AAIeAAkJmyH9BQBYAwAeAAkJmyH9BQBYAwAAAA==.',
Gh='Ghoran:BAAALgAECgEJAQAAAA==.',
Gn='Gnork:BAAALgAECgcJEQABLgAFFAMJBgAeALsIAA==.',
Go='Goldwolf:BAAALgAECgYJBwAAAA==.Gotarrnianan:BAAALgAECgEJBAAAAA==.Gothpally:BAAALgAECgQJBAABLgAECgUJBwAfAAAAAA==.',
Gr='Grandmasterx:BAAALgAECgIJAwAAAA==.Graveworm:BAAALgAECgEJAgAAAA==.Gravewurm:BAAALgAECgEJAQAAAA==.Grayfoxx:BAABLgAECn80AAIFAAkJaxqHKwBSAgAFAAkJaxqHKwBSAgAAAA==.Grayhard:BAAALgAECgYJBwAAAA==.Greenhornn:BAAALgAECgkJCQAAAA==.Grìmmgor:BAACLgAFFH8TAAIgAAQJTSKrAAA2AQAgAAQJTSKrAAA2AQAuAAQKfysAAiAACQmDIkwAAIgDACAACQmDIkwAAIgDAAAA.',
Gu='Guerriera:BAAALgAECggJEAAAAA==.Gulkenn:BAAALgADCgcJBwAAAA==.',
['Gô']='Gôôdbye:BAAALgAECggJEwAAAA==.',
Ha='Hado:BAAALgAECgQJBAAAAA==.Halbrand:BAACLgAFFH8KAAIFAAIJTBKn2wCHAAAFAAIJTBKn2wCHAAAuAAQKfxwAAgUACAmDG91QANEBAAUACAmDG91QANEBAAEuAAUUBwkWACEACRYA.Hamburgmeat:BAAALgADCgYJBQAAAA==.',
He='Healovathyme:BAACLgAFFH8IAAIeAAIJqSAFPgC4AAAeAAIJqSAFPgC4AAAuAAQKfxoAAh4ACAlxIugVAIcCAB4ACAlxIugVAIcCAAAA.Hellstomper:BAABLgAECn8UAAMiAAYJ9QunQwCYAAAiAAUJZg2nQwCYAAAjAAUJXAZJOwBrAAAAAA==.Heygrlhey:BAACLgAFFH8FAAINAAMJuhScXADrAAANAAMJuhScXADrAAAuAAQKfz8AAw0ACQmeI8EMAO0CAA0ACQmeI8EMAO0CAA4ABAlHB7RgAL4AAAAA.',
Hi='Hidaoushi:BAAALgADCgkJCQAAAA==.',
Ho='Holdstillbro:BAAALgADCgEJAQABLgAECgkJNgAGAEAhAA==.',
Hu='Hukkaluzul:BAAALgAECgEJAQAAAA==.Humaladin:BAAALgAECgEJAQAAAA==.Humanpaladin:BAABLgAECn8YAAMCAAkJTRMuXQC3AQACAAgJ8xMuXQC3AQAMAAgJcwlqIgABAQABLgAECgkJFwABADwXAA==.Hungryghost:BAAALgAECgkJCwAAAA==.Hunna:BAABLgAECn8dAAINAAgJxxrzPgDmAQANAAgJxxrzPgDmAQAAAA==.Hurtzdonit:BAAALgAFFAIJAgAAAA==.',
Hv='Hvtn:BAAALgAECgYJEAAAAA==.',
Ic='Icyfractals:BAAALgADCgQJBQAAAA==.',
Ik='Ik:BAAALgAECgEJAQABLgAFFAgJMgAHAJAjAA==.',
Il='Ilmerel:BAAALgAFFAkJAQAAAA==.',
In='Inebriated:BAABLgAECn8bAAINAAgJIgtsgAA+AQANAAgJIgtsgAA+AQAAAA==.',
Io='Iondia:BAAALgAECgQJCgAAAA==.',
Is='Iselune:BAAALgAECgIJAgAAAA==.',
It='Itwítçh:BAAALgAECgEJAwAAAA==.',
Iz='Izanami:BAAALgAECgIJAgAAAA==.',
Ja='Jambi:BAAALgAECggJDgAAAA==.Jandrina:BAAALgADCgYJCgAAAA==.Jaraxxus:BAAALgADCgcJBwAAAA==.Jardran:BAAALgAECgEJAgAAAA==.',
Jo='Joanchokkea:BAAALgADCgcJDgAAAA==.Joankorel:BAAALgADCgkJCQAAAA==.Johnconnor:BAAALgAECgEJAQAAAA==.Jolty:BAAALgAECgcJCAABLgAFFAYJGgAFAFEgAA==.',
Ju='Jun:BAAALgAECgEJAQAAAA==.',
['Jê']='Jêanne:BAABLgAECn8VAAIFAAcJug3hDADQAAAFAAcJug3hDADQAAAAAA==.',
Ka='Kael:BAAALgAECgcJEwAAAA==.Kahira:BAEALgADCgQJBAAAAA==.Kalidra:BAAALgAECgQJBQAAAA==.Kaname:BAAALgADCgYJCQABLgAECgUJEAAfAAAAAA==.',
Ke='Kenpashi:BAAALgADCgYJBgAAAA==.Kermitted:BAAALgAECgEJAwABLgAECgYJCQAfAAAAAA==.',
Kh='Khán:BAABLgAECn8wAAICAAkJMRdBAgA0AgACAAkJMRdBAgA0AgAAAA==.',
Ki='Kirlo:BAAALgADCgcJDQAAAA==.Kittytiddies:BAAALgADCgUJBQAAAA==.',
Ko='Kobethama:BAAALgAECgEJBQAAAA==.Kohnan:BAABLgAECn8UAAIIAAgJ2gibkgD7AAAIAAgJ2gibkgD7AAABLgAFFAIJAgAfAAAAAA==.Kotoko:BAABLgAECn8nAAIQAAkJvB4GCgAVAwAQAAkJvB4GCgAVAwAAAA==.',
Kr='Kring:BAAALgAECggJDwAAAA==.',
Ks='Ksauce:BAABLgAECn8oAAIkAAkJ0wOdCgDcAAAkAAkJ0wOdCgDcAAAAAA==.',
Ku='Kungfumama:BAAALgAECgEJAQAAAA==.',
Ky='Kynan:BAACLgAFFH8UAAICAAQJaRN2RQAhAQACAAQJaRN2RQAhAQAuAAQKfywAAwIACAmwHmcCACMCAAIACAmwHmcCACMCAAwAAQmfA7deABMAAAEuAAQKBQkHAB8AAAAA.Kynon:BAABLgAECn8ZAAMRAAYJbRTOMABjAQARAAYJbRTOMABjAQATAAEJLgFmdwAUAAABLgAECgUJBwAfAAAAAA==.Kyran:BAAALgAECgUJBwAAAA==.',
La='Laerai:BAAALgADCgcJDAAAAA==.Lament:BAABLgAECn8UAAIIAAgJQxrzLQAPAgAIAAgJQxrzLQAPAgAAAA==.Lamurun:BAAALgAECgYJCQAAAA==.Lancelöt:BAACLgAFFH8JAAICAAQJ0yC9LgBWAQACAAQJ0yC9LgBWAQAuAAQKf0cAAgIACQloJA0JACEDAAIACQloJA0JACEDAAAA.Lastra:BAAALgAECgkJEgABLgAFFAQJBwAIABYdAA==.Lathina:BAAALgAECgYJCQAAAA==.Lavendere:BAAALgAECgYJEgABLgAFFAYJEQAbAEMVAA==.',
Le='Lectra:BAAALgAECgIJAgAAAA==.Leechang:BAAALgADCgMJAwAAAA==.',
Li='Liiam:BAAALgADCgYJBgAAAA==.Linafox:BAABLgAECn8wAAIaAAkJrgskawClAQAaAAkJrgskawClAQAAAA==.Linnëa:BAABLgAFFH8HAAMGAAMJ6hIOKQCvAAAGAAMJ6hIOKQCvAAAFAAEJUAQTIgE0AAAAAA==.Linta:BAAALgADCgcJCQAAAA==.Lizardwizard:BAABLgAECn8XAAIVAAgJQRGFMQBwAQAVAAgJQRGFMQBwAQAAAA==.',
Ll='Llonia:BAAALgADCgMJAwAAAA==.',
Lo='Lockraum:BAAALgAFFAEJAQAAAA==.Lokix:BAABLgAECn85AAIFAAkJbiLKDQD+AgAFAAkJbiLKDQD+AgAAAA==.',
Lu='Luexis:BAAALgADCgkJFgAAAA==.Luobo:BAAALgADCgQJBQAAAA==.Lustie:BAAALgADCgMJAwAAAA==.',
Ly='Lysistratta:BAABLgAECn85AAIGAAkJdA0fHgBmAQAGAAkJdA0fHgBmAQAAAA==.',
Ma='Magikishi:BAABLgAECn8cAAIaAAgJYR8xOwCKAgAaAAgJYR8xOwCKAgAAAA==.Magimal:BAAALgAECgYJBgABLgAECgkJHwATAHwSAA==.Mahka:BAACLgAFFH8FAAIeAAMJQwkNSwCQAAAeAAMJQwkNSwCQAAAuAAQKf0gABB4ACQkHIHEPANkCAB4ACQkHIHEPANkCACEAAwkfI4E/ABEBACIAAgmtDtNcAFUAAAEuAAMKAQkBAB8AAAAA.Mainframe:BAAALgAECgEJAQAAAA==.Maldar:BAAALgAECgIJAgABLgAECgkJHwATAHwSAA==.Maldrakesus:BAAALgADCgEJAQABLgAECgkJHwATAHwSAA==.Malifecent:BAAALgAECgMJAwAAAA==.Manthalus:BAAALgAECgIJAgAAAA==.Marquista:BAABLgAECn8fAAICAAgJzA6jhwBhAQACAAgJzA6jhwBhAQAAAA==.Masika:BAAALgAECgIJAgAAAA==.',
Mc='Mchammer:BAAALgADCgMJAwAAAA==.',
Me='Meatball:BAAALgAECgMJAwAAAA==.Meganstoon:BAAALgAECgMJBAAAAA==.Meladaris:BAAALgAECgQJEQAAAA==.Mey:BAABLgAECn9ZAAIHAAkJtxsHDACnAgAHAAkJtxsHDACnAgAAAA==.',
Mi='Misfortune:BAAALgADCgUJBQAAAA==.Missperfect:BAAALgAECgcJEQAAAA==.Mitenalla:BAACLgAFFH8WAAICAAYJYxRqJwBsAQACAAYJYxRqJwBsAQAuAAQKfxoAAgIACAm6G9BSANEBAAIACAm6G9BSANEBAAAA.',
Mo='Mokris:BAAALgAECgUJCQAAAA==.Monkrobin:BAAALgAECgEJAQAAAA==.Morninbreath:BAAALgAECgUJBQAAAA==.Mossberger:BAAALgAECgUJBgAAAA==.',
Mu='Muatahawa:BAAALgAECgMJBQAAAA==.Muglackh:BAAALgAECgcJEwAAAA==.',
My='Myoue:BAAALgAECgMJBQAAAA==.Mysticraven:BAABLgAECn86AAIhAAkJpArEAgBXAQAhAAkJpArEAgBXAQAAAA==.Mythbredor:BAAALgAECgYJBgAAAA==.',
Na='Naariah:BAAALgAECgEJAQAAAA==.Nagendra:BAACLgAFFH8RAAIVAAUJjhuSKAAoAQAVAAUJjhuSKAAoAQAuAAQKfx4AAhUACQmYIOgHAPoCABUACQmYIOgHAPoCAAAA.Natharion:BAAALgADCgUJCgAAAA==.',
Ne='Neoptolemos:BAAALgAECgcJEAAAAA==.Nezpak:BAAALgADCgcJEAAAAA==.',
Ni='Nicnevin:BAABLgAECn84AAIWAAkJ4gwfCQCZAQAWAAkJ4gwfCQCZAQAAAA==.Nitrochrist:BAABLgAECn9DAAIBAAkJSRY2PQDnAQABAAkJSRY2PQDnAQAAAA==.Nixxy:BAAALgAECgYJBwABLgAFFAcJGQAlANIQAA==.',
No='Nokansee:BAAALgADCgQJBAAAAA==.Nokimi:BAAALgAECgUJCAAAAA==.Noobru:BAAALgAECgYJDwAAAA==.Nordathair:BAABLgAECn8oAAIVAAkJxRGAJQCzAQAVAAkJxRGAJQCzAQAAAA==.Nori:BAACLgAFFH8zAAQaAAkJ7CIGBwDLAgAaAAgJUiQGBwDLAgAmAAMJsCBnAwDWAAAkAAEJ5CShBABsAAAuAAQKfywAAxoACQm9JpoAAPwDABoACQm9JpoAAPwDACQAAwkSILcPAMcAAAAA.',
Ob='Oblivion:BAAALgADCgQJBAAAAA==.',
On='Onebuttonman:BAAALgAECgEJAQAAAA==.Onlyfoxes:BAAALgAECgIJAgAAAA==.',
Or='Original:BAACLgAFFH8NAAICAAYJuBnWCgA+AQACAAYJuBnWCgA+AQAuAAQKfxoAAgIACAk2ImIcAJoCAAIACAk2ImIcAJoCAAAA.Originals:BAABLgAFFH8IAAMgAAQJFxLRCACbAAAFAAMJ/w8MpADQAAAgAAIJ2w/RCACbAAAAAA==.',
Ot='Otome:BAABLgAECn8ZAAIFAAgJEAukDgC+AAAFAAgJEAukDgC+AAAAAA==.',
Ov='Overpoweredd:BAAALgAECggJCQAAAA==.',
Pa='Painfulpoo:BAAALgAECgIJAgAAAA==.Parsemae:BAACLgAFFH8RAAIaAAYJ5RWVOACIAQAaAAYJ5RWVOACIAQAuAAQKfyMAAxoACAm2HW0vALQCABoACAm2HW0vALQCACYAAQkdD64QADEAAAAA.Pastries:BAACLgAFFH8fAAIIAAkJnx1KAgAyAgAIAAkJnx1KAgAyAgAuAAQKfzcAAwgACQmrIrkCAKUDAAgACQmrIrkCAKUDABkAAgnMFL9PAHgAAAAA.',
Pb='Pbd:BAAALgAECgIJAgAAAA==.',
Pi='Pierce:BAAALgAECgYJBgAAAA==.Pitlin:BAABLgAECn8kAAInAAkJFiHgBQAnAwAnAAkJFiHgBQAnAwAAAA==.',
Pm='Pmsavenger:BAAALgADCgkJEgAAAA==.',
Po='Polynya:BAAALgAECgQJCgAAAA==.Pooshot:BAAALgAECgYJCwAAAA==.',
Pr='Priestalisha:BAACLgAFFH8yAAIHAAgJkCMVAQDJAgAHAAgJkCMVAQDJAgAuAAQKf0oAAgcACQmtJlEAAOsDAAcACQmtJlEAAOsDAAAA.Prognie:BAAALgADCgcJCAAAAA==.',
Ra='Raelana:BAABLgAECn84AAICAAkJIgpcggBqAQACAAkJIgpcggBqAQAAAA==.Ragetatertot:BAAALgAECgYJDgAAAA==.Ragingpoo:BAABLgAECn8ZAAIFAAkJlxQ/RQDzAQAFAAkJlxQ/RQDzAQAAAA==.Rakenroll:BAAALgADCggJCAAAAA==.Rawsteak:BAABLgAECn8iAAIGAAkJgR7DBgCxAgAGAAkJgR7DBgCxAgAAAA==.Razdaz:BAABLgAECn8eAAMnAAcJfh3/FQD0AQAnAAYJxhv/FQD0AQAHAAcJUhk/HgDTAQAAAA==.',
Re='Redcrow:BAABLgAECn8WAAIJAAkJsAboQgA5AQAJAAkJsAboQgA5AQAAAA==.Reheal:BAABLgAECn8eAAIHAAgJjR17DgCAAgAHAAgJjR17DgCAAgAAAA==.Reshocker:BAABLgAECn8tAAIcAAkJghpMGgAPAgAcAAkJghpMGgAPAgAAAA==.Restosexualz:BAAALgAECgMJBAAAAA==.',
Ri='Rixxy:BAACLgAFFH8ZAAMlAAcJ0hB7BQD1AAAlAAcJ0hB7BQD1AAAVAAEJsAGobAAuAAAuAAQKf0AAAyUACQmsI0UCAFEDACUACQmsI0UCAFEDABUABwnxDY4FALcAAAAA.',
Ro='Roastbeefdr:BAACLgAFFH8MAAMGAAMJwCHQBwD2AAAGAAMJwCHQBwD2AAAFAAEJhh0ACAFSAAAuAAQKf1EAAwYACQnxJEQCAC0DAAYACQnxJEQCAC0DAAUABAkjH0SzAA8BAAAA.Roderigo:BAABLgAECn8lAAIeAAgJBRFjPQCdAQAeAAgJBRFjPQCdAQAAAA==.Root:BAAALgAECgYJEQAAAA==.',
Ru='Runian:BAAALgAECgUJCwAAAA==.Rusladh:BAAALgADCgYJBgAAAA==.',
Sa='Sadlypink:BAABLgAECn8XAAIaAAcJLBRKhwDDAQAaAAcJLBRKhwDDAQAAAA==.Saisaith:BAACLgAFFH8RAAMbAAYJQxWkGAAiAQAbAAUJ8RakGAAiAQAHAAEJUgiCMwBJAAAuAAQKfxwAAxsACQlHGbEOAGwCABsACQlHGbEOAGwCAAcAAQlkBXV6AB8AAAAA.Sanarian:BAAALgADCgMJAwAAAA==.Sand:BAACLgAFFH8MAAIFAAUJkhZDNQCVAQAFAAUJkhZDNQCVAQAuAAQKfyQAAgUABwkuFTxoAL0BAAUABwkuFTxoAL0BAAAA.Sandy:BAAALgAECgcJBQAAAA==.Savadar:BAABLgAECn8VAAMYAAkJMxOTDQB5AQAYAAUJmxqTDQB5AQAZAAYJeQbeQgCqAAAAAA==.Saymourcox:BAAALgAECggJDAAAAA==.',
Se='Seadra:BAAALgADCggJDQABLgAECgYJFAAMAM4ZAA==.Sealyboi:BAAALgADCgQJBAAAAA==.Serpeng:BAABLgAECn8bAAMZAAgJEBG1IwBaAQAZAAgJ1g+1IwBaAQAYAAYJ9QrWGgDGAAAAAA==.Setareh:BAABLgAECn8YAAIaAAgJvwaXqgAqAQAaAAgJvwaXqgAqAQAAAA==.Settra:BAAALgADCgcJDAAAAA==.',
Sh='Shakuru:BAABLgAECn8yAAIaAAkJyw55YgC6AQAaAAkJyw55YgC6AQAAAA==.Shanta:BAAALgAECgMJAwAAAA==.Shedoria:BAAALgAECgEJAQAAAA==.Shkar:BAACLgAFFH8NAAIJAAMJ2wpBOQDOAAAJAAMJ2wpBOQDOAAAuAAQKf2AAAgkACQnhGkoSAGECAAkACQnhGkoSAGECAAAA.Shokan:BAAALgAECgYJDAAAAA==.',
Si='Silanah:BAAALgADCgEJAQAAAA==.Silandrya:BAAALgAECgYJCwAAAA==.Sildin:BAAALgAECgUJDAAAAA==.Silverclaws:BAAALgAECgcJBwAAAA==.',
Sj='Sjaridin:BAEALgAECgQJDAABLgAFFAcJJgAiAGkDAA==.',
Sk='Skittle:BAABLgAECn8yAAQiAAgJVAkKMwDdAAAiAAgJVAkKMwDdAAAeAAYJIwM0oQBuAAAjAAEJPQfHZQAYAAAAAA==.Skullhunter:BAABLgAFFH8HAAQOAAYJKR17IQCgAAAOAAQJXiF7IQCgAAAoAAEJ2RXEMQBLAAANAAEJ3Bf8pQBIAAAAAA==.',
Sl='Slenderama:BAAALgADCgYJCQAAAA==.Slenderella:BAAALgADCgUJBQAAAA==.',
Sm='Small:BAAALgADCgEJAQAAAA==.Smawbrawl:BAAALgAECggJCQAAAA==.Smoothroller:BAABLgAECn8sAAMTAAkJbhb2FwBZAgATAAkJbhb2FwBZAgARAAIJAAe9kwA8AAAAAA==.',
So='Sogen:BAAALgADCgMJAwAAAA==.Soloxtremist:BAAALgADCgEJAQAAAA==.Soulreever:BAAALgAECgMJAwAAAA==.Soulripper:BAAALgAECgYJBwABLgAFFAIJAgAfAAAAAA==.Soultank:BAAALgAECgQJBAAAAA==.',
St='Staysalty:BAAALgADCgEJAQAAAA==.Stickyricky:BAAALgADCgUJCgAAAA==.Strongmandan:BAAALgAECgEJAQAAAA==.Stubs:BAAALgADCgYJDAAAAA==.',
Su='Sule:BAEBLgAECn88AAIaAAkJRhbrSAAAAgAaAAkJRhbrSAAAAgAAAA==.',
Sw='Sweetpea:BAAALgAFFAEJAQABLgAFFAYJGAASAK8YAA==.',
['Sä']='Sämuel:BAAALgAECgMJAwAAAA==.',
Ta='Tanks:BAAALgAECgIJAgAAAA==.',
Th='Thelorax:BAACLgAFFH8FAAIIAAMJyAbhcgChAAAIAAMJyAbhcgChAAAuAAQKfx8AAggACQlDEI5FALYBAAgACQlDEI5FALYBAAAA.Theyeti:BAAALgADCgEJAgABLgADCgQJBwAfAAAAAA==.Thhee:BAABLgAECn8zAAIdAAkJOhlLDQBSAgAdAAkJOhlLDQBSAgAAAA==.Thumbelina:BAAALgAECgMJAwABLgAECggJIwAeALUbAA==.Thumbelyna:BAABLgAECn8jAAMeAAgJtRs6IABFAgAeAAgJtRs6IABFAgAiAAEJMQrzNQAeAAAAAA==.',
To='Towelp:BAAALgAFFAIJAgABLgAFFAcJKAAbAHkeAA==.',
Tr='Trigger:BAAALgAECgEJAQAAAA==.',
Ts='Tsuro:BAAALgAECggJDAAAAA==.',
Tu='Tukktukk:BAAALgAECgEJAQAAAA==.',
Ty='Tyrini:BAAALgADCgIJAgAAAA==.',
Um='Umie:BAAALgAECgEJAQAAAA==.',
Un='Unholylife:BAABLgAECn8aAAICAAgJSAYavwAKAQACAAgJSAYavwAKAQAAAA==.',
Up='Up:BAABLgAECn8VAAIYAAcJVB/nBABjAgAYAAcJVB/nBABjAgAAAA==.',
Ur='Ursan:BAAALgAECgYJBwAAAA==.',
Va='Valasi:BAAALgAECgEJAwAAAA==.',
Ve='Velocet:BAACLgAFFH8XAAIdAAYJTQvKEwBuAQAdAAYJTQvKEwBuAQAuAAQKfzcAAx0ACQm0GngVAGQCAB0ACQm0GngVAGQCAAoAAwmICL0WAIsAAAAA.Velryn:BAAALgADCgEJAQAAAA==.Vetlance:BAAALgAECgQJBQAAAA==.',
Vo='Voroak:BAAALgADCgYJBgAAAA==.',
Wa='Waghdaddy:BAABLgAECn8pAAICAAkJlCKlFgC7AgACAAkJlCKlFgC7AgAAAA==.Waghiechan:BAAALgAECgcJDQAAAA==.Walzy:BAAALgAECgIJAgAAAA==.',
We='Wenzday:BAAALgAECgEJAQAAAA==.Werewolf:BAAALgAECgUJBQAAAA==.',
Wh='Whatøncewas:BAAALgAFFAEJAQABLgAFFAIJAwAfAAAAAA==.Whitfield:BAAALgADCgUJBQAAAA==.Whordie:BAAALgAECgEJAQAAAA==.',
Wi='Wildlily:BAAALgADCgkJCQABLgAFFAQJBgACAM4OAA==.Wistful:BAAALgAECgQJBwAAAA==.',
Wo='Wobiwabi:BAAALgADCgIJAgAAAA==.',
Wr='Wratheon:BAACLgAFFH8WAAISAAYJ8RwjDQDGAQASAAYJ8RwjDQDGAQAuAAQKfzsAAxIACQm4HhcIALICABIACQm4HhcIALICABEAAgmxCzKsACcAAAAA.',
Wu='Wuji:BAABLgAECn83AAInAAkJfg7LIgC5AQAnAAkJfg7LIgC5AQAAAA==.',
['Wê']='Wêrewôlf:BAAALgADCgUJBQAAAA==.',
Xa='Xablau:BAAALgAECgYJBwAAAA==.Xanthus:BAAALgAECgIJAgAAAA==.',
Ye='Yeli:BAABLgAECn8UAAIIAAkJDBVpQADHAQAIAAkJDBVpQADHAQAAAA==.Yetisham:BAAALgAECgIJAgAAAA==.',
Ze='Zenaf:BAAALgAECgUJBwAAAA==.Zeryph:BAAALgADCgYJCwABLgAFFAMJBQAUAPMPAA==.',
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
