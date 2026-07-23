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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Priest-Discipline','Priest-Holy','Unknown-Unknown','Warrior-Fury','Warlock-Destruction','Warlock-Affliction','Druid-Restoration','Druid-Balance','Paladin-Retribution','Druid-Guardian','Paladin-Protection','Hunter-Marksmanship','DeathKnight-Unholy','Paladin-Holy','Mage-Frost','DemonHunter-Devourer','Rogue-Subtlety','Warrior-Protection','Evoker-Augmentation','Monk-Brewmaster','Priest-Shadow','Monk-Mistweaver','Hunter-Survival','Evoker-Devastation','Evoker-Preservation','Monk-Windwalker','Warrior-Arms','Druid-Feral','Shaman-Elemental','DemonHunter-Havoc','Shaman-Restoration','Shaman-Enhancement','Mage-Arcane','DemonHunter-Vengeance','DeathKnight-Blood','Mage-Fire','DeathKnight-Frost',}
local provider = {region='US',realm='Rivendare',name='US',type='weekly',zone=46,date='2026-07-19',data={Ai='Aisling:BAAALgADCgYJBgAAAA==.',
Al='Alanispally:BAAALgADCgIJAQAAAA==.Algryn:BAAALgADCgUJBQAAAA==.Alkanz:BAABLgAECn8UAAIBAAkJKQwxYACpAQABAAkJKQwxYACpAQAAAA==.Allinaa:BAABLgAECn8cAAICAAkJwQ5ZUgCsAQACAAkJwQ5ZUgCsAQAAAA==.Alya:BAABLgAECn82AAMDAAkJPRY4AgA/AgADAAkJ2BQ4AgA/AgAEAAkJ9wrmKQB4AQAAAA==.',
Am='Ameliee:BAAALgAECgEJAQAAAA==.Amorvea:BAAALgADCgUJBQABLgAECgIJAgAFAAAAAA==.',
An='Angron:BAAALgADCgIJBQAAAA==.Anika:BAACLgAFFH8UAAIGAAQJkAW9GADIAAAGAAQJkAW9GADIAAAuAAQKfzUAAgYACQnXDuYvAI8BAAYACQnXDuYvAI8BAAAA.Antilight:BAAALgAECgcJAQAAAA==.',
Ar='Arcade:BAAALgAECgEJAgAAAA==.Arlyx:BAACLgAFFH8RAAMBAAUJRR7kXQAMAQABAAQJBSDkXQAMAQAHAAIJzxMHIABUAAAuAAQKfysABAEACAkmHwssACkCAAEABwlVGwssACkCAAcAAwnzFohHAJgAAAgAAgnoBzQfAHcAAAAA.Arnwaz:BAABLgAECn8UAAMJAAgJ7xU7MgDWAQAJAAgJ7xU7MgDWAQAKAAEJUw7ojAAzAAAAAA==.Arthuria:BAAALgAECgkJEwAAAA==.',
As='Aslan:BAAALgADCgQJBwAAAA==.',
At='Atelwen:BAAALgAECgcJBwAAAA==.',
Av='Avelyn:BAABLgAECn8WAAILAAkJax0oPwAKAgALAAkJax0oPwAKAgAAAA==.',
Ba='Babyruthie:BAAALgAECgMJBAAAAA==.Baf:BAACLgAFFH8MAAILAAQJaxe7RwAcAQALAAQJaxe7RwAcAQAuAAQKfxwAAgsACQmaHYY+ACsCAAsACQmaHYY+ACsCAAAA.Banjodave:BAAALgAECgUJBQAAAA==.Bayside:BAAALgAECgYJEQAAAA==.',
Be='Bearfomat:BAABLgAFFH8FAAIMAAMJFh6yEAABAQAMAAMJFh6yEAABAQAAAA==.Beefis:BAAALgAECgUJDAAAAA==.Beenjuicin:BAAALgAFFAEJAgABLgAFFAIJAgAFAAAAAA==.Berfomat:BAACLgAFFH8OAAINAAQJVxp5AwD9AAANAAQJVxp5AwD9AAAuAAQKfy0AAg0ACQnQIloDAOECAA0ACQnQIloDAOECAAAA.Berfy:BAAALgAFFAEJAQAAAA==.',
Bi='Bingchilling:BAACLgAFFH8bAAIOAAUJRBbpCgBrAQAOAAUJRBbpCgBrAQAuAAQKfzIAAg4ACQkFHp8EAGYCAA4ACQkFHp8EAGYCAAAA.',
Bj='Bjorn:BAACLgAFFH8KAAIPAAQJAA0oNQDyAAAPAAQJAA0oNQDyAAAuAAQKfxcAAg8ACAn0GAxHAO0BAA8ACAn0GAxHAO0BAAAA.',
Bl='Bloodyfupa:BAAALgAECgIJAgAAAA==.Bloomyvfd:BAACLgAFFH8MAAIQAAMJ7wpIGQByAAAQAAMJ7wpIGQByAAAuAAQKfz8AAhAACQk6H3UGACYDABAACQk6H3UGACYDAAAA.',
Bo='Bombuur:BAAALgAECgQJCAAAAA==.Bonniebadass:BAABLgAECn8VAAILAAgJRArznwA3AQALAAgJRArznwA3AQAAAA==.Bottle:BAABLgAECn8XAAIGAAgJrxt1HQACAgAGAAgJrxt1HQACAgAAAA==.Boxxylove:BAAALgAECgQJBwABLgAECgkJNgADAD0WAA==.',
Br='Bravas:BAAALgAECgcJBQAAAA==.Brimscythe:BAAALgADCgQJBAAAAA==.Broxar:BAAALgADCgcJCwAAAA==.',
['Bî']='Bîa:BAABLgAECn8rAAILAAkJOSTiAwBjAgALAAkJOSTiAwBjAgAAAA==.',
Ca='Cabbages:BAAALgADCgEJAQABLgAECgMJAwAFAAAAAA==.Cablemstache:BAAALgADCgcJBwAAAA==.Calisti:BAABLgAECn8tAAIRAAcJ/xvVZgAJAgARAAcJ/xvVZgAJAgAAAA==.Capybubger:BAABLgAECn8cAAISAAgJciB4FQCXAgASAAgJciB4FQCXAgABLgAFFAgJGgATAK0jAA==.Cavalis:BAACLgAFFH8UAAQHAAQJ4RJ+FACXAAABAAMJcg8keADSAAAHAAIJdRB+FACXAAAIAAEJhhDdIgBNAAAuAAQKfzQABAEACQmTG4M3APsBAAEACAm3GYM3APsBAAgABQmyF7ESAAEBAAcABAlsHOMWAOwAAAAA.',
Ce='Ceedh:BAAALgAFFAMJBAAAAA==.Ceejr:BAACLgAFFH8cAAMGAAkJRCGlAQDoAQAGAAUJ5iKlAQDoAQAUAAcJgx/BBgDcAQAuAAQKfyoAAwYACQlpJSQBAMQDAAYACQlpJSQBAMQDABQABgmLIlEQAOIBAAAA.Cerovallen:BAAALgAECgYJCQAAAA==.',
Ch='Chailee:BAAALgADCgEJAQAAAA==.Cherish:BAAALgADCgMJAwABLgAECgUJCgAFAAAAAA==.Chillum:BAAALgAECgIJAgABLgAFFAUJFgAVAKMWAA==.Chimneybeans:BAAALgADCgcJBwAAAA==.',
Co='Corny:BAAALgAECgUJCwAAAA==.',
Cr='Creativez:BAACLgAFFH8IAAIWAAIJxRmzGACoAAAWAAIJxRmzGACoAAAuAAQKfxYAAhYABwkIJK8OAKsCABYABwkIJK8OAKsCAAEuAAUUBAkOAAwApBsA.Creativezd:BAABLgAFFH8OAAIMAAQJpBtwCwA8AQAMAAQJpBtwCwA8AQAAAA==.',
Da='Dadgoo:BAAALgAECgYJEAAAAA==.Damnskippy:BAAALgAECgcJDQAAAA==.Dannÿ:BAABLgAECn8wAAMDAAkJlRjmHgDXAQADAAgJ+BnmHgDXAQAXAAQJwBD6TQDYAAAAAA==.Dantè:BAAALgAECgIJAgAAAA==.Daris:BAAALgADCgMJAwAAAA==.Darkire:BAACLgAFFH8QAAICAAYJNA+UNABEAQACAAYJNA+UNABEAQAuAAQKfyoAAgIACAkhHLo4APsBAAIACAkhHLo4APsBAAAA.Darkstar:BAAALgADCgUJBQAAAA==.Darkwarriorx:BAAALgADCgQJBAAAAA==.',
De='Deathlegion:BAAALgAECgQJBAAAAA==.Deathroll:BAABLgAECn8oAAIYAAkJNhnTEgCGAgAYAAkJNhnTEgCGAgAAAA==.Delarus:BAAALgAECgEJAQAAAA==.Demonarmor:BAAALgAECgMJCAABLgAECgcJCAAFAAAAAA==.Demonfist:BAAALgAECgkJCQAAAA==.Demonicfupa:BAAALgAECgkJCwABLgAECgUJDgAFAAAAAA==.',
Di='Diddley:BAAALgADCgMJAwAAAA==.',
Do='Dogmatik:BAAALgAECgEJAQABLgAECgMJAwAFAAAAAA==.Dontah:BAAALgAECggJCQABLgAFFAQJFAAZAJ4cAA==.Doomward:BAABLgAECn89AAIPAAkJXRSNCACOAQAPAAkJXRSNCACOAQAAAA==.Dorien:BAACLgAFFH8UAAIZAAQJnhzYDgBNAQAZAAQJnhzYDgBNAQAuAAQKfysAAxkACQmoIb0FAMkCABkACQmoIb0FAMkCAAIABAk6HQp1AFUBAAAA.',
Dr='Drachilly:BAACLgAFFH8WAAIVAAUJoxb8LAARAQAVAAUJoxb8LAARAQAuAAQKfyQABBUACQlcHg8bAP4BABUACQnZHQ8bAP4BABoABgknHj0QANgBABsAAQkPArFFABsAAAAA.Dragnar:BAABLgAECn8jAAICAAkJlwzuPQC3AQACAAkJlwzuPQC3AQAAAA==.Dragvalis:BAAALgADCgIJAgABLgAFFAQJFAAHAOESAA==.Drakbonespur:BAAALgAECggJEwAAAA==.Drhealzgood:BAAALgAECgQJBAAAAA==.Droggo:BAAALgADCgIJAgAAAA==.',
Er='Ermergerd:BAAALgAECgIJAgAAAA==.',
Ev='Evilvdduck:BAAALgAECgEJAQAAAA==.',
Ey='Eysia:BAAALgADCgUJCAAAAA==.',
Fa='Faemi:BAAALgAECgMJBAAAAA==.Faewryn:BAABLgAECn8YAAIQAAkJlxGJIgDwAQAQAAkJlxGJIgDwAQAAAA==.Faeya:BAAALgADCgEJAQABLgAECgYJGQAMAFIXAA==.Falekia:BAAALgAECgEJAQAAAA==.Fay:BAACLgAFFH8YAAIWAAYJyhpJEQCaAQAWAAYJyhpJEQCaAQAuAAQKfyIAAhYACQkuInwRAC0CABYACQkuInwRAC0CAAAA.',
Fe='Felltown:BAAALgADCgMJAwAAAA==.',
Fi='Firstblood:BAAALgAECggJCwAAAA==.Fishnchimps:BAABLgAFFH8NAAMYAAMJyRctNwDMAAAYAAMJyRctNwDMAAAcAAIJ9AWwOQBgAAAAAA==.',
Fr='Frenchtoast:BAAALgADCgMJAwAAAA==.Frogz:BAAALgAECgYJBwAAAA==.Frostyfupa:BAAALgADCgIJAgAAAA==.',
Fu='Fupalicious:BAAALgAFFAEJAQABLgAECgUJDgAFAAAAAA==.Furrburger:BAAALgADCgIJAgAAAA==.',
Ga='Gaiserik:BAABLgAECn8rAAIdAAkJRCEmBADfAgAdAAkJRCEmBADfAgAAAA==.Galenda:BAAALgAECgEJAQAAAA==.Gandolph:BAAALgADCgEJAQAAAA==.Garduhm:BAAALgADCgYJCQABLgAECgIJAgAFAAAAAA==.Garlictoast:BAAALgAECgQJBwAAAA==.',
Ge='Gearsofhate:BAAALgAECgEJAgAAAA==.Gehenna:BAAALgADCgYJCgAAAA==.Genga:BAAALgADCgYJBgAAAA==.',
Go='Goldenorder:BAAALgAECggJCgAAAA==.Gome:BAAALgADCgcJGwABLgAFFAMJDQAYAMkXAA==.Goodvbes:BAAALgAECgQJBAAAAA==.',
Gr='Gragolf:BAABLgAECn8fAAICAAkJlhU0PwDlAQACAAkJlhU0PwDlAQAAAA==.Greggor:BAAALgAECgYJDQAAAA==.Gronkus:BAAALgAECgYJBwAAAA==.',
Gu='Gustabo:BAABLgAECn8bAAIeAAYJGyI4DgDSAQAeAAYJGyI4DgDSAQAAAA==.',
['Gå']='Gåndalf:BAAALgAECgEJAgAAAA==.',
Ha='Haslin:BAAALgADCgEJAgAAAA==.Havibonespur:BAABLgAECn8XAAMWAAYJXQtcSgDTAAAWAAYJXQtcSgDTAAAcAAEJyQTYuwAeAAABLgAECggJEwAFAAAAAA==.',
He='Healir:BAABLgAECn8TAAMDAAgJZiJHGgD+AQADAAgJZiJHGgD+AQAXAAQJnh/ULAB3AQABLgAFFAUJCAAVAGsXAA==.Healmepls:BAAALgADCgYJCgABLgAFFAUJDAAfAHcPAA==.Hellsong:BAAALgAECgEJAQAAAA==.Helor:BAABLgAECn8XAAMSAAkJcRZBQADIAQASAAkJcRZBQADIAQAgAAUJ3RXDLgBXAQAAAA==.',
Hi='Hiéi:BAAALgAECgEJAQAAAA==.',
Ho='Holydeath:BAABLgAECn8YAAIEAAcJwB3PFAAvAgAEAAcJwB3PFAAvAgAAAA==.Hotboydragon:BAABLgAFFH8IAAIVAAUJaxc2KAAqAQAVAAUJaxc2KAAqAQAAAA==.Hotpocketz:BAAALgADCgcJCQABLgAECggJFwAGACoXAA==.',
Hu='Hughjazz:BAAALgAECggJDgAAAA==.Hunterish:BAAALgADCgEJAQAAAA==.',
Ia='Iadrithe:BAAALgADCgYJBgAAAA==.',
Im='Impossiberf:BAAALgAECgYJBgAAAA==.',
In='Inspectadeck:BAAALgAECgMJBAAAAA==.Inthezone:BAAALgAECgkJCgAAAA==.Invisus:BAABLgAECn8WAAIGAAcJZxkNJwDBAQAGAAcJZxkNJwDBAQAAAA==.',
Is='Ispayderj:BAAALgAECgMJBAAAAA==.',
Ja='Jahy:BAAALgADCgIJAgAAAA==.Jake:BAACLgAFFH8MAAILAAUJ3SAbIgB/AQALAAUJ3SAbIgB/AQAuAAQKfykAAgsACQkkJt4EAFEDAAsACQkkJt4EAFEDAAAA.Jarlan:BAACLgAFFH8hAAIdAAUJZSNNCwCUAQAdAAUJZSNNCwCUAQAuAAQKfykAAh0ACAmRI7sBACMDAB0ACAmRI7sBACMDAAAA.Jarlhun:BAABLgAECn8dAAIOAAcJjh06CQDlAQAOAAcJjh06CQDlAQABLgAFFAUJIQAdAGUjAA==.Jarmon:BAAALgAFFAEJAgABLgAFFAUJIQAdAGUjAA==.',
Je='Jellous:BAACLgAFFH8GAAMSAAIJpQY3jwBkAAASAAIJBgU3jwBkAAAgAAEJZwv7DQBOAAAuAAQKfyoAAyAACQmCF5MTADgCACAACAl5GJMTADgCABIACQllFN4zACoCAAAA.Jethereal:BAAALgADCgcJBwABLgAFFAIJBgASAKUGAA==.',
Ju='Jurista:BAAALgADCgYJBgAAAA==.Justen:BAAALgADCgMJAwAAAA==.Justin:BAAALgAECgYJBgAAAA==.',
Ke='Ketharion:BAABLgAECn8rAAMQAAkJ5RXXHAAcAgAQAAkJ5RXXHAAcAgALAAEJigvnrAEqAAAAAA==.Kevamin:BAABLgAECn8nAAILAAkJUhWzPAARAgALAAkJUhWzPAARAgAAAA==.',
Kh='Khaela:BAAALgAECgIJAgAAAA==.Khato:BAABLgAECn8TAAIfAAkJnRYSRgAbAQAfAAkJnRYSRgAbAQAAAA==.',
Ki='Killznkrushz:BAAALgAECgEJAQABLgAECggJJAARAMUbAA==.Kirasha:BAAALgADCgcJBwAAAA==.',
Ku='Kulfa:BAAALgADCgcJCgAAAA==.Kurailos:BAAALgADCggJCAAAAA==.Kurisu:BAAALgAECgQJCAAAAA==.',
La='Lailyne:BAABLgAECn8fAAQZAAkJ+BOzJwBhAQAZAAcJIA2zJwBhAQAOAAYJ8A2mRgA6AQACAAUJexQPnAAJAQAAAA==.Lake:BAAALgAECgcJDAAAAA==.Lastcast:BAAALgAECgEJAQABLgAECgcJEgAFAAAAAA==.Laîlyne:BAAALgAECgYJBgABLgAECgkJHwAZAPgTAA==.',
Le='Learned:BAABLgAECn8VAAIPAAgJzArLjwBGAQAPAAgJzArLjwBGAQAAAA==.Leo:BAABLgAECn8bAAIUAAkJwR74BwB+AgAUAAkJwR74BwB+AgAAAA==.Leone:BAAALgAECgYJBwAAAA==.',
Li='Lilany:BAACLgAFFH8IAAIhAAMJWQ8ZWACdAAAhAAMJWQ8ZWACdAAAuAAQKfxUAAiEACQlPFqI+ALQBACEACQlPFqI+ALQBAAAA.Lillymeii:BAAALgAECgEJAQAAAA==.Linova:BAAALgADCgUJBQAAAA==.Lithrak:BAABLgAECn8wAAIiAAkJ0B8rBADfAgAiAAkJ0B8rBADfAgAAAA==.',
Lo='Logical:BAAALgAFFAEJAgAAAA==.Lorakine:BAAALgADCgUJBQAAAA==.',
Lu='Luciferr:BAAALgADCgEJAQAAAA==.Lucit:BAAALgAECgYJCgABLgAFFAUJEQABAEUeAA==.Lute:BAAALgAECgQJCAAAAA==.',
Ly='Lyric:BAAALgADCgcJDAABLgAFFAYJGAAWAMoaAA==.',
['Lá']='Lárien:BAABLgAECn8XAAIJAAcJsxTgQwCBAQAJAAcJsxTgQwCBAQAAAA==.',
Ma='Mable:BAAALgADCggJCAAAAA==.Magicmicah:BAAALgADCgcJBwAAAA==.Maldamba:BAAALgADCgcJBwAAAA==.Manon:BAACLgAFFH8YAAIhAAYJIhqsEgDRAQAhAAYJIhqsEgDRAQAuAAQKfx8AAyEACQn9FBEtANYBACEACQn9FBEtANYBAB8AAQm+B3i3ACUAAAAA.',
Mc='Mcchungus:BAACLgAFFH8HAAMZAAMJHA6ZIwC7AAAZAAMJ2gaZIwC7AAACAAIJaw8WhQCRAAAuAAQKfxwAAxkACAlQGNAdAK4BABkABwlZFdAdAK4BAAIABwmVFdptAGUBAAAA.',
Me='Meliodas:BAAALgAECgQJBgAAAA==.Menghao:BAABLgAECn8qAAMRAAkJUgjBgwBwAQARAAkJUgjBgwBwAQAjAAIJ3AFqGgBEAAAAAA==.Meowmixx:BAAALgAECgcJAwAAAA==.Metiss:BAAALgAECgcJDgABLgAFFAQJFAAHAOESAA==.',
Mi='Mikala:BAAALgADCgQJBAAAAA==.Mikayybrew:BAAALgADCgUJBQAAAA==.Mischief:BAACLgAFFH8mAAMIAAYJShB0AQBlAQAIAAYJShB0AQBlAQABAAEJBQR2ZQA3AAAuAAQKf1kAAggACQmAH0UAAMgCAAgACQmAH0UAAMgCAAAA.Mistorfistor:BAAALgAECgQJCgAAAA==.',
Mk='Mk:BAEALgAECgQJCQABLgAECgkJTQAcAIoiAA==.',
Mo='Mooage:BAACLgAFFH8GAAIRAAIJYiDBMwDLAAARAAIJYiDBMwDLAAAuAAQKfzMAAhEACQmcJBcMAGQDABEACQmcJBcMAGQDAAAA.Morewyn:BAABLgAECn8nAAICAAkJVBJ4PQDrAQACAAkJVBJ4PQDrAQAAAA==.Mozoh:BAAALgADCgMJAwABLgAECgIJAgAFAAAAAA==.',
Na='Nadok:BAAALgAECgkJBgAAAA==.Nalock:BAAALgAECgYJBgAAAA==.',
Ne='Nerrgall:BAAALgADCgcJBwAAAA==.',
Ni='Nickignomaj:BAABLgAECn8pAAQcAAgJYh74DQBnAgAcAAgJYh74DQBnAgAYAAQJLBElRwC+AAAWAAUJswY5XQCZAAABLgAFFAQJDQAdAAMTAA==.Nidhogg:BAAALgADCgcJBwABLgAECgkJIQAhANcaAA==.Nisara:BAACLgAFFH8GAAIBAAMJRAqhMQC1AAABAAMJRAqhMQC1AAAuAAQKfyQAAgEACQl9EHELABwBAAEACQl9EHELABwBAAAA.',
No='Noellie:BAAALgAFFAEJAgAAAA==.Noobdestroya:BAAALgAECgQJEAAAAA==.Nosfuratu:BAAALgADCgkJCQAAAA==.',
Ny='Nymi:BAAALgADCgYJBgAAAA==.',
Of='Offline:BAAALgADCgcJCwAAAA==.',
Ol='Oldbutcool:BAAALgADCgEJAgAAAA==.Oldicyfupa:BAAALgAECgYJBwAAAA==.',
Om='Omantul:BAABLgAECn8hAAMhAAkJ1xqGIgAQAgAhAAgJDRqGIgAQAgAfAAYJUBlxUgDvAAAAAA==.',
Or='Orangez:BAAALgAECgMJBAAAAA==.',
Ou='Ouija:BAAALgAECgEJAQAAAA==.',
Ow='Owocoxl:BAAALgAECgIJAgABLgAFFAUJEgATALkQAA==.',
Pa='Painfull:BAABLgAECn8jAAISAAgJpB08MQABAgASAAgJpB08MQABAgAAAA==.Pants:BAAALgAECgEJAgAAAA==.Pantzor:BAAALgADCgEJAQAAAA==.Paz:BAAALgADCgcJBwABLgAECgIJAgAFAAAAAA==.',
Ph='Phakes:BAAALgAECgUJCAAAAA==.Phengzera:BAABLgAECn8WAAIRAAcJMBX3dADoAQARAAcJMBX3dADoAQAAAA==.Phizz:BAABLgAFFH8MAAISAAQJaRfFPgAsAQASAAQJaRfFPgAsAQAAAA==.',
Pn='Pneumagloom:BAAALgAECgMJAwAAAA==.',
Po='Po:BAAALgADCgcJDQABLgAFFAYJEwAgACcZAA==.Pontius:BAAALgADCgMJAwABLgAECgkJDgAFAAAAAA==.',
Pr='Prowlborn:BAAALgADCgEJAQAAAA==.',
Pu='Puke:BAABLgAECn8zAAIkAAkJXiWPAABUAwAkAAkJXiWPAABUAwAAAA==.Pumpkinspice:BAAALgADCgYJCQAAAA==.Purplepower:BAAALgAECgMJBAAAAA==.',
Ra='Rarim:BAAALgAECgkJDgAAAA==.',
Re='Reaperfive:BAAALgADCgcJBwAAAA==.Redbonespur:BAAALgADCgcJBwABLgAECggJEwAFAAAAAA==.',
Ri='Rimtardo:BAAALgAECgQJBwAAAA==.Rio:BAAALgAECgMJAwABLgAFFAQJCgABALkQAA==.',
Ro='Rotdaddy:BAABLgAECn8aAAITAAgJ4BGHLQCVAQATAAgJ4BGHLQCVAQAAAA==.Roxxev:BAAALgADCgcJBwAAAA==.',
Ry='Ryø:BAABLgAECn8jAAMJAAkJsgdkWwBAAQAJAAkJsgdkWwBAAQAMAAgJ3AgSNQDTAAAAAA==.',
Sa='Saintrandy:BAAALgADCgMJAwAAAA==.Saphiel:BAAALgAECgEJAQAAAA==.',
Sc='Scorch:BAAALgADCgcJCgAAAA==.',
Se='Seigler:BAAALgAECgEJAQAAAA==.Seraphym:BAAALgADCgYJCAAAAA==.',
Sh='Shaviji:BAAALgAECgcJBwAAAA==.Sheldor:BAAALgAECgEJAQAAAA==.Shinra:BAAALgADCgEJAQABLgAECgcJEgAFAAAAAA==.Shore:BAABLgAECn8eAAMZAAkJ8xtWDQBRAgAZAAkJ8xtWDQBRAgAOAAYJQRKXFAAZAQAAAA==.Shrekw:BAAALgAECgcJEwAAAA==.Shuralya:BAACLgAFFH8dAAMLAAUJ6R0dMwBJAQALAAUJ6R0dMwBJAQAQAAMJURI8MwCjAAAuAAQKf0MAAwsACQkhJCcHADUDAAsACQkhJCcHADUDABAACQk9GH0gABcCAAAA.',
Si='Silverhorn:BAABLgAECn8UAAIVAAgJ0A5YMwBnAQAVAAgJ0A5YMwBnAQAAAA==.Siouxsie:BAAALgADCgcJCgAAAA==.',
Sm='Smoldnrg:BAAALgAECgUJBQAAAA==.',
So='Sofka:BAABLgAECn8fAAMlAAkJCQ5uGgB+AQAlAAkJCQ5uGgB+AQAPAAEJMgHwOwEbAAAAAA==.Souliel:BAAALgAECgEJAQAAAA==.Sourpatch:BAAALgAECgIJAgAAAA==.',
St='Stilts:BAABLgAECn8UAAMiAAcJpxyHDQDXAQAiAAcJpxyHDQDXAQAhAAQJsAVNfwCWAAAAAA==.Stradynia:BAABLgAECn8UAAQgAAkJVxrUHADaAQAgAAkJVxrUHADaAQAkAAIJLwoVBwBnAAASAAEJzQKTPQEYAAAAAA==.Stuart:BAAALgADCgMJAwABLgAECgIJAgAFAAAAAA==.Stócky:BAAALgAECgcJEwAAAA==.',
Su='Sui:BAAALgADCgUJCAABLgAECgYJGQAMAFIXAA==.Survas:BAACLgAFFH8QAAITAAYJrA5rEQCFAQATAAYJrA5rEQCFAQAuAAQKfyEAAhMACQnsGj8cALQBABMACQnsGj8cALQBAAAA.',
Sw='Swobu:BAAALgAECgEJAQAAAA==.',
Sy='Sylvanna:BAABLgAECn8ZAAMMAAYJUhfZBABKAQAMAAYJUhfZBABKAQAeAAIJ0xKkCQBvAAAAAA==.Sylwynn:BAAALgADCgUJCAAAAA==.',
['Sá']='Sárkány:BAAALgADCgcJCQAAAA==.',
Ta='Talanaz:BAAALgAECgYJDAAAAA==.Taleah:BAAALgAECgEJAgAAAA==.Taleb:BAAALgAECgYJEAABLgAECgcJDQAFAAAAAA==.Tardor:BAAALgADCgMJAwAAAA==.Tavgoesboom:BAAALgAFFAIJAgABLgAFFAMJDQAYAMkXAA==.Tawna:BAAALgAECgQJBQAAAA==.',
Te='Tealan:BAABLgAECn8VAAQVAAgJuRZGKAB7AQAVAAcJSxVGKAB7AQAbAAYJmhTVJwA1AQAaAAEJOQjJQAAvAAAAAA==.Tenyi:BAAALgAECgMJAwAAAA==.Terrin:BAAALgAECgQJBQABLgAECgcJDQAFAAAAAA==.',
Th='Thor:BAAALgAECgEJAgAAAA==.',
To='Toospooky:BAABLgAECn8VAAQXAAcJFhjfNQA/AQAXAAYJGhffNQA/AQADAAUJXgkUTADUAAAEAAEJ0AaidAAlAAAAAA==.Tovlacar:BAAALgAECgUJBgABLgAECgkJMAADAO0PAA==.Toyboy:BAAALgAECgQJBAAAAA==.',
Tr='Triage:BAABLgAECn8VAAQjAAgJjhxsBAAFAgAjAAUJCSRsBAAFAgARAAUJOhUE5gDSAAAmAAEJTRYmEwA7AAAAAA==.Trolladin:BAAALgAFFAEJAQAAAA==.Tronarn:BAAALgAECgcJDQAAAA==.',
Ug='Ugin:BAACLgAFFH8UAAMPAAQJ4RM6JgAsAQAPAAQJ4RM6JgAsAQAnAAMJ4waJGgC1AAAuAAQKfywAAycACQlmGF4KANgBACcACQkXFl4KANgBAA8ACAk+FtoYAMUAAAAA.',
Um='Umaydie:BAAALgAECgIJAwAAAA==.Umbrasyl:BAAALgAECggJEwAAAA==.',
Un='Unclecharlie:BAAALgAFFAMJAwABLgAFFAUJDgAnALQdAA==.Unholylukers:BAAALgAECgIJAwAAAA==.Unit:BAAALgADCgcJCwAAAA==.',
Va='Valkiere:BAAALgADCgEJAQAAAA==.Valkrit:BAAALgADCgIJAgAAAA==.Vasrin:BAACLgAFFH8MAAIiAAQJnRxSBgBXAQAiAAQJnRxSBgBXAQAuAAQKfzMAAiIACQnmIYcDAMwCACIACQnmIYcDAMwCAAAA.',
Ve='Velaria:BAAALgADCgYJEAABLgAECgYJDAAFAAAAAA==.Venitaurus:BAAALgAECgEJAQAAAA==.Veon:BAAALgADCgYJBgAAAA==.Verlehn:BAAALgADCgcJBgAAAA==.',
Vi='Victra:BAAALgAECgEJAgAAAA==.',
Vo='Voidomo:BAAALgAFFAIJBAAAAA==.Vonbearback:BAABLgAFFH8GAAIPAAMJPQSivwCqAAAPAAMJPQSivwCqAAAAAA==.',
Wa='Walden:BAABLgAECn8XAAIMAAcJJhZRIABLAQAMAAcJJhZRIABLAQAAAA==.Waterlance:BAAALgAECgEJBgAAAA==.',
We='Weeniefuyu:BAAALgAECgMJBgAAAA==.',
Wi='Wildfupa:BAAALgAECggJCwAAAA==.Wisecraic:BAABLgAECn8eAAIJAAYJ2hSTCQDqAAAJAAYJ2hSTCQDqAAAAAA==.Wispi:BAAALgAECgQJBAAAAA==.',
Wo='Wocoxl:BAACLgAFFH8SAAITAAUJuRBJHgAvAQATAAUJuRBJHgAvAQAuAAQKfycAAhMACQlIHbUGACQDABMACQlIHbUGACQDAAAA.',
Xe='Xerah:BAAALgADCggJDgAAAA==.',
Ya='Yaracklea:BAABLgAECn8XAAIEAAkJuRW6EwA7AgAEAAkJuRW6EwA7AgAAAA==.',
Yi='Yingu:BAAALgADCgEJAQAAAA==.',
['Yü']='Yüki:BAAALgAECgIJBAAAAA==.',
Za='Zabaniya:BAAALgAECgQJBQAAAA==.Zac:BAAALgADCgYJDAAAAA==.Zacceptable:BAABLgAECn8VAAIjAAcJWBSCCQBRAQAjAAcJWBSCCQBRAQAAAA==.Zaida:BAAALgADCgUJBQABLgAECgIJAgAFAAAAAA==.',
Ze='Zeale:BAACLgAFFH8KAAIBAAQJuRD7UwAeAQABAAQJuRD7UwAeAQAuAAQKfy8AAgEACQkvGdMgAGACAAEACQkvGdMgAGACAAAA.Zenedict:BAACLgAFFH8LAAIhAAQJ6A4jIADAAAAhAAQJ6A4jIADAAAAuAAQKfx4AAyEACQlSHMEaAHUCACEACQlSHMEaAHUCAB8AAwk2CVV4AIUAAAAA.Zeniya:BAAALgADCgEJAQAAAA==.',
Zh='Zharsha:BAAALgADCgkJCQAAAA==.',
Zs='Zsofi:BAAALgAFFAEJAQAAAA==.',
Zu='Zulubonespur:BAAALgAECgEJAQABLgAECggJEwAFAAAAAA==.',
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
