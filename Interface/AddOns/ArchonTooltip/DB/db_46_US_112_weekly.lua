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

local lookup = {'Unknown-Unknown','Warrior-Fury','Druid-Balance','Druid-Restoration','Mage-Frost','Paladin-Retribution','Paladin-Protection','Evoker-Devastation','Evoker-Augmentation','Warlock-Destruction','DeathKnight-Unholy','Warrior-Protection','Shaman-Restoration','Monk-Brewmaster','Hunter-BeastMastery','DeathKnight-Frost','Warlock-Demonology','Hunter-Survival','Priest-Holy','Warlock-Affliction','Rogue-Subtlety','Priest-Discipline','Shaman-Elemental','Shaman-Enhancement','Monk-Mistweaver','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Marksmanship','DeathKnight-Blood','Druid-Feral','Druid-Guardian','Paladin-Holy','Priest-Shadow','Mage-Arcane','Rogue-Assassination','Warrior-Arms','Evoker-Preservation','Monk-Windwalker',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aaffoxx:BAAALgAECgEJAQAAAA==.Aagonyy:BAAALgAECgEJAwAAAA==.',
Ae='Aenninicus:BAAALgAECgEJAgAAAA==.Aernoth:BAAALgAECgUJDQAAAA==.',
Af='Affox:BAAALgAECgEJAQAAAA==.',
Ak='Akaidia:BAAALgAECgYJBgABLgAECgYJCwABAAAAAA==.',
Al='Alderan:BAABLgAECn8lAAICAAcJIg4cQwA5AQACAAcJIg4cQwA5AQAAAA==.Aleinas:BAABLgAECn8kAAMDAAcJKxbHMwBKAQADAAcJKxbHMwBKAQAEAAQJQQixlQCIAAAAAA==.Alektophobia:BAAALgAFFAEJAQAAAA==.Alendra:BAAALgAECgEJAQABLgAECgYJFAAFANQfAA==.Alluisice:BAAALgAECgYJBgAAAA==.Allysaun:BAAALgAECgUJBgAAAA==.Alpharoach:BAAALgADCgYJBgAAAA==.Alzeinrich:BAABLgAECn8XAAMGAAcJSQd63gDgAAAGAAcJmgV63gDgAAAHAAQJbwjHNwCAAAAAAA==.',
Am='Amorina:BAABLgAECn8cAAIGAAgJzxWqVQDKAQAGAAgJzxWqVQDKAQAAAA==.',
An='Anda:BAAALgAECgMJAwAAAA==.Andarnn:BAAALgAECgEJAQAAAA==.Andracca:BAABLgAECn8eAAMIAAkJFAspDABOAQAIAAkJFAspDABOAQAJAAEJQAXvnAAkAAAAAA==.Andromeda:BAABLgAECn8XAAIEAAkJXQz2TwBPAQAEAAkJXQz2TwBPAQAAAA==.Aner:BAAALgAECgEJBgAAAA==.Angrygnome:BAACLgAFFH8JAAIKAAMJex46CAAUAQAKAAMJex46CAAUAQAuAAQKfx4AAgoACQmqILoBAL4CAAoACQmqILoBAL4CAAAA.Angélique:BAAALgAFFAIJAwABLgAFFAYJGAALAOUhAA==.Antcension:BAAALgADCgUJBQAAAA==.Antemental:BAAALgAECgYJEAAAAA==.Anthigos:BAAALgAECgMJAwAAAA==.',
Ar='Arax:BAABLgAECn8dAAIMAAcJ7yHVDgD9AQAMAAcJ7yHVDgD9AQAAAA==.Arcada:BAAALgAECgUJBQABLgAECgUJBQABAAAAAA==.Arcaidious:BAAALgAECgUJCgABLgAECggJJAANAFcRAA==.Arcamoon:BAAALgAECgIJAgABLgAECgUJBQABAAAAAA==.Arcashi:BAAALgADCgcJCgABLgAECgUJBQABAAAAAA==.Arcxdd:BAAALgAECgQJBAAAAA==.Areuawizard:BAAALgAECgYJBgAAAA==.Arianlion:BAAALgAECgEJAgAAAA==.Ariantheone:BAAALgAECgEJAQAAAA==.Armistice:BAAALgAECgEJAgAAAA==.Arowenn:BAAALgADCgMJAwAAAA==.Arrokoth:BAAALgAECgIJAwAAAA==.Artana:BAAALgAECgIJAgAAAA==.Artistic:BAAALgADCgYJBgAAAA==.',
As='Askook:BAAALgAECgcJDAAAAA==.Astolvik:BAAALgAECgQJBgAAAA==.',
At='Attachedplag:BAAALgAECgYJEwAAAA==.Atulwa:BAABLgAECn8pAAINAAkJ6xfYIwA3AgANAAkJ6xfYIwA3AgAAAA==.',
Au='Aurinox:BAABLgAECn8dAAIFAAYJ9w4EugATAQAFAAYJ9w4EugATAQAAAA==.Autodrive:BAAALgAECggJEQAAAA==.',
Av='Avralea:BAABLgAECn9FAAIOAAgJ8BvNEgAdAgAOAAgJ8BvNEgAdAgAAAA==.',
Az='Azenthal:BAAALgAECgEJAQAAAA==.Azurestrider:BAAALgAECgEJAQAAAA==.',
Ba='Bananahammik:BAAALgAECgYJDgAAAA==.Banzen:BAABLgAECn8ZAAIPAAUJ/g9YqgDuAAAPAAUJ/g9YqgDuAAAAAA==.Basz:BAACLgAFFH8MAAILAAQJKQ9nCgDTAAALAAQJKQ9nCgDTAAAuAAQKfzwAAwsACAn4HWwuAEYCAAsACAn4HWwuAEYCABAABAn+E7weANcAAAAA.',
Be='Beefburglar:BAAALgAECgYJBgAAAA==.Beginagain:BAAALgADCgcJCQAAAA==.Belfias:BAAALgAECgEJAgABLgAECgkJFgAQAFMaAA==.Belgran:BAABLgAECn8WAAIQAAkJUxrSAwA9AgAQAAkJUxrSAwA9AgAAAA==.Belris:BAAALgAECgMJAwAAAA==.Berunma:BAABLgAECn8YAAIPAAgJ2BBzeABPAQAPAAgJ2BBzeABPAQAAAA==.Betabill:BAAALgAECgUJBQAAAA==.',
Bh='Bhain:BAABLgAECn8hAAMRAAcJ5R3lSgDpAQARAAcJ5R3lSgDpAQAKAAEJaA2FdAAwAAABLgAFFAUJEgAGANIeAA==.',
Bi='Bileshots:BAABLgAECn8UAAISAAgJNRcjHAC8AQASAAgJNRcjHAC8AQAAAA==.Biowolf:BAACLgAFFH8fAAIFAAUJNQh8CQDgAAAFAAUJNQh8CQDgAAAuAAQKfywAAgUACQneFBhEAA8CAAUACQneFBhEAA8CAAAA.Birdhunter:BAAALgAFFAEJAQAAAA==.Bishopixixix:BAAALgAECgYJCwABLgAECgcJDwABAAAAAA==.Bits:BAABLgAECn8rAAIRAAkJWgfecwBSAQARAAkJWgfecwBSAQAAAA==.',
Bj='Bjoren:BAABLgAECn8wAAITAAkJGyRTAwBcAwATAAkJGyRTAwBcAwAAAA==.',
Bl='Blackdread:BAAALgADCgYJBgAAAA==.Blasterjenny:BAAALgAECgIJAgAAAA==.Bloodcaptain:BAABLgAECn8cAAMKAAkJORfuBgDtAQAKAAkJZBbuBgDtAQAUAAYJshf6CAC3AQAAAA==.',
Bo='Bohma:BAAALgADCgEJAQAAAA==.Boopblast:BAAALgAECgQJCAAAAA==.Bootiebang:BAABLgAECn8WAAIVAAcJrQOlOgDjAAAVAAcJrQOlOgDjAAAAAA==.Bootieknight:BAAALgAECgUJBQAAAA==.Bootycaall:BAAALgADCgkJGwAAAA==.Bootycall:BAAALgADCgkJCQAAAA==.Boroth:BAAALgADCgcJBwAAAA==.',
Br='Breetech:BAAALgAECgIJAgAAAA==.Brett:BAAALgAECgEJAQAAAA==.Breé:BAAALgAECgEJAQAAAA==.Brianx:BAAALgADCgIJAgAAAA==.Brklyn:BAAALgAFFAEJAQAAAA==.Brockshot:BAAALgADCgcJBwAAAA==.Brokki:BAAALgADCgEJAQAAAA==.',
Bu='Buckaroo:BAAALgAECgQJBQAAAA==.Bucknastey:BAAALgAECgIJAgAAAA==.Bucknekkid:BAABLgAECn8UAAIGAAkJpwWwyAD9AAAGAAkJpwWwyAD9AAAAAA==.Buckwhild:BAABLgAECn8iAAMTAAgJ4CA0CQDWAgATAAgJ4CA0CQDWAgAWAAIJ2BuCAgClAAAAAA==.Burrhus:BAAALgAECgQJBAAAAA==.',
Ca='Cagomei:BAAALgADCggJDgAAAA==.Caladbolg:BAABLgAECn9DAAMHAAgJDyI4BQCfAgAHAAgJDyI4BQCfAgAGAAEJkAP5VwEnAAAAAA==.Camrillem:BAAALgAFFAEJAQAAAA==.Cannacola:BAABLgAECn8mAAMXAAYJvB/IKwCXAQAYAAYJ1BzoDQDeAQAXAAYJOh7IKwCXAQAAAA==.Carebearr:BAAALgAECgMJAwAAAA==.',
Ce='Cearius:BAAALgAECgYJCgABLgAFFAUJFAARAOUfAA==.Celthis:BAAALgADCgcJBwABLgAECgUJCQABAAAAAA==.Cerdwin:BAAALgAECgEJAQABLgAECgYJFAAFANQfAA==.Cesàrè:BAABLgAECn8cAAIZAAgJ/AiHBQCGAAAZAAgJ/AiHBQCGAAAAAA==.',
Ch='Chahra:BAABLgAECn8bAAIaAAkJzg1aEABGAQAaAAkJzg1aEABGAQAAAA==.Chammie:BAAALgAECgYJBgAAAA==.Chamuki:BAACLgAFFH8GAAMbAAMJ4g86IgCJAAAbAAIJZhY6IgCJAAAcAAEJ2wKipwAyAAAuAAQKfyEABBsACAn4HPEOADcCABsABwnBIPEOADcCABwABQm2DcK5ALgAABoAAgkXFtQwAEAAAAEuAAUUBQkaAAMAsR8A.Chaosbolt:BAAALgAECgEJBAAAAA==.Cheesecake:BAACLgAFFH8YAAMLAAYJ5SH+KADGAQALAAYJ5SH+KADGAQAQAAIJ3A9FHgCSAAAuAAQKfyYAAwsACQl+JcQCAK4DAAsACQl+JcQCAK4DABAAAwn6GuImAJwAAAAA.Cheesecaké:BAAALgAFFAIJAgABLgAFFAYJGAALAOUhAA==.Cheesuspiece:BAAALgADCgIJAgAAAA==.Chrispbacon:BAAALgAECgMJBAAAAA==.Chuubak:BAAALgAECgkJBwAAAA==.',
Cl='Clangedin:BAABLgAECn8qAAICAAgJzQm3AgC+AAACAAgJzQm3AgC+AAAAAA==.',
Co='Cobalt:BAAALgADCgUJBQABLgAFFAMJCQARADYbAA==.Colonidus:BAAALgADCgUJBQAAAA==.Coondic:BAAALgADCgEJAQAAAA==.Coreydruid:BAAALgAECgMJBwAAAA==.Coreypala:BAAALgAECgIJBAAAAA==.Coreysham:BAAALgAECgQJBQAAAA==.Corily:BAAALgADCgcJHAAAAA==.Corsten:BAABLgAECn8kAAIMAAgJuA8IAQDuAAAMAAgJuA8IAQDuAAAAAA==.Cosmictonic:BAAALgADCgYJBgAAAA==.',
Cr='Crabpack:BAAALgADCgIJAgAAAA==.Crayoneater:BAAALgAECgQJBAAAAA==.Crippleswagg:BAAALgAECgYJAQAAAA==.Croisades:BAAALgAECgQJCgAAAA==.Crosis:BAAALgADCgcJFwAAAA==.Crowmatic:BAABLgAECn8aAAILAAkJ+h5eJwBlAgALAAkJ+h5eJwBlAgAAAA==.Crusadan:BAAALgADCgYJBgAAAA==.Cryo:BAAALgAECgEJAQAAAA==.',
Cu='Cucklizard:BAAALgAECgEJAQAAAA==.Cute:BAABLgAFFH8NAAICAAMJNCOdKAATAQACAAMJNCOdKAATAQAAAA==.',
['Cà']='Càhos:BAAALgADCgUJBQAAAA==.',
Da='Dakon:BAABLgAECn83AAMHAAkJThoNCgArAgAHAAkJThoNCgArAgAGAAIJcBi7DAF9AAAAAA==.Dalune:BAABLgAECn80AAIXAAgJ5AgDAgDZAAAXAAgJ5AgDAgDZAAAAAA==.Daneaus:BAABLgAECn8sAAIEAAkJviH1BQBZAwAEAAkJviH1BQBZAwAAAA==.Daniellson:BAACLgAFFH8GAAISAAMJ1g1XIQDOAAASAAMJ1g1XIQDOAAAuAAQKfxgABB0ACAkoEesvALUBAB0ACAkoEesvALUBABIAAQk+EKFhADgAAA8AAQkAAFrcABcAAAEuAAUUBgkPAB4ApRgA.Daredevil:BAAALgAECgYJCQABLgAECggJFwALALYcAA==.Darkchronos:BAAALgAECgEJAQAAAA==.Darkehawke:BAAALgAECgEJAQAAAA==.Darkscorp:BAAALgADCgkJDgAAAA==.Darkwolf:BAACLgAFFH8IAAILAAQJkQb3hwD6AAALAAQJkQb3hwD6AAAuAAQKfzcAAwsACQlnFC43ACICAAsACQlnFC43ACICAB4ACAldBicyANQAAAAA.Darnuus:BAAALgAECgYJDQABLgAECggJKgAJAPILAA==.Datromandude:BAAALgAECgUJCAAAAA==.Dawnbringer:BAAALgADCgQJBAAAAA==.',
Db='Dblaster:BAAALgAECgUJCwAAAA==.',
De='Deathbydruid:BAABLgAECn8oAAMEAAkJyANEfwC8AAAEAAkJyANEfwC8AAADAAYJ1QCCfwBJAAAAAA==.Deathnelf:BAABLgAECn8bAAQQAAkJ5AnKFgAiAQAQAAgJAgvKFgAiAQALAAYJYQXK8gC9AAAeAAIJIQMdBABEAAAAAA==.Deazraelle:BAABLgAECn8bAAIRAAcJPhvwPADoAQARAAcJPhvwPADoAQAAAA==.Decimator:BAAALgADCggJHwAAAA==.Declan:BAAALgADCgUJBQAAAA==.Dedric:BAABLgAECn8nAAQfAAgJ8wqDIwDuAAAfAAgJGwiDIwDuAAADAAgJKgRCTgDTAAAgAAEJNRcpbAA+AAAAAA==.Dellin:BAABLgAECn8qAAIDAAkJFBccGAAMAgADAAkJFBccGAAMAgAAAA==.Demeco:BAEALgAECgcJDgABLgAFFAkJIQAhAAscAA==.Demonch:BAAALgAECgUJCAAAAA==.Demonweasel:BAAALgAECgYJBwABLgAFFAIJBQARAPAWAA==.Depeche:BAABLgAECn8dAAIcAAYJ8BC+mgDrAAAcAAYJ8BC+mgDrAAAAAA==.Deralle:BAABLgAECn8qAAIJAAgJ8gvLOQBFAQAJAAgJ8gvLOQBFAQAAAA==.Dethrift:BAAALgAECgEJAQAAAA==.',
Di='Dil:BAAALgAECgIJAwABLgAECggJGAAFAJUaAA==.Diminuendo:BAAALgAECgcJEAAAAA==.',
Do='Donalda:BAAALgAECgEJAQAAAA==.Dorillion:BAAALgAECgUJCQAAAA==.Dorozh:BAABLgAECn8fAAIKAAgJfRTvCQCnAQAKAAgJfRTvCQCnAQAAAA==.',
Dr='Draconx:BAAALgADCgYJBgAAAA==.Draghr:BAAALgAECgQJBAAAAA==.Dragonzmage:BAAALgAECgMJAwAAAA==.Dragskar:BAAALgADCgUJBQAAAA==.Drala:BAABLgAECn8hAAMWAAkJZhPnFwAVAgAWAAkJZhPnFwAVAgATAAEJ2w77ggAuAAAAAA==.Dreadmage:BAAALgADCgUJBQABLgADCgUJCQABAAAAAA==.Dreadpally:BAAALgADCgEJAQABLgADCgUJCQABAAAAAA==.Dreadsham:BAAALgADCgIJAgABLgADCgUJCQABAAAAAA==.Dreco:BAAALgADCgcJBwAAAA==.Driver:BAAALgAFFAIJBAABLgAFFAUJDwARALYLAA==.Dryconias:BAACLgAFFH8KAAIGAAMJvBYZaQDcAAAGAAMJvBYZaQDcAAAuAAQKfzUAAwYACQkqHKUhAIACAAYACQkqHKUhAIACAAcAAQmfCNBUACcAAAAA.Drèadpriest:BAABLgAECn8VAAQWAAUJwR2GJQCjAQAWAAUJux2GJQCjAQATAAUJ0hR3QgDhAAAiAAIJCRMGUQCJAAAAAA==.Drôgô:BAABLgAECn8VAAIPAAYJnhM7TgB+AQAPAAYJnhM7TgB+AQABLgAECggJCAABAAAAAA==.',
Du='Dunkelzhan:BAABLgAECn9WAAIFAAkJyh6NAAChAgAFAAkJyh6NAAChAgAAAA==.Duntack:BAAALgADCgEJBAAAAA==.',
Dy='Dyana:BAABLgAECn8fAAIPAAgJ2BVHRgDPAQAPAAgJ2BVHRgDPAQAAAA==.',
Dz='Dz:BAACLgAFFH8MAAMhAAQJhRkzIAAcAQAhAAQJhRkzIAAcAQAGAAQJPwm8VgACAQAuAAQKf0QAAyEACQlBJlwAAN8DACEACQlBJlwAAN8DAAYABAktDqP4AMAAAAAA.',
['Dø']='Dømimømmÿ:BAAALgAECgUJCAAAAA==.',
Ea='Earts:BAAALgAECgYJBgAAAA==.',
Ed='Edgyname:BAABLgAECn8UAAIcAAcJBCAWMwD5AQAcAAcJBCAWMwD5AQAAAA==.Edgyvoid:BAAALgADCgYJDAAAAA==.Edlund:BAABLgAECn8jAAIIAAkJfQ1jCACqAQAIAAkJfQ1jCACqAQAAAA==.',
Ef='Effyinzpjake:BAAALgAECgYJDgAAAA==.',
Ei='Eianistic:BAAALgADCgEJAQAAAA==.',
El='Elbiee:BAAALgAECggJCAABLgAECgkJFAAXACIZAA==.Eleos:BAAALgAECgMJAwAAAA==.Elfvispresly:BAAALgAECgEJAQABLgAECgkJDwABAAAAAA==.Ellenee:BAAALgADCgMJAwAAAA==.Ellinor:BAAALgADCgkJMgAAAA==.Elvy:BAABLgAECn8vAAIDAAkJVxgZGgD7AQADAAkJVxgZGgD7AQAAAA==.',
En='Enngin:BAAALgAFFAMJBAAAAA==.Enragee:BAAALgAECgEJAQABLgAECgcJGQANAIUiAA==.Enroks:BAAALgAECgUJBQAAAA==.',
Er='Erebus:BAAALgAECgYJDAAAAA==.Erythra:BAAALgAECgQJBAAAAA==.',
Ev='Evildefiant:BAAALgAECgEJAQAAAA==.Evilfoxx:BAAALgADCgQJBQAAAA==.',
Ex='Exsalsior:BAAALgADCgYJBgAAAA==.',
Ey='Eyedoc:BAAALgADCgQJBAAAAA==.',
Fa='Fabulousness:BAABLgAECn8vAAITAAkJCiHpBAAxAwATAAkJCiHpBAAxAwAAAA==.',
Fe='Fearliz:BAAALgADCgEJAQAAAA==.',
Fi='Fifefrost:BAAALgAECgQJBAAAAA==.Fishingsucks:BAAALgAECgcJCgAAAA==.Fiurich:BAAALgAFFAEJAQAAAA==.',
Fl='Flexi:BAAALgADCgEJAQAAAA==.Flitred:BAAALgAECggJDwAAAA==.Flock:BAAALgAECgcJCgAAAA==.',
Fo='Foxx:BAAALgAECgUJDQAAAA==.',
Fr='Framboise:BAABLgAECn8ZAAICAAYJUQcaYAAwAQACAAYJUQcaYAAwAQAAAA==.Frostybolt:BAAALgAECgUJBwAAAA==.',
Fu='Furryriver:BAAALgAECgcJEAAAAA==.Furytotem:BAAALgAECgUJCwABLgABCgIJAgABAAAAAA==.',
['Fø']='Føxx:BAAALgAECgEJAQAAAA==.',
Ga='Galadhras:BAAALgADCgYJFAAAAA==.Galdryn:BAAALgADCgIJAQAAAA==.Galianna:BAABLgAECn8WAAITAAgJOhIyIQC5AQATAAgJOhIyIQC5AQAAAA==.Gamboslice:BAABLgAECn8eAAIQAAgJthbpCgDMAQAQAAgJthbpCgDMAQAAAA==.Garkevon:BAAALgAECgQJAwAAAA==.',
Ge='Gemeni:BAAALgAECgEJAQAAAA==.Gevul:BAACLgAFFH8FAAIRAAMJ9guNfQDJAAARAAMJ9guNfQDJAAAuAAQKf2QAAxEACQmnG6YZAIoCABEACQmTG6YZAIoCAAoABAnlEwEkAJIAAAAA.',
Gh='Ghostess:BAAALgADCgkJAQAAAA==.Ghrank:BAABLgAECn8bAAQRAAcJmwwwAgANAQARAAcJmwwwAgANAQAUAAYJHwgNHQDWAAAKAAYJ8QcFIgCfAAAAAA==.',
Gi='Gilliruni:BAAALgADCgUJBQAAAA==.Gitpull:BAAALgAECggJDQAAAA==.',
Gl='Glimley:BAAALgADCgMJAwAAAA==.',
Gn='Gnimsh:BAAALgAECgEJAwAAAA==.Gnorst:BAAALgADCgkJCgAAAA==.',
Go='Goodfoxx:BAAALgADCgQJBAAAAA==.Goreolio:BAAALgADCgkJDwABLgAECgYJEQABAAAAAA==.',
Gr='Grandmatank:BAAALgADCgkJCQAAAA==.Grasshopaa:BAAALgADCgYJCQAAAA==.Grassy:BAAALgADCgkJCQAAAA==.Greengoatlin:BAAALgADCgcJBwAAAA==.Gremlock:BAAALgAECgEJAQAAAA==.Gremz:BAABLgAECn8mAAIaAAkJCQrEEABAAQAaAAkJCQrEEABAAQAAAA==.Grozny:BAAALgAECgQJBAAAAA==.Grày:BAABLgAECn8wAAILAAkJXx2nIQCBAgALAAkJXx2nIQCBAgAAAA==.',
Gu='Gumboslice:BAACLgAFFH8RAAIEAAUJfhDVJgAmAQAEAAUJfhDVJgAmAQAuAAQKfx8AAgQACQnSHYELAAcDAAQACQnSHYELAAcDAAAA.Gusgus:BAABLgAECn8kAAIFAAgJBgv9AwABAQAFAAgJBgv9AwABAQAAAA==.',
['Gä']='Gändälf:BAABLgAECn8XAAIjAAgJvxXFBACgAQAjAAgJvxXFBACgAQAAAA==.',
Ha='Habanero:BAABLgAECn8qAAMNAAkJSA+rPAC8AQANAAkJSA+rPAC8AQAXAAQJUxhrTgD8AAAAAA==.Hachedev:BAAALgAECgMJCAAAAA==.Hadrîan:BAAALgADCgcJCQAAAA==.Hadtopandadk:BAAALgAECgcJDQAAAA==.Hallia:BAACLgAFFH8GAAIEAAMJ9BHqQACtAAAEAAMJ9BHqQACtAAAuAAQKfzgAAgQACQlTGjcTALECAAQACQlTGjcTALECAAAA.Hark:BAAALgADCgkJLgAAAA==.Harrybob:BAAALgADCgcJCgAAAA==.Havvocchi:BAAALgAECgEJAwAAAA==.Hawgwild:BAABLgAECn8kAAILAAgJWRHLYgCiAQALAAgJWRHLYgCiAQAAAA==.',
He='Headdinks:BAAALgADCgcJDAAAAA==.Healcap:BAAALgADCgQJBAAAAA==.Healvisprsly:BAABLgAECn8bAAQEAAkJgxgYKgAEAgAEAAgJSxoYKgAEAgADAAYJ9BgEJgCcAQAgAAMJ3hluMgDfAAAAAA==.Heisenberg:BAAALgADCgMJAwABLgAECgMJBwABAAAAAA==.Helena:BAABLgAECn9EAAMGAAkJFSSJBgA8AwAGAAkJEySJBgA8AwAHAAkJUB5sBQCbAgAAAA==.Heliarc:BAAALgADCgkJMgAAAA==.Hermès:BAAALgAECgUJBgABLgAFFAYJGAALAOUhAA==.',
Hi='Highfive:BAAALgAECgUJCwAAAA==.',
Ho='Holybeech:BAAALgAECgQJBAAAAA==.Honestly:BAAALgAFFAIJBAAAAA==.Honkytonkman:BAAALgADCgQJBAAAAA==.Hover:BAAALgAECgYJEQAAAA==.',
Ih='Ihmoen:BAAALgADCgYJBgAAAA==.',
Il='Illuminate:BAAALgADCgQJBAAAAA==.Illustria:BAAALgADCgkJIQAAAA==.Illustriâ:BAAALgADCgkJEQABLgADCgkJIQABAAAAAA==.',
Im='Imprison:BAAALgAECgYJBgABLgAECggJGAAFAJUaAA==.',
In='Insidious:BAABLgAECn8fAAIeAAkJFRrMDwAPAgAeAAkJFRrMDwAPAgAAAA==.Invoke:BAAALgADCgEJAQAAAA==.',
Ir='Irs:BAAALgAECgUJBwAAAA==.',
Is='Isisvane:BAAALgAECgIJAgAAAA==.',
It='Itchyfeet:BAAALgAECgUJCAABLgAFFAUJGwAFAJQiAA==.Itchymage:BAACLgAFFH8bAAIFAAUJlCJ1OgCBAQAFAAUJlCJ1OgCBAQAuAAQKfyUAAgUACQnIIzMdAAEDAAUACQnIIzMdAAEDAAAA.',
Ja='Jacckiemoon:BAAALgAECgQJBAABLgAECgkJGwAEAIMYAA==.Jadehunterr:BAAALgAECgMJBAAAAA==.Jaesn:BAAALgADCgYJBgAAAA==.',
Je='Jenae:BAAALgAECgEJAQAAAA==.Jenövha:BAAALgADCgkJFwAAAA==.Jezebelle:BAAALgAECgUJBQAAAA==.',
Ji='Jighlipuff:BAAALgAECgIJAgAAAA==.Jigs:BAABLgAECn9KAAIPAAkJTRpEIABmAgAPAAkJTRpEIABmAgAAAA==.Jiräiya:BAAALgADCgYJBgAAAA==.',
Jo='Johastrasz:BAAALgADCggJCAAAAA==.',
Ju='Junsing:BAAALgADCgEJAQABLgAECggJKgAJAPILAA==.',
['Jå']='Jåfar:BAAALgADCgEJAgAAAA==.',
Ka='Kabøchi:BAAALgAECgUJBQAAAA==.Kaladriel:BAAALgADCgEJAQAAAA==.Kaldrick:BAABLgAECn8gAAIXAAkJZBTpGwACAgAXAAkJZBTpGwACAgAAAA==.Kamstareater:BAABLgAECn8mAAIcAAkJ+hLXPgDNAQAcAAkJ+hLXPgDNAQAAAA==.Kanakas:BAABLgAECn8UAAIhAAkJohtYHQAYAgAhAAkJohtYHQAYAgAAAA==.Kanaloa:BAABLgAECn8pAAIFAAkJ1gkJeACJAQAFAAkJ1gkJeACJAQAAAA==.Kayler:BAAALgAECgYJBgABLgAECgYJCwABAAAAAA==.',
Ke='Kegerator:BAAALgAECgQJBQAAAA==.Keirin:BAAALgAECggJEgAAAA==.Keldica:BAAALgAECgIJAgABLgAECgYJFAAFANQfAA==.Kelemver:BAAALgADCgMJAwAAAA==.Kelysa:BAAALgAECggJDwAAAA==.Kena:BAAALgADCgUJBQAAAA==.Kenshan:BAAALgAECgMJAwAAAA==.Kevinbox:BAAALgAECgYJEAAAAA==.Kevinslayer:BAAALgAECgUJDAAAAA==.Keynaridan:BAABLgAECn8ZAAIcAAgJ1xJKVACJAQAcAAgJ1xJKVACJAQAAAA==.Keyss:BAAALgADCgIJAgAAAA==.',
Kg='Kglizard:BAAALgAECgUJCAAAAA==.',
Kh='Khalinor:BAABLgAECn8lAAIhAAkJXhcQEgCCAgAhAAkJXhcQEgCCAgAAAA==.Khardun:BAAALgAECgEJAQAAAA==.Khotuhn:BAAALgADCgkJJAAAAA==.',
Ki='Kickazdin:BAACLgAFFH8LAAIhAAQJShwDGQBbAQAhAAQJShwDGQBbAQAuAAQKfyIAAyEACQm7HisHABkDACEACQm7HisHABkDAAYAAgkFClBDAWkAAAAA.Killadragon:BAAALgADCgUJBQAAAA==.Kiryie:BAABLgAECn8bAAIPAAkJDA8fXgCMAQAPAAkJDA8fXgCMAQAAAA==.Kisäme:BAAALgAECggJCwAAAA==.',
Kl='Klad:BAAALgAECgEJAQAAAA==.Kluma:BAAALgAECgEJAQAAAA==.',
Kn='Knok:BAAALgAECggJCAAAAA==.',
Ko='Kobu:BAAALgADCgUJBgAAAA==.Konran:BAAALgADCgEJAQAAAA==.',
Kr='Kraigen:BAABLgAECn8wAAIbAAkJLh6WBwC3AgAbAAkJLh6WBwC3AgAAAA==.Krinack:BAABLgAECn8jAAIVAAkJlBHEFgDnAQAVAAkJlBHEFgDnAQAAAA==.Krixiz:BAAALgAECgYJCgAAAA==.',
Ks='Kshamify:BAABLgAFFH8GAAINAAMJchAvVwCgAAANAAMJchAvVwCgAAAAAA==.',
Ku='Kurindrixx:BAAALgADCgIJAgAAAA==.Kurtakum:BAAALgADCgMJAwAAAA==.Kutiel:BAABLgAECn8YAAIXAAcJUgrbUAD0AAAXAAcJUgrbUAD0AAAAAA==.',
Kw='Kwarify:BAAALgADCgEJAQAAAA==.',
Ky='Kynasmira:BAAALgADCgcJHQAAAA==.Kyrsh:BAAALgADCgcJEAAAAA==.',
La='Ladrona:BAABLgAECn8ZAAIkAAkJ+B0lAgDHAgAkAAkJ+B0lAgDHAgAAAA==.Lailyre:BAAALgAECgYJCwAAAA==.Lassan:BAAALgAECgYJCQAAAA==.Later:BAAALgAECggJDAAAAA==.Latimir:BAAALgAECgIJAgAAAA==.Laur:BAAALgADCgYJBgAAAA==.Lavendeer:BAABLgAECn8lAAIDAAkJFhP+HgDQAQADAAkJFhP+HgDQAQAAAA==.Laydin:BAAALgAECgkJCAABLgAECgkJKAAEAMgDAA==.Laylana:BAAALgADCgIJAgABLgADCgUJCQABAAAAAA==.Lazyeye:BAAALgADCgUJBAABLgAECgcJDgABAAAAAA==.',
Lb='Lb:BAAALgADCgUJBgABLgAECgkJFAAXACIZAA==.',
Le='Legume:BAAALgADCgcJCAABLgAECgUJDQABAAAAAA==.Legzanot:BAACLgAFFH8TAAIXAAQJcgoNBgCBAAAXAAQJcgoNBgCBAAAuAAQKfygAAhcACQkyFiQdACgCABcACQkyFiQdACgCAAAA.Leonceault:BAAALgAECgEJAQAAAA==.',
Li='Lifebringa:BAABLgAECn8sAAMTAAgJTh9oCwCwAgATAAcJ4yJoCwCwAgAiAAcJxhWnJgCXAQAAAA==.Lightningfox:BAABLgAECn8rAAMGAAgJkBqXOwAVAgAGAAgJkBqXOwAVAgAhAAIJug7zdABmAAAAAA==.Lightsfallen:BAAALgAECgkJDwAAAA==.Lileth:BAAALgAECgYJBAAAAA==.Lilylulu:BAAALgADCgIJAgAAAA==.Limzzmagus:BAAALgAECgMJBgAAAA==.Lithia:BAABLgAECn8bAAILAAkJzw95cgB/AQALAAkJzw95cgB/AQAAAA==.Littlemo:BAAALgAECgcJEAAAAA==.',
Lo='Loggs:BAAALgAFFAEJAQAAAA==.Lohnar:BAAALgAECgcJEAAAAA==.Lornah:BAAALgADCgQJBAAAAA==.',
Lu='Lucidslock:BAAALgADCgIJAgAAAA==.Lucielbaal:BAABLgAECn8sAAIRAAkJ9R4LDwDUAgARAAkJ9R4LDwDUAgAAAA==.Luciferus:BAAALgAECgUJCAABLgAECggJLgASAKcQAA==.Luckystop:BAABLgAECn8ZAAMNAAcJhSJYFACpAgANAAcJhSJYFACpAgAXAAQJNwqMagCoAAAAAA==.Lumenir:BAAALgAECgEJAQAAAA==.Lunareth:BAAALgAECgQJBAAAAA==.Luraris:BAAALgAECgEJAQAAAA==.',
Ly='Lyrska:BAABLgAECn8vAAISAAkJLREWFAAEAgASAAkJLREWFAAEAgAAAA==.Lytearrow:BAABLgAECn8nAAIPAAgJRA8gYQCEAQAPAAgJRA8gYQCEAQAAAA==.',
['Lè']='Lèonidas:BAAALgAECgEJAQABLgAECgkJLgAgAAMVAA==.',
['Lé']='Léaf:BAAALgAECgMJAwAAAA==.',
Ma='Mahrylee:BAAALgAECgcJEAAAAA==.Maiya:BAAALgADCgcJEAAAAA==.Majutsu:BAAALgADCgEJAQABLgADCgcJDgABAAAAAA==.Malbrax:BAABLgAECn8ZAAIRAAgJcxIxVACfAQARAAgJcxIxVACfAQAAAA==.Maleficents:BAABLgAECn8tAAIDAAcJ4RJ3LgBnAQADAAcJ4RJ3LgBnAQAAAA==.Malurius:BAABLgAECn8bAAMlAAkJshS0EADoAQAlAAkJsRK0EADoAQACAAYJ4AomZwDBAAAAAA==.Malware:BAAALgAECgYJEQAAAA==.Manana:BAAALgADCgEJAQAAAA==.Manbearpally:BAAALgAECgQJBAAAAA==.Manikfury:BAABLgAECn8iAAMfAAgJwBu5CQAmAgAfAAgJwBu5CQAmAgAEAAYJYx5aLQDxAQAAAA==.Maniksmage:BAAALgAECgcJDAABLgAECggJIgAfAMAbAA==.Mannypack:BAABLgAECn8eAAQDAAgJixwSFQAoAgADAAgJixwSFQAoAgAEAAQJkAz6gQC1AAAgAAEJOxOocAA3AAAAAA==.Maranelli:BAAALgAECgIJAwAAAA==.Maseles:BAAALgAECgUJBgABLgAECgUJCQABAAAAAA==.Maxiticon:BAABLgAECn8XAAQiAAYJTQixYACWAAAiAAUJ0QWxYACWAAATAAUJogXPVACJAAAWAAEJnQ72egAwAAAAAA==.',
Mc='Mcdawg:BAAALgADCgYJCgAAAA==.Mcleary:BAAALgAECgYJCQAAAA==.',
Me='Meldrus:BAAALgAECgEJAQAAAA==.Melinashala:BAABLgAECn88AAIRAAkJBwVkBACdAAARAAkJBwVkBACdAAAAAA==.Mending:BAAALgAECgUJBQAAAA==.Meowinator:BAAALgAECgYJDQAAAA==.Mephizto:BAAALgAECgYJCQAAAA==.Metatrøn:BAAALgAECgYJBwAAAA==.Metide:BAAALgAECgQJBAAAAA==.',
Mi='Miala:BAAALgAECgEJAQAAAA==.Mierna:BAAALgAECgkJEgAAAA==.Miler:BAAALgAECgUJBwAAAA==.Millylittle:BAAALgADCgUJBQAAAA==.Minisor:BAAALgAECgUJBQAAAA==.Misanth:BAAALgAECgYJDgAAAA==.Mistdruid:BAAALgAECgIJAwABLgAECgIJBgABAAAAAA==.',
Mo='Moemo:BAABLgAECn8hAAIEAAkJQh8PCwANAwAEAAkJQh8PCwANAwAAAA==.Mogryn:BAAALgAECgkJEwAAAA==.Moistymists:BAAALgAECgYJCQAAAA==.Moll:BAAALgADCgEJAQAAAA==.Mommybree:BAAALgAECgYJEgAAAA==.Monksterz:BAABLgAECn8wAAIOAAkJayEnBgDaAgAOAAkJayEnBgDaAgAAAA==.Monophobic:BAAALgAECgcJBwAAAA==.Monoxidê:BAAALgAECgEJAQAAAA==.Moonwarriorx:BAAALgAECggJDAAAAA==.Morsecode:BAABLgAECn8hAAIKAAkJSRbHCAC+AQAKAAkJSRbHCAC+AQABLgABCgIJAgABAAAAAA==.Morthok:BAABLgAECn8rAAIRAAgJCBhKOwDtAQARAAgJCBhKOwDtAQAAAA==.Mortischa:BAAALgADCggJCAAAAA==.Mosh:BAABLgAECn8bAAIOAAkJDhQRGgDVAQAOAAkJDhQRGgDVAQAAAA==.',
Mu='Muchuchu:BAAALgAECgUJEQABLgAECgIJAgABAAAAAA==.Muldern:BAAALgAECgEJAQAAAA==.Munkee:BAAALgAECgYJEQAAAA==.Murdinbronze:BAAALgADCgUJCAAAAA==.Mustachekick:BAAALgAECgUJBQAAAA==.Musyl:BAAALgADCgEJAQABLgAECgYJEQABAAAAAA==.',
['Mã']='Mãf:BAABLgAECn8kAAMNAAgJVxH1VABhAQANAAgJVxH1VABhAQAXAAEJtxx3kABRAAAAAA==.',
['Mí']='Místwalker:BAAALgAECgIJBgAAAA==.',
Na='Nackthyr:BAACLgAFFH8cAAMIAAUJCiYoAQCyAQAIAAUJCiYoAQCyAQAJAAIJNRvNTACbAAAuAAQKfz0AAggACQmxJkcAAHcDAAgACQmxJkcAAHcDAAAA.Nafir:BAAALgADCgYJFwAAAA==.Nakky:BAAALgAECgYJDgAAAA==.Narlin:BAAALgAECgYJCQAAAA==.Nasta:BAABLgAECn8bAAIGAAYJ6QhY4QDcAAAGAAYJ6QhY4QDcAAAAAA==.Natureboi:BAAALgADCgQJBAABLgADCgYJDAABAAAAAA==.Nazareths:BAAALgAECgQJCwAAAA==.Nazgor:BAABLgAECn8VAAILAAgJ9BZFAgA2AQALAAgJ9BZFAgA2AQAAAA==.Nazrien:BAAALgADCgMJAwAAAA==.',
Ne='Neckromancy:BAAALgAECgYJCgAAAA==.Necrosius:BAAALgAECgYJDwAAAA==.Neonarc:BAEALgADCgkJJAAAAA==.Neshi:BAAALgAECgMJBQAAAA==.Neuman:BAAALgADCgEJAQAAAA==.',
Ni='Nibblemah:BAAALgAECgcJCwAAAA==.Nightsbane:BAAALgADCgcJEAAAAA==.Nivdk:BAAALgADCgYJBgABLgAECgYJEQABAAAAAA==.Nivora:BAAALgAECgYJEQAAAA==.',
No='Notsure:BAABLgAECn8YAAIMAAkJTgReJwD4AAAMAAkJTgReJwD4AAAAAA==.',
Ny='Nyxstalia:BAAALgAECgUJDAAAAA==.Nyyx:BAABLgAECn8jAAIcAAgJMwg6nQDnAAAcAAgJMwg6nQDnAAAAAA==.',
['Ná']='Nácl:BAAALgAECgcJCAABLgAFFAUJHAAIAAomAA==.',
Oa='Oath:BAAALgAECgUJBQAAAA==.',
Ob='Obscyra:BAAALgAFFAEJAQAAAA==.',
Ol='Olmek:BAACLgAFFH8eAAICAAgJcRoXCADiAQACAAgJcRoXCADiAQAuAAQKfx4AAgIABwk7JlUPAIACAAIABwk7JlUPAIACAAAA.',
Oo='Oochie:BAAALgADCgQJAwAAAA==.Oonagi:BAAALgAECgUJBQAAAA==.',
Op='Opalana:BAAALgADCgIJAwAAAA==.Ophiana:BAAALgAECgEJAgAAAA==.Oprahwndfury:BAAALgAECgYJDgABLgAECgkJGwAEAIMYAA==.',
Or='Orasaya:BAAALgADCgYJBgAAAA==.Orphee:BAAALgADCgcJBwAAAA==.Orzanis:BAAALgADCgcJDgAAAA==.',
Pa='Paige:BAAALgADCgcJDgAAAA==.Palasades:BAAALgADCgUJBQAAAA==.Pallymarc:BAAALgADCgcJCwAAAA==.Pallytune:BAACLgAFFH8QAAIhAAMJPxPWLQDDAAAhAAMJPxPWLQDDAAAuAAQKfxwAAiEACQnxDiwlAN0BACEACQnxDiwlAN0BAAAA.Pandalorian:BAAALgAECgYJEAAAAA==.Pandamajack:BAAALgAECggJEwAAAA==.',
Ph='Philandre:BAABLgAECn8jAAIGAAgJlBNtYgCrAQAGAAgJlBNtYgCrAQAAAA==.',
Pi='Picoso:BAABLgAECn8iAAIFAAkJrw33aQCoAQAFAAkJrw33aQCoAQAAAA==.Piianca:BAAALgAECgUJBgAAAA==.Piianna:BAABLgAECn8ZAAITAAcJoBuaGwDrAQATAAcJoBuaGwDrAQAAAA==.Pirko:BAAALgADCggJCwAAAA==.',
Po='Pocketheal:BAAALgADCgkJEAAAAA==.',
Pt='Pteradactyl:BAAALgAECgYJBgAAAA==.',
Pu='Punch:BAAALgAECgEJAgAAAA==.Purplerain:BAAALgAECgQJBQAAAA==.Putrigord:BAAALgAECgQJCwAAAA==.',
Py='Pylarthius:BAAALgADCgcJBwAAAA==.',
Qi='Qik:BAAALgAECgEJAQAAAA==.Qikkaw:BAABLgAECn8tAAMNAAgJ5hGnAwC4AAANAAgJ5hGnAwC4AAAXAAcJVAhMaACuAAAAAA==.Qitetsu:BAAALgAECgUJBgAAAA==.',
Qu='Quantos:BAABLgAECn87AAIgAAkJlBDqAAA8AQAgAAkJlBDqAAA8AQAAAA==.Ququmatz:BAAALgADCgMJAwAAAA==.',
Ra='Raatha:BAABLgAECn8gAAIGAAkJeRY8NAAvAgAGAAkJeRY8NAAvAgAAAA==.Raeyla:BAAALgAECgcJEwAAAA==.Raganar:BAABLgAECn88AAIHAAgJ2haYDgDaAQAHAAgJ2haYDgDaAQAAAA==.Ranlerodis:BAAALgADCgMJAwAAAA==.Rayjean:BAAALgADCgkJIwAAAA==.',
Re='Redneckboots:BAAALgADCgEJAQAAAA==.Relmax:BAABLgAECn8fAAIMAAgJKwoFIgAgAQAMAAgJKwoFIgAgAQAAAA==.Rendeminae:BAAALgADCgcJBwAAAA==.Renri:BAABLgAECn8eAAIVAAcJFBZTHwCbAQAVAAcJFBZTHwCbAQAAAA==.Repose:BAAALgAECgIJAwAAAA==.Revick:BAAALgAECgUJCAAAAA==.Revil:BAAALgADCgIJAgAAAA==.',
Rh='Rhaenýs:BAAALgADCgcJDQAAAA==.Rhonwynn:BAABLgAECn81AAINAAgJXB5JFgCXAgANAAgJXB5JFgCXAgAAAA==.',
Ri='Rikershipdwn:BAABLgAECn8ZAAIPAAgJQRRnTgC3AQAPAAgJQRRnTgC3AQAAAA==.Rikersline:BAAALgADCgkJCQAAAA==.Rimish:BAABLgAECn8aAAIhAAkJ4xQ/FgBaAgAhAAkJ4xQ/FgBaAgAAAA==.Rimrave:BAABLgAECn8qAAQlAAkJnh0IBwCKAgAlAAkJJRwIBwCKAgACAAYJIxscNQDVAQAMAAYJiB0LGgBqAQAAAA==.Ripavicii:BAAALgAECgEJAQAAAA==.Ritobeans:BAAALgADCgkJLgAAAA==.Rivik:BAAALgAECgQJAwAAAA==.',
Ro='Robbstark:BAAALgAECgYJDAAAAA==.Robertkenway:BAABLgAECn8uAAMSAAgJpxCiHAC4AQASAAgJpxCiHAC4AQAPAAEJAADX1AAwAAAAAA==.Roguebot:BAAALgADCgkJEgAAAA==.Rohdaric:BAABLgAECn8ZAAISAAYJUxTNFgBdAQASAAYJUxTNFgBdAQAAAA==.Rokte:BAABLgAECn8bAAIUAAkJ0w+iDACSAQAUAAkJ0w+iDACSAQAAAA==.Rollhots:BAAALgAECgYJBgAAAA==.Roo:BAAALgAECgEJAwAAAA==.Rook:BAABLgAECn8nAAQKAAgJNyN2BAA2AgARAAgJxCGuFACpAgAKAAcJcyB2BAA2AgAUAAEJAAC8SQAAAAAAAA==.Rookeh:BAAALgAECgYJBgABLgAECggJJwAKADcjAA==.Rosekenway:BAABLgAECn8wAAMEAAkJ7hZbAABHAgAEAAkJ7hZbAABHAgADAAQJzQj2aQB5AAABLgAECggJLgASAKcQAA==.',
Rr='Rratt:BAAALgAECgYJDwAAAA==.',
Ru='Rubimoon:BAAALgAECgUJBQAAAA==.Rumí:BAAALgAECggJCAAAAA==.Running:BAAALgAECgIJAgAAAA==.',
Sa='Saammiee:BAAALgAECgMJBAAAAA==.Sabiha:BAABLgAECn8UAAMPAAYJaA+qZQA2AQAPAAYJaA+qZQA2AQAdAAEJwQPplAAlAAAAAA==.Safewaybag:BAAALgADCgQJBAAAAA==.Saintb:BAAALgAECgUJBAAAAA==.Saintotem:BAABLgAECn8lAAIXAAkJYBGeJgC2AQAXAAkJYBGeJgC2AQAAAA==.Samartyr:BAAALgAECgYJCQAAAA==.Samison:BAAALgAECgYJBgAAAA==.Sammiiee:BAAALgADCgQJBAABLgAECgMJBAABAAAAAA==.Sandii:BAAALgADCgkJCgAAAA==.Sangwynaris:BAAALgAECgcJCAAAAA==.Saphiiraa:BAABLgAECn8nAAImAAkJyxEfDgDsAQAmAAkJyxEfDgDsAQAAAA==.Sayahealer:BAAALgADCgcJDgAAAA==.',
Sc='Scorpmage:BAABLgAECn8nAAIFAAgJAhnLSQD+AQAFAAgJAhnLSQD+AQAAAA==.Scramms:BAAALgADCgcJDQAAAA==.Scrams:BAABLgAECn8VAAIdAAcJpwxdFgAFAQAdAAcJpwxdFgAFAQAAAA==.',
Se='Sedrick:BAABLgAECn8/AAMhAAkJRSB8DADHAgAhAAgJMiF8DADHAgAGAAcJyBW+cgCIAQAAAA==.Sekendipity:BAAALgADCgEJAQABLgAECgcJDgABAAAAAA==.Sekhmett:BAAALgADCgMJAwAAAA==.Sekndestroy:BAAALgADCgYJCQABLgAECgcJDgABAAAAAA==.Sektacular:BAAALgADCgQJBAABLgAECgcJDgABAAAAAA==.Sekzen:BAAALgAECgcJDgAAAA==.Semiazas:BAABLgAECn83AAQUAAkJbw88AADTAQAUAAkJbw88AADTAQARAAUJ2QmotwDpAAAKAAEJAAD7egAnAAAAAA==.Semiazes:BAAALgADCgYJBgAAAA==.Senessa:BAAALgADCgIJAgAAAA==.Sensy:BAAALgAECgQJCQAAAA==.Sepulveda:BAAALgAECgUJBQABLgAECgkJIQAEAEIfAA==.Serwonton:BAAALgADCgUJBQAAAA==.Seumas:BAAALgADCgMJAwAAAA==.',
Sh='Shadrock:BAAALgADCgYJBgAAAA==.Shamtune:BAAALgAECgMJAwABLgAFFAMJEAAhAD8TAA==.Shattered:BAABLgAECn8dAAIaAAkJSxuFBQBNAgAaAAkJSxuFBQBNAgAAAA==.Shayrisa:BAABLgAECn84AAMNAAkJTBLDPAC7AQANAAkJTBLDPAC7AQAXAAcJ4w4bSQAQAQAAAA==.Shazool:BAABLgAECn8bAAMNAAkJmR7rEgC1AgANAAkJmR7rEgC1AgAYAAIJkQtPMgBoAAABLgAFFAMJBgAEAPQRAA==.Sheep:BAABLgAECn8YAAMFAAgJlRpvSwD5AQAFAAgJshlvSwD5AQAjAAIJmBn/EwBMAAAAAA==.Shifterz:BAAALgAECgcJDwAAAA==.Shrieke:BAAALgAECgYJCQAAAA==.Shrubbery:BAABLgAECn8fAAIgAAgJpBElHABtAQAgAAgJpBElHABtAQAAAA==.Shxdow:BAAALgAECgQJBAAAAA==.',
Si='Sind:BAABLgAECn8VAAIHAAgJRhaZDwDKAQAHAAgJRhaZDwDKAQABLgAECgkJLgAgAAMVAA==.Sindella:BAAALgAECgUJCAABLgAECgkJLgAgAAMVAA==.Sinna:BAAALgADCgUJCQAAAA==.Sinthorne:BAABLgAECn8uAAMgAAkJAxX4EQDQAQAgAAgJcxf4EQDQAQAfAAMJ8AW+PQBjAAAAAA==.',
Sk='Skedaddle:BAAALgAECgYJCwABLgAECgkJPwAFAEUkAA==.Skithíryx:BAAALgAECgcJDwAAAA==.',
Sl='Slashbndcoot:BAAALgAFFAMJAwAAAA==.Slashgquit:BAACLgAFFH8SAAIeAAQJniDiEwBSAQAeAAQJniDiEwBSAQAuAAQKfzUAAh4ACQmIJOgDAPwCAB4ACQmIJOgDAPwCAAAA.Slumbermist:BAABLgAECn89AAMnAAkJxhExHgC8AQAnAAkJxhExHgC8AQAZAAcJhBKvAQBMAQABLgABCgIJAgABAAAAAA==.',
So='Solaire:BAABLgAECn8hAAMHAAcJWRzfEAC2AQAHAAcJWRzfEAC2AQAhAAUJqRDRTwD6AAABLgAFFAQJCQAnAMQiAA==.Soras:BAAALgADCgkJHwAAAA==.Sourjack:BAAALgAECgUJBgAAAA==.',
St='Steph:BAAALgAECgUJBQAAAA==.',
Su='Sunareas:BAAALgADCgIJAgAAAA==.',
Sy='Syndar:BAAALgAECgEJAQABLgAECgYJFAAFANQfAA==.Synthetic:BAABLgAECn8mAAIKAAkJWxYHCADPAQAKAAkJWxYHCADPAQAAAA==.Syrebriel:BAAALgADCgEJAgABLgAECgcJGAAXAFIKAA==.',
Sz='Szasstaam:BAABLgAECn8jAAMjAAkJ4wc+BwA9AQAjAAkJ4wc+BwA9AQAFAAQJGQL8JgFsAAAAAA==.',
['Sé']='Sénåtor:BAAALgADCgYJCAABLgAECgkJLwAGAHgUAA==.Séékér:BAAALgADCgcJFQAAAA==.',
Ta='Talanith:BAAALgADCggJEAAAAA==.Tarayk:BAAALgADCgYJCAABLgADCgkJIwABAAAAAA==.Taxal:BAAALgADCgYJBwAAAA==.Taxlock:BAABLgAECn8aAAIRAAcJ9wmCmwAGAQARAAcJ9wmCmwAGAQAAAA==.',
Tb='Tbagjones:BAAALgAECgQJBAAAAA==.',
Te='Tecsaran:BAABLgAECn8UAAIFAAYJ1B/ebgD2AQAFAAYJ1B/ebgD2AQAAAA==.Tekis:BAAALgADCgEJAQAAAA==.Telz:BAAALgAECgYJCgAAAA==.Terania:BAAALgADCgIJAgAAAA==.',
Th='Thalira:BAABLgAECn8dAAQmAAgJQAfnGwAgAQAmAAgJQAfnGwAgAQAJAAcJTwImcACLAAAIAAQJrQGENQBpAAAAAA==.',
Ti='Tibbz:BAAALgADCgIJAgAAAA==.Tiger:BAACLgAFFH8+AAQfAAkJECUBAACwAwAfAAkJECUBAACwAwAgAAQJiCLUDAArAQAEAAMJYhp3MwDgAAAuAAQKfyoAAx8ACQnqJgUAABYEAB8ACQnqJgUAABYEAAQAAQm1C4TEAD8AAAAA.Tinkera:BAAALgAECgQJBAAAAA==.Tinnea:BAAALgAECgUJDgAAAA==.Titanosaurus:BAAALgAECgcJEAAAAA==.Tizzly:BAABLgAECn8rAAIFAAkJzQ5uagCnAQAFAAkJzQ5uagCnAQAAAA==.',
To='Torhilda:BAAALgAECgYJBgABLgAECgYJFAAFANQfAA==.Torridwells:BAABLgAECn8bAAIPAAkJdA/TWgCVAQAPAAkJdA/TWgCVAQAAAA==.',
Tr='Trad:BAAALgADCgYJBgAAAA==.Troag:BAABLgAECn8eAAINAAkJcRzzGgBzAgANAAkJcRzzGgBzAgAAAA==.Troagstar:BAABLgAECn8mAAIXAAkJChvmGwACAgAXAAkJChvmGwACAgAAAA==.',
Ts='Tsaesci:BAAALgADCgQJBgAAAA==.Tsynn:BAAALgADCgYJFAAAAA==.',
Ty='Tylerz:BAAALgAECgYJCwAAAA==.Tyraana:BAABLgAECn9BAAMbAAkJRSCRBQDnAgAbAAkJRSCRBQDnAgAcAAgJ3RRoTACgAQAAAA==.Tyrinwar:BAAALgADCgYJDAAAAA==.Tyrmog:BAABLgAECn8dAAILAAkJHAl+lgA7AQALAAkJHAl+lgA7AQAAAA==.Tytus:BAAALgAECgUJBQAAAA==.',
Un='Unique:BAAALgAECgEJAQABLgAFFAUJGQACAJ4lAA==.',
Us='Ushas:BAABLgAECn8yAAMTAAkJChmpGQD+AQATAAkJChmpGQD+AQAWAAQJqQXfWwCQAAAAAA==.Usmcshammy:BAAALgAECgUJBQAAAA==.',
Va='Vali:BAABLgAECn8sAAIdAAkJHB/vAgCyAgAdAAkJHB/vAgCyAgAAAA==.Valindrea:BAAALgAECgcJEAAAAA==.Vasrael:BAABLgAECn82AAMGAAkJshd7OwAWAgAGAAgJ/Bl7OwAWAgAhAAcJYRzdHQAUAgAAAA==.Vav:BAABLgAECn8UAAMPAAYJeBdmoQD/AAAPAAYJeBdmoQD/AAASAAIJswzTYAA5AAAAAA==.',
Ve='Vecnis:BAAALgAECgIJAgAAAA==.Veliette:BAAALgAECgUJBwAAAA==.Verdena:BAAALgADCgcJBwABLgADCgkJIwABAAAAAA==.Vexen:BAABLgAECn8VAAIcAAkJRQ+6AAC5AQAcAAkJRQ+6AAC5AQAAAA==.',
Vi='Victaliste:BAAALgAECgQJBQAAAA==.Vithper:BAAALgAECggJEwAAAA==.',
Vn='Vnia:BAAALgADCgMJAwABLgAECgMJCAABAAAAAA==.',
Vo='Voidmuffinz:BAACLgAFFH8IAAIcAAMJ4gwBawC2AAAcAAMJ4gwBawC2AAAuAAQKfyMAAhwACQkmGFEtABICABwACQkmGFEtABICAAAA.',
Vy='Vynis:BAAALgAECgcJDQABLgAFFAMJEAAhAD8TAA==.Vyrahildard:BAABLgAECn8tAAIGAAkJfRuXJwBlAgAGAAkJfRuXJwBlAgAAAA==.',
Wa='Wakkiq:BAAALgAECgEJAQAAAA==.Waringoutlaw:BAABLgAECn8UAAICAAcJYgGXngA3AAACAAcJYgGXngA3AAAAAA==.Wasteland:BAABLgAECn8rAAIeAAkJphEtGwCDAQAeAAkJphEtGwCDAQAAAA==.',
We='Weaselhunter:BAAALgAFFAEJAQABLgAFFAIJBQARAPAWAA==.Weasellock:BAABLgAFFH8FAAIRAAIJ8BY4kgCeAAARAAIJ8BY4kgCeAAAAAA==.Weaselmage:BAAALgAFFAEJAQABLgAFFAIJBQARAPAWAA==.Welor:BAAALgADCgYJDAAAAA==.',
Wh='Whatthef:BAAALgAECggJCwAAAA==.',
Wi='Wildweasel:BAAALgAFFAIJAwABLgAFFAIJBQARAPAWAA==.Winterhide:BAABLgAECn8xAAILAAkJoxnCIwB2AgALAAkJoxnCIwB2AgAAAA==.',
Wo='Wolfe:BAAALgADCgIJAgAAAA==.',
Xa='Xallie:BAECLgAFFH8GAAIcAAMJaQgacACpAAAcAAMJaQgacACpAAAuAAQKfz8AAhwACQl8GoMgAFECABwACQl8GoMgAFECAAAA.Xanvyr:BAABLgAECn8hAAIGAAkJXxk+PwAJAgAGAAkJXxk+PwAJAgAAAA==.Xaquillis:BAACLgAFFH8QAAMQAAQJVwvzEQADAQAQAAQJKwrzEQADAQALAAMJuQ05tQC8AAAuAAQKfyYAAwsACQkuGyc8AEcCAAsACAmZGyc8AEcCABAABAmwFr0VACsBAAAA.Xarthis:BAAALgAECgEJAQABLgAFFAQJEAAQAFcLAA==.',
Xe='Xentrie:BAAALgADCgUJCgAAAA==.Xeyvara:BAABLgAECn8sAAIaAAkJoCTaAABCAwAaAAkJoCTaAABCAwAAAA==.',
Xg='Xg:BAAALgADCgUJBgABLgAECgYJJgAXALwfAA==.',
Xi='Xindra:BAAALgAECgkJCQAAAA==.',
Ya='Yamiyugi:BAAALgAECgEJAQAAAA==.Yatsui:BAAALgAECgQJBAAAAA==.',
Yo='Youngthug:BAAALgAECgIJAwAAAA==.',
Yu='Yutaa:BAAALgADCgYJBgAAAA==.',
Za='Zaden:BAAALgAECgYJBwAAAA==.Zangi:BAAALgAECgEJAgABLgAECgkJLAAEAL4hAA==.Zarihanna:BAABLgAECn8tAAIFAAgJ+hOUfAB/AQAFAAgJ+hOUfAB/AQAAAA==.Zatannah:BAAALgADCgUJBQAAAA==.',
Ze='Zedryn:BAABLgAECn8nAAIRAAkJew91RwDDAQARAAkJew91RwDDAQAAAA==.Zenshi:BAAALgAECgEJAgAAAA==.Zeperios:BAAALgAECgYJCgAAAA==.Zeril:BAABLgAECn8UAAMUAAgJjReLDACTAQAUAAgJjReLDACTAQARAAEJHgXqVwEoAAAAAA==.Zestdruid:BAAALgAECggJEQAAAA==.Zestull:BAABLgAECn8lAAIOAAgJnCS2BgDOAgAOAAgJnCS2BgDOAgAAAA==.Zetsuboiki:BAAALgADCgYJBgAAAA==.Zetsudeath:BAAALgADCgYJBgAAAA==.',
Zh='Zhoel:BAAALgADCgEJAQAAAA==.',
Zi='Ziak:BAAALgAECgUJBQAAAA==.Zindeshal:BAAALgAECgYJCQAAAA==.',
Zo='Zorc:BAACLgAFFH8VAAIXAAQJhRwsGwBBAQAXAAQJhRwsGwBBAQAuAAQKfycAAhcACQmKIPsJAPQCABcACQmKIPsJAPQCAAAA.',
Zu='Zunji:BAAALgAECgEJBAAAAA==.',
Zy='Zyate:BAABLgAECn8xAAIRAAkJTRJcRwDEAQARAAkJTRJcRwDEAQAAAA==.Zyrryn:BAABLgAECn8XAAIIAAgJwQOXEgDhAAAIAAgJwQOXEgDhAAAAAA==.',
['Ät']='Ätlas:BAAALgADCgYJDAAAAA==.',
['Ër']='Ërëbus:BAAALgADCgQJBAAAAA==.',
['Ðo']='Ðonjon:BAAALgADCgEJAQAAAA==.',
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
