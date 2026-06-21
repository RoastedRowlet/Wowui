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

local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Hunter-Marksmanship','DemonHunter-Havoc','Monk-Mistweaver','Druid-Restoration','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Warrior-Fury','Warrior-Arms','Unknown-Unknown','DeathKnight-Blood','Warlock-Destruction','Mage-Frost','Shaman-Enhancement','Priest-Holy','Monk-Windwalker','Monk-Brewmaster','Druid-Guardian','Druid-Balance','Shaman-Restoration','Paladin-Holy','Shaman-Elemental','Rogue-Outlaw','DeathKnight-Unholy','Mage-Arcane','Priest-Discipline','DeathKnight-Frost','Druid-Feral','Hunter-Survival','DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Vengeance','Warrior-Protection','Paladin-Protection',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=46,date='2026-06-20',data={Ad='Adamonious:BAAALgAECgYJCwABLgAECgkJFgABAA8WAA==.Adaware:BAAALgAECgUJBgAAAA==.Addieeboy:BAAALgADCgEJAQAAAA==.Adellea:BAAALgAECgYJBwAAAA==.',
Ai='Aisha:BAAALgAECgEJAgAAAA==.',
Al='Alaponia:BAAALgAECgEJAgAAAA==.Alba:BAABLgAECn8uAAICAAgJkx2NNAAuAgACAAgJkx2NNAAuAgABLgAFFAQJFQABACEZAA==.Aletta:BAAALgAECgcJDQAAAA==.Allast:BAAALgADCgYJDQAAAA==.',
An='Andezard:BAABLgAECn8/AAMBAAkJuhjAKQA3AgABAAkJuhjAKQA3AgADAAIJTAkKMwBPAAAAAA==.Angelys:BAABLgAECn8iAAIEAAgJLwjELgAOAQAEAAgJLwjELgAOAQAAAA==.',
Ap='Aphrobitey:BAAALgAECgIJAgAAAA==.',
Aq='Aquâ:BAAALgADCgkJEAABLgAECgkJMQAFAOIYAA==.',
Ar='Arathas:BAAALgADCgcJDAAAAA==.Arianes:BAAALgAECgcJDgAAAA==.Arrowin:BAAALgADCgYJBgAAAA==.Arturias:BAABLgAECn8cAAICAAgJ7hLYawCXAQACAAgJ7hLYawCXAQAAAA==.',
At='Athenaowl:BAABLgAECn8XAAIBAAgJHgqfewBIAQABAAgJHgqfewBIAQAAAA==.',
Au='Autofocus:BAABLgAECn8eAAIBAAgJPBqZQQDdAQABAAgJPBqZQQDdAQAAAA==.',
Aw='Aweyna:BAABLgAECn8aAAIGAAkJ0QxYUgBGAQAGAAkJ0QxYUgBGAQAAAA==.Awisha:BAAALgADCgUJBQAAAA==.',
Ay='Ayanoriko:BAACLgAFFH8PAAIHAAUJ7hTgBAA1AQAHAAUJ7hTgBAA1AQAuAAQKfywAAgcACQnkHx4DAIsCAAcACQnkHx4DAIsCAAAA.Ayasumi:BAAALgAECgIJAgAAAA==.',
Ba='Babaganoosh:BAAALgAECgUJCwAAAA==.Baoyue:BAAALgAECggJCwABLgAFFAYJFAAIAPEaAA==.Barracuda:BAAALgAECgYJBgAAAA==.',
Be='Beans:BAABLgAFFH8OAAMJAAUJFRu2PQBXAQAJAAUJFRu2PQBXAQAKAAEJ4grKJgBIAAABLgAFFAYJDgALACshAA==.Benmonk:BAAALgAECgMJAwAAAA==.',
Bi='Bifur:BAAALgADCgkJDwAAAA==.Bigbuttflori:BAAALgAECgMJBQAAAA==.Bigstones:BAACLgAFFH8JAAIMAAMJRQQTPwCrAAAMAAMJRQQTPwCrAAAuAAQKfykAAwwACQmbD2otAJwBAAwACQmqDmotAJwBAA0ABQmjDz88ANQAAAAA.',
Bl='Blacksavior:BAAALgAECgQJBAAAAA==.Blindbone:BAAALgAECgcJCQABLgAECggJEwAOAAAAAA==.Blisterine:BAAALgAECgYJBgAAAA==.Bluehydra:BAAALgADCgcJCAAAAA==.',
Bo='Bobbydigital:BAABLgAECn86AAIPAAkJvhtvCgBrAgAPAAkJvhtvCgBrAgAAAA==.Bohd:BAAALgADCgIJAgAAAA==.Bolas:BAAALgAECgYJCAAAAA==.Boneski:BAAALgAECgUJEAAAAA==.Booger:BAAALgAECgQJBAAAAA==.',
Br='Bracynn:BAABLgAECn8hAAIPAAgJ7QZPNwC4AAAPAAgJ7QZPNwC4AAAAAA==.Brixx:BAAALgAECgMJAwAAAA==.Brudiclad:BAABLgAECn8uAAQKAAkJzxR7CgC3AQAKAAkJQRN7CgC3AQAJAAYJaQu1qQDvAAAQAAIJzxH2UQB4AAAAAA==.',
Bu='Budfight:BAAALgAECgQJCAAAAA==.Burnt:BAAALgAECgQJBAAAAA==.Butterfinger:BAAALgADCgQJBwAAAA==.Buxxor:BAAALgAECgcJBwAAAA==.',
Ca='Caimark:BAABLgAECn8uAAIRAAgJzgOrxwD+AAARAAgJzgOrxwD+AAAAAA==.Calahan:BAACLgAFFH8HAAICAAMJgBm9agDZAAACAAMJgBm9agDZAAAuAAQKfx4AAgIACAmxGmw0AFACAAIACAmxGmw0AFACAAAA.',
Ch='Chakuneeai:BAAALgADCgYJBgAAAA==.Chancleta:BAAALgAECgYJDAAAAA==.Cherub:BAAALgADCgIJAgAAAA==.Chikostix:BAABLgAECn8tAAISAAgJ9wlEGABGAQASAAgJ9wlEGABGAQAAAA==.Christae:BAABLgAECn8nAAITAAkJNRn4EABcAgATAAkJNRn4EABcAgAAAA==.',
Cl='Clementînê:BAAALgAECgIJAgAAAA==.Clemêntine:BAAALgAECgYJDAAAAA==.Clydè:BAABLgAECn9SAAMUAAkJ6RaHFABJAgAUAAgJbheHFABJAgAVAAkJrhL8GwDFAQAAAA==.Cláncey:BAAALgAFFAEJAQAAAA==.',
Co='Coachhazzard:BAAALgAECgQJCwAAAA==.Cocytus:BAAALgADCgIJAgABLgAFFAIJBwAJADkaAA==.Colinferal:BAABLgAFFH8FAAIWAAEJRCAmPgAzAAAWAAEJRCAmPgAzAAAAAA==.Combatant:BAAALgADCgYJDAAAAA==.Compromise:BAAALgAECgYJCAAAAA==.Compromised:BAACLgAFFH8GAAIEAAMJ1A6mGwDFAAAEAAMJ1A6mGwDFAAAuAAQKfy8AAgQACQneG/8KAHcCAAQACQneG/8KAHcCAAAA.Connalious:BAAALgAECgEJAQAAAA==.Conquests:BAAALgAECgIJAgAAAA==.Corelack:BAACLgAFFH8OAAIWAAUJgxOJEwDnAAAWAAUJgxOJEwDnAAAuAAQKfxcAAxYACQm9Da0lACYBABYACQmZDa0lACYBABcABQmpBd1iAI8AAAAA.',
Cr='Crwth:BAAALgAECgUJBQAAAA==.',
Ct='Ctrlaltmagic:BAAALgAECgEJAgAAAA==.',
Cu='Cupis:BAAALgAECgQJBAAAAA==.Curendae:BAABLgAECn8zAAIBAAkJ0Bf8LAApAgABAAkJ0Bf8LAApAgAAAA==.',
Da='Dabaldzombie:BAACLgAFFH8TAAIRAAUJoxqPLAAEAQARAAUJoxqPLAAEAQAuAAQKfx0AAhEACQkSGTxMAFICABEACQkSGTxMAFICAAEuAAUUBgkTABgA6B8A.Daddyshocker:BAABLgAECn8WAAIZAAcJthRILwCeAQAZAAcJthRILwCeAQAAAA==.Danamy:BAAALgADCggJDQAAAA==.Daxzazi:BAABLgAECn8cAAMUAAcJ9gNNWACvAAAUAAcJ9gNNWACvAAAFAAUJrAQXkwByAAAAAA==.',
De='Deadlee:BAAALgADCgEJAQAAAA==.Deadmanwlkin:BAAALgADCgIJAgAAAA==.Defias:BAAALgADCggJCAAAAA==.Delicious:BAEBLgAFFH8IAAIPAAUJAAtTJADMAAAPAAUJAAtTJADMAAABLgAFFAcJEwAaABEVAA==.Despair:BAAALgADCggJDgABLgAFFAQJFQABACEZAA==.',
Di='Dice:BAACLgAFFH8RAAIbAAUJAB4LBABdAQAbAAUJAB4LBABdAQAuAAQKfzAAAxsACQllIu8AABIDABsACQllIu8AABIDAAgAAQmeFHZYAEUAAAAA.Disturbd:BAACLgAFFH8OAAMcAAUJ5Aq0gwABAQAcAAQJ5Aq0gwABAQAPAAEJAADBYAAAAAAuAAQKfxgAAxwACQn9DENeAK0BABwACQn9DENeAK0BAA8ABAmJAMY9AFsAAAAA.Disturbian:BAAALgAFFAIJAwABLgAFFAUJDgAcAOQKAA==.Dixierecht:BAABLgAECn8gAAIZAAgJbhsNGABHAgAZAAgJbhsNGABHAgAAAA==.',
Do='Docvader:BAAALgAECgEJBQAAAA==.Dodrop:BAAALgADCgYJBwAAAA==.',
Dr='Drunkenhealz:BAAALgAECgUJEAAAAA==.Drvargas:BAAALgAECgQJDAAAAA==.',
['Då']='Dårth:BAAALgAECgEJAQAAAA==.',
['Dè']='Dèrty:BAAALgAECgIJAgAAAA==.',
El='Elenestern:BAECLgAFFH8FAAIRAAIJXRoeEwBYAAARAAIJXRoeEwBYAAAuAAQKfzYAAhEACQmwEkZIAAICABEACQmwEkZIAAICAAAA.Elmo:BAABLgAECn8oAAMRAAkJHhZIPQAmAgARAAkJ0BVIPQAmAgAdAAEJwxVmFQA/AAAAAA==.',
Em='Emryssa:BAAALgAECgMJDAAAAA==.',
Er='Erosis:BAACLgAFFH8OAAIRAAUJ/xuZSgBMAQARAAUJ/xuZSgBMAQAuAAQKfyQAAhEACAlsIwIvALYCABEACAlsIwIvALYCAAAA.',
Es='Esia:BAAALgADCgkJCQAAAA==.',
Ev='Evarg:BAAALgADCgcJDQAAAA==.',
Ex='Exghoulfiend:BAAALgAECgIJAgAAAA==.',
Ez='Ezaratren:BAAALgAECgUJCgABLgAFFAUJDgAWAIMTAA==.',
Fa='Fakêr:BAAALgADCgEJAQAAAA==.',
Fe='Fear:BAACLgAFFH8GAAIJAAMJMxu+HQANAQAJAAMJMxu+HQANAQAuAAQKfygAAwkACAmDIOgrAF8CAAkACAmDIOgrAF8CABAABQkbFk4bAHIBAAAA.Felcatalyist:BAABLgAECn8gAAMcAAkJABgcYwDKAQAcAAkJtBUcYwDKAQAPAAgJXA2eKAAQAQAAAA==.Felisaty:BAAALgAECgEJAQAAAA==.Fellisaty:BAABLgAECn8WAAIZAAgJfQ9rMgCMAQAZAAgJfQ9rMgCMAQAAAA==.Felysria:BAAALgAECgQJAgAAAA==.',
Fi='Fistitresk:BAAALgADCgQJBQABLgAECgcJFAAeAIYeAA==.Fistofwayne:BAABLgAECn8cAAIVAAgJMBAxKABwAQAVAAgJMBAxKABwAQABLgAFFAYJHwAfAPoeAA==.',
Fr='Frizzalot:BAAALgAECgEJAwAAAA==.Frizzer:BAAALgAECgMJAwAAAA==.',
Ga='Gakopozy:BAABLgAECn8WAAIIAAcJPA21AABkAQAIAAcJPA21AABkAQAAAA==.Gambrinos:BAAALgADCgMJAwAAAA==.Gander:BAAALgADCgEJAQABLgAECgEJAQAOAAAAAA==.Gandermon:BAAALgAECgEJAQAAAA==.Garnath:BAAALgADCgYJBgAAAA==.',
Ge='Geg:BAABLgAFFH8FAAIcAAMJvBEhJwD7AAAcAAMJvBEhJwD7AAAAAA==.',
Gl='Glorrex:BAAALgADCgYJBgAAAA==.',
Go='Gongsho:BAAALgAECgQJBgAAAA==.',
Gr='Grapez:BAAALgAFFAIJAgABLgAFFAcJIAAPADEaAA==.Grimlokke:BAAALgAECgIJAgABLgAFFAUJDgAWAIMTAA==.Grïmyst:BAAALgAECgEJAQABLgAFFAUJDgAWAIMTAA==.',
Gu='Guldán:BAAALgAECgYJEQAAAA==.',
Gw='Gwydre:BAACLgAFFH8TAAIPAAQJaCApFABPAQAPAAQJaCApFABPAQAuAAQKfxUAAg8ACAnqHvYNAC4CAA8ACAnqHvYNAC4CAAAA.',
Ha='Harbard:BAAALgADCgYJCwAAAA==.Havran:BAAALgAECgQJBAABLgAECgkJQwAWABYXAA==.Havrin:BAABLgAECn9DAAMWAAkJFhfAEADeAQAWAAkJFhfAEADeAQAgAAEJQhLgMQA7AAAAAA==.',
He='Headshots:BAACLgAFFH8VAAIBAAQJIRkvPgAxAQABAAQJIRkvPgAxAQAuAAQKfy4AAgEACQmVH10UAJMCAAEACQmVH10UAJMCAAAA.Heartsong:BAAALgAECgEJAQAAAA==.Heavylode:BAAALgAECgQJCAAAAA==.Hexatar:BAAALgAECgQJBAAAAA==.',
Hk='Hkia:BAAALgAFFAMJAwAAAA==.',
Ho='Hoardkiller:BAAALgAECgQJAwABLgAFFAUJFQAhANQNAA==.Holmie:BAAALgADCgkJCgAAAA==.Honk:BAAALgAFFAIJAwAAAA==.Hoofsoflove:BAAALgADCgQJBAAAAA==.Hoogablop:BAABLgAFFH8HAAICAAYJQxetJwBrAQACAAYJQxetJwBrAQABLgAFFAYJDgALACshAA==.Hoogaplop:BAACLgAFFH8aAAMPAAUJkybjEwBSAQAcAAUJkyYSOQCKAQAPAAUJqB/jEwBSAQAuAAQKf0UAAw8ACQnDJEgFANcCABwACQm5IQMUAAMDAA8ACAl1JEgFANcCAAEuAAUUBgkOAAsAKyEA.',
Hu='Huamulan:BAABLgAECn9UAAICAAkJPQ6RAgA6AQACAAkJPQ6RAgA6AQAAAA==.',
Ib='Ibc:BAAALgADCgcJDQABLgAFFAIJBQAcAJQRAA==.Ibchilling:BAABLgAECn8pAAIRAAgJxBpDTwDuAQARAAgJxBpDTwDuAQABLgAFFAIJBQAcAJQRAA==.Ibcorrupted:BAABLgAFFH8FAAIcAAIJlBFBzACWAAAcAAIJlBFBzACWAAAAAA==.',
Ic='Icarrus:BAACLgAFFH8RAAIFAAUJzxGQKAAqAQAFAAUJzxGQKAAqAQAuAAQKfy8AAwUACQnkHGYaAEUCAAUACQnkHGYaAEUCABQABQmTEFxNAM4AAAEuAAUUBAkIABwAzQsA.Icarus:BAAALgADCgEJAQABLgAFFAQJCAAcAM0LAA==.Iccarus:BAAALgAECgUJBQABLgAFFAQJCAAcAM0LAA==.Icebone:BAAALgAECgcJCgABLgAECggJEwAOAAAAAA==.',
Ig='Ignis:BAACLgAFFH8IAAIcAAQJzQuEfgAKAQAcAAQJzQuEfgAKAQAuAAQKfxYAAxwABgl5G4SEAFoBABwABgnzGYSEAFoBAB8AAQkRFno3AD8AAAAA.',
Il='Illioch:BAAALgAECgEJAQAAAA==.',
Im='Imaway:BAAALgAECgEJAQAAAA==.',
In='Inesh:BAAALgADCgEJAQAAAA==.',
Ir='Irrizia:BAAALgADCgkJCgAAAA==.',
Is='Iseldra:BAAALgAECgEJAQAAAA==.',
['Iç']='Içyhot:BAAALgAECgEJBAABLgAECgcJEwAOAAAAAA==.',
Ja='Jackbfistn:BAAALgAECggJEwAAAA==.Jaskim:BAABLgAECn8dAAMcAAkJzAzxXwCpAQAcAAkJzAzxXwCpAQAfAAIJ2AWkNgBCAAAAAA==.',
Je='Jeses:BAAALgAECgUJCQABLgAECgkJLwACAEIWAA==.',
Jo='Jolty:BAAALgAECgEJAQABLgAFFAYJGgAcAFEgAA==.Jooni:BAAALgADCggJDwAAAA==.Jordomon:BAABLgAECn8eAAMXAAcJzwbVTwDOAAAXAAcJwwbVTwDOAAAgAAMJ8gZOPwBfAAAAAA==.',
Jy='Jyundiel:BAAALgADCgYJBgABLgADCgYJBgAOAAAAAA==.',
['Jú']='Júliët:BAAALgAECgIJAgAAAA==.',
Ka='Kaazaama:BAAALgADCgYJBgAAAA==.Kahtonah:BAAALgADCgMJAwAAAA==.Kalessin:BAAALgADCgkJDgABLgAECgQJCAAOAAAAAA==.Kaltaan:BAABLgAECn8sAAQeAAkJxiFyBgAZAwAeAAkJxiFyBgAZAwATAAQJUh8jPABKAQALAAEJ4R0ydQBWAAAAAA==.Karasan:BAABLgAECn8jAAIBAAkJ0BeIMAAaAgABAAkJ0BeIMAAaAgAAAA==.Karenas:BAABLgAECn8mAAMRAAkJ6CB2EAD4AgARAAkJ6CB2EAD4AgAdAAIJ4QqZFgBmAAAAAA==.Karr:BAABLgAECn8XAAICAAgJNAcYtgAWAQACAAgJNAcYtgAWAQAAAA==.Kataraara:BAACLgAFFH8HAAIVAAQJRiBAGABgAQAVAAQJRiBAGABgAQAuAAQKfxcAAhUACAntJN4EADwDABUACAntJN4EADwDAAEuAAUUBgkgAA8ABCYA.Katbeans:BAABLgAECn8sAAQFAAkJGB1WDgC6AgAFAAkJGB1WDgC6AgAVAAUJIQ6RYgC4AAAUAAEJJhYglQA7AAAAAA==.Kathrynne:BAAALgAECgUJCQAAAA==.Katmai:BAAALgADCgEJAQAAAA==.Katrielle:BAAALgAECgUJBQAAAA==.Kaykoh:BAABLgAFFH8GAAIcAAIJtRvxDgCYAAAcAAIJtRvxDgCYAAAAAA==.',
Ke='Kelicemoon:BAABLgAECn8oAAMJAAkJZgoPYwB5AQAJAAkJSQkPYwB5AQAQAAcJIQd4MQBYAAABLgAFFAIJBgACAKQLAA==.Kemono:BAAALgADCgYJBgAAAA==.',
Kh='Khaliope:BAABLgAECn82AAIiAAkJpQ2VdwAyAQAiAAkJpQ2VdwAyAQAAAA==.Khat:BAAALgADCgkJCQAAAA==.',
Ki='Kiara:BAACLgAFFH8ZAAMjAAYJ8xZaEgBuAQAjAAUJVxlaEgBuAQAkAAIJWhapRQCwAAAuAAQKfy0AAyMACQlpH1QIALUCACMACQlpH1QIALUCACQABAm9E/lLAP0AAAAA.Kiryu:BAAALgAECgUJBQAAAA==.',
Ko='Korzari:BAAALgADCgEJAQAAAA==.Koven:BAAALgADCgcJCQAAAA==.',
Kr='Krogers:BAAALgAECgYJDwABLgAECgcJDQAOAAAAAA==.',
Ku='Kumojo:BAAALgAECgkJAgAAAA==.',
Ky='Kyndlearya:BAAALgAECgEJAQAAAA==.',
['Kû']='Kûrr:BAAALgAECgEJAQABLgAFFAEJAQAOAAAAAA==.',
La='Lahrnaon:BAAALgAFFAIJAgAAAA==.Laxeron:BAABLgAECn8iAAIMAAkJQCRWBQAMAwAMAAkJQCRWBQAMAwAAAA==.',
Le='Leotherassy:BAAALgAECgYJCQAAAA==.Leychron:BAAALgAECgEJAQAAAA==.',
Li='Lightsworn:BAAALgAECgEJAQAAAA==.Lilin:BAAALgAECgYJBwAAAA==.',
Lo='Longboneman:BAAALgAECgIJAgABLgAECggJEwAOAAAAAA==.Lotiel:BAAALgAECgMJCQABLgAFFAUJFwAGAEoSAA==.',
Lu='Lucrecia:BAABLgAECn8WAAMiAAYJbB0oUgCuAQAiAAUJ2iEoUgCuAQAlAAEJswudLAAuAAAAAA==.',
Ly='Lymara:BAAALgADCgcJCAAAAA==.Lynthirae:BAAALgADCgcJDAAAAA==.',
['Lø']='Lørðzêdd:BAAALgAECgQJEgAAAA==.',
Ma='Madmabel:BAAALgADCgQJBAAAAA==.Madness:BAAALgAECgIJAgAAAA==.Mahkaidook:BAAALgADCgYJBgAAAA==.Mal:BAAALgADCgkJCQABLgAFFAMJBAAOAAAAAA==.Manyace:BAAALgAECgQJBgAAAA==.',
Mc='Mcbodhran:BAABLgAECn8gAAICAAkJDA9teAB9AQACAAkJDA9teAB9AQAAAA==.Mcfeast:BAABLgAECn8ZAAILAAgJ+A++KwB2AQALAAgJ+A++KwB2AQAAAA==.',
Me='Medra:BAABLgAECn8uAAQMAAkJ2RSmHwDyAQAMAAkJ2RSmHwDyAQAmAAQJEgP8QABsAAANAAIJ2wYIbQBHAAAAAA==.Meowdi:BAAALgAECgQJCAAAAA==.Merogoth:BAAALgADCgUJBwAAAA==.Mestrois:BAABLgAECn9GAAIRAAgJVgqBBQDMAAARAAgJVgqBBQDMAAAAAA==.',
Mi='Minibone:BAAALgAECgMJAwABLgAECggJEwAOAAAAAA==.Mixr:BAAALgADCgQJAwAAAA==.',
Mo='Monana:BAAALgAECgQJBwAAAA==.Morar:BAAALgAECgUJDAAAAA==.Morul:BAAALgAECgQJBAAAAA==.',
Ms='Msprettÿp:BAAALgADCgIJAgAAAA==.',
Mu='Murimlinn:BAAALgADCgMJAwAAAA==.Mustafa:BAAALgAECgUJCAAAAA==.',
Na='Nanija:BAAALgAECgQJCAAAAA==.Narushi:BAAALgAECgQJBQAAAA==.',
Ne='Nezrin:BAAALgADCgQJBwAAAA==.',
Ni='Nightcat:BAAALgAECgUJBwAAAA==.Nitebäne:BAAALgADCggJCAAAAA==.Nitesbane:BAAALgADCgYJBgABLgAECgkJHAACACwgAA==.Nitesbåne:BAAALgADCgcJBwAAAA==.Niteshiftah:BAAALgADCgcJBwAAAA==.Nitestorm:BAAALgAECgQJBAAAAA==.Nivaniraa:BAAALgAECgEJAgAAAA==.Nixie:BAABLgAECn8uAAMGAAkJEgaRYgANAQAGAAkJEgaRYgANAQAXAAkJ8gSqRAD5AAAAAA==.',
No='Nobonesjones:BAACLgAFFH8LAAIEAAUJlQacBgDfAAAEAAUJlQacBgDfAAAuAAQKfxsAAgQACQlPFjMeAM4BAAQACQlPFjMeAM4BAAAA.',
Og='Oguricap:BAAALgADCgcJBwAAAA==.Ogwarshock:BAACLgAFFH8PAAQJAAUJxhq5TgAoAQAJAAQJHRa5TgAoAQAQAAEJChtIJgBIAAAKAAEJAAC6MQAAAAAuAAQKfyQAAwkACQk0IkEhAF4CAAkABwm0IUEhAF4CABAABQm9HzkaAHsBAAAA.',
Ok='Okkotsu:BAAALgAECgIJAwAAAA==.Okote:BAAALgAECgMJBAAAAA==.',
Ol='Oliiver:BAABLgAECn82AAIBAAkJ/SBzCgADAwABAAkJ/SBzCgADAwAAAA==.',
Om='Omni:BAAALgAECgEJAQABLgAFFAUJDgAWAIMTAA==.Omnivore:BAAALgADCgcJCAAAAA==.Omën:BAAALgAECgQJBAABLgAECgQJCAAOAAAAAA==.',
On='Oniichan:BAAALgAECgQJBQAAAA==.',
Or='Orbeez:BAABLgAECn8pAAIiAAkJNyAKFQCaAgAiAAkJNyAKFQCaAgAAAA==.',
Pa='Pack:BAAALgAECgcJAQAAAA==.Paladlin:BAAALgADCgYJCwAAAA==.Panaceus:BAABLgAECn86AAIjAAkJ1yLWAQBsAwAjAAkJ1yLWAQBsAwAAAA==.Paragon:BAAALgADCgkJDQABLgAFFAMJDwAcAFYgAA==.Patron:BAAALgAECgIJAgAAAA==.',
Pe='Pepe:BAAALgAECgUJBQAAAA==.Perennial:BAAALgAECgYJCQAAAA==.Perpetrator:BAAALgAECgYJBwAAAA==.',
Ph='Phreeq:BAEALgAECgYJDgABLgAECggJMwAZAK4UAA==.Phrequency:BAEBLgAECn8zAAMZAAgJrhQqJwDRAQAZAAgJrhQqJwDRAQACAAgJ+BG7cACNAQAAAA==.',
Pi='Piety:BAAALgADCgIJAgABLgAECgYJBgAOAAAAAA==.Pig:BAAALgAECgEJAQABLgAFFAYJDgALACshAA==.',
Pl='Plazma:BAAALgAECgEJAQAAAA==.Plazmafury:BAABLgAFFH8KAAMMAAYJ5g9fEgB1AQAMAAYJZw5fEgB1AQANAAEJyA02QgBDAAAAAA==.Plazmaglaive:BAAALgAFFAEJAQAAAA==.Plumsham:BAAALgADCgQJBAAAAA==.',
Po='Poisonóus:BAACLgAFFH8PAAIPAAUJrBiEGgATAQAPAAUJrBiEGgATAQAuAAQKfzMAAg8ACQmeHVkKAGwCAA8ACQmeHVkKAGwCAAAA.Polyxo:BAAALgAECgYJBwAAAA==.',
Pr='Profang:BAAALgAECgQJBAAAAA==.',
Py='Pyrelic:BAABLgAFFH8ZAAIUAAUJgRpfEgAqAQAUAAUJgRpfEgAqAQAAAA==.Pyroela:BAAALgAECgUJCgABLgAFFAQJEwAPAGggAA==.',
['Pö']='Pöncho:BAAALgAECgEJAQAAAA==.',
Qa='Qayllera:BAAALgAECgUJDwAAAA==.',
Qe='Qelcie:BAAALgAECgQJBQAAAA==.',
Qu='Quixotic:BAAALgADCgUJBgAAAA==.Quizet:BAAALgADCgYJCgAAAA==.',
Ra='Radicchio:BAAALgAECgQJBAAAAA==.Radkeem:BAABLgAECn8YAAIPAAkJiB0bCQCBAgAPAAkJiB0bCQCBAgAAAA==.Raf:BAAALgAECgYJBwAAAA==.Raizo:BAAALgAECgYJCAAAAA==.Rakeem:BAAALgAECgcJEAABLgAECgkJGAAPAIgdAA==.Ralivan:BAAALgADCgEJAQAAAA==.Ravenhawk:BAAALgADCgQJCAAAAA==.Razorknight:BAAALgAECgEJAQAAAA==.',
Re='Redtoxin:BAAALgAECgQJCAAAAA==.Reilley:BAACLgAFFH8aAAIcAAYJ3hUoPgB8AQAcAAYJ3hUoPgB8AQAuAAQKfzMAAhwACQnxIJUNAAADABwACQnxIJUNAAADAAAA.Reilleÿ:BAAALgAECgQJBAABLgAFFAYJGgAcAN4VAA==.Reko:BAAALgAECgYJDwAAAA==.Remorsa:BAABLgAECn8XAAMCAAcJxBvLTwDZAQACAAcJxBvLTwDZAQAZAAQJJRXOVwAcAQAAAA==.Renni:BAABLgAECn8sAAIJAAkJxBa8LQAiAgAJAAkJxBa8LQAiAgABLgAECgkJJAAVAKIZAA==.Reshath:BAAALgADCgEJAQAAAA==.Reznor:BAABLgAECn8kAAIZAAkJLBbDJwDtAQAZAAkJLBbDJwDtAQAAAA==.',
Ri='Rinela:BAAALgADCgcJBwAAAA==.Riselle:BAAALgAFFAEJAgAAAA==.',
Ro='Rosealia:BAABLgAECn8YAAIBAAgJjQYNogD+AAABAAgJjQYNogD+AAAAAA==.',
Ru='Runeight:BAAALgADCgIJAQAAAA==.',
Ry='Ryder:BAAALgAECgIJBAAAAA==.',
['Ró']='Rómëo:BAACLgAFFH8UAAIIAAYJ8RobDgCyAQAIAAYJ8RobDgCyAQAuAAQKf1cAAggACQloJlcAAJYDAAgACQloJlcAAJYDAAAA.',
Sa='Sabbatical:BAAALgADCgEJAQAAAA==.Sacon:BAAALgAECgEJAQABLgAFFAMJBAAOAAAAAA==.Sahmeah:BAAALgAECgYJCQAAAA==.Saintzan:BAAALgAECgkJEQAAAA==.Salivan:BAAALgAECgUJCgAAAA==.San:BAAALgAECgYJDwAAAA==.Sanketsu:BAAALgADCgYJCwABLgAECgkJKwACAFYUAA==.Sathariel:BAAALgAECgIJAgAAAA==.',
Sc='Scalyboyos:BAABLgAECn8mAAMjAAkJcwwJGQBEAQAjAAgJwwsJGQBEAQAkAAEJxwf/kAA5AAAAAA==.Schmoop:BAACLgAFFH8OAAILAAYJKyFKCQDQAQALAAYJKyFKCQDQAQAuAAQKfzEABAsACQnHI1AJALkCAAsACAnyI1AJALkCABMABgmLGvcvAFABAB4AAwnkEtpaAJQAAAAA.',
Se='Seldaria:BAAALgAECgYJEAAAAA==.Senza:BAABLgAECn8iAAICAAgJ5wmpvQAMAQACAAgJ5wmpvQAMAQAAAA==.Senzyri:BAABLgAECn8mAAIBAAkJLxNHPgDoAQABAAkJLxNHPgDoAQAAAA==.Sephirath:BAAALgAECgIJAgAAAA==.Serote:BAAALgADCgcJBwAAAA==.Setmabone:BAAALgADCgkJCQABLgAECggJEwAOAAAAAA==.Sevilo:BAAALgADCgkJCwABLgAECgIJAgAOAAAAAA==.',
Sh='Shamagoth:BAAALgAECgYJBgAAAA==.Shambhala:BAAALgAECgYJEgAAAA==.Shoes:BAAALgAECgUJBwAAAA==.Shymyst:BAAALgAFFAEJAgABLgAFFAUJFwAGAEoSAA==.',
Si='Simic:BAABLgAECn85AAIPAAkJEBQtFgC4AQAPAAkJEBQtFgC4AQAAAA==.',
Sk='Skre:BAAALgAECgYJBgAAAA==.',
Sm='Smiddy:BAABLgAFFH8GAAQPAAMJfg/gNQBfAAAfAAIJnAeEIACEAAAPAAIJBRPgNQBfAAAcAAEJ3wbDEgFAAAAAAA==.Smokeace:BAAALgAECgEJAQAAAA==.',
Sn='Snowthistle:BAABLgAECn8WAAIXAAcJQgWzUwDAAAAXAAcJQgWzUwDAAAAAAA==.',
So='Sorle:BAAALgADCgYJCQABLgAECgkJLgAMANkUAA==.Soulnãris:BAAALgAECgcJCQAAAA==.',
Sp='Spin:BAABLgAFFH8JAAMUAAIJrRmrLgCNAAAUAAIJoxarLgCNAAAVAAEJIBewVgBAAAAAAA==.Spudpal:BAAALgADCgEJAQABLgAECgkJLAAeAMYhAA==.Spyro:BAAALgADCgUJBQAAAA==.',
Sq='Squirley:BAAALgAECgQJCAAAAA==.',
St='Starge:BAAALgAECgYJBgAAAA==.Stargefall:BAAALgAECgMJAwAAAA==.Static:BAAALgAECgYJBgAAAA==.Stonymahoney:BAABLgAECn89AAICAAkJwxoAJgBsAgACAAkJwxoAJgBsAgAAAA==.',
Su='Sudokoo:BAAALgADCgMJAwAAAA==.Sumorna:BAAALgAECgEJAQAAAA==.Suraisu:BAACLgAFFH8HAAIMAAMJ1Bw6LAADAQAMAAMJ1Bw6LAADAQAuAAQKfzYAAgwACQk/JDcDADkDAAwACQk/JDcDADkDAAAA.Suê:BAAALgADCgEJAQABLgADCgQJBAAOAAAAAA==.',
Sv='Sveela:BAACLgAFFH8TAAIWAAUJpiIjBwCFAQAWAAUJpiIjBwCFAQAuAAQKfyQAAhYACQlrIsEDAMoCABYACQlrIsEDAMoCAAAA.Sveelaa:BAABLgAECn8lAAIBAAgJax9dHgBwAgABAAgJax9dHgBwAgABLgAFFAUJEwAWAKYiAA==.Sveella:BAABLgAECn8UAAMcAAgJ/gtMmAA4AQAcAAcJ8gxMmAA4AQAPAAEJRgadZQAfAAABLgAFFAUJEwAWAKYiAA==.',
Sw='Swampjimmy:BAAALgAECgkJDAAAAA==.',
Sy='Sylrin:BAAALgADCgcJCgAAAA==.Synap:BAAALgADCgEJAQAAAA==.',
Ta='Tabchan:BAAALgAECgYJBwAAAA==.Tacocat:BAABLgAECn89AAMTAAkJmR76CADZAgATAAkJmR76CADZAgALAAEJNAUClQAlAAAAAA==.Tadeusz:BAAALgADCgEJAQAAAA==.Talras:BAAALgAECgMJAwAAAA==.',
Te='Temlock:BAABLgAECn8yAAIJAAkJFxgsMQBIAgAJAAkJFxgsMQBIAgAAAA==.Tempest:BAAALgAECgUJBQABLgAFFAMJDwAcAFYgAA==.Temtank:BAABLgAECn84AAIPAAkJkiLhAwD8AgAPAAkJkiLhAwD8AgABLgAECgkJMgAJABcYAA==.Testerosa:BAAALgADCgEJAQAAAA==.',
Th='Thalagosa:BAAALgADCgkJCQAAAA==.',
To='Tosi:BAAALgADCgMJAwAAAA==.',
Tr='Trak:BAABLgAECn8ZAAIkAAgJOQ0DQAApAQAkAAgJOQ0DQAApAQAAAA==.Trukarak:BAABLgAECn8rAAICAAkJVhSSSwDkAQACAAkJVhSSSwDkAQAAAA==.',
Tu='Tuvaquitamuu:BAAALgAECgEJAQAAAA==.',
Ur='Uraha:BAAALgADCgEJAQAAAA==.',
Va='Vaeegoldiir:BAAALgAECgEJAQAAAA==.Vaelithria:BAAALgAECgcJCAABLgAFFAYJFAAIAPEaAA==.Valenti:BAABLgAECn8kAAMnAAkJ0A9zFACIAQAnAAkJ0A9zFACIAQACAAEJ0AZSwAEjAAAAAA==.Valor:BAABLgAECn8kAAICAAcJhiEwUgDSAQACAAcJhiEwUgDSAQAAAA==.Vanity:BAAALgADCgMJAwAAAA==.',
Ve='Veliann:BAAALgAECgEJAQAAAA==.Vellatrix:BAAALgAECgQJBgAAAA==.Velynesti:BAAALgAECgQJBAAAAA==.',
Vi='Vipershot:BAAALgADCggJDwAAAA==.',
Wa='Warlode:BAAALgADCgkJDgAAAA==.',
We='Weewoo:BAAALgADCgcJCwAAAA==.Weliiam:BAAALgADCgYJBwAAAA==.',
Wi='Wildama:BAABLgAECn8sAAIGAAkJSBIsLgDtAQAGAAkJSBIsLgDtAQAAAA==.Wildtail:BAABLgAECn8YAAIBAAkJtQrpBADeAAABAAkJtQrpBADeAAAAAA==.Windseer:BAAALgAECgMJAwABLgAFFAQJFQABACEZAA==.',
Wr='Wrenwillow:BAAALgAECgIJAgAAAA==.',
Wu='Wumbo:BAAALgADCgEJAQAAAA==.',
Xa='Xarríøn:BAAALgADCgYJBgABLgAFFAMJCwACAB0ZAA==.',
Xh='Xhadowz:BAAALgAECgEJAgAAAA==.',
Xi='Xiao:BAABLgAECn82AAMFAAkJQBhuFwBeAgAFAAkJQBhuFwBeAgAUAAYJIAwVAgCgAAAAAA==.',
Xy='Xylaini:BAAALgAECgQJBAABLgAFFAEJAQAOAAAAAA==.',
Ya='Yahargul:BAABLgAECn8mAAILAAkJ9w+xIADAAQALAAkJ9w+xIADAAQAAAA==.',
Yo='Yogafarts:BAAALgAECgYJCAAAAA==.',
Yt='Yt:BAAALgADCgcJDAAAAA==.',
Za='Zanatilli:BAAALgAECgEJAQAAAA==.Zaterok:BAAALgAECgMJAwABLgAECgkJKwACAFYUAA==.',
Ze='Zeik:BAABLgAECn87AAMnAAkJSR/aAwDOAgAnAAkJSR/aAwDOAgACAAMJngpdWAFYAAAAAA==.Zephyrgosa:BAAALgADCgcJDgAAAA==.Zerase:BAAALgAECgQJCAAAAA==.',
Zu='Zucco:BAAALgAECgkJDgAAAA==.Zuufungo:BAAALgAECgUJBQABLgAECgkJLAAeAMYhAA==.',
['Zí']='Zíx:BAABLgAECn8oAAImAAkJSxI1GAB+AQAmAAkJSxI1GAB+AQAAAA==.',
['Àl']='Àlcàrà:BAABLgAECn8ZAAMPAAcJcA8pJwAaAQAPAAcJcA8pJwAaAQAcAAEJDgptIQEzAAAAAA==.',
['Ål']='Åldaren:BAAALgADCgQJBAAAAA==.',
['Ÿa']='Ÿamar:BAAALgAECgEJAQAAAA==.',
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
