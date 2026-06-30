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

local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Unknown-Unknown','Hunter-Marksmanship','DemonHunter-Havoc','Monk-Mistweaver','Druid-Restoration','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Warrior-Fury','Warrior-Arms','DeathKnight-Blood','Warlock-Destruction','Mage-Frost','Shaman-Enhancement','Priest-Holy','Monk-Windwalker','Monk-Brewmaster','Druid-Guardian','Druid-Balance','Shaman-Restoration','Paladin-Holy','Shaman-Elemental','Rogue-Outlaw','DeathKnight-Unholy','Mage-Arcane','Priest-Discipline','DeathKnight-Frost','Druid-Feral','Hunter-Survival','DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Vengeance','Warrior-Protection','Paladin-Protection',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=46,date='2026-06-27',data={Ad='Adamonious:BAAALgAECgYJCwABLgAECgkJFgABAA8WAA==.Adaware:BAAALgAECgUJBgAAAA==.Addieeboy:BAAALgADCgEJAQAAAA==.Adellea:BAAALgAECgYJBwAAAA==.',
Ai='Aisha:BAAALgAECgEJAgAAAA==.',
Ak='Akumashi:BAAALgADCgYJBgAAAA==.',
Al='Alaponia:BAAALgAECgEJAgAAAA==.Alba:BAABLgAECn8vAAICAAgJkx2MNAAuAgACAAgJkx2MNAAuAgABLgAFFAQJFQABACEZAA==.Aletta:BAAALgAECgcJDQABLgAECgcJEQADAAAAAA==.Allast:BAAALgADCgYJDQAAAA==.',
An='Andezard:BAABLgAECn9EAAMBAAkJ1xi+KQA3AgABAAkJuhi+KQA3AgAEAAQJGBRwAQD0AAAAAA==.Angelys:BAABLgAECn8kAAIFAAgJLwjILgAOAQAFAAgJLwjILgAOAQAAAA==.',
Ap='Aphrobitey:BAAALgAECgIJAgAAAA==.',
Aq='Aquâ:BAAALgADCgkJEAABLgAECgkJMQAGAOIYAA==.',
Ar='Arathas:BAAALgADCgcJDAAAAA==.Arianes:BAAALgAECgcJDgAAAA==.Arrowin:BAAALgADCgYJBgAAAA==.Arturias:BAABLgAECn8cAAICAAgJ7hLUawCXAQACAAgJ7hLUawCXAQAAAA==.',
At='Athenaowl:BAABLgAECn8cAAIBAAgJBAsHCgAbAQABAAgJBAsHCgAbAQAAAA==.',
Au='Autofocus:BAABLgAECn8eAAIBAAgJPBqWQQDdAQABAAgJPBqWQQDdAQAAAA==.',
Aw='Aweyna:BAABLgAECn8aAAIHAAkJ0QxVUgBGAQAHAAkJ0QxVUgBGAQAAAA==.Awisha:BAAALgADCgUJBQAAAA==.',
Ay='Ayanoriko:BAACLgAFFH8PAAIIAAUJ7hTgBAA1AQAIAAUJ7hTgBAA1AQAuAAQKfywAAggACQnkHx4DAIsCAAgACQnkHx4DAIsCAAAA.Ayasumi:BAAALgAECgIJAgAAAA==.',
Ba='Babaganoosh:BAAALgAECgUJCwAAAA==.Bacca:BAAALgADCgIJAgAAAA==.Baoyue:BAAALgAECggJCwABLgAFFAcJFQAJAGAZAA==.Barracuda:BAAALgAECgYJBgAAAA==.',
Be='Beans:BAABLgAFFH8OAAMKAAUJFRuWPQBXAQAKAAUJFRuWPQBXAQALAAEJ4grMJgBIAAABLgAFFAcJDwAMAJYhAA==.Benmonk:BAAALgAECgMJAwAAAA==.',
Bi='Bifur:BAAALgADCgkJDwAAAA==.Bigbuttflori:BAAALgAECgMJBQAAAA==.Bigpapapump:BAAALgAECgEJAQAAAA==.Bigstones:BAACLgAFFH8JAAINAAMJRQQOPwCrAAANAAMJRQQOPwCrAAAuAAQKfykAAw0ACQmbD2otAJwBAA0ACQmqDmotAJwBAA4ABQmjD0A8ANQAAAAA.',
Bl='Blacksavior:BAAALgAECgQJBAAAAA==.Blindbone:BAAALgAECgcJCQABLgAECggJEwADAAAAAA==.Blisterine:BAAALgAECgYJBgAAAA==.Bluehydra:BAAALgADCgcJCAAAAA==.',
Bo='Bobbydigital:BAABLgAECn86AAIPAAkJvhttCgBrAgAPAAkJvhttCgBrAgAAAA==.Bohd:BAAALgADCgIJAgAAAA==.Bolas:BAAALgAECgYJCQAAAA==.Boneski:BAAALgAECgUJEAAAAA==.Booger:BAAALgAECgQJBAAAAA==.',
Br='Bracynn:BAABLgAECn8hAAIPAAgJ7QZRNwC4AAAPAAgJ7QZRNwC4AAAAAA==.Brixx:BAAALgAECgMJAwAAAA==.Brudiclad:BAABLgAECn8uAAQLAAkJzxR8CgC3AQALAAkJQRN8CgC3AQAKAAYJaQu2qQDvAAAQAAIJzxH2UQB4AAAAAA==.',
Bu='Budfight:BAAALgAECgQJCwAAAA==.Burnt:BAAALgAECgQJBAAAAA==.Butterfinger:BAAALgADCgQJBwAAAA==.Buxxor:BAAALgAECgcJBwAAAA==.',
Ca='Caimark:BAABLgAECn8vAAIRAAgJLAWxxwD+AAARAAgJLAWxxwD+AAAAAA==.Calahan:BAACLgAFFH8HAAICAAMJgBmzagDZAAACAAMJgBmzagDZAAAuAAQKfx4AAgIACAmxGmw0AFACAAIACAmxGmw0AFACAAAA.',
Ce='Cealia:BAAALgAECgYJBgAAAA==.',
Ch='Chakuneeai:BAAALgADCgYJBgAAAA==.Chancleta:BAAALgAECgYJDAAAAA==.Cherub:BAAALgADCgIJAgAAAA==.Chikostix:BAABLgAECn8tAAISAAgJ9wlEGABGAQASAAgJ9wlEGABGAQAAAA==.Christae:BAABLgAECn8nAAITAAkJNRn4EABcAgATAAkJNRn4EABcAgAAAA==.',
Ci='Cillicone:BAAALgAECgEJAgAAAA==.',
Cl='Clementînê:BAAALgAECgIJAgAAAA==.Clemêntine:BAAALgAECgYJDAAAAA==.Clydè:BAABLgAECn9SAAMUAAkJ6RaHFABJAgAUAAgJbheHFABJAgAVAAkJrhL9GwDFAQAAAA==.Cláncey:BAAALgAFFAEJAQAAAA==.',
Co='Coachhazzard:BAAALgAECgQJCwAAAA==.Cocytus:BAAALgADCgIJAgABLgAFFAIJBwAKADkaAA==.Colinferal:BAABLgAFFH8FAAIWAAEJRCAlPgAzAAAWAAEJRCAlPgAzAAAAAA==.Combatant:BAAALgADCgYJDAAAAA==.Compromise:BAAALgAECgYJCAAAAA==.Compromised:BAACLgAFFH8GAAIFAAMJ1A6pGwDFAAAFAAMJ1A6pGwDFAAAuAAQKfy8AAgUACQneG/4KAHcCAAUACQneG/4KAHcCAAAA.Connalious:BAAALgAECgEJAQAAAA==.Conquests:BAAALgAECgIJAgAAAA==.Corelack:BAACLgAFFH8OAAIWAAUJgxOKEwDnAAAWAAUJgxOKEwDnAAAuAAQKfxcAAxYACQm9DaslACYBABYACQmZDaslACYBABcABQmpBeJiAI8AAAAA.',
Cr='Crwth:BAAALgAECgUJBQAAAA==.',
Ct='Ctrlaltmagic:BAAALgAECgEJAgAAAA==.',
Cu='Cupis:BAAALgAECgQJBAAAAA==.Curendae:BAABLgAECn84AAIBAAkJ0BedBQCBAQABAAkJ0BedBQCBAQAAAA==.',
Da='Dabaldzombie:BAACLgAFFH8TAAIRAAUJoxqPLAAEAQARAAUJoxqPLAAEAQAuAAQKfx0AAhEACQkSGTxMAFICABEACQkSGTxMAFICAAEuAAUUBwkUABgAGiAA.Daddyshocker:BAABLgAECn8WAAIZAAcJthRKLwCeAQAZAAcJthRKLwCeAQAAAA==.Danamy:BAAALgADCggJDQAAAA==.Daxzazi:BAABLgAECn8cAAMUAAcJ9gNOWACvAAAUAAcJ9gNOWACvAAAGAAUJrAQckwByAAAAAA==.',
De='Deadlee:BAAALgAECgMJAwAAAA==.Deadlights:BAAALgAECgIJAgAAAA==.Deadmanwlkin:BAAALgADCgIJAgAAAA==.Defias:BAAALgADCggJCAAAAA==.Delicious:BAEBLgAFFH8IAAIPAAUJAAtOJADMAAAPAAUJAAtOJADMAAABLgAFFAcJEwAaABEVAA==.Despair:BAAALgADCggJDgABLgAFFAQJFQABACEZAA==.',
Di='Dice:BAACLgAFFH8RAAIbAAUJAB4LBABdAQAbAAUJAB4LBABdAQAuAAQKfzAAAxsACQllIu8AABIDABsACQllIu8AABIDAAkAAQmeFHdYAEUAAAAA.Disturbd:BAACLgAFFH8OAAMcAAUJ5AqtgwABAQAcAAQJ5AqtgwABAQAPAAEJAAC/YAAAAAAuAAQKfxgAAxwACQn9DEVeAK0BABwACQn9DEVeAK0BAA8ABAmJAMY9AFsAAAAA.Disturbian:BAAALgAFFAIJAwABLgAFFAUJDgAcAOQKAA==.Dixierecht:BAABLgAECn8gAAIZAAgJbhsKGABIAgAZAAgJbhsKGABIAgAAAA==.',
Do='Docvader:BAAALgAECgQJCAAAAA==.Dodrop:BAAALgADCgYJBwAAAA==.',
Dr='Drunkenhealz:BAAALgAECgUJEAAAAA==.Drvargas:BAAALgAECgQJDwAAAA==.',
Du='Durzostern:BAEALgAECgMJAwABLgAFFAMJBgARAHwSAA==.',
['Då']='Dårth:BAAALgAECgEJAQAAAA==.',
['Dè']='Dèrty:BAAALgAECgIJAgAAAA==.',
El='Elenestern:BAECLgAFFH8GAAIRAAMJfBJuLgCHAAARAAMJfBJuLgCHAAAuAAQKfzYAAhEACQmwEkVIAAICABEACQmwEkVIAAICAAAA.Elmo:BAABLgAECn8oAAMRAAkJHhZDPQAmAgARAAkJ0BVDPQAmAgAdAAEJwxVmFQA/AAAAAA==.',
Em='Emryssa:BAAALgAECgMJDAAAAA==.',
Er='Erosis:BAACLgAFFH8OAAIRAAUJ/xt/SgBMAQARAAUJ/xt/SgBMAQAuAAQKfyQAAhEACAlsIwIvALYCABEACAlsIwIvALYCAAAA.',
Es='Esia:BAAALgADCgkJCQAAAA==.',
Ev='Evarg:BAAALgADCgcJDQAAAA==.',
Ex='Exghoulfiend:BAAALgAECgIJAgAAAA==.',
Ez='Ezaratren:BAAALgAECgUJCgABLgAFFAUJDgAWAIMTAA==.',
Fa='Fakêr:BAAALgADCgEJAQAAAA==.',
Fe='Fear:BAACLgAFFH8GAAIKAAMJMxu+HQANAQAKAAMJMxu+HQANAQAuAAQKfygAAwoACAmDIOgrAF8CAAoACAmDIOgrAF8CABAABQkbFk4bAHIBAAAA.Felcatalyist:BAABLgAECn8gAAMcAAkJABgcYwDKAQAcAAkJtBUcYwDKAQAPAAgJXA2iKAAQAQAAAA==.Felisaty:BAAALgAECgEJAQAAAA==.Fellisaty:BAABLgAECn8WAAIZAAgJfQ9rMgCMAQAZAAgJfQ9rMgCMAQAAAA==.Felysria:BAAALgAECgQJAgAAAA==.',
Fi='Fistitresk:BAAALgADCgQJBgABLgAECgcJFAAeAIYeAA==.Fistofwayne:BAABLgAECn8cAAIVAAgJMBA1KABwAQAVAAgJMBA1KABwAQABLgAFFAYJIAAfAPoeAA==.',
Fr='Frizzalot:BAAALgAECgEJAwAAAA==.Frizzer:BAAALgAECgMJAwAAAA==.',
Ga='Gakopozy:BAABLgAECn8bAAIJAAcJPA3rAQBZAQAJAAcJPA3rAQBZAQAAAA==.Gambrinos:BAAALgADCgMJAwAAAA==.Gander:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.Gandermon:BAAALgAECgEJAQAAAA==.Garnath:BAAALgADCgYJBgAAAA==.',
Ge='Geg:BAABLgAFFH8FAAIcAAMJvBEhJwD7AAAcAAMJvBEhJwD7AAAAAA==.',
Gl='Glorrex:BAAALgADCgYJBgAAAA==.',
Go='Gongsho:BAAALgAECgQJBgAAAA==.',
Gr='Grapez:BAAALgAFFAIJAgABLgAFFAgJIQAPADMbAA==.Grimlokke:BAAALgAECgIJAgABLgAFFAUJDgAWAIMTAA==.Grïmyst:BAAALgAECgEJAQABLgAFFAUJDgAWAIMTAA==.',
Gu='Guldán:BAAALgAECgYJEQAAAA==.',
Gw='Gwydre:BAACLgAFFH8TAAIPAAQJaCAgFABPAQAPAAQJaCAgFABPAQAuAAQKfxUAAg8ACAnqHvYNAC4CAA8ACAnqHvYNAC4CAAAA.',
Ha='Harbard:BAAALgADCgYJCwAAAA==.Havran:BAAALgAECgQJBAABLgAECgkJQwAWABYXAA==.Havrin:BAABLgAECn9DAAMWAAkJFhe/EADeAQAWAAkJFhe/EADeAQAgAAEJQhLgMQA7AAAAAA==.',
He='Headshots:BAACLgAFFH8VAAIBAAQJIRkrPgAxAQABAAQJIRkrPgAxAQAuAAQKfy4AAgEACQmVH10UAJMCAAEACQmVH10UAJMCAAAA.Heartsong:BAAALgAECgEJAQAAAA==.Heavylode:BAAALgAECgQJCwAAAA==.Hexatar:BAAALgAECgQJBAAAAA==.',
Hk='Hkia:BAAALgAFFAMJAwAAAA==.',
Ho='Hoardkiller:BAAALgAECgQJAwABLgAFFAUJFQAhANQNAA==.Holmie:BAAALgADCgkJCgAAAA==.Honk:BAAALgAFFAIJAwAAAA==.Hoofsoflove:BAAALgADCgQJBAAAAA==.Hoogablop:BAABLgAFFH8IAAICAAYJxxeYJwBsAQACAAYJxxeYJwBsAQABLgAFFAcJDwAMAJYhAA==.Hoogaplop:BAACLgAFFH8aAAMPAAUJkybbEwBSAQAcAAUJkyYEOQCKAQAPAAUJqB/bEwBSAQAuAAQKf0UAAw8ACQnDJEUFANcCABwACQm5IQMUAAMDAA8ACAl1JEUFANcCAAEuAAUUBwkPAAwAliEA.',
Hu='Huamulan:BAABLgAECn9cAAICAAkJtQ5qBACVAQACAAkJtQ5qBACVAQAAAA==.',
Ib='Ibc:BAAALgADCgcJDQABLgAFFAIJBQAcAJQRAA==.Ibchilling:BAABLgAECn8pAAIRAAgJxBpCTwDuAQARAAgJxBpCTwDuAQABLgAFFAIJBQAcAJQRAA==.Ibcorrupted:BAABLgAFFH8FAAIcAAIJlBE8zACWAAAcAAIJlBE8zACWAAAAAA==.',
Ic='Icarrus:BAACLgAFFH8RAAIGAAUJzxGVKAAqAQAGAAUJzxGVKAAqAQAuAAQKfy8AAwYACQnkHGUaAEUCAAYACQnkHGUaAEUCABQABQmTEF1NAM4AAAEuAAUUBAkIABwAzQsA.Icarus:BAAALgADCgEJAQABLgAFFAQJCAAcAM0LAA==.Iccarus:BAAALgAECgUJBQABLgAFFAQJCAAcAM0LAA==.Icebone:BAAALgAECgcJCgABLgAECggJEwADAAAAAA==.',
Ig='Ignis:BAACLgAFFH8IAAIcAAQJzQt7fgAKAQAcAAQJzQt7fgAKAQAuAAQKfxYAAxwABgl5G4aEAFoBABwABgnzGYaEAFoBAB8AAQkRFnw3AD8AAAAA.',
Il='Illioch:BAAALgAECgEJAQAAAA==.',
Im='Imaway:BAAALgAECgEJAQAAAA==.',
In='Inesh:BAAALgADCgEJAQAAAA==.',
Ir='Irrizia:BAAALgADCgkJCgAAAA==.',
Is='Iseldra:BAAALgAECgEJAQAAAA==.',
['Iç']='Içyhot:BAAALgAECgEJBAABLgAECgcJEwADAAAAAA==.',
Ja='Jackbfistn:BAAALgAECggJEwAAAA==.Jaskim:BAABLgAECn8eAAMcAAkJWw3yXwCpAQAcAAkJWw3yXwCpAQAfAAIJ2AWjNgBCAAAAAA==.',
Je='Jeses:BAAALgAECgUJCQABLgAECgkJLwACAEIWAA==.',
Jo='Jolty:BAAALgAECgEJAQABLgAFFAYJGgAcAFEgAA==.Jooni:BAAALgADCggJDwAAAA==.Jordomon:BAABLgAECn8fAAMXAAcJDQfcTwDOAAAXAAcJAQfcTwDOAAAgAAMJ8gZOPwBfAAAAAA==.',
Jy='Jyundiel:BAAALgADCgYJBgABLgADCgYJBgADAAAAAA==.',
['Jú']='Júliët:BAAALgAECgIJAgAAAA==.',
Ka='Kaazaama:BAAALgADCgYJBgAAAA==.Kahtonah:BAAALgADCgMJAwAAAA==.Kalessin:BAAALgADCgkJDgABLgAECgQJCwADAAAAAA==.Kaltaan:BAABLgAECn8tAAQeAAkJxiFyBgAZAwAeAAkJxiFyBgAZAwATAAQJUh8jPABKAQAMAAEJ4R07dQBWAAAAAA==.Karasan:BAABLgAECn8jAAIBAAkJ0BeHMAAaAgABAAkJ0BeHMAAaAgAAAA==.Karenas:BAACLgAFFH8GAAIRAAMJ5BF3KwCcAAARAAMJ5BF3KwCcAAAuAAQKfyYAAxEACQnoIHIQAPgCABEACQnoIHIQAPgCAB0AAgnhCpkWAGYAAAAA.Karr:BAABLgAECn8XAAICAAgJNAcWtgAWAQACAAgJNAcWtgAWAQAAAA==.Kataraara:BAACLgAFFH8HAAIVAAQJRiA0GABgAQAVAAQJRiA0GABgAQAuAAQKfxcAAhUACAntJN4EADwDABUACAntJN4EADwDAAEuAAUUBwkhAA8AeSUA.Katbeans:BAABLgAECn8sAAQGAAkJGB1UDgC6AgAGAAkJGB1UDgC6AgAVAAUJIQ6RYgC4AAAUAAEJJhYflQA7AAAAAA==.Kathrynne:BAAALgAECgUJCQAAAA==.Katmai:BAAALgADCgEJAQAAAA==.Katrielle:BAAALgAECgUJBQAAAA==.Kaykoh:BAABLgAFFH8HAAIcAAIJLB1BMAChAAAcAAIJLB1BMAChAAAAAA==.',
Ke='Kelicemoon:BAABLgAECn8oAAMKAAkJZgoPYwB5AQAKAAkJSQkPYwB5AQAQAAcJIQd5MQBYAAABLgAFFAIJBgACAKQLAA==.Kemono:BAAALgADCgYJBgAAAA==.',
Kh='Khaliope:BAABLgAECn82AAIiAAkJpQ2UdwAyAQAiAAkJpQ2UdwAyAQAAAA==.Khat:BAAALgADCgkJCQAAAA==.',
Ki='Kiara:BAACLgAFFH8aAAMjAAYJ8xZWEgBuAQAjAAUJVxlWEgBuAQAkAAIJWhayRQCwAAAuAAQKfy0AAyMACQlpH1QIALUCACMACQlpH1QIALUCACQABAm9E/tLAP0AAAAA.Kiryu:BAAALgAECgUJBQAAAA==.',
Ko='Korzari:BAAALgADCgEJAQAAAA==.Koven:BAAALgADCgcJCQAAAA==.',
Kr='Krogers:BAAALgAECgcJEQAAAA==.',
Ku='Kumojo:BAAALgAECgkJAgAAAA==.',
Ky='Kyndlearya:BAAALgAECgEJAQAAAA==.',
['Kû']='Kûrr:BAAALgAECgEJAQABLgAFFAEJAQADAAAAAA==.',
La='Lahrnaon:BAAALgAFFAIJAgAAAA==.Laxeron:BAABLgAECn8iAAINAAkJQCRXBQAMAwANAAkJQCRXBQAMAwAAAA==.',
Le='Leighty:BAAALgADCgUJBQAAAA==.Leotherassy:BAAALgAECgYJCQAAAA==.Leychron:BAAALgAECgEJAQAAAA==.',
Li='Lightsworn:BAAALgAECgEJAQAAAA==.Lilin:BAAALgAECgYJBwAAAA==.',
Lo='Longboneman:BAAALgAECgIJAgABLgAECggJEwADAAAAAA==.Lotiel:BAAALgAECgMJCQABLgAFFAUJFwAHAEoSAA==.',
Lu='Lucrecia:BAABLgAECn8WAAMiAAYJbB0oUgCuAQAiAAUJ2iEoUgCuAQAlAAEJswudLAAuAAAAAA==.',
Ly='Lymara:BAAALgADCgcJCAAAAA==.Lynthirae:BAAALgADCgcJDAAAAA==.',
['Lø']='Lørðzêdd:BAAALgAECgQJEgAAAA==.',
Ma='Madmabel:BAAALgADCgQJBAAAAA==.Madness:BAAALgAECgIJAgAAAA==.Mahkaidook:BAAALgADCgYJBgAAAA==.Mal:BAAALgADCgkJCQABLgAFFAMJBAADAAAAAA==.Manyace:BAAALgAECgQJBgAAAA==.',
Mc='Mcbodhran:BAABLgAECn8hAAICAAkJTRFseAB9AQACAAkJTRFseAB9AQAAAA==.Mcfeast:BAABLgAECn8ZAAIMAAgJ+A/AKwB2AQAMAAgJ+A/AKwB2AQAAAA==.',
Me='Medra:BAABLgAECn8uAAQNAAkJ2RSoHwDyAQANAAkJ2RSoHwDyAQAmAAQJEgP9QABsAAAOAAIJ2wYHbQBHAAAAAA==.Meowdi:BAAALgAECgQJCwAAAA==.Merogoth:BAAALgADCgUJBwAAAA==.Mestrois:BAABLgAECn9HAAIRAAgJVgrWDADkAAARAAgJVgrWDADkAAAAAA==.',
Mi='Minibone:BAAALgAECgMJAwABLgAECggJEwADAAAAAA==.Mixr:BAAALgADCgQJAwAAAA==.',
Mo='Monana:BAAALgAECgQJBwAAAA==.Morar:BAAALgAECgUJDAAAAA==.Morul:BAAALgAECgQJBAAAAA==.',
Ms='Msprettÿp:BAAALgADCgIJAgAAAA==.',
Mu='Murimlinn:BAAALgADCgMJAwAAAA==.Mustafa:BAAALgAECgUJCAAAAA==.',
Na='Nanija:BAAALgAECgQJCwAAAA==.Narushi:BAAALgAECgQJBQAAAA==.',
Ne='Nezrin:BAAALgADCgQJBwAAAA==.',
Ni='Nightcat:BAAALgAECgUJBwAAAA==.Nitebäne:BAAALgADCggJCAAAAA==.Nitesbane:BAAALgADCgYJBgABLgAECgkJHQACACwgAA==.Nitesbåne:BAAALgADCgcJBwAAAA==.Niteshiftah:BAAALgADCgcJBwAAAA==.Nitestorm:BAAALgAECgcJCQAAAA==.Nivaniraa:BAAALgAECgEJAgAAAA==.Nixie:BAABLgAECn8vAAMHAAkJjAaOYgANAQAHAAkJjAaOYgANAQAXAAkJ8gSuRAD5AAAAAA==.',
No='Nobonesjones:BAACLgAFFH8LAAIFAAUJlQacBgDfAAAFAAUJlQacBgDfAAAuAAQKfxsAAgUACQlPFjMeAM4BAAUACQlPFjMeAM4BAAAA.',
Og='Oguricap:BAAALgADCgcJBwAAAA==.Ogwarshock:BAACLgAFFH8PAAQKAAUJxhqdTgAoAQAKAAQJHRadTgAoAQAQAAEJChtEJgBIAAALAAEJAAC8MQAAAAAuAAQKfyQAAwoACQk0IkIhAF4CAAoABwm0IUIhAF4CABAABQm9HzkaAHsBAAAA.',
Ok='Okkotsu:BAAALgAECgIJAwAAAA==.Okote:BAAALgAECgMJBAAAAA==.',
Ol='Oliiver:BAABLgAECn88AAIBAAkJLiGBAQCUAgABAAkJLiGBAQCUAgAAAA==.',
Om='Omni:BAAALgAECgEJAQABLgAFFAUJDgAWAIMTAA==.Omnivore:BAAALgADCgcJCAAAAA==.Omën:BAAALgAECgQJBAABLgAECgQJCAADAAAAAA==.',
On='Oniichan:BAAALgAECgQJBQAAAA==.',
Or='Orbeez:BAABLgAECn8pAAIiAAkJNyAIFQCaAgAiAAkJNyAIFQCaAgAAAA==.',
Pa='Pack:BAAALgAECgcJAQAAAA==.Paladlin:BAAALgADCgYJCwAAAA==.Panaceus:BAABLgAECn86AAIjAAkJ1yLWAQBsAwAjAAkJ1yLWAQBsAwAAAA==.Paragon:BAAALgADCgkJDQABLgAFFAMJDwAcAFYgAA==.Patron:BAAALgAECgIJAgAAAA==.',
Pe='Pepe:BAAALgAECgUJCQAAAA==.Perennial:BAAALgAECgYJCQAAAA==.Perpetrator:BAAALgAECgYJBwAAAA==.',
Ph='Phreeq:BAEALgAECgYJDgABLgAECggJMwAZAK4UAA==.Phrequency:BAEBLgAECn8zAAMZAAgJrhQsJwDRAQAZAAgJrhQsJwDRAQACAAgJ+BG4cACNAQAAAA==.',
Pi='Piety:BAAALgADCgIJAgABLgAECgYJBgADAAAAAA==.Pig:BAAALgAECgEJAQABLgAFFAcJDwAMAJYhAA==.',
Pl='Plazma:BAAALgAECgEJAQAAAA==.Plazmafury:BAABLgAFFH8KAAMNAAYJ5g9UEgB1AQANAAYJZw5UEgB1AQAOAAEJyA02QgBDAAAAAA==.Plazmaglaive:BAAALgAFFAEJAQAAAA==.Plumsham:BAAALgADCgQJBAAAAA==.',
Po='Poisonóus:BAACLgAFFH8PAAIPAAUJrBh+GgATAQAPAAUJrBh+GgATAQAuAAQKfzMAAg8ACQmeHVcKAGwCAA8ACQmeHVcKAGwCAAAA.Polyxo:BAAALgAECgYJDAAAAA==.',
Pr='Profang:BAAALgAECgQJBAAAAA==.',
Py='Pyrelic:BAABLgAFFH8aAAIUAAYJsxdfEgAqAQAUAAYJsxdfEgAqAQAAAA==.Pyroela:BAAALgAECgUJCgABLgAFFAQJEwAPAGggAA==.',
['Pö']='Pöncho:BAAALgAECgEJAQAAAA==.',
Qa='Qayllera:BAABLgAECn8VAAIRAAYJAAksDQDfAAARAAYJAAksDQDfAAAAAA==.',
Qe='Qelcie:BAAALgAECgQJBQAAAA==.',
Qu='Quixotic:BAAALgADCgUJBgAAAA==.Quizet:BAAALgADCgYJCgAAAA==.',
Ra='Radicchio:BAAALgAECgQJBAAAAA==.Radkeem:BAABLgAECn8YAAIPAAkJiB0ZCQCBAgAPAAkJiB0ZCQCBAgAAAA==.Raf:BAAALgAECgYJBwAAAA==.Raizo:BAAALgAECgYJCAAAAA==.Rakeem:BAAALgAECgcJEAABLgAECgkJGAAPAIgdAA==.Ralivan:BAAALgADCgEJAQAAAA==.Ravenhawk:BAAALgADCgQJCAAAAA==.Razorknight:BAAALgAECgEJAQAAAA==.',
Re='Redtoxin:BAAALgAECgQJCwAAAA==.Reilley:BAACLgAFFH8bAAIcAAYJ3hUdPgB8AQAcAAYJ3hUdPgB8AQAuAAQKfzMAAhwACQnxIJYNAAADABwACQnxIJYNAAADAAAA.Reilleÿ:BAAALgAECgQJBAABLgAFFAYJGwAcAN4VAA==.Reko:BAAALgAECgYJEAAAAA==.Remorsa:BAABLgAECn8XAAMCAAcJxBvHTwDZAQACAAcJxBvHTwDZAQAZAAQJJRXOVwAcAQAAAA==.Renni:BAABLgAECn8sAAIKAAkJxBa7LQAiAgAKAAkJxBa7LQAiAgABLgAECgkJJAAVAKIZAA==.Reshath:BAAALgADCgEJAQAAAA==.Reznor:BAABLgAECn8kAAIZAAkJLBbDJwDtAQAZAAkJLBbDJwDtAQAAAA==.',
Ri='Rinela:BAAALgADCgcJBwAAAA==.Riselle:BAAALgAFFAEJAgAAAA==.',
Ro='Rosealia:BAABLgAECn8YAAIBAAgJigYNogD+AAABAAgJigYNogD+AAAAAA==.',
Ru='Runeight:BAAALgADCgIJAQAAAA==.',
Ry='Ryder:BAAALgAECgIJBAAAAA==.',
['Ró']='Rómëo:BAACLgAFFH8VAAIJAAcJYBkUDgCyAQAJAAcJYBkUDgCyAQAuAAQKf1cAAgkACQloJlcAAJYDAAkACQloJlcAAJYDAAAA.',
Sa='Sabbatical:BAAALgADCgEJAQAAAA==.Sacon:BAAALgAECgEJAQABLgAFFAMJBAADAAAAAA==.Sahmeah:BAAALgAECgYJCQAAAA==.Saintzan:BAAALgAECgkJEQAAAA==.Salivan:BAAALgAECgUJCgAAAA==.San:BAAALgAECgYJDwAAAA==.Sanketsu:BAAALgADCgYJCwABLgAECgkJLAACACkVAA==.Sathariel:BAAALgAECgIJAgAAAA==.',
Sc='Scalyboyos:BAABLgAECn8mAAMjAAkJcwwJGQBEAQAjAAgJwwsJGQBEAQAkAAEJxwcBkQA5AAAAAA==.Schmoop:BAACLgAFFH8PAAIMAAcJliFKCQDQAQAMAAcJliFKCQDQAQAuAAQKfzEABAwACQnHI1AJALkCAAwACAnyI1AJALkCABMABgmLGvwvAFABAB4AAwnkEttaAJQAAAAA.',
Se='Seldaria:BAAALgAECgYJEAAAAA==.Senza:BAABLgAECn8iAAICAAgJ+AmrvQAMAQACAAgJ+AmrvQAMAQAAAA==.Senzyri:BAABLgAECn8mAAIBAAkJLxNFPgDoAQABAAkJLxNFPgDoAQAAAA==.Sephirath:BAAALgAECgIJAgAAAA==.Serote:BAAALgADCgcJBwAAAA==.Setmabone:BAAALgADCgkJCQABLgAECggJEwADAAAAAA==.Sevilo:BAAALgADCgkJCwABLgAECgIJAgADAAAAAA==.',
Sh='Shamagoth:BAAALgAECgYJBgAAAA==.Shambhala:BAAALgAECgYJEgAAAA==.Shockwàve:BAAALgADCgEJAQAAAA==.Shoes:BAAALgAECgUJBwAAAA==.Shymyst:BAAALgAFFAEJAgABLgAFFAUJFwAHAEoSAA==.',
Si='Simic:BAABLgAECn8+AAIPAAkJEBScAgAeAQAPAAkJEBScAgAeAQAAAA==.',
Sk='Skre:BAAALgAECgYJBgAAAA==.',
Sl='Sloppy:BAAALgAFFAEJAwABLgAFFAcJDwAMAJYhAA==.',
Sm='Smiddy:BAABLgAFFH8GAAQPAAMJfg/fNQBfAAAfAAIJnAeCIACEAAAPAAIJBRPfNQBfAAAcAAEJ3wbAEgFAAAAAAA==.Smokeace:BAAALgAECgEJAQAAAA==.',
Sn='Snowthistle:BAABLgAECn8YAAIXAAcJUwe6UwDAAAAXAAcJUwe6UwDAAAAAAA==.',
So='Sorle:BAAALgADCgYJCQABLgAECgkJLgANANkUAA==.Soulnãris:BAAALgAECgcJCQAAAA==.',
Sp='Spin:BAABLgAFFH8JAAMUAAIJrRmqLgCNAAAUAAIJoxaqLgCNAAAVAAEJIBeqVgBAAAAAAA==.Spudpal:BAAALgADCgEJAQABLgAECgkJLQAeAMYhAA==.Spyro:BAAALgADCgUJBQAAAA==.',
Sq='Squirley:BAAALgAECgQJCAAAAA==.',
St='Starge:BAAALgAECgYJBgAAAA==.Stargefall:BAAALgAECgMJAwAAAA==.Static:BAAALgAECgYJBgAAAA==.Stonymahoney:BAABLgAECn89AAICAAkJwxoAJgBsAgACAAkJwxoAJgBsAgAAAA==.',
Su='Sudokoo:BAAALgADCgMJAwAAAA==.Sumorna:BAAALgAECgEJAQAAAA==.Suraisu:BAACLgAFFH8HAAINAAMJ1Bw2LAADAQANAAMJ1Bw2LAADAQAuAAQKfzYAAg0ACQk/JDcDADkDAA0ACQk/JDcDADkDAAAA.Suê:BAAALgADCgEJAQABLgADCgQJBAADAAAAAA==.',
Sv='Sveela:BAACLgAFFH8TAAIWAAUJpiIjBwCFAQAWAAUJpiIjBwCFAQAuAAQKfyQAAhYACQlrIsEDAMoCABYACQlrIsEDAMoCAAAA.Sveelaa:BAABLgAECn8lAAIBAAgJax9cHgBwAgABAAgJax9cHgBwAgABLgAFFAUJEwAWAKYiAA==.Sveella:BAABLgAECn8UAAMcAAgJ/gtOmAA4AQAcAAcJ8gxOmAA4AQAPAAEJRgadZQAfAAABLgAFFAUJEwAWAKYiAA==.',
Sw='Swampjimmy:BAAALgAECgkJDAAAAA==.',
Sy='Sylrin:BAAALgADCgcJCgAAAA==.Synap:BAAALgADCgEJAQAAAA==.',
Ta='Tabchan:BAAALgAECgYJBwAAAA==.Tacocat:BAABLgAECn89AAMTAAkJmR77CADZAgATAAkJmR77CADZAgAMAAEJNAUKlQAlAAAAAA==.Tadeusz:BAAALgADCgEJAQAAAA==.Tahlonia:BAAALgAECgMJAwAAAA==.Talras:BAAALgAECgMJAwAAAA==.',
Te='Temlock:BAABLgAECn8yAAIKAAkJFxgsMQBIAgAKAAkJFxgsMQBIAgAAAA==.Tempest:BAAALgAECgUJBQABLgAFFAMJDwAcAFYgAA==.Temtank:BAABLgAECn84AAIPAAkJkiLfAwD8AgAPAAkJkiLfAwD8AgABLgAECgkJMgAKABcYAA==.Testerosa:BAAALgADCgEJAQAAAA==.',
Th='Thalagosa:BAAALgADCgkJCQAAAA==.',
To='Tosi:BAAALgADCgMJAwAAAA==.',
Tr='Trak:BAABLgAECn8ZAAIkAAgJOQ0FQAApAQAkAAgJOQ0FQAApAQAAAA==.Trukarak:BAABLgAECn8sAAICAAkJKRWOSwDkAQACAAkJKRWOSwDkAQAAAA==.',
Tu='Tuvaquitamuu:BAAALgAECgEJAQAAAA==.',
Ur='Uraha:BAAALgADCgEJAQAAAA==.',
Va='Vaeegoldiir:BAAALgAECgEJAQAAAA==.Vaelithria:BAAALgAECgcJCAABLgAFFAcJFQAJAGAZAA==.Valenti:BAABLgAECn8kAAMnAAkJ0A9zFACIAQAnAAkJ0A9zFACIAQACAAEJ0AZVwAEjAAAAAA==.Valor:BAABLgAECn8kAAICAAcJhiEtUgDSAQACAAcJhiEtUgDSAQAAAA==.Vanity:BAAALgADCgMJAwAAAA==.',
Ve='Veliann:BAAALgAECgEJAQAAAA==.Vellatrix:BAAALgAECgQJBgAAAA==.Velynesti:BAAALgAECgQJBAAAAA==.',
Vi='Vipershot:BAAALgADCggJDwAAAA==.',
Wa='Warlode:BAAALgADCgkJDgAAAA==.',
We='Weewoo:BAAALgADCgcJCwAAAA==.Weliiam:BAAALgADCgYJBwAAAA==.',
Wi='Wildama:BAABLgAECn8xAAIHAAkJkBOkAgBwAQAHAAkJkBOkAgBwAQAAAA==.Wildtail:BAABLgAECn8YAAIBAAkJkgoiDgDaAAABAAkJkgoiDgDaAAAAAA==.Windseer:BAAALgAECgMJAwABLgAFFAQJFQABACEZAA==.',
Wr='Wrenwillow:BAAALgAECgIJAgAAAA==.',
Wu='Wumbo:BAAALgADCgEJAQAAAA==.',
Xa='Xarríøn:BAAALgADCgYJBgABLgAFFAMJDQACAB0ZAA==.',
Xh='Xhadowz:BAAALgAECgEJAgAAAA==.',
Xi='Xiao:BAABLgAECn88AAMGAAkJ/Rj2AgCrAQAGAAkJ/Rj2AgCrAQAUAAYJIAzVBQCaAAAAAA==.Xiaolongbao:BAAALgADCgcJBwAAAA==.',
Xy='Xylaini:BAAALgAECgQJBAABLgAFFAEJAQADAAAAAA==.',
Ya='Yahargul:BAABLgAECn8mAAIMAAkJ9w+yIADAAQAMAAkJ9w+yIADAAQAAAA==.',
Yo='Yogafarts:BAAALgAECgYJCAAAAA==.',
Yt='Yt:BAAALgADCgcJDAAAAA==.',
Za='Zanatilli:BAAALgAECgMJBAAAAA==.Zaterok:BAAALgAECgMJAwABLgAECgkJLAACACkVAA==.',
Ze='Zeik:BAABLgAECn9BAAMnAAkJ9R9YAACAAgAnAAkJ9R9YAACAAgACAAMJngpiWAFYAAAAAA==.Zephyrgosa:BAAALgADCgcJDgAAAA==.Zerase:BAAALgAECgQJCwAAAA==.',
Zo='Zoomin:BAAALgAECgIJAgAAAA==.',
Zu='Zucco:BAAALgAECgkJDgAAAA==.Zuufungo:BAAALgAECgUJBQABLgAECgkJLQAeAMYhAA==.',
['Zí']='Zíx:BAABLgAECn8oAAImAAkJSxI0GAB+AQAmAAkJSxI0GAB+AQAAAA==.',
['Àl']='Àlcàrà:BAABLgAECn8ZAAMPAAcJcA8rJwAbAQAPAAcJcA8rJwAbAQAcAAEJDgptIQEzAAAAAA==.',
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
