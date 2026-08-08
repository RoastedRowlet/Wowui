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

local lookup = {'Priest-Shadow','Warlock-Demonology','Paladin-Retribution','Warlock-Destruction','Warrior-Protection','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','DemonHunter-Devourer','Warrior-Fury','Rogue-Assassination','Paladin-Holy','Paladin-Protection','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Restoration','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Evoker-Augmentation','Mage-Fire','Warrior-Arms','Evoker-Devastation','Warlock-Affliction','DemonHunter-Vengeance','DemonHunter-Havoc','Mage-Frost','Shaman-Elemental','Druid-Restoration','Rogue-Subtlety','Unknown-Unknown','DeathKnight-Frost','Druid-Balance','Druid-Guardian','Druid-Feral','Mage-Arcane','Evoker-Preservation','Priest-Discipline','Hunter-Survival',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=46,date='2026-08-04',data={Ab='Abharn:BAAALgAECgYJDQAAAA==.',
Ac='Aceieus:BAAALgADCgYJBgAAAA==.',
Ae='Aeitheus:BAAALgADCgMJAwABLgAFFAgJFAABAOMTAA==.',
Ag='Agoneer:BAAALgAECgQJBwAAAA==.',
Ak='Akeera:BAABLgAECn8VAAICAAcJUA6TjQAfAQACAAcJUA6TjQAfAQAAAA==.Akkiya:BAAALgAECgYJDwABLgAFFAgJGQADACwTAA==.',
Al='Alannah:BAAALgAECgYJBAAAAA==.Althtar:BAAALgADCgQJBAAAAA==.',
Am='Amalyn:BAAALgAECgYJCAAAAA==.Amarantha:BAABLgAECn8rAAMEAAkJqgvqGwDGAAACAAYJYAmlkQAYAQAEAAcJYArqGwDGAAAAAA==.',
An='Anaesthetize:BAAALgAECgYJCAAAAA==.Aness:BAABLgAECn8hAAIFAAgJagOzLQDOAAAFAAgJagOzLQDOAAAAAA==.Angelinalizy:BAAALgAECgQJCgAAAA==.Animagon:BAAALgAECgUJEAAAAA==.Animaker:BAABLgAECn8xAAMGAAkJLBZKQAACAgAGAAkJLBZKQAACAgAHAAEJ1hWoFgA9AAAAAA==.Anngus:BAAALgAECgQJBQAAAA==.Anvilkrash:BAAALgADCgcJCwAAAA==.',
Ar='Ariese:BAAALgAECgEJAQAAAA==.',
As='Ashido:BAABLgAECn8WAAIIAAYJJhyDHwDIAQAIAAYJJhyDHwDIAQAAAA==.Astreos:BAABLgAFFH8YAAMEAAkJVRSlAQCPAQAEAAUJPhWlAQCPAQACAAcJsRflQwBCAQABLgAFFAkJIAAJALIdAA==.Astrikin:BAAALgAECgYJDwABLgAFFAkJIAAJALIdAA==.',
Au='Auraiel:BAAALgADCgcJFAAAAA==.Aurhon:BAAALgAECgYJEAAAAA==.Aurorastar:BAAALgAECgEJAQAAAA==.',
Ba='Bagawgwah:BAAALgAECgEJAwAAAA==.Baluu:BAAALgAECgQJBAAAAA==.Bandurie:BAAALgAFFAEJAQAAAA==.Baultier:BAAALgADCgkJDgAAAA==.',
Be='Bel:BAABLgAECn9MAAIFAAkJDiUEAgAvAwAFAAkJDiUEAgAvAwAAAA==.Beraxes:BAABLgAECn8vAAMFAAkJgRfWAwB3AQAKAAkJixGkIgDdAQAFAAUJKRnWAwB3AQAAAA==.Bethäny:BAAALgAECgQJBQAAAA==.',
Bl='Blasser:BAABLgAECn8fAAILAAkJ6BrTBAA+AgALAAkJ6BrTBAA+AgAAAA==.Blizizdumz:BAACLgAFFH8NAAMDAAQJQBExSgAYAQADAAQJQBExSgAYAQAMAAEJEQoGSwAyAAAuAAQKfzkABAMACQmtHtseAI0CAAMACQmFHdseAI0CAA0ABgnAI3gSAJ8BAAwAAQmYAiigAB8AAAAA.',
Bm='Bmcgilicuddy:BAAALgAECgYJCwAAAA==.',
Br='Bralindra:BAAALgAECgEJAgAAAA==.Breadpitt:BAAALgAECggJEQAAAA==.Brewdhism:BAAALgAECgMJAwAAAA==.Brillane:BAAALgAECgQJBwAAAA==.',
Bu='Bulsy:BAACLgAFFH8eAAMOAAYJTx3KEQCUAQAOAAYJTx3KEQCUAQAPAAEJcgHZPAAsAAAuAAQKfyQAAw4ACQnwHSwUALECAA4ACQnwHSwUALECAA8ABAmQBOtoAJsAAAAA.',
Ca='Calamidade:BAABLgAECn8rAAMQAAkJfQTjGwAhAQAQAAkJfQTjGwAhAQARAAMJdwHh0gA4AAAAAA==.Calashlar:BAAALgAECgIJBQAAAA==.Camri:BAAALgADCgMJAwAAAA==.Capwnd:BAAALgAECgMJAwAAAA==.',
Ce='Cerryan:BAABLgAECn85AAIMAAkJ0hHJIQD1AQAMAAkJ0hHJIQD1AQAAAA==.Cexar:BAABLgAECn8fAAIKAAkJXRDNCgAUAQAKAAkJXRDNCgAUAQAAAA==.',
Ch='Chaoticprime:BAAALgAECgEJAQAAAA==.Charivium:BAAALgADCgQJBAAAAA==.Charo:BAABLgAECn8/AAQSAAkJ0iGTBgDiAgASAAgJoSSTBgDiAgATAAkJFhcDAgDkAQAUAAQJ9BO9FADmAAABLgAFFAQJBgAVACQUAA==.Chaòs:BAAALgADCgMJAwAAAA==.Chinup:BAABLgAECn82AAIHAAkJQCFdCQB8AgAHAAkJQCFdCQB8AgAAAA==.Chrozesh:BAAALgADCgMJAwABLgAECgcJJQAWAKcaAA==.',
Cl='Clother:BAACLgAFFH8bAAMKAAUJVyRLBACwAQAKAAUJ7RhLBACwAQAXAAUJVyT3AQBkAQAuAAQKfxoAAwoACAkEIfYKAAQDAAoACAkEIfYKAAQDABcABgnmIGEHAEkCAAEuAAUUBwkWAAYAGhwA.',
Co='Cokenopepsi:BAABLgAECn8ZAAIHAAgJiB5LEgDpAQAHAAgJiB5LEgDpAQAAAA==.Cole:BAABLgAFFH8LAAMMAAQJOhHkFwCUAAAMAAMJahXkFwCUAAANAAQJrAVRCQB/AAAAAA==.Cormbread:BAAALgAECggJCwAAAA==.Cormigo:BAABLgAECn8XAAMVAAcJLQwRCQDeAAAVAAcJLQwRCQDeAAAYAAEJWQSrKgAjAAAAAA==.',
Cr='Crackle:BAAALgADCgcJDAAAAA==.Crazyhorse:BAAALgAECgYJCwAAAA==.Cristos:BAAALgADCgYJCwAAAA==.Crusade:BAAALgADCgYJBgAAAA==.',
Cu='Curses:BAABLgAECn8XAAMCAAkJZxeTBgC3AQACAAkJxBaTBgC3AQAZAAMJwx20FQDYAAABLgAECgkJGAADAE0TAA==.',
['Cø']='Cøløssus:BAAALgAECgEJAQAAAA==.',
Da='Daddypie:BAABLgAECn8/AAQaAAkJ0iQfAQAyAwAaAAkJ0iQfAQAyAwAbAAIJCx6+FgBbAAAJAAEJ7AwCDgE8AAAAAA==.Damasscus:BAAALgAECgcJDQAAAA==.Darkdesire:BAAALgADCgUJBQAAAA==.Daze:BAAALgAECgUJCQAAAA==.',
De='Deathkanight:BAAALgAFFAIJAgAAAA==.Desdakharii:BAAALgAECgEJAQAAAA==.',
Di='Diebastahl:BAAALgADCgYJCgAAAA==.Diktug:BAAALgAECgMJAwAAAA==.Disney:BAABLgAECn8WAAILAAcJshLOCgCDAQALAAcJshLOCgCDAQAAAA==.',
Dj='Djaztech:BAACLgAFFH8WAAMKAAYJTh9BCgBuAQAKAAYJTh9BCgBuAQAXAAQJgxIxHAAKAQAuAAQKfyYAAwoACQnFIrsRAGcCAAoACAnxIbsRAGcCABcABwlQGlMSANQBAAAA.',
Do='Donkie:BAABLgAECn8gAAIOAAgJUxwzLAAsAgAOAAgJUxwzLAAsAgAAAA==.',
Dr='Dracsano:BAAALgAFFAIJAwAAAA==.Draha:BAACLgAFFH8GAAIVAAQJJBQOFQAGAQAVAAQJJBQOFQAGAQAuAAQKfyMAAhUACQnwHCIBAJsCABUACQnwHCIBAJsCAAAA.Dreadhunter:BAAALgAECgQJBAAAAA==.Dreamzz:BAAALgADCgMJAwAAAA==.Drixadin:BAAALgAECgQJBwAAAA==.Drshockêr:BAACLgAFFH8QAAIRAAQJpRnjLAAvAQARAAQJpRnjLAAvAQAuAAQKf1kAAxEACQlnIjYEAHYDABEACQlnIjYEAHYDABAACAmeDFsXAFABAAAA.Drugdhealer:BAAALgAECgcJBwAAAA==.',
Ds='Dsakony:BAABLgAECn8WAAIcAAkJZhS1nABBAQAcAAkJZhS1nABBAQAAAA==.',
Du='Dunthat:BAAALgAECgUJBwAAAA==.Duskdruid:BAAALgAFFAEJAQABLgAFFAYJBwAHAHYiAA==.Duthir:BAACLgAFFH8NAAIGAAMJRxRrnADYAAAGAAMJRxRrnADYAAAuAAQKfywAAgYACQldHc8/ADkCAAYACQldHc8/ADkCAAEuAAUUCAkUAAEA4xMA.',
Dy='Dyte:BAAALgAECgEJAQAAAA==.',
Ea='East:BAAALgAECgYJEwAAAA==.',
Ed='Edd:BAAALgAECgEJAQAAAA==.',
Eg='Egrok:BAABLgAECn8fAAIdAAkJbhG8CQAjAQAdAAkJbhG8CQAjAQAAAA==.',
El='Elekat:BAAALgAECgEJAQAAAA==.Elenor:BAAALgAECgIJAgABLgAECggJIwAeALUbAA==.',
Em='Emaeel:BAABLgAECn8fAAQUAAkJfBKtOQCLAQAUAAgJqRCtOQCLAQASAAgJOQ+lLQBVAQATAAQJJgTjXgCUAAAAAA==.Emporia:BAAALgAFFAEJAgAAAA==.',
En='Enhae:BAAALgAECgUJCAAAAA==.Envyqt:BAAALgADCgEJAQAAAA==.',
Er='Erissel:BAABLgAECn8iAAIfAAgJgBDNAwCGAQAfAAgJgBDNAwCGAQAAAA==.',
Es='Esso:BAACLgAFFH8XAAMGAAcJsRQhNACZAQAGAAYJsRQhNACZAQAHAAEJAACxWgAAAAAuAAQKfxcAAgYABwmNFsiEAFoBAAYABwmNFsiEAFoBAAAA.',
Fa='Faelenor:BAAALgAECgYJCAAAAA==.Faelure:BAABLgAECn8dAAIDAAgJ/QmnuwAOAQADAAgJ/QmnuwAOAQAAAA==.',
Fe='Feyed:BAAALgAECgEJAgAAAA==.',
Fi='Fiddleoux:BAAALgAECgYJEAAAAA==.Fiending:BAAALgAECgEJAQAAAA==.Finnarius:BAAALgADCgYJBgAAAA==.Firenze:BAAALgAECgYJDgAAAA==.Fizzlewar:BAAALgADCgIJAgABLgAFFAQJDQADAEARAQ==.Fizzpop:BAAALgAECgMJAwAAAA==.',
Fo='Foros:BAABLgAECn8+AAIMAAkJxCTsAADwAgAMAAkJxCTsAADwAgAAAA==.',
Fr='Frozone:BAACLgAFFH8HAAIcAAQJJQviOADfAAAcAAQJJQviOADfAAAuAAQKfyQAAhwACAlaGBZVAN0BABwACAlaGBZVAN0BAAAA.Fryiertuck:BAAALgAECgYJCgAAAA==.',
Ga='Gabil:BAABLgAECn80AAIYAAkJcQn0CgBqAQAYAAkJcQn0CgBqAQAAAA==.Gaunshots:BAAALgAECgQJBwABLgAECgkJGAADAE0TAA==.',
Ge='Gendorosan:BAABLgAECn80AAIeAAkJmyH9BQBYAwAeAAkJmyH9BQBYAwAAAA==.',
Gh='Ghoran:BAAALgAECgEJAQAAAA==.',
Gn='Gnork:BAAALgAECgcJEQABLgAFFAMJBgAeALsIAA==.',
Go='Goldwolf:BAAALgAECgYJBwAAAA==.Gotarrnianan:BAAALgAECgEJBAAAAA==.Gothpally:BAAALgAECgQJBAABLgAECgUJBwAgAAAAAA==.',
Gr='Grandmasterx:BAAALgAECgIJAwAAAA==.Graveworm:BAAALgAECgEJAgAAAA==.Gravewurm:BAAALgAECgEJAQAAAA==.Grayfoxx:BAABLgAECn80AAIGAAkJaxqHKwBSAgAGAAkJaxqHKwBSAgAAAA==.Grayhard:BAAALgAECgYJBwAAAA==.Greenhornn:BAAALgAECgkJCQAAAA==.Grìmmgor:BAACLgAFFH8TAAIhAAQJTSKrAAA2AQAhAAQJTSKrAAA2AQAuAAQKfysAAiEACQmDIkwAAIgDACEACQmDIkwAAIgDAAAA.',
Gu='Guerriera:BAAALgAECggJEAAAAA==.Gulkenn:BAAALgADCgcJBwAAAA==.',
['Gô']='Gôôdbye:BAABLgAECn8UAAIOAAgJ7wnLlgASAQAOAAgJ7wnLlgASAQAAAA==.',
Ha='Hado:BAAALgAECgQJBwAAAA==.Halbrand:BAACLgAFFH8LAAIGAAIJohUCgQBYAAAGAAIJohUCgQBYAAAuAAQKfxwAAgYACAmDG91QANEBAAYACAmDG91QANEBAAEuAAUUCAkeACIAORUA.Hamburgmeat:BAAALgADCgYJBQAAAA==.Hamuül:BAAALgADCgIJAgAAAA==.',
He='Healovathyme:BAACLgAFFH8IAAIeAAIJqSAFPgC4AAAeAAIJqSAFPgC4AAAuAAQKfxoAAh4ACAlxIugVAIcCAB4ACAlxIugVAIcCAAAA.Hellstomper:BAABLgAECn8dAAQiAAcJ/AxhEACxAAAiAAYJOAphEACxAAAjAAUJvA2nQwCYAAAkAAUJXAZJOwBrAAAAAA==.Heygrlhey:BAACLgAFFH8FAAIOAAMJuhScXADrAAAOAAMJuhScXADrAAAuAAQKfz8AAw4ACQmeI8EMAO0CAA4ACQmeI8EMAO0CAA8ABAlHB7RgAL4AAAAA.',
Hi='Hidaoushi:BAAALgADCgkJCQAAAA==.',
Ho='Holdstillbro:BAAALgADCgEJAQABLgAECgkJNgAHAEAhAA==.',
Hu='Hukkaluzul:BAAALgAECgEJAQAAAA==.Humaladin:BAAALgAECgEJAQAAAA==.Humanpaladin:BAABLgAECn8YAAMDAAkJTRMuXQC3AQADAAgJ8xMuXQC3AQANAAgJcwlqIgABAQAAAA==.Hungryghost:BAAALgAECgkJCwAAAA==.Hunna:BAABLgAECn8dAAIOAAgJxxrzPgDmAQAOAAgJxxrzPgDmAQAAAA==.Huntdemon:BAAALgAECgUJCQAAAA==.Hurtzdonit:BAAALgAFFAIJAgAAAA==.',
Hv='Hvtn:BAAALgAECgYJEAAAAA==.',
Ic='Icyfractals:BAAALgADCgQJBQAAAA==.',
Ik='Ik:BAAALgAECgEJAQABLgAFFAgJOgAIAJwjAA==.',
Il='Ilmerel:BAAALgAFFAkJAwAAAA==.',
In='Inebriated:BAABLgAECn8bAAIOAAgJIgtsgAA+AQAOAAgJIgtsgAA+AQAAAA==.',
Io='Iondia:BAAALgAECgQJCgAAAA==.',
Is='Iselune:BAAALgAECgIJAgAAAA==.',
It='Itwítçh:BAAALgAECgEJAwAAAA==.',
Iz='Izanami:BAAALgAECgIJAgAAAA==.',
Ja='Jambi:BAABLgAECn8YAAMfAAgJAhPqAwCAAQAfAAcJGRXqAwCAAQALAAQJ3wUPHAB/AAAAAA==.Jandrina:BAAALgADCgYJCgAAAA==.Jaraxxus:BAAALgADCgcJBwAAAA==.Jardran:BAAALgAECgEJAgAAAA==.',
Jo='Joanchokkea:BAAALgADCgcJDgAAAA==.Joankorel:BAAALgADCgkJCQAAAA==.Johnconnor:BAAALgAECgMJBAAAAA==.Jolty:BAAALgAECgcJCAABLgAFFAYJGgAGAFEgAA==.',
Ju='Jun:BAAALgAECgEJAQAAAA==.',
['Jê']='Jêanne:BAABLgAECn8XAAMGAAcJxw1VGwDQAAAGAAcJxw1VGwDQAAAhAAEJZRUlEwA/AAAAAA==.',
Ka='Kael:BAABLgAECn8lAAIWAAcJpxq1AACxAQAWAAcJpxq1AACxAQAAAA==.Kahira:BAEALgADCgQJBAAAAA==.Kalidra:BAAALgAECgQJBQAAAA==.Kaname:BAAALgADCgYJCQABLgAECgUJEAAgAAAAAA==.',
Ke='Kelethen:BAAALgADCgMJAwABLgAECgcJJQAWAKcaAA==.Kenpashi:BAAALgADCgYJBgAAAA==.Kermitted:BAAALgAECgEJBAABLgAECgYJDQAgAAAAAA==.',
Kh='Khán:BAABLgAECn8xAAIDAAkJWBdnBgAkAgADAAkJWBdnBgAkAgAAAA==.',
Ki='Kirlo:BAAALgADCgcJDQAAAA==.Kittytiddies:BAAALgADCgUJBQAAAA==.',
Ko='Kobethama:BAAALgAECgEJBQAAAA==.Kohnan:BAABLgAECn8UAAIJAAgJ2gibkgD7AAAJAAgJ2gibkgD7AAABLgAFFAIJAwAgAAAAAA==.Kolgan:BAAALgAECgEJAQAAAA==.Kotoko:BAABLgAECn8oAAIRAAkJvB4GCgAVAwARAAkJvB4GCgAVAwAAAA==.',
Kr='Kring:BAAALgAFFAIJAgAAAA==.',
Ks='Ksauce:BAABLgAECn8oAAIlAAkJ0wOdCgDcAAAlAAkJ0wOdCgDcAAAAAA==.',
Ku='Kungfumama:BAAALgAECgEJAQAAAA==.',
Ky='Kynan:BAACLgAFFH8YAAIDAAQJeBZtHwAPAQADAAQJeBZtHwAPAQAuAAQKfy0AAwMACQmvHPcGABACAAMACAm9HvcGABACAA0AAgn4CHYXADIAAAEuAAQKBQkHACAAAAAA.Kynin:BAAALgAECgUJBQABLgAECgUJBwAgAAAAAA==.Kynon:BAABLgAECn8ZAAMSAAYJbRTOMABjAQASAAYJbRTOMABjAQAUAAEJLgFmdwAUAAABLgAECgUJBwAgAAAAAA==.Kyran:BAAALgAECgUJBwAAAA==.',
La='Laerai:BAAALgADCgcJDAAAAA==.Lament:BAABLgAECn8UAAIJAAgJQxrzLQAPAgAJAAgJQxrzLQAPAgABLgAFFAkJEwAJALQlAA==.Lamurun:BAAALgAECgYJCQAAAA==.Lancelöt:BAACLgAFFH8JAAIDAAQJ0yC9LgBWAQADAAQJ0yC9LgBWAQAuAAQKf0cAAgMACQloJA0JACEDAAMACQloJA0JACEDAAAA.Lastra:BAAALgAECgkJEgABLgAFFAgJCwAJAOwaAA==.Lathina:BAAALgAECgYJDQAAAA==.Lavendere:BAAALgAECgYJEgABLgAFFAgJFAABAOMTAA==.',
Le='Lectra:BAAALgAECgIJAgAAAA==.Leechang:BAAALgADCgMJAwAAAA==.',
Li='Liiam:BAAALgADCgYJBgAAAA==.Linafox:BAABLgAECn8+AAIcAAkJkRLSCADWAQAcAAkJkRLSCADWAQAAAA==.Linnëa:BAABLgAFFH8HAAMHAAMJ6hIOKQCvAAAHAAMJ6hIOKQCvAAAGAAEJUAQTIgE0AAAAAA==.Linta:BAAALgADCgcJCQABLgAECgUJBwAgAAAAAA==.Lizardwizard:BAABLgAECn8XAAIVAAgJQRGFMQBwAQAVAAgJQRGFMQBwAQAAAA==.',
Ll='Llonia:BAAALgADCgMJAwAAAA==.Lluvia:BAAALgAECgEJAQAAAA==.',
Lo='Lockraum:BAAALgAFFAEJAQAAAA==.Lokix:BAABLgAECn86AAIGAAkJaSLKDQD+AgAGAAkJaSLKDQD+AgAAAA==.Lorenzo:BAAALgADCgEJAQAAAA==.',
Lu='Luexis:BAAALgADCgkJFgAAAA==.Luobo:BAAALgADCgQJBQAAAA==.Lustie:BAAALgADCgMJAwAAAA==.',
Ly='Lysistratta:BAABLgAECn85AAIHAAkJdA0fHgBmAQAHAAkJdA0fHgBmAQAAAA==.',
Ma='Magikishi:BAABLgAECn8cAAIcAAgJYR8xOwCKAgAcAAgJYR8xOwCKAgAAAA==.Magimal:BAAALgAECgYJBgABLgAECgkJHwAUAHwSAA==.Mahka:BAACLgAFFH8FAAIeAAMJQwkNSwCQAAAeAAMJQwkNSwCQAAAuAAQKf0gABB4ACQkHIHEPANkCAB4ACQkHIHEPANkCACIAAwkfI4E/ABEBACMAAgmtDtNcAFUAAAEuAAMKAQkBACAAAAAA.Mainframe:BAAALgAECgEJAQAAAA==.Maldar:BAAALgAECgIJAgABLgAECgkJHwAUAHwSAA==.Maldrakesus:BAAALgADCgEJAQABLgAECgkJHwAUAHwSAA==.Malifecent:BAAALgAECgMJAwAAAA==.Manthalus:BAAALgAECgIJAgAAAA==.Marquista:BAABLgAECn8gAAIDAAgJzA6jhwBhAQADAAgJzA6jhwBhAQAAAA==.Masika:BAAALgAECgIJAgAAAA==.',
Mc='Mchammer:BAAALgADCgMJAwAAAA==.',
Me='Meatball:BAAALgAECgMJAwAAAA==.Meganstoon:BAAALgAECgMJBAAAAA==.Meladaris:BAAALgAFFAEJAQAAAA==.Meloetta:BAAALgADCgUJBQAAAA==.Mey:BAABLgAECn9aAAIIAAkJwBsHDACnAgAIAAkJwBsHDACnAgAAAA==.',
Mi='Misfortune:BAAALgADCgUJBQAAAA==.Missperfect:BAAALgAECgcJEQAAAA==.Mitenalla:BAACLgAFFH8ZAAIDAAgJLBNqJwBsAQADAAgJLBNqJwBsAQAuAAQKfxoAAgMACAm6G9BSANEBAAMACAm6G9BSANEBAAAA.',
Mo='Mokris:BAAALgAECgUJCQAAAA==.Monkrobin:BAAALgAECgEJAQAAAA==.Morninbreath:BAAALgAECgUJBQAAAA==.Mossberger:BAAALgAECgUJBgAAAA==.',
Mu='Muatahawa:BAAALgAECgMJBQAAAA==.Muglackh:BAAALgAECgcJEwAAAA==.',
My='Myoue:BAAALgAECgMJBQAAAA==.Mysticraven:BAABLgAECn87AAIiAAkJ0gqbCAAvAQAiAAkJ0gqbCAAvAQAAAA==.Mythbredor:BAAALgAECgYJBgAAAA==.',
Na='Naariah:BAAALgAECgEJAQAAAA==.Nagendra:BAACLgAFFH8TAAIVAAcJBBiSKAAoAQAVAAcJBBiSKAAoAQAuAAQKfx4AAhUACQmYIOgHAPoCABUACQmYIOgHAPoCAAAA.Natharion:BAAALgADCgUJCgAAAA==.',
Ne='Necrosisa:BAAALgAECgEJAQAAAA==.Neoptolemos:BAAALgAECgcJEAAAAA==.Nezpak:BAAALgADCgcJEAAAAA==.',
Ni='Nicnevin:BAABLgAECn9VAAMVAAkJbRNUAgDdAQAVAAkJSxNUAgDdAQAYAAkJ4gwfCQCZAQAAAA==.Nikolos:BAAALgAECgYJBwAAAA==.Nitrochrist:BAABLgAECn9DAAICAAkJSRY2PQDnAQACAAkJSRY2PQDnAQAAAA==.Nixxy:BAAALgAECgYJCgABLgAFFAcJIAAmACYTAA==.',
No='Nokansee:BAAALgADCgQJBAAAAA==.Nokimi:BAAALgAFFAIJAgAAAA==.Noobru:BAAALgAECgYJDwAAAA==.Nordathair:BAABLgAECn8pAAMVAAkJqRGAJQCzAQAVAAkJqRGAJQCzAQAmAAEJphGRDQA1AAAAAA==.Nori:BAACLgAFFH9AAAQcAAkJCyUGBwDLAgAcAAgJ+CQGBwDLAgAWAAMJ1CTxAgDNAAAlAAEJ5CShBABsAAAuAAQKfywAAxwACQm9JpoAAPwDABwACQm9JpoAAPwDACUAAwkSILcPAMcAAAAA.',
Ny='Nyxza:BAAALgAECgMJAwABLgAECgkJJwAOACgcAA==.',
Ob='Oblivion:BAAALgADCgQJBAAAAA==.',
On='Onebuttonman:BAAALgAECgEJAQAAAA==.Onlyfoxes:BAAALgAECgIJAgAAAA==.',
Or='Original:BAACLgAFFH8PAAIDAAgJMBmBCwC9AQADAAgJMBmBCwC9AQAuAAQKfxoAAgMACAk2ImIcAJoCAAMACAk2ImIcAJoCAAAA.Originals:BAABLgAFFH8JAAMGAAQJFxIMpADQAAAGAAMJ/w8MpADQAAAhAAIJ2w8QEwCKAAAAAA==.',
Ot='Otome:BAABLgAECn8ZAAIGAAgJEAsLjgBJAQAGAAgJEAsLjgBJAQAAAA==.',
Ov='Overpoweredd:BAAALgAECggJCQAAAA==.',
Pa='Painfulpoo:BAAALgAECgIJAgAAAA==.Parsemae:BAACLgAFFH8TAAMcAAgJABWVOACIAQAcAAcJWxaVOACIAQAlAAEJ4gzJBgBEAAAuAAQKfyMAAxwACAm2HW0vALQCABwACAm2HW0vALQCABYAAQkdD64QADEAAAAA.Pastries:BAACLgAFFH8gAAIJAAkJsh1KAgAyAgAJAAkJsh1KAgAyAgAuAAQKfzcAAwkACQmrIrkCAKUDAAkACQmrIrkCAKUDABsAAgnMFL9PAHgAAAAA.',
Pb='Pbd:BAAALgAECgIJAgAAAA==.',
Pi='Pierce:BAAALgAECggJCAAAAA==.Pitlin:BAABLgAECn8kAAInAAkJFiHgBQAnAwAnAAkJFiHgBQAnAwAAAA==.',
Pm='Pmsavenger:BAAALgADCgkJEgABLgAECggJGAAfAAITAA==.',
Po='Polynya:BAAALgAECgQJCgAAAA==.Pooshot:BAAALgAECgYJCwAAAA==.',
Pr='Priestalisha:BAACLgAFFH86AAIIAAgJnCMVAQDJAgAIAAgJnCMVAQDJAgAuAAQKf0oAAggACQmtJlEAAOsDAAgACQmtJlEAAOsDAAAA.Prognie:BAAALgADCgcJCAAAAA==.',
Ra='Raelana:BAABLgAECn85AAIDAAkJIgpcggBqAQADAAkJIgpcggBqAQAAAA==.Ragetatertot:BAAALgAECgYJDgAAAA==.Ragingpoo:BAABLgAECn8ZAAIGAAkJlxQ/RQDzAQAGAAkJlxQ/RQDzAQAAAA==.Rakenroll:BAAALgAFFAMJBAAAAA==.Rawsteak:BAABLgAECn8iAAIHAAkJgR7DBgCxAgAHAAkJgR7DBgCxAgAAAA==.Razdaz:BAABLgAECn8eAAMnAAcJfh3/FQD0AQAnAAYJxhv/FQD0AQAIAAcJUhk/HgDTAQAAAA==.',
Re='Redcrow:BAABLgAECn8XAAIKAAkJWQfoQgA5AQAKAAkJWQfoQgA5AQAAAA==.Reheal:BAABLgAECn8eAAIIAAgJjR17DgCAAgAIAAgJjR17DgCAAgAAAA==.Reshocker:BAABLgAECn8tAAIdAAkJghpMGgAPAgAdAAkJghpMGgAPAgAAAA==.Restosexualz:BAAALgAECgMJBAAAAA==.',
Ri='Rinella:BAAALgADCgIJAgAAAA==.Rixxy:BAACLgAFFH8gAAMmAAcJJhPRBwBcAQAmAAcJJhPRBwBcAQAVAAEJsAGobAAuAAAuAAQKf0AAAyYACQmsI0UCAFEDACYACQmsI0UCAFEDABUABwnxDQoNAKAAAAAA.',
Ro='Roastbeefdr:BAACLgAFFH8NAAMHAAQJwCGBHAACAQAHAAMJwCGBHAACAQAGAAIJhh0ACAFSAAAuAAQKf1IAAwcACQnxJEQCAC0DAAcACQnxJEQCAC0DAAYABQl9HESzAA8BAAAA.Roderigo:BAABLgAECn8lAAIeAAgJBRFjPQCdAQAeAAgJBRFjPQCdAQAAAA==.Root:BAAALgAECgYJEQAAAA==.',
Ru='Runian:BAAALgAECgUJCwAAAA==.Rusladh:BAAALgADCgcJBwAAAA==.',
Sa='Sadlypink:BAABLgAECn8dAAIcAAcJ8RcaDwBpAQAcAAcJ8RcaDwBpAQAAAA==.Saisaith:BAACLgAFFH8UAAMBAAgJ4xOkGAAiAQABAAcJxxSkGAAiAQAIAAEJUgiCMwBJAAAuAAQKfxwAAwEACQlHGbEOAGwCAAEACQlHGbEOAGwCAAgAAQlkBXV6AB8AAAAA.Sanarian:BAAALgADCgMJAwAAAA==.Sand:BAACLgAFFH8MAAIGAAUJkhZDNQCVAQAGAAUJkhZDNQCVAQAuAAQKfyQAAgYABwkuFTxoAL0BAAYABwkuFTxoAL0BAAAA.Sandy:BAAALgAECgcJBQAAAA==.Sanguinbella:BAAALgAECgUJBQAAAA==.Savadar:BAABLgAECn8WAAMaAAkJ2BOTDQB5AQAaAAUJpBuTDQB5AQAbAAYJeQbeQgCqAAAAAA==.Saymourcox:BAAALgAECggJDAAAAA==.',
Se='Seadra:BAAALgADCggJDQABLgAECgYJFAANAM4ZAA==.Sealyboi:BAAALgADCgQJBAAAAA==.Seardela:BAAALgADCgUJBQAAAA==.Seleia:BAAALgAECgUJBQABLgAECgkJPgAcAJESAA==.Serpeng:BAABLgAECn8bAAMbAAgJEBG1IwBaAQAbAAgJ1g+1IwBaAQAaAAYJ9QrWGgDGAAAAAA==.Setareh:BAABLgAECn8YAAIcAAgJvwaXqgAqAQAcAAgJvwaXqgAqAQAAAA==.Settra:BAAALgADCgcJDAAAAA==.',
Sh='Shakuru:BAABLgAECn8yAAIcAAkJyw55YgC6AQAcAAkJyw55YgC6AQAAAA==.Shanta:BAAALgAECgMJAwAAAA==.Shedoria:BAAALgAECgEJAQAAAA==.Shkar:BAACLgAFFH8QAAIKAAMJNgtBOQDOAAAKAAMJNgtBOQDOAAAuAAQKf2AAAgoACQnhGkoSAGECAAoACQnhGkoSAGECAAAA.Shokan:BAAALgAECgYJDAAAAA==.Shotrix:BAAALgAECgEJAQABLgAECgUJBwAgAAAAAA==.',
Si='Silanah:BAAALgADCgEJAQAAAA==.Silandrya:BAABLgAECn8YAAIEAAgJzA8lAwBbAQAEAAgJzA8lAwBbAQAAAA==.Sildin:BAAALgAECgUJDAAAAA==.Silverclaws:BAAALgAECgcJBwAAAA==.',
Sj='Sjaridin:BAEALgAECgQJDAABLgAFFAgJKAAjAAsDAA==.',
Sk='Skittle:BAABLgAECn82AAQjAAgJrAkKMwDdAAAjAAgJrAkKMwDdAAAeAAYJMQM0oQBuAAAkAAEJPQfHZQAYAAAAAA==.Skullhunter:BAABLgAFFH8HAAQPAAYJKR17IQCgAAAPAAQJXiF7IQCgAAAoAAEJ2RXEMQBLAAAOAAEJ3Bf8pQBIAAAAAA==.',
Sl='Slenderama:BAAALgADCgYJCQAAAA==.Slenderella:BAAALgADCgUJBQAAAA==.',
Sm='Small:BAAALgADCgEJAQAAAA==.Smawbrawl:BAAALgAECggJCQAAAA==.Smoothroller:BAABLgAECn8sAAMUAAkJbhb2FwBZAgAUAAkJbhb2FwBZAgASAAIJAAe9kwA8AAAAAA==.',
So='Sogen:BAAALgADCgMJAwAAAA==.Soloxtremist:BAAALgADCgEJAQAAAA==.Soulreever:BAAALgAECgYJCQAAAA==.Soulripper:BAAALgAECgYJBwABLgAFFAIJAwAgAAAAAA==.Soultank:BAAALgAECgQJBAAAAA==.',
St='Staysalty:BAAALgADCgEJAQAAAA==.Stickylock:BAAALgAECgEJAQAAAA==.Stickyricky:BAAALgADCgUJCgAAAA==.Strongmandan:BAAALgAECgEJAQAAAA==.Stubs:BAAALgADCgYJDAAAAA==.',
Su='Sule:BAEBLgAECn88AAIcAAkJRhbrSAAAAgAcAAkJRhbrSAAAAgAAAA==.',
Sw='Sweetpea:BAAALgAFFAEJAQABLgAFFAYJGAATAK8YAA==.',
['Sä']='Sämuel:BAAALgAECgMJAwAAAA==.',
['Sï']='Sïn:BAAALgADCgEJAQAAAA==.',
Ta='Tanks:BAAALgAECgIJAgAAAA==.',
Te='Tenleroenish:BAAALgADCgIJAgAAAA==.',
Th='Thelorax:BAACLgAFFH8FAAIJAAMJyAbhcgChAAAJAAMJyAbhcgChAAAuAAQKfx8AAgkACQlDEI5FALYBAAkACQlDEI5FALYBAAAA.Theyeti:BAAALgADCgEJAgABLgADCgQJBwAgAAAAAA==.Thhee:BAABLgAECn8zAAIfAAkJOhlLDQBSAgAfAAkJOhlLDQBSAgAAAA==.Thumbelina:BAAALgAECgMJAwABLgAECggJIwAeALUbAA==.Thumbelyna:BAABLgAECn8jAAMeAAgJtRs6IABFAgAeAAgJtRs6IABFAgAjAAEJMQrzNQAeAAAAAA==.',
To='Towelp:BAAALgAFFAMJBAABLgAFFAcJKAABAKAeAA==.',
Tr='Trigger:BAAALgAECgEJAQAAAA==.',
Ts='Tsuro:BAAALgAECggJDAAAAA==.',
Tu='Tukktukk:BAAALgAECgEJAQAAAA==.',
Tw='Twentÿfourk:BAAALgAECgIJAgABLgAECgYJCQAgAAAAAA==.',
Ty='Tyrini:BAAALgADCgIJAgAAAA==.',
Um='Umie:BAAALgAECgEJAQAAAA==.',
Un='Unholylife:BAABLgAECn8aAAIDAAgJSAYavwAKAQADAAgJSAYavwAKAQAAAA==.',
Up='Up:BAABLgAECn8VAAIaAAcJVB/nBABjAgAaAAcJVB/nBABjAgAAAA==.',
Va='Valasi:BAAALgAECgEJAwAAAA==.Valinta:BAAALgAECgQJBAAAAA==.',
Ve='Velocet:BAACLgAFFH8cAAIfAAgJEQvhCgBaAQAfAAgJEQvhCgBaAQAuAAQKfzcAAx8ACQm0GngVAGQCAB8ACQm0GngVAGQCAAsAAwmICL0WAIsAAAAA.Velryn:BAAALgADCgEJAQAAAA==.Vetlance:BAAALgAECgQJBQAAAA==.',
Vo='Voroak:BAAALgADCgYJBgAAAA==.',
Wa='Waghdaddy:BAABLgAECn8pAAIDAAkJlCKlFgC7AgADAAkJlCKlFgC7AgAAAA==.Waghiechan:BAAALgAECgcJDQAAAA==.Walzy:BAAALgAECgIJBQAAAA==.',
We='Wenzday:BAAALgAECgEJAQAAAA==.Werewolf:BAAALgAECgUJBQAAAA==.',
Wh='Whatøncewas:BAAALgAFFAEJAQABLgAFFAIJAwAgAAAAAA==.Whitfield:BAAALgADCgUJBQAAAA==.Whordie:BAAALgAECgEJAQAAAA==.',
Wi='Wildlily:BAAALgADCgkJCQABLgAFFAQJBgADAM4OAA==.Wistful:BAAALgAECgQJBwAAAA==.',
Wo='Wobiwabi:BAAALgADCgIJAgAAAA==.',
Wr='Wratheon:BAACLgAFFH8YAAITAAgJ3hwjDQDGAQATAAgJ3hwjDQDGAQAuAAQKfzsAAxMACQm4HhcIALICABMACQm4HhcIALICABIAAgmxCzKsACcAAAAA.',
Wu='Wuji:BAABLgAECn83AAInAAkJcg7LIgC5AQAnAAkJcg7LIgC5AQAAAA==.',
['Wê']='Wêrewôlf:BAAALgADCgUJBQAAAA==.',
Xa='Xablau:BAAALgAECgYJBwAAAA==.Xanthus:BAAALgAECgIJAgAAAA==.',
Ye='Yeli:BAABLgAECn8YAAIJAAkJ5BZfCgBOAQAJAAkJ5BZfCgBOAQAAAA==.Yetisham:BAAALgAECgIJAgABLgADCgQJBwAgAAAAAA==.',
Ze='Zenaf:BAAALgAECgUJBwAAAA==.Zeryph:BAAALgADCgYJCwABLgAFFAMJBQAXAPMPAA==.',
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
