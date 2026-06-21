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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Priest-Holy','Unknown-Unknown','Warrior-Fury','Warlock-Destruction','Warlock-Affliction','Druid-Restoration','Druid-Balance','Paladin-Retribution','Druid-Guardian','Paladin-Protection','Hunter-Marksmanship','DeathKnight-Unholy','Paladin-Holy','Mage-Frost','DemonHunter-Devourer','Rogue-Subtlety','Warrior-Protection','Evoker-Augmentation','Monk-Brewmaster','Priest-Discipline','Priest-Shadow','Monk-Mistweaver','Hunter-Survival','Evoker-Devastation','Evoker-Preservation','Monk-Windwalker','Warrior-Arms','Druid-Feral','Shaman-Elemental','DemonHunter-Havoc','Shaman-Restoration','Shaman-Enhancement','Mage-Arcane','DemonHunter-Vengeance','DeathKnight-Blood','Mage-Fire','DeathKnight-Frost',}
local provider = {region='US',realm='Rivendare',name='US',type='weekly',zone=46,date='2026-06-20',data={Ai='Aisling:BAAALgADCgYJBgAAAA==.',
Al='Alanispally:BAAALgADCgIJAQAAAA==.Algryn:BAAALgADCgUJBQAAAA==.Alkanz:BAABLgAECn8UAAIBAAkJKQwxYACpAQABAAkJKQwxYACpAQAAAA==.Allinaa:BAABLgAECn8cAAICAAkJwQ5aUgCsAQACAAkJwQ5aUgCsAQAAAA==.Alya:BAABLgAECn8UAAIDAAkJ9wrgKQB4AQADAAkJ9wrgKQB4AQAAAA==.',
Am='Amorvea:BAAALgADCgUJBQABLgAECgIJAgAEAAAAAA==.',
An='Angron:BAAALgADCgIJBQAAAA==.Anika:BAACLgAFFH8OAAIFAAMJMgT7PQCzAAAFAAMJMgT7PQCzAAAuAAQKfzMAAgUACQnrDOQvAI8BAAUACQnrDOQvAI8BAAAA.Antilight:BAAALgAECgcJAQAAAA==.',
Ar='Arcade:BAAALgAECgEJAgAAAA==.Arlyx:BAACLgAFFH8QAAMBAAUJRR4DXgAMAQABAAQJBSADXgAMAQAGAAIJzxMNIABUAAAuAAQKfysABAEACAkmHwssACkCAAEABwlVGwssACkCAAYAAwnzFohHAJgAAAcAAgnoBzQfAHcAAAAA.Arnwaz:BAABLgAECn8UAAMIAAgJ7xU+MgDWAQAIAAgJ7xU+MgDWAQAJAAEJUw7ljAAzAAAAAA==.Arthuria:BAAALgAECgkJEAAAAA==.',
As='Aslan:BAAALgADCgQJBwAAAA==.',
At='Atelwen:BAAALgAECgcJBwAAAA==.',
Av='Avelyn:BAABLgAECn8UAAIKAAgJaB4qPwAJAgAKAAgJaB4qPwAJAgAAAA==.',
Ba='Babyruthie:BAAALgAECgMJBAAAAA==.Baf:BAACLgAFFH8MAAIKAAQJaxfHRwAcAQAKAAQJaxfHRwAcAQAuAAQKfxwAAgoACQmaHYY+ACsCAAoACQmaHYY+ACsCAAAA.Bayside:BAAALgAECgYJEQAAAA==.',
Be='Bearfomat:BAABLgAFFH8FAAILAAMJFh6xEAABAQALAAMJFh6xEAABAQAAAA==.Beefis:BAAALgAECgUJDAAAAA==.Beenjuicin:BAAALgAFFAEJAgABLgAFFAIJAgAEAAAAAA==.Berfomat:BAACLgAFFH8IAAIMAAQJfRcVBgAgAQAMAAQJfRcVBgAgAQAuAAQKfysAAgwACQnUIVoDAOECAAwACQnUIVoDAOECAAAA.',
Bi='Bingchilling:BAACLgAFFH8bAAINAAUJRBbpCgBrAQANAAUJRBbpCgBrAQAuAAQKfzIAAg0ACQkFHp8EAGYCAA0ACQkFHp8EAGYCAAAA.',
Bj='Bjorn:BAABLgAECn8UAAIOAAgJfRcJRwDtAQAOAAgJfRcJRwDtAQAAAA==.',
Bl='Bloodyfupa:BAAALgAECgIJAgAAAA==.Bloomyvfd:BAACLgAFFH8IAAIPAAMJkwaUOACJAAAPAAMJkwaUOACJAAAuAAQKfzgAAg8ACQk6H3UGACYDAA8ACQk6H3UGACYDAAAA.',
Bo='Bombuur:BAAALgAECgQJCAAAAA==.Bonniebadass:BAABLgAECn8VAAIKAAgJRArynwA3AQAKAAgJRArynwA3AQAAAA==.Bottle:BAABLgAECn8WAAIFAAgJrxtzHQACAgAFAAgJrxtzHQACAgAAAA==.Boxxylove:BAAALgAECgQJBwABLgAECgkJFAADAPcKAA==.',
Br='Bravas:BAAALgAECgcJBQAAAA==.Brimscythe:BAAALgADCgQJBAAAAA==.Broxar:BAAALgADCgcJCwAAAA==.',
['Bî']='Bîa:BAABLgAECn8pAAIKAAgJMiTzAAD+AQAKAAgJMiTzAAD+AQAAAA==.',
Ca='Cablemstache:BAAALgADCgcJBwAAAA==.Calisti:BAABLgAECn8tAAIQAAcJ/xvVZgAJAgAQAAcJ/xvVZgAJAgAAAA==.Capybubger:BAABLgAECn8cAAIRAAgJciB6FQCXAgARAAgJciB6FQCXAgABLgAFFAgJGgASAK0jAA==.Cavalis:BAACLgAFFH8QAAQGAAQJ4RKGFACXAAABAAMJcg86eADSAAAGAAIJdRCGFACXAAAHAAEJhhDbIgBNAAAuAAQKfzMABAEACQmTG4E3APsBAAEACAm3GYE3APsBAAcABQmyF7ESAAEBAAYABAlsHOEWAOwAAAAA.',
Ce='Ceedh:BAAALgAFFAMJBAAAAA==.Ceejr:BAACLgAFFH8bAAMFAAgJhCKlAQDoAQAFAAUJ5iKlAQDoAQATAAYJrSDEBgDcAQAuAAQKfyoAAwUACQlpJSQBAMQDAAUACQlpJSQBAMQDABMABgmLIlIQAOIBAAAA.Cerovallen:BAAALgAECgYJCQAAAA==.',
Ch='Chailee:BAAALgADCgEJAQAAAA==.Cherish:BAAALgADCgMJAwABLgAECgUJCgAEAAAAAA==.Chillum:BAAALgAECgIJAgABLgAFFAUJFgAUAKMWAA==.Chimneybeans:BAAALgADCgcJBwAAAA==.',
Co='Corny:BAAALgAECgUJCwAAAA==.',
Cr='Creativez:BAACLgAFFH8IAAIVAAIJxRmzGACoAAAVAAIJxRmzGACoAAAuAAQKfxYAAhUABwkIJK8OAKsCABUABwkIJK8OAKsCAAEuAAUUBAkMAAsApBsA.Creativezd:BAABLgAFFH8MAAILAAQJpBtvCwA8AQALAAQJpBtvCwA8AQAAAA==.',
Da='Dadgoo:BAAALgAECgYJDgAAAA==.Damnskippy:BAAALgAECgcJDQAAAA==.Dannÿ:BAABLgAECn8uAAMWAAgJuRjkHgDXAQAWAAcJVBrkHgDXAQAXAAQJwBD4TQDYAAAAAA==.Dantè:BAAALgAECgIJAgAAAA==.Daris:BAAALgADCgMJAwAAAA==.Darkire:BAACLgAFFH8QAAICAAYJNA+YNABEAQACAAYJNA+YNABEAQAuAAQKfyoAAgIACAkhHLw4APsBAAIACAkhHLw4APsBAAAA.Darkstar:BAAALgADCgUJBQAAAA==.Darkwarriorx:BAAALgADCgQJBAAAAA==.',
De='Deathlegion:BAAALgAECgQJBAAAAA==.Deathroll:BAABLgAECn8oAAIYAAkJNhnTEgCGAgAYAAkJNhnTEgCGAgAAAA==.Delarus:BAAALgAECgEJAQAAAA==.Demonarmor:BAAALgAECgMJCAABLgAECgcJCAAEAAAAAA==.Demonicfupa:BAAALgAECgcJCQABLgAECgUJDgAEAAAAAA==.',
Di='Diddley:BAAALgADCgMJAwAAAA==.',
Do='Dogmatik:BAAALgAECgEJAQABLgAECgMJAwAEAAAAAA==.Dontah:BAAALgADCgcJBwABLgAFFAQJDgAZAJEZAA==.Doomward:BAABLgAECn8uAAIOAAgJgRTEWQC5AQAOAAgJgRTEWQC5AQAAAA==.Dorien:BAACLgAFFH8OAAIZAAQJkRnYDgBNAQAZAAQJkRnYDgBNAQAuAAQKfysAAxkACQmoIb4FAMkCABkACQmoIb4FAMkCAAIABAk6HQ51AFUBAAAA.',
Dr='Drachilly:BAACLgAFFH8WAAIUAAUJoxb1LAARAQAUAAUJoxb1LAARAQAuAAQKfyQABBQACQlcHhAbAP4BABQACQnZHRAbAP4BABoABgknHj0QANgBABsAAQkPArJFABsAAAAA.Dragnar:BAABLgAECn8jAAICAAkJlwzuPQC3AQACAAkJlwzuPQC3AQAAAA==.Drakbonespur:BAAALgAECggJEwAAAA==.Drhealzgood:BAAALgAECgQJBAAAAA==.Droggo:BAAALgADCgIJAgAAAA==.',
Ev='Evilvdduck:BAAALgAECgEJAQAAAA==.',
Ey='Eysia:BAAALgADCgUJCAAAAA==.',
Fa='Faemi:BAAALgAECgMJBAAAAA==.Faewryn:BAABLgAECn8YAAIPAAkJlxGIIgDwAQAPAAkJlxGIIgDwAQAAAA==.Faeya:BAAALgADCgEJAQABLgAECgYJBwAEAAAAAA==.Falekia:BAAALgAECgEJAQAAAA==.Fay:BAACLgAFFH8YAAIVAAYJyhpZEQCaAQAVAAYJyhpZEQCaAQAuAAQKfyIAAhUACQkuInsRAC0CABUACQkuInsRAC0CAAAA.',
Fe='Felltown:BAAALgADCgMJAwAAAA==.',
Fi='Firstblood:BAAALgAECgYJCQAAAA==.Fishnchimps:BAABLgAFFH8NAAMYAAMJyRcqNwDMAAAYAAMJyRcqNwDMAAAcAAIJ9AW0OQBgAAAAAA==.',
Fr='Frogz:BAAALgAECgYJBwAAAA==.Frostyfupa:BAAALgADCgIJAgAAAA==.',
Fu='Fupalicious:BAAALgAECggJDgABLgAECgUJDgAEAAAAAA==.Furrburger:BAAALgADCgIJAgAAAA==.',
Ga='Gaiserik:BAABLgAECn8rAAIdAAkJRCEmBADfAgAdAAkJRCEmBADfAgAAAA==.Galenda:BAAALgAECgEJAQAAAA==.Gandolph:BAAALgADCgEJAQAAAA==.Garduhm:BAAALgADCgYJCQABLgAECgIJAgAEAAAAAA==.Garlictoast:BAAALgAECgQJBwAAAA==.',
Ge='Gearsofhate:BAAALgAECgEJAgAAAA==.Gehenna:BAAALgADCgYJCgAAAA==.Genga:BAAALgADCgYJBgAAAA==.',
Go='Goldenorder:BAAALgAECggJCgAAAA==.Gome:BAAALgADCgcJGwABLgAFFAMJDQAYAMkXAA==.Goodvbes:BAAALgAECgQJBAAAAA==.',
Gr='Gracile:BAAALgADCgEJAQAAAA==.Gragolf:BAABLgAECn8fAAICAAkJlhU3PwDlAQACAAkJlhU3PwDlAQAAAA==.Greggor:BAAALgAECgYJDQAAAA==.Gronkus:BAAALgAECgYJBwAAAA==.',
Gu='Gustabo:BAABLgAECn8bAAIeAAYJGyI3DgDSAQAeAAYJGyI3DgDSAQAAAA==.',
['Gå']='Gåndalf:BAAALgAECgEJAgAAAA==.',
Ha='Haslin:BAAALgADCgEJAgAAAA==.Havibonespur:BAABLgAECn8XAAMVAAYJXQtbSgDTAAAVAAYJXQtbSgDTAAAcAAEJyQTXuwAeAAABLgAECggJEwAEAAAAAA==.',
He='Healir:BAABLgAECn8TAAMWAAgJZiJGGgD+AQAWAAgJZiJGGgD+AQAXAAQJnh/ULAB3AQABLgAFFAUJCAAUAGsXAA==.Healmepls:BAAALgADCgYJCgABLgAFFAUJDAAfAHcPAA==.Hellsong:BAAALgAECgEJAQAAAA==.Helor:BAABLgAECn8XAAMRAAkJcRY+QADIAQARAAkJcRY+QADIAQAgAAUJ3RXDLgBXAQAAAA==.',
Hi='Hiéi:BAAALgAECgEJAQAAAA==.',
Ho='Holydeath:BAABLgAECn8YAAIDAAcJwB3QFAAvAgADAAcJwB3QFAAvAgAAAA==.Hotboydragon:BAABLgAFFH8IAAIUAAUJaxc5KAAqAQAUAAUJaxc5KAAqAQAAAA==.Hotpocketz:BAAALgADCgcJCQABLgAECggJFwAFACoXAA==.',
Hu='Hughjazz:BAAALgAECggJDAAAAA==.Hunterish:BAAALgADCgEJAQAAAA==.',
Ia='Iadrithe:BAAALgADCgYJBgAAAA==.',
In='Inspectadeck:BAAALgAECgMJBAAAAA==.Inthezone:BAAALgAECgkJCQAAAA==.Invisus:BAABLgAECn8WAAIFAAcJZxkMJwDBAQAFAAcJZxkMJwDBAQAAAA==.',
Is='Ispayderj:BAAALgAECgMJBAAAAA==.',
Ja='Jahy:BAAALgADCgIJAgAAAA==.Jake:BAACLgAFFH8MAAIKAAUJ3SAyIgB/AQAKAAUJ3SAyIgB/AQAuAAQKfykAAgoACQkkJt0EAFEDAAoACQkkJt0EAFEDAAAA.Jarlan:BAACLgAFFH8hAAIdAAUJZSNPCwCUAQAdAAUJZSNPCwCUAQAuAAQKfykAAh0ACAmRI7sBACMDAB0ACAmRI7sBACMDAAAA.Jarlhun:BAABLgAECn8dAAINAAcJjh06CQDlAQANAAcJjh06CQDlAQABLgAFFAUJIQAdAGUjAA==.Jarmon:BAAALgAECgUJCQABLgAFFAUJIQAdAGUjAA==.',
Je='Jellous:BAACLgAFFH8GAAMRAAIJpQY/jwBkAAARAAIJBgU/jwBkAAAgAAEJZwv7DQBOAAAuAAQKfyoAAyAACQmCF5MTADgCACAACAl5GJMTADgCABEACQllFN4zACoCAAAA.Jethereal:BAAALgADCgcJBwABLgAFFAIJBgARAKUGAA==.',
Ju='Jurista:BAAALgADCgYJBgAAAA==.Justin:BAAALgAECgYJBgAAAA==.',
Ke='Ketharion:BAABLgAECn8rAAMPAAkJ5RXXHAAcAgAPAAkJ5RXXHAAcAgAKAAEJigvlrAEqAAAAAA==.Kevamin:BAABLgAECn8nAAIKAAkJUhW2PAARAgAKAAkJUhW2PAARAgAAAA==.',
Kh='Khaela:BAAALgAECgIJAgAAAA==.Khato:BAAALgAFFAEJAQAAAA==.',
Ki='Kirasha:BAAALgADCgcJBwAAAA==.',
Ku='Kulfa:BAAALgADCgcJCgAAAA==.Kurailos:BAAALgADCggJCAAAAA==.Kurisu:BAAALgAECgQJCAAAAA==.',
La='Lailyne:BAABLgAECn8fAAQZAAkJ+BOyJwBhAQAZAAcJIA2yJwBhAQANAAYJ8A2mRgA6AQACAAUJexQMnAAJAQAAAA==.Lake:BAAALgAECgcJDAAAAA==.Lastcast:BAAALgAECgEJAQABLgAECgcJEgAEAAAAAA==.Laîlyne:BAAALgAECgYJBgABLgAECgkJHwAZAPgTAA==.',
Le='Learned:BAABLgAECn8VAAIOAAgJzArLjwBGAQAOAAgJzArLjwBGAQAAAA==.Leo:BAABLgAECn8bAAITAAkJwR75BwB+AgATAAkJwR75BwB+AgAAAA==.Leone:BAAALgAECgYJBwAAAA==.',
Li='Lilany:BAACLgAFFH8IAAIhAAMJWQ8YWACdAAAhAAMJWQ8YWACdAAAuAAQKfxUAAiEACQlPFqE+ALQBACEACQlPFqE+ALQBAAAA.Lillymeii:BAAALgAECgEJAQAAAA==.Linova:BAAALgADCgUJBQAAAA==.Lithrak:BAABLgAECn8wAAIiAAkJ0B8rBADfAgAiAAkJ0B8rBADfAgAAAA==.',
Lo='Logical:BAAALgAECgYJBgAAAA==.Lorakine:BAAALgADCgUJBQAAAA==.',
Lu='Luciferr:BAAALgADCgEJAQAAAA==.Lucit:BAAALgAECgYJCgABLgAFFAUJEAABAEUeAA==.Lute:BAAALgAECgQJCAAAAA==.',
Ly='Lyric:BAAALgADCgcJDAABLgAFFAYJGAAVAMoaAA==.',
['Lá']='Lárien:BAABLgAECn8XAAIIAAcJsxTjQwCBAQAIAAcJsxTjQwCBAQAAAA==.',
Ma='Mable:BAAALgADCggJCAAAAA==.Magicmicah:BAAALgADCgcJBwAAAA==.Manon:BAACLgAFFH8YAAIhAAYJIhqjEgDRAQAhAAYJIhqjEgDRAQAuAAQKfx8AAyEACQn9FBEtANYBACEACQn9FBEtANYBAB8AAQm+B3S3ACUAAAAA.',
Mc='Mcchungus:BAACLgAFFH8HAAMZAAMJHA6YIwC7AAAZAAMJ2gaYIwC7AAACAAIJaw8WhQCRAAAuAAQKfxwAAxkACAlQGNEdAK4BABkABwlZFdEdAK4BAAIABwmVFd5tAGUBAAAA.',
Me='Meliodas:BAAALgAECgQJBgAAAA==.Menghao:BAABLgAECn8qAAMQAAkJUgjAgwBwAQAQAAkJUgjAgwBwAQAjAAIJ3AFqGgBEAAAAAA==.Meowmixx:BAAALgAECgcJAwAAAA==.',
Mi='Mikayybrew:BAAALgADCgUJBQAAAA==.Mischief:BAACLgAFFH8dAAIHAAYJShD/BAA5AQAHAAYJShD/BAA5AQAuAAQKf1QAAgcACQksHw4AANQCAAcACQksHw4AANQCAAAA.',
Mk='Mk:BAEALgAECgQJCQABLgAECgkJTQAcAIoiAA==.',
Mo='Mooage:BAACLgAFFH8GAAIQAAIJYiDBMwDLAAAQAAIJYiDBMwDLAAAuAAQKfzMAAhAACQmcJBcMAGQDABAACQmcJBcMAGQDAAAA.Morewyn:BAABLgAECn8nAAICAAkJVBJ5PQDrAQACAAkJVBJ5PQDrAQAAAA==.Mozoh:BAAALgADCgMJAwABLgAECgIJAgAEAAAAAA==.',
Na='Nalock:BAAALgAECgUJBQAAAA==.',
Ne='Nerrgall:BAAALgADCgcJBwAAAA==.',
Ni='Nickignomaj:BAABLgAECn8pAAQcAAgJYh74DQBnAgAcAAgJYh74DQBnAgAYAAQJLBElRwC+AAAVAAUJswY5XQCZAAABLgAFFAQJDQAdAAMTAA==.Nidhogg:BAAALgADCgcJBwABLgAECgkJIQAhANcaAA==.Nisara:BAABLgAECn8fAAIBAAkJDgwmWACVAQABAAkJDgwmWACVAQAAAA==.',
No='Noellie:BAAALgAFFAEJAgAAAA==.Noobdestroya:BAAALgAECgQJEAAAAA==.Nosfuratu:BAAALgADCgkJCQAAAA==.',
Ny='Nymi:BAAALgADCgYJBgAAAA==.',
Of='Offline:BAAALgADCgcJCwAAAA==.',
Ol='Oldbutcool:BAAALgADCgEJAgAAAA==.Oldicy:BAAALgAECgYJBwAAAA==.',
Om='Omantul:BAABLgAECn8hAAMhAAkJ1xqGIgAQAgAhAAgJDRqGIgAQAgAfAAYJUBluUgDvAAAAAA==.',
Or='Orangez:BAAALgAECgMJBAAAAA==.',
Ou='Ouija:BAAALgAECgEJAQAAAA==.',
Ow='Owocoxl:BAAALgAECgIJAgABLgAFFAUJEgASALkQAA==.',
Pa='Painfull:BAABLgAECn8jAAIRAAgJpB0+MQABAgARAAgJpB0+MQABAgAAAA==.Pants:BAAALgAECgEJAgAAAA==.Pantzor:BAAALgADCgEJAQAAAA==.Paz:BAAALgADCgcJBwABLgAECgIJAgAEAAAAAA==.',
Ph='Phakes:BAAALgAECgUJCAAAAA==.Phengzera:BAABLgAECn8WAAIQAAcJMBX3dADoAQAQAAcJMBX3dADoAQAAAA==.Phizz:BAABLgAFFH8KAAIRAAQJaRfPPgAsAQARAAQJaRfPPgAsAQAAAA==.',
Pn='Pneumagloom:BAAALgADCgUJBQAAAA==.',
Po='Po:BAAALgADCgcJDQABLgAFFAYJEwAgACcZAA==.Pontius:BAAALgADCgMJAwABLgAECgkJDgAEAAAAAA==.',
Pr='Prowlborn:BAAALgADCgEJAQAAAA==.',
Pu='Puke:BAABLgAECn8zAAIkAAkJXiWPAABUAwAkAAkJXiWPAABUAwAAAA==.Pumpkinspice:BAAALgADCgYJCQAAAA==.Purplepower:BAAALgAECgMJBAAAAA==.',
Ra='Rarim:BAAALgAECgkJDgAAAA==.',
Re='Reaperfive:BAAALgADCgcJBwAAAA==.Redbonespur:BAAALgADCgcJBwABLgAECggJEwAEAAAAAA==.',
Ri='Rimtardo:BAAALgAECgQJBwAAAA==.Rio:BAAALgAECgMJAwABLgAFFAQJCgABALkQAA==.',
Ro='Rotdaddy:BAABLgAECn8aAAISAAgJ4BGHLQCVAQASAAgJ4BGHLQCVAQAAAA==.Roxxev:BAAALgADCgcJBwAAAA==.',
Ry='Ryø:BAABLgAECn8jAAMIAAkJsgdkWwBAAQAIAAkJsgdkWwBAAQALAAgJ3AgPNQDTAAAAAA==.',
Sa='Saintrandy:BAAALgADCgMJAwAAAA==.Saphiel:BAAALgAECgEJAQAAAA==.',
Sc='Scorch:BAAALgADCgcJCgAAAA==.',
Se='Seraphym:BAAALgADCgYJCAAAAA==.',
Sh='Shaviji:BAAALgAECgcJBwAAAA==.Sheldor:BAAALgAECgEJAQAAAA==.Shinra:BAAALgADCgEJAQABLgAECgcJEgAEAAAAAA==.Shore:BAABLgAECn8eAAMZAAkJ8xtYDQBRAgAZAAkJ8xtYDQBRAgANAAYJQRKXFAAZAQAAAA==.Shrekw:BAAALgAECgcJEwAAAA==.Shuralya:BAACLgAFFH8ZAAMKAAQJhh0vMwBJAQAKAAQJhh0vMwBJAQAPAAMJURI7MwCjAAAuAAQKf0MAAwoACQkhJCYHADUDAAoACQkhJCYHADUDAA8ACQk9GH0gABcCAAAA.',
Si='Silverhorn:BAABLgAECn8UAAIUAAgJ0A5XMwBnAQAUAAgJ0A5XMwBnAQAAAA==.Siouxsie:BAAALgADCgcJCgAAAA==.',
Sm='Smoldnrg:BAAALgAECgUJBQAAAA==.',
So='Sofka:BAABLgAECn8fAAMlAAkJCQ5uGgB+AQAlAAkJCQ5uGgB+AQAOAAEJMgHwOwEbAAAAAA==.Souliel:BAAALgAECgEJAQAAAA==.Sourpatch:BAAALgAECgIJAgAAAA==.',
St='Stilts:BAABLgAECn8UAAMiAAcJpxyHDQDXAQAiAAcJpxyHDQDXAQAhAAQJsAVNfwCWAAAAAA==.Stradynia:BAAALgAECgkJEwAAAA==.Stuart:BAAALgADCgMJAwABLgAECgIJAgAEAAAAAA==.Stócky:BAAALgAECgcJEwAAAA==.',
Su='Sui:BAAALgADCgUJCAABLgAECgYJBwAEAAAAAA==.Survas:BAACLgAFFH8QAAISAAYJrA5vEQCFAQASAAYJrA5vEQCFAQAuAAQKfyEAAhIACQnsGj4cALQBABIACQnsGj4cALQBAAAA.',
Sw='Swobu:BAAALgAECgEJAQAAAA==.',
Sy='Sylvanna:BAAALgAECgYJBwAAAA==.Sylwynn:BAAALgADCgUJCAAAAA==.',
['Sá']='Sárkány:BAAALgADCgcJCQAAAA==.',
Ta='Talanaz:BAAALgAECgYJDAAAAA==.Taleah:BAAALgAECgEJAgAAAA==.Taleb:BAAALgAECgYJEAABLgAECgcJDQAEAAAAAA==.Tardor:BAAALgADCgMJAwAAAA==.Tavgoesboom:BAAALgAFFAIJAgABLgAFFAMJDQAYAMkXAA==.Tawna:BAAALgAECgQJBQAAAA==.',
Te='Tealan:BAABLgAECn8VAAQUAAgJuRZGKAB7AQAUAAcJSxVGKAB7AQAbAAYJmhTVJwA1AQAaAAEJOQjJQAAvAAAAAA==.Tenyi:BAAALgAECgMJAwAAAA==.Terrin:BAAALgAECgQJBQABLgAECgcJDQAEAAAAAA==.',
To='Toospooky:BAABLgAECn8VAAQXAAcJFhjbNQA/AQAXAAYJGhfbNQA/AQAWAAUJXgkUTADUAAADAAEJ0AaddAAlAAAAAA==.Tovlacar:BAAALgAECgUJBgABLgAECgkJMAAWAO0PAA==.Toyboy:BAAALgAECgQJBAAAAA==.',
Tr='Triage:BAABLgAECn8VAAQjAAgJjhxsBAAFAgAjAAUJCSRsBAAFAgAQAAUJOhX/5QDSAAAmAAEJTRYmEwA7AAAAAA==.Trolladin:BAAALgAFFAEJAQAAAA==.Tronarn:BAAALgAECgcJDQAAAA==.',
Ty='Tyrias:BAAALgAECgkJAwAAAA==.',
Ug='Ugin:BAACLgAFFH8NAAMnAAMJ4waLGgC1AAAnAAMJ4waLGgC1AAAOAAMJPQOHwwCjAAAuAAQKfyoAAycACQk+F14KANgBACcACQkXFl4KANgBAA4ACAnsEO2HAFQBAAAA.',
Um='Umaydie:BAAALgAECgIJAwAAAA==.Umbrasyl:BAAALgAECgUJDQAAAA==.',
Un='Unclecharlie:BAAALgAFFAMJAwABLgAFFAUJDgAnALQdAA==.Unholylukers:BAAALgAECgIJAwAAAA==.Unit:BAAALgADCgcJCwAAAA==.',
Va='Valkiere:BAAALgADCgEJAQAAAA==.Valkrit:BAAALgADCgIJAgAAAA==.Vasrin:BAACLgAFFH8JAAIiAAQJRRxUBgBXAQAiAAQJRRxUBgBXAQAuAAQKfzMAAiIACQnmIYgDAMwCACIACQnmIYgDAMwCAAAA.',
Ve='Velaria:BAAALgADCgYJEAABLgAECgYJDAAEAAAAAA==.Venitaurus:BAAALgAECgEJAQAAAA==.Veon:BAAALgADCgYJBgAAAA==.Verlehn:BAAALgADCgcJBgAAAA==.',
Vo='Voidomo:BAAALgAFFAIJBAAAAA==.Vonbearback:BAABLgAFFH8GAAIOAAMJPQSmvwCqAAAOAAMJPQSmvwCqAAAAAA==.',
Wa='Walden:BAABLgAECn8XAAILAAcJJhZSIABLAQALAAcJJhZSIABLAQAAAA==.Waterlance:BAAALgAECgEJBAAAAA==.',
We='Weeniefuyu:BAAALgAECgMJBgAAAA==.',
Wi='Wildfupa:BAAALgAECgYJCAAAAA==.Wisecraic:BAABLgAECn8UAAIIAAYJGhQwSABvAQAIAAYJGhQwSABvAQAAAA==.Wispi:BAAALgAECgQJBAAAAA==.',
Wo='Wocoxl:BAACLgAFFH8SAAISAAUJuRBOHgAvAQASAAUJuRBOHgAvAQAuAAQKfycAAhIACQlIHbUGACQDABIACQlIHbUGACQDAAAA.',
Xe='Xerah:BAAALgADCggJDgAAAA==.',
Ya='Yaracklea:BAABLgAECn8VAAIDAAkJuRW6EwA7AgADAAkJuRW6EwA7AgAAAA==.',
Yi='Yingu:BAAALgADCgEJAQAAAA==.',
['Yü']='Yüki:BAAALgAECgIJAwAAAA==.',
Za='Zabaniya:BAAALgAECgQJBQAAAA==.Zac:BAAALgADCgYJDAAAAA==.Zacceptable:BAABLgAECn8VAAIjAAcJWBSCCQBRAQAjAAcJWBSCCQBRAQAAAA==.Zaida:BAAALgADCgUJBQABLgAECgIJAgAEAAAAAA==.',
Ze='Zeale:BAACLgAFFH8KAAIBAAQJuRAaVAAeAQABAAQJuRAaVAAeAQAuAAQKfy8AAgEACQkvGdIgAGACAAEACQkvGdIgAGACAAAA.Zenedict:BAABLgAECn8bAAMhAAkJJBq+GgB1AgAhAAkJJBq+GgB1AgAfAAMJNglSeACFAAABLgAFFAMJAwAEAAAAAA==.Zeniya:BAAALgADCgEJAQAAAA==.',
Zh='Zharsha:BAAALgADCgkJCQAAAA==.',
Zs='Zsofi:BAAALgADCgkJCQAAAA==.',
Zu='Zulubonespur:BAAALgAECgEJAQABLgAECggJEwAEAAAAAA==.',
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
