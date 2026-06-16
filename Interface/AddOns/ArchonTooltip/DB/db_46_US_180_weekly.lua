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
local provider = {region='US',realm='Rivendare',name='US',type='weekly',zone=46,date='2026-06-13',data={Ai='Aisling:BAAALgADCgYJBgAAAA==.',
Al='Alanispally:BAAALgADCgIJAQAAAA==.Algryn:BAAALgADCgUJBQAAAA==.Alkanz:BAABLgAECn8UAAIBAAkJKQwxYACpAQABAAkJKQwxYACpAQAAAA==.Allinaa:BAABLgAECn8cAAICAAkJwQ7DUACsAQACAAkJwQ7DUACsAQAAAA==.Alya:BAAALgAECggJDAAAAA==.',
Am='Amorvea:BAAALgADCgUJBQABLgAECgIJAgADAAAAAA==.',
An='Angron:BAAALgADCgIJBQAAAA==.Anika:BAACLgAFFH8OAAIEAAMJMgQvPACzAAAEAAMJMgQvPACzAAAuAAQKfzMAAgQACQnrDHMuAJUBAAQACQnrDHMuAJUBAAAA.Antilight:BAAALgAECgcJAQAAAA==.',
Ar='Arcade:BAAALgAECgEJAgAAAA==.Arlyx:BAACLgAFFH8QAAMBAAUJRR6HWgAOAQABAAQJBSCHWgAOAQAFAAIJzxMvHwBUAAAuAAQKfygABAEACAkTH/0uABsCAAEABwlCG/0uABsCAAUAAwnzFohHAJgAAAYAAgnoBzQfAHcAAAAA.Arnwaz:BAABLgAECn8UAAMHAAgJ7xWlMQDXAQAHAAgJ7xWlMQDXAQAIAAEJUw5iigAzAAAAAA==.Arthuria:BAAALgAECgkJDwAAAA==.',
As='Aslan:BAAALgADCgQJBwAAAA==.',
At='Atelwen:BAAALgAECgcJBwAAAA==.',
Av='Avelyn:BAAALgAFFAIJAwAAAA==.',
Ba='Babyruthie:BAAALgAECgMJBAAAAA==.Baf:BAACLgAFFH8MAAIJAAQJaxfFRAAdAQAJAAQJaxfFRAAdAQAuAAQKfxwAAgkACQmaHYY+ACsCAAkACQmaHYY+ACsCAAAA.Bayside:BAAALgAECgYJEQAAAA==.',
Be='Bearfomat:BAABLgAFFH8FAAIKAAMJFh6xDwAEAQAKAAMJFh6xDwAEAQAAAA==.Beefis:BAAALgAECgUJDAAAAA==.Beenjuicin:BAAALgAFFAEJAgABLgAFFAIJAgADAAAAAA==.Berfomat:BAACLgAFFH8IAAILAAQJfRfeBQAhAQALAAQJfRfeBQAhAQAuAAQKfysAAgsACQnUIUEDAOICAAsACQnUIUEDAOICAAAA.',
Bi='Bingchilling:BAACLgAFFH8bAAIMAAUJRBbpCgBrAQAMAAUJRBbpCgBrAQAuAAQKfzIAAgwACQkFHn8EAGcCAAwACQkFHn8EAGcCAAAA.',
Bj='Bjorn:BAABLgAECn8UAAINAAgJfRfKRQDvAQANAAgJfRfKRQDvAQAAAA==.',
Bl='Bloodyfupa:BAAALgAECgIJAgAAAA==.Bloomyvfd:BAACLgAFFH8IAAIOAAMJkwZJNwCJAAAOAAMJkwZJNwCJAAAuAAQKfzgAAg4ACQk6H0kGACcDAA4ACQk6H0kGACcDAAAA.',
Bo='Bombuur:BAAALgAECgQJCAAAAA==.Bonniebadass:BAABLgAECn8VAAIJAAgJRAq9nAA6AQAJAAgJRAq9nAA6AQAAAA==.Bottle:BAABLgAECn8WAAIEAAgJrxsZHQAEAgAEAAgJrxsZHQAEAgAAAA==.Boxxylove:BAAALgAECgQJBwABLgAECggJDAADAAAAAA==.',
Br='Bravas:BAAALgAECgcJBQAAAA==.Brimscythe:BAAALgADCgQJBAAAAA==.Broxar:BAAALgADCgcJCwAAAA==.',
['Bî']='Bîa:BAABLgAECn8jAAIJAAgJCCPTGwCcAgAJAAgJCCPTGwCcAgAAAA==.',
Ca='Cablemstache:BAAALgADCgcJBwAAAA==.Calisti:BAABLgAECn8tAAIPAAcJ/xvVZgAJAgAPAAcJ/xvVZgAJAgAAAA==.Capybubger:BAABLgAECn8cAAIQAAgJciAOFQCXAgAQAAgJciAOFQCXAgABLgAFFAgJGQARABojAA==.Cavalis:BAACLgAFFH8QAAQFAAQJ4RLsEwCYAAABAAMJcg8PdQDTAAAFAAIJdRDsEwCYAAAGAAEJhhDdIQBNAAAuAAQKfzMABAEACQmTG9k2APwBAAEACAm3Gdk2APwBAAYABQmyF7ESAAEBAAUABAlsHG0WAO0AAAAA.',
Ce='Ceedh:BAAALgAFFAMJBAAAAA==.Ceejr:BAACLgAFFH8bAAMEAAgJhCKlAQDoAQAEAAUJ5iKlAQDoAQASAAYJrSAbBgDiAQAuAAQKfyoAAwQACQlpJSQBAMQDAAQACQlpJSQBAMQDABIABgmLIgoQAOMBAAAA.Cerovallen:BAAALgAECgYJCQAAAA==.',
Ch='Chailee:BAAALgADCgEJAQAAAA==.Cherish:BAAALgADCgMJAwABLgAECgUJCgADAAAAAA==.Chillum:BAAALgAECgIJAgABLgAFFAUJFgATAKMWAA==.Chimneybeans:BAAALgADCgcJBwAAAA==.',
Co='Corny:BAAALgAECgUJCwAAAA==.',
Cr='Creativez:BAACLgAFFH8IAAIUAAIJxRmzGACoAAAUAAIJxRmzGACoAAAuAAQKfxYAAhQABwkIJK8OAKsCABQABwkIJK8OAKsCAAEuAAUUBAkMAAoApBsA.Creativezd:BAABLgAFFH8MAAIKAAQJpBu2CgA/AQAKAAQJpBu2CgA/AQAAAA==.',
Da='Dadgoo:BAAALgAECgYJDgAAAA==.Damnskippy:BAAALgAECgcJDQAAAA==.Dannÿ:BAABLgAECn8tAAMVAAgJyxYzHgDZAQAVAAcJIBgzHgDZAQAWAAQJwBAoTADcAAAAAA==.Dantè:BAAALgAECgIJAgAAAA==.Daris:BAAALgADCgMJAwAAAA==.Darkire:BAACLgAFFH8QAAICAAYJNA+5MQBEAQACAAYJNA+5MQBEAQAuAAQKfyoAAgIACAkhHEk3APwBAAIACAkhHEk3APwBAAAA.Darkstar:BAAALgADCgUJBQAAAA==.Darkwarriorx:BAAALgADCgQJBAAAAA==.',
De='Deathlegion:BAAALgAECgQJBAAAAA==.Deathroll:BAABLgAECn8oAAIXAAkJNhloEgCFAgAXAAkJNhloEgCFAgAAAA==.Delarus:BAAALgAECgEJAQAAAA==.Demonarmor:BAAALgAECgMJCAABLgAECgcJCAADAAAAAA==.Demonicfupa:BAAALgAECgQJBQABLgAECgUJDQADAAAAAA==.',
Di='Diddley:BAAALgADCgMJAwAAAA==.',
Do='Dogmatik:BAAALgAECgEJAQABLgAECgMJAwADAAAAAA==.Dontah:BAAALgADCgcJBwABLgAFFAQJDQAYAJEZAA==.Doomward:BAABLgAECn8uAAINAAgJgRRhWAC6AQANAAgJgRRhWAC6AQAAAA==.Dorien:BAACLgAFFH8NAAIYAAQJkRkuDgBPAQAYAAQJkRkuDgBPAQAuAAQKfysAAxgACQmoIYsFAMwCABgACQmoIYsFAMwCAAIABAk6HX5yAFYBAAAA.',
Dr='Drachilly:BAACLgAFFH8WAAITAAUJoxa6KgAXAQATAAUJoxa6KgAXAQAuAAQKfyQABBMACQlcHs8aAP4BABMACQnZHc8aAP4BABkABgknHj0QANgBABoAAQkPAqlEABsAAAAA.Dragnar:BAABLgAECn8jAAICAAkJlwzuPQC3AQACAAkJlwzuPQC3AQAAAA==.Drakbonespur:BAAALgAECggJEwAAAA==.Drhealzgood:BAAALgAECgQJBAAAAA==.Droggo:BAAALgADCgIJAgAAAA==.',
Ev='Evilvdduck:BAAALgAECgEJAQAAAA==.',
Ey='Eysia:BAAALgADCgUJCAAAAA==.',
Fa='Faemi:BAAALgAECgMJBAAAAA==.Faewryn:BAABLgAECn8YAAIOAAkJlxEKIgDxAQAOAAkJlxEKIgDxAQAAAA==.Faeya:BAAALgADCgEJAQABLgADCgUJCAADAAAAAA==.Falekia:BAAALgAECgEJAQAAAA==.Fay:BAACLgAFFH8YAAIUAAYJyhojEACcAQAUAAYJyhojEACcAQAuAAQKfyIAAhQACQkuIjsRAC4CABQACQkuIjsRAC4CAAAA.',
Fe='Felltown:BAAALgADCgMJAwAAAA==.',
Fi='Firstblood:BAAALgAECgYJCQAAAA==.Fishnchimps:BAABLgAFFH8NAAMXAAMJyRegNADMAAAXAAMJyRegNADMAAAbAAIJ9AXaNwBgAAAAAA==.',
Fr='Frogz:BAAALgAECgIJAgAAAA==.Frostyfupa:BAAALgADCgIJAgAAAA==.',
Fu='Fupalicious:BAAALgAECgcJDQABLgAECgUJDQADAAAAAA==.Furrburger:BAAALgADCgIJAgAAAA==.',
Ga='Gaiserik:BAABLgAECn8rAAIcAAkJRCEHBADgAgAcAAkJRCEHBADgAgAAAA==.Galenda:BAAALgADCgQJBQAAAA==.Gandolph:BAAALgADCgEJAQAAAA==.Garduhm:BAAALgADCgYJCQABLgAECgIJAgADAAAAAA==.Garlictoast:BAAALgAECgQJBwAAAA==.',
Ge='Gearsofhate:BAAALgAECgEJAgAAAA==.Gehenna:BAAALgADCgYJCgAAAA==.Genga:BAAALgADCgYJBgAAAA==.',
Go='Goldenorder:BAAALgAECggJCgAAAA==.Gome:BAAALgADCgcJGwABLgAFFAMJDQAXAMkXAA==.Goodvbes:BAAALgAECgQJBAAAAA==.',
Gr='Gracile:BAAALgADCgEJAQAAAA==.Gragolf:BAABLgAECn8fAAICAAkJlhXgPQDlAQACAAkJlhXgPQDlAQAAAA==.Greggor:BAAALgAECgYJDQAAAA==.Gronkus:BAAALgAECgYJBwAAAA==.',
Gu='Gustabo:BAABLgAECn8bAAIdAAYJGyLdDQDSAQAdAAYJGyLdDQDSAQAAAA==.',
['Gå']='Gåndalf:BAAALgAECgEJAQAAAA==.',
Ha='Haslin:BAAALgADCgEJAgAAAA==.Havibonespur:BAABLgAECn8XAAMUAAYJXQueSQDTAAAUAAYJXQueSQDTAAAbAAEJyQRcuAAeAAABLgAECggJEwADAAAAAA==.',
He='Healir:BAABLgAECn8TAAMVAAgJZiLiGQD/AQAVAAgJZiLiGQD/AQAWAAQJnh/ULAB3AQABLgAFFAUJCAATAGsXAA==.Healmepls:BAAALgADCgYJCgABLgAFFAUJDAAeAHcPAA==.Hellsong:BAAALgAECgEJAQAAAA==.Helor:BAABLgAECn8XAAMQAAkJcRZYPwDIAQAQAAkJcRZYPwDIAQAfAAUJ3RXDLgBXAQAAAA==.',
Hi='Hiéi:BAAALgAECgEJAQAAAA==.',
Ho='Holydeath:BAABLgAECn8YAAIgAAcJwB1zFAAwAgAgAAcJwB1zFAAwAgAAAA==.Hotboydragon:BAABLgAFFH8IAAITAAUJaxf9JQAxAQATAAUJaxf9JQAxAQAAAA==.Hotpocketz:BAAALgADCgcJCQABLgAECggJFwAEACoXAA==.',
Hu='Hughjazz:BAAALgAECgcJCgAAAA==.Hunterish:BAAALgADCgEJAQAAAA==.',
Ia='Iadrithe:BAAALgADCgYJBgAAAA==.',
In='Inspectadeck:BAAALgAECgMJBAAAAA==.Invisus:BAABLgAECn8WAAIEAAcJZxmSJgDDAQAEAAcJZxmSJgDDAQAAAA==.',
Is='Ispayderj:BAAALgAECgMJBAAAAA==.',
Ja='Jahy:BAAALgADCgIJAgAAAA==.Jake:BAACLgAFFH8MAAIJAAUJ3SDKHwCBAQAJAAUJ3SDKHwCBAQAuAAQKfykAAgkACQkkJqQEAFMDAAkACQkkJqQEAFMDAAAA.Jarlan:BAACLgAFFH8hAAIcAAUJZSOGCgCXAQAcAAUJZSOGCgCXAQAuAAQKfykAAhwACAmRI7sBACMDABwACAmRI7sBACMDAAAA.Jarlhun:BAABLgAECn8dAAIMAAcJjh0ACQDlAQAMAAcJjh0ACQDlAQABLgAFFAUJIQAcAGUjAA==.Jarmon:BAAALgAECgUJBQABLgAFFAUJIQAcAGUjAA==.',
Je='Jellous:BAACLgAFFH8GAAMQAAIJpQajiwBkAAAQAAIJBgWjiwBkAAAfAAEJZwv7DQBOAAAuAAQKfyoAAx8ACQmCF5MTADgCAB8ACAl5GJMTADgCABAACQllFN4zACoCAAAA.Jethereal:BAAALgADCgcJBwABLgAFFAIJBgAQAKUGAA==.',
Ju='Jurista:BAAALgADCgYJBgAAAA==.Justin:BAAALgAECgYJBgAAAA==.',
Ke='Ketharion:BAABLgAECn8rAAMOAAkJ5RVsHAAeAgAOAAkJ5RVsHAAeAgAJAAEJigsWpgEqAAAAAA==.Kevamin:BAABLgAECn8mAAIJAAkJUhXMOwASAgAJAAkJUhXMOwASAgAAAA==.',
Kh='Khaela:BAAALgAECgIJAgAAAA==.Khato:BAAALgAECgkJEgAAAA==.',
Ki='Kirasha:BAAALgADCgcJBwAAAA==.',
Ku='Kulfa:BAAALgADCgcJCgAAAA==.Kurailos:BAAALgADCggJCAAAAA==.Kurisu:BAAALgAECgQJCAAAAA==.',
La='Lailyne:BAABLgAECn8fAAQYAAkJ+BMdJwBmAQAYAAcJIA0dJwBmAQAMAAYJ8A2mRgA6AQACAAUJexT3mAAJAQAAAA==.Lake:BAAALgAECgcJDAAAAA==.Laîlyne:BAAALgAECgYJBgABLgAECgkJHwAYAPgTAA==.',
Le='Learned:BAABLgAECn8UAAINAAgJzAqcjABJAQANAAgJzAqcjABJAQAAAA==.Leo:BAABLgAECn8bAAISAAkJwR7JBwB/AgASAAkJwR7JBwB/AgAAAA==.Leone:BAAALgAECgYJBwAAAA==.',
Li='Lilany:BAACLgAFFH8IAAIhAAMJWQ+kVQCdAAAhAAMJWQ+kVQCdAAAuAAQKfxUAAiEACQlPFqU9ALQBACEACQlPFqU9ALQBAAAA.Lillymeii:BAAALgAECgEJAQAAAA==.Linova:BAAALgADCgUJBQAAAA==.Lithrak:BAABLgAECn8wAAIiAAkJ0B8rBADfAgAiAAkJ0B8rBADfAgAAAA==.',
Lo='Logical:BAAALgAECgYJBgAAAA==.Lorakine:BAAALgADCgUJBQAAAA==.',
Lu='Luciferr:BAAALgADCgEJAQAAAA==.Lucit:BAAALgAECgYJCAABLgAFFAUJEAABAEUeAA==.Lute:BAAALgAECgQJCAAAAA==.',
Ly='Lyric:BAAALgADCgcJDAABLgAFFAYJGAAUAMoaAA==.',
['Lá']='Lárien:BAABLgAECn8XAAIHAAcJsxQQQwCCAQAHAAcJsxQQQwCCAQAAAA==.',
Ma='Mable:BAAALgADCggJCAAAAA==.Magicmicah:BAAALgADCgcJBwAAAA==.Manon:BAACLgAFFH8YAAIhAAYJIhozEQDSAQAhAAYJIhozEQDSAQAuAAQKfx8AAyEACQn9FBEtANYBACEACQn9FBEtANYBAB4AAQm+B7yzACUAAAAA.',
Mc='Mcchungus:BAACLgAFFH8HAAMYAAMJHA7PIgC7AAAYAAMJ2gbPIgC7AAACAAIJaw/ZfwCRAAAuAAQKfxwAAxgACAlQGCkdALMBABgABwlZFSkdALMBAAIABwmVFcprAGUBAAAA.',
Me='Meliodas:BAAALgAECgQJBgAAAA==.Menghao:BAABLgAECn8pAAMPAAkJUgjwgQBwAQAPAAkJUgjwgQBwAQAjAAIJ3AFqGgBEAAAAAA==.Meowmixx:BAAALgAECgcJAwAAAA==.',
Mi='Mikayybrew:BAAALgADCgUJBQAAAA==.Mischief:BAACLgAFFH8cAAIGAAUJ8xO9BAA6AQAGAAUJ8xO9BAA6AQAuAAQKf0sAAgYACQmhHiwCALkCAAYACQmhHiwCALkCAAAA.',
Mk='Mk:BAEALgAECgQJCQABLgAECgkJQQAbAIAgAA==.',
Mo='Mooage:BAACLgAFFH8GAAIPAAIJYiDBMwDLAAAPAAIJYiDBMwDLAAAuAAQKfzMAAg8ACQmcJBcMAGQDAA8ACQmcJBcMAGQDAAAA.Morewyn:BAABLgAECn8nAAICAAkJVBIUPADsAQACAAkJVBIUPADsAQAAAA==.Mozoh:BAAALgADCgMJAwABLgAECgIJAgADAAAAAA==.',
Na='Nalock:BAAALgAECgUJBQAAAA==.',
Ne='Nerrgall:BAAALgADCgcJBwAAAA==.',
Ni='Nickignomaj:BAABLgAECn8pAAQbAAgJYh60DQBoAgAbAAgJYh60DQBoAgAXAAQJLBElRwC+AAAUAAUJswZRXACZAAABLgAFFAQJDQAcAAMTAA==.Nidhogg:BAAALgADCgcJBwABLgAECgkJIQAhANcaAA==.Nisara:BAABLgAECn8fAAIBAAkJDgw3VgCZAQABAAkJDgw3VgCZAQAAAA==.',
No='Noellie:BAAALgAFFAEJAgAAAA==.Noobdestroya:BAAALgAECgQJEAAAAA==.Nosfuratu:BAAALgADCgkJCQAAAA==.',
Ny='Nymi:BAAALgADCgYJBgAAAA==.',
Of='Offline:BAAALgADCgcJCwAAAA==.',
Ol='Oldbutcool:BAAALgADCgEJAgAAAA==.Oldicy:BAAALgAECgYJBwAAAA==.',
Om='Omantul:BAABLgAECn8hAAMhAAkJ1xqGIgAQAgAhAAgJDRqGIgAQAgAeAAYJUBkOUQDvAAAAAA==.',
Or='Orangez:BAAALgAECgMJBAAAAA==.',
Ou='Ouija:BAAALgAECgEJAQAAAA==.',
Ow='Owocoxl:BAAALgAECgIJAgABLgAFFAUJEgARALkQAA==.',
Pa='Painfull:BAABLgAECn8jAAIQAAgJpB1/MAABAgAQAAgJpB1/MAABAgAAAA==.Pants:BAAALgAECgEJAgAAAA==.Pantzor:BAAALgADCgEJAQAAAA==.Paz:BAAALgADCgcJBwABLgAECgIJAgADAAAAAA==.',
Ph='Phakes:BAAALgAECgUJCAAAAA==.Phengzera:BAABLgAECn8WAAIPAAcJMBX3dADoAQAPAAcJMBX3dADoAQAAAA==.Phizz:BAABLgAFFH8KAAIQAAQJaReEPAAtAQAQAAQJaReEPAAtAQAAAA==.',
Pn='Pneumagloom:BAAALgADCgUJBQAAAA==.',
Po='Po:BAAALgADCgcJDQABLgAFFAYJEAAQAC4QAA==.Pontius:BAAALgADCgMJAwABLgAECgkJDgADAAAAAA==.',
Pr='Prowlborn:BAAALgADCgEJAQAAAA==.',
Pu='Puke:BAABLgAECn8zAAIkAAkJXiWMAABVAwAkAAkJXiWMAABVAwAAAA==.Pumpkinspice:BAAALgADCgYJCQAAAA==.Purplepower:BAAALgAECgMJBAAAAA==.',
Ra='Rarim:BAAALgAECgkJDgAAAA==.',
Re='Reaperfive:BAAALgADCgcJBwAAAA==.Redbonespur:BAAALgADCgcJBwABLgAECggJEwADAAAAAA==.',
Ri='Rimtardo:BAAALgAECgQJBwAAAA==.Rio:BAAALgAECgMJAwABLgAFFAQJCgABALkQAA==.',
Ro='Rotdaddy:BAABLgAECn8aAAIRAAgJ4BGHLQCVAQARAAgJ4BGHLQCVAQAAAA==.Roxxev:BAAALgADCgcJBwAAAA==.',
Ry='Ryø:BAABLgAECn8jAAMHAAkJsgdkWwBAAQAHAAkJsgdkWwBAAQAKAAgJ3Ai5MwDUAAAAAA==.',
Sa='Saintrandy:BAAALgADCgMJAwAAAA==.Saphiel:BAAALgAECgEJAQAAAA==.',
Sc='Scorch:BAAALgADCgcJCgAAAA==.',
Se='Seraphym:BAAALgADCgYJCAAAAA==.',
Sh='Shaviji:BAAALgAECgcJBwAAAA==.Sheldor:BAAALgAECgEJAQAAAA==.Shinra:BAAALgADCgEJAQABLgAECgcJEgADAAAAAA==.Shore:BAABLgAECn8eAAMYAAkJ8xsGDQBVAgAYAAkJ8xsGDQBVAgAMAAYJQRI5FAAZAQAAAA==.Shrekw:BAAALgAECgcJEwAAAA==.Shuralya:BAACLgAFFH8ZAAMJAAQJhh0fMABLAQAJAAQJhh0fMABLAQAOAAMJURIFMgCkAAAuAAQKf0MAAwkACQkhJM8GADcDAAkACQkhJM8GADcDAA4ACQk9GH0gABcCAAAA.',
Si='Silverhorn:BAABLgAECn8UAAITAAgJ0A4SMgBqAQATAAgJ0A4SMgBqAQAAAA==.Siouxsie:BAAALgADCgcJCgAAAA==.',
Sm='Smoldnrg:BAAALgAECgUJBQAAAA==.',
So='Sofka:BAABLgAECn8fAAMlAAkJCQ5uGgB+AQAlAAkJCQ5uGgB+AQANAAEJMgHwOwEbAAAAAA==.Souliel:BAAALgAECgEJAQAAAA==.Sourpatch:BAAALgAECgIJAgAAAA==.',
St='Stilts:BAABLgAECn8UAAMiAAcJpxxBDQDYAQAiAAcJpxxBDQDYAQAhAAQJsAVNfwCWAAAAAA==.Stradynia:BAAALgAECgkJEwAAAA==.Stuart:BAAALgADCgMJAwABLgAECgIJAgADAAAAAA==.Stócky:BAAALgAECgcJEwAAAA==.',
Su='Sui:BAAALgADCgUJCAAAAA==.Survas:BAACLgAFFH8QAAIRAAYJrA56EACGAQARAAYJrA56EACGAQAuAAQKfyEAAhEACQnsGrEbALUBABEACQnsGrEbALUBAAAA.',
Sw='Swobu:BAAALgAECgEJAQAAAA==.',
Sy='Sylwynn:BAAALgADCgUJCAAAAA==.',
['Sá']='Sárkány:BAAALgADCgcJCQAAAA==.',
Ta='Talanaz:BAAALgAECgYJDAAAAA==.Taleah:BAAALgAECgEJAgAAAA==.Taleb:BAAALgAECgYJEAABLgAECgcJDQADAAAAAA==.Tardor:BAAALgADCgMJAwAAAA==.Tavgoesboom:BAAALgAFFAIJAgABLgAFFAMJDQAXAMkXAA==.Tawna:BAAALgAECgQJBQAAAA==.',
Te='Tealan:BAABLgAECn8VAAQTAAgJuRZGKAB7AQATAAcJSxVGKAB7AQAaAAYJmhTVJwA1AQAZAAEJOQjJQAAvAAAAAA==.Tenyi:BAAALgAECgMJAwAAAA==.Terrin:BAAALgAECgQJBQABLgAECgcJDQADAAAAAA==.',
To='Toospooky:BAABLgAECn8VAAQWAAcJFhgiNQBBAQAWAAYJGhciNQBBAQAVAAUJXgmDSQDcAAAgAAEJ0AbUcgAlAAAAAA==.Tovlacar:BAAALgAECgUJBgABLgAECgkJMAAVAO0PAA==.Toyboy:BAAALgAECgQJBAAAAA==.',
Tr='Triage:BAABLgAECn8VAAQjAAgJjhxsBAAFAgAjAAUJCSRsBAAFAgAPAAUJOhW44gDTAAAmAAEJTRaDEgA7AAAAAA==.Trolladin:BAAALgAFFAEJAQAAAA==.Tronarn:BAAALgAECgcJDQAAAA==.',
Ty='Tyrias:BAAALgAECggJAwAAAA==.',
Ug='Ugin:BAACLgAFFH8NAAMnAAMJ4wZDGQC1AAAnAAMJ4wZDGQC1AAANAAMJPQNyvQCmAAAuAAQKfyoAAycACQk+FwcKAN0BACcACQkXFgcKAN0BAA0ACAnsEASFAFcBAAAA.',
Um='Umaydie:BAAALgAECgIJAwAAAA==.Umbrasyl:BAAALgAECgUJDAAAAA==.',
Un='Unclecharlie:BAAALgAFFAMJAwABLgAFFAUJDgAnALQdAA==.Unholylukers:BAAALgAECgIJAwAAAA==.Unit:BAAALgADCgcJCwAAAA==.',
Va='Valkiere:BAAALgADCgEJAQAAAA==.Valkrit:BAAALgADCgIJAgAAAA==.Vasrin:BAACLgAFFH8JAAIiAAQJRRzRBQBeAQAiAAQJRRzRBQBeAQAuAAQKfzMAAiIACQnmIW4DAM0CACIACQnmIW4DAM0CAAAA.',
Ve='Velaria:BAAALgADCgYJEAABLgAECgYJDAADAAAAAA==.Venitaurus:BAAALgAECgEJAQAAAA==.Veon:BAAALgADCgYJBgAAAA==.Verlehn:BAAALgADCgcJBgAAAA==.',
Vo='Voidomo:BAAALgAFFAIJBAAAAA==.Vonbearback:BAABLgAFFH8GAAINAAMJPQTHuQCtAAANAAMJPQTHuQCtAAAAAA==.',
Wa='Walden:BAABLgAECn8XAAIKAAcJJhamHwBLAQAKAAcJJhamHwBLAQAAAA==.Waterlance:BAAALgAECgEJBAAAAA==.',
We='Weeniefuyu:BAAALgAECgMJBgAAAA==.',
Wi='Wildfupa:BAAALgAECgYJCAAAAA==.Wisecraic:BAAALgAECgYJEAAAAA==.Wispi:BAAALgAECgQJBAAAAA==.',
Wo='Wocoxl:BAACLgAFFH8SAAIRAAUJuRBFHQAvAQARAAUJuRBFHQAvAQAuAAQKfycAAhEACQlIHbUGACQDABEACQlIHbUGACQDAAAA.',
Xe='Xerah:BAAALgADCggJDgAAAA==.',
Ya='Yaracklea:BAABLgAECn8VAAIgAAkJuRVmEwA7AgAgAAkJuRVmEwA7AgAAAA==.',
Yi='Yingu:BAAALgADCgEJAQAAAA==.',
['Yü']='Yüki:BAAALgAECgIJAwAAAA==.',
Za='Zabaniya:BAAALgAECgQJBQAAAA==.Zac:BAAALgADCgYJDAAAAA==.Zacceptable:BAABLgAECn8VAAIjAAcJWBSCCQBRAQAjAAcJWBSCCQBRAQAAAA==.Zaida:BAAALgADCgUJBQABLgAECgIJAgADAAAAAA==.',
Ze='Zeale:BAACLgAFFH8KAAIBAAQJuRBXUQAfAQABAAQJuRBXUQAfAQAuAAQKfy8AAgEACQkvGTkgAGICAAEACQkvGTkgAGICAAAA.Zenedict:BAABLgAECn8YAAMhAAkJJBotGgB1AgAhAAkJJBotGgB1AgAeAAMJNgkFdgCFAAAAAA==.Zeniya:BAAALgADCgEJAQAAAA==.',
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
