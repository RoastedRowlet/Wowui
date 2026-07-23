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
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=46,date='2026-07-19',data={Ad='Adamonious:BAAALgAECgYJCwABLgAECgkJFgABAA8WAA==.Adaware:BAAALgAECgUJBgAAAA==.Addieeboy:BAAALgADCgEJAQAAAA==.Adellea:BAAALgAECgYJBwAAAA==.',
Ai='Aisha:BAAALgAECgEJAgAAAA==.',
Ak='Akumashi:BAAALgAECgEJAQAAAA==.',
Al='Alaponia:BAAALgAECgEJAgAAAA==.Alba:BAABLgAECn8vAAICAAgJkx2MNAAuAgACAAgJkx2MNAAuAgABLgAFFAUJFwABACEZAA==.Aletta:BAAALgAECgkJEQAAAA==.Allast:BAAALgADCgYJDQAAAA==.',
An='Andezard:BAABLgAECn9VAAMBAAkJchwPAwCdAgABAAkJchwPAwCdAgADAAcJ9hLfAQBSAQAAAA==.Angelys:BAABLgAECn8rAAIEAAgJKgtDCgDDAAAEAAgJKgtDCgDDAAAAAA==.',
Ap='Aphrobitey:BAAALgAECgMJBQAAAA==.',
Aq='Aquâ:BAAALgADCgkJEAABLgAECgkJMQAFAOIYAA==.',
Ar='Arathas:BAAALgADCgcJDAAAAA==.Arianes:BAAALgAECgcJDgAAAA==.Arrowin:BAAALgADCgYJBgAAAA==.Arturias:BAABLgAECn8cAAICAAgJ7hLUawCXAQACAAgJ7hLUawCXAQAAAA==.',
At='Athenaowl:BAABLgAECn8cAAIBAAgJBAvEFgAAAQABAAgJBAvEFgAAAQAAAA==.',
Au='Autofocus:BAABLgAECn8eAAIBAAgJPBqWQQDdAQABAAgJPBqWQQDdAQAAAA==.',
Aw='Aweyna:BAABLgAECn8aAAIGAAkJ0QxVUgBGAQAGAAkJ0QxVUgBGAQAAAA==.Awisha:BAAALgADCgUJBQAAAA==.',
Ay='Ayanoriko:BAACLgAFFH8QAAIHAAYJkxPgBAA1AQAHAAYJkxPgBAA1AQAuAAQKfywAAgcACQnkHx4DAIsCAAcACQnkHx4DAIsCAAAA.Ayasumi:BAAALgAECgIJAgAAAA==.',
Ba='Babaganoosh:BAAALgAECgUJCwAAAA==.Bacca:BAAALgADCgIJAgAAAA==.Baoyue:BAAALgAECggJCwABLgAFFAcJFQAIAEQZAA==.Barracuda:BAAALgAECgYJBgAAAA==.',
Be='Beans:BAABLgAFFH8PAAMJAAYJTReWPQBXAQAJAAYJTReWPQBXAQAKAAEJ4grMJgBIAAABLgAFFAcJFAALAM4iAA==.Benmonk:BAAALgAECgMJAwAAAA==.',
Bi='Bifur:BAAALgADCgkJDwAAAA==.Bigbuttflori:BAAALgAECgMJBQAAAA==.Bigpapapump:BAAALgAECgEJAQAAAA==.Bigstones:BAACLgAFFH8KAAMMAAQJBQQOPwCrAAAMAAMJRQQOPwCrAAANAAEJRANxIQAuAAAuAAQKfykAAwwACQmbD2otAJwBAAwACQmqDmotAJwBAA0ABQmjD0A8ANQAAAAA.',
Bl='Blacksavior:BAAALgAECgUJCAAAAA==.Blindbone:BAAALgAECgcJCQABLgAECggJEwAOAAAAAA==.Blisterine:BAAALgAECgYJBgAAAA==.Bluehydra:BAAALgADCgcJCAAAAA==.',
Bo='Bobbydigital:BAACLgAFFH8FAAIPAAIJqBefFwCBAAAPAAIJqBefFwCBAAAuAAQKfzoAAg8ACQm+G20KAGsCAA8ACQm+G20KAGsCAAAA.Bohd:BAAALgADCgIJAgAAAA==.Bolas:BAAALgAECggJEgAAAA==.Boneski:BAAALgAECgUJEAAAAA==.Booger:BAAALgAECgQJBAAAAA==.',
Br='Bracynn:BAABLgAECn8iAAIPAAkJOwZRNwC4AAAPAAkJOwZRNwC4AAAAAA==.Brenonna:BAAALgAECgQJCAABLgAECggJGwAPAI0NAA==.Brixx:BAAALgAECgMJAwAAAA==.Brudiclad:BAABLgAECn8uAAQKAAkJzhR8CgC3AQAKAAkJQBN8CgC3AQAJAAYJaQu2qQDvAAAQAAIJzxH2UQB4AAAAAA==.',
Bu='Budfight:BAAALgAECgUJDwAAAA==.Burnt:BAAALgAECgQJBAAAAA==.Butterfinger:BAAALgADCgQJBwAAAA==.Buxxor:BAAALgAECgcJBwAAAA==.',
Ca='Caimark:BAABLgAECn8yAAIRAAgJ6wYVKACHAAARAAgJ6wYVKACHAAAAAA==.Calahan:BAACLgAFFH8HAAICAAMJgBmzagDZAAACAAMJgBmzagDZAAAuAAQKfx4AAgIACAmxGmw0AFACAAIACAmxGmw0AFACAAAA.',
Ce='Cealia:BAAALgAECgcJEQAAAA==.',
Ch='Chakuneeai:BAAALgADCgYJBgAAAA==.Chancleta:BAAALgAECgYJDAAAAA==.Chaszy:BAAALgAECgUJCgABLgAECgkJJQAIAMQPAA==.Cherub:BAAALgADCgIJAgAAAA==.Chikostix:BAABLgAECn8tAAISAAgJ9wlEGABGAQASAAgJ9wlEGABGAQAAAA==.Christae:BAABLgAECn8nAAITAAkJNRn4EABcAgATAAkJNRn4EABcAgAAAA==.',
Ci='Cillicone:BAAALgAECgEJAgAAAA==.',
Cl='Clementînê:BAAALgAECgIJAgAAAA==.Clemêntine:BAAALgAECgYJDAAAAA==.Clydè:BAABLgAECn9SAAMUAAkJ6RaHFABJAgAUAAgJbheHFABJAgAVAAkJrhL9GwDFAQAAAA==.Cláncey:BAAALgAFFAEJAQAAAA==.',
Co='Coachhazzard:BAAALgAECgQJCwAAAA==.Cocytus:BAAALgADCgIJAgABLgAFFAIJBwAJADkaAA==.Colinferal:BAABLgAFFH8FAAIWAAEJRCAlPgAzAAAWAAEJRCAlPgAzAAAAAA==.Combatant:BAAALgADCgYJDAAAAA==.Compromise:BAAALgAECgYJCAAAAA==.Compromised:BAACLgAFFH8LAAIEAAMJ5xUjCgDuAAAEAAMJ5xUjCgDuAAAuAAQKfy8AAgQACQneG/4KAHcCAAQACQneG/4KAHcCAAAA.Connalious:BAAALgAECgEJAQAAAA==.Conquests:BAAALgAECgIJAgAAAA==.Corelack:BAACLgAFFH8RAAIWAAUJgxOKEwDnAAAWAAUJgxOKEwDnAAAuAAQKfxcAAxYACQm9DaslACYBABYACQmZDaslACYBABcABQmpBeJiAI8AAAAA.',
Cr='Crwth:BAAALgAECgUJBQAAAA==.',
Ct='Ctrlaltmagic:BAAALgAECgEJAgAAAA==.',
Cu='Cupis:BAAALgAECgQJBAAAAA==.Curendae:BAABLgAECn9EAAIBAAkJZhjtBQAOAgABAAkJZhjtBQAOAgAAAA==.',
Da='Dabaldzombie:BAACLgAFFH8TAAIRAAUJoxqPLAAEAQARAAUJoxqPLAAEAQAuAAQKfx0AAhEACQkSGTxMAFICABEACQkSGTxMAFICAAEuAAUUCAkVABgAxB8A.Daddyshocker:BAABLgAECn8WAAIZAAcJthRKLwCeAQAZAAcJthRKLwCeAQAAAA==.Danamy:BAAALgADCggJDQAAAA==.Daxzazi:BAABLgAECn8dAAMUAAgJQAROWACvAAAUAAgJQAROWACvAAAFAAUJrAQckwByAAAAAA==.',
De='Deadlee:BAAALgAECgMJAwAAAA==.Deadlights:BAAALgAECgUJBwAAAA==.Deadmanwlkin:BAAALgADCgIJAgAAAA==.Defias:BAAALgADCggJCAAAAA==.Delicious:BAEBLgAFFH8IAAIPAAUJAAtOJADMAAAPAAUJAAtOJADMAAABLgAFFAcJGQAaAGsXAA==.Demonhots:BAAALgAECgEJAQAAAA==.Despair:BAAALgAECgMJAwABLgAFFAUJFwABACEZAA==.',
Di='Dice:BAACLgAFFH8RAAIbAAUJAB4LBABdAQAbAAUJAB4LBABdAQAuAAQKfzAAAxsACQllIu8AABIDABsACQllIu8AABIDAAgAAQmeFHdYAEUAAAAA.Disturbd:BAACLgAFFH8OAAMcAAUJ5AqtgwABAQAcAAQJ5AqtgwABAQAPAAEJAAC/YAAAAAAuAAQKfxgAAxwACQn9DEVeAK0BABwACQn9DEVeAK0BAA8ABAmJAMY9AFsAAAAA.Disturbian:BAAALgAFFAIJAwABLgAFFAUJDgAcAOQKAA==.Dixierecht:BAABLgAECn8gAAIZAAgJbhsKGABIAgAZAAgJbhsKGABIAgAAAA==.',
Do='Docvader:BAAALgAECgQJCQAAAA==.Dodrop:BAAALgADCgYJBwAAAA==.',
Dr='Drunkenhealz:BAAALgAECgUJEAAAAA==.Drvargas:BAABLgAECn8WAAIQAAYJzhHdAwANAQAQAAYJzhHdAwANAQAAAA==.',
Du='Durzostern:BAEALgAECgQJBwABLgAFFAQJBwARADcPAA==.',
['Då']='Dårth:BAAALgAECgEJAQAAAA==.',
['Dè']='Dèrty:BAAALgAECgIJAgAAAA==.',
Ed='Educe:BAAALgAECgMJAwAAAA==.',
El='Elenestern:BAECLgAFFH8HAAIRAAQJNw/VPAC7AAARAAQJNw/VPAC7AAAuAAQKfzYAAhEACQmwEkVIAAICABEACQmwEkVIAAICAAAA.Elmo:BAABLgAECn8oAAMRAAkJHhZDPQAmAgARAAkJ0BVDPQAmAgAdAAEJwxVmFQA/AAAAAA==.',
Em='Emryssa:BAAALgAECgMJDAAAAA==.',
Er='Erimia:BAAALgAECgEJAQAAAA==.Erosis:BAACLgAFFH8OAAIRAAUJ/xt/SgBMAQARAAUJ/xt/SgBMAQAuAAQKfyQAAhEACAlsIwIvALYCABEACAlsIwIvALYCAAAA.',
Es='Esia:BAAALgADCgkJCQAAAA==.',
Ev='Evarg:BAAALgADCgcJDQAAAA==.',
Ex='Exghoulfiend:BAAALgAECgIJAgAAAA==.',
Ez='Ezaratren:BAAALgAECgUJCgABLgAFFAUJEQAWAIMTAA==.',
Fa='Fakêr:BAAALgADCgEJAQAAAA==.',
Fe='Fear:BAACLgAFFH8GAAIJAAMJMxu+HQANAQAJAAMJMxu+HQANAQAuAAQKfygAAwkACAmDIOgrAF8CAAkACAmDIOgrAF8CABAABQkbFk4bAHIBAAAA.Felcatalyist:BAABLgAECn8gAAMcAAkJABgcYwDKAQAcAAkJtBUcYwDKAQAPAAgJXA2iKAAQAQAAAA==.Felisaty:BAAALgAECgEJAQAAAA==.Fellisaty:BAABLgAECn8WAAIZAAgJfQ9rMgCMAQAZAAgJfQ9rMgCMAQAAAA==.Felysria:BAAALgAECgQJAgAAAA==.',
Fi='Fistitresk:BAAALgADCgQJBgABLgAECgkJFgAeAGofAA==.Fistofwayne:BAABLgAECn8cAAIVAAgJMBA1KABwAQAVAAgJMBA1KABwAQABLgAFFAYJIQAfAPoeAA==.',
Fr='Frizzalot:BAAALgAECgEJAwAAAA==.Frizzer:BAAALgAECgMJAwAAAA==.',
Ga='Gakopozy:BAABLgAECn8lAAIIAAkJxA8xAgDOAQAIAAkJxA8xAgDOAQAAAA==.Gambrinos:BAAALgADCgMJAwAAAA==.Gander:BAAALgADCgEJAQABLgAECgEJAQAOAAAAAA==.Gandermon:BAAALgAECgEJAQAAAA==.Garnath:BAAALgADCgYJBgAAAA==.',
Ge='Geg:BAABLgAFFH8FAAIcAAMJvBEhJwD7AAAcAAMJvBEhJwD7AAAAAA==.',
Gl='Glorrex:BAAALgADCgYJBgAAAA==.',
Go='Gongsho:BAAALgAECgQJBgAAAA==.',
Gr='Grapez:BAAALgAFFAIJAgABLgAFFAgJIwAPAOEbAA==.Grimlokke:BAAALgAECgIJAwABLgAFFAUJEQAWAIMTAA==.Grïmyst:BAAALgAECgEJAQABLgAFFAUJEQAWAIMTAA==.',
Gu='Guldán:BAABLgAECn8WAAIJAAYJxQi+FQCfAAAJAAYJxQi+FQCfAAAAAA==.',
Gw='Gwendilynne:BAAALgAECgIJAgAAAA==.Gwydre:BAACLgAFFH8TAAIPAAQJaCAgFABPAQAPAAQJaCAgFABPAQAuAAQKfxUAAg8ACAnqHvYNAC4CAA8ACAnqHvYNAC4CAAAA.',
Ha='Harbard:BAAALgADCgYJCwAAAA==.Havran:BAAALgAECgQJBAABLgAECgkJSAAWAAEbAA==.Havrin:BAABLgAECn9IAAQWAAkJARu/EADeAQAWAAkJaBi/EADeAQAgAAQJZBr8BgCyAAAGAAEJ/QvxHQAqAAAAAA==.',
He='Headshots:BAACLgAFFH8XAAMBAAUJIRkrPgAxAQABAAQJIRkrPgAxAQAhAAIJPgNVHAA2AAAuAAQKfy4AAgEACQmVH10UAJMCAAEACQmVH10UAJMCAAAA.Heartsong:BAAALgAECgEJAQAAAA==.Heavylode:BAAALgAECgUJDwAAAA==.Hexatar:BAAALgAECgQJBAAAAA==.',
Hk='Hkia:BAAALgAFFAMJAwAAAA==.',
Ho='Hoardkiller:BAAALgAECgQJAwABLgAFFAUJFQAhANQNAA==.Holmie:BAAALgADCgkJCgAAAA==.Honk:BAAALgAFFAIJAwAAAA==.Hoofsoflove:BAAALgADCgQJBAAAAA==.Hoogablop:BAABLgAFFH8KAAICAAcJZxeYJwBsAQACAAcJZxeYJwBsAQABLgAFFAcJFAALAM4iAA==.Hoogaplop:BAACLgAFFH8aAAMPAAUJkybbEwBSAQAcAAUJkyYEOQCKAQAPAAUJqB/bEwBSAQAuAAQKf0UAAw8ACQnDJEUFANcCABwACQm5IQMUAAMDAA8ACAl1JEUFANcCAAEuAAUUBwkUAAsAziIA.',
Hu='Huamulan:BAABLgAECn9sAAICAAkJTg+eCQCWAQACAAkJTg+eCQCWAQAAAA==.',
Ib='Ibc:BAAALgADCgcJDQABLgAFFAIJBwAcADoTAA==.Ibchilling:BAABLgAECn8pAAIRAAgJxBpCTwDuAQARAAgJxBpCTwDuAQABLgAFFAIJBwAcADoTAA==.Ibcorrupted:BAABLgAFFH8HAAIcAAIJOhM8zACWAAAcAAIJOhM8zACWAAAAAA==.',
Ic='Icarrus:BAACLgAFFH8SAAIFAAYJ+w+VKAAqAQAFAAYJ+w+VKAAqAQAuAAQKfy8AAwUACQnkHGUaAEUCAAUACQnkHGUaAEUCABQABQmTEF1NAM4AAAEuAAUUBQkNABwA7AwA.Icarus:BAAALgADCgEJAQABLgAFFAUJDQAcAOwMAA==.Iccarus:BAAALgAECgUJBQABLgAFFAUJDQAcAOwMAA==.Icebone:BAAALgAECgcJCgABLgAECggJEwAOAAAAAA==.',
Ig='Ignis:BAACLgAFFH8NAAIcAAUJ7AzjMQD9AAAcAAUJ7AzjMQD9AAAuAAQKfxYAAxwABgl5G4aEAFoBABwABgnzGYaEAFoBAB8AAQkRFnw3AD8AAAAA.',
Il='Illioch:BAAALgAECgEJAQAAAA==.',
Im='Imaway:BAAALgAECgEJAQAAAA==.',
In='Inesh:BAAALgADCgEJAQAAAA==.',
Ir='Irrizia:BAAALgADCgkJCgAAAA==.',
Is='Iseldra:BAAALgAECgEJAQAAAA==.',
['Iç']='Içyhot:BAAALgAECgEJBAABLgAECgcJEwAOAAAAAA==.',
Ja='Jackbfistn:BAAALgAECggJEwAAAA==.Jaskim:BAABLgAECn8hAAMcAAkJWw3yXwCpAQAcAAkJWw3yXwCpAQAfAAIJ2AWjNgBCAAAAAA==.',
Je='Jeses:BAAALgAECgUJCQABLgAFFAIJBQABAPcLAA==.',
Jo='Jolty:BAAALgAECgEJAQABLgAFFAYJGgAcAFEgAA==.Jooni:BAAALgADCggJDwAAAA==.Jordomon:BAABLgAECn8fAAMXAAcJDQfcTwDOAAAXAAcJAQfcTwDOAAAgAAMJ8gZOPwBfAAAAAA==.',
Jy='Jyundiel:BAAALgADCgYJBgABLgADCgYJBgAOAAAAAA==.',
['Jú']='Júliët:BAAALgAECgIJAgAAAA==.',
Ka='Kaazaama:BAAALgADCgYJBgAAAA==.Kahtonah:BAAALgADCgMJAwAAAA==.Kalessin:BAAALgADCgkJDgABLgAECgUJDwAOAAAAAA==.Kaltaan:BAABLgAECn8tAAQeAAkJxiFyBgAZAwAeAAkJxiFyBgAZAwATAAQJUh8jPABKAQALAAEJ4R07dQBWAAAAAA==.Karasan:BAABLgAECn8lAAIBAAkJ0BeHMAAaAgABAAkJ0BeHMAAaAgAAAA==.Karenas:BAACLgAFFH8OAAIRAAQJahq5HgBTAQARAAQJahq5HgBTAQAuAAQKfyYAAxEACQnoIHIQAPgCABEACQnoIHIQAPgCAB0AAgnhCpkWAGYAAAAA.Karr:BAABLgAECn8XAAICAAgJNAcWtgAWAQACAAgJNAcWtgAWAQAAAA==.Kataraara:BAACLgAFFH8HAAIVAAQJRiA0GABgAQAVAAQJRiA0GABgAQAuAAQKfx0AAxUACAkqJd4EADwDABUACAkqJd4EADwDAAUAAQkxI6ggAGMAAAEuAAUUCAkiAA8AjCUA.Katbeans:BAABLgAECn9AAAQFAAkJtR1UAQDSAgAFAAkJtR1UAQDSAgAVAAUJIQ6RYgC4AAAUAAEJJhYflQA7AAAAAA==.Kathrynne:BAAALgAECgUJCQAAAA==.Katmai:BAAALgADCgEJAQAAAA==.Katrielle:BAAALgAECgUJBQAAAA==.Kaykoh:BAABLgAFFH8IAAIcAAIJHSAdSwC2AAAcAAIJHSAdSwC2AAAAAA==.',
Ke='Kelicemoon:BAABLgAECn8oAAMJAAkJZgoPYwB5AQAJAAkJSQkPYwB5AQAQAAcJIQd5MQBYAAAAAA==.Kemono:BAAALgADCgYJBgAAAA==.',
Kh='Khaliope:BAABLgAECn82AAIiAAkJpQ2UdwAyAQAiAAkJpQ2UdwAyAQAAAA==.Khat:BAAALgADCgkJCQAAAA==.',
Ki='Kiara:BAACLgAFFH8cAAMjAAYJ8xZWEgBuAQAjAAUJVxlWEgBuAQAkAAIJWhayRQCwAAAuAAQKfy0AAyMACQlpH1QIALUCACMACQlpH1QIALUCACQABAm9E/tLAP0AAAAA.Kiryu:BAAALgAECgUJBQAAAA==.',
Ko='Korzari:BAAALgADCgEJAQAAAA==.Koven:BAAALgADCgcJCQAAAA==.',
Kr='Krogers:BAAALgAECgcJEQABLgAECgkJEQAOAAAAAA==.',
Ku='Kumojo:BAAALgAECgkJAgAAAA==.',
Ky='Kyndlearya:BAAALgAECgEJAQAAAA==.',
['Kû']='Kûrr:BAAALgAECgEJAQABLgAFFAEJAQAOAAAAAA==.',
La='Lahrnaon:BAAALgAFFAIJAgAAAA==.Laxeron:BAABLgAECn8jAAIMAAkJUyRXBQAMAwAMAAkJUyRXBQAMAwAAAA==.',
Le='Leighty:BAAALgADCgUJBQAAAA==.Leotherassy:BAAALgAECgYJCwAAAA==.Leychron:BAAALgAECgEJAQAAAA==.',
Li='Lightsworn:BAAALgAECgEJAQAAAA==.Lilin:BAAALgAECgYJBwAAAA==.',
Lo='Longboneman:BAAALgAECgIJAgABLgAECggJEwAOAAAAAA==.Lorquendus:BAAALgAECgYJBgAAAA==.Lotiel:BAAALgAECgMJCQABLgAFFAUJFwAGAEoSAA==.',
Lu='Lucrecia:BAABLgAECn8WAAMiAAYJbB0oUgCuAQAiAAUJ2iEoUgCuAQAlAAEJswudLAAuAAAAAA==.Lumbersnack:BAAALgAECgEJAQAAAA==.',
Ly='Lyat:BAAALgAFFAIJAgAAAA==.Lymara:BAAALgADCgcJCAAAAA==.Lynthirae:BAAALgADCgcJDAAAAA==.',
['Lø']='Lørðzêdd:BAAALgAECgQJEgAAAA==.',
Ma='Madness:BAAALgAECgIJAgAAAA==.Madpearl:BAAALgAECgMJAwAAAA==.Mahkaidook:BAAALgADCgYJBgAAAA==.Mal:BAAALgADCgkJCQABLgAFFAMJBAAOAAAAAA==.Manyace:BAAALgAECgQJBgAAAA==.',
Mc='Mcbodhran:BAABLgAECn8iAAICAAkJTRFseAB9AQACAAkJTRFseAB9AQAAAA==.Mcfeast:BAABLgAECn8ZAAILAAgJ+A/AKwB2AQALAAgJ+A/AKwB2AQAAAA==.',
Me='Medra:BAABLgAECn8uAAQMAAkJ2RSoHwDyAQAMAAkJ2RSoHwDyAQAmAAQJEgP9QABsAAANAAIJ2wYHbQBHAAAAAA==.Melidoria:BAAALgADCgEJAQABLgAECgkJSQAkAL0cAA==.Meowdi:BAAALgAECgUJDgAAAA==.Merogoth:BAAALgADCgUJBwAAAA==.Mestrois:BAACLgAFFH8HAAIRAAIJRwKBUwBjAAARAAIJRwKBUwBjAAAuAAQKf0cAAhEACAlWCiMbANMAABEACAlWCiMbANMAAAAA.',
Mi='Minibone:BAAALgAECgMJAwABLgAECggJEwAOAAAAAA==.Mixr:BAAALgAECgEJAQAAAA==.',
Mo='Monana:BAAALgAECgUJCQAAAA==.Moonscreamer:BAAALgAECgEJAQAAAA==.Morar:BAAALgAECgUJDAAAAA==.Morul:BAAALgAECgQJBAAAAA==.',
Ms='Msprettÿp:BAAALgADCgIJAgAAAA==.',
Mu='Murimlinn:BAAALgADCgMJAwAAAA==.Mustafa:BAAALgAECgUJCAAAAA==.',
Na='Nadjá:BAAALgAECgYJBgAAAA==.Nanija:BAAALgAECgUJDwAAAA==.Narushi:BAAALgAECgQJBQAAAA==.',
Ne='Nezrin:BAAALgADCgQJBwAAAA==.',
Ni='Nightcat:BAAALgAECgUJCAAAAA==.Nitebäne:BAAALgAECgkJCgAAAA==.Nitesbane:BAAALgADCgYJBgABLgAECgkJHQACACwgAA==.Nitesbåne:BAAALgADCgcJBwAAAA==.Niteshiftah:BAAALgADCgcJBwAAAA==.Nitestorm:BAAALgAECgcJCQAAAA==.Nivaniraa:BAAALgAECgEJAgAAAA==.Nixie:BAABLgAECn8vAAMGAAkJjAaOYgANAQAGAAkJjAaOYgANAQAXAAkJ8gSuRAD5AAAAAA==.',
No='Nobonesjones:BAACLgAFFH8LAAIEAAUJlQacBgDfAAAEAAUJlQacBgDfAAAuAAQKfxsAAgQACQlPFjMeAM4BAAQACQlPFjMeAM4BAAAA.',
Og='Oguricap:BAAALgADCgcJBwAAAA==.Ogwarshock:BAACLgAFFH8QAAQJAAYJNhydTgAoAQAJAAQJHRadTgAoAQAQAAIJgB4BCgBiAAAKAAEJAAC8MQAAAAAuAAQKfyQAAwkACQk0IkIhAF4CAAkABwm0IUIhAF4CABAABQm9HzkaAHsBAAAA.',
Ok='Okkotsu:BAAALgAECgIJAwABLgAFFAIJAgAOAAAAAA==.Okote:BAAALgAECgMJBAAAAA==.',
Ol='Oliiver:BAABLgAECn9OAAIBAAkJrCEMAgDpAgABAAkJrCEMAgDpAgAAAA==.',
Om='Omni:BAAALgAECgEJAQABLgAFFAUJEQAWAIMTAA==.Omnivore:BAAALgADCgcJCAAAAA==.Omën:BAAALgAECgQJBAABLgAECgQJCAAOAAAAAA==.',
On='Oniichan:BAAALgAECgQJBQAAAA==.',
Or='Orbeez:BAABLgAECn88AAMiAAkJJCGmAQCVAgAiAAkJJCGmAQCVAgAlAAcJjhPtAQBqAQAAAA==.',
Pa='Pack:BAAALgAECgcJAQAAAA==.Paladlin:BAAALgADCgYJCwAAAA==.Panaceus:BAABLgAECn86AAIjAAkJ1yLWAQBsAwAjAAkJ1yLWAQBsAwAAAA==.Paragon:BAAALgADCgkJDQABLgAFFAMJDwAcAFYgAA==.Patron:BAAALgAECgIJAgAAAA==.',
Pe='Pepe:BAAALgAECgUJCQAAAA==.Perennial:BAAALgAECgYJCQAAAA==.Perpetrator:BAAALgAECgYJBwAAAA==.',
Ph='Phreeq:BAEALgAECgYJDgABLgAECgkJNAAZAJkWAA==.Phrequency:BAEBLgAECn80AAMZAAkJmRYsJwDRAQAZAAgJrhQsJwDRAQACAAkJlhG4cACNAQAAAA==.',
Pi='Piety:BAAALgADCgIJAgABLgAECgYJBgAOAAAAAA==.Pig:BAAALgAECgEJAQABLgAFFAcJFAALAM4iAA==.',
Pl='Plazma:BAAALgAECgEJAQAAAA==.Plazmafury:BAABLgAFFH8KAAMMAAYJ5g9UEgB1AQAMAAYJZw5UEgB1AQANAAEJyA02QgBDAAAAAA==.Plazmaglaive:BAAALgAFFAEJAQAAAA==.Plumsham:BAAALgADCgQJBAAAAA==.',
Po='Poisonóus:BAACLgAFFH8QAAIPAAYJMRp+GgATAQAPAAYJMRp+GgATAQAuAAQKfzMAAg8ACQmeHVcKAGwCAA8ACQmeHVcKAGwCAAAA.Polyxo:BAABLgAECn8ZAAICAAgJIxDsCwBtAQACAAgJIxDsCwBtAQAAAA==.',
Pr='Profang:BAAALgAECgQJBAAAAA==.',
Py='Pyrelic:BAABLgAFFH8aAAIUAAYJ2hdfEgAqAQAUAAYJ2hdfEgAqAQAAAA==.Pyroela:BAAALgAECgUJCgABLgAFFAQJEwAPAGggAA==.',
['Pö']='Pöncho:BAAALgAECgEJAQAAAA==.',
Qa='Qayllera:BAABLgAECn8bAAIRAAYJqg33FwDsAAARAAYJqg33FwDsAAAAAA==.',
Qe='Qelcie:BAAALgAECgQJBQAAAA==.',
Qu='Quellerodra:BAAALgADCgkJCQAAAA==.Quixotic:BAAALgADCgUJBgAAAA==.Quizet:BAAALgADCgYJCgAAAA==.',
Ra='Radicchio:BAAALgAECgUJBgAAAA==.Radkeem:BAABLgAECn8YAAIPAAkJiB0ZCQCBAgAPAAkJiB0ZCQCBAgAAAA==.Raf:BAAALgAECgYJBwAAAA==.Raizo:BAAALgAECgYJCAAAAA==.Rakeem:BAAALgAECgcJEAABLgAECgkJGAAPAIgdAA==.Ralivan:BAAALgADCgEJAgAAAA==.Ravenhawk:BAAALgADCgQJCAAAAA==.Razorknight:BAAALgAECgEJAQAAAA==.',
Re='Redtoxin:BAAALgAECgUJDgAAAA==.Reilley:BAACLgAFFH8cAAIcAAYJ3hUdPgB8AQAcAAYJ3hUdPgB8AQAuAAQKfzMAAhwACQnxIJYNAAADABwACQnxIJYNAAADAAAA.Reilleÿ:BAAALgAECgQJBAABLgAFFAYJHAAcAN4VAA==.Reko:BAAALgAECggJEwAAAA==.Remorsa:BAABLgAECn8XAAMCAAcJxBvHTwDZAQACAAcJxBvHTwDZAQAZAAQJJRXOVwAcAQAAAA==.Renni:BAABLgAECn8sAAIJAAkJxBa7LQAiAgAJAAkJxBa7LQAiAgABLgAECgkJJAAVAKIZAA==.Reshath:BAAALgADCgEJAQAAAA==.Reznor:BAABLgAECn8kAAIZAAkJLBbDJwDtAQAZAAkJLBbDJwDtAQAAAA==.',
Ri='Rinela:BAAALgADCgcJBwAAAA==.Ripli:BAAALgAECgUJBQABLgAFFAUJFwABACEZAA==.Riselle:BAAALgAFFAEJAgAAAA==.',
Ro='Rosealia:BAABLgAECn8ZAAIBAAkJkwYNogD+AAABAAkJkwYNogD+AAAAAA==.',
Ru='Rubiesue:BAAALgAECgEJAgAAAA==.Runeight:BAAALgADCgIJAQAAAA==.',
Ry='Ryder:BAAALgAECgIJBAAAAA==.',
['Ró']='Rómëo:BAACLgAFFH8VAAIIAAcJRBkUDgCyAQAIAAcJRBkUDgCyAQAuAAQKf1cAAggACQloJlcAAJYDAAgACQloJlcAAJYDAAAA.',
Sa='Sabbatical:BAAALgADCgEJAQAAAA==.Sacon:BAAALgAECgEJAQABLgAFFAMJBAAOAAAAAA==.Sahmeah:BAAALgAECgYJCQAAAA==.Saintzan:BAAALgAECgkJEQAAAA==.Salivan:BAAALgAECgUJCgAAAA==.San:BAAALgAECgYJDwAAAA==.Sanketsu:BAAALgADCgYJCwABLgAECgkJLgACAFkWAA==.Sardonyx:BAAALgAECgMJAwAAAA==.Sathariel:BAAALgAECgIJAgAAAA==.',
Sc='Scalyboyos:BAABLgAECn8mAAMjAAkJcwwJGQBEAQAjAAgJwwsJGQBEAQAkAAEJxwcBkQA5AAAAAA==.Schmoop:BAACLgAFFH8UAAMLAAcJziILBQCwAQALAAcJziILBQCwAQATAAEJoxL0FgBVAAAuAAQKfzIABAsACQnHI1AJALkCAAsACAnyI1AJALkCABMABgmLGvwvAFABAB4AAwnkEttaAJQAAAAA.',
Se='Seldaria:BAAALgAECgYJEAAAAA==.Sellari:BAAALgAECgQJCwAAAA==.Senza:BAABLgAECn8nAAICAAkJEwujHQDCAAACAAkJEwujHQDCAAAAAA==.Senzyri:BAABLgAECn8mAAIBAAkJLxNFPgDoAQABAAkJLxNFPgDoAQAAAA==.Sephirath:BAAALgAECgIJAgAAAA==.Serote:BAAALgADCgcJBwAAAA==.Setmabone:BAAALgADCgkJCQABLgAECggJEwAOAAAAAA==.Sevilo:BAAALgADCgkJCwABLgAECgIJAgAOAAAAAA==.',
Sh='Shamagoth:BAAALgAECgYJBgAAAA==.Shambhala:BAAALgAECgYJEwAAAA==.Shockwàve:BAAALgAECgEJAQAAAA==.Shoes:BAAALgAECgUJBwAAAA==.Shymyst:BAAALgAFFAEJAgABLgAFFAUJFwAGAEoSAA==.',
Si='Simic:BAABLgAECn9OAAIPAAkJEBZ9AgDsAQAPAAkJEBZ9AgDsAQAAAA==.',
Sk='Skre:BAAALgAECgYJBgAAAA==.',
Sl='Sloppy:BAAALgAFFAEJBAABLgAFFAcJFAALAM4iAA==.',
Sm='Smiddy:BAACLgAFFH8GAAQPAAMJfg/fNQBfAAAfAAIJnAeCIACEAAAPAAIJBRPfNQBfAAAcAAEJ3wbAEgFAAAAuAAQKfxUAAw8ACQnPE0ISAOcBAA8ACQnPE0ISAOcBABwABQlOB10pAXcAAAAA.Smokeace:BAAALgAECgEJAQAAAA==.',
Sn='Snowthistle:BAABLgAECn8YAAIXAAcJUwe6UwDAAAAXAAcJUwe6UwDAAAAAAA==.',
So='Sorle:BAAALgADCgYJCQABLgAECgkJLgAMANkUAA==.Soulnãris:BAAALgAECgcJCQAAAA==.',
Sp='Spin:BAABLgAFFH8JAAMUAAIJrRmqLgCNAAAUAAIJoxaqLgCNAAAVAAEJIBeqVgBAAAAAAA==.Spudpal:BAAALgADCgEJAQABLgAECgkJLQAeAMYhAA==.Spyro:BAAALgADCgUJBQAAAA==.',
Sq='Squirley:BAAALgAECgQJCAAAAA==.',
St='Starge:BAAALgAECgYJBgAAAA==.Stargefall:BAAALgAECgMJAwAAAA==.Static:BAAALgAECgYJBgAAAA==.Stonymahoney:BAACLgAFFH8JAAICAAQJ8BZZFwAlAQACAAQJ8BZZFwAlAQAuAAQKf0MAAgIACQnHIeUGAN4BAAIACQnHIeUGAN4BAAAA.',
Su='Sudokoo:BAAALgADCgMJAwAAAA==.Sumorna:BAAALgAECgEJAQAAAA==.Suraisu:BAACLgAFFH8HAAIMAAMJ1Bw2LAADAQAMAAMJ1Bw2LAADAQAuAAQKfzgAAwwACQk/JDcDADkDAAwACQk/JDcDADkDACYAAgkTE2IJAIgAAAAA.Suê:BAAALgADCgEJAQABLgADCgQJBAAOAAAAAA==.',
Sv='Sveela:BAACLgAFFH8UAAIWAAYJuCEjBwCFAQAWAAYJuCEjBwCFAQAuAAQKfyQAAhYACQlrIsEDAMoCABYACQlrIsEDAMoCAAAA.Sveelaa:BAABLgAECn8lAAIBAAgJax9cHgBwAgABAAgJax9cHgBwAgABLgAFFAYJFAAWALghAA==.Sveella:BAABLgAECn8UAAMcAAgJ/gtOmAA4AQAcAAcJ8gxOmAA4AQAPAAEJRgadZQAfAAABLgAFFAYJFAAWALghAA==.',
Sw='Swampjimmy:BAAALgAECgkJDAAAAA==.',
Sy='Sylrin:BAAALgADCgcJCgAAAA==.Synap:BAAALgADCgEJAQAAAA==.',
Ta='Tabchan:BAAALgAECgYJBwAAAA==.Tacocat:BAABLgAECn89AAMTAAkJmR77CADZAgATAAkJmR77CADZAgALAAEJNAUKlQAlAAAAAA==.Tadeusz:BAAALgADCgIJAgAAAA==.Tahlonia:BAAALgAECgMJAwAAAA==.Talras:BAAALgAECgMJAwAAAA==.',
Te='Temlock:BAABLgAECn83AAIJAAkJPxklCABbAQAJAAkJPxklCABbAQAAAA==.Tempest:BAAALgAECgUJBQABLgAFFAMJDwAcAFYgAA==.Temtank:BAABLgAECn84AAIPAAkJkiLfAwD8AgAPAAkJkiLfAwD8AgABLgAECgkJNwAJAD8ZAA==.Testerosa:BAAALgADCgcJBwAAAA==.',
Th='Thalagosa:BAAALgADCgkJCQAAAA==.',
To='Tosi:BAAALgADCgMJAwAAAA==.',
Tr='Trak:BAABLgAECn8ZAAIkAAgJOQ0FQAApAQAkAAgJOQ0FQAApAQAAAA==.Trukarak:BAABLgAECn8uAAICAAkJWRaOSwDkAQACAAkJWRaOSwDkAQAAAA==.',
Tu='Tuvaquitamuu:BAAALgAECgEJAQAAAA==.',
Ur='Uraha:BAAALgADCgEJAQAAAA==.',
Va='Vaeegoldiir:BAAALgAECgEJAQAAAA==.Vaelithria:BAAALgAECgcJCAABLgAFFAcJFQAIAEQZAA==.Valenti:BAABLgAECn8kAAMnAAkJ0A9zFACIAQAnAAkJ0A9zFACIAQACAAEJ0AZVwAEjAAAAAA==.Valor:BAABLgAECn8kAAICAAcJhiEtUgDSAQACAAcJhiEtUgDSAQAAAA==.Vanity:BAAALgADCgMJAwAAAA==.',
Ve='Veliann:BAAALgAECgEJAQAAAA==.Vellatrix:BAAALgAECgQJBgAAAA==.Velynesti:BAAALgAECgQJBAAAAA==.',
Vi='Vipershot:BAAALgADCggJDwAAAA==.',
Wa='Warlode:BAAALgADCgkJDgAAAA==.',
We='Weewoo:BAAALgAECgEJAQAAAA==.Weliiam:BAAALgADCgYJBwAAAA==.',
Wi='Wildama:BAABLgAECn9CAAIGAAkJ7xToAgAQAgAGAAkJ7xToAgAQAgAAAA==.Wildtail:BAABLgAECn8YAAIBAAkJkgo3YQCEAQABAAkJkgo3YQCEAQAAAA==.Windseer:BAAALgAECgcJDwABLgAFFAUJFwABACEZAA==.',
Wr='Wrenwillow:BAAALgAECgIJAgAAAA==.',
Wu='Wumbo:BAAALgADCgEJAQAAAA==.',
Xa='Xarríøn:BAAALgADCgYJBgAAAA==.',
Xh='Xhadowz:BAAALgAFFAEJAQAAAA==.',
Xi='Xiao:BAABLgAECn9JAAMFAAkJiBnJAgA5AgAFAAkJiBnJAgA5AgAUAAgJtBEUAwCRAQAAAA==.Xiaolongbao:BAAALgADCgcJDQAAAA==.',
Xy='Xylaini:BAAALgAECgQJBAABLgAFFAEJAQAOAAAAAA==.',
Ya='Yahargul:BAABLgAECn8mAAILAAkJ9w+yIADAAQALAAkJ9w+yIADAAQAAAA==.',
Yo='Yogafarts:BAAALgAECgYJCAAAAA==.',
Yt='Yt:BAAALgADCgcJDAAAAA==.',
Za='Zanatilli:BAAALgAECgQJCAAAAA==.Zaterok:BAAALgAECgMJAwABLgAECgkJLgACAFkWAA==.',
Ze='Zeik:BAABLgAECn9TAAMnAAkJNyJfAAAFAwAnAAkJNyJfAAAFAwACAAMJngpiWAFYAAAAAA==.Zephyrgosa:BAAALgADCgcJDgAAAA==.Zerase:BAAALgAECgUJDgAAAA==.',
Zo='Zoomin:BAAALgAECgIJAgAAAA==.',
Zu='Zucco:BAAALgAECgkJDgAAAA==.Zuufungo:BAAALgAECgUJBQABLgAECgkJLQAeAMYhAA==.',
['Zí']='Zíx:BAABLgAECn8oAAImAAkJSxI0GAB+AQAmAAkJSxI0GAB+AQAAAA==.',
['Àl']='Àlcàrà:BAABLgAECn8bAAMPAAgJjQ0rJwAbAQAPAAgJjQ0rJwAbAQAcAAEJDgptIQEzAAAAAA==.',
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
