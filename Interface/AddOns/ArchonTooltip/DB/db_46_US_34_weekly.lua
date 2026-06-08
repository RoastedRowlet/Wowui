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

local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Hunter-Marksmanship','DemonHunter-Havoc','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Unknown-Unknown','Warrior-Fury','DeathKnight-Blood','Warlock-Destruction','Mage-Frost','Shaman-Enhancement','Priest-Holy','Monk-Windwalker','Monk-Brewmaster','Druid-Guardian','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Rogue-Outlaw','DeathKnight-Unholy','Paladin-Holy','Mage-Arcane','Priest-Discipline','DeathKnight-Frost','Druid-Feral','Hunter-Survival','DemonHunter-Devourer','Druid-Restoration','DemonHunter-Vengeance','Warrior-Protection','Warrior-Arms','Evoker-Preservation','Evoker-Augmentation','Paladin-Protection',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=46,date='2026-06-06',data={Ad='Adamonious:BAAALgAECgYJCwABLgAECgkJFgABAA8WAA==.Adaware:BAAALgAECgUJBgAAAA==.Addieeboy:BAAALgADCgEJAQAAAA==.Adellea:BAAALgAECgYJBwAAAA==.',
Ai='Aisha:BAAALgAECgEJAgAAAA==.',
Al='Alaponia:BAAALgAECgEJAQAAAA==.Alba:BAABLgAECn8sAAICAAgJkx34MAAyAgACAAgJkx34MAAyAgABLgAFFAQJEQABACEZAA==.Aletta:BAAALgAECgYJCAAAAA==.Allast:BAAALgADCgYJDQAAAA==.',
An='Andezard:BAABLgAECn81AAMBAAkJNxf9KAAvAgABAAkJNxf9KAAvAgADAAIJTAl8MABPAAAAAA==.Angelys:BAABLgAECn8YAAIEAAcJSwebMwDdAAAEAAcJSwebMwDdAAAAAA==.',
Ap='Aphrobitey:BAAALgAECgIJAgAAAA==.',
Aq='Aquâ:BAAALgADCgkJDwABLgAECgkJMQAFAOIYAA==.',
Ar='Arathas:BAAALgADCgcJDAAAAA==.Arianes:BAAALgAECgcJDgAAAA==.Arrowin:BAAALgADCgYJBgAAAA==.Arturias:BAABLgAECn8cAAICAAgJ7hK8ZACbAQACAAgJ7hK8ZACbAQAAAA==.',
At='Athenaowl:BAAALgAECggJDwAAAA==.',
Au='Autofocus:BAABLgAECn8eAAIBAAgJPBqkOwDlAQABAAgJPBqkOwDlAQAAAA==.',
Aw='Aweyna:BAAALgAECgkJEgAAAA==.Awisha:BAAALgADCgUJBQAAAA==.',
Ay='Ayanoriko:BAACLgAFFH8OAAIGAAUJjBO/BAA3AQAGAAUJjBO/BAA3AQAuAAQKfysAAgYACAmMH/wEACgCAAYACAmMH/wEACgCAAAA.Ayasumi:BAAALgAECgIJAgAAAA==.',
Ba='Babaganoosh:BAAALgAECgUJCwAAAA==.Baoyue:BAAALgAECggJCwABLgAFFAYJFAAHAPEaAA==.Barracuda:BAAALgAECgYJBgAAAA==.',
Be='Beans:BAABLgAFFH8KAAMIAAUJOxd3QwAzAQAIAAUJyBV3QwAzAQAJAAEJ4grqIgBKAAABLgAFFAYJCwAKACggAA==.Benmonk:BAAALgAECgMJAwAAAA==.',
Bi='Bifur:BAAALgADCgkJDwAAAA==.Bigbuttflori:BAAALgAECgIJAgABLgAECgMJAwALAAAAAA==.Bigstones:BAACLgAFFH8IAAIMAAMJRQRHOQCrAAAMAAMJRQRHOQCrAAAuAAQKfyMAAgwACAnsDjE2AGcBAAwACAnsDjE2AGcBAAAA.',
Bl='Blacksavior:BAAALgAECgQJBAAAAA==.Blindbone:BAAALgAECgcJCQABLgAECggJEwALAAAAAA==.Bluehydra:BAAALgADCgcJCAAAAA==.',
Bo='Bobbydigital:BAABLgAECn85AAINAAkJvhtmCQB1AgANAAkJvhtmCQB1AgAAAA==.Bohd:BAAALgADCgIJAgAAAA==.Bolas:BAAALgAECgEJAQAAAA==.Boneski:BAAALgAECgUJEAAAAA==.Booger:BAAALgAECgQJBAAAAA==.',
Br='Bracynn:BAABLgAECn8gAAINAAcJ5wdUMwDBAAANAAcJ5wdUMwDBAAAAAA==.Brixx:BAAALgAECgMJAwAAAA==.Brudiclad:BAABLgAECn8sAAQJAAkJNBSGCQC5AQAJAAkJphKGCQC5AQAIAAYJaQspoAD6AAAOAAIJzxH2UQB4AAAAAA==.',
Bu='Budfight:BAAALgAECgEJAQAAAA==.Burnt:BAAALgAECgQJBAAAAA==.Butterfinger:BAAALgADCgQJBwAAAA==.Buxxor:BAAALgAECgcJBwAAAA==.',
Ca='Caimark:BAABLgAECn8uAAIPAAgJzgNRvwAFAQAPAAgJzgNRvwAFAQAAAA==.Calahan:BAACLgAFFH8HAAICAAMJgBlbXgDdAAACAAMJgBlbXgDdAAAuAAQKfx4AAgIACAmxGmw0AFACAAIACAmxGmw0AFACAAAA.',
Ch='Chakuneeai:BAAALgADCgYJBgAAAA==.Chancleta:BAAALgAECgYJCQAAAA==.Cherub:BAAALgADCgIJAgAAAA==.Chikostix:BAABLgAECn8mAAIQAAcJ6gibGgAcAQAQAAcJ6gibGgAcAQAAAA==.Christae:BAABLgAECn8nAAIRAAkJNRmqDwBgAgARAAkJNRmqDwBgAgAAAA==.',
Cl='Clementînê:BAAALgAECgIJAgAAAA==.Clemêntine:BAAALgAECgYJDAAAAA==.Clydè:BAABLgAECn9SAAMSAAkJ6RaHFABJAgASAAgJbheHFABJAgATAAkJrhLkGgDGAQAAAA==.Cláncey:BAAALgAFFAEJAQAAAA==.',
Co='Coachhazzard:BAAALgAECgQJCwAAAA==.Cocytus:BAAALgADCgIJAgABLgAFFAIJBwAIADkaAA==.Colinferal:BAAALgAFFAEJAwAAAA==.Combatant:BAAALgADCgYJDAAAAA==.Compromise:BAAALgAECgYJCAAAAA==.Compromised:BAABLgAECn8vAAIEAAkJ3hv4CQB6AgAEAAkJ3hv4CQB6AgAAAA==.Connalious:BAAALgAECgEJAQAAAA==.Conquests:BAAALgAECgIJAgAAAA==.Corelack:BAACLgAFFH8NAAIUAAQJgxPIDwDyAAAUAAQJgxPIDwDyAAAuAAQKfxcAAxQACQm9Db4iACYBABQACQmZDb4iACYBABUABQmpBbJdAJAAAAAA.',
Cr='Crwth:BAAALgAECgUJBQAAAA==.',
Ct='Ctrlaltmagic:BAAALgAECgEJAgAAAA==.',
Cu='Cupis:BAAALgAECgQJBAAAAA==.Curendae:BAABLgAECn8vAAIBAAkJwRcYKQAvAgABAAkJwRcYKQAvAgAAAA==.',
Da='Dabaldzombie:BAACLgAFFH8TAAIPAAUJoxp9WgAqAQAPAAUJoxp9WgAqAQAuAAQKfxgAAg8ACQktGDxMAFICAA8ACQktGDxMAFICAAEuAAUUBgkNABYArRcA.Daddyshocker:BAAALgAECgcJEgAAAA==.Danamy:BAAALgADCggJDQAAAA==.Daxzazi:BAABLgAECn8cAAMSAAcJ9gMXUwCxAAASAAcJ9gMXUwCxAAAFAAUJrAQFhQByAAAAAA==.',
De='Deadlee:BAAALgADCgEJAQAAAA==.Deadmanwlkin:BAAALgADCgIJAgAAAA==.Defias:BAAALgADCggJCAAAAA==.Delicious:BAEBLgAFFH8IAAINAAUJAAsOIADYAAANAAUJAAsOIADYAAABLgAFFAcJEwAXABEVAA==.Despair:BAAALgADCggJDgABLgAFFAQJEQABACEZAA==.',
Di='Dice:BAACLgAFFH8RAAIYAAUJAB5xAwBhAQAYAAUJAB5xAwBhAQAuAAQKfzAAAxgACQllItQAABMDABgACQllItQAABMDAAcAAQmeFEVTAEUAAAAA.Disturbd:BAACLgAFFH8OAAMZAAUJ5Ap9dQAJAQAZAAQJ5Ap9dQAJAQANAAEJAAAUVwAAAAAuAAQKfxgAAxkACQn9DAtZALMBABkACQn9DAtZALMBAA0ABAmJAMY9AFsAAAAA.Disturbian:BAAALgAFFAIJAwABLgAFFAUJDgAZAOQKAA==.Dixierecht:BAABLgAECn8gAAIaAAgJbhubFgBKAgAaAAgJbhubFgBKAgAAAA==.',
Do='Docvader:BAAALgAECgEJAgAAAA==.Dodrop:BAAALgADCgYJBwAAAA==.',
Dr='Drunkenhealz:BAAALgAECgUJEAAAAA==.Drvargas:BAAALgAECgQJCgAAAA==.',
['Då']='Dårth:BAAALgAECgEJAQAAAA==.',
['Dè']='Dèrty:BAAALgAECgIJAgAAAA==.',
El='Elenestern:BAEBLgAECn8wAAIPAAkJWhLgRAAHAgAPAAkJWhLgRAAHAgAAAA==.Elmo:BAABLgAECn8oAAMPAAkJHhaZOAAwAgAPAAkJ0BWZOAAwAgAbAAEJwxUtEwA/AAAAAA==.',
Em='Emryssa:BAAALgAECgMJDAAAAA==.',
Er='Erosis:BAACLgAFFH8OAAIPAAUJ/xv8PwBfAQAPAAUJ/xv8PwBfAQAuAAQKfyQAAg8ACAlsIwIvALYCAA8ACAlsIwIvALYCAAAA.',
Es='Esia:BAAALgADCgkJCQAAAA==.',
Ev='Evarg:BAAALgADCgcJDQAAAA==.',
Ez='Ezaratren:BAAALgAECgUJCgABLgAFFAQJDQAUAIMTAA==.',
Fa='Fakêr:BAAALgADCgEJAQAAAA==.',
Fe='Fear:BAACLgAFFH8GAAIIAAMJMxu+HQANAQAIAAMJMxu+HQANAQAuAAQKfygAAwgACAmDIOgrAF8CAAgACAmDIOgrAF8CAA4ABQkbFk4bAHIBAAAA.Felcatalyist:BAABLgAECn8gAAMZAAkJABgcYwDKAQAZAAkJtBUcYwDKAQANAAgJXA0eJgAXAQAAAA==.Felisaty:BAAALgAECgEJAQAAAA==.Fellisaty:BAABLgAECn8WAAIaAAgJfQ/1LwCPAQAaAAgJfQ/1LwCPAQAAAA==.Felysria:BAAALgAECgQJAgAAAA==.',
Fi='Finvindru:BAAALgAFFAIJAgABLgAFFAQJEwANAGggAA==.Fistitresk:BAAALgADCgQJBAABLgAECgcJFAAcAIYeAA==.Fistofwayne:BAABLgAECn8cAAITAAgJMBCkJgBxAQATAAgJMBCkJgBxAQABLgAFFAYJGAAdAFQaAA==.',
Fr='Frizzalot:BAAALgAECgEJAwAAAA==.Frizzer:BAAALgAECgMJAwAAAA==.',
Ga='Gakopozy:BAAALgAECgYJDwAAAA==.Gambrinos:BAAALgADCgMJAwAAAA==.Gander:BAAALgADCgEJAQABLgAECgEJAQALAAAAAA==.Gandermon:BAAALgAECgEJAQAAAA==.',
Ge='Geg:BAABLgAFFH8FAAIZAAMJvBEhJwD7AAAZAAMJvBEhJwD7AAAAAA==.',
Gl='Glorrex:BAAALgADCgYJBgAAAA==.',
Go='Gongsho:BAAALgAECgQJBgAAAA==.',
Gr='Grapez:BAAALgAFFAIJAgABLgAFFAYJHgAdAKceAA==.Grïmyst:BAAALgAECgEJAQABLgAFFAQJDQAUAIMTAA==.',
Gu='Guldán:BAAALgAECgYJEQAAAA==.',
Gw='Gwydre:BAACLgAFFH8TAAINAAQJaCDFEABaAQANAAQJaCDFEABaAQAuAAQKfxUAAg0ACAnqHvYNAC4CAA0ACAnqHvYNAC4CAAAA.',
Ha='Havran:BAAALgAECgQJBAABLgAECgkJQwAUABYXAA==.Havrin:BAABLgAECn9DAAMUAAkJFhddDwDeAQAUAAkJFhddDwDeAQAeAAEJQhLgMQA7AAAAAA==.',
He='Headshots:BAACLgAFFH8RAAIBAAQJIRmpMwA7AQABAAQJIRmpMwA7AQAuAAQKfy4AAgEACQmVH10UAJMCAAEACQmVH10UAJMCAAAA.Heartsong:BAAALgAECgEJAQAAAA==.Heavylode:BAAALgAECgEJAQAAAA==.Hexatar:BAAALgAECgQJBAAAAA==.',
Hk='Hkia:BAAALgAFFAMJAwAAAA==.',
Ho='Hoardkiller:BAAALgAECgQJAwABLgAFFAUJEwAfANQNAA==.Holmie:BAAALgADCgkJCgAAAA==.Honk:BAAALgAFFAIJAwAAAA==.Hoofsoflove:BAAALgADCgQJBAAAAA==.Hoogaplop:BAACLgAFFH8ZAAMZAAUJkyZjLACXAQAZAAUJkyZjLACXAQANAAUJqB+SEABcAQAuAAQKfzsAAxkACQkcJAMUAAMDABkACQlWIQMUAAMDAA0ACAmPIhIHAKQCAAEuAAUUBgkLAAoAKCAA.',
Hu='Huamulan:BAABLgAECn9GAAICAAkJGwh2gQBgAQACAAkJGwh2gQBgAQAAAA==.',
Ib='Ibc:BAAALgADCgcJDQABLgAFFAIJBAALAAAAAA==.Ibchilling:BAABLgAECn8pAAIPAAgJxBr/SwDxAQAPAAgJxBr/SwDxAQABLgAFFAIJBAALAAAAAA==.Ibcorrupted:BAAALgAFFAIJBAAAAA==.',
Ic='Icarrus:BAACLgAFFH8QAAIFAAQJJRHNKwDnAAAFAAQJJRHNKwDnAAAuAAQKfywAAwUACQnkHDIYAEQCAAUACQnkHDIYAEQCABIABAmQE9NVAKkAAAEuAAUUBAkHABkAzQsA.Icarus:BAAALgADCgEJAQABLgAFFAQJBwAZAM0LAA==.Iccarus:BAAALgAECgUJBQABLgAFFAQJBwAZAM0LAA==.Icebone:BAAALgAECgcJCgABLgAECggJEwALAAAAAA==.',
Ig='Ignis:BAACLgAFFH8HAAIZAAQJzQtMcQARAQAZAAQJzQtMcQARAQAuAAQKfxYAAxkABgl5G6d9AF8BABkABgnzGad9AF8BAB0AAQkRFk0yAEAAAAAA.',
Il='Illioch:BAAALgAECgEJAQAAAA==.',
Im='Imaway:BAAALgAECgEJAQAAAA==.',
In='Inesh:BAAALgADCgEJAQAAAA==.',
Ir='Irrizia:BAAALgADCgkJCgAAAA==.',
Is='Iseldra:BAAALgADCggJDgAAAA==.',
['Iç']='Içyhot:BAAALgAECgEJBAABLgAECgcJEwALAAAAAA==.',
Ja='Jackbfistn:BAAALgAECggJEwAAAA==.Jaskim:BAABLgAECn8dAAMZAAkJzAzxWgCuAQAZAAkJzAzxWgCuAQAdAAIJ2AUWMQBFAAAAAA==.',
Je='Jeses:BAAALgAECgUJCQABLgAECgkJLwACAEIWAA==.',
Jo='Jolty:BAAALgAECgEJAQABLgAFFAYJFQAZAEMgAA==.Jooni:BAAALgADCggJDwAAAA==.Jordomon:BAABLgAECn8bAAMVAAcJWwa5SwDOAAAVAAcJTwa5SwDOAAAeAAMJ8gaPOQBgAAAAAA==.',
Jy='Jyundiel:BAAALgADCgYJBgABLgADCgYJBgALAAAAAA==.',
['Jú']='Júliët:BAAALgAECgIJAgAAAA==.',
Ka='Kaazaama:BAAALgADCgYJBgAAAA==.Kahtonah:BAAALgADCgMJAwAAAA==.Kalessin:BAAALgADCgkJDgABLgAECgEJAQALAAAAAA==.Kaltaan:BAABLgAECn8sAAQcAAkJxiHnBQAcAwAcAAkJxiHnBQAcAwARAAQJUh8jPABKAQAKAAEJ4R3XbgBWAAAAAA==.Karasan:BAABLgAECn8jAAIBAAkJ0BdYLAAgAgABAAkJ0BdYLAAgAgAAAA==.Karenas:BAABLgAECn8lAAMPAAgJoSHWHACoAgAPAAgJoSHWHACoAgAbAAIJ4QqZFgBmAAAAAA==.Karr:BAABLgAECn8XAAICAAgJNAeKqwAaAQACAAgJNAeKqwAaAQAAAA==.Kataraara:BAACLgAFFH8HAAITAAQJRiDDFABnAQATAAQJRiDDFABnAQAuAAQKfxcAAhMACAntJN4EADwDABMACAntJN4EADwDAAEuAAUUBgkbAA0ABCYA.Katbeans:BAABLgAECn8pAAQFAAkJeRtLDQC3AgAFAAkJeRtLDQC3AgATAAUJIQ6RYgC4AAASAAEJJhZyiwA7AAAAAA==.Kathrynne:BAAALgAECgUJCQAAAA==.Katrielle:BAAALgAECgUJBQAAAA==.Kaykoh:BAAALgAFFAIJAgAAAA==.',
Ke='Kelicemoon:BAABLgAECn8oAAMIAAkJZgrfXACDAQAIAAkJSQnfXACDAQAOAAcJIQeCLgBZAAAAAA==.Kemono:BAAALgADCgYJBgAAAA==.',
Kh='Khaliope:BAABLgAECn82AAIgAAkJpQ0scgAxAQAgAAkJpQ0scgAxAQAAAA==.Khat:BAAALgADCgkJCQAAAA==.',
Ki='Kiryu:BAAALgAECgUJBQAAAA==.',
Ko='Korzari:BAAALgADCgEJAQAAAA==.Koven:BAAALgADCgcJCQAAAA==.',
Kr='Krogers:BAAALgAECgQJCQABLgAECgYJCAALAAAAAA==.',
Ku='Kumojo:BAAALgAECgkJAgAAAA==.',
Ky='Kyndlearya:BAAALgADCgEJAQAAAA==.',
['Kû']='Kûrr:BAAALgAECgEJAQABLgAFFAEJAQALAAAAAA==.',
La='Lahrnaon:BAAALgAFFAIJAgAAAA==.Laxeron:BAABLgAECn8iAAIMAAkJQCSfBAAUAwAMAAkJQCSfBAAUAwAAAA==.',
Le='Leotherassy:BAAALgAECgYJCQAAAA==.Leychron:BAAALgAECgEJAQAAAA==.',
Li='Lightsworn:BAAALgAECgEJAQAAAA==.Lilin:BAAALgAECgYJBwAAAA==.',
Lo='Lotiel:BAAALgAECgMJCQABLgAFFAUJFwAhAEoSAA==.',
Lu='Lucrecia:BAABLgAECn8WAAMgAAYJbB0oUgCuAQAgAAUJ2iEoUgCuAQAiAAEJswudLAAuAAAAAA==.',
Ly='Lymara:BAAALgADCgcJCAAAAA==.Lynthirae:BAAALgADCgcJDAAAAA==.',
['Lø']='Lørðzêdd:BAAALgAECgQJEgAAAA==.',
Ma='Madmabel:BAAALgADCgQJBAAAAA==.Mahkaidook:BAAALgADCgYJBgAAAA==.Mal:BAAALgADCgkJCQABLgAECgYJBgALAAAAAA==.Manyace:BAAALgAECgQJBgAAAA==.',
Mc='Mcbodhran:BAABLgAECn8gAAICAAkJDA/zcQB/AQACAAkJDA/zcQB/AQAAAA==.Mcfeast:BAABLgAECn8ZAAIKAAgJ+A8LKACGAQAKAAgJ+A8LKACGAQAAAA==.',
Me='Medra:BAABLgAECn8uAAQMAAkJ2RR/HQD7AQAMAAkJ2RR/HQD7AQAjAAQJEgO0PQBsAAAkAAIJ2wZoZQBHAAAAAA==.Meowdi:BAAALgAECgEJAQAAAA==.Merogoth:BAAALgADCgUJBwAAAA==.Mestrois:BAABLgAECn87AAIPAAgJRAelmgA/AQAPAAgJRAelmgA/AQAAAA==.',
Mi='Minibone:BAAALgAECgMJAwABLgAECggJEwALAAAAAA==.Mixr:BAAALgADCgQJAwAAAA==.',
Mo='Monana:BAAALgADCgkJBQAAAA==.Morar:BAAALgAECgUJDAAAAA==.Morul:BAAALgAECgQJBAAAAA==.',
Ms='Msprettÿp:BAAALgADCgIJAgAAAA==.',
Mu='Murimlinn:BAAALgADCgMJAwAAAA==.Mustafa:BAAALgAECgUJCAAAAA==.',
Na='Nanija:BAAALgAECgEJAQAAAA==.Narushi:BAAALgAECgQJBQAAAA==.',
Ne='Nezrin:BAAALgADCgQJBwAAAA==.',
Ni='Nightcat:BAAALgAECgQJBQAAAA==.Nitebäne:BAAALgADCggJCAAAAA==.Nitesbane:BAAALgADCgYJBgABLgAECggJFwACAKAgAA==.Nitesbåne:BAAALgADCgcJBwAAAA==.Niteshiftah:BAAALgADCgcJBwAAAA==.Nitestorm:BAAALgAECgQJBAAAAA==.Nivaniraa:BAAALgAECgEJAgAAAA==.Nixie:BAABLgAECn8uAAMhAAkJEgbKXgAQAQAhAAkJEgbKXgAQAQAVAAkJ8gR+QAD9AAAAAA==.',
No='Nobonesjones:BAACLgAFFH8LAAIEAAUJlQacBgDfAAAEAAUJlQacBgDfAAAuAAQKfxsAAgQACQlPFjMeAM4BAAQACQlPFjMeAM4BAAAA.',
Og='Oguricap:BAAALgADCgcJBwAAAA==.Ogwarshock:BAACLgAFFH8OAAQIAAUJeBoXTAAhAQAIAAQJzxUXTAAhAQAOAAEJChvDIgBLAAAJAAEJAACsLAAAAAAuAAQKfyMAAwgACAkAJLQtABwCAAgABgm4I7QtABwCAA4ABQm9HzkaAHsBAAAA.',
Ok='Okkotsu:BAAALgAECgIJAwAAAA==.',
Ol='Oliiver:BAABLgAECn8uAAIBAAkJdSCNCwDuAgABAAkJdSCNCwDuAgAAAA==.',
Om='Omni:BAAALgAECgEJAQABLgAFFAQJDQAUAIMTAA==.Omnivore:BAAALgADCgcJCAAAAA==.Omën:BAAALgAECgQJBAABLgAECgQJCAALAAAAAA==.',
On='Oniichan:BAAALgAECgQJBQAAAA==.',
Or='Orbeez:BAABLgAECn8oAAIgAAkJNyC+EwCaAgAgAAkJNyC+EwCaAgAAAA==.',
Pa='Pack:BAAALgAECgcJAQAAAA==.Paladlin:BAAALgADCgYJBgAAAA==.Panaceus:BAABLgAECn86AAIlAAkJ1yK0AQBwAwAlAAkJ1yK0AQBwAwAAAA==.Paragon:BAAALgADCgkJDQABLgAFFAMJDgAZAFYgAA==.Patron:BAAALgADCgIJAwAAAA==.',
Pe='Pepe:BAAALgAECgMJAwAAAA==.Perennial:BAAALgAECgYJCQAAAA==.Perpetrator:BAAALgAECgEJAgAAAA==.',
Ph='Phreeq:BAEALgAECgYJDgABLgAECggJLQAaACUSAA==.Phrequency:BAEBLgAECn8tAAMaAAgJJRIMJgDNAQAaAAgJJRIMJgDNAQACAAcJXxNegABjAQAAAA==.',
Pi='Piety:BAAALgADCgIJAgAAAA==.Pig:BAAALgAECgEJAQABLgAFFAYJCwAKACggAA==.',
Pl='Plazmafury:BAAALgAFFAMJBAAAAA==.Plumsham:BAAALgADCgQJBAAAAA==.',
Po='Poisonóus:BAACLgAFFH8OAAINAAUJrBiNFgAfAQANAAUJrBiNFgAfAQAuAAQKfzIAAg0ACAmPHhINAC4CAA0ACAmPHhINAC4CAAAA.',
Pr='Profang:BAAALgAECgQJBAAAAA==.',
Py='Pyrelic:BAABLgAFFH8YAAISAAUJgRqADwA3AQASAAUJgRqADwA3AQAAAA==.Pyroela:BAAALgAECgUJCgABLgAFFAQJEwANAGggAA==.',
['Pö']='Pöncho:BAAALgAECgEJAQAAAA==.',
Qa='Qayllera:BAAALgAECgQJCgAAAA==.',
Qe='Qelcie:BAAALgAECgQJBQAAAA==.',
Qu='Quixotic:BAAALgADCgUJBQAAAA==.Quizet:BAAALgADCgYJCgAAAA==.',
Ra='Radicchio:BAAALgADCgkJBQAAAA==.Radkeem:BAABLgAECn8YAAINAAkJiB1DCACKAgANAAkJiB1DCACKAgAAAA==.Raf:BAAALgAECgYJBwAAAA==.Raizo:BAAALgAECgEJAwAAAA==.Rakeem:BAAALgAECgcJEAABLgAECgkJGAANAIgdAA==.Ralivan:BAAALgADCgEJAQAAAA==.Ravenhawk:BAAALgADCgQJCAAAAA==.Razorknight:BAAALgAECgEJAQAAAA==.',
Re='Redtoxin:BAAALgAECgEJAQAAAA==.Reilley:BAACLgAFFH8XAAIZAAUJAxqfVgA4AQAZAAUJAxqfVgA4AQAuAAQKfzIAAhkACAmyItYWALYCABkACAmyItYWALYCAAAA.Reilleÿ:BAAALgAECgQJBAABLgAFFAUJFwAZAAMaAA==.Reko:BAAALgAECgYJBgAAAA==.Remorsa:BAAALgAECgYJEQAAAA==.Renni:BAABLgAECn8sAAIIAAkJxBaRKgAqAgAIAAkJxBaRKgAqAgABLgAECgkJHwATAOAYAA==.Reshath:BAAALgADCgEJAQAAAA==.Reznor:BAABLgAECn8kAAIaAAkJLBbDJwDtAQAaAAkJLBbDJwDtAQAAAA==.',
Ri='Rinela:BAAALgADCgcJBwAAAA==.Riselle:BAAALgAFFAEJAQAAAA==.',
Ro='Rosealia:BAABLgAECn8XAAIBAAcJ/QXZlwACAQABAAcJ/QXZlwACAQAAAA==.',
Ru='Runeight:BAAALgADCgIJAQAAAA==.',
Ry='Ryder:BAAALgAECgIJBAAAAA==.',
['Ró']='Rómëo:BAACLgAFFH8UAAIHAAYJ8RohCwC7AQAHAAYJ8RohCwC7AQAuAAQKf04AAgcACQl3IssCAB4DAAcACQl3IssCAB4DAAAA.',
Sa='Sabbatical:BAAALgADCgEJAQAAAA==.Sacon:BAAALgADCgcJBwABLgAECgYJBgALAAAAAA==.Sahmeah:BAAALgAECgYJCAAAAA==.Saintzan:BAAALgAECgkJEQAAAA==.Salivan:BAAALgAECgUJCgAAAA==.San:BAAALgAECgYJDwAAAA==.Sanketsu:BAAALgADCgYJCwABLgAECgkJKwACAFYUAA==.Sathariel:BAAALgAECgIJAgAAAA==.',
Sc='Scalyboyos:BAABLgAECn8mAAMlAAkJcwyTFwBPAQAlAAgJwwuTFwBPAQAmAAEJxwfXiAA5AAAAAA==.Schmoop:BAACLgAFFH8LAAIKAAYJKCBdCADEAQAKAAYJKCBdCADEAQAuAAQKfy8ABAoACAnyI6wIAL8CAAoACAnyI6wIAL8CABEABgmLGoEtAFEBABwAAQnxEGNWADQAAAAA.',
Se='Seldaria:BAAALgAECgYJEAAAAA==.Senza:BAABLgAECn8hAAICAAcJZQrpsQAQAQACAAcJZQrpsQAQAQAAAA==.Senzyri:BAABLgAECn8mAAIBAAkJLxPUOADwAQABAAkJLxPUOADwAQAAAA==.Sephirath:BAAALgAECgIJAgAAAA==.Serote:BAAALgADCgcJBwAAAA==.Setmabone:BAAALgADCgkJCQABLgAECggJEwALAAAAAA==.Sevilo:BAAALgADCgkJCwABLgAECgIJAgALAAAAAA==.',
Sh='Shamagoth:BAAALgADCgEJAQAAAA==.Shambhala:BAAALgAECgYJEgAAAA==.Shoes:BAAALgAECgUJBwAAAA==.',
Si='Simic:BAABLgAECn8vAAINAAkJzQ8EGgCEAQANAAkJzQ8EGgCEAQAAAA==.',
Sk='Skre:BAAALgAECgYJBgAAAA==.',
Sm='Smiddy:BAAALgAFFAIJBAAAAA==.Smokeace:BAAALgAECgEJAQAAAA==.',
Sn='Snowthistle:BAABLgAECn8WAAIVAAcJQgVKTwDBAAAVAAcJQgVKTwDBAAAAAA==.',
So='Sorle:BAAALgADCgYJCQABLgAECgkJLgAMANkUAA==.Soulnãris:BAAALgAECgcJCQAAAA==.',
Sp='Spin:BAABLgAFFH8JAAMSAAIJrRn/KQCUAAASAAIJoxb/KQCUAAATAAEJIBcKUgBCAAAAAA==.Spudpal:BAAALgADCgEJAQABLgAECgkJLAAcAMYhAA==.Spyro:BAAALgADCgUJBQAAAA==.',
Sq='Squirley:BAAALgAECgQJCAAAAA==.',
St='Starge:BAAALgAECgYJBgAAAA==.Stargefall:BAAALgAECgMJAwAAAA==.Static:BAAALgAECgYJBgAAAA==.Stonymahoney:BAABLgAECn89AAICAAkJwxrGIgBxAgACAAkJwxrGIgBxAgAAAA==.',
Su='Sudokoo:BAAALgADCgMJAwAAAA==.Sumorna:BAAALgAECgEJAQAAAA==.Suraisu:BAACLgAFFH8FAAIMAAMJSxqUKAD/AAAMAAMJSxqUKAD/AAAuAAQKfzUAAgwACQk/JLICAEEDAAwACQk/JLICAEEDAAAA.Suê:BAAALgADCgEJAQABLgADCgQJBAALAAAAAA==.',
Sv='Sveela:BAACLgAFFH8RAAIUAAQJpiKDBQCNAQAUAAQJpiKDBQCNAQAuAAQKfyQAAhQACQlrIsEDAMoCABQACQlrIsEDAMoCAAAA.Sveelaa:BAABLgAECn8lAAIBAAgJax8qGwB2AgABAAgJax8qGwB2AgABLgAFFAQJEQAUAKYiAA==.Sveella:BAAALgAECggJDgABLgAFFAQJEQAUAKYiAA==.',
Sw='Swampjimmy:BAAALgAECgkJDAAAAA==.',
Sy='Sylrin:BAAALgADCgcJCgAAAA==.Synap:BAAALgADCgEJAQAAAA==.',
Ta='Tabchan:BAAALgAECgYJBwAAAA==.Tacocat:BAABLgAECn89AAMRAAkJmR4lCADdAgARAAkJmR4lCADdAgAKAAEJNAUGjAAlAAAAAA==.Tadeusz:BAAALgADCgEJAQAAAA==.Talras:BAAALgAECgMJAwAAAA==.',
Te='Temlock:BAABLgAECn8yAAIIAAkJFxgsMQBIAgAIAAkJFxgsMQBIAgAAAA==.Tempest:BAAALgAECgUJBQABLgAFFAMJDgAZAFYgAA==.Temtank:BAABLgAECn83AAINAAkJJCLoAwD2AgANAAkJJCLoAwD2AgABLgAECgkJMgAIABcYAA==.',
Tr='Trak:BAABLgAECn8ZAAImAAgJOQ0+PAAuAQAmAAgJOQ0+PAAuAQAAAA==.Trukarak:BAABLgAECn8rAAICAAkJVhR6RgDoAQACAAkJVhR6RgDoAQAAAA==.',
Tu='Tuvaquitamuu:BAAALgAECgEJAQAAAA==.',
Va='Vaeegoldiir:BAAALgAECgEJAQAAAA==.Vaelithria:BAAALgAECgcJCAABLgAFFAYJFAAHAPEaAA==.Valenti:BAABLgAECn8kAAMnAAkJ0A86EwCKAQAnAAkJ0A86EwCKAQACAAEJ0AaaowEmAAAAAA==.Valor:BAABLgAECn8kAAICAAcJhiHJTADWAQACAAcJhiHJTADWAQAAAA==.Vanity:BAAALgADCgMJAwAAAA==.',
Ve='Veliann:BAAALgAECgEJAQAAAA==.Vellatrix:BAAALgAECgQJBgAAAA==.Velynesti:BAAALgAECgQJBAAAAA==.',
Vi='Vipershot:BAAALgADCggJDwAAAA==.',
Wa='Warlode:BAAALgADCgkJDgAAAA==.',
We='Weewoo:BAAALgADCgcJCwAAAA==.',
Wi='Wildama:BAABLgAECn8jAAIhAAkJnA/nNwCuAQAhAAkJnA/nNwCuAQAAAA==.Wildtail:BAAALgAECgYJCgAAAA==.',
Wr='Wrenwillow:BAAALgAECgIJAgAAAA==.',
Wu='Wumbo:BAAALgADCgEJAQAAAA==.',
Xa='Xarríøn:BAAALgADCgYJBgABLgAFFAMJCgACAB0ZAA==.',
Xh='Xhadowz:BAAALgAECgEJAgAAAA==.',
Xi='Xiao:BAABLgAECn8uAAMFAAkJuReBFgBTAgAFAAkJuReBFgBTAgASAAQJoArwVACrAAAAAA==.',
Xy='Xylaini:BAAALgAECgQJBAABLgAFFAEJAQALAAAAAA==.',
Ya='Yahargul:BAABLgAECn8kAAIKAAgJFQ83KgB4AQAKAAgJFQ83KgB4AQAAAA==.',
Yo='Yogafarts:BAAALgAECgYJCAAAAA==.',
Za='Zanatilli:BAAALgAECgEJAQAAAA==.Zaterok:BAAALgAECgMJAwABLgAECgkJKwACAFYUAA==.',
Ze='Zeik:BAABLgAECn8zAAMnAAkJVB4RBAC5AgAnAAkJVB4RBAC5AgACAAMJngruQwFbAAAAAA==.Zephyrgosa:BAAALgADCgcJDgAAAA==.Zerase:BAAALgAECgEJAQAAAA==.',
Zu='Zucco:BAAALgAECgkJDgAAAA==.Zuufungo:BAAALgAECgUJBQABLgAECgkJLAAcAMYhAA==.',
['Zí']='Zíx:BAABLgAECn8oAAIjAAkJSxK3FgCCAQAjAAkJSxK3FgCCAQAAAA==.',
['Àl']='Àlcàrà:BAABLgAECn8YAAMNAAcJCg8SJgAYAQANAAcJCg8SJgAYAQAZAAEJDgptIQEzAAAAAA==.',
['Ål']='Åldaren:BAAALgADCgQJBAAAAA==.',
['Ÿa']='Ÿamar:BAAALgADCgMJAwAAAA==.',
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
