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

local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Hunter-Marksmanship','DemonHunter-Havoc','Monk-Mistweaver','Druid-Restoration','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Unknown-Unknown','Warrior-Fury','DeathKnight-Blood','Warlock-Destruction','Mage-Frost','Shaman-Enhancement','Priest-Holy','Monk-Windwalker','Monk-Brewmaster','Druid-Guardian','Druid-Balance','Shaman-Restoration','Paladin-Holy','Shaman-Elemental','Rogue-Outlaw','DeathKnight-Unholy','Mage-Arcane','Priest-Discipline','DeathKnight-Frost','Druid-Feral','Hunter-Survival','DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Vengeance','Warrior-Protection','Warrior-Arms','Paladin-Protection',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=46,date='2026-06-13',data={Ad='Adamonious:BAAALgAECgYJCwABLgAECgkJFgABAA8WAA==.Adaware:BAAALgAECgUJBgAAAA==.Addieeboy:BAAALgADCgEJAQAAAA==.Adellea:BAAALgAECgYJBwAAAA==.',
Ai='Aisha:BAAALgAECgEJAgAAAA==.',
Al='Alaponia:BAAALgAECgEJAQAAAA==.Alba:BAABLgAECn8uAAICAAgJkx2jMwAvAgACAAgJkx2jMwAvAgABLgAFFAQJFAABACEZAA==.Aletta:BAAALgAECgYJCwAAAA==.Allast:BAAALgADCgYJDQAAAA==.',
An='Andezard:BAABLgAECn88AAMBAAkJWRe6KAA4AgABAAkJWRe6KAA4AgADAAIJTAlOMgBPAAAAAA==.Angelys:BAABLgAECn8iAAIEAAgJLwh+LQASAQAEAAgJLwh+LQASAQAAAA==.',
Ap='Aphrobitey:BAAALgAECgIJAgAAAA==.',
Aq='Aquâ:BAAALgADCgkJEAABLgAECgkJMQAFAOIYAA==.',
Ar='Arathas:BAAALgADCgcJDAAAAA==.Arianes:BAAALgAECgcJDgAAAA==.Arrowin:BAAALgADCgYJBgAAAA==.Arturias:BAABLgAECn8cAAICAAgJ7hI1aQCaAQACAAgJ7hI1aQCaAQAAAA==.',
At='Athenaowl:BAABLgAECn8VAAIBAAgJfggzeQBIAQABAAgJfggzeQBIAQAAAA==.',
Au='Autofocus:BAABLgAECn8eAAIBAAgJPBr3PwDeAQABAAgJPBr3PwDeAQAAAA==.',
Aw='Aweyna:BAABLgAECn8XAAIGAAkJzAtYUQBHAQAGAAkJzAtYUQBHAQAAAA==.Awisha:BAAALgADCgUJBQAAAA==.',
Ay='Ayanoriko:BAACLgAFFH8PAAIHAAUJ7hS0BAA6AQAHAAUJ7hS0BAA6AQAuAAQKfywAAgcACQnkHxEDAIsCAAcACQnkHxEDAIsCAAAA.Ayasumi:BAAALgAECgIJAgAAAA==.',
Ba='Babaganoosh:BAAALgAECgUJCwAAAA==.Baoyue:BAAALgAECggJCwABLgAFFAYJFAAIAPEaAA==.Barracuda:BAAALgAECgYJBgAAAA==.',
Be='Beans:BAABLgAFFH8OAAMJAAUJFRsvOwBYAQAJAAUJFRsvOwBYAQAKAAEJ4gq+JQBIAAABLgAFFAYJDAALACggAA==.Benmonk:BAAALgAECgMJAwAAAA==.',
Bi='Bifur:BAAALgADCgkJDwAAAA==.Bigbuttflori:BAAALgAECgIJAgABLgAECgMJAwAMAAAAAA==.Bigstones:BAACLgAFFH8JAAINAAMJRQQzPQCrAAANAAMJRQQzPQCrAAAuAAQKfyQAAg0ACQmqDjgsAKEBAA0ACQmqDjgsAKEBAAAA.',
Bl='Blacksavior:BAAALgAECgQJBAAAAA==.Blindbone:BAAALgAECgcJCQABLgAECggJEwAMAAAAAA==.Blisterine:BAAALgAECgYJBgAAAA==.Bluehydra:BAAALgADCgcJCAAAAA==.',
Bo='Bobbydigital:BAABLgAECn86AAIOAAkJvhspCgBuAgAOAAkJvhspCgBuAgAAAA==.Bohd:BAAALgADCgIJAgAAAA==.Bolas:BAAALgAECgUJBgAAAA==.Boneski:BAAALgAECgUJEAAAAA==.Booger:BAAALgAECgQJBAAAAA==.',
Br='Bracynn:BAABLgAECn8gAAIOAAcJ5wfpNQC8AAAOAAcJ5wfpNQC8AAAAAA==.Brixx:BAAALgAECgMJAwAAAA==.Brudiclad:BAABLgAECn8tAAQKAAkJNBQuCgC4AQAKAAkJphIuCgC4AQAJAAYJaQtPpwDzAAAPAAIJzxH2UQB4AAAAAA==.',
Bu='Budfight:BAAALgAECgMJBAAAAA==.Burnt:BAAALgAECgQJBAAAAA==.Butterfinger:BAAALgADCgQJBwAAAA==.Buxxor:BAAALgAECgcJBwAAAA==.',
Ca='Caimark:BAABLgAECn8uAAIQAAgJzgP9xAD+AAAQAAgJzgP9xAD+AAAAAA==.Calahan:BAACLgAFFH8HAAICAAMJgBkrZwDaAAACAAMJgBkrZwDaAAAuAAQKfx4AAgIACAmxGmw0AFACAAIACAmxGmw0AFACAAAA.',
Ch='Chakuneeai:BAAALgADCgYJBgAAAA==.Chancleta:BAAALgAECgYJCQAAAA==.Cherub:BAAALgADCgIJAgAAAA==.Chikostix:BAABLgAECn8tAAIRAAgJ9wmvFwBHAQARAAgJ9wmvFwBHAQAAAA==.Christae:BAABLgAECn8nAAISAAkJNRmrEABdAgASAAkJNRmrEABdAgAAAA==.',
Cl='Clementînê:BAAALgAECgIJAgAAAA==.Clemêntine:BAAALgAECgYJDAAAAA==.Clydè:BAABLgAECn9SAAMTAAkJ6RaHFABJAgATAAgJbheHFABJAgAUAAkJrhK4GwDFAQAAAA==.Cláncey:BAAALgAFFAEJAQAAAA==.',
Co='Coachhazzard:BAAALgAECgQJCwAAAA==.Cocytus:BAAALgADCgIJAgABLgAFFAIJBwAJADkaAA==.Colinferal:BAAALgAFFAEJBAAAAA==.Combatant:BAAALgADCgYJDAAAAA==.Compromise:BAAALgAECgYJCAAAAA==.Compromised:BAACLgAFFH8FAAIEAAMJ1A6nGgDFAAAEAAMJ1A6nGgDFAAAuAAQKfy8AAgQACQneG8AKAHgCAAQACQneG8AKAHgCAAAA.Connalious:BAAALgAECgEJAQAAAA==.Conquests:BAAALgAECgIJAgAAAA==.Corelack:BAACLgAFFH8OAAIVAAUJgxNWEgDrAAAVAAUJgxNWEgDrAAAuAAQKfxcAAxUACQm9DdIkACYBABUACQmZDdIkACYBABYABQmpBTphAI8AAAAA.',
Cr='Crwth:BAAALgAECgUJBQAAAA==.',
Ct='Ctrlaltmagic:BAAALgAECgEJAgAAAA==.',
Cu='Cupis:BAAALgAECgQJBAAAAA==.Curendae:BAABLgAECn8wAAIBAAkJwRfjKwApAgABAAkJwRfjKwApAgAAAA==.',
Da='Dabaldzombie:BAACLgAFFH8TAAIQAAUJoxqPLAAEAQAQAAUJoxqPLAAEAQAuAAQKfxkAAhAACQkSGTxMAFICABAACQkSGTxMAFICAAEuAAUUBgkTABcA6B8A.Daddyshocker:BAABLgAECn8WAAIYAAcJthRqLgCgAQAYAAcJthRqLgCgAQAAAA==.Danamy:BAAALgADCggJDQAAAA==.Daxzazi:BAABLgAECn8cAAMTAAcJ9gNmVgCxAAATAAcJ9gNmVgCxAAAFAAUJrARljgByAAAAAA==.',
De='Deadlee:BAAALgADCgEJAQAAAA==.Deadmanwlkin:BAAALgADCgIJAgAAAA==.Defias:BAAALgADCggJCAAAAA==.Delicious:BAEBLgAFFH8IAAIOAAUJAAsRIwDRAAAOAAUJAAsRIwDRAAABLgAFFAcJEwAZABEVAA==.Despair:BAAALgADCggJDgABLgAFFAQJFAABACEZAA==.',
Di='Dice:BAACLgAFFH8RAAIaAAUJAB7hAwBeAQAaAAUJAB7hAwBeAQAuAAQKfzAAAxoACQllIusAABMDABoACQllIusAABMDAAgAAQmeFMZWAEUAAAAA.Disturbd:BAACLgAFFH8OAAMbAAUJ5ApKfwAFAQAbAAQJ5ApKfwAFAQAOAAEJAACFXQAAAAAuAAQKfxgAAxsACQn9DMVcAK8BABsACQn9DMVcAK8BAA4ABAmJAMY9AFsAAAAA.Disturbian:BAAALgAFFAIJAwABLgAFFAUJDgAbAOQKAA==.Dixierecht:BAABLgAECn8gAAIYAAgJbhu1FwBJAgAYAAgJbhu1FwBJAgAAAA==.',
Do='Docvader:BAAALgAECgEJAwAAAA==.Dodrop:BAAALgADCgYJBwAAAA==.',
Dr='Drunkenhealz:BAAALgAECgUJEAAAAA==.Drvargas:BAAALgAECgQJCwAAAA==.',
['Då']='Dårth:BAAALgAECgEJAQAAAA==.',
['Dè']='Dèrty:BAAALgAECgIJAgAAAA==.',
El='Elenestern:BAABLgAECn81AAIQAAkJahIWRwADAgAQAAkJahIWRwADAgAAAA==.Elmo:BAABLgAECn8oAAMQAAkJHhZnPAAmAgAQAAkJ0BVnPAAmAgAcAAEJwxWjFAA/AAAAAA==.',
Em='Emryssa:BAAALgAECgMJDAAAAA==.',
Er='Erosis:BAACLgAFFH8OAAIQAAUJ/xt/RgBdAQAQAAUJ/xt/RgBdAQAuAAQKfyQAAhAACAlsIwIvALYCABAACAlsIwIvALYCAAAA.',
Es='Esia:BAAALgADCgkJCQAAAA==.',
Ev='Evarg:BAAALgADCgcJDQAAAA==.',
Ez='Ezaratren:BAAALgAECgUJCgABLgAFFAUJDgAVAIMTAA==.',
Fa='Fakêr:BAAALgADCgEJAQAAAA==.',
Fe='Fear:BAACLgAFFH8GAAIJAAMJMxu+HQANAQAJAAMJMxu+HQANAQAuAAQKfygAAwkACAmDIOgrAF8CAAkACAmDIOgrAF8CAA8ABQkbFk4bAHIBAAAA.Felcatalyist:BAABLgAECn8gAAMbAAkJABgcYwDKAQAbAAkJtBUcYwDKAQAOAAgJXA0DKAARAQAAAA==.Felisaty:BAAALgAECgEJAQAAAA==.Fellisaty:BAABLgAECn8WAAIYAAgJfQ90MQCPAQAYAAgJfQ90MQCPAQAAAA==.Felysria:BAAALgAECgQJAgAAAA==.',
Fi='Finvindru:BAAALgAFFAIJAgABLgAFFAQJEwAOAGggAA==.Fistitresk:BAAALgADCgQJBAABLgAECgcJFAAdAIYeAA==.Fistofwayne:BAABLgAECn8cAAIUAAgJMBC/JwBwAQAUAAgJMBC/JwBwAQABLgAFFAYJHQAeAPoeAA==.',
Fr='Frizzalot:BAAALgAECgEJAwAAAA==.Frizzer:BAAALgAECgMJAwAAAA==.',
Ga='Gakopozy:BAAALgAECgYJDwAAAA==.Gambrinos:BAAALgADCgMJAwAAAA==.Gander:BAAALgADCgEJAQABLgAECgEJAQAMAAAAAA==.Gandermon:BAAALgAECgEJAQAAAA==.Garnath:BAAALgADCgYJBgAAAA==.',
Ge='Geg:BAABLgAFFH8FAAIbAAMJvBEhJwD7AAAbAAMJvBEhJwD7AAAAAA==.',
Gl='Glorrex:BAAALgADCgYJBgAAAA==.',
Go='Gongsho:BAAALgAECgQJBgAAAA==.',
Gr='Grapez:BAAALgAFFAIJAgABLgAFFAcJHwAOADEaAA==.Grimlokke:BAAALgADCgIJAgABLgAFFAUJDgAVAIMTAA==.Grïmyst:BAAALgAECgEJAQABLgAFFAUJDgAVAIMTAA==.',
Gu='Guldán:BAAALgAECgYJEQAAAA==.',
Gw='Gwydre:BAACLgAFFH8TAAIOAAQJaCAbEwBTAQAOAAQJaCAbEwBTAQAuAAQKfxUAAg4ACAnqHvYNAC4CAA4ACAnqHvYNAC4CAAAA.',
Ha='Harbard:BAAALgADCgUJBQAAAA==.Havran:BAAALgAECgQJBAABLgAECgkJQwAVABYXAA==.Havrin:BAABLgAECn9DAAMVAAkJFhdXEADeAQAVAAkJFhdXEADeAQAfAAEJQhLgMQA7AAAAAA==.',
He='Headshots:BAACLgAFFH8UAAIBAAQJIRkgOwAxAQABAAQJIRkgOwAxAQAuAAQKfy4AAgEACQmVH10UAJMCAAEACQmVH10UAJMCAAAA.Heartsong:BAAALgAECgEJAQAAAA==.Heavylode:BAAALgAECgMJBAAAAA==.Hexatar:BAAALgAECgQJBAAAAA==.',
Hk='Hkia:BAAALgAFFAMJAwAAAA==.',
Ho='Hoardkiller:BAAALgAECgQJAwABLgAFFAUJFQAgANQNAA==.Holmie:BAAALgADCgkJCgAAAA==.Honk:BAAALgAFFAIJAwAAAA==.Hoofsoflove:BAAALgADCgQJBAAAAA==.Hoogablop:BAABLgAFFH8FAAICAAUJ7xRERAAeAQACAAUJ7xRERAAeAQABLgAFFAYJDAALACggAA==.Hoogaplop:BAACLgAFFH8aAAMOAAUJkybYEgBWAQAbAAUJkybsNACOAQAOAAUJqB/YEgBWAQAuAAQKf0AAAw4ACQlzJH4FAM8CABsACQlWIQMUAAMDAA4ACAkaJH4FAM8CAAEuAAUUBgkMAAsAKCAA.',
Hu='Huamulan:BAABLgAECn9NAAICAAkJdAifhABjAQACAAkJdAifhABjAQAAAA==.',
Ib='Ibc:BAAALgADCgcJDQABLgAFFAIJBAAMAAAAAA==.Ibchilling:BAABLgAECn8pAAIQAAgJxBoWTgDuAQAQAAgJxBoWTgDuAQABLgAFFAIJBAAMAAAAAA==.Ibcorrupted:BAAALgAFFAIJBAAAAA==.',
Ic='Icarrus:BAACLgAFFH8RAAIFAAUJzxGUJgAqAQAFAAUJzxGUJgAqAQAuAAQKfy8AAwUACQnkHLoZAEQCAAUACQnkHLoZAEQCABMABQmTELlLANAAAAEuAAUUBAkIABsAzQsA.Icarus:BAAALgADCgEJAQABLgAFFAQJCAAbAM0LAA==.Iccarus:BAAALgAECgUJBQABLgAFFAQJCAAbAM0LAA==.Icebone:BAAALgAECgcJCgABLgAECggJEwAMAAAAAA==.',
Ig='Ignis:BAACLgAFFH8IAAIbAAQJzQsAegAOAQAbAAQJzQsAegAOAQAuAAQKfxYAAxsABgl5G/OCAFsBABsABgnzGfOCAFsBAB4AAQkRFuE1AD8AAAAA.',
Il='Illioch:BAAALgAECgEJAQAAAA==.',
Im='Imaway:BAAALgAECgEJAQAAAA==.',
In='Inesh:BAAALgADCgEJAQAAAA==.',
Ir='Irrizia:BAAALgADCgkJCgAAAA==.',
Is='Iseldra:BAAALgADCggJDgAAAA==.',
['Iç']='Içyhot:BAAALgAECgEJBAABLgAECgcJEwAMAAAAAA==.',
Ja='Jackbfistn:BAAALgAECggJEwAAAA==.Jaskim:BAABLgAECn8dAAMbAAkJzAyyXgCqAQAbAAkJzAyyXgCqAQAeAAIJ2AXPNABEAAAAAA==.',
Je='Jeses:BAAALgAECgUJCQABLgAECgkJLwACAEIWAA==.',
Jo='Jolty:BAAALgAECgEJAQABLgAFFAYJGQAbAFEgAA==.Jooni:BAAALgADCggJDwAAAA==.Jordomon:BAABLgAECn8bAAMWAAcJWwaNTgDOAAAWAAcJTwaNTgDOAAAfAAMJ8gaKPQBfAAAAAA==.',
Jy='Jyundiel:BAAALgADCgYJBgABLgADCgYJBgAMAAAAAA==.',
['Jú']='Júliët:BAAALgAECgIJAgAAAA==.',
Ka='Kaazaama:BAAALgADCgYJBgAAAA==.Kahtonah:BAAALgADCgMJAwAAAA==.Kalessin:BAAALgADCgkJDgABLgAECgMJBAAMAAAAAA==.Kaltaan:BAABLgAECn8sAAQdAAkJxiE/BgAcAwAdAAkJxiE/BgAcAwASAAQJUh8jPABKAQALAAEJ4R1LcwBWAAAAAA==.Karasan:BAABLgAECn8jAAIBAAkJ0BdZLwAaAgABAAkJ0BdZLwAaAgAAAA==.Karenas:BAABLgAECn8mAAMQAAkJ6CD8DwD5AgAQAAkJ6CD8DwD5AgAcAAIJ4QqZFgBmAAAAAA==.Karr:BAABLgAECn8XAAICAAgJNAdksgAZAQACAAgJNAdksgAZAQAAAA==.Kataraara:BAACLgAFFH8HAAIUAAQJRiAyFwBiAQAUAAQJRiAyFwBiAQAuAAQKfxcAAhQACAntJN4EADwDABQACAntJN4EADwDAAEuAAUUBgkgAA4ABCYA.Katbeans:BAABLgAECn8pAAQFAAkJeRsJDgC5AgAFAAkJeRsJDgC5AgAUAAUJIQ6RYgC4AAATAAEJJhZMkgA7AAAAAA==.Kathrynne:BAAALgAECgUJCQAAAA==.Katmai:BAAALgADCgEJAQAAAA==.Katrielle:BAAALgAECgUJBQAAAA==.Kaykoh:BAAALgAFFAIJBAAAAA==.',
Ke='Kelicemoon:BAABLgAECn8oAAMJAAkJZgpaYQB8AQAJAAkJSQlaYQB8AQAPAAcJIQd2MABYAAABLgAECgkJQQACAJoXAA==.Kemono:BAAALgADCgYJBgAAAA==.',
Kh='Khaliope:BAABLgAECn82AAIhAAkJpQ38dQAxAQAhAAkJpQ38dQAxAQAAAA==.Khat:BAAALgADCgkJCQAAAA==.',
Ki='Kiara:BAACLgAFFH8ZAAMiAAYJ8xbNEQBvAQAiAAUJVxnNEQBvAQAjAAIJWhZ6RACxAAAuAAQKfy0AAyIACQlpH1QIALUCACIACQlpH1QIALUCACMABAm9Ew5KAAABAAAA.Kiryu:BAAALgAECgUJBQAAAA==.',
Ko='Korzari:BAAALgADCgEJAQAAAA==.Koven:BAAALgADCgcJCQAAAA==.',
Kr='Krogers:BAAALgAECgUJCwABLgAECgYJCwAMAAAAAA==.',
Ku='Kumojo:BAAALgAECgkJAgAAAA==.',
Ky='Kyndlearya:BAAALgAECgEJAQAAAA==.',
['Kû']='Kûrr:BAAALgAECgEJAQABLgAFFAEJAQAMAAAAAA==.',
La='Lahrnaon:BAAALgAFFAIJAgAAAA==.Laxeron:BAABLgAECn8iAAINAAkJQCQkBQAOAwANAAkJQCQkBQAOAwAAAA==.',
Le='Leotherassy:BAAALgAECgYJCQAAAA==.Leychron:BAAALgAECgEJAQAAAA==.',
Li='Lightsworn:BAAALgAECgEJAQAAAA==.Lilin:BAAALgAECgYJBwAAAA==.',
Lo='Longboneman:BAAALgAECgIJAgABLgAECggJEwAMAAAAAA==.Lotiel:BAAALgAECgMJCQABLgAFFAUJFwAGAEoSAA==.',
Lu='Lucrecia:BAABLgAECn8WAAMhAAYJbB0oUgCuAQAhAAUJ2iEoUgCuAQAkAAEJswudLAAuAAAAAA==.',
Ly='Lymara:BAAALgADCgcJCAAAAA==.Lynthirae:BAAALgADCgcJDAAAAA==.',
['Lø']='Lørðzêdd:BAAALgAECgQJEgAAAA==.',
Ma='Madmabel:BAAALgADCgQJBAAAAA==.Mahkaidook:BAAALgADCgYJBgAAAA==.Mal:BAAALgADCgkJCQABLgAECgYJBgAMAAAAAA==.Manyace:BAAALgAECgQJBgAAAA==.',
Mc='Mcbodhran:BAABLgAECn8gAAICAAkJDA8HdwB+AQACAAkJDA8HdwB+AQAAAA==.Mcfeast:BAABLgAECn8ZAAILAAgJ+A9oKgB9AQALAAgJ+A9oKgB9AQAAAA==.',
Me='Medra:BAABLgAECn8uAAQNAAkJ2RQHHwD1AQANAAkJ2RQHHwD1AQAlAAQJEgP4PwBsAAAmAAIJ2wZ5agBHAAAAAA==.Meowdi:BAAALgAECgMJBAAAAA==.Merogoth:BAAALgADCgUJBwAAAA==.Mestrois:BAABLgAECn9AAAIQAAgJRAdwoAA3AQAQAAgJRAdwoAA3AQAAAA==.',
Mi='Minibone:BAAALgAECgMJAwABLgAECggJEwAMAAAAAA==.Mixr:BAAALgADCgQJAwAAAA==.',
Mo='Monana:BAAALgAECgMJAwAAAA==.Morar:BAAALgAECgUJDAAAAA==.Morul:BAAALgAECgQJBAAAAA==.',
Ms='Msprettÿp:BAAALgADCgIJAgAAAA==.',
Mu='Murimlinn:BAAALgADCgMJAwAAAA==.Mustafa:BAAALgAECgUJCAAAAA==.',
Na='Nanija:BAAALgAECgMJBAAAAA==.Narushi:BAAALgAECgQJBQAAAA==.',
Ne='Nezrin:BAAALgADCgQJBwAAAA==.',
Ni='Nightcat:BAAALgAECgQJBQAAAA==.Nitebäne:BAAALgADCggJCAAAAA==.Nitesbane:BAAALgADCgYJBgABLgAECgkJHAACACwgAA==.Nitesbåne:BAAALgADCgcJBwAAAA==.Niteshiftah:BAAALgADCgcJBwAAAA==.Nitestorm:BAAALgAECgQJBAAAAA==.Nivaniraa:BAAALgAECgEJAgAAAA==.Nixie:BAABLgAECn8uAAMGAAkJEgZhYQAOAQAGAAkJEgZhYQAOAQAWAAkJ8gQgQwD8AAAAAA==.',
No='Nobonesjones:BAACLgAFFH8LAAIEAAUJlQacBgDfAAAEAAUJlQacBgDfAAAuAAQKfxsAAgQACQlPFjMeAM4BAAQACQlPFjMeAM4BAAAA.',
Og='Oguricap:BAAALgADCgcJBwAAAA==.Ogwarshock:BAACLgAFFH8PAAQJAAUJxhoQTAApAQAJAAQJHRYQTAApAQAPAAEJChv9JABKAAAKAAEJAABOMAAAAAAuAAQKfyQAAwkACQk0Ip8gAF8CAAkABwm0IZ8gAF8CAA8ABQm9HzkaAHsBAAAA.',
Ok='Okkotsu:BAAALgAECgIJAwAAAA==.Okote:BAAALgAECgMJAwAAAA==.',
Ol='Oliiver:BAABLgAECn8zAAIBAAkJ/SD7CQAFAwABAAkJ/SD7CQAFAwAAAA==.',
Om='Omni:BAAALgAECgEJAQABLgAFFAUJDgAVAIMTAA==.Omnivore:BAAALgADCgcJCAAAAA==.Omën:BAAALgAECgQJBAABLgAECgQJCAAMAAAAAA==.',
On='Oniichan:BAAALgAECgQJBQAAAA==.',
Or='Orbeez:BAABLgAECn8oAAIhAAkJNyCrFACaAgAhAAkJNyCrFACaAgAAAA==.',
Pa='Pack:BAAALgAECgcJAQAAAA==.Paladlin:BAAALgADCgYJBgAAAA==.Panaceus:BAABLgAECn86AAIiAAkJ1yLLAQBsAwAiAAkJ1yLLAQBsAwAAAA==.Paragon:BAAALgADCgkJDQABLgAFFAMJDgAbAFYgAA==.Patron:BAAALgAECgIJAgAAAA==.',
Pe='Pepe:BAAALgAECgMJAwAAAA==.Perennial:BAAALgAECgYJCQAAAA==.Perpetrator:BAAALgAECgYJBwAAAA==.',
Ph='Phreeq:BAEALgAECgYJDgABLgAECggJMAAYAJQSAA==.Phrequency:BAEBLgAECn8wAAMYAAgJlBKuJgDRAQAYAAgJlBKuJgDRAQACAAgJ+BEebwCNAQAAAA==.',
Pi='Piety:BAAALgADCgIJAgABLgAECgYJBgAMAAAAAA==.Pig:BAAALgAECgEJAQABLgAFFAYJDAALACggAA==.',
Pl='Plazma:BAAALgAECgEJAQAAAA==.Plazmafury:BAABLgAFFH8KAAMNAAYJ5g91EQB1AQANAAYJZw51EQB1AQAmAAEJyA3sPwBDAAAAAA==.Plazmaglaive:BAAALgAFFAEJAQAAAA==.Plumsham:BAAALgADCgQJBAAAAA==.',
Po='Poisonóus:BAACLgAFFH8PAAIOAAUJrBh+GQAWAQAOAAUJrBh+GQAWAQAuAAQKfzMAAg4ACQmeHRcKAG8CAA4ACQmeHRcKAG8CAAAA.Polyxo:BAAALgAECgIJAgAAAA==.',
Pr='Profang:BAAALgAECgQJBAAAAA==.',
Py='Pyrelic:BAABLgAFFH8ZAAITAAUJgRqTEQArAQATAAUJgRqTEQArAQAAAA==.Pyroela:BAAALgAECgUJCgABLgAFFAQJEwAOAGggAA==.',
['Pö']='Pöncho:BAAALgAECgEJAQAAAA==.',
Qa='Qayllera:BAAALgAECgUJDwAAAA==.',
Qe='Qelcie:BAAALgAECgQJBQAAAA==.',
Qu='Quixotic:BAAALgADCgUJBgAAAA==.Quizet:BAAALgADCgYJCgAAAA==.',
Ra='Radicchio:BAAALgADCgkJBQAAAA==.Radkeem:BAABLgAECn8YAAIOAAkJiB3hCACEAgAOAAkJiB3hCACEAgAAAA==.Raf:BAAALgAECgYJBwAAAA==.Raizo:BAAALgAECgMJBgAAAA==.Rakeem:BAAALgAECgcJEAABLgAECgkJGAAOAIgdAA==.Ralivan:BAAALgADCgEJAQAAAA==.Ravenhawk:BAAALgADCgQJCAAAAA==.Razorknight:BAAALgAECgEJAQAAAA==.',
Re='Redtoxin:BAAALgAECgMJBAAAAA==.Reilley:BAACLgAFFH8XAAIbAAUJAxomYQAxAQAbAAUJAxomYQAxAQAuAAQKfzMAAhsACQnxIDINAAEDABsACQnxIDINAAEDAAAA.Reilleÿ:BAAALgAECgQJBAABLgAFFAUJFwAbAAMaAA==.Reko:BAAALgAECgYJCwAAAA==.Remorsa:BAABLgAECn8XAAMCAAcJxBujTgDaAQACAAcJxBujTgDaAQAYAAQJJRXOVwAcAQAAAA==.Renni:BAABLgAECn8sAAIJAAkJxBZILAAmAgAJAAkJxBZILAAmAgABLgAECgkJHwAUAOAYAA==.Reshath:BAAALgADCgEJAQAAAA==.Reznor:BAABLgAECn8kAAIYAAkJLBbDJwDtAQAYAAkJLBbDJwDtAQAAAA==.',
Ri='Rinela:BAAALgADCgcJBwAAAA==.Riselle:BAAALgAFFAEJAgAAAA==.',
Ro='Rosealia:BAABLgAECn8XAAIBAAcJ/QUMnwD+AAABAAcJ/QUMnwD+AAAAAA==.',
Ru='Runeight:BAAALgADCgIJAQAAAA==.',
Ry='Ryder:BAAALgAECgIJBAAAAA==.',
['Ró']='Rómëo:BAACLgAFFH8UAAIIAAYJ8RoWDQC0AQAIAAYJ8RoWDQC0AQAuAAQKf1cAAggACQloJlIAAJcDAAgACQloJlIAAJcDAAAA.',
Sa='Sabbatical:BAAALgADCgEJAQAAAA==.Sacon:BAAALgAECgEJAQABLgAECgYJBgAMAAAAAA==.Sahmeah:BAAALgAECgYJCAAAAA==.Saintzan:BAAALgAECgkJEQAAAA==.Salivan:BAAALgAECgUJCgAAAA==.San:BAAALgAECgYJDwAAAA==.Sanketsu:BAAALgADCgYJCwABLgAECgkJKwACAFYUAA==.Sathariel:BAAALgAECgIJAgAAAA==.',
Sc='Scalyboyos:BAABLgAECn8mAAMiAAkJcwy6GABEAQAiAAgJwwu6GABEAQAjAAEJxwdqjgA5AAAAAA==.Schmoop:BAACLgAFFH8MAAILAAYJKCDBCQC9AQALAAYJKCDBCQC9AQAuAAQKfy8ABAsACAnyIycJALsCAAsACAnyIycJALsCABIABgmLGiYvAFABAB0AAQnxEGNWADQAAAAA.',
Se='Seldaria:BAAALgAECgYJEAAAAA==.Senza:BAABLgAECn8hAAICAAcJZQqluQAPAQACAAcJZQqluQAPAQAAAA==.Senzyri:BAABLgAECn8mAAIBAAkJLxPiPADoAQABAAkJLxPiPADoAQAAAA==.Sephirath:BAAALgAECgIJAgAAAA==.Serote:BAAALgADCgcJBwAAAA==.Setmabone:BAAALgADCgkJCQABLgAECggJEwAMAAAAAA==.Sevilo:BAAALgADCgkJCwABLgAECgIJAgAMAAAAAA==.',
Sh='Shamagoth:BAAALgAECgYJBgAAAA==.Shambhala:BAAALgAECgYJEgAAAA==.Shoes:BAAALgAECgUJBwAAAA==.Shymyst:BAAALgAFFAEJAgABLgAFFAUJFwAGAEoSAA==.',
Si='Simic:BAABLgAECn82AAIOAAkJ7xG6FQC7AQAOAAkJ7xG6FQC7AQAAAA==.',
Sk='Skre:BAAALgAECgYJBgAAAA==.',
Sm='Smiddy:BAABLgAFFH8GAAQOAAMJfg9tMwBmAAAeAAIJnAfpHgCEAAAOAAIJBRNtMwBmAAAbAAEJ3wbOCAFDAAAAAA==.Smokeace:BAAALgAECgEJAQAAAA==.',
Sn='Snowthistle:BAABLgAECn8WAAIWAAcJQgVPUgDAAAAWAAcJQgVPUgDAAAAAAA==.',
So='Sorle:BAAALgADCgYJCQABLgAECgkJLgANANkUAA==.Soulnãris:BAAALgAECgcJCQAAAA==.',
Sp='Spin:BAABLgAFFH8JAAMTAAIJrRkVLQCNAAATAAIJoxYVLQCNAAAUAAEJIBcxVQBBAAAAAA==.Spudpal:BAAALgADCgEJAQABLgAECgkJLAAdAMYhAA==.Spyro:BAAALgADCgUJBQAAAA==.',
Sq='Squirley:BAAALgAECgQJCAAAAA==.',
St='Starge:BAAALgAECgYJBgAAAA==.Stargefall:BAAALgAECgMJAwAAAA==.Static:BAAALgAECgYJBgAAAA==.Stonymahoney:BAABLgAECn89AAICAAkJwxo2JQBuAgACAAkJwxo2JQBuAgAAAA==.',
Su='Sudokoo:BAAALgADCgMJAwAAAA==.Sumorna:BAAALgAECgEJAQAAAA==.Suraisu:BAACLgAFFH8HAAINAAMJ1BykKgAEAQANAAMJ1BykKgAEAQAuAAQKfzUAAg0ACQk/JBQDADwDAA0ACQk/JBQDADwDAAAA.Suê:BAAALgADCgEJAQABLgADCgQJBAAMAAAAAA==.',
Sv='Sveela:BAACLgAFFH8TAAIVAAUJpiKTBgCIAQAVAAUJpiKTBgCIAQAuAAQKfyQAAhUACQlrIsEDAMoCABUACQlrIsEDAMoCAAAA.Sveelaa:BAABLgAECn8lAAIBAAgJax9kHQBxAgABAAgJax9kHQBxAgABLgAFFAUJEwAVAKYiAA==.Sveella:BAABLgAECn8UAAMbAAgJ/gtqlQA6AQAbAAcJ8gxqlQA6AQAOAAEJRgY2ZAAfAAABLgAFFAUJEwAVAKYiAA==.',
Sw='Swampjimmy:BAAALgAECgkJDAAAAA==.',
Sy='Sylrin:BAAALgADCgcJCgAAAA==.Synap:BAAALgADCgEJAQAAAA==.',
Ta='Tabchan:BAAALgAECgYJBwAAAA==.Tacocat:BAABLgAECn89AAMSAAkJmR7LCADaAgASAAkJmR7LCADaAgALAAEJNAU2kgAlAAAAAA==.Tadeusz:BAAALgADCgEJAQAAAA==.Talras:BAAALgAECgMJAwAAAA==.',
Te='Temlock:BAABLgAECn8yAAIJAAkJFxgsMQBIAgAJAAkJFxgsMQBIAgAAAA==.Tempest:BAAALgAECgUJBQABLgAFFAMJDgAbAFYgAA==.Temtank:BAABLgAECn84AAIOAAkJkiLBAwD/AgAOAAkJkiLBAwD/AgABLgAECgkJMgAJABcYAA==.',
Tr='Trak:BAABLgAECn8ZAAIjAAgJOQ0ePwAqAQAjAAgJOQ0ePwAqAQAAAA==.Trukarak:BAABLgAECn8rAAICAAkJVhRwSgDlAQACAAkJVhRwSgDlAQAAAA==.',
Tu='Tuvaquitamuu:BAAALgAECgEJAQAAAA==.',
Va='Vaeegoldiir:BAAALgAECgEJAQAAAA==.Vaelithria:BAAALgAECgcJCAABLgAFFAYJFAAIAPEaAA==.Valenti:BAABLgAECn8kAAMnAAkJ0A8xFACHAQAnAAkJ0A8xFACHAQACAAEJ0Ab4sgEmAAAAAA==.Valor:BAABLgAECn8kAAICAAcJhiHQPQAtAgACAAcJhiHQPQAtAgAAAA==.Vanity:BAAALgADCgMJAwAAAA==.',
Ve='Veliann:BAAALgAECgEJAQAAAA==.Vellatrix:BAAALgAECgQJBgAAAA==.Velynesti:BAAALgAECgQJBAAAAA==.',
Vi='Vipershot:BAAALgADCggJDwAAAA==.',
Wa='Warlode:BAAALgADCgkJDgAAAA==.',
We='Weewoo:BAAALgADCgcJCwAAAA==.',
Wi='Wildama:BAABLgAECn8qAAIGAAkJSBKhLQDuAQAGAAkJSBKhLQDuAQAAAA==.Wildtail:BAABLgAECn8UAAIBAAkJxwhaXwCEAQABAAkJxwhaXwCEAQAAAA==.Windseer:BAAALgAECgMJAwABLgAFFAQJFAABACEZAA==.',
Wr='Wrenwillow:BAAALgAECgIJAgAAAA==.',
Wu='Wumbo:BAAALgADCgEJAQAAAA==.',
Xa='Xarríøn:BAAALgADCgYJBgABLgAFFAMJCwACAB0ZAA==.',
Xh='Xhadowz:BAAALgAECgEJAgAAAA==.',
Xi='Xiao:BAABLgAECn8zAAMFAAkJQBjqFgBcAgAFAAkJQBjqFgBcAgATAAYJjQqoOgATAQAAAA==.',
Xy='Xylaini:BAAALgAECgQJBAABLgAFFAEJAQAMAAAAAA==.',
Ya='Yahargul:BAABLgAECn8mAAILAAkJ9w9fHwDJAQALAAkJ9w9fHwDJAQAAAA==.',
Yo='Yogafarts:BAAALgAECgYJCAAAAA==.',
Yt='Yt:BAAALgADCgYJBgAAAA==.',
Za='Zanatilli:BAAALgAECgEJAQAAAA==.Zaterok:BAAALgAECgMJAwABLgAECgkJKwACAFYUAA==.',
Ze='Zeik:BAABLgAECn84AAMnAAkJPB+/AwDPAgAnAAkJPB+/AwDPAgACAAMJngqATwFbAAAAAA==.Zephyrgosa:BAAALgADCgcJDgAAAA==.Zerase:BAAALgAECgMJBAAAAA==.',
Zu='Zucco:BAAALgAECgkJDgAAAA==.Zuufungo:BAAALgAECgUJBQABLgAECgkJLAAdAMYhAA==.',
['Zí']='Zíx:BAABLgAECn8oAAIlAAkJSxLTFwB/AQAlAAkJSxLTFwB/AQAAAA==.',
['Àl']='Àlcàrà:BAABLgAECn8ZAAMOAAcJcA+LJgAcAQAOAAcJcA+LJgAcAQAbAAEJDgptIQEzAAAAAA==.',
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
