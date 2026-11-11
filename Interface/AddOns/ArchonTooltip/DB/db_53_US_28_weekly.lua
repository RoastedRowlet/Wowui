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

local lookup = {'Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Paladin-Holy','Warlock-Demonology','DemonHunter-Devourer','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Arcane','Priest-Holy','Paladin-Protection','DeathKnight-Blood','Paladin-Retribution','Warlock-Destruction','Druid-Balance','Monk-Windwalker','Priest-Discipline','Druid-Restoration','Druid-Feral','Warrior-Protection','Warrior-Arms','DemonHunter-Vengeance','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Havoc','Mage-Frost','Shaman-Restoration','Priest-Shadow','Monk-Mistweaver','Monk-Brewmaster','Warlock-Affliction','Mage-Fire','Evoker-Preservation','Warrior-Fury','Evoker-Devastation','Shaman-Enhancement',}
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abednego:BAABNQAECn8zAAMBAAkKrxdVDgCSAgABAAkKZRdVDgCSAgACAAQKFQ6PQwB4AAAAAA==.',
Ac='Acidrain:BAABNQAECn83AAIDAAoKbRngKgAfAgADAAoKbRngKgAfAgAAAA==.Acmiax:BAABNQAECn8eAAIEAAgKFRKQUQC7AQAEAAgKFRKQUQC7AQABNQAECgoKNQAFAMAVAA==.',
Ad='Adar:BAAANQAECgUIDwAAAA==.Adonsinn:BAABNQAECn8cAAIGAAgKMCGPGQCOAgAGAAgKMCGPGQCOAgAAAA==.',
Ae='Aegos:BAAANQAECgQIBgAAAA==.Aep:BAAANQAECgMJBAABNQAECgUIDQAHAAAAAA==.',
Ah='Ahu:BAABNQAECn81AAMIAAkK3hbUSACSAgAIAAkK3hbUSACSAgAJAAEKKgZMlQArAAAAAA==.',
Ai='Aiden:BAAANQAECgcIEgAAAA==.',
Al='Alakazam:BAAANQADCgUIBgAAAA==.Alanath:BAAANQADCgQIBAAAAA==.Alandramun:BAAANQAECgIIAgAAAA==.Aleroderp:BAABNQAECn8lAAIJAAoK0waFHQB2AQAJAAoK0waFHQB2AQAAAA==.Allaria:BAAANQAECgIIBQAAAA==.Alucard:BAAANQAECgcICQAAAA==.',
Am='Amaging:BAABNQAECn8lAAIKAAkKqgqmxAD7AQAKAAkKqgqmxAD7AQAAAA==.Ambassador:BAAANQAECgUIBQAAAA==.Amoondai:BAACNQAFFH8MAAILAAMKrh0NGAAhAQALAAMKrh0NGAAhAQA1AAQKf1cAAgsACgq3I+sNAFUDAAsACgq3I+sNAFUDAAAA.',
An='Analytics:BAABNQAECn8cAAIMAAgKBxGuIwA7AQAMAAgKBxGuIwA7AQAAAA==.Angusdei:BAAANQADCgIIAgAAAA==.Anyr:BAAANQADCgMIAwAAAA==.',
Ap='Apochryphal:BAABNQAECn85AAINAAoKECH2DAC/AgANAAoKECH2DAC/AgAAAA==.',
Ar='Araon:BAAANQAECgMIAwAAAA==.Araylva:BAAANQADCggIDwAAAA==.Arienei:BAAANQABCgQIBQAAAA==.Arrtemiss:BAAANQADCgMIAwABNQAECgUIDgAHAAAAAA==.',
As='Ashogg:BAAANQAECgYIEQAAAA==.',
Au='Aurén:BAAANQADCggIGQAAAA==.',
Az='Azuree:BAAANQAECgMIBQAAAA==.',
Ba='Bacstabath:BAABNQAECn9DAAMCAAoK5iIODwAJAwACAAgKKCMODwAJAwABAAoKYR7TDwB/AgAAAA==.Baelgrimm:BAABNQAECn8gAAMOAAgKmBBMoQB1AQAOAAcKmBBMoQB1AQAMAAEKAACTdwAAAAAAAA==.',
Be='Becca:BAABNQAECn89AAIMAAoKUR6nCgB6AgAMAAoKUR6nCgB6AgAAAA==.Bequin:BAAANQADCgUIBQAAAA==.',
Bi='Bigdaddys:BAAANQAECgMIAgAAAA==.Bigduh:BAAANQADCgQIBAAAAA==.Birblock:BAABNQAECn9KAAMFAAoKyyO6CQAUAwAFAAoKyyO6CQAUAwAPAAQK8A9YNgDoAAABNQAFFAcIFwAQANYSAA==.',
Bl='Blaizee:BAAANQAECgEIAQAAAA==.Blasphemar:BAAANQADCgYJBgAAAA==.Bloodios:BAABNQAECn9OAAINAAoKdhyMFABdAgANAAoKdhyMFABdAgAAAA==.Bluechewgold:BAABNQAECn8mAAINAAoKMCHJCgBeAwANAAoKMCHJCgBeAwAAAA==.',
Bo='Bobbardment:BAAANQADCgQIBAABNQAECgQIBAAHAAAAAA==.Bobin:BAABNQAECn8hAAIRAAoKKRBKKQDUAQARAAoKKRBKKQDUAQAAAA==.Bombadil:BAABNQAECn8yAAISAAoKnhAtBAD4AQASAAoKnhAtBAD4AQAAAA==.Boshek:BAAANQABCgUJCQAAAA==.',
Br='Bribage:BAACNQAFFH8XAAMQAAcK1hLKDwBtAQAQAAcK1hLKDwBtAQATAAEKowkQFQBKAAA1AAQKfzEAAxAACgr3IbUcAOMCABAACgr3IbUcAOMCABQAAgrWGek4AFkAAAAA.Brightest:BAAANQAECgIIAQAAAA==.Brolaf:BAAANQADCgIIAgABNQAFFAYIFQAEAB0kAA==.Brolavski:BAABNQAFFH8VAAIEAAYKHSQvBgANAgAEAAYKHSQvBgANAgAAAA==.',
Bu='Budderwar:BAABNQAECn83AAMVAAkKZSYJAQDKAwAVAAkKZSYJAQDKAwAWAAQK9RGs9QDzAAAAAA==.Buster:BAABNQAECn8dAAMXAAoKDwrLFQBPAQAXAAoKDwrLFQBPAQAGAAQKhQMZYQBpAAAAAA==.Buzkills:BAAANQABCgIIAwAAAA==.',
['Bà']='Bàdmofos:BAAANQADCgcIBwAAAA==.',
Ce='Celerydk:BAABNQAECn9JAAIYAAoKmR43FACeAgAYAAoKmR43FACeAgAAAA==.',
Ch='Chaosgaara:BAAANQADCgEIAQAAAA==.Chikñ:BAAANQAECgQIAQAAAA==.',
Co='Colossus:BAABNQAECn8hAAMZAAoKkB+QJQCoAgAZAAoKkB+QJQCoAgANAAMKUgtDqQB+AAAAAA==.Connor:BAAANQAECgIIBAAAAA==.Correin:BAABNQAECn8/AAIaAAoKGxT9IADuAQAaAAoKGxT9IADuAQAAAA==.',
Cr='Craszhin:BAABNQAECn83AAIQAAoKcQ6zJwCrAQAQAAoKcQ6zJwCrAQAAAA==.Crime:BAAANQAECgMIAwAAAA==.',
['Cè']='Cèl:BAABNQAECn9FAAMbAAoKzRDuCgDVAQAbAAoKzRDuCgDVAQAKAAYKVAMHGQF7AAAAAA==.',
Da='Daddio:BAEANQAECgQIBwAAAA==.Dadeb:BAAANQAECgcICwABNQAECgoKNQAFAMAVAA==.Daenarea:BAAANQADCgYIBgAAAA==.Dangpup:BAABNQAECn9EAAIJAAoKrxdIEQAbAgAJAAoKrxdIEQAbAgAAAA==.Danru:BAAANQADCgQICwAAAA==.Darkdelight:BAABNQAECn87AAIIAAoKQRbOUQB7AgAIAAoKQRbOUQB7AgAAAA==.Dazynth:BAAANQAECgMIAgAAAA==.',
De='Deathlylazy:BAAANQAECgcICgAAAA==.Deets:BAABNQAECn8xAAIIAAoKxCB/IQCsAgAIAAoKxCB/IQCsAgAAAA==.Demona:BAABNQAECn84AAMPAAoKjw3qBQB1AQAPAAoKjw3qBQB1AQAFAAEKEwE7WgEcAAAAAA==.Derfhurnturr:BAAANQAECgUIBgAAAA==.Descalabrada:BAAANQAECggIDQAAAA==.',
Di='Distol:BAAANQADCgIIAgAAAA==.',
Dm='Dmt:BAAANQAECgIIAgAAAA==.',
Dr='Draeamorjan:BAAANQADCgEIAQAAAA==.Driver:BAEANQAECggIBwAAAA==.Drpeppers:BAABNQAECn8wAAITAAoKvRJFHwDmAQATAAoKvRJFHwDmAQAAAA==.',
['Dé']='Déathsavage:BAAANQADCggIHwAAAA==.',
Ea='Eatmorchikin:BAAANQAECgEIAQAAAA==.',
Ec='Eclair:BAABNQAECn85AAIcAAoKviHeDABMAwAcAAoKviHeDABMAwAAAA==.',
El='Elfkr:BAABNQAECn8eAAMcAAgKJiEDIwDbAgAcAAgKJiEDIwDbAgADAAIK+hif+wCbAAAAAA==.Elhayn:BAABNQAECn8yAAIdAAoKUyNOBgABAwAdAAoKUyNOBgABAwAAAA==.Elmos:BAABNQAECn87AAIRAAoKviHtBwBQAwARAAoKviHtBwBQAwAAAA==.',
Er='Erethidian:BAAANQADCgQIBAAAAA==.Eris:BAAANQAECgQICAAAAA==.',
Eu='Eucalyptus:BAAANQAECgQICwAAAA==.',
Ev='Evilmonkeydr:BAAANQAECgQIBAABNQAECgoKHwAKAD0eAA==.Evilmonkeymg:BAABNQAECn8fAAIKAAoKPR5wWwDJAgAKAAoKPR5wWwDJAgAAAA==.Evilmonkeysh:BAAANQADCgUIBQABNQAECgoKHwAKAD0eAA==.',
Ez='Ezaylia:BAABNQAECn8xAAIaAAoKMA8bKwChAQAaAAoKMA8bKwChAQAAAA==.',
Fa='Fatehunter:BAABNQAECn8cAAIIAAcKuhLAmADWAQAIAAcKuhLAmADWAQAAAA==.',
Fe='Feim:BAAANQADCggICAAAAA==.Fergis:BAABNQAECn82AAMbAAoK6BymBQBmAgAbAAkK6BymBQBmAgAKAAYKGxSc+wCWAQAAAA==.',
Fi='Firefox:BAABNQAECn8dAAINAAkKORlONgAyAgANAAkKORlONgAyAgAAAA==.',
Fl='Flypig:BAAANQADCggIBwAAAA==.',
Fr='Frostymonk:BAABNQAECn8iAAMeAAkKZguQGwA4AQAeAAkKZguQGwA4AQAfAAIKlATKIgBFAAAAAA==.Frostypally:BAAANQAECggIDwAAAA==.',
Fu='Fuel:BAAANQADCgYIBgABNQAECgcIGQAIAMwOAA==.Furrybear:BAAANQAECgEIAgAAAA==.',
Ga='Gala:BAABNQAECn8mAAIKAAoK/RYNQwA2AgAKAAoK/RYNQwA2AgAAAA==.',
Ge='Genorian:BAACNQAFFH8GAAIQAAYK7AQlFwCdAAAQAAYK7AQlFwCdAAA1AAQKfzAAAhAACgrxF8UXAEECABAACgrxF8UXAEECAAAA.',
Gi='Gigem:BAABNQAECn8aAAIIAAcKVRysiwDzAQAIAAcKVRysiwDzAQAAAA==.Girlshoon:BAAANQAECgUIBwAAAA==.Githan:BAAANQAECgYIDAABNQAECgkJJwATAK0bAA==.',
Gl='Glarheals:BAAANQADCgEIAQABNQAECgoKOQABAFYRAA==.Glarious:BAABNQAECn85AAIBAAoKVhH3FAA/AgABAAoKVhH3FAA/AgAAAA==.',
Go='Gobbozap:BAAANQADCggIDgABNQAECgoKNwASAA4gAA==.',
Gr='Gredan:BAABNQAECn8qAAINAAgKiRYPMACAAQANAAgKiRYPMACAAQAAAA==.Greymoor:BAAANQABCgQIBAAAAA==.Gruhm:BAAANQADCgUIBQAAAA==.Grôg:BAAANQAECggIEgAAAA==.',
Gu='Guldaniel:BAABNQAECn81AAQFAAoKwBX/PQCZAgAFAAoKwBX/PQCZAgAPAAEKbBexLgBFAAAgAAEK+wHSLwAYAAAAAA==.Guthuzad:BAAANQADCgUIBgAAAA==.Guthx:BAABNQAECn8fAAMQAAoKTRgYRADjAQAQAAgK6BUYRADjAQATAAUKIBBbUQCfAAAAAA==.',
Ha='Halfaman:BAAANQAECgQIBgABNQAFFAIIAgAHAAAAAA==.Hantzel:BAAANQADCgUIBQAAAA==.',
He='Healyeah:BAAANQAECgEIAQAAAA==.Hellen:BAABNQAECn8cAAIFAAoKnSDuLADSAgAFAAoKnSDuLADSAgAAAA==.',
Hw='Hwat:BAAANQAECgYIDwAAAA==.',
Ic='Ictus:BAABNQAECn8ZAAIKAAoK+RzjcACcAgAKAAoK+RzjcACcAgAAAA==.',
In='Incredabull:BAAANQAECgIIAgAAAA==.',
Is='Isabelle:BAACNQAFFH8KAAIJAAMKHQc8FACaAAAJAAMKHQc8FACaAAA1AAQKf0AAAgkACQoBGJkSAAUCAAkACQoBGJkSAAUCAAAA.Isharded:BAABNQAECn9DAAMgAAoK3hEuBwAvAgAgAAoK3hEuBwAvAgAFAAYKLgZEoAACAQAAAA==.Istayblunted:BAAANQAECgUIDAAAAA==.',
Ja='Jacqualyn:BAAANQAFFAIIAgAAAA==.Jaylon:BAAANQADCgUIBQAAAA==.',
Ji='Jiayerah:BAAANQADCggIDwABNQAECggIKgALAOIWAA==.Jinkuzo:BAABNQAECn81AAIfAAoKlhxJBABrAgAfAAoKlhxJBABrAgAAAA==.Jinmu:BAABNQAECn85AAMBAAoKQBItGQAQAgABAAoKQBItGQAQAgACAAcKJwjeVgBfAQAAAA==.',
Ju='Juanaloopa:BAAANQAECgcIDAAAAA==.Juggie:BAABNQAECn8dAAMLAAcKVwWCnQA9AQALAAcKVwWCnQA9AQAdAAUKXwSwVAC7AAAAAA==.Julienned:BAABNQAECn9HAAICAAoKVhT2CwABAgACAAoKVhT2CwABAgAAAA==.',
['Jè']='Jèsse:BAAANQADCgcJBwAAAA==.',
Ka='Kainen:BAABNQAECn85AAQOAAoKaRmnZABtAgAOAAoKaRmnZABtAgAEAAQKGQOP8QCdAAAMAAQK4QNSWgBzAAAAAA==.',
Ke='Kesoyi:BAAANQADCgMIAwABNQAFFAIIAgAHAAAAAA==.',
Ki='Kinkybunny:BAAANQADCgYJBgAAAA==.',
Kl='Klodar:BAABNQAECn8sAAIdAAgKsxTfHACTAQAdAAgKsxTfHACTAQAAAA==.Klum:BAAANQABCgQIBgAAAA==.',
Kr='Krazee:BAAANQABCgMIBQAAAA==.Krotallas:BAAANQAECgYIBAAAAA==.',
La='Lafey:BAAANQADCgIJAgAAAA==.Lamedout:BAAANQADCgcIBwABNQAECgcIGQAIAMwOAA==.Lanfear:BAAANQADCgQIBAAAAA==.Laurenya:BAAANQADCgMIAwABNQAECgUIDgAHAAAAAA==.',
Le='Leida:BAAANQADCgcICwAAAA==.Leinen:BAAANQAECgUIBAAAAA==.',
Lo='Logi:BAAANQAECgUIDQAAAA==.Lostrage:BAAANQADCgcICgAAAA==.',
Lu='Lumiyer:BAABNQAECn8rAAILAAoKbB2LDwBQAwALAAoKbB2LDwBQAwABNQAFFAcIGgAeAHgcAA==.',
Ly='Lygra:BAABNQAECn8mAAIIAAgKYhIpiACMAQAIAAgKYhIpiACMAQAAAA==.Lykana:BAAANQAECgQIBQAAAA==.Lyrasong:BAAANQADCgMIAwAAAA==.Lytharielis:BAAANQABCgQIBAAAAA==.',
Ma='Majellan:BAABNQAECn9OAAMMAAoKNhxCCwBtAgAMAAoKNhxCCwBtAgAOAAgKzw2NuACtAQAAAA==.Marsawn:BAABNQAECn9HAAMLAAoKkxh/LwCqAgALAAoKkxh/LwCqAgAdAAgKGBmXFQDxAQAAAA==.Mass:BAACNQAFFH8dAAIVAAgKzCUWAADzAgAVAAgKzCUWAADzAgA1AAQKfzkAAhUACgrYJh0AAJsDABUACgrYJh0AAJsDAAAA.',
Me='Meatbatticus:BAAANQAECgcIDAAAAA==.Meqi:BAABNQAECn8qAAMKAAgKASIzRgAtAgAKAAgKASIzRgAtAgAhAAMKuh38BAD+AAAAAA==.',
Mi='Mindlessness:BAABNQAECn9DAAIWAAoKcR/IIgCsAgAWAAoKcR/IIgCsAgAAAA==.Mineralelf:BAABNQAECn9OAAIIAAoKoww9YwDmAQAIAAoKoww9YwDmAQAAAA==.Minichaos:BAABNQAECn87AAMPAAoKYhYaBQCYAQAPAAkK7hQaBQCYAQAFAAgKDQ+QZwCMAQAAAA==.Miriam:BAABNQAECn9QAAIKAAoK4hHhTAAaAgAKAAoK4hHhTAAaAgAAAA==.',
Mo='Mojosavage:BAABNQAECn8YAAIFAAcKWgPJ6AD4AAAFAAcKWgPJ6AD4AAAAAA==.Moonblade:BAAANQAECgYICQAAAA==.',
My='Mylas:BAAANQADCgcIBwAAAA==.Mysticalfox:BAAANQADCgEIAQAAAA==.Mythrixx:BAAANQAECgcIDQAAAA==.',
Na='Nalfilas:BAABNQAECn8aAAIKAAYK+geVNgExAQAKAAYK+geVNgExAQAAAA==.',
Ne='Necromm:BAAANQABCgQIBgAAAA==.Nephaleos:BAABNQAECn8mAAIiAAkKnR+UCwDqAgAiAAkKnR+UCwDqAgAAAA==.Nessie:BAAANQAECgIIAgAAAA==.',
Ni='Nihlus:BAABNQAECn8YAAIOAAoKTQmRyAAuAQAOAAoKTQmRyAAuAQAAAA==.',
No='Nocturnous:BAAANQAECgQICgAAAA==.',
Nu='Nurzul:BAAANQADCggICAABNQAECggIEgAHAAAAAA==.',
Ny='Nyrvana:BAAANQAECgYICQAAAA==.',
['Nà']='Nàtureswrath:BAABNQAECn8ZAAIIAAcKzA6otQArAQAIAAcKzA6otQArAQAAAA==.',
Og='Ogre:BAAANQADCggIGAAAAA==.',
Or='Orceo:BAABNQAECn9AAAIIAAoK0yPvCwAmAwAIAAoK0yPvCwAmAwAAAA==.Orkeo:BAAANQADCgcICwAAAA==.Orkreghar:BAABNQAECn88AAIIAAoK1B4nNwBdAgAIAAoK1B4nNwBdAgAAAA==.',
Pa='Pallon:BAAANQAECgcJCwAAAA==.',
Pe='Perkybites:BAAANQABCggICQAAAA==.',
Ph='Phazma:BAAANQADCgUIBQAAAA==.',
Pi='Pindapin:BAAANQAECgMIBQAAAA==.',
Po='Poco:BAAANQABCgcIDQAAAA==.Pompompower:BAABNQAECn80AAIDAAoKAAnkdwC6AQADAAoKAAnkdwC6AQAAAA==.Popashammy:BAAANQAECgIIAgAAAA==.Poplock:BAAANQADCgcIFgAAAA==.Popple:BAABNQAECn8lAAIjAAoKMhB2CwC7AQAjAAoKMhB2CwC7AQAAAA==.Potential:BAAANQAECgQIBAAAAA==.',
Pu='Puggsly:BAAANQAECgYIDgABNQAECgoKNQAFAMAVAA==.',
Qu='Quixotical:BAAANQADCgYIDAAAAA==.',
Ra='Radaghast:BAAANQAECgIIAgAAAA==.',
Re='Rectumraker:BAAANQAECgUICgAAAA==.Reishirome:BAAANQADCggIFQAAAA==.Revenmar:BAAANQADCgQIBAAAAA==.',
Rh='Rhaelin:BAABNQAECn81AAIcAAoKJh5IHgDyAgAcAAoKJh5IHgDyAgAAAA==.Rhaellia:BAAANQADCggICAAAAA==.Rhoke:BAABNQAECn8vAAIOAAgKIhBcrgDCAQAOAAgKIhBcrgDCAQAAAA==.',
Ro='Rockyy:BAAANQAECgQIBAAAAA==.Romeoz:BAAANQAECgcIBwABNQAFFAIIAgAHAAAAAA==.Rona:BAAANQAECgQIDAAAAA==.Roofhouse:BAAANQAECgEIAQAAAA==.Rosary:BAABNQAECn8gAAILAAoKWyAsJQDXAgALAAoKWyAsJQDXAgAAAA==.Rotiserychic:BAAANQAECgcIDAAAAA==.Roukia:BAAANQADCgEIAQAAAA==.',
Ru='Rusticfinger:BAABNQAECn8fAAIcAAoKQBQSUwAaAgAcAAoKQBQSUwAaAgAAAA==.',
Sa='Sacerdote:BAAANQAECgMIBAAAAA==.Sansa:BAABNQAECn8qAAILAAgK4hZbTADyAQALAAgK4hZbTADyAQAAAA==.Saruma:BAAANQADCggIDgABNQAECggIEgAHAAAAAA==.',
Sc='Scalygrob:BAABNQAECn8YAAIkAAoKdRASFgDqAQAkAAoKdRASFgDqAQAAAA==.Scarytery:BAAANQAECgYIEAAAAA==.Scrügemcmonk:BAAANQAECgQIBAAAAA==.',
Sh='Shamaya:BAAANQABCgMIAwABNQADCgIIAgAHAAAAAA==.Shamfox:BAABNQAECn8YAAMDAAcKDw0PkQB6AQADAAcKDw0PkQB6AQAcAAEKNwJTKQElAAAAAA==.',
Si='Sidewinder:BAAANQAECgYICQAAAA==.',
Sm='Smogcheck:BAACNQAFFH8MAAMiAAMKLBK1EgCDAAAiAAIKHRS1EgCDAAAkAAIKsgQsBgBoAAA1AAQKfzUAAyIACgraF3ITAHYCACIACgraF3ITAHYCACQABQqaD/8aAIQAAAAA.',
Sn='Snowsz:BAABNQAECn8WAAIKAAkKnBhdYQDkAQAKAAkKnBhdYQDkAQAAAA==.Snowws:BAABNQAECn8uAAIaAAoKtx5lEQAUAwAaAAoKtx5lEQAUAwAAAA==.Snowzz:BAAANQAECggIEQAAAA==.',
So='Sonektot:BAAANQAECgEIAQAAAA==.Sortis:BAABNQAECn8iAAMKAAkKGRx/ZAC1AgAKAAkKGRx/ZAC1AgAbAAEK/wNQUAAnAAAAAA==.',
Sp='Spicebreff:BAAANQAECgEIAQABNQAECggIHQAWAKEXAA==.',
St='Steck:BAABNQAECn8gAAIIAAcKHhEmtQCaAQAIAAcKHhEmtQCaAQAAAA==.Strigg:BAAANQADCgMIAwAAAA==.',
Su='Suprahunts:BAABNQAECn8dAAMIAAcKcCLRUgB4AgAIAAcKcCLRUgB4AgAJAAQKeA3tVQDOAAAAAA==.',
['Sà']='Sàlís:BAAANQADCgcIEAAAAA==.',
Ta='Talander:BAAANQADCgUIBQABNQAFFAIIAgAHAAAAAA==.Talas:BAABNQAECn8+AAMIAAoKoht3MQDYAgAIAAoKoht3MQDYAgAJAAYK1w+JRQAtAQAAAA==.',
Te='Teaka:BAAANQAECgEIAQAAAA==.Temberle:BAAANQAECgQIBAABNQAECggIFgAQAPMMAA==.',
Th='Thaeker:BAAANQADCggIDgAAAA==.Thaelink:BAAANQAECgEIAQABNQAECgkJIAAKAE8XAA==.Thickthighs:BAAANQAECgYICgABNQAFFAIIAgAHAAAAAA==.Thorss:BAAANQAECgUIDAABNQAECggIIAAOACUKAA==.Thrann:BAABNQAECn87AAIZAAoKkybuAAB/AwAZAAoKkybuAAB/AwAAAA==.',
Ti='Tirium:BAABNQAECn8dAAIWAAgKoRfenADUAQAWAAgKoRfenADUAQAAAA==.',
To='Tolkien:BAABNQAECn8qAAIYAAkKVhJFKQD9AQAYAAkKVhJFKQD9AQAAAA==.',
Tu='Tubbytotem:BAAANQADCgYICgAAAA==.',
Un='Unduril:BAAANQADCgYIBgAAAA==.',
Ur='Ursae:BAAANQADCgIIAgAAAA==.',
Va='Vanargandr:BAAANQADCgYIBgAAAA==.Vartlek:BAAANQADCgYIBQAAAA==.',
Ve='Velarys:BAAANQABCgIIAgABNQAECgoKNwASAA4gAA==.Velinlock:BAAANQABCgEIAQAAAA==.Velinthil:BAAANQADCgcIBwAAAA==.Verðandi:BAAANQADCgMJAwAAAA==.',
Vi='Vigilante:BAAANQAECgUIBQAAAA==.Vitrois:BAAANQADCgEIAQABNQAECgoKLAAZAIsdAA==.',
Vo='Voidraven:BAAANQAECgQIBgAAAA==.Volvox:BAAANQADCggICwAAAA==.',
Vy='Vyxenn:BAABNQAECn9OAAMcAAoKTRy4GwDGAgAcAAoKTRy4GwDGAgADAAIK1wbXFwFfAAAAAA==.',
Wa='Wanders:BAAANQAECgQIAQABNQAECgQIBAAHAAAAAA==.Washim:BAAANQADCggICQAAAA==.',
Wo='Wonkybits:BAAANQAECgQIBgAAAA==.',
Wu='Wurm:BAAANQADCgQIBAABNQAECggIEgAHAAAAAA==.',
Ye='Yejena:BAABNQAECn8ZAAIOAAkK+Qk6twBMAQAOAAkK+Qk6twBMAQAAAA==.',
Ym='Ymir:BAAANQADCgQIBAAAAA==.',
Za='Zaleras:BAAANQADCggIDgAAAA==.',
Ze='Zerkium:BAAANQAECgcIEQAAAA==.',
Zi='Zillaamiri:BAABNQAECn8YAAIlAAkKeQIUIgDzAAAlAAkKeQIUIgDzAAAAAA==.',
Zu='Zugzugdaboo:BAAANQADCggIFgAAAA==.',
Zy='Zyreal:BAAANQADCgIIAgAAAA==.Zyrinx:BAAANQABCgIIAgAAAA==.Zywol:BAABNQAECn9OAAMQAAoKvhj9GgAdAgAQAAoKvhj9GgAdAgATAAkKEQ6cJQCoAQAAAA==.',
['Ër']='Ëresta:BAAANQADCgYIEwABNQAECgoKNgAIAAkdAA==.',
['Ðe']='Ðespair:BAABNQAECn8gAAMLAAoK9h1bTABAAgALAAcKgRxbTABAAgAdAAgKNRpLHgCEAQAAAA==.',
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
