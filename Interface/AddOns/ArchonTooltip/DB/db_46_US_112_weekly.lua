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

local lookup = {'Unknown-Unknown','Warrior-Fury','Druid-Balance','Druid-Restoration','Evoker-Devastation','Warlock-Destruction','DeathKnight-Unholy','Warrior-Protection','Shaman-Restoration','Monk-Brewmaster','DeathKnight-Frost','Hunter-BeastMastery','Warlock-Demonology','Paladin-Retribution','Mage-Frost','Priest-Holy','Warlock-Affliction','Rogue-Subtlety','Paladin-Protection','Shaman-Elemental','Shaman-Enhancement','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Hunter-Marksmanship','Monk-Windwalker','DeathKnight-Blood','Evoker-Augmentation','Druid-Feral','Druid-Guardian','Paladin-Holy','Priest-Discipline','Priest-Shadow','Mage-Arcane','Warrior-Arms','Rogue-Assassination','Evoker-Preservation','Monk-Mistweaver',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=46,date='2026-05-23',data={Ae='Aernoth:BAAALgAECgUJDQAAAA==.',
Ak='Akaidia:BAAALgAECgYJBgABLgAECgYJCwABAAAAAA==.',
Al='Alderan:BAABLgAECn8lAAICAAcJIg41OABAAQACAAcJIg41OABAAQAAAA==.Aleinas:BAABLgAECn8kAAMDAAcJKxb0KgBNAQADAAcJKxb0KgBNAQAEAAQJQQjfhwCFAAAAAA==.Alektophobia:BAAALgAECgcJDAAAAA==.Alendra:BAAALgAECgEJAQAAAA==.Alluisice:BAAALgAECgYJBgAAAA==.Allysaun:BAAALgAECgIJAwAAAA==.Alpharoach:BAAALgADCgYJBgAAAA==.Alzeinrich:BAAALgAECgYJDAAAAA==.',
Am='Amorina:BAAALgAECggJEwAAAA==.',
An='Anda:BAAALgADCgYJBgAAAA==.Andarnn:BAAALgAECgEJAQAAAA==.Andracca:BAABLgAECn8aAAIFAAYJTwxgDgAGAQAFAAYJTwxgDgAGAQAAAA==.Andromeda:BAAALgAECgYJEwAAAA==.Aner:BAAALgAECgEJBQAAAA==.Angrygnome:BAABLgAECn8dAAIGAAkJVSBHAQC9AgAGAAkJVSBHAQC9AgAAAA==.Angélique:BAAALgAFFAEJAQABLgAFFAUJFAAHANkiAA==.Antcension:BAAALgADCgUJBQAAAA==.Antemental:BAAALgAECgYJEAAAAA==.Anthigos:BAAALgAECgMJAwAAAA==.',
Ar='Arax:BAABLgAECn8dAAIIAAcJ7yFICwAVAgAIAAcJ7yFICwAVAgAAAA==.Arcada:BAAALgAECgUJBQABLgAECgUJBQABAAAAAA==.Arcamoon:BAAALgAECgIJAgABLgAECgUJBQABAAAAAA==.Arcashi:BAAALgADCgcJCgABLgAECgUJBQABAAAAAA==.Arianlion:BAAALgAECgEJAgAAAA==.Armistice:BAAALgAECgEJAgAAAA==.Arowenn:BAAALgADCgMJAwAAAA==.Arrokoth:BAAALgAECgEJAQAAAA==.Artana:BAAALgAECgIJAgAAAA==.',
As='Astolvik:BAAALgAECgQJBgAAAA==.',
At='Attachedplag:BAAALgAECgYJEAAAAA==.Atulwa:BAABLgAECn8hAAIJAAkJdRaJIgASAgAJAAkJdRaJIgASAgAAAA==.',
Au='Aurinox:BAAALgAECgUJDgAAAA==.Autodrive:BAAALgAECgUJCAAAAA==.',
Av='Avralea:BAABLgAECn8+AAIKAAgJ8BuFEAAYAgAKAAgJ8BuFEAAYAgAAAA==.',
Az='Azenthal:BAAALgAECgEJAQAAAA==.',
Ba='Bananahammik:BAAALgAECgYJDgAAAA==.Banzen:BAAALgAECgUJDwAAAA==.Basz:BAABLgAECn8iAAMHAAgJfBkgPgDnAQAHAAgJfBkgPgDnAQALAAMJDBASGwCqAAAAAA==.',
Be='Beefburglar:BAAALgAECgYJBgAAAA==.Beginagain:BAAALgADCgcJCQAAAA==.Belgran:BAABLgAECn8WAAILAAkJUxrSAwA9AgALAAkJUxrSAwA9AgAAAA==.Belris:BAAALgADCgYJBgAAAA==.Berunma:BAABLgAECn8YAAIMAAgJ2BA3YABZAQAMAAgJ2BA3YABZAQAAAA==.',
Bh='Bhain:BAABLgAECn8hAAMNAAcJ5R3lSgDpAQANAAcJ5R3lSgDpAQAGAAEJaA2FdAAwAAABLgAFFAQJCgAOAGIRAA==.',
Bi='Bileshots:BAAALgAECggJDwAAAA==.Biowolf:BAACLgAFFH8RAAIPAAQJmQe/VgAWAQAPAAQJmQe/VgAWAQAuAAQKfywAAg8ACQneFK43AB0CAA8ACQneFK43AB0CAAAA.Birdhunter:BAAALgAECggJEgAAAA==.Bishopixixix:BAAALgAECgYJCwAAAA==.Bits:BAABLgAECn8aAAINAAcJ0gZEkwD/AAANAAcJ0gZEkwD/AAAAAA==.',
Bj='Bjoren:BAABLgAECn8uAAIQAAkJGyQeAgBxAwAQAAkJGyQeAgBxAwAAAA==.',
Bl='Blackdread:BAAALgADCgYJBgAAAA==.Blasterjenny:BAAALgADCgcJBwAAAA==.Bloodcaptain:BAABLgAECn8cAAMGAAkJORfoBAD8AQAGAAkJZBboBAD8AQARAAYJshf6CAC3AQAAAA==.',
Bo='Bohma:BAAALgADCgEJAQAAAA==.Bootiebang:BAABLgAECn8VAAISAAYJCQP9NwC5AAASAAYJCQP9NwC5AAAAAA==.Bootycaall:BAAALgADCgkJGwAAAA==.Bootycall:BAAALgADCgkJCQAAAA==.Boroth:BAAALgADCgcJBwAAAA==.',
Br='Breetech:BAAALgAECgIJAgAAAA==.Brett:BAAALgAECgEJAQAAAA==.Breé:BAAALgAECgEJAQAAAA==.Brianx:BAAALgADCgIJAgAAAA==.Brklyn:BAAALgAFFAEJAQAAAA==.Brokki:BAAALgADCgEJAQAAAA==.',
Bu='Buckaroo:BAAALgAECgQJBQAAAA==.Bucknekkid:BAAALgAECgYJEAAAAA==.Buckwhild:BAABLgAECn8VAAIQAAcJoyEFCwCPAgAQAAcJoyEFCwCPAgAAAA==.Burrhus:BAAALgAECgQJBAAAAA==.',
Ca='Cagomei:BAAALgADCggJDgAAAA==.Caladbolg:BAABLgAECn8wAAMTAAgJOyGfBACLAgATAAgJOyGfBACLAgAOAAEJkAP5VwEnAAAAAA==.Camrillem:BAAALgAFFAEJAQAAAA==.Cannacola:BAABLgAECn8kAAMUAAYJvB+AIwCdAQAVAAYJ1BzoDQDeAQAUAAYJOh6AIwCdAQAAAA==.Carebearr:BAAALgADCgcJCgAAAA==.',
Ce='Cearius:BAAALgAECgYJCgABLgAFFAMJEAANAGQlAA==.Cesàrè:BAAALgAECgYJEAAAAA==.',
Ch='Chahra:BAABLgAECn8XAAIWAAYJ2g/fEgDzAAAWAAYJ2g/fEgDzAAAAAA==.Chammie:BAAALgAECgYJBgAAAA==.Chamuki:BAABLgAECn8VAAMXAAYJwBgQHQBWAQAXAAUJXx0QHQBWAQAYAAUJtg1UnwC4AAABLgAFFAQJDgAEAMceAA==.Cheesecake:BAACLgAFFH8UAAMHAAUJ2SLfJwB6AQAHAAUJ2SLfJwB6AQALAAIJ9A8AAAAAAAAuAAQKfyEAAwcACQlfJcQCAK4DAAcACQlfJcQCAK4DAAsAAQkAAPQyAAAAAAAA.Cheesuspiece:BAAALgADCgIJAgAAAA==.Chrispbacon:BAAALgAECgMJBAAAAA==.Chuubak:BAAALgAECgkJBQAAAA==.',
Cl='Clangedin:BAAALgAECgYJEAAAAA==.',
Co='Cobalt:BAAALgADCgUJBQABLgAECgkJIAANAD4cAA==.Coreydruid:BAAALgAECgMJBwAAAA==.Coreypala:BAAALgAECgIJBAAAAA==.Coreysham:BAAALgAECgQJBQAAAA==.Corily:BAAALgADCgcJFwAAAA==.Corsten:BAAALgAECgcJEQAAAA==.Cosmictonic:BAAALgADCgYJBgAAAA==.',
Cr='Crabpack:BAAALgADCgIJAgAAAA==.Crayoneater:BAAALgAECgQJBAAAAA==.Crippleswagg:BAAALgAECgYJAQAAAA==.Croisades:BAAALgAECgQJCgAAAA==.Crosis:BAAALgADCgcJFwAAAA==.Crowmatic:BAABLgAECn8ZAAIHAAkJlR6gHwBpAgAHAAkJlR6gHwBpAgAAAA==.Crusadan:BAAALgADCgYJBgAAAA==.Cryo:BAAALgAECgEJAQAAAA==.',
Cu='Cucklizard:BAAALgAECgEJAQAAAA==.Cute:BAABLgAFFH8JAAICAAMJ+R2PHgAPAQACAAMJ+R2PHgAPAQAAAA==.',
['Cà']='Càhos:BAAALgADCgUJBQAAAA==.',
Da='Dakon:BAABLgAECn83AAMTAAkJThpsBwA5AgATAAkJThpsBwA5AgAOAAIJcBi7DAF9AAAAAA==.Dalune:BAABLgAECn8fAAIUAAgJmAf4PQAMAQAUAAgJmAf4PQAMAQAAAA==.Daneaus:BAABLgAECn8kAAIEAAgJJyK2CQABAwAEAAgJJyK2CQABAwAAAA==.Daniellson:BAACLgAFFH8FAAIZAAMJrQzWGADiAAAZAAMJrQzWGADiAAAuAAQKfxgABBoACAkoEesvALUBABoACAkoEesvALUBABkAAQk+EPZSADsAAAwAAQkAAFrcABcAAAEuAAUUBgkSABsAHCQA.Daredevil:BAAALgAECgYJBgABLgAECggJFwAHALYcAA==.Darkchronos:BAAALgADCgcJEAAAAA==.Darkscorp:BAAALgADCgkJDgAAAA==.Darkwolf:BAABLgAECn8yAAMHAAgJuhXdPgDkAQAHAAgJuhXdPgDkAQAcAAgJlwX0KgDQAAAAAA==.Darnuus:BAAALgAECgQJCwABLgAECggJFAAdABcHAA==.Datromandude:BAAALgAECgEJAQAAAA==.',
Db='Dblaster:BAAALgAECgUJCwAAAA==.',
De='Deathbydruid:BAABLgAECn8cAAMEAAkJqAJsjAB6AAAEAAgJBQJsjAB6AAADAAYJ1QDvagBJAAAAAA==.Deathnelf:BAABLgAECn8VAAMLAAYJHw1RFgDbAAALAAYJHw1RFgDbAAAHAAYJYQX5ygDCAAAAAA==.Deazraelle:BAAALgAECgYJEQAAAA==.Decimator:BAAALgADCggJHAAAAA==.Declan:BAAALgADCgUJBQAAAA==.Dedric:BAABLgAECn8nAAQeAAgJ8wpQGgAAAQAeAAgJGwhQGgAAAQADAAgJKgRYQQDVAAAfAAEJNRdrTABBAAAAAA==.Dellin:BAABLgAECn8iAAIDAAgJrxTSJAB2AQADAAgJrxTSJAB2AQAAAA==.Demeco:BAEALgAECgcJDgABLgAFFAgJGQAgAJwcAA==.Demonch:BAAALgAECgUJCAAAAA==.Demonweasel:BAAALgAECgEJAQAAAA==.Depeche:BAABLgAECn8cAAIYAAYJ8BAehQDtAAAYAAYJ8BAehQDtAAAAAA==.Deralle:BAABLgAECn8UAAIdAAgJFwdjOQAfAQAdAAgJFwdjOQAfAQAAAA==.',
Di='Diminuendo:BAAALgAECgYJDgAAAA==.',
Do='Donalda:BAAALgAECgEJAQAAAA==.Dorillion:BAAALgAECgUJCQAAAA==.Dorozh:BAABLgAECn8ZAAIGAAgJlRJ7CQCBAQAGAAgJlRJ7CQCBAQAAAA==.',
Dr='Draconx:BAAALgADCgYJBgAAAA==.Draghr:BAAALgAECgQJBAAAAA==.Dragonzmage:BAAALgADCgYJBgAAAA==.Dragskar:BAAALgADCgUJBQAAAA==.Drala:BAABLgAECn8cAAMhAAkJBBA3FgD3AQAhAAkJBBA3FgD3AQAQAAEJ2w77ggAuAAAAAA==.Dreadmage:BAAALgADCgUJBQABLgADCgUJCQABAAAAAA==.Dreadpally:BAAALgADCgEJAQABLgADCgUJCQABAAAAAA==.Dreco:BAAALgADCgcJBwAAAA==.Driver:BAEALgAFFAIJBAABLgAFFAQJCgANANAMAA==.Dryconias:BAACLgAFFH8IAAIOAAMJvBYaRgD2AAAOAAMJvBYaRgD2AAAuAAQKfykAAg4ACQkZG9glAEsCAA4ACQkZG9glAEsCAAAA.Drèadpriest:BAABLgAECn8VAAQhAAUJwR19HgCrAQAhAAUJux19HgCrAQAQAAUJ0hQEOgDsAAAiAAIJCRMGUQCJAAAAAA==.Drôgô:BAABLgAECn8VAAIMAAYJnhM7TgB+AQAMAAYJnhM7TgB+AQABLgAECggJCAABAAAAAA==.',
Du='Dunkelzhan:BAABLgAECn9AAAIPAAkJEhtKIQB9AgAPAAkJEhtKIQB9AgAAAA==.Duntack:BAAALgADCgEJAgAAAA==.',
Dy='Dyana:BAABLgAECn8ZAAIMAAgJTBOGPQC/AQAMAAgJTBOGPQC/AQAAAA==.',
Dz='Dz:BAABLgAECn8+AAMgAAkJpyWHAADGAwAgAAkJpyWHAADGAwAOAAQJLQ5WzADTAAAAAA==.',
['Dø']='Dømimømmÿ:BAAALgAECgUJCAAAAA==.',
Ed='Edgyname:BAAALgAECgYJEgAAAA==.Edgyvoid:BAAALgADCgYJDAAAAA==.Edlund:BAABLgAECn8iAAIFAAgJnA3CCAB+AQAFAAgJnA3CCAB+AQAAAA==.',
Ef='Effyinzpjake:BAAALgAECgYJDgAAAA==.',
Ei='Eianistic:BAAALgADCgEJAQAAAA==.',
El='Ellenee:BAAALgADCgMJAwAAAA==.Ellinor:BAAALgADCgYJHgAAAA==.Elvy:BAABLgAECn8sAAIDAAkJ8xZLHQCwAQADAAkJ8xZLHQCwAQAAAA==.',
En='Enngin:BAAALgAFFAMJAwAAAA==.',
Er='Erebus:BAAALgAECgYJDAAAAA==.Erythra:BAAALgAECgMJAwAAAA==.',
Ev='Evildefiant:BAAALgAECgEJAQAAAA==.',
Ex='Exsalsior:BAAALgADCgYJBgAAAA==.',
Ey='Eyedoc:BAAALgADCgQJBAAAAA==.',
Fa='Fabulousness:BAABLgAECn8hAAIQAAgJ+R+9CAC6AgAQAAgJ+R+9CAC6AgAAAA==.',
Fe='Fearliz:BAAALgADCgEJAQAAAA==.',
Fi='Fifefrost:BAAALgADCgMJAwAAAA==.Fishingsucks:BAAALgAECgcJCgAAAA==.',
Fl='Flexi:BAAALgADCgEJAQAAAA==.Flitred:BAAALgAECggJDwAAAA==.Flock:BAAALgAECgUJBQAAAA==.',
Fo='Foxx:BAAALgAECgUJDQAAAA==.',
Fr='Framboise:BAABLgAECn8ZAAICAAYJUQcaYAAwAQACAAYJUQcaYAAwAQAAAA==.Frostybolt:BAAALgAECgEJAgAAAA==.',
Fu='Furryriver:BAAALgAECgYJDgAAAA==.',
['Fø']='Føxx:BAAALgAECgEJAQAAAA==.',
Ga='Galadhras:BAAALgADCgYJFAAAAA==.Galdryn:BAAALgADCgIJAQAAAA==.Galianna:BAAALgAECgcJEQAAAA==.Garkevon:BAAALgADCgMJAwAAAA==.',
Ge='Gemeni:BAAALgAECgEJAQAAAA==.Gevul:BAABLgAECn89AAMNAAgJCBf0NQDpAQANAAgJCBf0NQDpAQAGAAQJuAhyRgCcAAAAAA==.',
Gh='Ghostess:BAAALgADCgkJAQAAAA==.Ghrank:BAAALgAECgcJDwAAAA==.',
Gi='Gilliruni:BAAALgADCgUJBQAAAA==.Gitpull:BAAALgAECggJDQAAAA==.',
Gl='Glimley:BAAALgADCgMJAwAAAA==.',
Gn='Gnimsh:BAAALgAECgEJAQAAAA==.Gnorst:BAAALgADCgkJCgAAAA==.',
Go='Goreolio:BAAALgADCgkJDwABLgAECgYJEQABAAAAAA==.',
Gr='Grandmatank:BAAALgADCgkJCQAAAA==.Grasshopaa:BAAALgADCgYJCQAAAA==.Grassy:BAAALgADCgkJCQAAAA==.Greengoatlin:BAAALgADCgcJBwAAAA==.Gremlock:BAAALgAECgEJAQAAAA==.Gremz:BAABLgAECn8mAAIWAAkJCQobDQBUAQAWAAkJCQobDQBUAQAAAA==.Grozny:BAAALgADCgYJBgAAAA==.Grày:BAABLgAECn8wAAIHAAkJXx1tGACSAgAHAAkJXx1tGACSAgAAAA==.',
Gu='Gumboslice:BAACLgAFFH8GAAIEAAQJugx7LQDdAAAEAAQJugx7LQDdAAAuAAQKfx0AAgQACQlNHMsLAOUCAAQACQlNHMsLAOUCAAAA.Gusgus:BAAALgAECggJEAAAAA==.',
['Gä']='Gändälf:BAABLgAECn8XAAIjAAgJvxWSAwC8AQAjAAgJvxWSAwC8AQAAAA==.',
Ha='Habanero:BAABLgAECn8iAAMJAAgJIw11RgBhAQAJAAgJIw11RgBhAQAUAAQJUxjuPwADAQAAAA==.Hachedev:BAAALgAECgMJCAAAAA==.Hadtopandadk:BAAALgAECgEJAgAAAA==.Hallia:BAACLgAFFH8GAAIEAAMJ9BHvMADMAAAEAAMJ9BHvMADMAAAuAAQKfzUAAgQACQkBF+EWAG4CAAQACQkBF+EWAG4CAAAA.Hark:BAAALgADCgYJGgAAAA==.Hawgwild:BAAALgAECgQJEQAAAA==.',
He='Headdinks:BAAALgADCgcJDAAAAA==.Healvisprsly:BAABLgAECn8VAAMDAAcJ9BhlHwCfAQADAAYJ9BhlHwCfAQAEAAUJVRmPQQBoAQAAAA==.Heisenberg:BAAALgADCgMJAwABLgAECgMJBwABAAAAAA==.Helena:BAABLgAECn9AAAMOAAkJWSOiBQAwAwAOAAkJViOiBQAwAwATAAkJUB7RAwCmAgAAAA==.Heliarc:BAAALgADCgYJHgAAAA==.Hermès:BAAALgAECgUJBgABLgAFFAUJFAAHANkiAA==.',
Hi='Highfive:BAAALgAECgUJCwAAAA==.',
Ho='Holybeech:BAAALgAECgQJBAAAAA==.Honestly:BAAALgAECgYJCQAAAA==.Honkytonkman:BAAALgADCgQJBAAAAA==.Hover:BAAALgAECgYJEQAAAA==.',
Ih='Ihmoen:BAAALgADCgYJBgAAAA==.',
Il='Illuminate:BAAALgADCgQJBAAAAA==.Illustria:BAAALgADCgYJFQAAAA==.Illustriâ:BAAALgADCgYJCQABLgADCgYJFQABAAAAAA==.',
Im='Imprison:BAAALgAECgYJBgABLgAECgcJFQAPANIXAA==.',
In='Insidious:BAABLgAECn8fAAIcAAkJFRqZCwAlAgAcAAkJFRqZCwAlAgAAAA==.Invoke:BAAALgADCgEJAQAAAA==.',
Ir='Irs:BAAALgAECgUJBwAAAA==.',
It='Itchyfeet:BAAALgAECgUJCAABLgAFFAQJDwAPANIgAA==.Itchymage:BAACLgAFFH8PAAIPAAQJ0iCTKACBAQAPAAQJ0iCTKACBAQAuAAQKfyIAAg8ACAl4JDMdAAEDAA8ACAl4JDMdAAEDAAAA.',
Ja='Jacckiemoon:BAAALgAECgMJAwABLgAECgcJFQADAPQYAA==.Jadehunterr:BAAALgAECgMJBAAAAA==.Jaesn:BAAALgADCgYJBgAAAA==.',
Je='Jenae:BAAALgAECgEJAQAAAA==.Jenövha:BAAALgADCgkJFwAAAA==.Jezebelle:BAAALgAECgUJBQAAAA==.',
Ji='Jigs:BAABLgAECn8yAAIMAAgJEhVgOQDOAQAMAAgJEhVgOQDOAQAAAA==.Jiräiya:BAAALgADCgYJBgAAAA==.',
Jo='Johastrasz:BAAALgADCggJCAAAAA==.',
Ju='Junsing:BAAALgADCgEJAQABLgAECggJFAAdABcHAA==.',
['Jå']='Jåfar:BAAALgADCgEJAgAAAA==.',
Ka='Kabøchi:BAAALgAECgUJBQAAAA==.Kaladriel:BAAALgADCgEJAQAAAA==.Kaldrick:BAAALgAECgUJCgAAAA==.Kamstareater:BAABLgAECn8eAAIYAAgJDhJVSACLAQAYAAgJDhJVSACLAQAAAA==.Kanakas:BAAALgAECgcJEQAAAA==.Kanaloa:BAABLgAECn8bAAIPAAcJfwe6pwAUAQAPAAcJfwe6pwAUAQAAAA==.Kayler:BAAALgAECgYJBgABLgAECgYJCwABAAAAAA==.',
Ke='Kegerator:BAAALgAECgEJAQAAAA==.Keirin:BAAALgAECggJEgAAAA==.Keldica:BAAALgAECgIJAgAAAA==.Kelysa:BAAALgAECggJDwAAAA==.Kena:BAAALgADCgUJBQAAAA==.Kenshan:BAAALgADCgcJEAAAAA==.Kevinbox:BAAALgAECgYJEAAAAA==.Kevinslayer:BAAALgAECgUJDAAAAA==.Keynaridan:BAABLgAECn8VAAIYAAgJYRFhTQB7AQAYAAgJYRFhTQB7AQAAAA==.Keyss:BAAALgADCgIJAgAAAA==.',
Kg='Kglizard:BAAALgAECgUJCAAAAA==.',
Kh='Khalinor:BAABLgAECn8cAAIgAAgJLhKkIwDCAQAgAAgJLhKkIwDCAQAAAA==.Khardun:BAAALgAECgEJAQAAAA==.Khotuhn:BAAALgADCgkJGAAAAA==.',
Ki='Kickazdin:BAABLgAECn8WAAMgAAkJWh01DACnAgAgAAgJLx41DACnAgAOAAEJUAc+WwE0AAAAAA==.Kiryie:BAABLgAECn8XAAIMAAYJhw0feAAgAQAMAAYJhw0feAAgAQAAAA==.Kisäme:BAAALgAECgUJBgAAAA==.',
Kl='Klad:BAAALgAECgEJAQAAAA==.Kluma:BAAALgAECgEJAQAAAA==.',
Kn='Knok:BAAALgAECggJCAAAAA==.',
Ko='Kobu:BAAALgADCgUJBgAAAA==.Konran:BAAALgADCgEJAQAAAA==.',
Kr='Kraigen:BAABLgAECn8iAAIXAAgJQhwvDQAdAgAXAAgJQhwvDQAdAgAAAA==.Krinack:BAABLgAECn8fAAISAAkJlBFlEgDvAQASAAkJlBFlEgDvAQAAAA==.Krixiz:BAAALgAECgYJCgAAAA==.',
Ks='Kshamify:BAAALgAECgcJCwAAAA==.',
Ku='Kurindrixx:BAAALgADCgIJAgAAAA==.Kurtakum:BAAALgADCgMJAwAAAA==.Kutiel:BAAALgAECgYJDQAAAA==.',
Kw='Kwarify:BAAALgADCgEJAQAAAA==.',
Ky='Kynasmira:BAAALgADCgYJFgAAAA==.Kyrsh:BAAALgADCgcJEAAAAA==.',
La='Ladrona:BAAALgAECggJEwAAAA==.Lailyre:BAAALgAECgYJCwAAAA==.Lassan:BAAALgAECgYJCQAAAA==.Later:BAAALgAECggJDAAAAA==.Latimir:BAAALgAECgIJAgAAAA==.Laur:BAAALgADCgYJBgAAAA==.Lavendeer:BAABLgAECn8gAAIDAAgJYhANKQBZAQADAAgJYhANKQBZAQAAAA==.Laylana:BAAALgADCgIJAgABLgADCgUJCQABAAAAAA==.Lazyeye:BAAALgADCgUJBAABLgAECgYJDAABAAAAAA==.',
Lb='Lb:BAAALgADCgUJBgABLgAECgkJCgABAAAAAA==.',
Le='Legume:BAAALgADCgcJCAABLgAECgUJDQABAAAAAA==.Legzanot:BAACLgAFFH8PAAIUAAQJ6Qj+IgDjAAAUAAQJ6Qj+IgDjAAAuAAQKfygAAhQACQkyFiQdACgCABQACQkyFiQdACgCAAAA.Leonceault:BAAALgAECgEJAQAAAA==.',
Li='Lifebringa:BAABLgAECn8iAAMQAAcJ/x3MDQBiAgAQAAcJ/x3MDQBiAgAiAAQJDBGITACtAAAAAA==.Lightningfox:BAABLgAECn8cAAMOAAgJ5hXtSADMAQAOAAgJ5hXtSADMAQAgAAIJug7dZgBnAAAAAA==.Lightsfallen:BAAALgAECgcJCQAAAA==.Lileth:BAAALgAECgYJBAAAAA==.Limzzmagus:BAAALgAECgMJBgAAAA==.Lithia:BAABLgAECn8XAAIHAAYJNBHKkAAeAQAHAAYJNBHKkAAeAQAAAA==.Littlemo:BAAALgAECgYJDgAAAA==.',
Lo='Loggs:BAAALgAFFAEJAQAAAA==.Lohnar:BAAALgAECgYJDgAAAA==.',
Lu='Lucidslock:BAAALgADCgIJAgAAAA==.Lucielbaal:BAABLgAECn8kAAINAAgJYhtKJAA0AgANAAgJYhtKJAA0AgAAAA==.Luciferus:BAAALgAECgQJBAABLgAECggJLAAZAPwOAA==.Luckystop:BAAALgAECgUJCQAAAA==.Lumenir:BAAALgAECgEJAQAAAA==.Lunareth:BAAALgADCgUJBQAAAA==.Luraris:BAAALgAECgEJAQAAAA==.',
Ly='Lyrska:BAABLgAECn8gAAIZAAYJaBEHJwBEAQAZAAYJaBEHJwBEAQAAAA==.Lytearrow:BAABLgAECn8iAAIMAAgJEg/hTwCFAQAMAAgJEg/hTwCFAQAAAA==.',
['Lé']='Léaf:BAAALgAECgMJAwAAAA==.',
Ma='Mahrylee:BAAALgAECgcJEAAAAA==.Maiya:BAAALgADCgcJEAAAAA==.Majutsu:BAAALgADCgEJAQABLgADCgcJDgABAAAAAA==.Malbrax:BAABLgAECn8YAAINAAgJQhDwUACRAQANAAgJQhDwUACRAQAAAA==.Maleficents:BAABLgAECn8lAAIDAAYJ/Q/zOgD0AAADAAYJ/Q/zOgD0AAAAAA==.Malurius:BAABLgAECn8bAAMkAAkJshRdDAD6AQAkAAkJsRJdDAD6AQACAAYJ4Aq4VgDGAAAAAA==.Malware:BAAALgAECgYJEQAAAA==.Manana:BAAALgADCgEJAQAAAA==.Manbearpally:BAAALgAECgQJBAAAAA==.Manikfury:BAABLgAECn8iAAMeAAgJwBtSBwAyAgAeAAgJwBtSBwAyAgAEAAYJYx58JwDyAQAAAA==.Maniksmage:BAAALgADCgUJDAABLgAECggJIgAeAMAbAA==.Mannypack:BAABLgAECn8YAAMDAAgJDR+8FgDvAQADAAcJ+R28FgDvAQAEAAQJkAy8dAC3AAAAAA==.Maranelli:BAAALgADCgYJBgAAAA==.Maseles:BAAALgAECgUJBgABLgAECgUJCQABAAAAAA==.Maxiticon:BAAALgAECgUJBgAAAA==.',
Mc='Mcdawg:BAAALgADCgYJCgAAAA==.Mcleary:BAAALgAECgUJBgAAAA==.',
Me='Melinashala:BAABLgAECn8jAAINAAgJ+gPkkQACAQANAAgJ+gPkkQACAQAAAA==.Mending:BAAALgAECgUJBQAAAA==.Meowinator:BAAALgAECgUJCgAAAA==.Mephizto:BAAALgAECgUJBQAAAA==.Metatrøn:BAAALgAECgIJAgAAAA==.Metide:BAAALgAECgQJBAAAAA==.',
Mi='Miala:BAAALgADCgYJBgAAAA==.Mierna:BAAALgAECggJCAAAAA==.Miler:BAAALgAECgQJBgAAAA==.Minisor:BAAALgAECgUJBQAAAA==.Misanth:BAAALgAECgYJDgAAAA==.Mistdruid:BAAALgAECgIJAwABLgAECgIJBgABAAAAAA==.',
Mo='Moemo:BAABLgAECn8cAAIEAAkJQh/hCAAOAwAEAAkJQh/hCAAOAwAAAA==.Mogryn:BAAALgAECggJDQAAAA==.Moistymists:BAAALgAECgYJCQAAAA==.Moll:BAAALgADCgEJAQAAAA==.Mommybree:BAAALgAECgYJDAAAAA==.Monksterz:BAABLgAECn8uAAIKAAkJzyB9BADlAgAKAAkJzyB9BADlAgAAAA==.Monoxidê:BAAALgAECgEJAQAAAA==.Moonwarriorx:BAAALgAECgQJBAAAAA==.Morsecode:BAABLgAECn8YAAIGAAcJNhMICwBjAQAGAAcJNhMICwBjAQABLgABCgIJAgABAAAAAA==.Morthok:BAABLgAECn8oAAINAAgJbhWAQADDAQANAAgJbhWAQADDAQAAAA==.Mortischa:BAAALgADCggJCAAAAA==.Mosh:BAABLgAECn8XAAIKAAkJHBMfFwDQAQAKAAkJHBMfFwDQAQAAAA==.',
Mu='Muchuchu:BAAALgAECgQJDgABLgAECgEJAQABAAAAAA==.Muldern:BAAALgAECgEJAQAAAA==.Munkee:BAAALgAECgYJEQAAAA==.Murdinbronze:BAAALgADCgUJCAAAAA==.Mustachekick:BAAALgADCgUJBwAAAA==.Musyl:BAAALgADCgEJAQABLgAECgYJEQABAAAAAA==.',
['Mã']='Mãf:BAABLgAECn8gAAMJAAcJmRIYWAAgAQAJAAYJbA8YWAAgAQAUAAEJUBE5hgA0AAAAAA==.',
['Mí']='Místwalker:BAAALgAECgIJBgAAAA==.',
Na='Nackthyr:BAACLgAFFH8TAAIFAAQJ+CV+AADBAQAFAAQJ+CV+AADBAQAuAAQKfzsAAgUACQn+JUEAAG8DAAUACQn+JUEAAG8DAAAA.Nafir:BAAALgADCgYJFwAAAA==.Narlin:BAAALgAECgIJBAAAAA==.Nasta:BAAALgAECgUJCgAAAA==.Natureboi:BAAALgADCgQJBAABLgADCgYJDAABAAAAAA==.Nazareths:BAAALgAECgQJCAAAAA==.Nazgor:BAAALgAECgMJAwAAAA==.',
Ne='Neckromancy:BAAALgADCgcJBwAAAA==.Necrosius:BAAALgAECgYJDQAAAA==.Neonarc:BAEALgADCgYJFwAAAA==.Neshi:BAAALgAECgMJBQAAAA==.Neuman:BAAALgADCgEJAQAAAA==.',
Ni='Nibblemah:BAAALgAECgUJBQAAAA==.Nightsbane:BAAALgADCgcJEAAAAA==.Nivdk:BAAALgADCgYJBgABLgAECgYJEQABAAAAAA==.Nivora:BAAALgAECgYJEQAAAA==.',
No='Notsure:BAAALgAECgkJDAAAAA==.',
Ny='Nyxstalia:BAAALgAECgUJDAAAAA==.Nyyx:BAABLgAECn8cAAIYAAgJqgXEgwDvAAAYAAgJqgXEgwDvAAAAAA==.',
['Ná']='Nácl:BAAALgAECgcJBwABLgAFFAQJEwAFAPglAA==.',
Ob='Obscyra:BAAALgADCgYJEQAAAA==.',
Ol='Olmek:BAACLgAFFH8WAAICAAYJTBdRBwCZAQACAAYJTBdRBwCZAQAuAAQKfxwAAgIABwkrJi0MAIQCAAIABwkrJi0MAIQCAAAA.',
Op='Opalana:BAAALgADCgIJAwAAAA==.Oprahwndfury:BAAALgAECgQJBwABLgAECgcJFQADAPQYAA==.',
Or='Orasaya:BAAALgADCgYJBgAAAA==.Orphee:BAAALgADCgcJBwAAAA==.Orzanis:BAAALgADCgcJDgAAAA==.',
Pa='Paige:BAAALgADCgcJDgAAAA==.Palasades:BAAALgADCgUJBQAAAA==.Pallymarc:BAAALgADCgYJBgAAAA==.Pallytune:BAACLgAFFH8IAAIgAAMJDAxiJwC8AAAgAAMJDAxiJwC8AAAuAAQKfxsAAiAACQnxDhcfAOQBACAACQnxDhcfAOQBAAAA.Pandalorian:BAAALgAECgYJEAAAAA==.Pandamajack:BAAALgAECgcJCwAAAA==.',
Ph='Philandre:BAAALgAECggJDgAAAA==.',
Pi='Picoso:BAABLgAECn8eAAIPAAgJ6gl1eQBoAQAPAAgJ6gl1eQBoAQAAAA==.Piianca:BAAALgADCgcJCgAAAA==.Piianna:BAABLgAECn8ZAAIQAAcJoBu9FQD+AQAQAAcJoBu9FQD+AQAAAA==.Pirko:BAAALgADCggJCwAAAA==.',
Po='Pocketheal:BAAALgADCgkJEAAAAA==.',
Pu='Punch:BAAALgAECgEJAgAAAA==.Purplerain:BAAALgAECgEJAQAAAA==.Putrigord:BAAALgAECgQJCwAAAA==.',
Qi='Qik:BAAALgADCgcJBwAAAA==.Qikkaw:BAABLgAECn8gAAMJAAgJaQ+MRABpAQAJAAgJaQ+MRABpAQAUAAUJtwm+WwCgAAAAAA==.Qitetsu:BAAALgAECgUJBgAAAA==.',
Qu='Quantos:BAABLgAECn8gAAIfAAgJ0hH/EABmAQAfAAgJ0hH/EABmAQAAAA==.Ququmatz:BAAALgADCgMJAwAAAA==.',
Ra='Raatha:BAABLgAECn8YAAIOAAgJdBPaVQCqAQAOAAgJdBPaVQCqAQAAAA==.Raganar:BAABLgAECn8fAAITAAgJyBH+EgBsAQATAAgJyBH+EgBsAQAAAA==.Ranlerodis:BAAALgADCgMJAwAAAA==.Rayjean:BAAALgADCgYJGAAAAA==.',
Re='Redneckboots:BAAALgADCgEJAQAAAA==.Relmax:BAABLgAECn8ZAAIIAAgJ5QazIQD6AAAIAAgJ5QazIQD6AAAAAA==.Rendeminae:BAAALgADCgcJBwAAAA==.Renri:BAABLgAECn8WAAISAAcJbROWHACHAQASAAcJbROWHACHAQAAAA==.Repose:BAAALgAECgIJAwAAAA==.Revick:BAAALgAECgUJCAAAAA==.Revil:BAAALgADCgIJAgAAAA==.',
Rh='Rhaenýs:BAAALgADCgcJDQAAAA==.Rhonwynn:BAABLgAECn8YAAIJAAcJLBvWIQAWAgAJAAcJLBvWIQAWAgAAAA==.',
Ri='Rikershipdwn:BAABLgAECn8YAAIMAAgJGhQqPwC6AQAMAAgJGhQqPwC6AQAAAA==.Rikersline:BAAALgADCgkJCQAAAA==.Rimish:BAAALgAECggJDAABLgAECgkJJAAlALgaAA==.Rimrave:BAABLgAECn8iAAQkAAgJQBuwDQDlAQAkAAgJSxawDQDlAQACAAYJIxscNQDVAQAIAAYJiB3fFAB9AQAAAA==.Ripavicii:BAAALgAECgEJAQAAAA==.Ritobeans:BAAALgADCgYJHgAAAA==.Rivik:BAAALgAECgQJAwAAAA==.',
Ro='Robbstark:BAAALgAECgYJDAAAAA==.Robertkenway:BAABLgAECn8sAAMZAAgJ/A6QGgCsAQAZAAgJ/A6QGgCsAQAMAAEJAADX1AAwAAAAAA==.Roguebot:BAAALgADCgkJEgAAAA==.Rohdaric:BAABLgAECn8ZAAIZAAYJUxTNFgBdAQAZAAYJUxTNFgBdAQAAAA==.Rokte:BAABLgAECn8XAAIRAAYJNRLEDwAsAQARAAYJNRLEDwAsAQAAAA==.Roo:BAAALgAECgEJAgAAAA==.Rook:BAABLgAECn8aAAQNAAgJix/VLwABAgANAAgJnR3VLwABAgAGAAMJmBk3HwCNAAARAAEJAAAdOAAAAAAAAA==.Rosekenway:BAABLgAECn8WAAMEAAcJBQoiVwATAQAEAAcJBQoiVwATAQADAAQJzQiPWQB5AAABLgAECggJLAAZAPwOAA==.',
Rr='Rratt:BAAALgAECgQJBAAAAA==.',
Ru='Rubimoon:BAAALgAECgUJBQAAAA==.Rumí:BAAALgADCgUJCQAAAA==.Running:BAAALgAECgIJAgAAAA==.',
Sa='Saammiee:BAAALgAECgIJAgAAAA==.Sabiha:BAABLgAECn8UAAMMAAYJaA+qZQA2AQAMAAYJaA+qZQA2AQAaAAEJwQPplAAlAAAAAA==.Saintotem:BAABLgAECn8dAAIUAAgJ6Q66LgBZAQAUAAgJ6Q66LgBZAQAAAA==.Samartyr:BAAALgAECgUJCAAAAA==.Sammiiee:BAAALgADCgQJBAABLgAECgIJAgABAAAAAA==.Sandii:BAAALgADCgcJBwAAAA==.Sangwynaris:BAAALgADCgYJCQAAAA==.Saphiiraa:BAABLgAECn8hAAImAAgJaRGnDwCsAQAmAAgJaRGnDwCsAQAAAA==.Sayahealer:BAAALgADCgcJDgAAAA==.',
Sc='Scorpmage:BAABLgAECn8ZAAIPAAcJohPLcwB1AQAPAAcJohPLcwB1AQAAAA==.Scramms:BAAALgADCgcJDQAAAA==.Scrams:BAABLgAECn8VAAIaAAcJpwwbEgATAQAaAAcJpwwbEgATAQAAAA==.',
Se='Sedrick:BAABLgAECn81AAMgAAkJRSAqCQDTAgAgAAgJMiEqCQDTAgAOAAYJzhWdfABUAQAAAA==.Sekendipity:BAAALgADCgEJAQABLgAECgYJDAABAAAAAA==.Sekhmett:BAAALgADCgMJAwAAAA==.Sekndestroy:BAAALgADCgYJCQABLgAECgYJDAABAAAAAA==.Sektacular:BAAALgADCgQJBAABLgAECgYJDAABAAAAAA==.Sekzen:BAAALgAECgYJDAAAAA==.Semiazas:BAABLgAECn8tAAQRAAkJ+Q3tBwC3AQARAAkJ+Q3tBwC3AQANAAUJ2QmotwDpAAAGAAEJAAD7egAnAAAAAA==.Semiazes:BAAALgADCgYJBgAAAA==.Senessa:BAAALgADCgIJAgAAAA==.Sensy:BAAALgAECgQJBgAAAA==.Serwonton:BAAALgADCgUJBQAAAA==.Seumas:BAAALgADCgMJAwAAAA==.',
Sh='Shadrock:BAAALgADCgYJBgAAAA==.Shattered:BAAALgAECgkJEAAAAA==.Shayrisa:BAABLgAECn81AAMJAAkJTBLYMQC9AQAJAAkJTBLYMQC9AQAUAAcJ4w4PPAAVAQAAAA==.Shazool:BAABLgAECn8XAAMJAAYJtyB2IAAfAgAJAAYJtyB2IAAfAgAVAAIJkQsDJgBoAAABLgAFFAMJBgAEAPQRAA==.Sheep:BAABLgAECn8VAAIPAAcJ0hfLYQCfAQAPAAcJ0hfLYQCfAQAAAA==.Shifterz:BAAALgAECgYJDQAAAA==.Shrieke:BAAALgAECgQJBAAAAA==.Shrubbery:BAABLgAECn8ZAAIfAAgJWw9PGgA6AQAfAAgJWw9PGgA6AQAAAA==.Shxdow:BAAALgAECgQJBAAAAA==.',
Si='Sind:BAAALgAECgEJAQABLgAECgkJIgAfABwRAA==.Sindella:BAAALgADCgIJAwABLgAECgkJIgAfABwRAA==.Sinna:BAAALgADCgUJCQAAAA==.Sinthorne:BAABLgAECn8iAAMfAAkJHBGrEwB+AQAfAAgJ/BKrEwB+AQAeAAMJ8AXkLQBpAAAAAA==.',
Sk='Skedaddle:BAAALgAECgUJCQABLgAECggJLgAPABMjAA==.Skithíryx:BAAALgAECgYJCAABLgAECgYJCwABAAAAAA==.',
Sl='Slashbndcoot:BAAALgAECgEJAQAAAA==.Slashgquit:BAACLgAFFH8PAAIcAAQJlB4eDABfAQAcAAQJlB4eDABfAQAuAAQKfzMAAhwACQmIJG8CABIDABwACQmIJG8CABIDAAAA.Slumbermist:BAABLgAECn80AAMbAAkJxhHBFwDMAQAbAAkJxhHBFwDMAQAnAAcJbxGrLQBLAQABLgABCgIJAgABAAAAAA==.',
So='Solaire:BAABLgAECn8eAAMTAAcJChtgDwCgAQATAAcJChtgDwCgAQAgAAUJqRAcRQABAQAAAA==.Soras:BAAALgADCgYJGwAAAA==.',
St='Steph:BAAALgAECgUJBQAAAA==.',
Su='Sunareas:BAAALgADCgIJAgAAAA==.',
Sy='Synthetic:BAABLgAECn8YAAIGAAcJtRNzCwBbAQAGAAcJtRNzCwBbAQAAAA==.',
Sz='Szasstaam:BAABLgAECn8dAAIjAAgJWAccBwASAQAjAAgJWAccBwASAQAAAA==.',
['Sé']='Sénåtor:BAAALgADCgYJCAABLgAECgkJIwAOANAQAA==.Séékér:BAAALgADCgcJFQAAAA==.',
Ta='Talanith:BAAALgADCggJEAAAAA==.Tarayk:BAAALgADCgYJBgABLgADCgYJGAABAAAAAA==.Taxal:BAAALgADCgYJBwAAAA==.Taxlock:BAABLgAECn8aAAINAAcJ9wmshAAbAQANAAcJ9wmshAAbAQAAAA==.',
Tb='Tbagjones:BAAALgAECgQJBAAAAA==.',
Te='Tecsaran:BAABLgAECn8UAAIPAAYJ1B/ebgD2AQAPAAYJ1B/ebgD2AQAAAA==.Tekis:BAAALgADCgEJAQAAAA==.Terania:BAAALgADCgIJAgAAAA==.',
Th='Thalira:BAABLgAECn8XAAQmAAcJjQkFHgDkAAAmAAYJogcFHgDkAAAdAAYJgQJjYQCFAAAFAAQJrQGENQBpAAAAAA==.',
Ti='Tiger:BAACLgAFFH84AAMeAAkJECUBAACwAwAeAAkJECUBAACwAwAEAAMJxhYuFwCoAAAuAAQKfyoAAx4ACQnqJgUAABYEAB4ACQnqJgUAABYEAAQAAQm1C4TEAD8AAAAA.Tinnea:BAAALgAECgUJDgAAAA==.Titanosaurus:BAAALgAECgYJDgAAAA==.Tizzly:BAABLgAECn8rAAIPAAkJzQ5YVgC8AQAPAAkJzQ5YVgC8AQAAAA==.',
To='Torhilda:BAAALgAECgYJBgAAAA==.Torridwells:BAABLgAECn8XAAIMAAYJJQ4BdgAlAQAMAAYJJQ4BdgAlAQAAAA==.',
Tr='Trad:BAAALgADCgYJBgAAAA==.Troag:BAABLgAECn8YAAIJAAcJyxywIQAXAgAJAAcJyxywIQAXAgAAAA==.Troagstar:BAABLgAECn8eAAIUAAcJMBUULQBiAQAUAAcJMBUULQBiAQAAAA==.',
Ts='Tsaesci:BAAALgADCgQJBgAAAA==.Tsynn:BAAALgADCgYJFAAAAA==.',
Ty='Tyraana:BAABLgAECn85AAMXAAkJbh9VBADbAgAXAAkJbh9VBADbAgAYAAgJ3RQ4QACnAQAAAA==.Tyrinwar:BAAALgADCgYJDAAAAA==.Tyrmog:BAABLgAECn8VAAIHAAcJmgbSqAD2AAAHAAcJmgbSqAD2AAAAAA==.Tytus:BAAALgADCgIJAgAAAA==.',
Us='Ushas:BAABLgAECn8tAAMQAAkJCxcTGgDRAQAQAAkJCxcTGgDRAQAhAAQJqQXuSACfAAAAAA==.',
Va='Vali:BAABLgAECn8oAAIaAAgJ0x9vAwBzAgAaAAgJ0x9vAwBzAgAAAA==.Valindrea:BAAALgAECgYJDgAAAA==.Vasrael:BAABLgAECn8oAAMgAAgJIh19GAAcAgAgAAcJYRx9GAAcAgAOAAcJRRufQQDiAQAAAA==.Vav:BAABLgAECn8UAAMMAAYJeBfEggAJAQAMAAYJeBfEggAJAQAZAAIJswwaUgA9AAAAAA==.',
Ve='Vecnis:BAAALgAECgIJAgAAAA==.Veliette:BAAALgAECgUJBwAAAA==.',
Vi='Vithper:BAAALgAECgcJDAAAAA==.',
Vn='Vnia:BAAALgADCgMJAwAAAA==.',
Vo='Voidmuffinz:BAACLgAFFH8IAAIYAAMJ4gz9TgDMAAAYAAMJ4gz9TgDMAAAuAAQKfx8AAhgACQnYFxYtAPQBABgACQnYFxYtAPQBAAAA.',
Vy='Vynis:BAAALgAECgcJDQABLgAFFAMJCAAgAAwMAA==.Vyrahildard:BAABLgAECn8kAAIOAAgJ5BpGNQALAgAOAAgJ5BpGNQALAgAAAA==.',
Wa='Waringoutlaw:BAAALgADCgkJCQAAAA==.Wasteland:BAABLgAECn8pAAIcAAkJphEwFQCUAQAcAAkJphEwFQCUAQAAAA==.',
We='Weaselhunter:BAAALgAECgYJBgABLgAECgcJEwABAAAAAA==.Weasellock:BAAALgAECgcJEwAAAA==.Weaselmage:BAAALgAECgYJDAABLgAECgcJEwABAAAAAA==.Welor:BAAALgADCgYJDAAAAA==.',
Wh='Whatthef:BAAALgAECgYJBwAAAA==.',
Wi='Wildweasel:BAAALgAECgYJCgABLgAECgcJEwABAAAAAA==.Winterhide:BAABLgAECn8oAAIHAAgJhRhmMAAaAgAHAAgJhRhmMAAaAgAAAA==.',
Xa='Xallie:BAECLgAFFH8GAAIYAAMJaQjMUwC9AAAYAAMJaQjMUwC9AAAuAAQKfzoAAhgACQmEF6UhAC4CABgACQmEF6UhAC4CAAAA.Xanvyr:BAABLgAECn8hAAIOAAkJXxlDLgAmAgAOAAkJXxlDLgAmAgAAAA==.Xaquillis:BAACLgAFFH8HAAMHAAMJuQ3JggDPAAAHAAMJuQ3JggDPAAALAAEJrAVBGgBAAAAuAAQKfyIAAwcACAmZGyc8AEcCAAcACAmZGyc8AEcCAAsAAQnZDqUsACwAAAAA.Xarthis:BAAALgAECgEJAQABLgAFFAMJBwAHALkNAA==.',
Xe='Xentrie:BAAALgADCgUJCgAAAA==.Xeyvara:BAABLgAECn8kAAIWAAgJliTkAQDXAgAWAAgJliTkAQDXAgAAAA==.',
Xg='Xg:BAAALgADCgUJBgABLgAECgYJJAAUALwfAA==.',
Ya='Yamiyugi:BAAALgADCgUJBQAAAA==.Yatsui:BAAALgAECgQJBAAAAA==.',
Yo='Youngthug:BAAALgAECgIJAwAAAA==.',
Yu='Yutaa:BAAALgADCgYJBgAAAA==.',
Za='Zaden:BAAALgADCgUJBQAAAA==.Zarihanna:BAABLgAECn8tAAIPAAgJ+hOfZgCTAQAPAAgJ+hOfZgCTAQAAAA==.Zatannah:BAAALgADCgUJBQAAAA==.',
Ze='Zedryn:BAABLgAECn8fAAINAAgJ3g1CWgB5AQANAAgJ3g1CWgB5AQAAAA==.Zenshi:BAAALgAECgEJAgAAAA==.Zeperios:BAAALgAECgYJCgAAAA==.Zeril:BAABLgAECn8UAAMRAAgJjRerCACnAQARAAgJjRerCACnAQANAAEJHgUVLQEpAAAAAA==.Zestdruid:BAAALgAECgQJBAAAAA==.Zestull:BAABLgAECn8kAAIKAAgJnCQUBQDWAgAKAAgJnCQUBQDWAgAAAA==.Zetsuboiki:BAAALgADCgYJBgAAAA==.Zetsudeath:BAAALgADCgYJBgAAAA==.',
Zh='Zhoel:BAAALgADCgEJAQAAAA==.',
Zi='Zindeshal:BAAALgAECgQJBAAAAA==.',
Zo='Zorc:BAACLgAFFH8QAAIUAAQJJhuVEQBRAQAUAAQJJhuVEQBRAQAuAAQKfycAAhQACQmKIPsJAPQCABQACQmKIPsJAPQCAAAA.',
Zu='Zunji:BAAALgAECgEJBAAAAA==.',
Zy='Zyate:BAABLgAECn8xAAINAAkJTRJ5OADfAQANAAkJTRJ5OADfAQAAAA==.Zyrryn:BAABLgAECn8XAAIFAAgJwQOUDwDuAAAFAAgJwQOUDwDuAAAAAA==.',
['Ät']='Ätlas:BAAALgADCgYJDAAAAA==.',
['Ër']='Ërëbus:BAAALgADCgQJBAAAAA==.',
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
