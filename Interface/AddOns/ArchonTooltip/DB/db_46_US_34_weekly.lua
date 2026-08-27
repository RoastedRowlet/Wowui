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

local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Hunter-Marksmanship','DemonHunter-Havoc','Monk-Mistweaver','Druid-Restoration','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Priest-Shadow','Unknown-Unknown','Warrior-Fury','Warrior-Arms','DeathKnight-Blood','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Mage-Frost','Mage-Arcane','Shaman-Enhancement','Priest-Holy','Monk-Windwalker','Monk-Brewmaster','Druid-Guardian','Druid-Balance','Shaman-Restoration','Paladin-Holy','Shaman-Elemental','Rogue-Outlaw','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Hunter-Survival','Priest-Discipline','DemonHunter-Devourer','DemonHunter-Vengeance','Warrior-Protection','Paladin-Protection',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=46,date='2026-08-25',data={Ad='Adamonious:BAAALgAECgYJCwABLgAECgkJFgABAA8WAA==.Adaware:BAAALgAECgUJBgAAAA==.Addieeboy:BAAALgADCgEJAQAAAA==.Adellea:BAAALgAECgYJBwAAAA==.',
Ai='Aisha:BAAALgAECgEJAgAAAA==.',
Ak='Akumashi:BAAALgAECgEJAQAAAA==.',
Al='Alaponia:BAAALgAECgEJAgAAAA==.Alba:BAABLgAECn8wAAICAAgJ+h2MNAAuAgACAAgJ+h2MNAAuAgABLgAFFAUJFwABACEZAA==.Aletta:BAAALgAECgkJEQAAAA==.Allast:BAAALgADCgYJDQAAAA==.',
An='Andezard:BAABLgAECn9jAAMBAAkJwR+sAgDjAgABAAkJwR+sAgDjAgADAAcJTRbzAQCVAQAAAA==.Angelys:BAABLgAECn8wAAIEAAgJ3QtXCgD+AAAEAAgJ3QtXCgD+AAAAAA==.',
Ap='Aphrobitey:BAAALgAECgMJBQAAAA==.',
Aq='Aquâ:BAAALgADCgkJEAABLgAECgkJMQAFAOIYAA==.',
Ar='Arathas:BAAALgADCgcJDAAAAA==.Arianes:BAAALgAECgcJDgAAAA==.Arrowin:BAAALgADCgYJBgAAAA==.Arturias:BAABLgAECn8cAAICAAgJ7hLUawCXAQACAAgJ7hLUawCXAQAAAA==.',
At='Athenaowl:BAABLgAECn8cAAIBAAgJBAs6HgDxAAABAAgJBAs6HgDxAAAAAA==.',
Au='Autofocus:BAABLgAECn8eAAIBAAgJPBqWQQDdAQABAAgJPBqWQQDdAQAAAA==.',
Aw='Aweyna:BAABLgAECn8aAAIGAAkJ0QxVUgBGAQAGAAkJ0QxVUgBGAQAAAA==.Awisha:BAAALgADCgUJBQAAAA==.',
Ay='Ayanoriko:BAACLgAFFH8RAAIHAAcJkxLgBAA1AQAHAAcJkxLgBAA1AQAuAAQKfy8AAgcACQkiIB4DAIsCAAcACQkiIB4DAIsCAAAA.Ayasumi:BAAALgAECgIJAgAAAA==.',
Ba='Babaganoosh:BAAALgAECgUJCwAAAA==.Babynick:BAAALgAECgEJAQAAAA==.Bacca:BAAALgADCgIJAgAAAA==.Baellefyre:BAAALgADCgYJBgAAAA==.Baoyue:BAAALgAECggJCwABLgAFFAcJFQAIAEQZAA==.Barracuda:BAAALgAECgYJBgAAAA==.',
Be='Beans:BAABLgAFFH8RAAQJAAgJ9xKWPQBXAQAJAAcJpRSWPQBXAQAKAAEJ4QikEQBKAAALAAEJ4grMJgBIAAABLgAFFAkJHQAMAE0iAA==.Benmonk:BAAALgAECgMJAwAAAA==.',
Bi='Bifur:BAAALgADCgkJDwAAAA==.Bigbuttflori:BAAALgAECgMJBQABLgAECgQJBAANAAAAAA==.Bigpapapump:BAAALgAECgEJAQAAAA==.Bigstones:BAACLgAFFH8KAAMOAAQJBQQOPwCrAAAOAAMJRQQOPwCrAAAPAAEJRAORKAArAAAuAAQKfywAAw4ACQn0EWotAJwBAA4ACQmqDmotAJwBAA8ABwlQEUA8ANQAAAAA.',
Bl='Blacksavior:BAAALgAECgUJCAAAAA==.Blindbone:BAAALgAECgcJCQABLgAECggJEwANAAAAAA==.Blisterine:BAAALgAECgYJBgAAAA==.Blucifer:BAAALgAECgUJCgAAAA==.Bluehydra:BAAALgADCgcJCAAAAA==.Bluepocalyps:BAAALgAECgQJBAAAAA==.',
Bo='Bobbydigital:BAACLgAFFH8JAAIQAAMJkRoTEgDXAAAQAAMJkRoTEgDXAAAuAAQKfzoAAhAACQm+G20KAGsCABAACQm+G20KAGsCAAAA.Bohd:BAAALgADCgIJAgAAAA==.Bolas:BAABLgAECn8XAAQRAAgJuwwHCQDlAAARAAcJjQsHCQDlAAASAAUJGgvfBACUAAATAAQJwgNcNQBQAAAAAA==.Boneski:BAAALgAECgUJEAAAAA==.Booger:BAAALgAECgQJBAAAAA==.',
Br='Bracynn:BAABLgAECn8iAAIQAAkJOwZRNwC4AAAQAAkJOwZRNwC4AAAAAA==.Brenonna:BAAALgAECgQJCAABLgAECggJGwAQAI0NAA==.Brixx:BAAALgAECgMJAwAAAA==.Brudiclad:BAABLgAECn8wAAQLAAkJSRV8CgC3AQALAAkJuhN8CgC3AQAJAAcJigu2qQDvAAAKAAIJzxH2UQB4AAAAAA==.',
Bu='Budfight:BAAALgAECgYJEQAAAA==.Burnt:BAAALgAECgQJBAAAAA==.Butterfinger:BAAALgADCgQJBwAAAA==.Buxxor:BAAALgAECgcJBwAAAA==.',
Ca='Caimark:BAABLgAECn8yAAIUAAgJ6waxxwD+AAAUAAgJ6waxxwD+AAAAAA==.Calahan:BAACLgAFFH8HAAICAAMJgBmzagDZAAACAAMJgBmzagDZAAAuAAQKfx4AAgIACAmxGmw0AFACAAIACAmxGmw0AFACAAAA.',
Ce='Cealia:BAABLgAECn8ZAAIVAAgJVh2NAABjAgAVAAgJVh2NAABjAgAAAA==.',
Ch='Chakuneeai:BAAALgADCgYJBgAAAA==.Chancleta:BAAALgAECgYJDAAAAA==.Chaszy:BAAALgAECgUJCgABLgAECgkJJQAIAMQPAA==.Cherub:BAAALgADCgIJAgAAAA==.Chikostix:BAABLgAECn8tAAIWAAgJ9wlEGABGAQAWAAgJ9wlEGABGAQAAAA==.Christae:BAABLgAECn8nAAIXAAkJNRn4EABcAgAXAAkJNRn4EABcAgAAAA==.Chronuwu:BAAALgAECgMJAwAAAA==.',
Ci='Cillicone:BAAALgAECgEJAgAAAA==.',
Cl='Clementînê:BAAALgAECgIJAgAAAA==.Clemêntine:BAAALgAECgYJDAAAAA==.Clydè:BAABLgAECn9SAAMYAAkJ6RaHFABJAgAYAAgJbheHFABJAgAZAAkJrhL9GwDFAQAAAA==.Cláncey:BAAALgAFFAEJAQAAAA==.',
Co='Coachhazzard:BAAALgAECgQJCwAAAA==.Cocytus:BAAALgADCgIJAgABLgAFFAIJBwAJADkaAA==.Colinferal:BAABLgAFFH8FAAIaAAEJRCAlPgAzAAAaAAEJRCAlPgAzAAAAAA==.Combatant:BAAALgADCgYJDAAAAA==.Compromise:BAAALgAECgYJCAAAAA==.Compromised:BAACLgAFFH8MAAIEAAQJgxZFCAAxAQAEAAQJgxZFCAAxAQAuAAQKfy8AAgQACQneG/4KAHcCAAQACQneG/4KAHcCAAAA.Connalious:BAAALgAECgEJAQAAAA==.Conquests:BAAALgAECgIJAgAAAA==.Corelack:BAACLgAFFH8RAAIaAAUJgxOKEwDnAAAaAAUJgxOKEwDnAAAuAAQKfxcAAxoACQm9DaslACYBABoACQmZDaslACYBABsABQmpBeJiAI8AAAAA.',
Cr='Crwth:BAAALgAECgUJBQAAAA==.',
Ct='Ctrlaltmagic:BAAALgAECgEJAgAAAA==.',
Cu='Cupis:BAAALgAECgQJBAAAAA==.Curendae:BAABLgAECn9IAAIBAAkJfRh5CAACAgABAAkJfRh5CAACAgAAAA==.Cuzom:BAAALgAECgMJAwAAAA==.',
Da='Dabaldzombie:BAACLgAFFH8TAAIUAAUJoxqPLAAEAQAUAAUJoxqPLAAEAQAuAAQKfx0AAhQACQkSGTxMAFICABQACQkSGTxMAFICAAEuAAUUCAkVABwAxB8A.Daddyshocker:BAABLgAECn8WAAIdAAcJthRKLwCeAQAdAAcJthRKLwCeAQAAAA==.Danamy:BAAALgADCggJDQAAAA==.Danglo:BAAALgAECgEJAQABLgAFFAQJFAAJAHwQAA==.Daxzazi:BAABLgAECn8dAAMYAAgJQAROWACvAAAYAAgJQAROWACvAAAFAAUJrAQckwByAAAAAA==.',
De='Deadlee:BAAALgAECgMJAwAAAA==.Deadlights:BAAALgAECgUJBwAAAA==.Deadmanwlkin:BAAALgADCgIJAgAAAA==.Defias:BAAALgADCggJCAAAAA==.Delicious:BAEBLgAFFH8MAAIQAAUJAAtOJADMAAAQAAUJAAtOJADMAAABLgAFFAgJIAAeANsYAA==.Demonhots:BAAALgAECgEJAQAAAA==.Despair:BAAALgAECgMJAwABLgAFFAUJFwABACEZAA==.',
Di='Dice:BAACLgAFFH8SAAIfAAYJShsLBABdAQAfAAYJShsLBABdAQAuAAQKfzAAAx8ACQllIu8AABIDAB8ACQllIu8AABIDAAgAAQmeFHdYAEUAAAAA.Disturbd:BAACLgAFFH8OAAMgAAUJ5AqtgwABAQAgAAQJ5AqtgwABAQAQAAEJAAC/YAAAAAAuAAQKfxgAAyAACQn9DEVeAK0BACAACQn9DEVeAK0BABAABAmJAMY9AFsAAAAA.Disturbian:BAAALgAFFAIJAwABLgAFFAUJDgAgAOQKAA==.Dixierecht:BAABLgAECn8gAAIdAAgJbhsKGABIAgAdAAgJbhsKGABIAgAAAA==.',
Do='Docvader:BAAALgAECgQJCgAAAA==.Dodrop:BAAALgADCgYJBwAAAA==.',
Dr='Drunkenhealz:BAAALgAECgUJEAAAAA==.Drvargas:BAABLgAECn8WAAIKAAYJzhE8BQARAQAKAAYJzhE8BQARAQAAAA==.',
Du='Durzostern:BAEALgAECgUJDAABLgAFFAQJBwAUADcPAA==.',
['Då']='Dårth:BAAALgAECgEJAQAAAA==.',
['Dè']='Dèrty:BAAALgAECgIJAgAAAA==.',
El='Elenestern:BAECLgAFFH8HAAIUAAQJNw+SRgCxAAAUAAQJNw+SRgCxAAAuAAQKfzYAAhQACQmwEkVIAAICABQACQmwEkVIAAICAAAA.Elmo:BAABLgAECn8oAAMUAAkJHhZDPQAmAgAUAAkJ0BVDPQAmAgAVAAEJwxVmFQA/AAAAAA==.Elyon:BAAALgADCgEJAQAAAA==.',
Em='Emryssa:BAAALgAECgMJDAAAAA==.',
Er='Erimia:BAAALgAECgEJAQAAAA==.Erosis:BAACLgAFFH8PAAIUAAYJkhp/SgBMAQAUAAYJkhp/SgBMAQAuAAQKfycAAhQACQnhIgIvALYCABQACQnhIgIvALYCAAAA.',
Es='Esia:BAAALgADCgkJCQAAAA==.',
Ev='Evarg:BAAALgADCgcJDQAAAA==.',
Ex='Exclusive:BAAALgAECgEJAQAAAA==.Exghoulfiend:BAAALgAECgIJAgAAAA==.',
Ez='Ezaratren:BAAALgAECgUJCgABLgAFFAUJEQAaAIMTAA==.',
Fa='Fakêr:BAAALgADCgEJAQAAAA==.',
Fe='Fear:BAACLgAFFH8GAAIJAAMJMxu+HQANAQAJAAMJMxu+HQANAQAuAAQKfygAAwkACAmDIOgrAF8CAAkACAmDIOgrAF8CAAoABQkbFk4bAHIBAAAA.Felcatalyist:BAABLgAECn8gAAMgAAkJABgcYwDKAQAgAAkJtBUcYwDKAQAQAAgJXA2iKAAQAQAAAA==.Felisaty:BAAALgAECgEJAQAAAA==.Fellisaty:BAABLgAECn8WAAIdAAgJfQ9rMgCMAQAdAAgJfQ9rMgCMAQAAAA==.Felysria:BAAALgAECgQJAgAAAA==.',
Fi='Fistofwayne:BAABLgAECn8cAAIZAAgJMBA1KABwAQAZAAgJMBA1KABwAQABLgAFFAcJJQAhAIYcAA==.',
Fr='Frizzalot:BAAALgAECgEJAwAAAA==.Frizzer:BAAALgAECgMJAwAAAA==.',
Fu='Funji:BAAALgADCgUJAQAAAA==.',
Ga='Gakopozy:BAABLgAECn8lAAIIAAkJxA8iAwDDAQAIAAkJxA8iAwDDAQAAAA==.Gambrinos:BAAALgADCgMJAwAAAA==.Gander:BAAALgADCgEJAQABLgAECgEJAQANAAAAAA==.Gandermon:BAAALgAECgEJAQAAAA==.Garnath:BAAALgADCgYJBgAAAA==.',
Ge='Geg:BAABLgAFFH8FAAIgAAMJvBEhJwD7AAAgAAMJvBEhJwD7AAAAAA==.',
Gl='Glorrex:BAAALgADCgYJBgAAAA==.',
Go='Gongsho:BAAALgAECgQJBwAAAA==.',
Gr='Grapez:BAAALgAFFAIJAgABLgAFFAgJIwAQAOEbAA==.Grimlokke:BAAALgAECgIJBAABLgAFFAUJEQAaAIMTAA==.Grïmyst:BAAALgAECgEJAQABLgAFFAUJEQAaAIMTAA==.',
Gu='Guldán:BAABLgAECn8WAAIJAAYJxQgTHACZAAAJAAYJxQgTHACZAAAAAA==.',
Gw='Gwendilynne:BAAALgAECgIJAgAAAA==.',
Ha='Harbard:BAAALgADCgYJCwAAAA==.Havran:BAAALgAECgQJBAABLgAECgkJSAAaAAEbAA==.Havrin:BAABLgAECn9IAAQaAAkJARu/EADeAQAaAAkJaBi/EADeAQAiAAQJZBpBCQCsAAAGAAEJ/QseJQAqAAAAAA==.',
He='Headshots:BAACLgAFFH8XAAMBAAUJIRkrPgAxAQABAAQJIRkrPgAxAQAjAAIJPgN1HwA0AAAuAAQKfy4AAgEACQmVH10UAJMCAAEACQmVH10UAJMCAAAA.Heartsong:BAAALgAECgEJAQAAAA==.Heavylode:BAAALgAECgUJDwAAAA==.Hexatar:BAAALgAECgQJBAAAAA==.',
Hk='Hkia:BAAALgAFFAMJAwAAAA==.',
Ho='Hoardkiller:BAAALgAECgQJAwABLgAFFAUJFQAjANQNAA==.Holmie:BAAALgADCgkJCgAAAA==.Holyguacamol:BAAALgAECgQJAgAAAA==.Honk:BAAALgAFFAIJAwAAAA==.Hoofsoflove:BAAALgADCgQJBAAAAA==.Hoogablop:BAABLgAFFH8KAAICAAcJZxeYJwBsAQACAAcJZxeYJwBsAQABLgAFFAkJHQAMAE0iAA==.Hoogaplop:BAACLgAFFH8cAAMQAAYJ9iLbEwBSAQAgAAYJ9iIEOQCKAQAQAAUJqB/bEwBSAQAuAAQKf0UAAxAACQnDJEUFANcCACAACQm5IQMUAAMDABAACAl1JEUFANcCAAEuAAUUCQkdAAwATSIA.',
Hu='Huamulan:BAABLgAECn9zAAICAAkJ2w/VDACbAQACAAkJ2w/VDACbAQAAAA==.',
Ib='Ibc:BAAALgADCgcJDQABLgAFFAMJCAAgAJMSAA==.Ibchilling:BAABLgAECn8pAAIUAAgJxBpCTwDuAQAUAAgJxBpCTwDuAQABLgAFFAMJCAAgAJMSAA==.Ibcorrupted:BAABLgAFFH8IAAIgAAMJkxJZYwCSAAAgAAMJkxJZYwCSAAAAAA==.',
Ic='Icarrus:BAACLgAFFH8SAAIFAAYJ+w+VKAAqAQAFAAYJ+w+VKAAqAQAuAAQKfy8AAwUACQnkHGUaAEUCAAUACQnkHGUaAEUCABgABQmTEF1NAM4AAAEuAAUUBQkVACAArBUA.Icarus:BAAALgADCgEJAQABLgAFFAUJFQAgAKwVAA==.Iccarus:BAAALgAECgUJBQABLgAFFAUJFQAgAKwVAA==.Icebone:BAAALgAECgcJCgABLgAECggJEwANAAAAAA==.',
Ig='Ignis:BAACLgAFFH8VAAIgAAUJrBWFLgAYAQAgAAUJrBWFLgAYAQAuAAQKfxYAAyAABgl5G4aEAFoBACAABgnzGYaEAFoBACEAAQkRFnw3AD8AAAAA.',
Il='Illioch:BAAALgAECgEJAQAAAA==.',
Im='Imaway:BAAALgAECgEJAQAAAA==.',
In='Inesh:BAAALgADCgEJAQAAAA==.',
Ir='Irrizia:BAAALgADCgkJCgAAAA==.',
Is='Iseldra:BAAALgAECgMJAwAAAA==.',
['Iç']='Içyhot:BAAALgAECgEJBAABLgAECgcJEwANAAAAAA==.',
Ja='Jackbfistn:BAAALgAECggJEwAAAA==.Jaskim:BAABLgAECn8hAAMgAAkJWw3yXwCpAQAgAAkJWw3yXwCpAQAhAAIJ2AWjNgBCAAAAAA==.',
Jo='Jolty:BAAALgAECgEJAQABLgAFFAYJGgAgAFEgAA==.Jooni:BAAALgADCggJDwAAAA==.Jordomon:BAABLgAECn8gAAMbAAgJNwfcTwDOAAAbAAgJLQfcTwDOAAAiAAMJ8gZOPwBfAAAAAA==.',
Jy='Jyundiel:BAAALgADCgYJBgABLgADCgYJBgANAAAAAA==.',
['Jú']='Júliët:BAAALgAECgIJAgAAAA==.',
Ka='Kaazaama:BAAALgADCgYJBgAAAA==.Kahtonah:BAAALgADCgMJAwAAAA==.Kalessin:BAAALgADCgkJDgABLgAECgYJEQANAAAAAA==.Kaltaan:BAABLgAECn8tAAQkAAkJxiFyBgAZAwAkAAkJxiFyBgAZAwAXAAQJUh8jPABKAQAMAAEJ4R07dQBWAAAAAA==.Karasan:BAABLgAECn8lAAIBAAkJ0BeHMAAaAgABAAkJ0BeHMAAaAgAAAA==.Karenas:BAACLgAFFH8QAAIUAAUJahq7JQBEAQAUAAUJahq7JQBEAQAuAAQKfyYAAxQACQnoIHIQAPgCABQACQnoIHIQAPgCABUAAgnhCpkWAGYAAAAA.Karr:BAABLgAECn8XAAICAAgJNAcWtgAWAQACAAgJNAcWtgAWAQAAAA==.Kataraara:BAACLgAFFH8HAAIZAAQJRiA0GABgAQAZAAQJRiA0GABgAQAuAAQKfx0AAxkACAkqJd4EADwDABkACAkqJd4EADwDAAUAAQkxI+EnAGIAAAEuAAUUCAkiABAAjCUA.Katbeans:BAABLgAECn9OAAQFAAkJtR3ZAQDMAgAFAAkJtR3ZAQDMAgAZAAkJaxlqAQBPAgAYAAYJhBhSBQBbAQAAAA==.Kathrynne:BAAALgAECgUJCQAAAA==.Katmai:BAAALgADCgEJAQAAAA==.Katrielle:BAAALgAECgUJBQAAAA==.Kaykoh:BAABLgAFFH8JAAIgAAIJRyIMTADDAAAgAAIJRyIMTADDAAAAAA==.',
Ke='Kelicemoon:BAABLgAECn8oAAMJAAkJZgoPYwB5AQAJAAkJSQkPYwB5AQAKAAcJIQd5MQBYAAABLgAFFAMJCwACADgMAA==.Kemono:BAAALgADCgYJBgAAAA==.',
Kh='Khaliope:BAABLgAECn82AAIlAAkJpQ2UdwAyAQAlAAkJpQ2UdwAyAQAAAA==.Khat:BAAALgADCgkJCQAAAA==.',
Ki='Kiara:BAACLgAFFH8dAAMTAAYJ8xZWEgBuAQATAAUJVxlWEgBuAQARAAIJWhayRQCwAAAuAAQKfy0AAxMACQlpH1QIALUCABMACQlpH1QIALUCABEABAm9E/tLAP0AAAAA.Kiryu:BAAALgAECgUJBQAAAA==.',
Ko='Koehler:BAAALgAECgQJBAAAAA==.Kopiroll:BAAALgADCgQJBgAAAA==.Korzari:BAAALgADCgEJAQAAAA==.Koven:BAAALgADCgcJCQAAAA==.',
Kr='Krecia:BAAALgAECgQJBAAAAA==.Krogers:BAAALgAECgcJEQABLgAECgkJEQANAAAAAA==.',
Ku='Kumojo:BAAALgAECgkJAgAAAA==.',
Ky='Kyndlearya:BAAALgAECgEJAQAAAA==.',
['Kû']='Kûrr:BAAALgAECgEJAQABLgAFFAEJAQANAAAAAA==.',
La='Lahrnaon:BAAALgAFFAIJAgAAAA==.Laxeron:BAABLgAECn8jAAIOAAkJUyRXBQAMAwAOAAkJUyRXBQAMAwAAAA==.',
Le='Leighty:BAAALgADCgUJBQAAAA==.Leotherassy:BAAALgAECgYJCwAAAA==.Leychron:BAAALgAECgEJAQAAAA==.',
Li='Lightsworn:BAAALgAECgEJAQAAAA==.Lilin:BAAALgAECgYJBwAAAA==.',
Lo='Lodehavoc:BAAALgAECgUJBwAAAA==.Longboneman:BAAALgAECgIJAgABLgAECggJEwANAAAAAA==.Lorquendus:BAAALgAECgYJEAAAAA==.Lotiel:BAAALgAECgMJCQABLgAFFAUJFwAGAEoSAA==.',
Lu='Lucrecia:BAABLgAECn8WAAMlAAYJbB0oUgCuAQAlAAUJ2iEoUgCuAQAmAAEJswudLAAuAAAAAA==.Lumbersnack:BAAALgAECgEJAQAAAA==.Lusariah:BAAALgAECgMJBAAAAA==.',
Ly='Lyat:BAABLgAFFH8MAAICAAUJvB/nEAB4AQACAAUJvB/nEAB4AQAAAA==.Lymara:BAAALgADCgcJCAAAAA==.Lynthirae:BAAALgADCgcJDAAAAA==.',
Ma='Madness:BAAALgAECgIJAgAAAA==.Madpearl:BAAALgAECgMJAwAAAA==.Mahkaidook:BAAALgADCgYJBgAAAA==.Mal:BAAALgADCgkJCQABLgAFFAMJBAANAAAAAA==.Manyace:BAAALgAECgQJBgAAAA==.',
Mc='Mcbodhran:BAABLgAECn8iAAICAAkJTRFseAB9AQACAAkJTRFseAB9AQAAAA==.Mcfeast:BAABLgAECn8ZAAIMAAgJ+A/AKwB2AQAMAAgJ+A/AKwB2AQAAAA==.',
Me='Medra:BAABLgAECn8uAAQOAAkJ2RSoHwDyAQAOAAkJ2RSoHwDyAQAnAAQJEgP9QABsAAAPAAIJ2wYHbQBHAAAAAA==.Melidoria:BAAALgAECgcJBwABLgAECgkJSQARAL0cAA==.Meowdi:BAABLgAECn8VAAMaAAYJhBgiBgBIAQAaAAYJhBgiBgBIAQAGAAEJPA6yJAArAAAAAA==.Merogoth:BAAALgADCgUJBwAAAA==.Mestrois:BAACLgAFFH8HAAIUAAIJRwKwXQBgAAAUAAIJRwKwXQBgAAAuAAQKf0cAAhQACAlWCjokAMkAABQACAlWCjokAMkAAAAA.',
Mi='Minibone:BAAALgAECgMJAwABLgAECggJEwANAAAAAA==.Mixr:BAAALgAECgEJAQAAAA==.',
Mo='Monana:BAAALgAECgUJDgAAAA==.Moonscreamer:BAAALgAECgEJAQAAAA==.Morar:BAAALgAECgUJDAAAAA==.Morul:BAAALgAECgQJBAAAAA==.',
Ms='Msprettÿp:BAAALgADCgIJAgAAAA==.',
Mu='Murimlinn:BAAALgADCgMJAwAAAA==.Mustafa:BAAALgAECgUJCAAAAA==.',
Na='Nadjá:BAAALgAECgcJEQAAAA==.Nanija:BAABLgAECn8UAAIcAAUJsQ4UGADSAAAcAAUJsQ4UGADSAAAAAA==.Narushi:BAAALgAECgQJBQAAAA==.',
Ne='Nezrin:BAAALgADCgQJBwAAAA==.',
Ni='Nightcat:BAABLgAECn8WAAMGAAkJDBV5BADmAQAGAAkJDBV5BADmAQAbAAEJdQX8LQAXAAAAAA==.Nitebäne:BAAALgAECgkJCgAAAA==.Nitesbane:BAAALgADCgYJBgABLgAECgkJHQACACwgAA==.Nitesbåne:BAAALgADCgcJBwAAAA==.Niteshiftah:BAAALgADCgcJBwAAAA==.Nitestorm:BAAALgAECgcJCQAAAA==.Nivaniraa:BAAALgAECgEJAgAAAA==.Nixie:BAABLgAECn8vAAMGAAkJjAaOYgANAQAGAAkJjAaOYgANAQAbAAkJ8gSuRAD5AAAAAA==.',
No='Nobonesjones:BAACLgAFFH8LAAIEAAUJlQacBgDfAAAEAAUJlQacBgDfAAAuAAQKfxsAAgQACQlPFjMeAM4BAAQACQlPFjMeAM4BAAAA.',
Og='Oguricap:BAAALgADCgcJBwAAAA==.Ogwarshock:BAACLgAFFH8RAAQKAAcJfx0GBgDNAAAJAAQJHRadTgAoAQAKAAMJTyAGBgDNAAALAAEJAAC8MQAAAAAuAAQKfycAAwkACQnjIkIhAF4CAAkABwl9IkIhAF4CAAoABQm9HzkaAHsBAAAA.',
Ok='Okkotsu:BAAALgAECgIJAwABLgAFFAIJAwANAAAAAA==.Okote:BAAALgAECgMJBAAAAA==.',
Ol='Oliiver:BAABLgAECn9WAAIBAAkJrCHeAgDaAgABAAkJrCHeAgDaAgAAAA==.',
Om='Omni:BAAALgAECgEJAQABLgAFFAUJEQAaAIMTAA==.Omnivore:BAAALgADCgcJCAAAAA==.Omën:BAAALgAECgQJBAABLgAECgQJCAANAAAAAA==.',
On='Oniichan:BAAALgAECgQJBQAAAA==.',
Or='Orbeez:BAABLgAECn88AAMlAAkJJCFSAgCJAgAlAAkJJCFSAgCJAgAmAAcJjhONAgBoAQAAAA==.',
Pa='Pack:BAAALgAECgcJAQAAAA==.Paladlin:BAAALgADCgYJCwAAAA==.Panaceus:BAABLgAECn86AAITAAkJ1yLWAQBsAwATAAkJ1yLWAQBsAwAAAA==.Paragon:BAAALgADCgkJDQABLgAFFAMJDwAgAFYgAA==.Patron:BAAALgAECgQJBgAAAA==.',
Pe='Pepe:BAAALgAECgUJCQAAAA==.Perennial:BAAALgAECgYJCQAAAA==.Perpetrator:BAAALgAECgYJBwAAAA==.',
Ph='Phreeq:BAEALgAECgYJDgABLgAECgkJNAAdAJkWAA==.Phrequency:BAEBLgAECn80AAMdAAkJmRYsJwDRAQAdAAgJrhQsJwDRAQACAAkJlhG4cACNAQAAAA==.',
Pi='Piety:BAAALgADCgIJAgABLgAECgYJBgANAAAAAA==.Pig:BAAALgAECgEJAQABLgAFFAkJHQAMAE0iAA==.',
Pl='Plazma:BAAALgAECgEJAQAAAA==.Plazmafury:BAABLgAFFH8KAAMOAAYJ5g9UEgB1AQAOAAYJZw5UEgB1AQAPAAEJyA02QgBDAAAAAA==.Plazmaglaive:BAAALgAFFAEJAQAAAA==.Plumsham:BAAALgADCgQJBAAAAA==.',
Po='Poisonóus:BAACLgAFFH8RAAIQAAcJ2RZ+GgATAQAQAAcJ2RZ+GgATAQAuAAQKfzMAAhAACQmeHVcKAGwCABAACQmeHVcKAGwCAAAA.Polyxo:BAABLgAECn8ZAAICAAgJIxCREABnAQACAAgJIxCREABnAQAAAA==.',
Pr='Profang:BAAALgAECgQJBAAAAA==.',
Py='Pyrelic:BAABLgAFFH8aAAIYAAYJ2hdfEgAqAQAYAAYJ2hdfEgAqAQAAAA==.',
['Pö']='Pöncho:BAAALgAECgEJAQAAAA==.',
Qa='Qayllera:BAABLgAECn8cAAIUAAcJFQ0eGgAKAQAUAAcJFQ0eGgAKAQAAAA==.',
Qe='Qelcie:BAAALgAECgQJBQAAAA==.',
Qu='Quellerodra:BAAALgADCgkJDwAAAA==.Quixotic:BAAALgADCgUJBgAAAA==.Quizet:BAAALgADCgYJCgAAAA==.',
Ra='Radicchio:BAAALgAECgUJCgAAAA==.Radkeem:BAABLgAECn8YAAIQAAkJiB0ZCQCBAgAQAAkJiB0ZCQCBAgAAAA==.Raf:BAAALgAECgYJBwAAAA==.Raizo:BAAALgAECgYJCAAAAA==.Rakeem:BAAALgAECgcJEAABLgAECgkJGAAQAIgdAA==.Ralivan:BAAALgADCgEJAgAAAA==.Ravenhawk:BAAALgADCgQJCAAAAA==.Razorknight:BAAALgAECgEJAQAAAA==.',
Re='Redtoxin:BAAALgAECgYJEQAAAA==.Reilley:BAACLgAFFH8cAAIgAAYJ3hUdPgB8AQAgAAYJ3hUdPgB8AQAuAAQKfzUAAiAACQlfIpYNAAADACAACQlfIpYNAAADAAAA.Reilleÿ:BAAALgAECgQJBAABLgAFFAYJHAAgAN4VAA==.Reko:BAAALgAECggJEwAAAA==.Remorsa:BAABLgAECn8YAAMCAAgJ5xvHTwDZAQACAAgJ5xvHTwDZAQAdAAQJJRXOVwAcAQAAAA==.Renni:BAABLgAECn8sAAIJAAkJxBa7LQAiAgAJAAkJxBa7LQAiAgABLgAECgkJJAAZAKIZAA==.Reshath:BAAALgADCgEJAQAAAA==.Reznor:BAABLgAECn8kAAIdAAkJLBbDJwDtAQAdAAkJLBbDJwDtAQAAAA==.',
Ri='Rinela:BAAALgADCgcJBwAAAA==.Ripli:BAAALgAECgYJCgABLgAFFAUJFwABACEZAA==.Riselle:BAAALgAFFAEJAgAAAA==.',
Ro='Rosealia:BAABLgAECn8ZAAIBAAkJkwYNogD+AAABAAkJkwYNogD+AAAAAA==.',
Ru='Rubiesue:BAAALgAECgEJAgAAAA==.Runeight:BAAALgADCgIJAQAAAA==.',
Ry='Ryder:BAAALgAECgIJBAAAAA==.',
['Ró']='Rómëo:BAACLgAFFH8VAAIIAAcJRBkUDgCyAQAIAAcJRBkUDgCyAQAuAAQKf1cAAggACQloJlcAAJYDAAgACQloJlcAAJYDAAAA.',
Sa='Sabbatical:BAAALgADCgEJAQAAAA==.Sacon:BAAALgAECgEJAQABLgAFFAMJBAANAAAAAA==.Sahmeah:BAAALgAECgYJCQAAAA==.Saintzan:BAAALgAECgkJEQAAAA==.Salivan:BAAALgAECgUJCgAAAA==.San:BAAALgAECgYJDwAAAA==.Sanketsu:BAAALgADCgYJCwABLgAECgkJLgACAFkWAA==.Sardonyx:BAAALgAECgQJDQAAAA==.Sathariel:BAAALgAECgIJAgAAAA==.',
Sc='Scalyboyos:BAABLgAECn8mAAMTAAkJcwwJGQBEAQATAAgJwwsJGQBEAQARAAEJxwcBkQA5AAAAAA==.Schmoop:BAACLgAFFH8dAAMMAAkJTSLjAAAhAwAMAAkJTSLjAAAhAwAXAAEJoxLxHABGAAAuAAQKfzIABAwACQnHI1AJALkCAAwACAnyI1AJALkCABcABgmLGvwvAFABACQAAwnkEttaAJQAAAAA.',
Se='Seldaria:BAAALgAECgYJEAAAAA==.Sellari:BAAALgAECgQJCwAAAA==.Senza:BAABLgAECn8nAAICAAkJEwvJJwC6AAACAAkJEwvJJwC6AAAAAA==.Senzyri:BAABLgAECn8mAAIBAAkJLxNFPgDoAQABAAkJLxNFPgDoAQAAAA==.Sephirath:BAAALgAECgIJAgAAAA==.Serote:BAAALgADCgcJBwAAAA==.Setmabone:BAAALgADCgkJCQABLgAECggJEwANAAAAAA==.Sevilo:BAAALgADCgkJCwABLgAECgIJAgANAAAAAA==.',
Sh='Shamagoth:BAAALgAECgYJBgAAAA==.Shambhala:BAAALgAECgYJEwAAAA==.Shockwàve:BAAALgAECgEJAQAAAA==.Shoes:BAAALgAECgUJCAAAAA==.Shymyst:BAAALgAFFAEJAgABLgAFFAUJFwAGAEoSAA==.',
Si='Simic:BAABLgAECn9cAAIQAAkJqRfvAgASAgAQAAkJqRfvAgASAgAAAA==.',
Sk='Skre:BAAALgAECgYJBgAAAA==.',
Sl='Sloppy:BAAALgAFFAEJBAABLgAFFAkJHQAMAE0iAA==.',
Sm='Smiddy:BAACLgAFFH8GAAQQAAMJfg/fNQBfAAAhAAIJnAeCIACEAAAQAAIJBRPfNQBfAAAgAAEJ3wbAEgFAAAAuAAQKfxYABBAACQkAFkISAOcBABAACQnPE0ISAOcBACAABQlOB10pAXcAACEAAQk7ICoQAFwAAAAA.Smokeace:BAAALgAECgEJAQAAAA==.',
Sn='Snowthistle:BAABLgAECn8YAAIbAAcJUwe6UwDAAAAbAAcJUwe6UwDAAAAAAA==.',
So='Sorle:BAAALgADCgYJCQABLgAECgkJLgAOANkUAA==.Soulnãris:BAAALgAECgcJCQAAAA==.',
Sp='Spin:BAABLgAFFH8JAAMYAAIJrRmqLgCNAAAYAAIJoxaqLgCNAAAZAAEJIBeqVgBAAAAAAA==.Spudpal:BAAALgADCgEJAQABLgAECgkJLQAkAMYhAA==.Spyro:BAAALgADCgUJBQAAAA==.',
Sq='Squirley:BAAALgAECgQJCAAAAA==.',
St='Starge:BAAALgAECgYJBgAAAA==.Stargefall:BAAALgAECgMJAwAAAA==.Static:BAAALgAECgYJBgAAAA==.Stonymahoney:BAACLgAFFH8JAAICAAQJ8BYEHQAbAQACAAQJ8BYEHQAbAQAuAAQKf0MAAgIACQnHIagJANgBAAIACQnHIagJANgBAAAA.',
Su='Sudokoo:BAAALgADCgMJAwAAAA==.Sumorna:BAAALgAECgEJAQAAAA==.Suraisu:BAACLgAFFH8HAAIOAAMJ1Bw2LAADAQAOAAMJ1Bw2LAADAQAuAAQKfzgAAw4ACQk/JDcDADkDAA4ACQk/JDcDADkDACcAAgkTE0gMAIUAAAAA.Suê:BAAALgADCgEJAQABLgADCgQJBAANAAAAAA==.',
Sv='Sveela:BAACLgAFFH8cAAIaAAYJuCEjBQBmAQAaAAYJuCEjBQBmAQAuAAQKfyQAAhoACQlrIsEDAMoCABoACQlrIsEDAMoCAAAA.Sveelaa:BAABLgAECn8lAAIBAAgJax9cHgBwAgABAAgJax9cHgBwAgABLgAFFAYJHAAaALghAA==.Sveella:BAABLgAECn8UAAMgAAgJ/gtOmAA4AQAgAAcJ8gxOmAA4AQAQAAEJRgadZQAfAAABLgAFFAYJHAAaALghAA==.',
Sw='Swampjimmy:BAAALgAECgkJDAAAAA==.',
Sy='Sylrin:BAAALgADCgcJCgAAAA==.Synap:BAAALgADCgEJAQAAAA==.',
Ta='Tabchan:BAAALgAECgYJBwAAAA==.Tacocat:BAABLgAECn89AAMXAAkJmR77CADZAgAXAAkJmR77CADZAgAMAAEJNAUKlQAlAAAAAA==.Tadeusz:BAAALgADCgIJAgAAAA==.Tahlonia:BAAALgAECgMJAwAAAA==.Talras:BAAALgAECgMJAwAAAA==.',
Te='Temlock:BAABLgAECn83AAIJAAkJPxmuCgBWAQAJAAkJPxmuCgBWAQAAAA==.Tempest:BAAALgAECgUJBQABLgAFFAMJDwAgAFYgAA==.Temtank:BAABLgAECn85AAIQAAkJkiLfAwD8AgAQAAkJkiLfAwD8AgABLgAECgkJNwAJAD8ZAA==.Testerosa:BAAALgAECgEJAQAAAA==.',
Th='Thalagosa:BAAALgADCgkJCQAAAA==.Theidor:BAAALgAECgEJAQAAAA==.',
To='Tosi:BAAALgADCgMJAwAAAA==.',
Tr='Trak:BAABLgAECn8ZAAIRAAgJOQ0FQAApAQARAAgJOQ0FQAApAQAAAA==.Trukarak:BAABLgAECn8uAAICAAkJWRaOSwDkAQACAAkJWRaOSwDkAQAAAA==.',
Tu='Tuvaquitamuu:BAAALgAECgEJAQAAAA==.',
Ur='Uraha:BAAALgADCgEJAQAAAA==.',
Va='Vaeegoldiir:BAAALgAECgEJAQAAAA==.Vaelithria:BAAALgAECgcJCAABLgAFFAcJFQAIAEQZAA==.Valenti:BAABLgAECn8kAAMoAAkJ0A9zFACIAQAoAAkJ0A9zFACIAQACAAEJ0AZVwAEjAAAAAA==.Valor:BAABLgAECn8kAAICAAcJhiEtUgDSAQACAAcJhiEtUgDSAQAAAA==.Vanity:BAAALgADCgMJAwAAAA==.',
Ve='Veliann:BAAALgAECgEJAQAAAA==.Vellatrix:BAAALgAECgQJBgAAAA==.Velynesti:BAAALgAECgQJBAAAAA==.',
Vi='Vipershot:BAAALgADCggJDwAAAA==.',
Wa='Warlode:BAAALgADCgkJDgAAAA==.',
We='Weewoo:BAAALgAECgEJAQAAAA==.Weliiam:BAAALgADCgYJBwAAAA==.',
Wi='Wildama:BAABLgAECn9HAAIGAAkJ7xSrAwATAgAGAAkJ7xSrAwATAgAAAA==.Wildtail:BAABLgAECn8YAAIBAAkJkgo3YQCEAQABAAkJkgo3YQCEAQAAAA==.Windseer:BAAALgAECgcJEAABLgAFFAUJFwABACEZAA==.',
Wr='Wrenwillow:BAAALgAECgIJAgAAAA==.',
Wu='Wumbo:BAAALgADCgEJAQAAAA==.',
Xa='Xarríøn:BAAALgADCgYJBgABLgAFFAMJDQACAB0ZAA==.',
Xh='Xhadowz:BAAALgAFFAEJAQAAAA==.',
Xi='Xiao:BAABLgAECn9RAAMFAAkJZxpDAwBWAgAFAAkJZxpDAwBWAgAYAAgJtBFOBACJAQAAAA==.Xiaolongbao:BAAALgADCgcJDQAAAA==.',
Xy='Xylaini:BAAALgAECgQJBAABLgAFFAEJAQANAAAAAA==.',
Ya='Yahargul:BAABLgAECn8mAAIMAAkJ9w+yIADAAQAMAAkJ9w+yIADAAQAAAA==.',
Yo='Yogafarts:BAAALgAECgYJCAAAAA==.',
Yt='Yt:BAAALgADCgcJDAAAAA==.',
Za='Zanatilli:BAAALgAECgUJDAAAAA==.Zaterok:BAAALgAECgMJAwABLgAECgkJLgACAFkWAA==.',
Ze='Zeik:BAABLgAECn9bAAMoAAkJNyKNAAABAwAoAAkJNyKNAAABAwACAAMJngpiWAFYAAAAAA==.Zephyrgosa:BAAALgADCgcJDgAAAA==.Zerase:BAAALgAECgYJEQAAAA==.',
Zo='Zoomin:BAAALgAECgIJAgAAAA==.',
Zu='Zucco:BAAALgAECgkJDgAAAA==.Zuufungo:BAAALgAECgUJBQABLgAECgkJLQAkAMYhAA==.',
['Zí']='Zíx:BAABLgAECn8oAAInAAkJSxI0GAB+AQAnAAkJSxI0GAB+AQAAAA==.',
['Àl']='Àlcàrà:BAABLgAECn8bAAMQAAgJjQ0rJwAbAQAQAAgJjQ0rJwAbAQAgAAEJDgptIQEzAAAAAA==.',
['Ål']='Åldaren:BAAALgADCgQJBAAAAA==.',
['Æv']='Ævølutîon:BAAALgAECgQJEgAAAA==.',
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
