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
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abednego:BAABNQAECn8yAAMBAAkKrxdVDgCSAgABAAkKZRdVDgCSAgACAAQKFQ7wQAB4AAAAAA==.',
Ac='Acidrain:BAABNQAECn8zAAIDAAkKAxsVLQDxAQADAAkKAxsVLQDxAQAAAA==.Acmiax:BAABNQAECn8YAAIEAAgKaw9EUQCcAQAEAAgKaw9EUQCcAQABNQAECgoKNQAFAMAVAA==.',
Ad='Adar:BAAANQAECgUIDwAAAA==.Adonsinn:BAABNQAECn8cAAIGAAgKMCGPGQCOAgAGAAgKMCGPGQCOAgAAAA==.',
Ae='Aegos:BAAANQAECgQIBgAAAA==.Aep:BAAANQAECgMJBAABNQAECgUIDQAHAAAAAA==.',
Ah='Ahu:BAABNQAECn81AAMIAAkK3hbUSACSAgAIAAkK3hbUSACSAgAJAAEKKgZMlQArAAAAAA==.',
Ai='Aiden:BAAANQAECgYIDAAAAA==.Airotciv:BAAANQAECgEIAQAAAA==.',
Al='Alakazam:BAAANQADCgUIBgAAAA==.Alanath:BAAANQADCgQIBAAAAA==.Alandramun:BAAANQAECgIIAgAAAA==.Aleroderp:BAABNQAECn8cAAIJAAkKHQSwKgDeAAAJAAkKHQSwKgDeAAAAAA==.Allaria:BAAANQAECgIIBQAAAA==.Alucard:BAAANQAECgIIAwAAAA==.',
Am='Amaging:BAABNQAECn8lAAIKAAkKqgqmxAD7AQAKAAkKqgqmxAD7AQAAAA==.Ambassador:BAAANQAECgUIBQAAAA==.Amoondai:BAACNQAFFH8MAAILAAMKrh2QFAApAQALAAMKrh2QFAApAQA1AAQKf08AAgsACgq3I+sNAFUDAAsACgq3I+sNAFUDAAAA.',
An='Analytics:BAABNQAECn8VAAIMAAcKchGQLAB4AQAMAAcKchGQLAB4AQAAAA==.Angusdei:BAAANQADCgIIAgAAAA==.Anyr:BAAANQADCgMIAwAAAA==.',
Ap='Apochryphal:BAABNQAECn81AAINAAkKnyCwEgBcAgANAAkKnyCwEgBcAgAAAA==.',
Ar='Araon:BAAANQAECgMIAwAAAA==.Araylva:BAAANQADCggIDwAAAA==.Arienei:BAAANQAECgEIAgAAAA==.Arrtemiss:BAAANQADCgMIAwABNQAECgUIDgAHAAAAAA==.',
As='Ashogg:BAAANQAECgYIEwAAAA==.',
Au='Aurén:BAAANQADCggIEwAAAA==.',
Az='Azuree:BAAANQAECgMIBgAAAA==.',
Ba='Bacstabath:BAABNQAECn9DAAMCAAoK5iIODwAJAwACAAgKKCMODwAJAwABAAoKYR7TDwB/AgAAAA==.Baelgrimm:BAABNQAECn8XAAMOAAgKWQsZtAApAQAOAAcKWQsZtAApAQAMAAEKAAAybgAAAAAAAA==.',
Be='Becca:BAABNQAECn89AAIMAAoKUR7ZCACHAgAMAAoKUR7ZCACHAgAAAA==.Bequin:BAAANQADCgUIBQAAAA==.',
Bi='Bigdaddys:BAAANQAECgMIAgAAAA==.Bigduh:BAAANQADCgQIBAAAAA==.Birblock:BAABNQAECn9IAAMFAAoKyyMjBwAeAwAFAAoKyyMjBwAeAwAPAAQK8A9YNgDoAAABNQAFFAcIFwAQANYSAA==.',
Bl='Blaizee:BAAANQAECgEIAQAAAA==.Blasphemar:BAAANQADCgYJBgAAAA==.Bloodios:BAABNQAECn9IAAINAAoKaByrEgBcAgANAAoKaByrEgBcAgAAAA==.Bluechewgold:BAABNQAECn8mAAINAAoKMCHJCgBeAwANAAoKMCHJCgBeAwAAAA==.',
Bo='Bobbardment:BAAANQADCgQIBAABNQAECgQIBAAHAAAAAA==.Bobin:BAABNQAECn8hAAIRAAoKKRBKKQDUAQARAAoKKRBKKQDUAQAAAA==.Bombadil:BAABNQAECn8uAAISAAkKJRAfBADKAQASAAkKJRAfBADKAQAAAA==.Boshek:BAAANQABCgUJCQAAAA==.',
Br='Bribage:BAACNQAFFH8XAAMQAAcK1hLKDwBtAQAQAAcK1hLKDwBtAQATAAEKowkQFQBKAAA1AAQKfywAAxAACgr3IbUcAOMCABAACgr3IbUcAOMCABQAAgrWGTQ3AEIAAAAA.Brightest:BAAANQAECgIIAQAAAA==.Brolaf:BAAANQADCgIIAgABNQAFFAYIFQAEAB0kAA==.Brolavski:BAACNQAFFH8VAAIEAAYKHSQvBgANAgAEAAYKHSQvBgANAgA1AAQKfxcAAgQACQr/HnYuAK0CAAQACQr/HnYuAK0CAAAA.',
Bu='Budderwar:BAABNQAECn83AAMVAAkKZSYJAQDKAwAVAAkKZSYJAQDKAwAWAAQK9RGs9QDzAAAAAA==.Buster:BAABNQAECn8dAAMXAAoKDwrLFQBPAQAXAAoKDwrLFQBPAQAGAAQKhQMZYQBpAAAAAA==.Buzkills:BAAANQABCgIIAwAAAA==.',
['Bà']='Bàdmofos:BAAANQADCgcIBwAAAA==.',
Ce='Celerydk:BAABNQAECn9DAAIYAAoK9B1pEgCUAgAYAAoK9B1pEgCUAgAAAA==.',
Ch='Chaosgaara:BAAANQADCgEIAQAAAA==.Chikñ:BAAANQAECgQIAQAAAA==.',
Co='Colossus:BAABNQAECn8hAAMZAAoKkB+QJQCoAgAZAAoKkB+QJQCoAgANAAMKUgtDqQB+AAAAAA==.Connor:BAAANQAECgIIBAAAAA==.Correin:BAABNQAECn87AAIaAAoKMRMNHgDiAQAaAAoKMRMNHgDiAQAAAA==.',
Cr='Craszhin:BAABNQAECn8zAAIQAAkKAA4cKwBvAQAQAAkKAA4cKwBvAQAAAA==.Crime:BAAANQAECgMIAwAAAA==.',
['Cè']='Cèl:BAABNQAECn8/AAMbAAoKzRBMDgDHAQAbAAoKzRBMDgDHAQAKAAYKVANrCgF9AAAAAA==.',
Da='Daddio:BAEANQAECgQIBwAAAA==.Dadeb:BAAANQAECgcIDAABNQAECgoKNQAFAMAVAA==.Daenarea:BAAANQADCgYIBgAAAA==.Dangpup:BAABNQAECn88AAIJAAoKrxdOEAAFAgAJAAoKrxdOEAAFAgAAAA==.Danru:BAAANQADCgQICwAAAA==.Darkdelight:BAABNQAECn87AAIIAAoKQRbOUQB7AgAIAAoKQRbOUQB7AgAAAA==.',
De='Deathlylazy:BAAANQAECgcICgAAAA==.Deets:BAABNQAECn8tAAIIAAkKLSHkLQBcAgAIAAkKLSHkLQBcAgAAAA==.Demona:BAABNQAECn80AAMPAAkKpgwlBgBQAQAPAAkKpgwlBgBQAQAFAAEKEwE7WgEcAAAAAA==.Derfhurnturr:BAAANQAECgUIBgAAAA==.Descalabrada:BAAANQAECggIDQAAAA==.',
Di='Distol:BAAANQADCgIIAgAAAA==.',
Dm='Dmt:BAAANQAECgIIAgAAAA==.',
Dr='Draeamorjan:BAAANQADCgEIAQAAAA==.Driver:BAEANQAECggICAAAAA==.Drpeppers:BAABNQAECn8sAAITAAkKlxMSHwC1AQATAAkKlxMSHwC1AQAAAA==.',
['Dé']='Déathsavage:BAAANQADCggIHwAAAA==.',
Ea='Eatmorchikin:BAAANQAECgEIAQAAAA==.',
Ec='Eclair:BAABNQAECn81AAIcAAkKuiFSEwDyAgAcAAkKuiFSEwDyAgAAAA==.',
El='Elfkr:BAABNQAECn8eAAMcAAgKJiEDIwDbAgAcAAgKJiEDIwDbAgADAAIK+hif+wCbAAAAAA==.Elhayn:BAABNQAECn8xAAIdAAkK6yOMCABUAwAdAAkK6yOMCABUAwAAAA==.Elmos:BAABNQAECn87AAIRAAoKviHtBwBQAwARAAoKviHtBwBQAwAAAA==.',
Er='Erethidian:BAAANQADCgQIBAAAAA==.Eris:BAAANQAECgYICgAAAA==.',
Eu='Eucalyptus:BAAANQAECgYICQAAAA==.',
Ev='Evilmonkeydr:BAAANQAECgQIBAABNQAECgoKHwAKAD0eAA==.Evilmonkeymg:BAABNQAECn8fAAIKAAoKPR5wWwDJAgAKAAoKPR5wWwDJAgAAAA==.Evilmonkeysh:BAAANQADCgUIBQABNQAECgoKHwAKAD0eAA==.',
Ez='Ezaylia:BAABNQAECn8tAAIaAAkKvA9JLABxAQAaAAkKvA9JLABxAQAAAA==.',
Fa='Fatehunter:BAABNQAECn8cAAIIAAcKuhLAmADWAQAIAAcKuhLAmADWAQAAAA==.',
Fe='Feim:BAAANQADCggICAAAAA==.Fergis:BAABNQAECn8yAAMbAAkKKBymBwADAgAbAAgKKBymBwADAgAKAAYKGxSc+wCWAQAAAA==.',
Fi='Firefox:BAABNQAECn8dAAINAAkKORlONgAyAgANAAkKORlONgAyAgAAAA==.',
Fl='Flypig:BAAANQADCggIBwAAAA==.',
Fr='Frostymonk:BAABNQAECn8iAAMeAAkKZgt6GAA+AQAeAAkKZgt6GAA+AQAfAAIKlATJHwBHAAAAAA==.Frostypally:BAAANQAECggIDwAAAA==.',
Fu='Fuel:BAAANQADCgYIBgABNQAECgcIFAAIAOgMAA==.Furrybear:BAAANQAECgEIAgAAAA==.',
Ga='Gala:BAABNQAECn8jAAIKAAoK/RYiOQBAAgAKAAoK/RYiOQBAAgAAAA==.',
Ge='Genorian:BAABNQAECn8rAAIQAAoKGBeEFgAxAgAQAAoKGBeEFgAxAgAAAA==.',
Gi='Gigem:BAABNQAECn8aAAIIAAcKVRysiwDzAQAIAAcKVRysiwDzAQAAAA==.Girlshoon:BAAANQAECgYIBwAAAA==.Githan:BAAANQAECgYIDAABNQAECgkJJwATAK0bAA==.',
Gl='Glarheals:BAAANQADCgEIAQABNQAECgoKOAABAFYRAA==.Glarious:BAABNQAECn84AAIBAAoKVhH3FAA/AgABAAoKVhH3FAA/AgAAAA==.',
Go='Gobbozap:BAAANQADCggIDgABNQAECgoKNwASAA4gAA==.',
Gr='Gredan:BAABNQAECn8jAAINAAgKiRaVKwB/AQANAAgKiRaVKwB/AQAAAA==.Greymoor:BAAANQABCgQIBAAAAA==.Gruhm:BAAANQADCgUIBQAAAA==.Grôg:BAAANQAECggIEgAAAA==.',
Gu='Guldaniel:BAABNQAECn81AAQFAAoKwBX/PQCZAgAFAAoKwBX/PQCZAgAPAAEKbBd1KgBGAAAgAAEK+wEKKgAYAAAAAA==.Guthuzad:BAAANQADCgUIBgAAAA==.Guthx:BAABNQAECn8fAAMQAAoKTRgYRADjAQAQAAgK6BUYRADjAQATAAUKIBA8SgCbAAAAAA==.',
Ha='Halfaman:BAAANQAECgQIBwABNQAFFAIIAgAHAAAAAA==.Hantzel:BAAANQADCgUIBQAAAA==.',
He='Healyeah:BAAANQAECgEIAQAAAA==.Hellen:BAABNQAECn8cAAIFAAoKnSDuLADSAgAFAAoKnSDuLADSAgAAAA==.',
Hw='Hwat:BAAANQAECgYIDwAAAA==.',
Ic='Ictus:BAABNQAECn8ZAAIKAAoK+RzjcACcAgAKAAoK+RzjcACcAgAAAA==.',
In='Incredabull:BAAANQAECgIIAgAAAA==.',
Is='Isabelle:BAACNQAFFH8KAAIJAAMKHQdpEACcAAAJAAMKHQdpEACcAAA1AAQKfzoAAgkACQrwFtsWAJ4BAAkACQrwFtsWAJ4BAAAA.Isharded:BAABNQAECn89AAIgAAoK3hHXBQDeAQAgAAoK3hHXBQDeAQAAAA==.Istayblunted:BAAANQAECgUIDQAAAA==.',
Ja='Jacqualyn:BAAANQAFFAIIAgAAAA==.Jaylon:BAAANQADCgUIBQAAAA==.',
Ji='Jiayerah:BAAANQADCggIDwABNQAECggIIwALAOIWAA==.Jinkuzo:BAABNQAECn8xAAIfAAkKzxwwBQAcAgAfAAkKzxwwBQAcAgAAAA==.Jinmu:BAABNQAECn81AAMBAAkKhRItGQAQAgABAAkKhRItGQAQAgACAAcKJwjeVgBfAQAAAA==.',
Ju='Juanaloopa:BAAANQAECgcIDQAAAA==.Juggie:BAABNQAECn8dAAMLAAcKVwWCnQA9AQALAAcKVwWCnQA9AQAdAAUKXwSwVAC7AAAAAA==.Julienned:BAABNQAECn9BAAICAAoK8hKnCwDvAQACAAoK8hKnCwDvAQAAAA==.',
['Jè']='Jèsse:BAAANQADCgcJBwAAAA==.',
Ka='Kainen:BAABNQAECn81AAQOAAkKvhmnZABtAgAOAAkKvhmnZABtAgAEAAQKGQOP8QCdAAAMAAQK4QNSWgBzAAAAAA==.',
Ke='Kesoyi:BAAANQADCgMIAwABNQAFFAIIAgAHAAAAAA==.',
Ki='Kinkybunny:BAAANQADCgYJBgAAAA==.',
Kl='Klodar:BAABNQAECn8mAAIdAAgKyxNcHAByAQAdAAgKyxNcHAByAQAAAA==.Klum:BAAANQABCgQIBgAAAA==.',
Kr='Krazee:BAAANQABCgMIBQAAAA==.Krotallas:BAAANQAECgYIBwAAAA==.',
La='Lafey:BAAANQADCgIJAgAAAA==.Lamedout:BAAANQADCgcIBwABNQAECgcIFAAIAOgMAA==.Lanfear:BAAANQADCgQIBAAAAA==.Laurenya:BAAANQADCgMIAwABNQAECgUIDgAHAAAAAA==.',
Le='Leida:BAAANQADCgcICwAAAA==.Leinen:BAAANQAECgUIBAAAAA==.',
Lo='Logi:BAAANQAECgUIDQAAAA==.Lostrage:BAAANQADCgcICgAAAA==.',
Lu='Lumiyer:BAABNQAECn8hAAILAAoKjxolFgD5AgALAAoKjxolFgD5AgABNQAFFAcIGQAeAHgcAA==.',
Ly='Lygra:BAABNQAECn8fAAIIAAcKHhNtlQBDAQAIAAcKHhNtlQBDAQAAAA==.Lykana:BAAANQAECgQIBQAAAA==.Lyrasong:BAAANQADCgMIAwAAAA==.Lytharielis:BAAANQABCgQIBAAAAA==.',
Ma='Majellan:BAABNQAECn9IAAMMAAoKnRu+CgBaAgAMAAoKnRu+CgBaAgAOAAgKzw2NuACtAQAAAA==.Marsawn:BAABNQAECn9HAAMLAAoKkxh/LwCqAgALAAoKkxh/LwCqAgAdAAgKGBnwEgDzAQAAAA==.Mass:BAACNQAFFH8dAAIVAAgKzCUOAABwAgAVAAgKzCUOAABwAgA1AAQKfzUAAhUACgrOJh0AAJoDABUACgrOJh0AAJoDAAAA.',
Me='Meatbatticus:BAAANQAECgcIDQAAAA==.Meqi:BAABNQAECn8jAAMKAAgKASKFOwA4AgAKAAgKASKFOwA4AgAhAAIKJRq9CgBVAAAAAA==.',
Mi='Mindlessness:BAABNQAECn89AAIWAAoK8h4SKgB0AgAWAAoK8h4SKgB0AgAAAA==.Mineralelf:BAABNQAECn9IAAIIAAoKVwyzWgDPAQAIAAoKVwyzWgDPAQAAAA==.Minichaos:BAABNQAECn82AAMPAAkKCRZ/BACQAQAPAAkKuxN/BACQAQAFAAYKVA+vhAAeAQAAAA==.Miriam:BAABNQAECn9MAAIKAAoKthA3SAAPAgAKAAoKthA3SAAPAgAAAA==.',
Mo='Mojosavage:BAABNQAECn8YAAIFAAcKWgPJ6AD4AAAFAAcKWgPJ6AD4AAAAAA==.Moonblade:BAAANQAECgMIBgAAAA==.',
My='Mylas:BAAANQADCgcIBwAAAA==.Mysticalfox:BAAANQADCgEIAQAAAA==.Mythrixx:BAAANQAECggIDAAAAA==.',
Na='Nalfilas:BAABNQAECn8aAAIKAAYK+geVNgExAQAKAAYK+geVNgExAQAAAA==.',
Ne='Necromm:BAAANQABCgQIBgAAAA==.Nephaleos:BAABNQAECn8mAAIiAAkKnR+UCwDqAgAiAAkKnR+UCwDqAgAAAA==.Nessie:BAAANQAECgIIAwAAAA==.',
Ni='Nihlus:BAAANQAECggIEwAAAA==.',
No='Nocturnous:BAAANQAECgUICwAAAA==.',
Nu='Nurzul:BAAANQADCggICAABNQAECggIEgAHAAAAAA==.',
Ny='Nyrvana:BAAANQAECgYICQAAAA==.',
['Nà']='Nàtureswrath:BAABNQAECn8UAAIIAAcK6AwXsgAJAQAIAAcK6AwXsgAJAQAAAA==.',
Og='Ogre:BAAANQADCggIGAAAAA==.',
Or='Orceo:BAABNQAECn84AAIIAAoKxiIVDwD+AgAIAAoKxiIVDwD+AgAAAA==.Orkeo:BAAANQADCgcICwAAAA==.Orkreghar:BAABNQAECn8zAAIIAAoKhB2GNgA9AgAIAAoKhB2GNgA9AgAAAA==.',
Pa='Pallon:BAAANQAECgcJCwAAAA==.',
Pe='Perkybites:BAAANQAECgEIAQAAAA==.',
Ph='Phazma:BAAANQADCgUIBQAAAA==.',
Pi='Pindapin:BAAANQAECgMIBQAAAA==.',
Po='Pompompower:BAABNQAECn80AAIDAAoKAAnkdwC6AQADAAoKAAnkdwC6AQAAAA==.Popashammy:BAAANQAECgIIAgAAAA==.Poplock:BAAANQADCgcIFgAAAA==.Popple:BAABNQAECn8hAAIjAAkK7w8XDACEAQAjAAkK7w8XDACEAQAAAA==.Potential:BAAANQAECgQIBAAAAA==.',
Pu='Puggsly:BAAANQAECggIDgABNQAECgoKNQAFAMAVAA==.',
Qu='Quixotical:BAAANQADCgYIDAAAAA==.',
Ra='Radaghast:BAAANQAECgIIAgAAAA==.',
Re='Rectumraker:BAAANQAECgMIDAAAAA==.Reishirome:BAAANQADCggIFQAAAA==.Revenmar:BAAANQADCgQIBAAAAA==.',
Rh='Rhaelin:BAABNQAECn8zAAIcAAoKyRxIHgDyAgAcAAoKyRxIHgDyAgAAAA==.Rhaellia:BAAANQADCggICAAAAA==.Rhoke:BAABNQAECn8vAAIOAAgKIhBcrgDCAQAOAAgKIhBcrgDCAQAAAA==.',
Ro='Rockyy:BAAANQAECgQIBAAAAA==.Romeoz:BAAANQAECgcICAABNQAFFAIIAgAHAAAAAA==.Rona:BAAANQAECgQIDAAAAA==.Roofhouse:BAAANQADCgMIAwAAAA==.Rosary:BAABNQAECn8gAAILAAoKWyAsJQDXAgALAAoKWyAsJQDXAgAAAA==.Rotiserychic:BAAANQAECgcICQAAAA==.Roukia:BAAANQADCgEIAQAAAA==.',
Ru='Rusticfinger:BAABNQAECn8fAAIcAAoKQBQSUwAaAgAcAAoKQBQSUwAaAgAAAA==.',
Sa='Sacerdote:BAAANQAECgMIBAAAAA==.Sansa:BAABNQAECn8jAAILAAgK4hZ9QAAAAgALAAgK4hZ9QAAAAgAAAA==.Saruma:BAAANQADCggIDgABNQAECggIEgAHAAAAAA==.',
Sc='Scalygrob:BAABNQAECn8YAAIkAAoKdRASFgDqAQAkAAoKdRASFgDqAQAAAA==.Scarytery:BAAANQAECgYIEAAAAA==.Scrügemcmonk:BAAANQAECgQIBAAAAA==.',
Sh='Shaithais:BAAANQAECggIAQAAAA==.Shamaya:BAAANQABCgMIAwABNQADCgIIAgAHAAAAAA==.Shamfox:BAABNQAECn8YAAMDAAcKDw0PkQB6AQADAAcKDw0PkQB6AQAcAAEKNwJTKQElAAAAAA==.',
Si='Sidewinder:BAAANQAECgYICQAAAA==.',
Sm='Smogcheck:BAACNQAFFH8KAAMiAAIKHRRYEACEAAAiAAIKHRRYEACEAAAkAAEKmAUQCAA2AAA1AAQKfzQAAyIACgraF3ITAHYCACIACgraF3ITAHYCACQABQqaD+IYAIQAAAAA.',
Sn='Snowsz:BAABNQAECn8WAAIKAAkKnBjnVgDmAQAKAAkKnBjnVgDmAQAAAA==.Snowws:BAABNQAECn8uAAIaAAoKtx5lEQAUAwAaAAoKtx5lEQAUAwAAAA==.Snowzz:BAAANQAECggIDgAAAA==.',
So='Sonektot:BAAANQAECgEIAQAAAA==.Sortis:BAABNQAECn8iAAMKAAkKGRx/ZAC1AgAKAAkKGRx/ZAC1AgAbAAEK/wNQUAAnAAAAAA==.',
Sp='Spicebreff:BAAANQAECgEIAQABNQAECggIHQAWAKEXAA==.',
St='Steck:BAABNQAECn8cAAIIAAcKHhG8lwA+AQAIAAcKHhG8lwA+AQAAAA==.Strigg:BAAANQADCgMIAwABNQAECgEIAQAHAAAAAA==.Strigöi:BAAANQAECgEIAQAAAA==.',
Su='Suprahunts:BAABNQAECn8dAAMIAAcKcCLRUgB4AgAIAAcKcCLRUgB4AgAJAAQKeA3tVQDOAAAAAA==.',
['Sà']='Sàlís:BAAANQADCgcIEAAAAA==.',
Ta='Talander:BAAANQADCgUIBQABNQAFFAIIAgAHAAAAAA==.Talas:BAABNQAECn87AAMIAAoKEBt3MQDYAgAIAAoKEBt3MQDYAgAJAAYK1w+JRQAtAQAAAA==.',
Te='Teaka:BAAANQAECgEIAQAAAA==.Temberle:BAAANQAECgQIBAABNQAECggIFgAQAPMMAA==.',
Th='Thaeker:BAAANQADCggIDgAAAA==.Thaelink:BAAANQAECgEIAQABNQAECgkJIAAKAE8XAA==.Thickthighs:BAAANQAECgYICwABNQAFFAIIAgAHAAAAAA==.Thorss:BAAANQAECgcIDwAAAA==.Thrann:BAABNQAECn86AAIZAAoKkyauAACEAwAZAAoKkyauAACEAwAAAA==.',
Ti='Tirium:BAABNQAECn8dAAIWAAgKoRfenADUAQAWAAgKoRfenADUAQAAAA==.',
To='Tolkien:BAABNQAECn8mAAIYAAgK2RD1LwCuAQAYAAgK2RD1LwCuAQAAAA==.',
Tu='Tubbytotem:BAAANQADCgYICgAAAA==.',
Un='Unduril:BAAANQADCgYIBgAAAA==.',
Ur='Ursae:BAAANQADCgIIAgAAAA==.',
Va='Vanargandr:BAAANQADCgYIBgAAAA==.Vartlek:BAAANQADCgYIBQAAAA==.',
Ve='Velarys:BAAANQABCgIIAgABNQAECgoKNwASAA4gAA==.Velinlock:BAAANQABCgEIAQAAAA==.Velinthil:BAAANQADCgcIBwAAAA==.Verðandi:BAAANQADCgMJAwAAAA==.',
Vi='Vigilante:BAAANQAECgUIBQAAAA==.Vitrois:BAAANQADCgEIAQABNQAECgoKIwAZANIYAA==.',
Vo='Voidraven:BAAANQAECgMIBQAAAA==.Volvox:BAAANQADCggICwAAAA==.',
Vy='Vyxenn:BAABNQAECn9IAAMcAAoKJBsaIwB5AgAcAAoKJBsaIwB5AgADAAIK1wbXFwFfAAAAAA==.',
Wa='Wanders:BAAANQAECgQIAQABNQAECgQIBAAHAAAAAA==.Washim:BAAANQADCggICQAAAA==.',
Wo='Wonkybits:BAAANQAECgQIBAAAAA==.',
Wu='Wurm:BAAANQADCgQIBAABNQAECggIEgAHAAAAAA==.',
Ye='Yejena:BAAANQAECggIDQAAAA==.',
Ym='Ymir:BAAANQAECgEIAQAAAA==.',
Za='Zaleras:BAAANQAECgEIAQAAAA==.',
Ze='Zerkium:BAAANQAECgcIEgAAAA==.',
Zi='Zillaamiri:BAABNQAECn8UAAIlAAgKIgIaIQDWAAAlAAgKIgIaIQDWAAAAAA==.',
Zu='Zugzugdaboo:BAAANQADCggJFgAAAA==.',
Zy='Zyrinx:BAAANQABCgIIAgAAAA==.Zywol:BAABNQAECn9IAAMQAAoKvhisGAAWAgAQAAoKvhisGAAWAgATAAgKSw2TJwBoAQAAAA==.',
['Ër']='Ëresta:BAAANQADCgYIEwABNQAECgkJNAAIAB4eAA==.',
['Ðe']='Ðespair:BAABNQAECn8gAAMLAAoK9h1bTABAAgALAAcKgRxbTABAAgAdAAgKNRqmGgCHAQAAAA==.',
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
