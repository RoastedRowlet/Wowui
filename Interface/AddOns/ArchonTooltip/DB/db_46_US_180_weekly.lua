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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Unknown-Unknown','Warrior-Fury','Warlock-Destruction','Warlock-Affliction','Druid-Restoration','Druid-Balance','Paladin-Retribution','Druid-Guardian','Paladin-Protection','Hunter-Marksmanship','DeathKnight-Unholy','Paladin-Holy','Mage-Frost','DemonHunter-Devourer','Rogue-Subtlety','Warrior-Protection','Evoker-Augmentation','Monk-Brewmaster','Priest-Discipline','Priest-Shadow','Monk-Mistweaver','Hunter-Survival','Evoker-Devastation','Evoker-Preservation','Monk-Windwalker','Warrior-Arms','Druid-Feral','Shaman-Elemental','DemonHunter-Havoc','Priest-Holy','Shaman-Restoration','Shaman-Enhancement','Mage-Arcane','DemonHunter-Vengeance','DeathKnight-Blood','Mage-Fire','DeathKnight-Frost',}
local provider = {region='US',realm='Rivendare',name='US',type='weekly',zone=46,date='2026-06-06',data={Ai='Aisling:BAAALgADCgYJBgAAAA==.',
Al='Alanispally:BAAALgADCgIJAQAAAA==.Algryn:BAAALgADCgUJBQAAAA==.Alkanz:BAABLgAECn8UAAIBAAkJKQwxYACpAQABAAkJKQwxYACpAQAAAA==.Allinaa:BAABLgAECn8cAAICAAkJwQ6sSwCyAQACAAkJwQ6sSwCyAQAAAA==.Alya:BAAALgAECgIJAwAAAA==.',
Am='Amorvea:BAAALgADCgUJBQABLgAECgIJAgADAAAAAA==.',
An='Angron:BAAALgADCgIJBQAAAA==.Anika:BAACLgAFFH8LAAIEAAMJ+gN7OACyAAAEAAMJ+gN7OACyAAAuAAQKfzMAAgQACQnrDDEsAJsBAAQACQnrDDEsAJsBAAAA.Antilight:BAAALgAECgcJAQAAAA==.',
Ar='Arcade:BAAALgAECgEJAgAAAA==.Arlyx:BAACLgAFFH8QAAMBAAUJRR7lUgAUAQABAAQJBSDlUgAUAQAFAAIJzxOXHABWAAAuAAQKfygABAEACAkTH3ctAB0CAAEABwlCG3ctAB0CAAUAAwnzFohHAJgAAAYAAgnoBzQfAHcAAAAA.Arnwaz:BAABLgAECn8UAAMHAAgJ7xUbMADYAQAHAAgJ7xUbMADYAQAIAAEJUw5+hQAzAAAAAA==.Arthuria:BAAALgAECggJDQAAAA==.',
As='Aslan:BAAALgADCgQJBwAAAA==.',
At='Atelwen:BAAALgAECgcJBwAAAA==.',
Av='Avelyn:BAAALgAFFAIJAwAAAA==.',
Ba='Babyruthie:BAAALgAECgMJBAAAAA==.Baf:BAACLgAFFH8MAAIJAAQJaxcaPgAgAQAJAAQJaxcaPgAgAQAuAAQKfxwAAgkACQmaHYY+ACsCAAkACQmaHYY+ACsCAAAA.Bayside:BAAALgAECgYJEQAAAA==.',
Be='Bearfomat:BAABLgAFFH8FAAIKAAMJFh6qDQAHAQAKAAMJFh6qDQAHAQAAAA==.Beefis:BAAALgAECgUJCwAAAA==.Beenjuicin:BAAALgAFFAEJAgABLgAFFAIJAgADAAAAAA==.Berfomat:BAACLgAFFH8FAAILAAQJfBTdBgADAQALAAQJfBTdBgADAQAuAAQKfysAAgsACQnUIQsDAOQCAAsACQnUIQsDAOQCAAAA.',
Bi='Bingchilling:BAACLgAFFH8bAAIMAAUJRBbpCgBrAQAMAAUJRBbpCgBrAQAuAAQKfzIAAgwACQkFHiIEAG0CAAwACQkFHiIEAG0CAAAA.',
Bj='Bjorn:BAABLgAECn8UAAINAAgJfRdBQgD0AQANAAgJfRdBQgD0AQAAAA==.',
Bl='Bloodyfupa:BAAALgAECgIJAQAAAA==.Bloomyvfd:BAACLgAFFH8FAAIOAAMJtgN2NQCIAAAOAAMJtgN2NQCIAAAuAAQKfzIAAg4ACAmYHg8OAKgCAA4ACAmYHg8OAKgCAAAA.',
Bo='Bombuur:BAAALgAECgQJCAAAAA==.Bonniebadass:BAABLgAECn8VAAIJAAgJRAr9lQA8AQAJAAgJRAr9lQA8AQAAAA==.Bottle:BAABLgAECn8WAAIEAAgJrxsFHAAHAgAEAAgJrxsFHAAHAgAAAA==.Boxxylove:BAAALgAECgQJBwABLgAECgIJAwADAAAAAA==.',
Br='Bravas:BAAALgAECgcJBQAAAA==.Brimscythe:BAAALgADCgQJBAAAAA==.Broxar:BAAALgADCgcJCwAAAA==.',
['Bî']='Bîa:BAABLgAECn8gAAIJAAgJuyKgGwCVAgAJAAgJuyKgGwCVAgAAAA==.',
Ca='Cablemstache:BAAALgADCgcJBwAAAA==.Calisti:BAABLgAECn8tAAIPAAcJ/xvVZgAJAgAPAAcJ/xvVZgAJAgAAAA==.Capybubger:BAABLgAECn8VAAIQAAgJiB62GQBwAgAQAAgJiB62GQBwAgABLgAFFAcJGAARAMMjAA==.Cavalis:BAACLgAFFH8NAAQBAAQJ4RIGbQDYAAABAAMJcg8GbQDYAAAFAAEJGxF8HwBRAAAGAAEJhhA1HwBPAAAuAAQKfzMABAEACQmTGy80AAMCAAEACAm3GS80AAMCAAYABQmyF7ESAAEBAAUABAlsHIMVAO8AAAAA.',
Ce='Ceedh:BAAALgAFFAMJBAAAAA==.Ceejr:BAACLgAFFH8bAAMEAAgJhCKlAQDoAQASAAYJrSCcBAD1AQAEAAUJ5iKlAQDoAQAuAAQKfyoAAwQACQlpJSQBAMQDAAQACQlpJSQBAMQDABIABgmLIkkPAOYBAAAA.Cerovallen:BAAALgAECgYJCQAAAA==.',
Ch='Chailee:BAAALgADCgEJAQAAAA==.Cherish:BAAALgADCgMJAwABLgAECgUJCgADAAAAAA==.Chillum:BAAALgAECgIJAgABLgAFFAUJEgATAKMWAA==.Chimneybeans:BAAALgADCgcJBwAAAA==.',
Co='Corny:BAAALgAECgUJCwAAAA==.',
Cr='Creativez:BAACLgAFFH8IAAIUAAIJxRmzGACoAAAUAAIJxRmzGACoAAAuAAQKfxYAAhQABwkIJK8OAKsCABQABwkIJK8OAKsCAAEuAAUUBAkKAAoAPhsA.Creativezd:BAABLgAFFH8KAAIKAAQJPhumCQA8AQAKAAQJPhumCQA8AQAAAA==.',
Da='Dadgoo:BAAALgAECgYJDAAAAA==.Damnskippy:BAAALgAECgcJDQAAAA==.Dannÿ:BAABLgAECn8tAAMVAAgJyxbFHADZAQAVAAcJIBjFHADZAQAWAAQJwBBLSADkAAAAAA==.Dantè:BAAALgAECgIJAgAAAA==.Daris:BAAALgADCgMJAwAAAA==.Darkire:BAACLgAFFH8LAAICAAUJPhCXOwArAQACAAUJPhCXOwArAQAuAAQKfyoAAgIACAkhHPszAAECAAIACAkhHPszAAECAAAA.Darkstar:BAAALgADCgUJBQAAAA==.Darkwarriorx:BAAALgADCgQJBAAAAA==.',
De='Deathlegion:BAAALgAECgQJBAAAAA==.Deathroll:BAABLgAECn8oAAIXAAkJNhlnEQCDAgAXAAkJNhlnEQCDAgAAAA==.Delarus:BAAALgAECgEJAQAAAA==.Demonarmor:BAAALgAECgMJCAABLgAECgcJCAADAAAAAA==.',
Di='Diddley:BAAALgADCgMJAwAAAA==.',
Do='Dogmatik:BAAALgAECgEJAQABLgAECgMJAwADAAAAAA==.Dontah:BAAALgADCgcJBwABLgAFFAQJDQAYAJEZAA==.Doomward:BAABLgAECn8oAAINAAgJQhSTWAC0AQANAAgJQhSTWAC0AQAAAA==.Dorien:BAACLgAFFH8NAAIYAAQJkRk/DABUAQAYAAQJkRk/DABUAQAuAAQKfysAAxgACQmoIToFANACABgACQmoIToFANACAAIABAk6HQ5uAFkBAAAA.',
Dr='Drachilly:BAACLgAFFH8SAAITAAUJoxa0JgAcAQATAAUJoxa0JgAcAQAuAAQKfyQABBMACQlcHvUZAP8BABMACQnZHfUZAP8BABkABgknHj0QANgBABoAAQkPApZCABsAAAAA.Dragnar:BAABLgAECn8jAAICAAkJlwzuPQC3AQACAAkJlwzuPQC3AQAAAA==.Drakbonespur:BAAALgAECggJEwAAAA==.Drhealzgood:BAAALgAECgQJBAAAAA==.Droggo:BAAALgADCgIJAgAAAA==.',
Ev='Evilvdduck:BAAALgAECgEJAQAAAA==.',
Ey='Eysia:BAAALgADCgUJCAAAAA==.',
Fa='Faemi:BAAALgAECgEJAgAAAA==.Faewryn:BAABLgAECn8YAAIOAAkJlxHEIADyAQAOAAkJlxHEIADyAQAAAA==.Faeya:BAAALgADCgEJAQABLgADCgUJCAADAAAAAA==.Falekia:BAAALgAECgEJAQAAAA==.Fay:BAACLgAFFH8TAAIUAAUJOxqeGgBAAQAUAAUJOxqeGgBAAQAuAAQKfyIAAhQACQkuInwQADACABQACQkuInwQADACAAAA.',
Fe='Felltown:BAAALgADCgMJAwAAAA==.',
Fi='Firstblood:BAAALgAECgYJCQAAAA==.Fishnchimps:BAABLgAFFH8NAAMXAAMJyRfuLgDTAAAXAAMJyRfuLgDTAAAbAAIJ9AWlMwBoAAAAAA==.',
Fr='Frostyfupa:BAAALgADCgIJAgAAAA==.',
Fu='Fupalicious:BAAALgAECgcJDQABLgAECgUJDQADAAAAAA==.Furrburger:BAAALgADCgIJAgAAAA==.',
Ga='Gaiserik:BAABLgAECn8rAAIcAAkJRCGxAwDjAgAcAAkJRCGxAwDjAgAAAA==.Galenda:BAAALgADCgQJBQAAAA==.Gandolph:BAAALgADCgEJAQAAAA==.Garduhm:BAAALgADCgYJCQABLgAECgIJAgADAAAAAA==.Garlictoast:BAAALgAECgQJBwAAAA==.',
Ge='Gearsofhate:BAAALgAECgEJAgAAAA==.Gehenna:BAAALgADCgYJCgAAAA==.Genga:BAAALgADCgYJBgAAAA==.',
Go='Goldenorder:BAAALgAECggJCgAAAA==.Gome:BAAALgADCgcJGwABLgAFFAMJDQAXAMkXAA==.Goodvbes:BAAALgAECgQJBAAAAA==.',
Gr='Gracile:BAAALgADCgEJAQAAAA==.Gragolf:BAABLgAECn8dAAICAAkJPRMdQgDQAQACAAkJPRMdQgDQAQAAAA==.Greggor:BAAALgAECgYJDQAAAA==.Gronkus:BAAALgAECgYJBwAAAA==.',
Gu='Gustabo:BAABLgAECn8bAAIdAAYJGyIhDQDUAQAdAAYJGyIhDQDUAQAAAA==.',
['Gå']='Gåndalf:BAAALgAECgEJAQAAAA==.',
Ha='Haslin:BAAALgADCgEJAgAAAA==.Havibonespur:BAABLgAECn8XAAMUAAYJXQslSADUAAAUAAYJXQslSADUAAAbAAEJyQQHsAAeAAABLgAECggJEwADAAAAAA==.',
He='Healir:BAABLgAECn8TAAMVAAgJZiKiGAD/AQAVAAgJZiKiGAD/AQAWAAQJnh/ULAB3AQABLgAFFAUJBwATALITAA==.Healmepls:BAAALgADCgYJCgABLgAFFAUJDAAeAHcPAA==.Hellsong:BAAALgAECgEJAQAAAA==.Helor:BAABLgAECn8XAAMQAAkJcRYAPQDIAQAQAAkJcRYAPQDIAQAfAAUJ3RXDLgBXAQAAAA==.',
Hi='Hiéi:BAAALgAECgEJAQAAAA==.',
Ho='Holydeath:BAABLgAECn8YAAIgAAcJwB0/EwAzAgAgAAcJwB0/EwAzAgAAAA==.Hotboydragon:BAABLgAFFH8HAAITAAUJshNtKgALAQATAAUJshNtKgALAQAAAA==.Hotpocketz:BAAALgADCgcJCQABLgAECggJFwAEACoXAA==.',
Hu='Hunterish:BAAALgADCgEJAQAAAA==.',
Ia='Iadrithe:BAAALgADCgYJBgAAAA==.',
In='Inspectadeck:BAAALgAECgMJBAAAAA==.Invisus:BAABLgAECn8WAAIEAAcJZxlaJQDFAQAEAAcJZxlaJQDFAQAAAA==.',
Is='Ispayderj:BAAALgAECgMJBAAAAA==.',
Ja='Jahy:BAAALgADCgIJAgAAAA==.Jake:BAACLgAFFH8MAAIJAAUJ3SDFGgCGAQAJAAUJ3SDFGgCGAQAuAAQKfykAAgkACQkkJhcEAFYDAAkACQkkJhcEAFYDAAAA.Jarlan:BAACLgAFFH8dAAIcAAUJTyMyCQCXAQAcAAUJTyMyCQCXAQAuAAQKfygAAhwACAmRI7sBACMDABwACAmRI7sBACMDAAAA.Jarlhun:BAABLgAECn8dAAIMAAcJjh2DCADoAQAMAAcJjh2DCADoAQABLgAFFAUJHQAcAE8jAA==.',
Je='Jellous:BAACLgAFFH8GAAMQAAIJpQZfgwBoAAAQAAIJBgVfgwBoAAAfAAEJZwv7DQBOAAAuAAQKfyoAAx8ACQmCF5MTADgCAB8ACAl5GJMTADgCABAACQllFN4zACoCAAAA.Jethereal:BAAALgADCgcJBwABLgAFFAIJBgAQAKUGAA==.',
Ju='Jurista:BAAALgADCgYJBgAAAA==.Justin:BAAALgAECgYJBgAAAA==.',
Ke='Ketharion:BAABLgAECn8rAAMOAAkJ5RVIGwAfAgAOAAkJ5RVIGwAfAgAJAAEJiguskAEsAAAAAA==.Kevamin:BAABLgAECn8dAAIJAAcJOBRlgQBhAQAJAAcJOBRlgQBhAQAAAA==.',
Kh='Khaela:BAAALgAECgIJAgAAAA==.Khato:BAAALgAECggJEAAAAA==.',
Ki='Kirasha:BAAALgADCgcJBwAAAA==.',
Ku='Kulfa:BAAALgADCgcJCgAAAA==.Kurailos:BAAALgADCggJCAAAAA==.Kurisu:BAAALgAECgQJCAAAAA==.',
La='Lailyne:BAABLgAECn8fAAQYAAkJ+BOgJQBsAQAYAAcJIA2gJQBsAQAMAAYJ8A2mRgA6AQACAAUJexSskgANAQAAAA==.Lake:BAAALgAECgcJDAAAAA==.Laîlyne:BAAALgAECgYJBgABLgAECgkJHwAYAPgTAA==.',
Le='Learned:BAABLgAECn8UAAINAAgJzAr4hQBPAQANAAgJzAr4hQBPAQAAAA==.Leo:BAABLgAECn8ZAAISAAgJSRx6DQAIAgASAAgJSRx6DQAIAgAAAA==.Leone:BAAALgAECgYJBwAAAA==.',
Li='Lilany:BAACLgAFFH8IAAIhAAMJWQ/mTgCiAAAhAAMJWQ/mTgCiAAAuAAQKfxUAAiEACQlPFsM6ALYBACEACQlPFsM6ALYBAAAA.Lillymeii:BAAALgAECgEJAQAAAA==.Linova:BAAALgADCgUJBQAAAA==.Lithrak:BAABLgAECn8wAAIiAAkJ0B8rBADfAgAiAAkJ0B8rBADfAgAAAA==.',
Lo='Logical:BAAALgAECgYJBgAAAA==.Lorakine:BAAALgADCgUJBQAAAA==.',
Lu='Luciferr:BAAALgADCgEJAQAAAA==.Lucit:BAAALgAECgYJCAABLgAFFAUJEAABAEUeAA==.Lute:BAAALgAECgQJCAAAAA==.',
Ly='Lyric:BAAALgADCgcJDAABLgAFFAUJEwAUADsaAA==.',
['Lá']='Lárien:BAABLgAECn8XAAIHAAcJsxRaQQCCAQAHAAcJsxRaQQCCAQAAAA==.',
Ma='Mable:BAAALgADCggJCAAAAA==.Magicmicah:BAAALgADCgcJBwAAAA==.Manon:BAACLgAFFH8TAAIhAAUJTRnMGQB+AQAhAAUJTRnMGQB+AQAuAAQKfx8AAyEACQn9FBEtANYBACEACQn9FBEtANYBAB4AAQm+B2WrACUAAAAA.',
Mc='Mcchungus:BAACLgAFFH8GAAMYAAMJ2QfBIAC8AAAYAAMJ2gbBIAC8AAACAAIJBgY8fwCGAAAuAAQKfxsAAxgACAlIF34eAKQBABgABwklFH4eAKQBAAIABwmVFQtmAGsBAAAA.',
Me='Meliodas:BAAALgAECgQJBgAAAA==.Menghao:BAABLgAECn8gAAMPAAcJ7AgErAAjAQAPAAcJ7AgErAAjAQAjAAIJ3AFqGgBEAAAAAA==.Meowmixx:BAAALgAECgcJAwAAAA==.',
Mi='Mikayybrew:BAAALgADCgUJBQAAAA==.Mischief:BAACLgAFFH8XAAIGAAUJxRFbBABAAQAGAAUJxRFbBABAAQAuAAQKf0sAAgYACQmhHvQBALwCAAYACQmhHvQBALwCAAAA.',
Mk='Mk:BAEALgAECgQJCQABLgAECgkJQQAbAIAgAA==.',
Mo='Mooage:BAACLgAFFH8GAAIPAAIJYiDBMwDLAAAPAAIJYiDBMwDLAAAuAAQKfzMAAg8ACQmcJBcMAGQDAA8ACQmcJBcMAGQDAAAA.Morewyn:BAABLgAECn8nAAICAAkJVBJROADyAQACAAkJVBJROADyAQAAAA==.Mozoh:BAAALgADCgMJAwABLgAECgIJAgADAAAAAA==.',
Na='Nalock:BAAALgAECgUJBQAAAA==.',
Ne='Nerrgall:BAAALgADCgcJBwAAAA==.',
Ni='Nickignomaj:BAABLgAECn8pAAQbAAgJZB73DABrAgAbAAgJZB73DABrAgAXAAQJLBElRwC+AAAUAAUJswbCWQCcAAABLgAFFAQJCwAcAAMTAA==.Nidhogg:BAAALgADCgcJBwABLgAECgkJIQAhANcaAA==.Nisara:BAABLgAECn8aAAIBAAkJMQr1WACNAQABAAkJMQr1WACNAQAAAA==.',
No='Noellie:BAAALgAFFAEJAgAAAA==.Noobdestroya:BAAALgAECgQJDwAAAA==.Nosfuratu:BAAALgADCgkJCQAAAA==.',
Ny='Nymi:BAAALgADCgYJBgAAAA==.',
Of='Offline:BAAALgADCgcJCwAAAA==.',
Ol='Oldbutcool:BAAALgADCgEJAgAAAA==.Oldicy:BAAALgAECgQJBAAAAA==.',
Om='Omantul:BAABLgAECn8hAAMhAAkJ1xqGIgAQAgAhAAgJDRqGIgAQAgAeAAYJUBl4TQDwAAAAAA==.',
Or='Orangez:BAAALgAECgMJBAAAAA==.',
Ou='Ouija:BAAALgAECgEJAQAAAA==.',
Ow='Owocoxl:BAAALgAECgIJAgABLgAFFAUJEgARALkQAA==.',
Pa='Painfull:BAABLgAECn8jAAIQAAgJpB14LgABAgAQAAgJpB14LgABAgAAAA==.Pants:BAAALgAECgEJAgAAAA==.Pantzor:BAAALgADCgEJAQAAAA==.Paz:BAAALgADCgcJBwABLgAECgIJAgADAAAAAA==.',
Ph='Phakes:BAAALgAECgUJCAAAAA==.Phengzera:BAABLgAECn8WAAIPAAcJMBX3dADoAQAPAAcJMBX3dADoAQAAAA==.Phizz:BAABLgAFFH8KAAIQAAQJaRcaNgA2AQAQAAQJaRcaNgA2AQAAAA==.',
Po='Po:BAAALgADCgcJDQABLgAFFAUJDgAQACARAA==.Pontius:BAAALgADCgMJAwABLgAECgkJDgADAAAAAA==.',
Pr='Prowlborn:BAAALgADCgEJAQAAAA==.',
Pu='Puke:BAABLgAECn8zAAIkAAkJXiVqAABXAwAkAAkJXiVqAABXAwAAAA==.Pumpkinspice:BAAALgADCgYJCQAAAA==.Purplepower:BAAALgAECgMJBAAAAA==.',
Ra='Rarim:BAAALgAECgkJDgAAAA==.',
Re='Reaperfive:BAAALgADCgcJBwAAAA==.Redbonespur:BAAALgADCgcJBwABLgAECggJEwADAAAAAA==.',
Ri='Rimtardo:BAAALgAECgQJBwAAAA==.Rio:BAAALgAECgMJAwABLgAFFAQJCQABAMUQAA==.',
Ro='Rotdaddy:BAABLgAECn8aAAIRAAgJ4BGHLQCVAQARAAgJ4BGHLQCVAQAAAA==.Roxxev:BAAALgADCgcJBwAAAA==.',
Ry='Ryø:BAABLgAECn8jAAMHAAkJsgdkWwBAAQAHAAkJsgdkWwBAAQAKAAgJ3AibMADUAAAAAA==.',
Sa='Saintrandy:BAAALgADCgMJAwAAAA==.Saphiel:BAAALgAECgEJAQAAAA==.',
Sc='Scorch:BAAALgADCgcJCgAAAA==.',
Se='Seraphym:BAAALgADCgYJCAAAAA==.',
Sh='Shaviji:BAAALgAECgcJBwAAAA==.Shinra:BAAALgADCgEJAQABLgAECgcJEQADAAAAAA==.Shore:BAABLgAECn8eAAMYAAkJ8xtNDABbAgAYAAkJ8xtNDABbAgAMAAYJQRKEEwAaAQAAAA==.Shrekw:BAAALgAECgcJEwAAAA==.Shuralya:BAACLgAFFH8ZAAMJAAQJhh0tKQBSAQAJAAQJhh0tKQBSAQAOAAMJURKILgCwAAAuAAQKf0MAAwkACQkhJA8GADsDAAkACQkhJA8GADsDAA4ACQk9GH0gABcCAAAA.',
Si='Silverhorn:BAABLgAECn8UAAITAAgJ0A7MLwBvAQATAAgJ0A7MLwBvAQAAAA==.Siouxsie:BAAALgADCgcJCgAAAA==.',
Sm='Smoldnrg:BAAALgAECgUJBQAAAA==.',
So='Sofka:BAABLgAECn8fAAMlAAkJCQ5uGgB+AQAlAAkJCQ5uGgB+AQANAAEJMgHwOwEbAAAAAA==.Souliel:BAAALgAECgEJAQAAAA==.Sourpatch:BAAALgAECgIJAgAAAA==.',
St='Stilts:BAABLgAECn8UAAMiAAcJpxyCDADcAQAiAAcJpxyCDADcAQAhAAQJsAVNfwCWAAAAAA==.Stradynia:BAAALgAECggJEQAAAA==.Stuart:BAAALgADCgMJAwABLgAECgIJAgADAAAAAA==.Stócky:BAAALgAECgcJEwAAAA==.',
Su='Sui:BAAALgADCgUJCAAAAA==.Survas:BAACLgAFFH8LAAIRAAUJZA4jHAAtAQARAAUJZA4jHAAtAQAuAAQKfyEAAhEACQnsGlsaALcBABEACQnsGlsaALcBAAAA.',
Sw='Swobu:BAAALgAECgEJAQAAAA==.',
Sy='Sylwynn:BAAALgADCgUJCAAAAA==.',
['Sá']='Sárkány:BAAALgADCgcJCQAAAA==.',
Ta='Talanaz:BAAALgAECgYJDAAAAA==.Taleah:BAAALgAECgEJAgAAAA==.Taleb:BAAALgAECgYJEAABLgAECgcJDQADAAAAAA==.Tardor:BAAALgADCgMJAwAAAA==.Tavgoesboom:BAAALgAFFAIJAgABLgAFFAMJDQAXAMkXAA==.Tawna:BAAALgAECgQJBQAAAA==.',
Te='Tealan:BAABLgAECn8VAAQTAAgJuRZGKAB7AQATAAcJSxVGKAB7AQAaAAYJmhTVJwA1AQAZAAEJOQjJQAAvAAAAAA==.Tenyi:BAAALgAECgMJAwAAAA==.Terrin:BAAALgAECgQJBQABLgAECgcJDQADAAAAAA==.',
To='Toospooky:BAABLgAECn8VAAQWAAcJFhgmMwBFAQAWAAYJGhcmMwBFAQAVAAUJXgnFRQDfAAAgAAEJ0AZ4bgAnAAAAAA==.Tovlacar:BAAALgAECgUJBgABLgAECgkJMAAVAO0PAA==.Toyboy:BAAALgAECgQJBAAAAA==.',
Tr='Triage:BAABLgAECn8VAAQjAAgJjhxsBAAFAgAjAAUJCSRsBAAFAgAPAAUJOhU53QDYAAAmAAEJTRZOEQA6AAAAAA==.Trolladin:BAAALgAFFAEJAQAAAA==.Tronarn:BAAALgAECgcJDQAAAA==.',
Ty='Tyrias:BAAALgAECggJAwAAAA==.',
Ug='Ugin:BAACLgAFFH8KAAMnAAMJegXUFgCsAAAnAAMJbQXUFgCsAAANAAMJPQOnrwCqAAAuAAQKfyoAAycACQk+FzsJAOEBACcACQkXFjsJAOEBAA0ACAnsEHN+AF0BAAAA.',
Um='Umaydie:BAAALgAECgIJAwAAAA==.Umbrasyl:BAAALgAECgUJDAAAAA==.',
Un='Unclecharlie:BAAALgAECgUJDAABLgAFFAQJCgAnALsbAA==.Unholylukers:BAAALgAECgIJAwAAAA==.Unit:BAAALgADCgcJCwAAAA==.',
Va='Valkiere:BAAALgADCgEJAQAAAA==.Valkrit:BAAALgADCgIJAgAAAA==.Vasrin:BAACLgAFFH8JAAIiAAQJRRy8BABnAQAiAAQJRRy8BABnAQAuAAQKfzMAAiIACQnmISUDANECACIACQnmISUDANECAAAA.',
Ve='Velaria:BAAALgADCgYJEAABLgAECgYJDAADAAAAAA==.Venitaurus:BAAALgAECgEJAQAAAA==.Veon:BAAALgADCgYJBgAAAA==.Verlehn:BAAALgADCgcJBgAAAA==.',
Vo='Voidomo:BAAALgAFFAIJBAAAAA==.Vonbearback:BAABLgAFFH8FAAINAAMJkQIlsACpAAANAAMJkQIlsACpAAAAAA==.',
Wa='Walden:BAABLgAECn8XAAIKAAcJJhbKHQBLAQAKAAcJJhbKHQBLAQAAAA==.Waterlance:BAAALgAECgEJBAAAAA==.',
We='Weeniefuyu:BAAALgAECgMJBAAAAA==.',
Wi='Wildfupa:BAAALgAECgQJBAAAAA==.Wisecraic:BAAALgAECgYJCwAAAA==.Wispi:BAAALgAECgQJBAAAAA==.',
Wo='Wocoxl:BAACLgAFFH8SAAIRAAUJuRBmGgA3AQARAAUJuRBmGgA3AQAuAAQKfycAAhEACQlIHbUGACQDABEACQlIHbUGACQDAAAA.',
Xe='Xerah:BAAALgADCggJDgAAAA==.',
Ya='Yaracklea:BAAALgAECggJEwAAAA==.',
Yi='Yingu:BAAALgADCgEJAQAAAA==.',
['Yü']='Yüki:BAAALgAECgIJAgAAAA==.',
Za='Zabaniya:BAAALgAECgEJAQAAAA==.Zac:BAAALgADCgYJDAAAAA==.Zacceptable:BAABLgAECn8VAAIjAAcJWBSCCQBRAQAjAAcJWBSCCQBRAQAAAA==.Zaida:BAAALgADCgUJBQABLgAECgIJAgADAAAAAA==.',
Ze='Zeale:BAACLgAFFH8JAAIBAAQJxRCNSgAkAQABAAQJxRCNSgAkAQAuAAQKfy0AAgEACQmmGNMfAF8CAAEACQmmGNMfAF8CAAAA.Zenedict:BAABLgAECn8XAAMhAAkJJBrhGAB2AgAhAAkJJBrhGAB2AgAeAAIJygkahgBUAAAAAA==.Zeniya:BAAALgADCgEJAQAAAA==.',
Zh='Zharsha:BAAALgADCgkJCQAAAA==.',
Zu='Zulubonespur:BAAALgAECgEJAQABLgAECggJEwADAAAAAA==.',
['Áç']='Áçe:BAAALgADCgMJAwAAAA==.',
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
