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

local lookup = {'Unknown-Unknown','Warrior-Fury','Druid-Balance','Druid-Restoration','Paladin-Retribution','Paladin-Protection','Evoker-Devastation','Evoker-Augmentation','Warlock-Destruction','DeathKnight-Unholy','Warrior-Protection','Shaman-Restoration','Mage-Frost','Monk-Brewmaster','Hunter-BeastMastery','DeathKnight-Frost','Warlock-Demonology','Hunter-Survival','Priest-Holy','Warlock-Affliction','Rogue-Subtlety','Shaman-Elemental','Shaman-Enhancement','Monk-Mistweaver','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Marksmanship','Monk-Windwalker','DeathKnight-Blood','Druid-Feral','Druid-Guardian','Paladin-Holy','Priest-Discipline','Priest-Shadow','Mage-Arcane','Rogue-Assassination','Warrior-Arms','Evoker-Preservation',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aaffoxx:BAAALgAECgEJAQAAAA==.Aagonyy:BAAALgAECgEJAwAAAA==.',
Ae='Aenninicus:BAAALgAECgEJAgAAAA==.Aernoth:BAAALgAECgUJDQAAAA==.',
Ak='Akaidia:BAAALgAECgYJBgABLgAECgYJCwABAAAAAA==.',
Al='Alderan:BAABLgAECn8lAAICAAcJIg6qPwA9AQACAAcJIg6qPwA9AQAAAA==.Aleinas:BAABLgAECn8kAAMDAAcJKxbxMABLAQADAAcJKxbxMABLAQAEAAQJQQhpkQCHAAAAAA==.Alektophobia:BAAALgAECggJEQAAAA==.Alendra:BAAALgAECgEJAQAAAA==.Alluisice:BAAALgAECgYJBgAAAA==.Allysaun:BAAALgAECgUJBgAAAA==.Alpharoach:BAAALgADCgYJBgAAAA==.Alzeinrich:BAABLgAECn8XAAMFAAcJSQeN0QDkAAAFAAcJmgWN0QDkAAAGAAQJbwjwNACAAAAAAA==.',
Am='Amorina:BAABLgAECn8bAAIFAAgJjxNCZwCWAQAFAAgJjxNCZwCWAQAAAA==.',
An='Anda:BAAALgAECgMJAwAAAA==.Andarnn:BAAALgAECgEJAQAAAA==.Andracca:BAABLgAECn8dAAMHAAgJ+Qp+CwBRAQAHAAgJ+Qp+CwBRAQAIAAEJQAX5kwAkAAAAAA==.Andromeda:BAABLgAECn8WAAIEAAgJ3AvgTABRAQAEAAgJ3AvgTABRAQAAAA==.Aner:BAAALgAECgEJBgAAAA==.Angrygnome:BAACLgAFFH8IAAIJAAMJex7EBgAcAQAJAAMJex7EBgAcAQAuAAQKfx4AAgkACQmqIIYBAMQCAAkACQmqIIYBAMQCAAAA.Angélique:BAAALgAFFAEJAQABLgAFFAYJGAAKAO8hAA==.Antcension:BAAALgADCgUJBQAAAA==.Antemental:BAAALgAECgYJEAAAAA==.Anthigos:BAAALgAECgMJAwAAAA==.',
Ar='Arax:BAABLgAECn8dAAILAAcJ7yHEDQADAgALAAcJ7yHEDQADAgAAAA==.Arcada:BAAALgAECgUJBQABLgAECgUJBQABAAAAAA==.Arcamoon:BAAALgAECgIJAgABLgAECgUJBQABAAAAAA==.Arcashi:BAAALgADCgcJCgABLgAECgUJBQABAAAAAA==.Arianlion:BAAALgAECgEJAgAAAA==.Armistice:BAAALgAECgEJAgAAAA==.Arowenn:BAAALgADCgMJAwAAAA==.Arrokoth:BAAALgAECgEJAQAAAA==.Artana:BAAALgAECgIJAgAAAA==.',
As='Askook:BAAALgAECgYJBgAAAA==.Astolvik:BAAALgAECgQJBgAAAA==.',
At='Attachedplag:BAAALgAECgYJEAAAAA==.Atulwa:BAABLgAECn8jAAIMAAkJdRaOKAAOAgAMAAkJdRaOKAAOAgAAAA==.',
Au='Aurinox:BAABLgAECn8YAAINAAUJxwyz2gDcAAANAAUJxwyz2gDcAAAAAA==.Autodrive:BAAALgAECgUJCAAAAA==.',
Av='Avralea:BAABLgAECn8+AAIOAAgJ8BvpEgASAgAOAAgJ8BvpEgASAgAAAA==.',
Az='Azenthal:BAAALgAECgEJAQAAAA==.Azurestrider:BAAALgAECgEJAQAAAA==.',
Ba='Bananahammik:BAAALgAECgYJDgAAAA==.Banzen:BAABLgAECn8VAAIPAAUJpglOsADSAAAPAAUJpglOsADSAAAAAA==.Basz:BAABLgAECn8zAAMKAAgJ+B2IKwBKAgAKAAgJ+B2IKwBKAgAQAAMJDBAMIgCqAAAAAA==.',
Be='Beefburglar:BAAALgAECgYJBgAAAA==.Beginagain:BAAALgADCgcJCQAAAA==.Belfias:BAAALgAECgEJAgABLgAECgkJFgAQAFMaAA==.Belgran:BAABLgAECn8WAAIQAAkJUxrSAwA9AgAQAAkJUxrSAwA9AgAAAA==.Belris:BAAALgAECgMJAwAAAA==.Berunma:BAABLgAECn8YAAIPAAgJ2BD9bwBVAQAPAAgJ2BD9bwBVAQAAAA==.',
Bh='Bhain:BAABLgAECn8hAAMRAAcJ5R3lSgDpAQARAAcJ5R3lSgDpAQAJAAEJaA2FdAAwAAABLgAFFAQJDwAFAHweAA==.',
Bi='Bileshots:BAABLgAECn8UAAISAAgJNRecGgDEAQASAAgJNRecGgDEAQAAAA==.Biowolf:BAACLgAFFH8VAAINAAQJmQcwaQAJAQANAAQJmQcwaQAJAQAuAAQKfywAAg0ACQneFLVAABQCAA0ACQneFLVAABQCAAAA.Birdhunter:BAAALgAFFAEJAQAAAA==.Bishopixixix:BAAALgAECgYJCwAAAA==.Bits:BAABLgAECn8mAAIRAAgJSAeohgAnAQARAAgJSAeohgAnAQAAAA==.',
Bj='Bjoren:BAABLgAECn8uAAITAAkJGyT6AgBfAwATAAkJGyT6AgBfAwAAAA==.',
Bl='Blackdread:BAAALgADCgYJBgAAAA==.Blasterjenny:BAAALgADCgkJGAABLgAECgIJAgABAAAAAA==.Bloodcaptain:BAABLgAECn8cAAMJAAkJORc+BgDyAQAJAAkJZBY+BgDyAQAUAAYJshf6CAC3AQAAAA==.',
Bo='Bohma:BAAALgADCgEJAQAAAA==.Boopblast:BAAALgAECgQJCAAAAA==.Bootiebang:BAABLgAECn8VAAIVAAYJCQOMPwC0AAAVAAYJCQOMPwC0AAAAAA==.Bootieknight:BAAALgADCgYJBgAAAA==.Bootycaall:BAAALgADCgkJGwAAAA==.Bootycall:BAAALgADCgkJCQAAAA==.Boroth:BAAALgADCgcJBwAAAA==.',
Br='Breetech:BAAALgAECgIJAgAAAA==.Brett:BAAALgAECgEJAQAAAA==.Breé:BAAALgAECgEJAQAAAA==.Brianx:BAAALgADCgIJAgAAAA==.Brklyn:BAAALgAFFAEJAQAAAA==.Brokki:BAAALgADCgEJAQAAAA==.',
Bu='Buckaroo:BAAALgAECgQJBQAAAA==.Bucknekkid:BAAALgAECggJEwAAAA==.Buckwhild:BAABLgAECn8WAAITAAcJoyG5DACMAgATAAcJoyG5DACMAgAAAA==.Burrhus:BAAALgAECgQJBAAAAA==.',
Ca='Cagomei:BAAALgADCggJDgAAAA==.Caladbolg:BAABLgAECn82AAMGAAgJUSGBBQCLAgAGAAgJUSGBBQCLAgAFAAEJkAP5VwEnAAAAAA==.Camrillem:BAAALgAFFAEJAQAAAA==.Cannacola:BAABLgAECn8mAAMWAAYJvB8PKQCYAQAXAAYJ1BzoDQDeAQAWAAYJOh4PKQCYAQAAAA==.Carebearr:BAAALgAECgMJAwAAAA==.',
Ce='Cearius:BAAALgAECgYJCgABLgAFFAMJEAARAGQlAA==.Celthis:BAAALgADCgcJBwABLgAECgUJCQABAAAAAA==.Cerdwin:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.Cesàrè:BAABLgAECn8WAAIYAAgJyAcIVQD/AAAYAAgJyAcIVQD/AAAAAA==.',
Ch='Chahra:BAABLgAECn8aAAIZAAgJQA5tDwBGAQAZAAgJQA5tDwBGAQAAAA==.Chammie:BAAALgAECgYJBgAAAA==.Chamuki:BAACLgAFFH8GAAMaAAMJ4g9KHQCNAAAaAAIJZhZKHQCNAAAbAAEJ2wLGmgAyAAAuAAQKfx4ABBoACAn4HJINADwCABoABwnBIJINADwCABsABQm2DRexALcAABkAAgkXFs8tAEAAAAEuAAUUBAkVAAQAxx4A.Chaosbolt:BAAALgAECgEJAgAAAA==.Cheesecake:BAACLgAFFH8YAAMKAAYJ7yHCOwBtAQAKAAYJ7yHCOwBtAQAQAAIJ3A8uGQCSAAAuAAQKfyYAAwoACQl+JcQCAK4DAAoACQl+JcQCAK4DABAAAwn6GrwjAJ4AAAAA.Cheesuspiece:BAAALgADCgIJAgAAAA==.Chrispbacon:BAAALgAECgMJBAAAAA==.Chuubak:BAAALgAECgkJBQAAAA==.',
Cl='Clangedin:BAABLgAECn8eAAICAAgJOQm8QAA5AQACAAgJOQm8QAA5AQAAAA==.',
Co='Cobalt:BAAALgADCgUJBQABLgAFFAIJBAARANASAA==.Coreydruid:BAAALgAECgMJBwAAAA==.Coreypala:BAAALgAECgIJBAAAAA==.Coreysham:BAAALgAECgQJBQAAAA==.Corily:BAAALgADCgcJHAAAAA==.Corsten:BAABLgAECn8XAAILAAcJww36IwADAQALAAcJww36IwADAQAAAA==.Cosmictonic:BAAALgADCgYJBgAAAA==.',
Cr='Crabpack:BAAALgADCgIJAgAAAA==.Crayoneater:BAAALgAECgQJBAAAAA==.Crippleswagg:BAAALgAECgYJAQAAAA==.Croisades:BAAALgAECgQJCgAAAA==.Crosis:BAAALgADCgcJFwAAAA==.Crowmatic:BAABLgAECn8aAAIKAAkJ+h7TJABpAgAKAAkJ+h7TJABpAgAAAA==.Crusadan:BAAALgADCgYJBgAAAA==.Cryo:BAAALgAECgEJAQAAAA==.',
Cu='Cucklizard:BAAALgAECgEJAQAAAA==.Cute:BAABLgAFFH8NAAICAAMJNCMYIgAcAQACAAMJNCMYIgAcAQAAAA==.',
['Cà']='Càhos:BAAALgADCgUJBQAAAA==.',
Da='Dakon:BAABLgAECn83AAMGAAkJThpQCQAuAgAGAAkJThpQCQAuAgAFAAIJcBi7DAF9AAAAAA==.Dalune:BAABLgAECn8vAAIWAAgJTAhgRQAOAQAWAAgJTAhgRQAOAQAAAA==.Daneaus:BAABLgAECn8sAAIEAAkJviFmBQBaAwAEAAkJviFmBQBaAwAAAA==.Daniellson:BAACLgAFFH8GAAISAAMJ1g2CHgDPAAASAAMJ1g2CHgDPAAAuAAQKfxgABBwACAkoEesvALUBABwACAkoEesvALUBABIAAQk+EKNcADsAAA8AAQkAAFrcABcAAAEuAAUUBgkSAB0AHCQA.Daredevil:BAAALgAECgYJBwABLgAECggJFwAKALYcAA==.Darkchronos:BAAALgAECgEJAQAAAA==.Darkehawke:BAAALgAECgEJAQAAAA==.Darkscorp:BAAALgADCgkJDgAAAA==.Darkwolf:BAABLgAECn81AAMKAAkJ/ROXNQAgAgAKAAkJ/ROXNQAgAgAeAAgJXQYMLwDbAAAAAA==.Darnuus:BAAALgAECgYJDQABLgAECggJIgAIAOELAA==.Datromandude:BAAALgAECgUJCAAAAA==.Dawnbringer:BAAALgADCgQJBAAAAA==.',
Db='Dblaster:BAAALgAECgUJCwAAAA==.',
De='Deathbydruid:BAABLgAECn8iAAMEAAkJqAI7mAB3AAAEAAgJBQI7mAB3AAADAAYJ1QDoeABJAAAAAA==.Deathnelf:BAABLgAECn8YAAMQAAgJAgtlFAArAQAQAAgJAgtlFAArAQAKAAYJYQXv5ADCAAAAAA==.Deazraelle:BAABLgAECn8YAAIRAAcJ9BcvSwC0AQARAAcJ9BcvSwC0AQAAAA==.Decimator:BAAALgADCggJHwAAAA==.Declan:BAAALgADCgUJBQAAAA==.Dedric:BAABLgAECn8nAAQfAAgJ8wpdIADyAAAfAAgJGwhdIADyAAADAAgJKgQtSgDUAAAgAAEJNRemYQA+AAAAAA==.Dellin:BAABLgAECn8qAAIDAAkJFBdsFgAPAgADAAkJFBdsFgAPAgAAAA==.Demeco:BAEALgAECgcJDgABLgAFFAgJGQAhAJwcAA==.Demonch:BAAALgAECgUJCAAAAA==.Demonweasel:BAAALgAECgYJBgABLgAECgcJEwABAAAAAA==.Depeche:BAABLgAECn8dAAIbAAYJ8BBykwDrAAAbAAYJ8BBykwDrAAAAAA==.Deralle:BAABLgAECn8iAAIIAAgJ4QsrNgBLAQAIAAgJ4QsrNgBLAQAAAA==.',
Di='Dil:BAAALgAECgIJAgAAAA==.Diminuendo:BAAALgAECgcJEAAAAA==.',
Do='Donalda:BAAALgAECgEJAQAAAA==.Dorillion:BAAALgAECgUJCQAAAA==.Dorozh:BAABLgAECn8eAAIJAAgJkBPPCgCGAQAJAAgJkBPPCgCGAQAAAA==.',
Dr='Draconx:BAAALgADCgYJBgAAAA==.Draghr:BAAALgAECgQJBAAAAA==.Dragonzmage:BAAALgAECgMJAwAAAA==.Dragskar:BAAALgADCgUJBQAAAA==.Drala:BAABLgAECn8gAAMiAAkJZhMtFgAZAgAiAAkJZhMtFgAZAgATAAEJ2w77ggAuAAAAAA==.Dreadmage:BAAALgADCgUJBQABLgADCgUJCQABAAAAAA==.Dreadpally:BAAALgADCgEJAQABLgADCgUJCQABAAAAAA==.Dreadsham:BAAALgADCgIJAgABLgADCgUJCQABAAAAAA==.Dreco:BAAALgADCgcJBwAAAA==.Driver:BAEALgAFFAIJBAABLgAFFAUJDwARALYLAA==.Dryconias:BAACLgAFFH8KAAIFAAMJvBZUXQDfAAAFAAMJvBZUXQDfAAAuAAQKfy8AAwUACQmRGzAoAFcCAAUACQmRGzAoAFcCAAYAAQmfCF5QACcAAAAA.Drèadpriest:BAABLgAECn8VAAQiAAUJwR1LIwClAQAiAAUJux1LIwClAQATAAUJ0hQoPwDkAAAjAAIJCRMGUQCJAAAAAA==.Drôgô:BAABLgAECn8VAAIPAAYJnhM7TgB+AQAPAAYJnhM7TgB+AQABLgAECggJCAABAAAAAA==.',
Du='Dunkelzhan:BAABLgAECn9HAAINAAkJhhvJIgCMAgANAAkJhhvJIgCMAgAAAA==.Duntack:BAAALgADCgEJBAAAAA==.',
Dy='Dyana:BAABLgAECn8eAAIPAAgJahR0RQDFAQAPAAgJahR0RQDFAQAAAA==.',
Dz='Dz:BAACLgAFFH8HAAIhAAQJJhggHQApAQAhAAQJJhggHQApAQAuAAQKf0AAAyEACQkoJmUAANkDACEACQkoJmUAANkDAAUABAktDn/rAMMAAAAA.',
['Dø']='Dømimømmÿ:BAAALgAECgUJCAAAAA==.',
Ed='Edgyname:BAABLgAECn8UAAIbAAcJBCBxMAD5AQAbAAcJBCBxMAD5AQAAAA==.Edgyvoid:BAAALgADCgYJDAAAAA==.Edlund:BAABLgAECn8jAAIHAAkJfQ3pBwCsAQAHAAkJfQ3pBwCsAQAAAA==.',
Ef='Effyinzpjake:BAAALgAECgYJDgAAAA==.',
Ei='Eianistic:BAAALgADCgEJAQAAAA==.',
El='Elbiee:BAAALgAECggJCAABLgAECgkJFAAWACIZAA==.Elfvispresly:BAAALgAECgEJAQABLgAECggJDgABAAAAAA==.Ellenee:BAAALgADCgMJAwAAAA==.Ellinor:BAAALgADCgkJKQAAAA==.Elvy:BAABLgAECn8vAAIDAAkJVxibGAD7AQADAAkJVxibGAD7AQAAAA==.',
En='Enngin:BAAALgAFFAMJAwAAAA==.Enroks:BAAALgAECgUJBQAAAA==.',
Er='Erebus:BAAALgAECgYJDAAAAA==.Erythra:BAAALgAECgQJBAAAAA==.',
Ev='Evildefiant:BAAALgAECgEJAQAAAA==.',
Ex='Exsalsior:BAAALgADCgYJBgAAAA==.',
Ey='Eyedoc:BAAALgADCgQJBAAAAA==.',
Fa='Fabulousness:BAABLgAECn8jAAITAAgJ+R/+CgCqAgATAAgJ+R/+CgCqAgAAAA==.',
Fe='Fearliz:BAAALgADCgEJAQAAAA==.',
Fi='Fifefrost:BAAALgAECgQJBAAAAA==.Fishingsucks:BAAALgAECgcJCgAAAA==.',
Fl='Flexi:BAAALgADCgEJAQAAAA==.Flitred:BAAALgAECggJDwAAAA==.Flock:BAAALgAECgcJCgAAAA==.',
Fo='Foxx:BAAALgAECgUJDQAAAA==.',
Fr='Framboise:BAABLgAECn8ZAAICAAYJUQcaYAAwAQACAAYJUQcaYAAwAQAAAA==.Frostybolt:BAAALgAECgUJBwAAAA==.',
Fu='Furryriver:BAAALgAECgcJEAAAAA==.Furytotem:BAAALgAECgUJCAABLgABCgIJAgABAAAAAA==.',
['Fø']='Føxx:BAAALgAECgEJAQAAAA==.',
Ga='Galadhras:BAAALgADCgYJFAAAAA==.Galdryn:BAAALgADCgIJAQAAAA==.Galianna:BAABLgAECn8WAAITAAgJOhJOHwC6AQATAAgJOhJOHwC6AQAAAA==.Gamboslice:BAAALgAECggJEwAAAA==.Garkevon:BAAALgADCgMJAwAAAA==.',
Ge='Gemeni:BAAALgAECgEJAQAAAA==.Gevul:BAABLgAECn9VAAMRAAkJthraGgB+AgARAAkJthraGgB+AgAJAAQJ+Q1yRgCcAAAAAA==.',
Gh='Ghostess:BAAALgADCgkJAQAAAA==.Ghrank:BAABLgAECn8VAAQJAAcJvgjCHwCjAAARAAcJUQd0mgAEAQAUAAYJHwiHGgDYAAAJAAYJ8QfCHwCjAAAAAA==.',
Gi='Gilliruni:BAAALgADCgUJBQAAAA==.Gitpull:BAAALgAECggJDQAAAA==.',
Gl='Glimley:BAAALgADCgMJAwAAAA==.',
Gn='Gnimsh:BAAALgAECgEJAwAAAA==.Gnorst:BAAALgADCgkJCgAAAA==.',
Go='Goreolio:BAAALgADCgkJDwABLgAECgYJEQABAAAAAA==.',
Gr='Grandmatank:BAAALgADCgkJCQAAAA==.Grasshopaa:BAAALgADCgYJCQAAAA==.Grassy:BAAALgADCgkJCQAAAA==.Greengoatlin:BAAALgADCgcJBwAAAA==.Gremlock:BAAALgAECgEJAQAAAA==.Gremz:BAABLgAECn8mAAIZAAkJCQrIDwBAAQAZAAkJCQrIDwBAAQAAAA==.Grozny:BAAALgAECgQJBAAAAA==.Grày:BAABLgAECn8wAAIKAAkJXx2/HgCIAgAKAAkJXx2/HgCIAgAAAA==.',
Gu='Gumboslice:BAACLgAFFH8OAAIEAAUJ5A5tIgA4AQAEAAUJ5A5tIgA4AQAuAAQKfx8AAgQACQnSHbIKAAgDAAQACQnSHbIKAAgDAAAA.Gusgus:BAABLgAECn8YAAINAAgJpAUNqQAnAQANAAgJpAUNqQAnAQAAAA==.',
['Gä']='Gändälf:BAABLgAECn8XAAIkAAgJvxVVBACoAQAkAAgJvxVVBACoAQAAAA==.',
Ha='Habanero:BAABLgAECn8qAAMMAAkJSA/XOAC+AQAMAAkJSA/XOAC+AQAWAAQJUxifSQD9AAAAAA==.Hachedev:BAAALgAECgMJCAAAAA==.Hadtopandadk:BAAALgAECgcJDAAAAA==.Hallia:BAACLgAFFH8GAAIEAAMJ9BHjOwC4AAAEAAMJ9BHjOwC4AAAuAAQKfzcAAgQACQlTGkgSALICAAQACQlTGkgSALICAAAA.Hark:BAAALgADCgkJJQAAAA==.Harrybob:BAAALgADCgcJCgAAAA==.Havvocchi:BAAALgAECgEJAwAAAA==.Hawgwild:BAABLgAECn8aAAIKAAYJEhHlmgArAQAKAAYJEhHlmgArAQAAAA==.',
He='Headdinks:BAAALgADCgcJDAAAAA==.Healcap:BAAALgADCgQJBAAAAA==.Healvisprsly:BAABLgAECn8XAAMEAAgJ0heRKAAEAgAEAAcJwxmRKAAEAgADAAYJ9Bj7IwCdAQAAAA==.Heisenberg:BAAALgADCgMJAwABLgAECgMJBwABAAAAAA==.Helena:BAABLgAECn9EAAMFAAkJFSSKBQBBAwAFAAkJEySKBQBBAwAGAAkJUB7oBACdAgAAAA==.Heliarc:BAAALgADCgkJKQAAAA==.Hermès:BAAALgAECgUJBgABLgAFFAYJGAAKAO8hAA==.',
Hi='Highfive:BAAALgAECgUJCwAAAA==.',
Ho='Holybeech:BAAALgAECgQJBAAAAA==.Honestly:BAAALgAFFAIJAgAAAA==.Honkytonkman:BAAALgADCgQJBAAAAA==.Hover:BAAALgAECgYJEQAAAA==.',
Ih='Ihmoen:BAAALgADCgYJBgAAAA==.',
Il='Illuminate:BAAALgADCgQJBAAAAA==.Illustria:BAAALgADCgkJHgAAAA==.Illustriâ:BAAALgADCgcJCwABLgADCgkJHgABAAAAAA==.',
Im='Imprison:BAAALgAECgYJBgABLgAECgcJFQANANIXAA==.',
In='Insidious:BAABLgAECn8fAAIeAAkJFRpeDgAYAgAeAAkJFRpeDgAYAgAAAA==.Invoke:BAAALgADCgEJAQAAAA==.',
Ir='Irs:BAAALgAECgUJBwAAAA==.',
Is='Isisvane:BAAALgADCgkJCQAAAA==.',
It='Itchyfeet:BAAALgAECgUJCAABLgAFFAUJFwANAMohAA==.Itchymage:BAACLgAFFH8XAAINAAUJyiG1OAB3AQANAAUJyiG1OAB3AQAuAAQKfyQAAg0ACQnIIzMdAAEDAA0ACQnIIzMdAAEDAAAA.',
Ja='Jacckiemoon:BAAALgAECgQJBAABLgAECggJFwAEANIXAA==.Jadehunterr:BAAALgAECgMJBAAAAA==.Jaesn:BAAALgADCgYJBgAAAA==.',
Je='Jenae:BAAALgAECgEJAQAAAA==.Jenövha:BAAALgADCgkJFwAAAA==.Jezebelle:BAAALgAECgUJBQAAAA==.',
Ji='Jigs:BAABLgAECn8/AAIPAAgJVBl/NAD/AQAPAAgJVBl/NAD/AQAAAA==.Jiräiya:BAAALgADCgYJBgAAAA==.',
Jo='Johastrasz:BAAALgADCggJCAAAAA==.',
Ju='Junsing:BAAALgADCgEJAQABLgAECggJIgAIAOELAA==.',
['Jå']='Jåfar:BAAALgADCgEJAgAAAA==.',
Ka='Kabøchi:BAAALgAECgUJBQAAAA==.Kaladriel:BAAALgADCgEJAQAAAA==.Kaldrick:BAABLgAECn8YAAIWAAkJFA0yLwB2AQAWAAkJFA0yLwB2AQAAAA==.Kamstareater:BAABLgAECn8mAAIbAAkJ+hL9OwDLAQAbAAkJ+hL9OwDLAQAAAA==.Kanakas:BAAALgAECggJEgAAAA==.Kanaloa:BAABLgAECn8dAAINAAgJ6QnkjwBSAQANAAgJ6QnkjwBSAQAAAA==.Kayler:BAAALgAECgYJBgABLgAECgYJCwABAAAAAA==.',
Ke='Kegerator:BAAALgAECgQJBQAAAA==.Keirin:BAAALgAECggJEgAAAA==.Keldica:BAAALgAECgIJAgAAAA==.Kelysa:BAAALgAECggJDwAAAA==.Kena:BAAALgADCgUJBQAAAA==.Kenshan:BAAALgAECgMJAwAAAA==.Kevinbox:BAAALgAECgYJEAAAAA==.Kevinslayer:BAAALgAECgUJDAAAAA==.Keynaridan:BAABLgAECn8XAAIbAAgJ+hHOVQB5AQAbAAgJ+hHOVQB5AQAAAA==.Keyss:BAAALgADCgIJAgAAAA==.',
Kg='Kglizard:BAAALgAECgUJCAAAAA==.',
Kh='Khalinor:BAABLgAECn8eAAIhAAgJLhKAKAC9AQAhAAgJLhKAKAC9AQAAAA==.Khardun:BAAALgAECgEJAQAAAA==.Khotuhn:BAAALgADCgkJHgAAAA==.',
Ki='Kickazdin:BAACLgAFFH8HAAIhAAMJbCEjHgAhAQAhAAMJbCEjHgAhAQAuAAQKfyEAAyEACQm7HnkGABwDACEACQm7HnkGABwDAAUAAgkFCnAzAWkAAAAA.Killadragon:BAAALgADCgUJBQAAAA==.Kiryie:BAABLgAECn8aAAIPAAgJTw6IVgCTAQAPAAgJTw6IVgCTAQAAAA==.Kisäme:BAAALgAECggJCgAAAA==.',
Kl='Klad:BAAALgAECgEJAQAAAA==.Kluma:BAAALgAECgEJAQAAAA==.',
Kn='Knok:BAAALgAECggJCAAAAA==.',
Ko='Kobu:BAAALgADCgUJBgAAAA==.Konran:BAAALgADCgEJAQAAAA==.',
Kr='Kraigen:BAABLgAECn8kAAIaAAgJeB2ADgAtAgAaAAgJeB2ADgAtAgAAAA==.Krinack:BAABLgAECn8jAAIVAAkJlBE8FQDpAQAVAAkJlBE8FQDpAQAAAA==.Krixiz:BAAALgAECgYJCgAAAA==.',
Ks='Kshamify:BAABLgAFFH8GAAIMAAMJchA0TgClAAAMAAMJchA0TgClAAAAAA==.',
Ku='Kurindrixx:BAAALgADCgIJAgAAAA==.Kurtakum:BAAALgADCgMJAwAAAA==.Kutiel:BAABLgAECn8YAAIWAAcJUgr+SwD1AAAWAAcJUgr+SwD1AAAAAA==.',
Kw='Kwarify:BAAALgADCgEJAQAAAA==.',
Ky='Kynasmira:BAAALgADCgcJHQAAAA==.Kyrsh:BAAALgADCgcJEAAAAA==.',
La='Ladrona:BAABLgAECn8ZAAIlAAkJ+B3xAQDJAgAlAAkJ+B3xAQDJAgAAAA==.Lailyre:BAAALgAECgYJCwAAAA==.Lassan:BAAALgAECgYJCQAAAA==.Later:BAAALgAECggJDAAAAA==.Latimir:BAAALgAECgIJAgAAAA==.Laur:BAAALgADCgYJBgAAAA==.Lavendeer:BAABLgAECn8lAAIDAAkJFhPMHADVAQADAAkJFhPMHADVAQAAAA==.Laydin:BAAALgAECgkJCAABLgAECgkJIgAEAKgCAA==.Laylana:BAAALgADCgIJAgABLgADCgUJCQABAAAAAA==.Lazyeye:BAAALgADCgUJBAABLgAECgcJDQABAAAAAA==.',
Lb='Lb:BAAALgADCgUJBgABLgAECgkJFAAWACIZAA==.',
Le='Legume:BAAALgADCgcJCAABLgAECgUJDQABAAAAAA==.Legzanot:BAACLgAFFH8RAAIWAAQJcgrKKwDXAAAWAAQJcgrKKwDXAAAuAAQKfygAAhYACQkyFiQdACgCABYACQkyFiQdACgCAAAA.Leonceault:BAAALgAECgEJAQAAAA==.',
Li='Lifebringa:BAABLgAECn8sAAMTAAgJTh9oCgCzAgATAAcJ4yJoCgCzAgAjAAcJxhWqJACcAQAAAA==.Lightningfox:BAABLgAECn8kAAMFAAgJwhcXTADYAQAFAAgJwhcXTADYAQAhAAIJug6vcABmAAAAAA==.Lightsfallen:BAAALgAECggJDgAAAA==.Lileth:BAAALgAECgYJBAAAAA==.Limzzmagus:BAAALgAECgMJBgAAAA==.Lithia:BAABLgAECn8aAAIKAAgJiw8ibACFAQAKAAgJiw8ibACFAQAAAA==.Littlemo:BAAALgAECgcJEAAAAA==.',
Lo='Loggs:BAAALgAFFAEJAQAAAA==.Lohnar:BAAALgAECgcJEAAAAA==.Lornah:BAAALgADCgQJBAAAAA==.',
Lu='Lucidslock:BAAALgADCgIJAgAAAA==.Lucielbaal:BAABLgAECn8sAAIRAAkJ9R6dDQDaAgARAAkJ9R6dDQDaAgAAAA==.Luciferus:BAAALgAECgQJBAABLgAECggJLgASAKcQAA==.Luckystop:BAAALgAECgcJEgAAAA==.Lumenir:BAAALgAECgEJAQAAAA==.Lunareth:BAAALgAECgQJBAAAAA==.Luraris:BAAALgAECgEJAQAAAA==.',
Ly='Lyrska:BAABLgAECn8qAAISAAgJqRD5GwC5AQASAAgJqRD5GwC5AQAAAA==.Lytearrow:BAABLgAECn8iAAIPAAgJEg8iXgB/AQAPAAgJEg8iXgB/AQAAAA==.',
['Lè']='Lèonidas:BAAALgADCgUJBQABLgAECgkJKgAgAAMVAA==.',
['Lé']='Léaf:BAAALgAECgMJAwAAAA==.',
Ma='Mahrylee:BAAALgAECgcJEAAAAA==.Maiya:BAAALgADCgcJEAAAAA==.Majutsu:BAAALgADCgEJAQABLgADCgcJDgABAAAAAA==.Malbrax:BAABLgAECn8YAAIRAAgJQhBCXACFAQARAAgJQhBCXACFAQAAAA==.Maleficents:BAABLgAECn8pAAIDAAcJTBERMQBKAQADAAcJTBERMQBKAQAAAA==.Malurius:BAABLgAECn8bAAMmAAkJshScDwDqAQAmAAkJsRKcDwDqAQACAAYJ4AoRYgDEAAAAAA==.Malware:BAAALgAECgYJEQAAAA==.Manana:BAAALgADCgEJAQAAAA==.Manbearpally:BAAALgAECgQJBAAAAA==.Manikfury:BAABLgAECn8iAAMfAAgJwBsACQAoAgAfAAgJwBsACQAoAgAEAAYJYx7YKwDxAQAAAA==.Maniksmage:BAAALgADCgUJDAABLgAECggJIgAfAMAbAA==.Mannypack:BAABLgAECn8dAAQDAAgJixzdEwApAgADAAgJixzdEwApAgAEAAQJkAynfQC2AAAgAAEJOxMBZgA3AAAAAA==.Maranelli:BAAALgAECgIJAwAAAA==.Maseles:BAAALgAECgUJBgABLgAECgUJCQABAAAAAA==.Maxiticon:BAAALgAECgYJEAAAAA==.',
Mc='Mcdawg:BAAALgADCgYJCgAAAA==.Mcleary:BAAALgAECgUJCAAAAA==.',
Me='Meldrus:BAAALgAECgEJAQAAAA==.Melinashala:BAABLgAECn8uAAIRAAgJaQTumwABAQARAAgJaQTumwABAQAAAA==.Mending:BAAALgAECgUJBQAAAA==.Meowinator:BAAALgAECgYJDQAAAA==.Mephizto:BAAALgAECgYJCQAAAA==.Metatrøn:BAAALgAECgIJAgAAAA==.Metide:BAAALgAECgQJBAAAAA==.',
Mi='Miala:BAAALgAECgEJAQAAAA==.Mierna:BAAALgAECgkJEQAAAA==.Miler:BAAALgAECgQJBgAAAA==.Millylittle:BAAALgADCgUJBQAAAA==.Minisor:BAAALgAECgUJBQAAAA==.Misanth:BAAALgAECgYJDgAAAA==.Mistdruid:BAAALgAECgIJAwABLgAECgIJBgABAAAAAA==.',
Mo='Moemo:BAABLgAECn8gAAIEAAkJQh9SCgANAwAEAAkJQh9SCgANAwAAAA==.Mogryn:BAAALgAECgkJEwAAAA==.Moistymists:BAAALgAECgYJCQAAAA==.Moll:BAAALgADCgEJAQAAAA==.Mommybree:BAAALgAECgYJEQAAAA==.Monksterz:BAABLgAECn8uAAIOAAkJzyCnBQDdAgAOAAkJzyCnBQDdAgAAAA==.Monoxidê:BAAALgAECgEJAQAAAA==.Moonwarriorx:BAAALgAECggJDAAAAA==.Morsecode:BAABLgAECn8ZAAIJAAcJFRRADABsAQAJAAcJFRRADABsAQABLgABCgIJAgABAAAAAA==.Morthok:BAABLgAECn8qAAIRAAgJCBjeOADxAQARAAgJCBjeOADxAQAAAA==.Mortischa:BAAALgADCggJCAAAAA==.Mosh:BAABLgAECn8bAAIOAAkJDhT4GADXAQAOAAkJDhT4GADXAQAAAA==.',
Mu='Muchuchu:BAAALgAECgQJDgABLgAECgIJAgABAAAAAA==.Muldern:BAAALgAECgEJAQAAAA==.Munkee:BAAALgAECgYJEQAAAA==.Murdinbronze:BAAALgADCgUJCAAAAA==.Mustachekick:BAAALgADCgUJBwAAAA==.Musyl:BAAALgADCgEJAQABLgAECgYJEQABAAAAAA==.',
['Mã']='Mãf:BAABLgAECn8iAAMMAAcJmRJ0ZAAeAQAMAAYJbA90ZAAeAQAWAAEJtxxShwBSAAAAAA==.',
['Mí']='Místwalker:BAAALgAECgIJBgAAAA==.',
Na='Nackthyr:BAACLgAFFH8bAAMHAAUJCibRAAC7AQAHAAUJCibRAAC7AQAIAAIJNRtHRgChAAAuAAQKfz0AAgcACQmxJjoAAHoDAAcACQmxJjoAAHoDAAAA.Nafir:BAAALgADCgYJFwAAAA==.Nakky:BAAALgAECgQJBAAAAA==.Narlin:BAAALgAECgYJCQAAAA==.Nasta:BAABLgAECn8WAAIFAAYJ6Qiy1ADfAAAFAAYJ6Qiy1ADfAAAAAA==.Natureboi:BAAALgADCgQJBAABLgADCgYJDAABAAAAAA==.Nazareths:BAAALgAECgQJCwAAAA==.Nazgor:BAAALgAECggJCwAAAA==.',
Ne='Neckromancy:BAAALgAECgUJBQAAAA==.Necrosius:BAAALgAECgYJDgAAAA==.Neonarc:BAEALgADCgkJGwAAAA==.Neshi:BAAALgAECgMJBQAAAA==.Neuman:BAAALgADCgEJAQAAAA==.',
Ni='Nibblemah:BAAALgAECgUJBQAAAA==.Nightsbane:BAAALgADCgcJEAAAAA==.Nivdk:BAAALgADCgYJBgABLgAECgYJEQABAAAAAA==.Nivora:BAAALgAECgYJEQAAAA==.',
No='Notsure:BAABLgAECn8UAAILAAkJTgQ8JQD6AAALAAkJTgQ8JQD6AAAAAA==.',
Ny='Nyxstalia:BAAALgAECgUJDAAAAA==.Nyyx:BAABLgAECn8dAAIbAAgJqgUFlwDlAAAbAAgJqgUFlwDlAAAAAA==.',
['Ná']='Nácl:BAAALgAECgcJBwABLgAFFAUJGwAHAAomAA==.',
Ob='Obscyra:BAAALgAECgMJAwAAAA==.',
Ol='Olmek:BAACLgAFFH8ZAAICAAcJixgVBgDlAQACAAcJixgVBgDlAQAuAAQKfxwAAgIABwkrJhoPAHwCAAIABwkrJhoPAHwCAAAA.',
Op='Opalana:BAAALgADCgIJAwAAAA==.Oprahwndfury:BAAALgAECgQJCQABLgAECggJFwAEANIXAA==.',
Or='Orasaya:BAAALgADCgYJBgAAAA==.Orphee:BAAALgADCgcJBwAAAA==.Orzanis:BAAALgADCgcJDgAAAA==.',
Pa='Paige:BAAALgADCgcJDgAAAA==.Palasades:BAAALgADCgUJBQAAAA==.Pallymarc:BAAALgADCgcJCwAAAA==.Pallytune:BAACLgAFFH8OAAIhAAMJDAywLgCvAAAhAAMJDAywLgCvAAAuAAQKfxwAAiEACQnxDnEjAN8BACEACQnxDnEjAN8BAAAA.Pandalorian:BAAALgAECgYJEAAAAA==.Pandamajack:BAAALgAECggJDQAAAA==.',
Ph='Philandre:BAABLgAECn8cAAIFAAgJzhLnXQCrAQAFAAgJzhLnXQCrAQAAAA==.',
Pi='Picoso:BAABLgAECn8gAAINAAgJLQtMhABoAQANAAgJLQtMhABoAQAAAA==.Piianca:BAAALgAECgUJBgAAAA==.Piianna:BAABLgAECn8ZAAITAAcJoBu0GQDuAQATAAcJoBu0GQDuAQAAAA==.Pirko:BAAALgADCggJCwAAAA==.',
Po='Pocketheal:BAAALgADCgkJEAAAAA==.',
Pt='Pteradactyl:BAAALgAECgEJAQAAAA==.',
Pu='Punch:BAAALgAECgEJAgAAAA==.Purplerain:BAAALgAECgQJBQAAAA==.Putrigord:BAAALgAECgQJCwAAAA==.',
Py='Pylarthius:BAAALgADCgcJBwAAAA==.',
Qi='Qik:BAAALgAECgEJAQAAAA==.Qikkaw:BAABLgAECn8gAAMMAAgJaQ8iTwBmAQAMAAgJaQ8iTwBmAQAWAAUJtwnaZwCfAAAAAA==.Qitetsu:BAAALgAECgUJBgAAAA==.',
Qu='Quantos:BAABLgAECn8pAAIgAAgJEhJbJQAVAQAgAAgJEhJbJQAVAQAAAA==.Ququmatz:BAAALgADCgMJAwAAAA==.',
Ra='Raatha:BAABLgAECn8gAAIFAAkJeRYDMAA1AgAFAAkJeRYDMAA1AgAAAA==.Raeyla:BAAALgAECgYJBwAAAA==.Raganar:BAABLgAECn8vAAIGAAgJBRbLDwC6AQAGAAgJBRbLDwC6AQAAAA==.Ranlerodis:BAAALgADCgMJAwAAAA==.Rayjean:BAAALgADCgkJHAAAAA==.',
Re='Redneckboots:BAAALgADCgEJAQAAAA==.Relmax:BAABLgAECn8eAAILAAgJtQjLIwAEAQALAAgJtQjLIwAEAQAAAA==.Rendeminae:BAAALgADCgcJBwAAAA==.Renri:BAABLgAECn8ZAAIVAAcJihR7HwCLAQAVAAcJihR7HwCLAQAAAA==.Repose:BAAALgAECgIJAwAAAA==.Revick:BAAALgAECgUJCAAAAA==.Revil:BAAALgADCgIJAgAAAA==.',
Rh='Rhaenýs:BAAALgADCgcJDQAAAA==.Rhonwynn:BAABLgAECn8oAAIMAAgJ6xySFgCJAgAMAAgJ6xySFgCJAgAAAA==.',
Ri='Rikershipdwn:BAABLgAECn8YAAIPAAgJGhTlSwCyAQAPAAgJGhTlSwCyAQAAAA==.Rikersline:BAAALgADCgkJCQAAAA==.Rimish:BAABLgAECn8XAAIhAAkJPxRwFgBMAgAhAAkJPxRwFgBMAgAAAA==.Rimrave:BAABLgAECn8qAAQmAAkJnh1zBgCNAgAmAAkJJRxzBgCNAgACAAYJIxscNQDVAQALAAYJiB1fGABvAQAAAA==.Ripavicii:BAAALgAECgEJAQAAAA==.Ritobeans:BAAALgADCgcJJQAAAA==.Rivik:BAAALgAECgQJAwAAAA==.',
Ro='Robbstark:BAAALgAECgYJDAAAAA==.Robertkenway:BAABLgAECn8uAAMSAAgJpxDtGgDBAQASAAgJpxDtGgDBAQAPAAEJAADX1AAwAAAAAA==.Roguebot:BAAALgADCgkJEgAAAA==.Rohdaric:BAABLgAECn8ZAAISAAYJUxTNFgBdAQASAAYJUxTNFgBdAQAAAA==.Rokte:BAABLgAECn8aAAIUAAgJ7xCICwCTAQAUAAgJ7xCICwCTAQAAAA==.Roo:BAAALgAECgEJAwAAAA==.Rook:BAABLgAECn8gAAQRAAgJ3iIPEwCvAgARAAgJxCEPEwCvAgAJAAMJmBlQIwCJAAAUAAEJAADaQwAAAAAAAA==.Rosekenway:BAABLgAECn8fAAMEAAgJFwsKUgA9AQAEAAgJFwsKUgA9AQADAAQJzQh7ZAB5AAABLgAECggJLgASAKcQAA==.',
Rr='Rratt:BAAALgAECgYJCwAAAA==.',
Ru='Rubimoon:BAAALgAECgUJBQAAAA==.Rumí:BAAALgAECggJCAAAAA==.Running:BAAALgAECgIJAgAAAA==.',
Sa='Saammiee:BAAALgAECgIJAgAAAA==.Sabiha:BAABLgAECn8UAAMPAAYJaA+qZQA2AQAPAAYJaA+qZQA2AQAcAAEJwQPplAAlAAAAAA==.Safewaybag:BAAALgADCgQJBAAAAA==.Saintb:BAAALgADCggJCAAAAA==.Saintotem:BAABLgAECn8lAAIWAAkJYBElJAC4AQAWAAkJYBElJAC4AQAAAA==.Samartyr:BAAALgAECgYJCQAAAA==.Samison:BAAALgAECgYJBgAAAA==.Sammiiee:BAAALgADCgQJBAABLgAECgIJAgABAAAAAA==.Sandii:BAAALgADCgcJBwAAAA==.Sangwynaris:BAAALgAECgcJCAAAAA==.Saphiiraa:BAABLgAECn8nAAInAAkJyxGBDQDvAQAnAAkJyxGBDQDvAQAAAA==.Sayahealer:BAAALgADCgcJDgAAAA==.',
Sc='Scorpmage:BAABLgAECn8lAAINAAgJHBgTSwD0AQANAAgJHBgTSwD0AQAAAA==.Scramms:BAAALgADCgcJDQAAAA==.Scrams:BAABLgAECn8VAAIcAAcJpwz9FAAIAQAcAAcJpwz9FAAIAQAAAA==.',
Se='Sedrick:BAABLgAECn88AAMhAAkJRSCHCwDKAgAhAAgJMiGHCwDKAgAFAAcJyBVlbACKAQAAAA==.Sekendipity:BAAALgADCgEJAQABLgAECgcJDQABAAAAAA==.Sekhmett:BAAALgADCgMJAwAAAA==.Sekndestroy:BAAALgADCgYJCQABLgAECgcJDQABAAAAAA==.Sektacular:BAAALgADCgQJBAABLgAECgcJDQABAAAAAA==.Sekzen:BAAALgAECgcJDQAAAA==.Semiazas:BAABLgAECn8uAAQUAAkJ+Q2gCgCkAQAUAAkJ+Q2gCgCkAQARAAUJ2QmotwDpAAAJAAEJAAD7egAnAAAAAA==.Semiazes:BAAALgADCgYJBgAAAA==.Senessa:BAAALgADCgIJAgAAAA==.Sensy:BAAALgAECgQJCQAAAA==.Serwonton:BAAALgADCgUJBQAAAA==.Seumas:BAAALgADCgMJAwAAAA==.',
Sh='Shadrock:BAAALgADCgYJBgAAAA==.Shamtune:BAAALgAECgMJAwABLgAFFAMJDgAhAAwMAA==.Shattered:BAABLgAECn8XAAIZAAkJtxkjBQBOAgAZAAkJtxkjBQBOAgAAAA==.Shayrisa:BAABLgAECn81AAMMAAkJTBLLOQC6AQAMAAkJTBLLOQC6AQAWAAcJ4w7JRAAQAQAAAA==.Shazool:BAABLgAECn8aAAMMAAgJRB9pEQC4AgAMAAgJRB9pEQC4AgAXAAIJkQtlLgBoAAABLgAFFAMJBgAEAPQRAA==.Sheep:BAABLgAECn8VAAINAAcJ0hdsbwCVAQANAAcJ0hdsbwCVAQAAAA==.Shifterz:BAAALgAECgcJDwAAAA==.Shrieke:BAAALgAECgQJBAAAAA==.Shrubbery:BAABLgAECn8eAAIgAAgJmBF3GwBgAQAgAAgJmBF3GwBgAQAAAA==.Shxdow:BAAALgAECgQJBAAAAA==.',
Si='Sind:BAAALgAECggJDAABLgAECgkJKgAgAAMVAA==.Sindella:BAAALgAECgMJAwABLgAECgkJKgAgAAMVAA==.Sinna:BAAALgADCgUJCQAAAA==.Sinthorne:BAABLgAECn8qAAMgAAkJAxVrEADQAQAgAAgJcxdrEADQAQAfAAMJ8AX1NwBlAAAAAA==.',
Sk='Skedaddle:BAAALgAECgUJCQABLgAECggJOwANALwkAA==.Skithíryx:BAAALgAECgYJCQABLgAECgYJCwABAAAAAA==.',
Sl='Slashbndcoot:BAAALgAFFAMJAwAAAA==.Slashgquit:BAACLgAFFH8PAAIeAAQJlB4uEgBKAQAeAAQJlB4uEgBKAQAuAAQKfzMAAh4ACQmIJG0DAAUDAB4ACQmIJG0DAAUDAAAA.Slumbermist:BAABLgAECn82AAMdAAkJxhElHADAAQAdAAkJxhElHADAAQAYAAcJcRHUTAAfAQABLgABCgIJAgABAAAAAA==.',
So='Solaire:BAABLgAECn8hAAMGAAcJWRzsDwC4AQAGAAcJWRzsDwC4AQAhAAUJqRCITAD+AAABLgAFFAQJCQAdAMQiAA==.Soras:BAAALgADCgkJHwAAAA==.Sourjack:BAAALgAECgUJBgAAAA==.',
St='Steph:BAAALgAECgUJBQAAAA==.',
Su='Sunareas:BAAALgADCgIJAgAAAA==.',
Sy='Synthetic:BAABLgAECn8eAAIJAAgJzBVSCAC4AQAJAAgJzBVSCAC4AQAAAA==.Syrebriel:BAAALgADCgEJAgABLgAECgcJGAAWAFIKAA==.',
Sz='Szasstaam:BAABLgAECn8iAAMkAAkJpQe9BgBAAQAkAAkJpQe9BgBAAQANAAQJGQLOGQFxAAAAAA==.',
['Sé']='Sénåtor:BAAALgADCgYJCAABLgAECgkJKgAFAFATAA==.Séékér:BAAALgADCgcJFQAAAA==.',
Ta='Talanith:BAAALgADCggJEAAAAA==.Tarayk:BAAALgADCgYJBgABLgADCgkJHAABAAAAAA==.Taxal:BAAALgADCgYJBwAAAA==.Taxlock:BAABLgAECn8aAAIRAAcJ9wldkwAQAQARAAcJ9wldkwAQAQAAAA==.',
Tb='Tbagjones:BAAALgAECgQJBAAAAA==.',
Te='Tecsaran:BAABLgAECn8UAAINAAYJ1B/ebgD2AQANAAYJ1B/ebgD2AQAAAA==.Tekis:BAAALgADCgEJAQAAAA==.Telz:BAAALgAECgYJBgAAAA==.Terania:BAAALgADCgIJAgAAAA==.',
Th='Thalira:BAABLgAECn8cAAQnAAgJvwhdHQAHAQAnAAcJ/AZdHQAHAQAIAAcJTwIhagCOAAAHAAQJrQGENQBpAAAAAA==.',
Ti='Tibbz:BAAALgADCgIJAgAAAA==.Tiger:BAACLgAFFH89AAQfAAkJECUBAACwAwAfAAkJECUBAACwAwAgAAQJiCKBCgAvAQAEAAMJYho3MQDlAAAuAAQKfyoAAx8ACQnqJgUAABYEAB8ACQnqJgUAABYEAAQAAQm1C4TEAD8AAAAA.Tinnea:BAAALgAECgUJDgAAAA==.Titanosaurus:BAAALgAECgcJEAAAAA==.Tizzly:BAABLgAECn8rAAINAAkJzQ6tYgCzAQANAAkJzQ6tYgCzAQAAAA==.',
To='Torhilda:BAAALgAECgYJBgAAAA==.Torridwells:BAABLgAECn8aAAIPAAgJ3A4GVACaAQAPAAgJ3A4GVACaAQAAAA==.',
Tr='Trad:BAAALgADCgYJBgAAAA==.Troag:BAABLgAECn8cAAIMAAgJsxsZGQB1AgAMAAgJsxsZGQB1AgAAAA==.Troagstar:BAABLgAECn8kAAIWAAgJixr7GQAEAgAWAAgJixr7GQAEAgAAAA==.',
Ts='Tsaesci:BAAALgADCgQJBgAAAA==.Tsynn:BAAALgADCgYJFAAAAA==.',
Ty='Tyraana:BAABLgAECn88AAMaAAkJDiAWBQDmAgAaAAkJDiAWBQDmAgAbAAgJ3RQYSQCfAQAAAA==.Tyrinwar:BAAALgADCgYJDAAAAA==.Tyrmog:BAABLgAECn8ZAAIKAAgJ9QeslgAyAQAKAAgJ9QeslgAyAQAAAA==.Tytus:BAAALgAECgUJBQAAAA==.',
Un='Unique:BAAALgAECgEJAQABLgAFFAUJFQACAJ4lAA==.',
Us='Ushas:BAABLgAECn8yAAMTAAkJChnyFwAAAgATAAkJChnyFwAAAgAiAAQJqQUPVQCWAAAAAA==.',
Va='Vali:BAABLgAECn8qAAIcAAgJ0x9OBABnAgAcAAgJ0x9OBABnAgAAAA==.Valindrea:BAAALgAECgcJEAAAAA==.Vasrael:BAABLgAECn8qAAMhAAgJIh1XHAAWAgAhAAcJYRxXHAAWAgAFAAcJRRtVTQDVAQAAAA==.Vav:BAABLgAECn8UAAMPAAYJeBfdlgAEAQAPAAYJeBfdlgAEAQASAAIJswz7XQA5AAAAAA==.',
Ve='Vecnis:BAAALgAECgIJAgAAAA==.Veliette:BAAALgAECgUJBwAAAA==.Verdena:BAAALgADCgcJBwABLgADCgkJHAABAAAAAA==.Vexen:BAAALgAECgYJBgAAAA==.',
Vi='Victaliste:BAAALgAECgEJAQAAAA==.Vithper:BAAALgAECggJEwAAAA==.',
Vn='Vnia:BAAALgADCgMJAwABLgAECgMJCAABAAAAAA==.',
Vo='Voidmuffinz:BAACLgAFFH8IAAIbAAMJ4gw7YQC6AAAbAAMJ4gw7YQC6AAAuAAQKfyMAAhsACQkmGN8qABICABsACQkmGN8qABICAAAA.',
Vy='Vynis:BAAALgAECgcJDQABLgAFFAMJDgAhAAwMAA==.Vyrahildard:BAABLgAECn8tAAIFAAkJfRt8JABpAgAFAAkJfRt8JABpAgAAAA==.',
Wa='Waringoutlaw:BAAALgAECgcJDQAAAA==.Wasteland:BAABLgAECn8rAAIeAAkJphFBGQCLAQAeAAkJphFBGQCLAQAAAA==.',
We='Weaselhunter:BAAALgAECgcJCwABLgAECgcJEwABAAAAAA==.Weasellock:BAAALgAECgcJEwAAAA==.Weaselmage:BAAALgAECgYJDAABLgAECgcJEwABAAAAAA==.Welor:BAAALgADCgYJDAAAAA==.',
Wh='Whatthef:BAAALgAECggJCwAAAA==.',
Wi='Wildweasel:BAAALgAECgcJDQABLgAECgcJEwABAAAAAA==.Winterhide:BAABLgAECn8qAAIKAAgJhRi2OAAVAgAKAAgJhRi2OAAVAgAAAA==.',
Xa='Xallie:BAECLgAFFH8GAAIbAAMJaQjyZQCuAAAbAAMJaQjyZQCuAAAuAAQKfz0AAhsACQl8GvAeAFACABsACQl8GvAeAFACAAAA.Xanvyr:BAABLgAECn8hAAIFAAkJXxntOgANAgAFAAkJXxntOgANAgAAAA==.Xaquillis:BAACLgAFFH8MAAMQAAQJSAvxFgCrAAAKAAMJuQ3LogDDAAAQAAMJsQbxFgCrAAAuAAQKfyIAAwoACAmZGyc8AEcCAAoACAmZGyc8AEcCABAAAQnZDu04ACsAAAAA.Xarthis:BAAALgAECgEJAQABLgAFFAQJDAAQAEgLAA==.',
Xe='Xentrie:BAAALgADCgUJCgAAAA==.Xeyvara:BAABLgAECn8sAAIZAAkJoCSxAABFAwAZAAkJoCSxAABFAwAAAA==.',
Xg='Xg:BAAALgADCgUJBgABLgAECgYJJgAWALwfAA==.',
Xi='Xindra:BAAALgAECgkJCQAAAA==.',
Ya='Yamiyugi:BAAALgADCgUJBQAAAA==.Yatsui:BAAALgAECgQJBAAAAA==.',
Yo='Youngthug:BAAALgAECgIJAwAAAA==.',
Yu='Yutaa:BAAALgADCgYJBgAAAA==.',
Za='Zaden:BAAALgAECgYJBgAAAA==.Zangi:BAAALgAECgEJAQABLgAECgkJLAAEAL4hAA==.Zarihanna:BAABLgAECn8tAAINAAgJ+hPndACJAQANAAgJ+hPndACJAQAAAA==.Zatannah:BAAALgADCgUJBQAAAA==.',
Ze='Zedryn:BAABLgAECn8nAAIRAAkJew+WQgDOAQARAAkJew+WQgDOAQAAAA==.Zenshi:BAAALgAECgEJAgAAAA==.Zeperios:BAAALgAECgYJCgAAAA==.Zeril:BAABLgAECn8UAAMUAAgJjRdoCwCVAQAUAAgJjRdoCwCVAQARAAEJHgXpSQEoAAAAAA==.Zestdruid:BAAALgAECgQJBQAAAA==.Zestull:BAABLgAECn8lAAIOAAgJnCQ3BgDRAgAOAAgJnCQ3BgDRAgAAAA==.Zetsuboiki:BAAALgADCgYJBgAAAA==.Zetsudeath:BAAALgADCgYJBgAAAA==.',
Zh='Zhoel:BAAALgADCgEJAQAAAA==.',
Zi='Ziak:BAAALgAECgUJBQAAAA==.Zindeshal:BAAALgAECgYJCQAAAA==.',
Zo='Zorc:BAACLgAFFH8SAAIWAAQJhRykFwBHAQAWAAQJhRykFwBHAQAuAAQKfycAAhYACQmKIPsJAPQCABYACQmKIPsJAPQCAAAA.',
Zu='Zunji:BAAALgAECgEJBAAAAA==.',
Zy='Zyate:BAABLgAECn8xAAIRAAkJTRITQgDQAQARAAkJTRITQgDQAQAAAA==.Zyrryn:BAABLgAECn8XAAIHAAgJwQOEEQDlAAAHAAgJwQOEEQDlAAAAAA==.',
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
