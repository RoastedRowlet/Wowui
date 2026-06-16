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

local lookup = {'Unknown-Unknown','Warrior-Fury','Druid-Balance','Druid-Restoration','Paladin-Retribution','Paladin-Protection','Evoker-Devastation','Evoker-Augmentation','Warlock-Destruction','DeathKnight-Unholy','Warrior-Protection','Shaman-Restoration','Mage-Frost','Monk-Brewmaster','Hunter-BeastMastery','DeathKnight-Frost','Warlock-Demonology','Hunter-Survival','Priest-Holy','Warlock-Affliction','Rogue-Subtlety','Shaman-Elemental','Shaman-Enhancement','Monk-Mistweaver','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Marksmanship','DeathKnight-Blood','Druid-Feral','Druid-Guardian','Paladin-Holy','Priest-Discipline','Priest-Shadow','Mage-Arcane','Rogue-Assassination','Warrior-Arms','Evoker-Preservation','Monk-Windwalker',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aaffoxx:BAAALgAECgEJAQAAAA==.Aagonyy:BAAALgAECgEJAwAAAA==.',
Ae='Aenninicus:BAAALgAECgEJAgAAAA==.Aernoth:BAAALgAECgUJDQAAAA==.',
Ak='Akaidia:BAAALgAECgYJBgABLgAECgYJCwABAAAAAA==.',
Al='Alderan:BAABLgAECn8lAAICAAcJIg7UQQA9AQACAAcJIg7UQQA9AQAAAA==.Aleinas:BAABLgAECn8kAAMDAAcJKxYJMwBJAQADAAcJKxYJMwBJAQAEAAQJQQhzlACHAAAAAA==.Alektophobia:BAAALgAFFAEJAQAAAA==.Alendra:BAAALgAECgEJAQAAAA==.Alluisice:BAAALgAECgYJBgAAAA==.Allysaun:BAAALgAECgUJBgAAAA==.Alpharoach:BAAALgADCgYJBgAAAA==.Alzeinrich:BAABLgAECn8XAAMFAAcJSQcc2gDiAAAFAAcJmgUc2gDiAAAGAAQJbwgANwCAAAAAAA==.',
Am='Amorina:BAABLgAECn8cAAIFAAgJzxVXUwDNAQAFAAgJzxVXUwDNAQAAAA==.',
An='Anda:BAAALgAECgMJAwAAAA==.Andarnn:BAAALgAECgEJAQAAAA==.Andracca:BAABLgAECn8dAAMHAAgJ+QoBDABOAQAHAAgJ+QoBDABOAQAIAAEJQAUXmgAkAAAAAA==.Andromeda:BAABLgAECn8WAAIEAAgJ3AsVTwBQAQAEAAgJ3AsVTwBQAQAAAA==.Aner:BAAALgAECgEJBgAAAA==.Angrygnome:BAACLgAFFH8JAAIJAAMJex7GBwAYAQAJAAMJex7GBwAYAQAuAAQKfx4AAgkACQmqIKoBAMACAAkACQmqIKoBAMACAAAA.Angélique:BAAALgAFFAIJAwABLgAFFAYJGAAKAOUhAA==.Antcension:BAAALgADCgUJBQAAAA==.Antemental:BAAALgAECgYJEAAAAA==.Anthigos:BAAALgAECgMJAwAAAA==.',
Ar='Arax:BAABLgAECn8dAAILAAcJ7yGIDgD/AQALAAcJ7yGIDgD/AQAAAA==.Arcada:BAAALgAECgUJBQABLgAECgUJBQABAAAAAA==.Arcaidious:BAAALgAECgUJCgABLgAECggJIwAMAAUTAA==.Arcamoon:BAAALgAECgIJAgABLgAECgUJBQABAAAAAA==.Arcashi:BAAALgADCgcJCgABLgAECgUJBQABAAAAAA==.Arcxdd:BAAALgAECgQJBAAAAA==.Areuawizard:BAAALgAECgYJBgAAAA==.Arianlion:BAAALgAECgEJAgAAAA==.Armistice:BAAALgAECgEJAgAAAA==.Arowenn:BAAALgADCgMJAwAAAA==.Arrokoth:BAAALgAECgIJAwAAAA==.Artana:BAAALgAECgIJAgAAAA==.',
As='Askook:BAAALgAECgYJBgAAAA==.Astolvik:BAAALgAECgQJBgAAAA==.',
At='Attachedplag:BAAALgAECgYJEQAAAA==.Atulwa:BAABLgAECn8oAAIMAAkJdRYmIwA4AgAMAAkJdRYmIwA4AgAAAA==.',
Au='Aurinox:BAABLgAECn8YAAINAAUJxwyZ4QDUAAANAAUJxwyZ4QDUAAAAAA==.Autodrive:BAAALgAECgYJDgAAAA==.',
Av='Avralea:BAABLgAECn8+AAIOAAgJ8Bu9EwAQAgAOAAgJ8Bu9EwAQAgAAAA==.',
Az='Azenthal:BAAALgAECgEJAQAAAA==.Azurestrider:BAAALgAECgEJAQAAAA==.',
Ba='Bananahammik:BAAALgAECgYJDgAAAA==.Banzen:BAABLgAECn8ZAAIPAAUJ/g8IpwDuAAAPAAUJ/g8IpwDuAAAAAA==.Basz:BAACLgAFFH8JAAIKAAQJLg7bbQAgAQAKAAQJLg7bbQAgAQAuAAQKfzcAAwoACAn4Ha0tAEYCAAoACAn4Ha0tAEYCABAABAnFD64dANsAAAAA.',
Be='Beefburglar:BAAALgAECgYJBgAAAA==.Beginagain:BAAALgADCgcJCQAAAA==.Belfias:BAAALgAECgEJAgABLgAECgkJFgAQAFMaAA==.Belgran:BAABLgAECn8WAAIQAAkJUxrSAwA9AgAQAAkJUxrSAwA9AgAAAA==.Belris:BAAALgAECgMJAwAAAA==.Berunma:BAABLgAECn8YAAIPAAgJ2BAjdgBPAQAPAAgJ2BAjdgBPAQAAAA==.Betabill:BAAALgAECgUJBQAAAA==.',
Bh='Bhain:BAABLgAECn8hAAMRAAcJ5R3lSgDpAQARAAcJ5R3lSgDpAQAJAAEJaA2FdAAwAAABLgAFFAUJEAAFAHweAA==.',
Bi='Bileshots:BAABLgAECn8UAAISAAgJNRd5GwDBAQASAAgJNRd5GwDBAQAAAA==.Biowolf:BAACLgAFFH8aAAINAAUJmQeEbwAIAQANAAUJmQeEbwAIAQAuAAQKfywAAg0ACQneFP9CABACAA0ACQneFP9CABACAAAA.Birdhunter:BAAALgAFFAEJAQAAAA==.Bishopixixix:BAAALgAECgYJCwABLgAECgcJDwABAAAAAA==.Bits:BAABLgAECn8qAAIRAAgJcAfOigAkAQARAAgJcAfOigAkAQAAAA==.',
Bj='Bjoren:BAABLgAECn8uAAITAAkJGyQ+AwBcAwATAAkJGyQ+AwBcAwAAAA==.',
Bl='Blackdread:BAAALgADCgYJBgAAAA==.Blasterjenny:BAAALgADCgkJGAABLgAECgIJAgABAAAAAA==.Bloodcaptain:BAABLgAECn8cAAMJAAkJORe9BgDuAQAJAAkJZBa9BgDuAQAUAAYJshf6CAC3AQAAAA==.',
Bo='Bohma:BAAALgADCgEJAQAAAA==.Boopblast:BAAALgAECgQJCAAAAA==.Bootiebang:BAABLgAECn8WAAIVAAcJrQOsOQDjAAAVAAcJrQOsOQDjAAAAAA==.Bootieknight:BAAALgAECgUJBQAAAA==.Bootycaall:BAAALgADCgkJGwAAAA==.Bootycall:BAAALgADCgkJCQAAAA==.Boroth:BAAALgADCgcJBwAAAA==.',
Br='Breetech:BAAALgAECgIJAgAAAA==.Brett:BAAALgAECgEJAQAAAA==.Breé:BAAALgAECgEJAQAAAA==.Brianx:BAAALgADCgIJAgAAAA==.Brklyn:BAAALgAFFAEJAQAAAA==.Brockshot:BAAALgADCgcJBwAAAA==.Brokki:BAAALgADCgEJAQAAAA==.',
Bu='Buckaroo:BAAALgAECgQJBQAAAA==.Bucknastey:BAAALgAECgEJAQAAAA==.Bucknekkid:BAAALgAECggJEwAAAA==.Buckwhild:BAABLgAECn8dAAITAAgJfSD/CADWAgATAAgJfSD/CADWAgAAAA==.Burrhus:BAAALgAECgQJBAAAAA==.',
Ca='Cagomei:BAAALgADCggJDgAAAA==.Caladbolg:BAABLgAECn89AAMGAAgJkiEUBQCgAgAGAAgJkiEUBQCgAgAFAAEJkAP5VwEnAAAAAA==.Camrillem:BAAALgAFFAEJAQAAAA==.Cannacola:BAABLgAECn8mAAMWAAYJvB8GKwCXAQAXAAYJ1BzoDQDeAQAWAAYJOh4GKwCXAQAAAA==.Carebearr:BAAALgAECgMJAwAAAA==.',
Ce='Cearius:BAAALgAECgYJCgABLgAFFAUJFAARAOUfAA==.Celthis:BAAALgADCgcJBwABLgAECgUJCQABAAAAAA==.Cerdwin:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.Cesàrè:BAABLgAECn8YAAIYAAgJyAcSWwD/AAAYAAgJyAcSWwD/AAAAAA==.',
Ch='Chahra:BAABLgAECn8aAAIZAAgJQA4WEABGAQAZAAgJQA4WEABGAQAAAA==.Chammie:BAAALgAECgYJBgAAAA==.Chamuki:BAACLgAFFH8GAAMaAAMJ4g+zIACKAAAaAAIJZhazIACKAAAbAAEJ2wJeowAyAAAuAAQKfyEABBoACAn4HJcOADkCABoABwnBIJcOADkCABsABQm2Dfq2ALgAABkAAgkXFu8vAEAAAAEuAAUUBQkaAAMAsR8A.Chaosbolt:BAAALgAECgEJAwAAAA==.Cheesecake:BAACLgAFFH8YAAMKAAYJ5SEsJgDGAQAKAAYJ5SEsJgDGAQAQAAIJ3A+4HACSAAAuAAQKfyYAAwoACQl+JcQCAK4DAAoACQl+JcQCAK4DABAAAwn6GgomAJwAAAAA.Cheesecaké:BAAALgAFFAIJAgABLgAFFAYJGAAKAOUhAA==.Cheesuspiece:BAAALgADCgIJAgAAAA==.Chrispbacon:BAAALgAECgMJBAAAAA==.Chuubak:BAAALgAECgkJBQAAAA==.',
Cl='Clangedin:BAABLgAECn8lAAICAAgJzAkQQQBAAQACAAgJzAkQQQBAAQAAAA==.',
Co='Cobalt:BAAALgADCgUJBQABLgAFFAIJBgARABwWAA==.Coondic:BAAALgADCgEJAQAAAA==.Coreydruid:BAAALgAECgMJBwAAAA==.Coreypala:BAAALgAECgIJBAAAAA==.Coreysham:BAAALgAECgQJBQAAAA==.Corily:BAAALgADCgcJHAAAAA==.Corsten:BAABLgAECn8eAAILAAgJuA/3GgBdAQALAAgJuA/3GgBdAQAAAA==.Cosmictonic:BAAALgADCgYJBgAAAA==.',
Cr='Crabpack:BAAALgADCgIJAgAAAA==.Crayoneater:BAAALgAECgQJBAAAAA==.Crippleswagg:BAAALgAECgYJAQAAAA==.Croisades:BAAALgAECgQJCgAAAA==.Crosis:BAAALgADCgcJFwAAAA==.Crowmatic:BAABLgAECn8aAAIKAAkJ+h7fJgBlAgAKAAkJ+h7fJgBlAgAAAA==.Crusadan:BAAALgADCgYJBgAAAA==.Cryo:BAAALgAECgEJAQAAAA==.',
Cu='Cucklizard:BAAALgAECgEJAQAAAA==.Cute:BAABLgAFFH8NAAICAAMJNCOmJgAVAQACAAMJNCOmJgAVAQAAAA==.',
['Cà']='Càhos:BAAALgADCgUJBQAAAA==.',
Da='Dakon:BAABLgAECn83AAMGAAkJThrjCQArAgAGAAkJThrjCQArAgAFAAIJcBi7DAF9AAAAAA==.Dalune:BAABLgAECn8vAAIWAAgJTAiOSAAOAQAWAAgJTAiOSAAOAQAAAA==.Daneaus:BAABLgAECn8sAAIEAAkJviHHBQBZAwAEAAkJviHHBQBZAwAAAA==.Daniellson:BAACLgAFFH8GAAISAAMJ1g2PIADOAAASAAMJ1g2PIADOAAAuAAQKfxgABBwACAkoEesvALUBABwACAkoEesvALUBABIAAQk+EEhgADgAAA8AAQkAAFrcABcAAAEuAAUUBgkPAB0ApRgA.Daredevil:BAAALgAECgYJBwABLgAECggJFwAKALYcAA==.Darkchronos:BAAALgAECgEJAQAAAA==.Darkehawke:BAAALgAECgEJAQAAAA==.Darkscorp:BAAALgADCgkJDgAAAA==.Darkwolf:BAACLgAFFH8GAAIKAAQJFQQ3jgDqAAAKAAQJFQQ3jgDqAAAuAAQKfzcAAwoACQlnFDM2ACMCAAoACQlnFDM2ACMCAB0ACAldBiQxANcAAAAA.Darnuus:BAAALgAECgYJDQABLgAECggJKgAIAPILAA==.Datromandude:BAAALgAECgUJCAAAAA==.Dawnbringer:BAAALgADCgQJBAAAAA==.',
Db='Dblaster:BAAALgAECgUJCwAAAA==.',
De='Deathbydruid:BAABLgAECn8oAAMEAAkJyAM3fgC8AAAEAAkJyAM3fgC8AAADAAYJ1QBTfQBJAAAAAA==.Deathnelf:BAABLgAECn8ZAAQQAAgJAgviFQAoAQAQAAgJAgviFQAoAQAKAAYJYQU47gC/AAAdAAEJMgRUagAUAAAAAA==.Deazraelle:BAABLgAECn8YAAIRAAcJ9BfvTACzAQARAAcJ9BfvTACzAQAAAA==.Decimator:BAAALgADCggJHwAAAA==.Declan:BAAALgADCgUJBQAAAA==.Dedric:BAABLgAECn8nAAQeAAgJ8wqyIgDtAAAeAAgJGwiyIgDtAAADAAgJKgT7TADTAAAfAAEJNRfcaAA+AAAAAA==.Dellin:BAABLgAECn8qAAIDAAkJFBeMFwANAgADAAkJFBeMFwANAgAAAA==.Demeco:BAEALgAECgcJDgABLgAFFAgJGQAgAJwcAA==.Demonch:BAAALgAECgUJCAAAAA==.Demonweasel:BAAALgAECgYJBwABLgAFFAIJAwABAAAAAA==.Depeche:BAABLgAECn8dAAIbAAYJ8BBymADrAAAbAAYJ8BBymADrAAAAAA==.Deralle:BAABLgAECn8qAAIIAAgJ8gunOABIAQAIAAgJ8gunOABIAQAAAA==.',
Di='Dil:BAAALgAECgIJAgAAAA==.Diminuendo:BAAALgAECgcJEAAAAA==.',
Do='Donalda:BAAALgAECgEJAQAAAA==.Dorillion:BAAALgAECgUJCQAAAA==.Dorozh:BAABLgAECn8fAAIJAAgJfRSeCQCoAQAJAAgJfRSeCQCoAQAAAA==.',
Dr='Draconx:BAAALgADCgYJBgAAAA==.Draghr:BAAALgAECgQJBAAAAA==.Dragonzmage:BAAALgAECgMJAwAAAA==.Dragskar:BAAALgADCgUJBQAAAA==.Drala:BAABLgAECn8hAAMhAAkJZhNSFwAXAgAhAAkJZhNSFwAXAgATAAEJ2w77ggAuAAAAAA==.Dreadmage:BAAALgADCgUJBQABLgADCgUJCQABAAAAAA==.Dreadpally:BAAALgADCgEJAQABLgADCgUJCQABAAAAAA==.Dreadsham:BAAALgADCgIJAgABLgADCgUJCQABAAAAAA==.Dreco:BAAALgADCgcJBwAAAA==.Driver:BAAALgAFFAIJBAABLgAFFAUJDwARALYLAA==.Dryconias:BAACLgAFFH8KAAIFAAMJvBZmZQDdAAAFAAMJvBZmZQDdAAAuAAQKfzUAAwUACQkqHPogAIECAAUACQkqHPogAIECAAYAAQmfCINTACcAAAAA.Drèadpriest:BAABLgAECn8VAAQhAAUJwR32JAClAQAhAAUJux32JAClAQATAAUJ0hR5QQDiAAAiAAIJCRMGUQCJAAAAAA==.Drôgô:BAABLgAECn8VAAIPAAYJnhM7TgB+AQAPAAYJnhM7TgB+AQABLgAECggJCAABAAAAAA==.',
Du='Dunkelzhan:BAABLgAECn9NAAINAAkJmhtEIQCWAgANAAkJmhtEIQCWAgAAAA==.Duntack:BAAALgADCgEJBAAAAA==.',
Dy='Dyana:BAABLgAECn8fAAIPAAgJ2BWORADPAQAPAAgJ2BWORADPAQAAAA==.',
Dz='Dz:BAACLgAFFH8LAAMgAAQJJhhEHwAdAQAgAAQJJhhEHwAdAQAFAAQJPwmnUwADAQAuAAQKf0QAAyAACQlBJlQAAOADACAACQlBJlQAAOADAAUABAktDpj1AMAAAAAA.',
['Dø']='Dømimømmÿ:BAAALgAECgUJCAAAAA==.',
Ed='Edgyname:BAABLgAECn8UAAIbAAcJBCBxMgD5AQAbAAcJBCBxMgD5AQAAAA==.Edgyvoid:BAAALgADCgYJDAAAAA==.Edlund:BAABLgAECn8jAAIHAAkJfQ1ICACqAQAHAAkJfQ1ICACqAQAAAA==.',
Ef='Effyinzpjake:BAAALgAECgYJDgAAAA==.',
Ei='Eianistic:BAAALgADCgEJAQAAAA==.',
El='Elbiee:BAAALgAECggJCAABLgAECgkJFAAWACIZAA==.Elfvispresly:BAAALgAECgEJAQABLgAECggJDgABAAAAAA==.Ellenee:BAAALgADCgMJAwAAAA==.Ellinor:BAAALgADCgkJLwAAAA==.Elvy:BAABLgAECn8vAAIDAAkJVxjOGQD6AQADAAkJVxjOGQD6AQAAAA==.',
En='Enngin:BAAALgAFFAMJBAAAAA==.Enragee:BAAALgAECgEJAQABLgAECgcJGQAMAIUiAA==.Enroks:BAAALgAECgUJBQAAAA==.',
Er='Erebus:BAAALgAECgYJDAAAAA==.Erythra:BAAALgAECgQJBAAAAA==.',
Ev='Evildefiant:BAAALgAECgEJAQAAAA==.Evilfoxx:BAAALgADCgQJAwAAAA==.',
Ex='Exsalsior:BAAALgADCgYJBgAAAA==.',
Ey='Eyedoc:BAAALgADCgQJBAAAAA==.',
Fa='Fabulousness:BAABLgAECn8uAAITAAkJCiHFBAAyAwATAAkJCiHFBAAyAwAAAA==.',
Fe='Fearliz:BAAALgADCgEJAQAAAA==.',
Fi='Fifefrost:BAAALgAECgQJBAAAAA==.Fishingsucks:BAAALgAECgcJCgAAAA==.Fiurich:BAAALgAFFAEJAQAAAA==.',
Fl='Flexi:BAAALgADCgEJAQAAAA==.Flitred:BAAALgAECggJDwAAAA==.Flock:BAAALgAECgcJCgAAAA==.',
Fo='Foxx:BAAALgAECgUJDQAAAA==.',
Fr='Framboise:BAABLgAECn8ZAAICAAYJUQcaYAAwAQACAAYJUQcaYAAwAQAAAA==.Frostybolt:BAAALgAECgUJBwAAAA==.',
Fu='Furryriver:BAAALgAECgcJEAAAAA==.Furytotem:BAAALgAECgUJCAABLgABCgIJAgABAAAAAA==.',
['Fø']='Føxx:BAAALgAECgEJAQAAAA==.',
Ga='Galadhras:BAAALgADCgYJFAAAAA==.Galdryn:BAAALgADCgIJAQAAAA==.Galianna:BAABLgAECn8WAAITAAgJOhKkIAC5AQATAAgJOhKkIAC5AQAAAA==.Gamboslice:BAABLgAECn8bAAIQAAgJKhSpCgDOAQAQAAgJKhSpCgDOAQAAAA==.Garkevon:BAAALgAECgQJAwAAAA==.',
Ge='Gemeni:BAAALgAECgEJAQAAAA==.Gevul:BAABLgAECn9eAAMRAAkJVRs7GgCFAgARAAkJQhs7GgCFAgAJAAQJ5RNVIwCSAAAAAA==.',
Gh='Ghostess:BAAALgADCgkJAQAAAA==.Ghrank:BAABLgAECn8VAAQUAAcJvgg8HADXAAARAAcJUQeWngABAQAUAAYJHwg8HADXAAAJAAYJ8QdTIQCgAAAAAA==.',
Gi='Gilliruni:BAAALgADCgUJBQAAAA==.Gitpull:BAAALgAECggJDQAAAA==.',
Gl='Glimley:BAAALgADCgMJAwAAAA==.',
Gn='Gnimsh:BAAALgAECgEJAwAAAA==.Gnorst:BAAALgADCgkJCgAAAA==.',
Go='Goodfoxx:BAAALgADCgQJBAAAAA==.Goreolio:BAAALgADCgkJDwABLgAECgYJEQABAAAAAA==.',
Gr='Grandmatank:BAAALgADCgkJCQAAAA==.Grasshopaa:BAAALgADCgYJCQAAAA==.Grassy:BAAALgADCgkJCQAAAA==.Greengoatlin:BAAALgADCgcJBwAAAA==.Gremlock:BAAALgAECgEJAQAAAA==.Gremz:BAABLgAECn8mAAIZAAkJCQp+EABAAQAZAAkJCQp+EABAAQAAAA==.Grozny:BAAALgAECgQJBAAAAA==.Grày:BAABLgAECn8wAAIKAAkJXx0jIQCCAgAKAAkJXx0jIQCCAgAAAA==.',
Gu='Gumboslice:BAACLgAFFH8QAAIEAAUJ/Q+5JQAmAQAEAAUJ/Q+5JQAmAQAuAAQKfx8AAgQACQnSHUwLAAcDAAQACQnSHUwLAAcDAAAA.Gusgus:BAABLgAECn8fAAINAAgJgAanqAAqAQANAAgJgAanqAAqAQAAAA==.',
['Gä']='Gändälf:BAABLgAECn8XAAIjAAgJvxWlBACiAQAjAAgJvxWlBACiAQAAAA==.',
Ha='Habanero:BAABLgAECn8qAAMMAAkJSA+uOwC8AQAMAAkJSA+uOwC8AQAWAAQJUxjkTAD9AAAAAA==.Hachedev:BAAALgAECgMJCAAAAA==.Hadrîan:BAAALgADCgMJAgAAAA==.Hadtopandadk:BAAALgAECgcJDAAAAA==.Hallia:BAACLgAFFH8GAAIEAAMJ9BFfPwCtAAAEAAMJ9BFfPwCtAAAuAAQKfzcAAgQACQlTGv0SALECAAQACQlTGv0SALECAAAA.Hark:BAAALgADCgkJKwAAAA==.Harrybob:BAAALgADCgcJCgAAAA==.Havvocchi:BAAALgAECgEJAwAAAA==.Hawgwild:BAABLgAECn8iAAIKAAgJWREOYQCkAQAKAAgJWREOYQCkAQAAAA==.',
He='Headdinks:BAAALgADCgcJDAAAAA==.Healcap:BAAALgADCgQJBAAAAA==.Healvisprsly:BAABLgAECn8aAAQEAAgJ0he7KQAEAgAEAAcJwxm7KQAEAgADAAYJ9BiQJQCcAQAfAAMJ3hk2MQDfAAAAAA==.Heisenberg:BAAALgADCgMJAwABLgAECgMJBwABAAAAAA==.Helena:BAABLgAECn9EAAMFAAkJFSQ8BgA+AwAFAAkJEyQ8BgA+AwAGAAkJUB5IBQCbAgAAAA==.Heliarc:BAAALgADCgkJLwAAAA==.Hermès:BAAALgAECgUJBgABLgAFFAYJGAAKAOUhAA==.',
Hi='Highfive:BAAALgAECgUJCwAAAA==.',
Ho='Holybeech:BAAALgAECgQJBAAAAA==.Honestly:BAAALgAFFAIJBAAAAA==.Honkytonkman:BAAALgADCgQJBAAAAA==.Hover:BAAALgAECgYJEQAAAA==.',
Ih='Ihmoen:BAAALgADCgYJBgAAAA==.',
Il='Illuminate:BAAALgADCgQJBAAAAA==.Illustria:BAAALgADCgkJHgAAAA==.Illustriâ:BAAALgADCgkJEQABLgADCgkJHgABAAAAAA==.',
Im='Imprison:BAAALgAECgYJBgABLgAECggJGAANAJUaAA==.',
In='Insidious:BAABLgAECn8fAAIdAAkJFRptDwASAgAdAAkJFRptDwASAgAAAA==.Invoke:BAAALgADCgEJAQAAAA==.',
Ir='Irs:BAAALgAECgUJBwAAAA==.',
Is='Isisvane:BAAALgAECgIJAgAAAA==.',
It='Itchyfeet:BAAALgAECgUJCAABLgAFFAUJGwANAJQiAA==.Itchymage:BAACLgAFFH8bAAINAAUJlCKPOQCHAQANAAUJlCKPOQCHAQAuAAQKfyQAAg0ACQnIIzMdAAEDAA0ACQnIIzMdAAEDAAAA.',
Ja='Jacckiemoon:BAAALgAECgQJBAABLgAECggJGgAEANIXAA==.Jadehunterr:BAAALgAECgMJBAAAAA==.Jaesn:BAAALgADCgYJBgAAAA==.',
Je='Jenae:BAAALgAECgEJAQAAAA==.Jenövha:BAAALgADCgkJFwAAAA==.Jezebelle:BAAALgAECgUJBQAAAA==.',
Ji='Jighlipuff:BAAALgAECgIJAgAAAA==.Jigs:BAABLgAECn9HAAIPAAkJTRpIHwBnAgAPAAkJTRpIHwBnAgAAAA==.Jiräiya:BAAALgADCgYJBgAAAA==.',
Jo='Johastrasz:BAAALgADCggJCAAAAA==.',
Ju='Junsing:BAAALgADCgEJAQABLgAECggJKgAIAPILAA==.',
['Jå']='Jåfar:BAAALgADCgEJAgAAAA==.',
Ka='Kabøchi:BAAALgAECgUJBQAAAA==.Kaladriel:BAAALgADCgEJAQAAAA==.Kaldrick:BAABLgAECn8gAAIWAAkJZBSDGwACAgAWAAkJZBSDGwACAgAAAA==.Kamstareater:BAABLgAECn8mAAIbAAkJ+hIOPgDMAQAbAAkJ+hIOPgDMAQAAAA==.Kanakas:BAABLgAECn8UAAIgAAkJohv7HAAZAgAgAAkJohv7HAAZAgAAAA==.Kanaloa:BAABLgAECn8oAAINAAkJ1gk/dgCJAQANAAkJ1gk/dgCJAQAAAA==.Kayler:BAAALgAECgYJBgABLgAECgYJCwABAAAAAA==.',
Ke='Kegerator:BAAALgAECgQJBQAAAA==.Keirin:BAAALgAECggJEgAAAA==.Keldica:BAAALgAECgIJAgAAAA==.Kelemver:BAAALgADCgMJAwAAAA==.Kelysa:BAAALgAECggJDwAAAA==.Kena:BAAALgADCgUJBQAAAA==.Kenshan:BAAALgAECgMJAwAAAA==.Kevinbox:BAAALgAECgYJEAAAAA==.Kevinslayer:BAAALgAECgUJDAAAAA==.Keynaridan:BAABLgAECn8YAAIbAAgJ1xJGUwCJAQAbAAgJ1xJGUwCJAQAAAA==.Keyss:BAAALgADCgIJAgAAAA==.',
Kg='Kglizard:BAAALgAECgUJCAAAAA==.',
Kh='Khalinor:BAABLgAECn8kAAIgAAkJXhekEQCFAgAgAAkJXhekEQCFAgAAAA==.Khardun:BAAALgAECgEJAQAAAA==.Khotuhn:BAAALgADCgkJHgAAAA==.',
Ki='Kickazdin:BAACLgAFFH8LAAIgAAQJShwcGABcAQAgAAQJShwcGABcAQAuAAQKfyIAAyAACQm7Hv8GABoDACAACQm7Hv8GABoDAAUAAgkFCl4+AWkAAAAA.Killadragon:BAAALgADCgUJBQAAAA==.Kiryie:BAABLgAECn8aAAIPAAgJTw5BXACMAQAPAAgJTw5BXACMAQAAAA==.Kisäme:BAAALgAECggJCwAAAA==.',
Kl='Klad:BAAALgAECgEJAQAAAA==.Kluma:BAAALgAECgEJAQAAAA==.',
Kn='Knok:BAAALgAECggJCAAAAA==.',
Ko='Kobu:BAAALgADCgUJBgAAAA==.Konran:BAAALgADCgEJAQAAAA==.',
Kr='Kraigen:BAABLgAECn8vAAIaAAkJHB5XBwC6AgAaAAkJHB5XBwC6AgAAAA==.Krinack:BAABLgAECn8jAAIVAAkJlBFFFgDpAQAVAAkJlBFFFgDpAQAAAA==.Krixiz:BAAALgAECgYJCgAAAA==.',
Ks='Kshamify:BAABLgAFFH8GAAIMAAMJchDFVACgAAAMAAMJchDFVACgAAAAAA==.',
Ku='Kurindrixx:BAAALgADCgIJAgAAAA==.Kurtakum:BAAALgADCgMJAwAAAA==.Kutiel:BAABLgAECn8YAAIWAAcJUgpUTwD1AAAWAAcJUgpUTwD1AAAAAA==.',
Kw='Kwarify:BAAALgADCgEJAQAAAA==.',
Ky='Kynasmira:BAAALgADCgcJHQAAAA==.Kyrsh:BAAALgADCgcJEAAAAA==.',
La='Ladrona:BAABLgAECn8ZAAIkAAkJ+B0bAgDHAgAkAAkJ+B0bAgDHAgAAAA==.Lailyre:BAAALgAECgYJCwAAAA==.Lassan:BAAALgAECgYJCQAAAA==.Later:BAAALgAECggJDAAAAA==.Latimir:BAAALgAECgIJAgAAAA==.Laur:BAAALgADCgYJBgAAAA==.Lavendeer:BAABLgAECn8lAAIDAAkJFhMvHgDTAQADAAkJFhMvHgDTAQAAAA==.Laydin:BAAALgAECgkJCAABLgAECgkJKAAEAMgDAA==.Laylana:BAAALgADCgIJAgABLgADCgUJCQABAAAAAA==.Lazyeye:BAAALgADCgUJBAABLgAECgcJDgABAAAAAA==.',
Lb='Lb:BAAALgADCgUJBgABLgAECgkJFAAWACIZAA==.',
Le='Legume:BAAALgADCgcJCAABLgAECgUJDQABAAAAAA==.Legzanot:BAACLgAFFH8RAAIWAAQJcgpaMADJAAAWAAQJcgpaMADJAAAuAAQKfygAAhYACQkyFiQdACgCABYACQkyFiQdACgCAAAA.Leonceault:BAAALgAECgEJAQAAAA==.',
Li='Lifebringa:BAABLgAECn8sAAMTAAgJTh8uCwCxAgATAAcJ4yIuCwCxAgAiAAcJxhVUJgCYAQAAAA==.Lightningfox:BAABLgAECn8rAAMFAAgJkBqgOgAWAgAFAAgJkBqgOgAWAgAgAAIJug63cwBmAAAAAA==.Lightsfallen:BAAALgAECggJDgAAAA==.Lileth:BAAALgAECgYJBAAAAA==.Limzzmagus:BAAALgAECgMJBgAAAA==.Lithia:BAABLgAECn8aAAIKAAgJiw+8cACAAQAKAAgJiw+8cACAAQAAAA==.Littlemo:BAAALgAECgcJEAAAAA==.',
Lo='Loggs:BAAALgAFFAEJAQAAAA==.Lohnar:BAAALgAECgcJEAAAAA==.Lornah:BAAALgADCgQJBAAAAA==.',
Lu='Lucidslock:BAAALgADCgIJAgAAAA==.Lucielbaal:BAABLgAECn8sAAIRAAkJ9R6UDgDWAgARAAkJ9R6UDgDWAgAAAA==.Luciferus:BAAALgAECgUJCAABLgAECggJLgASAKcQAA==.Luckystop:BAABLgAECn8ZAAMMAAcJhSLeEwCqAgAMAAcJhSLeEwCqAgAWAAQJNwqgaACpAAAAAA==.Lumenir:BAAALgAECgEJAQAAAA==.Lunareth:BAAALgAECgQJBAAAAA==.Luraris:BAAALgAECgEJAQAAAA==.',
Ly='Lyrska:BAABLgAECn8vAAISAAkJLRGLEwAKAgASAAkJLRGLEwAKAgAAAA==.Lytearrow:BAABLgAECn8nAAIPAAgJRA8kXwCFAQAPAAgJRA8kXwCFAQAAAA==.',
['Lè']='Lèonidas:BAAALgADCgUJBQABLgAECgkJKgAfAAMVAA==.',
['Lé']='Léaf:BAAALgAECgMJAwAAAA==.',
Ma='Mahrylee:BAAALgAECgcJEAAAAA==.Maiya:BAAALgADCgcJEAAAAA==.Majutsu:BAAALgADCgEJAQABLgADCgcJDgABAAAAAA==.Malbrax:BAABLgAECn8ZAAIRAAgJcxL4UgCiAQARAAgJcxL4UgCiAQAAAA==.Maleficents:BAABLgAECn8tAAIDAAcJ4RLTLQBnAQADAAcJ4RLTLQBnAQAAAA==.Malurius:BAABLgAECn8bAAMlAAkJshRqEADoAQAlAAkJsRJqEADoAQACAAYJ4Ar0ZQDDAAAAAA==.Malware:BAAALgAECgYJEQAAAA==.Manana:BAAALgADCgEJAQAAAA==.Manbearpally:BAAALgAECgQJBAAAAA==.Manikfury:BAABLgAECn8iAAMeAAgJwBuJCQAlAgAeAAgJwBuJCQAlAgAEAAYJYx4GLQDxAQAAAA==.Maniksmage:BAAALgAECgYJCwABLgAECggJIgAeAMAbAA==.Mannypack:BAABLgAECn8eAAQDAAgJixzTFAAoAgADAAgJixzTFAAoAgAEAAQJkAyigAC2AAAfAAEJOxNJbQA3AAAAAA==.Maranelli:BAAALgAECgIJAwAAAA==.Maseles:BAAALgAECgUJBgABLgAECgUJCQABAAAAAA==.Maxiticon:BAABLgAECn8XAAQiAAYJTQjVXgCYAAAiAAUJ0QXVXgCYAAATAAUJogWdUwCJAAAhAAEJnQ5reAAwAAAAAA==.',
Mc='Mcdawg:BAAALgADCgYJCgAAAA==.Mcleary:BAAALgAECgUJCAAAAA==.',
Me='Meldrus:BAAALgAECgEJAQAAAA==.Melinashala:BAABLgAECn81AAIRAAkJ1AQjhgAsAQARAAkJ1AQjhgAsAQAAAA==.Mending:BAAALgAECgUJBQAAAA==.Meowinator:BAAALgAECgYJDQAAAA==.Mephizto:BAAALgAECgYJCQAAAA==.Metatrøn:BAAALgAECgYJBwAAAA==.Metide:BAAALgAECgQJBAAAAA==.',
Mi='Miala:BAAALgAECgEJAQAAAA==.Mierna:BAAALgAECgkJEgAAAA==.Miler:BAAALgAECgUJBwAAAA==.Millylittle:BAAALgADCgUJBQAAAA==.Minisor:BAAALgAECgUJBQAAAA==.Misanth:BAAALgAECgYJDgAAAA==.Mistdruid:BAAALgAECgIJAwABLgAECgIJBgABAAAAAA==.',
Mo='Moemo:BAABLgAECn8hAAIEAAkJQh/ZCgANAwAEAAkJQh/ZCgANAwAAAA==.Mogryn:BAAALgAECgkJEwAAAA==.Moistymists:BAAALgAECgYJCQAAAA==.Moll:BAAALgADCgEJAQAAAA==.Mommybree:BAAALgAECgYJEgAAAA==.Monksterz:BAABLgAECn8uAAIOAAkJzyD7BQDaAgAOAAkJzyD7BQDaAgAAAA==.Monoxidê:BAAALgAECgEJAQAAAA==.Moonwarriorx:BAAALgAECggJDAAAAA==.Morsecode:BAABLgAECn8fAAIJAAcJfhiCCAC/AQAJAAcJfhiCCAC/AQABLgABCgIJAgABAAAAAA==.Morthok:BAABLgAECn8qAAIRAAgJCBisOgDvAQARAAgJCBisOgDvAQAAAA==.Mortischa:BAAALgADCggJCAAAAA==.Mosh:BAABLgAECn8bAAIOAAkJDhTPGQDVAQAOAAkJDhTPGQDVAQAAAA==.',
Mu='Muchuchu:BAAALgAECgUJEQABLgAECgIJAgABAAAAAA==.Muldern:BAAALgAECgEJAQAAAA==.Munkee:BAAALgAECgYJEQAAAA==.Murdinbronze:BAAALgADCgUJCAAAAA==.Mustachekick:BAAALgAECgUJBQAAAA==.Musyl:BAAALgADCgEJAQABLgAECgYJEQABAAAAAA==.',
['Mã']='Mãf:BAABLgAECn8jAAMMAAgJBRO3UwBhAQAMAAcJWxC3UwBhAQAWAAEJtxywjQBRAAAAAA==.',
['Mí']='Místwalker:BAAALgAECgIJBgAAAA==.',
Na='Nackthyr:BAACLgAFFH8cAAMHAAUJCiYMAQC0AQAHAAUJCiYMAQC0AQAIAAIJNRvdSgCdAAAuAAQKfz0AAgcACQmxJkIAAHcDAAcACQmxJkIAAHcDAAAA.Nafir:BAAALgADCgYJFwAAAA==.Nakky:BAAALgAECgYJDgAAAA==.Narlin:BAAALgAECgYJCQAAAA==.Nasta:BAABLgAECn8bAAIFAAYJ6Qhj3ADfAAAFAAYJ6Qhj3ADfAAAAAA==.Natureboi:BAAALgADCgQJBAABLgADCgYJDAABAAAAAA==.Nazareths:BAAALgAECgQJCwAAAA==.Nazgor:BAAALgAECggJEAAAAA==.Nazrien:BAAALgADCgMJAwAAAA==.',
Ne='Neckromancy:BAAALgAECgUJBQAAAA==.Necrosius:BAAALgAECgYJDgAAAA==.Neonarc:BAEALgADCgkJIQAAAA==.Neshi:BAAALgAECgMJBQAAAA==.Neuman:BAAALgADCgEJAQAAAA==.',
Ni='Nibblemah:BAAALgAECgcJCwAAAA==.Nightsbane:BAAALgADCgcJEAAAAA==.Nivdk:BAAALgADCgYJBgABLgAECgYJEQABAAAAAA==.Nivora:BAAALgAECgYJEQAAAA==.',
No='Notsure:BAABLgAECn8YAAILAAkJTgTJJgD4AAALAAkJTgTJJgD4AAAAAA==.',
Ny='Nyxstalia:BAAALgAECgUJDAAAAA==.Nyyx:BAABLgAECn8iAAIbAAgJtwXwmgDnAAAbAAgJtwXwmgDnAAAAAA==.',
['Ná']='Nácl:BAAALgAECgcJCAABLgAFFAUJHAAHAAomAA==.',
Oa='Oath:BAAALgAECgUJBQAAAA==.',
Ob='Obscyra:BAAALgAFFAEJAQAAAA==.',
Ol='Olmek:BAACLgAFFH8ZAAICAAcJixiPBwDiAQACAAcJixiPBwDiAQAuAAQKfxwAAgIABwkrJs4PAHoCAAIABwkrJs4PAHoCAAAA.',
Oo='Oochie:BAAALgADCgMJAwAAAA==.Oonagi:BAAALgAECgUJBQAAAA==.',
Op='Opalana:BAAALgADCgIJAwAAAA==.Oprahwndfury:BAAALgAECgYJDQABLgAECggJGgAEANIXAA==.',
Or='Orasaya:BAAALgADCgYJBgAAAA==.Orphee:BAAALgADCgcJBwAAAA==.Orzanis:BAAALgADCgcJDgAAAA==.',
Pa='Paige:BAAALgADCgcJDgAAAA==.Palasades:BAAALgADCgUJBQAAAA==.Pallymarc:BAAALgADCgcJCwAAAA==.Pallytune:BAACLgAFFH8QAAIgAAMJPxO6LADDAAAgAAMJPxO6LADDAAAuAAQKfxwAAiAACQnxDrQkAN4BACAACQnxDrQkAN4BAAAA.Pandalorian:BAAALgAECgYJEAAAAA==.Pandamajack:BAAALgAECggJEgAAAA==.',
Ph='Philandre:BAABLgAECn8jAAIFAAgJlBPSXwCvAQAFAAgJlBPSXwCvAQAAAA==.',
Pi='Picoso:BAABLgAECn8hAAINAAkJZQtlaACoAQANAAkJZQtlaACoAQAAAA==.Piianca:BAAALgAECgUJBgAAAA==.Piianna:BAABLgAECn8ZAAITAAcJoBsbGwDrAQATAAcJoBsbGwDrAQAAAA==.Pirko:BAAALgADCggJCwAAAA==.',
Po='Pocketheal:BAAALgADCgkJEAAAAA==.',
Pt='Pteradactyl:BAAALgAECgYJBgAAAA==.',
Pu='Punch:BAAALgAECgEJAgAAAA==.Purplerain:BAAALgAECgQJBQAAAA==.Putrigord:BAAALgAECgQJCwAAAA==.',
Py='Pylarthius:BAAALgADCgcJBwAAAA==.',
Qi='Qik:BAAALgAECgEJAQAAAA==.Qikkaw:BAABLgAECn8oAAMMAAgJyhBATgB0AQAMAAgJyhBATgB0AQAWAAYJDQhhZgCvAAAAAA==.Qitetsu:BAAALgAECgUJBgAAAA==.',
Qu='Quantos:BAABLgAECn8yAAIfAAkJlBArIQBAAQAfAAkJlBArIQBAAQAAAA==.Ququmatz:BAAALgADCgMJAwAAAA==.',
Ra='Raatha:BAABLgAECn8gAAIFAAkJeRalMgAzAgAFAAkJeRalMgAzAgAAAA==.Raeyla:BAAALgAECgYJDQAAAA==.Raganar:BAABLgAECn83AAIGAAgJkhZPDgDaAQAGAAgJkhZPDgDaAQAAAA==.Ranlerodis:BAAALgADCgMJAwAAAA==.Rayjean:BAAALgADCgkJIgAAAA==.',
Re='Redneckboots:BAAALgADCgEJAQAAAA==.Relmax:BAABLgAECn8fAAILAAgJKwp6IQAgAQALAAgJKwp6IQAgAQAAAA==.Rendeminae:BAAALgADCgcJBwAAAA==.Renri:BAABLgAECn8eAAIVAAcJFBbOHgCcAQAVAAcJFBbOHgCcAQAAAA==.Repose:BAAALgAECgIJAwAAAA==.Revick:BAAALgAECgUJCAAAAA==.Revil:BAAALgADCgIJAgAAAA==.',
Rh='Rhaenýs:BAAALgADCgcJDQAAAA==.Rhonwynn:BAABLgAECn8wAAIMAAgJjh3TFQCYAgAMAAgJjh3TFQCYAgAAAA==.',
Ri='Rikershipdwn:BAABLgAECn8ZAAIPAAgJQRSaTAC3AQAPAAgJQRSaTAC3AQAAAA==.Rikersline:BAAALgADCgkJCQAAAA==.Rimish:BAABLgAECn8YAAIgAAkJ4xS7FQBcAgAgAAkJ4xS7FQBcAgAAAA==.Rimrave:BAABLgAECn8qAAQlAAkJnh3fBgCKAgAlAAkJJRzfBgCKAgACAAYJIxscNQDVAQALAAYJiB2mGQBrAQAAAA==.Ripavicii:BAAALgAECgEJAQAAAA==.Ritobeans:BAAALgADCgkJKwAAAA==.Rivik:BAAALgAECgQJAwAAAA==.',
Ro='Robbstark:BAAALgAECgYJDAAAAA==.Robertkenway:BAABLgAECn8uAAMSAAgJpxAFHAC8AQASAAgJpxAFHAC8AQAPAAEJAADX1AAwAAAAAA==.Roguebot:BAAALgADCgkJEgAAAA==.Rohdaric:BAABLgAECn8ZAAISAAYJUxTNFgBdAQASAAYJUxTNFgBdAQAAAA==.Rokte:BAABLgAECn8aAAIUAAgJ7xBWDACSAQAUAAgJ7xBWDACSAQAAAA==.Rollhots:BAAALgAECgYJBgAAAA==.Roo:BAAALgAECgEJAwAAAA==.Rook:BAABLgAECn8nAAQJAAgJNyNHBAA4AgARAAgJxCEkFACrAgAJAAcJcyBHBAA4AgAUAAEJAADcRwAAAAAAAA==.Rosekenway:BAABLgAECn8nAAMEAAgJ6gsqUwBAAQAEAAgJ6gsqUwBAAQADAAQJzQhDaAB5AAABLgAECggJLgASAKcQAA==.',
Rr='Rratt:BAAALgAECgYJDAAAAA==.',
Ru='Rubimoon:BAAALgAECgUJBQAAAA==.Rumí:BAAALgAECggJCAAAAA==.Running:BAAALgAECgIJAgAAAA==.',
Sa='Saammiee:BAAALgAECgIJAgAAAA==.Sabiha:BAABLgAECn8UAAMPAAYJaA+qZQA2AQAPAAYJaA+qZQA2AQAcAAEJwQPplAAlAAAAAA==.Safewaybag:BAAALgADCgQJBAAAAA==.Saintb:BAAALgADCggJCAAAAA==.Saintotem:BAABLgAECn8lAAIWAAkJYBHkJQC3AQAWAAkJYBHkJQC3AQAAAA==.Samartyr:BAAALgAECgYJCQAAAA==.Samison:BAAALgAECgYJBgAAAA==.Sammiiee:BAAALgADCgQJBAABLgAECgIJAgABAAAAAA==.Sandii:BAAALgADCgkJCgAAAA==.Sangwynaris:BAAALgAECgcJCAAAAA==.Saphiiraa:BAABLgAECn8nAAImAAkJyxHvDQDsAQAmAAkJyxHvDQDsAQAAAA==.Sayahealer:BAAALgADCgcJDgAAAA==.',
Sc='Scorpmage:BAABLgAECn8nAAINAAgJAhm1SAD+AQANAAgJAhm1SAD+AQAAAA==.Scramms:BAAALgADCgcJDQAAAA==.Scrams:BAABLgAECn8VAAIcAAcJpwz/FQAFAQAcAAcJpwz/FQAFAQAAAA==.',
Se='Sedrick:BAABLgAECn88AAMgAAkJRSBGDADIAgAgAAgJMiFGDADIAgAFAAcJyBUdcQCJAQAAAA==.Sekendipity:BAAALgADCgEJAQABLgAECgcJDgABAAAAAA==.Sekhmett:BAAALgADCgMJAwAAAA==.Sekndestroy:BAAALgADCgYJCQABLgAECgcJDgABAAAAAA==.Sektacular:BAAALgADCgQJBAABLgAECgcJDgABAAAAAA==.Sekzen:BAAALgAECgcJDgAAAA==.Semiazas:BAABLgAECn8uAAQUAAkJ+Q1bCwCjAQAUAAkJ+Q1bCwCjAQARAAUJ2QmotwDpAAAJAAEJAAD7egAnAAAAAA==.Semiazes:BAAALgADCgYJBgAAAA==.Senessa:BAAALgADCgIJAgAAAA==.Sensy:BAAALgAECgQJCQAAAA==.Sepulveda:BAAALgAECgUJBQABLgAECgkJIQAEAEIfAA==.Serwonton:BAAALgADCgUJBQAAAA==.Seumas:BAAALgADCgMJAwAAAA==.',
Sh='Shadrock:BAAALgADCgYJBgAAAA==.Shamtune:BAAALgAECgMJAwABLgAFFAMJEAAgAD8TAA==.Shattered:BAABLgAECn8XAAIZAAkJtxlrBQBNAgAZAAkJtxlrBQBNAgAAAA==.Shayrisa:BAABLgAECn81AAMMAAkJTBLsOwC7AQAMAAkJTBLsOwC7AQAWAAcJ4w7wRwAQAQAAAA==.Shazool:BAABLgAECn8aAAMMAAgJRB98EgC2AgAMAAgJRB98EgC2AgAXAAIJkQvsMABoAAABLgAFFAMJBgAEAPQRAA==.Sheep:BAABLgAECn8YAAMNAAgJlRpWSgD5AQANAAgJshlWSgD5AQAjAAIJmBlIEwBMAAAAAA==.Shifterz:BAAALgAECgcJDwAAAA==.Shrieke:BAAALgAECgYJCQAAAA==.Shrubbery:BAABLgAECn8fAAIfAAgJpBF8GwBsAQAfAAgJpBF8GwBsAQAAAA==.Shxdow:BAAALgAECgQJBAAAAA==.',
Si='Sind:BAABLgAECn8UAAIGAAgJRhZRDwDKAQAGAAgJRhZRDwDKAQABLgAECgkJKgAfAAMVAA==.Sindella:BAAALgAECgMJBAABLgAECgkJKgAfAAMVAA==.Sinna:BAAALgADCgUJCQAAAA==.Sinthorne:BAABLgAECn8qAAMfAAkJAxWDEQDQAQAfAAgJcxeDEQDQAQAeAAMJ8AVJPABiAAAAAA==.',
Sk='Skedaddle:BAAALgAECgYJCwABLgAECgkJPAANANgjAA==.Skithíryx:BAAALgAECgcJDwAAAA==.',
Sl='Slashbndcoot:BAAALgAFFAMJAwAAAA==.Slashgquit:BAACLgAFFH8SAAIdAAQJniDcEgBWAQAdAAQJniDcEgBWAQAuAAQKfzQAAh0ACQmIJMkDAP8CAB0ACQmIJMkDAP8CAAAA.Slumbermist:BAABLgAECn82AAMnAAkJxhGsHQC8AQAnAAkJxhGsHQC8AQAYAAcJcRHcUQAfAQABLgABCgIJAgABAAAAAA==.',
So='Solaire:BAABLgAECn8hAAMGAAcJWRyYEAC3AQAGAAcJWRyYEAC3AQAgAAUJqRCiTgD9AAABLgAFFAQJCQAnAMQiAA==.Soras:BAAALgADCgkJHwAAAA==.Sourjack:BAAALgAECgUJBgAAAA==.',
St='Steph:BAAALgAECgUJBQAAAA==.',
Su='Sunareas:BAAALgADCgIJAgAAAA==.',
Sy='Synthetic:BAABLgAECn8kAAIJAAgJtRbKBwDQAQAJAAgJtRbKBwDQAQAAAA==.Syrebriel:BAAALgADCgEJAgABLgAECgcJGAAWAFIKAA==.',
Sz='Szasstaam:BAABLgAECn8jAAMjAAkJ4wcRBwA/AQAjAAkJ4wcRBwA/AQANAAQJGQIZIwFsAAAAAA==.',
['Sé']='Sénåtor:BAAALgADCgYJCAABLgAECgkJLwAFAHgUAA==.Séékér:BAAALgADCgcJFQAAAA==.',
Ta='Talanith:BAAALgADCggJEAAAAA==.Tarayk:BAAALgADCgYJBgABLgADCgkJIgABAAAAAA==.Taxal:BAAALgADCgYJBwAAAA==.Taxlock:BAABLgAECn8aAAIRAAcJ9wkqmQAKAQARAAcJ9wkqmQAKAQAAAA==.',
Tb='Tbagjones:BAAALgAECgQJBAAAAA==.',
Te='Tecsaran:BAABLgAECn8UAAINAAYJ1B/ebgD2AQANAAYJ1B/ebgD2AQAAAA==.Tekis:BAAALgADCgEJAQAAAA==.Telz:BAAALgAECgYJCgAAAA==.Terania:BAAALgADCgIJAgAAAA==.',
Th='Thalira:BAABLgAECn8dAAQmAAgJQAedGwAgAQAmAAgJQAedGwAgAQAIAAcJTwL9bQCMAAAHAAQJrQGENQBpAAAAAA==.',
Ti='Tibbz:BAAALgADCgIJAgAAAA==.Tiger:BAACLgAFFH89AAQeAAkJECUBAACwAwAeAAkJECUBAACwAwAfAAQJiCITDAAtAQAEAAMJYhqoMQDiAAAuAAQKfyoAAx4ACQnqJgUAABYEAB4ACQnqJgUAABYEAAQAAQm1C4TEAD8AAAAA.Tinkera:BAAALgAECgQJBAAAAA==.Tinnea:BAAALgAECgUJDgAAAA==.Titanosaurus:BAAALgAECgcJEAAAAA==.Tizzly:BAABLgAECn8rAAINAAkJzQ7VaACnAQANAAkJzQ7VaACnAQAAAA==.',
To='Torhilda:BAAALgAECgYJBgAAAA==.Torridwells:BAABLgAECn8aAAIPAAgJ3A4CWQCVAQAPAAgJ3A4CWQCVAQAAAA==.',
Tr='Trad:BAAALgADCgYJBgAAAA==.Troag:BAABLgAECn8cAAIMAAgJsxtrGgB0AgAMAAgJsxtrGgB0AgAAAA==.Troagstar:BAABLgAECn8kAAIWAAgJixppGwADAgAWAAgJixppGwADAgAAAA==.',
Ts='Tsaesci:BAAALgADCgQJBgAAAA==.Tsynn:BAAALgADCgYJFAAAAA==.',
Ty='Tylerz:BAAALgAECgYJBgAAAA==.Tyraana:BAABLgAECn9AAAMaAAkJRSBmBQDpAgAaAAkJRSBmBQDpAgAbAAgJ3RSRSwCfAQAAAA==.Tyrinwar:BAAALgADCgYJDAAAAA==.Tyrmog:BAABLgAECn8cAAIKAAgJQAk2kwA+AQAKAAgJQAk2kwA+AQAAAA==.Tytus:BAAALgAECgUJBQAAAA==.',
Un='Unique:BAAALgAECgEJAQABLgAFFAUJGQACAJ4lAA==.',
Us='Ushas:BAABLgAECn8yAAMTAAkJChlGGQD+AQATAAkJChlGGQD+AQAhAAQJqQVpWQCVAAAAAA==.',
Va='Vali:BAABLgAECn8rAAIcAAkJHB/hAgCzAgAcAAkJHB/hAgCzAgAAAA==.Valindrea:BAAALgAECgcJEAAAAA==.Vasrael:BAABLgAECn81AAMFAAkJshdxOgAXAgAFAAgJ/BlxOgAXAgAgAAcJYRx9HQAVAgAAAA==.Vav:BAABLgAECn8UAAMPAAYJeBdkngD/AAAPAAYJeBdkngD/AAASAAIJswyIXwA5AAAAAA==.',
Ve='Vecnis:BAAALgAECgIJAgAAAA==.Veliette:BAAALgAECgUJBwAAAA==.Verdena:BAAALgADCgcJBwABLgADCgkJIgABAAAAAA==.Vexen:BAAALgAECgYJDAAAAA==.',
Vi='Victaliste:BAAALgAECgQJBQAAAA==.Vithper:BAAALgAECggJEwAAAA==.',
Vn='Vnia:BAAALgADCgMJAwABLgAECgMJCAABAAAAAA==.',
Vo='Voidmuffinz:BAACLgAFFH8IAAIbAAMJ4gwpaAC2AAAbAAMJ4gwpaAC2AAAuAAQKfyMAAhsACQkmGKcsABICABsACQkmGKcsABICAAAA.',
Vy='Vynis:BAAALgAECgcJDQABLgAFFAMJEAAgAD8TAA==.Vyrahildard:BAABLgAECn8tAAIFAAkJfRvkJgBmAgAFAAkJfRvkJgBmAgAAAA==.',
Wa='Wakkiq:BAAALgAECgEJAQAAAA==.Waringoutlaw:BAAALgAECgcJDQAAAA==.Wasteland:BAABLgAECn8rAAIdAAkJphGxGgCGAQAdAAkJphGxGgCGAQAAAA==.',
We='Weaselhunter:BAAALgAECgcJCwABLgAFFAIJAwABAAAAAA==.Weasellock:BAAALgAFFAIJAwAAAA==.Weaselmage:BAAALgAFFAEJAQABLgAFFAIJAwABAAAAAA==.Welor:BAAALgADCgYJDAAAAA==.',
Wh='Whatthef:BAAALgAECggJCwAAAA==.',
Wi='Wildweasel:BAAALgAFFAEJAQABLgAFFAIJAwABAAAAAA==.Winterhide:BAABLgAECn8wAAIKAAkJoxkBIwB4AgAKAAkJoxkBIwB4AgAAAA==.',
Xa='Xallie:BAECLgAFFH8GAAIbAAMJaQgtbQCpAAAbAAMJaQgtbQCpAAAuAAQKfz0AAhsACQl8GhYgAFECABsACQl8GhYgAFECAAAA.Xanvyr:BAABLgAECn8hAAIFAAkJXxlOPgAKAgAFAAkJXxlOPgAKAgAAAA==.Xaquillis:BAACLgAFFH8QAAMQAAQJVwsbEQADAQAQAAQJKwobEQADAQAKAAMJuQ1yrwC/AAAuAAQKfyYAAwoACQkuGyc8AEcCAAoACAmZGyc8AEcCABAABAmwFiIVAC8BAAAA.Xarthis:BAAALgAECgEJAQABLgAFFAQJEAAQAFcLAA==.',
Xe='Xentrie:BAAALgADCgUJCgAAAA==.Xeyvara:BAABLgAECn8sAAIZAAkJoCTTAABDAwAZAAkJoCTTAABDAwAAAA==.',
Xg='Xg:BAAALgADCgUJBgABLgAECgYJJgAWALwfAA==.',
Xi='Xindra:BAAALgAECgkJCQAAAA==.',
Ya='Yamiyugi:BAAALgAECgEJAQAAAA==.Yatsui:BAAALgAECgQJBAAAAA==.',
Yo='Youngthug:BAAALgAECgIJAwAAAA==.',
Yu='Yutaa:BAAALgADCgYJBgAAAA==.',
Za='Zaden:BAAALgAECgYJBwAAAA==.Zangi:BAAALgAECgEJAgABLgAECgkJLAAEAL4hAA==.Zarihanna:BAABLgAECn8tAAINAAgJ+hOzegB/AQANAAgJ+hOzegB/AQAAAA==.Zatannah:BAAALgADCgUJBQAAAA==.',
Ze='Zedryn:BAABLgAECn8nAAIRAAkJew+8RQDIAQARAAkJew+8RQDIAQAAAA==.Zenshi:BAAALgAECgEJAgAAAA==.Zeperios:BAAALgAECgYJCgAAAA==.Zeril:BAABLgAECn8UAAMUAAgJjRc8DACUAQAUAAgJjRc8DACUAQARAAEJHgW+UwEoAAAAAA==.Zestdruid:BAAALgAECgcJEAAAAA==.Zestull:BAABLgAECn8lAAIOAAgJnCSOBgDPAgAOAAgJnCSOBgDPAgAAAA==.Zetsuboiki:BAAALgADCgYJBgAAAA==.Zetsudeath:BAAALgADCgYJBgAAAA==.',
Zh='Zhoel:BAAALgADCgEJAQAAAA==.',
Zi='Ziak:BAAALgAECgUJBQAAAA==.Zindeshal:BAAALgAECgYJCQAAAA==.',
Zo='Zorc:BAACLgAFFH8VAAIWAAQJhRzCGQBEAQAWAAQJhRzCGQBEAQAuAAQKfycAAhYACQmKIPsJAPQCABYACQmKIPsJAPQCAAAA.',
Zu='Zunji:BAAALgAECgEJBAAAAA==.',
Zy='Zyate:BAABLgAECn8xAAIRAAkJTRK2RQDIAQARAAkJTRK2RQDIAQAAAA==.Zyrryn:BAABLgAECn8XAAIHAAgJwQNHEgDhAAAHAAgJwQNHEgDhAAAAAA==.',
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
