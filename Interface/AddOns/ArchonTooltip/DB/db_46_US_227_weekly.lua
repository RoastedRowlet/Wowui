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

local lookup = {'Priest-Shadow','Warlock-Demonology','Paladin-Retribution','Warlock-Destruction','Warrior-Protection','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','DemonHunter-Devourer','Warrior-Fury','Rogue-Assassination','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Restoration','Paladin-Holy','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Evoker-Augmentation','Mage-Fire','Warrior-Arms','Paladin-Protection','Evoker-Devastation','Warlock-Affliction','DemonHunter-Vengeance','DemonHunter-Havoc','Unknown-Unknown','Mage-Frost','Shaman-Elemental','Druid-Restoration','Rogue-Subtlety','DeathKnight-Frost','Druid-Balance','Druid-Guardian','Druid-Feral','Mage-Arcane','Evoker-Preservation','Priest-Discipline','Hunter-Survival',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=46,date='2026-08-25',data={Ab='Abharn:BAAALgAECgYJDQAAAA==.',
Ac='Aceieus:BAAALgADCgYJBgAAAA==.',
Ae='Aeitheus:BAAALgADCgMJAwABLgAFFAgJGAABAHQUAA==.',
Ag='Agoneer:BAAALgAECgQJBwAAAA==.',
Ak='Akeera:BAABLgAECn8VAAICAAcJUA6TjQAfAQACAAcJUA6TjQAfAQAAAA==.Akkiya:BAAALgAECgYJDwABLgAFFAgJHQADAHsVAA==.',
Al='Alannah:BAAALgAECgYJBAAAAA==.Althtar:BAAALgADCgQJBAAAAA==.',
Am='Amalyn:BAAALgAECgYJCAAAAA==.Amarantha:BAABLgAECn8rAAMEAAkJqgvqGwDGAAACAAYJYAmlkQAYAQAEAAcJYArqGwDGAAAAAA==.',
An='Anaesthetize:BAAALgAECgYJCAAAAA==.Aness:BAABLgAECn8hAAIFAAgJagOzLQDOAAAFAAgJagOzLQDOAAAAAA==.Angelinalizy:BAAALgAECgQJCgAAAA==.Animagon:BAAALgAECgUJEAAAAA==.Animaker:BAABLgAECn8xAAMGAAkJLBZKQAACAgAGAAkJLBZKQAACAgAHAAEJ1hUJGQA9AAAAAA==.Anngus:BAAALgAECgQJBQAAAA==.Anvilkrash:BAAALgADCgcJCwAAAA==.',
Ar='Ariese:BAAALgAECgEJAQAAAA==.',
As='Ashido:BAABLgAECn8WAAIIAAYJJhyDHwDIAQAIAAYJJhyDHwDIAQAAAA==.Astreos:BAABLgAFFH8ZAAMEAAkJbhT5AAACAgAEAAYJJRj5AAACAgACAAcJsRe1JAAAAQABLgAFFAkJIAAJALIdAA==.Astrikin:BAAALgAECgYJDwABLgAFFAkJIAAJALIdAA==.',
Au='Auraiel:BAAALgADCgcJFAAAAA==.Aurhon:BAAALgAECgYJEAAAAA==.Aurorastar:BAAALgAECgEJAQAAAA==.',
Ba='Bagawgwah:BAAALgAECgEJAwAAAA==.Baluu:BAAALgAECgQJBAAAAA==.Bandurie:BAAALgAFFAEJAQAAAA==.Baultier:BAAALgADCgkJDgAAAA==.',
Be='Bel:BAABLgAECn9MAAIFAAkJDiUEAgAvAwAFAAkJDiUEAgAvAwAAAA==.Beraxes:BAABLgAECn8xAAMFAAkJ5hivAwCRAQAKAAkJixGkIgDdAQAFAAUJZBuvAwCRAQAAAA==.Bethäny:BAAALgAECgQJBQAAAA==.',
Bl='Blasser:BAABLgAECn8fAAILAAkJ6BrTBAA+AgALAAkJ6BrTBAA+AgAAAA==.',
Bm='Bmcgilicuddy:BAAALgAECgYJCwAAAA==.',
Br='Bralindra:BAAALgAECgEJAgAAAA==.Breadpitt:BAAALgAECggJEQAAAA==.Brewdhism:BAAALgAECgMJAwAAAA==.Brillane:BAAALgAECgQJBwAAAA==.',
Bu='Bulsy:BAACLgAFFH8eAAMMAAYJTx26EgCSAQAMAAYJTx26EgCSAQANAAEJcgHZPAAsAAAuAAQKfyQAAwwACQnwHSwUALECAAwACQnwHSwUALECAA0ABAmQBOtoAJsAAAAA.',
Ca='Calamidade:BAABLgAECn8rAAMOAAkJfQTjGwAhAQAOAAkJfQTjGwAhAQAPAAMJdwHh0gA4AAAAAA==.Calashlar:BAAALgAECgIJBQAAAA==.Camri:BAAALgADCgMJAwAAAA==.Capwnd:BAAALgAECgMJAwAAAA==.',
Ce='Cerryan:BAABLgAECn85AAIQAAkJ0hHJIQD1AQAQAAkJ0hHJIQD1AQAAAA==.Cexar:BAABLgAECn8gAAIKAAkJLRMrBwBzAQAKAAkJLRMrBwBzAQAAAA==.',
Ch='Chaoticprime:BAAALgAECgEJAQAAAA==.Charivium:BAAALgADCgQJBAAAAA==.Charo:BAABLgAECn8/AAQRAAkJ0iGTBgDiAgARAAgJoSSTBgDiAgASAAkJFhcaAgDjAQATAAQJ9BOFFQDlAAABLgAFFAQJBgAUACMUAA==.Chaòs:BAAALgADCgMJAwAAAA==.Chinup:BAABLgAECn82AAIHAAkJQCFdCQB8AgAHAAkJQCFdCQB8AgAAAA==.Chrozesh:BAAALgADCgMJAwABLgAECgkJLwAVANgdAA==.',
Cl='Clother:BAACLgAFFH8hAAMKAAcJvx5LBACwAQAWAAcJvx7kBADBAQAKAAUJ7RhLBACwAQAuAAQKfxoAAwoACAkEIfYKAAQDAAoACAkEIfYKAAQDABYABgnmIGEHAEkCAAAA.',
Co='Cokenopepsi:BAABLgAECn8ZAAIHAAgJiB5LEgDpAQAHAAgJiB5LEgDpAQAAAA==.Cole:BAABLgAFFH8LAAMQAAQJOhHuGACTAAAQAAMJahXuGACTAAAXAAQJrAXDCQB/AAAAAA==.Cormbread:BAAALgAECggJCwAAAA==.Cormigo:BAABLgAECn8XAAMUAAcJLQy4CQDUAAAUAAcJLQy4CQDUAAAYAAEJWQSrKgAjAAAAAA==.',
Cr='Crackle:BAAALgADCgcJDAAAAA==.Crazyhorse:BAAALgAECgYJCwAAAA==.Cristos:BAAALgADCgYJCwAAAA==.Crusade:BAAALgADCgYJBgAAAA==.',
Cu='Curses:BAABLgAECn8XAAMCAAkJZxcJBwC1AQACAAkJxBYJBwC1AQAZAAMJwx20FQDYAAABLgAECgkJGAADAE0TAA==.',
['Cø']='Cøløssus:BAAALgAECgEJAQAAAA==.',
Da='Daddypie:BAABLgAECn8/AAQaAAkJ0iQfAQAyAwAaAAkJ0iQfAQAyAwAbAAIJCx6EGABbAAAJAAEJ7AwCDgE8AAAAAA==.Damasscus:BAAALgAECgcJDQAAAA==.Darkdesire:BAAALgADCgUJBQAAAA==.Daze:BAAALgAECgUJCQAAAA==.',
De='Deathkanight:BAAALgAFFAIJAgAAAA==.Desdakharii:BAAALgAECgEJAQAAAA==.',
Di='Diebastahl:BAAALgADCgYJCgAAAA==.Diktug:BAAALgAECgMJAwABLgAECgYJDQAcAAAAAA==.Disney:BAABLgAECn8WAAILAAcJshLOCgCDAQALAAcJshLOCgCDAQAAAA==.',
Dj='Djaztech:BAACLgAFFH8WAAMKAAYJTh++CgBsAQAKAAYJTh++CgBsAQAWAAQJgxIxHAAKAQAuAAQKfyYAAwoACQnFIrsRAGcCAAoACAnxIbsRAGcCABYABwlQGlMSANQBAAAA.',
Do='Donkie:BAABLgAECn8gAAIMAAgJUxwzLAAsAgAMAAgJUxwzLAAsAgAAAA==.',
Dr='Dracsano:BAAALgAFFAIJAwAAAA==.Draha:BAACLgAFFH8GAAIUAAQJIxTLJgCMAAAUAAQJIxTLJgCMAAAuAAQKfyMAAhQACQnwHDMBAJUCABQACQnwHDMBAJUCAAAA.Dreadhunter:BAAALgAECgUJBQAAAA==.Dreamzz:BAAALgADCgMJAwAAAA==.Drixadin:BAAALgAECgQJBwAAAA==.Drshockêr:BAACLgAFFH8QAAIPAAQJpRnjLAAvAQAPAAQJpRnjLAAvAQAuAAQKf1kAAw8ACQlnIjYEAHYDAA8ACQlnIjYEAHYDAA4ACAmeDFsXAFABAAAA.Drugdhealer:BAAALgAECggJDAAAAA==.',
Ds='Dsakony:BAABLgAECn8WAAIdAAkJZhS1nABBAQAdAAkJZhS1nABBAQAAAA==.',
Du='Dunthat:BAAALgAECgUJBwAAAA==.Duthir:BAACLgAFFH8NAAIGAAMJRxRrnADYAAAGAAMJRxRrnADYAAAuAAQKfywAAgYACQldHc8/ADkCAAYACQldHc8/ADkCAAEuAAUUCAkYAAEAdBQA.',
Dy='Dyte:BAAALgAECgEJAQAAAA==.',
Ea='East:BAAALgAECgYJEwAAAA==.',
Ed='Edd:BAAALgAECgEJAQAAAA==.',
Eg='Egrok:BAABLgAECn8fAAIeAAkJbhGbCgAiAQAeAAkJbhGbCgAiAQAAAA==.',
El='Elekat:BAAALgAECgEJAQAAAA==.Elenor:BAAALgAECgIJAgABLgAECggJIwAfALUbAA==.',
Em='Emaeel:BAABLgAECn8fAAQTAAkJfBKtOQCLAQATAAgJqRCtOQCLAQARAAgJOQ+lLQBVAQASAAQJJgTjXgCUAAAAAA==.Emporia:BAAALgAFFAEJAgAAAA==.',
En='Enhae:BAAALgAECgUJCAAAAA==.Envyqt:BAAALgADCgEJAQAAAA==.',
Er='Erissel:BAABLgAECn8iAAIgAAgJgBAlBACEAQAgAAgJgBAlBACEAQAAAA==.',
Es='Esso:BAACLgAFFH8XAAMGAAcJsRQhNACZAQAGAAYJsRQhNACZAQAHAAEJAACxWgAAAAAuAAQKfxcAAgYABwmNFsiEAFoBAAYABwmNFsiEAFoBAAAA.',
Fa='Faelenor:BAAALgAECgYJCAAAAA==.Faelure:BAABLgAECn8dAAIDAAgJ/QmnuwAOAQADAAgJ/QmnuwAOAQAAAA==.',
Fe='Feyed:BAAALgAECgEJAgAAAA==.',
Fi='Fiddleoux:BAAALgAECgYJEAAAAA==.Fiending:BAAALgAECgEJAQAAAA==.Finnarius:BAAALgADCgYJBgAAAA==.Firenze:BAAALgAECgYJDgAAAA==.Fizzlewar:BAAALgADCgIJAgABLgAFFAQJDQADAEARAQ==.Fizzpop:BAAALgAECgMJAwAAAA==.',
Fo='Foros:BAABLgAECn8+AAIQAAkJxCQDAQDyAgAQAAkJxCQDAQDyAgAAAA==.',
Fr='Frozono:BAACLgAFFH8HAAIdAAQJJQtHOwDYAAAdAAQJJQtHOwDYAAAuAAQKfyQAAh0ACAlaGBZVAN0BAB0ACAlaGBZVAN0BAAAA.Fryiertuck:BAAALgAECgYJCgAAAA==.',
Ga='Gabil:BAABLgAECn80AAIYAAkJcQn0CgBqAQAYAAkJcQn0CgBqAQAAAA==.Gaunshots:BAAALgAECgQJBwABLgAECgkJGAADAE0TAA==.',
Ge='Gendorosan:BAABLgAECn80AAIfAAkJmyH9BQBYAwAfAAkJmyH9BQBYAwAAAA==.',
Gh='Ghoran:BAAALgAECgEJAQAAAA==.',
Gn='Gnork:BAAALgAECgcJEQABLgAFFAMJBgAfALsIAA==.',
Go='Goldwolf:BAAALgAECgYJBwAAAA==.Gotarrnianan:BAAALgAECgEJBAAAAA==.Gothpally:BAAALgAECgQJBAABLgAECgUJBwAcAAAAAA==.',
Gr='Grandmasterx:BAAALgAECgIJAwAAAA==.Graveworm:BAAALgAECgEJAgAAAA==.Gravewurm:BAAALgAECgEJAQAAAA==.Grayfoxx:BAABLgAECn80AAIGAAkJaxqHKwBSAgAGAAkJaxqHKwBSAgAAAA==.Grayhard:BAAALgAECgYJBwAAAA==.Greenhornn:BAAALgAECgkJCQAAAA==.Grìmmgor:BAACLgAFFH8TAAIhAAQJTSKrAAA2AQAhAAQJTSKrAAA2AQAuAAQKfysAAiEACQmDIkwAAIgDACEACQmDIkwAAIgDAAAA.',
Gu='Guerriera:BAAALgAECggJEAAAAA==.Gulkenn:BAAALgADCgcJBwAAAA==.',
['Gô']='Gôôdbye:BAABLgAECn8UAAIMAAgJ7wnLlgASAQAMAAgJ7wnLlgASAQAAAA==.',
Ha='Hado:BAAALgAECgQJBwAAAA==.Halbrand:BAACLgAFFH8LAAIGAAIJohW1gwBXAAAGAAIJohW1gwBXAAAuAAQKfxwAAgYACAmDG91QANEBAAYACAmDG91QANEBAAEuAAUUCAkeACIAORUA.Hamburgmeat:BAAALgADCgYJBQAAAA==.Hamuül:BAAALgADCgIJAgAAAA==.',
He='Healovathyme:BAACLgAFFH8IAAIfAAIJqSAFPgC4AAAfAAIJqSAFPgC4AAAuAAQKfxoAAh8ACAlxIugVAIcCAB8ACAlxIugVAIcCAAAA.Hellstomper:BAABLgAECn8iAAQiAAgJEA8iDAD7AAAiAAcJdA0iDAD7AAAjAAUJvA2nQwCYAAAkAAUJXAZJOwBrAAAAAA==.Heygrlhey:BAACLgAFFH8FAAIMAAMJuhScXADrAAAMAAMJuhScXADrAAAuAAQKfz8AAwwACQmeI8EMAO0CAAwACQmeI8EMAO0CAA0ABAlHB7RgAL4AAAAA.',
Hi='Hidaoushi:BAAALgADCgkJCQAAAA==.',
Ho='Holdstillbro:BAAALgADCgEJAQABLgAECgkJNgAHAEAhAA==.',
Hu='Hukkaluzul:BAAALgAECgEJAQAAAA==.Humaladin:BAAALgAECgEJAQAAAA==.Humanpaladin:BAABLgAECn8YAAMDAAkJTRMuXQC3AQADAAgJ8xMuXQC3AQAXAAgJcwlqIgABAQAAAA==.Hungryghost:BAAALgAECgkJCwAAAA==.Hunna:BAABLgAECn8dAAIMAAgJxxrzPgDmAQAMAAgJxxrzPgDmAQAAAA==.Huntdemon:BAAALgAECgUJCQAAAA==.Hurtzdonit:BAAALgAFFAIJAgAAAA==.',
Hv='Hvtn:BAAALgAECgYJEAAAAA==.',
Ic='Icyfractals:BAAALgADCgQJBQAAAA==.',
Ik='Ik:BAAALgAECgEJAQABLgAFFAgJOwAIAK4kAA==.',
Il='Ilmerel:BAAALgAFFAkJAwAAAA==.',
In='Inebriated:BAABLgAECn8bAAIMAAgJIgtsgAA+AQAMAAgJIgtsgAA+AQAAAA==.',
Io='Iondia:BAAALgAECgQJCgAAAA==.',
Is='Iselune:BAAALgAECgIJAgAAAA==.Isitpink:BAABLgAECn8dAAIdAAcJ8RcwEABnAQAdAAcJ8RcwEABnAQAAAA==.',
It='Itwítçh:BAAALgAECgEJAwAAAA==.',
Iz='Izanami:BAAALgAECgIJAgAAAA==.',
Ja='Jambi:BAABLgAECn8ZAAMgAAgJAhNHBAB+AQAgAAcJGRVHBAB+AQALAAQJ3wUPHAB/AAAAAA==.Jandrina:BAAALgADCgYJCgAAAA==.Jaraxxus:BAAALgADCgcJBwAAAA==.Jardran:BAAALgAECgEJAgAAAA==.',
Jo='Joanchokkea:BAAALgADCgcJDgAAAA==.Joankorel:BAAALgADCgkJCQAAAA==.Johnconnor:BAAALgAECgMJBAAAAA==.Jolty:BAAALgAECgcJCAABLgAFFAYJGgAGAFEgAA==.',
Ju='Jun:BAAALgAECgEJAQAAAA==.',
['Jê']='Jêanne:BAABLgAECn8XAAMGAAcJxw3oHADRAAAGAAcJxw3oHADRAAAhAAEJZRWeFAA/AAAAAA==.',
Ka='Kael:BAABLgAECn8vAAIVAAkJ2B05AAC/AgAVAAkJ2B05AAC/AgAAAA==.Kahira:BAEALgADCgQJBAAAAA==.Kalidra:BAAALgAECgQJBQAAAA==.Kaname:BAAALgADCgYJCQABLgAECgUJEAAcAAAAAA==.',
Ke='Kelethen:BAAALgADCgMJAwABLgAECgkJLwAVANgdAA==.Kenpashi:BAAALgADCgYJBgAAAA==.Kermitted:BAAALgAECgEJBAABLgAECgYJDQAcAAAAAA==.',
Kh='Khán:BAABLgAECn8xAAIDAAkJWBf3BgAiAgADAAkJWBf3BgAiAgAAAA==.',
Ki='Kirlo:BAAALgADCgcJDQAAAA==.Kittytiddies:BAAALgADCgUJBQAAAA==.',
Ko='Kobethama:BAAALgAECgEJBQAAAA==.Kohnan:BAABLgAECn8UAAIJAAgJ2gibkgD7AAAJAAgJ2gibkgD7AAABLgAFFAIJAwAcAAAAAA==.Kolgan:BAAALgAECgMJBAAAAA==.Kotoko:BAABLgAECn8oAAIPAAkJvB4GCgAVAwAPAAkJvB4GCgAVAwAAAA==.',
Kr='Kring:BAAALgAFFAIJAgAAAA==.',
Ks='Ksauce:BAABLgAECn8oAAIlAAkJ0wOdCgDcAAAlAAkJ0wOdCgDcAAAAAA==.',
Ku='Kungfumama:BAAALgAECgEJAQAAAA==.',
Ky='Kynan:BAACLgAFFH8YAAIDAAQJeBZwIAAKAQADAAQJeBZwIAAKAQAuAAQKfy0AAwMACQmvHJEHAA4CAAMACAm9HpEHAA4CABcAAgn4CDEZADAAAAEuAAQKBQkHABwAAAAA.Kynin:BAAALgAECgYJCQABLgAECgUJBwAcAAAAAA==.Kynon:BAABLgAECn8aAAMRAAYJbRTOMABjAQARAAYJbRTOMABjAQATAAEJLgFmdwAUAAABLgAECgUJBwAcAAAAAA==.Kyran:BAAALgAECgUJBwAAAA==.',
La='Laerai:BAAALgADCgcJDAAAAA==.Lament:BAABLgAECn8UAAIJAAgJQxrzLQAPAgAJAAgJQxrzLQAPAgABLgAFFAkJEwAJALQlAA==.Lamurun:BAAALgAECgYJCQAAAA==.Lancelöt:BAACLgAFFH8JAAIDAAQJ0yC9LgBWAQADAAQJ0yC9LgBWAQAuAAQKf0cAAgMACQloJA0JACEDAAMACQloJA0JACEDAAAA.Lastra:BAAALgAECgkJEgABLgAFFAgJCwAJAOwaAA==.Lathina:BAAALgAECgYJDQAAAA==.Lavendere:BAAALgAECgYJEgABLgAFFAgJGAABAHQUAA==.',
Le='Lectra:BAAALgAECgIJAgAAAA==.Leechang:BAAALgADCgMJAwAAAA==.',
Li='Liiam:BAAALgADCgYJBgAAAA==.Linafox:BAABLgAECn8+AAIdAAkJkRKDCQDVAQAdAAkJkRKDCQDVAQAAAA==.Linnëa:BAABLgAFFH8HAAMHAAMJ6hIOKQCvAAAHAAMJ6hIOKQCvAAAGAAEJUAQTIgE0AAAAAA==.Linta:BAAALgADCgcJCQABLgAECgUJBwAcAAAAAA==.Lizardwizard:BAABLgAECn8XAAIUAAgJQRGFMQBwAQAUAAgJQRGFMQBwAQAAAA==.',
Ll='Llonia:BAAALgADCgMJAwAAAA==.Lluvia:BAAALgAECgEJAQAAAA==.',
Lo='Lockraum:BAAALgAFFAEJAQAAAA==.Lokix:BAABLgAECn86AAIGAAkJaSLKDQD+AgAGAAkJaSLKDQD+AgAAAA==.Lorenzo:BAAALgAECgMJAwAAAA==.',
Lu='Luexis:BAAALgADCgkJFgAAAA==.Luobo:BAAALgADCgQJBQAAAA==.Lustie:BAAALgADCgMJAwAAAA==.',
Ly='Lysistratta:BAABLgAECn85AAIHAAkJdA0fHgBmAQAHAAkJdA0fHgBmAQAAAA==.',
Ma='Magikishi:BAABLgAECn8cAAIdAAgJYR8xOwCKAgAdAAgJYR8xOwCKAgAAAA==.Magimal:BAAALgAECgYJBgABLgAECgkJHwATAHwSAA==.Mahka:BAACLgAFFH8FAAIfAAMJQwkNSwCQAAAfAAMJQwkNSwCQAAAuAAQKf0gABB8ACQkHIHEPANkCAB8ACQkHIHEPANkCACIAAwkfI4E/ABEBACMAAgmtDtNcAFUAAAEuAAMKAQkBABwAAAAA.Mainframe:BAAALgAECgEJAQAAAA==.Maldar:BAAALgAECgIJAgABLgAECgkJHwATAHwSAA==.Maldrakesus:BAAALgADCgEJAQABLgAECgkJHwATAHwSAA==.Malifecent:BAAALgAECgMJAwAAAA==.Manthalus:BAAALgAECgIJAgAAAA==.Marquista:BAABLgAECn8gAAIDAAgJzA6jhwBhAQADAAgJzA6jhwBhAQAAAA==.Masika:BAAALgAECgIJAgAAAA==.',
Mc='Mchammer:BAAALgADCgMJAwAAAA==.',
Me='Meatball:BAAALgAECgMJAwAAAA==.Meganstoon:BAAALgAECgMJBAAAAA==.Meladaris:BAAALgAFFAEJAQAAAA==.Meloetta:BAAALgADCgUJBQAAAA==.Mey:BAABLgAECn9aAAIIAAkJwBsHDACnAgAIAAkJwBsHDACnAgAAAA==.',
Mi='Misfortune:BAAALgADCgUJBQAAAA==.Missperfect:BAAALgAECgcJEQAAAA==.Mitenalla:BAACLgAFFH8dAAIDAAgJexWSCwC/AQADAAgJexWSCwC/AQAuAAQKfxoAAgMACAm6G9BSANEBAAMACAm6G9BSANEBAAAA.',
Mo='Mokris:BAAALgAECgUJCQAAAA==.Monkrobin:BAAALgAECgEJAQAAAA==.Morninbreath:BAAALgAECgUJBQAAAA==.Mossberger:BAAALgAECgUJBgAAAA==.',
Mu='Muatahawa:BAAALgAECgMJBQAAAA==.Muglackh:BAAALgAECgcJEwAAAA==.',
My='Myoue:BAAALgAECgMJBQAAAA==.Mysticraven:BAABLgAECn87AAIiAAkJ0grpCQAjAQAiAAkJ0grpCQAjAQAAAA==.Mythbredor:BAAALgAECgYJBgAAAA==.',
Na='Naariah:BAAALgAECgEJAQAAAA==.Nagendra:BAACLgAFFH8XAAMUAAcJBBiSKAAoAQAUAAcJBBiSKAAoAQAYAAIJ9Q5jBQCAAAAuAAQKfx4AAhQACQmYIOgHAPoCABQACQmYIOgHAPoCAAAA.Natharion:BAAALgADCgUJCgAAAA==.',
Ne='Necrosisa:BAAALgAECgQJBQAAAA==.Neoptolemos:BAAALgAECgcJEAAAAA==.Nezpak:BAAALgADCgcJEAAAAA==.',
Ni='Nicnevin:BAABLgAECn9WAAMUAAkJbRN3AgDZAQAUAAkJSxN3AgDZAQAYAAkJ4gwfCQCZAQAAAA==.Nikolos:BAAALgAECgYJBwAAAA==.Nitrochrist:BAABLgAECn9DAAICAAkJSRY2PQDnAQACAAkJSRY2PQDnAQAAAA==.Nixxy:BAAALgAECgYJCgABLgAFFAcJIAAmACYTAA==.',
No='Nokansee:BAAALgADCgQJBAAAAA==.Nokimi:BAAALgAFFAIJAgAAAA==.Noobru:BAAALgAECgYJDwAAAA==.Nordathair:BAABLgAECn8pAAMUAAkJqRGAJQCzAQAUAAkJqRGAJQCzAQAmAAEJphG1DgA1AAAAAA==.Nori:BAACLgAFFH9CAAQdAAkJDCUGBwDLAgAdAAgJ+CQGBwDLAgAVAAMJ1yQRAwDOAAAlAAEJ5CShBABsAAAuAAQKfywAAx0ACQm9JpoAAPwDAB0ACQm9JpoAAPwDACUAAwkSILcPAMcAAAAA.',
Ny='Nyxza:BAAALgAECgMJAwAAAA==.',
Ob='Oblivion:BAAALgADCgQJBAAAAA==.',
On='Onebuttonman:BAAALgAECgEJAQAAAA==.Onlyfoxes:BAAALgAECgIJAgAAAA==.',
Or='Original:BAACLgAFFH8PAAIDAAgJMBlnDACzAQADAAgJMBlnDACzAQAuAAQKfxoAAgMACAk2ImIcAJoCAAMACAk2ImIcAJoCAAAA.Originals:BAABLgAFFH8JAAMGAAQJFxIMpADQAAAGAAMJ/w8MpADQAAAhAAIJ2w/EEwCIAAAAAA==.',
Ot='Otome:BAABLgAECn8ZAAIGAAgJEAsLjgBJAQAGAAgJEAsLjgBJAQAAAA==.',
Ov='Overpoweredd:BAAALgAECggJCQAAAA==.',
Pa='Painfulpoo:BAAALgAECgIJAgAAAA==.Parsemae:BAACLgAFFH8XAAMdAAgJ3hWVOACIAQAdAAcJXReVOACIAQAlAAIJnhIABACOAAAuAAQKfyMAAx0ACAm2HW0vALQCAB0ACAm2HW0vALQCABUAAQkdD64QADEAAAAA.Pastries:BAACLgAFFH8gAAIJAAkJsh1KAgAyAgAJAAkJsh1KAgAyAgAuAAQKfzcAAwkACQmrIrkCAKUDAAkACQmrIrkCAKUDABsAAgnMFL9PAHgAAAAA.',
Pb='Pbd:BAAALgAECgIJAgAAAA==.',
Pi='Pierce:BAAALgAECggJCAAAAA==.Pitlin:BAABLgAECn8kAAInAAkJFiHgBQAnAwAnAAkJFiHgBQAnAwAAAA==.',
Pm='Pmsavenger:BAAALgADCgkJEgABLgAECggJGQAgAAITAA==.',
Po='Polynya:BAAALgAECgQJCgAAAA==.Pooshot:BAAALgAECgYJCwAAAA==.',
Pr='Priestalisha:BAACLgAFFH87AAIIAAgJriQVAQDJAgAIAAgJriQVAQDJAgAuAAQKf0oAAggACQmtJlEAAOsDAAgACQmtJlEAAOsDAAAA.Prognie:BAAALgADCgcJCAAAAA==.',
Ra='Raelana:BAABLgAECn85AAIDAAkJIgpcggBqAQADAAkJIgpcggBqAQAAAA==.Ragetatertot:BAAALgAECgYJDgAAAA==.Ragingpoo:BAABLgAECn8ZAAIGAAkJlxQ/RQDzAQAGAAkJlxQ/RQDzAQAAAA==.Rakenroll:BAABLgAFFH8FAAIkAAMJ/h1qBAAJAQAkAAMJ/h1qBAAJAQAAAA==.Rawsteak:BAABLgAECn8iAAIHAAkJgR7DBgCxAgAHAAkJgR7DBgCxAgAAAA==.Razdaz:BAABLgAECn8eAAMnAAcJfh3/FQD0AQAnAAYJxhv/FQD0AQAIAAcJUhk/HgDTAQAAAA==.',
Re='Redcrow:BAABLgAECn8XAAIKAAkJWQfoQgA5AQAKAAkJWQfoQgA5AQAAAA==.Reheal:BAABLgAECn8eAAIIAAgJjR17DgCAAgAIAAgJjR17DgCAAgAAAA==.Reshocker:BAABLgAECn8tAAIeAAkJghpMGgAPAgAeAAkJghpMGgAPAgAAAA==.Restosexualz:BAAALgAECgQJCAAAAA==.',
Ri='Rinella:BAAALgADCgIJAgAAAA==.Rixxy:BAACLgAFFH8gAAMmAAcJJhMhCABbAQAmAAcJJhMhCABbAQAUAAEJsAGobAAuAAAuAAQKf0AAAyYACQmsI0UCAFEDACYACQmsI0UCAFEDABQABwnxDckNAJsAAAAA.',
Ro='Roastbeefdr:BAACLgAFFH8NAAMHAAQJwCGBHAACAQAHAAMJwCGBHAACAQAGAAIJhh0ACAFSAAAuAAQKf1IAAwcACQnxJEQCAC0DAAcACQnxJEQCAC0DAAYABQl9HESzAA8BAAAA.Roderigo:BAABLgAECn8lAAIfAAgJBRFjPQCdAQAfAAgJBRFjPQCdAQAAAA==.Root:BAAALgAECgYJEQAAAA==.',
Ru='Runian:BAAALgAECgUJCwAAAA==.Rusladh:BAAALgADCgcJBwAAAA==.',
Sa='Saisaith:BAACLgAFFH8YAAMBAAgJdBTgBgCqAQABAAcJcBXgBgCqAQAIAAEJUgiCMwBJAAAuAAQKfxwAAwEACQlHGbEOAGwCAAEACQlHGbEOAGwCAAgAAQlkBXV6AB8AAAAA.Sanarian:BAAALgADCgMJAwAAAA==.Sand:BAACLgAFFH8MAAIGAAUJkhZDNQCVAQAGAAUJkhZDNQCVAQAuAAQKfyQAAgYABwkuFTxoAL0BAAYABwkuFTxoAL0BAAAA.Sandy:BAAALgAECgcJBQAAAA==.Sanguinbella:BAAALgAECgUJBQAAAA==.Savadar:BAABLgAECn8WAAMaAAkJ2BOTDQB5AQAaAAUJpBuTDQB5AQAbAAYJeQbeQgCqAAAAAA==.Saymourcox:BAAALgAECggJDAAAAA==.',
Se='Seadra:BAAALgADCggJDQABLgAECgYJFAAXAM4ZAA==.Sealyboi:BAAALgADCgQJBAAAAA==.Seardela:BAAALgADCgUJBQAAAA==.Seleia:BAAALgAECgUJBQABLgAECgkJPgAdAJESAA==.Serpeng:BAABLgAECn8bAAMbAAgJEBG1IwBaAQAbAAgJ1g+1IwBaAQAaAAYJ9QrWGgDGAAAAAA==.Setareh:BAABLgAECn8YAAIdAAgJvwaXqgAqAQAdAAgJvwaXqgAqAQAAAA==.Settra:BAAALgADCgcJDAAAAA==.',
Sh='Shakuru:BAABLgAECn8yAAIdAAkJyw55YgC6AQAdAAkJyw55YgC6AQAAAA==.Shanta:BAAALgAECgMJAwAAAA==.Shedoria:BAAALgAECgEJAQAAAA==.Shkar:BAACLgAFFH8QAAIKAAMJNgtBOQDOAAAKAAMJNgtBOQDOAAAuAAQKf2AAAgoACQnhGkoSAGECAAoACQnhGkoSAGECAAAA.Shokan:BAAALgAECgYJDAAAAA==.',
Si='Silanah:BAAALgADCgEJAQAAAA==.Silandrya:BAABLgAECn8YAAIEAAgJzA9yAwBaAQAEAAgJzA9yAwBaAQAAAA==.Sildin:BAAALgAECgUJDAAAAA==.Silverclaws:BAAALgAECgcJCAAAAA==.',
Sj='Sjaridin:BAEALgAECgQJDAABLgAFFAgJKAAjAAsDAA==.',
Sk='Skittle:BAABLgAECn82AAQjAAgJrAkKMwDdAAAjAAgJrAkKMwDdAAAfAAYJMQM0oQBuAAAkAAEJPQfHZQAYAAAAAA==.Skullhunter:BAABLgAFFH8HAAQNAAYJKR17IQCgAAANAAQJXiF7IQCgAAAoAAEJ2RXEMQBLAAAMAAEJ3Bf8pQBIAAAAAA==.',
Sl='Slenderama:BAAALgADCgYJCQAAAA==.Slenderella:BAAALgADCgUJBQAAAA==.',
Sm='Small:BAAALgADCgEJAQAAAA==.Smawbrawl:BAAALgAECggJCQAAAA==.Smoothroller:BAABLgAECn8sAAMTAAkJbhb2FwBZAgATAAkJbhb2FwBZAgARAAIJAAe9kwA8AAAAAA==.',
So='Sogen:BAAALgADCgMJAwAAAA==.Soloxtremist:BAAALgADCgEJAQAAAA==.Soulintosh:BAACLgAFFH8NAAMDAAQJQBExSgAYAQADAAQJQBExSgAYAQAQAAEJEQoGSwAyAAAuAAQKfzkABAMACQmtHtseAI0CAAMACQmFHdseAI0CABcABgnAI3gSAJ8BABAAAQmYAiigAB8AAAAA.Soulreever:BAAALgAECgYJCQAAAA==.Soulripper:BAAALgAECgYJBwABLgAFFAIJAwAcAAAAAA==.Soultank:BAAALgAECgQJBAAAAA==.',
St='Staysalty:BAAALgADCgEJAQAAAA==.Stickylock:BAAALgAECgEJAQAAAA==.Stickyricky:BAAALgADCgUJCgAAAA==.Strongmandan:BAAALgAECgEJAQAAAA==.Stubs:BAAALgADCgYJDAAAAA==.',
Su='Sule:BAEBLgAECn88AAIdAAkJRhbrSAAAAgAdAAkJRhbrSAAAAgAAAA==.',
Sw='Sweetpea:BAAALgAFFAEJAQABLgAFFAYJGAASAK8YAA==.',
['Sä']='Sämuel:BAAALgAECgMJAwAAAA==.',
['Sï']='Sïn:BAAALgAECgMJAwAAAA==.',
Ta='Tanks:BAAALgAECgIJAgAAAA==.',
Te='Tenleroenish:BAAALgADCgIJAgAAAA==.',
Th='Thelorax:BAACLgAFFH8FAAIJAAMJyAbhcgChAAAJAAMJyAbhcgChAAAuAAQKfx8AAgkACQlDEI5FALYBAAkACQlDEI5FALYBAAAA.Theyeti:BAAALgADCgEJAgABLgADCgQJBwAcAAAAAA==.Thhee:BAABLgAECn8zAAIgAAkJOhlLDQBSAgAgAAkJOhlLDQBSAgAAAA==.Thumbelina:BAAALgAECgMJAwABLgAECggJIwAfALUbAA==.Thumbelyna:BAABLgAECn8jAAMfAAgJtRs6IABFAgAfAAgJtRs6IABFAgAjAAEJMQrzNQAeAAAAAA==.',
To='Towelp:BAAALgAFFAMJBAABLgAFFAcJKAABAKAeAA==.',
Tr='Trigger:BAAALgAECgEJAQAAAA==.',
Ts='Tsuro:BAAALgAECggJDAAAAA==.',
Tu='Tukktukk:BAAALgAECgEJAQAAAA==.',
Tw='Twentÿfourk:BAAALgAECgIJAgABLgAECgYJCQAcAAAAAA==.',
Ty='Tyrini:BAAALgADCgIJAgAAAA==.',
Tz='Tzunami:BAAALgADCgEJAQAAAA==.',
Um='Umie:BAAALgAECgEJAQAAAA==.',
Un='Unholylife:BAABLgAECn8aAAIDAAgJSAYavwAKAQADAAgJSAYavwAKAQAAAA==.',
Up='Up:BAABLgAECn8VAAIaAAcJVB/nBABjAgAaAAcJVB/nBABjAgAAAA==.',
Va='Valasi:BAAALgAECgEJAwAAAA==.Valinta:BAAALgAECgQJBAAAAA==.',
Ve='Velocet:BAACLgAFFH8gAAIgAAgJEQv0CACXAQAgAAgJEQv0CACXAQAuAAQKfzcAAyAACQm0GngVAGQCACAACQm0GngVAGQCAAsAAwmICL0WAIsAAAAA.Velryn:BAAALgADCgEJAQAAAA==.Vetlance:BAAALgAECgQJBQAAAA==.',
Vo='Voroak:BAAALgADCgYJBgAAAA==.',
Wa='Waghdaddy:BAABLgAECn8pAAIDAAkJlCKlFgC7AgADAAkJlCKlFgC7AgAAAA==.Waghiechan:BAAALgAECgcJDQAAAA==.Walzy:BAAALgAECgIJBQAAAA==.',
We='Wenzday:BAAALgAECgEJAQAAAA==.Werewolf:BAAALgAECgUJBQAAAA==.',
Wh='Whatøncewas:BAAALgAFFAEJAQABLgAFFAIJAwAcAAAAAA==.Whitfield:BAAALgADCgUJBQAAAA==.Whordie:BAAALgAECgEJAQAAAA==.',
Wi='Wildlily:BAAALgADCgkJCQABLgAFFAYJCAADAMANAA==.Wistful:BAAALgAECgQJBwAAAA==.',
Wo='Wobiwabi:BAAALgADCgIJAgAAAA==.',
Wr='Wratheon:BAACLgAFFH8cAAISAAgJ3hwjDQDGAQASAAgJ3hwjDQDGAQAuAAQKfzsAAxIACQm4HhcIALICABIACQm4HhcIALICABEAAgmxCzKsACcAAAAA.',
Wu='Wuji:BAABLgAECn83AAInAAkJcg7LIgC5AQAnAAkJcg7LIgC5AQAAAA==.',
['Wê']='Wêrewôlf:BAAALgADCgUJBQAAAA==.',
Xa='Xablau:BAAALgAECgYJBwAAAA==.Xanthus:BAAALgAECgIJAgAAAA==.',
Ye='Yeli:BAABLgAECn8YAAIJAAkJ5BYnCwBKAQAJAAkJ5BYnCwBKAQAAAA==.Yeonwoo:BAAALgADCgIJAgABLgAECgkJLwAVANgdAA==.Yetisham:BAAALgAECgIJAgABLgADCgQJBwAcAAAAAA==.',
Ze='Zenaf:BAAALgAECgUJBwAAAA==.Zeryph:BAAALgADCgYJCwABLgAFFAMJBQAWAPMPAA==.',
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
