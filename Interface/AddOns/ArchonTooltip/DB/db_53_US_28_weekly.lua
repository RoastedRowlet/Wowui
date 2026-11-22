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

local lookup = {'Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Paladin-Holy','Warlock-Demonology','Hunter-BeastMastery','DemonHunter-Devourer','Unknown-Unknown','Hunter-Marksmanship','Mage-Arcane','Priest-Holy','Paladin-Protection','DeathKnight-Blood','Paladin-Retribution','Warlock-Destruction','Druid-Balance','Monk-Windwalker','Priest-Discipline','Druid-Restoration','Druid-Feral','Warrior-Protection','Warrior-Arms','DemonHunter-Vengeance','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Havoc','Mage-Frost','Shaman-Restoration','Priest-Shadow','Monk-Mistweaver','Monk-Brewmaster','Warlock-Affliction','Mage-Fire','Evoker-Preservation','Warrior-Fury','Evoker-Devastation','Shaman-Enhancement',}
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abednego:BAABNQAECn8zAAMBAAkKrxdVDgCSAgABAAkKZRdVDgCSAgACAAQKFQ5kRQB3AAAAAA==.',
Ac='Acidrain:BAABNQAECn83AAIDAAoKbRnbLwAaAgADAAoKbRnbLwAaAgAAAA==.Acmiax:BAABNQAECn8eAAIEAAgKFRL1VwC2AQAEAAgKFRL1VwC2AQABNQAECgoKNQAFAMAVAA==.',
Ad='Adar:BAAANQAECgUIDwABNQAECgoKSQAGADYkAA==.Adonsinn:BAABNQAECn8cAAIHAAgKMCGPGQCOAgAHAAgKMCGPGQCOAgAAAA==.',
Ae='Aegos:BAAANQAECgQIBgAAAA==.Aep:BAAANQAECgMJBAABNQAECgUIDQAIAAAAAA==.',
Ah='Ahu:BAABNQAECn81AAMGAAkK3hbUSACSAgAGAAkK3hbUSACSAgAJAAEKKgZMlQArAAAAAA==.',
Ai='Aiden:BAAANQAECggIEwAAAA==.',
Al='Alakazam:BAAANQADCgUIBgAAAA==.Alanath:BAAANQADCgQIBAAAAA==.Alandramun:BAAANQAECgIIAgAAAA==.Aleroderp:BAABNQAECn8lAAIJAAoK0wa1HwB0AQAJAAoK0wa1HwB0AQAAAA==.Allaria:BAAANQAECgIIBQAAAA==.Alucard:BAAANQAECgYIDAAAAA==.',
Am='Amaging:BAABNQAECn8lAAIKAAkKqgqmxAD7AQAKAAkKqgqmxAD7AQAAAA==.Ambassador:BAAANQAECgUIBQAAAA==.Amoondai:BAACNQAFFH8OAAILAAMKrh20GgAfAQALAAMKrh20GgAfAQA1AAQKf1wAAgsACgq3I+sNAFUDAAsACgq3I+sNAFUDAAAA.',
An='Analytics:BAABNQAECn8cAAIMAAgKBxHhJgA5AQAMAAgKBxHhJgA5AQAAAA==.Angusdei:BAAANQADCgIIAgAAAA==.Anyr:BAAANQADCgMIAwAAAA==.',
Ap='Apochryphal:BAABNQAECn85AAINAAoKECEaDgC5AgANAAoKECEaDgC5AgAAAA==.',
Ar='Araon:BAAANQAECgMIAwAAAA==.Araylva:BAAANQADCggIDwAAAA==.Arienei:BAAANQABCgQIBQAAAA==.Arrtemiss:BAAANQADCgMIAwABNQAECgUIDgAIAAAAAA==.',
As='Ashogg:BAAANQAECgYIEQAAAA==.',
Au='Aurén:BAAANQADCggIGQAAAA==.',
Az='Azuree:BAAANQAECgIIBgAAAA==.',
Ba='Bacstabath:BAABNQAECn9DAAMCAAoK5iIODwAJAwACAAgKKCMODwAJAwABAAoKYR7TDwB/AgAAAA==.Baelgrimm:BAABNQAECn8mAAMOAAgKmBCbrwBxAQAOAAcKmBCbrwBxAQAMAAEKAAAEfgAAAAAAAA==.',
Be='Becca:BAABNQAECn9BAAIMAAoKUR7oCwB0AgAMAAoKUR7oCwB0AgAAAA==.Bequin:BAAANQADCgUIBQAAAA==.',
Bi='Bigdaddys:BAAANQAECgMIAgAAAA==.Bigduh:BAAANQADCgQIBAAAAA==.Birblock:BAABNQAECn9QAAMFAAoKyyMyCwARAwAFAAoKyyMyCwARAwAPAAQK8A9YNgDoAAABNQAFFAgIGAAQAPwRAA==.',
Bl='Blaizee:BAAANQAECgEIAQAAAA==.Blasphemar:BAAANQADCgYJBgAAAA==.Bloodios:BAABNQAECn9UAAINAAoKiRxbFABrAgANAAoKiRxbFABrAgAAAA==.Bluechewgold:BAABNQAECn8mAAINAAoKMCHJCgBeAwANAAoKMCHJCgBeAwAAAA==.',
Bo='Bobbardment:BAAANQADCgQIBAABNQAECgQIBAAIAAAAAA==.Bobin:BAABNQAECn8hAAIRAAoKKRBKKQDUAQARAAoKKRBKKQDUAQAAAA==.Bombadil:BAABNQAECn8yAAISAAoKnhC3BADoAQASAAoKnhC3BADoAQAAAA==.Boshek:BAAANQABCgUJCQAAAA==.',
Br='Bribage:BAACNQAFFH8YAAMQAAgK/BHKDwBtAQAQAAgK/BHKDwBtAQATAAEKowkQFQBKAAA1AAQKfzEAAxAACgr3IbUcAOMCABAACgr3IbUcAOMCABQAAgrWGek4AFkAAAAA.Brightest:BAAANQAECgEIAQAAAA==.Brolaf:BAAANQADCgIIAgABNQAFFAcIFgAEAIIgAA==.Brolavski:BAABNQAFFH8WAAIEAAcKgiAvBgANAgAEAAcKgiAvBgANAgAAAA==.',
Bu='Budderwar:BAABNQAECn83AAMVAAkKZSYJAQDKAwAVAAkKZSYJAQDKAwAWAAQK9RGs9QDzAAAAAA==.Buster:BAABNQAECn8dAAMXAAoKDwrLFQBPAQAXAAoKDwrLFQBPAQAHAAQKhQMZYQBpAAAAAA==.Buzkills:BAAANQABCgIIAwAAAA==.',
['Bà']='Bàdmofos:BAAANQADCgcIBwAAAA==.',
Ce='Celerydk:BAABNQAECn9KAAIYAAoKrR7UFQCeAgAYAAoKrR7UFQCeAgAAAA==.',
Ch='Chaosgaara:BAAANQADCgEIAQAAAA==.Chikñ:BAAANQAECgQIAQAAAA==.',
Co='Colossus:BAABNQAECn8hAAMZAAoKkB+QJQCoAgAZAAoKkB+QJQCoAgANAAMKUgtDqQB+AAAAAA==.Connor:BAAANQAECgIIBAAAAA==.Correin:BAABNQAECn9FAAIaAAoKuRSvIgD1AQAaAAoKuRSvIgD1AQAAAA==.',
Cr='Craszhin:BAABNQAECn83AAIQAAoKcQ7PKgCqAQAQAAoKcQ7PKgCqAQAAAA==.Crime:BAAANQAECgMIAwAAAA==.',
['Cè']='Cèl:BAABNQAECn9LAAMbAAoKwxGXCwDlAQAbAAoKwxGXCwDlAQAKAAYKVAOqIgF7AAAAAA==.',
Da='Daddio:BAEANQAECgQIBwAAAA==.Dadeb:BAAANQAECgcICwABNQAECgoKNQAFAMAVAA==.Daenarea:BAAANQADCgYIBgAAAA==.Dangpup:BAABNQAECn9EAAIJAAoKrxeOEgAZAgAJAAoKrxeOEgAZAgAAAA==.Danru:BAAANQADCgQICwAAAA==.Darkdelight:BAABNQAECn87AAIGAAoKQRbOUQB7AgAGAAoKQRbOUQB7AgAAAA==.Dazynth:BAAANQAECgIIAgAAAA==.',
De='Deathlylazy:BAAANQAECgcICgAAAA==.Deets:BAABNQAECn8xAAIGAAoKxCDTJgCkAgAGAAoKxCDTJgCkAgAAAA==.Demona:BAABNQAECn84AAMPAAoKjw3GBgBvAQAPAAoKjw3GBgBvAQAFAAEKEwE7WgEcAAAAAA==.Derfhurnturr:BAAANQAECgUIBgAAAA==.Descalabrada:BAAANQAECggIDQAAAA==.',
Di='Distol:BAAANQADCgIIAgAAAA==.',
Dm='Dmt:BAAANQAECgIIAgAAAA==.',
Dr='Draeamorjan:BAAANQADCgEIAQAAAA==.Driver:BAEANQAECggIBwAAAA==.Drpeppers:BAABNQAECn8wAAITAAoKvRJ9IgDjAQATAAoKvRJ9IgDjAQAAAA==.',
['Dé']='Déathsavage:BAAANQADCggIHwAAAA==.',
Ea='Eatmorchikin:BAAANQAECgEIAQAAAA==.',
Ec='Eclair:BAABNQAECn85AAIcAAoKviH/DgBFAwAcAAoKviH/DgBFAwAAAA==.',
El='Elfkr:BAABNQAECn8eAAMcAAgKJiEDIwDbAgAcAAgKJiEDIwDbAgADAAIK+hif+wCbAAAAAA==.Elhayn:BAABNQAECn8yAAIdAAoKUyPbBgAAAwAdAAoKUyPbBgAAAwAAAA==.Elmos:BAABNQAECn87AAIRAAoKviHtBwBQAwARAAoKviHtBwBQAwAAAA==.',
Er='Erethidian:BAAANQADCgQIBAAAAA==.Eris:BAAANQAECgQIDQAAAA==.',
Eu='Eucalyptus:BAAANQAECgUIDgAAAA==.',
Ev='Evilmonkeydr:BAAANQAECgQIBAABNQAECgoKHwAKAD0eAA==.Evilmonkeymg:BAABNQAECn8fAAIKAAoKPR5wWwDJAgAKAAoKPR5wWwDJAgAAAA==.Evilmonkeysh:BAAANQADCgUIBQABNQAECgoKHwAKAD0eAA==.',
Ez='Ezaylia:BAABNQAECn8xAAIaAAoKMA/6LgCeAQAaAAoKMA/6LgCeAQAAAA==.',
Fa='Fatehunter:BAABNQAECn8cAAIGAAcKuhLAmADWAQAGAAcKuhLAmADWAQAAAA==.',
Fe='Feim:BAAANQADCggICAAAAA==.Fergis:BAABNQAECn82AAMbAAoK6BxmBgBiAgAbAAkK6BxmBgBiAgAKAAYKGxSc+wCWAQAAAA==.',
Fi='Firefox:BAABNQAECn8dAAINAAkKORlONgAyAgANAAkKORlONgAyAgAAAA==.',
Fl='Flypig:BAAANQADCggIBwAAAA==.',
Fr='Frostymonk:BAABNQAECn8iAAMeAAkKZguUHQAzAQAeAAkKZguUHQAzAQAfAAIKlATKJABFAAAAAA==.Frostypally:BAAANQAECggIDwAAAA==.',
Fu='Fuel:BAAANQADCgYIBgABNQAECggIGgAGAI8OAA==.Furrybear:BAAANQAECgEIAgAAAA==.',
Ga='Gala:BAABNQAECn8mAAIKAAoK/RbiSAAzAgAKAAoK/RbiSAAzAgAAAA==.',
Ge='Genorian:BAACNQAFFH8GAAIQAAYK7AQFGgCcAAAQAAYK7AQFGgCcAAA1AAQKfzAAAhAACgrxF6AZAD8CABAACgrxF6AZAD8CAAAA.',
Gh='Ghidorahh:BAAANQAECggICAAAAA==.',
Gi='Gigem:BAABNQAECn8aAAIGAAcKVRysiwDzAQAGAAcKVRysiwDzAQAAAA==.Girlshoon:BAAANQAECgUICAAAAA==.Githan:BAAANQAECgYIDAABNQAECgkJJwATAK0bAA==.',
Gl='Glarheals:BAAANQADCgEIAQABNQAECgoKOQABAFYRAA==.Glarious:BAABNQAECn85AAIBAAoKVhH3FAA/AgABAAoKVhH3FAA/AgAAAA==.',
Go='Gobbozap:BAAANQADCggIDgABNQAECgoKOwASAA4gAA==.',
Gr='Gredan:BAABNQAECn8yAAINAAkKpRa3JgDHAQANAAkKpRa3JgDHAQAAAA==.Greymoor:BAAANQABCgQIBAAAAA==.Gruhm:BAAANQADCgUIBQAAAA==.Grôg:BAAANQAECggIEgAAAA==.',
Gu='Guldaniel:BAABNQAECn81AAQFAAoKwBX/PQCZAgAFAAoKwBX/PQCZAgAPAAEKbBdyMQBFAAAgAAEK+wFzMwAYAAAAAA==.Guthuzad:BAAANQADCgUIBgAAAA==.Guthx:BAABNQAECn8fAAMQAAoKTRgYRADjAQAQAAgK6BUYRADjAQATAAUKIBBjVgCfAAAAAA==.',
Ha='Halfaman:BAAANQAECgQIBgABNQAFFAIIAgAIAAAAAA==.Hantzel:BAAANQADCgUIBQAAAA==.',
He='Healyeah:BAAANQAECgEIAQAAAA==.Hellen:BAABNQAECn8cAAIFAAoKnSDuLADSAgAFAAoKnSDuLADSAgAAAA==.',
Hw='Hwat:BAAANQAECgYIDwAAAA==.',
Ic='Ictus:BAABNQAECn8ZAAIKAAoK+RzjcACcAgAKAAoK+RzjcACcAgAAAA==.',
In='Incredabull:BAAANQAECgIIAgAAAA==.',
Is='Isabelle:BAACNQAFFH8MAAIJAAUKHQebFwCYAAAJAAUKHQebFwCYAAA1AAQKf0YAAgkACQrFGNgSABUCAAkACQrFGNgSABUCAAAA.Isharded:BAABNQAECn9JAAMgAAoKaBPgBgD+AQAgAAoKaBPgBgD+AQAFAAYKLgYeqgABAQAAAA==.Istayblunted:BAAANQAECgUIDAAAAA==.',
Ja='Jacqualyn:BAAANQAFFAIIAgAAAA==.Jaylon:BAAANQADCgUIBQAAAA==.',
Ji='Jiayerah:BAAANQADCggIDwABNQAECgkJMgALACQXAA==.Jinkuzo:BAABNQAECn81AAIfAAoKlhyxBABsAgAfAAoKlhyxBABsAgAAAA==.Jinmu:BAABNQAECn85AAMBAAoKQBItGQAQAgABAAoKQBItGQAQAgACAAcKJwjeVgBfAQAAAA==.',
Ju='Juanaloopa:BAAANQAECgcIDAAAAA==.Juggie:BAABNQAECn8lAAMLAAkKxQSCnQA9AQALAAkKxQSCnQA9AQAdAAYKgASwVAC7AAAAAA==.Julienned:BAABNQAECn9NAAICAAoKkhR9DAAEAgACAAoKkhR9DAAEAgAAAA==.',
['Jè']='Jèsse:BAAANQADCgcJBwAAAA==.',
Ka='Kainen:BAABNQAECn85AAQOAAoKaRmnZABtAgAOAAoKaRmnZABtAgAEAAQKGQOP8QCdAAAMAAQK4QNSWgBzAAAAAA==.',
Ke='Kesoyi:BAAANQADCgMIAwABNQAFFAIIAgAIAAAAAA==.',
Ki='Kinkybunny:BAAANQADCgYJBgAAAA==.',
Kl='Klodar:BAABNQAECn8yAAIdAAgKmhXjHQChAQAdAAgKmhXjHQChAQAAAA==.Klum:BAAANQABCgQIBgAAAA==.',
Ko='Korinna:BAACNQAFFH8FAAIOAAIK9APEKgBqAAAOAAIK9APEKgBqAAA1AAQKfzcAAw4ACQoIDi2oAH4BAA4ACQoIDi2oAH4BAAwAAgrVClVnAC8AAAAA.',
Kr='Krazee:BAAANQABCgMIBQAAAA==.Krotallas:BAAANQAECgQICAAAAA==.',
La='Lafey:BAAANQADCgIJAgAAAA==.Lamedout:BAAANQADCgcIBwABNQAECggIGgAGAI8OAA==.Lanfear:BAAANQADCgQIBAAAAA==.Laurenya:BAAANQADCgMIAwABNQAECgUIDgAIAAAAAA==.',
Le='Leida:BAAANQADCgcICwAAAA==.Leinen:BAAANQAECgUIBAAAAA==.',
Lo='Logi:BAAANQAECgUIDQAAAA==.Lostrage:BAAANQADCgcICgAAAA==.',
Lu='Lumiyer:BAABNQAECn8rAAILAAoKbB1HEgBHAwALAAoKbB1HEgBHAwABNQAFFAcIGgAeAHgcAA==.',
Ly='Lygra:BAABNQAECn8nAAIGAAkKvBAihQCvAQAGAAkKvBAihQCvAQAAAA==.Lykana:BAAANQAECgQIBQAAAA==.Lyrasong:BAAANQADCgMIAwAAAA==.Lytharielis:BAAANQABCgQIBAAAAA==.',
Ma='Majellan:BAABNQAECn9UAAMMAAoKuhyECwB8AgAMAAoKuhyECwB8AgAOAAgKzw2NuACtAQAAAA==.Marsawn:BAABNQAECn9HAAMLAAoKkxh/LwCqAgALAAoKkxh/LwCqAgAdAAgKGBk8FwDxAQAAAA==.Mass:BAACNQAFFH8dAAIVAAgKzCUWAADzAgAVAAgKzCUWAADzAgA1AAQKfzkAAhUACgrYJisAAJoDABUACgrYJisAAJoDAAAA.',
Me='Meatbatticus:BAAANQAECgcIDAAAAA==.Meqi:BAABNQAECn8yAAMKAAkKdSCBMwB0AgAKAAkKdSCBMwB0AgAhAAMKuh2eBQD+AAAAAA==.',
Mi='Mindlessness:BAABNQAECn9DAAIWAAoKcR/1JgCkAgAWAAoKcR/1JgCkAgAAAA==.Mineralelf:BAABNQAECn9UAAIGAAoKowy7awDrAQAGAAoKowy7awDrAQAAAA==.Minichaos:BAABNQAECn9BAAMPAAoKYhbIBQCTAQAFAAkKqg4fWgDGAQAPAAkK7hTIBQCTAQAAAA==.Miriam:BAABNQAECn9ZAAIKAAoKahLrUAAeAgAKAAoKahLrUAAeAgAAAA==.',
Mo='Mojosavage:BAABNQAECn8YAAIFAAcKWgPJ6AD4AAAFAAcKWgPJ6AD4AAAAAA==.Moonblade:BAAANQAECggICwAAAA==.',
My='Mylas:BAAANQADCgcIBwAAAA==.Mysticalfox:BAAANQADCgEIAQAAAA==.Mythrixx:BAAANQAECgcIDQAAAA==.',
Na='Nalfilas:BAABNQAECn8aAAIKAAYK+geVNgExAQAKAAYK+geVNgExAQAAAA==.',
Ne='Necromm:BAAANQABCgQIBgAAAA==.Nephaleos:BAABNQAECn8mAAIiAAkKnR+UCwDqAgAiAAkKnR+UCwDqAgAAAA==.Nessie:BAAANQAECgIIAgAAAA==.',
Ni='Nihlus:BAABNQAECn8ZAAIOAAoKTQmg1wArAQAOAAoKTQmg1wArAQAAAA==.',
No='Nocturnous:BAAANQAECgQIDgAAAA==.',
Nu='Nurzul:BAAANQADCggICAABNQAECggIEgAIAAAAAA==.',
Ny='Nyrvana:BAAANQAECgYICQAAAA==.',
['Nà']='Nàtureswrath:BAABNQAECn8aAAIGAAgKjw6BogBuAQAGAAgKjw6BogBuAQAAAA==.',
Og='Ogre:BAAANQADCggIGAAAAA==.',
Or='Orceo:BAABNQAECn9JAAIGAAoKNiQCCQBDAwAGAAoKNiQCCQBDAwAAAA==.Orkeo:BAAANQADCgcIDAABNQAECgoKSQAGADYkAA==.Orkreghar:BAABNQAECn9EAAIGAAoKjSDtKQCZAgAGAAoKjSDtKQCZAgAAAA==.',
Pa='Pallon:BAAANQAECgcJCwAAAA==.',
Pe='Perkybites:BAAANQABCggICQAAAA==.',
Ph='Phazma:BAAANQADCgUIBQAAAA==.',
Pi='Pindapin:BAAANQAECgMIBQAAAA==.Pippitron:BAAANQABCgMIAwAAAA==.',
Po='Poco:BAAANQADCgMIAwAAAA==.Pompompower:BAABNQAECn80AAIDAAoKAAnkdwC6AQADAAoKAAnkdwC6AQAAAA==.Popashammy:BAAANQAECgIIAgAAAA==.Poplock:BAAANQADCgcIFgAAAA==.Popple:BAABNQAECn8lAAIjAAoKMhABDQCzAQAjAAoKMhABDQCzAQAAAA==.Potential:BAAANQAECgQIBAAAAA==.',
Pu='Puggsly:BAAANQAECgYIEgABNQAECgoKNQAFAMAVAA==.',
Py='Pyrocaster:BAAANQAECgYIBQAAAA==.',
Qa='Qaccy:BAAANQABCgQIBAAAAA==.',
Qu='Quixotical:BAAANQADCgYIDAAAAA==.',
Ra='Radaghast:BAAANQAECgIIAgAAAA==.',
Re='Rectumraker:BAAANQAECgUICgAAAA==.Reishirome:BAAANQADCggIFQAAAA==.Revenmar:BAAANQADCgQIBAAAAA==.',
Rh='Rhaelin:BAABNQAECn84AAIcAAoKJh5IHgDyAgAcAAoKJh5IHgDyAgAAAA==.Rhaellia:BAAANQADCggICAAAAA==.Rhoke:BAABNQAECn8vAAIOAAgKIhBcrgDCAQAOAAgKIhBcrgDCAQAAAA==.',
Ro='Rockyy:BAAANQAECgQIBAAAAA==.Romeoz:BAAANQAECgcIBwABNQAFFAIIAgAIAAAAAA==.Rona:BAAANQAECgQIDAAAAA==.Roofhouse:BAAANQAECgEIAQAAAA==.Rosary:BAABNQAECn8gAAILAAoKWyAsJQDXAgALAAoKWyAsJQDXAgAAAA==.Rotiserychic:BAAANQAECggIDAAAAA==.Roukia:BAAANQADCgEIAQAAAA==.',
Ru='Rusticfinger:BAABNQAECn8fAAIcAAoKQBQSUwAaAgAcAAoKQBQSUwAaAgAAAA==.',
Sa='Sacerdote:BAAANQAECgMIBAAAAA==.Sansa:BAABNQAECn8yAAILAAkKJBfjQAA2AgALAAkKJBfjQAA2AgAAAA==.Saruma:BAAANQADCggIDgABNQAECggIEgAIAAAAAA==.',
Sc='Scalygrob:BAABNQAECn8YAAIkAAoKdRASFgDqAQAkAAoKdRASFgDqAQAAAA==.Scarytery:BAAANQAECgYIEAAAAA==.Scrügemcmonk:BAAANQAECgQIBAAAAA==.',
Sh='Shamaya:BAAANQABCgMIAwABNQADCgIIAgAIAAAAAA==.Shamfox:BAABNQAECn8YAAMDAAcKDw0PkQB6AQADAAcKDw0PkQB6AQAcAAEKNwJTKQElAAAAAA==.',
Si='Sidewinder:BAAANQAECgYICQAAAA==.',
Sm='Smogcheck:BAACNQAFFH8MAAMiAAMKLBI+FACCAAAiAAIKHRQ+FACCAAAkAAIKsgSPBgBoAAA1AAQKfzUAAyIACgraF3ITAHYCACIACgraF3ITAHYCACQABQqaD1ccAIQAAAAA.',
Sn='Snowsz:BAABNQAECn8WAAIKAAkKnBisaADiAQAKAAkKnBisaADiAQAAAA==.Snowws:BAABNQAECn8uAAIaAAoKtx5lEQAUAwAaAAoKtx5lEQAUAwAAAA==.Snowzz:BAABNQAECn8ZAAIBAAoKTRbhLQBGAgABAAoKTRbhLQBGAgAAAA==.',
So='Sonektot:BAAANQAECgEIAQAAAA==.Sortis:BAABNQAECn8iAAMKAAkKGRx/ZAC1AgAKAAkKGRx/ZAC1AgAbAAEK/wNQUAAnAAAAAA==.',
Sp='Spicebreff:BAAANQAECgEIAQABNQAECggIHQAWAKEXAA==.',
St='Steck:BAABNQAECn8jAAIGAAkKrQ7zhwCoAQAGAAkKrQ7zhwCoAQAAAA==.Strigg:BAAANQADCgMIAwAAAA==.',
Su='Suprahunts:BAABNQAECn8dAAMGAAcKcCLRUgB4AgAGAAcKcCLRUgB4AgAJAAQKeA3tVQDOAAAAAA==.',
['Sà']='Sàlís:BAAANQADCgcIEAAAAA==.',
Ta='Talander:BAAANQADCgUIBQABNQAFFAIIAgAIAAAAAA==.Talas:BAABNQAECn8+AAMGAAoKoht3MQDYAgAGAAoKoht3MQDYAgAJAAYK1w+JRQAtAQAAAA==.',
Te='Teaka:BAAANQAECgEIAQAAAA==.Temberle:BAAANQAECgQIBAABNQAECggIFgAQAPMMAA==.',
Th='Thaeker:BAAANQADCggIDgAAAA==.Thaelink:BAAANQAECgEIAQABNQAECgkJIAAKAE8XAA==.Thickthighs:BAAANQAECgYICgABNQAFFAIIAgAIAAAAAA==.Thorss:BAAANQAECgUIDAABNQAECggIIAAOACUKAA==.Thrann:BAABNQAECn87AAIZAAoKkyYvAQB8AwAZAAoKkyYvAQB8AwAAAA==.',
Ti='Tirium:BAABNQAECn8dAAIWAAgKoRfenADUAQAWAAgKoRfenADUAQAAAA==.',
To='Tolkien:BAABNQAECn8qAAIYAAkKVhLgLQD3AQAYAAkKVhLgLQD3AQAAAA==.',
Tu='Tubbytotem:BAAANQADCgYICgAAAA==.',
Un='Unduril:BAAANQADCgYIBgAAAA==.',
Ur='Ursae:BAAANQADCgIIAgAAAA==.',
Va='Vanargandr:BAAANQADCgYIBgAAAA==.Vartlek:BAAANQADCgYIBQAAAA==.',
Ve='Velarys:BAAANQABCgIIAgABNQAECgoKOwASAA4gAA==.Velinlock:BAAANQABCgEIAQAAAA==.Velinthil:BAAANQADCgcIBwAAAA==.Verðandi:BAAANQADCgMJAwAAAA==.',
Vi='Vigilante:BAAANQAECgUIBQAAAA==.Vitrois:BAAANQADCgEIAQABNQAECgoKLAAZAIsdAA==.',
Vo='Voidraven:BAAANQAECgQICgAAAA==.Volvox:BAAANQADCggICwAAAA==.',
Vy='Vyxenn:BAABNQAECn9UAAMcAAoKTRx9HgDHAgAcAAoKTRx9HgDHAgADAAIK1wbXFwFfAAAAAA==.',
Wa='Wanders:BAAANQAECgQIAQABNQAECgQIBAAIAAAAAA==.Washim:BAAANQADCggICQAAAA==.',
Wo='Wonkybits:BAAANQAECgQIBgAAAA==.',
Wu='Wurm:BAAANQADCgQIBAABNQAECggIEgAIAAAAAA==.',
Ye='Yejena:BAABNQAECn8hAAIOAAoKvAtKoQCLAQAOAAoKvAtKoQCLAQAAAA==.',
Ym='Ymir:BAAANQADCgQIBAAAAA==.',
Za='Zaleras:BAAANQADCggIDgAAAA==.',
Ze='Zerkium:BAAANQAECgcIEQAAAA==.',
Zi='Zillaamiri:BAABNQAECn8YAAIlAAkKeQJtJADyAAAlAAkKeQJtJADyAAAAAA==.',
Zu='Zugzugdaboo:BAAANQADCggIFgAAAA==.',
Zy='Zyreal:BAAANQADCgIIAgAAAA==.Zyrinx:BAAANQABCgIIAgAAAA==.Zywol:BAABNQAECn9UAAMQAAoKvhiiIgC6AgAQAAoKvhiiIgC6AgATAAkK0hCmIgDiAQAAAA==.',
['Ër']='Ëresta:BAAANQADCgYIEwABNQAECgoKNgAGAAkdAA==.',
['Ðe']='Ðespair:BAABNQAECn8gAAMLAAoK9h1bTABAAgALAAcKgRxbTABAAgAdAAgKNRq9IACEAQAAAA==.',
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
