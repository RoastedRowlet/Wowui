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

local lookup = {'Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Warlock-Demonology','DemonHunter-Devourer','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Arcane','Priest-Holy','DeathKnight-Blood','Paladin-Protection','Warlock-Destruction','Druid-Balance','Monk-Windwalker','Priest-Discipline','Druid-Restoration','Druid-Feral','Paladin-Holy','Warrior-Protection','Warrior-Arms','DemonHunter-Vengeance','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Havoc','Mage-Frost','Shaman-Restoration','Priest-Shadow','Monk-Mistweaver','Monk-Brewmaster','Warlock-Affliction','Paladin-Retribution','Mage-Fire','Evoker-Preservation','Warrior-Fury','Evoker-Devastation',}
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abednego:BAABNQAECn8xAAMBAAkKrxdVDgCSAgABAAkKZRdVDgCSAgACAAQKFQ4ZPAB8AAAAAA==.',
Ac='Acidrain:BAABNQAECn8wAAIDAAkKAxsEIgDvAQADAAkKAxsEIgDvAQAAAA==.Acmiax:BAAANQAECgQICwABNQAECgoKLgAEAMAVAA==.',
Ad='Adar:BAAANQAECgUIDwAAAA==.Adonsinn:BAABNQAECn8cAAIFAAgKMCGPGQCOAgAFAAgKMCGPGQCOAgAAAA==.',
Ae='Aegos:BAAANQAECgQIBgAAAA==.Aep:BAAANQAECgMJBAABNQAECgUIDQAGAAAAAA==.',
Ah='Ahu:BAABNQAECn81AAMHAAkK3hbUSACSAgAHAAkK3hbUSACSAgAIAAEKKgZMlQArAAAAAA==.',
Ai='Aiden:BAAANQAECgYIBgAAAA==.',
Al='Alakazam:BAAANQADCgUIBgAAAA==.Alanath:BAAANQADCgQIBAAAAA==.Alandramun:BAAANQAECgIIAgAAAA==.Aleroderp:BAABNQAECn8cAAIIAAkKHQQoIgDsAAAIAAkKHQQoIgDsAAAAAA==.Allaria:BAAANQAECgIIBQAAAA==.Alucard:BAAANQAECgIIAgAAAA==.',
Am='Amaging:BAABNQAECn8lAAIJAAkKqgqmxAD7AQAJAAkKqgqmxAD7AQAAAA==.Ambassador:BAAANQAECgUIBQAAAA==.Amoondai:BAACNQAFFH8JAAIKAAMK4Q9pGwCfAAAKAAMK4Q9pGwCfAAA1AAQKf0YAAgoACgr9IusNAFUDAAoACgr9IusNAFUDAAAA.',
An='Analytics:BAAANQAECgcIEQAAAA==.Angusdei:BAAANQADCgIIAgAAAA==.Anyr:BAAANQADCgMIAwAAAA==.',
Ap='Apochryphal:BAABNQAECn8yAAILAAkKnyCCDQBtAgALAAkKnyCCDQBtAgAAAA==.',
Ar='Araon:BAAANQAECgMIAwAAAA==.Araylva:BAAANQADCggIDwAAAA==.Arienei:BAAANQABCgQIBQAAAA==.Arrtemiss:BAAANQADCgMIAwABNQAECgUIDgAGAAAAAA==.',
As='Ashogg:BAAANQAECgYIEQAAAA==.',
Au='Aurén:BAAANQADCggIEwAAAA==.',
Az='Azuree:BAAANQAECgIIBAAAAA==.',
Ba='Bacstabath:BAABNQAECn9CAAMCAAoK5iIODwAJAwACAAgKKCMODwAJAwABAAoKYR7TDwB/AgAAAA==.Baelgrimm:BAAANQAECgQIDAAAAA==.',
Be='Becca:BAABNQAECn85AAIMAAoKYB0kBwBuAgAMAAoKYB0kBwBuAgAAAA==.Bequin:BAAANQADCgUIBQAAAA==.',
Bi='Bigdaddys:BAAANQAECgMIAgAAAA==.Bigduh:BAAANQADCgQIBAAAAA==.Birblock:BAABNQAECn8/AAMEAAoKGCJ8CgDeAgAEAAoKGCJ8CgDeAgANAAQK8A9YNgDoAAABNQAFFAcIFwAOANYSAA==.',
Bl='Blaizee:BAAANQAECgEIAQAAAA==.Blasphemar:BAAANQADCgYJBgAAAA==.Bloodios:BAABNQAECn8+AAILAAoKbhs0DgBjAgALAAoKbhs0DgBjAgAAAA==.Bluechewgold:BAABNQAECn8mAAILAAoKMCHJCgBeAwALAAoKMCHJCgBeAwAAAA==.',
Bo='Bobbardment:BAAANQADCgQIBAABNQAECgQIBAAGAAAAAA==.Bobin:BAABNQAECn8gAAIPAAoKCRBKKQDUAQAPAAoKCRBKKQDUAQAAAA==.Bombadil:BAABNQAECn8rAAIQAAkKWA8fAwDAAQAQAAkKWA8fAwDAAQAAAA==.Boshek:BAAANQABCgUJCQAAAA==.',
Br='Bribage:BAACNQAFFH8XAAMOAAcK1hLKDwBtAQAOAAcK1hLKDwBtAQARAAEKowkQFQBKAAA1AAQKfyoAAw4ACgr3IfgRACoCAA4ACgr3IfgRACoCABIAAgrWGXIrAEQAAAAA.Brightest:BAAANQAECgIIAQAAAA==.Brolaf:BAAANQADCgIIAgABNQAFFAYIFQATAB0kAA==.Brolavski:BAABNQAFFH8VAAITAAYKHSQvBgANAgATAAYKHSQvBgANAgAAAA==.',
Bu='Budderwar:BAABNQAECn83AAMUAAkKZSYJAQDKAwAUAAkKZSYJAQDKAwAVAAQK9RGs9QDzAAAAAA==.Buster:BAABNQAECn8cAAMWAAoKhAnLFQBPAQAWAAoKhAnLFQBPAQAFAAQKhQMZYQBpAAAAAA==.Buzkills:BAAANQABCgIIAwAAAA==.',
['Bà']='Bàdmofos:BAAANQADCgcIBwAAAA==.',
Ce='Celerydk:BAABNQAECn85AAIXAAoKmhsrGADJAgAXAAoKmhsrGADJAgAAAA==.',
Ch='Chaosgaara:BAAANQADCgEIAQAAAA==.Chikñ:BAAANQAECgQIAQAAAA==.',
Co='Colossus:BAABNQAECn8gAAMYAAoKlx6QJQCoAgAYAAoKlx6QJQCoAgALAAMKUgtDqQB+AAAAAA==.Connor:BAAANQAECgIIBAAAAA==.Correin:BAABNQAECn81AAIZAAoKLRJgFgD4AQAZAAoKLRJgFgD4AQAAAA==.',
Cr='Craszhin:BAABNQAECn8xAAIOAAkKTw3VIQB2AQAOAAkKTw3VIQB2AQAAAA==.Crime:BAAANQAECgMIAwAAAA==.',
['Cè']='Cèl:BAABNQAECn81AAMaAAoKQBANCACjAQAaAAoKQBANCACjAQAJAAUKCAOUogF9AAAAAA==.',
Da='Daddio:BAEANQAECgQIBwAAAA==.Dadeb:BAAANQAECgUIBQABNQAECgoKLgAEAMAVAA==.Daenarea:BAAANQADCgYIBgAAAA==.Dangpup:BAABNQAECn8zAAIIAAoKrxcEGQCPAgAIAAoKrxcEGQCPAgAAAA==.Danru:BAAANQADCgQICwAAAA==.Darkdelight:BAABNQAECn87AAIHAAoKQRbOUQB7AgAHAAoKQRbOUQB7AgAAAA==.',
De='Deathlylazy:BAAANQAECgcICgAAAA==.Deets:BAABNQAECn8qAAIHAAkKlCDyIwBUAgAHAAkKlCDyIwBUAgAAAA==.Demona:BAABNQAECn8xAAMNAAkKpgyWBABWAQANAAkKpgyWBABWAQAEAAEKEwE7WgEcAAAAAA==.Derfhurnturr:BAAANQAECgUIBgAAAA==.Descalabrada:BAAANQAECgcIDAAAAA==.',
Di='Distol:BAAANQADCgIIAgAAAA==.',
Dm='Dmt:BAAANQAECgIIAgAAAA==.',
Dr='Draeamorjan:BAAANQADCgEIAQAAAA==.Driver:BAEANQAECgYIBgABNQAECggICAAGAAAAAA==.Drpeppers:BAABNQAECn8pAAIRAAkKlxNiFgDIAQARAAkKlxNiFgDIAQAAAA==.',
['Dé']='Déathsavage:BAAANQADCggIHwAAAA==.',
Ea='Eatmorchikin:BAAANQAECgEIAQAAAA==.',
Ec='Eclair:BAABNQAECn8yAAIbAAkKuiEqDAADAwAbAAkKuiEqDAADAwAAAA==.',
El='Elfkr:BAABNQAECn8eAAMbAAgKJiEDIwDbAgAbAAgKJiEDIwDbAgADAAIK+hif+wCbAAAAAA==.Elhayn:BAABNQAECn8uAAIcAAkK6yOMCABUAwAcAAkK6yOMCABUAwAAAA==.Elmos:BAABNQAECn87AAIPAAoKviHtBwBQAwAPAAoKviHtBwBQAwAAAA==.',
Er='Erethidian:BAAANQADCgQIBAAAAA==.Eris:BAAANQAECgMIAwAAAA==.',
Eu='Eucalyptus:BAAANQAECgQIAwAAAA==.',
Ev='Evilmonkeydr:BAAANQAECgQIBAABNQAECgoKHwAJAD0eAA==.Evilmonkeymg:BAABNQAECn8fAAIJAAoKPR5wWwDJAgAJAAoKPR5wWwDJAgAAAA==.Evilmonkeysh:BAAANQADCgUIBQABNQAECgoKHwAJAD0eAA==.',
Ez='Ezaylia:BAABNQAECn8qAAIZAAkKkA+0IQCIAQAZAAkKkA+0IQCIAQAAAA==.',
Fa='Fatehunter:BAABNQAECn8cAAIHAAcKuhLAmADWAQAHAAcKuhLAmADWAQAAAA==.',
Fe='Feim:BAAANQADCggICAAAAA==.Fergis:BAABNQAECn8vAAMaAAkKKBzUBAAYAgAaAAgKKBzUBAAYAgAJAAYKGxSc+wCWAQAAAA==.',
Fi='Firefox:BAABNQAECn8dAAILAAkKORlONgAyAgALAAkKORlONgAyAgAAAA==.',
Fl='Flypig:BAAANQADCggIBwAAAA==.',
Fr='Frostybeary:BAAANQABCgYIBwAAAA==.Frostymonk:BAABNQAECn8aAAMdAAkKFQtkJQBPAQAdAAcKbw1kJQBPAQAeAAIKlAQxGgBOAAAAAA==.Frostypally:BAAANQAECggIDwAAAA==.',
Fu='Fuel:BAAANQADCgYIBgABNQAECgYIDwAGAAAAAA==.Furrybear:BAAANQAECgEIAgAAAA==.',
Ga='Gala:BAABNQAECn8bAAIJAAoKaBU/LwA0AgAJAAoKaBU/LwA0AgAAAA==.',
Ge='Genorian:BAABNQAECn8lAAIOAAoKlRXhEgAdAgAOAAoKlRXhEgAdAgAAAA==.',
Gi='Gigem:BAABNQAECn8ZAAIHAAcKjhqsiwDzAQAHAAcKjhqsiwDzAQAAAA==.Girlshoon:BAAANQAECgEIAgAAAA==.Githan:BAAANQAECgYIDAABNQAECgkJJwARAK0bAA==.',
Gl='Glarheals:BAAANQADCgEIAQABNQAECgoKMgABAFYRAA==.Glarious:BAABNQAECn8yAAIBAAoKVhH3FAA/AgABAAoKVhH3FAA/AgAAAA==.',
Go='Gobbozap:BAAANQADCggIDgABNQAECgoKMgAQAA4gAA==.',
Gr='Gredan:BAABNQAECn8cAAILAAcK4BaSLgA0AQALAAcK4BaSLgA0AQAAAA==.Greymoor:BAAANQABCgQIBAAAAA==.Gruhm:BAAANQADCgUIBQAAAA==.Grôg:BAAANQAECggICgAAAA==.',
Gu='Guldaniel:BAABNQAECn8uAAIEAAoKwBX/PQCZAgAEAAoKwBX/PQCZAgAAAA==.Guthuzad:BAAANQADCgUIBgAAAA==.Guthx:BAABNQAECn8eAAMOAAoKzxkYRADjAQAOAAcK7BcYRADjAQARAAUKIBDdOwCpAAAAAA==.',
Ha='Halfaman:BAAANQAECgQIBgABNQAFFAIIAgAGAAAAAA==.Hantzel:BAAANQADCgUIBQAAAA==.',
He='Healyeah:BAAANQAECgEIAQAAAA==.Hellen:BAABNQAECn8bAAIEAAoKnSDuLADSAgAEAAoKnSDuLADSAgAAAA==.',
Hw='Hwat:BAAANQAECgYIDwAAAA==.',
Ic='Ictus:BAABNQAECn8ZAAIJAAoK+RzjcACcAgAJAAoK+RzjcACcAgAAAA==.',
In='Incredabull:BAAANQAECgIIAgAAAA==.',
Is='Isabelle:BAACNQAFFH8KAAIIAAMKHQcqDACkAAAIAAMKHQcqDACkAAA1AAQKfzQAAggACQrwFg8RALQBAAgACQrwFg8RALQBAAAA.Isharded:BAABNQAECn84AAIfAAoK3hHkAgALAgAfAAoK3hHkAgALAgAAAA==.Istayblunted:BAAANQAECgUICgAAAA==.',
Ja='Jacqualyn:BAAANQAFFAIIAgAAAA==.Jaylon:BAAANQADCgUIBQAAAA==.',
Ji='Jiayerah:BAAANQADCggIDwABNQAECgcIHAAKAFwWAA==.Jinkuzo:BAABNQAECn8uAAIeAAkKCRqLBADyAQAeAAkKCRqLBADyAQAAAA==.Jinmu:BAABNQAECn8yAAMBAAkKhRItGQAQAgABAAkKhRItGQAQAgACAAcKJwjeVgBfAQAAAA==.',
Ju='Juanaloopa:BAAANQAECgcIDAAAAA==.Juggie:BAABNQAECn8dAAMKAAcKVwWCnQA9AQAKAAcKVwWCnQA9AQAcAAUKXwSwVAC7AAAAAA==.Julienned:BAABNQAECn83AAICAAoK4xByCQDyAQACAAoK4xByCQDyAQAAAA==.',
['Jè']='Jèsse:BAAANQADCgcJBwAAAA==.',
Ka='Kainen:BAABNQAECn8yAAQgAAkKOBnYTQDMAQAgAAkKOBnYTQDMAQATAAQKGQOP8QCdAAAMAAQK4QNSWgBzAAAAAA==.',
Ki='Kinkybunny:BAAANQADCgYJBgAAAA==.',
Kl='Klodar:BAABNQAECn8gAAIcAAgKyxMsFgBtAQAcAAgKyxMsFgBtAQAAAA==.Klum:BAAANQABCgQIBgAAAA==.',
Kr='Krazee:BAAANQABCgMIBQAAAA==.',
La='Lafey:BAAANQADCgIJAgAAAA==.Lamedout:BAAANQADCgcIBwABNQAECgYIDwAGAAAAAA==.Lanfear:BAAANQADCgQIBAAAAA==.Laurenya:BAAANQADCgMIAwABNQAECgUIDgAGAAAAAA==.',
Le='Leida:BAAANQADCgcICwAAAA==.Leinen:BAAANQADCgYIBwAAAA==.',
Lo='Logi:BAAANQAECgUIDQAAAA==.Lostrage:BAAANQADCgcICgAAAA==.',
Lu='Lumiyer:BAABNQAECn8hAAIKAAoKjxoUDgAIAwAKAAoKjxoUDgAIAwABNQAFFAcIGQAdAHgcAA==.',
Ly='Lygra:BAABNQAECn8aAAIHAAcKHhN3dgBIAQAHAAcKHhN3dgBIAQAAAA==.Lykana:BAAANQAECgQIBQAAAA==.Lyrasong:BAAANQADCgMIAwAAAA==.Lytharielis:BAAANQABCgQIBAAAAA==.',
Ma='Majellan:BAABNQAECn8+AAMMAAoK9xkSCQAxAgAMAAoK9xkSCQAxAgAgAAgKzw2NuACtAQAAAA==.Marsawn:BAABNQAECn89AAMKAAoKWRh/LwCqAgAKAAoKWRh/LwCqAgAcAAIKbh8/VQC4AAAAAA==.Mass:BAACNQAFFH8bAAIUAAcKiyUWAADzAgAUAAcKiyUWAADzAgA1AAQKfzEAAhQACgrOJg0AAKEDABQACgrOJg0AAKEDAAE1AAUUCAglABUAzBoA.',
Me='Meatbatticus:BAAANQAECgcIDAAAAA==.Meqi:BAABNQAECn8cAAMJAAcKVCHASQDUAQAJAAcKVCHASQDUAQAhAAEK7R29CgBVAAAAAA==.',
Mi='Mindlessness:BAABNQAECn8zAAIVAAoKDB2tKAA/AgAVAAoKDB2tKAA/AgAAAA==.Mineralelf:BAABNQAECn8+AAIHAAoKIAymRwDIAQAHAAoKIAymRwDIAQAAAA==.Minichaos:BAABNQAECn8rAAMNAAkKXhVUBABhAQANAAkKEBNUBABhAQAEAAYKsQ1oiADhAAAAAA==.Miriam:BAABNQAECn9CAAIJAAoKqAyXRgDfAQAJAAoKqAyXRgDfAQAAAA==.',
Mo='Mojosavage:BAABNQAECn8YAAIEAAcKWgPJ6AD4AAAEAAcKWgPJ6AD4AAAAAA==.Moonblade:BAAANQAECgIIAQAAAA==.',
My='Mylas:BAAANQADCgcIBwAAAA==.Mysticalfox:BAAANQADCgEIAQAAAA==.Mythrixx:BAAANQAECgcIBwAAAA==.',
Na='Nalfilas:BAABNQAECn8aAAIJAAYK+geVNgExAQAJAAYK+geVNgExAQAAAA==.',
Ne='Necromm:BAAANQABCgQIBgAAAA==.Nephaleos:BAABNQAECn8mAAIiAAkKnR+UCwDqAgAiAAkKnR+UCwDqAgAAAA==.Nessie:BAAANQAECgIIAgAAAA==.',
Ni='Nihlus:BAAANQAECgcIDgAAAA==.',
No='Nocturnous:BAAANQAECgQIBgAAAA==.',
Nu='Nurzul:BAAANQADCggICAABNQAECggICgAGAAAAAA==.',
Ny='Nyrvana:BAAANQAECgYICQAAAA==.',
['Nà']='Nàtureswrath:BAAANQAECgYIDwAAAA==.',
Og='Ogre:BAAANQADCggIGAAAAA==.',
Or='Orceo:BAABNQAECn8wAAIHAAoKwCIJDgDeAgAHAAoKwCIJDgDeAgAAAA==.Orkeo:BAAANQADCgcICwAAAA==.Orkreghar:BAABNQAECn8sAAIHAAoKexvxQACoAgAHAAoKexvxQACoAgAAAA==.',
Pa='Pallon:BAAANQAECgcJCwAAAA==.',
Pe='Perkybites:BAAANQABCggICQAAAA==.',
Ph='Phazma:BAAANQADCgUIBQAAAA==.',
Pi='Pindapin:BAAANQAECgMIBQAAAA==.',
Po='Pompompower:BAABNQAECn8zAAIDAAoKrQjkdwC6AQADAAoKrQjkdwC6AQAAAA==.Popashammy:BAAANQAECgIIAgAAAA==.Poplock:BAAANQADCgcIFgAAAA==.Popple:BAABNQAECn8eAAIjAAkK5w8xCQB9AQAjAAkK5w8xCQB9AQAAAA==.Potential:BAAANQAECgQIBAAAAA==.',
Pu='Puggsly:BAAANQAECgYIBwABNQAECgoKLgAEAMAVAA==.',
Qu='Quixotical:BAAANQADCgYIDAAAAA==.',
Ra='Radaghast:BAAANQAECgIIAgAAAA==.',
Re='Rectumraker:BAAANQAECgMIBwAAAA==.Reishirome:BAAANQADCggIFQAAAA==.Revenmar:BAAANQADCgQIBAAAAA==.',
Rh='Rhaelin:BAABNQAECn8rAAIbAAoKxhtIHgDyAgAbAAoKxhtIHgDyAgAAAA==.Rhaellia:BAAANQADCggICAAAAA==.Rhoke:BAABNQAECn8vAAIgAAgKIhBcrgDCAQAgAAgKIhBcrgDCAQAAAA==.',
Ro='Romeoz:BAAANQAECgcIBwABNQAFFAIIAgAGAAAAAA==.Rona:BAAANQAECgQIDAAAAA==.Roofhouse:BAAANQADCgMIAwAAAA==.Rosary:BAABNQAECn8fAAIKAAoKah8sJQDXAgAKAAoKah8sJQDXAgAAAA==.Rotiserychic:BAAANQAECgIIAgAAAA==.Roukia:BAAANQADCgEIAQAAAA==.',
Ru='Rusticfinger:BAABNQAECn8eAAIbAAoKPBQSUwAaAgAbAAoKPBQSUwAaAgAAAA==.',
Sa='Sacerdote:BAAANQAECgMIBAAAAA==.Sansa:BAABNQAECn8cAAIKAAcKXBbaPwC1AQAKAAcKXBbaPwC1AQAAAA==.Saruma:BAAANQADCggIDgABNQAECggICgAGAAAAAA==.',
Sc='Scalygrob:BAABNQAECn8XAAIkAAoKGhASFgDqAQAkAAoKGhASFgDqAQAAAA==.Scarytery:BAAANQAECgYIEAAAAA==.Scrügemcmonk:BAAANQAECgQIBAAAAA==.',
Sh='Shamaya:BAAANQABCgMIAwABNQADCgIIAgAGAAAAAA==.Shamfox:BAABNQAECn8YAAMDAAcKDw0PkQB6AQADAAcKDw0PkQB6AQAbAAEKNwJTKQElAAAAAA==.',
Si='Sidewinder:BAAANQAECgYIBgAAAA==.',
Sm='Smogcheck:BAACNQAFFH8IAAIiAAIKHRRODQCHAAAiAAIKHRRODQCHAAA1AAQKfy0AAyIACgrBFnITAHYCACIACgrBFnITAHYCACQAAwpQC+Q1AF8AAAAA.',
Sn='Snowsz:BAABNQAECn8WAAIJAAkKnBhmPQD/AQAJAAkKnBhmPQD/AQAAAA==.Snowws:BAABNQAECn8uAAIZAAoKtx5lEQAUAwAZAAoKtx5lEQAUAwAAAA==.Snowzz:BAAANQAECgQIBAAAAA==.',
So='Sonektot:BAAANQAECgEIAQAAAA==.Sortis:BAABNQAECn8iAAMJAAkKGRx/ZAC1AgAJAAkKGRx/ZAC1AgAaAAEK/wNQUAAnAAAAAA==.',
Sp='Spicebreff:BAAANQAECgEIAQABNQAECgcIHAAVAOsYAA==.',
St='Steck:BAABNQAECn8XAAIHAAcKHhEmtQCaAQAHAAcKHhEmtQCaAQAAAA==.Strigg:BAAANQADCgMIAwABNQADCggIEQAGAAAAAA==.Strigöi:BAAANQADCggIEQAAAA==.',
Su='Suprahunts:BAABNQAECn8dAAMHAAcKcCLRUgB4AgAHAAcKcCLRUgB4AgAIAAQKeA3tVQDOAAAAAA==.',
['Sà']='Sàlís:BAAANQADCgcIEAAAAA==.',
Ta='Talander:BAAANQADCgUIBQABNQAFFAIIAgAGAAAAAA==.Talas:BAABNQAECn87AAMHAAoKEBt3MQDYAgAHAAoKEBt3MQDYAgAIAAYK1w+JRQAtAQAAAA==.',
Te='Teaka:BAAANQAECgEIAQAAAA==.',
Th='Thaeker:BAAANQADCggIDgAAAA==.Thaelink:BAAANQAECgEIAQABNQAECgkJIAAJAE8XAA==.Thickthighs:BAAANQAECgYICQABNQAFFAIIAgAGAAAAAA==.Thorss:BAAANQAECgUIBwABNQAECggIGAAgAFQJAA==.Thrann:BAABNQAECn8yAAIYAAoKWyZgAACIAwAYAAoKWyZgAACIAwAAAA==.',
Ti='Tirium:BAABNQAECn8cAAIVAAcK6xjenADUAQAVAAcK6xjenADUAQAAAA==.',
To='Tolkien:BAABNQAECn8iAAIXAAcK6Q+jLwBoAQAXAAcK6Q+jLwBoAQAAAA==.',
Tu='Tubbytotem:BAAANQADCgYICgAAAA==.',
Un='Unduril:BAAANQADCgYIBgAAAA==.',
Ur='Ursae:BAAANQADCgIIAgAAAA==.',
Va='Vanargandr:BAAANQADCgYIBgAAAA==.Vartlek:BAAANQADCgYIBQAAAA==.',
Ve='Velarys:BAAANQABCgIIAgABNQAECgoKMgAQAA4gAA==.Velinlock:BAAANQABCgEIAQAAAA==.Velinthil:BAAANQADCgcIBwAAAA==.Verðandi:BAAANQADCgMJAwAAAA==.',
Vi='Vigilante:BAAANQAECgUIBQAAAA==.',
Vo='Volvox:BAAANQADCggICwAAAA==.',
Vy='Vyxenn:BAABNQAECn8+AAMbAAoKJBuaGQB1AgAbAAoKJBuaGQB1AgADAAIK1wbXFwFfAAAAAA==.',
Wa='Wanders:BAAANQAECgQIAQABNQAECgQIBAAGAAAAAA==.Washim:BAAANQADCggICQAAAA==.',
Wo='Wonkybits:BAAANQAECgQIAwAAAA==.',
Wu='Wurm:BAAANQADCgQIBAABNQAECggICgAGAAAAAA==.',
Ye='Yejena:BAAANQAECgQIBQAAAA==.',
Ym='Ymir:BAAANQADCgQIBAAAAA==.',
Za='Zaleras:BAAANQADCggIDgAAAA==.',
Ze='Zerkium:BAAANQAECgcIEQAAAA==.',
Zi='Zillaamiri:BAAANQAECgcIEAAAAA==.',
Zu='Zugzugdaboo:BAAANQADCggJFgAAAA==.',
Zy='Zyrinx:BAAANQABCgIIAgAAAA==.Zywol:BAABNQAECn8+AAMOAAoKUBh/EgAiAgAOAAoKUBh/EgAiAgARAAMKDg0mWQCjAAAAAA==.',
['Ër']='Ëresta:BAAANQADCgYIEwABNQAECgkJMQAHAB4eAA==.',
['Ðe']='Ðespair:BAABNQAECn8gAAMKAAoK9h1bTABAAgAKAAcKgRxbTABAAgAcAAgKNRqhEwCSAQAAAA==.',
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
